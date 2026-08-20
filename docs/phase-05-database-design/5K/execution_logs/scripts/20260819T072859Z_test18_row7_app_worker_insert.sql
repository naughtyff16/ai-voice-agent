-- §18 row 7: app_worker direct INSERT into workflow.workflow_executions -> expect Denied
SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';
INSERT INTO workflow.workflow_executions (id, started_at, organization_id, workflow_version_id, session_ref, status)
VALUES (gen_uuid_v7(), now(), '00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-00000000e1aa', gen_uuid_v7(), 'ACTIVE');
