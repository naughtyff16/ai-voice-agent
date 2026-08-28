## AI Voice Agent Platform — Phase 6 — API Design — Phase 6D

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6D — Voice, Calls, Conversations & AI Agent APIs |
| Phase | 6 — API Design |
| Status | **APPROVED/FROZEN** (see §40) — reached via an initial draft, a focused correction pass, an audit-mechanism closure pass, and this final editorial closure |
| Author | karthi (karthimadan2003@gmail.com) |
| Date | 2026-08-23 |
| Depends on (frozen) | Phase 1 SRS; Phase 2 HLA; Phase 3A/3B/3E LLD; Phase 4A/4B/4G/4H/4I DDD; Phase 5A/5B/5C DB Design (unmodified); Phase 5J DB Design (unmodified except the two authorized amendments named under Modifies); Phase 5K migrations 001–077 (unmodified); Phase 6A, 6B, 6C (unmodified) |
| Modifies | Phase 5J only, through two explicitly authorized, documentation-only governance amendments: (1) §14.3 — Voice audit `action_kind` vocabulary extension; (2) §14.5 — Voice synchronous-audit exception (`audit.fn_insert_audit_event(...)`). No Phase 5 schema, SQL migration, function, constraint, RLS policy, grant, index, Alembic revision, or other Phase 5 implementation artifact is modified. Nothing else upstream is touched. |
| Hard boundary | This document designs **only** the API-facing surface of the frozen Voice & AI bounded contexts (4B): AI Agent configuration/versioning, Call lifecycle and control, Conversation/Turn observation, Recordings, Transcripts, Tool Definitions/Executions (observation), Provider routing (read-only boundary), Tenant Phone Numbers (thin surface), Language Evaluation Records (read-only), and the realtime `/ws/v1/voice/...` contract. It does not design Knowledge/RAG, Workflow, Prompt Management, Conversation Memory, CRM, Campaign, Billing, Integrations, or Analytics APIs — those are consumed by reference only, per their existing 4B ports/events, and remain 6E–6M territory. It does not modify any Phase 5 schema or implementation artifact — the only Phase 5 changes are the two explicitly authorized, documentation-only 5J governance amendments (§14.3, §14.5) described above under Modifies. It does not modify 6A (frozen), 6B (frozen), or 6C (frozen). It does not begin 6E or any later API-design document. |

---

## 2. Purpose

Phase 6C closed Core Platform (Organizations, Memberships, Teams, Compliance Policy configuration, Data Subject Requests, User Profile) and left an explicit, named gap: *"Voice/AI Agent/Knowledge/CRM/Campaign/Workflow/Integrations/Billing/Analytics/Admin — DEFERRED — 6D–6M"* (6C §6 Resource Ownership Matrix, row 107). This document is the first bounded-context API design to fill that gap, taking the first-listed, foundationally-required context: **Voice & AI** (4B).

The platform's core product promise (`product/PRODUCT_VISION.md`) is a natural, real-time AI voice agent that a caller cannot easily distinguish from a well-trained human agent within India-first market conditions (Tamil/English code-switching, PSTN telephony via Exotel-class providers). That promise lives or dies on one number: how long the caller waits, in silence, between finishing a sentence and hearing the agent's reply. This document's central engineering commitment is therefore not merely "design CRUD endpoints for Voice resources" but to **make a ≤750ms p50 caller-perceived turn-latency target architecturally plausible** in the API/realtime contract itself — every design choice in §8–§20 is evaluated against whether it protects or threatens that number, and §21 makes the reasoning explicit and auditable.

Secondary purposes, in the same order 6B/6C established: (a) give the Agent aggregate (4B §5.3) a complete, immutable-version-respecting API contract; (b) give the Call aggregate (4B §5.1) a REST contract that never blocks a request on an external telephony provider's full call-establishment sequence; (c) fully specify, for the first time on this platform, the generic realtime WebSocket contract 6A §27 promised but explicitly declined to instantiate ("no domain-specific event catalog is defined here... this is the envelope shape every future event type must use," 6A §27.3); (d) make barge-in and TTS cancellation — FR-VOICE-007 — a first-class, API-visible runtime contract, not an implementation detail; (e) honestly reconcile every genuine gap between the frozen DDD/DB layer and what a rigorous API design requires, rather than silently inventing permissions, audit vocabulary, or DB guard mechanisms that do not exist.

---

## 3. Scope / Hard Boundary

### 3.1 In Scope

- AI Agent CRUD, draft-config editing, publish/deprecate/clone lifecycle, AgentVersion read access.
- Call initiation (outbound), inbound call boundary classification, call lifecycle observation, call control actions (terminate, transfer, hold, resume).
- Conversation and Turn read/observation contracts (no tenant-facing create/update — these are internal-runtime-written).
- Recording metadata, signed-URL access, deletion.
- Transcript metadata and finalized-segment pagination.
- Tool Definition CRUD (tenant custom tools) and Tool Execution observation (read-only).
- Provider health/routing **read-only** boundary (no tenant provider-credential CRUD designed here — see §19, DEP-6D-06).
- Tenant Phone Number **read + agent-assignment** thin surface (no provisioning/purchase flow — see §19, DEP-6D-07).
- Language Evaluation Records read-only reference surface.
- The realtime `/ws/v1/voice/...` contract: connection lifecycle, envelope, message catalog, barge-in/TTS-cancellation semantics, reconnect/backpressure rules.
- The provider inbound callback boundary classification (not a redesign of 6A §28.2/5I's generic inbound-webhook mechanism — a statement of how Voice's telephony callbacks fit inside it).

### 3.2 Explicitly Out of Scope (named, not silently absorbed)

| Context | Why excluded | Where it belongs |
|---|---|---|
| Knowledge Base / RAG (`KnowledgeSearchPort`) | 4B consumes it via a port; 6D does not design KB ingestion/search endpoints | 6E+ |
| Workflow Engine (`WorkflowExecutionPort`) | 4B consumes it per-turn via a port; 6D does not design workflow graph/node endpoints | 6E+ |
| Prompt Management (`PromptRenderPort`) | 4B consumes it via a port; 6D does not design prompt CRUD/versioning endpoints | 6E+ |
| Conversation Memory (`ConversationMemoryPort`) | 4B consumes it via a port; 6D does not design memory storage endpoints | 6E+ |
| CRM (Contact, lead qualification write-back) | Voice publishes domain events CRM consumes; 6D does not design CRM endpoints | 6E+ |
| Campaign Engine | Voice publishes `call.ended`/`call.failed`; Campaign triggers outbound calls via an in-process module call (4B §18.2), not a 6D-owned HTTP endpoint | 6E+ |
| Billing / Usage metering | Voice publishes `call.answered`/`call.ended`; 6D does not design usage/invoice endpoints | 6E+ |
| Analytics | Voice publishes turn/call events consumed into projections; 6D does not design analytics query endpoints | 6E+ |
| Compliance Policy CRUD | Owned by 6C (§12); 6D **consumes** the active policy read-only (§20) | 6C (frozen) |
| Integrations / generic inbound-webhook table | Owned by 5I/6A §28; 6D states how Voice's provider callbacks fit inside it, does not redesign it | 6A/6C+ |

Per the governing instruction, this document does not absorb any of the above merely because Voice consumes them.

---

## 4. Governing Documents

**Product/Requirements:** `product/PRODUCT_VISION.md`, `product/ARCHITECTURE_PRINCIPLES.md`, `product/TECH_STACK.md`, `product/PROJECT_ROADMAP.md`, `phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` (FR-VOICE-001–007, NFR-PERF-001, NFR-OBS-002, NFR-AVAIL-001, NFR-SEC-*).

**Architecture:** `phase-02-high-level-architecture/HIGH_LEVEL_ARCHITECTURE.md`.

**LLD:** `3A-Platform-Architecture.md`, `3B-Voice-Platform.md` (primary), `3E-Platform-Services.md`; `3D-Workflow-RAG.md` consulted only where Voice references Workflow/RAG ports (not redesigned here).

**DDD:** `4A-Core-Domains.md`, `4B-Voice-AI-Domain.md` (primary), `4G-Analytics-Cross-Domain-Context-Map.md`, `4H-Final-Architecture-Review.md`, `4I-India-First-Decision-Closure.md`.

**Database:** `5A-Database-Architecture-and-Standards.md`, `5B-Identity-Organization-Multitenancy-Security.md` (permission catalog), `5C-Voice-Schema.md` (primary — all 13 tables), `5F`/`5G`/`5H` consulted only for cross-references, `5J-Analytics-Audit-Schema.md` (audit vocabulary, outbox), `5K/EXECUTION_REPORT.md`, `5K/MIGRATION_MANIFEST.md`, migrations `009`–`018` (5C), `076_5K1.sql`, `077_5J1.sql`.

**Frozen Phase 6:** `6A-API-Architecture-and-Standards.md` (binding cross-cutting standards), `6B-Authentication-and-Authorization-API.md` (JWT/API-key/internal-token mechanisms consumed as-is), `6C-Core-Platform-APIs.md` (Compliance Policy contract consumed as-is; resource-ownership-matrix and dependency-register conventions reused).

All are treated as authoritative and unmodified by this document.

---

## 5. Source Reconciliation

Verified before writing a single endpoint, per the governing task's explicit instruction to check for conflicts rather than invent a third interpretation:

| # | Question | Finding | Resolution |
|---|---|---|---|
| 1 | Does any repository artifact already name/scope "Phase 6D"? | No. Searched `PROJECT_ROADMAP.md` (numbers phases 1–24 only, no A–M sub-lettering), all of `docs/phase-06-api-design/`, and every `docs/phase-05-database-design/**` file. Only 6C §6 row 107 references "6D–6M" as an unscoped placeholder range for nine deferred contexts. | Used the governing task's fallback title verbatim: **"6D — Voice, Calls, Conversations & AI Agent APIs."** Not invented — explicitly authorized as the fallback when no repository artifact defines 6D's title. |
| 2 | Does 6A's Tier E latency reference (~725ms) conflict with a stricter 6D target? | No — 6A §11 states 725ms p50 (no-tool) as the *reference design budget* reproduced from 3B §21, itself flagged "proposed, not previously approved." 6A does not claim this is measured, and does not forbid a stricter downstream engineering target. | 6D adopts ≤750ms p50 as a **stricter engineering target** layered on top of the existing 725ms reference budget and the frozen NFR-PERF-001 <800ms ceiling — no contradiction, no 6A edit. Full treatment in §21. |
| 3 | Does 4B's Call/Conversation/Agent state-machine design match 5C's implemented CHECK-constraint enums exactly? | Yes, verified column-by-column: 5C §8's `CHECK (status IN (...))` lists for `call_sessions`, `conversations`, `agents`, `tool_executions`, `recordings`, `transcripts` match 4B §6/§7's Value Object enumerations exactly, including `ABANDONED` and `TRANSFERRED` as terminal Call states. | No conflict. Used verbatim in §11's state-machine tables. |
| 4 | Does 5C provide `SECURITY DEFINER` guarded state-transition functions for Call/Agent/Conversation status, the way 5E/5I do for `webhook_deliveries`/`call_jobs`? | **No.** Grepped every `CREATE OR REPLACE FUNCTION voice.*` in 5C: only `prevent_agent_version_mutation()`, `prevent_tool_exec_arguments_mutation()` (immutability triggers), and `resolve_inbound_phone_number()` exist. No `fn_claim_*`/`fn_transition_*` function exists for `call_sessions.status`, `agents.status`, or `conversations.status`. | This is a real, disclosed gap (not a conflict to silently paper over). 6A §17.2 already anticipates this case ("via the guarded SECURITY DEFINER function **where one exists**") and 6C's own ADR-6C-02 already established the fallback: an API-layer atomic conditional `UPDATE ... WHERE status = ANY(allowed) RETURNING id` (CAS), no bespoke DB function invented, no `SELECT ... FOR UPDATE`. 6D reuses this exact mechanism (§11, §30, ADR-6D-03) rather than inventing a third pattern. |
| 5 | Does 4B's Recording aggregate's `RecordingPolicy` source (`OrgSettings`) match 4I's later correction (`CompliancePolicy.RecordingPolicy`)? | 4I §27.4 (CONTRADICTION-04) already found and resolved this: `CompliancePolicy.RecordingPolicy` (6C-owned) is authoritative; `Recording.RecordingPolicy` (5C `recordings.recording_policy`) is a **snapshot copied at recording creation time**, immutable thereafter — the same pattern as `RetentionPolicy`. | Later-approved artifact (4I) already reconciled this before 5C was written; 5C's column comment matches 4I's resolution exactly. No new reconciliation needed — restated in §20. |
| 6 | Does the frozen audit `action_kind` vocabulary (5J §14.3) cover Voice-domain mutations? | At the time of 6D's first draft: only `AGENT_PUBLISHED`/`AGENT_DEPRECATED` existed. No `CALL_*`, no `AGENT_CREATED`/`AGENT_CONFIG_UPDATED`, no `TOOL_DEFINITION_*`, no `RECORDING_DELETED`, no phone-number action kind existed anywhere in 5J's governed list (including the ten values added by the 6C-driven `077_5J1` governance amendment) — 13 of 6D's 15 state-changing endpoints had no exact-match value. | **This finding is now RESOLVED.** This correction pass is explicitly authorized to perform the same class of controlled, documentation-only 5J §14.3 governance amendment that resolved 6C's structurally identical gap. Twelve new governed values (`AGENT_CREATED`, `AGENT_CONFIG_UPDATED`, `CALL_INITIATED`, `CALL_TERMINATED`, `CALL_TRANSFERRED`, `CALL_HELD`, `CALL_RESUMED`, `TOOL_DEFINITION_CREATED`, `TOOL_DEFINITION_UPDATED`, `TOOL_DEFINITION_DEACTIVATED`, `RECORDING_DELETED`, `PHONE_NUMBER_AGENT_ASSIGNED`) were added to 5J §14.3, marked `‡`, with no SQL migration (`chk_ae_action_kind` remains the same length check it always was). Former **DEP-6D-04** is now **RESOLVED** — see §36, §40. |
| 7 | Does the frozen 5B permission catalog cover every action 6D needs to gate? | Partially. `agent:read/write/publish/delete`, `call:read/initiate/transfer/record`, `recording:read/delete`, `transcript:read` all exist and fit. No `call:terminate/hold/resume`, no `tool:*`, no `phone_number:*` permission exists anywhere in 5B. | Three narrow, documented interim-mapping dependencies (DEP-6D-01/02/03, §25/§36) — following exactly the precedent 6C's ADR-6C-04/DEP-6C-03/DEP-6C-09 set: reuse the nearest existing, correctly-scoped permission, disclose the gap, do not invent a string. **Re-verified this pass against 5B's actual canonical role-permission grant table (5B, System Permissions/Role Assignments block):** DEP-6D-01 and the tool-CRUD half of DEP-6D-02 checked out as conservative (identical actor sets to an already-adjacent permission); the phone-number-assignment half of DEP-6D-03 did **not** — `agent:write` (OWNER/ADMIN/MEMBER) over-granted MEMBER a live-inbound-call-routing change with no version-pinning safety net, so it was retargeted to `agent:publish` (OWNER/ADMIN only), a better-fitting existing permission — no new 5B permission was required (§25, ADR-6D-08). |

---

## 6. Resource Ownership Matrix

Extends 6C §6's matrix with the Voice/AI candidate resources 4B §5 + 5C §3 define, evaluated against the governing task's classification scheme.

| # | Resource (4B aggregate / 5C table) | Classification | Rationale |
|---|---|---|---|
| 1 | AI Agent (`voice.agents`) | **OWNED BY 6D** | 4B §5.3 AggregateRoot; the platform's primary Voice configuration surface |
| 2 | Agent Version (`voice.agent_versions`) | **OWNED BY 6D (read-only after creation)** | Created only as a side effect of the `publish` action endpoint (§9); never directly mutable — DDR-4B-003 |
| 3 | Published-version resolution for call start | **INTERNAL ONLY** | `CallRoutingService.resolve()` (4B §8.1) runs in-process inside the same modular-monolith deployable that owns the DB connection (3A/3B) — never a public or internal HTTP hop |
| 4 | Call / Call Session (`voice.call_sessions`) | **OWNED BY 6D** | 4B §5.1 AggregateRoot |
| 5 | Conversation (`voice.conversations`) | **OWNED BY 6D — read-only surface** | 4B §5.2 AggregateRoot; created internally by `StartConversation` on call answer (§10), never via a tenant-facing POST |
| 6 | Turn (`voice.turns`) | **READ-ONLY PROJECTION** | Entity embedded in Conversation per DDD, materialized as its own checkpoint table (5C §5.3); no create/update API — internal-runtime-written only |
| 7 | Recording (`voice.recordings`) | **OWNED BY 6D** | 4B §5.6 AggregateRoot; metadata + signed-URL + delete only, never raw bytes (6A §29) |
| 8 | Transcript (`voice.transcripts`) + Transcript Segment (`voice.transcript_segments`) | **OWNED BY 6D — read-only surface** | 4B §5.7 AggregateRoot; strictly finalized-segment read access, no write API (5C §11.4 — append-only, internal-runtime-written) |
| 9 | Tool Definition (`voice.tool_definitions`) | **OWNED BY 6D** | 4B §5.4 AggregateRoot; tenant custom tools are CRUD-able, platform built-ins are read-only |
| 10 | Tool Execution (`voice.tool_executions`) | **READ-ONLY PROJECTION** | 4B §5.5 AggregateRoot with its own lifecycle, but created/mutated only by the in-process turn loop (4B §18.3) — never a tenant-invoked create; exposed for observability only |
| 11 | Provider Configuration (`voice.provider_configs`) | **READ-ONLY PROJECTION** (health/routing fields only) + **DEFERRED** (tenant credential/priority CRUD) | 4B §5.8 AggregateRoot, mixed-scope; no `provider:*` permission exists and no product requirement for tenant self-service provider override surfaced in Phase 1–5 — DEP-6D-06 |
| 12 | Tenant Phone Number (`voice.tenant_phone_numbers`) | **OWNED BY 6D — thin surface (read + agent-assignment)** + **DEFERRED** (provisioning/purchase) | `TelephonyPort` (4B §16) has no `provision_number()` method — number acquisition from a carrier is not a designed capability anywhere in Phase 1–5 — DEP-6D-07 |
| 13 | Language Evaluation Record (`voice.language_evaluation_records`) | **OWNED BY 6D — read-only** | Platform-scoped reference data (5C §5.12, no RLS); write path is `app_platform_admin`-only, not a tenant API |
| 14 | Realtime call session/control surface | **OWNED BY 6D** | The `/ws/v1/voice/...` contract this document formalizes (§13) |
| 15 | Compliance Policy | **NOT OWNED — consumed read-only** | 6C §12 owns CRUD; 6D reads the active policy via 6C's existing internal endpoint (§20) |
| 16 | Knowledge/RAG, Workflow, Prompt, Memory, CRM, Campaign, Billing, Analytics, Admin | **NOT EXPOSED / DEFERRED** | Per §3.2 — explicitly not absorbed |

---

## 7. Voice/API Architecture Overview

### 7.1 Two Physically Distinct Surfaces, One Codebase

3A/3B already establish (and 6A §27.1 ratifies) that Voice runs as two cooperating pieces of one modular monolith, not two independently-designed systems:

```
┌─────────────────────────────┐        ┌──────────────────────────────────┐
│   Core API (tenant REST)     │        │   Voice Gateway (realtime)        │
│   /api/v1/agents             │        │   /ws/v1/voice/media/{session}    │
│   /api/v1/calls              │        │     (provider media, raw frames,  │
│   /api/v1/conversations      │        │      reused from 3B unmodified)   │
│   /api/v1/recordings         │        │   /ws/v1/voice/calls/{call_id}    │
│   /api/v1/transcripts        │        │     (tenant observation channel,  │
│   /api/v1/tools              │        │      NEW — this document, §13)    │
│   /api/v1/provider-health    │        │   Voice Orchestrator (in-process, │
│   /api/v1/phone-numbers      │        │     asyncio, STT→LLM→TTS pipeline,│
│   /api/v1/language-evals     │        │     3B §9–§13 — NOT an API,       │
│   /api/internal/v1/...       │        │     not redesigned here)          │
└──────────────┬────────────────┘        └────────────────┬─────────────────┘
               │                                            │
               └───────────────── shared PostgreSQL + Redis ┘
                     (voice.* schema, 5C — both surfaces read/write
                      it via the same repository classes; no HTTP
                      hop between Core API and Voice Gateway for
                      DB access — 3A's "no direct module-to-module
                      imports" rule governs Python imports, not a
                      network boundary that doesn't exist here)
```

This matters for API design in one concrete way: **the tenant-facing REST surface this document specifies is never on the voice-turn hot path.** A human operator calling `GET /api/v1/calls/{id}` mid-call and the Voice Orchestrator's internal STT→LLM→TTS loop touch the same rows, but never the same request/response cycle. §21/§22 make this isolation explicit.

### 7.2 What 6D Adds to 6A's Foundation

Every cross-cutting rule below is 6A's, reused verbatim, not restated in full: request/response envelope (6A §10), error contract (6A §24), pagination/filtering (6A §14–15), idempotency (6A §16), concurrency/CAS (6A §17), async job architecture (6A §18, not used by 6D — no Voice resource needs Tier D), rate limiting (6A §20), timeouts/retries/circuit breakers (6A §21), security architecture (6A §22), multi-tenant context (6A §23), WebSocket transport decision (6A §27.1 — raw WebSocket, `/ws/v1/...`, no Socket.IO), webhook mechanism split (6A §28), file/media pattern (6A §29), transaction-boundary exceptions (6A §35).

6D's job is to instantiate these standards for Voice's specific aggregates and to close the two genuine gaps 6A left explicitly for a later document to resolve: (1) the realtime **event catalog** for a domain-specific channel (6A §27.3 declined to define one), and (2) the **latency-architecture reconciliation** between the frozen 725ms reference budget and a stricter, binding 6D engineering target (§21).

### 7.3 Latency Classes Used By 6D Endpoints (6A §11, unmodified)

| 6D endpoint class | 6A Tier | Example |
|---|---|---|
| Agent/Tool CRUD, reads | Tier A — Interactive | `GET /agents/{id}`, `GET /tools` |
| Call/Conversation/Recording/Transcript reads | Tier A — Interactive | `GET /calls/{id}`, `GET /conversations/{id}/turns` |
| Call control actions | Tier B — Operational | `POST /calls/{id}/terminate` — durably recorded, does not block on telephony provider confirmation |
| Call initiation | Tier B — Operational | `POST /calls` — durably recorded, does not block on the callee answering |
| Agent publish | Tier B — Operational | `POST /agents/{id}/publish` — short same-transaction write, no external call |
| Voice-turn realtime loop | Tier E — Realtime | **Not a REST tier at all** — the `/ws/v1/voice/media/*` provider audio path (3B, unmodified) and the ≤750ms turn target (§21) apply here, never to the REST tiers above |
| Realtime observation channel (`/ws/v1/voice/calls/*`) | Non-voice realtime (6A §11) | p95 <500ms server-emit-to-client-receive — "feels live," not a human-turn-taking constraint |

---

## 8. Agent API Design

### 8.1 Grounding

`Agent` — AggregateRoot, 4B §5.3; table `voice.agents` + `voice.agent_versions`, 5C §5.4–5.5. An Agent has a mutable `DraftConfig` (editable at will) and a list of immutable, versioned snapshots created only by `publish()`. `status ∈ {DRAFT, PUBLISHED, DEPRECATED}` (4B §7.3).

### 8.2 Editable Draft-Config Fields (typed allow-list, per 6A/6C convention — never a generic JSON bag at the API boundary)

Matches 5C §5.4's documented `draft_config` JSONB structure exactly — every field below is individually typed and validated in the request schema, even though it is stored as one JSONB column:

| Field | Type | Validation |
|---|---|---|
| `name` | string | 2–100 chars (5C `CHECK (length(name) BETWEEN 2 AND 100)`) |
| `description` | string, nullable | 0–500 chars |
| `voice_config.voice_id` | string | provider-agnostic voice identifier |
| `voice_config.language` | string | BCP 47, validated against the platform's supported-language whitelist (4B §5.3.1, includes `ta`/`ta-IN`) |
| `voice_config.speaking_rate` | number | 0.5–2.0 |
| `voice_config.emotion` | enum | `NEUTRAL \| FRIENDLY \| PROFESSIONAL \| EMPATHETIC` |
| `voice_config.barge_in_sensitivity` | enum | `LOW \| MEDIUM \| HIGH` |
| `voice_config.tamil_code_switching` | boolean | — |
| `model_config.preferred_provider` | string, nullable | must reference an active `provider_configs` row (category=LLM) if set |
| `model_config.fallback_providers` | string[] | ordered; each validated the same way |
| `model_config.latency_bias` / `cost_bias` | number | 0.0–1.0 |
| `model_config.max_tokens_per_turn` | integer, nullable | — |
| `language_policy.*` | object | `primary_language`, `fallback_language`, `allowed_languages[]`, `code_switching_enabled`, `language_detection_mode`, `pronunciation_lexicon_ref`, `script_preference` — per 5C §5.4's exact structure |
| `prompt_ref` | UUID, nullable | opaque reference to Prompt Management (6E+); 6D validates format only, never resolves it |
| `workflow_ref` | UUID, nullable | opaque reference to Workflow Engine (6E+); format-validated only |
| `knowledge_base_refs` | UUID[], nullable | opaque references to Knowledge Base (6E+); format-validated only |
| `tool_permissions` | array of `{tool_id, tool_name}` | each `tool_id` must resolve to an active `voice.tool_definitions` row visible to the tenant (built-in or own) — **the one field 6D validates against its own data**, per 4B §5.3 invariant 4 |
| `qualification_criteria` | object, nullable | structured; no fixed schema imposed beyond JSON-Schema-shaped object (4B leaves this open) |
| `calling_hours` | object, nullable | `TimeWindow` structure |

**Why opaque-reference fields are format-validated only, not resolved:** `prompt_ref`, `workflow_ref`, `knowledge_base_refs` point into bounded contexts 6D does not own (§3.2). Resolving them would require 6D to either import those modules directly (violating 3A's module-boundary rule) or make a synchronous cross-context call on a config-edit path that has no latency requirement justifying the coupling. They are stored, round-tripped, and validated for well-formedness (valid UUID) only; existence/authorization checks belong to whichever future document owns those contexts, exercised at **call-start time** by the in-process ports (4B §16), not at draft-edit time.

### 8.3 Endpoints (full contracts in §28)

| Endpoint | Purpose |
|---|---|
| `POST /api/v1/agents` | Create a new Agent in `DRAFT` |
| `GET /api/v1/agents` | List agents (paginated, filterable by `status`) |
| `GET /api/v1/agents/{agent_id}` | Get one agent (draft config + status + published version pointer) |
| `PATCH /api/v1/agents/{agent_id}` | Update draft-config fields (§8.2 allow-list) |
| `POST /api/v1/agents/{agent_id}/publish` | Action endpoint — snapshot `DraftConfig` into a new immutable `AgentVersion` (§9) |
| `POST /api/v1/agents/{agent_id}/deprecate` | Action endpoint — `PUBLISHED → DEPRECATED` |
| `POST /api/v1/agents/{agent_id}/clone` | Create a new `DRAFT` Agent whose `draft_config` is copied from this agent's current draft (or published version, if specified) |

### 8.4 What Is Never Exposed

- Direct mutation of `voice.agent_versions.snapshot_json` — enforced twice over: the API never routes a write to it outside `publish`, and 5C §11.6's `BEFORE UPDATE` trigger rejects any attempted change at the DB layer regardless.
- A generic `PATCH /agents/{id}` that accepts a `status` field — `status` transitions only via `publish`/`deprecate` action endpoints (6A §8.3, §17.2 — guarded transitions never ride a free-form PATCH).
- Cross-tenant agent references — `tool_permissions[].tool_id` validation is tenant-scoped (own tools + platform built-ins only); an agent can never reference another tenant's custom tool.

---

## 9. Agent Versioning / Publishing

### 9.1 The Immutability Contract (DDR-4B-003, restated as a binding API contract)

```
Agent.draft_config (mutable, edited freely via PATCH)
        │
        │  POST /agents/{id}/publish
        ▼
AgentVersion.snapshot_json (immutable JSONB, written once, DB-trigger-enforced)
        │
        │  read once, at call-start time, by CallRoutingService (in-process)
        ▼
Call.agent_version_id (pinned for the entire lifetime of that Call — 4B §5.1 invariant 1)
```

**The guarantee this document exists to make explicit at the API level:** publishing Agent version N+1 while 200 calls are pinned to version N has **zero effect** on those 200 calls. No 6D endpoint — publish, deprecate, or draft-config PATCH — ever reaches into an in-progress Call's pinned configuration. This is enforced structurally (the Call aggregate stores its own `agent_version_id` at creation, 5C §5.1, and nothing in 6D's endpoint set writes to `call_sessions.agent_version_id` after creation) rather than by a runtime check that could be bypassed by a future bug.

