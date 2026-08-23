-- =================================================================
-- Migration 092 (Phase 5F.12): reindex manifest predicate corrected to
--   the true retrieval-eligibility rule (READY only, not merely
--   "not DELETED")
-- down_revision: 091_5F11
-- Transaction: yes
-- Source: Phase 5L.2 final freeze review, item 6
--
-- 088_5F8.sql's manifest population (fn_kb_reindex_begin) and
-- completion-relevance check (fn_kb_reindex_complete) both used
-- `d.status <> 'DELETED'` to decide which documents are "currently
-- searchable" and therefore must be present in the rebuild manifest.
-- That predicate is too broad: documents.status also has an ARCHIVED
-- value, and 6F's ArchivedDocumentNotQueryable policy (4E §10, 6F
-- §23.3/§23.5) excludes ARCHIVED documents from retrieval — only
-- status='READY' is actually queryable. Under the old predicate, an
-- ARCHIVED document was still required by the manifest, and a reindex
-- worker that correctly skipped rebuilding non-searchable ARCHIVED
-- content would have its completion wrongly rejected as "incomplete."
--
-- Fixed by tightening both predicates to `d.status = 'READY'`. This
-- also correctly handles a document ARCHIVED (or DELETED) *during* an
-- in-progress rebuild: fn_kb_reindex_complete()'s check re-evaluates
-- documents.status at completion time, so a manifest entry whose
-- document is no longer READY by then is excluded from what must be
-- proven complete — it does not block cutover. (A version SUPERSEDED
-- during rebuild was already correctly excluded via the existing
-- `dv.status = 'READY'` check — unaffected by this migration.)
-- =================================================================

CREATE OR REPLACE FUNCTION knowledge.fn_kb_reindex_begin(
  p_kb_id           UUID,
  p_organization_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_catalog, public
AS $$
DECLARE
  v_status         TEXT;
  v_current        INTEGER;
  v_new_generation INTEGER;
  v_job_id         UUID;
BEGIN
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

  v_new_generation := v_current + 1;

  UPDATE knowledge.knowledge_bases
  SET status = 'REINDEXING', updated_at = NOW()
  WHERE id = p_kb_id AND organization_id = p_organization_id;

  INSERT INTO knowledge.kb_reindex_jobs (knowledge_base_id, organization_id, generation, status)
  VALUES (p_kb_id, p_organization_id, v_new_generation, 'BUILDING')
  RETURNING id INTO v_job_id;

  -- Snapshot the rebuild scope: every document's current version that
  -- is actually retrieval-eligible right now (status = 'READY' — the
  -- only value ArchivedDocumentNotQueryable/6F actually search), with
  -- that version READY. ARCHIVED/DELETED/PENDING/PROCESSING/FAILED
  -- documents are correctly never required by this job.
  INSERT INTO knowledge.kb_reindex_job_manifest (job_id, document_version_id, expected_chunk_count, organization_id)
  SELECT v_job_id, d.current_version_id, COALESCE(dv.chunk_count, 0), p_organization_id
  FROM knowledge.documents d
  JOIN knowledge.document_versions dv ON dv.id = d.current_version_id
  WHERE d.knowledge_base_id = p_kb_id
    AND d.organization_id = p_organization_id
    AND d.status = 'READY'
    AND d.current_version_id IS NOT NULL
    AND dv.status = 'READY';

  RETURN v_new_generation;
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
  v_status        TEXT;
  v_current       INTEGER;
  v_job_id        UUID;
  v_missing       INTEGER;
  v_manifest_size INTEGER;
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

  SELECT id INTO v_job_id FROM knowledge.kb_reindex_jobs
  WHERE knowledge_base_id = p_kb_id AND generation = p_new_generation AND status = 'BUILDING'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_complete: no BUILDING job found for kb % generation % — cannot complete.', p_kb_id, p_new_generation;
  END IF;

  SELECT count(*) INTO v_manifest_size FROM knowledge.kb_reindex_job_manifest WHERE job_id = v_job_id;

  -- A manifest entry is still "relevant" (must be proven complete) only
  -- if its document is still READY (excludes: archived or deleted since
  -- begin) and its version is still READY (excludes: superseded via a
  -- publish/rollback, or GDPR-erased, since begin).
  SELECT count(*) INTO v_missing
  FROM knowledge.kb_reindex_job_manifest m
  JOIN knowledge.document_versions dv ON dv.id = m.document_version_id
  JOIN knowledge.documents d ON d.id = dv.document_id
  WHERE m.job_id = v_job_id
    AND d.status = 'READY'
    AND dv.status = 'READY'
    AND (
      SELECT count(*) FROM knowledge.document_chunks c
      WHERE c.document_version_id = m.document_version_id AND c.index_generation = p_new_generation
    ) <> m.expected_chunk_count;

  IF v_missing > 0 THEN
    RAISE EXCEPTION 'fn_kb_reindex_complete: % of % manifested document version(s) are missing or incomplete in generation % — refusing to cut over to a partial build.', v_missing, v_manifest_size, p_new_generation;
  END IF;

  UPDATE knowledge.kb_reindex_jobs SET status = 'COMPLETED', completed_at = NOW() WHERE id = v_job_id;

  UPDATE knowledge.knowledge_bases
  SET index_version = p_new_generation, status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_kb_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_complete(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_complete(UUID, UUID, INTEGER) TO app_worker, app_platform_admin;
