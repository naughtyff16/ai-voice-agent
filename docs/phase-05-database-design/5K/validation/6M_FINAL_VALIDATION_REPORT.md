# Phase 6M — Final Validation Report (Alembic head `109_5B7`)

**Date:** 2026-09-05 (Phase 6M closure pass, superseding this document's earlier
`108_5B6`-head revision from earlier the same day).
**Status of this document:** canonical, final validation record for Phase 6M as of the
current and final Alembic head, `109_5B7`. It **supersedes** `6M_VALIDATION_REPORT.md` (dated
2026-09-03, scoped only to `105_5B4`/`106_5H3`, predates `107_5B5`–`109_5B7` entirely) as the
document referenced by `docs/phase-06-api-design/6M-Admin-Platform-APIs.md` §40/§49/§61.
`6M_VALIDATION_REPORT.md` is **not deleted** — it remains correct for the narrower scope it
actually covers and is cited below as evidence, not superseded content.

**What changed since the `108_5B6`-head revision of this document:** that revision recorded
that no new migration was required and none was authored, per the DB Gap Ledger conclusion in
`6M-Admin-Platform-APIs.md` §57/§58. Phase 6M's closure pass subsequently authored exactly one
further migration, `109_5B7.sql` (Platform Admin manual-credit/billing-adjustment guarded
wrappers; Plan/PlanVersion/PlanPrice catalog commands; Commercial Pricing Agreement lifecycle
wrappers; Tax category/rule commands; 3 safe Platform Admin identity views; a guarded
forced-session-revocation command; `webhooks.webhook_deliveries` DML narrowing; and
`app_platform_admin` grant narrowing on every table/function those new guarded paths
supersede) — see §5 below for its full validation record. `109_5B7` is confirmed the final
migration of the Phase 6M closure pass; no `110` was created or is planned.

---

## 1. Scope

| Migration | Purpose | Validated by |
|---|---|---|
| `105_5B4.sql` | Purpose-scoped break-glass extension; guarded org suspend/reactivate | §2 below, evidence in `6M_VALIDATION_REPORT.md` |
| `106_5H3.sql` | Quota override; guarded refund saga; `is_platform_admin()` NULL fail-open fix | §2 below, evidence in `6M_VALIDATION_REPORT.md` |
| `107_5B5.sql` | `session_user` trust hardening; `app_api` EXECUTE revocation; sensitive recording/transcript access hardening; `app_billing_reconciler`; refund settlement/failure principal separation; atomic privileged-action auditing | §3 below, evidence in `6M_PRIVILEGE_AND_SECURITY_DEFINER_INVENTORY.md` and dated execution logs |
| `108_5B6.sql` | Closes Finding F-26-1 (child-partition ACL bypass on `voice.transcript_segments`) | §4 below, evidence in `6M_PRIVILEGE_AND_SECURITY_DEFINER_INVENTORY.md` and dated execution logs |
| `109_5B7.sql` | Phase 6M closure: Platform Admin guarded billing/CPA/tax commands, safe identity views, forced-session-revocation, webhook DML narrowing, grant narrowing | §5 below, evidence in `6M_FREEZE_01`–`04` (this directory) |

Migrations 001–104 are frozen and out of scope here; their checksums are re-confirmed
unchanged as part of every validation pass cited below (see §6).

---

## 2. `105_5B4` / `106_5H3` — validated 2026-09-03

Full narrative, method, and evidence: `6M_VALIDATION_REPORT.md` (this directory). Summary of
what it establishes, not repeated in full here:

- Two disposable PostgreSQL 18 Docker legs (`phase6m-pg18-fresh`, `phase6m-pg18-incr`),
  separate from any shared/production database.
- Fresh-chain (`001→106_5H3`) and independent incremental-chain (`104_5B3` + pre-105
  fixtures → `105_5B4` → `106_5H3`) both exit 0, fixtures survive, `break_glass_grants.purposes`
  backfilled correctly.
