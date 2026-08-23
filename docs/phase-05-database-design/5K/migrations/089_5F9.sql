-- =================================================================
-- Migration 089 (Phase 5F.9): rollback-safe generation cleanup
--   + the unified retrieval-generation contract
-- down_revision: 088_5F8
-- Transaction: yes
-- Source: Phase 5L.1 post-reconciliation correction, Blocker #4
--   (fn_docver_rollback vs fn_kb_reindex_cleanup_old_generations)
--
-- PROBLEM: the executed fn_kb_reindex_cleanup_old_generations() deleted
-- every document_chunks row with index_generation < the KB's current
-- index_version, unconditionally. A document_version that is SUPERSEDED
-- (i.e., rollback-eligible via fn_docver_rollback(), migration
-- 079_5F2.sql) but was never re-embedded into a newer generation (which
-- is normal — a reindex only rebuilds the currently-published content,
-- per the job manifest added in 088_5F8.sql) has its *only* surviving
-- chunk copy tagged with whatever generation existed when it was last
-- current. Unconditional cleanup deletes that copy. A subsequent
-- rollback to that version then succeeds at the SQL layer (document_versions
-- and documents rows are fine) but leaves the reactivated version with
-- zero searchable chunks — a silent RAG-correctness break, not caught by
-- any constraint.
--
-- Considered and rejected:
--   Option A (rebuild every rollback-eligible historical version into
--   every new generation) — correctness-preserving but rebuilds
--   unbounded historical content on every reindex; not grounded in any
--   frozen requirement and explicitly against "no overbuilding".
--   Option B (make rollback an async, worker-driven rebuild-then-cutover
--   operation, mirroring reindex) — adds an entire second asynchronous
--   lifecycle for what FR-RAG-004/4E model as a synchronous pointer-swap
--   (mirroring Prompt Management's synchronous rollback), and the
--   embedding rebuild itself is an external (non-DB) operation with no
--   DDD basis for gating rollback behind it.
--
-- CHOSEN — Option D (source-grounded, not implementation-convenience):
-- cleanup deletes an old-generation chunk row for a given
-- document_version_id ONLY IF a newer-generation chunk row already
-- exists for that SAME document_version_id (proving that specific
-- version's content has a fresh copy and the old one is a true,
-- redundant duplicate — not proof that *some* newer generation exists
-- for the KB in general), OR the owning version has since become
-- GDPR_ERASED/FAILED (nothing to protect). A SUPERSEDED, still-
-- rollback-eligible version's sole surviving chunk copy is therefore
-- never removed by this function, for as long as it remains
-- rollback-eligible — regardless of how many KB-wide reindexes have run
-- since. This is a deliberate, disclosed storage/retention trade-off in
-- favor of the correctness guarantee this section requires; it does not
-- create unbounded growth beyond what already exists (document_versions
-- itself already retains full history indefinitely by design, 5F §14).
--
-- UNIFIED RETRIEVAL CONTRACT (documented here; no DB enforcement of a
-- query shape is possible, so this is also restated in the 5F/6F
-- amendments): a chunk row is eligible for retrieval when
--   document_version_id = documents.current_version_id
--   AND index_generation <= knowledge_bases.index_version
-- This single predicate is what makes the guarantee above actually
-- useful: it hides not-yet-cut-over new-generation rows during a
-- rebuild (their generation number exceeds index_version until
-- fn_kb_reindex_complete() advances it) AND finds a rollback-reactivated
-- version regardless of how far behind its generation number is
-- (a reactivated version's generation number can never exceed the
-- current index_version, since it was created at or before it). In
-- steady state there is exactly one qualifying row per current_version_id
-- (this cleanup function is what keeps that true for rebuilt content;
-- rollback-reactivated content never had a second copy to begin with).
--
-- A supporting index is added for both the cleanup EXISTS-subquery and
-- this retrieval predicate.
-- =================================================================

CREATE INDEX idx_dc_version_generation ON knowledge.document_chunks (document_version_id, index_generation);

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

  DELETE FROM knowledge.document_chunks dc
  WHERE dc.knowledge_base_id = p_kb_id
    AND dc.index_generation < v_current
    AND (
      -- a strictly newer copy of THIS SAME version's content already
      -- exists — the old row is a true, safe-to-drop duplicate
      EXISTS (
        SELECT 1 FROM knowledge.document_chunks newer
        WHERE newer.document_version_id = dc.document_version_id
          AND newer.knowledge_base_id = dc.knowledge_base_id
          AND newer.index_generation >= v_current
      )
      OR
      -- nothing left to protect — the version can never become current
      -- again
      EXISTS (
        SELECT 1 FROM knowledge.document_versions dv
        WHERE dv.id = dc.document_version_id
          AND dv.status IN ('GDPR_ERASED', 'FAILED')
      )
    );
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- Retire job/manifest bookkeeping for generations that are both old
  -- and no longer mid-build (never touch a still-BUILDING job — that
  -- would be a concurrent reindex, not this one's business).
  DELETE FROM knowledge.kb_reindex_jobs
  WHERE knowledge_base_id = p_kb_id AND generation < v_current AND status <> 'BUILDING';

  RETURN v_deleted;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_cleanup_old_generations(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_cleanup_old_generations(UUID, UUID) TO app_worker, app_platform_admin;
