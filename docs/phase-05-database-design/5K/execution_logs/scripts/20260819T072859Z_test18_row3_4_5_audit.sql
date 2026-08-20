-- Row: app_api inserts a normal org-scoped audit event via the function (expected: allowed)
SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';
SET ROLE app_api;
SELECT audit.fn_insert_audit_event(
  '00000000-0000-0000-0000-00000000aaaa'::uuid, 'USER', '00000000-0000-0000-0000-0000000000a1'::uuid, 'Test User',
  'test.action', 'workflow_execution', NULL, 'SUCCESS', NULL, NULL, NULL, NULL, NULL, NULL, '{}'::jsonb, false
) AS app_api_audit_insert_result;
RESET ROLE;

-- app_api attempts direct INSERT into audit.audit_events bypassing the function (expected: denied, only SELECT granted)
SET ROLE app_api;
INSERT INTO audit.audit_events (organization_id, actor_type, action_kind, outcome) VALUES ('00000000-0000-0000-0000-00000000aaaa', 'USER', 'test.direct', 'SUCCESS');
RESET ROLE;
