-- =================================================================
-- Migration 107 (Phase 5B.5): Platform Admin trust-boundary hardening
-- down_revision: 106_5H3
-- Transaction: yes
-- Source: 6M STRICT FINAL REMEDIATION SS1, SS3, SS4, SS6, SS7, SS9
-- =================================================================
--
-- This is a forward, additive migration. It does NOT edit 001-104
-- (frozen) and does NOT edit 105_5B4.sql or 106_5H3.sql's own text
-- (both left byte-identical). It CREATE OR REPLACEs functions those
-- files defined, and narrows/extends GRANTs those files (and
-- 018_5C.sql) issued -- the same override technique 106_5H3.sql
-- already used against 001_5B.sql's is_platform_admin().
--
-- Six independent defects are fixed, each traced to an exact prior
-- migration:
--
-- (A) P0 SELF-FORGERY (SS1). organization.is_platform_admin()
--     (001_5B.sql, COALESCE-patched by 106_5H3.sql) trusts a single
--     session GUC that an ordinary app_api session can itself SET.
--     Fixed by additionally binding to session_user = 'app_platform_
--     admin' -- the actual authenticated connecting role, fixed at
--     connection time by the credential used, not settable by SQL.
--     session_user (not current_user) is required because SECURITY
--     DEFINER callers change current_user to the function owner;
--     072_5J.sql's own fn_insert_audit_event already documents and
--     relies on this exact session_user-vs-current_user distinction.
--     Every privileged function that calls is_platform_admin() is
--     hardened transitively by this one change, with no edits to
--     their own bodies required for the identity check itself.
--
-- (B) P0/P1 OVER-BROAD GRANTS (SS1, SS2-G). 087_5B1.sql and 105_5B4.sql
--     GRANT EXECUTE ... TO app_api, app_platform_admin on every
--     break-glass/org-lifecycle function; 106_5H3.sql does the same
--     for quota-override and refund-reserve. Since (A) closes the
--     GUC-forgery path, an app_api session can no longer satisfy
--     is_platform_admin() -- but least-privilege still requires these
--     EXECUTE grants be narrowed to app_platform_admin only, removing
--     app_api's grant entirely rather than leaving a redundant one.
--
-- (C) P0 RAW SENSITIVE-MEDIA ACCESS (SS3, SS4). 018_5C.sql's finalization
--     pass issued a blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON
--     ALL TABLES IN SCHEMA voice TO app_platform_admin`. Combined with
--     BYPASSRLS (001_5B.sql), this lets app_platform_admin directly
--     SELECT voice.recordings.storage_ref, voice.transcript_segments.
--     text, voice.conversations.summary_text, and voice.turns.
--     utterance_text/response_text -- i.e. raw call-recording pointers
--     and transcript/summary content -- across every tenant, with no
--     break-glass, no purpose, no audit. This is superseded here with
--     REVOKE ALL + column-level GRANT SELECT that excludes exactly
--     those content columns, plus two new guarded SECURITY DEFINER
--     functions (fn_platform_access_recording, fn_platform_access_
--     transcript) that are the only path back to that content, gated
--     on a durable SENSITIVE_MEDIA_ACCESS break-glass grant bound to
--     org + admin + session, with resource-ownership cross-checked
--     against the grant's organization_id, and an atomic audit write
--     containing only IDs (never storage_ref, never transcript text).
--     This closes SS6 (transcript break-glass parity) in the same
--     change as recording support -- both use the identical guard.
--
-- (D) P1 REFUND FABRICATION (SS7). 106_5H3.sql's fn_platform_settle_
--     refund/fn_platform_fail_refund accept a caller-supplied
--     p_provider_refund_id with no independent verification, and are
--     callable by app_platform_admin (a human support connection) --
--     meaning a human could mark a refund SUCCEEDED with a fabricated
--     provider reference. This introduces a new dedicated, non-admin,
--     non-superuser principal app_billing_reconciler (LOGIN only, no
--     BYPASSRLS -- the exact CREATE ROLE ... LOGIN pattern 099_5C1.sql
--     already established for app_voice_reconciler) and re-points
--     EXECUTE on both settle/fail functions to it exclusively,
--     REVOKEd from both app_api and app_platform_admin. Provider truth
--     must now flow through the trusted backend calling as this
--     principal after an actual PaymentProviderPort response -- never
--     through an interactive Platform Admin session. reserve_refund is
--     unaffected (it does not assert settlement truth) beyond the
--     general app_api narrowing in (B).
--
-- (E) P1 AUDIT NOT ATOMIC (SS9). 105_5B4.sql's own header comment
--     states plainly that its break-glass and org-lifecycle functions
--     do not call audit.fn_insert_audit_event() internally -- "two
--     separate calls made by the application layer, not fused inside
--     the DB function" -- so a crash/bug between the state COMMIT and
--     the application's later audit-insert call leaves an unaudited
--     privileged mutation. 106_5H3.sql's quota-override and refund-
--     reserve functions have the same gap. Every guarded mutation
--     function touched by this migration now performs its audit write
--     via audit.fn_insert_audit_event() in the SAME transaction as its
--     state change, immediately before RETURN, using the existing
--     16-parameter signature from 072_5J.sql (already GRANTed to
--     app_platform_admin/app_worker; no new GRANT needed). Because
--     fn_insert_audit_event requires p_organization_id to equal
--     organization.current_tenant_id() for non-platform events, each
--     function first binds tenant context transaction-locally via
--     `PERFORM set_config('app.tenant_id', <already-row-validated-
--     org-id>::text, true)` -- safe because that org id is not raw
--     caller input, it is the same id the function's own row lock/
--     ownership check already independently validated. This also
--     satisfies DEC-6M-03B (tenants can see Platform Admin actions
--     against their own org in their own audit trail), since the
--     resulting row lands in the tenant-scoped, non-platform audit
--     stream. fn_break_glass_release and the two refund-settlement
--     functions additionally now SELECT organization_id (previously
--     only status) under their existing FOR UPDATE lock so they have
--     a validated org id to bind. fn_platform_suspend_organization /
--     fn_platform_reactivate_organization also now persist the
--     previously-silently-discarded p_reason into the audit row's
--     resource_snapshot (105_5B4.sql validated its length but never
--     stored it anywhere -- SS11 documentation correction).
--
-- (F) Vocabulary note (SS6, SS9). Two new audit action_kind values are
--     introduced by the calls added here: ORGANIZATION_SUSPENDED,
--     ORGANIZATION_REACTIVATED, and TRANSCRIPT_ACCESS_GRANTED.
--     audit.audit_events.action_kind (072_5J.sql) is unconstrained free
--     text (`CHECK (length(action_kind) BETWEEN 1 AND 200)` only, no
--     enum/lookup table) so this requires NO schema change here -- it
--     is a documentation-level 5J vocabulary amendment, tracked
--     separately in 5J-Analytics-Audit-Schema.md and 6M-Admin-
--     Platform-APIs.md. BREAK_GLASS_GRANTED, BREAK_GLASS_RELEASED,
--     QUOTA_OVERRIDE_SET, REFUND_RESERVED, REFUND_SETTLED, REFUND_
--     FAILED, and RECORDING_ACCESS_GRANTED already exist in that
--     vocabulary and are reused as-is.
--
-- Nothing here reopens Phase 6L's frozen analytics/RBAC decisions,
-- changes the tenant-facing recording:read/recording:access_media or
-- transcript:read/transcript:access_content permission model, or
-- grants app_platform_admin workflow-execution-start ability.
-- =================================================================


-- -----------------------------------------------------------------
-- (A) Hardened Platform Admin identity check.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT session_user = 'app_platform_admin'
     AND COALESCE(current_setting('app.is_platform_admin', true), 'false') = 'true'
$$;

COMMENT ON FUNCTION organization.is_platform_admin() IS
  'Controlled amendment (107_5B5, 2026-09-04) over 106_5H3''s COALESCE-'
  'only fix. Binds Platform Admin identity to session_user = '
  '''app_platform_admin'' (the actual authenticated connecting DB '
  'role -- fixed at connection time by the credential used, never '
  'settable by a SQL session, and unaffected by SECURITY DEFINER, '
  'unlike current_user) IN ADDITION TO the app.is_platform_admin GUC. '
  'Closes the self-forgery gap where any app_api session could '
  'previously grant itself Platform Admin by running SET app.is_'
  'platform_admin = ''true'' or set_config(...): the GUC alone was '
  'never a trust boundary because app_api sessions can set arbitrary '
  'session-local GUCs. 6M remediation SS1.';


-- -----------------------------------------------------------------
-- (B) Narrow EXECUTE on Platform-Admin-only functions: revoke from
--     app_api, leaving app_platform_admin as the sole grantee. Bodies
--     of fn_break_glass_check, fn_platform_reactivate_organization
--     (audit added below), and fn_platform_reserve_refund are
--     otherwise unchanged by this section; fn_break_glass_check needs
--     no CREATE OR REPLACE since it adds no audit write.
-- -----------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION organization.fn_break_glass_check(UUID, UUID, UUID, TEXT, TEXT) FROM app_api;


-- -----------------------------------------------------------------
-- (E)+(B) fn_break_glass_grant (5-arg, 087_5B1.sql original) --
--     add atomic audit write, narrow grant.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.fn_break_glass_grant(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_justification   TEXT,
  p_ttl_seconds     INTEGER,
  p_session_id      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_break_glass_grant: caller is not authorized to grant break-glass access.';
  END IF;
  IF p_ttl_seconds NOT BETWEEN 60 AND 86400 THEN
    RAISE EXCEPTION 'fn_break_glass_grant: p_ttl_seconds % out of the conservative technical bound [60, 86400] seconds.', p_ttl_seconds;
  END IF;

  INSERT INTO organization.break_glass_grants (
    organization_id, admin_user_id, justification, session_id, expires_at
  ) VALUES (
    p_organization_id, p_admin_user_id, p_justification, p_session_id,
    NOW() + make_interval(secs => p_ttl_seconds)
  )
  RETURNING id INTO v_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'BREAK_GLASS_GRANTED', 'BREAK_GLASS_GRANT', v_id, 'SUCCESS', NULL,
    NULL, NULL, p_session_id, NULL, NULL,
    jsonb_build_object('grant_id', v_id, 'ttl_seconds', p_ttl_seconds),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT) TO app_platform_admin;


-- -----------------------------------------------------------------
-- (E)+(B) fn_break_glass_grant (6-arg, 105_5B4.sql, purpose-scoped) --
--     add atomic audit write, narrow grant.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.fn_break_glass_grant(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_justification   TEXT,
  p_ttl_seconds     INTEGER,
  p_session_id      TEXT,
  p_purposes        TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, public, pg_catalog
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_break_glass_grant: caller is not authorized to grant break-glass access.';
  END IF;
  IF p_ttl_seconds NOT BETWEEN 60 AND 86400 THEN
    RAISE EXCEPTION 'fn_break_glass_grant: p_ttl_seconds % out of the conservative technical bound [60, 86400] seconds.', p_ttl_seconds;
  END IF;
  IF p_purposes IS NULL OR array_length(p_purposes, 1) IS NULL THEN
    RAISE EXCEPTION 'fn_break_glass_grant: at least one purpose is required.';
  END IF;
  IF NOT (p_purposes <@ ARRAY[
      'SUPPORT_GENERAL','SUPPORT_BILLING','SUPPORT_ORG_LIFECYCLE',
      'SUPPORT_QUOTA','SENSITIVE_MEDIA_ACCESS','SUPPORT_SECURITY_INCIDENT'
    ]::TEXT[]) THEN
    RAISE EXCEPTION 'fn_break_glass_grant: purposes % contains a value outside the allow-list.', p_purposes;
  END IF;

  INSERT INTO organization.break_glass_grants (
    organization_id, admin_user_id, justification, session_id, expires_at, purposes
  ) VALUES (
    p_organization_id, p_admin_user_id, p_justification, p_session_id,
    NOW() + make_interval(secs => p_ttl_seconds), p_purposes
  )
  RETURNING id INTO v_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'BREAK_GLASS_GRANTED', 'BREAK_GLASS_GRANT', v_id, 'SUCCESS', NULL,
    NULL, NULL, p_session_id, NULL, NULL,
    jsonb_build_object('grant_id', v_id, 'purposes', p_purposes, 'ttl_seconds', p_ttl_seconds),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT, TEXT[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT, TEXT[]) FROM app_api;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT, TEXT[]) TO app_platform_admin;


-- -----------------------------------------------------------------
-- (E)+(B) fn_break_glass_release (087_5B1.sql) -- fetch organization_id
--     under the existing lock to bind tenant context, add atomic
--     audit write, narrow grant.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.fn_break_glass_release(
  p_grant_id    UUID,
  p_released_by UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_status TEXT;
  v_org_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_break_glass_release: caller is not authorized to release break-glass grants.';
  END IF;

  SELECT status, organization_id INTO v_status, v_org_id
  FROM organization.break_glass_grants
  WHERE id = p_grant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_break_glass_release: grant % not found.', p_grant_id;
  END IF;

  IF v_status = 'RELEASED' THEN
    RETURN; -- idempotent no-op
  END IF;

  UPDATE organization.break_glass_grants
  SET status = 'RELEASED', released_at = NOW(), released_by = p_released_by
  WHERE id = p_grant_id;

  PERFORM set_config('app.tenant_id', v_org_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    v_org_id, 'PLATFORM_ADMIN', p_released_by, NULL,
    'BREAK_GLASS_RELEASED', 'BREAK_GLASS_GRANT', p_grant_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('grant_id', p_grant_id),
    FALSE
  );
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_release(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION organization.fn_break_glass_release(UUID, UUID) FROM app_api;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_release(UUID, UUID) TO app_platform_admin;


-- -----------------------------------------------------------------
-- (E)+(B) fn_platform_suspend_organization / fn_platform_reactivate_
--     organization (105_5B4.sql) -- persist p_reason (previously
--     validated then silently discarded), add atomic audit write,
--     narrow grant.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.fn_platform_suspend_organization(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_reason          TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: caller is not authorized.';
  END IF;
  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: p_admin_user_id is required.';
  END IF;
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: p_reason must be between 10 and 2000 characters.';
  END IF;

  SELECT status INTO v_status
  FROM organization.organizations
  WHERE id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: organization % not found.', p_organization_id;
  END IF;

  IF v_status = 'SUSPENDED' THEN
    RETURN v_status; -- idempotent no-op
  END IF;

  IF v_status = 'CANCELLED' THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: organization % is CANCELLED (terminal state) and cannot be suspended.', p_organization_id;
  END IF;

  UPDATE organization.organizations
  SET status = 'SUSPENDED', updated_at = NOW()
  WHERE id = p_organization_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'ORGANIZATION_SUSPENDED', 'ORGANIZATION', p_organization_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('previous_status', v_status, 'reason', p_reason),
    FALSE
  );

  RETURN 'SUSPENDED';
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_platform_suspend_organization(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION organization.fn_platform_suspend_organization(UUID, UUID, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION organization.fn_platform_suspend_organization(UUID, UUID, TEXT) TO app_platform_admin;

CREATE OR REPLACE FUNCTION organization.fn_platform_reactivate_organization(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_reason          TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: caller is not authorized.';
  END IF;
  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: p_admin_user_id is required.';
  END IF;
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: p_reason must be between 10 and 2000 characters.';
  END IF;

  SELECT status INTO v_status
  FROM organization.organizations
  WHERE id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: organization % not found.', p_organization_id;
  END IF;

  IF v_status = 'ACTIVE' THEN
    RETURN v_status; -- idempotent no-op
  END IF;

  IF v_status = 'CANCELLED' THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: organization % is CANCELLED (terminal state) and cannot be reactivated.', p_organization_id;
  END IF;

  UPDATE organization.organizations
  SET status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_organization_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'ORGANIZATION_REACTIVATED', 'ORGANIZATION', p_organization_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('previous_status', v_status, 'reason', p_reason),
    FALSE
  );

  RETURN 'ACTIVE';
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_platform_reactivate_organization(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION organization.fn_platform_reactivate_organization(UUID, UUID, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION organization.fn_platform_reactivate_organization(UUID, UUID, TEXT) TO app_platform_admin;


-- -----------------------------------------------------------------
-- (E)+(B)+(G) fn_platform_set_quota_override (106_5H3.sql) -- add
--     atomic audit write, narrow grant. (G) is a newly-identified
--     defect found during 6M remediation live testing (§32
--     "server-authoritative org" battery, item Q5): the function had
--     NO organization-existence check, and billing.quota_configs.
--     organization_id carries no FK constraint, so a caller could
--     silently create a quota override (and a matching audit event)
--     for a nonexistent organization id. Fixed by adding an explicit
--     existence check, in the same style/position already used by
--     fn_platform_suspend_organization / fn_platform_reactivate_
--     organization in this same file. Signature otherwise unchanged.
-- -----------------------------------------------------------------

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
SET search_path = billing, organization, pg_catalog
AS $$
DECLARE
  v_id UUID;
  v_unit_label TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: caller is not authorized.';
  END IF;
  IF p_metric NOT IN (
      'CALL_MINUTES','CALL_COUNT','SMS_COUNT','WHATSAPP_MESSAGE_COUNT',
      'STORAGE_GB','API_REQUEST_COUNT','WORKFLOW_EXECUTION_COUNT',
      'AGENT_COUNT','SEAT_COUNT','KNOWLEDGE_BASE_DOCUMENT_COUNT',
      'INTEGRATION_COUNT','CONCURRENT_CALL_COUNT','LLM_TOKEN_COUNT',
      'RECORDING_STORAGE_GB','WEBHOOK_DELIVERY_COUNT'
    ) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: metric % is not a recognized usage dimension.', p_metric;
  END IF;
  IF p_soft_limit IS NULL OR p_soft_limit <= 0 OR p_hard_limit IS NULL OR p_hard_limit <= 0 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: soft_limit and hard_limit must both be positive.';
  END IF;
  IF p_hard_limit < p_soft_limit THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: hard_limit must be >= soft_limit.';
  END IF;
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_reason must be between 10 and 2000 characters.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM organization.organizations WHERE id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: organization % not found.', p_organization_id;
  END IF;

  v_unit_label := COALESCE(p_unit_label, CASE p_metric
    WHEN 'CALL_MINUTES' THEN 'minutes'
    WHEN 'STORAGE_GB' THEN 'GB'
    WHEN 'RECORDING_STORAGE_GB' THEN 'GB'
    WHEN 'LLM_TOKEN_COUNT' THEN 'tokens'
    ELSE 'count'
  END);

  INSERT INTO billing.quota_configs (
    organization_id, metric, soft_limit, hard_limit, override_reason,
    effective_from, expires_at, updated_by, unit_label
  ) VALUES (
    p_organization_id, p_metric, p_soft_limit, p_hard_limit, p_reason,
    NOW(), p_expires_at, p_admin_user_id, v_unit_label
  )
  ON CONFLICT ON CONSTRAINT uq_qc_org_metric DO UPDATE
  SET soft_limit = EXCLUDED.soft_limit,
      hard_limit = EXCLUDED.hard_limit,
      override_reason = EXCLUDED.override_reason,
      effective_from = EXCLUDED.effective_from,
      expires_at = EXCLUDED.expires_at,
      updated_by = EXCLUDED.updated_by,
      unit_label = EXCLUDED.unit_label
  RETURNING id INTO v_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'QUOTA_OVERRIDE_SET', 'QUOTA_CONFIG', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'metric', p_metric, 'soft_limit', p_soft_limit, 'hard_limit', p_hard_limit,
      'reason', p_reason, 'expires_at', p_expires_at, 'unit_label', v_unit_label
    ),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) TO app_platform_admin;


-- -----------------------------------------------------------------
-- (E)+(B) fn_platform_reserve_refund (106_5H3.sql) -- add atomic
--     audit write, narrow grant. Signature/body otherwise unchanged.
-- -----------------------------------------------------------------

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
  v_pa billing.payment_attempts%ROWTYPE;
  v_already_refunded NUMERIC(18,4);
  v_refund_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: caller is not authorized.';
  END IF;
  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: p_admin_user_id is required.';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: p_amount must be positive.';
  END IF;
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: p_reason must be between 10 and 2000 characters.';
  END IF;

  SELECT * INTO v_pa
  FROM billing.payment_attempts
  WHERE id = p_payment_attempt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: payment_attempt % not found.', p_payment_attempt_id;
  END IF;
  IF v_pa.organization_id <> p_organization_id THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: payment_attempt % does not belong to organization %.', p_payment_attempt_id, p_organization_id;
  END IF;
  IF v_pa.status <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: payment_attempt % is not SUCCEEDED (status=%).', p_payment_attempt_id, v_pa.status;
  END IF;
  IF v_pa.amount_currency <> p_currency THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: currency % does not match payment_attempt currency %.', p_currency, v_pa.amount_currency;
  END IF;

  SELECT COALESCE(SUM(amount_amount), 0) INTO v_already_refunded
  FROM billing.refunds
  WHERE payment_attempt_id = p_payment_attempt_id
    AND status IN ('PENDING', 'SUCCEEDED');

  IF v_already_refunded + p_amount > v_pa.amount_amount THEN
    RAISE EXCEPTION 'fn_platform_reserve_refund: requested refund % plus already-reserved/settled % would exceed original payment amount %.', p_amount, v_already_refunded, v_pa.amount_amount;
  END IF;

  INSERT INTO billing.refunds (
    organization_id, payment_attempt_id, payment_provider, provider_refund_id,
    amount_amount, amount_currency, reason, status
  ) VALUES (
    p_organization_id, p_payment_attempt_id, v_pa.payment_provider, NULL,
    p_amount, p_currency, p_reason, 'PENDING'
  )
  RETURNING id INTO v_refund_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'REFUND_RESERVED', 'REFUND', v_refund_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'payment_attempt_id', p_payment_attempt_id, 'amount', p_amount,
      'currency', p_currency, 'reason', p_reason
    ),
    FALSE
  );

  RETURN v_refund_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_reserve_refund(UUID, UUID, UUID, NUMERIC, CHAR(3), TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_reserve_refund(UUID, UUID, UUID, NUMERIC, CHAR(3), TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_reserve_refund(UUID, UUID, UUID, NUMERIC, CHAR(3), TEXT) TO app_platform_admin;

-- CONTROLLED AMENDMENT (6M remediation, live-validation finding): an
-- earlier draft of this CREATE OR REPLACE diverged from 106_5H3.sql's
-- reserve-refund body by referencing columns that do not exist on the
-- live schema -- billing.payment_attempts.currency/.amount and
-- billing.refunds.amount/.currency/.requested_by, none of which are
-- real columns (the actual columns are amount_currency, amount_amount,
-- and payment_provider; billing.refunds has no requested_by column at
-- all -- the reserving admin is captured only in the audit event, per
-- SS9's audit-atomicity requirement, not on the refund row itself).
-- That draft would have raised "column does not exist" on every
-- invocation. Corrected to use the real column names
-- (v_pa.amount_currency, v_pa.amount_amount, v_pa.payment_provider,
-- billing.refunds.amount_amount/.amount_currency/.payment_provider),
-- restoring exact behavioral parity with 106_5H3.sql's reservation
-- logic (over-refund guard, org/currency/status checks) plus the new
-- atomic audit call. Found and fixed via live PostgreSQL 18 execution
-- against phase6m-pg18-incr while building the SS30 refund test
-- battery -- fixed DDL preserved at
-- docs/phase-05-database-design/5K/execution_logs/20260904T125500Z_6M_24_00_refund_reserve_bugfix_ddl_source.sql.txt,
-- and the fix is live-proven end-to-end (11 scenarios: valid reservation,
-- over-refund/zero/negative rejection, currency mismatch, failed-payment
-- rejection, cross-org redirection rejection with positive control,
-- server-derived provider, atomic audit) in
-- docs/phase-05-database-design/5K/execution_logs/20260904T161500Z_6M_24_04_refund_battery_part1_output.txt.
-- If a future read of 106_5H3.sql's live definition ever disagrees with
-- the body above in a way that changes validation behavior, that
-- disagreement must be treated as a defect in this migration, not an
-- intentional change, and corrected.


-- -----------------------------------------------------------------
-- (D) Dedicated trusted billing-reconciliation principal. Same
--     CREATE ROLE ... LOGIN pattern as app_voice_reconciler
--     (099_5C1.sql) / app_billing_webhook_ingress (102_5H2.sql):
--     LOGIN only, no BYPASSRLS, no broad table grants -- all access
--     is through the two SECURITY DEFINER functions below, which run
--     with their owner's privileges regardless of this role's own
--     table grants.
-- -----------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_billing_reconciler') THEN
    CREATE ROLE app_billing_reconciler LOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA billing TO app_billing_reconciler;


-- -----------------------------------------------------------------
-- (D)+(E) fn_platform_settle_refund / fn_platform_fail_refund
--     (106_5H3.sql) -- re-gated to app_billing_reconciler only
--     (REVOKEd from app_api AND app_platform_admin: no human/support
--     route may fabricate settlement truth -- 6M remediation SS7).
--     Authorization check changed from is_platform_admin() to
--     session_user = 'app_billing_reconciler'. organization_id is now
--     fetched under the existing FOR UPDATE lock to bind tenant
--     context for the new atomic audit write. Audited as actor_type
--     WORKER (a trusted automated principal reconciling verified
--     provider state), not PLATFORM_ADMIN; the admin who originally
--     reserved the refund is preserved in the audit resource_snapshot
--     for traceability, not as the acting principal.
-- -----------------------------------------------------------------

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
  v_org_id UUID;
BEGIN
  IF session_user <> 'app_billing_reconciler' THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: caller % is not the trusted billing reconciliation principal; refund settlement must be driven by verified payment-provider results, never by a human/admin route (6M remediation SS7).', session_user;
  END IF;
  IF p_provider_refund_id IS NULL OR length(p_provider_refund_id) < 1 THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: p_provider_refund_id is required.';
  END IF;

  SELECT status, organization_id INTO v_status, v_org_id
  FROM billing.refunds
  WHERE id = p_refund_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: refund % not found.', p_refund_id;
  END IF;

  IF v_status = 'SUCCEEDED' THEN
    RETURN v_status; -- idempotent no-op
  END IF;

  IF v_status = 'FAILED' THEN
    RAISE EXCEPTION 'fn_platform_settle_refund: refund % is already FAILED (terminal state).', p_refund_id;
  END IF;

  UPDATE billing.refunds
  SET status = 'SUCCEEDED', provider_refund_id = p_provider_refund_id, completed_at = NOW()
  WHERE id = p_refund_id;

  PERFORM set_config('app.tenant_id', v_org_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    v_org_id, 'WORKER', NULL, 'app_billing_reconciler',
    'REFUND_SETTLED', 'REFUND', p_refund_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('provider_refund_id', p_provider_refund_id, 'requested_by_admin_user_id', p_admin_user_id),
    FALSE
  );

  RETURN 'SUCCEEDED';
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_settle_refund(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_settle_refund(UUID, UUID, TEXT) FROM app_api, app_platform_admin;
GRANT EXECUTE ON FUNCTION billing.fn_platform_settle_refund(UUID, UUID, TEXT) TO app_billing_reconciler;

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
  v_org_id UUID;
BEGIN
  IF session_user <> 'app_billing_reconciler' THEN
    RAISE EXCEPTION 'fn_platform_fail_refund: caller % is not the trusted billing reconciliation principal (6M remediation SS7).', session_user;
  END IF;
  IF p_failure_reason IS NOT NULL AND length(p_failure_reason) > 2000 THEN
    RAISE EXCEPTION 'fn_platform_fail_refund: p_failure_reason exceeds 2000 characters.';
  END IF;

  SELECT status, organization_id INTO v_status, v_org_id
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

  PERFORM set_config('app.tenant_id', v_org_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    v_org_id, 'WORKER', NULL, 'app_billing_reconciler',
    'REFUND_FAILED', 'REFUND', p_refund_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('failure_reason', p_failure_reason, 'requested_by_admin_user_id', p_admin_user_id),
    FALSE
  );

  RETURN 'FAILED';
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_fail_refund(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_fail_refund(UUID, UUID, TEXT) FROM app_api, app_platform_admin;
GRANT EXECUTE ON FUNCTION billing.fn_platform_fail_refund(UUID, UUID, TEXT) TO app_billing_reconciler;


-- -----------------------------------------------------------------
-- (C) Sensitive voice-content hardening. Supersedes 018_5C.sql's
--     blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN
--     SCHEMA voice TO app_platform_admin` for exactly these five
--     tables. app_platform_admin loses INSERT/UPDATE/DELETE entirely
--     on voice content (it should never write voice data directly --
--     that remains app_worker's job) and loses SELECT on the specific
--     content columns; column-restricted SELECT is retained for
--     support/diagnostic metadata. Every other table in schema voice
--     (including voice.call_sessions) is untouched.
-- -----------------------------------------------------------------

REVOKE ALL ON voice.recordings FROM app_platform_admin;
REVOKE ALL ON voice.transcripts FROM app_platform_admin;
REVOKE ALL ON voice.transcript_segments FROM app_platform_admin;
REVOKE ALL ON voice.conversations FROM app_platform_admin;
REVOKE ALL ON voice.turns FROM app_platform_admin;

-- voice.transcripts carries no content column (id, organization_id,
-- conversation_id, call_id, status, total_segments, completed_at,
-- created_at, updated_at) -- full SELECT is metadata-only and safe.
GRANT SELECT ON voice.transcripts TO app_platform_admin;

-- Excludes storage_ref (the S3 path to the audio recording itself).
GRANT SELECT (
  id, organization_id, call_id, conversation_id, status, storage_provider,
  content_type, duration_seconds, file_size_bytes, checksum_sha256,
  recording_policy, consent_obtained, retention_days, delete_after,
  deleted_at, deleted_by, created_at, updated_at
) ON voice.recordings TO app_platform_admin;

-- Excludes text (the transcript segment content itself).
GRANT SELECT (
  id, created_at, organization_id, transcript_id, conversation_id, call_id,
  sequence_number, speaker, is_partial, start_ms, end_ms, confidence,
  language, stt_provider_id, provider_segment_id
) ON voice.transcript_segments TO app_platform_admin;

-- Excludes summary_text (LLM-generated call summary).
GRANT SELECT (
  id, organization_id, call_id, agent_version_id, contact_ref, status,
  qualification_outcome, sentiment_label, sentiment_score,
  prompt_tokens_used, completion_tokens_used, total_tokens_used,
  total_turns, started_at, completed_at, created_at, updated_at
) ON voice.conversations TO app_platform_admin;

-- Excludes utterance_text and response_text (turn-level transcript
-- content in both directions).
GRANT SELECT (
  id, organization_id, conversation_id, sequence_number, speaker_role,
  utterance_confidence, utterance_start_ms, utterance_end_ms,
  detected_language, detected_languages, code_switch_detected,
  language_detection_confidence, directive_kind, workflow_node_ref,
  tool_execution_ids, llm_provider_id, stt_provider_id, stt_ms,
  llm_first_token_ms, tts_first_audio_ms, turn_e2e_ms, barge_in_occurred,
  completed_at, created_at
) ON voice.turns TO app_platform_admin;


-- -----------------------------------------------------------------
-- (C) Guarded purpose-bound sensitive-media read functions. The only
--     remaining path from app_platform_admin back to recording
--     storage_ref / transcript text. Both require, in order: (1) the
--     caller is genuinely session_user = app_platform_admin (belt-
--     and-suspenders on top of is_platform_admin(), since these
--     functions are the most sensitive surface in the schema); (2) a
--     durable, non-expired, non-released break-glass grant bound to
--     this exact organization + admin + session, scoped to purpose
--     SENSITIVE_MEDIA_ACCESS (organization.fn_break_glass_check,
--     105_5B4.sql -- already enforces all of expiry/release/org/
--     admin/session/purpose binding, satisfying the SS4 stacked-
--     condition requirement without duplicating that logic here);
--     (3) the requested resource actually belongs to the granted
--     organization (resource-ownership cross-check -- an Org A grant
--     cannot be used to read an Org B resource, independent of and
--     in addition to fn_break_glass_check's own org binding, closing
--     SS10 item 6 at the resource level, not just the grant level).
--     On success, exactly one atomic audit event is recorded
--     (resource_snapshot carries only IDs -- never storage_ref, never
--     transcript text; SS5, SS10 items 20-21) before the row(s) are
--     returned. The recording function returns storage_ref/storage_
--     provider only -- callers must delegate to the authoritative
--     Voice application/storage capability to actually sign a URL;
--     no signing logic lives here (SS5).
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION voice.fn_platform_access_recording(
  p_grant_id         UUID,
  p_admin_user_id    UUID,
  p_organization_id  UUID,
  p_session_id       TEXT,
  p_recording_id     UUID
)
RETURNS TABLE (
  id               UUID,
  call_id          UUID,
  conversation_id  UUID,
  storage_ref      TEXT,
  storage_provider TEXT,
  content_type     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, organization, pg_catalog
AS $$
DECLARE
  v_rec voice.recordings%ROWTYPE;
BEGIN
  IF session_user <> 'app_platform_admin' THEN
    RAISE EXCEPTION 'fn_platform_access_recording: caller % is not the Platform Admin principal.', session_user;
  END IF;

  IF NOT organization.fn_break_glass_check(
      p_grant_id, p_admin_user_id, p_organization_id, p_session_id, 'SENSITIVE_MEDIA_ACCESS'
    ) THEN
    RAISE EXCEPTION 'fn_platform_access_recording: no valid SENSITIVE_MEDIA_ACCESS break-glass grant for this organization/admin/session.';
  END IF;

  SELECT * INTO v_rec
  FROM voice.recordings r
  WHERE r.id = p_recording_id
    AND r.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_access_recording: recording % not found for organization %.', p_recording_id, p_organization_id;
  END IF;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'RECORDING_ACCESS_GRANTED', 'RECORDING', p_recording_id, 'SUCCESS', NULL,
    NULL, NULL, p_session_id, NULL, NULL,
    jsonb_build_object('grant_id', p_grant_id, 'call_id', v_rec.call_id, 'recording_id', p_recording_id),
    FALSE
  );

  RETURN QUERY SELECT v_rec.id, v_rec.call_id, v_rec.conversation_id, v_rec.storage_ref, v_rec.storage_provider, v_rec.content_type;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_platform_access_recording(UUID, UUID, UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_platform_access_recording(UUID, UUID, UUID, TEXT, UUID) TO app_platform_admin;

CREATE OR REPLACE FUNCTION voice.fn_platform_access_transcript(
  p_grant_id         UUID,
  p_admin_user_id    UUID,
  p_organization_id  UUID,
  p_session_id       TEXT,
  p_transcript_id    UUID
)
RETURNS TABLE (
  sequence_number INTEGER,
  speaker         TEXT,
  text            TEXT,
  is_partial      BOOLEAN,
  start_ms        INTEGER,
  end_ms          INTEGER,
  language        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, organization, pg_catalog
AS $$
DECLARE
  v_tr voice.transcripts%ROWTYPE;
BEGIN
  IF session_user <> 'app_platform_admin' THEN
    RAISE EXCEPTION 'fn_platform_access_transcript: caller % is not the Platform Admin principal.', session_user;
  END IF;

  IF NOT organization.fn_break_glass_check(
      p_grant_id, p_admin_user_id, p_organization_id, p_session_id, 'SENSITIVE_MEDIA_ACCESS'
    ) THEN
    RAISE EXCEPTION 'fn_platform_access_transcript: no valid SENSITIVE_MEDIA_ACCESS break-glass grant for this organization/admin/session.';
  END IF;

  SELECT * INTO v_tr
  FROM voice.transcripts t
  WHERE t.id = p_transcript_id
    AND t.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_access_transcript: transcript % not found for organization %.', p_transcript_id, p_organization_id;
  END IF;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'TRANSCRIPT_ACCESS_GRANTED', 'TRANSCRIPT', p_transcript_id, 'SUCCESS', NULL,
    NULL, NULL, p_session_id, NULL, NULL,
    jsonb_build_object('grant_id', p_grant_id, 'call_id', v_tr.call_id, 'transcript_id', p_transcript_id),
    FALSE
  );

  RETURN QUERY
  SELECT ts.sequence_number, ts.speaker, ts.text, ts.is_partial, ts.start_ms, ts.end_ms, ts.language
  FROM voice.transcript_segments ts
  WHERE ts.transcript_id = p_transcript_id
    AND ts.organization_id = p_organization_id
  ORDER BY ts.sequence_number;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_platform_access_transcript(UUID, UUID, UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_platform_access_transcript(UUID, UUID, UUID, TEXT, UUID) TO app_platform_admin;
