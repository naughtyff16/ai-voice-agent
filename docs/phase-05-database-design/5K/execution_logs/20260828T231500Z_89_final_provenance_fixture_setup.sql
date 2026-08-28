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

\echo FIXTURES_DONE orga=:orga_id orgb=:orgb_id agentva=:agentva_id tpna=:tpna_id
