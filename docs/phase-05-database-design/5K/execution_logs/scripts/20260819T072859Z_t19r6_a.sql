SELECT pg_sleep(0.5);
SELECT plugins.fn_upgrade_plugin('00000000-0000-0000-0000-00000000aaaa'::uuid, 'a0000000-0000-0000-0000-000000000006'::uuid, 'a0000000-0000-0000-0000-000000000005'::uuid);
SELECT 'conn_a_done' AS status;
