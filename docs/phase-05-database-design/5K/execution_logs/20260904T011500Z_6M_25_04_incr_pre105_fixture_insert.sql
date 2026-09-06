-- Phase 6M / §25 incremental validation leg — pre-105 fixture insert
-- Run against phase6m-pg18-incr AFTER `alembic upgrade 104_5B3` and BEFORE `alembic upgrade head`.
-- Purpose: prove pre-existing tenant data survives the 105/106/107 hardening migrations untouched.
-- Inserted as `postgres` (BYPASSRLS) so RLS forced-policies on tenant tables do not block the fixture load.
BEGIN;

-- 2 users
INSERT INTO identity.users (id, email, email_normalized, display_name, status, created_at, updated_at)
VALUES
  ('f0000000-0000-4000-8000-000000000001', 'owner@fixture.test', 'owner@fixture.test', 'Fixture Owner', 'ACTIVE', now(), now()),
  ('f0000000-0000-4000-8000-000000000002', 'admin@fixture.test', 'admin@fixture.test', 'Fixture Admin', 'ACTIVE', now(), now());

-- 1 organization (Org A, ACTIVE)
INSERT INTO organization.organizations
  (id, name, slug, status, owner_user_id, country_code, currency, created_at, updated_at)
VALUES
  ('f0000000-0000-4000-8000-0000000000a1', 'Fixture Org A', 'fixture-org-a', 'ACTIVE',
   'f0000000-0000-4000-8000-000000000001', 'IN', 'INR', now(), now());

-- 1 billing_account
INSERT INTO billing.billing_accounts
  (id, organization_id, billing_status, currency, created_at, updated_at)
VALUES
  ('f0000000-0000-4000-8000-0000000000b1', 'f0000000-0000-4000-8000-0000000000a1', 'ACTIVE', 'INR', now(), now());

-- 1 invoice (PAID)
INSERT INTO billing.invoices
  (id, organization_id, billing_account_id, invoice_number, invoice_kind, status, currency,
   subtotal_amount, subtotal_currency, total_credits_amount, total_credits_currency,
   total_tax_amount, total_tax_currency, total_due_amount, total_due_currency,
   amount_paid_amount, amount_paid_currency, issue_date, due_date, paid_at, created_at, updated_at)
VALUES
  ('f0000000-0000-4000-8000-0000000000c1', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-0000000000b1', 'INV-FIX-0001', 'TAX_INVOICE', 'PAID', 'INR',
   1000.00, 'INR', 0, 'INR', 180.00, 'INR', 1180.00, 'INR', 1180.00, 'INR',
   current_date, current_date + 7, now(), now(), now());

-- 1 payment_attempt (SUCCEEDED)
INSERT INTO billing.payment_attempts
  (id, organization_id, invoice_id, payment_provider, provider_transaction_id, status,
   amount_amount, amount_currency, initiated_at, completed_at, created_at)
VALUES
  ('f0000000-0000-4000-8000-0000000000d1', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-0000000000c1', 'RAZORPAY', 'pay_fix0001', 'SUCCEEDED',
   1180.00, 'INR', now(), now(), now());

-- 1 refund (PENDING, partial)
INSERT INTO billing.refunds
  (id, organization_id, payment_attempt_id, payment_provider, provider_refund_id,
   amount_amount, amount_currency, reason, status, initiated_at, created_at)
VALUES
  ('f0000000-0000-4000-8000-0000000000e1', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-0000000000d1', 'RAZORPAY', 'rfnd_fix0001',
   500.00, 'INR', 'fixture pre-105 survival test', 'PENDING', now(), now());

-- 1 quota_config
INSERT INTO billing.quota_configs
  (id, organization_id, metric, soft_limit, hard_limit, unit_label, created_at, updated_at)
VALUES
  ('f0000000-0000-4000-8000-0000000000f1', 'f0000000-0000-4000-8000-0000000000a1',
   'MINUTES_PER_MONTH', 1000, 1200, 'minutes', now(), now());

-- 1 break_glass_grant (ACTIVE) -- inserted BEFORE 105_5B4 adds the `purposes` column
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, issued_at, expires_at, status)
VALUES
  ('f0000000-0000-4000-8000-0000000000a9', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000002', 'fixture pre-105 break-glass survival test justification',
   'fixture-session-001', now(), now() + interval '1 hour', 'ACTIVE');

COMMIT;

-- Immediate post-insert sanity read
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
