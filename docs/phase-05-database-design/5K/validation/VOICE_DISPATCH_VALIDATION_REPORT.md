# Voice Provider-Dispatch Durability Validation Report

**Date:** 2026-08-28 (Phase 6H Final Blocker Remediation pass)
**Scope:** live proof, on PostgreSQL 16.10, that Blocker A (expired-CLAIMED
double-dial hazard) and Blocker D (idempotency replay tenant/payload
validation) are closed, and that the full crash/timeout/reconciliation
failure matrix behaves as designed. Full raw transcript:
`execution_logs/20260828T143000Z_69_privilege_and_dispatch_state_machine_tests.txt`.

## The original defect (Blocker A), restated precisely

Before this pass, a `CLAIMED` row's lease expiring was the *only* signal
`fn_claim_dispatch_for_provider_submission()` used to decide whether a row
was safe to re-claim — and `CLAIMED` covered the entire span from "worker
acquired the lease" through "provider definitely responded," including the
moment the worker actually calls the telephony provider. A worker that
crashed after the provider received (and possibly accepted) the request,
but before writing anything back to the database, left a row that would
eventually become re-claimable — permitting a second worker to call the
provider again and physically dial the customer twice.

## The fix, proven live

`CLAIMED` was split into `CLAIMED` (preparation lease, provider not yet
contacted) and `SUBMITTING` (a new, durable state committed by
`fn_begin_provider_submission()` **before** the caller is permitted to
invoke the telephony provider). `fn_claim_dispatch_for_provider_submission`
never reclaims a `SUBMITTING` row, regardless of how stale its lease
becomes.

### Test: crash before the SUBMITTING boundary is ever reached (Case A — safe)

Dispatch key `3333...` was claimed with a 5-second lease and **never**
advanced to `SUBMITTING` (simulating a crash during local preparation, before
any network call). After the lease genuinely expired (`pg_sleep(6)`):

```
claimed | call_session_id | provider_request_ref | attempt_count | reason
--------+------------------+-----------------------+---------------+--------
t       | 01a048cf-...     | 333...3               |             2 |
```

**Reclaimed successfully** — attempt_count incremented to 2, confirming
this is a genuine second claim, not a no-op. The recovering worker then
completed `fn_begin_provider_submission` → `fn_record_dispatch_confirmed`
normally. The call was not lost.

### Test: crash AFTER the SUBMITTING boundary commits (Case B/C — THE critical assertion)

Dispatch key `4444...` was claimed, then `fn_begin_provider_submission`
committed `SUBMITTING` (returned `began=t`) — then the "worker" stopped,
calling nothing further. After the same 5-second lease genuinely expired:

```
claimed | call_session_id | provider_request_ref | attempt_count | reason
--------+------------------+-----------------------+---------------+--------------------------
f       | 01a048cf-...     | 444...4               |             1 | NOT_CLAIMABLE_SUBMITTING
```

**Reclaim correctly refused**, even though the lease had genuinely expired
and nothing else had touched the row since — `attempt_count` is still `1`
(the value set by the original claim), proving no reclaim occurred. This is
the direct, empirical closure of Blocker A: a second worker cannot obtain
permission to call the telephony provider for this dispatch key.

**Test-artifact disclosure, not a product defect:** the very next line in
the transcript is a direct `SELECT dispatch_state, claimed_by,
claim_expires_at, submission_started_at FROM voice.call_dispatch_keys
WHERE ...`, still under `SET ROLE app_worker`, which returned `(0 rows)` —
not because the row was gone, but because this test script never set
`app.tenant_id` for that session, and `voice.call_dispatch_keys`' RLS policy
(`organization_id = organization.current_tenant_id()`) silently filters
everything to zero rows when that setting is unset, for a role without
`BYPASSRLS`. The actual proof of Blocker A's closure is the `fn_claim_...`
call's own return row above (which is `SECURITY DEFINER` and therefore
unaffected by this), not this follow-up `SELECT` — the `SELECT`'s empty
result is called out here explicitly rather than silently reported as
confirming a state it did not actually observe.

