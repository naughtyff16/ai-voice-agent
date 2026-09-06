-- Run as app_platform_admin (session_user = app_platform_admin). Confirms
-- that the table-level GRANT alone already blocks any raw UPDATE attempt --
-- app_platform_admin holds only SELECT ("r") on organization.
-- break_glass_grants, no UPDATE/"w" -- so a mutation attempt should fail
-- with a permission-denied error before the trg_bgg_immutable_fields
-- trigger is ever reached. This is layer 1 of 2.
\set ON_ERROR_STOP off
SET app.is_platform_admin = 'true';

\echo '=== [I1] app_platform_admin attempts to widen g1 purposes via raw UPDATE -> expect permission denied (no UPDATE grant) ==='
UPDATE organization.break_glass_grants
SET purposes = ARRAY['SENSITIVE_MEDIA_ACCESS','SUPPORT_BILLING']
WHERE id = 'f0000000-0000-4000-8000-000000000401';

\echo '=== [I2] app_platform_admin attempts to replace g1 purposes entirely via raw UPDATE -> expect permission denied (no UPDATE grant) ==='
UPDATE organization.break_glass_grants
SET purposes = ARRAY['SUPPORT_BILLING']
WHERE id = 'f0000000-0000-4000-8000-000000000401';

\echo '=== [I3] post-attempt state: g1 purposes/status unchanged ==='
SELECT id, status, purposes FROM organization.break_glass_grants
WHERE id = 'f0000000-0000-4000-8000-000000000401';
