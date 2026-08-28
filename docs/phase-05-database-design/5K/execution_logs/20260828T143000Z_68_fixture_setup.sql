-- Fixtures: two orgs, a campaign, a contact, an agent+version, a tenant phone number.
\set ON_ERROR_STOP on

INSERT INTO identity.users (id, email, email_normalized, display_name, status)
VALUES ('00000000-0000-0000-0000-0000000000aa', 'ownera@example.com', 'ownera@example.com', 'Owner A', 'ACTIVE')
RETURNING id \gset usera_

INSERT INTO identity.users (id, email, email_normalized, display_name, status)
VALUES ('00000000-0000-0000-0000-0000000000bb', 'ownerb@example.com', 'ownerb@example.com', 'Owner B', 'ACTIVE')
RETURNING id \gset userb_

INSERT INTO organization.organizations (id, name, slug, owner_user_id, country_code, currency)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'Org A', 'org-a-pg16', :'usera_id', 'IN', 'INR')
RETURNING id \gset orga_

INSERT INTO organization.organizations (id, name, slug, owner_user_id, country_code, currency)
VALUES ('00000000-0000-0000-0000-0000000000b1', 'Org B', 'org-b-pg16', :'userb_id', 'IN', 'INR')
RETURNING id \gset orgb_

INSERT INTO voice.agents (id, organization_id, name, status, created_by)
VALUES ('00000000-0000-0000-0000-0000000000a2', :'orga_id', 'Agent A', 'PUBLISHED', :'usera_id')
RETURNING id \gset agenta_

INSERT INTO voice.agent_versions (id, organization_id, agent_id, version_number, snapshot_json, language_policy, published_by, published_at)
VALUES ('00000000-0000-0000-0000-0000000000a3', :'orga_id', :'agenta_id', 1, '{}'::jsonb, '{}'::jsonb, :'usera_id', NOW())
RETURNING id \gset agentva_

INSERT INTO voice.tenant_phone_numbers (id, organization_id, phone_e164, phone_country, provider_id)
VALUES ('00000000-0000-0000-0000-0000000000a4', :'orga_id', '+911234500001', 'IN', 'exotel')
RETURNING id \gset tpna_

INSERT INTO campaign.campaigns (id, organization_id, name, status, agent_id, agent_version_id, phone_number_id, created_by)
VALUES ('00000000-0000-0000-0000-0000000000a5', :'orga_id', 'Campaign A', 'RUNNING', :'agenta_id', :'agentva_id', :'tpna_id', :'usera_id')
RETURNING id \gset campa_

INSERT INTO campaign.campaigns (id, organization_id, name, status, agent_id, agent_version_id, phone_number_id, created_by)
VALUES ('00000000-0000-0000-0000-0000000000a6', :'orga_id', 'Campaign A2', 'RUNNING', :'agenta_id', :'agentva_id', :'tpna_id', :'usera_id')
RETURNING id \gset campa2_

INSERT INTO organization.organizations (id, name, slug, owner_user_id, country_code, currency)
VALUES ('00000000-0000-0000-0000-0000000000c1', 'Org C (unused placeholder)', 'org-c-pg16', :'userb_id', 'IN', 'INR')
ON CONFLICT DO NOTHING;

INSERT INTO crm.contacts (id, organization_id, full_name, phone_e164, phone_country, source)
VALUES ('00000000-0000-0000-0000-0000000000a7', :'orga_id', 'Contact One', '+911234500002', 'IN', 'MANUAL')
RETURNING id \gset conta_

INSERT INTO crm.contacts (id, organization_id, full_name, phone_e164, phone_country, source)
VALUES ('00000000-0000-0000-0000-0000000000a8', :'orga_id', 'Contact Two', '+911234500003', 'IN', 'MANUAL')
RETURNING id \gset contb_

INSERT INTO campaign.campaigns (id, organization_id, name, status, agent_id, agent_version_id, phone_number_id, created_by)
VALUES ('00000000-0000-0000-0000-0000000000b5', :'orgb_id', 'Campaign B', 'RUNNING', :'agenta_id', :'agentva_id', :'tpna_id', :'userb_id')
RETURNING id \gset campb_

\echo FIXTURES_DONE orga=:orga_id orgb=:orgb_id campa=:campa_id campa2=:campa2_id campb=:campb_id conta=:conta_id contb=:contb_id agentva=:agentva_id tpna=:tpna_id
