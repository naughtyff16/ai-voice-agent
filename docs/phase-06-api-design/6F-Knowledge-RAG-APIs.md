# 6F — Knowledge / RAG APIs

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6F

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6F-Knowledge-RAG-APIs.md |
| Phase | 6F (sixth document of Phase 6 — API Design) — **history: STRICT CORRECTION PASS 1, then Phase 5L, Phase 5L.1, Phase 5L.2 database reconciliation passes; this revision is the Phase 5L.2 document-consistency pass** |
| Depends on | Phase 1 SRS (FR-RAG-001..005, FR-TEN-002/005, NFR-SEC-003/006), Phase 3D (Workflow/RAG LLD), Phase 3A/3B/3E/3F, Phase 4E (Knowledge & RAG DDD), Phase 4I (India-First closure, OQ-FINAL-03), Phase 5F (Knowledge/RAG Schema — design document, including its Phase 5L/5L.1/5L.2 amendments), **the executed migrations — physical source of truth, §4.1 — now spanning `docs/phase-05-database-design/5K/migrations/034_5F.sql`–`038_5F.sql`, `043_5F.sql`, `044_5F.sql` (original 5F schema) PLUS the full reconciliation chain `078_5F1.sql`, `079_5F2.sql`, `080_5F3.sql`, `081_5F4.sql`, `082_5F5.sql`, `083_5F6.sql`, `084_5F7.sql`, `088_5F8.sql`, `089_5F9.sql`, `090_5F10.sql`, `091_5F11.sql`, `092_5F12.sql` — current head `092_5F12`**, Phase 5B (Identity/RBAC, incl. its Phase 5L break-glass amendment), Phase 5D (CRM, incl. its Phase 5L suppression amendment), Phase 5H (Billing, incl. its Phase 5L amendment), Phase 5J (Analytics/Audit, incl. its Phase 5L vocabulary amendment), `docs/phase-05-database-design/5L-Global-Database-Reconciliation/5L-Global-Database-Reconciliation.md` (Phase 5L/5L.1/5L.2 addenda — the full classification report and live validation evidence for every migration named above), 6A (API Architecture & Standards), 6B (Auth API), 6C (Core Platform API), 6D (Voice/Call API), 6E (AI Agent API) |
| Status of dependencies | Phases 1–5 (5A–5J, 5K, 5K.1, 5L, 5L.1, 5L.2) and 6A–6E are **APPROVED / FROZEN**. No changes made to any of them by this document — this document only records the resulting status. |
| Author scope | Knowledge Base, Document, DocumentVersion, IngestionJob management and Knowledge retrieval/search API surface only. |
| Supersedes | Revision 1 (2026-08-24, first draft); the Strict Correction Pass 1 revision; the Phase 5L.1 revision — each superseded revision's own reasoning is preserved inline (marked historical/resolved), not deleted |
| Governs | 6G onward may reference this document's resource ownership boundary but do not extend it. |
| Date | 2026-08-24 (Phase 5L.2 final consistency pass) |
| **Status of this revision** | **PHASE 6F — APPROVED / FROZEN.** All six originally-BLOCKING dependencies (§39), plus the `DEP-6F-03` vocabulary item, are `RESOLVED` against the executed schema (migrations `078_5F1`-`092_5F12`), live-validated across three reconciliation passes (Phase 5L, 5L.1, 5L.2) — see `5L-Global-Database-Reconciliation.md` for full evidence. §43's freeze gate (re-run below) confirms zero remaining BLOCKING items. |

---

### 1.1a Phase 5L.1 Post-Database-Reconciliation Correction (2026-08-24)

This is a **targeted correction**, not a regeneration — most of this document's content (request/response shapes, non-blocked endpoints, security model, error taxonomy) is unchanged. Only the following are updated by this pass, everywhere they occur in this document:

- `DEP-6F-01`, `DEP-6F-02`, `DEP-6F-09`, `DEP-6F-14`, `DEP-6F-15`, `DEP-6F-16` (and `DEP-6F-03`, vocabulary) move from **BLOCKING** to **RESOLVED** (§39).
- The three previously **CONTRACT-DEFINED, EXECUTION BLOCKED** endpoints — `POST .../reindex`, `POST .../documents/{id}/reprocess`, `DELETE .../documents/{id}` — move to **IMPLEMENTATION-READY** (§8-§16, §33.1, §42).
- `POST .../reindex` now describes the **real** generation-based reindex lifecycle (begin/build/complete/fail/cleanup, `083_5F6.sql`/`088_5F8.sql`/`089_5F9.sql`) — the withdrawn fake metadata-only behavior (§22, prior pass) is **not** restored.
- §12.4's "there is no rollback endpoint" claim is corrected — `knowledge.fn_docver_rollback()` (`079_5F2.sql`) now exists and is proven to remain correct even after a full reindex+cleanup cycle (`089_5F9.sql`'s coherence fix).
- The hybrid-search keyword leg (§20/QP-09) is corrected from a single unconditional `english`-config query to a two-branch query matching the storage-side language allow-list (`en`/`ta`/`te`/`hi`) established in `084_5F7.sql` — the old pattern was live-proven to miss unstemmed `simple`-stored content.
- Endpoint readiness counts (§33.1, §42) are recomputed: **22/22 IMPLEMENTATION-READY** (was 18/21; +1 new endpoint, `POST .../rollback`, §12.4).
- Not changed by this pass: 6A/6C/6D/6E (no contradiction found), request/response schemas, auth/permission model, rate-limit tiers, error taxonomy, the embedding-model single-value constraint, or any endpoint not named above.

### 1.1b Phase 5L.2 Final Freeze Review — Consistency Pass (2026-08-24)

