-- =================================================================
-- Migration 042 (Phase 5G): prompt templates, versions, experiments
-- down_revision: 041_5G
-- Transaction: yes
-- Source: 5G §16.3
-- =================================================================

CREATE TABLE prompt.prompt_templates (
  id                    UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID        NOT NULL,
  name                  TEXT        NOT NULL,
  description           TEXT        NULL,
  status                TEXT        NOT NULL DEFAULT 'DRAFT',
  draft_content         TEXT        NULL,
  draft_variable_schema JSONB       NOT NULL DEFAULT '[]',
  active_versions       JSONB       NOT NULL DEFAULT '{}',
  created_by            UUID        NOT NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_prompt_templates PRIMARY KEY (id),
  CONSTRAINT chk_pt_status       CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
  CONSTRAINT chk_pt_name_len     CHECK (length(name) BETWEEN 1 AND 200),
  CONSTRAINT chk_pt_draft_len    CHECK (draft_content IS NULL OR length(draft_content) <= 50000)
);
CREATE UNIQUE INDEX uq_pt_name        ON prompt.prompt_templates (organization_id, name);
CREATE        INDEX idx_pt_org_status ON prompt.prompt_templates (organization_id, status);
CREATE TRIGGER trg_pt_updated_at BEFORE UPDATE ON prompt.prompt_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE prompt.prompt_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt.prompt_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pt_tenant ON prompt.prompt_templates FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON prompt.prompt_templates TO app_api, app_worker;

CREATE TABLE prompt.prompt_versions (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id    UUID        NOT NULL,
  prompt_template_id UUID        NOT NULL,
  version_number     INTEGER     NOT NULL,
  content            TEXT        NOT NULL,
  variable_schema    JSONB       NOT NULL,
  published_by       UUID        NOT NULL,
  published_at       TIMESTAMPTZ NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_prompt_versions    PRIMARY KEY (id),
  CONSTRAINT fk_pv_template        FOREIGN KEY (prompt_template_id) REFERENCES prompt.prompt_templates(id) ON DELETE CASCADE,
  CONSTRAINT uq_pv_version_number  UNIQUE (prompt_template_id, version_number),
  CONSTRAINT chk_pv_version_number CHECK (version_number >= 1),
  CONSTRAINT chk_pv_content_len    CHECK (length(content) <= 50000)
);
CREATE INDEX idx_pv_template ON prompt.prompt_versions (prompt_template_id);
CREATE INDEX idx_pv_org      ON prompt.prompt_versions (organization_id);
CREATE TRIGGER trg_pv_immutable BEFORE UPDATE ON prompt.prompt_versions FOR EACH ROW EXECUTE FUNCTION prompt.prevent_pv_mutation();
ALTER TABLE prompt.prompt_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt.prompt_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pv_tenant ON prompt.prompt_versions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON prompt.prompt_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON prompt.prompt_versions FROM app_api, app_worker;

CREATE TABLE prompt.prompt_experiments (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id    UUID        NOT NULL,
  prompt_template_id UUID        NOT NULL,
  name               TEXT        NOT NULL,
  status             TEXT        NOT NULL DEFAULT 'DRAFT',
  variants           JSONB       NOT NULL,
  assignment_basis   TEXT        NOT NULL DEFAULT 'SESSION_ID',
  started_at         TIMESTAMPTZ NULL,
  completed_at       TIMESTAMPTZ NULL,
  created_by         UUID        NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_prompt_experiments    PRIMARY KEY (id),
  CONSTRAINT chk_pe_status            CHECK (status IN ('DRAFT','ACTIVE','COMPLETED','CANCELLED')),
  CONSTRAINT chk_pe_assignment_basis  CHECK (assignment_basis IN ('SESSION_ID','USER_ID'))
);
CREATE INDEX idx_pe_org_active ON prompt.prompt_experiments (organization_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_pe_template   ON prompt.prompt_experiments (organization_id, prompt_template_id);
CREATE TRIGGER trg_pe_updated_at BEFORE UPDATE ON prompt.prompt_experiments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE prompt.prompt_experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt.prompt_experiments FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pe_tenant ON prompt.prompt_experiments FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON prompt.prompt_experiments TO app_api, app_worker;
