# Phase 5F — Knowledge / RAG Schema
## Physical PostgreSQL Database Design

| | |
|---|---|
| **Phase** | 5F — Knowledge / RAG Schema Physical Database Design |
| **Schema** | `knowledge` |
| **Status** | Corrected v1.1 — Blocker corrections applied before Phase 5G |
| **Authority** | Phase 5A + Phase 5B + Phase 4E (DDD) + Phase 4I (OQ-FINAL-03: embedding model closed) |
| **Follows** | Phase 5E (APPROVED, PHASE 5F READY) |
| **Precedes** | Phase 5G — Workflow / Prompt / Memory Schema |

---

## 1. Executive Summary

This document delivers the complete physical database design for the `knowledge` schema — the RAG (retrieval-augmented generation) data layer. The design is derived from the Phase 4E Knowledge & RAG DDD and Phase 4I, which closed OQ-FINAL-03 (embedding model, dimension, distance metric, and index type).

**Correction pass applied (v1.1):**

| Issue | Fix |
|---|---|
| BLOCKER 1 — `fn_docver_publish()` missing `document_id` ownership check | Added `AND document_id = p_document_id` to precondition; added INV-12 |
| BLOCKER 2 — "document_versions immutable" contradicts lifecycle UPDATEs | Replaced with "content/identity immutable; lifecycle state controlled by SECURITY DEFINER" |

**Critical Phase 4I closed decisions applied here:**

| Decision | Value |
|---|---|
| Embedding model | OpenAI `text-embedding-3-large` |
| Embedding dimensions | **1536** (explicitly requested via API `dimensions=1536`; model default is 3072) |
| Distance metric | **Cosine similarity** (`<=>` operator in pgvector) |
| pgvector index type | **HNSW** |
| `document_chunks` column type | `vector(1536)` |
| `document_chunks` partitioning | LIST on `knowledge_base_id` (Phase 4I §25.15) |

**Key design decisions:**

| Decision | Outcome |
|---|---|
| Aggregates mapped | KnowledgeBase, Document, DocumentVersion, IngestionJob — 4 tables + 1 partitioned entity table |
| Document versioning | Separate `document_versions` table; `documents.current_version_id` is the publication gate |
| Chunks + embeddings | Single `document_chunks` table — Phase 4E §18 explicitly co-locates them |
| Hybrid search | In scope for V1 — Phase 4E §4.4 defines RRF; `tsvector` column on `document_chunks` |
| Agent ↔ KB relationship | Logical UUID references via `agent_versions.snapshot_json` (Phase 5C); no coupling table |
| `document_chunks` partitioning | LIST on `knowledge_base_id` — Phase 4I §25.15 |
| Ingestion job lifecycle | `PENDING\|EXTRACTING\|CHUNKING\|EMBEDDING\|INDEXING\|READY\|FAILED\|CANCELLED` |
| DocumentVersion lifecycle | `PENDING\|READY\|SUPERSEDED\|FAILED\|GDPR_ERASED` |

**Tables created in Phase 5F:** 5 tables (1 LIST-partitioned), SECURITY DEFINER lifecycle functions, HNSW vector index, full-text GIN index.

---

## 2. Scope

**In scope:** `knowledge` schema — 5 tables, all indexes (relational + vector), constraints, RLS, SECURITY DEFINER functions, triggers, grants.

**Out of scope:** `voice`, `crm`, `campaign`, `workflow`, `billing`, `analytics`, `identity`, `organization`. Workflow, Prompt Management, and Conversation Memory are Phase 5G.

---

## 3. Bounded Context Ownership

**Knowledge & RAG context owns:**
- Knowledge Base configuration and lifecycle
- Document registration, version history, publication state
- Ingestion job progress and error tracking
- Document chunks (text fragments + embeddings + full-text index)
- Retrieval configuration (chunking strategy, retrieval config on KB)

**Knowledge does NOT own:**
- Calls, conversations, recordings, transcripts (→ Voice)
- Contacts, consent, suppression (→ CRM)
- Campaigns, call jobs (→ Campaign)
- Workflow definitions and executions (→ Phase 5G)
- Prompt templates (→ Phase 5G)
- Conversation memory (→ Phase 5G)
- Billing and usage events (→ Phase 5H)

**Agent ↔ Knowledge Base relationship:** Agents reference Knowledge Base IDs inside `voice.agent_versions.snapshot_json` (Phase 5C ADR). There is no coupling table in the `knowledge` schema.

---

## 4. Aggregate → Table Mapping

| Phase 4E Aggregate / Entity | Table | Notes |
|---|---|---|
| `KnowledgeBase` (AggregateRoot) | `knowledge.knowledge_bases` | Configuration + lifecycle |
| `Document` (AggregateRoot) | `knowledge.documents` | Lifecycle; `current_version_id` is publication gate |
| `DocumentVersion` (Entity — child of Document) | `knowledge.document_versions` | Separate table; controlled lifecycle |
| `IngestionJob` (AggregateRoot) | `knowledge.ingestion_jobs` | Multi-stage pipeline tracking |
| `DocumentChunk` + `Embedding` (Entity) | `knowledge.document_chunks` | Co-located per Phase 4E §18; LIST-partitioned |

---

## 5. Domain Invariants

| # | Invariant | Source | Enforcement |
|---|---|---|---|
| INV-01 | `EmbeddingModelRef` is immutable after KB creation | Phase 4E §4.1 inv.1 | `BEFORE UPDATE` trigger `knowledge.prevent_kb_model_mutation()` |
| INV-02 | **Document Version Content Immutability.** After creation, normal application operations cannot modify the document version's immutable identity/content fields (`document_id`, `version_number`, `mime_type`, `size_bytes`, `created_at`, `created_by`, `storage_ref`, `content_hash`). Only controlled lifecycle operations may modify lifecycle fields (`status`, `ingestion_completed_at`). GDPR erasure is an explicit compliance exception that may set `storage_ref = 'ERASED'` and `content_hash = 'ERASED'`. | Phase 4E §4.2 | `BEFORE UPDATE` trigger `knowledge.prevent_docver_immutable_field_mutation()` + REVOKE UPDATE from app roles |
| INV-03 | Duplicate content hash rejected within same KB and version scope | Phase 4E §4.2 inv.1 | UNIQUE constraint |
| INV-04 | `AttemptCount ≤ 3` on IngestionJob | Phase 4E §4.3 inv.1 | CHECK constraint |
| INV-05 | Stage transitions monotonic | Phase 4E §4.3 inv.2 | Application layer |
| INV-06 | COMPLETED IngestionJob is immutable | Phase 4E §4.3 inv.3 | `BEFORE UPDATE` trigger `knowledge.prevent_completed_job_mutation()` |
| INV-07 | Only `status = 'INDEXED'` chunks eligible for retrieval | Phase 4E retrieval | `WHERE d.current_version_id = dv.id AND dv.status = 'READY'` in retrieval queries |
| INV-08 | Vector search must enforce `organization_id` | Phase 5A + Phase 4I §25.16 | RLS + explicit filter in all vector queries |
| INV-09 | `EmbeddingDimensions` is immutable after KB creation | Phase 4E §4.1 inv.2 | Same trigger as INV-01 |
| INV-10 | Chunks belong to the document version that produced them | Phase 4E §4.2 | `document_chunks.document_version_id` FK within schema |
| INV-11 | `documents.current_version_id` may only point to a `READY` version of that document | Phase 4E publication contract | `fn_docver_publish()` enforces pre-condition |
| **INV-12** | **Document-Version Ownership.** A document version may become the current version of a document ONLY when: `document_versions.document_id = documents.id` AND `document_versions.organization_id = documents.organization_id` AND `document_versions.status = 'READY'`. | Blocker 1 correction | `fn_docver_publish()` precondition verifies `document_id = p_document_id` AND `organization_id = p_organization_id` AND `status = 'READY'` |

---

## 6. Table Dictionary

### 6.1 `knowledge.knowledge_bases`

