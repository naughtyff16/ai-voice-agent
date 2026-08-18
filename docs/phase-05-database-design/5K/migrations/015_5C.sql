-- =================================================================
-- Migration 015 (Phase 5C): provider_configs, language_evaluation_records,
--                           tenant_phone_numbers, resolve_inbound_phone_number()
-- down_revision: 014_5C
-- Transaction: yes
-- Source: 5C §16.7
-- Note: resolve_inbound_phone_number() moved HERE from 009 (5K §10.3)
--       because it selects from voice.tenant_phone_numbers.
-- =================================================================

CREATE TABLE voice.provider_configs (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NULL,
  category             TEXT        NOT NULL,
  provider_id          TEXT        NOT NULL,
  model_id             TEXT        NULL,
  is_active            BOOLEAN     NOT NULL DEFAULT TRUE,
  priority             INTEGER     NOT NULL,
  health_state         TEXT        NOT NULL DEFAULT 'AVAILABLE',
  last_health_check_at TIMESTAMPTZ NULL,
  p50_latency_ms       INTEGER     NULL,
  error_rate_pct       NUMERIC(5,2) NOT NULL DEFAULT 0.00,
  circuit_state        TEXT        NOT NULL DEFAULT 'CLOSED',
  circuit_opened_at    TIMESTAMPTZ NULL,
  credential_ref       TEXT        NULL,
  config_json          JSONB       NOT NULL DEFAULT '{}',
  supports_languages   TEXT[]      NOT NULL DEFAULT '{}',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_provider_configs PRIMARY KEY (id),
  CONSTRAINT chk_pc_category     CHECK (category IN ('TELEPHONY','STT','TTS','LLM','EMBEDDING')),
  CONSTRAINT chk_pc_circuit      CHECK (circuit_state IN ('CLOSED','OPEN','HALF_OPEN')),
  CONSTRAINT chk_pc_health       CHECK (health_state IN ('AVAILABLE','DEGRADED','UNAVAILABLE')),
  CONSTRAINT chk_pc_error_rate   CHECK (error_rate_pct BETWEEN 0 AND 100),
  CONSTRAINT chk_pc_priority     CHECK (priority >= 1),
  CONSTRAINT chk_pc_cred_ref     CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
);
CREATE UNIQUE INDEX uq_pc_priority     ON voice.provider_configs (organization_id, category, priority) WHERE is_active = TRUE;
CREATE UNIQUE INDEX uq_pc_platform_cat ON voice.provider_configs (provider_id, category) WHERE organization_id IS NULL AND is_active = TRUE;
CREATE        INDEX idx_pc_org_cat     ON voice.provider_configs (organization_id, category, priority) WHERE is_active = TRUE AND circuit_state = 'CLOSED';
CREATE        INDEX idx_pc_platform    ON voice.provider_configs (category, priority) WHERE organization_id IS NULL AND is_active = TRUE;
CREATE TRIGGER trg_pc_updated_at BEFORE UPDATE ON voice.provider_configs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.provider_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.provider_configs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pc_read   ON voice.provider_configs FOR SELECT USING (organization_id = organization.current_tenant_id() OR organization_id IS NULL);
CREATE POLICY rls_pc_insert ON voice.provider_configs FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());
CREATE POLICY rls_pc_modify ON voice.provider_configs FOR UPDATE USING (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.provider_configs TO app_api, app_worker;

CREATE TABLE voice.language_evaluation_records (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  language           TEXT        NOT NULL,
  provider_id        TEXT        NOT NULL,
  provider_model_ref TEXT        NOT NULL,
  capability         TEXT        NOT NULL,
  evaluation_set_ref TEXT        NOT NULL,
  scores             JSONB       NOT NULL,
  evaluated_at       TIMESTAMPTZ NOT NULL,
  verdict            TEXT        NOT NULL,
  notes              TEXT        NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ler          PRIMARY KEY (id),
  CONSTRAINT chk_ler_cap     CHECK (capability IN ('STT','TTS','LLM')),
  CONSTRAINT chk_ler_verdict CHECK (verdict IN ('APPROVED','CONDITIONAL','REJECTED'))
);
CREATE UNIQUE INDEX uq_ler_eval   ON voice.language_evaluation_records (language, provider_id, provider_model_ref, capability, evaluation_set_ref);
CREATE        INDEX idx_ler_lookup ON voice.language_evaluation_records (language, provider_id, capability, evaluated_at DESC);
CREATE        INDEX idx_ler_verdict ON voice.language_evaluation_records (language, capability, verdict);
GRANT SELECT ON voice.language_evaluation_records TO app_api, app_worker, app_readonly;

CREATE TABLE voice.tenant_phone_numbers (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id    UUID        NOT NULL,
  phone_e164         TEXT        NOT NULL,
  phone_country      TEXT        NOT NULL,
  provider_id        TEXT        NOT NULL,
  provider_number_id TEXT        NULL,
  status             TEXT        NOT NULL DEFAULT 'ACTIVE',
  inbound_enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
  outbound_enabled   BOOLEAN     NOT NULL DEFAULT TRUE,
  assigned_agent_id  UUID        NULL,
  capabilities       TEXT[]      NOT NULL DEFAULT '{}',
  number_type        TEXT        NULL,
  verified_at        TIMESTAMPTZ NULL,
  credential_ref     TEXT        NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_phone_numbers   PRIMARY KEY (id),
  CONSTRAINT chk_pn_status      CHECK (status IN ('ACTIVE','SUSPENDED','RELEASED')),
  CONSTRAINT chk_pn_e164_format CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_pn_cred_ref    CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
);
COMMENT ON COLUMN voice.tenant_phone_numbers.phone_e164 IS 'pii:phone — E.164 canonical number';
CREATE UNIQUE INDEX uq_pn_e164        ON voice.tenant_phone_numbers (phone_e164);
CREATE        INDEX idx_pn_org_status ON voice.tenant_phone_numbers (organization_id, status) WHERE status = 'ACTIVE';
CREATE        INDEX idx_pn_agent      ON voice.tenant_phone_numbers (organization_id, assigned_agent_id) WHERE assigned_agent_id IS NOT NULL;
CREATE TRIGGER trg_pn_updated_at BEFORE UPDATE ON voice.tenant_phone_numbers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.tenant_phone_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.tenant_phone_numbers FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pn_tenant ON voice.tenant_phone_numbers FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.tenant_phone_numbers TO app_api, app_worker;

-- resolve_inbound_phone_number() — placed here (after tenant_phone_numbers exists)
CREATE OR REPLACE FUNCTION voice.resolve_inbound_phone_number(p_phone_e164 TEXT)
RETURNS TABLE (organization_id UUID, tenant_phone_number_id UUID, assigned_agent_id UUID)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = voice, organization, pg_temp
AS $$
  SELECT pn.organization_id, pn.id, pn.assigned_agent_id
  FROM voice.tenant_phone_numbers pn
  WHERE pn.phone_e164 = p_phone_e164
    AND pn.status = 'ACTIVE'
    AND pn.inbound_enabled = TRUE
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION voice.resolve_inbound_phone_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.resolve_inbound_phone_number(TEXT) TO app_api, app_worker, app_platform_admin;