### 9.2 Publish Mechanics

`POST /agents/{id}/publish` is one of 6A §35's **named approved exceptions** for same-transaction, cross-aggregate atomicity: *"Publish Agent + AgentVersion"* — reused exactly, not re-derived. Within one DB transaction:

1. Guard: `agents.status` must be `DRAFT` or `PUBLISHED` (re-publishing a currently-published agent with new draft edits is the normal "ship an update" flow) — `DEPRECATED` is terminal for publish (4B §7.3: "An Agent in DEPRECATED status cannot be published again").
2. **Re-validate every `tool_permissions[].tool_id` in the current draft** against `voice.tool_definitions` — each must still resolve to a row visible to the tenant (built-in or own) **and** `is_active = TRUE` → `422 VALIDATION_ERROR` naming the offending `tool_id` if not (full contract in §28.5).
3. `INSERT INTO voice.agent_versions (agent_id, version_number, snapshot_json, language_policy, published_by, published_at)` — `version_number = MAX(version_number) + 1` for this agent (or 1 for the first publish), enforced by `uq_av_version` (5C §7) — see §9.2a for the bounded-retry handling of a concurrent-publish unique-violation.
4. `UPDATE voice.agents SET status='PUBLISHED', published_version_id = <new version id>`.
5. `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_PUBLISHED', ...)` — the durable audit record (§24.0), synchronous, same transaction. **Never a direct `INSERT INTO audit.audit_events`** — no application role holds that privilege (5J §5/§14.2, `REVOKE ALL`); `fn_insert_audit_event()` is the sole legal write path.
6. `INSERT INTO audit.domain_event_outbox (event_type='agent.published', ...)` — same transaction (§24), a **separate** write from step 5, for cross-context propagation.

**Why draft-time validation alone is insufficient — corrected this pass:** an earlier draft of this document claimed "no tool-existence re-validation happens at publish time... since the draft can never have entered an invalid state in the first place." That claim was wrong and has been removed. §8.2's draft-edit-time check only proves a `tool_id` was valid **at the moment the draft was last edited** — it says nothing about whether that tool is *still* valid at the later moment of publish:

```
draft edited, tool_permissions=[toolX], toolX.is_active=TRUE   — valid at T1
        ↓
toolX deactivated via POST /tools/{toolX}/deactivate            — at T2 (§18.1)
        ↓
POST /agents/{id}/publish, no further draft edit in between     — at T3
```

At T3, the draft's `tool_permissions` still literally contains `toolX`'s ID, but the referenced tool is no longer active. Publishing without re-checking would snapshot a dangling/inactive reference into an otherwise-immutable `AgentVersion` (5C §11.6) — a mistake that could never afterward be corrected for that version. Step 2 above closes this gap by treating publish as the point where the *entire* draft's tool references are proven valid as of the moment they become permanently frozen, not merely as of whenever each field was last touched.

### 9.2a Concurrent Publish — `23505`, Not a Serialization Failure (corrected this pass)

**An earlier draft of this document incorrectly described a `uq_av_version` collision as a Postgres "serialization failure."** Under this endpoint's actual isolation level (READ COMMITTED, the platform default, no `SERIALIZABLE` isolation is used anywhere in this design), two concurrent publishes on the same Agent do **not** produce SQLSTATE `40001` (`serialization_failure`) — that error class only arises under `REPEATABLE READ`/`SERIALIZABLE` isolation. What actually happens under READ COMMITTED:

```
Transaction A: reads MAX(version_number)=7 → attempts INSERT version_number=8
Transaction B: reads MAX(version_number)=7 → attempts INSERT version_number=8
                                                      (concurrently, same agent_id)
```

Whichever `INSERT` commits first succeeds. The second `INSERT` raises **SQLSTATE `23505` (`unique_violation`)** against `uq_av_version` (5C §7) — not `40001`.

**Corrected bounded-retry algorithm (implementation rule, not a Phase 5 change):**

```
1. BEGIN transaction
2. compute next version_number = MAX(version_number) + 1 for this agent_id
3. attempt INSERT INTO voice.agent_versions (...)
4. IF the INSERT raises 23505 (unique_violation) on uq_av_version:
     ROLLBACK the transaction
     retry from step 1 with a freshly-computed MAX(version_number)
     (bounded: 3 attempts, matching this platform's general retry
      discipline for generated sequence-like values under contention —
      no existing generic 23505-retry helper is documented anywhere in
      Phase 1–6, so this is a 6D-local implementation rule, stated
      explicitly rather than assumed to exist elsewhere)
5. IF retries are exhausted (3 consecutive 23505s):
     surface 409 STATE_CONFLICT to the client, `error.details.reason:
     "concurrent_publish_contention"` — an honest signal to retry the
     whole publish request, not a 500
```

This is **not** a `SELECT ... FOR UPDATE` (6A §17.3 remains unviolated — no new API-layer locking scheme is introduced) and **not** a Phase 5 schema change (`uq_av_version` already does the only enforcement needed; the retry loop is purely an application-layer response to a constraint violation the database was always going to raise). §28.5's Concurrency bullet and §30.2's race table are corrected to match this exact mechanism.

### 9.3 Read Access

`GET /agents/{id}/versions` (list, newest first) and `GET /agents/{id}/versions/{version_id}` (one snapshot, including `language_policy` and `published_by`/`published_at`) are the only two version-read endpoints. There is no "diff between versions" or "rollback to version N" endpoint — 4B's domain model has no `RollbackAgent` command; a rollback is performed by a tenant editing the draft back to the desired shape and publishing again, which correctly creates a new version rather than resurrecting an old one (consistent with `agent_versions` being effectively append-only, 5C §5.5).

### 9.4 Deprecation and Archival

`POST /agents/{id}/deprecate`: guard `status = PUBLISHED` → `status = DEPRECATED`. Per 4B §7.3, `DEPRECATED` is terminal except for an eventual soft-delete (not designed here — no `DeleteAgent`/`ArchiveAgent` command exists in 4B §12.3's command catalogue, and no `deleted_at`-setting endpoint is invented; `voice.agents.deleted_at` exists in 5C §5.4 but no 4B command populates it, so 6D does not expose a delete/archive action beyond `deprecate` — a disclosed, non-blocking scope boundary, not a silent omission).

A `DEPRECATED` agent's already-published versions remain fully readable (audit/history), and any Call already pinned to one of its versions is entirely unaffected — deprecation only prevents **new** calls from resolving to this agent (`CallRoutingService.resolve()` excludes non-`PUBLISHED` agents, 4B §9 policy `AgentMustBePublished`).

---

## 10. Call API Design

### 10.1 Grounding

`Call` — AggregateRoot, 4B §5.1; table `voice.call_sessions`, 5C §5.1 (partitioned monthly on `started_at`). Direction `INBOUND | OUTBOUND`. 14-value state machine (§11).

### 10.2 The Client-Request-vs-Provider-Side-Effect Split (the central design decision of this section)

Per the governing task's explicit instruction and 6A §11 Tier B's own rule: `POST /api/v1/calls` **durably records and validates intent**, then returns — it never blocks on the telephony provider completing the actual call-establishment sequence (dialing, ringing, the callee picking up).

```
Tenant                Core API                         Voice module (in-process)        Telephony Provider
  │                       │                                      │                              │
  ├─ POST /calls ────────►│                                      │                              │
  │  {agent_id, to_number,│                                      │                              │
  │   phone_number_id}    │                                      │                              │
  │                       ├─ resolve phone_number_id → from_number (§10.2a, deterministic, server-side)
  │                       ├─ AgentMustBePublished policy check   │                              │
  │                       ├─ ConcurrentCallQuotaNotExceeded check │                              │
  │                       ├─ CallingWindowEnforced check (outbound)                              │
  │                       ├─ Compliance gate (§20) — cached read  │                              │
  │                       ├─ INSERT call_sessions (status=INITIATED) ── same request txn ────────┤
  │◄── 202/201, call_id, ─┤                                      │                              │
  │    from_number        │                                      │                              │
  │                       │                                      ├─ TelephonyPort.place_call() ─►│
  │                       │                                      │◄── ProviderCallRef ───────────┤
  │                       │                                      ├─ UPDATE status=RINGING (async, event-driven)
  │                       │                                      │      (Note over Call,Bus in 4B §18.2:
  │                       │                                      │       the callee's eventual answer arrives
  │                       │                                      │       via the provider's own webhook, which
  │                       │                                      │       is the provider callback surface, §10.4 —
  │                       │                                      │       never a second tenant-facing REST call)
  │◄── call.state_changed events on /ws/v1/voice/calls/{id} ─────┤                              │
```

The response body carries `call_id` and `status: "INITIATED"` — an honest reflection of exactly what has committed at response time, matching 6C's own discipline of never returning a field the response transaction cannot honestly know (6C §15.1's `compliance_policy_seeded` removal is the precedent this follows). Callers observe subsequent state via `GET /calls/{id}` (poll) or the WS observation channel (push, §13).

### 10.2a Outbound Caller-ID Selection — Deterministic, Server-Resolved (corrected this pass)

**The gap this subsection closes:** the first draft of this document correctly forbade a raw, client-supplied `from_number` (ADR-6D-07 still stands, unchanged), but never defined *how* the server picks a caller ID when a tenant owns more than one outbound-capable `voice.tenant_phone_numbers` row. That ambiguity is resolved here.

**Request contract:**

```json
POST /api/v1/calls
{
  "agent_id": "...",
  "to_number": "+91XXXXXXXXXX",
  "phone_number_id": "...",
  "campaign_lead_ref": null
}
```

