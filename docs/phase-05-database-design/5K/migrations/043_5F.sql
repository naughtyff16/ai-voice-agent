-- =================================================================
-- Migration 043 (Phase 5F): HNSW vector index on document_chunks
-- down_revision: 042_5G
-- Transaction: YES (PostgreSQL 16 does not support CREATE INDEX
--              CONCURRENTLY on partitioned tables; the 5K spec calls
--              for CONCURRENTLY specifically to avoid blocking during
--              initial deployment, but since document_chunks is
--              LIST-partitioned and the only partition at migration
--              time is the DEFAULT safety partition with no data,
--              a standard transactional CREATE INDEX is safe and
--              instantaneous. The CONCURRENTLY qualifier applies to
--              future per-KB partitions created by create_kb_partition()
--              at runtime — those should use CREATE INDEX CONCURRENTLY
--              at the application layer when building on non-empty
--              partitions.)
-- Source: 5F §14 Migration 043
-- =================================================================

CREATE INDEX idx_dc_embedding_hnsw
  ON knowledge.document_chunks
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
