# 6A — API Architecture & Standards

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6A

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6A-API-Architecture-and-Standards.md |
| Phase | 6A (first document of Phase 6 — API Design) |
| Depends on | Phase 1 SRS, Phase 2 HLA, Phase 3 LLD (3A–3F), Phase 4 DDD (4A–4I), Phase 5 Database Design (5A–5J), Phase 5K + 5K.1 (FROZEN) |
| Status of dependencies | Phase 5 (5A–5J, 5K, 5K.1) is **APPROVED / FROZEN / PRODUCTION BASELINE READY**. No changes made to it by this document. |
| Author scope | Platform-wide API architecture and standards only. No business-domain endpoints designed. |
| Supersedes | Nothing (first Phase 6 document) |
| Governs | 6B onward — every later Phase 6 API design document must conform to this document unless an explicitly documented, approved exception is recorded here or in the governing document at the time. |
| Date | 2026-08-21 |

---

## 2. Purpose

This document establishes the single governing API architecture standard for the AI Voice Agent Platform. It defines *how* every future API is built — communication model, REST conventions, request/response pipelines, latency budgets, pagination, idempotency, concurrency, caching, rate limiting, security, tenancy, realtime, webhooks, media transfer, versioning, documentation, and testing — so that 6B onward (Auth APIs, Voice APIs, CRM APIs, Campaign APIs, Billing APIs, etc.) can be designed consistently, quickly, and without re-litigating cross-cutting decisions.

It does **not** design any endpoint. It is the constitution those endpoints must satisfy.

---

## 3. Scope

**In scope:** platform-wide API architecture, REST conventions, request/response lifecycle, performance and latency standards, pagination/filtering/search conventions, idempotency, concurrency, async job contract, caching, rate limiting, timeout/retry/circuit-breaker policy, security architecture, multi-tenant context propagation, error contract, observability, WebSocket/realtime standards, webhook standards, file/media transfer standards, versioning and backward compatibility, OpenAPI/documentation standards, contract-testing requirements, business-logic and transaction boundaries, performance anti-patterns, and traceability rules.

**Out of scope (explicitly deferred):**
- Any concrete endpoint for Auth, Voice, Agent, CRM, Campaign, Billing, Knowledge/RAG, Workflow, Integrations, Webhooks, Plugins, or Analytics (Phase 6B onward).
- FastAPI routers, Pydantic models, SQLAlchemy code, Celery tasks, WebSocket handlers, infrastructure changes.
- Any change to Phase 5 (schema, RLS policy, functions, triggers, indexes, migrations).
- API-MASTER-INDEX, API-ERROR-CATALOG, API-AUTHORIZATION-MATRIX, API-VERSIONING-STRATEGY — these are separate future artifacts once the domain APIs that populate them exist.

---

## 4. Phase 5 Frozen Baseline

Phase 5 is authoritative and closed. Per `docs/phase-05-database-design/5K/validation/FINAL_5K_VALIDATION_REPORT.md`:

> "PHASE 5K.1 PATCH COMPLETE / PHASE 5K FINAL VALIDATION COMPLETE / PHASE 5K PRODUCTION BASELINE READY / PHASE 5K APPROVED / PHASE 5K FROZEN. No Phase 5A-5J architecture was changed. No Phase 6 work, API design, or further database changes follow this closure."

Baseline facts this document treats as immovable:

| Property | Value | Source |
|---|---|---|
| Migrations | 76 (`001_5B.sql` … `076_5K1.sql`) | `MIGRATION_MANIFEST.md`; `EXECUTION_REPORT.md` §12.6 |
| Schemas | 16 (15 business + `public`): `identity, organization, voice, crm, campaign, knowledge, workflow, billing, integrations, webhooks, plugins, analytics, audit`, prompt, memory, public | `EXECUTION_REPORT.md` §10; 4H §18.2 |
| Tables | ~197–199 | `EXECUTION_REPORT.md` §10, §12.4 |
| Partitioned tables | 22 | 5K §13.1 |
| RLS-enabled tenant tables | 91, `ENABLE + FORCE` | `EXECUTION_REPORT.md` §10 |
| RLS policies | 103 | `EXECUTION_REPORT.md` §10 |
| `SECURITY DEFINER` functions | 43 | `EXECUTION_REPORT.md` §12.2 |
| Native Postgres ENUM types | 0 (TEXT + CHECK used instead, by design) | `EXECUTION_REPORT.md` §10 |
| Native SEQUENCE objects | 0 (row-locked table used for invoice numbering) | `EXECUTION_REPORT.md` §10 |

Every rule in this document that touches persistence (IDs, timestamps, money, enums, pagination cursors, idempotency, concurrency, RLS) is derived from what Phase 5 actually implemented — never redesigned to make an API "cleaner." Where an API requirement genuinely cannot be satisfied by the frozen schema, it is flagged inline as:

> **API-DESIGN DEPENDENCY / FUTURE DECISION** — description, and which future phase should own it.

Four such items surfaced during research and are tracked in full in §40 (Risks/Open Questions).

---

## 5. API Design Principles

Inherited unmodified from `docs/product/ARCHITECTURE_PRINCIPLES.md` and made concrete for the API layer:

1. **API First** — every capability is a versioned API; the web frontend is a first-class API consumer, not a privileged backdoor (SRS §5: web UI dogfoods the same `/v1` API as external partners).
2. **Multi-Tenancy is Non-Negotiable** — every request, cache key, queue message, and event carries tenant context; tenant isolation is enforced at API, service, database, cache, storage, and event layers (SRS FR-TEN-002; HLA §7.8).
3. **Hexagonal / Clean Architecture** — the API (Interface layer) is a thin adapter over Application Services; it never contains business rules (3A §2.1–2.2).
4. **Provider Independence** — no API contract leaks a specific telephony/STT/TTS/LLM/payment vendor's shape; all such detail is normalized (`docs/product/ARCHITECTURE_PRINCIPLES.md`; 4I §13.3 `FailureCode` normalization).
5. **Stateless Services, Horizontal Scale** — no API handler holds in-process state across requests beyond a single pod's local WebSocket connection table (3B `ConnectionManager`, explicitly pod-local, "discovery only, not failover").
6. **Latency-First Design** — every endpoint declares its latency tier before implementation (§40 of this document formalizes the rule).
7. **Backward Compatibility by Default** — breaking changes require a new version and a published deprecation policy (SRS NFR-COMPAT-001).
8. **Observability by Construction** — every request is traced, correlated, and measured; nothing is added after the fact (`docs/product/ARCHITECTURE_PRINCIPLES.md` "Observability").
9. **Security by Design** — TLS, RBAC, tenant isolation, audit, and input validation are structural, not optional middleware someone forgot to add.

---

## 6. API Communication Architecture

The platform already establishes, at Phase 2/3 level, that not every operation belongs on the same transport. Phase 6A makes this explicit and binding.

| Transport | Used for | Why | Established by |
|---|---|---|---|
| **Synchronous REST (HTTP/JSON)** | CRUD, configuration, auth, lightweight queries, command endpoints whose side effect is "durably record a state transition" | Client needs an immediate, bounded-latency answer; underlying work is a short DB transaction | HLA §7.3 (WebApp→Gateway→sync HTTP to CRUD services) |
| **Asynchronous (202 + Job)** | Document ingestion, embedding generation, CSV/bulk contact import, campaign audience materialization, exports, analytics backfills, post-call summarization | Work is provider-bound (LLM/STT), scales with data volume, or is explicitly modeled as a background job in Phase 5 (`ingestion_jobs`, `csv_import_job`, campaign `PREPARING` state) | 3B §18.2, 3E §6.6, 5F §6.4, 4D Campaign lifecycle |
| **Realtime (WebSocket)** | Live call audio/control, agent runtime turn events, campaign progress, workflow execution progress, in-app notifications | Sub-800ms voice turn budget cannot tolerate HTTP request/response round-trips; server-push is required for progress/notification UX | HLA §7.5; 3B §17–18 (voice WS already implemented); NFR-PERF-001 |
| **Outbound Webhooks** | Notifying **tenant-owned external systems** of lifecycle events (`call.completed`, `campaign.finished`, `invoice.generated`, etc.) | Platform-initiated, at-least-once, tenant-configured destination outside the platform's trust boundary — fundamentally different from a WS event pushed to a browser tab the platform itself owns | 5I `webhooks.webhook_deliveries` (fully implemented); 3E §7 |

**Binding rule:** an operation whose expected p95 exceeds the Tier A/B budgets in §11, or which depends synchronously on an external AI/telephony/payment provider for its *full* result, MUST NOT be exposed as a plain synchronous REST call. It is either (a) modeled as an async job (§19), or (b) it returns as soon as the durable state transition is recorded and the caller observes completion via WebSocket event or webhook (§18, §27–28).

This directly encodes an existing Phase 4 invariant (4H §9.1, §20 checklist): *"the voice hot path (sub-800ms turn loop) must never make a synchronous call to Billing, Analytics, CRM-write, or Campaign-write."* Phase 6A generalizes this into a platform-wide rule, not just a voice-turn rule.

---

## 7. REST Standards

### 7.1 Why REST, not GraphQL

**Decision (ADR-6A-01, §39):** REST over HTTP/JSON is the platform's public and internal API style. GraphQL is rejected for V1.

Rationale: the domain is already resource-shaped by 56 aggregate roots across 30 bounded contexts (4H §15–16) with clear ownership boundaries and REST-friendly state machines. FastAPI + Pydantic + OpenAPI is the approved stack (TECH_STACK.md) and generates REST contracts natively. GraphQL's main advantage — client-driven field selection to avoid over/under-fetching — is better solved here by sparse fieldsets (§9) and purpose-built read endpoints for the heavy-read (analytics/CQRS projection) tier, without taking on a second query-execution engine, N+1 risk at the resolver level, and a caching/rate-limiting model that doesn't map cleanly onto per-tenant Redis quota enforcement. Revisit only if a specific aggregation-heavy client need (e.g. a partner building custom dashboards) cannot be met by Tier C heavy-read endpoints.

### 7.2 Namespace

**Decision:** `/api/v1/` for all tenant- and user-facing endpoints, reconciling SRS §5's `/v1/...` requirement with FastAPI convention and the existing NGINX ingress path-based routing (3F §8.2). `/api/` distinguishes API traffic from the Next.js web app sharing the same edge/CDN, `v1` is the version segment (§31).

- `/api/v1/{resource}` — tenant/user-facing REST resources.
- `/api/internal/v1/{...}` — internal service-to-service endpoints (§23.4), never exposed through the public ingress rate-limit/documentation surface.
- `/health/live`, `/health/ready` — unversioned, unauthenticated, infra-only (already implemented, 3F §20.1).
- WebSocket endpoints are not under `/api/v1` — they use a distinct `/ws/v1/...` path (§27), since they are a different protocol with different framing.

### 7.3 HTTP Methods

