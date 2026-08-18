-- =================================================================
-- Migration 021 (Phase 5D): crm.pipelines and crm.deals
-- down_revision: 020_5D
-- Transaction: yes
-- Source: 5D §14.3
-- =================================================================

CREATE TABLE crm.pipelines (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  name            TEXT        NOT NULL,
  is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
  stages          JSONB       NOT NULL DEFAULT '[]',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_pipelines      PRIMARY KEY (id),
  CONSTRAINT chk_pipe_name_len CHECK (length(name) BETWEEN 1 AND 100)
);
CREATE UNIQUE INDEX uq_pipelines_name    ON crm.pipelines (organization_id, name);
CREATE UNIQUE INDEX uq_pipelines_default ON crm.pipelines (organization_id) WHERE is_default = TRUE;
CREATE        INDEX idx_pipelines_org    ON crm.pipelines (organization_id);
CREATE TRIGGER trg_pipelines_updated_at BEFORE UPDATE ON crm.pipelines FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.pipelines FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pipelines_tenant ON crm.pipelines FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.pipelines TO app_api, app_worker;

CREATE TABLE crm.deals (
  id                  UUID           NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID           NOT NULL,
  title               TEXT           NOT NULL,
  contact_id          UUID           NOT NULL,
  company_id          UUID           NULL,
  pipeline_id         UUID           NOT NULL,
  current_stage_id    UUID           NOT NULL,
  value_amount        NUMERIC(18,4)  NULL,
  value_currency      CHAR(3)        NULL,
  status              TEXT           NOT NULL DEFAULT 'OPEN',
  close_date          DATE           NULL,
  owned_by            UUID           NULL,
  won_at              TIMESTAMPTZ    NULL,
  lost_at             TIMESTAMPTZ    NULL,
  lost_reason         TEXT           NULL,
  custom_field_values JSONB          NOT NULL DEFAULT '[]',
  created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_deals                  PRIMARY KEY (id),
  CONSTRAINT fk_deals_pipeline         FOREIGN KEY (pipeline_id) REFERENCES crm.pipelines(id) ON DELETE RESTRICT,
  CONSTRAINT chk_deals_status          CHECK (status IN ('OPEN','WON','LOST','ABANDONED')),
  CONSTRAINT chk_deals_value_nn        CHECK (value_amount IS NULL OR value_amount >= 0),
  CONSTRAINT chk_deals_currency_format CHECK (value_currency IS NULL OR value_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_deals_money_pair      CHECK ((value_amount IS NULL) = (value_currency IS NULL)),
  CONSTRAINT chk_deals_title_len       CHECK (length(title) BETWEEN 1 AND 200)
);
CREATE INDEX idx_deals_contact  ON crm.deals (organization_id, contact_id, status);
CREATE INDEX idx_deals_pipeline ON crm.deals (organization_id, pipeline_id, current_stage_id) WHERE status = 'OPEN';
CREATE INDEX idx_deals_status   ON crm.deals (organization_id, status);
CREATE INDEX idx_deals_owner    ON crm.deals (organization_id, owned_by) WHERE owned_by IS NOT NULL;
CREATE INDEX idx_deals_close    ON crm.deals (organization_id, close_date) WHERE status = 'OPEN' AND close_date IS NOT NULL;
CREATE TRIGGER trg_deals_updated_at BEFORE UPDATE ON crm.deals FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.deals FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_deals_tenant ON crm.deals FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.deals TO app_api, app_worker;
