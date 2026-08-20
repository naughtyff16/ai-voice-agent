# Phase 5K — Migration Reconciliation Report

**Date:** 2026-08-19
**Scope:** reconciliation of `MIGRATION_MANIFEST.md` against the actual 75
`migrations/*.sql` files, plus write-up and classification of every genuine defect or
architectural conflict surfaced during Phase 5K validation. Per the governing rule
("§2 Preserve approved architecture; genuine conflicts must be identified, classified,
and documented — never silently redesigned"), nothing in this file was fixed by
altering Phase 5A-5J design or any frozen `.sql` migration; every item below is
reported, root-caused, and classified BLOCKING / NON-BLOCKING / DEFERRED TO PHASE 6+.

This file is one of the four mandated §7 validation reports, split out of the
original interim `validation/01_final_validation_report.md` (now removed).

---

## 1. Migration manifest reconciliation

`MIGRATION_MANIFEST.md` was checked against the actual current contents of all 75 `migrations/*.sql` files.

**Found wrong, fixed:**

1. All 75 rows had stale Size/SHA-256 values that did not match current file contents, despite the manifest's own header claiming otherwise. Regenerated from actual file bytes (SHA-256, cross-checked against `sha256sum` on a 5-file sample: 001, 002, 020, 043, 075 — 0 mismatches after regeneration).
2. Row 043's `Txn Mode` was listed as `NON-TRANSACTIONAL (CONCURRENTLY)`; the actual `043_5F.sql` (and its own header comment) is transactional — a plain `CREATE INDEX` against the table's empty `DEFAULT` partition, with `CONCURRENTLY` deferred to the app-layer `create_kb_partition()` path. Corrected to `transactional`, matching every other row and matching what actually executed in the fresh-DB gate (`ALEMBIC_VALIDATION_REPORT.md` §2 — no `autocommit_block()` was invoked anywhere during the 75-revision run).

**Baseline claim in the original task framing** ("~75 mapped, 66 canonical, 8 conflicts resolved, 5 unconfirmed, 2 blocked") **does not correspond to any field the real manifest has ever had.** `MIGRATION_MANIFEST.md`'s actual schema is `# | Phase | Filename | Down Revision | Txn Mode | Size | SHA-256` — a checksum/ordering manifest, not a per-migration status tracker with canonical/conflict/unconfirmed/blocked categories. This is documented explicitly in the manifest's own "Reconciliation" section rather than silently forced to match the assumed baseline.

**Result: PASS** (after fixing the two defects above). 75/75 rows present, in order, root `001_5B` → head `075_5J`, no gaps, no duplicates, checksums now correct.

**Classification: NON-BLOCKING** (documentation-accuracy defects, already fixed; no schema or migration-content change).

---

## 2. Finding: `SECURITY DEFINER` functions with incomplete `search_path` (missing `public`)

### Root cause

A repo-wide grep across migrations `060, 061, 062, 063, 064, 065, 068, 069` found 24
`SECURITY DEFINER` function definitions (schemas `integrations`, `webhooks`, `plugins`,
`analytics`) whose `SET search_path` clause omits `public`. This is only a defect for a
function whose logic — directly or via a table's `DEFAULT gen_uuid_v7()` on an
`INSERT` — needs anything defined in `public`. `gen_uuid_v7()` itself lives in `public`
and internally calls pgcrypto's `gen_random_bytes()`, also in `public`. With `public`
outside a function's restricted search path, any `INSERT` into a table whose `id`
column defaults to `gen_uuid_v7()` fails with
`ERROR: function gen_random_bytes(integer) does not exist`.

### Live evidence (not inferred)

Live, reproducible failures, each independently connection-tested against the fresh
post-upgrade database:

| Function | Migration | Evidence |
|---|---|---|
| `analytics.fn_claim_projection_slot` | `068_5J.sql` | `execution_logs/20260819T072859Z_32_concurrency_r2_conn_A.txt` / `_conn_B.txt` (both connections failed identically) |
| `plugins.fn_create_plugin_installation` | `065_5I.sql` | `execution_logs/20260819T072859Z_39_defect_confirm_fn_create_plugin_installation.txt` |
| `integrations.fn_create_integration_connection` | `061_5I.sql` | `execution_logs/20260819T072859Z_40_defect_confirm_fn_create_integration_connection.txt` |

All three fail with the identical error:
`ERROR: function gen_random_bytes(integer) does not exist`.

### Full classification of all 24 flagged functions

A mechanical audit of every flagged function's body (does it contain `INSERT INTO`,
i.e. could it ever hit a `gen_uuid_v7()` column default) sorted them into three groups:

