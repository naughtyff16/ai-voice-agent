-- =================================================================
-- Migration 035 (Phase 5F): knowledge.knowledge_bases
-- down_revision: 034_5F
-- Transaction: yes
-- Source: 5F §14 Migration 035
-- =================================================================

CREATE TABLE knowledge.knowledge_bases (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  name                 TEXT        NOT NULL,
  description          TEXT        NULL,
  embedding_model_ref  TEXT        NOT NULL,
  embedding_dimensions INTEGER     NOT NULL,
  chunking_strategy    JSONB       NOT NULL,
  retrieval_config     JSONB       NOT NULL DEFAULT '{}',
  index_version        INTEGER     NOT NULL DEFAULT 1,
  status               TEXT        NOT NULL DEFAULT 'ACTIVE',
  document_count       INTEGER     NOT NULL DEFAULT 0,
  created_by           UUID        NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_knowledge_bases    PRIMARY KEY (id),
  CONSTRAINT chk_kb_status         CHECK (status IN ('ACTIVE','REINDEXING','DEGRADED','ARCHIVED')),
  CONSTRAINT chk_kb_dimensions_pos CHECK (embedding_dimensions > 0),
  CONSTRAINT chk_kb_doc_count_nn   CHECK (document_count >= 0),
  CONSTRAINT chk_kb_index_version  CHECK (index_version >= 1),
  CONSTRAINT chk_kb_name_len       CHECK (length(name) BETWEEN 1 AND 200)
);
CREATE UNIQUE INDEX uq_kb_name    ON knowledge.knowledge_bases (organization_id, name);
CREATE        INDEX idx_kb_org_st ON knowledge.knowledge_bases (organization_id, status);
CREATE        INDEX idx_kb_org_cr ON knowledge.knowledge_bases (organization_id, created_at DESC);
CREATE TRIGGER trg_kb_updated_at BEFORE UPDATE ON knowledge.knowledge_bases FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_kb_model_immutable BEFORE UPDATE ON knowledge.knowledge_bases FOR EACH ROW EXECUTE FUNCTION knowledge.prevent_kb_model_mutation();
ALTER TABLE knowledge.knowledge_bases ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.knowledge_bases FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_kb_tenant ON knowledge.knowledge_bases FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON knowledge.knowledge_bases TO app_api, app_worker;