| Method | Safe | Idempotent | Use |
|---|---|---|---|
| GET | Yes | Yes | Read a resource or collection. Never mutates. |
| POST | No | No (unless Idempotency-Key supplied, §16) | Create a resource, or invoke a non-CRUD command/action. |
| PUT | No | Yes | Full replacement of a resource. Rarely used — most resources are partially updatable and state-machine guarded (§17), so PUT is reserved for genuinely full-replace semantics (e.g., replacing a workflow's entire draft graph). |
| PATCH | No | Yes (same input → same result; not "apply twice = double effect") | Partial update of mutable fields. |
| DELETE | No | Yes | Remove or soft-delete a resource, matching the resource's Phase 5 delete semantics (§7.6). |

### 7.4 Status Codes

| Code | Meaning | Standard use |
|---|---|---|
| 200 | OK | Successful GET/PATCH/PUT/action with synchronous result |
| 201 | Created | Successful POST creating a resource; `Location` header set |
| 202 | Accepted | Async operation enqueued (§19) |
| 204 | No Content | Successful DELETE, or action with no response body |
| 400 | Bad Request | Malformed request (unparseable JSON, invalid query params) |
| 401 | Unauthorized | Missing/invalid/expired credential |
| 403 | Forbidden | Authenticated but not authorized (RBAC or tenant-boundary denial) |
| 404 | Not Found | Resource doesn't exist **or** exists in another tenant (§23 — never distinguish the two) |
| 409 | Conflict | State-machine transition guard rejected the request, or Idempotency-Key payload mismatch (§16, §17) |
| 412 | Precondition Failed | `If-Match` ETag mismatch (§17) |
| 413 | Payload Too Large | Request body exceeds limit (§15) |
| 422 | Unprocessable Entity | Well-formed but semantically invalid (Pydantic validation failure) |
| 429 | Too Many Requests | Rate limit exceeded (§20) |
| 500 | Internal Server Error | Unhandled failure — never leaks internals (§25) |
| 502/503/504 | Upstream/Unavailable/Timeout | Dependency failure surfaced honestly, not masked as 500 |

### 7.5 Encoding Conventions

| Concern | Standard | Source |
|---|---|---|
| Content type | `application/json; charset=utf-8` exclusively for request/response bodies (media transfer uses signed URLs, §29, not JSON payloads) | — |
| Text encoding | UTF-8 everywhere | — |
| Date/time | ISO 8601 `TIMESTAMPTZ` in UTC, e.g. `2026-08-21T09:15:30.123Z` — mirrors 5A §9.1 exactly (all DB timestamps are `TIMESTAMPTZ` in UTC); the API never emits naive/local timestamps. Calling-window/appointment fields that need a companion IANA timezone (5A §9.3) expose it as a separate `timezone` field, never folded into the timestamp string. | 5A §9.1, §9.3 |
| UUID | Lowercase, hyphenated, RFC 4122 string form of the underlying UUIDv7 primary key (5A §8.1). API never exposes DB sequence/row-count information — UUIDv7 is already opaque enough (time-ordered but not enumerable). | 5A §8.1 |
| Money | Always an object: `{"amount": "1234.5000", "currency": "INR"}` — `amount` serialized as a **string**, not a JSON number, to avoid floating-point precision loss on `NUMERIC(18,4)`; `currency` is ISO 4217. Never a bare numeric field. This mirrors the DB's `(amount, currency)` pair convention and the platform invariant that cross-currency arithmetic is a domain error (5A §10.1; 4I §11.2). | 5A §10, 4I §11.2 |
| Boolean | JSON `true`/`false` only — never `"Y"/"N"` or `0/1` | — |
| Enums | JSON string, exact value of the DB's `TEXT + CHECK` constraint (e.g. `"ACTIVE"`, `"DEAD_LETTER"`) — the API never re-encodes Phase 5's status vocabulary into a different casing/shape, since that vocabulary is the contract every state machine in §17 depends on. New enum values are additive-only within a major version (§30). | 5A §21.7 |
| Null vs absent | `null` means "explicitly cleared"; a field omitted from a PATCH body means "leave unchanged." Every PATCH endpoint documents this per-field. | — |
| Phone numbers | Canonical E.164 string (`+91XXXXXXXXXX`) always, both directions — the API is the single normalization boundary; it never accepts or returns a non-E.164 phone format as canonical (raw display formatting is a frontend concern). | 4I §5.3 |

### 7.6 Delete Semantics

The API's DELETE verb must match what the underlying aggregate actually supports (5A §16) — it is never a blanket hard delete:

- **Soft-delete resources** (`contacts`, `documents`, `recordings`, `users`): DELETE sets `deleted_at` / terminal status server-side; GET on a soft-deleted resource returns 404 to non-privileged callers.
- **Terminal-status resources** (`campaigns`, `deals`, `workflow_definitions`, most aggregates): DELETE is either disallowed (410/405) in favor of an explicit archive/cancel action endpoint (§8.3), or maps to the aggregate's own terminal-state transition.
- **Append-only / immutable resources** (`audit_events`, `usage_events`, `webhook_deliveries`, `activities`): DELETE is never exposed — 405 Method Not Allowed. These are Phase 5 invariants (REVOKE UPDATE/DELETE from app roles), not an API-layer choice.

---

## 8. URL and Resource Naming

### 8.1 Nouns, Plurals, Nesting

- Resources are plural nouns: `/api/v1/agents`, `/api/v1/calls`, `/api/v1/contacts`, `/api/v1/campaigns` — mirrors 5A §21.2's table-naming convention (`snake_case`, plural) translated to `kebab-case-if-multiword` URL segments.
- Path parameters use the resource's singular + `_id` in documentation (`{agent_id}`), matching 5A §21.3's FK-naming convention.
- Nesting is used only for genuine ownership/containment (max 2 levels): `/api/v1/campaigns/{campaign_id}/contacts`, `/api/v1/knowledge-bases/{kb_id}/documents`. A resource addressable independently by its own ID is **never** nested (e.g. `/api/v1/contacts/{id}` directly, not only reachable via a campaign).
- Cross-bounded-context references are never expressed as nested URLs implying a joinable relation — this mirrors the frozen "no cross-schema FK" rule (4G §18.9 / 4H §18.6): a Contact referenced from a Campaign is `campaign_contact.contact_id` (a plain field), not a URL path through the CRM context.

### 8.2 Verbs Are Forbidden in Resource Paths

No `/getContacts`, `/createCampaign`. The HTTP method carries the verb.

### 8.3 Command / Action Endpoints

Reserved for state transitions that are **not** a generic field PATCH — i.e., transitions already modeled in Phase 5 as guarded, `SECURITY DEFINER`-controlled state-machine moves (5C, 5E, 5G, 5I; §17 of this document). Pattern: `POST /api/v1/{resource}/{id}/{action}`.

```
POST /api/v1/calls/{call_id}/terminate
POST /api/v1/campaigns/{campaign_id}/pause
POST /api/v1/campaigns/{campaign_id}/resume
POST /api/v1/webhook-deliveries/{delivery_id}/replay
POST /api/v1/workflows/{workflow_id}/publish
```

**When an action endpoint is preferable to `PATCH .../calls/{id}`:** whenever the transition (a) is guarded by business rules beyond "field X now equals Y" (e.g. `ACTIVE→WRAP_UP` only via explicit directive, timeout, or hangup — 4B §7.1), (b) has side effects beyond the row update (e.g. terminating a call must also signal the Voice Gateway), or (c) corresponds to one of Phase 5's `SECURITY DEFINER` transition functions (`fn_claim_delivery`, `fn_replay_webhook_delivery`, `fn_start_workflow_execution`, etc.) that already encodes the guard. A bare `PATCH {"status": "TERMINATED"}` would force the API layer to reimplement that guard logic and would invite exactly the kind of direct, ungated status mutation Phase 5's `REVOKE UPDATE` grants were designed to prevent. Command endpoints map 1:1 onto these functions; the API never exposes a generic "set status to anything" PATCH for guarded aggregates.

Plain `PATCH` remains correct for genuinely free-form field updates (e.g. `PATCH /api/v1/contacts/{id}` to update `email`/`display_name`) where no state-machine guard applies.

### 8.4 Bulk, Search, Export

- Bulk operations: `POST /api/v1/{resource}/bulk` (e.g., bulk contact suppression) — always async (§19), always with per-item result reporting in the job's result payload, never a single all-or-nothing 5000-row transaction.
- Search: `GET /api/v1/{resource}/search?q=...` only where full-text/semantic search is a genuinely distinct query mode from filtered listing (§14); otherwise `?search=` is a query parameter on the existing collection endpoint, not a separate resource.
- Export: `POST /api/v1/{resource}/exports` (creates an async export job, §19), `GET /api/v1/exports/{export_id}` to poll, result delivered via signed download URL (§29) — never a synchronous CSV/Excel stream from a list endpoint.

### 8.5 Internal Endpoints

`/api/internal/v1/...` — service-to-service only (worker → core API callbacks, admin break-glass tooling). Never documented in the public OpenAPI surface (§31), never subject to tenant JWT auth (uses the internal service-principal mechanism, §23.4), and excluded from the public rate-limit/quota system (governed instead by a fixed internal ceiling).

---

## 9. Request / Inbound Architecture

### 9.1 Canonical Pipeline

The Phase 3 LLD documents middleware **files** (`tenant_resolution.py`, `correlation_id.py`, `rate_limit.py`, `error_handler.py`) but — per the research pass — never states their execution order (3A §3, file-listing order only; explicitly flagged as unspecified). Phase 6A resolves this gap and makes it binding:

```
Client
  ↓
DNS / Edge (CDN — static/media only, never API traffic, §13)
  ↓
TLS termination (cert-manager + Let's Encrypt, at NGINX Ingress — 3F §8.1–8.2)
  ↓
NGINX Ingress: coarse rate limiting (per-IP, pre-auth abuse defense — 3F §8.4)
  ↓
Request ID / Correlation ID assignment (contextvar, feeds structured logs + OTel span — 3A §12.4)
  ↓
Authentication (JWT verification or API-key hash lookup — 3E §12.2)
  ↓
Tenant Resolution (TenantContext.set(); SET LOCAL app.tenant_id prepared for the DB session — 3A §11.2, 5B §16.1)
  ↓
Fine-grained Rate Limiting (tenant/API-key/endpoint-class aware, now that identity is known — 3E "second line of defence")
  ↓
Authorization (RBAC permission check, Redis-cached — 3E §12, 5B §17)
  ↓
Input Validation (Pydantic schema — strict, rejects unknown fields)
  ↓
Business Logic (Application Service → Domain → Repository, §33)
  ↓
Database / Cache / Queue
  ↓
Response (serialize → compress → emit)
```

**Why coarse rate limiting sits before authentication:** an unauthenticated flood must not be allowed to spend CPU on JWT verification or a Redis API-key lookup; NGINX's `per_ip` zone (60 r/min, already implemented — 3F §8.4) is the cheap first gate. **Why fine-grained rate limiting sits after tenant resolution, not before:** tenant/plan-tier-aware quotas (tied to the existing `QuotaConfig` aggregate, 4A §5.7/4F §5.4) cannot be evaluated until the tenant is known — this is the concrete meaning of 3E's "second line of defence" comment. **Why authorization sits after tenant resolution but before business logic:** RBAC permission compilation (`rbac:permissions:{org_id}:{user_id}`, 5B §17) requires both identity and tenant context, and no domain code should run for a request that will be rejected.

Everything above "Business Logic" is generic middleware, applied uniformly by the framework — no individual endpoint re-implements auth, tenant resolution, or rate limiting.

### 9.2 What Must Happen Before Business Logic

Non-negotiable, for every request without exception: request ID assigned, principal authenticated, tenant context resolved and about to be bound to the DB session via `SET LOCAL app.tenant_id` (5B §16.1 — this is a hard DB-level dependency, not a style preference: RLS fails closed to zero rows if unset), rate limit checked, permission checked, and the request body schema-validated. A handler function is never reachable with an un-set tenant context, because RLS provides no protection at all in that state (5A §6.1: `current_setting(..., true)` returns NULL → RLS predicate matches zero rows — safe, but silently empty, which is worse than an explicit 401/403 for debuggability). The middleware layer must fail the request explicitly rather than let it fall through to an empty-but-200 response.

---

## 10. Response / Outbound Architecture

### 10.1 Response Envelope

**Decision (ADR-6A-04, §39):** a minimal, discriminated envelope:

```json
// Success — single resource
{ "data": { ... }, "meta": { "request_id": "..." } }

// Success — collection
{ "data": [ ... ], "meta": { "request_id": "...", "pagination": { "next_cursor": "...", "has_more": true } } }

// Error
{ "error": { "code": "...", "message": "...", "details": {}, "request_id": "..." } }
```

`data` and `error` are mutually exclusive top-level keys. Rationale: a uniform envelope lets every client (web app, partner integrations, internal services) branch on presence of `error` without inspecting HTTP status semantics deeply, and `meta.request_id` gives support/debugging a stable correlation handle on every response, not just errors. The overhead (~30–40 bytes of wrapper JSON) is negligible against actual payload size for CRUD/config responses (Tier A/B, §11) and is not applied to WebSocket events (§27, which have their own envelope) or to signed-URL-based media transfer (§29, which never returns raw bytes as JSON).

**Exception:** endpoints explicitly documented as Tier A "hot list" (e.g., a polling endpoint hit at high frequency by the frontend) MAY omit `meta.pagination` fields that aren't relevant and keep `data` as the sole substantive key — but the `{data, meta}` *shape* itself is never dropped, to preserve client-side uniformity. No endpoint returns a bare array or bare object at the top level.

### 10.2 Serialization and Field Selection

- Pydantic response models are explicit allow-lists (never `model_dump()` of an ORM row) — this is also the mechanism that guarantees secret/credential fields (`credential_ref`, `signing_secret_ref`, `password_hash`, `key_hash`) are structurally impossible to leak (§22.5), because they're never in the response model's field set to begin with.
- Sparse fieldsets (`?fields=id,name,status`) are supported only on Tier C heavy-read/list endpoints where payload size is a genuine concern (e.g., a contacts list); not on Tier A single-resource GETs, where the full resource is cheap and predictability matters more than shaving bytes.
- Nested child collections are never inlined unbounded — cap at 20 items with a `has_more` flag and a link to the child collection's own paginated endpoint (mirrors §15's anti-embedding rule).

