-- =================================================================
-- Migration 098 (Phase 5E.1 — controlled amendment): campaign dispatch
--   concurrency-safety primitives
--   + campaign.campaign_contact_identities, campaign.fn_enqueue_contact()
--   + campaign.fn_reserve_dispatch()
-- down_revision: 097_5D5
-- Transaction: yes
-- Source: docs/phase-06-api-design/6H-Campaign-APIs.md Phase 6H Remediation
--   (2026-08-28) — Blocker #1 (DEP-6H-03, CampaignContact duplicate-enqueue
--   race) and Blocker #2 (durable Pause/Stop-vs-dispatch serialization).
--
-- REVISION NOTE (Final Remediation pass, same day): this file supersedes
-- the version first written earlier in this same reconciliation. It has
-- NOT been applied to any production database (disclosed explicitly in
-- both passes), so it is corrected in place here rather than superseded
-- by a new 100_5E2.sql — there is no "frozen, already-applied" version of
-- this file to preserve. The only change from the first pass is the
-- SECURITY DEFINER search_path fix in §A below; the table/function
-- purpose, invariants, and grants are otherwise unchanged.
--
-- =================================================================
-- §A. SECURITY DEFINER search_path — empirically verified fix
-- =================================================================
-- The first pass of this file used SET search_path = campaign,
-- organization, pg_catalog and called the platform's shared
-- gen_uuid_v7() unqualified. That is unsafe for two independent
-- reasons, both confirmed live against a disposable PostgreSQL 18
-- database before this fix was written (not assumed):
--   1. An unqualified gen_uuid_v7() call cannot resolve at all unless
--      `public` (where 001_5B.sql defines it) is in the search_path.
--   2. Schema-qualifying the call site alone (public.gen_uuid_v7()) is
--      NOT sufficient: gen_uuid_v7()'s own body calls gen_random_bytes()
--      (pgcrypto) unqualified, with no SET search_path of its own, so
--      it inherits the CALLER's search_path at execution time. A
--      restricted search_path lacking `public` on the caller makes
--      gen_uuid_v7() itself fail with "function gen_random_bytes(integer)
--      does not exist" even when the outer call is fully qualified —
--      live-reproduced before writing this fix.
-- Because gen_uuid_v7() is a frozen, existing platform function (001_5B.sql)
-- that this migration has no authority to edit, and because broadening
-- fn_enqueue_contact()/fn_reserve_dispatch()'s own search_path to include
-- `public` would apply that broadening to functions that also do
-- tenant-sensitive row locking and RLS-relevant reads, this migration
-- instead defines one small, single-purpose, fully-isolated bridge
-- function per the guidance to prefer explicit qualification and keep
-- the search_path of security/tenant-sensitive functions minimal:
-- campaign.fn_new_uuid_v7() is the ONLY function in this file that
-- includes `public` in its search_path, and it does nothing else.
-- =================================================================

CREATE OR REPLACE FUNCTION campaign.fn_new_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
  -- The only function in this migration permitted to see `public` —
  -- its sole purpose is bridging into the platform's shared UUIDv7
  -- generator (001_5B.sql), which itself depends unqualified on
  -- pgcrypto's gen_random_bytes(), also installed in `public`.
  RETURN public.gen_uuid_v7();
END;
$$;

REVOKE ALL ON FUNCTION campaign.fn_new_uuid_v7() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION campaign.fn_new_uuid_v7() TO app_worker;

-- -----------------------------------------------------------------
-- Blocker #1: durable, non-partitioned (campaign_id, contact_id) claim
-- -----------------------------------------------------------------

CREATE TABLE campaign.campaign_contact_identities (
  campaign_id          UUID        NOT NULL,
  contact_id           UUID        NOT NULL,
  organization_id      UUID        NOT NULL,
  campaign_contact_id  UUID        NOT NULL,
  imported_at          TIMESTAMPTZ NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaign_contact_identities PRIMARY KEY (campaign_id, contact_id)
);

COMMENT ON TABLE campaign.campaign_contact_identities IS
  'Durable, non-partitioned uniqueness guard for (campaign_id, contact_id). '
  'campaign.campaign_contacts is partitioned by imported_at, so PostgreSQL '
  'cannot enforce (campaign_id, contact_id) uniqueness directly on it. This '
  'table is the PK-backed atomic claim campaign.fn_enqueue_contact() uses '
  'before ever inserting into campaign_contacts, mirroring '
  'crm.event_consumer_dedup + crm.fn_claim_event() (094_5D3.sql). Added by '
  'Phase 6H Campaign remediation (098_5E1) to resolve DEP-6H-03 / 5L item #37.';

CREATE INDEX idx_cci_org ON campaign.campaign_contact_identities (organization_id);
CREATE INDEX idx_cci_campaign_contact_id ON campaign.campaign_contact_identities (campaign_contact_id);

