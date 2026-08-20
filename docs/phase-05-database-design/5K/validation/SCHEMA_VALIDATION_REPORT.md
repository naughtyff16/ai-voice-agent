# Phase 5K — Schema Validation Report

**Date:** 2026-08-19
**Scope:** structural validation of the schema actually produced by running all 75
migrations against a genuinely fresh PostgreSQL 16 database (see
`ALEMBIC_VALIDATION_REPORT.md` §2 for the upgrade gate itself). This report covers
object counts, their reconciliation against two different measurement passes, and
migration-file-level integrity checks (destructive DDL, ordering, duplicates).

This file is one of the four mandated §7 validation reports, split out of the
original interim `validation/01_final_validation_report.md` (now removed).

---

## 1. Schema validation (post-upgrade, actual PostgreSQL state)

| Object | Count | Evidence file |
|---|---|---|
| Schemas | 16 (15 business + `public`) | `_10_schema_table_counts_by_schema.txt` |
| Tables | 199 (includes partition parent + child tables; 22 partitioned parents) | `_09_schema_tables_full.txt`, `_10_...` |
| Extensions | 4 — `pgcrypto`, `vector`, `pg_stat_statements`, `plpgsql` | `_08_schema_extensions.txt` |
| Foreign keys | 50 | `_11_schema_fk_count.txt` |
| Primary keys | 197 (`information_schema.table_constraints`) / 259 (raw `pg_constraint`) | see §2 below — both correct, reconciled |
| Unique constraints | 94 (`information_schema.table_constraints`) / 142 (raw `pg_constraint`) | see §2 below — both correct, reconciled |
| Check constraints | 2,541 (`information_schema.table_constraints`) / 558 (raw `pg_constraint`) | see §2 below — both correct, reconciled |
| Indexes | 821 | `_15_schema_index_count.txt` |
| Views | 2 | `_16_schema_view_count.txt` |
| Materialized views | 0 | `_17_schema_matview_count.txt` |
| Functions | 219 (`prokind='f'` only) / 223 (`prokind='f'` + `prokind='a'` aggregates) | see §2 below — both correct, reconciled |
| Triggers | 105 | `_19_schema_trigger_count.txt` |
| Native ENUM types | 0 | `_20_schema_enum_count.txt` |
| Native SEQUENCE objects | 0 | `_21_schema_sequence_count.txt` |
| RLS-enabled tables (ENABLE + FORCE) | 91 | `_22_schema_rls_tables.txt` |
| RLS policies | 103 | `_23_schema_policy_count.txt` |

All evidence file paths above are relative to `../execution_logs/`, prefix
`20260819T061806Z_` unless otherwise noted.

### Classification of findings against Phase 5A-5J design

