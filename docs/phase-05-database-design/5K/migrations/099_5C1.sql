-- =================================================================
-- Migration 099 (Phase 5C.1 — controlled amendment): in-process outbound
--   call dispatch idempotency AND provider-dispatch durability
--   + voice.call_dispatch_keys (extended, provider-submission-boundary
--     state machine, reconciliation provenance), voice.fn_initiate_
--     outbound_call_idempotent()
--   + voice.fn_claim_dispatch_for_provider_submission()
--   + voice.fn_begin_provider_submission()
--   + voice.fn_record_dispatch_confirmed()
--   + voice.fn_record_dispatch_ambiguous()
--   + voice.fn_record_dispatch_failed()
--   + voice.fn_reconcile_dispatch_outcome_internal() (mechanism only, no
--     direct EXECUTE grant to any role)
--   + voice.fn_reconcile_dispatch_from_provider() (new -- replaces
--     fn_reconcile_dispatch_outcome(), provider-source-only, EXECUTE:
--     app_voice_reconciler)
--   + voice.fn_reconcile_dispatch_by_operator() (new -- replaces
--     fn_reconcile_dispatch_outcome(), OPERATOR-only, hardcoded, EXECUTE:
--     app_platform_admin)
--   + role app_voice_reconciler (new, Final Blocker Remediation pass)
-- down_revision: 098_5E1
-- Transaction: yes
-- Source: docs/phase-06-api-design/6H-Campaign-APIs.md Phase 6H Remediation
--   (2026-08-28/29) — Blocker #3 (Campaign -> Voice in-process dispatch
--   idempotency gap), extended by the Final Remediation pass (same day)
--   with Blocker C (crash-before-provider-submission durability hole) and
--   the SECURITY DEFINER search_path fix (§A), extended again by the Final
--   Blocker Remediation pass (same day, third pass) with Blocker A
--   (expired-CLAIMED-lease double-dial hazard), Blocker C-of-that-pass
--   (direct-INSERT privilege bypass), and Blocker D (idempotency replay
--   tenant/payload validation) — see §D/§E/§F below — extended again by the
--   Final Micro-Remediation pass (same day, fourth pass) with the
--   reconciliation-authorization-boundary fix (restricting WHO could call
--   reconciliation: app_voice_reconciler / app_platform_admin only,
--   REVOKED from app_api/app_worker) — extended once more by the fifth
--   pass (Final Micro-Fix) with the reconciliation-PROVENANCE fix: the
--   fourth pass's single fn_reconcile_dispatch_outcome() still let EITHER
--   authorized caller choose WHICH provenance category
--   (PROVIDER_CALLBACK/PROVIDER_LOOKUP/OPERATOR) to record via a plain
--   parameter, meaning the automated reconciler could falsely record
--   itself as an operator decision or vice versa — an audit-integrity
--   defect, closed by splitting into two capability-specific functions,
--   each hardcoding the provenance/actor_type its own EXECUTE grant is
--   allowed to produce — see §C's fn_reconcile_dispatch_outcome_internal()
--   header — and extended once more by this sixth pass (Final Admin-DML
--   Hardening) with the removal of app_platform_admin's own direct
--   INSERT/UPDATE/DELETE grant on voice.call_dispatch_keys (§B): every
--   prior pass restricted app_api/app_worker/app_voice_reconciler, but
--   app_platform_admin's original blanket DML grant on this table was
--   never touched, meaning it could bypass CONFIRMED immutability, the
--   SUBMITTING/AMBIGUOUS hard stops, and the provider/operator provenance
--   split entirely, via one raw UPDATE statement no guarded function ever
--   sees. app_platform_admin now holds SELECT only, identical in shape to
--   every other runtime role.
--
-- REVISION NOTE: this file supersedes the version first written earlier in
-- this same reconciliation, five times now. It has NOT been applied to any
-- production database (disclosed explicitly in every pass), so it is
-- corrected in place here rather than superseded by a new 100_5C2.sql —
-- there is no "frozen, already-applied" version of this file to preserve.
--
-- SCOPE DISCIPLINE:
--   This remains a CONTROLLED, ADDITIVE AMENDMENT to the `voice` schema.
--   It adds one new table (extended across six passes now), ten
--   functions, all inside `voice`, and one new, narrowly-scoped PostgreSQL
--   role (app_voice_reconciler — see §B1 for why an existing role was not
--   reused). voice.call_sessions itself is still untouched — no column is
--   added to it, no existing row shape changes. `campaign_lead_ref`
--   (existing, nullable, 011_5C.sql) is still reused for Campaign
--   correlation unchanged.
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
--                   voice.fn_reconcile_dispatch_from_provider() /
--                   voice.fn_reconcile_dispatch_by_operator() below, an
--                   identity-correlated (not lease-owner-correlated)
--                   resolution path for a delayed provider callback or a
--                   bounded operator/provider-lookup decision -- each
--                   restricted to producing only its own trusted
--                   provenance category (§C).
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
  reconciliation_source    TEXT        NULL,
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
    CHECK (dispatch_state <> 'SUBMITTING' OR submission_started_at IS NOT NULL),
  -- Micro-remediation (reconciliation authorization boundary): the three
  -- provenance fields for a reconciled outcome are all-or-nothing -- a row
  -- is either untouched by reconciliation (all three NULL) or was genuinely
  -- reconciled through fn_reconcile_dispatch_from_provider()/
  -- fn_reconcile_dispatch_by_operator() (all three populated). No path can
  -- set one without the other two.
  CONSTRAINT chk_cdk_reconciliation_fields_together
    CHECK (
      (reconciliation_source IS NULL AND reconciled_by IS NULL AND reconciled_at IS NULL)
      OR (reconciliation_source IS NOT NULL AND reconciled_by IS NOT NULL AND reconciled_at IS NOT NULL)
    ),
  CONSTRAINT chk_cdk_reconciliation_source
    CHECK (reconciliation_source IS NULL OR reconciliation_source IN ('PROVIDER_CALLBACK','PROVIDER_LOOKUP','OPERATOR')),
  -- The dangerous direction (SUBMITTING/AMBIGUOUS -> FAILED via reconciliation
  -- re-opens physical retry eligibility) may never be recorded with a blank
  -- evidence field -- this cannot verify the evidence is TRUE (that is what
  -- the EXECUTE-privilege boundary on fn_reconcile_dispatch_from_provider()/
  -- fn_reconcile_dispatch_by_operator() is for), but it makes "no evidence
  -- at all" structurally impossible for a reconciled FAILED row. Does not
  -- constrain the synchronous, same-worker fn_record_dispatch_failed()
  -- path (a direct observation, not a reconciliation of someone else's
  -- abandoned attempt).
  CONSTRAINT chk_cdk_reconciled_failed_has_evidence
    CHECK (
      NOT (dispatch_state = 'FAILED' AND reconciliation_source IS NOT NULL)
      OR (last_error IS NOT NULL AND length(btrim(last_error)) > 0)
    )
);

