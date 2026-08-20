SELECT pg_sleep(0.5);
SELECT analytics.fn_ingest_analytics_event(
  '00000000-0000-0000-0000-00000000aaaa','call.completed','1','dedup-race-key-1',now(),
  'call', gen_uuid_v7(), 'system', NULL, gen_uuid_v7(), NULL, gen_uuid_v7(), NULL, NULL,
  'test','test-model','{}','{}') AS conn_b_result;
