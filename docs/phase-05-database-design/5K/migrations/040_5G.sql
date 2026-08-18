-- =================================================================
-- Migration 040 (Phase 5G): workflow.workflow_definitions and workflow_versions
-- down_revision: 039_5G
-- Transaction: yes
-- Source: 5G §16.2
-- =================================================================

CREATE TABLE workflow.workflow_definitions (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  name                 TEXT        NOT NULL,
  description          TEXT        NULL,
  status               TEXT        NOT NULL DEFAULT 'DRAFT',
  published_version_id UUID        NULL,
  draft_graph          JSONB       NOT NULL DEFAULT '{}',
  created_by           UUID        NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_workflow_definitions PRIMARY KEY (id),
  CONSTRAINT chk_wfd_status          CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
  CONSTRAINT chk_wfd_name_len        CHECK (length(name) BETWEEN 1 AND 200),
  CONSTRAINT chk_wfd_desc_len        CHECK (description IS NULL OR length(description) <= 500)
);
CREATE UNIQUE INDEX uq_wfd_name        ON workflow.workflow_definitions (organization_id, name);
CREATE        INDEX idx_wfd_org_status ON workflow.workflow_definitions (organization_id, status);
CREATE        INDEX idx_wfd_pub_ver    ON workflow.workflow_definitions (published_version_id) WHERE published_version_id IS NOT NULL;
CREATE TRIGGER trg_wfd_updated_at BEFORE UPDATE ON workflow.workflow_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE workflow.workflow_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.workflow_definitions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wfd_tenant ON workflow.workflow_definitions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON workflow.workflow_definitions TO app_api, app_worker;

CREATE TABLE workflow.workflow_versions (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NOT NULL,
  workflow_definition_id UUID        NOT NULL,
  version_number         INTEGER     NOT NULL,
  graph_json             JSONB       NOT NULL,
  published_by           UUID        NOT NULL,
  published_at           TIMESTAMPTZ NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_workflow_versions  PRIMARY KEY (id),
  CONSTRAINT fk_wv_definition      FOREIGN KEY (workflow_definition_id) REFERENCES workflow.workflow_definitions(id) ON DELETE CASCADE,
  CONSTRAINT uq_wv_version_number  UNIQUE (workflow_definition_id, version_number),
  CONSTRAINT chk_wv_version_number CHECK (version_number >= 1)
);
CREATE INDEX idx_wv_org ON workflow.workflow_versions (organization_id);
CREATE TRIGGER trg_wv_immutable BEFORE UPDATE ON workflow.workflow_versions FOR EACH ROW EXECUTE FUNCTION workflow.prevent_wf_version_mutation();
ALTER TABLE workflow.workflow_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.workflow_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wv_tenant ON workflow.workflow_versions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON workflow.workflow_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON workflow.workflow_versions FROM app_api, app_worker;
