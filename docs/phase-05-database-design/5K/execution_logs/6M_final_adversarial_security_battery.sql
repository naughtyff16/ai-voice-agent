-- Phase 6M PG18 validation: final consolidated adversarial security battery (27 tests).
-- Run against phase6m-pg18-incr at alembic head (106_5H3), post fixture insertion + upgrade.
-- Fixture IDs: users 11111111.../22222222..., org 33333333..., billing_account 44444444...,
-- invoice 55555555..., payment_attempt 66666666... (1000.0000 INR, SUCCEEDED),
-- pre-existing refund 77777777... (200.0000 INR, SUCCEEDED) -> remaining refundable balance = 800.0000
-- before this script runs any new reservations.
-- Confirmed function signatures used throughout (see execution_logs history for discovery):
--   organization.fn_platform_suspend_organization(p_organization_id uuid, p_admin_user_id uuid, p_reason text)
--   organization.fn_platform_reactivate_organization(p_organization_id uuid, p_admin_user_id uuid, p_reason text)
--   organization.fn_break_glass_grant(p_organization_id uuid, p_admin_user_id uuid, p_justification text, p_ttl_seconds integer, p_session_id text, p_purposes text[])
--   organization.fn_break_glass_check(p_grant_id uuid, p_admin_user_id uuid, p_organization_id uuid, p_session_id text, p_required_purpose text)
--   billing.fn_platform_set_quota_override(p_organization_id uuid, p_admin_user_id uuid, p_metric text, p_soft_limit numeric, p_hard_limit numeric, p_reason text, p_expires_at timestamptz DEFAULT NULL, p_unit_label text DEFAULT NULL)
--   billing.fn_platform_reserve_refund(p_organization_id uuid, p_admin_user_id uuid, p_payment_attempt_id uuid, p_amount numeric, p_currency character, p_reason text)
--   billing.fn_platform_settle_refund(p_refund_id uuid, p_admin_user_id uuid, p_provider_refund_id text)
--   billing.fn_platform_fail_refund(p_refund_id uuid, p_admin_user_id uuid, p_failure_reason text)

\set org_id '''33333333-3333-3333-3333-333333333333'''
\set admin_id '''22222222-2222-2222-2222-222222222222'''
\set pay_id '''66666666-6666-6666-6666-666666666666'''

-- === TESTS 1-6: app_platform_admin role cannot bypass functions via raw DML (must all FAIL: permission denied) ===
\echo '=== TEST 1: app_platform_admin cannot raw-INSERT into organizations (must FAIL) ==='
SET ROLE app_platform_admin;
INSERT INTO organization.organizations (id, name, slug, owner_user_id, country_code, currency)
VALUES (gen_random_uuid(), 'x', 'raw-insert-test', :admin_id, 'IN', 'INR');
RESET ROLE;

\echo '=== TEST 2: app_platform_admin cannot raw-UPDATE organizations.status (must FAIL) ==='
SET ROLE app_platform_admin;
UPDATE organization.organizations SET status = 'SUSPENDED' WHERE id = :org_id;
RESET ROLE;

\echo '=== TEST 3: app_platform_admin cannot raw-DELETE organizations (must FAIL) ==='
SET ROLE app_platform_admin;
DELETE FROM organization.organizations WHERE id = :org_id;
RESET ROLE;

\echo '=== TEST 4: app_platform_admin cannot raw-INSERT billing.refunds (must FAIL) ==='
SET ROLE app_platform_admin;
INSERT INTO billing.refunds (id, organization_id, payment_attempt_id, payment_provider, provider_refund_id, amount_amount, amount_currency, reason)
VALUES (gen_random_uuid(), :org_id, :pay_id, 'RAZORPAY', 'raw-insert-test', 1.00, 'INR', 'raw insert test');
RESET ROLE;

\echo '=== TEST 5: app_platform_admin cannot raw-UPDATE billing.payment_attempts (must FAIL) ==='
SET ROLE app_platform_admin;
UPDATE billing.payment_attempts SET status = 'FAILED' WHERE id = :pay_id;
RESET ROLE;

\echo '=== TEST 6: app_platform_admin cannot raw-INSERT billing.quota_configs (must FAIL) ==='
SET ROLE app_platform_admin;
INSERT INTO billing.quota_configs (id, organization_id, metric, unit_label) VALUES (gen_random_uuid(), :org_id, 'CALL_MINUTES', 'MINUTES');
RESET ROLE;

-- === TESTS 7-12: suspend/reactivate state machine ===
\echo '=== TEST 7: fn_platform_suspend_organization REJECTS caller without is_platform_admin GUC (must FAIL) ==='
SELECT organization.fn_platform_suspend_organization(:org_id, :admin_id, 'test 7 no guc');