**Aggregate:** `KnowledgeBase` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `name` | TEXT | NOT NULL | — | 1–200 chars; unique within org |
| `description` | TEXT | NULL | — | 0–500 chars |
| `embedding_model_ref` | TEXT | NOT NULL | — | Stable ID e.g. `openai:text-embedding-3-large:1536`. **Immutable (INV-01).** |
| `embedding_dimensions` | INTEGER | NOT NULL | — | Derived at creation. **Immutable (INV-09).** Currently `1536`. |
| `chunking_strategy` | JSONB | NOT NULL | — | `ChunkingStrategy` value object |
| `retrieval_config` | JSONB | NOT NULL | `'{}'` | Top-K, similarity threshold, hybrid weights |
| `index_version` | INTEGER | NOT NULL | `1` | Incremented on `TriggerReindex` |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| REINDEXING \| DEGRADED \| ARCHIVED` |
| `document_count` | INTEGER | NOT NULL | `0` | Updated by event handler |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 6.2 `knowledge.documents`

**Aggregate:** `Document` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `knowledge_base_id` | UUID | NOT NULL | — | FK → `knowledge_bases(id)` RESTRICT |
| `source_type` | TEXT | NOT NULL | — | `PDF \| DOCX \| TXT \| CSV \| URL \| FAQ \| WEBSITE` |
| `original_filename` | TEXT | NULL | — | **pii:potential** |
| `title` | TEXT | NULL | — | Human label |
| `status` | TEXT | NOT NULL | `'PENDING'` | Document-level lifecycle status |
| `current_version_id` | UUID | NULL | — | Logical ref: `knowledge.document_versions.id`. Set only when a version becomes READY. **Publication gate (INV-11).** |
| `metadata` | JSONB | NOT NULL | `'{}'` | Key-value filtering metadata (max 50 keys) |
| `deleted_at` | TIMESTAMPTZ | NULL | — | Soft delete — row retained as tombstone |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Document status values:** `PENDING | PROCESSING | READY | FAILED | ARCHIVED | DELETED`

### 6.3 `knowledge.document_versions`

**Entity:** `DocumentVersion` (child of Document aggregate — separate table for controlled lifecycle)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref — for RLS |
| `document_id` | UUID | NOT NULL | — | FK → `knowledge.documents(id)` CASCADE |
| `version_number` | INTEGER | NOT NULL | — | Monotonically increasing per document. **Immutable (INV-02).** |
| `storage_ref` | TEXT | NOT NULL | — | S3 path. **Immutable in normal operation; ERASED on GDPR (INV-02).** **pii:potential** |
| `content_hash` | CHAR(64) | NOT NULL | — | SHA-256 of version content. **Immutable in normal operation; ERASED on GDPR (INV-02).** |
| `mime_type` | TEXT | NOT NULL | — | e.g. `application/pdf`. **Immutable (INV-02).** |
| `size_bytes` | BIGINT | NOT NULL | — | **Immutable (INV-02).** |
| `status` | TEXT | NOT NULL | `'PENDING'` | **Lifecycle state — controlled by SECURITY DEFINER only.** |
| `ingestion_completed_at` | TIMESTAMPTZ | NULL | — | **Lifecycle state — set by `fn_docver_mark_ready()`.** |
| `chunk_count` | INTEGER | NULL | — | Set when ingestion READY |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id`. **Immutable (INV-02).** |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | **Immutable (INV-02).** |

**Document version status values:**
`PENDING | READY | SUPERSEDED | FAILED | GDPR_ERASED`

**Immutability model (INV-02 — BLOCKER 2 resolution):**

| Field category | Fields | Mutability |
|---|---|---|
| Identity / content | `document_id`, `version_number`, `mime_type`, `size_bytes`, `created_at`, `created_by` | **Immutable always** — trigger rejects any UPDATE |
| Content references | `storage_ref`, `content_hash` | **Immutable in normal operation** — GDPR erasure sets both to `'ERASED'` as an explicit compliance exception |
| Lifecycle state | `status`, `ingestion_completed_at` | **Controlled mutation** — only through `fn_docver_mark_ready()`, `fn_docver_publish()`, and the GDPR erasure function |
| Auxiliary | `chunk_count` | Set once when READY; immutable thereafter |

Normal application roles (`app_api`, `app_worker`) have **no UPDATE privilege** on `document_versions`. All permitted updates flow through SECURITY DEFINER lifecycle functions.

### 6.4 `knowledge.ingestion_jobs`

**Aggregate:** `IngestionJob` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `document_version_id` | UUID | NOT NULL | — | FK → `knowledge.document_versions(id)` CASCADE |
| `knowledge_base_id` | UUID | NOT NULL | — | Denormalized |
| `status` | TEXT | NOT NULL | `'PENDING'` | `PENDING\|EXTRACTING\|CHUNKING\|EMBEDDING\|INDEXING\|READY\|FAILED\|CANCELLED` |
| `current_stage` | TEXT | NULL | — | Last active stage |
| `attempt_count` | INTEGER | NOT NULL | `1` | 1–3 |
| `parsed_text_ref` | TEXT | NULL | — | S3 path of intermediate text; cleaned after INDEXING |
| `chunks_produced` | INTEGER | NULL | — | Set after CHUNKING |
| `embeddings_produced` | INTEGER | NULL | — | Set after EMBEDDING |
| `error_message` | TEXT | NULL | — | Set on FAILED |
| `started_at` | TIMESTAMPTZ | NULL | — | |
| `completed_at` | TIMESTAMPTZ | NULL | — | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Ingestion job status distinction from document version status (ADR-5F-004):**

| Axis | Table | Statuses | Meaning |
|---|---|---|---|
| Worker execution state | `ingestion_jobs` | `PENDING\|EXTRACTING\|CHUNKING\|EMBEDDING\|INDEXING\|READY\|FAILED\|CANCELLED` | Pipeline progress — mutable per-worker |
| Durable version lifecycle | `document_versions` | `PENDING\|READY\|SUPERSEDED\|FAILED\|GDPR_ERASED` | Publication state — controlled by SECURITY DEFINER |

When an ingestion job reaches `READY`, it calls `fn_docver_mark_ready()` to advance the document version's status. These are separate state machines.

### 6.5 `knowledge.document_chunks` (Partitioned — LIST on `knowledge_base_id`)

**Entity:** `DocumentChunk` + `Embedding` (co-located per Phase 4E §18)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK `(id, knowledge_base_id)` |
| `knowledge_base_id` | UUID | NOT NULL | — | **Partition key** |
| `organization_id` | UUID | NOT NULL | — | For RLS + pre-filter index |
| `document_id` | UUID | NOT NULL | — | Logical ref: `knowledge.documents.id` |
| `document_version_id` | UUID | NOT NULL | — | Logical ref: `knowledge.document_versions.id` (INV-10) |
| `chunk_index` | INTEGER | NOT NULL | — | 0-based ordering within version |
| `content` | TEXT | NOT NULL | — | Chunk text. **pii:potential** |
| `content_hash` | CHAR(64) | NOT NULL | — | SHA-256 of `content`. Idempotency key. |
| `embedding` | vector(1536) | NOT NULL | — | OpenAI `text-embedding-3-large` @ 1536 dims. **pii:potential (derived)** |
| `tsvector_content` | TSVECTOR | NOT NULL | — | Full-text index. Auto-maintained by trigger. |
| `token_count` | INTEGER | NOT NULL | — | |
| `page_number` | INTEGER | NULL | — | |
| `section_heading` | TEXT | NULL | — | |
| `source_location` | TEXT | NULL | — | For citation |
| `embedding_model_ref` | TEXT | NOT NULL | — | Must match KB's `embedding_model_ref` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Append-only (INSERT/DELETE, no UPDATE):** `REVOKE UPDATE ON knowledge.document_chunks FROM app_api, app_worker`.

---

## 7. JSONB Decisions

### 7.1 `chunking_strategy` — JSONB on `knowledge_bases`

Bounded value object, always read with KB. Structure: `{strategy_type, chunk_size_tokens, overlap_tokens, split_on}`.

### 7.2 `retrieval_config` — JSONB on `knowledge_bases`

Bounded retrieval defaults. Structure: `{default_top_k, similarity_threshold, hybrid_search_enabled, hybrid_semantic_weight, hybrid_keyword_weight}`.

### 7.3 `metadata` — JSONB on `documents`

Variable key-value pairs for filtering (max 50 keys, values: string/number/boolean). Always read with Document.

---

## 8. Unique Constraints

| Table | Columns | Condition | Rationale |
|---|---|---|---|
| `knowledge_bases` | `(organization_id, name)` | — | Unique KB name per tenant |
| `documents` | `(knowledge_base_id, id)` | — | PK-backed; no natural unique other than PK |
| `document_versions` | `(document_id, version_number)` | — | Unique version per document |
| `document_versions` | `(knowledge_base_id, content_hash)` | `WHERE status NOT IN ('FAILED','GDPR_ERASED')` | Dedup within KB across all active versions |
| `document_chunks` | `(document_version_id, chunk_index, knowledge_base_id)` | — | Unique chunk position per version (must include partition key) |

