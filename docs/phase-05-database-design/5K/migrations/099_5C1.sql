-- =================================================================
-- Migration 099 (Phase 5C.1 — controlled amendment): in-process outbound
--   call dispatch idempotency AND provider-dispatch durability
--   + voice.call_dispatch_keys (extended, provider-submission-boundary
--     state machine), voice.fn_initiate_outbound_call_idempotent()
--   + voice.fn_claim_dispatch_for_provider_submission()
--   + voice.fn_begin_provider_submission()
--   + voice.fn_record_dispatch_confirmed()
--   + voice.fn_record_dispatch_ambiguous()
--   + voice.fn_record_dispatch_failed()
--   + voice.fn_reconcile_dispatch_outcome()
-- down_revision: 098_5E1
-- Transaction: yes
-- Source: docs/phase-06-api-design/6H-Campaign-APIs.md Phase 6H Remediation
--   (2026-08-28) — Blocker #3 (Campaign -> Voice in-process dispatch
--   idempotency gap), extended by the Final Remediation pass (same day)
--   with Blocker C (crash-before-provider-submission durability hole) and
--   the SECURITY DEFINER search_path fix (§A), and extended again by the
--   Final Blocker Remediation pass (same day, third pass) with Blocker A
--   (expired-CLAIMED-lease double-dial hazard), Blocker C-of-that-pass
--   (direct-INSERT privilege bypass), and Blocker D (idempotency replay
--   tenant/payload validation) — see §D/§E/§F below.
--
-- REVISION NOTE: this file supersedes the version first written earlier in
-- this same reconciliation, twice now. It has NOT been applied to any
-- production database (disclosed explicitly in every pass), so it is
-- corrected in place here rather than superseded by a new 100_5C2.sql —
-- there is no "frozen, already-applied" version of this file to preserve.
--
-- SCOPE DISCIPLINE:
--   This remains a CONTROLLED, ADDITIVE AMENDMENT to the `voice` schema.
--   It adds one new table (extended across three passes now), eight
--   functions, all inside `voice`. voice.call_sessions itself is still
--   untouched — no column is added to it, no existing row shape changes.
--   `campaign_lead_ref` (existing, nullable, 011_5C.sql) is still reused
--   for Campaign correlation unchanged.
--
-- =================================================================
-- §A. SECURITY DEFINER search_path — empirically verified fix
--     (identical reasoning and fix pattern as 098_5E1.sql §A; unchanged by
--     this pass)
-- =================================================================

CREATE OR REPLACE FUNCTION voice.fn_new_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
  -- The only function in this migration permitted to see `public` — see
  -- 098_5E1.sql §A for the live-verified reasoning (gen_uuid_v7()'s own
  -- unqualified, SET-search_path-less call to gen_random_bytes() requires
  -- `public` to be reachable at the point it executes; qualifying only the
  -- outer call site is not sufficient, confirmed empirically).
  RETURN public.gen_uuid_v7();
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_new_uuid_v7() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_new_uuid_v7() TO app_api, app_worker;

