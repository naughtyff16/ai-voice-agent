-- Fixture setup for §18/§19 live security & concurrency tests. Run as postgres (bypasses RLS as superuser).
BEGIN;

INSERT INTO identity.users (id, email, email_normalized, display_name, status)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'ownera@test.local', 'ownera@test.local', 'Owner A', 'ACTIVE'),
       ('00000000-0000-0000-0000-0000000000b1', 'ownerb@test.local', 'ownerb@test.local', 'Owner B', 'ACTIVE');

INSERT INTO organization.organizations (id, name, slug, owner_user_id, country_code, currency)
VALUES ('00000000-0000-0000-0000-00000000aaaa', 'Org A', 'org-a-5k-test', '00000000-0000-0000-0000-0000000000a1', 'IN', 'INR'),
       ('00000000-0000-0000-0000-00000000bbbb', 'Org B', 'org-b-5k-test', '00000000-0000-0000-0000-0000000000b1', 'IN', 'INR');

INSERT INTO workflow.workflow_definitions (id, organization_id, name, status, created_by)
VALUES ('00000000-0000-0000-0000-00000000d1aa', '00000000-0000-0000-0000-00000000aaaa', 'Test WF A', 'PUBLISHED', '00000000-0000-0000-0000-0000000000a1');

INSERT INTO workflow.workflow_versions (id, organization_id, workflow_definition_id, version_number, graph_json, published_by, published_at)
VALUES ('00000000-0000-0000-0000-00000000e1aa', '00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-00000000d1aa', 1, '{}'::jsonb, '00000000-0000-0000-0000-0000000000a1', now());

COMMIT;

\echo '--- fixtures created ---'
SELECT 'org A' , id FROM organization.organizations WHERE id = '00000000-0000-0000-0000-00000000aaaa';
SELECT 'wf version A', id FROM workflow.workflow_versions WHERE id = '00000000-0000-0000-0000-00000000e1aa';
