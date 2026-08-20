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