A same-worker retry of `fn_begin_provider_submission` after its own lease
lapsed was also tested and correctly failed closed:

```
began | reason
-------+------------------
f      | NOT_CLAIM_HOLDER
```

### Test: resolving a stuck SUBMITTING row via reconciliation (delayed callback simulation)

`fn_reconcile_dispatch_outcome(key='4444...', outcome='CONFIRMED',
provider_call_ref='PROVIDER-CALL-REF-004')` — identity-correlated (no
`claimed_by` check, since the original worker/lease is presumed gone):

```
reconciled | reason
------------+--------
t          |
```

`reconciled=t` confirms exactly one row was matched and updated by this
call (the function's own `GET DIAGNOSTICS`-based row count, not a
follow-up `SELECT` — the same RLS-without-`app.tenant_id` artifact noted
above applies equally to any direct `SELECT` run under `SET ROLE app_api`
in this test script, so this report relies on the guarded function's own
return value rather than a follow-up row read). This is the mechanism that
resolves a genuine external ambiguity without ever risking a second
physical provider call.

### Test: AMBIGUOUS (provider timeout) never blindly retried, but IS reconcilable to FAILED

Dispatch key `5555...`: claimed → `SUBMITTING` → `fn_record_dispatch_ambiguous`
(simulating a provider timeout). A reclaim attempt was correctly refused
(`NOT_CLAIMABLE_AMBIGUOUS`). `fn_reconcile_dispatch_outcome(outcome='FAILED')`
(simulating a provider-side lookup that positively found no such call) then
succeeded, and a fresh claim of the now-`FAILED` row succeeded
(`attempt_count=2`) — proving `AMBIGUOUS`/`FAILED` are genuinely different,
not the same state under two names.

### Test: definite pre-acceptance rejection (FAILED from SUBMITTING)

Dispatch key `6666...`: claimed → `SUBMITTING` → `fn_record_dispatch_failed`
(simulating a synchronous 422 from the provider, proving no call was ever
accepted). Retry immediately allowed (`attempt_count=2`).

### Test: provider-dispatch concurrency (INV-VOICE-DISPATCH-02)

Two genuinely concurrent `psql` processes, synchronized via an identical
`pg_sleep(2)` start gate, both called
`fn_claim_dispatch_for_provider_submission` on the identical `RESERVED`
dispatch key `rrrr...`:

```
Connection A: claimed=f, reason=NOT_CLAIMABLE_CLAIMED
Connection B: claimed=t
```

Exactly one winner under real, overlapping concurrent load — not simulated
sequentially. Full transcript:
`execution_logs/20260828T143000Z_71_voice_dispatch_claim_concurrency_race.txt`.

## Idempotency tenant/payload validation (Blocker D)

Dispatch key `1111...` (`K1`), Org A, payload P1 (`to_number=
+919876500001`):

| Call | Result |
|---|---|
| First call, key K1, payload P1 | `is_new=t, outcome=CREATED` |
| Same key K1, same payload P1 | `is_new=f, outcome=REPLAYED`, same `call_session_id` |
| Same key K1, **different** payload (`to_number=+919876500099`) | `outcome=IDEMPOTENCY_KEY_REUSE_MISMATCH`, `call_session_id=NULL` — no session identity disclosed |
| Same key K1, called by **Org B** | `ERROR: fn_initiate_outbound_call_idempotent: dispatch_idempotency_key not available for organization <org-b-id>` — non-disclosing exception, never reveals Org A's key exists |

The payload fingerprint is computed inside the function itself from the
actual call parameters (organization_id, campaign_lead_ref, to_number,
from_number, agent_version_id, tenant_phone_number_id) via
`public.digest(jsonb_build_object(...)::text, 'sha256')` — never accepted as
a caller-supplied value, so a caller cannot forge a matching fingerprint for
a request it didn't actually make.

