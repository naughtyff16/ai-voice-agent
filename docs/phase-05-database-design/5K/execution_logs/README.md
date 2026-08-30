# Execution logs — Phase 5K final validation (2026-08-19)

All files below carry the prefix `20260819T061806Z`, the UTC start time of
the fresh-database `alembic upgrade head` run (captured in file `05`; the
run completed at `2026-08-19T06:18:10Z`, per the source timing files this
was generated from). Every command was run against a disposable, purpose-
built PostgreSQL 16 container (`pgvector/pgvector:pg16`) created and
destroyed solely for this validation — never against any shared or
production database. No connection string, password, or other secret
appears in any file here; where SQLAlchemy's own log output includes a
connection URL, the password segment is already masked as `***` by
SQLAlchemy itself (see file `04`).

| File | Command | Purpose |
|---|---|---|
| `01_alembic_history_verbose.txt` | `alembic history --verbose` | Full chain metadata for all 75 revisions, run before the fresh-DB gate, to inspect for duplicate/branch/orphan revisions. |
| `02_alembic_history_order.txt` | `alembic history` | Compact base→head ordering, used to confirm a single linear chain (no branches). |
| `03_alembic_heads_preflight.txt` | `alembic heads --verbose` | Confirms exactly one head (`075_5J`) before the fresh-DB run. |
| `04_alembic_current_preflight.txt` | `alembic current --verbose` | State of the pre-existing validation DB before it was dropped and recreated (shows it was already at `075_5J` from prior work — this is why the DB was explicitly dropped/recreated next, to get a genuinely empty starting point). |
| `05_alembic_upgrade_head_fresh_db.txt` | `alembic upgrade head` | **The Section 5 critical gate.** Full output of upgrading a genuinely empty, freshly dropped-and-recreated database from base to `075_5J`. All 75 "Running upgrade" lines present, exit code 0. This is the run that surfaced and confirmed the fix to `_frozen_sql.py` (see `alembic/README.md`'s "Update" section and `EXECUTION_REPORT.md` §10) — an earlier attempt on an equally empty database failed at revision `002_5B` with a psycopg2 paramstyle error; that failing run's raw output was not preserved as a separate file (it was overwritten by this successful re-run), but the root cause, fix, and re-validation are documented in `EXECUTION_REPORT.md` §10 and `alembic/README.md`. |
| `06_alembic_current_post_upgrade.txt` | `alembic current --verbose` | Confirms `075_5J (head)` immediately after the fresh-DB upgrade. |
| `07_alembic_heads_post_upgrade.txt` | `alembic heads` | Confirms `075_5J (head)` is still the single head after upgrade (no drift). |
| `08_schema_extensions.txt` | `\dx` (psql) | Installed extensions: `pgcrypto`, `vector`, `pg_stat_statements`, `plpgsql` — 4 total. |
| `09_schema_tables_full.txt` | query against `information_schema.tables` / `pg_class` joined with `pg_namespace`, all 16 schemas | Full table inventory post-upgrade: 199 rows (includes partition parent + child tables). |
| `10_schema_table_counts_by_schema.txt` | `GROUP BY table_schema` | Per-schema table counts, sums to 199 across 16 schemas. |
| `11_schema_fk_count.txt` | count of `pg_constraint` where `contype='f'` | 50 foreign keys. |
| `12_schema_pk_count.txt` | count of `pg_constraint` where `contype='p'` | 197 primary keys. |
| `13_schema_unique_count.txt` | count of `pg_constraint` where `contype='u'` | 94 unique constraints. |
| `14_schema_check_count.txt` | count of `pg_constraint` where `contype='c'` | 2,541 check constraints. |
| `15_schema_index_count.txt` | count of `pg_indexes` | 821 indexes. |
| `16_schema_view_count.txt` | count of `information_schema.views` | 2 views. |
| `17_schema_matview_count.txt` | count of `pg_matviews` | 0 materialized views. |
| `18_schema_function_count.txt` | count of `pg_proc` in non-system schemas | 219 functions. |
| `19_schema_trigger_count.txt` | count of `pg_trigger` (non-internal) | 105 triggers. |
| `20_schema_enum_count.txt` | count of `pg_type` where `typtype='e'` | 0 — confirmed intentional, see `EXECUTION_REPORT.md` §10 (5A §21.7 prohibits native ENUM). |
| `21_schema_sequence_count.txt` | count of `pg_sequences` | 0 — confirmed intentional (table-based gapless allocation, `billing.invoice_number_sequences`), see `EXECUTION_REPORT.md` §10. |
| `22_schema_rls_tables.txt` | `pg_class.relrowsecurity` / `relforcerowsecurity` | 91 tables with RLS `ENABLE + FORCE`. |
| `23_schema_policy_count.txt` | count of `pg_policies` | 103 RLS policies. |
| `24_validation_suite_section17_remaining_checks.txt` | 5 targeted queries against the same live DB, run after the checks above, to close out the specific items in `5K-Database-Migration-and-Implementation.md` §17 not already covered by files 08-23 or by `EXECUTION_REPORT.md` §4: check 1 (15 business schemas + `public`, all present), check 7 (43/43 `SECURITY DEFINER` functions have `prosecdef=true` and `search_path` in `proconfig` — matches `EXECUTION_REPORT.md` §4.2), check 8 (105/105 triggers `tgenabled='O'`), check 12 (`pgcrypto`/`vector` both installed), check 13 (`workflow.workflow_executions`: the only indexes are the required PK unique index `pk_workflow_executions` (id, started_at) and five non-unique indexes including `idx_we_active_session` — no *additional* unique index exists on session-scoped columns, consistent with defect #8 in `EXECUTION_REPORT.md` §3.1, where a UNIQUE partial index was converted to non-unique because it omitted the partition key; the session-active invariant is enforced at the application layer via `pg_advisory_xact_lock`, not a DB-level unique index). |

| `25_rls_tenant_isolation_live_test.txt` | 4 live queries as role `app_api` (temporary password set via `ALTER ROLE` on the disposable test DB only, then reset to `NULL` immediately after; test rows deleted after) against `identity.api_keys`, a real RLS+FORCE-RLS table | Direct evidence for the §18 "Tenant A reads Tenant A's own data / Tenant A reads Tenant B's data" test row: session-scoped `app.tenant_id` correctly limits `SELECT` to the current tenant's row only (tests 1-2); an explicit cross-tenant `WHERE organization_id = '<other org>'` returns 0 rows rather than an error (test 3); an `INSERT` claiming another tenant's `organization_id` is rejected with `ERROR: new row violates row-level security policy` (test 4, the `WITH CHECK` half of the policy). No password or secret appears in the file — the `ALTER ROLE ... PASSWORD` commands were issued directly via `psql -c`, outside anything captured to this log. |

See `../validation/FINAL_5K_VALIDATION_REPORT.md` (and the other three
reports in `../validation/`) for the consolidated result and gate-by-gate
PASS/BLOCKED determination these logs support. (`01_final_validation_report.md`
was the single interim file used during validation; it has been split into
the four mandated reports per Phase 5K §7 — see `../validation/README.md`
if present, or the four report files directly.)

## Second batch — remaining §18/§19 live tests + count reconciliation (2026-08-19, prefix `20260819T072859Z`)

The batch above (files `01`-`25`) closed most of §17/§18. This second batch,
run later the same day against the same disposable container
(`5k_validate_pg`, `pgvector/pgvector:pg16`, already at `075_5J` from the
first batch — no re-migration needed, this batch only adds fixture rows and
runs read/write tests), closes the **remaining** rows of the §18 security
matrix and the §19 concurrency matrix, and reconciles a structural-count
discrepancy noticed while re-verifying. As before: no password, connection
string, or other secret appears in any of these files. Where a test
required a real password-authenticated connection (not `SET ROLE` — see the
note on file `36`/`36b` below), the temporary password was set and reset to
`NULL` via commands issued directly on the command line, never captured to
a logged file, and confirmed reset immediately after the test.

Fixture data used across this batch (all fictitious, no real PII):
Org A (`aaaa...`, pre-existing from the first batch) gets a webhook
endpoint + one PENDING delivery, one plugin with two approved versions and
one active installation (`scripts/..._fixtures_2.sql`, log `26`/`31`); Org B
(`bbbb...`, pre-existing) gets one workflow definition + published version
1 (`scripts/..._fixtures_orgb.sql`, log `33`), used only for the row-7
cross-tenant race.

| File | Command | Purpose |
|---|---|---|
| `26_fixture_setup.txt` | `scripts/..._setup_fixtures.sql` | Base fixtures for the still-open §18 rows (audit-event actor/org rows). |
| `27_security_row6_row7_row8.txt` | `scripts/..._test18_row6_app_api_insert.sql` / `_row7_app_worker_insert.sql` / `_row8_app_platform_admin_insert.sql` | §18 rows 6-8: org-scoped audit-event inserts as `app_api`, `app_worker`, `app_platform_admin` (via `SET ROLE`, valid here since these are org-scoped, not the `session_user`-gated platform-event path — see rows 5/6 below for that distinction). All PASS. |
| `28_security_row9_double_active.txt` | `scripts/..._test18_row9_double_active.sql` | §18 row 9: second-active-session/invariant check. PASS. |
| `29_security_row11_row12_immutability.txt` | `scripts/..._test18_row11_row12_immutability.sql` | §18 rows 11-12: `workflow.workflow_executions` immutability checks — `session_ref` immutable after creation, and the row immutable once `COMPLETED`/`FAILED` (both trigger-enforced). PASS. (Corrected 2026-08-19: this row previously mis-described the test as an `audit.audit_events` immutability check; the underlying script and captured output were always correct — only this summary text was wrong.) |
| `30_concurrency_row1_conn_A.txt` / `_conn_B.txt` / `_final_state.txt` | `scripts/..._test19_row1_concurrent_a.sql` / `_b.sql` | §19 row 1: genuine two-connection concurrent race (each `psql -f` backgrounded, `pg_sleep(0.5)` synchronized, `wait`ed, then a final-state query). PASS. |
| `31_fixture_setup_2.txt` | `scripts/..._fixtures_2.sql` | Webhook + plugin fixtures for §19 rows 2, 5, 6 (see above). |
| `32_concurrency_r2_conn_A.txt` / `_conn_B.txt` | `scripts/..._t19r2_a.sql` / `_b.sql` | §19 row 2: concurrent calls to `analytics.fn_claim_projection_slot`. **BOTH connections failed**: `ERROR: function gen_random_bytes(integer) does not exist`. This is a genuine, newly-discovered defect in the frozen SQL, not a test-setup error — see "New finding" below and `MIGRATION_RECONCILIATION_REPORT.md`. |
| `32_concurrency_r3_conn_A.txt` / `_conn_B.txt` | `scripts/..._t19r3_a.sql` / `_b.sql` | §19 row 3: concurrent calls to `analytics.fn_ingest_analytics_event` with the same `dedup_key`. One connection returned `f`, the other `t` — exactly one dedup winner. PASS. |
| `32_concurrency_r4_conn_A.txt` / `_conn_B.txt` | `scripts/..._t19r4_a.sql` / `_b.sql` | §19 row 4: concurrent direct `INSERT` into `webhooks.inbound_webhook_events` with the same `(org, provider, event_id)`. One connection succeeded, the other hit the unique constraint (`uq_iwe_org_provider_event`). PASS. |
| `32_concurrency_r5_conn_A.txt` / `_conn_B.txt` | `scripts/..._t19r5_a.sql` / `_b.sql` | §19 row 5: concurrent `webhooks.fn_claim_delivery` (`SKIP LOCKED`) against a single PENDING row. One connection claimed it, the other got 0 rows. PASS. |
| `32_concurrency_r6_conn_A.txt` / `_conn_B.txt` | `scripts/..._t19r6_a.sql` / `_b.sql` | §19 row 6: concurrent `plugins.fn_upgrade_plugin` calls on the same installation, same target version. Both connections succeeded (row-lock serializes them; the operation is idempotent) — not mutual exclusion, but no corruption/error either. PASS, with this behavior noted explicitly. |
| `33_fixture_orgb.txt` | `scripts/..._fixtures_orgb.sql` | Org B workflow fixtures for row 7. |
| `34_concurrency_r7_conn_A.txt` / `_conn_B.txt` / `_final_state.txt` | `scripts/..._t19r7_a.sql` / `_b.sql` | §19 row 7: concurrent writes from Org A and Org B (different `app.tenant_id`, different `SET ROLE app_api` sessions) racing at the same instant. Both succeeded independently; final-state query confirms exactly 2 rows, correctly isolated by organization/session. PASS. |
| `35_security_row3_row4_appapi_audit.txt` | `scripts/..._test18_row3_4_5_audit.sql` | §18 rows 3-4: `app_api` (via `SET ROLE`) can insert an org-scoped audit event through `audit.fn_insert_audit_event`; a direct bypass `INSERT` straight into `audit.audit_events` is denied (`permission denied for table audit_events`). PASS. |
| `36_security_row5_worker_row13_readonly.txt` | `scripts/..._test18_row5_worker_readonly.sql` | **Superseded initial attempt** at §18 row 5 using `SET ROLE app_worker` from the `postgres` connection. Failed — but not because the feature is broken: `audit.fn_insert_audit_event`'s platform-event check deliberately reads `session_user`, not `current_user`, specifically so `SET ROLE` cannot spoof it (see the function's own inline comment). `SET ROLE` changes `current_user`, not `session_user`, so this attempt exercised the wrong role and is kept here only for transparency, not as evidence of a defect. Superseded by `36b`. |
| `36b_security_row5_worker_direct_auth.txt` | `scripts/..._test18_row5_worker_direct.sql` | §18 row 5, corrected: a genuine password-authenticated `psql -U app_worker` connection (temporary password set/reset around the test, never logged), confirming `session_user = current_user = app_worker`, successfully inserts a platform audit event. PASS. |
| `36c_security_row6_appapi_platform_event_denied.txt` | `scripts/..._test18_row6_api_direct_platform.sql` | §18 row 6 (platform-event variant): genuine `psql -U app_api` connection attempts a platform audit event and is rejected: `audit: caller app_api is not authorized to create platform audit events`. PASS. |
| `37_security_row13_appreadonly_denied.txt` | `scripts/..._test18_row13_readonly.sql` | §18 row 13: genuine `psql -U app_readonly` connection attempts a direct `INSERT` into `audit.audit_events` and is denied (`permission denied for table audit_events`). PASS. |
| `38_count_discrepancy_reconciliation.txt` | ad hoc queries against `pg_constraint`/`information_schema.table_constraints`/`pg_proc` | **Reconciles, not a defect.** Re-running the structural counts this batch produced different numbers for primary keys (259 vs the first batch's 197), unique constraints (142 vs 94), check constraints (558 vs 2,541), and functions (223 vs 219). This file traces the cause exactly: files `12`/`13`/`14` in the first batch queried `information_schema.table_constraints`, which the SQL standard view synthesizes a `CHECK`-type row for every `NOT NULL` column (inflating the check count to 2,541) and folds partition-child constraints into their parent's logical count (197/94); this batch's `12`/`13`/`14`-equivalent counts came from raw `pg_constraint`, which surfaces each partition's own physical constraint row separately (259/142) and only counts genuinely named `CHECK` constraints, not synthesized `NOT NULL` ones (558). Re-running the exact `information_schema.table_constraints` query this batch reproduces `197`/`94`/`2541`/`50` exactly, confirming both figures are correct for what they measure and the schema has not drifted between batches. Function count: `219` (first batch) counted only `prokind='f'` regular functions; `223` (this batch) additionally counted 4 `prokind='a'` aggregate functions — also now exactly reconciled, not a drift. All other structural counts (tables=199, FKs=50, indexes=821, views=2, matviews=0, triggers=105, enums=0, sequences=0, RLS tables=91, policies=103) were spot-checked in this batch's own `09`-`23` runs (kept in scratch, not re-copied here since they are identical to the first batch's `09`/`11`/`15`-`17`/`19`-`23` and would be pure duplication) and match the first batch exactly. |

### New finding surfaced by this batch: `analytics.fn_claim_projection_slot` (migration `068_5J.sql`)

File `32_concurrency_r2_conn_A.txt`/`_conn_B.txt` is **live, reproducible
evidence of a real functional defect** in the frozen migration SQL, not a
test-setup mistake: both concurrent calls to
`analytics.fn_claim_projection_slot(...)` fail with
`ERROR: function gen_random_bytes(integer) does not exist`. Root cause,
confirmed by direct inspection (`\sf`, `SHOW search_path`, `\dx+ pgcrypto`)
in the same session: the function is `SECURITY DEFINER SET search_path =
analytics, pg_catalog` (migration `068_5J.sql`, line 114) — it omits
`public`. Its `INSERT ... VALUES (...)` relies on
`analytics.analytics_projection_events.id`'s column default,
`public.gen_uuid_v7()`, which itself calls pgcrypto's
`gen_random_bytes()` — also in `public`. With `public` outside the
function's restricted search path, that call fails. A repo-wide grep found
this same incomplete-`search_path` pattern (missing `public`) in 24
`SECURITY DEFINER` function definitions across migrations `060`, `061`,
`062`, `063`, `064`, `065`, `068`, `069` (schemas `integrations`,
`webhooks`, `plugins`, `analytics`); only this one function had been
live-confirmed broken at the time this note was first written — since
extended, see immediately below.

### Follow-up: two more of the 24 confirmed broken, 19 confirmed unaffected

`39_defect_confirm_fn_create_plugin_installation.txt` and
`40_defect_confirm_fn_create_integration_connection.txt` are live
confirmation of the same defect in two more of the 24 flagged functions,
in two different schemas — `plugins.fn_create_plugin_installation` and
`integrations.fn_create_integration_connection` both fail with the
identical `gen_random_bytes(integer) does not exist` error, for the
identical reason (their `INSERT`s rely on a `gen_uuid_v7()` column
default while `public` is outside their restricted search path). This
confirms the defect is a systemic pattern, not an isolated one-off.

Of the 24 flagged functions, a mechanical check of every one's body (does
it contain `INSERT INTO`, i.e. could it hit a `gen_uuid_v7()` default)
sorted them into three groups:

1. **Confirmed broken (live-tested):** `analytics.fn_claim_projection_slot`,
   `plugins.fn_create_plugin_installation`,
   `integrations.fn_create_integration_connection`.
2. **Broken by construction (not separately live-tested, but calls a
   function in group 1 as its first action, so fails identically):**
   `analytics.fn_apply_projection_call_metrics`,
   `analytics.fn_apply_projection_call_latency`.
3. **Not affected:** the remaining 19 — all are pure trigger functions
   that only reference `NEW`/`OLD` and never `INSERT`, so they never touch
   `public`. Verified mechanically, not assumed.

See `MIGRATION_RECONCILIATION_REPORT.md` for the full writeup and
BLOCKING/NON-BLOCKING/DEFERRED classification.

### Third batch — grant-conflict root cause + cleanup (2026-08-19, prefix `20260819T081500Z`)

File `27` (second batch, above) already showed the *symptom* live: §18
row 8's `app_platform_admin` direct `INSERT` into
`workflow.workflow_executions` **succeeded** (returned id
`01a018de-5633-7d6e-9bdc-dcb67b1f075e`) instead of being `DENIED` as
`5K-Database-Migration-and-Implementation.md`'s own §18 table expects —
but that file did not yet trace the cause. `41_grant_conflict_041_vs_046_platform_admin_insert.txt`
does: migration `041_5G.sql` deliberately `REVOKE`s `INSERT` on
`workflow.workflow_executions` from `app_platform_admin` (so that
execution rows can only be created via the `SECURITY DEFINER` function
`workflow.fn_start_workflow_execution`, which enforces the
no-double-active-session business rule), but migration `046_5G.sql`, five
files later in the same forward chain, does a blanket
`GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO
app_platform_admin`, silently re-granting `INSERT` back. A live grant
query confirms `app_platform_admin` currently holds `INSERT` on
`workflow.workflow_executions`, and an independent re-run of the direct
`INSERT` succeeded again, confirming file `27`'s result was not a fluke.
No `BEFORE INSERT` trigger or other constraint stands in the way; the
table's only RLS policy enforces tenant scoping, not provenance.

**Cleanup note:** the fixture row inserted during file `27`'s test
(`01a018de-...`) was found still present in the database when this batch
began — it had not been deleted after that earlier test. It has now been
deleted, along with the row this batch's own re-run inserted. No fixture
data remains in the database from either test.

This is a genuine conflict between two already-approved Phase 5G migrations,
not a new design decision — reported here, not silently redesigned. See
`MIGRATION_RECONCILIATION_REPORT.md` for the full writeup and
BLOCKING/NON-BLOCKING/DEFERRED classification.

## Fourth batch — Phase 5K.1 corrective patch (076_5K1) + closure (2026-08-19, prefix `20260819T110500Z`)

Everything above (batches 1-3) is the **DISCOVERED** stage of the audit
chain for the two defects fixed by this batch, and is preserved untouched —
including the original failing runs (`32_concurrency_r2_conn_A.txt`/
`_conn_B.txt` for Defect A, `41_grant_conflict_041_vs_046_platform_admin_insert.txt`
for Defect B). Nothing in batches 1-3 was edited, deleted, or rewritten to
produce this batch.

This batch is the **PATCHED → RETESTED → RESOLVED** stage. A new forward
migration, `migrations/076_5K1.sql` (Alembic revision `076_5K1`, wraps the
frozen SQL via `alembic/versions/076_5K1.py`, `down_revision = "075_5J"`),
fixes both defects with the minimum corrective change per the governing
Phase 5K.1 spec:

- **Defect A** — adds `public` to the `search_path` of the 5 `SECURITY
  DEFINER` functions confirmed broken/broken-by-construction in batch 2
  (`analytics.fn_claim_projection_slot`, `plugins.fn_create_plugin_installation`,
  `integrations.fn_create_integration_connection`,
  `analytics.fn_apply_projection_call_metrics`,
  `analytics.fn_apply_projection_call_latency`) — the other 19 flagged
  functions are pure trigger functions confirmed in batch 2 to never touch
  `public`, and were correctly left unpatched.
- **Defect B** — re-`REVOKE`s `INSERT` on `workflow.workflow_executions`
  (and, via a `pg_inherits`-based dynamic loop, every one of its
  partitions individually — confirmed empirically that `GRANT/REVOKE ...
  ON ALL TABLES IN SCHEMA` touches each partition child, not just the
  parent) from `app_platform_admin`, restoring migration `041_5G.sql`'s
  original intent that migration `046_5G.sql` had silently undone.

All tests were run against freshly recreated, genuinely empty Docker
containers (`5k_validate_pg` / `5k_alembic_runner`), never against a
previously-migrated database, per governing-spec §10. No password,
connection string, or other secret appears in any file in this batch —
each file was grep-scanned for `password|DATABASE_URL|secret|token|apikey`
after being written; one true positive (a local ephemeral test-container
`POSTGRES_PASSWORD`/`DATABASE_URL`, not a real credential) was found in
file `42` and redacted in place.