COMMENT ON COLUMN voice.call_dispatch_keys.dispatch_state IS
  'Provider-dispatch attempt state machine: RESERVED -> CLAIMED -> SUBMITTING '
  '-> CONFIRMED | AMBIGUOUS | FAILED (FAILED also reachable directly from '
  'CLAIMED for a pre-submission local abort). Independent of voice.call_sessions'
  '.status (the call''s own conversational/telephony lifecycle, unchanged, '
  'owned by 6D). SUBMITTING and AMBIGUOUS are both hard stops for automatic '
  'retry -- reconciliation-only (voice.fn_reconcile_dispatch_from_provider/'
  'fn_reconcile_dispatch_by_operator). This is '
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
  'fn_reconcile_dispatch_from_provider()/fn_reconcile_dispatch_by_operator() '
  'can resolve it.';
COMMENT ON COLUMN voice.call_dispatch_keys.submission_started_at IS
  'Set exactly once, by fn_begin_provider_submission(), in the same short '
  'transaction that commits the CLAIMED -> SUBMITTING transition, strictly '
  'BEFORE the caller ever invokes TelephonyPort.place_call(). Its presence '
  'is the durable proof that external submission may have begun.';
COMMENT ON COLUMN voice.call_dispatch_keys.provider_call_ref IS
  'The provider''s own call identifier, recorded only once CONFIRMED.';