## Function count and privilege inspection

`SELECT count(*) FROM pg_proc ... WHERE nspname='voice' AND proname LIKE
'fn_%'` → **8**, matching the migration's own header claim exactly (the
prior pass's stale "five functions" reference is corrected everywhere —
see `MIGRATION_MANIFEST.md` and the Alembic wrapper). All 11 `SECURITY
DEFINER` functions touched by 098/099 (3 `campaign.fn_*` + 8 `voice.fn_*`)
were inspected directly against `pg_proc.proconfig` and confirmed to carry
their documented, minimal `search_path`; `has_function_privilege('public',
oid, 'EXECUTE')` returned `false` for every one of them.

## Addendum (2026-08-28, Final Micro-Remediation pass) — reconciliation authorization boundary

The prior pass's own `fn_reconcile_dispatch_outcome()` — the function that
can convert `AMBIGUOUS`/`SUBMITTING` into `FAILED`, re-opening physical
retry eligibility — granted `EXECUTE` to `app_api` and `app_worker`, the two
broad application roles. This addendum closes that gap. Full raw
transcript: `execution_logs/20260828T210000Z_81_final_reconciliation_privilege_and_provenance_output.txt`.

**Role model inspected first:** the existing catalog (`app_api`,
`app_worker`, `app_readonly`, `app_migration`, `app_platform_admin`) was
checked for a narrow-enough existing capability before creating anything
new — none fit (see `MIGRATION_MANIFEST.md`'s Final Micro-Remediation entry
for the full reasoning). A new role, `app_voice_reconciler` (`LOGIN`, `NOT
BYPASSRLS`, no table DML, `EXECUTE` on exactly one function), was created.

**Privilege tests, on PostgreSQL 16.10:**

| Caller | Action | Result |
|---|---|---|
| `app_api` | `fn_reconcile_dispatch_outcome(..., 'FAILED', ...)` | `ERROR: permission denied for function fn_reconcile_dispatch_outcome` |
| `app_worker` | same | `ERROR: permission denied for function fn_reconcile_dispatch_outcome` |
| `app_api`, forging `p_reconciled_by = 'admin'` | same | Still `permission denied` — the forged parameter never reaches the function body |
| `app_voice_reconciler` | `AMBIGUOUS → CONFIRMED` (with `provider_call_ref`) | Succeeds; `reconciliation_source='PROVIDER_CALLBACK'` persisted |
| `app_voice_reconciler` | `AMBIGUOUS → FAILED` (with evidence note) | Succeeds; the row is then genuinely re-claimable (`attempt_count` incremented) — proves `FAILED` really reopens retry |
| `app_voice_reconciler` | `AMBIGUOUS → FAILED`, empty-string note | `ERROR: p_note (evidence description) is required when p_outcome = FAILED` |
| `app_voice_reconciler` | `AMBIGUOUS → FAILED`, `NULL` note | Same error |
| `app_voice_reconciler` | `CONFIRMED → FAILED` (attempting to reopen a known-accepted call) | `reconciled=false, reason=NOT_RECONCILABLE_OR_NOT_FOUND` — row remains `CONFIRMED` |
| `app_voice_reconciler`, Org B credentials, targeting an Org A dispatch key | `AMBIGUOUS → FAILED` | `reconciled=false, reason=NOT_RECONCILABLE_OR_NOT_FOUND` — non-disclosing; row's `organization_id`/state confirmed unchanged afterward |

`has_function_privilege()` across all 6 roles: only `app_voice_reconciler`
and `app_platform_admin` show `true`; `app_api`, `app_worker`,
`app_readonly`, `app_migration` all show `false`.

**Provenance, verified by direct query (not assumed present):**
```
 dispatch_state | reconciliation_source | reconciled_by     | has_ts | provider_call_ref     | last_error
 CONFIRMED      | PROVIDER_CALLBACK     | webhook-handler-1 | t      | PROVIDER-CALL-REF-R1  | matched via provider_request_ref callback
 FAILED         | PROVIDER_LOOKUP       | reconciler-svc    | t      |                       | authoritative provider lookup: call never created
```