-- =================================================================
-- §B. voice.call_dispatch_keys — provider-submission-boundary state
--     machine (Blocker C, first found; Blocker A, this pass, closed)
-- =================================================================
--
-- WHY THE FIRST PASS (Blocker C fix) WAS STILL INSUFFICIENT (Blocker A,
-- found by this pass's own adversarial final review, not by this
-- migration's own author claiming success):
--
--   The Blocker-C design distinguished RESERVED / CLAIMED / CONFIRMED /
--   AMBIGUOUS / FAILED, and treated a stale (lease-expired) CLAIMED row as
--   always safely re-claimable, on the reasoning that "a worker crash
--   between claiming and actually issuing the network call is
--   indistinguishable, from the database's point of view, from a crash
--   during the network call." That reasoning was WRONG for one specific
--   window: CLAIMED covered the *entire* span from "worker acquired the
--   lease" through "provider definitely responded", including the moment
--   the worker actually calls TelephonyPort.place_call(). A worker that
--   crashes AFTER the provider received and possibly accepted the request,
--   but BEFORE it could write anything back to the database, leaves a
--   CLAIMED row whose lease will eventually expire — and the Blocker-C
--   design would let a second worker reclaim it and call the provider
--   AGAIN, physically dialing the customer twice. This is exactly the
--   scenario the Final Blocker Remediation review named:
--
--     Worker A claims -> place_call() begins -> provider accepts ->
--     Worker A crashes -> DB still says CLAIMED -> lease expires ->
--     Worker B reclaims -> Worker B calls the provider again ->
--     the customer may receive a second physical call.
--
--   THE FIX: split what was one state (CLAIMED) into two, with a durable
--   commit boundary between them that happens strictly BEFORE the network
--   call is ever made:
--
--     RESERVED   -- logical call reserved; provider submission has
--                   definitely NOT been attempted; local prep work (if
--                   any) may still be in progress. Safe to (re)claim.
--     CLAIMED    -- exactly one worker owns the right to PREPARE a
--                   provider submission, under a time-bounded lease. The
--                   worker has NOT yet told the database it is about to
--                   call the provider. A crash here (or an expired lease
--                   with no further evidence) is provably pre-network —
--                   safe to (re)claim, because voice.fn_begin_provider_
--                   submission() below is the ONLY way a row ever leaves
--                   CLAIMED for SUBMITTING, and that transition commits to
--                   the database strictly BEFORE TelephonyPort.place_call()
--                   is ever invoked, in the caller's own contract.
--     SUBMITTING -- the durable "external submission may now begin"
--                   boundary (Final Blocker Remediation §4). Once this
--                   commits, the platform can no longer prove the provider
--                   was never contacted, so this state is NEVER
--                   automatically reclaimed for a fresh attempt, no matter
--                   how stale claim_expires_at becomes. This is the entire
--                   fix for Blocker A: fn_claim_dispatch_for_provider_
--                   submission()'s reclaim predicate below excludes
--                   SUBMITTING unconditionally.
--     CONFIRMED  -- the provider definitely accepted the request
--                   (provider_call_ref recorded). Reached only from
--                   SUBMITTING.
--     AMBIGUOUS  -- the provider submission's outcome could not be
--                   determined (network error/timeout on the response
--                   leg, or a crash after SUBMITTING committed with no
--                   further evidence ever recorded). Reached only from
--                   SUBMITTING. MUST NOT be blindly retried — closed by
--                   voice.fn_reconcile_dispatch_outcome() below, an
--                   identity-correlated (not lease-owner-correlated)
--                   resolution path for a delayed provider callback or a
--                   bounded operator/provider-lookup decision.
--     FAILED     -- the provider DEFINITELY rejected the request before
--                   any chance of it having been accepted (a synchronous
--                   pre-acceptance error), OR a local pre-submission
--                   failure discovered while still CLAIMED (never reached
--                   the provider at all). Reached from CLAIMED (local
--                   abort) or SUBMITTING (definite provider rejection).
--                   Safe to retry.
--
--   The one residual sliver this migration still cannot close alone: a
--   crash strictly between SUBMITTING's COMMIT and the process actually
--   transmitting the request on the wire (Case B, Final Blocker
--   Remediation §5) is indistinguishable, from the database's point of
--   view, from a crash during the provider's own processing of an
--   already-sent request (Case C). This design treats BOTH conservatively
--   as "may have started" — SUBMITTING is never auto-reclaimed either
--   way, which is the only sound choice, since the alternative (assuming
--   Case B and auto-retrying) risks the double-dial this entire pass
--   exists to close. Closing this sliver with certainty requires either
--   (a) a provider-native idempotency key honoured by the provider itself
--   on retry (not documented for Exotel in 3B/6D — see §F below, not
--   assumed here), or (b) a provider-side reference echoed back on every
--   callback so a bounded reconciliation window can positively confirm or
--   rule out the call was ever placed. This migration implements the
--   DB-side half of (b): provider_request_ref is now a stable, immutable,
--   platform-generated value fixed at reservation time (never regenerated
--   per attempt — INV-VOICE-DISPATCH-06), and fn_reconcile_dispatch_
--   outcome() gives a genuine, tested resolution path from SUBMITTING or
--   AMBIGUOUS. The dependency on the provider-adapter layer actually
--   supporting reference echo-back is documented, not assumed — see 6D
--   §28.10a and 6H §18.4.
-- =================================================================

-- Base table (this migration is the only place voice.call_dispatch_keys is
-- ever created — there is no separately-applied earlier pass of
-- 099_5C1.sql in any real environment, since it has never been applied to
-- production; the CREATE TABLE and every state-machine revision below are
-- one migration).
CREATE TABLE voice.call_dispatch_keys (
  dispatch_idempotency_key CHAR(64)    NOT NULL,
  organization_id          UUID        NOT NULL,
  call_session_id          UUID        NOT NULL,
  started_at               TIMESTAMPTZ NOT NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Blocker D (idempotency replay payload validation): a canonical
  -- SHA-256 fingerprint of the immutable request fields, computed inside
  -- fn_initiate_outbound_call_idempotent() itself (never trusted as a
  -- caller-supplied value) — see §D below for the exact canonical format.
  payload_fingerprint CHAR(64) NOT NULL,

  -- INV-VOICE-DISPATCH-06: fixed, immutable, platform-generated at
  -- reservation time — the same value is propagated to the provider on
  -- EVERY attempt (first attempt or any retry), never regenerated per
  -- claim. No function in this migration ever UPDATEs this column.
  provider_request_ref TEXT NOT NULL,

  dispatch_state         TEXT        NOT NULL DEFAULT 'RESERVED',
  claimed_by              TEXT        NULL,
  claimed_at               TIMESTAMPTZ NULL,
  claim_expires_at         TIMESTAMPTZ NULL,
  attempt_count            INTEGER     NOT NULL DEFAULT 0,
  submission_started_at    TIMESTAMPTZ NULL,
  provider_call_ref        TEXT        NULL,
  confirmed_at             TIMESTAMPTZ NULL,
  last_error               TEXT        NULL,
  reconciled_by            TEXT        NULL,
  reconciled_at            TIMESTAMPTZ NULL,

  CONSTRAINT pk_call_dispatch_keys PRIMARY KEY (dispatch_idempotency_key),
  CONSTRAINT chk_cdk_dispatch_state
    CHECK (dispatch_state IN ('RESERVED','CLAIMED','SUBMITTING','CONFIRMED','AMBIGUOUS','FAILED')),
  CONSTRAINT chk_cdk_attempt_count_nn CHECK (attempt_count >= 0),
  CONSTRAINT chk_cdk_confirmed_has_ref
    CHECK (dispatch_state <> 'CONFIRMED' OR provider_call_ref IS NOT NULL),
  CONSTRAINT chk_cdk_claimed_has_lease
    CHECK (dispatch_state NOT IN ('CLAIMED','SUBMITTING')
           OR (claimed_by IS NOT NULL AND claim_expires_at IS NOT NULL)),
  CONSTRAINT chk_cdk_submitting_has_marker
    CHECK (dispatch_state <> 'SUBMITTING' OR submission_started_at IS NOT NULL)
);

COMMENT ON COLUMN voice.call_dispatch_keys.dispatch_state IS
  'Provider-dispatch attempt state machine: RESERVED -> CLAIMED -> SUBMITTING '
  '-> CONFIRMED | AMBIGUOUS | FAILED (FAILED also reachable directly from '
  'CLAIMED for a pre-submission local abort). Independent of voice.call_sessions'
  '.status (the call''s own conversational/telephony lifecycle, unchanged, '
  'owned by 6D). SUBMITTING and AMBIGUOUS are both hard stops for automatic '
  'retry -- reconciliation-only (voice.fn_reconcile_dispatch_outcome). This is '
  'the Blocker-A fix: an expired lease on a CLAIMED row is safe to reclaim '
  '(no evidence the provider was ever contacted); an expired lease on a '
  'SUBMITTING row is NEVER auto-reclaimed, because the provider may already '
  'have been contacted.';
COMMENT ON COLUMN voice.call_dispatch_keys.payload_fingerprint IS
  'SHA-256 hex of the canonical, versioned JSON representation of the '
  'immutable request fields (organization_id, campaign_lead_ref, to_number, '
  'from_number, agent_version_id, tenant_phone_number_id), computed by '
  'fn_initiate_outbound_call_idempotent() itself -- never accepted as a '
  'caller-supplied value. A replay with the same dispatch_idempotency_key but '
  'a different fingerprint is rejected as IDEMPOTENCY_KEY_REUSE_MISMATCH '
  'rather than silently returning the original call (Blocker D).';
COMMENT ON COLUMN voice.call_dispatch_keys.provider_request_ref IS
  'Stable, immutable, platform-generated reference propagated to the '
  'telephony provider on every submission attempt for this dispatch key '
  '(INV-VOICE-DISPATCH-06) -- enables reconciliation of a SUBMITTING/'
  'AMBIGUOUS attempt via provider callback correlation without relying on '
  'provider-native idempotency. Whether the active provider adapter '
  'actually echoes a caller-supplied reference back on status callbacks is '
  'a documented, disclosed dependency (6D §28.10a), not assumed universally '
  'true of every provider.';
COMMENT ON COLUMN voice.call_dispatch_keys.claimed_by IS
  'Worker identifier holding the current provider-submission-preparation '
  'lease. NULL when not CLAIMED/SUBMITTING.';
COMMENT ON COLUMN voice.call_dispatch_keys.claim_expires_at IS
  'Lease expiry. A CLAIMED row past this timestamp is treated as an '
  'abandoned (crashed-worker) claim and may be re-claimed by '
  'fn_claim_dispatch_for_provider_submission(). A SUBMITTING row past this '
  'timestamp is NOT re-claimable through that path at any point -- only '
  'fn_reconcile_dispatch_outcome() can resolve it.';
COMMENT ON COLUMN voice.call_dispatch_keys.submission_started_at IS
  'Set exactly once, by fn_begin_provider_submission(), in the same short '
  'transaction that commits the CLAIMED -> SUBMITTING transition, strictly '
  'BEFORE the caller ever invokes TelephonyPort.place_call(). Its presence '
  'is the durable proof that external submission may have begun.';
COMMENT ON COLUMN voice.call_dispatch_keys.provider_call_ref IS
  'The provider''s own call identifier, recorded only once CONFIRMED.';
COMMENT ON COLUMN voice.call_dispatch_keys.reconciled_by IS
  'Set only by fn_reconcile_dispatch_outcome() -- identifies the callback '
  'handler / operator / backfill process that resolved a SUBMITTING or '
  'AMBIGUOUS row, distinct from claimed_by (the original, presumed-gone, '
  'dispatching worker).';

CREATE INDEX idx_cdk_org ON voice.call_dispatch_keys (organization_id);
CREATE INDEX idx_cdk_call_session_id ON voice.call_dispatch_keys (call_session_id);

-- Reconciliation/monitoring sweep index: RESERVED rows never attempted,
-- CLAIMED rows whose prep lease has expired (safely reclaimable), and
-- SUBMITTING/AMBIGUOUS rows awaiting fn_reconcile_dispatch_outcome().
CREATE INDEX idx_cdk_reconciliation
  ON voice.call_dispatch_keys (dispatch_state, claim_expires_at)
  WHERE dispatch_state IN ('RESERVED','CLAIMED','SUBMITTING','AMBIGUOUS');

ALTER TABLE voice.call_dispatch_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.call_dispatch_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cdk_tenant ON voice.call_dispatch_keys
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Blocker C (this pass, Final Blocker Remediation, 2026-08-28): no role
-- holds direct INSERT/UPDATE/DELETE on this table. Every row is created
-- and every state transition happens through one of the guarded functions
-- below, all SECURITY DEFINER, owned by app_migration (which already
-- holds full privileges on every object it creates independent of any
-- GRANT statement here). The original design already withheld direct
-- UPDATE; this pass additionally withholds direct INSERT, which the first
-- two passes left open -- an adversarial review correctly observed that a
-- caller holding INSERT could construct an arbitrary dispatch_state
-- (including a fabricated 'CONFIRMED' row bypassing the entire state
-- machine) without ever calling fn_initiate_outbound_call_idempotent().
GRANT SELECT ON voice.call_dispatch_keys TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON voice.call_dispatch_keys TO app_platform_admin;

-- =================================================================
-- §C. Functions
-- =================================================================

-- -----------------------------------------------------------------
-- fn_initiate_outbound_call_idempotent: reserves the logical call
-- identity. Never claims provider-submission ownership; never implies the
-- provider was (or was not) contacted.
--
-- §D. Blocker D fix (this pass): tenant and payload validation on replay.
-- This function is SECURITY DEFINER and therefore bypasses RLS entirely
-- (owner privilege, per 6G's/098_5E1.sql's own documented precedent) --
-- the explicit organization_id check below on the replay path IS the
-- entire tenant-isolation guarantee for this function, not one layer of
-- several. A cross-tenant replay of someone else's dispatch_idempotency_key
-- resolves as a generic, non-disclosing exception (never reveals that the
-- key exists under a different tenant, matching fn_enqueue_contact's own
-- established non-disclosure convention, 098_5E1.sql). A same-tenant
-- replay with a DIFFERENT payload_fingerprint (destination/agent/tenant
-- number silently changed under an old key) is rejected with the
-- project's existing global error semantic `IDEMPOTENCY_KEY_REUSE_MISMATCH`
-- (6A §16.2), reused here at the domain layer exactly as instructed rather
-- than inventing a new vocabulary -- returned as an `outcome` value, not
-- an exception, matching this schema's existing convention of returning a
-- caller-actionable reason code for expected, non-security outcomes (the
-- same convention campaign.fn_reserve_dispatch already uses for its
-- `reason` column).
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_initiate_outbound_call_idempotent(
  p_organization_id          UUID,
  p_from_number              TEXT,
  p_to_number                TEXT,
  p_agent_version_id         UUID,
  p_tenant_phone_number_id   UUID,
  p_campaign_lead_ref        TEXT,
  p_dispatch_idempotency_key CHAR(64)
)
RETURNS TABLE(call_session_id UUID, session_started_at TIMESTAMPTZ, is_new BOOLEAN, outcome TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, organization, pg_catalog
AS $$
DECLARE
  v_id          UUID        := voice.fn_new_uuid_v7();
  v_now         TIMESTAMPTZ := NOW();
  v_claim       voice.call_dispatch_keys%ROWTYPE;
  v_fingerprint CHAR(64);
BEGIN
  -- §D. Canonical fingerprint (see §D header note above and the migration's
  -- final footer comment for the exact format). Computed here, inside the
  -- function, from the actual parameters -- never accepted as a
  -- caller-supplied hash, which would defeat the point of verifying the
  -- ACTUAL fields on replay. public.digest() is pgcrypto's C-language
  -- digest function, fully schema-qualified at this call site; unlike
  -- gen_uuid_v7() (§A), it has no internal unqualified nested call that
  -- would require `public` in this function's own search_path -- verified
  -- live, not assumed (see 6H §49 live-validation evidence for this pass).
  v_fingerprint := encode(
    public.digest(
      jsonb_build_object(
        'v', 1,
        'organization_id', p_organization_id,
        'campaign_lead_ref', p_campaign_lead_ref,
        'to_number', p_to_number,
        'from_number', p_from_number,
        'agent_version_id', p_agent_version_id,
        'tenant_phone_number_id', p_tenant_phone_number_id
      )::text,
      'sha256'
    ),
    'hex'
  );

  -- dispatch_state defaults to 'RESERVED' at INSERT time (column DEFAULT).
  -- provider_request_ref is fixed here, for the lifetime of this dispatch
  -- key, to the key itself (INV-VOICE-DISPATCH-06) -- see §B's column
  -- comment for why this is a distinct, named column rather than reusing
  -- dispatch_idempotency_key directly at every call site.
  INSERT INTO voice.call_dispatch_keys
    (dispatch_idempotency_key, organization_id, call_session_id, started_at,
     payload_fingerprint, provider_request_ref)
  VALUES (p_dispatch_idempotency_key, p_organization_id, v_id, v_now,
          v_fingerprint, p_dispatch_idempotency_key)
  ON CONFLICT (dispatch_idempotency_key) DO NOTHING
  RETURNING * INTO v_claim;

  IF v_claim.dispatch_idempotency_key IS NOT NULL THEN
    -- Won the claim: create the actual call_sessions row using the SAME
    -- id/started_at just reserved, in the SAME transaction -- the claim and
    -- the call_sessions row can never diverge.
    INSERT INTO voice.call_sessions (
      id, started_at, organization_id, direction, status,
      from_number, to_number, tenant_phone_number_id, agent_version_id,
      campaign_lead_ref
    ) VALUES (
      v_claim.call_session_id, v_claim.started_at, p_organization_id, 'OUTBOUND', 'INITIATED',
      p_from_number, p_to_number, p_tenant_phone_number_id, p_agent_version_id,
      p_campaign_lead_ref
    );

    RETURN QUERY SELECT v_claim.call_session_id, v_claim.started_at, TRUE, 'CREATED'::TEXT;
    RETURN;
  END IF;

  -- Lost the claim: a prior call (the original attempt, or a genuine
  -- concurrent race) already owns this dispatch identity.
  SELECT * INTO v_claim
  FROM voice.call_dispatch_keys
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key;

  -- §D tenant check -- see header note. Non-disclosing: the message never
  -- states whether the key exists, only that it is unavailable to this
  -- caller.
  IF v_claim.organization_id <> p_organization_id THEN
    RAISE EXCEPTION 'fn_initiate_outbound_call_idempotent: dispatch_idempotency_key not available for organization %', p_organization_id;
  END IF;

  -- §D payload check -- same tenant, different immutable request. Returned
  -- as an outcome code (caller-actionable), not an exception; no session
  -- identity is returned so the caller cannot accidentally act on the
  -- original (mismatched) call.
  IF v_claim.payload_fingerprint <> v_fingerprint THEN
    RETURN QUERY SELECT NULL::UUID, NULL::TIMESTAMPTZ, FALSE, 'IDEMPOTENCY_KEY_REUSE_MISMATCH'::TEXT;
    RETURN;
  END IF;

  -- Same tenant, same payload: genuine idempotent replay.
  RETURN QUERY SELECT v_claim.call_session_id, v_claim.started_at, FALSE, 'REPLAYED'::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_initiate_outbound_call_idempotent(UUID,TEXT,TEXT,UUID,UUID,TEXT,CHAR(64)) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_initiate_outbound_call_idempotent(UUID,TEXT,TEXT,UUID,UUID,TEXT,CHAR(64)) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_claim_dispatch_for_provider_submission: the ONLY legal way a worker
-- acquires the right to PREPARE a provider submission. Pure SQL, no
-- external call inside this transaction. Does NOT by itself authorize
-- calling TelephonyPort.place_call() -- see fn_begin_provider_submission()
-- below, which is the actual durable submission boundary.
--
-- Blocker A fix (this pass): the reclaim predicate below deliberately
-- excludes 'SUBMITTING' unconditionally, regardless of how stale
-- claim_expires_at becomes. Only 'RESERVED', 'FAILED', and a 'CLAIMED' row
-- past its lease are reclaimable -- all three are states in which the
-- database can prove the provider was never contacted.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_claim_dispatch_for_provider_submission(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_worker_id                TEXT,
  p_lease_seconds            INTEGER DEFAULT 30
)
RETURNS TABLE(claimed BOOLEAN, call_session_id UUID, provider_request_ref TEXT, attempt_count INTEGER, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
#variable_conflict use_column
-- Required because this function's RETURNS TABLE output parameters
-- `attempt_count` and `provider_request_ref` share names with
-- voice.call_dispatch_keys columns of the same name -- `attempt_count` is
-- both read and incremented by the UPDATE below (`attempt_count =
-- attempt_count + 1`), reproducing the exact "column reference is
-- ambiguous" error found live in the prior pass. This pragma makes every
-- bare identifier inside this function prefer the table column over the
-- like-named PL/pgSQL variable, the correct resolution for that UPDATE.
DECLARE
  v_row voice.call_dispatch_keys%ROWTYPE;
BEGIN
  IF p_lease_seconds NOT BETWEEN 5 AND 300 THEN
    RAISE EXCEPTION 'fn_claim_dispatch_for_provider_submission: p_lease_seconds % out of bounds [5,300]', p_lease_seconds;
  END IF;

  UPDATE voice.call_dispatch_keys
  SET dispatch_state        = 'CLAIMED',
      claimed_by             = p_worker_id,
      claimed_at              = NOW(),
      claim_expires_at        = NOW() + make_interval(secs => p_lease_seconds),
      attempt_count           = attempt_count + 1,
      submission_started_at   = NULL  -- reset: any prior attempt's marker
                                       -- does not describe this new attempt
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND (
      dispatch_state = 'RESERVED'
      OR dispatch_state = 'FAILED'
      OR (dispatch_state = 'CLAIMED' AND claim_expires_at < NOW())
      -- Deliberately NO branch for SUBMITTING at any staleness -- Blocker A.
    )
  RETURNING * INTO v_row;

  IF v_row.dispatch_idempotency_key IS NULL THEN
    -- Either genuinely not found, or in a state that forbids claiming
    -- right now (CONFIRMED -- already done; SUBMITTING/AMBIGUOUS -- may
    -- have reached the provider, never auto-retried, reconciliation-only;
    -- CLAIMED with a still-valid lease -- another worker owns it right now).
    SELECT * INTO v_row FROM voice.call_dispatch_keys
      WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
        AND organization_id = p_organization_id;

    IF v_row.dispatch_idempotency_key IS NULL THEN
      RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT, 0, 'DISPATCH_KEY_NOT_FOUND'::TEXT;
    ELSE
      RETURN QUERY SELECT FALSE, v_row.call_session_id, v_row.provider_request_ref, v_row.attempt_count,
        ('NOT_CLAIMABLE_' || v_row.dispatch_state)::TEXT;
    END IF;
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, v_row.call_session_id, v_row.provider_request_ref, v_row.attempt_count, NULL::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_claim_dispatch_for_provider_submission(CHAR(64),UUID,TEXT,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_claim_dispatch_for_provider_submission(CHAR(64),UUID,TEXT,INTEGER) TO app_worker;


-- -----------------------------------------------------------------
-- fn_begin_provider_submission: THE durable submission boundary (Final
-- Blocker Remediation §4). The caller's mandatory contract: call this,
-- confirm began=TRUE, and only THEN invoke TelephonyPort.place_call() --
-- never before. CAS-guarded on (key, claimed_by, lease still valid): if
-- this worker's own lease already expired (a slow worker that paused long
-- enough for another to have reclaimed, or simply run out its lease with
-- nobody else near it yet), this call safely fails closed (began=FALSE)
-- rather than letting a worker that may no longer hold exclusive ownership
-- proceed to contact the provider.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_begin_provider_submission(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_worker_id                TEXT
)
RETURNS TABLE(began BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE voice.call_dispatch_keys
  SET dispatch_state = 'SUBMITTING',
      submission_started_at = NOW()
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state = 'CLAIMED'
    AND claimed_by = p_worker_id
    AND claim_expires_at > NOW();
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 THEN
    RETURN QUERY SELECT TRUE, NULL::TEXT;
  ELSE
    RETURN QUERY SELECT FALSE, 'NOT_CLAIM_HOLDER'::TEXT;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_begin_provider_submission(CHAR(64),UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_begin_provider_submission(CHAR(64),UUID,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_record_dispatch_confirmed: called after TelephonyPort.place_call()
-- returns a definite provider acceptance. Only legal from SUBMITTING (a
-- confirmation implies a submission attempt genuinely happened).
-- CAS-guarded on (key, claimed_by) so only the worker currently holding
-- the claim can record a result -- a reclaimed row's original (crashed)
-- worker calling this late is a safe no-op (0 rows), not a corruption of
-- the new claimant's work. (In practice this cannot race against a fresh
-- reclaim in this design, since SUBMITTING is never reclaimable -- this
-- CAS guard is retained as defense-in-depth, not the primary safety
-- mechanism.)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_record_dispatch_confirmed(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_worker_id                TEXT,
  p_provider_call_ref        TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_provider_call_ref IS NULL OR length(p_provider_call_ref) = 0 THEN
    RAISE EXCEPTION 'fn_record_dispatch_confirmed: p_provider_call_ref is required';
  END IF;

  UPDATE voice.call_dispatch_keys
  SET dispatch_state = 'CONFIRMED',
      provider_call_ref = p_provider_call_ref,
      confirmed_at = NOW(),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state = 'SUBMITTING'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_record_dispatch_confirmed(CHAR(64),UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_record_dispatch_confirmed(CHAR(64),UUID,TEXT,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_record_dispatch_ambiguous: called when the provider network call's
-- outcome could not be determined (timeout, connection reset, 5xx with no
-- clear body) by the SAME worker that made the attempt, synchronously.
-- Only legal from SUBMITTING. This is a HARD STOP for automatic retry --
-- the row stays AMBIGUOUS until fn_reconcile_dispatch_outcome() (an
-- operator, a provider callback correlation, or a bounded provider-side
-- lookup) explicitly resolves it. No function in this migration
-- transitions AMBIGUOUS back to CLAIMED/SUBMITTING automatically.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_record_dispatch_ambiguous(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_worker_id                TEXT,
  p_error                    TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE voice.call_dispatch_keys
  SET dispatch_state = 'AMBIGUOUS',
      last_error = LEFT(COALESCE(p_error, ''), 2000),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state = 'SUBMITTING'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_record_dispatch_ambiguous(CHAR(64),UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_record_dispatch_ambiguous(CHAR(64),UUID,TEXT,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_record_dispatch_failed: called either (a) while still CLAIMED, when a
-- local pre-submission check fails and the provider was never contacted
-- at all, or (b) from SUBMITTING, only when the provider's response
-- DEFINITELY proves no call was accepted (a synchronous validation/auth
-- error with a clear response body -- never a timeout, never an
-- ambiguous response; those go to fn_record_dispatch_ambiguous instead).
-- Safe to retry -- fn_claim_dispatch_for_provider_submission allows
-- re-claiming a FAILED row.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_record_dispatch_failed(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_worker_id                TEXT,
  p_error                    TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE voice.call_dispatch_keys
  SET dispatch_state = 'FAILED',
      last_error = LEFT(COALESCE(p_error, ''), 2000),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state IN ('CLAIMED', 'SUBMITTING')
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_record_dispatch_failed(CHAR(64),UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_record_dispatch_failed(CHAR(64),UUID,TEXT,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_reconcile_dispatch_outcome: the ONLY way a SUBMITTING or AMBIGUOUS
-- row is ever resolved by anyone other than the original dispatching
-- worker. Deliberately NOT CAS-guarded on claimed_by -- the original
-- worker/lease is presumed gone (that is precisely why the row is stuck).
-- Resolution is identity-correlated instead: the caller (a provider
-- status-callback handler that has already matched the inbound callback
-- to this dispatch_idempotency_key via provider_request_ref, or a bounded
-- operator/provider-lookup decision) asserts a definite outcome.
-- Idempotent: calling this again on an already-CONFIRMED/FAILED row
-- matches zero rows and returns reconciled=FALSE, rather than erroring or
-- silently double-applying a side effect.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_reconcile_dispatch_outcome(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_outcome                  TEXT,   -- 'CONFIRMED' | 'FAILED'
  p_reconciled_by             TEXT,
  p_provider_call_ref         TEXT DEFAULT NULL,
  p_note                      TEXT DEFAULT NULL
)
RETURNS TABLE(reconciled BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_outcome NOT IN ('CONFIRMED','FAILED') THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_outcome: invalid p_outcome %, must be CONFIRMED or FAILED', p_outcome;
  END IF;

  IF p_outcome = 'CONFIRMED' AND (p_provider_call_ref IS NULL OR length(p_provider_call_ref) = 0) THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_outcome: p_provider_call_ref is required when p_outcome = CONFIRMED';
  END IF;

  UPDATE voice.call_dispatch_keys
  SET dispatch_state = p_outcome,
      provider_call_ref = CASE WHEN p_outcome = 'CONFIRMED' THEN p_provider_call_ref ELSE provider_call_ref END,
      confirmed_at = CASE WHEN p_outcome = 'CONFIRMED' THEN NOW() ELSE confirmed_at END,
      last_error = COALESCE(p_note, last_error),
      reconciled_by = p_reconciled_by,
      reconciled_at = NOW(),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state IN ('SUBMITTING', 'AMBIGUOUS');
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 THEN
    RETURN QUERY SELECT TRUE, NULL::TEXT;
  ELSE
    RETURN QUERY SELECT FALSE, 'NOT_RECONCILABLE_OR_NOT_FOUND'::TEXT;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_reconcile_dispatch_outcome(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_reconcile_dispatch_outcome(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT) TO app_api, app_worker;

-- =================================================================
-- §E. Provider-dispatch invariants formalized by this migration (6H §51
--     mirrors these exactly as INV-VOICE-DISPATCH-01..06):
--
--   01. One dispatch_idempotency_key maps to exactly one logical
--       voice.call_sessions row (pk_call_dispatch_keys + the same-
--       transaction INSERT in fn_initiate_outbound_call_idempotent()).
--   02. At most one worker owns provider-submission preparation at a time
--       (claimed_by CAS, enforced by every UPDATE ... WHERE claimed_by = ...).
--   03. Lease expiration alone cannot authorize a second provider call
--       once SUBMITTING has been durably committed (fn_claim_dispatch_
--       for_provider_submission's reclaim predicate excludes SUBMITTING
--       unconditionally -- Blocker A).
--   04. Only states that prove provider submission never began (RESERVED,
--       FAILED, lease-expired CLAIMED) are automatically retryable.
--   05. Ambiguous provider outcomes require fn_reconcile_dispatch_outcome
--       (reconciliation), never a blind redial.
--   06. provider_request_ref is fixed at reservation time and never
--       regenerated on retry -- the same stable platform reference is
--       propagated to the provider on every attempt.
-- =================================================================

-- =================================================================
-- §F. Provider idempotency capability -- verified, not invented.
--
--   This migration and 6D/3B were re-checked in this pass for any
--   documented Exotel (or other configured provider) native
--   idempotency-key mechanism for outbound call creation. NONE IS
--   DOCUMENTED anywhere in this repository's 3B (Telephony ACL/provider
--   contract) or 6D (Voice/Call Agent API) material. This migration
--   therefore makes NO claim that a second physical provider submission
--   is prevented by the provider itself. What IS guaranteed, DB-enforced,
--   and live-validated:
--     - exactly-one logical call identity (INV-VOICE-DISPATCH-01);
--     - at-most-one concurrent platform-side owner of a submission attempt
--       (INV-VOICE-DISPATCH-02);
--     - no automatic retry once the platform can no longer prove the
--       provider was never contacted (INV-VOICE-DISPATCH-03/04);
--     - a stable reference is available for the active provider adapter to
--       propagate, IF that adapter is later confirmed to support
--       echoing a caller reference back on status callbacks
--       (INV-VOICE-DISPATCH-06) -- Exotel's actual support for this is
--       NOT verified in this pass and is not claimed.
--   What is explicitly NOT guaranteed: exactly-once PHYSICAL provider
--   submission during a genuinely ambiguous external failure (Case
--   B/C, §B above). That residual risk is bounded by 6D's pre-existing
--   provider-retry contract (3B §19) and by fn_reconcile_dispatch_outcome
--   (operator/callback-driven resolution), not eliminated by the database
--   alone -- stated plainly rather than claimed away.
-- =================================================================

-- =================================================================
-- Caller contract, precisely (6D §28.10a mirrors this exactly):
--   1. fn_initiate_outbound_call_idempotent() -- reserve logical call.
--      Commit. If outcome = 'IDEMPOTENCY_KEY_REUSE_MISMATCH', stop and
--      surface 409 IDEMPOTENCY_KEY_REUSE_MISMATCH (6A §16.2) -- do not
--      proceed to dispatch anything.
--   2. fn_claim_dispatch_for_provider_submission() -- claim submission-
--      preparation ownership. Commit. If claimed=FALSE, stop (another
--      worker owns it, or it is in a non-claimable state -- do not call
--      the provider).
--   3. fn_begin_provider_submission() -- commit the durable "submission
--      may now begin" boundary. Commit. If began=FALSE, STOP -- do not
--      call the provider (another worker's claim now owns this row, or
--      this worker's own lease already lapsed).
--   4. TelephonyPort.place_call() -- OUTSIDE any transaction, using
--      provider_request_ref returned by step 2.
--   5a. On definite provider acceptance: fn_record_dispatch_confirmed().
--   5b. On definite provider rejection (sync validation error,
--       pre-acceptance): fn_record_dispatch_failed().
--   5c. On ANY ambiguity (timeout, connection reset, unclear response):
--       fn_record_dispatch_ambiguous() -- never guess, never auto-retry.
--   A provider status-callback handler (or a bounded operator/backfill
--   process), upon positively correlating an inbound callback to this
--   dispatch_idempotency_key (via provider_request_ref), calls
--   fn_reconcile_dispatch_outcome() to resolve a SUBMITTING or AMBIGUOUS
--   row to its true terminal outcome -- this is the only path that
--   resolves a crash that occurred strictly between step 3's COMMIT and
--   step 5's recording (Case B/C, §B above), and is exercised live by
--   this pass's "duplicate callback while SUBMITTING" and "reconcile an
--   AMBIGUOUS row" test scenarios (6H §49).
-- =================================================================
