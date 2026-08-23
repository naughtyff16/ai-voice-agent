# 6F — Knowledge / RAG APIs

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6F

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6F-Knowledge-RAG-APIs.md |
| Phase | 6F (sixth document of Phase 6 — API Design) — **STRICT CORRECTION PASS 1** |
| Depends on | Phase 1 SRS (FR-RAG-001..005, FR-TEN-002/005, NFR-SEC-003/006), Phase 3D (Workflow/RAG LLD), Phase 3A/3B/3E/3F, Phase 4E (Knowledge & RAG DDD), Phase 4I (India-First closure, OQ-FINAL-03), Phase 5F (Knowledge/RAG Schema — design document), **the executed migrations `docs/phase-05-database-design/5K/migrations/034_5F.sql`–`038_5F.sql`, `043_5F.sql`, `044_5F.sql` (physical source of truth, §4.1)**, Phase 5B (Identity/RBAC), Phase 5J (Analytics/Audit), 6A (API Architecture & Standards), 6B (Auth API), 6C (Core Platform API), 6D (Voice/Call API), 6E (AI Agent API) |
| Status of dependencies | Phases 1–5 (5A–5J, 5K, 5K.1) and 6A–6E are **APPROVED / FROZEN**. No changes made to any of them by this document. |
| Author scope | Knowledge Base, Document, DocumentVersion, IngestionJob management and Knowledge retrieval/search API surface only. |
| Supersedes | Revision 1 of this document (2026-08-24, first draft) — corrected against executed migration reality per independent review |
| Governs | 6G onward may reference this document's resource ownership boundary but do not extend it. |
| Date | 2026-08-24 (correction pass) |
| **Status of this revision** | **PHASE 6F — REVISION REQUIRED.** Six genuine BLOCKING dependencies exist against the frozen physical schema (§39). This document is **not** freeze-eligible in this revision. See §43. |

