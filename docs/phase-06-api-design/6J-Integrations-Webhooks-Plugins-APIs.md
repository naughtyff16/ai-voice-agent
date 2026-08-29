# 6J — Integrations, Webhooks & Plugins APIs

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6J

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6J-Integrations-Webhooks-Plugins-APIs.md |
| Phase | 6J (tenth document of Phase 6 — API Design) |
| Depends on | Phase 1 SRS, Phase 2 HLA, Phase 3 LLD, Phase 4F DDD (§6–§9, §12–§13), Phase 5B/5H/5I/5J (FROZEN), Phase 6A (FROZEN), Phase 6B (FROZEN), Phase 6D–6I (FROZEN) |
| Status of dependencies | Phase 5 is APPROVED/FROZEN/PRODUCTION BASELINE READY. Phase 6A–6I are APPROVED/FROZEN. No changes made to any of them by this document. This document's own additive amendment (`5K/migrations/101_5I1.sql`) touches only the `integrations`/`plugins`/`webhooks` schemas 5I itself defined — no other Phase 5 schema is touched. |
| Author scope | Integration, webhook (outbound + inbound), and plugin API contracts only. No workflow-execution, CRM, campaign, call, or knowledge-domain endpoints are (re)designed here. |
| Supersedes | Nothing |
| Governed by | 6A (platform-wide API standards — binding), 6B (auth/authz — binding) |
| Unblocks | 6I §23/§54 item 5 — `WEBHOOK`/`API_CALL` workflow node execution (contract-defined, execution-blocked pending this document, per ADR-6I-04) |
| Original date | 2026-08-29 |
| **Remediation pass 1** | 2026-08-29 (same day) — strict corrective pass following independent engineering/security review. 7 P0 and 17 P1/P2 findings addressed; `101_5I1.sql` authored, not yet live-validated. |
| **Remediation pass 2 (FINAL)** | **2026-08-29 (same day) — database closure and live PostgreSQL 18.6 validation pass**, following a second independent review that found 3 further P0s in pass 1's migration. All closed via `101_5I1.sql` amended in place (§55 ADRs, §56 DEP table); a major, live-discovered, platform-wide-impact defect (`gen_uuid_v7()` missing `search_path`, affecting 84 of 99 `SECURITY DEFINER` functions across the entire 001-100 baseline — not introduced by 6J) was found and fixed in the same pass. Full adversarial live-test matrix (tenant-forgery, OAuth, integration/plugin lifecycle, webhook rotation, concurrency race, RLS, privileges, `SECURITY DEFINER` inventory, targeted regression) — **all PASS**, PostgreSQL 18.6 (engine-version deviation from the requested 16, disclosed). Full evidence: `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`. **Final status: `PHASE 6J — IMPLEMENTATION READY`** (§62), with two explicitly disclosed, non-blocking-per-scope items: SSRF/application-layer tests (no deployed app code exists in this repo to test against) and a 6I cross-phase schema-compatibility item for plugin-version-pinning (6I is frozen; disclosed, not silently resolved). |

---

## 2. Purpose

This document is the implementation-ready API contract for the platform's **Integration**, **Webhook**, and **Plugin** bounded contexts — the three schemas (`integrations`, `webhooks`, `plugins`) delivered, fully DDL-complete and validated, by Phase 5I. It defines every REST endpoint a backend engineer needs to expose tenant-facing connector management, outbound event notification, inbound provider callback ingestion, and platform-reviewed plugin installation — without inventing schema, redesigning frozen architecture, or silently resolving genuine gaps between what Phase 5I implemented and what a complete API surface requires.

It is written to the same rigor bar as 6A/6B/6I: every endpoint has an explicit auth/authz/idempotency/concurrency/audit contract; every claim about what the database can do is checked against the executed DDL in `docs/phase-05-database-design/5I-Integrations-Webhooks-Plugins-Schema.md` (§28), not against the conceptual model in 4F alone. Where the executed DDL does not support a capability the task brief or 4F's DDD model implies, that gap is disclosed as a **PHASE 5 SCHEMA GAP** (§56) — never silently papered over with an unauthorized direct SQL statement or an invented SECURITY DEFINER function this document has no authority to create.

---

## 3. Scope

**In scope:**
- Integration provider catalog discovery (`integrations.integration_definitions`)
- Tenant integration connection lifecycle, credential/OAuth handling, health, testing, sync (`integrations.integration_connections`, `oauth_attempts`, `integration_health`)
- Outbound webhook subscription management, delivery observability, and replay (`webhooks.webhook_endpoints`, `webhook_deliveries`)
- Inbound provider webhook ingestion contract (`webhooks.inbound_webhook_events`) — the generic mechanism; provider-specific ACL translation for contexts that own their own domain (e.g., 6D/Voice for Exotel) is out of scope here, per §7
- Plugin catalog, manifest, installation lifecycle, permissions, and the plugin↔workflow execution boundary (`plugins.plugins`, `plugin_versions`, `plugin_installations`, `plugin_executions`)
- SSRF/egress-control contract for every tenant-configurable outbound URL this document's resources create (webhook targets, plugin base URLs) and the credential/egress-control seam 6I's `WEBHOOK`/`API_CALL` workflow nodes depend on

**Out of scope (explicitly deferred to their owning phase):**
- Workflow definitions, executions, triggers, and node evaluation (6I) — 6J supplies the integration capability contract only, per §7
- CRM/lead domain records (6G), campaign domain records (6H), call/telephony domain records (6D), agent domain (6E), knowledge base/document domain (6F) — 6J connects to them, never redefines their resources
- Billing ledger semantics, invoices, plan/quota configuration (future 6K) — 6J may emit usage facts, never designs billing
- Analytics projections/dashboards (future 6L)
- A public third-party plugin marketplace, developer self-service publishing UI, or any form of tenant-uploaded arbitrary executable code — 5I/4F already settle plugins as external HTTP services the platform calls out to under a signed, capability-scoped contract (§25); this document does not introduce a competing execution model
- Any change to Phase 5 (schema, RLS, functions, triggers, indexes, migrations) or to Phase 6A/6B/6D–6I

---

## 4. Non-Goals

- No in-process plugin code execution, sandboxing, or WASM/container-per-plugin runtime is designed. 4F §9.3 and 5I §24 already establish plugins as external HTTP callees; this is restated and made binding for the API surface (§25), not reopened.
- No Kafka, service mesh, separate integration microservice, or bespoke distributed-transaction coordinator. The modular monolith + Redis Streams + `audit.domain_event_outbox` transactional-outbox architecture (6A §6, 6C, 5J migration `077_5J1`) is reused as-is.
- No new RBAC permission strings beyond what 5B already seeds (`integration:read/manage`, `webhook:read/manage`, `plugin:read/install/manage`) — confirmed sufficient for every endpoint this document defines (§33).
- No generic "run arbitrary code" workflow action. §30's SSRF/egress contract is scoped exactly to what 6I's `WEBHOOK`/`API_CALL` node types and this document's own webhook/plugin registration flows need.
- No redesign of 6D's Exotel/telephony provider abstraction or its own inbound callback endpoint — 6J owns the generic inbound-webhook table and verification discipline; 6D's callback handler is a consumer of that shared mechanism, not a resource 6J re-specifies (§24.5).

---

## 5. Source-of-Truth Documents

| Document | What this document takes from it |
|---|---|
| `5I-Integrations-Webhooks-Plugins-Schema.md` | Authoritative schema: tables, columns, CHECK constraints, SECURITY DEFINER functions, grants, RLS, indexes, ADRs (§28 DDL is cited by exact function/table name throughout) |
| `4F-Billing-Usage-Integrations.md` §6–9, §12–13 | Aggregate/DDD vocabulary, domain events, webhook topic catalog (§8.4), plugin security model (§9.3), sequence diagrams |
| `5B-Identity-Organization-Multitenancy-Security.md` | Permission catalog (`integration:*`, `webhook:*`, `plugin:*`), role→permission seed grants |
| `5H-Billing-Usage-Schema.md` | `billing.usage_events` idempotency shape, referenced only for the forward billing-handoff seam (§46) |
| `5J-Analytics-Audit-Schema.md` | `audit.audit_events` (`action_kind` vocabulary, open TEXT+CHECK-length, not a closed enum), `audit.domain_event_outbox` (migration `077_5J1.sql`) — the transactional outbox this document reuses |
| `6A-API-Architecture-and-Standards.md` | Binding platform-wide conventions: envelope, pagination, idempotency, concurrency, error contract, latency tiers, async job pattern, webhook contract summary (§28), URL naming for webhook resources (§8.3, §28.1) |
| `6B-Authentication-and-Authorization-API.md` | Auth architecture, API key model, internal service-to-service JWT (§17, ADR-6B-11 central internal token issuer) |
| `6D-Voice-Call-Agent-APIs.md` | Confirms Exotel/telephony inbound callbacks reuse `webhooks.inbound_webhook_events` without 6J redesigning 6D's own endpoint (§10.4 there) |
| `6I-Workflow-APIs.md` §23, §54 item 5 | The exact dependency 6J must close: credential-binding + egress-control infrastructure for `WEBHOOK`/`API_CALL` workflow nodes |

---

## 6. Terminology