1. **Confirmed broken, live-tested (3):** `analytics.fn_claim_projection_slot`,
   `plugins.fn_create_plugin_installation`, `integrations.fn_create_integration_connection`.
2. **Broken by construction, not separately live-tested (2):** `analytics.fn_apply_projection_call_metrics`
   (`068_5J.sql`) and `analytics.fn_apply_projection_call_latency` (`069_5J.sql`) — each
   calls a group-1 function as its first action, so each fails identically without
   needing a separate live connection to prove it.
3. **Confirmed NOT affected (19):** the remaining flagged functions, mechanically
   verified to contain no `INSERT INTO` at all — all are pure trigger functions that
   only read/write `NEW`/`OLD` (e.g. `fn_id_slug_immutable`, `fn_ic_terminal_guard`,
   `fn_redeem_oauth_attempt`, `fn_rotate_integration_credential`,
   `fn_integrations_anonymize_org`, `fn_update_inbound_event_status`,
   `fn_wd_identity_immutable`, `fn_claim_delivery`, `fn_delivery_succeeded`,
   `fn_delivery_failed`, `fn_plug_slug_immutable`, `fn_pv_manifest_immutable`,
   `fn_pi_version_immutable`, `fn_pi_terminal_guard`, `fn_activate_plugin`,
   `fn_uninstall_plugin`, `fn_upgrade_plugin`, `fn_mark_event_projected`,
   `fn_mark_event_dead_letter`). They never touch `public`, so the missing entry in
   their `search_path` is harmless.

### Impact

The 5 broken/derived-broken functions (group 1 + group 2) are core write paths for:
plugin installation (`plugins.fn_create_plugin_installation`), integration connection
setup (`integrations.fn_create_integration_connection`), and the analytics projection
pipeline (`analytics.fn_claim_projection_slot`,
`fn_apply_projection_call_metrics`, `fn_apply_projection_call_latency`). As shipped,
none of these 5 can successfully execute an `INSERT` against a fresh database — every
call fails immediately with the `gen_random_bytes` error.

### Classification: **BLOCKING** — ~~unresolved~~ **RESOLVED by Phase 5K.1 patch (see §4 below)**

This is a genuine implementation defect in frozen `.sql` files (`061_5I.sql`,
`065_5I.sql`, `068_5J.sql`, `069_5J.sql`), not a documentation or measurement issue,
and not something that can be worked around at the application layer (the functions
cannot successfully perform their one job — creating rows). Per the governing rule
against silently redesigning frozen migrations, **no fix was applied to the frozen
files above** — the defect was reported here, live-evidenced, and root-caused for a
corrective forward patch to correct by adding `public` to each affected function's
`search_path` (a one-line change per function, no schema/business-logic change
required). It blocked calling these 5 specific write paths production-ready; it did
**not** block the rest of the 199-table schema, which functions correctly, nor did it
block completing Phase 5K's own validation (the defect itself was fully validated and
documented, which is what Phase 5K requires).

> **Status update (2026-08-19, Phase 5K.1):** This finding is now **RESOLVED**. A new
> forward-only migration `076_5K1.sql` / `076_5K1.py` (`down_revision = 075_5J`) adds
> `public` to the `SET search_path` clause of exactly the 5 functions confirmed or
> derived broken above — `analytics.fn_claim_projection_slot`,
> `analytics.fn_apply_projection_call_metrics`, `analytics.fn_apply_projection_call_latency`,
> `plugins.fn_create_plugin_installation`, `integrations.fn_create_integration_connection`
> — and none of the other 19 unaffected flagged functions. All 5 were live re-executed
> post-patch and now succeed. See §4 below and `FINAL_5K_VALIDATION_REPORT.md` for full
> evidence.

