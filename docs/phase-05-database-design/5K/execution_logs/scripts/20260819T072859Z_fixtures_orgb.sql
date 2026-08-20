BEGIN;
INSERT INTO workflow.workflow_definitions (id, organization_id, name, status, created_by)
VALUES ('00000000-0000-0000-0000-00000000d1bb', '00000000-0000-0000-0000-00000000bbbb', 'Org B Workflow', 'PUBLISHED', '00000000-0000-0000-0000-0000000000b1');

INSERT INTO workflow.workflow_versions (id, organization_id, workflow_definition_id, version_number, graph_json, published_by, published_at)
VALUES ('00000000-0000-0000-0000-00000000e1bb', '00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-00000000d1bb', 1, '{}', '00000000-0000-0000-0000-0000000000b1', now());
COMMIT;
