-- =================================================================
-- Migration 088 (Phase 5F.8): reindex build manifest + completeness proof
--   + fn_kb_reindex_fail generation-forgery guard
-- down_revision: 087_5B1
-- Transaction: yes
-- Source: Phase 5L.1 post-reconciliation correction, Blockers #2 and #3
--   (independent review findings against migration 083_5F6.sql)
--
-- BLOCKER (fn_kb_reindex_fail): the executed function deleted
-- WHERE index_generation = p_failed_generation without proving
-- p_failed_generation is actually the pending build generation
-- (index_version + 1). A buggy or malicious app_worker could pass the
-- CURRENT serving generation and delete it. Fixed by requiring
-- p_failed_generation = index_version + 1 AND a matching 'BUILDING'
-- job row to exist (belt-and-suspenders — the job table is now the
-- authoritative record of which generation is actually pending).
--
-- BLOCKER (fn_kb_reindex_complete): the executed function only proved
-- "at least one chunk row exists" for the new generation — a rebuild
-- that produced 1 chunk out of a KB with 100 searchable documents
-- would pass and silently disappear 99 documents from retrieval.
--
-- Fixed with the smallest source-grounded completeness check: a new
-- immutable manifest, snapshotted once at fn_kb_reindex_begin() time,
-- records every currently-searchable (READY, non-deleted) document
-- version and its already-durable expected_chunk_count
-- (document_versions.chunk_count, set by fn_docver_mark_ready() and
-- otherwise untouched). fn_kb_reindex_complete() then requires, for
-- every manifest entry still relevant at completion time (its document
-- not since deleted, its version still READY — entries whose document
-- was archived/deleted or whose version was superseded/GDPR-erased
-- during the rebuild are correctly excluded, since they are no longer
-- part of what needs to be searchable), that generation N+1 has
-- EXACTLY expected_chunk_count chunks for that version_id — not merely
-- "at least one". A newly-ingested document created during the rebuild
-- is not in the manifest and is not required (it was not part of the
-- snapshot the rebuild was scoped against); it is naturally picked up
-- by the next reindex, matching standard rebuild-snapshot semantics.
-- =================================================================

CREATE TABLE knowledge.kb_reindex_jobs (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  knowledge_base_id UUID        NOT NULL,
  organization_id   UUID        NOT NULL,
  generation        INTEGER     NOT NULL,
  status            TEXT        NOT NULL DEFAULT 'BUILDING',
  started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at      TIMESTAMPTZ NULL,

  CONSTRAINT pk_kb_reindex_jobs    PRIMARY KEY (id),
  CONSTRAINT fk_krj_kb             FOREIGN KEY (knowledge_base_id) REFERENCES knowledge.knowledge_bases(id) ON DELETE CASCADE,
  CONSTRAINT chk_krj_status        CHECK (status IN ('BUILDING','COMPLETED','FAILED')),
  CONSTRAINT chk_krj_generation    CHECK (generation >= 2)
);
-- Partial (not table-wide) uniqueness: a FAILED attempt at generation N
-- must not permanently block a later retry at the same generation N
-- (fn_kb_reindex_begin() always computes the new generation as
-- index_version + 1, which is unchanged by a failed attempt — a
-- table-wide UNIQUE(kb, generation) would make generation N unusable
-- forever after one failure). Only one BUILDING or COMPLETED job may
-- ever exist per (kb, generation); any number of FAILED ones may.
CREATE UNIQUE INDEX uq_krj_kb_generation_active ON knowledge.kb_reindex_jobs (knowledge_base_id, generation) WHERE status <> 'FAILED';
CREATE INDEX idx_krj_kb_status ON knowledge.kb_reindex_jobs (knowledge_base_id, status);
ALTER TABLE knowledge.kb_reindex_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.kb_reindex_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_krj_tenant ON knowledge.kb_reindex_jobs FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON knowledge.kb_reindex_jobs TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON knowledge.kb_reindex_jobs TO app_platform_admin;