- A genuine defect was found and fixed **during** this pass, not left open: the
  `organization.is_platform_admin()` NULL-fail-open bug (TEST 7 of the adversarial battery).
  Root-caused, fixed via `106_5H3.sql`'s `COALESCE(..., 'false')` redefinition (without
  touching frozen `001_5B.sql`), and re-validated from a clean rebuild with the full 28-test
  battery plus a true-concurrency double-refund race (TEST 27R) — zero regressions.
- Checksums for `102_5H2.sql`/`103_5J2.sql`/`104_5B3.sql` confirmed unchanged; `105_5B4.sql`/
  `106_5H3.sql` checksummed at their final, post-fix bytes.

Raw evidence: `execution_logs/20260903T0100–0300Z_6M_01` through `_22` (24 files).

---

## 3. `107_5B5` — validated 2026-09-04

Full narrative and evidence: `6M_PRIVILEGE_AND_SECURITY_DEFINER_INVENTORY.md` §26/§27 (this
directory) plus `MIGRATION_MANIFEST.md` Row 107 (line 1799). Summary:

- Fresh (`001→107_5B5`) and independent incremental (`104_5B3` + pre-105 fixtures →
  `105_5B4→106_5H3→107_5B5`) chains both validated, fixtures survive.
- Live `\du`/`role_table_grants`/`proacl` inspection (not code review alone) confirms: only
  `postgres`, `app_migration`, `app_platform_admin` hold `BYPASSRLS`; `app_platform_admin` has
  **zero** direct table grant on `voice.recordings`, `voice.conversations`, `voice.turns`, and
  only column-restricted `SELECT` (excluding `text`) on the `voice.transcript_segments`
  *parent*; `app_api` has **no EXECUTE** on any platform-admin-only `SECURITY DEFINER`
  function; `app_billing_reconciler` has **no direct table privilege at all** on any billing
  table — its only capability is `EXECUTE` on `fn_platform_settle_refund`/`fn_platform_fail_refund`.
- `organization.is_platform_admin()`'s hardened body (`session_user = 'app_platform_admin'`
  AND the caller-scoped GUC, both required) confirmed live via `\sf`.
- Refund saga re-battery (reserve/settle/fail, idempotency, terminal-state rejection,
  true-concurrency double-reserve race) re-run against the `107_5B5` head — all PASS.
- One non-bug finding documented for completeness (F-27-1: legacy 5-arg
  `fn_break_glass_grant` overload defaults `purposes` to `{SUPPORT_GENERAL}` — verified safe,
  cannot satisfy a `SENSITIVE_MEDIA_ACCESS` check).

Raw evidence: `execution_logs/20260904T0000–0130Z_6M_10` through `_25_07` (fresh/incremental
chain re-runs), `20260904T0135–0140Z_6M_26_*`/`6M_27_*` (privilege/function inventory),
`20260904T1046–1245Z_6M_17`–`_23` (extra fixtures, platform-admin/forgery tests, quota
lifecycle, break-glass immutability, Redis/Postgres consistency notes), `20260904T1255–1645Z
_6M_24_*` (refund reserve bugfix + full refund battery incl. concurrent-reservation race).

---

## 4. `108_5B6` — validated 2026-09-04 (F-26-1 fix)

Full narrative and evidence: `6M_PRIVILEGE_AND_SECURITY_DEFINER_INVENTORY.md`'s corrected
Finding F-26-1 entry (§26) plus `MIGRATION_MANIFEST.md` Row 108 (line 1835). Summary:

- **Finding F-26-1** (discovered during the `107_5B5` privilege-inventory pass, corrected
  from an initial understated "low severity, hygiene" classification to **P0, live-confirmed
  exploitable**): `app_platform_admin`'s table-level grants on `voice.transcript_segments`'s
  five child partitions were broader than the parent's column-restricted grant, because
  PostgreSQL does not propagate a parent-level `REVOKE`/`GRANT` to pre-existing child
  partitions. Live-tested directly: as `app_platform_admin`, raw `SELECT text`, `DELETE`, and
  `INSERT` against `voice.transcript_segments_2026_09` all succeeded with no permission
  error — a genuine bypass of the `107_5B5` hardening, not a hypothetical.
