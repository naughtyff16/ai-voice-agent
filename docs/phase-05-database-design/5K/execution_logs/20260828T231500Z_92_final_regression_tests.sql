\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set orgb '''00000000-0000-0000-0000-0000000000b1'''
\set agentva '''00000000-0000-0000-0000-0000000000a3'''
\set tpna '''00000000-0000-0000-0000-0000000000a4'''

\echo ==== REGRESSION: expired CLAIMED before SUBMITTING -> safe reclaim ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544001', :agentva, :tpna, 'lead-y1', repeat('y',63) || '1');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('y',63) || '1', :orga, 'worker-crash-A', 5);
RESET ROLE;
SELECT pg_sleep(6);
SET ROLE app_worker;
SELECT claimed, reason FROM voice.fn_claim_dispatch_for_provider_submission(repeat('y',63) || '1', :orga, 'worker-recover-A', 30);
RESET ROLE;

\echo ==== REGRESSION: SUBMITTING hard-stop (the P0 assertion) still holds ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544002', :agentva, :tpna, 'lead-y2', repeat('y',63) || '2');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('y',63) || '2', :orga, 'worker-crash-B', 5);
SELECT * FROM voice.fn_begin_provider_submission(repeat('y',63) || '2', :orga, 'worker-crash-B');
RESET ROLE;
SELECT pg_sleep(6);
SET ROLE app_worker;
SELECT claimed, reason FROM voice.fn_claim_dispatch_for_provider_submission(repeat('y',63) || '2', :orga, 'attacker', 30);
RESET ROLE;

\echo ==== REGRESSION: same-key/same-payload replay, different-payload mismatch, cross-tenant denial ====
SET ROLE app_api;
SELECT outcome FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544003', :agentva, :tpna, 'lead-y3', repeat('y',63) || '3');
SELECT outcome FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544003', :agentva, :tpna, 'lead-y3', repeat('y',63) || '3');
SELECT outcome FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876599999', :agentva, :tpna, 'lead-y3', repeat('y',63) || '3');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orgb, '+911234599999', '+919876544003', :agentva, :tpna, 'lead-y3', repeat('y',63) || '3');
RESET ROLE;

\echo ==== REGRESSION: concurrent claim race (same key, two connections) still gives exactly one winner ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544004', :agentva, :tpna, 'lead-y4', repeat('y',63) || '4');
RESET ROLE;

\echo ==== REGRESSION: provider timeout -> AMBIGUOUS via synchronous fn_record_dispatch_ambiguous still works unchanged ====
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('y',63) || '4', :orga, 'worker-y4', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('y',63) || '4', :orga, 'worker-y4');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('y',63) || '4', :orga, 'worker-y4', 'connection reset');
RESET ROLE;
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('y',63) || '4';

\echo REGRESSION_DONE
