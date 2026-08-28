\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set orgb '''00000000-0000-0000-0000-0000000000b1'''
\set agentva '''00000000-0000-0000-0000-0000000000a3'''
\set tpna '''00000000-0000-0000-0000-0000000000a4'''

\echo ==== CATALOG: current grants on voice.call_dispatch_keys ====
SELECT grantee, string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
FROM information_schema.role_table_grants
WHERE table_schema = 'voice' AND table_name = 'call_dispatch_keys'
GROUP BY grantee ORDER BY grantee;

\echo ==== CATALOG: current grants on campaign.campaign_contact_identities ====
SELECT grantee, string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
FROM information_schema.role_table_grants
WHERE table_schema = 'campaign' AND table_name = 'campaign_contact_identities'
GROUP BY grantee ORDER BY grantee;

-- Fixture dispatch keys for the admin-DML tests below.
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544101', :agentva, :tpna, 'lead-z1', repeat('z',63) || '1');
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544102', :agentva, :tpna, 'lead-z2', repeat('z',63) || '2');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('z',63) || '1', :orga, 'w1', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('z',63) || '1', :orga, 'w1');
SELECT * FROM voice.fn_record_dispatch_confirmed(repeat('z',63) || '1', :orga, 'w1', 'PROVIDER-CONFIRMED-Z1');

SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('z',63) || '2', :orga, 'w2', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('z',63) || '2', :orga, 'w2');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('z',63) || '2', :orga, 'w2', 'timeout');
RESET ROLE;

\echo ==== TEST platform_admin_select_allowed ====
SET ROLE app_platform_admin;
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('z',63) || '1';
RESET ROLE;

\echo ==== TEST platform_admin_insert_denied ====
SET ROLE app_platform_admin;
INSERT INTO voice.call_dispatch_keys (dispatch_idempotency_key, organization_id, call_session_id, started_at, payload_fingerprint, provider_request_ref)
VALUES (repeat('q',64), :orga, gen_random_uuid(), NOW(), repeat('q',64), 'x');
RESET ROLE;

\echo ==== TEST platform_admin_update_denied ====
SET ROLE app_platform_admin;
UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE dispatch_idempotency_key = repeat('z',63) || '2';
RESET ROLE;

\echo ==== TEST platform_admin_delete_denied ====
SET ROLE app_platform_admin;
DELETE FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('z',63) || '2';
RESET ROLE;

\echo ==== TEST platform_admin_provenance_forgery_denied ====
SET ROLE app_platform_admin;
UPDATE voice.call_dispatch_keys SET reconciliation_source = 'PROVIDER_CALLBACK', reconciled_by = 'fake-provider' WHERE dispatch_idempotency_key = repeat('z',63) || '2';
RESET ROLE;

\echo ==== TEST confirmed_direct_reopen_denied ====
SET ROLE app_platform_admin;
UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE dispatch_idempotency_key = repeat('z',63) || '1';
RESET ROLE;
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('z',63) || '1';

\echo ==== TEST campaign_identity_admin_insert_denied ====
SET ROLE app_platform_admin;
INSERT INTO campaign.campaign_contact_identities (campaign_id, contact_id, organization_id, campaign_contact_id, imported_at)
VALUES (gen_random_uuid(), gen_random_uuid(), :orga, gen_random_uuid(), NOW());
RESET ROLE;

\echo ==== TEST operator_function_allowed (AMBIGUOUS -> FAILED with evidence) ====
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('z',63) || '2', :orga, 'FAILED', 'operator-jane', NULL, 'authoritative provider console lookup shows no call was ever created');
RESET ROLE;
SELECT dispatch_state, reconciliation_source, reconciled_by FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('z',63) || '2';

\echo ==== TEST confirmed_operator_reopen_denied ====
SET ROLE app_platform_admin;
SELECT * FROM voice.fn_reconcile_dispatch_by_operator(repeat('z',63) || '1', :orga, 'FAILED', 'operator-jane', NULL, 'attempt to reopen a confirmed call');
RESET ROLE;
SELECT dispatch_state FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('z',63) || '1';

