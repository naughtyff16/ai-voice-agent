-- Session A of the TEST 27R true-concurrency double-refund race.
-- Remaining refundable balance before this test: 700.0000 INR.
-- Two sessions each reserve 400.0000 INR simultaneously (800 > 700 remaining);
-- exactly one must succeed under fn_platform_reserve_refund's internal
-- SELECT ... FOR UPDATE lock on the payment_attempts row.
SET app.is_platform_admin = 'true';
SELECT billing.fn_platform_reserve_refund(
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222',
  '66666666-6666-6666-6666-666666666666',
  400.00, 'INR', 'TEST 27R session A concurrent reserve'
) AS session_a_result;
