-- Phase 6M PG18 validation: pre-105 fixture insertion
-- Applied against phase6m-pg18-incr at alembic revision 104_5B3 (before 105_5B4/106_5H3 are applied).
-- Fixture ID scheme (fixed, reused across all 6M validation runs):
--   users:            11111111-1111-1111-1111-111111111111 (owner), 22222222-2222-2222-2222-222222222222 (admin)
--   organization:      33333333-3333-3333-3333-333333333333
--   billing_account:   44444444-4444-4444-4444-444444444444
--   invoice:           55555555-5555-5555-5555-555555555555
--   payment_attempt:   66666666-6666-6666-6666-666666666666 (amount 1000.0000 INR, SUCCEEDED)
--   refund:            77777777-7777-7777-7777-777777777777 (200.0000 INR, SUCCEEDED)
--   quota_config:      88888888-8888-8888-8888-888888888888 (CALL_MINUTES)
--   break_glass_grant: 99999999-9999-9999-9999-999999999999 (purposes column does not exist yet at 104_5B3;
--                       it is added by 106_5H3 as an ALTER TABLE ... ADD COLUMN with a default, so this
--                       pre-existing row will pick up the new column via that migration's DEFAULT/backfill.)

BEGIN;

INSERT INTO identity.users (id, email, email_normalized, display_name, status)
VALUES ('11111111-1111-1111-1111-111111111111', 'owner@fixture.test', 'owner@fixture.test', 'Fixture Owner', 'ACTIVE');

INSERT INTO identity.users (id, email, email_normalized, display_name, status)
VALUES ('22222222-2222-2222-2222-222222222222', 'admin@fixture.test', 'admin@fixture.test', 'Fixture Platform Admin', 'ACTIVE');

INSERT INTO organization.organizations (id, name, slug, owner_user_id, country_code, currency)
VALUES ('33333333-3333-3333-3333-333333333333', 'Fixture Org', 'fixture-org', '11111111-1111-1111-1111-111111111111', 'IN', 'INR');

INSERT INTO billing.billing_accounts (id, organization_id, currency)
VALUES ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'INR');

INSERT INTO billing.invoices (id, organization_id, billing_account_id, currency, subtotal_currency, total_credits_currency, total_tax_currency, total_due_currency, amount_paid_currency)
VALUES ('55555555-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'INR', 'INR', 'INR', 'INR', 'INR', 'INR');

INSERT INTO billing.payment_attempts (id, organization_id, invoice_id, payment_provider, status, amount_amount, amount_currency, completed_at)
VALUES ('66666666-6666-6666-6666-666666666666', '33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555', 'RAZORPAY', 'SUCCEEDED', 1000.0000, 'INR', now());

INSERT INTO billing.refunds (id, organization_id, payment_attempt_id, payment_provider, provider_refund_id, amount_amount, amount_currency, reason, status, completed_at)
VALUES ('77777777-7777-7777-7777-777777777777', '33333333-3333-3333-3333-333333333333', '66666666-6666-6666-6666-666666666666', 'RAZORPAY', 'rfnd_fixture_001', 200.0000, 'INR', 'fixture pre-existing refund', 'SUCCEEDED', now());

INSERT INTO billing.quota_configs (id, organization_id, metric, soft_limit, hard_limit, unit_label)
VALUES ('88888888-8888-8888-8888-888888888888', '33333333-3333-3333-3333-333333333333', 'CALL_MINUTES', 5000.0000, 10000.0000, 'MINUTES');

INSERT INTO organization.break_glass_grants (id, organization_id, admin_user_id, justification, session_id, expires_at)
VALUES ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'Fixture pre-existing break-glass grant for 6M validation', 'fixture-session-001', now() + interval '1 hour');

COMMIT;

SELECT 'users' AS t, count(*) FROM identity.users WHERE id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222')
UNION ALL SELECT 'orgs', count(*) FROM organization.organizations WHERE id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'billing_accounts', count(*) FROM billing.billing_accounts WHERE id = '44444444-4444-4444-4444-444444444444'
UNION ALL SELECT 'invoices', count(*) FROM billing.invoices WHERE id = '55555555-5555-5555-5555-555555555555'
UNION ALL SELECT 'payment_attempts', count(*) FROM billing.payment_attempts WHERE id = '66666666-6666-6666-6666-666666666666'
UNION ALL SELECT 'refunds', count(*) FROM billing.refunds WHERE id = '77777777-7777-7777-7777-777777777777'
UNION ALL SELECT 'quota_configs', count(*) FROM billing.quota_configs WHERE id = '88888888-8888-8888-8888-888888888888'
UNION ALL SELECT 'bgg', count(*) FROM organization.break_glass_grants WHERE id = '99999999-9999-9999-9999-999999999999';
