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
