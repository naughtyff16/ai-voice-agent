-- =================================================================
-- Migration 099 (Phase 5C.1 — controlled amendment): in-process outbound
--   call dispatch idempotency AND provider-dispatch durability
--   + voice.call_dispatch_keys (extended), voice.fn_initiate_outbound_call_idempotent()
--   + voice.fn_claim_dispatch_for_provider_submission()
--   + voice.fn_record_dispatch_confirmed()
--   + voice.fn_record_dispatch_ambiguous()
--   + voice.fn_record_dispatch_failed()
-- down_revision: 098_5E1
-- Transaction: yes
-- Source: docs/phase-06-api-design/6H-Campaign-APIs.md Phase 6H Remediation
--   (2026-08-28) — Blocker #3 (Campaign -> Voice in-process dispatch
--   idempotency gap), extended by the Final Remediation pass (same day)
--   with Blocker C: a genuine crash-durability hole in the first pass's
--   design (see §C below) and the SECURITY DEFINER search_path fix (§A).
--
-- REVISION NOTE: this file supersedes the version first written earlier
-- in this same reconciliation. It has NOT been applied to any production
-- database (disclosed explicitly in every pass), so it is corrected in
-- place here rather than superseded by a new 100_5C2.sql — there is no
-- "frozen, already-applied" version of this file to preserve.
--
-- SCOPE DISCIPLINE:
--   This remains a CONTROLLED, ADDITIVE AMENDMENT to the `voice` schema.
--   It adds one new table (extended from the first pass), five functions
--   (four new since the first pass), all inside `voice`. voice.call_sessions
--   itself is still untouched — no column is added to it, no existing row
--   shape changes. `campaign_lead_ref` (existing, nullable, 011_5C.sql) is
--   still reused for Campaign correlation unchanged.
--
-- =================================================================
-- §A. SECURITY DEFINER search_path — empirically verified fix
--     (identical reasoning and fix pattern as 098_5E1.sql §A)
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
-- §B. voice.call_dispatch_keys — extended with the provider-dispatch
--     state machine (Blocker C)
-- =================================================================
--
-- WHY THE FIRST PASS WAS INSUFFICIENT (Blocker C, found by adversarial
-- final review, not by this migration's own author claiming success):
--
--   First-pass flow:
--     1. claim dispatch_idempotency_key, INSERT call_sessions (COMMIT)
--     2. TelephonyPort.place_call() -- outside any transaction
--     3. on retry: if key already claimed, refuse to call the provider
--        again ("is_new = FALSE -> do not re-invoke the telephony provider")
--
--   Failure mode this creates: if the worker crashes between step 1's
--   COMMIT and step 2's network call, the call_sessions row exists
--   forever at status='INITIATED', but the provider was NEVER contacted.
--   A retry sees is_new=FALSE (the key is already claimed) and, per the
--   first pass's own stated contract, correctly refuses to call the
--   provider again -- permanently losing a call that was never actually
--   placed. This is exactly the "logical call exists forever but no
--   actual call occurs" failure the Final Remediation task named.
--
--   The fix requires distinguishing, durably, at least these states:
--     RESERVED   -- logical call reserved; provider submission has
--                   definitely NOT been attempted yet
--     CLAIMED    -- exactly one worker currently owns provider
--                   submission, under a time-bounded lease
--     CONFIRMED  -- the provider definitely accepted the request
--                   (provider_call_ref recorded)
--     AMBIGUOUS  -- the provider submission's outcome could not be
--                   determined (network error/timeout on the response
--                   leg) -- MUST NOT be blindly retried
--     FAILED     -- the provider definitely rejected the request before
--                   any chance of it having been accepted (e.g. a
--                   synchronous 4xx validation error) -- safe to retry
--
--   A stale (lease-expired) CLAIMED row is the crash-before-or-during-
--   submission case: this migration treats it as re-claimable (safe to
--   attempt submission again), because a worker crash between claiming
--   and actually issuing the network call is indistinguishable, from the
--   database's point of view, from a crash *during* the network call --
--   and this design explicitly accepts that a fresh CLAIMED lease with no
--   evidence of an actual network attempt (no AMBIGUOUS/CONFIRMED/FAILED
--   ever recorded) has not yet reached the provider boundary. THE ONE
--   CASE THIS MIGRATION DOES NOT AND CANNOT SOLVE ALONE: a crash *during*
--   the provider's own network processing of an already-sent request,
--   where the provider received it but our process died before writing
--   even a "submission attempted" marker. Closing that residual sliver
--   requires either (a) a provider-native idempotency key honoured by
--   the provider itself on retry (verify per-provider, not assumed here
--   -- 3B/6D do not currently document Exotel supporting one), or (b) a
--   provider-side reference echoed back on every callback so a bounded
--   reconciliation window can positively confirm or rule out that the
--   call was ever placed. This migration implements the DB-side half of
--   option (b) (provider_request_ref, a reconciliation query, and the
--   AMBIGUOUS state that blocks auto-retry) and documents the dependency
--   on the provider-adapter layer explicitly rather than claiming a
--   guarantee the database alone cannot provide -- see 6D §28.10a's
--   corresponding update and 6H §18.4's disclosure.
-- =================================================================

-- Base table (this migration is the only place voice.call_dispatch_keys is
-- ever created — there is no separately-applied "first pass" of 099_5C1.sql
-- in any real environment, since it has never been applied to production;
-- the CREATE TABLE and the state-machine extension below are one migration).
CREATE TABLE voice.call_dispatch_keys (
  dispatch_idempotency_key CHAR(64)    NOT NULL,
  organization_id          UUID        NOT NULL,
  call_session_id          UUID        NOT NULL,
  started_at               TIMESTAMPTZ NOT NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  dispatch_state       TEXT        NOT NULL DEFAULT 'RESERVED',
  claimed_by           TEXT        NULL,
  claimed_at           TIMESTAMPTZ NULL,
  claim_expires_at     TIMESTAMPTZ NULL,
  attempt_count        INTEGER     NOT NULL DEFAULT 0,
  provider_request_ref TEXT        NULL,
  provider_call_ref    TEXT        NULL,
  submitted_at         TIMESTAMPTZ NULL,
  confirmed_at         TIMESTAMPTZ NULL,
  last_error           TEXT        NULL,

  CONSTRAINT pk_call_dispatch_keys PRIMARY KEY (dispatch_idempotency_key),
  CONSTRAINT chk_cdk_dispatch_state
    CHECK (dispatch_state IN ('RESERVED','CLAIMED','CONFIRMED','AMBIGUOUS','FAILED')),
  CONSTRAINT chk_cdk_attempt_count_nn CHECK (attempt_count >= 0),
  CONSTRAINT chk_cdk_confirmed_has_ref
    CHECK (dispatch_state <> 'CONFIRMED' OR provider_call_ref IS NOT NULL),
  CONSTRAINT chk_cdk_claimed_has_lease
    CHECK (dispatch_state <> 'CLAIMED' OR (claimed_by IS NOT NULL AND claim_expires_at IS NOT NULL))
);

COMMENT ON COLUMN voice.call_dispatch_keys.dispatch_state IS
  'Provider-dispatch attempt state machine (Blocker C): RESERVED -> CLAIMED '
  '-> CONFIRMED | AMBIGUOUS | FAILED. Independent of voice.call_sessions.status '
  '(the call''s own conversational/telephony lifecycle, unchanged, owned by 6D). '
  'AMBIGUOUS is a hard stop for automatic retry -- reconciliation-only.';
COMMENT ON COLUMN voice.call_dispatch_keys.claimed_by IS
  'Worker identifier holding the current provider-submission lease. NULL when not CLAIMED.';
COMMENT ON COLUMN voice.call_dispatch_keys.claim_expires_at IS
  'Lease expiry. A CLAIMED row past this timestamp is treated as an abandoned '
  '(crashed-worker) claim and may be re-claimed by fn_claim_dispatch_for_provider_submission().';
COMMENT ON COLUMN voice.call_dispatch_keys.provider_request_ref IS
  'Platform-generated reference passed to the telephony provider on the outbound '
  'request, where the provider''s API/adapter supports echoing a caller-supplied '
  'reference back on status callbacks -- enables reconciliation of an AMBIGUOUS '
  'attempt without relying on provider-native idempotency. NULL if the active '
  'provider adapter does not support this (a documented, disclosed dependency, '
  'not assumed universally true of every provider -- 6D §28.10a).';
COMMENT ON COLUMN voice.call_dispatch_keys.provider_call_ref IS
  'The provider''s own call identifier, recorded only once CONFIRMED.';

CREATE INDEX idx_cdk_org ON voice.call_dispatch_keys (organization_id);
CREATE INDEX idx_cdk_call_session_id ON voice.call_dispatch_keys (call_session_id);

-- Reconciliation sweep index: find RESERVED rows never attempted, CLAIMED
-- rows whose lease has expired, and AMBIGUOUS rows awaiting resolution.
CREATE INDEX idx_cdk_reconciliation
  ON voice.call_dispatch_keys (dispatch_state, claim_expires_at)
  WHERE dispatch_state IN ('RESERVED','CLAIMED','AMBIGUOUS');

ALTER TABLE voice.call_dispatch_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.call_dispatch_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cdk_tenant ON voice.call_dispatch_keys
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Deliberately no direct UPDATE grant for app_api/app_worker: every state
-- transition (CLAIMED/CONFIRMED/AMBIGUOUS/FAILED) must go through one of
-- the guarded functions below, matching the platform's established
-- pattern for other guarded state machines (e.g. crm.contact_suppressions
-- has no direct UPDATE grant either — only crm.lift_suppression()). The
-- functions themselves run SECURITY DEFINER and do not need this grant.
GRANT SELECT, INSERT ON voice.call_dispatch_keys TO app_api, app_worker;
GRANT SELECT ON voice.call_dispatch_keys TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON voice.call_dispatch_keys TO app_platform_admin;

-- =================================================================
-- §C. Functions
-- =================================================================

CREATE OR REPLACE FUNCTION voice.fn_initiate_outbound_call_idempotent(
  p_organization_id          UUID,
  p_from_number              TEXT,
  p_to_number                TEXT,
  p_agent_version_id         UUID,
  p_tenant_phone_number_id   UUID,
  p_campaign_lead_ref        TEXT,
  p_dispatch_idempotency_key CHAR(64)
)
RETURNS TABLE(call_session_id UUID, session_started_at TIMESTAMPTZ, is_new BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, organization, pg_catalog
AS $$
DECLARE
  v_id      UUID        := voice.fn_new_uuid_v7();
  v_now     TIMESTAMPTZ := NOW();
  v_claim   voice.call_dispatch_keys%ROWTYPE;
BEGIN
  -- dispatch_state defaults to 'RESERVED' at INSERT time (column DEFAULT) --
  -- this call only ever reserves the logical call identity. It never
  -- claims provider-submission ownership and never implies the provider
  -- was (or was not) contacted -- see fn_claim_dispatch_for_provider_submission().
  INSERT INTO voice.call_dispatch_keys
    (dispatch_idempotency_key, organization_id, call_session_id, started_at)
  VALUES (p_dispatch_idempotency_key, p_organization_id, v_id, v_now)
  ON CONFLICT (dispatch_idempotency_key) DO NOTHING
  RETURNING * INTO v_claim;

  IF v_claim.dispatch_idempotency_key IS NULL THEN
    -- Lost the claim: a prior call (the original attempt, or a genuine
    -- concurrent race) already owns this dispatch identity. Idempotent
    -- no-op: return the winner's call_session_id/started_at so the caller
    -- can inspect its current provider-dispatch state instead of assuming
    -- anything about whether the provider was ever contacted.
    SELECT * INTO v_claim
    FROM voice.call_dispatch_keys
    WHERE dispatch_idempotency_key = p_dispatch_idempotency_key;

    RETURN QUERY SELECT v_claim.call_session_id, v_claim.started_at, FALSE;
    RETURN;
  END IF;

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

  RETURN QUERY SELECT v_claim.call_session_id, v_claim.started_at, TRUE;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_initiate_outbound_call_idempotent(UUID,TEXT,TEXT,UUID,UUID,TEXT,CHAR(64)) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_initiate_outbound_call_idempotent(UUID,TEXT,TEXT,UUID,UUID,TEXT,CHAR(64)) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_claim_dispatch_for_provider_submission: the ONLY legal way a worker
-- acquires the right to actually call TelephonyPort.place_call() for a
-- given dispatch. Pure SQL, no external call inside this transaction.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_claim_dispatch_for_provider_submission(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_worker_id                TEXT,
  p_lease_seconds            INTEGER DEFAULT 30,
  p_provider_request_ref     TEXT DEFAULT NULL
)
RETURNS TABLE(claimed BOOLEAN, call_session_id UUID, attempt_count INTEGER, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
#variable_conflict use_column
-- Required because this function's RETURNS TABLE output parameter
-- `attempt_count` has the same name as voice.call_dispatch_keys'
-- `attempt_count` column, which the UPDATE below both reads and
-- increments (`attempt_count = attempt_count + 1`). Without this
-- pragma PL/pgSQL raises "column reference is ambiguous" — reproduced
-- live before this fix was added, not merely anticipated. This pragma
-- makes every bare identifier inside this function prefer the table
-- column over the like-named PL/pgSQL variable, which is the correct
-- and intended resolution for this specific UPDATE statement.
DECLARE
  v_row voice.call_dispatch_keys%ROWTYPE;
BEGIN
  IF p_lease_seconds NOT BETWEEN 5 AND 300 THEN
    RAISE EXCEPTION 'fn_claim_dispatch_for_provider_submission: p_lease_seconds % out of bounds [5,300]', p_lease_seconds;
  END IF;

  UPDATE voice.call_dispatch_keys
  SET dispatch_state   = 'CLAIMED',
      claimed_by       = p_worker_id,
      claimed_at       = NOW(),
      claim_expires_at = NOW() + make_interval(secs => p_lease_seconds),
      attempt_count    = attempt_count + 1,
      provider_request_ref = COALESCE(p_provider_request_ref, provider_request_ref)
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND (
      dispatch_state = 'RESERVED'
      OR dispatch_state = 'FAILED'
      OR (dispatch_state = 'CLAIMED' AND claim_expires_at < NOW())
    )
  RETURNING * INTO v_row;

  IF v_row.dispatch_idempotency_key IS NULL THEN
    -- Either genuinely not found, or in a state that forbids claiming
    -- right now (CONFIRMED -- already done; AMBIGUOUS -- needs
    -- reconciliation, never auto-retried; CLAIMED with a still-valid
    -- lease -- another worker owns it right now).
    SELECT * INTO v_row FROM voice.call_dispatch_keys
      WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
        AND organization_id = p_organization_id;

    IF v_row.dispatch_idempotency_key IS NULL THEN
      RETURN QUERY SELECT FALSE, NULL::UUID, 0, 'DISPATCH_KEY_NOT_FOUND'::TEXT;
    ELSE
      RETURN QUERY SELECT FALSE, v_row.call_session_id, v_row.attempt_count,
        ('NOT_CLAIMABLE_' || v_row.dispatch_state)::TEXT;
    END IF;
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, v_row.call_session_id, v_row.attempt_count, NULL::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_claim_dispatch_for_provider_submission(CHAR(64),UUID,TEXT,INTEGER,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_claim_dispatch_for_provider_submission(CHAR(64),UUID,TEXT,INTEGER,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_record_dispatch_confirmed: called after TelephonyPort.place_call()
-- returns a definite provider acceptance. CAS-guarded on (key, claimed_by)
-- so only the worker currently holding the claim can record a result --
-- a reclaimed row's original (crashed) worker calling this late is a
-- safe no-op (0 rows), not a corruption of the new claimant's work.
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
      submitted_at = COALESCE(submitted_at, NOW()),
      confirmed_at = NOW(),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state = 'CLAIMED'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_record_dispatch_confirmed(CHAR(64),UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_record_dispatch_confirmed(CHAR(64),UUID,TEXT,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_record_dispatch_ambiguous: called when the provider network call's
-- outcome could not be determined (timeout, connection reset, 5xx with
-- no clear body). This is a HARD STOP for automatic retry -- the row
-- stays AMBIGUOUS until an operator or a reconciliation process (matching
-- an inbound provider callback against provider_request_ref, or a
-- provider-side lookup, or a bounded manual decision) explicitly resolves
-- it via fn_record_dispatch_confirmed() or fn_record_dispatch_failed().
-- No function in this migration transitions AMBIGUOUS back to CLAIMED
-- automatically -- this is deliberate, matching the Final Remediation
-- task's explicit requirement.
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
      submitted_at = COALESCE(submitted_at, NOW()),
      last_error = LEFT(COALESCE(p_error, ''), 2000),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state = 'CLAIMED'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_record_dispatch_ambiguous(CHAR(64),UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_record_dispatch_ambiguous(CHAR(64),UUID,TEXT,TEXT) TO app_worker;


-- -----------------------------------------------------------------
-- fn_record_dispatch_failed: called only when the provider DEFINITELY
-- rejected the request before any chance of it having been accepted
-- (e.g. a synchronous validation/auth error with a clear response body,
-- not a timeout). Safe to retry -- fn_claim_dispatch_for_provider_submission
-- allows re-claiming a FAILED row.
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
    AND dispatch_state = 'CLAIMED'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_record_dispatch_failed(CHAR(64),UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_record_dispatch_failed(CHAR(64),UUID,TEXT,TEXT) TO app_worker;

-- =================================================================
-- Caller contract, precisely (6D §28.10a mirrors this exactly):
--   1. fn_initiate_outbound_call_idempotent() -- reserve logical call. Commit.
--   2. fn_claim_dispatch_for_provider_submission() -- claim submission
--      ownership. Commit. If claimed=FALSE, stop (another worker owns it,
--      or it is CONFIRMED/AMBIGUOUS already -- do not call the provider).
--   3. TelephonyPort.place_call() -- OUTSIDE any transaction.
--   4a. On definite provider acceptance: fn_record_dispatch_confirmed().
--   4b. On definite provider rejection (sync validation error, pre-acceptance):
--       fn_record_dispatch_failed().
--   4c. On ANY ambiguity (timeout, connection reset, unclear response):
--       fn_record_dispatch_ambiguous() -- never guess, never auto-retry.
--   A background reconciliation process (idx_cdk_reconciliation) periodically
--   re-claims stale RESERVED/expired-CLAIMED rows (safe -- no evidence the
--   provider was ever contacted) and separately surfaces AMBIGUOUS rows for
--   provider-callback correlation (via provider_request_ref, where the
--   active adapter supports echoing it) or bounded operator reconciliation --
--   never for automatic retry.
-- =================================================================
