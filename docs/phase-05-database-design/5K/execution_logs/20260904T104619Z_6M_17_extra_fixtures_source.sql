-- Phase 6M extended fixtures (post-107 head), inserted on phase6m-pg18-incr
-- (which already carries the 9-row 104-baseline fixture set through 105/106/107).
-- Adds: a second organization (Org B, for cross-org grant/resource tests), a
-- third fixture user (a second Platform Admin actor, for cross-admin tests),
-- one voice.conversations/recordings/transcripts/transcript_segments set for
-- Org A and one minimal set for Org B, and a battery of break-glass grants
-- covering the §10 21-item adversarial matrix's distinguishing conditions
-- (valid SENSITIVE_MEDIA_ACCESS; wrong-but-valid purpose; expired; released;
-- wrong org; wrong admin; wrong session). Run as postgres (BYPASSRLS) so RLS
-- does not interfere with fixture loading across two tenants in one session.
BEGIN;

-- Third fixture user: a second Platform Admin actor, distinct from f...002.
INSERT INTO identity.users (id, email, email_normalized, display_name, status, password_hash)
VALUES ('f0000000-0000-4000-8000-000000000003', 'admin2.fixture@example.com', 'admin2.fixture@example.com', 'Fixture Platform Admin Actor Two', 'ACTIVE', 'argon2id$fixture$fake-hash-not-real');

-- Org B: a second tenant, used only to prove cross-tenant grant/resource
-- boundaries. Reuses the existing fixture owner user (001) as owner.
INSERT INTO organization.organizations (id, name, slug, status, owner_user_id, country_code, currency)
VALUES ('f0000000-0000-4000-8000-0000000000a2', 'Fixture Org 6M (B)', 'fixture-org-6m-b', 'ACTIVE', 'f0000000-0000-4000-8000-000000000001', 'IN', 'INR');

-- Org A voice content: one conversation, one recording, one transcript with
-- two segments -- the resource set the positive-path access functions and
-- the raw-column-denial tests will exercise.
INSERT INTO voice.conversations
  (id, organization_id, call_id, agent_version_id, status, summary_text, started_at, completed_at)
VALUES
  ('f0000000-0000-4000-8000-000000000201', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000301', 'f0000000-0000-4000-8000-000000000401',
   'COMPLETED', 'SENSITIVE: caller discussed a medical prescription refill.', now() - interval '10 minutes', now());

INSERT INTO voice.recordings
  (id, organization_id, call_id, conversation_id, status, storage_ref, storage_provider,
   content_type, duration_seconds, recording_policy, consent_obtained)
VALUES
  ('f0000000-0000-4000-8000-000000000202', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000301', 'f0000000-0000-4000-8000-000000000201',
   'STORED', 'org/f0000000-0000-4000-8000-0000000000a1/recordings/call-301.wav', 'S3',
   'audio/wav', 245, 'ENABLED', true);

INSERT INTO voice.transcripts
  (id, organization_id, conversation_id, call_id, status, total_segments, completed_at)
VALUES
  ('f0000000-0000-4000-8000-000000000203', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000201', 'f0000000-0000-4000-8000-000000000301',
   'COMPLETED', 2, now());

INSERT INTO voice.transcript_segments
  (id, organization_id, transcript_id, conversation_id, call_id, sequence_number, speaker, text, is_partial)
VALUES
  ('f0000000-0000-4000-8000-000000000204', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000203', 'f0000000-0000-4000-8000-000000000201',
   'f0000000-0000-4000-8000-000000000301', 0, 'CALLER', 'SENSITIVE: my date of birth is 4th of March and my prescription number is 9981.', false),
  ('f0000000-0000-4000-8000-000000000205', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000203', 'f0000000-0000-4000-8000-000000000201',
   'f0000000-0000-4000-8000-000000000301', 1, 'AGENT', 'SENSITIVE: confirming refill for prescription 9981, dispatching to your pharmacy.', false);

-- Org B voice content: one recording, so a grant issued for Org A can be
-- proven unable to read it (§10 item 6 / §29 cross-org resource test).
INSERT INTO voice.conversations
  (id, organization_id, call_id, agent_version_id, status, summary_text, started_at, completed_at)
VALUES
  ('f0000000-0000-4000-8000-000000000211', 'f0000000-0000-4000-8000-0000000000a2',
   'f0000000-0000-4000-8000-000000000311', 'f0000000-0000-4000-8000-000000000401',
   'COMPLETED', 'SENSITIVE (Org B): unrelated caller content.', now() - interval '5 minutes', now());

INSERT INTO voice.recordings
  (id, organization_id, call_id, conversation_id, status, storage_ref, storage_provider,
   content_type, duration_seconds, recording_policy, consent_obtained)
VALUES
  ('f0000000-0000-4000-8000-000000000212', 'f0000000-0000-4000-8000-0000000000a2',
   'f0000000-0000-4000-8000-000000000311', 'f0000000-0000-4000-8000-000000000211',
   'STORED', 'org/f0000000-0000-4000-8000-0000000000a2/recordings/call-311.wav', 'S3',
   'audio/wav', 90, 'ENABLED', true);

INSERT INTO voice.transcripts
  (id, organization_id, conversation_id, call_id, status, total_segments, completed_at)
VALUES
  ('f0000000-0000-4000-8000-000000000213', 'f0000000-0000-4000-8000-0000000000a2',
   'f0000000-0000-4000-8000-000000000211', 'f0000000-0000-4000-8000-000000000311',
   'COMPLETED', 0, now());