### 10.3 Caching Headers

- `ETag` on single-resource GETs for state-machine-guarded and free-form-mutable resources alike (derived per §17.2), enabling conditional `GET (If-None-Match)` → 304, and `PATCH (If-Match)` → optimistic concurrency.
- `Cache-Control: private, no-store` by default on all tenant-scoped responses (never cached by shared/CDN infrastructure — consistent with §13's "CDN never caches API traffic" rule, already true in the frozen deployment topology, 3F §13).
- `Cache-Control: public, max-age=300` is permitted **only** on platform-global, non-tenant-scoped reference endpoints (e.g. `/api/v1/permissions`, `/api/v1/integration-definitions`) — the small allow-listed set of endpoints reading platform reference tables with `organization_id IS NULL` (5B §16.4's mixed-scope pattern).

### 10.4 Compression and Large Objects

- gzip/brotli negotiated via `Accept-Encoding`, applied at the NGINX layer for responses > 1KB (standard, no custom logic needed).
- Large binary objects (recordings, documents, exports) are **never** serialized into a JSON response — see §29. A JSON response containing a `download_url` (signed, short-TTL) is the only accepted pattern.

---

## 11. Latency Architecture

Two numbers already exist in the frozen requirements and must not be contradicted: **NFR-PERF-001** (voice end-to-end p50 < 800ms) and **NFR-PERF-002** (non-voice API p99 < 300ms under nominal load) — SRS §4. Everything below is derived from those two anchors plus the per-stage voice budget already proposed in 3B §21 (explicitly flagged there as "proposed, not previously approved" — Phase 6A adopts it as the binding Tier E reference since no superseding number exists).

| API Class | p50 | p95 | p99 | Timeout | Notes |
|---|---:|---:|---:|---:|---|
| **Tier A — Interactive** (CRUD, config, light reads) | 60 ms | 180 ms | 300 ms | 5 s | p99 target is exactly NFR-PERF-002. Single indexed query or Redis-cached RBAC/permission check, no external dependency on the request path. |
| **Tier B — Operational** (call control, campaign pause/resume, workflow commands) | 100 ms | 300 ms | 500 ms | 8 s | Endpoint acknowledges once the state transition is **durably recorded** (short DB txn via the guarded transition function, §17); it does not wait for the external side effect (e.g. actual telephony hangup) to be confirmed — that confirmation arrives via WS event or webhook. This is what keeps Tier B close to Tier A despite triggering real-world effects. |
| **Tier C — Heavy Read** (analytics, reports, complex filtering) | 300 ms | 1200 ms | 2500 ms | 10 s | Must read from pre-computed CQRS projections (4G §3.1 — Analytics is projection-based, ≤60s lag), never aggregate raw transactional tables inline. A heavy-read endpoint that cannot be served from a projection is a signal the projection is missing, not that the budget should be relaxed. |
| **Tier D — Async Submit** (ingestion, bulk import, exports, campaign prep) | — | — | — | Enqueue: 200 ms p95 | Not measured as request latency. See §19 for the full job-lifecycle SLA breakdown (enqueue / job-start / completion). |
| **Tier E — Realtime** (voice WS turn, agent events) | 725 ms (full turn, no tool call) | 1500 ms (full turn) | — | Per-turn budget, not connection timeout | Reproduced from 3B §21's per-stage table below; this is the existing voice-turn budget, not a new number. |

**Tier E per-stage breakdown** (3B §21, adopted as-is):

| Stage | p50 | p95 |
|---|---:|---:|
| Network: caller → telephony → gateway | 50 ms | 120 ms |
| VAD / endpoint detection | 150 ms | 300 ms |
| STT finalization | 100 ms | 200 ms |
| Model Router selection | <5 ms | <10 ms |
| LLM time-to-first-token | 250 ms | 500 ms |
| Tool execution (if invoked) | 150 ms | 400 ms |
| TTS time-to-first-audio-byte | 120 ms | 250 ms |
| Network: gateway → telephony → caller | 50 ms | 120 ms |

Non-voice realtime events (campaign progress, notifications over WS) target p95 < 500 ms server-emit-to-client-receive — looser than voice because there is no human-perceptible turn-taking constraint, only a "feels live" UX bar.

**Latency components, explicitly separated** (never conflated as if the API server controls the whole path):

```
end-to-end client-observed latency
  = network (client ↔ edge)
  + edge/gateway processing (TLS, NGINX rate limit)
  + application processing (auth + authz + validation + business logic + serialization)
  + database latency
  + cache latency
  + external dependency latency (only for Tier E turn stages / async jobs — never inline on Tier A/B/C)
  + network (edge ↔ client, response)
```

The Tier A–C targets above bound *server processing latency* (auth through serialization); they explicitly exclude client-side network RTT, which varies by geography and is out of the API's control. Where a dependency (LLM/STT/TTS/telephony/payment provider) cannot meet a strict inline budget, §6's rule applies: it is moved off the synchronous path entirely, not absorbed into a relaxed Tier A/B target.

---

## 12. Performance Budgets

Breaking down the Tier A p99 = 300 ms ceiling into a budget every layer must respect (illustrative allocation, not a hard per-layer SLA each endpoint must individually prove — but a design constraint: if any one layer alone regularly consumes more than its share, that layer needs its own fix, not a Tier A target increase):

| Component | Budget (of 300 ms p99) | Mechanism keeping it there |
|---|---:|---|
| Edge / NGINX ingress | 5 ms | TLS session reuse, no app logic |
| Authentication | 10 ms | Redis-cached API-key hash lookup (5 min TTL, 3E §12.2); JWT verification is pure CPU, no I/O |
| Tenant resolution | <1 ms | Read from already-verified JWT claim / API-key lookup result — no extra DB round trip |
| Authorization (RBAC) | 10 ms | Redis-cached `rbac:permissions:{org}:{user}` (5 min TTL, invalidated on role change — 5B §17, 3E §12) |
| Input validation | <5 ms | Pydantic, in-process, no I/O |
| Application logic | 20 ms | Thin — orchestration only, no heavy computation on the request path (§33) |
| Database | 100–150 ms | Single indexed query via tenant-first composite index (5A §13.3); PgBouncer transaction-mode pool avoids per-request connection setup cost (3F §15.1) |
| Cache (Redis) | 2–5 ms | In-region Redis Cluster, hash-tagged by tenant (3F §16.2) |
| Serialization | 5 ms | Explicit Pydantic response models, no reflection-heavy ORM dumps |
| Network (server-side egress) | remainder | — |

Where a dependency genuinely cannot be isolated to this budget (e.g. a third-party CRM integration lookup), the endpoint is not Tier A — it is either Tier C (if it's a read that can be cached/projected) or it is redesigned as async (§19). No endpoint is allowed to claim Tier A status while making a synchronous call to an external, non-platform-controlled system.

---

## 13. Database Performance Rules

Phase 5 is frozen; these are rules for how the API layer *queries* it, not schema changes.

| Rule | Requirement | Basis |
|---|---|---|
| Tenant-first filtering | Every tenant-scoped query must filter on `organization_id` (matches the leading column of every tenant-scoped composite index, 5A §13.1/§13.3) — this is also what RLS predicate pushdown and partition pruning depend on. | 5A §13 |
| No `SELECT *` | Repository queries select only mapped columns needed for the response model — never `SELECT *` into an ORM entity that's then partially serialized. | 5A §29 anti-patterns; CODING_STANDARDS |
| Pagination over OFFSET | Cursor pagination is the default for any collection that can grow past a few hundred rows (§14) — large `OFFSET` on partitioned, high-volume tables (`call_sessions`, `usage_events`, `audit_events`, `campaign_contacts`) is explicitly disallowed. | 5A §14 (partitioned tables list) |
| Query limits | Every list endpoint enforces a server-side max page size (§14.3) regardless of what the client requests. | — |
| N+1 prevention | Aggregate repositories load the aggregate root with its owned child entities in one query (eager-loaded join or a single batched follow-up query) — never per-row lazy loads in a serialization loop (3A §7; 5A §27.2). | 3A §7, 5A §27.2 |
| Query timeouts | Tier A/B queries: `statement_timeout` 5 s. Tier C heavy-read queries: 30 s, and only against projection tables or the read replica, never the primary OLTP path (3F §15.2 read/write split). | 3F §15.2 |
| Transaction scope | Short — validate, single-aggregate write inside one transaction, commit, then async follow-up (§34). Never held open across an external HTTP call. | 4H §9.1 invariant; §34 of this document |
| Connection pooling | PgBouncer **transaction-mode** pooling (already implemented, 3F §15.1) — the API layer must use `SET LOCAL app.tenant_id = ...` (never bare `SET`) precisely because a plain `SET` would leak across pooled connections in transaction mode; `SET LOCAL` is correctly transaction-scoped and is what Phase 5's RLS design already assumes (5A §27.1, 5B §16.1). | 5A §27.1, 5B §16.1, 3F §15.1 |
| Read/write separation | Writes and per-call-turn reads go to the primary (staleness risk too high for the voice path); Tier C analytics/heavy reads may use a read replica where the projection lag tolerance (§11 Tier C) allows it. | 3F §15.2 |
| Index-aware sort/filter | Only fields covered by an existing Phase 5 index (or a documented partial/composite index) are exposed as `sort=`/`status=` filter parameters (§14) — the API never lets a client request an unindexed sort/filter that would force a sequential scan on a partitioned table. | 5A §13 |

---

## 14. Pagination

### 14.1 Decision

**Cursor pagination is the default** for every collection endpoint. **Decision (ADR-6A-03, §39).**

| | Offset | Cursor |
|---|---|---|
| Pros | Simple; supports "jump to page N" | Stable under concurrent writes; scales to partitioned, high-volume tables without `OFFSET` scan cost |
| Cons | Expensive/unstable at large offsets; skips/duplicates rows under concurrent insert-heavy tables | No arbitrary page jump; slightly more client bookkeeping |
| Used for | Small, bounded, rarely-changing admin lookups only (roles, permissions, integration catalog — typically <1000 rows, `organization_id IS NULL` reference tables) | Everything else, especially `call_sessions`, `usage_events`, `audit_events`, `campaign_contacts`, `webhook_deliveries`, `document_chunks` — all of which are Phase 5's actual partitioned, high-volume tables (5A §14.2) |

### 14.2 Cursor Format

The cursor is an **opaque, HMAC-signed, base64url-encoded token** — never a raw UUID or raw column value the client could parse or forge. It encodes `(sort_column_value, id, direction)`. Signing prevents a client from constructing an out-of-range cursor to probe data outside their tenant, and keeps the internal sort-key shape (which may reference UUIDv7 time-ordering) an implementation detail, not a public contract, even though UUIDv7 is already fairly opaque on its own (5A §8.1).

### 14.3 Defaults

| Setting | Value | Rationale |
|---|---|---|
| Default page size | 25 | Matches Tier A/C payload-size targets (§15) without forcing excessive round trips for typical UI list views |
| Maximum page size | 100 | Beyond this, the client should be exporting (§8.4), not paginating |
| Ordering | Every cursor-paginated endpoint orders by `(indexed_sort_column, id)` — the trailing `id` tiebreaker guarantees deterministic ordering even when the primary sort column has duplicate values (e.g. many rows with the same `created_at` millisecond), preventing the classic cursor-pagination bug of skipped/duplicated rows. | — |
| Default sort | `created_at DESC` unless the resource documents otherwise (e.g. `campaign_contacts` defaults to a dial-priority order) | — |

---

## 15. Filtering / Sorting / Search

| Concern | Standard |
|---|---|
| Filter syntax | `?status=active`, `?created_after=`, `?created_before=` — flat query parameters, one value or comma-separated list per field. No nested/boolean query-expression language is accepted from clients (`?filter[or][status]=...` style is rejected) — this is a deliberate anti-injection boundary (§15 of the task brief; §35 anti-patterns). |
| Allowed fields | Each endpoint documents an explicit allow-list of filterable fields — always a subset of that resource's indexed columns (§13). A field not on the allow-list returns 422, not a silent no-op. |
| Sort syntax | `?sort=-created_at` (leading `-` = descending), restricted to the same indexed-field allow-list. Multi-field sort is capped at 2 fields. |
| Search | `?search=` maps to either (a) Postgres full-text search (`tsvector`/GIN, where the underlying table has one) for structured entity search (contacts, documents by title), or (b) semantic search via the Knowledge/RAG context's existing pgvector/HNSW infrastructure (5F) for knowledge-base content — never a client-supplied `LIKE '%...%'` across arbitrary columns. Max search string length: 500 characters. |
| Maximum filter complexity | At most 10 filter parameters combined (AND-ed) per request; no client-supplied OR/NOT logic. |
| Injection protection | All filter/sort values are bound as parameters through SQLAlchemy — never string-interpolated into SQL — and validated against the field allow-list before touching the query builder, so there is no path from a query string to an arbitrary column or SQL fragment. |

---

## 16. Idempotency

### 16.1 Scope

Required for POST endpoints where a duplicate request has a dangerous side effect: resource creation with real-world consequences, campaign launch/pause/resume commands, bulk actions, workflow commands, and any endpoint fronting a payment or billing action. Mirrors and generalizes the idempotency patterns Phase 5 already implements natively for specific flows: `call_jobs.idempotency_key` (`UNIQUE ... WHERE status IN ('PENDING','DISPATCHED')`, 5E §5.5, ADR-5E-009), `usage_events` (`UNIQUE (organization_id, source_system, source_event_id, occurred_at)`, 5H ADR-5H-003), `payment_attempts.provider_webhook_event_id` (`UNIQUE (provider, event_id)`, 5H §17.3), and `inbound_webhook_events` (`UNIQUE (organization_id, provider_slug, provider_event_id)`, 5I §10).

### 16.2 Header Contract

```
Idempotency-Key: <client-generated opaque string, ≤255 chars, e.g. UUID>
```

| Property | Value |
|---|---|
| Scope | `(organization_id, principal_id, endpoint, Idempotency-Key)` — a key is only unique within one tenant + caller + endpoint, matching the tenant-scoped uniqueness pattern already used for `usage_events` and `inbound_webhook_events`. |
| Storage | Redis primary (`idempotency:{org_id}:{endpoint}:{key}` → cached response + request fingerprint hash, fast path). For endpoints backing a Phase 5 table that already has a DB-level uniqueness constraint (campaign call jobs, usage events, inbound webhooks), the DB constraint is the ultimate backstop — Redis is a latency optimization, not the sole guarantee. |
| TTL | 24 hours — matches the existing `notification:dedupe:{hash}` 24-hour pattern (3E §16) rather than inventing a new duration. |
| Request fingerprint | SHA-256 of the normalized (whitespace/key-order-independent) request body, stored alongside the cached response. |
| Duplicate, same payload | Return the originally cached response (same status code, same body) without reprocessing. |
| Duplicate, different payload | 409 Conflict with `error.code = IDEMPOTENCY_KEY_REUSE_MISMATCH` — the client reused a key for a materially different request. |
| Replay after TTL expiry | Treated as a new request — the caller is responsible for key uniqueness only within the TTL window they care about. |

GET (and other safe methods) never require or accept an Idempotency-Key — HTTP idempotency for safe/idempotent verbs is already structural (§7.3).

---

## 17. Concurrency / Consistency

### 17.1 The Real Constraint

Research confirmed Phase 5C–5J has **no generic optimistic-concurrency `version` column** on business-domain tables (a `version` column exists only in the `identity` schema, out of scope here). What Phase 5 has instead, applied with unusual consistency across every guarded aggregate, is: `status TEXT + CHECK`, `REVOKE UPDATE/DELETE` from application roles, and all state transitions routed through `SECURITY DEFINER` functions that internally perform a compare-and-swap on current status before mutating (e.g. `fn_claim_delivery` using `SELECT ... FOR UPDATE SKIP LOCKED`, `fn_delivery_failed` computing the new attempt count and forcing `DEAD_LETTER` regardless of caller intent, `fn_start_workflow_execution` enforcing single-active-session). This *is* the platform's optimistic/guarded-concurrency mechanism — Phase 6A formalizes it rather than inventing a parallel one.

### 17.2 API-Layer Rules

| Case | Mechanism |
|---|---|
| State-machine transitions (Call, Campaign, WebhookDelivery, WorkflowExecution, etc.) | Always via **action endpoints** (§8.3), which call the corresponding guarded DB function. If the function's internal guard rejects the transition (wrong current state, already claimed, etc.), the API returns **409 Conflict** with `error.details.current_state` so the client can resync, never a generic 500. |
| Free-form field updates on non-state-machine resources (e.g. a Contact's display name) | HTTP **ETag**, derived from `hash(id, updated_at)` — a weak validator, not a true monotonic version counter. `PATCH` requires `If-Match`; mismatch → **412 Precondition Failed**. |
| Read-then-conditionally-write client patterns | `GET` returns `ETag`; client submits `If-Match` on the follow-up `PATCH`. |

**API-DESIGN DEPENDENCY / FUTURE DECISION:** the `updated_at`-derived ETag is weaker than a dedicated `version_number` column (two updates within the same timestamp granularity are indistinguishable). This is flagged for a future Phase 5 revision to consider adding explicit `version_number` columns to high-contention, non-state-machine-guarded tables if `updated_at`-based ETags prove insufficient in practice. No such change is made here.

### 17.3 Locking and Retries

The API layer never takes its own application-level locks beyond what Phase 5's `SECURITY DEFINER` functions already do (e.g. `SELECT ... FOR UPDATE SKIP LOCKED` inside `fn_claim_delivery`) or what the Campaign Execution context already does via Redis `SETNX` (5E ADR-5E-012) — introducing a second, API-layer locking scheme would create two sources of truth for "who owns this row right now." Retries on 409/412 are the client's responsibility; the API never silently retries a conflicting write on the caller's behalf.

---

## 18. Async Job Architecture

### 18.1 The Contract

```
POST /api/v1/{resource}/{action}         →  202 Accepted  { "data": { "job_id": "...", "status": "PENDING" } }
GET  /api/v1/jobs/{job_id}                →  200 OK        { "data": { "job_id", "status", "progress", "result_ref", "error" } }
```

### 18.2 Job Status Vocabulary

`PENDING | RUNNING | SUCCEEDED | FAILED | CANCELLED` — chosen to generalize the two closest existing Phase 5 patterns (`voice.tool_executions.status`: `PENDING|RUNNING|SUCCEEDED|FAILED|TIMED_OUT`, and `knowledge.ingestion_jobs.status`: a richer multi-stage version of the same shape) into one API-facing vocabulary. `RETRYING` is intentionally **not** a top-level job status — retry attempts are visible via `attempt_count`/`current_stage` detail fields, keeping the primary status machine small and consistent for every job type.

### 18.3 Where the `/jobs` Resource Gets Its Data

`/api/v1/jobs/{job_id}` is an API-layer abstraction, not a new database table. For operations already backed by a Phase 5 tracking table (`knowledge.ingestion_jobs`, `campaign.call_jobs`, campaign `PREPARING` materialization, `csv_import_job`), the job endpoint **projects** from that table — no duplicate job-tracking state is introduced. For an operation with no dedicated domain table yet (e.g. a future generic "export" feature), this is flagged as:

> **API-DESIGN DEPENDENCY / FUTURE DECISION** — the owning Phase 6B+ domain document must either point the job endpoint at an existing table or specify a lightweight Celery-result-backed job record; this document does not create one.

### 18.4 Lifecycle Detail

| Field | Meaning |
|---|---|
| `progress` | Either a percentage (0–100) or a structured count (`{"completed": 340, "total": 5000}`) — resource-type-specific, documented per endpoint. |
| `result_ref` | A URI to fetch the full result (e.g. a signed download URL for an export, or the created resource's own `/api/v1/{resource}/{id}`) — never the full result inlined into the job status response (§15 payload-size rule). |
| `error` | Present only when `status = FAILED`; uses the standard error contract (§25). |

### 18.5 Async SLA Targets (Tier D, expanding §11)

| Stage | Target | Notes |
|---|---|---|
| Enqueue latency (202 response) | p95 < 200 ms | Just the DB write + Celery enqueue — no provider call on this path (§6, §12). |
| Job-start latency (queued → worker picks up) | p95 < 30 s | Bounded by Celery queue depth; monitored via `platform_celery_queue_depth` (3E §14.2). |
| Completion SLA — single document ingestion | p95 < 2 min | Indicative; owning phase (Knowledge/RAG, Phase 6/10) refines per actual embedding-provider throughput. |
| Completion SLA — bulk CSV import (10k rows) | p95 < 10 min | Indicative; owning phase (CRM, Phase 6/11) refines. |
| Completion SLA — campaign audience materialization (100k contacts) | p95 < 5 min | Indicative; owning phase (Campaign, Phase 6/12) refines. |

These are placeholders for design purposes, not committed SLAs — each owning domain document must confirm or revise them against real provider throughput data once implemented.

---

## 19. Caching

| Layer | Governs | Rule |
|---|---|---|
| Redis (application cache) | RBAC permissions, API-key auth, feature flags, quota counters, idempotency keys, response caching for expensive Tier C reads | Every key is tenant-namespaced: `{purpose}:{organization_id}:{...}` — "No cross-tenant key access is possible by construction" (5A §5.1). Phase 6A's new API-response cache keys (e.g. `apicache:{org_id}:{endpoint}:{params_hash}`) follow the identical pattern. |
| HTTP cache headers | Client/intermediary caching | `private, no-store` for all tenant data by default (§10.3); `public, max-age=300` only for the small platform-global reference-data allow-list. |
| CDN | Static assets, signed media URLs only | Never API JSON responses or WebSocket traffic (already true in the frozen deployment, 3F §13). |
| Client (TanStack Query) | UI-perceived freshness | Out of scope for this document — a frontend concern layered on top of the HTTP cache contract above. |

**Invalidation:** cache-then-invalidate-on-write, not TTL-only, for anything security-sensitive — API-key revocation and role changes explicitly issue a Redis `DEL` immediately rather than waiting out the 5-minute TTL (5B §31, 3E §12.1). Feature-flag and reference-data caches invalidate on their owning `*.updated` domain event (3A §10).

**Stampede prevention:** expensive Tier C cache regeneration uses a Redis `SETNX` single-flight lock (the same primitive already used for `lock:call:{provider_call_sid}`, 3B §16) — only one request recomputes; concurrent requests wait or serve stale-while-revalidate.

**Negative caching:** 404s on enumerable ID lookups are cached briefly (10s TTL) to blunt ID-guessing/enumeration probes without materially affecting legitimate-client latency.

---

## 20. Rate Limiting

Two enforcement points, matching the frozen infra + app split already established (3F §8.4, 3E "second line of defence"):

| Layer | Scope | Limit | Purpose |
|---|---|---|---|
| L1 — NGINX Ingress | Per source IP | 60 req/min (already implemented, `limit_req_zone $binary_remote_addr`) | Coarse pre-auth DDoS/abuse defense — applies before identity is known. |
| L1 — NGINX Ingress | Per WS connection | 5 concurrent (`limit_conn ws_conn 5`) | Prevents connection-flood abuse of the voice/realtime gateway. |
| L2 — Application, per-tenant | Standard CRUD | Default 300 req/min per organization, configurable per plan tier via the existing `QuotaConfig` aggregate (4A §5.7 / 4F §5.4) | Ties rate limiting to the platform's existing quota/plan model rather than a new parallel concept. |
| L2 — Application, per-tenant | Auth endpoints (login, password reset, OAuth callback) | Strict, IP + identifier keyed, ~5–10/min | Credential-stuffing/brute-force defense. |
| L2 — Application, per-tenant | Cost-sensitive (outbound call initiation, LLM-backed operations) | Governed by the existing real-time `Usage & Quota` bounded context's `CheckQuota` port (4A #6), not a separate limiter | Reuses the platform's real-time cost-quota enforcement rather than duplicating it. |
| L2 — Application, per-tenant | Heavy-read/analytics | Lower req/min ceiling + max 3 concurrent heavy queries per org | Protects the database from concurrent expensive scans (§13). |
| L2 — Application, per-tenant | Bulk/async submission | Limited by concurrent job count per org, not requests/min | Matches Tier D's job-based model (§19). |
| Internal service traffic | `/api/internal/v1/...` | High fixed ceiling, separate bucket, not tenant-quota-governed | Internal callers are trusted infrastructure, not tenant consumers. |

**429 response:** standard headers `Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`; body uses the standard error envelope with `error.code = RATE_LIMIT_EXCEEDED`.

Outbound webhook delivery (platform → tenant systems) is governed by its own retry/backoff contract (§28), not this rate-limiting system — it is a different traffic direction entirely.

---

## 21. Timeout / Retry / Circuit Breaker

| Dependency | Timeout | Retry | Notes |
|---|---|---|---|
| Inbound request (NGINX → app) | 120 s standard API, 3600 s for the voice WS ingress (already configured, 3F §8.2–8.3) | — | Existing infra values, not restated arbitrarily. |
| Database query | 5 s (Tier A/B), 30 s (Tier C) | Never auto-retried by the API for writes; safe to retry for pure reads at the client's discretion | §13 |
| Redis | Connect 1 s, command 2 s | One immediate retry on connection error, then fall through to Postgres where the data is also authoritative (Redis is never the sole source of truth, 5A §18.3) | **Newly specified by Phase 6A** — Phase 3 left Redis client timeout/pool config unspecified; this closes that gap without touching infra config already owned elsewhere. |
| Telephony provider | Per existing voice retry table | 2 attempts, exponential backoff, base 200 ms, jitter | 3B §19 — reused as-is. |
| STT provider | Per existing voice retry table | 1 retry, then failover to secondary provider | 3B §19–20 |
| LLM provider | Per existing voice retry table | 1 retry same provider, then Model Router re-selects | 3B §19 — the 800ms voice budget cannot absorb more. |
| TTS provider | Per existing voice retry table | 1 retry; **no approved fallback vendor** (explicit open item, 3B Review Note 4 — carried into §40) | 3B §19 |
| General external HTTP (non-voice, e.g. payment/CRM integration calls via `httpx`) | Connect 3 s, read 10 s | 1 retry with jitter for idempotent (GET) calls only; non-idempotent calls never auto-retried without an Idempotency-Key round trip to the provider (§16 principle applied outward, not just inward) | **Newly specified by Phase 6A** for the non-voice provider path, generalizing the voice-specific numbers 3B already set. |
| Webhook delivery (outbound) | 10 s HTTP timeout (already implemented) | Exponential backoff, `max_attempts` default 7 (1–10, per-endpoint configurable), then `DEAD_LETTER` | 5I §13–14 — reused exactly as implemented. |
| Circuit breaker | Shared cluster-wide via Redis `providerhealth:{provider_name}` (voice providers, already implemented, 3B §16/§19) | Generalized by Phase 6A to any external dependency (payment, integration providers) using the identical Redis-backed pattern rather than a pod-local breaker, for the same reason 3B gives: "a pod-local breaker would rediscover every outage independently on every pod." | 3B §16, extended |

**Critical rule, restated:** non-idempotent operations (plain POST without an Idempotency-Key) are never auto-retried by any layer of this stack — not by the API, not by a client library the platform ships. Only GET/PUT/DELETE, or POST carrying an Idempotency-Key, may be safely retried.

---

## 22. Security Architecture

| Concern | Standard |
|---|---|
| Transport | TLS everywhere (cert-manager + Let's Encrypt, already implemented, 3F §8.2); no plaintext HTTP path, including internal service traffic. |
| Authentication | JWT (15-min access token, stateless) + OAuth2 SSO for human principals; organization-scoped API keys (`vxa_...`, SHA-256 hashed at rest) for programmatic/partner access (5B §9.5, §18). No user-scoped or platform-scoped API keys exist in the frozen schema — the API never pretends otherwise. |
| Authorization | RBAC, `{resource}:{action}` permission strings (5B §17), evaluated server-side on every request post-tenant-resolution (§9.1); never trust a client-supplied role/permission claim without server-side recomputation from the DB/cache. |
| Tenant isolation | Enforced primarily by PostgreSQL RLS via `SET LOCAL app.tenant_id` (5B §16) — the API's authorization layer is defense-in-depth on top of RLS, never a substitute for it. `tenant_id`/`organization_id` is **never** accepted from the client body for authorization purposes; it is always derived from the verified JWT claim or API-key lookup (5B §16.4, §38 Tenant Isolation Test Matrix). |
| Input validation | Pydantic strict schemas — unknown fields rejected (`extra="forbid"`), preventing mass assignment (a client can never write a field the schema doesn't declare, e.g. `is_platform_admin` or `organization_id` on a create-user payload). |
| Output filtering | Response models are explicit allow-lists (§10.2) — credential/secret fields are structurally absent from every response model, matching the Phase 5 invariant that `credential_ref`/`signing_secret_ref` are opaque secret-manager references, never plaintext (5I §16, ADR-5I-002). |
| Secret handling | The API never returns a raw secret after initial issuance (API keys, webhook signing secrets are shown once at creation, matching 5B §18's "returned once" pattern) and never accepts a raw secret in a request body destined for a `credential_ref` field — those are populated via a dedicated secret-manager exchange flow (owned by a later phase), not inline JSON. |
| PII minimization / redaction | Logs and traces strip `phone_number|email|token|password|secret` (already implemented at the OTel Collector and `structlog` processor level, 3E §14.1, 3A §12.4) — the API layer does not additionally embed PII into `resource_snapshot` audit payloads beyond what 5B §30's documented allow-list specifies. |
| Audit logging | Every state-changing endpoint maps to a documented `action_kind` (5B §30, 4I §19.4) and triggers an `audit.audit_events` write — synchronous in the same transaction for auth/API-key/break-glass/data-subject/admin actions, async (Celery) for configuration/campaign/plugin/billing events (5J §14.5, reused exactly). |
| Request/webhook signing | Outbound webhooks: HMAC-SHA256 over `f"ts={unix_timestamp}.{payload_json}"`, header `X-Platform-Signature: v1={hex}` (5I §16, exact scheme, reused as-is — superseding the slightly different header shape informally mentioned at LLD service-description level in 3E, since the DB layer's implementation is authoritative). |
| Replay protection | Consumers are advised to reject webhook deliveries with `ts` more than 5 minutes old (application-layer guidance per 5I §16; not DB-enforced, so this document makes it a binding platform recommendation for both outbound signing and any future inbound signature verification). |
| CORS | Explicit origin allow-list per environment (never `*` combined with credentials); the web app and documented partner origins only. |
| CSRF | Not applicable to Bearer-token API auth (no ambient cookie credential is used for `/api/v1` calls); if a browser-session refresh-token cookie is ever introduced, it must be `httpOnly` + `SameSite=Strict`. |
| SSRF protection | Webhook endpoint registration (`webhook_endpoints.target_url`) validates HTTPS-only (already a DB CHECK, 5I §28) plus, at the API layer, blocks private/link-local/cloud-metadata IP ranges both at registration time and via a DNS-rebinding-safe fetch at dispatch time. |
| Injection prevention | Parameterized queries only, via SQLAlchemy (CODING_STANDARDS; §15's filter/sort allow-list is the same principle applied to client-supplied filter values). |
| Mass assignment | Covered above (strict Pydantic schemas); additionally, state-machine-guarded fields (`status` on guarded aggregates) are **never** writable via generic PATCH at all — only via action endpoints (§8.3, §17.2). |
| Object-level authorization (IDOR) | RLS is the primary guarantee; the application layer additionally verifies resource ownership/membership before returning data as defense-in-depth, and a resource in another tenant returns 404, never 403 (§7.4 — never confirm existence across a tenant boundary). |
| Rate limiting / abuse prevention | §20. Auth-endpoint step-up (CAPTCHA/MFA challenge on repeated failure) is flagged as an **open item** — not specified anywhere in Phase 1–5 (§40). |

---

## 23. Multi-Tenant Request Context

### 23.1 Canonical Context Chain

```
Request
  ↓
authenticated principal   (JWT subject, or API key → identity.api_keys row)
  ↓
organization               (JWT organization_id claim, or api_keys.organization_id — never client-supplied)
  ↓
membership + role          (organization.memberships ⋈ role, RLS-protected once tenant context is set)
  ↓
compiled permissions       (Redis-cached rbac:permissions:{org}:{user}, DB fallback on miss)
  ↓
resource authorization     (RLS + application-layer ownership check)
```

### 23.2 How Tenant Context Is Determined and Validated

- **JWT flow:** the JWT carries an `organization_id` claim for the currently-selected organization; switching organizations issues a new JWT (5B §22.1). The API sets `SET LOCAL app.tenant_id = jwt.organization_id` at the start of the request's DB transaction(s) — never from any request body/query-param field named `organization_id`, even if a client supplies one (it is ignored for authorization purposes and, if present, cross-checked against the resolved tenant only for defense-in-depth 400/409 reporting on obviously malformed clients).
- **API-key flow:** `identity.api_keys.organization_id` is resolved via the `SECURITY DEFINER` `identity.validate_api_key()` lookup that must run *before* tenant context exists (5B §35.2), then used to set `app.tenant_id` for the rest of the request.
- **Background workers:** derive tenant context from the event envelope's `organization_id` field before processing each message (5B §16.1) — the same rule, applied to the async path.

### 23.3 Fail-Closed Guarantee

If tenant context is somehow unset, RLS returns zero rows rather than all rows (5A §6.1) — but §9.2 makes explicit that the middleware layer must never let a request reach business logic in that state; an unset tenant context is a 401/500 at the middleware boundary, not a silent empty-result 200.

### 23.4 Service-to-Service Authentication

**API-DESIGN DEPENDENCY / FUTURE DECISION, resolved here without a Phase 5 change:** research confirmed Phase 5B defines no service-account/machine-credential table distinct from tenant-scoped API keys, and no internal auth protocol is documented anywhere in Phase 1–5. Phase 6A defines the missing piece as a **stateless mechanism requiring no new database table**, consistent with the "do not modify Phase 5" constraint:

- Internal service principals (Worker → Core API, Voice Gateway → Core API where such calls exist) authenticate with a **short-lived, platform-signed internal JWT** (separate signing key from user-facing JWTs), carrying `service_id` and, where the call is performed on behalf of a specific tenant's data, `on_behalf_of_organization_id`.
- This is validated by the same authentication middleware (§9.1), which treats it as a distinct principal type — mapping cleanly onto the `actor_type` values Phase 5J's audit schema already reserves for this (`WORKER | SYSTEM | PLATFORM_ADMIN | INTEGRATION`, 5J §14.1) — so audit logging for internal-service actions requires no new vocabulary.
- No new table is required: the internal JWT is verified by signature, not by a DB lookup, keeping this addition entirely within the API layer.

This decision is marked for confirmation alongside the ADR list (§39) since it introduces a mechanism not explicitly present in any frozen document — it is presented as the Phase 6A recommendation, subject to review (§42/§44).

---

## 24. Error Contract

### 24.1 Structure

```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "The requested resource could not be found.",
    "details": {},
    "request_id": "01930000-0000-7000-8000-000000000000",
    "retryable": false
  }
}
```

| Field | Purpose |
|---|---|
| `code` | Machine-readable, stable, `UPPER_SNAKE_CASE`, namespaced per error family (see §24.2). Clients branch on this, never on `message`. |
| `message` | Human-readable, safe to display; never contains internals. |
| `details` | Structured, error-family-specific (e.g., field-level validation errors as `{"field": "email", "issue": "invalid_format"}[]`; state-conflict errors as `{"current_state": "COMPLETED", "attempted_transition": "TERMINATE"}`). |
| `request_id` | Matches the request's correlation ID (§26) — the single handle support/debugging needs to find the exact log/trace. |
| `retryable` | Explicit boolean so clients don't have to infer retry-safety from the HTTP status code alone — particularly important for 5xx vs. 409/422 distinctions. |

### 24.2 Code Families (illustrative, not exhaustive — the full catalog is a future artifact, API-ERROR-CATALOG, per §45)

`VALIDATION_ERROR`, `AUTHENTICATION_REQUIRED`, `AUTHORIZATION_DENIED`, `RESOURCE_NOT_FOUND`, `STATE_CONFLICT`, `PRECONDITION_FAILED`, `IDEMPOTENCY_KEY_REUSE_MISMATCH`, `RATE_LIMIT_EXCEEDED`, `PAYLOAD_TOO_LARGE`, `DEPENDENCY_UNAVAILABLE`, `INTERNAL_ERROR`.

### 24.3 Never Exposed

SQL error text, stack traces, internal service/pod names, database schema/table/function names, provider credentials, or any `credential_ref`/`signing_secret_ref` value — the global exception handler (`error_handler.py`, already implemented, 3A §3) maps every unhandled exception to a generic `INTERNAL_ERROR` with a `request_id` for correlation, and full detail goes only to the structured log/trace (§26), never the response body.

---

## 25. Observability

Reconciled with the already-implemented Phase 3 stack (OpenTelemetry + Prometheus + Grafana Tempo + `structlog`) rather than inventing a parallel one.

| Concern | Standard |
|---|---|
| Request ID / Correlation ID | Assigned at entry middleware (§9.1), propagated through every log line, span, and — for voice — reused as the call/session correlation ID (3A §12.4). Returned to the client in `meta.request_id` / `error.request_id`. |
| Distributed tracing | OpenTelemetry SDK; every HTTP request, WS session, Celery task, and DB query is a span (3E §14.1). Sampling: staging 100%; production adaptive — 10% baseline for API requests escalating to 100% on 5xx/p99 breach, 100% for voice call traces, 25% baseline for Celery tasks (3F §19.2, reused exactly). |
| Structured logging | JSON via `structlog`, one shared processor pipeline, PII-redacting processor active on every log line, `print()` mechanically banned via lint (3A §12.4). |
| Metrics | Prometheus, `platform_`-prefixed (the platform's actual established convention — this document uses it rather than the generic `http_requests_total` naming a plain tutorial would suggest, reconciling with 3E §14.2 as instructed). Core set already defined and reused: `platform_http_requests_total{method,endpoint,status_code,tenant_id}`, `platform_http_request_duration_seconds{method,endpoint}`, `platform_celery_task_duration_seconds`, `platform_celery_queue_depth`, plus domain-specific metrics per bounded context (`voice_turn_e2e_seconds`, `webhook_delivery_success_rate`, `provider_circuit_open`, etc., 3E §14.2). |
| DB / cache / dependency latency | Captured as span attributes and dedicated histograms (`db_query_duration_seconds`-equivalent already implied by DB spans; Redis operation spans) — every Tier A/B/C endpoint's trace shows the auth/authz/DB/cache/serialization breakdown from §12, not just total latency, so a p99 regression is diagnosable without guessing. |
| Payload size | Request/response byte sizes recorded as span attributes for endpoints exceeding a size threshold, to catch §15 violations before they become incidents. |

---

## 26. API Performance Monitoring

| Signal | What it answers | Minimum tracked |
|---|---|---|
| Availability | Was the API successful? | Error rate (%5xx, %4xx-by-family), timeout rate |
| Latency | How fast did it respond? | p50/p90/p95/p99 per endpoint per Tier (§11) |
| Throughput | How many requests/sec? | `platform_http_requests_total` rate, per tenant and aggregate |
| Saturation | How close to capacity? | HPA-tracked CPU/memory (3F §9.1), `platform_celery_queue_depth`, DB connection pool utilization |
| Dependency health | Is Postgres/Redis/an AI or telephony provider the bottleneck? | Span-level dependency latency breakdown (§25); `provider_circuit_open` gauge |

A Grafana "API Performance" dashboard (alongside the existing Platform SLO, Voice Pipeline, Provider Health, Campaign Operations, Cost & Usage, Security, Tenant Utilization dashboards already provisioned as code, 3E §14.3) is the concrete deliverable expected once endpoints exist to instrument — tracked per Tier (A/B/C separately, since blending them hides regressions), with error rate, timeout rate, throughput, DB latency, and dependency latency at minimum.

---

## 27. WebSocket / Realtime Standards

### 27.1 Transport Decision

**Decision (ADR-6A-05, §39 — flagged for stakeholder sign-off, §40):** raw WebSocket (native FastAPI, `AsyncIO`) is the platform standard for **all** realtime channels, not just voice. Voice already implements this (3B §17–18); Phase 6A recommends extending the same protocol/infra to non-voice realtime (campaign progress, notifications, workflow execution progress) rather than standing up Socket.IO as a second realtime stack, even though `TECH_STACK.md` lists Socket.IO for the frontend. Rationale: one auth/tenant-isolation/observability path instead of two, no need for Socket.IO's long-polling fallback or room abstraction (the platform's connections are already tenant-scoped and don't need cross-tab broadcast rooms beyond what Redis pub/sub + per-tenant Redis Cluster hash-tagging already provides, 3F §16.2). This does not unilaterally override `TECH_STACK.md` — it is a recommendation requiring frontend-team sign-off before this ADR can be considered final (§40).

### 27.2 Connection Lifecycle

Reused exactly from the already-implemented voice gateway pattern (3B §17), generalized as the platform standard for every WS channel:

```
CONNECTING → AUTHENTICATED → BOUND (session/subscription attached) → STREAMING → CLOSING → CLOSED
```

- **Authentication:** JWT (query param or subprotocol header at connect time, since browsers can't set arbitrary headers on the WS handshake) or, for voice, the call-setup payload (3A §11.2/§3 line 362) — tenant resolved identically to the REST path (§23).
- **Heartbeat / reconnect:** server-side heartbeat/TTL on the connection's Redis presence key; client-side reconnect with exponential backoff + jitter is the client's responsibility (not server-mandated timing beyond documenting the heartbeat interval per channel).
- **No mid-stream resume for dropped voice call audio** — a WS drop mid-call ends the call; the stale-session reaper detects it via heartbeat/TTL expiry and force-transitions to `FAILED`, emitting `call.failed` (3B §17, reused as-is — this is a deliberate, already-approved hard boundary, not relaxed by Phase 6A). Non-voice channels (notifications, progress) MAY support resume-from-sequence on reconnect (§27.4), since there's no live-audio real-time constraint forcing an immediate hard cutover.
- **Connection limits:** 5 concurrent per source (already enforced at NGINX, 3F §8.4).

### 27.3 Event Envelope

Voice's WS protocol uses raw binary/control frames with no generic envelope (3B §17 — explicitly flagged as unformalized). **Phase 6A formalizes a generic JSON event envelope for every *non-audio* realtime channel** (control-frame events, campaign progress, notifications, workflow progress):

```json
{
  "event_id": "01930000-0000-7000-8000-000000000001",
  "event_type": "call.started",
  "version": 1,
  "timestamp": "2026-08-21T09:15:30.123Z",
  "organization_id": "...",
  "resource_id": "...",
  "sequence": 42,
  "payload": { }
}
```

| Field | Purpose |
|---|---|
| `event_id` | Dedup key, mirrors the `dedup_key` discipline already established for analytics ingestion (5J §7–8). |
| `sequence` | Monotonic per-connection/per-subscription counter — clients detect gaps (a dropped/out-of-order event) and can request a resync, honoring the platform-wide rule that cross-context event ordering is **not** guaranteed (4G §12.4). |
| `version` | Event schema version, independent of the API's `/v1` URL versioning (§31) — an event type can version forward without bumping the whole API. |

No domain-specific event catalog is defined here (explicitly out of scope, per the task brief) — this is the envelope shape every future event type must use.

### 27.4 Authorization and Isolation

Every WS connection is bound to exactly one resolved `organization_id` for its lifetime (no cross-tenant multiplexing on one socket); subscription-scoped channels (e.g., "campaign X's progress") re-verify RBAC permission on subscribe, not just at connect time.

---

## 28. Webhook Standards

Two distinct webhook directions exist in this platform and must not be conflated:

### 28.1 Outbound (Platform → Tenant's External Systems)

Fully implemented at the DB layer (5I) and reused here as-is, not redesigned:

| Concern | Standard |
|---|---|
| Subscription | `webhook_endpoints`: HTTPS-only `target_url`, `topics TEXT[]` filter, `signing_secret_ref` (opaque secret-manager reference — never plaintext), `max_attempts` (default 7, 1–10 configurable), `timeout_ms` (default 10000, 1000–30000) |
| Delivery model | At-least-once; `webhooks.webhook_deliveries`, partitioned monthly; status `PENDING → DELIVERING → DELIVERED` (terminal) `\| DELIVERING → PENDING` (retry) `\| DELIVERING → DEAD_LETTER` (forced once `attempt_count >= max_attempts`) `\| PENDING → CANCELLED` |
| Signing | `HMAC-SHA256(secret, f"ts={unix_timestamp}.{payload_json}")`, header `X-Platform-Signature: v1={hex}` |
| Replay protection guidance | Tenant systems should reject deliveries with `ts` > 5 minutes old |
| Retry / backoff | Exponential, capped by `max_attempts`; claim via `SELECT ... FOR UPDATE SKIP LOCKED` |
| Dead-letter | Retained 90 days; replay creates a **new** delivery row (`replay_of_delivery_id` set), original delivery's history stays immutable |
| Idempotency (consumer-facing) | `event_id` is the delivery's stable identity across retries/replays — tenant systems dedupe on it |
| Ordering | Not guaranteed across event types (matches §27.3's `sequence` gap-detection rationale) — consumers must be resilient to out-of-order delivery, consistent with the platform-wide eventual-consistency model (4G §12) |
| Response body capture | First 2KB only stored, to bound storage |

`POST /api/v1/webhook-endpoints` (register), `GET /api/v1/webhook-deliveries`, `POST /api/v1/webhook-deliveries/{id}/replay` are the resulting REST surface shape (endpoint design itself deferred to a Phase 6B+ Integrations/Webhooks document — this section only fixes the underlying delivery contract those endpoints must expose).

### 28.2 Inbound (External Providers → Platform)

Telephony/payment/integration provider callbacks land on dedicated, unauthenticated-by-JWT endpoints (verified instead by the provider's own signature scheme) and are recorded in `webhooks.inbound_webhook_events`, idempotent on `UNIQUE (organization_id, provider_slug, provider_event_id)` (5I §10). These endpoints follow the same SSRF/signing-verification discipline as §22 but are **not** rate-limited by the tenant quota system (§20) — they're governed by the provider's own delivery volume, with the platform's job being fast accept-and-enqueue (`RECEIVED → PROCESSING → PROCESSED|FAILED|SKIPPED`), never synchronous heavy processing inline.

### 28.3 Three Distinct Mechanisms — Not to Be Confused

| Mechanism | Direction | Trust boundary | Ordering | Delivery guarantee |
|---|---|---|---|---|
| API response | Client ↔ Platform | Synchronous, same request | N/A | Exactly the one response |
| WebSocket event | Platform → connected client the platform itself owns (browser tab, voice leg) | Inside the platform's session | Sequence-numbered per connection, gaps detectable | Best-effort, no resume for voice audio |
| Outbound webhook | Platform → tenant-owned external system, outside platform trust boundary | Signed, tenant-configured | Not guaranteed across event types | At-least-once, with dead-letter |

---

## 29. File / Media Transfer

**Standard pattern (reused from the already-implemented recording storage flow, 5C `recordings.storage_ref` + 3F's signed S3 URL, 15-min expiry):**

```
API                                    Object Storage
 │                                          │
 ├─ POST /api/v1/{resource}/upload-url ──►  (nothing yet — API creates a PENDING record + presigned PUT URL)
 │◄─ { upload_url, resource_id, expires_at (15 min) }
 │
 (client PUTs bytes directly to S3, never through the API)
 │
 ├─ POST /api/v1/{resource}/{id}/complete ► transitions PENDING → PROCESSING (triggers async scan/ingest job, §19)
 │
 └─ GET /api/v1/{resource}/{id}/download-url ► { download_url, expires_at (15 min) }
```

| Concern | Standard |
|---|---|
| Upload initiation | Client declares expected `content_type` and `max_size_bytes` in the presign request; the S3 policy embedded in the presigned URL enforces both — the API never proxies the file bytes. |
| Authorization | Presign request goes through the standard auth/authz pipeline (§9) exactly like any other POST; the presigned URL itself is the only thing that's unauthenticated (S3-native, time-boxed). |
| Content-type validation | Enforced at presign time (declared) and re-verified server-side after upload-complete (actual bytes' magic number checked before transitioning out of `PENDING`/`PROCESSING`). |
| Size limits | Per-resource-type, declared at presign time; the S3 bucket policy is the hard backstop, not client honesty. |
| Malware/security scanning hook | Async job (§19) runs between `upload complete` and `READY` — documents/recordings are never queryable/downloadable until this stage passes, mirroring the existing Knowledge/RAG ingestion state machine (`PENDING → PROCESSING → ... → READY | FAILED`, 5F §6). |
| Download authorization | Signed GET URL, 15-min expiry (matches the already-implemented recording-download pattern, 3F §13), re-validated against RBAC/tenant ownership at the moment the download-url endpoint is called — never a long-lived or publicly guessable URL. |
| Range requests | Supported natively by S3-signed URLs for audio scrubbing/playback — no API-layer involvement needed. |
| Anti-pattern (explicit prohibition) | No endpoint ever accepts or returns base64-encoded media inside a JSON body. No API response embeds a recording/document's raw bytes. This is absolute — enforced by response-model design (§10.2), not just documentation. |

No actual media endpoints are designed here — this section fixes the pattern every future Voice/Knowledge/CRM media endpoint (6B+) must follow.

---

## 30. API Versioning

- URL-path major versioning: `/api/v1/`, `/api/v2/`, etc. — a new major version is created only for breaking changes (§31.1); the old version keeps running through its published deprecation window.
- Event schema (`version` field, §27.3) versions independently of the URL path — an event type can gain a new version without forcing an API major-version bump, and vice versa.
- No minor/patch version in the URL — additive, backward-compatible changes ship into the current major version continuously (this is what backward compatibility (§31) exists to make safe).

---

## 31. Backward Compatibility

### 31.1 Breaking vs. Non-Breaking

| Breaking (requires new major version) | Non-breaking (safe within current version) |
|---|---|
| Removing a response field | Adding a new optional response field |
| Changing a field's type or shape | Adding a new endpoint |
| Changing an enum's semantics (not just adding a new value) | Adding a new *value* to an existing enum, where clients are documented to treat unknown enum values as "unrecognized, fall back gracefully" |
| Making an optional request field required | Adding a new optional request field with a safe default |
| Changing an endpoint's authorization requirement to be stricter | Loosening an authorization requirement (rare, but non-breaking by definition) |
| Changing what a 200 response means for existing callers | Adding a new HTTP method to an existing resource |
| Changing pagination default page size | Adding a new filter/sort field to the allow-list |

### 31.2 Deprecation Lifecycle

1. **Announce:** new version ships; old version marked deprecated in OpenAPI (`deprecated: true` + `Sunset` HTTP header on every response from the deprecated version) and in developer-facing docs.
2. **Compatibility period:** minimum 6 months (indicative default — adjust per actual partner-integration commitments once they exist; no partner contract data exists yet to derive a harder number from Phase 1–5).
3. **Sunset:** deprecated version returns 410 Gone after the compatibility period, with a `Link` header pointing to the migration guide.

Enums specifically: clients consuming a `status`/enum field are contractually required (documented in every domain API's spec) to treat an unrecognized value as "unknown, do not crash" — this is what lets Phase 5's TEXT+CHECK enum extensibility (5A §21.7 — deliberately chosen over native Postgres ENUM precisely so new states are cheap to add) translate into a genuinely non-breaking API change instead of an accidental breaking one.

---

## 32. OpenAPI / Documentation Standards

### 32.1 Every Endpoint Documents

Purpose, HTTP method + URL, authentication requirement, authorization (required permission string, §22), path/query parameters, headers (incl. `Idempotency-Key` where applicable), request body schema, response schema (success + every documented error), idempotency behavior, rate-limit class (§20), latency tier (§11), side effects (which events/webhooks it triggers), consistency behavior (sync vs. eventual, per §6/4G §12), audit behavior (`action_kind` emitted, §22), example request, example response.

### 32.2 FastAPI-Generated OpenAPI Reconciliation

**Decision (ADR-6A-06, §39):** FastAPI's auto-generated OpenAPI (from route decorators + Pydantic models) is the single machine-readable contract — there is no separately hand-maintained OpenAPI file to drift out of sync (DRY, per `CODING_STANDARDS.md`). Metadata this document requires that OpenAPI doesn't natively express (latency tier, idempotency class, audit action, permission required) is carried as **OpenAPI vendor extension fields** on each route:

```yaml
x-latency-tier: "A"
x-idempotent: true
x-permission-required: "contact:read"
x-audit-action-kind: "CONTACT_UPDATED"
x-rate-limit-class: "standard-crud"
```

A CI lint script verifies every non-internal route carries the required `x-*` fields before merge — this is how "manually designed API specification" and "FastAPI-generated OpenAPI" are reconciled without maintaining two documents.

---

## 33. API Contract Testing

| Category | What it verifies | Runs |
|---|---|---|
| Contract tests | Request/response schema conformance against the OpenAPI-derived contract (§32) | Every PR, per endpoint |
| Authorization tests | Role, tenant boundary, resource ownership — including the explicit cross-tenant "read another org's data by manipulating IDs" probes already modeled in Phase 5's Tenant Isolation Test Matrix (5B §38) | Every PR touching an endpoint or RLS-adjacent logic |
| Functional tests | Business rules, especially state-machine guard behavior (§17) | Every PR |
| Performance tests | p50/p95/p99 against the Tier A–E targets (§11) | CI on a schedule + pre-release gate |
| Load tests | Sustained + burst traffic against rate-limit (§20) and connection-pool (§13) assumptions | Pre-release, and after any change to pooling/limits |
| Failure tests | Timeout, dependency failure (DB/Redis/provider down) — confirming circuit breakers and fallback behavior (§21) degrade as designed, not silently | Pre-release |
| Security tests | IDOR, injection, privilege escalation, tenant isolation (extends 5B §38's DB-level matrix up through the API) | Every PR touching auth/authz/tenant-context code; full sweep pre-release |

Matches `CODING_STANDARDS.md`'s existing requirement ("Every feature requires Unit Tests, Integration Tests, Contract Tests; critical workflows require E2E tests") — Phase 6A adds the API-specific categories (authorization, performance, load, failure, security) as domain-specific instances of that same rule, not a competing testing philosophy.

---

## 34. Business Logic Boundaries

Reused exactly from the already-approved Phase 3A layered architecture (3A §2.1–2.2) — Phase 6A does not invent a competing layering:

```
Interface (REST router / WS handler / Pydantic schema)
  ↓
Application Service (Use Case, Port, DTO, UnitOfWork)
  ↓
Domain (Entity, Value Object, Domain Event, Domain Service)
  ↑ (implemented by)
Infrastructure (Repository, ORM mapping, provider Adapter)
  ↓
PostgreSQL / Redis / External Services
```

The API (Interface) layer's job, and only its job: authenticate, authorize, resolve tenant context, validate/normalize input, invoke exactly one Application Service use case, serialize the result, handle protocol concerns (status codes, headers, pagination cursors). It never: contains a business rule, duplicates a database invariant already enforced by a `SECURITY DEFINER` function or `CHECK` constraint, reaches into an unrelated bounded context's tables directly, or bypasses the layered call chain to "save a hop." Module boundary enforcement is already mechanical (import-linter CI gate, 3A §2.3) — Phase 6A's API layer lives entirely inside a bounded context's `interface/` package and is subject to the same gate.

---

## 35. Transaction Boundaries

**Rule:** never hold a database transaction open while waiting on an AI provider, telephony provider, webhook delivery, external HTTP call, or long-running job.

**Standard shape:**

```
validate (in-process, no I/O)
  ↓
short DB transaction (single aggregate write, via the guarded SECURITY DEFINER function where one exists)
  ↓
commit
  ↓
async / external processing (Celery enqueue, provider call, webhook dispatch) — outside the transaction
```

**Approved exceptions requiring true same-transaction atomicity** (reused exactly from 4G §12's "strong/same-transaction" list — Phase 6A does not add to this list unilaterally, since it's a domain-consistency decision, not an API-layer one):

- Create Organization + owner Membership
- Start Call + Conversation (`ConversationRef`)
- Transfer Ownership (two Memberships)
- Publish Agent + AgentVersion
- Publish Workflow + WorkflowVersion
- CSV import batch

Every other cross-aggregate effect is eventual, event-driven, with the documented lag targets already set (4G §12: `call.ended` → CRM Activity <5s, → Usage metering <10s, → Analytics projection <60s, → Webhook delivery <30s, `invoice.generated` → Notification <5min) — an API endpoint's synchronous response must never wait for these downstream effects to complete; it returns once its own aggregate's transaction commits.

---

## 36. Performance Anti-Patterns (Prohibited)

- `SELECT *` in any repository query (§13).
- N+1 query patterns in any list/serialization path (§13).
- Unbounded list endpoints (no pagination) or unbounded joins.
- Unbounded nested resource embedding (cap 20 items inline, §10.2).
- Huge JSON responses — no single response body exceeds 5MB (§15); large objects use signed URLs (§29).
- Synchronous external-provider calls on the Tier A/B request path for anything that could instead be async (§6).
- Long-held database transactions spanning an external call (§35).
- Blocking the asyncio event loop (CPU-bound work must go to a bounded `ThreadPoolExecutor`, per the already-implemented voice-gateway pattern, 3B §18.1).
- Blocking (non-async) HTTP clients inside async request handlers — `httpx` async client only.
- Repeated per-request token/permission database lookups instead of the established Redis cache (§9.1, §12).
- Cache stampedes — always single-flight via Redis `SETNX` lock for expensive regeneration (§19).
- Cross-tenant cache keys — every Redis key is tenant-namespaced (§19); a key without a tenant segment is only acceptable for the small platform-global reference-data allow-list.
- Unbounded/arbitrary search — no client-supplied `LIKE '%...%'` across arbitrary columns, no boolean query-expression language (§15).
- Arbitrary SQL-shaped filters accepted from clients (§15).
- Base64-encoded media inside a JSON request or response body (§29).
- Synchronous analytics aggregation on a transactional (Tier A/B) endpoint — analytics reads come from projections (§11 Tier C, 4G §3.1), never a live `GROUP BY` over OLTP tables mid-request.
- Non-idempotent POST operations auto-retried by any layer without an Idempotency-Key (§16, §21).
- A plain `SET` (instead of `SET LOCAL`) for `app.tenant_id` under PgBouncer transaction-mode pooling — this is not a style nit, it is a tenant-isolation bug waiting to happen (§13).

---

## 37. API Design Traceability

**Mandatory for every Phase 6B+ endpoint design**, no exceptions:

```
SRS requirement
  ↓
Bounded Context (Phase 4)
  ↓
Phase 5 entity / capability (table, function, state machine)
  ↓
API resource (this document's naming/URL rules, §8)
  ↓
Endpoint (method + path + latency tier, §11)
  ↓
Permission (RBAC string, §22)
  ↓
Business rule (invariant, §17/§34)
  ↓
Database operation (query/transaction shape, §13/§35)
  ↓
Response / Event (envelope, §10; WS event or webhook, §27–28)
```

A Phase 6B+ document that cannot fill in every link of this chain for a proposed endpoint has either found a genuine Phase 5 gap (document it as an API-DESIGN DEPENDENCY, per §4's convention) or is designing an endpoint that doesn't belong in this platform's domain model — either way, it stops and escalates rather than inventing an endpoint the chain doesn't support.

---

## 38. Document Structure

*(This section is the table of contents realized as the document above — §1 through §44, per the governing task brief's required structure. No separate restatement needed here beyond confirming structural compliance: all 42 required sections are present.)*

---

## 39. Architecture Decision Records

| ID | Decision | Alternatives considered | Rationale (condensed) | Status |
|---|---|---|---|---|
| ADR-6A-01 | REST over GraphQL | GraphQL | Domain is already resource-shaped by 56 aggregates; avoids a second query-execution/caching model; heavy-read needs met by CQRS projections instead (§7.1) | **Decided** |
| ADR-6A-02 | `/api/v1/` namespace | `/v1/` bare, no prefix | Reconciles SRS's `/v1/...` wording with the need to distinguish API traffic from the Next.js app at the shared ingress (§7.2) | **Decided** |
| ADR-6A-03 | Cursor pagination as default | Offset-only, hybrid | Phase 5's own partitioned high-volume tables make large-OFFSET scans expensive/unstable; offset kept only for small reference tables (§14) | **Decided** |
| ADR-6A-04 | `{data, meta}` / `{error}` response envelope | Bare resource, minimal-response-only | Uniform client branching, negligible overhead vs. CRUD payload size; WS/media transfer explicitly excluded (§10.1) | **Decided** |
| ADR-6A-05 | Raw WebSocket for all realtime, not just voice | Socket.IO for browser-facing channels (per `TECH_STACK.md`) | One realtime stack, one auth/tenant path; Socket.IO's fallback-transport/rooms not needed given existing Redis-backed tenant isolation | **REVIEW REQUIRED — needs frontend/product sign-off, conflicts with an already-approved TECH_STACK.md entry (§40, Risk R-1)** |
| ADR-6A-06 | FastAPI-generated OpenAPI + vendor extension fields, no separately hand-maintained spec | Fully manual OpenAPI spec | DRY; avoids spec drift; extension fields (`x-latency-tier`, etc.) carry what OpenAPI can't natively express (§32.2) | **Decided** |
| ADR-6A-07 | Idempotency-Key storage: Redis primary + existing Phase 5 unique constraints as backstop | Postgres-only idempotency table | Reuses already-implemented DB-level uniqueness (call_jobs, usage_events, inbound_webhook_events) instead of a new generic table; Redis gives the latency win (§16) | **Decided** |
| ADR-6A-08 | Concurrency control via guarded state-transition functions (action endpoints) + weak `updated_at`-ETag for free-form fields, no new `version` column | Add `version_number` columns to Phase 5 (rejected — would modify frozen schema); ETag-only everywhere | Matches what Phase 5 actually implemented (CAS inside `SECURITY DEFINER` functions) without touching frozen schema (§17) | **Decided**, with a flagged future-schema-improvement note |
| ADR-6A-09 | Service-to-service auth via short-lived internal-signed JWT, no new DB table | mTLS between services; new service-account table (would modify Phase 5) | No Phase 5 table exists for this; a signature-verified JWT needs no DB lookup and reuses existing `actor_type` audit vocabulary (§23.4) | **REVIEW REQUIRED — new mechanism not present in any frozen document (§40, Risk R-2)** |
| ADR-6A-10 | Generalize the voice-specific circuit breaker (Redis `providerhealth:{provider}`) to all external dependencies | Per-dependency bespoke breakers; pod-local breakers | Same rationale 3B already gives for voice — a pod-local breaker "rediscovers every outage independently on every pod" (§21) | **Decided** |

---

## 40. Risks / Open Questions

| ID | Item | Why it matters | Owner / next step |
|---|---|---|---|
| R-1 | **WebSocket vs. Socket.IO conflict.** `TECH_STACK.md` lists Socket.IO for the frontend; Phase 3A (line 53) already flagged this as unresolved and explicitly deferred it to Phase 6. This document recommends raw WebSocket platform-wide (ADR-6A-05) but that recommendation revises an already-approved tech-stack entry. | Determines the WS client library, reconnect/backoff implementation, and whether a Socket.IO-compatible gateway is needed for non-voice channels. | Needs explicit frontend/product sign-off before ADR-6A-05 can move from "recommended" to "decided." |
| R-2 | **No service-to-service auth mechanism exists in any frozen document.** §23.4 proposes a stateless internal-JWT mechanism requiring no schema change, but it is a genuinely new addition, not a restatement of an existing decision. | Affects how Worker/Voice-Gateway/Core-API internal calls (if any are added in 6B+) authenticate. | Confirm with platform security owner before treating as final; low risk to change later since it's schema-free. |
| R-3 | **India/data-residency requirement is not a hard SRS requirement**, only an open question deferred to Phase 5/22 (SRS §6). Phase 4I's `RegionRef`/`DataResidencyProfile` abstraction (§9.1–9.2) gives the API a clean seam to route through if/when a hard requirement lands, but no API-visible region-selection contract is defined here. | If a hard data-residency requirement emerges, it should not require an API breaking change — confirm the abstraction holds. | Revisit when Phase 22 (Deployment) or legal/product closes the open SRS question. |
| R-4 | **Redis client-side connection pool size/timeout was unspecified in Phase 3.** §21 introduces defaults (connect 1s, command 2s) as a Phase 6A addition, since no prior document set them. | Affects Tier A/B latency budget (§12) if the defaults prove wrong under load. | Validate against real load-test data once implemented; adjust here if wrong — this is a Phase 6A-owned number, not a Phase 3 restatement. |
| R-5 | **TTS has no approved fallback vendor** (3B Review Note 4, still open). | A TTS provider outage has no failover path today — affects Tier E reliability, not directly an API-layer decision, but the retry table in §21 inherits this gap ("no retry can fix a missing fallback"). | Owned by Phase 9 (Voice Pipeline) / provider-integration work, not Phase 6A — flagged here for downstream awareness only. |
| R-6 | **Async completion SLAs (§18.5) are indicative placeholders**, not measured commitments — no provider throughput data exists yet to derive firm numbers. | Setting a firm SLA now risks being wrong once real embedding/dialing throughput is measured. | Each owning Phase 6B+ / Phase 10-13 document must confirm or revise its specific job-completion SLA against real data. |
| R-7 | **Weak ETag concurrency control** (`updated_at`-derived, ADR-6A-08) is less precise than a dedicated version counter for high-contention, non-state-machine-guarded resources. | Two updates within the same timestamp granularity are indistinguishable — a narrow correctness gap, not currently known to affect any specific resource. | Future Phase 5 revision (out of this document's authority) could add `version_number` columns if this proves insufficient in practice. |
| R-8 | **Auth-endpoint abuse step-up (CAPTCHA/adaptive MFA)** is not specified in any Phase 1–5 document. | Login/password-reset brute-force defense today relies solely on rate limiting (§20) and account lockout counters (5B `failed_login_count`) — no adaptive challenge layer. | Flagged for whichever Phase 6B document designs the Auth API surface (or Phase 8, Authentication & Authorization) to close explicitly. |

---

## 41. Phase 6A Acceptance Criteria

- [x] API architecture defined (§6)
- [x] REST standards defined (§7)
- [x] URL conventions defined (§8)
- [x] Request/inbound pipeline defined (§9)
- [x] Response/outbound pipeline defined (§10)
- [x] Latency classes defined (§11)
- [x] p50/p95/p99 targets defined (§11)
- [x] Timeout strategy defined (§21)
- [x] Database performance standards defined (§13)
- [x] Pagination defined (§14)
- [x] Filtering defined (§15)
- [x] Sorting defined (§15)
- [x] Search defined (§15)
- [x] Payload limits defined (§10.4, §15, §36)
- [x] Idempotency defined (§16)
- [x] Concurrency defined (§17)
- [x] Async operations defined (§19)
- [x] Caching defined (§19)
- [x] Rate limiting defined (§20)
- [x] Retry/circuit breaker rules defined (§21)
- [x] Tenant context defined (§23)
- [x] Security standards defined (§22)
- [x] Error contract defined (§24)
- [x] Observability defined (§25)
- [x] Performance metrics defined (§26)
- [x] WebSocket/realtime standards defined (§27)
- [x] Webhook standards defined (§28)
- [x] Media/file transfer defined (§29)
- [x] Versioning defined (§30)
- [x] Backward compatibility defined (§31)
- [x] OpenAPI strategy defined (§32)
- [x] Contract testing defined (§33)
- [x] Business logic boundary defined (§34)
- [x] Transaction boundary defined (§35)
- [x] Anti-patterns defined (§36)
- [x] Traceability defined (§37)
- [x] ADRs recorded (§39)
- [x] Risks/open questions documented (§40)
- [x] No Phase 5 changes (§4 — confirmed; every DB-touching rule cites and reuses frozen Phase 5 facts, never redesigns them)
- [x] No Phase 6 business APIs prematurely designed (§3 — confirmed; zero concrete endpoints for Auth/Voice/Agent/CRM/Campaign/Billing/Knowledge/Workflow/Integrations/Webhooks/Plugins/Analytics appear anywhere in this document)

All content-completeness criteria are satisfied. Two ADRs (ADR-6A-05, ADR-6A-09) are marked **REVIEW REQUIRED** pending stakeholder sign-off (§40, R-1/R-2) rather than final decisions — this is what determines the overall status below.

---

## 42. Final Approval Status

### PHASE 6A STATUS: **REVIEW REQUIRED**

All 42 required content sections are complete, internally consistent, and traceable to Phase 1–5 source documents with citations. Phase 5 was not modified. No business-domain endpoints were designed. However, this document is not marked APPROVED/FROZEN because it contains two decisions that go beyond restating existing frozen architecture and require explicit stakeholder confirmation before 6B+ can safely build on them without risk of rework:

1. **ADR-6A-05** (raw WebSocket platform-wide) revises an entry in the already-approved `TECH_STACK.md` (Socket.IO) — needs frontend/product sign-off.
2. **ADR-6A-09** (internal service-to-service JWT mechanism) introduces a mechanism absent from every frozen document — needs platform security review.

Once R-1 and R-2 (§40) are resolved (either confirmed as written or amended), this document should be re-issued as **APPROVED / FROZEN** and become binding on 6B onward. Every other section is ready to govern immediately.

---

## 43. Implementation Summary

**1. Files created**
- `docs/phase-06-api-design/6A-API-Architecture-and-Standards.md` (this document)

**2. Files modified**
- None. Phase 5 (5A–5J, 5K, 5K.1) untouched, as required.

**3. Major architecture decisions**
- REST (not GraphQL) under `/api/v1/`, with a distinct `/api/internal/v1/` for service-to-service traffic and `/ws/v1/` for realtime (§7–8, ADR-6A-01/02).
- Cursor pagination as default; offset reserved for small reference tables (§14, ADR-6A-03).
- `{data, meta}` / `{error}` response envelope, minimal overhead, excluded from WS/media (§10, ADR-6A-04).
- Four-way communication model: sync REST / async job / WebSocket / outbound webhook, each with explicit "use when" rules (§6).
- Concurrency control built on Phase 5's actual mechanism (guarded `SECURITY DEFINER` state transitions) rather than inventing version columns Phase 5 doesn't have (§17, ADR-6A-08).

**4. Latency/performance decisions**
- Five-tier latency model (Interactive/Operational/Heavy-Read/Async-Submit/Realtime) derived from NFR-PERF-001/002 and the existing 3B voice-turn budget, not invented numbers (§11).
- Tier A p99 = 300ms is a direct restatement of NFR-PERF-002, broken into a per-layer budget (§12).
- Database rules (tenant-first indexes, no `SELECT *`, cursor over offset, short transactions, `SET LOCAL` under transaction-mode PgBouncer) all traced to specific 5A/3F citations (§13).

**5. Inbound/outbound decisions**
- Canonical middleware pipeline order resolved (§9.1) — this was an explicit gap in Phase 3 (file-listing order only, no stated execution order); Phase 6A closes it with justification for each ordering choice.
- Two-tier rate limiting (coarse IP-based at NGINX, fine tenant-aware at the app layer) reusing the existing 3F/3E split rather than inventing a third scheme (§20).

**6. Security decisions**
- Tenant context is always server-derived (JWT claim / API-key lookup), never client-supplied — directly enforced by Phase 5's RLS design (§22–23).
- Full security checklist (TLS, RBAC, input validation, output filtering, secret handling, audit, webhook signing, SSRF, injection, mass assignment, IDOR, rate limiting) mapped to specific existing Phase 5 mechanisms wherever one exists, flagged as new only where genuinely new (§22).

**7. Async/realtime decisions**
- Generic `/api/v1/jobs/{job_id}` contract that *projects* from existing Phase 5 job-tracking tables rather than creating a new generic jobs table (§18).
- WebSocket event envelope formalized for non-audio realtime channels, addressing a flagged Phase 3A gap (§27.3).
- Outbound webhook contract reused exactly from the fully-implemented 5I schema; inbound webhook handling addressed separately (§28).

**8. Open questions** (§40, full detail)
- R-1: WebSocket vs. Socket.IO — needs frontend/product decision.
- R-2: Service-to-service auth mechanism — needs security review.
- R-3: India data-residency — inherited open SRS item, not resolved here.
- R-4: Redis client pool defaults — newly set by this document, needs load-test validation.
- R-6: Async completion SLAs — placeholders pending real throughput data.
- R-7: Weak ETag concurrency — narrower gap than a version counter, flagged for future Phase 5 consideration.
- R-8: Auth abuse step-up — unaddressed in any prior phase.

**9. Risks**
- R-5 (no TTS fallback vendor) and R-3 (data residency) are pre-existing risks this document inherits and surfaces but does not own resolving.
- The two REVIEW REQUIRED ADRs (R-1, R-2) are the primary risk to 6B+ velocity if left unresolved — they touch foundational auth/realtime plumbing every subsequent domain API will depend on.

**10. Conflicts discovered with Phase 1–5**
- `TECH_STACK.md` (Socket.IO) vs. the Voice Gateway's already-implemented raw WebSocket (3B) — not a contradiction within Phase 1–5 itself (TECH_STACK.md is frontend-general, 3B is voice-specific backend), but a gap Phase 6 was explicitly tasked (3A line 53) with resolving; this document proposes a resolution but flags it for sign-off rather than declaring it unilaterally.
- Minor terminology inconsistency noted between 3E's LLD-level description of webhook delivery statuses/signature header (`RETRYING`, `X-Platform-Signature: sha256=...`) and 5I's actual implemented DDL (`DELIVERING`, `X-Platform-Signature: v1=...`) — this document treats 5I (the frozen database implementation) as authoritative per the source-of-truth rule (§1 of the governing task), and used its exact vocabulary throughout §17, §21, §28.

---

**STOP — Phase 6A complete. Phase 6B not started.**
