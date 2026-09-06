-- Session B of the TEST 27R true-concurrency double-refund race. See 6M_race_a.sql header.
SET app.is_platform_admin = 'true';
SELECT billing.fn_platform_reserve_refund(
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222',
  '66666666-6666-6666-6666-666666666666',
  400.00, 'INR', 'TEST 27R session B concurrent reserve'
) AS session_b_result;
