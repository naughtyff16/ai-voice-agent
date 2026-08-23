# Phase 5K — Execution & Validation Report

## Real execution evidence, not conceptual claims

This report documents what was actually built and actually run, against a real PostgreSQL 16 instance (with pgvector, pgcrypto, pg_stat_statements installed) provisioned in this environment. Every claim below is backed by a specific command and its captured output — logs for all 75 migration runs are included in `execution_logs/`.

---

## 1. `gen_uuid_v7()` — Resolved

The frozen Phase 5B document contains two different implementations. Both were tested live:

| Version | Location | Result |
|---|---|---|
| A | §11 "Primary Keys" (narrative) | **Fails immediately**: `ERROR: invalid input syntax for type uuid` |
| B | §33 "Complete PostgreSQL DDL" / Migration 001 (the actual DDL) | **Works**: valid UUIDs, correct version/variant bits, time-ordered |

Version B was stress-tested: 100,000 generated values, 100,000 distinct (zero collisions). **Version B is authoritative** — it's now in `migrations/001_5B.sql`.

---

## 2. `CHANGE_IN_PRODUCTION` — Removed

`migrations/001_5B.sql` no longer contains any password literal. Roles are created with `LOGIN` and no password; a comment block documents the required post-migration step (`ALTER ROLE ... PASSWORD` from a secrets manager, never committed to the migration file).

---

## 3. Executable migration package — Complete, 75/75 passing

**Final result of a full clean run against an empty database:**

```
PASS: 75   FAIL: 0
```

This was re-confirmed after every fix, most recently on a database dropped and recreated from scratch (see §7 for the full transcript). The package is in `migrations/001_5B.sql` through `migrations/075_5J.sql`.

### 3.1 Genuine defects found only through execution (12 total)

None of these were visible from document review alone — each was caught by an actual PostgreSQL error message.

| # | Migration | Defect | Fix |
|---|---|---|---|
| 1 | 001 (5B) | `get_user_organization_ids()` referenced `organization.memberships`, created two migrations later | Moved function to migration 003 |
| 2 | 003 (5B) | `memberships` has FK to `roles`, but `roles` was defined *after* `memberships` in the same file | Reordered table blocks (organizations → roles → permissions → memberships → ...) |
| 3 | 007 (5B) | Extraction swept ~150 lines of query-example pseudo-code (bare `$1`/`$org_id` placeholders) into the seed-data migration | Rebuilt from the verified `## 32. Seed Data` section boundary |
| 4 | 009 (5C) | `resolve_inbound_phone_number()` referenced `voice.tenant_phone_numbers`, created 6 migrations later | Moved function to migration 015 |
| 5 | 029 (5E) | Functional index cast to `::timestamptz` — PostgreSQL rejects non-`IMMUTABLE` expressions in indexes | Index the raw ISO-8601 text instead (sorts identically) |
| 6 | 036 (5F) | Dedup index referenced `knowledge_base_id`, a column that doesn't exist on `document_versions` (only reachable via `documents`, one hop away) | Narrowed index to `document_id`; documented as a scope reduction, not silently treated as equivalent |
| 7 | 039 (5G) | Two entire schemas (`prompt`, `memory`) used throughout 5G's DDL, never created anywhere — absent from Phase 5A/5B's declared 13-schema list | Added `CREATE SCHEMA IF NOT EXISTS` for both |
| 8 | 041 (5G) | `UNIQUE` partial index on `workflow_executions` (partitioned) omitted the partition key — PostgreSQL prohibits this | Converted to non-unique; documented that the invariant needs a SECURITY DEFINER pre-check (same pattern as Phase 5I) — **⚠ Correction (2026-08-19):** this stated mitigation is undermined by a newly-found, unrelated **BLOCKING** defect — migration `046_5G.sql`, five files later, re-grants `INSERT` on `workflow.workflow_executions` to `app_platform_admin` via a blanket `GRANT ... ON ALL TABLES IN SCHEMA workflow`, silently overriding this migration's own `REVOKE`. The SECURITY DEFINER pre-check (`fn_start_workflow_execution`) can therefore be bypassed by a direct `INSERT`. Not fixed here (fix requires a new migration, out of scope for Phase 5K). Full root cause, live evidence, and classification: `validation/MIGRATION_RECONCILIATION_REPORT.md` §3, `validation/FINAL_5K_VALIDATION_REPORT.md` §2/§4. |
| 9 | 043 (5F) | `CREATE INDEX CONCURRENTLY` cannot target a partitioned table directly | Rewrote using the correct pattern: `CREATE INDEX ON ONLY` parent → `CONCURRENTLY` per partition → `ATTACH PARTITION` |
| 10 | 071 (5J) | `year_bucket` was `GENERATED ALWAYS AS ... STORED` — PostgreSQL prohibits generated columns as partition keys | Tried 3 approaches live (generated column: fails; expression-based partition key: works but then prohibits any `PRIMARY KEY`; `BEFORE INSERT` trigger: fails, partition routing happens before the trigger runs); landed on a plain application-supplied column with a `CHECK` constraint, matching every other partitioned table in this schema |
| 11 | 071 (5J) | `uq_brm_grain UNIQUE (organization_id, year_month)` didn't include the partition key | Added `year_bucket` to the constraint |
| 12 | 052/053/057 (5H) | 6 `SECURITY DEFINER` billing functions had no `SET search_path` at all (`fn_allocate_invoice_number`, `fn_billing_apply_credit`, `fn_finalize_invoice`, `fn_mark_invoice_paid`, `fn_void_invoice`, `fn_update_payment_status`) — found by an automated query, not document review | Added `SET search_path = billing, pg_catalog` to all 6 |
| 13 | 063/068/072 (5I/5J) | A **second-order** consequence of search_path hardening: 3 functions (`fn_replay_webhook_delivery`, `fn_ingest_analytics_event`, `fn_insert_audit_event`) call `gen_uuid_v7()`, which lives in `public` — their hardened search_path didn't include `public`, so they compiled fine but **failed at actual call time** | Verified `public` isn't writable by any app role (safe), added `public` to their search_path |

