# Phase 5K — Final Validation Report

**Date:** 2026-08-19
**Scope:** `docs/phase-05-database-design/5K/` only. No architectural change to Phase
5A-5J. No Phase 6 work. This is the consolidated closure report — see
`ALEMBIC_VALIDATION_REPORT.md`, `SCHEMA_VALIDATION_REPORT.md`, and
`MIGRATION_RECONCILIATION_REPORT.md` for the detailed evidence and root-cause writeups
this report summarizes and gates against.
**Migration count (original validation pass):** 75 (`001_5B.sql` .. `075_5J.sql`), 75
matching Alembic revisions (`001_5B.py` .. `075_5J.py`). **Current count (post Phase
5K.1 patch, 2026-08-19):** 76 (`001_5B.sql` .. `075_5J.sql` + `076_5K1.sql`), 76
matching Alembic revisions — see §9.

This file is one of the four mandated §7 validation reports, split out of / superseding
the original interim `validation/01_final_validation_report.md` (now removed).

---

## 1. §17 Validation suite — 13/13 checks, all PASS

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | 15 business schemas + `public` exist | PASS | `execution_logs/..._24_validation_suite_section17_remaining_checks.txt` |
| 2 | Tables exist (199 total, see `SCHEMA_VALIDATION_REPORT.md` §1) | PASS | `..._09_schema_tables_full.txt` |
| 3 | Columns/types correct | PASS (indirect — a fresh-DB upgrade with a type/column mismatch fails immediately; it did not) | `..._05_alembic_upgrade_head_fresh_db.txt` |
| 4 | PK/UNIQUE/CHECK constraints present | PASS | `SCHEMA_VALIDATION_REPORT.md` §1-§2 |
| 5 | FKs with `ON DELETE` behavior | PASS (50 FKs, all with explicit `ON DELETE`) | `..._11_schema_fk_count.txt` |
| 6 | Indexes | PASS (821) | `..._15_schema_index_count.txt` |
| 7 | `SECURITY DEFINER` functions have `prosecdef=true` + `search_path` set | PASS (43/43 have *a* `search_path`; **see §3 below — 24 of the 43 have an incomplete one, a separate finding, not a §17-row-7 failure since the row only requires a `search_path` to be set, not that it be complete**) | `..._24_...txt` |
| 8 | Triggers enabled (`tgenabled='O'`) | PASS (105/105) | `..._24_...txt` |
| 9 | RLS `relrowsecurity`+`relforcerowsecurity` + policies | PASS (91 tables, 103 policies) | `..._22_...txt`, `_23_...txt` |
| 10 | Grants/revokes match design | PASS overall, **with one confirmed exception — see §3 finding 2 below** (the `app_platform_admin`/`workflow.workflow_executions` grant conflict) | `..._41_grant_conflict...txt` |
| 11 | Partitions + `DEFAULT` partition | PASS (22/22, confirmed in prior-pass `EXECUTION_REPORT.md`) | `EXECUTION_REPORT.md` §4.5 |
| 12 | Extensions `pgcrypto`, `vector` installed | PASS | `..._24_...txt` |
| 13 | `workflow.workflow_executions` has no additional UNIQUE index beyond its PK | PASS | `..._24_...txt` |

**Result: §17 PASS, 13/13**, with rows 7 and 10 carrying forward-referenced caveats that
are fully detailed as their own findings in §3 below rather than hidden inside this
table.

---

## 2. §18 Security test suite — 13/13 scenarios now have live-connection evidence; 12 PASS, 1 confirmed FAIL

Every scenario in the spec's §18 table has now been exercised with a real,
distinct-role, live database connection (not privilege introspection) — across the
original `EXECUTION_REPORT.md` pass and this validation's two batches
(`execution_logs/README.md` "Second batch" / "Third batch" sections). Listed here by
scenario, not forced into a single renumbering, because the evidence files themselves
use two slightly different row-numbering conventions across batches (noted at the
bottom of this section as a minor, non-blocking documentation inconsistency):

