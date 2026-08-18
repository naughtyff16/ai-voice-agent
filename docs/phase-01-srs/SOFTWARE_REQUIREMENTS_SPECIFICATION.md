# AI Voice Agent Platform
## Phase 1 — Software Requirements Specification (SRS)

# PART A — SOFTWARE REQUIREMENTS SPECIFICATION

## 1. Introduction

### 1.1 Purpose
This SRS defines the functional and non-functional requirements for a multi-tenant, enterprise-grade AI Voice Agent platform. It is the contract between product intent (`PRODUCT_VISION.md`) and everything that gets built afterward. Every later phase (LLD, DDD, DB design, API design, implementation) must trace back to a requirement ID defined here.

### 1.2 Scope
The platform enables organizations to configure, deploy, and operate AI voice agents that place and receive real phone calls, execute business workflows, integrate with CRM/ERP systems, run outbound campaigns, retrieve knowledge via RAG, call tools/functions, and report on cost, quality, and revenue outcomes — across telephony, STT, TTS, and LLM providers that are swappable per organization.

Out of scope for this document: pricing/packaging strategy, exact UI mockups, and provider contractual terms.

### 1.3 Definitions, Acronyms, Abbreviations

| Term | Meaning |
|---|---|
| Org / Tenant | An isolated customer account on the platform |
| Agent | A configured AI persona (prompt + voice + tools + workflow) that handles calls |
| Session | One live phone call from ring to hangup |
| Turn | One exchange (customer speaks → agent responds) within a session |
| STT / TTS | Speech-to-Text / Text-to-Speech |
| RAG | Retrieval-Augmented Generation (knowledge base search feeding the LLM) |
| Workflow | A JSON-defined graph of nodes (decision, prompt, tool, transfer, etc.) an agent executes during a call |
| Tool | A callable function the LLM can invoke (e.g., `bookAppointment`) |
| Model Router | Component that selects an LLM provider/model per request |
| DDD / EDA | Domain-Driven Design / Event-Driven Architecture |
| RBAC | Role-Based Access Control |

### 1.4 References
`PRODUCT_VISION.md` (goals, success metrics), `ARCHITECTURE_PRINCIPLES.md` (mandated architecture style), `TECH_STACK.md` (approved technologies), `CODING_STANDARDS.md`, `PROJECT_ROADMAP.md` (phase gating), `PROMPT_GUIDELINES.md` (documentation/coding discipline).

### 1.5 Document Conventions
Functional requirements are coded `FR-<MODULE>-<NNN>`. Non-functional requirements are coded `NFR-<CATEGORY>-<NNN>`. Priority: **P0** (must-have for MVP-of-the-enterprise-platform, i.e. cannot ship without it), **P1** (required within first two release trains), **P2** (roadmap, not blocking).

---

## 2. Overall Description

### 2.1 Product Perspective
This is a new, provider-agnostic, cloud-native SaaS platform — not an extension of an existing system. It sits between (a) telephony/STT/TTS/LLM vendors and (b) enterprise buyers who need programmable voice agents. Per `ARCHITECTURE_PRINCIPLES.md`, no business logic may depend directly on any vendor SDK; every external system is an adapter behind a port.

### 2.2 Product Functions (Summary)
Inbound/outbound voice AI, AI receptionist/sales/support/collections/survey/booking/follow-up/qualification agents, CRM, campaign engine, visual workflow builder, knowledge base (RAG), prompt management, conversation memory, multi-LLM orchestration, tool calling, analytics + cost analytics, billing, webhooks, plugin SDK, admin control plane.

### 2.3 User Classes and Characteristics

| User Class | Description | Key Needs |
|---|---|---|
| Platform Super Admin | Anthropic-of-the-platform staff | Cross-tenant visibility, quotas, health, billing overrides |
| Organization Admin | Buyer-side account owner | Users, billing, org-wide settings, security policy |
| Agent Builder / Prompt Engineer | Configures agents, prompts, workflows | Workflow builder, prompt versioning, testing/eval tools |
| Campaign Manager | Runs outbound campaigns | CSV upload, scheduling, pacing, outcome dashboards |
| Supervisor / QA | Monitors live and historical calls | Live listen, transcripts, sentiment, scorecards |
| Billing Admin | Manages plan, invoices, cost | Usage dashboards, cost breakdowns, invoices |
| Partner / Developer | Builds integrations | Public API, webhooks, Plugin SDK, API keys |
| End Customer (Caller) | The human on the phone | Fast, natural, low-latency conversation |
| AI Agent | System actor, not a human | Deterministic behavior bound by workflow + guardrails |

