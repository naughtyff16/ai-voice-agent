# Phase 6I FINAL Privilege Cleanup Validation Report

**Date:** 2026-08-29 (Phase 6I Workflow APIs — FINAL Privilege Cleanup pass)
**Scope:** live proof, on genuine PostgreSQL 16.10, that `app_platform_admin`
can no longer directly invoke `workflow.fn_start_workflow_execution(...)`,
per the product owner's authoritative decision (Option 2, resolving the
`USER DECISION REQUIRED` item raised in the FINAL MICRO-REMEDIATION pass,
`6I-Workflow-APIs.md` §65.3), with zero regression to any other Phase 6I
guarantee. Full raw evidence: `execution_logs/20260829T050000Z_53` through
`_63_*.txt`.

---

## Migration policy

`100_5G1.sql` amended in place a fourth time — confirmed still never
applied to any real/production database. `revision`/`down_revision`
unchanged; SHA-256/size updated in the manifest.

---

## Privilege change

**Signature (verified from the repository, not guessed):**
`workflow.fn_start_workflow_execution(p_organization_id UUID,
p_workflow_version_id UUID, p_session_ref UUID, p_started_at TIMESTAMPTZ
DEFAULT NOW())`.

```
BEFORE: GRANT EXECUTE ON FUNCTION workflow.fn_start_workflow_execution(...)
        TO app_api, app_worker, app_platform_admin;

AFTER:  GRANT EXECUTE ON FUNCTION workflow.fn_start_workflow_execution(...)
        TO app_api, app_worker;
```

`REVOKE ALL ... FROM PUBLIC` on the same function is unchanged. No other
statement in `100_5G1.sql` was touched — the function body, tenant
validation, `ARCHIVED` locking (`FOR SHARE OF wd`), duplicate-start
semantics, and advisory-lock behavior are byte-for-byte identical to the
FINAL MICRO-REMEDIATION pass' own version.

**Live-verified grant state** (`..._53_*.txt`, queried directly from
`pg_proc.proacl` via `aclexplode`, not asserted from the SQL source):

```
execute_grantees: app_api, app_worker
public_can_execute: f
```

---

## Runtime regression

**Test A — `app_platform_admin` denied** (`..._55_*.txt`):
```
ERROR:  permission denied for function fn_start_workflow_execution
```
The function body never executes — confirmed by the error occurring at
the privilege-check layer, before any of the function's own logic runs.

**Test B — legitimate runtime roles allowed** (`..._54_*.txt`, `..._56_*.txt`):
`app_api` and `app_worker` both successfully start a fresh execution
(`outcome = STARTED`).

**Test C — duplicate-start regression** (`..._54_*.txt`, `..._57_*.txt`):
```
same session + same version      -> REPLAYED_EXISTING (same execution_id)
same session + different version -> VERSION_CONFLICT (same execution_id, no substitution)
```

**Test D — Archive/StartExecution regression** (`..._57_*.txt`):
```
Race A (Start locks first): STARTED; Archive measurably waited 0.48s; Archive
  succeeded only after commit; execution remained ACTIVE afterward.
Race B (Archive committed first): subsequent StartExecution against that
  version rejected with the expected ARCHIVED exception.
```

All 6 scenarios in this suite PASS — zero regression.

---

## Final privilege matrix — `workflow.fn_start_workflow_execution`

| Role | EXECUTE |
|---|---|
| `app_api` | ✅ |
| `app_worker` | ✅ |
| `app_platform_admin` | ❌ |
| `app_readonly` | ❌ (never granted) |
| `PUBLIC` | ❌ |

---

## PostgreSQL 16 validation

| Check | Result |
|---|---|
| Fresh `voice_agent_pg16_finalfresh4`: `001_5B → … → 100_5G1` | **PASS, exit 0**, single head `100_5G1`. `..._58_..._60_*.txt` |
| Incremental `voice_agent_pg16_incremental4`: `099_5C1` then `100_5G1` alone | **PASS, exit 0** both steps. `..._61_*.txt`, `..._62_*.txt` |
| `alembic history` | Single linear 100-entry chain, no branch. `..._63_*.txt` |

---

## Final freeze-review checklist (§12 of the governing task)

| Guarantee | Status |
|---|---|
| Guarded Workflow publish only | ✅ unaffected, unchanged |
| Mandatory exact-draft publish precondition | ✅ unaffected, unchanged |
| Archive ↔ StartExecution serialization | ✅ re-confirmed live this pass |
| Monotonic Workflow checkpoint CAS | ✅ unaffected, unchanged |
| Durable side-effect claim identity | ✅ unaffected, unchanged |
| SUBMITTING cannot become retryable FAILED via ordinary worker | ✅ unaffected, unchanged |
| AMBIGUOUS cannot auto-retry | ✅ unaffected, unchanged |
| Normal runtime roles cannot bypass Workflow lifecycle invariants by raw DML | ✅ unaffected, unchanged |
| `app_platform_admin` cannot start Workflow executions | ✅ **closed by this pass** |
| WorkflowVersion history remains immutable | ✅ unaffected, unchanged |
| WEBHOOK/API_CALL remain execution-blocked until 6J | ✅ unaffected, unchanged |

All eleven guarantees hold.

---

## Summary

**Final verdict: APPROVED — PHASE 6I READY TO FREEZE.** No open
`USER DECISION REQUIRED` items remain.