- **0 native ENUM types, 2,541 CHECK constraints instead** — **intentional, approved design**, not a gap. `5A-Database-Architecture-and-Standards.md` §21.7 ("Enum / Reference Data Strategy") explicitly prohibits native PostgreSQL `ENUM` for evolving status fields in favor of `TEXT` + `CHECK` (line 1613: "ENUMs for evolving status values | ❌ PROHIBITED"). Confirmed consistent, no action needed.
- **0 native SEQUENCE objects, table-based allocation instead** (`billing.invoice_number_sequences`) — **intentional, approved design**. 5A §"Primary Keys"/invoice-numbering sections explain sequences are avoided because they leak row counts/insert rates to API consumers and don't compose across multiple application instances without a coordination service; a row-locked table provides gapless, per-org, per-fiscal-year allocation instead. Confirmed consistent.
- **Schema count drift in 5A's own text**: `5A-Database-Architecture-and-Standards.md` line 296 says "consistent across all 13 schemas" — stale, predates the `prompt` and `memory` schemas added during Phase 5G (already caught and fixed as an implementation defect during 5K's own execution history — see `EXECUTION_REPORT.md` defect #7). Classified as a **pre-existing minor documentation defect in 5A**, not a 5K deliverable and not touched here (5A is frozen architecture). Reported, not acted on. **Classification: NON-BLOCKING.**
- **Table count moved from an earlier reported 168 (in `EXECUTION_REPORT.md`) to 199** — consistent with more partition child tables existing at the later measurement time (22 partitioned parents × several partitions each per the spec's §13.2 partition-count table) and the `prompt`/`memory` schema fix. Classified as **expected growth, not a defect**; `EXECUTION_REPORT.md` documents this explicitly.
- **RLS "gaps" on partition child tables**: not evaluated fresh in this pass beyond confirming 91 RLS-enabled tables system-wide, consistent with the count `EXECUTION_REPORT.md` previously investigated and explained (child partitions correctly inherit RLS from their parent; PostgreSQL does not set `relrowsecurity` on children directly). No new discrepancy found.

**Result: PASS**, with all differences from earlier reported figures classified as either intentional-approved-design or expected/explained growth — no unresolved architectural conflict, no implementation defect found in the schema itself.

---

## 2. Count-discrepancy reconciliation (PK / UNIQUE / CHECK / function counts)

A second, independent structural-count pass (run later the same day, same disposable
container, no re-migration) produced different raw numbers for four object types than
the first pass above: PK 259 vs 197, UNIQUE 142 vs 94, CHECK 558 vs 2,541, functions 223
vs 219. This was investigated rather than silently reconciled or hidden — full evidence:
`execution_logs/20260819T072859Z_38_count_discrepancy_reconciliation.txt`.

**Root cause, confirmed by exact reproduction — not schema drift:**

- The first-pass queries (`_12`/`_13`/`_14_schema_*_count.txt`) used
  `information_schema.table_constraints`, the SQL-standard catalog view. This view
  **synthesizes a `CHECK`-type row for every `NOT NULL` column** (which is why its CHECK
  count, 2,541, is far larger than the number of genuinely-authored `CHECK (...)`
  constraints), and it **folds each partitioned table's per-partition physical
  constraint rows into one logical parent-level row** for PK/UNIQUE (which is why its
  PK/UNIQUE counts, 197/94, are smaller than the raw physical-object counts).
- The second pass queried raw `pg_constraint` directly, which does the opposite on both
  counts: it surfaces **each partition child's own physical constraint object
  separately** (inflating PK/UNIQUE to 259/142), but it **only counts constraints with
  `contype='c'` that were actually authored as `CHECK (...)`**, not ones
  `information_schema` synthesizes for `NOT NULL` (deflating CHECK to 558).
- Re-running the exact `information_schema.table_constraints` query from the second
  pass's session reproduced `197`/`94`/`2541`/`50` **exactly**, confirming the schema
  had not changed between passes — only the measurement method differed.
- Function count: `219` (first pass) counted only `pg_proc` rows with `prokind='f'`
  (ordinary functions). `223` (second pass) additionally counted 4 rows with
  `prokind='a'` (aggregate functions) that exist in non-system schemas. Both are
  correct for what they measure; the schema has 219 plain functions and 4 aggregates,
  223 `pg_proc` entries total.
- All other structural counts (tables=199, FKs=50, indexes=821, views=2, matviews=0,
  triggers=105, enums=0, sequences=0, RLS tables=91, policies=103) were spot-checked
  again in the second pass and matched the first pass exactly — no drift on any of
  those.

**Result: RECONCILED, not a defect.** Both sets of figures are correct for the query
that produced them; the apparent discrepancy is a counting-methodology artifact, fully
explained and reproduced on demand. **Classification: NON-BLOCKING** (no schema change,
no implementation defect — a documentation/measurement-methodology note only).

---

## 3. Migration integrity checks

| Check | Result |
|---|---|
| `DROP TABLE` / `DROP COLUMN` / `DROP SCHEMA` / `TRUNCATE` anywhere in `migrations/*.sql` | **None found** — zero destructive DDL in the entire frozen package |
| Duplicate index names across files | **None found** |
| Duplicate `ADD CONSTRAINT` names across files | **None found** |
| Extension dependency ordering | **Correct** — `pgcrypto`/`pg_stat_statements` created in `001_5B.sql` before first use (`gen_uuid_v7()` etc. used starting in `001_5B.sql` itself); `vector` created in `034_5F.sql` before first `vector(...)` column use (`034_5F.sql`, `038_5F.sql`) — no forward references |
| FK ordering / dependency ordering | Implicitly proven by the successful fresh-DB run — every `ADD CONSTRAINT ... FOREIGN KEY` executed in order with its referenced table already present (a fresh-DB upgrade would fail immediately otherwise) |
| Enum ordering | N/A — no native ENUM types exist in this design (§1) |
| Bad defaults / NULL handling | Not flagged by the fresh-DB run or the SECURITY DEFINER/RLS checks; see `MIGRATION_RECONCILIATION_REPORT.md` for the one class of default-related defect that *was* found (SECURITY DEFINER `search_path` omitting `public`, affecting functions whose `INSERT`s rely on a `gen_uuid_v7()` column default) |
| Environment-specific assumptions | None found — `DATABASE_URL` is the only environment input, read exclusively from the process environment, never defaulted |

**Result: PASS**, with one related defect (not a migration-integrity/ordering problem
itself, but a `SECURITY DEFINER` configuration defect surfaced via this validation)
cross-referenced to `MIGRATION_RECONCILIATION_REPORT.md` rather than duplicated here.

---

## Section result

**SCHEMA VALIDATION: PASS.** All structural counts are internally consistent once
measurement methodology is accounted for; both ENUM/SEQUENCE absences are confirmed
intentional per frozen 5A design; no destructive DDL, ordering problem, or duplicate
object name exists anywhere in the 75-file migration package.

---

## 4. Phase 5K.1 — post-patch schema validation (2026-08-19)

Migration `076_5K1` was applied on top of the validated 75-file baseline
above (fresh, disposable PostgreSQL 16 database — see
`ALEMBIC_VALIDATION_REPORT.md` §4). This section confirms the patch changed
**only** what it was scoped to change.

### 4.1 SECURITY DEFINER search_path — Defect A fix confirmed at the catalog level

| Function | `search_path` post-076 |
|---|---|
| `analytics.fn_apply_projection_call_latency` | `search_path=analytics, pg_catalog, public` |
| `analytics.fn_apply_projection_call_metrics` | `search_path=analytics, pg_catalog, public` |
| `analytics.fn_claim_projection_slot` | `search_path=analytics, pg_catalog, public` |
| `integrations.fn_create_integration_connection` | `search_path=integrations, pg_catalog, public` |
| `plugins.fn_create_plugin_installation` | `search_path=plugins, pg_catalog, public` |

All 5 now include `public`; `SECURITY DEFINER` property, arguments, return
type, and body are otherwise unchanged. `076_5K1.sql` implements this via
`CREATE OR REPLACE FUNCTION` — an identical, full reproduction of each
function's original body/signature/return type/owner with `public`
appended to its existing `SET search_path = <own_schema>, pg_catalog`
clause — rather than a bare `ALTER FUNCTION ... SET search_path`, so the
complete definition stays auditable in the patch and so existing
GRANT/REVOKE state on the functions (untouched by `CREATE OR REPLACE
FUNCTION`) is preserved. The other 19 flagged functions (pure trigger
functions, confirmed in the original validation pass to never touch
`public`) were left unpatched, as scoped.

### 4.2 app_platform_admin INSERT privilege — Defect B fix confirmed at the catalog level

`information_schema.role_table_grants` query for `grantee='app_platform_admin'`,
`table_name='workflow_executions'` OR any of its partitions,
`privilege_type='INSERT'`: **0 rows** (was 1+ rows pre-patch, confirmed via
`execution_logs/20260819T081500Z_41_grant_conflict_041_vs_046_platform_admin_insert.txt`).
`app_platform_admin`'s other grants (SELECT/UPDATE/DELETE on `workflow`
tables, all privileges elsewhere) are unchanged.

