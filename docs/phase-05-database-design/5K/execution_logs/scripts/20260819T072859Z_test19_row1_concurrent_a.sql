SET app.tenant_id = '00000000-0000-0000-0000-00000000aaaa';
SELECT pg_sleep(0.5);
SELECT clock_timestamp() AS ts, 'conn_A' AS conn, workflow.fn_start_workflow_execution(
  '00000000-0000-0000-0000-00000000aaaa'::uuid,
  '00000000-0000-0000-0000-00000000e1aa'::uuid,
  '33333333-3333-3333-3333-333333333333'::uuid
) AS execution_id;
