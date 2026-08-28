-- =================================================================
-- Migration 093 (Phase 5D.2): Contact merge-lineage support +
--   crm.fn_merge_contacts() guarded merge primitive
-- down_revision: 092_5F12
-- Transaction: yes
-- Source: Phase 6G CRM Reconciliation (2026-08-28), Blockers A/B/C-partial
--
-- WHY THIS EXISTS
-- ----------------
-- 6G's first pass represented a merged-away Contact by setting
-- `deleted_at = NOW()` — reusing the GDPR-erasure tombstone mechanism.
-- That is semantically wrong: `deleted_at` in this schema means
-- "PII has been cleared / this row is a GDPR tombstone" (5D §5.1,
-- ADR-5D-007). 4C §6.2 describes MergeContacts producing a distinct
-- terminal identity state ("secondary is then set to ContactStatus.MERGED,
-- a terminal status distinct from ACTIVE or CONVERTED") that has nothing
-- to do with data erasure — a merged contact's PII is NOT cleared, it is
-- folded into the survivor. Conflating the two would make a merged
-- contact's phone number silently eligible for the GDPR partial-unique-
-- index re-registration path (`uq_contacts_phone ... WHERE deleted_at IS
-- NULL`), which is correct for real erasure but wrong for merge (a merged
-- number should stay associated with its lineage, not be treated as if
-- the person requested erasure).
--
-- This migration adds two nullable columns instead:
--   merged_into_contact_id UUID NULL  -- the surviving Contact's id
--   merged_at              TIMESTAMPTZ NULL
-- both NULL on every normal Contact, both NOT NULL together exactly once
-- a Contact has been merged away, never independently.
--
-- MERGE-LINEAGE INVARIANTS ENFORCED HERE (defense in depth: constraint +
-- trigger + function, matching this schema's existing pattern of stacking
-- guards rather than relying on any single layer):
--   1. Both-or-neither (chk_contacts_merge_pair).
--   2. No self-merge (chk_contacts_no_self_merge).
--   3. merged_into_contact_id must reference an existing crm.contacts row
--      (fk_contacts_merged_into) — self-referential FK, safe here because
--      this is the same aggregate type pointing at another instance of
--      itself, not a cross-aggregate reference (5D §12's aggregate-
--      independence rule governs Contact->Company/Deal->Contact style
--      references; it does not forbid a same-table identity pointer).
--   4. Cross-tenant merge destination is rejected at the trigger level
--      (trg_contacts_merge_tenant_guard) — a CHECK constraint cannot see
--      other rows, so this needs a trigger, not just a CHECK.
--   5. Merge lineage is immutable once recorded — a second attempt to
--      change merged_into_contact_id/merged_at on an already-merged row
--      is rejected by trg_contacts_merge_immutable. Combined with rule 6
--      below (fn_merge_contacts refuses to use an already-merged contact
--      as EITHER primary or secondary of a new merge), this makes a
--      merge cycle structurally impossible: the only way a cycle could
--      form is if some contact X, already merged into Y, were later
--      accepted as the *target* of a further merge — but X is
--      permanently barred from being chosen as primary (fn_merge_contacts
--      rejects "primary already merged"), so X can never receive a new
--      merged_into_contact_id pointing elsewhere, and it can never be
--      re-pointed by direct SQL either (trigger). Multi-hop lineage
--      (A merged into B, B later merged into C) is still possible and
--      intentionally supported — B is a normal, non-merged Contact right
--      up until the moment it itself becomes a secondary, so it may
--      accumulate its own secondaries (A) before then. Readers that need
--      "the current, non-merged survivor for a given Contact id" must
--      walk the merged_into_contact_id chain to its end (see 6G §10 for
--      the exact read pattern) — this migration deliberately does not
--      rewrite A's merged_into_contact_id when B later merges into C,
--      because that would itself be a mutation of an already-merged row,
--      which rule 5 forbids for the same audit-integrity reason 4C
--      requires for every other append-style history in this schema.
--   6. `fn_merge_contacts` additionally rejects: primary == secondary,
--      cross-tenant pair, either side already GDPR-erased
--      (deleted_at IS NOT NULL), either side already merged away
--      (merged_into_contact_id IS NOT NULL) — this last check is what
--      makes rule 5's cycle-freedom argument hold.
--
-- WHAT IS DELIBERATELY NOT DONE HERE
-- -----------------------------------
-- No blanket "reject any UPDATE on an already-merged Contact" trigger is
-- added. 4C's MERGED state is terminal for ordinary CRM editing, and the
-- API layer (6G) enforces that by refusing PATCH on a Contact whose
-- merged_into_contact_id is set — but GDPR erasure is a compliance-
-- mandated right that must remain available on ANY Contact row regardless
-- of merge status (a data subject's erasure request does not stop
-- applying because a CRM operator merged their record). A field-allowlist
-- trigger that tried to distinguish "erasure fields" from "ordinary
-- fields" would be fragile (full_name/phone_e164/address_* are both
-- ordinarily-editable AND part of the erasure field-set) and would
-- duplicate logic the application layer already owns. This mirrors the
-- schema's own existing precedent for `lead_temperature` (5D §5.1):
-- "derivation logic is enforced at the application domain service layer,
-- not by a database trigger" when a DB trigger would be overly rigid.
--
-- fn_merge_contacts() re-points only the mutable child aggregates that
-- already hold real UPDATE grants (crm.deals, crm.tasks, crm.notes,
-- crm.appointments). It never touches crm.activities or
-- crm.lead_score_records — both are REVOKE UPDATE, DELETE for
-- app_api/app_worker (022_5D.sql, 023_5D.sql) and this migration does
-- NOT restore that privilege (explicit instruction: do not broadly
-- restore UPDATE/DELETE on append-only tables). Those two histories stay
-- physically attached to the Contact id under which they were originally
-- recorded; the surviving Contact's read-side timeline/score-history
-- must follow merge lineage to include them (6G §10/§14, application-
-- layer UNION across the lineage chain, not a database rewrite).
--
-- fn_merge_contacts() is SECURITY DEFINER per the governing task's
-- explicit request, but — unlike crm.lift_suppression() — this is NOT
-- required for privilege elevation: app_api/app_worker already hold
-- UPDATE on crm.contacts/deals/tasks/notes/appointments and INSERT on
-- crm.activities (the only tables this function writes). SECURITY
-- DEFINER is chosen here for centralized invariant enforcement and
-- transactional atomicity of a multi-table operation — a single,
-- narrowly-scoped, well-tested code path every merge goes through,
-- rather than trusting the application layer to compose five statements
-- in the right order under the right locks every time. The same
-- hardening discipline as every other SECURITY DEFINER function in this
-- schema still applies: explicit safe search_path, REVOKE ALL FROM
-- PUBLIC, explicit GRANT EXECUTE only to the roles that need it. Because
-- FORCE ROW LEVEL SECURITY is set on every table this function touches,
-- RLS does not implicitly scope any statement inside a SECURITY DEFINER
-- function whose owning role holds BYPASSRLS (the same situation
-- crm.lift_suppression() and the outbox claim functions already operate
-- under) — every statement below therefore filters explicitly by
-- organization_id = p_organization_id, exactly like
-- crm.lift_suppression() already does, rather than relying on RLS.
-- =================================================================