### 2.4 Operating Environment
Cloud-native, container-orchestrated (Kubernetes), horizontally scalable, multi-region-capable. Browser-based admin console (evergreen browsers). Voice legs run over telephony providers' PSTN/SIP trunks; media reaches the platform via provider streaming APIs (WebSocket/RTP-to-WS bridges depending on provider).

### 2.5 Design and Implementation Constraints
- Must use the approved stack in `TECH_STACK.md` only; any new technology requires an ADR (Architecture Decision Record).
- Must follow Clean Architecture + DDD + Hexagonal + Event-Driven Design (`ARCHITECTURE_PRINCIPLES.md`) — business logic isolated from frameworks/vendors.
- Every request must carry tenant context; isolation enforced at API, service, DB, cache, storage, and event layers.
- Application servers stateless; all state in PostgreSQL, Redis, or object storage.
- All provider integrations (telephony, STT, TTS, LLM, payments) behind abstraction ports — never invoked directly from domain logic.
- Target end-to-end voice response latency < 800ms where achievable.

### 2.6 Assumptions and Dependencies
- Telephony, STT, TTS, and LLM vendors expose streaming APIs with acceptable SLAs; the platform depends on their uptime for the voice leg even though it abstracts them.
- Supabase-hosted PostgreSQL is acceptable as primary OLTP store at current scale targets; ClickHouse is deferred until analytics volume justifies it.
- Organizations provide their own consent/compliance basis for call recording per local law; platform provides the enforcement mechanism (recording toggle, disclosure playback, retention policy) but not the legal basis itself.

---

## 3. System Features / Functional Requirements

Each module below will get its own detailed design in later phases; this section fixes *what* must exist so later phases have a stable contract to design against.

### 3.1 Multi-Tenancy & Organization Management

| ID | Requirement | Priority |
|---|---|---|
| FR-TEN-001 | System shall support unlimited organizations, each fully isolated (data, config, quotas). | P0 |
| FR-TEN-002 | Every API request, DB row, cache key, storage object, and event shall carry a `tenant_id`. | P0 |
| FR-TEN-003 | Org Admins shall manage users, roles, phone numbers, and org-level settings within their tenant only. | P0 |
| FR-TEN-004 | Platform Super Admins shall manage cross-tenant quotas, suspension, and health without accessing tenant conversation content unless explicitly authorized (break-glass, audited). | P1 |
| FR-TEN-005 | System shall support per-tenant configurable quotas (agents, numbers, concurrent calls, storage, API rate). | P1 |

### 3.2 Authentication & Authorization

| ID | Requirement | Priority |
|---|---|---|
| FR-AUTH-001 | System shall support JWT-based session auth and OAuth2 for SSO (enterprise buyers). | P0 |
| FR-AUTH-002 | System shall enforce RBAC with platform-defined roles (Super Admin, Org Admin, Builder, Campaign Manager, Supervisor, Billing Admin, Developer, Read-Only) plus custom roles. | P0 |
| FR-AUTH-003 | System shall support scoped API keys (per-org, per-environment, revocable, least-privilege). | P0 |
| FR-AUTH-004 | System shall log every authentication and authorization decision to an immutable audit trail. | P0 |
| FR-AUTH-005 | System shall support MFA for admin roles. | P1 |

### 3.3 Voice Pipeline (Inbound & Outbound)

| ID | Requirement | Priority |
|---|---|---|
| FR-VOICE-001 | System shall handle inbound calls: answer, stream audio, run agent, respond in real time. | P0 |
| FR-VOICE-002 | System shall place outbound calls individually or via campaigns. | P0 |
| FR-VOICE-003 | System shall support call transfer (warm/cold) to a human or another agent. | P0 |
| FR-VOICE-004 | System shall support voicemail detection and voicemail-drop behavior. | P1 |
| FR-VOICE-005 | System shall support hold and basic conference scenarios. | P2 |
| FR-VOICE-006 | System shall record calls (configurable per org/agent), store transcript, generate summary, sentiment, and lead score per call. | P0 |
| FR-VOICE-007 | System shall stream partial responses (barge-in capable) to keep perceived latency low. | P0 |
| FR-VOICE-008 | System shall automatically push post-call outcomes into CRM records. | P1 |

