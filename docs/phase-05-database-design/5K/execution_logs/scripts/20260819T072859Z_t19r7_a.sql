SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';
SET ROLE app_api;
SELECT pg_sleep(0.5);
SELECT workflow.fn_start_workflow_execution(
  '00000000-0000-0000-0000-00000000aaaa'::uuid,
  '00000000-0000-0000-0000-00000000e1aa'::uuid,
  '77777777-7777-7777-7777-777777777777'::uuid
) AS conn_a_new_execution_id;
RESET ROLE;
