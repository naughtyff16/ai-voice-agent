# Phase 6M — DB Privilege Inventory (§26) and SECURITY DEFINER Inventory (§27)

Status: LIVE-VERIFIED against `phase6m-pg18-fresh`/`phase6m-pg18-incr` at Alembic head `108_5B6`
(PostgreSQL 18.6). All raw command output referenced below is archived verbatim under
`docs/phase-05-database-design/5K/execution_logs/20260904T0135-0140Z_6M_26_*` (original §26/§27
inventory pass, taken at head `107_5B5`) and `docs/phase-05-database-design/5K/execution_logs/
20260904T2200-2230Z_6M_27_*` (migration 108's live re-validation and the child-partition
proof-of-fix battery, taken at head `108_5B6`).

**Revision note (this pass):** the original version of this document, written against head
`107_5B5`, classified the child-partition grant gap below as "Finding F-26-1 (new, low severity,
hygiene)" and described the bypass only as something that "would succeed" hypothetically. That
characterization understated the finding — a subsequent live query, run as `app_platform_admin`
directly against `voice.transcript_segments_2026_09`, confirmed the bypass *did* succeed (raw
`SELECT text`, `DELETE`, and `INSERT` all completed with no permission error), which is a live P0
violation of §3/§4 (PLATFORM_ADMIN/BYPASSRLS alone must not be sufficient to read transcript
content outside purpose-bound break-glass), not a low-severity hygiene item. This document is
corrected below rather than silently re-filed, per the remediation spec's instruction not to
optimize for declaring success. The gap is now fixed by migration `108_5B6.sql` and
live-confirmed closed on both fresh and incremental PostgreSQL 18 legs — see the corrected
Finding F-26-1 entry below.

This document satisfies remediation-spec §26 and §27. It does not restate or reopen any
architectural decision from §1–§11 (already fixed and live-tested in prior segments); it exists
to provide the auditable evidence trail those sections require, plus one incidental
non-bug finding (the `fn_break_glass_grant` legacy overload, see §27.4 below).

---

## §26 — DB Role → Table Privilege Inventory

### Roles present (`\du` against fully-migrated fresh DB)

| Role | Attributes |
|---|---|
| `app_api` | (none) |
| `app_billing_reconciler` | (none) |
| `app_billing_webhook_ingress` | (none) |
| `app_migration` | Bypass RLS |
| `app_platform_admin` | **Bypass RLS** |
| `app_readonly` | (none) |
| `app_voice_reconciler` | (none) |
| `app_worker` | (none) |
| `postgres` | Superuser, Create role, Create DB, Replication, Bypass RLS |

Only `postgres`, `app_migration`, and `app_platform_admin` have `BYPASSRLS`. For `app_platform_admin`
this means **table-level GRANTs, not RLS, are the sole remaining control surface** for every table it
can name in a query — which is exactly what the rest of this table verifies row by row.

### Sensitive-media tables (§3/§4 focus) — `app_platform_admin` vs. others