---

## 9. Check Constraints

```sql
-- knowledge_bases
CHECK (status IN ('ACTIVE','REINDEXING','DEGRADED','ARCHIVED'))
CHECK (embedding_dimensions > 0)
CHECK (document_count >= 0)
CHECK (index_version >= 1)
CHECK (length(name) BETWEEN 1 AND 200)

-- documents
CHECK (source_type IN ('PDF','DOCX','TXT','CSV','URL','FAQ','WEBSITE'))
CHECK (status IN ('PENDING','PROCESSING','READY','FAILED','ARCHIVED','DELETED'))

-- document_versions
CHECK (status IN ('PENDING','READY','SUPERSEDED','FAILED','GDPR_ERASED'))
CHECK (version_number >= 1)
CHECK (size_bytes > 0)
CHECK (chunk_count IS NULL OR chunk_count >= 0)
-- storage_ref and content_hash may be 'ERASED' (GDPR exception), hence no format CHECK

-- ingestion_jobs
CHECK (status IN ('PENDING','EXTRACTING','CHUNKING','EMBEDDING','INDEXING','READY','FAILED','CANCELLED'))
CHECK (attempt_count BETWEEN 1 AND 3)
CHECK (chunks_produced IS NULL OR chunks_produced >= 0)
CHECK (embeddings_produced IS NULL OR embeddings_produced >= 0)

-- document_chunks
CHECK (chunk_index >= 0)
CHECK (token_count > 0)
CHECK (length(embedding_model_ref) > 0)
```

---

## 10. Index Strategy

### 10.1 `knowledge.knowledge_bases`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_knowledge_bases` | `id` | UNIQUE B-tree (PK) | |
| `uq_kb_name` | `(organization_id, name)` | UNIQUE B-tree | |
| `idx_kb_org_status` | `(organization_id, status)` | B-tree | |
| `idx_kb_org_created` | `(organization_id, created_at DESC)` | B-tree | |

### 10.2 `knowledge.documents`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_documents` | `id` | UNIQUE B-tree (PK) | |
| `idx_doc_kb_status` | `(organization_id, knowledge_base_id, status)` | B-tree | |
| `idx_doc_current_version` | `current_version_id` | B-tree | `WHERE current_version_id IS NOT NULL` |

### 10.3 `knowledge.document_versions`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_document_versions` | `id` | UNIQUE B-tree (PK) | |
| `uq_dv_version_number` | `(document_id, version_number)` | UNIQUE B-tree | |
| `uq_dv_content_hash` | `(knowledge_base_id, content_hash)` | PARTIAL UNIQUE B-tree | `WHERE status NOT IN ('FAILED','GDPR_ERASED')` |
| `idx_dv_document_status` | `(document_id, status)` | B-tree | |
| `idx_dv_org` | `organization_id` | B-tree | RLS support |

### 10.4 `knowledge.ingestion_jobs`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_ingestion_jobs` | `id` | UNIQUE B-tree (PK) | |
| `idx_ij_docver` | `document_version_id` | B-tree | |
| `idx_ij_org_status` | `(organization_id, status)` | B-tree | |

### 10.5 `knowledge.document_chunks` (Critical)

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_document_chunks` | `(id, knowledge_base_id)` | UNIQUE B-tree (PK) | |
| `uq_chunk_position` | `(document_version_id, chunk_index, knowledge_base_id)` | UNIQUE B-tree | |
| `idx_dc_org_kb` | `(organization_id, knowledge_base_id)` | B-tree | Vector search pre-filter |
| `idx_dc_document_version` | `(document_version_id, chunk_index ASC)` | B-tree | Ordered chunk read |
| `idx_dc_tsvector` | `tsvector_content` | GIN | Full-text keyword search |
| `idx_dc_embedding_hnsw` | `embedding` | **HNSW** (cosine) | ANN vector search |

**HNSW parameters:** `m = 16, ef_construction = 64` — built `CONCURRENTLY` in separate migration 043.

---

## 11. Partitioning — LIST on `knowledge_base_id`

`knowledge.document_chunks` is partitioned LIST on `knowledge_base_id` (Phase 4I §25.15). One child partition per Knowledge Base. Created by `knowledge.create_kb_partition()` SECURITY DEFINER when a KB is created. DEFAULT safety partition catches overflow.

Other tables (`knowledge_bases`, `documents`, `document_versions`, `ingestion_jobs`) are not partitioned in V1.

---

## 12. RLS Architecture

Standard tenant policy applied to all five tables:

```sql
ALTER TABLE knowledge.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.<table> FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_<table>_tenant ON knowledge.<table>
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

**Append-only enforcement — `document_chunks`:**
```sql
GRANT SELECT, INSERT, DELETE ON knowledge.document_chunks TO app_api, app_worker;
REVOKE UPDATE ON knowledge.document_chunks FROM app_api, app_worker;
```

**No direct UPDATE on `document_versions` for application roles:**
```sql
GRANT SELECT, INSERT ON knowledge.document_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON knowledge.document_versions FROM app_api, app_worker;
-- All mutations flow through SECURITY DEFINER lifecycle functions
```

---

## 13. SECURITY DEFINER Lifecycle Functions

All functions: `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO app_api, app_worker, app_platform_admin`.

### 13.1 Immutability Triggers

```sql
-- KB embedding model immutability (INV-01, INV-09)
CREATE OR REPLACE FUNCTION knowledge.prevent_kb_model_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.embedding_model_ref IS DISTINCT FROM NEW.embedding_model_ref OR
     OLD.embedding_dimensions IS DISTINCT FROM NEW.embedding_dimensions THEN
    RAISE EXCEPTION
      'knowledge_bases.embedding_model_ref/dimensions are immutable. kb_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- Document version immutable field protection (INV-02)
-- CONTENT and IDENTITY fields cannot be modified by any operation.
-- LIFECYCLE fields (status, ingestion_completed_at) are modified only by SECURITY DEFINER functions.
-- GDPR exception: storage_ref and content_hash may be set to 'ERASED' through the GDPR function only.
CREATE OR REPLACE FUNCTION knowledge.prevent_docver_immutable_field_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- These fields are ALWAYS immutable — no exception, including GDPR
  IF OLD.document_id IS DISTINCT FROM NEW.document_id OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.mime_type IS DISTINCT FROM NEW.mime_type OR
     OLD.size_bytes IS DISTINCT FROM NEW.size_bytes OR
     OLD.created_at IS DISTINCT FROM NEW.created_at OR
     OLD.created_by IS DISTINCT FROM NEW.created_by THEN
    RAISE EXCEPTION
      'document_versions identity/content fields are immutable. version_id: %, '
      'Attempted mutation on always-immutable column.', OLD.id;
  END IF;
  -- storage_ref and content_hash: immutable unless being set to 'ERASED' (GDPR)
  IF (OLD.storage_ref IS DISTINCT FROM NEW.storage_ref AND NEW.storage_ref != 'ERASED') OR
     (OLD.content_hash IS DISTINCT FROM NEW.content_hash AND NEW.content_hash != 'ERASED') THEN
    RAISE EXCEPTION
      'document_versions.storage_ref and content_hash are immutable in normal operation. '
      'Only GDPR erasure (value=''ERASED'') is permitted. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- Ingestion job completion immutability (INV-06)
CREATE OR REPLACE FUNCTION knowledge.prevent_completed_job_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'READY' THEN
    RAISE EXCEPTION 'READY ingestion_jobs are immutable. job_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- tsvector auto-maintenance
CREATE OR REPLACE FUNCTION knowledge.update_chunk_tsvector()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.tsvector_content := to_tsvector('english', COALESCE(NEW.content, ''));
  RETURN NEW;
END;
$$;
```

### 13.2 `fn_docver_mark_ready()` — Mark Version READY After Ingestion