- **Fix**: `108_5B6.sql` walks `pg_inherits` for the table's current children and applies the
  identical `REVOKE ALL` + column-restricted `GRANT SELECT` (excluding `text`) already applied
  to the parent, plus a self-verifying assertion block that fails the migration if any
  partition is left over-privileged.
- **Re-validation**: fresh (`001→108_5B6`) and independent incremental
  (`104→105→106→107→108`) chains both exit 0. On both legs, all 5 partitions report `false`
  for `has_table_privilege(... 'SELECT'|'INSERT'|'UPDATE'|'DELETE')` and `false` for
  `has_column_privilege(..., 'text', 'SELECT')`, while metadata columns (e.g.
  `sequence_number`) remain readable — confirming the fix is precisely column-scoped, not an
  overbroad lockout.
- **Regression spot-check**: a 21-table sweep of every partitioned table with any
  `app_platform_admin` grant confirms this "parent hardened, children forgotten" defect
  pattern was isolated to this one table; the only other previously-restricted-parent table
  (`workflow.workflow_executions`, fixed earlier via `076_5K1.sql`/`100_5G1.sql` against the
  same defect class) has clean children, and the remaining 19 partitioned tables were never
  restricted at the parent, so full parent+child access there is expected, not a regression.

Raw evidence: `execution_logs/20260904T2200–2230Z_6M_27_01` through `_07` (7 files: fresh
upgrade, fresh heads, fresh proof-of-fix, incremental upgrade, incremental heads, incremental
proof-of-fix, 21-table partitioned-grant spot-check).

---

## 5. `109_5B7` — validated 2026-09-05 (Phase 6M closure); P1 remediation 2026-09-06

