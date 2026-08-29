-- =================================================================
-- Migration 101 (Phase 5I.1 — controlled amendment): integration
-- connection lifecycle functions, plugin installation lifecycle
-- functions, OAuth callback tenant-bootstrap function, webhook
-- dual-secret rotation support.
-- down_revision: 100_5G1
--
-- Source: docs/phase-06-api-design/6J-Integrations-Webhooks-Plugins-APIs.md
--   remediation pass (2026-08-29) — closes DEP-6J-01 (P0), DEP-6J-02
--   (P0), the OAuth-callback tenant-bootstrap defect (P0, remediation
--   §4), the webhook-secret-rotation cryptographic defect (P0,
--   remediation §6), DEP-6J-04 (connection_id correlation), DEP-6J-05
--   (OAuth denial path), DEP-6J-09 (is_active enforcement).
--
-- Scope discipline (per the governing task's explicit constraint):
--   This is a CONTROLLED AMENDMENT, not a Phase 5 rewrite. It adds
--   ELEVEN new SECURITY DEFINER functions, ONE CREATE OR REPLACE on an
--   existing function body (fn_create_integration_connection — same
--   signature, adds an is_active check; see rationale at that
--   statement), five new columns across two existing tables (all
--   NULLable, all additive, no existing row's data invalidated), and
--   five EXECUTE-grant widenings on pre-existing 5I functions. It does
--   not alter any existing table's PRIMARY KEY, RLS policy, or
--   REVOKE/GRANT baseline beyond the five named widenings. No
--   already-applied migration file (059-100) is edited.
--
-- Why these functions are safe to call directly from `app_api` (the
-- ordinary tenant-request DB role), removing the need for the
-- Worker-only EXECUTE restriction 059-066 used for the *pre-existing*
-- plugin/credential/replay functions this migration also re-grants:
-- every function below performs its own `organization_id`-scoped
-- `SELECT ... FOR UPDATE` before any write, so tenant isolation is
-- enforced inside the function body regardless of which role calls
-- it — the same discipline `fn_create_integration_connection` and
-- `fn_create_plugin_installation` (059-066) already established for
-- direct `app_api` execution.
-- =================================================================

-- -----------------------------------------------------------------
-- 1. oauth_attempts: new columns (additive, nullable)
--    - connection_id: closes DEP-6J-04 — the attempt's owning
--      connection is now an explicit FK, not inferred from the
--      (organization_id, definition_id) one-non-terminal-connection
--      invariant. Nullable because it is populated by the INSERT
--      statement the Application Service already issues (ordinary
--      INSERT privilege, no function wraps oauth_attempts creation)
--      and a NULL here for any pre-existing row is impossible since
--      oauth_attempts is TTL-purged within 24h of expiry/redemption
--      (5I §23) — no historical row survives to need backfill.
--    - failure_reason: closes part of DEP-6J-05 — a place to record
--      why an attempt was marked FAILED (provider denial, token
--      exchange failure), sanitized/truncated, never a raw provider
--      body (mirrors the ≤1000/≤2000-char bound pattern used
--      throughout 5I for untrusted external content).
-- -----------------------------------------------------------------
ALTER TABLE integrations.oauth_attempts
  ADD COLUMN connection_id UUID NULL
    REFERENCES integrations.integration_connections(id) ON DELETE CASCADE,
  ADD COLUMN failure_reason TEXT NULL;

ALTER TABLE integrations.oauth_attempts
  ADD CONSTRAINT chk_oa_failure_reason_len
    CHECK (failure_reason IS NULL OR length(failure_reason) <= 1000);

CREATE INDEX idx_oa_connection ON integrations.oauth_attempts (connection_id)
  WHERE connection_id IS NOT NULL;

-- -----------------------------------------------------------------
-- 2. webhook_endpoints: new columns for dual-secret rotation grace
--    (closes the P0 cryptographic defect in remediation §6 — the
--    prior design retained the old secret in the secret manager
--    without ever signing with it, which gives a consumer holding
--    the old secret no working grace period at all).
-- -----------------------------------------------------------------
ALTER TABLE webhooks.webhook_endpoints
  ADD COLUMN previous_signing_secret_ref TEXT NULL,
  ADD COLUMN previous_secret_expires_at TIMESTAMPTZ NULL;

ALTER TABLE webhooks.webhook_endpoints
  ADD CONSTRAINT chk_we_previous_signing_secret_ref
    CHECK (previous_signing_secret_ref IS NULL OR previous_signing_secret_ref LIKE 'secret_manager://%'),
  ADD CONSTRAINT chk_we_previous_secret_pair
    CHECK ((previous_signing_secret_ref IS NULL) = (previous_secret_expires_at IS NULL));

-- ===================================================================
-- INTEGRATION CONNECTION LIFECYCLE (closes DEP-6J-01, P0)
-- ===================================================================

-- -------------------------------------------------------------
-- fn_activate_integration_connection: CONNECTING|DEGRADED -> ACTIVE.
-- Used for (a) initial activation after OAuth callback / immediate
-- non-OAuth credential acceptance, and (b) DEGRADED -> ACTIVE health
-- recovery (credential refresh succeeded, or manual reconnect).
-- p_credential_ref, when supplied, REPLACES the connection's current
-- credential_ref (used to swap the OAuth placeholder sentinel for the
-- real post-token-exchange reference) — when NULL, the existing
-- credential_ref is left untouched (the DEGRADED-recovery case, where
-- fn_rotate_integration_credential already updated it separately, or
-- no credential change occurred).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_activate_integration_connection(
  p_organization_id       UUID,
  p_connection_id         UUID,
  p_credential_ref        TEXT DEFAULT NULL,
  p_external_account_ref  TEXT DEFAULT NULL,
  p_external_account_name TEXT DEFAULT NULL,
  p_connected_by_ref      UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF p_credential_ref IS NOT NULL AND p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: credential_ref must be a secret_manager:// reference';
  END IF;

  SELECT status INTO v_status
  FROM integrations.integration_connections
  WHERE id = p_connection_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found for this organization';
  END IF;
  IF v_status NOT IN ('CONNECTING', 'DEGRADED') THEN
    RAISE EXCEPTION 'integrations: cannot activate connection from status %', v_status;
  END IF;

  UPDATE integrations.integration_connections
  SET status                = 'ACTIVE',
      credential_ref        = COALESCE(p_credential_ref, credential_ref),
      external_account_ref  = COALESCE(p_external_account_ref, external_account_ref),
      external_account_name = COALESCE(p_external_account_name, external_account_name),
      connected_at          = COALESCE(connected_at, NOW()),
      connected_by_ref      = COALESCE(connected_by_ref, p_connected_by_ref),
      last_sync_error       = NULL,
      updated_at            = NOW()
  WHERE id = p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_activate_integration_connection(UUID, UUID, TEXT, TEXT, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_activate_integration_connection(UUID, UUID, TEXT, TEXT, TEXT, UUID)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_fail_integration_connection: CONNECTING -> FAILED (terminal).
-- Matches 4F §7.5's state machine exactly: FAILED is reachable only
-- from CONNECTING (OAuth denial, initial credential validation
-- failure) — ACTIVE/DEGRADED connections transition to DISCONNECTED,
-- never FAILED, per the frozen DDD state diagram. Idempotent: calling
-- this on an already-FAILED connection is a no-op (matches
-- fn_uninstall_plugin's idempotent-return pattern, 5I §28).
-- chk_ic_terminal_has_at requires disconnected_at to be set even for
-- FAILED (not just DISCONNECTED) — this function sets it accordingly.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_fail_integration_connection(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_reason          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM integrations.integration_connections
  WHERE id = p_connection_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found for this organization';
  END IF;
  IF v_status = 'FAILED' THEN
    RETURN; -- idempotent
  END IF;
  IF v_status <> 'CONNECTING' THEN
    RAISE EXCEPTION 'integrations: connection can only fail from CONNECTING (current status %)', v_status;
  END IF;

  UPDATE integrations.integration_connections
  SET status            = 'FAILED',
      disconnected_at   = NOW(),
      disconnect_reason = LEFT(COALESCE(p_reason, 'connection_failed'), 1000),
      updated_at        = NOW()
  WHERE id = p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_fail_integration_connection(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_fail_integration_connection(UUID, UUID, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_degrade_integration_connection: ACTIVE -> DEGRADED. Driven by
-- health-tracking logic (repeated sync/test failures, credential
-- expiry auto-detected) — never called directly from a tenant-facing
-- REST handler; the Application Service's health-evaluation code path
-- calls this once a degradation threshold is crossed. Idempotent on
-- an already-DEGRADED connection.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_degrade_integration_connection(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_reason          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM integrations.integration_connections
  WHERE id = p_connection_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found for this organization';
  END IF;
  IF v_status = 'DEGRADED' THEN
    RETURN; -- idempotent
  END IF;
  IF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'integrations: connection can only degrade from ACTIVE (current status %)', v_status;
  END IF;

  UPDATE integrations.integration_connections
  SET status          = 'DEGRADED',
      last_sync_error = LEFT(COALESCE(p_reason, last_sync_error, ''), 1000),
      updated_at      = NOW()
  WHERE id = p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_degrade_integration_connection(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_degrade_integration_connection(UUID, UUID, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_disconnect_integration_connection: {CONNECTING|ACTIVE|DEGRADED}
-- -> DISCONNECTED (terminal). Tenant-initiated disconnect. Idempotent
-- on an already-terminal (DISCONNECTED or FAILED) connection —
-- disconnect is a "make sure it's off" action, not a strict state
-- transition the client must avoid re-calling.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_disconnect_integration_connection(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_reason          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM integrations.integration_connections
  WHERE id = p_connection_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found for this organization';
  END IF;
  IF v_status IN ('DISCONNECTED', 'FAILED') THEN
    RETURN; -- idempotent
  END IF;

  UPDATE integrations.integration_connections
  SET status            = 'DISCONNECTED',
      disconnected_at   = NOW(),
      disconnect_reason = LEFT(COALESCE(p_reason, 'tenant_disconnected'), 1000),
      updated_at        = NOW()
  WHERE id = p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_disconnect_integration_connection(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_disconnect_integration_connection(UUID, UUID, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_update_integration_connection_config: free-form field update on
-- a non-terminal connection. Never touches status/credential_ref.
-- p_display_name / p_configuration NULL means "leave unchanged" — the
-- Application Service is responsible for passing the current value
-- when a field is not part of the requested change (display_name has
-- a NOT NULL column constraint, so a literal NULL can never be
-- persisted regardless).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_update_integration_connection_config(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_display_name    TEXT DEFAULT NULL,
  p_configuration   JSONB DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM integrations.integration_connections
  WHERE id = p_connection_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found for this organization';
  END IF;
  IF v_status IN ('DISCONNECTED', 'FAILED') THEN
    RAISE EXCEPTION 'integrations: connection % is in terminal state % — create a new connection', p_connection_id, v_status;
  END IF;

  UPDATE integrations.integration_connections
  SET display_name  = COALESCE(p_display_name, display_name),
      configuration = COALESCE(p_configuration, configuration),
      updated_at    = NOW()
  WHERE id = p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_update_integration_connection_config(UUID, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_update_integration_connection_config(UUID, UUID, TEXT, JSONB)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_record_integration_sync_result: writes last_sync_at/
-- last_sync_error only. Never changes status — a sync failure alone
-- does not degrade a connection; repeated failures crossing the
-- Application Service's own threshold call
-- fn_degrade_integration_connection() separately. Callable on any
-- non-terminal connection; a terminal connection recording a
-- still-in-flight sync's late result is a documented no-op (the sync
-- was for a connection the tenant has since disconnected/failed).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_record_integration_sync_result(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_success         BOOLEAN,
  p_error_message   TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM integrations.integration_connections
  WHERE id = p_connection_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found for this organization';
  END IF;
  IF v_status IN ('DISCONNECTED', 'FAILED') THEN
    RETURN; -- no-op: sync result for a connection the tenant has already terminated
  END IF;

  UPDATE integrations.integration_connections
  SET last_sync_at    = NOW(),
      last_sync_error = CASE WHEN p_success THEN NULL ELSE LEFT(COALESCE(p_error_message, ''), 1000) END,
      updated_at      = NOW()
  WHERE id = p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_record_integration_sync_result(UUID, UUID, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_record_integration_sync_result(UUID, UUID, BOOLEAN, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_create_integration_connection: CREATE OR REPLACE on the existing
-- (059-066) function — SAME signature, body extended with exactly one
-- additional check (closes DEP-6J-09): the target definition must be
-- is_active. This is a defense-in-depth hardening of an
-- already-existing function, not a new capability or a behavior
-- change for any caller that was already respecting is_active at the
-- application layer (the documented status quo) — a caller that
-- was NOT already checking is_active now gets a clear DB-level
-- rejection instead of silently creating a connection to a
-- deactivated provider.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_create_integration_connection(
  p_organization_id   UUID,
  p_definition_id     UUID,
  p_display_name      TEXT,
  p_credential_ref    TEXT,
  p_configuration     JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_existing_id  UUID;
  v_new_id       UUID;
  v_is_active    BOOLEAN;
BEGIN
  IF p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: credential_ref must be a secret_manager:// reference';
  END IF;

  SELECT is_active INTO v_is_active
  FROM integrations.integration_definitions
  WHERE id = p_definition_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: definition % not found', p_definition_id;
  END IF;
  IF NOT v_is_active THEN
    RAISE EXCEPTION 'integrations: definition % is not active', p_definition_id;
  END IF;

  SELECT id INTO v_existing_id
  FROM integrations.integration_connections
  WHERE organization_id = p_organization_id
    AND definition_id   = p_definition_id
    AND status NOT IN ('DISCONNECTED','FAILED')
  FOR UPDATE;

  IF FOUND THEN
    RAISE EXCEPTION
      'integrations: a non-terminal connection (id=%) already exists for this (org, definition). '
      'Disconnect it first, then create a new connection.',
      v_existing_id;
  END IF;

  INSERT INTO integrations.integration_connections
    (organization_id, definition_id, display_name, credential_ref, configuration, status)
  VALUES
    (p_organization_id, p_definition_id, p_display_name, p_credential_ref, p_configuration, 'CONNECTING')
  RETURNING id INTO v_new_id;

  INSERT INTO integrations.integration_health (organization_id, integration_connection_id)
  VALUES (p_organization_id, v_new_id)
  ON CONFLICT (integration_connection_id) DO NOTHING;

  RETURN v_new_id;
END;
$$;
-- Grants unchanged from 061_5I (REVOKE ALL FROM PUBLIC; GRANT EXECUTE TO app_api, app_worker,
-- app_platform_admin already in place) — CREATE OR REPLACE preserves existing grants in PostgreSQL.

-- ===================================================================
-- OAUTH CALLBACK TENANT BOOTSTRAP (closes the P0 defect, remediation §4)
-- ===================================================================

-- -------------------------------------------------------------
-- fn_redeem_oauth_callback_state: the ONLY redemption path used by
-- the unauthenticated browser-callback endpoint
-- (GET /api/v1/integrations/oauth/{key}/callback, 6J §13.4). Takes
-- `state` ALONE — no organization_id parameter — because the caller
-- (a browser mid-OAuth-redirect) genuinely does not have tenant
-- context yet; `state` itself (256-bit, cryptographically random,
-- UNIQUE, 10-minute TTL, single-use) IS the security boundary here,
-- functioning exactly like a password-reset token.
--
-- This does NOT require removing RLS from oauth_attempts, and does
-- NOT rely on any RLS-bypass assumption about the calling role: this
-- function is SECURITY DEFINER, so its internal queries execute under
-- the function OWNER's privileges (the role that ran this migration —
-- `app_migration`, created BYPASSRLS in 001_5B.sql and independently
-- confirmed BYPASSRLS-still-unchanged in the 077_5J1 live validation
-- pass, docs/phase-05-database-design/5K/validation/
-- 077_5J1_VALIDATION_REPORT.md line 309) — RLS was never actually the
-- obstacle inside a SECURITY DEFINER function owned by a BYPASSRLS
-- role; the prior defect was purely that fn_redeem_oauth_attempt's
-- SIGNATURE wrongly required organization_id as an INPUT the caller
-- could not supply. This function fixes that by returning
-- organization_id (and definition_id, connection_id) as OUTPUT
-- instead.
--
-- fn_redeem_oauth_attempt (059-066) is left untouched and still
-- exists for any future authenticated-redemption caller that already
-- has organization_id in hand; it is simply not the function 6J's
-- callback endpoint calls.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_redeem_oauth_callback_state(
  p_state TEXT
) RETURNS TABLE (
  oauth_attempt_id UUID,
  organization_id  UUID,
  definition_id    UUID,
  connection_id    UUID,
  code_verifier    TEXT,
  redirect_uri     TEXT,
  requested_scopes TEXT[]
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_id       UUID;
  v_status   TEXT;
  v_expires  TIMESTAMPTZ;
BEGIN
  SELECT oa.id, oa.status, oa.expires_at
  INTO v_id, v_status, v_expires
  FROM integrations.oauth_attempts oa
  WHERE oa.state = p_state
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found';
  END IF;
  IF v_status = 'REDEEMED' THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % already redeemed', v_id;
  END IF;
  IF v_status IN ('EXPIRED', 'FAILED') THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % is in terminal state %', v_id, v_status;
  END IF;
  IF v_expires <= NOW() THEN
    UPDATE integrations.oauth_attempts SET status = 'EXPIRED' WHERE id = v_id;
    RAISE EXCEPTION 'integrations: OAuth attempt % has expired', v_id;
  END IF;

  UPDATE integrations.oauth_attempts
  SET status = 'REDEEMED', redeemed_at = NOW()
  WHERE id = v_id;

  RETURN QUERY
  SELECT oa.id, oa.organization_id, oa.definition_id, oa.connection_id,
         oa.code_verifier, oa.redirect_uri, oa.requested_scopes
  FROM integrations.oauth_attempts oa
  WHERE oa.id = v_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_redeem_oauth_callback_state(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_redeem_oauth_callback_state(TEXT)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_fail_oauth_callback_state: the denial/failure counterpart, same
-- bootstrap shape (state alone, no organization_id) — closes
-- DEP-6J-05. Called when the provider redirects with `?error=...`
-- instead of `?code=...`, or when server-side token exchange fails
-- after a successful redemption. Idempotent-safe: does not error on
-- an attempt that is already FAILED; still rejects (loudly) an
-- attempt that is already REDEEMED, since failing a successfully
-- redeemed attempt after the fact would be a logic error in the
-- caller, not a legitimate retry.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_fail_oauth_callback_state(
  p_state  TEXT,
  p_reason TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_id     UUID;
  v_status TEXT;
BEGIN
  SELECT id, status INTO v_id, v_status
  FROM integrations.oauth_attempts
  WHERE state = p_state
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found';
  END IF;
  IF v_status = 'FAILED' THEN
    RETURN v_id; -- idempotent
  END IF;
  IF v_status = 'REDEEMED' THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % already redeemed — cannot fail a redeemed attempt', v_id;
  END IF;

  UPDATE integrations.oauth_attempts
  SET status = 'FAILED', failure_reason = LEFT(COALESCE(p_reason, 'provider_denied'), 1000)
  WHERE id = v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_fail_oauth_callback_state(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_fail_oauth_callback_state(TEXT, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- ===================================================================
-- PLUGIN INSTALLATION LIFECYCLE (closes DEP-6J-02, P0)
-- ===================================================================

-- -------------------------------------------------------------
-- fn_suspend_plugin_installation: ACTIVE -> SUSPENDED. Idempotent on
-- an already-SUSPENDED installation. Blocked by the existing
-- fn_pi_terminal_guard trigger if UNINSTALLED (no change needed
-- there — that guard already covers this new transition for free).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION plugins.fn_suspend_plugin_installation(
  p_organization_id UUID,
  p_installation_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM plugins.plugin_installations
  WHERE id = p_installation_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_status = 'SUSPENDED' THEN
    RETURN; -- idempotent
  END IF;
  IF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'plugins: cannot suspend from status %', v_status;
  END IF;

  UPDATE plugins.plugin_installations
  SET status = 'SUSPENDED', suspended_at = NOW(), updated_at = NOW()
  WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_suspend_plugin_installation(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_suspend_plugin_installation(UUID, UUID)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_reactivate_plugin_installation: SUSPENDED -> ACTIVE. Unlike
-- fn_upgrade_plugin, this does NOT reset enabled_capabilities — no
-- version change occurred, so the previously-enabled capabilities
-- remain valid and are preserved. Re-validates plugin/version are
-- still APPROVED at reactivation time (defense-in-depth, mirrors
-- fn_activate_plugin's own re-check).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION plugins.fn_reactivate_plugin_installation(
  p_organization_id UUID,
  p_installation_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_status         TEXT;
  v_plugin_status  TEXT;
  v_version_status TEXT;
BEGIN
  SELECT pi.status, pl.status, pv.status
  INTO v_status, v_plugin_status, v_version_status
  FROM plugins.plugin_installations pi
  JOIN plugins.plugins pl ON pl.id = pi.plugin_id
  JOIN plugins.plugin_versions pv ON pv.id = pi.plugin_version_id
  WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id
  FOR UPDATE OF pi;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_status = 'ACTIVE' THEN
    RETURN; -- idempotent
  END IF;
  IF v_status <> 'SUSPENDED' THEN
    RAISE EXCEPTION 'plugins: cannot reactivate from status %', v_status;
  END IF;
  IF v_plugin_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin is no longer APPROVED — reactivation blocked';
  END IF;
  IF v_version_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: installed version is no longer APPROVED (status=%) — reactivation blocked', v_version_status;
  END IF;

  UPDATE plugins.plugin_installations
  SET status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_reactivate_plugin_installation(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_reactivate_plugin_installation(UUID, UUID)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_update_plugin_installation_config: free-form field update.
-- Never touches status, plugin_version_id, credential_ref, or
-- enabled_capabilities.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION plugins.fn_update_plugin_installation_config(
  p_organization_id UUID,
  p_installation_id UUID,
  p_configuration   JSONB DEFAULT NULL,
  p_rate_limit_override INTEGER DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM plugins.plugin_installations
  WHERE id = p_installation_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_status = 'UNINSTALLED' THEN
    RAISE EXCEPTION 'plugins: installation % is UNINSTALLED (terminal)', p_installation_id;
  END IF;
  IF p_rate_limit_override IS NOT NULL AND p_rate_limit_override <= 0 THEN
    RAISE EXCEPTION 'plugins: rate_limit_override must be positive';
  END IF;

  UPDATE plugins.plugin_installations
  SET configuration       = COALESCE(p_configuration, configuration),
      rate_limit_override = CASE WHEN p_rate_limit_override IS NOT NULL
                                  THEN p_rate_limit_override ELSE rate_limit_override END,
      updated_at          = NOW()
  WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_update_plugin_installation_config(UUID, UUID, JSONB, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_update_plugin_installation_config(UUID, UUID, JSONB, INTEGER)
  TO app_api, app_worker, app_platform_admin;

-- -------------------------------------------------------------
-- fn_rotate_plugin_installation_credential: mirrors
-- fn_rotate_integration_credential exactly, applied to
-- plugin_installations.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION plugins.fn_rotate_plugin_installation_credential(
  p_organization_id    UUID,
  p_installation_id    UUID,
  p_new_credential_ref TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF p_new_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'plugins: new credential_ref must be a secret_manager:// reference';
  END IF;

  UPDATE plugins.plugin_installations
  SET credential_ref = p_new_credential_ref, updated_at = NOW()
  WHERE id = p_installation_id
    AND organization_id = p_organization_id
    AND status <> 'UNINSTALLED';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found or is UNINSTALLED';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_rotate_plugin_installation_credential(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_rotate_plugin_installation_credential(UUID, UUID, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- ===================================================================
-- WEBHOOK DUAL-SECRET ROTATION (closes the P0 defect, remediation §6)
-- ===================================================================

-- -------------------------------------------------------------
-- fn_rotate_webhook_secret: atomically moves the current
-- signing_secret_ref into previous_signing_secret_ref (with an
-- expiry), and installs the new secret as the current one. During
-- [NOW(), previous_secret_expires_at), the delivery worker signs
-- every outbound delivery with BOTH the current and (if still
-- unexpired) the previous secret, emitting both signatures so a
-- consumer holding either secret validates successfully (see 6J §21
-- for the wire-format contract this enables). A rotation called again
-- before the previous window expires discards the prior "previous"
-- secret immediately (only one grace generation is retained by
-- design) — its secret-manager entry is purged by the calling
-- Application Service, not by this function (this function only
-- manages the opaque reference, never the secret material itself,
-- consistent with every other credential_ref column in this schema).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION webhooks.fn_rotate_webhook_secret(
  p_organization_id      UUID,
  p_webhook_endpoint_id  UUID,
  p_new_signing_secret_ref TEXT,
  p_grace_period_seconds INTEGER DEFAULT 3600
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
DECLARE
  v_current_secret_ref TEXT;
BEGIN
  IF p_new_signing_secret_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'webhooks: new signing_secret_ref must be a secret_manager:// reference';
  END IF;
  IF p_grace_period_seconds NOT BETWEEN 0 AND 86400 THEN
    RAISE EXCEPTION 'webhooks: grace_period_seconds must be between 0 and 86400';
  END IF;

  SELECT signing_secret_ref INTO v_current_secret_ref
  FROM webhooks.webhook_endpoints
  WHERE id = p_webhook_endpoint_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'webhooks: webhook endpoint not found for this organization';
  END IF;

  UPDATE webhooks.webhook_endpoints
  SET previous_signing_secret_ref = CASE WHEN p_grace_period_seconds > 0 THEN v_current_secret_ref ELSE NULL END,
      previous_secret_expires_at  = CASE WHEN p_grace_period_seconds > 0
                                          THEN NOW() + make_interval(secs => p_grace_period_seconds) ELSE NULL END,
      signing_secret_ref          = p_new_signing_secret_ref,
      updated_at                  = NOW()
  WHERE id = p_webhook_endpoint_id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_rotate_webhook_secret(UUID, UUID, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_rotate_webhook_secret(UUID, UUID, TEXT, INTEGER)
  TO app_api, app_worker, app_platform_admin;

-- ===================================================================
-- EXECUTE-GRANT WIDENING (closes remediation §12 — removes the need
-- for the internal-RPC pattern the pre-remediation 6J document
-- invented; these five PRE-EXISTING (059-066) functions already
-- perform their own organization_id-scoped SELECT ... FOR UPDATE
-- authorization internally, so direct app_api execution is exactly as
-- safe as the app_api-granted functions already added in 059-066
-- (fn_create_integration_connection, fn_create_plugin_installation).
-- No function BODY is touched here — grants only.
-- ===================================================================
GRANT EXECUTE ON FUNCTION plugins.fn_activate_plugin(UUID, UUID, TEXT[]) TO app_api;
GRANT EXECUTE ON FUNCTION plugins.fn_uninstall_plugin(UUID, UUID) TO app_api;
GRANT EXECUTE ON FUNCTION plugins.fn_upgrade_plugin(UUID, UUID, UUID) TO app_api;
GRANT EXECUTE ON FUNCTION integrations.fn_rotate_integration_credential(UUID, UUID, TEXT) TO app_api;
GRANT EXECUTE ON FUNCTION webhooks.fn_replay_webhook_delivery(UUID, UUID, TIMESTAMPTZ) TO app_api;

-- ===================================================================
-- Retention note (documentation only, no pg_cron — matches 5I/077's
-- own established no-scheduled-job pattern): oauth_attempts rows
-- carrying a non-NULL failure_reason are purged on the same 24-hour
-- post-expiry/redemption schedule as every other oauth_attempts row
-- (5I §23) — no separate retention rule is introduced for the two new
-- columns on that table. webhook_endpoints.previous_signing_secret_ref
-- becomes operationally unusable (but is not DB-purged) once
-- previous_secret_expires_at passes; the delivery worker's signing
-- code (application layer, not this migration) MUST stop emitting the
-- previous-secret signature at that timestamp regardless of whether
-- the column has been cleared yet.
-- ===================================================================
