-- =================================================================
-- Migration 002 (Phase 5B): identity schema tables
-- down_revision: 001_5B
-- Transaction: yes
-- Source: 5B §33.2
-- RLS for identity.api_keys bundled here (5K §4.1 pattern)
-- =================================================================

-- identity.users
CREATE TABLE identity.users (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  email                TEXT        NOT NULL,
  email_normalized     TEXT        NOT NULL,
  display_name         TEXT        NOT NULL,
  phone_e164           TEXT        NULL,
  phone_verified_at    TIMESTAMPTZ NULL,
  email_verified_at    TIMESTAMPTZ NULL,
  password_hash        TEXT        NULL,
  password_changed_at  TIMESTAMPTZ NULL,
  status               TEXT        NOT NULL DEFAULT 'PENDING_VERIFICATION',
  last_login_at        TIMESTAMPTZ NULL,
  failed_login_count   INTEGER     NOT NULL DEFAULT 0,
  last_failed_login_at TIMESTAMPTZ NULL,
  mfa_enabled          BOOLEAN     NOT NULL DEFAULT FALSE,
  mfa_secret_ref       TEXT        NULL,
  deleted_at           TIMESTAMPTZ NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_users              PRIMARY KEY (id),
  CONSTRAINT chk_users_status      CHECK (status IN ('PENDING_VERIFICATION','ACTIVE','SUSPENDED','DELETED')),
  CONSTRAINT chk_users_email_fmt   CHECK (email_normalized ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  CONSTRAINT chk_users_mfa_ref     CHECK (mfa_secret_ref IS NULL OR mfa_secret_ref LIKE 'secret_manager://%')
);
CREATE UNIQUE INDEX uq_users_email_normalized ON identity.users (email_normalized);
CREATE INDEX idx_users_status_active ON identity.users (status) WHERE status = 'ACTIVE';
CREATE INDEX idx_users_created_at    ON identity.users (created_at);
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON identity.users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
GRANT SELECT, INSERT, UPDATE ON identity.users TO app_api, app_worker;
GRANT SELECT ON identity.users TO app_platform_admin;

-- Currency immutability function (shared, placed here before organizations)
CREATE OR REPLACE FUNCTION prevent_currency_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.currency IS DISTINCT FROM OLD.currency THEN
    RAISE EXCEPTION 'organizations.currency is immutable after creation. Current: %, Attempted: %', OLD.currency, NEW.currency;
  END IF;
  RETURN NEW;
END;
$$;

-- identity.sessions
CREATE TABLE identity.sessions (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  user_id            UUID        NOT NULL,
  refresh_token_hash TEXT        NOT NULL,
  access_token_jti   TEXT        NULL,
  status             TEXT        NOT NULL DEFAULT 'ACTIVE',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at         TIMESTAMPTZ NOT NULL,
  revoked_at         TIMESTAMPTZ NULL,
  last_seen_at       TIMESTAMPTZ NULL,
  device_label       TEXT        NULL,
  ip_address         INET        NULL,
  user_agent_hash    TEXT        NULL,

  CONSTRAINT pk_sessions        PRIMARY KEY (id),
  CONSTRAINT chk_sessions_status CHECK (status IN ('ACTIVE','REVOKED','EXPIRED'))
);
CREATE UNIQUE INDEX uq_sessions_token_hash ON identity.sessions (refresh_token_hash);
CREATE INDEX idx_sessions_user_active ON identity.sessions (user_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_sessions_expires_at  ON identity.sessions (expires_at);
GRANT SELECT, INSERT, UPDATE ON identity.sessions TO app_api, app_worker;

-- identity.password_reset_tokens
CREATE TABLE identity.password_reset_tokens (
  id         UUID        NOT NULL DEFAULT gen_uuid_v7(),
  user_id    UUID        NOT NULL,
  token_hash TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ NULL,
  purpose    TEXT        NOT NULL DEFAULT 'PASSWORD_RESET',

  CONSTRAINT pk_password_reset_tokens PRIMARY KEY (id),
  CONSTRAINT chk_prt_purpose CHECK (purpose IN ('PASSWORD_RESET','EMAIL_VERIFICATION','INVITATION'))
);
CREATE UNIQUE INDEX uq_prt_token_hash ON identity.password_reset_tokens (token_hash);
CREATE INDEX idx_prt_user_id    ON identity.password_reset_tokens (user_id);
CREATE INDEX idx_prt_expires_at ON identity.password_reset_tokens (expires_at);
GRANT SELECT, INSERT, UPDATE ON identity.password_reset_tokens TO app_api, app_worker;

-- identity.oauth_identities
CREATE TABLE identity.oauth_identities (
  id                       UUID        NOT NULL DEFAULT gen_uuid_v7(),
  user_id                  UUID        NOT NULL,
  provider                 TEXT        NOT NULL,
  provider_subject         TEXT        NOT NULL,
  email_at_provider        TEXT        NULL,
  display_name_at_provider TEXT        NULL,
  status                   TEXT        NOT NULL DEFAULT 'ACTIVE',
  credential_ref           TEXT        NULL,
  linked_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at            TIMESTAMPTZ NULL,
  unlinked_at              TIMESTAMPTZ NULL,

  CONSTRAINT pk_oauth_identities PRIMARY KEY (id),
  CONSTRAINT chk_oauth_status    CHECK (status IN ('ACTIVE','UNLINKED')),
  CONSTRAINT chk_oauth_cred_ref  CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
);
CREATE UNIQUE INDEX uq_oauth_provider_subject ON identity.oauth_identities (provider, provider_subject);
CREATE INDEX idx_oauth_user_id ON identity.oauth_identities (user_id);
GRANT SELECT, INSERT, UPDATE ON identity.oauth_identities TO app_api, app_worker;

-- identity.api_keys (with inline RLS — see 5K §4.1)
CREATE TABLE identity.api_keys (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  created_by      UUID        NOT NULL,
  name            TEXT        NOT NULL,
  key_prefix      TEXT        NOT NULL,
  key_hash        TEXT        NOT NULL,
  scopes          TEXT[]      NOT NULL DEFAULT '{}',
  status          TEXT        NOT NULL DEFAULT 'ACTIVE',
  expires_at      TIMESTAMPTZ NULL,
  last_used_at    TIMESTAMPTZ NULL,
  last_used_ip    INET        NULL,
  revoked_at      TIMESTAMPTZ NULL,
  revoked_by      UUID        NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_api_keys         PRIMARY KEY (id),
  CONSTRAINT chk_api_keys_status CHECK (status IN ('ACTIVE','REVOKED','EXPIRED')),
  CONSTRAINT chk_api_keys_prefix CHECK (length(key_prefix) = 8)
);
CREATE UNIQUE INDEX uq_api_keys_key_hash ON identity.api_keys (key_hash);
CREATE INDEX idx_api_keys_org_status ON identity.api_keys (organization_id, status);
CREATE TRIGGER trg_api_keys_updated_at BEFORE UPDATE ON identity.api_keys FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE identity.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.api_keys FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_api_keys_tenant ON identity.api_keys
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON identity.api_keys TO app_api, app_worker;
