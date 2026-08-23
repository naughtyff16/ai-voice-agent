-- =================================================================
-- Migration 078 (Phase 5F.1): fn_docver_publish() DELETED-document guard
--   + column-level lockdown of documents.current_version_id
-- down_revision: 077_5J1
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6F-16
--
-- Problem (verified live against 034_5F.sql / 036_5F.sql, not assumed):
--   1. knowledge.fn_docver_publish() validates document_versions.status
--      = 'READY' but never checks documents.status. If a document's
--      delete flow has already tombstoned it (status = 'DELETED'), a
--      late-committing/concurrent publish call silently revives it —
--      sets current_version_id and status = 'READY' on an already-
--      deleted document. 6F Race #9 / DEP-6F-16.
--   2. Independently, documents.current_version_id (INV-12, "Publication
--      gate ... Set by fn_docver_publish() only" per 036_5F.sql's own
--      column comment) is only a convention — app_api/app_worker hold
--      plain table UPDATE on knowledge.documents (036_5F.sql) with no
--      column-level restriction and no FK, so either role could set
--      current_version_id directly, bypassing fn_docver_publish()
--      (and the guard added below) entirely. This is the same
--      integrity gap from a second angle and is closed in the same
--      migration.
--
-- Fix:
--   1. CREATE OR REPLACE fn_docver_publish() with an added precondition
--      that the target document is not DELETED.
--   2. REVOKE UPDATE (current_version_id) ON knowledge.documents FROM
--      app_api, app_worker. SECURITY DEFINER functions (this one,
--      fn_docver_rollback in 079, fn_document_gdpr_delete in 081) are
--      unaffected — they run as the owning role, not the caller.
--      app_platform_admin's existing full-table grant (044_5F.sql) is
--      untouched.
-- =================================================================

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
DECLARE
  v_old_version_id UUID;
  v_doc_status     TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM knowledge.document_versions
    WHERE id = p_new_version_id AND document_id = p_document_id
      AND organization_id = p_organization_id AND status = 'READY'
  ) THEN
    RAISE EXCEPTION 'fn_docver_publish: version does not belong to document, tenant, or is not READY. document_id: %, version_id: %', p_document_id, p_new_version_id;
  END IF;

  SELECT current_version_id, status INTO v_old_version_id, v_doc_status
  FROM knowledge.documents
  WHERE id = p_document_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_docver_publish: document not found or not owned by tenant. document_id: %', p_document_id;
  END IF;

  IF v_doc_status = 'DELETED' THEN
    RAISE EXCEPTION 'fn_docver_publish: document % is DELETED and cannot be published to (DEP-6F-16 guard).', p_document_id;
  END IF;

  IF v_old_version_id IS NOT NULL THEN
    UPDATE knowledge.document_versions SET status = 'SUPERSEDED'
    WHERE id = v_old_version_id AND organization_id = p_organization_id;
  END IF;

  UPDATE knowledge.documents SET current_version_id = p_new_version_id, status = 'READY', updated_at = NOW()
  WHERE id = p_document_id AND organization_id = p_organization_id;
END;
$$;
-- REVOKE ALL / GRANT EXECUTE unchanged from 034_5F.sql — CREATE OR REPLACE
-- preserves existing grants, restated here for auditability only.
REVOKE ALL ON FUNCTION knowledge.fn_docver_publish(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_publish(UUID, UUID, UUID) TO app_api, app_worker, app_platform_admin;

-- Column-level lockdown: current_version_id may only move through
-- fn_docver_publish() / fn_docver_rollback() (079) / fn_document_gdpr_delete()
-- (081), all SECURITY DEFINER.
--
-- Postgres note: column-level REVOKE cannot narrow a pre-existing
-- table-level GRANT UPDATE (column privileges are additive on top of,
-- never subtractive from, a table-level grant — REVOKE UPDATE
-- (current_version_id) alone would be a silent no-op here). The correct
-- mechanism is to REVOKE the table-level UPDATE entirely and re-GRANT
-- UPDATE at the column level for every column except current_version_id
-- — preserving the exact prior behavior for all other columns (this
-- migration narrows only current_version_id; it does not otherwise
-- change what app_api/app_worker may update on this table).
REVOKE UPDATE ON knowledge.documents FROM app_api, app_worker;
GRANT UPDATE (
  organization_id, knowledge_base_id, source_type, original_filename,
  title, status, metadata, deleted_at, created_by, created_at, updated_at
) ON knowledge.documents TO app_api, app_worker;
