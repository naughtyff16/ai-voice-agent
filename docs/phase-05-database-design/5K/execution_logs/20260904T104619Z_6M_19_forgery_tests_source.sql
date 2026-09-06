-- SS2 forgery test battery A-D, plus is_platform_admin() probes, run as
-- app_api (session_user = app_api, no BYPASSRLS, ordinary tenant principal).
\set ON_ERROR_STOP off

\echo '=== A. app_api, no GUC set -> is_platform_admin() expect false ==='
SELECT organization.is_platform_admin() AS is_admin, session_user, current_user;

\echo '=== B. app_api + SET app.is_platform_admin=true -> is_platform_admin() expect still false (session_user check blocks it) ==='
SET app.is_platform_admin = 'true';
SELECT organization.is_platform_admin() AS is_admin, session_user, current_user, current_setting('app.is_platform_admin', true) AS guc_value;

\echo '=== C. app_api + set_config(...,...,false) (non-local, "durable" within session) -> still expect false ==='
SELECT set_config('app.is_platform_admin', 'true', false);
SELECT organization.is_platform_admin() AS is_admin;

\echo '=== B/C follow-on: app_api attempts fn_break_glass_grant directly despite forged GUC -> expect permission denied (REVOKE EXECUTE FROM app_api) ==='
SELECT organization.fn_break_glass_grant(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Forged attempt: app_api trying to self-grant break-glass access via GUC forgery.',
  3600, 'forged-session', ARRAY['SENSITIVE_MEDIA_ACCESS']
);

\echo '=== app_api attempts fn_platform_suspend_organization directly despite forged GUC -> expect permission denied ==='
SELECT organization.fn_platform_suspend_organization(
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'Forged suspend attempt via app_api with spoofed GUC.'
);

\echo '=== app_api attempts voice.fn_platform_access_recording directly despite forged GUC + forged grant id -> expect permission denied (function not GRANTed to app_api) ==='
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000401'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '=== app_api attempts billing.fn_platform_settle_refund directly -> expect permission denied (not granted to app_api) ==='
SELECT billing.fn_platform_settle_refund(
  'f0000000-0000-4000-8000-0000000000e1'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'forged-provider-refund-id'
);

\echo '=== D. app_api + caller-controlled tenant context (app.tenant_id set to a foreign org) does not confer platform admin or cross-tenant break-glass capability ==='
SET app.tenant_id = 'f0000000-0000-4000-8000-0000000000a2';
SELECT organization.is_platform_admin() AS is_admin;
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000401'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a2'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000212'::uuid
);

\echo '=== G. app_api raw SELECT of protected voice content columns (ordinary tenant path uses RLS, not this GUC forgery) -> expect RLS-scoped/denied per tenant grants, not a bypass ==='
SELECT storage_ref FROM voice.recordings WHERE id = 'f0000000-0000-4000-8000-000000000202';
