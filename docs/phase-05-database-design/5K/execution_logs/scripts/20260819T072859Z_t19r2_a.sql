SELECT pg_sleep(0.5);
SELECT analytics.fn_claim_projection_slot('proj_test', 'b0000000-0000-0000-0000-000000000001', now()) AS conn_a_result;