### 3.4 Telephony Provider Abstraction

| ID | Requirement | Priority |
|---|---|---|
| FR-TEL-001 | System shall support Exotel as primary provider at launch. | P0 |
| FR-TEL-002 | System shall support Twilio, Telnyx, Plivo, and generic SIP as additional providers without business-logic changes. | P1 |
| FR-TEL-003 | System shall allow per-org, per-number provider selection. | P1 |
| FR-TEL-004 | System shall support automatic provider failover for outbound calling where configured. | P2 |

### 3.5 Speech-to-Text / Text-to-Speech

| ID | Requirement | Priority |
|---|---|---|
| FR-STT-001 | System shall use Deepgram as primary STT with automatic failover to Gladia. | P0 |
| FR-TTS-001 | System shall use ElevenLabs for TTS, with Tamil-optimized voice support, streaming synthesis, multiple voices, and emotion control. | P0 |
| FR-TTS-002 | System shall support voice cloning per organization/agent where the provider allows it. | P2 |

### 3.6 LLM Orchestration & Model Router

| ID | Requirement | Priority |
|---|---|---|
| FR-LLM-001 | System shall let each org choose an LLM provider per agent (OpenAI, Anthropic, Gemini, Groq, OpenRouter, DeepSeek, Ollama). | P0 |
| FR-LLM-002 | System shall implement a Model Router selecting provider/model by latency, cost, context window, and availability, with per-agent override. | P1 |
| FR-LLM-003 | System shall support automatic fallback to a secondary model on provider error/timeout. | P1 |
| FR-LLM-004 | New LLM providers shall be pluggable without changes to orchestration business logic. | P0 |

### 3.7 Tool Calling Framework

| ID | Requirement | Priority |
|---|---|---|
| FR-TOOL-001 | System shall support dynamic function/tool calling from the LLM during a live call. | P0 |
| FR-TOOL-002 | Built-in tools shall include: createLead, updateLead, bookAppointment, cancelAppointment, sendWhatsApp, sendSMS, sendEmail, transferCall, hangup, createTask, scheduleFollowup, lookupKnowledge. | P0 |
| FR-TOOL-003 | System shall provide a Custom Tool SDK for partners/developers to register new tools with schema validation. | P1 |
| FR-TOOL-004 | Tool execution shall be sandboxed, timeout-bound, and independently auditable per call. | P0 |

### 3.8 Knowledge Base (RAG)

| ID | Requirement | Priority |
|---|---|---|
| FR-RAG-001 | System shall ingest PDF, DOCX, TXT, CSV, website URLs, and FAQ pairs. | P0 |
| FR-RAG-002 | System shall chunk, embed (pgvector), and index documents per tenant/knowledge-base. | P0 |
| FR-RAG-003 | System shall support hybrid search (semantic + keyword) with metadata filtering. | P1 |
| FR-RAG-004 | System shall version knowledge bases and allow rollback. | P1 |
| FR-RAG-005 | An agent shall be able to query one or more knowledge bases mid-call via the `lookupKnowledge` tool with bounded latency. | P0 |

### 3.9 CRM

| ID | Requirement | Priority |
|---|---|---|
| FR-CRM-001 | System shall manage Contacts, Companies, Deals, Tasks, Activities, Notes, Appointments, and Pipelines. | P0 |
| FR-CRM-002 | System shall compute and store lead scores based on configurable rules/models. | P1 |
| FR-CRM-003 | System shall maintain full call history per contact. | P0 |
| FR-CRM-004 | System shall support sync with external CRMs via the Plugin SDK. | P1 |

### 3.10 Campaign Engine

| ID | Requirement | Priority |
|---|---|---|
| FR-CAMP-001 | System shall support CSV upload of leads for outbound campaigns. | P0 |
| FR-CAMP-002 | System shall support scheduling, concurrency limits, and rate limits per campaign and per org. | P0 |
| FR-CAMP-003 | System shall support automatic retries with configurable backoff for no-answer/busy/failed calls. | P0 |
| FR-CAMP-004 | System shall support pause, resume, and stop of an in-flight campaign. | P0 |
| FR-CAMP-005 | System shall report outcome tracking, ROI, and lead qualification per campaign. | P1 |