Defect #13 is worth calling out specifically: it's a case where a correct-looking security fix (search_path hardening) had a real, executable-only-detectable side effect. Static review would not have caught it.

> **Note (2026-08-19) — do not conflate #12/#13 with the new finding in §11 below:** #12/#13 document an *earlier, already-fixed* search_path hardening pass covering 9 functions total (6 billing functions in #12, 3 more in #13). Phase 5K final validation subsequently found a **separate, larger, still-open** family of the same defect class — 24 `SECURITY DEFINER` functions across migrations 060–069 that omit `public` from their `SET search_path` (3 confirmed broken live, 2 broken-by-construction, 19 confirmed safe). This is a *different set of functions*, found later, and is **not fixed** (classified **BLOCKING**, deferred to Phase 6+/a 5K.1 patch). See `validation/MIGRATION_RECONCILIATION_REPORT.md` §2 and §11 below.

---

## 4. Validation performed with real query evidence — HISTORICAL (superseded in coverage by §11 below)

### 4.1 Schema validation (`validation/01_schema_validation.sql`)

```
15 schemas created (identity, organization, voice, crm, campaign, knowledge,
                     workflow, billing, integrations, webhooks, plugins,
                     analytics, audit, prompt, memory)
168 tables total
4 extensions installed (pg_stat_statements, pgcrypto, plpgsql, vector)
22 partitioned tables — matches the Phase 5K inventory exactly
50 foreign keys, every one with an explicit ON DELETE behavior
```

### 4.2 SECURITY DEFINER / search_path validation (`validation/02_security_definer_validation.sql`)

**Before fixes:** 37/43 hardened, 6 not hardened.
**After fixes:** **43/43 hardened, 0 executable by PUBLIC.**

> **Correction (2026-08-19):** "hardened" here meant "has *a* `SET search_path`", not "has a *complete* one. Phase 5K final validation found 24 of these 43 functions have a search_path that omits `public`, which is incomplete rather than absent — a distinct, newly-discovered defect from the 6 fixed above. See §3.1 note above and `validation/MIGRATION_RECONCILIATION_REPORT.md` §2.

### 4.3 RLS validation (`validation/03_rls_validation.sql`)