\echo '=== TEST 8: fn_platform_suspend_organization SUCCEEDS with is_platform_admin GUC true ==='
SET app.is_platform_admin = 'true';
SELECT organization.fn_platform_suspend_organization(:org_id, :admin_id, 'test 8 suspend');
SELECT id, status FROM organization.organizations WHERE id = :org_id;

\echo '=== TEST 9: suspend is idempotent (already SUSPENDED -> no-op, no error) ==='
SELECT organization.fn_platform_suspend_organization(:org_id, :admin_id, 'test 9 suspend again');
SELECT id, status FROM organization.organizations WHERE id = :org_id;

\echo '=== TEST 10: reactivate succeeds from SUSPENDED ==='
SELECT organization.fn_platform_reactivate_organization(:org_id, :admin_id, 'test 10 reactivate');
SELECT id, status FROM organization.organizations WHERE id = :org_id;

\echo '=== TEST 11: suspend then cancel then reactivate must be REJECTED (terminal state) ==='
UPDATE organization.organizations SET status = 'CANCELLED' WHERE id = :org_id;
SELECT organization.fn_platform_reactivate_organization(:org_id, :admin_id, 'test 11 reactivate cancelled');

\echo '=== TEST 12: restore org to ACTIVE for subsequent tests (direct fixture repair, superuser) ==='
UPDATE organization.organizations SET status = 'ACTIVE' WHERE id = :org_id;

-- === TESTS 13R-14R: purpose-scoped break-glass check on the pre-existing fixture grant (purposes={SUPPORT_GENERAL}) ===
\echo '=== TEST 13R: fixture grant (purposes={SUPPORT_GENERAL}) DENIED for SENSITIVE_MEDIA_ACCESS (must return FALSE) ==='
SELECT organization.fn_break_glass_check('99999999-9999-9999-9999-999999999999', :admin_id, :org_id, 'fixture-session-001', 'SENSITIVE_MEDIA_ACCESS') AS should_be_false;

\echo '=== TEST 14R: fixture grant PASSES for its own purpose SUPPORT_GENERAL (must return TRUE) ==='
SELECT organization.fn_break_glass_check('99999999-9999-9999-9999-999999999999', :admin_id, :org_id, 'fixture-session-001', 'SUPPORT_GENERAL') AS should_be_true;

-- === TESTS 15R-17B: forbidden purpose values rejected at grant issuance ===
\echo '=== TEST 15R: wildcard purpose "*" rejected at grant issuance (must FAIL) ==='
SELECT organization.fn_break_glass_grant(:org_id, :admin_id, 'wildcard purpose test', 3600, 'sess-15r', ARRAY['*']);

\echo '=== TEST 16R: wildcard purpose "ALL_ACCESS" rejected (must FAIL) ==='
SELECT organization.fn_break_glass_grant(:org_id, :admin_id, 'all_access purpose test', 3600, 'sess-16r', ARRAY['ALL_ACCESS']);

\echo '=== TEST 17R: purpose "SUPER_ADMIN" rejected (must FAIL) ==='
SELECT organization.fn_break_glass_grant(:org_id, :admin_id, 'super_admin purpose test', 3600, 'sess-17r', ARRAY['SUPER_ADMIN']);

\echo '=== TEST 17B: mixed array with one wildcard among valid purposes still rejected (must FAIL) ==='
SELECT organization.fn_break_glass_grant(:org_id, :admin_id, 'mixed wildcard purpose test', 3600, 'sess-17b', ARRAY['SUPPORT_GENERAL','ALL']);

-- === TESTS 18R-18C: legitimate sensitive-purpose grant, scoped correctly ===
\echo '=== TEST 18R: legit grant with SENSITIVE_MEDIA_ACCESS purpose succeeds, and check with that purpose passes ==='
SELECT organization.fn_break_glass_grant(:org_id, :admin_id, 'legit sensitive media access grant', 3600, 'sess-18r', ARRAY['SENSITIVE_MEDIA_ACCESS']) AS new_grant_id \gset
SELECT organization.fn_break_glass_check(:'new_grant_id', :admin_id, :org_id, 'sess-18r', 'SENSITIVE_MEDIA_ACCESS') AS should_be_true;

\echo '=== TEST 18C: that same grant is DENIED for a DIFFERENT purpose it was not issued with (must return FALSE) ==='
SELECT organization.fn_break_glass_check(:'new_grant_id', :admin_id, :org_id, 'sess-18r', 'BILLING_SUPPORT') AS should_be_false;