```sql
CREATE OR REPLACE FUNCTION knowledge.fn_docver_mark_ready(
  p_document_version_id UUID,
  p_organization_id     UUID,
  p_chunk_count         INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, organization, pg_temp
AS $$
BEGIN
  -- Validate version exists, belongs to tenant, and is in PENDING status
  IF NOT EXISTS (
    SELECT 1 FROM knowledge.document_versions
    WHERE id = p_document_version_id
      AND organization_id = p_organization_id
      AND status = 'PENDING'
  ) THEN
    RAISE EXCEPTION
      'fn_docver_mark_ready: version not found, not owned by tenant, or not in PENDING status. version_id: %',
      p_document_version_id;
  END IF;

  UPDATE knowledge.document_versions
  SET status               = 'READY',
      ingestion_completed_at = NOW(),
      chunk_count          = p_chunk_count
  WHERE id = p_document_version_id
    AND organization_id = p_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION knowledge.fn_docver_mark_ready(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_mark_ready(UUID, UUID, INTEGER)
  TO app_api, app_worker, app_platform_admin;
```

### 13.3 `fn_docver_publish()` — Publish a READY Version (BLOCKER 1 Fixed)

```sql
-- BLOCKER 1 FIX: precondition NOW includes AND document_id = p_document_id.
-- A READY version belonging to Document B must NEVER be publishable as
-- the current version of Document A (INV-12).

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
BEGIN
  -- BLOCKER 1 FIX: Verify the version belongs to THIS document, THIS tenant, and is READY.
  -- Without the document_id check, a READY version from Document B could be published
  -- as the current version of Document A — a critical aggregate-integrity violation (INV-12).
  IF NOT EXISTS (
    SELECT 1
    FROM knowledge.document_versions
    WHERE id             = p_new_version_id
      AND document_id    = p_document_id        -- INV-12: ownership check
      AND organization_id = p_organization_id
      AND status         = 'READY'
  ) THEN
    RAISE EXCEPTION
      'fn_docver_publish: version does not belong to document, tenant, or is not READY. '
      'document_id: %, version_id: %', p_document_id, p_new_version_id;
  END IF;

  -- Load the document's current version (may be NULL for first publish)
  SELECT current_version_id
  INTO v_old_version_id
  FROM knowledge.documents
  WHERE id = p_document_id
    AND organization_id = p_organization_id;  -- tenant ownership confirmed

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'fn_docver_publish: document not found or not owned by tenant. document_id: %',
      p_document_id;
  END IF;

  -- Supersede the previous current version if one exists
  IF v_old_version_id IS NOT NULL THEN
    UPDATE knowledge.document_versions
    SET status = 'SUPERSEDED'
    WHERE id = v_old_version_id
      AND organization_id = p_organization_id;
  END IF;

  -- Set new current version on the document
  UPDATE knowledge.documents
  SET current_version_id = p_new_version_id,
      status             = 'READY',
      updated_at         = NOW()
  WHERE id = p_document_id
    AND organization_id = p_organization_id;

  -- The new version's status remains 'READY' — it is now the current version
END;
$$;

REVOKE ALL ON FUNCTION knowledge.fn_docver_publish(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.fn_docver_publish(UUID, UUID, UUID)
  TO app_api, app_worker, app_platform_admin;
```

### 13.4 `create_kb_partition()` — Create Per-KB Chunk Partition

```sql
CREATE OR REPLACE FUNCTION knowledge.create_kb_partition(p_kb_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = knowledge, pg_temp
AS $$
DECLARE
  v_partition_name TEXT;
BEGIN
  v_partition_name := 'document_chunks_' || substring(replace(p_kb_id::text, '-', ''), 1, 8);
  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS knowledge.%I '
    'PARTITION OF knowledge.document_chunks '
    'FOR VALUES IN (%L)',
    v_partition_name, p_kb_id
  );
END;
$$;

REVOKE ALL ON FUNCTION knowledge.create_kb_partition(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION knowledge.create_kb_partition(UUID)
  TO app_api, app_worker, app_platform_admin;
```

---

## 14. Complete PostgreSQL DDL

### Migration 034 — Schema, Extensions, Functions

```sql
CREATE EXTENSION IF NOT EXISTS vector;
GRANT USAGE ON SCHEMA knowledge TO app_api, app_worker, app_readonly, app_platform_admin;

-- (All function definitions from §13 go here)
```

### Migration 035 — `knowledge_bases`

```sql
CREATE TABLE knowledge.knowledge_bases (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL,
  name                  TEXT          NOT NULL,
  description           TEXT          NULL,
  embedding_model_ref   TEXT          NOT NULL,
  embedding_dimensions  INTEGER       NOT NULL,
  chunking_strategy     JSONB         NOT NULL,
  retrieval_config      JSONB         NOT NULL DEFAULT '{}',
  index_version         INTEGER       NOT NULL DEFAULT 1,
  status                TEXT          NOT NULL DEFAULT 'ACTIVE',
  document_count        INTEGER       NOT NULL DEFAULT 0,
  created_by            UUID          NOT NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_knowledge_bases    PRIMARY KEY (id),
  CONSTRAINT chk_kb_status         CHECK (status IN ('ACTIVE','REINDEXING','DEGRADED','ARCHIVED')),
  CONSTRAINT chk_kb_dimensions_pos CHECK (embedding_dimensions > 0),
  CONSTRAINT chk_kb_doc_count_nn   CHECK (document_count >= 0),
  CONSTRAINT chk_kb_index_version  CHECK (index_version >= 1),
  CONSTRAINT chk_kb_name_len       CHECK (length(name) BETWEEN 1 AND 200)
);

CREATE UNIQUE INDEX uq_kb_name    ON knowledge.knowledge_bases (organization_id, name);
CREATE        INDEX idx_kb_org_st ON knowledge.knowledge_bases (organization_id, status);
CREATE        INDEX idx_kb_org_cr ON knowledge.knowledge_bases (organization_id, created_at DESC);

CREATE TRIGGER trg_kb_updated_at
  BEFORE UPDATE ON knowledge.knowledge_bases
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_kb_model_immutable
  BEFORE UPDATE ON knowledge.knowledge_bases
  FOR EACH ROW EXECUTE FUNCTION knowledge.prevent_kb_model_mutation();

ALTER TABLE knowledge.knowledge_bases ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.knowledge_bases FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_kb_tenant ON knowledge.knowledge_bases
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON knowledge.knowledge_bases TO app_api, app_worker;
```

### Migration 036 — `documents` and `document_versions`

