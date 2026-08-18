-- =================================================================
-- Migration 038 (Phase 5F): knowledge.document_chunks (LIST partitioned)
-- down_revision: 037_5F
-- Transaction: yes
-- Source: 5F §14 Migration 038
-- =================================================================

CREATE TABLE knowledge.document_chunks (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  knowledge_base_id   UUID          NOT NULL,
  organization_id     UUID          NOT NULL,
  document_id         UUID          NOT NULL,
  document_version_id UUID          NOT NULL,
  chunk_index         INTEGER       NOT NULL,
  content             TEXT          NOT NULL,
  content_hash        CHAR(64)      NOT NULL,
  embedding           vector(1536)  NOT NULL,
  tsvector_content    TSVECTOR      NOT NULL,
  token_count         INTEGER       NOT NULL,
  page_number         INTEGER       NULL,
  section_heading     TEXT          NULL,
  source_location     TEXT          NULL,
  embedding_model_ref TEXT          NOT NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_document_chunks     PRIMARY KEY (id, knowledge_base_id),
  CONSTRAINT uq_chunk_position      UNIQUE (document_version_id, chunk_index, knowledge_base_id),
  CONSTRAINT chk_dc_chunk_index_nn  CHECK (chunk_index >= 0),
  CONSTRAINT chk_dc_token_count_pos CHECK (token_count > 0),
  CONSTRAINT chk_dc_model_ref_len   CHECK (length(embedding_model_ref) > 0)
) PARTITION BY LIST (knowledge_base_id);

COMMENT ON COLUMN knowledge.document_chunks.content   IS 'pii:potential — document text fragment';
COMMENT ON COLUMN knowledge.document_chunks.embedding IS 'pii:potential (derived) — 1536-dim cosine vector';
CREATE INDEX idx_dc_org_kb  ON knowledge.document_chunks (organization_id, knowledge_base_id);
CREATE INDEX idx_dc_docver  ON knowledge.document_chunks (document_version_id, chunk_index ASC);
CREATE INDEX idx_dc_tsvector ON knowledge.document_chunks USING GIN (tsvector_content);
CREATE TRIGGER trg_dc_tsvector BEFORE INSERT ON knowledge.document_chunks FOR EACH ROW EXECUTE FUNCTION knowledge.update_chunk_tsvector();
ALTER TABLE knowledge.document_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.document_chunks FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_dc_tenant ON knowledge.document_chunks FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, DELETE ON knowledge.document_chunks TO app_api, app_worker;
REVOKE UPDATE ON knowledge.document_chunks FROM app_api, app_worker;
CREATE TABLE knowledge.document_chunks_default PARTITION OF knowledge.document_chunks DEFAULT;