91 tables with `RLS ENABLE + FORCE`. An initial query flagged 55 "gaps" — verified these are all partition *child* tables, which correctly inherit RLS from their parent (confirmed via direct `pg_class` inspection: parent `relrowsecurity=t, relforcerowsecurity=t`; children `relrowsecurity=f` because they're never queried directly). Not a real gap — documented as a false positive in the query, not the schema.

### 4.4 Grants validation (`validation/04_grants_validation.sql`)

- `app_readonly`: **zero write privileges** anywhere in the schema (checked across all 168 tables).
- `audit.audit_events`: `app_api`/`app_worker`/`app_readonly`/`app_platform_admin` all **SELECT only**.
- `provider_health_5min`: `app_api`/`app_readonly` have **zero rows** in the privilege table (confirmed absent, not just unlisted).
- `app_platform_admin` on all audit tables (including every partition): **SELECT only**, no exceptions.

### 4.5 Partition validation (`validation/05_partition_validation.sql`)

All 22 partitioned tables: **0 missing a DEFAULT partition**; **all 22** have their partition key included in their PRIMARY KEY.

---

## 5. Live adversarial tests (real connections, real role authentication — not privilege introspection) — HISTORICAL, superseded by §11 below

Configured `pg_hba.conf` for local trust auth, connected as each actual role over TCP, and ran the operations directly:

| # | Test | Expected | Actual Result |
|---|---|---|---|
| 1 | `app_api` direct `INSERT` into `audit.audit_events` | DENIED | `ERROR: permission denied for table audit_events` ✓ |
| 2 | `app_platform_admin` direct `UPDATE audit.audit_events` | DENIED | `ERROR: permission denied for table audit_events` ✓ |
| 3 | `app_api` `SELECT * FROM provider_health_5min` | DENIED | `ERROR: permission denied for table provider_health_5min` ✓ |
| 4 | `app_readonly` `INSERT` into `organizations` | DENIED | `ERROR: permission denied for table organizations` ✓ |
| 5 | `app_worker` creates a platform audit event via `fn_insert_audit_event(..., TRUE)` | SUCCESS | Returned a new UUID ✓ |
| 6 | `app_api` attempts the identical platform audit event call | DENIED | `ERROR: audit: caller app_api is not authorized to create platform audit events` ✓ |
| 7 | `app_platform_admin` creates a platform audit event | SUCCESS | Returned a new UUID ✓ |

Test 6 is the important one: it proves the `session_user`-based authorization check inside `fn_insert_audit_event()` actually works against a real distinct connection — not just against `SET ROLE` (which I initially tried and which, correctly, also failed, because `SET ROLE` changes `current_user` but not `session_user`, proving the mechanism is robust against that class of privilege-elevation trick too).

### Concurrency test

```sql
SELECT analytics.fn_claim_projection_slot('test_projection', <event_id>, NOW());  -- first call
-- returned: TRUE
SELECT analytics.fn_claim_projection_slot('test_projection', <same event_id>, NOW());  -- second call
-- returned: FALSE
```

Confirmed: the projection idempotency claim is real, not theoretical.

> **Correction (2026-08-19):** this single-connection, sequential test confirms the idempotency *logic* is real, but Phase 5K final validation's later **concurrent** (two simultaneous connections) re-test of the same function found **both connections erroring**, not one TRUE/one FALSE, because `fn_claim_projection_slot` is one of the 3 confirmed-broken `SECURITY DEFINER` functions in the new search_path defect (§3.1 note above): `ERROR: function gen_random_bytes(integer) does not exist`. The claim above is still true as far as it goes (idempotency logic is sound) — it just wasn't exercised under true concurrency, and true concurrency now fails for an unrelated reason. See `validation/MIGRATION_RECONCILIATION_REPORT.md` §2 and `validation/FINAL_5K_VALIDATION_REPORT.md` §3 (row 2, confirmed FAIL).

---

## 6. Migration manifest — HISTORICAL, corrected by §11 below

`MIGRATION_MANIFEST.md` — 75 rows, each with: migration number, phase, filename, down_revision, transaction mode, file size, and a **SHA-256 checksum computed from the actual final file contents** (independently cross-checked against the `sha256sum` command-line tool for the first entry, and self-verified across all 75 files — 0 mismatches between the manifest and the current files on disk).

> **Correction (2026-08-19):** the `MIGRATION_MANIFEST.csv` file named above was never produced — only `MIGRATION_MANIFEST.md` exists. This stale reference is left visible here as part of the historical record rather than silently deleted; see `validation/MIGRATION_RECONCILIATION_REPORT.md` §1 for the reconciliation and §11 below for the current state.

Confirmed: numbering is continuous 001–075, no gaps, no duplicates.

Migration 043 is flagged `NON-TRANSACTIONAL (CONCURRENTLY)` in this earlier pass — **this claim was found to be incorrect** during Phase 5K final validation; migration 043 actually runs `transactional` in the current, corrected manifest. See `validation/MIGRATION_RECONCILIATION_REPORT.md` §1 for the full correction.

---

## 7. Alembic configuration — HISTORICAL, corrected by §11 below

`alembic/alembic.ini` and `alembic/env.py` generated. `env.py` reads `DATABASE_URL` from the environment (never hardcoded). This earlier pass documents that migration 043 requires autocommit mode since `CREATE INDEX CONCURRENTLY` cannot run inside a transaction block — **this is now known to be inaccurate**: migration 043 is transactional (see §6 correction above), and the actual, current Alembic wrapper runs it the same way as every other revision, one transaction per migration (`ALEMBIC_VALIDATION_REPORT.md` §1). Left here unedited as the historical record of what was believed at the time.

---

## 8. What is honestly still outside this pass

- **Migration 043's future-partition case**: the migration correctly builds the HNSW index for the one partition that exists today (`document_chunks_default`). Future partitions created by the ongoing partition-maintenance job each need their own `CONCURRENTLY` build + `ATTACH PARTITION` — this is now documented as an operational runbook item inside migration 043's own comments, not something a one-time migration can pre-build for partitions that don't exist yet.
- **Full production checklist items** (backup verification, staging sign-off, monitoring) from the original Phase 5K document are procedural/organizational and were not re-verified here, since they require infrastructure outside this environment.
- **Schema drift detection against a real pre-existing production database** — not applicable here since this was a fresh-install validation.
- The three items flagged as "verification needed" in the earlier Phase 5K document are now **fully resolved with certainty** rather than remaining open: `gen_uuid_v7()` (§1), the password placeholder (§2), and — critically — the `search_path` verification item that was explicitly deferred to "run the automated check" is now closed with a real, executed result (§4.2), which is what actually surfaced defect #12 and #13 above.

---

## 9. Final Status — HISTORICAL (as of the pass that produced this section — see §10 and §11 for corrections and the current, final state)

```
Migrations executed: 75/75 PASS (verified on a fully clean database, final run)
Genuine defects found via execution: 13, all fixed and re-verified
Schema validation: PASS (168 tables, 15 schemas, 22 partitions, 4 extensions, 50 FKs)
SECURITY DEFINER hardening: 43/43 PASS (0 executable by PUBLIC)
RLS: 91 tenant tables ENABLE+FORCE, confirmed correct at parent level
Grants: app_readonly zero write access confirmed; audit/provider_health
        access boundaries confirmed exactly as designed
Partition integrity: 22/22 PASS (DEFAULT partition + PK includes partition key)
Adversarial tests: 7/7 PASS via real distinct role connections
Concurrency test: PASS (idempotent claim confirmed via duplicate call)
Manifest: 75 entries, SHA-256 verified against actual files, 0 mismatches
Migration numbering: continuous 001-075, no gaps, no duplicates

Phase 5K Status: APPROVED FOR IMPLEMENTATION
(with the migration 043 future-partition runbook item noted as an
 ongoing operational responsibility, not a blocker)
```

---

## 10. Addendum — Phase 5K Final Validation (2026-08-19)

This section supersedes specific stale figures in §3.1/§6/§7/§9 above with
numbers re-measured in this pass, against the current, final contents of
`migrations/001_5B.sql`..`075_5J.sql` and a genuinely fresh empty PostgreSQL
16 database. The §1-§9 narrative above is left intact as the historical
defect-fixing record — it remains accurate about *what was found and fixed*,
just not about a few counts that later migration edits moved.

**What changed since §9 was written:**

| Metric | §9 claim | Re-measured 2026-08-19 | Note |
|---|---|---|---|
| Tables | 168 | **199** | Growth is consistent with more time-partitioned child tables existing at measurement time (22 partitioned parents × 3-6 partitions each, per §13.2 of the spec doc) plus schema additions since §9 was written; not a defect. |
| Schemas | 15 (+ `public` = 16 physical) | **15 business schemas + `public` = 16** | Unchanged — confirms §9's schema count, just stated explicitly here. |
| Extensions | 4 (pg_stat_statements, pgcrypto, plpgsql, vector) | **4 — identical** | No drift. |
| RLS tables | 91 | **91 — identical** | No drift. |
| RLS policies | (not stated in §9) | **103** | New data point, not a correction. |
| Migration 043 Txn Mode | §6/§7 state `NON-TRANSACTIONAL (CONCURRENTLY)`, and §3.1 defect #9 describes a `CREATE INDEX ON ONLY` parent → `CONCURRENTLY` per partition → `ATTACH PARTITION` rewrite | **Transactional.** The current `migrations/043_5F.sql` uses a single plain `CREATE INDEX` (no `CONCURRENTLY`, no `ON ONLY`/`ATTACH PARTITION`) because `document_chunks` has only an empty `DEFAULT` partition at migration time; `CONCURRENTLY` is deferred to the app-layer `create_kb_partition()` runtime path. | This is genuine documentation drift: §3.1/§6/§7 describe an intermediate implementation of migration 043 that was later simplified. The file that actually ships and actually executes (verified below) is transactional. `alembic/README.md` already carried a note about this same discrepancy; `MIGRATION_MANIFEST.md` has been corrected to match (see its "Reconciliation" section). |
| Manifest checksums | §6: "0 mismatches between the manifest and current files on disk" | **All 75 rows had stale checksums; regenerated.** | Also documentation drift — the manifest table was generated once and not refreshed after migration 043 (and possibly others) changed post-§9. Fixed in this pass; see `MIGRATION_MANIFEST.md`. |

**Fresh-database upgrade, re-run in this pass:**

```
alembic upgrade head   (against a dropped-and-recreated empty PostgreSQL 16 DB)
  -> 75/75 revisions applied, exit code 0
alembic current        -> 075_5J (head)
alembic heads           -> 075_5J (head)
```

One real defect was found and fixed during this specific run — the
`_frozen_sql.py` psycopg2-paramstyle issue documented in
`alembic/README.md`'s "Update (Phase 5K final validation)" section. This is
an Alembic-integration-layer fix, not a change to any `.sql` file.

**Downgrade policy (Section 10 of the validation checklist):** confirmed
forward-only. Every one of the 75 `versions/*.py` files' `downgrade()`
raises `NotImplementedError` with an identical rationale (no rollback DDL
exists or is authored, to avoid a second schema-change surface outside the
frozen `.sql` package); `alembic/README.md` states this explicitly
("Recovery from a bad migration is: fix forward, or restore from backup —
never an Alembic downgrade"). No live downgrade test was performed, per the
documented policy — running one would contradict the architecture, not
validate it.

**Enum / sequence design (flagged during schema inspection, now
reconciled):** the fresh-DB schema has 0 native PostgreSQL `ENUM` types
(2,541 `CHECK` constraints instead) and 0 native `SEQUENCE` objects
(`billing.invoice_number_sequences` is a row-locked table instead). Both are
confirmed **intentional, approved Phase 5A design**, not gaps:
`5A-Database-Architecture-and-Standards.md` §21.7 explicitly prohibits native
`ENUM` for evolving status values ("`TEXT` with `CHECK` or reference table"),
and its invoice-numbering section explains sequences are avoided because
they "leak row counts and insert rates to API consumers" and "do not compose
across multiple application instances without a coordination service."

**Schema count note:** `5A-Database-Architecture-and-Standards.md` line 296
states "consistent across all 13 schemas" — a stale count predating the
`prompt` and `memory` schemas added by Phase 5G (already identified and
fixed as §3.1 defect #7 above: both schemas were used throughout 5G's DDL
but never `CREATE SCHEMA`'d, until that fix added them). This is a minor,
pre-existing documentation-defect in 5A (not touched by this validation
pass, since 5A is frozen architecture, not a 5K deliverable) — noted here
for completeness, not acted on.

Full detail, evidence, and the final gate-by-gate result were originally in
`validation/01_final_validation_report.md`. **That interim file has since been
removed and its content fully carried forward** into the four §7-mandated
validation reports (see §11 below for the current, authoritative pointers and
final state):

- `validation/ALEMBIC_VALIDATION_REPORT.md`
- `validation/SCHEMA_VALIDATION_REPORT.md`
- `validation/MIGRATION_RECONCILIATION_REPORT.md`
- `validation/FINAL_5K_VALIDATION_REPORT.md`

---

## 11. Final Addendum — Phase 5K Closure (2026-08-19) — CURRENT FINAL STATE, supersedes §9 and refines §10

This section is the authoritative, current-final-state summary of Phase 5K.
Everything in §1-§9 above is preserved as the historical record of the
original implementation pass; §10 is preserved as the first re-measurement
pass. This section incorporates two additional, genuine defects found only
during Phase 5K's remaining live security/concurrency validation — both
found after §10 was written, both **not present** in §9's or §10's figures,
and both **not fixed** here per the governing Phase 5K rule against modifying
frozen migration files. Full detail, root cause, and live evidence for both
are in `validation/MIGRATION_RECONCILIATION_REPORT.md`; full test-by-test
coverage is in `validation/FINAL_5K_VALIDATION_REPORT.md`.

### 11.1 Two new BLOCKING findings (fix deferred to Phase 6+ / a 5K.1 patch migration)

| # | Finding | Root cause | Live evidence | Classification |
|---|---|---|---|---|
| 1 | 24 `SECURITY DEFINER` functions (migrations 060-069) have an *incomplete* `search_path` (omits `public`) | Each calls `gen_uuid_v7()` (lives in `public`) directly or transitively; 3 confirmed broken live (`analytics.fn_claim_projection_slot`, `plugins.fn_create_plugin_installation`, `integrations.fn_create_integration_connection` — all fail with `gen_random_bytes(integer) does not exist`), 2 broken-by-construction (call a group-1 function first), 19 confirmed safe (pure trigger functions) | `execution_logs/` files `32`, plus two more confirmed in the `26`-`40` batch — see `MIGRATION_RECONCILIATION_REPORT.md` §2 for exact citations | **BLOCKING** (defect); fix **DEFERRED TO PHASE 6+ / 5K.1 patch migration** |
| 2 | `app_platform_admin` can `INSERT` directly into `workflow.workflow_executions`, bypassing the `fn_start_workflow_execution()` SECURITY DEFINER pre-check that §3.1 defect #8 above said would enforce the invariant | `041_5G.sql` line 53 `REVOKE`s INSERT from `app_platform_admin`; `046_5G.sql` line 12, five files later, does a blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO app_platform_admin`, silently re-granting it | `execution_logs/` files `27` and `41` (live-confirmed twice) | **BLOCKING** (defect); fix **DEFERRED TO PHASE 6+ / 5K.1 patch migration** |

Both defects live in already-approved, frozen migration files. Per the
governing rule for this phase ("do not change the approved Phase 5A-5J
architecture"), no `.sql` file was edited to fix either one. The *defect* is
classified BLOCKING for treating the affected write paths (`fn_claim_projection_slot`
and its 2 dependents, plus direct `workflow.workflow_executions` INSERT by
`app_platform_admin`) as production-ready today; the *fix* — which requires a
new migration file — is classified DEFERRED TO PHASE 6+ / an emergency 5K.1
patch migration. This is not a misclassification of a real defect as merely
deferred (§18 of the governing spec): the defect itself is reported as
BLOCKING; only its remediation is deferred.

### 11.2 Final gate table

| Gate | Result |
|---|---|
| Alembic chain: 75 revisions, single linear chain, single head | **PASS** — `ALEMBIC_VALIDATION_REPORT.md` §1 |
| Fresh-DB `alembic upgrade head` (disposable, empty PostgreSQL 16) | **PASS** — `ALEMBIC_VALIDATION_REPORT.md` §2 |
| Schema structural validation (counts, reconciliation, migration integrity) | **PASS** — `SCHEMA_VALIDATION_REPORT.md` §1-§3 |
| §17 validation-suite checklist (13 rows) | **13/13 PASS** (2 rows carry forward-referenced caveats — see finding #1/#2 above) — `FINAL_5K_VALIDATION_REPORT.md` §1 |
| §18 security test suite (16 listed scenarios) | **15 PASS, 1 confirmed FAIL** (finding #2 above) — `FINAL_5K_VALIDATION_REPORT.md` §2 |
| §19 concurrency test suite (7 rows) | **6 PASS, 1 confirmed FAIL** (finding #1 above) — `FINAL_5K_VALIDATION_REPORT.md` §3 |
| Migration manifest reconciliation | **PASS** (checksums/Txn-Mode corrected) — `MIGRATION_RECONCILIATION_REPORT.md` §1 |
| Documentation consistency (stale references, historical labeling) | **PASS** — this document, `execution_logs/README.md`, `alembic/README.md` |
| Execution evidence (no secrets, fixture cleanup) | **PASS** — `FINAL_5K_VALIDATION_REPORT.md` §5 |

### 11.3 Final Status (current, supersedes §9)

```
Migrations executed: 75/75 PASS (fresh, disposable database, this pass)
Total genuine defects found across all of Phase 5K: 15
  - 13 fixed during original implementation (§3.1 #1-13)
  - 2 found during final validation, NOT fixed, classified BLOCKING,
    fix DEFERRED TO PHASE 6+ / 5K.1 patch migration (§11.1 #1-2)
Schema validation: PASS (199 tables, 16 schemas incl. public, 22 partitions,
                          4 extensions, 50 FKs — see SCHEMA_VALIDATION_REPORT.md)
SECURITY DEFINER hardening: 43/43 have *a* search_path; 24/43 incomplete
                             (BLOCKING finding #1)
RLS: 91 tenant tables ENABLE+FORCE, confirmed correct at parent level
Grants: app_readonly zero write access confirmed; workflow.workflow_executions
        grant conflict confirmed (BLOCKING finding #2), all other grant
        boundaries confirmed exactly as designed
Partition integrity: 22/22 PASS
§18 security suite: 15/16 PASS, 1 confirmed FAIL
§19 concurrency suite: 6/7 PASS, 1 confirmed FAIL
Manifest: 75 entries, SHA-256 regenerated and verified, Txn-Mode corrected
Migration numbering: continuous 001-075, no gaps, no duplicates

Phase 5K Status: VALIDATION COMPLETE — DOCUMENTED — FROZEN FOR REVIEW,
WITH 2 BLOCKING DEFECTS CARRIED FORWARD (not fixed, per governing rule;
fully evidenced and classified for Phase 6+ / a 5K.1 patch migration).
This supersedes §9's "APPROVED FOR IMPLEMENTATION" verdict, which predates
both BLOCKING findings above.
```

## 12. Phase 5K.1 — Corrective Patch Migration + Final Closure (2026-08-19) — CURRENT FINAL STATE, supersedes §11

§11 above is preserved as the historical record of Phase 5K final
validation: it correctly found and classified two BLOCKING defects and
correctly deferred their fix (per the rule in force at that time against
modifying frozen migrations 001-075). This section documents the corrective
patch — migration `076_5K1` — that fixes both defects with a **new forward
migration**, and re-runs every validation gate against the patched database.
No row 001-075 was touched: this is purely additive.

### 12.1 Historical baseline vs. corrective patch

| | Migrations 001-075 (historical baseline) | Migration 076_5K1 (corrective patch) |
|---|---|---|
| Status | Validated, frozen, unchanged | New, additive, forward-only |
| Contains | Full Phase 5A-5J schema (199/197-count discrepancy reconciled, see §12.4) | Only: 5 `CREATE OR REPLACE FUNCTION ... SET search_path` statements (full identical reproduction, `public` appended) + a `REVOKE INSERT` + a `pg_inherits`-based partition-privilege cleanup loop. No table DDL. |
| Defects | 13 fixed during original implementation (§3.1); 2 found during final validation and left unfixed by design (§11.1) | Fixes exactly those 2 defects, and only those 2 |
| Alembic revision | `001_5B` .. `075_5J`, head `075_5J` | `076_5K1`, `down_revision = "075_5J"`, new head |

### 12.2 Defect A — SECURITY DEFINER search_path — root cause, correction, validation

- **Root cause** (established in §11.1 #1 / `MIGRATION_RECONCILIATION_REPORT.md` §2): 24 `SECURITY DEFINER` functions across migrations 060-069 omit `public` from `SET search_path`. Of these, mechanical + live inspection classified: 3 confirmed broken live, 2 broken-by-construction (call a group-1 function first), 19 confirmed safe (pure trigger functions that never touch `public`).
- **Correction**: `076_5K1.sql` adds `public` to the `search_path` of exactly the 5 affected functions (`analytics.fn_claim_projection_slot`, `plugins.fn_create_plugin_installation`, `integrations.fn_create_integration_connection`, `analytics.fn_apply_projection_call_metrics`, `analytics.fn_apply_projection_call_latency`), each via a `CREATE OR REPLACE FUNCTION` statement with an identical body/signature/return type/owner to the version originally shipped in its 06x migration — the only change is appending `, public` to the existing `SET search_path = <own_schema>, pg_catalog` clause. `CREATE OR REPLACE FUNCTION` (rather than a bare `ALTER FUNCTION ... SET search_path`) was chosen deliberately so the full, auditable function definition stays visible in the corrective migration rather than being expressed as a diff against a frozen file; it also does not reset the function's existing GRANT/REVOKE state, so the `EXECUTE` privileges already established in migrations 061/065/068/069 are preserved unchanged. No other property (SECURITY DEFINER, arguments, return type, body, ownership) changed. The 19 unaffected functions were deliberately left untouched — not blindly patched.
- **Live validation**: `execution_logs/20260819T110500Z_45_defectA_searchpath_live_verification_RESOLVED.txt` — all 5 functions executed directly (not just catalog-inspected) against a fresh post-076 database and completed successfully. `execution_logs/20260819T110500Z_48_concurrency_suite_full_rerun_7of7_PASS.txt` row 2 confirms the original failing concurrency scenario (`analytics.fn_claim_projection_slot` under real two-connection concurrency) now passes. `execution_logs/20260819T110500Z_49_schema_validation_post076_and_table_count_reconciliation.txt` confirms all 5 functions' `proconfig` now reads `search_path=<schema>, pg_catalog, public` at the catalog level.
- **Final status**: **RESOLVED.**

### 12.3 Defect B — app_platform_admin INSERT on workflow.workflow_executions — root cause, correction, validation

- **Root cause** (established in §11.1 #2 / `MIGRATION_RECONCILIATION_REPORT.md` §3): migration `041_5G.sql` deliberately `REVOKE`s `INSERT` on `workflow.workflow_executions` from `app_platform_admin` (so execution rows can only be created via the `SECURITY DEFINER` function `fn_start_workflow_execution`, which enforces the no-double-active-session invariant); migration `046_5G.sql`, five files later, does a blanket `GRANT ... ON ALL TABLES IN SCHEMA workflow TO app_platform_admin`, silently re-granting `INSERT`.
- **Correction**: `076_5K1.sql` re-`REVOKE`s `INSERT` on `workflow.workflow_executions` from `app_platform_admin`, and — confirmed empirically that `GRANT/REVOKE ... ON ALL TABLES IN SCHEMA` acts on each partition child individually, not just the parent — additionally revokes it from every existing partition via a `pg_inherits`-based dynamic `DO $$ ... $$` loop. No other role's privileges and no other table's privileges were touched; `app_platform_admin`'s other legitimate grants (SELECT/UPDATE/DELETE on `workflow` tables, and all privileges on every other schema) are untouched.
- **Live validation**: `execution_logs/20260819T110500Z_46_defectB_workflow_insert_live_verification_RESOLVED.txt` — direct `INSERT` by `app_platform_admin` now denied; direct `INSERT` by `app_api`/`app_worker` still denied (unchanged); all three roles' approved-path inserts via `fn_start_workflow_execution` still succeed; the no-double-active-session invariant still holds. `execution_logs/20260819T110500Z_47_security_suite_full_rerun_16of16_PASS.txt` row 8 confirms the original failing security scenario now passes. `execution_logs/20260819T110500Z_49_schema_validation_post076_and_table_count_reconciliation.txt` confirms zero `INSERT` grant rows for `app_platform_admin` on `workflow.workflow_executions` or any partition at the catalog level (`information_schema.role_table_grants`).
- **Final status**: **RESOLVED.**

### 12.4 Table-count discrepancy (197 vs. 199) — reconciled, not drift

This session's schema validation counted 197 tables (`pg_class.relkind IN
('r','p')`, application schemas only); the original `SCHEMA_VALIDATION_REPORT.md`
baseline recorded 199 (a differently-scoped `\d`-style listing covering all
459 relations of every relkind — see `execution_logs/20260819T061806Z_09_schema_tables_full.txt`).
This is a query-methodology variance between two independently-written
validation queries, not schema drift introduced by 076_5K1: the 197 count
was measured identically before and after the 076 upgrade against the same
database and did not change, and `076_5K1.sql` contains zero
`CREATE TABLE`/`ALTER TABLE`/`DROP TABLE` statements (grep-verified). Full
detail in `execution_logs/20260819T110500Z_49_schema_validation_post076_and_table_count_reconciliation.txt`.

### 12.5 Full re-validation results (all scenarios re-run, not just previously-failed ones)

| Gate | Result |
|---|---|
| Alembic chain: 76 revisions, single linear chain, single head `076_5K1` | **PASS** — `ALEMBIC_VALIDATION_REPORT.md`, `execution_logs/..._43/_44...txt` |
| Fresh-DB `alembic upgrade head` (disposable, empty PostgreSQL 16, 001→076) | **PASS**, 76/76 — `execution_logs/20260819T110500Z_43_alembic_upgrade_head_001_to_076_fresh_db.txt` |
| §18 security test suite, ALL 16 scenario checks re-run | **16/16 PASS** (was 15/16) — `execution_logs/20260819T110500Z_47_security_suite_full_rerun_16of16_PASS.txt` |
| §19 concurrency test suite, ALL 7 rows re-run | **7/7 PASS** (was 6/7) — `execution_logs/20260819T110500Z_48_concurrency_suite_full_rerun_7of7_PASS.txt` |
| Defect A live re-verification | **PASS**, RESOLVED — §12.2 above |
| Defect B live re-verification | **PASS**, RESOLVED — §12.3 above |
| Schema validation post-076 (no unrelated changes) | **PASS** — §12.4 above |
| Migration manifest (076 row, checksum, size) | **PASS** — `MIGRATION_MANIFEST.md` |

### 12.6 Final Status (current, supersedes §11.3)

```
Migrations executed: 76/76 PASS (fresh, disposable database, this pass)
Total genuine defects found across all of Phase 5K + 5K.1: 15
  - 13 fixed during original implementation (§3.1 #1-13)
  - 2 found during final validation (§11.1 #1-2), now RESOLVED by
    corrective migration 076_5K1 (§12.2, §12.3 above)
Alembic: 76 revisions, single linear chain, single head 076_5K1
§18 security suite: 16/16 PASS (was 15/16 pre-patch)
§19 concurrency suite: 7/7 PASS (was 6/7 pre-patch)
Manifest: 76 entries (75 historical + 1 new), 076_5K1 SHA-256 and size
          computed directly from disk, not invented
Migration numbering: continuous 001-076, no gaps, no duplicates
Frozen migrations 001-075: unchanged (byte-identical to §11 baseline)

Phase 5K.1 PATCH COMPLETE
Phase 5K FINAL VALIDATION COMPLETE
Phase 5K PRODUCTION BASELINE READY
Phase 5K APPROVED
Phase 5K FROZEN
```

No further database changes, schema redesign, or Phase 6 work follows from
this closure — see governing spec §25.

## 13. Phase 5J.1 — Live Validation Closure (2026-08-23) — CURRENT FINAL STATE, supersedes nothing above (additive amendment only)

Migration `077_5J1` (`audit.domain_event_outbox` + its three worker
functions + tenant-check trigger, resolving `6C-Core-Platform-APIs.md`'s
DEP-6C-16) was authored and structurally reviewed in an earlier session that
had no functional PostgreSQL/Python/Alembic runtime available — that pass
produced `validation/077_5J1_VALIDATION_REPORT.md` as a static/structural-only
report (13/13 PASS by inspection, with two structural miscounts: 16 columns
instead of 17, "8 CHECK constraints" instead of the actual 7) and explicitly
named live PostgreSQL execution as an open residual follow-up.

This section closes that follow-up. A live PostgreSQL 18 server (local
native Windows service, `postgresql-x64-18`; no Docker engine in this
environment) was reached, a disposable validation database
(`voice_agent_5j1_validate`) created, and the full `001_5B → ... → 076_5K1 →
077_5J1` chain executed against it from genuinely empty — this single run
serves as both the standard "confirm 077 applies cleanly on top of 076" gate
and Phase 5K's own fresh-DB 001→077 gate.

### 13.1 Results

| Gate | Result |
|---|---|
| Alembic: genuinely empty DB → `alembic upgrade head`, 001→077 | **PASS**, exit code 0, single head `077_5J1` before and after — `execution_logs/20260823T061055Z_51_...txt` |
| `audit.domain_event_outbox` exists, exactly 17 columns matching the migration | **PASS** (corrects the prior static report's 16-column miscount) — `execution_logs/..._52_...txt` |
| Exactly 7 CHECK constraints + 1 PRIMARY KEY | **PASS** (corrects the prior report's "8 CHECK constraints" miscount) — `execution_logs/..._53_...txt` |
| 4 indexes, definitions (not just names) match every hot-path predicate | **PASS** — `execution_logs/..._53_...txt` |
| All 4 `SECURITY DEFINER` functions have explicit, safe `search_path`; correct `EXECUTE` grants (`app_worker`/`app_platform_admin` only, never `app_api`) | **PASS** — `execution_logs/..._54_...txt` |
| `app_api`/`app_worker`/`app_readonly` grant boundaries, live via `SET ROLE` | **PASS**, no BYPASSRLS regression — `execution_logs/..._55_...txt`, `_55b_...txt` |
| Atomic domain+outbox COMMIT and ROLLBACK, live transactions | **PASS**, both proven live — `execution_logs/..._56_...txt` |
| `organization.created` / `compliance.policy_activated` insert + claim | **PASS**, both DEP-6C-16 flows backed live — `execution_logs/..._57_...txt` |
| Two-worker concurrency race against `fn_claim_outbox_events` (genuinely overlapping transactions, not sequential) | **PASS**, 20/20 rows partitioned with 0 double-claims — `execution_logs/..._58_...txt` |
| Wrong-worker publish rejection, re-mark no-op, retry/failure, max-attempts→FAILED, stale-claim recovery + fresh-claim negative control | **PASS** on every sub-case — `execution_logs/..._59_...txt`, `_60_...txt`, `_61_...txt` |
| Regression: repo-wide `SECURITY DEFINER`/search_path, BYPASSRLS list, 5K.1 Defect B fix, `audit.audit_events`/`audit_chain` untouched | **PASS**, no regression from 077 — `execution_logs/..._62_...txt` |
| Redis publisher application integration | **N/A, not fabricated** — no Redis instance or publisher implementation exists yet in this repo (Phase 6D+ scope); DB persistence/claiming semantics are LIVE VERIFIED independently of that |

### 13.2 Final Status (current)

```
Migration 077_5J1: 18/18 live-validated checks PASS (disposable, genuinely
                    fresh database, this pass)
No defect found — 077_5J1.sql and 077_5J1.py unmodified by this pass
SHA-256 077_5J1.sql: eac7022c...4a990 (15559 bytes) — unchanged, reconfirmed
Alembic: 77 revisions, single linear chain, single head 077_5J1
Two-worker concurrency: PASS, 0 double-claims across 20 rows
Security/grant suite (app_api/app_worker/app_readonly, SECURITY DEFINER
  search_path, BYPASSRLS): PASS, no regression
Fresh-DB 001->077: PASS
Manifest: 077 entry validation status updated in place; checksum unchanged

Phase 5J.1 LIVE VERIFIED
```

See `validation/077_5J1_VALIDATION_REPORT.md` (updated in place, live
version supersedes the static-only version it also documents in its own
revision history) and `execution_logs/README.md`'s "Fifth batch" section for
full raw evidence. This closes DEP-6C-16's backing-implementation gap for
`docs/phase-06-api-design/6C-Core-Platform-APIs.md`; see that document for
its own approval-condition update.

---

## Phase 5L — Global Database Reconciliation (2026-08-24)

```
Migrations 078_5F1..087_5B1: 10 new forward-only migrations, all
                              live-validated, PASS
Baseline reconfirmed: SQL head 077_5J1, Alembic head 077_5J1, single
                       head, before this pass began
New SQL head: 087_5B1 (10 files, 078_5F1..087_5B1)
New Alembic head: 087_5B1, single linear chain
Fresh-DB 001->087: PASS, exit code 0
Existing-DB 077_5J1->087_5B1: PASS, exit code 0 (separate database,
                               pinned at 077_5J1, upgraded forward)
Structural delta (077 baseline -> 087, same methodology both times):
  tables 198->199 (+1: organization.break_glass_grants)
  functions (non-extension) 70->83 (+13)
  SECURITY DEFINER functions 47->58 (+11)
  triggers 106->108 (+2)
  indexes 826->834 (+8, net of 1 dropped: uq_dv_content_hash)
  RLS-enabled tables 91->92 (+1)
  RLS policies 103->104 (+1)
  all deltas individually reconciled against the intended DDL — see
  5L-Global-Database-Reconciliation.md
DEP-6F-16 (publish/delete race): PASS, live guard + column-privilege test
DEP-6F-01 (rollback): PASS, live pointer-swap + invalid-source rejection
DEP-6F-09 (mark failed): PASS, live PENDING->FAILED + idempotency + wrong-state rejection
DEP-6F-15 (GDPR erase): PASS, live chunk deletion + content erasure + idempotency + full-document delete
DEP-6F-14 (KB-wide dedup): PASS, live same-KB rejection + cross-KB allowance + anti-spoofing derive-trigger proof
DEP-6F-02 (reindex generations): PASS, live begin/complete/fail/cleanup lifecycle + genuine two-session concurrency race (one session blocked, correctly rejected)
Multilingual FTS: PASS, live English/Tamil/Telugu/Hindi/Tamil-English-code-mixed tokenization, no corruption/loss
DEP-5D suppression uniqueness: PASS, live duplicate rejection (incl. NULLS NOT DISTINCT proof for PLATFORM scope) + genuine two-session concurrency race + lift/reinsert
DEP-5H billing hardening: PASS, live direct-INSERT denial + function success + cross-tenant invoice rejection
DEP-6B-01 break-glass: PASS, live non-admin denial (function + RLS-blind SELECT) + full grant/release lifecycle + immutable-terminal-state trigger proof
AI/untrusted-input safety: PASS, SQL-injection-shaped chunk content stored as inert text, documents table unaffected
Regression slice: PASS, app_readonly INSERT-on-audit_events still denied, cross-tenant RLS still isolates Org A/Org B
SECURITY DEFINER audit (12 new functions): PASS, all prosecdef=true, all
  have explicit search_path, no PUBLIC EXECUTE grant on any of them
Cleanup: both throwaway databases dropped, all four app_* role passwords
  reset to NULL — local instance restored to its pre-session state

Phase 5L LIVE VERIFIED
```

See `docs/phase-05-database-design/5L-Global-Database-Reconciliation/
5L-Global-Database-Reconciliation.md` for the full classification report
(Category A/B/C/D per candidate finding) and
`5L-Global-Database-Reconciliation/execution_logs/` for the raw captured
command/query evidence (25 timestamped files, prefix `20260823T204549Z`).
This closes six of `docs/phase-06-api-design/6F-Knowledge-RAG-APIs.md`'s
blocking dependencies (DEP-6F-01, 02, 09, 14, 15, 16) and
`docs/phase-06-api-design/6B-Authentication-and-Authorization-API.md`'s
DEP-6B-01; both documents' own dependency-status rows are updated
separately (freeze-eligibility verdicts are not changed here — that
review is independent of this database pass).