-- Break-glass grants covering the §10 matrix's distinguishing conditions.
-- g1: valid SENSITIVE_MEDIA_ACCESS grant, org A, admin 002, session S1 -- the
--     ALLOW baseline (item 3).
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, expires_at, purposes)
VALUES
  ('f0000000-0000-4000-8000-000000000401', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000002', 'Fixture grant g1: valid SENSITIVE_MEDIA_ACCESS for positive-path testing.',
   'fixture-session-001', now() + interval '1 hour', ARRAY['SENSITIVE_MEDIA_ACCESS']);

-- g2: valid but wrong purpose (SUPPORT_BILLING only) -- item 2.
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, expires_at, purposes)
VALUES
  ('f0000000-0000-4000-8000-000000000402', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000002', 'Fixture grant g2: valid grant with a different allow-listed purpose only.',
   'fixture-session-001', now() + interval '1 hour', ARRAY['SUPPORT_BILLING']);

-- g3: SENSITIVE_MEDIA_ACCESS but already expired -- item 4. issued_at is
-- explicitly backdated too, since chk_bgg_expires_after_issued requires
-- expires_at > issued_at and issued_at otherwise defaults to now().
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, issued_at, expires_at, purposes)
VALUES
  ('f0000000-0000-4000-8000-000000000403', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000002', 'Fixture grant g3: expired SENSITIVE_MEDIA_ACCESS grant.',
   'fixture-session-001', now() - interval '2 hours', now() - interval '1 hour', ARRAY['SENSITIVE_MEDIA_ACCESS']);

-- g4: SENSITIVE_MEDIA_ACCESS but RELEASED -- item 5.
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, expires_at, purposes, status, released_at, released_by)
VALUES
  ('f0000000-0000-4000-8000-000000000404', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000002', 'Fixture grant g4: released SENSITIVE_MEDIA_ACCESS grant.',
   'fixture-session-001', now() + interval '1 hour', ARRAY['SENSITIVE_MEDIA_ACCESS'], 'RELEASED', now(), 'f0000000-0000-4000-8000-000000000002');

-- g5: valid SENSITIVE_MEDIA_ACCESS grant issued for Org B (not Org A) -- used
--     to prove an Org-B grant cannot be redeemed against Org A (item 6, at
--     the grant level).
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, expires_at, purposes)
VALUES
  ('f0000000-0000-4000-8000-000000000405', 'f0000000-0000-4000-8000-0000000000a2',
   'f0000000-0000-4000-8000-000000000002', 'Fixture grant g5: valid SENSITIVE_MEDIA_ACCESS grant, but issued for Org B.',
   'fixture-session-001', now() + interval '1 hour', ARRAY['SENSITIVE_MEDIA_ACCESS']);

-- g6: valid SENSITIVE_MEDIA_ACCESS grant, org A, but issued to admin 003
--     (not 002) -- item 7 (Admin A grant used by Admin B).
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, expires_at, purposes)
VALUES
  ('f0000000-0000-4000-8000-000000000406', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000003', 'Fixture grant g6: valid SENSITIVE_MEDIA_ACCESS grant, issued to a different admin.',
   'fixture-session-001', now() + interval '1 hour', ARRAY['SENSITIVE_MEDIA_ACCESS']);

-- g7: valid SENSITIVE_MEDIA_ACCESS grant, org A, admin 002, but bound to a
--     different session (fixture-session-002) -- item 8 (session S1 grant
--     used from S2).
INSERT INTO organization.break_glass_grants
  (id, organization_id, admin_user_id, justification, session_id, expires_at, purposes)
VALUES
  ('f0000000-0000-4000-8000-000000000407', 'f0000000-0000-4000-8000-0000000000a1',
   'f0000000-0000-4000-8000-000000000002', 'Fixture grant g7: valid SENSITIVE_MEDIA_ACCESS grant, bound to a different session.',
   'fixture-session-002', now() + interval '1 hour', ARRAY['SENSITIVE_MEDIA_ACCESS']);

COMMIT;

-- Verification.
SELECT
  (SELECT count(*) FROM identity.users WHERE id = 'f0000000-0000-4000-8000-000000000003') AS user3,
  (SELECT count(*) FROM organization.organizations WHERE id = 'f0000000-0000-4000-8000-0000000000a2') AS org_b,
  (SELECT count(*) FROM voice.conversations WHERE organization_id IN ('f0000000-0000-4000-8000-0000000000a1','f0000000-0000-4000-8000-0000000000a2')) AS conversations,
  (SELECT count(*) FROM voice.recordings WHERE organization_id IN ('f0000000-0000-4000-8000-0000000000a1','f0000000-0000-4000-8000-0000000000a2')) AS recordings,
  (SELECT count(*) FROM voice.transcripts WHERE organization_id IN ('f0000000-0000-4000-8000-0000000000a1','f0000000-0000-4000-8000-0000000000a2')) AS transcripts,
  (SELECT count(*) FROM voice.transcript_segments WHERE organization_id = 'f0000000-0000-4000-8000-0000000000a1') AS segments,
  (SELECT count(*) FROM organization.break_glass_grants WHERE id IN (
    'f0000000-0000-4000-8000-000000000401','f0000000-0000-4000-8000-000000000402',
    'f0000000-0000-4000-8000-000000000403','f0000000-0000-4000-8000-000000000404',
    'f0000000-0000-4000-8000-000000000405','f0000000-0000-4000-8000-000000000406',
    'f0000000-0000-4000-8000-000000000407')) AS grants_g1_to_g7;