COMMENT ON COLUMN voice.call_dispatch_keys.reconciliation_source IS
  'Set only via fn_reconcile_dispatch_outcome_internal(), never directly: '
  'PROVIDER_CALLBACK/PROVIDER_LOOKUP are the only values '
  'fn_reconcile_dispatch_from_provider() (EXECUTE: app_voice_reconciler '
  'only) can ever produce -- OPERATOR is not an accepted value there under '
  'any circumstance; OPERATOR is the only value '
  'fn_reconcile_dispatch_by_operator() (EXECUTE: app_platform_admin only) '
  'can ever produce -- it takes no source parameter at all, so no caller '
  'can request a provider-sourced value through that path. This is '
  'evidentiary provenance, not authorization by itself -- but unlike the '
  'prior pass, WHICH provenance value a given EXECUTE grant can produce is '
  'now fixed by which wrapper function that grant is on, not by any '
  'caller-suppliable parameter (Blocker: forgeable reconciliation '
  'provenance, this pass).';
COMMENT ON COLUMN voice.call_dispatch_keys.reconciled_by IS
  'Set only via fn_reconcile_dispatch_outcome_internal() (through either '
  'fn_reconcile_dispatch_from_provider() or fn_reconcile_dispatch_by_'
  'operator()) -- identifies the callback handler / operator / backfill '
  'process that resolved a SUBMITTING or AMBIGUOUS row, distinct from '
  'claimed_by (the original, presumed-gone, dispatching worker). Free-text '
  'metadata for audit/debugging only -- never consulted for authorization '
  '(§ "Do not trust reconciled_by as authorization" -- verified: no WHERE '
  'clause, no IF/CASE branch, and no privilege decision anywhere in this '
  'migration reads this parameter).';

CREATE INDEX idx_cdk_org ON voice.call_dispatch_keys (organization_id);
CREATE INDEX idx_cdk_call_session_id ON voice.call_dispatch_keys (call_session_id);

-- Reconciliation/monitoring sweep index: RESERVED rows never attempted,
-- CLAIMED rows whose prep lease has expired (safely reclaimable), and
-- SUBMITTING/AMBIGUOUS rows awaiting fn_reconcile_dispatch_from_provider()/
-- fn_reconcile_dispatch_by_operator().
CREATE INDEX idx_cdk_reconciliation
  ON voice.call_dispatch_keys (dispatch_state, claim_expires_at)
  WHERE dispatch_state IN ('RESERVED','CLAIMED','SUBMITTING','AMBIGUOUS');

ALTER TABLE voice.call_dispatch_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.call_dispatch_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cdk_tenant ON voice.call_dispatch_keys
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Blocker C (Final Blocker Remediation pass): no ORDINARY runtime role
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
--
-- FINAL PRIVILEGE-HARDENING PASS (this pass): app_platform_admin's own
-- direct INSERT/UPDATE/DELETE, retained from the very first version of
-- this table, is now ALSO removed -- it was the one remaining path that
-- could bypass every invariant built above it (CONFIRMED immutability, the
-- SUBMITTING/AMBIGUOUS hard stops, and the provider/operator provenance
-- split, none of which a raw UPDATE statement is aware of or enforces). A
-- caller with the old grant could run
-- `UPDATE voice.call_dispatch_keys SET dispatch_state = 'FAILED' WHERE
-- dispatch_state = 'CONFIRMED'` directly, re-opening a known-accepted call
-- for a second physical attempt, or forge
-- `reconciliation_source = 'PROVIDER_CALLBACK'` on a row it never actually
-- reconciled via the provider path -- both completely undetectable by, and
-- unrelated to, the guarded functions' own careful validation. Removing
-- this grant does not impair the legitimate operator path at all:
-- fn_reconcile_dispatch_by_operator() is SECURITY DEFINER, owned by
-- app_migration, and needs no direct grant on this table to keep writing
-- (identical reasoning already established for app_api/app_worker's own
-- guarded-function calls). app_platform_admin retains SELECT only, for
-- diagnostics/support -- explicitly still a legitimate need, not removed.
-- No documented admin workflow anywhere in 5C/6D/6H depends on direct DML
-- here; if a future retention/cleanup need arises, it should be a new
-- guarded function, not a reopened blanket grant.
GRANT SELECT ON voice.call_dispatch_keys TO app_api, app_worker, app_readonly, app_platform_admin;