- The client selects an **opaque `phone_number_id`** (a `voice.tenant_phone_numbers.id`, per §19.1's own read endpoints) — never a raw E.164 `from_number`. ADR-6D-07's prohibition is unchanged; this only adds the missing selection mechanism.
- The server resolves the actual E.164 caller ID from the selected row and returns it in the response as `from_number` — the client learns the resolved number, it never asserts it.
- **Validation, in order:** (1) `phone_number_id` must resolve to a `voice.tenant_phone_numbers` row belonging to the caller's own tenant — a cross-tenant or nonexistent ID yields `404 RESOURCE_NOT_FOUND` (6B/6C non-disclosure discipline, §25); (2) the row's `status` must be `ACTIVE` and `outbound_enabled = TRUE` (5C §5.13) — otherwise `422 VALIDATION_ERROR`, `error.details.field: "phone_number_id"`; (3) if the row's `assigned_agent_id` is set, it must match the request's `agent_id` — a tenant may not place an outbound call as an agent through a number assigned to a different agent, preventing caller-ID/agent-identity mismatch — otherwise `422 VALIDATION_ERROR`.
- **`phone_number_id` is optional** only when the resolved Agent has **exactly one** eligible (`ACTIVE`, `outbound_enabled=TRUE`, and either unassigned or assigned to this Agent) `tenant_phone_numbers` row — in that single-number case the server resolves it automatically, matching the common single-number-tenant deployment shape without forcing every caller to look up an ID it has no real choice over. When more than one eligible number exists, `phone_number_id` becomes **required**; its omission yields `422 VALIDATION_ERROR`, `error.details.field: "phone_number_id"`, `error.details.reason: "ambiguous — multiple eligible outbound numbers, phone_number_id required"`.
- **No `default_outbound_phone_number` column is invented.** 5C §5.13 has no such column, and none is added here (Phase 5 remains untouched) — "exactly one eligible number" is computed as a query-time condition (`COUNT(*) = 1` over the eligibility filter above), not a stored default flag.

This keeps `from_number` selection fully deterministic and fully server-controlled while giving a genuinely multi-number tenant an explicit, auditable way to choose which of its own numbers places a given call.

### 10.3 Endpoints (full contracts in §28)

| Endpoint | Purpose |
|---|---|
| `POST /api/v1/calls` | Initiate an outbound call |
| `GET /api/v1/calls` | List calls (filterable by `status`, `direction`, date range, `contact_ref`) |
| `GET /api/v1/calls/{call_id}` | Get one call |
| `POST /api/v1/calls/{call_id}/terminate` | End an in-progress or ringing call (§11.2) |
| `POST /api/v1/calls/{call_id}/transfer` | Transfer to a human/queue (§11.2) |
| `POST /api/v1/calls/{call_id}/hold` | Place an active call on hold (§11.2) |
| `POST /api/v1/calls/{call_id}/resume` | Resume a held call (§11.2) |

There is no `POST /api/v1/calls/{call_id}/answer` — inbound-call answering is a provider-driven event, never a tenant REST action (§10.4).

### 10.4 Inbound Call Boundary — Classification (governing task requirement)

| Surface | Path shape | Auth | Tenant-facing? |
|---|---|---|---|
| Provider call-status callback | `POST /webhooks/voice/{provider_slug}/events` | Provider-native signature scheme (HMAC or provider-specific header, verified per-adapter in the Telephony ACL, 4B §21 "Anti-Corruption Layer"), **not** tenant JWT/API-key | **No.** Provider-facing only. Recorded in `webhooks.inbound_webhook_events` (5I §10) exactly as 6A §28.2 already specifies for every inbound provider callback platform-wide — 6D does not invent a second inbound-webhook mechanism, it fits Voice's provider callbacks into the one that already exists. Idempotent on `UNIQUE (organization_id, provider_slug, provider_event_id)`. |
| Provider media stream | `/ws/v1/voice/media/{session_id}` (conceptual path, reconciled to 6A §27.1's platform-wide `/ws/v1/...` convention; wire format is 3B's existing raw binary/control-frame protocol, unmodified) | Call-setup payload correlation (3A §11.2/§3), not tenant JWT | **No.** Internal/realtime media surface — the actual audio. Never reachable by a tenant's browser session or API key. |
| Tenant call observation | `/ws/v1/voice/calls/{call_id}` (§13, new) | Tenant JWT (query param or WS subprotocol, per 6A §27.2) | **Yes.** This is the channel a tenant's dashboard/supervisor UI connects to. |
| Tenant call control | `/api/v1/calls/{call_id}/*` (§10.3) | Tenant JWT or API key | **Yes.** |

The Anti-Corruption Layer boundary (4B §21) is restated as binding for 6D: every provider-specific field mapping (Exotel/Twilio/Telnyx wire format → `InitiateCall`/`AnswerCall`/`CallEnded` commands) lives in the Telephony ACL adapter, never in a 6D-designed endpoint handler or response model. 6D's REST/WS contracts are 100% provider-agnostic by construction — no endpoint in this document accepts or returns a provider-native field name.

### 10.5 Outbound Eligibility — What 6D Checks, What It Does Not

`POST /calls` runs three policies inline (4B §9, cheap, in-process, no external call): `AgentMustBePublished`, `ConcurrentCallQuotaNotExceeded` (reads `call_sessions` partial index `idx_cs_org_status WHERE status='ACTIVE'`, 5C §9.1 — an indexed count, not a live provider probe), `CallingWindowEnforced` (compares against `AgentVersion.calling_hours`, already in the Redis-cached snapshot). It does **not** run consent/suppression/DNC eligibility checks — per 4I §16.3, those are "checked at campaign dispatch (before the call), never during a turn" and belong to the Campaign Engine's `OutboundEligibilityService` (4I §6.2), a 6E+ concern. A tenant calling `POST /calls` directly (not via a campaign) is responsible for its own consent basis exactly as 4I §7.1's platform/organization responsibility boundary states — 6D does not fabricate a compliance gate this endpoint was never designed to own beyond what §20 requires.

---

## 11. Call Control / State Transitions

### 11.1 Full State Machine (4B §7.1, 5C §5.1 CHECK constraint — verbatim, unmodified)

```
INITIATED ──► RINGING ──► ANSWERED ──► ACTIVE ──► ON_HOLD ──► ACTIVE (resume)
    │             │                       │           │
    │             ├──► NO_ANSWER          │           └──► ABANDONED (hold timeout)
    │             ├──► CANCELLED          ├──► TRANSFERRING ──► TRANSFERRED
    │             └──► VOICEMAIL          │                └──► ACTIVE (transfer failed)
    │                                     ├──► WRAP_UP ──► COMPLETED
    └──► FAILED                          ├──► FAILED
ANSWERED ──► FAILED                       └──► ABANDONED (caller hangs up)
```

Terminal states: `NO_ANSWER, CANCELLED, VOICEMAIL, TRANSFERRED, COMPLETED, FAILED, ABANDONED`. Per 4B §5.1 invariant 2: **a Call in any terminal state accepts no further commands** — every action endpoint below rejects with `409 STATE_CONFLICT` against any of these seven states.

### 11.2 Action Endpoints — Guard Table (CAS pattern, §5 finding #4 / ADR-6D-03)

No `SECURITY DEFINER` guard function exists in 5C for `call_sessions.status` (verified, §5). 6D reuses 6C's own ADR-6C-02 mechanism exactly: an atomic conditional `UPDATE ... WHERE status = ANY($allowed_current) RETURNING id`. Zero rows affected → `409 STATE_CONFLICT` with `error.details.current_state` (read back in the same handler for an honest error body) — never a `SELECT ... FOR UPDATE` (6A §17.3 forbids API-layer locking beyond what a DB function already does).

| Action endpoint | Allowed current state(s) | Resulting state | Disambiguation applied |
|---|---|---|---|
| `POST /calls/{id}/terminate` | `RINGING` | `CANCELLED` | Terminate-intent on a not-yet-answered outbound call maps to the frozen state machine's `RINGING → CANCELLED` transition (4B §7.1) — an explicit, documented API-layer mapping of one tenant intent ("stop this call") onto the two matching pre-existing transitions, not a new domain transition |
| `POST /calls/{id}/terminate` | `ANSWERED`, `ACTIVE` | `WRAP_UP` (→ `COMPLETED` once goodbye audio delivered, in-process, 4B §7.1 note) | `EndCall(initiated_by=API_USER)` — 4B §12.1's `EndCallInitiator` enum already includes a caller-initiated case alongside `AGENT_DIRECTIVE \| CALLER_HANGUP \| SYSTEM_TIMEOUT \| ADMIN` |
| `POST /calls/{id}/transfer` | `ACTIVE` | `TRANSFERRING` (→ `TRANSFERRED` or back to `ACTIVE` on failure, provider-confirmed, async) | Exact 4B §7.1 transition; `TransferOnlyOncePerCall` policy (4B §9) additionally guards a call already `TRANSFERRED` |
| `POST /calls/{id}/hold` | `ACTIVE` | `ON_HOLD` | Exact 4B §7.1 transition |
| `POST /calls/{id}/resume` | `ON_HOLD` | `ACTIVE` | Exact 4B §7.1 transition; hold-timeout auto-transition to `ABANDONED` is system-driven (APScheduler stale-session reaper, 3B §18.2), not reachable via this endpoint once expired — resume on an already-`ABANDONED` call correctly 409s |

**What is deliberately not exposed:** a call in `TRANSFERRING`, `WRAP_UP`, or `INITIATED` accepts none of the four action endpoints — these are transient, system-advanced states with no tenant-commandable exit per 4B's own state diagram, and 6D does not invent one.

### 11.3 Why Tier B, Not Tier A (restated precisely for Voice)

Every action endpoint above completes its response once the CAS `UPDATE` commits — it does not wait for `TelephonyPort.transfer()`/`hangup()` to receive the provider's own confirmation. That confirmation arrives asynchronously as a provider webhook (§10.4), which the platform then reflects as a further state transition (`TRANSFERRING → TRANSFERRED`) and a WS event (§13/§29) — exactly 6A §11 Tier B's documented rationale ("this is what keeps Tier B close to Tier A despite triggering real-world effects").

### 11.4 Race Conditions (governing-task-required explicit analysis; full table in §30)

- **Terminate vs. transfer, concurrent:** both target `ACTIVE` as their sole allowed source state for their respective non-`terminate`-from-`RINGING` paths; the CAS `UPDATE` is atomic per row — whichever request's `UPDATE` commits first wins, the second sees zero rows affected against the now-different `current_state` and receives `409` with the accurate `current_state` in the body. No lost update, no double transition.
- **Remote hangup (provider webhook) vs. local terminate (tenant REST):** the provider webhook handler and the REST terminate handler both attempt the same CAS `UPDATE`; only one can win. If the webhook wins first (caller hung up a fraction of a second before the tenant clicked "end call"), the tenant's REST call correctly 409s with `current_state: "COMPLETED"` or `"ABANDONED"` — not a 500, not a silent success.
- **Duplicate provider status callback:** 5I's `UNIQUE (organization_id, provider_slug, provider_event_id)` (§10.4) makes redelivery of the same callback a no-op before it ever reaches the CAS update a second time.

---

## 12. Conversation / Turn Design

### 12.1 Grounding and the One-Per-Call Rule

`Conversation` — AggregateRoot, 4B §5.2; table `voice.conversations`, 5C §5.2. `voice.conversations.call_id` carries a `UNIQUE` index (`idx_conv_call_id`, 5C §9.2) — one Conversation per Call, enforced at the DB layer, matching 4B §5.1 invariant 5 ("`ConversationRef` is set exactly once"). 6D exposes no endpoint that could violate this: there is no `POST /conversations` at all — a Conversation is created only by the internal `StartConversation` command (4B §12.1), itself triggered by the Call's provider-confirmed answer event, never by a tenant HTTP request.

### 12.2 Turns Are a Read-Only Projection, By Design

`Turn` (4B §5.2, embedded entity) is materialized as its own table (`voice.turns`, 5C §5.3) purely for checkpoint-write efficiency — it is not a separately-owned aggregate and 6D does not expose create/update for it. `UNIQUE (conversation_id, sequence_number)` (5C §7) is the DB-enforced monotonicity guarantee; 6D's read endpoint (`GET /conversations/{id}/turns`) simply orders by it, and additionally supports resync after a realtime gap (§28.18) via this same, persisted `sequence_number`.

**Two same-word, different-namespace identifiers — stated explicitly to prevent confusion (corrected this pass):** `voice.turns.sequence_number` (persisted, monotonic **within one Conversation**, 5C §5.3) and the WS envelope's `sequence` field (§13.3, monotonic **within one WS connection**, resets on reconnect) are **unrelated counters that happen to share the English word "sequence."** A client must never compare them, subtract one from the other, or use a WS `sequence` value as a `since_sequence` REST query parameter, or vice versa. Resync after a realtime gap uses only `voice.turns.sequence_number` via `since_sequence` (§28.18); resync/gap-detection on the live socket itself uses only the WS `sequence` field (§13.3, §29.2).

### 12.3 Six Distinct "Message" Concepts — Not Collapsed Into One

Per the governing task's explicit instruction, these are never conflated in this design, in the WS catalog (§29), or in client-facing documentation:

| Concept | Persisted? | Where it lives | Visible via |
|---|---|---|---|
| **Persisted Turn** | Yes — Postgres, checkpoint per completed turn | `voice.turns` | `GET /conversations/{id}/turns` (REST), `turn.completed` (WS, §29) |
| **Realtime Turn Event** | No — ephemeral notification of a state change | Redis hot-tier only (5C §4.1) | WS events only (`turn.agent_response_final`, etc., §29) |
| **Partial STT Event** | **Never** — 5C §5.10/§11.4: PostgreSQL stores only finalized segments | Redis hot-tier only | `turn.utterance_partial` (WS only, §29) |
| **Final STT Event** | Yes — one row per final segment | `voice.transcript_segments` | `turn.utterance_final` (WS, real-time) + `GET .../transcript/segments` (REST, after the fact) |
| **LLM Stream Event** | No — the incremental text delta itself is never persisted; only the final `response_text` on the completed Turn is | Redis hot-tier only, in-process | `turn.agent_response_delta` (WS only, marked provider-dependent granularity, §29) |
| **TTS Audio** | No — never stored as a discrete resource; the finished call may later have a `Recording` (a wholly separate aggregate, §16) | Never a database row | Never a REST or WS JSON payload (6A §29 — audio bytes are never embedded in JSON) |

### 12.4 Bounded Context Hydration — Compatible With the Latency Target

The governing task requires an explicit answer to "how much conversation history is loaded, and when," because an unbounded hydration strategy would directly threaten §21's target. 6D's answer, grounded in what 4B/3B already specify (not a new invention):

- **At call start:** `ConversationMemoryPort.load()` (4B §16) runs during `StartConversation`, overlapping telephony connection establishment (4I §16.5, ADR-REVIEW-03) — this is a Memory-context (6E+) concern, not a 6D endpoint, but 6D's design respects it by never requiring an additional REST round-trip before the first turn can begin.
- **Per turn, in-process:** the Voice Orchestrator (3B §9) holds the current Conversation's in-flight state in the Redis hot-tier (`conversation:{session_id}:state`, 5C §4.1) — a full re-read of all prior Turns from Postgres never happens on the hot path; only the running token-budget check (`ConversationContextService`, 4B §8.5) decides when older turns need summarization, itself an async/Memory-context concern.
- **On the REST/observation side (6D's actual surface):** `GET /conversations/{id}/turns` is a **paginated** endpoint (6A §14 cursor pagination, default page size per 6A §14.3) — a supervisor UI or API integration retrieving a long call's history does so in bounded pages, never as one unbounded embed. No 6D response ever inlines a full Turn history inside a Call or Conversation resource body (6A §36's "unbounded nested resource embedding" anti-pattern, capped at 20 items inline — 6D's Call/Conversation detail responses do not embed Turns at all, by design, precisely to avoid needing to reason about that cap).

### 12.5 Endpoints (full contracts in §28)

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/conversations/{conversation_id}` | Get conversation (status, qualification outcome, sentiment, summary, token usage, turn count) |
| `GET /api/v1/conversations/{conversation_id}/turns` | Paginated, sequence-ordered list of persisted Turns |

A convenience reverse-lookup (`call.conversation_id`, already present on the Call resource's response body, §28) is sufficient to navigate Call → Conversation; no separate `/calls/{id}/conversation` alias is added.

---

## 13. Realtime WebSocket Contract

### 13.1 Two Connection Paths, Deliberately Not Merged

| Path | Surface | Wire format | Owner |
|---|---|---|---|
| `/ws/v1/voice/media/{session_id}` | Provider-facing media ingress | Raw binary (audio) + JSON control frames, **3B §17, reused unmodified** — no generic envelope, per 6A §27.3's own carve-out ("Voice's WS protocol uses raw binary/control frames with no generic envelope... explicitly flagged as unformalized") | Voice Gateway (existing) |
| `/ws/v1/voice/calls/{call_id}` | Tenant-facing single-call observation + light control | 6A §27.3's generic JSON event envelope, **instantiated here for the first time** | 6D (this document) |
| `/ws/v1/voice/calls/stream` | Tenant-facing multi-call observation (org-wide "active calls" dashboard) | Same envelope; explicit per-call `session.subscribe`/`unsubscribe` frames | 6D (this document) |

6D does not touch the first row's wire format — 6A §27.1 already ratified raw WebSocket as the platform-wide realtime transport specifically *because* Voice's existing implementation already committed to it; redesigning it here would contradict that ratification. 6D's actual contribution is the second and third rows: the tenant-observable event stream 6A §27.3 explicitly deferred to "whatever future event type" needed one.

### 13.2 Connection Lifecycle (6A §27.2, applied)

```
CONNECTING → AUTHENTICATED → BOUND → STREAMING → CLOSING → CLOSED
```

1. **CONNECTING:** client opens `wss://.../ws/v1/voice/calls/{call_id}` (or `.../stream`) with the access token as a WS subprotocol value (`Sec-WebSocket-Protocol: bearer.<jwt>`) — query-param fallback accepted per 6A §27.2's stated reason (browsers cannot set arbitrary headers at handshake time). No API-key auth for this channel — WS connections are always a live human/UI session (access token only), consistent with 6C's own restriction of certain flows to session-bound credentials.
2. **AUTHENTICATED:** server validates the JWT exactly as the REST pipeline does (6A §9.1/§23) — same middleware entry point, same tenant-resolution chain.
3. **BOUND:** for the single-call path, the server resolves `{call_id}` against the caller's `organization_id` — a cross-tenant `call_id` yields **connection close with code 4404** (never a distinguishing error that would leak existence, per 6B/6C's non-disclosure discipline applied to WS closes) — and checks `call:read` (§25). For the multi-call `stream` path, BOUND happens with no specific call yet; the client must send `session.subscribe` per call (§13.4).
4. **STREAMING:** events flow (§13.5, §29).
5. **CLOSING/CLOSED:** graceful (`session.unsubscribe` then client-initiated close) or server-initiated (call reached a terminal state and a configurable grace period elapsed — default 30s post-terminal, enough for a UI to render the final state before the socket closes).

### 13.3 Message Envelope (6A §27.3, instantiated) — Two Schemas, Not One (corrected this pass)

**Server-sent events and client-sent control frames use two distinct, deliberately different schemas — restated explicitly here per this pass's own review (§13.6a) because the first draft's examples mixed them without saying so.**

**Server → client (every row of §29.1–29.7) — the full envelope:**

```json
{
  "event_id": "01930000-0000-7000-8000-000000000001",
  "event_type": "turn.utterance_final",
  "version": 1,
  "timestamp": "2026-08-23T09:15:30.123Z",
  "organization_id": "...",
  "call_id": "...",
  "conversation_id": "...",
  "turn_id": "...",
  "sequence": 42,
  "replay_cursor": "01930000-...-000002a1",
  "payload": { }
}
```

**Client → server control frames (§13.6, §29.1) — a minimal, flat schema, never the envelope above:**

```json
{ "type": "session.subscribe", "call_id": "...", "resume_from_cursor": "..." }
```

Client frames carry no `event_id`/`sequence`/`replay_cursor` — they are one-off commands, not entries in an ordered, replayable event stream, so none of those fields have meaning for them. §13.6a states this distinction as a binding rule for every message type this document defines.

**Two independent identity concepts on the server-event envelope — corrected this pass, replacing a genuine contradiction in the first draft:**

| Field | Scope | Purpose | Survives reconnect? |
|---|---|---|---|
| `sequence` | **Per-connection** — resets to 0 (or 1) on every new WS connection | Live gap detection **on the current socket only**: a client that sees `sequence` jump from 41 to 44 knows it missed events 42–43 *on this connection*, without needing any external state | **No** — a new connection has a new, independent `sequence` namespace. The first draft's reconnect design incorrectly tried to resume from a `sequence` value produced by a connection that no longer exists; that design is retracted (§13.7). |
| `replay_cursor` | **Stable per (call_id, subscription)** — independent of any one connection | The only field a client may present on reconnect to resume delivery from a specific point | **Yes** — this is exactly its purpose. Derived from the ordering position of the underlying Redis-backed short-lived event buffer (§13.7) that already exists in this design, not a new piece of infrastructure. |

`turn_id`/`conversation_id`/`call_id` remain the correlation IDs the governing task requires; cross-context event ordering is explicitly not guaranteed platform-wide (4G §12.4, 6A §27.3) — 6D does not claim otherwise for these events either.

### 13.4 Subscription Model

- **Single-call path (`/calls/{call_id}`):** implicitly subscribed at `BOUND` — every event for this `call_id` streams automatically. A client may still send `session.subscribe` with `resume_from_cursor` immediately after connecting (e.g., right after a reconnect) to trigger replay for this one call; otherwise it is accepted as a no-op/ack for client-implementation symmetry with the multi-call path.
- **Multi-call path (`/calls/stream`):** client sends `{ "type": "session.subscribe", "call_id": "...", "resume_from_cursor": "..." }`; the server re-verifies `call:read` + tenant ownership **on every subscribe**, not only at connect (6A §27.4's explicit rule: "subscription-scoped channels re-verify RBAC permission on subscribe, not just at connect time"). `session.unsubscribe` removes it. A connection may hold many concurrent subscriptions, bounded by a configurable per-connection cap (default 50) to bound server-side fan-out cost.
- **Each call subscription owns its own replay cursor (§13.7) — never a single global counter shared across calls.** On the `/calls/stream` path, a connection subscribed to five calls tracks five independent `replay_cursor` positions, one per `call_id`; reconnecting and resubscribing to three of those five calls resumes each from its own last-seen cursor, entirely independent of what happened on the other two. There is no connection-wide resume position — resume is always scoped to `(call_id, subscription)`, matching the fact that `sequence` (per-connection) and `replay_cursor` (per-call-subscription) are already two different scopes (§13.3).

### 13.5 Server-Emitted Event Categories (full catalog, §29)

Call-state events (`call.state_changed`, `call.answered`, `call.held`, `call.resumed`, `call.transferring`, `call.transferred`, `call.ended`, `call.failed`) mirror `call_sessions.status` transitions 1:1 — every one of them is a **reflection** of a state already committed via REST (§11) or a provider callback (§10.4), never a WS-originated state change. Turn/utterance events, tool-execution events, and voice-runtime events (`voice.barge_in_detected`, `voice.tts_cancelled`) are covered in §14 and §29.

### 13.6 Client-Sent Control Frames — Deliberately Narrow

**Design decision (ADR-6D-05, §37):** this channel carries **no** call-control commands (no WS-native terminate/transfer/hold/resume). Every guarded state transition goes through the REST action endpoints of §11 only. The WS channel sends `session.subscribe`, `session.unsubscribe`, and `heartbeat.ping` (client) / `heartbeat.pong`, `session.subscribed`, `error` (server) — nothing else. **Why:** 6A §17.3 already forbids the API layer from introducing a second, parallel locking/authority mechanism for a guarded resource ("introducing a second, API-layer locking scheme would create two sources of truth for who owns this row right now"); allowing WS-native `terminate` alongside REST-native `terminate` would create exactly that — two independent code paths racing to CAS-update the same row, doubling the concurrency surface analyzed in §11.4 for no latency benefit (call control is not on the ≤750ms hot path — §21 §10 already establishes it as Tier B).

### 13.6a Client vs. Server Message Schemas — Binding Rule (corrected this pass)

Per Task L of this correction pass: this document defines **exactly two** message shapes, never mixed:

1. **Client-sent control frames** (`session.subscribe`, `session.unsubscribe`, `heartbeat.ping`) use the flat `{ "type": "<name>", ...fields }` shape shown in §13.3/§13.4/§29.1. They are never wrapped in the server-event envelope, and never carry `event_id`, `sequence`, or `replay_cursor` — those concepts belong to the ordered, replayable server→client stream only.
2. **Server-sent events** (every other row in §29) use the full envelope shape shown in §13.3, with `event_type` (not `type`) naming the message, plus `event_id`/`version`/`timestamp`/correlation IDs/`sequence`/`replay_cursor`/`payload`.

Every table in §29 is read against this rule: a `dir: C→S` row uses schema 1; a `dir: S→C` row uses schema 2. No message type in this document uses a third shape.

### 13.7 Heartbeat, Reconnect, Backpressure, Limits

| Concern | Rule |
|---|---|
| Heartbeat | Server-side presence TTL (6A §27.2, reused); client sends `heartbeat.ping` every 20s, server replies `heartbeat.pong`; no pong within 45s → server closes with 4408 |
| **Reconnect / replay cursor** — **fully corrected this pass, replacing the first draft's contradictory `resume_from_sequence` design** | **Non-voice realtime channel — resume IS supported** (6A §27.2's explicit carve-out: "Non-voice channels... MAY support resume-from-sequence on reconnect, since there's no live-audio real-time constraint"), but resume is keyed by `replay_cursor`, never by the per-connection `sequence` counter that a closed connection's namespace no longer has any meaning for (§13.3). Full contract below. |
| Duplicate/out-of-order | `event_id` is the dedup key (6A §27.3) — a client that sees a repeated `event_id` discards the duplicate silently; a live `sequence` gap (current connection only) triggers the same-connection resync path (§29.2), never a client-side guess at reordering |
| Backpressure | Server-side per-connection outbound queue, bounded (default 500 events); on overflow the server drops the **oldest** buffered non-final events (partial-STT-class, high-frequency, superseded quickly) first, never `call.state_changed`/terminal events, and emits `resync.required` for the dropped range, carrying the `replay_cursor` range the client can use to catch up (§29.2) — mirrors 3B §12's "queue.put() naturally blocks/drops" backpressure philosophy, adapted from binary audio frames to JSON events |
| Max message size | 32KB per message (JSON events are small; this is generous headroom, not audio — audio never traverses this channel, §12.3) |
| Rate/abuse limits | Connection-level: 5 concurrent per source (6A §27.2/3F §8.4, reused); subscribe-frame rate: 20/min per connection (abuse guard against subscribe-spam on the `stream` path) |
| Observability | Every connection tagged with `organization_id`, `call_id` (bounded — one per single-call connection; a set for `stream`), `connection_id` (high-cardinality, trace/log-correlation only, never a Prometheus label per §32's cardinality rule) |

#### 13.7a Replay Cursor — Full Contract

| Property | Definition |
|---|---|
| **Identity** | An opaque, server-generated string (implementation may use the underlying Redis Stream entry ID, e.g. `<ms-timestamp>-<seq>` — Redis Streams' own native ID format — so no new ID scheme is invented; this reuses the ordering primitive Redis Streams already provides for the outbox-publisher's consumer-group mechanism, 5J/077, applied here to the short-lived per-call event buffer rather than the durable outbox) |
| **Scope** | One `replay_cursor` sequence per `(organization_id, call_id)` — **not** per connection, per subscription-instance, or global. Two different connections replaying the same `call_id` from the same cursor value see the identical replay sequence. |
| **Ordering guarantee** | Total order within one `call_id`'s buffer, matching the order events were originally emitted server-side for that call. No cross-call ordering guarantee is made (consistent with 4G §12.4/6A §27.3's platform-wide stance, restated §13.3). |
| **Expiry / retention** | The same short-lived Redis buffer already named in this design (60s retention window, per-call, holding the recent event history for exactly this purpose) — a `replay_cursor` older than the buffer's retention window is **too old** by construction; there is no separate cursor-expiry clock to reason about beyond the buffer's own TTL. |
| **Cursor too old** | The server cannot locate the requested `replay_cursor` in the live buffer (either it fell outside the 60s window, or the call itself predates the buffer, e.g., a reconnect long after the call ended) → server responds with `resync.required` (§29.2) instead of replaying, naming the requested cursor as unresolvable; the client falls back to REST (`GET /conversations/{id}/turns?since_sequence=...`, §28.18) for the persisted subset of what it missed, and accepts that ephemeral-only content (partial STT, LLM deltas) from that gap is permanently unrecoverable — consistent with §12.3's existing statement that partials/deltas are never durable. |
| **Duplicate replay handling** | Replaying from a cursor may re-deliver an event the client already has (e.g., if the client's own bookkeeping of "last successfully processed cursor" lagged slightly behind what it actually rendered) — `event_id` (unchanged, §13.3) remains the dedup key for this case exactly as it already is for live delivery; a replayed event with an `event_id` the client has already seen is discarded, not reprocessed. |
| **Multi-call `/calls/stream` behavior** | Each `session.subscribe` carries its own `resume_from_cursor` scoped to the one `call_id` in that subscribe frame (§13.4) — a connection resubscribing to five calls sends up to five independent `resume_from_cursor` values (or omits it per-call to start fresh from "now"), never one cursor covering the whole connection. |
| **New connection, no cursor supplied** | Starts fresh from "now" for that `call_id` — identical behavior to the first draft's un-corrected default, unaffected by this fix. |

---

## 14. Barge-In / Interruption Semantics

### 14.1 Where Barge-In Actually Happens (restated honestly — an API boundary, not a reimplementation)

Barge-in detection and TTS cancellation execute **in-process**, inside the Voice Orchestrator's asyncio task group, using `BargeInDetectionService` (4B §8.3) and `TtsPort.cancel()` (3B §10.3) — this is existing, frozen, in-process runtime behavior (3B §12.2), not something 6D designs from scratch. 6D's job is exactly two things: (1) define how this becomes **visible** to a tenant observer via the WS channel, and (2) define the **configuration surface** (already in §8.2's `VoiceConfig.BargeInSensitivity`) that lets a tenant tune it per agent. 6D does not invent a REST or WS command that *triggers* barge-in from outside the call — barge-in is caller-speech-driven only, by domain design (4B §8.3).

### 14.2 The Runtime Sequence, and 6D's Observable Surface Over It

```
Caller speaks while agent audio is playing (state = SPEAKING)
        │
        ▼
STT partial fragment, confidence > BargeInSensitivity threshold (in-process, 3B §12.2)
        │
        ▼
BargeInDetectionService.evaluate() → BARGE_IN_DETECTED (in-process, pure function, 4B §8.3)
        │
        ├──► TtsPort.cancel(stream_id) — attempt to stop the in-flight synthesis (in-process)
        ├──► discard unplayed audio already queued for the telephony leg (in-process, 3B §12.2)
        ├──► CallStateMachine sub-state: SPEAKING → LISTENING (in-process, 4B §7.2)
        │
        ▼
  ══════════ 6D's observable boundary begins here ══════════
        │
        ├──► WS event: voice.barge_in_detected  {call_id, conversation_id, turn_id, detected_at}
        ├──► WS event: voice.tts_cancelled      {call_id, conversation_id, turn_id, cancel_confirmed: bool}
        └──► persisted: the interrupted Turn's `barge_in_occurred = TRUE` (5C §5.3 column, written at
                         the turn's normal checkpoint boundary — never a separate synchronous write)
```

### 14.3 Race Handling and Stale-Audio Suppression

- **Race between barge-in detection and turn checkpoint:** if the caller's barge-in fragment arrives after the Turn's response has already been fully delivered and checkpointed, `BargeInDetectionService` naturally no-ops (there is nothing playing left to cancel) — this is a timing outcome of the in-process pipeline (3B §12.2), not an API-layer race 6D needs to additionally guard, since no 6D-owned resource is mutated by this path outside the normal Turn checkpoint.
- **Stale audio suppression:** "discard unplayed audio already queued for the telephony leg" (3B §12.2) happens entirely in-process, before any audio reaches the caller — 6D's WS observer receives `voice.tts_cancelled` as a factual notification, never as a command it must act on to prevent the caller hearing stale audio (that guarantee is the runtime's, not the API consumer's, responsibility).
- **`cancel_confirmed` field, explicitly nullable-honest:** `TtsPort.cancel()`'s actual provider-level cancellation guarantee is an **open, disclosed dependency** (3B §23, Review Note 2: *"Confirm barge-in confidence threshold and TTS cancellation support against ElevenLabs' real API"* — never validated against a live provider integration anywhere in Phase 1–5). 6D's `voice.tts_cancelled` event therefore carries `cancel_confirmed: boolean` rather than asserting cancellation unconditionally — if the TTS provider's streaming API does not support true mid-stream cancellation, the field is `false` and the event still fires (the platform has stopped *sending* further audio to the caller even if the provider-side buffer briefly continues), so an observer is never told something false. This is carried forward as **DEP-6D-08** (§36) — an inherited, not newly-introduced, dependency.
- **Correlation:** every barge-in-related event carries `turn_id` — the interrupted turn — so an observer can unambiguously associate the interruption with the specific Turn it truncated, even though that Turn's own `turn.completed` event (with `barge_in_occurred: true`) may arrive slightly later once the checkpoint write completes.

### 14.4 What Is Persisted vs. Transient (restated for barge-in specifically)

| Data | Persisted? | Where |
|---|---|---|
| The fact that barge-in occurred on Turn N | Yes | `voice.turns.barge_in_occurred` (5C §5.3) |
| The exact partial-STT confidence value that triggered it | No | Transient, Redis/in-process only — never a durable column (5C has no such column, and 6D does not propose one) |
| The cancelled TTS audio bytes | Never existed as a resource | Nothing to persist — audio is never stored except as part of a full-call `Recording` (§16), and a cancelled synthesis was never part of that recording pipeline's output in the first place |
| The WS notification itself | No | Ephemeral WS event only (§13.3) — an observer who was not connected at the moment of interruption learns about it only via the persisted `barge_in_occurred` flag on the Turn, after the fact, via REST |

---

## 15. Provider Routing / Failover API Boundary

### 15.1 Server-Side Only — No Client Coupling to Vendor SDKs

`ProviderConfig` (4B §5.8, `voice.provider_configs`, 5C §5.11) is read by `ProviderSelectionService` (4B §8.2, a pure, no-I/O domain service) and `ModelRouter` (3B §11) entirely in-process. No 6D endpoint returns a provider-native SDK shape, a raw model parameter object, or a `credential_ref` value (§26). The API surface is read-only observability over already-computed health/routing state — never a live probe.

### 15.2 What 6D Exposes

`GET /api/v1/provider-health?category={TELEPHONY|STT|TTS|LLM|EMBEDDING}` — returns, per active `ProviderConfig` row visible to the tenant (own + platform defaults, per 5C §11.3's mixed-scope RLS read policy): `provider_id`, `category`, `model_id`, `health_state`, `circuit_state`, `p50_latency_ms`, `error_rate_pct`, `supports_languages[]`, `priority`. **Never** `credential_ref`, `config_json` (may contain non-secret but still internal routing parameters), or `last_health_check_at`'s raw scheduling internals.

### 15.3 What 6D Does Not Expose (DEP-6D-06)

Tenant-initiated create/update of a `ProviderConfig` row (choosing a non-default provider, setting `priority`, linking a `credential_ref`) is **not designed** in this document. No `provider:*` permission exists in 5B, and no product requirement for tenant self-service provider selection surfaces anywhere in Phase 1–5 beyond the per-agent `ModelConfig.PreferredProvider`/`FallbackProviders` fields (§8.2), which **are** already exposed via the Agent draft-config PATCH. A tenant's only lever over provider choice is therefore through Agent configuration, not a standalone Provider Config resource — consistent with 4B §8.2's own framing ("respecting the Agent's `ModelConfig.PreferredProvider`").

### 15.4 Hot-Path Discipline (restated as a binding API-design constraint, §21 depends on this)

`ModelRouter.select()` and `ProviderSelectionService.select()` are pure, no-I/O functions (3B §11, 4B §8.2) reading **pre-loaded**, Redis-cached health data (`providerhealth:{provider_name}`, 3B §16). No 6D endpoint, and no code path 6D's design implies, performs a live provider health probe inline with a conversational turn — health is refreshed by the existing periodic Celery health-polling worker (3B §18.2, ~10s cadence), never synchronously. `GET /provider-health` itself reads the same Redis-cached/DB rows any dashboard would — it is a Tier A read, fully decoupled from the turn loop.

### 15.5 Failover Visibility

Provider failover (4B §7.5, §18.5) is entirely in-process and never blocks on a 6D endpoint. Its only API-visible trace is: (a) the Turn's `stt_provider_id`/`llm_provider_id` fields (5C §5.3) reflecting which provider actually served that turn, readable via `GET /conversations/{id}/turns`; (b) `provider.circuit_opened`/`circuit_closed`/`failover_triggered` domain events (4B §11.6), which are internal Redis Streams events (§24) — not surfaced as tenant-facing WS events in this document's message catalog (§29), since a tenant observer cares about *their call continuing to work*, not the platform's internal provider topology; a future Provider Health dashboard-specific WS channel is out of 6D's scope.

---

## 16. Recording API

### 16.1 Grounding

`Recording` — AggregateRoot, 4B §5.6; table `voice.recordings`, 5C §5.8. `status ∈ {PENDING, IN_PROGRESS, STORED, FAILED, DELETED}`. `recording_policy` is a **snapshot** copied from the authoritative `CompliancePolicy.RecordingPolicy` at recording-creation time (4I §27.4 CONTRADICTION-04 resolution, §5 finding #5) — 6D never re-derives or re-reads this field from `CompliancePolicy` after creation; it is immutable, matching the same pattern already established for `RetentionPolicy` (4B §5.6 invariant 3).

### 16.2 Signed-URL Pattern — 6A §29, Reused Exactly

```
GET /api/v1/recordings/{id}/download-url
  → { "download_url": "https://...", "expires_at": "<now+15min>" }
```

No 6D endpoint ever returns `storage_ref` directly or embeds audio bytes in a JSON body (6A §29's absolute prohibition, restated). `content_type`/range-request support is native to the signed S3 URL (audio scrubbing/playback) — no 6D-layer involvement.

### 16.3 Endpoints (full contracts in §28)

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/calls/{call_id}/recording` | Get recording metadata for a call (status, duration, size, policy, retention) |
| `GET /api/v1/recordings/{recording_id}/download-url` | Signed, time-boxed download URL |
| `POST /api/v1/recordings/{recording_id}/delete` | Action endpoint — `STORED → DELETED` (clears `storage_ref`, retains the row for audit, 4B §5.6 invariant 2) |

**Why `POST .../delete`, not `DELETE`:** per 6A §7.6's Delete Semantics table, `recordings` is a **soft-delete resource** whose deletion also has a real external side effect (an S3 object removal job, async) beyond a simple `deleted_at` flag — 6A §8.3's action-endpoint criteria (b) applies ("has side effects beyond the row update"). A bare `DELETE` would also need to communicate the guard (only `STORED` recordings can be deleted; a `PENDING`/`IN_PROGRESS` one cannot) — matching 6A §8.3's criterion (a).

### 16.3a Crash-Safe Durable Cleanup Handoff (corrected this pass — Task J)

**The gap this subsection closes:** the first draft's `delete` transaction cleared `storage_ref` to `NULL` in the same write that set `status='DELETED'`, with the actual S3 object removal described only as "async." That is unsafe as written: if the S3-cleanup step happens in a process that reads `storage_ref` *after* it has already been nulled, there is no durable reference left anywhere for it to delete — the object silently orphans in storage forever.

**Corrected transaction shape — the internal `storage_ref` value is captured and handed off durably, in the same transaction, before it is cleared from the row:**

```sql
WITH old AS (
  SELECT storage_ref FROM voice.recordings WHERE id = $1
)
UPDATE voice.recordings
SET status = 'DELETED', storage_ref = NULL
WHERE id = $1 AND status = 'STORED'
RETURNING (SELECT storage_ref FROM old) AS captured_storage_ref;
-- Single statement; the CTE reads the pre-update value under the same
-- statement snapshot. This is NOT a SELECT ... FOR UPDATE (6A §17.3
-- remains unviolated) — it is the ordinary row-lock any UPDATE already
-- takes, with no separate, additional application-level lock introduced.
```

```
BEGIN
  <CAS UPDATE above, capturing captured_storage_ref, guard: status='STORED'>
  SELECT audit.fn_insert_audit_event(p_action_kind => 'RECORDING_DELETED', ...)  -- §24.0, durable
                                                                                    -- audit — NEVER a
                                                                                    -- direct INSERT
                                                                                    -- (5J §5/§14.2)
  INSERT audit.domain_event_outbox (
    event_type='recording.deleted',
    payload=jsonb_build_object(
      'recording_id', $1,
      'organization_id', ...,
      '_internal_cleanup_ref', captured_storage_ref    -- internal only, see below
    )
  )
COMMIT

-- Only after commit, asynchronously:
recording.deleted consumer (existing outbox → Redis Streams path, §24.1)
  → reads _internal_cleanup_ref from the event payload
  → deletes the S3 object
  → retries idempotently on failure (deleting an already-deleted/nonexistent
    object is treated as success — standard idempotent-delete semantics)
```

**No second cleanup mechanism is invented.** 5C/5A/3F define no separate, dedicated "storage delete job" table distinct from the domain-event outbox already used throughout this document (§24) — per this pass's own instruction to reuse an existing durable mechanism rather than add a new one, the already-verified, already-durable outbox (migration `077_5J1.sql`, live-verified per 6C DEP-6C-16) is the correct, minimal-change home for this handoff.

**Security — the internal reference is never externally exposed:** `_internal_cleanup_ref` travels only inside the outbox payload, consumed only by the internal cleanup worker — it is never rendered by any public 6D response model (§16.2's signed-URL pattern remains the *only* way `storage_ref`-derived data ever reaches a client, and only while the recording is still `STORED`, never after `DELETED`). This does not weaken 5C §13's `pii:voice (reference)` classification of `storage_ref` — an outbox payload is internal system-to-system data, not a public API surface, exactly like the compliance-policy-activation payload already carries an internal `policy_id` with no public-exposure concern (6C §12.2).

### 16.4 Consent/Disclosure Surface — Consumed, Not Redesigned

`Recording.ConsentObtained` and the disclosure-prompt mechanics are driven by the authoritative `CompliancePolicy` (6C-owned, §20) and the in-call disclosure prompt (`RecordingDisclosureRef`, a `PromptRef` — 6E+ Prompt Management territory). 6D's Recording resource surfaces `consent_obtained` (boolean, read-only) as metadata; it does not expose an endpoint to *record* consent (that is `ConsentRecord`, a 4I/CRM-context aggregate, `consent:manage` permission — out of 6D's scope entirely, §3.2).

---

## 17. Transcript API

### 17.1 Grounding

`Transcript` — AggregateRoot, 4B §5.7 (DDR-4B-002 — deliberately separate from Conversation to avoid write contention); tables `voice.transcripts` (metadata) + `voice.transcript_segments` (partitioned, append-only, 5C §5.9–§5.10).

### 17.2 The One Rule This Section Exists to Enforce

**PostgreSQL stores only finalized segments** (5C §5.10, §11.4 — "strictly append-only... There is no UPDATE path for any application role"). 6D's transcript-read endpoints therefore expose **only** what is durably finalized; a transcript's real-time partial content is available exclusively through the WS observation channel's `turn.utterance_partial` events (§13.3, §29) and is never retroactively reconstructable via REST — there is nothing in Postgres to reconstruct it from, by design.

### 17.3 Endpoints (full contracts in §28)

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/conversations/{conversation_id}/transcript` | Metadata: `status`, `total_segments`, `completed_at` |
| `GET /api/v1/conversations/{conversation_id}/transcript/segments` | Cursor-paginated (6A §14), sequence-ordered, finalized segments only |

### 17.4 Access Control / PII

Every segment's `text` field is `pii:voice` (5C §13) — gated by `transcript:read` (exact existing permission, §25), the same permission that already governs 6C's non-disclosure discipline for cross-tenant access (a foreign `conversation_id` yields `404`, never `403`). No field-level redaction is applied beyond the existing permission gate — 5B's role matrix already restricts `transcript:read` to `OWNER/ADMIN/MEMBER` (not `VIEWER`... actually `VIEWER` also holds `transcript:read` per 5B's seed data, §25 restates the exact grant table).

---

## 18. Tool Execution Boundary

### 18.1 Tool Definitions — OWNED BY 6D (Tenant CRUD)

`ToolDefinition` — AggregateRoot, 4B §5.4; table `voice.tool_definitions`, 5C §5.6. Platform built-ins (`organization_id IS NULL`) are seeded and read-only to tenants (5C §16.9 seed data); tenant custom tools are fully tenant-owned.

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/tools` | List tools visible to the tenant (built-in ∪ own, per 5C §11.3's mixed-scope RLS read policy) |
| `POST /api/v1/tools` | Create a tenant custom tool |
| `GET /api/v1/tools/{tool_id}` | Get one tool |
| `PATCH /api/v1/tools/{tool_id}` | Update a tenant-owned tool (never a built-in — `organization_id IS NULL` rows reject PATCH with `403`) |
| `POST /api/v1/tools/{tool_id}/deactivate` | `is_active: true → false` (action endpoint — deactivating a tool referenced by a live `AgentVersion.ToolPermissions` must not silently break in-flight calls; it only prevents *new* selection, exactly mirroring the Agent-deprecation pattern §9.4) |

`input_schema`/`output_schema` are validated as well-formed JSON Schema at create/update time (6D's own validation, not deferred to call time) — 4B §5.4's `ToolDefinition` invariants are otherwise unchanged.

### 18.2 Tool Executions — READ-ONLY PROJECTION

`ToolExecution` — AggregateRoot, 4B §5.5 (DDR-4B-004 — separate from Turn precisely so it can be queried independently). Created and mutated exclusively by the in-process turn loop (4B §18.3's Tool Calling Flow sequence) — 6D exposes **observation only**, never a tenant-invoked create/retry/cancel.

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/conversations/{conversation_id}/tool-executions` | List executions for a conversation, newest first |
| `GET /api/v1/tool-executions/{execution_id}` | Get one execution: `status`, `tool_name`, `arguments` (see §26 PII note), `result`, `attempt_count`, timing |

**Why no cancel/retry endpoint:** 4B §5.5 invariant 2 makes `ToolExecution.Status` transitions strictly monotonic and system-driven (timeout/retry logic lives in the in-process `ToolExecutionPort`, 3B §13, bounded by `ToolDefinition.TimeoutMs`) — there is no tenant-commandable intervention point in the domain model, and 6D does not invent one. A stuck/misbehaving tool execution self-resolves via its own timeout, observable via this read endpoint, not tenant-cancellable.

### 18.3 `arguments`/`result` Exposure — PII and Size Discipline

`arguments` (validated, immutable per 5C §11.7's trigger) is returned in full — it was already tenant-supplied via the Agent's tool configuration. `result` may be large (5C §5.7 notes a 64KB application-layer cap, with >50KB flagged for a future S3-offload pattern not yet implemented) — 6D's `GET .../tool-executions/{id}` response is therefore documented as potentially large relative to other 6D resources, still within 6A §36's 5MB response-body ceiling, and does not require a separate signed-URL pattern today (unlike Recordings) because the 64KB cap keeps it well under any threshold that would need one.

---

## 19. Tenant Phone Number / Provider Config Boundary

### 19.1 Tenant Phone Numbers — Thin, Assignment-Only Surface

`voice.tenant_phone_numbers` (5C §5.13) — globally unique `phone_e164` (one number, one tenant, platform-wide). 6D exposes only what call-routing/agent-configuration visibility genuinely requires:

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/phone-numbers` | List the org's numbers (status, capabilities, assigned agent) |
| `GET /api/v1/phone-numbers/{id}` | Get one number |
| `POST /api/v1/phone-numbers/{id}/assign-agent` | Action endpoint — set/change `assigned_agent_id` (which Agent answers inbound calls to this number, 4B §8.1 `CallRoutingService`) |

**Permission re-review, corrected this pass (Task K / ADR-6D-08):** the first draft gated `assign-agent` by `agent:write` (OWNER/ADMIN/MEMBER). Re-checked against 5B's actual role-permission grant table, this **over-granted** MEMBER: reassigning a live phone number's `assigned_agent_id` takes effect immediately for the next inbound call, with none of `publish`'s version-pinning safety net (§9.1) protecting in-flight calls from a routing change — its blast radius (redirect an entire number's inbound traffic) is closer to `agent:publish`'s "go live" sensitivity (OWNER/ADMIN only) than to an ordinary draft-config edit. The endpoint is retargeted to `agent:publish` — an existing, correctly-scoped permission, not a new one — closing the over-grant without any 5B schema change.

### 19.2 What Is Deliberately Not Designed (DEP-6D-07)

Number **provisioning** (acquiring a new number from a carrier — Exotel/Twilio) is not designed here. `TelephonyPort` (4B §16) has no `provision_number()`/`purchase_number()` method — verified directly against its full method list (`place_call, answer, hold, resume, transfer, hangup`) — and no other Phase 1–5 document defines this capability's command/port shape. Inventing a provisioning endpoint here would mean inventing the underlying domain command it calls, which is out of an API-design document's authority (it belongs in a DDD document). This is disclosed as a genuine, non-blocking scope boundary, not a silent omission — a tenant's numbers must currently be provisioned by an out-of-band/ops process and inserted directly, then made assignable via §19.1's endpoints.

### 19.3 Provider Configuration — Covered in §15

No further boundary distinct from §15 applies here; `provider_configs` is discussed there in full because its primary consumer is the LLM/STT/TTS routing path, not phone-number management, even though both are 5C mixed-scope tables.

---

## 20. Compliance Integration

### 20.1 6D Consumes, Never Redesigns

`CompliancePolicy` is **owned by 6C** (§12 there — CRUD, versioning, activation, the `organizations.compliance_policy_id` non-authoritative pointer discipline). 6D duplicates none of it: no compliance table, no compliance CRUD endpoint, no second activation mechanism.

### 20.2 What 6D Reads, and When

6D reads the active policy through 6C's own existing internal contract — `GET /api/internal/v1/organizations/{organization_id}/compliance-policy` (6C §12.2, §15.42), or, for the in-process hot-path case, the identical Redis cache key 6C already establishes and invalidates (`compliance_policy:{organization_id}`, 5B §31, invalidated synchronously by 6C's own activation endpoint, §12.2). 6D does **not** invent a second read path or a second cache key.

**When:** exactly once per outbound call, at `POST /calls` (§10.5) — never per turn, never per audio frame. This satisfies the governing task's explicit requirement ("keep compliance lookup out of per-token/per-audio-frame hot loops... perform gating at the appropriate call/operation boundary") precisely because call initiation, not the turn loop, is the correct boundary: `CompliancePolicy.RecordingPolicy` is read once to set `Recording.recording_policy`'s immutable snapshot (§16.1); `CompliancePolicy.AllowedCallingWindows` is intersected with the Agent's `CallingHours` at the same moment as the `CallingWindowEnforced` policy check (§10.5) — both are one Redis read (or DB fallback on cache miss), not a live HTTP call to 6C's endpoint on every single outbound call (the internal endpoint exists for the cold-cache/cross-process case; the warm path is the shared Redis cache both 6C and 6D read from identically).

### 20.3 Fail-Closed

Per the governing task's explicit instruction: if the compliance-policy read fails (cache miss **and** DB unreachable, or no `ACTIVE` policy row exists for the org at all — an org that has never activated one, 6C §12.2's default-seeding flow not yet having completed asynchronously), `POST /calls` for an **outbound** call fails closed with `422 VALIDATION_ERROR` / `error.code = DEPENDENCY_UNAVAILABLE` as appropriate to the failure mode — it never silently proceeds with an assumed-permissive default. Inbound calls are unaffected (compliance gating in this document applies to outbound-call *initiation* only, matching 4I §7.2's own framing of `CompliancePolicy` as governing "outbound-call consent/recording/calling-window rules").

### 20.4 Never Relies on the Non-Authoritative Pointer

Per the governing task's explicit instruction and 6C §12.2's own binding rule: 6D's compliance read **always** resolves against `organization.compliance_policies.status = 'ACTIVE'` (via the cache key or internal endpoint, both of which 6C itself defines this way) — never against `organizations.compliance_policy_id`, which 6C explicitly documents as "non-authoritative convenience data only... no read or enforcement path may ever depend on pointer freshness." 6D's compliance gate is therefore correct even during any period where 6C's async pointer-update consumer (§12.2 there) is degraded or delayed.

---

## 21. Voice Turn Latency Architecture — ≤750ms Target

### 21.1 Exact Metric Definition

```
metric name:   voice_turn_response_latency_ms  (§32)

START:  the platform determines the caller has finished the current utterance
        / the endpoint (VAD) is committed

END:    the caller starts receiving the first audible audio bytes of the
        agent's response

This is caller-perceived, end-of-user-turn → first-agent-audio-delivered-
toward-the-caller. It is NOT: REST request latency, LLM full-completion
latency, first-text-token-only, TTS generation-completion, or server-side-
only processing time.
```

### 21.2 Upstream Requirements — Reconciled, Not Contradicted

| Source | Number | Status |
|---|---|---|
| SRS `NFR-PERF-001` | Voice end-to-end p50 **<800ms**, "where provider chain allows" | Frozen ceiling |
| 6A §11 / 3B §21 | ~725ms p50, no-tool full turn | Frozen **reference design budget** — 3B §21 itself: "proposed, not previously approved"; 6A §11 adopted it "as the binding Tier E reference since no superseding number exists" |
| **6D (this document)** | **≤750ms p50, no-tool conversational turn** | **New, stricter engineering target**, layered on top of the above two — not a replacement, not a contradiction |

**The relationship, stated exactly as the governing task requires:**

```
~725ms reference design budget   <   ≤750ms 6D engineering target   <   <800ms frozen SRS ceiling
        (3B §21 / 6A §11)                  (this document)                  (NFR-PERF-001)
```

The existing ~725ms figure already satisfies a ≤750ms target with a small, honestly-labeled margin. 6D does not lower any individual stage's number to manufacture a smaller total, and does not fabricate an optimization. The ~25ms of headroom between 725ms and 750ms is treated as **engineering margin for real-world variance**, not as guaranteed, bankable slack — §21.9 states exactly what can and cannot consume it.

### 21.3 Reference Stage Budget (reproduced from 3B §21 / 6A §11, unmodified)

| Stage | p50 | p95 | Classification |
|---|---:|---:|---|
| Network: caller → telephony → gateway | 50ms | 120ms | **OUTSIDE-PLATFORM-CONTROL** |
| VAD / endpoint detection | 150ms | 300ms | **PLATFORM-CONTROLLED** (tunable per agent) |
| STT finalization (post-endpoint) | 100ms | 200ms | **PROVIDER-DEPENDENT** (Deepgram primary) |
| Model Router selection | <5ms | <10ms | **PLATFORM-CONTROLLED** (pure in-memory scoring, §15.4) |
| LLM time-to-first-token | 250ms | 500ms | **PROVIDER-DEPENDENT** (largest variable, 7 adapters, 3B §10.4) |
| TTS time-to-first-audio-byte | 120ms | 250ms | **PROVIDER-DEPENDENT** (ElevenLabs primary) |
| Network: gateway → telephony → caller | 50ms | 120ms | **OUTSIDE-PLATFORM-CONTROL** |
| **TOTAL (no tool call)** | **~725ms** | **~1500ms** | — |

**Tool execution (150ms p50 / 400ms p95, only if invoked) is additive and excluded from the 725ms no-tool total** — exactly as 6A §11's own table already structures it ("Tier E — Realtime (voice WS turn, agent events) — 725ms (full turn, no tool call)"). §21.6 treats tool-assisted turns separately, per the governing task's explicit instruction.

**Honest classification, restated:** ~725ms is a **TARGET** design budget. No number in this table is **MEASURED** — no benchmark artifact exists anywhere in this repository proving any of these figures against a live provider integration (verified: no `phase-23`/`phase-24` testing/production directories exist yet; 3B §23 lists "validate the per-stage latency budget against real provider benchmarks" as an explicit open item for Phase 23/24). §21.10 names the benchmark plan that will eventually produce MEASURED numbers.

### 21.4 Critical Path Diagram

```
Caller audio ──► [Telephony/Gateway network: 50ms, OUTSIDE-PLATFORM] ──► Voice Gateway WS ingress
                                                                                │
                                                                                ▼
                                                          [VAD/endpoint detection: 150ms, PLATFORM]
                                                                                │
                                                                                ▼
                                                    [STT streaming + finalization: 100ms, PROVIDER]
                                                    (partials streamed continuously BEFORE this point —
                                                     only the finalization step counts toward the budget)
                                                                                │
                                                                                ▼
                                                    [Model Router selection: <5ms, PLATFORM — pure,
                                                     in-memory, Redis-cached health data, no network call]
                                                                                │
                                                                                ▼
                                            [LLM streaming completion, TTFT: 250ms, PROVIDER]
                                            (generation CONTINUES streaming after first token —
                                             the budget only measures time-to-FIRST-token)
                                                                                │
                                          ┌─────────────────────────────────────┘
                                          │ first usable text chunk/sentence fragment
                                          ▼
                                [Sentence/clause splitter, in-process, ~0ms — 3B §12]
                                          │
                                          ▼
                            [TTS streaming synthesis, TTFA: 120ms, PROVIDER]
                            (started on the FIRST usable text chunk, not the full LLM response —
                             §21.5 rule 2/3)
                                          │
                                          ▼
                    [Telephony/Gateway network out: 50ms, OUTSIDE-PLATFORM] ──► Caller hears agent
                                          │
                              ═══ voice_turn_response_latency_ms ends here ═══
```

### 21.5 Streaming Rules (binding on the API/runtime design, restated from 3B, enforced here as an API-design constraint)

1. **End-to-end streaming, always:** telephony audio → streaming STT → streaming LLM → streaming TTS → telephony audio (3B §12) — 6D's REST/WS contracts never introduce a batch/buffered hop into this chain. No 6D endpoint exists that could tempt an implementation to "wait for the full result, then respond" on this path — the only REST endpoints touching Voice's hot-path resources are Tier A reads that happen entirely outside the turn loop (§7.1).
2. **Never wait for full LLM completion before starting TTS** — TTS begins on the first usable sentence/clause fragment (3B §12's `SentenceSplitter`), while the LLM task continues generating the rest of the response concurrently (3B §12.1's per-turn sequence diagram).
3. **Feed usable LLM chunks to TTS as soon as safely supported** — bounded by whatever chunking granularity the selected TTS adapter's streaming API actually accepts; 6D's Model Router/provider-selection design (§15) does not penalize a provider for finer-grained streaming support, since finer granularity only helps this rule.
4. **Partial STT stays hot-path/transient state** — never written to PostgreSQL (5C §5.10/§11.4, §12.3, §17.2) — this is a repeated, load-bearing constraint restated across §12/§13/§17/§21 because it is the single largest volume-reduction decision protecting the database from ever being on this path (5C §10.2's own volume estimate: ~150 segments/call × 1M calls/day if *every* partial were persisted — finals-only cuts this to the actual utterance count).

### 21.6 Tool-Assisted Turns — a Genuinely Different Metric, Not a Weakened ≤750ms

**Two distinct, separately-measured metrics, per the governing task's explicit instruction — never blended into one number:**

| Turn type | Metric | Target |
|---|---|---|
| **No-tool conversational turn** | `voice_turn_response_latency_ms` (§21.1) | **p50 ≤750ms** |
| **Tool-assisted turn** | `voice_turn_response_latency_ms` for the *pre-tool-call* portion (unchanged — the LLM's decision to invoke a tool is itself a first-token-class event) **+** a separately-tracked `tool_execution_duration_ms` (already a first-class column, `voice.tool_executions`, 5C §5.7) | Tool latency is **additive, provider/tool-dependent, and separately measured** — the ≤750ms target does **not** claim the entire tool-execution-plus-final-answer sequence completes within 750ms |

**Latency-preserving contract for the caller during a tool-assisted turn (per the governing task's explicit request for a strategy, using only approved architecture):**

- **Bounded tool execution timeout:** `ToolDefinition.TimeoutMs` (100–30000ms, 5C §5.6 CHECK constraint) — already a first-class, per-tool-configurable value; 3B §13 confirms `execute()` is wrapped with this bound.
- **Interim conversational acknowledgement:** 4B's `DirectiveKind` enum already includes `WAIT` (4B §6, alongside `SPEAK | TRANSFER | END_CALL | TOOL_CALL`) — an Agent's prompt/workflow design (Prompt Management/Workflow Engine, 6E+ territory, consumed via `PromptRenderPort`/`WorkflowExecutionPort`) may direct the LLM to speak a short filler ("let me check that for you") before the tool call resolves. 6D's contribution is only to confirm the domain model already has the vocabulary for this pattern — 6D does not itself design the filler-selection logic, which belongs to Prompt/Workflow.
- **Tool progress/runtime event:** `tool_execution.started` (WS, §29) fires the moment execution begins, letting an observer (and, transitively, the caller-facing UX built on top of the Agent's own directive logic) know work is in progress rather than inferring silence as a failure.
- **Graceful tool timeout back into the LLM:** 4B §7.4's state machine (`RUNNING → TIMED_OUT → RUNNING [retry] → FAILED`) already routes a timeout back to the LLM as a tool-failure result the LLM can respond to gracefully (3B §13: "the orchestrator handles [a timeout] by informing the LLM the tool failed... rather than hanging the call") — this is existing, frozen runtime behavior 6D's API surface makes observable (`GET .../tool-executions/{id}` shows `TIMED_OUT`/`FAILED` with `attempt_count`), not a new mechanism.
- **Never indefinite silence:** the combination of a bounded per-tool timeout (hard ceiling: 30s) and the graceful-failure-back-to-LLM path structurally guarantees the caller is never left waiting past `TimeoutMs × (MaxRetriesOnTimeout + 1)` (5C §5.6: retries capped 0–2) before the LLM produces *some* spoken response, even if that response is "I wasn't able to look that up right now."

### 21.7 Barge-In Impact on the Latency Target

Barge-in (§14) truncates a turn already in `SPEAKING` state — it does not add latency to the ≤750ms metric for the *interrupted* turn (that turn's audio delivery already started, satisfying its own `voice_turn_response_latency_ms` measurement at the moment first audio played). The *new* turn that begins after barge-in (the caller's fresh utterance) is measured identically to any other turn, starting fresh from its own end-of-utterance moment (§21.1) — barge-in does not carry over or discount any latency budget from the turn it interrupted.

### 21.8 Provider-Failover Impact on the Latency Target

Per 3B §19–20 (reused, not modified): STT failover is 1 immediate retry then a hot-swap to the fallback provider (brief transcription gap, logged as a latency anomaly, turn continues — 4B §18.5); LLM failover is 1 same-provider retry then Model Router re-selection (no second full retry cycle — 3B §19's own reasoning: "the 800ms budget can't absorb multiple full retry cycles"). **A turn that experiences failover is expected to exceed the p50 target** — this is why the reference budget also carries a p95 figure (~1500ms) explicitly wider than 2× the p50, absorbing exactly this class of event. Failover turns are not excluded from the `voice_turn_response_latency_ms` metric (§32) — they are what pushes the metric's tail, which is precisely why per-stage, per-provider observability (§32) exists: to distinguish "the p50 regressed" from "failover rate increased," which require different operational responses.

### 21.9 Degraded-Mode Behavior

| Condition | Behavior |
|---|---|
| All providers in a category `CircuitState = OPEN` | `AllProvidersUnavailableError` (3B §22) → the Call transitions to `FAILED` (4B §24 risk table: "no LLM/STT/TTS available... Call transitions to FAILED; alert fires") — the platform does not attempt a degraded partial-functionality mode (e.g., DTMF-only fallback) that is not designed anywhere in Phase 1–5; inventing one here would exceed this document's authority |
| One provider degraded, others healthy | Model Router excludes the degraded/open-circuit provider from candidate scoring (3B §11) — the turn proceeds on a fallback provider, subject to §21.8's expected p50 impact |
| The ~25ms margin (750ms target vs. 725ms reference budget) | Treated as **engineering margin only** — it may absorb small, real per-turn jitter (e.g., Model Router selection running 8ms instead of 5ms) but is **never** counted as bankable headroom for a new, additive hot-path operation. §21.11 names the operations forbidden from consuming it. |

### 21.10 Benchmark Plan for Phase 23/24 (explicitly deferred — this document designs the plan, not the result)

1. **Instrument first:** every stage in §21.3's table becomes a span (§32) before any load test is run — `voice_turn_response_latency_ms` and its per-stage children must be observable in a real deployment before a number can be claimed as MEASURED.
2. **Per-provider matrix:** benchmark each STT/LLM/TTS adapter combination independently (7 LLM adapters × Deepgram/Gladia × ElevenLabs, 3B §10) — a blended average across providers would hide the "which provider choice actually drives the p50" signal the Model Router needs to be tuned against (3B §11's own stated revisit trigger).
3. **Language-specific pass:** Tamil/code-switching turns benchmarked separately from English-only turns (4I §4.4's Tamil-First Language Evaluation Framework already exists for STT/TTS/LLM capability scoring — Phase 23/24 reuses that framework's evaluation-set methodology for latency, not just accuracy).
4. **Cold vs. warm:** first-turn-of-call latency (provider connections freshly established, per §22's connection-reuse rules) benchmarked separately from steady-state mid-call turns.
5. **Load/concurrency:** the p50/p95 figures must hold under `NFR-SCALE-001`'s "tens of thousands of concurrent calls" condition, not only in isolation — this is where the Redis-shared circuit-breaker/health design (3B §16) either proves itself or reveals a bottleneck.
6. **Output:** a MEASURED figure replaces the TARGET figure in a future revision of this document (or a dedicated Phase 23/24 report this document does not preempt) — 6D does not claim this outcome in advance.

### 21.11 Operations Explicitly Forbidden on the Critical Path

Restated, consolidated, and made binding across every section of this document (source: 4B §16.3, 3B §7/§12, 6A §35/§36):

- No synchronous write to Analytics, CRM, Billing/Usage aggregation, or Campaign on the voice-turn hot path (all are async/event-driven, §24).
- No synchronous post-call summarization, sentiment computation, or recording finalization inline with a turn (4B §18.6 — Celery, post-`call.ended` only).
- No synchronous audit/compliance query inline with a turn — compliance is read once per call, at initiation (§20.2), never per turn.
- No live provider health probe inline with a turn (§15.4) — health is Redis-cached, refreshed by a periodic background worker.
- No per-turn database write beyond the Turn checkpoint itself (§12.2) and the append-only final-transcript-segment insert (§17.2) — both are the coarsest granularity that still bounds data loss to at most one in-flight turn (3B §7).
- No REST request/response cycle anywhere in the STT→LLM→TTS chain — that chain is exclusively in-process `asyncio` tasks connected by `asyncio.Queue` (3B §12), never an HTTP call to any 6D-designed endpoint.
- No per-turn reconnect to a provider — connections are reused/pooled per call (§22).

### 21.12 Observability Metrics for This Target

Full detail in §32; the primary SLO metric is named here to close this section: `voice_turn_response_latency_ms` (histogram), measured exactly per §21.1, with bounded-cardinality labels only (`organization_id` excluded from the metric label set — high-cardinality identifiers go to trace/log correlation, §32) — never claimed as MEASURED in this document, only defined and targeted.

### 21.13 TARGET ≠ MEASURED — Final Restatement

Every number in §21.2–§21.9 is a design **TARGET**. Zero numbers in this document are **MEASURED** — no load test, no live provider benchmark, no production trace exists in this repository to substantiate any of them as measured fact. This distinction is binding on every future revision of this document: a number may move from TARGET to MEASURED only when a Phase 23/24 benchmark artifact is cited by name.

---

## 22. Caching / Hot-Path State

| Cache key | Contents | TTL | Written by | Read on hot path? |
|---|---|---|---|---|
| `session:{tenant_id}:{call_id}` | Current Call/Turn state, in-flight buffer, agent config snapshot (3B §7) | Call duration + 5min grace | Voice Gateway | Yes — the primary hot-tier |
| `agent_version:{version_id}:snapshot` | `AgentVersion.snapshot_json`, immutable | 1h | On publish / cache-miss reload | Yes — read once per call at `CallRoutingService.resolve()` (in-process, §6 row 3), never re-read mid-call |
| `conversation:{session_id}:state` | Current in-flight Turn (partial STT, etc.) | Call duration | Voice Orchestrator, continuously | Yes |
| `provider_health:{provider_id}` | `HealthState`, `P50LatencyMs`, `CircuitState` | 60s buckets | Periodic Celery health-polling worker (3B §18.2) | Yes — read-only, never written inline (§15.4) |
| `provider_config:{org_id}:{category}` | Ordered `ProviderConfig` candidate list | 5min | Admin API / on config change | Yes |
| `compliance_policy:{organization_id}` | Active `CompliancePolicy` fields 6D needs (§20) | Per 6C §12/5B §31 | 6C's activation endpoint (write-then-invalidate) | Once per call, at initiation only (§20.2) — never per turn |
| `localization:{org_id}` | Org localization subset (6C-owned) | 15min | 6C | Not read by 6D directly — Voice reads Agent-level `VoiceConfig.Language`, not org localization, for turn-level language decisions |

**Connection reuse / prewarming rule (governing-task-required):** per-call provider sessions (an open STT streaming connection, an LLM request context) are established **once per call**, not per turn — 3B §7/§12's design keeps the STT/LLM/TTS pipeline's provider connections alive for the call's duration inside the same in-process `asyncio` task group; §21.11 already forbids per-turn reconnect. 6D's API design reinforces this by never exposing a REST endpoint that could plausibly be mistaken for a "per-turn provider handshake" — no such endpoint exists in this document's inventory (§28).

**Cache rule, restated:** every cache key above is tenant-namespaced except `provider_health:*` and the platform-default portion of `provider_config:*` (mixed-scope, matching 5C §11.3's RLS pattern) — consistent with 6A §36's prohibition on cross-tenant cache keys.

---

## 23. Transaction Boundaries

### 23.1 The Governing Rule (6A §35, unmodified, reused verbatim)

Never hold a DB transaction open while waiting on an AI provider, telephony provider, webhook delivery, or external HTTP call. Standard shape: validate (no I/O) → short DB transaction (single aggregate, or an approved exception below) → commit → async/external processing outside the transaction.

### 23.2 Which of 6A §35's Named Exceptions 6D Actually Uses

| 6A §35 approved exception | Used by 6D? | Where |
|---|---|---|
| Create Organization + owner Membership | No | 6C-owned |
| **Start Call + Conversation** | **Yes** | The internal `StartConversation` handler (triggered by the provider's answer webhook, §10.4 — **not** a tenant-invoked REST endpoint) writes `call_sessions.conversation_id` and creates the `conversations` row in one transaction, per 4B §5.1's own transaction-boundary note ("the `StartConversation` command sets `ConversationRef`... the Conversation aggregate is saved in the same Unit of Work"). No 6D-designed public endpoint itself performs this transaction — it is internal-runtime behavior this document classifies, not a new REST contract. |
| Transfer Ownership (two Memberships) | No | 6C-owned, unrelated |
| **Publish Agent + AgentVersion** | **Yes** | `POST /agents/{id}/publish` (§9.2) — the one 6D-designed **public REST endpoint** that performs a same-transaction, cross-aggregate write, exactly matching this named exception |
| Publish Workflow + WorkflowVersion | No | 6E+ (Workflow) |
| CSV import batch | No | Unrelated |

**No new exception is added by 6D.** Every other cross-aggregate effect in Voice — Call→Recording, Call→Transcript, Conversation→ToolExecution, Call/Conversation→CRM/Billing/Analytics/Campaign — is asynchronous and event-driven (§24), per 6A §35's closing rule: "every other cross-aggregate effect is eventual, event-driven... an API endpoint's synchronous response must never wait for these downstream effects to complete."

### 23.3 Per-Endpoint Transaction Shape (the two showcase cases)

**`POST /calls` (§10.2):** one transaction, one aggregate (`call_sessions` INSERT, status=`INITIATED`) — `TelephonyPort.place_call()` happens **after** commit, outside the transaction, exactly as 6A §35's standard shape requires. This is not one of the named exceptions — it is the default single-aggregate case.

**`POST /calls/{id}/terminate`/`transfer`/`hold`/`resume` (§11.2):** one transaction, one aggregate, one CAS `UPDATE` — `TelephonyPort.hangup()/transfer()/hold()/resume()` happens after commit, outside the transaction. The provider's own confirmation arrives later via webhook (§10.4), triggering a **second**, independent single-aggregate transaction (the follow-up status update) — never held open waiting for it.

### 23.4 Call-Start Transaction Boundary, Precisely

```
REQUEST TRANSACTION (POST /calls, Tier B):
  BEGIN
    INSERT voice.call_sessions (status='INITIATED', ...)
    SELECT audit.fn_insert_audit_event(p_action_kind => 'CALL_INITIATED', ...)  -- §24.0, durable
                                                                                   -- audit — the sole
                                                                                   -- legal write path
                                                                                   -- (5J §5/§14.2);
                                                                                   -- never a direct
                                                                                   -- INSERT
    INSERT audit.domain_event_outbox (event_type='call.initiated', ...)  -- §24.0, separate, cross-context
  COMMIT
  ↓ (outside the transaction)
  TelephonyPort.place_call() — async, may fail/retry per §21's retry table (6A §21)

[later, async, on provider answer webhook — the "Start Call + Conversation" exception]:
INTERNAL TRANSACTION (not a 6D REST endpoint — the provider-callback handler):
  BEGIN
    UPDATE voice.call_sessions SET status='ANSWERED', answered_at=NOW()
    INSERT voice.conversations (call_id=..., status='ACTIVE', ...)
    UPDATE voice.call_sessions SET conversation_id=<new conversation id>
    INSERT audit.domain_event_outbox (event_type='call.conversation_started', ...)
  COMMIT
  -- No audit.audit_events row here: this transition is provider-webhook-driven, not
  -- tenant-REST-triggered (§10.4) — its durable record is webhooks.inbound_webhook_events
  -- (5I §10), per 6A §28.2's mechanism split, not audit.audit_events (§24.0 amendment note).
```

---

## 24. Domain Events / Outbox

### 24.0 The Durable Audit Trail — `audit.fn_insert_audit_event()`, Never a Direct INSERT (corrected this pass — Task I, revised again this pass)

**The gap this subsection closes (revised):** the first draft's §24.1 table only ever described `audit.domain_event_outbox` as "the" durable mechanism, with no row for `audit.audit_events` at all — that was corrected in an earlier pass. **That earlier correction itself contained a fresh error, fixed here:** it described the audit write as a plain `INSERT INTO audit.audit_events (...)`. **5J §5/§14.2 make this illegal at the database layer** — `REVOKE ALL ON audit.audit_events FROM app_api, app_worker, app_readonly, app_platform_admin` (5J, migration `072_5J.sql`) means **no application role holds any INSERT privilege on this table at all**, under any circumstance. The **only** permitted write path is the `SECURITY DEFINER` function `audit.fn_insert_audit_event(...)`, which performs the tenant/platform-event authorization check itself (via `session_user`, unspoofable by the function's own privilege elevation) before it will insert anything. Every place in this document that previously read `INSERT INTO audit.audit_events` or `audit.audit_events (INSERT ...)` is corrected below to `SELECT audit.fn_insert_audit_event(...)` — no exceptions, no direct-INSERT phrasing survives anywhere in §28.

**The actual, corrected picture — binding for every state-changing endpoint in this document:**

```
BEGIN

  <domain mutation>                                  -- e.g. UPDATE voice.call_sessions ...

  SELECT audit.fn_insert_audit_event(                 -- (1) THE DURABLE AUDIT TRAIL —
    p_organization_id   => <tenant id>,               --     the ONLY legal write path (5J §14.2);
    p_actor_type        => 'USER'|'API_KEY'|...,       --     synchronous, same transaction,
    p_actor_ref         => <actor id, nullable>,       --     authoritative for 6A §22 compliance,
    p_actor_name        => <display name/key prefix>,  --     does not depend on Redis/outbox/consumers.
    p_action_kind       => '<governed 5J §14.3 value>', --    A raised exception here (e.g. tenant
    p_resource_type     => '<voice resource>',         --     mismatch) aborts the WHOLE transaction —
    p_resource_id       => <resource id>,              --     the domain mutation above is rolled back
    p_outcome           => 'SUCCESS',                  --     too, since both live in one BEGIN/COMMIT.
    p_failure_reason    => NULL,
    p_ip_address        => <request ip>,
    p_user_agent        => <request user agent>,
    p_session_id        => <session id>,
    p_request_id        => <request id, 6A §25 correlation>,
    p_correlation_id    => <call/conversation correlation id>,
    p_resource_snapshot => <5B §30 allow-listed snapshot fields>,
    p_is_platform_event => FALSE                       --     always FALSE for 6D — every Voice audit
  );                                                    --     event is tenant-scoped, never platform-scoped

  INSERT INTO audit.domain_event_outbox (              -- (2) OPTIONAL — only where a cross-context
    event_type = <domain event>,                       --     durable event is genuinely needed
    ...                                                 --     (§24.2's selective routing table).
  )                                                     --     Unlike (1), app_api/app_worker DO hold
                                                          --     ordinary INSERT on this table (5J/077) —
                                                          --     a plain INSERT is correct here, not a
                                                          --     function call.

COMMIT

-- Only AFTER commit, asynchronously, for row (2) only:
outbox → Redis Streams → future consumers (§24.2, at-least-once, idempotent)
```

**Binding rules, stated once, applied to every endpoint in §28:**

1. `audit.fn_insert_audit_event(...)` is **the sole legal write path** to `audit.audit_events` — 6D never instructs a direct `INSERT INTO audit.audit_events`, because no application role is granted that privilege (5J §5/§14.2, `REVOKE ALL`). It is invoked synchronously, in the same transaction as the domain mutation, for **every** state-changing endpoint this document defines — independent of whether that endpoint also happens to emit an outbox event.
2. Because the function is `SECURITY DEFINER` and runs inside the same transaction, **its failure (e.g., a raised exception on tenant mismatch) aborts the entire transaction** — the domain mutation it accompanies rolls back too. Audit is not a best-effort side note; it is a genuine co-requirement of the mutation succeeding at all, exactly as 5J §14.2's own design intends ("for synchronous audit categories, this correctly aborts the triggering action, since an unauditable security-critical action must not silently succeed").
3. `audit.domain_event_outbox` is a **separate, additional** write — an ordinary `INSERT` (application roles *do* hold that privilege, per migration `077_5J1.sql`) — used **only** where a cross-bounded-context consumer genuinely needs to learn about the change (§24.2). It is never a substitute for, and never a precondition for, the `fn_insert_audit_event()` call above.
4. Audit correctness **must not depend on Redis or any downstream consumer's availability.** If Redis is down or a consumer is lagging, every §28 endpoint's `audit.audit_events` row (written via the function) is already durably committed in Postgres — only the (separate, optional) cross-context propagation via the outbox is affected, and only for the endpoints that route through it (§24.2).
5. Logs and metrics are **not** substitutes for either mechanism — restated from 6A §22, unchanged.
6. No schema change, no new function, and no change to `audit.fn_insert_audit_event()` itself is made or required by this correction — 6D consumes the function exactly as 5J already defines it (§5J §14.2's own DDL, unmodified).

Every endpoint contract in §28 that mentions an `action_kind` now names it as a `fn_insert_audit_event(...)` call (rule 1 above); where that endpoint *also* emits a domain event, its `Domain Event:` bullet remains a separate, clearly labeled line referring to rule 3.

### 24.1 Three Mechanisms, Not Conflated (6A §28.3, applied to Voice)

| Mechanism | Used for | Example |
|---|---|---|
| **Durable audit write** (`audit.fn_insert_audit_event(...)` writing to `audit.audit_events`, §24.0 — the authoritative 6A §22 mechanism, synchronous, same-transaction, every state-changing endpoint; **never** a direct `INSERT` — no application role holds that privilege, 5J §5/§14.2) | Recording *that a mutation happened, by whom, with what outcome* — the compliance/security audit trail itself | Every governed `action_kind` in §28 (`AGENT_CREATED`, `CALL_INITIATED`, `CALL_TERMINATED`, etc. — full list, §36) |
| **Request-transaction durable event** (`audit.domain_event_outbox`, migration `077_5J1.sql`, live-verified per 6C §27 DEP-6C-16) | State changes another bounded context must eventually, reliably learn about, where the originating write is itself a REST-triggered, single-aggregate transaction — a **separate** write from the row above, not a replacement for it | `agent.published`, `agent.deprecated`, `call.initiated` (from `POST /calls`), `call.terminated`/`transferred`/`held`/`resumed` (from the action endpoints, §11) |
| **Realtime WebSocket event** (§13/§29, no outbox involved — ephemeral, at-most-once, best-effort) | High-frequency, latency-sensitive, tenant-observable events that do not need cross-context durability | `turn.utterance_partial`, `turn.agent_response_delta`, `voice.barge_in_detected` |
| **Internal Redis Stream event** (via the outbox → `fn_claim_outbox_events()`/`fn_mark_outbox_published()` publisher path, or a lighter-weight internal pub/sub for non-durable-required signals) | Cross-context domain events not needed by a tenant-facing WS observer, consumed by CRM/Analytics/Billing/Campaign (6E+) | `conversation.turn_completed` (feeds Analytics/Billing token-usage projections), `conversation.qualification_set` (feeds CRM), `provider.failover_triggered` (internal only, §15.5) |
| **Future tenant webhook** (6A §28.1, 5I-owned — not designed by 6D) | Not used by any 6D-designed event today | None of the events below are currently webhook-eligible; a future Integrations-phase document may opt specific Voice events in |

### 24.2 What Goes Through the Outbox — Deliberately Selective

Per `077_5J1.sql`'s own header comment (verified directly, §5): the outbox table carries **no partitioning** and is sized for "a single unpartitioned table... a handful of event types," explicitly **not** designed for per-turn volume. 6D therefore routes only **call/agent/conversation-lifecycle-boundary** events through the outbox — never per-turn events.

**Corrected this pass (Issue 3):** the "Consumed by" column below previously listed `Audit` as a consumer for nearly every row. That is retracted — the authoritative audit record for every one of these mutations is **already** durably written, synchronously, via `audit.fn_insert_audit_event(...)` in the *originating* request transaction (§24.0), before the outbox row is even inserted. The outbox's job is exclusively **cross-bounded-context propagation** to consumers this document does not itself own — it is never what makes an event "audited," and listing `Audit` here would wrongly suggest audit durability runs through Redis/a consumer, which §24.0 explicitly forbids. Each row below now names only genuine cross-context consumers, or says so explicitly where none currently exists — no consumer is invented merely to fill the column, per this pass's own instruction.

| Outbox-routed event | Trigger | Consumed by |
|---|---|---|
| `agent.created`, `agent.config_updated`, `agent.published`, `agent.deprecated` | §8/§9 endpoints | None currently; durable event retained for a defined future integration (Analytics agent-lifecycle projections, 6E+) |
| `call.initiated` | `POST /calls` | Analytics (future), Campaign (future — lead-status correlation for campaign-originated calls) |
| `call.answered`, `call.conversation_started` | Provider webhook / internal `StartConversation` (§23.4) | CRM (future — call-history projection, per 4B §21's own event catalogue), Billing (future — start-of-metering signal) |
| `call.ended`, `call.failed`, `call.transferred`, `call.held`, `call.resumed` | §11 action endpoints / provider webhook | CRM, Campaign, Billing, Analytics (all future, 6E+ — matching 4B §11.2's own `call.ended`/`call.failed` consumer list: "CRM, Campaign, Billing, Analytics") |
| `recording.deleted` | §16 delete action | The recording-object cleanup worker (this document's own consumer, §16.3a) — reads `_internal_cleanup_ref` from the payload and performs the actual S3 object removal. **Not** Audit — `RECORDING_DELETED` is already durably recorded via `fn_insert_audit_event()` in the same transaction that produced this outbox row (§24.0), before the cleanup worker ever runs. |
| `tool_definition.*` (created/updated/deactivated) | §18.1 endpoints | None currently; durable event retained for a defined future integration (Analytics tool-usage projections, 6E+) |

**Never outbox-routed (Redis Streams direct, or WS-only, never both claimed as durable):** `conversation.turn_completed` (per-turn, high frequency — 4B §11.3 itself already documents this must go straight to consumers, not through a durability-guaranteeing outbox sized for "a handful of event types"), `transcript.segment_added` (4B §11.7: "internal — high frequency, not published to event bus" at all, in the domain's own words), `tool_execution.*` (internal Redis Streams only — observability is via REST polling of §18.2's read endpoints, not event durability guarantees).

### 24.3 Delivery Semantics — Restated, Not Overclaimed

Per 6C §20/§27 DEP-6C-16's own language, reused verbatim: PostgreSQL domain transaction + outbox INSERT → COMMIT → Redis Streams → **at-least-once** consumer → idempotent handling. **Never exactly-once.** Every future consumer of a 6D-emitted outbox event (CRM, Billing, Analytics, Campaign — none of which this document designs) is required to be idempotent on `event_id`, exactly as 6C's own consumers are required to be (6C §7.7 point 4) — 6D does not relax this requirement for Voice events. **This at-least-once/never-exactly-once caveat applies only to the outbox → Redis Streams → consumer path (§24.1's second row) — it has no bearing on `audit.audit_events` (§24.0's first row), which is written via a single, synchronous, same-transaction `SELECT audit.fn_insert_audit_event(...)` call with no delivery-semantics question at all: it either commits with the domain mutation, or the whole transaction rolls back and neither happened.**

---

## 25. Authorization Matrix

Every row below states: endpoint, permission, actor eligibility, API-key eligibility, cross-tenant behavior (uniformly `404`, never `403`, per 6B/6C's non-disclosure discipline, restated once here rather than per row).

| Endpoint | Permission (5B, exact unless marked) | Actor | API key? | Internal service? |
|---|---|---|---|---|
| `POST /agents` | `agent:write` | USER | Yes | No |
| `GET /agents`, `GET /agents/{id}` | `agent:read` | USER, API_KEY | Yes | No |
| `PATCH /agents/{id}` | `agent:write` | USER | Yes | No |
| `POST /agents/{id}/publish` | `agent:publish` | USER | No — publish is a human-gated action, matching 5B's grant (`agent:publish` held by OWNER/ADMIN only, never the broader `agent:write` set) | No |
| `POST /agents/{id}/deprecate` | `agent:delete` *(interim reuse — DEP-6D-01 does not cover this; see ADR-6D-01)* | USER | No | No |
| `POST /agents/{id}/clone` | `agent:write` | USER | Yes | No |
| `GET /agents/{id}/versions[/{id}]` | `agent:read` | USER, API_KEY | Yes | No |
| `POST /calls` | `call:initiate` | USER, API_KEY | Yes | No |
| `GET /calls`, `GET /calls/{id}` | `call:read` | USER, API_KEY | Yes | No |
| `POST /calls/{id}/terminate` | `call:transfer` *(interim mapping — DEP-6D-01)* | USER, API_KEY | Yes | No |
| `POST /calls/{id}/transfer` | `call:transfer` (exact match) | USER, API_KEY | Yes | No |
| `POST /calls/{id}/hold` / `resume` | `call:transfer` *(interim mapping — DEP-6D-01)* | USER, API_KEY | Yes | No |
| `GET /conversations/{id}[/turns]` | `call:read` (conversation observation reuses the Call-family permission — no separate `conversation:*` permission exists or is needed, since Conversation is 1:1 with Call, §12.1) | USER, API_KEY | Yes | No |
| `GET /calls/{id}/recording`, `GET /recordings/{id}/download-url` | `recording:read` | USER, API_KEY | Yes | No |
| `POST /recordings/{id}/delete` | `recording:delete` | USER | No | No |
| `GET /conversations/{id}/transcript[/segments]` | `transcript:read` | USER, API_KEY | Yes | No |
| `GET /tools`, `GET /tools/{id}` | `agent:read` *(interim mapping — DEP-6D-02)* | USER, API_KEY | Yes | No |
| `POST /tools`, `PATCH /tools/{id}`, `POST /tools/{id}/deactivate` | `agent:write` *(interim mapping — DEP-6D-02)* | USER | Yes | No |
| `GET /conversations/{id}/tool-executions`, `GET /tool-executions/{id}` | `call:read` (adequate reuse — read-only observability adjacent to call/conversation data, no gap flagged) | USER, API_KEY | Yes | No |
| `GET /provider-health` | `agent:read` (adequate reuse — provider health informs agent model/voice configuration; read-only reference data, no gap flagged) | USER, API_KEY | Yes | No |
| `GET /phone-numbers[/{id}]` | `call:read` *(interim mapping — DEP-6D-03)* | USER, API_KEY | Yes | No |
| `POST /phone-numbers/{id}/assign-agent` | `agent:publish` *(interim mapping, retargeted this pass — DEP-6D-03, ADR-6D-08; **not** `agent:write`)* | USER | No | No |
| `GET /language-evaluations` | `agent:read` (adequate reuse — no gap; matches 5C §11.5's "read by all application roles" platform-reference-data posture) | USER, API_KEY | Yes | No |
| `GET /internal/v1/calls/{id}` | None (internal service JWT only, 6A §23.4/6B §17) | PLATFORM_ADMIN via internal service | No | Yes — central internal token issuer only |
| `GET /internal/v1/agents/{id}/versions/{id}` | Same as above | PLATFORM_ADMIN via internal service | No | Yes |
| `/ws/v1/voice/calls/{id}[/stream]` | `call:read`, re-verified on subscribe (§13.4) | USER only (no API-key WS auth, §13.2) | No | No |

**Cross-tenant behavior:** every row above returns `404 RESOURCE_NOT_FOUND` for a resource ID belonging to another tenant — never `403` (6B/6C's established discipline, reused without exception). **Break-glass:** no Voice-specific break-glass mechanism is designed here; the two internal endpoints (§28) are the only cross-tenant-capable surface, gated by the platform-admin-only internal service mechanism 6B §17/6A §23.4 already define — 6D introduces no new break-glass concept.

---

## 26. PII / Data Exposure Matrix

| Field / resource | PII class (5C §13, restated) | Exposed via | Never exposed via |
|---|---|---|---|
| `call_sessions.from_number`/`to_number`/`transfer_target` | `pii:phone` | `GET /calls[/{id}]` (masked in logs, per 6A §22's structlog PII-redaction processor — not masked in the authorized JSON response itself, since the caller of `call:read` is entitled to the number) | Never in Prometheus metric labels (§32) |
| `conversations.summary_text` | `pii:voice` | `GET /conversations/{id}` | Never in a webhook (no Voice event is webhook-eligible today, §24.1) |
| `turns.utterance_text`/`response_text` | `pii:voice` | `GET /conversations/{id}/turns` | Never in an audit `resource_snapshot` beyond 5B §30's documented allow-list |
| `transcript_segments.text` | `pii:voice` | `GET .../transcript/segments`, `turn.utterance_final`/`agent_response_final` (WS) | Never persisted twice (WS payload is ephemeral; REST reads the one durable copy, §17.2) |
| `recordings.storage_ref` | `pii:voice` (reference) | Never directly — only via `download-url`'s signed, 15-min-expiry URL (§16.2) | Never in any JSON field named `storage_ref`/`recording_url` directly — the response field is always `download_url`, generated fresh per request |
| `tenant_phone_numbers.phone_e164` | `pii:phone` | `GET /phone-numbers[/{id}]` | Masked in logs |
| `tool_executions.arguments`/`result` | Not classified `pii:*` in 5C, but may contain caller-supplied data indirectly (e.g., a `createLead` tool's arguments containing a name/phone) | `GET /tool-executions/{id}` (§18.3) — gated by `call:read`, the same bar as transcript access, since tool arguments are conversationally-derived data of comparable sensitivity | — |
| `provider_configs.credential_ref` | Secret reference | **Never** — not present in any 6D response model (§15.2 explicitly excludes it) | — |
| `agents.draft_config` (prompt_ref, workflow_ref, etc.) | Opaque references only, no raw prompt text stored in `voice.agents` itself | `GET /agents/{id}` | The actual prompt *text* lives in Prompt Management (6E+), not in any 6D response |

**Absolute prohibitions, restated (6A §22/§24.3):** no 6D response ever contains a raw `credential_ref` value, an encryption key, a token hash, or internal provider SDK credentials. No 6D error response ever contains SQL text, stack traces, or internal service/schema/function names.

---

## 27. Error Catalog

### 27.1 Reused From 6A/6B/6C, Unmodified

`VALIDATION_ERROR`, `AUTHENTICATION_REQUIRED`, `AUTHORIZATION_DENIED`, `RESOURCE_NOT_FOUND`, `STATE_CONFLICT` (used for every §11.2 guarded-transition 409, carrying `error.details.current_state`), `PRECONDITION_FAILED` (ETag mismatch on Agent draft-config PATCH, §28), `IDEMPOTENCY_KEY_REUSE_MISMATCH`, `RATE_LIMIT_EXCEEDED`, `PAYLOAD_TOO_LARGE`, `DEPENDENCY_UNAVAILABLE` (used for `AllProvidersUnavailableError`, §21.9, and for compliance-read failure, §20.3 — Category B reuse, not a new code), `INTERNAL_ERROR`.

### 27.2 New — Genuinely Voice-Specific (justified individually, none duplicating an existing family)

| Code | HTTP | Meaning | Why not an existing code |
|---|---|---|---|
| `AGENT_NOT_PUBLISHED` | 422 | `POST /calls` referenced an Agent with no `PUBLISHED` version (4B §9 policy `AgentMustBePublished`) | Distinct from `STATE_CONFLICT`, which describes the *target resource's own* guarded-transition failure; this is a precondition failure on a **referenced** resource at creation time — closer to a semantic validation failure than a state conflict on the Call being created (which does not yet exist) |
| `QUOTA_EXCEEDED` | 429 | `ConcurrentCallQuotaNotExceeded` policy violation (4B §9), or any future plan/quota-tier limit | Distinct from `RATE_LIMIT_EXCEEDED` (abuse-prevention rate limiting, 6A §20) — this is a **commercial plan/quota** limit, a materially different cause requiring a different tenant remediation (upgrade plan vs. slow down requests). Named generically (not `CALL_LIMIT_EXCEEDED`) so a future Billing/Usage phase can reuse it rather than mint a parallel code — flagged as a forward-compatibility naming choice, not a retroactive change to any frozen document. |
| `RECORDING_NOT_AVAILABLE` | 404 | `GET /recordings/{id}/download-url` called against a recording in `PENDING`/`FAILED`/`DELETED` status | A `GET` that cannot be fulfilled because the underlying object was never stored (or no longer is) is conventionally a 404-class outcome, not a 409 — no existing code communicates "this specific downloadable artifact isn't available," and `RESOURCE_NOT_FOUND` alone would conflate "the recording row doesn't exist" with "the recording row exists but has no downloadable audio," which are operationally different for a support/debugging audience |

**Explicitly not introduced (per the governing task's caution against inventing when an adequate code exists):** `CALL_STATE_CONFLICT` (covered by generic `STATE_CONFLICT`), `AGENT_VERSION_CONFLICT` (no scenario in this design produces one — publish always creates a new version, never collides), `TRANSFER_NOT_ALLOWED` (covered by generic `STATE_CONFLICT`, since `TransferOnlyOncePerCall` is a state-conflict on the Call's own status), `PROVIDER_UNAVAILABLE` (covered by the existing `DEPENDENCY_UNAVAILABLE`).

---

## 28. Endpoint Contract Inventory

### 28.0 Shared Template

Every endpoint instantiates 6A's `{data, meta}`/`{error}` envelope, error shape, and `request_id` propagation (6A §10/§24/§25) throughout. Every rate limit is a **configurable default**, not a benchmark; every latency figure is a **TARGET** (6A §11 tiers, §7.3). Tenant scope for every endpoint below is `organization_id` resolved from the caller's JWT/API-key (6B §9); a path `{id}` belonging to another tenant yields `404 RESOURCE_NOT_FOUND`, never `403` (§25). Three endpoints are given full depth as showcases (§28.5 publish, §28.10 initiate call, §28.13 terminate call); the remainder use the compact form 6C §15.2–§15.5 established.

### 28.1 `POST /api/v1/agents`

- **Purpose:** Create a new Agent in `DRAFT`. **Auth:** access token or API key. **Authz:** `agent:write`. **Actor:** USER, API_KEY.
- **Request:** `{ "name", "description"? }` — only top-level metadata; `draft_config` starts empty/default and is populated via `PATCH` (§28.4).
- **Response `201`:** full Agent resource (§8.1), `status: "DRAFT"`, `Location` header.
- **Errors:** `400/422` (name length, §8.1); no idempotency requirement stated as mandatory (creating a duplicate DRAFT agent has no dangerous real-world side effect, unlike a Call or Organization) — `Idempotency-Key` accepted but optional.
- **Latency:** Tier A. **DB:** single-row INSERT, `voice.agents`, plus a synchronous `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_CREATED', ...)` call in the same transaction (§24.0 — never a direct `INSERT INTO audit.audit_events`, which no application role is privileged to execute, 5J §5/§14.2). **Audit:** `AGENT_CREATED` (5J §14.3 ‡ — **exact match, Category A**). **Domain Event:** `agent.created` (outbox, §24.2, separate write).

### 28.2 `GET /api/v1/agents`

- **Purpose:** List agents. **Authz:** `agent:read`. **Query params:** `status` filter, cursor pagination (6A §14). **Response `200`:** paginated Agent summaries. **Latency:** Tier A. **Audit:** none (read). **Cache:** none (list freshness matters more than cache hit rate at this volume).

### 28.3 `GET /api/v1/agents/{agent_id}`

- **Purpose:** Get one agent. **Authz:** `agent:read`. **Response `200`:** full Agent resource incl. `draft_config`, `published_version_id`, `status`. `ETag` header (weak, `hash(id, updated_at)`, 6A ADR-6A-08). **Errors:** `404`. **Audit:** none.

### 28.4 `PATCH /api/v1/agents/{agent_id}`

- **Purpose:** Update draft-config fields (§8.2 allow-list). **Authz:** `agent:write`. **Headers:** `If-Match` (ETag, optional but recommended). **Request:** any subset of §8.2's typed fields; `extra="forbid"` rejects unknown fields incl. `status`/`published_version_id` (mass-assignment protection, 6A §22).
- **Validation:** per-field (§8.2); `tool_permissions[].tool_id` must resolve to a tenant-visible `voice.tool_definitions` row (`422` otherwise, `error.details.field: "tool_permissions"`).
- **Response `200`:** updated Agent. **Errors:** `400/422`, `403`, `404`, `412` (ETag mismatch). **Concurrency:** weak ETag (6A ADR-6A-08), matching 6C's pattern for non-state-machine free-form fields.
- **Audit:** `AGENT_CONFIG_UPDATED` (5J §14.3 ‡ — **exact match, Category A**), recorded via a synchronous `audit.fn_insert_audit_event(...)` call in the same transaction as the `voice.agents` UPDATE (§24.0 — never a direct `INSERT INTO audit.audit_events`). **Domain Event:** `agent.config_updated` (outbox, separate write). **Cache:** invalidates `agent_version:*` only indirectly (draft edits do not touch published snapshots — no cache invalidation needed for this endpoint).

### 28.5 `POST /api/v1/agents/{agent_id}/publish` — **Full depth (showcase)**

- **Purpose:** Snapshot the current `DraftConfig` into a new immutable `AgentVersion` and mark the Agent `PUBLISHED` (§9.2).
- **API surface:** Public. **Authentication:** Access token only — **no API key** (publish is a human-gated action; `agent:publish` is not part of any documented API-key-scopable default set, matching 6C's precedent of restricting certain lifecycle actions to session-bound credentials).
- **Authorization:** `agent:publish` (5B — OWNER/ADMIN only). **Actor:** USER. **Tenant Scope:** path `agent_id`, cross-checked.
- **Path Params:** `agent_id`. **Headers:** `Idempotency-Key` recommended (a retried publish should not create two versions from one intent) but not float-blocking — a retry with the same key returns the originally-cached `200`/version.
- **Request Schema:** empty body (the snapshot is taken from the Agent's *current* `draft_config` server-side, per 4B §12.3's `PublishAgent` command comment: "draft config snapshot is taken from `Agent.DraftConfig` at publish time — not passed in the command — ensures the exact saved draft is published").
- **Validation:** `agents.status` must be `DRAFT` or `PUBLISHED` (not `DEPRECATED` — 4B §7.3) → `409 STATE_CONFLICT` with `current_state` otherwise. **Every `tool_permissions[].tool_id` in the current draft is re-verified at publish time** to still resolve to a tenant-visible, `is_active=TRUE` `voice.tool_definitions` row (§9.2 step 2 — corrected this pass; a referenced custom tool may have been deactivated since the field was last edited, §9.2's T1/T2/T3 example) → `422` with the offending `tool_id` if not.
- **Response `201`:** `{ "data": { "version_id", "version_number", "published_at", "agent": {...updated Agent...} } }`.
- **Errors:** `403`, `404`, `409` (wrong Agent status, or concurrent-publish contention exhausted — §9.2a), `422` (dangling/inactive tool reference).
- **Rate Limit:** 30/hour/org (configurable default — publishing is infrequent by nature). **Idempotency:** recommended, not mandatory (see above). **Latency:** Tier B — one short, same-transaction, two-aggregate write (the one 6A §35-named exception this endpoint uses, §23.2); no external call.
- **Database:** `voice.agent_versions` (INSERT), `voice.agents` (UPDATE `status`, `published_version_id`), `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_PUBLISHED', ...)` (§24.0 — the sole legal audit write path, never a direct `INSERT INTO audit.audit_events`, 5J §5/§14.2), `audit.domain_event_outbox` (INSERT `agent.published`, a separate, ordinary INSERT — application roles do hold that privilege, unlike `audit.audit_events` — §24.0) — **all in one transaction**, per 6A §35's "Publish Agent + AgentVersion" named exception.
- **Cache:** `agent_version:{new_version_id}:snapshot` populated (write-through) so the very next call resolving this agent hits a warm cache rather than a cold DB read.
- **RLS:** standard tenant policy on both tables (5C §11.1).
- **Audit:** `AGENT_PUBLISHED` (5J §14.3 — **exact match, Category A**), synchronous, recorded via `audit.fn_insert_audit_event(...)` (§24.0) — a raised exception from the function aborts the whole transaction, including the version INSERT and status UPDATE above.
- **Domain Event:** `agent.published` (outbox → Redis Streams, at-least-once, §24).
- **Observability:** `agent_published_total` (no `organization_id` label — bounded-cardinality only, §32.1; per-tenant breakdown via trace/log correlation).
- **Side Effects:** none beyond the two-row write — no call is affected (§9.1).
- **Concurrency — corrected this pass (Task F):** two concurrent publishes on the same Agent both compute `version_number = MAX(version_number)+1` inside their own transaction; the loser's `INSERT` raises **SQLSTATE `23505` (`unique_violation`)** against `uq_av_version` (5C §7) under this endpoint's actual READ COMMITTED isolation — **not** a `40001` serialization failure, which only arises under `SERIALIZABLE`/`REPEATABLE READ` isolation, neither of which this design uses. The loser's handler follows §9.2a's bounded-retry algorithm (up to 3 attempts, recomputing `MAX(version_number)` each time) before surfacing `409 STATE_CONFLICT` (`error.details.reason: "concurrent_publish_contention"`) on exhaustion.
- **Security:** the empty request body is deliberate — a publish can never smuggle in draft-config values that didn't go through §28.4's own validation pipeline.

### 28.6 `POST /api/v1/agents/{agent_id}/deprecate`

- **Purpose:** `PUBLISHED → DEPRECATED` (§9.4). **Authz:** `agent:delete` (interim mapping, ADR-6D-01). **Guard:** current status must be `PUBLISHED` → `409 STATE_CONFLICT` otherwise. **Response `200`:** updated Agent. **Latency:** Tier B. **Audit:** `AGENT_DEPRECATED` (exact match, Category A, via `audit.fn_insert_audit_event(...)`, §24.0 — never a direct INSERT). **Domain Event:** `agent.deprecated` (outbox, separate write).

### 28.7 `POST /api/v1/agents/{agent_id}/clone`

- **Purpose:** Create a new `DRAFT` Agent copying `draft_config` from this agent (or a specified published version). **Authz:** `agent:write`. **Request:** `{ "source": "draft" | "published_version_id" }`. **Response `201`:** new Agent. **Audit:** `AGENT_CREATED` (5J §14.3 ‡ — **exact match, Category A**; the same value §28.1 uses — a clone is, from the audit trail's perspective, the creation of a new Agent row).

### 28.8 `GET /api/v1/agents/{agent_id}/versions`

- **Purpose:** List versions, newest first. **Authz:** `agent:read`. **Pagination:** cursor (6A §14). **Response fields:** `version_id`, `version_number`, `published_by`, `published_at` — **not** the full `snapshot_json` (kept for the detail endpoint, §28.9, to avoid an unnecessarily large list response, 6A §36).

### 28.9 `GET /api/v1/agents/{agent_id}/versions/{version_id}`

- **Purpose:** Get one version's full immutable snapshot, incl. `language_policy`. **Authz:** `agent:read`. **Response:** read-only — no `PATCH`/`PUT` exists for this resource by design (§8.4, 5C §11.6 trigger-enforced immutability).

### 28.10 `POST /api/v1/calls` — **Full depth (showcase)**

- **Purpose:** Initiate an outbound call — durably records intent, does not block on the callee answering (§10.2).
- **API surface:** Public. **Authentication:** access token or API key. **Authorization:** `call:initiate`. **Actor:** USER, API_KEY. **Tenant Scope:** resolved from JWT/API-key.
- **Headers:** `Idempotency-Key` **required** (a retried outbound-call request has a real-world consequence — dialing a phone twice).
- **Request Schema:** `{ "agent_id", "to_number" (E.164), "phone_number_id"? (required when the Agent has more than one eligible outbound number, §10.2a), "campaign_lead_ref"? }` — `from_number` is **always** resolved server-side, never client-supplied, per §10.2a's deterministic selection rule, to prevent a tenant spoofing an unowned caller-ID number.
- **Validation:** `to_number` E.164 format (`400`); `phone_number_id` resolution (§10.2a — `404` cross-tenant/nonexistent, `422` inactive/not-outbound-enabled/agent-mismatch, `422` "ambiguous" if omitted and more than one eligible number exists); `AgentMustBePublished` (`422 AGENT_NOT_PUBLISHED`); `ConcurrentCallQuotaNotExceeded` (`429 QUOTA_EXCEEDED`); `CallingWindowEnforced` for outbound (`422 VALIDATION_ERROR`, `details.policy: "CallingWindowEnforced"`); compliance gate (§20.3 — `422`/`503` as appropriate, fail-closed).
- **Response `201`:** `{ "data": { "call_id", "status": "INITIATED", "direction": "OUTBOUND", "agent_version_id", "to_number", "from_number", "started_at" } }` — `from_number` is the server-resolved value (§10.2a); an honest reflection of exactly what committed (§10.2); no field asserting the callee has been reached.
- **Errors:** `400`, `404` (`phone_number_id` cross-tenant/nonexistent), `422` (`AGENT_NOT_PUBLISHED`, calling-window, compliance, phone-number ineligibility/ambiguity), `429` (`QUOTA_EXCEEDED`), `503` (`DEPENDENCY_UNAVAILABLE` — compliance-read total failure).
- **Rate Limit:** governed by the existing real-time Usage & Quota `CheckQuota` port (4A #6, 6A §20's own stated rule for "cost-sensitive... outbound call initiation" — not a separate limiter).
- **Idempotency:** required, 24h TTL (6A §16.2). **Latency:** Tier B — durably recorded once the single-aggregate transaction commits; `TelephonyPort.place_call()` runs after, outside the transaction (§23.3).
- **Database:** `voice.call_sessions` (INSERT, `status='INITIATED'`), `SELECT audit.fn_insert_audit_event(p_action_kind => 'CALL_INITIATED', ...)` (§24.0 — sole legal audit write path, never a direct `INSERT INTO audit.audit_events`), `audit.domain_event_outbox` (INSERT `call.initiated`, a separate, ordinary INSERT, §24.0) — same transaction.
- **Cache:** none written; `provider_config`/`compliance_policy` reads are cache-hits on the warm path (§22).
- **RLS:** standard tenant policy (5C §11.1).
- **Audit:** `CALL_INITIATED` (5J §14.3 ‡ — **exact match, Category A**).
- **Domain Event:** `call.initiated` (outbox → Redis Streams, separate write).
- **Observability:** `calls_initiated_total{direction}` (no `organization_id` label — bounded-cardinality only, §32.1; per-tenant breakdown via trace/log correlation).
- **Side Effects:** `TelephonyPort.place_call()` dispatched post-commit; subsequent state changes arrive via provider webhook (§10.4) and the WS observation channel (§13).
- **Concurrency:** two concurrent `POST /calls` under the same `Idempotency-Key` → second returns the cached first response (6A §16.2); under different keys, both proceed independently and are separately subject to the quota check (no race between them beyond the quota check's own indexed-count read, which is not a hard serialization point — a documented, low-severity race where two near-simultaneous requests could both pass a quota check that a strictly serialized check would have rejected the second of; **DEP-6D-09**, §36, non-blocking, identical in nature to 6C's own disclosed, non-blocking concurrency residuals).
- **Security:** `from_number` is never client-suppliable — the client selects only an opaque `phone_number_id` (§10.2a), and the server resolves/returns the actual E.164 value; this is the specific structural control preventing caller-ID spoofing of a number the tenant does not own.

### 28.10a Controlled Amendment — Phase 6H Campaign Dispatch Idempotency (added 2026-08-28; extended same day with provider-dispatch durability; extended again same day with the provider-submission boundary, privilege hardening, and idempotency tenant/payload validation)

**This subsection is an additive amendment, not a rewrite of §28.10 above.** Every statement in §28.10 remains exactly as written and continues to govern `POST /api/v1/calls` unchanged. This subsection documents a *separate* contract for a caller `POST /api/v1/calls` never serves: Campaign's in-process invocation of the outbound-call use case (§6's row: "Campaign triggers outbound calls via an in-process module call ... not a 6D-owned HTTP endpoint").

**The gap this closes, across three passes:** §28.10's `Idempotency-Key` requirement is an HTTP-layer mechanism (6A §16.2) with no meaning for an in-process caller (pass 1: `voice.fn_initiate_outbound_call_idempotent()`). Refusing to ever re-invoke the provider once a key was claimed then risked permanently losing a call on a pre-submission crash (pass 2: the claim/confirm/ambiguous/failed protocol). A final adversarial freeze review then found the pass-2 design still permitted the opposite failure — **a worker that crashed *after* the provider had already received the request** would eventually have its lease expire and be re-claimed by another worker, which would call the provider again, physically dialing the same person twice. Pass 3 (this one) closes that P0 gap with a durable pre-network-call boundary, closes two direct-table-write privilege bypasses, and adds tenant/payload validation to replay. All three passes are described together below as the current, single contract — no prior wording describing a "claim, then never re-invoke" or "any expired lease is always safe to retry" rule still applies.

**Existing contract (unchanged):** the in-process port is `InitiateOutboundCallUseCase`, invoked directly by the Campaign Executor, bypassing the REST layer, tenant-JWT auth, and rate limiting entirely (it runs as a trusted in-process call within the same modular monolith, per 4H §9.1's boundary).

**Corrected/extended contract — four calls, not one:**

```
# Step 1 — reserve the logical call identity (idempotent; safe to retry any number of times)
InitiateOutboundCallUseCase(
    organization_id, agent_id, agent_version_id, phone_number_id, to_number,
    campaign_lead_ref,
    dispatch_idempotency_key: str,   # required for this in-process caller
) -> InitiateOutboundCallResult(call_session_id, session_started_at, is_new: bool, outcome: str)
    # outcome: 'CREATED' | 'REPLAYED' | 'IDEMPOTENCY_KEY_REUSE_MISMATCH'
    # a cross-tenant replay attempt raises a non-disclosing exception instead of returning a row

# Step 2 — claim exclusive ownership of PREPARING the provider network call
#          (does NOT yet authorize calling the provider — see Step 3)
ClaimDispatchForProviderSubmission(
    dispatch_idempotency_key, organization_id, worker_id: str, lease_seconds: int = 30,
) -> ClaimResult(claimed: bool, call_session_id, provider_request_ref: str, attempt_count: int, reason: str | None)

# Step 3 (only if claimed=True) — commit the durable "submission may now begin" boundary
#          BEFORE calling the provider. If began=False, DO NOT call the provider.
BeginProviderSubmission(dispatch_idempotency_key, organization_id, worker_id) -> BeginResult(began: bool, reason: str | None)

# Step 4 (only if began=True) — call TelephonyPort.place_call() OUTSIDE any transaction,
# using provider_request_ref from Step 2, then record exactly one of:
RecordDispatchConfirmed(dispatch_idempotency_key, organization_id, worker_id, provider_call_ref: str) -> bool
RecordDispatchFailed(dispatch_idempotency_key, organization_id, worker_id, error: str | None) -> bool     # definite rejection, pre-acceptance — safe to retry
RecordDispatchAmbiguous(dispatch_idempotency_key, organization_id, worker_id, error: str | None) -> bool  # outcome unknown — NEVER auto-retried

# Called asynchronously (e.g. from the provider status-callback handler), NOT by the
# original dispatching worker — resolves a row stuck in SUBMITTING or AMBIGUOUS once the
# caller has independently correlated an inbound callback (or a bounded operator/provider-
# lookup decision) to this dispatch_idempotency_key:
ReconcileDispatchOutcome(
    dispatch_idempotency_key, organization_id, outcome: 'CONFIRMED' | 'FAILED',
    reconciled_by: str, provider_call_ref: str | None = None, note: str | None = None,
) -> ReconcileResult(reconciled: bool, reason: str | None)
```

- **Idempotency + tenant/payload validation semantics (Step 1):** `dispatch_idempotency_key` is the caller's own domain identity (for Campaign: the exact same SHA-256 `campaign.call_jobs.idempotency_key` value already computed per DDR-4D-002 — passed through unchanged, never recomputed by Voice). Backed by `voice.fn_initiate_outbound_call_idempotent()` (`099_5C1.sql`) — a `PRIMARY KEY`-backed atomic claim (`voice.call_dispatch_keys`), because `voice.call_sessions` is itself `PARTITION BY RANGE (started_at)` and cannot carry a direct partition-key-free `UNIQUE` constraint on this key. The function now additionally computes a canonical SHA-256 `payload_fingerprint` from the actual immutable request fields on every call (never a caller-supplied value) and validates every replay against it: same key + same tenant + same fingerprint → `outcome='REPLAYED'` with the original `call_session_id`; same key + same tenant + a **different** fingerprint (destination/agent/tenant-number silently changed under an old key) → `outcome='IDEMPOTENCY_KEY_REUSE_MISMATCH'` (6A §16.2's existing global error semantic, reused here, not a new vocabulary) with **no session identity returned**; same key + a **different tenant** → a non-disclosing exception (this function is `SECURITY DEFINER` and bypasses RLS entirely, so this explicit check is the *entire* tenant-isolation guarantee for a replay, not defense-in-depth). **Live-proven on PostgreSQL 16** (the declared production baseline): all three outcomes, plus the original concurrency proof (a genuine two-connection concurrent call with the same key produces exactly one `call_sessions` row).
- **Provider-submission-preparation ownership semantics (Step 2):** `dispatch_state` moves `RESERVED`/`FAILED`/lease-expired-`CLAIMED` → `CLAIMED` only for the one caller whose claim succeeds — a concurrent second claim attempt for the same key is refused (`claimed=False`, `reason='NOT_CLAIMABLE_CLAIMED'`) while the lease is valid. **Critically, a lease-expired `SUBMITTING` row is never claimable through this function, under any condition** — see Step 3. **Live-proven:** two concurrent claims for the same `RESERVED` key produced exactly one claimant, under genuine overlapping connections, not simulated.
- **The durable submission boundary (Step 3, the P0 fix):** `BeginProviderSubmission` is the **only** way a row moves `CLAIMED → SUBMITTING`, and this transition **must** commit before the caller ever invokes `TelephonyPort.place_call()` — this is a mandatory sequencing rule, not an optional optimization. Once `SUBMITTING` is durably committed, the platform can no longer prove the provider was never contacted, so `ClaimDispatchForProviderSubmission` **never** re-claims a `SUBMITTING` row automatically, no matter how stale its lease becomes — closing the exact double-dial scenario a prior pass left open. If `began=False` (the caller's own lease already lapsed, or another worker has since claimed the row), the caller **must not** call the provider. **Live-proven, the critical assertion of this entire amendment:** a row claimed and moved to `SUBMITTING`, then abandoned (simulating a mid-flight crash), remained refused for reclaim (`NOT_CLAIMABLE_SUBMITTING`) even after its lease genuinely expired — verified on PostgreSQL 16, not merely PostgreSQL 18.
- **Outcome-recording semantics (Step 4):** `RecordDispatchConfirmed` requires a `provider_call_ref` and moves `SUBMITTING → CONFIRMED` (terminal). `RecordDispatchFailed` moves `CLAIMED → FAILED` (a local pre-submission abort) or `SUBMITTING → FAILED` (a **definite**, pre-acceptance provider rejection only) — safe to retry either way. `RecordDispatchAmbiguous` moves `SUBMITTING → AMBIGUOUS` for **any** outcome that cannot be determined (timeout, connection reset, unclear response) and is a **hard stop** — no function transitions `AMBIGUOUS` (or `SUBMITTING`) back to a claimable state automatically, ever. **Live-proven:** all three recorders exercised from `SUBMITTING`, including confirming the `AMBIGUOUS`/`FAILED` asymmetry is real (an `AMBIGUOUS` row rejects every reclaim attempt; a `FAILED` row is genuinely re-claimable).
- **Reconciliation semantics (new, closes the residual sliver):** `ReconcileDispatchOutcome` is deliberately **not** CAS-guarded on the original `worker_id` — the original worker/lease is presumed gone, which is precisely why the row is stuck. It resolves a `SUBMITTING` or `AMBIGUOUS` row to a definite `CONFIRMED`/`FAILED` outcome via identity correlation only (the caller — a provider status-callback handler, or a bounded operator/provider-lookup decision — has already matched the inbound signal to this `dispatch_idempotency_key`, e.g. via `provider_request_ref`). **Live-proven:** a stuck `SUBMITTING` row was resolved to `CONFIRMED`; a stuck `AMBIGUOUS` row was resolved to `FAILED` and was then genuinely re-claimable.
- **`provider_request_ref` (INV-VOICE-DISPATCH-06):** fixed, immutable, generated once at Step 1 and never regenerated on any retry — the same stable reference is available to propagate to the provider on every attempt, for whichever provider adapter is later confirmed to support echoing a caller reference back on callbacks. **Not verified for Exotel specifically** — this is a documented capability seam, not a claimed guarantee (see below).
- **Campaign caller behavior:** on Step 3's `began=True`, Campaign proceeds to `TelephonyPort.place_call()` **outside any transaction** (unchanged from §23.3's existing rule), using `provider_request_ref` from Step 2, then calls exactly one of the three Step-4 outcome recorders based on what actually happened. On `claimed=False` or `began=False`, Campaign **must not** call the provider.
- **Error behavior:** a validation failure inside Step 1 (invalid `agent_version_id`, inactive `phone_number_id`, etc.) raises exactly as it does for the REST path today (§28.10's `422`/`404` conditions) — unchanged by this amendment.
- **Privilege hardening (new, closes two direct-write bypasses):** no role — including `app_api`/`app_worker`, the two roles that actually call the functions above — holds direct `INSERT`/`UPDATE`/`DELETE` on `voice.call_dispatch_keys`. Every row and every state transition provably requires going through one of the eight functions listed above; a caller can no longer fabricate an arbitrary `dispatch_state` (including a forged `CONFIRMED` row) by writing to the table directly. **Live-proven:** direct `INSERT` as both `app_worker` and `app_api` fails with `permission denied`.
- **Backward compatibility:** none of this affects `POST /api/v1/calls`'s own HTTP `Idempotency-Key` mechanism (§28.10) — a human/API-key caller through the REST endpoint never supplies or sees any of these parameters. 6D's own implementation of `POST /calls` may, in a future revision, choose to route through the same primitives; this amendment does not mandate that today.
- **Why this does not invalidate the rest of frozen 6D:** purely additive to one internal port's contract that no tenant-facing surface in this document depends on; no existing endpoint, permission, DTO, error code, or state-machine transition in §1–§37 is altered. `voice.call_sessions`' own columns, constraints, and grants (`011_5C.sql`) remain completely untouched.

**What this explicitly does not and cannot solve, stated precisely rather than claimed away:** exactly-once **logical call identity** is fully platform-guaranteed (Step 1 + `payload_fingerprint`). At-most-one **concurrent platform-side owner** of a submission attempt is fully platform-guaranteed (Steps 2-3). No **automatic** retry occurs once the platform can no longer prove the provider was never contacted (the `SUBMITTING` boundary). What is explicitly **not** guaranteed: exactly-once **physical provider submission** during a genuinely ambiguous external failure (a crash strictly between the `SUBMITTING` commit and the actual network transmission, or during the provider's own processing of an already-sent request, are indistinguishable to the database and both handled identically — never auto-retried). No documented Exotel (or other configured provider) native idempotency-key mechanism for outbound call creation exists anywhere in this repository's 3B or 6D material, re-checked in this pass — this amendment does not claim one. That residual sliver is bounded by 6D's pre-existing provider-retry contract (3B §19) and `ReconcileDispatchOutcome`'s dependency on the provider adapter actually supporting reference echo-back, which remains unverified for Exotel specifically.

**Verification status:** live-executed and race-tested against a **genuinely separate PostgreSQL 16.10 instance** (the declared production baseline; the prior two passes had validated only against PostgreSQL 18) — the EDB full installer failed in this environment ("requires elevation," disclosed rather than worked around silently); a binaries-only distribution was used instead, with `pgvector` built from source via the locally available MSVC toolchain. Fresh-database and incremental `alembic upgrade` both passed (exit code 0); every concurrency/crash-recovery/reconciliation scenario named above was exercised as a genuine multi-connection transaction or real elapsed-time lease expiry, not simulated or narrated. Full transcripts: `docs/phase-05-database-design/5K/execution_logs/README.md`'s "Sixth batch" and `docs/phase-05-database-design/5K/validation/VOICE_DISPATCH_VALIDATION_REPORT.md`.

**Full DDL and rationale:** `099_5C1.sql`; `docs/phase-05-database-design/5C-Voice-Schema.md`'s matching amendment section; `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 4) §18, §49.

### 28.11 `GET /api/v1/calls`

- **Purpose:** List calls. **Authz:** `call:read`. **Filters:** `status`, `direction`, date range, `contact_ref`. **Pagination:** cursor. **Latency:** Tier A.

### 28.12 `GET /api/v1/calls/{call_id}`

- **Purpose:** Get one call. **Authz:** `call:read`. **Response:** full Call resource incl. `conversation_id` (nullable), current `status`, `outcome` (nullable), latency-profile summary fields (5C §5.1's running p50 columns). **Errors:** `404`.

### 28.13 `POST /api/v1/calls/{call_id}/terminate` — **Full depth (showcase)**

- **Purpose:** End an in-progress or ringing call (§11.2's disambiguation table).
- **Authorization:** `call:transfer` (interim mapping, DEP-6D-01, ADR-6D-01). **Actor:** USER, API_KEY.
- **Request:** empty body (or optional `{ "reason": "..." }` for operator note, not domain-significant).
- **Guard (CAS, §11.2):** `RINGING → CANCELLED` or `{ANSWERED, ACTIVE} → WRAP_UP`; any other current state → `409 STATE_CONFLICT` with `error.details.current_state`.
- **Response `200`:** updated Call resource with the new `status`.
- **Errors:** `403`, `404`, `409`.
- **Idempotency:** naturally near-idempotent (a second `terminate` on an already-terminal call cleanly 409s rather than double-processing) — no `Idempotency-Key` required, matching 6A §16.1's scope (action endpoints with a DB-guarded CAS do not need the header; the guard itself is the idempotency mechanism).
- **Latency:** Tier B — response returns once the CAS `UPDATE` commits; `TelephonyPort.hangup()` dispatched after, outside the transaction (§23.3) — this is precisely why Tier B stays close to Tier A "despite triggering real-world effects" (6A §11).
- **Database:** one CAS `UPDATE` on `voice.call_sessions`, plus `SELECT audit.fn_insert_audit_event(p_action_kind => 'CALL_TERMINATED', ...)` (§24.0 — sole legal audit write path, never a direct INSERT) and `audit.domain_event_outbox` INSERT (`call.ended` or `call.cancelled`, matching the resulting state — a separate, ordinary INSERT, §24.0) — same transaction.
- **Audit:** `CALL_TERMINATED` (5J §14.3 ‡ — **exact match, Category A**).
- **Domain Event:** `call.ended`/`call.failed` (outbox) depending on resulting state.
- **Observability:** `calls_terminated_total{resulting_status}` (no `organization_id` label — bounded-cardinality only, §32.1).
- **Concurrency:** full race analysis in §11.4/§30.
- **Security:** no PII beyond what `call:read` already exposes; no new exposure introduced by this action.

### 28.14 `POST /api/v1/calls/{call_id}/transfer`

- **Purpose:** Transfer to human/queue (§11.2). **Authz:** `call:transfer` (exact match). **Request:** `{ "transfer_target": "<E.164 or queue_id>", "transfer_type": "WARM"|"COLD" }`. **Guard:** `ACTIVE → TRANSFERRING`; `TransferOnlyOncePerCall` policy (already-`TRANSFERRED` calls 409). **Audit:** `CALL_TRANSFERRED` (5J §14.3 ‡ — **exact match, Category A**, via `audit.fn_insert_audit_event(...)`, §24.0 — never a direct INSERT). **Domain Event:** `call.transferring` then, on provider confirmation (async, not this endpoint's transaction), `call.transferred` (outbox, separate write).

### 28.15 `POST /api/v1/calls/{call_id}/hold`

- **Purpose:** `ACTIVE → ON_HOLD`. **Authz:** `call:transfer` (interim, DEP-6D-01). **Audit:** `CALL_HELD` (5J §14.3 ‡ — **exact match, Category A**).

### 28.16 `POST /api/v1/calls/{call_id}/resume`

- **Purpose:** `ON_HOLD → ACTIVE`. **Authz:** `call:transfer` (interim, DEP-6D-01). **Guard:** additionally rejects if the hold-timeout has already forced `ABANDONED` (system-driven, §11.2). **Audit:** `CALL_RESUMED` (5J §14.3 ‡ — **exact match, Category A**).

### 28.17 `GET /api/v1/conversations/{conversation_id}`

- **Purpose:** Get conversation. **Authz:** `call:read`. **Response:** `status`, `qualification_outcome`, `sentiment_label`/`score`, `summary_text` (nullable until post-call summarization completes, §12.4), token-usage totals, `total_turns`. **Errors:** `404`. **Latency:** Tier A.

### 28.18 `GET /api/v1/conversations/{conversation_id}/turns`

- **Purpose:** Paginated, sequence-ordered Turn history (§12.2), doubling as the REST resync target after a realtime gap (§13.7a) — **formally defined this pass** (Task D correction; the first draft referenced this query parameter from §13.3 without ever specifying it here).
- **Authz:** `call:read`.
- **Query params:** `since_sequence` (integer, optional, ≥1) — when present, returns only persisted Turns with `sequence_number > since_sequence`, ordered ascending by `sequence_number`; when absent, the endpoint returns the normal descending-by-recency page (§12.2's default). **`since_sequence` refers exclusively to `voice.turns.sequence_number` (persisted, per-Conversation) — never the WS envelope's per-connection `sequence` field (§13.3); the two are unrelated namespaces documented explicitly in §12.2, and a client must never pass a WS `sequence` value here.** Cursor pagination (6A §14) still applies on top of the `since_sequence` filter if more rows match than one page holds — the two mechanisms compose rather than conflict (`since_sequence` narrows the result set; the cursor paginates whatever remains).
- **Response fields per Turn:** `sequence_number`, `speaker_role`, `utterance_text`, `response_text`, `directive_kind`, `tool_execution_ids[]`, latency breakdown (`stt_ms`, `llm_first_token_ms`, `tts_first_audio_ms`, `turn_e2e_ms`), `barge_in_occurred`, `completed_at`.
- **Errors:** `400` (`since_sequence` not a positive integer).
- **Latency:** Tier A.

### 28.19 `GET /api/v1/calls/{call_id}/recording`

- **Purpose:** Recording metadata for a call. **Authz:** `recording:read`. **Response:** `status`, `duration_seconds`, `file_size_bytes`, `recording_policy` (snapshot, §16.1), `consent_obtained`, `retention_days`/`delete_after` — **never** `storage_ref`. **Errors:** `404` (no recording exists, e.g. `RecordingPolicy=DISABLED` at creation time).

### 28.20 `GET /api/v1/recordings/{recording_id}/download-url`

- **Purpose:** Signed, time-boxed download URL (§16.2, 6A §29). **Authz:** `recording:read`. **Guard:** `status` must be `STORED` → `404 RECORDING_NOT_AVAILABLE` otherwise (§27.2). **Response `200`:** `{ "download_url", "expires_at" }` (15-min expiry, matching 6A §29's platform-wide default). **Rate Limit:** 60/hour/org (signed-URL minting is cheap but not unlimited). **Audit:** not audited (read-only access-grant, matching 6C's own precedent for `logo/upload-url`-class endpoints, §15.4 there).

### 28.21 `POST /api/v1/recordings/{recording_id}/delete`

- **Purpose:** `STORED → DELETED`, clears `storage_ref`, retains row (4B §5.6 invariant 2), with a **crash-safe durable cleanup handoff — corrected this pass** (§16.3a): the pre-update `storage_ref` is captured in the same CAS `UPDATE` and carried, internal-only, in the same-transaction outbox payload — never cleared before a durable copy exists for the async cleanup consumer. **Authz:** `recording:delete`. **Guard:** `status='STORED'` → `409 STATE_CONFLICT` otherwise. **Latency:** Tier B (async S3-object-removal consumer triggered off the outbox event, post-commit, §16.3a). **Database:** the CTE-based CAS `UPDATE` of §16.3a, plus a synchronous `audit.fn_insert_audit_event(...)` call (§24.0 — never a direct `INSERT INTO audit.audit_events`) and `audit.domain_event_outbox` (`_internal_cleanup_ref` payload field, §16.3a, an ordinary INSERT) — same transaction. **Audit:** `RECORDING_DELETED` (5J §14.3 ‡ — **exact match, Category A**). **Domain Event:** `recording.deleted` (outbox, carries the internal cleanup reference, never exposed publicly, §16.3a).

### 28.22 `GET /api/v1/conversations/{conversation_id}/transcript`

- **Purpose:** Transcript metadata. **Authz:** `transcript:read`. **Response:** `status`, `total_segments`, `completed_at`. **Errors:** `404`.

### 28.23 `GET /api/v1/conversations/{conversation_id}/transcript/segments`

- **Purpose:** Cursor-paginated, sequence-ordered, **finalized-only** segments (§17.2). **Authz:** `transcript:read`. **Response fields per segment:** `sequence_number`, `speaker`, `text`, `start_ms`/`end_ms`, `confidence` (nullable, CALLER only), `language`. **Never** `is_partial=true` rows — none exist in Postgres to return (5C §5.10).

### 28.24 `GET /api/v1/tools`

- **Purpose:** List tools visible to the tenant (built-in ∪ own). **Authz:** `agent:read` (interim, DEP-6D-02). **Filters:** `is_active`. **Response fields:** `tool_id`, `tool_name`, `description`, `is_builtin`, `is_active` — **not** `input_schema`/`output_schema` in the list view (detail endpoint only, avoiding an unnecessarily large list payload).

### 28.25 `POST /api/v1/tools`

- **Purpose:** Create a tenant custom tool. **Authz:** `agent:write` (interim, DEP-6D-02). **Request:** `{ "tool_name" (camelCase, matches 5C CHECK regex), "description", "input_schema", "output_schema", "timeout_ms"? (100–30000, default 5000), "requires_confirmation"?, "max_retries_on_timeout"? (0–2, default 1) }`. **Validation:** schemas must be well-formed JSON Schema (§18.1); `tool_name` uniqueness within tenant (`409 STATE_CONFLICT`). **Audit:** `TOOL_DEFINITION_CREATED` (5J §14.3 ‡ — **exact match, Category A**).

### 28.26 `GET /api/v1/tools/{tool_id}`

- **Purpose:** Get one tool, full schema. **Authz:** `agent:read` (interim, DEP-6D-02). **Errors:** `404`.

### 28.27 `PATCH /api/v1/tools/{tool_id}`

- **Purpose:** Update a tenant-owned tool. **Authz:** `agent:write` (interim, DEP-6D-02). **Guard:** `organization_id IS NOT NULL` (built-ins reject with `403`). **Audit:** `TOOL_DEFINITION_UPDATED` (5J §14.3 ‡ — **exact match, Category A**).

### 28.28 `POST /api/v1/tools/{tool_id}/deactivate`

- **Purpose:** `is_active: true → false` (§18.1). **Authz:** `agent:write` (interim, DEP-6D-02). **Guard:** built-ins reject with `403` (platform tools are not tenant-deactivatable). **Audit:** `TOOL_DEFINITION_DEACTIVATED` (5J §14.3 ‡ — **exact match, Category A**).

### 28.29 `GET /api/v1/conversations/{conversation_id}/tool-executions`

- **Purpose:** List executions for a conversation, newest first (§18.2). **Authz:** `call:read`. **Pagination:** cursor.

### 28.30 `GET /api/v1/tool-executions/{execution_id}`

- **Purpose:** Get one execution (§18.2/§18.3). **Authz:** `call:read`. **Response:** `status`, `tool_name`, `arguments`, `result` (nullable until terminal), `error_message`/`error_code` (on failure), `attempt_count`, `started_at`/`completed_at`. **Errors:** `404`.

### 28.31 `GET /api/v1/provider-health`

- **Purpose:** Read-only health/routing observability (§15.2). **Authz:** `agent:read`. **Query:** `category` filter. **Response fields:** exactly the allow-list in §15.2 — never `credential_ref`/`config_json`. **Latency:** Tier A, Redis-cache-backed (§15.4).

### 28.32 `GET /api/v1/phone-numbers`

- **Purpose:** List the org's numbers (§19.1). **Authz:** `call:read` (interim, DEP-6D-03). **Response fields:** `phone_e164`, `status`, `capabilities[]`, `assigned_agent_id`, `inbound_enabled`/`outbound_enabled`.

### 28.33 `GET /api/v1/phone-numbers/{id}`

- **Purpose:** Get one number. **Authz:** `call:read` (interim, DEP-6D-03). **Errors:** `404`.

### 28.34 `POST /api/v1/phone-numbers/{id}/assign-agent`

- **Purpose:** Set/change `assigned_agent_id` (§19.1). **Authz:** `agent:publish` (interim mapping, retargeted this pass — DEP-6D-03, ADR-6D-08; OWNER/ADMIN only, correcting the first draft's over-broad `agent:write`). **Request:** `{ "agent_id" }`. **Validation:** target Agent must be `PUBLISHED` (consistent with `AgentMustBePublished`'s spirit — an inbound number should not route to a DRAFT agent). **Audit:** `PHONE_NUMBER_AGENT_ASSIGNED` (5J §14.3 ‡ — **exact match, Category A**).

### 28.35 `GET /api/v1/language-evaluations`

- **Purpose:** Platform reference data — "which providers are Tamil-capable for STT," etc. (5C §5.12). **Authz:** `agent:read` (adequate reuse, no gap). **Query:** `language`, `capability`, `verdict` filters. **RLS:** none — platform-scoped (5C §11.5). **Response fields:** `language`, `provider_id`, `provider_model_ref`, `capability`, `scores[]`, `verdict`, `evaluated_at`. **Latency:** Tier A. **Audit:** none (read, platform reference data).

### 28.36 `GET /api/internal/v1/calls/{call_id}`

- **Purpose:** Cross-tenant platform-admin/support lookup (mirrors 6C §15.41's exact pattern). **Authentication:** internal service JWT only (6A §23.4, 6B §17.2 central internal token issuer). **Authorization:** `actor_type=PLATFORM_ADMIN` asserted by the issuer, not a `{resource}:{action}` permission string. **Never** documented in the public OpenAPI surface (6A §8.5). **Not** subject to the public rate-limit/quota system — governed by a fixed internal ceiling instead.

### 28.37 `GET /api/internal/v1/agents/{agent_id}/versions/{version_id}`

- **Purpose:** Internal snapshot fetch for platform-admin debugging / a future Workflow-preview tool outside this monolith's direct DB access boundary. **Authentication/Authorization:** identical to §28.36. Same internal-only posture.

---

## 29. Realtime Message Catalog

All messages use the envelope of §13.3. `dir` = C→S (client-sent) or S→C (server-sent). Every S→C event's `payload` fields are drawn only from columns/values already defined in 5C/4B — no field is invented without a domain-model source. Total: **28 distinct message types.**

### 29.1 Connection / Session Control (5) — client frames use the flat `{type, ...}` schema (§13.6a); server acks use the full envelope (§13.3)

| `type` / `event_type` | dir | Payload | Notes |
|---|---|---|---|
| `session.subscribe` | C→S | `{ type: "session.subscribe", call_id, resume_from_cursor? }` | Required on `/calls/stream`; auto-satisfied (but still acceptable) on `/calls/{id}` (§13.4). `resume_from_cursor` is the stable, per-`(call_id)` replay cursor (§13.7a) — **never** the old, retracted `resume_from_sequence` field |
| `session.subscribed` | S→C | envelope payload: `{ call_id, current_status, replay_cursor }` | Ack; `current_status` lets the client render the call's state immediately without a separate REST call; `replay_cursor` is the position to persist client-side for the *next* reconnect's `resume_from_cursor` |
| `session.unsubscribe` | C→S | `{ type: "session.unsubscribe", call_id }` | Multi-call path only |
| `heartbeat.ping` | C→S | `{ type: "heartbeat.ping" }` | Every 20s (§13.7) |
| `heartbeat.pong` | S→C | envelope payload: `{}` | — |

### 29.2 Errors / Resync (2)

| `event_type` | dir | Payload | Notes |
|---|---|---|---|
| `error` | S→C | `{ code, message }` (mirrors 6A §24.1's error shape) | e.g. `AUTHORIZATION_DENIED` on a subscribe attempt lacking `call:read` |
| `resync.required` | S→C | `{ call_id, reason: "live_gap" \| "cursor_expired" \| "backpressure_drop", gap_from_sequence?, gap_to_sequence?, requested_cursor? }` | `reason: "live_gap"` — a `sequence` gap on the current connection (§13.3), carries `gap_from_sequence`/`gap_to_sequence`. `reason: "cursor_expired"` — a `resume_from_cursor` on `session.subscribe` fell outside the 60s replay buffer (§13.7a), carries the unresolvable `requested_cursor`. `reason: "backpressure_drop"` — server dropped buffered events under overflow (§13.7), carries the affected `gap_from_sequence`/`gap_to_sequence` on this connection. In every case, the client falls back to REST (`GET /conversations/{id}/turns?since_sequence=...`, §28.18) for the persisted subset of what it missed. |

### 29.3 Call-State Events (8) — mirror `call_sessions.status`, never WS-originated (§13.5)

| `event_type` | dir | Payload | Persisted equivalent |
|---|---|---|---|
| `call.state_changed` | S→C | `{ call_id, previous_status, new_status }` | Generic catch-all, fired alongside every specific event below for clients that only care about the raw enum |
| `call.answered` | S→C | `{ call_id, answered_at }` | `call_sessions.answered_at` |
| `call.held` | S→C | `{ call_id, session_id, held_at }` | Embedded `sessions[]` entry |
| `call.resumed` | S→C | `{ call_id, session_id, resumed_at }` | Embedded `sessions[]` entry |
| `call.transferring` | S→C | `{ call_id, transfer_target, transfer_type }` | Transient state |
| `call.transferred` | S→C | `{ call_id, transfer_confirmed_at }` | `call_sessions.status='TRANSFERRED'` |
| `call.ended` | S→C | `{ call_id, ended_at, duration_seconds, outcome }` | Terminal |
| `call.failed` | S→C | `{ call_id, failure_reason, failed_at }` | Terminal |

### 29.4 Conversation / Turn Events (7)

| `event_type` | dir | Payload | Persisted? |
|---|---|---|---|
| `conversation.started` | S→C | `{ conversation_id, call_id, agent_version_id }` | Yes — `voice.conversations` row |
| `turn.utterance_partial` | S→C | `{ turn_id (provisional), text_so_far, confidence }` | **No** — Redis-only, never written to Postgres (§17.2) |
| `turn.utterance_final` | S→C | `{ turn_id, text, confidence, detected_language, start_ms, end_ms }` | Yes — corresponds to the `voice.transcript_segments` row written at this moment |
| `turn.agent_response_delta` | S→C | `{ turn_id, text_delta }` | **No** — marked provider-dependent granularity (§12.3); some TTS/LLM adapter combinations may emit larger chunks than others |
| `turn.agent_response_final` | S→C | `{ turn_id, response_text, directive_kind, latency: {stt_ms, llm_first_token_ms, tts_first_audio_ms, turn_e2e_ms} }` | Yes — mirrors the fields written at Turn checkpoint |
| `turn.completed` | S→C | `{ turn_id, sequence_number, barge_in_occurred }` | Yes — fired once the `voice.turns` INSERT commits; the authoritative "this turn is now durably recorded" signal |
| `conversation.completed` | S→C | `{ conversation_id, total_turns, total_tokens_used }` | Yes |

### 29.5 Tool Execution Events (3)

| `event_type` | dir | Payload | Notes |
|---|---|---|---|
| `tool_execution.started` | S→C | `{ execution_id, turn_id, tool_name }` | Satisfies §21.6's "tool progress/runtime event" requirement |
| `tool_execution.succeeded` | S→C | `{ execution_id, duration_ms }` | Result payload itself is **not** inlined (potentially large, §18.3) — client calls `GET /tool-executions/{id}` for detail |
| `tool_execution.failed` | S→C | `{ execution_id, error_code, attempt_count }` | Covers both `FAILED` and `TIMED_OUT` terminal states, distinguished by `error_code` |

### 29.6 Voice-Runtime / Barge-In Events (2) — per §14

| `event_type` | dir | Payload |
|---|---|---|
| `voice.barge_in_detected` | S→C | `{ call_id, conversation_id, turn_id, detected_at }` |
| `voice.tts_cancelled` | S→C | `{ call_id, conversation_id, turn_id, cancel_confirmed }` |

### 29.7 Qualification Event (1)

| `event_type` | dir | Payload |
|---|---|---|
| `conversation.qualification_set` | S→C | `{ conversation_id, outcome, criteria_matched[] }` |

**Total: 5 + 2 + 8 + 7 + 3 + 2 + 1 = 28 message types.**

---

## 30. Concurrency / Idempotency

### 30.1 Mechanism (restated once, applies to every guarded endpoint)

No 5C `SECURITY DEFINER` guard function exists for Call/Agent/Conversation status (§5 finding #4). Every guarded transition in this document uses the **API-layer CAS** pattern (`UPDATE ... WHERE status = ANY($allowed) RETURNING id`) — identical to 6C's ADR-6C-02, not a third mechanism. No API-layer `SELECT ... FOR UPDATE` is introduced anywhere (6A §17.3).

### 30.2 Named Race Analysis

| Race | Outcome |
|---|---|
| Terminate vs. transfer (concurrent, same call) | Atomic CAS — one wins, the other 409s with accurate `current_state` (§11.4) |
| Remote hangup (provider webhook) vs. local terminate (tenant REST) | Same CAS row; whichever commits first wins; the other gets `409` (§11.4) |
| Barge-in vs. active TTS stream | Handled entirely in-process (3B §12.2) — not an API-layer race; 6D's WS surface only reports the outcome (§14.3) |
| Double call-start retry | `Idempotency-Key` required on `POST /calls` (§28.10) — same key + same payload replays the cached response; same key + different payload → `409 IDEMPOTENCY_KEY_REUSE_MISMATCH` (6A §16.2) |
| Concurrent agent publish/update | `uq_av_version`'s DB uniqueness constraint is the ultimate backstop — under this endpoint's READ COMMITTED isolation the loser raises **SQLSTATE `23505` (`unique_violation`)**, not a `40001` serialization failure (corrected this pass, Task F); handled by §9.2a's bounded retry (up to 3 attempts), `409 STATE_CONFLICT` on exhaustion (§28.5) |
| Provider callback duplication | `UNIQUE (organization_id, provider_slug, provider_event_id)` on `webhooks.inbound_webhook_events` (5I §10, reused per 6A §28.2) — a no-op on redelivery, before it ever reaches the CAS update |
| Duplicate transcript-final delivery | Deterministic UUIDv7 derived from `(transcript_id, sequence_number)` (5C §11.4) makes the INSERT naturally idempotent via `ON CONFLICT (id, created_at) DO NOTHING` — no 6D-layer logic needed, this is a Phase 5-provided guarantee 6D's design relies on correctly |
| Repeated telephony status callback (e.g., "answered" delivered twice) | Same `UNIQUE (org, provider_slug, provider_event_id)` guard as above; additionally, the resulting CAS `UPDATE` targeting `call_sessions.status` is itself idempotent-safe (a second `RINGING→ANSWERED` attempt against an already-`ANSWERED` row simply matches zero rows and no-ops, rather than erroring loudly) |
| Two near-simultaneous `POST /calls` both passing the concurrent-call quota check | Disclosed, non-blocking residual — **DEP-6D-09** (§36), identical in severity class to 6C's own disclosed DEP-6C-13 |

### 30.3 Idempotency Summary (6A §16, applied)

Required: `POST /agents/{id}/publish` (recommended), `POST /calls` (required). Not required: every `GET`, every action endpoint already protected by a CAS guard whose own 409-on-retry behavior is sufficient (terminate/transfer/hold/resume, deprecate, deactivate) — a second identical retry either lands on the same terminal state (safe no-op observable via `GET`) or cleanly 409s; neither outcome is "dangerous" in 6A §16.1's sense once the CAS guard exists.

---

## 31. Rate Limits / Quotas

### 31.1 Abuse Rate Limiting vs. Commercial Quota — Not Conflated (6A §20, applied)

| Layer | Applies to | Mechanism |
|---|---|---|
| L1 — NGINX ingress | Every 6D REST endpoint, every WS connection attempt | Per-source-IP (60/min), per-WS-connection-count (5 concurrent) — 6A §20/3F §8.4, reused unmodified |
| L2 — App, standard CRUD | Agent/Tool/Phone-Number reads and writes | Default 300 req/min/org (6A §20's default) |
| L2 — App, cost-sensitive | `POST /calls` | **Not** a request-count limiter — governed by the existing `CheckQuota` port (4A #6), exactly as 6A §20 already specifies for "outbound call initiation, LLM-backed operations" |
| L2 — App, heavy-read | `GET /provider-health`, `GET /language-evaluations` | Standard Tier A ceiling — neither is a genuinely heavy aggregate query (both are small, cached/reference-data reads), so no special lower ceiling is warranted beyond the standard default |
| Realtime connection | `/ws/v1/voice/calls/*` | Connection/subscribe-frame limits, §13.7 — governed separately from the REST rate-limit system, per 6A §20's own statement that realtime traffic needs its own connection/frame/backpressure protections, not a generic per-request limiter |

### 31.2 Concurrent-Call Quota — Consumed, Not Redesigned

`ConcurrentCallQuotaNotExceeded` (4B §9) reads the existing `QuotaConfig` aggregate (4A §5.7/4F §5.4, 5H `quota_configs` table) via the platform's real-time Usage & Quota bounded context's `CheckQuota` port — 6D does not design or duplicate this mechanism; it consumes the port exactly as 4B §9/§14.1 already specify, and as 6A §20 already directs for this exact scenario.

### 31.3 429 Response Shape

Standard 6A headers (`Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) for abuse-layer 429s. For a `QUOTA_EXCEEDED` (§27.2) commercial-limit 429, `Retry-After` is omitted or set to a plan-tier-appropriate hint (e.g., "try again once a concurrent call completes") — it is not framed as a fixed request-pacing window, since the underlying cause (too many concurrent calls, not too many requests) is qualitatively different.

---

## 32. Observability

### 32.1 The Primary SLO Metric

`voice_turn_response_latency_ms` — histogram, defined exactly per §21.1. Bounded-cardinality labels only: `organization_id` is **excluded** from this metric's label set (per the governing task's explicit caution against uncontrolled high-cardinality Prometheus labels) — per-tenant breakdowns are obtained via trace/log correlation (below), never via a metric label that would create one time series per tenant.

### 32.2 Per-Stage Metrics (§21.3's table, each independently observable)

| Metric | Stage |
|---|---|
| `voice_vad_endpoint_latency_ms` | VAD / endpoint detection |
| `voice_stt_finalization_latency_ms{provider}` | STT finalization — `provider` is a bounded label (small, fixed set of adapter names, 3B §10.2) |
| `voice_model_router_latency_ms` | Model Router selection |
| `voice_llm_ttft_ms{provider, model}` | LLM time-to-first-token — bounded labels (7 adapters × a small model list) |
| `voice_tool_execution_duration_ms{is_builtin}` | Tool execution, only when invoked — **corrected this pass (Task H):** the first draft's `{tool_name}` label was unbounded (tenant-defined custom tools can grow without limit, 5C §5.6); replaced with `is_builtin` (bounded: `true`/`false`, an actual `voice.tool_definitions` column). Exact `tool_name` is a trace/log-correlation attribute only (§32.3), never a metric label. |
| `voice_tts_ttfa_ms{provider}` | TTS time-to-first-audio-byte — **corrected this pass (Task H):** the first draft's `{provider, voice_id}` label set included `voice_id`, which is tenant/agent-configurable and has no bounded replacement in 5C (no "voice category" column exists) — per this pass's own instruction to omit a label rather than invent an unbounded one, `voice_id` is dropped from the metric and kept as a trace/log-correlation attribute only (§32.3) |
| `voice_turn_response_latency_ms` | End-to-end (§32.1) |

### 32.3 Correlation Dimensions — High-Cardinality vs. Bounded, Explicitly Separated

| Dimension | Treatment |
|---|---|
| `organization_id`, `call_id`, `conversation_id`, `turn_id`, `agent_version_id`, `tool_name`, `voice_id` | **Trace/log correlation only** (OpenTelemetry span attributes, structured log fields, 6A §25) — never a Prometheus metric label. `tool_name` and `voice_id` added to this list this pass (Task H) — both are tenant/agent-configurable and unbounded, exactly like the other identifiers already in this row. |
| STT provider, LLM provider/model, TTS provider, `language`, `is_builtin` (tool category) | **Bounded metric labels** — small, fixed, slowly-changing sets, safe per 6A §25's existing convention (`platform_`-prefixed metrics already use exactly this style of bounded label) |

### 32.4 Tracing

Every REST request, WS session, and (where instrumented in a future Phase 23/24 pass) each turn-loop stage is an OpenTelemetry span, reusing 6A §25's existing sampling policy (100% for voice call traces, unchanged) — 6D introduces no new tracing infrastructure, only new span names/attributes for Voice-specific stages.

### 32.5 Dashboards

Extends the already-provisioned "Voice Pipeline" and "Provider Health" Grafana dashboards (3E §14.3, 6A §26) with the §32.2 metrics — no new dashboard *tool* is introduced, only new panels on the existing, already-provisioned-as-code dashboards.

---

## 33. Threat Model

| Threat | Mitigation |
|---|---|
| Cross-tenant call/conversation/recording/transcript access (IDOR) | RLS (5C §11.1) as the primary guarantee; application-layer ownership check as defense-in-depth; `404` never `403` on cross-tenant reference (§25) |
| Caller-ID spoofing via a client-supplied `from_number` | Structurally prevented — `from_number` is never client-suppliable on `POST /calls` (§28.10); always server-resolved from the tenant's own assigned numbers |
| Tenant referencing another tenant's custom tool in `Agent.tool_permissions` | Validated at every draft-config write (§8.2) — `tool_id` must resolve to a tenant-visible row |
| Forged/replayed telephony provider webhook | Provider-native signature verification (§10.4) + `UNIQUE (org, provider_slug, provider_event_id)` idempotency (5I §10) — not tenant-JWT-authenticated, by design, since the caller is the provider, not a tenant |
| WS connection hijack / cross-tenant subscription | JWT-authenticated handshake (§13.2), tenant-bound for connection lifetime, RBAC re-verified on every `subscribe` (§13.4, 6A §27.4) |
| Recording/transcript exfiltration via long-lived URL | 15-min signed-URL expiry (§16.2, 6A §29) — never a long-lived or guessable URL |
| Tool-execution `arguments`/`result` leaking secrets | `arguments` are tenant-declared JSON, validated against `input_schema` — not a secret-injection point; `credential_ref` values are never placed in `arguments`/`result` by domain design (5C §5.11's `credential_ref` lives only on `provider_configs`, a table §26 already excludes from every 6D response) |
| Confused-deputy: internal token presented at a public route (or vice versa) | 6B §17.3's routing rule, reused unmodified — neither validator falls back to the other |
| Denial of service via WS subscribe-spam | 20 subscribes/min/connection (§13.7), 5 concurrent connections/source (6A §27.2) |
| Denial of service via oversized WS message | 32KB max message size (§13.7) |
| Quota-exhaustion abuse (many outbound calls) | `CheckQuota` port (§31.2) + standard L1/L2 rate limiting (§31.1) |
| Barge-in false-positive griefing (a bot triggering repeated barge-ins) | `BargeInSensitivity` is a per-agent tunable (4B §8.3), not attacker-controlled from outside the call itself; a malicious caller can only barge in on *their own* call, with no cross-call or cross-tenant blast radius |

---

## 34. Test Strategy

### 34.1 Contract

Every REST endpoint (§28, 37 total) and every WS message type (§29, 28 total) gets a contract test verifying request/response schema, status codes, and the standard 6A envelope shape.

### 34.2 Authorization

All role × permission combinations from §25's matrix; API-key scope intersection (6B §16.1's "scopes ∩ role permissions" rule) for every API-key-eligible endpoint; cross-tenant denial (`404`, never `403`) for every resource-scoped endpoint; internal-service-JWT-only access for §28.36/§28.37, verified to reject a user/API-key credential and vice versa (6B §17.3's confused-deputy test).

### 34.3 State

Every legal transition in §11.1/§11.2's tables (14 Call states, all documented transitions) and §9's Agent lifecycle (`DRAFT→PUBLISHED→DEPRECATED`), both positive (succeeds from an allowed state) and negative (409s from every other state) — a full state × action matrix, not spot-checks.

### 34.4 Concurrency

Every race in §30.2's table gets a dedicated concurrent-request test: terminate/transfer race, duplicate provider callback, duplicate transcript-final delivery, concurrent agent publish, double call-start retry under one `Idempotency-Key`.

### 34.5 Realtime

Connection auth (valid/expired/wrong-tenant JWT), reconnect with `resume_from_cursor` (including the "cursor expired, `resync.required`" path, §13.7a), same-connection `sequence`-gap detection (distinct test from cursor-based resume — §13.3's two-namespace rule gets its own dedicated test asserting a client never conflates them), duplicate `event_id` handling on both live delivery and cursor-based replay, per-call independent replay cursors on the `/calls/stream` multi-call path (§13.4), backpressure (forcing the 500-event buffer to overflow and verifying oldest-first drop + `resync.required`), graceful disconnect, and — specifically — the full barge-in sequence (§14.2's diagram, end to end: inject a barge-in condition, verify `voice.barge_in_detected` and `voice.tts_cancelled` both fire with matching `turn_id`, verify the interrupted Turn's `barge_in_occurred=true` on its eventual checkpoint).

### 34.6 Latency

The no-tool turn p50 ≤750ms target test uses **exactly** the §21.1 metric definition: start = caller end-of-utterance/endpoint-committed, end = first agent audio byte delivered toward the caller — never REST latency, never LLM-completion latency, never first-text-token-only. Per-stage timing assertions against §21.3's table. A provider-specific benchmark matrix (§21.10) run separately per STT/LLM/TTS adapter combination. Cold-connection (first turn of a call) vs. warm (steady-state) compared separately. Load/concurrency effects measured under `NFR-SCALE-001`'s target concurrency. The Tamil/code-switching path benchmarked as its own row, reusing 4I §4.4's evaluation-set methodology. **No latency PASS is claimed without an actual measurement — this test suite's existence, and the metric's definition, is what this document delivers; the results are Phase 23/24's, not this document's, to report** (§21.13).

### 34.7 Failure

STT/LLM/TTS/telephony provider failure and failover (§21.8, 4B §18.5's sequence reproduced as a test); all-providers-unavailable (`AllProvidersUnavailableError` → Call `FAILED`, §21.9); Redis interruption (session hot-tier read/write failure — verify graceful degradation to at-most-one-lost-in-flight-turn, 3B §7); DB interruption outside the hot path (a `GET` endpoint's DB unavailability, verified to surface `503`/`DEPENDENCY_UNAVAILABLE`, never hang); outbox delay (a consumer lag scenario, verifying the request-transaction-side behavior is unaffected — §23/§24); caller disconnect mid-call (verify the stale-session reaper's `FAILED` force-transition and `call.failed` emission, 3B §18.2).

---

## 35. Traceability

| Requirement | Source | 4B | 5C | 6A | 6B | 6C | 6D coverage |
|---|---|---|---|---|---|---|---|
| `FR-VOICE-001` (inbound call handling) | SRS | §5.1, §18.1 | `call_sessions` | §27, §28.2 | §17 (internal auth) | — | §10.4, §28.10–16 |
| `FR-VOICE-002` (outbound call initiation) | SRS | §5.1, §18.2 | `call_sessions` | §11 Tier B, §35 | — | — | §10, §28.10 |
| `FR-VOICE-003` (AI conversation / turn loop) | SRS | §5.2, §7.2, §18.1 | `conversations`, `turns` | §27.3 | — | — | §12, §13, §29 |
| `FR-VOICE-004` (transfer to human) | SRS, where in scope | §5.1, §12.1, §18.4 | `call_sessions.transfer_target` | §8.3 | — | — | §11.2, §28.14 |
| `FR-VOICE-005` (call recording), where in scope | SRS | §5.6 | `recordings` | §29 | — | §12 (RecordingPolicy source) | §16 |
| `FR-VOICE-006` (transcript generation) | SRS | §5.7 | `transcripts`, `transcript_segments` | §14 (append-only) | — | — | §17 |
| `FR-VOICE-007` (partial responses / barge-in) | SRS | §8.3, §12.2 (3B) | `turns.barge_in_occurred` | §27.3 | — | — | §14, §29.6 |
| `NFR-PERF-001` (<800ms p50) | SRS | — | — | §11 | — | — | §21 (≤750ms 6D target, reconciled) |
| `NFR-OBS-002` (per-stage voice latency observability) | SRS | — | — | §25, §26 | — | — | §32 |
| `NFR-AVAIL-001` | SRS | §7.5, §8.4 (circuit breaker) | `provider_configs` | §21 (circuit breaker) | — | — | §15, §21.8–9 |
| `NFR-SEC-*` applicable to Voice | SRS | §21 (Tamil), security review | §13, §19 (PII, RLS) | §22 | §9, §11, §17 | §14, §24 | §25, §26, §33 |
| Agent/LLM/TTS/STT requirements consumed | 4B §16 ports | §16 | §5.11 | §11 | — | — | §15 |

---

## 36. Dependencies / Open Issues

| ID | Description | Source of gap | Affected endpoint/path | Design status | Implementation status | Security impact | Latency impact | Blocks 6D architecture? | Blocks 6D implementation? | Blocks final approval? |
|---|---|---|---|---|---|---|---|---|---|---|
| **DEP-6D-01** | No `call:terminate`/`call:hold`/`call:resume` permission exists in 5B | 5B permission catalog (§5 finding #7) | §28.13/28.15/28.16 | Interim mapping specified (reuses `call:transfer`, identical role-grant footprint to `call:initiate`), ADR-6D-01. **Re-verified this pass (Task K) against 5B's canonical role-permission grant table:** `call:transfer` and `call:initiate` are both held by exactly `{OWNER, ADMIN, MEMBER}` — confirmed conservative, no over-grant | Implementable today with the interim mapping | None — mapping is conservative, no over-grant | None | No | No | No |
| **DEP-6D-02** | No `tool:*` permission exists in 5B | 5B permission catalog | §28.24–28.28 | Interim mapping specified (`agent:read`/`agent:write`), ADR-6D-02. **Re-verified this pass (Task K):** `agent:write` (`{OWNER, ADMIN, MEMBER}`) already lets a MEMBER fully control which tools an agent invokes via `tool_permissions` (§8.2) — allowing the same actor set to also define the tool's schema introduces no privilege a MEMBER doesn't already effectively hold; confirmed non-blocking, no change made | Implementable today | None | None | No | No | No |
| **DEP-6D-03** | No `phone_number:*` permission exists in 5B | 5B permission catalog | §28.32–28.34 | **Split into two, and one half corrected this pass (Task K):** phone-number *viewing* (§28.32/28.33) uses `call:read` (`{OWNER, ADMIN, MEMBER, VIEWER}`) — confirmed appropriate, matches Call-family read sensitivity. Phone-number *assignment* (§28.34) was re-targeted from the first draft's `agent:write` to **`agent:publish`** (`{OWNER, ADMIN}` only) — the original `agent:write` mapping over-granted MEMBER a live-inbound-call-routing change with no version-pinning safety net (§9.1); `agent:publish`'s existing OWNER/ADMIN-only grant matches that action's actual "immediately affects live traffic" sensitivity. ADR-6D-08. No new 5B permission was required — an existing, better-fitting permission was substituted | Implementable today with the corrected interim mapping | **Resolved this pass** — the one genuine over-grant this Task K review found was closed by re-targeting to a stricter existing permission, not by leaving it open | None | No | No | No |
| **DEP-6D-04 — RESOLVED this pass** | ~~5J §14.3's audit `action_kind` vocabulary has no value for `AGENT_CREATED`, `AGENT_CONFIG_UPDATED`, `CALL_INITIATED`, `CALL_TERMINATED`, `CALL_TRANSFERRED`, `CALL_HELD`, `CALL_RESUMED`, `TOOL_DEFINITION_CREATED`/`UPDATED`/`DEACTIVATED`, `RECORDING_DELETED`, `PHONE_NUMBER_AGENT_ASSIGNED` (12 missing values covering 13 of 6D's 15 state-changing endpoints — corrected count, Task B: only `agent.publish`/`agent.deprecate` had exact matches before this amendment; `AGENT_CREATED` alone covers both `POST /agents` and `POST /agents/{id}/clone`, which is why 12 values close a 13-endpoint gap)~~ **All twelve values added to `5J-Analytics-Audit-Schema.md` §14.3, marked `‡`, this pass** | 5J §14.3, verified directly (§5 finding #6) | §28.1, 28.4, 28.7, 28.10, 28.13–16, 28.21, 28.25, 28.27–28, 28.34 | **RESOLVED** — every endpoint's `Audit:` bullet in §28 now names an exact-match, governed `action_kind`, Category A | **RESOLVED — governance-only amendment, no SQL migration** (`chk_ae_action_kind` remains a length check, not an enum, verified directly against `072_5J.sql`, unchanged by this amendment) | None — this closes a governance gap, it does not open one | None (audit writes are already off the hot path, §21.11) | **No** | **No** — all 15 of 15 state-changing endpoints now write a governed, exact-match `action_kind` synchronously (§24.0) | **No — resolved. This was the sole blocker in the prior pass; see §40.** |
| **DEP-6D-13 — new and RESOLVED this pass** | ~~The prior pass's own audit-write description was itself illegal: it instructed a direct `INSERT INTO audit.audit_events`, which no application role may execute (5J §5/§14.2, `REVOKE ALL` — `audit.fn_insert_audit_event()` is the sole permitted write path)~~ **Every §28 endpoint, §9.2, §16.3a, §23.4, and §24.0 corrected to `SELECT audit.fn_insert_audit_event(...)` — zero direct-INSERT instructions remain in this document** | Self-review of the prior pass's own §24.0/§28 wording against 5J §5/§14.2's actual `REVOKE`/`SECURITY DEFINER` contract | §9.2, §16.3a, §23.4, §24.0, all 15 §28 mutation contracts | **RESOLVED** | **RESOLVED — no schema change, no function change; 6D now consumes `fn_insert_audit_event()` exactly as 5J already defines it** | None on its own; the retracted wording, if implemented literally, would have failed at runtime with a permissions error on every single mutation — this closes that risk | None (audit call sites are unchanged in count and transaction placement, only in call syntax) | **No** | **No** | **No — resolved this pass** |
| **DEP-6D-14 — new and RESOLVED this pass** | ~~5J §14.5's "Configuration, campaign, plugin lifecycle changes → Asynchronous (Celery)" row did not name an exception for 6D's Voice control-plane endpoints, which this document requires to be synchronous~~ **5J §14.5 amended this pass with an explicit, named 6D Voice synchronous exception (documentation-only, no SQL change)** | 5J §14.5, cross-checked against 6D's own synchronous-audit requirement (§24.0) | All 15 §28 mutation endpoints | **RESOLVED** | **RESOLVED — governance-only amendment** | None — this closes an ambiguity, it does not open one | None — Voice control-plane endpoints are already Tier A/B, off the ≤750ms hot path (§21.11) | **No** | **No** | **No — resolved this pass** |
| **DEP-6D-05** | Platform-default ring timeout (outbound `RINGING→NO_ANSWER`) and hold timeout (`ON_HOLD→ABANDONED`) values are undefined | 4B OQ-4B-01/OQ-4B-02, carried forward unresolved | §11.1 (implicit — the transitions exist, the timer values do not) | Not an API-contract concern (no endpoint takes these as parameters) — a runtime configuration value | Blocked on Product, not on this document | None | None — timer values do not affect the turn-latency target | No | No — the state machine and API contract are complete regardless of the specific timeout value | No |
| **DEP-6D-06** | Tenant-facing `ProviderConfig` CRUD (choosing/prioritizing a non-default provider, linking `credential_ref`) is not designed | No `provider:*` permission; no product requirement surfaced in Phase 1–5 beyond per-agent `ModelConfig` fields (§15.3) | N/A — no endpoint proposed | Explicitly deferred, not designed | N/A | N/A | N/A | No | No | No |
| **DEP-6D-07** | Tenant phone-number provisioning/purchase from a carrier is not designed | `TelephonyPort` (4B §16) has no `provision_number()` method (§19.2) | N/A — no endpoint proposed | Explicitly deferred, not designed — would require a new DDD command, out of this document's authority | N/A | N/A | N/A | No | No | No |
| **DEP-6D-08** | `TtsPort.cancel()`'s real cancellation guarantee is unverified against a live provider (ElevenLabs) API | 3B §23, Review Note 2 (inherited, not newly introduced) | §14.3, `voice.tts_cancelled` event | Designed defensively — `cancel_confirmed: boolean` never asserts unconditionally (§14.3) | Blocked on a provider-API validation spike (3B's own stated need) | Low — worst case is a brief audio overlap during barge-in, not a security issue | Could affect perceived barge-in responsiveness if cancellation is slower than assumed, not the ≤750ms *turn* metric itself (§21.7) | No | No — the API contract degrades gracefully either way | No |
| **DEP-6D-09** | Two near-simultaneous `POST /calls` requests can both pass the concurrent-call-quota check before either commits | `ConcurrentCallQuotaNotExceeded`'s indexed-count read is not a hard serialization point (§28.10) | §28.10 | Disclosed, contained — at most a brief, bounded over-quota condition, self-correcting on the next check | Functional today with the disclosed residual | None | None | No | No | No |
| **DEP-6D-10** | No fallback TTS vendor is approved | 3B §23, Review Note 4 (inherited) | §15 (ProviderSelectionService candidate list for TTS) | Disclosed — the Model Router's TTS candidate list may legitimately be length-1 today | Blocked on Product/Architecture sign-off (3B's own stated need) | None | If the sole TTS provider is unavailable, `AllProvidersUnavailableError` fires (§21.9) — a wider blast radius than STT/LLM's multi-provider fallback, but not a new gap 6D introduces | No | No | No |
| **DEP-6D-11** | The §21.3 per-stage latency budget has never been validated against real provider benchmarks | 3B §23 (inherited) | §21 entire | Benchmark plan specified (§21.10) | Deferred to Phase 23/24 by design — this document does not claim it is done | None | Central to whether ≤750ms is achievable in production — explicitly labeled TARGET, not MEASURED, throughout §21 | No | No | No |
| **DEP-6D-12** | Agent archival/hard-delete (`voice.agents.deleted_at`) has no corresponding 4B command and no 6D endpoint | 5C §5.4 column exists; 4B §12.3's command catalogue has no `ArchiveAgent`/`DeleteAgent` | §9.4 | Disclosed scope boundary — `deprecate` is the only lifecycle-terminal action 6D exposes | N/A — no feature exists to be blocked | None | None | No | No | No |

**Reading the table, updated this pass:** **DEP-6D-04 — the sole architecture-approval blocker from the prior pass — is now RESOLVED**, via the same class of controlled, documentation-only 5J §14.3 governance amendment that resolved 6C's structurally identical DEP-6C-07/10/11/14/15 cluster, explicitly authorized for this pass. DEP-6D-01/02 were re-verified against 5B's actual grant table and remain non-blocking, unchanged. DEP-6D-03 was re-verified and **partially corrected** — its phone-number-assignment half was over-granting MEMBER and is now tightened to `agent:publish` (ADR-6D-08); its phone-number-viewing half was already appropriate and is unchanged. The remaining eight dependencies (DEP-6D-05/06/07/08/09/10/11/12) are genuinely non-blocking and out of this document's authority to resolve — each requires a Product decision, a DDD-level command addition, or a live provider validation spike this document cannot perform, and none was newly introduced or newly resolved by this correction pass. **With DEP-6D-04 resolved and DEP-6D-01/02/03 confirmed or corrected to non-blocking, no dependency in this register blocks final approval** — see §40.

---

## 37. Architecture Decision Records

| ID | Decision | Alternatives considered | Rationale | Status |
|---|---|---|---|---|
| ADR-6D-01 | `POST /calls/{id}/terminate`, `/hold`, `/resume` are gated by the existing `call:transfer` permission (no dedicated `call:terminate`/`call:hold`/`call:resume` permission exists) | Invent new permission strings (rejected — violates the explicit instruction not to invent permissions silently); gate by `call:initiate` instead (rejected — semantically about *starting* a call, not controlling an active one) | `call:transfer` is the platform's only existing "actively manage a live call" permission beyond `call:initiate`/`call:read`, and its role-grant footprint (OWNER/ADMIN/MEMBER) is identical to `call:initiate`'s — the same actors who can start a call can already, today, transfer it, so extending the same set to terminate/hold/resume introduces no privilege-escalation surface | Decided (interim — DEP-6D-01) |
| ADR-6D-02 | Tool Definition CRUD (§18.1) is gated by `agent:read`/`agent:write` (no dedicated `tool:*` permission exists); Phone Number *viewing* (§19.1) is gated by `call:read` | Invent `tool:read`/`tool:write`/`phone_number:read` (rejected — same reason as ADR-6D-01); gate tools by a Knowledge/Workflow-adjacent permission (rejected — Tool Definitions are squarely a Voice/Agent-context resource, 4B §5.4, not Knowledge or Workflow) | Tools exist to be referenced by an Agent's `tool_permissions` (§8.2) — their lifecycle is naturally agent-configuration-adjacent; phone-number *viewing* is call-routing-configuration-adjacent, matching `call:read`'s existing scope | Decided (interim — DEP-6D-02, DEP-6D-03) |
| ADR-6D-08 (new this pass) | Phone Number **assignment** (`POST /phone-numbers/{id}/assign-agent`) is gated by `agent:publish` (OWNER/ADMIN only), not `agent:write` | Keep the first draft's `agent:write` mapping (retracted — re-checked against 5B's canonical grant table this pass, §5 finding #7: `agent:write` includes MEMBER, which over-grants a live-inbound-routing change with no version-pinning safety net); invent a new `phone_number:manage` permission via a 5B amendment (rejected — an existing, correctly-scoped permission already fits; inventing a new one is unnecessary per this pass's own Task K instruction to prefer the minimum change) | Reassigning a number's `assigned_agent_id` takes effect immediately for the next inbound call — no `AgentVersion` pinning protects against it the way a live call's own pinned configuration protects an in-progress call (§9.1); its blast radius is closer to `agent:publish`'s "go live" sensitivity than to an ordinary draft-config edit, and `agent:publish`'s existing OWNER/ADMIN-only grant matches that sensitivity exactly | Decided (interim — DEP-6D-03) |
| ADR-6D-03 | Call/Agent/Conversation guarded state transitions use an atomic conditional `UPDATE ... WHERE status = ANY(allowed) RETURNING id` (CAS), no API-layer lock, in the absence of a bespoke Phase 5 `SECURITY DEFINER` function | Add a new `SECURITY DEFINER` function to 5C (rejected — modifies frozen Phase 5); use `SELECT ... FOR UPDATE` (rejected — violates frozen 6A §17.3) | Directly reuses the exact mechanism 6C's own ADR-6C-02 already established for the identical gap in Core Platform — a proven, already-sanctioned pattern, not a new one invented for Voice | Decided |
| ADR-6D-04 | The ≤750ms p50 no-tool caller-perceived turn-latency target is adopted as 6D's binding engineering target, layered on top of (not replacing) the frozen NFR-PERF-001 <800ms ceiling and the 6A/3B ~725ms reference budget | Lower the reference budget's individual stage numbers to manufacture a smaller total (rejected — governing task explicitly forbids fabricating optimization gains); leave the target at <800ms unchanged (rejected — the governing task explicitly requires the stricter ≤750ms engineering target) | The existing ~725ms reference budget already satisfies ≤750ms with a small, honestly-labeled margin (§21.2) — no design change was needed to make the target plausible, only precise reconciliation and honest TARGET-vs-MEASURED labeling | Decided |
| ADR-6D-05 | The `/ws/v1/voice/calls/*` observation channel carries no call-control commands — every guarded state transition (terminate/transfer/hold/resume) is REST-only; WS reflects the resulting events | Allow WS-native call-control frames as a lower-latency alternative to REST for supervisor-initiated actions (rejected — call control is not on the ≤750ms hot path, so no latency benefit exists to justify a second command authority) | 6A §17.3's "two sources of truth" prohibition, applied to REST-vs-WS command duplication, not just API-vs-DB locking | Decided |
| ADR-6D-06 | Partial STT, LLM-delta, and per-turn-realtime events are WS-only and never routed through `audit.domain_event_outbox` | Route every domain event through the outbox uniformly for consistency (rejected — `077_5J1.sql`'s own header comment explicitly sizes the outbox for "a handful of event types," not per-turn volume; routing turn-level events through it would create the exact partitioning/volume problem the outbox's author deliberately avoided) | Respects the outbox's own documented design constraint rather than overloading it | Decided |
| ADR-6D-07 (amended this pass) | `from_number` on `POST /calls` is always server-resolved, never client-supplied — the client selects only an opaque `phone_number_id` (§10.2a, added this pass to close the original ADR's undefined selection mechanism when a tenant owns more than one eligible number) | Accept a client-supplied `from_number` and validate ownership server-side (rejected — an unnecessary attack surface for caller-ID-spoofing bugs); silently auto-pick "the first" eligible number with no client input at all (rejected — non-deterministic and unauditable for a genuinely multi-number tenant) | Structural prevention (never accept a raw number) plus explicit, opaque-ID-based selection when genuinely ambiguous is stronger and clearer than either full client control or silent server guessing | Decided |
| ADR-6D-09 (new this pass) | Realtime replay/resume uses a stable, per-`(organization_id, call_id)` `replay_cursor`, entirely separate from the per-connection `sequence` counter | Resume from the old connection's `sequence` value (the first draft's design — retracted: a closed connection's `sequence` namespace no longer exists, so this could never have worked); make `sequence` itself durable/cross-connection (rejected — conflates live-gap-detection with cross-reconnect resume, two concerns 6A §27.3 keeps separate) | `sequence` and `replay_cursor` answer different questions ("did I just miss something on this socket" vs. "where do I resume after reconnecting") and must not share one field | Decided |
| ADR-6D-10 (new this pass) | The Voice-domain audit `action_kind` vocabulary gap (former DEP-6D-04) is closed via a controlled, documentation-only amendment to 5J §14.3 (12 new `‡`-marked values), performed under this pass's explicit authorization | Leave the gap open and disclosed (rejected — this pass is explicitly authorized to perform the same class of amendment that resolved 6C's structurally identical gap); add a new `CHECK ... IN (...)` enum constraint while amending (rejected — an unrequested schema change; `chk_ae_action_kind` is deliberately a length check, not an enum) | Mirrors 6C's own proven, safe resolution pattern exactly — no SQL migration, twelve new governed strings an `INSERT` may legitimately use | Decided |
| ADR-6D-11 (new this pass) | A concurrent `AgentVersion` publish race is handled as a bounded, application-layer retry on Postgres `SQLSTATE 23505` (`unique_violation`), not as a "serialization failure" and not via `SELECT ... FOR UPDATE` | Describe/handle it as a `40001` serialization failure (retracted — this endpoint runs under READ COMMITTED, which cannot raise `40001`); add `SELECT ... FOR UPDATE` before the version-number computation (rejected — violates frozen 6A §17.3) | The database's actual behavior under the isolation level this design uses is `23505`, not `40001` — the wrong SQLSTATE would mislead an implementer's error-handling code | Decided |
| ADR-6D-12 (new this pass) | Recording deletion captures the pre-update `storage_ref` in the same CAS `UPDATE` (via a read-then-update CTE) and hands it to the async cleanup consumer through the existing `audit.domain_event_outbox`, internal-only, never exposed publicly | Clear `storage_ref` first and rely on a best-effort async job reading it "at some point after" (retracted — a crash between the clearing write and the cleanup job reading it could permanently orphan the S3 object); invent a new, dedicated storage-cleanup-job table (rejected — no such table exists in Phase 5; the already-existing, already-durable outbox is the minimal-change home) | A durable reference must exist before the only column holding it is nulled — capturing it atomically and handing it off through infrastructure already relied on elsewhere closes the gap with no new moving parts | Decided |
| ADR-6D-13 (new this pass) | Every 6D audit write is expressed as `SELECT audit.fn_insert_audit_event(...)` — never `INSERT INTO audit.audit_events` | Describe the write as a plain `INSERT` (the prior pass's own wording — **retracted**: `REVOKE ALL ON audit.audit_events FROM app_api, app_worker, app_readonly, app_platform_admin` means no application role can execute that statement at all, 5J §5/§14.2; a literal implementation of the prior wording would fail at runtime on every single mutation); grant `app_api`/`app_worker` a table-level INSERT on `audit.audit_events` to make the prior wording work (rejected — this would be an unauthorized Phase 5 privilege-model change, exactly the kind of edit this document has no authority to make) | `fn_insert_audit_event()` is 5J's own, already-frozen, already-correct answer to "how does an application write an audit event" — 6D's job is to consume it correctly, not to describe a shortcut around it | Decided |
| ADR-6D-14 (new this pass) | 5J §14.5's general "configuration/lifecycle changes → asynchronous" policy is amended with an explicit, named exception for 6D's Voice control-plane state-changing REST operations, which remain synchronous | Leave 6D's synchronous-audit requirement (§24.0) silently contradicting 5J §14.5's general table (rejected — an unresolved contradiction between two documents this platform treats as authoritative); reclassify Voice's own audit writes as asynchronous to match 5J §14.5's general row (rejected — 6A §22 requires durable audit for state-changing endpoints, and 6D's own hot-path analysis (§21.11) already establishes these operations are off the ≤750ms path, so there is no latency reason to weaken them to async) | Voice control-plane operations (Agent/Call/Tool/Recording/Phone-Number mutations) are configuration/lifecycle actions in 5J §14.5's own taxonomy, but they are also 6A §22-governed state-changing API commands with no hot-path latency constraint forcing asynchrony — the exception is narrow, named, and justified on exactly those two grounds | Decided |
| ADR-6D-15 (new this pass) | `audit.domain_event_outbox`'s "Consumed by" column (§24.2) never lists `Audit` as a consumer for any event | List `Audit` as a consumer wherever a mutation is audited (the prior pass's own wording — **retracted**: the authoritative audit record is already durably written via `fn_insert_audit_event()` in the *originating* transaction, before the outbox row is even inserted; listing `Audit` as an outbox consumer wrongly implies audit durability runs through Redis/a consumer, which §24.0 explicitly forbids) | The outbox's consumer list must describe only genuine cross-bounded-context propagation targets — conflating it with the (already-complete, already-synchronous) audit write is the exact ambiguity §24.0 exists to prevent | Decided |

---

## 38. OpenAPI / Realtime Contract Readiness

### 38.1 REST Surface

All 35 public + 2 internal endpoints (§28) are OpenAPI-ready per 6A §32.1's checklist: purpose, method+path, auth, authz permission string, path/query params, headers (incl. `Idempotency-Key` where applicable), request/response schemas, idempotency behavior, rate-limit class, latency tier, side effects/events, consistency behavior, audit `action_kind` (all 15 state-changing endpoints now cite an exact-match, governed value per §24.0's amendment — no endpoint's `action_kind` remains pending), example request/response. The two internal endpoints (§28.36–37) are excluded from the *public* OpenAPI document per 6A §8.5/6B §17.2's own rule, documented separately for internal-consumer reference only.

### 38.2 Realtime Surface

Not plain OpenAPI request/response routes, per the governing task's own framing — instead, §13 (connection contract) + §29 (28-message-type catalog, each with an explicit JSON payload shape) together constitute a complete, implementable specification: a client/server implementer needs no further design decision to build against this document. No realtime semantic is left to prose-only description without an accompanying schema (§29's tables are the schema).

---

## 39. Implementation Readiness

| Area | Ready? | Notes |
|---|---|---|
| REST endpoint contracts | Yes | §28, full depth on 3 showcases, compact-but-complete on the remaining 34 |
| Realtime contract | Yes | §13 (incl. the corrected §13.3/§13.7a replay-cursor contract), §14, §29 |
| Authorization | Yes | §25, DEP-6D-01/02/03 — re-verified against 5B's grant table this pass (Task K), one over-grant found and corrected (phone-number assignment, ADR-6D-08); nothing else blocking |
| **Audit coverage** | **Yes — resolved this pass; write path corrected this pass** | Former DEP-6D-04. All 15 of 15 state-changing endpoints now cite an exact-match, governed `action_kind` (5J §14.3, 12 new `‡` values), recorded synchronously via `audit.fn_insert_audit_event(...)` — never a direct `INSERT INTO audit.audit_events`, which no application role is privileged to execute (5J §5/§14.2) — and independently of the outbox/Redis (§24.0) |
| State machines / concurrency | Yes | §11, §30, ADR-6D-03; concurrent-publish handling corrected to the actual `23505` SQLSTATE (§9.2a, ADR-6D-11) |
| Latency architecture | Yes, as a design (not yet measured) | §21 — plausible, honestly labeled, benchmark plan named for Phase 23/24; unchanged by this pass |
| Compliance integration | Yes | §20 — consumes 6C's existing contract without modification |
| PII/security | Yes | §26, §33; recording deletion's durable cleanup handoff corrected this pass without any new public-facing exposure (§16.3a, ADR-6D-12) |
| Outbound caller-ID selection | Yes — closed this pass | §10.2a — deterministic, opaque `phone_number_id`, no invented schema column (ADR-6D-07, amended) |
| Observability cardinality | Yes — closed this pass | §32.2/§32.3 — every metric label re-checked against the document's own bounded-cardinality rule; two unbounded labels replaced/dropped (Task H) |

---

## 40. Final Approval Gate / Status

### 40.1 History — the Prior Correction Pass's Own Gate (superseded by §40.2, retained for the record)

The immediately prior correction pass evaluated a 19-condition gate and concluded all 19 passed, including condition 11 ("`audit.audit_events` is clearly separate from `audit.domain_event_outbox`"). **That pass's own resolution of condition 11 was itself defective** — it described the audit write as a direct `INSERT INTO audit.audit_events`, which is illegal under 5J §5/§14.2's `REVOKE ALL` grant model. This section's history is kept, not deleted, so the correction trail stays auditable; §40.2 is the current, authoritative gate.

### 40.2 This Pass's Gate — the Exact 10-Point Closure Check

| # | Condition | Result |
|---|---|---|
| 1 | 5J §14.3 still contains all 12 Voice `action_kind` values | **PASS** — unchanged by this pass; verified present, still `‡`-marked, in `5J-Analytics-Audit-Schema.md` §14.3 |
| 2 | 5J §14.5 explicitly documents the synchronous 6D Voice exception | **PASS — resolved this pass.** 5J §14.5 amended with a named, bounded exception for 6D's Voice control-plane state-changing REST operations, citing `audit.fn_insert_audit_event(...)` and 6A §22/hot-path (§21.11) as the reasons; the general Configuration/Campaign/Plugin row is otherwise unchanged |
| 3 | 6D contains ZERO application-level direct INSERT instructions for `audit.audit_events` | **PASS — resolved this pass.** Every occurrence in §9.2, §16.3a, §23.4, §24.0, and all 15 §28 mutation contracts corrected to `SELECT audit.fn_insert_audit_event(...)`; every remaining textual mention of "`INSERT INTO audit.audit_events`" in the document appears only inside an explicit "never do this" retraction, never as an instruction (verified by direct search, §36 DEP-6D-13) |
| 4 | Every 6D audit write uses `audit.fn_insert_audit_event(...)` | **PASS — resolved this pass.** Same fix as condition 3 — one canonical call form used uniformly |
| 5 | All 15 mutation endpoints have governed exact action kinds | **PASS — unchanged by this pass, re-verified.** Still 15/15, Category A, per the prior pass's DEP-6D-04 resolution — this pass changed only *how* each endpoint invokes the write, not *whether* it has a governed `action_kind` |
| 6 | Audit and outbox are clearly separate | **PASS — strengthened this pass.** §24.0's binding rules now additionally state that `audit.audit_events` accepts no direct INSERT from any application role while `audit.domain_event_outbox` does (5J/077) — a structural, not just conceptual, separation |
| 7 | §24.2 no longer claims the authoritative audit trail is created by an outbox/Redis consumer | **PASS — resolved this pass.** Every "Consumed by" cell in §24.2 that previously read `Audit` is corrected: agent/tool-definition lifecycle events now read "None currently; durable event retained for a defined future integration"; call-lifecycle events name only genuine future cross-context consumers (Analytics/Campaign/CRM/Billing, matching 4B §11.2's own catalogue minus Audit); `recording.deleted` names the recording-cleanup worker, with an explicit note that `RECORDING_DELETED` is already durably recorded via `fn_insert_audit_event()` before that worker ever runs (ADR-6D-15) |
| 8 | Recording deletion still has durable cleanup handoff | **PASS — unchanged by this pass, re-verified.** §16.3a's capture-then-clear CTE pattern is untouched in substance; only its audit-write line was corrected to the function call (condition 3) |
| 9 | ≤750ms hot-path architecture unchanged | **PASS.** §21 not touched by this pass, as instructed |
| 10 | No other frozen document changed | **PASS.** Only `5J-Analytics-Audit-Schema.md` (§14.5, the one authorized clarification) and `6D-Voice-Call-Agent-APIs.md` were edited — 6A, 6B, 6C, 5C, every SQL migration, and Alembic history are untouched (§41) |

**All 10 conditions PASS.**

This closure pass fixed exactly the three issues named in its governing task — an illegal direct-INSERT audit-write description (now uniformly `audit.fn_insert_audit_event(...)`), a latent contradiction between 5J §14.5's general async policy and 6D's own synchronous-audit requirement (now resolved by a named, bounded 5J exception), and an outbox consumer table that wrongly implied audit durability runs through Redis (now corrected to name only genuine cross-context consumers, with `RECORDING_DELETED` explicitly reaffirmed as already durably recorded before any outbox consumer runs). No other decision from that pass was reopened: DEP-6D-04's resolved status, the 15/15 audit-coverage count, the `replay_cursor` design, the `since_sequence` resync contract, Agent-publish tool revalidation, the `23505` bounded-retry design, `phone_number_id` outbound selection, the `agent:publish` phone-number-assignment permission, the recording-cleanup handoff's substance, the Prometheus cardinality corrections, and the ≤750ms/~725ms latency architecture all stood exactly as that pass left them.

### 40.3 This Pass — Final Editorial Closure

A subsequent, purely editorial pass corrected one remaining document-control inconsistency: the top-level **Document Control** table (§1) and **Hard Boundary** sentence still read "Nothing upstream. This document is additive only." and "does not modify Phase 5 (frozen)" — no longer literally accurate once the two authorized 5J amendments (§14.3, §14.5) existed. Both are corrected to name the two amendments explicitly and to state precisely that no Phase 5 schema, SQL migration, function, constraint, RLS policy, grant, index, or Alembic revision was touched. A full-document search for equivalent contradictory phrasing ("does not modify Phase 5," "Nothing upstream," "Phase 5 untouched," "5J untouched") found no other occurrence — §41's Confirmations already stated the two-amendment position accurately from the prior pass and required no change. **No API contract, WebSocket contract, audit `action_kind`, permission, DB/schema/migration/Alembic artifact, `replay_cursor` design, outbound phone-number design, recording-deletion design, or the ≤750ms/~725ms latency figures were touched by this editorial pass** — this was wording-only, confined to §1 and this subsection.

### PHASE 6D STATUS: **APPROVED / FROZEN**

With the document-control inconsistency corrected and no other open item remaining, Phase 6D is **APPROVED / FROZEN**, per the user's explicit direction in this closure pass. This does not retroactively resolve any of the remaining, already-documented non-blocking dependencies (DEP-6D-01/02/03/05–12) — they remain exactly as classified in §36, carried forward as disclosed, non-blocking residuals rather than closed items.

---

## 41. Confirmations

- **6A untouched.** No edit made to `6A-API-Architecture-and-Standards.md` this pass.
- **6B untouched.** No edit made to `6B-Authentication-and-Authorization-API.md` this pass.
- **6C untouched.** No edit made to `6C-Core-Platform-APIs.md` this pass.
- **Phase 5 — two explicitly authorized, controlled, documentation-only amendments; otherwise untouched.** `5J-Analytics-Audit-Schema.md` §14.3 received the (unchanged, prior-pass) 12 new `‡`-marked `action_kind` values. `5J-Analytics-Audit-Schema.md` §14.5 received this pass's own amendment: a named, bounded synchronous exception for 6D's 15 Voice control-plane operations, citing `audit.fn_insert_audit_event(...)` — no SQL migration, no schema/constraint/function change, and no change to the general Configuration/Campaign/Plugin/Billing rows for either amendment. No other edit was made to `5J` or to any other `phase-05-database-design/**` file — `5C-Voice-Schema.md`, every migration under `5K/migrations/`, and the Alembic history are all unmodified.
- **6E+ not started.** No Knowledge/RAG, Workflow, Prompt, Memory, CRM, Campaign, Billing, Integrations, or Analytics API design was performed in this document — §3.2's exclusion list is exhaustive and was checked against every section before writing it.