---

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
| F-1 | FR-RAG-004 ("version knowledge bases and allow rollback") has no `KnowledgeBaseVersion` aggregate anywhere in 4E or 5F. The only physical versioning is per-Document (`document_versions` + `current_version_id`). | Adopted: "knowledge base versioning" is realized as **per-document version history + publication**, not a KB-level snapshot/rollback. True historical **rollback** (re-activating a `SUPERSEDED` version) has **no supporting `SECURITY DEFINER` function** — `fn_docver_publish()`'s precondition requires `status = 'READY'`, which a `SUPERSEDED` version never regains. This is `DEP-6F-01`, **BLOCKING** for full FR-RAG-004 compliance only (§40-A). |
| F-2 | 4E states a Knowledge Base in `REINDEXING` "continues to serve queries from the previous index version — the old index is only replaced when the new one is fully built." 5F has no per-chunk `index_version` column, no dual-generation index representation, and `document_chunks` is INSERT/DELETE-only (no UPDATE). Re-embedding an already-`READY` document's content under a new `document_versions` row collides with `uq_dv_content_hash` (identical bytes, prior version not excluded from the uniqueness scope since it is `SUPERSEDED`, not `FAILED`/`GDPR_ERASED`). | Adopted: `POST .../reindex` is designed as a **narrow, schema-safe** action (KB-level config bump + `index_version` increment, effective for **new** ingestions only). Full re-embedding of already-`READY` content across a KB is **not implementable** against the frozen schema without a new lifecycle function. `DEP-6F-02`, BLOCKING for full-reindex compliance only (§40-E). |
| F-3 | 4E's `Document` lifecycle names `ReprocessDocument` from `FAILED` only, and the design document's version of `uq_dv_content_hash` excludes rows with `status IN ('FAILED','GDPR_ERASED')` — implying reprocess is schema-safe once the prior version is `FAILED`. **However**, no executed migration (`034_5F.sql`–`038_5F.sql`) grants `app_api`/`app_worker` any path to ever set `document_versions.status = 'FAILED'`: `UPDATE`/`DELETE` are explicitly revoked (`036_5F.sql` line 82), and the only two executed lifecycle functions are `fn_docver_mark_ready()` and `fn_docver_publish()` — neither can transition a row to `FAILED`. | **Corrected finding, this pass:** the "consistent, not contradictory" conclusion from the prior revision was premature — it verified the *exclusion clause's* consistency but not whether the excluded state is *reachable*. It is not. Reprocess's precondition (§15) is real and documented, but its **execution is BLOCKED**: a retry version cannot legally be created while the prior `PENDING` (never-`FAILED`) row still occupies the `uq_dv_content_hash` slot. `DEP-6F-09`, **BLOCKING** (§15, §39). |
| F-4 | 4E's Document commands list has no explicit `GdprEraseDocument` command; the design document's `document_versions.status` enum includes `GDPR_ERASED`, and its QP-06/ADR-5F-011 describe a single combined "Delete / GDPR Erase Document" flow. **However**, no executed migration defines a `fn_docver_gdpr_erase()` (or equivalently named) function, and `036_5F.sql` revokes `UPDATE`/`DELETE` on `document_versions` from every application role unconditionally — there is no legal path today for `app_api`/`app_worker` to set `storage_ref='ERASED'`/`content_hash='ERASED'`/`status='GDPR_ERASED'` on an existing row. | **Corrected finding, this pass:** `DELETE /documents/{id}`'s **contract** is still the single, combined GDPR-erasure-capable action (one action, not two) — but its **execution is BLOCKED** for the version-erasure step specifically. `DEP-6F-15`, **BLOCKING** (§23, §39). |
| F-5 | 6E's `DEP-6E-04` records `knowledge_base_refs` existence/ownership validation as explicitly unresolved, NON-BLOCKING, "ownership belongs to 6F." No existence-check port is defined anywhere in Phase 4. | Adopted: 6F defines the **authoritative read contract** (`GET /knowledge-bases/{kb_id}`) any caller may use to check existence/ownership/status, but does **not** invent a synchronous cross-context call from 6E. Runtime resolution via `KnowledgeSearchPort` fails soft on a missing/non-`ACTIVE` KB. `DEP-6F-04`, NON-BLOCKING (§21). This finding is unaffected by this correction pass. |
| F-6 | 5J's `action_kind` vocabulary has `KNOWLEDGE_BASE_CREATED`, `KNOWLEDGE_BASE_DELETED`, `DOCUMENT_DELETED` but no values for KB update/archive/reindex, document upload/archive/reprocess, or version publish. | **Corrected count, this pass:** the prior revision's §30 said "six new values" while its own table listed **seven** (`KNOWLEDGE_BASE_UPDATED`, `KNOWLEDGE_BASE_ARCHIVED`, `KNOWLEDGE_BASE_REINDEX_TRIGGERED`, `DOCUMENT_UPLOADED`, `DOCUMENT_ARCHIVED`, `DOCUMENT_REPROCESS_REQUESTED`, `DOCUMENT_VERSION_PUBLISHED`). Corrected to **seven** everywhere in this document. The DB `CHECK` constraint (`chk_ae_action_kind`, a length check, not an enum) *physically accepts* any of these seven strings today, but **physical acceptance is not governance approval** — none of the seven is yet a *documented, sanctioned* value in 5J §14.3. `DEP-6F-03`, NON-BLOCKING for 6F's own execution (the strings can legally be inserted), but a controlled 5J vocabulary amendment is required before 6F's audit surface is fully governance-compliant (§30.2, §44). |
| F-7 | **New finding, this pass.** The design document (`5F-Knowledge-RAG-Schema.md`) states `uq_dv_content_hash` as `(knowledge_base_id, content_hash)` and frames `NoDuplicateDocumentContent` (4E §10) as "same `ContentHash` in same KB is rejected." The **executed** `036_5F.sql` instead creates `uq_dv_content_hash ON knowledge.document_versions (document_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')`, with an explicit in-file comment: `document_versions` has no `knowledge_base_id` column, so the constraint was corrected to `document_id` scope during migration authoring. | **This is a genuine, unresolved DDD-to-migration inconsistency**, not a restatement. Physical reality: a duplicate version of the **same document** is rejected (relevant only to reprocess, F-3); two **different** documents in the **same KB** with identical content are **not** rejected by any DB constraint. 4E's `NoDuplicateDocumentContent` policy is therefore **not enforced** by the executed schema at the KB level it was specified for. `DEP-6F-14`, **BLOCKING**. The prior revision's entire §11 "duplicate content" narrative assumed the design document's (now-superseded-by-migration) KB-wide scope and is corrected throughout this pass (§11.4, §28, §32, §40-J). |
| F-8 | **New finding, this pass.** `fn_docver_publish()` as executed (`034_5F.sql`) validates `version_id`/`document_id`/`organization_id`/`status='READY'` but has no precondition on `documents.status`. A concurrent/late-committing publish can therefore set `documents.current_version_id`/`status='READY'` on a document whose delete flow has already tombstoned it (`status='DELETED'`). | `DEP-6F-16`, **BLOCKING** for closing this specific race (§12.2, §23, §28 race #9, §39). Does not block ordinary, non-racing publish operation. |

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
| `/api/v1/knowledge-bases/{kb_id}/reindex` | POST | **CONTRACT-DEFINED, EXECUTION BLOCKED.** See §22 — this is not a functioning "reindex" and must not be presented as one; retained only as a forward-looking contract | `knowledge:write` | Tier B | — | Not part of the V1 implementable surface. `DEP-6F-02`, BLOCKING. See §22 for the full, corrected treatment — the prior revision's "narrow reindex" characterization is withdrawn (§22.2). |

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
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/reprocess` | POST | Retry ingestion from `FAILED` (showcase, §15) | `knowledge:write` | Tier B | — | **CONTRACT-DEFINED, EXECUTION BLOCKED** — `DEP-6F-09` (§15) |
| `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | DELETE | Soft-delete + content erasure (§23) | `knowledge:delete` | Tier B | — | **CONTRACT-DEFINED, EXECUTION BLOCKED** for the version-erasure step — `DEP-6F-15` (§23) |
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
| **Duplicate-content outcome — corrected this pass** | **`uq_dv_content_hash` is executed as `(document_id, content_hash)` (§4.1, §5 F-7), not `(knowledge_base_id, content_hash)`.** For the *first* version of a *newly registered* document, `document_id` is freshly generated and has no prior rows — there is structurally **no way for this `INSERT` to collide**, regardless of whether another document (in this KB or any other) already holds identical content. **This document's, and 4E's, "duplicate document upload is rejected within a KB" behavior is therefore not enforced by the executed schema — `DEP-6F-14`, BLOCKING.** The one case where `uq_dv_content_hash` genuinely fires is a **second** version of the **same** `document_id` sharing content with a still-non-`FAILED`/non-`GDPR_ERASED` prior version of *that same document* — relevant only to reprocess (§15), which is itself execution-blocked by `DEP-6F-09`. |
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

**No source type's initial registration is protected against KB-wide duplicate content by the executed schema.** The design document's and 4E's stated `NoDuplicateDocumentContent` guarantee ("same content hash in same KB is rejected") does not hold physically. This is `DEP-6F-14`, BLOCKING, and is the single most significant correction in this pass (§5 F-7, §40-J).

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
| Concurrency | See §28 races 7/8/9. **Race 9 is a genuine, disclosed integrity gap, not merely an accepted narrow race:** the executed `fn_docver_publish()` (`034_5F.sql`) checks `version_id`/`document_id`/`organization_id`/`status='READY'` only — it has **no precondition on `documents.status`**, so a publish that commits after a concurrent delete's tombstone step can re-set `current_version_id`/`status='READY'` on an already-`DELETED` document. `DEP-6F-16`, BLOCKING for closing this race (does not block ordinary, non-racing publish). |
| PII/security | None |
| **Readiness** | **IMPLEMENTATION-READY for the core, non-racing operation** — `fn_docver_publish()` exists, is granted, and functions exactly as specified for a normal publish. The `DEP-6F-16` race is a disclosed integrity gap on top of working functionality, not an execution blocker for the endpoint itself. |

### 12.3 Auto-Publish vs. Explicit Publish (ADR-6F-07)

| Scenario | Behavior |
|---|---|
| First-ever successful ingestion of a Document (`current_version_id IS NULL`) | The ingestion worker calls `fn_docver_mark_ready()` **then immediately** `fn_docver_publish()` in the same pipeline run — **auto-published**. There is nothing at risk to protect, and gating the very first version behind a manual step would delay searchability with no safety benefit (contradicts FR-RAG-005's "bounded latency" spirit — a document should become queryable as soon as it is ready). |
| A later version succeeds while a current version already exists (i.e., a `reprocess`-after-`FAILED` recovery, §15) | The worker calls `fn_docver_mark_ready()` **only** — it does **not** auto-publish. The tenant must call `POST .../publish` explicitly. Rationale: a document that already has working, searchable content should never be silently swapped out by a background retry the tenant didn't confirm. **This entire scenario is currently unreachable in practice**, because the reprocess action that would produce this "later version" is itself execution-blocked (`DEP-6F-09`, §15) — this row documents the intended contract for when that dependency is resolved, not a currently-exercisable path. |

### 12.4 Rollback — What Is and Is Not Supported

`GET .../versions` gives full, honest history (audit/traceability satisfied). **There is no rollback endpoint** — re-activating a `SUPERSEDED` version has no supporting `fn_docver_publish()` path (its precondition requires `status = 'READY'`, which a `SUPERSEDED` row never regains) and no other 5F function exists for it. This is `DEP-6F-01`, formally recorded in §39 and analyzed in §40-A. FR-RAG-004's "rollback" is satisfied only in the forward sense — uploading a corrected version and publishing it — not as historical restoration.

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

**On ingestion failure at any stage — verified directly against the executed migrations, not the design document (§4.1):** `ingestion_jobs.status → 'FAILED'`, `error_message` set — this part works: `037_5F.sql` grants `app_worker` `UPDATE` on `ingestion_jobs` unconditionally, and `prevent_completed_job_mutation()` only blocks mutation of an already-`READY` row, so transitioning a job to `FAILED` is fully legal. **The corresponding `document_versions` row, however, cannot be transitioned to `FAILED` at all**: `036_5F.sql` line 82 is `REVOKE UPDATE, DELETE ON knowledge.document_versions FROM app_api, app_worker` — unconditional, no carve-out — and the only two executed lifecycle functions (`fn_docver_mark_ready()`, `fn_docver_publish()`, both in `034_5F.sql`) transition a version **out of** `PENDING`/`READY` respectively, never **into** `FAILED`. There is no `fn_docver_mark_failed()` (or equivalently named function) anywhere in `034_5F.sql`–`044_5F.sql`. This is `DEP-6F-09` (§39), **BLOCKING**: a failed ingestion's `document_versions` row is permanently stuck at `status='PENDING'` — a state with no further legal application-layer transition — while `ingestion_jobs.status='FAILED'` correctly reflects the failure at the job-tracking level. Reprocess eligibility (§15) is therefore keyed off **`ingestion_jobs.status = 'FAILED'`** (the one signal that is actually reachable), but reprocess's own `INSERT` is separately blocked by the same underlying gap (§15.1).

---

## 15. Reprocess / Retry Semantics (Showcase 4: Reprocess Document) — CONTRACT-DEFINED, EXECUTION BLOCKED

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
| **Readiness** | **CONTRACT-DEFINED, EXECUTION BLOCKED.** `DEP-6F-09`, BLOCKING. No `SECURITY DEFINER` path exists to move a failed `document_versions` row out of `PENDING`, so the required `INSERT` for the retry version cannot legally succeed against the executed schema. This is not an edge case — it is the **normal-path** consequence of the very first ingestion failure for any document, so reprocess cannot be exercised at all in the current physical schema, not merely under contention. |

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
| DB / query | Parallel: 5F QP-08 (vector, HNSW, publication-gated) + QP-09 (full-text, GIN, publication-gated) — every table/column/index these query patterns depend on (`document_chunks.embedding`, the HNSW index, `tsvector_content`/GIN, `documents.current_version_id`) was independently re-verified present in the executed `038_5F.sql`/`036_5F.sql` in this pass; unaffected by any of the six BLOCKING dependencies |
| **Readiness** | **IMPLEMENTATION-READY.** None of the three DDD-vs-migration divergences found in this pass touch retrieval's read path. |
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

## 22. Reindex / Index-Version Semantics (ADR-6F-08) — CONTRACT-DEFINED, EXECUTION BLOCKED (corrected this pass)

**Correction notice:** the prior revision of this document defined a "narrow reindex" — incrementing `index_version` and cycling `status: ACTIVE → REINDEXING → ACTIVE` while re-chunking/re-embedding nothing — and presented it as the implemented behavior of `POST .../reindex`. An independent review correctly identified that this is **not reindexing** in any sense 4E's `TriggerReindex` command or FR-RAG-003/004's retrieval-quality intent describe: incrementing a bookkeeping counter while rebuilding no index is a no-op wearing a reindex's name. **That characterization is withdrawn.** This section now treats `POST .../reindex` as a **contract-defined, execution-blocked** endpoint — not part of 6F's V1 implementable surface — and explains precisely what is and is not physically possible, without redefining "reindex" to mean something it does not.

### 22.1 What `index_version` Actually Represents

`knowledge_bases.index_version INTEGER` is a single, KB-level bookkeeping counter, confirmed present exactly as such in the executed `035_5F.sql` — there is no per-chunk or per-partition "generation" column anywhere in `document_chunks` (`038_5F.sql`), and no dual-index-generation representation exists in the physical schema (§5 F-2, full analysis §40-E).

### 22.2 What a Real Reindex Would Require, and Why None of It Is Physically Available

4E's `TriggerReindex`/`REINDEXING` semantics require, at minimum: (a) re-chunking and re-embedding every `READY` document in the KB under the KB's current `chunking_strategy`, (b) the *old* chunks remaining queryable throughout, and (c) an atomic cutover to the *new* chunks once rebuilt, with `index_version` advancing to mark the cutover. None of (a)–(c) has a supported execution path in the executed schema:

- **(a) is blocked by `DEP-6F-14`/`uq_dv_content_hash`'s scope in the case of a same-document re-ingest**, and has no supported "re-chunk in place" function at all — `document_chunks` is `INSERT`/`DELETE`-only (`038_5F.sql` line 43, `REVOKE UPDATE`), and the one field that would need to change consistently with a new chunk set, `document_versions.chunk_count`, is set exactly once by `fn_docver_mark_ready()` and never revisited by any executed function.
- **(b) and (c) require a dual-generation representation** (old chunks queryable while new chunks build, then an atomic swap) that no column, index, or function in `034_5F.sql`–`044_5F.sql` provides.
- There is no `fn_docver_reindex()` or equivalently named function anywhere in the executed migration set.

**Conclusion: a full KB reindex is not implementable against the frozen physical schema, full stop — not "narrowly implementable," not "implementable if redefined."** This is `DEP-6F-02`, **BLOCKING**.

### 22.3 What This Document Does *Not* Offer as a Substitute

The prior revision's "bump `index_version`, cycle `status`, rebuild nothing" behavior is **removed from this document as an implementable endpoint.** It is not offered as a lesser form of reindexing, because it is not a form of reindexing at all — it is a metadata write with no relationship to index quality or content freshness, and presenting it under the `reindex` name would mislead a caller into believing retrieval quality had changed when it had not. If a future Phase 5 amendment adds the missing lifecycle function(s) and dual-generation representation, `POST .../reindex` can be implemented against this same contract (§22 heading, request/response shape) without a URL or method change.

**What a tenant *can* legitimately do today to change future retrieval behavior:**

- `PATCH /knowledge-bases/{kb_id}` (§8.2, §9) to change `chunking_strategy`/`retrieval_config` — takes effect for **documents ingested from this point forward only**; already-`READY` documents keep the chunk layout/embeddings they were ingested with, indefinitely, until individually reprocessed (§15 — itself execution-blocked, `DEP-6F-09`) or deleted (§23 — itself execution-blocked for full erasure, `DEP-6F-15`) and re-uploaded as a new document.
- This is a **real, useful, implementation-ready capability** (§9), but it is a KB **configuration** change, not a reindex, and this document does not call it one.

### 22.4 Reindex While Already Reindexing / `409` Semantics

Not applicable in this revision — `POST .../reindex` is not offered as an implementable endpoint (§22.3), so there is no `REINDEXING` state a tenant-facing action can enter or race against. `knowledge_bases.status = 'REINDEXING'` remains a valid CHECK-constraint value (`035_5F.sql`) for a future implementation to use, but no 6F endpoint sets it today.

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

### 23.4 Document Delete — Also the GDPR Erasure Path (F-4, §5) — CONTRACT-DEFINED, EXECUTION BLOCKED

`DELETE /api/v1/knowledge-bases/{kb_id}/documents/{document_id}` (§10.1) is designed as a single action implementing the design document's QP-06/ADR-5F-011 flow:

1. `DELETE FROM document_chunks WHERE document_id = ... AND organization_id = ...` — chunks physically removed, immediately excluding the document from retrieval. **IMPLEMENTATION-READY** — `038_5F.sql` grants `app_api`/`app_worker` `DELETE` on `document_chunks` unconditionally.
2. GDPR-erase every version's content references (`storage_ref='ERASED'`, `content_hash='ERASED'`, `status='GDPR_ERASED'`). **EXECUTION BLOCKED.** No executed migration (`034_5F.sql`–`044_5F.sql`) defines a `fn_docver_gdpr_erase()` or equivalently named `SECURITY DEFINER` function, and `036_5F.sql` line 82 unconditionally revokes `UPDATE`/`DELETE` on `document_versions` from `app_api`/`app_worker` — there is no legal path today to write `storage_ref='ERASED'`/`content_hash='ERASED'`/`status='GDPR_ERASED'` on an existing row, immutability-trigger compliance exception or not, because the trigger's exception only matters once a caller has UPDATE privilege to invoke, and no role granted that privilege exists. `DEP-6F-15`, **BLOCKING**.
3. `UPDATE documents SET status='DELETED', current_version_id=NULL, original_filename=NULL, deleted_at=NOW()` — the row survives as an audit tombstone (6A §7.6's soft-delete pattern, `documents` explicitly named there). **IMPLEMENTATION-READY in isolation** — `036_5F.sql` grants `UPDATE` on `documents` — but see the ordering note below.
4. S3 object deletion — a **separate**, best-effort application-layer `ObjectStorePort.delete()` call, outside the DB transaction, eventually consistent (6A §35 — never hold a transaction across an external call). **IMPLEMENTATION-READY** (no DB dependency).

**Because step 2 cannot legally execute, this document does not offer a version of `DELETE` that silently skips it.** Skipping step 2 while still performing steps 1/3/4 would leave `document_versions.storage_ref`/`content_hash` pointing at now-orphaned-but-unerased content references — a materially different (and materially weaker) compliance posture than the one this document's title, `documents.metadata`'s `pii:potential` classification, and NFR-COMPLY-001 require. **The whole `DELETE` action is therefore held as execution-blocked, not partially implemented.**

| Field | Value |
|---|---|
| Success status | `202 Accepted` (intended — not currently reachable end-to-end) |
| Errors | `404` |
| Idempotency | Deleting an already-`DELETED` document is intended to be a no-op `202` |
| **Readiness** | **CONTRACT-DEFINED, EXECUTION BLOCKED.** `DEP-6F-15`, BLOCKING. Steps 1, 3, and 4 are individually implementation-ready; step 2 has no legal execution path, and this document does not ship a partial/degraded delete that omits it. |
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
| Reprocess document | Precondition read (`ingestion_jobs.status='FAILED'`, `attempt_count<3`) | — | — | — | — | **BLOCKED — `DEP-6F-09`.** The `INSERT document_versions` step cannot legally succeed (§15.1) |
| Publish version | — | `SELECT fn_docver_publish(...)` | Yes | Function's internal commit | Audit (async) | READY (core operation); `DEP-6F-16` integrity gap disclosed separately |
| Delete document | — | — | — | — | — | **BLOCKED — `DEP-6F-15`.** Step 2 (version content erasure) has no legal execution path; the action is held blocked rather than run partially (§23.4) |
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
| 3 | Duplicate document upload (same content) | **Corrected this pass:** two different documents (even in the same KB) with identical content are **not** prevented by any constraint — `uq_dv_content_hash` is `(document_id, content_hash)` (§5 F-7), and each new document has a fresh `document_id`. `DEP-6F-14`, BLOCKING. The *only* race `uq_dv_content_hash` actually guards is two concurrent attempts to re-ingest the **same** document's content (relevant to reprocess, itself blocked — race #5) |
| 4 | Document upload vs. document delete | If delete commits first, the async pipeline's later steps operate against a `documents` row already `status='DELETED'` — the worker checks document status before each stage transition and aborts the pipeline (job → `CANCELLED`) rather than reviving a deleted document. Unaffected by this pass — delete's step 1/3/4 are individually legal even though the overall action is held blocked pending `DEP-6F-15`; this race concerns ordering between two operations that are each independently reachable in a partial-execution sense, so it is retained as a documented design intent |
| 5 | Two reprocess requests on the same document | Moot while `DEP-6F-09` is unresolved — neither request's `INSERT document_versions` can succeed (§15.1), so there is no race to lose; both would receive whatever error the blocked `INSERT` surfaces |
| 6 | Ingestion retry vs. worker completion | Not applicable in this design — retry (reprocess) always creates a **new** job row rather than racing an in-place retry of an existing one; the existing `READY` job (INV-06) is immutable and cannot be concurrently mutated. (Moot alongside #5 while reprocess is blocked.) |
| 7 | Two attempts to publish the same document version | Both call `fn_docver_publish()` with the same `version_id`; the function is not `SERIALIZABLE`, but its own internal `UPDATE ... WHERE id = v_old_version_id` and `UPDATE documents SET current_version_id = ...` are idempotent in effect — the second call re-supersedes an already-`SUPERSEDED` old version (no-op) and re-sets the same `current_version_id` (no-op); both callers observe `200`. Unaffected by this pass — publish's core function is READY. |
| 8 | Two different `READY` versions published concurrently | Both transactions call `fn_docver_publish()` for different `version_id`s on the same `document_id`; under `READ COMMITTED`, whichever commits last wins — `documents.current_version_id` ends up pointing at the later-committing call's version, and the earlier one is left `SUPERSEDED` even though it "won" the race first. This is a disclosed, narrow, non-serializable race, matching the same class of accepted race 6E's own `AgentVersion` publish path documents (6E §15.2) — no `SELECT ... FOR UPDATE` is introduced (6A §17.3). Unaffected by this pass. |
| 9 | Publish-version vs. document delete/GDPR erase | **Elevated this pass, from an accepted narrow race to a formally BLOCKING gap.** `fn_docver_publish()` (verified against the executed `034_5F.sql`) checks `version_id`/`document_id`/`organization_id`/`status='READY'` only — it has **no precondition on `documents.status`**. If delete's tombstone step (§23.4 step 3) commits, then a concurrent publish commits after it, `fn_docver_publish()` would re-set `current_version_id`/`status='READY'` on an already-`DELETED` document, reviving its publication state. `DEP-6F-16`, **BLOCKING** for closing this race — the function needs a `documents.status != 'DELETED'` guard that does not exist today. In practice, this race's *worst* manifestation (chunks reappearing for a deleted document) cannot currently occur, because delete's own step 1 (chunk removal) is independently reachable and step 2/3 gating means the overall `DELETE` action is held blocked (§23.4) — but the gap in `fn_docver_publish()` itself is real and independent of that. |
| 10 | Reindex requested while already `REINDEXING` | Not applicable — `POST .../reindex` is not offered as an endpoint in this revision (§22.3, `DEP-6F-02`) |
| 11 | Archive KB while ingestion is running | Not prevented — an in-flight `ingestion_jobs` row continues to completion independent of the KB's `status`; the resulting `READY` chunks simply never surface in retrieval because the KB-level `ARCHIVED` exclusion (§23.5) is checked at query time, not at ingestion time. Unaffected by this pass. |
| 12 | Retrieval while reindex is running | Not applicable — reindex is not an implementable action in this revision (§22); retrieval is simply unaffected by anything in §22 |
| 13 | Retrieval while a new version becomes current | `GET /knowledge/search`'s QP-08/QP-09 join `documents.current_version_id = dv.id` inside its own single query execution — under `READ COMMITTED`, the query sees whichever `current_version_id` was committed at the instant the query's snapshot was taken; it never sees a partially-published mixed state, because `fn_docver_publish()`'s `UPDATE documents` is a single atomic statement (one row, one commit) |
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
| 6 | POST | `/api/v1/knowledge-bases/{kb_id}/reindex` | `knowledge:write` | Required | B | — | **CONTRACT-DEFINED, EXECUTION BLOCKED** — `DEP-6F-02` (§22) |
| 7 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/upload-url` | `knowledge:write` | Required | A | 201 | **IMPLEMENTATION-READY** |
| 8 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/complete` | `knowledge:write` | — | A (enqueue) | 202 | **IMPLEMENTATION-READY** (dedup caveat, `DEP-6F-14`, disclosed §11.4 — does not block execution) |
| 9 | POST | `/api/v1/knowledge-bases/{kb_id}/documents` (URL/WEBSITE) | `knowledge:write` | Required | A (enqueue) | 202 | **IMPLEMENTATION-READY** (same dedup caveat) |
| 10 | POST | `/api/v1/knowledge-bases/{kb_id}/documents` (FAQ) | `knowledge:write` | Required | B | 201 | **IMPLEMENTATION-READY** (same dedup caveat) |
| 11 | GET | `/api/v1/knowledge-bases/{kb_id}/documents` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 12 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 13 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/reprocess` | `knowledge:write` | Required | B | — | **CONTRACT-DEFINED, EXECUTION BLOCKED** — `DEP-6F-09` (§15) |
| 14 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/archive` | `knowledge:write` | Required | A | 200 | **IMPLEMENTATION-READY** |
| 15 | DELETE | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | `knowledge:delete` | — | B | — | **CONTRACT-DEFINED, EXECUTION BLOCKED** — `DEP-6F-15` (§23.4) |
| 16 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 17 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 18 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/publish` | `knowledge:write` | Recommended | A | 200 | **IMPLEMENTATION-READY** for the core operation; `DEP-6F-16` integrity gap disclosed separately (§28 race 9) — does not block ordinary use |
| 19 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 20 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs/{job_id}` | `knowledge:read` | — | A | 200 | **IMPLEMENTATION-READY** |
| 21 | GET | `/api/v1/knowledge/search` | `knowledge:read` | — | B | 200 | **IMPLEMENTATION-READY** |

### 33.1 Readiness Summary

| Classification | Count | Endpoints |
|---|---|---|
| **IMPLEMENTATION-READY** | 18 | 1–5, 7–12, 14, 16–21 |
| **CONTRACT-DEFINED, EXECUTION BLOCKED** | 3 | 6 (reindex, `DEP-6F-02`), 13 (reprocess, `DEP-6F-09`), 15 (delete, `DEP-6F-15`) |
| **DEFERRED / NOT EXPOSED** | 0 | — |

21 endpoints total — every one traced to a 4E command/query and a 5F table/function in §5, §8–§16, §21–§23. **18 of 21 are implementation-ready; 3 are contract-defined but execution-blocked pending a Phase 5 amendment (§44).** This is a materially different, and materially more conservative, statement than the prior revision's readiness claim — it reflects an endpoint-by-endpoint re-verification against the executed migrations, not the design document's prose.

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
| FR-RAG-002 (chunk, embed, index per tenant/KB) | §3.8 | §9.3–9.4 | §4.1–4.4, `NoDuplicateDocumentContent` policy | OQ-FINAL-03 | `chunking_strategy`, `document_chunks`, `uq_dv_content_hash` | — | — | — | — | §14 — **partially covered**: chunk/embed/index pipeline is fully covered; the policy's duplicate-content dimension is **not enforced** by the executed schema at KB scope, `DEP-6F-14` BLOCKING |
| FR-RAG-003 (hybrid search + metadata filter) | §3.8 | §9.5 | §4.4 RRF | §25.16 GIN index | QP-08/QP-09, GIN | §15 filter syntax | — | — | — | §16–18 — **fully covered** |
| FR-RAG-004 (KB versioning + rollback) | §3.8 | §7.2 (prompt, not KB) | §4.2 `Document`/`DocumentVersion` | — | `document_versions`, `current_version_id` | §17.2 concurrency | — | — | — | §12.4 — **partially covered**: version history + forward publication yes; true rollback **not implemented**, `DEP-6F-01` **BLOCKING** — 6F cannot claim this requirement closed until product/architecture governance formally accepts forward-only publication as FR-RAG-004's satisfying interpretation, or a physical rollback mechanism is added (§40-A, §44) |
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

**Note (Phase 5L, 2026-08-24):** all six of this register's `BLOCKING` items, plus the `DEP-6F-03` vocabulary item, are now `RESOLVED` at the database layer — see the rows above and the Phase 5L report. This does **not** itself flip this document's own freeze-eligibility banner (§43) or the "REVISION REQUIRED" status stated at the top of this document; that editorial verdict is for the independent review the Phase 5L authorizing task explicitly reserves, not this amendment.

**Six BLOCKING dependencies exist. Per §43, Phase 6F cannot be APPROVED/FROZEN while any BLOCKING dependency remains open — this is dispositive, not a judgment call left to per-item "sub-capability only" framing.**

---

## 40. High-Risk Contradiction Check

### A. FR-RAG-004 "versioning and rollback" vs. 4E's aggregate model vs. 5F's `DocumentVersion`/`current_version_id`/`index_version`

- **SRS position:** "System shall version knowledge bases and allow rollback" (P1).
- **4E position:** No `KnowledgeBaseVersion` aggregate anywhere — only `KnowledgeBase.IndexVersion` (an integer bumped on reindex) and the separate `Document`/`DocumentVersion` model.
- **5F position:** Implements `document_versions` + `documents.current_version_id` with `fn_docver_publish()` as the only state-transition path, `READY`-only precondition, no return path from `SUPERSEDED`.
- **Determination:** 5F (later, frozen, physical) is authoritative over 4E's illustrative "versioned and allow rollback" phrasing, which was never given a concrete rollback mechanism to begin with. The requirement is **partially** satisfiable: version **history** and forward **publication** are fully implemented; historical **rollback** is not. `DEP-6F-01`, BLOCKING for that sub-capability, does not block the rest of the document.

### B. 4E Document lifecycle terminology vs. 5F actual statuses

- 4E's Document state diagram (§7.1) uses `UPLOADED|PROCESSING|PARSING|CHUNKING|EMBEDDING|INDEXING|INDEXED|ARCHIVED|DELETED|FAILED`.
- 5F's `documents.status` CHECK is the coarser `PENDING|PROCESSING|READY|FAILED|ARCHIVED|DELETED`; the fine-grained pipeline stages (`PARSING/EXTRACTING|CHUNKING|EMBEDDING|INDEXING`) live on `ingestion_jobs.status`/`current_stage` instead, and `INDEXED` is renamed `READY` at the document/version level.
- **Determination:** not a contradiction — 5F's ADR-5F-004 explicitly documents this as **two separate, intentional state machines** (worker execution state vs. durable version lifecycle), and 6F's IngestionJob API (§13) and Document API (§10) reflect exactly this split rather than forcing 4E's single fine-grained diagram onto the physical model.

### C. 4E duplicate-content semantics vs. the executed `uq_dv_content_hash` scope — CORRECTED, GENUINE CONTRADICTION FOUND

- **4E position:** "a document with the same hash in the same Knowledge Base is rejected" (Document invariant 1) — KB-wide scope.
- **5F design-document position:** describes `uq_dv_content_hash` as `(knowledge_base_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')` — matches 4E.
- **Executed migration position (`036_5F.sql`):** `uq_dv_content_hash ON knowledge.document_versions (document_id, content_hash) WHERE status NOT IN ('FAILED','GDPR_ERASED')` — **document-scoped, not KB-scoped**, with an explicit in-file comment explaining the correction was necessary because `document_versions` carries no `knowledge_base_id` column.
- **Determination, corrected this pass:** the prior revision's "consistent — 5F is the precise implementation of 4E's stated rule" conclusion was reached by reading only the design document, not the executed SQL, and is **withdrawn**. The executed migration diverges from both 4E's invariant and the design document's own prose. **This is a genuine, unresolved DDD-to-migration contradiction, not a restatement.** The `WHERE` clause's exclusion of `FAILED`/`GDPR_ERASED` rows is correctly preserved either way and does make reprocess-from-`FAILED` schema-safe *in principle* (finding F-3) — but the primary KB-wide duplicate-rejection guarantee 4E and the design document both describe does not hold physically. `DEP-6F-14`, **BLOCKING**, requires a controlled Phase 5F reconciliation (§44) to decide the correct physical enforcement mechanism; 6F does not presume or invent that resolution.

### D. 4E ingestion lifecycle vs. 5F's actual `ingestion_jobs` status enum/functions

- Consistent, per B above — `ingestion_jobs` implements 4E's `IngestionJob` aggregate's stage progression essentially verbatim (`PENDING|EXTRACTING|CHUNKING|EMBEDDING|INDEXING|READY|FAILED|CANCELLED` vs. 4E's `PENDING|PARSING|CHUNKING|EMBEDDING|INDEXING|COMPLETED|FAILED` — `EXTRACTING`≈`PARSING`, `READY`≈`COMPLETED`, plus `CANCELLED` added). No contradiction; a naming/enum-value evolution 5F is authoritative for.

### E. 4E's "old index remains queryable while REINDEXING" vs. 5F's physical capability to represent two index generations — CORRECTED, POSTURE WITHDRAWN

- **4E position:** stated as an invariant of `KnowledgeBase` (§4.1 inv. 3): old generation queryable while new generation builds, then atomic cutover.
- **Executed migration position:** no per-chunk generation column anywhere in `document_chunks` (`038_5F.sql`), no dual-index representation, `document_chunks` is `INSERT`/`DELETE`-only, and `uq_dv_content_hash` (as corrected in finding C above) blocks re-ingesting identical content under a `SUPERSEDED`/`READY` prior version of the same document.
- **Determination, corrected this pass:** genuinely **not implementable** as a full-KB re-embed operation — this part of the prior revision's conclusion stands. **What is withdrawn is the prior revision's resolution**: redefining `POST .../reindex` to mean "bump `index_version`, rebuild nothing" and treating 4E's invariant as "trivially satisfied" by that redefinition is an independent-review-identified error — a no-op dressed as a reindex does not satisfy an invariant about index rebuilding; it sidesteps the question by ensuring the invariant's precondition (a rebuild is happening) never occurs. **Corrected posture (§22):** the endpoint is withdrawn from the V1 implementable surface entirely. `DEP-6F-02`, BLOCKING, requires a controlled Phase 5F reconciliation (§44) to decide whether and how a true reindex mechanism is added.

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

**Readiness, recomputed this pass (§33.1): 18 of 21 endpoints are IMPLEMENTATION-READY. 3 (`reindex`, `reprocess`, `DELETE` document) are CONTRACT-DEFINED, EXECUTION BLOCKED — not "contract-complete pending a minor dependency," but genuinely non-functional against the executed schema today.** None of the three should be wired into a router that returns anything other than a deliberate "not yet available" response (or simply not routed at all) until their respective `DEP-6F-*` items are resolved. Shipping them as live routes today would either fail at the DB layer with an ungraceful error (reprocess, delete) or silently do nothing useful while claiming to (reindex, if the withdrawn narrow behavior were reinstated) — both outcomes this pass exists to prevent.

---

## 43. Final Closure / Freeze Recommendation

### 43.1 Closure Table

| # | Item | Status |
|---|---|---|
| 1 | All FR-RAG requirements traced | ✅ traced; ⚠️ FR-RAG-002 and FR-RAG-004 marked partial with named blockers (§38) |
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
| 12 | Duplicate-content behavior matches DB constraint | ❌ **FAILS** — §11.4/§40-C: the executed constraint does not match 4E's stated invariant; `DEP-6F-14` BLOCKING |
| 13 | Publication uses the frozen DB guard function | ✅ core function §12.2; ⚠️ guard gap disclosed, `DEP-6F-16` |
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
| 25 | Reindex behavior matches physical model | ❌ **FAILS as an implemented capability** — §22: no reindex mechanism is implementable; withdrawn from V1 surface, `DEP-6F-02` BLOCKING |
| 26 | FR-RAG-004 contradiction fully reconciled or correctly marked blocking | ✅ correctly marked — §40-A, `DEP-6F-01` (marking it correctly does not resolve it; see status below) |
| 27 | Archive/delete/GDPR semantics reconciled | ❌ **FAILS execution** — §23.4: `DELETE` cannot execute its GDPR-erasure step, `DEP-6F-15` BLOCKING |
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
| 43 | OpenAPI implementation readiness complete | ❌ **FAILS as "complete"** — §42: 18/21 ready, 3 genuinely blocked (not merely "contract-complete") |
| 44 | No Phase 5 modification required unless a genuine blocker proves otherwise | ⚠️ **Six** genuine blockers found this pass (`DEP-6F-01`, `02`, `09`, `14`, `15`, `16`) — up from three in the prior revision — all disclosed, none silently worked around, none require this document to modify Phase 5 itself |
| 45 | 6A–6E untouched | ✅ — verified no edits made to any file outside this document |
| 46 | 6G+ not started | ✅ |

**Four items fail outright this pass (12, 25, 27, 43); one additional item (44) reports a materially larger blocker count than the prior revision disclosed.**

### 43.2 Status

**PHASE 6F — REVISION REQUIRED**

Six BLOCKING dependencies exist (`DEP-6F-01`, `DEP-6F-02`, `DEP-6F-09`, `DEP-6F-14`, `DEP-6F-15`, `DEP-6F-16`, §39.1). Per the governing correction-pass instruction, a phase with open BLOCKING dependencies cannot be marked APPROVED/FROZEN CANDIDATE regardless of how narrowly each is scoped, and regardless of what fraction of the endpoint surface is otherwise usable. 18 of 21 endpoints are implementation-ready (§33.1) — this is a real, positive outcome of this pass's corrections, and is not diminished by the status above — but it does not by itself satisfy the freeze gate, because:

- Three endpoints (`reindex`, `reprocess`, `DELETE` document) are not merely incomplete but **non-functional** against the executed schema.
- One frozen SRS requirement (FR-RAG-004) has a named, unresolved BLOCKING gap that this document cannot close on its own authority.
- One 4E domain policy (`NoDuplicateDocumentContent`) is not enforced by the executed schema at the scope it was specified for.
- One `SECURITY DEFINER` function (`fn_docver_publish()`) has a disclosed integrity gap.

**This document does not authorize the Phase 5 or Phase 5J changes that would close these six items** (§44 names them explicitly, scoped to a separate controlled reconciliation step). Once that reconciliation resolves all six BLOCKING items — or product/architecture governance formally accepts an alternative interpretation for `DEP-6F-01` specifically — this document is structurally ready for a subsequent pass to re-evaluate freeze eligibility. It is not there yet.

---

## 44. Controlled Reconciliation Required

**6F itself does NOT authorize any of the changes listed below.** This section exists to hand a precise, scoped work list to whatever separate, explicitly-approved reconciliation step follows this document — no executable SQL, no migration numbers, no Alembic revisions are proposed here, per this pass's explicit instruction.

### 44.1 Phase 5F Controlled Reconciliation Candidates

| # | Item | Source finding |
|---|---|---|
| 1 | Knowledge-base-wide duplicate-content enforcement mismatch (`uq_dv_content_hash` executed as `(document_id, content_hash)` vs. 4E's KB-wide `NoDuplicateDocumentContent` policy) | `DEP-6F-14`, §5 F-7, §40-C |
| 2 | Durable `DocumentVersion` `FAILED` transition — no `SECURITY DEFINER` path exists today | `DEP-6F-09`, §5 F-3, §14, §15 |
| 3 | GDPR `DocumentVersion` erase transition — no `SECURITY DEFINER` path exists today (the design document's own §19 already carried this forward as unresolved) | `DEP-6F-15`, §5 F-4, §23.4 |
| 4 | `fn_docver_publish()` guard against publishing onto a `DELETED` document | `DEP-6F-16`, §5 F-8, §12.2, §28 race 9 |
| 5 | True reindex / index-generation physical mechanism, if the architecture retains this capability at all | `DEP-6F-02`, §22, §40-E |
| 6 | Rollback/publication lifecycle support, if chosen by governance as FR-RAG-004's resolution path (see §44.3 — this is conditional on a product decision, not automatically in scope) | `DEP-6F-01`, §12.4, §40-A |

### 44.2 Phase 5J Controlled Governance Candidate

| # | Item | Source finding |
|---|---|---|
| 1 | Seven Knowledge/RAG `action_kind` values requiring documented governance sanction (`KNOWLEDGE_BASE_UPDATED`, `KNOWLEDGE_BASE_ARCHIVED`, `KNOWLEDGE_BASE_REINDEX_TRIGGERED`, `DOCUMENT_UPLOADED`, `DOCUMENT_ARCHIVED`, `DOCUMENT_REPROCESS_REQUESTED`, `DOCUMENT_VERSION_PUBLISHED`) | `DEP-6F-03`, §30.2 |

### 44.3 Product / Architecture Reconciliation

| # | Item | Source finding |
|---|---|---|
| 1 | The exact accepted interpretation of FR-RAG-004 ("knowledge base versioning and allow rollback") — either (A) formally ratify forward-only version publication as the satisfying interpretation, closing the gap without a schema change, or (B) direct that a physical rollback mechanism be added under §44.1 item 6 | `DEP-6F-01`, §12.4, §40-A |

### 44.4 What This Section Is Not

This is a work list for a separate, future, explicitly-approved reconciliation pass — it is not a request this document is making of itself, and completing it is **not** something 6F can do by editing its own prose further. No item above is resolved, partially resolved, or worked around anywhere else in this document.

---

