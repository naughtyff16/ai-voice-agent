-- =================================================================
-- Migration 101 (Phase 5I.1 — controlled amendment): integration
-- connection lifecycle functions, plugin installation lifecycle
-- functions, OAuth callback tenant-bootstrap function, webhook
-- dual-secret rotation support.
-- down_revision: 100_5G1
--
-- Source: docs/phase-06-api-design/6J-Integrations-Webhooks-Plugins-APIs.md
--   remediation passes (2026-08-29) — closes DEP-6J-01 (P0), DEP-6J-02
--   (P0), the OAuth-callback tenant-bootstrap defect (P0), the webhook
--   dual-signature rotation defect (P0), DEP-6J-04, DEP-6J-05,
--   DEP-6J-09, and — this revision of 101_5I1 (second remediation
--   pass, same day) — the SECURITY DEFINER tenant-forgery defect
--   (P0), the OAuth token-exchange-failure state-machine contradiction
--   (P0), and the OAuth state/provider-binding gap (P0).
--
-- Amendment history: this file has been revised in place twice since
-- first authored, following the exact same "amended in place, never
-- applied to any real/production database" policy already used for
-- 100_5G1.sql (see MIGRATION_MANIFEST.md's own precedent for that
-- file) — 101_5I1 has, at the time of each revision, only ever been
-- applied to this session's own throwaway validation databases, never
-- to a shared/production/frozen baseline, so amending it in place
-- (rather than issuing 102_5I2) is the policy-consistent choice.
--
-- Scope discipline (per the governing task's explicit constraint):
--   This is a CONTROLLED AMENDMENT, not a Phase 5 rewrite. No
--   already-applied migration file (059-100) is edited. Every
--   pre-existing (059-066) function this file touches is touched
--   exclusively via CREATE OR REPLACE FUNCTION with an IDENTICAL
--   signature — PostgreSQL preserves existing grants across CREATE OR
--   REPLACE, and no business-logic behavior is changed for any
--   already-correct call — only a tenant-context guard is added.
--
-- ================================================================
-- TENANT-FORGERY GUARD — THE CENTRAL FIX OF THIS REVISION
-- ================================================================
-- Every function below that is callable by `app_api` (a non-BYPASSRLS,
-- ordinary tenant-request role) and accepts `p_organization_id` as an
-- explicit parameter now additionally requires:
--
--   organization.current_tenant_id() = p_organization_id
--
-- before touching any row. `organization.current_tenant_id()` reads
-- `current_setting('app.tenant_id', true)::UUID` (confirmed by direct
-- introspection of the live schema this pass — STABLE SQL function,
-- schema `organization`) — the exact same session GUC 6A §23.2/5B
-- §16.1 already require the API layer to `SET LOCAL app.tenant_id =
-- <JWT organization_id claim>` before any tenant-scoped work. Without
-- this guard, a `SECURITY DEFINER` function owned by a `BYPASSRLS`
-- role (`app_migration`, confirmed BYPASSRLS in `001_5B.sql` and the
-- live `077_5J1_VALIDATION_REPORT.md`) and callable by `app_api` would
-- trust `p_organization_id` as an ordinary, unchecked SQL parameter —
-- meaning a compromised or buggy Application Service code path could
-- pass a *different* tenant's UUID and mutate that tenant's data,
-- entirely bypassing RLS (which never applies inside a BYPASSRLS-owned
-- SECURITY DEFINER function's own queries).
--
-- This guard is added to:
--   (a) every NEW function in this migration that is `app_api`-
--       callable and tenant-bound (i.e., every one except the three
--       OAuth callback bootstrap functions, which are intentionally
--       exempt — see the "Function classes" note below);
--   (b) every PRE-EXISTING (059-066) function this migration widens
--       to `app_api` (`fn_activate_plugin`, `fn_uninstall_plugin`,
--       `fn_upgrade_plugin`, `fn_rotate_integration_credential`,
--       `fn_replay_webhook_delivery`);
--   (c) the two PRE-EXISTING (059-066) `app_api`-callable creation
--       functions that were ALREADY exposed to `app_api` before this
--       migration and share the identical defect class
--       (`fn_create_integration_connection`, `fn_create_plugin_
--       installation`) — this is a historical defect in 059-066,
--       exposed by this review, closed here via CREATE OR REPLACE
--       rather than by editing 061_5I.sql/065_5I.sql;
--   (d) `fn_redeem_oauth_attempt` (061, pre-existing, not used by
--       6J's own callback flow but independently `app_api`-callable
--       and sharing the same defect class — closed for defense in
--       depth, consistent with (c)).
--
-- Function classes (per the governing remediation's own required
-- classification — do not apply one rule blindly to every function):
--
--   TENANT-BOUND RUNTIME FUNCTIONS (guard REQUIRED, listed above):
--     called from an authenticated tenant request (JWT/API key) or an
--     on-behalf-of-tenant worker job, where `app.tenant_id` is already
--     set by the caller per 6A §23.2/5B §16.1 before the call.
--
--   CALLBACK BOOTSTRAP FUNCTIONS (guard MUST NOT be applied):
--     `fn_redeem_oauth_callback_state`, `fn_fail_oauth_callback_state`,
--     `fn_record_oauth_exchange_failure` — called from the
--     unauthenticated OAuth callback hop, where NO tenant context
--     exists yet (that is precisely the bootstrap problem these
--     functions solve, ADR-6J-08). Applying the guard here would make
--     these functions permanently uncallable. Their security instead
--     rests on `state`'s own 256-bit unguessable, single-use, tenant-
--     bound-by-the-row-itself design (§13.3 of 6J), narrowly-scoped
--     `EXECUTE` grants (`app_api, app_platform_admin` only — no
--     `app_worker`, since no worker process handles OAuth callbacks),
--     and — new this revision — explicit binding of `state` to the
--     expected provider/definition BEFORE consuming it (closes a
--     separate P0, see below).
--
--   WORKER/SYSTEM FUNCTIONS (not modified by this migration):
--     `fn_claim_delivery`, `fn_delivery_succeeded`, `fn_delivery_
--     failed`, `fn_update_inbound_event_status` (all `app_worker`-only,
--     operate across every tenant's queued work by design — a
--     per-tenant guard would break the worker pipeline entirely) and
--     `fn_integrations_anonymize_org` (`app_platform_admin`-only, GDPR
--     erasure — platform-admin cross-tenant access is its own,
--     separately-audited trust model, 6B §17.3 break-glass, not the
--     ordinary tenant-request path this guard targets). None of these
--     are touched by this migration.
--
-- ================================================================
-- OAUTH STATE-MACHINE CORRECTION — SECOND FIX OF THIS REVISION
-- ================================================================
-- The first revision of this file introduced a genuine self-
-- contradiction: `fn_redeem_oauth_callback_state` transitions
-- `PENDING -> REDEEMED` *before* the caller performs the actual
-- provider token exchange (correct — redemption and token exchange
-- are necessarily two separate steps, since redemption must be
-- atomic/single-use while token exchange is an external HTTP call
-- that must never happen inside the same DB transaction, 6A §35). But
-- the first revision's `fn_fail_oauth_callback_state` explicitly
-- REJECTED an attempt already in `REDEEMED` status — while its own
-- accompanying documentation claimed it also handled "token exchange
-- failure after successful redemption." Those two statements cannot
-- both be true of the same function.
--
-- Corrected design (Option B from the governing remediation: retain
-- the existing status vocabulary, add a separate exchange-outcome
-- field, rather than inventing new CHECK-constrained status values):
--   - `oauth_attempts.exchange_failed_at TIMESTAMPTZ NULL` (new column,
--     this revision) records a POST-redemption token-exchange failure
--     without changing `status` away from `REDEEMED` — `REDEEMED`
--     correctly continues to mean "this state value has been consumed
--     and can never be redeemed again" (the single-use replay-safety
--     guarantee, INV-INT-03, is completely unaffected).
--   - `fn_fail_oauth_callback_state` is now unambiguously scoped to
--     the PRE-redemption denial path only (`PENDING -> FAILED`,
--     provider returned `?error=...` before any code was ever
--     exchanged) — its rejection of an already-`REDEEMED` row is
--     therefore correct and no longer contradicts anything.
--   - `fn_record_oauth_exchange_failure` (new function, this revision)
--     is the POST-redemption counterpart: requires `status = 'REDEEMED'`
--     exactly, sets `exchange_failed_at`/`failure_reason`, leaves
--     `status` unchanged. Idempotent on a second call (no-op if
--     `exchange_failed_at` is already set).
--
-- ================================================================
-- OAUTH STATE/PROVIDER BINDING — THIRD FIX OF THIS REVISION
-- ================================================================
-- The first revision's `fn_redeem_oauth_callback_state(p_state)`
-- verified only that `state` exists, is `PENDING`, and is unexpired —
-- it never checked that the *route* the caller arrived through
-- actually matches the `definition_id` the attempt was created for.
-- A `state` value issued for Provider A, presented at Provider B's
-- callback route (via a captured/leaked/misdirected redirect), would
-- have redeemed successfully and returned Provider A's `organization_id`
-- to Provider B's callback handler — a genuine cross-provider
-- confusion risk, independent of (and in addition to) the tenant-
-- forgery class above.
--
-- Corrected: `fn_redeem_oauth_callback_state(p_state, p_expected_
-- definition_id)` now takes the caller's own resolved "which provider
-- route am I" as a second parameter and verifies it against the row's
-- own `definition_id` BEFORE consuming the state — a mismatch raises
-- an exception and leaves the row untouched (still `PENDING`, still
-- redeemable later through the *correct* provider's callback route).
-- =================================================================

-- ================================================================
-- PLATFORM-WIDE LATENT DEFECT — DISCOVERED BY LIVE EXECUTION OF THIS
-- MIGRATION, FIXED HERE (out of 6J's original scope, but a hard
-- prerequisite for this migration's own functions, and safe/additive
-- to fix once, here, for every affected caller platform-wide).
--
-- `public.gen_uuid_v7()` (001_5B.sql) is LANGUAGE plpgsql with NO
-- `SET search_path` of its own, and its body calls the unqualified
-- `gen_random_bytes(10)` (installed by pgcrypto into `public`,
-- confirmed live: `SELECT extnamespace::regnamespace FROM pg_extension
-- WHERE extname='pgcrypto'` -> `public`). PL/pgSQL re-resolves
-- unqualified names against the ACTIVE search_path at each execution
-- (unlike a table column's DEFAULT expression, which binds to a fixed
-- function OID at table-definition time and is therefore NOT
-- affected). When `gen_uuid_v7()` executes nested inside a
-- `SECURITY DEFINER` function that sets `SET search_path = <schema>,
-- pg_catalog` (the universal convention this entire codebase uses —
-- confirmed live: 99 SECURITY DEFINER functions across the full
-- 001-100 baseline set a search_path, 84 of those exclude `public`),
-- it inherits THAT restricted search_path, not the calling session's
-- own — and `gen_random_bytes` cannot be found. Live-reproduced
-- directly against this instance (see the validation report/execution
-- logs for the exact repro and error text) — this is a real,
-- pre-existing defect in the frozen 001-100 baseline, not something
-- introduced by this file, and not scoped to `integrations`/`plugins`/
-- `webhooks` — every one of the 84 affected functions, in every
-- phase's schema, is at risk the moment its own body (or a table
-- DEFAULT it triggers) calls `gen_uuid_v7()`.
--
-- Fix: `CREATE OR REPLACE FUNCTION public.gen_uuid_v7()` adding a
-- fixed `SET search_path = public, pg_catalog` — this function is NOT
-- `SECURITY DEFINER`, so pinning its search_path changes no privilege
-- boundary whatsoever, it only fixes which functions are visible while
-- IT runs, regardless of which caller's context it was invoked from.
-- This single, minimal, purely-additive change transitively fixes all
-- 84 affected functions platform-wide without touching any of their
-- individual definitions — the smallest possible fix for the largest
-- possible correctness win. Flagged prominently in 6J's own
-- documentation as a finding whose scope exceeds 6J (§62/validation
-- report) — a full audit of which of the other 83 functions actually
-- exercise the broken path in practice is out of this migration's
-- scope and is recorded as a forward finding for the owning phases.
-- ================================================================
CREATE OR REPLACE FUNCTION gen_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_millis  BIGINT := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
  v_rand    BYTEA  := gen_random_bytes(10);
BEGIN
  RETURN (
    lpad(to_hex(v_millis), 12, '0') ||
    '7' ||
    lpad(to_hex(get_byte(v_rand,0) * 256 + get_byte(v_rand,1)), 3, '0') ||
    '-' ||
    lpad(to_hex((get_byte(v_rand,2) & 63) | 128), 2, '0') ||
    lpad(to_hex(get_byte(v_rand,3)), 2, '0') ||
    '-' ||
    encode(substring(v_rand FROM 4 FOR 6), 'hex')
  )::UUID;
END;
$$;
-- Grants unchanged (CREATE OR REPLACE preserves existing grants; this
-- function was never REVOKEd from PUBLIC in 001_5B.sql).

-- -----------------------------------------------------------------
-- 1. oauth_attempts: new columns (additive, nullable)
--    - connection_id: closes DEP-6J-04 — the attempt's owning
--      connection is now an explicit FK, not inferred.
--    - failure_reason: pre-redemption denial reason (fn_fail_oauth_
--      callback_state) and, reused, post-redemption exchange-failure
--      reason (fn_record_oauth_exchange_failure).
--    - exchange_failed_at: NEW this revision — see the OAuth
--      state-machine correction note above.
-- -----------------------------------------------------------------
ALTER TABLE integrations.oauth_attempts
  ADD COLUMN connection_id UUID NULL
    REFERENCES integrations.integration_connections(id) ON DELETE CASCADE,
  ADD COLUMN failure_reason TEXT NULL,
  ADD COLUMN exchange_failed_at TIMESTAMPTZ NULL;

ALTER TABLE integrations.oauth_attempts
  ADD CONSTRAINT chk_oa_failure_reason_len
    CHECK (failure_reason IS NULL OR length(failure_reason) <= 1000);

CREATE INDEX idx_oa_connection ON integrations.oauth_attempts (connection_id)
  WHERE connection_id IS NOT NULL;

-- -----------------------------------------------------------------
-- 2. webhook_endpoints: new columns for dual-secret rotation grace.
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
-- Every function below: tenant-bound runtime function, guard applied.
-- ===================================================================

CREATE OR REPLACE FUNCTION integrations.fn_activate_integration_connection(
  p_organization_id       UUID,
  p_connection_id         UUID,
  p_credential_ref        TEXT DEFAULT NULL,
  p_external_account_ref  TEXT DEFAULT NULL,
  p_external_account_name TEXT DEFAULT NULL,
  p_connected_by_ref      UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;
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

CREATE OR REPLACE FUNCTION integrations.fn_fail_integration_connection(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_reason          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION integrations.fn_degrade_integration_connection(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_reason          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION integrations.fn_disconnect_integration_connection(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_reason          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION integrations.fn_update_integration_connection_config(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_display_name    TEXT DEFAULT NULL,
  p_configuration   JSONB DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION integrations.fn_record_integration_sync_result(
  p_organization_id UUID,
  p_connection_id   UUID,
  p_success         BOOLEAN,
  p_error_message   TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;

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
-- fn_create_integration_connection: CREATE OR REPLACE, SAME signature.
-- Adds (a) the tenant-forgery guard — closes a historical 059-066
-- defect exposed by this review (remediation §9) — and (b) the
-- is_active check (closes former DEP-6J-09), both additive to the
-- original 061_5I body.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_create_integration_connection(
  p_organization_id   UUID,
  p_definition_id     UUID,
  p_display_name      TEXT,
  p_credential_ref    TEXT,
  p_configuration     JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_existing_id  UUID;
  v_new_id       UUID;
  v_is_active    BOOLEAN;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;
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
-- Grants unchanged from 061_5I (CREATE OR REPLACE preserves existing grants).

-- -------------------------------------------------------------
-- fn_rotate_integration_credential: CREATE OR REPLACE, SAME signature.
-- Adds the tenant-forgery guard — this function is widened to app_api
-- by this migration's grant section below, so the guard is required.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_rotate_integration_credential(
  p_organization_id           UUID,
  p_integration_connection_id UUID,
  p_new_credential_ref        TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;
  IF p_new_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: new credential_ref must be a secret_manager:// reference';
  END IF;

  UPDATE integrations.integration_connections
  SET credential_ref = p_new_credential_ref, updated_at = NOW()
  WHERE id = p_integration_connection_id
    AND organization_id = p_organization_id
    AND status NOT IN ('DISCONNECTED','FAILED');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found or is in terminal state';
  END IF;
END;
$$;
-- Grants unchanged from 061_5I (app_worker, app_platform_admin); app_api added below.

-- -------------------------------------------------------------
-- fn_redeem_oauth_attempt: CREATE OR REPLACE, SAME signature. Adds the
-- tenant-forgery guard for defense in depth (remediation §9) — this
-- function is not called by 6J's own flow (fn_redeem_oauth_callback_
-- state is), but remains independently app_api-callable and shares
-- the identical defect class, so it is hardened identically.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_redeem_oauth_attempt(
  p_state           TEXT,
  p_organization_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, organization, pg_catalog AS $$
DECLARE
  v_id       UUID;
  v_status   TEXT;
  v_expires  TIMESTAMPTZ;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'integrations: caller tenant context does not match the requested organization';
  END IF;

  SELECT id, status, expires_at INTO v_id, v_status, v_expires
  FROM integrations.oauth_attempts
  WHERE state = p_state AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found for this organization';
  END IF;
  IF v_status = 'REDEEMED' THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % already redeemed', v_id;
  END IF;
  IF v_status IN ('EXPIRED','FAILED') THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % is in terminal state %', v_id, v_status;
  END IF;
  IF v_expires <= NOW() THEN
    UPDATE integrations.oauth_attempts SET status = 'EXPIRED' WHERE id = v_id;
    RAISE EXCEPTION 'integrations: OAuth attempt % has expired', v_id;
  END IF;

  UPDATE integrations.oauth_attempts
  SET status = 'REDEEMED', redeemed_at = NOW()
  WHERE id = v_id;

  RETURN v_id;
END;
$$;
-- Grants unchanged from 061_5I (app_api, app_worker, app_platform_admin).

-- ===================================================================
-- OAUTH CALLBACK TENANT BOOTSTRAP (closes the P0 defect, ADR-6J-08)
-- Callback bootstrap functions — NO tenant-forgery guard (see the
-- "Function classes" note at the top of this file).
-- ===================================================================

-- -------------------------------------------------------------
-- fn_redeem_oauth_callback_state: the ONLY redemption path used by
-- the unauthenticated browser-callback endpoint. Takes `state` PLUS
-- (new this revision) `p_expected_definition_id` — the calling
-- Provider Adapter's own resolved "which provider route is this,"
-- verified against the row's own definition_id BEFORE the state is
-- consumed. A mismatch leaves the row untouched (still PENDING,
-- redeemable later through the correct route) — closes the OAuth
-- state/provider-binding P0.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_redeem_oauth_callback_state(
  p_state                    TEXT,
  p_expected_definition_id   UUID
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
  v_id            UUID;
  v_status        TEXT;
  v_expires       TIMESTAMPTZ;
  v_definition_id UUID;
BEGIN
  SELECT oa.id, oa.status, oa.expires_at, oa.definition_id
  INTO v_id, v_status, v_expires, v_definition_id
  FROM integrations.oauth_attempts oa
  WHERE oa.state = p_state
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found';
  END IF;

  -- Provider/definition binding check BEFORE any status mutation —
  -- a mismatch must never consume the state (closes the P0 binding gap).
  IF v_definition_id <> p_expected_definition_id THEN
    RAISE EXCEPTION 'integrations: OAuth attempt was not issued for the expected provider';
  END IF;

  IF v_status = 'REDEEMED' THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % already redeemed', v_id;
  END IF;
  IF v_status IN ('EXPIRED', 'FAILED') THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % is in terminal state %', v_id, v_status;
  END IF;
  IF v_expires <= NOW() THEN
    -- Deliberately does NOT `UPDATE ... SET status = 'EXPIRED'` before
    -- raising (corrects a live-discovered defect present identically in
    -- the pre-existing, unmodified fn_redeem_oauth_attempt, 061_5I.sql):
    -- an UPDATE immediately followed by RAISE EXCEPTION in the same
    -- statement/transaction is rolled back by that same exception unless
    -- the caller wraps the call in its own PL/pgSQL exception block
    -- (creating an implicit savepoint) — an ordinary top-level
    -- Application Service call does not, so the UPDATE's effect is
    -- silently lost and `status` never actually persists as 'EXPIRED'
    -- through this path. This is an OBSERVABILITY-ONLY gap, not a
    -- security defect: expiry is re-derived live from `expires_at <=
    -- NOW()` on every call (as above), so a stale-but-technically-still-
    -- PENDING row can never be redeemed past its expiry regardless of
    -- what `status` displays. Marking `status = 'EXPIRED'` for reporting
    -- purposes is left to a periodic housekeeping sweep (out of this
    -- migration's scope, matching the platform's own established
    -- "no pg_cron; documented cleanup query for an external process"
    -- pattern already used for retention elsewhere, e.g. the outbox
    -- table's own retention note, 077_5J1.sql) rather than attempted
    -- here where it cannot actually succeed.
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
REVOKE ALL ON FUNCTION integrations.fn_redeem_oauth_callback_state(TEXT, UUID) FROM PUBLIC;
-- Least privilege (remediation §7): only Core API's own callback handler
-- (app_api) and platform_admin (support/break-glass introspection) —
-- no worker process ever handles an OAuth callback.
GRANT EXECUTE ON FUNCTION integrations.fn_redeem_oauth_callback_state(TEXT, UUID)
  TO app_api, app_platform_admin;

-- -------------------------------------------------------------
-- fn_fail_oauth_callback_state: PRE-redemption denial path only
-- (PENDING -> FAILED). Explicitly rejects an already-REDEEMED attempt
-- — that case is fn_record_oauth_exchange_failure's job instead (see
-- the OAuth state-machine correction note at the top of this file).
-- Also binds to the expected provider, mirroring the redemption path.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_fail_oauth_callback_state(
  p_state                  TEXT,
  p_expected_definition_id UUID,
  p_reason                 TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_id            UUID;
  v_status        TEXT;
  v_definition_id UUID;
BEGIN
  SELECT id, status, definition_id INTO v_id, v_status, v_definition_id
  FROM integrations.oauth_attempts
  WHERE state = p_state
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found';
  END IF;
  IF v_definition_id <> p_expected_definition_id THEN
    RAISE EXCEPTION 'integrations: OAuth attempt was not issued for the expected provider';
  END IF;
  IF v_status = 'FAILED' THEN
    RETURN v_id; -- idempotent
  END IF;
  IF v_status = 'REDEEMED' THEN
    RAISE EXCEPTION
      'integrations: OAuth attempt % already redeemed — use fn_record_oauth_exchange_failure '
      'for a post-redemption token-exchange failure instead', v_id;
  END IF;
  IF v_status = 'EXPIRED' THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % is already EXPIRED', v_id;
  END IF;

  UPDATE integrations.oauth_attempts
  SET status = 'FAILED', failure_reason = LEFT(COALESCE(p_reason, 'provider_denied'), 1000)
  WHERE id = v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_fail_oauth_callback_state(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_fail_oauth_callback_state(TEXT, UUID, TEXT)
  TO app_api, app_platform_admin;

-- -------------------------------------------------------------
-- fn_record_oauth_exchange_failure: NEW this revision. POST-redemption
-- counterpart to fn_fail_oauth_callback_state — requires status =
-- REDEEMED exactly, records the failure without reopening the state
-- for reuse (status stays REDEEMED; single-use guarantee untouched).
-- Idempotent: a second call after exchange_failed_at is already set
-- is a no-op. No provider-binding check needed here — this is always
-- called as a direct continuation of the same request that already
-- passed fn_redeem_oauth_callback_state's own binding check; there is
-- no separate untrusted routing decision being made a second time.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_record_oauth_exchange_failure(
  p_state  TEXT,
  p_reason TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_id                 UUID;
  v_status             TEXT;
  v_exchange_failed_at TIMESTAMPTZ;
BEGIN
  SELECT id, status, exchange_failed_at INTO v_id, v_status, v_exchange_failed_at
  FROM integrations.oauth_attempts
  WHERE state = p_state
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found';
  END IF;
  IF v_status <> 'REDEEMED' THEN
    RAISE EXCEPTION
      'integrations: exchange failure can only be recorded for a REDEEMED attempt (current status %)', v_status;
  END IF;
  IF v_exchange_failed_at IS NOT NULL THEN
    RETURN v_id; -- idempotent
  END IF;

  UPDATE integrations.oauth_attempts
  SET exchange_failed_at = NOW(),
      failure_reason     = LEFT(COALESCE(p_reason, 'token_exchange_failed'), 1000)
  WHERE id = v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_record_oauth_exchange_failure(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_record_oauth_exchange_failure(TEXT, TEXT)
  TO app_api, app_platform_admin;

-- ===================================================================
-- PLUGIN INSTALLATION LIFECYCLE (closes DEP-6J-02, P0)
-- Every function below: tenant-bound runtime function, guard applied.
-- ===================================================================

CREATE OR REPLACE FUNCTION plugins.fn_suspend_plugin_installation(
  p_organization_id UUID,
  p_installation_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION plugins.fn_reactivate_plugin_installation(
  p_organization_id UUID,
  p_installation_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_status         TEXT;
  v_plugin_status  TEXT;
  v_version_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION plugins.fn_update_plugin_installation_config(
  p_organization_id UUID,
  p_installation_id UUID,
  p_configuration   JSONB DEFAULT NULL,
  p_rate_limit_override INTEGER DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

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

CREATE OR REPLACE FUNCTION plugins.fn_rotate_plugin_installation_credential(
  p_organization_id    UUID,
  p_installation_id    UUID,
  p_new_credential_ref TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;
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

-- -------------------------------------------------------------
-- fn_create_plugin_installation: CREATE OR REPLACE, SAME signature.
-- Adds the tenant-forgery guard (remediation §9 — same historical
-- defect class as fn_create_integration_connection).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION plugins.fn_create_plugin_installation(
  p_organization_id   UUID,
  p_plugin_id         UUID,
  p_plugin_version_id UUID,
  p_configuration     JSONB DEFAULT '{}',
  p_credential_ref    TEXT DEFAULT NULL,
  p_installed_by_ref  UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_plugin_status  TEXT;
  v_version_status TEXT;
  v_version_plugin UUID;
  v_new_id         UUID;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

  SELECT pv.status, pv.plugin_id, pl.status
  INTO v_version_status, v_version_plugin, v_plugin_status
  FROM plugins.plugin_versions pv
  JOIN plugins.plugins pl ON pl.id = pv.plugin_id
  WHERE pv.id = p_plugin_version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: plugin version % not found', p_plugin_version_id;
  END IF;
  IF v_version_plugin <> p_plugin_id THEN
    RAISE EXCEPTION 'plugins: version % does not belong to plugin %',
      p_plugin_version_id, p_plugin_id;
  END IF;
  IF v_plugin_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin % is not APPROVED (status=%)', p_plugin_id, v_plugin_status;
  END IF;
  IF v_version_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: version % is not APPROVED (status=%)',
      p_plugin_version_id, v_version_status;
  END IF;
  IF p_credential_ref IS NOT NULL AND p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'plugins: credential_ref must be a secret_manager:// reference';
  END IF;

  INSERT INTO plugins.plugin_installations
    (organization_id, plugin_id, plugin_version_id, configuration,
     credential_ref, installed_by_ref)
  VALUES
    (p_organization_id, p_plugin_id, p_plugin_version_id, p_configuration,
     p_credential_ref, p_installed_by_ref)
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;
-- Grants unchanged from 065_5I (CREATE OR REPLACE preserves existing grants).

-- -------------------------------------------------------------
-- fn_activate_plugin / fn_uninstall_plugin / fn_upgrade_plugin:
-- CREATE OR REPLACE, SAME signatures. Adds the tenant-forgery guard —
-- required because this migration widens all three to app_api below.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION plugins.fn_activate_plugin(
  p_organization_id      UUID,
  p_installation_id      UUID,
  p_enabled_capabilities TEXT[]
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_inst          RECORD;
  v_manifest_caps TEXT[];
  v_cap           TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

  SELECT pi.status, pi.plugin_version_id,
         pv.status AS version_status, pl.status AS plugin_status, pv.manifest
  INTO v_inst
  FROM plugins.plugin_installations pi
  JOIN plugins.plugin_versions pv ON pv.id = pi.plugin_version_id
  JOIN plugins.plugins pl ON pl.id = pi.plugin_id
  WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_inst.status NOT IN ('INSTALLED','SUSPENDED') THEN
    RAISE EXCEPTION 'plugins: cannot activate from status %', v_inst.status;
  END IF;
  IF v_inst.plugin_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin is not APPROVED';
  END IF;
  IF v_inst.version_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin version is not APPROVED (status=%)', v_inst.version_status;
  END IF;

  SELECT ARRAY(SELECT jsonb_array_elements_text(v_inst.manifest -> 'capabilities'))
  INTO v_manifest_caps;

  FOREACH v_cap IN ARRAY p_enabled_capabilities LOOP
    IF NOT (v_cap = ANY(v_manifest_caps)) THEN
      RAISE EXCEPTION 'plugins: capability % is not in the plugin version manifest', v_cap;
    END IF;
  END LOOP;

  UPDATE plugins.plugin_installations
  SET status               = 'ACTIVE',
      enabled_capabilities = p_enabled_capabilities,
      activated_at         = COALESCE(activated_at, NOW()),
      updated_at           = NOW()
  WHERE id = p_installation_id;
END;
$$;
-- Grants: unchanged from 065_5I (app_worker, app_platform_admin); app_api added below.

CREATE OR REPLACE FUNCTION plugins.fn_uninstall_plugin(
  p_organization_id UUID,
  p_installation_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

  SELECT status INTO v_status
  FROM plugins.plugin_installations
  WHERE id = p_installation_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found';
  END IF;
  IF v_status = 'UNINSTALLED' THEN
    RETURN; -- idempotent
  END IF;

  UPDATE plugins.plugin_installations
  SET status         = 'UNINSTALLED',
      uninstalled_at = NOW(),
      updated_at     = NOW()
  WHERE id = p_installation_id;
END;
$$;
-- Grants: unchanged from 065_5I (app_worker, app_platform_admin); app_api added below.

CREATE OR REPLACE FUNCTION plugins.fn_upgrade_plugin(
  p_organization_id   UUID,
  p_installation_id   UUID,
  p_new_version_id    UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, organization, pg_catalog AS $$
DECLARE
  v_inst       RECORD;
  v_new_ver    RECORD;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'plugins: caller tenant context does not match the requested organization';
  END IF;

  SELECT pi.status, pi.plugin_id, pi.plugin_version_id
  INTO v_inst
  FROM plugins.plugin_installations pi
  WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_inst.status = 'UNINSTALLED' THEN
    RAISE EXCEPTION 'plugins: cannot upgrade UNINSTALLED installation';
  END IF;

  SELECT pv.plugin_id, pv.status
  INTO v_new_ver
  FROM plugins.plugin_versions pv
  WHERE pv.id = p_new_version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: new version % not found', p_new_version_id;
  END IF;
  IF v_new_ver.plugin_id <> v_inst.plugin_id THEN
    RAISE EXCEPTION 'plugins: version % does not belong to the same plugin', p_new_version_id;
  END IF;
  IF v_new_ver.status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: new version % is not APPROVED (status=%)',
      p_new_version_id, v_new_ver.status;
  END IF;
  IF p_new_version_id = v_inst.plugin_version_id THEN
    RETURN; -- already on this version; idempotent
  END IF;

  PERFORM set_config('plugins.upgrade_in_progress', 'true', TRUE);

  UPDATE plugins.plugin_installations
  SET plugin_version_id    = p_new_version_id,
      enabled_capabilities = '{}',
      status               = 'INSTALLED',
      updated_at           = NOW()
  WHERE id = p_installation_id;

  PERFORM set_config('plugins.upgrade_in_progress', 'false', TRUE);
END;
$$;
-- Grants: unchanged from 065_5I (app_worker, app_platform_admin); app_api added below.

-- ===================================================================
-- WEBHOOK DUAL-SECRET ROTATION (closes the P0 defect)
-- ===================================================================

CREATE OR REPLACE FUNCTION webhooks.fn_rotate_webhook_secret(
  p_organization_id      UUID,
  p_webhook_endpoint_id  UUID,
  p_new_signing_secret_ref TEXT,
  p_grace_period_seconds INTEGER DEFAULT 3600
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, organization, pg_catalog AS $$
DECLARE
  v_current_secret_ref TEXT;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'webhooks: caller tenant context does not match the requested organization';
  END IF;
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

-- -------------------------------------------------------------
-- fn_replay_webhook_delivery: CREATE OR REPLACE, SAME signature. Adds
-- the tenant-forgery guard — required because this migration widens
-- this function to app_api below.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION webhooks.fn_replay_webhook_delivery(
  p_organization_id UUID,
  p_delivery_id     UUID,
  p_created_at      TIMESTAMPTZ
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, organization, pg_catalog AS $$
DECLARE
  v_orig            RECORD;
  v_new_id          UUID := gen_uuid_v7();
  v_existing_replay UUID;
BEGIN
  IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
    RAISE EXCEPTION 'webhooks: caller tenant context does not match the requested organization';
  END IF;

  SELECT * INTO v_orig
  FROM webhooks.webhook_deliveries
  WHERE id = p_delivery_id AND created_at = p_created_at AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'webhooks: delivery not found';
  END IF;
  IF v_orig.status NOT IN ('DEAD_LETTER','DELIVERED') THEN
    RAISE EXCEPTION 'webhooks: only DEAD_LETTER or DELIVERED deliveries can be replayed; status = %',
      v_orig.status;
  END IF;

  SELECT id INTO v_existing_replay
  FROM webhooks.webhook_deliveries
  WHERE replay_of_delivery_id = p_delivery_id AND status IN ('PENDING','DELIVERING');
  IF FOUND THEN
    RETURN v_existing_replay;
  END IF;

  INSERT INTO webhooks.webhook_deliveries
    (id, organization_id, webhook_endpoint_id, event_type, event_id,
     payload_json, payload_hash, status, max_attempts, next_attempt_at, replay_of_delivery_id)
  VALUES
    (v_new_id, p_organization_id, v_orig.webhook_endpoint_id,
     v_orig.event_type, v_orig.event_id,
     v_orig.payload_json, v_orig.payload_hash,
     'PENDING', v_orig.max_attempts, NOW(), p_delivery_id);

  UPDATE webhooks.webhook_deliveries
  SET replay_count     = replay_count + 1,
      last_replayed_at = NOW()
  WHERE id = p_delivery_id AND created_at = p_created_at;

  RETURN v_new_id;
END;
$$;
-- Grants: unchanged from 063_5I (app_worker, app_platform_admin); app_api added below.

-- ===================================================================
-- EXECUTE-GRANT WIDENING (ADR-6J-01) — every widened function above
-- has just been hardened with the tenant-forgery guard via CREATE OR
-- REPLACE; these grants are now safe to add.
-- ===================================================================
GRANT EXECUTE ON FUNCTION plugins.fn_activate_plugin(UUID, UUID, TEXT[]) TO app_api;
GRANT EXECUTE ON FUNCTION plugins.fn_uninstall_plugin(UUID, UUID) TO app_api;
GRANT EXECUTE ON FUNCTION plugins.fn_upgrade_plugin(UUID, UUID, UUID) TO app_api;
GRANT EXECUTE ON FUNCTION integrations.fn_rotate_integration_credential(UUID, UUID, TEXT) TO app_api;
GRANT EXECUTE ON FUNCTION webhooks.fn_replay_webhook_delivery(UUID, UUID, TIMESTAMPTZ) TO app_api;

-- ===================================================================
-- Retention note (documentation only, no pg_cron): unchanged from the
-- first revision of this file — see the closing comment block that
-- was here before; oauth_attempts purge policy and
-- previous_signing_secret_ref operational-expiry handling are
-- application-layer/ops concerns, not altered by this revision's
-- security corrections.
-- ===================================================================