| Table | `app_api` | `app_platform_admin` | `app_worker` | `app_readonly` | Assessment |
|---|---|---|---|---|---|
| `voice.recordings` (has `storage_ref`, `storage_provider`, `checksum_sha256`) | INSERT,SELECT,UPDATE | **(no grant at all)** | INSERT,SELECT,UPDATE | SELECT | ✅ Correct — Platform Admin has **zero** direct SQL path to this table, including `storage_ref`. Only reachable via `voice.fn_platform_access_recording(...)` (SECURITY DEFINER, break-glass gated). |
| `voice.transcripts` (metadata only: `status`, `total_segments`, timestamps — **no transcript text column**) | INSERT,SELECT,UPDATE | SELECT | INSERT,SELECT,UPDATE | SELECT | ✅ Correct and consistent with the approved `transcript:read` = metadata contract. This table carries no sensitive text, so raw SELECT here does **not** constitute the §3 violation the spec warns about — verified by schema inspection (see `20260904T013700Z_6M_26_03_schema_voice_transcripts.txt`). |
| `voice.transcript_segments` (partitioned; **has the actual `text` column** — the real transcript content) — base/parent table | INSERT,SELECT | **(no grant on the parent)** | INSERT,SELECT | SELECT | ✅ Correct — querying `voice.transcript_segments` (the name the query planner checks permissions against) as `app_platform_admin` is denied. Only reachable via `voice.fn_platform_access_transcript(...)` (SECURITY DEFINER, break-glass gated), which reads the child partitions internally under the function owner's (`postgres`) privileges. |
| `voice.transcript_segments_2026_09..12`, `_default` (child partitions) — **post-108 state** | — | **(no table-level grant; column-restricted `SELECT` only, excluding `text`)** | — | — | Fixed by migration `108_5B6.sql`. Pre-108, direct grants existed on the children (`DELETE,INSERT,SELECT,UPDATE` — inherited from `018_5C.sql`'s blanket schema grant, never revoked when `107_5B5.sql` restricted only the parent). PostgreSQL checks privileges against the table named in the query, not the partition an inherited row happens to live in, so naming a child partition directly bypassed the parent-level restriction entirely — see corrected Finding F-26-1 below. Post-108, `has_table_privilege('app_platform_admin', <partition>, 'SELECT'\|'INSERT'\|'UPDATE'\|'DELETE')` is `false` for all 5 partitions and `has_column_privilege('app_platform_admin', <partition>, 'text', 'SELECT')` is `false` — live-confirmed on both fresh and incremental DBs, `execution_logs/20260904T22*_6M_27_*`. |
| `voice.conversations` | INSERT,SELECT,UPDATE | **(no grant)** | INSERT,SELECT,UPDATE | SELECT | ✅ Correct — revoked. |
| `voice.turns` | INSERT,SELECT | **(no grant)** | INSERT,SELECT | SELECT | ✅ Correct — revoked. |
| `voice.call_sessions` (call metadata, not transcript/recording content) | INSERT,SELECT,UPDATE | DELETE,INSERT,SELECT,UPDATE (+ all listed partitions) | INSERT,SELECT,UPDATE | SELECT | Acceptable — this table holds call lifecycle/session metadata, not transcript text or recording refs, so full DML for support/lifecycle operations is within the approved Platform Admin support scope. `DELETE` here should be confirmed against a retention/purge use case during the §36 write-up rather than left implicit. |

**Finding F-26-1 (P0 — corrected from an earlier, understated "low severity, hygiene" classification;
FIXED, migration `108_5B6.sql`, live-confirmed closed):** `app_platform_admin`'s table-level grants on
the `voice.transcript_segments` child partitions (`_2026_09` … `_default`) were broader than the grant
on the parent — `107_5B5.sql`'s `REVOKE ALL` + column-restricted `GRANT SELECT` named only the parent
relation, and PostgreSQL does not propagate a parent-level `REVOKE`/`GRANT` to already-existing child
partitions. This was **not** merely a theoretical risk requiring an attacker to "know/guess" partition
names — the naming scheme is fully deterministic and documented (`014_5C.sql`: `transcript_segments_
<YYYY>_<MM>`, four months pre-created, plus `_default`), and any session already authenticated as
`app_platform_admin` (the exact identity this finding concerns) can trivially enumerate partitions via
`pg_inherits`. Live-tested directly (not assumed): as `app_platform_admin`, `SELECT text FROM voice.
transcript_segments_2026_09` succeeded (no permission error), as did `DELETE FROM voice.
transcript_segments_2026_09 WHERE false` and an `INSERT`. This is a live, unremediated instance of
exactly the §3/§4 violation the spec's P0 rule is written to prevent: PLATFORM_ADMIN identity/BYPASSRLS
alone was sufficient to reach raw, un-audited, un-purpose-bound transcript content. **Fixed** by
`108_5B6.sql`, which walks `pg_inherits` for the table's current children and applies the identical
`REVOKE ALL` + column-restricted `GRANT SELECT` already applied to the parent, plus a self-verifying
assertion block that fails the migration if any partition is left over-privileged. **Live-confirmed
closed** on both a fresh (`001→108`) and a separate incremental (`104→105→106→107→108`) PostgreSQL 18
database: all 5 partitions now report `false` for `SELECT`/`INSERT`/`UPDATE`/`DELETE` via
`has_table_privilege` and `false` for column-level `SELECT` on `text` via `has_column_privilege`, while
metadata columns (e.g. `sequence_number`) remain readable, confirming the fix is precisely
column-scoped rather than an overbroad lockout — `execution_logs/20260904T2200-2230Z_6M_27_*`. A
21-table spot-check across every partitioned table in the schema with any `app_platform_admin` grant
(`execution_logs/20260904T223000Z_6M_27_07_partitioned_table_spotcheck.txt`) confirms this defect
pattern ("parent hardened, children forgotten") was isolated to this one table — the only other
restricted-parent table, `workflow.workflow_executions` (fixed earlier via `076_5K1.sql`/`100_5G1.sql`
against this same defect class), has clean children; the remaining 19 partitioned tables with
`app_platform_admin` grants were never restricted at the parent in the first place, so full parent+child
access there is expected, not a regression of this bug. See `MIGRATION_MANIFEST.md` Row 108 for the
complete fix/validation narrative.

### Financial tables (§7–§9 focus)

| Table | `app_api` | `app_platform_admin` | `app_worker` | `app_billing_reconciler` |
|---|---|---|---|---|
| `billing.refunds` | SELECT | SELECT | INSERT,SELECT | *(no direct table grant — see below)* |
| `billing.payment_attempts` | SELECT | SELECT | INSERT,SELECT | *(no direct table grant)* |
| `billing.invoices` | SELECT | DELETE,INSERT,SELECT,UPDATE | INSERT,SELECT | *(no direct table grant)* |
| `billing.billing_accounts` | INSERT,SELECT,UPDATE | DELETE,INSERT,SELECT,UPDATE | INSERT,SELECT,UPDATE | *(no direct table grant)* |
| `billing.quota_configs` | SELECT | SELECT | INSERT,SELECT,UPDATE | *(no direct table grant)* |

`app_billing_reconciler` has **no direct table privileges at all** on any billing table (confirmed: it
does not appear in the `role_table_grants` result set for schema `billing`). Its entire capability is the
two EXECUTE grants below (`fn_platform_settle_refund`, `fn_platform_fail_refund`) — both SECURITY DEFINER,
both internally writing through `audit.fn_insert_audit_event`. This is the strongest possible form of the
§7 requirement: the reconciler principal cannot even `SELECT` a refund row directly, let alone forge one —
its only capability is "settle/fail the one refund it's told to, via the guarded function." ✅

`app_api` has only `SELECT` on `billing.refunds` and `billing.payment_attempts` (read/list, no mutation
path at all) and only `SELECT` on `billing.quota_configs` (no path to self-grant a quota override).
`app_platform_admin` also has only `SELECT` on `refunds`/`payment_attempts`/`quota_configs` — all
privileged mutation for these three goes exclusively through the SECURITY DEFINER functions inventoried
in §27, not raw UPDATE. ✅ This directly confirms the §9 atomicity requirement is structurally enforced
(there is no raw-DML path that could commit a state change without going through the audited function).

`app_platform_admin` does hold full DML on `billing.invoices` — this is pre-existing, approved Phase 6K
support-account capability (e.g. void/credit-note support flows), not a refund-settlement bypass; the
refund tables themselves (`refunds`, `payment_attempts`) are read-only for this role, which is the
relevant control for §7.

### Governance tables

| Table | `app_api` | `app_platform_admin` | `app_worker` | `app_readonly` |
|---|---|---|---|---|
| `organization.break_glass_grants` | SELECT | SELECT | SELECT | SELECT |
| `organization.organizations` | INSERT,SELECT,UPDATE | **SELECT only** | INSERT,SELECT,UPDATE | SELECT |
| `audit.audit_events` (+ partitions) | SELECT | SELECT | SELECT | SELECT |
| `audit.domain_event_outbox` | INSERT | DELETE,SELECT,UPDATE | INSERT,SELECT | SELECT |

Every role — including `app_platform_admin` — has **read-only** access to `break_glass_grants` and
`audit_events` at the table-grant level; all mutation of both goes exclusively through
`organization.fn_break_glass_grant/_release` and `audit.fn_insert_audit_event` respectively. No role
(not even `app_platform_admin`) can raw-INSERT/UPDATE/DELETE an audit event — confirmed both by this
grant inventory and by the absence of `INSERT`/`UPDATE`/`DELETE` in the `audit_events` row above. This
directly closes §28 (audit security) at the privilege-grant level, corroborating the earlier
code-review-only finding with a live query.

`app_platform_admin` is notably **more restricted than `app_api`** on `organization.organizations`
(`SELECT` only, vs. `app_api`'s `INSERT,SELECT,UPDATE`) — all organization lifecycle mutation
(suspend/reactivate) is forced through `fn_platform_suspend_organization`/`fn_platform_reactivate_organization`,
never raw UPDATE. ✅ Matches the approved §31 lifecycle model.

---

## §27 — SECURITY DEFINER Function Inventory

All functions below are owned by `postgres`, `SECURITY DEFINER` (`prosecdef = t`), with an explicit
non-empty `search_path` (no function relies on the caller's search_path — confirmed via
`20260904T013800Z_6M_27_01_...txt`), except `organization.is_platform_admin()` which is plain SQL,
`SECURITY INVOKER` (default), `STABLE`, with no `search_path` override needed since it references no
unqualified objects.

| Function | prosecdef | search_path | PUBLIC EXECUTE? | `app_api` EXECUTE? | `app_platform_admin` EXECUTE? | `app_billing_reconciler` EXECUTE? | Binding enforced inside |
|---|---|---|---|---|---|---|---|
| `organization.is_platform_admin()` | f (invoker) | n/a (no unqualified refs) | **Yes (default)** | Yes (harmless — see below) | Yes | Yes | `session_user = 'app_platform_admin'` AND caller-scoped GUC `app.is_platform_admin='true'` — **both required**. `session_user` cannot be forged by any SQL the connecting role can run, so PUBLIC-executability of this predicate is safe; it only ever evaluates true on a genuine `app_platform_admin` connection. |
| `organization.fn_break_glass_check(...)` | t | `organization, pg_catalog` | No | No | **Yes (only)** | No | Calls `is_platform_admin()`; grant exists + `status='ACTIVE'` + not expired + admin/org/session match (all `IS DISTINCT FROM`, so NULL-safe) + required purpose ∈ `purposes[]`. All 7 conditions must hold. |
| `organization.fn_break_glass_grant(5-arg, no purposes)` | t | `organization, pg_catalog` | No | No | **Yes (only)** | No | Legacy signature; omits `purposes` from the INSERT so it takes the column DEFAULT `{SUPPORT_GENERAL}` (confirmed live, see Finding F-27-1). TTL bounded to [60s, 86400s]. |
| `organization.fn_break_glass_grant(6-arg, +purposes)` | t | `organization, pg_catalog` | No | No | **Yes (only)** | No | Same as above but accepts explicit `p_purposes text[]`, subject to the `chk_bgg_purposes_*` CHECK constraints (allow-listed values, no wildcard, 1–5 entries). This is the only path that can create a `SENSITIVE_MEDIA_ACCESS` grant. |
| `organization.fn_break_glass_release(...)` | t | `organization, pg_catalog` | No | No | **Yes (only)** | No | (Body reviewed in prior segment — releases by id, sets `status='RELEASED'`, audited.) |
| `organization.fn_platform_suspend_organization(...)` | t | `organization, pg_catalog` | No | No | **Yes (only)** | No | (Reviewed prior segment) org-existence + status-guard + atomic audit. |
| `organization.fn_platform_reactivate_organization(...)` | t | `organization, pg_catalog` | No | No | **Yes (only)** | No | Same pattern; terminal-state guard confirmed in §31 tests. |
| `billing.fn_platform_set_quota_override(...)` | t | `billing, organization, pg_catalog` | No | No | **Yes (only)** | No | Server-authoritative org id, metric allow-list, positive-value guard, atomic audit (§32 tests). |
| `billing.fn_platform_reserve_refund(...)` | t | `billing, pg_catalog` | No | No | **Yes (only)** | No | Reserves (status `PENDING`) — the human/admin-reachable half of the §7/§8 saga. Does **not** touch `provider_refund_id`/settlement. |
| `billing.fn_platform_settle_refund(...)` | t | `billing, pg_catalog` | No | No | **No** | **Yes (only)** | Only the reconciler principal can mark SUCCEEDED — confirmed live via `proacl`, not just code review. Human Platform Admin route has **zero** EXECUTE grant on this function. |
| `billing.fn_platform_fail_refund(...)` | t | `billing, pg_catalog` | No | No | **No** | **Yes (only)** | Symmetric to settle; same grant pattern. |
| `billing.fn_validate_refund_amount()` | f (invoker) | (none) | trigger fn | n/a | n/a | n/a | Trigger on `billing.refunds`; sums PENDING+SUCCEEDED for the same payment_attempt, rejects overshoot — this is the DB-level backstop against over-refund regardless of which principal writes the row. |
| `voice.fn_platform_access_recording(...)` | t | `voice, organization, pg_catalog` | No | No | **Yes (only)** | No | `session_user='app_platform_admin'` re-checked inside the function itself (defense in depth beyond the grant) + `fn_break_glass_check(..., 'SENSITIVE_MEDIA_ACCESS')` + resource-ownership match (`organization_id`) + atomic `RECORDING_ACCESS_GRANTED` audit + returns only `id, call_id, conversation_id, storage_ref, storage_provider, content_type` (never signs a URL, never returns credentials — matches §5). |
| `voice.fn_platform_access_transcript(...)` | t | `voice, organization, pg_catalog` | No | No | **Yes (only)** | No | Same stacked model; reads `voice.transcript_segments` (the real text) under the function owner's privilege, returns segment rows, atomic `TRANSCRIPT_ACCESS_GRANTED` audit. **This closes §6** — the transcript half of the frozen 6D/6L break-glass handoff is implemented, live, and symmetric with recording access; it was not merely designed but is present and callable in the current `108_5B6` head (the function itself is unchanged since `107_5B5.sql`; only the head revision advanced, to close F-26-1's child-partition bypass — see below). |

**Finding F-27-1 (non-bug, documented for completeness):** The legacy 5-argument
`fn_break_glass_grant` overload silently defaults `purposes` to `{SUPPORT_GENERAL}` only. Verified this
is safe, not a bypass: `chk_bgg_purposes_allowed`/`_no_wildcard`/`_nonempty` all still apply to the
default value, and `fn_break_glass_check` requires the *specific* required purpose (e.g.
`SENSITIVE_MEDIA_ACCESS`) to be present in `purposes[]` — a grant issued through the legacy overload can
never satisfy a sensitive-media check. No fix required; documented here so a future reader does not
mistake the two-overload surface for an oversight.

---

## Summary against the remediation spec's final rule

This live evidence confirms, at the DB-grant level (not merely by code inspection):
- Ordinary `app_api` has no EXECUTE on any Platform-Admin-only function, and no raw-DML path to
  bypass `organization.organizations` lifecycle, `billing.refunds`/`payment_attempts` settlement, or
  `organization.break_glass_grants` mutation.
- `app_platform_admin` (BYPASSRLS) has no raw SELECT on `voice.recordings`, `voice.conversations`,
  `voice.turns`, or `voice.transcript_segments` — parent **and, as of migration `108_5B6.sql`, every
  child partition** — sensitive content requires the guarded functions. (F-26-1, the child-partition
  bypass, is now fixed and live-confirmed closed on both fresh and incremental PostgreSQL 18 legs; see
  the corrected finding above.)
- `app_billing_reconciler` is the sole settlement path — the only trusted,
  provider-authoritative reconciler principal.
- Every high-risk function's only mutation path writes through `audit.fn_insert_audit_event` in the same
  PL/pgSQL function body as the state change (same implicit transaction) — no raw audit DML exists for
  any role.

Open items carried to §38: none from this inventory pass remain open. F-26-1 was found (P0,
live-confirmed exploitable via directly-named child partitions), fixed by migration `108_5B6.sql`, and
is now live-re-validated closed on both fresh and incremental PostgreSQL 18 legs (see the corrected
Finding F-26-1 above and `MIGRATION_MANIFEST.md` Row 108) — it is disclosed transparently in §38 as a
found-and-fixed finding, not carried forward as unresolved. This document itself, including the F-26-1
correction, is evidence to be cited by the final `6M_FINAL_VALIDATION_REPORT.md` and the §38
remediation report.
