-- Phase 6M / §25 incremental validation leg — post-upgrade fixture survival check
-- Run against phase6m-pg18-incr AFTER `alembic upgrade head` (104_5B3 -> 105_5B4 -> 106_5H3 -> 107_5B5).
-- Confirms every pre-105 fixture row is untouched, and that new 105+ columns (e.g. break_glass_grants.purposes)
-- are present with sane defaults on the pre-existing row.

SELECT 'users' AS tbl, count(*) FROM identity.users WHERE id IN
  ('f0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000002')
UNION ALL
SELECT 'organizations', count(*) FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a1'
UNION ALL
SELECT 'billing_accounts', count(*) FROM billing.billing_accounts WHERE id = 'f0000000-0000-4000-8000-0000000000b1'
UNION ALL
SELECT 'invoices', count(*) FROM billing.invoices WHERE id = 'f0000000-0000-4000-8000-0000000000c1'
UNION ALL
SELECT 'payment_attempts', count(*) FROM billing.payment_attempts WHERE id = 'f0000000-0000-4000-8000-0000000000d1'
UNION ALL
SELECT 'refunds', count(*) FROM billing.refunds WHERE id = 'f0000000-0000-4000-8000-0000000000e1'
UNION ALL
SELECT 'quota_configs', count(*) FROM billing.quota_configs WHERE id = 'f0000000-0000-4000-8000-0000000000f1'
UNION ALL
SELECT 'break_glass_grants', count(*) FROM organization.break_glass_grants WHERE id = 'f0000000-0000-4000-8000-0000000000a9';

-- Value-level spot checks (not just counts)
SELECT id, status, total_due_amount, amount_paid_amount FROM billing.invoices
  WHERE id = 'f0000000-0000-4000-8000-0000000000c1';

SELECT id, status, amount_amount, provider_refund_id FROM billing.refunds
  WHERE id = 'f0000000-0000-4000-8000-0000000000e1';

SELECT id, status, justification, purposes FROM organization.break_glass_grants
  WHERE id = 'f0000000-0000-4000-8000-0000000000a9';

SELECT id, status FROM organization.organizations
  WHERE id = 'f0000000-0000-4000-8000-0000000000a1';