### 4.3 Aggregate counts, before vs. after 076 (same fresh database, before/after upgrade)

| Object | Count | Changed by 076? |
|---|---|---|
| Tables | 197 (this session's query scope — see §4.4 below) | No — identical before/after the 076 upgrade |
| Indexes | 821 | No |
| Triggers | 105 | No |
| RLS policies | 103 | No |
| Extensions | 4 | No |
| `SECURITY DEFINER` functions | 43 | No (076 only alters `search_path` on 5 existing ones, does not add/remove functions) |
| Function count | 223 total `pg_proc` (`prokind='f'`+`'a'`) | No |

Evidence: `../execution_logs/20260819T110500Z_49_schema_validation_post076_and_table_count_reconciliation.txt`.

### 4.4 Table-count methodology note (197 this session vs. 199 in §1 above)

This session's post-076 table count (197) used `pg_class.relkind IN
('r','p')` restricted to the 16 application schemas. The 199 figure in §1
above came from a differently-scoped `\d`-style listing over all relkinds
(`execution_logs/20260819T061806Z_09_schema_tables_full.txt`, 459 total
relations of every kind). This is the same class of methodology variance
already reconciled for PK/UNIQUE/CHECK/function counts in §2 above, not new
drift: the 197 count was measured identically immediately before and
immediately after the 076 upgrade against the same database, and did not
change — and `076_5K1.sql` contains zero `CREATE TABLE`/`ALTER TABLE`/`DROP
TABLE` statements (grep-verified against the frozen file). **Classification:
NON-BLOCKING** (measurement-methodology note, not a schema-content defect).

### Section 4 result

**PHASE 5K.1 SCHEMA VALIDATION: PASS.** Both defects confirmed fixed at the
catalog level; every other structural count is unchanged across the 076
upgrade; the patch is confirmed narrowly scoped with no unrelated schema
changes.