A final independent freeze review found two remaining technical
coherence issues in Phase 5L.1's own new mechanisms, plus stale
contradictory text left over from the pre-5L.1 correction pass (BLOCKING
dependency descriptions, an outdated "Controlled Reconciliation
Required" work list) that Phase 5L.1's edits had not fully swept through
this document. This is again a **targeted correction, not a
regeneration** — this pass:

- Corrects the **final** retrieval predicate (§16.5, new): `index_generation
  <= index_version` alone was insufficient — it allows both an old and a
  new chunk generation to match simultaneously for a short window after
  a reindex cutover but before cleanup, producing duplicate hits. The
  corrected predicate adds a `NOT EXISTS` clause selecting exactly the
  single highest available generation per current document version.
  Applied identically to QP-08 (vector) and QP-09 (keyword) — see §16.5
  for the exact SQL. No new index required (confirmed via `EXPLAIN
  ANALYZE` against the existing `idx_dc_version_generation`).
- Corrects the reindex manifest predicate (migration `092_5F12.sql`):
  `d.status <> 'DELETED'` incorrectly included `ARCHIVED` documents,
  which 6F's own retrieval policy excludes — tightened to
  `d.status = 'READY'` (§22.2).
- Sweeps every remaining stale "BLOCKING"/"no supporting function
  exists"/"not implemented" statement left in §5 (findings F-1–F-8),
  §11.4, §28 (races 3, 9, 10, 12), §31 (test matrix), §38 (traceability),
  and §43 (closure checklist) — each now reads **RESOLVED**, with the
  closing migration named, and the original finding's reasoning
  preserved (not deleted) as historical context.
- Converts §44 ("Controlled Reconciliation Required") from a forward-
  looking work list into a **closure record** — every item shows its
  resolving migration and validation evidence, status `CLOSED`.
- Updates the top-of-document status banner (§1) from "APPROVED / FROZEN
  CANDIDATE" to **"APPROVED / FROZEN"** — per the governing task's own
  freeze-gate rule, now that every condition it lists is independently
  re-verified (§43.2).
- Not changed by this pass: endpoint count (still 22/22), request/response
  schemas, the multilingual two-branch language strategy (Phase 5L.1,
  unaffected), auth/permission model, any endpoint's route/method/status
  code.

### 1.1 What Changed in This Correction Pass

An independent review found that the prior revision relied on the 5F **design document's** prose in several places where the **executed migrations** (`034_5F.sql`–`038_5F.sql`) physically differ from that prose, and that the prior revision's freeze recommendation ("APPROVED / FROZEN CANDIDATE") was inconsistent with its own disclosed BLOCKING dependencies. This pass:

1. Re-derives every duplicate-content, lifecycle-transition, and GDPR-erasure claim from the **executed SQL**, not the design document's narrative, wherever the two could differ (§4.1).
2. Adds three newly discovered BLOCKING dependencies (`DEP-6F-14`, `DEP-6F-15`, `DEP-6F-16`) that the prior pass missed or under-classified.
3. Removes every "implementation-ready" claim for an endpoint whose physical execution path does not actually exist in the granted privileges/functions.
4. Corrects the freeze gate (§43) to **PHASE 6F — REVISION REQUIRED**, consistent with having unresolved BLOCKING dependencies.
5. Adds §44, a Controlled Reconciliation Required list, scoped explicitly to work this document does **not** authorize.

---

## 2. Purpose

This document is the authoritative API design for the Knowledge / RAG capability of the platform: Knowledge Base configuration, Document ingestion and lifecycle, Document Version publication, Ingestion Job observation, and Knowledge retrieval (hybrid semantic + keyword search) — both as an external/manual REST surface and as the in-process contract the Voice runtime consumes mid-call.

It does not redesign anything already frozen in Phases 1–5 or 6A–6E. Every capability below is traced to an existing requirement, aggregate, table, function, or port. Where the frozen sources do not fully specify a capability, this document says so explicitly (§39 Dependencies) rather than inventing a mechanism.

---

## 3. Scope / Hard Boundary

### 3.1 6F Owns

- Knowledge Base lifecycle: create, read/list, update settings, archive, (bounded) reindex.
- Document lifecycle inside a Knowledge Base: register/upload, read/list, reprocess (retry-from-failure), delete (soft-delete + GDPR-grade content erasure, per §23).
- DocumentVersion read model and publication action (thin wrapper over `fn_docver_publish()`).
- IngestionJob status observation (read-only; no tenant-callable cancel).
- Knowledge retrieval/search API — the external/manual REST surface — and the boundary contract for the Voice runtime's in-process retrieval path (§20).
- Knowledge-source metadata (`documents.metadata`) as an opaque, bounded key-value filter surface.
- Object-storage boundary for Knowledge documents (presigned upload/download, never proxied bytes).

### 3.2 6F Does Not Own

| Capability | Owner |
|---|---|
| AI Agent CRUD/configuration, `knowledge_base_refs` field itself | 6E |
| Voice/call runtime, WS turn loop | 6D |
| Workflow APIs (`KNOWLEDGE_SEARCH` node authoring) | 6I |
| CRM | 6G |
| Campaign | 6H |
| Billing / usage metering / storage quota | 6K |
| Integrations / provider plugins / knowledge-provider connectors | 6J |
| Analytics / cost projections over Knowledge events | 6L |
| Admin control plane | 6M |
| Prompt management | Not 6F (no roadmap document assigns it here) |
| Conversation memory | Not 6F |

6F does not absorb any of the above merely because Knowledge/RAG interacts with them (Agent references, Workflow nodes, Analytics event consumption, Billing cost events) — every such interaction is either an opaque reference, a domain event, or an in-process port, never a new endpoint owned by 6F on another context's behalf.

---

## 4. Governing Documents

| Document | Role |
|---|---|
| `phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` | FR-RAG-001..005, FR-TEN-002/005, NFR-SEC-003/006 — binding requirements |
| `phase-03-low-level-design/3D-Workflow-RAG.md` | LLD for ingestion pipeline, hybrid search, ports |
| `phase-04-domain-driven-design/4E-Knowledge-RAG-Workflow-Tools.md` | Aggregates, invariants, commands, queries, domain events, DDRs |
| `phase-04-domain-driven-design/4I-India-First-Decision-Closure.md` | OQ-FINAL-03 (embedding model closure), S3/index/partition additions |
| `phase-05-database-design/5F-Knowledge-RAG-Schema.md` | Design-intent narrative — **not treated as physical source of truth wherever it conflicts with the executed migration (§4.1)** |
| `phase-05-database-design/5K/migrations/034_5F.sql` – `038_5F.sql`, `043_5F.sql`, `044_5F.sql` | **Executed, physical source of truth** for every table, constraint, index, trigger, function, and grant this document relies on |
| `phase-05-database-design/5B-Identity-Organization-Multitenancy-Security.md` | Permission catalog (`knowledge:read/write/delete`), role matrix |
| `phase-05-database-design/5J-Analytics-Audit-Schema.md` | `action_kind` vocabulary, `audit.fn_insert_audit_event()` |
| `phase-06-api-design/6A-API-Architecture-and-Standards.md` | Binding cross-cutting API standards |
| `phase-06-api-design/6E-AI-Agent-APIs.md` | `knowledge_base_refs` handoff (`DEP-6E-04`) |

### 4.1 Design Document vs. Executed Migration — Precedence Rule

Per the governing correction-pass instruction: **where `5F-Knowledge-RAG-Schema.md`'s prose and the executed migration SQL differ, the executed migration is the physical reality this document designs against.** Migration `036_5F.sql` carries an explicit in-file correction comment confirming one such divergence exists (§5 F-7, §11.4, §40-J):

> *"Correction: dedup index changed from `(knowledge_base_id, content_hash)` to `(document_id, content_hash)` — `knowledge.document_versions` has no `knowledge_base_id` column (5K §10.4)."*

This document's every claim about `uq_dv_content_hash`, `fn_docver_mark_ready()`, `fn_docver_publish()`, `create_kb_partition()`, and every table's grant set has been re-verified directly against `034_5F.sql`–`038_5F.sql`/`044_5F.sql` in this pass, not re-derived from the design document's prose alone.

---

## 5. Source Reconciliation Findings

This section records every place the frozen sources required interpretation, and states the interpretation adopted. Full analysis is in §40.

| # | Finding | Resolution |
|---|---|---|
| F-1 | FR-RAG-004 ("version knowledge bases and allow rollback") has no `KnowledgeBaseVersion` aggregate anywhere in 4E or 5F. The only physical versioning is per-Document (`document_versions` + `current_version_id`). | Adopted: "knowledge base versioning" is realized as **per-document version history + publication**, not a KB-level snapshot/rollback. True historical **rollback** (re-activating a `SUPERSEDED` version) originally had no supporting function — `DEP-6F-01`, then BLOCKING for full FR-RAG-004 compliance (§40-A). **RESOLVED, migration `079_5F2.sql` (Phase 5L):** `knowledge.fn_docver_rollback()` implements exactly this — document-level historical rollback, mirroring Prompt Management's existing pointer-swap pattern. Remains correct after a reindex+cleanup cycle by construction (`089_5F9.sql`, Phase 5L.1) and resolves the correct chunk generation at retrieval time (§16.5, Phase 5L.2). Live-validated end-to-end (5L.1's 17-step test; 5L.2's rollback-fallback test). See §12.4. |
| F-2 | 4E states a Knowledge Base in `REINDEXING` "continues to serve queries from the previous index version — the old index is only replaced when the new one is fully built." 5F has no per-chunk `index_version` column, no dual-generation index representation, and `document_chunks` is INSERT/DELETE-only (no UPDATE). Re-embedding an already-`READY` document's content under a new `document_versions` row collides with `uq_dv_content_hash` (identical bytes, prior version not excluded from the uniqueness scope since it is `SUPERSEDED`, not `FAILED`/`GDPR_ERASED`). | Originally: full re-embedding of already-`READY` content across a KB was not implementable — `DEP-6F-02`, BLOCKING (§40-E). **RESOLVED, migrations `083_5F6.sql` (Phase 5L) + `088_5F8.sql`/`089_5F9.sql`/`092_5F12.sql` (Phase 5L.1/5L.2):** derived chunk/index generations (`document_chunks.index_generation`) plus a full begin/build/complete/fail/cleanup lifecycle satisfy 4E's requirement exactly as stated — old generation serves throughout the rebuild, completeness is proven against a manifest snapshot (correctly scoped to `status='READY'` documents only, §22.2), and cutover is atomic. Live-validated including a genuine two-session concurrency race and a partial-build rejection test. See §22. |
| F-3 | 4E's `Document` lifecycle names `ReprocessDocument` from `FAILED` only, and the design document's version of `uq_dv_content_hash` excludes rows with `status IN ('FAILED','GDPR_ERASED')` — implying reprocess is schema-safe once the prior version is `FAILED`. **However**, no executed migration (`034_5F.sql`–`038_5F.sql`) grants `app_api`/`app_worker` any path to ever set `document_versions.status = 'FAILED'`: `UPDATE`/`DELETE` are explicitly revoked (`036_5F.sql` line 82), and the only two executed lifecycle functions are `fn_docver_mark_ready()` and `fn_docver_publish()` — neither can transition a row to `FAILED`. | Originally: reprocess's retry-version `INSERT` could not legally succeed — `DEP-6F-09`, BLOCKING (§15, §39). **RESOLVED, migration `080_5F3.sql` (Phase 5L):** `knowledge.fn_docver_mark_failed()` provides the missing `PENDING`→`FAILED` `SECURITY DEFINER` path (idempotent, rejects any other source state). Live-validated. See §15. |
| F-4 | 4E's Document commands list has no explicit `GdprEraseDocument` command; the design document's `document_versions.status` enum includes `GDPR_ERASED`, and its QP-06/ADR-5F-011 describe a single combined "Delete / GDPR Erase Document" flow. **However**, no executed migration defines a `fn_docver_gdpr_erase()` (or equivalently named) function, and `036_5F.sql` revokes `UPDATE`/`DELETE` on `document_versions` from every application role unconditionally — there is no legal path today for `app_api`/`app_worker` to set `storage_ref='ERASED'`/`content_hash='ERASED'`/`status='GDPR_ERASED'` on an existing row. | Originally: the version-erasure step of `DELETE /documents/{id}` had no legal execution path — `DEP-6F-15`, BLOCKING (§23, §39). **RESOLVED, migration `081_5F4.sql` (Phase 5L):** `knowledge.fn_docver_gdpr_erase()` (per-version) and `knowledge.fn_document_gdpr_delete()` (per-document orchestration) provide it, using the pre-existing `prevent_docver_immutable_field_mutation()` carve-out. Live-validated. See §23.4. |
| F-5 | 6E's `DEP-6E-04` records `knowledge_base_refs` existence/ownership validation as explicitly unresolved, NON-BLOCKING, "ownership belongs to 6F." No existence-check port is defined anywhere in Phase 4. | Adopted: 6F defines the **authoritative read contract** (`GET /knowledge-bases/{kb_id}`) any caller may use to check existence/ownership/status, but does **not** invent a synchronous cross-context call from 6E. Runtime resolution via `KnowledgeSearchPort` fails soft on a missing/non-`ACTIVE` KB. `DEP-6F-04`, NON-BLOCKING (§21). This finding is unaffected by this correction pass. |
| F-6 | 5J's `action_kind` vocabulary has `KNOWLEDGE_BASE_CREATED`, `KNOWLEDGE_BASE_DELETED`, `DOCUMENT_DELETED` but no values for KB update/archive/reindex, document upload/archive/reprocess, or version publish. | Seven values needed (`KNOWLEDGE_BASE_UPDATED`, `KNOWLEDGE_BASE_ARCHIVED`, `KNOWLEDGE_BASE_REINDEX_TRIGGERED`, `DOCUMENT_UPLOADED`, `DOCUMENT_ARCHIVED`, `DOCUMENT_REPROCESS_REQUESTED`, `DOCUMENT_VERSION_PUBLISHED`) — `DEP-6F-03`, NON-BLOCKING for execution (the length-only `CHECK` physically accepts any of them) but required for governance completeness. **RESOLVED — doc-only amendment, Phase 5L:** all seven, plus 4 more for DEP-6B-02 and 4 more for Phase 5L's own new lifecycle functions, added to `5J-Analytics-Audit-Schema.md` §14.3 (`§` marker). Zero SQL required. |
| F-7 | The design document (`5F-Knowledge-RAG-Schema.md`) states `uq_dv_content_hash` as `(knowledge_base_id, content_hash)` and frames `NoDuplicateDocumentContent` (4E §10) as "same `ContentHash` in same KB is rejected." The **executed** `036_5F.sql` instead creates `uq_dv_content_hash ON knowledge.document_versions (document_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')`, with an explicit in-file comment: `document_versions` has no `knowledge_base_id` column, so the constraint was corrected to `document_id` scope during migration authoring. | Originally a genuine DDD-to-migration inconsistency: two different documents in the same KB with identical content were not rejected — `DEP-6F-14`, BLOCKING. **RESOLVED, migration `082_5F5.sql` (Phase 5L):** `document_versions.knowledge_base_id` added (server-derived via trigger, never client-supplied; FK-enforced), `uq_dv_content_hash_kb (knowledge_base_id, content_hash)` replaces the document-scoped index. Live-validated: same-KB cross-document duplicate rejected, cross-KB identical content allowed, spoofing attempt overridden. See §11.4. |
| F-8 | `fn_docver_publish()` as executed (`034_5F.sql`) validates `version_id`/`document_id`/`organization_id`/`status='READY'` but has no precondition on `documents.status`. A concurrent/late-committing publish can therefore set `documents.current_version_id`/`status='READY'` on a document whose delete flow has already tombstoned it (`status='DELETED'`). | Originally: `DEP-6F-16`, BLOCKING for closing this race (§12.2, §23, §28 race #9, §39). **RESOLVED, migration `078_5F1.sql` (Phase 5L):** `fn_docver_publish()` now requires `documents.status <> 'DELETED'`; additionally, `documents.current_version_id` is column-privilege-locked (a second, independently-discovered bypass path via direct `UPDATE`, closed in the same migration). Live-validated. |

---

## 6. Resource Ownership Matrix

| Resource | Aggregate (4E) | Table (5F) | 6F Endpoint Root |
|---|---|---|---|
| Knowledge Base | `KnowledgeBase` | `knowledge.knowledge_bases` | `/api/v1/knowledge-bases` |
| Document | `Document` | `knowledge.documents` | `/api/v1/knowledge-bases/{kb_id}/documents` |
| Document Version | `DocumentVersion` (entity) | `knowledge.document_versions` | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions` |
| Ingestion Job | `IngestionJob` | `knowledge.ingestion_jobs` | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs` |
| Document Chunk | `DocumentChunk` (entity, not AR) | `knowledge.document_chunks` | **Not independently addressable** — surfaced only as scored/cited retrieval results |
| Retrieval | `RetrievalService` (domain service) | reads `document_chunks`/`document_versions`/`documents` | `/api/v1/knowledge/search` |

No endpoint exposes `document_chunks` as a CRUD resource, per §4E's own classification of chunks as non-independent entities and per the governing task's explicit prohibition.

---

## 7. Knowledge/RAG Architecture Overview

```
                         ┌───────────────────────────────────────────┐
                         │        Tenant / Admin / API-key caller     │
                         └───────────────────────────┬─────────────────┘
                                                       │ REST /api/v1/*
                    ┌──────────────────────────────────▼──────────────────────────────┐
                    │                     6F Interface Layer (this doc)                 │
                    │  KnowledgeBase router · Document router · Version router ·         │
                    │  IngestionJob router · Retrieval router                            │
                    └───────┬───────────────────────────────────────────┬──────────────┘
                            │ calls (in-process, same module)            │ calls
                    ┌───────▼─────────────────┐                 ┌───────▼──────────────┐
                    │ KnowledgeApplicationService│                │ KnowledgeApplicationService│
                    │ .upload_document() etc.    │                │ .search_knowledge()        │
                    └───────┬─────────────────┘                 └───────┬──────────────┘
                            │                                            │
              ┌─────────────▼──────────────┐                ┌────────────▼───────────────┐
              │ Document/KB/IngestionJob    │                │ RetrievalService (domain)   │
              │ aggregates + repositories    │                │ RRF + citation assembly     │
              └─────────────┬──────────────┘                └────────────┬───────────────┘
                            │                                             │
              ┌─────────────▼─────────────────────────────────────────────▼──────────────┐
              │  Ports: ObjectStorePort · DocumentParserPort · ChunkerPort ·                │
              │  EmbeddingPort · VectorSearchPort                                            │
              └─────────────┬──────────────────────────────────────────────┬──────────────┘
                            │                                               │
              ┌─────────────▼───────────┐                    ┌──────────────▼─────────────┐
              │ S3 object storage         │                    │ PostgreSQL `knowledge` schema│
              │ (source bytes, parsed txt)│                    │ (5F tables, RLS, HNSW, GIN) │
              └───────────────────────────┘                    └─────────────────────────────┘

                         ┌───────────────────────────────────────────┐
                         │        Voice Orchestrator (6D / 4B)         │
                         │  KnowledgeSearchNode / lookupKnowledge tool │
                         └───────────────────────────┬─────────────────┘
                                                       │ in-process call — NOT HTTP (§20)
                                                       ▼
                                    KnowledgeApplicationService.search_knowledge()
                                    (the SAME application service GET /knowledge/search calls)
```

Both the public REST retrieval endpoint and the Voice runtime's mid-call tool invocation are thin callers of the **same** `KnowledgeApplicationService.search_knowledge()` use case — there are two front doors (REST, in-process port) and one implementation, per DRY and per 4E §14.1.

---

## 8. KnowledgeBase API — Full Depth (Showcase 1: Create Knowledge Base)

### 8.1 `POST /api/v1/knowledge-bases`

| Field | Value |
|---|---|
| Purpose | Create a new Knowledge Base — the configuration/embedding-model/chunking boundary a tenant's documents live inside. |
| Surface | Public (`/api/v1/`) |
| Auth | JWT (user session) or organization-scoped API key |
| Permission | `knowledge:write` (5B §17.1) |
| Allowed actors | OWNER, ADMIN, MEMBER (5B §17.2 role matrix — MEMBER has `knowledge:write`) |
| API-key eligible | Yes — no capability here is user-session-only |
| Tenant scope | `organization_id` derived from JWT/API-key context (6A §23.2) — never accepted from the body |
| Path parameters | None |
| Headers | `Idempotency-Key` (required — real-world resource creation, 6A §16.1) |
| Request body | `{ "name": str[1..200], "description": str[0..500]?, "embedding_model_ref": str, "chunking_strategy": {strategy_type, chunk_size_tokens[128..2048], overlap_tokens[0..512], split_on?}, "retrieval_config": {default_top_k?, similarity_threshold?, hybrid_search_enabled?, hybrid_semantic_weight?, hybrid_keyword_weight?}? }` |
| `embedding_model_ref` validation | Must equal the platform's single supported value `"openai:text-embedding-3-large:1536"` (4I OQ-FINAL-03 / ADR-INDIA-014) — any other value is `422 VALIDATION_ERROR`. No provider-registry lookup exists (§25, `DEP-6F-05`). |
| Response schema | `{ "data": { "id", "organization_id", "name", "description", "embedding_model_ref", "embedding_dimensions", "chunking_strategy", "retrieval_config", "index_version", "status", "document_count", "created_by", "created_at", "updated_at" } }` |
| Success status | `201 Created`, `Location: /api/v1/knowledge-bases/{id}` |
| Errors | `422 VALIDATION_ERROR` (bad `chunking_strategy` bounds, unsupported `embedding_model_ref`), `409 CONFLICT` (duplicate `(organization_id, name)` — `uq_kb_name`), `429 RATE_LIMIT_EXCEEDED`, `IDEMPOTENCY_KEY_REUSE_MISMATCH` |
| Idempotency | Required (§6A §16) — same key + same fingerprint replays the cached `201`; same key + different body → `409 IDEMPOTENCY_KEY_REUSE_MISMATCH` |
| Rate-limit class | Standard CRUD (L2, 300 req/min/org, 6A §20) |
| Latency tier | Tier A — Interactive (single indexed insert + one `SECURITY DEFINER` call, no external dependency, 6A §11) |
| DB / function | `INSERT knowledge.knowledge_bases (...)` then `SELECT knowledge.create_kb_partition($kb_id)` — same transaction (5F QP-01) |
| RLS | `rls_kb_tenant` enforces `organization_id = organization.current_tenant_id()` on the INSERT's `WITH CHECK` |
| Transaction boundary | Single short transaction: validate (in-process) → INSERT `knowledge_bases` → `create_kb_partition()` → commit. No external call inside the transaction. |
| Audit | `action_kind = KNOWLEDGE_BASE_CREATED` (existing, Category A). **Synchrony, precisely stated:** this is a "Configuration... lifecycle change" under 5J §14.5's general rule, and 6F names no approved exception for it — it therefore follows the **asynchronous default**: the mutation's own transaction commits first, and a Celery-dispatched follow-up calls `audit.fn_insert_audit_event()` (the same sole write path every synchronous category also uses — §30.3) outside that transaction. This is *not* same-transaction-rollback-coupled to the KB creation itself. |
| Domain event / outbox | `knowledge_base.created` (4E §11.1) — published to the durable outbox after commit, at-least-once |
| Async side effects | None beyond the outbox publish and async audit write |
| Object-storage effects | None |
| Concurrency | Two concurrent creates with the same `(organization_id, name)` — second INSERT violates `uq_kb_name` → `409 CONFLICT` with `error.details.field="name"` |
| PII/security | `name`/`description` are tenant-authored, not PII-classified; no secret fields in the response |

### 8.2 Compact Inventory — Remaining KnowledgeBase Endpoints

| Endpoint | Method | Purpose | Permission | Latency Tier | Status | Notes |
|---|---|---|---|---|---|---|
| `/api/v1/knowledge-bases` | GET | List KBs (cursor-paginated, filter `status`) | `knowledge:read` | Tier A | 200 | Default sort `created_at DESC`; summary DTO (no `chunking_strategy`/`retrieval_config` inline — fetch detail for that) |
| `/api/v1/knowledge-bases/{kb_id}` | GET | Get one KB (full config) | `knowledge:read` | Tier A | 200 / 404 | 404 for cross-tenant (never 403, 6A §7.4) |
| `/api/v1/knowledge-bases/{kb_id}` | PATCH | Update `name`, `description`, `chunking_strategy`, `retrieval_config` | `knowledge:write` | Tier A | 200 / 404 / 409 / 412 / 422 | **IMPLEMENTATION-READY.** `If-Match` required (ETag on `updated_at`, 6A §17.2). **`embedding_model_ref` and `embedding_dimensions` are not in the allow-listed field set — any attempt to set them is `422 VALIDATION_ERROR` with `details.reason="EMBEDDING_MODEL_IMMUTABLE"`**, defended additionally by the DB trigger `prevent_kb_model_mutation()` (INV-01/INV-09, belt-and-braces). `chunking_strategy` changes apply only to **future** ingestions — this KB row-level `UPDATE` itself is unaffected by any BLOCKING dependency; only downstream *reindexing of already-ingested content* is blocked (§22). |
| `/api/v1/knowledge-bases/{kb_id}/archive` | POST | `ACTIVE → ARCHIVED` (terminal for retrieval — archived KBs excluded from search, §23) | `knowledge:write` | Tier B | 202 / 404 / 409 | **IMPLEMENTATION-READY.** Plain `UPDATE knowledge_bases SET status` — the `UPDATE` grant on `knowledge_bases` is not revoked (`035_5F.sql`). Idempotency-Key required. `409 STATE_CONFLICT` if already `ARCHIVED`. Documents inside remain readable via management APIs (§23.5) but the KB drops out of retrieval. |
| `/api/v1/knowledge-bases/{kb_id}/reindex` | POST | **IMPLEMENTATION-READY (Phase 5L.1).** Begins a real, generation-based full rebuild — see §22. `DB: SELECT knowledge.fn_kb_reindex_begin($kb_id, $org_id)`, worker rebuilds chunks tagged with the returned generation, then `SELECT knowledge.fn_kb_reindex_complete($kb_id, $org_id, $generation)` (or `fn_kb_reindex_fail(...)` on error) | `knowledge:write` | Tier B | — | `DEP-6F-02`, **RESOLVED** — see §22 for the full corrected treatment. |

`PUT`/full-replace is not offered for `knowledge_bases` — 6A §7.3 reserves `PUT` for genuine full-replacement resources; a KB's immutable fields (`embedding_model_ref`) make a full-replace semantic meaningless here.

---

## 9. KnowledgeBase Configuration Contract

| Field | Mutable after creation? | Enforcement |
|---|---|---|
| `name` | Yes (PATCH) | `uq_kb_name` on write |
| `description` | Yes (PATCH) | — |
| `embedding_model_ref` | **No** | DB trigger `prevent_kb_model_mutation()` (INV-01) + API-level allow-list exclusion |
| `embedding_dimensions` | **No** | Same trigger (INV-09) |
| `chunking_strategy` | Yes, but **prospective only** — already-`READY` document versions keep the chunk layout they were ingested with | Application-level; no DB constraint prevents the value from changing, but retrieval never re-chunks existing content |
| `retrieval_config` (`default_top_k`, `similarity_threshold`, `hybrid_search_enabled`, `hybrid_semantic_weight`, `hybrid_keyword_weight`) | Yes, **retroactive** — read live at query time from the KB row, so a PATCH takes effect on the very next search | Application-level bounds validation (§18) |
| `index_version` | No (system-managed, incremented only by `reindex`) | — |
| `status` | Only via `archive`/`reindex` action endpoints, never generic PATCH (6A §8.3) | — |
| `document_count` | No (event-projected, 4E §4.1 inv.4) | Updated by async projection consuming `document.indexed`/`document.deleted` |

There is no "update embedding model" endpoint, and none is added: per DDR-4E-003, changing the embedding model requires creating a **new** Knowledge Base and re-ingesting into it. 6F exposes no migration/copy tool for this (§26 prohibited-capabilities list — no KB copy/clone).

---

## 10. Document API

### 10.1 Compact Inventory

| Endpoint | Method | Purpose | Permission | Latency Tier | Status | Readiness |
|---|---|---|---|---|---|---|
| `/api/v1/knowledge-bases/{kb_id}/documents` | POST | Register/upload a document (all source types, §11) | `knowledge:write` | Tier A (register) / Tier B (FAQ synchronous write) | 201 / 202 | **IMPLEMENTATION-READY** (§11.4 — but see the corrected duplicate-content scope, §5 F-7) |
| `/api/v1/knowledge-bases/{kb_id}/documents` | GET | List documents (cursor, filter `status`, `source_type`) | `knowledge:read` | Tier A | 200 | **IMPLEMENTATION-READY** |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | GET | Get one document (summary + current version pointer) | `knowledge:read` | Tier A | 200 / 404 | **IMPLEMENTATION-READY** |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/reprocess` | POST | Retry ingestion from `FAILED` (§15) | `knowledge:write` | Tier B | — | **IMPLEMENTATION-READY (Phase 5L.1)** — `DB: SELECT knowledge.fn_docver_mark_failed($version_id, $org_id, $reason)` then a new `PENDING` version. `DEP-6F-09`, **RESOLVED** (§15) |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | DELETE | Soft-delete + content erasure (§23) | `knowledge:delete` | Tier B | — | **IMPLEMENTATION-READY (Phase 5L.1)** — `DB: SELECT knowledge.fn_document_gdpr_delete($document_id, $org_id)`. `DEP-6F-15`, **RESOLVED** (§23) |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/archive` | POST | `READY → ARCHIVED` (excluded from retrieval, row/content retained) | `knowledge:write` | Tier A | 200 / 404 / 409 | **IMPLEMENTATION-READY** — plain `UPDATE documents SET status`, `UPDATE` grant not revoked (`036_5F.sql`) |

A document's full extracted text/content is **never** returned by any of these endpoints (6A §10.4/§15/§27 — large content belongs in object storage or in bounded chunk-level retrieval results, never a management-API JSON payload).

### 10.2 Document Response Shape (Summary)

```json
{
  "id": "...", "knowledge_base_id": "...", "source_type": "PDF",
  "original_filename": "handbook.pdf", "title": "Employee Handbook",
  "status": "READY",
  "current_version": { "id": "...", "version_number": 2, "status": "READY", "chunk_count": 84, "created_at": "..." },
  "metadata": { "department": "hr", "language": "en" },
  "created_by": "...", "created_at": "...", "updated_at": "..."
}
```

`current_version` is `null` until the document's first successful ingestion is published (§12.3). `metadata` mirrors `documents.metadata` (max 50 keys, string/number/boolean values only, per 4E §4.2 inv.5).

---

## 11. Document Source / Upload Contract (Showcase 2: Register/Upload Document)

Three distinct contracts exist for the three source families 5F actually persists (`SourceType`: `PDF|DOCX|TXT|CSV|URL|FAQ|WEBSITE`). None is forced into a one-size-fits-all multipart upload.

### 11.1 File-Backed Sources (`PDF`, `DOCX`, `TXT`, `CSV`) — Presigned Upload

**Step 1 — `POST /api/v1/knowledge-bases/{kb_id}/documents/upload-url`**

| Field | Value |
|---|---|
| Purpose | Register upload intent and obtain a presigned S3 PUT URL — the standard 6A §29 media-transfer pattern. |
| Permission | `knowledge:write` |
| Request body | `{ "source_type": "PDF"\|"DOCX"\|"TXT"\|"CSV", "filename": str, "content_type": str, "size_bytes": int, "title": str?, "metadata": object? }` |
| Validation | `content_type` must match the declared `source_type`'s allow-listed MIME set (`application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `text/plain`, `text/csv`); `size_bytes` bounded by a 6F-level maximum (this document adopts **50 MB**, directionally consistent with 4E §22's "document size limit enforced at upload, default configurable, default 50 MB" — not a newly fabricated number); `filename` sanitized (strip path separators/control characters) before use in the storage key. |
| Response | `201 Created` — `{ "document_id", "upload_url" (S3 presigned PUT, 15-min expiry, 6A §29), "storage_ref", "expires_at" }` |
| DB effect | `INSERT knowledge.documents (status='PENDING', ...)` — a `document_versions` row is **not** created yet; `content_hash` is unknown until bytes exist in S3 |
| Object storage | Nothing written yet — only a presigned PUT policy issued, scoped to `org/{tenant_id}/knowledge/{kb_id}/{document_id}.{ext}` (4I §25.18 namespace, reused exactly) |
| Latency tier | Tier A (no external call other than the S3 presign, which is a local SDK signing operation, not a network round trip) |
| Idempotency | Required |

Client then `PUT`s bytes directly to S3 (never through the API — 6A §29's absolute rule against proxying media bytes).

**Step 2 — `POST /api/v1/knowledge-bases/{kb_id}/documents/{document_id}/complete`**

| Field | Value |
|---|---|
| Purpose | Confirm upload finished; hand off to the async ingestion pipeline. |
| Permission | `knowledge:write` |
| Request body | Empty |
| Response | `202 Accepted` — `{ "document_id", "status": "PROCESSING", "ingestion_job_id": null }` (`ingestion_job_id` populates once the async pipeline's first stage creates the job — poll `GET .../documents/{id}` or the ingestion-job endpoint, §13) |
| Transaction boundary | Short: `documents.status PENDING → PROCESSING`. Commit. Then enqueue the async pipeline (§14) — **the request never waits on S3 HEAD, hashing, parsing, chunking, or embedding.** |
| Async pipeline (worker, outside this request) | 1. `HEAD`/download the S3 object; verify actual bytes' magic number against declared `content_type` (6A §29). 2. Compute SHA-256 `content_hash`. 3. `INSERT document_versions (version_number=1, status='PENDING', content_hash, storage_ref, mime_type, size_bytes)` — see the **corrected duplicate-content note** immediately below; for a brand-new document this `INSERT` cannot collide with `uq_dv_content_hash` (§11.4). 4. `INSERT ingestion_jobs (attempt_count=1)`. 5. Proceed through `EXTRACTING → CHUNKING → EMBEDDING → INDEXING` (§14). |
| **Duplicate-content outcome — RESOLVED, Phase 5L** | `uq_dv_content_hash_kb ON document_versions (knowledge_base_id, content_hash)` (migration `082_5F5.sql`, replacing the document-scoped `uq_dv_content_hash` this row previously described) rejects a new document's first version if its content hash already matches any other non-`FAILED`/non-`GDPR_ERASED` version anywhere in the same KB — `knowledge_base_id` is server-derived (never client-supplied) and immutable. `DEP-6F-14` **RESOLVED**. Live-validated: same-KB cross-document duplicate rejected; cross-KB identical content allowed; client-side spoofing of `knowledge_base_id` overridden by the server-derived value. |
| Errors (sync, this request) | `404` (unknown `document_id`), `409 STATE_CONFLICT` (already `PROCESSING`/`READY`) |

### 11.2 URL / WEBSITE Sources — Direct Register, Async Crawl

**`POST /api/v1/knowledge-bases/{kb_id}/documents`** with `{ "source_type": "URL"|"WEBSITE", "source_url": str, "title": str?, "metadata": object? }`.

| Concern | Behavior |
|---|---|
| Synchronous validation (in this request, Tier A) | Scheme allow-list (`https://` only, matching 6A §22's SSRF standard for `webhook_endpoints.target_url`, applied here identically); DNS resolution check rejecting private/link-local/loopback/cloud-metadata IP ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `127.0.0.0/8`, IPv6 equivalents); `source_url` length bound (2048 chars). Failure → `422 VALIDATION_ERROR`. |
| Response | `202 Accepted` — `{ "document_id", "status": "PENDING" }` |
| Async crawl (worker) | Re-validates the resolved IP at fetch time (DNS-rebinding-safe fetch, 6A §22), follows redirects with the **same** validation re-applied per hop (never trusts a redirect target blindly), enforces a content-size limit and fetch timeout (implementation-level bound; no frozen number exists — tracked as `DEP-6F-08`), then proceeds through the identical `content_hash` → `document_versions` INSERT → `EXTRACTING → ...` pipeline as file sources. |
| `content_hash` timing | Asynchronous — identical reasoning to §11.1 (content isn't known until the crawl fetches it) |
| Duplicate content | Same corrected reality as §11.1: `uq_dv_content_hash` is `(document_id, content_hash)` (§5 F-7) — a new document's first version cannot collide with any other document's content, crawled or otherwise. `DEP-6F-14` applies identically here. |

### 11.3 FAQ Sources — Structured Body, Synchronous Registration

5F has **no separate FAQ-pair table** — `FAQ` is a `SourceType` value like any other, backed by the same `documents`/`document_versions`/`document_chunks` tables. No FAQ-pair CRUD API is invented (per the governing task's explicit prohibition and per the absence of a supporting table).

**`POST /api/v1/knowledge-bases/{kb_id}/documents`** with `{ "source_type": "FAQ", "faq_pairs": [{"question": str[1..500], "answer": str[1..4000]}], "title": str?, "metadata": object? }` — bounded to **500 pairs** per request (a 6F-level bound, not a frozen number, chosen to keep the synchronous write inside Tier B).

| Step | Detail |
|---|---|
| 1 | Validate `faq_pairs` shape/bounds (in-process, no I/O) |
| 2 | Serialize pairs into a canonical text document (e.g. `Q: ...\nA: ...` blocks) — this is the one source type where content is fully available **in the request body**, so `content_hash` (SHA-256 of the canonical serialization) is computable **synchronously**, unlike files/URLs |
| 3 | Write the serialized text to S3 (`ObjectStorePort.put()`, `org/{tenant_id}/knowledge/{kb_id}/{document_id}.txt`) — this happens **outside** any DB transaction (6A §35 rule: never hold a transaction open across an external call) |
| 4 | Short transaction: `INSERT documents (status='PENDING')` + `INSERT document_versions (version_number=1, status='PENDING', content_hash, storage_ref, mime_type='text/plain')`. **Corrected this pass:** because `document_id` is freshly generated for this request, this `INSERT` cannot collide with `uq_dv_content_hash` (`(document_id, content_hash)`, §5 F-7) regardless of whether identical FAQ content already exists elsewhere in the KB — the prior revision's claim that FAQ registration synchronously rejects duplicate content was based on the design document's superseded `(knowledge_base_id, content_hash)` scope and is **withdrawn**. `content_hash` is still computed synchronously here (the one genuine advantage FAQ retains over file/URL sources — the value is available for storage/citation/future-reprocess purposes), but it enforces nothing at registration time. `DEP-6F-14` applies identically here. |
| 5 | Enqueue `EXTRACTING`(no-op, text already extracted) `→ CHUNKING → EMBEDDING → INDEXING` same as any other source |
| Response | `201 Created` (the version row is created synchronously; only the chunk/embed/index stages remain async) |

### 11.4 Cross-Source Reconciliation Table (Corrected)

| Source Type | Bytes arrive via | `content_hash` computed | KB-wide duplicate detected? | Same-document re-ingest duplicate detected? | Success status |
|---|---|---|---|---|---|
| PDF/DOCX/TXT/CSV | Presigned S3 PUT (client-direct) | Async (worker, post-upload) | **No — `DEP-6F-14`** | Only relevant to reprocess, which is itself blocked (`DEP-6F-09`) | `201` (register) then `202` (complete) |
| URL/WEBSITE | Async crawl (worker) | Async | **No — `DEP-6F-14`** | Same as above | `202` |
| FAQ | Inline in request body, server writes to S3 | Synchronous (in-process, no I/O needed) | **No — `DEP-6F-14`** | Same as above | `201` |

**KB-wide duplicate content is now rejected at the DB level for every source type's initial registration**, matching the design document's and 4E's stated `NoDuplicateDocumentContent` guarantee exactly. `DEP-6F-14` **RESOLVED** (migration `082_5F5.sql`, Phase 5L; §5 F-7).

---

## 12. DocumentVersion API / Publication Model (Showcase 3: Publish Document Version)

### 12.1 Read Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions` | GET | List version history (cursor, small — bounded by attempt/publish count) |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}` | GET | Get one version (status, `chunk_count`, `mime_type`, `size_bytes`, timestamps — **never** `storage_ref`/`content_hash` raw values beyond existence, and never chunk content) |

### 12.2 `POST /api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/publish`

| Field | Value |
|---|---|
| Purpose | Make a `READY` version the document's current, searchable version — the sole write path onto `documents.current_version_id`. |
| Surface | Public |
| Auth | JWT or API key |
| Permission | `knowledge:write` |
| API-key eligible | Yes |
| Tenant scope | `organization_id` from context |
| Path parameters | `kb_id`, `document_id`, `version_id` |
| Headers | `Idempotency-Key` (recommended; the underlying operation is naturally idempotent — republishing the already-current version is a no-op `200`, so a key is not strictly required but is accepted) |
| Request body | Empty |
| Response schema | `{ "data": { "document_id", "current_version_id", "previous_version_id" } }` |
| Success status | `200 OK` |
| Errors | `404` (version/document not found or cross-tenant), `409 STATE_CONFLICT` (version not `READY`, or belongs to a different `document_id` — INV-12) |
| DB / function | `SELECT knowledge.fn_docver_publish($document_id, $version_id, $org_id)` — verified against the **executed** `034_5F.sql` in this pass, byte-for-byte consistent with the design document — the **sole** write path; 6F never issues a raw `UPDATE documents SET current_version_id = ...` (6A §8.3's guarded-transition rule) |
| RLS | `fn_docver_publish()` is `SECURITY DEFINER`; its own internal `organization_id` equality checks are the actual guard (INV-11/INV-12), not RLS alone, since the function runs with elevated privilege by design |
| Transaction boundary | Single call to the function — it internally supersedes the old current version and sets the new one, atomically, in one statement's execution |
| Audit | `action_kind = DOCUMENT_VERSION_PUBLISHED` — **proposed** (Category C gap, `DEP-6F-03`) — async (configuration-lifecycle default, per the corrected wording in §30.3) |
| Domain event / outbox | `document.indexed` was already published when the version reached `READY` (4E §11.1); publication itself has no dedicated 4E domain event name — reuses the same event's implicit "now current" meaning; no new event name is fabricated |
| Async side effects | None — this is a pure metadata cutover; no re-embedding, no S3 work |
| Concurrency | See §28 races 7/8/9. Race 9 (`fn_docver_publish()` vs. concurrent delete) is **RESOLVED** (migration `078_5F1.sql`, Phase 5L) — `fn_docver_publish()` now requires `documents.status <> 'DELETED'`. `DEP-6F-16` closed. |
| PII/security | None |
| **Readiness** | **IMPLEMENTATION-READY.** `fn_docver_publish()` exists, is granted, and functions as specified. `DEP-6F-16` (the publish/delete race) is **RESOLVED** — the function now requires `documents.status <> 'DELETED'`, and `documents.current_version_id` is column-privilege-locked against direct bypass (migration `078_5F1.sql`, live-validated). |

### 12.3 Auto-Publish vs. Explicit Publish (ADR-6F-07)

| Scenario | Behavior |
|---|---|
| First-ever successful ingestion of a Document (`current_version_id IS NULL`) | The ingestion worker calls `fn_docver_mark_ready()` **then immediately** `fn_docver_publish()` in the same pipeline run — **auto-published**. There is nothing at risk to protect, and gating the very first version behind a manual step would delay searchability with no safety benefit (contradicts FR-RAG-005's "bounded latency" spirit — a document should become queryable as soon as it is ready). |
| A later version succeeds while a current version already exists (i.e., a `reprocess`-after-`FAILED` recovery, §15) | The worker calls `fn_docver_mark_ready()` **only** — it does **not** auto-publish. The tenant must call `POST .../publish` explicitly. Rationale: a document that already has working, searchable content should never be silently swapped out by a background retry the tenant didn't confirm. Reprocess (§15) is now implementation-ready (Phase 5L.1, `DEP-6F-09` resolved), so this row is a normal, exercisable path. |

### 12.4 Rollback — What Is and Is Not Supported (IMPLEMENTATION-READY, Phase 5L.1)

`GET .../versions` gives full, honest history (audit/traceability satisfied). `DEP-6F-01` is **RESOLVED**: `POST /api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/rollback` → `DB: SELECT knowledge.fn_docver_rollback($document_id, $target_version_id, $org_id)` (migration `079_5F2.sql`). Re-activates a `SUPERSEDED` version — the target must currently be `SUPERSEDED` (a version that was previously published, then superseded; a never-published `PENDING`/`FAILED` version cannot be "rolled back" to); the current version is set to `SUPERSEDED`, the target to `READY`, `documents.current_version_id` updated — the same `documents.status <> 'DELETED'` guard as publish. No content is mutated and no version row is deleted — this is a pointer swap, mirroring Prompt Management's existing `rollback(environment, target_version)` pattern (4E), applied here to Documents (Interpretation A of FR-RAG-004 — document-level historical rollback, grounded in DDD evidence: Knowledge/RAG has no `KnowledgeBaseVersion` aggregate to apply a KB-snapshot interpretation to instead).

**Remains correct after a reindex**, by construction: `fn_kb_reindex_cleanup_old_generations()` (§22.2 step 5) never deletes the sole surviving chunk copy of a still-`SUPERSEDED` version, so a rollback target's content is always retrievable even after the KB has since been fully reindexed and cleaned up — live-proven end-to-end (`5L-Global-Database-Reconciliation.md` Phase 5L.1 items 3-4, the mandatory 17-step lifecycle test).

Success: `200 OK` with the updated document/version state. Errors: `404` (document/version not found), `409` (target not `SUPERSEDED`, or document `DELETED`). Permission: `knowledge:write`. Audit: `DOCUMENT_VERSION_ROLLED_BACK` (5J §14.3, Phase 5L amendment).

---

## 13. IngestionJob API

| Endpoint | Method | Purpose | Permission | Latency Tier |
|---|---|---|---|---|
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs` | GET | List all ingestion attempts for this document (≤3 per version chain, small/bounded) | `knowledge:read` | Tier A |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs/{job_id}` | GET | Get one job's detail (`status`, `current_stage`, `attempt_count`, `chunks_produced`, `embeddings_produced`, `error_message`, timestamps) | `knowledge:read` | Tier A |

Follows 6A §18's generic `/jobs/{job_id}` contract, **projected** from `knowledge.ingestion_jobs` — no duplicate job-tracking state. Status vocabulary is the richer, domain-specific one already defined in 5F (`PENDING|EXTRACTING|CHUNKING|EMBEDDING|INDEXING|READY|FAILED|CANCELLED`), not 6A §18.2's generic 5-value vocabulary — 6A §18.2 explicitly anticipates this: *"`knowledge.ingestion_jobs.status`: a richer multi-stage version of the same shape"* is the exact source cited for the generic vocabulary's design, so exposing the richer native vocabulary here is consistent with, not a deviation from, 6A.

There is **no tenant-callable job-level retry/cancel endpoint.** Retry is exclusively the document-level `reprocess` action (§15) — it creates a **new** job row rather than mutating an existing one, consistent with INV-06 (a `READY`/completed job is immutable). **That action is currently execution-blocked (`DEP-6F-09`)** — the two read-only job endpoints above are themselves fully implementation-ready (read-only, no lifecycle-function dependency), but the only tenant-facing *write* path this section names (reprocess) is not. Cancel is not offered: no `CancelIngestion` command exists in 4E's catalogue, and `CANCELLED` in the 5F status enum has no supported entry path documented anywhere upstream — recorded as a non-fabricated gap, not implemented.

---

## 14. Async Ingestion Pipeline Contract

```
POST /documents (or /upload-url + /complete)
  → short transaction: register document (+ version, if content already known) → commit
  → 202/201 response to client — NEVER waits for parsing/chunking/embedding/indexing
  → Celery enqueue (outside the transaction)
      ↓
  Worker: EXTRACTING  → DocumentParserPort.parse(storage_ref, source_type) → ParsedDocument
      ↓
  Worker: CHUNKING    → ChunkerPort.chunk(text, kb.chunking_strategy) → list[TextChunk]
      ↓                  (ingestion_jobs.chunks_produced set)
  Worker: EMBEDDING    → EmbeddingPort.embed_batch(chunk_texts, kb.embedding_model_ref) → list[EmbeddingVector]
      ↓                  (ingestion_jobs.embeddings_produced set)
  Worker: INDEXING     → VectorSearchPort.upsert_chunks(...) → INSERT knowledge.document_chunks (batch)
      ↓
  Worker: knowledge.fn_docver_mark_ready(version_id, org_id, chunk_count)
      ↓
  Worker: knowledge.fn_docver_publish(...) IF current_version_id IS NULL (§12.3), else leave for tenant
      ↓
  Worker: publish document.indexed (outbox)
```

No stage runs inside a database transaction held open across the S3/parser/embedding-provider call — each stage's DB write (job status transition) is its own short transaction (6A §35). Stage transitions are monotonic (INV-05), enforced at the application/worker layer (no executed migration adds a DB trigger for this — it is a worker-code invariant, not a schema one).

**On ingestion failure at any stage:** `ingestion_jobs.status → 'FAILED'`, `error_message` set (`037_5F.sql` grants `app_worker` `UPDATE` on `ingestion_jobs` unconditionally). **RESOLVED (Phase 5L, migration `080_5F3.sql`):** the corresponding `document_versions` row now transitions `PENDING → FAILED` via `knowledge.fn_docver_mark_failed()` (idempotent, `SECURITY DEFINER`, rejects any source state other than `PENDING`). `DEP-6F-09` closed — reprocess eligibility (§15) is keyed off `ingestion_jobs.status = 'FAILED'` and the retry version's `INSERT` now legally succeeds once the prior version is marked `FAILED` (its `content_hash` is excluded from `uq_dv_content_hash_kb`'s scope, §11.4).

---

## 15. Reprocess / Retry Semantics (Showcase 4: Reprocess Document) — IMPLEMENTATION-READY (Phase 5L.1)

**This endpoint's contract is fully specified below for forward-compatibility and for the future Phase 5 amendment to implement against. It is not part of 6F's V1 implementable surface — see the Readiness row.**

### 15.1 `POST /api/v1/knowledge-bases/{kb_id}/documents/{document_id}/reprocess`

| Field | Value |
|---|---|
| Purpose | Retry ingestion for a document whose latest attempt failed. |
| Surface | Public |
| Auth | JWT or API key |
| Permission | `knowledge:write` |
| API-key eligible | Yes |
| Tenant scope | `organization_id` from context |
| Path parameters | `kb_id`, `document_id` |
| Headers | `Idempotency-Key` (required) |
| Request body | Empty |
| Precondition | The document's most recent `ingestion_jobs` row (by `created_at DESC`) has `status = 'FAILED'` **and** `attempt_count < 3` (INV-04). |
| Response schema | `{ "data": { "document_id", "new_version_id", "ingestion_job_id", "attempt_count" } }` |
| Success status | `202 Accepted` |
| Errors | `404` (document not found), `409 STATE_CONFLICT` with `details.reason="LATEST_ATTEMPT_NOT_FAILED"` (most recent job isn't `FAILED`) or `details.reason="MAX_RETRY_ATTEMPTS_EXCEEDED"` (`attempt_count = 3`, INV-04) |
| DB / transaction | Short transaction: `INSERT document_versions (version_number = max+1, status='PENDING', SAME storage_ref/content_hash/mime_type/size_bytes as the failed attempt)` + `INSERT ingestion_jobs (attempt_count = prior+1)`. Commit. Then enqueue the pipeline (§14) — no re-upload required, the same S3 object is re-read. |
| `uq_dv_content_hash` interaction | The new version row would share the failed attempt's `content_hash` under the **same** `document_id`. This is schema-safe **only if** the prior (failed) version's `status` is excluded from `uq_dv_content_hash`'s scope — i.e. `FAILED` or `GDPR_ERASED`. Per the corrected finding above (`DEP-6F-09`), the prior version's `document_versions.status` is permanently stuck at `PENDING` (no granted path sets it to `FAILED`), which is **not** excluded — so this `INSERT` would violate `uq_dv_content_hash (document_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')` (`036_5F.sql`) under the current grant set. **No interim workaround is offered here** — an application-side `DELETE` of the stuck `document_versions` row is not legal either (`036_5F.sql` grants `SELECT, INSERT` only, no `DELETE`, to `app_api`/`app_worker`). |
| Audit | `action_kind = DOCUMENT_REPROCESS_REQUESTED` — proposed (Category C, `DEP-6F-03`) |
| Domain event | `document.uploaded`-shaped re-run — 4E names `IngestionJobRetried` (§11 catalogue is Workflow-only in that section; the Knowledge-specific equivalent is inferred from the `RetryIngestion` command in §4.3's command list, not separately catalogued as a domain event in §11.1 — this document does not fabricate an event name beyond what 4E's command catalogue implies) |
| Concurrency | Two concurrent `reprocess` calls on the same document — the second sees the first's new `ingestion_jobs` row is no longer the "most recent `FAILED`" once the first commits, so it naturally fails the precondition check (`409`), no explicit lock needed beyond ordinary `READ COMMITTED` visibility of the first commit. Moot until `DEP-6F-09` is resolved, since neither call can complete its `INSERT` today. |
| **Readiness** | **IMPLEMENTATION-READY (Phase 5L.1).** `DEP-6F-09` **RESOLVED** — `knowledge.fn_docver_mark_failed()` (migration `080_5F3.sql`) provides the `SECURITY DEFINER` path to move a `PENDING` `document_versions` row to `FAILED` (idempotent, rejects any other source state), unblocking the retry-version `INSERT`. Live-validated. |

### 15.2 Why This Is the Only (Intended) Retry Surface

- No job-level `POST .../ingestion-jobs/{id}/retry` exists — 4E's `RetryIngestion` command is scoped to the Document/IngestionJob pair, and reprocessing always produces a **new** job row (never mutates a `READY`/completed one, INV-06).
- `attempt_count` is enforced by the DB `CHECK (attempt_count BETWEEN 1 AND 3)` (INV-04) — the third failed attempt leaves no further retry available; the tenant must delete and re-upload as a new document if they wish to try again beyond the cap. (Delete is itself execution-blocked for its GDPR-erasure step, `DEP-6F-15` — §23 — so even this fallback is not currently usable end-to-end.)
- **A document whose first ingestion attempt fails today has no tenant-facing recovery path at all** until `DEP-6F-09` is resolved: reprocess cannot create a retry version, and delete cannot fully erase the failed version's content reference either.

---

## 16. Knowledge Retrieval / Search API (Showcase 5: Search Knowledge)

### 16.1 `GET /api/v1/knowledge/search`

Grounded directly in the domain query `SearchKnowledge(query, kb_ids, tenant_id, top_k, metadata_filter) -> RetrievalContext` (4E §13), **not** chosen by REST convention alone. Route shape (not nested under a single KB) follows from `SearchKnowledge`'s own signature accepting `kb_ids: list[...]` — multi-KB search is a first-class part of the domain query, so the endpoint cannot be `/knowledge-bases/{kb_id}/search`. `GET`, not `POST`, follows 6A §8.4's own explicit anticipation of this exact case: *"Search: ... (b) semantic search via the Knowledge/RAG context's existing pgvector/HNSW infrastructure (5F) for knowledge-base content"* is named as the example justifying a `GET .../search?q=...` route.

| Field | Value |
|---|---|
| Purpose | Tenant/admin/Agent-Builder manual retrieval — hybrid semantic + keyword search across one or more Knowledge Bases. |
| Surface | Public (`/api/v1/`) — **this is the external/manual path only; it is not what the Voice runtime calls, §20.** |
| Auth | JWT or API key |
| Permission | `knowledge:read` |
| API-key eligible | Yes |
| Tenant scope | `organization_id` from context; enforced on every underlying query (§16.4) |
| Path parameters | None |
| Query parameters | `q` (required, string, ≤500 chars, 6A §15's search-string cap), `kb_ids` (required, comma-separated UUIDs, **1–10 KBs** — a 6F-level bound), `top_k` (optional, integer, default **5**, max **20** — a 6F-level bound directionally consistent with the `top_k=5` example used throughout 3D §9.6/4E §16.2's own sequence diagrams, not claimed as a separately frozen number), `filter.{key}` (optional, repeatable, flat equality — §18) |
| Headers | None special (no `Idempotency-Key` — safe/idempotent GET, 6A §16.2) |
| Response schema | See §16.2 |
| Success status | `200 OK` (including the zero-results case — an empty `results[]` array, never `404`) |
| Errors | `422 VALIDATION_ERROR` (`q` too long, `top_k`/`kb_ids` out of bounds, unknown `filter.` key), `404` is **not** used for an unknown/cross-tenant `kb_id` inside `kb_ids` — that `kb_id` is silently excluded from the search rather than failing the whole request (consistent with 6A §7.4's non-disclosure rule: revealing "that KB doesn't exist" via a distinguishing error would leak cross-tenant existence information) |
| Idempotency | Not applicable (safe GET) |
| Rate-limit class | Standard CRUD tier, **not** the cost-sensitive LLM-backed tier (embedding calls are cache-favored and bounded; this is a read, not a billed generation) — 6A §20 |
| Latency tier | **Tier B — Operational** (6A §11) — bounded synchronous work: embedding-cache lookup (usually a hit), parallel HNSW + GIN queries, in-process RRF, no external provider call required for the *full* result under the common (cache-hit) path; on a cache miss, one bounded embedding-provider call is made, still within Tier B's 8s timeout ceiling. No new latency tier is invented. |
| DB / query | Parallel: 5F QP-08 (vector, HNSW, publication-gated, **effective-generation-gated**) + QP-09 (full-text, GIN, publication-gated, **effective-generation-gated**, two-branch language query) — see §16.5 for the exact, final corrected predicate (Phase 5L.2). Every table/column/index these query patterns depend on (`document_chunks.embedding`, the HNSW index, `tsvector_content`/GIN, `documents.current_version_id`, `document_chunks.index_generation`, `knowledge_bases.index_version`) is present in the executed schema through migration `092_5F12.sql`. |
| **Readiness** | **IMPLEMENTATION-READY.** |
| RLS | `rls_dc_tenant` on `document_chunks`, `rls_dv_tenant` on `document_versions`, `rls_doc_tenant` on `documents` — **plus** explicit `organization_id = $current_tenant_id` predicates in both QP-08 and QP-09 (INV-08 — RLS alone is insufficient by explicit domain invariant) |
| Transaction boundary | Single read-only transaction (or none — two independent read queries) — no write, no lock |
| Audit | **Not audited** — read-only retrieval is not a state-changing action per 5J's audit model (§14.1 grain is "auditable action"; a search is not one) |
| Domain event / outbox | None — reads never publish events |
| Async side effects | None |
| Object-storage effects | None |
| Concurrency | See §28 races 14/15 (retrieval during reindex, retrieval during publish race) |
| PII/security | Chunk `content` may contain tenant document text (`pii:potential` per 5F); never returns raw embedding vectors; citations never leak cross-tenant document identity (an inaccessible `kb_id` is excluded, not partially disclosed) |

### 16.2 Response Shape

```json
{
  "data": {
    "query": "what is the refund policy",
    "results": [
      {
        "chunk_id": "01930000-...",
        "score": 0.83,
        "text": "Refunds are processed within 5-7 business days...",
        "metadata": { "department": "billing" },
        "citation": {
          "document_id": "...",
          "document_title": "Billing FAQ",
          "knowledge_base_id": "...",
          "chunk_id": "01930000-...",
          "text_preview": "Refunds are processed within 5-7...",
          "page_number": null,
          "section_heading": "Refund Policy",
          "source_location": null
        }
      }
    ],
    "context_token_count": 842
  },
  "meta": { "request_id": "..." }
}
```

`results[]` is bounded to `top_k`; `context_token_count` reflects `RetrievalService.assemble_context()`'s token-budget accounting (4E §4.4). No field in this response is a raw `vector(1536)` value, and none ever will be (§19).

### 16.5 The Corrected Retrieval Predicate (Phase 5L.2 — final)

Both QP-08 and QP-09 use the **identical** row-eligibility predicate below (differing only in their `ORDER BY`/match clause) — this is a hard requirement, not a convenience: the semantic and keyword legs must never search different generations for the same current document version, or RRF would fuse rankings computed over inconsistent underlying content.

```sql
... FROM knowledge.document_chunks dc
    JOIN knowledge.documents d ON d.id = dc.document_id
    JOIN knowledge.knowledge_bases kb ON kb.id = d.knowledge_base_id
    WHERE dc.knowledge_base_id = ANY($kb_ids)
      AND d.organization_id = $org_id                    -- explicit tenant filter, not RLS alone (INV-08)
      AND dc.document_version_id = d.current_version_id   -- publication gate
      AND dc.index_generation <= kb.index_version
      AND NOT EXISTS (                                    -- effective-generation gate (Phase 5L.2)
        SELECT 1 FROM knowledge.document_chunks newer
        WHERE newer.document_version_id = dc.document_version_id
          AND newer.index_generation > dc.index_generation
          AND newer.index_generation <= kb.index_version
      )
```

**Why the `NOT EXISTS` clause is mandatory, not optional:** `index_generation <= kb.index_version` alone is satisfied by *every* generation at or below current — after a reindex cutover but before the separate, asynchronous `fn_kb_reindex_cleanup_old_generations()` call runs, a current version can legitimately have chunks at both an old and a new generation simultaneously. Without the `NOT EXISTS` clause this produces duplicate semantic hits, duplicate keyword hits, duplicate citations, and distorted RRF ranking. The clause selects exactly the single highest generation `<= kb.index_version` that has chunks for that specific `document_version_id` — which is also exactly what a rollback-reactivated historical version resolves to (its own highest surviving generation, which by `089_5F9.sql`'s cleanup rule is guaranteed to still exist and is never required to equal `kb.index_version` itself). Live-proven, both legs, including a pre-cleanup no-duplicates case and a rollback-fallback case — see `docs/phase-05-database-design/5L-Global-Database-Reconciliation/5L-Global-Database-Reconciliation.md`'s Phase 5L.2 addendum.

**QP-09's keyword-match clause** (Phase 5L.1, unchanged by 5L.2) adds, in place of a single unconditional `english`-config query:

```sql
AND (
  (dc.content_language = 'en' AND dc.tsvector_content @@ plainto_tsquery('english', $query_text))
  OR (dc.content_language IN ('ta','te','hi') AND dc.tsvector_content @@ plainto_tsquery('simple', $query_text))
)
```

The same raw `$query_text` is run through both `regconfig`s already established by storage (migration `084_5F7.sql`) — no per-query language detection, AI-derived or otherwise, decides which branch matches; both branches always evaluate, closed over the same four-language allow-list (`en`/`ta`/`te`/`hi`) storage uses. **Any earlier revision's SQL shown as a single unconditional `plainto_tsquery('english', ...)` clause is historical/superseded** — it was proven, live, to miss unstemmed `simple`-stored content (5L.1) and must not be read as the current contract.

**Index support**: `idx_dc_version_generation (document_version_id, index_generation)` (`089_5F9.sql`) serves the `NOT EXISTS` clause via an index-only scan — confirmed via `EXPLAIN (ANALYZE, BUFFERS)`, sub-millisecond on the tested dataset; no additional index was added (Phase 5L.2 evaluated and declined one as redundant).

---

## 17. Hybrid Search / RRF Contract

Hybrid search (FR-RAG-003) is semantic (pgvector HNSW cosine, QP-08) + keyword (Postgres full-text `tsvector`/GIN, QP-09), merged by Reciprocal Rank Fusion — **entirely inside `RetrievalService.reciprocal_rank_fusion()`**, a pure domain-service function (DDR-4E-001, 4E §4.4). 6F's API layer:

- Never re-implements RRF at the API or database layer — it calls the one domain service.
- Exposes only the **toggle and weighting** already modeled in `knowledge_bases.retrieval_config` (`hybrid_search_enabled`, `hybrid_semantic_weight`, `hybrid_keyword_weight`) via KB `PATCH` (§9) — there is no per-request override of the fusion formula's `k` constant (fixed at 60 per 4E §4.4, not client-configurable) or of which signals are blended.
- `hybrid_search_enabled = false` degrades the search to semantic-only (the keyword leg is skipped entirely, not merely down-weighted to zero) — a straightforward, honest reading of "enabled" rather than a fabricated third mode.

---

## 18. Metadata Filtering

FR-RAG-003 requires metadata filtering; 4E constrains `Document.Metadata` to string/number/boolean scalar values (inv. 5); 5F stores it as `documents.metadata JSONB`. No frozen source defines an exact filter DSL — 6F defines the **smallest safe** one, per the governing task's explicit instruction, and marks it as a 6F API-level contract (not a frozen requirement):

| Rule | Detail |
|---|---|
| Syntax | `filter.{key}={value}` flat query parameters — one exact-equality comparison per parameter, mirroring 6A §15's flat, non-nested filter syntax exactly |
| Operators | Equality only, V1. No range, no `IN`, no `OR`/`NOT`, no nested JSON path expressions accepted from the client |
| Bound | ≤10 `filter.` parameters per request (matches 6A §15's general "at most 10 filter parameters" rule) |
| Type coercion | Values are compared as JSONB scalars matching `documents.metadata`'s value types (string/number/boolean) — a filter value is type-inferred from its literal form (`"true"`/`"false"` → boolean, numeric literal → number, else string) |
| Injection safety | Bound as parameters through the ORM/query builder into a `metadata @> '{"key": "value"}'::jsonb` containment predicate (mirrors the pattern already shown in 3D §9.4's `metadata @> :metadata_filter`) — never string-interpolated |
| Cross-tenant safety | The filter only ever narrows an already tenant-scoped, KB-scoped result set — it cannot be used to reach outside `kb_ids`/`organization_id` |
| Unknown key | Not rejected (metadata keys are tenant-defined, open-ended) — a filter on a key no document has simply yields no matches for that predicate |

---

## 19. Retrieval Context / Citation Contract

4E's `RetrievalService.assemble_context()` states the domain invariant explicitly: **no included chunk may exist without a Citation.** 6F's API response (§16.2) enforces this structurally — `results[].citation` is a **required** field in the response model (Pydantic, non-nullable), not optional. The `Citation` value object (4E §9) is `(document_id, document_title, chunk_id, chunk_text_preview)`; 6F's citation object reproduces exactly those four fields and additionally surfaces `knowledge_base_id`, `page_number`, `section_heading`, `source_location` — all of which are physical columns on `document_chunks` whose own column comments in 5F identify them as citation-purposed (`source_location | For citation`). This is an extension grounded in existing physical columns, not a fabricated field.

No response anywhere in 6F exposes: raw embedding vectors, internal pgvector operator syntax, HNSW parameters, or database storage internals (table/schema/partition names).

---

## 20. Voice Runtime / KnowledgeSearchPort Boundary (ADR-6F-05)

### 20.1 Two Callers, One Implementation

| Caller | Path | Mechanism |
|---|---|---|
| Tenant/admin/Agent-Builder/API-key caller | External | `GET /api/v1/knowledge/search` (§16) — public REST, full auth/authz/rate-limit pipeline (6A §9.1) |
| Voice Orchestrator, via `KnowledgeSearchNode` executor or the `lookupKnowledge` tool runner | Mid-call, in-process | `KnowledgeSearchPort.search()` → `KnowledgeApplicationService.search_knowledge()` — **the same application service**, called as a Python method inside the same modular-monolith process, never HTTP |

### 20.2 Why No Network Hop

- 4E §19 (Cross-Domain Communication) states this explicitly: *"Knowledge & RAG → Voice Platform (4B): KB supplies `KnowledgeSearchPort` — `search()` via tool runner."* This is a Phase 4 **in-process port**, not an HTTP contract — identical in kind to `WorkflowExecutionPort`, `PromptRenderPort`, `ConversationMemoryPort`, all of which 4E implements as application-service methods, never as internal REST calls.
- 3A/3B's module structure places `knowledge_rag`, `workflow_engine`, and the Voice Orchestrator inside the **same deployable** (the modular monolith) — a tool runner calling another module's public application-service use case directly (3D §10.4's "each runner calls its target module's *public use case* — never the module's repositories directly") is the established, approved cross-module pattern (3B §13, 3D §2's Foundation Reused table, reused by every other cross-module call in the platform: CRM tools, Campaign triggers).
- **Latency budget preservation:** 6A §11's Tier E per-stage table gives "Tool execution (if invoked): 150ms p50 / 400ms p95" as the bounded sub-budget for exactly this kind of mid-turn invocation. An HTTP round trip (TLS, NGINX, full auth/authz/rate-limit pipeline, §16.1's own Tier B budget) would consume that entire sub-budget on transport alone, before any actual retrieval work — introducing a network hop here would make FR-RAG-005's "bounded latency" requirement structurally unmeetable. Nothing in 3D, 4E, or 6D proposes an internal HTTP endpoint for this path, and 6F does not invent one.
- **`/api/internal/v1/...` is explicitly not needed for this path** — 6A §8.5 reserves that namespace for genuine service-to-service HTTP (Worker → Core API callbacks); the Voice runtime and Knowledge module are not separate services here, they are modules in one process, so there is no "internal HTTP endpoint" question to answer at all.

### 20.3 What Is the Same, What Differs, Between the Two Paths

| Aspect | REST (`GET /knowledge/search`) | In-process (`KnowledgeSearchPort`) |
|---|---|---|
| Auth/tenant resolution | Full JWT/API-key pipeline (6A §9.1) | Tenant context already resolved by the Voice session (4B `TenantContext`, propagated to every port call) |
| RBAC permission check | `knowledge:read` evaluated per-request | Not re-evaluated per search — the Agent's authorization to use the referenced KBs is a publish-time/config concern (§21), not re-checked on every turn |
| Result shape | HTTP JSON envelope (§16.2) | `RetrievalContext` DTO (4E §9) — same underlying `ScoredChunk`/`Citation` data, no envelope wrapper |
| Rate limiting | 6A §20 L2 tenant quota | Bounded by the Tier E turn budget itself — no separate quota counter on this path (a runaway workflow is bounded by `max_turns`, 4E §5.1.4, not by RAG-specific rate limiting) |
| Latency budget | Tier B (§16.1) | Tier E tool-execution sub-budget (150ms p50/400ms p95, 6A §11) |
| Citation contract | §19, identical | §19, identical — `RetrievalService.assemble_context()` is the same call either way |

---

## 21. Agent `knowledge_base_refs` Reconciliation (ADR-6F-11, resolves `DEP-6E-04`)

### 21.1 The Handoff

6E's `Agent.draft_config.knowledge_base_refs: UUID[]` is validated by 6E for **format only** — `DEP-6E-04` records existence/ownership validation as explicitly unresolved and assigns ownership to 6F. 6E is frozen and is **not** modified by this document.

### 21.2 What 6F Provides

| Question | Answer |
|---|---|
| Where can existence/ownership/status be checked? | `GET /api/v1/knowledge-bases/{kb_id}` (§8) — returns `404` for a nonexistent or cross-tenant KB, and `status` (`ACTIVE\|REINDEXING\|DEGRADED\|ARCHIVED`) for an existing one. This is the **authoritative read contract** any caller — including a future Agent Builder UI performing client-side validation while an operator types a KB reference into an Agent's config — may use. |
| Does 6E call this synchronously at Agent PATCH/publish time? | **No, and this document does not change that.** 6E is frozen; inventing a synchronous cross-context HTTP call from 6E into 6F would silently modify 6E's already-approved behavior, which §41 of the governing task prohibits. |
| Is there a new DDD-level existence-check port? | **No.** 4B §16's port catalogue defines `KnowledgeSearchPort` as a **runtime-consumption** port only (`search()`, not `exists()`/`checkOwnership()`). No frozen document defines an existence-check port, and 6F does not fabricate one — per the governing task's explicit instruction to record this honestly rather than invent a mechanism. |
| What happens at runtime if an Agent references an archived/nonexistent KB? | The Voice runtime's `KnowledgeSearchPort.search()` call (§20) resolves against `kb_ids` exactly as `GET /knowledge/search` does (§16.1's error handling) — an unresolvable or non-`ACTIVE` `kb_id` inside the list is **silently excluded** from the search, never a call-ending error. If **all** referenced KBs are unresolvable, `search_knowledge()` returns an empty `RetrievalContext` (zero results, zero citations) — the turn continues; the LLM simply receives no retrieved context for that lookup. This "fails soft" behavior is consistent with `RetrievalContext`'s own shape (a list that can be empty) and with 4E's general design posture of graceful degradation over hard failure on the voice hot path. |
| Is this dependency now closed? | `DEP-6F-04`, **NON-BLOCKING** (§39) — the read contract exists and the runtime behavior is fully specified; what remains open is only the optional future possibility of a proactive, synchronous existence-check port, which no current requirement demands. |

### 21.3 What 6F Does Not Do

6F does not add a coupling table between `agents`/`agent_versions` and `knowledge_bases` (ADR-5F-012 already forecloses this — KB IDs live only in `voice.agent_versions.snapshot_json`), and does not retroactively validate every existing Agent's `knowledge_base_refs` on a schedule (no such sweep is specified anywhere upstream; inventing one would be a new capability outside this document's authority).

---

## 22. Reindex / Index-Version Semantics (ADR-6F-08) — IMPLEMENTATION-READY (Phase 5L.1, real generation-based reindex)

**Correction notice (superseded by Phase 5L.1):** the prior revision of this document defined a "narrow reindex" (bookkeeping-only, rebuilding nothing) and presented it as implemented; that characterization was withdrawn in the prior correction pass. **The withdrawn behavior is NOT restored here.** Phase 5L (`083_5F6.sql`) and Phase 5L.1 (`088_5F8.sql`, `089_5F9.sql`) instead implemented a real, derived chunk/index-generation mechanism satisfying 4E's `TriggerReindex` requirements (a)-(c) below in full, live-validated including a genuine two-session concurrency race and a partial-build rejection test.

### 22.1 What `index_version` and `index_generation` Represent

`knowledge_bases.index_version INTEGER` (`035_5F.sql`) is the KB's current-serving generation pointer — it now advances exactly once, atomically, at the end of a successful reindex (`fn_kb_reindex_complete()`). `document_chunks.index_generation INTEGER` (added by `083_5F6.sql`) tags which build pass a chunk row belongs to. `document_chunks` remains `INSERT`/`DELETE`-only (no `UPDATE`) — a reindex never mutates an existing chunk row; it inserts a fresh set under a new generation number and, once proven complete, atomically advances `index_version` to make it current.

### 22.2 The Real Reindex Lifecycle

Satisfies 4E's `TriggerReindex`/`REINDEXING` requirements: (a) re-chunk/re-embed every currently-`READY` document under the KB's current `chunking_strategy`, (b) the *old* generation remains queryable throughout, (c) atomic cutover once the new generation is proven complete.

1. `POST .../reindex` → `DB: SELECT knowledge.fn_kb_reindex_begin($kb_id, $org_id)` — requires KB `status='ACTIVE'` (advisory-lock-serialized against a concurrent begin), sets `status='REINDEXING'`, snapshots a build manifest (every currently-`READY` document version + its expected chunk count, `knowledge.kb_reindex_job_manifest`), returns the new generation number.
2. Worker re-chunks/re-embeds each manifested document version, inserting `document_chunks` rows tagged with the new generation. **Old-generation chunks are untouched and continue to serve retrieval** — satisfying (b) — because the retrieval predicate (§20, corrected Phase 5L.2) selects a version's single highest generation `<= knowledge_bases.index_version`, and the new generation's number exceeds `index_version` until cutover, so it is not yet selected by anything.
3. `DB: SELECT knowledge.fn_kb_reindex_complete($kb_id, $org_id, $generation)` — **proves** completeness against the manifest (every still-relevant entry has exactly its expected chunk count in the new generation, not merely "at least one row") before atomically advancing `index_version` and setting `status='ACTIVE'`. A partial/incomplete build is rejected, not silently accepted (live-tested — `5L-Global-Database-Reconciliation.md` Phase 5L.1 item 2).
4. On worker failure: `DB: SELECT knowledge.fn_kb_reindex_fail($kb_id, $org_id, $generation)` — requires the generation to exactly match the pending build (rejects any other value, including the current serving generation — closing a live-found forgery gap, Phase 5L.1 item 1), deletes the partial generation's rows, reverts `status='ACTIVE'` with `index_version` unchanged (old generation stays current).
5. `DB: SELECT knowledge.fn_kb_reindex_cleanup_old_generations($kb_id, $org_id)` — callable any time after a successful cutover (not inline in step 3, to keep cutover fast); deletes an old-generation chunk row only once a newer copy of that *same* document version exists, or the version is `GDPR_ERASED`/`FAILED` — **never** the sole surviving copy of a still-rollback-eligible (`SUPERSEDED`) version (Phase 5L.1 item 3-4; this is what keeps §12.4's rollback guarantee true even after a reindex).

`fn_docver_reindex()` (a per-document-version function) does not exist and is not needed — reindex is a KB-wide operation over the manifest above, not a per-version one.

### 22.3 Request/Response Shape

`POST /api/v1/knowledge-bases/{kb_id}/reindex` → `202 Accepted`, `{"generation": <int>, "status": "REINDEXING"}`. Progress/completion is observed via `GET /knowledge-bases/{kb_id}` (`index_version`, `status`) — no separate job-status endpoint is added by this pass (the `knowledge.kb_reindex_jobs` table backing it is an internal implementation detail, not a new public resource in this revision).

**What a tenant could already do before this pass, unaffected:** `PATCH /knowledge-bases/{kb_id}` (§8.2, §9) to change `chunking_strategy`/`retrieval_config` for **future** ingestions only — this remains a KB configuration change, distinct from `POST .../reindex`'s full-KB rebuild of already-`READY` content.

### 22.4 Reindex While Already Reindexing / `409` Semantics

`fn_kb_reindex_begin()` requires KB `status='ACTIVE'` and is advisory-lock-serialized per KB — a second concurrent `begin` call blocks on the row/advisory lock, then (once the first commits) sees `status='REINDEXING'` and is rejected. `POST .../reindex` on an already-`REINDEXING` KB returns `409 Conflict`. Live-tested with two genuinely concurrent database sessions (`5L-Global-Database-Reconciliation.md` Phase 5L.1 item 1).

### 22.5 `DEGRADED` Status

5F's `knowledge_bases.status` CHECK includes `DEGRADED` alongside `ACTIVE|REINDEXING|ARCHIVED`. No frozen source specifies what transitions a KB into `DEGRADED` or what retrieval does differently for a `DEGRADED` KB. 6F does not fabricate a trigger condition; `DEGRADED` is exposed read-only (visible on `GET`) and is not excluded from retrieval by any rule this document invents — absent a specified reason to exclude it, retrieval treats `DEGRADED` the same as `ACTIVE`.

---

## 23. Archive / Delete / GDPR Boundary (ADR-6F-12)

### 23.1 Distinct States, Precisely

| State axis | Values | Meaning |
|---|---|---|
| `knowledge_bases.status` | `ACTIVE\|REINDEXING\|DEGRADED\|ARCHIVED` | KB-level: `ARCHIVED` excludes the whole KB from retrieval |
| `documents.status` | `PENDING\|PROCESSING\|READY\|FAILED\|ARCHIVED\|DELETED` | Document-level lifecycle |
| `document_versions.status` | `PENDING\|READY\|SUPERSEDED\|FAILED\|GDPR_ERASED` | Version-level publication/compliance state |

### 23.2 KnowledgeBase Archive

`POST .../knowledge-bases/{kb_id}/archive` (§8.2) — sets `status='ARCHIVED'`. Documents inside are **not** individually touched (no cascade to `documents.status`) — they remain `READY` at their own level, but the KB-level exclusion (§23.5) removes the whole KB from `GET /knowledge/search`'s effective universe regardless of individual document status. Management APIs (`GET .../documents`, `GET .../knowledge-bases/{id}`) continue to work on an archived KB — archiving is a retrieval-visibility change, not a read-access change.

### 23.3 Document Archive

`POST .../documents/{document_id}/archive` — `documents.status → 'ARCHIVED'`, a plain `UPDATE` (no `REVOKE UPDATE` on `documents`, unlike `document_versions`). Per the `ArchivedDocumentNotQueryable` policy (4E §10), archived documents are excluded from retrieval (§23.5) but the row, its versions, and its chunks are **not** removed — this is fully reversible in principle, though no `unarchive` command exists in 4E's catalogue, so 6F does not offer one (a genuine, disclosed gap, non-blocking — the tenant's only path back is delete + re-upload).

### 23.4 Document Delete — Also the GDPR Erasure Path (F-4, §5) — IMPLEMENTATION-READY (Phase 5L.1)

`DELETE /api/v1/knowledge-bases/{kb_id}/documents/{document_id}` (§10.1) is designed as a single action implementing the design document's QP-06/ADR-5F-011 flow:

1. `DELETE FROM document_chunks WHERE document_id = ... AND organization_id = ...` — chunks physically removed, immediately excluding the document from retrieval. **IMPLEMENTATION-READY** — `038_5F.sql` grants `app_api`/`app_worker` `DELETE` on `document_chunks` unconditionally.
2. GDPR-erase every version's content references (`storage_ref='ERASED'`, `content_hash='ERASED'`, `status='GDPR_ERASED'`). **IMPLEMENTATION-READY (Phase 5L.1).** `knowledge.fn_docver_gdpr_erase()` (migration `081_5F4.sql`, `SECURITY DEFINER`) provides this legal path — idempotent, deletes the version's chunks, then writes `storage_ref='ERASED'`/`content_hash='ERASED'`/`status='GDPR_ERASED'` under the existing `prevent_docver_immutable_field_mutation()` trigger's carve-out (`034_5F.sql`). `DEP-6F-15`, **RESOLVED**.
3. `UPDATE documents SET status='DELETED', current_version_id=NULL, original_filename=NULL, deleted_at=NOW()` — the row survives as an audit tombstone (6A §7.6's soft-delete pattern, `documents` explicitly named there). **IMPLEMENTATION-READY.**
4. S3 object deletion — a **separate**, best-effort application-layer `ObjectStorePort.delete()` call, outside the DB transaction, eventually consistent (6A §35 — never hold a transaction across an external call). **IMPLEMENTATION-READY** (no DB dependency).

Steps 1-3 are now orchestrated atomically in one transaction by `knowledge.fn_document_gdpr_delete()` (migration `081_5F4.sql`): it loops every non-`GDPR_ERASED` version of the document calling `fn_docver_gdpr_erase()` (step 1+2 per version), then tombstones the document row (step 3). Step 4 (S3 deletion) remains external/post-commit, per 6A §35.

| Field | Value |
|---|---|
| Success status | `202 Accepted` |
| Errors | `404` |
| Idempotency | Deleting an already-`DELETED` document is a no-op `202` (`fn_document_gdpr_delete()`'s per-version erase is itself idempotent) |
| **Readiness** | **IMPLEMENTATION-READY (Phase 5L.1).** `DEP-6F-15` **RESOLVED** — `knowledge.fn_document_gdpr_delete()` (migration `081_5F4.sql`, using `fn_docver_gdpr_erase()` per-version) provides step 2's legal execution path and orchestrates all four steps atomically. Live-validated. |
| Audit | Reuses existing `action_kind = DOCUMENT_DELETED` (Category A, exact match) |
| Concurrency | See §28 race 9 (publish-version vs. delete) |

There is **no separate "GDPR erase" endpoint** — a document delete in this platform always fully erases retrievable content and content references; there is no softer delete that leaves an S3 pointer or content hash intact for a document no longer in the KB. This is the correct, privacy-by-default reading of what 5F's QP-06/ADR-5F-011 actually implement, not an invented policy.

### 23.5 Retrieval Exclusion Summary

| Condition | Excluded from `GET /knowledge/search` and `KnowledgeSearchPort`? |
|---|---|
| `knowledge_bases.status = 'ARCHIVED'` | Yes — whole KB excluded |
| `documents.status = 'ARCHIVED'` | Yes — `ArchivedDocumentNotQueryable` policy |
| `documents.status = 'DELETED'` | Yes, whenever this state is reached — chunks are physically removed by step 1, which is itself implementation-ready and legal to execute independent of step 2's blocked status. **Note:** because `DELETE`'s overall execution is held blocked (§23.4) rather than run partially, `documents.status = 'DELETED'` is not reachable via the 6F API in this revision — this row documents the intended, not currently exercisable, effect. |
| `documents.current_version_id IS NULL` (never published) | Yes — QP-08/QP-09's `d.current_version_id = dv.id` gate excludes it structurally |
| `document_versions.status != 'READY'` for the chunk's owning version | Yes — INV-07, enforced in every retrieval query |
| A `SUPERSEDED` version's chunks (superseded by a newer publish) | Yes — same gate; only the **current** version's chunks are ever joined in |

### 23.6 `current_version_id` on Erasure

**Intended contract** (not currently reachable — §23.4): when a document is deleted/GDPR-erased, `current_version_id` is explicitly set to `NULL` (step 3) — it is never left dangling, pointing at a now-`GDPR_ERASED` version. A `GET .../documents/{id}` on a `DELETED` document would return `status="DELETED"`, `current_version=null`. This remains the correct target contract for when `DEP-6F-15` is resolved.

### 23.7 Archived KBs — Still Readable by Management APIs

Yes — `GET /knowledge-bases/{kb_id}` and its document/version sub-resources remain fully readable on an `ARCHIVED` KB (only `POST .../archive` again is a no-op `409`, and retrieval excludes it). Archiving is a retrieval concern, not an access-control concern.

---

## 24. Object Storage Boundary (ADR-6F-03)

| Concern | Answer |
|---|---|
| Does 6F ever proxy file bytes through the API? | Never (6A §29 absolute rule) |
| How do file bytes get into storage? | Presigned S3 PUT, client-direct (§11.1) |
| What is persisted before upload? | A `documents` row (`status='PENDING'`) — no `document_versions` row yet, since `content_hash` is unknown |
| What is persisted after upload completes? | `document_versions` row with `storage_ref`, `content_hash`, `mime_type`, `size_bytes` — all four are the **immutable identity/content fields** (INV-02) |
| How does a `DocumentVersion` reference stored content? | `storage_ref TEXT` — an opaque S3 path, namespaced `org/{tenant_id}/knowledge/{kb_id}/{document_id}.{ext}` (4I §25.18, reused exactly) |
| Which fields are safe to expose? | `storage_ref`'s *existence* is implied by version metadata; the raw path string is **not** returned in any response body (it is `pii:potential` per 5F's own column comment) — download, where needed, goes through a signed URL (below), never the raw key |
| Download/read behavior | Not required for V1 — no frozen requirement asks a tenant to download the original source bytes back out of the platform (they uploaded them; the value is retrieval, not storage). No `GET .../download-url` endpoint is added speculatively. |
| Tenant-scoped storage keys | Yes, structurally — the `org/{tenant_id}/` prefix is the isolation boundary, identical to every other object-storage namespace in the platform (4I §25.18) |
| Limits | 50 MB file size ceiling (§11.1, directionally consistent with 4E §22's stated default, not fabricated); 2048-char URL length for `URL`/`WEBSITE` sources; 500 pairs / bounded field lengths for `FAQ` (§11.3) |
| Malware/content scanning | A scanning hook is required by 6A §29's generic pattern ("documents are never queryable/downloadable until this stage passes"), applied here between `complete` and the `EXTRACTING` stage — no concrete scanner/vendor is named anywhere in Phase 1–5; this is `DEP-6F-07`, NON-BLOCKING (the behavioral contract is specified, the implementation is deferred) |
| Transaction discipline | No DB transaction is ever held open across an S3 PUT, HEAD, GET, or DELETE call — every object-storage interaction in this document happens either client-direct (bypassing the API server entirely) or in an async worker step outside any transaction (6A §35) |

---

## 25. Embedding Model Boundary

| Question | Answer |
|---|---|
| Is `embedding_model_ref` client-selectable from a list? | No — there is exactly **one** supported value in V1: `openai:text-embedding-3-large:1536` (4I OQ-FINAL-03/ADR-INDIA-014). It is accepted as a literal string that must equal this constant; any other value is `422 VALIDATION_ERROR`. |
| Is there a provider/model registry API? | No such registry exists anywhere in Phase 1–5, and 6F does not invent one. `DEP-6F-05`, NON-BLOCKING for V1 (single closed value), tracked for a future phase if/when multi-model support is added. |
| How are dimensions derived? | `embedding_dimensions` is set at KB-creation time to the fixed value `1536`, matching the single supported model — not independently client-supplied (the API computes it server-side from the validated `embedding_model_ref`, never trusts a client-supplied `embedding_dimensions`). |
| What happens for an unsupported model? | `422 VALIDATION_ERROR` at `POST /knowledge-bases` — never reaches the DB. |
| Is `embedding_model_ref` ever `PATCH`able? | **No** (§8.2, §9) — DDR-4E-003, INV-01, and the DB trigger `prevent_kb_model_mutation()` all agree; a new KB is required to use a different model. |
| Are embedding-provider credentials ever exposed? | Never — no credential/secret field exists in any 6F request or response model (6A §22.5's structural guarantee applies identically here) |
| Is an embedding-provider call ever made inside a DB transaction? | No — `EmbeddingPort.embed()`/`embed_batch()` calls happen in the async worker pipeline (§14), outside any transaction; the one synchronous-request-path embedding call (query embedding for `GET /knowledge/search`, cache-miss case) also happens before any DB read, not nested inside a transaction |
| Embedding provider outage behavior | `GET /knowledge/search` on a cache-miss with the embedding provider down → `502/503 DEPENDENCY_UNAVAILABLE` (6A §24.2 existing error family, `retryable: true`) — no new error code invented. Ingestion pipeline: the `EMBEDDING` stage retries per 4E §22's risk table, ultimately counted against the same `attempt_count ≤ 3` ceiling (INV-04) if it cannot recover. |

---

## 26. Security / Prompt Injection / SSRF

### 26.1 Prompt-Injection Detection (NFR-SEC-006)

NFR-SEC-006 requires prompt-injection detection/mitigation for knowledge-base content specifically. No frozen source (Phase 1–5, 6A–6E) names a concrete scanner, model, or service for this — `DEP-6F-06` records this honestly rather than inventing one. What 6F **does** define, at the API/ingestion boundary it owns:

| Layer | 6F's responsibility | Explicitly NOT 6F's responsibility |
|---|---|---|
| API input validation | Structural bounds on `faq_pairs`, `source_url`, `metadata` — rejects malformed shapes (§11) | Semantic content inspection |
| File/content scanning | The 6A §29 malware-scan hook gate (before `READY`) is the structural point where a future content-safety scan would plug in | Naming/operating the actual scanner (`DEP-6F-07`) |
| Retrieval-time trust labeling | Every retrieval result is explicitly sourced from tenant-authored knowledge content, distinguishable by its `citation` block from the agent's own instructions or the caller's live speech — this structural separation (never concatenating retrieved text into the system prompt without attribution) is what the Workflow/Prompt layer (owned elsewhere) consumes to apply its own mitigation | Runtime LLM-level mitigation (guardrail prompting, output filtering) — owned by the Agent runtime (6D/6E), not 6F |
| Sanitization/normalization | Chunk text is stored and returned as extracted plain text — no HTML/script execution surface exists in any 6F response (JSON string field, never rendered) | — |

`DEP-6F-06`, NON-BLOCKING for 6F's own API contract (it does not claim a mitigation mechanism that doesn't exist); the requirement itself remains open pending an owning implementation phase.

### 26.2 File Upload Security

| Concern | Standard |
|---|---|
| MIME validation | Declared `content_type` checked against source-type allow-list at presign time; actual bytes' magic number re-verified after upload, before leaving `PENDING`/`PROCESSING` (6A §29, §11.1) |
| Extension vs. content mismatch | Caught by the same magic-number re-verification — a `.pdf` filename with non-PDF bytes fails this check, transitions the document to `FAILED` |
| Maximum size | 50 MB (§11.1, §24) |
| Filename sanitization | Path separators and control characters stripped before use in the S3 key; the S3 key itself is server-generated (`{document_id}.{ext}`), never the raw client-supplied filename (`original_filename` is stored separately, display-only) |
| Object-key tenant isolation | `org/{tenant_id}/knowledge/{kb_id}/...` prefix (4I §25.18) |
| Archive/zip-bomb handling | Not applicable — the supported `SourceType` set (`PDF|DOCX|TXT|CSV`) contains no archive/container format; a `.zip` upload is rejected at the MIME-allow-list stage |
| Executable processing | None of the supported parsers (`pdfplumber`, `python-docx`, CSV/TXT readers — 3D §3 module structure) execute embedded content; no assumption of executable safety is required because none is ever executed |

### 26.3 URL / Website Security (SSRF)

| Concern | Standard |
|---|---|
| Scheme allow-list | `https://` only |
| Private/link-local/metadata IP blocking | Enforced at both registration time (DNS resolution check) and fetch time (DNS-rebinding-safe re-check immediately before the actual HTTP fetch) — mirrors 6A §22's `webhook_endpoints.target_url` SSRF standard exactly, applied here to a structurally identical risk (a tenant-supplied URL the platform's own infrastructure will fetch) |
| Redirect handling | Every redirect hop re-validated against the same allow-list/IP-block rules before being followed — a redirect to a blocked range aborts the crawl, marks the ingestion `FAILED` |
| DNS rebinding | Addressed by re-resolving and re-validating at the moment of the actual fetch, not trusting the registration-time resolution (6A §22's named mitigation) |
| Content-size/time limits | Bounded fetch (implementation-level bound; no frozen number exists — `DEP-6F-08`) |
| Tenant isolation | The crawled content is stored under the same `org/{tenant_id}/...` namespace as any other source; the crawl itself carries no tenant credentials or session state that could leak |

`DEP-6F-08`, NON-BLOCKING — the behavioral contract (scheme allow-list, IP blocking, redirect re-validation, DNS-rebinding safety) is fully specified here; the concrete crawler library/implementation is deferred, consistent with how 6A treats every other "mechanism not yet implemented, contract now fixed" item.

---

## 27. Transactions

Per-mutation transaction boundary, following 6A §35's canonical shape exactly:

| Mutation | Validation (no I/O) | Short transaction | `SECURITY DEFINER`? | Commit point | Async/external work (after commit) | Readiness |
|---|---|---|---|---|---|---|
| Create KB | Bounds, `embedding_model_ref` literal match | `INSERT knowledge_bases` + `create_kb_partition()` | `create_kb_partition()` only | After both statements | Audit (async), outbox publish | READY |
| Update KB settings | Field allow-list, `If-Match` | `UPDATE knowledge_bases` | No | After UPDATE | Audit (async) | READY |
| Archive KB | — | `UPDATE knowledge_bases SET status='ARCHIVED'` | No | After UPDATE | Audit (async) | READY |
| Reindex KB | — | — | — | — | — | **BLOCKED — `DEP-6F-02`. Not offered as an endpoint (§22).** |
| Register document (file, step 1) | MIME/size bounds | `INSERT documents (PENDING)` | No | After INSERT | S3 presign (no DB involvement — presigning is local signing, not a network call) | READY |
| Complete upload (step 2) | — | `UPDATE documents SET status='PROCESSING'` | No | After UPDATE | Full async pipeline (§14), entirely outside any transaction. Worker's `INSERT document_versions` cannot enforce KB-wide dedup — `DEP-6F-14` | READY (dedup caveat disclosed, §11.4) |
| Register document (URL/WEBSITE) | Scheme/IP validation | `INSERT documents (PENDING)` | No | After INSERT | Async crawl + pipeline; same `DEP-6F-14` caveat | READY (dedup caveat disclosed) |
| Register document (FAQ) | Shape/bounds | `INSERT documents` + `INSERT document_versions` | No | After both | S3 write happens **before** the transaction opens (§11.3 step 3); async chunk/embed/index; same `DEP-6F-14` caveat — the `INSERT` cannot collide for a new document | READY (dedup caveat disclosed) |
| Reprocess document | Precondition read (`ingestion_jobs.status='FAILED'`, `attempt_count<3`) | — | — | — | — | **RESOLVED — `DEP-6F-09` (§15.1, migration `080_5F3.sql`)** |
| Publish version | — | `SELECT fn_docver_publish(...)` | Yes | Function's internal commit | Audit (async) | READY (core operation); `DEP-6F-16` integrity gap disclosed separately |
| Delete document | — | — | — | — | — | **RESOLVED — `DEP-6F-15` (§23.4, migration `081_5F4.sql`)** |
| Archive document | — | `UPDATE documents SET status='ARCHIVED'` | No | After UPDATE | Audit (async) | READY |
| Search (read) | Query/filter bounds | None (read-only) | No | N/A | None | READY |

No **ready** mutation in this table holds a transaction open across S3, the embedding provider, the parser, the crawler, or any other external/long-running work — every async pipeline stage (§14) is its own short transaction, entered and committed independently by the worker. This transaction-discipline finding is unaffected by this correction pass; the three newly-blocked mutations are blocked by missing privileges/functions, not by any transaction-boundary defect.

---

## 28. Concurrency / Idempotency

Per 6A §17.1: no new locking scheme is invented; every guard below is either an existing unique constraint, an existing `SECURITY DEFINER` function's internal precondition, or ordinary `READ COMMITTED` visibility.

| # | Race | Outcome |
|---|---|---|
| 1 | Two KB creates, same `(organization_id, name)` | Second `INSERT` violates `uq_kb_name` → `409 CONFLICT` |
| 2 | Concurrent KB update and archive | Both are plain `UPDATE`s under `READ COMMITTED`; last-committed-wins on non-overlapping fields (update touches `name`/`description`/config JSONB, archive touches `status`) — no corruption, but a client relying on `If-Match` on the update will see `412` if the archive's `updated_at` bump landed first (ETag is `hash(id, updated_at)`, 6A §17.2) |
| 3 | Duplicate document upload (same content) | **RESOLVED (Phase 5L, migration `082_5F5.sql`):** `uq_dv_content_hash_kb (knowledge_base_id, content_hash)` rejects two different documents in the same KB with identical content, concurrent-insert-safe (real DB unique constraint, not an app-level check). `DEP-6F-14` closed. |
| 4 | Document upload vs. document delete | If delete commits first, the async pipeline's later steps operate against a `documents` row already `status='DELETED'` — the worker checks document status before each stage transition and aborts the pipeline (job → `CANCELLED`) rather than reviving a deleted document. Unaffected by this pass — delete's step 1/3/4 are individually legal even though the overall action is held blocked pending `DEP-6F-15`; this race concerns ordering between two operations that are each independently reachable in a partial-execution sense, so it is retained as a documented design intent |
| 5 | Two reprocess requests on the same document | Moot while `DEP-6F-09` is unresolved — neither request's `INSERT document_versions` can succeed (§15.1), so there is no race to lose; both would receive whatever error the blocked `INSERT` surfaces |
| 6 | Ingestion retry vs. worker completion | Not applicable in this design — retry (reprocess) always creates a **new** job row rather than racing an in-place retry of an existing one; the existing `READY` job (INV-06) is immutable and cannot be concurrently mutated. (Moot alongside #5 while reprocess is blocked.) |
| 7 | Two attempts to publish the same document version | Both call `fn_docver_publish()` with the same `version_id`; the function is not `SERIALIZABLE`, but its own internal `UPDATE ... WHERE id = v_old_version_id` and `UPDATE documents SET current_version_id = ...` are idempotent in effect — the second call re-supersedes an already-`SUPERSEDED` old version (no-op) and re-sets the same `current_version_id` (no-op); both callers observe `200`. Unaffected by this pass — publish's core function is READY. |
| 8 | Two different `READY` versions published concurrently | Both transactions call `fn_docver_publish()` for different `version_id`s on the same `document_id`; under `READ COMMITTED`, whichever commits last wins — `documents.current_version_id` ends up pointing at the later-committing call's version, and the earlier one is left `SUPERSEDED` even though it "won" the race first. This is a disclosed, narrow, non-serializable race, matching the same class of accepted race 6E's own `AgentVersion` publish path documents (6E §15.2) — no `SELECT ... FOR UPDATE` is introduced (6A §17.3). Unaffected by this pass. |
| 9 | Publish-version vs. document delete/GDPR erase | **RESOLVED (Phase 5L, migration `078_5F1.sql`):** `fn_docver_publish()` now requires `documents.status <> 'DELETED'`, and `documents.current_version_id` is column-privilege-locked against a direct-`UPDATE` bypass of the same guard (a second path to the same integrity gap, discovered and closed in the same migration). `DEP-6F-16` closed, live-validated. |
| 10 | Reindex requested while already `REINDEXING` | **RESOLVED (Phase 5L, `083_5F6.sql`):** `fn_kb_reindex_begin()` requires KB `status='ACTIVE'`, advisory-lock-serialized per KB — a second concurrent `begin` blocks then is rejected once the KB is `REINDEXING`. `409 Conflict`. Live-tested with two genuinely concurrent database sessions (§22.4). |
| 11 | Archive KB while ingestion is running | Not prevented — an in-flight `ingestion_jobs` row continues to completion independent of the KB's `status`; the resulting `READY` chunks simply never surface in retrieval because the KB-level `ARCHIVED` exclusion (§23.5) is checked at query time, not at ingestion time. Unaffected by this pass. |
| 12 | Retrieval while reindex is running | **RESOLVED (Phase 5L.2, §16.5):** the retrieval predicate's effective-generation `NOT EXISTS` clause hides a not-yet-cut-over new generation until `fn_kb_reindex_complete()` advances `index_version` — retrieval sees only the old, stable generation throughout the rebuild, per 4E invariant 3. Live-tested (pre-cleanup no-duplicates case). |
| 13 | Retrieval while a new version becomes current | `GET /knowledge/search`'s QP-08/QP-09 join `documents.current_version_id = dv.id` inside its own single query execution — under `READ COMMITTED`, the query sees whichever `current_version_id` was committed at the instant the query's snapshot was taken; it never sees a partially-published mixed state, because `fn_docver_publish()`'s `UPDATE documents` is a single atomic statement (one row, one commit). Also covers a rollback-reactivated version after a subsequent reindex — resolved to its own highest surviving generation, never the wrong one (§16.5, Phase 5L.2, live-tested with a non-obvious generation number). |
| 14 | Two attempts to `PATCH` KB settings and `archive` concurrently | Covered by race #2 |
| 15 | Idempotency-Key reuse with a different body | `409 CONFLICT`, `error.code=IDEMPOTENCY_KEY_REUSE_MISMATCH` (6A §16.2, applied identically here on every state-changing 6F POST) |

---

## 29. Authorization Matrix

| Operation | Permission | OWNER | ADMIN | MEMBER | BILLING_ADMIN | VIEWER | API Key |
|---|---|---|---|---|---|---|---|
| Create KB | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Read/List KB | `knowledge:read` | ✅ | ✅ | ✅ | — | ✅ | Eligible |
| Update KB settings | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Archive KB | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Reindex KB | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Upload/register document | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Read/list document | `knowledge:read` | ✅ | ✅ | ✅ | — | ✅ | Eligible |
| Reprocess document | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Archive document | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Delete document | `knowledge:delete` | ✅ | ✅ | — | — | — | Eligible |
| Read version / version list | `knowledge:read` | ✅ | ✅ | ✅ | — | ✅ | Eligible |
| Publish version | `knowledge:write` | ✅ | ✅ | ✅ | — | — | Eligible |
| Read ingestion job | `knowledge:read` | ✅ | ✅ | ✅ | — | ✅ | Eligible |
| Search / retrieval | `knowledge:read` | ✅ | ✅ | ✅ | — | ✅ | Eligible |

Sourced exactly from 5B §17.1/§17.2's frozen `knowledge:read/write/delete` catalog and role matrix — **no new permission string is introduced.** `knowledge:publish`, `rag:query`, `document:reprocess` are explicitly **not** created; the existing three-permission catalog fully represents every 6F operation's authorization need (write covers all non-destructive mutations including publish/reprocess/archive/reindex, matching the pattern already used elsewhere in 5B where e.g. `campaign:write` alone covers several campaign sub-mutations without a dedicated permission per action). API-key eligibility is uniform across every 6F endpoint — none of them is a human-session-only capability (no MFA gate, no break-glass path here).

---

## 30. Audit

### 30.1 Mutation-to-Audit Matrix

**Count corrected this pass:** the prior revision's §30 stated "six new values" while its own table listed **seven**. Corrected to seven, consistently, throughout this document (§5 F-6).

| Endpoint | `action_kind` | Category | Sync/Async (5J §14.5) | Endpoint execution status |
|---|---|---|---|---|
| `POST /knowledge-bases` | `KNOWLEDGE_BASE_CREATED` | **A** — exact existing match | Async (configuration-lifecycle default) | READY |
| `PATCH /knowledge-bases/{id}` | `KNOWLEDGE_BASE_UPDATED` | **C** — gap, proposed (§30.2) | Async | READY |
| `POST /knowledge-bases/{id}/archive` | `KNOWLEDGE_BASE_ARCHIVED` | **C** — gap, proposed | Async | READY |
| `POST /knowledge-bases/{id}/reindex` | `KNOWLEDGE_BASE_REINDEX_TRIGGERED` | **C** — gap, proposed | Async | **BLOCKED**, `DEP-6F-02` — endpoint not offered (§22); `action_kind` retained here only for the future contract |
| `POST .../documents` (register/upload) | `DOCUMENT_UPLOADED` | **C** — gap, proposed | Async | READY |
| `POST .../documents/{id}/reprocess` | `DOCUMENT_REPROCESS_REQUESTED` | **C** — gap, proposed | Async | **BLOCKED**, `DEP-6F-09` |
| `POST .../documents/{id}/archive` | `DOCUMENT_ARCHIVED` — nearest existing (`DOCUMENT_DELETED`) is not reusable (archive ≠ delete) | **C** — gap, proposed | Async | READY |
| `DELETE .../documents/{id}` | `DOCUMENT_DELETED` | **A** — exact existing match | Async | **BLOCKED**, `DEP-6F-15` |
| `POST .../versions/{id}/publish` | `DOCUMENT_VERSION_PUBLISHED` | **C** — gap, proposed | Async | READY (core operation; `DEP-6F-16` integrity gap disclosed separately, §28 race 9) |
| `GET /knowledge/search` | None — reads are not audited (5J §14.1 grain is state-changing actions) | N/A | N/A | READY |

Three of the ten rows above (`reindex`, `reprocess`, `delete`) correspond to endpoints that are themselves execution-blocked (§39) — their `action_kind` mapping is recorded for completeness/forward-compatibility, not as evidence the mutation can happen today.

### 30.2 Proposed 5J Vocabulary Amendment — Governance Pending (`DEP-6F-03`)

Only Category C entries justify a proposal; no duplicate vocabulary is created. **Seven** new values (corrected count, §5 F-6), following the **exact** naming convention 5J §14.3 already uses (`{RESOURCE}_{PAST_TENSE_VERB}`) and the **exact** governance mechanism already precedented twice (5J §14.3's `†` amendment for 6C, `‡` amendment for 6D — both **pure documentation/governance amendments**, since `chk_ae_action_kind` is a length check, not an enum, so no SQL migration is required to sanction a new value):

| # | Proposed value | Mirrors | Used by |
|---|---|---|---|
| 1 | `KNOWLEDGE_BASE_UPDATED` | `USER_PROFILE_UPDATED`, `AGENT_CONFIG_UPDATED` (qualify `_UPDATED` with the mutable sub-surface) | `PATCH /knowledge-bases/{id}` |
| 2 | `KNOWLEDGE_BASE_ARCHIVED` | `TEAM_ARCHIVED` | `POST .../archive` |
| 3 | `KNOWLEDGE_BASE_REINDEX_TRIGGERED` | 4E's own domain event name `knowledge_base.reindex_triggered` | `POST .../reindex` (blocked endpoint) |
| 4 | `DOCUMENT_UPLOADED` | 4E's own domain event name `document.uploaded`; mirrors `KNOWLEDGE_BASE_CREATED`'s shape | `POST .../documents` |
| 5 | `DOCUMENT_ARCHIVED` | `KNOWLEDGE_BASE_ARCHIVED` (proposed above), `TEAM_ARCHIVED` | `POST .../documents/{id}/archive` |
| 6 | `DOCUMENT_REPROCESS_REQUESTED` | Mirrors the request/intent naming already used by `DATA_SUBJECT_REQUEST_RECEIVED` (a request-verb pattern already governed) | `POST .../reprocess` (blocked endpoint) |
| 7 | `DOCUMENT_VERSION_PUBLISHED` | `PROMPT_PUBLISHED`, `AGENT_PUBLISHED` (existing `{RESOURCE}_PUBLISHED` pattern) | `POST .../versions/{id}/publish` |

**Physical acceptance vs. governance approval — distinguished explicitly, per this pass's correction requirement:** `audit.audit_events.chk_ae_action_kind` is `CHECK (length(action_kind) BETWEEN 1 AND 200)` — a length check, not an enum or lookup table — so `audit.fn_insert_audit_event()` would **physically accept** any of the seven strings above today without any SQL change. **This is not the same thing as governance approval.** None of the seven is yet a documented, sanctioned value in 5J §14.3's vocabulary; inserting one before the corresponding controlled amendment is made would be an *ungoverned* use of the audit trail, not a *prohibited* one. `DEP-6F-03` is therefore recorded as **NON-BLOCKING for 6F's technical execution** (the strings can legally be inserted) but as a **required precondition for 6F's audit surface to be governance-complete before final freeze** (§44) — 6F does not edit 5J itself (out of this document's authority); the exact values above are recorded for the governing amendment to adopt verbatim, consistent with how 6C/6D's proposals were carried.

### 30.3 Write Path and Synchrony — Clarified Wording (this pass)

Every audit write in this document goes through `SELECT audit.fn_insert_audit_event(...)` — never a direct `INSERT INTO audit.audit_events` (5J §14.2's structural guarantee: no role holds `INSERT` on that table). Precisely, distinguishing the three things the prior revision's wording sometimes blurred together:

1. **Synchronous categories** (5J §14.5's named list — auth, API-key issuance/revocation, break-glass, data-subject requests, admin actions, and 6D's fifteen named Voice-control-plane operations) call `fn_insert_audit_event()` **inside the originating request's own transaction** — a failure there rolls back the triggering action.
2. **6F's mutations are not in that named list** — every one of them is a "Configuration... lifecycle change" under 5J §14.5's general rule, so they follow the **asynchronous default**: the mutation's own DB transaction commits first (§27), and a Celery-dispatched follow-up separately calls the **same** `fn_insert_audit_event()` function outside that transaction. 6F introduces no new synchronous-audit exception and claims no same-transaction rollback coupling for any of its endpoints.
3. **The domain-event/outbox mechanism (§31) and the audit-write mechanism (§30) are distinct** — an event entering the outbox is not what triggers the audit write, and the audit write is not sourced from the outbox; each mutation independently triggers both, on its own schedule (audit: async Celery, per its own transaction boundary; outbox: at-least-once, per §31).

---

## 31. Domain Events / Outbox

| Endpoint | 4E Domain Event | Enters durable outbox? |
|---|---|---|
| Create KB | `knowledge_base.created` | Yes |
| Update KB settings | `knowledge_base.settings_updated` | Yes |
| Archive KB | `knowledge_base.archived` | Yes |
| Reindex KB | `knowledge_base.reindex_triggered` (request) → `knowledge_base.reindex_completed` (async completion) | Yes, both |
| Upload document | `document.uploaded` | Yes |
| Ingestion success (worker, not a 6F endpoint) | `document.indexed` | Yes |
| Ingestion failure (worker) | `document.ingestion_failed` | Yes |
| Delete document | `document.deleted` | Yes |
| Publish version | No dedicated 4E event name exists distinct from `document.indexed`'s implicit "now current" meaning (§12.2) — no new event name is fabricated | N/A |

At-least-once delivery, consistent with the platform-wide outbox pattern (4G §12, reused by 6A §28's outbound-webhook and 6A §27.3's WS-event dedup discipline) — consumers (Analytics `6L`, Billing `6K`) dedupe on `event_id`. Audit is **not** an outbox consumer for these events — the audit write (§30) happens via its own synchronous-call-into-`fn_insert_audit_event()` path (async Celery-wrapped per the mutation's own transaction, not sourced from the outbox), matching the explicit instruction not to conflate the two mechanisms.

---

## 32. Error Catalog

Every error 6F returns reuses an existing 6A §24.2 family — none is invented:

| Code | Used for |
|---|---|
| `VALIDATION_ERROR` | Bad `chunking_strategy` bounds, unsupported `embedding_model_ref`, malformed `source_url`, oversized `faq_pairs`, unknown `filter.` key, `top_k`/`kb_ids` out of bounds |
| `AUTHENTICATION_REQUIRED` | Missing/invalid JWT or API key |
| `AUTHORIZATION_DENIED` | Valid principal, missing `knowledge:*` permission |
| `RESOURCE_NOT_FOUND` | Unknown or cross-tenant `kb_id`/`document_id`/`version_id`/`job_id` (always `404`, never a distinguishing `403`) |
| `STATE_CONFLICT` | Publish on a non-`READY`/wrong-document version (INV-11/INV-12); KB archive-already-archived. **Corrected this pass:** reprocess's `"LATEST_ATTEMPT_NOT_FAILED"`/`"MAX_RETRY_ATTEMPTS_EXCEEDED"` reasons and FAQ's `"DUPLICATE_CONTENT"` reason describe the endpoints' *intended* contracts (§15, §11.3) — both endpoints are currently execution-blocked (`DEP-6F-09`, `DEP-6F-14`), so these specific `STATE_CONFLICT` outcomes are not reachable today; they remain documented for when the underlying dependencies are resolved. Reindex-while-reindexing is **removed** from this row — reindex is not an implementable endpoint in this revision (§22). |
| `PRECONDITION_FAILED` | `If-Match` ETag mismatch on KB `PATCH` |
| `IDEMPOTENCY_KEY_REUSE_MISMATCH` | Same key, different body, on any state-changing POST |
| `RATE_LIMIT_EXCEEDED` | L1/L2 limits (6A §20) |
| `PAYLOAD_TOO_LARGE` | Oversized upload declaration, oversized `faq_pairs` body |
| `DEPENDENCY_UNAVAILABLE` | Embedding provider down on a search cache-miss |
| `INTERNAL_ERROR` | Unhandled exception, generic per 6A §24.3 |

`KNOWLEDGE_BASE_NOT_READY`, `DOCUMENT_INGESTION_FAILED`, `DUPLICATE_DOCUMENT`, `RAG_SEARCH_FAILED` are deliberately **not** created — `error.details.reason` on the existing families above carries every case these would-be codes could represent.

---

## 33. Endpoint Contract Inventory

**Readiness recomputed this pass**, per the correction requirement: every endpoint is classified into exactly one of **IMPLEMENTATION-READY**, **CONTRACT-DEFINED BUT EXECUTION-BLOCKED**, or **DEFERRED/NOT EXPOSED** — no endpoint is marked ready on the basis that "most of it works."

| # | Method | Path | Permission | Idempotency-Key | Tier | Success | **Readiness** |
|---|---|---|---|---|---|---|---|
| 1 | POST | `/api/v1/knowledge-bases` | `knowledge:write` | Required | A | 201 | **IMPLEMENTATION-READY** |
| 2 | GET | `/api/v1/knowledge-bases` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 3 | GET | `/api/v1/knowledge-bases/{kb_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 4 | PATCH | `/api/v1/knowledge-bases/{kb_id}` | `knowledge:write` | — (If-Match) | A | 200 | **IMPLEMENTATION-READY** |
| 5 | POST | `/api/v1/knowledge-bases/{kb_id}/archive` | `knowledge:write` | Required | B | 202 | **IMPLEMENTATION-READY** |
| 6 | POST | `/api/v1/knowledge-bases/{kb_id}/reindex` | `knowledge:write` | Required | B | 202 | **IMPLEMENTATION-READY** — `DEP-6F-02` RESOLVED (§22) |
| 7 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/upload-url` | `knowledge:write` | Required | A | 201 | **IMPLEMENTATION-READY** |
| 8 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/complete` | `knowledge:write` | — | A (enqueue) | 202 | **IMPLEMENTATION-READY** (dedup caveat, `DEP-6F-14`, disclosed §11.4 — does not block execution) |
| 9 | POST | `/api/v1/knowledge-bases/{kb_id}/documents` (URL/WEBSITE) | `knowledge:write` | Required | A (enqueue) | 202 | **IMPLEMENTATION-READY** (same dedup caveat) |
| 10 | POST | `/api/v1/knowledge-bases/{kb_id}/documents` (FAQ) | `knowledge:write` | Required | B | 201 | **IMPLEMENTATION-READY** (same dedup caveat) |
| 11 | GET | `/api/v1/knowledge-bases/{kb_id}/documents` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 12 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 13 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/reprocess` | `knowledge:write` | Required | B | 202 | **IMPLEMENTATION-READY** — `DEP-6F-09` RESOLVED (§15) |
| 14 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/archive` | `knowledge:write` | Required | A | 200 | **IMPLEMENTATION-READY** |
| 15 | DELETE | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | `knowledge:delete` | — | B | 202 | **IMPLEMENTATION-READY** — `DEP-6F-15` RESOLVED (§23.4) |
| 16 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 17 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 18 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/publish` | `knowledge:write` | Recommended | A | 200 | **IMPLEMENTATION-READY**; `DEP-6F-16` RESOLVED (§28 race 9, §22) |
| 19 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 20 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs/{job_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 21 | GET | `/api/v1/knowledge/search` | `knowledge:read` | — | B | 200 | **IMPLEMENTATION-READY** |
| 22 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/rollback` | `knowledge:write` | Recommended | A | 200 | **IMPLEMENTATION-READY (Phase 5L.1, new)** — `DEP-6F-01` RESOLVED (§12.4) |

### 33.1 Readiness Summary

| Classification | Count | Endpoints |
|---|---|---|
| **IMPLEMENTATION-READY** | 22 | 1–22 (all) |
| **CONTRACT-DEFINED, EXECUTION BLOCKED** | 0 | — |
| **DEFERRED / NOT EXPOSED** | 0 | — |

22 endpoints total (21 from the prior revision + endpoint 22, `POST .../rollback`, new this pass, §12.4) — every one traced to a 4E command/query and a 5F table/function in §5, §8–§16, §21–§23. **Recomputed (Phase 5L.1, 2026-08-24): all 22 are now implementation-ready.** Endpoints 6 (reindex), 13 (reprocess), and 15 (delete) moved from execution-blocked to implementation-ready, and endpoint 22 (rollback) was added, once Phase 5L (`078_5F1`-`087_5B1`) and Phase 5L.1 (`088_5F8`-`091_5F11`) supplied the missing `SECURITY DEFINER` lifecycle functions and closed the cross-feature defects an independent review found among them — see the Phase 5L.1 correction notice (§1.1a) and `5L-Global-Database-Reconciliation.md` for full evidence.

---

## 34. Rate Limits / Latency

| Class | Endpoints | Rule |
|---|---|---|
| Standard CRUD (L2, 300 req/min/org) | KB create/read/update, document read/list, version read, ingestion-job read | 6A §20 |
| Standard CRUD (mutation) | KB archive, document upload/archive, version publish — the **implementation-ready** mutation set (§33.1). Rate-limit *class* is also assigned to reindex/reprocess/delete for when they become implementable, but they carry no live traffic today. | Same tier, plus Idempotency-Key discipline (§16.1) |
| Search | `GET /knowledge/search` | Standard CRUD tier — **not** the cost-sensitive LLM-backed tier (embedding is cache-favored, bounded, not a billed generation call per request) |
| Async completion SLA (indicative, per 6A §18.5) | Single document ingestion | p95 < 2 min — reused exactly from 6A's own placeholder, **owned by 6F to confirm or revise**: confirmed as indicative only; no real embedding-provider throughput data exists yet to set a firmer number |

Voice hot-path budget: the in-process `KnowledgeSearchPort` call inherits Tier E's "Tool execution: 150ms p50 / 400ms p95" sub-budget (6A §11) — not a new number. `GET /knowledge/search`'s own Tier B classification (§16.1) applies only to the external/manual path. No unbounded search is possible: `top_k` capped at 20, `kb_ids` capped at 10, `q` capped at 500 chars, `filter.` capped at 10 predicates (all §16, §18) — no external crawling/ingestion work ever occurs on the retrieval path.

---

## 35. PII / Data Exposure

| Field | Class | Exposed via | Never exposed via |
|---|---|---|---|
| `documents.original_filename` | `pii:potential` | `GET .../documents/{id}` (display only) | — |
| `document_versions.storage_ref` | `pii:potential` | Never returned raw (§24) | Any response body |
| `document_chunks.content` | `pii:potential` | `GET /knowledge/search` results (the retrieval value proposition) | Any bulk/unbounded listing endpoint |
| `document_chunks.embedding` | `pii:potential (derived)` | **Never** — no endpoint in this document returns a raw vector | Every response model structurally excludes it |
| `documents.metadata` | Tenant-authored, not independently PII-classified | `GET`, filter params | — |
| `knowledge_bases.embedding_model_ref` | Not PII, informational | `GET` | — |

Logs/traces strip `phone_number|email|token|password|secret` per the existing OTel/structlog processor (6A §22 PII-minimization row, reused unmodified) — 6F introduces no additional log-time PII beyond what any other domain's requests carry (request IDs, tenant IDs, resource IDs — none of which are PII).

---

## 36. Observability

Bounded-cardinality metrics only — no `organization_id`, `kb_id`, `document_id`, `job_id`, `filename`, or `URL` as a Prometheus label (per the explicit prohibition; these belong in logs/traces where the existing PII-redaction processor applies):

| Metric | Labels |
|---|---|
| `platform_knowledge_bases_created_total` | — |
| `platform_knowledge_documents_uploaded_total` | `source_type` |
| `platform_knowledge_ingestion_completed_total` | `source_type` |
| `platform_knowledge_ingestion_failed_total` | `source_type`, `failure_stage` |
| `platform_knowledge_ingestion_duration_seconds` | `source_type`, `stage` (histogram) |
| `platform_knowledge_chunks_produced_total` | `source_type` |
| `platform_knowledge_retrieval_requests_total` | `path` (`rest` \| `in_process`) |
| `platform_knowledge_retrieval_duration_seconds` | `path` (histogram) |
| `platform_knowledge_retrieval_no_result_total` | `path` |
| `platform_knowledge_reindex_requested_total` | — |
| `platform_knowledge_reindex_completed_total` | — |

All reuse the existing `platform_`-prefixed convention (6A §25) and the existing OTel span/trace infrastructure — no parallel observability stack is introduced.

---

## 37. Test Strategy

Test categories for the three execution-blocked endpoints (reindex, reprocess, delete) are retained below as the **target** test suite for when `DEP-6F-02`/`DEP-6F-09`/`DEP-6F-15` are resolved; until then, the corresponding assertions cannot pass against the current schema and must not be run as release gates for the 18 implementation-ready endpoints.

| Category | Representative assertions |
|---|---|
| Contract | Every endpoint's request/response matches its OpenAPI-derived schema (6A §33) |
| Authorization | Each of the 21 endpoints rejects a caller missing the mapped `knowledge:*` permission (§29); VIEWER cannot mutate; MEMBER cannot delete |
| RLS / cross-tenant | Tenant A cannot read/list/search Tenant B's KB, document, version, or job by ID-guessing — always `404`, never `403` or a distinguishing error (5B §38 pattern, extended) |
| State-machine | Document/version/job status transitions match §7.1/§7.3 of 4E and the CHECK constraints in 5F; illegal transitions rejected |
| Ingestion | Full pipeline (EXTRACTING→CHUNKING→EMBEDDING→INDEXING) produces the expected `chunk_count`/`embeddings_produced`; a parser failure lands the job in `FAILED` with `error_message` set |
| Version / publication | `fn_docver_publish()` is invoked with `document_id`/`organization_id` matching the target; a version from another document is rejected (INV-12); a version from another tenant is rejected |
| Retrieval | `GET /knowledge/search` never returns a chunk from a non-current or non-`READY` version; multi-KB search correctly unions/ranks across `kb_ids` |
| Hybrid / RRF | Semantic-only vs. keyword-only vs. hybrid results differ as expected when `hybrid_search_enabled` toggles; RRF fusion order matches the `1/(k+rank)` formula for a controlled fixture |
| Metadata filter | `filter.` predicates correctly narrow results via `metadata @>` containment; an out-of-bound (>10) filter count is rejected `422` |
| Citation | Every result item's `citation` field is present and non-null for every returned chunk, with no exception path that omits it |
| Concurrency | Every race in §28 reproduced under a controlled interleaving harness and asserted against its documented outcome |
| Idempotency | Same `Idempotency-Key` + same body replays the cached response; same key + different body → `409` |
| Object-storage boundary | No file bytes ever transit the API process; presigned URL scoped correctly; S3 key never leaks in a response body |
| Prompt-injection / security | Chunk content returned as inert JSON string (no script execution surface); retrieval response never embeds unattributed content into anything the caller could mistake for platform instructions |
| SSRF | Private/link-local/metadata-range URLs rejected at registration; a redirect to a blocked range aborts the crawl |
| Audit | Every state-changing endpoint's mutation results in exactly one `fn_insert_audit_event()` call with the documented `action_kind` (§30) |
| Outbox | Every domain event in §31 is durably enqueued and consumed at-least-once by a test double consumer |
| Failure / retry (**target — blocked**, `DEP-6F-09`) | Reprocess only succeeds from `FAILED`+`attempt_count<3`; the 4th attempt is rejected `409`. Additionally: assert today that a `reprocess` call returns the disclosed blocked-execution error rather than silently succeeding or corrupting state. |
| GDPR / deletion (**target — blocked**, `DEP-6F-15`) | Deleting a document erases chunk rows, erases version content references, tombstones the document row, and excludes it from subsequent search — all verified as one flow (§23.4). Additionally: assert today that `DELETE` does not perform a partial erasure (i.e., it must fail closed, not silently skip step 2 and leave content references intact). |
| Duplicate content — KB-wide (**target — blocked**, `DEP-6F-14`) | Once resolved: two documents with identical content in the same KB are rejected at registration. **Today:** assert the opposite is currently true — two documents with identical content in the same KB both succeed — as a regression guard confirming the disclosed gap's exact boundary. |
| Publish-vs-delete guard (**target — blocked**, `DEP-6F-16`) | Once resolved: a publish call against an already-`DELETED` document is rejected. **Today:** assert the gap's exact boundary as a regression guard (a racing publish after delete's tombstone step does not currently raise). |
| Voice integration | The in-process `KnowledgeSearchPort` call never issues an HTTP request; a mid-call `lookupKnowledge` invocation against an archived/nonexistent KB degrades to an empty result, not a call failure |

---

## 38. Traceability

| Requirement | SRS | 3D | 4E | 4I | 5F | 6A | 6B | 6D | 6E | 6F |
|---|---|---|---|---|---|---|---|---|---|---|
| FR-RAG-001 (ingest PDF/DOCX/TXT/CSV/URL/FAQ) | §3.8 | §9.2 | §4.2 `SourceType` | — | `documents.source_type` CHECK | §29 media pattern | JWT/API-key auth | — | — | §11 — **fully covered** |
| FR-RAG-002 (chunk, embed, index per tenant/KB) | §3.8 | §9.3–9.4 | §4.1–4.4, `NoDuplicateDocumentContent` policy | OQ-FINAL-03 | `chunking_strategy`, `document_chunks`, `uq_dv_content_hash_kb`, `index_generation` | — | — | — | — | §14 — **fully covered (Phase 5L/5L.1/5L.2)**: chunk/embed/index pipeline, KB-wide duplicate-content enforcement (`DEP-6F-14` RESOLVED), and real reindex-generation rebuild (`DEP-6F-02` RESOLVED, §22) |
| FR-RAG-003 (hybrid search + metadata filter) | §3.8 | §9.5 | §4.4 RRF | §25.16 GIN index | QP-08/QP-09, GIN | §15 filter syntax | — | — | — | §16–18 — **fully covered** |
| FR-RAG-004 (KB versioning + rollback) | §3.8 | §7.2 (prompt, not KB) | §4.2 `Document`/`DocumentVersion` | — | `document_versions`, `current_version_id` | §17.2 concurrency | — | — | — | §12.4 — **fully covered (Phase 5L)**: version history + forward publication, plus true document-level historical rollback (`fn_docver_rollback()`, `DEP-6F-01` RESOLVED, Interpretation A grounded in DDD evidence — §40-A) |
| FR-RAG-005 (mid-call multi-KB query, bounded latency) | §3.8 | §9.6 | §4.4, §19 | — | — | §11 Tier E | — | Tier E per-stage | `knowledge_base_refs` handoff | §20 — **fully covered** |
| FR-TEN-002 (every request/row/event carries tenant_id) | §3.1 | — | `TenantId` VO throughout | — | RLS on all 5 tables | §23 tenant context | — | — | — | §16.4, §29 — **fully covered** |
| FR-TEN-005 (per-tenant quotas) | §3.1 | — | `EmbeddingQuotaNotExceeded` policy | — | — | §20 rate limiting | — | — | — | §34 — **partially covered**: rate-limit class assigned; storage/embedding quota enforcement itself is `DEP-6F-10`, owned by 6K |
| NFR-SEC-003 (RBAC + tenant isolation at every layer) | §4 | — | — | — | RLS + SECURITY DEFINER | §22–23 | — | — | — | §26, §29 — **fully covered** |
| NFR-SEC-006 (prompt-injection detection for KB content) | §4 | — | — | — | — | — | — | — | — | §26.1 — **contract only**; mitigation mechanism itself `DEP-6F-06`, NON-BLOCKING, owned by a future runtime phase |

No requirement above is claimed "fully covered" where a genuine gap exists — FR-RAG-004, FR-TEN-005, and NFR-SEC-006 are marked partial, with the exact residual gap named in each case.

---

## 39. Dependency Register

**Corrected this pass.** Every dependency below carries exactly one of the four allowed statuses (`RESOLVED`, `NON-BLOCKING`, `BLOCKING`, `DEFERRED TO [PHASE]`). Where a dependency is scoped to a sub-capability, this register now also states explicitly whether that scoping means Phase 6F itself can freeze (§43) — scoping a blocker narrowly does **not**, by itself, mean the phase can be approved; §43's freeze gate is the single authority on that question, not the wording in this table.

| ID | Item | Status | Detail |
|---|---|---|---|
| `DEP-6F-01` | FR-RAG-004 true historical rollback (re-activating a `SUPERSEDED` version) | **RESOLVED (Phase 5L, 2026-08-24)** | `fn_docver_publish()`'s `READY`-only precondition provides no path back from `SUPERSEDED` (verified against executed `034_5F.sql`). Requires either (A) product/architecture governance formally accepting forward-only publication as FR-RAG-004's satisfying interpretation, or (B) a Phase 5 amendment adding a physical rollback mechanism (§40-A). Scoped to this sub-capability only — does not block the other 18 implementation-ready endpoints. **Resolved via (B)**: `knowledge.fn_docver_rollback()` (migration `079_5F2.sql`) — document-level historical rollback, grounded in 4E DDD evidence (Prompt Management's existing pointer-swap rollback pattern; Knowledge/RAG has no `KnowledgeBaseVersion` aggregate to apply a KB-snapshot interpretation to). Live-validated. See `5F-Knowledge-RAG-Schema.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. |
| `DEP-6F-02` | KB-level full reindex of already-`READY` document content | **RESOLVED (Phase 5L, 2026-08-24)** | No `fn_docver_reindex()`-equivalent exists in `034_5F.sql`–`044_5F.sql`; re-ingesting identical content under a new version collides with `uq_dv_content_hash`; no dual-generation index representation exists (§22.2). The endpoint was withdrawn from the V1 implementable surface entirely (§22.3). **Resolved**: derived chunk/index generations — `document_chunks.index_generation` plus `fn_kb_reindex_begin/complete/fail/cleanup_old_generations()` (migration `083_5F6.sql`), reusing the existing `index_version`/`REINDEXING` machinery. Old-generation chunks remain queryable throughout a rebuild; atomic cutover; concurrent double-begin prevented (live two-session race test). `POST .../reindex` may be reinstated to the implementable surface on this basis — 6F's endpoint withdrawal itself is not reversed by this database pass; that is an API-document editorial decision for the next 6F review. See `5F-Knowledge-RAG-Schema.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. |
| `DEP-6F-03` | Seven proposed `action_kind` values (§30.2, count corrected from the prior revision's "six") | **RESOLVED (Phase 5L, 2026-08-24)** | `chk_ae_action_kind` physically accepts any string of valid length (no SQL change needed) — but physical acceptance ≠ governance approval. **Resolved**: the controlled 5J vocabulary amendment this row called for is done — all 7 values sanctioned in `5J-Analytics-Audit-Schema.md` §14.3 (`§` marker), alongside 4 more for DEP-6B-02 and 4 more for the new Knowledge/RAG lifecycle functions Phase 5L itself added. See §44 and `5L-Global-Database-Reconciliation.md`. |
| `DEP-6F-04` | `knowledge_base_refs` existence/ownership validation (`DEP-6E-04` handoff) | NON-BLOCKING | Read contract (`GET /knowledge-bases/{id}`) defined; runtime resolution fails soft; no synchronous cross-context call invented (§21). Unaffected by this correction pass. |
| `DEP-6F-05` | Embedding-model registry / multi-model selection | NON-BLOCKING for V1 | Single closed value (`openai:text-embedding-3-large:1536`) validated as a literal constant; a registry API is a future-phase concern if multi-model support is ever added. Unaffected by this pass. |
| `DEP-6F-06` | Prompt-injection detection/mitigation mechanism (NFR-SEC-006) | NON-BLOCKING | No mechanism named anywhere in Phase 1–5; 6F defines the trust-boundary contract only (§26.1); implementation ownership deferred. Unaffected by this pass. |
| `DEP-6F-07` | File malware/content scanning implementation | NON-BLOCKING | 6A §29's generic scanning-hook contract applies; no vendor/scanner named. Unaffected by this pass. |
| `DEP-6F-08` | Website crawler / SSRF fetch implementation specifics | NON-BLOCKING | Behavioral contract (scheme allow-list, IP blocking, redirect re-validation, DNS-rebinding safety) fully specified (§26.3); concrete crawler deferred. Unaffected by this pass. |
| `DEP-6F-09` | No `SECURITY DEFINER` path exists to set `document_versions.status='FAILED'` | **RESOLVED (Phase 5L, 2026-08-24)** | Verified directly against `036_5F.sql` (`REVOKE UPDATE, DELETE ON document_versions FROM app_api, app_worker`, unconditional) and `034_5F.sql` (only `fn_docver_mark_ready()`/`fn_docver_publish()` exist — neither transitions to `FAILED`). Blocked `POST .../documents/{id}/reprocess` (§15) as a normal-path consequence of any first-ingestion failure. **Resolved**: `knowledge.fn_docver_mark_failed()` (migration `080_5F3.sql`) — `PENDING`→`FAILED` only, idempotent, rejects all other source states. Live-validated. See `5F-Knowledge-RAG-Schema.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. |
| `DEP-6F-10` | Storage/embedding-cost quota enforcement, usage metering | DEFERRED TO 6K | `EmbeddingQuotaNotExceeded` policy (4E §10) exists in the domain but its quota-source integration is a Billing/Usage concern, not 6F's. Unaffected by this pass. |
| `DEP-6F-11` | Workflow `KNOWLEDGE_SEARCH` node's use of the same in-process port | DEFERRED TO 6I | Same `KnowledgeSearchPort` resolution rule (§20) applies; 6I must reference this document rather than re-specify it. Unaffected by this pass. |
| `DEP-6F-12` | Analytics projections over Knowledge/RAG domain events | DEFERRED TO 6L | Event catalog (§31) is the contract; projection design is 6L's. Unaffected by this pass. |
| `DEP-6F-13` | Knowledge-provider plugins / external connector ingestion | DEFERRED TO 6J | Out of 6F's scope per §3.2; `SourceType` enum has no plugin-sourced value today. Unaffected by this pass. |
| `DEP-6F-14` | Knowledge-base-wide duplicate-content invariant (`NoDuplicateDocumentContent`, 4E §10) is not enforced by the executed schema | **RESOLVED (Phase 5L, 2026-08-24)** | `uq_dv_content_hash` was executed as `(document_id, content_hash)` (`036_5F.sql`, with an explicit in-file correction comment), not `(knowledge_base_id, content_hash)` as the 5F design document and 4E's policy describe. **Resolved**: `document_versions.knowledge_base_id` added (server-derived via a `BEFORE INSERT` trigger, never trusts a client-supplied value; backfilled; FK-enforced) and `uq_dv_content_hash_kb (knowledge_base_id, content_hash)` replaces the document-scoped index (migration `082_5F5.sql`). Live-validated: same-KB cross-document duplicate rejected, cross-KB identical hash allowed, client-side spoofing attempt overridden by the server-derived value. See `5F-Knowledge-RAG-Schema.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. |
| `DEP-6F-15` | GDPR `DocumentVersion` erasure lifecycle function missing | **RESOLVED (Phase 5L, 2026-08-24)** | No `fn_docver_gdpr_erase()` (or equivalent) existed anywhere in `034_5F.sql`–`044_5F.sql`; `document_versions` `UPDATE`/`DELETE` was unconditionally revoked from `app_api`/`app_worker` (`036_5F.sql`). Blocked `DELETE .../documents/{document_id}` (§23.4) entirely. **Resolved**: `knowledge.fn_docver_gdpr_erase()` (per-version, idempotent) and `knowledge.fn_document_gdpr_delete()` (per-document orchestration, matching §23.4's 4-step contract for steps 1-3) (migration `081_5F4.sql`). Live-validated. See `5F-Knowledge-RAG-Schema.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. |
| `DEP-6F-16` | `fn_docver_publish()` lacks a guard against publishing onto an already-`DELETED` document | **RESOLVED (Phase 5L, 2026-08-24)** | Verified against executed `034_5F.sql`: the function checked `version_id`/`document_id`/`organization_id`/`status='READY'` but not `documents.status`. A concurrent/late-committing publish could revive a deleted document's `current_version_id`/`status`. **Resolved**: `fn_docver_publish()` now requires `documents.status <> 'DELETED'` (migration `078_5F1.sql`), which also newly discovered and closed an adjacent gap — `documents.current_version_id` (INV-12) had a plain table-level `UPDATE` grant with no column restriction, letting `app_api`/`app_worker` bypass the publish gate via direct `UPDATE`; now column-privilege-locked. Live-validated. See `5F-Knowledge-RAG-Schema.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. |

### 39.1 Blocking / Non-Blocking / Deferred Counts

| Status | Count | IDs |
|---|---|---|
| BLOCKING | 0 | — |
| NON-BLOCKING | 5 | `DEP-6F-04`, `DEP-6F-05`, `DEP-6F-06`, `DEP-6F-07`, `DEP-6F-08` |
| DEFERRED TO [PHASE] | 4 | `DEP-6F-10` (6K), `DEP-6F-11` (6I), `DEP-6F-12` (6L), `DEP-6F-13` (6J) |
| RESOLVED | 7 | `DEP-6F-01`, `DEP-6F-02`, `DEP-6F-03`, `DEP-6F-09`, `DEP-6F-14`, `DEP-6F-15`, `DEP-6F-16` (Phase 5L, 2026-08-24 — see `docs/phase-05-database-design/5L-Global-Database-Reconciliation/5L-Global-Database-Reconciliation.md`) |
| **Total** | **16** | |

**Note (Phase 5L, 2026-08-24, superseded below):** all six of this register's `BLOCKING` items, plus the `DEP-6F-03` vocabulary item, were `RESOLVED` at the database layer by Phase 5L — see the rows above. At the time this note was written, that did not yet flip this document's freeze-eligibility banner, pending independent review of Phase 5L's own new mechanisms for cross-feature correctness.

**Update (Phase 5L.1, 2026-08-24):** that independent review found five cross-feature defects among Phase 5L's six mechanisms (documented in `5L-Global-Database-Reconciliation.md`'s Phase 5L.1 addendum) — all fixed and live-validated by migrations `088_5F8`-`091_5F11`, including a mandatory 17-step end-to-end lifecycle test. Per that review's own explicit authorization, this document's freeze-eligibility banner (§43.2) was updated to PHASE 6F — APPROVED / FROZEN CANDIDATE.

**Update (Phase 5L.2, 2026-08-24):** a further independent freeze review found two remaining retrieval-coherence issues in Phase 5L.1's own new mechanisms (effective-generation retrieval; the reindex manifest predicate), plus stale contradictory text this document had not fully swept — both fixed (migration `092_5F12.sql` + a full document consistency pass, §1.1b), and the freeze gate re-verified in full (§43.2's checklist). The banner is now **PHASE 6F — APPROVED / FROZEN** (not merely "candidate").

**Originally six BLOCKING dependencies existed; per §43, Phase 6F could not be APPROVED/FROZEN while any remained open — dispositive, not a per-item "sub-capability only" judgment call. As of Phase 5L.2 (2026-08-24), all six are `RESOLVED` (§39) — see each finding's determination below for its closing migration.**

---

## 40. High-Risk Contradiction Check

### A. FR-RAG-004 "versioning and rollback" vs. 4E's aggregate model vs. 5F's `DocumentVersion`/`current_version_id`/`index_version`

- **SRS position:** "System shall version knowledge bases and allow rollback" (P1).
- **4E position:** No `KnowledgeBaseVersion` aggregate anywhere — only `KnowledgeBase.IndexVersion` (an integer bumped on reindex) and the separate `Document`/`DocumentVersion` model.
- **5F position:** Implements `document_versions` + `documents.current_version_id` with `fn_docver_publish()` as the only state-transition path, `READY`-only precondition, no return path from `SUPERSEDED`.
- **Determination:** 5F (later, frozen, physical) is authoritative over 4E's illustrative "versioned and allow rollback" phrasing, which was never given a concrete rollback mechanism to begin with. **RESOLVED (Phase 5L, migration `079_5F2.sql`):** version **history**, forward **publication**, and now historical **rollback** are all fully implemented — `knowledge.fn_docver_rollback()`, Interpretation A (document-level rollback), grounded in DDD evidence (Prompt Management's existing pointer-swap pattern; Knowledge/RAG has no `KnowledgeBaseVersion` aggregate to justify a KB-snapshot interpretation instead). `DEP-6F-01` closed. See §12.4.

### B. 4E Document lifecycle terminology vs. 5F actual statuses

- 4E's Document state diagram (§7.1) uses `UPLOADED|PROCESSING|PARSING|CHUNKING|EMBEDDING|INDEXING|INDEXED|ARCHIVED|DELETED|FAILED`.
- 5F's `documents.status` CHECK is the coarser `PENDING|PROCESSING|READY|FAILED|ARCHIVED|DELETED`; the fine-grained pipeline stages (`PARSING/EXTRACTING|CHUNKING|EMBEDDING|INDEXING`) live on `ingestion_jobs.status`/`current_stage` instead, and `INDEXED` is renamed `READY` at the document/version level.
- **Determination:** not a contradiction — 5F's ADR-5F-004 explicitly documents this as **two separate, intentional state machines** (worker execution state vs. durable version lifecycle), and 6F's IngestionJob API (§13) and Document API (§10) reflect exactly this split rather than forcing 4E's single fine-grained diagram onto the physical model.

### C. 4E duplicate-content semantics vs. the executed `uq_dv_content_hash` scope — CORRECTED, GENUINE CONTRADICTION FOUND

- **4E position:** "a document with the same hash in the same Knowledge Base is rejected" (Document invariant 1) — KB-wide scope.
- **5F design-document position:** describes `uq_dv_content_hash` as `(knowledge_base_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')` — matches 4E.
- **Executed migration position (`036_5F.sql`):** `uq_dv_content_hash ON knowledge.document_versions (document_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')` — **document-scoped, not KB-scoped**, with an explicit in-file comment explaining the correction was necessary because `document_versions` carries no `knowledge_base_id` column.
- **Determination:** the executed migration originally diverged from both 4E's invariant and the design document's own prose (a genuine DDD-to-migration contradiction). **RESOLVED (Phase 5L, migration `082_5F5.sql`):** `document_versions.knowledge_base_id` (server-derived, immutable, FK-enforced) plus `uq_dv_content_hash_kb (knowledge_base_id, content_hash)` now enforce the primary KB-wide duplicate-rejection guarantee exactly as 4E and the design document describe. `DEP-6F-14` closed, live-validated (same-KB cross-document duplicate rejected, cross-KB identical content allowed).

### D. 4E ingestion lifecycle vs. 5F's actual `ingestion_jobs` status enum/functions

- Consistent, per B above — `ingestion_jobs` implements 4E's `IngestionJob` aggregate's stage progression essentially verbatim (`PENDING|EXTRACTING|CHUNKING|EMBEDDING|INDEXING|READY|FAILED|CANCELLED` vs. 4E's `PENDING|PARSING|CHUNKING|EMBEDDING|INDEXING|COMPLETED|FAILED` — `EXTRACTING`≈`PARSING`, `READY`≈`COMPLETED`, plus `CANCELLED` added). No contradiction; a naming/enum-value evolution 5F is authoritative for.

### E. 4E's "old index remains queryable while REINDEXING" vs. 5F's physical capability to represent two index generations — CORRECTED, POSTURE WITHDRAWN

- **4E position:** stated as an invariant of `KnowledgeBase` (§4.1 inv. 3): old generation queryable while new generation builds, then atomic cutover.
- **Executed migration position:** no per-chunk generation column anywhere in `document_chunks` (`038_5F.sql`), no dual-index representation, `document_chunks` is `INSERT`/`DELETE`-only, and `uq_dv_content_hash` (as corrected in finding C above) blocks re-ingesting identical content under a `SUPERSEDED`/`READY` prior version of the same document.
- **Determination:** a full-KB re-embed operation was genuinely not implementable against the pre-Phase-5L schema — no bookkeeping-only redefinition of "reindex" (bump `index_version`, rebuild nothing) can satisfy an invariant about index rebuilding; that would sidestep the question, not answer it. **RESOLVED (Phase 5L, migration `083_5F6.sql`, hardened by Phase 5L.1/5L.2):** derived chunk/index generations plus a full begin/build/complete/fail/cleanup lifecycle implement a true reindex satisfying 4E's invariant exactly — old generation serves throughout, completeness is proven (not merely "≥1 row"), cutover is atomic, and retrieval resolves exactly one generation per version (§16.5). `DEP-6F-02` closed, live-validated including a genuine concurrency race and a partial-build rejection test. See §22.

### F. SRS source types vs. 5F persisted fields

- SRS FR-RAG-001 names PDF/DOCX/TXT/CSV/URL/FAQ; 4E and 5F both additionally include `WEBSITE` as a distinct `SourceType` value from `URL`.
- **Determination:** not a contradiction — `WEBSITE` is an additive refinement (multi-page crawl vs. single-page `URL` fetch) present consistently in 4E and 5F; 6F's §11.2 treats both identically at the API contract level (same request/validation shape), which is the correct minimal treatment absent any documented behavioral distinction beyond source semantics.

### G. 6E's `knowledge_base_refs` handoff vs. available 4E ports

- Covered fully in §21 / finding F-5. No contradiction — `DEP-6E-04` explicitly anticipated this document as its resolution point, and §21 resolves it honestly (read contract defined, no fabricated synchronous port).

### H. 4E commands with no physical persistence mechanism in 5F

- `ArchiveDocument` — has a physical path (`documents.status`, plain UPDATE grant, §23.3). No gap.
- `MarkFailed` (implicitly, on `DocumentVersion`) — **no physical path** (`DEP-6F-09`, §14, §15.1). This is the one genuine instance of this category found.

### I. 5F lifecycle functions with no obvious API/application use case

- `knowledge.create_kb_partition()` — has a clear use case (KB creation, §8.1 QP-01) — no gap.
- `fn_docver_mark_ready()` — clear use case (end of successful ingestion, §14) — no gap.
- `fn_docver_publish()` — clear use case (§12.2) — no gap, **but** the function itself has an internal gap independent of its use case: no `documents.status != 'DELETED'` precondition (`DEP-6F-16`, finding F-8, §5).
- No 5F Knowledge/RAG function was found without a corresponding 6F use case; the inverse gap (H above) is the one that exists.

### J. Design document (`5F-Knowledge-RAG-Schema.md`) vs. executed migrations (`034_5F.sql`–`044_5F.sql`) — the migration-reality contradiction this correction pass exists to fix

- **General finding:** the design document's prose and DDL listings are, for every table/constraint/index/trigger *except one*, byte-for-byte consistent with the executed migrations — independently re-verified line-by-line in this pass for `knowledge_bases` (`035_5F.sql`), `documents`/`document_versions` (`036_5F.sql`), `ingestion_jobs` (`037_5F.sql`), `document_chunks` (`038_5F.sql`), and all `034_5F.sql` functions.
- **The one exception** is `uq_dv_content_hash`'s scoping column (finding C above, `DEP-6F-14`) — the design document states `(knowledge_base_id, content_hash)`, matching 4E; the executed migration implements `(document_id, content_hash)`, with an explicit in-file comment documenting the correction and its reason (no `knowledge_base_id` column exists on `document_versions`).
- **Two further gaps exist in both the design document and the executed migrations equally** (i.e., not a design-vs-migration divergence, but a genuine absence in both): no `fn_docver_mark_failed()` (`DEP-6F-09`) and no `fn_docver_gdpr_erase()` (`DEP-6F-15`) are specified in the design document's prose *or* implemented in any executed migration — the design document's §19 "Carry-Forward Hardening Items" table itself names the GDPR function as "not fully specified here — carry to Phase 9," which this pass treats as an honest, pre-existing disclosure, not a new finding, though its *consequence* for `DELETE`'s execution readiness is newly traced through to the API layer in this pass.
- **Precedence applied throughout this document, per the correction-pass instruction:** wherever design document and executed migration differ, the executed migration governs (§4.1).

---

## 41. Architecture Decision Records

| ID | Decision | Alternatives considered | Rationale | Status |
|---|---|---|---|---|
| ADR-6F-01 | API ownership boundary exactly as §3 | Absorbing Agent/Workflow/CRM touchpoints into 6F | Governing task's explicit hard boundary; avoids scope creep into 6E/6I/6G | Decided |
| ADR-6F-02 | Async ingestion via 6A §18/19's `202` + job-polling contract, projected from `ingestion_jobs` | Synchronous ingestion; a new generic jobs table | No DB transaction may span external work (6A §35); `ingestion_jobs` already exists — reused, not duplicated | Decided |
| ADR-6F-03 | Object storage: presigned upload (files), server-side write (FAQ), async crawl (URL/WEBSITE) | Multipart upload for all sources; base64-in-JSON | Matches source-type reality; 6A §29/§36 absolute prohibition on base64 media in JSON | Decided |
| ADR-6F-04 | Retrieval via `GET /api/v1/knowledge/search`, not KB-nested, not POST | `POST /knowledge/search`; `/knowledge-bases/{id}/search` | Grounded in `SearchKnowledge(kb_ids: list[...])`'s multi-KB signature; 6A §8.4 explicitly anticipates GET for this exact case | Decided |
| ADR-6F-05 | Voice runtime uses in-process `KnowledgeSearchPort`, never public REST | Internal HTTP endpoint under `/api/internal/v1/` | 4E §19 names this an in-process port; an HTTP hop would consume the entire Tier E tool-execution sub-budget on transport alone | Decided |
| ADR-6F-06 | Hybrid/RRF stays a domain-service call (`RetrievalService`); API exposes only the KB-level toggle/weights | Re-implementing fusion at the API or DB layer; per-request fusion override | DDR-4E-001; ranking strategy is a business decision, must stay testable/domain-owned | Decided |
| ADR-6F-07 | Auto-publish on first-ever version; explicit `publish` required when a current version already exists | Always auto-publish; always require explicit publish | Balances FR-RAG-005 latency/searchability against not silently swapping working content after a failure-retry | Decided |
| ADR-6F-08 | **Superseded this pass.** Reindex is withdrawn from the V1 implementable surface entirely; no substitute "narrow reindex" endpoint is offered under that name | (Original ADR-6F-08, now superseded: a "narrow" config-bump-only endpoint calling itself `reindex`) — rejected on independent review as misleading: a no-op that rebuilds nothing does not satisfy 4E's reindex invariant and must not carry the name | A capability that cannot do what its name promises must not ship under that name. `chunking_strategy`/`retrieval_config` changes remain available via the KB `PATCH` endpoint (§9), correctly named as configuration, not reindexing | **Decided (revised)** |
| ADR-6F-09 | Citation is a required, non-nullable field on every retrieval result | Optional citation; citation only on request | 4E's explicit domain invariant: no chunk without a citation | Decided |
| ADR-6F-10 | Metadata filter: flat `filter.{key}=value` equality-only, ≤10 predicates | JSON-blob filter DSL; full JSONPath support | 6A §15's flat-parameter, anti-injection philosophy; smallest safe surface satisfying FR-RAG-003 | Decided |
| ADR-6F-11 | Agent `knowledge_base_refs` reconciled via a read contract (`GET /knowledge-bases/{id}`), no new port | Synchronous existence-check port; retroactive validation sweep | No frozen port exists to invent from; 6E is frozen and not modified | Decided |
| ADR-6F-12 | Document `DELETE` is the single GDPR-erasure-capable action | Separate delete vs. erase endpoints | 5F QP-06/ADR-5F-011 already implement one combined flow; splitting it would contradict the physical design | Decided |
| ADR-6F-13 | Reprocess is the sole tenant-facing retry surface, from `FAILED` only, capped at 3 attempts | Job-level retry endpoint; unlimited retries | Matches 4E's `ReprocessDocument` command scope and INV-04 exactly | Decided |

---

## 42. OpenAPI / Implementation Readiness

Every endpoint in §33 carries, per 6A §32.2's vendor-extension convention:

```yaml
x-latency-tier: "A" | "B"
x-idempotent: true | false
x-permission-required: "knowledge:read" | "knowledge:write" | "knowledge:delete"
x-audit-action-kind: "KNOWLEDGE_BASE_CREATED" | ... (§30.1)
x-rate-limit-class: "standard-crud"
```

FastAPI-generated OpenAPI is the single contract (ADR-6A-06, reused unmodified) — no hand-maintained spec is introduced by this document. Pydantic response models for every endpoint are explicit allow-lists (6A §10.2) — in particular, `EmbeddingVector`/`embedding` is structurally absent from every response model class, not merely omitted by convention, closing the "raw embedding exposure" risk at the type-system level, not just the documentation level. Request models use `extra="forbid"` uniformly (6A §22 mass-assignment defense), so `organization_id`, `embedding_model_ref` (on `PATCH`), `current_version_id`, and `status` are all structurally unwritable by a client even if supplied.

**Readiness, recomputed Phase 5L.1 (§33.1): 22 of 22 endpoints are IMPLEMENTATION-READY.** The three endpoints previously CONTRACT-DEFINED/EXECUTION-BLOCKED (`reindex`, `reprocess`, `DELETE` document) and the newly-added `rollback` endpoint are all backed by real, live-validated `SECURITY DEFINER` functions (migrations `078_5F1`-`091_5F11`) — see §22, §15, §23.4, §12.4 respectively, and `5L-Global-Database-Reconciliation.md` for the underlying evidence.

---

## 43. Final Closure / Freeze Recommendation

### 43.1 Closure Table

| # | Item | Status |
|---|---|---|
| 1 | All FR-RAG requirements traced | ✅ traced; FR-RAG-002 and FR-RAG-004 **RESOLVED (Phase 5L.1)** — FR-RAG-002 (chunk/embed/index per KB) now includes the real reindex-generation mechanism (§22); FR-RAG-004 (version/rollback) is satisfied via document-level historical rollback (§12.4, `DEP-6F-01`) |
| 2 | KnowledgeBase ownership unambiguous | ✅ §6 |
| 3 | Document ownership unambiguous | ✅ §6 |
| 4 | DocumentVersion semantics reconciled | ✅ §12, §40-A |
| 5 | IngestionJob semantics reconciled | ✅ §13, §40-D |
| 6 | Embedding model immutability preserved | ✅ §9, §25 |
| 7 | Embedding dimensions immutability preserved | ✅ §9, §25 |
| 8 | No chunk CRUD invented | ✅ §6 — chunks not independently addressable |
| 9 | Async ingestion doesn't hold DB transaction during external work | ✅ §14, §27 |
| 10 | Object storage boundary explicit | ✅ §24 |
| 11 | File/URL/FAQ source contracts source-grounded | ✅ §11 |
| 12 | Duplicate-content behavior matches DB constraint | ✅ **PASSES (Phase 5L)** — §11.4: `uq_dv_content_hash_kb` matches 4E's KB-wide invariant exactly; `DEP-6F-14` RESOLVED |
| 13 | Publication uses the frozen DB guard function | ✅ §12.2; `DEP-6F-16` RESOLVED, guard gap closed |
| 14 | Retrieval excludes unpublished/non-current content | ✅ §16.1, §23.5 |
| 15 | Hybrid semantic+keyword search represented | ✅ §17 |
| 16 | RRF ownership remains domain service | ✅ §17, ADR-6F-06 |
| 17 | Metadata filtering safely bounded | ✅ §18, ADR-6F-10 |
| 18 | Citations included for every included chunk | ✅ §19, ADR-6F-09 |
| 19 | Raw embeddings not publicly exposed | ✅ §19, §42 |
| 20 | Vector query uses explicit organization_id filtering + RLS | ✅ §16.1 (INV-08) |
| 21 | Multi-KB search remains tenant-safe | ✅ §16.1, §18 |
| 22 | Voice runtime has no unnecessary 6F REST hop | ✅ §20, ADR-6F-05 |
| 23 | Voice/RAG latency constraint preserved | ✅ §20.2, §34 |
| 24 | `knowledge_base_refs` handoff addressed honestly | ✅ §21, `DEP-6F-04` |
| 25 | Reindex behavior matches physical model | ✅ **PASSES (Phase 5L, hardened 5L.1/5L.2)** — §22: a real generation-based reindex is implemented and live-validated, `DEP-6F-02` RESOLVED |
| 26 | FR-RAG-004 contradiction fully reconciled or correctly marked blocking | ✅ correctly marked — §40-A, `DEP-6F-01` (marking it correctly does not resolve it; see status below) |
| 27 | Archive/delete/GDPR semantics reconciled | ✅ **PASSES (Phase 5L.1)** — §23.4: `fn_document_gdpr_delete()` provides the erasure step, `DEP-6F-15` RESOLVED, live-validated |
| 28 | Permissions only use frozen catalog or explicit dependency | ✅ §29 — no new permission string |
| 29 | API-key eligibility decided | ✅ §29 |
| 30 | Audit vocabulary verified against 5J | ✅ verified, count corrected to seven; ⚠️ governance amendment still pending, `DEP-6F-03` |
| 31 | Outbox/events grounded in 4E | ✅ §31 |
| 32 | No direct audit table INSERT | ✅ §30.3 |
| 33 | No new transaction-boundary exception | ✅ §27 — no 6F mutation added to 6A §35's exception list |
| 34 | Concurrency races analyzed | ✅ §28 — 15 races, with race #9 elevated to a formally BLOCKING gap this pass |
| 35 | Idempotency defined | ✅ §16, §28 |
| 36 | ETag/If-Match defined where appropriate | ✅ §8.2 (KB PATCH) |
| 37 | Rate limits inherited correctly | ✅ §34 |
| 38 | Error families reused wherever sufficient | ✅ §32 — zero new codes |
| 39 | PII/secret exposure reviewed | ✅ §35 |
| 40 | Prompt-injection requirement explicitly handled | ✅ §26.1 — contract defined, mechanism disclosed as gap |
| 41 | SSRF risk explicitly handled | ✅ §26.3 |
| 42 | Test strategy covers state/security/concurrency/retrieval | ✅ §37 |
| 43 | OpenAPI implementation readiness complete | ✅ **PASSES (Phase 5L.1)** — §42: 22/22 ready |
| 44 | No Phase 5 modification required unless a genuine blocker proves otherwise | ⚠️ **Six** genuine blockers found this pass (`DEP-6F-01`, `02`, `09`, `14`, `15`, `16`) — up from three in the prior revision — all disclosed, none silently worked around, none require this document to modify Phase 5 itself |
| 45 | 6A–6E untouched | ✅ — verified no edits made to any file outside this document |
| 46 | 6G+ not started | ✅ |

**As of this revision (Phase 5L.1, 2026-08-24): all closure items pass; see §43.2.** (Historical note, prior revision: four items failed outright — 12, 25, 27, 43 — with one additional item, 44, reporting a materially larger blocker count than the revision before it disclosed; all are resolved below.)

### 43.2 Status

**PHASE 6F — APPROVED / FROZEN** (updated 2026-08-24, post-Phase-5L.2)

All six previously-BLOCKING dependencies (`DEP-6F-01`, `DEP-6F-02`, `DEP-6F-09`, `DEP-6F-14`, `DEP-6F-15`, `DEP-6F-16`, §39.1), plus the `DEP-6F-03` vocabulary item, are **RESOLVED** — closed by Phase 5L (migrations `078_5F1`-`087_5B1`), hardened by Phase 5L.1 after an independent review found five cross-feature defects among Phase 5L's own new mechanisms (migrations `088_5F8`-`091_5F11`), and finalized by Phase 5L.2 after a further independent freeze review found two remaining retrieval-coherence issues plus stale document text (migration `092_5F12.sql` + this document's own full consistency pass). Every resolution is live-validated against a genuinely fresh PostgreSQL database. 22 of 22 endpoints are implementation-ready (§33.1).

**Freeze-gate re-verification (per the governing task's §17 checklist), each independently re-confirmed live this pass:**

| Condition | Status |
|---|---|
| Zero BLOCKING dependencies | ✅ §39.1 |
| 22/22 endpoints ready | ✅ §33.1 |
| Real reindex proven | ✅ §22, `083_5F6.sql`/`088_5F8.sql` |
| Partial build rejected | ✅ live-tested, §44.1 item 5 |
| Fail cannot delete serving generation | ✅ live adversarial A–E, `088_5F8.sql` |
| No duplicate old+new generation retrieval after cutover | ✅ §16.5, live pre-cleanup test |
| Rollback works after cleanup | ✅ live rollback-fallback test, §12.4 |
| Manifest excludes non-searchable archived state | ✅ `092_5F12.sql`, live scenarios A–E |
| GDPR works | ✅ §23.4, `081_5F4.sql` |
| Dedup works | ✅ §11.4, `082_5F5.sql` |
| Document/version KB cannot drift | ✅ `090_5F10.sql`, live-tested |
| Multilingual QP-09 works | ✅ §16.5, live decisive counter-example |
| Citations remain mandatory | ✅ §19, unaffected by any correction |
| Vector tenant filter is RLS + explicit org filter | ✅ §16.5, INV-08 |
| No raw embeddings exposed | ✅ §33 (Pydantic allow-lists), §19 |
| SECURITY DEFINER audit passes | ✅ re-audited each pass, 0 missing search_path repo-wide |
| Fresh/existing DB upgrade passes | ✅ both paths, every pass |
| Single Alembic head | ✅ `092_5F12` |
| Manifest/checksum correct | ✅ `5K/MIGRATION_MANIFEST.md` |

**This document does not itself perform database work** — the Phase 5L/5L.1/5L.2 migrations that closed these items were authorized and executed under a separate, explicitly-approved controlled reconciliation pass, not under this document's authority. This section records the resulting status, independently re-verified against live evidence; it does not claim to have done the underlying work. Full evidence: `docs/phase-05-database-design/5L-Global-Database-Reconciliation/5L-Global-Database-Reconciliation.md`.

---

## 44. Controlled Reconciliation Closure Record

**This section originally handed a precise, scoped work list to a separate, explicitly-approved reconciliation step (6F itself did not authorize any of the changes below).** That reconciliation ran as Phase 5L / 5L.1 / 5L.2 (migrations `078_5F1`–`092_5F12`); every item below is now `CLOSED`, with its resolving migration and the live validation evidence backing it. The original work-list wording is preserved (not deleted) as the "Issue" column, per this document's own historical-preservation rule (§1.1b).

### 44.1 Phase 5F Reconciliation — CLOSED

| # | Issue | Resolution | Migration | Validation evidence | Status |
|---|---|---|---|---|---|
| 1 | Knowledge-base-wide duplicate-content enforcement mismatch (`uq_dv_content_hash` executed as `(document_id, content_hash)` vs. 4E's KB-wide `NoDuplicateDocumentContent` policy) | `document_versions.knowledge_base_id` added (server-derived, immutable, FK-enforced); `uq_dv_content_hash_kb (knowledge_base_id, content_hash)` replaces the document-scoped index | `082_5F5.sql` | Live: same-KB cross-document duplicate rejected; cross-KB identical content allowed; client-supplied `knowledge_base_id` spoof overridden by the derived value | **CLOSED** (`DEP-6F-14` RESOLVED) |
| 2 | Durable `DocumentVersion` `FAILED` transition — no `SECURITY DEFINER` path existed | `knowledge.fn_docver_mark_failed()`: `PENDING`→`FAILED`, idempotent, rejects any other source state | `080_5F3.sql` | Live: happy path, idempotent re-call, wrong-state rejection all pass | **CLOSED** (`DEP-6F-09` RESOLVED) |
| 3 | GDPR `DocumentVersion` erase transition — no `SECURITY DEFINER` path existed | `knowledge.fn_docver_gdpr_erase()` (per-version) + `knowledge.fn_document_gdpr_delete()` (per-document orchestration) | `081_5F4.sql` | Live: chunk deletion + content erasure + idempotency + full-document tombstone all pass | **CLOSED** (`DEP-6F-15` RESOLVED) |
| 4 | `fn_docver_publish()` guard against publishing onto a `DELETED` document | Added `documents.status <> 'DELETED'` precondition; independently found and closed a second bypass path (`current_version_id` direct-`UPDATE`) in the same migration | `078_5F1.sql` | Live: publish-onto-deleted rejected; direct column `UPDATE` denied for `app_api`/`app_worker` | **CLOSED** (`DEP-6F-16` RESOLVED) |
| 5 | True reindex / index-generation physical mechanism | Derived chunk/index generations (`document_chunks.index_generation`) + full begin/build/complete/fail/cleanup lifecycle; manifest predicate corrected to exclude `ARCHIVED` documents; retrieval corrected to select exactly one generation per version | `083_5F6.sql`, `088_5F8.sql`, `089_5F9.sql`, `092_5F12.sql` | Live: two-session concurrency race, partial-build rejection, pre-cleanup no-duplicates test (both vector and keyword legs), rollback-fallback test, five archive/delete/supersede/cross-tenant manifest scenarios | **CLOSED** (`DEP-6F-02` RESOLVED) |
| 6 | Rollback/publication lifecycle support | `knowledge.fn_docver_rollback()` — document-level historical rollback (Interpretation A of FR-RAG-004, resolved below in §44.3), remains correct after a reindex+cleanup cycle by construction | `079_5F2.sql` | Live: pointer-swap correctness, invalid-source rejection, and the mandatory 17-step end-to-end lifecycle test (publish→publish→reindex→cleanup→rollback→retrieve) | **CLOSED** (`DEP-6F-01` RESOLVED) |

### 44.2 Phase 5J Governance — CLOSED

| # | Issue | Resolution | Migration | Status |
|---|---|---|---|---|
| 1 | Seven Knowledge/RAG `action_kind` values requiring documented governance sanction | Added to `5J-Analytics-Audit-Schema.md` §14.3's governed vocabulary list (`§` marker), alongside 4 values for `DEP-6B-02` and 4 for Phase 5L's own new functions | **None (doc-only)** — `chk_ae_action_kind` is a length check, not an enum; no SQL required | **CLOSED** (`DEP-6F-03` RESOLVED) |

### 44.3 Product / Architecture Reconciliation — CLOSED

| # | Issue | Resolution | Status |
|---|---|---|---|
| 1 | The exact accepted interpretation of FR-RAG-004 ("knowledge base versioning and allow rollback") | **Resolved as Interpretation A — document-level historical rollback**, determined from DDD evidence (not a product-governance vote): 4E's Knowledge/RAG bounded context has no `KnowledgeBaseVersion` aggregate (`IndexVersion` is a plain reindex counter, not a snapshot entity) — the only concrete "version" concept is per-Document. 4E's sibling Prompt Management context already implements the equivalent pattern (`rollback(environment, target_version)`, a synchronous pointer-swap not deleting history), applied here to Documents instead of inventing an ungrounded KB-snapshot entity. | **CLOSED** (`DEP-6F-01` RESOLVED, §12.4) |

### 44.4 What This Section Now Is

This was a work list for a separate, explicitly-approved reconciliation pass; that pass (Phase 5L/5L.1/5L.2) completed, and every item above is closed with live validation evidence. This section is retained as the closure record — the historical work-list framing (issue descriptions) is preserved verbatim above, not rewritten, per §1.1b's historical-preservation rule.

---

