\set ON_ERROR_STOP off
SET app.is_platform_admin = 'true';

\echo '=== [Q5-RETEST] server-authoritative org / wrong org id -> expect not-found style failure (fixed) ==='
SELECT billing.fn_platform_set_quota_override(
  'f0000000-0000-4000-8000-000000000000'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'CONCURRENT_CALL_COUNT', 10, 20,
  'Fixture attempt: nonexistent organization id (post-fix retest).',
  NULL, 'calls'
);

\echo '=== [Q5-RETEST verify] confirm no row was created for the nonexistent org ==='
SELECT count(*) AS orphan_row_count FROM billing.quota_configs
WHERE organization_id = 'f0000000-0000-4000-8000-000000000000';

\echo '=== [Q5-RETEST verify] confirm no new audit row was created for the nonexistent org ==='
SELECT count(*) AS orphan_audit_count FROM audit.audit_events
WHERE resource_type = 'QUOTA_CONFIG'
  AND resource_snapshot ->> 'reason' = 'Fixture attempt: nonexistent organization id (post-fix retest).';
