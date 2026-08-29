# Phase 6I FINAL Blocker Remediation Validation Report

**Date:** 2026-08-29 (Phase 6I Workflow APIs — FINAL Blocker Remediation pass)
**Scope:** live proof, on genuine PostgreSQL 16.10, that the revised
`100_5G1.sql` closes the three remaining blocker classes a second,
adversarial review of the first remediation pass found: (E) ordinary
runtime roles could still bypass guarded Workflow publishing with raw
DML, (F) `StartExecution` did not truly serialize against `Archive`, and
(G) new side-effect `SECURITY DEFINER` functions did not fully enforce
tenant/execution/checkpoint identity. Full raw evidence:
`execution_logs/20260829T033000Z_20` through `_36_*.txt`.

---

## Environment

Identical approach to the first remediation pass, rebuilt from scratch
(the prior throwaway instance had been torn down): native PostgreSQL
16.10 from the EDB binaries-only distribution at
`C:\Users\Dell\pgval16\pgsql`, port 5433, trust auth, loopback only;
`pgvector` 0.8.0 built from source via MSVC 14.51.36231; Alembic
`1.19.1`/SQLAlchemy `2.0.52`/`psycopg[binary]` `3.3.4` in a throwaway
`uv`-managed Python 3.12 venv — torn down, along with the PostgreSQL
instance itself, at the end of this batch.

---

## Migration policy

`100_5G1.sql` was amended in place a second time, not superseded by a
new `101_5G2.sql` — identical revision policy to `099_5C1.sql`'s own
six-pass history, since this file has never been applied to any
real/production database (every validation pass runs against a
disposable local instance). `revision`/`down_revision` are unchanged
(`099_5C1 → 100_5G1`); only the file's SHA-256/size changed (recomputed
in the manifest).

---

## Blocker E — guarded Workflow publish/archive capability

**Raw-DML bypass closed** (`..._20_*.txt`):

```
P1.1 app_api INSERT workflow_versions               -> permission denied
P1.2 app_api UPDATE published_version_id             -> permission denied
P1.3 app_api UPDATE status='PUBLISHED'                -> permission denied
P1.4 app_api UPDATE draft_graph (safe column)          -> still succeeds
P1.5 old fn_workflow_publish(...)                      -> function does not exist (dropped)
```

**Live-discovered defect, fixed within this same pass:** the first
attempt revoked only column-level `UPDATE (status, published_version_id)`
while leaving `040_5G.sql`'s table-level `UPDATE` grant intact — live
tests P1.2/P1.3 both showed `UPDATE 1` (succeeded) against that first
attempt. PostgreSQL's own privilege model makes a table-level grant
implicitly cover every column regardless of any column-level `REVOKE`
issued afterward. Fixed by revoking the table-level grant entirely, then
re-granting `UPDATE` on only `(name, description, draft_graph)` —
reconfirmed closed on the corrected version (`..._20_*.txt`, second run).

**`fn_publish_workflow`/`fn_archive_workflow` functional** (`..._21_*.txt`,
12/12 PASS): fresh publish → version 1; republish → version 2 (sequential,
no gap); stale `p_expected_updated_at` → `PRECONDITION_FAILED`, confirmed
zero new versions created; archive → `ARCHIVED`; archive again →
`ALREADY_ARCHIVED` (idempotent); publish an archived workflow →
`ARCHIVED` outcome, no version created; publish nonexistent workflow →
`NOT_FOUND`; cross-tenant forged `organization_id` → exception; publish
another tenant's workflow while authenticated as the caller's own tenant
→ `NOT_FOUND` (non-disclosing, matches 6A's cross-tenant-existence
convention); archive with forged org → exception. `app_worker` denied
`EXECUTE` on `fn_publish_workflow` (`..._22_*.txt`) — Publish is
deliberately `app_api`-only, narrower than its dropped predecessor.

**Live-discovered defect #2, fixed within this same pass:**
`fn_publish_workflow`'s `RETURNS TABLE` OUT parameter `version_number`
collided with the real `workflow_versions.version_number` column,
producing `ERROR: column reference "version_number" is ambiguous` on the
first functional test — the identical class of bug `099_5C1.sql`'s own
header comment documents for `fn_claim_dispatch_for_provider_submission`.
Fixed with the same `#variable_conflict use_column` pragma; reconfirmed
clean afterward.

**Concurrent publish** (`..._23_*.txt`, test D1): two genuine threads/
connections publish the SAME workflow simultaneously —

```
outcomes: {'A': (1, 'PUBLISHED'), 'B': (2, 'PUBLISHED')}
[PASS] both publishers succeeded
[PASS] version numbers are unique and sequential: {1, 2}
```

---

## Blocker F — StartExecution/Archive serialization

