-- §18 row 9: app_api calls fn_start_workflow_execution twice for the same session while ACTIVE -> expect Exception on 2nd call
SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';
\echo '-- first call (expect success, new execution id) --'
SELECT workflow.fn_start_workflow_execution(
  '00000000-0000-0000-0000-00000000aaaa'::uuid,
  '00000000-0000-0000-0000-00000000e1aa'::uuid,
  '11111111-1111-1111-1111-111111111111'::uuid
) AS execution_id;
\echo '-- second call, same session_ref, still ACTIVE (expect Exception) --'
SELECT workflow.fn_start_workflow_execution(
  '00000000-0000-0000-0000-00000000aaaa'::uuid,
  '00000000-0000-0000-0000-00000000e1aa'::uuid,
  '11111111-1111-1111-1111-111111111111'::uuid
) AS execution_id;
