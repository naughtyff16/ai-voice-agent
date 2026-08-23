-- =================================================================
-- Migration 085 (Phase 5D.1): active-suppression DB-level uniqueness
-- down_revision: 084_5F7
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, Section 5
--
-- 5D-CRM-Schema.md itself already names the fix as a carry-forward: a
-- partial unique index on (organization_id, phone_e164, scope, channel)
-- WHERE status = 'ACTIVE'. Implemented now because suppression/opt-out/
-- DNC state is compliance-sensitive and must fail safe — a SELECT-
-- existing-then-INSERT application pattern is race-prone and the
-- executed schema (024_5D.sql) has never enforced this at the DB level.
--
-- NULLS NOT DISTINCT is required: organization_id is NULL for PLATFORM/
-- REGULATORY scope rows (chk_sup_scope_org_id), and a plain UNIQUE index
-- treats every NULL as distinct — it would silently fail to deduplicate
-- those two scopes. (Precedented elsewhere in this schema, e.g.
-- analytics.billing_revenue_monthly, 071_5J.sql.)
--
-- scope is part of the key, so an ORG-scope suppression and a
-- PLATFORM-scope suppression for the same phone/channel remain
-- independent rows (both legitimately ACTIVE) — this migration does not
-- block that. Only two ACTIVE rows with the identical
-- (organization_id, phone_e164, scope, channel) tuple — which are
-- functionally the same suppression regardless of differing reason/
-- source — are rejected.
-- =================================================================

DO $$
DECLARE
  v_dupe_count INTEGER;
BEGIN
  SELECT count(*) INTO v_dupe_count FROM (
    SELECT organization_id, phone_e164, scope, channel
    FROM crm.contact_suppressions
    WHERE status = 'ACTIVE'
    GROUP BY organization_id, phone_e164, scope, channel
    HAVING count(*) > 1
  ) dupes;
  IF v_dupe_count > 0 THEN
    RAISE EXCEPTION 'migration 085_5D1: % existing duplicate ACTIVE suppression group(s) for the same (organization_id, phone_e164, scope, channel) would violate the new uniqueness constraint. Manual reconciliation (lift all but one per group) required before this migration can proceed.', v_dupe_count;
  END IF;
END;
$$;

CREATE UNIQUE INDEX uq_sup_active
  ON crm.contact_suppressions (organization_id, phone_e164, scope, channel)
  NULLS NOT DISTINCT
  WHERE status = 'ACTIVE';