`fn_start_workflow_execution`'s ARCHIVED check now takes `FOR SHARE OF
wd`. Live-proven via two genuine races (`..._23_*.txt`, tests D2/D3):

**Race A (Start locks first):**
```
outcomes: {'start_pre_commit': (..., 'STARTED'), 'archive_wait_seconds': 0.49, 'archive_outcome': 'ARCHIVED'}
[PASS] StartExecution succeeded
[PASS] Archive was measurably forced to WAIT (0.49s observed — real lock contention, not assumed)
[PASS] Archive succeeded only after A committed
[PASS] the existing execution remains ACTIVE despite the later Archive
```

**Race B (Archive commits first):**
```
[PASS] StartExecution against an already-ARCHIVED workflow's version is rejected:
"fn_start_workflow_execution: the WorkflowDefinition owning workflow_version ... is ARCHIVED"
```

---

## Blocker G — side-effect claim tenant/identity integrity

**Four previously-unguarded functions now reject forged tenant arguments**
(`..._25_*.txt`, 6/6 PASS): `fn_begin_node_submission`,
`fn_record_node_succeeded`, `fn_record_node_ambiguous`,
`fn_record_node_failed` all now raise `organization_id ... does not match
current tenant context` on a forged argument, and all still succeed
normally with the correct tenant.

**`fn_claim_node_execution` identity/checkpoint/graph validation**
(`..._24_*.txt`, 7/7 PASS):
```
S1.1 valid claim (seq=current+1, node in pinned graph)   -> succeeds
S1.2 wrong target_checkpoint_seq                          -> exception
S1.3 wrong workflow_execution_started_at                  -> exception (not found)
S1.4 node_id not in pinned graph                          -> exception
S1.5 node_id exists, node_type mismatched                 -> exception
S1.6 nonexistent execution entirely                       -> exception
S1.7 claim against a COMPLETED (terminal) execution       -> exception
```

---

## Full regression (no defect reintroduced)

`..._26_*.txt`, 13/13 PASS: the entire first-pass concurrency suite
(concurrent duplicate node claim, out-of-order checkpoint commit,
simultaneous StartExecution, Archive-vs-draft-update — the last updated
to route through the new `fn_archive_workflow()` since raw `UPDATE
... SET status` is no longer possible for `app_api` at all) re-run
against the FINAL migration with zero regressions.

`..._27_*.txt`, 8/8 PASS: `app_platform_admin` bypass regression —
`UPDATE workflow_definitions`, `DELETE`/`INSERT workflow_versions`,
`DELETE`/`UPDATE workflow_executions`, `DELETE node_execution_claims`,
and (new) `EXECUTE fn_publish_workflow` all denied; legitimate `SELECT`
still works.

`..._29_*.txt`, 6/6 PASS: tenant isolation regression across
`workflow_definitions`/`workflow_executions`/`node_execution_claims`,
including the fail-closed no-tenant-context case.

---

## Full `SECURITY DEFINER` inventory

`..._28_*.txt` — all 12 Workflow/Prompt `SECURITY DEFINER` functions
(old and new) queried directly from `pg_proc`/`pg_roles`/`pg_namespace`:
every one shows `prosecdef = t`, `PUBLIC EXECUTE = false`, and an
`EXECUTE` grantee list matching this document's own stated design
(`fn_publish_workflow`/`fn_archive_workflow`: `app_api` only;
`fn_start_workflow_execution`: `app_api, app_worker, app_platform_admin`,
unchanged from the first pass; every other function: `app_api,
app_worker`). Search paths: `fn_claim_node_execution`,
`fn_publish_workflow`, and `fn_start_workflow_execution` correctly
include `public` (each performs an `INSERT` relying on a
`gen_uuid_v7()`-defaulted column or an explicit `gen_uuid_v7()` call);
every other function correctly omits it (pure guards, no ID generation).

---

## PostgreSQL 16 validation

| Check | Result |
|---|---|
| Fresh `voice_agent_pg16_finalfresh2`: `001_5B → … → 100_5G1` (revised) | **PASS, exit 0**, single head `100_5G1`. `..._30_..._32_*.txt` |
| Incremental `voice_agent_pg16_incremental2`: pin at `099_5C1`, apply `100_5G1` alone | **PASS, exit 0** both steps. `..._33_*.txt`, `..._34_*.txt` |
| `alembic history` | Single linear 100-entry chain, no branch. `..._35_*.txt` |
| `downgrade()` | Raises `NotImplementedError` (message updated for this pass' additions); DB remains at `100_5G1`. `..._36_*.txt` |

---

## Summary

Every scenario explicitly named in the governing task's §42 adversarial
list was tested live and closed: raw INSERT/UPDATE publish bypass (all
three roles), two concurrent publishers, stale-ETag publish, publish of
an archived workflow, resolve-then-archive-then-start ordering in both
directions, duplicate StartExecution (same/different version), forged
tenant on every new side-effect function, forged execution identity/
checkpoint sequence, claims against a terminal execution, and direct
claim-table DML.

**Final verdict: APPROVED — PHASE 6I READY TO FREEZE.**
