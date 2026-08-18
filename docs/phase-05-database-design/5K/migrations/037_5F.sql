-- =================================================================
-- Migration 037 (Phase 5F): knowledge.ingestion_jobs
-- down_revision: 036_5F
-- Transaction: yes
-- Source: 5F §14 Migration 037
-- =================================================================

CREATE TABLE knowledge.ingestion_jobs (
  id                  UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID        NOT NULL,
  document_version_id UUID        NOT NULL,
  knowledge_base_id   UUID        NOT NULL,
  status              TEXT        NOT NULL DEFAULT 'PENDING',
  current_stage       TEXT        NULL,
  attempt_count       INTEGER     NOT NULL DEFAULT 1,
  parsed_text_ref     TEXT        NULL,
  chunks_produced     INTEGER     NULL,
  embeddings_produced INTEGER     NULL,
  error_message       TEXT        NULL,
  started_at          TIMESTAMPTZ NULL,
  completed_at        TIMESTAMPTZ NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ingestion_jobs PRIMARY KEY (id),
  CONSTRAINT fk_ij_docver      FOREIGN KEY (document_version_id) REFERENCES knowledge.document_versions(id) ON DELETE CASCADE,
  CONSTRAINT chk_ij_status     CHECK (status IN ('PENDING','EXTRACTING','CHUNKING','EMBEDDING','INDEXING','READY','FAILED','CANCELLED')),
  CONSTRAINT chk_ij_attempts   CHECK (attempt_count BETWEEN 1 AND 3),
  CONSTRAINT chk_ij_chunks_nn  CHECK (chunks_produced IS NULL OR chunks_produced >= 0),
  CONSTRAINT chk_ij_emb_nn     CHECK (embeddings_produced IS NULL OR embeddings_produced >= 0)
);
CREATE INDEX idx_ij_docver     ON knowledge.ingestion_jobs (document_version_id);
CREATE INDEX idx_ij_org_status ON knowledge.ingestion_jobs (organization_id, status);
CREATE TRIGGER trg_ij_updated_at      BEFORE UPDATE ON knowledge.ingestion_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ij_ready_immutable BEFORE UPDATE ON knowledge.ingestion_jobs FOR EACH ROW EXECUTE FUNCTION knowledge.prevent_completed_job_mutation();
ALTER TABLE knowledge.ingestion_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.ingestion_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ij_tenant ON knowledge.ingestion_jobs FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON knowledge.ingestion_jobs TO app_api, app_worker;
