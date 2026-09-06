-- Phase 6M live test battery, run as app_platform_admin (session_user =
-- app_platform_admin) with the application GUC set, exactly as the real
-- Platform Admin REST backend would connect. Exercises:
--   * §31 organization lifecycle tests (active<->suspended, idempotency,
--     terminal-state guard, not-found, audit atomicity)
--   * §32 quota override tests (valid override, invalid metric, zero/negative
--     prohibited, overflow (soft>hard), idempotent retry, audit atomicity)
-- Org B (f...a2) is used for lifecycle tests so Org A (f...a1) is left
-- undisturbed for any later reruns of the break-glass/sensitive-media tests.
-- Org C (f...a3) is a pre-seeded CANCELLED terminal-state fixture, inserted
-- directly as postgres (superuser/BYPASSRLS) prior to this script, since no
-- Platform Admin function reaches CANCELLED from ACTIVE.
\set ON_ERROR_STOP off
SET app.is_platform_admin = 'true';

\echo '=== [L0] Pre-state: Org B and Org C status ==='
SELECT id, status FROM organization.organizations
WHERE id IN ('f0000000-0000-4000-8000-0000000000a2','f0000000-0000-4000-8000-0000000000a3');

\echo '=== [L1] active -> suspended: Org B, admin 002, valid reason -> expect ALLOW, status=SUSPENDED ==='
SELECT organization.fn_platform_suspend_organization(
  'f0000000-0000-4000-8000-0000000000a2'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture suspension: routine lifecycle test suspension for Org B.'
);
SELECT id, status FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a2';

\echo '=== [L2] idempotent re-suspend: same call again -> expect no error, status stays SUSPENDED ==='
SELECT organization.fn_platform_suspend_organization(
  'f0000000-0000-4000-8000-0000000000a2'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture suspension: idempotent retry of the same suspension.'
);
SELECT id, status FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a2';

\echo '=== [L3] suspended -> active: Org B, admin 002 -> expect ALLOW, status=ACTIVE ==='
SELECT organization.fn_platform_reactivate_organization(
  'f0000000-0000-4000-8000-0000000000a2'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture reactivation: routine lifecycle test reactivation for Org B.'
);
SELECT id, status FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a2';

\echo '=== [L4] idempotent re-reactivate: same call again while already ACTIVE -> expect no error, status stays ACTIVE ==='
SELECT organization.fn_platform_reactivate_organization(
  'f0000000-0000-4000-8000-0000000000a2'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture reactivation: idempotent retry of the same reactivation.'
);
SELECT id, status FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a2';

\echo '=== [L5] terminal-state guard: attempt to suspend a CANCELLED org (Org C) -> expect exception, no state change ==='
SELECT organization.fn_platform_suspend_organization(
  'f0000000-0000-4000-8000-0000000000a3'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture attempt: try to suspend an already-cancelled terminal org.'
);
SELECT id, status FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a3';

\echo '=== [L6] terminal-state guard: attempt to reactivate a CANCELLED org (Org C) -> expect exception, no state change ==='
SELECT organization.fn_platform_reactivate_organization(
  'f0000000-0000-4000-8000-0000000000a3'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture attempt: try to reactivate an already-cancelled terminal org.'
);
SELECT id, status FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a3';

\echo '=== [L7] wrong/nonexistent org id -> expect not-found style failure, no row created/changed ==='
SELECT organization.fn_platform_suspend_organization(
  'f0000000-0000-4000-8000-000000000000'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Fixture attempt: suspend a nonexistent organization id.'
);

\echo '=== [L8] audit atomicity: confirm ORGANIZATION_SUSPENDED / ORGANIZATION_REACTIVATED rows exist for Org B, and none exist for the failed Org C / nonexistent-org attempts ==='
SELECT action_kind, resource_type, resource_id, resource_snapshot
FROM audit.audit_events
WHERE action_kind IN ('ORGANIZATION_SUSPENDED','ORGANIZATION_REACTIVATED')
  AND resource_id IN ('f0000000-0000-4000-8000-0000000000a2','f0000000-0000-4000-8000-0000000000a3','f0000000-0000-4000-8000-000000000000')
ORDER BY occurred_at;

\echo '=== [Q1] valid quota override: Org A, metric concurrent_calls, soft=50, hard=100 -> expect ALLOW ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'CONCURRENT_CALL_COUNT', 50, 100,
  'Fixture quota override: routine test override.',
  NULL, 'calls'
);
SELECT organization_id, metric, soft_limit, hard_limit, unit_label, override_reason
FROM billing.quota_configs WHERE organization_id = 'f0000000-0000-4000-8000-0000000000a1' AND metric = 'CONCURRENT_CALL_COUNT';

\echo '=== [Q2] idempotent retry: same override applied again -> expect ALLOW, no duplicate row (upsert on uq_qc_org_metric) ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'CONCURRENT_CALL_COUNT', 55, 110,
  'Fixture quota override: idempotent retry with updated limits.',
  NULL, 'calls'
);
SELECT count(*) AS row_count_for_metric FROM billing.quota_configs
WHERE organization_id = 'f0000000-0000-4000-8000-0000000000a1' AND metric = 'CONCURRENT_CALL_COUNT';

\echo '=== [Q3] zero/negative prohibited: soft_limit = -1 -> expect exception (function-level guard) ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'CONCURRENT_CALL_COUNT', -1, 100,
  'Fixture attempt: negative soft_limit.',
  NULL, 'calls'
);

\echo '=== [Q4] overflow: soft_limit > hard_limit -> expect exception (function-level guard) ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'CONCURRENT_CALL_COUNT', 200, 100,
  'Fixture attempt: soft_limit greater than hard_limit.',
  NULL, 'calls'
);

\echo '=== [Q5] server-authoritative org / wrong org id -> expect not-found style failure (post-fix: organization existence guard added in 107_5B5.sql) ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-000000000000'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'CONCURRENT_CALL_COUNT', 10, 20,
  'Fixture attempt: nonexistent organization id (post-fix).',
  NULL, 'calls'
);
SELECT count(*) AS orphan_row_count FROM billing.quota_configs
WHERE organization_id = 'f0000000-0000-4000-8000-000000000000';

\echo '=== [Q7] invalid metric name -> expect exception (not a recognized usage dimension) ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'BOGUS_METRIC', 10, 20,
  'Fixture attempt: unrecognized metric name.',
  NULL, 'count'
);

\echo '=== [Q6] audit atomicity: confirm QUOTA_OVERRIDE_SET audit row(s) exist for Org A/CONCURRENT_CALL_COUNT, and none exist for the failed negative/overflow/wrong-org/invalid-metric attempts ==='
SELECT action_kind, resource_type, resource_id, resource_snapshot
FROM audit.audit_events
WHERE resource_type = 'QUOTA_CONFIG'
   OR action_kind ILIKE '%QUOTA%'
ORDER BY occurred_at;