**Audit evidence, verified by direct query against `audit.audit_events`:**
both successful reconciliations produced a `VOICE_DISPATCH_RECONCILED`
event with `actor_type='WORKER'` (both tested sources were provider-driven,
not `OPERATOR`), the correct `resource_id` (the call session), `outcome=
'SUCCESS'`, and a `resource_snapshot` containing only the dispatch key,
old/new state, reconciliation source, and provider reference — no phone
number or other PII.

**Test-script artifact, disclosed:** two follow-up diagnostic `SELECT`s
against `voice.call_dispatch_keys`, issued while still `SET ROLE
app_voice_reconciler`, failed with `permission denied for table
call_dispatch_keys` — confirming this role has no privilege on the table
itself beyond the one function's `EXECUTE`, exactly as intended (true least
privilege). The provenance table above was retrieved via a follow-up query
run as the test session's superuser instead.

**Regression, unchanged:** the full sixth-batch scenario set (expired-
`CLAIMED`-before-`SUBMITTING` recovery, the `SUBMITTING` hard-stop,
same-key/same-payload replay, same-key/different-payload mismatch,
cross-tenant `fn_initiate_outbound_call_idempotent()` denial) was re-run on
this pass's own fresh PostgreSQL 16 instance and reproduced identical
results — this pass's changes did not touch any of that logic.

## Addendum (2026-08-28, Final Micro-Fix pass) — non-forgeable reconciliation provenance

The prior addendum's `fn_reconcile_dispatch_outcome()` correctly restricted
*who* could reconcile but still let either authorized caller freely choose
*which* provenance category to record via a plain `p_reconciliation_source`
parameter — the automated reconciler could pass `'OPERATOR'`, or the
operator role could pass `'PROVIDER_CALLBACK'`, misrepresenting which
trusted path actually made the decision. This addendum closes that gap by
splitting the function into three: `fn_reconcile_dispatch_outcome_internal()`
(granted to no role at all), `fn_reconcile_dispatch_from_provider()`
(`EXECUTE`: `app_voice_reconciler` only; source restricted by an internal
`CHECK` to `PROVIDER_CALLBACK`/`PROVIDER_LOOKUP`), and
`fn_reconcile_dispatch_by_operator()` (`EXECUTE`: `app_platform_admin`
only; source hardcoded to `'OPERATOR'`, no source parameter exists). Full
raw transcript: `execution_logs/20260828T231500Z_91_final_provenance_output.txt`.

**The critical forgery test, on PostgreSQL 16.10:**

```sql
-- app_voice_reconciler GENUINELY holds EXECUTE on this function:
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(
  <key>, <org>, 'CONFIRMED', 'OPERATOR', 'reconciler-claiming-operator', 'FAKE-OPERATOR-REF', NULL
);
```
```
ERROR:  fn_reconcile_dispatch_from_provider: invalid p_provider_source OPERATOR --
only PROVIDER_CALLBACK or PROVIDER_LOOKUP may be recorded through this capability;
OPERATOR provenance cannot be produced by the automated reconciliation path
```

This is rejected by the **function body's own `CHECK`**, not by a missing
`GRANT` — proving the restriction is structural, not merely a privilege
gate the caller happened not to have.

**Full authorization/forgery matrix, on PostgreSQL 16.10:**

| Caller | Function | Result |
|---|---|---|
| `app_api` | either | `permission denied` |
| `app_worker` | either | `permission denied` |
| `app_voice_reconciler` | `fn_reconcile_dispatch_by_operator` | `permission denied` (no grant) |
| `app_voice_reconciler` | `fn_reconcile_dispatch_from_provider`, `p_provider_source='OPERATOR'` | Rejected by internal `CHECK` (has the grant, value is illegal) |
| `app_platform_admin` | `fn_reconcile_dispatch_from_provider` | `permission denied` (no grant) |
| `app_voice_reconciler` | `fn_reconcile_dispatch_from_provider`, `PROVIDER_CALLBACK`/`PROVIDER_LOOKUP` | Succeeds; correct provenance persisted |
| `app_platform_admin` | `fn_reconcile_dispatch_by_operator` | Succeeds; `OPERATOR` provenance hardcoded regardless of any input |