ALTER TABLE crm.contacts
  ADD COLUMN merged_into_contact_id UUID NULL,
  ADD COLUMN merged_at              TIMESTAMPTZ NULL;

COMMENT ON COLUMN crm.contacts.merged_into_contact_id IS
  'Set exactly once, by crm.fn_merge_contacts(), when this Contact is merged away into a survivor. Distinct from deleted_at (GDPR erasure) — a merged Contact''s PII is not cleared, it is folded into the survivor. NULL on every non-merged Contact.';
COMMENT ON COLUMN crm.contacts.merged_at IS
  'Set together with merged_into_contact_id, never independently (chk_contacts_merge_pair).';

ALTER TABLE crm.contacts
  ADD CONSTRAINT fk_contacts_merged_into
    FOREIGN KEY (merged_into_contact_id) REFERENCES crm.contacts(id),
  ADD CONSTRAINT chk_contacts_merge_pair
    CHECK ((merged_into_contact_id IS NULL) = (merged_at IS NULL)),
  ADD CONSTRAINT chk_contacts_no_self_merge
    CHECK (merged_into_contact_id IS DISTINCT FROM id);

CREATE INDEX idx_contacts_merged_into
  ON crm.contacts (organization_id, merged_into_contact_id)
  WHERE merged_into_contact_id IS NOT NULL;