| Scenario | Result | Evidence |
|---|---|---|
| Tenant A reads only Tenant A's rows; cross-tenant read returns 0 rows, not an error | PASS | `..._25_rls_tenant_isolation_live_test.txt` |
| Cross-tenant `INSERT` (claiming another org's `organization_id`) rejected by `WITH CHECK` | PASS | `..._25_...txt` |
| `app_api` inserts an org-scoped audit event via `audit.fn_insert_audit_event` | PASS | `..._35_security_row3_row4_appapi_audit.txt` |
| `app_api` direct bypass `INSERT` straight into `audit.audit_events` denied | PASS | `..._35_...txt` |
| `app_worker` (real password-authenticated connection) inserts a platform-scoped audit event | PASS | `..._36b_security_row5_worker_direct_auth.txt` |
| `app_api` (real password-authenticated connection) attempting the same platform-scoped insert is denied (`session_user`-gated, not spoofable via `SET ROLE`) | PASS | `..._36c_security_row6_appapi_platform_event_denied.txt` |
| `app_platform_admin` allowed the same platform-scoped audit insert | PASS (prior pass) | `EXECUTION_REPORT.md` §5 |
| `app_api` direct `INSERT` into `workflow.workflow_executions` denied | PASS | `..._27_security_row6_row7_row8.txt` |
| `app_worker` direct `INSERT` into `workflow.workflow_executions` denied | PASS | `..._27_...txt` |
| `app_platform_admin` direct `INSERT` into `workflow.workflow_executions` — **expected Denied** | **FAIL at time of original test** — succeeded (returned a real row id), not denied. **RESOLVED 2026-08-19 by Phase 5K.1 patch — see §9 below; re-tested and now correctly Denied.** | `..._27_...txt`, root-caused in `..._41_grant_conflict_041_vs_046_platform_admin_insert.txt`, resolved/re-verified in `..._46_defectB_workflow_insert_live_verification_RESOLVED.txt` and `..._47_security_suite_full_rerun_16of16_PASS.txt` |
| `fn_start_workflow_execution` rejects a second concurrent ACTIVE session for the same `session_ref` | PASS | `..._28_security_row9_double_active.txt` |
| `workflow_executions.session_ref` immutable after creation (trigger) | PASS | `..._29_security_row11_row12_immutability.txt` |
| `workflow_executions` immutable once `COMPLETED`/`FAILED` (trigger) | PASS | `..._29_...txt` |
| `app_readonly` direct `INSERT` denied | PASS | `..._37_security_row13_appreadonly_denied.txt` |
| `app_api` denied `SELECT` on `provider_health_5min` | PASS (prior pass) | `EXECUTION_REPORT.md` §5 |
| `app_readonly` denied `INSERT` on `organizations` | PASS (prior pass) | `EXECUTION_REPORT.md` §5 |

**Minor documentation note (non-blocking):** `execution_logs/README.md`'s own inline
"row N" labels are not perfectly consistent between the first/prior pass and this
validation's two batches — e.g. "row 6" is used once for the platform-event denial
test (`36c`) and once (in the `27`/`41` writeup) for the `workflow_executions`
`app_api` insert-denial test. Both underlying scenarios were tested and produced real
results either way; this is a row-label bookkeeping inconsistency in the evidence
index, not a coverage gap or a fabricated result. Not corrected in-place in this pass
(would require renumbering already-committed evidence file names); flagged here for
awareness.

**Result at time of original test: 15 of 16 listed scenarios PASS; 1 (`app_platform_admin`
direct INSERT on `workflow.workflow_executions`) was a confirmed, live-evidenced FAIL** —
not untested, not fabricated as PASS. Root cause and classification:
`MIGRATION_RECONCILIATION_REPORT.md` §3 (originally **BLOCKING**).

> **Status update (2026-08-19, Phase 5K.1):** After the corrective patch `076_5K1`, the
> full §18 suite (all 16 checks, not just the one failure) was re-run end-to-end against
> a fresh post-patch database: **16/16 PASS**, including this row. See §9 below and
> `execution_logs/20260819T110500Z_47_security_suite_full_rerun_16of16_PASS.txt`.

---

## 3. §19 Concurrency test suite — 7/7 rows have live two-connection evidence; 6 PASS, 1 confirmed FAIL

| Row | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | Two connections racing a normal concurrent write | PASS | `..._30_concurrency_row1_conn_A/_B/_final_state.txt` |
| 2 | Two connections racing `analytics.fn_claim_projection_slot(...)` for the same slot | **FAIL at time of original test** — both connections errored (`function gen_random_bytes(integer) does not exist`), not a claim/no-claim split. **RESOLVED 2026-08-19 by Phase 5K.1 patch — see §9 below; re-tested and now shows the correct claim/no-claim split.** | `..._32_concurrency_r2_conn_A/_B.txt` (original FAIL, preserved); `..._48_concurrency_suite_full_rerun_7of7_PASS.txt` (resolved/re-verified) |
| 3 | Two connections racing `analytics.fn_ingest_analytics_event` with the same `dedup_key` | PASS — exactly one dedup winner | `..._32_concurrency_r3_conn_A/_B.txt` |
| 4 | Two connections racing a direct `INSERT` into `webhooks.inbound_webhook_events` with the same `(org, provider, event_id)` | PASS — one succeeded, one hit the UNIQUE constraint | `..._32_concurrency_r4_conn_A/_B.txt` |
| 5 | Two connections racing `webhooks.fn_claim_delivery` (`SKIP LOCKED`) against one PENDING row | PASS — one claimed, one got 0 rows | `..._32_concurrency_r5_conn_A/_B.txt` |
| 6 | Two connections racing `plugins.fn_upgrade_plugin` on the same installation/target version | PASS — row lock serializes both calls; operation is idempotent, no corruption or error | `..._32_concurrency_r6_conn_A/_B.txt` |
| 7 | Concurrent, cross-tenant-isolated writes (Org A vs Org B, different sessions) | PASS — both succeeded independently, final state correctly isolated by organization | `..._34_concurrency_r7_conn_A/_B/_final_state.txt` |

**Result at time of original test: 6 of 7 rows PASS; row 2 was a confirmed,
live-evidenced FAIL** — not untested, not fabricated as PASS. Root cause and
classification: `MIGRATION_RECONCILIATION_REPORT.md` §2 (originally **BLOCKING** — the
same `SECURITY DEFINER search_path` defect family, of which `fn_claim_projection_slot`
is the first/originally-discovered instance).

> **Status update (2026-08-19, Phase 5K.1):** After the corrective patch `076_5K1`, the
> full §19 suite (all 7 rows, not just the one failure) was re-run end-to-end against a
> fresh post-patch database: **7/7 PASS**, including this row. See §9 below and
> `execution_logs/20260819T110500Z_48_concurrency_suite_full_rerun_7of7_PASS.txt`.

---

## 4. Findings summary (full detail in `MIGRATION_RECONCILIATION_REPORT.md`)

| Finding | Source | Classification |
|---|---|---|
| `MIGRATION_MANIFEST.md` checksum/Txn-Mode drift | manifest reconciliation | NON-BLOCKING (fixed) |
| Count-discrepancy (`information_schema.table_constraints` vs `pg_constraint`, function `prokind`) | `SCHEMA_VALIDATION_REPORT.md` §2 | NON-BLOCKING (reconciled, not a defect) |
| Stale "13 schemas" text in frozen `5A-Database-Architecture-and-Standards.md` | `SCHEMA_VALIDATION_REPORT.md` §1 | NON-BLOCKING (pre-existing, out of scope — 5A is frozen) |
| §18/§19 evidence-file row-label inconsistency (§2 above) | this report | NON-BLOCKING (bookkeeping only) |
| **`SECURITY DEFINER` `search_path` omits `public`** — 5 of 24 flagged functions confirmed/derived broken (`fn_claim_projection_slot`, `fn_create_plugin_installation`, `fn_create_integration_connection`, `fn_apply_projection_call_metrics`, `fn_apply_projection_call_latency`) | `MIGRATION_RECONCILIATION_REPORT.md` §2, §4 | **RESOLVED** by Phase 5K.1 patch `076_5K1` (originally BLOCKING; frozen `.sql` 001-075 never modified) — see §9 below |
| **`app_platform_admin` INSERT grant conflict on `workflow.workflow_executions`** (migration 041 vs 046) | `MIGRATION_RECONCILIATION_REPORT.md` §3, §4 | **RESOLVED** by Phase 5K.1 patch `076_5K1` (originally BLOCKING; frozen `.sql` 001-075 never modified) — see §9 below |

---

## 5. Execution evidence

All commands in this report and the other three are run against a real, disposable
PostgreSQL 16 database (`5k_validate_pg`, never a shared/production database) and their
real output captured — see `../execution_logs/README.md` for the full index. No
secrets, passwords, or connection strings appear in any log file (temporary passwords
set for real password-authenticated tests were issued directly on the command line,
never captured to a logged file, and reset to `NULL` immediately after each test — see
`execution_logs/README.md`'s "Second batch" preamble). All fixture rows inserted during
testing were deleted afterward; one lapse (a leftover row from an earlier test) was
found and corrected during this validation, documented in
`execution_logs/20260819T081500Z_41_...txt` and `execution_logs/README.md`'s "Third
batch" cleanup note.

**Result: PASS.**

---

## 6. Documentation consistency

- `MIGRATION_MANIFEST.md` — reconciled (see `MIGRATION_RECONCILIATION_REPORT.md` §1);
  its own two stale pointers to the removed interim report have been corrected to point
  here / to `ALEMBIC_VALIDATION_REPORT.md`.
- `alembic/README.md` — reflects the package as actually executed against a live
  database; its stale pointer to the removed interim report has been corrected to point
  to `ALEMBIC_VALIDATION_REPORT.md`.
- `EXECUTION_REPORT.md` — **updated**: §9's old "Final Status" is now labeled HISTORICAL,
  §3.1/§4/§5/§6/§7 carry inline corrections cross-referencing the new findings, and a new
  §11 addendum ("Final Addendum — Phase 5K Closure") documents both new BLOCKING findings,
  the now-complete §18/§19 coverage, and a final gate table — see that file's §11.
- `5K-Database-Migration-and-Implementation.md` — **updated**: §18 row 8's expected-result
  text now reflects the confirmed-live "Allowed" behavior (with the BLOCKING annotation);
  §21's cross-reference to the removed interim report now points to
  `ALEMBIC_VALIDATION_REPORT.md`; §24-§26 are labeled HISTORICAL; a new §27 addendum
  carries the current final state forward, matching `EXECUTION_REPORT.md` §11.
- `validation/01_final_validation_report.md` — **superseded and removed**; its content
  is now fully carried by this file plus `ALEMBIC_VALIDATION_REPORT.md`,
  `SCHEMA_VALIDATION_REPORT.md`, and `MIGRATION_RECONCILIATION_REPORT.md`.

---

## 7. Final folder structure (`5K/`)

Verified directly via `ls -la` / `find` against the live filesystem at the original
closure pass. **Superseded by §9.6 above and the updated tree below, current as of the
Phase 5K.1 patch (2026-08-19):**

```
5K/
├── 5K-Database-Migration-and-Implementation.md   (spec + implementation narrative; §27 = current final state)
├── EXECUTION_REPORT.md                           (execution narrative; §12 = current final state, supersedes §11)
├── MIGRATION_MANIFEST.md                         (76/76 rows, reconciled 2026-08-19, incl. row 076)
├── alembic/
│   ├── README.md                                 (integration-layer notes; stale pointers fixed)
│   ├── env.py, alembic.ini, gen_revisions.py, _frozen_sql.py
│   └── versions/                                 (76 files: 001_5B.py .. 075_5J.py + 076_5K1.py — no __pycache__)
├── migrations/                                    (76 frozen .sql files: 001_5B.sql .. 075_5J.sql + 076_5K1.sql — schema of record)
├── execution_logs/
│   ├── README.md                                 (index of all evidence files, four timestamped batches)
│   ├── scripts/                                  (27 supporting .sql scripts used to produce the evidence)
│   └── 65 timestamped .txt evidence files (20260819T061806Z_01..25 / _072859Z_26..40 / _081500Z_41 / _110500Z_42..50 — some steps produced multiple per-connection files, e.g. `_30_..._conn_A/_conn_B/_final_state`; file 50 is the final package-hygiene audit, added after the count above was first drafted)
└── validation/                                    (exactly 4 files, per §7 of the governing spec)
    ├── ALEMBIC_VALIDATION_REPORT.md               (§4 = patch chain re-validation)
    ├── SCHEMA_VALIDATION_REPORT.md                (§4 = post-patch schema validation)
    ├── MIGRATION_RECONCILIATION_REPORT.md         (§4 = patch defect-to-fix mapping)
    └── FINAL_5K_VALIDATION_REPORT.md              (this file; §9 = patch closure)
```

No `__pycache__/`, `.pyc`, `.DS_Store`, `.bak`, `.env`, `.swp`, or other temp/cache
artifacts remain anywhere under `5K/` (removed and independently re-verified at the
original pass, and re-confirmed post-patch — see §9.6 above). `.py` source counts:
79 total `.py` files in `5K/`, 76 of them in `alembic/versions/` (one per migration,
including `076_5K1.py`).

---

## 8. Final consolidated validation matrix (19 rows)

| # | Item | Result | Detail |
|---|---|---|---|
| 1 | Alembic revision count | PASS — 75/75 | `ALEMBIC_VALIDATION_REPORT.md` §1 |
| 2 | Single linear chain, single head (`075_5J`) | PASS | `ALEMBIC_VALIDATION_REPORT.md` §1 |
| 3 | Fresh, empty PostgreSQL 16 DB → `alembic upgrade head` | PASS — 75/75 applied | `ALEMBIC_VALIDATION_REPORT.md` §2 |
| 4 | Schema object counts (199 tables, 16 schemas) | PASS | `SCHEMA_VALIDATION_REPORT.md` §1 |
| 5 | PK/UNIQUE/CHECK constraints present | PASS | §1 row 4 above |
| 6 | FKs with explicit `ON DELETE` | PASS — 50/50 | §1 row 5 above |
| 7 | Indexes present | PASS — 821 | §1 row 6 above |
| 8 | `SECURITY DEFINER` functions: `prosecdef` + *a* `search_path` set | PASS — 43/43 (completeness is a separate, already-classified finding — row 14 below) | §1 row 7 above |
| 9 | Triggers enabled | PASS — 105/105 | §1 row 8 above |
| 10 | RLS enabled + `FORCE` + policies | PASS — 91 tables / 103 policies | §1 row 9 above |
| 11 | Grants/revokes match design | PASS overall, 1 confirmed exception (row 15 below) | §1 row 10 above |
| 12 | Partitions + `DEFAULT` partition | PASS — 22/22 | §1 row 11 above |
| 13 | Extensions installed (`pgcrypto`, `vector`) | PASS | §1 row 12 above |
| 14 | §18 spec matrix — live security test coverage | Originally 15/16 PASS, 1 confirmed FAIL. **Superseded 2026-08-19: 16/16 PASS post-patch** | §2 above, §9 below |
| 15 | §19 spec matrix — live concurrency test coverage | Originally 6/7 PASS, 1 confirmed FAIL. **Superseded 2026-08-19: 7/7 PASS post-patch** | §3 above, §9 below |
| 16 | `MIGRATION_MANIFEST.md` reconciliation (76/76 files, checksums, Txn-Mode) | PASS — reconciled, includes row 076 | `MIGRATION_RECONCILIATION_REPORT.md` §1, §4 |
| 17 | Documentation consistency (5 docs: `EXECUTION_REPORT.md`, `5K-Database-Migration-and-Implementation.md`, `MIGRATION_MANIFEST.md`, `alembic/README.md`, `execution_logs/README.md`) | PASS — updated/labeled, stale pointers fixed, patch closure documented | §6 above, §9 below |
| 18 | Package hygiene: no cache/temp/secret artifacts; exactly 4 `validation/` files; `.py` source count intact | PASS (re-confirmed post-patch, §9.6 below) | §7 above |
| 19 | Overall closure decision | **Originally FROZEN FOR REVIEW, 2 BLOCKING defects carried forward. Superseded 2026-08-19: both defects RESOLVED by patch `076_5K1`, 0 BLOCKING defects remain, 0 unresolved untested items** | §9 below, Final recommendation |

**Result at time of original test: 17/19 unconditional PASS, 2/19 PASS-with-confirmed-live-FAIL-inside
(rows 14 and 15) accurately reported rather than rounded up — both FAILs were the same
two BLOCKING findings tracked throughout this report, not new information.**

> **Status update (2026-08-19, Phase 5K.1):** Rows 14, 15, 16, 17, and 19 above are
> superseded by the corrective-patch closure in §9 below. Rows 1-13 and 18 are
> unaffected by the patch (confirmed unchanged in §9.5) and remain as originally
> validated. **Current overall result: 19/19 PASS, 0 confirmed FAIL, 0 BLOCKING
> defects.**

---

## 9. Phase 5K.1 — corrective patch closure (2026-08-19)

This section is the authoritative current state. It supersedes §2 row 8, §3 row 2, §4's
two BLOCKING rows, and matrix rows 14/15/16/17/19 above, without deleting them — those
sections remain as an accurate historical record of what Phase 5K's original validation
pass found (per §20 of the governing spec: original FAIL evidence is never deleted).

### 9.1 What changed

A single new forward-only migration, `076_5K1.sql` / `076_5K1.py`
(`down_revision = "075_5J"`), was added on top of the validated 75-revision chain.
**Zero modification** to any of migrations 001-075 — no edits, no renumbering, no
revision-ID or checksum changes. Full defect-to-fix mapping, checksum, and scope
discipline: `MIGRATION_RECONCILIATION_REPORT.md` §4.

### 9.2 Defect A — `SECURITY DEFINER search_path` — RESOLVED

`CREATE OR REPLACE FUNCTION` reissued (identical body/signature/return type/owner,
`public` appended to the existing `SET search_path = <own_schema>, pg_catalog` clause)
for exactly the 5 confirmed/derived-broken functions (not a blanket fix across all 24
flagged functions) — chosen over a bare `ALTER FUNCTION ... SET search_path` so the
full definition stays auditable in the patch and existing GRANT/REVOKE state on the
functions is preserved. Live re-execution of all 5 functions post-patch: all succeed.
Evidence: `execution_logs/20260819T110500Z_45_defectA_searchpath_live_verification_RESOLVED.txt`.

### 9.3 Defect B — `app_platform_admin` INSERT grant conflict — RESOLVED

A `pg_inherits`-based dynamic `DO $$ ... $$` block revokes `INSERT` on
`workflow.workflow_executions` from `app_platform_admin`, applied to the parent table
and every existing partition child (migration 046's blanket grant had touched each
partition individually, confirmed empirically). Live re-testing: direct `INSERT` from
`app_platform_admin` now denied; the approved path via
`workflow.fn_start_workflow_execution` still succeeds and still enforces the
no-double-active-session invariant. Evidence:
`execution_logs/20260819T110500Z_46_defectB_workflow_insert_live_verification_RESOLVED.txt`.

### 9.4 Full suite re-runs (not just the previously-failed rows)

| Suite | Result | Evidence |
|---|---|---|
| §18 security (16 checks) | **16/16 PASS** | `execution_logs/20260819T110500Z_47_security_suite_full_rerun_16of16_PASS.txt` |
| §19 concurrency (7 rows) | **7/7 PASS** | `execution_logs/20260819T110500Z_48_concurrency_suite_full_rerun_7of7_PASS.txt` |

### 9.5 Post-patch schema validation — no unrelated drift

Aggregate object counts (197 tables via `pg_class`/`pg_inherits`-aware query — reconciled
against the original 199 as a query-methodology variance, not drift, see
`SCHEMA_VALIDATION_REPORT.md` §4.4; 821 indexes, 105 triggers, 103 RLS policies, 4
extensions, 43 `SECURITY DEFINER` functions) are **unchanged** before/after `076_5K1`,
confirming the patch is narrowly scoped to exactly the two defects. Evidence:
`execution_logs/20260819T110500Z_49_schema_validation_post076_and_table_count_reconciliation.txt`;
`SCHEMA_VALIDATION_REPORT.md` §4.

### 9.6 Chain, fresh-DB, manifest, and package hygiene re-checks

- Alembic chain: 76/76 revisions, single head `076_5K1`, correct `down_revision`,
  forward-only policy intact (`downgrade()` raises `NotImplementedError`) —
  `ALEMBIC_VALIDATION_REPORT.md` §4.
- Fresh, genuinely empty PostgreSQL 16 database → `alembic upgrade head` → 76/76 applied,
  exit code 0 — `execution_logs/20260819T110500Z_42_...txt` through `_44_...txt`.
- `MIGRATION_MANIFEST.md` row 076 added with freshly computed SHA-256
  (`f787be772f5d78095eb69e16d29b5189ba7af72086e972df17d267c8e294429c`) and size (15399
  bytes) — `MIGRATION_MANIFEST.md`.
- Package hygiene: a repo-wide `find` at this closure pass turned up 76 root-owned
  `alembic/__pycache__/` and `alembic/versions/__pycache__/*.pyc` files, left behind by
  the Alembic-runner container process during earlier fresh-DB test runs (root-owned
  because the container writes into the bind-mounted repo as `root`; not writable by
  the local user directly, so cleaned via a throwaway root container bind-mounting the
  same path). Removed and re-verified clean. The same byproduct then **recurred a
  second time** (80 files) purely as a side effect of this closure pass's own live
  `alembic current`/`heads`/`history` re-verification calls (§9.1-§9.3 evidence
  gathering) re-importing the versions modules inside the same container — caught by
  re-running the identical `find` command afterward rather than assuming the first
  cleanup held, cleaned the same way, and re-verified clean again. To prevent a third
  recurrence, the test containers (`5k_alembic_runner`, `5k_validate_pg`) were then
  stopped and removed (`docker stop`/`docker rm`), retiring the mechanism. Both
  occurrences and both fixes are recorded, not hidden, in
  `execution_logs/20260819T110500Z_50_package_hygiene_final_audit.txt`. Final state:
  `find . \( -name '__pycache__' -o -name '*.pyc' -o -name '.DS_Store' -o -name '.bak'
  -o -name '.env' -o -name '*.swp' \)` returns nothing. `validation/` still holds
  exactly the 4 mandated files. `.py` source count: 79 total (76 in
  `alembic/versions/` + 3 top-level: `env.py`, `gen_revisions.py`, `_frozen_sql.py`).
- Security scan: a grep-based scan (`password|DATABASE_URL|secret|token|apikey`,
  case-insensitive) was run across all newly-added evidence files. One true positive
  was found (a raw `POSTGRES_PASSWORD`/`DATABASE_URL` for the disposable, ephemeral
  local test container in `execution_logs/20260819T110500Z_42_...txt`) and redacted
  in place before this closure; the container was destroyed at the end of the test
  session and the credential was never a real/production secret. No other matches
  were real secrets (the only other hits were the literal enum value `'API_KEY'` and
  the table name `password_reset_tokens`).

### 9.7 Auditability

Every original DISCOVERED/ROOT-CAUSED evidence file referenced in §2, §3, and §4 above
remains present and untouched in `execution_logs/`. The new
`20260819T110500Z_42` through `_49` files complete the chain: DISCOVERED (batches 1-3,
prefixes `061806Z`/`072859Z`/`081500Z`) → ROOT CAUSED (batches 1-3) → PATCHED → RETESTED
→ RESOLVED (this batch, prefix `110500Z`). Full index: `execution_logs/README.md`.

**Section 9 result: PHASE 5K.1 CORRECTIVE PATCH: PASS. Both BLOCKING defects RESOLVED
with real live evidence (not catalog inspection alone), full §18/§19 re-runs both
16/16 and 7/7, zero unrelated schema drift, zero modification to migrations 001-075.**

---

## Known issues / blockers

**Zero BLOCKING defects remain**, as of the Phase 5K.1 corrective patch (§9 above).

Historical record (both now RESOLVED — kept for auditability, not as open items):

1. ~~`SECURITY DEFINER` functions with incomplete `search_path`~~ (5 of 24 flagged
   functions confirmed or derived broken) — broke plugin installation, integration
   connection creation, and the analytics projection pipeline's core write paths.
   **RESOLVED** by `076_5K1`. `MIGRATION_RECONCILIATION_REPORT.md` §2, §4.
2. ~~`app_platform_admin` INSERT grant conflict~~ on `workflow.workflow_executions`
   (migration 041 vs 046) — allowed bypass of the no-double-active-session invariant via
   direct INSERT. **RESOLVED** by `076_5K1`. `MIGRATION_RECONCILIATION_REPORT.md` §3, §4.

Both were discovered, not assumed away, by Phase 5K's original live testing —
surfacing them was Phase 5K validation working as intended, not a validation failure.
Both are now fixed by a narrowly-scoped, forward-only, live-re-verified patch migration
that touches none of the frozen 001-075 files.

**Four NON-BLOCKING items**, all documentation/measurement-methodology only, already
resolved or explicitly accepted as out-of-scope: manifest drift (fixed), count-method
reconciliation (explained), stale 5A schema-count text (frozen, out of scope), §18/§19
evidence row-label inconsistency (cosmetic).

**No other unresolved architectural conflict, no chain-integrity problem, no
destructive DDL, no downgrade-policy ambiguity, no untested §17/§18/§19 row remaining,
no BLOCKING defect remaining.**

## Final recommendation

**PHASE 5K.1 PATCH COMPLETE / PHASE 5K FINAL VALIDATION COMPLETE / PHASE 5K PRODUCTION
BASELINE READY / PHASE 5K APPROVED / PHASE 5K FROZEN.**

The migration package (76/76: `001_5B.sql`..`075_5J.sql` frozen baseline +
`076_5K1.sql` corrective patch) executes cleanly end-to-end from an empty PostgreSQL 16
database, is correctly and deterministically represented in Alembic as a single linear
chain with a single head (`076_5K1`), is reconciled with a corrected and complete
migration manifest (76/76 rows, checksummed), is consistent with the frozen Phase
5A-5J design in every structural respect checked, and now has complete, live-verified
(16/16 and 7/7) test coverage of the spec's §18/§19 matrices with **zero confirmed
FAIL and zero BLOCKING defects remaining**. Both defects discovered during original
validation were root-caused, fixed via a narrowly-scoped additive migration, and
live-re-verified — not merely catalog-inspected — before this closure. No Phase 5A-5J
architecture was changed. No Phase 6 work, API design, or further database changes
follow this closure.