\echo ==== fixture: fresh AMBIGUOUS key for provider reconciler test ====
SET ROLE app_api;
SELECT * FROM voice.fn_initiate_outbound_call_idempotent(:orga, '+911234599999', '+919876544103', :agentva, :tpna, 'lead-z3', repeat('z',63) || '3');
RESET ROLE;
SET ROLE app_worker;
SELECT * FROM voice.fn_claim_dispatch_for_provider_submission(repeat('z',63) || '3', :orga, 'w3', 30);
SELECT * FROM voice.fn_begin_provider_submission(repeat('z',63) || '3', :orga, 'w3');
SELECT * FROM voice.fn_record_dispatch_ambiguous(repeat('z',63) || '3', :orga, 'w3', 'timeout');
RESET ROLE;

\echo ==== TEST provider_reconciler_allowed ====
SET ROLE app_voice_reconciler;
SELECT * FROM voice.fn_reconcile_dispatch_from_provider(repeat('z',63) || '3', :orga, 'CONFIRMED', 'PROVIDER_CALLBACK', 'webhook-handler-z3', 'PROVIDER-CALL-REF-Z3', 'matched via callback');
RESET ROLE;
SELECT dispatch_state, reconciliation_source FROM voice.call_dispatch_keys WHERE dispatch_idempotency_key = repeat('z',63) || '3';

\echo ==== TEST app_api_direct_dml_denied ====
SET ROLE app_api;
INSERT INTO voice.call_dispatch_keys (dispatch_idempotency_key, organization_id, call_session_id, started_at, payload_fingerprint, provider_request_ref)
VALUES (repeat('q',64), :orga, gen_random_uuid(), NOW(), repeat('q',64), 'x');
UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE dispatch_idempotency_key = repeat('z',63) || '1';
RESET ROLE;

\echo ==== TEST app_worker_direct_dml_denied ====
SET ROLE app_worker;
INSERT INTO voice.call_dispatch_keys (dispatch_idempotency_key, organization_id, call_session_id, started_at, payload_fingerprint, provider_request_ref)
VALUES (repeat('q',64), :orga, gen_random_uuid(), NOW(), repeat('q',64), 'x');
UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE dispatch_idempotency_key = repeat('z',63) || '1';
RESET ROLE;

\echo ==== TEST voice_reconciler_direct_dml_denied ====
SET ROLE app_voice_reconciler;
INSERT INTO voice.call_dispatch_keys (dispatch_idempotency_key, organization_id, call_session_id, started_at, payload_fingerprint, provider_request_ref)
VALUES (repeat('q',64), :orga, gen_random_uuid(), NOW(), repeat('q',64), 'x');
UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE dispatch_idempotency_key = repeat('z',63) || '1';
RESET ROLE;

\echo ==== Privilege matrix, final ====
SELECT r.rolname,
  has_table_privilege(r.rolname, 'voice.call_dispatch_keys', 'SELECT') AS sel,
  has_table_privilege(r.rolname, 'voice.call_dispatch_keys', 'INSERT') AS ins,
  has_table_privilege(r.rolname, 'voice.call_dispatch_keys', 'UPDATE') AS upd,
  has_table_privilege(r.rolname, 'voice.call_dispatch_keys', 'DELETE') AS del
FROM pg_roles r WHERE r.rolname LIKE 'app_%' ORDER BY r.rolname;

SELECT r.rolname,
  has_table_privilege(r.rolname, 'campaign.campaign_contact_identities', 'SELECT') AS sel,
  has_table_privilege(r.rolname, 'campaign.campaign_contact_identities', 'INSERT') AS ins,
  has_table_privilege(r.rolname, 'campaign.campaign_contact_identities', 'UPDATE') AS upd,
  has_table_privilege(r.rolname, 'campaign.campaign_contact_identities', 'DELETE') AS del
FROM pg_roles r WHERE r.rolname LIKE 'app_%' ORDER BY r.rolname;

\echo ADMIN_DML_TESTS_DONE
