-- =================================================================
-- Migration 096 (Phase 5B.2): permission catalog amendment —
--   crm_field:manage (OWNER/ADMIN only)
-- down_revision: 095_5D4
-- Transaction: yes
-- Source: Phase 6G CRM Reconciliation (2026-08-28), DEP-6G-10
--
-- WHY THIS EXISTS
-- ----------------
-- 6G exposes CRM custom-field-definition administration (create/update/
-- archive a tenant-wide field definition — crm.crm_field_definitions).
-- 6G's first pass mapped this onto the existing contact:write permission
-- for lack of a dedicated scope, then flagged it (DEP-6G-10) as a real
-- least-privilege concern: contact:write is MEMBER-eligible (007_5B.sql),
-- but a custom-field-definition change has tenant-wide schema impact —
-- every future Contact/Company/Deal create/edit is affected — a
-- materially larger blast radius than an ordinary per-record contact
-- edit. This crosses the bar the governing task sets for adding a new
-- permission ("prove that the existing catalog cannot safely represent
-- an exposed capability") — none of the other 4C/5B terminology gaps
-- reviewed in this same reconciliation pass (contact:qualify,
-- contact:score_override, contact:force_convert, crm:admin for non-
-- author note delete) meet that bar, because in each of those cases the
-- capability is either not exposed at all, or the existing interim
-- mapping (contact:write, or an OWNER/ADMIN role check) is already
-- appropriately conservative — see 6G §5/§39 for the full classification.
--
-- This migration is purely additive, following 007_5B.sql's exact
-- idempotent ON CONFLICT DO NOTHING seeding pattern. It does not modify
-- 007_5B.sql (frozen) and does not touch any other permission, role, or
-- role-permission row.
-- =================================================================

INSERT INTO organization.permissions (name, display_name, resource, action) VALUES
  ('crm_field:manage', 'Manage CRM Custom Field Definitions', 'crm_field', 'manage')
ON CONFLICT (name) DO NOTHING;

WITH
  r AS (SELECT id, name FROM organization.roles WHERE organization_id IS NULL),
  p AS (SELECT id, name FROM organization.permissions WHERE name = 'crm_field:manage')
INSERT INTO organization.role_permissions (id, role_id, permission_id)
SELECT gen_uuid_v7(), r.id, p.id
FROM (VALUES
  ('OWNER', 'crm_field:manage'),
  ('ADMIN', 'crm_field:manage')
) AS m(role_name, perm_name)
JOIN r ON r.name = m.role_name
JOIN p ON p.name = m.perm_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
