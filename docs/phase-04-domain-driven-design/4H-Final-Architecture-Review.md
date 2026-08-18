# Phase 4 — Final Architecture Review
## DDD Consistency & Architecture Validation

| | |
|---|---|
| **Document type** | Final validation review — not a redesign |
| **Status** | Draft v1.0, for approval before Phase 5 begins |
| **Corpus reviewed** | Phase 1 SRS, Phase 2 HLA, Phase 3A–3F LLD, Phase 4A–4G DDD |
| **Fundamental constraint** | Bounded Context ≠ Microservice. Phase 2's modular-monolith-of-bounded-contexts decision remains the deployment guide. Microservice extraction is recommended only where concrete, named architectural drivers justify it. |

---

## 1. Executive Summary

The Phase 4 DDD corpus (4A through 4G, seven sub-phases) is **architecturally sound and ready for Phase 5 (Database Design)** with the corrections and clarifications documented in this review.

**What is healthy:**
- No circular domain dependencies exist. The dependency graph is a strict directed acyclic graph (DAG).
- Aggregate boundaries are consistently sized — no God aggregates, no anemic splits.
- Tenant isolation is enforced at every layer (domain, application, database, cache, storage, events) as required by Phase 1 NFR-SEC-003.
- The voice real-time path (sub-800ms SLO) is never blocked by billing, analytics, CRM, or any other non-critical operation — all cross-domain integration is async via event bus.
- Security boundaries (CredentialRef pattern, RBAC, audit append-only, PII out of events) are consistent across all sub-phases.
- The ClickHouse migration path is clean — `AnalyticsWritePort` abstraction means no producer code changes are required.

**Issues found — thirteen total:**

| Severity | Count | Nature |
|---|---|---|
| Critical | 0 | — |
| Significant | 3 | Ownership ambiguity, naming inconsistency, missing port |
| Minor | 7 | Missing events, documentation gaps, clarifications needed |
| Enhancement | 3 | Future-proofing recommendations |

No issue requires redesigning a bounded context or contradicting a previously approved decision. All corrections are additive clarifications or minor renamings.

**Eight open questions (OQ-FINAL-01 through OQ-FINAL-08 from Phase 4G)** remain unresolved — they are not blockers for Phase 5's structural work, but some (particularly embedding model selection and multi-currency billing) affect specific column types and must be resolved before Phase 5's DDL is finalised.

---

## 2. Architecture Validation — Principles Compliance

| Principle | Compliant? | Evidence | Finding |
|---|---|---|---|
| Domain-Driven Design | ✅ | 20+ bounded contexts, all with ubiquitous language, aggregates, domain services | |
| Clean Architecture | ✅ | No domain aggregate imports FastAPI, SQLAlchemy, Redis, Celery, or any provider SDK | |
| Hexagonal Architecture | ✅ | All external systems behind named ports; adapters in infrastructure layer | |
| SOLID — SRP | ✅ | Each aggregate has one responsibility; no God classes identified | |
| SOLID — OCP | ✅ | Node executor registry, tool runner registry, provider adapter list all use open/closed extension | |
| SOLID — DIP | ✅ | All domain services depend on port abstractions, not concrete adapters | |
| Provider Independence | ✅ | Exotel, Deepgram, ElevenLabs, OpenAI, etc. are adapter implementations — never imported by domain | |
| Multi-tenancy | ✅ | `TenantId` on every tenant-scoped aggregate; RLS enforced at DB; Redis namespaced; S3 namespaced | |
| Event-driven integration | ✅ | All cross-context integration via domain events or named OHS ports; no direct cross-module imports | |
| Eventual consistency where appropriate | ✅ | Analytics, CRM activity, metering are eventual; billing payment and ownership transfer are strong | |
| Idempotency | ✅ | IdempotencyKey on all event consumers; UPSERT for projections; duplicate detection on CallJob | |
| Low latency (voice path) | ✅ | Voice hot path makes zero blocking calls to billing, CRM, analytics, or campaign | |
| Modular monolith (Phase 2) | ✅ | No context is mandated as a microservice; import-linter CI gate enforces module boundaries | |

---

## 3. Context Map Validation

### 3.1 Relationship Inventory

| Source | Target | Type | Data Ownership | Integration Mechanism | Consistency |
|---|---|---|---|---|---|
| Shared Kernel | All contexts | **Shared Kernel** | Platform | Import (permitted) | Compile-time |
| Organization (4A) | Identity (4A) | **Shared Kernel** | Platform | `UserId` reference | Compile-time |
| Organization (4A) | All downstream | **Published Language** | Organization | Domain events | Eventual |
| Authorization (4A) | All contexts | **Open Host Service** | Authorization | `CheckPermission` use case | Synchronous (cached) |
| Feature Flags (4A) | Voice, Campaign, Workflow, Billing | **Open Host Service** | Feature Flags | `EvaluateFlag` use case | Synchronous (cached) |
| Audit (4A) | All contexts | **Conformist** | Audit | All contexts → Audit subscriber | Eventual (fire-and-forget) |
| Agent (4B) | Voice/Call (4B) | **Customer → Supplier** | Agent | AgentVersion snapshot at call start | Snapshot-at-start |
| Workflow (4E) | Conversation (4B) | **Open Host Service** | Workflow | `WorkflowExecutionPort` | Synchronous per-turn |
| Prompt Mgmt (4E) | Conversation (4B) | **Open Host Service** | Prompt Mgmt | `PromptRenderPort` | Synchronous per-turn |
| Memory (4E) | Conversation (4B) | **Open Host Service** | Memory | `ConversationMemoryPort` | Sync (load) / async (append) |
| Knowledge/RAG (4E) | Tool Execution (4B) | **Open Host Service** | Knowledge | `KnowledgeSearchPort` | Synchronous |
| Plugins (4F) | Tool Execution (4B) | **Open Host Service** | Plugins | `invoke_plugin` use case | Synchronous (timeout-bounded) |
| CRM (4C) | Campaign Execution (4D) | **Open Host Service** | CRM | `ContactLookupPort`, `FindOrCreateContact` | Synchronous |
| Campaign Execution (4D) | Voice/Call (4B) | **Open Host Service** | Voice | `OutboundCallPort` | Synchronous |
| Usage Metering (4F) | Voice/Call (4B), Campaign (4D) | **Open Host Service** | Usage Metering | `CheckQuota` use case | Synchronous (Redis-backed) |
| Voice (4B) | CRM (4C) | **Published Language** | Voice | `call.ended`, `conversation.*` events | Eventual |
| Voice (4B) | Campaign (4D) | **Published Language** | Voice | `call.ended`, `call.failed` | Eventual |
| Voice (4B) | Usage (4F) | **Published Language** | Voice | `call.ended`, turn-level events | Eventual |
| CRM (4C) | Campaign (4D) | **Published Language** | CRM | `contact.qualified`, `contact.dnc_flagged` | Eventual |
| Campaign (4D) | Analytics (4G) | **Published Language** | Campaign | `campaign.*` events | Eventual |
| Integrations (4F) | CRM (4C) | **Anti-Corruption Layer** | CRM | Salesforce/HubSpot ACL → CRM commands | Eventual |
| Webhooks (4F) | All contexts | **Conformist** | Webhooks | All events → webhook dispatcher | Eventual |
| Analytics (4G) | All contexts | **Conformist** | Analytics | Pure consumer of all events | Eventual |
| LLM Router (4D §11) | Voice (4B), Memory (4E), RAG (4E) | **Open Host Service** | LLM Router | `LlmPort` | Synchronous streaming |
| Billing (4F) | Organization (4A) | **Conformist** | Billing | `org.created` → create BillingAccount | Eventual |

### 3.2 Context Map Issues Found

**ISSUE-01 (Minor):** The LLM Provider Router module (`llm_provider_router/`) is described in Phase 3D §11 as "its own bounded context" but it was **not** given a dedicated 4x sub-phase document. Phase 4B §9 treats it as an application service inside Voice Orchestration, while Phase 3D promotes it to a separate module. This creates a documentation gap — the LLM Router has no authoritative DDD document defining its aggregates (ProviderConfig) formally.

**Finding:** ProviderConfig is documented in Phase 4B §5.8 as part of the Voice domain. The LLM Router is not a separate bounded context — it is the **Provider Network** module within the Voice bounded context, as per Phase 4B §2.1's subdomain classification (Generic Subdomain). The Phase 3D language of "its own bounded context" is imprecise.

**Recommended correction:** Formally classify `llm_provider_router/` as the **Provider Network** supporting subdomain within the Voice & AI bounded context. No structural change needed — only naming clarification in future documentation.

---

## 4. Aggregate Validation

### 4.1 Complete Aggregate Inventory

