## AI Voice Agent Platform — Phase 6 — API Design — Phase 6E

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6E — AI Agent APIs |
| Phase | 6 — API Design |
| Status | **CANDIDATE — APPROVED/FROZEN CANDIDATE** (see §41) — pending the user's independent review before final freeze. Reached via an initial draft and three correction passes. **Pass 1** fixed a false ToolDefinition-namespace threat-model claim, an overstated tool-deactivate/publish transactional guarantee, an underspecified `ProviderConfig`/`LanguageEvaluationRecord` resolution rule, an overstated `qualification_criteria` secret-safety claim, an unhandled FR-TEN-005 quota-traceability gap, and imprecise 6D→6E relationship wording (§41.1). **Pass 2** fixed three genuine internal contradictions Pass 1 introduced: (a) §11.4 had conflated 6E's provider-existence check with 6D's `circuit_state`-filtered runtime-routability query, making an `OPEN`-circuit provider fail existence before its own `WARNING` rule could fire; (b) §15.6 had reused 5C §15.12's `verdict`-filtered, `provider_id`-agnostic reference-list query for publish validation, making `REJECTED` structurally undetectable and provider-specific lookups impossible; (c) publish-time provider-capability validation had been claimed generically across STT/TTS/LLM despite Agent config never identifying a specific STT/TTS provider. Pass 2 also retracted an unsupported `qualification_criteria` input-validation rule and narrowed an overstated PostgreSQL NULL-semantics ordering claim (§41.2). **Pass 3 (this revision, micro-correction)** fixed one remaining implementation-level inconsistency Pass 2's new §11.4 query (A) left behind: it omitted `supports_languages` (needed by §15.4 rule #12) and `LIMIT 1` (leaving "the resolved row" ambiguous relative to rule #5's own result) — both are added, with no `WHERE`/`ORDER BY`/schema change. See §41.2a for this pass's exact closure check. |
| Author | karthi (karthimadan2003@gmail.com) |
| Date | 2026-08-23 (initial draft); 2026-08-23 (correction pass 1); 2026-08-23 (correction pass 2); 2026-08-23 (correction pass 3, this revision) |
| Depends on (frozen) | Phase 1 SRS; Phase 2 HLA; Phase 3A/3B/3D/3E LLD; Phase 4A/4B/4E/4G/4H/4I DDD; Phase 5A/5B/5C/5F/5G/5J DB Design (unmodified); Phase 5K migrations 001–077 (unmodified); Phase 6A, 6B, 6C, 6D (unmodified, in full) |
| Modifies | **Nothing.** No Phase 5 schema, SQL migration, function, constraint, RLS policy, grant, index, or Alembic revision is touched. No 5J amendment is required — every audit `action_kind` and the synchronous-audit exception 6E's mutations need already exist, added by 6D's own already-authorized `‡` amendment (§25 of this document explains why no further amendment is needed). 6A, 6B, 6C, and 6D are read as authoritative and **not edited** anywhere in this document. |
| Hard boundary | This document is the authoritative **AI Agent management API** design: Agent CRUD, Agent draft configuration (VoiceConfig, ModelConfig, LanguagePolicy, tool permissions, opaque references, qualification criteria, calling hours), Agent validation, Agent publish/deprecate/clone lifecycle, AgentVersion read access, Tool Definition management (reconciled from 6D — §21), and Agent-configuration-adjacent reference data (Provider health, Language Evaluation Records — reconciled from 6D — §20). It does **not** design Call/Conversation/Turn/Recording/Transcript/realtime-WebSocket/barge-in/Tenant-Phone-Number APIs — those remain 6D's authoritative territory, consumed here only by reference (§5). It does not design Knowledge/RAG, Workflow, Prompt Management, CRM, Campaign, Billing, Integrations, or Analytics APIs — Agent configuration may hold opaque references into those contexts, never CRUD for them (§14). It does not begin 6F or any later Phase 6 document. |

---

## 2. Purpose

Phase 6D was built and frozen under the working title "Voice, Calls, Conversations & AI Agent APIs" — at the time it was written, no later document existed to own Agent management, so 6D necessarily designed the Agent CRUD/lifecycle/versioning surface itself, alongside the Call/Conversation/Voice-runtime surface that is 6D's true, permanent center of gravity. The authoritative Phase 6 sequence now names an explicit successor — **6E — AI Agent APIs** — and this document is that successor.

6E's purpose is narrow and precise: **make 6D's existing Agent-management contract authoritative under 6E's name, going forward**, without reopening, rewriting, or contradicting a single line of frozen 6D. Concretely, this document:

1. **Reconciles ownership** (§5–§6): draws the exact boundary between Agent *management* (6E) and Voice/Call *runtime consumption* of a published AgentVersion (6D remains authoritative there, unchanged).
2. **Preserves 6D's existing contract and adds explicitly disclosed refinements on top of it** (§8, §16–§19, §30): 6D's paths, resource-ownership origins, permission strings, lifecycle states, persistence invariants, and runtime-pinning semantics are preserved exactly. This is **not** a claim that every behavior is byte-for-byte identical — 6E introduces a small number of additive validation and concurrency clarifications, precisely enumerated in item 3 below and never described elsewhere in this document as "verbatim" or "zero behavior change."
3. **Extends** 6D's Agent validation model with an explicit **ERROR vs. WARNING** classification (§15) that 6D's frozen text implied but never formalized, and with disclosed, additive validation and concurrency refinements 6D's frozen text left underspecified: duplicate tool permissions (§13.3), fallback-provider ordering (§15.4), language-policy semantic consistency (§12.2), deterministic provider/evaluation-record resolution (§11.4, §15.5), a cross-scope tool-name-uniqueness invariant (§21.2a), an honest secret-safety caveat for `qualification_criteria` (§9.4), an optional `If-Match` precondition on publish (§16.6), and a precise (not overstated) tool-deactivate-vs-publish transactional guarantee (§15.2). None of these contradicts a stated 6D behavior — each closes an area 6D's frozen text left silent.
4. **Moves two resource groups from 6D's authority to 6E's**, per the governing task's explicit direction, because both are primarily Agent-configuration reference data rather than Call-runtime data: **Tool Definition management** (§21) and **Provider-health / Language-Evaluation reference data** (§20). In both cases the endpoint paths, permissions, and audit vocabulary are reproduced unchanged; §21's Tool Definition CRUD additionally gains the one new cross-scope name-uniqueness validation rule named in item 3.
5. **Restates, unaltered**, every binding runtime invariant 6D already established that 6E's design must not violate: AgentVersion immutability (DDR-4B-003), pinning of `agent_version_id` at call start, no Agent REST call on the Voice hot path, and the frozen ≤750ms p50 / ~725ms reference budget / <800ms NFR-PERF-001 ceiling (§22).
6. **Discloses every genuine gap** this reconciliation surfaces — in the DDD/DB layer, in the permission catalog, and in product-desired-but-undesigned capability (Agent preview/test) — as a named `DEP-6E-XX`, rather than silently inventing a resolution (§38).

Secondary purpose, in the same order 6B/6C/6D established: give the platform's Agent Builder / Prompt Engineer persona (SRS actor, `product/PRODUCT_VISION.md`, NFR-USAB-001 — "usable by non-technical Agent Builders to construct a working agent without writing code") a complete, strongly-typed, safe-by-construction configuration API — one that cannot silently publish an unusable or dangerous Agent, and that structurally prevents a secret from entering an immutable, permanently-frozen version snapshot through every closed-shape configuration field, with a disclosed, evidence-grounded mitigation (not an absolute guarantee) for the one field that remains genuinely open-ended (`qualification_criteria`, §9.4/§28.3).

---

## 3. Scope / Hard Boundary

### 3.1 In Scope

- Agent aggregate CRUD: create, list, get, update draft configuration.
- Agent lifecycle action endpoints: publish, deprecate, clone.
- AgentVersion read access: list versions, get one version's immutable snapshot.
- The full typed Agent draft-configuration contract: `VoiceConfig`, `ModelConfig`, `LanguagePolicy`, `ToolPermissions`, opaque references (`prompt_ref`, `workflow_ref`, `knowledge_base_refs`), `QualificationCriteria`, `CallingHours`.
- Agent validation: continuous (PATCH-time, structural) and full (publish-time, structural + semantic + tool re-verification), with an explicit ERROR/WARNING classification.
- Tool Definition management (reconciled from 6D — tenant custom-tool CRUD, platform built-ins read-only).
- Provider-health and Language-Evaluation-Record reference data, read-only (reconciled from 6D).
- Authorization, audit, PII, concurrency, observability, and test strategy for all of the above.

### 3.2 Explicitly Out of Scope (named, not silently absorbed)

| Context | Why excluded | Where it belongs |
|---|---|---|
| Call lifecycle, control actions, inbound/outbound boundary | 6D's permanent, primary subject | 6D (frozen) |
| Conversation / Turn observation | 6D's permanent, primary subject | 6D (frozen) |
| Realtime `/ws/v1/voice/...` contract, barge-in observability | 6D's permanent, primary subject | 6D (frozen) |
| Recording, Transcript | 6D's permanent, primary subject | 6D (frozen) |
| Tool Execution (runtime observation, tied to Turn/Conversation) | Remains 6D's — a different aggregate from Tool Definition (DDR-4B-004); its lifecycle is driven by the in-process turn loop, not Agent configuration | 6D (frozen) |
| Tenant Phone Number (read + agent-assignment) | Call-routing configuration, not Agent configuration; `assign-agent` references an Agent but is a phone-number-resource action, not an Agent-resource action | 6D (frozen) |
| Provider *routing/failover runtime* behavior (Model Router, circuit breakers) | 6D's permanent Voice-runtime subject; only the **read-only reference data view** moves to 6E (§20) | 6D (frozen) |
| Knowledge Base / RAG | 4B/6D consume it via a port/opaque reference; 6E does not design ingestion/search | 6F |
| Workflow Engine | 4B/6D consume it via a port/opaque reference; 6E does not design graph/node endpoints | 6I |
| Prompt Management | 4B/6D consume it via a port/opaque reference; 6E does not design prompt CRUD/versioning | Later phase (not yet numbered in the authoritative sequence) |
| CRM, Campaign, Billing, Integrations, Analytics, Admin | Consumed via domain events only; no CRUD designed here | 6G, 6H, 6K, 6J, 6L, 6M |

Per the governing instruction, this document does not absorb any of the above merely because Agent configuration references them.

### 3.3 Hard Boundary — What This Document Does Not Modify

No edit is made to: the SRS; Phase 2; Phase 3; Phase 4; any Phase 5 schema, migration, function, RLS policy, grant, or Alembic revision; 6A; 6B; 6C; or 6D. No 6F work (Knowledge Base API, RAG retrieval, CRM, Campaign, Workflow, Prompt Management, Integrations, Billing, Analytics, or Admin API) is performed. No implementation code (FastAPI routers, Pydantic classes, SQLAlchemy models, repositories, Redis code, provider adapters, migrations, Alembic revisions) is produced — this is an API-design document only.

---

## 4. Governing Documents

**Product/Requirements:** `product/PRODUCT_VISION.md`, `product/ARCHITECTURE_PRINCIPLES.md`, `product/TECH_STACK.md`, `product/PROJECT_ROADMAP.md`, `phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` (FR-LLM-001/002, FR-TTS-002, FR-TEN-005, FR-RAG-005 boundary, NFR-USAB-001, NFR-PERF-001 — consumed, not redefined).

**Architecture:** `phase-02-high-level-architecture/HIGH_LEVEL_ARCHITECTURE.md`.

**LLD:** `3A-Platform-Architecture.md`, `3B-Voice-Platform.md` (primary — Agent-adjacent runtime sections), `3D-Workflow-RAG.md` (consulted only where Agent config references Workflow/Prompt/KB), `3E-Platform-Services.md`.

**DDD:** `4A-Core-Domains.md`, `4B-Voice-AI-Domain.md` (primary — §5.3 Agent Aggregate, §5.4 ToolDefinition Aggregate, §7.3 Agent Lifecycle, §11.4 Agent Events, §12.3 Agent Commands, DDR-4B-003/004), `4E-Knowledge-RAG-Workflow-Tools.md` (opaque-reference boundary only), `4G-Analytics-Cross-Domain-Context-Map.md`, `4H-Final-Architecture-Review.md`, `4I-India-First-Decision-Closure.md` (§4.2 LanguagePolicy, §4.4 Tamil-First Language Evaluation Framework, CONTRADICTION-02).

**Database:** `5A-Database-Architecture-and-Standards.md`, `5B-Identity-Organization-Multitenancy-Security.md` (§17.2 permission catalog — primary), `5C-Voice-Schema.md` (§5.4–5.6, §5.11–5.12 — primary), `5F-Knowledge-RAG-Schema.md` / `5G-Workflow-Prompt-Memory-Schema.md` (opaque-reference-ownership boundary only), `5J-Analytics-Audit-Schema.md` (§14.2–14.5 audit vocabulary and synchrony — primary), `5K/EXECUTION_REPORT.md`, `5K/MIGRATION_MANIFEST.md`, migrations `013` (tool_definitions), `016`–`017` (agents/agent_versions), `076_5K1.sql`, `077_5J1.sql`.

**Frozen Phase 6:** `6A-API-Architecture-and-Standards.md` (binding cross-cutting standards — §8.3 action endpoints, §14 pagination, §16 idempotency, §17 concurrency/ETag, §22 security, §35 transaction exceptions — reused verbatim), `6B-Authentication-and-Authorization-API.md` (§16 API-key scoping, §17 internal-service auth — consumed as-is), `6C-Core-Platform-APIs.md` (resource-ownership-matrix and dependency-register conventions reused), `6D-Voice-Call-Agent-APIs.md` (**the primary source this document reconciles** — §8–9, §18–19, §15, §24–28, §30, §36–37, §40).

All are treated as authoritative and unmodified by this document.

---

## 5. 6D/6E Ownership Reconciliation

### 5.1 Why 6D Owned Agent Endpoints in the First Place

6D §2 records that it was the first bounded-context API document written after 6C, and took "the first-listed, foundationally-required context: Voice & AI (4B)" as a whole — because no 6E existed yet to split Agent management out. 6D's own §3.2 already anticipated a future split for Knowledge/Workflow/Prompt/Memory ("6E+"), but did not anticipate that Agent management itself, as opposed to Call/Conversation/Voice-runtime, would eventually get its own document. The authoritative Phase 6 sequence now makes that split explicit and names it 6E.

### 5.2 The Boundary, Stated Once, Binding for the Rest of This Document

```
PHASE 6D OWNS (unchanged, not reopened):
  Voice runtime · Call lifecycle · Conversation/Turn observation
  Realtime WS voice/call behavior · barge-in · recording/transcript voice surface
  How a Call consumes a published AgentVersion · AgentVersion pinning at call start
  Runtime use of Agent VoiceConfig/ModelConfig/LanguagePolicy
  Voice-side provider routing and failover (runtime behavior, not reference data)
  Voice hot-path latency (≤750ms p50 target, §22)
  Tenant Phone Number (read + agent-assignment)
  Tool Execution (runtime observation)

PHASE 6E OWNS (this document, authoritative going forward):
  AI Agent management API · Agent configuration API · Agent draft lifecycle
  Agent validation · AgentVersion management API · publish/deprecate lifecycle · cloning
  Agent configuration references (format-validated, opaque)
  AI model/voice/language configuration (management surface, not runtime)
  Agent tool-permission configuration
  Tool Definition management (reconciled from 6D, §21)
  Provider-health / Language-Evaluation reference data (reconciled from 6D, §20)
  Agent API authorization/audit/events · Agent management concurrency/idempotency
```

### 5.3 Reconciliation Method Applied to Every Overlapping Endpoint