### 3.11 Workflow Builder

| ID | Requirement | Priority |
|---|---|---|
| FR-WF-001 | System shall provide a visual, no-code workflow builder producing a JSON graph. | P0 |
| FR-WF-002 | Supported node types shall include: Greeting, Decision, Prompt, LLM, Knowledge Search, Transfer Call, Book Appointment, Webhook, API Call, Delay, Condition, Branch, Human Transfer, End Call. | P0 |
| FR-WF-003 | A Workflow Execution Engine shall interpret the JSON graph deterministically at call time. | P0 |
| FR-WF-004 | Workflows shall be versioned; a live call always runs a pinned version. | P1 |

### 3.12 Prompt Management

| ID | Requirement | Priority |
|---|---|---|
| FR-PROMPT-001 | System shall support prompt templates with variables. | P0 |
| FR-PROMPT-002 | System shall version prompts and support rollback. | P0 |
| FR-PROMPT-003 | System shall support environment-scoped prompts (dev/staging/prod). | P1 |
| FR-PROMPT-004 | System shall support A/B testing and evaluation scoring of prompt variants. | P2 |

### 3.13 Conversation Memory

| ID | Requirement | Priority |
|---|---|---|
| FR-MEM-001 | System shall maintain session memory (current call) and persistent customer/organization memory (across calls). | P0 |
| FR-MEM-002 | System shall summarize and compress context to stay within model context limits. | P0 |
| FR-MEM-003 | Memory retrieval into the live prompt shall be automatic and tenant/customer-scoped. | P1 |

### 3.14 Analytics & Cost Analytics

| ID | Requirement | Priority |
|---|---|---|
| FR-AN-001 | System shall provide Executive, Operational, Campaign, Agent, and Financial dashboards. | P1 |
| FR-AN-002 | System shall track calls, latency, STT/TTS/LLM cost, telephony cost, token usage, conversions, CSAT, agent utilization, call/campaign funnels. | P0 |
| FR-AN-003 | System shall compute profit per organization and per campaign from tracked cost + revenue signals. | P1 |
| FR-AN-004 | Analytics shall be able to migrate to ClickHouse without disrupting transactional workloads (write path abstracted). | P2 |

### 3.15 Billing

| ID | Requirement | Priority |
|---|---|---|
| FR-BILL-001 | System shall meter usage (minutes, tokens, messages, storage) per org in real time. | P0 |
| FR-BILL-002 | System shall support plan-based and usage-based billing with invoicing. | P1 |
| FR-BILL-003 | System shall integrate with a payment gateway via the Plugin SDK abstraction. | P1 |

### 3.16 Webhooks & Event Architecture

| ID | Requirement | Priority |
|---|---|---|
| FR-EVT-001 | System shall emit domain events including `call.started`, `call.completed`, `call.failed`, `campaign.started`, `campaign.completed`, `lead.created`, `lead.qualified`, `appointment.booked`. | P0 |
| FR-EVT-002 | External systems shall be able to subscribe to events via configurable webhooks with retry and signature verification. | P0 |

### 3.17 Plugin SDK

| ID | Requirement | Priority |
|---|---|---|
| FR-PLUG-001 | System shall allow third parties to build CRM/ERP connectors, custom tools, payment gateways, notification providers, and knowledge providers. | P1 |
| FR-PLUG-002 | Plugins shall run under a defined permission/capability model; they never bypass tenant isolation. | P0 |

### 3.18 Feature Flags

| ID | Requirement | Priority |
|---|---|---|
| FR-FLAG-001 | System shall support feature flags scoped at organization, user, and environment level with percentage rollout. | P1 |

### 3.19 Admin Control Plane

| ID | Requirement | Priority |
|---|---|---|
| FR-ADM-001 | System shall provide tenant management, quota management, usage, billing, support tooling, logs, health, API keys, and system configuration to Platform Super Admins. | P1 |

### 3.20 Notifications

| ID | Requirement | Priority |
|---|---|---|
| FR-NOTIF-001 | System shall send WhatsApp, SMS, and Email notifications as tool actions or workflow steps, through provider abstractions. | P0 |

