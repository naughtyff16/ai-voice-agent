-- =================================================================
-- Migration 090 (Phase 5F.10): lock identity/ownership/audit-origin
--   columns on knowledge.documents
-- down_revision: 089_5F9
-- Transaction: yes
-- Source: Phase 5L.1 post-reconciliation correction, Blocker #5
--
-- Migration 082_5F5.sql added document_versions.knowledge_base_id,
-- server-derived and immutable, on the assumption that
-- documents.knowledge_base_id itself does not change after a version
-- exists. Migration 078_5F1.sql, however, re-granted app_api/app_worker
-- column-level UPDATE on every knowledge.documents column except
-- current_version_id — including knowledge_base_id, organization_id,
-- source_type, created_by, and created_at. Nothing prevented an
-- ordinary UPDATE from moving a Document to a different Knowledge Base
-- (or a different tenant) after its versions were created, silently
-- invalidating 082's "cannot drift from its parent" guarantee, the
-- KB-wide dedup scope (DEP-6F-14), reindex ownership, and retrieval
-- scoping.
--
-- Checked against 4E's Document aggregate (§4.2) before fixing: its
-- command list is UploadDocument, StartIngestion, MarkChunked,
-- MarkEmbedded, MarkIndexed, MarkFailed, ReprocessDocument,
-- ArchiveDocument, DeleteDocument — no move/transfer-between-KBs (or
-- between-tenants) command exists anywhere in the frozen DDD. Moving a
-- Document between Knowledge Bases is therefore not a supported
-- capability, and locking the column is a correctness fix, not a
-- capability removal.
--
-- Columns locked (identity/ownership/audit-origin — never legitimately
-- app-mutable): knowledge_base_id, organization_id, source_type,
-- created_by, created_at.
-- Columns still app-writable (ordinary mutable document fields,
-- unchanged from before): title, original_filename, status, metadata,
-- deleted_at, updated_at.
-- current_version_id remains locked from 078_5F1.sql (SECURITY DEFINER
-- functions only).
-- =================================================================

REVOKE UPDATE ON knowledge.documents FROM app_api, app_worker;
GRANT UPDATE (
  title, original_filename, status, metadata, deleted_at, updated_at
) ON knowledge.documents TO app_api, app_worker;
