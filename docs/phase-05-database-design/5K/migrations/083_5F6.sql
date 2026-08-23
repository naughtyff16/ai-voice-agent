-- =================================================================
-- Migration 083 (Phase 5F.6): KB reindex — derived chunk/index generations
-- down_revision: 082_5F5
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6F-02
--
-- No dual-generation representation exists anywhere in the executed
-- schema; the previously-withdrawn "fake" metadata-only reindex is
-- confirmed absent (not restored here). knowledge_bases.status already
-- has a REINDEXING value and index_version already exists (035_5F.sql)
-- but nothing has ever written to either meaningfully.
--
-- Design: derived generations on document_chunks (not a new
-- DocumentVersion abuse). A new document_chunks.index_generation column
-- tags which "build" a chunk row belongs to. knowledge_bases.index_version
-- (already existing) is reused as the KB's current-serving-generation
-- pointer — no new KB column. Old and new generations coexist in the
-- same partition during a rebuild (satisfies 4E invariant 3: "a KB in
-- REINDEXING continues to serve queries from the previous index version
-- ... only replaced when the new one is fully built") because nothing
-- about the old generation's rows is touched until an explicit,
-- separate cutover.
--
-- Four SECURITY DEFINER functions provide the safe state machine:
--   fn_kb_reindex_begin     ACTIVE -> REINDEXING, returns the new
--                           generation number to tag freshly-built
--                           chunks with. Advisory-lock-guarded so two
--                           concurrent reindex requests for the same KB
--                           cannot both proceed.
--   fn_kb_reindex_complete  Atomic cutover: bumps index_version to the
--                           new generation, REINDEXING -> ACTIVE. CAS-
--                           guarded on the expected new-generation
--                           number; requires the new generation to
--                           actually have rows (refuses to cut over to
--                           an empty/failed build).
--   fn_kb_reindex_fail      Reverts status to ACTIVE without bumping
--                           index_version (old generation stays
--                           current) and deletes the failed generation's
--                           partial rows.
--   fn_kb_reindex_cleanup_old_generations
--                           Deletes rows strictly older than the
--                           current generation. Callable separately
--                           (not inline in complete()) so cutover stays
--                           fast; safe to run any time after a
--                           successful cutover.
--
-- Existing HNSW (idx_dc_embedding_hnsw) and GIN (idx_dc_tsvector)
-- indexes cover the embedding/tsvector_content columns across all
-- generations already present — no change needed to either; query-time
-- generation filtering (WHERE index_generation = <kb's current
-- index_version>) is an application-layer contract, documented in the
-- 5F amendment, not a DB-enforced default (mirrors how document status
-- filtering already works for search queries).
-- =================================================================

ALTER TABLE knowledge.document_chunks
  ADD COLUMN index_generation INTEGER NOT NULL DEFAULT 1;
ALTER TABLE knowledge.document_chunks
  ADD CONSTRAINT chk_dc_index_generation CHECK (index_generation >= 1);

-- Widen the chunk-position uniqueness to include the generation, so the
-- same document_version's chunks can legally exist under two
-- generations simultaneously during a rebuild.
ALTER TABLE knowledge.document_chunks DROP CONSTRAINT uq_chunk_position;
ALTER TABLE knowledge.document_chunks
  ADD CONSTRAINT uq_chunk_position UNIQUE (document_version_id, chunk_index, knowledge_base_id, index_generation);

CREATE INDEX idx_dc_kb_generation ON knowledge.document_chunks (knowledge_base_id, index_generation);

CREATE OR REPLACE FUNCTION knowledge.fn_kb_reindex_begin(
  p_kb_id           UUID,
  p_organization_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_catalog
AS $$
DECLARE
  v_status  TEXT;
  v_current INTEGER;
BEGIN
  -- Serialize concurrent begin attempts for the same KB.
  PERFORM pg_advisory_xact_lock(hashtext('knowledge.reindex:' || p_kb_id::text));

  SELECT status, index_version INTO v_status, v_current
  FROM knowledge.knowledge_bases
  WHERE id = p_kb_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_begin: knowledge base not found or not owned by tenant. kb_id: %', p_kb_id;
  END IF;

  IF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'fn_kb_reindex_begin: knowledge base % is % — reindex may only begin from ACTIVE.', p_kb_id, v_status;
  END IF;

  UPDATE knowledge.knowledge_bases
  SET status = 'REINDEXING', updated_at = NOW()
  WHERE id = p_kb_id AND organization_id = p_organization_id;

  RETURN v_current + 1;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_begin(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_begin(UUID, UUID) TO app_api, app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.fn_kb_reindex_complete(
  p_kb_id           UUID,
  p_organization_id UUID,
  p_new_generation  INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_catalog
AS $$
DECLARE
  v_status  TEXT;
  v_current INTEGER;
BEGIN
  SELECT status, index_version INTO v_status, v_current
  FROM knowledge.knowledge_bases
  WHERE id = p_kb_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_complete: knowledge base not found or not owned by tenant. kb_id: %', p_kb_id;
  END IF;

  IF v_status <> 'REINDEXING' THEN
    RAISE EXCEPTION 'fn_kb_reindex_complete: knowledge base % is % — cannot complete a reindex that is not in progress.', p_kb_id, v_status;
  END IF;

  IF p_new_generation <> v_current + 1 THEN
    RAISE EXCEPTION 'fn_kb_reindex_complete: generation mismatch for kb % (expected %, got %) — stale or duplicate completion call.', p_kb_id, v_current + 1, p_new_generation;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM knowledge.document_chunks
    WHERE knowledge_base_id = p_kb_id AND index_generation = p_new_generation
  ) THEN
    RAISE EXCEPTION 'fn_kb_reindex_complete: generation % of kb % has no chunk rows — refusing to cut over to an empty build.', p_new_generation, p_kb_id;
  END IF;

  UPDATE knowledge.knowledge_bases
  SET index_version = p_new_generation, status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_kb_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_complete(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_complete(UUID, UUID, INTEGER) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.fn_kb_reindex_fail(
  p_kb_id             UUID,
  p_organization_id   UUID,
  p_failed_generation INTEGER
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
  FROM knowledge.knowledge_bases
  WHERE id = p_kb_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_fail: knowledge base not found or not owned by tenant. kb_id: %', p_kb_id;
  END IF;

  IF v_status <> 'REINDEXING' THEN
    RAISE EXCEPTION 'fn_kb_reindex_fail: knowledge base % is % — cannot fail a reindex that is not in progress.', p_kb_id, v_status;
  END IF;

  DELETE FROM knowledge.document_chunks
  WHERE knowledge_base_id = p_kb_id AND index_generation = p_failed_generation;

  UPDATE knowledge.knowledge_bases
  SET status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_kb_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_fail(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_fail(UUID, UUID, INTEGER) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION knowledge.fn_kb_reindex_cleanup_old_generations(
  p_kb_id           UUID,
  p_organization_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_catalog
AS $$
DECLARE
  v_current INTEGER;
  v_deleted INTEGER;
BEGIN
  SELECT index_version INTO v_current
  FROM knowledge.knowledge_bases
  WHERE id = p_kb_id AND organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_cleanup_old_generations: knowledge base not found or not owned by tenant. kb_id: %', p_kb_id;
  END IF;

  DELETE FROM knowledge.document_chunks
  WHERE knowledge_base_id = p_kb_id AND index_generation < v_current;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_cleanup_old_generations(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_cleanup_old_generations(UUID, UUID) TO app_worker, app_platform_admin;