\echo '=== TEST 19R: purposes column is immutable after creation (UPDATE attempt must FAIL) ==='
UPDATE organization.break_glass_grants SET purposes = ARRAY['SUPER_ADMIN'] WHERE id = :'new_grant_id';

\echo '=== TEST 20R: fn_break_glass_check REJECTS entirely when caller lacks is_platform_admin GUC (must return FALSE, not error) ==='
RESET app.is_platform_admin;
SELECT organization.fn_break_glass_check(:'new_grant_id', :admin_id, :org_id, 'sess-18r', 'SENSITIVE_MEDIA_ACCESS') AS should_be_false_no_admin_ctx;
SET app.is_platform_admin = 'true';

-- === TEST 21R (== original test 20): quota override, out-of-allow-list metric REJECTED ===
\echo '=== TEST 21R: quota override with an out-of-allow-list metric REJECTED ==='
SELECT billing.fn_platform_set_quota_override(:org_id, :admin_id, 'NOT_A_REAL_METRIC', 100.00, 200.00, 'invalid metric test');

-- === TESTS 22R-23R (== original test 21, corrected): valid metric succeeds + idempotent upsert, unit_label auto-derived ===
\echo '=== TEST 22R: quota override with a valid, never-before-configured metric SUCCEEDS (unit_label auto-derived) ==='
SELECT billing.fn_platform_set_quota_override(:org_id, :admin_id, 'STORAGE_GB', 100.00, 200.00, 'valid metric test #22');
SELECT metric, soft_limit, hard_limit, unit_label FROM billing.quota_configs WHERE organization_id = :org_id AND metric = 'STORAGE_GB';

\echo '=== TEST 23R: repeat call on same metric is an idempotent upsert (updates limits, no duplicate row) ==='
SELECT billing.fn_platform_set_quota_override(:org_id, :admin_id, 'STORAGE_GB', 150.00, 250.00, 'valid metric test #23 (upsert)');
SELECT count(*) AS should_be_1_row, metric, soft_limit, hard_limit, unit_label FROM billing.quota_configs WHERE organization_id = :org_id AND metric = 'STORAGE_GB' GROUP BY metric, soft_limit, hard_limit, unit_label;

-- === TESTS 22-26 (original refund state machine, renumbered 24-... to avoid clash but kept as-designed) ===
-- Remaining refundable balance at this point: 1000.0000 - 200.0000 (fixture) = 800.0000
\echo '=== TEST 24 (orig 22): refund reserve REJECTED when amount would exceed remaining refundable balance ==='
SELECT billing.fn_platform_reserve_refund(:org_id, :admin_id, :pay_id, 900.00, 'INR', 'exceeds balance test');

\echo '=== TEST 25 (orig 23): refund reserve SUCCEEDS within remaining balance, then settle succeeds ==='
SELECT billing.fn_platform_reserve_refund(:org_id, :admin_id, :pay_id, 100.00, 'INR', 'reserve then settle test') AS settle_test_refund_id \gset
SELECT billing.fn_platform_settle_refund(:'settle_test_refund_id', :admin_id, 'prov_settle_test25');
SELECT status, provider_refund_id FROM billing.refunds WHERE id = :'settle_test_refund_id';

\echo '=== TEST 26 (orig 24): settle is idempotent (calling again on already-SUCCEEDED must no-op, not error) ==='
SELECT billing.fn_platform_settle_refund(:'settle_test_refund_id', :admin_id, 'prov_settle_test25');

\echo '=== TEST 27P (orig 25): fail on an already-SUCCEEDED refund must be REJECTED (terminal state) ==='
SELECT billing.fn_platform_fail_refund(:'settle_test_refund_id', :admin_id, 'attempt to fail a settled refund');

\echo '=== TEST 28 (orig 26): reserve+fail path -- reserve then fail, fail is idempotent, then settle-after-fail REJECTED ==='
SELECT billing.fn_platform_reserve_refund(:org_id, :admin_id, :pay_id, 50.00, 'INR', 'reserve then fail test') AS fail_test_refund_id \gset
SELECT billing.fn_platform_fail_refund(:'fail_test_refund_id', :admin_id, 'test 28 fail');
SELECT billing.fn_platform_fail_refund(:'fail_test_refund_id', :admin_id, 'test 28 fail again (idempotent)');
SELECT billing.fn_platform_settle_refund(:'fail_test_refund_id', :admin_id, 'prov_should_not_settle');

\echo '=== ALL SEQUENTIAL TESTS ISSUED (see companion race_a.sql/race_b.sql output appended below for TEST 27R true-concurrency race) ==='
