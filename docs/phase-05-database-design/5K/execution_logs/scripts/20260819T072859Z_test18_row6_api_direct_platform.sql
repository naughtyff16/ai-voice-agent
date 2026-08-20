SELECT session_user, current_user;
SELECT audit.fn_insert_audit_event(
  NULL, 'USER', NULL, 'x',
  'system.maintenance', 'system', NULL, 'SUCCESS', NULL, NULL, NULL, NULL, NULL, NULL, '{}'::jsonb, true
) AS app_api_platform_audit_should_be_denied;
