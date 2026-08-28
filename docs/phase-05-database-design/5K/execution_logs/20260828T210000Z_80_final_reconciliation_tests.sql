\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set orgb '''00000000-0000-0000-0000-0000000000b1'''
\set agentva '''00000000-0000-0000-0000-0000000000a3'''
\set tpna '''00000000-0000-0000-0000-0000000000a4'''

-- Fixture: create three AMBIGUOUS dispatch keys and one CONFIRMED key for the tests below.
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876511001', :agentva, :tpna, 'lead-r1', repeat('r',63) || '1');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876511002', :agentva, :tpna, 'lead-r2', repeat('r',63) || '2');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876511003', :agentva, :tpna, 'lead-r3', repeat('r',63) || '3');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876511004', :agentva, :tpna, 'lead-r4', repeat('r',63) || '4');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('r',63) || '1', :orga, 'w1', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('r',63) || '1', :orga, 'w1');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('r',63) || '1', :orga, 'w1', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('r',63) || '2', :orga, 'w2', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('r',63) || '2', :orga, 'w2');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('r',63) || '2', :orga, 'w2', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('r',63) || '3', :orga, 'w3', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('r',63) || '3', :orga, 'w3');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('r',63) || '3', :orga, 'w3', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('r',63) || '4', :orga, 'w4', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('r',63) || '4', :orga, 'w4');
SELECT * FROM voice.fn_record_dispatch_confirmed(repeat('r',63) || '4', :orga, 'w4', 'PROVIDER-CONFIRMED-4');
RESET ROLE;

\echo ==== TEST 17/21: ordinary app_api attempts direct reconciliation -- MUST BE DENIED ====
SET ROLE app_api;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '1', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'attacker-api', NULL, 'forged evidence');
RESET ROLE;

\echo ==== TEST 18/21: generic app_worker attempts direct reconciliation -- MUST BE DENIED ====
SET ROLE app_worker;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '1', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'attacker-worker', NULL, 'forged evidence');
RESET ROLE;

\echo -- confirm dispatch key 1 is STILL AMBIGUOUS after both denied attempts --
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('r',63) || '1';

\echo ==== TEST 8/9 (authorization forgery attempt): reconciled_by='admin'/'provider' must NOT grant privilege when caller role itself lacks EXECUTE ====
SET ROLE app_api;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '1', :orga, 'CONFIRMED', 'PROVIDER_CALLBACK', 'admin', 'FORGED-REF', 'trying reconciled_by=admin');
RESET ROLE;

\echo ==== TEST 19: authorized reconciler (app_voice_reconciler) resolves AMBIGUOUS -> CONFIRMED ====
SET ROLE app_voice_reconciler;
SET app.tenant_id = :orga;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '1', :orga, 'CONFIRMED', 'PROVIDER_CALLBACK', 'webhook-handler-1', 'PROVIDER-CALL-REF-R1', 'matched via provider_request_ref callback');
SELECT dispatch_state, provider_call_ref, reconciliation_source, reconciled_by, reconciled_at IS NOT NULL AS has_ts FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('r',63) || '1';
RESET ROLE;
RESET app.tenant_id;

\echo ==== TEST 20: authorized reconciler resolves AMBIGUOUS -> FAILED with authoritative negative evidence, then verify retry becomes eligible ====
SET ROLE app_voice_reconciler;
SET app.tenant_id = :orga;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '2', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'reconciler-svc', NULL, 'authoritative provider lookup: call never created');
SELECT dispatch_state, reconciliation_source, last_error FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('r',63) || '2';
RESET ROLE;
\echo -- normal retry flow: fresh claim of the now-FAILED row must succeed --
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('r',63) || '2', :orga, 'w2-retry', 30);
RESET ROLE;
RESET app.tenant_id;

\echo ==== TEST (§6): FAILED reconciliation with NO evidence must be rejected even for the authorized role ====
SET ROLE app_voice_reconciler;
SET app.tenant_id = :orga;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '3', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'reconciler-svc', NULL, '');
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '3', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'reconciler-svc', NULL, NULL);
RESET ROLE;
\echo -- confirm dispatch key 3 is STILL AMBIGUOUS (both no-evidence attempts rejected) --
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('r',63) || '3';
RESET app.tenant_id;

\echo ==== TEST 22: CONFIRMED state immutability -- authorized reconciler attempts CONFIRMED -> FAILED, must be denied ====
SET ROLE app_voice_reconciler;
SET app.tenant_id = :orga;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '4', :orga, 'FAILED', 'OPERATOR', 'operator-1', NULL, 'attempt to reopen a confirmed call');
RESET ROLE;
\echo -- confirm dispatch key 4 is STILL CONFIRMED --
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('r',63) || '4';
RESET app.tenant_id;

\echo ==== TEST 23: cross-tenant reconciliation -- Org B attempts to reconcile Org A dispatch key 3 (still AMBIGUOUS) ====
SET ROLE app_voice_reconciler;
SET app.tenant_id = :orgb;
SELECT * FROM voice.fn_reconcile_dispatch_outcome(repeat('r',63) || '3', :orgb, 'FAILED', 'OPERATOR', 'org-b-operator', NULL, 'org b trying to resolve org a dispatch');
RESET ROLE;
RESET app.tenant_id;
\echo -- confirm dispatch key 3 organization_id and state are unchanged, no cross-tenant leak --
SELECT organization_id, dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('r',63) || '3';

\echo ==== TEST 24: reconciliation provenance persisted, direct query ====
SELECT dispatch_idempotency_key, dispatch_state, reconciliation_source, reconciled_by, reconciled_at IS NOT NULL AS has_ts, provider_call_ref, last_error
FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key IN (repeat('r',63) || '1', repeat('r',63) || '2') ORDER BY dispatch_idempotency_key;

\echo ==== TEST: audit event written for successful reconciliations ====
SELECT action_kind, actor_type, actor_name, resource_type, resource_id, outcome, resource_snapshot
FROM audit.audit_events WHERE action_kind = 'VOICE_DISPATCH_RECONCILED' ORDER BY occurred_at;

\echo ==== Privilege matrix: has_function_privilege per role ====
SELECT r.rolname, has_function_privilege(r.rolname, 'voice.fn_reconcile_dispatch_outcome(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT,TEXT)', 'EXECUTE') AS can_execute
FROM pg_roles r WHERE r.rolname LIKE 'app_%' ORDER BY r.rolname;

\echo RECONCILE_TESTS_DONE