---

## 4. Non-Functional Requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-PERF-001 | Performance | End-to-end voice response latency (customer stops speaking → agent audio starts) shall target < 800ms p50 where provider chain allows. |
| NFR-PERF-002 | Performance | API p99 latency < 300ms for non-voice CRUD endpoints under nominal load. |
| NFR-SCALE-001 | Scalability | System shall support thousands of organizations and millions of calls over time, with tens of thousands of concurrent calls at peak. |
| NFR-SCALE-002 | Scalability | Every service shall scale horizontally; no service may rely on local/in-process memory for state. |
| NFR-AVAIL-001 | Reliability | Core voice path shall target 99.9%+ monthly availability; degraded-mode behavior (e.g., fallback TTS/LLM) preferred over hard failure mid-call. |
| NFR-AVAIL-002 | Reliability | Provider failures (telephony/STT/TTS/LLM) shall trigger automatic failover where a secondary provider is configured. |
| NFR-SEC-001 | Security | All data encrypted in transit (TLS) and at rest. |
| NFR-SEC-002 | Security | Secrets shall be stored in a secret manager, never in code or plain environment files committed to source control. |
| NFR-SEC-003 | Security | RBAC and tenant isolation enforced at API, service, database, cache, storage, and event layers. |
| NFR-SEC-004 | Security | All state-changing actions logged to an immutable, queryable audit trail. |
| NFR-SEC-005 | Security | PII shall be masked in logs and analytics by default. |
| NFR-SEC-006 | Security | System shall include prompt-injection detection/mitigation for LLM-facing inputs (knowledge base content, tool results, caller speech). |
| NFR-SEC-007 | Security | API shall enforce rate limiting per tenant/API key. |
| NFR-SEC-008 | Security | System shall follow OWASP ASVS-aligned practices across web and API layers. |
| NFR-OBS-001 | Observability | Every service shall emit structured logs, metrics, and traces (OpenTelemetry) plus audit events. |
| NFR-OBS-002 | Observability | Voice-path latency shall be broken down and observable per stage (STT, LLM, tool call, TTS, network) to diagnose regressions. |
| NFR-MAINT-001 | Maintainability | Business logic isolated from frameworks/vendors per Clean/Hexagonal Architecture; new provider integrations require adapter-only changes. |
| NFR-COMPAT-001 | Compatibility | Public APIs versioned; breaking changes require a new version, old versions supported per a published deprecation policy. |
| NFR-COMPLY-001 | Compliance | Call recording, storage, and retention shall be configurable to support regional consent/data-residency requirements. |
| NFR-USAB-001 | Usability | Admin console usable by non-technical Agent Builders to construct a working agent without writing code. |

---

## 5. External Interface Requirements

| Interface | Description |
|---|---|
| Web UI | Next.js (App Router) admin console for all human user classes; role-aware navigation. |
| Public REST/WebSocket API | Versioned (`/v1/...`), API-key authenticated, used by partners and the web UI alike (dogfooded — “API First”). |
| Realtime Voice Interface | WebSocket/streaming interface between telephony provider and the Voice Gateway; internal streaming interfaces to STT/TTS/LLM. |
| Webhook Interface | Outbound HTTPS callbacks with HMAC signature, retry with backoff, per-org subscription management. |
| Provider Adapters | Telephony, STT, TTS, LLM, Payment, Notification, and Knowledge-source adapters, each behind a stable internal port/interface. |

---

## 6. Assumptions, Risks, Open Questions (carried into Phase 2+)

| Item | Type | Notes |
|---|---|---|
| Sub-800ms latency across 3rd-party STT+LLM+TTS chain | Risk | Depends heavily on provider performance; needs a latency budget per stage (see §7.11) validated in Phase 9 (Voice Pipeline design). |
| Single Postgres as source of truth at "millions of calls" scale | Risk | Mitigated by partitioning, read replicas, and planned ClickHouse offload for analytics (Phase 19). |
| Multi-tenant LLM/tool "prompt injection" surface | Risk | Requires a dedicated guardrail layer; detailed design in Phase 8/16/17. |
| Regulatory variance (recording consent, data residency) by region | Open Question | Needs product/legal input before Phase 5 (DB design, retention fields) and Phase 22 (deployment/region strategy). |

---
