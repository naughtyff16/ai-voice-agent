-- =================================================================
-- Migration 036 (Phase 5F): knowledge.documents and document_versions
-- down_revision: 035_5F
-- Transaction: yes
-- Source: 5F §14 Migration 036
-- Correction: dedup index changed from (knowledge_base_id, content_hash) to
--   (document_id, content_hash) — knowledge.document_versions has no
--   knowledge_base_id column (5K §10.4). document_id uniquely identifies the
--   document within a KB, so dedup per document still enforces no two active
--   versions of the same document with identical content.
-- =================================================================

CREATE TABLE knowledge.documents (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  knowledge_base_id UUID        NOT NULL,
  source_type       TEXT        NOT NULL,
  original_filename TEXT        NULL,
  title             TEXT        NULL,
  status            TEXT        NOT NULL DEFAULT 'PENDING',
  current_version_id UUID       NULL,
  metadata          JSONB       NOT NULL DEFAULT '{}',
  deleted_at        TIMESTAMPTZ NULL,
  created_by        UUID        NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_documents        PRIMARY KEY (id),
  CONSTRAINT fk_doc_kb           FOREIGN KEY (knowledge_base_id) REFERENCES knowledge.knowledge_bases(id) ON DELETE RESTRICT,
  CONSTRAINT chk_doc_source_type CHECK (source_type IN ('PDF','DOCX','TXT','CSV','URL','FAQ','WEBSITE')),
  CONSTRAINT chk_doc_status      CHECK (status IN ('PENDING','PROCESSING','READY','FAILED','ARCHIVED','DELETED'))
);
COMMENT ON COLUMN knowledge.documents.current_version_id IS 'Set by fn_docver_publish() only. May only reference a READY version of this document (INV-12).';
COMMENT ON COLUMN knowledge.documents.original_filename IS 'pii:potential';
CREATE INDEX idx_doc_kb_status   ON knowledge.documents (organization_id, knowledge_base_id, status);
CREATE INDEX idx_doc_cur_version ON knowledge.documents (current_version_id) WHERE current_version_id IS NOT NULL;
CREATE TRIGGER trg_doc_updated_at BEFORE UPDATE ON knowledge.documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE knowledge.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.documents FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_doc_tenant ON knowledge.documents FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON knowledge.documents TO app_api, app_worker;

CREATE TABLE knowledge.document_versions (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NOT NULL,
  document_id            UUID        NOT NULL,
  version_number         INTEGER     NOT NULL,
  storage_ref            TEXT        NOT NULL,
  content_hash           CHAR(64)    NOT NULL,
  mime_type              TEXT        NOT NULL,
  size_bytes             BIGINT      NOT NULL,
  status                 TEXT        NOT NULL DEFAULT 'PENDING',
  ingestion_completed_at TIMESTAMPTZ NULL,
  chunk_count            INTEGER     NULL,
  created_by             UUID        NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_document_versions  PRIMARY KEY (id),
  CONSTRAINT fk_dv_document        FOREIGN KEY (document_id) REFERENCES knowledge.documents(id) ON DELETE CASCADE,
  CONSTRAINT uq_dv_version_number  UNIQUE (document_id, version_number),
  CONSTRAINT chk_dv_status         CHECK (status IN ('PENDING','READY','SUPERSEDED','FAILED','GDPR_ERASED')),
  CONSTRAINT chk_dv_version_number CHECK (version_number >= 1),
  CONSTRAINT chk_dv_size_bytes     CHECK (size_bytes > 0),
  CONSTRAINT chk_dv_chunk_count    CHECK (chunk_count IS NULL OR chunk_count >= 0)
);

-- Dedup index: no two active versions of the same document may have identical content hash
-- (Corrected: document_id used instead of knowledge_base_id — 5K §10.4)
CREATE UNIQUE INDEX uq_dv_content_hash ON knowledge.document_versions (document_id, content_hash)
  WHERE status NOT IN ('FAILED','GDPR_ERASED');
CREATE INDEX idx_dv_document_status ON knowledge.document_versions (document_id, status);
CREATE INDEX idx_dv_org             ON knowledge.document_versions (organization_id);

COMMENT ON COLUMN knowledge.document_versions.storage_ref  IS 'pii:potential — S3 path; set to ERASED on GDPR erasure';
COMMENT ON COLUMN knowledge.document_versions.content_hash IS 'Set to ERASED on GDPR erasure';

CREATE TRIGGER trg_dv_immutable_fields BEFORE UPDATE ON knowledge.document_versions FOR EACH ROW EXECUTE FUNCTION knowledge.prevent_docver_immutable_field_mutation();
ALTER TABLE knowledge.document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.document_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_dv_tenant ON knowledge.document_versions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON knowledge.document_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON knowledge.document_versions FROM app_api, app_worker;
