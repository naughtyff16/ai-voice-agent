-- =================================================================
-- Migration 104 (Phase 5B.3): sensitive-media permission split
--   recording:access_media, transcript:access_content
-- down_revision: 103_5J2
-- Transaction: yes
-- Source: docs/phase-06-api-design/6L-Analytics-Audit-APIs.md freeze-gate
--   remediation pass, owner-approved sensitive-media policy (Section 3
--   of the governing remediation task) and the confirmed RBAC
--   contradiction it identifies (Section 4).
--
-- Trigger -- a genuine, evidenced contradiction, not a convenience
-- change:
--
--   007_5B.sql seeds exactly two permissions covering recordings and
--   transcripts: recording:read and transcript:read. Both are granted
--   by default to OWNER, ADMIN, MEMBER, and VIEWER (007_5B.sql lines
--   88-90, 121, 143, 156, 167) -- and 6D-Voice-Call-Agent-APIs.md
--   §16/§17/§25 (frozen, prior to this remediation pass) gates BOTH
--   recording metadata AND the signed playback/download-url capability
--   behind the single recording:read permission, and BOTH transcript
--   metadata AND full segment text behind the single transcript:read
--   permission. There is no permission distinguishing "may see that a
--   recording/transcript exists" from "may hear the audio / read the
--   words" -- so every MEMBER and VIEWER in every tenant organization
--   today can play call recordings and read full transcript content by
--   default, with no per-tenant configuration able to prevent it short
--   of building an entirely separate authorization mechanism outside
--   RBAC. This contradicts the owner-approved default policy: MEMBER
--   and VIEWER get sensitive media content NO by default (MEMBER only
--   via an explicit custom-role grant; VIEWER never); OWNER and ADMIN
--   get it YES; BILLING_ADMIN never (already correctly excluded --
--   BILLING_ADMIN holds neither recording:read nor transcript:read in
--   007_5B.sql's seed, and gains neither new permission here either).
--
-- What this migration does: adds two new permissions --
-- recording:access_media and transcript:access_content -- gates
-- nothing by itself (a permission catalog row has no enforcement
-- effect on its own; 6D's own endpoint contracts, amended in this same
-- remediation pass, are what actually re-gate the two sensitive
-- endpoints behind these new strings). Grants both, by default, to
-- OWNER and ADMIN only -- mirroring 007_5B.sql's own existing pattern
-- for every other sensitivity-tiered permission pair in that file
-- (e.g. api_key:manage, compliance:manage, data_subject:manage are all
-- OWNER/ADMIN-only, never MEMBER/VIEWER/BILLING_ADMIN). MEMBER and
-- VIEWER receive neither by default. A tenant's own OWNER/ADMIN may
-- assign either or both permissions to a tenant-created custom role
-- (organization.roles WHERE organization_id = <tenant> AND is_system =
-- FALSE, already fully supported by 003_5B.sql/007_5B.sql's own
-- role:manage-gated mechanism -- no schema change needed for that
-- capability, it already exists) and assign a MEMBER-tier user to that
-- custom role -- this is the exact mechanism the owner-approved policy
-- names as "MEMBER... may receive sensitive-media access ONLY through
-- explicit custom-role permission."
--
-- What this migration does NOT do: it does not remove, rename, or
-- change the grant set of recording:read or transcript:read (both
-- remain exactly as seeded by 007_5B.sql for OWNER/ADMIN/MEMBER/VIEWER
-- -- ordinary call/report metadata visibility is explicitly preserved,
-- per the governing task's own instruction not to solve this problem
-- by removing ordinary call metadata/report visibility); it does not
-- touch BILLING_ADMIN's grant set (already correctly excluded from
-- both permissions); it does not touch any table, function, role, or
-- grant outside organization.permissions / organization.role_
-- permissions; it does not modify migrations 001-103.
--
-- Display-name clarification (documentation-only, no behavioral
-- change): recording:read's and transcript:read's display_name are
-- UPDATEd to make their now-explicitly-metadata-only scope
-- unambiguous to anyone reading the permission catalog directly --
-- their name/resource/action columns, RLS behavior, and grant set are
-- completely unchanged; only the human-readable label is corrected.
-- =================================================================

-- ---------------------------------------------------------------
-- Part A: new permissions
-- ---------------------------------------------------------------

INSERT INTO organization.permissions (name, display_name, resource, action) VALUES
  ('recording:access_media','Access Recording Media (Playback/Download)','recording','access_media'),
  ('transcript:access_content','Access Transcript Content','transcript','access_content')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------
-- Part B: display-name clarification for the existing, unchanged-
-- grant-set metadata permissions (documentation only)
-- ---------------------------------------------------------------

UPDATE organization.permissions
   SET display_name = 'View Recording Metadata (status, duration, policy -- not audio)'
 WHERE name = 'recording:read';

UPDATE organization.permissions
   SET display_name = 'View Transcript Metadata (status, segment count -- not text)'
 WHERE name = 'transcript:read';

-- ---------------------------------------------------------------
-- Part C: default role grants -- OWNER and ADMIN only
-- ---------------------------------------------------------------

WITH
  r AS (SELECT id, name FROM organization.roles WHERE organization_id IS NULL),
  p AS (SELECT id, name FROM organization.permissions)
INSERT INTO organization.role_permissions (id, role_id, permission_id)
SELECT gen_uuid_v7(), r.id, p.id
FROM (VALUES
  ('OWNER','recording:access_media'),
  ('OWNER','transcript:access_content'),
  ('ADMIN','recording:access_media'),
  ('ADMIN','transcript:access_content')
) AS m(role_name, perm_name)
JOIN r ON r.name = m.role_name
JOIN p ON p.name = m.perm_name
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Deliberately NOT granted here (matches the owner-approved default
-- policy exactly): MEMBER, VIEWER, BILLING_ADMIN receive neither
-- recording:access_media nor transcript:access_content by default.
-- MEMBER may be granted either via a tenant-created custom role
-- (organization.roles, is_system = FALSE) -- no migration needed for
-- that per-tenant action, it uses the existing role:manage-gated
-- custom-role/role_permissions mechanism unchanged by this file.