```sql
CREATE TABLE knowledge.documents (
  id                UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID          NOT NULL,
  knowledge_base_id UUID          NOT NULL,
  source_type       TEXT          NOT NULL,
  original_filename TEXT          NULL,
  title             TEXT          NULL,
  status            TEXT          NOT NULL DEFAULT 'PENDING',
  current_version_id UUID         NULL,
  metadata          JSONB         NOT NULL DEFAULT '{}',
  deleted_at        TIMESTAMPTZ   NULL,
  created_by        UUID          NOT NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_documents        PRIMARY KEY (id),
  CONSTRAINT fk_doc_kb           FOREIGN KEY (knowledge_base_id)
    REFERENCES knowledge.knowledge_bases(id) ON DELETE RESTRICT,
  CONSTRAINT chk_doc_source_type CHECK (source_type IN
    ('PDF','DOCX','TXT','CSV','URL','FAQ','WEBSITE')),
  CONSTRAINT chk_doc_status      CHECK (status IN
    ('PENDING','PROCESSING','READY','FAILED','ARCHIVED','DELETED'))
);

COMMENT ON COLUMN knowledge.documents.current_version_id IS
  'Publication gate (INV-11): may only reference a READY version of this document (INV-12). '
  'Set by fn_docver_publish() only.';
COMMENT ON COLUMN knowledge.documents.original_filename IS 'pii:potential';

CREATE INDEX idx_doc_kb_status   ON knowledge.documents (organization_id, knowledge_base_id, status);
CREATE INDEX idx_doc_cur_version ON knowledge.documents (current_version_id)
  WHERE current_version_id IS NOT NULL;

CREATE TRIGGER trg_doc_updated_at
  BEFORE UPDATE ON knowledge.documents
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE knowledge.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.documents FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_doc_tenant ON knowledge.documents
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON knowledge.documents TO app_api, app_worker;


-- document_versions: content/identity immutable; lifecycle controlled by SECURITY DEFINER
CREATE TABLE knowledge.document_versions (
  id                     UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID          NOT NULL,
  document_id            UUID          NOT NULL,
  version_number         INTEGER       NOT NULL,
  storage_ref            TEXT          NOT NULL,   -- pii:potential; 'ERASED' on GDPR
  content_hash           CHAR(64)      NOT NULL,   -- 'ERASED' on GDPR
  mime_type              TEXT          NOT NULL,
  size_bytes             BIGINT        NOT NULL,
  status                 TEXT          NOT NULL DEFAULT 'PENDING',
  ingestion_completed_at TIMESTAMPTZ   NULL,
  chunk_count            INTEGER       NULL,
  created_by             UUID          NOT NULL,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_document_versions   PRIMARY KEY (id),
  CONSTRAINT fk_dv_document         FOREIGN KEY (document_id)
    REFERENCES knowledge.documents(id) ON DELETE CASCADE,
  CONSTRAINT uq_dv_version_number   UNIQUE (document_id, version_number),
  CONSTRAINT chk_dv_status          CHECK (status IN
    ('PENDING','READY','SUPERSEDED','FAILED','GDPR_ERASED')),
  CONSTRAINT chk_dv_version_number  CHECK (version_number >= 1),
  CONSTRAINT chk_dv_size_bytes      CHECK (size_bytes > 0),
  CONSTRAINT chk_dv_chunk_count     CHECK (chunk_count IS NULL OR chunk_count >= 0)
);

-- Dedup: no two active versions in same KB may have same content
CREATE UNIQUE INDEX uq_dv_content_hash
  ON knowledge.document_versions (knowledge_base_id, content_hash)
  WHERE status NOT IN ('FAILED','GDPR_ERASED');

CREATE INDEX idx_dv_document_status ON knowledge.document_versions (document_id, status);
CREATE INDEX idx_dv_org             ON knowledge.document_versions (organization_id);

COMMENT ON COLUMN knowledge.document_versions.storage_ref   IS 'pii:potential — S3 path; set to ERASED on GDPR erasure';
COMMENT ON COLUMN knowledge.document_versions.content_hash  IS 'Set to ERASED on GDPR erasure';
COMMENT ON TABLE  knowledge.document_versions IS
  'Document version CONTENT and IDENTITY are immutable after creation (INV-02). '
  'Lifecycle state (status, ingestion_completed_at) is mutable only through '
  'controlled SECURITY DEFINER lifecycle operations. GDPR erasure is an explicit '
  'compliance exception.';

-- Immutability trigger (INV-02)
CREATE TRIGGER trg_dv_immutable_fields
  BEFORE UPDATE ON knowledge.document_versions
  FOR EACH ROW EXECUTE FUNCTION knowledge.prevent_docver_immutable_field_mutation();

-- No set_updated_at trigger: document_versions has no updated_at column
-- (lifecycle mutations tracked through status + ingestion_completed_at)

ALTER TABLE knowledge.document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.document_versions FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_dv_tenant ON knowledge.document_versions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- No direct UPDATE or DELETE for application roles (INV-02)
GRANT SELECT, INSERT ON knowledge.document_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON knowledge.document_versions FROM app_api, app_worker;
```

### Migration 037 — `ingestion_jobs`

```sql
CREATE TABLE knowledge.ingestion_jobs (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID          NOT NULL,
  document_version_id UUID          NOT NULL,
  knowledge_base_id   UUID          NOT NULL,
  status              TEXT          NOT NULL DEFAULT 'PENDING',
  current_stage       TEXT          NULL,
  attempt_count       INTEGER       NOT NULL DEFAULT 1,
  parsed_text_ref     TEXT          NULL,
  chunks_produced     INTEGER       NULL,
  embeddings_produced INTEGER       NULL,
  error_message       TEXT          NULL,
  started_at          TIMESTAMPTZ   NULL,
  completed_at        TIMESTAMPTZ   NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ingestion_jobs   PRIMARY KEY (id),
  CONSTRAINT fk_ij_docver        FOREIGN KEY (document_version_id)
    REFERENCES knowledge.document_versions(id) ON DELETE CASCADE,
  CONSTRAINT chk_ij_status       CHECK (status IN
    ('PENDING','EXTRACTING','CHUNKING','EMBEDDING','INDEXING','READY','FAILED','CANCELLED')),
  CONSTRAINT chk_ij_attempts     CHECK (attempt_count BETWEEN 1 AND 3),
  CONSTRAINT chk_ij_chunks_nn    CHECK (chunks_produced IS NULL OR chunks_produced >= 0),
  CONSTRAINT chk_ij_emb_nn       CHECK (embeddings_produced IS NULL OR embeddings_produced >= 0)
);

CREATE INDEX idx_ij_docver     ON knowledge.ingestion_jobs (document_version_id);
CREATE INDEX idx_ij_org_status ON knowledge.ingestion_jobs (organization_id, status);

CREATE TRIGGER trg_ij_updated_at
  BEFORE UPDATE ON knowledge.ingestion_jobs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_ij_ready_immutable
  BEFORE UPDATE ON knowledge.ingestion_jobs
  FOR EACH ROW EXECUTE FUNCTION knowledge.prevent_completed_job_mutation();

ALTER TABLE knowledge.ingestion_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.ingestion_jobs FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_ij_tenant ON knowledge.ingestion_jobs
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON knowledge.ingestion_jobs TO app_api, app_worker;
```

### Migration 038 — `document_chunks` (Partitioned)

```sql
CREATE TABLE knowledge.document_chunks (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  knowledge_base_id     UUID          NOT NULL,   -- PARTITION KEY
  organization_id       UUID          NOT NULL,
  document_id           UUID          NOT NULL,
  document_version_id   UUID          NOT NULL,
  chunk_index           INTEGER       NOT NULL,
  content               TEXT          NOT NULL,   -- pii:potential
  content_hash          CHAR(64)      NOT NULL,
  embedding             vector(1536)  NOT NULL,   -- pii:potential (derived)
  tsvector_content      TSVECTOR      NOT NULL,
  token_count           INTEGER       NOT NULL,
  page_number           INTEGER       NULL,
  section_heading       TEXT          NULL,
  source_location       TEXT          NULL,
  embedding_model_ref   TEXT          NOT NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_document_chunks     PRIMARY KEY (id, knowledge_base_id),
  CONSTRAINT uq_chunk_position      UNIQUE (document_version_id, chunk_index, knowledge_base_id),
  CONSTRAINT chk_dc_chunk_index_nn  CHECK (chunk_index >= 0),
  CONSTRAINT chk_dc_token_count_pos CHECK (token_count > 0),
  CONSTRAINT chk_dc_model_ref_len   CHECK (length(embedding_model_ref) > 0)
) PARTITION BY LIST (knowledge_base_id);

COMMENT ON COLUMN knowledge.document_chunks.content     IS 'pii:potential — document text fragment';
COMMENT ON COLUMN knowledge.document_chunks.embedding   IS 'pii:potential (derived) — 1536-dim cosine vector';

CREATE INDEX idx_dc_org_kb
  ON knowledge.document_chunks (organization_id, knowledge_base_id);
CREATE INDEX idx_dc_docver
  ON knowledge.document_chunks (document_version_id, chunk_index ASC);
CREATE INDEX idx_dc_tsvector
  ON knowledge.document_chunks USING GIN (tsvector_content);

CREATE TRIGGER trg_dc_tsvector
  BEFORE INSERT ON knowledge.document_chunks
  FOR EACH ROW EXECUTE FUNCTION knowledge.update_chunk_tsvector();

ALTER TABLE knowledge.document_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge.document_chunks FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_dc_tenant ON knowledge.document_chunks
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, DELETE ON knowledge.document_chunks TO app_api, app_worker;
REVOKE UPDATE ON knowledge.document_chunks FROM app_api, app_worker;

-- DEFAULT partition (safety net)
CREATE TABLE knowledge.document_chunks_default
  PARTITION OF knowledge.document_chunks DEFAULT;
```

### Migration 043 — HNSW Index (CONCURRENTLY)

```sql
-- Must run with transaction_per_migration = False (cannot be in a transaction block)
CREATE INDEX CONCURRENTLY idx_dc_embedding_hnsw
  ON knowledge.document_chunks
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

### Migration 044 — Grants Finalization

```sql
GRANT SELECT ON knowledge.knowledge_bases    TO app_readonly;
GRANT SELECT ON knowledge.documents          TO app_readonly;
GRANT SELECT ON knowledge.document_versions  TO app_readonly;
GRANT SELECT ON knowledge.ingestion_jobs     TO app_readonly;
GRANT SELECT ON knowledge.document_chunks    TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA knowledge
  TO app_platform_admin;
