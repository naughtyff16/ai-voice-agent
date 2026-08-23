-- =================================================================
-- Migration 081 (Phase 5F.4): GDPR DocumentVersion erasure
--   knowledge.fn_docver_gdpr_erase() + knowledge.fn_document_gdpr_delete()
-- down_revision: 080_5F3
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6F-15
--
-- No fn_docver_gdpr_erase()-equivalent exists anywhere in 034_5F.sql-
-- 044_5F.sql; document_versions UPDATE/DELETE is unconditionally revoked
-- from app_api/app_worker (036_5F.sql). This blocks
-- DELETE .../documents/{document_id} (6F §23.4) entirely.
--
-- The existing prevent_docver_immutable_field_mutation() trigger
-- (034_5F.sql) already carves out storage_ref/content_hash -> 'ERASED'
-- as a legal mutation; it has simply been unreachable because no role
-- has ever had UPDATE on document_versions. These SECURITY DEFINER
-- functions are that reachable path.
--
-- fn_docver_gdpr_erase(): erases ONE version's content — deletes its
-- document_chunks rows (so nothing from it remains retrievable via
-- search), sets storage_ref/content_hash = 'ERASED', status =
-- 'GDPR_ERASED'. Idempotent (no-op if already GDPR_ERASED). Legal from
-- ANY prior state (PENDING/READY/SUPERSEDED/FAILED) — GDPR erasure must
-- not be blocked by lifecycle position (immutability exception, matches
-- the existing trigger's own carve-out).
--
-- fn_document_gdpr_delete(): the document-level orchestration behind
-- 6F §23.4's 4-step contract, steps 1-3 (step 4, S3 object deletion,
-- stays external/app-layer/post-commit). Erases every non-erased
-- version of the document, then tombstones the document row.
-- =================================================================

CREATE OR REPLACE FUNCTION knowledge.fn_docver_gdpr_erase(
  p_document_version_id UUID,
  p_organization_id     UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM knowledge.document_versions
  WHERE id = p_document_version_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_docver_gdpr_erase: version not found or not owned by tenant. version_id: %', p_document_version_id;
  END IF;

  IF v_status = 'GDPR_ERASED' THEN
    RETURN; -- idempotent no-op
  END IF;

  DELETE FROM knowledge.document_chunks
  WHERE document_version_id = p_document_version_id AND organization_id = p_organization_id;

  UPDATE knowledge.document_versions
  SET storage_ref = 'ERASED', content_hash = 'ERASED', status = 'GDPR_ERASED'
  WHERE id = p_document_version_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_docver_gdpr_erase(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_gdpr_erase(UUID, UUID) TO app_api, app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.fn_document_gdpr_delete(
  p_document_id     UUID,
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_catalog
AS $$
DECLARE
  v_version_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM knowledge.documents
    WHERE id = p_document_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_document_gdpr_delete: document not found or not owned by tenant. document_id: %', p_document_id;
  END IF;

  FOR v_version_id IN
    SELECT id FROM knowledge.document_versions
    WHERE document_id = p_document_id AND organization_id = p_organization_id
      AND status <> 'GDPR_ERASED'
  LOOP
    PERFORM knowledge.fn_docver_gdpr_erase(v_version_id, p_organization_id);
  END LOOP;

  UPDATE knowledge.documents
  SET status = 'DELETED', current_version_id = NULL, original_filename = NULL, deleted_at = NOW(), updated_at = NOW()
  WHERE id = p_document_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_document_gdpr_delete(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_document_gdpr_delete(UUID, UUID) TO app_api, app_worker, app_platform_admin;