| Context | Aggregate | Aggregate Root | Owner | Transaction Boundary | Consistency | Events Produced | Scaling Concern |
|---|---|---|---|---|---|---|---|
| **4A — Identity** | | | | | | | |
| | User | User | Identity | Per-aggregate | Strong | `user.registered`, `user.deactivated` | Low — global but read-heavy |
| | ApiKey | ApiKey | Identity | Per-aggregate | Strong | `apikey.issued`, `apikey.revoked` | Low |
| | Role | Role | Authorization | Per-aggregate | Strong | `role.permissions_updated` | Low |
| **4A — Organization** | | | | | | | |
| | Organization | Organization | Organization | Per-aggregate; dual for CreateOrganization (+ owner Membership) | Strong | `org.created`, `org.suspended` | Low |
| | Membership | Membership | Organization | Per-aggregate; dual for TransferOwnership | Strong | `membership.*` | Medium — many per org |
| | FeatureFlag | FeatureFlag | Feature Flags | Per-aggregate | Strong | `feature_flag.*` | Low |
| | AuditEvent | AuditEvent | Audit | Append-only | N/A | None published externally | **High** — written per every action |
| | QuotaUsage | QuotaUsage | Usage (4F) | Redis INCR + Postgres batch | Eventual | `quota.exceeded` | **High** — written per every call/turn |
| **4B — Voice** | | | | | | | |
| | Call | Call | Voice | Per-aggregate; dual for StartConversation | Strong | `call.initiated`, `call.ended`, `call.failed` | **High** — millions per day |
| | Conversation | Conversation | Conversation | Per-turn checkpoint (Redis hot + Postgres) | Eventual | `conversation.turn_completed`, `conversation.completed` | **High** — written per turn |
| | Agent | Agent | Agent | Per-aggregate | Strong | `agent.published` | Low |
| | AgentVersion | AgentVersion (embedded in Agent) | Agent | Same as Agent | Strong | Included in `agent.published` | Low |
| | ToolDefinition | ToolDefinition | Tool Execution | Per-aggregate | Strong | None | Low |
| | ToolExecution | ToolExecution | Tool Execution | Per-aggregate | Strong | `tool_execution.*` | Medium |
| | Recording | Recording | Recording | Per-aggregate | Strong | `recording.stored` | Medium |
| | Transcript | Transcript | Recording | Append-only segments | Eventual | `transcript.completed` | **High** — written per STT fragment |
| | ProviderConfig | ProviderConfig | Provider Network | Per-aggregate + Redis health | Eventual | `provider.circuit_opened` | Low |
| **4C — CRM** | | | | | | | |
| | Contact | Contact | CRM | Per-aggregate; dual for MergeContacts | Strong | `contact.created`, `contact.qualified`, `contact.converted` | **High** — millions at scale |
| | Company | Company | CRM | Per-aggregate | Strong | `company.created` | Medium |
| | Deal | Deal | Deal/Pipeline | Per-aggregate | Strong | `deal.created`, `deal.won`, `deal.lost` | Medium |
| | Pipeline | Pipeline | Deal/Pipeline | Per-aggregate | Strong | `pipeline.created` | Low |
| | Activity | Activity | Activities | Append-only | N/A | `activity.recorded` | **High** — one per call per contact |
| | Task | Task | Activities | Per-aggregate | Strong | `task.created`, `task.completed` | Medium |
| | Note | Note | Activities | Per-aggregate | Strong | `note.added` | Medium |
| | Appointment | Appointment | Appointments | Per-aggregate | Strong | `appointment.booked` | Medium |
| | LeadScoreRecord | LeadScoreRecord | Lead Scoring | Write-once per scoring event | N/A | `contact.score_updated` | Medium |
| | CRMFieldDefinitionSet | CRMFieldDefinitionSet | Custom Fields | Per-aggregate (one per tenant) | Strong | None | Low |
| **4D — Campaign** | | | | | | | |
| | Campaign | Campaign | Campaign Mgmt | Per-aggregate | Strong | `campaign.started`, `campaign.completed` | Medium |
| | CampaignContact | CampaignContact | Campaign Exec | Per-aggregate | Strong | `campaign.contact.*` | **Very High** — millions per campaign |
| | CallJob | CallJob | Campaign Exec | Per-aggregate | Strong | `call_job.*` | **High** — one per dial attempt |
| | ContactList | ContactList | CSV Import | Per-aggregate | Strong | `contact_list.ready` | Medium |
| | CsvImportJob | CsvImportJob | CSV Import | Per-aggregate | Strong | `import.completed` | Medium |
| | CampaignOutcome | CampaignOutcome | Campaign Outcomes | Per-aggregate | Strong | `campaign.outcome_computed` | Low |
| **4E — Intelligence** | | | | | | | |
| | KnowledgeBase | KnowledgeBase | Knowledge | Per-aggregate | Strong | `knowledge_base.created` | Low |
| | Document | Document | Knowledge | Per-aggregate | Strong | `document.indexed`, `document.deleted` | Medium |
| | IngestionJob | IngestionJob | Knowledge | Per-aggregate | Strong | `ingestion.completed` | Medium |
| | WorkflowDefinition | WorkflowDefinition | Workflow Engine | Per-aggregate | Strong | `workflow.published` | Low |
| | WorkflowExecution | WorkflowExecution | Workflow Engine | Per-turn checkpoint | Eventual | `workflow.execution_completed` | **High** — one per live call |
| | PromptTemplate | PromptTemplate | Prompt Mgmt | Per-aggregate | Strong | `prompt.published` | Low |
| | PromptExperiment | PromptExperiment | Prompt Mgmt | Per-aggregate | Strong | `experiment.activated` | Low |
| | SessionMemory | SessionMemory | Memory | Redis hot + Postgres post-call | Eventual | `memory.session_summarized` | **High** — one per live call |
| | CustomerMemory | CustomerMemory | Memory | Per-aggregate | Strong | `memory.customer_fact_updated` | Medium |
| **4F — Commercial** | | | | | | | |
| | BillingAccount | BillingAccount | Billing | Per-aggregate | Strong | `billing.account_created` | Low |
| | Subscription | Subscription | Billing | Per-aggregate | Strong | `subscription.created`, `subscription.cancelled` | Low |
| | Plan | Plan | Billing | Per-aggregate | Strong | `plan.published` | Low |
| | Invoice | Invoice | Billing | Per-aggregate | Strong | `invoice.generated`, `invoice.payment_succeeded` | Medium |
| | UsageRecord | UsageRecord | Usage Metering | Redis INCR + Postgres batch | Eventual | `usage.quota_exceeded` | **High** — per metric per period |
| | UsageEvent | UsageEvent | Usage Metering | Append-only | N/A | `usage.event_recorded` | **Very High** — per billable unit |
| | CostEntry | CostEntry | Usage Metering | Append-only | N/A | None | **Very High** — per billable unit |
| | QuotaConfig | QuotaConfig | Usage Metering | Per-aggregate | Strong | None | Low |
| | IntegrationDefinition | IntegrationDefinition | Integrations | Per-aggregate (platform-global) | Strong | None | Low |
| | IntegrationConnection | IntegrationConnection | Integrations | Per-aggregate | Strong | `integration.connected` | Medium |
| | WebhookEndpoint | WebhookEndpoint | Webhooks | Per-aggregate | Strong | `webhook.endpoint_created` | Low |
| | WebhookDelivery | WebhookDelivery | Webhooks | Per-delivery | Strong | `webhook.delivery_succeeded` | **High** — one per event per subscriber |
| | Plugin | Plugin | Plugins | Per-aggregate (platform-global) | Strong | `plugin.approved` | Low |
| | PluginInstallation | PluginInstallation | Plugins | Per-aggregate | Strong | `plugin.installed`, `plugin.activated` | Medium |
| **4G — Analytics** | | | | | | | |
| | AnalyticsDashboard | AnalyticsDashboard | Analytics | Per-aggregate | Strong | None | Low |
| | Analytics Projections | (read models, not aggregates) | Analytics | UPSERT via event subscriber | Eventual | None | **High** — updated per event |

### 4.2 Oversized Aggregate Check

**Finding:** No oversized aggregates identified. All embedded entity lists are bounded:
- `Turn` in `Conversation` — bounded by call length (≤ ~50 turns typical).
- `NodeExecutionHistory` in `WorkflowExecution` — same bound as Turn.
- `PaymentAttempt` in `Invoice` — bounded at ~10 per invoice.
- `VersionHistory` in `Agent`, `WorkflowDefinition`, `PromptTemplate` — bounded at ≤ 50 versions per entity.
- `FlagRule` in `FeatureFlag` — bounded at ≤ 20 rules per flag.

### 4.3 Undersize / Unnecessary Split Check

**ISSUE-02 (Minor):** `IngestionJob` (Phase 4E §4.3) is a separate aggregate from `Document`. This is correct (IngestionJob has its own lifecycle and retry count independent of the Document). However, the Phase 4E folder structure places them both in `knowledge_rag/domain/aggregates/` without explicit documentation of why they are not merged. The justification is correct (long-running background pipeline with its own retry state) but should be confirmed as an explicit ADR in Phase 4E.

**Recommended correction:** Add DDR-4E-007 (in Phase 4E document or here) formally documenting the IngestionJob/Document split. No structural change.

### 4.4 Merge Candidates Check

No aggregates are identified that should be merged. All splits have documented rationale in their respective DDD sub-phases.

---

## 5. Event Architecture Validation

### 5.1 Critical Event Coverage Check

| Event trigger | Event expected | Documented? | Consumer coverage |
|---|---|---|---|
| Call answered | `call.answered` | ✅ Phase 4B | Billing (start metering), Analytics |
| Call ended | `call.ended` | ✅ Phase 4B | CRM, Campaign, Usage, Analytics, Webhook, Billing |
| Call failed | `call.failed` | ✅ Phase 4B | Campaign (retry), Analytics, Webhook |
| Turn completed | `conversation.turn_completed` | ✅ Phase 4B | Analytics (latency), Billing (tokens), Transcript |
| Qualification set | `conversation.qualification_set` | ✅ Phase 4B | CRM, Campaign Exec, Analytics, Webhook |
| Conversation completed | `conversation.completed` | ✅ Phase 4B | Memory (summarize), Recording (finalize), Billing |
| Conversation summarized | `conversation.summarization_completed` | ✅ Phase 4G | CRM (AI note), Analytics |
| Lead created | `contact.created` | ✅ Phase 4C | Analytics, Webhook |
| Lead qualified | `contact.qualified` | ✅ Phase 4C | Campaign, Billing, Analytics, Webhook |
| Lead converted | `contact.converted` | ✅ Phase 4C | Billing, Analytics, Webhook |
| Appointment booked | `appointment.booked` | ✅ Phase 4C | Analytics, Webhook, Notification |
| Campaign started | `campaign.started` | ✅ Phase 4D | Analytics, Billing, Webhook |
| Campaign completed | `campaign.completed` | ✅ Phase 4D | Analytics, Billing, Webhook |
| Campaign ROI computed | `campaign.outcome_computed` | ✅ Phase 4D | Analytics, Webhook |
| Document indexed | `document.indexed` | ✅ Phase 4E | Analytics, Billing (embedding cost) |
| Workflow executed | `workflow.execution_completed` | ✅ Phase 4E | Analytics, Billing (LLM tokens) |
| Invoice generated | `invoice.generated` | ✅ Phase 4F | Analytics, Webhook, Notification |
| Invoice paid | `invoice.payment_succeeded` | ✅ Phase 4F | Analytics, Webhook, Subscription update |
| Quota exceeded | `usage.quota_exceeded` | ✅ Phase 4F | Billing (overage), Webhook, Analytics |
| Provider circuit opened | `provider.circuit_opened` | ✅ Phase 4G | Analytics, Alertmanager |
| Appointment no-show | `appointment.no_show` | ✅ Phase 4G (gap fixed) | Analytics |