```

---

## 15. Query Patterns

### QP-01: Create Knowledge Base (with Partition)

```sql
-- SET LOCAL app.tenant_id = $org_id
INSERT INTO knowledge.knowledge_bases (...) VALUES (...);
SELECT knowledge.create_kb_partition($kb_id);
-- Both in one transaction
```

### QP-02: Upload Document and Create First Version

```sql
-- Step 1: Insert Document row
INSERT INTO knowledge.documents (id, organization_id, knowledge_base_id, source_type,
  original_filename, title, status, metadata, created_by)
VALUES ($doc_id, $org_id, $kb_id, $source_type, $filename, $title, 'PENDING', $meta, $user_id);

-- Step 2: Insert DocumentVersion row
INSERT INTO knowledge.document_versions (id, organization_id, document_id, version_number,
  storage_ref, content_hash, mime_type, size_bytes, status, created_by)
VALUES ($ver_id, $org_id, $doc_id, 1,
  'org/' || $org_id || '/knowledge/' || $kb_id || '/' || $doc_id || '.' || $ext,
  $sha256, $mime_type, $size_bytes, 'PENDING', $user_id);
```

### QP-03: Mark Version READY (After Ingestion Completes)

```sql
-- Via SECURITY DEFINER function — no direct UPDATE
SELECT knowledge.fn_docver_mark_ready($version_id, $org_id, $chunk_count);
```

### QP-04: Publish a READY Version as Current

```sql
-- Via SECURITY DEFINER function — validates INV-11 and INV-12
-- BLOCKER 1 FIX: fn_docver_publish verifies document_id = p_document_id
SELECT knowledge.fn_docver_publish($doc_id, $new_version_id, $org_id);
```

### QP-05: Create Ingestion Job and Claim Work

```sql
INSERT INTO knowledge.ingestion_jobs (id, organization_id, document_version_id, knowledge_base_id)
VALUES ($id, $org_id, $ver_id, $kb_id)
ON CONFLICT DO NOTHING;

UPDATE knowledge.ingestion_jobs
SET status = 'EXTRACTING', current_stage = 'EXTRACTING', started_at = NOW(), updated_at = NOW()
WHERE id = (
  SELECT id FROM knowledge.ingestion_jobs
  WHERE organization_id = organization.current_tenant_id()
    AND status = 'PENDING'
  ORDER BY created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED
)
RETURNING id, document_version_id, knowledge_base_id;
```

### QP-06: Delete / GDPR Erase Document

```sql
-- Step 1: Remove chunks for the document's versions
DELETE FROM knowledge.document_chunks
WHERE document_id = $doc_id
  AND knowledge_base_id = $kb_id
  AND organization_id = organization.current_tenant_id();

-- Step 2: GDPR-erase the version content references
-- (Via SECURITY DEFINER GDPR function — not shown; it sets storage_ref='ERASED',
--  content_hash='ERASED', status='GDPR_ERASED')

-- Step 3: Mark document as DELETED, clear current_version_id
UPDATE knowledge.documents
SET status = 'DELETED', current_version_id = NULL,
    original_filename = NULL, deleted_at = NOW(), updated_at = NOW()
WHERE id = $doc_id
  AND organization_id = organization.current_tenant_id();

-- S3 deletion: separate application ObjectStorePort call
```

### QP-07: Retrieve a Specific Published Version's Chunks

```sql
-- QP-07: Access published version chunks by explicit version ID
SELECT dc.id, dc.chunk_index, dc.content, dc.page_number, dc.section_heading, dc.source_location
FROM knowledge.document_chunks dc
JOIN knowledge.document_versions dv ON dv.id = dc.document_version_id
  AND dv.organization_id = organization.current_tenant_id()
  AND dv.status = 'READY'                -- only READY versions
WHERE dc.organization_id = organization.current_tenant_id()
  AND dc.document_version_id = $version_id
  AND dc.knowledge_base_id = $kb_id
ORDER BY dc.chunk_index ASC;
```

### QP-08: Retrieve Only Current Published Content (Publication Gate — INV-11)

```sql
-- QP-08: Vector search restricted to CURRENT PUBLISHED versions only
-- READY-but-not-current versions are intentionally excluded.
-- d.current_version_id = dv.id ensures only the active published version is searched.

SELECT
  dc.id AS chunk_id,
  dc.content,
  dc.page_number,
  dc.section_heading,
  dc.source_location,
  dc.token_count,
  d.title   AS document_title,
  dv.id     AS version_id,
  1 - (dc.embedding <=> $query_embedding::vector) AS similarity_score
FROM knowledge.document_chunks dc
JOIN knowledge.document_versions dv
  ON dv.id = dc.document_version_id
  AND dv.organization_id = organization.current_tenant_id()
  AND dv.status = 'READY'
JOIN knowledge.documents d
  ON d.id = dv.document_id
  AND d.organization_id = organization.current_tenant_id()
  AND d.current_version_id = dv.id    -- publication gate: only CURRENT versions (INV-11)
  AND d.deleted_at IS NULL
WHERE dc.organization_id = organization.current_tenant_id()  -- RLS + explicit filter
  AND dc.knowledge_base_id = ANY($kb_ids::uuid[])
ORDER BY dc.embedding <=> $query_embedding::vector
LIMIT $top_k * 2;
-- RLS: organization_id = current_tenant_id() ✓
-- Index: idx_dc_embedding_hnsw (HNSW); pre-filtered by idx_dc_org_kb
```

### QP-09: Full-Text Search (Second Leg for Hybrid RRF)

```sql
SELECT
  dc.id AS chunk_id,
  dc.content,
  ts_rank(dc.tsvector_content, plainto_tsquery('english', $query_text)) AS keyword_score
FROM knowledge.document_chunks dc
JOIN knowledge.document_versions dv
  ON dv.id = dc.document_version_id
  AND dv.organization_id = organization.current_tenant_id()
  AND dv.status = 'READY'
JOIN knowledge.documents d
  ON d.id = dv.document_id
  AND d.current_version_id = dv.id    -- publication gate
  AND d.deleted_at IS NULL
WHERE dc.organization_id = organization.current_tenant_id()
  AND dc.knowledge_base_id = ANY($kb_ids::uuid[])
  AND dc.tsvector_content @@ plainto_tsquery('english', $query_text)
ORDER BY keyword_score DESC
LIMIT $top_k * 2;
-- Index: idx_dc_tsvector (GIN)
```

---

## 16. Migration Plan

```
Phase 5E migrations (027–033)
        ↓
034_knowledge_schema_extensions_functions
    down_revision = '033_campaign_grants_finalize'
    purpose: pgvector extension; GRANT USAGE; all trigger functions;
             fn_docver_mark_ready(), fn_docver_publish(), create_kb_partition()
             SECURITY DEFINER functions with REVOKE ALL FROM PUBLIC

035_knowledge_bases
    down_revision = '034_knowledge_schema_extensions_functions'
    purpose: knowledge.knowledge_bases, immutability trigger, indexes, RLS, grants

036_knowledge_documents_and_versions
    down_revision = '035_knowledge_bases'
    purpose: knowledge.documents, knowledge.document_versions,
             FK (documents→knowledge_bases RESTRICT),
             FK (document_versions→documents CASCADE),
             immutability trigger (INV-02) on document_versions,
             REVOKE UPDATE DELETE on document_versions from app roles,
             indexes, RLS, grants

037_knowledge_ingestion_jobs
    down_revision = '036_knowledge_documents_and_versions'
    purpose: knowledge.ingestion_jobs,
             FK (ingestion_jobs→document_versions CASCADE),
             READY immutability trigger, indexes, RLS, grants

038_knowledge_document_chunks_partitioned
    down_revision = '037_knowledge_ingestion_jobs'
    purpose: knowledge.document_chunks (LIST partition, DEFAULT partition),
             B-tree and GIN indexes, tsvector trigger,
             REVOKE UPDATE from app roles, RLS, grants

043_knowledge_hnsw_index
    down_revision = '038_knowledge_document_chunks_partitioned'
    purpose: CREATE INDEX CONCURRENTLY idx_dc_embedding_hnsw
             (Alembic transaction_per_migration = False)

044_knowledge_grants_finalize
    down_revision = '043_knowledge_hnsw_index'
    purpose: app_readonly grants; app_platform_admin full access
