-- =================================================================
-- Migration 080 (Phase 5F.3): knowledge.fn_docver_mark_failed()
-- down_revision: 079_5F2
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6F-09
--
-- No SECURITY DEFINER path exists to set document_versions.status =
-- 'FAILED' (verified: 036_5F.sql unconditionally revokes UPDATE, DELETE
-- on document_versions from app_api/app_worker; 034_5F.sql only defines
-- fn_docver_mark_ready() and fn_docver_publish(), neither of which
-- transitions to FAILED). This blocks the document reprocess flow
-- (POST .../documents/{id}/reprocess, 6F §15) as a normal-path
-- consequence of any first-ingestion failure, not merely under
-- contention.
--
-- Allowed source state: PENDING only (a version that has not yet
-- completed ingestion). Idempotent: re-calling on an already-FAILED
-- version is a no-op, not an error (tolerates retry from an at-least-
-- once ingestion worker). Any other source state (READY, SUPERSEDED,
-- GDPR_ERASED) is rejected — those are not valid predecessors of a
-- FAILED outcome. No content or ownership column is touched.
-- =================================================================

CREATE OR REPLACE FUNCTION knowledge.fn_docver_mark_failed(
  p_document_version_id UUID,
  p_organization_id     UUID,
  p_reason              TEXT DEFAULT NULL
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
    RAISE EXCEPTION 'fn_docver_mark_failed: version not found or not owned by tenant. version_id: %', p_document_version_id;
  END IF;

  IF v_status = 'FAILED' THEN
    RETURN; -- idempotent no-op
  END IF;

  IF v_status <> 'PENDING' THEN
    RAISE EXCEPTION 'fn_docver_mark_failed: version % is % — only a PENDING version may be marked FAILED.', p_document_version_id, v_status;
  END IF;

  UPDATE knowledge.document_versions
  SET status = 'FAILED'
  WHERE id = p_document_version_id AND organization_id = p_organization_id;

  -- p_reason is accepted for the caller's audit-event narration (see 5J
  -- amendment, DOCUMENT_VERSION_MARKED_FAILED) but is not persisted here —
  -- document_versions has no failure_reason column; ingestion_jobs.error_message
  -- (already app-writable, 037_5F.sql) is the existing home for that detail.
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_docver_mark_failed(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_mark_failed(UUID, UUID, TEXT) TO app_api, app_worker, app_platform_admin;
