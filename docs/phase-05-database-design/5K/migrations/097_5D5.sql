-- =================================================================
-- Migration 097 (Phase 5D.5): crm.fn_merge_contacts() — remove Contact
--   PII from the immutable merge marker Activity payload
-- down_revision: 096_5B2
-- Transaction: yes
-- Source: independent whole-project review following the Phase 6G CRM
--   Reconciliation (2026-08-28) — blocker: merge marker leaks PII past
--   GDPR erasure
--
-- WHY THIS EXISTS
-- ----------------
-- 093_5D2.sql's crm.fn_merge_contacts() recorded a marker Activity on the
-- merge survivor whose payload copied the secondary Contact's direct PII:
--   'secondary_full_name', v_secondary.full_name,
--   'secondary_phone_e164', v_secondary.phone_e164,
-- crm.activities is deliberately append-only (DDR-4C-002, REVOKE UPDATE,
-- DELETE on app_api/app_worker, 022_5D.sql) and is never touched by
-- Contact GDPR erasure (§22 of 6G-CRM-Leads-APIs.md; ADR-5D-007 — erasure
-- clears fields on the crm.contacts row only). Copying a Contact's name/
-- phone into that Activity's JSONB payload therefore created a second,
-- durable, erasure-proof copy of exactly the PII `DELETE /contacts/{id}`
-- is supposed to clear — a real, physical GDPR-erasure-boundary defect,
-- not merely an undesirable design choice.
--
-- THE FIX
-- --------
-- CREATE OR REPLACE crm.fn_merge_contacts() with an IDENTICAL body except
-- the marker Activity's payload now carries identifier/provenance fields
-- only:
--   event                 -- 'contact_merged', unchanged
--   secondary_contact_id  -- unchanged — an id, not PII by itself
--   primary_contact_id    -- newly added — the survivor's own id, useful
--                            context for anyone reading the payload out
--                            of the timeline it's already attached to
--   merged_by             -- unchanged — a UserId, not PII by itself
-- No Contact name, phone, email, address, custom-field value, or
-- qualification_reason is ever written into this payload, before or
-- after this fix's own initial draft (verified against every field this
-- function reads from v_secondary/v_primary before writing this
-- migration — only the two now-removed lines touched Activity payload
-- PII; every other v_secondary/v_primary field reference in the function
-- writes to crm.contacts itself, which GDPR erasure already covers).
--
-- Every other line of the function — self/tenant/erased/already-merged
-- guards, lock ordering, lead-status ranking, tag/custom-field-value
-- union and cap enforcement, the four mutable-child repoints, and the
-- secondary's own merged_into_contact_id/merged_at assignment — is
-- byte-for-byte unchanged from 093_5D2.sql. This migration does not
-- touch merge-lineage columns, triggers, constraints, grants on the
-- mutable child tables, or the append-only privileges on
-- crm.activities/crm.lead_score_records.
--
-- 093_5D2.sql itself is NOT edited — it is a prior, already-applied,
-- checksummed migration. This is a new forward migration that replaces
-- the function definition currently installed in a live database.
-- SECURITY DEFINER hardening is carried forward unchanged: explicit
-- non-empty search_path (public included, for the same gen_uuid_v7()/
-- gen_random_bytes() reason 093_5D2.sql's own header comment documents),
-- REVOKE ALL FROM PUBLIC, EXECUTE granted only to app_api/app_worker/
-- app_platform_admin — identical grant set to before.
-- =================================================================

CREATE OR REPLACE FUNCTION crm.fn_merge_contacts(
  p_primary_contact_id   UUID,
  p_secondary_contact_id UUID,
  p_organization_id      UUID,
  p_merged_by_ref        UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = crm, public, pg_catalog
-- 'public' is required here, not optional: this function's final step
-- INSERTs into crm.activities, whose id column defaults to
-- public.gen_uuid_v7(), which itself calls public.gen_random_bytes()
-- (pgcrypto, installed into 'public' per 001_5B.sql). Unchanged from
-- 093_5D2.sql — see that file's header comment for the full rationale.
AS $$
DECLARE
  v_primary   crm.contacts%ROWTYPE;
  v_activity_id UUID;
  v_secondary crm.contacts%ROWTYPE;
  v_lock_first  UUID;
  v_lock_second UUID;
  v_new_tags TEXT[];
  v_merged_cfv JSONB;
  v_cfv_count INTEGER;
  v_primary_rank INTEGER;
  v_secondary_rank INTEGER;
  v_new_lead_status TEXT;
  v_new_converted_at TIMESTAMPTZ;
BEGIN
  IF p_primary_contact_id = p_secondary_contact_id THEN
    RAISE EXCEPTION 'MERGE_SELF_REJECTED: primary and secondary Contact ids are identical (%)', p_primary_contact_id;
  END IF;

  -- Deterministic lock ordering (smaller id first) to avoid deadlock
  -- against a concurrent merge naming the same pair in the opposite order.
  IF p_primary_contact_id < p_secondary_contact_id THEN
    v_lock_first := p_primary_contact_id; v_lock_second := p_secondary_contact_id;
  ELSE
    v_lock_first := p_secondary_contact_id; v_lock_second := p_primary_contact_id;
  END IF;

  PERFORM 1 FROM crm.contacts WHERE id = v_lock_first  AND organization_id = p_organization_id FOR UPDATE;
  PERFORM 1 FROM crm.contacts WHERE id = v_lock_second AND organization_id = p_organization_id FOR UPDATE;

  SELECT * INTO v_primary   FROM crm.contacts WHERE id = p_primary_contact_id   AND organization_id = p_organization_id;
  SELECT * INTO v_secondary FROM crm.contacts WHERE id = p_secondary_contact_id AND organization_id = p_organization_id;

  IF v_primary.id IS NULL THEN
    RAISE EXCEPTION 'MERGE_PRIMARY_NOT_FOUND: Contact % not found in organization %', p_primary_contact_id, p_organization_id;
  END IF;
  IF v_secondary.id IS NULL THEN
    RAISE EXCEPTION 'MERGE_SECONDARY_NOT_FOUND: Contact % not found in organization %', p_secondary_contact_id, p_organization_id;
  END IF;
  IF v_primary.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'MERGE_PRIMARY_ERASED: Contact % has been GDPR-erased and cannot be a merge primary', p_primary_contact_id;
  END IF;
  IF v_secondary.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'MERGE_SECONDARY_ERASED: Contact % has been GDPR-erased and cannot be a merge secondary', p_secondary_contact_id;
  END IF;
  IF v_primary.merged_into_contact_id IS NOT NULL THEN
    RAISE EXCEPTION 'MERGE_PRIMARY_ALREADY_MERGED: Contact % is already merged into % and cannot be a merge primary', p_primary_contact_id, v_primary.merged_into_contact_id;
  END IF;
  IF v_secondary.merged_into_contact_id IS NOT NULL THEN
    RAISE EXCEPTION 'MERGE_SECONDARY_ALREADY_MERGED: Contact % is already merged into % and cannot be merged again', p_secondary_contact_id, v_secondary.merged_into_contact_id;
  END IF;

  -- lead_status "further along" ranking — a documented interpretation of
  -- 4C §6.2's "further along the LeadStatus state machine" (4C does not
  -- itself give a numeric ranking; NURTURING/CONTACTED/DISQUALIFIED are
  -- treated as lateral to each other, not strictly ordered, per the
  -- non-linear shape of 4C §7.1's actual state diagram).
  v_primary_rank   := CASE v_primary.lead_status   WHEN 'CONVERTED' THEN 3 WHEN 'QUALIFIED' THEN 2
                            WHEN 'CONTACTED' THEN 1 WHEN 'NURTURING' THEN 1 WHEN 'DISQUALIFIED' THEN 1 ELSE 0 END;
  v_secondary_rank := CASE v_secondary.lead_status WHEN 'CONVERTED' THEN 3 WHEN 'QUALIFIED' THEN 2
                            WHEN 'CONTACTED' THEN 1 WHEN 'NURTURING' THEN 1 WHEN 'DISQUALIFIED' THEN 1 ELSE 0 END;
  IF v_secondary_rank > v_primary_rank THEN
    v_new_lead_status := v_secondary.lead_status;
    v_new_converted_at := CASE WHEN v_secondary.lead_status = 'CONVERTED' THEN v_secondary.converted_at ELSE v_primary.converted_at END;
  ELSE
    v_new_lead_status := v_primary.lead_status;
    v_new_converted_at := v_primary.converted_at;
  END IF;

  v_new_tags := ARRAY(SELECT DISTINCT unnest(v_primary.tags || v_secondary.tags));
  IF cardinality(v_new_tags) > 20 THEN
    RAISE EXCEPTION 'MERGE_TAG_CAP_EXCEEDED: merged tag set would have % tags, cap is 20', cardinality(v_new_tags);
  END IF;

  SELECT jsonb_agg(v ORDER BY v->>'field_id') INTO v_merged_cfv
  FROM (
    SELECT DISTINCT ON (elem->>'field_id') elem AS v
    FROM (
      SELECT jsonb_array_elements(v_primary.custom_field_values)   AS elem, 0 AS pri
      UNION ALL
      SELECT jsonb_array_elements(v_secondary.custom_field_values) AS elem, 1 AS pri
    ) combined
    ORDER BY elem->>'field_id', pri
  ) deduped;
  v_merged_cfv := COALESCE(v_merged_cfv, '[]'::JSONB);
  v_cfv_count := jsonb_array_length(v_merged_cfv);
  IF v_cfv_count > 50 THEN
    RAISE EXCEPTION 'MERGE_CUSTOM_FIELD_CAP_EXCEEDED: merged custom_field_values would have % entries, cap is 50', v_cfv_count;
  END IF;

  UPDATE crm.contacts
  SET company_id               = COALESCE(v_primary.company_id, v_secondary.company_id),
      owned_by                 = COALESCE(v_primary.owned_by, v_secondary.owned_by),
      secondary_phone_e164     = COALESCE(v_primary.secondary_phone_e164, v_secondary.secondary_phone_e164),
      primary_email            = COALESCE(v_primary.primary_email, v_secondary.primary_email),
      primary_email_normalized = COALESCE(v_primary.primary_email_normalized, v_secondary.primary_email_normalized),
      address_line1            = COALESCE(v_primary.address_line1, v_secondary.address_line1),
      address_line2            = COALESCE(v_primary.address_line2, v_secondary.address_line2),
      address_city             = COALESCE(v_primary.address_city, v_secondary.address_city),
      address_state            = COALESCE(v_primary.address_state, v_secondary.address_state),
      address_postal_code      = COALESCE(v_primary.address_postal_code, v_secondary.address_postal_code),
      address_country_code     = COALESCE(v_primary.address_country_code, v_secondary.address_country_code),
      qualification_reason     = COALESCE(v_primary.qualification_reason, v_secondary.qualification_reason),
      last_contacted_at        = GREATEST(v_primary.last_contacted_at, v_secondary.last_contacted_at),
      lead_status              = v_new_lead_status,
      converted_at             = v_new_converted_at,
      tags                     = v_new_tags,
      custom_field_values      = v_merged_cfv,
      updated_at               = NOW()
  WHERE id = p_primary_contact_id AND organization_id = p_organization_id;

  -- Re-point only the mutable child aggregates (real UPDATE grants exist
  -- on all four). crm.activities and crm.lead_score_records are
  -- deliberately NOT touched here — see 093_5D2.sql's header comment.
  UPDATE crm.deals SET contact_id = p_primary_contact_id, updated_at = NOW()
    WHERE contact_id = p_secondary_contact_id AND organization_id = p_organization_id;

  UPDATE crm.tasks SET subject_id = p_primary_contact_id, updated_at = NOW()
    WHERE subject_type = 'CONTACT' AND subject_id = p_secondary_contact_id AND organization_id = p_organization_id;

  UPDATE crm.notes SET subject_id = p_primary_contact_id, updated_at = NOW()
    WHERE subject_type = 'CONTACT' AND subject_id = p_secondary_contact_id AND organization_id = p_organization_id;

  UPDATE crm.appointments SET contact_id = p_primary_contact_id, updated_at = NOW()
    WHERE contact_id = p_secondary_contact_id AND organization_id = p_organization_id;

  -- Mark the secondary. trg_contacts_merge_tenant_guard and
  -- chk_contacts_no_self_merge / chk_contacts_merge_pair all fire on this
  -- statement too, as a second, independent layer of the same checks
  -- this function already performed above.
  UPDATE crm.contacts
  SET merged_into_contact_id = p_primary_contact_id,
      merged_at = NOW(),
      updated_at = NOW()
  WHERE id = p_secondary_contact_id AND organization_id = p_organization_id;

  -- Marker Activity on the survivor — this is how the merge becomes
  -- visible in the audit-grade timeline, since the secondary's own
  -- historical Activities are not (and cannot be) re-pointed.
  --
  -- PII-MINIMAL BY DESIGN (097_5D5 fix): this payload carries identifiers
  -- and provenance only — event name, both Contact ids, and the acting
  -- UserId. It NEVER carries the secondary's full_name, phone_e164,
  -- secondary_phone_e164, email, address, custom_field_values, or
  -- qualification_reason. crm.activities is append-only and survives
  -- Contact GDPR erasure (DDR-4C-002; erasure clears fields on
  -- crm.contacts only, 5D §5.1) — copying direct Contact PII into this
  -- payload would create a second, erasure-proof copy of exactly the
  -- data `DELETE /contacts/{id}` is supposed to clear. If a human-
  -- readable audit trail of *what* was merged is ever needed beyond these
  -- identifiers, it must be produced by re-reading the (still erasable)
  -- crm.contacts rows at query time, never by duplicating their PII into
  -- this immutable record.
  v_activity_id := public.gen_uuid_v7();
  INSERT INTO crm.activities (
    id, organization_id, occurred_at, activity_type, subject_type, subject_id,
    actor_type, actor_ref, summary, payload
  ) VALUES (
    v_activity_id, p_organization_id, NOW(), 'STAGE_CHANGE', 'CONTACT', p_primary_contact_id,
    'HUMAN', p_merged_by_ref, 'Contact merged',
    jsonb_build_object(
      'event', 'contact_merged',
      'primary_contact_id', p_primary_contact_id,
      'secondary_contact_id', p_secondary_contact_id,
      'merged_by', p_merged_by_ref
    )
  );

  -- Caller must publish contact.merged domain event after this function returns.
END;
$$;

REVOKE ALL ON FUNCTION crm.fn_merge_contacts(UUID, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.fn_merge_contacts(UUID, UUID, UUID, UUID)
  TO app_api, app_worker, app_platform_admin;
