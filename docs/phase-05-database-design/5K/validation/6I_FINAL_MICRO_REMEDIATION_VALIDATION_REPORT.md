# Phase 6I FINAL Micro-Remediation Validation Report

**Date:** 2026-08-29 (Phase 6I Workflow APIs — FINAL Micro-Remediation pass)
**Scope:** live proof, on genuine PostgreSQL 16.10, that (A) an ordinary
runtime worker can no longer turn a `SUBMITTING` side-effect claim into
a retryable `FAILED` state, and (B) `fn_publish_workflow()`'s exact-draft
concurrency precondition is now mandatory, with no `NULL`-bypass route.
Full raw evidence: `execution_logs/20260829T040000Z_37` through `_52_*.txt`.

---

## Migration policy

`100_5G1.sql` amended in place a third time — never applied to any
real/production database, identical policy to the prior two passes and
to `099_5C1.sql`'s own six-pass precedent. `revision`/`down_revision`
unchanged; SHA-256/size updated in the manifest.

---

## Blocker A — SUBMITTING hard-stop closure

**Before:** `fn_record_node_failed()`'s `WHERE claim_state IN
('CLAIMED','SUBMITTING')` permitted an ordinary worker to move a
`SUBMITTING` claim (external side effect potentially already in flight
or already succeeded) directly to `FAILED` — a reclaimable state,
letting a mis-recorded timeout/lost-response/crash-recovery guess make
an uncertain or already-successful side effect automatically retryable.

**After:** only `claim_state = 'CLAIMED'` is accepted. Return type
upgraded `BOOLEAN → TABLE(recorded, reason)` so the caller can
distinguish `NOT_FAILABLE_AFTER_SUBMISSION` from `NOT_CLAIM_HOLDER`/
`NOT_FOUND` rather than one ambiguous `FALSE`.

**Live evidence** (`..._37_*.txt`):

```
TEST 9  — CLAIMED -> FAILED                         : recorded=t (ALLOWED)
        — FAILED state then safely reclaimed         : claimed=t
TEST 10 — SUBMITTING -> FAILED (fn_record_node_failed): recorded=f, reason=NOT_FAILABLE_AFTER_SUBMISSION
        — row remains SUBMITTING (verified directly)
        — subsequent claim attempt: NOT_CLAIMABLE_SUBMITTING (unchanged)
TEST 11 — SUBMITTING -> AMBIGUOUS                    : still allowed; reclaim -> NOT_CLAIMABLE_AMBIGUOUS
TEST 12 — SUBMITTING -> SUCCEEDED                    : still allowed, terminal; reclaim -> NOT_CLAIMABLE_SUCCEEDED
Wrong worker_id on fn_record_node_failed             : recorded=f, reason=NOT_CLAIM_HOLDER
```

All 8 scenarios PASS exactly as required by the governing task's own
§9–§12 test specification.

---

## Blocker B — mandatory exact-draft publish precondition

**Before:** `p_expected_updated_at TIMESTAMPTZ DEFAULT NULL`; a `NULL`
value (the default) bypassed the precondition check entirely.

**After:** no default; an explicit `IF p_expected_updated_at IS NULL
THEN RAISE EXCEPTION` guard inside the function body, defensive against
an authorized caller passing a literal `NULL` even without a default
(PostgreSQL does not `NOT NULL`-constrain function parameters).

**Live evidence** (`..._38_*.txt`):

```
NULL precondition      -> ERROR: fn_publish_workflow: p_expected_updated_at is required ...
                        -> 0 versions created, definition unchanged (verified)
Stale precondition     -> PRECONDITION_FAILED, 0 versions created
Correct precondition   -> PUBLISHED, version_number=1
Re-publish using the
  now-stale (already-
  consumed) precondition -> PRECONDITION_FAILED, still exactly 1 version (no silent extra publish)