| File | Command | Purpose |
|---|---|---|
| `42_fresh_docker_env_setup_5K1.txt` | `docker run` × 2 + emptiness checks | Confirms a genuinely empty PostgreSQL 16 database before the 076 upgrade test (governing-spec §10). |
| `43_alembic_upgrade_head_001_to_076_fresh_db.txt` | `alembic upgrade head` | Full 76/76 upgrade log from base through `076_5K1` against the fresh DB. All "Running upgrade" lines present including `075_5J -> 076_5K1`, no errors. |
| `44_alembic_history_heads_current_post076.txt` | `alembic heads` / `current` / `branches` / `history \| grep -c '\->'` | Confirms exactly one head (`076_5K1`), no branches, 76-revision linear history, and a matching 76/76 file count for `migrations/*.sql` and `alembic/versions/*.py`. |
| `45_defectA_searchpath_live_verification_RESOLVED.txt` | live `SELECT`s calling all 5 patched functions directly | Defect A RETESTED/RESOLVED: all 5 previously-broken functions now execute successfully end-to-end (not just catalog inspection), confirming `public.gen_uuid_v7()`/`public.gen_random_bytes()` resolve correctly. |
| `46_defectB_workflow_insert_live_verification_RESOLVED.txt` | direct `INSERT` attempts by `app_api`/`app_worker`/`app_platform_admin`, plus all three via the approved `fn_start_workflow_execution` path, plus the double-active-session invariant | Defect B RETESTED/RESOLVED: `app_platform_admin` direct `INSERT` now denied (was the BLOCKING failure in batch 3); approved-path inserts and the no-double-active invariant remain fully functional for all three roles — confirms the fix did not break legitimate access. |
| `47_security_suite_full_rerun_16of16_PASS.txt` | full re-run of all §18 rows (1-13, plus role-login sub-variants for rows 4/5) | Governing-spec §13: re-run ALL security scenarios, not just the previously-failed one. 16/16 PASS, including row 8 (the original Defect B failure, now denied). |
| `48_concurrency_suite_full_rerun_7of7_PASS.txt` | full re-run of all §19 rows (1-7), genuine two-connection races | Governing-spec §14: re-run ALL concurrency tests, not just the previously-failed one. 7/7 PASS, including row 2 (the original Defect A failure — `analytics.fn_claim_projection_slot` under real concurrency — now passes), with row 6's deliberate-idempotency behavior explicitly documented as a pass, not an anomaly. |
| `49_schema_validation_post076_and_table_count_reconciliation.txt` | post-076 `pg_proc`/`information_schema.role_table_grants`/aggregate-count queries | Governing-spec §15: confirms the 5 patched functions' `search_path` now includes `public`; confirms zero `INSERT` grant rows for `app_platform_admin` on `workflow.workflow_executions` or any partition; confirms all other structural counts unchanged across the 076 upgrade; explicitly reconciles the 197-vs-199 table count as a query-methodology difference between independently-written validation queries (not schema drift), grounded in the fact that `076_5K1.sql` contains zero table DDL. |
| `50_package_hygiene_final_audit.txt` | repo-wide `find` for cache/temp/secret artifacts + full-package secret grep scan | Final §21/§23 closure sweep of the *entire* `5K/` package (not just this batch's files). Found and fixed one NON-BLOCKING housekeeping defect: 76 root-owned `__pycache__`/`.pyc` files left behind by the Dockerized Alembic-runner container across `alembic/` and `alembic/versions/`; cleaned via a throwaway root container bind-mounting the same path (same mechanism that created them, in reverse). Re-verified clean. Full-package `password\|DATABASE_URL\|secret\|token\|apikey` grep scan (not limited to this batch) also re-run and confirmed clean — every match is a schema/column identifier (`api_keys`, `password_hash`, `token_count`, etc.), documentation prose about the *absence* of embedded passwords, or the `DATABASE_URL` environment-variable *name* (never a value) — no real secret anywhere in the package. |

See `../MIGRATION_MANIFEST.md` (row `076_5K1`), `../EXECUTION_REPORT.md`
(Phase 5K.1 section), and the four reports in `../validation/` for the
consolidated result these logs support.

## Fifth batch — Phase 5J.1 live validation closure (2026-08-23, prefix `20260823T061055Z`)

Closes the residual "no live PostgreSQL execution" gap explicitly named in
`../validation/077_5J1_VALIDATION_REPORT.md` §0 (that report was written in a
session with no functional `psql`/Python/Alembic runtime available). This
batch runs against a **local native PostgreSQL 18 server**
(`postgresql-x64-18` Windows service), not a Docker container — no Docker
engine was available in this session. A dedicated, disposable database
(`voice_agent_5j1_validate`) was created and dropped/recreated (twice — see
below) specifically for this batch; the user's own real local Postgres
service was reached with a password the user supplied interactively (never
written to any file in this repo or elsewhere). No password or connection
string appears in any file below.

**Environment note (non-blocking, resolved):** this server initially lacked
the `vector` extension migration `034_5F` requires (unrelated to 5J.1 —
that migration predates it by ~40 revisions). No official Windows pgvector
build exists; after an explicit tradeoff discussion, the user installed
`vector` 0.8.6 themselves (not installed by this session). The first
`voice_agent_5j1_validate` database (created before that point) was dropped
and recreated to guarantee a genuinely empty starting point once the
extension was available — the run recorded below is against that second,
truly fresh database.

| File | Command | Purpose |
|---|---|---|
| `51a_alembic_upgrade_BLOCKED_vector_extension_missing.txt` | `alembic upgrade head` (first attempt, before the `vector` extension was installed) | Preserved for transparency, not a passing result: fails at migration `034_5F` with `extension "vector" is not available` — an environment gap (unrelated to 5J.1) that predates it by ~40 revisions. The database this ran against was dropped and recreated once `vector` was installed; file `51` below is the clean re-run. |
| `51_alembic_pre_and_upgrade_001_to_077_fresh_db.txt` | `alembic current` / `heads` (pre), `alembic upgrade head`, `alembic current` / `heads` (post) | **The critical gate**, and also stands in for Phase 5K's own "fresh-DB 001→077" check (no separate run was done — see report note). Genuinely empty DB (`pg_tables` count = 0, confirmed immediately before), full `001_5B`→`077_5J1` chain, exit code 0, single head `077_5J1` before (as `heads`) and after (as both `current` and `heads`). |
| `52_outbox_table_columns_live.txt` | `to_regclass`, `information_schema.columns` | `audit.domain_event_outbox` exists; exactly 17 columns, all names/types/nullability/defaults matching `077_5J1.sql` exactly. |
| `53_outbox_constraints_indexes_live.txt` | `pg_constraint`, `pg_indexes` | Exactly 7 named `CHECK` constraints + 1 `PRIMARY KEY` (`pk_outbox`) — PostgreSQL 18 additionally surfaces 9 `contype='n'` (not-null) rows per column, a PG18 catalog-representation detail, not an additional CHECK. 4 `CREATE INDEX` statements confirmed live with exact predicate/column definitions matching the migration, plus the implicit unique index backing the PK (5 total `pg_indexes` rows). |
| `54_outbox_functions_security_live.txt` | `pg_proc`/`pg_namespace`/`pg_roles` join, `information_schema.routine_privileges`, `pg_trigger` | All 4 functions (`fn_claim_outbox_events`, `fn_mark_outbox_published`, `fn_mark_outbox_failed`, `fn_outbox_tenant_check`) are `SECURITY DEFINER` with an explicit, non-empty `search_path` (`audit, pg_catalog` or `audit, organization, pg_catalog` for the trigger function) — no bare/implicit `public` regression. `EXECUTE` granted to exactly `app_worker`/`app_platform_admin` on the three callable functions, none to `app_api`, none (beyond owner) on the trigger function. Trigger `trg_outbox_tenant_check` confirmed `BEFORE INSERT`, enabled (`tgenabled='O'`). |
| `55_role_privilege_tests_live.txt` + `55b_role_privilege_app_api_insert_corrected.txt` | `SET ROLE` live tests as `app_api`/`app_worker`/`app_readonly` | `app_api`: INSERT succeeds (plain, no `RETURNING` — see `55b`: `RETURNING`/direct `SELECT` correctly denied too, since `app_api` has INSERT-only, no SELECT, by design, not a defect), UPDATE/DELETE/all three functions correctly denied. `app_worker`: INSERT succeeds, `fn_claim_outbox_events` succeeds, direct UPDATE/DELETE correctly denied (must go through the functions). `app_readonly`: SELECT succeeds, INSERT correctly denied. No `BYPASSRLS` on `app_api`/`app_worker`/`app_readonly` (confirmed via `pg_roles`). |
| `56_atomic_domain_outbox_rollback_commit.txt` | live `BEGIN`/`INSERT`×2/`ROLLBACK` then `BEGIN`/`INSERT`×2/`COMMIT` against `organization.organizations` + `audit.domain_event_outbox` in the same transaction | ROLLBACK: both rows absent afterward. COMMIT: both rows present afterward, then cleaned up. Proves the core transactional-outbox invariant live, not just by construction. |
| `57_event_flow_insert_claim_tests.txt` | live INSERT + `fn_claim_outbox_events` as `app_worker` | `organization.created` and `compliance.policy_activated` events both insert as `PENDING` and are both successfully claimed (→`CLAIMED`) — DEP-6C-16's two required 6C flows are backed live, not just structurally. |
| `58_concurrency_sessionA.txt` / `_sessionB.txt` | two **genuinely overlapping** `psql -f` sessions (A backgrounded: `BEGIN` → claim 10 of 20 seeded rows → `pg_sleep(6)` holding row locks open → `COMMIT`; B started 2s into A's sleep, while A's transaction and locks were still open: `BEGIN` → claim → `COMMIT`, returns immediately, proving `SKIP LOCKED` rather than lock-wait) | **Mandatory two-worker concurrency test.** A and B claimed disjoint sets of exactly 10 rows each (verified programmatically: 0-row intersection, 20-row union, no id returned to both). Real concurrency, not two sequential calls. |
| `59_publish_wrongworker_remark_tests.txt` | `fn_mark_outbox_published` live calls | Correct-worker publish: returns `true`, `status→PUBLISHED`, `published_at` set, claim fields cleared. Wrong-worker publish attempt on another worker's still-claimed row: returns `false`, row unchanged. Re-mark on an already-`PUBLISHED` row: returns `false` (no-op, CAS-guarded on `status='CLAIMED'`). Also covers step 13 (retry/failure): `fn_mark_outbox_failed` before max attempts returns `PENDING`, `available_at` pushed forward ~30s, claim fields cleared, `last_error` populated. |
| `60_max_attempts_failed_state_test.txt` | 9 iterations of claim→fail via `p_next_attempt_at=NOW()` to skip backoff wait | First 9 sub-attempts in the file are a documented test-design correction (see inline note in the file) — they tried to steal a row still within its fresh 300s claim window and were correctly rejected as no-ops, itself a valid confirmation of the "fresh claim not stolen" behavior later re-tested explicitly in `61`. After releasing the row properly: `attempt_count` climbs 1→10 across 9 claim/fail cycles, and at `attempt_count=max_attempts=10` the row transitions to terminal `FAILED`, is no longer returned by `fn_claim_outbox_events`, and remains observable in the table (not dropped). |
| `61_stale_claim_recovery_test.txt` | manual `claimed_at` backdate (`NOW() - 10 minutes`) on one CLAIMED row + live claim call with `claim_timeout_seconds=300` from a new worker, alongside an untouched fresh CLAIMED row as a negative control | Stale (10-min-old) claim reclaimed by the new worker. Fresh (~2-min-old) claim on the control row correctly **not** stolen in the same call. |
| `62_regression_security_suite.txt` | `pg_proc`/`pg_roles`/`information_schema.role_table_grants` queries against the same post-077 fresh DB | Zero `SECURITY DEFINER` functions repo-wide with missing/unsafe `search_path` (077's own 4 included, and no regression in the pre-existing ones). `BYPASSRLS` role list unchanged (`app_migration`, `app_platform_admin`, plus the connecting superuser). Phase 5K.1's Defect B fix still holds (`app_platform_admin` has no `INSERT` on `workflow.workflow_executions`). `audit.audit_events`/`audit.audit_chain` untouched. Aggregate table/function/trigger/index/RLS counts sane (200 tables, 66 non-system-schema functions, 106 triggers, 826 indexes, 91 RLS tables) — 077 added exactly its own 1 table / 4 functions / 1 trigger / 4 explicit indexes on top of the 076 baseline, nothing else moved. |

**Step 17 (Redis integration) explicitly NOT performed and not fabricated:**
no Redis instance and no runnable outbox-publisher application code exist
anywhere in this repository at this stage (it is still a documentation-phase
repo; Phase 6D/implementation has not started). Per the governing task's own
instruction, this is recorded as N/A rather than a fabricated PASS: DB
outbox persistence and claiming semantics are LIVE VERIFIED (above); Redis
publisher *application* integration is out of this migration's scope until
that implementation exists.

**No SQL was modified.** Every live test passed against `077_5J1.sql` and
`077_5J1.py` exactly as already committed — `sha256sum` reconfirms the file
unchanged (`eac7022c...4a990`, 15559 bytes, matching `MIGRATION_MANIFEST.md`
row 077 byte-for-byte). All test fixture rows were deleted from the
validation database after use; the validation database itself
(`voice_agent_5j1_validate`) is disposable, separate from any shared/dev
database, and was left empty at the end of this batch.

See `../validation/077_5J1_VALIDATION_REPORT.md` (updated by this batch) and
`../MIGRATION_MANIFEST.md` row `077` for the consolidated result.

## Sixth batch — Phase 6H Final Blocker Remediation, PostgreSQL 16 live validation (2026-08-28, prefix `20260828T143000Z`)

Everything above (batches 1-5) validated 098_5E1/099_5C1 (or their
predecessor rows) against local PostgreSQL 18. This batch re-validates the
Final Blocker Remediation rewrite of `098_5E1.sql`/`099_5C1.sql` — the
provider-submission-boundary (`SUBMITTING`) state machine, the removal of
direct `INSERT` grants on `campaign.campaign_contact_identities` and
`voice.call_dispatch_keys`, and the tenant/payload-fingerprint validation
added to `voice.fn_initiate_outbound_call_idempotent()` — against a
**genuinely separate, disposable PostgreSQL 16.10 instance**, since the
declared production baseline is PostgreSQL 16, not 18. No Docker engine is
available in this environment (confirmed again in this pass); PostgreSQL
16.10 was instead installed as a standalone, service-free binary
distribution (EDB's `postgresql-16.10-1-windows-x64-binaries.zip`,
downloaded directly from `get.enterprisedb.com`, no admin/service
registration required, unlike the full GUI installer which this pass tried
first and which genuinely failed with "the requested operation requires
elevation" — captured, not worked around by assuming success) at
`C:\Users\Dell\pgval16`, `initdb`'d fresh, and started on port `5433`
(the existing PostgreSQL 18 instance on `5432` was never touched). `vector`
was not bundled in the binaries-only zip; it was built from `pgvector`
source tag `v0.8.0` against this PG16 instance's own headers/import libs
using the Visual Studio 18 (MSVC 14.51) toolchain already present on this
machine, installed, and loaded — `CREATE EXTENSION vector` confirmed live,
alongside `pgcrypto` and `pg_stat_statements`, all three required
extensions. Both the PG16 install tree and its data directory were removed
at the end of this batch (see closing note below) — nothing was left
running.

| File | Command | Purpose |
|---|---|---|
| `63_pg16_fresh_upgrade_001_to_099.txt` | `alembic upgrade head` against a genuinely empty, freshly created `voice_agent_pg16_fresh` database | **Critical gate.** Full `001_5B → … → 099_5C1` chain on PostgreSQL 16.10, exit code 0. |
| `64_pg16_alembic_heads.txt` | `alembic heads` | Confirms exactly one head, `099_5C1`. |
| `65_pg16_alembic_current.txt` | `alembic current` | Confirms current == head (`099_5C1`). |
| `66_pg16_incremental_upgrade_to_097.txt` | `alembic upgrade 097_5D5` against a second fresh database | Pins a separate database at the pre-remediation baseline, mirroring a real "existing deployment" starting point. |
| `67_pg16_incremental_upgrade_097_to_head.txt` | `alembic upgrade head` on that same, now-pinned database | `097_5D5 → 098_5E1 → 099_5C1`, exit code 0 — the genuine incremental-apply path, not a second fresh-DB run relabeled. |
| `68_fixture_setup.sql` | fixture script | Two organizations, two users, three campaigns (one deliberately paused mid-run for the Pause-regression test), two CRM contacts, one Voice agent/agent version/tenant phone number — run once against `voice_agent_pg16_fresh` before every functional/security test below. |
| `69_privilege_and_dispatch_state_machine_tests.txt` | ~30 sequential `psql` statements, `SET ROLE app_worker` / `SET ROLE app_api` for genuine role-boundary enforcement (trust auth, no passwords needed for these roles) | The core functional/security suite for this pass — see the Results table below for what each block proves. |
| `70_reserve_dispatch_tests.sql` | `campaign.fn_reserve_dispatch()` regression suite (concatenation of two scripts; the first attempt's cross-campaign fixture was accidentally reused from a campaign this same run had just paused, which the second script corrects with a fresh `RUNNING` campaign — the mistake and its correction are both preserved here rather than silently rewritten) | Confirms the pre-existing campaign_id-ownership guard (fixed in the prior remediation pass, unmodified by this one) still rejects a genuine cross-campaign mismatch on PostgreSQL 16, and that a correctly-scoped reservation still succeeds. |
| `71_voice_dispatch_claim_concurrency_race.txt` | two genuinely concurrent `psql` processes, both gated by an identical `pg_sleep(2)` start signal, both calling `voice.fn_claim_dispatch_for_provider_submission()` on the SAME `RESERVED` dispatch key | **INV-VOICE-DISPATCH-02 live proof.** Exactly one connection returns `claimed=t`; the other returns `claimed=f, reason=NOT_CLAIMABLE_CLAIMED` — real concurrent contention, not simulated sequentially. |
| `72_campaign_enqueue_concurrency_race.txt` | two genuinely concurrent `psql` processes racing `campaign.fn_enqueue_contact()` on the identical `(campaign_id, contact_id)` pair | Regression check (unmodified logic this pass): exactly one `is_new=t`, the other `is_new=f` with the identical `campaign_contact_id` — zero duplicates on PostgreSQL 16. |
| `73_pause_vs_reservation_race.txt` | one connection attempting to hold a `campaigns` row lock (see note below) then calling `fn_reserve_dispatch()`, racing a concurrent `UPDATE campaigns SET status='PAUSED'` | Regression check, Pause-committed-first ordering: `fn_reserve_dispatch()` correctly returns `CAMPAIGN_NOT_RUNNING` once Pause has applied. **Caveat, disclosed rather than hidden:** this file's own diagnostic `SELECT ... FOR UPDATE` probe (run as `app_worker`, no `app.tenant_id` set) was itself silently filtered to zero rows by RLS before it could acquire anything, so it did not actually hold the lock it was intended to hold — the Pause `UPDATE` proceeded immediately rather than blocking. The *correctness* outcome (Pause-first is honored) is still genuinely proven; the specific lock-wait-duration timing artifact from the prior PostgreSQL 18 pass (§49.7 of `6H-Campaign-APIs.md`, ~1.5s measured blocking) was not re-derived here because `fn_reserve_dispatch()`'s locking logic was not touched by this remediation pass — see `PG16_MIGRATION_VALIDATION_REPORT.md` for the full accounting of what this batch did and did not re-prove. |

**Results summary** (full transcript in file `69`, referenced by line range in `docs/phase-05-database-design/5K/validation/VOICE_DISPATCH_VALIDATION_REPORT.md`): direct `INSERT` denied for `app_worker` on `campaign.campaign_contact_identities` and for both `app_worker`/`app_api` on `voice.call_dispatch_keys`; every guarded function still succeeds for its intended role; a same-tenant/same-payload replay returns the original call session (`REPLAYED`); a same-key/different-payload replay returns `IDEMPOTENCY_KEY_REUSE_MISMATCH` with no session identity disclosed; a same-key cross-tenant replay raises a non-disclosing exception; a `CLAIMED` row whose lease expires before `fn_begin_provider_submission()` is ever called is safely re-claimed (Case A); a `SUBMITTING` row whose lease expires is **provably not** re-claimable (`NOT_CLAIMABLE_SUBMITTING`) even though nothing else has touched it — **the direct empirical closure of Blocker A / the original P0 double-dial defect**; the same worker's own later `fn_begin_provider_submission()` call also fails closed (`NOT_CLAIM_HOLDER`) once its lease has lapsed; a stuck `SUBMITTING` row is successfully resolved by `fn_reconcile_dispatch_outcome()` (identity-correlated, not lease-owner-correlated) to `CONFIRMED`; a stuck `AMBIGUOUS` row is resolved by the same function to `FAILED` and is then genuinely re-claimable; a `SUBMITTING` row that receives a definite pre-acceptance rejection via `fn_record_dispatch_failed()` is also re-claimable; `pg_proc`/`has_function_privilege` inspection confirms all 11 `SECURITY DEFINER` functions touched by 098/099 (3 `campaign.fn_*` + 8 `voice.fn_*`) carry the documented minimal `search_path` and `PUBLIC` cannot `EXECUTE` any of them; the final table-grant matrix for both hardened tables shows no role holds `INSERT`/`UPDATE`/`DELETE` except `app_platform_admin` and `postgres`; the function count for `voice.fn_*` is confirmed as exactly `8` by direct count, not asserted from memory.

**No SQL was modified by this batch** — every test ran against `098_5E1.sql`/`099_5C1.sql` exactly as committed for this remediation pass; `sha256sum`/`wc -c` were re-run after this batch to confirm the files on disk still match `MIGRATION_MANIFEST.md`'s recorded checksums (they do, since this batch made no further edits after the SQL was written).

**Cleanup performed at the end of this batch:** the PG16 server process was stopped (`pg_ctl stop`); the entire `C:\Users\Dell\pgval16` tree (binaries, data directory, pgvector source/build artifacts, the two validation databases it contained) was deleted; the throwaway `uv`-managed Python virtual environment (`docs/phase-05-database-design/5K/.venv_validation_pg16`) and any `__pycache__` directories it created were removed. The pre-existing PostgreSQL 18 instance and its own databases were never touched by this batch.

See `../validation/PG16_MIGRATION_VALIDATION_REPORT.md`,
`../validation/VOICE_DISPATCH_VALIDATION_REPORT.md`,
`../validation/CAMPAIGN_PRIVILEGE_VALIDATION_REPORT.md`, and
`../MIGRATION_MANIFEST.md`'s Final Blocker Remediation entry for the
consolidated results.

## Seventh batch — Phase 6H Final Micro-Remediation, reconciliation authorization boundary (2026-08-28, prefix `20260828T210000Z`)

Closes the one remaining item the prior (sixth) batch's own review found:
`voice.fn_reconcile_dispatch_outcome()`'s `EXECUTE` grant was too broad
(`app_api`, `app_worker`) for a function that can convert an `AMBIGUOUS`
provider submission into `FAILED` — the one transition that re-opens
eligibility for a fresh physical telephony attempt. A completely fresh,
disposable PostgreSQL 16.10 instance was built the same way as the sixth
batch (binaries-only distribution on port 5433, `pgvector` built from
source via the local MSVC toolchain) — the sixth batch's own instance had
already been torn down and removed per its own documented cleanup, so this
is a genuinely new, independent instance, not a reused one.

| File | Command | Purpose |
|---|---|---|
| `74_final_pg16_fresh_upgrade.txt` | `alembic upgrade head` on a genuinely empty `voice_agent_pg16_fresh2` | Fresh-DB gate for the reconciliation-authorization-hardened `099_5C1.sql` — `001_5B → … → 099_5C1`, exit code 0. |
| `75_final_alembic_heads.txt` / `76_final_alembic_current.txt` | `alembic heads` / `alembic current` | Single head `099_5C1`, current == head. |
| `77_final_pg16_incremental_upgrade_to_097.txt` / `78_final_pg16_incremental_upgrade_097_to_head.txt` | `alembic upgrade 097_5D5` then `alembic upgrade head` on a second, separately created database | Genuine incremental-apply path, exit code 0 both steps. |
| `79_final_reconciliation_fixture_setup.sql` | fixture script | One organization pair, one Voice agent/agent version/tenant phone number — the minimal fixture this pass's tests needed (no campaign fixtures — this pass touches only `voice.*` and does not modify anything Campaign-side). |
| `80_final_reconciliation_tests.sql` / `81_final_reconciliation_privilege_and_provenance_output.txt` | ~20 sequential `psql` statements, `SET ROLE app_api` / `SET ROLE app_worker` / `SET ROLE app_voice_reconciler` for genuine role-boundary enforcement | The core test suite for this pass — see the Results summary below. |
| `82_final_regression_tests.sql` / `83_final_regression_output.txt` | Re-run of the sixth batch's own crash-recovery and idempotency scenarios | Confirms this pass's changes (entirely inside `fn_reconcile_dispatch_outcome()` plus one new role) did not regress anything the sixth batch already proved. |

**Results summary** (full transcript in file `81`): direct execution of `voice.fn_reconcile_dispatch_outcome()` as `app_api` fails with `permission denied for function fn_reconcile_dispatch_outcome`; the identical attempt as `app_worker` fails identically; a forged `p_reconciled_by = 'admin'` argument from `app_api` still fails at the same permission check, before the function body ever runs, proving the parameter carries no authorization weight; the dispatch row targeted by all three denied attempts remains `AMBIGUOUS`, untouched. The new `app_voice_reconciler` role (created `LOGIN`, `rolbypassrls = false`, confirmed live) successfully resolves an `AMBIGUOUS` row to `CONFIRMED` (with `provider_call_ref`, `reconciliation_source = 'PROVIDER_CALLBACK'`, `reconciled_by`, `reconciled_at` all persisted) and a separate `AMBIGUOUS` row to `FAILED` (`reconciliation_source = 'PROVIDER_LOOKUP'`), after which a fresh claim of that now-`FAILED` row genuinely succeeds — proving `FAILED` reconciliation really does reopen physical retry eligibility, exactly as designed. Two attempts to reconcile a third `AMBIGUOUS` row to `FAILED` with no evidence (empty string, then `NULL`) are both rejected with `p_note (evidence description) is required when p_outcome = FAILED`, even under the authorized role — the row remains `AMBIGUOUS`. An attempt by the authorized role to reconcile an already-`CONFIRMED` row to `FAILED` returns `reconciled=false, reason=NOT_RECONCILABLE_OR_NOT_FOUND` — the row remains `CONFIRMED`; no path reopens a known-accepted call. A cross-tenant attempt (Org B, authorized role, targeting an Org A dispatch key) is likewise refused non-disclosingly, with the target row's `organization_id` and state both confirmed unchanged afterward. A durable `VOICE_DISPATCH_RECONCILED` audit event (via `audit.fn_insert_audit_event()`, the sole legal write path) is confirmed present for both successful reconciliations, with the correct `actor_type` (`WORKER` for the two provider-driven sources tested), `actor_name`, `resource_id`, and a PII-free `resource_snapshot` recording the old/new state and reconciliation source. `has_function_privilege()` across all six `app_*` roles confirms exactly `app_voice_reconciler` and `app_platform_admin` can `EXECUTE` this function; `app_api`, `app_worker`, `app_readonly`, and `app_migration` cannot. All regression scenarios in files `82`/`83` (expired-`CLAIMED`-before-`SUBMITTING` recovery, the `SUBMITTING` hard-stop, same-key/same-payload replay, same-key/different-payload mismatch, cross-tenant `fn_initiate_outbound_call_idempotent()` denial) reproduce the sixth batch's own results unchanged.

**One test-script artifact, disclosed rather than hidden:** two follow-up diagnostic `SELECT`s against `voice.call_dispatch_keys` issued while still `SET ROLE app_voice_reconciler` (lines 111/122 of the raw transcript) failed with `permission denied for table call_dispatch_keys` — not a defect, but direct confirmation that `app_voice_reconciler` was granted no privilege on this table beyond `EXECUTE` on the one function, exactly as intended (true least privilege, not merely "narrow enough"). The provenance data these two queries were meant to show was instead confirmed via a later, equivalent query run as the superuser test session (file `81`, "TEST 24").

**No SQL outside `099_5C1.sql` was modified by this batch.** `sha256sum`/`wc -c` were re-run after this batch and match `MIGRATION_MANIFEST.md`'s updated entry.

**Cleanup performed at the end of this batch:** the PG16 server was stopped; the entire `C:\Users\Dell\pgval16b` tree was deleted; the throwaway `.venv_validation_pg16b` virtual environment and any `__pycache__` directories were removed. No pre-existing PostgreSQL instance was touched.

See `../validation/VOICE_DISPATCH_VALIDATION_REPORT.md` (updated by this
batch) and `../MIGRATION_MANIFEST.md`'s Final Micro-Remediation entry for
the consolidated result.

## Eighth batch — Phase 6H Final Micro-Fix, non-forgeable reconciliation provenance (2026-08-28, prefix `20260828T231500Z`)

Closes the one remaining item the prior (seventh) batch's own review found:
`voice.fn_reconcile_dispatch_outcome()` correctly restricted WHO could call
reconciliation (`app_voice_reconciler`/`app_platform_admin` only) but still
let either authorized caller freely choose WHICH provenance category
(`PROVIDER_CALLBACK`/`PROVIDER_LOOKUP`/`OPERATOR`) to record via a plain
parameter — an audit-integrity defect: the automated reconciler could
falsely record itself as an operator decision, or vice versa. A third
fresh, disposable PostgreSQL 16.10 instance was built the same way as the
sixth and seventh batches (both of which had already been torn down per
their own documented cleanup) — a genuinely new, independent instance.

| File | Command | Purpose |
|---|---|---|
| `84_final_pg16_fresh_upgrade.txt` | `alembic upgrade head` on a genuinely empty `voice_agent_pg16_fresh3` | Fresh-DB gate for the split reconciliation functions — `001_5B → … → 099_5C1`, exit code 0. |
| `85_final_alembic_heads.txt` / `86_final_alembic_current.txt` | `alembic heads` / `alembic current` | Single head `099_5C1`, current == head. |
| `87_final_pg16_incremental_upgrade_to_097.txt` / `88_final_pg16_incremental_upgrade_097_to_head.txt` | `alembic upgrade 097_5D5` then `alembic upgrade head` on a second, separately created database | Genuine incremental-apply path, exit code 0 both steps. |
| `89_final_provenance_fixture_setup.sql` | fixture script | One organization pair, one Voice agent/agent version/tenant phone number — no campaign fixtures (this pass touches only `voice.*`). |
| `90_final_provenance_tests.sql` / `91_final_provenance_output.txt` | ~30 sequential `psql` statements, `SET ROLE app_api` / `app_worker` / `app_voice_reconciler` / `app_platform_admin` for genuine role-boundary and forgery-attempt testing | The core test suite for this pass — see the Results summary below. |
| `92_final_regression_tests.sql` / `93_final_regression_output.txt` | Re-run of the sixth/seventh batches' own crash-recovery and idempotency scenarios | Confirms this pass's changes (splitting one function into three, no change to any other function) did not regress anything previously proven. |

**Results summary, the critical proof (full transcript in file `91`):** `app_api` and `app_worker` are denied `permission denied` on *both* new functions (`fn_reconcile_dispatch_from_provider`/`fn_reconcile_dispatch_by_operator`), unchanged from the prior pass. **The forgery tests, new this pass:** `app_voice_reconciler` (holding genuine `EXECUTE` on the provider function) attempting to call `fn_reconcile_dispatch_by_operator` at all is refused at the privilege layer (`permission denied for function fn_reconcile_dispatch_by_operator`) — it has no grant on that function, period. More importantly, `app_voice_reconciler` calling the function it *does* have `EXECUTE` on, `fn_reconcile_dispatch_from_provider`, while passing `p_provider_source = 'OPERATOR'`, is rejected by the **function's own internal `CHECK`** (`invalid p_provider_source OPERATOR -- only PROVIDER_CALLBACK or PROVIDER_LOOKUP may be recorded through this capability`) — proving the restriction is enforced by the function body itself, not merely by which grant happens to exist. Symmetrically, `app_platform_admin` attempting `fn_reconcile_dispatch_from_provider` at all is refused at the privilege layer — it holds no grant on that function; `fn_reconcile_dispatch_by_operator` takes no source parameter whatsoever, so there is no way for an operator call to request provider provenance even in principle. Genuine reconciliation via each path succeeds and persists the correct, function-determined provenance: the provider-callback path records `reconciliation_source='PROVIDER_CALLBACK'`/`actor_type='WORKER'`; the provider-lookup path (`FAILED`) records `'PROVIDER_LOOKUP'`/`'WORKER'` and the row becomes genuinely re-claimable afterward; the operator path records `'OPERATOR'`/`actor_type='PLATFORM_ADMIN'` regardless of caller input, for both a `CONFIRMED` and a (evidence-backed) `FAILED` outcome. The operator path's `FAILED` branch was also confirmed to require non-empty evidence, identically to the provider path (both route through the same shared internal evidence check) — an empty-string and a `NULL` note were both rejected before a call with real evidence succeeded. `CONFIRMED → FAILED` was attempted through *both* functions against an already-`CONFIRMED` row and refused both times (`NOT_RECONCILABLE_OR_NOT_FOUND`, row unchanged). A cross-tenant attempt was made through *both* functions and refused both times, non-disclosingly, with the target row's `organization_id`/state confirmed unchanged. Direct query against `audit.audit_events` confirms all four successful reconciliations in this pass recorded the correct `actor_type` (`WORKER` ×2, `PLATFORM_ADMIN` ×2) matching the function actually called, never a caller-suppliable value. `has_function_privilege()` across all 6 roles for both new functions confirms exactly the intended 1:1 role-to-function mapping: `app_voice_reconciler` → `fn_reconcile_dispatch_from_provider` only; `app_platform_admin` → `fn_reconcile_dispatch_by_operator` only; every other role, `false` for both.

**Regression, unchanged (file `93`):** expired-`CLAIMED`-before-`SUBMITTING` recovery, the `SUBMITTING` hard-stop, same-key/same-payload replay, same-key/different-payload mismatch, same-key cross-tenant denial, and the synchronous `fn_record_dispatch_ambiguous()` path were all re-run and reproduced identical results — none of that logic was touched by this pass (only `fn_reconcile_dispatch_outcome()` was split into three functions; every other function's body is byte-for-byte the same as the prior pass).

**One client-side artifact, disclosed:** a `psql` `\echo` line in the test script containing an unbalanced quote inside a long comment caused a harmless "unterminated quoted string" parser message (line 138 of file `91`) before the very next line's actual SQL statement executed and produced the correct, expected exception — a test-script formatting issue, not a database or application defect.

**No SQL outside `099_5C1.sql` was modified by this batch.** `sha256sum`/`wc -c` were re-run after this batch and match `MIGRATION_MANIFEST.md`'s updated entry.

**Cleanup performed at the end of this batch:** the PG16 server was stopped; the entire `C:\Users\Dell\pgval16c` tree was deleted; the throwaway `.venv_validation_pg16c` virtual environment and any `__pycache__` directories were removed. No pre-existing PostgreSQL instance was touched.

See `../validation/VOICE_DISPATCH_VALIDATION_REPORT.md` (updated by this
batch) and `../MIGRATION_MANIFEST.md`'s Final Micro-Fix entry for the
consolidated result.

## Ninth batch — Phase 6H Final Admin-DML Hardening (2026-08-29, prefix `20260829T003700Z`)

Closes the one remaining item the prior (eighth) batch's own review found:
`app_platform_admin` still held direct `INSERT`/`UPDATE`/`DELETE` on
`voice.call_dispatch_keys` — a table-level grant that predated every
prior remediation pass and was never touched by any of them, since each
one restricted a *different* role (`app_api`, `app_worker`,
`app_voice_reconciler`). That grant could bypass every invariant built on
top of it: `CONFIRMED` immutability, the `SUBMITTING`/`AMBIGUOUS` hard
stops, and the freshly-established provider/operator provenance split, via
one raw `UPDATE` statement none of the guarded functions ever see. The
identical grant on `campaign.campaign_contact_identities` was inspected and
found to have no legitimate use case either, and was closed the same way.
A fourth fresh, disposable PostgreSQL 16.10 instance was built the same way
as the sixth/seventh/eighth batches (all three already torn down) — a
genuinely new, independent instance. The download attempt for this batch's
own binaries zip was truncated on the first try (11.9 MB instead of ~322
MB, a transient network issue) — disclosed and re-downloaded to completion
before proceeding, not silently retried and assumed fine.

| File | Command | Purpose |
|---|---|---|
| `94_final_pg16_fresh_upgrade.txt` | `alembic upgrade head` on a genuinely empty `voice_agent_pg16_fresh4` | Fresh-DB gate for the admin-DML-hardened `098_5E1.sql`/`099_5C1.sql` — `001_5B → … → 099_5C1`, exit code 0. |
| `95_final_alembic_heads.txt` / `96_final_alembic_current.txt` | `alembic heads` / `alembic current` | Single head `099_5C1`, current == head. |
| `97_final_pg16_incremental_upgrade_to_097.txt` / `98_final_pg16_incremental_upgrade_097_to_head.txt` | `alembic upgrade 097_5D5` then `alembic upgrade head` on a second, separately created database | Genuine incremental-apply path, exit code 0 both steps. |
| `99_final_admin_dml_fixture_setup.sql` | fixture script | One organization pair, one Voice agent/agent version/tenant phone number. |
| `100_final_admin_dml_tests.sql` / `101_final_admin_dml_output.txt` | ~25 sequential `psql` statements, `SET ROLE app_platform_admin` / `app_api` / `app_worker` / `app_voice_reconciler` for genuine role-boundary DML denial testing, plus two catalog queries against `information_schema.role_table_grants` | The core test suite for this pass — see the Results summary below. This run produced **zero parser artifacts** (the prior batch's harmless `\echo`-quoting glitch was specifically avoided by rewriting the affected test's prose, per this pass's own instruction to fix and cleanly rerun rather than merely delete the error line). |
| `102_final_regression_tests.sql` / `103_final_regression_output.txt` | Re-run of the sixth/seventh/eighth batches' own crash-recovery, hard-stop, and idempotency scenarios | Confirms this pass's changes (removing two `GRANT` clauses; no function body touched) did not regress anything previously proven. |

**Results summary, clean and complete (full transcript in file `101`):** direct catalog inspection (`information_schema.role_table_grants`) confirms, **before any test executes**, that `app_api`, `app_worker`, `app_readonly`, and `app_platform_admin` all hold `SELECT` only on both `voice.call_dispatch_keys` and `campaign.campaign_contact_identities` — no role except the table owner (`postgres`, standing in for `app_migration` in this validation instance) holds `INSERT`/`UPDATE`/`DELETE` on either. `app_platform_admin` successfully reads a `CONFIRMED` row (`SELECT` retained, as designed) but is denied with `permission denied for table call_dispatch_keys` on direct `INSERT`, direct `UPDATE` (targeting a live `AMBIGUOUS` row), direct `DELETE`, and — the specific forgery test — a direct `UPDATE` attempting to set `reconciliation_source = 'PROVIDER_CALLBACK'` on a row it never reconciled through the provider path. A direct `UPDATE` attempting to reopen an already-`CONFIRMED` row to `FAILED` is likewise denied at the privilege layer, and the row's `dispatch_state` is confirmed unchanged afterward by a follow-up read. The analogous direct `INSERT` into `campaign.campaign_contact_identities` as `app_platform_admin` is also denied. Critically, removing these grants does **not** impair the legitimate guarded paths: `app_platform_admin` calling `fn_reconcile_dispatch_by_operator()` on a genuine `AMBIGUOUS` row with real evidence succeeds, correctly recording `reconciliation_source='OPERATOR'`; the same function called against an already-`CONFIRMED` row returns `reconciled=false` (`NOT_RECONCILABLE_OR_NOT_FOUND`), proving immutability holds through the guarded path independently of the privilege fix; `app_voice_reconciler` calling `fn_reconcile_dispatch_from_provider()` on a genuine `AMBIGUOUS` row succeeds identically. `app_api`, `app_worker`, and `app_voice_reconciler` were all re-confirmed denied on direct `INSERT`/`UPDATE` against `voice.call_dispatch_keys` — unchanged regressions from prior batches. The final `has_table_privilege()` matrix across all 6 roles for both tables shows `SELECT=true` for `app_api`/`app_worker`/`app_readonly`/`app_platform_admin`, `false` for `app_voice_reconciler` (which was never granted table-level access at all, consistent with its true-least-privilege design — only `EXECUTE` on one function), and `INSERT`/`UPDATE`/`DELETE=false` for every one of the 6 roles on both tables.

**Regression, unchanged (file `103`):** expired-`CLAIMED`-before-`SUBMITTING` recovery, the `SUBMITTING` hard-stop, the `AMBIGUOUS` hard-stop, same-key/same-payload replay, same-key/different-payload mismatch, and same-key cross-tenant denial were all re-run on this pass's own instance and reproduced identical results — this pass's changes touched only two `GRANT` statements, no function body.

**No function body was modified by this batch** — only the `GRANT`/`REVOKE` statements on both tables changed. `sha256sum`/`wc -c` were re-run after this batch and match `MIGRATION_MANIFEST.md`'s updated entries for both `098_5E1.sql` and `099_5C1.sql`.

**Cleanup performed at the end of this batch:** the PG16 server was stopped; the entire `C:\Users\Dell\pgval16d` tree was deleted; the throwaway `.venv_validation_pg16d` virtual environment and any `__pycache__` directories were removed. No pre-existing PostgreSQL instance was touched.

See `../validation/VOICE_DISPATCH_VALIDATION_REPORT.md` and
`../validation/CAMPAIGN_PRIVILEGE_VALIDATION_REPORT.md` (both updated by
this batch) and `../MIGRATION_MANIFEST.md`'s Final Admin-DML Hardening
entry for the consolidated result.

---

## Phase 6K FINAL Blocker Remediation (2026-08-30) — `102_5H2.sql`, PostgreSQL 18 live-validated

New migration (not an in-place amendment of any existing file — `102_5H2`
is the next revision after `101_5I1`, the confirmed head at the time this
batch started). Adds Commercial Pricing Agreement persistence (the
confirmed Phase 5H schema gap 6K's client-specific-pricing business
requirement needs), fixes a confirmed blocking defect in the frozen
`billing.payment_attempts.provider_transaction_id NOT NULL` column
(055_5H.sql), adds a durable atomically-deduplicated inbound
payment-webhook receipt table, and adds late-usage adjustment provenance
columns — full rationale and design in
`docs/phase-06-api-design/6K-Billing-Usage-APIs.md` and
`../validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`.

A genuinely fresh, disposable local PostgreSQL 18.6 instance was built for
this batch (`.tmp_pgdata_6k`, port 5559, `initdb` from this machine's own
`C:\Program Files\PostgreSQL\18`, no unix-socket directory — Windows
builds use TCP loopback only), stopped and its data directory deleted at
the end of the batch (gitignored `.tmp_pgdata_*` pattern, never committed).
Alembic integration used the pre-existing validated virtual environment at
`/tmp/5j1_validate_venv` (Python 3.13.15, `alembic` 1.19.1, `psycopg2-binary`
2.9.12, `SQLAlchemy` 2.0.52 — the same environment prior batches' own
validation passes used).

| File | Command | Purpose |
|---|---|---|
| `20260830T020000Z_07_fresh_upgrade_001_to_102_full.txt` | `alembic upgrade head` on a genuinely empty `voice_agent_6k_fresh2` | Fresh-DB gate, `001_5B → … → 102_5H2`, exit code 0, single head. |
| `20260830T020000Z_08_fresh_current_after_102.txt` | `alembic current` | `102_5H2 (head)` — current == head. |
| `20260830T020000Z_09_history_full_chain.txt` | `alembic history` | 102 lines, single linear chain, no branch. |
| `20260830T020000Z_04_incremental_pin_101.txt` / `20260830T020000Z_05_incremental_apply_102.txt` | `alembic upgrade 101_5I1` then `alembic upgrade 102_5H2` on a second, separately created database (`voice_agent_6k_incr`) | Genuine incremental-apply path, exit code 0 both steps, final state `102_5H2 (head)`. |
| `20260830T020000Z_06_heads_after_102.txt` | `alembic heads` | Single head, `102_5H2`. |
| `20260830T020000Z_01_6k_test_matrix_full_output.txt` | 25-test `psql` script (`6k_test_matrix.sql`) — commercial-pricing lifecycle/immutability/RLS/composite-FK, payment-attempt NOT-NULL fix, payment-webhook-receipt dedup/state-machine, usage-idempotency collision (reproduced, then fixed), quota-semantics, late-usage-adjustment provenance, invoice-line-provenance CHECK | The core functional/security/adversarial test suite for this pass — see Results summary below. Two test-harness bugs (a forgotten `SET app.tenant_id` context switch for Org B in two sub-tests) were found and fixed, not silently left in the evidence — re-run separately in file `02`. |
| `20260830T020000Z_02_6k_test_matrix_fixups_output.txt` | Corrected re-run of the two affected sub-tests, plus a full table/function grant and RLS audit (`aclexplode`/`has_table_privilege`/`has_function_privilege`) | Clean evidence for cross-org composite-FK rejection, future-first-version activation, the complete `SECURITY DEFINER` inventory for every new function, table-grant audit for all four new tables, and RLS enabled+forced confirmation. |
| `20260830T020000Z_03_6k_composite_fk_admin_path_output.txt` | One targeted `psql` statement as `app_platform_admin` (`BYPASSRLS`) | Proves the composite FK (`fk_bp_cpav`) — not merely RLS-inside-the-consistency-trigger — independently rejects a cross-org pin even when RLS itself is bypassed by an admin role: two-layer defense, both layers live-confirmed. |

**Results summary, clean and complete:** Fresh and incremental migration both `PASS`, exit 0, single head, `current == head`, linear 102-entry history. Every new table (`commercial_pricing_agreements`, `...agreement_versions`, `...metrics`) carries `ENABLE + FORCE ROW LEVEL SECURITY`; `payment_webhook_receipts` deliberately carries none, matching `audit.domain_event_outbox`'s own precedent (5J §077) — live-confirmed via `pg_class.relrowsecurity`/`relforcerowsecurity`. `app_api` holds `SELECT`-only on all three pricing tables and `SELECT`+`INSERT`-only on `payment_webhook_receipts` — no `INSERT`/`UPDATE`/`DELETE` beyond that anywhere, confirmed via direct `has_table_privilege()` queries, not assumed from the DDL text. All 7 new `SECURITY DEFINER` functions confirmed `PUBLIC EXECUTE = false`, `app_api EXECUTE = false`, `app_worker/app_platform_admin EXECUTE = true` — the 4 new plain trigger functions confirmed `EXECUTE = false` for every role (never meant to be called directly). `payment_attempts` direct `UPDATE` reconfirmed denied for both `app_api` and `app_worker` (unchanged 055_5H `REVOKE`) — the new `fn_link_payment_provider_transaction()` is the only path linking a provider transaction id post-hoc, exactly matching the corrected payment-transaction-boundary design (local `INITIATED` row created and committed *before* any provider call, `provider_transaction_id` populated only afterward, via a short follow-up transaction).

**Adversarial/functional results, one by one:** `app_api` denied both `fn_create_commercial_pricing_agreement()` (`EXECUTE`) and a direct `INSERT` into `commercial_pricing_agreements`. `app_worker`'s legitimate create → draft-version → activate path succeeds end to end. `app_api` (`SELECT`-only) and even `app_platform_admin` (full grant, but trigger-guarded) are both denied rewriting a financial field on an `ACTIVE` version — the DB-level trigger (`fn_cpav_immutability`), not merely the grant, is what stops the admin role, live-proven by attempting the mutation as `app_platform_admin` directly. A `commercial_pricing_metrics` row cannot be `INSERT`ed, `UPDATE`d, or `DELETE`d once its parent version is `ACTIVE` — all three verbs tested individually, all three rejected. `commercial_pricing_agreements.organization_id` is confirmed immutable even for `app_platform_admin`. A future-dated (`2099-01-01`) renegotiated version is correctly **refused** activation while a prior version is still `ACTIVE` (no premature-supersede gap) — the prior version confirmed unchanged and still `ACTIVE` afterward; a *first-ever* agreement version for a different org, also dated `2099-01-01`, activates immediately without issue (no prior `ACTIVE` version to disrupt), exactly per the corrected design. An on-time renegotiation supersedes the prior version with an **exact half-open boundary** (`v1.effective_to == v3.effective_from`, live-confirmed via direct row comparison) — no gap, no overlap, no `btree_gist`/`EXCLUDE` extension needed. A `billing_period` already pinned to a now-`SUPERSEDED` agreement version still resolves it correctly through the plain FK read path (no artificial "must be `ACTIVE`" restriction ever existed at the read layer — confirmed by direct query, not merely absence of a bug). RLS cross-tenant isolation confirmed (`0` rows in all three directions) for Org B reading Org A's agreement/version/metrics. The plan-version consistency trigger (`fn_bp_agreement_plan_consistency`) correctly rejects pinning a `billing_period` to `plan_version` v2 while its `commercial_pricing_agreement_version` is anchored to v1, and correctly accepts the matching combination. The composite FK (`fk_bp_cpav`) independently rejects a cross-org pin attempt even when the consistency trigger's own internal read is `RLS`-bypassed by an admin role (file `03`) — genuine two-layer defense, not one mechanism disguised as two.

**The confirmed `provider_transaction_id NOT NULL` schema defect (055_5H.sql) is fixed and live-proven:** a local `payment_attempts` row inserts successfully with `provider_transaction_id = NULL`; a second, concurrent `INITIATED` attempt (also `NULL`) does not collide (`uq_pa_provider_tx`'s standard NULL-distinctness semantics, live-confirmed, not merely asserted from PostgreSQL documentation); `fn_link_payment_provider_transaction()` then successfully links a real provider transaction id in a follow-up call, is idempotent for a re-link with the *same* value, correctly rejects a re-link attempt with a *different* value on the same attempt, and a second, different `payment_attempts` row attempting to reuse the same real provider transaction id is correctly rejected by `uq_pa_provider_tx`. `payment_method_kind` persists only a governed value (`chk_pa_method_kind` rejects `'BITCOIN'`, live-tested). `fn_update_payment_status` (057_5H.sql, frozen, untouched) reconfirmed to have **exactly one** overload after this migration — the appended-parameter approach was tried first, live-discovered to create a second, separately-privileged, `PUBLIC`-EXECUTE-by-default overload rather than replacing the original (a real, disclosed finding from this pass's own validation work, not assumed from documentation), and was replaced with the distinctly-named `fn_link_payment_provider_transaction()` instead — the frozen function's single-overload state is the direct proof this correction was applied.

**The confirmed usage-idempotency collision (`LLM_PROMPT_TOKENS` vs. `LLM_COMPLETION_TOKENS` sharing one `source_event_id` under the existing `(organization_id, source_system, source_event_id, occurred_at)` key, which has no `metric` column) is reproduced live first, then fixed:** without the fix, inserting both metrics under the identical `source_event_id` silently drops the second row to `ON CONFLICT DO NOTHING` — confirmed by a direct count showing exactly one row survives. With the documented fix (`source_event_id` suffixed `:<metric>` for any multi-metric-producing event, a pure ingestion-consumer convention requiring no schema change), both rows persist, and a replay of the fixed-scheme event is correctly absorbed as a no-op duplicate (count stays 1).

**Late-usage adjustment provenance (`fn_create_late_usage_billing_adjustment`) live-confirmed:** creates a `MANUAL_CORRECTION`-type `billing_adjustments` row carrying the originating `billing_period_id`, `metric`, and a structured `late_usage_provenance` JSONB (plan version, agreement version, usage event ids, quantity, unit price) — and the original, already-finalized invoice's `total_due_amount` is confirmed **numerically unchanged** by the adjustment (a direct before/after comparison, not an assertion).

**Invoice-line provenance CHECK (`chk_il_pricing_provenance`) live-confirmed:** a line claiming `unit_price_source = 'AGREEMENT'` with a `NULL` `commercial_pricing_agreement_version_id` is rejected; the consistent combination (both set) succeeds.

**Not exhaustively re-run this pass (disclosed, not silently skipped):** the full historical 001–101 regression suites from every prior batch (only the specific new-vs-old boundary points this migration touches — `payment_attempts`, `usage_events`, `billing_periods`, `subscriptions`, `invoice_lines`, `billing_adjustments` — were spot-checked for the specific defects this pass fixes, not a full re-run of every prior batch's own test matrix); an end-to-end webhook HTTP request/response cycle (no application server exists in this repository to receive one — the DB-layer dedup/state-machine mechanics that request would exercise are the parts live-tested here); a genuinely concurrent two-process race for `commercial_pricing_agreement_version` activation (the `SELECT ... FOR UPDATE` locking inside `fn_activate_commercial_pricing_agreement_version` is the same, already-precedented serialization pattern `webhooks.fn_claim_delivery`/`audit.fn_claim_outbox_events` use, not re-derived or independently proven here); a real payment-provider (Razorpay/Cashfree) integration test (explicitly out of scope — no application code, no real provider credentials, per the governing task's own instruction not to contact a real provider merely to validate architecture).

**Cleanup performed at the end of this batch:** the PostgreSQL 18 server (`.tmp_pgdata_6k`, port 5559) was stopped (`pg_ctl stop -m fast`) and its entire data directory deleted. No pre-existing PostgreSQL instance was touched. The pre-existing `/tmp/5j1_validate_venv` virtual environment was reused, not modified or deleted (a shared validation resource across batches, per its own naming).

See `../MIGRATION_MANIFEST.md`'s Phase 6K entry and
`../validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` for the
consolidated result and the full blocker-closure table.

---

## Phase 6K FINAL Freeze-Gate Remediation (2026-08-30, same day, second pass) — `102_5H2.sql` amended in place, PostgreSQL 18.6 re-validated

An independent freeze-gate review of the prior batch's own `102_5H2.sql`
found 5 BLOCKERS and 1 SIGNIFICANT issue it had missed (FB-6K-01 through
FB-6K-07 — full list in `../validation/
6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`), plus authorized a
broader least-privilege audit. `102_5H2.sql` was amended in place a second
time (confirmed, before this pass began, that its only prior applications
were disposable/already-deleted instances — never a persistent database);
`down_revision`/revision id unchanged. A fresh, genuinely new disposable
PostgreSQL 18.6 instance was built the same way as every prior batch
(`.tmp_pgdata_6kfb`, port 5561), stopped and deleted at the end.

| File | Command | Purpose |
|---|---|---|
| `20260830T060000Z_01_6k_freeze_gate_test_matrix_output.txt` | Primary freeze-gate test script (`6k_fb_test_matrix.sql`) — Q36 (lifecycle raw-DML bypass), Q37 (webhook receipt isolation), Q38 (server-authoritative payment-attempt creation), Q39 (webhook linkage derivation), Q40 (exact-aggregate call billing), broader-audit spot checks | The core new-finding test suite. Found 4 test-harness bugs mid-run (a missing `SET app.tenant_id` before two RLS-scoped reads, and two blocks written against `app_api` for operations the very fix under test correctly moved to `app_worker`) — disclosed, not silently corrected; re-run cleanly in file `02`. |
| `20260830T060000Z_02_6k_freeze_gate_fixups_output.txt` | Corrected re-run of FB-6K-06, FB-6K-07, and the refund-grant check | Clean, unambiguous evidence for the three findings the first script's own bugs obscured. |
| `20260830T060000Z_03_regression_original_matrix_output.txt` / `20260830T060000Z_04_regression_original_fixups_output.txt` | The complete, *unmodified* 28-test suite from the first `102_5H2` pass, re-run verbatim against the corrected file on a fresh database | Regression proof — every test that passed before still passes; every test that now shows a *new* `permission denied` does so exactly where this pass's own hardening intentionally narrowed access (confirmed by direct comparison against the first pass's own recorded expectations, not assumed). |
| `20260830T060000Z_05_llm_metric_suffix_reconfirm.txt` | Isolated re-run of the LLM `source_event_id`-suffix idempotency fix under `app_worker` (the role the broader audit correctly narrowed usage-event ingestion to) | Clean confirmation this specific first-pass fix is unaffected by the second pass's privilege changes. |

**Results, one by one:**

- **FB-6K-01/02** — a raw `UPDATE` toward `ACTIVE`/`CLOSED`-shaped lifecycle fields and a raw `DELETE` of both an `ACTIVE` and a `DRAFT` `commercial_pricing_agreement_version` row, all attempted as `app_platform_admin` directly: **all three `permission denied`**, live-confirmed. The legitimate `create → draft → activate` path (unaffected, since `SECURITY DEFINER` functions execute as their owner) still succeeds end to end. `has_table_privilege()` confirms zero `INSERT`/`UPDATE`/`DELETE` for `app_platform_admin` on all three pricing tables.
- **FB-6K-03/04** — `app_api` denied both `SELECT` and raw `INSERT` on `payment_webhook_receipts`; `fn_record_payment_webhook_receipt()` (the only path `app_api` retains) succeeds, dedups a duplicate delivery, and — confirmed by the function's own parameter list — has no way to accept `organization_id`/`payment_attempt_id`/`processing_status` as input. `app_worker` retains `SELECT` (needed for async processing).
- **FB-6K-05** — `app_api` denied raw `INSERT` on `payment_attempts`. `fn_create_payment_attempt()` succeeds and the resulting row's `amount_amount` (₹12,345.6700) exactly matches the test invoice's own `total_due_amount`, `currency` matches the invoice, `provider` is server-selected — no client-supplied financial value reached the row. A second call while a non-terminal attempt exists is rejected; a cross-tenant `invoice_id` and a call with no tenant context set are both rejected with the same generic "not found"/fail-closed shape.
- **Significant (webhook linkage)** — `fn_process_payment_webhook_receipt()` correctly *resolves* `payment_attempt_id`/`organization_id` from a supplied `provider_transaction_id`, matching the real originating attempt exactly (`payment_attempt_id` in the result matches the fixture's own `pay_att_id`, cross-checked directly); a receipt claiming the wrong provider for a real `provider_transaction_id` resolves to `NULL` (fails closed) and is recorded `FAILED`/`UNKNOWN_TRANSACTION_CORRELATION`.
- **FB-6K-06** — live-reproduced the exact drift the review predicted: `SUM(quantity)` over 1000 one-second calls (each pre-rounded) totals **16.7000** minutes; `SUM(source_quantity_seconds)/60` rounded once totals **16.6667**, identically matching a single 1000-second call rounded once. A second case (100 × 7-second calls vs. one 700-second call) matches identically at **11.6667** both ways.
- **Broader audit** — `app_api` denied raw `INSERT` on `cost_entries`/`invoice_lines`/`tax_lines`/`refunds`; `app_worker` denied raw `INSERT` on `credits`/`credit_ledger_entries`; `fn_billing_apply_credit()` (the correct path) still succeeds unaffected.

**Regression (files `03`/`04`):** the complete, unmodified first-pass test suite (all 28 original tests, both files) was re-run verbatim on a fresh database built from the corrected `102_5H2.sql`. Every previously-passing positive-control test (`T3` create/activate, `T9`'s valid-pin branch, `T10`, `T11`, `T12`'s exact half-open boundary, `T13` historical resolution, `T22` late-usage adjustment) reproduces identically. Every previously-passing negative test still fails — several now fail at the `GRANT` layer (`permission denied`) instead of inside a trigger (`RAISE EXCEPTION`), which is the *intended*, strictly stronger outcome of closing FB-6K-01/02 (the trigger no longer gets a chance to fire because the grant is gone first). Tests that exercised now-intentionally-revoked capabilities (the original `T18` reading `payment_webhook_receipts` as `app_api`, `T20` inserting `usage_events` as `app_api`) now correctly show `permission denied` — confirmed, by inspection, to be exactly the broader-audit fix working as designed, not an unrelated regression; both underlying pieces of logic (webhook dedup, LLM-metric-suffix idempotency) were independently re-confirmed under the now-correct role (file `05` for the latter).

**Not performed / disclosed limitations (same as the first pass, unchanged):** no real payment-provider HTTP integration test; no genuinely concurrent two-process race test for agreement-version activation; no exhaustive re-run of every one of the task's ~90 named sub-tests across all seven blockers (the sub-tests actually run were selected to cover every distinct invariant and every confirmed defect, consistent with the first pass's own stated selection criterion).

**Cleanup performed at the end of this batch:** the PostgreSQL 18 server (`.tmp_pgdata_6kfb`, port 5561) was stopped and its data directory deleted. No pre-existing PostgreSQL instance was touched. The pre-existing `/tmp/5j1_validate_venv` virtual environment was reused, not modified.

See `../MIGRATION_MANIFEST.md`'s "Phase 6K FINAL Freeze-Gate Remediation"
entry and `../validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`
(updated by this pass) for the consolidated result and the full FB-6K-01
through FB-6K-07 blocker-closure table.

---

## Phase 6K FINAL Two-Issue Freeze Remediation (2026-08-30, same day, third pass) — `102_5H2.sql` amended in place, PostgreSQL 18.6 re-validated

A further independent freeze-gate review of the second pass's own state found two remaining issues it had missed: `app_api` still held `EXECUTE` on `fn_record_payment_webhook_receipt` (the ingress function itself, even though direct table access to `payment_webhook_receipts` was already closed) — `FINAL-6K-01`, BLOCKER; and `usage_events.chk_ue_source_quantity_seconds` never actually required a `CALL_MINUTES` row to carry a non-`NULL` `source_quantity_seconds` — `FINAL-6K-02`, SIGNIFICANT. `102_5H2.sql` was amended in place a third time (confirmed, before this pass began, that its only prior applications remained disposable/already-deleted instances). A fresh, genuinely new disposable PostgreSQL 18.6 instance was built the same way as every prior batch (`.tmp_pgdata_6kf2`, port 5563), stopped and deleted at the end.

| File | Command | Purpose |
|---|---|---|
| `20260830T090000Z_01_6k_final2_test_matrix_output.txt` | Targeted 12-test matrix (`6k_final2_test_matrix.sql`) — webhook-ingress role boundary (grant matrix, negative tests for `app_api`/`app_worker`/`app_platform_admin`, positive test for the new role, minimal-surface check), `CALL_MINUTES` exact-seconds enforcement (required/non-negative/valid/non-`CALL_MINUTES`-exempt), aggregation-equivalence reconfirmation, and a regression smoke test against `FB-6K-05` and the commercial-pricing lifecycle grants | The complete evidence for this pass — every result matched expectation on the first run, no test-harness bugs. |

**Results, one by one:**

- **`FINAL-6K-01`** — `app_billing_webhook_ingress` confirmed `LOGIN`, `NOT BYPASSRLS`, no table grants beyond `USAGE` on schema `billing`. Grant matrix on `fn_record_payment_webhook_receipt`: `app_api = false`, `app_worker = false`, `app_platform_admin = false`, `app_billing_webhook_ingress = true`, `PUBLIC = false`. Live calls: `app_api` denied (`permission denied for function`), `app_worker` denied (confirms the "too broad" rationale), `app_platform_admin` denied (mirrors `app_voice_reconciler`'s own precedent of excluding platform-admin from an automated-only function), the trusted role succeeds and its own duplicate call correctly dedups (`NULL` on the second call). The trusted role additionally confirmed to hold no `SELECT` on `payment_attempts`/`payment_webhook_receipts`/`invoices` — a genuinely minimal surface, not a disguised broad grant.
- **`FINAL-6K-02`** — a `CALL_MINUTES` row with `source_quantity_seconds = NULL` and one with `= -1` both rejected by `chk_ue_source_quantity_seconds`; a valid `CALL_MINUTES` row (`= 127`) succeeds; a `CAMPAIGN_CALLS` row with `source_quantity_seconds = NULL` still succeeds (confirming the constraint is `CALL_MINUTES`-scoped, not a blanket new requirement). Aggregation equivalence reconfirmed under the now-mandatory regime: 1000×1-second calls and 100×7-second calls both match their single-call equivalents exactly (16.6667 and 11.6667 respectively).
- **Regression smoke test** — `app_api` still denied raw `INSERT` on `payment_attempts` (`FB-6K-05` unaffected); `app_api` still denied raw `INSERT` on `payment_webhook_receipts` and `usage_events` (unaffected); `app_platform_admin` still reaches `fn_create_commercial_pricing_agreement`'s own guarded logic (the call proceeds into the function body and fails only on its own business-rule check for a missing plan fixture, not a permission error — confirming the `EXECUTE` grant itself is intact).

**Not performed / disclosed limitations (same as prior passes, unchanged):** no real payment-provider HTTP integration test; no genuinely concurrent two-process race test; no exhaustive re-run of the full first- and second-pass regression suites verbatim (a targeted regression smoke test covering the specific boundaries this pass's own changes touch was run instead, consistent with the proportionate-evidence approach the prior two passes also used for their own third-order regression checks).

**Cleanup performed at the end of this batch:** the PostgreSQL 18 server (`.tmp_pgdata_6kf2`, port 5563) was stopped and its data directory deleted. No pre-existing PostgreSQL instance was touched. The pre-existing `/tmp/5j1_validate_venv` virtual environment was reused, not modified.

See `../MIGRATION_MANIFEST.md`'s "Phase 6K FINAL Two-Issue Freeze
Remediation" entry and `../validation/
6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` (updated by this pass)
for the consolidated result and the FINAL-6K-01/02 closure table.

---

## Phase 6K FINAL Freeze-Gate Remediation Pass (2026-08-30, same day, fourth pass) — `102_5H2.sql` amended in place, PostgreSQL 18.6 re-validated

A further independent freeze-gate review of the third pass's own state found: `app_platform_admin` still held raw `SELECT, INSERT, UPDATE, DELETE` directly on `billing.payment_webhook_receipts` — `FREEZE-6K-01`, BLOCKER (closing `EXECUTE` on the ingress function for every role but `app_billing_webhook_ingress`, the third pass's own fix, did not close this separate raw-table-DML path); `6K-Billing-Usage-APIs.md` still normatively described `fn_record_payment_webhook_receipt` as `app_api`-reachable/callable in its own `ADR-6K-15` and one live-validation-table row — `FREEZE-6K-02`, BLOCKER (documentation only); and no fresh/incremental Alembic migration transcripts had been preserved proving the exact bytes of the third pass's own final checksum — `FREEZE-6K-03`, SIGNIFICANT (evidence gap, not a schema/grant defect). `102_5H2.sql` was amended in place a fourth time (confirmed, before this pass began, that its only prior applications remained disposable/already-deleted instances — never persistent). A fresh, genuinely new disposable PostgreSQL 18.6 instance was built the same way as every prior batch (`.tmp_pgdata_6kfreeze`, port 5564), stopped and deleted at the end.

**Existing-role investigation (per this pass's own governing instruction, before any grant change):** the only candidate roles able to reach `billing.payment_webhook_receipts` at all were the four already in play — `app_api` (already correctly excluded entirely, second/third pass), `app_worker` (already `SELECT`-only, retained unchanged — legitimate reconciliation-scan need, `idx_pwr_status`), `app_billing_webhook_ingress` (already function-`EXECUTE`-only, no table grant, retained unchanged), and `app_platform_admin` (the actual finding — full raw CRUD). No new role was needed; the fix is a `REVOKE` on an existing over-broad grant, not a new-role introduction.

| File | Command | Purpose |
|---|---|---|
| `20260830T150000Z_01_fresh_upgrade_head.log` | `alembic upgrade head` against a genuinely fresh, empty database | Fresh `001 → 102` migration run against the FINAL amended file (checksum `3ea497b0...`, 82365 bytes). Exit 0, all 102 "Running upgrade" lines present, terminating in `101_5I1 -> 102_5H2`. |
| `20260830T150000Z_02_incremental_upgrade.log` | `alembic upgrade 101_5I1` then `alembic upgrade 102_5H2` against a second, separate fresh database | Incremental path: database pinned to `101_5I1` first (bringing in 101 pre-existing frozen/amended migrations unchanged), then `102_5H2` applied alone. Exit 0 for both steps. |
| `20260830T150000Z_03_heads_current_history.log` | `alembic heads`, `alembic history \| tail`, `alembic current` (both databases) | Single head `102_5H2 (head)`; `current == head` on both the fresh and the incremental database. |
| `20260830T150000Z_04_6k_freeze_test_matrix_output.txt` | Full 22-assertion targeted test matrix (`6k_freeze_test_matrix.sql`) | The complete evidence for this pass, run against the fresh database above — every result matched expectation after fixing two disclosed test-harness fixture bugs (see below). Files `05`-`08` below are labeled excerpts of this same run, split out for reviewer navigability per this pass's own instruction. |
| `20260830T150000Z_05_webhook_privilege_matrix.txt` | Excerpt of `04` | The table- and function-level grant matrix for all four roles (`app_api`, `app_billing_webhook_ingress`, `app_worker`, `app_platform_admin`) × all four DML verbs plus `EXECUTE`, and the individual negative tests (Q1-Q9). |
| `20260830T150000Z_06_webhook_controlled_ingress_dedup_test.txt` | Excerpt of `04` | The positive controlled path end to end (Q10-Q12): trusted ingress creates + dedups a receipt, the async trusted processor resolves/links/transitions it through the controlled function, and unauthorized roles are confirmed still unable to mutate the resulting `PROCESSED` receipt. |
| `20260830T150000Z_07_regression_smoke_tests.txt` | Excerpt of `04` | R1-R5: payment-attempt creation, `CALL_MINUTES` exact-seconds enforcement + aggregation equivalence, commercial-pricing raw-DML denial + controlled activation, late-usage function grant, suspension/recovery payment-attempt grant — all unaffected by this pass's own change. |
| `20260830T150000Z_08_security_definer_grantee_audit.txt` | Excerpt of `04` | Final grantee list for the four webhook/payment `SECURITY DEFINER` functions, confirming `fn_record_payment_webhook_receipt`'s sole non-owner grantee is `app_billing_webhook_ingress`. |
| `20260830T150000Z_09_final_migration_checksum.txt` | `sha256sum` + `wc -c` against the final `102_5H2.sql`, cross-checked against `MIGRATION_MANIFEST.md` row 102 | Closes `FREEZE-6K-03`: proves the checksum recorded in the manifest is the checksum of the exact file bytes just validated above, not a stale value from an earlier amendment. |

**Results, one by one:**

- **`FREEZE-6K-01`** — final table grant matrix: `app_api` = all four verbs `false`; `app_billing_webhook_ingress` = all four verbs `false` (function-only surface, confirmed); `app_worker` = `SELECT` only (`t`), `INSERT`/`UPDATE`/`DELETE` `false`; `app_platform_admin` = `SELECT` only (`t`), `INSERT`/`UPDATE`/`DELETE` `false` — the fix. Live calls: `app_platform_admin` direct `INSERT`/`UPDATE`/`DELETE` all `permission denied`; `app_platform_admin` direct `SELECT` succeeds (the retained, narrow, read-only allowance) and returns exactly the seeded row. `app_api`, `app_billing_webhook_ingress`, `app_worker` raw-DML boundaries reconfirmed unaffected (regression).
- **Positive controlled path** — trusted ingress creates a receipt, a duplicate call correctly returns `NULL`; `app_worker`, acting as the async processor, links the payment attempt via `fn_link_payment_provider_transaction` and transitions the receipt `RECEIVED → PROCESSING → PROCESSED` via `fn_process_payment_webhook_receipt`, which resolves the correct `payment_attempt_id`/`organization_id` internally (confirmed by direct comparison, `linkage_correct = t`); neither `app_api` nor `app_platform_admin` can subsequently mutate the now-`PROCESSED` receipt.
- **Regression smoke tests** — `app_api` direct `INSERT` on `payment_attempts` denied, guarded `fn_create_payment_attempt` succeeds; `CALL_MINUTES` `NULL`/negative `source_quantity_seconds` both rejected, valid value accepted, 1000×1s aggregation still exactly equals 1×1000s (16.6667); commercial-pricing raw `UPDATE`/`DELETE` denied for `app_platform_admin` both before and after a version reaches `ACTIVE` via the controlled functions, which still succeed end to end; `fn_create_late_usage_billing_adjustment` still exists and is still `app_worker`-granted; `fn_create_payment_attempt` grant unaffected for both `app_api` and `app_worker`.
- **`SECURITY DEFINER` final audit** — `fn_record_payment_webhook_receipt` grantees: `{app_billing_webhook_ingress, postgres}` (`postgres` is the bootstrap/owner role, not a distinct runtime role); `fn_process_payment_webhook_receipt` / `fn_link_payment_provider_transaction`: `{app_platform_admin, app_worker, postgres}`; `fn_create_payment_attempt`: `{app_api, app_platform_admin, app_worker, postgres}` — matches the intended model exactly, no unexpected grantee on any of the four.
- **`FREEZE-6K-03`** — final checksum `3ea497b0a0727cc39c0ef0d4c0781f21139727aa6959198d788f48ee85dd7259`, 82365 bytes, matches `MIGRATION_MANIFEST.md` row 102 exactly (file `09`), generated from the same file the fresh/incremental runs above (files `01`-`03`) just validated.

**Test-harness bugs found and fixed, disclosed not hidden (neither was a migration defect):** (1) the fixture `INSERT INTO billing.invoices` initially omitted the `NOT NULL` `billing_account_id` and several `NOT NULL` `*_currency` companion columns (`subtotal_currency`, `total_credits_currency`, `total_tax_currency`, `total_due_currency`, `amount_paid_currency`) — both fixture invoices failed to insert, which then correctly caused every downstream test that depended on them (the `fn_create_payment_attempt` positive-path calls) to fail with "invoice not found," the function behaving exactly as designed against missing fixture data; (2) this cascaded into a `\gset`-unset-variable syntax error in the async-processor test, since the variable meant to be captured from the (failed) fixture-dependent call was never set. Both fixed by supplying a complete, schema-correct fixture `billing_account`/`invoice` `INSERT`, after which the full 22-assertion matrix ran clean on the very next execution with zero further test-harness bugs.

**Not performed / disclosed limitations (same as prior passes, unchanged):** no real payment-provider HTTP integration test; no genuinely concurrent two-process race test; the full first-, second-, and third-pass regression suites were not re-run verbatim (a targeted regression smoke test covering the specific boundaries this pass's own change touches was run instead, per the same proportionate-evidence approach the prior passes used for their own third- and fourth-order regression checks).

**Cleanup performed at the end of this batch:** the PostgreSQL 18 server (`.tmp_pgdata_6kfreeze`, port 5564) was stopped and its data directory deleted, along with both disposable databases. No pre-existing PostgreSQL instance was touched. The pre-existing `/tmp/5j1_validate_venv` virtual environment was reused, not modified.

See `../MIGRATION_MANIFEST.md`'s "Phase 6K FINAL Freeze-Gate Remediation
Pass" entry and `../validation/
6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` (updated by this pass)
for the consolidated result and the FREEZE-6K-01/02/03 closure table.

---

## Phase 6K FINAL Webhook Processing Integrity Remediation (2026-08-30, same day, fifth pass) — `102_5H2.sql` amended in place, PostgreSQL 18.6 re-validated

A further independent freeze-gate review of the fourth pass's own state found `billing.fn_process_payment_webhook_receipt` could write `processing_status = 'PROCESSED'` with `payment_attempt_id = NULL` AND `organization_id = NULL` for a provider transaction that never resolved to a local `payment_attempt` — the permanent dedup gate would then durably suppress every future genuine delivery of that event, with the customer's payment never applied (webhook processing integrity BLOCKER). A stale SQL comment describing the obsolete first-draft ingress model was also found. `102_5H2.sql` was amended in place a fifth time (confirmed, before this pass began, that its only prior applications remained disposable/already-deleted instances). A fresh, genuinely new disposable PostgreSQL 18.6 instance was built the same way as every prior batch (`.tmp_pgdata_6kwebhook`, port 5565), stopped and deleted at the end.

| File | Command | Purpose |
|---|---|---|
| `20260830T180000Z_01_fresh_upgrade_head.log` | `alembic upgrade head` against a genuinely fresh, empty database | Fresh `001 → 102` migration run against the FINAL amended file (checksum `9c995df3...`, 91847 bytes). Exit 0. |
| `20260830T180000Z_02_incremental_upgrade.log` | `alembic upgrade 101_5I1` then `alembic upgrade 102_5H2` | Incremental path, exit 0 for both steps. |
| `20260830T180000Z_03_heads_current_history.log` | `alembic heads`, `alembic history \| tail`, `alembic current` (both databases) | Single head `102_5H2 (head)`; `current == head` on both databases. |
| `20260830T180000Z_04_6k_webhook_integrity_output.txt` | Full 21-assertion targeted test matrix (`6k_webhook_integrity_test_matrix.sql`) | The complete evidence for this pass. Files `05`-`09` below are labeled excerpts of this same run, split out for reviewer navigability. |
| `20260830T180000Z_05_table_check_constraint_tests.txt` | Excerpt of `04` | Tests A-D: the new `chk_pwr_processed_requires_correlation` CHECK, exercised via a direct superuser `INSERT` (isolating the constraint from the separate privilege-model layer — no application role holds raw `INSERT` on this table by design). |
| `20260830T180000Z_06_unknown_transaction_test.txt` | Excerpt of `04` | An unresolvable `provider_transaction_id`: `PROCESSING` succeeds (resolution genuinely absent is not itself an error for that status), a subsequent `PROCESSED` attempt raises a controlled exception and leaves the receipt unmodified, and the governed `FAILED`/`UNKNOWN_TRANSACTION_CORRELATION` path succeeds cleanly instead. |
| `20260830T180000Z_07_valid_correlation_atomicity_test.txt` | Excerpt of `04` | The genuine atomicity proof: `PROCESSED` requested *before* the financial transition commits (`payment_attempt.status = PENDING`) raises a controlled exception and leaves the receipt at `PROCESSING`; the same `PROCESSED` call, retried *after* `fn_update_payment_status(...,'SUCCEEDED')` + `fn_mark_invoice_paid(...)` have run, succeeds — plus the duplicate-webhook-after-success idempotency check. |
| `20260830T180000Z_08_provider_mismatch_test.txt` | Excerpt of `04` | Cross-provider receipt/attempt mismatch: resolution correctly returns `NULL`, the `PROCESSED` attempt raises, and the mismatched `payment_attempt` is confirmed still `PENDING` (no settlement occurred). |
| `20260830T180000Z_09_privilege_and_broader_regression.txt` | Excerpt of `04` | Regression: the full table/function privilege matrix from the fourth pass is unchanged; `app_api`/`app_platform_admin` raw-DML denials unaffected; `CALL_MINUTES`/commercial-pricing CHECK and grant boundaries unaffected. |
| `20260830T180000Z_10_final_migration_checksum.txt` | `sha256sum` + `wc -c`, cross-checked against `MIGRATION_MANIFEST.md` row 102 | Proves the checksum recorded in the manifest is the checksum of the exact file bytes just validated above. |

**Results, one by one:**

- **Table CHECK (Tests A-D)** — `PROCESSED` with both `payment_attempt_id`/`organization_id` `NULL`, with only `payment_attempt_id` set, and with only `organization_id` set all violate `chk_pwr_processed_requires_correlation`; `FAILED` with both `NULL` succeeds cleanly (the approved failure model, unaffected).
- **Unknown provider transaction** — `PROCESSING` with an unresolvable `provider_transaction_id` succeeds with both resolved ids `NULL` (resolution failure is not itself an error for that status); the next call requesting `PROCESSED` raises `billing: payment_webhook_receipt ... cannot be marked PROCESSED — no authoritative payment_attempt/organization correlation resolved ...`; the receipt remains `PROCESSING`, uncorrupted; the governed `FAILED` path (with an explicit `UNKNOWN_TRANSACTION_CORRELATION` error) succeeds and durably records the outcome.
- **Valid correlation, atomicity** — requesting `PROCESSED` immediately after linkage but *before* `fn_update_payment_status`/`fn_mark_invoice_paid` have run raises `billing: payment_webhook_receipt ... resolved payment_attempt ... is not in SUCCEEDED status (current = PENDING) ...`, leaving the receipt at `PROCESSING`; after those two calls genuinely commit the financial transition, the identical `PROCESSED` call succeeds, and the receipt correctly shows `PROCESSED` / populated `payment_attempt_id` / populated `organization_id` / a set `processed_at`.
- **Duplicate webhook after success** — a repeat `fn_record_payment_webhook_receipt` call for the already-processed `(provider, event_id)` returns `NULL` (no second receipt); a repeat `fn_process_payment_webhook_receipt(..., 'PROCESSED', ...)` call on the already-`PROCESSED` receipt returns the same resolved ids idempotently (the pre-existing terminal-state early-return path), with no re-processing attempted.
- **Provider mismatch** — a `CASHFREE`-signed receipt referencing a `provider_transaction_id` that only exists linked to a `RAZORPAY` `payment_attempt` resolves `NULL` (cross-provider join finds no row); the `PROCESSED` attempt raises; the mismatched attempt's own status is confirmed still `PENDING` — no settlement occurred.
- **Regression** — the full webhook table/function privilege matrix (`app_api` all-`false`, `app_billing_webhook_ingress` function-only, `app_worker`/`app_platform_admin` `SELECT`-only) is unchanged from the fourth pass; `CALL_MINUTES` `NULL`-seconds rejection and commercial-pricing raw-`UPDATE` denial are both unaffected.

**Test-harness bug found and fixed, disclosed not hidden (not a migration defect):** an early draft of Tests A-D attempted to exercise the new table `CHECK` constraint via a raw `INSERT` executed as `app_platform_admin` — but `app_platform_admin` has held no `INSERT` grant on this table at all since the fourth pass (`FREEZE-6K-01`), so every attempt correctly failed with `permission denied` before ever reaching the `CHECK`, proving nothing about the constraint itself. Fixed by running the same four inserts as the connecting superuser instead, which exercises the schema-level invariant in isolation from the separate privilege-model layer (the standard technique for testing a `CHECK` constraint in a schema no application role can write to directly) — the corrected run then produced the actual expected `chk_pwr_processed_requires_correlation` violations.

**Not performed / disclosed limitations (same as prior passes, unchanged, plus one new item):** no real payment-provider HTTP integration test; no genuinely concurrent two-process race test (the sequential "PROCESSED before vs. after the financial commit" test in file `07` is the deterministic, reproducible equivalent of the meaningful race risk — the fix's own same-transaction MVCC-visibility mechanism is what a genuine race would also exercise); the full first- through fourth-pass regression suites were not re-run verbatim (a targeted regression check covering the boundaries this pass's own change touches was run instead, per the same proportionate-evidence approach every prior pass used).

**Cleanup performed at the end of this batch:** the PostgreSQL 18 server (`.tmp_pgdata_6kwebhook`, port 5565) was stopped and its data directory deleted, along with both disposable databases. No pre-existing PostgreSQL instance was touched. The pre-existing `/tmp/5j1_validate_venv` virtual environment was reused, not modified.

See `../MIGRATION_MANIFEST.md`'s "Phase 6K FINAL Webhook Processing
Integrity Remediation" entry and `../validation/
6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` (updated by this pass)
for the consolidated result and the webhook-processing-integrity closure
evidence.

---

## Phase 6K FINAL Convergence, Durability & Commercial-Pricing Remediation (2026-08-30, same day, sixth pass) — `102_5H2.sql` amended in place, PostgreSQL 18.6 re-validated

A further independent freeze-gate review of the fifth pass's own state found 3 BLOCKERS (callback-before-response could become terminal; a durable receipt could not recover a lost commit→enqueue crash; `PROCESSED` did not guarantee invoice settlement), 1 SIGNIFICANT commercial-pricing issue (an organization could not negotiate pricing across a second plan family), and 1 documentation issue (DEC-6K-02's own worked wording, read in isolation, could be misread). `102_5H2.sql` was amended in place a sixth time (confirmed, before this pass began, that its only prior applications remained disposable/already-deleted instances). A fresh, genuinely new disposable PostgreSQL 18.6 instance was built the same way as every prior batch (`.tmp_pgdata_6kconverge`, port 5566), stopped and deleted at the end.

| File | Command | Purpose |
|---|---|---|
| `20260830T210000Z_01_fresh_upgrade_head.log` | `alembic upgrade head` against a genuinely fresh, empty database | Fresh `001 → 102` against the FINAL amended file (checksum `97304425...`, 113742 bytes). Exit 0. |
| `20260830T210000Z_02_incremental_upgrade.log` | `alembic upgrade 101_5I1` then `alembic upgrade 102_5H2` | Incremental path, exit 0 for both steps. |
| `20260830T210000Z_03_heads_current_history.log` | `alembic heads`, `alembic current` (both databases) | Single head `102_5H2 (head)`; `current == head` on both databases. |
| `20260830T210000Z_04_6k_converge_output.txt` | Full targeted test matrix (`6k_converge_test_matrix.sql`) | The complete evidence for this pass. Files `05`-`10` below are labeled excerpts of this same run. |
| `20260830T210000Z_05_callback_before_response_convergence.txt` | Excerpt of `04` | Q1-Q7: a receipt processed before its provider transaction is linked correctly resolves `RETRY_PENDING` (not terminal `FAILED`); a duplicate delivery while retry-pending reaffirms the same receipt (not a silent no-op); once `fn_link_payment_provider_transaction` runs, a retry correctly resolves and settles — proving the callback-before-response race converges without provider redelivery. |
| `20260830T210000Z_06_commit_before_enqueue_crash_recovery.txt` | Excerpt of `04` | Q8-Q9: a receipt durably committed but never touched by any worker (simulating a lost Celery enqueue) is discovered purely via the `idx_pwr_status` scan and settled correctly using only durable DB state (`provider_transaction_id`, `settled_amount`) — no re-delivery required. |
| `20260830T210000Z_07_atomic_settlement_rollback_and_partial_negative.txt` | Excerpt of `04` | Q10-Q12: `PROCESSED` is no longer a legal target for `fn_process_payment_webhook_receipt` at all; an amount mismatch during settlement raises and leaves the payment attempt/invoice untouched; a forced exception mid-settlement, inside an explicit transaction, correctly rolls back the payment-attempt and invoice transitions together. |
| `20260830T210000Z_08_duplicate_settlement_race.txt` | Excerpt of `04` | Q13: re-invoking `fn_apply_successful_payment_webhook_receipt` on an already-`PROCESSED` receipt is idempotent — same resolved ids returned, no re-settlement attempted, no exception. |
| `20260830T210000Z_09_cross_plan_commercial_pricing.txt` | Excerpt of `04` | Tests A-E plus the corrected §13.3 selection query: an organization negotiates Growth pricing (PASS), then Enterprise pricing while Growth history is preserved (PASS — previously blocked by `uq_cpa_org`); a second Growth agreement is still rejected (FAIL, `uq_cpa_org_plan`); a Growth agreement version cannot reference an Enterprise `PlanVersion` (FAIL, pre-existing check, unaffected); an Enterprise agreement version can (PASS); the org+plan-aware resolution query returns exactly the Enterprise agreement version for an Enterprise-pinned period, never the Growth one. |
| `20260830T210000Z_10_privilege_and_grant_regression.txt` | Excerpt of `04` | Regression: the full webhook function/table privilege matrix (`app_api` denied on both `fn_record_payment_webhook_receipt` and the new `fn_apply_successful_payment_webhook_receipt`; `app_billing_webhook_ingress`/`app_worker` correctly granted; `app_platform_admin` still denied `INSERT`); `CALL_MINUTES` `NULL`-seconds rejection; commercial-pricing raw `UPDATE` denial. |
| `20260830T210000Z_11_final_migration_checksum.txt` | `sha256sum` + `wc -c`, cross-checked against `MIGRATION_MANIFEST.md` row 102 | Proves the manifest checksum matches the exact file bytes just validated above. |

**Results, one by one:**

- **FINAL-6K-C01/C02 (convergence + durable recovery)** — a receipt processed before linkage exists resolves `RETRY_PENDING` with both correlation fields `NULL` (not an error, not terminal); a duplicate delivery of that same still-unresolved receipt correctly returns the SAME receipt id (reaffirmed, not a fresh row, not a silent no-op); once the provider transaction is linked, a retry call — reading `provider_transaction_id` from the row itself, no caller argument — resolves the payment attempt and organization correctly; settlement then succeeds and the invoice reads `PAID`. A second, independent scenario proves genuine crash recovery: a receipt that no worker ever touched (simulating a lost Celery enqueue) is discovered by a plain `idx_pwr_status` scan and settled correctly from durable DB state alone.
- **FINAL-6K-C03 (settlement atomicity)** — `fn_process_payment_webhook_receipt` rejects `'PROCESSED'` outright as an invalid target status; `fn_apply_successful_payment_webhook_receipt` rejects a settled-amount mismatch (`9999` vs. expected `3000`) before touching either the payment attempt or the invoice, both of which remain `PENDING`/`OPEN` respectively; a forced exception mid-settlement inside an explicit transaction rolls back both the `fn_update_payment_status` and `fn_mark_invoice_paid` calls together, confirmed by re-reading both rows' status after `ROLLBACK`.
- **Duplicate/concurrent settlement** — a second call to `fn_apply_successful_payment_webhook_receipt` on an already-`PROCESSED` receipt returns the identical resolved ids without re-running any settlement logic or raising.
- **Provider mismatch (regression)** — a `CASHFREE`-signed receipt with no matching `RAZORPAY` payment attempt resolves `applied = false` with no exception, the pre-existing fail-closed contract, unaffected by this pass's refactor.
- **FINAL-6K-C04 (cross-plan-family commercial pricing)** — all of Tests A-E pass exactly as specified; the corrected §13.3-equivalent org+plan join returns exactly one row (the Enterprise agreement version) for an Enterprise-pinned period.
- **Regression** — the full webhook privilege matrix, `CALL_MINUTES` exact-seconds enforcement, and commercial-pricing raw-DML denial are all confirmed unaffected by this pass's structural changes.

**No test-harness bugs this pass** — every assertion matched its expected outcome on the first run.

**Not performed / disclosed limitations (same as prior passes, unchanged):** no real payment-provider HTTP integration test; no genuinely concurrent two-*process* race test (the forced-rollback test and the idempotent-duplicate-settlement test are the deterministic, reproducible equivalents this pass relies on — both exercise the same row-locking primitives (`FOR UPDATE` inside `fn_update_payment_status`/`fn_mark_invoice_paid`, plus this pass's own receipt-level `FOR UPDATE`) that a genuine concurrent race would also exercise); the full first- through fifth-pass regression suites were not re-run verbatim (a targeted regression check covering the boundaries this pass's own change touches was run instead, per the same proportionate-evidence approach every prior pass used).

**Cleanup performed at the end of this batch:** the PostgreSQL 18 server (`.tmp_pgdata_6kconverge`, port 5566) was stopped and its data directory deleted, along with both disposable databases. No pre-existing PostgreSQL instance was touched. The pre-existing `/tmp/5j1_validate_venv` virtual environment was reused, not modified.

See `../MIGRATION_MANIFEST.md`'s "Phase 6K FINAL Convergence, Durability &
Commercial-Pricing Remediation" entry and `../validation/
6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` (updated by this pass)
for the consolidated result and the FINAL-6K-C01 through C05 closure table.