---

## 3. Finding: `app_platform_admin` INSERT grant conflict — migration 041 vs 046 (`workflow.workflow_executions`)

### Root cause

- `041_5G.sql` (line 53) deliberately does:
  ```sql
  REVOKE INSERT ON workflow.workflow_executions FROM app_api, app_worker, app_platform_admin;
  GRANT SELECT, UPDATE ON workflow.workflow_executions TO app_api, app_worker;
  GRANT SELECT, UPDATE, DELETE ON workflow.workflow_executions TO app_platform_admin;
  ```
  This is intentional design: execution rows must only be created via the
  `SECURITY DEFINER` function `workflow.fn_start_workflow_execution`, which enforces
  the no-double-active-session business rule (see §18 row 9 test, PASS). Direct
  `INSERT` from any application role — including `app_platform_admin` — is meant to be
  denied, per `5K-Database-Migration-and-Implementation.md`'s own §18 security-test
  table (row 8: "`app_platform_admin` direct `INSERT INTO workflow.workflow_executions`"
  → expected "Denied (REVOKE INSERT)").
- `046_5G.sql` (line 12), five files later in the same forward chain, does a blanket:
  ```sql
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO app_platform_admin;
  ```
  This silently re-grants `INSERT` on `workflow.workflow_executions` (and every other
  current table in the `workflow` schema) to `app_platform_admin`, undoing 041's
  deliberate revoke. GRANT/REVOKE is plain role-privilege state, not additive or
  versioned — the final, actually-applied state after all 75 migrations run is
  whatever the last statement touching that grant left it as: `app_platform_admin`
  **does** hold `INSERT`.

### Live evidence (not inferred)

- `execution_logs/20260819T072859Z_27_security_row6_row7_row8.txt` — §18 rows 6-8
  tested together: `app_api` and `app_worker` direct `INSERT` correctly `DENIED`
  (`permission denied for table workflow_executions`); `app_platform_admin`'s direct
  `INSERT` **succeeded**, returning a real row id, contrary to the spec's expectation.
- `execution_logs/20260819T081500Z_41_grant_conflict_041_vs_046_platform_admin_insert.txt`
  — root-cause deep dive: a live `information_schema.role_table_grants` query confirms
  `app_platform_admin` currently holds `INSERT` on `workflow.workflow_executions`; an
  independent re-run of the direct `INSERT` succeeded again, confirming the first
  result was not a fluke; confirmed no `BEFORE INSERT` trigger or other constraint
  stands in the way (the table's only trigger-based guards,
  `trg_we_immutable`/`trg_we_updated_at`, are both `BEFORE UPDATE` only); confirmed the
  table's only RLS policy enforces tenant scoping, not provenance. Both fixture rows
  created by these two tests were deleted afterward; no fixture data was left behind
  in the disposable database.

### Impact

`app_platform_admin` can create a `workflow.workflow_executions` row by direct
`INSERT`, completely bypassing `fn_start_workflow_execution`'s
no-double-active-session guard — there is no DB-level uniqueness constraint enforcing
that invariant (`idx_we_active_session` is a plain non-unique index, by design, per
`EXECUTION_REPORT.md` defect #8, which itself assumed the INSERT path was already
locked down by GRANT alone — an assumption 046 quietly invalidated).

### Classification: **BLOCKING** — ~~unresolved~~ **RESOLVED by Phase 5K.1 patch (see §4 below)**

