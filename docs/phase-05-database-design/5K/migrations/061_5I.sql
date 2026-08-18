-- Migration 061 (Phase 5I): integration_connections, oauth_attempts, integration_health + all SECURITY DEFINER functions
-- down_revision: 060_5I
CREATE TABLE integrations.integration_connections (
  id                    UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID        NOT NULL,
  definition_id         UUID        NOT NULL REFERENCES integrations.integration_definitions(id) ON DELETE RESTRICT,
  display_name          TEXT        NOT NULL,
  status                TEXT        NOT NULL DEFAULT 'CONNECTING',
  credential_ref        TEXT        NOT NULL,
  configuration         JSONB       NOT NULL DEFAULT '{}',
  enabled_capabilities  TEXT[]      NOT NULL DEFAULT '{}',
  external_account_ref  TEXT        NULL,
  external_account_name TEXT        NULL,
  last_sync_at          TIMESTAMPTZ NULL,
  last_sync_error       TEXT        NULL,
  connected_at          TIMESTAMPTZ NULL,
  connected_by_ref      UUID        NULL,
  disconnected_at       TIMESTAMPTZ NULL,
  disconnect_reason     TEXT        NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_integration_connections PRIMARY KEY (id),
  CONSTRAINT chk_ic_status              CHECK (status IN ('CONNECTING','ACTIVE','DEGRADED','DISCONNECTED','FAILED')),
  CONSTRAINT chk_ic_credential_ref      CHECK (credential_ref LIKE 'secret_manager://%'),
  CONSTRAINT chk_ic_display_name        CHECK (length(display_name) BETWEEN 1 AND 200),
  CONSTRAINT chk_ic_sync_error_len      CHECK (last_sync_error IS NULL OR length(last_sync_error) <= 1000),
  CONSTRAINT chk_ic_terminal_has_at     CHECK ((status IN ('DISCONNECTED','FAILED') AND disconnected_at IS NOT NULL) OR status NOT IN ('DISCONNECTED','FAILED'))
);
COMMENT ON COLUMN integrations.integration_connections.external_account_name IS 'pii:name';
CREATE INDEX idx_ic_org_def_nonterminal ON integrations.integration_connections (organization_id, definition_id) WHERE status NOT IN ('DISCONNECTED','FAILED');
CREATE INDEX idx_ic_org_status          ON integrations.integration_connections (organization_id, status);
CREATE INDEX idx_ic_ext_account         ON integrations.integration_connections (definition_id, external_account_ref) WHERE external_account_ref IS NOT NULL;
CREATE OR REPLACE FUNCTION integrations.fn_ic_terminal_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  IF OLD.status IN ('DISCONNECTED','FAILED') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'integrations: connection % is in terminal state % — create a new connection', OLD.id, OLD.status;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_ic_terminal_guard() FROM PUBLIC;
CREATE TRIGGER trg_ic_terminal_guard BEFORE UPDATE ON integrations.integration_connections FOR EACH ROW EXECUTE FUNCTION integrations.fn_ic_terminal_guard();
CREATE TRIGGER trg_ic_updated_at     BEFORE UPDATE ON integrations.integration_connections FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE integrations.integration_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.integration_connections FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ic_tenant ON integrations.integration_connections FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE INSERT, UPDATE, DELETE ON integrations.integration_connections FROM app_api, app_worker;
GRANT SELECT ON integrations.integration_connections TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON integrations.integration_connections TO app_platform_admin;

-- integration_health (must exist before fn_create_integration_connection references it)
CREATE TABLE integrations.integration_health (
  id                        UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id           UUID        NOT NULL,
  integration_connection_id UUID        NOT NULL REFERENCES integrations.integration_connections(id) ON DELETE CASCADE,
  last_success_at           TIMESTAMPTZ NULL,
  last_failure_at           TIMESTAMPTZ NULL,
  consecutive_failure_count INTEGER     NOT NULL DEFAULT 0,
  last_failure_reason       TEXT        NULL,
  auth_failure_count        INTEGER     NOT NULL DEFAULT 0,
  rate_limit_reset_at       TIMESTAMPTZ NULL,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_integration_health     PRIMARY KEY (id),
  CONSTRAINT uq_ih_connection          UNIQUE (integration_connection_id),
  CONSTRAINT chk_ih_failure_count      CHECK (consecutive_failure_count >= 0),
  CONSTRAINT chk_ih_auth_count         CHECK (auth_failure_count >= 0),
  CONSTRAINT chk_ih_failure_reason_len CHECK (last_failure_reason IS NULL OR length(last_failure_reason) <= 1000)
);
CREATE INDEX idx_ih_org ON integrations.integration_health (organization_id);
CREATE TRIGGER trg_ih_updated_at BEFORE UPDATE ON integrations.integration_health FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE integrations.integration_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.integration_health FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ih_tenant ON integrations.integration_health FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON integrations.integration_health TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON integrations.integration_health TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON integrations.integration_health TO app_platform_admin;

