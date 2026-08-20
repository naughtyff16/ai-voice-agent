SELECT pg_sleep(0.5);
SELECT * FROM webhooks.fn_claim_delivery('worker-a', 10) AS conn_a_claimed;