-- =================================================================
-- §B1. app_voice_reconciler -- a new, narrowly-scoped role (micro-remediation,
--   reconciliation authorization boundary)
-- =================================================================
--
-- WHY A NEW ROLE, RATHER THAN GRANTING BACK TO app_worker/app_api: the
-- existing role catalog (001_5B.sql: app_api, app_worker, app_readonly,
-- app_migration, app_platform_admin) was inspected first, per this pass's
-- own instruction, and contains no role narrow enough for this specific
-- capability. app_api and app_worker are broad, shared-by-many-functions
-- roles -- granting either EXECUTE on the reconciliation functions means
-- EVERY piece of ordinary application/API/worker code (campaign dispatch,
-- materialization, real-time call initiation, everything) could resolve an
-- AMBIGUOUS submission to FAILED and re-open physical retry, which is
-- exactly the authorization gap this pass exists to close. app_readonly
-- cannot write anything, by design, and is not fit for purpose either.
-- app_platform_admin (BYPASSRLS, the existing break-glass/operator role,
-- `087_5B1.sql`) is the correct fit for the human/operator reconciliation
-- path (see the GRANT below) but is far broader than a single function
-- needs for the automated provider-callback/provider-lookup path -- using
-- it there would mean every automated reconciliation call runs with full
-- platform-admin/BYPASSRLS power for no reason connected to its actual job.
--
-- app_voice_reconciler is therefore a new, minimal role: LOGIN (matching
-- this catalog's own established convention -- every existing role is a
-- directly-connectable LOGIN role, not a NOLOGIN group role granted to
-- others; there is no group-role layer anywhere in this schema to attach a
-- NOLOGIN role to), NOT BYPASSRLS, no table DML of any kind, no membership
-- in any other role. Its entire privilege surface is exactly:
-- USAGE on schema voice, and EXECUTE on exactly one function. A real
-- deployment authenticates its trusted, authenticated provider-status-
-- callback-processing service (or an equivalent narrowly-scoped
-- reconciliation worker) as this role, using a distinct credential from the
-- generic app_worker credential used for campaign dispatch, materialization,
-- and every other Voice/Campaign write.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_voice_reconciler') THEN
    CREATE ROLE app_voice_reconciler LOGIN;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA voice TO app_voice_reconciler;

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
-- the row stays AMBIGUOUS until fn_reconcile_dispatch_from_provider()
-- (a provider callback correlation or a bounded provider-side lookup) or
-- fn_reconcile_dispatch_by_operator() (an operator decision) explicitly
-- resolves it. No function in this migration transitions AMBIGUOUS back to
-- CLAIMED/SUBMITTING automatically.
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
-- MICRO-FIX (non-forgeable reconciliation provenance, this pass): the prior
-- pass's fn_reconcile_dispatch_outcome() correctly restricted WHO could
-- call reconciliation (app_voice_reconciler / app_platform_admin only) but
-- still let EITHER of those two callers freely choose WHICH provenance
-- category to record via a plain p_reconciliation_source parameter. That
-- means the automated reconciliation credential could pass 'OPERATOR' (or
-- an operator action could pass 'PROVIDER_CALLBACK'), producing an audit
-- trail that misrepresents which trusted path actually made the
-- physical-redial authorization decision -- an audit-integrity defect,
-- not merely a cosmetic one, for a decision this safety-critical.
--
-- THE FIX: split into three functions.
--   fn_reconcile_dispatch_outcome_internal() -- the actual state-transition
--     + audit logic (identical to the prior single function's body), but
--     NEVER granted EXECUTE to any app_* role at all. It takes an
--     ALREADY-DETERMINED p_reconciliation_source/p_actor_type -- it is not
--     itself a decision point, only a mechanism, and is reachable only via
--     the two wrappers below calling it internally under their own
--     SECURITY DEFINER owner privileges (the identical pattern already
--     used for campaign.fn_new_uuid_v7()/voice.fn_new_uuid_v7() -- a
--     function nobody is ever directly granted EXECUTE on, callable only
--     through another SECURITY DEFINER function's own internal call).
--   fn_reconcile_dispatch_from_provider() -- EXECUTE granted ONLY to
--     app_voice_reconciler. Accepts a source choice restricted, by a CHECK
--     inside the function body, to PROVIDER_CALLBACK | PROVIDER_LOOKUP --
--     'OPERATOR' is not a legal value here even if somehow supplied, and
--     hardcodes actor_type='WORKER'. There is no code path by which this
--     function can record OPERATOR provenance.
--   fn_reconcile_dispatch_by_operator() -- EXECUTE granted ONLY to
--     app_platform_admin. Takes NO source parameter at all -- provenance
--     is hardcoded to 'OPERATOR' and actor_type='PLATFORM_ADMIN' inside the
--     function body. There is no parameter by which a caller could request
--     PROVIDER_CALLBACK/PROVIDER_LOOKUP provenance through this path.
--
-- This makes INV-RECON-01/02/04/05/06 (6H §51) true by construction: the
-- database itself, not caller-supplied metadata and not application-layer
-- trust, determines which provenance category a given EXECUTE grant can
-- ever produce. p_reconciled_by remains pure free-text metadata in both
-- wrappers, exactly as before -- never read in any authorization decision.
-- -----------------------------------------------------------------

DROP FUNCTION IF EXISTS voice.fn_reconcile_dispatch_outcome(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT,TEXT);

CREATE OR REPLACE FUNCTION voice.fn_reconcile_dispatch_outcome_internal(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_outcome                  TEXT,   -- 'CONFIRMED' | 'FAILED'
  p_reconciliation_source    TEXT,   -- already validated/hardcoded by the calling wrapper -- not re-validated against caller input here
  p_actor_type               TEXT,   -- already determined by the calling wrapper: 'WORKER' | 'PLATFORM_ADMIN'
  p_reconciled_by            TEXT,   -- free-text actor/system identity -- metadata only, NEVER authorization
  p_provider_call_ref        TEXT DEFAULT NULL,
  p_note                     TEXT DEFAULT NULL
)
RETURNS TABLE(reconciled BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
DECLARE
  v_rows      INTEGER;
  v_row       voice.call_dispatch_keys%ROWTYPE;
  v_old_state TEXT;
BEGIN
  IF p_outcome NOT IN ('CONFIRMED','FAILED') THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_outcome_internal: invalid p_outcome %, must be CONFIRMED or FAILED', p_outcome;
  END IF;

  -- Defense in depth only -- by construction, every real caller is one of
  -- the two wrappers below, which never pass anything else.
  IF p_reconciliation_source NOT IN ('PROVIDER_CALLBACK','PROVIDER_LOOKUP','OPERATOR') THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_outcome_internal: invalid p_reconciliation_source %', p_reconciliation_source;
  END IF;

  IF p_outcome = 'CONFIRMED' AND (p_provider_call_ref IS NULL OR length(p_provider_call_ref) = 0) THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_outcome_internal: p_provider_call_ref is required when p_outcome = CONFIRMED';
  END IF;

  -- FAILED reopens physical retry eligibility -- never accepted without an
  -- explicit evidence description (also enforced by
  -- chk_cdk_reconciled_failed_has_evidence, defense in depth).
  IF p_outcome = 'FAILED' AND (p_note IS NULL OR length(btrim(p_note)) = 0) THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_outcome_internal: p_note (evidence description) is required when p_outcome = FAILED';
  END IF;

  SELECT dispatch_state INTO v_old_state
  FROM voice.call_dispatch_keys
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id;

  UPDATE voice.call_dispatch_keys
  SET dispatch_state = p_outcome,
      provider_call_ref = CASE WHEN p_outcome = 'CONFIRMED' THEN p_provider_call_ref ELSE provider_call_ref END,
      confirmed_at = CASE WHEN p_outcome = 'CONFIRMED' THEN NOW() ELSE confirmed_at END,
      last_error = COALESCE(p_note, last_error),
      reconciliation_source = p_reconciliation_source,
      reconciled_by = p_reconciled_by,
      reconciled_at = NOW(),
      claimed_by = NULL,
      claim_expires_at = NULL
  WHERE dispatch_idempotency_key = p_dispatch_idempotency_key
    AND organization_id = p_organization_id
    AND dispatch_state IN ('SUBMITTING', 'AMBIGUOUS')  -- ONLY these two -- CONFIRMED->FAILED is impossible by construction
  RETURNING * INTO v_row;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    -- Not found, wrong tenant, or wrong state (including CONFIRMED/FAILED/
    -- RESERVED/CLAIMED) -- deliberately one generic, non-disclosing reason
    -- for all three, matching this schema's established convention.
    RETURN QUERY SELECT FALSE, 'NOT_RECONCILABLE_OR_NOT_FOUND'::TEXT;
    RETURN;
  END IF;

  -- Durable audit evidence for this safety-critical transition. actor_type
  -- is whatever the calling wrapper determined -- never derived from
  -- p_reconciliation_source or any other caller-suppliable value here.
  -- resource_snapshot carries no phone/PII data -- voice.call_dispatch_keys
  -- itself stores none.
  PERFORM audit.fn_insert_audit_event(
    p_organization_id   => p_organization_id,
    p_actor_type        => p_actor_type,
    p_actor_ref         => NULL,
    p_actor_name        => p_reconciled_by,
    p_action_kind       => 'VOICE_DISPATCH_RECONCILED',
    p_resource_type     => 'voice.call_dispatch_keys',
    p_resource_id       => v_row.call_session_id,
    p_outcome           => 'SUCCESS',
    p_failure_reason    => NULL,
    p_ip_address        => NULL,
    p_user_agent        => NULL,
    p_session_id        => NULL,
    p_request_id        => NULL,
    p_correlation_id    => NULL,
    p_resource_snapshot => jsonb_build_object(
      'dispatch_idempotency_key', p_dispatch_idempotency_key,
      'old_state', v_old_state,
      'new_state', p_outcome,
      'reconciliation_source', p_reconciliation_source,
      'provider_call_ref', v_row.provider_call_ref
    )
  );

  RETURN QUERY SELECT TRUE, NULL::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_reconcile_dispatch_outcome_internal(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
-- Deliberately NOT granted to ANY app_* role, including app_voice_reconciler
-- and app_platform_admin -- callable only via the two wrappers below, which
-- invoke it under their own SECURITY DEFINER owner privileges (app_migration),
-- identical to the fn_new_uuid_v7() bridge-function pattern (§A).


-- -----------------------------------------------------------------
-- fn_reconcile_dispatch_from_provider: the automated reconciliation path.
-- Callable ONLY by app_voice_reconciler. p_provider_source is restricted to
-- the two provider-evidence categories -- 'OPERATOR' is not an accepted
-- value here under any circumstance, so this credential cannot record
-- itself as an operator/admin decision no matter what a caller supplies.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_reconcile_dispatch_from_provider(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_outcome                  TEXT,   -- 'CONFIRMED' | 'FAILED'
  p_provider_source          TEXT,   -- 'PROVIDER_CALLBACK' | 'PROVIDER_LOOKUP' ONLY
  p_reconciled_by            TEXT,   -- stable service identity (e.g. the callback handler's own name) -- metadata only
  p_provider_call_ref        TEXT DEFAULT NULL,
  p_note                     TEXT DEFAULT NULL
)
RETURNS TABLE(reconciled BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
BEGIN
  IF p_provider_source NOT IN ('PROVIDER_CALLBACK','PROVIDER_LOOKUP') THEN
    RAISE EXCEPTION 'fn_reconcile_dispatch_from_provider: invalid p_provider_source % -- only PROVIDER_CALLBACK or PROVIDER_LOOKUP may be recorded through this capability; OPERATOR provenance cannot be produced by the automated reconciliation path', p_provider_source;
  END IF;

  RETURN QUERY SELECT * FROM voice.fn_reconcile_dispatch_outcome_internal(
    p_dispatch_idempotency_key, p_organization_id, p_outcome,
    p_provider_source,   -- restricted above to the two legal provider values
    'WORKER',            -- hardcoded -- never derived from any parameter
    p_reconciled_by, p_provider_call_ref, p_note
  );
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_reconcile_dispatch_from_provider(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_reconcile_dispatch_from_provider(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO app_voice_reconciler;


-- -----------------------------------------------------------------
-- fn_reconcile_dispatch_by_operator: the human/operator reconciliation
-- path. Callable ONLY by app_platform_admin (the existing break-glass/
-- operator role, `087_5B1.sql` -- no second new role introduced for this).
-- Takes NO source parameter at all -- 'OPERATOR' is hardcoded, so this
-- credential cannot record PROVIDER_CALLBACK/PROVIDER_LOOKUP provenance no
-- matter what evidence an operator believes they have; a genuinely
-- provider-sourced signal must go through fn_reconcile_dispatch_from_provider
-- (i.e. through the automated path), never through this one.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_reconcile_dispatch_by_operator(
  p_dispatch_idempotency_key CHAR(64),
  p_organization_id          UUID,
  p_outcome                  TEXT,   -- 'CONFIRMED' | 'FAILED'
  p_reconciled_by            TEXT,   -- authenticated admin identity, supplied by the application layer -- metadata only
  p_provider_call_ref        TEXT DEFAULT NULL,
  p_note                     TEXT DEFAULT NULL
)
RETURNS TABLE(reconciled BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, pg_catalog
AS $$
BEGIN
  RETURN QUERY SELECT * FROM voice.fn_reconcile_dispatch_outcome_internal(
    p_dispatch_idempotency_key, p_organization_id, p_outcome,
    'OPERATOR',           -- hardcoded -- no parameter can override this
    'PLATFORM_ADMIN',     -- hardcoded -- never derived from any parameter
    p_reconciled_by, p_provider_call_ref, p_note
  );
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_reconcile_dispatch_by_operator(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_reconcile_dispatch_by_operator(CHAR(64),UUID,TEXT,TEXT,TEXT,TEXT) TO app_platform_admin;

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
--   05. Ambiguous provider outcomes require reconciliation
--       (fn_reconcile_dispatch_from_provider() / fn_reconcile_dispatch_
--       by_operator()), never a blind redial.
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
--   provider-retry contract (3B §19) and by fn_reconcile_dispatch_from_
--   provider()/fn_reconcile_dispatch_by_operator() (operator/callback-
--   driven resolution), not eliminated by the database alone -- stated
--   plainly rather than claimed away.
-- =================================================================

-- =================================================================
-- §G. Audit governance note (documentation-only, zero additional SQL):
--   this migration's fn_reconcile_dispatch_outcome_internal() (called from
--   both fn_reconcile_dispatch_from_provider() and fn_reconcile_dispatch_
--   by_operator()) writes a 'VOICE_DISPATCH_RECONCILED' audit event via
--   audit.fn_insert_audit_event()
--   (5J §14.2 / 6D §24.0's sole legal write path). audit.audit_events.
--   action_kind is TEXT with only a length CHECK (chk_ae_action_kind,
--   072_5J.sql), not a CHECK...IN(...) enum and not backed by a lookup
--   table -- identical precedent to every prior phase's own new action_kind
--   value (6C/6D/6F/6G, most recently 077_5J1.sql's ten-value governance
--   amendment). 'VOICE_DISPATCH_RECONCILED' is therefore usable today with
--   zero schema change; it is recorded here, and in 5C-Voice-Schema.md's
--   canonical vocabulary list, as a governance amendment only.
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
--   A trusted, authenticated provider status-callback-processing service
--   (running as app_voice_reconciler), upon positively correlating an
--   inbound callback to this dispatch_idempotency_key (via
--   provider_request_ref), calls fn_reconcile_dispatch_from_provider() --
--   the ONLY function it can call, and the ONLY function that can ever
--   record PROVIDER_CALLBACK/PROVIDER_LOOKUP provenance. A privileged
--   operator (running as app_platform_admin, per a controlled, audited
--   procedure backed by provider-console evidence) instead calls
--   fn_reconcile_dispatch_by_operator() -- the ONLY function it can call,
--   and the ONLY function that can ever record OPERATOR provenance; it has
--   no source parameter to override this. Neither role can call the
--   other's function, so neither credential can misrepresent which trusted
--   path actually made the decision (micro-fix, this pass -- 6H §5 finding
--   27). Both resolve a SUBMITTING or AMBIGUOUS row to its true terminal
--   outcome -- this is the only path that resolves a crash that occurred
--   strictly between step 3's COMMIT and step 5's recording (Case B/C, §B
--   above). ORDINARY app_api/app_worker callers CANNOT call either
--   function -- EXECUTE is revoked from both (micro-remediation,
--   reconciliation authorization boundary, prior pass) -- see each
--   function's own header comment for the full authorization/provenance
--   model, and 6H §5 findings 26–27 for why this was a genuine, closed
--   defect, not a design choice restated.
-- =================================================================
