SELECT session_user, current_user;
SELECT audit.fn_insert_audit_event(
  NULL, 'WORKER', NULL, 'Background Worker',
  'system.maintenance', 'system', NULL, 'SUCCESS', NULL, NULL, NULL, NULL, NULL, NULL, '{}'::jsonb, true
) AS app_worker_platform_audit_result;