**2026-09-06 update:** an independent freeze-gate review of `109_5B7` (as validated below)
found P0=0, P1=6 (currency/server-authority gaps in the manual-credit and billing-adjustment
wrappers, session-revoke-all durability, plan-deactivation idempotency/non-cascade to a
referencing CPA, and a TaxRule grain/overlap validation gap). All 6 were resolved by amending
`109_5B7.sql` and its Alembic wrapper `109_5B7.py` **in place** — `108_5B6` and earlier remain
untouched, and no `110` migration was created. Exactly one final fresh + incremental
validation cycle was then run against the amended migration (`6M_FREEZE_01`, reconfirmed
header dated 2026-09-06), plus a targeted remediation regression battery re-confirming P1
#1-#4 positive paths and exercising a new 12-assertion P1#5 negative battery for TaxRule
(8 component-validation exceptions + 1 overlap rejection + 3 success paths)
(`6M_FREEZE_02`'s 2026-09-06 sections). All results are green on both the fresh and
incremental databases; current checksums are recorded in §6 below and superseded the
pre-remediation values also kept there for audit-trail purposes.

Full narrative: `docs/phase-06-api-design/6M-Admin-Platform-APIs.md` (closure-pass sections).
Raw evidence, this directory: `6M_FREEZE_01_fresh_incremental_upgrade.txt`,
`6M_FREEZE_02_platform_billing_security.txt`, `6M_FREEZE_03_identity_webhook_security.txt`,
`6M_FREEZE_04_heads_checksums.txt`. Summary:

- **Fresh chain** (`001_5B → 109_5B7`, full replay against a wiped `phase6m-pg18-fresh`
  container) and **independent incremental chain** (`phase6m-pg18-incr` pre-seeded to
  `108_5B6`, then `108_5B6 → 109_5B7` applied as a single step) both exit 0. `alembic heads`
  and `alembic current` report exactly one head, `109_5B7`, on both databases; `alembic
  history` confirms a single linear chain from `<base>` through `109_5B7` with no branching.
  (`6M_FREEZE_01`, `6M_FREEZE_04`)
- **Trust boundary** re-confirmed live: `organization.is_platform_admin()`'s real body
  requires `session_user = 'app_platform_admin'` AND the caller-scoped
  `app.is_platform_admin` GUC; `SET SESSION AUTHORIZATION app_platform_admin` plus
  `set_config('app.is_platform_admin', 'true', true)` correctly satisfies it
  (`trust_check_ok = t`), matching the same hardened design already validated for `107_5B5`.
- **Functional battery**, run identically against both databases inside `BEGIN`/`ROLLBACK`
  (no test data persisted): manual CREDIT, BILLING ADJUSTMENT, PLAN → PLAN_VERSION →
  PLAN_PRICE (price created before publish, per the immutable-once-published business rule)
  → PUBLISH, Commercial Pricing Agreement create → version → activate → expire, TAX category
  + rule — all guarded `fn_platform_*` wrapper functions executed successfully as
  `app_platform_admin` and returned the expected generated ids/booleans. (`6M_FREEZE_02`)
- **Identity/webhook/negative-authorization battery**, same two databases: the 3 new safe
  Platform Admin identity views (`v_platform_safe_users`/`v_platform_safe_sessions`/
  `v_platform_safe_api_keys`) return column-restricted rows; `fn_platform_revoke_all_sessions`
  executes successfully; an explicit **negative test** confirms a non-platform-admin caller
  (`app.is_platform_admin = false`) is rejected by `fn_platform_apply_credit` with "caller is
  not authorized"; `app_platform_admin` can no longer `INSERT` into
  `webhooks.webhook_deliveries` (`SELECT` retained); `app_platform_admin` retains prior
  `SELECT` on `billing.billing_accounts`/`billing.invoices`, confirming both are untouched by
  this migration per ADR-5H-006; and `app_platform_admin` can no longer `UPDATE`
  `identity.users` directly, `INSERT` `billing.credits` directly, or `EXECUTE` the raw
  (pre-109) `billing.fn_billing_apply_credit` — all three now require the new guarded
  `fn_platform_*` path. (`6M_FREEZE_03`)
- **2026-09-06 targeted acceptance test — multi-session forced revocation**: the identity
  battery above only ever exercised `fn_platform_revoke_all_sessions` against an empty
  session set (0 revoked). A genuine 3-ACTIVE-session fixture (1 admin caller + 1 target
  user, 3 sessions with distinct `access_token_jti` values) was run against the same
  validated `phase6m_fresh`/`phase6m_incr` databases, inside `BEGIN`/`ROLLBACK`, with a
  post-rollback residue check confirming zero persisted rows on both. Results, identical on
  both databases: first call returns `revoked_count = 3`; exactly one outbox row is written
  (`event_type = identity.forced_revocation_required`, payload carrying 3 session ids + 3
  jtis + the reason string, with no refresh-token hash or other token material present);
  exactly one `PLATFORM_SESSIONS_REVOKED` audit row is written with no jti array in
  `resource_snapshot` (only `revoked_session_count` and the outbox event's id as a
  correlation reference); all 3 target sessions are left `status = REVOKED` with
  `revoked_at` set. A retry against the same (now fully-revoked) user returns
  `revoked_count = 0` and writes no additional outbox row (no duplicate denylist-publisher
  work). One nuance is called out rather than glossed over: the retry *does* write a second
  `PLATFORM_SESSIONS_REVOKED` audit row (`revoked_session_count = 0`), because the
  function's audit call is unconditional by design, unlike the outbox insert which is
  guarded by `IF v_count > 0` — an audit-completeness property, not a defect, and outside
  the scope of the P1 #1 remediation. The raw psql stdout/stderr backing every assertion
  above (both `phase6m_fresh` and `phase6m_incr`, byte-identical, zero-byte stderr on both)
  is stored in this repository, not merely summarized here — see the
  **"3-SESSION FORCED-REVOCATION ACCEPTANCE — RAW EVIDENCE"** section appended to
  `6M_FREEZE_03_identity_webhook_security.txt` (2026-09-06), immediately following the
  narrative "2026-09-06 TARGETED ACCEPTANCE TEST" section this bullet otherwise summarizes.
- **Static review**: the one flagged risk carried over from static review (unverified
  parameter order on the pre-existing `billing.fn_create_commercial_pricing_agreement` that
  `109_5B7`'s wrapper calls) was resolved by reading `102_5H2.sql:1736-1763` directly — the
  real signature (`p_organization_id, p_base_plan_id, p_contract_reference,
  p_created_by_ref`) matches the wrapper's call exactly. No defect found.
- **Result (2026-09-05 initial authorship pass): zero defects found in `109_5B7.sql` itself.** Every issue encountered while
  building the test battery (three, all self-found and self-fixed) traced to an incorrect
  assumption in the test fixtures/ordering, never a bug in the migration's functions, grants,
  or views: (1) initial fixture INSERTs assumed non-existent columns on
  `organization.organizations`/`identity.users`/`billing.billing_accounts`, corrected against
  live `\d` output; (2) the test initially published a plan version before creating its price,
  correctly triggering the migration's own "already published and immutable" guard — fixed by
  reordering the test, not the migration; (3) the test initially set a CPA version's
  `effective_from`/`effective_to` to the same day, correctly triggering the pre-existing (not
  109-introduced) `chk_cpav_dates` check constraint — fixed by using `CURRENT_DATE - 1` for
  `effective_from`.
- **Result (2026-09-06 P1 remediation pass): all 6 independently-reviewed P1 issues fixed
  in place and re-validated green** on both databases — see the update note at the top of
  this section and `6M_FREEZE_02`'s 2026-09-06 sections for the full assertion-by-assertion
  detail. P0=0, P1=0 remaining as of this pass.

Checksums (current, this head, post-remediation): see §6 below.

---

## 6. Checksums (final, this head)

Authoritative source: `MIGRATION_MANIFEST.md`'s own checksum table (not reproduced in full
here to avoid a second copy that could drift) and `execution_logs/20260904T2200Z_6M_27_01`
(fresh upgrade to `108_5B6`, which re-confirms 001–107 unchanged as a side effect of the
alembic chain replay), plus `6M_FREEZE_04_heads_checksums.txt` (this directory) for `109_5B7`.
Spot-confirmed again as part of this pass (static `sha256sum`):

```
105_5B4.sql  a16262285c3a4f1d290817940a8ed28e6c4ad6348f6ec2cc19f21ce2eb779a57   15,898 bytes
106_5H3.sql  d589017d89d329f123f990faedb823574ce9f109b3600d6104b98447d50f2ac0   21,430 bytes
107_5B5.sql  ae105f45a34e946cb3a27b4d5d50513557b024c6b16f071916358eabfa158c26   45,554 bytes
108_5B6.sql  01cf8fe719a74f5cf384aaaaa311287104eee58a9f5ce2b2648565f4b228afd3    6,847 bytes
108_5B6.py   720ee7f38c325a710d60dcef9a646d7971df16512122e5a8a144b5e058d8ef18    3,970 bytes
109_5B7.sql  a761239d7e63e3d2d982f4dbf7291b81711a24dc051c2577bc44ff46052b0cf3   53,473 bytes  (current, post-2026-09-06 in-place P1 remediation)
109_5B7.py   d60f497b9c6c494e051b86d2f086211c77aef8e6b46bc390321e179e83fb9602    4,949 bytes  (current, post-remediation)
```

Pre-remediation values (2026-09-05, superseded by the amendment above, retained here for
audit-trail continuity only — not the current state of the file):

```
109_5B7.sql  07e80f76a58da9d552c4eddcf49c02372a211c73cc074251da7d310c658fa0b7   45,004 bytes  (superseded)
109_5B7.py   9c543782102c823154051c61cda31f71a688c5b1c09ff455a617743153fc567c    4,921 bytes  (superseded)
```

001–104 remain frozen and byte-identical to the values recorded before Phase 6M began
(`execution_logs/20260903T000000Z_6L_13_final_checksums_and_sizes.txt`, re-confirmed
`20260904T000000Z_6L_17_final_checksums_confirm_unchanged.txt`).

---

## 7. Why no further PostgreSQL migration beyond `109_5B7` was authored

The original DB Gap Ledger (`6M-Admin-Platform-APIs.md` §57 — feature-flag persistence,
credit/adjustment function audit-fusion, billing-account manual override, cross-tenant
webhook replay, admin workflow-execution override) was resolved as **migration required:
NO** for every item except the guarded-command/grant-narrowing closure work that `109_5B7`
implements, either because existing guarded functions/read paths are sufficient, the item is
a deliberate owner decision (not an oversight), or the item is explicitly FUTURE/roadmap-
dependent and out of v1 scope (e.g. FR-FLAG-001, feature-flag persistence, remains P1 and
explicitly out of `109_5B7`'s scope — it is not a freeze blocker). `109_5B7` was authored,
validated (§5 above), and confirmed the final migration of the Phase 6M closure pass; no
`110` was created or is planned. With `109_5B7` validated and zero P0/P1 gaps remaining,
there is no further DDL/DML/grant change to validate against a live database.

---

## 8. Conclusion

Every migration between the pre-Phase-6M baseline and the current, final head, `109_5B7`,
has live PostgreSQL 18 validation evidence on record: fresh-chain replay, independent
incremental replay with pre-existing-data fixtures, adversarial security batteries (including
true-concurrency races), direct live grant/ACL inspection (not code review alone) for
`107_5B5`/`108_5B6`/`109_5B7`, and a full functional test battery covering every guarded
command and view `109_5B7` introduces plus an explicit negative-authorization test. Two real
defects were found and fixed during earlier validation passes (the `is_platform_admin()` NULL
fail-open bug during `106_5H3`'s validation; the child-partition ACL bypass, F-26-1, during
`107_5B5`'s privilege-inventory pass, fixed by `108_5B6`) — both disclosed transparently above
as found-and-fixed, not carried forward as open items. At initial authorship (2026-09-05),
zero defects were found in `109_5B7.sql` across that pass's full validation cycle (§5). A
subsequent **independent freeze-gate review found P0=0, P1=6** against `109_5B7`; all 6 were
resolved by amending `109_5B7.sql`/`109_5B7.py` in place (108 and earlier untouched, no `110`
created), and exactly one final fresh + incremental re-validation cycle was run against the
amended migration, together with a targeted remediation regression battery (§5's 2026-09-06
update). That cycle confirms: `alembic heads`/`current`/`history` still report exactly one
head, `109_5B7`, on both independently-built validation databases, with no branching; and the
full P1 #1-#5 remediation battery is green on both. **As of this pass: P0 = 0, P1 = 0.** No
gap remaining required a further migration, so none was authored and `109_5B7` is confirmed
final.

This report records **P0 = 0, P1 = 0** for the database layer at head `109_5B7` following the
in-place remediation and final re-validation cycle described above. Consistent with this
package's freeze-gate process, this report does not itself declare Phase 6M
APPROVED/FROZEN — that determination belongs to the independent freeze-gate reviewer. See
`docs/phase-06-api-design/6M-Admin-Platform-APIs.md` for the corresponding API-layer
phase-status statement and the one acknowledged, non-blocking P1 roadmap item
(FR-FLAG-001, feature-flag persistence, explicitly out of `109_5B7`'s scope).
