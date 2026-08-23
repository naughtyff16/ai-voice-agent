-- =================================================================
-- Migration 079 (Phase 5F.2): knowledge.fn_docver_rollback()
-- down_revision: 078_5F1
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6F-01 (FR-RAG-004)
--
-- FR-RAG-004 ("System shall version knowledge bases and allow rollback")
-- is resolved as document-level historical rollback (Interpretation A),
-- grounded in 4E DDD evidence: Knowledge/RAG has no KnowledgeBaseVersion
-- aggregate (IndexVersion is a plain reindex counter, not a snapshot
-- entity) — the only concrete "version" concept in this bounded context
-- is per-Document (document_versions, SUPERSEDED state). 4E's Prompt
-- Management context already implements the equivalent pattern
-- ("rollback(environment, target_version) does not delete the current
-- version — it updates the active pointer to an earlier version").
-- This function mirrors that pattern for Documents instead of inventing
-- a new KB-snapshot entity with no DDD basis.
--
-- Rollback re-activates a SUPERSEDED version (one that was previously
-- READY/published, then superseded by a later publish). It is not a
-- content mutation — document_versions rows are never edited, only their
-- status and the document's current_version_id pointer move. Full
-- version history is retained (nothing is deleted). Same DELETED-document
-- guard as fn_docver_publish() (078).
-- =================================================================

CREATE OR REPLACE FUNCTION knowledge.fn_docver_rollback(
  p_document_id       UUID,
  p_target_version_id UUID,
  p_organization_id   UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, organization, pg_temp
AS $$
DECLARE
  v_old_version_id UUID;
  v_doc_status     TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM knowledge.document_versions
    WHERE id = p_target_version_id AND document_id = p_document_id
      AND organization_id = p_organization_id AND status = 'SUPERSEDED'
  ) THEN
    RAISE EXCEPTION 'fn_docver_rollback: target version does not belong to document/tenant or is not SUPERSEDED (only a previously-published version may be rolled back to). document_id: %, version_id: %', p_document_id, p_target_version_id;
  END IF;

  SELECT current_version_id, status INTO v_old_version_id, v_doc_status
  FROM knowledge.documents
  WHERE id = p_document_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_docver_rollback: document not found or not owned by tenant. document_id: %', p_document_id;
  END IF;

  IF v_doc_status = 'DELETED' THEN
    RAISE EXCEPTION 'fn_docver_rollback: document % is DELETED and cannot be rolled back.', p_document_id;
  END IF;

  IF v_old_version_id = p_target_version_id THEN
    RAISE EXCEPTION 'fn_docver_rollback: version % is already the current version of document %.', p_target_version_id, p_document_id;
  END IF;

  IF v_old_version_id IS NOT NULL THEN
    UPDATE knowledge.document_versions SET status = 'SUPERSEDED'
    WHERE id = v_old_version_id AND organization_id = p_organization_id;
  END IF;

  UPDATE knowledge.document_versions SET status = 'READY'
  WHERE id = p_target_version_id AND organization_id = p_organization_id;

  UPDATE knowledge.documents SET current_version_id = p_target_version_id, status = 'READY', updated_at = NOW()
  WHERE id = p_document_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_docver_rollback(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_rollback(UUID, UUID, UUID) TO app_api, app_worker, app_platform_admin;