ALTER TABLE campaign.campaign_contact_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaign_contact_identities FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cci_tenant ON campaign.campaign_contact_identities
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Only the materialization worker path ever writes this table directly, and
-- only through fn_enqueue_contact() below in practice; SELECT is also
-- granted directly for read-side reconciliation/diagnostics.
GRANT SELECT, INSERT ON campaign.campaign_contact_identities TO app_worker;
GRANT SELECT ON campaign.campaign_contact_identities TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON campaign.campaign_contact_identities TO app_platform_admin;

CREATE OR REPLACE FUNCTION campaign.fn_enqueue_contact(
  p_organization_id      UUID,
  p_campaign_id          UUID,
  p_contact_id           UUID,
  p_phone_e164           TEXT,
  p_max_attempts         INTEGER,
  p_is_dnc               BOOLEAN,
  p_status               TEXT,              -- 'PENDING' | 'DNC_SKIPPED' | 'INELIGIBLE'
  p_ineligibility_reason TEXT DEFAULT NULL
)
RETURNS TABLE(campaign_contact_id UUID, imported_at TIMESTAMPTZ, is_new BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = campaign, organization, pg_catalog
AS $$
DECLARE
  v_id     UUID        := campaign.fn_new_uuid_v7();
  v_now    TIMESTAMPTZ := NOW();
  v_claim  campaign.campaign_contact_identities%ROWTYPE;
  v_campaign_org UUID;
BEGIN
  IF p_status NOT IN ('PENDING','DNC_SKIPPED','INELIGIBLE') THEN
    RAISE EXCEPTION 'fn_enqueue_contact: invalid initial status %', p_status;
  END IF;

  -- Tenant-ownership guard (found missing by live cross-tenant testing during
  -- this remediation pass — this function originally trusted p_organization_id
  -- without ever confirming p_campaign_id actually belongs to it, unlike
  -- fn_reserve_dispatch()'s own campaigns-row lookup, which already had this
  -- check. Because this function is SECURITY DEFINER (owner bypasses RLS
  -- entirely, per 6G's own documented precedent for fn_merge_contacts()),
  -- RLS provides no defense-in-depth here at all — this explicit lookup is
  -- the ENTIRE tenant-isolation guarantee for this function, not merely one
  -- layer of several. A cross-tenant campaign_id resolves as a generic,
  -- non-disclosing exception — it never reveals whether the campaign exists
  -- under a different tenant.
  SELECT organization_id INTO v_campaign_org
  FROM campaign.campaigns WHERE id = p_campaign_id;

  IF v_campaign_org IS NULL OR v_campaign_org <> p_organization_id THEN
    RAISE EXCEPTION 'fn_enqueue_contact: campaign % not found for organization %', p_campaign_id, p_organization_id;
  END IF;

  INSERT INTO campaign.campaign_contact_identities
    (campaign_id, contact_id, organization_id, campaign_contact_id, imported_at)
  VALUES (p_campaign_id, p_contact_id, p_organization_id, v_id, v_now)
  ON CONFLICT (campaign_id, contact_id) DO NOTHING
  RETURNING * INTO v_claim;

  IF v_claim.campaign_contact_id IS NULL THEN
    -- Lost the claim: another transaction (a genuine concurrent race, or a
    -- redelivered/duplicate materialization batch item) already enqueued
    -- this Contact for this Campaign. Idempotent no-op: return the winner's
    -- identity so the caller can safely treat this as "already exists."
    SELECT * INTO v_claim
    FROM campaign.campaign_contact_identities
    WHERE campaign_id = p_campaign_id AND contact_id = p_contact_id;

    RETURN QUERY SELECT v_claim.campaign_contact_id, v_claim.imported_at, FALSE;
    RETURN;
  END IF;

  -- Won the claim: the actual campaign_contacts row is created in the SAME
  -- transaction, using the identity just reserved — the two can never
  -- diverge, by construction.
  INSERT INTO campaign.campaign_contacts (
    id, imported_at, organization_id, campaign_id, contact_id, phone_e164,
    status, max_attempts, is_dnc, ineligibility_reason
  ) VALUES (
    v_claim.campaign_contact_id, v_claim.imported_at, p_organization_id, p_campaign_id,
    p_contact_id, p_phone_e164, p_status, p_max_attempts, p_is_dnc, p_ineligibility_reason
  );

  RETURN QUERY SELECT v_claim.campaign_contact_id, v_claim.imported_at, TRUE;
END;
$$;

REVOKE ALL ON FUNCTION campaign.fn_enqueue_contact(UUID,UUID,UUID,TEXT,INTEGER,BOOLEAN,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION campaign.fn_enqueue_contact(UUID,UUID,UUID,TEXT,INTEGER,BOOLEAN,TEXT,TEXT) TO app_worker;

-- -----------------------------------------------------------------
-- Blocker #2: durable Campaign-status-vs-dispatch serialization
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION campaign.fn_reserve_dispatch(
  p_organization_id     UUID,
  p_campaign_id         UUID,
  p_campaign_contact_id UUID,
  p_imported_at         TIMESTAMPTZ,
  p_attempt_number      INTEGER,
  p_idempotency_key     CHAR(64),
  p_phone_e164          TEXT
)
RETURNS TABLE(reserved BOOLEAN, call_job_id UUID, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = campaign, organization, pg_catalog
AS $$
DECLARE
  v_campaign_status TEXT;
  v_contact_status  TEXT;
  v_next_attempt_at TIMESTAMPTZ;
  v_job_id          UUID := campaign.fn_new_uuid_v7();
  v_inserted_id     UUID;
BEGIN
  -- Deterministic lock order: campaigns row, then campaign_contacts row.
  -- No other code path in this schema locks campaign_contacts before
  -- campaigns, so this ordering cannot deadlock against itself or against
  -- PauseCampaign/StopCampaign/ResumeCampaign/CancelCampaign/
  -- UpdateCampaignConfig, all of which touch only the campaigns row.
  SELECT status INTO v_campaign_status
  FROM campaign.campaigns
  WHERE id = p_campaign_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF v_campaign_status IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'CAMPAIGN_NOT_FOUND'::TEXT;
    RETURN;
  END IF;

  IF v_campaign_status <> 'RUNNING' THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'CAMPAIGN_NOT_RUNNING'::TEXT;
    RETURN;
  END IF;

  -- Also found by live cross-tenant/cross-campaign testing during this
  -- remediation pass: the campaign_id = p_campaign_id predicate below is
  -- required, not merely defensive. Without it, a caller could pass a
  -- syntactically-valid but MISMATCHED (p_campaign_id, p_campaign_contact_id)
  -- pair — a real CampaignContact belonging to a *different* campaign in the
  -- same organization — and this function would still lock and dispatch it,
  -- creating a call_jobs row whose own campaign_id disagrees with the
  -- CampaignContact it actually references, corrupting that other campaign's
  -- own completion-check/progress queries (which filter by campaign_id).
  SELECT status, next_attempt_at INTO v_contact_status, v_next_attempt_at
  FROM campaign.campaign_contacts
  WHERE id = p_campaign_contact_id AND imported_at = p_imported_at
    AND organization_id = p_organization_id
    AND campaign_id = p_campaign_id
  FOR UPDATE;

  IF v_contact_status IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'CONTACT_NOT_FOUND'::TEXT;
    RETURN;
  END IF;

  IF v_contact_status NOT IN ('PENDING','RETRY_SCHEDULED') THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'CONTACT_NOT_DISPATCHABLE'::TEXT;
    RETURN;
  END IF;

  IF v_contact_status = 'RETRY_SCHEDULED' AND v_next_attempt_at IS NOT NULL AND v_next_attempt_at > NOW() THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'RETRY_NOT_YET_DUE'::TEXT;
    RETURN;
  END IF;

  INSERT INTO campaign.call_jobs (
    id, organization_id, campaign_id, campaign_contact_id, phone_e164,
    attempt_number, idempotency_key, status
  ) VALUES (
    v_job_id, p_organization_id, p_campaign_id, p_campaign_contact_id, p_phone_e164,
    p_attempt_number, p_idempotency_key, 'PENDING'
  )
  ON CONFLICT (idempotency_key) WHERE status IN ('PENDING','DISPATCHED') DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'DUPLICATE_ATTEMPT'::TEXT;
    RETURN;
  END IF;

  UPDATE campaign.campaign_contacts
  SET status = 'CALLING', updated_at = NOW()
  WHERE id = p_campaign_contact_id AND imported_at = p_imported_at
    AND organization_id = p_organization_id
    AND campaign_id = p_campaign_id
    AND status IN ('PENDING','RETRY_SCHEDULED');

  RETURN QUERY SELECT TRUE, v_inserted_id, NULL::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION campaign.fn_reserve_dispatch(UUID,UUID,UUID,TIMESTAMPTZ,INTEGER,CHAR(64),TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION campaign.fn_reserve_dispatch(UUID,UUID,UUID,TIMESTAMPTZ,INTEGER,CHAR(64),TEXT) TO app_worker;

-- Note on lock duration: fn_reserve_dispatch() performs pure-SQL work only —
-- no in-process CRM eligibility call, no Redis round trip, no network call of
-- any kind is made while its row locks are held. Dispatch-time eligibility
-- (CRM suppression/consent, 6H §17) is evaluated BEFORE this function is
-- invoked, as ordinary lock-free reads; this function's sole job is the
-- final, authoritative, lock-protected reservation against Campaign status
-- and CampaignContact status. This keeps lock hold time bounded to a single
-- short OLTP transaction (sub-few-milliseconds), consistent with 6A §13's
-- transaction-scope discipline.
