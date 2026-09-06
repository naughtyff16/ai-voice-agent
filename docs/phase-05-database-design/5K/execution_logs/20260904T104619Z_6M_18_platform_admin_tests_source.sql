-- Phase 6M live test battery, run as app_platform_admin (session_user =
-- app_platform_admin) with the application GUC set, exactly as the real
-- Platform Admin REST backend would connect. Exercises:
--   * SS10 item 3 (positive path, grant g1) + SS29/SS10 items 20-21 (audit
--     content assertions)
--   * SS10 items 2,4,5,6,7,8 (adversarial matrix: wrong purpose, expired,
--     released, wrong org, wrong admin, wrong session) via g2-g7
--   * SS10 item 6 at the resource-ownership level (valid grant, resource
--     belongs to the other org)
--   * SS10 item 19 / SS29 (raw column SELECT denial on protected content
--     columns, even though session_user = app_platform_admin and BYPASSRLS)
\set ON_ERROR_STOP off
SET app.is_platform_admin = 'true';

\echo '--- [1] POSITIVE PATH: g1, recording, org A (expect: ALLOW, storage_ref returned) ---'
SELECT id, call_id, storage_ref, storage_provider, content_type
FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000401'::uuid, -- grant g1
  'f0000000-0000-4000-8000-000000000002'::uuid, -- admin 002
  'f0000000-0000-4000-8000-0000000000a1'::uuid, -- org A
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid  -- recording
);

\echo '--- [2] POSITIVE PATH: g1, transcript, org A (expect: ALLOW, segment text returned) ---'
SELECT sequence_number, speaker, text
FROM voice.fn_platform_access_transcript(
  'f0000000-0000-4000-8000-000000000401'::uuid, -- grant g1
  'f0000000-0000-4000-8000-000000000002'::uuid, -- admin 002
  'f0000000-0000-4000-8000-0000000000a1'::uuid, -- org A
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000203'::uuid  -- transcript
)
ORDER BY sequence_number;

\echo '--- [3] item 2: g2 (valid grant, wrong purpose SUPPORT_BILLING) + recording -> expect DENY ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000402'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '--- [4] item 4: g3 (expired) + recording -> expect DENY ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000403'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '--- [5] item 5: g4 (released) + recording -> expect DENY ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000404'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '--- [6] item 6 (grant level): g5 (issued for org B) used with p_organization_id=org A -> expect DENY ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000405'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '--- [6b] item 6 (resource level): g1 (org A, valid) but target recording belongs to org B -> expect DENY (not found for org) ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000401'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000212'::uuid -- Org B recording
);

\echo '--- [7] item 7: g6 (issued to admin 003) but called with admin_user_id=002 -> expect DENY ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000406'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '--- [8] item 8: g7 (bound to fixture-session-002) but called with fixture-session-001 -> expect DENY ---'
SELECT * FROM voice.fn_platform_access_recording(
  'f0000000-0000-4000-8000-000000000407'::uuid,
  'f0000000-0000-4000-8000-000000000002'::uuid,
  'f0000000-0000-4000-8000-0000000000a1'::uuid,
  'fixture-session-001',
  'f0000000-0000-4000-8000-000000000202'::uuid
);

\echo '--- [9] item 19: raw SELECT of protected column storage_ref by app_platform_admin -> expect permission denied for column ---'
SELECT storage_ref FROM voice.recordings WHERE id = 'f0000000-0000-4000-8000-000000000202';

\echo '--- [9b] item 19: raw SELECT of protected column text (segments) by app_platform_admin -> expect permission denied for column ---'
SELECT text FROM voice.transcript_segments WHERE transcript_id = 'f0000000-0000-4000-8000-000000000203';

\echo '--- [9c] item 19: raw SELECT of protected column summary_text (conversations) by app_platform_admin -> expect permission denied for column ---'
SELECT summary_text FROM voice.conversations WHERE id = 'f0000000-0000-4000-8000-000000000201';

\echo '--- [9d] control: raw SELECT of a NON-protected column by app_platform_admin -> expect ALLOW (proves it is column-scoped, not table-wide) ---'
SELECT id, status FROM voice.recordings WHERE id = 'f0000000-0000-4000-8000-000000000202';

\echo '--- [10] items 20-21: audit rows for the positive-path accesses, confirming grant_id present and no storage_ref/transcript text leakage ---'
SELECT action_kind, resource_type, resource_id, actor_type,
       resource_snapshot ? 'storage_ref' AS leaked_storage_ref,
       resource_snapshot ? 'text' AS leaked_transcript_text,
       resource_snapshot
FROM audit.audit_events
WHERE action_kind IN ('RECORDING_ACCESS_GRANTED', 'TRANSCRIPT_ACCESS_GRANTED')
  AND resource_id IN ('f0000000-0000-4000-8000-000000000202', 'f0000000-0000-4000-8000-000000000203')
ORDER BY occurred_at;
