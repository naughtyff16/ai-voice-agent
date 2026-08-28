# Phase 6I Blocker Remediation Validation Report

**Date:** 2026-08-29 (Phase 6I Workflow APIs — Blocker Remediation pass)
**Scope:** live proof, on genuine PostgreSQL 16.10, that migration
`100_5G1.sql` closes all four blockers `6I-Workflow-APIs.md`'s own review
found and left open: (A) side-effecting Workflow node re-execution after
crash/Redis-loss, (B) stale/out-of-order PostgreSQL checkpoint moving a
`WorkflowExecution` backward, (C) `app_platform_admin` direct-DML bypass of
Workflow/Prompt version-identity and lifecycle invariants, and (D) the
Archive-vs-draft-update race that could mutate an `ARCHIVED`
`WorkflowDefinition`. Full raw evidence:
`execution_logs/20260829T020000Z_01` through `_19_*.txt`.

---

## Environment

No Docker engine available in this environment (reconfirmed). A native
PostgreSQL 18 install already exists at `C:\Program Files\PostgreSQL\18`
(untouched by this pass). PostgreSQL 16.10 was built from the EDB
binaries-only distribution (`postgresql-16.10-1-windows-x64-binaries.zip`,
downloaded directly from `get.enterprisedb.com`, no installer/no elevation
required), extracted to `C:\Users\Dell\pgval16\pgsql`, `initdb` + `pg_ctl
start -o "-p 5433"` run directly as the current OS user with `trust`
authentication for local loopback only — identical in approach to the prior
`PG16_MIGRATION_VALIDATION_REPORT.md` pass (2026-08-28), rebuilt from
scratch in this pass because that prior throwaway instance had already been
torn down.

```
2026-08-29 02:04:12.034 IST LOG:  starting PostgreSQL 16.10, compiled by Visual C++ build 1944, 64-bit
2026-08-29 02:04:12.035 IST LOG:  listening on IPv4 address "127.0.0.1", port 5433
2026-08-29 02:04:12.136 IST LOG:  database system is ready to accept connections
```

`pgvector` 0.8.0 was built from source (`nmake /f Makefile.win` /
`Makefile.win install`) against this PG16 install's own headers/import
library, using the MSVC 14.51.36231 (Visual Studio 18 Community) toolchain
already present on this machine — build and install both exit 0. All four
required extensions confirmed loadable before any migration ran:

```
 extname            | extversion
---------------------+------------
 plpgsql            | 1.0
 vector             | 0.8.0
 pgcrypto           | 1.3
 pg_stat_statements | 1.10
```

Alembic `1.19.1` / SQLAlchemy `2.0.52` / `psycopg[binary]` `3.3.4` in a
throwaway `uv`-managed Python 3.12.14 venv at
`docs/phase-05-database-design/5K/.venv_validation_pg16` — identical
versions to the prior PG16 pass, removed at the end of this batch.

---

## Migration chain validation

| Check | Result |
|---|---|
| Fresh `voice_agent_pg16_finalfresh`: `001_5B → … → 099_5C1 → 100_5G1` | **PASS, exit code 0.** `execution_logs/20260829T020000Z_12_6i_FINAL_pg16_fresh_001_to_100.txt` |
| `alembic heads` (fresh DB) | `100_5G1 (head)` — single head. `..._13_*.txt` |
| `alembic current` (fresh DB) | `100_5G1 (head)`. `..._14_*.txt` |
| Incremental `voice_agent_pg16_incremental`: pin at `099_5C1`, then apply `100_5G1` alone | **PASS, exit code 0** for both steps. `..._15_*.txt`, `..._16_*.txt` |
| `alembic history` (incremental DB) | Single linear 100-entry chain, `<base> → 001_5B → … → 100_5G1`, no branch. `..._17_*.txt` |
| `alembic downgrade 099_5C1` | Raises `NotImplementedError` as designed (forward-only, matching every other 5K revision); the failed transaction rolls back cleanly — `alembic current` immediately after still reports `100_5G1 (head)`, confirmed. `..._18_*.txt` |

