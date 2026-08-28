-- =================================================================
-- Migration 095 (Phase 5D.4): crm.fn_apply_lead_score() — CAS-safe
--   denormalized score/temperature apply (fixes out-of-order overwrite)
-- down_revision: 094_5D3
-- Transaction: yes
-- Source: Phase 6G CRM Reconciliation (2026-08-28), lead-score ordering fix
--
-- WHY THIS EXISTS
-- ----------------
-- 6G's first pass accepted, as a documented risk, that a slow-to-arrive
-- scoring computation could finish after a newer one and overwrite
-- contacts.lead_score/lead_temperature with a stale value ("last write
-- wins on the denormalized field"). The governing task requires this be
-- fixed rather than accepted.
--
-- NO NEW COLUMN IS ADDED. crm.lead_score_records already carries
-- computed_at (and, being a UUIDv7 table, each row's own id is itself
-- monotonically time-ordered with no possibility of a true tie — see
-- 5A §8.1) — that is sufficient to determine "is the row I just inserted
-- still the newest one for this Contact" without any new schema. The
-- safe ordering this migration implements:
--
--   BEGIN;
--     INSERT INTO crm.lead_score_records (...) RETURNING id INTO v_my_id;
--     -- lock the Contact row so a concurrent apply for the SAME contact
--     -- must wait here, not race past this point:
--     SELECT ... FROM crm.contacts WHERE id = $1 FOR UPDATE;
--     -- now, with that lock held, find the true latest row across BOTH
--     -- this and any concurrently-committed sibling computation:
--     SELECT id FROM crm.lead_score_records WHERE contact_id = $1
--       ORDER BY computed_at DESC, id DESC LIMIT 1;
--     IF that id = v_my_id THEN
--       UPDATE crm.contacts SET lead_score = ..., lead_temperature = ...;
--     END IF;
--   COMMIT;
--
-- The FOR UPDATE lock on the Contact row (not a new column, not a
-- broader locking scheme, not SELECT ... FOR UPDATE on lead_score_records
-- itself — which would not help, since Postgres row locks never block a
-- concurrent INSERT of a brand-new row) is exactly the "narrow Contact-
-- row lock" the governing task explicitly allows for this one real
-- ordering invariant. It serializes concurrent scoring transactions for
-- the SAME Contact only; different Contacts are never contended against
-- each other. Ties in computed_at (two computations landing in the same
-- microsecond) are broken deterministically by the row's own id, which
-- can never be equal for two different rows — there is no ambiguous case.
--
-- lead_score_records itself remains append-only and untouched by this
-- migration: REVOKE UPDATE, DELETE from 023_5D.sql stands. This function
-- INSERTs into it (a privilege app_worker already holds) and otherwise
-- only ever reads it.
-- =================================================================

CREATE OR REPLACE FUNCTION crm.fn_apply_lead_score(
  p_contact_id           UUID,
  p_organization_id      UUID,
  p_score                INTEGER,
  p_previous_score       INTEGER,
  p_score_version        TEXT,
  p_signals              JSONB,
  p_computed_at          TIMESTAMPTZ,
  p_computed_by          TEXT,
  p_computed_by_user_ref UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = crm, public, pg_catalog
-- 'public' is required, not optional — see 093_5D2.sql's identical note
-- on crm.fn_merge_contacts: this function's INSERT below relies on
-- crm.lead_score_records.id's DEFAULT public.gen_uuid_v7(), which itself
-- calls public.gen_random_bytes() (pgcrypto). Generated explicitly as
-- v_my_id below (belt-and-braces), matching audit.fn_insert_audit_event's
-- established convention exactly.
AS $$
DECLARE
  v_my_id      UUID := public.gen_uuid_v7();
  v_latest_id  UUID;
  v_temperature TEXT;
BEGIN
  INSERT INTO crm.lead_score_records (
    id, organization_id, contact_id, score, previous_score, score_version,
    signals, computed_at, computed_by, computed_by_user_ref
  ) VALUES (
    v_my_id, p_organization_id, p_contact_id, p_score, p_previous_score, p_score_version,
    p_signals, p_computed_at, p_computed_by, p_computed_by_user_ref
  );

  -- Lock the Contact row: any concurrent fn_apply_lead_score() call for
  -- this same Contact now serializes behind this transaction.
  PERFORM 1 FROM crm.contacts WHERE id = p_contact_id AND organization_id = p_organization_id FOR UPDATE;

  SELECT id INTO v_latest_id
  FROM crm.lead_score_records
  WHERE contact_id = p_contact_id AND organization_id = p_organization_id
  ORDER BY computed_at DESC, id DESC
  LIMIT 1;

  IF v_latest_id IS DISTINCT FROM v_my_id THEN
    -- A newer computation is already the latest for this Contact — this
    -- call's own row remains in the immutable history (never deleted or
    -- rewritten), but it must not overwrite a newer denormalized value.
    RETURN FALSE;
  END IF;

  v_temperature := CASE
    WHEN p_score >= 70 THEN 'HOT'
    WHEN p_score >= 40 THEN 'WARM'
    WHEN p_score >= 0  THEN 'COLD'
    ELSE NULL
  END;

  UPDATE crm.contacts
  SET lead_score = p_score,
      lead_temperature = v_temperature,
      updated_at = NOW()
  WHERE id = p_contact_id AND organization_id = p_organization_id;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION crm.fn_apply_lead_score(UUID, UUID, INTEGER, INTEGER, TEXT, JSONB, TIMESTAMPTZ, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.fn_apply_lead_score(UUID, UUID, INTEGER, INTEGER, TEXT, JSONB, TIMESTAMPTZ, TEXT, UUID)
  TO app_worker, app_platform_admin;