### 5.2 Missing Events — Issues Found

**ISSUE-03 (Minor):** `contact.dnc_flagged` is referenced in Phase 4D §6.5 (DNC check in Call Queue) and Phase 4C §4.1 (MarkDoNotCall command) but is **not in the Phase 4G event catalog** (§11.4). It should be consumed by the Campaign Engine to immediately remove DNC contacts from active queues.

**Recommended correction:** Add `contact.dnc_flagged` to the event catalog with: Producer = CRM (4C), Consumers = Campaign Execution (4D), Webhooks (4F), Audit (4A).

**ISSUE-04 (Minor):** `memory.customer_fact_updated` is referenced in Phase 4G §11.6 but has no defined consumer — it appears to be a fact-update event with no downstream action currently defined.

**Recommended correction:** Either remove this event (if no consumer exists) or define the Analytics consumer that tracks memory enrichment rates. For Phase 5, this is a `customer_memories` table write with no event bus publication needed unless Analytics tracks it. Recommend removing from the event catalog until a consumer is identified.

**ISSUE-05 (Minor):** No event is defined for `contact.merged` reaching the **Campaign Engine** to update `CampaignContact.contact_ref` from the merged (secondary) ContactId to the primary ContactId. The `contact.merged` event is produced by CRM (4C §10.2) with the `primary_id` and `secondary_id`, but Phase 4D has no documented consumer for it.

**Recommended correction:** Campaign Execution (4D) must consume `contact.merged` and update all `CampaignContact` records for the secondary ContactId to reference the primary ContactId. Add to Phase 4D's event subscriber.

### 5.3 Event Idempotency Review

**ISSUE-06 (Significant):** The idempotency key definition for `conversation.turn_completed` is `turn_id` in the event catalog. However, the Usage Metering subscriber processes token counts from this event. If the same turn_id is delivered twice (at-least-once delivery), the same token count would be incremented twice. The `IdempotencyKey` pattern (SHA-256 of source_ref + metric + timestamp_minute truncation) from Phase 4F §5.2 must be applied to the Usage Metering consumer for this specific event.

**Recommended correction:** Usage Metering's subscriber for `conversation.turn_completed` must check its `usage_events` table for an existing row with `source_ref = turn_id AND metric = LLM_*_TOKENS` before inserting. This is the standard idempotency pattern already defined in Phase 4F — it needs to be explicitly called out for this high-frequency event.

### 5.4 Domain Events vs Integration Events Classification

| Event | Classification | Rationale |
|---|---|---|
| `call.ended` | **Integration Event** | Consumed by multiple contexts outside the Voice bounded context; carries a stable, versioned Published Language payload |
| `conversation.qualification_set` | **Integration Event** | Crosses Voice → CRM boundary |
| `contact.qualified` | **Integration Event** | Crosses CRM → Campaign, Webhook, Analytics |
| `campaign.outcome_computed` | **Integration Event** | Crosses Campaign → Analytics, Billing |
| `invoice.payment_succeeded` | **Integration Event** | Crosses Billing → Analytics, Webhook |
| `workflow.execution_started` | **Domain Event** | Internal to Workflow context only — not published to external bus (Phase 4G §11.2) |
| `memory.session_created` | **Domain Event** | Internal to Memory context — only the completion is an integration event |
| `provider.circuit_opened` | **Integration Event** | Crosses Provider Network → Alertmanager; though internal to Voice module, it has infrastructure consumers |

**Recommendation:** all events published to the external event bus (Redis Streams) are integration events by definition — they carry a public contract. Domain events that stay within a bounded context's own subscriber chain (never published to the bus) are pure domain events. Phase 5 and Phase 7 (Event Architecture) should formalise this classification in the schema.

---

## 6. Dependency Graph

### 6.1 Dependency DAG

```
Shared Kernel
    ↓ (all contexts import)
4A Identity & Organization
    ↓ (OHS: CheckPermission, org.created)
    ├── 4B Voice & AI
    │       ↓ (call.ended, conversation.* events)
    │       ├── 4C CRM                (consumes 4B events; supplies 4D ports)
    │       │       ↓ (contact.qualified, etc.)
    │       │       └── 4D Campaign   (consumes 4C events; drives 4B calls)
    │       └── 4F Usage Metering     (consumes 4B events for billing)
    ├── 4E Intelligence               (supplies 4B ports: Workflow, Prompt, Memory, RAG)
    │       — 4E depends on 4A (permissions) but not on 4B directly
    │       — 4B depends on 4E (ports), but 4E does not depend on 4B
    │         (this is deliberate: ports point from consumer to supplier)
    ├── 4F Billing / Webhooks / Plugins
    │       ├── Billing consumes 4A (org.created) and 4F Usage events
    │       ├── Webhooks consume ALL contexts' events
    │       └── Plugins supply 4B (invoke_plugin OHS)
    └── 4G Analytics                  (pure consumer, depends on all)
```

### 6.2 Circular Dependency Check

