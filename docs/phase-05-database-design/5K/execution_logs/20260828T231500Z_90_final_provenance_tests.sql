\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set orgb '''00000000-0000-0000-0000-0000000000b1'''
\set agentva '''00000000-0000-0000-0000-0000000000a3'''
\set tpna '''00000000-0000-0000-0000-0000000000a4'''

-- Fixture: five AMBIGUOUS dispatch keys + one CONFIRMED key for the tests below.
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876533001', :agentva, :tpna, 'lead-p1', repeat('p',63) || '1');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876533002', :agentva, :tpna, 'lead-p2', repeat('p',63) || '2');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876533003', :agentva, :tpna, 'lead-p3', repeat('p',63) || '3');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876533004', :agentva, :tpna, 'lead-p4', repeat('p',63) || '4');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876533005', :agentva, :tpna, 'lead-p5', repeat('p',63) || '5');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876533006', :agentva, :tpna, 'lead-p6', repeat('p',63) || '6');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '1', :orga, 'w1', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('p',63) || '1', :orga, 'w1');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('p',63) || '1', :orga, 'w1', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '2', :orga, 'w2', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('p',63) || '2', :orga, 'w2');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('p',63) || '2', :orga, 'w2', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '3', :orga, 'w3', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('p',63) || '3', :orga, 'w3');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('p',63) || '3', :orga, 'w3', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '4', :orga, 'w4', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('p',63) || '4', :orga, 'w4');
SELECT * FROM voice.fn_record_dispatch_confirmed(repeat('p',63) || '4', :orga, 'w4', 'PROVIDER-CONFIRMED-4');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '5', :orga, 'w5', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('p',63) || '5', :orga, 'w5');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('p',63) || '5', :orga, 'w5', 'timeout');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '6', :orga, 'w6', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('p',63) || '6', :orga, 'w6');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('p',63) || '6', :orga, 'w6', 'timeout');
RESET ROLE;

\echo ==== TEST 27: app_api / app_worker denied on BOTH reconciliation functions ====
SET ROLE app_api;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '1', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'attacker', NULL, 'forged');
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '1', :orga, 'FAILED', 'attacker', NULL, 'forged');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '1', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'attacker', NULL, 'forged');
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '1', :orga, 'FAILED', 'attacker', NULL, 'forged');
RESET ROLE;

\echo ==== TEST 19/37: provider reconciler (app_voice_reconciler) CANNOT call the operator function -- must be DENIED at the privilege layer ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '1', :orga, 'CONFIRMED', 'reconciler-pretending-to-be-admin', 'FAKE-REF', NULL);
RESET ROLE;

\echo ==== TEST (forgery, function-level): app_voice_reconciler HOLDS EXECUTE on fn_reconcile_dispatch_from_provider, but passes p_provider_source=OPERATOR -- must be REJECTED by the function's own internal CHECK, not merely by a grant ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '1', :orga, 'CONFIRMED', 'OPERATOR', 'reconciler-claiming-operator', 'FAKE-OPERATOR-REF', NULL);
RESET ROLE;
\echo -- confirm dispatch key 1 is STILL AMBIGUOUS after all three forgery/denial attempts above --
SELECT dispatch_state, reconciliation_source FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '1';

\echo ==== TEST 20/37: platform admin CANNOT call the provider function -- must be DENIED at the privilege layer ====
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '1', :orga, 'CONFIRMED', 'PROVIDER_CALLBACK', 'admin-pretending-to-be-provider', 'FAKE-PROVIDER-REF', NULL);
RESET ROLE;
\echo -- confirm dispatch key 1 is STILL AMBIGUOUS --
SELECT dispatch_state, reconciliation_source FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '1';

\echo ==== TEST 21: genuine provider callback path -- AMBIGUOUS -> CONFIRMED via fn_reconcile_dispatch_from_provider ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '1', :orga, 'CONFIRMED', 'PROVIDER_CALLBACK', 'webhook-handler-1', 'PROVIDER-CALL-REF-P1', 'matched via provider_request_ref callback');
RESET ROLE;
SELECT dispatch_state, reconciliation_source, reconciled_by, provider_call_ref FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '1';

\echo ==== TEST 22: genuine provider lookup path -- AMBIGUOUS -> FAILED via fn_reconcile_dispatch_from_provider, then retry eligible ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '2', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'reconciler-svc', NULL, 'authoritative provider lookup: call never created');
RESET ROLE;
SELECT dispatch_state, reconciliation_source FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '2';
SET ROLE app_worker;
SELECT claimed, reason FROM voice.fn_claim_dispatch_for_provider_submission(repeat('p',63) || '2', :orga, 'w2-retry', 30);
RESET ROLE;

\echo ==== TEST 23: genuine operator path -- AMBIGUOUS -> CONFIRMED via fn_reconcile_dispatch_by_operator ====
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '3', :orga, 'CONFIRMED', 'operator-jane', 'PROVIDER-CALL-REF-P3-OPERATOR-CONFIRMED', 'operator confirmed via provider console lookup');
RESET ROLE;
SELECT dispatch_state, reconciliation_source, reconciled_by FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '3';

\echo ==== TEST 24: operator path requires evidence for FAILED (empty then NULL note both rejected) ====
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '5', :orga, 'FAILED', 'operator-jane', NULL, '');
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '5', :orga, 'FAILED', 'operator-jane', NULL, NULL);
RESET ROLE;
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '5';
\echo -- now with acceptable evidence: must succeed --
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '5', :orga, 'FAILED', 'operator-jane', NULL, 'operator confirmed via provider console: no call record exists');
RESET ROLE;
SELECT dispatch_state, reconciliation_source FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '5';

\echo ==== TEST 25: CONFIRMED immutability -- both functions attempt CONFIRMED(key 4) -> FAILED, must be denied ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '4', :orga, 'FAILED', 'PROVIDER_LOOKUP', 'reconciler-svc', NULL, 'attempt to reopen a confirmed call');
RESET ROLE;
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '4', :orga, 'FAILED', 'operator-jane', NULL, 'attempt to reopen a confirmed call');
RESET ROLE;
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '4';

\echo ==== TEST 26: cross-tenant -- Org B attempts both functions against Org A dispatch key 6 (still AMBIGUOUS) ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('p',63) || '6', :orgb, 'FAILED', 'PROVIDER_LOOKUP', 'org-b-reconciler', NULL, 'org b trying to resolve org a dispatch');
RESET ROLE;
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('p',63) || '6', :orgb, 'FAILED', 'org-b-operator', NULL, 'org b trying to resolve org a dispatch');
RESET ROLE;
SELECT organization_id, dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('p',63) || '6';

\echo ==== Audit verification: actor_type/source correctness for the three successful reconciliations ====
SELECT action_kind, actor_type, actor_name, outcome, resource_snapshot->>'reconciliation_source' AS src
FROM audit.audit_events WHERE action_kind = 'VOICE_DISPATCH_RECONCILED' ORDER BY occurred_at;

\echo ==== Privilege matrix ====
SELECT r.rolname,
  has_function_privilege(r.rolname, 'voice.fn_reconcile_dispatch_from_provider(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT,TEXT)', 'EXECUTE') AS can_exec_provider,
  has_function_privilege(r.rolname, 'voice.fn_reconcile_dispatch_by_operator(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT)', 'EXECUTE') AS can_exec_operator
FROM pg_roles r WHERE r.rolname LIKE 'app_%' ORDER BY r.rolname;

\echo PROVENANCE_TESTS_DONE