For every endpoint 6D already defines that this document now treats as 6E-authoritative, the method is: (1) reproduce the path, permission, and audit `action_kind` **exactly as 6D froze them** — zero silent renames, zero contradiction of a behavior 6D's frozen text actually states; (2) where this document's own validation model (§15) adds a check 6D's frozen text did not explicitly specify, disclose it explicitly as a **6E refinement** (additive tightening of an area 6D left underspecified — this document does not describe such refinements as "verbatim" or "unchanged," since they are genuinely new normative behavior, only as non-contradicting); (3) where a genuine conflict exists between 4B/5C and 6D's operational description, prefer 6D's later, frozen reconciliation and record the finding (§5.4); (4) never edit `6D-Voice-Call-Agent-APIs.md` itself — its historical text remains accurate as the origin of these contracts, while this document is the forward reference. **Precise scope of "preserved unchanged":** 6D's paths, resource-ownership origins, permission strings, lifecycle states (`DRAFT`/`PUBLISHED`/`DEPRECATED`), persistence invariants (AgentVersion immutability), and runtime-pinning semantics are preserved exactly. Request/response *shape* is preserved except where §7.3 names an explicit, additive extension (the `warnings[]` field on publish's response, and the one new tool-name-uniqueness validation rule on Tool Definition create/rename) — those extensions are called out individually wherever they appear, never folded silently into a blanket "unchanged" claim.

### 5.4 Source Reconciliation Findings (verified before writing an endpoint, per the same discipline 6D §5 and 6C §5 applied)

| # | Question | Finding | Resolution |
|---|---|---|---|
| 1 | Does 4B §7.3's Agent lifecycle diagram (`PUBLISHED --> DRAFT: UpdateDraftConfig`) match 6D's operational description of `PATCH /agents/{id}`? | **Apparent conflict, resolved in favor of the later frozen text.** 4B's mermaid diagram shows editing the draft config while `PUBLISHED` transitions `status` back to `DRAFT`. 6D §9.2 step 1 explicitly frames "re-publishing a currently-published agent with new draft edits" as "the normal 'ship an update' flow" — coherent only if `status` **remains `PUBLISHED`** while draft edits accumulate (otherwise the publish guard's "or `PUBLISHED`" branch would be unreachable after any edit). 6D §8.4 additionally states, as an absolute rule, that `status` "transitions only via publish/deprecate action endpoints... guarded transitions never ride a free-form PATCH." | Per the governing reconciliation rule (prefer the later approved/frozen text; do not invent a third interpretation): **`PATCH /agents/{id}` never changes `status`.** An Agent may be `PUBLISHED` with a modified, not-yet-published `draft_config` sitting alongside its current `published_version_id` — the next `publish()` call snapshots that modified draft. 4B's diagram is stale illustrative text superseded by 6D's binding operational contract, exactly as 4I §CONTRADICTION-02 already superseded 4B's `TamilCodeSwitching` boolean with 5C's `language_policy` JSONB. No 6E endpoint behavior is left undefined by this finding — it is recorded here for auditability, not as a blocking `DEP-6E`. |
| 2 | Does 4B §12.3's `UpdateDraftConfig` command signature (which lists `voice_config`, `model_config`, `prompt_ref`, `workflow_ref`, `knowledge_base_refs`, `tool_permissions`, `qualification_criteria`, `calling_hours`, but no `language_policy` parameter) omit `LanguagePolicy` from the draft-config allow-list? | No — this is an artifact of sequencing, not a real gap. 4B's command predates 4I's `CONTRADICTION-02` correction, which retired `VoiceConfig.TamilCodeSwitching` in favor of the richer `LanguagePolicy` value object, later materialized in 5C §5.4's `draft_config` JSONB structure (`language_policy` as a top-level key, verified directly against the schema, §10). | 5C (later, frozen) is authoritative for the exact set of editable top-level keys. `language_policy` **is** part of the typed allow-list (§9), exactly as 6D §8.2 already treats it. No new finding beyond what 6D already resolved. |
| 3 | Does 6D's own Resource Ownership Matrix (its §6, row 9) classify `voice.tool_definitions` as "OWNED BY 6D"? | Yes, verbatim: *"Tenant custom tools are CRUD-able, platform built-ins are read-only."* This document reclassifies the same table as **OWNED BY 6E** (§6, §21), per the governing task's explicit instruction to evaluate Tool Definition ownership and its explicit framing of tool permission configuration as Agent-configuration-adjacent. | Not a contradiction of 6D's *content* (the endpoints, permissions, and audit kinds are unchanged) — a reclassification of *authoritative-document ownership only*, exactly the same class of change already applied to the Agent aggregate itself. §21 states the full rationale and the "do not duplicate paths" guarantee. |
| 4 | Does 6D's own Resource Ownership Matrix (its §6, row 11) classify `voice.provider_configs` as split between "READ-ONLY PROJECTION" and "DEFERRED"? | Yes. The governing task for this document explicitly lists `voice.provider_configs` and `voice.language_evaluation_records` among 6E's **primary grounding tables**, with the stated rationale that both are "primarily used while configuring Agent STT/TTS/LLM capability." | The **read-only reference-data view** (`GET /provider-health`, `GET /language-evaluations`) moves to 6E (§20); the **deferred tenant-credential/priority-CRUD** half (6D's `DEP-6D-06`) remains deferred, unchanged, inherited as `DEP-6E-10`/`DEP-6E-11` (§38) — no new capability is designed for either document by this move. |

---

## 6. Resource Ownership Matrix

Extends 6D §6's matrix. Every row is one of: **OWNED BY 6E**, **READ-ONLY PROJECTION**, **INTERNAL ONLY**, **DEFERRED TO LATER PHASE**, or **NOT EXPOSED**.

| # | Resource (4B aggregate / 5C table) | Classification | Rationale |
|---|---|---|---|
| 1 | AI Agent (`voice.agents`) | **OWNED BY 6E** | Management authority moves here per §5; 4B §5.3 AggregateRoot |
| 2 | Agent Version (`voice.agent_versions`) | **OWNED BY 6E (read-only after creation)** | Created only as a side effect of `publish` (§16); never directly mutable — DDR-4B-003, 5C §11.6 trigger |
| 3 | Published-version resolution for call start | **INTERNAL ONLY — unchanged from 6D** | `CallRoutingService.resolve()` (4B §8.1) runs in-process inside the same modular-monolith deployable — never a public or internal HTTP hop. 6E introduces no new access path to this (§22). |
| 4 | Tool Definition (`voice.tool_definitions`) | **OWNED BY 6E** | Reclassified from 6D (§5.4 finding #3, §21) — Agent-configuration-adjacent; endpoints/permissions/audit unchanged |
| 5 | Tool Execution (`voice.tool_executions`) | **REMAINS 6D-OWNED — READ-ONLY PROJECTION** | DDR-4B-004 — a separate aggregate with its own runtime lifecycle, tied to Turn/Conversation, not Agent configuration; 6E does not touch it |
| 6 | Provider Configuration (`voice.provider_configs`) | **OWNED BY 6E (read-only reference-data view)** + **DEFERRED** (tenant credential/priority CRUD — inherited `DEP-6D-06` → `DEP-6E-10`) | Reclassified per §5.4 finding #4; runtime routing/failover behavior remains 6D's |
| 7 | Language Evaluation Record (`voice.language_evaluation_records`) | **OWNED BY 6E — read-only** | Reclassified from 6D §6 row 13, per the governing task's explicit preference (§20) |
| 8 | Call / Call Session (`voice.call_sessions`) | **NOT OWNED — referenced only** | 6D-owned; 6E reads nothing from it directly, references it only conceptually (a Call pins one `agent_version_id`, §22) |
| 9 | Conversation / Turn | **NOT OWNED** | 6D-owned in full |
| 10 | Recording / Transcript | **NOT OWNED** | 6D-owned in full |
| 11 | Tenant Phone Number (`voice.tenant_phone_numbers`) | **NOT OWNED** | 6D-owned in full — `assign-agent` references an Agent but is a phone-number-resource action |
| 12 | Realtime `/ws/v1/voice/...` surface | **NOT OWNED** | 6D-owned in full |
| 13 | Compliance Policy | **NOT OWNED — not consumed by 6E** | 6C-owned; 6D consumes it at call initiation; 6E's `calling_hours` field is Agent-level configuration only, never cross-checked against `CompliancePolicy` at publish time (that check happens at call start, 6D §10.5, outside 6E's scope) |
| 14 | Prompt Management, Workflow Engine, Knowledge Base, Conversation Memory | **NOT EXPOSED / DEFERRED TO LATER PHASE** | Consumed via opaque, format-validated-only references (§14) — no CRUD, no existence validation, no synchronous cross-context call |
| 15 | CRM, Campaign, Billing, Integrations, Analytics, Admin | **NOT EXPOSED / DEFERRED TO LATER PHASE** | Per §3.2 |

---

## 7. AI Agent Architecture Overview

### 7.1 Where 6E Sits in the Two-Surface Architecture

6D §7.1 already establishes that Voice runs as two cooperating pieces of one modular monolith — the tenant-facing Core API and the realtime Voice Gateway — sharing one PostgreSQL/Redis substrate with no HTTP hop between them. 6E's entire endpoint surface lives on the **Core API** side, and every one of its endpoints is a Tier A (read) or Tier B (operational, action-endpoint) request per 6A §11 — **none of them is ever on the voice-turn hot path** (§22 makes this a binding, restated constraint).

```
┌──────────────────────────────────────────────┐        ┌────────────────────────────┐
│   Core API (tenant REST)                      │        │   Voice Gateway (realtime) │
│   /api/v1/agents             ← 6E (this doc)  │        │   (unchanged — 6D)         │
│   /api/v1/agents/{id}/versions ← 6E            │        │                            │
│   /api/v1/tools              ← 6E (moved)      │        │   Voice Orchestrator reads │
│   /api/v1/provider-health    ← 6E (moved)      │        │   AgentVersion.snapshot_   │
│   /api/v1/language-evaluations ← 6E (moved)    │        │   json ONCE per call, via  │
│   /api/v1/calls, /conversations, ...  ← 6D     │────────┤   CallRoutingService.      │
│   /ws/v1/voice/...            ← 6D             │        │   resolve() — in-process,  │
└──────────────────────────────────────────────┘        │   never an HTTP call to    │
                                                           │   any 6E endpoint          │
                                                           └────────────────────────────┘
```

### 7.2 The Agent Aggregate, Restated From 4B §5.3 (unchanged)

An `Agent` has a mutable `draft_config` (editable at will via PATCH) and a bounded (~<50 per agent) list of immutable, versioned `AgentVersion` snapshots, created only as a side effect of `publish()`. `status ∈ {DRAFT, PUBLISHED, DEPRECATED}` — the exact three values 5C's `chk_agents_status` CHECK constraint enforces, and no others (§17 restates why no `PAUSED`/`ARCHIVED`/`DISABLED`/`ACTIVE` state is invented).

### 7.3 What 6E Adds Beyond Reproducing 6D

1. A formal **ERROR vs. WARNING** validation classification (§15) — 6D's frozen text always described publish validation as pass/fail, never distinguishing a hard invariant violation from an advisory quality signal.
2. Three disclosed, additive validation refinements 6D's frozen text did not specify either way: duplicate `tool_permissions` entries, `fallback_providers` ordering/duplicate-reference checks, and `LanguagePolicy` internal-consistency checks (§15.4).
3. An optional `If-Match` precondition on `POST /agents/{id}/publish` (§16.6) — a backward-compatible refinement (omitting the header behaves exactly as 6D specified) that lets a caller assert "publish exactly the draft state I last read," using the same weak-ETag mechanism 6A §17.2 already defines for PATCH.
4. Ownership and a single authoritative home for Tool Definition management and Provider/Language reference data (§20–§21), closing the "who do I ask" ambiguity a reader of 6D alone would have once 6E exists.

---

## 8. Agent Aggregate API

### 8.1 Grounding

`Agent` — AggregateRoot, 4B §5.3; table `voice.agents` (5C §5.4) + `voice.agent_versions` (5C §5.5). Reproduced from 6D §8.1, unchanged.

### 8.2 Endpoints (full contracts in §30)

| Endpoint | Purpose | Origin |
|---|---|---|
| `POST /api/v1/agents` | Create a new Agent in `DRAFT` | Adopted from 6D §28.1, unchanged |
| `GET /api/v1/agents` | List agents (paginated, filterable by `status`) | Adopted from 6D §28.2, unchanged |
| `GET /api/v1/agents/{agent_id}` | Get one agent (draft config + status + published version pointer) | Adopted from 6D §28.3, unchanged |
| `PATCH /api/v1/agents/{agent_id}` | Update draft-config fields (§9 allow-list) | Adopted from 6D §28.4; validation extended per §15.4 |
| `POST /api/v1/agents/{agent_id}/publish` | Snapshot `draft_config` into a new immutable `AgentVersion` (§16) | Adopted from 6D §28.5; optional `If-Match` added per §16.6 |
| `POST /api/v1/agents/{agent_id}/deprecate` | `PUBLISHED → DEPRECATED` (§19) | Adopted from 6D §28.6, unchanged |
| `POST /api/v1/agents/{agent_id}/clone` | Create a new `DRAFT` Agent copying `draft_config` (§18) | Adopted from 6D §28.7, unchanged |
| `GET /api/v1/agents/{agent_id}/versions` | List versions, newest first (§17) | Adopted from 6D §28.8, unchanged |
| `GET /api/v1/agents/{agent_id}/versions/{version_id}` | Get one version's immutable snapshot (§17) | Adopted from 6D §28.9, unchanged |

### 8.3 What Is Never Exposed (restated, binding, unchanged from 6D §8.4)

- Direct mutation of `voice.agent_versions.snapshot_json` — enforced twice: no 6E endpoint routes a write to it outside `publish`, and 5C §11.6's `BEFORE UPDATE` trigger rejects any attempted change regardless.
- A generic `PATCH /agents/{id}` that accepts a `status`, `published_version_id`, `organization_id`, `deleted_at`, `created_at`, or `updated_at` field — every request schema in this document uses Pydantic-style `extra="forbid"` semantics (6A §22) plus an explicit allow-list (§9) that structurally excludes these six fields from ever being client-writable. `status` transitions only via `publish`/`deprecate` (§5.4 finding #1).
- Cross-tenant agent or tool references — `tool_permissions[].tool_id` validation is tenant-scoped (own tools + platform built-ins only, §13); an Agent can never reference another tenant's custom tool.

### 8.4 Agent Create — What the Request Accepts, and Why

Per the governing task's explicit instruction to ground this in the actual frozen model rather than invent a larger object: `CreateAgent` (4B §12.3) takes exactly `tenant_id` (implicit, from JWT/API-key), `name`, `description`, `created_by` (implicit, from actor). 6D §28.1 reproduces this precisely: `POST /agents` accepts `{ "name", "description"? }` only — `draft_config` starts at 5C's documented default, `'{}'` (empty JSONB object).

**Why an empty default `draft_config` is safe, not merely convenient:** an Agent created this way cannot be published — §15's publish-time validation requires `voice_config.language`, `voice_config.voice_id`, and `language_policy.primary_language` to be present and valid, none of which exist in an empty object. `POST /agents/{id}/publish` against a freshly-created Agent therefore deterministically fails `422 VALIDATION_ERROR` until the tenant populates the required fields via `PATCH`. This is the "safe default" the governing task requires: the platform never silently creates a *publishable-but-broken* Agent — it creates an honestly-incomplete `DRAFT` that structurally cannot go live until it is actually configured. No 6E endpoint auto-publishes on creation (4B §7.3's `[*] --> DRAFT` transition is the only creation-time state; `PublishAgent` is a separate, explicit command).

### 8.5 Concurrency / Idempotency Summary (full analysis in §32)

`POST /agents` accepts an optional `Idempotency-Key` (not required — 6A §16.1's "dangerous side effect" bar is not met by creating an extra `DRAFT` row, matching 6D §28.1's own reasoning). `PATCH` uses a weak ETag / `If-Match` (6A §17.2, ADR-6A-08). `publish` uses the bounded `23505` retry (§16.4). `deprecate`/`clone` rely on their own guard conditions being naturally idempotent-safe on retry.

---

## 9. Agent Draft Configuration

### 9.1 A Fully Typed, Allow-Listed Contract — Never a Generic JSON Bag at the API Boundary

Matches 5C §5.4's documented `draft_config` JSONB structure exactly (verified directly against the schema, §4). Every field below is individually typed and validated in the request schema, even though the column itself is stored as one JSONB blob:

| Field | Type | Validation | Source |
|---|---|---|---|
| `name` | string | 2–100 chars (5C `chk_agents_name_len`) | 5C §5.4 |
| `description` | string, nullable | 0–500 chars | 5C §5.4 |
| `voice_config.*` | object | §10 | 5C §5.4, 4B §5.3.1 |
| `model_config.*` | object | §11 | 5C §5.4, 4B §5.3.2 |
| `language_policy.*` | object | §12 | 5C §5.4/§5.5, 4I §4.2 (CONTRADICTION-02) |
| `prompt_ref` | UUID, nullable | Format-validated only, §14 | 4B §5.3 |
| `workflow_ref` | UUID, nullable | Format-validated only, §14 | 4B §5.3 |
| `knowledge_base_refs` | UUID[], nullable | Format-validated only, §14 | 4B §5.3 |
| `tool_permissions` | array of `{tool_id, tool_name}` | §13 — the one reference field 6E validates against its own data | 4B §5.3 invariant 4 |
| `qualification_criteria` | object, nullable | Structured JSON-Schema-shaped object; no fixed schema imposed (4B leaves this open) — **the one field in this table without a closed shape; see §9.4's secret-safety caveat** | 4B §5.3 |
| `calling_hours` | object, nullable | `TimeWindow` structure | 4B §5.3 |

### 9.2 Mass-Assignment Prevention — Binding, Restated

The following fields are **never** accepted in any `POST`/`PATCH` request body for this aggregate, structurally (schema-level `extra="forbid"` plus omission from every allow-list, 6A §22): `status`, `published_version_id`, `organization_id`, `deleted_at`, `created_at`, `updated_at`. A request body containing any of these is rejected `422 VALIDATION_ERROR` naming the offending field — never silently ignored, so a client relying on one of these fields being writable fails loudly rather than being quietly misled.

### 9.3 What Changed From 6D's Original Framing — Nothing Structural

6D §8.2 already documents this exact table (voice_config/model_config/language_policy/prompt_ref/workflow_ref/knowledge_base_refs/tool_permissions/qualification_criteria/calling_hours). This section reproduces it as 6E's authoritative allow-list going forward; §10–§14 give each sub-object its own dedicated section with the ERROR/WARNING validation classification §15 formalizes.

### 9.4 `qualification_criteria` — The One Open-Ended Field, and Its Secret-Safety Caveat (corrected this pass)

**The gap this subsection closes:** every other field in §9.1's table has a closed shape — a fixed set of typed keys, an enum, a number range, or a UUID. `qualification_criteria` is the sole exception: 4B §5.3 describes it only as "nullable structured criteria" with no further value-object definition anywhere in Phase 1–5 (verified directly — 4B §12.3's `UpdateDraftConfig` command types it as a plain `dict | None`; 5C §5.4's `draft_config` example shows `"qualification_criteria": null`; 4C §1's Ubiquitous Language glossary describes it only as "the agent-configured rules... stored on the Agent (Phase 4B)," and 4D §4's Campaign aggregate lists it as "forwarded to Agent; owned by Phase 4B" — every context that touches it treats it as an opaque, Agent-owned structure, and none of them defines its internal shape). Because it is a genuinely free-form nested JSON object, **this document does not claim that a secret-shaped value is structurally incapable of entering `qualification_criteria`** — unlike every other `draft_config` field, arbitrary keys and values are syntactically legal here.

**What a prior version of this document did — retracted, not merely softened:** it introduced a publish/PATCH-time `422 VALIDATION_ERROR` rejection rule for any key name containing `token`/`password`/`secret`/`credential`, citing 6A §22's PII redaction vocabulary as authorization. On direct re-review, **that citation does not support that rule.** 6A §22's row is titled "PII minimization / redaction" and its own text scopes it explicitly to *logs and traces* ("Logs and traces strip `phone_number|email|token|password|secret`... the API layer does not additionally embed PII into `resource_snapshot` audit payloads beyond what 5B §30's documented allow-list specifies") — it is an **output-redaction** standard for observability surfaces, not an **input-validation/rejection** standard for API request bodies. No frozen document anywhere in Phase 1–6A authorizes rejecting a tenant's `qualification_criteria` input based on a key-name substring match. Applying it that way risked false positives against entirely legitimate domain field names a tenant might reasonably choose — e.g. `credential_status`, `secretary_available`, `token_budget_category` — none of which holds a secret, all of which this rule would have wrongly rejected. **This rule is removed.** No `422 VALIDATION_ERROR` rule for `qualification_criteria` key names exists in this document.

**The safer, evidence-supported boundary adopted instead:** `qualification_criteria` remains open-ended, Agent-owned JSON, because no frozen `QualificationCriteria` value object or schema exists anywhere in Phase 1–5 — inventing one is DDD-level work outside this API-design document's authority. Given that, this document adopts output-side, not input-side, discipline, which 6A §22 genuinely does support:

- **`qualification_criteria`'s raw contents are treated as sensitive** and **must not** be written to logs, traces, metrics, or `error.details` (6A §22's redaction standard, applied at the surface it actually governs).
- **`qualification_criteria` is never placed in an audit `resource_snapshot`** — 5B §30's allow-list already governs exactly which fields an audit snapshot may carry, and this document does not add `qualification_criteria` to any endpoint's allow-listed snapshot fields (§25.0's `p_resource_snapshot` parameter). This is a genuine, existing mechanism (an omission from an allow-list, not a new rejection rule), not a fabricated one.
- **6E cannot structurally guarantee that a tenant will not place secret material inside this field** — this document does not claim otherwise, in §28.3 or anywhere else. Full structural closure requires a future frozen `QualificationCriteria` value object/schema that this document does not have the authority to define.

This residual is tracked as `DEP-6E-16` (§38) — re-scoped by this correction pass a second time: from "mitigated by an invented validation rule" to "mitigated only by output-side non-exposure (logs/traces/audit-snapshot), with no input-side control, honestly disclosed as such."

---

## 10. VoiceConfig

### 10.1 Fields (4B §5.3.1, 5C §5.4 — unchanged from 6D §8.2)

| Field | Type | Validation |
|---|---|---|
| `voice_id` | string | Provider-agnostic voice identifier |
| `language` | string | BCP 47, validated against the platform's supported-language whitelist (4B §5.3.1, includes `ta`/`ta-IN`) |
| `speaking_rate` | number | 0.5–2.0 |
| `emotion` | enum | `NEUTRAL \| FRIENDLY \| PROFESSIONAL \| EMPATHETIC` |
| `barge_in_sensitivity` | enum | `LOW \| MEDIUM \| HIGH` |

### 10.2 Ownership Split — Restated

6E owns the **management API** for `VoiceConfig` (this section, plus PATCH/publish validation). 6D owns the **runtime behavior** that consumes it — `BargeInDetectionService` reading `BargeInSensitivity` mid-call, `TtsPort` reading `voice_id`/`speaking_rate`/`emotion` per turn (6D §14.1). 6E never designs or redescribes that runtime behavior; it only guarantees the configuration reaching it is structurally well-formed (field types, ranges, enum membership, BCP 47 validity, §15.4 rules #2–#4). **6E does not, and cannot, validate `VoiceConfig` against a specific STT/TTS provider's capability** — `voice_id` is explicitly provider-agnostic (4B §5.3.1) and no frozen document defines a deterministic mapping from it to a `voice.provider_configs` row; §15.5 states this scoping correction in full. The only provider-specific capability validation 6E performs is for the LLM provider(s) identified in `ModelConfig` (§11, §15.5).

### 10.3 India-First Note (restated, not re-litigated)

Tamil, English, Telugu, and Hindi are ordinary values of `voice_config.language` / `language_policy.*` — there is no Tamil-only API surface, no Tamil-specific endpoint, and no separate validation code path keyed on a single hardcoded language string. 4B's `TamilCodeSwitching` boolean is superseded by the general `LanguagePolicy.code_switching_enabled` (§12, 4I CONTRADICTION-02) — the underlying capability is general-purpose code-switching, of which Tamil-English is the platform's first validated instance (4I §4.4), not a special case in the schema or the API.

---

## 11. ModelConfig

### 11.1 Fields (4B §5.3.2, 5C §5.4 — unchanged from 6D §8.2)

| Field | Type | Validation |
|---|---|---|
| `preferred_provider` | string, nullable | Must identify a `provider_id` that resolves, via §11.4's query (A), to a single **`is_active = TRUE`**, tenant-visible `voice.provider_configs` row (category=`LLM`) — **`circuit_state` is deliberately not a resolution predicate** (§11.4 explains why); that same resolved row's `supports_languages` also backs §15.4 rule #12's language-capability check, if set |
| `fallback_providers` | string[] | Ordered; each `provider_id` validated the same way as `preferred_provider`; see §15.4 for ordering/duplicate checks |
| `latency_bias` | number | 0.0–1.0 |
| `cost_bias` | number | 0.0–1.0 |
| `max_tokens_per_turn` | integer, nullable | — |

**`model_id` is deliberately not a `ModelConfig` field.** 4B §5.3.2's `ModelConfig` value object and 5C §5.4's `draft_config.model_config` JSON structure both define exactly `preferred_provider`, `fallback_providers`, `latency_bias`, `cost_bias`, `max_tokens_per_turn` — there is no client-supplied `model_id`. The specific model variant (e.g. `gpt-4o` vs. `gpt-4o-mini`) is an attribute of the *resolved* `voice.provider_configs` row (`model_id` column, 5C §5.11), not an independent Agent-config input — an Agent selects a **provider**, and the tenant's or platform's own `provider_configs` configuration (outside 6E's CRUD authority, per `DEP-6E-10`) determines which model that provider row currently points to.

### 11.2 Provider-Independence — Binding (ADR-6E-07)

Per the governing task's explicit instruction: `ModelConfig` never exposes a provider-native SDK parameter object, a raw model-specific hyperparameter set, or a `credential_ref` value. The client selects a **platform-recognized provider identifier** (`voice.provider_configs.provider_id`, e.g. `openai` — 5C §5.11) — never a provider SDK-shaped payload, and never a `model_id` (§11.1). Validating that identifier against `voice.provider_configs` happens only through the read-only reference-data endpoint this document now owns (§20), never through a direct cross-module import of provider-adapter code (3A's module-boundary rule).

### 11.3 The Agent Configures Preference; the Voice Runtime Retains Final Routing Authority

Restated from 6D §15: `ModelRouter.select()` and `ProviderSelectionService.select()` (3B §11, 4B §8.2) are pure, no-I/O, in-process functions that read the **pinned, immutable** `AgentVersion.snapshot_json`'s `model_config` alongside Redis-cached provider health at call time — not a live call back into any 6E endpoint. 6E's `ModelConfig` API is a **configuration-preference** surface; **actual runtime provider selection, failover, and circuit-breaker behavior remain 6D's territory, unmoved by this document.**

### 11.4 Deterministic `ProviderConfig` Resolution — Configuration Identity (6E) vs. Runtime Routability (6D), Kept Separate (corrected this pass)

**The gap this subsection closes — a real contradiction in a prior pass, not a stylistic one:** an earlier version of this document validated Agent-config provider identifiers by reusing 5C §15.11's runtime pre-selection query **verbatim**, including its `circuit_state = 'CLOSED'` filter. That query answers a different question than 6E needs answered. 5C §15.11 is 6D's **runtime routability** query — "which providers can actually carry traffic right now" — and correctly excludes an open-circuit provider entirely, because the Voice runtime must never attempt to route a call through a provider it already knows is failing. 6E's question is different: "did the tenant configure a provider identifier that actually exists and is administratively enabled" — a **configuration-identity** question, answered once at publish time, that must remain true regardless of the provider's transient, second-to-second health. Reusing 6D's query for 6E's purpose meant a `provider_id` matching an `is_active = TRUE` but momentarily `circuit_state = 'OPEN'` row would fail the existence check as a hard `ERROR` before §15.4 rule #15's `OPEN`-circuit `WARNING` could ever fire — an internal contradiction this pass removes.

**Two distinct queries, two distinct owners, never conflated again:**

**(A) 6E's configuration-identity/existence query — new, owned by this document, used by `PATCH`/`publish` validation (§15.4 rules #5/#12/#15) — corrected this pass to return the single effective row, with every column 6E's own checks need:**

```sql
SELECT
    id,
    provider_id,
    model_id,
    organization_id,
    priority,
    health_state,
    circuit_state,
    supports_languages
FROM voice.provider_configs
WHERE (organization_id = organization.current_tenant_id()
       OR organization_id IS NULL)
  AND category = $category
  AND provider_id = $provider_id
  AND is_active = TRUE
ORDER BY organization_id NULLS LAST, priority ASC
LIMIT 1;
```

**The gap this correction closes:** a prior version of this query omitted `LIMIT 1` and omitted `supports_languages` — leaving it ambiguous whether "the resolved row" §15.4 rules #12/#15 refer to was the same row query (A) returns, and leaving `supports_languages` (needed by rule #12's language-capability check) absent from the one query this document names as authoritative for provider resolution. Both are fixed by this single, minimal edit — no new query, no schema/index change, no altered `WHERE`/`ORDER BY` semantics.

**Query (A) is the sole, authoritative definition of the single `ProviderConfig` row used by every 6E publish-time check for a given `provider_id`.** Its result is interpreted as follows:

- **Zero rows returned** → the `provider_id` does not resolve — `422 VALIDATION_ERROR` (§15.4 rule #5, `ERROR`).
- **Exactly one row returned** (guaranteed by `LIMIT 1` whenever a match exists) → this is **the effective `ProviderConfig` row** — the same row, not a re-derived or re-queried one, that every subsequent 6E check for this `provider_id` (rules #5, #12, #15) reads from. No 6E check runs a second, independent lookup for the same `provider_id`.
- **That one row supplies every field 6E's own rules need**, with no further query: `model_id` (observability/traceability only, §11.1 — never a client-supplied value), `supports_languages` (rule #12's language-capability check, §15.5), `health_state`/`circuit_state` (rule #15's dynamic-health `WARNING` check, unchanged from this section's own prior correction).
- **Tenant-scoped rows precede platform-default rows** — `organization_id NULLS LAST` places every non-`NULL` (tenant) row ahead of every `NULL` (platform-default) row in the order `LIMIT 1` selects from.
- **Within the tenant scope, `priority ASC` determines precedence** — `uq_pc_priority` (5C §16.5) guarantees no two active tenant-scope rows in one `(organization_id, category)` share a `priority`, so this ordering is a strict, tie-free total order for that scope (§11.4's ordering-claim correction, below, states exactly how far this guarantee extends).
- **`circuit_state` is deliberately not a `WHERE` predicate** — it is dynamic runtime health, not configuration identity (restated from this section's own opening paragraph); it is still `SELECT`-ed so rule #15 can inspect it on the very row `LIMIT 1` already resolved.
- **`is_active = TRUE, circuit_state = OPEN`** → the row is still returned (`LIMIT 1` never excludes it) → the provider **exists** (rule #5 passes) and rule #15 fires a `WARNING`, never an `ERROR`.
- **`is_active = FALSE`, or no row for the `provider_id`/`category`/tenant-visibility combination at all** → zero rows → `ERROR`, unconditionally, regardless of what `circuit_state` an inactive row happens to carry.

**(B) 6D's frozen runtime pre-selection query — 5C §15.11, unmodified, reused for citation only, never re-run by any 6E endpoint:**

```sql
SELECT id, provider_id, model_id, priority, circuit_state, health_state,
       p50_latency_ms, error_rate_pct, supports_languages, config_json
FROM voice.provider_configs
WHERE (organization_id = organization.current_tenant_id() OR organization_id IS NULL)
  AND category = $category
  AND is_active = TRUE
  AND circuit_state = 'CLOSED'
ORDER BY organization_id NULLS LAST, priority ASC;
-- organization_id NULLS LAST: tenant configs preferred over platform defaults
```

This is the query the Voice runtime (6D, `ModelRouter.select()`/`ProviderSelectionService.select()`, §11.3) actually runs, per call, against the pinned `AgentVersion`'s resolved provider set — it correctly excludes open-circuit providers, because routing a live call through a known-failing provider would be a runtime defect, not a configuration one. 6E does not alter this query, does not re-run it, and does not use it for existence validation.

**Consequently, restated precisely against the required test matrix:**

| Provider state | `is_active` | `circuit_state` | 6E existence check (query A) | 6D runtime routability (query B) |
|---|---|---|---|---|
| Healthy | `TRUE` | `CLOSED` | Exists | Routable |
| Open circuit | `TRUE` | `OPEN` | **Exists** — publish proceeds, §15.4 rule #15 fires `WARNING` | Not routable until circuit closes/half-opens (6D territory) |
| Recovery probe | `TRUE` | `HALF_OPEN` | Exists, no `WARNING` (§15.4 rule #15 restated below) | Conditionally routable (6D's own probe logic, unmoved) |
| Deactivated | `FALSE` | any | **Does not exist** — `ERROR` (§15.4 rule #5) | Excluded (same reason, different layer) |

**Ordering claim, corrected — narrower than the prior pass's phrasing:** the prior pass claimed `uq_pc_priority` (5C §16.5, `UNIQUE (organization_id, category, priority) WHERE is_active = TRUE`) produces "a strict total order over every tenant-visible candidate row," unqualified. That overstates what an ordinary (non-`NULLS NOT DISTINCT`) PostgreSQL unique index guarantees: for a **concrete, non-`NULL` tenant `organization_id`**, the constraint compares real UUID values, so no two active tenant-scope rows in one `(organization_id, category)` can share a `priority` — the ordering claim holds fully there, and directly answers the "multiple tenant rows with the same `provider_id` but different `priority`" test case: they are the tenant's own two rows, never tied on `priority`, so `priority ASC` deterministically orders them. For the **platform-default scope** (`organization_id IS NULL`), ordinary PostgreSQL unique-index semantics treat every `NULL` as distinct from every other `NULL` for uniqueness purposes (no `NULLS NOT DISTINCT` clause exists on this index, verified directly against 5C §16.5's migration DDL) — so `uq_pc_priority` **does not**, by itself, prevent two platform-default rows from sharing a `priority` value. This does not create an actual ambiguity in practice, because a **different**, `NULL`-safe constraint already caps the platform scope independently: `uq_pc_platform_cat` (`UNIQUE (provider_id, category) WHERE organization_id IS NULL`) constrains on `provider_id`, a `NOT NULL` column, so it correctly guarantees **at most one** active platform-default row per `(provider_id, category)` regardless of `priority` ties among *other* providers. The "tenant provider + platform fallback with the same `provider_id`" test case is therefore answered by `NULLS LAST` alone (tenant row sorts first) and never needs the platform-scope priority ordering at all.

**Existence check, restated (§15.4 rule #5):** `preferred_provider`/each `fallback_providers[i]` is valid if query (A) — run once per `provider_id` — returns its single effective row for the required `category`; it is invalid (zero rows) otherwise. 6E does not assert *which* row the runtime will ultimately route a live call to (that remains query (B)'s, and 6D's, exclusive concern, and may legitimately differ turn-to-turn with health/circuit state) — only that, at publish time, the identifier resolved to one real, tenant-visible, administratively-enabled row, and that this same row is what rules #12/#15 also read.

No new precedence rule is fabricated for the ordering claim that remains; it is 5C §15.11's own `ORDER BY` clause, narrowed to the scope it actually, verifiably guarantees.

---

## 12. LanguagePolicy

### 12.1 Fields (5C §5.4/§5.5, 4I §4.2 — supersedes 4B's `VoiceConfig.TamilCodeSwitching` per CONTRADICTION-02)

| Field | Type | Validation |
|---|---|---|
| `primary_language` | string (BCP 47) | Required at publish; must be on the platform's supported-language whitelist |
| `fallback_language` | string (BCP 47), nullable | See §12.2 |
| `allowed_languages` | string[] (BCP 47) | Non-empty at publish; `primary_language` must appear in it (§12.2) |
| `code_switching_enabled` | boolean | See §12.2 |
| `language_detection_mode` | enum | e.g. `CONTINUOUS` (5C example value; exact enum set is 4I's, consumed not redefined here) |
| `pronunciation_lexicon_ref` | opaque reference, nullable | Format-validated only — owned by a later bounded context if/when a Pronunciation-Lexicon resource is designed; today it is stored and round-tripped, never resolved |
| `script_preference` | enum | e.g. `LATIN` (5C example value) |

### 12.2 Semantic Validation Rules — New, Explicit (6E refinement, §5.3 method item 2)

6D's frozen text never formalized `LanguagePolicy`'s internal-consistency rules beyond "validated against the platform's supported-language whitelist." This document makes the following explicit, grounded in the invariant the field names themselves imply and in 4B §5.3 invariant 5's language-whitelist requirement generalized to the full policy object:

| Rule | Classification | Rationale |
|---|---|---|
| `primary_language` must be a member of `allowed_languages` | **ERROR** | `allowed_languages` is meaningless as a boundary if the primary language itself falls outside it — an Agent that cannot legally speak its own primary language is a structurally broken configuration |
| `fallback_language`, if set, must be a member of `allowed_languages` | **ERROR** | Same reasoning — a fallback the policy does not itself permit can never be reached |
| `fallback_language` must not equal `primary_language`, if both are set | **ERROR** | A self-referential fallback is a configuration mistake, not a meaningful policy — nothing in 4I's `LanguagePolicy` model gives this combination a defined meaning |
| `code_switching_enabled = true` requires `allowed_languages` to contain at least two distinct languages | **ERROR** | Code-switching between one language is not a coherent capability request — mirrors 4B §5.3's `TamilCapableProviderSpecification` reasoning generalized: a capability flag with no eligible second language to switch to cannot be honored |
| `primary_language` / `allowed_languages` values must each be well-formed BCP 47 tags | **ERROR** | Structural validity, independent of whitelist membership |

**What is deliberately not added:** no rule here claims platform-wide authoritative knowledge of *which* languages a given provider/model actually supports beyond what `voice.provider_configs.supports_languages` and `voice.language_evaluation_records` document (§15.5) — that is a provider-capability question, handled separately and classified per §15.5's ERROR/WARNING split, not a `LanguagePolicy`-internal-consistency question.

---

## 13. Tool Permission Configuration

### 13.1 `Agent.tool_permissions` Is Agent Configuration, and Therefore 6E-Owned

Per 4B §5.3 invariant 4 and the governing task's explicit framing: the *list of which tools an Agent may invoke* is Agent draft configuration, validated by 6E at both PATCH-time (existence) and publish-time (existence + active status, §15.2). This is distinct from *Tool Definition management itself* (creating/editing the tool's schema, timeout, retry policy) — that CRUD surface is reconciled to 6E separately, §21, for a different reason (Tool Definitions are naturally Agent-configuration-adjacent resources, not because `tool_permissions` needs them to be).

### 13.2 Field Shape

`tool_permissions: [{ "tool_id": "<uuid>", "tool_name": "<string>" }]` — `tool_name` is a denormalized, human-readable convenience field (matching 5C's own `draft_config` example, §4); `tool_id` is authoritative and the only field re-validated against `voice.tool_definitions`.

### 13.3 Duplicate-Entry Validation — New, Explicit (6E refinement)

**ERROR:** `tool_permissions` containing the same `tool_id` more than once → `422 VALIDATION_ERROR`, `error.details.field: "tool_permissions"`, `error.details.reason: "duplicate_tool_id"`. 6D's frozen text never specified behavior for this case one way or the other; this is a disclosed tightening of previously-unspecified behavior, not a contradiction — no configuration that would have failed 6D's existing checks now succeeds, and no configuration 6D's text explicitly declared valid now fails.

---

## 14. External / Opaque References

### 14.1 What 6E May Do

`prompt_ref`, `workflow_ref`, `knowledge_base_refs` point into bounded contexts 6E does not own (§3.2). Per the governing task's explicit boundary: 6E may validate UUID shape, store the reference, and round-trip it unchanged through every read/write path — including into the immutable `AgentVersion.snapshot_json` at publish time (§16).

### 14.2 What 6E Must Not Do

6E does not design Prompt CRUD, Workflow CRUD, or Knowledge Base CRUD. It does not import another bounded context's repository or domain module directly (3A's module-boundary rule). It does not invent a synchronous cross-context HTTP call to "check the reference exists" at PATCH or publish time.

### 14.3 Existence Validation — Explicitly Unresolved, Not Silently Assumed

No approved in-process port for validating `prompt_ref`/`workflow_ref`/`knowledge_base_refs` existence is documented anywhere in Phase 1–5 today (4B §16's port catalogue defines `PromptRenderPort`/`WorkflowExecutionPort`/`KnowledgeSearchPort` as **runtime consumption** ports, invoked per-call by the Voice Orchestrator — not existence-check ports invocable from an Agent-management PATCH/publish request). 6E therefore does **not** claim these references are validated for existence — only for well-formedness. This is recorded as `DEP-6E-02`/`DEP-6E-03`/`DEP-6E-04` (§38), exactly matching the honest, disclosed-gap posture 6D already used for `provider:*` (`DEP-6D-06`) and phone-number provisioning (`DEP-6D-07`).

### 14.4 What This Means Operationally

An Agent can be published with a `prompt_ref` that does not exist in whatever future system owns Prompt Management — the immutable `AgentVersion` snapshot will carry a dangling opaque reference, discoverable only when the Voice runtime (or a future Prompt Management document's own existence-check, exercised at whatever boundary that document defines) attempts to resolve it. This is not a 6E defect; it is the correct consequence of a genuine, disclosed modular-monolith boundary (3A) that this document does not have the authority to close by inventing a cross-context call.

---

## 15. Agent Validation

### 15.1 Two Validation Moments, Different Rule Sets

| Moment | Scope | Trigger |
|---|---|---|
| **Continuous (PATCH-time)** | Structural: field types, ranges, enum membership, BCP 47 well-formedness, `tool_permissions[].tool_id` existence + tenant-visibility (not yet active-status-checked). `qualification_criteria` accepts any well-formed JSON object — no key-name validation rule exists for it (§9.4, corrected this pass); its output-side non-exposure (never logged, traced, or audit-snapshotted) is enforced at the observability/audit layer, not by rejecting input | Every `PATCH /agents/{id}` |
| **Full (publish-time)** | Everything PATCH-time checks, **plus**: `tool_permissions[].tool_id` re-verified `is_active=TRUE` against the state visible at this transaction's own validation read (§15.2, corrected this pass), §12.2's `LanguagePolicy` semantic rules, §13.3's duplicate-tool check, §11.4's deterministic provider-resolution check, §15.5/§15.6's provider-language-capability and evaluation-record-selection checks | `POST /agents/{id}/publish` |

**Why draft-time validation alone is insufficient — restated, unchanged from 6D §9.2:** a `tool_id` valid when a field was last edited may have been deactivated since. Publish is the moment the *entire* current draft becomes permanently frozen into an immutable version — it is therefore the point at which every reference must be proven valid **as of that moment**, not merely as of whenever each field was last touched.

### 15.2 Tool Reference Re-Verification at Publish — Precise Transactional Semantics (corrected this pass)

**The gap this subsection closes:** a prior version of this document (following 6D §9.2's own phrasing) described this check as verifying a tool is "active at the exact moment of publication." Under ordinary PostgreSQL READ COMMITTED semantics, that phrasing overstates the actual guarantee — "the moment of publication" is ambiguous between "the moment publish's validation query executes" and "the moment the publish transaction commits," and a concurrent `deactivate` can commit *between* those two instants (§32.2's race table). The corrected, precise statement:

**Tool permissions are revalidated against the committed tool state visible to the publish transaction at its validation read.** Concretely: within `publish`'s transaction, before the `AgentVersion` `INSERT` (§16.2 step 2), a `SELECT is_active FROM voice.tool_definitions WHERE id = ANY($tool_ids)` runs under READ COMMITTED — it sees whatever was last committed for each `tool_definitions` row at the instant *this statement* executes. If every referenced tool is `is_active = TRUE` at that instant, validation passes and the transaction proceeds to `INSERT`/`UPDATE`/`COMMIT`.

**What this does and does not guarantee:**
- A concurrent `POST /tools/{id}/deactivate` that commits **before** publish's validation `SELECT` → publish correctly sees `is_active = FALSE` and fails `422 VALIDATION_ERROR` (§15.4 rule #9).
- A concurrent `deactivate` that commits **after** publish's validation `SELECT` but **before** publish's own `COMMIT` → publish's validation already passed against the pre-deactivation state; publish proceeds to commit, and **the resulting immutable `AgentVersion` snapshot references a tool that is inactive by the time the new version actually exists.** This is not prevented by this design, and this document does not claim otherwise. No `SELECT ... FOR UPDATE` or new locking mechanism is introduced to close this window (6A §17.3 remains unviolated, per the governing task's explicit instruction).
- **Already-published `AgentVersion` rows are never retroactively invalidated** by a later `deactivate` — an existing immutable snapshot remains historically valid and readable regardless of what happens to the tools it references afterward (consistent with §16.1's immutability contract; a snapshot is a point-in-time record, not a live reference).
- **A *subsequent* publish** (a new `publish` call after the tool has been deactivated) **will** fail §15.4 rule #9, because its own validation `SELECT` runs after the deactivation committed.

This is acceptable, disclosed behavior, not a defect: it is the same class of narrow, bounded race already accepted elsewhere in this document (§16.3's draft-PATCH-vs-publish race) and in 6D's own frozen design (6D §11.4's terminate-vs-transfer race) — a genuinely instantaneous, zero-window guarantee would require `SELECT ... FOR UPDATE` or `SERIALIZABLE` isolation, neither of which 6A §17.3/6D's frozen isolation-level choice permits introducing here. This check moved authority from 6D to 6E along with Tool Definition management (§21); the mechanism, timing, and failure mode are unchanged from 6D's actual runtime behavior — only the **description** of the guarantee is corrected, from an overstated "exact moment" claim to the precise "validation-read snapshot" semantics above.

### 15.3 ERROR vs. WARNING — Formalized (new; ADR-6E-11)

The governing task requires an explicit distinction the frozen documents implied but never stated as a rule. 6E adopts:

- **ERROR** — publish **must** fail. Reserved for: a hard domain invariant violation (dangling/inactive tool reference, malformed required field, a `LanguagePolicy` internal-consistency violation, a provider identifier that does not resolve to any **`is_active = TRUE`** `voice.provider_configs` row per §11.4's configuration-identity query — deliberately independent of `circuit_state`, a language the provider's `supports_languages` array does not list at all).
- **WARNING** — publish **may** succeed; the response carries a non-blocking `warnings[]` array. Reserved for: a *dynamic, time-varying* condition that the Voice runtime (6D), not the Agent-management layer, is responsible for handling gracefully at call time (an *already-existing* provider's `health_state = DEGRADED` or `circuit_state = OPEN` at the instant of publish — 6D's failover design already assumes providers can be transiently unhealthy at any moment, §22.1 — this is a health check layered *on top of* a passed existence check, never a substitute for one, §11.4), or an *advisory quality signal* the domain model itself treats as non-binding (`voice.language_evaluation_records.verdict = CONDITIONAL` for the tenant-identified LLM provider/language pairing, `capability = 'LLM'` only per §15.5's scoping — 5C §5.12 documents `verdict` as `APPROVED | CONDITIONAL | REJECTED`, and only `REJECTED` combined with no viable alternative is treated as a hard block, per §15.5).

### 15.4 Full Publish-Time Validation Table

| # | Check | Classification | Basis |
|---|---|---|---|
| 1 | `name` 2–100 chars, `description` 0–500 chars | ERROR | 5C `chk_agents_name_len` |
| 2 | `voice_config.voice_id`/`language` present; `language` on platform whitelist | ERROR | 4B §5.3 invariant 5 |
| 3 | `voice_config.speaking_rate` ∈ [0.5, 2.0] | ERROR | 4B §5.3.1 |
| 4 | `voice_config.emotion` / `barge_in_sensitivity` valid enum members | ERROR | 4B §5.3.1 |
| 5 | `model_config.preferred_provider`, each `fallback_providers[i]` resolve — via §11.4's query (A), `LIMIT 1` — to a single `is_active = TRUE`, tenant-visible `voice.provider_configs` row, category=`LLM`; that row is the one effective `ProviderConfig` rules #12/#15 also read for this `provider_id` — `circuit_state` is **not** evaluated by this rule | ERROR | 4B §8.2, 5C §5.11/§16.5 |
| 6 | `fallback_providers` contains no duplicate entry, and does not repeat `preferred_provider` | **ERROR (new, 6E refinement)** | Disclosed tightening — an ordered failover list with a repeated entry is a configuration mistake with no defined runtime meaning; 6D's text never specified this either way |
| 7 | `model_config.latency_bias`/`cost_bias` ∈ [0.0, 1.0] | ERROR | 4B §5.3.2 |
| 8 | `language_policy.*` internal-consistency (§12.2's five rules) | ERROR | New, §12.2 |
| 9 | `tool_permissions[].tool_id` exists, tenant-visible, `is_active=TRUE` | ERROR | 6D §9.2, unchanged |
| 10 | `tool_permissions` contains no duplicate `tool_id` | **ERROR (new, 6E refinement)** | §13.3 |
| 11 | `calling_hours`, if set, is a well-formed `TimeWindow` | ERROR | 4B §5.3 |
| 12 | The tenant-identified LLM provider's (`model_config.preferred_provider`, and independently each `fallback_providers[i]`) `supports_languages` — read from the **same** §11.4 query (A) row rule #5 already resolved for that `provider_id`, no second lookup — includes `language_policy.primary_language` — **LLM only, per §15.5's scoping correction; no equivalent check exists for STT/TTS, since Agent config never identifies a specific STT/TTS provider** | ERROR | 4B/4I `TamilCapableProviderSpecification`, generalized to LLM (§15.5) |
| 13 | The **most recent** `voice.language_evaluation_records` row (via §15.6's query (B), `capability = 'LLM'` only) for the tenant-identified LLM provider has `verdict = CONDITIONAL` | **WARNING** | 5C §5.12 — advisory, not a hard support flag (§15.5) |
| 14 | The most recent applicable record for the tenant-identified LLM provider has `verdict = REJECTED`, **and no fallback LLM provider satisfies the same language at a better verdict (or has no applicable record at all)** | **ERROR** | A `REJECTED` verdict with no viable alternative anywhere in the configured LLM provider set is not a warning-worthy risk — it is a configuration that the platform's own evaluation data says cannot work |
| 15 | The tenant-identified LLM provider's `health_state = DEGRADED` or `circuit_state = OPEN` at the moment of publish — read from the **same** §11.4 query (A) row rules #5/#12 already resolved for that `provider_id`; this rule inspects that row's dynamic health columns only, it does not re-run existence or re-query | **WARNING** — `circuit_state = HALF_OPEN` does **not** trigger this rule (it is an active recovery-probe state, not a failure state, per the provider circuit lifecycle `CLOSED → OPEN → HALF_OPEN`, 4B §7.5) | Dynamic condition; 6D's runtime failover already handles this at call time (§22.1). Existence and health are deliberately evaluated as two separate questions (§11.4) — a provider can exist (rule #5 passes) while also being unhealthy (this rule additionally warns) |
| 16 | `fallback_providers` is empty | **WARNING** | Single point of failure, not a structural defect |

**Rule #17 removed this pass.** A prior version of this table rejected `qualification_criteria` keys matching a prohibited-substring pattern, citing 6A §22's logging/tracing redaction vocabulary as authorization. That citation does not support an input-rejection rule (§9.4 states the retraction in full) — the rule risked rejecting legitimate field names (`credential_status`, `token_budget_category`, etc.) with no secret-safety benefit precise enough to justify the false-positive risk. No `qualification_criteria` key-name validation rule exists in this document; §9.4 states the output-side (never input-side) mitigation adopted instead.

### 15.5 Provider/Language Capability Validation — Grounded, Not Fabricated, and Scoped to What Agent Config Actually Identifies (corrected this pass)

**The gap this subsection closes:** a prior version of this document validated "the selected provider" against `language_evaluation_records` generically across `STT`, `TTS`, and `LLM` capabilities, as if Agent configuration always identifies one specific provider per category. It does not. Re-reading 4B §5.3.1/§5.3.2 and 5C §5.4's `draft_config` structure directly: `ModelConfig` (§11) carries `preferred_provider`/`fallback_providers` — client-supplied `provider_id` values — and 4B §8.2/3B §11 confirm `ModelConfig`/`ModelRouter` are the LLM-selection surface (`FR-LLM-002`). `VoiceConfig` (§10) carries `voice_id`, explicitly documented as "**provider-agnostic** voice identity" (4B §5.3.1) — it identifies *a voice*, not *a provider*. There is no `stt_provider_id` or `tts_provider_id` field anywhere in `VoiceConfig`, `draft_config`, or any port/service signature in 4B/3B/5C, and no frozen document defines a deterministic mapping from `voice_id` (or any other `VoiceConfig` field) to a specific STT or TTS `voice.provider_configs` row — STT/TTS provider selection is entirely `ModelRouter`/`ProviderSelectionService`'s own runtime decision (3B §11, 6D §15), made from the *platform's* candidate list, health data, and `supports_languages`, never from a tenant-supplied identifier.

**Consequently, publish-time provider-specific validation in 6E is scoped to LLM only** — the only category for which Agent configuration ever supplies a client-identified `provider_id`:

- Rule #12 (`supports_languages` check) validates only the tenant-identified LLM provider(s) (`model_config.preferred_provider`, each `fallback_providers[i]`) — **never** a hypothesized STT or TTS provider, because 6E has no `provider_id` for those categories to validate against. `supports_languages` itself is read directly from §11.4 query (A)'s single effective row for that `provider_id` — corrected this pass to be part of that query's `SELECT` list — never a second, separate lookup.
- Rules #13/#14 (`language_evaluation_records` verdict check, §15.6) likewise run only with `capability = 'LLM'`, for the same reason.
- **What 6E can and does still validate for `VoiceConfig`/STT/TTS**, from inputs it actually owns: BCP 47 well-formedness and platform-whitelist membership of `voice_config.language` (§15.4 rule #2), `LanguagePolicy`'s internal five-rule consistency (§12.2), and `VoiceConfig`'s own structural fields (`speaking_rate`, `emotion`, `barge_in_sensitivity`, §15.4 rules #3/#4). None of these requires knowing which specific STT/TTS provider will ultimately serve the call.
- **`GET /api/v1/language-evaluations` (§20) is unaffected** — it remains a read-only reference-data endpoint that may surface `STT`/`TTS`/`LLM` evaluation records generically to an Agent Builder UI (5C §5.12's `capability` column genuinely has three values, and the reference-data query, §15.6 query (A), is not restricted to `LLM`). Exposing broader reference data for human browsing is a different concern from 6E being able to *automatically resolve and validate* a specific STT/TTS provider from Agent config — the two are not in tension, and this document does not conflate them.

This is recorded as `DEP-6E-21` (§38, RESOLVED) — the scoping correction itself, not an open gap, since 6E's actual validation surface now matches exactly what Agent configuration can deterministically identify.

Two, and only two, sources of provider-capability truth exist in the frozen schema for the LLM check that remains: `voice.provider_configs.supports_languages` (5C §5.11 — a declared, deterministic support flag) and `voice.language_evaluation_records.verdict`/`scores` (5C §5.12 — an evaluated, advisory quality signal). Rule #12 is a hard ERROR because `supports_languages` is a declared capability, not a probabilistic score — selecting an LLM provider for a language it does not declare is a structural misconfiguration, exactly the same class of check 4B's `TamilCapableProviderSpecification` already enforces for the Tamil case, generalized here to every language (for the LLM category only, per the scoping above). Rules #13/#14 read `verdict` as advisory data about *quality*, not *capability* — a `CONDITIONAL` verdict does not mean the provider cannot serve the language, only that the platform's own evaluation methodology (4I §4.4) found it imperfect; a tenant is entitled to accept that risk knowingly, hence WARNING, not ERROR.

### 15.6 Deterministic `LanguageEvaluationRecord` Selection — a 6E Application Query Over an Existing Frozen Index (corrected this pass)

**The gap this subsection closes — a real contradiction in a prior pass, not a stylistic one:** an earlier version of this document tried to use 5C §15.12's reference-list query as if it were 6E's publish-time validation lookup. That query does two things 6E's validation rules cannot tolerate: (1) it filters `WHERE verdict IN ('APPROVED', 'CONDITIONAL')`, which makes a `REJECTED` verdict **structurally invisible** to the query — §15.4 rule #14 needs to *detect* `REJECTED`, so a query that discards `REJECTED` rows before they can be inspected can never support that rule; (2) it filters only on `(language, capability)`, with no `provider_id` predicate at all, so it cannot answer "what is the verdict for *this specific* resolved provider" — it returns every provider's evaluation history for a language/capability at once. Both are real defects in the prior pass's text, not phrasing issues, and are fixed here by defining a **separate, 6E-owned application-layer query**, distinct from 5C §15.12's reference-list query, while still resting on the same already-frozen index — no Phase 5 change is made or needed.

**Two distinct queries, two distinct purposes, never conflated again:**

**(A) 5C §15.12's existing reference-list query — unchanged, still exactly what it was, used only to back `GET /api/v1/language-evaluations` (§20):**

```sql
SELECT provider_id, provider_model_ref, capability, verdict, scores, evaluated_at
FROM voice.language_evaluation_records
WHERE language = $language
  AND capability = $capability
  AND verdict IN ('APPROVED', 'CONDITIONAL')
ORDER BY evaluated_at DESC;
-- Index: idx_ler_lookup
```

This query is a **browsing/reference-data** view for an Agent Builder deciding what to configure — deliberately pre-filtered to hide `REJECTED` rows because a human browsing "which providers can I pick" has no use for options the platform already knows do not work. 6E does not alter it and continues to expose it unmodified via §20.

**(B) 6E's new publish-time validation query — application-layer, owned by this document, supported by the same already-frozen `idx_ler_lookup` index `(language, provider_id, capability, evaluated_at DESC)` (5C §9.12), no schema/index/migration change:**

```sql
SELECT provider_id, provider_model_ref, capability, verdict, scores,
       evaluated_at, evaluation_set_ref
FROM voice.language_evaluation_records
WHERE language = $language
  AND provider_id = $provider_id
  AND capability = $capability
ORDER BY evaluated_at DESC
LIMIT 1;
-- Index: idx_ler_lookup (same index as query A; no new index required —
-- this query is a strict subset/refinement of what the index already supports:
-- adding an equality predicate on provider_id and dropping the verdict filter
-- both narrow the scan, they do not require a different access path)
```

**Critically, this query does not filter by `verdict` at all** — it selects the single most-recent row for the exact `(language, provider_id, capability)` tuple, **then** §15.4 rules #13/#14 interpret whatever `verdict` that row holds (`APPROVED`, `CONDITIONAL`, or `REJECTED`). Filtering by `verdict` before selecting "the latest row" would make it structurally impossible to ever observe a `REJECTED` outcome, which is exactly the defect this correction removes.

**Selection rule, applied at publish time for rules #13/#14:**

1. **Lookup tuple:** `(language = language_policy.primary_language, provider_id = the specific provider being validated, capability = 'LLM')` — per Issue-3's correction (§15.5), 6E only ever has a client-identified `provider_id` for the LLM category (§11.1), so this lookup runs once per LLM `provider_id` under validation (the preferred provider, then independently each `fallback_providers[i]`) — never for STT/TTS, since no `provider_id` for those categories is ever supplied by Agent config.
2. **Multiple records for the same tuple:** query (B)'s `ORDER BY evaluated_at DESC LIMIT 1` selects the single most-recent row directly — the same "most recent record by timestamp" pattern 4I already uses for `ConsentRecord` (4I §8.1 invariant 2: "the effective consent for a `(SubjectRef, Purpose, Channel)` triple is the most recent record by `RecordedAt`"), applied here to the structurally analogous "authoritative record among several over time" problem.
3. **Multiple evaluation sets (`evaluation_set_ref`):** not a second selection axis — it is descriptive provenance on the winning row (which corpus produced this verdict); `evaluated_at DESC LIMIT 1` already picks one row regardless of how many distinct `evaluation_set_ref` values exist for the tuple.
4. **`provider_model_ref` — a disclosed, non-blocking residual (folded into `DEP-6E-12`, §38):** query (B) selects `provider_model_ref` for observability but does not filter on it — because §11.1 establishes that `ModelConfig` carries no client-supplied `model_id`, 6E has no tenant-supplied value to match `provider_model_ref` against. The winning row's `provider_model_ref` may therefore describe a different model variant than the one the resolved `provider_configs.model_id` currently serves (e.g., an evaluation performed against an older model version). Disclosed as a residual imprecision, non-blocking because rules #13/#14 are already WARNING/conditionally-ERROR (§15.3), not an unconditional hard gate.
5. **Missing record entirely (query (B) returns zero rows for the tuple):** treated as "no advisory data available" — neither WARNING nor ERROR (§15.4's rules #13/#14 simply do not fire), consistent with `DEP-6E-12`'s conservative posture. 6E does not infer either "presumed safe" or "presumed unsafe" from an absent evaluation record.
6. **Preferred provider `REJECTED`, a fallback `APPROVED`:** rule #14 does not fire (a viable alternative exists in the configured `fallback_providers` list, itself checked via its own independent query (B) lookup) — publish succeeds, though rule #13-class `WARNING`s may still apply to the fallback depending on its own most-recent verdict.
7. **Preferred provider `APPROVED`, a fallback `REJECTED`:** no rule fires for the fallback specifically — §15.4 rule #14 only blocks when the *primary selection path* has no viable candidate; a `REJECTED` fallback that is never reached in practice (because the preferred provider is healthy) is not itself a publish-time error, though it is a candidate for a future informational `WARNING` if product requirements later ask for one (not designed here — recorded as part of `DEP-6E-12`'s scope, non-blocking).
8. **Older `APPROVED` superseded by a newer `REJECTED` (or vice versa):** query (B)'s `evaluated_at DESC LIMIT 1` always takes the newest row regardless of direction of change — an older `APPROVED` record is not "sticky" once a newer evaluation exists, and an older `REJECTED` is not held against a provider once a newer evaluation clears it. This is the same "most recent wins" rule applied symmetrically, not a special case.

No selection rule above is invented from nothing: query (B)'s tuple shape and ordering rest on 5C's own already-frozen `idx_ler_lookup` index; the "most recent wins" semantics mirrors 4I's own explicit precedent for the structurally identical `ConsentRecord` problem. What is genuinely new in this pass is the query *itself* (B) — it is an application-layer construction over an existing index, not a reproduction of 5C §15.12's reference-list query, and this document no longer claims otherwise.

---

## 16. Agent Publishing

### 16.1 The Immutability Contract — Restated, Unchanged, Binding (DDR-4B-003)

```
Agent.draft_config (mutable, edited freely via PATCH)
        │
        │  POST /agents/{id}/publish
        ▼
AgentVersion.snapshot_json (immutable JSONB, written once, DB-trigger-enforced)
        │
        │  read once, at call-start time, by CallRoutingService (in-process, 6D territory)
        ▼
Call.agent_version_id (pinned for the entire lifetime of that Call — 4B §5.1 invariant 1)
```

Publishing version N+1 while calls are pinned to version N has **zero effect** on those calls — enforced structurally (the Call aggregate stores its own `agent_version_id` at creation, 6D §9.1) rather than by a runtime check a future bug could bypass. 6E introduces no endpoint that writes to `call_sessions.agent_version_id` after creation, at any point after call start (§22.4).

### 16.2 Publish Mechanics — Adopted From 6D §9.2, Unchanged in Substance

`POST /agents/{id}/publish` is 6A §35's named approved exception, **"Publish Agent + AgentVersion"**, reused exactly — not re-derived, not a new exception. Within one DB transaction:

1. Guard: `agents.status` must be `DRAFT` or `PUBLISHED` (§5.4 finding #1) — `DEPRECATED` is terminal for publish (4B §7.3).
2. Run every check in §15.4's table; any ERROR-classified failure aborts before any write.
3. `INSERT INTO voice.agent_versions (agent_id, version_number, snapshot_json, language_policy, published_by, published_at)` — `version_number = MAX(version_number) + 1` (or `1` for the first publish), enforced by `uq_av_version` (5C §7) — bounded-retry handling of a concurrent-publish collision in §16.4.
4. `UPDATE voice.agents SET status='PUBLISHED', published_version_id = <new version id>`.
5. `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_PUBLISHED', ...)` — the sole legal audit write path (§25.0); never a direct `INSERT INTO audit.audit_events` (5J §5/§14.2, `REVOKE ALL`).
6. `INSERT INTO audit.domain_event_outbox (event_type='agent.published', ...)` — same transaction, separate write (§26).

### 16.3 The Draft-PATCH-vs-Publish Race, Made Explicit

**The scenario:** User A edits an Agent's draft while User B calls `publish` on the same Agent.

**Grounded in PostgreSQL's actual transaction model, no locking mechanism invented (6A §17.3):** `publish`'s transaction reads `voice.agents.draft_config` with an ordinary `SELECT` under READ COMMITTED isolation — it therefore always sees the **latest committed** value of `draft_config` at the instant of its own read, never a partially-written or uncommitted value (Postgres MVCC guarantees this at the row-version level; there is no intermediate "half-written JSONB" state a concurrent reader can ever observe). Two outcomes are both correct and both acceptable:

- If User A's `PATCH` **commits** before User B's `publish` transaction begins its own read → the new version snapshots User A's edit. This is the intended "ship an update" flow.
- If User A's `PATCH` is still in-flight (uncommitted) when User B's `publish` reads → the new version snapshots the *previous* committed draft. User A's edit is not lost — it remains in `draft_config` for the *next* publish; it is simply not included in *this* one.

Neither outcome corrupts data or produces an inconsistent snapshot; both are the ordinary, well-defined behavior of "publish snapshots whatever the last commit before this transaction's read produced." No `SELECT ... FOR UPDATE` is introduced (6A §17.3 remains unviolated).

### 16.4 Concurrent Publish — `23505`, Not a Serialization Failure (adopted from 6D §9.2a, unchanged)

Under READ COMMITTED (the platform default; no `SERIALIZABLE` isolation is used anywhere in this design), two concurrent publishes on the same Agent do **not** produce `40001` (`serialization_failure`) — that class only arises under `SERIALIZABLE`/`REPEATABLE READ`. Whichever `INSERT` commits first succeeds; the second raises **`23505` (`unique_violation`)** against `uq_av_version`. The bounded-retry algorithm is reproduced exactly from 6D §9.2a: recompute `MAX(version_number)`, retry, bounded at 3 attempts, `409 STATE_CONFLICT` (`error.details.reason: "concurrent_publish_contention"`) on exhaustion. This is an application-layer response to a constraint violation Postgres was always going to raise — not a new locking scheme, not a Phase 5 change.

### 16.5 Response

`{ "data": { "version_id", "version_number", "published_at", "warnings": [...], "agent": {...updated Agent...} } }` — the `warnings` array (empty when no §15.3 WARNING-classified condition fired) is the one addition 6E makes to 6D's original response shape, purely additive (an older client ignoring an unknown field observes identical behavior to 6D's frozen contract).

### 16.6 Optional `If-Match` Precondition — New, Additive Refinement (ADR-6E-10)

The governing task explicitly invites evaluating whether an ETag/version precondition on publish is useful. 6D's frozen contract requires an empty request body and does not mention `If-Match` for this endpoint either way — silence, not a documented prohibition. 6E adds an **optional** `If-Match` header, reusing the exact weak-ETag mechanism 6A §17.2/ADR-6A-08 already defines for `GET`/`PATCH` (`hash(id, updated_at)`): if supplied, the server verifies it against the Agent row's current ETag *before* proceeding, returning `412 PRECONDITION_FAILED` on mismatch. Omitting the header behaves exactly as 6D originally specified — this is a pure capability addition for a caller that wants a "publish exactly the draft I last read" guarantee (e.g., an Agent-builder UI that fetched the Agent, showed a "Publish" button, and wants to detect if someone else edited in between), not a new required behavior and not a new locking mechanism (it is the same weak-ETag comparison already used elsewhere, applied to one more endpoint).

---

## 17. AgentVersion API

### 17.1 Read-Only Endpoints (adopted from 6D §9.3, §28.8–28.9, unchanged)

`GET /agents/{id}/versions` (list, newest first, cursor-paginated per 6A §14) and `GET /agents/{id}/versions/{version_id}` (one snapshot, including `language_policy`, `published_by`, `published_at`) are the only two version-read endpoints.

### 17.2 No Diff, No Rollback, No Mutation — Restated, Binding

There is no "diff between versions" endpoint and no "rollback to version N" endpoint. 4B's command catalogue (§12.3) has no `RollbackAgent`/`CompareAgentVersions` command, and `agent_versions` is effectively append-only (5C §5.5, no `updated_at` column, `BEFORE UPDATE` trigger rejects any change). A rollback is performed by editing the draft back to the desired shape and publishing again — which correctly creates a **new** version rather than resurrecting an old one. This document does not invent either capability merely because a modern Agent-management UI might want them; the governing task explicitly forbids that.

### 17.3 List Response Fields — Bounded, Per 6A §36

`GET /agents/{id}/versions` returns `version_id`, `version_number`, `published_by`, `published_at` per row — **not** the full `snapshot_json` (reserved for the detail endpoint, avoiding an unbounded list-response size, 6A §36's anti-pattern list).

---

## 18. Agent Clone

### 18.1 Contract (adopted from 6D §28.7, unchanged)

`POST /agents/{id}/clone` — `{ "source": "draft" | "published_version_id" }`. Creates a new Agent whose `draft_config` is copied from the source (either the source Agent's current `draft_config`, or a specific `AgentVersion.snapshot_json` if a `published_version_id` is given).

### 18.2 Resulting State — Always `DRAFT`

The new Agent is always created in `DRAFT`, regardless of the source Agent's own status. **`published_version_id` is never copied** into the new Agent — a clone starts with no published version of its own, even when cloned from a `published_version_id` source, because a cloned Agent has never itself been published; only its *configuration* is copied, never its *publication history*.

### 18.3 What Is Copied vs. Reset

| Field | Behavior |
|---|---|
| `draft_config` (all sub-objects) | Copied verbatim from the source |
| `name` | Copied verbatim (the tenant is expected to rename via a follow-up `PATCH` if desired — no automatic "(copy)" suffix is invented, since no frozen source specifies one) |
| `status` | Always `DRAFT` |
| `published_version_id` | Always `NULL` |
| `Versions` (AgentVersion history) | **Never copied** — a new Agent has an empty version list; version history is 6D's/4B's own aggregate-scoped concept and does not transfer across Agent identities |
| `id`, `created_at`, `updated_at`, `created_by` | New values for the new Agent row |

### 18.4 Audit

`AGENT_CREATED` (5J §14.3 `‡` — exact match, Category A) — the same value `POST /agents` uses, since a clone is, from the audit trail's perspective, the creation of a new Agent row (6D §28.7's own reasoning, unchanged).

### 18.5 No Immediate Publish

Cloning never produces an immediately-`PUBLISHED` Agent, even when the source's `published_version_id` is given as the clone source — 4B's command catalogue has no `CloneAndPublishAgent` command, and inventing an auto-publish-on-clone behavior would contradict §8.4's binding rule that no 6E endpoint auto-publishes on creation.

---

## 19. Agent Deprecation / Delete Boundary

### 19.1 Deprecation — Adopted From 6D §9.4/§28.6, Unchanged

`POST /agents/{id}/deprecate`: guard `status = PUBLISHED` → `status = DEPRECATED`, `409 STATE_CONFLICT` otherwise. Per 4B §7.3, `DEPRECATED` is terminal for the publish action (an Agent cannot be published again once deprecated) but its already-published versions remain fully readable (audit/history), and any Call already pinned to one of its versions is **entirely unaffected** — deprecation only prevents **new** calls from resolving to this Agent (`CallRoutingService.resolve()` excludes non-`PUBLISHED` agents, 4B §9 policy `AgentMustBePublished`, enforced in 6D's territory at call-start time).

### 19.2 Deprecation Is the Only API-Visible Terminal Lifecycle Action

Per the governing task's explicit instruction: `voice.agents.deleted_at` exists as a column (5C §5.4) but no 4B command (`CreateAgent`, `UpdateDraftConfig`, `PublishAgent`, `DeprecateAgent`, `CloneAgent` — the complete list, 4B §12.3) populates it. There is no `DeleteAgent`/`ArchiveAgent` domain command anywhere in Phase 1–5. Per this document's explicit hard boundary (no inventing an endpoint merely because a column exists), **6E does not expose `DELETE /agents/{id}` or `POST /agents/{id}/archive`.** This is disclosed as `DEP-6E-14` (§38) — a non-blocking, inherited scope boundary (originally 6D's `DEP-6D-12`), not a silent omission.

### 19.3 Permission — Adopted From 6D §25, Unchanged

`agent:delete` (5B §17.2 — `OWNER`, `ADMIN` only) gates `deprecate`, reusing the existing permission rather than inventing `agent:deprecate` — per the governing task's explicit instruction not to invent a permission string when an existing one adequately covers the operation, and matching 6D's own ADR (its own text notes this as an "interim reuse" in the sense that the permission's *name* says "delete" while the *operation* is "deprecate," not in the sense that the role-grant footprint is wrong — `OWNER`/`ADMIN`-only is exactly the right sensitivity for a terminal, live-traffic-affecting lifecycle action).

---

## 20. Provider / Language Reference Data

### 20.1 Ownership — Reconciled From 6D (§5.4 finding #4, §6 row 6/7)

Per the governing task's explicit preference — "6E owns Agent configuration reference-data reads because this information is primarily used while configuring Agent STT/TTS/LLM capability" — the following two read-only endpoints move from 6D's authority to 6E's, **unchanged in path, shape, permission, and behavior**:

| Endpoint | Purpose | Adopted from |
|---|---|---|
| `GET /api/v1/provider-health` | Read-only routing/health observability, informing `ModelConfig` selection | 6D §28.31, unchanged |
| `GET /api/v1/language-evaluations` | Platform reference data — which providers are capable/evaluated for a given language/capability, informing an Agent Builder's manual `LanguagePolicy`/`VoiceConfig`/`ModelConfig` decisions (a human-browsing use, not an automated per-provider validation — §15.5's scoping correction) | 6D §28.35, unchanged |

### 20.2 What Is Exposed, What Is Not — Restated

`GET /provider-health` returns, per active `voice.provider_configs` row visible to the tenant: `provider_id`, `category`, `model_id`, `health_state`, `circuit_state`, `p50_latency_ms`, `error_rate_pct`, `supports_languages[]`, `priority`. **Never** `credential_ref`, `config_json`, or `last_health_check_at`'s raw scheduling internals (6D §15.2, unchanged; §27 restates as 6E's own PII matrix).

`GET /language-evaluations` returns `language`, `provider_id`, `provider_model_ref`, `capability`, `scores[]`, `verdict`, `evaluated_at` — platform-scoped reference data (5C §5.12, no RLS, `app_platform_admin`-only write path), backed by §15.6 query (A) (5C §15.12's own reference-list query, pre-filtered to `APPROVED`/`CONDITIONAL` — a human deciding what to configure has no use for options already known not to work). This is a **different query from, and serves a different purpose than**, §15.6 query (B) — the unfiltered, `provider_id`-specific, `REJECTED`-visible lookup 6E's own publish-time LLM validation uses internally (§15.4 rules #13/#14). The two are never conflated: this endpoint is for a human browsing options; query (B) is for 6E's own automated gate, and is never itself exposed as a public endpoint. No mutation endpoint is exposed here — this document does not design a platform-admin write surface for evaluation records, matching 6D's own posture ("Do not expose platform-admin mutation endpoints unless a frozen requirement defines them" — none does).

### 20.3 Hot-Path Discipline — Unchanged

Both endpoints are Tier A reads, backed by Redis-cached or directly-indexed data (6D §15.4) — never a live provider probe. Reading them at Agent-configuration time (PATCH/publish) has zero relationship to the Voice-turn hot path; §22 restates this explicitly.

### 20.4 What Remains 6D's — Provider Routing/Failover Runtime

The **decision logic** that consumes this data per-turn (`ModelRouter.select()`, `ProviderSelectionService.select()`, circuit-breaker state transitions) remains entirely 6D's territory, unmoved. 6E's ownership of the read-only reference-data *view* does not imply ownership of the runtime *behavior* that also reads the underlying table — exactly the same split already drawn for `VoiceConfig`/`ModelConfig` themselves (§10.2, §11.3).

---

## 21. Tool Definition Ownership Boundary

### 21.1 The Decision — Option A, With Reasoning

Per the governing task's explicit instruction to choose between Option A (6E owns Tool Definition management, since tools are configured on Agents) and Option B (Tool Definitions remain a shared resource carried forward from 6D unchanged): **this document adopts Option A.**

**Reasoning:** `ToolDefinition` (4B §5.4) exists to be referenced by `Agent.tool_permissions` (§13) — its entire reason for being tenant-CRUD-able is that an Agent Builder needs to define what an Agent can invoke. `ToolExecution` (4B §5.5, DDR-4B-004), by contrast, is a *separate* aggregate with its own runtime lifecycle (`PENDING → RUNNING → SUCCEEDED/FAILED/TIMED_OUT`) driven entirely by the in-process turn loop (4B §18.3) — it is Call/Conversation/Turn-adjacent, not Agent-configuration-adjacent, and correctly remains 6D's. Splitting the two aggregates' authoritative-document ownership along exactly the line 4B already drew between them (DDR-4B-004's own stated rationale: separate lifecycle, separate query needs) is the reconciliation that introduces the least new surface area while best matching the domain model's own boundary.

### 21.2 Endpoints — Adopted From 6D §18.1/§28.24–28.28, Unchanged

| Endpoint | Purpose | Adopted from |
|---|---|---|
| `GET /api/v1/tools` | List tools visible to the tenant (built-in ∪ own) | 6D §28.24 |
| `POST /api/v1/tools` | Create a tenant custom tool | 6D §28.25 |
| `GET /api/v1/tools/{tool_id}` | Get one tool, full schema | 6D §28.26 |
| `PATCH /api/v1/tools/{tool_id}` | Update a tenant-owned tool | 6D §28.27 |
| `POST /api/v1/tools/{tool_id}/deactivate` | `is_active: true → false` | 6D §28.28 |

Path, response shape, permission, and audit-`action_kind` are unchanged from 6D. `input_schema`/`output_schema` well-formed-JSON-Schema validation (6D §18.1) is unchanged. §21.2a below adds one new, explicitly disclosed request-validation rule that 6D's frozen text never specified.

### 21.2a Visible Tool-Name Uniqueness — New, Explicit Invariant (6E refinement; ADR-6E-12)

**The gap this subsection closes:** 5C §16.5's migration DDL defines exactly two unique indexes for `voice.tool_definitions`: `uq_td_platform_name` on `tool_name` `WHERE organization_id IS NULL` (platform built-ins are unique among themselves) and `uq_td_tenant_name` on `(organization_id, tool_name)` `WHERE organization_id IS NOT NULL` (a tenant's own custom tools are unique among themselves) — 5C §9.6's design-level index table names the same two indexes `uq_tool_name_platform`/`uq_tool_name_tenant`, a pre-existing internal naming inconsistency between 5C's design and migration sections that this document does not attempt to resolve (out of scope — no Phase 5 edit is made). **Neither index, nor any other Phase 5 constraint, prevents a tenant's custom tool from sharing a `tool_name` with a platform built-in** — the two indexes protect two independent namespaces, not one merged one. A tenant could create a custom tool named `createLead` even though a platform built-in named `createLead` already exists and is visible to that same tenant (5C §11.3's mixed-scope read policy: built-in ∪ own). Because the Voice/Tool runtime resolves/invokes tools by `tool_name` inside a turn (3B §12.1's tool-call flow), this ambiguity is a real operational hazard, not merely a cosmetic one — a prior correction pass's threat-model claim that Phase 5 indexes alone prevent this collision was incorrect and is retracted (§35).

**The corrected invariant — an API/application-layer check, not a Phase 5 change:** for `POST /api/v1/tools` and any `PATCH /api/v1/tools/{tool_id}` that changes `tool_name`, the requested name must be unique across the tenant's **entire visible tool namespace** — the union of platform built-ins (`organization_id IS NULL`) and that tenant's own custom tools (`organization_id = tenant`) — not merely unique within the tenant's own scope. The check reads: `SELECT 1 FROM voice.tool_definitions WHERE tool_name = $tool_name AND (organization_id IS NULL OR organization_id = $tenant_id) AND id <> $excluded_id LIMIT 1` (an ordinary `SELECT`, no new index, no `SELECT ... FOR UPDATE`). A match → `409 STATE_CONFLICT`, `error.details.field: "tool_name"`, `error.details.reason: "tool_name_conflicts_with_visible_tool"`.

**Why `409 STATE_CONFLICT`, not a new error code:** per the governing task's explicit preference and 6A §7.4/§24.2's existing family — a name-collision-on-create/rename is a conflict with the current state of the visible namespace, the same class of condition 6D's own `tool_name` uniqueness-within-tenant check already used `409 STATE_CONFLICT` for (6D §28.25); this document widens the *scope* of the check, not the *error family* it reports through.

**Concurrency scope — corrected this pass, narrowed to what can actually happen on the 6E mutation surface today:**

- **Tenant-vs-own-tenant collision** (two concurrent `POST /tools`, or a create racing a rename, both targeting the same name within one tenant's own custom-tool scope): a genuine race, resolved by whichever transaction's `INSERT`/`UPDATE` commits first — the loser's own `uq_td_tenant_name` index raises `23505`, surfaced as `409 STATE_CONFLICT`. This is a real DB-backed guarantee, not merely the application-layer `SELECT`.
- **Tenant-vs-platform-built-in collision:** **this is not a race at all, and this document no longer describes it as one.** 6E exposes no endpoint that creates, renames, or otherwise mutates a platform built-in (`organization_id IS NULL`) row — built-ins are seeded/provisioned entirely outside 6E's mutation surface (5C §16.9's seed data, an ops/migration-time concern, not a 6E API path). A built-in's `tool_name` is therefore always already-committed, static data at the instant any 6E tenant request's own visible-namespace `SELECT` runs — there is no concurrent writer to race against, so the check is fully reliable for this case under ordinary READ COMMITTED semantics, with no TOCTOU window to disclose.
- **The invariant is therefore fully resolved for 6E's actual tenant ToolDefinition mutation surface** — both halves (tenant-vs-tenant, DB-backed; tenant-vs-built-in, reliable-by-construction since built-ins are immutable from 6E's perspective) hold without any open residual. **Should a future platform-admin/built-in provisioning API ever be designed** (not designed here, and not implied by this document), **it must independently enforce this same visible-namespace invariant before introducing or renaming a built-in** — a genuine race would only become possible at that point, and is explicitly out of scope for this document to resolve in advance.

### 21.3 What Stays 6D's — Tool Execution Observation

`GET /api/v1/conversations/{conversation_id}/tool-executions` and `GET /api/v1/tool-executions/{execution_id}` (6D §28.29–28.30) are **not** moved — they remain 6D's, gated by `call:read`, tied to Conversation/Turn context, never a tenant-invoked create/retry/cancel (4B §5.5 invariant 2).

### 21.4 No Duplicate Paths — Explicit Guarantee

No endpoint in this document is served at a second, parallel path. `/api/v1/tools*` has exactly one authoritative home going forward (this document); 6D's `§18`/`§28.24–28.28` text remains historically accurate as the origin of the contract and is not edited, but a reader implementing against Phase 6 going forward should treat 6E as the current source of truth for these five endpoints' management semantics, exactly as for the Agent endpoints themselves (§5.3).

### 21.5 Workflow Tool Execution — Not Designed Here

Per the governing task's explicit instruction: this document does not design Workflow-context tool-execution APIs (a Workflow node that itself invokes a tool via the Workflow Engine, as opposed to the Voice turn loop invoking one) — that is 6I's (Workflow APIs) territory if/when such a capability is designed.

---

## 22. Agent Configuration and the Frozen ≤750ms Voice Runtime Boundary

### 22.1 The Binding Constraint, Restated Without Alteration

6D §21 froze the Voice-turn latency architecture: **≤750ms p50, no-tool conversational turn**, layered on the ~725ms reference design budget (3B §21/6A §11) and the <800ms `NFR-PERF-001` ceiling. **This document changes none of these numbers, none of their classification as TARGET-not-MEASURED, and none of the reasoning in 6D §21.2–21.13.** 6E is a control-plane, Agent-*management* API phase — Agent CRUD/publish/version reads are categorically not on the per-turn hot path, and nothing in this document may be read as loosening that separation.

### 22.2 What 6E Must Ensure, Explicitly

- **AgentVersion snapshot prepared at publish, once.** All of §15's validation and §16's normalization work happens at publish time — never re-run per call, never re-run per turn.
- **Immutable snapshot, hot-cache-friendly structure.** `snapshot_json`/`language_policy` (5C §5.5) are exactly what 6D's `agent_version:{version_id}:snapshot` Redis cache (6D §22, unchanged, consumed not redesigned here) serves to the Voice runtime — 6E introduces no additional structure the runtime would need to reshape before use.
- **Provider preferences already normalized/validated where possible.** §15.4's provider/language checks run once, at publish — the Voice runtime never re-validates a pinned version's `model_config`/`language_policy` at call time; it trusts the snapshot exactly because 6E already proved it valid at the moment it became immutable.
- **No `draft_config` DB fetch every turn.** The Voice runtime never reads `voice.agents.draft_config` at all, on any path — only the pinned `AgentVersion.snapshot_json`, resolved once at call start (6D §9.1).
- **No Agent REST call from the Voice runtime, anywhere, ever.** `CallRoutingService.resolve()` (§6 row 3) is in-process; this document introduces no HTTP-reachable variant of it, public or internal.
- **No publish-time process blocks an active call.** Publishing version N+1 while calls are pinned to version N is a single, short, two-aggregate transaction (§16.2) with no cross-call side effect — restated from §16.1.
- **No runtime validation of static Agent configuration that §15 could have done at publish.** Everything in §15.4's table is checked exactly once, at publish; nothing in it is re-checked per turn.
- **No per-turn call to any 6E-designed endpoint.** None of this document's 17 endpoints (§30) is ever invoked from inside the STT→LLM→TTS loop (3B §12) — every one is a Tier A/B REST request, entirely outside 6D §7.3's Tier E realtime classification.

### 22.3 The One-Sentence Summary

**6E must reduce runtime configuration work, not add to 6D's hot-path budget** — every design choice in §9–§21 above was evaluated against this sentence, and none of them introduces a new per-call or per-turn cost.

### 22.4 AgentVersion Pinning — Restated as a Binding Integration Invariant

A Call resolves and pins exactly one `agent_version_id` at call start (6D §9.1, 4B §5.1 invariant 1). After that: an Agent `PATCH` cannot affect the call; a subsequent `publish` (version N+1) cannot affect the call; a `deprecate` cannot rewrite the call; provider/model/voice configuration for that call is read exclusively from the pinned immutable snapshot. **No endpoint in this document mutates `call_sessions.agent_version_id` after call creation** — 6E defines no such endpoint, and none of its endpoints touches the `voice.call_sessions` table at all, in any column, at any time.

### 22.5 No New Agent-Management Latency SLO

Per the governing task's explicit instruction: this document does not invent a separate Agent-management latency SLO. Every 6E endpoint inherits its latency tier from 6A §11 exactly as 6D's Agent endpoints originally did (Tier A for reads, Tier B for `publish`/`deprecate`/`clone` — §33 restates the exact tier assignments).

---

## 23. Caching / Runtime Snapshot Consumption

### 23.1 Cache Keys 6E's Endpoints Write To — Unchanged From 6D §22

| Cache key | Contents | Written by (6E endpoint) | Read on hot path? |
|---|---|---|---|
| `agent_version:{version_id}:snapshot` | `AgentVersion.snapshot_json`, immutable | `POST /agents/{id}/publish` (write-through, §16.5) | Yes — read once per call at `CallRoutingService.resolve()` (6D territory), never re-read mid-call |
| `provider_config:{org_id}:{category}` | Ordered `ProviderConfig` candidate list | Not written by any 6E endpoint (read-only reference data, §20) — written by whatever admin/config-change path 6D/3B already document | Yes, by 6D's runtime — 6E's `GET /provider-health` reads the same cache, does not write it |

6E writes to exactly one cache key (`agent_version:{version_id}:snapshot`, on successful publish) — the same write-through behavior 6D §22 already documents for this key, unchanged.

### 23.2 No New Cache Key Invented

`PATCH /agents/{id}` invalidates nothing — draft edits do not touch published snapshots, so there is nothing to invalidate (6D §28.4, unchanged). No 6E endpoint constructs a cross-tenant cache key (6A §36's prohibition, restated).

---

## 24. Transaction Boundaries

### 24.1 The Governing Rule — 6A §35, Unmodified, Reused Verbatim

Never hold a DB transaction open while waiting on an AI provider, telephony provider, or external HTTP call. Standard shape: validate (no I/O) → short DB transaction (single aggregate, or an approved exception) → commit → async/external processing outside the transaction.

### 24.2 Which of 6A §35's Named Exceptions 6E Uses

| 6A §35 approved exception | Used by 6E? | Where |
|---|---|---|
| **Publish Agent + AgentVersion** | **Yes** | `POST /agents/{id}/publish` (§16.2) — the one same-transaction, cross-aggregate write in this document, reusing 6A's existing named exception exactly, adding no new one |
| All others (Create Organization + Membership, Start Call + Conversation, Transfer Ownership, Publish Workflow + WorkflowVersion, CSV import batch) | No | Owned elsewhere (6C, 6D, future 6I) |

**No new transaction-boundary exception is added by 6E.** Every other 6E-touched effect — `agent.created`/`agent.config_updated`/`agent.published`/`agent.deprecated` outbox propagation, Tool Definition lifecycle events — is asynchronous and event-driven (§26), per 6A §35's closing rule: an endpoint's synchronous response never waits for a downstream effect to complete.

### 24.3 Per-Endpoint Transaction Shape

**`POST /agents` / `PATCH /agents/{id}` / `POST /agents/{id}/deprecate`:** one transaction, one aggregate (`voice.agents`), plus the synchronous audit-function call (§25) — the default single-aggregate case, no exception needed.

**`POST /agents/{id}/clone`:** one transaction, one aggregate (the **new** `voice.agents` row) — reading the source Agent's `draft_config` (or a source `AgentVersion.snapshot_json`) happens as an ordinary `SELECT` before the `INSERT`, within the same transaction, no cross-aggregate write (the source Agent is not mutated by a clone).

**`POST /agents/{id}/publish`:** the one named exception (§24.2) — `voice.agents` (UPDATE) + `voice.agent_versions` (INSERT) in one transaction, as detailed in §16.2.

**`POST /tools`, `PATCH /tools/{id}`, `POST /tools/{id}/deactivate`:** one transaction, one aggregate (`voice.tool_definitions`) — unchanged from 6D §18.1's original transaction shape.

---

## 25. Audit

### 25.0 The Durable Audit Trail — `audit.fn_insert_audit_event()`, Never a Direct INSERT (unchanged, binding, reused from 6D §24.0)

Every state-changing endpoint in this document follows exactly the pattern 6D §24.0 established and this document's Document Control table confirms requires no further amendment:

```
BEGIN
  <domain mutation on voice.agents / voice.agent_versions / voice.tool_definitions>
  SELECT audit.fn_insert_audit_event(
    p_organization_id => <tenant id>, p_actor_type => 'USER'|'API_KEY',
    p_actor_ref => <actor id>, p_actor_name => <display name/key prefix>,
    p_action_kind => '<governed 5J §14.3 value>', p_resource_type => '<resource>',
    p_resource_id => <resource id>, p_outcome => 'SUCCESS', p_failure_reason => NULL,
    p_ip_address => <ip>, p_user_agent => <ua>, p_session_id => <sid>,
    p_request_id => <request id>, p_correlation_id => NULL,
    p_resource_snapshot => <5B §30 allow-listed fields>, p_is_platform_event => FALSE
  );  -- (1) THE DURABLE AUDIT TRAIL — sole legal write path, 5J §5/§14.2 REVOKE ALL
  INSERT INTO audit.domain_event_outbox (event_type = <domain event>, ...)  -- (2) OPTIONAL, separate
COMMIT
```

`audit.fn_insert_audit_event(...)` is the **sole legal write path** to `audit.audit_events` — no application role holds `INSERT` privilege on that table (5J §5/§14.2, `REVOKE ALL`). A raised exception (e.g., tenant mismatch) aborts the whole transaction, including the domain mutation. `audit.domain_event_outbox` is a separate, ordinary `INSERT` (application roles do hold that privilege, 5J/077) — never a substitute for, and never a precondition for, the audit-function call.

### 25.1 Why No Further 5J Amendment Is Required

Every `action_kind` this document's mutations need already exists in 5J §14.3, added by 6D's own already-authorized `‡` amendment: `AGENT_CREATED`, `AGENT_CONFIG_UPDATED`, `AGENT_PUBLISHED`, `AGENT_DEPRECATED`, `TOOL_DEFINITION_CREATED`, `TOOL_DEFINITION_UPDATED`, `TOOL_DEFINITION_DEACTIVATED` — verified directly against 5J §14.3's current text (§4 of this document). 6E introduces **zero new mutation types** beyond what 6D already named and governed; it only moves which document is the authoritative narrator of the endpoints that produce these same `action_kind`s. This is `DEP-6E-06`, resolved by observation, not by any new amendment (§38).

### 25.2 The 5J §14.5 Synchronous Exception — Reviewed, Consumed As-Is

5J §14.5's `‡` clarification names, verbatim, the exact four Agent `action_kind`s and three Tool Definition `action_kind`s this document's mutations produce, as an explicit synchronous exception to the general "Configuration... lifecycle changes → Asynchronous" rule — citing `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md` as the document that required it. The clarification's substance is **action-kind-scoped**, not endpoint-owning-document-scoped: it says which *strings* must be written synchronously, not which *document* is authoritative for the endpoints that write them. Since 6E introduces no new `action_kind` and does not change the synchrony requirement for any of the ones it uses, **the existing 5J §14.5 wording remains fully accurate and sufficient as written.** No amendment is made. This is `DEP-6E-07`, resolved by observation (§38) — the governing task's own instruction ("If yes: consume it; do not create another redundant amendment") applies directly: 6E consumes 5J §14.5's exception exactly as 6D left it.

### 25.3 Per-Endpoint Audit Coverage

| Endpoint | `action_kind` | Category |
|---|---|---|
| `POST /agents` | `AGENT_CREATED` | A — exact match |
| `PATCH /agents/{id}` | `AGENT_CONFIG_UPDATED` | A — exact match |
| `POST /agents/{id}/publish` | `AGENT_PUBLISHED` | A — exact match |
| `POST /agents/{id}/deprecate` | `AGENT_DEPRECATED` | A — exact match |
| `POST /agents/{id}/clone` | `AGENT_CREATED` (same value as create — §18.4) | A — exact match |
| `POST /tools` | `TOOL_DEFINITION_CREATED` | A — exact match |
| `PATCH /tools/{id}` | `TOOL_DEFINITION_UPDATED` | A — exact match |
| `POST /tools/{id}/deactivate` | `TOOL_DEFINITION_DEACTIVATED` | A — exact match |
| `GET` endpoints (agents, versions, tools, provider-health, language-evaluations) | None — reads are not audited | N/A |

**All eight state-changing 6E endpoints have an exact-match, governed `action_kind` — zero Category C gaps.**

---

## 26. Domain Events / Outbox

### 26.1 Mechanism — Unchanged From 6D §24.1–24.3

Three mechanisms, not conflated: the durable audit write (§25), the request-transaction durable outbox event (this section), and — not applicable to 6E, since 6E has no realtime WS surface — the realtime WebSocket event. Delivery semantics for the outbox path are **at-least-once, never exactly-once** (6C §20/§27 DEP-6C-16, reused verbatim) — this caveat has no bearing on `audit.audit_events`, which is synchronous and same-transaction (§25.0).

### 26.2 What Goes Through the Outbox

| Outbox-routed event | Trigger | Consumed by |
|---|---|---|
| `agent.created` | `POST /agents`, `POST /agents/{id}/clone` | None currently; retained for a defined future integration (Analytics agent-lifecycle projections, 6L+) |
| `agent.config_updated` | `PATCH /agents/{id}` | None currently; same as above |
| `agent.published` | `POST /agents/{id}/publish` | None currently; same as above — **not** consumed by any 6E-internal mechanism (the Redis-cache write-through in §23.1 happens inline in the same request, not via the outbox) |
| `agent.deprecated` | `POST /agents/{id}/deprecate` | None currently; same as above |
| `tool_definition.*` (created/updated/deactivated) | §21.2 endpoints | None currently; retained for a defined future integration (Analytics tool-usage projections, 6L+) |

No consumer is invented merely to fill this column — matching 6D §24.2's own explicit discipline. `audit.domain_event_outbox`'s "Consumed by" column, per 6D's own corrected framing (its ADR-6D-15), never lists "Audit" — the audit record for every row above is already durably written, synchronously, via `audit.fn_insert_audit_event(...)` in the *originating* transaction, before the outbox row is even inserted.

---

## 27. Authorization Matrix

Every row: endpoint, permission (5B §17.2, exact), actor eligibility, API-key eligibility, cross-tenant behavior (uniformly `404`, never `403`, per 6B/6C/6D's established non-disclosure discipline — restated once here).

| Endpoint | Permission | Role grant (5B §17.2) | Actor | API key? |
|---|---|---|---|---|
| `POST /agents` | `agent:write` | OWNER, ADMIN, MEMBER | USER | Yes |
| `GET /agents`, `GET /agents/{id}` | `agent:read` | OWNER, ADMIN, MEMBER, VIEWER | USER, API_KEY | Yes |
| `PATCH /agents/{id}` | `agent:write` | OWNER, ADMIN, MEMBER | USER | Yes |
| `POST /agents/{id}/publish` | `agent:publish` | OWNER, ADMIN only | USER | **No** — human-gated, matching 6D's precedent |
| `POST /agents/{id}/deprecate` | `agent:delete` (reused, §19.3) | OWNER, ADMIN only | USER | No |
| `POST /agents/{id}/clone` | `agent:write` | OWNER, ADMIN, MEMBER | USER | Yes |
| `GET /agents/{id}/versions[/{id}]` | `agent:read` | OWNER, ADMIN, MEMBER, VIEWER | USER, API_KEY | Yes |
| `GET /tools`, `GET /tools/{id}` | `agent:read` (interim reuse, inherited `DEP-6D-02` → `DEP-6E-08`) | OWNER, ADMIN, MEMBER, VIEWER | USER, API_KEY | Yes |
| `POST /tools`, `PATCH /tools/{id}`, `POST /tools/{id}/deactivate` | `agent:write` (interim reuse, same lineage) | OWNER, ADMIN, MEMBER | USER | Yes |
| `GET /provider-health` | `agent:read` (adequate reuse, no gap) | OWNER, ADMIN, MEMBER, VIEWER | USER, API_KEY | Yes |
| `GET /language-evaluations` | `agent:read` (adequate reuse, no gap) | OWNER, ADMIN, MEMBER, VIEWER | USER, API_KEY | Yes |
| `GET /api/internal/v1/agents/{agent_id}/versions/{version_id}` | None — internal service JWT only (6A §23.4, 6B §17) | PLATFORM_ADMIN via internal service | Internal service | No |

**No new permission string is invented anywhere in this table.** `agent:read`, `agent:write`, `agent:publish`, `agent:delete` are the four real, existing permissions (5B §17.2, verified §4) this document uses; none of `agent:clone`, `agent:validate`, `agent:version`, or `agent:deprecate` is created, per the governing task's explicit instruction — the existing four adequately cover every 6E operation without over-granting (§27.1).

### 27.1 Over-Grant Review

Every mapping above is re-verified against 5B §17.2's canonical role-permission matrix (§4), following the same discipline 6D's own Task K review applied. **No over-grant is found:** `agent:write` (`OWNER/ADMIN/MEMBER`) already lets a `MEMBER` fully control an Agent's `tool_permissions` (§13) — extending the same actor set to Tool Definition CRUD (§21) introduces no privilege a `MEMBER` did not already effectively hold, exactly matching 6D's own DEP-6D-02 reasoning, now carried forward under 6E's authority.

### 27.2 API-Key Eligibility — Reconciled

Consistent with 6D's posture: `create`, `update draft`, `clone`, `read versions`, tool CRUD, and reference-data reads are all API-key-eligible (programmatic Agent-management workflows are a legitimate, common integration pattern — e.g., a CI/CD-style Agent-configuration pipeline). **`publish` and `deprecate` remain human/session-restricted, no API key** — the same "sensitive go-live lifecycle action" reasoning 6D already established for `publish` (its own `agent:publish` grant excludes API keys structurally, since `identity.api_keys.scopes` is intersected with the issuing user's permissions **at issuance time**, 6B §16.4, and `agent:publish`'s restriction to `OWNER`/`ADMIN` is a role-level, not scope-level, gate this document does not weaken).

---

## 28. PII / Data Exposure

### 28.1 Field / Resource Matrix

| Field / resource | PII class | Exposed via | Never exposed via |
|---|---|---|---|
| `agents.draft_config` (`prompt_ref`, `workflow_ref`, `knowledge_base_refs`) | Opaque references only — no raw prompt/workflow/knowledge-base *content* is stored in `voice.agents` itself | `GET /agents/{id}` | The actual prompt/workflow/knowledge-base content — never in any 6E response (owned by a later phase) |
| `agent_versions.snapshot_json` / `language_policy` | Same opaque-reference class, frozen at publish time | `GET /agents/{id}/versions/{id}` | Same exclusions as above, permanently, since the snapshot is immutable |
| `tool_definitions.input_schema` / `output_schema` | Tenant-authored JSON Schema, not classified `pii:*` | `GET /tools/{id}` | — |
| `provider_configs.credential_ref` | Secret reference | **Never** — not present in any 6E response model | — |
| `provider_configs.config_json` | May contain non-secret but internal routing parameters | **Never** — excluded from `GET /provider-health`'s response allow-list (§20.2) | — |
| `language_evaluation_records.*` | Platform reference data, no PII | `GET /language-evaluations` | — |

### 28.2 Absolute Prohibitions — Restated, Unchanged (6A §22/§24.3)

No 6E response ever contains a raw `credential_ref` value, an encryption key, a token hash, or internal provider-SDK credentials. No 6E error response ever contains SQL text, stack traces, or internal service/schema/function names.

### 28.3 AgentVersion Snapshot Secret-Safety — Structural for Every Field Except One, Mitigated for That One

This is the single most important secret-safety property this document must guarantee, since a published `AgentVersion` snapshot is **permanent and immutable** (§16.1) — a secret accidentally frozen into it can never be redacted, only made unreadable by deleting the whole row (which no command supports, §19.2). **The claim below is stated at the strength the schema actually supports — it is not a blanket guarantee for every field.**

**Structurally guaranteed (closed-shape fields):** `voice_config`, `model_config`, `language_policy`, `prompt_ref`/`workflow_ref`/`knowledge_base_refs`, `tool_permissions`, and `calling_hours` all have a closed, fully-typed shape (§9.1, §10–§14) — enums, numbers, opaque UUID references, or provider identifiers (`model_config.preferred_provider`/`fallback_providers` are `voice.provider_configs.provider_id` strings like `"openai"`, never `credential_ref` values or raw API keys, §11.2). There is no code path by which a secret-shaped value could enter any of these fields, because none of their allow-listed keys is shaped to hold one.

**Not structurally guaranteed — mitigated only at the output side (`qualification_criteria`), corrected this pass:** per §9.4, this one field is genuinely open-ended JSON with no closed schema anywhere in Phase 1–5, and **this document no longer applies any input-side key-name validation rule to it** — a prior pass's `422`-rejection rule cited 6A §22's logging/tracing redaction vocabulary as authorization, which does not actually support rejecting API input (§9.4 states the retraction in full). The only mitigation that remains is that `qualification_criteria`'s raw contents are never written to logs, traces, or an audit `resource_snapshot` (§9.4, §25.0) — a genuine application of 6A §22's actual scope (output redaction), not a fabricated one. **This document does not claim there is no possible code path for secret-shaped content to enter `snapshot_json` via `qualification_criteria`, and does not claim any input-side control exists for this field at all** — only that every *other* field is genuinely closed, and that this one field's exposure is at least bounded on the observability side.

This residual is tracked as `DEP-6E-16` in the dependency register (§38) — re-scoped by this correction pass a second time to remove the now-retracted input-validation claim and state the honest, narrower mitigation that remains.

---

## 29. Error Catalog

### 29.1 Reused From 6A/6B/6C/6D, Unmodified

`VALIDATION_ERROR`, `AUTHENTICATION_REQUIRED`, `AUTHORIZATION_DENIED`, `RESOURCE_NOT_FOUND`, `STATE_CONFLICT` (every guarded-transition 409, carrying `error.details.current_state`), `PRECONDITION_FAILED` (ETag mismatch on `PATCH`, and the new optional `If-Match` on `publish`, §16.6), `IDEMPOTENCY_KEY_REUSE_MISMATCH`, `RATE_LIMIT_EXCEEDED`, `DEPENDENCY_UNAVAILABLE`, `INTERNAL_ERROR`.

### 29.2 6D's Existing Voice-Specific Codes — Not Reused Here, By Design

`AGENT_NOT_PUBLISHED` (6D §27.2) fires on `POST /calls` when a referenced Agent has no `PUBLISHED` version — that is a Call-initiation-time check, entirely 6D's territory (§3.2); no 6E endpoint ever returns it, since no 6E endpoint initiates a call.

### 29.3 New — Genuinely Agent-Management-Specific (justified individually)

No new error code is introduced. Every condition this document's endpoints can produce is adequately covered by an existing family with structured `error.details`:

| Condition | Code used | `error.details` |
|---|---|---|
| Duplicate `tool_id` in `tool_permissions` | `VALIDATION_ERROR` (422) | `{ "field": "tool_permissions", "reason": "duplicate_tool_id", "tool_id": "..." }` |
| Duplicate/self-referential entry in `fallback_providers` | `VALIDATION_ERROR` (422) | `{ "field": "model_config.fallback_providers", "reason": "duplicate_or_repeats_preferred" }` |
| `LanguagePolicy` internal-consistency violation | `VALIDATION_ERROR` (422) | `{ "field": "language_policy", "reason": "<specific rule name, §12.2>" }` |
| Dangling/inactive tool reference at publish | `VALIDATION_ERROR` (422) | `{ "field": "tool_permissions", "tool_id": "..." }` — exact reuse of 6D's existing shape |
| Provider/language capability `REJECTED` with no viable fallback | `VALIDATION_ERROR` (422) | `{ "field": "model_config", "reason": "no_capable_provider_for_language", "language": "..." }` |
| Concurrent-publish contention exhausted | `STATE_CONFLICT` (409) | `{ "reason": "concurrent_publish_contention" }` — exact reuse of 6D's `§9.2a` shape |
| Wrong Agent status for the requested action | `STATE_CONFLICT` (409) | `{ "current_state": "..." }` |
| Optional `If-Match` mismatch on publish | `PRECONDITION_FAILED` (412) | — |
| `tool_name` collides with another tool visible to the tenant (own or platform built-in), on create or rename | `STATE_CONFLICT` (409) | `{ "field": "tool_name", "reason": "tool_name_conflicts_with_visible_tool" }` — §21.2a |

**`qualification_criteria` has no dedicated error row — corrected this pass.** A prior version of this table included a `VALIDATION_ERROR` row for a `qualification_criteria` "prohibited key pattern" rejection. That rule is retracted (§9.4, §15.4) — no frozen standard authorizes rejecting API input on a key-name substring match, and the rule risked false positives against legitimate field names. `qualification_criteria` accepts any well-formed JSON object; its risk is mitigated at the output side (never logged/traced/audit-snapshotted, §9.4), not by an input-rejection error code.

Per the governing task's explicit caution against inventing a code when an adequate family exists: `AGENT_CONFIG_INVALID`, `AGENT_REFERENCE_INVALID`, and `AGENT_VERSION_CONFLICT` are all considered and **rejected** — `VALIDATION_ERROR` and `STATE_CONFLICT`, with structured `details`, already communicate every distinction a client needs.

---

## 30. Endpoint Contract Inventory

### 30.0 Shared Template

Every endpoint instantiates 6A's `{data, meta}`/`{error}` envelope and `request_id` propagation (6A §10/§24/§25). Tenant scope is `organization_id` resolved from the caller's JWT/API-key (6B §9); a path `{id}` belonging to another tenant yields `404 RESOURCE_NOT_FOUND`, never `403` (§27). Total: **16 public REST endpoints + 1 internal endpoint = 17.** Three endpoints are given full depth as showcases (`POST /agents`, `POST /agents/{id}/publish`, `POST /agents/{id}/clone`); the remainder use the compact form 6C/6D's own convention established.

### 30.1 `POST /api/v1/agents` — **Full depth (showcase)**

- **Purpose:** Create a new Agent in `DRAFT` (§8.4). **API surface:** Public. **Authentication:** access token or API key. **Authorization:** `agent:write`. **Actor:** USER, API_KEY. **Tenant scope:** resolved from JWT/API-key.
- **Request schema:** `{ "name": string(2-100), "description"?: string(0-500) }` — `extra="forbid"`; `draft_config`, `status`, `published_version_id`, `organization_id`, `deleted_at`, `created_at`, `updated_at` are all structurally absent from this schema (§9.2).
- **Validation:** `name` length; `description` length if present.
- **Response `201`:** full Agent resource — `id`, `name`, `description`, `status: "DRAFT"`, `published_version_id: null`, `draft_config: {}`, `created_by`, `created_at`, `updated_at`; `Location` header; weak `ETag`.
- **Errors:** `400`/`422` (name/description length), `401`, `403`.
- **Idempotency:** `Idempotency-Key` accepted, not required (§8.5).
- **Rate limit:** standard 300 req/min/org tier (§33).
- **Latency:** Tier A. **DB:** single-row `INSERT voice.agents`, plus `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_CREATED', ...)`, same transaction. **Cache:** none written. **RLS:** standard tenant policy (5C §11.1). **Audit:** `AGENT_CREATED` (Category A). **Domain event:** `agent.created` (outbox, separate write, §26.2). **Observability:** `agents_created_total` (no `organization_id` label, §34). **Transaction:** single-aggregate, no exception needed. **Side effects:** none. **Concurrency:** none (creating a `DRAFT` row has no contended resource). **PII/security:** no PII in the request or response beyond `name`/`description`, which are not classified `pii:*`.

### 30.2 `GET /api/v1/agents`

Purpose: list agents, paginated (cursor, 6A §14), filterable by `status`. Authz: `agent:read`. Response: paginated Agent summaries (`id`, `name`, `status`, `published_version_id`, `created_at`, `updated_at` — not the full `draft_config`, matching 6A §36's list-payload discipline). Latency: Tier A. Audit: none (read). Cache: none.

### 30.3 `GET /api/v1/agents/{agent_id}`

Purpose: get one Agent. Authz: `agent:read`. Response: full Agent resource incl. `draft_config`, `published_version_id`, `status`. Weak `ETag` (`hash(id, updated_at)`, 6A ADR-6A-08). Errors: `404`. Audit: none.

### 30.4 `PATCH /api/v1/agents/{agent_id}`

Purpose: update draft-config fields (§9's allow-list). Authz: `agent:write`. Headers: `If-Match` (optional, recommended). Request: any subset of §9's typed fields; `extra="forbid"` (§9.2). Validation: per-field per §15.1's continuous rule set, including the `tool_permissions[].tool_id` tenant-visibility check (not yet active-status-checked — that is publish-time only, §15.1). Response `200`: updated Agent. Errors: `400`/`422`, `403`, `404`, `412` (ETag mismatch). Concurrency: weak ETag (6A ADR-6A-08). Audit: `AGENT_CONFIG_UPDATED` (Category A), via `audit.fn_insert_audit_event(...)`. Domain event: `agent.config_updated` (outbox). Cache: none invalidated (§23.2).

### 30.5 `POST /api/v1/agents/{agent_id}/publish` — **Full depth (showcase)**

- **Purpose:** Snapshot the current `draft_config` into a new immutable `AgentVersion` and mark the Agent `PUBLISHED` (§16).
- **API surface:** Public. **Authentication:** Access token only — **no API key** (§27.2). **Authorization:** `agent:publish` (OWNER/ADMIN only). **Actor:** USER. **Tenant scope:** path `agent_id`, cross-checked.
- **Headers:** `Idempotency-Key` recommended, not required. `If-Match` optional (§16.6, new).
- **Request schema:** empty body — the snapshot is taken server-side from `Agent.draft_config` at publish time (4B §12.3's `PublishAgent` command comment, unchanged).
- **Validation:** §15.4's full table — every ERROR-classified check must pass; every WARNING-classified condition is collected into the response, not blocking.
- **Response `201`:** `{ "data": { "version_id", "version_number", "published_at", "warnings": [...], "agent": {...} } }` (§16.5).
- **Errors:** `403`, `404`, `409` (wrong status, or concurrent-publish contention exhausted, §16.4), `412` (optional `If-Match` mismatch), `422` (any ERROR-classified §15.4 failure, naming the offending field/reason).
- **Rate limit:** 30/hour/org (configurable default, unchanged from 6D). **Idempotency:** recommended. **Latency:** Tier B — one short, same-transaction, two-aggregate write (6A §35's named exception, §24.2); no external call.
- **Database:** `voice.agent_versions` (INSERT), `voice.agents` (UPDATE `status`, `published_version_id`), `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_PUBLISHED', ...)`, `audit.domain_event_outbox` (INSERT `agent.published`) — all one transaction.
- **Cache:** `agent_version:{new_version_id}:snapshot` populated write-through (§23.1).
- **RLS:** standard tenant policy on both tables (5C §11.1).
- **Audit:** `AGENT_PUBLISHED` (Category A).
- **Domain event:** `agent.published` (outbox → Redis Streams, at-least-once).
- **Observability:** `agent_published_total`, `agent_publish_validation_failures_total{reason_category}` (bounded reason categories, e.g. `tool_reference`, `language_policy`, `provider_reference` — never the raw field/tool_id/agent_id itself), `agent_publish_23505_retries_total` (§34).
- **Transaction:** the one named 6A §35 exception this document uses.
- **Side effects:** none beyond the two-row write — no active Call is affected (§22.4).
- **Concurrency:** full analysis §16.3–16.4/§32.
- **Security:** the empty request body is deliberate — a publish can never smuggle in `draft_config` values that did not go through §30.4's own validation pipeline.

### 30.6 `POST /api/v1/agents/{agent_id}/deprecate`

Purpose: `PUBLISHED → DEPRECATED` (§19.1). Authz: `agent:delete`. Guard: current status must be `PUBLISHED` → `409 STATE_CONFLICT` otherwise. Response `200`: updated Agent. Latency: Tier B. Audit: `AGENT_DEPRECATED` (Category A). Domain event: `agent.deprecated` (outbox).

### 30.7 `POST /api/v1/agents/{agent_id}/clone` — **Full depth (showcase)**

- **Purpose:** Create a new `DRAFT` Agent copying `draft_config` from this Agent's current draft, or from a specified `AgentVersion` (§18).
- **API surface:** Public. **Authentication:** access token or API key. **Authorization:** `agent:write`. **Actor:** USER, API_KEY.
- **Request schema:** `{ "source": "draft" | "<published_version_id UUID>" }`.
- **Validation:** if `source` is a `published_version_id`, it must resolve to a version of *this* Agent, tenant-scoped (`404` cross-tenant/nonexistent).
- **Response `201`:** new Agent resource, `status: "DRAFT"`, `published_version_id: null` (§18.2), `Location` header.
- **Errors:** `400`, `403`, `404`.
- **Idempotency:** not required (creating a new `DRAFT` row has no dangerous real-world consequence, same reasoning as §30.1).
- **Rate limit:** standard 300 req/min/org tier.
- **Latency:** Tier B (single-aggregate write, but classified alongside the other lifecycle actions for consistency with 6D's original tiering — no external call either way).
- **Database:** `SELECT` on the source (`voice.agents.draft_config` or `voice.agent_versions.snapshot_json`), `INSERT voice.agents` (new row), `SELECT audit.fn_insert_audit_event(p_action_kind => 'AGENT_CREATED', ...)` — one transaction, single new aggregate (§24.3).
- **Cache:** none written.
- **RLS:** standard tenant policy.
- **Audit:** `AGENT_CREATED` (Category A, §18.4).
- **Domain event:** `agent.created` (outbox).
- **Observability:** `agents_cloned_total` (no `agent_id` label, §34).
- **Transaction:** single-aggregate — the source Agent is read, never mutated, so no cross-aggregate exception is needed even though two rows are involved.
- **Side effects:** none.
- **Concurrency:** the source's `draft_config` may change between the clone's `SELECT` and its own commit under a concurrent `PATCH` on the source — this is the same READ-COMMITTED-consistent, non-corrupting race already analyzed in §16.3, applied to a read instead of a publish; whichever committed value exists at the moment of the clone's `SELECT` is what gets copied, and this is disclosed as expected, non-blocking behavior, not a defect.
- **Security:** no PII beyond what `agent:read` on the source would already expose to the same actor.

### 30.8 `GET /api/v1/agents/{agent_id}/versions`

Purpose: list versions, newest first (§17.3). Authz: `agent:read`. Pagination: cursor (6A §14). Response fields: `version_id`, `version_number`, `published_by`, `published_at` — not the full `snapshot_json`.

### 30.9 `GET /api/v1/agents/{agent_id}/versions/{version_id}`

Purpose: get one version's full immutable snapshot, incl. `language_policy` (§17.1). Authz: `agent:read`. Response: read-only — no `PATCH`/`PUT` exists for this resource by design (§8.3, 5C §11.6 trigger-enforced immutability).

### 30.10 `GET /api/v1/tools`

Purpose: list tools visible to the tenant (built-in ∪ own, §21.2). Authz: `agent:read`. Filters: `is_active`. Response fields: `tool_id`, `tool_name`, `description`, `is_builtin`, `is_active` — not `input_schema`/`output_schema` in the list view.

### 30.11 `POST /api/v1/tools`

Purpose: create a tenant custom tool. Authz: `agent:write`. Request: `{ tool_name, description, input_schema, output_schema, timeout_ms?, requires_confirmation?, max_retries_on_timeout? }`. Validation: well-formed JSON Schema; `tool_name` unique across the tenant's full visible namespace (own tools ∪ platform built-ins), per §21.2a's new invariant — `409 STATE_CONFLICT`, `error.details.reason: "tool_name_conflicts_with_visible_tool"`. Audit: `TOOL_DEFINITION_CREATED` (Category A).

### 30.12 `GET /api/v1/tools/{tool_id}`

Purpose: get one tool, full schema. Authz: `agent:read`. Errors: `404`.

### 30.13 `PATCH /api/v1/tools/{tool_id}`

Purpose: update a tenant-owned tool. Authz: `agent:write`. Guard: built-ins (`organization_id IS NULL`) reject with `403`. Validation: if `tool_name` is being changed, the new name must satisfy §21.2a's visible-namespace-uniqueness invariant identically to `POST /tools` (`409 STATE_CONFLICT`, `error.details.reason: "tool_name_conflicts_with_visible_tool"`). Audit: `TOOL_DEFINITION_UPDATED` (Category A).

### 30.14 `POST /api/v1/tools/{tool_id}/deactivate`

Purpose: `is_active: true → false` (§21.2). Authz: `agent:write`. Guard: built-ins reject with `403`. Audit: `TOOL_DEFINITION_DEACTIVATED` (Category A).

### 30.15 `GET /api/v1/provider-health`

Purpose: read-only health/routing observability (§20.2). Authz: `agent:read`. Query: `category` filter. Response fields: exactly §20.2's allow-list — never `credential_ref`/`config_json`. Latency: Tier A, Redis-cache-backed.

### 30.16 `GET /api/v1/language-evaluations`

Purpose: platform reference data (§20.2). Authz: `agent:read`. Query: `language`, `capability`, `verdict` filters. RLS: none — platform-scoped (5C §11.5). Latency: Tier A. Audit: none.

### 30.17 `GET /api/internal/v1/agents/{agent_id}/versions/{version_id}`

Purpose: internal snapshot fetch for platform-admin debugging / support tooling outside the monolith's direct DB access boundary. Authentication/authorization: internal service JWT only (6A §23.4, 6B §17.2 central internal token issuer) — `actor_type=PLATFORM_ADMIN` asserted by the issuer, not a permission string. Never in the public OpenAPI surface (6A §8.5). Not subject to the public rate-limit/quota system.

---

## 31. State Machines

### 31.1 Agent Lifecycle — Unchanged, No New States Invented

```
[*] --> DRAFT              (CreateAgent / POST /agents)
DRAFT --> DRAFT             (UpdateDraftConfig / PATCH — editable at will)
DRAFT --> PUBLISHED         (PublishAgent / POST /publish — creates AgentVersion)
PUBLISHED --> PUBLISHED     (PATCH edits accumulate in draft_config; status unchanged — §5.4 finding #1)
PUBLISHED --> PUBLISHED     (PublishAgent again — "ship an update," new AgentVersion, same status)
PUBLISHED --> DEPRECATED    (DeprecateAgent / POST /deprecate)
DEPRECATED --> [*]          (soft delete after grace period — no command exists to trigger this, §19.2)
```

Terminal for the `publish` action: `DEPRECATED` (4B §7.3 — "cannot be published again"). No `PAUSED`, `ARCHIVED`, `DISABLED`, or `ACTIVE` state exists in 5C's `chk_agents_status` CHECK constraint (`DRAFT | PUBLISHED | DEPRECATED` only, verified §4), and none is invented here.

### 31.2 ToolDefinition — Not a State Machine

`is_active` is a boolean flag (`TRUE → FALSE` via `deactivate`, one-directional per 6D's original design — no `reactivate` endpoint exists in 6D's frozen text and none is invented here), not a multi-state lifecycle. `POST /tools/{id}/deactivate` is a CAS-style action endpoint (guarded by `is_active=TRUE` as the required current state) even though the underlying column is a plain boolean, matching 6A §8.3's action-endpoint criteria (side effect beyond the row: previously-published `AgentVersion` snapshots referencing this tool are unaffected, but *new* publishes referencing it will fail §15.2's check).

### 31.3 Action-Endpoint Guard Table

| Action endpoint | Allowed current state(s) | Resulting state |
|---|---|---|
| `POST /agents/{id}/publish` | `DRAFT`, `PUBLISHED` | `PUBLISHED` |
| `POST /agents/{id}/deprecate` | `PUBLISHED` | `DEPRECATED` |
| `POST /tools/{id}/deactivate` | `is_active = TRUE` | `is_active = FALSE` |

Every other current state for each action yields `409 STATE_CONFLICT` with `error.details.current_state` (agents) or a `409`-class "already inactive" response (tools), never a silent no-op and never a `500`.

---

## 32. Concurrency / Idempotency

### 32.1 Mechanism — Unchanged From 6D §30.1

No 5C `SECURITY DEFINER` guard function exists for `agents.status`. Every guarded transition uses the API-layer CAS pattern (`UPDATE ... WHERE status = ANY($allowed) RETURNING id`), identical to 6C's ADR-6C-02 and 6D's ADR-6D-03 — not a third mechanism. No API-layer `SELECT ... FOR UPDATE` is introduced anywhere (6A §17.3).

### 32.2 Named Race Analysis

| Race | Outcome |
|---|---|
| Draft `PATCH` vs. `publish` (same Agent) | READ-COMMITTED-consistent, non-corrupting — publish snapshots whatever was last committed at the moment of its own read (§16.3). No data loss: an edit not included in this publish remains in `draft_config` for the next one. |
| Two concurrent `publish` calls (same Agent) | `uq_av_version`'s uniqueness constraint is the backstop; loser raises `23505`, handled by the bounded retry (§16.4), `409 STATE_CONFLICT` on exhaustion |
| `publish` vs. `deprecate` (same Agent) | Both are CAS `UPDATE`s against `agents.status`; whichever commits first wins — `publish` requires `DRAFT`/`PUBLISHED` and `deprecate` requires `PUBLISHED`, so a `publish` that lands first leaves the Agent `PUBLISHED` (deprecate then succeeds normally); a `deprecate` that lands first leaves the Agent `DEPRECATED` (the concurrent `publish` then correctly 409s, since `DEPRECATED` is not in `publish`'s allowed-state set) |
| `deprecate` vs. new call start (cross-boundary with 6D) | Entirely non-conflicting by design — `CallRoutingService.resolve()` (6D territory) reads `agents.status`/`published_version_id` at the instant of call start; if `deprecate`'s CAS commits first, the new call simply fails `AgentMustBePublished` (6D §27.2, `AGENT_NOT_PUBLISHED`); if the call's resolution reads first, it proceeds normally against the still-`PUBLISHED` state — no lock, no coordination needed, no 6E endpoint is involved in the call's resolution path at all (§22.4) |
| `clone` while the source's draft is concurrently edited | Disclosed, non-blocking — the clone's `SELECT` sees whatever was last committed at that instant (§30.7) |
| Tool `deactivate` vs. concurrent `publish` referencing that tool | Per §15.2's corrected semantics: publish's tool re-verification reads `tool_definitions.is_active` at its own validation-read instant, within its own transaction. If `deactivate` **commits before** that read, publish correctly sees `is_active=FALSE` and 422s. If `deactivate` commits **after** publish's read but **before** publish's commit, publish proceeds and commits an immutable `AgentVersion` referencing a tool that is inactive by the time the version exists — this is a disclosed, accepted race window, not prevented by any lock (§15.2), and the resulting version is not retroactively invalid; the *next* publish attempt (any later `publish` call) will correctly 422 against the now-committed inactive state |
| Two concurrent `POST /tools` (or a create racing a rename via `PATCH`) requesting the same `tool_name`, both within one tenant's own scope | A genuine race — `uq_td_tenant_name` is the DB-level backstop, the loser raises `23505`, surfaced as `409 STATE_CONFLICT` (no bounded-retry loop is needed here, unlike `publish`'s version numbering, since there is no "next available name" to recompute — the client must choose a different name) |
| A tenant request naming an already-existing platform built-in's `tool_name` | **Not a race — corrected this pass.** 6E exposes no endpoint that creates or renames a built-in (§21.2a); a built-in's name is always already-committed, static data by the time any tenant request's own `SELECT` runs, so §21.2a's application-layer check reliably catches this every time under ordinary READ COMMITTED semantics — there is no concurrent writer to lose a race against, and no residual disclosed here |
| `Idempotency-Key` replay on `POST /agents` | Not required, but if supplied: same key + same payload replays the cached response; same key + different payload → `409 IDEMPOTENCY_KEY_REUSE_MISMATCH` (6A §16.2) |
| `If-Match` mismatch on `PATCH` or `publish` | `412 PRECONDITION_FAILED` (6A §17.2, and §16.6's new optional publish precondition) |

### 32.3 Idempotency Summary (6A §16, applied)

Recommended, not required: `POST /agents/{id}/publish`. Not required: every `GET`; `POST /agents`, `POST /agents/{id}/clone`, `POST /tools` (creating an extra row has no dangerous real-world consequence, unlike a Call — 6A §16.1's bar is not met); every CAS-guarded action endpoint (`deprecate`, `deactivate`) whose own 409-on-retry behavior is sufficient.

---

## 33. Rate Limits

| Layer | Applies to | Mechanism |
|---|---|---|
| L1 — NGINX ingress | Every 6E REST endpoint | Per-source-IP (60/min) — 6A §20/3F §8.4, reused unmodified |
| L2 — App, standard CRUD | Agent/Tool reads and writes, reference-data reads | Default 300 req/min/org (6A §20's default) |
| L2 — App, lifecycle action | `POST /agents/{id}/publish` | 30/hour/org (configurable default — publishing is infrequent by nature, unchanged from 6D §28.5) |
| L2 — App, lifecycle action | `POST /agents/{id}/deprecate`, `POST /agents/{id}/clone`, `POST/PATCH/deactivate /tools*` | Standard 300 req/min/org tier — no special lower ceiling warranted (these are ordinary, non-cost-sensitive control-plane mutations) |

**Three distinct concepts, not conflated (per the governing task's explicit instruction):**

1. **Request-rate limiting** (the table above) — abuse prevention, applies today, unconditionally, to every 6E endpoint.
2. **Commercial/billing quota** (metered usage cost — LLM tokens, TTS characters, call-minutes) — does not apply to any 6E endpoint today, because Agent/Tool management invokes no paid provider (no preview/test capability is designed, §38 `DEP-6E-09`) and is not itself a metered resource.
3. **A future Agent-*count* plan quota** (FR-TEN-005 — "how many Agents may this org have") — genuinely distinct from both of the above, **not designed by this document**, and **not permanently ruled out** by statement 2. `POST /agents` (§30.1) is the endpoint any such quota would eventually gate; §38 `DEP-6E-20` tracks this explicitly as a non-blocking, deferred-to-6K item rather than allowing FR-TEN-005 to be silently read as satisfied or waived by this document.

No 6E endpoint enforces concept 2 or concept 3 today — only concept 1.

---

## 34. Observability

### 34.1 Metrics — Bounded Cardinality Only (6A §25, 6D §32's cardinality rule, applied identically)

| Metric | Labels (bounded only) |
|---|---|
| `agents_created_total` | none |
| `agents_cloned_total` | none |
| `agent_published_total` | none |
| `agent_deprecated_total` | none |
| `agent_publish_validation_failures_total` | `reason_category` (bounded set: `tool_reference`, `language_policy`, `provider_reference`, `provider_capability`, `structural`) |
| `agent_publish_23505_retries_total` | none |
| `agent_publish_warnings_total` | `warning_category` (bounded set: `degraded_provider`, `conditional_language_verdict`, `no_fallback_provider`) |
| `tool_definitions_created_total` | none |
| `tool_definitions_deactivated_total` | none |

### 34.2 Never a Metric Label — Trace/Log Correlation Only

`organization_id`, `agent_id`, `agent_version_id`, `tool_id`, `tool_name`, `prompt_ref`, `workflow_ref`, `knowledge_base_id`, `provider_id` (unbounded per-tenant provider aliasing is not a concern here, but the identifier itself is still treated as a correlation attribute, not a label, for consistency with 6D §32.3's rule) — every one of these is an OpenTelemetry span attribute or structured-log field, never a Prometheus label (6A §25's existing convention, 6D §32.3, reused verbatim). No metric in this document includes a raw Agent name, tool name, or opaque-reference value.

### 34.3 Tracing / Dashboards

Every REST request is an OpenTelemetry span, reusing 6A §25's existing sampling policy — no new tracing infrastructure. Extends the already-provisioned "Voice Pipeline" Grafana dashboard (3E §14.3, 6A §26, 6D §32.5) with an "Agent Management" panel group — no new dashboard tool introduced.

---

## 35. Threat Model

| Threat | Mitigation |
|---|---|
| Cross-tenant Agent/Tool/Version access (IDOR) | RLS (5C §11.1) primary guarantee; application-layer ownership check defense-in-depth; `404` never `403` on cross-tenant reference (§27) |
| Mass assignment (`status`, `published_version_id`, `organization_id`, `deleted_at`, `created_at`, `updated_at`) | Structurally absent from every request schema (§9.2) — a client can never write these fields regardless of intent |
| Tenant referencing another tenant's custom tool in `tool_permissions` | Validated at every draft-config write and re-validated at publish (§13, §15.2) — `tool_id` must resolve to a tenant-visible row |
| Secret smuggled into an immutable `AgentVersion` snapshot via a closed-shape field (`voice_config`, `model_config`, `language_policy`, opaque references, `tool_permissions`, `calling_hours`) | Structurally prevented — none of these fields is shaped to hold a secret (§28.3); `credential_ref` never appears in any Agent-management request/response model |
| Secret smuggled into an immutable `AgentVersion` snapshot via `qualification_criteria` (the one open-ended field) | **Not prevented on the input side — corrected this pass.** A prior pass's input-rejection rule cited an unsupported source (§9.4's retraction) and is removed. The only mitigation that remains is output-side: `qualification_criteria` is never written to logs, traces, or an audit `resource_snapshot` (§9.4, §25.0). Disclosed as `DEP-6E-16` (§38), explicitly not claimed as closed or mitigated on the input side |
| Confused-deputy: internal token presented at a public route (or vice versa) | 6B §17.3's routing rule, reused unmodified, applies identically to §30.17's internal endpoint |
| Publish used to smuggle unvalidated config | Structurally prevented — the publish request body is empty; the server always snapshots the already-validated, already-committed `draft_config` (§30.5) |
| Quota-exhaustion abuse via rapid Agent/Tool creation | Standard L1/L2 rate limiting (§33) — no commercial quota needed since these are not metered resources |
| Dangling opaque reference (`prompt_ref`/`workflow_ref`/`knowledge_base_refs`) exploited to reference another tenant's resource in a future context | Out of 6E's authority to prevent structurally (§14.3) — disclosed as `DEP-6E-02/03/04`; whichever future document owns existence/ownership validation for these references is responsible for its own tenant-isolation check at the point it resolves them |
| A tenant's custom tool sharing a `tool_name` with a platform built-in (namespace ambiguity for `tool_name`-based runtime resolution) | **Corrected this pass — the prior claim that 5C's mixed-scope unique indexes alone prevent this was false and is retracted.** `uq_td_platform_name` (`organization_id IS NULL`) and `uq_td_tenant_name` (`organization_id, tool_name`, `WHERE organization_id IS NOT NULL`) protect two *independent* namespaces — neither prevents a tenant's own `createLead` from coexisting with a platform built-in `createLead`. The actual mitigation is §21.2a's new application-layer visible-namespace-uniqueness check on `POST /tools`/`PATCH /tools/{id}` — DB-backed (`uq_td_tenant_name`) for the tenant-vs-own-tenant case; for the tenant-vs-platform-built-in case, 6E exposes no built-in-mutation endpoint at all, so a built-in's name is always static, already-committed data by the time the application-layer check runs — reliable-by-construction, not merely a best-effort defense-in-depth layer (§21.2a) |
| Cross-tenant `tool_name` collision (Tenant A's custom tool name colliding with Tenant B's) | Prevented by `uq_td_tenant_name`'s own tenant-scoped uniqueness (`(organization_id, tool_name)`) — this claim, unlike the one above, is accurate: two different tenants' own namespaces are fully independent and a collision between them has no operational consequence (5C §11.3's RLS ensures each tenant only ever sees its own custom tools plus built-ins, never another tenant's) |

---

## 36. Test Strategy

### 36.1 Contract

Every REST endpoint (§30, 17 total) gets a contract test verifying request/response schema, status codes, and the standard 6A envelope shape.

### 36.2 Authorization

All role × permission combinations from §27's matrix (`OWNER`, `ADMIN`, `MEMBER`, `VIEWER`); API-key scope intersection (6B §16.4) for every API-key-eligible endpoint; cross-tenant denial (`404`, never `403`) for every resource-scoped endpoint; internal-service-JWT-only access for §30.17, verified to reject a user/API-key credential and vice versa (6B §17.3's confused-deputy test).

### 36.3 Agent State

`DRAFT`, `PUBLISHED`, `DEPRECATED` — every legal transition (§31.3) and every illegal transition (409 from every other state), a full state × action matrix, not spot checks.

### 36.4 Validation

Every §15.4 row: invalid `VoiceConfig` (out-of-range `speaking_rate`, invalid enum), invalid `ModelConfig` (unresolvable provider per §11.4's configuration-identity query, duplicate `fallback_providers` entry), invalid `LanguagePolicy` (all five §12.2 rules, positive and negative), inactive/cross-tenant tool reference, duplicate `tool_permissions` entry, provider/language capability `REJECTED` with and without a viable fallback (both branches of rule #14, including the "preferred rejected, fallback approved" and "preferred approved, fallback rejected" cases named in §15.6), `CONDITIONAL` verdict producing a `warnings[]` entry without blocking publish, and a `tool_name` visible-namespace collision on both `POST /tools` and a `PATCH /tools/{id}` rename (§21.2a — own-tenant collision asserted as a genuine `23505`-backed race; built-in collision asserted as reliably caught, not as a race, per §21.2a's corrected concurrency scope). Opaque Prompt/Workflow/Knowledge reference behavior: format-valid UUID accepted and round-tripped; malformed UUID rejected; no existence check attempted (verified by asserting no outbound call is made).

**`qualification_criteria` — corrected this pass:** verify `PATCH`/`publish` accept **any** well-formed JSON object for this field, including keys such as `credential_status`/`token_budget_category` that a prior pass's retracted rule would have wrongly rejected (§9.4) — there is no key-name validation rule to test for rejection; instead, verify the field's contents never appear in a request log, a trace span, or an audit `resource_snapshot` (output-side non-exposure, the only mitigation that remains).

**Provider configuration-identity vs. runtime routability — the full test matrix (§11.4, `DEP-6E-22`):** `is_active=TRUE, circuit_state=CLOSED` → exists, no `WARNING`; `is_active=TRUE, circuit_state=OPEN` → **exists** (rule #5 passes), rule #15 fires `WARNING`; `is_active=TRUE, circuit_state=HALF_OPEN` → exists, **no** `WARNING` (§15.4 rule #15's explicit carve-out); `is_active=FALSE` (any `circuit_state`) → does not exist, `ERROR` regardless of `circuit_state`; a `provider_id` matching only a platform-default row succeeds; matching only a tenant-scoped row succeeds; matching both scopes resolves deterministically to the tenant-scoped row per `NULLS LAST`; two tenant rows sharing a `provider_id` at different `priority` values resolve deterministically via `priority ASC` (no ties possible within one tenant's own scope, §11.4/ADR-6E-18) — assert via the resolved row's `id`, not merely "publish succeeded." **Single-row/shared-row assertion, corrected this pass:** verify §11.4 query (A) returns at most one row (`LIMIT 1`) even when multiple candidate rows exist; verify rules #5, #12, and #15 all read `supports_languages`/`health_state`/`circuit_state` off that *same* returned row (assert exactly one query execution per `provider_id` per publish attempt, not three) — this is the test that would have caught the pre-fix inconsistency (query (A) previously omitting `supports_languages` and `LIMIT 1`).

**`LanguageEvaluationRecord` selection — the full test matrix (§15.6, `DEP-6E-23`):** latest record `APPROVED` → no `WARNING`/`ERROR`; latest `CONDITIONAL` → `WARNING`; latest `REJECTED` with no viable fallback → `ERROR`; latest `REJECTED` with an `APPROVED`/`CONDITIONAL` fallback → publish succeeds (rule #14 does not fire); an **older** `APPROVED` superseded by a **newer** `REJECTED` → the newer `REJECTED` wins (rule #14 evaluates, per §15.6 point 8); an **older** `REJECTED` superseded by a **newer** `APPROVED` → the newer `APPROVED` wins, no block; missing record entirely → neither `WARNING` nor `ERROR` fires; preferred provider `REJECTED` + fallback `APPROVED` → publish succeeds; preferred `APPROVED` + fallback `REJECTED` → publish succeeds, no rule fires for the unreached fallback. **Every one of these cases requires the test's underlying query to be capable of returning `REJECTED` rows** — verified by asserting the test fixture's query is §15.6 query (B), never query (A)'s `verdict IN ('APPROVED','CONDITIONAL')`-filtered shape. A `provider_model_ref` mismatch between the winning evaluation row and the currently-configured `provider_configs.model_id` does not itself block publish (disclosed residual, `DEP-6E-12`).

**LLM-only scoping (§15.5, `DEP-6E-21`):** verify rules #12–#14 run for the tenant-identified LLM provider(s) only; verify no test, fixture, or implementation path attempts to resolve or validate a "selected STT provider" or "selected TTS provider" from Agent config — confirmed by asserting no code path constructs an `stt_provider_id`/`tts_provider_id` value anywhere in the validation pipeline.

### 36.5 Versioning

First publish (`version_number=1`); republish (`version_number` increments, prior version's `snapshot_json` byte-for-byte unchanged); correct `published_version_id` after each publish; clone from `draft` and from a `published_version_id`, verifying `published_version_id: null` and empty version history on the new Agent in both cases; version-history read (list + detail); concurrent publish producing the `23505`-bounded-retry path, verified up to and including exhaustion (`409 STATE_CONFLICT`).

### 36.6 Concurrency

Every race in §32.2's table gets a dedicated concurrent-request test: draft-edit-vs-publish (asserting the snapshot always matches *some* committed draft state, never a corrupted/partial one), publish-vs-publish, publish-vs-deprecate, tool-deactivate-vs-publish **both orderings, explicitly asserting the corrected §15.2 semantics** — deactivate-before-validation-read → publish 422s; deactivate-after-validation-read-but-before-publish-commit → publish succeeds and the resulting version references the now-inactive tool (asserted as expected, not as a bug) → a subsequent publish attempt then 422s, clone-vs-concurrent-source-edit, tool-name-collision-on-create-vs-create **within one tenant's own scope** (a genuine race, asserting `23505`→`409`), a tenant request naming an already-existing built-in (asserted as a reliable, always-caught rejection — **not** modeled as a race, since 6E has no built-in-mutation endpoint for anything to race against, §21.2a), `Idempotency-Key` replay (same and different payload), `If-Match` mismatch on both `PATCH` and `publish`.

### 36.7 Security

Cross-tenant IDOR on every path-parameterized endpoint; forbidden mass-assignment (attempt to set `status`/`published_version_id`/`organization_id`/`deleted_at`/`created_at`/`updated_at` via `POST`/`PATCH`, asserting `422` or silent-field-rejection per schema, never silent acceptance); secret/credential non-exposure (assert no response body anywhere in this document's surface ever contains `credential_ref` or a raw secret); AgentVersion snapshot secret-leakage (attempt to inject a secret-shaped value into every closed-shape `draft_config` field, verify none survives into `snapshot_json` — trivially true given §28.3's structural argument for those fields, but tested to catch a future schema-allow-list regression); `qualification_criteria` output-side non-exposure (place a secret-shaped value in this field — under both a conventionally-named and an innocuously-named key, since no input rule distinguishes them any more, §9.4 — publish successfully, then assert the value never appears in any request/access log, any trace span attribute, or the audit `resource_snapshot`; **do not** assert that publish rejects it, since no such rejection rule exists after this pass's retraction); API-key restrictions (`publish`/`deprecate` reject an API-key credential with `403`, never silently succeeding).

### 36.8 Audit

Each mutation uses its exact `action_kind` (§25.3); `audit.fn_insert_audit_event()` is the only code path exercised (a direct `INSERT INTO audit.audit_events` attempt is verified to fail at the DB-privilege layer, matching 6D's own `DEP-6D-13` verification); audit failure (a raised exception from the function) rolls back the accompanying domain mutation — verified for at least `publish` and `deprecate`.

### 36.9 Events

Outbox row inserted in the same transaction as the domain mutation, for every §26.2 row; at-least-once/idempotency expectations documented and tested via forced redelivery; Redis unavailable after a DB commit does not erase the already-durable audit record (verified by asserting `audit.audit_events` contains the row even when the outbox→Redis publish path is simulated as failed).

### 36.10 Voice Integration (cross-boundary with 6D)

A published `AgentVersion` can be resolved by 6D's frozen `CallRoutingService.resolve()` — verified as an integration test spanning both documents' contracts, not a 6E-only unit test. Draft edits made after a Call has already pinned an `agent_version_id` do not affect that Call (§22.4). A new `publish` (version N+1) does not affect an in-progress Call pinned to version N. A `deprecate` does not affect an in-progress Call. **No test in this suite, or in any 6E implementation, ever issues an HTTP request from inside a simulated Voice-turn loop to any 6E endpoint** — this absence is itself the assertion (§22.2's "no per-turn call to any 6E-designed endpoint" is verified negatively, by confirming no such call site exists in the runtime code path, not merely by omission of a positive test).

---

## 37. Traceability

| Requirement | Source | 4B | 5C | 6A | 6B | 6D | 6E coverage |
|---|---|---|---|---|---|---|---|
| `FR-LLM-001` (choose LLM provider per agent) | SRS | §5.3.2 ModelConfig | `provider_configs` | §11 Tier A/B | — | §15 (reference-data origin) | §11, §20 |
| `FR-LLM-002` (Model Router, per-agent override) | SRS | §8.2 ProviderSelectionService | `provider_configs` | §11 | — | §15.4 (hot-path discipline) | §11.3, §22 |
| `FR-TTS-002` (voice cloning per org/agent, where provider allows) | SRS | §5.3.1 VoiceConfig | `agents.draft_config.voice_config` | — | — | §8.2 | §10 |
| `FR-TEN-005` (per-tenant configurable agent quota, including *number of agents*) | SRS | — | — | §20 (rate limiting) | — | §31.2 (CheckQuota port, Call-side) | **Not fully closed by this document — see `DEP-6E-20` (§38).** 6E owns `POST /agents` (§30.1), the endpoint any future Agent-count quota must gate; 6E does not itself enforce that quota, invent its value, or invent a billing/plan model — that belongs to 6K (Billing/Usage APIs) per the roadmap. §33's "no commercial-quota limiter applies to any 6E endpoint" statement describes *today's* state, not a permanent exemption — it is explicitly qualified in §33 to distinguish request-rate limiting (6E, today) from commercial/billing quota (6K, future) from a specific future Agent-count plan quota (6K, future, tracked by `DEP-6E-20`) |
| `NFR-USAB-001` (non-technical Agent Builder, no code) | SRS | §5.3 Agent Aggregate | `agents`, `agent_versions` | §7 REST standards | — | — | §8–§19 (the full typed, strongly-validated configuration contract) |
| `NFR-PERF-001` (<800ms p50, indirect) | SRS | — | — | §11 | — | §21 (≤750ms target) | §22 (explicit non-interference boundary) |
| Agent Aggregate | 4B §5.3 | — | `agents`, `agent_versions` | §7–8 | — | §8–9 | §8–§19 |
| ToolDefinition Aggregate | 4B §5.4 | — | `tool_definitions` | §8.3 | — | §18.1 | §21 |
| DDR-4B-003 (AgentVersion immutable, pinned at call start) | 4B | — | §11.6 trigger | §35 | — | §9.1 | §16.1, §22.4 |
| DDR-4B-004 (ToolExecution separate from ToolDefinition) | 4B | — | — | — | — | §18 | §21.1 (ownership-split rationale) |
| 4I §4.2 LanguagePolicy / CONTRADICTION-02 | 4I | — | §5.4/§5.5 | — | — | §8.2 | §12 |
| 4I §4.4 Tamil-First Language Evaluation Framework | 4I | — | `language_evaluation_records` | — | — | §15 (ref-data origin) | §15.5–§15.6, §20 |
| 4I §8.1 invariant 2 (`ConsentRecord` "most recent by timestamp" precedent) | 4I | — | — | — | — | — | §15.6 (selection-algorithm grounding) |
| 5C §15.11/§15.12 (Provider/Language lookup query patterns) | 5C | §8.2 ProviderSelectionService | `provider_configs`, `language_evaluation_records` | — | — | §15.2/§15.4 | §11.4, §15.6 |

---

## 38. Dependencies

Every row's **Status** is exactly one of `RESOLVED`, `NON-BLOCKING`, `BLOCKING`, or `DEFERRED TO [PHASE]` — no unresolved ambiguity is labeled non-blocking merely to make §41's closure table pass; where a residual genuinely remains, the Status cell says `NON-BLOCKING` only with an explicit reason why it does not gate this document's freeze.

| ID | Description | Source | Affected endpoint | Status | Detail | Blocks final approval? |
|---|---|---|---|---|---|---|
| **DEP-6E-01** | 6D/6E Agent ownership overlap | Governing task; 6D's necessarily-broad original scope | All Agent endpoints | **RESOLVED** | This entire document is the resolution (§5) | No |
| **DEP-6E-02** | Opaque `prompt_ref` existence validation ownership | No approved in-process existence-check port exists for Prompt Management (4B §16 defines only a runtime-consumption `PromptRenderPort`) | §14 | **NON-BLOCKING** | Format-validated only, existence unverified by design; ownership belongs to whichever future document owns Prompt Management | No |
| **DEP-6E-03** | Opaque `workflow_ref` existence validation ownership | Same reasoning, `WorkflowExecutionPort` is runtime-consumption-only | §14 | **NON-BLOCKING** | Same as above; ownership belongs to 6I (Workflow APIs) | No |
| **DEP-6E-04** | Opaque `knowledge_base_refs` existence validation ownership | Same reasoning, `KnowledgeSearchPort` is runtime-consumption-only | §14 | **NON-BLOCKING** | Same as above; ownership belongs to 6F (Knowledge/RAG APIs) | No |
| **DEP-6E-05** | Tool Definition management ownership required a decision between 6D-retained and 6E-adopted | Governing task, Option A vs. B | §21 | **RESOLVED** | Option A adopted (§21.1); endpoints/permissions/audit unchanged, one new validation rule added (§21.2a) | No |
| **DEP-6E-06** | Whether 6E's mutations need a new 5J `action_kind` | 5J §14.3 | §25 | **RESOLVED** | No gap exists — all four Agent + three Tool Definition `action_kind`s already governed by 6D's `‡` amendment (§25.1) | No |
| **DEP-6E-07** | Whether 5J §14.5's synchronous-audit exception needs rewording now that 6E owns the endpoints | 5J §14.5 | §25 | **RESOLVED** | No amendment needed — the clarification is action-kind-scoped, not endpoint-owning-document-scoped (§25.2) | No |
| **DEP-6E-08** | Interim permission reuse for Tool Definition CRUD (`agent:read`/`agent:write`, no dedicated `tool:*` permission) | 5B §17.2 permission catalog; inherited from 6D's `DEP-6D-02`, now under 6E's authority since Tool ownership moved | §21.2, §30.10–30.14 | **NON-BLOCKING** | Re-verified against 5B's grant table (§27.1) — no over-grant found | No |
| **DEP-6E-09** | Agent preview/test/validate-as-a-standalone-action capability is product-plausible but has no domain command | 4B §12.3's command catalogue (`CreateAgent`, `UpdateDraftConfig`, `PublishAgent`, `DeprecateAgent`, `CloneAgent` — no `ValidateAgent`/`TestAgent`/`PreviewAgent`) | N/A — no endpoint proposed | **NON-BLOCKING** | Explicitly not designed, per the governing task's explicit instruction not to invent an endpoint merely because it is a common industry pattern; would require new DDD-level command work first | No |
| **DEP-6E-10** | Tenant-facing `ProviderConfig` CRUD (choosing/prioritizing a non-default provider, linking `credential_ref`) is not designed | Inherited from 6D's `DEP-6D-06` — no `provider:*` permission, no product requirement beyond per-agent `ModelConfig` fields | N/A | **DEFERRED TO A FUTURE PHASE** | No product requirement surfaced in Phase 1–6E; unchanged from 6D | No |
| **DEP-6E-11** | Provider/model "compatibility" beyond declared `supports_languages` and advisory `verdict` scores is not exhaustively modeled | 5C §5.11/§5.12 — only two sources of capability truth exist | §15.5 | **NON-BLOCKING** | §15.5's two-source model is deliberately conservative — a hard capability check only where a declared flag exists (rule #12), advisory-only where the data itself is advisory (rules #13/14) | No |
| **DEP-6E-12** | `LanguageEvaluationRecord` selection has two disclosed residuals: (a) a missing record for a given tuple is treated as "no data," neither WARNING nor ERROR; (b) the winning record's `provider_model_ref` may not match the currently-configured `provider_configs.model_id`, since `ModelConfig` carries no client-supplied `model_id` to match against (§11.1) | 4I §4.4's evaluation framework (ongoing by nature); §15.6's selection algorithm | §15.4 rules #13/14, §15.6 | **NON-BLOCKING** | Both residuals are conservative-by-construction (they never cause a false ERROR, only a possible false absence of a WARNING) and are fully disclosed in §15.6 rather than silently assumed away; resolving (b) fully would require `ModelConfig` to carry a client-supplied `model_id`, a scope change this document does not make | No |
| **DEP-6E-13** | Publish/edit concurrency mechanism | 6D's `23505` bounded-retry design | §16.4, §32 | **RESOLVED** | Reused unchanged from 6D, no new mechanism | No |
| **DEP-6E-14** | Agent archival/hard-delete (`voice.agents.deleted_at`) has no corresponding domain command | Inherited from 6D's `DEP-6D-12`; 5C §5.4 column exists, 4B §12.3's command catalogue has no `ArchiveAgent`/`DeleteAgent` | §19.2 | **NON-BLOCKING** | Disclosed scope boundary — `deprecate` is the only lifecycle-terminal action exposed; would require new DDD-level command work | No |
| **DEP-6E-15** | API-key restriction on `publish`/`deprecate` | 6B §16.4 scope model; 5B §17.2 role grants | §27.2 | **RESOLVED** | Reused unchanged from 6D | No |
| **DEP-6E-16** | `qualification_criteria` is the one `draft_config` field with no closed schema anywhere in Phase 1–5; **corrected this pass — the field has no input-side validation at all** (a prior pass's key-substring rejection rule cited an unsupported source and is retracted, §9.4). The only remaining mitigation is output-side: raw contents are never logged, traced, or placed in an audit `resource_snapshot` | 4B §5.3/§12.3, 4C §1, 4D §4 — no `QualificationCriteria` value object is ever schema-defined; §9.4/§28.3's own honest re-statement, corrected this pass | §9.4, §28.3 | **NON-BLOCKING — MITIGATED ON THE OUTPUT SIDE ONLY, NOT INPUT-VALIDATED, NOT FULLY RESOLVED** | No input-side control exists for this field, honestly disclosed rather than covered by an unsupported rule. Full structural closure requires a frozen `QualificationCriteria` schema this document has no DDD authority to invent. Does not block 6E approval because every *other* `draft_config` field is genuinely closed and this residual is honestly disclosed, not asserted away. Flagged for full resolution once a future document defines a closed `QualificationCriteria` schema. | No |
| **DEP-6E-17** | Runtime cache/prewarm implementation for `agent_version:{version_id}:snapshot` is 6D's/3B's implementation detail | 6D §22, unchanged | §23.1 | **RESOLVED** | Consumed unchanged — no new dependency introduced by 6E | No |
| **DEP-6E-18** | Tenant-custom `tool_name` could collide with a platform built-in's name — a prior version of this document incorrectly claimed Phase 5 indexes alone prevent this | 5C §16.5's mixed-scope unique indexes protect two independent namespaces, not one merged one (§21.2a) | §30.11, §30.13 | **RESOLVED** | §21.2a's new application-layer visible-namespace-uniqueness invariant closes the gap for 6E's actual tenant ToolDefinition mutation surface: DB-constraint-backed (`uq_td_tenant_name`) for the tenant-vs-own-tenant case; reliable-by-construction (not merely "disclosed as a race") for the tenant-vs-platform-built-in case, since 6E exposes no built-in-mutation endpoint and a built-in's name is therefore always static, already-committed data. **Corrected this pass:** the prior wording implied a genuine concurrency race against built-in creation; that race does not exist on 6E's actual API surface and is no longer described as one. Any future platform-admin/built-in-provisioning API must independently enforce this same invariant before it would introduce a real race | No |
| **DEP-6E-19** | Deterministic `ProviderConfig` resolution when a `provider_id` could match more than one tenant-visible row | 5C §5.11's `uq_pc_priority`/`uq_pc_platform_cat` constraints do not prevent a tenant-scope and platform-default row from sharing a `provider_id` | §11.1, §15.4 rule #5 | **RESOLVED** | §11.4 grounds the resolution in 5C §15.11's own already-frozen `ORDER BY` pattern, narrowed this pass to the scope it actually guarantees (tenant-scope ordering is fully deterministic via `uq_pc_priority`; platform-scope ordering does not rely on priority uniqueness at all, since `uq_pc_platform_cat` already caps at most one row per `provider_id` there) — no rule is fabricated, and the prior pass's unqualified "strict total order" claim is corrected | No |
| **DEP-6E-20** | FR-TEN-005's per-tenant Agent-*count* quota is not enforced by any 6E endpoint | SRS FR-TEN-005; §33/§37 (this pass's correction) | `POST /agents` (§30.1) | **DEFERRED TO 6K (Billing/Usage APIs)** | 6E owns the endpoint the quota would eventually gate; 6E does not invent the quota's value, billing/plan model, or enforcement error code. This is an explicit handoff, not a silent waiver of FR-TEN-005 — Final API Reconciliation (the cross-Phase-6 closure step named in the authoritative sequence) must attach 6K's quota enforcement/error behavior to `POST /agents` once 6K is designed | No |
| **DEP-6E-21** | Publish-time provider-specific capability/evaluation validation (§15.4 rules #12–#14) must be scoped to only the categories Agent config actually identifies a `provider_id` for | 4B §5.3.1 (`VoiceConfig.voice_id` is explicitly "provider-agnostic"); 4B §5.3.2/3B §11 (`ModelConfig`/`ModelRouter` are the LLM-selection surface); no `stt_provider_id`/`tts_provider_id` field or deterministic `voice_id`→provider mapping exists anywhere in 3B/4B/5C | §10.2, §11.1, §15.4–§15.6, §20 | **RESOLVED** | This pass's scoping correction restricts provider-specific validation to the LLM category (§15.5); `GET /language-evaluations`'s broader `STT`/`TTS`/`LLM` reference-data exposure is unaffected, since it serves human browsing, not automated per-provider validation | No |
| **DEP-6E-22** | Provider configuration-identity/existence validation (6E) must not be conflated with provider runtime-routability validation (6D) — a prior pass's §11.4 reused 6D's `circuit_state = 'CLOSED'`-filtered query for 6E's existence check, contradicting §15.4 rule #15's `OPEN`-circuit `WARNING` | 5C §15.11 (6D's frozen runtime pre-selection query) vs. the configuration-identity question 6E actually needs answered | §11.1, §11.4, §15.3, §15.4 rules #5/#15 | **RESOLVED** | §11.4 now defines two explicit, separate queries: 6E's existence query (A, no `circuit_state` filter, `LIMIT 1`) and 6D's unmodified runtime query (B, `circuit_state = 'CLOSED'`, cited not re-run) — an `is_active = TRUE`/`circuit_state = OPEN` provider now correctly exists (passes rule #5) while also triggering rule #15's `WARNING` | No |
| **DEP-6E-23** | The `LanguageEvaluationRecord` publish-validation lookup must be able to observe a `REJECTED` verdict and must filter by the resolved `provider_id` — a prior pass reused 5C §15.12's `verdict IN ('APPROVED','CONDITIONAL')`-filtered, `provider_id`-agnostic reference-list query for this purpose, making `REJECTED` structurally undetectable | 5C §15.12's reference-list query vs. the per-provider validation question §15.4 rules #13/#14 actually need answered | §15.4 rules #13/#14, §15.6, §20 | **RESOLVED** | §15.6 now defines a separate, 6E-owned application query (B) — filtered by `provider_id`, unfiltered by `verdict`, `ORDER BY evaluated_at DESC LIMIT 1` — over the same already-frozen `idx_ler_lookup` index; no schema/index/migration change. 5C §15.12's original reference-list query (A) is unchanged and continues to back `GET /language-evaluations` only | No |
| **DEP-6E-24** | §11.4 query (A) previously omitted `supports_languages` (needed by rule #12) and `LIMIT 1` (leaving "the resolved row" rules #12/#15 refer to ambiguous relative to what rule #5's existence check actually returned) | Direct re-review of §11.4 against §15.4 rules #5/#12/#15's actual data needs | §11.1, §11.4, §15.4 rules #5/#12/#15, §15.5 | **RESOLVED** | Query (A) now selects `supports_languages` alongside `model_id`/`health_state`/`circuit_state`, and adds `LIMIT 1`; §11.4 states explicitly that this single returned row is the one effective `ProviderConfig` every one of rules #5/#12/#15 reads for a given `provider_id`, with no second query — no schema/index change, since `supports_languages` was already a column and `LIMIT 1` changes no `WHERE`/`ORDER BY` semantics | No |

**Reading the table:** every `NON-BLOCKING` or `DEFERRED` item (`DEP-6E-02/03/04/08/09/10/11/12/14/16/20`) is either a disclosed scope boundary requiring a future bounded-context's own design work, a Product/DDD decision this document has no authority to make unilaterally, or (in `DEP-6E-16`'s case) a residual explicitly mitigated on the output side only, not input-validated, and not fully structurally closed. Every genuinely resolvable ambiguity investigated across both correction passes (`DEP-6E-18` tool-name collision, `DEP-6E-19` provider resolution, `DEP-6E-21` LLM-only scoping, `DEP-6E-22` existence-vs-routability separation, `DEP-6E-23` language-evaluation query fix, `DEP-6E-24` query (A) field/cardinality completeness) **was** resolved by grounding the answer in already-frozen 5C query patterns or by narrowing scope to what Agent config actually identifies, never left open. **No dependency in this register — resolved or non-blocking — blocks architecture approval, implementation, or final approval** (§41); `DEP-6E-16` and `DEP-6E-20` are the two items future work should specifically revisit, and both are named exactly for that purpose.

---

## 39. Architecture Decision Records

| ID | Decision | Alternatives considered | Rationale | Status |
|---|---|---|---|---|
| ADR-6E-01 | 6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption of the resulting published AgentVersion | Leave Agent management inside 6D permanently (rejected — contradicts the authoritative Phase 6 sequence naming 6E explicitly); fork a contradictory second Agent contract (rejected — explicitly forbidden by the governing task) | 6D's original scope was a necessary starting point, not a permanent home; splitting along the Agent-management/Call-runtime seam matches how 4B itself separates the Agent and Call aggregates | Decided |
| ADR-6E-02 | Tool Definition management (CRUD) moves to 6E; Tool Execution (runtime observation) remains 6D's | Keep both under 6D (Option B, rejected — Tool Definitions are Agent-configuration-adjacent, not Call-runtime-adjacent); move both to 6E (rejected — ToolExecution's lifecycle is entirely Turn/Conversation-driven, DDR-4B-004) | Splits authoritative-document ownership along the exact aggregate boundary 4B already drew (DDR-4B-004) | Decided |
| ADR-6E-03 | Provider-health and Language-Evaluation reference-data reads move to 6E; provider routing/failover runtime behavior remains 6D's | Move all of `provider_configs`/`language_evaluation_records` including runtime routing logic (rejected — runtime routing is Voice-hot-path behavior, not Agent-configuration reference data); leave both fully in 6D (rejected — contradicts the governing task's explicit framing) | The read-only reference-data *view* and the runtime *decision logic* over the same table are separable concerns, exactly as already true for VoiceConfig/ModelConfig themselves | Decided |
| ADR-6E-04 | `AgentVersion.snapshot_json` remains immutable, write-once, DB-trigger-enforced; no endpoint in this document ever mutates it | Allow a narrow, audited "correction" PATCH on a published version (rejected — directly contradicts DDR-4B-003 and 5C §11.6's trigger, and would break the pinning guarantee for any in-progress Call) | DDR-4B-003 is a foundational, frozen invariant this document has no authority to weaken | Decided |
| ADR-6E-05 | Publish-time validation is classified ERROR (blocks publish) vs. WARNING (publish succeeds, disclosed risk) | Treat every validation concern as a hard error (rejected — the governing task explicitly requires this distinction, and treating dynamic provider-health as a hard error would wrongly couple Agent-management to a condition 6D's own runtime failover already handles); treat every concern as advisory-only (rejected — a dangling tool reference or invalid LanguagePolicy must block, per 4B's own invariants) | Matches the actual nature of each underlying condition — structural/domain-invariant violations are errors; time-varying or advisory-quality signals are warnings | Decided |
| ADR-6E-06 | No 6E endpoint is ever reachable from the Voice-turn hot path; `CallRoutingService.resolve()` remains exclusively in-process | Expose an internal HTTP endpoint for runtime AgentVersion resolution "for consistency" with other internal endpoints (rejected — would introduce a network hop into the ≤750ms budget for no benefit, and directly contradicts 6D's frozen architecture) | Restates 6D's own binding architectural commitment; 6E must not introduce what 6D deliberately avoided | Decided |
| ADR-6E-07 | `ModelConfig` exposes only platform-recognized provider/model identifiers, never a provider-native SDK parameter object or raw credential | Allow a pass-through `provider_native_config` JSON blob for power users (rejected — reintroduces the exact vendor-lock-in and secret-exposure risk 4B/5C's `credential_ref`-as-opaque-reference design exists to prevent) | Provider-independence is a standing platform architecture principle (`product/ARCHITECTURE_PRINCIPLES.md`), not a 6E-local choice | Decided |
| ADR-6E-08 | `prompt_ref`/`workflow_ref`/`knowledge_base_refs` are format-validated only; no synchronous cross-context existence check is invented | Add a synchronous internal HTTP/in-process call to whichever future context owns these resources (rejected — no such port is designed anywhere in Phase 1–5 today, and inventing one here would exceed an API-design document's authority — it would require a new DDD port) | Respects the modular-monolith boundary (3A) and the governing task's explicit prohibition on inventing cross-context synchronous calls | Decided |
| ADR-6E-09 | `POST /agents/{id}/publish` and `POST /agents/{id}/deprecate` remain human/session-only — no API-key eligibility | Allow API-key-driven publish for CI/CD-style Agent pipelines (considered, rejected for this document — 6D already established publish as a human-gated, sensitive go-live action, and 6E has no new evidence that changes that risk calculus) | Preserves 6D's existing security posture rather than weakening it for convenience, per the governing task's explicit instruction | Decided |
| ADR-6E-10 | `POST /agents/{id}/publish` accepts an optional `If-Match` precondition, reusing the existing weak-ETag mechanism | Leave publish with no precondition option at all (the original 6D behavior — retained as the default when the header is omitted); invent a dedicated `version_number`-based precondition (rejected — 6A §17.1 confirms no such column exists platform-wide, and inventing one would be a Phase 5 change this document cannot make) | A purely additive, backward-compatible refinement using a mechanism 6A already defines | Decided |
| ADR-6E-11 | Duplicate `tool_permissions` entries and duplicate/self-referential `fallback_providers` entries are hard publish-time errors | Leave both unspecified, as 6D's frozen text did (rejected — the governing task explicitly asks 6E to validate these); treat them as warnings only (rejected — neither has any defined runtime meaning, so silently accepting them would let an Agent Builder believe a no-op configuration does something) | Disclosed tightening of a previously-unspecified area, consistent with §5.3's reconciliation method | Decided |
| ADR-6E-12 (new; amended this pass) | Tenant-custom `tool_name` must be unique across the tenant's full visible namespace (own tools ∪ platform built-ins), enforced at the application layer on `POST /tools`/`PATCH /tools/{id}`, not merely within the tenant's own scope. **Amended this pass:** the tenant-vs-built-in half is reliable-by-construction (no race), not merely "disclosed as a residual" — 6E exposes no built-in-mutation endpoint, so there is no concurrent writer to race against (§21.2a) | Rely on 5C's existing two mixed-scope unique indexes alone (retracted — they protect two independent namespaces, never checked against each other); add a new cross-scope Phase 5 unique constraint (rejected — would require a functional/partial index spanning both `organization_id IS NULL` and a specific tenant's rows, which Postgres cannot express as a single constraint without knowing the tenant at DDL time) | The runtime resolves/invokes tools by `tool_name` — a same-name built-in/custom pair is a real ambiguity hazard, not a cosmetic one; the fix belongs at the API layer since Phase 5 cannot express this constraint declaratively, and describing its concurrency profile accurately (no built-in-mutation endpoint exists) is part of getting the fix right | Decided |
| ADR-6E-13 (amended twice — this pass and the prior one) | Effective `ProviderConfig` **configuration-identity/existence** resolution (6E) is answered by a single, `circuit_state`-agnostic, `LIMIT 1` application query (§11.4 query A) returning every column rules #5/#12/#15 need (`model_id`, `supports_languages`, `health_state`, `circuit_state`); 6D's frozen `circuit_state = 'CLOSED'`-filtered runtime query (5C §15.11, query B) is cited, not reused, for that purpose | **Superseded, prior pass:** the original decision reused query B verbatim for 6E's existence check (retracted — it silently excluded `OPEN`-circuit providers from *existing*, `DEP-6E-22`). **Amended, this pass:** query A itself was missing `supports_languages` and `LIMIT 1`, leaving rule #12 without a data source and "the resolved row" ambiguous relative to rule #5's own result (retracted, `DEP-6E-24`) — both are added, no schema/index change | Existence (a configuration fact) and routability (a runtime, second-to-second fact) must not share one filtered query; separately, once 6E owns its own existence query, that query must actually carry every field 6E's own rules read from "the resolved row," and must return exactly one row so "the resolved row" has an unambiguous referent | Decided |
| ADR-6E-14 (amended this pass) | `LanguageEvaluationRecord` selection for publish-time validation uses a new, 6E-owned application query (§15.6 query B) — filtered by the resolved `provider_id`, unfiltered by `verdict`, `ORDER BY evaluated_at DESC LIMIT 1` — over the same already-frozen `idx_ler_lookup` index; 5C §15.12's own reference-list query (query A) is unchanged and continues to serve `GET /language-evaluations` only | **Superseded this pass:** the original decision reused query A verbatim for 6E's validation lookup (retracted — query A's `WHERE verdict IN ('APPROVED','CONDITIONAL')` makes `REJECTED` structurally undetectable, and it carries no `provider_id` predicate at all, `DEP-6E-23`); select by `evaluation_set_ref` recency instead of `evaluated_at` (rejected — no frozen document orders evaluation sets independent of `evaluated_at`); require an exact `provider_model_ref` match (rejected — `ModelConfig` carries no client-supplied `model_id` to match against, §11.1) | `idx_ler_lookup`'s own `(language, provider_id, capability, evaluated_at DESC)` shape already supports an unfiltered, `provider_id`-scoped query — the fix is a new application query over the existing index, not a new index and not a reinterpretation of the existing reference-data query | Decided |
| ADR-6E-15 (retracted and replaced this pass) | **The original decision — a publish/PATCH-time prohibited-key-substring rejection rule for `qualification_criteria`, citing 6A §22's redaction vocabulary — is retracted in full.** Replaced with: no input-side validation rule for this field; output-side non-exposure only (never logged, traced, or placed in an audit `resource_snapshot`) | Keep the rejection rule (retracted — 6A §22's cited row is scoped explicitly to *logs and traces*, an output-redaction standard, and does not authorize rejecting API input; the rule also risked false positives against legitimate field names such as `credential_status`/`token_budget_category`); invent a new closed `QualificationCriteria` schema (rejected — DDD-level work outside this API-design document's authority, no frozen source defines one); claim no mitigation at all is possible (rejected — output-side non-exposure is a genuine, frozen-standard-supported mitigation, §9.4) | An unsupported validation rule is worse than no rule — it creates false confidence in a nonexistent guarantee while also being user-hostile; the honest, evidence-grounded position is disclosed risk plus output-side discipline | Decided |
| ADR-6E-16 (new this pass) | The tool-deactivate-vs-publish transactional guarantee is stated precisely as "revalidated against the committed state visible at the publish transaction's own validation read" — not as "active at the exact moment of publication" | Keep the original, stronger-sounding phrasing (retracted — it overstates what READ COMMITTED actually guarantees, per the governing task's explicit correction); add `SELECT ... FOR UPDATE` to close the race window entirely (rejected — violates frozen 6A §17.3, and 6D's own frozen design already accepts structurally identical races elsewhere, e.g. terminate-vs-transfer) | An implementer's error-handling and test-writing code must be built against the guarantee PostgreSQL actually provides, not an idealized one | Decided |
| ADR-6E-17 (new this pass) | Publish-time provider-specific capability/evaluation validation (§15.4 rules #12–#14) is scoped to the LLM category only — the sole category for which Agent configuration ever supplies a client-identified `provider_id` | Validate "the selected provider" generically across `STT`/`TTS`/`LLM` (retracted — no frozen document defines a deterministic mapping from `VoiceConfig` to a specific STT/TTS `provider_configs` row; `voice_id` is explicitly provider-agnostic, 4B §5.3.1); invent `stt_provider_id`/`tts_provider_id` fields to make the generic check possible (rejected — this would be a DDD/schema-level scope change no API-design document has authority to make) | 6E can only validate what Agent configuration actually, deterministically identifies; claiming broader provider-specific validation than that would be fabricating a capability the platform does not have | Decided |
| ADR-6E-18 (new this pass) | The `uq_pc_priority` ordering claim in §11.4 is narrowed to the scope it actually guarantees: full deterministic ordering within one tenant's own `(organization_id, category)` scope (a concrete, non-`NULL` value); platform-scope determinism rests on the separate, `NULL`-safe `uq_pc_platform_cat` constraint instead, not on `uq_pc_priority` | Keep the original "strict total order over every tenant-visible candidate row" claim, unqualified (retracted — ordinary PostgreSQL `UNIQUE` semantics treat every `NULL` as distinct from every other `NULL` for uniqueness purposes, absent an explicit `NULLS NOT DISTINCT` clause, which 5C §16.5's migration DDL does not use; the claim therefore does not hold for the `organization_id IS NULL` scope as stated) | An implementer's concurrency/ordering assumptions must match what the actual index definition — and PostgreSQL's actual NULL-handling semantics — guarantee, not an idealized reading of the `ORDER BY` clause | Decided |
| ADR-6E-19 (new this pass — micro-correction) | §11.4 query (A) is the **sole, authoritative** definition of the single `ProviderConfig` row consumed by every 6E publish-time check for a `provider_id` — it therefore must `SELECT` every column any such check reads (`supports_languages` for rule #12, alongside the already-present `model_id`/`health_state`/`circuit_state`) and must return at most one row (`LIMIT 1`) | Add a second query for `supports_languages` specifically, run alongside query (A) (rejected — reintroduces exactly the "which row, read when" ambiguity §11.4 exists to close, and doubles the round-trips for no benefit); leave `supports_languages` out and have rule #12 "assume" it was fetched elsewhere (rejected — never actually specified anywhere, a silent gap); omit `LIMIT 1` and rely on the `ORDER BY` alone (rejected — a query without `LIMIT 1` returns a *set*, not "the resolved row" later sections plainly refer to in the singular) | One authoritative query per resolved entity is simpler to reason about, test, and implement than several partially-overlapping ones; the fix is minimal — two clauses added, zero semantics changed for existence or ordering | Decided |

---

## 40. OpenAPI / Implementation Readiness

### 40.1 REST Surface

All 16 public + 1 internal endpoint (§30) are OpenAPI-ready per 6A §32.1's checklist: purpose, method+path, auth, authz permission string, path/query params, headers (incl. `Idempotency-Key`/`If-Match` where applicable), request/response schemas, idempotency behavior, rate-limit class, latency tier, side effects/events, consistency behavior, audit `action_kind` (all eight state-changing endpoints cite an exact-match, governed value, §25.3), example request/response. The one internal endpoint (§30.17) is excluded from the public OpenAPI document per 6A §8.5/6B §17.2's own rule.

### 40.2 Implementation Readiness Matrix

| Area | Ready? | Notes |
|---|---|---|
| REST endpoint contracts | Yes | §30 — full depth on 3 showcases, compact-but-complete on the remaining 14 |
| Authorization | Yes | §27 — re-verified against 5B's grant table, no over-grant found |
| Audit coverage | Yes | §25 — 8/8 state-changing endpoints, exact-match governed `action_kind`s, no 5J amendment required |
| Validation model | Yes | §15 — ERROR/WARNING classification formalized, grounded in 5C/4B/4I data, no fabricated capability claims |
| State machine / concurrency | Yes | §31–§32 — reused 6D mechanism, draft-PATCH-vs-publish race explicitly grounded in Postgres MVCC |
| ≤750ms Voice runtime boundary | Yes, unchanged | §22 — zero figures altered, explicit non-interference argument for every 6E design choice |
| Tool Definition ownership | Yes | §21 — Option A decided, path/permission/audit unchanged, one new visible-namespace-uniqueness rule added (§21.2a) and disclosed as such |
| Provider/Language reference data ownership | Yes | §20 — moved, unchanged in substance |
| PII/security | Yes, with one disclosed residual | §28 — AgentVersion snapshot secret-safety is structurally argued for every closed-shape field; `qualification_criteria` has **no input-side control at all** after this pass's retraction of the unsupported key-substring rule, mitigated only on the output side (never logged/traced/audit-snapshotted, `DEP-6E-16`) |
| Opaque-reference boundary | Yes, disclosed | §14 — format-only, existence-validation ownership explicitly open (`DEP-6E-02/03/04`), not silently assumed resolved |
| Tool-name visible-namespace uniqueness | Yes | §21.2a — new invariant closing the false-guarantee gap a prior pass's threat model contained; DB-backed within one tenant's scope, reliable-by-construction (no built-in-mutation endpoint exists, so no race) across the tenant/built-in scope boundary — corrected this pass from an earlier "disclosed race residual" framing that did not match 6E's actual API surface |
| Tool-deactivate-vs-publish concurrency semantics | Yes, precisely stated | §15.2 — corrected from an overstated "exact moment" claim to the actual READ-COMMITTED validation-read guarantee; the disclosed race window is accepted, not hidden |
| **Provider configuration-identity vs. runtime routability — separated** | **Yes** | §11.4 — two explicit, separate queries (6E existence, `circuit_state`-agnostic; 6D runtime, `circuit_state='CLOSED'`); an `OPEN`-circuit provider now correctly exists and produces a `WARNING` (§15.4 rule #15) instead of a contradictory `ERROR` (`DEP-6E-22`) |
| **§11.4 query (A) field/cardinality completeness — micro-corrected this pass** | **Yes** | §11.4 — query (A) now selects `supports_languages` (previously missing, leaving rule #12 without a data source) and adds `LIMIT 1` (previously absent, leaving "the resolved row" ambiguous); it is now the single, authoritative source for every field rules #5/#12/#15 read for one `provider_id` (`DEP-6E-24`) |
| **`LanguageEvaluationRecord` validation query — fixed to observe `REJECTED`** | **Yes** | §15.6 — a new, `provider_id`-filtered, `verdict`-unfiltered application query (B) replaces the prior reuse of 5C §15.12's `APPROVED`/`CONDITIONAL`-only reference-list query; `REJECTED` is now structurally detectable (`DEP-6E-23`) — unchanged by this pass, not reopened |
| **Provider-specific validation scoped to LLM only** | **Yes** | §15.5 — rules #12–#14 now run only for the tenant-identified LLM provider(s); no STT/TTS provider-specific check is claimed, since Agent config never identifies one (`DEP-6E-21`) — unchanged by this pass, not reopened |
| Deterministic `ProviderConfig` resolution | Yes, ordering claim narrowed | §11.4 — grounded in 5C §15.11's already-frozen query pattern; the "strict total order" claim is corrected to apply fully within one tenant's own scope, with platform-scope determinism resting on `uq_pc_platform_cat` instead of an overstated reading of `uq_pc_priority`'s NULL semantics |
| Deterministic `LanguageEvaluationRecord` selection | Yes, with disclosed residuals | §15.6 — most-recent-by-`evaluated_at` via a `provider_id`-scoped query, grounded in 5C's index shape and 4I's `ConsentRecord` precedent; two non-blocking residuals named (`DEP-6E-12`) |
| FR-TEN-005 Agent-count quota traceability | Yes, explicitly handed off | §33, §37, `DEP-6E-20` — not silently waived; named as 6K's future responsibility against the endpoint (`POST /agents`) 6E already owns |

---

## 41. Final Approval Gate / Status

### 41.1 The Prior Correction Pass's Seven Closure Checks (carried forward, re-verified still passing)

| # | Condition | Result |
|---|---|---|
| A | Visible ToolDefinition namespace uniqueness is correctly guaranteed, and the prior false claim is retracted | **PASS** — §21.2a's application-layer invariant closes the gap; §35's threat-model row retracts the false "Phase 5 indexes alone prevent this" claim. **Scope further corrected this pass** — see §41.2 check 8 |
| B | Tool-deactivate/publish concurrency semantics are stated at the strength PostgreSQL actually provides | **PASS**, unchanged this pass — §15.2 |
| C | Deterministic `ProviderConfig` resolution is defined or honestly declared unresolved | **PASS**, **ordering claim narrowed this pass** — see §41.2 check 1/2 and `DEP-6E-19` |
| D | Deterministic `LanguageEvaluationRecord` selection is defined or honestly declared unresolved | **PASS**, **query itself corrected this pass** — see §41.2 checks 3/4/5 and `DEP-6E-23` |
| E | `QualificationCriteria` / immutable-snapshot secret safety is stated at the strength actually supported | **PASS**, **mitigation mechanism corrected this pass** — see §41.2 check 7 and `DEP-6E-16` |
| F | FR-TEN-005 Agent-count quota handoff to 6K is explicit, not silently absorbed or waived | **PASS**, unchanged this pass — §33, §37, `DEP-6E-20` |
| G | 6D→6E wording accurately distinguishes "preserved" from "additive refinement" | **PASS**, unchanged this pass — §2, §5.3, §7.3 |

### 41.2 Correction Pass 2's Eight Freeze-Blocker Closure Checks (carried forward, re-verified still passing)

| # | Condition | Result |
|---|---|---|
| 1 | Provider existence (6E) vs. runtime routability (6D) are separated | **PASS.** §11.4 now defines two distinct queries — (A) 6E's existence check, no `circuit_state` filter; (B) 6D's frozen runtime query, `circuit_state='CLOSED'`, cited not reused. The prior pass's reuse of query B for 6E's existence check is retracted (`DEP-6E-22`, RESOLVED) |
| 2 | An `OPEN`-circuit provider can resolve (pass existence) and independently generate a `WARNING` | **PASS.** §15.4 rule #5 passes for any `is_active=TRUE` row regardless of `circuit_state`; rule #15 separately inspects `circuit_state`/`health_state` on an already-existing row and fires `WARNING` for `OPEN` (never `ERROR`) — the two rules no longer contradict each other. `HALF_OPEN` is explicitly carved out as producing no `WARNING` (§15.4 rule #15, §11.4's test matrix) |
| 3 | The `LanguageEvaluationRecord` publish-validation query can actually observe `REJECTED` | **PASS.** §15.6 query (B) carries no `verdict` filter at all — it selects the single most-recent row by `evaluated_at DESC LIMIT 1` and interprets whatever verdict it holds, `REJECTED` included. 5C §15.12's original `verdict IN ('APPROVED','CONDITIONAL')`-filtered query (A) is preserved unchanged but is now explicitly scoped to `GET /language-evaluations` only, never to publish validation (`DEP-6E-23`, RESOLVED) |
| 4 | The `LanguageEvaluationRecord` publish-validation query filters by the resolved `provider_id` | **PASS.** §15.6 query (B) includes `AND provider_id = $provider_id`; the prior pass's query had no `provider_id` predicate at all — corrected in the same edit as check 3 |
| 5 | The latest applicable record is selected *before* its verdict is interpreted, not filtered by verdict first | **PASS.** §15.6 query (B)'s `ORDER BY evaluated_at DESC LIMIT 1` runs with no `WHERE verdict = ...` clause; §15.4 rules #13/#14 and §15.6 points 2/8 interpret the single returned row's `verdict` only after it is selected, including the "older `APPROVED` superseded by newer `REJECTED`" and "older `REJECTED` superseded by newer `APPROVED`" cases named explicitly in §15.6 point 8 and tested in §36.4 |
| 6 | No unsupported STT/TTS provider-specific resolution is claimed | **PASS.** §15.5 states, grounded in 4B §5.3.1's "provider-agnostic" `voice_id` and the absence of any `stt_provider_id`/`tts_provider_id` field or mapping anywhere in 3B/4B/5C, that provider-specific validation (§15.4 rules #12–#14) is scoped to the LLM category only — the sole category Agent config ever identifies a `provider_id` for. `GET /language-evaluations`'s broader reference-data exposure (§20) is unaffected and not conflated with this scoping (`DEP-6E-21`, RESOLVED) |
| 7 | `QualificationCriteria` secret handling rests on a supported standard, not an invented API rule | **PASS.** The prior pass's `422`-rejection rule (citing 6A §22's logging/tracing redaction vocabulary as authorization for an input-validation rule) is retracted in full (§9.4, ADR-6E-15). The mitigation that remains — never logging/tracing/audit-snapshotting `qualification_criteria`'s raw contents — is a genuine application of 6A §22's actual, output-scoped redaction standard. No input-side rejection rule for this field exists anywhere in this document (`DEP-6E-16`, re-scoped, NON-BLOCKING — MITIGATED ON THE OUTPUT SIDE ONLY) |
| 8 | The tool visible-name guarantee is scoped to what 6E's API surface actually does | **PASS.** §21.2a, §32.2, and §35 no longer describe the tenant-vs-platform-built-in half as a disclosed concurrency race — 6E exposes no built-in-mutation endpoint, so a built-in's name is always static, already-committed data with no concurrent writer to race against. The invariant is stated as fully resolved for 6E's actual tenant ToolDefinition mutation surface, with an explicit forward-looking note that any future platform-admin/built-in-provisioning API must independently enforce the same invariant (`DEP-6E-18`, RESOLVED, re-scoped) |

**All eight of Pass 2's closure checks PASS** (check 1 is superseded in substance, not overturned, by §41.2a's check below — Pass 2 correctly separated the two queries; this pass corrects a field-completeness gap in the query Pass 2 introduced).

### 41.2a This Micro-Correction Pass (Pass 3) — One Closure Check

| # | Condition | Result |
|---|---|---|
| 1 | §11.4 query (A) is a single, complete, authoritative source for every field 6E's publish-time provider checks read for one `provider_id` | **PASS.** Query (A) now `SELECT`s `supports_languages` (previously absent, leaving rule #12's language-capability check without a data source anywhere in the query it was said to rely on) and adds `LIMIT 1` (previously absent, leaving "the resolved row" rules #12/#15 refer to ambiguous relative to what rule #5's existence check itself returned, and permitting more than one row where "the effective row" is described in the singular). §11.4, §15.4 rules #5/#12/#15, and §15.5 now all point to this one query, one row, explicitly (`DEP-6E-24`, RESOLVED; ADR-6E-13 amended, ADR-6E-19 added). No `WHERE`/`ORDER BY` predicate changed, no schema/index/migration touched, and none of the following is reopened: LLM-only scoping (§15.5, `DEP-6E-21`), the `LanguageEvaluationRecord` query fix (§15.6, `DEP-6E-23`), tool-name uniqueness (§21.2a, `DEP-6E-18`), `qualification_criteria` treatment (§9.4, `DEP-6E-16`), tool-deactivate/publish semantics (§15.2), FR-TEN-005 (`DEP-6E-20`), AgentVersion immutability (§16.1), permissions/audit/outbox (§25–§27), Phase 5 schema, or 6D runtime behavior |

**This pass's one closure check PASSES.**

### 41.3 The Original 29-Point Closure Check, Re-Verified (rows corrected across all three passes)

| # | Condition | Result |
|---|---|---|
| 1 | 6D/6E ownership overlap is explicitly reconciled | **PASS** — §5, §6 |
| 2 | No frozen 6D contract is contradicted | **PASS — wording corrected this pass.** 6D's paths, permissions, audit `action_kind`s, lifecycle states, and persistence invariants are reproduced without contradiction; this document no longer describes its own additive validation/concurrency refinements as "verbatim" reproductions, only as non-contradicting extensions (§2, §5.3, §7.3) |
| 3 | Agent management ownership is clear | **PASS** — §5.2's boundary statement |
| 4 | All Agent endpoints are complete | **PASS** — §30.1–30.9, 9 endpoints |
| 5 | Agent draft config is strongly typed | **PASS** — §9, no generic JSON bag at the API boundary, with `qualification_criteria`'s one open-ended exception now honestly flagged (§9.4) rather than silently treated as closed |
| 6 | AgentVersion remains immutable | **PASS** — §16.1, ADR-6E-04, unchanged from DDR-4B-003/5C §11.6 |
| 7 | Publish uses the Agent + AgentVersion approved transaction exception | **PASS** — §16.2, §24.2, reuses 6A §35's named exception, no new exception added |
| 8 | Tool references revalidated at publish, with the transactional guarantee stated precisely | **PASS — corrected this pass.** §15.2 states the actual READ-COMMITTED validation-read semantics rather than an overstated "exact moment" claim; mechanism and timing are unchanged from 6D §9.2, only the description is corrected |
| 9 | Concurrent publish uses correct `23505` bounded retry | **PASS** — §16.4, unchanged from 6D §9.2a/ADR-6D-11 |
| 10 | Call AgentVersion pinning remains untouched | **PASS** — §16.1, §22.4 |
| 11 | Voice runtime performs no per-turn Agent REST call | **PASS** — §22.2, §22.4, §36.10 (verified negatively) |
| 12 | Frozen ≤750ms Voice target unchanged | **PASS** — §22.1, zero figures altered |
| 13 | Auth uses real 5B permissions | **PASS** — §27, four existing permissions only (`agent:read/write/publish/delete`), zero invented |
| 14 | API-key eligibility is safe | **PASS** — §27.2, publish/deprecate remain human-only, unchanged from 6D |
| 15 | All mutations have governed audit action kinds | **PASS** — §25.3, 8/8 |
| 16 | Audit uses `audit.fn_insert_audit_event(...)` | **PASS** — §25.0, zero direct-INSERT instructions anywhere in this document |
| 17 | Outbox is separate from audit | **PASS** — §26.1, restates 6D's ADR-6D-15 correction |
| 18 | No later-phase API designed | **PASS** — §3.2, §3.3; no Knowledge/Workflow/Prompt/CRM/Campaign/Billing/Integrations/Analytics/Admin endpoint anywhere in this document |
| 19 | PII/secrets are bounded, at the strength actually supported by the schema | **PASS — wording corrected this pass.** §28 now distinguishes structurally-closed fields from `qualification_criteria`'s mitigated-only field, rather than a blanket claim (§28.1–28.3) |
| 20 | AgentVersion snapshot secret safety is stated honestly | **PASS — corrected across both passes.** §28.3 argues structural closure for every field except `qualification_criteria`; for that field, this pass further retracts the (unsupported) input-validation mitigation and states plainly that only output-side non-exposure remains, with no input-side control at all (`DEP-6E-16`) |
| 21 | Concurrency behavior is defined | **PASS** — §32, including the explicit draft-PATCH-vs-publish race (§16.3), the corrected tool-deactivate-vs-publish race (§15.2/§32.2), the tenant-vs-tenant tool-name-collision race (§32.2, a genuine race), and the tenant-vs-built-in tool-name check (§32.2, correctly *not* described as a race this pass) |
| 22 | Traceability complete | **PASS** — §37, including FR-TEN-005's corrected, non-waiving handoff wording |
| 23 | No unresolved architecture blocker remains | **PASS** — §38, every `DEP-6E-XX` (through `DEP-6E-23`) is labeled `RESOLVED`, `NON-BLOCKING`, or `DEFERRED TO [PHASE]`; none is labeled `BLOCKING` |
| 24 | 6A untouched | **PASS** |
| 25 | 6B untouched | **PASS** |
| 26 | 6C untouched | **PASS** |
| 27 | 6D untouched | **PASS** |
| 28 | Phase 5 schema/migrations untouched | **PASS** — no 5J amendment made, none required (§25.1–25.2); this correction pass also makes no Phase 5 edit |
| 29 | 6F+ not started | **PASS** — §3.2 |

**All 29 conditions PASS.**

### 41.4 Verdict

**PHASE 6E — APPROVED / FROZEN CANDIDATE.**

All seven of Pass 1's closure checks (§41.1, re-verified), all eight of Pass 2's freeze-blocker closure checks (§41.2, re-verified), this pass's (Pass 3's) one micro-correction closure check (§41.2a), and all 29 of the original closure conditions (§41.3) pass. Per the governing task's explicit instruction, this status remains a **candidate** recommendation, not a self-certified freeze — the user will independently review this corrected document before it is marked final `APPROVED/FROZEN`. No blocker from any checklist is outstanding; the two items future work should specifically revisit (`DEP-6E-16`, `DEP-6E-20`) are non-blocking by design and named exactly for that purpose (§38).

---

## 42. Confirmations

- **6A untouched.** No edit made to `6A-API-Architecture-and-Standards.md`.
- **6B untouched.** No edit made to `6B-Authentication-and-Authorization-API.md`.
- **6C untouched.** No edit made to `6C-Core-Platform-APIs.md`.
- **6D untouched.** No edit made to `6D-Voice-Call-Agent-APIs.md` — every adopted contract is reproduced by reference and citation, never by editing the source document. 6D's own text, including its historical framing as owning Agent CRUD, remains exactly as frozen; this document is the forward-looking authoritative pointer, not a retroactive correction.
- **Phase 5 — untouched, no amendment.** No edit was made to any file under `phase-05-database-design/`, including `5J-Analytics-Audit-Schema.md`. §25.1–25.2 explain precisely why no amendment is required: every `action_kind` and the synchronous-audit exception this document's mutations need were already added by 6D's own prior, already-authorized amendment.
- **6F+ not started.** No Knowledge/RAG, Workflow, Prompt, Memory, CRM, Campaign, Billing, Integrations, or Analytics API design was performed in this document — §3.2's exclusion list is exhaustive and was checked against every section before writing it.
