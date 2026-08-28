\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set campa '''00000000-0000-0000-0000-0000000000a5'''
\set campa2 '''00000000-0000-0000-0000-0000000000a6'''
\set conta '''00000000-0000-0000-0000-0000000000a7'''
\set contb '''00000000-0000-0000-0000-0000000000a8'''

SELECT id, imported_at FROM campaign.campaign_contacts WHERE campaign_id = :campa AND contact_id = :conta \gset cca_
SELECT id, imported_at FROM campaign.campaign_contacts WHERE campaign_id = :campa AND contact_id = :contb \gset ccb_

\echo ==== TEST: campaign.fn_reserve_dispatch happy path for conta on campa ====
SET ROLE app_worker;
SELECT * FROM campaign.fn_reserve_dispatch(:orga, :campa, :'cca_id', :'cca_imported_at', 1, repeat('7',64), '+911234500002');
RESET ROLE;

\echo ==== TEST: duplicate dispatch reservation (same idempotency_key retried) must be refused (DUPLICATE_ATTEMPT) ====
SET ROLE app_worker;
SELECT * FROM campaign.fn_reserve_dispatch(:orga, :campa, :'cca_id', :'cca_imported_at', 1, repeat('7',64), '+911234500002');
RESET ROLE;

\echo ==== TEST: cross-campaign mismatch regression -- contb belongs to campa, but caller claims campa2 -- must be CONTACT_NOT_FOUND ====
SET ROLE app_worker;
SELECT * FROM campaign.fn_reserve_dispatch(:orga, :campa2, :'ccb_id', :'ccb_imported_at', 1, repeat('8',64), '+911234500003');
RESET ROLE;

\echo ==== TEST: correct campaign (campa) for contb -- should succeed ====
SET ROLE app_worker;
SELECT * FROM campaign.fn_reserve_dispatch(:orga, :campa, :'ccb_id', :'ccb_imported_at', 1, repeat('10',64), '+911234500003');
RESET ROLE;

\echo RESERVE_DISPATCH_TESTS_DONE
\set ON_ERROR_STOP off
\set orga '''00000000-0000-0000-0000-0000000000a1'''
\set campa '''00000000-0000-0000-0000-0000000000a5'''
\set contb '''00000000-0000-0000-0000-0000000000a8'''
\set usera '''00000000-0000-0000-0000-0000000000aa'''
\set agentva '''00000000-0000-0000-0000-0000000000a3'''
\set agenta '''00000000-0000-0000-0000-0000000000a2'''
\set tpna '''00000000-0000-0000-0000-0000000000a4'''

INSERT INTO campaign.campaigns (id, organization_id, name, status, agent_id, agent_version_id, phone_number_id, created_by)
VALUES ('00000000-0000-0000-0000-0000000000a9', :orga, 'Campaign A3 (running, for mismatch test)', 'RUNNING', :agenta, :agentva, :tpna, :usera)
RETURNING id \gset campa3_

SELECT id, imported_at FROM campaign.campaign_contacts WHERE campaign_id = :campa AND contact_id = :contb \gset ccb_

\echo ==== TEST: cross-campaign mismatch -- contb genuinely belongs to campa, caller wrongly claims campa3 (RUNNING) -- must be CONTACT_NOT_FOUND ====
SET ROLE app_worker;
SELECT * FROM campaign.fn_reserve_dispatch(:orga, :'campa3_id', :'ccb_id', :'ccb_imported_at', 1, repeat('8',64), '+911234500003');
RESET ROLE;

\echo ==== TEST: correct campaign (campa) for contb -- should succeed ====
SET ROLE app_worker;
SELECT * FROM campaign.fn_reserve_dispatch(:orga, :campa, :'ccb_id', :'ccb_imported_at', 1, repeat('c',64), '+911234500003');
RESET ROLE;

\echo RESERVE_DISPATCH_FIX_DONE
