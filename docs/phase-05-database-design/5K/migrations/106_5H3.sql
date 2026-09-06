-- =================================================================
-- Migration 106 (Phase 5H.3): platform-admin quota override +
-- guarded refund saga (reserve / settle / fail)
-- down_revision: 105_5B4
-- Transaction: yes
-- Source: Phase 6M Admin/Platform Control-Plane API design
--
-- Two independent, additive changes over already-frozen billing
-- persistence (048_5H, 052_5H, 055_5H). None of 001-104 is edited.
--
-- (1) Quota override lifecycle (6M Block 1 §18). 052_5H.sql's
--     billing.quota_configs has soft_limit/hard_limit/override_reason
--     but no effective-dating or attribution columns, so an override's
--     "as of when" and "set by whom" cannot be answered from persistence
--     today — a genuine schema gap, closed here additively.
--     `metric` is deliberately left without a table-level CHECK: 5H
--     §11.1 documents the usage-dimension enum as application-layer-
--     validated by design ("New metrics are new data rows, not schema
--     migrations"), matching usage_events.metric's own un-constrained
--     TEXT column. Adding a DB CHECK here would contradict that
--     documented extensibility choice for the very same enum, so the
--     metric allow-list required by §18 is enforced inside
--     fn_platform_set_quota_override() instead — the only mutation path
--     available once app_platform_admin's raw DML is revoked below.
--     The upsert uses ON CONFLICT (organization_id, metric) DO UPDATE,
--     which is atomically serialized by Postgres on the existing
--     uq_qc_org_metric unique constraint — no additional API-layer or
--     function-internal locking is needed for this one-row-keyed write.
--
-- (2) Refund saga (6M Block 1 §28, §40-42). 055_5H.sql's
--     fn_validate_refund_amount is a BEFORE INSERT trigger doing an
--     unlocked SELECT SUM(...) against billing.refunds — two concurrent
--     refund INSERTs against the same payment_attempt_id can both read
--     the same pre-insert sum and both pass the check before either
--     commits, over-refunding the original payment. This is a real,
--     reproducible race in the existing trigger (confirmed by reading
--     055_5H.sql in full), not a hypothetical one.
--
--     The fix is a three-phase saga, never a single INSERT-and-call-the-
--     provider endpoint (6A: never hold a DB transaction open across an
--     external network call):
--       reserve  -> fn_platform_reserve_refund: takes a function-internal
--                   SELECT ... FOR UPDATE lock on the specific
--                   payment_attempts row (the same pattern 087_5B1's
--                   fn_break_glass_release already uses for single-row
--                   transition safety — not API-layer locking), then
--                   re-runs the sum check under that lock and inserts a
--                   PENDING billing.refunds row. Commits and returns
--                   before any provider call is made.
--       (network)-> the application layer calls the payment provider
--                   with the reservation's refund id as an idempotency
--                   key, entirely outside any open DB transaction.
--       settle/fail -> fn_platform_settle_refund / fn_platform_fail_refund
--                   transition the PENDING row to its terminal state in
--                   a second, independent transaction, keyed by
--                   provider_refund_id (settle) or a bounded failure
--                   reason (fail). Both are idempotent no-ops if the
--                   row is already in that terminal state, so a retried
--                   webhook/poll after a lost response cannot double-
--                   apply.
--     billing.refunds.provider_refund_id (NOT NULL in 055_5H.sql) is
--     relaxed to nullable here, because the provider has not yet
--     assigned one at reserve time; a new CHECK enforces it is always
--     present once a refund reaches SUCCEEDED. fn_validate_refund_amount
--     (055_5H.sql) is left completely unedited and keeps firing on every
--     INSERT as a second, defense-in-depth check — it is simply no
--     longer the *only* check, and the new lock above makes it race-free
--     in practice because the reserving transaction already holds the
--     relevant payment_attempts row lock before the trigger's SELECT
--     SUM runs.
--
--     app_platform_admin's raw INSERT/UPDATE/DELETE on
--     billing.refunds, billing.payment_attempts, and
--     billing.quota_configs (all granted in 048_5H/052_5H/055_5H.sql,
--     unedited here) is REVOKEd — SELECT is retained on all three for
--     read-side support/reconciliation views (6M §25-31). app_api's and
--     app_worker's own existing grants on these tables are untouched;
--     this migration narrows only the platform-admin surface, per 6M
--     Block 1's "Platform Admin is not a database superuser" invariant.
--     Because the new functions are SECURITY DEFINER, they execute with
--     their owning role's privileges regardless of this revoke.
--
-- Billing-account manual suspend/reactivate (6M Block 1 §30) and the
-- refund reversal-target policy (6M Block 1 §29, DEC-6M-REFUND-01) are
-- deliberately NOT resolved by SQL here — the former is recorded as an
-- open owner decision in the 6M document, the latter is a policy choice
-- with a stated recommendation, neither requires new persistence to
-- state the recommendation, and nothing here forecloses either answer.
--
-- (0) CRITICAL SECURITY FIX — organization.is_platform_admin() fail-open
--     NULL bug (discovered by 6M live adversarial validation on
--     phase6m-pg18-incr, TEST 7 of the consolidated security battery).
--     001_5B.sql defines:
--       SELECT current_setting('app.is_platform_admin', true) = 'true'
--     current_setting(name, missing_ok=>true) returns SQL NULL — not
--     'false', not '' — when a custom GUC has never been SET (or RESET)
--     at all in the current session/connection. 'NULL = ''true''' is
--     NULL, so is_platform_admin() itself returns NULL, not FALSE, in
--     that state. Every gated function in 087_5B1.sql (frozen),
--     105_5B4.sql, and this file guards its privileged body with
--     `IF NOT organization.is_platform_admin() THEN RAISE EXCEPTION ...
--     END IF;` (fn_break_glass_check instead does `... THEN RETURN
--     FALSE; END IF;`, same underlying condition). PL/pgSQL's IF
--     treats a NULL condition identically to FALSE: the guard's own
--     branch is skipped — so RAISE/RETURN FALSE never fires — and
--     execution falls through into the privileged body. Confirmed live:
--     a brand-new connection that never touches app.is_platform_admin
--     calls fn_platform_suspend_organization(...) and it SUCCEEDS
--     (returns SUSPENDED) instead of raising "caller is not
--     authorized." This directly violates the fail-closed invariant
--     required of the break-glass/platform-admin model and is a
--     pre-existing defect inherited from Phase 5B, not something
--     introduced by 105_5B4/106_5H3 — but 001_5B.sql is frozen
--     (migrations 001-104 are never edited), so the fix is applied here
--     as a CREATE OR REPLACE of the same function, which overrides
--     001_5B.sql's definition for every existing and future caller
--     (including the still-frozen 087_5B1.sql functions and the
--     break_glass_grants RLS policy that reference it by name) without
--     touching or re-checksumming 001_5B.sql itself. The fix wraps the
--     comparison in COALESCE so a never-set GUC now evaluates to the
--     same proper, non-NULL FALSE that an explicit RESET already
--     produced (the discrepancy this validation run exposed): a missing
--     admin context is now indistinguishable, at every call site, from
--     an explicit "not an admin" — fail-closed in both cases.
-- =================================================================

-- -----------------------------------------------------------------
-- (0) Security fix: organization.is_platform_admin() must never
--     evaluate to NULL — see rationale above.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT COALESCE(current_setting('app.is_platform_admin', true), 'false') = 'true'
$$;

COMMENT ON FUNCTION organization.is_platform_admin() IS 'Controlled amendment (106_5H3, 2026-09-03): CREATE OR REPLACE over 001_5B.sqls definition (not edited) to close a fail-open NULL bug — current_setting() on a never-SET custom GUC returns NULL, which every `IF NOT is_platform_admin() THEN RAISE/RETURN` guard treated as FALSE (branch skipped), silently admitting an unauthenticated caller. COALESCE forces a proper FALSE default. See 6M-Admin-Platform-APIs.md Owner Decisions / Findings.';

-- -----------------------------------------------------------------
-- (1) Quota override lifecycle
-- -----------------------------------------------------------------

ALTER TABLE billing.quota_configs
  ADD COLUMN effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN expires_at     TIMESTAMPTZ NULL,
  ADD COLUMN updated_by     UUID NULL;

COMMENT ON COLUMN billing.quota_configs.effective_from IS 'When this override took effect. Set by fn_platform_set_quota_override(); not client-suppliable.';
COMMENT ON COLUMN billing.quota_configs.expires_at IS 'Optional override expiration (6M §18). NULL = no expiration. EXPIRED is computed at read time from expires_at < NOW(), never written, matching the crm.contact_suppressions / break_glass_grants pattern.';
COMMENT ON COLUMN billing.quota_configs.updated_by IS 'logical ref: identity.users.id — platform admin who last set this override (5A convention, no cross-schema FK).';

ALTER TABLE billing.quota_configs
  ADD CONSTRAINT chk_qc_expires_after_effective CHECK (expires_at IS NULL OR expires_at > effective_from);

CREATE OR REPLACE FUNCTION billing.fn_platform_set_quota_override(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_metric          TEXT,
  p_soft_limit      NUMERIC,
  p_hard_limit      NUMERIC,
  p_reason          TEXT,
  p_expires_at      TIMESTAMPTZ DEFAULT NULL,
  p_unit_label      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE
  v_id UUID;
  v_unit_label TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: caller is not authorized.';
  END IF;

  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_admin_user_id is required.';
  END IF;

  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_reason must be between 10 and 2000 characters.';
  END IF;

  IF NOT (p_metric = ANY (ARRAY[
      'CALL_MINUTES','AI_MINUTES','STT_SECONDS','TTS_CHARACTERS',
      'LLM_PROMPT_TOKENS','LLM_COMPLETION_TOKENS','EMBEDDING_TOKENS',
      'CAMPAIGN_CALLS','WORKFLOW_EXECUTIONS','TOOL_EXECUTIONS',
      'KNOWLEDGE_RETRIEVALS','STORAGE_GB','API_REQUESTS',
      'ACTIVE_AGENTS','ACTIVE_PHONE_NUMBERS'
    ])) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: metric % is outside the 5H §11.1 usage-dimension allow-list.', p_metric;
  END IF;

  IF p_expires_at IS NOT NULL AND p_expires_at <= NOW() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_expires_at must be in the future.';
  END IF;

  -- billing.quota_configs.unit_label (052_5H.sql) is a caller-supplied
  -- NOT NULL display label with no DB-level allow-list of its own (it is
  -- not a security-relevant field — it never gates an authorization
  -- decision). When the caller does not supply one, fall back to the
  -- 5H §11.1 metric's own conventional unit so this function can create
  -- a brand-new quota_configs row for a metric that has never had one,
  -- not just update an existing row's limits. A future call that omits
  -- p_unit_label on an existing row resets it to this same convention
  -- rather than silently preserving a prior custom label — acceptable
  -- because the label is descriptive metadata, not authoritative state.
  v_unit_label := COALESCE(p_unit_label, CASE p_metric
    WHEN 'CALL_MINUTES'          THEN 'minutes'
    WHEN 'AI_MINUTES'            THEN 'minutes'
    WHEN 'STT_SECONDS'           THEN 'seconds'
    WHEN 'TTS_CHARACTERS'        THEN 'characters'
    WHEN 'LLM_PROMPT_TOKENS'     THEN 'tokens'
    WHEN 'LLM_COMPLETION_TOKENS' THEN 'tokens'
    WHEN 'EMBEDDING_TOKENS'      THEN 'tokens'
    WHEN 'CAMPAIGN_CALLS'        THEN 'calls'
    WHEN 'WORKFLOW_EXECUTIONS'   THEN 'executions'
    WHEN 'TOOL_EXECUTIONS'       THEN 'executions'
    WHEN 'KNOWLEDGE_RETRIEVALS'  THEN 'retrievals'
    WHEN 'STORAGE_GB'            THEN 'GB'
    WHEN 'API_REQUESTS'          THEN 'requests'
    WHEN 'ACTIVE_AGENTS'         THEN 'agents'
    WHEN 'ACTIVE_PHONE_NUMBERS'  THEN 'phone_numbers'
  END);

  -- soft_limit/hard_limit/ordering are still enforced by 052_5H.sql's
  -- own chk_qc_soft_limit / chk_qc_hard_limit / chk_qc_limits_order.
  INSERT INTO billing.quota_configs (
    organization_id, metric, soft_limit, hard_limit, override_reason,
    effective_from, expires_at, updated_by, unit_label
  ) VALUES (
    p_organization_id, p_metric, p_soft_limit, p_hard_limit, p_reason,
    NOW(), p_expires_at, p_admin_user_id, v_unit_label
  )
  ON CONFLICT ON CONSTRAINT uq_qc_org_metric DO UPDATE SET
    soft_limit     = EXCLUDED.soft_limit,
    hard_limit     = EXCLUDED.hard_limit,
    override_reason = EXCLUDED.override_reason,
    effective_from = EXCLUDED.effective_from,
    expires_at     = EXCLUDED.expires_at,
    updated_by     = EXCLUDED.updated_by,
    unit_label     = EXCLUDED.unit_label,
    updated_at     = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) TO app_api, app_platform_admin;

REVOKE INSERT, UPDATE, DELETE ON billing.quota_configs FROM app_platform_admin;

-- -----------------------------------------------------------------
-- (2) Refund saga: reserve / settle / fail
-- -----------------------------------------------------------------

ALTER TABLE billing.refunds
  ALTER COLUMN provider_refund_id DROP NOT NULL;

ALTER TABLE billing.refunds
  ADD COLUMN failure_reason TEXT NULL;

COMMENT ON COLUMN billing.refunds.provider_refund_id IS 'NULL while status = PENDING (assigned by the provider on the out-of-transaction network call); required once status = SUCCEEDED, enforced by chk_ref_provider_refund_id_when_succeeded.';
COMMENT ON COLUMN billing.refunds.failure_reason IS 'Bounded support-facing reason set by fn_platform_fail_refund() when a reservation cannot be completed. Not payment-provider secret material.';

ALTER TABLE billing.refunds
  ADD CONSTRAINT chk_ref_provider_refund_id_when_succeeded
    CHECK (status <> 'SUCCEEDED' OR provider_refund_id IS NOT NULL);

ALTER TABLE billing.refunds
  ADD CONSTRAINT chk_ref_failure_reason_len
    CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000);

