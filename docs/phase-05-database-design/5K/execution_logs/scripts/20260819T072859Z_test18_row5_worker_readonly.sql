-- app_worker inserts a platform-level audit event (org_id NULL, is_platform_event=true) (expected: allowed)
SET ROLE app_worker;
SELECT audit.fn_insert_audit_event(
  NULL, 'WORKER', NULL, 'Background Worker',
  'system.maintenance', 'system', NULL, 'SUCCESS', NULL, NULL, NULL, NULL, NULL, NULL, '{}'::jsonb, true
) AS app_worker_platform_audit_result;
RESET ROLE;

-- app_readonly attempts direct INSERT into audit.audit_events (expected: denied, SELECT only)
SET ROLE app_readonly;
INSERT INTO audit.audit_events (organization_id, actor_type, action_kind, outcome) VALUES ('00000000-0000-0000-0000-00000000aaaa', 'USER', 'test.readonly', 'SUCCESS');
RESET ROLE;

-- app_readonly attempts to call the SECURITY DEFINER function directly (expected: denied, no EXECUTE grant unless present)
SET ROLE app_readonly;
SELECT audit.fn_insert_audit_event(
  '00000000-0000-0000-0000-00000000aaaa'::uuid, 'USER', NULL, 'x', 'x', 'x', NULL, 'SUCCESS', NULL, NULL, NULL, NULL, NULL, NULL, '{}'::jsonb, false
);
RESET ROLE;