-- fn_create_integration_connection (references integration_health — must be after)
CREATE OR REPLACE FUNCTION integrations.fn_create_integration_connection(
  p_organization_id UUID, p_definition_id UUID, p_display_name TEXT,
  p_credential_ref TEXT, p_configuration JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE v_existing_id UUID; v_new_id UUID;
BEGIN
  IF p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: credential_ref must be a secret_manager:// reference';
  END IF;
  SELECT id INTO v_existing_id FROM integrations.integration_connections
  WHERE organization_id = p_organization_id AND definition_id = p_definition_id AND status NOT IN ('DISCONNECTED','FAILED')
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION 'integrations: a non-terminal connection (id=%) already exists for this (org, definition). Disconnect it first.', v_existing_id;
  END IF;
  INSERT INTO integrations.integration_connections (organization_id, definition_id, display_name, credential_ref, configuration, status)
  VALUES (p_organization_id, p_definition_id, p_display_name, p_credential_ref, p_configuration, 'CONNECTING')
  RETURNING id INTO v_new_id;
  INSERT INTO integrations.integration_health (organization_id, integration_connection_id)
  VALUES (p_organization_id, v_new_id) ON CONFLICT (integration_connection_id) DO NOTHING;
  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_create_integration_connection(UUID, UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_create_integration_connection(UUID, UUID, TEXT, TEXT, JSONB) TO app_api, app_worker, app_platform_admin;

CREATE TABLE integrations.oauth_attempts (
  id               UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID        NOT NULL,
  definition_id    UUID        NOT NULL REFERENCES integrations.integration_definitions(id) ON DELETE RESTRICT,
  state            TEXT        NOT NULL,
  code_verifier    TEXT        NULL,
  redirect_uri     TEXT        NOT NULL,
  requested_scopes TEXT[]      NOT NULL DEFAULT '{}',
  status           TEXT        NOT NULL DEFAULT 'PENDING',
  expires_at       TIMESTAMPTZ NOT NULL,
  redeemed_at      TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_oauth_attempts   PRIMARY KEY (id),
  CONSTRAINT uq_oa_state         UNIQUE (state),
  CONSTRAINT chk_oa_status       CHECK (status IN ('PENDING','REDEEMED','EXPIRED','FAILED')),
  CONSTRAINT chk_oa_expires      CHECK (expires_at > created_at),
  CONSTRAINT chk_oa_redirect_uri CHECK (redirect_uri LIKE 'https://%' OR redirect_uri LIKE 'http://localhost%')
);
CREATE INDEX idx_oa_org_expires ON integrations.oauth_attempts (organization_id, expires_at);
ALTER TABLE integrations.oauth_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.oauth_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_oa_tenant ON integrations.oauth_attempts FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON integrations.oauth_attempts FROM app_api, app_worker;
GRANT SELECT, INSERT ON integrations.oauth_attempts TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON integrations.oauth_attempts TO app_platform_admin;

CREATE OR REPLACE FUNCTION integrations.fn_redeem_oauth_attempt(p_state TEXT, p_organization_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE v_id UUID; v_status TEXT; v_expires TIMESTAMPTZ;
BEGIN
  SELECT id, status, expires_at INTO v_id, v_status, v_expires
  FROM integrations.oauth_attempts WHERE state = p_state AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'integrations: OAuth attempt not found for this organization'; END IF;
  IF v_status = 'REDEEMED' THEN RAISE EXCEPTION 'integrations: OAuth attempt % already redeemed', v_id; END IF;
  IF v_status IN ('EXPIRED','FAILED') THEN RAISE EXCEPTION 'integrations: OAuth attempt % is in terminal state %', v_id, v_status; END IF;
  IF v_expires <= NOW() THEN
    UPDATE integrations.oauth_attempts SET status = 'EXPIRED' WHERE id = v_id;
    RAISE EXCEPTION 'integrations: OAuth attempt % has expired', v_id;
  END IF;
  UPDATE integrations.oauth_attempts SET status = 'REDEEMED', redeemed_at = NOW() WHERE id = v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_redeem_oauth_attempt(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_redeem_oauth_attempt(TEXT, UUID) TO app_api, app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION integrations.fn_rotate_integration_credential(
  p_organization_id UUID, p_integration_connection_id UUID, p_new_credential_ref TEXT
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  IF p_new_credential_ref NOT LIKE 'secret_manager://%' THEN RAISE EXCEPTION 'integrations: new credential_ref must be a secret_manager:// reference'; END IF;
  UPDATE integrations.integration_connections SET credential_ref = p_new_credential_ref, updated_at = NOW()
  WHERE id = p_integration_connection_id AND organization_id = p_organization_id AND status NOT IN ('DISCONNECTED','FAILED');
  IF NOT FOUND THEN RAISE EXCEPTION 'integrations: connection not found or is in terminal state'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_rotate_integration_credential(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_rotate_integration_credential(UUID, UUID, TEXT) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION integrations.fn_integrations_anonymize_org(p_organization_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  UPDATE integrations.integration_connections
  SET external_account_name = '[redacted]', external_account_ref = NULL,
      status = CASE WHEN status NOT IN ('DISCONNECTED','FAILED') THEN 'DISCONNECTED' ELSE status END,
      disconnected_at = CASE WHEN status NOT IN ('DISCONNECTED','FAILED') THEN NOW() ELSE disconnected_at END,
      disconnect_reason = 'gdpr_erasure', updated_at = NOW()
  WHERE organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_integrations_anonymize_org(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_integrations_anonymize_org(UUID) TO app_platform_admin;