```

**Note on migration numbering:** Migrations 039–042 are reserved for Phase 5G (Workflow/Memory). Phase 5F uses 034–038, 043, 044 to align with the Phase 5G dependency chain.

---

## 17. ADRs

### ADR-5F-001: KnowledgeBase Aggregate Model

**Decision:** `knowledge_bases` maps directly to the Phase 4E `KnowledgeBase` aggregate. `chunking_strategy` and `retrieval_config` are JSONB (bounded, always read whole with KB). `EmbeddingModelRef` and `EmbeddingDimensions` are immutable after creation.

### ADR-5F-002: Document Version Content/Identity Immutability (BLOCKER 2 corrected)

**Decision:** Document version **content and identity** are immutable after creation. Lifecycle **state** is mutable only through controlled SECURITY DEFINER lifecycle operations (`fn_docver_mark_ready`, `fn_docver_publish`, and the GDPR erasure function). Normal application and worker roles cannot directly UPDATE the `document_versions` table. GDPR erasure is an explicit compliance exception that may set `storage_ref` and `content_hash` to `'ERASED'`.

**Rationale:** Document versions serve as the durable publication record. Their content references (`storage_ref`, `content_hash`) and identity fields (`document_id`, `version_number`, etc.) must not change to preserve audit integrity and citation traceability. Lifecycle fields must change (PENDING → READY → SUPERSEDED) to enable the publication workflow. The SECURITY DEFINER approach reconciles both requirements: no unconstrained UPDATE access, but controlled lifecycle progression.

**Immutable fields (always):** `document_id`, `version_number`, `mime_type`, `size_bytes`, `created_at`, `created_by`.

**Immutable in normal operation, ERASED on GDPR only:** `storage_ref`, `content_hash`.

**Lifecycle-controlled fields:** `status`, `ingestion_completed_at` — changed only by `fn_docver_mark_ready()`, `fn_docver_publish()`, and the GDPR erasure function.

### ADR-5F-003: Object Storage Boundary

**Decision:** document binary content is stored in S3. PostgreSQL stores only `storage_ref`, `content_hash`, and metadata. No `BYTEA` column. S3 deletion is a separate application-layer operation.

### ADR-5F-004: Separate State Machines — IngestionJob vs. DocumentVersion (corrected)

**Decision:** `ingestion_jobs` and `document_versions` have separate, distinct state machines:

| | `ingestion_jobs` | `document_versions` |
|---|---|---|
| Purpose | Worker execution state | Durable version lifecycle / publication state |
| Statuses | `PENDING \| EXTRACTING \| CHUNKING \| EMBEDDING \| INDEXING \| READY \| FAILED \| CANCELLED` | `PENDING \| READY \| SUPERSEDED \| FAILED \| GDPR_ERASED` |
| Mutability | Mutable per-worker via direct UPDATE | Controlled by SECURITY DEFINER only |

When an ingestion job reaches `READY`, it calls `fn_docver_mark_ready()` to advance the document version's status. These are synchronized but independent state machines.

### ADR-5F-005: Chunk Immutability (INSERT/DELETE Only)

**Decision:** `REVOKE UPDATE ON document_chunks FROM app_api, app_worker`. Reprocessing DELETEs old version's chunks and INSERTs new version's chunks.

### ADR-5F-006: Chunks and Embeddings Co-Located

**Decision:** `knowledge.document_chunks` contains both text content and `vector(1536)`. No separate embeddings table. Per Phase 4E §18.

### ADR-5F-007: Single Embedding Model Strategy

**Decision:** `vector(1536)`, OpenAI `text-embedding-3-large` @ 1536 dimensions (Phase 4I OQ-FINAL-03). KB's `embedding_model_ref` is immutable.

### ADR-5F-008: HNSW Index with Cosine Distance

**Decision:** `USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64)`. Built `CONCURRENTLY` in migration 043.

### ADR-5F-009: Vector Search Tenant Isolation — RLS + Explicit Filter

**Decision:** All vector queries include `AND organization_id = organization.current_tenant_id()` in addition to RLS.

### ADR-5F-010: LIST Partitioning on `knowledge_base_id`

**Decision:** `document_chunks` partitioned LIST on `knowledge_base_id`. Per Phase 4I §25.15.

### ADR-5F-011: GDPR Deletion Propagation

**Decision:** GDPR erasure: (1) DELETE chunks, (2) set version `storage_ref = 'ERASED'`, `content_hash = 'ERASED'`, `status = 'GDPR_ERASED'` via dedicated function, (3) set document `status = 'DELETED'`, `current_version_id = NULL`, clear PII fields. Row retained as tombstone. S3 deletion is separate.

### ADR-5F-012: Knowledge ↔ Agent Boundary — No Coupling Table

**Decision:** KB IDs stored in `voice.agent_versions.snapshot_json`. No coupling table.

---

## 18. Security and Test Matrix

### 18.1 Security Matrix

| Scenario | Mechanism | Expected Result |
|---|---|---|
| Tenant A reads Tenant B's KB | RLS | 0 rows |
| Tenant A reads Tenant B's document versions | RLS | 0 rows |
| Tenant A vector search into Tenant B's KB | RLS + explicit `organization_id` filter | 0 rows |
| Tenant A inserts chunks into Tenant B's KB | RLS WITH CHECK | Rejected |
| Missing tenant context | `current_tenant_id() = NULL` | 0 rows all tables |
| KB embedding model changed after creation | Immutability trigger | RAISE EXCEPTION |
| READY ingestion job UPDATE | Immutability trigger | RAISE EXCEPTION |
| Retrieval returns non-current READY version | `d.current_version_id = dv.id` gate (QP-08) | Excluded |
| GDPR-erased chunk in retrieval | DELETE removes all chunks | Returns 0 chunks |
| Embedding model mismatch | Application-layer validation | Query rejected pre-SQL |
| app_api directly UPDATEs document_versions | REVOKE UPDATE | Permission denied |

### 18.2 Immutability Test Matrix

```text
Immutable field protection (document_versions):
    UPDATE document_id     → RAISE EXCEPTION (trigger)
    UPDATE version_number  → RAISE EXCEPTION (trigger)
    UPDATE mime_type       → RAISE EXCEPTION (trigger)
    UPDATE size_bytes      → RAISE EXCEPTION (trigger)
    UPDATE created_at      → RAISE EXCEPTION (trigger)
    UPDATE created_by      → RAISE EXCEPTION (trigger)
    UPDATE storage_ref     → RAISE EXCEPTION (trigger) [unless new value = 'ERASED']
    UPDATE content_hash    → RAISE EXCEPTION (trigger) [unless new value = 'ERASED']

Controlled lifecycle (via SECURITY DEFINER functions only):
    PENDING → READY via fn_docver_mark_ready()    → allowed
    READY → SUPERSEDED via fn_docver_publish()    → allowed (old version superseded)
    READY → current version via fn_docver_publish → allowed (new version becomes current)
    READY/SUPERSEDED → GDPR_ERASED via GDPR fn   → allowed (compliance exception)

Cross-document publication (BLOCKER 1 INV-12):
    Document A version A1 — status = READY
    Document B version B1 — status = READY
    Attempt: fn_docver_publish(document_id=A, new_version_id=B1, org_id=OrgX)
    Expected: RAISE EXCEPTION — B1.document_id != A → precondition fails
    Document A.current_version_id → unchanged
    Version B1 → still associated with Document B, status = READY

Cross-document publication within same tenant → MUST fail.

Invalid lifecycle transitions:
    SUPERSEDED → READY → rejected by status check in fn_docver_mark_ready
    GDPR_ERASED → READY → rejected by fn_docver_mark_ready precondition
    PENDING → SUPERSEDED → cannot occur (fn_docver_publish requires READY)