| Term | Meaning (this document's exact usage) |
|---|---|
| **IntegrationDefinition** | Platform-owned, read-only catalog entry for a supported external system (`integrations.integration_definitions`). Not tenant-specific. |
| **IntegrationConnection** | A tenant's configured instance of an IntegrationDefinition (`integrations.integration_connections`). Carries `credential_ref`, never a raw secret. |
| **OAuthAttempt** | A single, single-use, time-boxed OAuth authorization-code-flow attempt (`integrations.oauth_attempts`). |
| **IntegrationHealth** | Durable per-connection health/failure counters (`integrations.integration_health`). |
| **WebhookEndpoint** | A tenant-registered outbound HTTPS destination + topic subscription (`webhooks.webhook_endpoints`). |
| **WebhookDelivery** | One attempted (and retried) delivery of one event to one WebhookEndpoint (`webhooks.webhook_deliveries`, partitioned). |
| **InboundWebhookEvent** | A durable, deduplicated record of one inbound provider callback (`webhooks.inbound_webhook_events`). |
| **Plugin** | Platform-reviewed registry entry for an externally-hosted HTTP integration (`plugins.plugins`). |
| **PluginVersion** | An immutable-once-approved manifest version of a Plugin (`plugins.plugin_versions`). |
| **PluginInstallation** | A tenant's activated instance of a specific PluginVersion (`plugins.plugin_installations`). |
| **PluginExecution** | One recorded invocation of an installed plugin capability (`plugins.plugin_executions`). |
| **`credential_ref`** | An opaque string of the form `secret_manager://...`. Never a plaintext secret. Enforced by DB CHECK on every column that holds one. |
| **Topic** | A webhook subscription filter string (`webhook_endpoints.topics TEXT[]`), e.g. `call.completed`. Not a DB enum — free text, forward-compatible (5I §12). |
| **Egress-control adapter** | The SSRF-safe HTTP client this document specifies (§30) for every tenant-configured outbound URL (webhook delivery, plugin callout, and the seam 6I's `WEBHOOK`/`API_CALL` nodes consume). |

---

## 7. Bounded Context Ownership

### 7.1 6J Owns

- `IntegrationDefinition` catalog read APIs
- `IntegrationConnection` lifecycle, credential/OAuth orchestration APIs, health, test, sync-trigger APIs
- `WebhookEndpoint` subscription management APIs
- `WebhookDelivery` observability + replay APIs
- `InboundWebhookEvent` — the generic ingestion mechanism (verification discipline, dedup key, status lifecycle) any provider-callback consumer builds on
- `Plugin`/`PluginVersion` catalog + manifest read APIs
- `PluginInstallation`/`PluginExecution` lifecycle and execution-boundary APIs
- The egress-control/credential-binding contract 6I's `WEBHOOK`/`API_CALL` nodes and Plugin `TOOL_CALL` capability invocations both consume (§30)

### 7.2 6I Owns (Workflow) — Not Redesigned Here

Workflow definitions, `WorkflowVersion`, `WorkflowExecution`, node evaluation, directive production, and the `TOOL_CALL`/`WEBHOOK`/`API_CALL` node **execution** itself. 6J supplies the **capability contract** (credential resolution + SSRF-safe HTTP execution) those two node types call into; 6J never calls `WorkflowRuntimeService`, never reads/writes `workflow.workflow_executions`, and never duplicates 6I's `node_execution_claims` idempotency mechanism (6I §63.2, already resolved there for `TOOL_CALL`/`TRANSFER`/`HUMAN_TRANSFER`). See §30.

### 7.3 6G Owns (CRM/Leads) — Not Redesigned Here

`crm.contacts`, `crm.deals`, and all CRM domain writes. An `IntegrationConnection` to an external CRM (Salesforce, HubSpot) only produces domain **commands** (`CreateContact`, `UpdateDeal`) that 6G's own application services execute via 4F §6.3's Anti-Corruption Layer pattern — 6J's provider-specific ACL adapters translate wire format into those commands and stop there.

### 7.4 6H Owns (Campaigns) — Not Redesigned Here

Campaign resources and execution. 6J may expose campaign-related webhook topics (`campaign.started`, `campaign.completed` — already in 4F §8.4's governed catalog) and, in the future, campaign-triggered integration sync — it never defines a campaign resource or campaign state machine.

### 7.5 6D Owns (Calls/Telephony) — Not Redesigned Here

`voice.call_sessions` and telephony provider abstraction (4B §21 ACL). Exotel's own inbound status callbacks already flow through `webhooks.inbound_webhook_events` per 6D's own design (6D §10.4, confirmed at 6D lines 57/1092/1653/1728: *"not a redesign of 6A §28.2/5I's generic inbound-webhook mechanism — a statement of how Voice's telephony callbacks fit inside it"*). 6J owns the shared table's generic contract (idempotency key shape, verification discipline, status vocabulary); 6D owns its own dedicated inbound endpoint path, its own Exotel-signature verification, and the Voice ACL that turns a validated callback into `InitiateCall`/`CallEnded` commands. 6J does not design or re-expose 6D's telephony callback endpoint.

### 7.6 6E Owns (AI Agents) — Not Redesigned Here

Agent/AgentVersion domain. Out of 6J's scope entirely; no integration in this document references an Agent resource directly.

### 7.7 6F Owns (Knowledge/RAG) — Not Redesigned Here

Knowledge base and document lifecycle (`PENDING → PROCESSING → ... → READY | FAILED`, 6A §29, 5F). 6J may, in the future, supply external-source connectors (Google Drive, SharePoint) whose sync writes into 6F's ingestion pipeline via a `DocumentUploadRequested`-shaped command — no such connector is designed here (no `IntegrationDefinition` for one exists in the platform-seeded catalog today, §9), and no knowledge-domain endpoint is defined in this document.

### 7.8 Cross-Context Communication

```
IntegrationConnection sync / InboundWebhookEvent processing
    → domain command (CreateContact, UpdateDeal, RecordUsageEvent, ...)
    → owning bounded context's own Application Service (6G/6H/6D/6F, never 6J's own tables)

Any domain event (Voice, CRM, Campaign, Billing, Workflow, Knowledge...)
    → audit.domain_event_outbox INSERT (same DB transaction as the state change, 6C precedent)
    → outbox-publisher worker (audit.fn_claim_outbox_events / fn_mark_outbox_published)
    → Redis Streams topic
    → WebhookDispatchService (4F §8.3) matches topic against active WebhookEndpoints
    → webhooks.webhook_deliveries INSERT (one row per matching endpoint)
    → delivery worker (webhooks.fn_claim_delivery / fn_delivery_succeeded / fn_delivery_failed)
    → egress-control adapter (§30) → tenant's HTTPS endpoint

External provider webhook
    → 6J's generic inbound endpoint (or 6D's dedicated telephony endpoint, reusing the same table)
    → provider signature verification (§24.2)
    → webhooks.inbound_webhook_events INSERT (idempotent: org + provider_slug + provider_event_id)
    → async processing worker
    → owning bounded context's ACL → domain command
```

No cross-schema foreign key exists anywhere in this flow (5A §2.2, reused). Every reference across a bounded-context boundary is a plain UUID field with no DB-level joinability guarantee — exactly the same discipline 4F §6.3 and 6A §8.1 already establish platform-wide.

---

## 8. Integration Domain Model

### 8.1 Resource Ownership

| Resource | Owner | `organization_id` | RLS | Client-visible? |
|---|---|---|---|---|
| `IntegrationDefinition` | Platform (seeded by `app_platform_admin` at bootstrap, §31) | — (NULL, global) | No — public read, `is_active` filtered | Yes, read-only |
| `IntegrationConnection` | Tenant | YES | YES, `ENABLE + FORCE` | Yes |
| `OAuthAttempt` | Tenant, ephemeral (10-min TTL) | YES | YES | Only its derived `authorize_url`/status; the row itself is never directly listable by clients (§13) |
| `IntegrationHealth` | Tenant, system-maintained | YES | YES | Yes, read-only |

**A provider is platform-global; a connection is tenant-owned** (4F §6.1–6.2, unchanged). One `IntegrationDefinition` row exists per supported external system; every tenant that connects to it gets its own `IntegrationConnection` row with its own `credential_ref`.

### 8.2 Can One Organization Have Multiple Connections to the Same Provider?

**No, in V1.** `integrations.fn_create_integration_connection()` (5I §28, migration `061`) enforces, via `SELECT ... FOR UPDATE` before INSERT: at most one **non-terminal** (`status NOT IN ('DISCONNECTED','FAILED')`) connection per `(organization_id, definition_id)`. A second `POST .../connections` call for the same provider while a non-terminal connection exists raises a DB exception, surfaced as `409 INTEGRATION_ALREADY_CONNECTED` (§35). This is 5I's own **ADR-5I-007** / **ODD-5I-01** (`OQ-4F-07`), explicitly left open for Product to reconsider — this document does not relax it; doing so would require a Phase 5 migration removing/relaxing the `SELECT FOR UPDATE` check inside `fn_create_integration_connection()`, which is out of this document's authority.

### 8.3 External Account Identity

`integration_connections.external_account_ref` (opaque provider-side account identifier, e.g. a Salesforce org ID) and `external_account_name` (`pii:name`, display-only) are populated by the Application Service after OAuth token exchange or, for non-OAuth connections, from the provider's own account-lookup API. Neither is a platform-issued identifier — they exist purely for tenant-facing display ("Connected as: acme-corp.my.salesforce.com") and for `idx_ic_ext_account`'s duplicate-account detection at the application layer (the DB does not enforce external-account uniqueness — see §56 DEP-6J-03).

### 8.4 What Is Exposed vs. Internal-Only

| Column | Client-visible | Reason |
|---|---|---|
| `credential_ref` | **Never** | Opaque secret reference; structurally excluded from every response model (§12) |
| `configuration` (JSONB) | Yes, minus any key the provider's config schema marks `secret: true` (§9.3) | Non-secret operational config (e.g. `salesforce_instance_url`) |
| `external_account_ref` | Yes | Tenant needs to see which external account is connected |
| `last_sync_error` | Yes, capped at the DB's own 1000-char bound | Truncated/sanitized already at the DB layer (5I FIX-11); still passed through the platform's generic untrusted-content handling (§35) |
| `connected_by_ref` | Yes, resolved to a display name by the API layer | Audit-adjacent, not sensitive |

### 8.5 Auth Method → Credential Handling

| `auth_type` (`integration_definitions.auth_type`) | Connection creation flow |
|---|---|
| `OAUTH2` | `POST .../connections` creates a `CONNECTING` placeholder row + `POST .../connections/{id}/oauth/authorize` (§13) starts the authorization-code flow; credential is stored only after callback + token exchange |
| `API_KEY` | `POST .../connections` accepts the key directly in the request body; the Application Service exchanges it for a `credential_ref` via the secret manager **before** calling `fn_create_integration_connection()` — the raw key is never itself persisted to Postgres (§12.3) |
| `BASIC` | Same as `API_KEY`, with a username+password pair exchanged for one `credential_ref` |
| `CUSTOM` | Provider-specific; the `IntegrationDefinition.configuration_schema` (§9) declares which fields are secret vs. plain config, and the same secret-manager-exchange-before-INSERT discipline applies |

### 8.6 Connection Lifecycle State Machine (Authoritative — 5I, Not Reinvented)

```
CONNECTING → ACTIVE          (credential granted: OAuth callback success, or immediate for API_KEY/BASIC/CUSTOM)
CONNECTING → FAILED          (terminal — OAuth denied, or initial credential validation failed)
ACTIVE → ACTIVE              (credential refresh / rotation — status unchanged)
ACTIVE → DEGRADED            (sync failure or credential-expiry auto-detected by health tracking, §14)
DEGRADED → ACTIVE            (credential refresh succeeds, or manual reconnect)
DEGRADED → DISCONNECTED      (terminal — tenant disconnects)
ACTIVE → DISCONNECTED        (terminal — tenant disconnects)
FAILED → (none)              (terminal — tenant must create a new connection)
DISCONNECTED → (none)        (terminal — tenant must create a new connection)
```

Exact values reused unchanged from 5I §8 / `chk_ic_status`: `CONNECTING`, `ACTIVE`, `DEGRADED`, `DISCONNECTED`, `FAILED`. **This document does not introduce `PENDING`, `AUTHORIZING`, `REAUTH_REQUIRED`, `DISABLED`, `ERROR`, or `REVOKED`** — those were illustrative values in the governing task brief only; 5I's executed schema already fixes the five-value vocabulary above, and `integrations.fn_ic_terminal_guard()` DB-enforces that `DISCONNECTED`/`FAILED` are terminal (any UPDATE attempting to move away from them raises an exception).

**DEP-6J-01 — RESOLVED, LIVE-VALIDATED (originally P0; see §56 for full detail and current status).** The 059-066 executed 5I DDL contained no SECURITY DEFINER function performing any of the transitions above except the initial `CONNECTING` INSERT (`fn_create_integration_connection`) and the GDPR-only forced-disconnect (`fn_integrations_anonymize_org`). This was closed by the additive amendment migration `5K/migrations/101_5I1.sql` (Alembic revision `101_5I1`, `down_revision = '100_5G1'`), which adds `integrations.fn_activate_integration_connection()` (`CONNECTING|DEGRADED → ACTIVE`), `fn_fail_integration_connection()` (`CONNECTING → FAILED`, matching 4F §7.5's state diagram exactly — `FAILED` is reachable only from `CONNECTING`, never from `ACTIVE`/`DEGRADED`), `fn_degrade_integration_connection()` (`ACTIVE → DEGRADED`), `fn_disconnect_integration_connection()` (`{CONNECTING|ACTIVE|DEGRADED} → DISCONNECTED`, idempotent on an already-terminal connection), `fn_update_integration_connection_config()` (free-form field update, never touches `status`/`credential_ref`), and `fn_record_integration_sync_result()` (writes `last_sync_at`/`last_sync_error` only). All six are tenant-forgery-guarded (§31.1, ADR-6J-11) and granted `EXECUTE` directly to `app_api` (each function's own tenant-scoped `SELECT ... FOR UPDATE` discipline is what makes this safe — see ADR-6J-01, §55, for why the internal-RPC pattern this document originally proposed was removed in favor of direct execution). **Status: live-validated against PostgreSQL 18.6** — fresh + incremental migration PASS, full integration-connection lifecycle adversarial matrix PASS (§60, `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §10).

---

## 9. Integration Provider Catalog API

### 9.1 `GET /api/v1/integration-definitions`

- **Purpose:** discover the platform's supported integration providers.
- **Auth:** JWT or API key. **Permission:** `integration:read`.
- **Tenant scope:** none — `integration_definitions` has `organization_id IS NULL` (5I §4); this is one of 6A §10.3's small platform-global reference-data allow-list endpoints.
- **Latency tier:** A (6A §11). `Cache-Control: public, max-age=300` per 6A §10.3.
- **Query params:** `?category=CRM|CALENDAR|COMMUNICATION|PAYMENT|STORAGE` (filters on `IntegrationDefinition.Category`, 4F §6.1 — 5I's executed DDL does not persist `category` as its own column; see DEP-6J-08, §56), `?is_active=true` (default), cursor pagination per 6A §14 (small reference table — offset pagination is also acceptable per 6A §14.1's small-table allowance, cursor preferred for consistency).
- **Response `200`:**
```json
{
  "data": [
    {
      "id": "01930000-0000-7000-8000-000000000010",
      "key": "salesforce_crm",
      "name": "Salesforce CRM",
      "description": "Sync contacts and deals with Salesforce.",
      "category": "CRM",
      "auth_type": "OAUTH2",
      "capabilities": ["crm.contact.create", "crm.contact.update", "crm.deal.update"],
      "required_scopes": ["api", "refresh_token"],
      "manifest_version": "1.0.0",
      "documentation_url": "https://docs.platform.example/integrations/salesforce",
      "is_active": true
    }
  ],
  "meta": { "request_id": "...", "pagination": { "next_cursor": null, "has_more": false } }
}
```
- **Errors:** `401` (no credential). No `403` — every authenticated tenant may read the global catalog.
- **Idempotency:** N/A (GET).
- **Audit:** none (read-only, platform-global).

### 9.2 `GET /api/v1/integration-definitions/{definition_key}`

- Same auth/permission/caching as §9.1. `{definition_key}` is `integration_definitions.slug` (stable, immutable, e.g. `salesforce_crm` — 5I `chk_id_slug_format`), not the UUID `id`, matching 4F §6.1's `IntegrationDefinitionId` being the stable business key.
- Adds `configuration_schema` (JSON Schema for the definition's non-secret `configuration` fields, application-owned metadata — not a 5I DDL column; see DEP-6J-08) and `feature_maturity` (`GA | BETA | DEPRECATED` — same caveat).
- **Errors:** `404 INTEGRATION_DEFINITION_NOT_FOUND` if slug doesn't exist or `is_active = false` for non-platform-admin callers.

---

## 10. Integration Connection Lifecycle — Summary

Restated compactly from §8.6 for cross-reference: `CONNECTING → {ACTIVE | FAILED}`, `ACTIVE ⇄ DEGRADED`, `{CONNECTING|ACTIVE|DEGRADED} → DISCONNECTED`. Every transition below names its backing function; all six are supplied by amendment migration `101_5I1.sql` (§8.6, §56) and are not-yet-live-validated as disclosed there.

---

## 11. Integration Connection APIs

### 11.1 `GET /api/v1/integrations/connections`

- **Purpose:** list the caller's organization's integration connections.
- **Auth:** JWT/API key. **Permission:** `integration:read`. **Tenant scope:** RLS-enforced (`integrations.integration_connections`, `ENABLE + FORCE`).
- **Query params:** `?status=`, `?definition_id=` (allow-listed against `idx_ic_org_status`, `idx_ic_org_def_nonterminal`), cursor pagination.
- **Latency tier:** A.
- **Response:** array of connection summaries (never `credential_ref`, per §12).
- **Idempotency:** N/A (GET).

### 11.2 `POST /api/v1/integrations/connections`

- **Purpose:** create a new integration connection.
- **Auth:** JWT/API key. **Permission:** `integration:manage`.
- **Request (`OAUTH2` definitions):**
```json
{ "definition_id": "01930000-0000-7000-8000-000000000010", "display_name": "Production Salesforce" }
```
- **Request (`API_KEY`/`BASIC`/`CUSTOM` definitions):**
```json
{
  "definition_id": "01930000-0000-7000-8000-000000000099",
  "display_name": "Ops Slack Workspace",
  "credential": { "api_key": "xoxb-...redacted-in-docs-only..." },
  "configuration": { "workspace_url": "https://acme.slack.com" }
}
```
`credential` is accepted **only** in this one request, is never echoed back, and never reaches `integration_connections` as plaintext — the Application Service exchanges it for a `credential_ref` via the secret manager (§12.3) before calling `integrations.fn_create_integration_connection()`, which itself DB-CHECKs the resulting reference (`chk_ic_credential_ref`).
- **Validation:** `definition_id` must reference an `is_active = true` definition — DB-enforced as of `101_5I1` (§56 DEP-6J-09, closed) inside `fn_create_integration_connection()` itself, not merely at the application layer. For `OAUTH2` definitions, `credential`/`configuration.secret_fields` must be absent (`400 VALIDATION_ERROR` if present — an OAuth connection's credential can only ever arrive via the callback flow, §13).
- **Behavior:** calls `integrations.fn_create_integration_connection(org_id, definition_id, display_name, credential_ref, configuration)`. For `OAUTH2`, `credential_ref` is a placeholder sentinel (e.g. `secret_manager://pending`) satisfying the CHECK constraint until the OAuth callback supplies the real reference — the callback handler then calls `fn_activate_integration_connection(org_id, connection_id, p_credential_ref := <real ref>, ...)` (§13.6, closes former DEP-6J-01) to swap the placeholder for the real reference **and** flip `status` to `ACTIVE` in the same call.
- **Response `201`:** the created connection, `status: "CONNECTING"`. For `OAUTH2`, the response also includes `next_step: { "action": "oauth_authorize", "url": "/api/v1/integrations/connections/{id}/oauth/authorize" }` so the client knows to continue the flow (§13).
- **Errors:** `404 INTEGRATION_DEFINITION_NOT_FOUND` (unknown or inactive definition); `409 INTEGRATION_ALREADY_CONNECTED` (§8.2, non-terminal connection already exists — DB raises, application maps); `422 VALIDATION_ERROR`.
- **Idempotency:** `Idempotency-Key` **required** (6A §16.1 — resource creation with a real-world OAuth/credential-exchange side effect).
- **Concurrency:** the DB function's own `SELECT ... FOR UPDATE` is the concurrency guard (6A §17.3 — no API-layer lock).
- **Audit:** `INTEGRATION_CONNECTION_CREATED` (sync, per 6A §22 — configuration-class event, async per 5J §14.5's own classification; this document treats connection-creation as sync-audited since it is credential-adjacent, matching 6A §22's "auth/API-key/... synchronous" carve-out).
- **Domain event:** `integration.connected` — deferred until the connection actually reaches `ACTIVE` (§37), not emitted at `CONNECTING` creation.

### 11.3 `GET /api/v1/integrations/connections/{connection_id}`

- **Auth:** JWT/API key. **Permission:** `integration:read`. Cross-tenant access → `404`, never `403` (6A §7.4/§22).
- **Response:** full connection detail + embedded `health` summary (§14) inlined (bounded — single nested object, not a collection, so 6A §10.2's 20-item cap doesn't apply).
- **Caching:** `ETag` derived from `hash(id, updated_at)` (6A §17.2 weak validator — no dedicated `version` column exists, per 6A's own platform-wide ADR-6A-08).

### 11.4 `PATCH /api/v1/integrations/connections/{connection_id}`

- **Purpose:** update `display_name` / `configuration` (non-secret fields only — never `credential_ref`, never `status`).
- **Permission:** `integration:manage`. **Concurrency:** `If-Match` required (6A §17.2 — this is a free-form field update on a non-fully-state-machine-guarded field set; `status` itself is never PATCH-able, only via action endpoints per 6A §8.3).
- **Validation:** rejects `status`, `credential_ref`, `credential` as unknown/forbidden fields (Pydantic `extra="forbid"`, 6A §22) — `422` if present, not silently ignored, since silently ignoring a client's attempt to set `status` would mask a client bug.
- **Behavior:** `app_api` has no direct `UPDATE` grant on `integration_connections` (5I's REVOKE, §28 — unchanged); this PATCH calls `integrations.fn_update_integration_connection_config(org_id, connection_id, display_name, configuration)` (added by `101_5I1.sql`, §56 — closes former DEP-6J-01's config-PATCH half), which is `SELECT ... FOR UPDATE`-guarded, rejects a terminal (`DISCONNECTED`/`FAILED`) connection with `409 INTEGRATION_DISABLED`, and touches only `display_name`/`configuration` — `status` and `credential_ref` are structurally unreachable from this function's parameter list.
- **Errors:** `404`, `412 PRECONDITION_FAILED` (ETag mismatch), `422`.
- **Audit:** `INTEGRATION_CONFIG_UPDATED`.

### 11.5 `DELETE /api/v1/integrations/connections/{connection_id}`

- Per 6A §7.6, `IntegrationConnection` is a terminal-status resource — DELETE is disallowed (`405`) in favor of the explicit disconnect action below.

### 11.6 `POST /api/v1/integrations/connections/{connection_id}/disconnect`

- **Purpose:** tenant-initiated disconnect. Maps to the DDD `DisconnectIntegration` command / `ACTIVE|DEGRADED → DISCONNECTED` transition (4F §6.2, §7.5).
- **Permission:** `integration:manage`.
- **Request:** `{ "reason": "no_longer_needed" }` (optional, free text ≤200 chars, `LEFT()`-truncated to 1000 by the function, stored in `disconnect_reason`).
- **Behavior:** calls `integrations.fn_disconnect_integration_connection(org_id, connection_id, reason)` (added by `101_5I1.sql`, §56 — closes former DEP-6J-01's disconnect half). Distinct from `fn_integrations_anonymize_org()`, which remains GDPR-erasure-only, platform-admin-gated, and additionally clears PII (`external_account_name`/`external_account_ref`) as a side effect — an ordinary tenant-initiated disconnect via this endpoint does **not** anonymize the connection, it only terminates it. Valid from any non-terminal status (`CONNECTING`, `ACTIVE`, `DEGRADED`).
- **Response `200`:** the connection with `status: "DISCONNECTED"`, `disconnected_at` set.
- **Idempotency:** natural — a second disconnect call on an already-`DISCONNECTED` **or already-`FAILED`** connection is a no-op returning `200` unchanged (the function's own idempotent-return, mirroring `fn_uninstall_plugin`'s pattern, 5I §28), not `409` — disconnecting an already-terminated connection is not an error, it is confirming a state the tenant already wanted.
- **Domain event:** `integration.disconnected`.
- **Audit:** `INTEGRATION_DISCONNECTED`.

### 11.7 `POST /api/v1/integrations/connections/{connection_id}/reauthorize`

- **Purpose:** re-run credential acquisition for a connection whose credential needs refreshing. **Eligible source states: `ACTIVE` and `DEGRADED` only.**
- **`FAILED` is explicitly NOT eligible** (corrected — a prior revision of this document incorrectly allowed reauthorize from `FAILED`, contradicting `FAILED`'s own terminal status: `integrations.fn_ic_terminal_guard()` DB-rejects *any* UPDATE moving a `FAILED` row's `status` away from `FAILED`, so a `fn_activate_integration_connection()` call against a `FAILED` connection would fail at the DB layer regardless of what the API layer intended — 5I §8/4F §7.5's state diagram shows `FAILED` reachable only from `CONNECTING`, with no outbound edge at all). A tenant whose connection reached `FAILED` must create a **new** connection (§11.2) — `POST .../reauthorize` on a `FAILED` or `DISCONNECTED` connection returns `409 INTEGRATION_DISABLED` with `error.details = {"current_state": "FAILED", "recovery": "create_new_connection"}`.
- **Permission:** `integration:manage`.
- **Behavior (`OAUTH2`):** creates a new `OAuthAttempt` exactly like §13's initial flow, scoped to the existing `connection_id` (via the `connection_id` column added by `101_5I1.sql`, §56 — closes former DEP-6J-04) — on successful callback, `fn_activate_integration_connection(org_id, connection_id, p_credential_ref := <new ref>)` both swaps the credential and moves `DEGRADED → ACTIVE` (or leaves an already-`ACTIVE` connection `ACTIVE`) in one guarded call.
- **Behavior (`API_KEY`/`BASIC`/`CUSTOM`):** accepts a new `credential` in the request body exactly like §11.2's create flow, calls `fn_rotate_integration_credential()` (unchanged from 5I §12.4, now additionally `EXECUTE`-granted to `app_api` directly per `101_5I1.sql`'s grant-widening, §56/§55 ADR-6J-01 — no internal-RPC hop needed), then, for a `DEGRADED` source connection, `fn_activate_integration_connection(org_id, connection_id)` (no new credential arg — the rotate call already updated it) to complete `DEGRADED → ACTIVE`.
- **Idempotency:** `Idempotency-Key` optional but recommended (credential-exchange side effect, not purely safe/GET-like).
- **Audit:** `INTEGRATION_REAUTHORIZED`.

### 11.8 `POST /api/v1/integrations/connections/{connection_id}/test`

- **Purpose:** verify current connectivity/credential validity without mutating tenant data at the provider.
- **Permission:** `integration:read` is **insufficient** — this makes an outbound provider call and is rate-limited; requires `integration:manage`.
- **Behavior:** Application Service resolves `credential_ref`, makes one bounded, read-only provider API call (e.g. "whoami"/account-info endpoint) through the egress-control adapter (§30), classifies the result (§35.2), and records it into `integration_health` via the worker's ordinary `UPDATE` grant (no SECURITY DEFINER needed — `integration_health` carries no state-machine guard, §28 grants `UPDATE` directly to `app_worker`). Does **not** itself flip `integration_connections.status`. Where `integration_health.consecutive_failure_count` crosses the platform's degradation threshold (§14.1's derivation, default 5), the Application Service's health-evaluation code path separately calls `integrations.fn_degrade_integration_connection(org_id, connection_id, reason)` (§56, added by `101_5I1.sql`) — a distinct, explicit call, never an implicit side effect of the `test` endpoint itself, keeping "record one health observation" and "decide the connection is now degraded" as two separable concerns.
- **Rate limit:** max 1 concurrent test per connection (Redis `SETNX` lock, `integrationtest:{connection_id}`, mirroring 6A §19's stampede-prevention pattern); max 10/hour per connection at the application quota layer.
- **Response `200`:**
```json
{ "data": { "result": "SUCCESS", "checked_at": "2026-08-29T10:00:00Z", "latency_ms": 340 } }
```
or `{ "data": { "result": "FAILURE", "failure_class": "AUTH_FAILED", "checked_at": "...", "detail": "Provider rejected the current credential." } }` — `failure_class` is one of the normalized classes in §29, never a raw provider error body.
- **Idempotency:** N/A — side-effect-free at the tenant-data layer, safe to call repeatedly (mutates only `integration_health`, an observability record, not a business resource); no `Idempotency-Key` required.
- **Audit:** `INTEGRATION_TEST_PERFORMED` (async, low-priority).

---

## 12. Credential & Secret Security

### 12.1 Absolute Rules (No Exceptions)

1. **`credential_ref` values are never returned by any read API.** Every response model in this document structurally excludes `credential_ref`, `signing_secret_ref`, and any plugin `credential_ref` — matching 6A §10.2/§22's platform-wide invariant that secret fields are absent from the Pydantic response model's field set, not merely nulled out.
2. **Secrets never appear in logs.** The PII-redaction log processor (6A §22, 3E §14.1) strips `token|password|secret|credential`-matching fields; this document adds no new logging path that bypasses it.
3. **Secrets never appear in audit payloads.** `audit.audit_events.resource_snapshot` (5B §30's allow-list) never includes `credential_ref`'s resolved value — only the opaque reference string itself is safe to record (it is not the secret, by construction), and even that is omitted from the snapshot unless explicitly needed for support triage.
4. **Secrets never appear in ordinary error details.** `error.details` (6A §24.1) never includes a `credential`/`credential_ref` value; provider auth-failure responses are normalized to `failure_class: AUTH_FAILED` (§29), never the provider's raw rejection body.
5. **Secrets never persist in the idempotency cache, and the fingerprint itself is hardened against low-entropy secrets (corrected — remediation §10, P1).** A bare `SHA-256(normalized_request_body)` fingerprint over a request body containing a raw credential is unsafe when that credential is low-entropy — a `BASIC` password or a short user-chosen `API_KEY` value is brute-forceable offline against a leaked or improperly-secured fingerprint store, unlike a high-entropy platform-issued token. The `Idempotency-Key` request-fingerprint (6A §16.2, as applied by this document) is instead computed as `HMAC-SHA256(platform_idempotency_fingerprint_key, canonical_request_body)`, where `platform_idempotency_fingerprint_key` is a platform-held secret (never derived from or related to any tenant credential, rotated per infrastructure key-rotation policy like any other platform signing key) — an attacker who obtains the Redis-stored fingerprint cannot brute-force the underlying credential without also possessing the platform's own HMAC key, closing the low-entropy-secret exposure a bare hash leaves open. The cached **response** still never includes the credential (rule 1 already guarantees this) — this rule concerns only the *fingerprint* used for duplicate-request collision detection.
6. **Secret values are write-only.** A client may `POST` a credential once (creation/reauthorization); it can never `GET` it back. Read APIs expose only: whether a credential is set (implicit — a `CONNECTING`/`FAILED` connection has none yet), `connected_at`, and (§12.4) rotation timestamps.

### 12.2 Encryption Mechanism — Reconciled with Phase 5, Not Redesigned

5I's `credential_ref` is an **opaque secret-manager reference** (`CHECK (credential_ref LIKE 'secret_manager://%')`, `chk_ic_credential_ref`/`chk_we_signing_secret_ref`/`chk_pi_credential_ref`) — the actual secret material is never in PostgreSQL at all, in any form, encrypted or otherwise. 4F §6.2 names the concrete reference shape: `secret_manager://org/{tenant_id}/integration/{connection_id}/token`, resolved through "the secret manager (Phase 3F §7)". This document does not pick a KMS product or specify pgcrypto envelope encryption inside Postgres — the frozen architecture's answer is "no secret touches Postgres," which is a stronger guarantee than DB-level encryption and this document treats it as final. Where a future phase's secret-manager implementation needs an API-facing contract (issue/resolve/rotate a reference), that is an infrastructure-layer concern this document does not redesign — the Application Service simply calls whatever secret-manager client 3F provisions and receives back an opaque string satisfying the `secret_manager://` CHECK.

### 12.3 Credential Exchange Flow (Non-OAuth)

```
Client → POST .../connections { credential: { api_key: "..." } }
    ↓ (TLS-terminated at ingress; body never logged, 6A §22)
Application Service
    ↓ secret_manager.store(org_id, connection_id, credential) → credential_ref string
    ↓ (raw credential discarded from memory immediately after this call returns)
integrations.fn_create_integration_connection(org_id, definition_id, display_name, credential_ref, configuration)
    ↓ DB CHECK confirms credential_ref LIKE 'secret_manager://%' — a bug that leaked a raw key here is caught at the DB boundary, not just trusted
```

### 12.4 Secret Rotation

| Resource | Rotation mechanism | Reauthorization required? |
|---|---|---|
| `IntegrationConnection` credential | `integrations.fn_rotate_integration_credential()` — independently rotatable without a full reconnect, **for non-OAuth definitions** (new API key/Basic credential submitted via §11.7) | No, for `API_KEY`/`BASIC`/`CUSTOM` |
| `IntegrationConnection` credential (OAuth) | New `OAuthAttempt` + callback (§13) is required — an OAuth access/refresh token pair cannot be "rotated" independently of running the authorization flow again unless the provider's own token-refresh flow is used (§13.6, distinct from user-facing reauthorization) | Yes, for `OAUTH2` (unless silent token refresh, §13.6, applies) |
| `WebhookEndpoint` signing secret | `POST .../webhook-endpoints/{id}/rotate-secret` (§18) — independently rotatable, no reconnect concept applies | N/A |
| `PluginInstallation` credential | Same pattern as non-OAuth `IntegrationConnection` — no dedicated rotate function exists in 5I; §26 flags this as part of DEP-6J-02 |

---

## 13. OAuth Architecture & API Contracts

### 13.1 Flow Overview (Authorization Code + PKCE) — Corrected Tenant-Bootstrap

```
1. Client (authenticated, JWT/API key):
            POST /api/v1/integrations/connections/{connection_id}/oauth/authorize
2. Server:  generate cryptographically random `state` (256-bit) + PKCE `code_verifier` (5I: TEXT, S256 challenge)
            INSERT INTO integrations.oauth_attempts
              (organization_id, definition_id, connection_id, state, code_verifier, redirect_uri,
               requested_scopes, expires_at = NOW() + 10 minutes)
              -- connection_id populated directly (101_5I1 column, §13.2) — no inference needed
            build provider authorization URL (client_id, redirect_uri, state,
              code_challenge=SHA256(code_verifier), code_challenge_method=S256, scope)
3. Server → Client: { "authorization_url": "https://provider.example/oauth/authorize?..." }
4. Client:  redirects the end user's browser to authorization_url
5. Provider: end user approves → redirects browser to
            GET /api/v1/integrations/oauth/{definition_key}/callback?code=...&state=...
              -- UNAUTHENTICATED hop: no platform JWT, no tenant context yet (§13.4)
6. Server:  integrations.fn_redeem_oauth_callback_state(state, expected_definition_id) — PENDING → REDEEMED,
              exactly once, takes `state` + the ROUTE's own resolved provider identity (no organization_id
              input — the caller doesn't have one yet), verifies state.definition_id = expected_definition_id
              BEFORE consuming state (closes the OAuth state/provider-binding P0 — §55 ADR-6J-12),
              RETURNS organization_id, definition_id, connection_id, code_verifier, redirect_uri, requested_scopes
              -- this is the corrected tenant-bootstrap step (§13.3); closes the former P0
            server now has organization_id — SET LOCAL app.tenant_id = organization_id for the remainder of
              this transaction, exactly mirroring 6A §23.2's ordinary JWT-authenticated request flow, so every
              subsequent guarded call below satisfies its own tenant-forgery guard (§55 ADR-6J-11)
            exchange code (+ code_verifier) for access/refresh tokens — server-side, direct provider call
              (using the RETURNED redirect_uri, never a client-supplied one — §13.4's CSRF guarantee, unchanged)
            secret_manager.store(...) → credential_ref
            integrations.fn_activate_integration_connection(organization_id, connection_id,
              p_credential_ref := credential_ref, p_external_account_ref := ..., p_connected_by_ref := ...)
              -- CONNECTING → ACTIVE in the same call that installs the real credential (§56, closes former DEP-6J-01)
7. Server:  emits integration.connected domain event + INTEGRATION_CONNECTED audit event
8. Server → browser: redirect to the platform's own post-connect UI page (never back to the provider)
```

### 13.2 `state` Binding (5I-Exact, Amended by `101_5I1`)

Per `integrations.oauth_attempts` (5I §28 migration `061`, amended by `101_5I1.sql` §56), every `OAuthAttempt` binds:

| Field | Binds to |
|---|---|
| `organization_id` | The requesting tenant — recovered as **output** from `fn_redeem_oauth_callback_state(state)` at redemption time (§13.3), never required as caller input |
| `definition_id` | Which provider this attempt is for |
| `connection_id` | **(new, `101_5I1`)** The exact connection this attempt belongs to — closes the former DEP-6J-04 ambiguity directly; no longer inferred from the `(organization_id, definition_id)` one-non-terminal-connection invariant, which also means this design remains correct even if Decision J1 (§57) later relaxes that invariant to allow multiple connections per provider |
| `state` | `UNIQUE` (`uq_oa_state`) — collision-resistant, single global namespace, unguessable (256-bit) — **this is the actual security boundary of the whole callback hop**, functioning exactly like a password-reset token |
| `code_verifier` | PKCE S256 — bound 1:1 to this attempt, never reused |
| `redirect_uri` | `CHECK (redirect_uri LIKE 'https://%' OR redirect_uri LIKE 'http://localhost%')` — allow-listed at INSERT time; the callback step's actual redirect target is validated against this stored value, not re-derived from client input at redemption time |
| `requested_scopes` | Recorded for audit/support visibility — actual scope enforcement happens provider-side |
| `expires_at` | `NOW() + 10 minutes` (5I default), `CHECK (expires_at > created_at)` |
| `failure_reason` | **(new, `101_5I1`)** Populated only on the denial path (§13.5), ≤1000 chars, sanitized/truncated |

### 13.3 Redemption — Exactly Once, Tenant-Bootstrap-Safe

**Corrected (previously a P0 defect — see §55 ADR-6J-08 for the full before/after):** the prior design called `fn_redeem_oauth_attempt(state, organization_id)`, which requires `organization_id` as an **input parameter** — but the unauthenticated browser callback (§13.4) has no tenant context to supply it with. This was a genuine circular dependency, not merely a documentation gap.

`integrations.fn_redeem_oauth_callback_state(p_state TEXT, p_expected_definition_id UUID)` (§56, `101_5I1.sql`) fixes this by taking `state` **plus the calling route's own resolved provider identity**, and returning tenant identity as **output**:

```sql
SELECT * FROM integrations.fn_redeem_oauth_callback_state(
  'the-state-value-from-the-query-string',
  '<definition_id the Provider Adapter resolved from {definition_key} in the URL path>'
);
-- returns: oauth_attempt_id, organization_id, definition_id, connection_id,
--          code_verifier, redirect_uri, requested_scopes
```

`p_expected_definition_id` closes a second, independent P0 found on review of the first version of this function (which took `state` alone with no provider binding at all): **the provider/definition check runs BEFORE any status mutation** — a `state` value issued for one provider, presented at a *different* provider's callback route (via a captured, leaked, or misdirected redirect), is rejected without being consumed, and remains redeemable later through the *correct* route (§55 ADR-6J-12; live-proven — a wrong-provider attempt against a real `state` was rejected and the row stayed `PENDING`; the same `state` then successfully redeemed through the correct provider route immediately after).

- Provider/definition mismatch → exception (`state` untouched, still `PENDING`) → API maps to `400 OAUTH_PROVIDER_MISMATCH`
- `NOT FOUND` (unknown state) → exception → API maps to `400 OAUTH_STATE_INVALID`
- `status = 'REDEEMED'` → exception → `409 OAUTH_STATE_ALREADY_USED` (replay attempt — the second caller, whether malicious or a duplicate browser back-navigation, never gets a second valid token exchange, and never learns which organization the state belonged to, since the exception carries no such detail)
- `status IN ('EXPIRED','FAILED')` → exception → `410 OAUTH_STATE_EXPIRED`
- `expires_at <= NOW()` → raises → `410 OAUTH_STATE_EXPIRED`. **Disclosed, non-security defect (live-found):** the function does **not** persist `status = 'EXPIRED'` on this path — an `UPDATE` immediately followed by `RAISE EXCEPTION` in the same statement is rolled back by that same exception (standard PostgreSQL semantics; confirmed by live reproduction), so the row's stored `status` stays `PENDING` even though it is functionally, permanently unredeemable (`expires_at <= NOW()` is re-evaluated fresh on every call — a stale row can never actually be redeemed past its expiry regardless of what `status` displays). This is an **observability-only gap** (a reporting dashboard counting "expired attempts" would undercount), not a security gap, and is inherited identically by the pre-existing, unmodified `fn_redeem_oauth_attempt` (059-066) — a periodic housekeeping sweep to mark truly-expired `PENDING` rows `EXPIRED` for reporting purposes is a forward, non-blocking item, out of this document's scope.
- Otherwise → `PENDING → REDEEMED`, `redeemed_at = NOW()`, returns the full row context

**Why this does not require removing RLS from `oauth_attempts` (a question a naive fix might reach for):** `oauth_attempts` keeps `ENABLE + FORCE ROW LEVEL SECURITY` completely unchanged. `fn_redeem_oauth_callback_state()` is `SECURITY DEFINER`, so its internal `SELECT`/`UPDATE` execute under the function's **owning role** — `app_migration`, which was created `BYPASSRLS` in `001_5B.sql` and independently reconfirmed still-`BYPASSRLS` by the live `077_5J1` validation pass (`5K/validation/077_5J1_VALIDATION_REPORT.md` line 309), and re-confirmed live again in this document's own remediation pass (§56, §60). RLS enforcement was therefore never actually the obstacle inside this function — the only real defect was the signature requiring an input the caller couldn't supply. This function's `EXECUTE` grant is narrower than the rest of this document's tenant-bound functions — **`app_api, app_platform_admin` only, deliberately excluding `app_worker`** (§55 ADR-6J-13, remediation §7's least-privilege instruction: no worker process ever handles an OAuth callback, so it never needs this grant) — live-confirmed: `has_function_privilege('app_worker', 'fn_redeem_oauth_callback_state(text,uuid)', 'EXECUTE')` = `false`, and a direct call attempt as `app_worker` is denied.

**Note — this function is deliberately exempt from the tenant-forgery guard §55 ADR-6J-11 applies to every other tenant-bound function in this document.** It is a *callback bootstrap function* (§56's "function classes" note): no tenant context exists yet at this point in the flow, by definition — applying the guard here would make the function permanently uncallable. Its security instead rests entirely on `state`'s own unguessable/single-use/TTL/now-provider-bound design, exactly as this section describes.

This closes CSRF (state is unguessable and, once redeemed, tenant identity is recovered server-side, never trusted from any client input), replay (single-use, DB-enforced via row lock, not merely application-layer "please don't call twice"), and expiration (10-minute TTL) simultaneously — 5I's own **INV-INT-03**, preserved exactly.

`fn_redeem_oauth_attempt(state, organization_id)` (5I §28, unmodified) remains in the schema for any future caller that already has tenant context in hand — it is simply **not** the function this endpoint calls.

### 13.4 `GET /api/v1/integrations/oauth/{definition_key}/callback`

- **Classification:** browser-redirect endpoint, **not** a JSON API — per the task brief's explicit instruction to distinguish the two. Not documented in the tenant-facing OpenAPI JSON contract surface the same way a `/api/v1/*` resource endpoint is; it is a redirect target only, reachable without a platform JWT (the browser arrives here mid-OAuth-dance, holding no platform session token at this exact hop — tenant identity is instead recovered from `fn_redeem_oauth_callback_state()`'s **output**, §13.3, never assumed or derived from any request-supplied value).
- **Query params:** `code`, `state` (both provider-supplied), or `error`/`error_description` (provider-denied case, §13.5).
- **Not rate-limited by the tenant quota system** (6A §28.2's carve-out for provider-driven callbacks) — bounded instead by `oauth_attempts`' own 10-minute TTL and single-use redemption. A narrower, non-tenant-keyed rate ceiling (per source IP, coarse) still applies at the edge (§22 of the SSRF/abuse controls) to blunt state-guessing brute-force probes, which is a meaningfully different risk from tenant quota exhaustion and is bounded to begin with by `state`'s 256-bit search space.
- **Response:** HTTP 302 redirect to a platform-owned URL (`{configured web app origin}/integrations/callback?connection_id=...&result=success|failed`) — never a JSON body (the far end of this hop is a browser, not an API client).
- **CSRF/redirect-URI validation:** the `redirect_uri` used for the actual OAuth token exchange (step 6) is the one **returned by `fn_redeem_oauth_callback_state()`**, i.e. the value **stored on the `oauth_attempts` row at creation time** (§13.2), never a value taken from the callback's own query string — a provider or attacker cannot redirect the token exchange to an arbitrary URI by manipulating the callback request, because the callback request supplies no `redirect_uri` at all.

### 13.5 Provider-Denied Authorization (Pre-Redemption Only)

If the provider redirects with `?error=access_denied` (or any `error` param) instead of `code`: the Application Service calls `integrations.fn_fail_oauth_callback_state(state, expected_definition_id, reason)` (§56, `101_5I1.sql` — closes former DEP-6J-05) — the same tenant-bootstrap-safe, provider-bound shape as §13.3 (`state` + the route's own resolved provider identity, no `organization_id` required) — which marks the `oauth_attempts` row `FAILED` (idempotent on an already-`FAILED` row) and stores the sanitized `reason` in `failure_reason`. **This function is now unambiguously scoped to the pre-redemption denial path only** — it explicitly rejects an attempt already in `REDEEMED` status, directing the caller to §13.5a's function instead (see §13.5a for why this split exists). The browser is then redirected to the platform's callback page with `result=denied`. The underlying `IntegrationConnection` is separately transitioned `CONNECTING → FAILED` via `integrations.fn_fail_integration_connection(organization_id, connection_id, reason)` (§56 — note this call now has `organization_id` in hand, having just been returned by the fail-state function, exactly mirroring §13.1 step 6's success path) — both the attempt and the connection reach a consistent terminal state together, not left in disagreement.

### 13.5a Post-Redemption Token-Exchange Failure — `fn_record_oauth_exchange_failure` (New, Second Remediation Pass)

**A genuine self-contradiction in an earlier revision of this section is corrected here.** OAuth redemption (§13.3) necessarily transitions `state` to `REDEEMED` *before* the server performs the actual provider token exchange (correct — 6A §35 forbids holding a DB transaction open across an external HTTP call, so redemption and exchange must be two separate steps, and redemption must be single-use/atomic regardless of what happens next). But §13.5's `fn_fail_oauth_callback_state` explicitly **rejects** an attempt already in `REDEEMED` status — so if the subsequent token exchange call itself fails (network error, provider `5xx`, invalid grant), there was previously no function that could durably record that outcome without contradicting the single-use replay-safety guarantee.

**Fix:** `integrations.fn_record_oauth_exchange_failure(p_state TEXT, p_reason TEXT)` (§56, `101_5I1.sql`) — requires the attempt to be exactly `REDEEMED`, records `exchange_failed_at = NOW()` and the sanitized `reason` into `failure_reason`, and **leaves `status` unchanged at `REDEEMED`** — the single-use guarantee is completely untouched; this is purely an annotation of what happened *after* the (already-final) redemption. Idempotent on a second call. Rejects a `PENDING` (never-redeemed) attempt — that case is still `fn_fail_oauth_callback_state`'s job. No provider-binding parameter is needed here (unlike §13.3/§13.5): this function is always called as a direct continuation of the same request that already passed `fn_redeem_oauth_callback_state`'s own binding check — there is no second, separately-untrusted routing decision being made.

**Live-proven** (§60): the exact contradiction scenario — calling `fn_fail_oauth_callback_state` on an already-`REDEEMED` attempt — is correctly rejected; the correct path (`fn_record_oauth_exchange_failure`) correctly records the failure while `status` stays `REDEEMED`; a second, idempotent call is a no-op; and calling it on a still-`PENDING` (never redeemed) attempt is correctly rejected.

The underlying `IntegrationConnection` remains `CONNECTING` (un-activated) after an exchange failure — `fn_activate_integration_connection` was never reached — it is tenant-visible via `GET .../connections/{id}` and disconnectable/re-attemptable by the tenant through the ordinary reauthorize flow (§11.7).

### 13.6 Token Refresh / Refresh-Token Rotation

**Not modeled by 5I's executed schema.** `oauth_attempts` records only the initial authorization-code exchange; there is no `refresh_tokens`/`oauth_tokens` table, and no scheduled or on-demand "silently refresh this connection's access token using its refresh token" function or endpoint exists. Per 4F §6.2/5I, the raw access/refresh token pair, once obtained, lives entirely inside the secret manager behind `credential_ref` — refreshing it is therefore an operation the Application Service performs by resolving `credential_ref`, calling the provider's token endpoint, and writing the new token pair back to the **same** secret-manager reference (no new `credential_ref` string, no DB write at all) whenever the cached token is found to be expired at use-time. This requires no new table and no new SECURITY DEFINER function — it is entirely a secret-manager-side operation invisible to Postgres, and is **not** the same code path as §12.4's `fn_rotate_integration_credential()` (which changes which `credential_ref` string a connection points to; silent token refresh keeps the same reference). No new endpoint is defined for it — it happens transparently inside whichever Application Service call needs a valid access token.

### 13.7 Incremental Consent / Reconnect

Not supported in V1 — `requested_scopes` on a fresh `OAuthAttempt` always requests `integration_definitions.required_scopes` in full (5I has no per-attempt partial-scope negotiation UI contract). A tenant needing broader scopes than originally granted must go through §11.7's reauthorize flow, which requests the full scope set again.

---

## 14. Integration Health

### 14.1 `GET /api/v1/integrations/connections/{connection_id}/health`

- **Purpose:** expose `integration_health`'s durable counters without forcing a synchronous provider call on every read (6A §29 anti-pattern rule — "no endpoint claims Tier A while making a synchronous call to an external system").
- **Permission:** `integration:read`.
- **Latency tier:** A — this is a plain indexed `SELECT` against `integration_health` (`uq_ih_connection`), never a live provider round-trip. A live check is §11.8's separate, explicitly rate-limited `test` action.
- **Response `200`:**
```json
{
  "data": {
    "connection_id": "...",
    "aggregate_status": "HEALTHY",
    "last_success_at": "2026-08-29T09:55:00Z",
    "last_failure_at": null,
    "consecutive_failure_count": 0,
    "auth_failure_count": 0,
    "rate_limit_reset_at": null
  }
}
```
- **`aggregate_status` derivation (API-layer computed, not a stored column):**

| Condition | `aggregate_status` |
|---|---|
| `connection.status = 'DISCONNECTED' \| 'FAILED'` | `DISABLED` |
| `consecutive_failure_count = 0` | `HEALTHY` |
| `auth_failure_count > 0` and most recent failure was an auth failure | `AUTH_REQUIRED` |
| `0 < consecutive_failure_count < 5` | `DEGRADED` |
| `consecutive_failure_count >= 5` | `FAILED` |

This mirrors the task brief's suggested health-state vocabulary (`HEALTHY`/`DEGRADED`/`AUTH_REQUIRED`/`FAILED`/`DISABLED`) as a **derived, API-only presentation layer** over 5I's actual stored counters — no new DB column or enum is introduced; the thresholds (`5` consecutive failures) are this document's own binding default, tunable at the application-config layer, not a DB CHECK.
- **Who writes `integration_health`:** `app_worker`, via ordinary `UPDATE` (grant exists, no SECURITY DEFINER required — `integration_health` carries no state-machine guard). Written by: (a) §11.8's `test` action, (b) the sync worker (§15) after every sync attempt, (c) any Application Service code path that makes a live provider call as part of normal operation (e.g., an ACL translating an inbound event) and observes success/failure.

---

## 15. Synchronization Model & APIs

### 15.1 What 5I Actually Persists

**PHASE 5 SCHEMA GAP (DEP-6J-06, §56):** the executed 5I DDL has **no `IntegrationSyncJob` or `IntegrationSyncCursor` table**. The only sync-related persistence is two columns directly on `integration_connections`: `last_sync_at` (TIMESTAMPTZ) and `last_sync_error` (TEXT, ≤1000 chars, DB-CHECKed). There is no per-sync-job history, no resumable cursor, no concurrent-sync-tracking, and no way to list past sync attempts beyond "when did the most recent one happen and did it fail."

### 15.2 V1 Contract — Minimum Viable, Not a Fabricated Job Table

Given §15.1, this document defines **one** sync endpoint whose semantics are honest about what the schema actually supports — it does **not** define `GET .../syncs` or `GET .../syncs/{sync_id}` (the task brief's suggested sub-resource pattern), because no backing table exists to serve them from, and 6A §18.3 requires job endpoints to project from a real tracking table or be explicitly flagged as a dependency rather than fabricated.

### 15.3 `POST /api/v1/integrations/connections/{connection_id}/sync`

- **Purpose:** trigger an on-demand sync for connections whose `IntegrationDefinition.capabilities` includes a sync-eligible capability (e.g. `crm.contact.sync`).
- **Permission:** `integration:manage`.
- **Concurrency:** a Redis `SETNX` lock (`integrationsync:{connection_id}`, mirroring 6A §19's stampede-prevention primitive and the existing `lock:call:{provider_call_sid}` pattern, 3B §16) ensures at most one sync runs per connection at a time — a second `POST .../sync` while one is in flight returns `409 INTEGRATION_SYNC_IN_PROGRESS`, not a queued second attempt (no cursor/queue table exists to make a second attempt meaningfully resumable/ordered against the first).
- **Behavior:** enqueues a Celery task (async — this genuinely is Tier D, §19, since the work is provider-bound and unbounded in duration per 6A §6). The task, on completion, calls `integrations.fn_record_integration_sync_result(org_id, connection_id, success, error_message)` (§56, added by `101_5I1.sql` — closes the sync-result-write half of former DEP-6J-01), which writes `last_sync_at`/`last_sync_error` only and is a documented no-op if the connection has since reached a terminal state (the tenant disconnected while the sync was in flight).
- **Response `202`:**
```json
{ "data": { "job_id": "01930000-...", "status": "PENDING" } }
```
`job_id` here is a **Celery task ID**, not a persisted `IntegrationSyncJob` row — per 6A §18.3's explicit allowance, this is disclosed as an **API-DESIGN DEPENDENCY**: `GET /api/v1/jobs/{job_id}` for this specific job type can report `status` (from the Celery result backend) but cannot report `progress` as a structured count, and the job's terminal state is not independently queryable after the Celery result TTL expires — the client should instead poll `GET .../connections/{id}` and read `last_sync_at`/`last_sync_error` for the durable outcome.
- **Errors:** `404`; `409 INTEGRATION_SYNC_IN_PROGRESS`; `422 INTEGRATION_SYNC_NOT_SUPPORTED` (definition has no sync-eligible capability).
- **Idempotency:** `Idempotency-Key` optional — a duplicate call while a sync is in flight is already rejected by the Redis lock (§ above); after completion, a duplicate call simply starts a new, independent sync (syncs are not inherently side-effect-free, so this is a deliberate "not idempotent, but safely re-triggerable" classification, not a gap).
- **Full/incremental, resumability, per-item conflict/partial-failure reporting:** **not implementable in V1** per §15.1 — flagged in full at DEP-6J-06 (§56) as the concrete schema addition (`integrations.integration_sync_jobs` with `cursor JSONB`, `status`, `items_processed`, `items_failed`, `error_summary`) a future migration would need.

---

## 16. Provider Quota / Rate Limit Handling

### 16.1 Five Distinct Rate/Quota Concepts — Not to Be Conflated

| # | Concept | Enforced by | Scope |
|---|---|---|---|
| 1 | Platform API rate limits (calling *this document's own* endpoints) | 6A §20 — L1 NGINX + L2 per-tenant Redis | Every `/api/v1/integrations/*`, `/api/v1/webhook-*`, `/api/v1/plugin*` endpoint |
| 2 | Provider API rate limits (the external system's own `429`) | This document, §16.2 | Outbound provider calls made during sync/test/plugin-callout |
| 3 | Provider account quotas (e.g. Salesforce API-call-per-day cap) | Surfaced via `integration_health.rate_limit_reset_at`; not independently tracked beyond that one field | Same as #2 |
| 4 | Connector concurrency controls | §15.3's per-connection `SETNX` lock; plugin `Manifest.RateLimitPerMinute` token bucket (§28) | Sync jobs; plugin callouts |
| 5 | Webhook delivery rate limiting | §22 — governed by `max_attempts`/backoff, not the tenant API quota system (6A §20's explicit carve-out) | Outbound webhook delivery only |

### 16.2 Provider `429` Handling

When an outbound provider call (sync, test, plugin callout — all routed through the egress-control adapter, §30) receives `429`:
1. If the provider supplies `Retry-After`, the Application Service honors it, capping at 300 seconds (avoids an abusive/misconfigured provider parking a worker indefinitely).
2. If absent, exponential backoff starting at 2 seconds, doubling, capped at 60 seconds, with ±20% jitter (6A §21's general external-HTTP retry shape, applied here).
3. `integration_health.rate_limit_reset_at` is set to `NOW() + Retry-After` (or the computed backoff ceiling) so `GET .../health` (§14) can surface it to the tenant without another live call.
4. A sync job (§15) that hits `429` on its first attempt within a run does **not** silently retry-forever inside the same Celery task — it fails the task with `failure_class: PROVIDER_RATE_LIMITED` (§29) after at most 2 in-task retries, letting the platform's normal Celery-retry/backoff policy (6A §21) govern the next attempt rather than blocking a worker slot.
5. **Per-tenant fairness:** the Redis `SETNX` per-connection lock (§15.3) already prevents one tenant's sync from starving others at the connector level; no additional cross-tenant fair-queueing is introduced — Celery's own per-queue concurrency limits (already-approved infra, out of this document's authority) are the platform-wide backstop.

---

## 17. Webhook Architecture (Outbound)

Two directions exist and are never conflated (6A §28.3, restated here as binding for every endpoint in §18–§24):

| | Outbound (§17–§23) | Inbound (§24) |
|---|---|---|
| Direction | Platform → tenant's external system | External provider → platform |
| Resource | `WebhookEndpoint` / `WebhookDelivery` | `InboundWebhookEvent` |
| Who configures it | The tenant, via this document's APIs | The provider, out-of-band (dashboard/config on the provider's side pointing at a platform-owned URL) |
| Trust boundary | Platform signs; tenant's server verifies | Provider signs (where supported); platform verifies |
| Auth on the HTTP call | None — the platform is the caller; the signature *is* the authentication | None (JWT) — provider signature or platform-generated shared secret is the authentication (§24.2) |

### 17.1 Fully Reused From 5I/6A — Not Redesigned

`webhook_endpoints`: HTTPS-only `target_url` (DB CHECK), `topics TEXT[]` (non-empty, DB CHECK), `signing_secret_ref` (opaque, DB CHECK), `max_attempts` (1–10, default 7), `timeout_ms` (1000–30000, default 10000), `status ∈ {ACTIVE, DISABLED, SUSPENDED}`. `webhook_deliveries`: partitioned monthly, `PENDING → DELIVERING → {DELIVERED | back to PENDING (retry) | DEAD_LETTER}`, `PENDING → CANCELLED`. All of §17–§23 is built directly on this — see 5I §11–16, §28 for the DDL this document assumes verbatim.

---

## 18. Webhook Subscription Model & Management APIs

### 18.1 Resource Shape

```json
{
  "id": "01930000-0000-7000-8000-000000000020",
  "display_name": "Production event sink",
  "target_url": "https://hooks.acme.example/platform-events",
  "topics": ["call.completed", "lead.created", "campaign.completed"],
  "status": "ACTIVE",
  "max_attempts": 7,
  "timeout_ms": 10000,
  "endpoint_verified_at": null,
  "last_delivery_at": "2026-08-29T09:40:00Z",
  "created_by": { "user_id": "...", "display_name": "Priya Sharma" },
  "created_at": "2026-08-01T00:00:00Z"
}
```
`signing_secret_ref` is never in this response — a signing secret is returned exactly once, at creation and at rotation (§21.3).

### 18.2 `GET /api/v1/webhook-endpoints`

- **Permission:** `webhook:read`. **Tenant scope:** RLS. **Query:** `?status=`, `?topic=` (GIN-indexed, `idx_we_org_topics`). Cursor pagination.

### 18.3 `POST /api/v1/webhook-endpoints`

- **Permission:** `webhook:manage`.
- **Request:**
```json
{
  "display_name": "Production event sink",
  "target_url": "https://hooks.acme.example/platform-events",
  "topics": ["call.completed", "lead.created"],
  "max_attempts": 7,
  "timeout_ms": 10000
}
```
- **Validation (fails `422 WEBHOOK_URL_UNSAFE` before any DB write):** `target_url` must be `https://`; every §30 SSRF check runs at registration time (resolve-then-pin DNS, reject loopback/link-local/RFC1918/cloud-metadata unless enterprise allow-listed, reject non-standard ports where policy restricts them). `topics` non-empty, every value must be a recognized topic from §19's governed catalog (`422 VALIDATION_ERROR` with `details.invalid_topics` for any unrecognized value — this is an application-layer allow-list check; the DB column itself is free TEXT[], §5I §12).
- **Behavior:** Application Service generates a random 256-bit signing secret, stores it via secret manager → `signing_secret_ref`, then ordinary `INSERT` (this table **does** grant `app_api` INSERT directly, 5I §28 — no SECURITY DEFINER function needed or present, and none is required).
- **Response `201`:** the endpoint **plus** `signing_secret` (raw, one-time-reveal, per 6A §22's "returned once" pattern — mirrors API key creation, 6B §16.5): `{ "data": { ...§18.1 shape..., "signing_secret": "whsec_...raw-value-shown-exactly-once..." } }`.
- **Idempotency:** `Idempotency-Key` **required** (creates a resource with a real external-notification side effect once deliveries start).
- **Audit:** `WEBHOOK_ENDPOINT_CREATED` (5J §14.3's own confirmed vocabulary entry — reused verbatim, not invented).
- **Domain event:** `webhook.endpoint_created` (4F §12.4, reused verbatim).

### 18.4 `GET /api/v1/webhook-endpoints/{webhook_endpoint_id}`

Standard single-resource GET, `ETag` per 6A §17.2. `404` on cross-tenant access.

### 18.5 `PATCH /api/v1/webhook-endpoints/{webhook_endpoint_id}`

- **Permission:** `webhook:manage`. **Fields:** `display_name`, `target_url` (re-runs full §30 SSRF validation — a PATCH that changes the target is not exempt from registration-time checks), `topics`, `max_attempts`, `timeout_ms`.
- **Concurrency:** `If-Match` required (ordinary UPDATE-grant table, no state-machine guard beyond the `status` CHECK — 6A §17.2's weak-ETag path applies).
- **Audit:** `WEBHOOK_ENDPOINT_UPDATED`.

### 18.6 `DELETE /api/v1/webhook-endpoints/{webhook_endpoint_id}`

**Corrected audit semantics (remediation §17, P1) — the endpoint's effect and its audit token must agree.** Per 6A §7.6 and ADR-6J-02 (§55): `app_api` has **no DELETE grant** on `webhook_endpoints` (5I §28 — only `SELECT, INSERT, UPDATE`; `DELETE` is `app_platform_admin`-only), so this document maps the `DELETE` HTTP verb to the **exact same underlying transition** as §18.8's explicit `disable` action: `status → 'DISABLED'`, `disabled_at = NOW()` (ordinary UPDATE, within grant). This document offers `DELETE` as a REST-conventional alias for the identical disable operation §18.8 also exposes (6A §7.6 explicitly sanctions "DELETE maps to the aggregate's own terminal-ish transition" for this resource shape) — a client may use either verb, and both produce identical state and identical audit output.
- **Response:** `204`.
- **Audit:** `WEBHOOK_ENDPOINT_DISABLED` — **not** `WEBHOOK_ENDPOINT_DELETED` (corrected; a prior revision emitted the `_DELETED` token here despite no row being deleted, which misrepresented the actual effect in the audit trail — the audit token now truthfully reflects what happened, matching §18.8's own token exactly, since the two endpoints perform the identical operation). Hard physical deletion remains a platform-admin/compliance-only operation (data-retention concern, §41), never tenant-self-service, and has no tenant-facing endpoint anywhere in this document.

### 18.7 `POST /api/v1/webhook-endpoints/{webhook_endpoint_id}/enable`

`status → 'ACTIVE'`. Ordinary UPDATE. **Audit:** `WEBHOOK_ENDPOINT_ENABLED`.

### 18.8 `POST /api/v1/webhook-endpoints/{webhook_endpoint_id}/disable`

`status → 'DISABLED'`, `disabled_at = NOW()`. Per 4F §8.1's invariant #3, a `SUSPENDED` (system-driven, §22.5) or `DISABLED` (tenant-driven) endpoint receives no new deliveries; deliveries already `PENDING`/`DELIVERING` at the moment of disable complete normally (not cancelled retroactively — avoids racing the delivery worker). **Audit:** `WEBHOOK_ENDPOINT_DISABLED`.

### 18.9 `POST /api/v1/webhook-endpoints/{webhook_endpoint_id}/rotate-secret`

See §21.3 for the full contract.

### 18.10 `POST /api/v1/webhook-endpoints/{webhook_endpoint_id}/test`

- **Purpose:** deliver a synthetic test event so the tenant can verify their endpoint is reachable and their signature-verification code is correct, without waiting for a real domain event.
- **Permission:** `webhook:manage`.
- **Behavior:** creates one `webhooks.webhook_deliveries` row exactly like a real delivery, with `event_type = "platform.test"` (§53 — a dedicated, non-domain event type; **never** a fabricated real domain event, per the task's explicit prohibition) and a fixed, documented `payload.data.object` shape (`{"message": "This is a test event from the platform.", "triggered_by": "<user display name>"}`). Delivered through the exact same signing/retry/timeout pipeline as any other delivery — this is the only way a test is meaningful (a shortcut path would not actually validate the tenant's signature-verification code).
- **Response `202`:** `{ "data": { "delivery_id": "...", "status": "PENDING" } }` — poll `GET .../webhook-deliveries/{delivery_id}` (§23) for the outcome.
- **Rate limit:** 10/hour per endpoint (application-layer quota, prevents test-triggered delivery-history bloat).
- **Delivery-history visibility:** test deliveries **do** appear in `GET .../webhook-deliveries` (§23) — they use the real table, no shadow history — but are marked `is_test: true` in the response so tenants (and support) can filter them out.
- **Idempotency:** N/A (each call intentionally creates a new, distinct test delivery).

---

## 19. External Event Catalog

### 19.1 Governed Vocabulary — 4F §8.4, Reused Verbatim

The platform's webhook topic catalog is **already fixed** by 4F §8.4 ("the authoritative list of supported webhook topics — the Published Language of the platform's event-driven integration API") and confirmed compatible with the executed `webhook_endpoints.topics TEXT[]` column (5I §12: free text, forward-compatible, no DB-level enum to conflict with). This document does not invent a new catalog — it reuses 4F's 19 topics and documents, per topic, the fields the task brief additionally requires (producer context, resource ID field, sensitive-data classification, schema version).

| Topic | Producer (bounded context) | Resource ID field | Sensitive data? | Schema version |
|---|---|---|---|---|
| `call.started` | Voice (6D) | `call_id` | No (metadata only — no transcript/recording) | 1 |
| `call.completed` | Voice (6D) | `call_id` | No — `recording_url`/`transcript` are **never** embedded (§40); reference-by-ID only | 1 |
| `call.failed` | Voice (6D) | `call_id` | No | 1 |
| `call.transferred` | Voice (6D) | `call_id` | No | 1 |
| `lead.created` | CRM (6G) | `contact_id` | Yes — `phone_number`/`name` may appear in `data.object` (§40 classifies exact fields) | 1 |
| `lead.qualified` | CRM (6G) | `contact_id` | Yes | 1 |
| `lead.disqualified` | CRM (6G) | `contact_id` | Yes | 1 |
| `deal.created` | CRM (6G) | `deal_id` | Possibly (deal name may embed contact info) | 1 |
| `deal.won` | CRM (6G) | `deal_id` | Possibly | 1 |
| `deal.lost` | CRM (6G) | `deal_id` | Possibly | 1 |
| `appointment.booked` | CRM (6G) | `appointment_id` | Yes (contact identity + timing) | 1 |
| `campaign.started` | Campaign (6H) | `campaign_id` | No | 1 |
| `campaign.completed` | Campaign (6H) | `campaign_id` | No | 1 |
| `campaign.contact.qualified` | Campaign (6H) | `campaign_contact_id` | Yes | 1 |
| `invoice.created` | Billing (future 6K) | `invoice_id` | Financial — amount/currency, no card data (never stored, 6A §22 payment-provider carve-out) | 1 |
| `invoice.paid` | Billing (future 6K) | `invoice_id` | Financial | 1 |
| `payment.failed` | Billing (future 6K) | `payment_attempt_id` | Financial | 1 |
| `usage.threshold_reached` | Usage/Billing (future 6K) | `organization_id` only | No | 1 |
| `subscription.changed` | Billing (future 6K) | `subscription_id` | No | 1 |

**All 19 are webhook-eligible** — 6A §28.1 itself cites `call.completed`/`campaign.finished`/`invoice.generated` as its own canonical examples of this mechanism, confirming this is already-authorized platform behavior, not a new exposure decision made unilaterally by this document.

**Not currently in the governed catalog** (and therefore not subscribable via `topics`, since §18.3 validates against this exact list): agent lifecycle (`agent.created/updated/activated`), workflow execution (`workflow.execution.started/completed/failed` — 6I §43 classifies these as **internal domain events**, not confirmed webhook-eligible), and knowledge/document ingestion (`document.ingested`, `knowledge_base.sync_completed`). Adding any of these is an additive, non-breaking extension of the `TEXT[]` column (5I explicitly designed it forward-compatible) — flagged as a **non-blocking forward product decision** (§57 DEC-6J-04), not fabricated here.

### 19.2 Billing Events — Confirmed Authorized, Not Yet Producible

`invoice.*`/`payment.*`/`subscription.*`/`usage.*` topics are named in 4F's governed catalog and their webhook-eligibility is confirmed, but **6K (Billing APIs) has not been designed yet** — no producer exists today to write these into `audit.domain_event_outbox`. This document defines them as valid, subscribable topics (a tenant may register a `WebhookEndpoint` with `topics: ["invoice.created"]` today) — but no delivery will ever be created for them until 6K ships its own outbox-insert call sites. This is not a 6J gap; it is an explicit forward dependency on 6K, recorded at §57.

---

## 20. Webhook Event Envelope

### 20.1 Canonical Shape — Reconciled With 6A §27.3, Not a Second Envelope

6A §27.3 already formalizes a generic envelope for realtime (WebSocket) events; this document defines the **outbound webhook** envelope as the same conceptual shape, adapted for HTTP delivery (no `sequence` field — 6A §28.1 already establishes webhook ordering is **not guaranteed**, so a per-connection sequence counter would be misleading):

```json
{
  "id": "evt_01930000-0000-7000-8000-000000000030",
  "type": "call.completed",
  "version": 1,
  "occurred_at": "2026-08-29T10:00:00Z",
  "organization_id": "01930000-0000-7000-8000-0000000000aa",
  "data": {
    "object": {
      "call_id": "01930000-...",
      "status": "COMPLETED",
      "duration_seconds": 127,
      "direction": "OUTBOUND"
    }
  },
  "request_id": "01930000-0000-7000-8000-000000000031"
}
```

| Field | Source | Notes |
|---|---|---|
| `id` | `webhook_deliveries.event_id` | Stable across retries **and** replays (§23.3) — the consumer's dedup key |
| `type` | `webhook_deliveries.event_type` | One of §19's governed topics |
| `version` | Application-assigned per event type (independent of `/api/v1` URL versioning, 6A §27.3/§30) | Starts at `1` for every topic in §19.1's table |
| `occurred_at` | The domain event's own timestamp (not `webhook_deliveries.created_at`, which is delivery-record creation time, and not delivery-attempt time) | ISO 8601 UTC, 6A §7.5 |
| `organization_id` | `webhook_deliveries.organization_id` | Always present — no platform-global event is ever delivered as an outbound webhook |
| `data.object` | Topic-specific, minimized per §40 | Never a full internal row dump |
| `request_id` | The delivery attempt's own correlation ID | For the tenant's support team to correlate with platform support, distinct from `id` |

`data` is deliberately nested one level (`data.object`) rather than flat, matching a widely-recognized webhook envelope convention and leaving room for a future `data.previous_attributes` (change-diff) field without a breaking change.

### 20.2 What Is Never in the Envelope

Internal-only fields: `webhook_endpoint_id` (the tenant already knows which endpoint they registered), `attempt_count`, `claimed_by`, `payload_hash`, any `SECURITY DEFINER` function name, any other tenant's data. `data.object` is built by a per-topic serializer that is itself an explicit allow-list (mirrors 6A §10.2's response-model allow-list discipline applied to webhook payloads, not just REST responses).

---

## 21. Webhook Signing & Secret Rotation

### 21.1 Signing Protocol — Exact, 5I/4F-Sourced

**Algorithm:** HMAC-SHA256. **Signature input:** `f"ts={unix_timestamp}.{payload_json}"` where `payload_json` is the exact raw JSON bytes of the request body (§20's envelope, serialized once and never re-serialized differently between signing and sending — re-serializing with different key ordering would silently break the signature). **Header:** `X-Platform-Signature: v1={hex_signature}` (5I §16, 4F §8.3's `WebhookSignatureService` — this exact scheme is a **Published Language contract with external consumers**, per 4F §8.3's own reasoning: *"If the algorithm changes, external consumers' verification code breaks. This is a business contract."* 6J does not alter it.)

**Additional headers sent with every delivery:**

| Header | Value |
|---|---|
| `X-Platform-Signature` | `v1={hex_signature}` |
| `X-Platform-Timestamp` | The same `unix_timestamp` used in the signature input(s) |
| `X-Platform-Event-Id` | `webhook_deliveries.event_id` (= envelope `id`) |
| `X-Platform-Delivery-Id` | `webhook_deliveries.id` — **distinct** from `event_id`; changes on replay (§23.3) |
| `X-Platform-Webhook-Version` | The envelope `version` (schema version, not API version) |

**Dual-signature rotation grace (corrected — remediation §6, ADR-6J-07, P0):** while a `WebhookEndpoint` has an unexpired `previous_signing_secret_ref` (i.e. `NOW() < previous_secret_expires_at`, §56/`101_5I1.sql`), the delivery worker computes **two** signatures — one with the current secret, one with the previous secret — over the **identical** `f"ts={unix_timestamp}.{payload_json}"` input (same timestamp, same body, only the key differs), and emits both:

```
X-Platform-Signature: v1={hex_signature_current}
X-Platform-Signature-Previous: v1={hex_signature_previous}   -- present ONLY during an active grace window
```

Once `previous_secret_expires_at` passes, `X-Platform-Signature-Previous` stops being emitted (the delivery worker checks the expiry on every send, not just at rotation time) — a stale, expired previous secret is never signed with, regardless of whether its DB reference has been purged yet.

### 21.2 Consumer Verification Contract (Binding Guidance, Not DB-Enforced)

Consumers **MUST**:
1. Recompute `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")` over the **raw, unparsed** request body bytes (parsing-then-re-serializing before verifying is a documented consumer footgun that silently breaks verification on whitespace/key-order differences) and compare against `X-Platform-Signature`'s hex value using **constant-time comparison** (`hmac.compare_digest` or equivalent — a naive `==` string comparison leaks timing information about how many leading bytes matched).
2. **During a secret rotation**, if verification against `X-Platform-Signature` (the current secret) fails and `X-Platform-Signature-Previous` is present, retry verification against `X-Platform-Signature-Previous` using the consumer's still-deployed old secret before rejecting — this is what makes the rotation grace window (§21.3) actually functional; a consumer that only ever checks `X-Platform-Signature` is unaffected outside of an active rotation and needs no code change to keep working, but will reject deliveries during a rotation until it redeploys with the new secret (exactly the pre-grace-window behavior — the grace window is an *opt-in* smoother transition, not a requirement to consume).
3. Reject any delivery where `X-Platform-Timestamp` is more than **5 minutes** older than the consumer's current time (5I §16's documented replay window, reused verbatim — this bounds how long a captured-and-replayed HTTP request stays valid even if TLS were somehow compromised in transit) — this check applies identically regardless of which of the two signatures matched.
4. Treat `X-Platform-Event-Id` as the idempotency key — a consumer that has already processed this `event_id` (from a retry or a replay) MUST NOT re-apply its side effect a second time.

### 21.3 `POST /api/v1/webhook-endpoints/{webhook_endpoint_id}/rotate-secret`

- **Permission:** `webhook:manage`.
- **Behavior:** generates a new 256-bit secret, stores it via the secret manager as a **new** `signing_secret_ref`, then calls `webhooks.fn_rotate_webhook_secret(org_id, webhook_endpoint_id, new_secret_ref, grace_period_seconds)` (§56, added by `101_5I1.sql`) — atomically moves the **current** `signing_secret_ref` into `previous_signing_secret_ref` (with `previous_secret_expires_at = NOW() + grace_period_seconds`) and installs the new secret as current, in one guarded call (not two separate `UPDATE`s that could race against an in-flight delivery reading a half-updated row).
- **Request:** `{ "grace_period_seconds": 3600 }` (optional, default 3600 = 1 hour, `0`–`86400` DB-CHECKed range; `0` disables the grace window entirely — immediate hard cutover).
- **Overlapping validity window:** for `grace_period_seconds` following rotation (default 1 hour), the platform genuinely signs every outbound delivery with **both** secrets (§21.1's dual-signature header pair) — this is the corrected mechanism; the prior design's "retain the old secret without ever signing with it" gave no working grace period at all (ADR-6J-07). The response discloses `previous_secret_expires_at` so the tenant knows their redeployment deadline. After the window, `X-Platform-Signature-Previous` stops being emitted, and the old secret's secret-manager entry is purged by the Application Service.
- **Response `200`:** `{ "data": { "signing_secret": "whsec_...new raw value, shown once...", "rotated_at": "...", "previous_secret_expires_at": "2026-08-29T11:00:00Z" } }` — the **new** secret is returned exactly once, per §12.1 rule 6; the **old** secret is never re-shown (it was already shown once, at its own creation/rotation time).
- **Idempotency:** `Idempotency-Key` optional but recommended — each successful call generates a genuinely new secret, so replaying it (without a key) would rotate twice, discarding the *previous* rotation's own grace window prematurely; with a key, a retried request returns the same newly-generated secret rather than generating a second one.
- **Audit:** `WEBHOOK_SECRET_ROTATED` — payload never includes either secret value (§12.1 rule 3).

---

## 22. Webhook Delivery Semantics & Retry / Backoff

### 22.1 Delivery Guarantee — At-Least-Once, Explicitly Not Exactly-Once

**Binding statement (6A §28.1, restated as authoritative here):** delivery is **at-least-once**. This platform makes no exactly-once claim over HTTP, ever — a delivery that succeeds at the provider but whose `2xx` response is lost to a network partition before the platform observes it will be retried, producing a duplicate. §21.2 rule 3 (consumer dedup on `event_id`) is the platform's answer to this, not a promise that duplicates cannot occur.

### 22.2 Ordering

**Not guaranteed globally, not guaranteed per endpoint, not guaranteed per event type.** 6A §28.1: *"consumers must be resilient to out-of-order delivery, consistent with the platform-wide eventual-consistency model (4G §12)."* A `call.started` delivery may arrive after its corresponding `call.completed` delivery for the same call under retry/backoff skew. Consumers needing ordering must use `occurred_at` (§20.1) to reorder client-side, or query the platform's own REST API for current state rather than trusting delivery order as a state machine.

### 22.3 Retry / Backoff — Exact Values

| Attempt | Backoff before this attempt (from `WebhookRetryPolicy.BackoffSchedule`, 4F §8.1.1) |
|---|---|
| 1 | Immediate (on `DeliveryCreated`) |
| 2 | 30s |
| 3 | 60s |
| 4 | 5m |
| 5 | 30m |
| 6 | 2h |
| 7 | 8h |
| (8, if `max_attempts` raised above default 7) | 24h |

`max_attempts` is per-endpoint configurable, `1–10` (5I `chk_we_max_attempts`); default `7`. `timeout_ms` per-endpoint, `1000–30000`; default `10000`. **HTTP timeout behavior:** a delivery attempt that exceeds `timeout_ms` is treated identically to a non-2xx response — it counts as a failed attempt and schedules the next backoff step.

### 22.4 Accepted Status Range / Retryable vs. Terminal

| Response | Classification |
|---|---|
| `200`–`299` | Success → `DELIVERED` |
| `300`–`399` | **Not followed** — a webhook delivery never follows an HTTP redirect (an endpoint returning a 3xx is treated as a failed attempt; this is a deliberate SSRF-adjacent control, §30 — silently following a redirect would let a compromised/misconfigured tenant endpoint retarget delivery traffic) |
| `400`–`499` (except `429`) | Retryable, same backoff schedule as any other failure — a `4xx` from a tenant's endpoint is not assumed permanent (a temporarily misconfigured auth check on their side is common and self-correcting) |
| `429` | Retryable; if `Retry-After` is present it is honored (capped at the delivery's own next backoff-schedule ceiling, never extended beyond it — a malicious/misconfigured target cannot use `Retry-After` to indefinitely pin a delivery slot) |
| `500`–`599` | Retryable |
| Connection refused / DNS failure / TLS failure / timeout | Retryable, classified as a network-layer failure in `failure_reason` |

No response code is ever treated as "stop retrying immediately, skip to dead-letter" — 5I's model has no such override; `max_attempts` exhaustion is the only path to `DEAD_LETTER` (`webhooks.fn_delivery_failed()`, 5I FIX-02, DB-enforced regardless of caller intent).

### 22.5 Suspension

**Not implemented at the DB layer** — 5I's `webhook_endpoints.status = 'SUSPENDED'` value exists (`chk_we_status`) but, like plugin `SUSPENDED` (§56 DEP-6J-02), **no function transitions an endpoint into or out of it automatically**. This document specifies the intended policy (a future migration's target behavior, not implementable today): an endpoint whose **last 20 consecutive deliveries** all reached `DEAD_LETTER` is auto-transitioned to `SUSPENDED` (no new deliveries created for it until a tenant explicitly re-enables it via §18.7) — flagged as **DEP-6J-07** (§56), non-blocking (tenant-visible `DEAD_LETTER` accumulation via §23 is sufficient signal in the interim; nothing breaks by this policy not existing yet, it is a quality-of-life protection against a permanently-broken endpoint quietly consuming delivery-worker capacity forever).

### 22.6 Dead-Letter Retention

`DEAD_LETTER` deliveries retained 90 days (5I §14, 4F §8.2 invariant #3 — the two sources agree exactly). `DELIVERED` deliveries purged after 30 days (5I §23 GDPR/PII table). Both are operational housekeeping, not independently DB-scheduled (5I has no pg_cron job for this — same documented pattern as `audit.domain_event_outbox`'s own retention, §41) — a background cleanup process, owned by ops/platform infrastructure, performs the actual `DELETE`.

---

## 23. Webhook Delivery APIs & Replay

### 23.1 `GET /api/v1/webhook-deliveries`

- **Permission:** `webhook:read`. **Query:** `?webhook_endpoint_id=` (required or defaults to "all of this org's endpoints" — `idx_wd_endpoint`), `?status=` (`idx_wd_status`), cursor pagination (mandatory here — `webhook_deliveries` is one of 6A §13's explicitly named high-volume partitioned tables; offset pagination is disallowed).
- **Response fields per delivery:** `id`, `event_id`, `event_type`, `status`, `attempt_count`, `max_attempts`, `next_attempt_at`, `last_attempt_at`, `last_response_code`, `last_response_body_preview` (≤512 chars, DB-capped, §12.1 rule 4's "never a raw provider response" principle extended: this preview is the *tenant's own endpoint's* response, not a third-party provider's, so it is shown — but still truncated/sanitized, since it is still untrusted external content, 5I FIX-11), `is_test`, `created_at`. **Never shown:** any authentication header value, the signing secret, `claimed_by` (internal worker identity), `payload_hash` (internal dedup artifact only).

### 23.2 `GET /api/v1/webhook-deliveries/{delivery_id}`

Adds `payload_json` (the exact envelope that was/will be sent — useful for a tenant debugging their own consumer) and `failure_reason` (≤2000 chars, DB-capped, sanitized untrusted content). `404` on cross-tenant/cross-partition access — the composite PK (`id, created_at`) means the API layer must know (or discover via an indexed lookup) the `created_at` partition key; this is an internal query-shaping detail, invisible to the client, who addresses the resource by `id` alone.

### 23.3 `POST /api/v1/webhook-deliveries/{delivery_id}/replay`

- **Purpose:** privileged manual redelivery of a `DEAD_LETTER` or already-`DELIVERED` delivery.
- **Permission:** `webhook:manage` (strictly greater than `webhook:read` — replay is a privileged write action, not observability).
- **Replayable window:** any delivery still within its 30/90-day retention window (§22.6) — a delivery already purged cannot be replayed (there is no row left to replay from); `404 WEBHOOK_DELIVERY_NOT_FOUND`.
- **Behavior:** calls `webhooks.fn_replay_webhook_delivery()` (5I §28) — creates a **new** `webhook_deliveries` row (`replay_of_delivery_id` set to the original), `status = 'PENDING'`, fresh `next_attempt_at = NOW()`. The **original** row's `payload_json`/result history is untouched (immutable, `fn_wd_identity_immutable` trigger) — only its `replay_count`/`last_replayed_at` metadata fields are updated.
- **Event ID vs. Delivery ID on replay:** the new row inherits the **same** `event_id` (`webhook_deliveries.event_id` — 5I's function copies it verbatim from `v_orig`) — the replayed delivery is, from the consumer's perspective, the identical logical event arriving again, which is exactly why §21.2 rule 3 (dedup on `event_id`, not delivery ID) matters. The **delivery ID** (`id`, and therefore `X-Platform-Delivery-Id`) is new and distinct.
- **Signature regeneration:** yes — the replay delivery gets a fresh `unix_timestamp` and therefore a freshly-computed `X-Platform-Signature` at send time (the original signature, computed against the original timestamp, would now fail §21.2 rule 2's 5-minute freshness check on the consumer side if reused).
- **Idempotency (of the replay *request* itself):** `fn_replay_webhook_delivery()` is itself idempotent — a second `POST .../replay` call while the first replay is still `PENDING`/`DELIVERING` returns the **same** new delivery ID rather than creating a second one (5I §15/§28). No client-supplied `Idempotency-Key` is required for this reason, though one is still accepted and honored per 6A §16 for defense-in-depth against network-level double-submission.
- **Maximum replay frequency:** 10 replays per delivery per 24 hours (application-layer quota — prevents a stuck-but-not-yet-purged dead letter from being replay-hammered).
- **DB execution note (ADR-6J-01, §55):** `fn_replay_webhook_delivery()`'s `EXECUTE` grant was widened to include `app_api` directly by `101_5I1.sql`'s grant-widening (§56) — no internal-RPC hop; the endpoint calls the function directly within its own request transaction. HTTP contract remains synchronous (`200`), since the underlying operation is a single fast in-transaction DB call with no external I/O.
- **Response `200`:** the new delivery row, `status: "PENDING"`.
- **Audit:** `WEBHOOK_DELIVERY_REPLAYED`.

---

## 24. Inbound Provider Webhooks

### 24.1 Pipeline (Binding Architecture)

```
Provider → Provider Adapter (provider-specific route, e.g. /api/v1/integrations/providers/{provider_slug}/callback)
    → Verification (§24.2 — provider-native signature, or platform-issued shared secret where the provider has none)
    → Fast ACK (§24.4 — 2xx returned before any domain processing)
    → webhooks.inbound_webhook_events INSERT (§24.3 — idempotent)
    → Normalize (provider wire format → platform-neutral shape)
    → Deduplicate (DB UNIQUE constraint is the actual guarantee; §24.3)
    → Async domain processing (Celery) → owning bounded context's ACL → domain command
```

**Inbound provider endpoints never expose internal domain implementation directly** — a provider's payload never reaches a CRM/Campaign/Voice application service un-translated; the Provider Adapter's ACL is the only code that understands the provider's wire format (4F §6.3, reused).

### 24.2 Verification

| Provider capability | Verification method |
|---|---|
| Provider signs its webhooks (most CRM/payment/messaging providers) | Verify the provider's own HMAC/RSA signature scheme against a platform-stored shared secret (obtained during OAuth/connection setup, stored via `credential_ref` exactly like any other integration secret, §12) — **never** trust the payload solely because the request reached the endpoint |
| Provider does not sign (rare, legacy) | A platform-generated, connection-specific shared secret is embedded in the callback URL the tenant configures on the provider's side (`?token=` or a per-connection path segment) — validated as a constant-time string comparison, not a cryptographic signature, and disclosed to the tenant as a materially weaker guarantee in the connection's setup UI copy |
| Source IP allow-listing | Defense-in-depth only, **never** the sole control (per the task brief's explicit instruction) — applied only where a provider publishes a stable, documented IP range |
| Timestamp/nonce | Honored where the provider supplies one (mirrors §21.2's outbound replay-window discipline, applied inbound); where absent, the DB-level dedup key (§24.3) is the actual protection, not a timestamp heuristic |

### 24.3 Deduplication — Exact Mechanism, Race-Safe by Construction

`UNIQUE (organization_id, provider_slug, provider_event_id)` on `webhooks.inbound_webhook_events` (5I `uq_iwe_org_provider_event`, **FIX-08**, tenant-scoped — two different tenants may legitimately receive the same `provider_event_id` from the same provider, e.g. two tenants both connected to the same Slack app receiving a platform-level Slack event; this is explicitly allowed, not a collision).

**Corrected enqueue coupling (remediation §13, P1):** the insert statement is

```sql
INSERT INTO webhooks.inbound_webhook_events (organization_id, provider_slug, provider_event_id, event_type, ...)
VALUES (...)
ON CONFLICT (organization_id, provider_slug, provider_event_id) DO NOTHING
RETURNING id;
```

and the async processing task (Celery) is enqueued **if and only if this statement actually returns a row** — the request handler checks `RETURNING id` explicitly rather than assuming "the INSERT ran, therefore enqueue." A prior revision's prose ("the second request has no row, so no worker picks it up") described the right outcome but did not make the enqueue-gating explicit as an implementation requirement; this is now stated as a hard requirement, not an incidental consequence engineers might miss. If `RETURNING id` yields no row (a duplicate), the handler skips the enqueue and proceeds straight to the fast-ACK (§24.4) — the DB constraint is the actual guarantee, and the application code path is written so it cannot accidentally enqueue a duplicate task even if the constraint alone would have prevented the duplicate row.

**Concurrency:** two nearly-simultaneous deliveries of the same event (a real-world provider behavior, not just a theoretical race) resolve safely under this exact pattern — for the second, concurrent `INSERT`, PostgreSQL's `ON CONFLICT` handling ensures at most one of the two statements returns a row; the other returns zero rows and its handler does not enqueue, deterministically, not by a "probably fine" race argument.

**Fallback fingerprinting (where a provider supplies no stable event ID) — corrected ordering (remediation §14, P1):** the prior design computed `provider_event_id` from "normalized_payload_bytes," which risked implying the platform's own post-insert domain-normalization step (provider wire format → platform-neutral shape, §24.1) was the input to the fingerprint — but that normalization happens *after* the durable insert this fingerprint is the key for, which is a circular/wrong ordering. The corrected fingerprint is computed **before** insert, from **verification-stage, pre-domain-normalization** material only: `provider_event_id := SHA-256(provider_slug || "." || raw_verified_request_body_bytes)` — the same raw bytes signature verification (§24.2) already validated, never the output of the ACL's later normalize step. This keeps "verify and canonicalize for dedup" strictly separate from "normalize into a domain command," which happens only afterward, only for a row that survived the dedup insert. This fallback remains a disclosed, honest limitation for providers with no stable event ID: two structurally-identical-but-legitimately-distinct events (e.g. two separate "contact updated" pings with identical field values) would incorrectly dedupe against each other — not silently presented as equivalent to a provider-native ID.

**Retention:** `inbound_webhook_events` is unpartitioned V1 (5I §27) with no dedicated TTL — retained under the platform's general audit/observability retention policy (§41) until §27's `>5M rows` partitioning threshold is reached, at which point a partitioning migration (out of this document's scope, matching 5I's own explicit "if >5M rows" note) is required.

**Duplicate response behavior:** the provider always receives the same `2xx` fast-ACK (§24.4) whether the event was newly inserted or was a duplicate silently ignored — the provider has no way to distinguish the two, by design (a provider should never infer platform-internal dedup state from the response).

### 24.4 Fast ACK, Async Processing, Payload Validation

- **Fast ACK:** the endpoint returns `2xx` **immediately after** the `INSERT ... ON CONFLICT DO NOTHING RETURNING id` commits (§24.3) — never after synchronous domain processing. `status` starts `RECEIVED`; a Celery task (enqueued only when `RETURNING id` yielded a row, §24.3) picks it up and drives it through `PROCESSING → PROCESSED | FAILED | SKIPPED` via `webhooks.fn_update_inbound_event_status()` (5I §28, unchanged — `app_worker`-only `EXECUTE`, deliberately: these are worker-pipeline-internal transitions, never called from the inbound HTTP request path itself, so the internal-RPC-removal reasoning in ADR-6J-01 does not apply here — this function was never a candidate for direct `app_api` access to begin with, since no tenant-facing endpoint ever calls it).
- **Request-size limits:** 1MB per inbound callback body (application-layer `413 PAYLOAD_TOO_LARGE` before the body is even fully buffered, where the framework supports streaming size-checking) — bounds a malicious/misbehaving provider from using the callback endpoint as an amplification or storage-exhaustion vector.
- **Payload validation:** the Provider Adapter's ACL schema-validates the payload shape **after** dedup-insert, **before** normalization — a malformed payload that passes signature verification but fails shape validation is recorded `status = 'FAILED'`, `failure_reason` set (≤2000 chars, DB-capped), and does not propagate to any domain command. `RECEIVED`-but-uninterpretable payloads are never silently dropped without a durable row — the row itself is the observability artifact.
- **Retry behavior (provider-initiated, not platform-initiated):** if a provider itself retries an undelivered/unacknowledged callback (common provider-side behavior on their own timeout), the dedup key (§24.3) absorbs it transparently — the platform never asks a provider to retry; it processes what it durably receives, once.
- **Poisoning / bad payloads:** a payload that repeatedly fails shape validation for the *same* `provider_event_id` (a provider bug, not a security event) is not retried by the platform beyond the initial processing attempt — `status = 'FAILED'` is terminal for that row; a provider-side fix and a genuinely new event (new `provider_event_id`) is the recovery path, not an platform-side automatic reprocessing loop.
- **Observability:** `GET /api/v1/inbound-webhook-events` / `GET /api/v1/inbound-webhook-events/{id}` (permission `integration:read`) expose `provider_slug`, `event_type`, `status`, `received_at`, `processed_at`, `failure_reason` — **never** `raw_payload_ref`'s resolved content by default (§40/§41; V1 default is to not even store raw payloads, 5I ADR-5I-010) and never the provider signature header's raw value.

### 24.5 6D/Exotel — Explicit Boundary, Not Redesigned

Per §7.5: 6D owns its own dedicated telephony-callback endpoint path and Exotel-specific signature verification; it writes into this same `webhooks.inbound_webhook_events` table using the identical `(organization_id, provider_slug='exotel', provider_event_id)` dedup key this section defines generically. This document does not create, rename, or re-specify that endpoint — 6D's own §10.4 (confirmed at 6D lines 57, 1092, 1653, 1728) already states its callback handling is "a statement of how Voice's telephony callbacks fit inside" 6A §28.2/5I's mechanism, not a competing one. Any *non-telephony* provider whose inbound events are not already owned by another bounded context (generic CRM/payment/messaging providers connected via `IntegrationConnection`) uses **6J's own** generic endpoint:

### 24.6 `POST /api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}`

**Corrected path shape and tenant-resolution sequence (remediation §9, P0, ADR-6J-10).** The prior design accepted `POST .../providers/{provider_slug}/callback` (no per-connection segment) and resolved the target tenant from "an external account identifier embedded in the callback payload" — trusting unverified body content to select which tenant's secret governs verification is a confused-deputy pattern (the payload was trusted to pick its own verifier before anything about it had been verified). This is corrected below.

- **Auth:** **None** (not JWT-authenticated) — the caller is the external provider, not a tenant (6A §28.2's explicit carve-out).
- **`{opaque_connection_route_id}`:** a non-secret, unguessable, per-connection routing token (distinct from, and not derivable from, the connection's own UUID or any credential) generated at connection-creation time and surfaced to the tenant to paste into the provider's own webhook-configuration screen — **this path segment, not any payload field, selects the candidate `IntegrationConnection`** (and therefore which stored public key / shared secret governs verification for this specific request) **before** any payload content is trusted.
- **Corrected resolution sequence:**
  1. `{opaque_connection_route_id}` → candidate `IntegrationConnection` lookup (routing only — this step establishes *which* connection's credential to attempt verification with, not that the request is authentic).
  2. That connection's provider-specific verification material (signed-header key, shared secret, or public key — §24.2, resolved via the connection's own `credential_ref` exactly like any other stored secret) verifies the request.
  3. **Only after verification succeeds** is the connection's `organization_id` treated as trusted tenant context for the rest of the pipeline (§24.1/§24.3) — a payload's own claimed identity is never itself the trust anchor.
  4. If verification fails at step 2, the request is rejected (`401`-equivalent from the provider's perspective, or silently dropped after fast-ACK per the provider's own expected contract — never processed as if step 3 had succeeded).
- **Preferred alternative where the provider supports it:** a provider-native signed key-ID/account-ID (§24.2) is preferred over the opaque-route-segment mechanism where available, since it lets one shared callback URL (no per-connection segment) serve every connection for that provider, with the signed key ID itself doing the routing job post-verification instead of pre-verification. The opaque-route-segment mechanism above is the fallback for providers supporting neither a signed key ID **nor** per-connection callback URL configuration; a provider supporting neither mechanism at all is out of scope for this generic endpoint and requires its own provider-specific callback design (mirroring 6D's own dedicated-endpoint precedent, §24.5) rather than being forced through a weaker generic path.
- **Rate limiting — layered, not tenant-quota-gated (remediation §22):** identity is not yet established when this endpoint is first reached (verification, step 2 above, comes after routing but the request must still be bounded before that). Controls, applied in order: (a) edge-level per-source-IP coarse limiting (6A §20 L1 NGINX tier, unchanged — pre-identity, generic abuse defense); (b) a global per-`provider_slug` ceiling (application-config, protects the ingestion worker pool from one misbehaving provider integration regardless of which connection it targets); (c) **after** step 3 (tenant verified), a per-**connection** ceiling (not per-organization, since one org's several connections to different providers are independent) bounds a single verified-but-compromised or misconfigured connection from monopolizing ingestion capacity; (d) request body size cap (§24.4, 1MB) and concurrent-in-flight-request cap, both pre-verification, bound resource exhaustion regardless of identity. The tenant API quota system (6A §20's per-organization CRUD limiter) never applies here at all — this is 6A §28.2's explicit, unchanged carve-out; a `429` from this endpoint, when it occurs, always originates from one of (a)-(d), never from the tenant-facing quota system a `429` on `/api/v1/*` would come from.
- **Response:** `2xx` fast-ACK per §24.4. Never the platform's standard `{data, meta}`/`{error}` envelope (6A §10.1) — that envelope is for tenant-facing JSON API responses; provider callback responses follow whatever minimal shape (often just an HTTP status, sometimes a provider-specific small JSON ack body) that specific provider's own webhook contract expects.

---

## 25. Plugin Architecture & Security Model

### 25.1 What a "Plugin" Is in This Architecture — Settled, Not Ambiguous

**This is not an open question.** 4F §9.3 and 5I §24's Security Model table both independently, explicitly settle it: *"Plugins run as external HTTP services — they never run code inside the platform's process"* (4F §9.3 "Sandbox" row) and *"Plugins are external HTTP services; no in-process execution"* (5I §24). A `Plugin`'s `PluginManifest.BaseUrl` (4F §9.1.1) is an HTTPS endpoint **the plugin developer hosts and operates** — the platform is a signed, capability-scoped **HTTP client** calling out to it, exactly like it is a client of Salesforce or Slack. No tenant, developer, or admin ever uploads executable code the platform runs. There is no sandbox, no WASM runtime, no per-tenant container, because there is no platform-side code execution to sandbox.

This settles §20 of the governing task brief without an `OWNER DECISION REQUIRED` flag: the task brief's instruction was to flag ambiguity if one existed — none exists here; two independent frozen sources (4F DDD, 5I schema) already made and recorded this decision. This document restates it as binding, not as a decision it is making itself.

### 25.2 What a Plugin V1 Actually Is, Concretely

A **platform-reviewed** (5I: `plugins.status ∈ {PENDING_REVIEW, APPROVED, REJECTED}`), **versioned, manifest-declared** (`plugin_versions.manifest JSONB`, immutable once approved) **remote HTTP integration**, installed per-tenant with tenant-scoped configuration and credentials, invoked by the platform under a declared set of **capabilities** the tenant explicitly enables at activation. It is closest in shape to a "verified connector" or "registered action provider," not an app-store executable and not a raw webhook subscription (which has no manifest, no capability model, no platform review gate).

### 25.3 Security Model — 4F §9.3, Extended Per Remediation §20/§21

| Layer | Mechanism |
|---|---|
| Platform → Plugin authentication | Every callout is HMAC-SHA256-signed by the platform (same algorithm as §21.1, applied outward to plugin callouts — one signing algorithm across the whole platform, not two) using the installation's own shared secret (`plugin_installations.credential_ref`-resolved, distinct per tenant even for the same plugin). **Signature scope corrected (remediation §20, P1):** the prior design signed only the request body, which permits a class of request-context substitution (an attacker who can intercept/replay a signed body onto a different method/path/timestamp still produces a body signature the plugin cannot distinguish from legitimate). The signature input is `f"ts={unix_timestamp}.{method}.{canonical_request_path}.{raw_body}"` — timestamp, HTTP method, canonical path, and raw body all covered — sent as `X-Platform-Signature: v1={hex}` plus `X-Platform-Timestamp`, mirroring §21.1's outbound webhook header shape exactly (one signing convention platform-wide, not two divergent ones). Plugins are documented to apply the identical replay-window discipline as §21.2 rule 3 (reject `X-Platform-Timestamp` more than 5 minutes stale). |
| Tenant isolation — **not a security boundary by itself (clarified, remediation §21)** | Every callout carries `X-Platform-Tenant-Id`. This header communicates which tenant's data a callout concerns; it is **not**, by itself, an enforcement mechanism — the plugin is an external HTTP service outside the platform's trust boundary, and the platform cannot verify or enforce that the plugin's own internal code actually scopes state by this header. What the platform *can* and does guarantee structurally: (a) it never sends one tenant's data in a callout carrying a different tenant's header — the header and the payload are constructed from the same request context, never independently; (b) `plugin_installations.credential_ref` is per-tenant-per-installation, so a plugin cannot use one tenant's credential to authenticate as another; (c) rate limiting (below) is per-`(organization_id, plugin_id)`, so one tenant's usage cannot exhaust another's quota. For plugins handling sensitive data classes, the platform additionally requires (§25.4 addition): platform review of the plugin's own stated data-handling practices before approval, a documented incident-response/revocation path (uninstall + credential purge, §42.3, available to the tenant unilaterally at any time), and minimized payloads (only the specific fields a capability invocation genuinely needs, never a full internal row, §25.4). This is a materially weaker guarantee than the platform's own internal RLS-based tenant isolation (§31), and is documented as such rather than implied to be equivalent. |
| Capability gating | `plugins.fn_activate_plugin()` DB-enforces `enabled_capabilities ⊆ manifest.capabilities` at activation (5I FIX-06); the invoking code additionally checks `capability ∈ installation.enabled_capabilities` at every single invocation, not just at activation time (defense-in-depth — an installation's `enabled_capabilities` can be narrowed after activation via §27's config-update path without a full deactivate/reactivate cycle) |
| Rate limiting | `manifest.RateLimitPerMinute`, enforced **platform-side**, before the HTTP callout, via a Redis token bucket `plugin:ratelimit:{organization_id}:{plugin_id}` (4F §9.3, 3E §16 — reused exactly); `plugin_installations.rate_limit_override` allows a **stricter** per-tenant ceiling than the manifest default, never a looser one (an installation cannot self-grant more throughput than the plugin's own manifest declares) |
| Timeout | `manifest.TimeoutMs` (≤30000, 4F §9.1.1 CHECK) is a hard ceiling on the callout — not negotiable per-invocation |
| Secret isolation | Each tenant's `PluginInstallation.credential_ref` is independent — the same plugin installed by two tenants never shares a secret manager path (5I `plugin_installations.credential_ref`, per-row) |
| Egress/redirect safety | Every plugin callout (`base_url`/`webhook_callback_url`) is routed through the same shared §30.3 egress-control adapter as every other outbound call in this document — including the redirect-credential-stripping rule (§30.3's redirect policy row): a plugin `base_url` that redirects elsewhere causes the callout to fail rather than silently signing for, and sending credentials to, an unreviewed destination |

### 25.4 What Plugins Do NOT Get

A plugin never receives platform database credentials, never receives another tenant's `X-Platform-Tenant-Id`-scoped data, never receives a raw OAuth/API-key credential belonging to an `IntegrationConnection` (plugins and integrations are separate credential namespaces — a plugin cannot silently piggyback on a tenant's Salesforce connection unless the tenant explicitly configures the plugin with its own, separate credential), and never receives more than the specific fields the invoking Application Service constructs for that one capability call (never a full internal row dump — same minimization discipline as §40).

---

## 26. Plugin Catalog & Manifest

### 26.1 `GET /api/v1/plugins`

- **Permission:** `plugin:read`. **Tenant scope:** none (platform-global read, `organization_id IS NULL` per 5I §4) — `Cache-Control: public, max-age=300` (6A §10.3).
- **Visibility filter (application-layer, not a DB column beyond `status`):** only `plugins.status = 'APPROVED'` rows are returned to ordinary tenant callers; `PENDING_REVIEW`/`REJECTED` are visible only to `PLATFORM_ADMIN` callers (a distinct admin-only listing mode, not this endpoint's default tenant-facing behavior) — there is no `plugins.visibility` column distinguishing "public/private/internal/deprecated/disabled" beyond the three-value `status` CHECK; a `DEPRECATED` state (per §29) applies at the **version** level (`plugin_versions.status` includes `DEPRECATED`), not the plugin level.
- **No public third-party marketplace / self-service publisher flow in V1** — every `Plugin` row's `developer_org_id` (5I §28) is populated by whichever internal or partner process registers it; there is no `POST /api/v1/plugins` **tenant-facing** endpoint in this document. Plugin registration/version-submission is a platform-admin/reviewed-partner operation, out of this document's tenant-facing API scope (matching the task brief's explicit instruction not to overbuild a marketplace) — stated explicitly here rather than silently omitted.
- **Response:** array of `{ id, key (slug), name, description, developer, documentation_url, latest_approved_version }`.

### 26.2 `GET /api/v1/plugins/{plugin_key}`

- `{plugin_key}` = `plugins.slug` (stable, immutable). Adds the full list of `APPROVED` `PluginVersion`s (semver, `approved_at`) and the **latest** version's manifest (§26.3) inlined for convenience.
- **Errors:** `404 PLUGIN_NOT_FOUND` (unknown slug, or `PENDING_REVIEW`/`REJECTED` for a non-admin caller — same non-disclosure discipline as cross-tenant 404s, 6A §7.4, applied here to avoid confirming the existence of an unapproved/rejected plugin to an ordinary tenant).

### 26.3 Manifest Contract — `PluginManifest`, 4F §9.1.1 Exact

```json
{
  "base_url": "https://plugin.example.com/platform-callout",
  "capabilities": ["crm.contact.create", "workflow.action.notify_slack"],
  "required_permissions": ["contact:write"],
  "rate_limit_per_minute": 60,
  "timeout_ms": 5000,
  "webhook_callback_url": null,
  "min_platform_version": "1.0.0"
}
```

| Field | Constraint | Purpose |
|---|---|---|
| `base_url` | HTTPS only (4F invariant #1); egress-validated per §30 at **both** version-approval time and every callout time (5I ADR "FIX-13", two-point validation — reused exactly, not redesigned) | Where the platform sends every callout for this plugin version |
| `capabilities` | List of platform-recognized capability strings (§28) | What this version can be asked to do |
| `required_permissions` | Must be a subset of the platform's permission registry (4F invariant #2) — **not** the tenant's RBAC role permissions (§28.4 draws this distinction precisely) | What platform-side authority a caller must hold to invoke this plugin |
| `rate_limit_per_minute` | Integer | Manifest-declared ceiling (§25.3) |
| `timeout_ms` | ≤30000 | Hard callout timeout |
| `webhook_callback_url` | Nullable HTTPS, same SSRF discipline as `base_url` | For plugins that need to receive an async result rather than return one synchronously (§27.6) |
| `min_platform_version` | Semver string | Compatibility gate (§29) |

Immutable once `plugin_versions.approved_at IS NOT NULL` (5I `fn_pv_manifest_immutable` trigger, INV-PLUG-01) — a manifest change after approval requires a **new version**, never an in-place edit.

### 26.4 Platform vs. Organization vs. Installation — Three Distinct Layers

| Layer | Resource | Who controls it |
|---|---|---|
| Platform/provider manifest | `Plugin` + `PluginVersion.manifest` | Platform admin (review/approve), plugin developer (submits) — read-only to tenants |
| Organization installation | `PluginInstallation` | The tenant — decides *whether* to install, at which pinned version |
| Organization-specific credentials/configuration | `plugin_installations.configuration` / `credential_ref` | The tenant — per-installation, never shared across tenants even for the same plugin (§25.3) |

---

## 27. Plugin Installation Lifecycle & APIs

### 27.1 Lifecycle State Machine (4F §7.6, 5I-Confirmed)

```
[*] → INSTALLED          (InstallPlugin — plugins.fn_create_plugin_installation)
INSTALLED → ACTIVE       (ActivatePlugin — plugins.fn_activate_plugin)
ACTIVE → SUSPENDED        (SuspendPlugin — plugins.fn_suspend_plugin_installation, added by 101_5I1.sql, §56)
SUSPENDED → ACTIVE        (ReactivatePlugin — plugins.fn_reactivate_plugin_installation, added by 101_5I1.sql, §56)
ACTIVE → UNINSTALLED      (UninstallPlugin — plugins.fn_uninstall_plugin)
SUSPENDED → UNINSTALLED   (UninstallPlugin — plugins.fn_uninstall_plugin, callable from either ACTIVE or SUSPENDED per its own guard: "cannot uninstall UNINSTALLED")
UNINSTALLED → [*]         (terminal — fn_pi_terminal_guard DB-enforced)
```

Executed values exactly: `INSTALLED`, `ACTIVE`, `SUSPENDED`, `UNINSTALLED` (5I `chk_pi_status`).

### 27.2 `GET /api/v1/plugin-installations`

- **Permission:** `plugin:read`. **Tenant scope:** RLS. **Query:** `?status=`, `?plugin_id=`. Cursor pagination.

### 27.3 `POST /api/v1/plugin-installations`

- **Purpose:** install an approved plugin version for this organization.
- **Permission:** `plugin:install` (a distinct permission from `plugin:manage` — installing is a narrower grant than full lifecycle management, matching 5B's own three-way split `plugin:read/install/manage`).
- **Request:**
```json
{
  "plugin_id": "01930000-...",
  "plugin_version_id": "01930000-...",
  "configuration": { "default_channel": "#sales" },
  "credential": { "api_token": "..." }
}
```
- **Behavior:** `credential` (if present) is exchanged for a `credential_ref` via the secret manager exactly like §12.3, **before** calling `plugins.fn_create_plugin_installation()` — which DB-validates: the version belongs to the named plugin (5I FIX-04), both plugin and version are `APPROVED` (5I §28), and `credential_ref` (if non-null) satisfies the `secret_manager://` CHECK. This function **is** granted to `app_api` (5I §28 — unlike most of the plugin-lifecycle functions, installation-creation is directly callable from the request path, no internal-RPC hop needed).
- **Response `201`:** the installation, `status: "INSTALLED"` — **not yet active**; capabilities are not enabled until §27.5.
- **Errors:** `404 PLUGIN_NOT_FOUND`/`PLUGIN_VERSION_NOT_FOUND`; `409 PLUGIN_ALREADY_INSTALLED` (5I `uq_pi_org_plugin_active` partial unique index — one non-`UNINSTALLED` installation per `(organization_id, plugin_id)`, mirroring §8.2's integration-connection rule exactly); `422 PLUGIN_VERSION_INCOMPATIBLE` (min_platform_version not satisfied, §29.3) or `PLUGIN_NOT_APPROVED`/`PLUGIN_VERSION_NOT_APPROVED`.
- **Idempotency:** `Idempotency-Key` **required**.
- **Audit:** `PLUGIN_INSTALLED` (5J-confirmed vocabulary token).
- **Domain event:** `plugin.installed` (4F §12.5).

### 27.4 `GET` / `PATCH` `/api/v1/plugin-installations/{installation_id}`

- **`GET`:** `plugin:read`. Full detail, `ETag`.
- **`PATCH`:** `plugin:manage`. Fields: `configuration`, `rate_limit_override` (must be `<= manifest.rate_limit_per_minute`, application-layer-enforced against the current version's manifest — the DB CHECK only ensures `> 0`, not the ceiling relationship). **Never** `plugin_version_id` (blocked by `fn_pi_version_immutable`, only `fn_upgrade_plugin` — §29.4 — may change it) or `status` (via action endpoints only, §27.5–27.7). `credential` may be resubmitted here to rotate it via a **separate** call to `POST .../plugin-installations/{id}/rotate-credential` (below) — kept as its own action endpoint, distinct from ordinary config PATCH, so a credential-bearing request is never silently accepted inside a generic PATCH body (mirrors §11's integration-connection design, which also never lets a raw credential ride along inside a general-purpose PATCH).
- **Behavior:** calls `plugins.fn_update_plugin_installation_config(org_id, installation_id, configuration, rate_limit_override)` (§56, added by `101_5I1.sql` — closes former DEP-6J-02's config-PATCH half); rejects a `UNINSTALLED` installation with `409 PLUGIN_NOT_INSTALLED`.

### 27.4a `POST /api/v1/plugin-installations/{installation_id}/rotate-credential`

- **Permission:** `plugin:manage`. **Request:** `{ "credential": { "api_token": "..." } }` — exchanged for a `credential_ref` via the secret manager exactly like §12.3, before calling `plugins.fn_rotate_plugin_installation_credential(org_id, installation_id, new_credential_ref)` (§56, added by `101_5I1.sql`, mirrors `fn_rotate_integration_credential` exactly). Rejects a `UNINSTALLED` installation. **Idempotency:** `Idempotency-Key` optional but recommended. **Audit:** `PLUGIN_CREDENTIAL_ROTATED`.

### 27.5 `POST /api/v1/plugin-installations/{installation_id}/activate`

- **Permission:** `plugin:manage`.
- **Request:** `{ "enabled_capabilities": ["crm.contact.create"] }`.
- **Behavior:** `plugins.fn_activate_plugin()` — DB-validates `enabled_capabilities ⊆ manifest.capabilities` (5I FIX-06) and that both plugin/version remain `APPROVED` at activation time (re-checked, not just at install time — a plugin could theoretically be de-approved between install and activate). `EXECUTE` was widened to `app_api` directly by `101_5I1.sql`'s grant-widening (§56, §55 ADR-6J-01) — no internal-RPC hop; synchronous `200` response, direct call.
- **Response `200`:** `status: "ACTIVE"`, `enabled_capabilities` set.
- **Errors:** `422 PLUGIN_SCOPE_DENIED` (a requested capability not in the manifest); `409 STATE_CONFLICT` (already `ACTIVE` — re-activation with a **different** capability set is allowed and updates `enabled_capabilities` in place, per the function's own semantics of accepting `INSTALLED` or `SUSPENDED` as the pre-state — calling it while already `ACTIVE` is out-of-contract for the DB function itself and surfaces as `409`).
- **Audit:** `PLUGIN_ACTIVATED`.

### 27.6 `POST /api/v1/plugin-installations/{installation_id}/suspend` / `.../reactivate`

- **Permission:** `plugin:manage`.
- **`suspend`:** calls `plugins.fn_suspend_plugin_installation(org_id, installation_id)` (§56, added by `101_5I1.sql` — closes former DEP-6J-02's suspend half) — `ACTIVE → SUSPENDED`, idempotent on an already-`SUSPENDED` installation, blocked by the existing `fn_pi_terminal_guard` trigger if `UNINSTALLED` (`409 PLUGIN_NOT_INSTALLED`). De-registers the plugin's tool endpoints from the Tool Registry per 4F §12.5's `plugin.suspended` consumer note — no further invocations accepted once `SUSPENDED`.
- **`reactivate`:** calls `plugins.fn_reactivate_plugin_installation(org_id, installation_id)` (§56, added by `101_5I1.sql` — closes former DEP-6J-02's reactivate half) — `SUSPENDED → ACTIVE`. **Unlike upgrade (§29.4), reactivation does NOT reset `enabled_capabilities`** — no version change occurred, so the previously-enabled capability set is preserved as-is. Re-validates plugin/version remain `APPROVED` at reactivation time (defense-in-depth, mirrors `fn_activate_plugin`'s own re-check) — `422 PLUGIN_NOT_APPROVED`/`PLUGIN_VERSION_NOT_APPROVED` if either has been de-approved since suspension.
- **Response `200`:** the installation with its updated `status`.
- **Idempotency:** both are naturally idempotent (function-level no-op on the already-target status).
- **Audit:** `PLUGIN_SUSPENDED` / `PLUGIN_REACTIVATED`.

### 27.7 `DELETE /api/v1/plugin-installations/{installation_id}`

- **Purpose:** uninstall. Maps directly to `plugins.fn_uninstall_plugin()` (5I §28) — per 6A §7.6, this **is** the aggregate's own terminal-state transition, so `DELETE` (not just a `POST .../uninstall` action) is the correct verb here.
- **Permission:** `plugin:manage`.
- **Behavior:** idempotent — calling it on an already-`UNINSTALLED` installation returns `204` (function itself returns early, no-op, per 5I §28's own documented idempotent-return design). `EXECUTE` was widened to `app_api` directly by `101_5I1.sql`'s grant-widening (§56, §55 ADR-6J-01) — no internal-RPC hop; direct, synchronous `204`.
- **Response:** `204`.
- **Side effects on dependents:** any `WorkflowDefinition` referencing this installation's capabilities as a workflow action (§30) is **not** automatically modified — see §42 for the exact dependency-conflict policy this document adopts.
- **Audit:** `PLUGIN_UNINSTALLED`.
- **Domain event:** `plugin.uninstalled` (4F §12.5) — `Bus → ToolRegistry: de-register`, per 4F's own consumer table.

---

## 28. Plugin Permissions / Scopes

### 28.1 Two Distinct Permission Systems — Not to Be Confused

| System | Governs | Example values | Owner |
|---|---|---|---|
| Platform RBAC permissions (5B, 6B) | Which **tenant users/roles** may call **this document's own management APIs** (install, activate, configure a plugin) | `plugin:read`, `plugin:install`, `plugin:manage` | 6B, reused here unchanged |
| Plugin capabilities | Which **platform-side operations** an **installed plugin instance** is authorized to be invoked for | `crm.contact.create`, `workflow.action.notify_slack` | 4F §9.1.1 `PluginManifest.Capabilities` / `PluginInstallation.EnabledCapabilities`, this document's §27.5 |

A tenant user needs `plugin:install` to call `POST /plugin-installations` at all; separately, the resulting installation's `enabled_capabilities` govern what that installation is allowed to *do* once running. Neither system substitutes for the other.

### 28.2 `required_permissions` vs. RBAC — 4F Invariant #2, Applied

`PluginManifest.required_permissions` (§26.3) must be a subset of "the platform's defined permission registry" (4F invariant #2) — i.e., every string in a manifest's `required_permissions` list must be a real, existing RBAC permission string from 5B's catalog (validated at version-approval time, platform-admin-reviewed, not self-declared-and-trusted). This is **not** the same as automatically granting the plugin that authority — it declares what a tenant *installing* this plugin should expect it to need on their behalf when it's invoked in a context requiring that permission (e.g., a plugin declaring `contact:write` will only succeed when invoked from a code path that itself already holds/checks `contact:write` for the acting principal — the plugin cannot use its manifest declaration to bypass the actual RBAC check 6G's own CRM-write path performs).

### 28.3 Effective Plugin Authority

```
effective_plugin_authority =
    platform_capability_registry (which capability strings exist at all)
  ∩ manifest.capabilities (what this plugin version claims to support)
  ∩ installation.enabled_capabilities (what this tenant has turned on — DB-enforced subset of manifest.capabilities, fn_activate_plugin)
  ∩ caller/system authorization (RBAC permission check on whichever code path is invoking the plugin for this specific operation — e.g. workflow execution's own authorization, §30)
```

Every layer narrows, never widens — a plugin cannot use a broader `enabled_capabilities` grant to bypass a narrower RBAC check on the invoking path, and a broad RBAC grant on the invoking path cannot make a capability available that the tenant never enabled at installation.

### 28.4 Machine-Executed vs. Human-Triggered Operations

| Trigger | Example | Authorization check performed |
|---|---|---|
| Human-triggered | Tenant admin clicks "Install" / "Activate" / "Configure" in the platform UI | Ordinary RBAC (`plugin:install`/`plugin:manage`) on the acting user's session, per §27's endpoints |
| Machine-executed (workflow-invoked) | A published `WorkflowExecution` reaches a node referencing this plugin's capability (§30) | The Voice Orchestrator/Workflow runtime's own authorization (6I §22's `AuthorizeAndStartToolExecution`-equivalent boundary, extended to plugin actions per §30) — **not** a fresh interactive RBAC check against a human principal, since none is present mid-call; authorization instead rests on the fact that the *workflow itself* was published by a principal who held the necessary permissions at publish time, and the plugin's own `enabled_capabilities ⊆ manifest.capabilities` gate (§28.3) still applies unconditionally regardless of trigger type |

---

## 29. Plugin Versioning / Compatibility

### 29.1 Semantic Versioning

`plugin_versions.semver` — `CHECK (semver ~ '^\d+\.\d+\.\d+')` (5I §28). Manifest is immutable once `approved_at IS NOT NULL` (INV-PLUG-01) — any change, including a non-breaking one, requires submitting a **new** `PluginVersion` row for platform-admin review.

### 29.2 Status Lifecycle

`PENDING_REVIEW → APPROVED | REJECTED | DEPRECATED` (5I `chk_pv_status`). `DEPRECATED` marks a version unavailable for **new** installations/upgrades while existing installations pinned to it continue running unaffected (§43's "no silent removal" principle) — `fn_create_plugin_installation()` and `fn_upgrade_plugin()` both require `status = 'APPROVED'` exactly, so a `DEPRECATED` version is mechanically rejected for new installs/upgrades by the DB itself, not merely by an application-layer filter that could be bypassed.

### 29.3 `min_platform_version` Compatibility Gate

Checked at installation (§27.3) and upgrade (§29.4) time by the Application Service against the platform's own current API version — **not** DB-enforced (no column on `plugin_installations` or a platform-version table exists for the DB to check against); this is an explicit, disclosed application-layer-only gate, consistent with 6A §30's URL-path major versioning being the platform's only formal version signal.

### 29.4 `POST /api/v1/plugin-installations/{installation_id}/upgrade`

- **Permission:** `plugin:manage`.
- **Request:** `{ "plugin_version_id": "..." }`.
- **Behavior:** `plugins.fn_upgrade_plugin()` (5I §28) — DB-validates the new version belongs to the **same** plugin (FIX-04) and is `APPROVED`; **resets `enabled_capabilities` to `{}` and `status` to `INSTALLED`** (not `ACTIVE`) — **the tenant must explicitly re-activate** (§27.5) with a capability set valid against the *new* version's manifest. This is 5I's own deliberate design (ADR-5I-008): an upgrade never silently carries forward the old version's enabled capabilities into a new manifest that may have renamed, removed, or changed the semantics of a capability string.
- **A workflow referencing this installation's capability does not silently change behavior** on upgrade — see §30.5 for the full, corrected determinism guarantee (a prior revision of this section's cross-reference here overstated what "fails closed" alone provides; §30.5 now also pins an explicit `plugin_version_id` inside the workflow node config itself, not just the installation ID).
- `EXECUTE` was widened to `app_api` directly by `101_5I1.sql`'s grant-widening (§56, §55 ADR-6J-01) — no internal-RPC hop; direct, synchronous `200`.
- **Response `200`:** `status: "INSTALLED"`, `enabled_capabilities: []`, new `plugin_version_id`.
- **Audit:** `PLUGIN_UPGRADED`.

### 29.5 Deprecated Versions and Breaking Changes

A plugin developer submitting a manifest with a **removed or renamed** capability string must do so as a new major-version-shaped semver bump (developer discipline, not DB-enforced — the platform does not parse semver semantics beyond format validation); the platform's own review gate (`PENDING_REVIEW → APPROVED`) is the point at which a human reviewer is expected to confirm the version bump matches the actual compatibility impact, per standard semver practice. This document does not automate that judgment.

---

## 30. Plugin + Workflow Integration — The 6I Dependency, Closed

### 30.1 What 6I Needs, Restated Precisely

6I §23/§54 item 5: `WEBHOOK`/`API_CALL` workflow node types are **accepted in `draft_graph`** but **publish is rejected** (`422 WORKFLOW_REFERENCE_NOT_READY`, `details.reason=INTEGRATION_BINDING_UNRESOLVED`) until 6J supplies exactly two things: (1) a **credential-reference type** callable from workflow node config, and (2) an **egress-control adapter** implementing the SSRF/timeout/redirect/response-size controls 6I §23.2 lists. This section supplies both, without touching `workflow.*` tables, `WorkflowRuntimeService`, or `node_execution_claims` (6I's own already-resolved idempotency mechanism, §63.2 there) — 6J's contribution is a **capability 6I's runtime calls into**, never the other way around.

### 30.2 Credential-Reference Type

A workflow's `WEBHOOK`/`API_CALL` node config (per 6I §11's `WebhookNodeConfig`) references credentials **exclusively** by one of:
- `{ "credential_source": "plugin_installation", "plugin_installation_id": "...", "plugin_version_id": "...", "capability": "..." }` — resolves at execution time to that `PluginInstallation.credential_ref`, gated by `capability ∈ installation.enabled_capabilities` (§28.3) — **never** a raw secret in `graph_json` (closing 6I §46's requirement directly). **`plugin_version_id` is a mandatory field, not optional** — see §30.5 for why (version-pinning determinism).
- `{ "credential_source": "integration_connection", "connection_id": "...", "capability": "..." }` — resolves to that `IntegrationConnection.credential_ref`, gated by `capability ∈ connection.enabled_capabilities` (verified against 5I's executed DDL: `integration_connections.enabled_capabilities TEXT[]` genuinely exists as a column, migration `061_5I.sql` — not an invented field)
- `{ "credential_source": "none" }` — for an unauthenticated public endpoint call; still fully subject to §30.3's egress controls

**CROSS-PHASE COORDINATION BLOCKER — DISCLOSED, NOT RESOLVED (found on independent review, confirmed by direct inspection this pass).** 6I §11's own frozen node-config table defines `WebhookNodeConfig` (`url_template`, `method`, `payload_template`, `timeout_ms`, `result_slot`) and `ApiCallNodeConfig` (`method`, `url_template`, `headers`) — **neither currently includes a `plugin_installation_id`, `plugin_version_id`, or `credential_source` field of any kind.** The three-shape credential-reference contract above is **6J's own proposed design for what 6I's node config should carry** once 6I incorporates it — it is not, and cannot be, a retroactive amendment to 6I's own frozen `graph_json` schema (6I is `APPROVED/FROZEN`; amending its schema is outside this document's authority, per §0's own instruction not to redesign previously-approved architecture). Per this remediation's own explicit instruction (governing task §13): this is disclosed here as an **unresolved, named cross-phase coordination item** rather than silently claimed closed. It does not block any other endpoint in this document's own inventory (§48) — every integration/webhook/plugin-installation endpoint is independently complete. Closing it requires a future, small, controlled 6I schema amendment (adding the three fields above to `WebhookNodeConfig`/`ApiCallNodeConfig`) coordinated with whoever owns 6I's next revision — 6J supplies the exact contract that amendment should implement (this section), it does not implement it.

6I's own `graph_json` never stores a `credential_ref` value or any resolved secret — only one of the three reference shapes above. Resolution happens exclusively inside the Application Service that executes the node, at execution time, immediately before the outbound call, and the resolved secret is never written back into any execution-history/checkpoint row (6I §32's `WorkflowExecutionDetailDTO` redaction rules, §63.2's `node_execution_claims`) — this document adds no persistence of resolved secrets anywhere.

### 30.3 Egress-Control Adapter — SSRF Contract (Applies to Every Tenant-Configurable URL in This Document)

This is the **single, shared** control this document defines once and applies to every outbound call it or 6I's `WEBHOOK`/`API_CALL` node type ever makes to a tenant-supplied or plugin-declared URL: webhook delivery targets (§17), plugin `base_url`/`webhook_callback_url` callouts (§26.3), integration connection `test`/`sync` provider calls (§11.8/§15), and 6I's `WEBHOOK`/`API_CALL` node execution.

| Control | Rule |
|---|---|
| Scheme allow-list | `https://` only. No `http://`, `ftp://`, `file://`, `gopher://`, or any other scheme — a non-`https` URL is rejected at **registration/configuration time**, not merely at call time (defense-in-depth: two-point validation, exactly 5I ADR "FIX-07"/"FIX-13"'s existing pattern for webhook/plugin URLs, extended here to workflow node config validation at 6I's own publish gate) |
| Private/internal address blocking | Reject loopback (`127.0.0.0/8`, `::1`), link-local (`169.254.0.0/16`, `fe80::/10`), RFC1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), IPv4-mapped-IPv6 (`::ffff:0:0/96`, evaluated against the same IPv4 rules as its unwrapped form — a naive check that only inspects the literal IPv6 form is bypassable), and IPv6 unique-local (`fc00::/7`) **unless** the target organization has an explicit enterprise egress allow-list entry (a future product surface — not designed here; V1 has no such allow-list, so these ranges are unconditionally rejected in V1). Unspecified (`0.0.0.0`, `::`) and multicast (`224.0.0.0/4`, `ff00::/8`) addresses are always rejected, no allow-list override. |
| Cloud metadata endpoint blocking | `169.254.169.254` (AWS/GCP/Azure IMDS) and equivalents (`fd00:ec2::254`, `metadata.google.internal`) always rejected — no enterprise-override path exists for this one, ever, since it is never a legitimate tenant webhook/plugin/action target |
| DNS resolution validation | **Resolve-then-pin, per request, not per registration:** DNS is resolved fresh at the start of **every** outbound call (not cached indefinitely from registration time); the resolved IP is checked against the block-list above; the connection is then made to that **pinned IP** for that one request — closing the DNS-rebinding window where a hostname resolves safely at validation time and unsafely at connection time. **The original hostname is preserved for TLS SNI and the `Host` header** — the adapter connects to the validated IP at the TCP layer but still presents the original hostname for the TLS handshake and HTTP request line, and the returned certificate is validated against that original hostname (never against the IP, and never skipped) — connecting to a validated IP is a network-layer control, not a substitute for normal TLS hostname verification. |
| Redirect policy | Bounded to **3** hops; **every** redirect's `Location` target is independently re-validated against the full scheme/address/metadata/DNS-resolution rules above before being followed (never a single validation-then-blind-follow) — a `3xx` response received during a webhook **delivery** attempt specifically is never followed at all (§22.4 — a stricter rule than this general adapter default, because a webhook delivery target changing its own redirect behavior post-registration is a stronger signal of compromise/misconfiguration than a one-off plugin/workflow call). **Credential/authorization headers are never forwarded across a cross-origin redirect** — if a redirect's target host differs from the original request's host, the adapter strips `Authorization`, any `X-Platform-*` signing headers, and any resolved integration/plugin credential material from the redirected request entirely (same-origin redirects, where host+scheme+port are unchanged, may carry the same headers forward, since no trust boundary is crossed). The plugin platform→plugin HMAC signature (§25.3) is likewise never re-issued for a redirected target — a plugin `base_url` redirecting elsewhere causes the call to fail rather than silently signing for an unreviewed destination. |
| Port restriction | Standard HTTPS port `443` only, unless the definition/manifest explicitly declares a non-standard port as part of its documented `base_url` (validated once at registration, not client-overridable per-call) |
| Timeout | Bounded per-resource: webhook `timeout_ms` (1000–30000, §17.1), plugin `manifest.timeout_ms` (≤30000, §26.3), workflow node `duration_ms`-adjacent timeout (1000–10000ms, per 6I §23.2's own already-specified `WebhookNodeConfig` bound) |
| Response size cap | 2MB for any egress-adapter call (webhook target responses are additionally truncated to 512 bytes for storage, §17.1 — this 2MB figure bounds what the adapter itself will buffer before aborting, protecting worker memory regardless of what's eventually persisted) |
| No DB transaction held during the call | Universal rule (6A §35) — every egress-adapter invocation happens strictly outside any open DB transaction, for every one of this section's call sites |

The full adversarial security test matrix exercising every row above (localhost, RFC1918, IPv6 loopback, IPv6 unique-local, cloud metadata, DNS rebinding, redirect-to-private-IP, redirect credential leakage, TLS hostname mismatch) is enumerated in §60. **Disclosed:** these are application-layer controls with no deployed application code anywhere in this repository to execute them against — §60 discloses this explicitly rather than fabricating results; only the DB-layer portion (`webhook_endpoints.target_url` HTTPS-only `CHECK`) is live-testable and was confirmed structurally intact.

### 30.4 Workflow Node → Egress Adapter Invocation (In-Process Contract, Not a REST Call)

6I's `WorkflowRuntimeService` (running in-process inside the Voice/Workflow runtime, 6I §7.1) calls the egress-control adapter as a **library/port interface**, not an HTTP call to a 6J-owned endpoint — there is no `/api/v1/integrations/execute-webhook-node` REST resource, because 6I §7 already establishes the entire runtime contract is in-process, and 6J does not introduce a second call path for something 6I's own architecture has already fixed as internal. The adapter is packaged as a shared library/module both 6I's runtime and 6J's own Application Services (§11.8, §15, §26) import and call — this closes 6I §23.2's dependency without 6J acquiring any execution authority over `workflow.*` tables or `WorkflowExecution` state, which remain 6I's alone (§7.2).

### 30.5 Action Identifiers, Versioning, Input/Output Schema

For a workflow node invoking a **plugin** capability specifically (as opposed to a bare `WEBHOOK`/`API_CALL` node hitting an arbitrary URL):

**Corrected version-pinning model (previously a P0 defect — see §55 ADR-6J-09 for the full before/after).** The prior revision of this row stored only `plugin_installation_id` in workflow node config and executed "whatever version the installation currently points to," reasoning that upgrade forcing `ACTIVE → INSTALLED` (§29.4) would fail-close in the gap between an upgrade and the tenant's next re-activation. **That reasoning was incomplete**: once the tenant re-activates the installation (with a capability set now valid against the *new* version), any workflow that had only ever referenced `plugin_installation_id` would silently resume executing — now against the new version's behavior — the very next time it ran, with nothing in the workflow's own definition having changed. That is exactly the non-deterministic "a workflow silently begins executing materially different plugin behavior merely because an installation was upgraded and reactivated" failure the governing review named.

| Concern | Contract |
|---|---|
| Action identifier | `{plugin_key}.{capability}` (e.g. `slack_notify.workflow.action.notify_slack`) — stable across plugin versions as long as the capability string itself is unchanged in the manifest |
| Version pinning | The workflow node config stores **both** `plugin_installation_id` **and** `plugin_version_id` (§30.2 — `plugin_version_id` is now a mandatory field, not inferred). **At publish time** (6I's own gate, 6I §14), 6I validates: the installation belongs to the publishing organization, is `ACTIVE`, its **current** `plugin_version_id` equals the node config's pinned `plugin_version_id` (i.e., the workflow is being published against the version actually installed right now), and `capability ∈ installation.enabled_capabilities ∩ (that version's) manifest.capabilities`. **At every execution** (not just publish), the same four checks are re-run: org ownership, `ACTIVE` status, **`installation.plugin_version_id = <the node's pinned plugin_version_id>` exactly** — if the installation has since been upgraded (its live `plugin_version_id` no longer matches what this workflow was published against), the node fails closed with `422 PLUGIN_VERSION_PINNED_MISMATCH` (§35), never silently executing against the new version — and `capability` still enabled. A `DEPRECATED` `PluginVersion` (§29.2) does **not** by itself block a pinned execution — deprecation blocks new installs/upgrades only; the deprecated version's manifest/row still exists (5I's `ON DELETE RESTRICT` FKs guarantee it is never removed while any installation references it) and remains fully resolvable for an already-pinned workflow. **Recovery path:** a tenant whose workflow now fails with `PLUGIN_VERSION_PINNED_MISMATCH` after upgrading the underlying installation must explicitly republish the workflow (6I's own publish flow, re-run against the now-current `plugin_version_id`) — an explicit, visible, auditable action, never an implicit consequence of the installation's own lifecycle. |
| Input schema | The manifest does not declare a separate per-capability input schema in the executed 5I/4F model — validation of the node's `argument_template`-rendered payload against the plugin's expectations is the plugin's own HTTP-level responsibility (it returns a `4xx` if the payload is malformed, handled per §30.6's error mapping), mirroring how 6I §22 already treats `TOOL_CALL`'s `input_schema` as owned by the tool/plugin registry, not by 6I or 6J's own schema store |
| Output schema | Plugin response body is captured, size-capped (§30.3), and written into the workflow's named slot exactly as 6I §22 already specifies for `TOOL_CALL` results (inheriting the same 64KB application-layer cap, `tool_executions.result` pattern) — 6J introduces no new slot-writing mechanism |
| Timeout / retryability | Bounded per §30.3; **not** auto-retried by 6J's egress adapter for non-idempotent (non-`GET`) calls, per 6A §21's platform-wide "non-idempotent POST is never auto-retried by any layer" rule — a failed plugin/webhook-node call surfaces its failure to 6I's own `on_failure_edge` handling (6I §22), which decides whether/how the workflow retries, not 6J |
| Idempotency | 6I's `node_execution_claims` (§63.2 there, already resolved) is the idempotency boundary for a crash-mid-execution retry of the **node evaluation itself** — 6J's egress adapter performs no independent idempotency tracking of its own; it is a stateless call executor invoked once per claimed attempt |
| Error mapping | Plugin/target HTTP errors are normalized into 6J's own error classes (§35, `INTEGRATION_PROVIDER_UNAVAILABLE`/`INTEGRATION_RATE_LIMITED`/etc.) before being handed back to 6I's node result — 6I never sees a raw provider status code/body, only the normalized class plus a safe, truncated detail string |
| Secret access | §30.2 — reference-only, resolved at call time, never persisted |
| Observability | Every egress-adapter call emits the same span/metric shape as any other outbound provider call (§44) — tagged with `caller: "workflow_node"` vs. `caller: "integration_sync"` etc., so a latency regression is attributable to its actual caller even though the adapter code path is shared |
| Authorization | §28.4 — the workflow's own publish-time authorization is the operative check; the plugin's `enabled_capabilities` gate (§28.3) is re-checked at every single invocation regardless |

### 30.6 Generic `WEBHOOK`/`API_CALL` Node (Non-Plugin) — Error Mapping

A bare `WEBHOOK`/`API_CALL` node (no plugin involved, an arbitrary tenant-configured URL per 6I §11) is subject to the identical §30.3 SSRF contract but has no manifest/capability model to consult — its "malformed payload" case (referenced in §30.5's input-schema row) surfaces directly as the target's own HTTP response status, mapped through §35's normalized classes (`INTEGRATION_OPERATION_FAILED` for a `4xx` the target returns, `INTEGRATION_PROVIDER_UNAVAILABLE` for network/timeout failures) exactly like any other egress-adapter caller.

---

## 31. Tenant Isolation

Every organization-scoped resource this document defines follows 6A §23's canonical chain unmodified:

```
authenticated principal → organization_id (JWT claim / API-key lookup, never client-supplied)
    → TenantContext.set() / SET LOCAL app.tenant_id
    → RLS-scoped repository read/write
    → resource ownership re-verified at the application layer (defense-in-depth over RLS)
```

| Resource | RLS | Cross-org ID guess result |
|---|---|---|
| `integration_connections` | `ENABLE + FORCE`, `rls_ic_tenant` | `404`, never `403` (6A §7.4) |
| `oauth_attempts` | `ENABLE + FORCE`, `rls_oa_tenant` | Redemption `NOT FOUND` → `400 OAUTH_STATE_INVALID` (§13.3) — deliberately not `404`, since an OAuth callback is not a normal authenticated resource lookup and disclosing "invalid" vs. "not found" carries no additional risk here (the caller is a browser mid-redirect, not a probing API client) |
| `integration_health` | `ENABLE + FORCE`, `rls_ih_tenant` | `404` |
| `webhook_endpoints` | `ENABLE + FORCE`, `rls_we_tenant` | `404` |
| `webhook_deliveries` | `ENABLE + FORCE`, `rls_wd_tenant` | `404` |
| `inbound_webhook_events` | `ENABLE + FORCE`, `rls_iwe_tenant` | `404` |
| `plugin_installations` | `ENABLE + FORCE`, `rls_pi_tenant` | `404` |
| `plugin_executions` | `ENABLE + FORCE`, `rls_pe_tenant` | `404` |
| `integration_definitions` / `plugins` / `plugin_versions` | No RLS — platform-global, `organization_id IS NULL` by design (5I §4) | N/A — every tenant reads the same rows |

**Resource IDs are identifiers, not authorization** — every `GET`/`PATCH`/`POST .../{id}/...` handler in this document relies on RLS to make a cross-tenant ID guess return zero rows, never on the ID's UUIDv7 structure being "hard to guess" as a security property (6A §7.5 — UUIDv7 is opaque but not a secret).

### 31.1 The `SECURITY DEFINER` Tenant-Forgery Guard — A Second, Independent Layer Beneath RLS

**Why a second layer is required at all (found on independent review, second remediation pass):** every mutating function in this document is `SECURITY DEFINER`, owned by a `BYPASSRLS` role (`app_migration` — confirmed live, §60). RLS is therefore **not** the operative control inside these functions' own queries — it only governs the *ordinary*, non-`SECURITY DEFINER` reads/writes the table above describes. A `SECURITY DEFINER` function that takes `p_organization_id` as a plain parameter and trusts it unconditionally would let a caller authenticated as Org A pass Org B's UUID and mutate Org B's data, entirely bypassing RLS.

**The guard (§55 ADR-6J-11):** every `app_api`-callable, `p_organization_id`-taking function in this document — every new integration/plugin/webhook lifecycle function, and (via `CREATE OR REPLACE`, same signature, no behavior change for any legitimate caller) every pre-existing 059-066 function sharing the same shape — requires, as its first check:

```sql
IF organization.current_tenant_id() IS NULL OR organization.current_tenant_id() <> p_organization_id THEN
  RAISE EXCEPTION '<schema>: caller tenant context does not match the requested organization';
END IF;
```

`organization.current_tenant_id()` reads `current_setting('app.tenant_id', true)::UUID` — the identical session GUC 6A §23.2/5B §16.1 already require the API layer to `SET LOCAL app.tenant_id = <JWT organization_id claim>` before any tenant-scoped work. This guard adds no new mechanism — it applies a check that was already structurally possible (the GUC was always being set) but not previously enforced inside these specific `SECURITY DEFINER` bodies. **Fail-closed**: an unset tenant context is rejected identically to a mismatched one.

**Three function classes, not one blanket rule (§56):**

| Class | Guard applied? | Examples |
|---|---|---|
| Tenant-bound runtime functions | **Yes** | Every function in §11, §21.3, §23.3, §27, §29.4 |
| Callback bootstrap functions | **No** — no tenant context exists yet, by definition (§13.4) | `fn_redeem_oauth_callback_state`, `fn_fail_oauth_callback_state`, `fn_record_oauth_exchange_failure` |
| Worker/system functions | **No** — operate across every tenant's queued work by design; a per-tenant guard would break the pipeline | `fn_claim_delivery`, `fn_delivery_succeeded`, `fn_delivery_failed`, `fn_update_inbound_event_status` (unchanged, `app_worker`-only); `fn_integrations_anonymize_org` (unchanged, `app_platform_admin`/break-glass-only) |

**Live-proven, not merely designed** (§60): an 11-test adversarial matrix — forged `p_organization_id` across integration-connection, plugin-installation, and webhook-secret-rotation function families; no-tenant-context calls; and a "correct org context, wrong resource" case exercising the *independent* resource-ownership `WHERE` clause layered beneath the guard — all resolved correctly, with zero forged rows created and zero forged mutations applied in every case.

---

## 32. Authorization

### 32.1 Permission Catalog — 5B-Seeded, Reused Verbatim, No New Strings

| Permission | Grants | Seeded to (5B) |
|---|---|---|
| `integration:read` | Read `integration_definitions`, `integration_connections`, `integration_health`, `oauth_attempts`-derived status, `inbound_webhook_events` observability | OWNER, ADMIN, MEMBER, VIEWER |
| `integration:manage` | Create/update/disconnect/reauthorize/test/sync connections | OWNER, ADMIN |
| `webhook:read` | Read `webhook_endpoints`, `webhook_deliveries` | OWNER, ADMIN, MEMBER, VIEWER |
| `webhook:manage` | Create/update/enable/disable/rotate-secret/test/replay | OWNER, ADMIN |
| `plugin:read` | Read `plugins`, `plugin_versions`, `plugin_installations` | OWNER, ADMIN, MEMBER, VIEWER |
| `plugin:install` | `POST /plugin-installations` only | OWNER, ADMIN |
| `plugin:manage` | Configure/activate/suspend/upgrade/uninstall an installation | OWNER, ADMIN |

**Zero new permission strings are introduced by this document.** `BILLING_ADMIN` holds none of the seven permissions above (confirmed against 5B's seed data — no `BILLING_ADMIN` row exists for any `integration:*`/`webhook:*`/`plugin:*` permission) and therefore cannot call any endpoint in this document; this is 5B's own existing seed, not a decision made here.

### 32.2 Full endpoint-level matrix: §48.

---

## 33. Idempotency

Per 6A §16, `Idempotency-Key` is **required** for POST endpoints with a dangerous real-world duplicate-side-effect (resource creation with a credential/OAuth/notification consequence), **optional-but-honored** where the underlying operation already has its own idempotent-return semantics, and **not applicable** to safe/GET-shaped or naturally-idempotent DELETE-equivalent actions.

| Endpoint | Idempotency-Key |
|---|---|
| `POST .../connections` | **Required** |
| `POST .../connections/{id}/disconnect` | Optional (naturally idempotent once DEP-6J-01 closes — mirrors `fn_uninstall_plugin`'s pattern) |
| `POST .../connections/{id}/reauthorize` | Optional-recommended |
| `POST .../connections/{id}/test` | N/A (side-effect-free at the business-resource layer) |
| `POST .../connections/{id}/sync` | Optional (Redis lock is the actual concurrency guard, §15.3) |
| `POST .../webhook-endpoints` | **Required** |
| `POST .../webhook-endpoints/{id}/rotate-secret` | Optional-recommended (protects against double-rotation on retry) |
| `POST .../webhook-endpoints/{id}/test` | N/A (intentionally creates a new test delivery each call) |
| `POST .../webhook-deliveries/{id}/replay` | Optional (DB function itself is idempotent, §23.3) |
| `POST .../plugin-installations` | **Required** |
| `POST .../plugin-installations/{id}/activate` | Optional-recommended |
| `POST .../plugin-installations/{id}/upgrade` | Optional-recommended |
| `DELETE .../plugin-installations/{id}` | N/A (naturally idempotent, §27.7) |

Storage/scope/TTL mechanics: unmodified from 6A §16.2 (Redis primary, `(organization_id, principal_id, endpoint, Idempotency-Key)` scope, 24h TTL). **Fingerprint mechanism is hardened beyond 6A's baseline for this document's own credential-bearing endpoints** — §12.1 rule 5's `HMAC-SHA256(platform_idempotency_fingerprint_key, ...)` construction, not a bare `SHA-256`, since several of this document's `Idempotency-Key`-bearing requests (§11.2, §27.3) carry raw credentials in their body that a bare hash would expose to offline brute-force for low-entropy secrets.

---

## 34. Concurrency

| Resource | Mechanism |
|---|---|
| `IntegrationConnection` creation | `fn_create_integration_connection()`'s own `SELECT ... FOR UPDATE` (§8.2) — no API-layer lock |
| `IntegrationConnection` free-form fields (`display_name`, `configuration`) | Weak `ETag` (`hash(id, updated_at)`), `If-Match` required on PATCH (6A §17.2 — no dedicated `version` column exists platform-wide, ADR-6A-08) |
| `OAuthAttempt` redemption | `fn_redeem_oauth_attempt()`'s `SELECT ... FOR UPDATE` + status/expiry check (§13.3) |
| `WebhookEndpoint` fields | Weak `ETag`, `If-Match` required |
| `WebhookDelivery` claim (worker-internal, not client-facing) | `fn_claim_delivery()`'s `SELECT ... FOR UPDATE SKIP LOCKED` (5I §28) |
| `WebhookDelivery` replay | `fn_replay_webhook_delivery()`'s own row lock + idempotent-return (§23.3) |
| `PluginInstallation` creation | `uq_pi_org_plugin_active` partial unique index (DB constraint, not an app-layer lock) |
| `PluginInstallation` activate/upgrade/uninstall | Each guarded function's own `SELECT ... FOR UPDATE` (5I §28) |
| Integration sync | Redis `SETNX` (`integrationsync:{connection_id}`, §15.3) — the one case in this document where a Redis lock, not a DB row lock, is the concurrency guard, because the "resource" being protected (an in-flight Celery task, not a DB row) has no natural row to lock |

No endpoint in this document takes an API-layer lock beyond what a guarded DB function or an already-established Redis primitive (`SETNX`) already provides — consistent with 6A §17.3's prohibition on a second, competing locking scheme.

---

## 35. Error Normalization

### 35.1 Principle

External providers (integration APIs, plugin HTTP services, generic webhook/API-call targets) return wildly inconsistent error shapes. This document normalizes every provider-originated failure into the platform's 6A §24 error contract **before** it ever reaches a client — no endpoint in this document passes through an arbitrary provider response body as `error.details`.

### 35.2 Normalized Failure Classes (Applied at Every Egress-Adapter Call Site — §11.8, §15, §26, §30)

| `failure_class` | Meaning | Maps to (when surfaced as a REST error) |
|---|---|---|
| `AUTH_FAILED` | Provider rejected the current credential (expired token, revoked key, wrong scope) | `INTEGRATION_AUTH_REQUIRED` |
| `PROVIDER_RATE_LIMITED` | Provider returned `429` or an account-quota rejection | `INTEGRATION_RATE_LIMITED` |
| `PROVIDER_UNAVAILABLE` | Network/DNS/TLS failure, timeout, or `5xx` | `INTEGRATION_PROVIDER_UNAVAILABLE` |
| `CONFIGURATION_INVALID` | Provider rejected the request shape/config (a `4xx` not attributable to auth or rate limiting) | `INTEGRATION_CONFIGURATION_INVALID` |
| `SCOPE_INSUFFICIENT` | Provider indicates the granted OAuth scope doesn't cover the attempted operation | `INTEGRATION_SCOPE_INSUFFICIENT` |
| `UNKNOWN` | Anything not classifiable into the above (fail-safe bucket, never silently dropped) | `INTEGRATION_OPERATION_FAILED` |

### 35.3 Full Error Catalog

| Error Code | HTTP | Meaning | Retryable | Applies To |
|---|---|---|---|---|
| `INTEGRATION_DEFINITION_NOT_FOUND` | 404 | Unknown/inactive provider slug | No | §9 |
| `INTEGRATION_NOT_FOUND` | 404 | Connection doesn't exist or belongs to another org | No | §11 |
| `INTEGRATION_ALREADY_CONNECTED` | 409 | A non-terminal connection already exists for this `(org, definition)` | No | §11.2 (§8.2) |
| `INTEGRATION_DISABLED` | 409 | Connection is `DISCONNECTED`/`FAILED` (terminal) — attempted action requires a non-terminal connection | No | §11.6–§11.8, §15.3 |
| `INTEGRATION_AUTH_REQUIRED` | 409 | Provider rejected current credential; connection needs reauthorization | No | §11.7, §11.8, §15.3 |
| `INTEGRATION_CONFIGURATION_INVALID` | 422 | Provider rejected the connection's configuration | No | §11.2, §11.4, §15.3 |
| `INTEGRATION_PROVIDER_UNAVAILABLE` | 502 | Network/timeout/5xx from the provider | Yes | §11.8, §15.3, §30 |
| `INTEGRATION_RATE_LIMITED` | 429 | Provider `429`/quota rejection | Yes | §11.8, §15.3, §16 |
| `INTEGRATION_SCOPE_INSUFFICIENT` | 403 | Granted OAuth scope insufficient for the attempted operation | No | §11.8, §15.3 |
| `INTEGRATION_SYNC_IN_PROGRESS` | 409 | A sync is already in flight for this connection | No | §15.3 |
| `INTEGRATION_SYNC_NOT_SUPPORTED` | 422 | Definition has no sync-eligible capability | No | §15.3 |
| `INTEGRATION_OPERATION_FAILED` | 502 | Fallback normalized-failure bucket | Sometimes (per `retryable` field) | §11.8, §15.3, §30 |
| `OAUTH_STATE_INVALID` | 400 | `state`/`organization_id` mismatch, or unknown state | No | §13.3, §13.4 |
| `OAUTH_STATE_ALREADY_USED` | 409 | Replay of an already-redeemed `state` | No | §13.3 |
| `OAUTH_STATE_EXPIRED` | 410 | `state` past its 10-minute TTL | No | §13.3 |
| `WEBHOOK_NOT_FOUND` | 404 | Endpoint doesn't exist / cross-tenant | No | §18 |
| `WEBHOOK_URL_UNSAFE` | 422 | `target_url` fails SSRF validation (§30.3) | No | §18.3, §18.5 |
| `WEBHOOK_TOPIC_INVALID` | 422 | One or more `topics` not in the governed catalog (§19) | No | §18.3, §18.5 |
| `WEBHOOK_DELIVERY_NOT_FOUND` | 404 | Delivery doesn't exist / already purged | No | §23.2, §23.3 |
| `WEBHOOK_REPLAY_NOT_ALLOWED` | 422 | Delivery not in `DEAD_LETTER`/`DELIVERED` (5I `fn_replay_webhook_delivery`'s own guard) | No | §23.3 |
| `WEBHOOK_REPLAY_RATE_LIMITED` | 429 | >10 replays/24h on this delivery | Yes (after window) | §23.3 |
| `PLUGIN_NOT_FOUND` | 404 | Unknown plugin slug, or not `APPROVED` for a non-admin caller | No | §26 |
| `PLUGIN_VERSION_NOT_FOUND` | 404 | Unknown version ID | No | §26, §27.3 |
| `PLUGIN_NOT_APPROVED` / `PLUGIN_VERSION_NOT_APPROVED` | 422 | Install/upgrade target not in `APPROVED` status | No | §27.3, §29.4 |
| `PLUGIN_ALREADY_INSTALLED` | 409 | Non-`UNINSTALLED` installation already exists for this `(org, plugin)` | No | §27.3 |
| `PLUGIN_NOT_INSTALLED` | 404 | Installation doesn't exist / cross-tenant | No | §27 |
| `PLUGIN_DISABLED` | 409 | Installation not `ACTIVE` (e.g. mid-upgrade, `INSTALLED`-only) — invocation attempted | No | §27.5, §30.5 |
| `PLUGIN_SCOPE_DENIED` | 422 | Requested `enabled_capabilities` not a subset of `manifest.capabilities` | No | §27.5 (5I FIX-06) |
| `PLUGIN_VERSION_INCOMPATIBLE` | 422 | `min_platform_version` not satisfied | No | §27.3, §29.4 |
| `PLUGIN_VERSION_PINNED_MISMATCH` | 422 | A workflow node's pinned `plugin_version_id` no longer matches the referenced installation's current version (upgraded since publish) | No | §30.5 (ADR-6J-09) |
| `WEBHOOK_ROTATION_INVALID` | 422 | `grace_period_seconds` outside the `0`–`86400` DB-CHECKed range | No | §21.3 |

`retryable` (6A §24.1) is `true` only for `INTEGRATION_PROVIDER_UNAVAILABLE`, `INTEGRATION_RATE_LIMITED`, `INTEGRATION_OPERATION_FAILED` (when the underlying `failure_class` is retryable), and `WEBHOOK_REPLAY_RATE_LIMITED` — every other code above is `false`. None of the codes in this catalog collide with 6A §24.2's platform-wide family (`VALIDATION_ERROR`, `AUTHENTICATION_REQUIRED`, `AUTHORIZATION_DENIED`, `RESOURCE_NOT_FOUND`, `STATE_CONFLICT`, `RATE_LIMIT_EXCEEDED`, etc.) — those remain available and are used for the generic cases (malformed request body, missing auth) that don't warrant a domain-specific code.

---

## 36. Audit

### 36.1 Vocabulary — Reused Where It Exists, Extended in the Same Style Where It Doesn't

`audit.audit_events.action_kind` is `CHECK (length(action_kind) BETWEEN 1 AND 200)` — **open TEXT, not a closed enum** (5J §14.3, migration `072_5J.sql`, reconfirmed unchanged through the 5L amendment pass). 5J §14.3 already confirms these exact tokens for this domain: `INTEGRATION_CONNECTED`, `INTEGRATION_DISCONNECTED`, `INTEGRATION_CREDENTIAL_ROTATED`, `WEBHOOK_ENDPOINT_CREATED`, `WEBHOOK_ENDPOINT_DELETED`, `PLUGIN_REGISTERED`, `PLUGIN_VERSION_APPROVED`, `PLUGIN_VERSION_REJECTED`, `PLUGIN_INSTALLED`, `PLUGIN_ACTIVATED`, `PLUGIN_UNINSTALLED`, `PLUGIN_UPGRADED`. Every additional token this document uses below follows the identical `{RESOURCE}_{VERB}` shape already established platform-wide (5J's own "mirrors `USER_PROFILE_UPDATED`" convention) and requires **no DB migration** — the CHECK constraint imposes only a length bound.

### 36.2 Full Audit Event List

| `action_kind` | Endpoint | Sync/Async (6A §22, 5J §14.5 classification) |
|---|---|---|
| `INTEGRATION_CONNECTION_CREATED` | §11.2 | Sync (credential-adjacent) |
| `INTEGRATION_CONFIG_UPDATED` | §11.4 | Async |
| `INTEGRATION_DISCONNECTED` | §11.6 | Sync |
| `INTEGRATION_REAUTHORIZED` | §11.7 | Sync (credential-adjacent) |
| `INTEGRATION_TEST_PERFORMED` | §11.8 | Async |
| `INTEGRATION_CONNECTED` | Emitted when status reaches `ACTIVE` (§37) | Sync |
| `INTEGRATION_CREDENTIAL_ROTATED` | §11.7, §12.4 | Sync |
| `WEBHOOK_ENDPOINT_CREATED` | §18.3 | Async |
| `WEBHOOK_ENDPOINT_UPDATED` | §18.5 | Async |
| `WEBHOOK_ENDPOINT_ENABLED` | §18.7 | Async |
| `WEBHOOK_ENDPOINT_DISABLED` | §18.6 (`DELETE`, alias of §18.8) and §18.8 | Async |
| `WEBHOOK_SECRET_ROTATED` | §21.3 | Sync (credential-adjacent) |
| `WEBHOOK_DELIVERY_REPLAYED` | §23.3 | Sync |
| `PLUGIN_INSTALLED` | §27.3 | Async |
| `PLUGIN_ACTIVATED` | §27.5 | Async |
| `PLUGIN_CONFIGURATION_CHANGED` | §27.4 | Async |
| `PLUGIN_UPGRADED` | §29.4 | Async |
| `PLUGIN_UNINSTALLED` | §27.7 | Async |

### 36.3 Secrets Never in Audit Payloads

Per §12.1 rule 3: `audit.audit_events.resource_snapshot` never carries a resolved `credential_ref`, a raw OAuth token, a webhook signing secret, or a plugin credential — only non-secret metadata (`display_name`, `status`, `topics`, `enabled_capabilities`) is ever snapshotted, exactly matching 5B §30's pre-existing allow-list discipline applied to this document's resources.

---

## 37. Domain Events / Outbox

### 37.1 Mechanism — Reused Exactly, `audit.domain_event_outbox`

Every domain event this document's write endpoints produce (`integration.connected`, `integration.disconnected`, `webhook.endpoint_created`, `plugin.installed`, `plugin.activated`, `plugin.uninstalled`, etc. — 4F §12.3–12.5's catalog) is inserted into `audit.domain_event_outbox` (migration `077_5J1.sql`) **in the same DB transaction** as the state change that produced it — never published to Redis Streams directly before commit (6A §35, 6C's own precedent, reused verbatim):

```sql
-- Inside the same transaction as the state-changing write:
INSERT INTO audit.domain_event_outbox (event_type, organization_id, aggregate_type, aggregate_id, payload)
VALUES ('integration.connected', :org_id, 'integration_connection', :connection_id, :payload_jsonb);
COMMIT;
-- Outside the transaction, asynchronously:
-- audit.fn_claim_outbox_events() → Redis Streams publish → audit.fn_mark_outbox_published()
```

`app_api` holds `INSERT` on `audit.domain_event_outbox` (5J grant, confirmed) — this document's own REST handlers, running under the ordinary tenant request role, can perform this insert directly within their own request transaction; no internal-RPC hop is needed for the outbox write itself (only for the handful of `app_worker`-only SECURITY DEFINER functions named in §11–§29's per-endpoint contracts, per ADR-6J-01).

### 37.2 Outbox → Webhook Delivery — the Actual Fan-Out

The outbox-publisher's Redis Streams publish is consumed by `WebhookDispatchService` (4F §8.3), which matches the published event's topic against every `ACTIVE` `WebhookEndpoint` subscribed to it (within the same `organization_id`) and creates one `webhooks.webhook_deliveries` row per match — this is the concrete mechanism behind §17.8's architecture diagram and closes the loop from "a domain event happened anywhere in the platform" to "a tenant's registered webhook receives it."

### 37.3 What 6J Does Not Do

6J does not define a competing outbox table, does not bypass `audit.domain_event_outbox` for any event this document's resources produce, and does not publish directly to Redis Streams from a REST handler (6A §35's universal "DB write + outbox insert atomically, external effect strictly after commit" rule applies without exception here).

---

## 38. Async Processing

| Operation | Sync or Async | Mechanism |
|---|---|---|
| Connection creation, disconnect, reauthorize, config update | Sync (Tier B, 6A §11) — durable DB write, response returned once committed | Direct DB write — `101_5I1.sql`'s new functions are `app_api`-grantable, no RPC hop (ADR-6J-01) |
| Connection `test` | Sync (Tier A/B) — single bounded provider call through the egress adapter | Direct, in-request-cycle |
| Connection `sync` | **Async (Tier D)** — provider-bound, unbounded duration | Celery task, §15.3 |
| Webhook endpoint CRUD, enable/disable/rotate-secret | Sync (Tier A) — ordinary DB write | Direct |
| Webhook `test` | Sync accept (`202`), delivery itself processed by the existing async delivery worker pipeline (5I `fn_claim_delivery`) | Existing webhook delivery infra, not a new async path |
| Webhook delivery replay | Sync (Tier B) — single fast DB call | Direct (ADR-6J-01's revision — grant widened, no RPC) |
| Plugin installation creation | Sync (Tier B) — direct DB write, `app_api`-grantable function | Direct |
| Plugin activate/upgrade/uninstall/suspend/reactivate/config-update/rotate-credential | Sync (Tier B) | Direct (ADR-6J-01's revision — all `app_api`-grantable, no RPC) |
| Inbound provider webhook ingestion | Fast-ACK sync (`2xx` on durable INSERT) + async domain processing | §24.4 |

No operation in this document is modeled as a generic `/api/v1/jobs/{job_id}`-polled async job **except** connection sync (§15.3), which is explicitly disclosed as a degraded instance of 6A §18's job contract (no persisted job row, Celery-task-ID-only, §15.3's own caveat) rather than silently claimed as a full implementation of it.

---

## 39. Recordings / Binary Content

This document's resources never transmit or reference call recordings, transcripts, or documents directly — those remain 6D/6F's own domains (§7.5, §7.7). Where a webhook payload's `data.object` could theoretically embed a reference to such content (e.g., a hypothetical `call.completed` payload wanting to point at a recording), §40.3 requires **ID-only reference**, never the binary itself and never an inlined signed URL with a long-enough TTL to become a durable-feeling link — a consumer wanting the actual recording must call 6D's own authenticated, RBAC-checked, short-TTL-signed-URL endpoint (6A §29), which independently re-validates the caller's authorization at the moment of the call. No endpoint in this document ever accepts or returns base64-encoded media in a JSON body (6A §29's absolute prohibition, restated as binding here since a naive plugin/webhook-payload design could otherwise be tempted to embed one).

---

## 40. Data Privacy / Minimization

### 40.1 Principle

Webhook payloads and plugin callout payloads are **not** row dumps. Every `data.object` (§20.1) is built by an explicit per-topic serializer — the same allow-list discipline 6A §10.2 already requires of ordinary REST response models, applied to event payloads.

### 40.2 Field Sensitivity Classification (§19.1's Table, Detailed)

| Field class | Appears in | Handling |
|---|---|---|
| Phone numbers | `lead.created`, `lead.qualified`, `appointment.booked` | E.164-canonical (6A §7.5), included **only** because the topic's entire purpose is notifying the tenant's own CRM integration of a new lead — the tenant already owns this data in their own CRM |
| Names | Same topics, plus `integration_connections.external_account_name` (never in a webhook payload — that field is API-response-only, §8.4) | Included in `lead.*` payloads for the same reason as phone numbers |
| Email addresses | `lead.created`/`lead.qualified` (where captured) | Same |
| Transcripts | **Never** in any webhook payload | Reference by `call_id` only — 6D's own transcript-retrieval endpoint |
| Recordings | **Never** in any webhook payload | §39 |
| Lead/deal metadata | `deal.*`, `appointment.booked` | Minimized to the fields a downstream CRM sync genuinely needs — not the full internal `crm.contacts`/`crm.deals` row |
| Call content (any) | **Never** | Reference by `call_id` only |
| Provider identifiers | `integration.connected`-class internal events (not webhook-eligible), inbound-event observability (`provider_slug`, `provider_event_id`) | Not PII; safe to expose in `GET /inbound-webhook-events` |

### 40.3 Sensitive Resources — Reference by ID

Any payload field that would otherwise embed heavy or sensitive content (a full transcript, a document body, a large CRM record) is replaced with the resource's own ID plus, where the consuming tenant needs to fetch it, a pointer to the platform's own authenticated REST endpoint for that resource — never an embedded signed URL with platform-decided TTL baked into a webhook payload that might sit in the tenant's own logs/queue for longer than that TTL was designed for.

### 40.4 Inbound Raw Payload — V1 Default Not Retained

Per 5I ADR-5I-010 (reused verbatim, not revisited): V1 default is that `inbound_webhook_events.raw_payload_ref` is **not populated** — the raw provider payload is processed and discarded, not stored. Where a specific provider integration's debugging needs require it, `raw_payload_ref` may be enabled per-provider, storing the raw bytes in S3 only (never Postgres), encrypted, tenant-scoped path, 7-day TTL, deleted on GDPR erasure — this document does not change this default, and no endpoint in §24 exposes a raw-payload toggle to tenants (it is a platform/provider-integration-level configuration decision, not tenant-configurable).

---

## 41. Retention

| Data | Retention | Source |
|---|---|---|
| `oauth_attempts` | Purged 24h after expiry/redemption (5I §23) | 5I |
| `webhook_deliveries` (`DELIVERED`) | 30 days | 5I §23, 4F §8.2 |
| `webhook_deliveries` (`DEAD_LETTER`) | 90 days | 5I §14, 4F §8.2 invariant #3 |
| `inbound_webhook_events` | No dedicated TTL — general observability retention; unpartitioned until `>5M` rows (5I §27) | 5I |
| `plugin_executions` | No dedicated TTL — unpartitioned until `>5M` rows (5I §27) | 5I |
| `integration_connections`/`plugin_installations` history (terminal rows) | Retained indefinitely (terminal rows are never purged — they are the compliance-relevant record of "this tenant was once connected to X") | 5I (no purge function exists for these) |
| `audit.domain_event_outbox` | `PUBLISHED` rows: 7 days; `FAILED` rows: 30 days (operator investigation window) | Migration `077_5J1.sql` |
| `audit.audit_events` (this document's audit rows) | Per 5J's own platform-wide audit retention (out of this document's authority to restate/change) | 5J |

None of the above is DB-scheduled (no `pg_cron` job exists for any of it, matching 5I's and `077_5J1`'s own explicit documented pattern) — purge is an operational/ops-owned background process, out of this document's scope to design.

---

## 42. Deletion / Disconnect / Uninstall Semantics

### 42.1 Integration Connection Disconnect (§11.6)

| Consideration | Behavior |
|---|---|
| Credentials | Revoked/deleted from the secret manager (best-effort — a provider-side revocation call, where the provider supports one, is attempted but not required for the platform-side disconnect to succeed; a provider outage during disconnect must not block the tenant from disconnecting) |
| Active workflows referencing the connection | **Not** automatically modified. A `WEBHOOK`/`API_CALL`/plugin-capability node (§30.2) referencing this connection's `credential_source: "integration_connection"` fails closed at next execution (`INTEGRATION_DISABLED`, §36) rather than the disconnect being blocked by a workflow reference — disconnecting is always allowed; a subsequently-broken workflow is a visible failure, not a silent one |
| Sync jobs | Any in-flight Celery sync task for this connection is not force-cancelled by disconnect (no cancellation mechanism exists, §15.3) — it completes or fails on its own, and its result write (once DEP-6J-01 closes) targets a connection that is already `DISCONNECTED`, which the intended `fn_record_integration_sync_result()`-shaped function should treat as a no-op rather than an error (forward design note for the function's eventual implementation) |
| Webhook registrations | Not applicable — `WebhookEndpoint`s are independent tenant resources, never owned by an `IntegrationConnection` |
| Historical audit records | Survive disconnect unconditionally (5B/5J's own immutable-audit-trail guarantee, never touched by this document) |

### 42.2 Webhook Endpoint Deletion (§18.6)

| Consideration | Behavior |
|---|---|
| Deliveries | Existing `webhook_deliveries` rows are untouched (immutable, §17.1) — visible in delivery history per their normal retention (§41) regardless of the endpoint's current status |
| Audit history | Survives |
| Secret | Purged from the secret manager once the overlap window (§21.3, if a rotation was in flight) elapses; otherwise purged immediately on hard delete (platform-admin path only, §18.6) |
| Future events | No new deliveries created once `status != 'ACTIVE'` (soft-delete-via-disable is the tenant-facing `DELETE` semantics, §18.6) |

### 42.3 Plugin Uninstall (§27.7)

| Consideration | Behavior |
|---|---|
| Workflows referencing plugin capabilities | Same fail-closed-at-execution policy as §42.1 — uninstall is never blocked by a workflow reference; a workflow node referencing an uninstalled installation's `plugin_installation_id` fails with `PLUGIN_NOT_INSTALLED` (§35) at next execution |
| Credentials | `credential_ref` row-level reference is orphaned in Postgres (the `plugin_installations` row itself persists, `status = 'UNINSTALLED'`, terminal) but the underlying secret-manager entry is purged (best-effort, mirrors §42.1) |
| Configuration | Retained on the terminal row (not cleared) — matches 5I's own "no seed data / historical rows survive" posture; nothing in the executed DDL clears `configuration` on uninstall, and this document does not introduce an uninstall-time data-scrub beyond credential purge |
| Execution history | `plugin_executions` rows survive uninstall unconditionally (retention per §41) |

### 42.4 No Reliance on Cascade Deletes

None of the three flows above relies on a database `ON DELETE CASCADE` to achieve correct behavior — every dependent-resource consideration above is either "the dependent row is immutable/historical and simply persists" or "the dependent operation fails closed at its own next execution," matching the task brief's explicit instruction not to rely blindly on cascade semantics for these resources. (5I's own FK `ON DELETE RESTRICT`s, e.g. `integration_connections.definition_id`, further guarantee a platform-owned definition/plugin cannot be hard-deleted while tenant rows still reference it — a structural, not just an application-level, safeguard.)

### 42.5 `409 INTEGRATION_IN_USE` — Not Used

This document deliberately does **not** introduce a blocking `409 INTEGRATION_IN_USE`-style dependency-conflict response for disconnect/uninstall, because the fail-closed-at-execution policy above (consistent with 6I's own `PLUGIN_DISABLED`/`INTEGRATION_DISABLED` fail-closed pattern for a node referencing a no-longer-active resource) is judged the better default for this platform: forcing a tenant to first find and edit every workflow referencing a connection before they're allowed to disconnect it would be a materially worse UX for a security-relevant self-service action (a tenant revoking access to a compromised or unwanted integration should never be blocked by an unrelated workflow's stale reference) — this is recorded as **ADR-6J-04** (§55), not a silent omission.

---

## 43. Deprecation & Provider Outage Behavior

### 43.1 Deprecation — No Silent Removal

| Resource | Deprecation path |
|---|---|
| `IntegrationDefinition` | `is_active = false` (ordinary platform-admin `UPDATE`, grant exists, §9) — blocks **new** connections; `fn_create_integration_connection()` now DB-checks `is_active` itself as of `101_5I1.sql` (§56, closes former DEP-6J-09), not merely at the application layer; existing connections are **not** force-disconnected — they continue operating until the tenant disconnects or the connection degrades on its own |
| `PluginVersion` | `DEPRECATED` status (§29.2) — blocks new installs/upgrades, DB-enforced; existing installations pinned to it continue running |
| `Plugin` (whole plugin withdrawn) | No dedicated "plugin-level deprecated" status exists beyond individual version deprecation (§26.1) — withdrawing an entire plugin from new installation is achieved by deprecating every `APPROVED` version; this is disclosed as the actual mechanism, not a separate one |
| `WebhookEndpoint` topic | Additive-only (§19.1, §53) — an existing topic string is never removed or repurposed; a genuinely breaking payload-shape change ships as a **new** topic (`call.completed.v2`), per 4F §8.4's own versioned-topic convention, leaving the old topic's subscribers unaffected |

**Existing customer installations/connections always have predictable behavior** — none of the deprecation paths above force an immediate, tenant-visible break; every one degrades gracefully (new-instance blocking only) or requires the tenant's own explicit action to be affected.

### 43.2 Provider Outage Behavior

| Concern | Behavior |
|---|---|
| Retry | Governed by §16.2 (provider `429`/`5xx` backoff) for sync/test/plugin calls; §22.3 for webhook deliveries |
| Circuit breaking | Reused from 6A §21's platform-wide generalization of the voice providers' Redis-backed `providerhealth:{provider_name}` pattern (3B §16/§19) — applied here to integration/plugin provider calls identically; **not reinvented** by this document |
| Degraded health, not deletion | A provider outage manifests as `integration_health.consecutive_failure_count` climbing and `aggregate_status` (§14.1) reading `DEGRADED`/`FAILED` — **never** an automatic `credential_ref` deletion or forced disconnect. §8.6's state machine has no "provider outage" transition at all; a connection stays `ACTIVE` (with degraded health visible via §14) through a provider outage unless/until the tenant manually disconnects |
| Operator visibility | `GET .../health` (§14) is the tenant-facing signal; platform-side, the same `provider_circuit_open` gauge (6A §26) any other provider dependency uses applies here without a new metric being invented |
| Bounded queue growth | Sync jobs (§15.3) are single-in-flight per connection (Redis lock) — a provider outage cannot cause unbounded queued sync attempts to pile up for one connection; webhook delivery's own `max_attempts` ceiling (§22.3) bounds retry-storm risk identically for outbound delivery |
| Distinguishing outage from invalid credentials | `failure_class` (§35.2) explicitly separates `PROVIDER_UNAVAILABLE` (network/5xx/timeout) from `AUTH_FAILED` (credential rejected) — the tenant-facing `aggregate_status` derivation (§14.1) surfaces `AUTH_REQUIRED` only for the latter, never conflating a transient outage with "your credential needs attention" |

---

## 44. Observability

Reconciled with the already-implemented OTel + Prometheus + `structlog` stack (6A §25) — no parallel observability system is introduced.

**Metric label cardinality (corrected — remediation §16, P1):** no Prometheus metric in this document is labeled with `organization_id` or any other per-tenant identifier — a prior revision's `platform_integration_connections_total{organization_id,...}` label was a high-cardinality design mistake (organization count × status count × definition count time series, unbounded growth as tenants are added, exactly the anti-pattern Prometheus's own data model warns against). Every metric below uses only low-cardinality dimensions (provider/plugin key, status, capability, failure class — each a small, bounded set). Per-tenant identity is carried instead in **traces** (span attributes), **structured logs**, and **audit records** (§36) — all three already tenant-scoped by design (6A §25) and appropriate for per-tenant drill-down without inflating the metrics time-series cardinality that dashboards and alerting rules query against.

### 44.1 Integrations

| Signal | Metric/trace |
|---|---|
| Connection counts | `platform_integration_connections_total{definition_key,status}` (gauge) — aggregate across all tenants; per-tenant connection counts are a query against the `integration_connections` table itself (§14/§51), not a metric label |
| Auth failures | `platform_integration_auth_failures_total{definition_key}` (counter), sourced from `integration_health.auth_failure_count` deltas |
| Provider requests/latency | Span per egress-adapter call, tagged `caller: "integration_test" \| "integration_sync"`, `provider: {definition_key}` — dependency-latency breakdown per 6A §25 |
| Provider errors | `platform_integration_provider_errors_total{definition_key,failure_class}` |
| Rate limiting | `platform_integration_rate_limited_total{definition_key}` |
| Sync duration/failures | `platform_integration_sync_duration_seconds{definition_key}`, `platform_integration_sync_failures_total{definition_key}` |

### 44.2 Webhooks

| Signal | Metric |
|---|---|
| Deliveries | `platform_webhook_deliveries_total{status}` |
| Success/failure rate | `webhook_delivery_success_rate` (already named in 6A §25's core metric set — reused, not reinvented) |
| Latency | `platform_webhook_delivery_duration_seconds` |
| Retries | `platform_webhook_delivery_attempts_total{attempt_number}` |
| Suspended endpoints | `platform_webhook_endpoints_suspended_total` (once DEP-6J-07 closes, §56) |
| Replay counts | `platform_webhook_replays_total` |

### 44.3 Plugins

| Signal | Metric |
|---|---|
| Executions | `platform_plugin_executions_total{plugin_key,capability,status}` — sourced from `plugin_executions` |
| Failures | `platform_plugin_execution_failures_total{plugin_key,capability}` |
| Latency | `platform_plugin_execution_duration_seconds{plugin_key}` |
| Scope denials | `platform_plugin_scope_denied_total{plugin_key}` (§28.3 rejections) |
| Version usage | `platform_plugin_installations_by_version{plugin_key,semver}` |

### 44.4 Correlation and Redaction

Every span/log line this document's code paths emit carries `request_id`/trace context (6A §25) and `organization_id` (nullable only for genuinely platform-scoped operations, e.g. `IntegrationDefinition` catalog reads). **Never logged:** `credential_ref`'s resolved value, `Authorization` headers (inbound or the outbound provider/plugin/webhook calls this document makes), signing secrets, raw OAuth tokens — the existing PII/secret-redacting log processor (3E §14.1, 6A §22) is not bypassed by any code path this document specifies.

---

## 45. Rate Limits

### 45.1 API Rate Limits

Governed entirely by 6A §20's existing two-tier model (NGINX per-IP, application per-tenant-per-endpoint-class) — no new rate-limiting mechanism is introduced. `POST .../connections/{id}/test` and `POST .../webhook-endpoints/{id}/test` carry their own additional, narrower application-quota ceilings (§11.8: 10/hour; §18.10: 10/hour) layered on top of, not instead of, 6A §20's standard-CRUD tenant quota.

### 45.2 Business/Resource Limits

| Limit | V1 default | Configurable? |
|---|---|---|
| Max webhook endpoints per organization | 20 | `LIMIT VALUE — BILLING/PRODUCT CONFIGURATION, NOT HARD-CODED IN 6J` |
| Max topic subscriptions per webhook endpoint | No explicit cap beyond the governed catalog's own size (19 topics, §19.1) — a single endpoint may subscribe to all of them | N/A |
| Max integration connections per provider per org | 1 non-terminal (§8.2, DB-enforced) | Not tenant-configurable — a Product/architecture decision (ODD-5I-01) |
| Max plugin installations per organization | Not capped by this document | `LIMIT VALUE — BILLING/PRODUCT CONFIGURATION, NOT HARD-CODED IN 6J` |
| Max webhook payload size | Delivery body itself is unbounded at the DB layer (`payload_json TEXT`) but application-layer capped at 256KB before INSERT (mirrors `audit.domain_event_outbox.chk_outbox_payload_size`'s own 262144-byte cap, applied here for consistency across the platform's two outbox-adjacent payload tables) | Fixed, not a business/plan-tier lever |
| Delivery timeout | 1000–30000ms, per-endpoint (`timeout_ms`, 5I) | Tenant-configurable within that DB-CHECKed range |
| Replay window | 30/90 days (§22.6, retention-bound) | Not tenant-configurable |
| Replay frequency | 10/delivery/24h (§23.3) | `LIMIT VALUE — BILLING/PRODUCT CONFIGURATION, NOT HARD-CODED IN 6J` |
| Sync concurrency | 1 per connection (§15.3, DB/Redis-enforced) | Not tenant-configurable |
| Plugin rate limit | `manifest.rate_limit_per_minute`, narrowable via `rate_limit_override` (§25.3) | Per-plugin-version (platform-set), per-installation override (tenant-set, narrowing only) |

Every row marked `LIMIT VALUE — BILLING/PRODUCT CONFIGURATION, NOT HARD-CODED IN 6J` is a placeholder default for design purposes, exactly matching the task brief's own required phrasing — actual plan-tier values are 6K/product's decision, not fabricated here.

---

## 46. Billing / Usage Handoff

### 46.1 What 6J May Emit

If Product later requires billing for integration/plugin usage, the natural metering points this document's own resources already produce (without 6J designing any billing semantics) are:

| Candidate billable fact | Source |
|---|---|
| Provider API operation count (per sync/test call) | `integration_health` update events, or a per-call span already emitted (§44.1) |
| Plugin execution count | `plugin_executions` row count (already durable, per-installation, per-capability) |
| Webhook delivery volume | `webhook_deliveries` row count (already durable) |
| Sync operation count/duration | Celery task result (§15.3) |

### 46.2 What 6J Does Not Do

6J does **not** write to `billing.usage_events`, does not define a `source_system` value for this domain, does not decide which of the candidates above are actually billable, and does not compute cost. Per 5H's own idempotency shape (`UNIQUE (organization_id, source_system, source_event_id, occurred_at)`), a future 6K document would define `source_system = 'integrations' | 'plugins' | 'webhooks'` and the exact `source_event_id` derivation (e.g. `plugin_executions.id` for plugin usage) — this document only confirms the raw facts exist and are durable enough for 6K to meter from, per §57's forward dependency (no billable metric is invented here without product-requirements evidence, per the task brief's explicit instruction).

---

## 47. Request/Response Examples

### 47.1 OAuth Authorize

`POST /api/v1/integrations/connections/{connection_id}/oauth/authorize` →
```json
{ "data": { "authorization_url": "https://login.salesforce.com/services/oauth2/authorize?client_id=...&redirect_uri=https%3A%2F%2Fapi.platform.example%2Fapi%2Fv1%2Fintegrations%2Foauth%2Fsalesforce_crm%2Fcallback&state=8f14e45f...&code_challenge=E9Melhoa...&code_challenge_method=S256&scope=api+refresh_token", "expires_at": "2026-08-29T10:10:00Z" } }
```

### 47.2 Connection Test — Failure

```json
{ "data": { "result": "FAILURE", "failure_class": "AUTH_FAILED", "checked_at": "2026-08-29T10:00:00Z", "detail": "Provider rejected the current credential." } }
```

### 47.3 Webhook Delivery Detail

```json
{
  "data": {
    "id": "01930000-0000-7000-8000-000000000040",
    "webhook_endpoint_id": "01930000-0000-7000-8000-000000000020",
    "event_id": "evt_01930000-0000-7000-8000-000000000030",
    "event_type": "call.completed",
    "status": "DELIVERED",
    "attempt_count": 1,
    "max_attempts": 7,
    "last_response_code": 200,
    "last_response_body_preview": "{\"ok\":true}",
    "is_test": false,
    "replay_count": 0,
    "payload_json": "{\"id\":\"evt_...\",\"type\":\"call.completed\",...}",
    "created_at": "2026-08-29T09:59:58Z",
    "completed_at": "2026-08-29T09:59:59Z"
  }
}
```

### 47.4 Sync Job Accepted

```json
{ "data": { "job_id": "c7b3f2a0-...", "status": "PENDING" } }
```

### 47.5 Plugin Installation

```json
{
  "data": {
    "id": "01930000-0000-7000-8000-000000000050",
    "plugin_id": "01930000-0000-7000-8000-000000000060",
    "plugin_version_id": "01930000-0000-7000-8000-000000000061",
    "status": "ACTIVE",
    "configuration": { "default_channel": "#sales" },
    "enabled_capabilities": ["workflow.action.notify_slack"],
    "rate_limit_override": null,
    "installed_by": { "user_id": "...", "display_name": "Priya Sharma" },
    "installed_at": "2026-08-20T00:00:00Z",
    "activated_at": "2026-08-20T00:05:00Z"
  }
}
```

### 47.6 Error Example — Scope Denial

```json
{
  "error": {
    "code": "PLUGIN_SCOPE_DENIED",
    "message": "One or more requested capabilities are not declared by this plugin version's manifest.",
    "details": { "requested": ["crm.contact.delete"], "allowed": ["workflow.action.notify_slack"] },
    "request_id": "01930000-0000-7000-8000-000000000070",
    "retryable": false
  }
}
```

---

## 48. Endpoint Inventory

All rows below reflect the two 2026-08-29 remediation passes' corrections — no endpoint is marked `EXECUTION-BLOCKED` any longer; §56's P0 gaps are closed by migration `101_5I1.sql` and **live-validated** against PostgreSQL 18.6 (§60); every DB-execution note below says "direct" rather than "internal-RPC" per ADR-6J-01's revision (§55).

| Method | Path | Purpose | Auth | Permission | Idempotency | Async | Audit |
|---|---|---|---|---|---|---|---|
| GET | `/api/v1/integration-definitions` | List provider catalog | JWT/API key | `integration:read` | N/A | No | No |
| GET | `/api/v1/integration-definitions/{key}` | Get provider definition | JWT/API key | `integration:read` | N/A | No | No |
| GET | `/api/v1/integrations/connections` | List connections | JWT/API key | `integration:read` | N/A | No | No |
| POST | `/api/v1/integrations/connections` | Create connection | JWT/API key | `integration:manage` | Required | No | `INTEGRATION_CONNECTION_CREATED` |
| GET | `/api/v1/integrations/connections/{id}` | Get connection | JWT/API key | `integration:read` | N/A | No | No |
| PATCH | `/api/v1/integrations/connections/{id}` | Update config (`fn_update_integration_connection_config`) | JWT/API key | `integration:manage` | N/A | No | `INTEGRATION_CONFIG_UPDATED` |
| DELETE | `/api/v1/integrations/connections/{id}` | Disallowed (405) — use `disconnect` | JWT/API key | `integration:manage` | N/A | No | N/A |
| POST | `/api/v1/integrations/connections/{id}/disconnect` | Disconnect (`fn_disconnect_integration_connection`) | JWT/API key | `integration:manage` | Optional | No | `INTEGRATION_DISCONNECTED` |
| POST | `/api/v1/integrations/connections/{id}/reauthorize` | Re-run credential acquisition (`ACTIVE`/`DEGRADED` only, never `FAILED`) | JWT/API key | `integration:manage` | Optional | No | `INTEGRATION_REAUTHORIZED` |
| POST | `/api/v1/integrations/connections/{id}/test` | Live connectivity test | JWT/API key | `integration:manage` | N/A | No | `INTEGRATION_TEST_PERFORMED` |
| POST | `/api/v1/integrations/connections/{id}/oauth/authorize` | Start OAuth flow | JWT/API key | `integration:manage` | N/A | No | No |
| GET | `/api/v1/integrations/oauth/{key}/callback` | OAuth browser redirect target (`fn_redeem_oauth_callback_state`, tenant-bootstrap-safe) | None (state-bound) | N/A | N/A | No | `INTEGRATION_CONNECTED` (on success) |
| GET | `/api/v1/integrations/connections/{id}/health` | Health snapshot | JWT/API key | `integration:read` | N/A | No | No |
| POST | `/api/v1/integrations/connections/{id}/sync` | Trigger sync | JWT/API key | `integration:manage` | Optional | **Yes (Tier D)** | No (task-level) |
| POST | `/api/v1/integrations/providers/{slug}/callbacks/{opaque_connection_route_id}` | Generic inbound provider callback (opaque routing, §24.6/ADR-6J-10) | None (provider-signed) | N/A | N/A (dedup key) | Fast-ACK + async | No |
| GET | `/api/v1/inbound-webhook-events` | List inbound events (observability) | JWT/API key | `integration:read` | N/A | No | No |
| GET | `/api/v1/inbound-webhook-events/{id}` | Get inbound event | JWT/API key | `integration:read` | N/A | No | No |
| GET | `/api/v1/webhook-endpoints` | List webhook endpoints | JWT/API key | `webhook:read` | N/A | No | No |
| POST | `/api/v1/webhook-endpoints` | Create webhook endpoint | JWT/API key | `webhook:manage` | Required | No | `WEBHOOK_ENDPOINT_CREATED` |
| GET | `/api/v1/webhook-endpoints/{id}` | Get webhook endpoint | JWT/API key | `webhook:read` | N/A | No | No |
| PATCH | `/api/v1/webhook-endpoints/{id}` | Update webhook endpoint | JWT/API key | `webhook:manage` | N/A | No | `WEBHOOK_ENDPOINT_UPDATED` |
| DELETE | `/api/v1/webhook-endpoints/{id}` | Soft-disable (alias of `.../disable`) | JWT/API key | `webhook:manage` | N/A | No | `WEBHOOK_ENDPOINT_DISABLED` |
| POST | `/api/v1/webhook-endpoints/{id}/enable` | Enable | JWT/API key | `webhook:manage` | N/A | No | `WEBHOOK_ENDPOINT_ENABLED` |
| POST | `/api/v1/webhook-endpoints/{id}/disable` | Disable | JWT/API key | `webhook:manage` | N/A | No | `WEBHOOK_ENDPOINT_DISABLED` |
| POST | `/api/v1/webhook-endpoints/{id}/rotate-secret` | Rotate signing secret (dual-signature grace, `fn_rotate_webhook_secret`) | JWT/API key | `webhook:manage` | Optional | No | `WEBHOOK_SECRET_ROTATED` |
| POST | `/api/v1/webhook-endpoints/{id}/test` | Send test delivery | JWT/API key | `webhook:manage` | N/A | Yes (delivery pipeline) | No |
| GET | `/api/v1/webhook-deliveries` | List deliveries | JWT/API key | `webhook:read` | N/A | No | No |
| GET | `/api/v1/webhook-deliveries/{id}` | Get delivery | JWT/API key | `webhook:read` | N/A | No | No |
| POST | `/api/v1/webhook-deliveries/{id}/replay` | Replay delivery | JWT/API key | `webhook:manage` | Optional | No (direct, ADR-6J-01) | `WEBHOOK_DELIVERY_REPLAYED` |
| GET | `/api/v1/plugins` | List plugin catalog | JWT/API key | `plugin:read` | N/A | No | No |
| GET | `/api/v1/plugins/{key}` | Get plugin + versions | JWT/API key | `plugin:read` | N/A | No | No |
| GET | `/api/v1/plugin-installations` | List installations | JWT/API key | `plugin:read` | N/A | No | No |
| POST | `/api/v1/plugin-installations` | Install plugin | JWT/API key | `plugin:install` | Required | No | `PLUGIN_INSTALLED` |
| GET | `/api/v1/plugin-installations/{id}` | Get installation | JWT/API key | `plugin:read` | N/A | No | No |
| PATCH | `/api/v1/plugin-installations/{id}` | Update config (`fn_update_plugin_installation_config`) | JWT/API key | `plugin:manage` | N/A | No | `PLUGIN_CONFIGURATION_CHANGED` |
| POST | `/api/v1/plugin-installations/{id}/rotate-credential` | Rotate installation credential (`fn_rotate_plugin_installation_credential`) | JWT/API key | `plugin:manage` | Optional | No | `PLUGIN_CREDENTIAL_ROTATED` |
| POST | `/api/v1/plugin-installations/{id}/activate` | Activate + set capabilities | JWT/API key | `plugin:manage` | Optional | No (direct, ADR-6J-01) | `PLUGIN_ACTIVATED` |
| POST | `/api/v1/plugin-installations/{id}/suspend` | Suspend (`fn_suspend_plugin_installation`) | JWT/API key | `plugin:manage` | Optional | No | `PLUGIN_SUSPENDED` |
| POST | `/api/v1/plugin-installations/{id}/reactivate` | Reactivate (`fn_reactivate_plugin_installation`, capabilities preserved, not reset) | JWT/API key | `plugin:manage` | Optional | No | `PLUGIN_REACTIVATED` |
| POST | `/api/v1/plugin-installations/{id}/upgrade` | Upgrade to new version | JWT/API key | `plugin:manage` | Optional | No (direct, ADR-6J-01) | `PLUGIN_UPGRADED` |
| DELETE | `/api/v1/plugin-installations/{id}` | Uninstall | JWT/API key | `plugin:manage` | N/A (idempotent) | No (direct, ADR-6J-01) | `PLUGIN_UNINSTALLED` |

**Total: 42 endpoints** (17 integration, 11 webhook, 14 plugin — including the two browser-redirect/provider-callback endpoints, and the one new `rotate-credential` action added this pass; excluding no listed row). Every endpoint above appears exactly once in this table.

---

## 49. Authorization Matrix

| Endpoint | Principal | Organization Scope | Permission | Ownership Check | Notes |
|---|---|---|---|---|---|
| `GET /integration-definitions[/…]` | User (JWT) or API key | None (global) | `integration:read` | N/A (platform-global) | Cacheable |
| `GET/POST/PATCH/DELETE/action /integrations/connections[/…]` | User (JWT) or API key | Tenant (RLS) | `integration:read` (GET) / `integration:manage` (mutations) | RLS + app-layer re-check | Cross-tenant ID → 404 |
| `GET /integrations/connections/{id}/oauth/authorize` (POST) | User (JWT) or API key | Tenant | `integration:manage` | RLS | Creates `oauth_attempts` row |
| `GET /integrations/oauth/{key}/callback` | **None** (browser, state-bound) | Recovered as **output** from `fn_redeem_oauth_callback_state(state)` — never required as caller input (§13.3, ADR-6J-08) | N/A | `state`'s own uniqueness/single-use/TTL (the security boundary) | Not a normal authenticated principal |
| `GET /integrations/connections/{id}/health` | User (JWT) or API key | Tenant | `integration:read` | RLS | — |
| `POST /integrations/connections/{id}/sync` | User (JWT) or API key | Tenant | `integration:manage` | RLS + Redis lock | Async |
| `POST /integrations/providers/{slug}/callbacks/{opaque_connection_route_id}` | **None** (external provider) | Resolved via `{opaque_connection_route_id}` **before** payload is trusted, confirmed only after provider-signature verification succeeds (§24.6, ADR-6J-10) | N/A | Opaque routing segment (or provider-signed key ID where supported) selects the connection; verification confirms it | Never tenant-JWT-authenticated; never trusts an unverified payload field for routing |
| `GET /inbound-webhook-events[/…]` | User (JWT) or API key | Tenant | `integration:read` | RLS | Observability only |
| `GET/POST/PATCH/DELETE/action /webhook-endpoints[/…]` | User (JWT) or API key | Tenant | `webhook:read` (GET) / `webhook:manage` (mutations) | RLS | — |
| `GET/POST /webhook-deliveries[/…]` | User (JWT) or API key | Tenant | `webhook:read` (GET) / `webhook:manage` (replay) | RLS | Cursor-paginated only |
| `GET /plugins[/…]` | User (JWT) or API key | None (global) | `plugin:read` | N/A; non-`APPROVED` hidden from non-admins | — |
| `GET /plugin-installations` | User (JWT) or API key | Tenant | `plugin:read` | RLS | — |
| `POST /plugin-installations` | User (JWT) or API key | Tenant | `plugin:install` | RLS | Narrower than `plugin:manage` |
| `GET/PATCH/DELETE/action /plugin-installations/{id}[/…]` (including `rotate-credential`, `suspend`, `reactivate`) | User (JWT) or API key | Tenant | `plugin:read` (GET) / `plugin:manage` (all others) | RLS | — |

**System/internal-only endpoints:** **none.** ADR-6J-01's revision (§55) removed the internal-RPC pattern this matrix previously listed a row for — every endpoint in this document's inventory (§48) executes directly within its own request transaction under `app_api`, with tenant isolation enforced by each SECURITY DEFINER function's own `organization_id`-scoped lock/check (§31), not by a separate internal-principal hop. This document introduces no `/api/internal/v1/...` surface of its own.

---

## 50. Event Catalog

| Event | Producer | External Webhook Eligible | Schema Version | Sensitive Data | Notes |
|---|---|---|---|---|---|
| `call.started` | Voice (6D) | Yes | 1 | No | 4F §8.4 |
| `call.completed` | Voice (6D) | Yes | 1 | No (references only) | §40.2 |
| `call.failed` | Voice (6D) | Yes | 1 | No | — |
| `call.transferred` | Voice (6D) | Yes | 1 | No | — |
| `lead.created` | CRM (6G) | Yes | 1 | Yes (phone/name/email) | §40.2 |
| `lead.qualified` | CRM (6G) | Yes | 1 | Yes | — |
| `lead.disqualified` | CRM (6G) | Yes | 1 | Yes | — |
| `deal.created` | CRM (6G) | Yes | 1 | Possibly | — |
| `deal.won` | CRM (6G) | Yes | 1 | Possibly | — |
| `deal.lost` | CRM (6G) | Yes | 1 | Possibly | — |
| `appointment.booked` | CRM (6G) | Yes | 1 | Yes | — |
| `campaign.started` | Campaign (6H) | Yes | 1 | No | — |
| `campaign.completed` | Campaign (6H) | Yes | 1 | No | — |
| `campaign.contact.qualified` | Campaign (6H) | Yes | 1 | Yes | — |
| `invoice.created` | Billing (future 6K) | Yes (contract-defined) | 1 | Financial | No producer yet, §46.2 |
| `invoice.paid` | Billing (future 6K) | Yes (contract-defined) | 1 | Financial | Same |
| `payment.failed` | Billing (future 6K) | Yes (contract-defined) | 1 | Financial | Same |
| `usage.threshold_reached` | Usage/Billing (future 6K) | Yes (contract-defined) | 1 | No | Same |
| `subscription.changed` | Billing (future 6K) | Yes (contract-defined) | 1 | No | Same |
| `integration.connected` | Integrations (6J) | No (internal domain event only — drives `INTEGRATION_CONNECTED` audit, not a subscribable topic) | 1 | No | §37 |
| `integration.disconnected` | Integrations (6J) | No | 1 | No | §37 |
| `webhook.endpoint_created` | Webhooks (6J) | No | 1 | No | §37 |
| `webhook.delivery_succeeded` / `.delivery_failed` / `.delivery_dead_lettered` | Webhooks (6J) | No (meta-events about delivery itself, not domain events — would be a confusing infinite-regress topic if made webhook-eligible) | 1 | No | 4F §12.4 |
| `plugin.installed` / `.activated` / `.suspended` / `.uninstalled` | Plugins (6J) | No | 1 | No | 4F §12.5 |
| `platform.test` | Webhooks (6J) | Yes — but **only** delivered on-demand via §18.10, never emitted from `audit.domain_event_outbox` | 1 | No | §18.10 |

**Not in the governed catalog (§19.1's explicit exclusions):** `agent.*`, `workflow.execution.*`, `document.*`/`knowledge_base.*` — flagged as non-blocking forward decisions (§57 DEC-6J-04), not fabricated.

---

## 51. Database Traceability

| API Resource | Database Table(s) | Source Document | Notes |
|---|---|---|---|
| `IntegrationDefinition` | `integrations.integration_definitions` | 5I §28 migration `060` | — |
| `IntegrationConnection` | `integrations.integration_connections` | 5I §28 migration `061` | DEP-6J-01 gaps apply (§56) |
| `OAuthAttempt` | `integrations.oauth_attempts` | 5I §28 migration `061` | DEP-6J-05 (fail-path gap) |
| `IntegrationHealth` | `integrations.integration_health` | 5I §28 migration `061` | Ordinary UPDATE grant, no gap |
| `WebhookEndpoint` | `webhooks.webhook_endpoints` | 5I §28 migration `062` | No gap |
| `WebhookDelivery` | `webhooks.webhook_deliveries` (partitioned) | 5I §28 migration `063` | No gap (replay function `app_worker`-only, ADR-6J-01 resolves) |
| `InboundWebhookEvent` | `webhooks.inbound_webhook_events` | 5I §28 migration `062` | No gap |
| `Plugin` | `plugins.plugins` | 5I §28 migration `064` | No gap |
| `PluginVersion` | `plugins.plugin_versions` | 5I §28 migration `064` | No gap |
| `PluginInstallation` | `plugins.plugin_installations` | 5I §28 migration `065` | DEP-6J-02 gap applies (§56) |
| `PluginExecution` | `plugins.plugin_executions` | 5I §28 migration `065` | No gap |
| Domain event outbox | `audit.domain_event_outbox` | 5J migration `077_5J1.sql` | Reused, not owned by 6J |
| Audit trail | `audit.audit_events` | 5J | Reused, not owned by 6J |
| `IntegrationSyncJob` / `IntegrationSyncCursor` | **Does not exist** | — | **PHASE 5 SCHEMA GAP — DEP-6J-06** (§56) |

No table name in this document is invented or presented as existing when it does not — every row above cites the exact migration that created it, or is explicitly flagged as absent.

---

## 52. Cross-Phase Traceability

| 6J Concern | Upstream Source | Dependency / Contract |
|---|---|---|
| Envelope, pagination, idempotency, error contract, latency tiers, versioning | 6A | Binding, unmodified (§5–§62 throughout) |
| Auth (JWT/API key), RBAC evaluation, internal service JWT | 6B | §32 permissions; internal service JWT reused only for §17.2's central-issuer mechanism generally — no longer for this document's own state-transition functions, per ADR-6J-01's revision (§55) |
| Organization/tenant/membership model | 6C (Core Platform) | Tenant resolution chain (§31), no redesign |
| Calls/telephony/Exotel boundary | 6D | §7.5, §24.5 — inbound table shared, endpoint not redesigned |
| AI Agent domain | 6E | Out of scope (§7.6) |
| Knowledge/RAG | 6F | Out of scope (§7.7), forward connector note |
| CRM/Leads | 6G | §7.3 — ACL produces commands only |
| Campaigns | 6H | §7.4 — topic exposure only |
| Workflow orchestration | 6I | §7.2, §30 — closes 6I §23/§54 item 5 dependency |
| Phase 5 integration/webhook/plugin schema | 5I | Authoritative DDL for §8–§29 throughout |
| Phase 5 audit schema | 5J | §36 vocabulary, §37 outbox |
| Transactional outbox | 5J migration `077_5J1.sql` | §37 |
| Billing handoff | Future 6K | §46 — facts only, no ledger semantics |
| Analytics handoff | Future 6L | §44's metrics are the raw material; no 6L-owned dashboard designed here |

---

## 53. Threat Model

| Threat | Control | Residual Risk |
|---|---|---|
| SSRF via webhook/plugin/workflow-node URL | §30.3 egress-control adapter — scheme allow-list, private/link-local/RFC1918/cloud-metadata blocking, resolve-then-pin DNS, bounded redirects, response-size cap | Enterprise-tenant private-network egress (a legitimate future need) is unconditionally blocked in V1 — no allow-list exists yet; low residual risk, tracked as a forward product decision, not a security gap |
| Credential leakage (API response, logs, audit, errors) | §12.1's six absolute rules; structurally-absent response-model fields (6A §10.2) | A future engineer adding a new response model incorrectly including `credential_ref` is a code-review-discipline risk, not a design gap — mitigated by the "structurally absent" pattern being harder to accidentally violate than a runtime redaction step |
| OAuth `state` replay | `UNIQUE(state)` + single-use `fn_redeem_oauth_callback_state` (§13.3, ADR-6J-08), DB row lock | None identified — DB-enforced, not merely application-checked |
| OAuth tenant-bootstrap circular dependency (a caller unable to supply `organization_id` for redemption) | **Corrected P0** — `fn_redeem_oauth_callback_state(state)` takes `state` alone and returns tenant identity as output (§13.3, ADR-6J-08); confirmed the fix requires no RLS change since the function's owning role (`app_migration`) already carries `BYPASSRLS` (§56, cited against `001_5B.sql` and the live `077_5J1_VALIDATION_REPORT.md`) | None identified for the corrected design; residual risk is the disclosed not-yet-live-validated status of the migration itself (§60) |
| CSRF on OAuth callback | `state` is unguessable (256-bit), tenant-bound, single-use; `redirect_uri` fixed at attempt-creation time, never taken from the callback request (§13.4) | None identified |
| Malicious/compromised webhook endpoint (tenant's own target) | §30.3 SSRF checks at registration; response body capped/truncated (512 bytes); no redirect-follow on delivery (§22.4) | A tenant registering their own malicious endpoint can still receive their own tenant's data (expected — it's their data); cannot be used to pivot into platform-internal or another tenant's resources |
| Webhook replay attacks (an attacker capturing and resending a delivery) | §21.2 rules 2–3 — 5-minute timestamp freshness window (checked against whichever of the two rotation-grace signatures matched), consumer-enforced; TLS in transit prevents interception in the first place | Relies on the consumer actually implementing the freshness check (documented as MUST, not DB-enforceable since it happens on the tenant's own server) |
| Webhook secret rotation leaving no working grace period (a consumer's in-flight deployment rejects every delivery mid-rotation) | **Corrected P0** — dual-signature grace (§21.1/§21.3, ADR-6J-07): the platform signs with both the current and unexpired-previous secret during the grace window, so a consumer holding either succeeds | None identified for the corrected design; a consumer whose own verification code checks only `X-Platform-Signature` (never attempting `X-Platform-Signature-Previous`) simply doesn't benefit from the grace period, which is an opt-in improvement, not a regression from pre-rotation behavior |
| Confused-deputy / cross-tenant routing on generic inbound provider callback (an unverified payload field selecting which tenant's secret governs verification) | **Corrected P0** — opaque per-connection routing segment (§24.6, ADR-6J-10) selects the candidate connection **before** any payload content is trusted; tenant identity is only trusted **after** that connection's own verification method succeeds | None identified for the corrected design; a provider supporting neither a signed key ID nor a per-connection callback URL is explicitly routed to its own provider-specific design instead (§24.6) rather than forced through a weaker generic path |
| Forged provider callback (inbound) | §24.2/§24.6 — provider-native signature verification wherever the provider supports one; platform-issued shared-secret fallback otherwise; IP allow-listing as defense-in-depth only; verification happens against the connection selected by the opaque route (above), never a payload-asserted one | A provider with genuinely no signing capability and no shared-secret option has a materially weaker guarantee — disclosed explicitly in setup UI copy per §24.2, not silently presented as equally secure |
| Duplicate provider events | `UNIQUE(organization_id, provider_slug, provider_event_id)` DB constraint + `ON CONFLICT DO NOTHING RETURNING id`, with Celery enqueue explicitly gated on a returned row (§24.3, corrected race-safety) | None identified for providers with stable event IDs; content-fingerprint fallback (§24.3, corrected to use pre-normalization verified bytes) has an honest, disclosed limitation for legitimately-identical-but-distinct events |
| Plugin privilege escalation | §25.3/§28.3's layered capability intersection; `fn_activate_plugin`'s DB-enforced `enabled_capabilities ⊆ manifest.capabilities` (5I FIX-06); plugin callout signature now covers method+path+timestamp+body, not body alone (§25.3, corrected) | A plugin's own external HTTP service could misbehave once invoked with valid capability scope — outside the platform's control by definition (external service, §25.1); bounded by rate limit/timeout, not eliminated |
| Workflow silently executing a different plugin version after an installation upgrade | **Corrected P0** — node config pins an explicit `plugin_version_id`, re-checked at every execution, not just `plugin_installation_id` (§30.5, ADR-6J-09); a mismatch fails closed (`PLUGIN_VERSION_PINNED_MISMATCH`) rather than silently running new behavior | None identified for the corrected design; a workflow published before this correction has no recorded pin to check against — flagged as a forward 6I-coordination item (ADR-6J-09's compatibility note), not resolved here |
| Tenant escape (cross-org data access) | RLS `ENABLE + FORCE` on every tenant table (§31); 404-not-403 non-disclosure (6A §7.4); `X-Platform-Tenant-Id` on plugin callouts communicates scope but is explicitly **not** treated as an enforcement boundary by itself (§25.3, corrected) — per-installation credential isolation and rate limiting are the structural guarantees | None identified beyond the platform-wide RLS guarantee's own scope; a plugin's own internal mishandling of `X-Platform-Tenant-Id` is outside the platform's control by definition (external service) and is now documented as such rather than implied to be prevented |
| Secret exposure in logs | 3E §14.1's redaction processor (6A §22), applied without exception (§44.4) | A field the redaction regex doesn't match (e.g. a secret embedded inside a free-text `failure_reason`) is a latent risk — mitigated by §35's normalization discarding raw provider bodies before they ever reach a log line in the first place |
| Idempotency-fingerprint exposure of a low-entropy tenant-supplied credential | **Corrected P1** — `HMAC-SHA256(platform_idempotency_fingerprint_key, ...)` instead of a bare hash (§12.1 rule 5) — an attacker with the fingerprint store cannot brute-force the credential without the platform's own HMAC key | None identified for the corrected design |
| DNS rebinding | §30.3 resolve-then-pin, refreshed on every request (not just at registration); original hostname preserved for TLS SNI/certificate validation, so pinning the IP does not weaken TLS hostname verification | None identified for the egress adapter's own calls |
| TLS hostname mismatch / certificate validation bypass via IP-pinning | §30.3 — the adapter connects to the validated IP but presents and validates against the **original hostname** for TLS, never the IP; certificate validation is never skipped as a side effect of IP-pinning | None identified |
| Redirect abuse (including credential leakage across a cross-origin redirect) | §30.3 — bounded to 3 hops, every hop independently re-validated including fresh DNS resolution; `Authorization`/signing headers/resolved credentials stripped on any cross-origin redirect, never forwarded blindly; webhook delivery never follows any redirect (§22.4, stricter default) | None identified |
| Oversized webhook/provider payloads | §24.4 (1MB inbound cap), §45.2 (256KB outbound payload cap), §30.3 (2MB egress-adapter response cap) | None identified |
| Provider response injection (a provider's response body containing content designed to exploit a naive log/display path) | §12.1 rule 4 / §35 — provider bodies are never passed through raw; truncated previews only, treated as untrusted content throughout | Depends on the truncation/sanitization actually stripping control characters, not just length — an implementation-level requirement, not a design gap |
| Malicious configuration schemas (a plugin manifest's `configuration_schema` or an integration's `configuration` JSON attempting injection) | Configuration values are stored as opaque JSONB and only ever interpolated into outbound HTTP calls via the egress adapter (never into a SQL string, never `eval`'d) — no code path in this document parses configuration as executable | None identified for this document's own handling; a plugin's own external service choosing to `eval` tenant-supplied config is outside the platform's control (§25.1) |

---

## 54. Security Invariants

1. **Secret values are never returned after storage**, except the explicitly-designed one-time-reveal at creation/rotation (§12.1 rule 6, §18.3, §21.3).
2. **Tenant ownership is independently verified on every organization resource** — RLS (§31) plus application-layer re-check, never RLS alone trusted as the only layer for a security-sensitive read.
3. **Webhook signatures are calculated over the raw body** — `f"ts={unix_timestamp}.{payload_json}"` computed over the exact bytes sent, never a re-serialized copy (§21.1); during an active secret-rotation grace window, this holds for **both** emitted signatures identically (§21.1/§21.3).
4. **Signature verification is timestamp-bound** — 5-minute replay window, documented as consumer-MUST, applying identically regardless of which of the (possibly two, during rotation) signatures matched (§21.2).
5. **OAuth state is random, expiring, and single-use** — 256-bit, 10-minute TTL, `fn_redeem_oauth_callback_state`'s DB-enforced single redemption (§13.3, ADR-6J-08) — and is the sole security boundary of the unauthenticated callback hop by design, never supplemented with a client-supplied tenant claim the caller cannot legitimately possess.
6. **Provider callbacks are authenticated/verified whenever provider capabilities allow** — §24.2, never trusted solely because the request reached the endpoint.
7. **User-configurable URLs are SSRF-protected** — the single shared §30.3 egress-control adapter, applied to every tenant-configurable outbound URL in this document without exception.
8. **Plugin permissions cannot exceed granted organization/platform capabilities** — the four-layer intersection in §28.3, DB-enforced at the innermost layer (`fn_activate_plugin`).
9. **Provider failures cannot expose secrets** — §35's normalization strips raw provider bodies before any surface (error response, log, audit) ever sees them.
10. **Webhook consumers must assume at-least-once delivery** — §22.1, explicitly never promised as exactly-once.
11. **Duplicate inbound provider events must not cause duplicate domain side effects** — DB `UNIQUE` constraint + `ON CONFLICT DO NOTHING` is the actual guarantee (§24.3), not an application-layer "check then act" race.
12. **Database state + outbox event commit atomically** — every domain event this document's endpoints produce is inserted into `audit.domain_event_outbox` in the same transaction as the state change (§37.1), never published before commit.
13. **A published workflow's plugin-capability behavior is fully determined by that node's own pinned `plugin_version_id`, never by the installation's current, mutable state** — an upgrade that moves the installation to a different version fails the pinned reference closed (`PLUGIN_VERSION_PINNED_MISMATCH`) rather than silently changing what the workflow executes (§30.5, ADR-6J-09).

---

## 55. Architecture Decision Records

### ADR-6J-01: Direct `app_api` Execution via Widened Grants, Not Internal RPC (REVISED this pass)

**Context:** 5I originally granted `EXECUTE` on `fn_activate_plugin`, `fn_uninstall_plugin`, `fn_upgrade_plugin`, `fn_rotate_integration_credential`, and `fn_replay_webhook_delivery` to `app_worker` only — not `app_api`. The pre-remediation revision of this document proposed a synchronous internal-JWT-authenticated RPC hop from Core API to Worker for exactly these five functions, reasoning that widening the grant "silently reverses a deliberate least-privilege boundary... without documented rationale."

**Revised decision (remediation §12):** on review, that reasoning did not hold up — every one of the five functions already performs its own `organization_id`-scoped `SELECT ... FOR UPDATE` authorization internally (identical to the discipline `fn_create_integration_connection`/`fn_create_plugin_installation` already use while being directly `app_api`-callable since 059-066), so **direct `app_api` execution is exactly as safe as the functions 5I already made `app_api`-callable** — the `app_worker`-only restriction was never protecting anything these five functions' own internal checks don't already cover, and no design record anywhere in 5I documents an actual reason beyond apparent convention. `101_5I1.sql` (§56) therefore widens `EXECUTE` to `app_api` directly for all five (grants only — no function body touched), and the internal-RPC pattern is removed entirely.

**Alternatives considered:** (a) Keep the internal-RPC hop (the original design) — rejected on review as unnecessary architectural complexity manufactured to work around a grant restriction that itself had no documented security rationale; introduces a network hop, a dependency on the central internal token issuer for operations that don't need it, and a maintenance burden (two execution paths — direct for some functions, RPC for others — for functions that are otherwise identical in shape). (b) Route these operations through Celery as genuine async jobs (`202` + poll) — rejected as unnecessary latency/complexity for an operation that completes in single-digit milliseconds with no external I/O; would also require inventing job-tracking state for operations with no natural job resource (mirrors §15's honest disclosure that connection *sync* genuinely does need this, but these five do not).

**Consequences:** five `GRANT EXECUTE ... TO app_api` statements (§56, `101_5I1.sql`) replace the internal-RPC design across §11.7, §23.3, §27.5, §27.6, §27.7, §29.4. No Application Service code needs to hold or route through a second DB execution context.

**Security implications:** identical security posture to the pre-existing `app_api`-grantable functions in 059-066 — tenant isolation is enforced by the function body's own `organization_id`-scoped lock and check, not by which role is permitted to call it. Removing the internal-RPC hop also removes a code path that previously had to be trusted to correctly propagate `on_behalf_of_organization_id` — one fewer place tenant context could be mis-threaded.

**Compatibility implications:** none — purely an Application Service/grant implementation detail, invisible to any API client; the five endpoints' HTTP contracts (still synchronous, Tier B) are unchanged by this revision.

### ADR-6J-02: `DELETE /webhook-endpoints/{id}` Maps to Soft-Disable, Not Hard Delete

**Context:** `app_api` has no `DELETE` grant on `webhook_endpoints` (5I §28); only `app_platform_admin` does.

**Decision:** the tenant-facing `DELETE` HTTP verb transitions `status → 'DISABLED'` (identical effect to §18.8's explicit disable action) rather than 404/500ing or silently no-op'ing.

**Alternatives considered:** (a) Disallow `DELETE` entirely (405), forcing tenants to always use `POST .../disable` — rejected as needlessly surprising given `DELETE` is a conventional, expected verb here and 6A §7.6 explicitly sanctions "DELETE maps to the aggregate's own terminal-ish transition" for exactly this shape of resource. (b) Grant `app_api` `DELETE` and hard-delete — rejected, loses delivery-history/audit traceability for a resource whose deliveries (§17.1) are meant to be immutable historical records, and reverses a 5I grant decision without authority to do so.

**Consequences:** hard physical deletion remains a platform-admin/compliance-only operation (§42.2).

**Security implications:** none negative — disabling is strictly safer than hard-deleting for a resource whose past deliveries are audit-relevant.

**Compatibility implications:** none — `DELETE` still returns `204` as clients expect.

### ADR-6J-03: 6J Owns the Generic Inbound-Webhook Mechanism; Domain Contexts Own Their Own Callback Endpoints

**Context:** 6D already writes Exotel callbacks into `webhooks.inbound_webhook_events` via its own dedicated endpoint, explicitly stating this is "a statement of how Voice's telephony callbacks fit inside" the shared mechanism, not a redesign of it (6D §10.4).

**Decision:** 6J formally confirms and generalizes this pattern: 6J owns the table, the dedup key shape, the verification discipline, and the status lifecycle (§24) as a **shared capability**; any bounded context whose external provider naturally belongs to its own domain (6D/telephony) implements its **own** dedicated endpoint reusing that shared capability; 6J's own `POST /integrations/providers/{slug}/callback` (§24.6) is the **default/fallback** path for providers not already owned by another context (generic CRM/payment/messaging integrations).

**Alternatives considered:** (a) 6J owns every inbound provider endpoint, including telephony — rejected, would contradict 6D's own already-frozen design and duplicate Exotel-specific ACL logic 6D already owns. (b) Every bounded context builds its own independent inbound-webhook table — rejected, would fragment the dedup/verification discipline five ways for no benefit, and contradicts 5I's single-schema design.

**Consequences:** a future domain context (e.g., 6H for a payment-provider-triggered campaign event) has a clear default answer — reuse 6J's generic endpoint unless it has a specific reason (like 6D's) to own its own.

**Security implications:** consistent verification/dedup discipline platform-wide, not context-by-context reinvention.

**Compatibility implications:** none — 6D's existing design is unaffected.

### ADR-6J-04: No `409 INTEGRATION_IN_USE`/`PLUGIN_IN_USE` — Fail-Closed-at-Execution Instead

Restated in full at §42.5. **Decision:** disconnect/uninstall are never blocked by a dependent-workflow reference; the dependent reference fails closed at its own next execution instead. **Alternatives:** block with a dependency-conflict `409` (rejected — worse UX for a security-relevant self-service action; would also require 6J to query into `workflow.*` tables it does not own, violating §7.2's boundary). **Consequences:** a tenant must separately notice and fix a broken workflow reference after disconnecting/uninstalling; §36's audit trail and 6I's own execution-failure observability (6I §32) are the discovery mechanism. **Security implications:** favors the tenant's ability to immediately revoke a compromised integration/plugin over preventing an accidental workflow breakage — judged the correct tradeoff for a security-sensitive action. **Compatibility implications:** none.

### ADR-6J-05: Workflow Node Credential References — Three Closed Shapes, Never a Raw Secret

**Context:** 6I §23.2/§46 requires a credential-reference type for `WEBHOOK`/`API_CALL` node config that never places a raw secret in `graph_json`.

**Decision:** exactly three reference shapes (§30.2) — `plugin_installation` capability reference, `integration_connection` capability reference, or `none` (unauthenticated). No fourth "inline credential" shape is ever accepted by node config validation (6I's own publish-time reference-validation gate, 6I §14, is where this is enforced — 6J supplies the resolver, 6I supplies the validation gate call site).

**Alternatives considered:** allowing a workflow to declare its own standalone credential (a `WorkflowCredential` resource) — rejected as scope creep duplicating `IntegrationConnection`/`PluginInstallation`'s existing credential-management surface (including their own rotation/security posture, §12) for no added capability.

**Consequences:** every workflow-node credential need is satisfiable exclusively through resources this document already secures end-to-end; 6I never needs its own credential-security design.

**Security implications:** no new secret-storage surface; capability-gating (§28.3) is reused instead of duplicated.

**Compatibility implications:** if 6I later needs a credential shape this document doesn't support (e.g., a workflow-scoped one-off credential with no persistent connection), that is a new joint decision, not silently added here.

### ADR-6J-06: One Shared Egress-Control Adapter, Not N Bespoke SSRF Implementations

**Context:** webhook delivery, plugin callout, integration test/sync, and 6I's `WEBHOOK`/`API_CALL` node execution all make outbound calls to tenant/developer-configured URLs and independently need SSRF protection.

**Decision:** exactly one egress-control adapter (§30.3), implemented once, imported as a shared library by every call site listed above — never four/five independently-maintained SSRF implementations that could drift out of sync with each other over time.

**Alternatives considered:** letting each bounded context implement its own SSRF checks against this document's stated rules — rejected as an near-certain source of future drift (one call site patched for a new bypass technique, others forgotten) for a control class where drift is a security incident, not a cosmetic inconsistency.

**Consequences:** a single point of ownership/testing/patching for this platform's entire SSRF posture; 6I's runtime imports 6J's adapter as a dependency rather than 6J calling into 6I.

**Security implications:** directly closes the exact risk class §26/§27 of the task brief exist to prevent.

**Compatibility implications:** any future change to SSRF policy (e.g., an enterprise private-network allow-list, §57 Decision J2) is made once and takes effect everywhere simultaneously.

### ADR-6J-07: Dual-Signature Webhook Secret Rotation, Not Retain-Without-Signing (NEW — remediation §6, P0)

**Context:** the pre-remediation design retained the old signing secret in the secret manager for a 60-minute window after rotation but only ever signed outbound deliveries with the *new* secret — meaning a consumer whose verification code was still deployed with the old secret would reject every delivery during the "grace" window, providing no actual grace at all. This was a genuine cryptographic defect, not a documentation gap.

**Decision:** `webhook_endpoints` gains two new columns (`previous_signing_secret_ref`, `previous_secret_expires_at`, §56/`101_5I1.sql`). During the grace window, the delivery worker signs every outbound delivery **with both** the current and the (unexpired) previous secret, emitting two signature values so a consumer holding either secret validates successfully — see §21.1/§21.3 for the corrected wire format.

**Alternatives considered:** (a) A delayed-activation cutover (new secret takes effect only after the grace window, old secret keeps signing until then) — rejected as strictly worse: it delays the *new* secret's protection taking effect at all, whereas dual-signing lets the new secret protect immediately while still accepting the old one, which is the actual security-vs-availability tradeoff a rotation grace period should make. (b) Keep single-signature rotation but require the tenant to update their verification code atomically at rotation time — rejected as operationally unrealistic (this is exactly the "instant cutover breaks in-flight consumer deployments" problem grace periods exist to solve).

**Consequences:** the delivery worker's signing code computes two HMACs per delivery during any active grace window (negligible CPU cost); `previous_signing_secret_ref`'s underlying secret-manager entry must be purged by the Application Service once `previous_secret_expires_at` passes (documented in the migration, not DB-scheduled — §41's established no-pg_cron pattern).

**Security implications:** closes the P0 defect directly — a rotation now provides a real, working grace period. The grace window is capped at 24 hours (`p_grace_period_seconds` DB CHECK, `101_5I1.sql`) to bound how long two live secrets are simultaneously valid.

**Compatibility implications:** the wire format gains a second, clearly-versioned signature header (§21.1) — additive per 6A §31.1's own rule ("adding a new optional response field"/header is non-breaking); a consumer that only checks `X-Platform-Signature` is unaffected.

### ADR-6J-08: OAuth Callback Redemption Takes `state` Alone, Never `organization_id` as Input (NEW — remediation §4, P0)

**Context:** the pre-remediation design called `fn_redeem_oauth_attempt(state, organization_id)` from the unauthenticated browser-callback endpoint — but that endpoint has no tenant context to supply `organization_id` with, a genuine circular dependency, not a documentation gap.

**Decision:** `fn_redeem_oauth_callback_state(state)` (§56/`101_5I1.sql`) takes `state` alone and returns `organization_id` (plus `definition_id`, `connection_id`, `code_verifier`, `redirect_uri`, `requested_scopes`) as output. `state` itself — 256-bit, `UNIQUE`, single-use, 10-minute TTL — is the actual security boundary, exactly like a password-reset token; requiring `organization_id` as well added no security value the unguessable, single-use `state` didn't already provide, while making the function impossible to call from its actual caller.

**Alternatives considered:** (a) Remove RLS from `oauth_attempts` (mirroring `identity.sessions`/`identity.password_reset_tokens`'s no-RLS pattern) — considered and rejected as unnecessary: `fn_redeem_oauth_callback_state()` is `SECURITY DEFINER`, owned by `app_migration` (confirmed `BYPASSRLS` — `001_5B.sql`, reconfirmed live in `077_5J1_VALIDATION_REPORT.md` line 309), so RLS was never actually blocking the function's internal queries regardless of the table's own RLS policy; stripping RLS from the table would have been a larger, unnecessary architectural change for a problem the function's own execution context already solves. (b) Have the client somehow pre-supply `organization_id` at the callback step — rejected outright: this is precisely the "let the client assert an arbitrary tenant" trust violation 6B §9.2 forbids.

**Consequences:** `fn_redeem_oauth_attempt(state, organization_id)` (059-066) is left in place, unused by this flow, for any future caller that already holds tenant context.

**Security implications:** closes the P0 tenant-bootstrap defect; preserves every existing CSRF/replay/expiry guarantee (§13.3) unchanged, since the fix only changes which value is an input vs. an output — the underlying single-use, row-locked redemption logic is otherwise identical.

**Compatibility implications:** none — this is a new function; no existing caller of `fn_redeem_oauth_attempt` is affected.

### ADR-6J-09: Workflow Plugin References Pin an Explicit `plugin_version_id`, Not Just `plugin_installation_id` (NEW — remediation §7, P0)

**Context:** the pre-remediation design stored only `plugin_installation_id` in a workflow's plugin-capability node config, reasoning that upgrade forcing the installation out of `ACTIVE` (§29.4) would fail-close any reference until the tenant re-activated. That protects only the window between upgrade and reactivation — once reactivated (now against the new version), a workflow referencing only the installation ID would silently resume running against different behavior, which is exactly the "a published workflow cannot silently begin executing materially different plugin behavior" failure mode this document is required to prevent.

**Decision:** node config stores `plugin_installation_id` **and** `plugin_version_id` (§30.2, mandatory). 6I's publish gate and every execution both re-verify `installation.plugin_version_id = <the pinned value>` in addition to org/active/capability checks (§30.5) — an upgrade silently breaks the pin (fails closed with `PLUGIN_VERSION_PINNED_MISMATCH`) rather than silently continuing under new behavior; the tenant must explicitly republish to re-pin.

**Alternatives considered:** (a) Reject plugin upgrades outright while any published workflow references the installation — rejected as requiring 6J to query into `workflow.*` tables it does not own (violating §7.2's boundary), and as a worse UX than "upgrade succeeds, dependent workflows need an explicit, visible republish" (consistent with ADR-6J-04's disconnect/uninstall reasoning). (b) Auto-migrate referencing workflows to the new version on upgrade — rejected as itself a silent behavior change, the opposite of what's required here.

**Consequences:** every plugin-capability workflow node's config grows one additional mandatory field; 6I's publish/execution validation gains one additional equality check, entirely within logic 6I already owns (6I supplies the call site, 6J supplies the fact being checked, per §30.4's existing division).

**Security/correctness implications:** closes the P0 non-determinism defect directly — a published workflow's behavior at any given plugin-capability node is now fully determined by the node's own config, never by the installation's current, mutable state.

**Compatibility implications:** any workflow published before this ADR under the old (installation-ID-only) shape has no recorded `plugin_version_id` to check against — out of scope for this document to migrate (6I-owned data); flagged as a forward coordination item with 6I, not resolved here.

### ADR-6J-10: Generic Inbound Callback Uses an Opaque Per-Connection Routing Segment, Not Payload-Derived Tenant Inference (NEW — remediation §9, P0)

**Context:** the pre-remediation design for `POST /integrations/providers/{provider_slug}/callback` resolved the target tenant from "an external account identifier embedded in the payload" — an unverified body field used to select which tenant's credential/secret governs signature verification, a confused-deputy risk: trusting routing information before any signature has been checked is backwards.

**Decision:** §24.6 now requires an opaque, non-secret, per-connection routing segment in the callback **path** (`/providers/{provider_slug}/callbacks/{opaque_connection_route_id}`) wherever the provider's own webhook-configuration UI allows a per-connection callback URL — the route segment alone (not a body field) selects the candidate `IntegrationConnection` and therefore which credential/public key to verify against; the payload is trusted only **after** that connection's own verification method succeeds against it.

**Alternatives considered:** trusting a signed header's key-ID/account-ID where the provider supports one (kept as the *preferred* mechanism where available, §24.2/§24.6) — the opaque-route-segment fallback exists for providers that support neither a per-connection callback URL's own path segment nor a signed key identifier; a provider supporting neither is flagged as requiring its own provider-specific callback design rather than being forced through the generic route with a weaker guarantee (§24.6).

**Consequences:** connection setup UI must surface the opaque per-connection callback URL to the tenant for the provider's own webhook-configuration screen, for every provider using the generic route.

**Security implications:** closes the confused-deputy/cross-tenant-routing risk directly — no unverified payload field ever selects which tenant's secret is used to verify that same payload.

**Compatibility implications:** none — this document had not previously specified a concrete inbound callback URL shape in enough detail for any implementation to exist yet.

### ADR-6J-11: SECURITY DEFINER Tenant-Forgery Guard on Every `p_organization_id`-Taking Function (NEW — second remediation pass, P0)

**Context:** every mutating function in this document is `SECURITY DEFINER`, owned by `BYPASSRLS`-attributed `app_migration` (confirmed live, §60). RLS therefore does not govern these functions' own internal queries. A function trusting its `p_organization_id` parameter unconditionally would let a caller authenticated as one tenant mutate another tenant's data by simply passing a different UUID — independent of, and not mitigated by, RLS being correctly configured on the underlying tables.

**Decision:** every `app_api`-callable, `p_organization_id`-taking function requires `organization.current_tenant_id() = p_organization_id`, fail-closed on unset context, as its first check (§31.1 for the full mechanism and the three-class exemption table). Applied via `CREATE OR REPLACE`, same signature, to 8 pre-existing (059-066) functions in addition to every new function this document introduces — including two (`fn_create_integration_connection`, `fn_create_plugin_installation`) that were already `app_api`-callable before this remediation pass and shared the identical defect class, exposed by this review rather than introduced by it.

**Alternatives considered:** (a) Rely on RLS alone — rejected, demonstrated not to apply inside these functions' own execution context (BYPASSRLS ownership). (b) Trust the Application Service layer to never pass a mismatched `p_organization_id` — rejected as the exact "trust the caller" assumption this finding demonstrates is insufficient defense-in-depth for a security boundary. (c) Remove `p_organization_id` as a parameter entirely, deriving it solely from `organization.current_tenant_id()` inside the function — rejected: several functions (notably OAuth-adjacent flows and any future auditing/debugging tooling) benefit from an explicit, loggable parameter the caller states its intent with, and the guard achieves the same safety with less signature churn against the already-published (§48) endpoint contracts.

**Consequences:** no legitimate caller's behavior changes (the Application Service was already expected to set `app.tenant_id` correctly and pass a matching `p_organization_id`); a compromised or buggy caller is now rejected at the DB layer instead of silently succeeding.

**Security implications:** closes a P0 that would otherwise have allowed complete cross-tenant data mutation via any of ~20 functions, independent of any other control in this document. Live-proven via an 11-test adversarial matrix (§60) with zero forged mutations succeeding.

**Compatibility implications:** none for any correctly-behaving caller; a caller that was (incorrectly) passing a mismatched `p_organization_id` — which should never have been possible in a correct implementation — now receives an explicit exception instead of a silent cross-tenant write.

### ADR-6J-12: OAuth State Bound to Its Issuing Provider Before Consumption (NEW — second remediation pass, P0)

**Context:** the first-pass `fn_redeem_oauth_callback_state(state)` verified only that `state` exists, is `PENDING`, and is unexpired — never that the route the caller arrived through matches the provider/definition the attempt was actually created for. A `state` issued for Provider A, presented at Provider B's callback route (captured, leaked, or misdirected redirect), would have redeemed successfully and returned Provider A's `organization_id` to Provider B's handler.

**Decision:** `fn_redeem_oauth_callback_state`/`fn_fail_oauth_callback_state` both now require `p_expected_definition_id`, verified against the row's own `definition_id` **before** any status mutation — a mismatch raises without consuming `state`, leaving it redeemable later through the correct route (§13.3/§13.5).

**Alternatives considered:** encoding the provider identity into `state` itself (e.g., a provider-prefixed token) — rejected as weaker: it conflates a routing convenience with the actual security check, and a caller could still construct a same-prefix mismatched request; an explicit, DB-verified equality check is unambiguous and cannot be spoofed by state-string construction.

**Consequences:** the Provider Adapter must resolve its own `{definition_key}` (from the callback URL path) to a `definition_id` and pass it explicitly — a small, already-necessary lookup (the adapter already needs the definition to know how to talk to that provider at all).

**Security implications:** closes a cross-provider confusion risk. Live-proven (§60, OA-4/OA-5): a wrong-provider attempt against a real, valid `state` was rejected and the row remained `PENDING`; the same `state` then successfully redeemed through the correct provider route immediately after.

**Compatibility implications:** none — this document had not previously specified enough detail for any implementation of the single-parameter version to exist.

### ADR-6J-13: OAuth Post-Redemption Failure Is a Separate Function From Pre-Redemption Denial (NEW — second remediation pass, P0)

**Context:** the first-pass `fn_fail_oauth_callback_state` explicitly rejected an attempt already in `REDEEMED` status, while the accompanying prose claimed it also handled "token exchange failure after successful redemption" — a direct self-contradiction found on independent review (both statements cannot be true of the same function).

**Decision:** `fn_fail_oauth_callback_state` is scoped exclusively to pre-redemption denial (`PENDING → FAILED`). A new function, `fn_record_oauth_exchange_failure(state, reason)`, handles the post-redemption case: requires `status = 'REDEEMED'` exactly, records a new `exchange_failed_at` timestamp plus `failure_reason`, and leaves `status` unchanged at `REDEEMED` — the single-use replay-safety guarantee is untouched, since no state value is ever reopened for reuse.

**Alternatives considered:** adding a new terminal `status` value (e.g. `EXCHANGE_FAILED`) — rejected as unnecessary schema churn; `REDEEMED` already correctly means "this state is consumed, permanently," and the *outcome* of what happened after consumption is better modeled as an annotation (a nullable timestamp + reason) than as a competing terminal state that would need its own guard interactions with every other function touching `oauth_attempts`.

**Consequences:** one new column (`exchange_failed_at`), one new function, `EXECUTE`-granted identically to the other two OAuth callback bootstrap functions (`app_api, app_platform_admin`, no `app_worker` — least privilege, remediation §7).

**Security implications:** none negative; closes a logical gap that would otherwise have left a genuine failure mode (provider token endpoint down/erroring) with no durable, correct representation.

**Compatibility implications:** none — new function, no existing caller affected.

### ADR-6J-14: `gen_uuid_v7()` Search-Path Fix — Platform-Wide, Out of 6J's Original Scope, Fixed as a Hard Prerequisite (NEW — live-discovered during second-pass validation)

**Context:** live testing of this document's own new functions immediately failed on the first real `INSERT` with `function gen_random_bytes(integer) does not exist`. Root-caused to `public.gen_uuid_v7()` (`001_5B.sql`) having no `SET search_path` of its own; its call to the unqualified `gen_random_bytes()` (installed by `pgcrypto` into `public`) fails whenever it executes nested inside a `SECURITY DEFINER` function whose own search_path excludes `public` — confirmed live to affect **84 of the 99** `SECURITY DEFINER` functions across the **entire 001-100 baseline**, not merely this document's own schemas. This is a pre-existing defect in the frozen baseline, reproduced via a minimal repro using the exact unmodified `061_5I.sql` search_path pattern — not introduced by any change in this document.

**Decision:** `CREATE OR REPLACE FUNCTION public.gen_uuid_v7() ... SET search_path = public, pg_catalog`, added to `101_5I1.sql` even though `gen_uuid_v7()` itself is owned by no particular phase's schema, because fixing it is a hard, unavoidable prerequisite for this document's own new functions to work at all, and the fix is minimal, additive, and carries no privilege implications (the function is not `SECURITY DEFINER`).

**Alternatives considered:** (a) Work around it locally by adding `public` to every one of this document's own function search_paths — rejected: this would fix only 6J's own ~20 functions, leaving the other 64+ affected functions across the rest of the platform silently broken, when the true fix is a single one-line change to the shared root cause. (b) Leave it undiscovered/unfixed and mark 6J's own functions as blocked pending a separate future migration — rejected: the defect was already found; disclosing it without fixing the trivially-fixable root cause would be a worse outcome for the platform than fixing it here with full disclosure of the broader, un-audited blast radius.

**Consequences:** every one of the 84 affected functions platform-wide is transitively fixed by this one change. A full audit of which of the other 83 (outside `integrations`/`plugins`/`webhooks`) actually exercise the broken path in practice is explicitly **out of scope** for this migration and is recorded as a forward finding for the owning phases (§56, §62).

**Security implications:** none negative (no privilege change); closes a correctness defect that would otherwise silently break any write path across the platform relying on `gen_uuid_v7()` from inside a restrictively-scoped `SECURITY DEFINER` function.

**Compatibility implications:** none — strictly additive fix to a function's internal name resolution, no signature or behavior change for any caller whose search_path already included `public` (the majority of ordinary, non-restricted call sites).

---

## 56. Phase 5 Schema Gaps

| ID | Severity | Gap | Affected endpoints | Status / remediation |
|---|---|---|---|---|
| **DEP-6J-01** | **P0 — RESOLVED, LIVE-VALIDATED** | Originally: no SECURITY DEFINER function transitioned `integration_connections.status` `CONNECTING → ACTIVE`, `ACTIVE ⇄ DEGRADED`, or any status `→ DISCONNECTED`. | §11.2 (completion half), §11.4, §11.6, §11.7 (status half), §15.3 (result-write half) | Closed by `5K/migrations/101_5I1.sql` (§8.6): `fn_activate_integration_connection`, `fn_fail_integration_connection`, `fn_degrade_integration_connection`, `fn_disconnect_integration_connection`, `fn_update_integration_connection_config`, `fn_record_integration_sync_result` — each additionally hardened with the tenant-forgery guard (§31.1, ADR-6J-11). **Live-validated** (PostgreSQL 18.6): fresh + incremental migration PASS, full integration-connection lifecycle matrix PASS (legal/illegal/idempotent transitions, terminal-guard re-confirmed) — `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §10. |
| **DEP-6J-02** | **P0 — RESOLVED, LIVE-VALIDATED** | Originally: no function suspended/reactivated a `plugin_installations` row, and no function updated `configuration`/`credential_ref` in place. | §27.4, §27.4a, §27.6 | Closed by `101_5I1.sql` (§27.1): `fn_suspend_plugin_installation`, `fn_reactivate_plugin_installation`, `fn_update_plugin_installation_config`, `fn_rotate_plugin_installation_credential` — tenant-forgery-guarded. **Live-validated**: full plugin lifecycle matrix PASS, including live-proven capability preservation across suspend→reactivate and capability reset+re-pin across version upgrade — validation report §11. |
| DEP-6J-03 | P2, still open | `integration_connections.external_account_ref` has no DB-level uniqueness constraint per `(definition_id, external_account_ref)` — two connections (across different orgs, or theoretically the same org after a disconnect/reconnect cycle) could reference the same external account without the DB objecting | §11.2 | Non-blocking; `idx_ic_ext_account` already supports an application-layer duplicate-check query; a DB constraint is a future hardening, not required for V1 correctness |
| **DEP-6J-04** | **RESOLVED, LIVE-VALIDATED** | Originally: `oauth_attempts` had no `connection_id` column — correlation was inferred via `(organization_id, definition_id)`. | §13.2 | Closed by `101_5I1.sql`: `oauth_attempts.connection_id` (nullable FK to `integration_connections`), populated at `INSERT` time. Correlation is now explicit, remaining correct even if Decision J1 (§57) later allows multiple connections per provider. Column presence and population confirmed live throughout the OAuth test matrix (validation report §9). |
| **DEP-6J-05** | **RESOLVED, LIVE-VALIDATED (was P0-adjacent — folded into the OAuth-callback tenant-bootstrap fix, then further split by ADR-6J-13)** | Originally: no function marked an `oauth_attempts` row `FAILED` on provider-denied authorization, and (more severely) the redemption path itself had a P0 tenant-bootstrap circular dependency (first-pass remediation §4), further found to have a P0 provider-binding gap and a P0 state-machine contradiction (second-pass remediation §5-§6). | §13.3, §13.5, §13.5a | Closed by `101_5I1.sql`: `fn_redeem_oauth_callback_state(state, expected_definition_id)`, `fn_fail_oauth_callback_state(state, expected_definition_id, reason)`, and the new `fn_record_oauth_exchange_failure(state, reason)` (§13.3/§13.5/§13.5a, ADR-6J-08/6J-12/6J-13). **Live-validated**: 14/14 OAuth test matrix — validation report §9. |
| **DEP-6J-06** | **P1, still open** | No `IntegrationSyncJob`/`IntegrationSyncCursor` table exists — sync history, resumable cursors, per-item conflict/partial-failure reporting are all unimplementable; only `last_sync_at`/`last_sync_error` on the connection itself persist | §15 (entire synchronization model) | Deliberately **not** addressed by `101_5I1.sql` (out of the remediation's named P0/P1 scope) — a future migration adding `integrations.integration_sync_jobs (id, organization_id, connection_id, status, cursor JSONB, items_processed, items_failed, error_summary, started_at, completed_at)` plus `GET .../syncs`/`GET .../syncs/{sync_id}` endpoints this document explicitly declines to fabricate today |
| DEP-6J-07 | Non-blocking, still open | No auto-suspend function/trigger exists for a `webhook_endpoint` whose deliveries are chronically `DEAD_LETTER` — `SUSPENDED` status exists but is system-driven-only by design (4F §8.1) and nothing drives it | §22.5 | A future migration or Celery-side policy (not necessarily DB-level) implementing the 20-consecutive-dead-letter threshold this document proposes as a default |
| DEP-6J-08 | Non-blocking, still open | `integration_definitions` has no `category`, `configuration_schema`, or `feature_maturity` column — these are presented in §9's response examples as **application-layer metadata** (a config file/admin-tool-managed overlay, not a DB column), consistent with the executed DDL's actual, narrower column set (`slug, name, description, auth_type, capabilities, required_scopes, manifest_version, documentation_url, is_active`) | §9.1, §9.2 | Non-blocking — this document's response contract is achievable entirely at the application layer; flagged so implementers don't search for a non-existent DB column |
| **DEP-6J-09** | **RESOLVED, LIVE-VALIDATED** | Originally: `fn_create_integration_connection()` did not itself check `integration_definitions.is_active`. | §11.2, §43.1 | Closed by `101_5I1.sql`'s `CREATE OR REPLACE` on `fn_create_integration_connection()` (same signature, added `is_active` check plus the tenant-forgery guard, ADR-6J-11). Live-validated as part of the tenant-forgery matrix, test 1 (validation report §8). |
| **DEP-6J-10** (new, second pass) | **P0 — RESOLVED, LIVE-VALIDATED** | `SECURITY DEFINER` tenant-forgery: every `app_api`-callable, `p_organization_id`-taking function (new and 8 pre-existing 059-066 functions alike) trusted its parameter unconditionally, with RLS not applicable inside a `BYPASSRLS`-owned function's own queries. | Every endpoint in §48 backed by a tenant-bound guarded function | Closed by `101_5I1.sql`'s tenant-forgery guard, ADR-6J-11, §31.1. **Live-validated**: 11-test adversarial matrix, zero forged mutations succeeded — validation report §8. |
| **DEP-6J-11** (new, second pass) | **Was P0-equivalent — RESOLVED, LIVE-VALIDATED, platform-wide impact beyond 6J** | `public.gen_uuid_v7()` (`001_5B.sql`, pre-existing, not a 6J defect) has no fixed `search_path`, breaking inside 84 of 99 `SECURITY DEFINER` functions platform-wide whenever their own search_path excludes `public`. Live-discovered blocking 6J's own functional writes. | All of §48 (was blocking every write path) | Closed by `101_5I1.sql`'s `CREATE OR REPLACE FUNCTION public.gen_uuid_v7() ... SET search_path = public, pg_catalog` (ADR-6J-14). **Live-validated** for `integrations`/`plugins`/`webhooks`. **A full audit of the other 83 affected functions outside these three schemas is explicitly out of scope for this document** — forward finding for the owning phases (5B-5H, 5J). |
| **DEP-6J-12** (new, second pass) | **Cross-phase coordination item, disclosed, not resolved** | 6I §11's frozen `WebhookNodeConfig`/`ApiCallNodeConfig` do not define the `plugin_installation_id`/`plugin_version_id`/`credential_source` fields §30.2's design targets. | §30.2, §30.5 | **Not resolvable by 6J** — 6I is `APPROVED/FROZEN`, amending its schema is outside this document's authority. 6J supplies the target contract; a small, controlled future 6I amendment must implement it. Does not block any other endpoint in §48. |

No table, column, or function name anywhere in this document is invented and presented as already existing — every reference above either cites the exact 5I/`101_5I1` migration/function or is explicitly listed here as absent. **Live validation status (PostgreSQL 18.6, not the requested 16 — disclosed engine-version deviation) for every "LIVE-VALIDATED" row above:** `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`, full raw evidence in `5K/execution_logs/` (14 files, prefix `20260829T210000Z_`).

---

## 57. Owner Decisions Required

### Decision J1

**Question:** Should V1 continue restricting a tenant to exactly one non-terminal `IntegrationConnection` per provider (§8.2), or should multiple simultaneous connections to the same provider be allowed (e.g., two Salesforce orgs for one platform tenant)?

**Why it matters:** this is 5I's own still-open `ODD-5I-01`/`OQ-4F-07` (Product-owned, explicitly deferred there) — 6J inherits it rather than resolving it, since relaxing it requires a Phase 5 migration removing/relaxing `fn_create_integration_connection()`'s `SELECT FOR UPDATE` uniqueness check, which is out of 6J's authority.

**Option A — Keep single-connection (current default):**
Pros: simpler mental model, simpler credential/health tracking, no ambiguity in `oauth_attempts` correlation (resolves DEP-6J-04 as a non-issue).
Cons: blocks a real enterprise use case (multi-org/multi-instance same-provider connections) some tenants will eventually request.

**Option B — Allow multiple connections per provider:**
Pros: matches real-world enterprise topology for some providers.
Cons: requires a Phase 5 migration; requires `oauth_attempts` to gain an explicit connection-correlation column (closing DEP-6J-04 for real, not just by inference); every "the connection" reference throughout this document (e.g., a workflow node's `credential_source`) already handles this correctly since it references a specific `connection_id`, not "the provider," so the API surface itself needs no redesign — only the uniqueness constraint and OAuth correlation need to change.

**Recommended technical default:** Option A (V1 default already assumed throughout this document).

**Can 6J proceed before this decision?** Yes — this document is fully self-consistent under Option A and requires no rework if Option B is chosen later (only a Phase 5 migration + the two DEP-6J-04-related additions above).

### Decision J2

**Question:** Should an enterprise tenant ever be allowed to configure a private-network/RFC1918 egress allow-list for webhook/plugin/workflow-node URLs (§30.3), for legitimate on-prem integration use cases?

**Why it matters:** affects security posture platform-wide (§30.3's SSRF control is currently unconditional) and is explicitly named as a possible future need by the governing task brief itself ("unless private IP ranges are explicitly enterprise-approved").

**Option A — Never allow (V1 default):**
Pros: simplest, safest; zero SSRF surface into any tenant's or the platform's own internal network.
Cons: blocks legitimate on-prem/VPN-connected enterprise integrations some large customers will eventually need.

**Option B — Admin-approved, per-tenant allow-list:**
Pros: unlocks enterprise on-prem use cases.
Cons: meaningfully expands the SSRF threat surface (a compromised tenant admin account could allow-list an internal target); requires a new tenant-configuration resource and review workflow not designed anywhere in this document.

**Recommended technical default:** Option A for V1 (already assumed throughout §30.3).

**Can 6J proceed before this decision?** Yes — §30.3's adapter is written to unconditionally reject private ranges in V1; adding an allow-list later is additive to the adapter's own logic, not a breaking change to any endpoint contract in this document.

### Decision J3

**Question:** Should the platform ever support a public, third-party, self-service plugin marketplace (external developers submitting/publishing plugins without a bespoke partner relationship)?

**Why it matters:** major product-scope and business-model decision; affects review-workflow investment, developer-facing tooling, and the trust model §25 currently assumes ("platform-reviewed" implies a controlled, non-self-service review queue in V1).

**Option A — Platform/partner-only registration (current default):**
Pros: matches the current, controlled trust model exactly; no new tenant-facing publishing API needed.
Cons: limits the integration catalog's growth rate to what the platform team/partners build directly.

**Option B — Self-service developer portal with review queue:**
Pros: scales the plugin catalog via a developer ecosystem.
Cons: needs a whole new API surface (developer accounts, submission/review workflow, versioning UX for external developers) not designed anywhere in Phase 1–6; needs a KYC/verification decision (5I's own `ODD-5I-06`, already deferred to "Phase 9").

**Recommended technical default:** Option A (already assumed throughout §26).

**Can 6J proceed before this decision?** Yes — §26.1 already explicitly discloses "no public third-party marketplace / self-service publisher flow in V1" as the assumed default; Option B would be an entirely additive future document, not a rework of this one.

### Decision J4

**Question:** Should integration/plugin/webhook usage be a billable metric in V1, or included in every plan tier at no separate charge?

**Why it matters:** pricing/business-model decision; determines whether 6K needs to design metering for this domain at all, and on what timeline.

**Option A — Not billed in V1 (included in plan):**
Pros: simpler GTM, no metering engineering needed yet.
Cons: no cost-recovery lever if a small number of tenants drive disproportionate provider-API/plugin-execution cost.

**Option B — Metered, billed per-operation:**
Pros: cost-aligned pricing.
Cons: requires 6K to design the metering/billing semantics (§46.2 explicitly out of 6J's scope) before this could ship.

**Recommended technical default:** Option A for V1 — the raw facts (§46.1) are already durable regardless of which option is chosen, so no data is lost by deferring.

**Can 6J proceed before this decision?** Yes — §46 already documents this as a forward dependency on 6K, not something 6J's own endpoint contracts depend on either way.

---

## 58. Implementation Readiness Checklist

- [x] Every endpoint has auth requirements (§48–§49).
- [x] Every endpoint has organization scoping (§31, §49).
- [x] Every mutating endpoint has permission mapping (§32, §48–§49).
- [x] Every mutating endpoint defines idempotency applicability (§33).
- [x] Every resource has lifecycle rules (§8.6, §17–§18, §27.1).
- [x] Integration credentials cannot leak (§12).
- [x] OAuth state handling is specified (§13.2–§13.3).
- [x] OAuth refresh/revocation behavior is specified (§13.6, §12.4).
- [x] Webhook signing is fully specified (§21.1–§21.2).
- [x] Webhook replay protection is specified (§21.2 rule 2, §23.3).
- [x] Webhook delivery is explicitly at-least-once (§22.1).
- [x] Retry/backoff behavior is specified (§22.3).
- [x] Delivery replay semantics are specified (§23.3).
- [x] Inbound provider callback verification is defined (§24.2).
- [x] Provider event deduplication is defined (§24.3).
- [x] SSRF is addressed (§30.3).
- [x] DNS rebinding is addressed (§30.3 resolve-then-pin).
- [x] Redirect safety is addressed (§30.3, §22.4).
- [x] Plugin permissions use least privilege (§28.3).
- [x] Plugins cannot bypass RBAC (§28.2–§28.3).
- [x] Workflow/plugin ownership boundary is clear (§7.2, §30).
- [x] 6J does not duplicate 6I workflow execution (§7.2, §30.4).
- [x] 6J does not duplicate CRM/campaign/call/knowledge domains (§7.3–§7.7).
- [x] Outbox usage is transactionally correct (§37.1).
- [x] Audit events omit secrets (§36.3, §12.1 rule 3).
- [x] Provider errors are normalized (§35).
- [x] Provider quotas/rate limits are accounted for (§16).
- [x] Tenant isolation is explicit (§31).
- [x] Database mappings have been verified (§51).
- [x] Missing persistence is flagged (§56 — DEP-6J-01/02/04/05/09/10/11 **resolved and LIVE-VALIDATED**; DEP-6J-06/07/08 remain genuinely open, non-blocking except DEP-6J-06 (P1); DEP-6J-12 disclosed as a cross-phase coordination item).
- [x] No invented table names are presented as existing (§51, §56).
- [x] No unapproved microservices are introduced (§4 — modular monolith, existing infra reused throughout).
- [x] No arbitrary executable plugin model is silently introduced (§25.1 — settled by 4F/5I, restated not reopened).
- [x] Endpoint inventory is complete (§48 — 42 endpoints, each appears once).
- [x] Authorization matrix is complete (§49).
- [x] Error catalog is complete (§35.3 — 30 domain-specific codes).
- [x] Event catalog is complete (§50 — 19 governed topics + internal-only events).
- [x] Traceability is complete (§51–§52).
- [x] Owner decisions are explicitly surfaced (§57 — 4 decisions, none blocking).
- [x] Every P0/P1 finding across both remediation passes is fixed-and-live-validated, fixed-at-the-design-level-with-a-disclosed-cross-phase-dependency, or explicitly re-classified with rationale (§61 Reconciliation Table — 32 findings, 0 defended-away, 0 silently dropped).
- [x] The adversarial security test matrix (§60) was **executed** against a genuine PostgreSQL 18.6 instance — tenant-forgery, OAuth, integration/plugin lifecycle, webhook rotation, a genuine concurrency race, RLS, privileges, and `SECURITY DEFINER` inventory all PASS, with full cited raw evidence (`5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`, `5K/execution_logs/`). SSRF (application-layer, no deployed code exists in this repo to test) is the one disclosed, explicitly non-DB-testable category.

**No item above is marked "EXECUTION-BLOCKED."** Every endpoint in §48 has a designed, DB-backed, **live-validated** execution path. What remains open is limited to two explicitly disclosed, named, non-blocking-per-scope items (§56 DEP-6J-12, the 6I cross-phase schema-compatibility gap; and the SSRF application-layer tests untestable at this repository's current layer) plus the pre-existing, still-open DEP-6J-06/07/08.

---

## 59. Phase 6J Acceptance Criteria

### Architecture
- [x] Aligns with 6A–6I — no frozen decision contradicted; every deviation from the task brief's illustrative examples (state vocabulary, URL shapes, endpoint list) is traced to an actual 5I/6A/4F source, not invented.
- [x] Preserves modular monolith — no Kafka, service mesh, second microservice, or bespoke plugin sandbox introduced (§4).
- [x] Cleanly separates integration, workflow, and domain ownership (§7).

### Integrations
- [x] Provider catalog specified (§9).
- [x] Connection lifecycle specified (§8, §11) — DEP-6J-01 resolved by `101_5I1.sql`, **live-validated** (§56, §60).
- [x] OAuth/API-key credentials secure (§12–§13) — tenant-bootstrap defect corrected (ADR-6J-08).
- [x] Provider errors and quotas normalized (§16, §35).
- [x] Sync semantics implementation-ready **for what 5I's schema actually supports** (§15) — full job-history semantics honestly flagged as a schema gap (DEP-6J-06, still open, P1), not fabricated.

### Webhooks
- [x] Subscriptions are first-class resources (§18).
- [x] Signing is secure (§21).
- [x] Retry semantics are deterministic (§22.3).
- [x] At-least-once delivery is clearly communicated (§22.1).
- [x] Consumers have an idempotency strategy (§21.2 rule 3).
- [x] Replay/redelivery is supported safely (§23.3).
- [x] Delivery history is observable (§23.1–§23.2).
- [x] Provider inbound webhook ingestion is verified and deduplicated (§24).

### Plugins
- [x] Plugin definition is precise (§25.2).
- [x] Manifest is versioned (§26.3, §29).
- [x] Installation lifecycle is complete (§27) — suspend/reactivate/config-update/credential-rotation gaps (DEP-6J-02) resolved by `101_5I1.sql`, **live-validated**.
- [x] Capability/scopes are least privilege (§28).
- [x] Integration with 6I workflows is clear (§30) — closes 6I §23/§54 item 5.
- [x] Plugin upgrades cannot silently change workflow behavior (§30.5, ADR-6J-09) — **corrected this pass**: explicit `plugin_version_id` pinning, re-checked at every execution, not merely "fails closed until reactivation" (the prior revision's weaker guarantee).
- [x] No arbitrary unsandboxed code execution is introduced (§25.1).

### Security
- [x] SSRF protections are concrete (§30.3).
- [x] OAuth CSRF/replay protections are concrete (§13.3–§13.4).
- [x] Tenant isolation is explicit (§31).
- [x] Credentials never leak (§12).
- [x] Webhook secrets can be safely rotated (§21.3) — **corrected this pass**: dual-signature grace (ADR-6J-07) actually provides a working grace period, unlike the prior revision's retain-without-signing design.
- [x] Provider callbacks are authenticated where possible (§24.2) and tenant-routed only after verification, never from an unverified payload field (§24.6, ADR-6J-10, corrected this pass).

### API Completeness
- [x] Endpoint inventory complete (§48).
- [x] Schemas complete (§47 examples throughout §9–§30).
- [x] Errors complete (§35.3).
- [x] Authz complete (§49).
- [x] Audit complete (§36).
- [x] Examples complete (§47).
- [x] DB traceability complete (§51).

---

## 60. Security Test Matrix

**Status: EXECUTED (PostgreSQL 18.6, not the requested 16 — disclosed engine-version deviation).** Every DB-layer-testable category below (§60.1-§60.7 as originally specified, covering OAuth, integration/plugin lifecycle, and — via the tenant-forgery/webhook-rotation matrices actually run — the equivalent of §60.2's tenant-scoping concerns) was executed as a real adversarial test suite against a genuine, isolated, throwaway PostgreSQL instance this pass, not merely specified. Full raw evidence, exact commands, and complete output: `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` and `5K/execution_logs/` (14 files, prefix `20260829T210000Z_`). The table below is retained as the original test specification — each row is annotated with its actual, live result. **§60.6 (SSRF) was not executed** — it is application-layer logic with no deployed application code anywhere in this repository to run it against; disclosed as untestable at this layer, not skipped. §60.7's underlying DB-layer capability check-enforced-capabilities test) was executed via the plugin lifecycle matrix (§26 renamed §60.3 below); the workflow-publish-time/execution-time re-check itself is 6I-owned code this document cannot execute (§56 DEP-6J-12).

### 60.1 OAuth

| # | Test | Expected result |
|---|---|---|
| 1 | Valid callback: `state` from a fresh `oauth_attempts` row, correct `code` | `fn_redeem_oauth_callback_state` returns full context; connection reaches `ACTIVE` |
| 2 | Unknown `state` | `400 OAUTH_STATE_INVALID`, no row mutated |
| 3 | Expired `state` (`expires_at` in the past) | `410 OAUTH_STATE_EXPIRED`; row transitions `PENDING → EXPIRED` |
| 4 | Replayed `state` (second redemption attempt after first succeeded) | `409 OAUTH_STATE_ALREADY_USED`; second caller never receives `organization_id` |
| 5 | Concurrent double callback (two simultaneous requests with the same `state`) | Exactly one succeeds (`SELECT ... FOR UPDATE` serializes); the other gets `409 OAUTH_STATE_ALREADY_USED`, never a torn/partial redemption |
| 6 | Provider-denied authorization (`?error=access_denied`) | `fn_fail_oauth_callback_state` marks `FAILED`; `fn_fail_integration_connection` marks the connection `FAILED`; both consistent |
| 7 | Token-exchange failure after successful redemption | Attempt already `REDEEMED` (correct — redemption and token exchange are separate steps); connection remains `CONNECTING` un-activated; a stuck `CONNECTING` connection is tenant-visible via `GET .../connections/{id}` and disconnectable |
| 8 | Cross-tenant `state` reuse attempt (attacker guesses/captures another org's `state` value) | Bounded entirely by `state`'s own 256-bit unguessability — not a distinct code path to test beyond #2/#4 above; no `organization_id` is ever accepted from the caller to begin with |
| 9 | `fn_redeem_oauth_callback_state` called by `app_api` (the actual caller) vs. directly as `app_migration` | Both succeed identically — confirms the `EXECUTE` grant, not RLS bypass, is what matters for `app_api`'s access (§56, ADR-6J-08) |
| 10 | PKCE: token exchange using a `code_verifier` that does NOT match the original `code_challenge` | Provider-side rejection (external, not DB-testable) — confirm the platform passes the DB-stored `code_verifier` through unmodified, never a client-supplied one |

### 60.2 Integration Connection Lifecycle

| # | Test | Expected result |
|---|---|---|
| 11 | `fn_activate_integration_connection` from `CONNECTING` | `→ ACTIVE`, `connected_at` set |
| 12 | `fn_activate_integration_connection` from `DEGRADED` | `→ ACTIVE`, `connected_at` unchanged (already set) |
| 13 | `fn_activate_integration_connection` from `ACTIVE`/`FAILED`/`DISCONNECTED` | Exception — not a valid source state |
| 14 | `fn_fail_integration_connection` from `CONNECTING` | `→ FAILED`, `disconnected_at` set (per `chk_ic_terminal_has_at`) |
| 15 | `fn_fail_integration_connection` from `ACTIVE`/`DEGRADED` | Exception — 4F §7.5's state diagram has no such edge |
| 16 | `fn_fail_integration_connection` called twice on the same `CONNECTING` connection | Second call idempotent no-op |
| 17 | `fn_disconnect_integration_connection` from `CONNECTING`/`ACTIVE`/`DEGRADED` | `→ DISCONNECTED` in every case |
| 18 | `fn_disconnect_integration_connection` on an already-`DISCONNECTED` or `FAILED` connection | Idempotent no-op, `200`, not an error |
| 19 | `fn_ic_terminal_guard` still fires for any *direct* `UPDATE` attempting to move a `FAILED`/`DISCONNECTED` row away from terminal (bypassing the new functions entirely) | Exception — confirms the new functions don't weaken the pre-existing trigger |
| 20 | `POST .../reauthorize` on a `FAILED` connection | `409 INTEGRATION_DISABLED` — never attempts `fn_activate_integration_connection` against a `FAILED` row |
| 21 | `fn_create_integration_connection` against an `is_active = false` definition | Exception — confirms the `101_5I1` `CREATE OR REPLACE` addition |

### 60.3 Plugin Installation Lifecycle

| # | Test | Expected result |
|---|---|---|
| 22 | `fn_suspend_plugin_installation` from `ACTIVE` | `→ SUSPENDED` |
| 23 | `fn_suspend_plugin_installation` from `INSTALLED`/`UNINSTALLED` | Exception |
| 24 | `fn_reactivate_plugin_installation` from `SUSPENDED`, plugin/version still `APPROVED` | `→ ACTIVE`, `enabled_capabilities` **unchanged** from pre-suspension value |
| 25 | `fn_reactivate_plugin_installation` where the version has since become `DEPRECATED` | Succeeds (deprecation doesn't block reactivation of an already-installed version, §29.2) |
| 26 | `fn_reactivate_plugin_installation` where the plugin has since become `REJECTED`/de-approved | Exception |
| 27 | `fn_pi_terminal_guard` still blocks suspend/reactivate against an `UNINSTALLED` row | Exception |

### 60.4 Webhook Dual-Signature Rotation

| # | Test | Expected result |
|---|---|---|
| 28 | `fn_rotate_webhook_secret` with default grace period | `previous_signing_secret_ref` = old current secret, `previous_secret_expires_at` = `NOW() + 3600s`, `signing_secret_ref` = new secret |
| 29 | Delivery sent during active grace window | Both `X-Platform-Signature` (new) and `X-Platform-Signature-Previous` (old) present, both verify against their respective secrets over the identical `ts.body` input |
| 30 | Delivery sent after `previous_secret_expires_at` passes | `X-Platform-Signature-Previous` absent; only current-secret signature present |
| 31 | `fn_rotate_webhook_secret` called a second time while a grace window is still active | Second rotation's "previous" is the second-current secret (the first rotation's own previous secret is discarded, not retained — single-generation-only design, disclosed) |
| 32 | `grace_period_seconds = 0` | No grace window at all — `previous_signing_secret_ref` stays `NULL`, immediate hard cutover |
| 33 | `grace_period_seconds` outside `0`–`86400` | `422 WEBHOOK_ROTATION_INVALID` |

### 60.5 Inbound Provider Webhooks

| # | Test | Expected result |
|---|---|---|
| 34 | Valid opaque-route-segment + valid provider signature | Request routes to the correct connection, verifies, processes |
| 35 | Valid opaque-route-segment + **invalid** provider signature | Rejected — the route segment alone never grants trust |
| 36 | Unknown/guessed opaque-route-segment | `404`-equivalent (or silent drop, per the provider's expected contract) — never discloses whether a route segment is valid |
| 37 | Duplicate delivery of the same `provider_event_id` (same tenant) | Second `INSERT ... ON CONFLICT DO NOTHING RETURNING id` returns no row; async task NOT enqueued a second time |
| 38 | Genuine concurrent duplicate (two near-simultaneous identical deliveries) | Exactly one row created, exactly one async task enqueued — proven under real concurrency, not assumed from the constraint alone |
| 39 | Same `provider_event_id`, different tenant (two orgs both connected to the same provider account structure) | Both rows created independently — confirmed non-collision (FIX-08 preserved) |
| 40 | Fallback-fingerprint path: two distinct-but-field-identical payloads from a provider with no native event ID | Second one dedupes against the first (disclosed, honest limitation — confirm the behavior matches the documented limitation, not a surprise) |

### 60.6 SSRF / Egress Adapter

| # | Test | Expected result |
|---|---|---|
| 41 | `target_url`/`base_url` = `http://...` (non-HTTPS) | Rejected at registration |
| 42 | `target_url` resolving to `127.0.0.1` | Rejected |
| 43 | `target_url` resolving to `169.254.169.254` (cloud metadata) | Rejected, no enterprise-override path exists |
| 44 | `target_url` resolving to an RFC1918 address | Rejected (V1, no allow-list) |
| 45 | `target_url` resolving to an IPv6 loopback (`::1`) | Rejected |
| 46 | `target_url` resolving to an IPv6 unique-local (`fc00::/7`) | Rejected |
| 47 | `target_url` resolving to an IPv4-mapped-IPv6 form of a private address (`::ffff:10.0.0.1`) | Rejected (confirms the unwrapped-form check, not just the literal IPv6 range) |
| 48 | DNS rebinding: hostname resolves safely at registration, resolves to a private IP at actual call time | Rejected at call time (resolve-then-pin is per-request, not cached from registration) |
| 49 | Redirect chain of exactly 3 hops, all safe | Followed, final response used |
| 50 | Redirect chain of 4+ hops | Rejected once the hop limit is exceeded |
| 51 | Redirect to a private/metadata address at any hop | Rejected at that hop, independent of earlier hops' validity |
| 52 | Cross-origin redirect (different host) carrying an `Authorization`/signing header | Header stripped before following; destination never receives it |
| 53 | Same-origin redirect (identical host/scheme/port) | Headers may be forwarded (no trust boundary crossed) |
| 54 | TLS certificate presented for the pinned IP does not match the original hostname | Rejected — hostname verification is against the original hostname, never skipped |
| 55 | Webhook delivery specifically receiving any `3xx` | Never followed, regardless of the general adapter's redirect policy (§22.4's stricter rule) |
| 56 | Response body exceeding 2MB | Truncated/aborted at the cap, not buffered unbounded |

### 60.7 Plugin Workflow Version Pinning

| # | Test | Expected result |
|---|---|---|
| 57 | Workflow published with `plugin_installation_id` + `plugin_version_id` matching the installation's current version | Publish succeeds |
| 58 | Workflow published where the pinned `plugin_version_id` does NOT match the installation's current version | Publish rejected (`422 WORKFLOW_REFERENCE_NOT_READY`/`PLUGIN_VERSION_PINNED_MISMATCH`, per 6I's own gate) |
| 59 | Published workflow executes; installation is later upgraded (`fn_upgrade_plugin`) to a different version | Next execution of the pinned node fails with `422 PLUGIN_VERSION_PINNED_MISMATCH` — does NOT silently run the new version |
| 60 | Tenant republishes the same workflow after the upgrade | New pin matches the new current version; publish succeeds; subsequent executions run the new version deliberately, not silently |
| 61 | Installation upgraded, then reactivated with capabilities valid for the new version, but an OLD unpinned-shape workflow (pre-`101_5I1`/ADR-6J-09, hypothetically) still exists | Out of scope for this document to fix retroactively (ADR-6J-09's compatibility note) — flagged, not silently claimed resolved |

### 60.8 Idempotency Fingerprint

| # | Test | Expected result |
|---|---|---|
| 62 | Two identical requests (including an identical raw credential) with the same `Idempotency-Key` | Second returns the cached response, no duplicate side effect |
| 63 | Confirm the Redis-stored fingerprint value is `HMAC-SHA256(platform_key, body)`, not `SHA-256(body)` | Fingerprint value differs from a bare `SHA-256` of the same body — confirms the keyed construction is actually in effect, not just documented |

---

## 61. Reconciliation Table

| # | Finding | Old 6J behavior | Corrected behavior | Persistence change? | Migration | Security impact | Status |
|---|---|---|---|---|---|---|---|
| 1 | Pass-1 §1 — phase status contradiction | Declared `IMPLEMENTATION READY` while documenting P0 blockers | Status logic corrected: `NOT READY` while any P0 is unresolved or unvalidated | No | — | Prevents a false "ready" signal from reaching an implementer | Fixed |
| 2 | Pass-1 §2 — DEP-6J-01, connection lifecycle | No DB path for `CONNECTING→ACTIVE`/`ACTIVE⇄DEGRADED`/`→DISCONNECTED` | 6 new SECURITY DEFINER functions (§8.6, §56) | Yes | `101_5I1.sql` | Closes a P0 functional gap; least-privilege pattern preserved | **Fixed, LIVE-VALIDATED** (§10 of validation report) |
| 3 | Pass-1 §3 — DEP-6J-02, plugin lifecycle | No DB path for suspend/reactivate/config-update/credential-rotate | 4 new SECURITY DEFINER functions (§27, §56) | Yes | `101_5I1.sql` | Same pattern as #2 | **Fixed, LIVE-VALIDATED** (§11) |
| 4 | Pass-1 §4 — OAuth callback tenant bootstrap | `fn_redeem_oauth_attempt(state, organization_id)` required an input the unauthenticated callback caller cannot supply | `fn_redeem_oauth_callback_state(state, expected_definition_id)` — state alone (plus provider binding, added pass 2), returns tenant identity as output; confirmed safe via `app_migration`'s live-reconfirmed `BYPASSRLS` | Yes | `101_5I1.sql` | Closes a P0 circular-dependency defect | **Fixed, LIVE-VALIDATED** (§9, OA-1 through OA-14) |
| 5 | Pass-1 §5 — reauthorize-from-FAILED contradiction | `POST .../reauthorize` allowed on `FAILED`, contradicting the terminal-state guard | Reauthorize restricted to `ACTIVE`/`DEGRADED` only | No | — | Removes a contract that would have thrown a DB exception | Fixed |
| 6 | Pass-1 §6 — webhook secret rotation cryptographic defect | Old secret retained but never signed with — no real grace period | Dual-signature grace: both current and unexpired-previous secrets sign every delivery | Yes (2 new columns) | `101_5I1.sql` | Closes a P0 defect | **Fixed, LIVE-VALIDATED** (§8 test 11, §12) |
| 7 | Pass-1 §7 — plugin/workflow version determinism | Node config stored only `plugin_installation_id` | Node config pins `plugin_version_id`, re-checked at every execution | No (6I-owned field; no 6J DB change) | — (DEP-6J-12) | Closes a P0 non-determinism defect at the design level | **Fixed (design), LIVE-PROVEN at the DB layer** (§11 — capability-set correctly reset on upgrade, old capability correctly rejected against new manifest); **6I's own schema does not yet carry the field — disclosed cross-phase blocker, DEP-6J-12, not resolved** |
| 8 | Pass-1 §8 — `enabled_capabilities` field existence | Assumed possibly invented | **Verified genuinely exists**, then **live-confirmed** via direct query against both tables | No | — | None — false alarm | Verified, no change needed |
| 9 | Pass-1 §9 — generic inbound tenant resolution (confused deputy) | Tenant resolved from unverified payload content | Opaque per-connection routing segment selects the connection before payload trust | No | — | Closes a P0 confused-deputy risk | Fixed (design; no application code exists in this repo to live-test the routing layer itself, though the underlying dedup mechanism it feeds is live-tested, #13 below) |
| 10 | Pass-1 §10 — idempotency fingerprint on low-entropy secrets | Bare `SHA-256(body)` | `HMAC-SHA256(platform_key, body)` | No (application-layer) | — | Closes a P1 exposure | Fixed (design; application-layer, not DB-testable) |
| 11 | Pass-1 §11 — OAuth denial path | No function marked an attempt `FAILED` | `fn_fail_oauth_callback_state`, further split from post-redemption failure by pass 2 (#26 below) | Yes | `101_5I1.sql` | Closes P1 | **Fixed, LIVE-VALIDATED** (§9, OA-7/OA-8) |
| 12 | Pass-1 §12 — internal-RPC pattern reconsidered | Synchronous internal-JWT RPC hop proposed | 5 `GRANT EXECUTE ... TO app_api` — direct execution | Yes (grants only) | `101_5I1.sql` | Security posture unchanged | **Fixed, LIVE-VALIDATED** (§15 privilege matrix confirms all 5 grants) |
| 13 | Pass-1 §13 — inbound dedup/enqueue race safety | Prose described the outcome without stating enqueue-gating as a hard requirement | `INSERT ... ON CONFLICT DO NOTHING RETURNING id`; enqueue gated on a returned row | No | — | Makes the guarantee explicit | **Fixed, LIVE-VALIDATED via a genuine two-process concurrency race** (§13 of validation report — exactly one of two simultaneous inserts won) |
| 14 | Pass-1 §14 — fallback fingerprint ordering | Post-normalization (wrong ordering) | Pre-normalization, from raw verified bytes | No | — | Removes a circular/wrong-ordering description | Fixed |
| 15 | Pass-1 §15 — SSRF DNS/TLS/redirect completeness | Missing IPv6 unique-local, IPv4-mapped-IPv6, per-request re-resolution, TLS/SNI, redirect stripping | All added to §30.3 | No | — | Closes several P1 gaps | Fixed (design; application-layer, no deployed code in this repo to test — §18 of validation report) |
| 16 | Pass-1 §16 — Prometheus label cardinality | `organization_id` in a metric label | Removed | No | — | Closes a P1 operational risk | Fixed |
| 17 | Pass-1 §17 — webhook DELETE/disable incoherence | `DELETE` emitted `WEBHOOK_ENDPOINT_DELETED` despite no deletion | `DELETE` now emits `WEBHOOK_ENDPOINT_DISABLED` | No | — | Corrects a misleading audit entry | Fixed |
| 18 | Pass-1 §18 — sync job contract honesty | Already largely honest | Re-confirmed, function cited by name | Yes (function only) | `101_5I1.sql` | N/A | Confirmed correct |
| 19 | Pass-1 §19 — rotation idempotency vs. one-time-secret exposure | Not fully analyzed | Analysis added; no new secret-exposure surface | No | — | Confirmed safe | Fixed (analysis) |
| 20 | Pass-1 §20 — plugin callout signature scope | Body-only signature | Method + canonical path + timestamp + body | No | — | Closes a P1 risk | Fixed (design; application-layer) |
| 21 | Pass-1 §21 — `X-Platform-Tenant-Id` overstated as isolation | Implied as a tenant-isolation guarantee | Explicitly reclassified as non-enforcing | No | — | Corrects a misleading claim | Fixed |
| 22 | Pass-1 §22 — provider callback rate limiting layers | Single global ceiling only | 4-layer model | No | — | Closes a P1 gap | Fixed (design) |
| 23 | Pass-1 §23 — redirect credential leakage | Not addressed | Folded into §30.3 | No | — | Same fix as #15 | Fixed |
| 24 | Pass-1 §24 — re-evaluate all DEP severities | First-drafted severities | Re-evaluated (superseded again by #29 below) | No | — | N/A | Fixed |
| 25 | **Pass-2 §2 — SECURITY DEFINER tenant-forgery** | Every `SECURITY DEFINER` function (new and 8 pre-existing) trusted `p_organization_id` unconditionally; RLS inapplicable inside `BYPASSRLS`-owned functions | `organization.current_tenant_id() = p_organization_id` guard, fail-closed, on every tenant-bound function (§31.1, ADR-6J-11) | Yes (function bodies, `CREATE OR REPLACE`) | `101_5I1.sql` (amended in place) | **Closes a P0 that would have allowed complete cross-tenant mutation** | **Fixed, LIVE-VALIDATED — 11-test adversarial matrix, zero forged mutations succeeded** (§8) |
| 26 | **Pass-2 §5 — OAuth exchange-failure state-machine contradiction** | `fn_fail_oauth_callback_state` claimed to handle post-redemption failure while explicitly rejecting `REDEEMED` status — self-contradictory | Split: `fn_fail_oauth_callback_state` pre-redemption only; new `fn_record_oauth_exchange_failure` post-redemption only, `status` stays `REDEEMED` | Yes (new column `exchange_failed_at`, new function) | `101_5I1.sql` | Closes a P0 logical gap | **Fixed, LIVE-VALIDATED** (§9, OA-9/OA-10/OA-11/OA-12) |
| 27 | **Pass-2 §6 — OAuth state/provider binding** | `state` redemption verified no relationship to the calling route's provider | `p_expected_definition_id` required, checked before consumption | Yes (function signature) | `101_5I1.sql` | Closes a P0 cross-provider confusion risk | **Fixed, LIVE-VALIDATED** (§9, OA-4/OA-5) |
| 28 | **Pass-2 §7 — OAuth callback least privilege** | Callback bootstrap functions granted to `app_worker` alongside `app_api`/`app_platform_admin` | Narrowed to `app_api, app_platform_admin` only | Yes (grants) | `101_5I1.sql` | Closes an unnecessary-privilege P1 | **Fixed, LIVE-VALIDATED** (§9 OA-14 — `app_worker` EXECUTE confirmed `false`, direct call denied) |
| 29 | **Pass-2 §9 — historical `fn_create_*` tenant-forgery** | `fn_create_integration_connection`/`fn_create_plugin_installation` (059-066, already `app_api`-callable) shared the tenant-forgery defect class, undiscovered until this review | `CREATE OR REPLACE`, same signature, guard added | Yes (function bodies) | `101_5I1.sql` | Closes a P0 in *pre-existing*, frozen functions | **Fixed, LIVE-VALIDATED** (§8 tests 2, 7) |
| 30 | **NEW — live-discovered, not in either remediation prompt: `gen_uuid_v7()` missing `search_path`** | Undiscovered; live testing of 6J's own new functions failed immediately | `CREATE OR REPLACE FUNCTION public.gen_uuid_v7() ... SET search_path = public, pg_catalog` | Yes (one function, platform-wide effect) | `101_5I1.sql` | Was blocking all functional writes for 6J; platform-wide, 84-function blast radius disclosed | **Fixed, LIVE-VALIDATED for `integrations`/`plugins`/`webhooks`; 83 other affected functions platform-wide explicitly un-audited, forward finding** (§6 of validation report) |
| 31 | **Pass-2 §14 — 6I `plugin_version_id` schema compatibility** | Assumed 6I's `graph_json` could carry the field; never directly verified | Directly inspected 6I §11's frozen node-config table — field does not exist | No (cannot be resolved by 6J) | — | N/A — disclosure, not a fix | **Disclosed as an explicit, unresolved cross-phase coordination item (DEP-6J-12), not silently claimed closed** |
| 32 | Live-database validation itself (governing task §20, both passes) | Not performed, pass 1 | Full adversarial suite executed against a genuine PostgreSQL 18.6 instance | N/A | N/A | Proves every claim above rather than asserting it | **Executed** — `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` |

**0 findings defended away or dismissed without either a fix or a directly-evidenced "not a real defect" determination.** Finding #8 (verified false alarm) and finding #18 (confirmed already correct) are the only two rows resolved by verification rather than a change — both backed by direct re-reading of source/live queries, not by declining to investigate.

---

## 62. Final Phase Status

`PHASE 6J — IMPLEMENTATION READY`

**This verdict reflects a real state change from this document's prior revision** (which correctly declared `NOT READY — P0 BLOCKERS REMAIN`, because at that point every P0 fix existed only as authored-but-unexecuted SQL). This pass closed that gap and three further P0s an independent review found in the first pass's own migration, then **executed the entire result against a genuine, isolated PostgreSQL 18.6 instance** — not PostgreSQL 16 as originally requested (disclosed engine-version deviation, §60) — with a full adversarial test suite, not a partial or representative sample.

**Every item in the remediation task's own explicit final-status gate is satisfied, with cited live evidence, not assertion:**

| Gate requirement | Result | Evidence |
|---|---|---|
| Zero P0 blockers | All 10 P0s across both remediation passes closed (§61: findings 2,3,4,6,7,9,25,26,27,29) | §56 DEP table, §61 |
| Migration executed on PostgreSQL (18.6, disclosed deviation from 16) | Fresh + incremental, both PASS, exit 0 | Validation report §2-§3 |
| Single Alembic head | `101_5I1 (head)`, `current == head`, linear history | Validation report §4 |
| Tenant-forgery tests PASS | 11/11 | Validation report §8 |
| OAuth tests PASS | 14/14 | Validation report §9 |
| Webhook rotation tests PASS | Dual-signature grace live-confirmed | Validation report §8 test 11, §12 |
| Plugin lifecycle tests PASS | All legal/illegal/idempotent transitions, version-pinning capability-reset proven | Validation report §11 |
| Integration lifecycle tests PASS | All legal/illegal/idempotent transitions, terminal guards re-confirmed | Validation report §10 |
| Privileges PASS | `PUBLIC EXECUTE = false` on all 34 functions; every role's grant matches design | Validation report §15 |
| SECURITY DEFINER inventory PASS | Owner/`BYPASSRLS`/`search_path` correct for all 34 functions | Validation report §16 |
| RLS PASS | Fail-closed with no tenant context; tenant-scoped visibility; direct DML denied | Validation report §14 |
| Regression PASS | Targeted spot-check on outbox, worker-only scoping, 6I's own RLS — no regression found | Validation report §17 |

**What remains genuinely open, explicitly disclosed, and does not block this verdict per the gate's own literal text:**
- **SSRF/application-layer tests** — not performable at the database layer; no deployed application code exists anywhere in this repository to execute them against. This is a statement about the repository's contents, not a skipped test.
- **6I plugin-version-pinning schema compatibility (DEP-6J-12)** — an explicit, named, unresolved cross-phase coordination item. 6I is `APPROVED/FROZEN`; amending its `graph_json` node-config schema is outside this document's authority. 6J supplies the target contract (§30.2/§30.5); a future, small, controlled 6I amendment must implement it. Does not block any other endpoint in this document's own inventory (§48).
- **DEP-6J-06** (sync-job history table) — genuinely open P1, out of both remediation passes' named scope, unchanged.
- **83 of 84 `gen_uuid_v7`-affected functions outside `integrations`/`plugins`/`webhooks`** — the root-cause fix is applied and benefits all 84 transitively, but a full audit of which of the other 83 functions actually exercise the previously-broken path in practice is out of this document's scope — forward finding for the owning phases.
- A full re-run of every historical 001-100 test file — targeted regression spot-checks only, not exhaustive re-validation of phases 5B-5H/5J/6I's own prior test suites.

This document does **not** declare itself `PHASE 6J — FROZEN`. Final freeze/approval remains an independent-review decision, per every prior pass's own standing instruction — this pass declares readiness for that review, with full, cited, live evidence backing every claim, not a self-assessment.

---