-- ---------------------------------------------------------------
-- Trigger 1: cross-tenant merge destination guard. A CHECK constraint
-- cannot see another row's organization_id, so this must be a trigger.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.prevent_cross_tenant_merge()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = crm, pg_catalog AS $$
DECLARE
  v_target_org UUID;
BEGIN
  IF NEW.merged_into_contact_id IS NOT NULL THEN
    SELECT organization_id INTO v_target_org
    FROM crm.contacts WHERE id = NEW.merged_into_contact_id;
    IF v_target_org IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'crm.contacts: merged_into_contact_id % belongs to a different organization than % (Contact %)',
        NEW.merged_into_contact_id, NEW.organization_id, NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION crm.prevent_cross_tenant_merge() FROM PUBLIC;

CREATE TRIGGER trg_contacts_merge_tenant_guard
  BEFORE INSERT OR UPDATE OF merged_into_contact_id ON crm.contacts
  FOR EACH ROW EXECUTE FUNCTION crm.prevent_cross_tenant_merge();

-- ---------------------------------------------------------------
-- Trigger 2: merge lineage is immutable once recorded. Blocks any direct
-- SQL attempt to change or clear merged_into_contact_id/merged_at after
-- they have been set — the only way to enter the merged state is via
-- fn_merge_contacts(), and once entered it cannot be re-pointed or
-- reversed by an ordinary UPDATE. This is what makes the cycle-freedom
-- argument in this file's header comment hold.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.prevent_remerge()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = crm, pg_catalog AS $$
BEGIN
  IF OLD.merged_into_contact_id IS NOT NULL
     AND (NEW.merged_into_contact_id IS DISTINCT FROM OLD.merged_into_contact_id
          OR NEW.merged_at IS DISTINCT FROM OLD.merged_at) THEN
    RAISE EXCEPTION 'crm.contacts: Contact % is already merged into % at % — merge lineage is immutable once recorded',
      OLD.id, OLD.merged_into_contact_id, OLD.merged_at;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION crm.prevent_remerge() FROM PUBLIC;

CREATE TRIGGER trg_contacts_merge_immutable
  BEFORE UPDATE OF merged_into_contact_id, merged_at ON crm.contacts
  FOR EACH ROW EXECUTE FUNCTION crm.prevent_remerge();

-- ---------------------------------------------------------------
-- crm.fn_merge_contacts(): the sole guarded merge write path.
-- ---------------------------------------------------------------
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
-- (pgcrypto, installed into 'public' per 001_5B.sql). A SECURITY DEFINER
-- function's SET search_path applies to everything it calls, including a
-- column-default expression evaluated during its own INSERT — omitting
-- 'public' here reproduces the exact class of defect already documented
-- in 5K/execution_logs/README.md's "New finding" section for
-- analytics.fn_claim_projection_slot (068_5J.sql), and is exactly why
-- audit.fn_insert_audit_event (072_5J.sql) explicitly includes 'public'
-- in its own SET search_path and additionally generates its id via a
-- local variable rather than relying on the column default (mirrored
-- below with v_activity_id, belt-and-braces, not either/or).
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
  -- deliberately NOT touched here — see this file's header comment.
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
  v_activity_id := public.gen_uuid_v7();
  INSERT INTO crm.activities (
    id, organization_id, occurred_at, activity_type, subject_type, subject_id,
    actor_type, actor_ref, summary, payload
  ) VALUES (
    v_activity_id, p_organization_id, NOW(), 'STAGE_CHANGE', 'CONTACT', p_primary_contact_id,
    'HUMAN', p_merged_by_ref, 'Contact merged',
    jsonb_build_object(
      'event', 'contact_merged',
      'secondary_contact_id', p_secondary_contact_id,
      'secondary_full_name', v_secondary.full_name,
      'secondary_phone_e164', v_secondary.phone_e164,
      'merged_by', p_merged_by_ref
    )
  );

  -- Caller must publish contact.merged domain event after this function returns.
END;
$$;

REVOKE ALL ON FUNCTION crm.fn_merge_contacts(UUID, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.fn_merge_contacts(UUID, UUID, UUID, UUID)
  TO app_api, app_worker, app_platform_admin;