```

---

## 19. Carry-Forward Hardening Items

| Item | Description | Target Phase |
|---|---|---|
| **HNSW parameter tuning** | Validate `m=16, ef_construction=64` against real volumes before launch | Phase 22 |
| **GIN index on `documents.metadata`** | Add if metadata filtering is frequent in retrieval | Phase 9 |
| **Hybrid search language config** | `tsvector_content` defaults to `'english'`; Tamil/multilingual requires language-aware trigger | Phase 9 |
| **`parsed_text_ref` S3 cleanup** | Intermediate parsed text must be deleted after ingestion READY | Phase 9 |
| **Reindexing pattern** | `TriggerReindex` DB pattern (mark REINDEXING, re-embed all INDEXED docs, swap index_version) | Phase 9 |
| **Duplicate active suppression** | `(organization_id, phone_e164, scope, channel) WHERE status = 'ACTIVE'` unique partial index on `contact_suppressions` | Phase 9 |
| **Multi-model future extension** | `vector(1536)` is a blocker if a second model with different dimensions is needed | Future phase |
| **GDPR erasure SECURITY DEFINER function** | Dedicated `fn_docver_gdpr_erase()` function (sets `storage_ref='ERASED'`, `content_hash='ERASED'`, `status='GDPR_ERASED'`) not fully specified here — carry to Phase 9 | Phase 9 |
| **Conversation Memory tables** | `SessionMemory` and `CustomerMemory` → Phase 5G | Phase 5G |

---

## 20. Final Consistency Review

### Phase 5A ✅
UUIDv7 PKs; no cross-schema FK; TEXT+CHECK for status; no monetary columns; JSONB justified; PII tagged; LIST partitioning per Phase 4I §25.15; REVOKE UPDATE on document_chunks and document_versions; 7 migrations including CONCURRENTLY HNSW.

### Phase 5B ✅
`organization.current_tenant_id()`, `gen_uuid_v7()`, `set_updated_at()` throughout. ENABLE + FORCE ROW LEVEL SECURITY on all 5 tables. SECURITY DEFINER functions: REVOKE ALL FROM PUBLIC + GRANT EXECUTE to approved roles.

### Phase 5C ✅
Voice owns calls, conversations, agents, agent versions. Knowledge references agents via logical UUIDs in `agent_versions.snapshot_json`. No Knowledge table references Voice.

### Phase 5D ✅
CRM owns contacts, consent, suppression. Knowledge does not store CRM data.

### Phase 5E ✅
Campaign owns campaigns, call jobs. Knowledge consumed via `KnowledgeSearchPort` only.

### DDD Consistency ✅
All Phase 4E Knowledge aggregates mapped. No tables added outside DDD scope.

### Phase 4I OQ-FINAL-03 ✅
`vector(1536)`, HNSW cosine, `openai:text-embedding-3-large:1536`.

### Blocker 1 ✅
`fn_docver_publish()` now verifies `document_id = p_document_id` in precondition. INV-12 added. Cross-document publication test added to test matrix.

### Blocker 2 ✅
"Document versions immutable" replaced with precise content/identity vs. lifecycle distinction. INV-02 rewritten. ADR-5F-002 corrected. ADR-5F-004 clarified with two separate state machines. Test matrix expanded with controlled lifecycle and invalid transition cases.

---

```
PHASE 5F STATUS

Knowledge Base:
APPROVED

Documents:
APPROVED

Document Versioning:
APPROVED (document_versions table; controlled lifecycle via SECURITY DEFINER;
          INV-02 content/identity immutable; lifecycle state controlled)

Ingestion:
APPROVED (separate state machine from document_versions per ADR-5F-004)

Chunks:
APPROVED (INSERT/DELETE only; REVOKE UPDATE)

Embeddings:
APPROVED (vector(1536) co-located; Phase 4E §18)

pgvector:
APPROVED (HNSW m=16 ef_construction=64, cosine distance, Phase 4I OQ-FINAL-03)

Vector Tenant Isolation:
APPROVED (RLS + explicit org filter + LIST partition isolation)

Publication / Version Consistency:
APPROVED (d.current_version_id = dv.id gate in QP-08; INV-11; INV-12)

GDPR / PII:
APPROVED (chunk DELETE + version content ERASED + document tombstone)

RLS:
APPROVED

Security:
APPROVED

DDL:
APPROVED

Indexes:
APPROVED (HNSW CONCURRENTLY in migration 043; GIN for hybrid search)

Migration Plan:
APPROVED (034–038, 043, 044)

Overall:
PHASE 5G READY
```

All blockers resolved. INV-12 (document-version ownership) added and enforced in `fn_docver_publish()`. INV-02 (document version immutability) corrected to distinguish content/identity immutability from lifecycle state control. Both ADRs updated. Test matrix expanded with cross-document publication test and immutable field protection cases.

---

## Controlled Amendment — Phase 5L (2026-08-24)

Six migrations (`078_5F1.sql` through `084_5F7.sql`) close all six of
6F's blocking dependencies against this schema, reconciling the physical
schema with both this document's own design intent and the 4E DDD
invariants it derives from. Each item below was a genuine gap between
the executed `034_5F.sql`-`044_5F.sql` and either this document's own
prose or 4E's frozen invariants — not a reinterpretation of either.

- **DEP-6F-16** (`078_5F1.sql`): `fn_docver_publish()` now requires
  `documents.status <> 'DELETED'`, closing the publish/delete race
  (§28 Race #9). Additionally, `documents.current_version_id` (INV-12)
  — previously updatable by any `app_api`/`app_worker` `UPDATE` despite
  its "set by `fn_docver_publish()` only" column comment — is now
  column-privilege-locked; only the SECURITY DEFINER functions
  (`fn_docver_publish`, `fn_docver_rollback`, `fn_document_gdpr_delete`)
  can write it.
- **DEP-6F-01** (`079_5F2.sql`): `fn_docver_rollback()` re-activates a
  `SUPERSEDED` version (Interpretation A of FR-RAG-004 — document-level
  historical rollback, grounded in 4E DDD evidence: Knowledge/RAG has no
  `KnowledgeBaseVersion` aggregate, and Prompt Management's existing
  `rollback(environment, target_version)` pointer-swap pattern is the
  closest already-implemented analog, applied here to Documents instead
  of inventing a new KB-snapshot entity).
- **DEP-6F-09** (`080_5F3.sql`): `fn_docver_mark_failed()`, `PENDING`→
  `FAILED` only, idempotent, rejecting all other source states.
- **DEP-6F-15** (`081_5F4.sql`): `fn_docver_gdpr_erase()` (per-version,
  idempotent, deletes chunks + erases `storage_ref`/`content_hash` under
  the existing `prevent_docver_immutable_field_mutation()` carve-out) and
  `fn_document_gdpr_delete()` (document-level orchestration, matching
  §23.4's 4-step contract for steps 1-3; S3 deletion, step 4, remains
  external/app-layer).
- **DEP-6F-14** (`082_5F5.sql`): `document_versions.knowledge_base_id`
  (server-derived via a `BEFORE INSERT` trigger — never trusts a
  client-supplied value — backfilled, FK-enforced) and
  `uq_dv_content_hash_kb (knowledge_base_id, content_hash)` replacing
  the document-scoped `uq_dv_content_hash`, correctly implementing 4E's
  `NoDuplicateDocumentContent` policy ("same hash in the same Knowledge
  Base is rejected") instead of the executed-but-narrower document scope.
- **DEP-6F-02** (`083_5F6.sql`): derived chunk/index generations —
  `document_chunks.index_generation` plus `fn_kb_reindex_begin/complete/
  fail/cleanup_old_generations()`. Reuses the existing `index_version`
  column and `REINDEXING` status (both previously unused) rather than
  adding a new KB column. Old-generation chunks remain queryable
  throughout a rebuild, satisfying 4E invariant 3; atomic cutover; a
  failed rebuild preserves the old generation and cleans up only its own
  partial rows; a second concurrent `begin` is blocked (advisory + row
  lock), live-tested with two genuinely concurrent sessions.
- **Multilingual FTS** (`084_5F7.sql`, closing the §19 carry-forward):
  `content_language` on `documents`/`document_chunks`
  (`en`/`ta`/`te`/`hi`), `update_chunk_tsvector()` now selects `'english'`
  for `en` and `'simple'` (tokenize + lowercase, no stemming — the safe
  fallback for languages without a stock PostgreSQL dictionary) for
  `ta`/`te`/`hi` and Tamil-English code-mixed content. Live-tested
  across all five cases; no keyword loss or corruption in any of them.

All six are live-validated against a genuinely fresh PostgreSQL database
(functional correctness, idempotency, tenant isolation, and — where
applicable — real concurrency races). See
`docs/phase-05-database-design/5L-Global-Database-Reconciliation/
5L-Global-Database-Reconciliation.md` for the full report and captured
evidence. `docs/phase-06-api-design/6F-Knowledge-RAG-APIs.md`'s own
dependency-register rows are updated separately; its freeze-eligibility
verdict is not changed by this amendment.
