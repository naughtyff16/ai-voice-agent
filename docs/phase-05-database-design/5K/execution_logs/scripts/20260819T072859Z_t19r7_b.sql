SET app.tenant_id = '00000000-0000-0000-0000-00000000bbbb';
SET ROLE app_api;
SELECT pg_sleep(0.5);
SELECT workflow.fn_start_workflow_execution(
  '00000000-0000-0000-0000-00000000bbbb'::uuid,
  '00000000-0000-0000-0000-00000000e1bb'::uuid,
  '88888888-8888-8888-8888-888888888888'::uuid
) AS conn_b_new_execution_id;
RESET ROLE;