This is a genuine conflict between two already-approved Phase 5G migrations (041's
intentional revoke vs. 046's blanket schema-wide re-grant), not a new design decision
proposed by this validation. Per the governing rule against silently redesigning
frozen migrations, **no fix was applied to `041_5G.sql` or `046_5G.sql`** — those files
are untouched. It was reported, live-evidenced, and classified for a corrective
forward patch to resolve — the fix implied by 041's own stated intent, a narrow
`REVOKE INSERT ON workflow.workflow_executions FROM app_platform_admin;`, was applied
as part of the new forward migration rather than as an edit to either historical file.
It blocked treating §18 row 8 as a verified PASS; it did not block the rest of the RBAC
model (rows 1-7, 9-13 of §18 all passed as expected — see `FINAL_5K_VALIDATION_REPORT.md`).

> **Status update (2026-08-19, Phase 5K.1):** This finding is now **RESOLVED**. The new
> forward-only migration `076_5K1.sql` / `076_5K1.py` (`down_revision = 075_5J`) revokes
> `INSERT` on `workflow.workflow_executions` from `app_platform_admin` — including on
> every existing partition child, via a `pg_inherits`-based dynamic loop, since
> `GRANT/REVOKE ... ON ALL TABLES IN SCHEMA` in migration 046 had touched each partition
> individually. Live re-testing confirms `app_platform_admin`'s direct `INSERT` is now
> denied, while the legitimate approved path (`workflow.fn_start_workflow_execution`,
> `SECURITY DEFINER`) continues to succeed and continues to enforce the
> no-double-active-session invariant. See §4 below and `FINAL_5K_VALIDATION_REPORT.md`
> for full evidence.

---

## Summary of findings in this report

| # | Finding | Files | Classification |
|---|---|---|---|
| 1 | Manifest checksum/Txn-Mode drift | `MIGRATION_MANIFEST.md` | NON-BLOCKING (fixed) |
| 2 | `SECURITY DEFINER search_path` missing `public` — 5 of 24 functions confirmed/derived broken | `061_5I.sql`, `065_5I.sql`, `068_5J.sql`, `069_5J.sql` (defect); fixed by `076_5K1.sql` (patch, additive) | **RESOLVED** by Phase 5K.1 (§4) — originally BLOCKING |
| 3 | `app_platform_admin` INSERT grant conflict on `workflow.workflow_executions` | `041_5G.sql` vs `046_5G.sql` (defect); fixed by `076_5K1.sql` (patch, additive) | **RESOLVED** by Phase 5K.1 (§4) — originally BLOCKING |

Both items above were pre-existing defects in the frozen `migrations/*.sql` package
that Phase 5K validation was specifically designed to surface — surfacing, root-causing,
and evidencing them **was** Phase 5K doing its job correctly, per the explicit
instruction never to fabricate a PASS or hide a discovered defect. Neither defect was
fixed by editing any of the 75 frozen historical files (`001_5B.sql`...`075_5J.sql`
remain byte-for-byte as validated); both were corrected by the new additive forward
migration described in §4. See `FINAL_5K_VALIDATION_REPORT.md` for the full closure
decision.

---

## 4. Phase 5K.1 — corrective patch migration (2026-08-19)

Both BLOCKING findings above are resolved by a single new forward-only migration,
added on top of the validated 75-revision chain with **zero modification** to any of
migrations 001-075 (no edits, no renumbering, no revision-ID or checksum changes —
independently confirmed in `MIGRATION_MANIFEST.md`'s reconciliation section and in
`ALEMBIC_VALIDATION_REPORT.md` §4).

| Field | Value |
|---|---|
| SQL file | `migrations/076_5K1.sql` |
| Alembic revision | `alembic/versions/076_5K1.py`, `revision="076_5K1"`, `down_revision="075_5J"` |
| Size | 15399 bytes |
| SHA-256 | `f787be772f5d78095eb69e16d29b5189ba7af72086e972df17d267c8e294429c` (see `MIGRATION_MANIFEST.md` row 076) |
| Txn mode | transactional |
| Downgrade | `NotImplementedError` — forward-only, consistent with all 75 prior revisions |

### Defect-to-fix mapping

| Defect | Fix applied by `076_5K1.sql` | Scope discipline |
|---|---|---|
| §2 above: 5 `SECURITY DEFINER` functions missing `public` in `search_path` | `CREATE OR REPLACE FUNCTION` reissued with an identical body/signature/return type/owner and `SET search_path = <own_schema>, pg_catalog, public` (i.e. the original clause with `public` appended) for exactly `analytics.fn_claim_projection_slot`, `analytics.fn_apply_projection_call_metrics`, `analytics.fn_apply_projection_call_latency`, `plugins.fn_create_plugin_installation`, `integrations.fn_create_integration_connection` — chosen over a bare `ALTER FUNCTION ... SET search_path` so the full function definition stays visible/auditable in the patch, and because `CREATE OR REPLACE FUNCTION` does not reset existing `GRANT`/`REVOKE` state | The other 19 flagged-but-unaffected functions (no `INSERT INTO` in body) are left untouched — patch is not a blanket fix, matching the governing instruction not to blindly patch every `SECURITY DEFINER` function |
| §3 above: `app_platform_admin` holds `INSERT` on `workflow.workflow_executions` | Dynamic `pg_inherits`-based `DO $$ ... $$` block issuing `REVOKE INSERT ON workflow.workflow_executions FROM app_platform_admin;` against the parent table and every existing partition child | All other grants/revokes on the `workflow` schema (rows 1-7, 9-13 of §18) are untouched; `app_api`/`app_worker` privileges unchanged |

### Live re-validation (not catalog-only)

- **Fresh-DB upgrade:** `alembic upgrade head` from a genuinely empty PostgreSQL 16
  database, 76/76 revisions apply cleanly, exit code 0.
  (`execution_logs/20260819T110500Z_42_...txt` through `_44_...txt`;
  `ALEMBIC_VALIDATION_REPORT.md` §4.)
- **Defect A live re-verification:** all 5 previously-broken functions directly
  re-executed post-patch; all now succeed (no `gen_random_bytes` error).
  (`execution_logs/20260819T110500Z_45_defectA_searchpath_live_verification_RESOLVED.txt`.)
- **Defect B live re-verification:** direct `INSERT` from `app_platform_admin` now
  denied (`permission denied for table workflow_executions`); the approved path via
  `fn_start_workflow_execution` still succeeds and still enforces the
  no-double-active-session invariant.
  (`execution_logs/20260819T110500Z_46_defectB_workflow_insert_live_verification_RESOLVED.txt`.)
- **Full §18 security suite re-run:** 16/16 PASS, including row 8 (formerly FAIL).
  (`execution_logs/20260819T110500Z_47_security_suite_full_rerun_16of16_PASS.txt`.)
- **Full §19 concurrency suite re-run:** 7/7 PASS, including row 2 (formerly FAIL).
  (`execution_logs/20260819T110500Z_48_concurrency_suite_full_rerun_7of7_PASS.txt`.)
- **Post-patch schema validation:** aggregate object counts (tables, indexes,
  triggers, RLS policies, extensions, `SECURITY DEFINER` function count) unchanged
  before/after `076_5K1`, confirming the patch is narrowly scoped to the two defects
  and introduces no unrelated schema drift.
  (`execution_logs/20260819T110500Z_49_schema_validation_post076_and_table_count_reconciliation.txt`;
  `SCHEMA_VALIDATION_REPORT.md` §4.)

### Auditability

Per the governing instruction never to delete discovered-defect evidence, every
original FAIL/root-cause file referenced in §2 and §3 above
(`20260819T072859Z_27_...txt`, `_32_concurrency_r2_conn_A/B.txt`, `_39_...txt`,
`_40_...txt`, `20260819T081500Z_41_...txt`) remains present and untouched in
`execution_logs/`. The new `20260819T110500Z_*` files are additive evidence
completing the chain: DISCOVERED (batches 1-3) → ROOT CAUSED (batches 1-3) → PATCHED
→ RETESTED → RESOLVED (this batch). See `execution_logs/README.md` for the full index.

**Section 4 result: PHASE 5K.1 MIGRATION RECONCILIATION: PASS — both BLOCKING findings
RESOLVED, live-evidenced, narrowly scoped, no unrelated changes.**
