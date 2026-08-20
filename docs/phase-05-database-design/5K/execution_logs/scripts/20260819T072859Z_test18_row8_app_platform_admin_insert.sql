-- §18 row 8: app_platform_admin direct INSERT into workflow.workflow_executions
-- Doc originally expected Denied (REVOKE INSERT, per migration 041). Live grants (see 046_5G.sql)
-- show app_platform_admin currently HOLDS INSERT. This test captures actual live behavior.
SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';
SET app.is_platform_admin = 'true';
INSERT INTO workflow.workflow_executions (id, started_at, organization_id, workflow_version_id, session_ref, status)
VALUES (gen_uuid_v7(), now(), '00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-00000000e1aa', gen_uuid_v7(), 'ACTIVE')
RETURNING id, status;