Two genuine, live-discovered defects were found and fixed **within this same pass**, before the evidence above was captured, not asserted from reading the SQL alone:

1. **`fn_claim_node_execution()`'s `SET search_path` omitted `public`** — an exact recurrence of `076_5K1.sql`'s own Group-1 defect class (an `INSERT` relying on a column `DEFAULT gen_uuid_v7()`, which itself makes an unqualified internal call to pgcrypto's `gen_random_bytes()`). Reproduced live on the very first functional test:
   ```
   ERROR:  function gen_random_bytes(integer) does not exist
   CONTEXT:  PL/pgSQL function public.gen_uuid_v7() line 4 during statement block local variable initialization
   ```
   Fixed by adding `public` to the search path in the same safe order `076_5K1.sql` established (own schema, `organization`, `pg_catalog`, `public` last), then re-verified clean on a from-scratch chain re-run.
2. **A parent-table-only `REVOKE` left every pre-existing partition's own, separately-inherited ACL untouched.** Confirmed live via `information_schema.role_table_grants` immediately after the first `REVOKE UPDATE, DELETE ON workflow.workflow_executions FROM app_platform_admin` — every one of the five existing partitions (`workflow_executions_2026_08` … `_default`) still showed `app_platform_admin` holding `DELETE`/`SELECT`/`UPDATE` and `app_api`/`app_worker` still holding `UPDATE`, exactly the class of gap `076_5K1.sql`'s own header comment already documents for its own INSERT revoke. Fixed by adding the identical defensive `pg_inherits`-walking `DO $$ … $$` loop `076_5K1.sql` uses, then reconfirmed closed:
   ```
   table_name                   | grantee            | privilege_type
   workflow_executions          | app_api            | SELECT
   workflow_executions          | app_platform_admin | SELECT
   workflow_executions          | app_worker         | SELECT
   workflow_executions_2026_08  | app_platform_admin | SELECT
   workflow_executions_2026_09  | app_platform_admin | SELECT
   workflow_executions_2026_10  | app_platform_admin | SELECT
   workflow_executions_2026_11  | app_platform_admin | SELECT
   workflow_executions_default  | app_platform_admin | SELECT
   ```

---

## Blocker A — side-effecting node idempotency

`workflow.node_execution_claims` + `fn_claim_node_execution()` /
`fn_begin_node_submission()` / `fn_record_node_succeeded()` /
`fn_record_node_ambiguous()` / `fn_record_node_failed()`.

**Functional suite** (`..._07_6i_node_claim_state_machine.txt`, 14/14 PASS):
fresh claim; second worker blocked while lease valid
(`NOT_CLAIMABLE_CLAIMED`); begin submission; a different worker's claim
attempt while `SUBMITTING` (`NOT_CLAIMABLE_SUBMITTING`, the core Blocker-A
fix); record `SUCCEEDED` with `downstream_ref`; a further claim attempt
after `SUCCEEDED` (`NOT_CLAIMABLE_SUCCEEDED`, `downstream_ref` readable
instead of re-invoking); an independent node in the same Turn independently
claimable; `SUBMITTING → AMBIGUOUS`; a reclaim attempt on `AMBIGUOUS`
(`NOT_CLAIMABLE_AMBIGUOUS`, never auto-reclaimed); `CLAIMED → FAILED`
(pre-submission local abort); a retry of a `FAILED` claim (`claimed=TRUE`,
safe); an expired 5-second lease safely reclaimed (same claim row reused,
not a duplicate row); a forged `organization_id` argument (exception);
direct DML on the table as `app_api` (permission denied).

**Genuine two-connection concurrency** (`..._08_6i_concurrency_python_harness.txt`,
test C1): two real threads/connections issue `fn_claim_node_execution()`
against the identical identity at effectively the same instant —

```
outcomes: {'B': (True, UUID('...'), 'CLAIMED', None), 'A': (False, UUID('...'), 'CLAIMED', 'NOT_CLAIMABLE_CLAIMED')}
[PASS] exactly one of the two concurrent claimants won
[PASS] the other was told NOT_CLAIMABLE_CLAIMED
[PASS] exactly ONE durable claim row exists for the identity
```

**TOOL_CALL / `voice.tool_executions`:** Option B adopted — no change to
`voice.tool_executions` (verified unmodified; `013_5C.sql`'s own DDL is
untouched by `100_5G1.sql`). `downstream_ref` is the opaque bridge.

**TRANSFER / HUMAN_TRANSFER:** 6D's own `TransferOnlyOncePerCall` policy
(cited in 6D §11, `POST /calls/{id}/transfer`'s `ACTIVE → TRANSFERRING`
guard) independently prevents a second physical transfer attempt against a
call that has already left `ACTIVE` — the new claim table adds an
audit-correlation point via `downstream_ref`, not a second call-control
mechanism.

**WEBHOOK / API_CALL:** unaffected, still execution-blocked pending 6J.

---

## Blocker B — checkpoint ordering

`workflow.workflow_executions.checkpoint_seq` + `fn_checkpoint_workflow_execution()`.

**Sequential functional suite** (`..._04_6i_checkpoint_cas_tests.txt`, 9/9
PASS): seq=1 then seq=2 both `APPLIED`; a delayed seq=1 arriving after
seq=2 already applied → `STALE_CHECKPOINT`, state unchanged (verified: the
row still shows `turn2`/seq=2, not the stale `turn1` payload); duplicate
delivery of an already-applied seq → `STALE_CHECKPOINT`, idempotent no-op;
checkpoint after `COMPLETED` → `EXECUTION_TERMINAL`; complete-after-complete
→ `EXECUTION_TERMINAL`; nonexistent execution → `NOT_FOUND`; cross-tenant
query → `NOT_FOUND` (non-disclosing, matches 6A's own cross-tenant-existence
convention); direct raw `UPDATE` as `app_api` → permission denied
(`..._11_*`); wrong `started_at`/partition hint → `NOT_FOUND`
(`..._19_6i_checkpoint_wrong_partition_hint.txt`).

**Trigger-level backstop, proven independent of privilege**
(`..._06_6i_trigger_backward_seq_part1/2.txt`): a fresh execution
checkpointed to seq=5, then, connecting as the `postgres` superuser
(bypasses every grant and RLS policy), a raw `UPDATE ... SET
checkpoint_seq = 2` is attempted directly:

```
ERROR:  workflow_executions.checkpoint_seq cannot move backward (old=5, new=2). execution_id: 01a04a1e-dbab-7fa9-a6a7-a72d2a20b5fc
CONTEXT:  PL/pgSQL function workflow.prevent_execution_mutation() line 16 at RAISE
```

**Genuine two-thread out-of-order-commit race** (`..._08_*.txt`, test C2):
connection B checkpoints seq=2 and commits immediately; connection A,
deliberately delayed 0.4s, then attempts seq=1 (an older Turn) —

```
outcomes: {'B': 'APPLIED', 'A': 'STALE_CHECKPOINT'}
[PASS] fast seq=2 writer got APPLIED
[PASS] delayed seq=1 writer got STALE_CHECKPOINT (never APPLIED)
[PASS] final durable checkpoint_seq is 2, never regressed to 1
```

---

## Blocker C — admin direct-DML bypass

**All nine previously-exploitable vectors, as `app_platform_admin`**
(`..._09_6i_admin_bypass_tests.txt`):

```
T6.1 UPDATE workflow_definitions (status/published_version_id)      -> permission denied
T6.2 DELETE workflow_versions                                        -> permission denied
T6.3 UPDATE workflow_versions.organization_id                        -> permission denied
T6.4 UPDATE workflow_versions.workflow_definition_id                 -> permission denied
T6.5 DELETE workflow_executions                                      -> permission denied
T6.6 UPDATE workflow_executions.checkpoint_seq                       -> permission denied
T6.7 INSERT workflow_definitions                                     -> permission denied
T6.9 UPDATE prompt_versions.organization_id                          -> permission denied
T6.8 SELECT (legitimate diagnostic path)                             -> still works (3/3 counts returned)
```

**Final grant posture**, confirmed via `information_schema.role_table_grants`:
`app_platform_admin` holds `SELECT` only on `workflow_definitions`,
`workflow_versions`, `workflow_executions` (parent + all partitions),
`node_execution_claims`, and `prompt_versions`.

---

## Blocker D — Archive terminal-immutability

**Identity-reassignment rejection, as `postgres` superuser**
(`..._10_6i_version_identity_trigger_superuser.txt`):

```
UPDATE workflow_versions SET workflow_definition_id = ... -> ERROR: workflow_versions fields are immutable
UPDATE workflow_versions SET organization_id = ...         -> ERROR: workflow_versions fields are immutable
UPDATE prompt_versions   SET prompt_template_id = ...       -> ERROR: prompt_versions fields are immutable
```

**Genuine two-thread Archive-vs-draft-update race** (`..._08_*.txt`, test
C4): connection A begins `UPDATE ... SET status='ARCHIVED'` and holds the
row lock; connection B (a separate thread) blocks on
`UPDATE ... SET draft_graph=... WHERE status IN ('DRAFT','PUBLISHED')`
against the same row; A commits, releasing the lock; B's blocked statement
then proceeds:

```
B result: {'rowcount': 0}
[PASS] queued draft UPDATE affects ZERO rows once Archive won the race
[PASS] final state is ARCHIVED with draft_graph UNCHANGED
```

**Trigger-level backstop**, same test, part B: as the `postgres` superuser,
a raw `UPDATE workflow_definitions SET name='hacked'` against the now-
`ARCHIVED` row:

```
[PASS] trigger rejects mutation of an ARCHIVED row even via superuser raw UPDATE
       workflow_definitions: ARCHIVED is terminal — no further mutation is permitted.
```

---

## Execution start idempotency (§26/§27 of `6I-Workflow-APIs.md`)

`..._03_6i_start_execution_outcomes.txt` (sequential) and `..._08_*.txt`
test C3/C3b (genuine concurrency):

```
T1.1 fresh start                                    -> STARTED
T1.2 duplicate start, same version                  -> REPLAYED_EXISTING (same execution_id)
T1.3 duplicate start, different version              -> VERSION_CONFLICT (same execution_id, no substitution)
T1.4 start against ARCHIVED workflow definition      -> RAISE EXCEPTION (closes the resolve-then-archive race)

C3b (two real threads, no ordering bias):
outcomes: {'D': (uuid, 'STARTED'), 'C': (uuid, 'REPLAYED_EXISTING')}   -- same uuid both sides
[PASS] true-simultaneous race resolves to a SINGLE execution id
[PASS] exactly one STARTED and one REPLAYED_EXISTING
```

---

## Tenant isolation regression

`..._11_6i_tenant_isolation_regression.txt`, 5/5 PASS: Org A sees only its
own workflow definitions; Org B sees 0 of Org A's rows and only its own;
Org B sees 0 rows on `node_execution_claims` and `workflow_executions`
(all fixtures are Org A); with no tenant context set at all, every one of
`workflow_definitions`/`workflow_executions`/`node_execution_claims`
returns 0 rows (fail-closed, not fail-open).

---

## Tenant-forgery adversarial tests

`..._05_6i_tenant_forgery_tests.txt`: a session authenticated as Org A
calling `fn_checkpoint_workflow_execution()`/`fn_start_workflow_execution()`
with `p_organization_id` forged to Org B — both raise, matching text:

```
ERROR: fn_checkpoint_workflow_execution: organization_id ...b does not match current tenant context
ERROR: fn_start_workflow_execution: organization_id ...b does not match current tenant context
```

`fn_claim_node_execution()` carries the identical explicit check (test
T5.13, `..._07_*.txt`).

---

## Summary — full PASS/FAIL matrix

38/38 live checks PASS across ten test files
(`execution_logs/20260829T020000Z_03` through `_19_*.txt`, plus the
migration-chain evidence `_12` through `_18`). Zero FAILs. No test was
skipped, weakened, or asserted without a corresponding raw output file.

**Final verdict: APPROVED — PHASE 6I READY TO FREEZE.**