CREATE OR REPLACE FUNCTION billing.fn_platform_reserve_refund(
  p_organization_id    UUID,
  p_admin_user_id      UUID,
  p_payment_attempt_id UUID,
  p_amount             NUMERIC(18,4),
  p_currency           CHAR(3),
  p_reason             TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE
  v_pa       billing.payment_attempts%ROWTYPE;
  v_refunded NUMERIC(18,4);
  v_refund_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: caller is not authorized.';
  END IF;

  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: p_admin_user_id is required.';
  END IF;

  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: p_reason must be between 10 and 2000 characters.';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: p_amount must be positive.';
  END IF;

  -- Function-internal single-row lock (the fn_break_glass_release
  -- pattern, 087_5B1) — closes the race in 055_5H.sql's
  -- fn_validate_refund_amount by serializing concurrent reservations
  -- against the same payment_attempt_id here, before either commits.
  SELECT * INTO v_pa
  FROM billing.payment_attempts
  WHERE id = p_payment_attempt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: payment attempt % not found.', p_payment_attempt_id;
  END IF;

  IF v_pa.organization_id <> p_organization_id THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: payment attempt % does not belong to organization %.', p_payment_attempt_id, p_organization_id;
  END IF;

  IF v_pa.status <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: payment attempt % is not SUCCEEDED (REFUND_NOT_ALLOWED).', p_payment_attempt_id;
  END IF;

  IF p_currency <> v_pa.amount_currency THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: currency % does not match the original payment currency %.', p_currency, v_pa.amount_currency;
  END IF;

  SELECT COALESCE(SUM(r.amount_amount), 0) INTO v_refunded
  FROM billing.refunds r
  WHERE r.payment_attempt_id = p_payment_attempt_id
    AND r.status IN ('PENDING', 'SUCCEEDED');

  IF (v_refunded + p_amount) > v_pa.amount_amount THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: refund amount % would exceed the remaining refundable balance (REFUND_AMOUNT_EXCEEDED).', p_amount;
  END IF;

  INSERT INTO billing.refunds (
    organization_id, payment_attempt_id, payment_provider, provider_refund_id,
    amount_amount, amount_currency, reason, status
  ) VALUES (
    p_organization_id, p_payment_attempt_id, v_pa.payment_provider, NULL,
    p_amount, p_currency, p_reason, 'PENDING'
  )
  RETURNING id INTO v_refund_id;

  RETURN v_refund_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_reserve_refund(UUID, UUID, UUID, NUMERIC, CHAR(3), TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_platform_reserve_refund(UUID, UUID, UUID, NUMERIC, CHAR(3), TEXT) TO app_api, app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_platform_settle_refund(
  p_refund_id          UUID,
  p_admin_user_id      UUID,
  p_provider_refund_id TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: caller is not authorized.';
  END IF;

  IF p_provider_refund_id IS NULL OR length(p_provider_refund_id) < 1 THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: p_provider_refund_id is required.';
  END IF;

  SELECT status INTO v_status
  FROM billing.refunds
  WHERE id = p_refund_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: refund % not found.', p_refund_id;
  END IF;

  IF v_status = 'SUCCEEDED' THEN
    RETURN v_status; -- idempotent no-op: safe retry after a lost response
  END IF;

  IF v_status = 'FAILED' THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: refund % is already FAILED (terminal state).', p_refund_id;
  END IF;

  UPDATE billing.refunds
  SET status = 'SUCCEEDED', provider_refund_id = p_provider_refund_id, completed_at = NOW()
  WHERE id = p_refund_id;

  RETURN 'SUCCEEDED';
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_settle_refund(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_platform_settle_refund(UUID, UUID, TEXT) TO app_api, app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_platform_fail_refund(
  p_refund_id      UUID,
  p_admin_user_id  UUID,
  p_failure_reason TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_fail_refund: caller is not authorized.';
  END IF;

  IF p_failure_reason IS NOT NULL AND length(p_failure_reason) > 2000 THEN
    RAISE EXCEPTION 'fn_platform_fail_refund: p_failure_reason exceeds 2000 characters.';
  END IF;

  SELECT status INTO v_status
  FROM billing.refunds
  WHERE id = p_refund_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_fail_refund: refund % not found.', p_refund_id;
  END IF;

  IF v_status = 'FAILED' THEN
    RETURN v_status; -- idempotent no-op
  END IF;

  IF v_status = 'SUCCEEDED' THEN
    RAISE EXCEPTION 'fn_platform_fail_refund: refund % is already SUCCEEDED (terminal state).', p_refund_id;
  END IF;

  UPDATE billing.refunds
  SET status = 'FAILED', failure_reason = p_failure_reason, completed_at = NOW()
  WHERE id = p_refund_id;

  RETURN 'FAILED';
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_fail_refund(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_platform_fail_refund(UUID, UUID, TEXT) TO app_api, app_platform_admin;

REVOKE INSERT, UPDATE, DELETE ON billing.refunds FROM app_platform_admin;
REVOKE INSERT, UPDATE, DELETE ON billing.payment_attempts FROM app_platform_admin;