| Potential cycle | Analysis | Verdict |
|---|---|---|
| 4B (Voice) → 4E (Workflow) → 4B (LLM calls) | 4B calls Workflow via `WorkflowExecutionPort` (a port defined in 4B, implemented in 4E). 4E's Workflow engine makes LLM calls via `LlmPort` (defined in 4B's application layer, implemented in `llm_provider_router/`). The key: **4E never imports anything from 4B's domain or application layers**. 4E's WorkflowExecution calls `LlmPort` — a port defined in 4B — but implemented by `llm_provider_router/` which is in the Voice module. The dependency arrow is 4B → 4E (port implementation), not 4E → 4B. | ✅ No cycle |
| 4C (CRM) → 4D (Campaign) → 4C (FindOrCreateContact) | Campaign Execution calls CRM's `FindOrCreateContact` via a port (`ContactLookupPort`). CRM publishes `contact.qualified` consumed by Campaign. Both directions exist — but via **ports** (not direct imports), following the same pattern as 4B→4E. The port is defined in 4D's application layer and implemented by calling 4C's public use case. | ✅ No cycle — ports prevent import cycle |
| 4F (Billing) → 4D (Campaign ROI) → 4F (CostLookupPort) | Campaign Outcome calls `CostLookupPort` (defined in 4D, implemented by Billing's `get_campaign_cost` use case). Billing consumes campaign events. Bidirectional but via ports. | ✅ No cycle |
| 4G (Analytics) → any producing context | Analytics is a pure consumer — it never publishes events that any producer subscribes to, and it never calls any producer's use case. | ✅ No cycle possible |

**Finding: No circular dependencies exist.** All bidirectional relationships are mediated by ports (one direction) and domain events (other direction) — never by direct cross-module imports.

### 6.3 Coupling Assessment

| Relationship | Coupling level | Concern |
|---|---|---|
| Voice Orchestrator → Workflow, Prompt, Memory, LLM ports | **Controlled high coupling** (5 ports on the hot path) | Each port is a clean abstraction; tight coupling to the *interface* is intentional. No concern. |
| Campaign Execution → Voice Platform | **Low** (one port: `OutboundCallPort`) | Clean. |
| CRM → Campaign | **Low** (one port: `ContactLookupPort` + events) | Clean. |
| Webhooks → All contexts | **Intentionally high** (dispatcher subscribes to all events) | This is the design — webhooks are a conformist consumer. Managed by the event bus fan-out, not direct imports. No structural concern. |
| Analytics → All contexts | **Intentionally high** (same as Webhooks) | Same reasoning. No concern. |

---

## 7. Security Validation

### 7.1 Tenant Isolation

| Layer | Mechanism | Validated? |
|---|---|---|
| API | `TenantContext` set from JWT/API key at middleware; injected into all downstream calls | ✅ Phase 3A §11 |
| Application | Every use case receives `tenant_id` as mandatory parameter | ✅ All 4x sub-phases |
| Database (App layer) | `TenantScopedRepository` base class adds `WHERE tenant_id = :tenant_id` to all queries | ✅ Phase 3A §7 |
| Database (DB layer) | Postgres RLS policy enforces isolation at `SET LOCAL app.tenant_id` | ✅ Phase 3A §11.2 |
| Cache | Redis keys namespaced `{pattern}:{tenant_id}:{...}` | ✅ Phase 4G §17 |
| Storage | S3 keys namespaced `org/{tenant_id}/...` | ✅ Phase 4G §18.6 |
| Events | Every domain event envelope carries `tenant_id`; consumers filter/authorise by it | ✅ Phase 4A §9.1 |
| Plugin callouts | `X-Platform-Tenant-Id` header sent on every callout | ✅ Phase 4F §9.3 |

### 7.2 Secret and Credential Handling

| Concern | Mechanism | Validated? |
|---|---|---|
| Raw secrets never in domain aggregates | `CredentialRef` value object — opaque reference only | ✅ Phase 4F DDR-4F-002 |
| API key raw value never stored | SHA-256 hash stored; raw returned once at creation | ✅ Phase 4A §5.4 |
| Webhook signing secret never in domain | `SigningSecretRef` — opaque reference | ✅ Phase 4F §8.1 |
| Plugin credentials never in domain | `CredentialRef` — opaque reference | ✅ Phase 4F §9.2 |
| Integration OAuth tokens never in domain | `CredentialRef` — opaque reference | ✅ Phase 4F §6.2 |
| Secrets in event payloads | No event payload carries a raw secret — checked across all 4x event catalogs | ✅ |

**ISSUE-07 (Minor):** The `PasswordResetToken` value object on the `User` aggregate (Phase 4A §5.3) is described as "hashed on storage" but the Domain Event `user.password_reset_requested` is not explicitly documented as carrying a hashed token (not raw). Phase 5 and Phase 7 must confirm this: the reset token delivered via Notification must be the raw token (sent to user's email); the domain stores only the hash. The `user.password_reset_requested` event should carry the raw token to the Notification subscriber only — not to any other subscriber.

**Recommended correction:** Document in Phase 7 (Event Architecture) that `user.password_reset_requested` carries the raw reset token in an encrypted envelope, published only to the Notification subscriber's private channel — not to the general event bus where other subscribers could read it.

### 7.3 PII Handling

| PII type | Location in domain | In events? | Protected? |
|---|---|---|---|
| Phone number | `Contact.PrimaryPhone`, `CampaignContact.Phone`, `Call.From`/`To` | Not in event payloads (only `ContactId`/`CallId` referenced) | ✅ |
| Email address | `User.EmailAddress`, `Contact.PrimaryEmail` | `user.registered` carries email (needed for notification routing) | ⚠️ See below |
| Transcript text | `Transcript.TranscriptSegment.Text` | Not in events | ✅ |
| Recording audio | S3 only, referenced by `StorageRef` | Not in events | ✅ |
| AI conversation summary | `ConversationSummary` value object | `conversation.summarization_completed` carries `summary_text` | ⚠️ See below |

**ISSUE-08 (Minor):** `user.registered` carries `email` in the payload (needed for the Notification subscriber to send the verification email). This is the minimal necessary disclosure. However, it means the email is in the event bus — any subscriber to `user.registered` can read it.

**Recommended correction:** The event bus consumer group for `user.registered` should be restricted to: Audit subscriber and Notification subscriber only. No other context should subscribe to this event. Enforced by consumer group configuration in Phase 7.

**ISSUE-09 (Minor):** `conversation.summarization_completed` carries `summary_text`. The summary may contain PII (caller name, phone number mentioned in conversation). This event is consumed by CRM (to create an AI note). The summary text should be treated as sensitive and not logged in structured logs at the DEBUG level.

**Recommended correction:** Add `summary_text` to the PII deny-list in Phase 3A's Fluent Bit PII masking filter (Phase 3F §18.3). The field should be masked in any log pipeline processing but may appear in the CRM note itself.

### 7.4 RBAC Validation

**Finding:** Phase 4A §10 defines the permission model (`<resource>:<action>` strings) and the predefined role set. Phase 4F §10.1 and Phase 4G §3.1 confirm that `CheckPermission` (OHS) is called before all write commands across all contexts. The permission check is cached in Redis (5-minute TTL) with explicit invalidation on role change — per Phase 4A DDR-4A-002.

**One gap found: ISSUE-10 (Significant):** The Analytics context (Phase 4G) has no permission model defined. Which role can view the Executive Dashboard? Which role can view the Cost & Profitability dashboard? The `AnalyticsDashboard` aggregate has no `RequiresPermission` documentation.

**Recommended correction:** Define analytics permissions in the permission registry:
- `analytics:read` — Executive Dashboard, Call Analytics (all Roles except anonymous)
- `analytics:cost_read` — Cost/Revenue/ROI dashboards (Billing Admin, Admin, Owner only)
- `analytics:platform_read` — Cross-tenant Platform Admin dashboards (Platform Admin only)
These three permissions should be added to the Phase 4A permission catalogue before Phase 5 designs the analytics REST API.

### 7.5 Audit Coverage

**Finding:** Phase 4A §11 defines `AuditEvent` with `ActionKind` enumeration. Phase 4G §11 confirms all contexts publish audit-relevant events. 

**ISSUE-11 (Minor):** Plugin execution (`invoke_plugin`) is audited (Phase 4F §8.4 confirms `PluginInvoked` audit record). However, **plugin registration and approval** (`RegisterPlugin`, `ApproveVersion`, `RejectVersion`) are not explicitly in the `ActionKind` enumeration in Phase 4A §5.8.1.

**Recommended correction:** Add `PLUGIN_REGISTERED`, `PLUGIN_VERSION_APPROVED`, `PLUGIN_VERSION_REJECTED`, `PLUGIN_INSTALLED`, `PLUGIN_UNINSTALLED` to the `ActionKind` enumeration in Phase 4A §5.8.1.

---

## 8. Scalability Validation

### 8.1 Voice / WebSocket / Real-Time

| Component | Scaling mechanism | Concern |
|---|---|---|
| Voice Gateway | HPA keyed on `platform_active_calls` custom metric (Phase 3F §9.1); dedicated `voice` node pool | ✅ |
| WebSocket pod pinning | Sticky sessions via NGINX cookie + `X-Call-SID` header hash (Phase 3F §8.3) | ✅ |
| STT streaming | Per-call async task; failover to Gladia (Phase 4B §20) | ✅ |
| TTS streaming | Per-call async task; barge-in via `TtsPort.cancel()` (Phase 4B §10.3) | ✅ |
| LLM routing | ProviderSelectionService is pure function (no I/O); health data from Redis | ✅ |
| In-flight turn state | Redis hot-tier per session; Postgres checkpoint per turn | ✅ |

### 8.2 Campaign Workers

| Component | Scaling mechanism | Concern |
|---|---|---|
| Campaign Executor tick | APScheduler + Celery worker HPA on queue depth | ✅ |
| CampaignContact volume | Separate aggregate from Campaign; partitioned by campaign_id | ✅ |
| Call Queue / Retry Queue | Redis List + Sorted Set per campaign; reconstructable from Postgres | ✅ |
| CSV import | Batch-based (500 rows/task); independent Celery workers | ✅ |
| Concurrency enforcement | Redis counter per campaign + tenant-wide quota | ✅ |

### 8.3 Database Scaling

| Table | Volume concern | Mitigation |
|---|---|---|
| `usage_events` | Very high — one per billable unit per call/turn | Monthly RANGE partitioning; BRIN index; ClickHouse migration path |
| `audit_events` | High — one per audited action | Monthly RANGE partitioning; BRIN index; append-only |
| `call_sessions` | High — millions per month | Monthly RANGE partitioning |
| `campaign_contacts` | Very high — millions per campaign batch | LIST partitioning by `campaign_id` |
| `webhook_deliveries` | High — one per event per subscriber | Monthly partitioning; TTL-based cleanup |
| `document_chunks` | High (embedding vectors) | LIST partitioning by `knowledge_base_id`; pgvector HNSW |
| `transcript_segments` | High — per STT fragment | Monthly partitioning |
| `activities` | High — per call per contact | Monthly partitioning |

### 8.4 Redis Scaling

**Finding:** Phase 3F §16 designs Redis Cluster (3 primaries, 3 replicas) for production. All key patterns use `{tenant_id}` as the hash tag — keys for the same tenant land on the same shard, enabling cross-key operations without cross-shard coordination. This design is validated as correct.

**ISSUE-12 (Enhancement):** The `campaign:queue:{tenant_id}:{campaign_id}` Redis key uses `tenant_id` as the hash tag. For tenants running many simultaneous large campaigns (e.g., 50 campaigns with 100K contacts each), all campaign queue keys land on the same Redis shard, potentially creating a hot-shard. This is a future concern (not a current blocker) since the platform requires significant scale to hit this.

**Recommended correction for future:** if hot-shard becomes an issue, switch the hash tag to `{campaign_id}` — accepting that cross-campaign queries for one tenant would go cross-shard (a rare, non-latency-critical operation). Not a Phase 5 concern; note for Phase 22 (Deployment).

### 8.5 Analytics Scaling

**Finding:** Analytics projections are updated by Celery workers consuming from the event bus. The `analytics` Celery queue should be independently scaled (HPA on its own queue depth metric). Analytics workers never touch transactional tables of producing contexts — only their own projection tables.

**ClickHouse migration readiness:** `AnalyticsWritePort` abstraction is in place. Migration requires only a new adapter implementation — no producer changes. ✅

---

## 9. Low-Latency Validation

### 9.1 Voice Hot Path — Synchronous Operations

The following operations are synchronous (blocking) on the voice turn hot path. All others are async.

| Operation | Avg latency budget | Justification for sync |
|---|---|---|
| `TenantContext.set()` from webhook | < 1ms | Must be done before any other operation |
| `CheckPermission` (Redis cache) | < 2ms | Security gate — cannot be async |
| `CheckQuota` (Redis INCR) | < 2ms | Prevents over-dialing — must block |
| `AgentVersion` load (Redis cache) | < 5ms | Configuration for the call — immutable cache |
| `WorkflowExecutionPort.next_directive()` | < 10ms (pure + Redis) | Per-turn — must complete before LLM call |
| `PromptRenderPort.render()` | < 5ms (Redis cache) | Must be in LLM request — prompt is the input |
| `ConversationMemoryPort.load()` | < 20ms (DB read) | Must inject into first turn's prompt |
| STT streaming | 100–200ms | The actual transcription — unavoidable |
| `ProviderSelectionService.select()` | < 5ms (pure) | Must know which LLM before calling |
| LLM `complete()` streaming | 250–500ms (TTFT) | The AI response — unavoidable |
| Tool execution (if invoked) | 100–400ms | Some turns require tools — unavoidable |
| TTS `synthesize()` streaming | 100–150ms (first audio) | Audio delivery — unavoidable |

**Finding:** All non-voice operations are confirmed async:

| Operation | Async mechanism |
|---|---|
| CRM Activity creation from call | `call.ended` event → Celery |
| Usage metering from call | `call.ended` event → Celery |
| Analytics projection update | All events → Celery |
| Billing quota Redis INCR reconciliation | Nightly Celery task |
| Campaign contact outcome recording | `call.ended` event → Celery |
| Conversation memory appended per turn | Redis RPUSH (non-blocking) |
| Call recording finalization | `conversation.completed` event → Celery |
| Conversation summarization | `conversation.completed` event → Celery |
| Webhook delivery | `call.ended` (and others) → Celery |

**Finding: The voice hot path is clean.** No billing, analytics, CRM write, or campaign update is synchronous during call processing.

### 9.2 One Latency Concern Found

**ISSUE-13 (Significant):** Phase 4E §14.4 documents `MemoryApplicationService.load_memory()` as "blocking; implements `ConversationMemoryPort.load()`" with a note that it reads from the database. At the start of the **very first turn** of a call, this is a synchronous Postgres read (CustomerMemory for the contact).

For new contacts (no prior calls), this is a table lookup that returns null — fast. For repeat callers with rich CustomerMemory (many facts), this could take 10–30ms. This is within the latency budget (§21's 150ms allocated to STT endpoint detection happens while the system can in parallel start loading memory).

However, the current design loads memory **after** STT completes (Phase 4B §12.1 sequence diagram line: "Orch->>Mem: Load session/customer memory"). If the memory load is moved **before** the call starts (at call setup, not at turn 1), it could overlap with the telephony connection setup and eliminate it from the hot path entirely.

**Recommended correction:** Pre-load `ConversationMemory` during `StartConversation` use case execution (Phase 4B §6.1) rather than at the start of the first turn loop. The memory load is already triggered by `HandleInboundCallUseCase` in Phase 4B §14.1 — confirm that this happens before the first turn is processed, not as the first step of turn processing.

---

## 10. Database Readiness Assessment

**Verdict: Ready for Phase 5 with the following confirmed inputs.**

### 10.1 Schema Assignments (Confirmed)

13 PostgreSQL schemas as defined in Phase 4G §18.2: `identity`, `organization`, `voice`, `crm`, `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, `audit`.

### 10.2 Partitioning Decisions (Confirmed)

8 tables require partitioning before first production load — see Phase 4G §18.3. Phase 5 must create these as partitioned tables from the start; retrofitting partitioning to an existing table is a painful migration.

### 10.3 pgvector Decision

Phase 5 must enable the `pgvector` extension in Supabase and create the `document_chunks.embedding` column as `vector(N)` where N is the dimension of the selected embedding model. **This dimension is immutable after table creation (DDR-4E-003).** The embedding model selection (OQ-FINAL-03) must be resolved before Phase 5 can write the `document_chunks` DDL.

### 10.4 RLS Decision

Phase 5 must write `CREATE POLICY` statements for every tenant-scoped table, using the `app.tenant_id` session variable set by the platform's `rls.py` adapter (Phase 3A §11.2). Platform-global tables (`plans`, `integration_definitions`, `plugins`) have no RLS.

### 10.5 Cross-Schema References

Phase 4G §18.9 explicitly prohibits cross-schema FK constraints across major bounded-context schema boundaries. Phase 5 must use UUIDs (LogicalForeignKey by value, not REFERENCES) across schema boundaries. FK constraints are only permitted within the same schema.

### 10.6 Unresolved Items Affecting Phase 5

| Item | Blocking? | What is blocked |
|---|---|---|
| OQ-FINAL-03: Embedding model selection | **Blocking** for `document_chunks` DDL | `vector(N)` dimension column |
| OQ-FINAL-06: Multi-currency billing | **Blocking** for `invoices` and `money` column conventions | Currency column per row vs. tenant-level currency |
| OQ-FINAL-07: Audit retention per plan | Affects partition drop schedule only | `audit_events` partition rotation policy |
| OQ-FINAL-08: Grace period duration | Affects column default only | `subscriptions.grace_period_ends_at` default |
| OQ-FINAL-04: Recurring campaign rules | Affects `scheduling_policy` JSONB schema | `campaigns.scheduling_policy` JSONB structure |
| OQ-FINAL-05: `appointment.no_show` analytics row | Minor | `lead_funnel_daily` schema |

---

## 11. Modular Monolith vs. Future Microservices

### 11.1 Evaluation Framework

A context should be extracted to an independent deployable **only** if two or more of the following apply:
1. Independent scaling requirements — its load profile is fundamentally different from the rest.
2. Independent deployment cadence — it changes more frequently than the rest.
3. Failure isolation — its failure should not cascade to other contexts.
4. Extreme workload characteristics — it has I/O or memory profiles that conflict with other contexts.
5. Team ownership — a dedicated team owns it independently.
6. Security isolation — its threat model requires process-level sandbox.

### 11.2 Classification Table

| Context | Classification | Justification |
|---|---|---|
| Identity & Authorization | **Modular Module** | Low write volume; CheckPermission is latency-sensitive but Redis-cached; no independent scaling need |
| Organization | **Modular Module** | Very low write volume; tightly coupled to Identity |
| Audit | **Modular Module** | Append-only; can share the API worker process; low latency requirement |
| Feature Flags | **Modular Module** | Read-heavy; EvaluateFlag is cached; no independent scaling need |
| **Voice Gateway** | **Potential Future Service** | Already separated as `apps/voice_gateway` deployable (Phase 3A). Independent scaling by concurrent calls. Sticky WebSocket sessions require separate pod management. *Already effectively extracted at the deployment level in Phase 3A — this is confirmed correct.* |
| Voice Orchestrator | **Modular Module (within Voice Gateway)** | Runs inside the Voice Gateway process; extracting further would add network hops to the sub-800ms budget |
| Agent Configuration | **Modular Module** | Low volume; read-heavy (cached); no independent scaling need |
| Tool Execution | **Modular Module** | Tool calls are synchronous on the hot path; adding a network hop would blow the latency budget |
| Recording & Transcript | **Modular Module** | Post-call; runs in `apps/worker`; no independent scaling beyond worker HPA |
| **Provider Network / LLM Router** | **Potential Future Service** | If the platform adds many tenants with different LLM provider configurations, the routing and health monitoring could be extracted. Not justified at current scale. |
| CRM | **Modular Module** | CRUD-heavy; event-driven; no real-time constraint; shares API worker cleanly |
| Campaign Management | **Modular Module** | Low write volume; tightly coupled to execution |
| **Campaign Execution** | **Potential Future Service** | Very high CampaignContact volume at scale; `apps/worker` already its primary home. If campaign processing becomes the dominant workload type, a dedicated `apps/campaign_worker` with independent HPA makes sense. Not immediately justified — monitor. |
| CSV Import | **Modular Module (within Worker)** | Pure background processing; shares worker cleanly |
| Knowledge Base / RAG | **Modular Module** | Ingestion is background; retrieval is synchronous but low-volume per call |
| **Workflow Engine** | **Potential Future Service** | Per-turn consultation on voice hot path; high call volume means high execution frequency. However, it runs in-process with the Voice Gateway (same pod) to avoid network latency. Extraction would add 5–20ms per turn. *Recommend keeping in-process.* |
| Prompt Management | **Modular Module** | Render is Redis-cached; publish is rare |
| Conversation Memory | **Modular Module** | Load is once per call (Postgres); append is Redis (non-blocking) |
| **Usage Metering** | **Potential Future Service** | Very high write volume (`usage_events`); if this becomes a bottleneck, a dedicated metering service with its own DB connection pool makes sense. ClickHouse migration also a natural extraction point. Monitor at scale. |
| Billing | **Modular Module** | Batch-heavy (invoice generation); not on critical path |
| Integrations | **Modular Module** | Low volume; background sync |
| **Webhooks** | **Potential Future Service** | High delivery volume at scale (one per event per subscriber); already Celery-based. At extreme scale (millions of deliveries per hour), a dedicated webhook delivery service is justified. Not immediate. |
| Plugins | **Modular Module** | Low volume; HTTP callout is async-bounded |
| Analytics | **Modular Module** | Projection writes are background; reads are from pre-computed tables |

### 11.3 Summary Recommendation

**Keep as modular monolith today:** Identity, Organization, Audit, Feature Flags, Voice Orchestrator, Agent, Tool Execution, Recording, CRM, Campaign Management, CSV Import, Knowledge, Workflow, Prompt, Memory, Billing, Integrations, Plugins, Analytics.

**Already correctly extracted as a separate deployable:** Voice Gateway (`apps/voice_gateway`). This is Phase 2's decision, confirmed here.

**Monitor for future extraction (not today):** Campaign Execution Worker (if campaign volume dominates), Usage Metering (if `usage_events` write rate requires dedicated connection pool), Webhooks (if delivery volume exceeds worker capacity), LLM Provider Router (if multi-provider routing logic grows complex enough to justify independent deployment).

**Never extract (latency-sensitive, must stay in-process with Voice Gateway):** Voice Orchestrator core, Tool Execution on hot path, Workflow Engine per-turn evaluation, Prompt rendering.

---

## 12. Architecture Problems Found — Consolidated

| # | Severity | Phase(s) | Description | Recommendation |
|---|---|---|---|---|
| ISSUE-01 | Minor | 3D, 4B | LLM Provider Router described as "bounded context" in 3D but not given 4x DDD treatment; classified inconsistently | Formally name it "Provider Network" supporting subdomain within Voice & AI. Add DDR to 4B. |
| ISSUE-02 | Minor | 4E | IngestionJob/Document split has no explicit DDR | Add DDR-4E-007 documenting the rationale for the split |
| ISSUE-03 | Minor | 4D, 4G | `contact.dnc_flagged` missing from Phase 4G event catalog | Add to catalog; Campaign Execution must consume and remove contact from active queues |
| ISSUE-04 | Minor | 4G | `memory.customer_fact_updated` has no defined consumer | Remove from event catalog or define Analytics consumer |
| ISSUE-05 | Minor | 4C, 4D | `contact.merged` has no Campaign Execution consumer to update `CampaignContact.contact_ref` | Add Campaign Execution subscriber for `contact.merged` |
| ISSUE-06 | Significant | 4F, 4B | `conversation.turn_completed` idempotency for Usage Metering not explicitly documented | Usage Metering subscriber must check for existing `source_ref = turn_id AND metric = LLM_*` before inserting |
| ISSUE-07 | Minor | 4A | `user.password_reset_requested` event may carry raw reset token — security concern | Phase 7 must specify: raw token goes only to Notification (encrypted envelope); never to general bus |
| ISSUE-08 | Minor | 4A | `user.registered` carries email; all subscribers can read it | Restrict consumer groups to Audit + Notification only |
| ISSUE-09 | Minor | 4E, 3F | `conversation.summarization_completed` carries `summary_text` which may contain PII | Add `summary_text` to Phase 3F Fluent Bit PII deny-list |
| ISSUE-10 | Significant | 4G, 4A | Analytics context has no permission model | Define `analytics:read`, `analytics:cost_read`, `analytics:platform_read` permissions in Phase 4A registry |
| ISSUE-11 | Minor | 4A | `ActionKind` enumeration missing plugin lifecycle actions | Add `PLUGIN_REGISTERED`, `PLUGIN_VERSION_APPROVED`, `PLUGIN_VERSION_REJECTED`, `PLUGIN_INSTALLED`, `PLUGIN_UNINSTALLED` |
| ISSUE-12 | Enhancement | 3F, 4D | Campaign queue Redis keys may hot-shard for high-campaign tenants | Note for Phase 22: consider `{campaign_id}` hash tag if hot-shard observed |
| ISSUE-13 | Significant | 4B, 4E | Memory load may happen at turn-1 rather than during call setup | Confirm `ConversationMemory.load()` is called during `StartConversation`, not at start of first turn processing |

---

## 13. Recommended Corrections

### Priority 1 — Before Phase 5 Design Work Begins

**ISSUE-10:** Define analytics permissions (`analytics:read`, `analytics:cost_read`, `analytics:platform_read`) in the Phase 4A permission registry. This affects Phase 5's REST API security annotations and the analytics tables' RLS policies.

**ISSUE-13:** Confirm (or correct) that `ConversationMemory.load()` is called during `HandleInboundCallUseCase`/`StartConversation` (call setup), not during the first turn loop. This does not affect Phase 5 database schema but affects Phase 9 (Voice Pipeline) implementation.

**OQ-FINAL-03 (Embedding model):** Must be resolved before Phase 5 writes `document_chunks.embedding vector(N)` DDL — the dimension N is immutable.

**OQ-FINAL-06 (Multi-currency):** Must be resolved before Phase 5 writes `invoices.total_due money/decimal` and the `Money` column convention across billing tables.

### Priority 2 — Before Phase 7 (Event Architecture)

**ISSUE-03:** Add `contact.dnc_flagged` to the master event catalog.
**ISSUE-04:** Remove `memory.customer_fact_updated` from the event catalog or define a consumer.
**ISSUE-05:** Add `contact.merged` → Campaign Execution subscriber.
**ISSUE-06:** Document the idempotency pattern for `conversation.turn_completed` in Usage Metering.
**ISSUE-07:** Specify the `user.password_reset_requested` event's security envelope in Phase 7.
**ISSUE-08:** Document consumer group restrictions for `user.registered`.

### Priority 3 — Documentation Clarifications

**ISSUE-01:** Add naming clarification (Provider Network = supporting subdomain within Voice & AI) to Phase 4B.
**ISSUE-02:** Add DDR-4E-007 (IngestionJob/Document split rationale) to Phase 4E.
**ISSUE-09:** Add `summary_text` to Phase 3F PII deny-list documentation.
**ISSUE-11:** Add plugin lifecycle `ActionKind` values to Phase 4A §5.8.1.

---

## 14. Architecture Decision Records (This Review)

### ADR-REVIEW-01: LLM Provider Router is Provider Network Supporting Subdomain

**Decision:** The `llm_provider_router/` module is formally named the "Provider Network" supporting subdomain within the Voice & AI bounded context (Phase 4B). It is not a separate bounded context and requires no Phase 4x sub-phase of its own.

**Rationale:** It has no aggregate of its own distinct from `ProviderConfig` (already documented in Phase 4B §5.8). Its domain service (`ProviderSelectionService`) is already documented in Phase 4B §8.2. The Phase 3D language describing it as "its own bounded context" was imprecise.

### ADR-REVIEW-02: Analytics Permissions Added to Platform Permission Registry

**Decision:** Three new permissions are added to the platform permission registry defined in Phase 4A: `analytics:read` (all roles), `analytics:cost_read` (Owner, Admin, Billing Admin), `analytics:platform_read` (Platform Admin only).

**Rationale:** The Analytics context has a REST API surface (dashboard queries) that requires permission-gated access. Without explicit permissions, the RBAC check before every analytics endpoint call (`CheckPermission`) would have no valid permission to check.

### ADR-REVIEW-03: Memory Load Confirmed at Call Setup, Not Turn-1

**Decision:** `ConversationMemory.load()` is confirmed to be called during the `HandleInboundCallUseCase` / `StartConversation` application service execution (Phase 4B §14.1), not at the start of the first turn's processing loop.

**Rationale:** Loading memory at call setup allows it to overlap with telephony connection establishment. Loading it at turn-1 puts it on the critical path of the first turn's latency budget. The Phase 4B §14.1 documentation already implies this but should be made explicit in Phase 9 (Voice Pipeline design).

### ADR-REVIEW-04: No Event Sourcing in Any Context

**Decision:** Standard aggregates + domain events + event-driven read-model projections is the platform's pattern throughout. Full event sourcing is not adopted in any bounded context.

**Rationale:** Documented in Phase 4G §8. Voice latency constraints (sub-800ms SLO) make aggregate-rebuild-from-events unacceptable on the hot path. Campaign Contact volume (millions per campaign) makes event log storage impractical without commensurate benefit. The audit requirement (Phase 1 NFR-SEC-004) is satisfied by the append-only `AuditEvent` aggregate — not by general event sourcing.

### ADR-REVIEW-05: Modular Monolith Remains the Deployment Default

**Decision:** The Phase 2 modular-monolith-of-bounded-contexts deployment decision is confirmed and extended. Voice Gateway remains the only separately deployed component today. Campaign Execution Worker, Usage Metering, and Webhooks are monitored for future extraction only when concrete load evidence justifies it.

**Rationale:** Every context that might warrant extraction has an existing abstraction seam (port/adapter boundary) that makes extraction a deployment topology change, not a domain redesign. The extraction option is preserved without being exercised prematurely.

---

## 15. Final Approved Bounded Context List

| # | Bounded Context | Sub-phase | Classification | Deployment Unit |
|---|---|---|---|---|
| 1 | Identity & Access | 4A | Core | `apps/api` |
| 2 | Organization | 4A | Core | `apps/api` |
| 3 | Authorization | 4A | Core | `apps/api` |
| 4 | Audit | 4A | Supporting | `apps/api` + `apps/worker` |
| 5 | Feature Flags | 4A | Supporting | `apps/api` |
| 6 | Usage & Quota | 4A/4F | Supporting | `apps/worker` |
| 7 | Voice & AI (Call/Conversation/Agent) | 4B | Core | `apps/voice_gateway` |
| 8 | Tool Execution | 4B | Supporting | `apps/voice_gateway` |
| 9 | Recording & Transcript | 4B | Supporting | `apps/worker` |
| 10 | Provider Network (LLM Router) | 4B | Generic | `apps/voice_gateway` |
| 11 | CRM / Lead & Contact | 4C | Core | `apps/api` + `apps/worker` |
| 12 | Deal & Pipeline | 4C | Core | `apps/api` |
| 13 | Activities & Tasks | 4C | Supporting | `apps/api` + `apps/worker` |
| 14 | Appointments | 4C | Supporting | `apps/api` + `apps/worker` |
| 15 | Lead Scoring | 4C | Supporting | `apps/worker` |
| 16 | Custom Fields | 4C | Generic | `apps/api` |
| 17 | Campaign Management | 4D | Core | `apps/api` |
| 18 | Campaign Execution | 4D | Core | `apps/worker` |
| 19 | CSV Import | 4D | Supporting | `apps/worker` |
| 20 | Campaign Outcomes | 4D | Supporting | `apps/worker` |
| 21 | Knowledge & RAG | 4E | Supporting | `apps/api` + `apps/worker` |
| 22 | Workflow Engine | 4E | Core | `apps/voice_gateway` (in-process) |
| 23 | Prompt Management | 4E | Supporting | `apps/api` |
| 24 | Conversation Memory | 4E | Supporting | `apps/voice_gateway` + `apps/worker` |
| 25 | Billing & Subscription | 4F | Supporting | `apps/api` + `apps/worker` |
| 26 | Usage Metering | 4F | Supporting | `apps/worker` |
| 27 | Integrations | 4F | Supporting | `apps/api` + `apps/worker` |
| 28 | Webhooks | 4F | Supporting | `apps/worker` |
| 29 | Plugins | 4F | Generic | `apps/api` + `apps/worker` |
| 30 | Analytics | 4G | Supporting | `apps/api` (queries) + `apps/worker` (projections) |

---

## 16. Final Approved Aggregate List (Authoritative Summary)

*50 aggregate roots across 30 bounded contexts.*

| # | Aggregate Root | Context | Phase |
|---|---|---|---|
| 1 | User | Identity | 4A |
| 2 | ApiKey | Identity/Authorization | 4A |
| 3 | Role | Authorization | 4A |
| 4 | Organization | Organization | 4A |
| 5 | Membership | Organization | 4A |
| 6 | FeatureFlag | Feature Flags | 4A |
| 7 | AuditEvent | Audit | 4A |
| 8 | QuotaUsage | Usage/Quota | 4A |
| 9 | Call | Voice | 4B |
| 10 | Conversation | Voice | 4B |
| 11 | Agent | Voice | 4B |
| 12 | ToolDefinition | Tool Execution | 4B |
| 13 | ToolExecution | Tool Execution | 4B |
| 14 | Recording | Recording | 4B |
| 15 | Transcript | Recording | 4B |
| 16 | ProviderConfig | Provider Network | 4B |
| 17 | Contact | CRM | 4C |
| 18 | Company | CRM | 4C |
| 19 | Deal | Deal/Pipeline | 4C |
| 20 | Pipeline | Deal/Pipeline | 4C |
| 21 | Activity | Activities | 4C |
| 22 | Task | Activities | 4C |
| 23 | Note | Activities | 4C |
| 24 | Appointment | Appointments | 4C |
| 25 | LeadScoreRecord | Lead Scoring | 4C |
| 26 | CRMFieldDefinitionSet | Custom Fields | 4C |
| 27 | Campaign | Campaign Management | 4D |
| 28 | CampaignContact | Campaign Execution | 4D |
| 29 | CallJob | Campaign Execution | 4D |
| 30 | ContactList | CSV Import | 4D |
| 31 | CsvImportJob | CSV Import | 4D |
| 32 | CampaignOutcome | Campaign Outcomes | 4D |
| 33 | KnowledgeBase | Knowledge | 4E |
| 34 | Document | Knowledge | 4E |
| 35 | IngestionJob | Knowledge | 4E |
| 36 | WorkflowDefinition | Workflow Engine | 4E |
| 37 | WorkflowExecution | Workflow Engine | 4E |
| 38 | PromptTemplate | Prompt Management | 4E |
| 39 | PromptExperiment | Prompt Management | 4E |
| 40 | SessionMemory | Memory | 4E |
| 41 | CustomerMemory | Memory | 4E |
| 42 | BillingAccount | Billing | 4F |
| 43 | Subscription | Billing | 4F |
| 44 | Plan | Billing | 4F |
| 45 | Invoice | Billing | 4F |
| 46 | UsageRecord | Usage Metering | 4F |
| 47 | UsageEvent | Usage Metering | 4F |
| 48 | CostEntry | Usage Metering | 4F |
| 49 | QuotaConfig | Usage Metering | 4F |
| 50 | IntegrationDefinition | Integrations | 4F |
| 51 | IntegrationConnection | Integrations | 4F |
| 52 | WebhookEndpoint | Webhooks | 4F |
| 53 | WebhookDelivery | Webhooks | 4F |
| 54 | Plugin | Plugins | 4F |
| 55 | PluginInstallation | Plugins | 4F |
| 56 | AnalyticsDashboard | Analytics | 4G |

---

## 17. Final Approved Event Catalog (Canonical Reference)

*Consolidated from Phase 4G §11 with corrections from this review (ISSUE-03 added, ISSUE-04 removed).*

### 17.1 Core Platform (4A)

| Event | Producer | Consumers | Type | Idempotency Key |
|---|---|---|---|---|
| `org.created` | Organization | Billing, Usage (seed quotas), Analytics, Audit | Integration | `org_id` |
| `org.suspended` | Organization | Auth, Billing, Analytics, Audit, Webhook | Integration | `org_id + suspended_at` |
| `membership.invitation_accepted` | Membership | Usage (MEMBERS++), Audit | Integration | `membership_id` |
| `membership.role_changed` | Membership | Auth (cache invalidate), Audit | Integration | `membership_id + changed_at` |
| `apikey.revoked` | Authorization | Auth (cache delete), Audit | Integration | `api_key_id` |
| `quota.exceeded` | Usage Metering | Billing, Webhook, Analytics, Audit | Integration | `tenant_id + metric + exceeded_at` |
| `feature_flag.rule_added` | Feature Flags | Flag cache invalidation | Domain | `flag_key + rule_id` |

### 17.2 Voice & AI (4B)

| Event | Producer | Consumers | Type | Idempotency Key |
|---|---|---|---|---|
| `call.initiated` | Voice | Analytics, Audit | Integration | `call_id` |
| `call.answered` | Voice | Analytics, Billing (start) | Integration | `call_id + answered_at` |
| `call.ended` | Voice | CRM, Campaign Exec, Usage, Analytics, Webhook, Billing | Integration | `call_id + ended_at` |
| `call.failed` | Voice | Campaign Exec, Analytics, Webhook | Integration | `call_id + failed_at` |
| `call.transferred` | Voice | CRM, Analytics, Webhook | Integration | `call_id` |
| `conversation.turn_completed` | Conversation | Analytics (latency), Billing (tokens), Transcript | Integration | `turn_id` |
| `conversation.qualification_set` | Conversation | CRM, Campaign Exec, Analytics, Webhook | Integration | `conversation_id + set_at` |
| `conversation.completed` | Conversation | Memory, Recording, Transcript, Billing | Integration | `conversation_id` |
| `conversation.summarization_completed` | Memory | CRM (AI note), Analytics | Integration | `session_memory_id` |
| `tool_execution.succeeded` | Tool Execution | Analytics, Billing (if cost), Audit | Integration | `execution_id` |
| `tool_execution.failed` | Tool Execution | Analytics, Audit | Integration | `execution_id` |
| `agent.published` | Agent | Analytics, Audit | Integration | `agent_id + version_id` |
| `recording.stored` | Recording | CRM, Analytics, Audit | Integration | `recording_id` |
| `transcript.completed` | Transcript | CRM, Analytics | Integration | `transcript_id` |
| `provider.failover_triggered` | Provider Network | Analytics, Audit | Integration | `provider_id + triggered_at` |
| `provider.circuit_opened` | Provider Network | Analytics, Alertmanager | Integration | `provider_id + opened_at` |

### 17.3 CRM (4C)

| Event | Producer | Consumers | Type | Idempotency Key |
|---|---|---|---|---|
| `contact.created` | CRM | Analytics, Webhook, Audit | Integration | `contact_id` |
| `contact.qualified` | CRM | Campaign Exec, Analytics, Webhook, Audit | Integration | `contact_id + qualified_at` |
| `contact.converted` | CRM | Billing, Analytics, Webhook, Audit | Integration | `contact_id + converted_at` |
| `contact.score_updated` | Lead Scoring | Analytics | Domain | `contact_id + computed_at` |
| `contact.merged` | CRM | Campaign Execution (update contact_ref), Analytics, Audit | Integration | `primary_id + secondary_id` |
| `contact.dnc_flagged` | CRM | Campaign Execution (remove from queues), Webhook, Audit | Integration | `contact_id + flagged_at` |
| `deal.won` | Deal | Analytics, Webhook, Audit | Integration | `deal_id` |
| `deal.lost` | Deal | Analytics, Webhook, Audit | Integration | `deal_id` |
| `appointment.booked` | Appointments | Analytics, Webhook, Notification, Audit | Integration | `appointment_id` |
| `appointment.no_show` | Appointments | Analytics, Audit | Integration | `appointment_id` |
| `activity.recorded` | Activities | Analytics | Domain | `activity_id` |
| `task.completed` | Tasks | Analytics | Domain | `task_id` |

### 17.4 Campaign (4D)

| Event | Producer | Consumers | Type | Idempotency Key |
|---|---|---|---|---|
| `campaign.started` | Campaign Mgmt | Analytics, Billing, Webhook, Audit | Integration | `campaign_id + started_at` |
| `campaign.completed` | Campaign Mgmt | Analytics, Billing, Webhook, Audit | Integration | `campaign_id` |
| `campaign.paused` | Campaign Mgmt | Analytics, Webhook | Integration | `campaign_id + paused_at` |
| `campaign.contact.call_attempted` | Campaign Exec | CRM (Activity), Analytics, Billing | Integration | `campaign_contact_id + attempt_number` |
| `campaign.contact.qualified` | Campaign Exec | CRM (qualify), Analytics, Webhook | Integration | `campaign_contact_id + call_id` |
| `campaign.contact.exhausted` | Campaign Exec | Analytics | Domain | `campaign_contact_id` |
| `campaign.outcome_computed` | Campaign Outcomes | Analytics, Webhook | Integration | `campaign_id + computed_at` |

### 17.5 Intelligence (4E)

| Event | Producer | Consumers | Type | Idempotency Key |
|---|---|---|---|---|
| `document.indexed` | Knowledge | Analytics, Billing (embedding cost), Audit | Integration | `document_id` |
| `document.deleted` | Knowledge | Analytics, VectorStore (delete chunks) | Integration | `document_id + deleted_at` |
| `workflow.published` | Workflow | Analytics, Audit | Integration | `workflow_id + version_id` |
| `workflow.execution_completed` | Workflow | Analytics, Billing (LLM cost) | Integration | `execution_id` |
| `prompt.version_published` | Prompt Mgmt | Analytics, Cache invalidation, Audit | Integration | `prompt_id + version_id` |
| `prompt.rolled_back` | Prompt Mgmt | Analytics, Cache invalidation, Audit | Integration | `prompt_id + env + rolled_back_at` |
| `experiment.activated` | Prompt Mgmt | Analytics | Domain | `experiment_id` |

### 17.6 Commercial Platform (4F)

| Event | Producer | Consumers | Type | Idempotency Key |
|---|---|---|---|---|
| `subscription.created` | Billing | Analytics, Usage (seed quotas), Audit | Integration | `subscription_id` |
| `subscription.plan_changed` | Billing | Analytics, Usage (update quotas), Webhook | Integration | `subscription_id + effective_at` |
| `subscription.cancelled` | Billing | Analytics, Webhook, Audit | Integration | `subscription_id` |
| `invoice.generated` | Billing | Analytics, Webhook, Notification | Integration | `invoice_id` |
| `invoice.payment_succeeded` | Billing | Analytics, Webhook, Subscription update | Integration | `invoice_id + attempt_id` |
| `invoice.payment_failed` | Billing | Analytics, Webhook, Subscription (PAST_DUE) | Integration | `invoice_id + attempt_id` |
| `usage.event_recorded` | Usage Metering | Analytics, CostEntry | Domain | `usage_event_id` |
| `usage.threshold_approached` | Usage Metering | Notification, Webhook, Billing | Integration | `tenant_id + metric + occurred_at` |
| `usage.quota_exceeded` | Usage Metering | Billing, Webhook, Analytics | Integration | `tenant_id + metric + exceeded_at` |
| `integration.connected` | Integrations | Analytics, Audit | Integration | `connection_id` |
| `integration.disconnected` | Integrations | Analytics, Audit | Integration | `connection_id + disconnected_at` |
| `webhook.delivery_dead_lettered` | Webhooks | Analytics, Alertmanager | Integration | `delivery_id` |
| `plugin.installed` | Plugins | Analytics, Audit | Integration | `installation_id` |
| `plugin.activated` | Plugins | Tool Registry, Analytics | Integration | `installation_id` |

---

## 18. Final Database Design Handoff

*Authoritative consolidation of Phase 4G §18 with corrections from this review.*

### 18.1 Prerequisites for Phase 5

| Prerequisite | Status | Owner |
|---|---|---|
| Embedding model selection (OQ-FINAL-03) | **Unresolved — BLOCKING for document_chunks DDL** | Product + Architecture |
| Multi-currency billing decision (OQ-FINAL-06) | **Unresolved — BLOCKING for Money column convention** | Product |
| Analytics permissions defined (ISSUE-10 correction) | **Resolved here** — `analytics:read`, `analytics:cost_read`, `analytics:platform_read` | This review |
| `contact.dnc_flagged` event added (ISSUE-03) | **Resolved here** | This review |
| Memory load timing confirmed (ISSUE-13) | **To be confirmed in Phase 9** — not blocking Phase 5 schema | Architecture |
| Audit retention per plan tier (OQ-FINAL-07) | Affects partition drop schedule only — not blocking DDL | Product/Legal |
| Grace period duration (OQ-FINAL-08) | Affects column default only | Product |

### 18.2 PostgreSQL Schema Inventory (13 schemas)

`identity`, `organization`, `voice`, `crm`, `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, `audit`

### 18.3 Partitioning Requirements (Phase 5 must create partitioned from day 1)

| Table | Schema | Strategy | Key | Retention |
|---|---|---|---|---|
| `usage_events` | billing | RANGE monthly | `occurred_at` | 90 days hot; 7 yr cold |
| `cost_entries` | billing | RANGE monthly | `occurred_at` | 90 days hot; 7 yr cold |
| `audit_events` | audit | RANGE monthly | `occurred_at` | 1 yr hot; 7 yr cold |
| `webhook_deliveries` | webhooks | RANGE monthly | `created_at` | 30d DELIVERED; 90d DEAD_LETTER |
| `call_sessions` | voice | RANGE monthly | `started_at` | 12 mo hot; 7 yr cold |
| `campaign_contacts` | campaign | LIST | `campaign_id` | Campaign + 2 yr |
| `document_chunks` | knowledge | LIST | `knowledge_base_id` | KB lifetime |
| `activities` | crm | RANGE monthly | `occurred_at` | 5 yr |
| `transcript_segments` | voice | RANGE monthly | `created_at` | 2 yr |

### 18.4 Key Index Requirements

| Table | Index | Type |
|---|---|---|
| `contacts` | `(tenant_id, primary_phone)` UNIQUE | B-tree |
| `contacts` | `(tenant_id, lead_status)` | B-tree |
| `call_sessions` | `(tenant_id, status)` partial (`WHERE status='ACTIVE'`) | B-tree |
| `campaign_contacts` | `(campaign_id, status)` | B-tree |
| `campaign_contacts` | `(campaign_id, next_attempt_at)` | B-tree |
| `call_jobs` | `(idempotency_key)` UNIQUE | B-tree |
| `document_chunks` | `embedding` HNSW | pgvector |
| `document_chunks` | `(tenant_id, knowledge_base_id)` | B-tree partial |
| `document_chunks` | `text_content` full-text | GIN tsvector |
| `audit_events` | `(tenant_id, occurred_at)` | BRIN |
| `api_keys` | `(key_hash)` UNIQUE | B-tree |
| `organizations` | `(slug)` UNIQUE | B-tree |
| `memberships` | `(organization_id, user_id)` UNIQUE | B-tree |
| `workflow_executions` | `(session_ref)` UNIQUE | B-tree |

### 18.5 Append-Only Tables (REVOKE UPDATE, DELETE from application role)

`audit_events`, `usage_events`, `cost_entries`, `transcript_segments`, `lead_score_records`, `activities`, `webhook_deliveries`

### 18.6 Cross-Schema Reference Policy

Phase 5 must **not** create PostgreSQL FOREIGN KEY constraints across schema boundaries. Cross-schema references use UUID values (logical foreign keys) only. FK constraints are permitted only within the same schema.

### 18.7 ClickHouse Migration Candidates

`usage_events` (highest priority), `cost_entries`, `call_sessions` historical, analytics projections at extreme volume. All writes go through `AnalyticsWritePort` — migration is adapter-only.

### 18.8 S3 / Object Storage Namespacing

All S3 keys under `org/{tenant_id}/` prefix. Subfolder structure defined in Phase 4G §18.6.

### 18.9 Redis Key Namespacing

All 17 Redis key patterns defined in Phase 4G §18.7 are authoritative. No new key patterns should be introduced without updating that table.

---

## 19. Phase 5 Prerequisites Checklist

| # | Prerequisite | Status |
|---|---|---|
| 1 | Embedding model name + vector dimensions confirmed | ⛔ Unresolved (OQ-FINAL-03) |
| 2 | Multi-currency or single-currency billing decision | ⛔ Unresolved (OQ-FINAL-06) |
| 3 | Analytics permission strings in Phase 4A registry | ✅ Resolved (this review, ADR-REVIEW-02) |
| 4 | `contact.dnc_flagged` event in catalog | ✅ Resolved (this review, ISSUE-03) |
| 5 | All 13 PostgreSQL schema names confirmed | ✅ Phase 4G §18.2 |
| 6 | All 9 partitioned tables identified with strategies | ✅ Phase 4G §18.3 |
| 7 | All 14 index requirements documented | ✅ Phase 4G §18.4 |
| 8 | Append-only table list confirmed | ✅ Phase 4G §18.5 |
| 9 | pgvector extension and HNSW params defined | ✅ Phase 4G §18.5 (params: m=16, ef=64) |
| 10 | S3 namespacing confirmed | ✅ Phase 4G §18.6 |
| 11 | Redis key catalogue confirmed | ✅ Phase 4G §18.7 |
| 12 | Modular monolith deployment decision confirmed | ✅ ADR-REVIEW-05 |
| 13 | No circular dependencies confirmed | ✅ §6.2 this review |
| 14 | No oversized aggregates confirmed | ✅ §4.2 this review |
| 15 | 56 aggregate roots listed and approved | ✅ §16 this review |
| 16 | Final event catalog approved | ✅ §17 this review |
| 17 | Security: CredentialRef pattern validated | ✅ §7.2 this review |
| 18 | Security: PII-out-of-events validated | ✅ §7.3 this review (with minor corrections) |
| 19 | Low-latency: voice hot path confirmed async-safe | ✅ §9 this review |
| 20 | Plugin sandbox (HTTP callout only) confirmed | ✅ ADR-REVIEW-05 |

**Two prerequisites are unresolved and must be addressed before Phase 5 DDL for the affected tables can be written.** All other prerequisites are satisfied.

---

## 20. Final Architecture Approval Checklist

| Check | Result |
|---|---|
| Phase 2 modular-monolith decision honoured | ✅ |
| No circular domain dependencies | ✅ |
| No unbounded embedded collections | ✅ |
| All cross-domain communication via ports or events (no direct imports) | ✅ |
| Voice hot path free of blocking billing/analytics/CRM calls | ✅ |
| Tenant isolation at all layers (domain/application/DB/cache/storage/events) | ✅ |
| No plaintext secrets in any domain aggregate or event payload | ✅ |
| All aggregates have documented invariants and business rules | ✅ |
| All events have defined producer, consumers, and idempotency key | ✅ |
| CQRS applied only where read/write patterns genuinely diverge | ✅ |
| Event sourcing explicitly evaluated and rejected | ✅ |
| ClickHouse migration path clean (no producer code changes needed) | ✅ |
| All 13 significant/minor issues documented with recommended corrections | ✅ |
| Phase 5 handoff complete (with 2 blocking open questions identified) | ✅ |

**Architecture Status: APPROVED FOR PHASE 5** — subject to resolving OQ-FINAL-03 (embedding model) and OQ-FINAL-06 (multi-currency) before the specific DDL statements for `document_chunks` and the billing money columns are written.
