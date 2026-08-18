-- =================================================================
-- Migration 034 (Phase 5F): pgvector extension, knowledge schema functions
-- down_revision: 033_5E
-- Transaction: yes
-- Source: 5F §13 (functions), §14 Migration 034
-- Note: SECURITY DEFINER functions have SET search_path hardening
-- =================================================================

CREATE EXTENSION IF NOT EXISTS vector;
GRANT USAGE ON SCHEMA knowledge TO app_api, app_worker, app_readonly, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.prevent_kb_model_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.embedding_model_ref IS DISTINCT FROM NEW.embedding_model_ref OR
     OLD.embedding_dimensions IS DISTINCT FROM NEW.embedding_dimensions THEN
    RAISE EXCEPTION 'knowledge_bases.embedding_model_ref/dimensions are immutable. kb_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION knowledge.prevent_docver_immutable_field_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.document_id IS DISTINCT FROM NEW.document_id OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.mime_type IS DISTINCT FROM NEW.mime_type OR
     OLD.size_bytes IS DISTINCT FROM NEW.size_bytes OR
     OLD.created_at IS DISTINCT FROM NEW.created_at OR
     OLD.created_by IS DISTINCT FROM NEW.created_by THEN
    RAISE EXCEPTION 'document_versions identity/content fields are immutable. version_id: %', OLD.id;
  END IF;
  IF (OLD.storage_ref IS DISTINCT FROM NEW.storage_ref AND NEW.storage_ref != 'ERASED') OR
     (OLD.content_hash IS DISTINCT FROM NEW.content_hash AND NEW.content_hash != 'ERASED') THEN
    RAISE EXCEPTION 'document_versions.storage_ref/content_hash are immutable except for GDPR erasure. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION knowledge.prevent_completed_job_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'READY' THEN
    RAISE EXCEPTION 'READY ingestion_jobs are immutable. job_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION knowledge.update_chunk_tsvector()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.tsvector_content := to_tsvector('english', COALESCE(NEW.content, ''));
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION knowledge.fn_docver_mark_ready(
  p_document_version_id UUID,
  p_organization_id     UUID,
  p_chunk_count         INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, organization, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM knowledge.document_versions
    WHERE id = p_document_version_id AND organization_id = p_organization_id AND status = 'PENDING'
  ) THEN
    RAISE EXCEPTION 'fn_docver_mark_ready: version not found, not owned by tenant, or not PENDING. version_id: %', p_document_version_id;
  END IF;
  UPDATE knowledge.document_versions
  SET status = 'READY', ingestion_completed_at = NOW(), chunk_count = p_chunk_count
  WHERE id = p_document_version_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_docver_mark_ready(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_mark_ready(UUID, UUID, INTEGER) TO app_api, app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.fn_docver_publish(
  p_document_id     UUID,
  p_new_version_id  UUID,
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, organization, pg_temp
AS $$
DECLARE v_old_version_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM knowledge.document_versions
    WHERE id = p_new_version_id AND document_id = p_document_id
      AND organization_id = p_organization_id AND status = 'READY'
  ) THEN
    RAISE EXCEPTION 'fn_docver_publish: version does not belong to document, tenant, or is not READY. document_id: %, version_id: %', p_document_id, p_new_version_id;
  END IF;
  SELECT current_version_id INTO v_old_version_id FROM knowledge.documents
  WHERE id = p_document_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_docver_publish: document not found or not owned by tenant. document_id: %', p_document_id;
  END IF;
  IF v_old_version_id IS NOT NULL THEN
    UPDATE knowledge.document_versions SET status = 'SUPERSEDED'
    WHERE id = v_old_version_id AND organization_id = p_organization_id;
  END IF;
  UPDATE knowledge.documents SET current_version_id = p_new_version_id, status = 'READY', updated_at = NOW()
  WHERE id = p_document_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_docver_publish(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_publish(UUID, UUID, UUID) TO app_api, app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.create_kb_partition(p_kb_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_temp
AS $$
DECLARE v_partition_name TEXT;
BEGIN
  v_partition_name := 'document_chunks_' || substring(replace(p_kb_id::text, '-', ''), 1, 8);
  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS knowledge.%I PARTITION OF knowledge.document_chunks FOR VALUES IN (%L)',
    v_partition_name, p_kb_id
  );
END;
$$;
REVOKE ALL ON FUNCTION knowledge.create_kb_partition(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.create_kb_partition(UUID) TO app_api, app_worker, app_platform_admin;
