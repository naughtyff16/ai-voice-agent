-- §10 items 15-16 -- ordinary tenant sensitive-media access must be
-- UNCHANGED by the app_platform_admin hardening in 107_5B5.sql. Tenant
-- OWNER/ADMIN/MEMBER/VIEWER/BILLING_ADMIN all connect through the SAME
-- shared app_api DB role (RLS-scoped by app.tenant_id) -- role-based
-- differentiation (OWNER/ADMIN get recording:access_media/transcript:
-- access_content, MEMBER/VIEWER/BILLING_ADMIN do not by default) is
-- enforced at the APPLICATION permission-check layer (5B/6D), not at the
-- DB grant layer, and is therefore orthogonal to and untouched by 107's
-- app_platform_admin-only REVOKE/column-restricted-GRANT changes. This
-- script proves the DB-layer half of that claim: app_api's own table
-- privileges and RLS policies on the five hardened voice.* tables are
-- byte-identical in effect to before 107 ran (full, unrestricted column
-- access, tenant-scoped by RLS) -- so no ordinary tenant user of any role
-- lost or gained anything at the DB layer as a side effect of hardening
-- app_platform_admin.
\set ON_ERROR_STOP off

\echo '=== [T1] app_api table + column privilege check on the five hardened tables -- expect FULL (unrestricted) column access, unlike app_platform_admin ==='
SELECT table_name, privilege_type, is_grantable
FROM information_schema.table_privileges
WHERE grantee = 'app_api' AND table_schema = 'voice'
  AND table_name IN ('recordings','transcripts','transcript_segments','conversations','turns')
ORDER BY table_name, privilege_type;

\echo '=== [T2] confirm NO column-level privilege restriction exists for app_api (i.e. no column_privileges rows at all -- table-level GRANT already covers every column) ==='
SELECT table_name, column_name, privilege_type
FROM information_schema.column_privileges
WHERE grantee = 'app_api' AND table_schema = 'voice'
  AND table_name IN ('recordings','transcripts','transcript_segments','conversations','turns');

-- Now connect as app_api itself (session_user = app_api), the role every
-- ordinary tenant request actually uses, and set tenant context to Org A
-- exactly as the real backend would after resolving the caller's JWT/API
-- key to their organization. Role-based (OWNER vs MEMBER vs VIEWER etc.)
-- differentiation is an application-layer permission-check concern (5B/6D)
-- that happens BEFORE this query is ever issued -- once the backend has
-- decided the caller may see the content, it reads through app_api, which
-- is what this proves is unrestricted, exactly as pre-hardening.

\echo '=== [T3] (as app_api, tenant=Org A) full-content recording read, including storage_ref -- expect SUCCESS, same as before 107 ==='
SET app.tenant_id = 'f0000000-0000-4000-8000-0000000000a1';
SELECT id, organization_id, storage_ref, status, consent_obtained
FROM voice.recordings
WHERE id = 'f0000000-0000-4000-8000-000000000202';

\echo '=== [T4] (as app_api, tenant=Org A) full-content transcript segment read, including text -- expect SUCCESS, same as before 107 ==='
SELECT id, organization_id, text, sequence_number
FROM voice.transcript_segments
WHERE conversation_id = (SELECT conversation_id FROM voice.recordings WHERE id = 'f0000000-0000-4000-8000-000000000202')
ORDER BY sequence_number;

\echo '=== [T5] (as app_api, tenant=Org A) RLS still correctly excludes Org B rows -- expect 0 rows for the Org B recording id ==='
SELECT id, organization_id, storage_ref
FROM voice.recordings
WHERE id = 'f0000000-0000-4000-8000-000000000212';

\echo '=== [T6] (as app_api, tenant=Org B) switching tenant context -- Org B recording now visible, Org A recording now excluded (proves RLS scoping is per-request tenant context, unaffected by any app_platform_admin change) ==='
SET app.tenant_id = 'f0000000-0000-4000-8000-0000000000a2';
SELECT id, organization_id, storage_ref FROM voice.recordings WHERE id = 'f0000000-0000-4000-8000-000000000212';
SELECT id, organization_id, storage_ref FROM voice.recordings WHERE id = 'f0000000-0000-4000-8000-000000000202';