**Provenance and audit, verified by direct query:** the provider-callback
path recorded `reconciliation_source='PROVIDER_CALLBACK'`; the
provider-lookup path (`FAILED`) recorded `'PROVIDER_LOOKUP'` and the row
became genuinely re-claimable afterward; the operator path recorded
`'OPERATOR'` for both a `CONFIRMED` and an evidence-backed `FAILED`
outcome. `audit.audit_events` confirmed the correct `actor_type` for all
four successful reconciliations in this pass: `WORKER` for both
provider-driven sources, `PLATFORM_ADMIN` for both operator-driven ones —
matching the function actually called, never a caller-supplied value.
`has_function_privilege()` across all 6 roles confirmed an exact 1:1
mapping: `app_voice_reconciler` → `fn_reconcile_dispatch_from_provider`
only; `app_platform_admin` → `fn_reconcile_dispatch_by_operator` only.

**Evidence requirement, confirmed shared across both paths:** the
operator path's `FAILED` branch rejected an empty-string and a `NULL`
evidence note identically to the provider path (both route through the
same internal check), then succeeded once real evidence was supplied.

**Immutability and tenancy, re-confirmed through both new functions:**
`CONFIRMED → FAILED` was attempted through both functions against an
already-`CONFIRMED` row and refused both times
(`NOT_RECONCILABLE_OR_NOT_FOUND`). A cross-tenant attempt was made through
both functions and refused both times, non-disclosingly, with the target
row's `organization_id`/state confirmed unchanged.

**Regression, unchanged:** the full sixth/seventh-batch scenario set
(expired-`CLAIMED`-before-`SUBMITTING` recovery, the `SUBMITTING`
hard-stop, same-key/same-payload replay, same-key/different-payload
mismatch, same-key cross-tenant denial, the synchronous `AMBIGUOUS` path)
was re-run on this pass's own genuinely fresh PostgreSQL 16 instance and
reproduced identical results.

## Addendum (2026-08-29, Final Admin-DML Hardening pass) — removing the platform-admin direct DML bypass

Every prior privilege pass restricted a *different* role. `app_platform_admin`'s own original `GRANT SELECT, INSERT, UPDATE, DELETE` on `voice.call_dispatch_keys` — present since the table was first created — was never touched, and could bypass `CONFIRMED` immutability and the freshly-established provenance split entirely via one raw `UPDATE`. This addendum removes `INSERT`/`UPDATE`/`DELETE` from that grant, retaining only `SELECT`. Full raw transcript: `execution_logs/20260829T003700Z_101_final_admin_dml_output.txt`.

**Catalog inspection, before any test ran:**
```sql
SELECT grantee, string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
FROM information_schema.role_table_grants
WHERE table_schema = 'voice' AND table_name = 'call_dispatch_keys'
GROUP BY grantee ORDER BY grantee;
```
```
      grantee       | privs
--------------------+--------
 app_api            | SELECT
 app_platform_admin | SELECT
 app_readonly       | SELECT
 app_worker         | SELECT
```
Confirmed on PostgreSQL 16.10: no role but the table owner holds `INSERT`/`UPDATE`/`DELETE`.

**Direct DML tests, `app_platform_admin`:**