```

All 4 required scenarios (§17–§19) PASS. The concurrent-publish
regression (`..._39_*.txt`, test D1) further demonstrates the exact
scenario §20 asks to be documented: two publishers sharing the same
(pre-race) precondition value — only the winner of the `FOR UPDATE` lock
race succeeds; the loser, now holding a stale precondition relative to
the winner's own commit, correctly receives `PRECONDITION_FAILED` rather
than silently publishing an unseen draft. This is a deliberate,
documented behavior change from the prior (optional-precondition) pass,
where both concurrent publishers could succeed with sequential version
numbers — mandatory preconditions make "genuinely concurrent, mutually
unaware publishes" impossible by design, which is the entire point of
optimistic concurrency control.

---

## `app_platform_admin` / `fn_start_workflow_execution` review

Traced to frozen, executed `041_5G.sql` — not introduced or altered by
any 6I remediation pass. Reviewed and **left unchanged**, not silently
revoked: unlike every REVOKE this remediation series has made elsewhere,
removing this grant would not close an invariant bypass (the function is
already fully tenant/archive/version-safe regardless of caller), so the
question is a business-policy scope decision, not a technical
least-privilege conclusion. Flagged as `USER DECISION REQUIRED` in the
accompanying chat report — not itself a freeze blocker, per the
governing task's own explicit framing.

---

## Full regression (zero defects reintroduced)

- Concurrency (`..._39_*.txt`): 9/9 PASS — duplicate claim race,
  out-of-order checkpoint, simultaneous StartExecution, Archive-vs-draft,
  concurrent publish under the new mandatory-precondition semantics.
- Archive/StartExecution (`..._40_*.txt`): 7/7 PASS — Race A/B (measured
  lock-blocking preserved), duplicate/version-conflict semantics,
  cross-tenant version denial.
- Side-effect tenant/identity security (`..._41_*.txt`): 10/10 PASS —
  wrong tenant, wrong `started_at`, wrong checkpoint sequence, terminal
  execution, cross-tenant on all four previously-hardened functions,
  direct table DML denied.
- Publish privilege (`..._42_*.txt`): 7/7 PASS — raw INSERT denied for
  all three roles, raw UPDATE denied, admin `EXECUTE` denied, direct
  `NULL`-precondition call denied.
- Admin bypass (`..._43_*.txt`): 6/6 PASS.
- Tenant isolation (`..._44_*.txt`): 6/6 PASS.
- Full `SECURITY DEFINER` inventory (`..._45_*.txt`): all 12 functions,
  `PUBLIC EXECUTE = false` throughout; `fn_record_node_failed`'s
  grantee list unchanged; `fn_start_workflow_execution` confirmed to
  still include `app_platform_admin`, matching the review decision above.

---

## PostgreSQL 16 validation

| Check | Result |
|---|---|
| Fresh `voice_agent_pg16_finalfresh3`: `001_5B → … → 100_5G1` | **PASS, exit 0**, single head. `..._46_..._48_*.txt` |
| Incremental `voice_agent_pg16_incremental3`: `099_5C1` then `100_5G1` alone | **PASS, exit 0** both steps. `..._49_*.txt`, `..._50_*.txt` |
| `alembic history` | Single linear 100-entry chain, no branch. `..._51_*.txt` |
| `downgrade()` | Raises `NotImplementedError`; DB remains at `100_5G1`. `..._52_*.txt` |

---

## Adversarial questions (§32 of the governing task)

| # | Question | Required answer | Confirmed |
|---|---|---|---|
| 1 | Can an ordinary worker move `SUBMITTING → FAILED`? | NO | ✅ `NOT_FAILABLE_AFTER_SUBMISSION` |
| 2 | Can a timeout become retryable automatically? | NO | ✅ must go to `AMBIGUOUS` |
| 3 | Can `SUBMITTING` become reclaimable after lease expiry? | NO | ✅ unchanged from prior pass |
| 4 | Can `AMBIGUOUS` become reclaimable? | NO | ✅ unchanged |
| 5 | Can `CLAIMED → FAILED` still be a safe pre-submission failure? | YES | ✅ |
| 6 | Can `app_api` publish with `NULL` precondition? | Call must fail | ✅ exception |
| 7 | Can `app_api` publish with a stale precondition? | `PRECONDITION_FAILED`, no version | ✅ |
| 8 | Can the correct exact-draft publish succeed? | YES | ✅ |
| 9 | Can raw SQL publish bypass the guarded function? | NO | ✅ all three roles denied |
| 10 | Did Archive↔StartExecution safety remain intact? | YES | ✅ 7/7 regression |

All ten required answers confirmed live.

---

## Summary

**Final verdict: APPROVED — PHASE 6I READY TO FREEZE**, with one
non-blocking, explicitly flagged product-policy question (the
`app_platform_admin`/`fn_start_workflow_execution` grant) left open for
the product owner rather than decided silently.
