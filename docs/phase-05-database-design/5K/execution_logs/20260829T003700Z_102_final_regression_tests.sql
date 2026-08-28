\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set orgb '''00000000-0000-0000-0000-0000000000b1'''
\set agentva '''00000000-0000-0000-0000-0000000000a3'''
\set tpna '''00000000-0000-0000-0000-0000000000a4'''

\echo ==== REGRESSION: expired CLAIMED before SUBMITTING -> safe reclaim ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876555001', :agentva, :tpna, 'lead-w1', repeat('w',63) || '1');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('w',63) || '1', :orga, 'worker-crash-A', 5);
RESET ROLE;
SELECT pg_sleep(6);
SET ROLE app_worker;
SELECT claimed, reason FROM voice.fn_claim_dispatch_for_provider_submission(repeat('w',63) || '1', :orga, 'worker-recover-A', 30);
RESET ROLE;

\echo ==== REGRESSION: SUBMITTING hard-stop still holds ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876555002', :agentva, :tpna, 'lead-w2', repeat('w',63) || '2');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('w',63) || '2', :orga, 'worker-crash-B', 5);
SELECT * FROM voice.fn_begin_provider_submission(repeat('w',63) || '2', :orga, 'worker-crash-B');
RESET ROLE;
SELECT pg_sleep(6);
SET ROLE app_worker;
SELECT claimed, reason FROM voice.fn_claim_dispatch_for_provider_submission(repeat('w',63) || '2', :orga, 'attacker', 30);
RESET ROLE;

\echo ==== REGRESSION: AMBIGUOUS hard-stop still holds ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876555003', :agentva, :tpna, 'lead-w3', repeat('w',63) || '3');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('w',63) || '3', :orga, 'worker-w3', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('w',63) || '3', :orga, 'worker-w3');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('w',63) || '3', :orga, 'worker-w3', 'connection reset');
SELECT claimed, reason FROM voice.fn_claim_dispatch_for_provider_submission(repeat('w',63) || '3', :orga, 'attacker2', 30);
RESET ROLE;

\echo ==== REGRESSION: same-key/same-payload replay, different-payload mismatch, cross-tenant denial ====
SET ROLE app_api;
SELECT outcome FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876555004', :agentva, :tpna, 'lead-w4', repeat('w',63) || '4');
SELECT outcome FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876555004', :agentva, :tpna, 'lead-w4', repeat('w',63) || '4');
SELECT outcome FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876599999', :agentva, :tpna, 'lead-w4', repeat('w',63) || '4');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orgb, '+911234599999', '+919876555004', :agentva, :tpna, 'lead-w4', repeat('w',63) || '4');
RESET ROLE;

\echo ==== REGRESSION: concurrent claim race still gives exactly one winner ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876555005', :agentva, :tpna, 'lead-w5', repeat('w',63) || '5');
RESET ROLE;

\echo REGRESSION_DONE
