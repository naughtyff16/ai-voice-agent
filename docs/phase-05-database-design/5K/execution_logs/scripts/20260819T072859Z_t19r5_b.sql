SELECT pg_sleep(0.5);
SELECT * FROM webhooks.fn_claim_delivery('worker-b', 10) AS conn_b_claimed;
