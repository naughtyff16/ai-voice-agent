-- Migration 060 (Phase 5I): integration_definitions
-- down_revision: 059_5I
CREATE TABLE integrations.integration_definitions (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  slug              TEXT        NOT NULL,
  name              TEXT        NOT NULL,
  description       TEXT        NULL,
  auth_type         TEXT        NOT NULL,
  capabilities      TEXT[]      NOT NULL DEFAULT '{}',
  required_scopes   TEXT[]      NOT NULL DEFAULT '{}',
  manifest_version  TEXT        NOT NULL DEFAULT '1.0.0',
  documentation_url TEXT        NULL,
  is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_integration_definitions PRIMARY KEY (id),
  CONSTRAINT uq_id_slug                 UNIQUE (slug),
  CONSTRAINT chk_id_slug_format         CHECK (slug ~ '^[a-z][a-z0-9_]{0,98}[a-z0-9]$'),
  CONSTRAINT chk_id_auth_type           CHECK (auth_type IN ('OAUTH2','API_KEY','BASIC','CUSTOM')),
  CONSTRAINT chk_id_name                CHECK (length(name) BETWEEN 1 AND 100)
);
CREATE OR REPLACE FUNCTION integrations.fn_id_slug_immutable()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  IF NEW.slug <> OLD.slug THEN RAISE EXCEPTION 'integration_definitions.slug is immutable'; END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_id_slug_immutable() FROM PUBLIC;
CREATE TRIGGER trg_id_slug_immutable BEFORE UPDATE ON integrations.integration_definitions FOR EACH ROW EXECUTE FUNCTION integrations.fn_id_slug_immutable();
CREATE TRIGGER trg_id_updated_at     BEFORE UPDATE ON integrations.integration_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_id_active ON integrations.integration_definitions (is_active);
GRANT SELECT ON integrations.integration_definitions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON integrations.integration_definitions TO app_platform_admin;