CREATE TABLE knowledge.kb_reindex_job_manifest (
  job_id                UUID    NOT NULL,
  document_version_id   UUID    NOT NULL,
  expected_chunk_count  INTEGER NOT NULL,
  organization_id       UUID    NOT NULL,

  CONSTRAINT pk_krjm             PRIMARY KEY (job_id, document_version_id),
  CONSTRAINT fk_krjm_job         FOREIGN KEY (job_id) REFERENCES knowledge.kb_reindex_jobs(id) ON DELETE CASCADE,
  CONSTRAINT chk_krjm_chunk_ct   CHECK (expected_chunk_count >= 0)
);
ALTER TABLE knowledge.kb_reindex_job_manifest ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.kb_reindex_job_manifest FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_krjm_tenant ON knowledge.kb_reindex_job_manifest FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON knowledge.kb_reindex_job_manifest TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON knowledge.kb_reindex_job_manifest TO app_platform_admin;

-- No direct INSERT/UPDATE/DELETE grant to app_api/app_worker on either
-- table above — only the SECURITY DEFINER functions below (which run
-- as the owning role) write them, matching this schema's established
-- house style (e.g. document_versions, break_glass_grants).

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

  -- Snapshot the rebuild scope: every document's current READY version
  -- in this KB, at this instant. Documents ingested or republished
  -- after this snapshot are intentionally not required by this job —
  -- they are within scope of the *next* reindex.
  INSERT INTO knowledge.kb_reindex_job_manifest (job_id, document_version_id, expected_chunk_count, organization_id)
  SELECT v_job_id, d.current_version_id, COALESCE(dv.chunk_count, 0), p_organization_id
  FROM knowledge.documents d
  JOIN knowledge.document_versions dv ON dv.id = d.current_version_id
  WHERE d.knowledge_base_id = p_kb_id
    AND d.organization_id = p_organization_id
    AND d.status <> 'DELETED'
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

  SELECT count(*) INTO v_missing
  FROM knowledge.kb_reindex_job_manifest m
  JOIN knowledge.document_versions dv ON dv.id = m.document_version_id
  JOIN knowledge.documents d ON d.id = dv.document_id
  WHERE m.job_id = v_job_id
    AND d.status <> 'DELETED'   -- excluded: archived/deleted during rebuild
    AND dv.status = 'READY'     -- excluded: superseded (rollback/republish) or GDPR-erased during rebuild
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
  v_status  TEXT;
  v_current INTEGER;
  v_job_id  UUID;
BEGIN
  SELECT status, index_version INTO v_status, v_current
  FROM knowledge.knowledge_bases
  WHERE id = p_kb_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_fail: knowledge base not found or not owned by tenant. kb_id: %', p_kb_id;
  END IF;
  IF v_status <> 'REINDEXING' THEN
    RAISE EXCEPTION 'fn_kb_reindex_fail: knowledge base % is % — cannot fail a reindex that is not in progress.', p_kb_id, v_status;
  END IF;

  -- Fixed this pass: p_failed_generation must be exactly the pending
  -- build generation. Without this, a caller could pass the current
  -- (serving) or any historical generation and have its chunks deleted.
  IF p_failed_generation <> v_current + 1 THEN
    RAISE EXCEPTION 'fn_kb_reindex_fail: p_failed_generation % does not match the pending build generation % for kb % — refusing (this would risk deleting a serving or historical generation).', p_failed_generation, v_current + 1, p_kb_id;
  END IF;

  SELECT id INTO v_job_id FROM knowledge.kb_reindex_jobs
  WHERE knowledge_base_id = p_kb_id AND generation = p_failed_generation AND status = 'BUILDING'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_kb_reindex_fail: no BUILDING job found for kb % generation % — nothing to fail.', p_kb_id, p_failed_generation;
  END IF;

  DELETE FROM knowledge.document_chunks
  WHERE knowledge_base_id = p_kb_id AND index_generation = p_failed_generation;

  UPDATE knowledge.kb_reindex_jobs SET status = 'FAILED', completed_at = NOW() WHERE id = v_job_id;

  UPDATE knowledge.knowledge_bases
  SET status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_kb_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION knowledge.fn_kb_reindex_fail(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_kb_reindex_fail(UUID, UUID, INTEGER) TO app_worker, app_platform_admin;