| Attempt | Result |
|---|---|
| `SELECT dispatch_state FROM voice.call_dispatch_keys WHERE ...` (a live `CONFIRMED` row) | Succeeds — `SELECT` retained, as designed |
| `INSERT INTO voice.call_dispatch_keys (...)` | `ERROR: permission denied for table call_dispatch_keys` |
| `UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE ...` (targeting a live `AMBIGUOUS` row) | `ERROR: permission denied for table call_dispatch_keys` |
| `DELETE FROM voice.call_dispatch_keys WHERE ...` | `ERROR: permission denied for table call_dispatch_keys` |
| `UPDATE voice.call_dispatch_keys SET reconciliation_source = 'PROVIDER_CALLBACK', reconciled_by = 'fake-provider' WHERE ...` (the provenance-forgery test) | `ERROR: permission denied for table call_dispatch_keys` |
| `UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE ...` (targeting an already-`CONFIRMED` row) | `ERROR: permission denied for table call_dispatch_keys`; row confirmed still `CONFIRMED` by a follow-up `SELECT` |

**Guarded-path regression, proving the privilege removal does not break legitimate reconciliation:**

| Caller | Call | Result |
|---|---|---|
| `app_platform_admin` | `fn_reconcile_dispatch_by_operator(..., 'FAILED', ..., 'authoritative provider console lookup shows no call was ever created')` on a genuine `AMBIGUOUS` row | Succeeds; `reconciliation_source='OPERATOR'`, `reconciled_by='operator-jane'` persisted |
| `app_platform_admin` | `fn_reconcile_dispatch_by_operator(..., 'FAILED', ...)` on an already-`CONFIRMED` row | `reconciled=false, reason=NOT_RECONCILABLE_OR_NOT_FOUND` — row remains `CONFIRMED` (immutability holds through the guarded path independently of the privilege fix) |
| `app_voice_reconciler` | `fn_reconcile_dispatch_from_provider(..., 'CONFIRMED', 'PROVIDER_CALLBACK', ...)` on a genuine `AMBIGUOUS` row | Succeeds; `reconciliation_source='PROVIDER_CALLBACK'` persisted |

**Regression, `app_api`/`app_worker`/`app_voice_reconciler` direct DML still denied:** all three re-attempted direct `INSERT`/`UPDATE` and were denied identically to every prior pass — this pass touched only `app_platform_admin`'s grant.

**The analogous fix on `campaign.campaign_contact_identities`:** the identical grant pattern was found and closed the same way — see `validation/CAMPAIGN_PRIVILEGE_VALIDATION_REPORT.md`'s own addendum for the full evidence.

**Final privilege matrix, `has_table_privilege()` across all 6 roles:**
```
       rolname        | sel | ins | upd | del
----------------------+-----+-----+-----+-----
 app_api              | t   | f   | f   | f
 app_migration        | f   | f   | f   | f
 app_platform_admin   | t   | f   | f   | f
 app_readonly         | t   | f   | f   | f
 app_voice_reconciler | f   | f   | f   | f
 app_worker           | t   | f   | f   | f
```
`app_voice_reconciler` shows `f` for `SELECT` too — it was never granted table-level access at all, only `EXECUTE` on one function, the true-least-privilege design already established in the sixth batch.

**Regression, full suite, unchanged:** expired-`CLAIMED`-before-`SUBMITTING` recovery, the `SUBMITTING` hard-stop, the `AMBIGUOUS` hard-stop, same-key/same-payload replay, same-key/different-payload mismatch, and same-key cross-tenant denial were all re-run on this pass's own fresh instance and reproduced identical results — no function body was touched by this pass, only the two `GRANT` statements.

## What remains an accepted, disclosed limitation

A crash strictly between the `SUBMITTING` commit and the process actually
transmitting bytes on the wire is indistinguishable from a crash during the
provider's own processing of an already-sent request — both are handled
identically (never auto-retried) because that is the only sound choice.
Whether the *telephony provider itself* received a request whose response
was lost cannot be resolved by any platform-side database mechanism alone;
it depends on `fn_reconcile_dispatch_outcome` being driven by a genuine
provider callback or lookup, which in turn depends on the provider adapter
actually supporting reference echo-back — not verified for Exotel
specifically in this or any prior pass (disclosed in 6D §28.10a and 6H
§18.4, not claimed away here).
