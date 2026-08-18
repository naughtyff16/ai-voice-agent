# Phase 5A — Database Architecture & Design Standards

| | |
|---|---|
| **Phase** | 5A — Database Architecture & Standards |
| **Status** | Draft v1.0, for approval before Phase 5B |
| **Authority** | Phase 4I — India-First Decision Closure (final Phase 4 authority) |
| **Scope** | Architecture standards, naming conventions, RLS design, partitioning strategy, index standards, migration conventions — all schemas. No SQL yet. |
| **Follows** | Phase 4H Final Architecture Review + Phase 4I Decision Closure |
| **Precedes** | Phase 5B–5I per-schema DDL |

---

## 1. Database Architecture Overview

### 1.1 Technology Stack — Confirmed

| Store | Role | Version target | Authority |
|---|---|---|---|
| **Supabase PostgreSQL** | Primary transactional database | PostgreSQL 15+ | Phase 2 HLA |
| **pgvector** | Vector embeddings inside PostgreSQL | 0.7+ | Phase 4E, 4I |
| **Redis** | Hot-tier: sessions, caches, queues, counters | Redis 7+ Cluster | Phase 3F |
| **S3 / Supabase Storage** | Object storage: recordings, documents, exports | S3-compatible | Phase 3F |
| **ClickHouse** | Future high-volume analytics | Deferred — V3 | Phase 4G |

**PostgreSQL is the authoritative source of truth for all durable business data.** Redis is a hot-tier cache and queue system — it is never authoritative. S3 is binary object storage — the database stores metadata and references. ClickHouse is not a V1 dependency.

### 1.2 Thirteen Schemas — Final Approved List

```
postgres (default admin, not used by application)
├── identity        — User, ApiKey, OAuth identity
├── organization    — Org, Membership, LocalizationProfile, CompliancePolicy, TaxProfileRef
├── voice           — Call, Conversation, Agent, ToolDefinition, Recording, Transcript, ProviderConfig
├── crm             — Contact, Company, Deal, Pipeline, Activity, Note, Task, Appointment,
│                     LeadScoreRecord, ConsentRecord, ContactSuppression
├── campaign        — Campaign, CampaignContact, CallJob, CsvImportJob, ContactList, CampaignOutcome
├── knowledge       — KnowledgeBase, Document, IngestionJob, DocumentChunk, EmbeddingVersion
├── workflow        — WorkflowDefinition, WorkflowExecution, PromptTemplate, PromptExperiment,
│                     SessionMemory, CustomerMemory, PronunciationLexicon
├── billing         — BillingAccount, Subscription, Plan, PlanVersion, Invoice, InvoiceLine,
│                     TaxLine, PaymentAttempt, UsageRecord, UsageEvent, CostEntry, QuotaConfig,
│                     TaxProfile, TaxRule, TaxCategory, InvoiceNumberSequence
├── integrations    — IntegrationDefinition, IntegrationConnection
├── webhooks        — WebhookEndpoint, WebhookDelivery
├── plugins         — Plugin, PluginInstallation
├── analytics       — All projection tables, AnalyticsDashboard
└── audit           — AuditEvent
```

**Adding a new schema requires answering:** which bounded context owns it, why existing schemas cannot accommodate it, how RLS is affected, and how cross-schema logical references interact. The bar is high — prefer a new table in an existing schema.

### 1.3 Application Roles

Three PostgreSQL roles reflect the three runtime boundaries (Phase 2):

| Role | Description | Privileges |
|---|---|---|
| `app_api` | Core API and Voice Gateway runtime | SELECT, INSERT, UPDATE, DELETE on all non-append-only tables within tenant context |
| `app_worker` | Background Celery workers | Same as `app_api` plus EXECUTE on maintenance functions |
| `app_readonly` | Analytics read queries, reporting | SELECT only on analytics projections and approved read models |
| `app_migration` | Alembic migration runner | Superuser equivalent — used only during deployments |
| `app_platform_admin` | Platform admin operations | SELECT across all tenants (no RLS bypass for data modification) |

**Append-only tables additionally have `REVOKE UPDATE, DELETE` for `app_api` and `app_worker`.** This is a schema-level enforcement, not just a convention.

### 1.4 Architectural Principles

1. **Normalised relational design for transactional data.** Denormalise only where read-performance justification is explicit and documented.
2. **Explicit aggregate ownership.** Every table belongs to exactly one bounded context and therefore exactly one schema. No shared tables.
3. **Explicit tenant ownership.** Every table is classified as tenant-owned, platform-owned, or mixed — documented in §3.
4. **No cross-schema foreign keys.** Cross-boundary references use logical UUID values only.
5. **JSONB where flexibility is genuinely required, not as a default.** Configuration snapshots, provider metadata, lexicon entries, and policy documents are appropriate JSONB uses. Core business identifiers, statuses, timestamps, and amounts are typed columns.
6. **Append-only for event/history entities.** Defined in §15.
7. **Versioned configuration.** Plan prices, tax rules, compliance policies, prompt versions, and agent version snapshots are immutable after publication. Changes create new versions, never overwrite.
8. **Immutable financial history.** Invoice lines, payment attempts, cost entries, and usage events are never updated after creation.
9. **Soft deletion only where domain semantics require it.** Most entities are hard-deleted or terminal-status'd. Soft deletion is reserved for entities that must survive for audit/reference after operational deletion (Contact, Document, Recording).
10. **Idempotency by design.** Every append-only write carries an idempotency key. Duplicate inserts are `ON CONFLICT DO NOTHING` or `ON CONFLICT DO UPDATE` as appropriate.

---

## 2. PostgreSQL Schema Architecture

### 2.1 Schema Ownership Map

| Schema | Owning Bounded Context(s) | Phase 4 Reference | Tenant-Scoped? |
|---|---|---|---|
| `identity` | Identity & Access, Authorization | 4A | Partially (ApiKey is tenant-scoped; User is platform-scoped) |
| `organization` | Organization, Compliance, Data Residency | 4A, 4I | Yes (org is the tenant root) |
| `voice` | Voice & AI, Tool Execution, Recording, Provider Network | 4B | Yes |
| `crm` | CRM, Appointments, Lead Scoring, Consent, Suppression | 4C, 4I | Yes |
| `campaign` | Campaign Management, Campaign Execution, CSV Import | 4D | Yes |
| `knowledge` | Knowledge & RAG | 4E | Yes |
| `workflow` | Workflow Engine, Prompt Management, Memory | 4E | Yes |
| `billing` | Billing & Subscription, Usage Metering, Tax | 4F, 4I | Yes (BillingAccount is tenant root) |
| `integrations` | Integrations | 4F | Mixed (IntegrationDefinition is platform; Connection is tenant) |
| `webhooks` | Webhooks | 4F | Yes |
| `plugins` | Plugins | 4F | Mixed (Plugin is platform; Installation is tenant) |
| `analytics` | Analytics | 4G | Yes |
| `audit` | Audit | 4A | Mixed (platform-scope rows exist) |

### 2.2 Schema Isolation Rules

```
Within a schema:   FK constraints are permitted and encouraged.
Across schemas:    Only logical UUID references (no FOREIGN KEY REFERENCES other_schema.table).
Cross-schema join: Permitted in read queries from the application layer.
                   Analytics projections may join across schemas in background workers.
Migration order:   identity → organization → voice → crm → campaign → knowledge →
                   workflow → billing → integrations → webhooks → plugins → analytics → audit
                   (respects logical dependency ordering)
```

---

## 3. Schema Ownership Matrix (Tenant vs. Platform)

| Table | Schema | Tenant-Owned? | Tenant Key Column | RLS Required? | Platform-Owned? | Notes |
|---|---|---|---|---|---|---|
| `users` | identity | No (platform) | — | No | Yes | Global user registry; scoped at membership |
| `api_keys` | identity | Yes | `organization_id` | Yes | No | |
| `oauth_identities` | identity | No | — | No | Yes | Provider + external_id unique |
| `organizations` | organization | Yes (self-root) | `id` | No (it is the root) | No | RLS root object |
| `memberships` | organization | Yes | `organization_id` | Yes | No | |
| `teams` | organization | Yes | `organization_id` | Yes | No | |
| `roles` | organization | Mixed | `organization_id` (nullable for system roles) | Yes with null exclusion | Partially | System roles have null org_id |
| `permissions` | organization | No | — | No | Yes | Platform permission catalogue |
| `role_permissions` | organization | Mixed | via `role_id` | Yes (tenant roles) | Partially | |
| `compliance_policies` | organization | Yes | `organization_id` | Yes | No | |
| `data_subject_requests` | organization | Yes | `organization_id` | Yes | No | Sensitive — restricted permission |
| `call_sessions` | voice | Yes | `organization_id` | Yes | No | High-volume; partitioned |
| `conversations` | voice | Yes | `organization_id` | Yes | No | |
| `turns` | voice | Yes | `organization_id` | Yes | No | |
| `agents` | voice | Yes | `organization_id` | Yes | No | |
| `agent_versions` | voice | Yes | `organization_id` | Yes | No | |
| `tool_definitions` | voice | Mixed | `organization_id` (nullable for platform tools) | Yes with null exclusion | Partially | |
| `tool_executions` | voice | Yes | `organization_id` | Yes | No | |
| `recordings` | voice | Yes | `organization_id` | Yes | No | |
| `transcript_segments` | voice | Yes | `organization_id` | Yes | No | Append-only; partitioned |
| `provider_configs` | voice | Mixed | `organization_id` (nullable for platform defaults) | Yes with null exclusion | Partially | |
| `language_evaluation_records` | voice | No | — | No | Yes | Provider evaluation data |
| `tenant_phone_numbers` | voice | Yes | `organization_id` | Yes | No | |
| `contacts` | crm | Yes | `organization_id` | Yes | No | High-volume |
| `companies` | crm | Yes | `organization_id` | Yes | No | |
| `deals` | crm | Yes | `organization_id` | Yes | No | |
| `pipelines` | crm | Yes | `organization_id` | Yes | No | |
| `pipeline_stages` | crm | Yes | `organization_id` | Yes | No | |
| `activities` | crm | Yes | `organization_id` | Yes | No | Append-only; partitioned |
| `tasks` | crm | Yes | `organization_id` | Yes | No | |
| `notes` | crm | Yes | `organization_id` | Yes | No | |
| `appointments` | crm | Yes | `organization_id` | Yes | No | |
| `lead_score_records` | crm | Yes | `organization_id` | Yes | No | Append-only |
| `crm_field_definitions` | crm | Yes | `organization_id` | Yes | No | |
| `consent_records` | crm | Yes | `organization_id` | Yes | No | Append-only; sensitive |
| `contact_suppressions` | crm | Mixed | `organization_id` (nullable for PLATFORM/REGULATORY scope) | Yes — special policy | Partially | See §6.4 |
| `campaigns` | campaign | Yes | `organization_id` | Yes | No | |
| `campaign_contacts` | campaign | Yes | `organization_id` | Yes | No | Very high-volume; partitioned |
| `call_jobs` | campaign | Yes | `organization_id` | Yes | No | |
| `contact_lists` | campaign | Yes | `organization_id` | Yes | No | |
| `csv_import_jobs` | campaign | Yes | `organization_id` | Yes | No | |
| `campaign_outcomes` | campaign | Yes | `organization_id` | Yes | No | |
| `knowledge_bases` | knowledge | Yes | `organization_id` | Yes | No | |
| `documents` | knowledge | Yes | `organization_id` | Yes | No | |
| `ingestion_jobs` | knowledge | Yes | `organization_id` | Yes | No | |
| `document_chunks` | knowledge | Yes | `organization_id` | Yes | No | pgvector; partitioned |
| `embedding_versions` | knowledge | No | — | No | Yes | Platform reference data |
| `workflow_definitions` | workflow | Yes | `organization_id` | Yes | No | |
| `workflow_executions` | workflow | Yes | `organization_id` | Yes | No | High-volume |
| `prompt_templates` | workflow | Yes | `organization_id` | Yes | No | |
| `prompt_experiments` | workflow | Yes | `organization_id` | Yes | No | |
| `session_memories` | workflow | Yes | `organization_id` | Yes | No | |
| `customer_memories` | workflow | Yes | `organization_id` | Yes | No | |
| `pronunciation_lexicons` | workflow | Yes | `organization_id` | Yes | No | |
| `billing_accounts` | billing | Yes | `organization_id` | Yes | No | 1:1 with org |
| `subscriptions` | billing | Yes | `organization_id` | Yes | No | |
| `plans` | billing | No | — | No | Yes | Platform product catalogue |
| `plan_versions` | billing | No | — | No | Yes | Immutable after creation |
| `plan_prices` | billing | No | — | No | Yes | |
| `invoices` | billing | Yes | `organization_id` | Yes | No | |
| `invoice_lines` | billing | Yes | `organization_id` | Yes | No | |
| `tax_lines` | billing | Yes | `organization_id` | Yes | No | |
| `payment_attempts` | billing | Yes | `organization_id` | Yes | No | |
| `credits` | billing | Yes | `organization_id` | Yes | No | |
| `usage_records` | billing | Yes | `organization_id` | Yes | No | |
| `usage_events` | billing | Yes | `organization_id` | Yes | No | Append-only; partitioned |
| `cost_entries` | billing | Yes | `organization_id` | Yes | No | Append-only; partitioned |
| `quota_configs` | billing | Yes | `organization_id` | Yes | No | |
| `tax_profiles` | billing | Yes | `organization_id` | Yes | No | |
| `tax_rules` | billing | No | — | No | Yes | Platform-managed rate data |
| `tax_categories` | billing | No | — | No | Yes | HSN/SAC reference |
| `invoice_number_sequences` | billing | Yes | `organization_id` | Yes | No | Gapless allocation |
| `fx_rates` | billing | No | — | No | Yes | Reference — not live market |
| `integration_definitions` | integrations | No | — | No | Yes | Platform catalogue |
| `integration_connections` | integrations | Yes | `organization_id` | Yes | No | |
| `webhook_endpoints` | webhooks | Yes | `organization_id` | Yes | No | |
| `webhook_deliveries` | webhooks | Yes | `organization_id` | Yes | No | Append-only; partitioned |
| `plugins` | plugins | No | — | No | Yes | Platform-registered |
| `plugin_versions` | plugins | No | — | No | Yes | |
| `plugin_installations` | plugins | Yes | `organization_id` | Yes | No | |
| `analytics_dashboards` | analytics | Yes | `organization_id` | Yes | No | |
| `call_metrics_hourly` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `call_latency_stage_hourly` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `conversation_turn_stats_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `lead_funnel_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `campaign_outcome_summary` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `agent_utilization_hourly` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `usage_cost_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `billing_revenue_monthly` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `roi_by_campaign` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `provider_health_5min` | analytics | No | — | No | Yes | Platform-scoped |
| `tool_execution_stats_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `webhook_delivery_stats_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `knowledge_retrieval_stats_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `campaign_eligibility_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `language_performance_daily` | analytics | Yes | `organization_id` | Yes | No | Projection |
| `audit_events` | audit | Mixed | `organization_id` (nullable for platform events) | Yes with null exclusion | Partially | Append-only; partitioned |

---

## 4. Aggregate-to-Table Mapping Strategy

### 4.1 One Aggregate, One Primary Table

Each aggregate root maps to exactly one primary table. Embedded entities and value objects that are small and always read/written with the root are stored in the same row (as columns or as typed JSONB). Embedded entities with their own identity and bounded collection size may use a child table within the same schema.

**Decision tree for embedded vs. separate table:**

| Condition | Pattern |
|---|---|
| Always read with parent, no independent query, small fixed set | Typed columns on parent row |
| Structured but variable/extensible (e.g. JSON schema, policy document, lexicon) | JSONB column on parent row |
| Has its own identity, queried independently, OR unbounded growth | Separate child table |
| Separate lifecycle from parent (can outlive parent reference) | Separate table with logical FK only |

**Examples:**

| Aggregate | Primary table | Embedded entities | Child tables |
|---|---|---|---|
| `Organization` | `organizations` | `LocalizationProfile` (columns), `DataResidencyProfile` (columns) | `memberships`, `teams` |
| `Agent` | `agents` | — | `agent_versions` |
| `AgentVersion` | `agent_versions` | `VoiceConfig` (columns), `ModelConfig` (columns), `LanguagePolicy` (JSONB) | — |
| `Call` | `call_sessions` | `LatencyProfile` (columns) | `call_session_legs` (if conference added later) |
| `Conversation` | `conversations` | — | `turns` |
| `Invoice` | `invoices` | `TaxProfileSnapshot` (JSONB) | `invoice_lines`, `tax_lines`, `payment_attempts` |
| `Plan` | `plans` | — | `plan_versions` |
| `Pipeline` | `pipelines` | — | `pipeline_stages` |
| `WorkflowDefinition` | `workflow_definitions` | `DraftGraph` (JSONB), `Versions` list (JSONB array) | — |
| `ContactSuppression` | `contact_suppressions` | — | — |
| `ConsentRecord` | `consent_records` | `ConsentEvidence` (JSONB) | — |
| `TaxRule` | `tax_rules` | `Components` list (JSONB array) | — |

### 4.2 Platform-Owned vs. Tenant-Owned Configuration

When a table contains both platform-owned rows (with `organization_id IS NULL`) and tenant-owned rows:
- `organization_id` is nullable.
- RLS treats `organization_id IS NULL` rows as readable by all tenants (when the semantic is "platform default") but writable only by `app_platform_admin`.
- This pattern is used for: `roles`, `tool_definitions`, `provider_configs`, `contact_suppressions` (PLATFORM/REGULATORY scope), `audit_events`.

---

## 5. Tenant Isolation Strategy

### 5.1 The Isolation Stack

```
Layer 1 — Application layer
  Every use-case receives tenant_id (= organization_id) as a mandatory argument.
  TenantContext contextvar (Phase 3A §11) is set from JWT/API-key at middleware before any handler executes.
  All repository methods accept and propagate tenant_id.

Layer 2 — Connection setup
  Every connection used by the application executes before first query:
    SET LOCAL app.tenant_id = '<uuid>';
  This is the RLS identity signal.

Layer 3 — PostgreSQL RLS (row-level security)
  Enabled on every tenant-owned table.
  Standard policy: organization_id = current_setting('app.tenant_id')::uuid
  Special cases documented in §6.

Layer 4 — Redis namespacing
  All keys are prefixed: {purpose}:{organization_id}:{...}
  No cross-tenant key access is possible by construction.

Layer 5 — S3 namespacing
  All object paths are prefixed: org/{organization_id}/...
  Presigned URLs are scoped to the organization's path prefix.

Layer 6 — Event envelope
  Every domain event carries organization_id (= tenant_id) in its envelope.
  Consumers filter and authorise on this field before processing.
```

### 5.2 `organization_id` as the Universal Tenant Key

All tenant-scoped tables use `organization_id UUID NOT NULL` (or `organization_id UUID` for mixed-scope tables). The column name is consistent across all 13 schemas.

**Why `organization_id` rather than `tenant_id`:** the domain language (Phase 4A) uses `Organization` as the tenant root. `organization_id` matches the domain name, making the database column directly readable without a mental mapping. `tenant_id` is a synonym that appears in event envelopes and application code; at the database level `organization_id` is canonical.

### 5.3 Consistency with `organization_id` as FK Root

The `organizations` table (schema `organization`) is the root of the tenant hierarchy. All tenant-scoped tables logically reference `organizations.id`. Cross-schema references from, e.g., `voice.call_sessions.organization_id` to `organization.organizations.id` are logical UUID references — there is no FK constraint across schemas, but the value must be a valid organization ID. Referential integrity across schemas is enforced at the application layer.

---

## 6. RLS Architecture

### 6.1 Standard RLS Pattern

```sql
-- Enabled on every tenant-owned table:
ALTER TABLE <schema>.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <schema>.<table> FORCE ROW LEVEL SECURITY;  -- applies to table owner too

-- Standard read policy:
CREATE POLICY rls_tenant_read ON <schema>.<table>
  FOR SELECT
  USING (organization_id = current_setting('app.tenant_id', true)::uuid);

-- Standard write policy:
CREATE POLICY rls_tenant_write ON <schema>.<table>
  FOR ALL  -- INSERT, UPDATE, DELETE
  USING (organization_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (organization_id = current_setting('app.tenant_id', true)::uuid);

-- app_migration and app_platform_admin bypass RLS:
ALTER TABLE <schema>.<table> FORCE ROW LEVEL SECURITY;
-- These roles use SET LOCAL app.tenant_id = 'platform-admin' for non-data-access operations.
```

`current_setting('app.tenant_id', true)` — the `true` argument means the function returns `NULL` rather than raising an error when the setting is not set. A null setting matches no rows, so an un-authenticated query reads nothing. This is the fail-safe behaviour.

### 6.2 Append-Only Table RLS

For append-only tables (audit_events, usage_events, cost_entries, consent_records, activities, transcript_segments, webhook_deliveries, lead_score_records):

```sql
-- Read: standard tenant policy
-- Insert: standard tenant policy (WITH CHECK only)
-- No UPDATE or DELETE policy — the REVOKE removes the privilege entirely

REVOKE UPDATE, DELETE ON <schema>.<append_only_table> FROM app_api, app_worker;
```

### 6.3 Mixed-Scope Tables — Platform + Tenant Rows

Tables where `organization_id IS NULL` rows are platform-owned (e.g., system roles, tool definitions, provider configs, audit events):

```sql
-- Read policy: see own rows OR platform rows
CREATE POLICY rls_mixed_read ON <schema>.<table>
  FOR SELECT
  USING (
    organization_id = current_setting('app.tenant_id', true)::uuid
    OR organization_id IS NULL
  );

-- Write policy: only own rows (platform rows protected)
CREATE POLICY rls_mixed_write ON <schema>.<table>
  FOR INSERT WITH CHECK (
    organization_id = current_setting('app.tenant_id', true)::uuid
  );

-- UPDATE/DELETE for tenant rows only
CREATE POLICY rls_mixed_update ON <schema>.<table>
  FOR UPDATE USING (
    organization_id = current_setting('app.tenant_id', true)::uuid
  );
```

### 6.4 Contact Suppressions — Special RLS Design

`contact_suppressions` has three scopes:

| Scope | `organization_id` | Readable by | Writable by |
|---|---|---|---|
| `ORG` | tenant UUID | That tenant only | That tenant (with `suppression:manage`) |
| `PLATFORM` | NULL | All tenants (read) | `app_platform_admin` only |
| `REGULATORY` | NULL | All tenants (read) | `app_platform_admin` only |

```sql
-- Read: own rows + platform/regulatory rows
CREATE POLICY rls_suppression_read ON crm.contact_suppressions
  FOR SELECT
  USING (
    organization_id = current_setting('app.tenant_id', true)::uuid
    OR (organization_id IS NULL AND scope IN ('PLATFORM', 'REGULATORY'))
  );

-- Insert: only own-scope rows
CREATE POLICY rls_suppression_insert ON crm.contact_suppressions
  FOR INSERT WITH CHECK (
    organization_id = current_setting('app.tenant_id', true)::uuid
    AND scope = 'ORG'
  );

-- No UPDATE or DELETE from app_api/app_worker (append-only for status transitions)
REVOKE UPDATE, DELETE ON crm.contact_suppressions FROM app_api, app_worker;
```

`PLATFORM` and `REGULATORY` rows are inserted only by `app_platform_admin` (which bypasses RLS). This ensures a regulatory suppression list entry is visible to all tenants at the enforcement read but cannot be accidentally overwritten by any tenant operation.

### 6.5 Audit Events — Special RLS Design

```sql
-- Read: own tenant events + platform events where organization_id IS NULL
CREATE POLICY rls_audit_read ON audit.audit_events
  FOR SELECT
  USING (
    organization_id = current_setting('app.tenant_id', true)::uuid
    OR organization_id IS NULL
  );

-- Insert: own tenant events only (platform events written by app_platform_admin)
CREATE POLICY rls_audit_insert ON audit.audit_events
  FOR INSERT WITH CHECK (
    organization_id = current_setting('app.tenant_id', true)::uuid
    OR organization_id IS NULL
  );
-- app_platform_admin writes platform events; standard role writes tenant events.

REVOKE UPDATE, DELETE ON audit.audit_events FROM app_api, app_worker;
```

### 6.6 Platform-Owned Tables — No RLS

`plans`, `plan_versions`, `tax_rules`, `tax_categories`, `currencies`, `countries`, `embedding_versions`, `integration_definitions`, `plugins`, `plugin_versions`, `language_evaluation_records`, `permissions`, `fx_rates` — these have no `organization_id` and no RLS policy. They are readable by all application roles and writable only by `app_platform_admin` or `app_migration`.

---

## 7. Cross-Schema Reference Strategy

### 7.1 The Rule

**No PostgreSQL `FOREIGN KEY ... REFERENCES` constraint crosses a schema boundary.** Cross-schema references use plain `UUID` columns with no database-enforced FK constraint.

### 7.2 Enforcement

The Alembic migration linter (a CI gate alongside import-linter) checks every migration file for:
- `REFERENCES` clauses pointing to a table in a different schema.
- If found, the migration is rejected with an explanatory error.

### 7.3 Cross-Schema Reference Naming Convention

When a table in schema A references a table in schema B:
- Column name: `{entity_name}_id` (same as if it were an FK).
- Comment: `-- logical ref: {schema_b}.{table} ({entity_name}.id)` — documents the semantic without creating a constraint.
- Application-layer validation: the use case that creates the referencing row must verify the referenced entity exists before committing.

**Example:**

```
-- In voice.call_sessions:
organization_id   UUID NOT NULL,  -- logical ref: organization.organizations.id
agent_version_id  UUID NOT NULL,  -- logical ref: voice.agent_versions.id (within-schema is also a logical ref when the FK would cross aggregate boundaries)
```

### 7.4 Within-Schema FK Policy

Within a schema, FK constraints are **encouraged** where:
- The referenced table is in the same bounded context.
- The FK represents a genuine containment or ownership relationship.
- The FK is not across an aggregate boundary (aggregates reference each other by ID, not FK).

**Example within `crm`:**

```sql
ALTER TABLE crm.deals ADD CONSTRAINT fk_deals_pipeline_id
  FOREIGN KEY (pipeline_id) REFERENCES crm.pipelines(id) ON DELETE RESTRICT;
```

**Counter-example (FK across aggregates — use logical reference instead):**

```sql
-- NOT acceptable within crm:
ALTER TABLE crm.activities ADD CONSTRAINT fk_activities_call_session_id
  FOREIGN KEY (call_session_id) REFERENCES voice.call_sessions(id);
-- Crosses schema boundary — use logical reference only.
```

---

## 8. ID Strategy

### 8.1 Primary Keys — UUIDv7

All primary keys use **UUIDv7** (time-ordered UUID). Column type: `UUID NOT NULL DEFAULT gen_uuid_v7()` (using a custom function until native PostgreSQL support; or application-generated before insert).

**Why UUIDv7 over UUIDv4:**
- Time-sortable — the physical index insert is approximately sequential, avoiding B-tree page splits on insert-heavy tables.
- Globally unique — no coordination needed across workers.
- Opaque — does not expose row count or creation sequence to the API layer.

**Why not `BIGSERIAL` / `IDENTITY`:**
- Integer sequences leak row counts and insert rates to API consumers.
- Sequences do not compose across multiple application instances without a coordination service.
- UUIDs allow application-side ID generation before the database write, enabling reliable idempotency keys.

### 8.2 ID Column Naming

| Usage | Convention | Example |
|---|---|---|
| Primary key | `id UUID` | `organizations.id` |
| FK to own schema table | `{singular_table_name}_id UUID` | `memberships.organization_id` |
| Logical FK to other schema | `{singular_aggregate_name}_id UUID` | `call_sessions.agent_version_id` |
| Idempotency key | `idempotency_key TEXT` | `call_jobs.idempotency_key` |
| External provider reference | `{provider}_{entity}_ref TEXT` | `call_sessions.provider_call_ref` |
| Opaque credential reference | `{credential_type}_credential_ref TEXT` | `integration_connections.credential_ref` |

### 8.3 Idempotency Keys

Pattern from Phase 4D and Phase 4F — every append-only write and every event-consumer write carries an idempotency key computed deterministically from the source data:

- `usage_events.idempotency_key`: `SHA-256(source_type + ':' + source_ref + ':' + metric + ':' + occurred_at_minute)` as hex string.
- `call_jobs.idempotency_key`: `SHA-256(campaign_id + ':' + campaign_contact_id + ':' + attempt_number)` as hex string.
- `webhook_deliveries`: `(webhook_endpoint_id, event_topic, payload_hash)` composite unique constraint.

All idempotency keys have a `UNIQUE` constraint. Duplicate inserts use `ON CONFLICT DO NOTHING`.

### 8.4 Public Identifiers

Where an entity's ID is surfaced in URLs or API responses, UUIDv7 is used directly. No separate "public ID" column is needed — UUIDv7 is already opaque. Slug-based URLs (e.g., organisation slugs) use a separate `slug TEXT UNIQUE` column.

### 8.5 Composite Uniqueness

Some entities have natural composite unique keys:

| Table | Composite unique | Rationale |
|---|---|---|
| `contacts` | `(organization_id, phone_e164)` | Phase 4C invariant — one contact per phone per org |
| `memberships` | `(organization_id, user_id)` | One membership per user per org |
| `usage_events` | `(idempotency_key)` | Deduplication |
| `call_jobs` | `(idempotency_key)` | No duplicate dial |
| `usage_records` | `(organization_id, metric, period_start)` | One record per metric per period |
| `quota_configs` | `(organization_id, metric)` | One config per metric per org |
| `customer_memories` | `(organization_id, contact_id)` | One memory per contact per org |
| `billing_accounts` | `(organization_id)` | One billing account per org |
| `workflow_executions` | `(session_id)` | One execution per call session |
| `organizations` | `(slug)` | Global slug uniqueness |
| `api_keys` | `(key_hash)` | Authentication lookup |
| `invoice_number_sequences` | `(organization_id, fiscal_year)` | Gapless numbering |
| `invoices` | `(organization_id, fiscal_year, invoice_number)` | Gapless uniqueness |

---

## 9. Timestamp Strategy

### 9.1 Storage Standard

**All timestamps are stored in UTC as `TIMESTAMPTZ` (timestamp with time zone).** Never `TIMESTAMP WITHOUT TIME ZONE`. Never local wall-clock time without timezone semantics.

`TIMESTAMPTZ` in PostgreSQL always stores the moment in UTC internally; the displayed value depends on the client's `TimeZone` setting. The application always uses UTC for all reads and writes.

### 9.2 Standard Timestamp Columns

Every mutable table has:

```
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

`updated_at` is maintained by a trigger (single shared trigger function `set_updated_at()` applied per table). Append-only tables have `created_at` only — no `updated_at`.

### 9.3 Timezone-Aware Operational Values

| Column type | When used | Convention |
|---|---|---|
| `TIMESTAMPTZ` | All event timestamps, audit timestamps, billing timestamps | Always UTC |
| `TIMESTAMPTZ` + `timezone TEXT` | Calling windows, appointment start/end, campaign scheduling | Store in UTC; companion column records the IANA timezone in which the window was configured |
| `DATE` | Billing periods, fiscal year, close date of deals | Calendar date; fiscal calendar is configured per org |
| `TIME WITHOUT TIME ZONE` | Calling window start/end time of day | Local time-of-day; evaluated with the companion timezone column |
| `INTERVAL` | Duration values (call duration, task delay) | Always a PostgreSQL `INTERVAL` or `INTEGER` seconds |

### 9.4 India-Specific Fiscal Year

India's fiscal year runs 1 April – 31 March. `invoice_number_sequences` uses `fiscal_year INTEGER` (e.g., `2024` for the FY2024-25 year) to derive the sequence period:

- `fiscal_year = EXTRACT(YEAR FROM (date - INTERVAL '3 months'))` — subtracting 3 months maps April → year Y to January → year Y.
- This is computed in application code; stored as a plain integer in the sequence table.
- For global tenants, the fiscal year start is configurable (January = calendar year default) and stored on `organizations`.

### 9.5 Timezone Representation

IANA timezone identifiers (e.g., `'Asia/Kolkata'`) are stored as `TEXT`. PostgreSQL validates them at runtime if used in `AT TIME ZONE` expressions. A separate reference table `reference.timezones` is not maintained in V1 — validation occurs at the application layer using the Python `zoneinfo` module before write.

### 9.6 Date/Time Columns Required for Phase 5B+

| Column pattern | Tables |
|---|---|
| `started_at`, `ended_at` | `call_sessions`, `conversations`, `workflow_executions` |
| `answered_at` | `call_sessions` |
| `occurred_at` | `activities`, `audit_events`, `usage_events`, `cost_entries` |
| `scheduled_start`, `scheduled_end` | `appointments` |
| `effective_from`, `effective_to` | `plan_versions`, `tax_rules` |
| `period_start`, `period_end` | `invoices`, `usage_records` |
| `trial_ends_at`, `cancelled_at` | `subscriptions` |
| `obtained_at`, `withdrawn_at`, `expires_at` | `consent_records` |
| `effective_from`, `expires_at` | `contact_suppressions` |
| `due_at` | `tasks`, `invoices` |

---

## 10. Currency Strategy

### 10.1 The Rule — Closed in Phase 4I

Every persisted monetary amount is a pair: `(amount, currency)`. No bare monetary numeric columns. No implicit currency assumption.

### 10.2 Column Conventions

```sql
-- Every monetary amount pair:
<field_name>_amount   NUMERIC(18,4) NOT NULL
<field_name>_currency CHAR(3)       NOT NULL  -- ISO 4217

-- Examples:
base_price_amount    NUMERIC(18,4) NOT NULL
base_price_currency  CHAR(3)       NOT NULL

total_due_amount     NUMERIC(18,4) NOT NULL
total_due_currency   CHAR(3)       NOT NULL

provider_cost_amount    NUMERIC(18,4)          -- nullable if cost not known
provider_cost_currency  CHAR(3)                -- nullable if cost not known
```

**Why `NUMERIC(18,4)` and not `NUMERIC(19,2)`:** four decimal places accommodate sub-cent per-token and per-second unit costs without rounding. Eighteen integer digits provides more than sufficient headroom for INR amounts at enterprise scale.

**`CHAR(3)` with a CHECK:** Phase 5B+ must add a `CHECK (currency ~ '^[A-Z]{3}$')` on all currency columns. A reference table of valid ISO 4217 codes is maintained in `billing.currencies` (platform-owned, no RLS) and validated at the application layer before insert — the CHECK is a last-resort guard.

### 10.3 V1 Default — INR

The default currency for new organisations is `INR`, set by `CreateOrganizationUseCase` from the signup context. It is **not** a column `DEFAULT` — a default would silently assign INR to future non-Indian tenants. Phase 5B must annotate `organizations.currency` with a comment: `-- Set explicitly at creation; no column default.`

### 10.4 Currency Is Write-Once on BillingAccount

`billing_accounts.currency` is set at creation and never updated. A `CHECK` trigger or application-layer constraint enforces immutability:

```sql
-- Enforced by a before-update trigger that raises if currency changes:
-- RAISE EXCEPTION 'billing_accounts.currency is immutable';
```

### 10.5 FX Rate Columns on CostEntry

```sql
-- cost_entries additional columns:
amount_in_billing_currency_amount    NUMERIC(18,4)
amount_in_billing_currency_currency  CHAR(3)
fx_rate_used                         NUMERIC(12,6)  -- e.g. 83.45 (INR per 1 USD)
fx_rate_source                       TEXT           -- e.g. 'manual_v1', 'openexchangerates'
fx_rate_captured_at                  TIMESTAMPTZ
```

### 10.6 Monetary Columns by Table — Phase 5 Inventory

| Table | Monetary columns (pairs) |
|---|---|
| `plan_versions` | `base_price` |
| `plan_prices` | `unit_price` (for overage rates per metric) |
| `invoices` | `subtotal`, `total_credits`, `total_tax`, `total_due` |
| `invoice_lines` | `unit_price`, `line_total` |
| `tax_lines` | `taxable_amount`, `tax_amount` |
| `payment_attempts` | `amount` |
| `credits` | `amount` |
| `cost_entries` | `amount` (provider currency), `amount_in_billing_currency` (nullable) |
| `deals` | `value` (nullable) |
| `campaign_outcomes` | `total_cost`, `estimated_revenue` (nullable), `profit` (nullable) |
| `usage_cost_daily` (projection) | `provider_cost`, `billed_amount` |
| `billing_revenue_monthly` (projection) | `revenue`, `cost`, `profit` |
| `roi_by_campaign` (projection) | `total_cost`, `estimated_revenue`, `profit` |

---

## 11. GST / Tax Strategy

### 11.1 Design Principle Reaffirmed

No tax rate, slab, threshold, or regulatory constant appears in column `DEFAULT` values, `CHECK` constraints, `ENUM` types, or application constants. Tax is computed by reading versioned, dated `tax_rules` rows.

### 11.2 Key Tables

| Table | Schema | Purpose |
|---|---|---|
| `tax_categories` | billing | HSN/SAC codes — platform reference data |
| `tax_rules` | billing | Versioned rates by regime, category, and jurisdiction |
| `tax_profiles` | billing | Per-organisation GST registration, GSTIN, place of supply |
| `invoices` | billing | Carries `tax_profile_snapshot` (JSONB), `place_of_supply`, `invoice_kind`, `invoice_number`, `e_invoice_ref` |
| `tax_lines` | billing | One row per tax component per taxable invoice line group |
| `invoice_number_sequences` | billing | Gapless, per-org, per-fiscal-year number allocation |

### 11.3 Tax Rule Structure

`tax_rules` uses a `components JSONB` column (array of `{component_code, rate_percent, applies_to}`) to avoid encoding CGST/SGST/IGST as fixed columns. A new tax regime or component type is a new data row, not a schema migration.

### 11.4 GSTIN Handling

- Stored as `TEXT` — format validation is application-layer only (`^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$` for India). Do not make the regex a `CHECK` — it would hard-code the format into the schema.
- Treated as a business identifier, not a secret. Encrypted at rest with the rest of the row (database-level encryption or column encryption as per deployment config).
- **Not** a sensitive field per PII definitions — it is a publicly verifiable registration number.
- Masked in log output (same treatment as phone numbers).

### 11.5 Invoice Numbering

`invoice_number_sequences` provides row-locked gapless allocation:

```
invoice_number_sequences
├── id               UUID
├── organization_id  UUID NOT NULL
├── fiscal_year      INTEGER NOT NULL  -- 2024 = FY2024-25 for India
├── next_number      INTEGER NOT NULL DEFAULT 1
├── prefix           TEXT              -- e.g. 'INV', 'CN' (credit note)
└── UNIQUE (organization_id, fiscal_year, prefix)
```

Allocation uses `UPDATE ... RETURNING next_number` with `SELECT ... FOR UPDATE` — the row lock guarantees gaplessness. Phase 5B DDL for this table must document the locking pattern.

---

## 12. Embedding / Vector Strategy

### 12.1 Decision Summary

| Parameter | Value | Authority |
|---|---|---|
| Provider | OpenAI | Phase 4I ADR-INDIA-014 |
| Model | `text-embedding-3-large` | Phase 4I ADR-INDIA-014 |
| Dimensions | **1536** (explicitly requested via `dimensions=1536`) | Phase 4I ADR-INDIA-015 |
| Native model default | 3072 (NOT used) | Phase 4I §14.2 |
| Distance metric | Cosine | Phase 4I ADR-INDIA-016 |
| Index type | HNSW | Phase 4I ADR-INDIA-016 |
| HNSW initial params | `m=16`, `ef_construction=64` | Phase 4G §18.5 |
| Storage | `document_chunks.embedding vector(1536)` | Phase 4I |

**Critical implementation guard (Phase 5B annotate prominently):** `document_chunks.embedding` is `vector(1536)`. Inserting a 3072-dimension vector causes a type error. The adapter must assert `len(returned_vector) == 1536` before attempting insertion.

### 12.2 Vector Column

```
document_chunks.embedding  vector(1536) NOT NULL
```

pgvector type `vector(1536)` enforces the dimension at the database level — any mismatch on insert raises an error rather than silently truncating or padding.

### 12.3 Embedding Provenance Columns

Every `document_chunks` row carries:

```
embedding_version_id    UUID NOT NULL   -- FK to knowledge.embedding_versions.id
embedding_provider      TEXT NOT NULL   -- e.g. 'openai'
embedding_model         TEXT NOT NULL   -- e.g. 'text-embedding-3-large'
embedding_dimension     INTEGER NOT NULL -- always 1536 in V1
content_hash            CHAR(64) NOT NULL -- SHA-256 hex of the chunk text
embedded_at             TIMESTAMPTZ NOT NULL
```

`embedding_dimension` is denormalised for validation: a `CHECK (embedding_dimension = 1536)` can be added in V1. When a V2 embedding version is introduced, this constraint must be reviewed/relaxed as part of that migration.

### 12.4 Embedding Versioning

`knowledge.embedding_versions` is the registry of embedding model versions:

```
embedding_versions
├── id                  UUID NOT NULL DEFAULT gen_uuid_v7()
├── version_label       TEXT NOT NULL UNIQUE  -- e.g. 'v1-openai-3large-1536'
├── provider            TEXT NOT NULL
├── model_name          TEXT NOT NULL
├── dimension           INTEGER NOT NULL
├── distance_metric     TEXT NOT NULL         -- 'cosine'
├── language_coverage   TEXT[] NOT NULL       -- BCP 47 array
├── status              TEXT NOT NULL         -- 'ACTIVE', 'DEPRECATED', 'RETIRED'
├── migration_status    TEXT                  -- 'NOT_STARTED', 'IN_PROGRESS', 'VALIDATING', 'COMPLETE'
├── created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
└── retired_at          TIMESTAMPTZ
```

Platform-owned; no RLS; readable by all roles.

### 12.5 Re-Embedding / Migration Rule

**Different embedding dimensions MUST NOT share the `document_chunks.embedding` column.**

If a future embedding model uses a dimension other than 1536:
- A new `embedding_versions` row is created with the new dimension.
- A new vector column (or a new table) is used for storage — the `document_chunks` table is not structurally altered to mix dimensions.
- Both versions coexist during migration; the knowledge base's `embedding_version_id` controls which version is queried.
- Old version transitions to `DEPRECATED` after validation, then `RETIRED`.

The physical migration strategy (new column vs. new table) is decided at the time of the model change. This document specifies the invariant, not the mechanism.

### 12.6 HNSW Index Parameters

```sql
-- Phase 5B will produce the exact DDL; this is the specification:
CREATE INDEX idx_document_chunks_embedding
  ON knowledge.document_chunks
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

These are initial parameters. They should be re-evaluated after the first 1M chunk insertions using pgvector's built-in query performance measurement.

`ef_search` (query-time parameter) defaults to 40 in pgvector — can be adjusted per session without a migration: `SET hnsw.ef_search = 80;` in analytics or bulk-retrieval contexts.

### 12.7 Hybrid Search Indexes

```sql
-- Full-text search on chunk text:
CREATE INDEX idx_document_chunks_fts
  ON knowledge.document_chunks
  USING gin (to_tsvector('simple', text_content));
-- 'simple' dictionary is used for cross-language compatibility; Tamil and Telugu
-- do not have native PostgreSQL text search dictionaries.
-- Application-side stemming and tokenisation (if required) happens before the query.

-- Pre-filter B-tree:
CREATE INDEX idx_document_chunks_tenant_kb
  ON knowledge.document_chunks (organization_id, knowledge_base_id);
```

---

## 13. Indexing Standards

### 13.1 Principles

1. **Index what is queried, not everything.** Unnecessary indexes add write overhead to every insert and update.
2. **Document the query that justifies each index.** If no use case query is identified, do not create the index.
3. **Tenant-first composite indexes.** For all tenant-scoped tables, the first column of every composite index is `organization_id`. This allows partition pruning even when RLS is applied.
4. **Partial indexes where the predicate is selective.** Partial indexes on status columns significantly reduce index size for active-subset queries.
5. **Prefer B-tree for equality and range.** GIN for JSONB containment and full-text. GiST for geometric types. HNSW for vectors.
6. **Avoid indexing low-cardinality columns alone.** An index on `status` with 3 distinct values across millions of rows provides little benefit without a leading `organization_id`.
7. **BRIN for append-only time-series tables.** `BRIN` (Block Range INdex) on `occurred_at` / `created_at` for partitioned append-only tables is far smaller than B-tree and effective for sequential-scan range queries on sorted data.
8. **Monitor `pg_stat_user_indexes`.** Phase 22 (Deployment) must configure Grafana alerts for unused indexes (zero scans after 30 days of production traffic).

### 13.2 Standard Index Naming Convention

```
idx_{table}_{column(s)}[_{type}][_{partial_qualifier}]

Examples:
idx_contacts_org_phone          -- B-tree on (organization_id, phone_e164)
idx_call_sessions_org_status    -- B-tree on (organization_id, status)
idx_call_sessions_active        -- Partial B-tree on (organization_id) WHERE status = 'ACTIVE'
idx_document_chunks_embedding   -- HNSW on (embedding)
idx_document_chunks_fts         -- GIN on to_tsvector(text_content)
idx_audit_events_org_occurred   -- BRIN on (organization_id, occurred_at)
idx_contacts_phone_unique       -- UNIQUE on (organization_id, phone_e164) -- preferred over constraint name
```

### 13.3 Required Indexes — Cross-Schema Standard

Every tenant-scoped table must have at minimum:
1. `PRIMARY KEY (id)` — implicitly a UNIQUE B-tree index.
2. Index on `(organization_id)` — required for RLS filter pushdown.
3. Index on `(organization_id, created_at)` for time-ordered queries if the table is queried by recency.

### 13.4 Critical Indexes — Identified from Phase 4G and Phase 4I

| Table | Index specification | Justification |
|---|---|---|
| `contacts` | `UNIQUE (organization_id, phone_e164)` | Deduplication invariant |
| `contacts` | `(organization_id, lead_status)` | Lead list filtering |
| `contacts` | `(organization_id, lead_score_cache)` | Score-sorted views |
| `call_sessions` | `(organization_id, status)` partial WHERE status = 'ACTIVE' | Active call count |
| `call_sessions` | `(organization_id, agent_version_id, started_at)` | Agent performance queries |
| `campaign_contacts` | `(campaign_id, status)` | Executor tick |
| `campaign_contacts` | `(campaign_id, next_attempt_at)` WHERE status = 'RETRY_SCHEDULED' | Retry queue recovery |
| `call_jobs` | `UNIQUE (idempotency_key)` | Duplicate call prevention |
| `document_chunks` | HNSW on `embedding` | ANN vector search |
| `document_chunks` | `(organization_id, knowledge_base_id)` | Pre-filter for vector search |
| `document_chunks` | GIN on `to_tsvector('simple', text_content)` | Keyword hybrid search |
| `audit_events` | BRIN on `(organization_id, occurred_at)` | Time-range compliance queries |
| `usage_events` | BRIN on `(organization_id, occurred_at)` | Usage aggregation |
| `api_keys` | `UNIQUE (key_hash)` | Authentication |
| `organizations` | `UNIQUE (slug)` | URL routing |
| `memberships` | `UNIQUE (organization_id, user_id)` | Membership invariant |
| `workflow_executions` | `UNIQUE (session_id)` | One execution per call |
| `invoices` | `UNIQUE (organization_id, fiscal_year, invoice_number)` | Gapless numbering |
| `contact_suppressions` | `(organization_id, phone_e164, status)` | Dispatch-time check |
| `contact_suppressions` | `(phone_e164, scope)` WHERE scope IN ('PLATFORM', 'REGULATORY') | Cross-tenant lookup |
| `consent_records` | `(organization_id, contact_id, purpose, channel, recorded_at DESC)` | Latest consent |
| `tax_rules` | `(regime, tax_category_id, effective_from DESC)` | Rule resolution |
| `language_evaluation_records` | `(language, provider_id, capability, evaluated_at DESC)` | Provider selection |
| `prompt_templates` | `UNIQUE (organization_id, name)` | Name uniqueness per tenant |

---

## 14. Partitioning Standards

### 14.1 When to Partition

Partition a table when **all three** of the following are true:
1. Expected row count exceeds 50M rows within 2 years at projected scale.
2. Data has a natural time or category dimension suitable for pruning.
3. The table is queried primarily within time or category ranges (not point lookups by PK alone).

Do not partition small configuration tables, reference data, or low-volume tables — partitioning adds operational overhead without benefit.

### 14.2 Partitioned Tables — Phase 5 Specification

| Table | Schema | Type | Key | Granularity | Retention | Notes |
|---|---|---|---|---|---|---|
| `usage_events` | billing | RANGE | `occurred_at` | Monthly | 90d hot, 7yr cold | Very high volume — one per billable unit |
| `cost_entries` | billing | RANGE | `occurred_at` | Monthly | 90d hot, 7yr cold | Same volume as usage_events |
| `audit_events` | audit | RANGE | `occurred_at` | Monthly | 1yr hot, 7yr cold | Compliance retention |
| `webhook_deliveries` | webhooks | RANGE | `created_at` | Monthly | 30d DELIVERED, 90d DEAD_LETTER | Purge by status |
| `call_sessions` | voice | RANGE | `started_at` | Monthly | 12mo hot, 7yr cold | |
| `transcript_segments` | voice | RANGE | `created_at` | Monthly | 2yr | Append-only, per STT fragment |
| `campaign_contacts` | campaign | LIST | `campaign_id` | Per campaign | Campaign + 2yr | Very high volume per batch |
| `document_chunks` | knowledge | LIST | `knowledge_base_id` | Per KB | KB lifetime | Vector storage |
| `activities` | crm | RANGE | `occurred_at` | Monthly | 5yr | Append-only |
| `consent_records` | crm | RANGE | `recorded_at` | Monthly | Org retention policy | Append-only |

### 14.3 Partitioning Design Rules

**RANGE monthly partitions:**
- Parent table: `CREATE TABLE ... PARTITION BY RANGE (occurred_at)`.
- Child table naming: `{table}_{YYYY}_{MM}` — e.g. `usage_events_2025_01`.
- Index on partition key: inherited from parent (does not need to be re-created per child for RANGE partitions with PostgreSQL 12+).
- Tenant index: `(organization_id, occurred_at)` — BRIN index on parent propagates to children.
- Pre-create partitions: create 3 months ahead in a scheduled maintenance job.
- Drop policy: drop partitions past the retention period in the maintenance job; archive to S3/cold storage first.

**LIST partitions (campaign_contacts, document_chunks):**
- Parent: `CREATE TABLE ... PARTITION BY LIST (campaign_id)`.
- Child table: one per campaign — `campaign_contacts_{campaign_id}`.
- Created when the Campaign transitions to PREPARING; dropped when the campaign + retention window expires.
- **Practical concern:** thousands of campaigns → thousands of partition child tables. PostgreSQL handles this at scale, but `pg_partman` or a dedicated partition management service must be used. Phase 5B must address this.

**Alternative for campaign_contacts at scale:** RANGE by `created_at` (monthly) with `organization_id` and `campaign_id` as leading composite index. The LIST-by-campaign approach is cleaner for data lifecycle (drop the partition when the campaign is archived) but requires partition management automation. Phase 5B makes the final call.

### 14.4 Index Strategy on Partitioned Tables

- Primary key index is created on the parent table and inherited.
- Unique indexes on partitioned tables must include the partition key (PostgreSQL requirement). If the natural unique key does not include the partition key, use a unique partial index strategy per partition.
- BRIN indexes on time-partitioned tables are very efficient — create on parent.
- HNSW index on `document_chunks.embedding` is created per-partition or on the parent; current pgvector best practice (v0.7+) supports parent-level HNSW index creation.

### 14.5 Archival Strategy

Hot-tier Postgres retention and cold-tier archival are separate concerns:

| Tier | Where | Mechanism |
|---|---|---|
| Hot (active queries) | Partitioned Postgres table | Partition included in query path |
| Cold (retention/compliance) | S3 / Supabase Storage | Partition exported as Parquet before drop |
| Deletion | Postgres partition dropped | After cold archive confirmed |

Cold archive format: **Apache Parquet** (columnar, compressed, future-compatible with ClickHouse `SELECT ... FROM s3(...)`). This is the clean ClickHouse migration path — no ETL redesign required.

---

## 15. Append-Only Standards

### 15.1 Append-Only Tables

| Table | Schema | Rationale |
|---|---|---|
| `audit_events` | audit | Tamper evidence — immutable after creation |
| `usage_events` | billing | Financial audit — immutable metering record |
| `cost_entries` | billing | Financial audit — immutable cost record |
| `transcript_segments` | voice | Call record — immutable after finalization (partial segments updated by `ON CONFLICT DO UPDATE` before finalization) |
| `lead_score_records` | crm | Score history — full trail preserved |
| `activities` | crm | CRM activity log — immutable after creation |
| `webhook_deliveries` | webhooks | Delivery audit — each attempt is a new row |
| `consent_records` | crm | Legal evidence — immutable (withdrawal = new row) |
| `contact_suppressions` | crm | Suppression evidence — status transitions = new rows |

### 15.2 Enforcement

```sql
-- Database-level enforcement (not just a convention):
REVOKE UPDATE ON <schema>.<append_only_table> FROM app_api, app_worker;
REVOKE DELETE ON <schema>.<append_only_table> FROM app_api, app_worker;

-- Only app_migration and app_platform_admin may update/delete (for corrections under extreme circumstances with full audit trail).
```

**Correction pattern:** if a row in an append-only table must be corrected (e.g., an audit event recorded the wrong action), the correction is performed by `app_platform_admin` with a corresponding audit event recording the correction itself. There is no silent UPDATE.

### 15.3 Partial Transcript Segment Handling

`transcript_segments` are partially append-only: partial STT results (`is_partial = true`) with the same `(transcript_id, sequence_number)` as a final result may be overwritten by `ON CONFLICT (transcript_id, sequence_number) DO UPDATE SET text = EXCLUDED.text, is_partial = FALSE, ...` — but only **before** the transcript is finalised. After `transcripts.status = 'COMPLETED'`, even partial segments are immutable.

This is the one permitted `ON CONFLICT DO UPDATE` on an otherwise append-only table — documented here as an explicit exception.

---

## 16. Soft Delete Standards

### 16.1 When Soft Delete Is Used

Soft deletion is used only where an entity must survive deletion for:
- **Audit reference**: an audit event references an entity that has been "deleted".
- **Historical query accuracy**: call history and campaign outcomes must remain meaningful even after a contact is deleted.
- **Idempotency safety**: re-creation should be distinguished from existence.

| Table | Soft delete approach | Rationale |
|---|---|---|
| `contacts` | `deleted_at TIMESTAMPTZ` (nullable) | Call history, campaign history, consent records reference ContactId |
| `documents` | `deleted_at TIMESTAMPTZ` + `status = 'DELETED'` | Vector chunks must be cleaned up; document remains as a tombstone |
| `recordings` | `status = 'DELETED'` (StorageRef cleared) | Recording aggregate retained for audit; binary deleted from S3 |
| `agents` | `status = 'DEPRECATED'` | Soft lifecycle via status; no deleted_at needed |
| `users` | `deleted_at TIMESTAMPTZ` | GDPR erasure — PII cleared but row retained for audit |

### 16.2 When Hard Delete Is Used

Most tables use hard delete or terminal status without a `deleted_at` column:
- `campaigns`, `deals`, `tasks`, `notes`, `appointments`, `workflow_definitions` — soft lifecycle via terminal status.
- `webhook_deliveries`, `call_jobs` — never deleted; aged out by partition drop.
- `api_keys` — `status = 'REVOKED'`; never deleted (audit).

### 16.3 GDPR / Data Subject Erasure

For `contacts`, erasure means: `phone_e164 = NULL`, `primary_email = NULL`, `full_name = '[ERASED]'`, `deleted_at = NOW()`, audit event `DATA_SUBJECT_ERASED`. The row is retained with PII cleared. This satisfies both the erasure requirement (PII gone) and audit requirements (record that this contact existed and was erased).

---

## 17. Audit Standards

### 17.1 What Is Audited

All operations in the following categories produce an `audit_events` row:

| Category | Examples |
|---|---|
| Authentication | Login, logout, MFA, failed attempts |
| Authorization | Permission changes, role assignments |
| Organisation management | Create, update, suspend, reactivate |
| Agent management | Create, publish, deprecate |
| Prompt management | Publish, rollback |
| Campaign management | Create, start, pause, cancel, block |
| Contact suppression | Add, lift |
| Consent | Record, withdraw |
| Compliance policy | Update |
| Recording policy | Change |
| Billing | Subscription changes, invoice, payment, refund |
| Tax configuration | GSTIN update, tax rule application |
| API keys | Issue, revoke |
| Integrations | Connect, disconnect |
| Plugins | Register, approve, install, uninstall |
| Data export | Subject export requests |
| Data deletion | Contact erasure, document deletion, recording deletion |
| Admin operations | Any `app_platform_admin` action |
| Plugin lifecycle | Register, approve, reject, install, uninstall |
| Embedding version | Create, migrate |

### 17.2 Audit Event Schema (preview — full DDL in Phase 5B)

```
audit.audit_events
├── id                UUID            PRIMARY KEY
├── organization_id   UUID            (nullable for platform events)
├── actor_type        TEXT            'USER', 'API_KEY', 'AI_AGENT', 'SYSTEM'
├── actor_ref         UUID            (nullable — UserId, ApiKeyId, etc.)
├── actor_name        TEXT            (display name at time of event)
├── action_kind       TEXT            (from ActionKind enum — TEXT not ENUM for extensibility)
├── resource_type     TEXT            (aggregate name)
├── resource_id       UUID            (nullable)
├── resource_snapshot JSONB           (nullable — relevant fields, no secrets, no raw PII)
├── outcome           TEXT            'SUCCESS', 'FAILURE', 'PARTIAL'
├── failure_reason    TEXT            (nullable)
├── ip_address        INET            (nullable — from request context)
├── user_agent        TEXT            (nullable)
├── session_id        TEXT            (nullable — application session)
├── occurred_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
└── chain_hash        CHAR(64)        (SHA-256 of previous event hash + this row's content)
```

`chain_hash` enables tamper-detection — a broken hash chain signals a deleted or modified event. Computed in the application layer (not a trigger) and verified by the compliance audit tool.

**What is NOT stored in `resource_snapshot`:** raw secrets, full PII fields (phone number, email address), full call transcripts, full AI summaries. References by ID only. Masked display values where required for context.

### 17.3 Retention and Cold Archive

Hot: 1 year in Postgres (monthly partitioned). Cold: 7 years in S3 as Parquet. Compliance reporting queries may require reading from both tiers — Phase 22 (Deployment) must configure a query federation approach for cold archive access.

---

## 18. Redis Data Ownership Rules

### 18.1 Classification

| Redis use | Source of truth | TTL | Rebuild strategy | Failure behaviour |
|---|---|---|---|---|
| Live call session state | `voice.call_sessions` | Call duration + 5min | Load from Postgres on cache miss | Call may have higher first-turn latency |
| Workflow execution cursor | `workflow.workflow_executions` | Call duration + 10min | Load from Postgres on miss | One turn re-run cost |
| RBAC permission cache | `organization.role_permissions` | 5min | Reload from DB; explicit invalidation on role change | Slightly stale permissions until TTL; acceptable |
| API key auth cache | `identity.api_keys` | 5min | Reload from DB; explicit invalidation on revoke | Risk: revoked key usable up to 5min — `apikey.revoked` event must clear cache immediately |
| Prompt render cache | `workflow.prompt_templates` | 5min | Reload from DB | Higher first-render latency |
| Embedding query cache | Query-embedding for RAG | 1 hour | Re-embed the query | Slightly higher RAG query latency |
| Agent version cache | `voice.agent_versions` | 1 hour | Reload from DB (version is immutable — long TTL safe) | None — immutable data |
| Usage quota counter | `billing.usage_records` | Billing period | Rebuilt from Postgres nightly reconciliation | Brief over-consumption possible; corrected by reconciliation |
| Campaign call queue | `campaign.campaign_contacts` | Campaign lifetime | Rebuilt from `status = 'PENDING'` contacts | Up to 5min dispatcher gap |
| Campaign retry queue | `campaign.campaign_contacts` | Campaign lifetime | Rebuilt from `status = 'RETRY_SCHEDULED'` | Retry window delay |
| Campaign concurrency counter | `campaign.call_jobs` | Rolling | Reconciled from `call_jobs.status = 'DISPATCHED'` | Brief over/under-counting |
| Campaign executor lock | (no Postgres equivalent) | Tick duration (~10s) | Re-acquire on next tick | At most one missed tick |
| Session memory turns | `workflow.session_memories` | Call duration | Reconstructed from Postgres after call ends | If Redis lost mid-call: memory for that session is post-call summary only |
| Provider health state | `voice.provider_configs` | 60s rolling | Health polling re-evaluates | Provider selection uses stale health data briefly |
| Suppression cache | `crm.contact_suppressions` | 1 hour | Reload on `suppression.added` / `suppression.lifted` event; fallback: DB query | At most 1 hour stale suppression — acceptable for dispatch-time check given that new suppressions also invalidate immediately via event |
| Consent cache | `crm.consent_records` | 1 hour | Invalidation on consent events | Same as suppression |
| Localisation profile cache | `organization.organizations` | 15min | Reload from DB | Slightly stale locale during window |
| Compliance policy cache | `organization.compliance_policies` | 15min | Invalidated on `compliance.policy_updated` | Brief stale policy |
| FX rate cache | `billing.fx_rates` | 24 hours | Manual refresh or scheduled job | Stale FX used for cost recording — acceptable for V1 manual rate management |
| Language evaluation cache | `voice.language_evaluation_records` | 1 hour | Reload from DB | Provider selection may briefly include a conditionally-evaluated provider |

### 18.2 Redis Namespace Catalogue (Complete)

All keys follow: `{purpose}:{organization_id_or_global}:{...identifiers}`

| Key pattern | Organisation scope |
|---|---|
| `session:{org}:{call_id}` | Per-org |
| `workflow_exec:{session_id}` | Per-org (session_id carries org) |
| `rbac:permissions:{org}:{user_id}` | Per-org |
| `apikey:{key_hash}` | Global (user is org-scoped internally) |
| `prompt_cache:{prompt_id}:{env}:{version_hash}` | Per-org (prompt_id is org-scoped) |
| `kb_embed:{sha256(query_text)}` | Global (embedding is language-model scoped, not org-scoped) |
| `agent_version:{version_id}` | Global (version is immutable platform data) |
| `usage:quota:{org}:{metric}` | Per-org |
| `campaign:queue:{org}:{campaign_id}` | Per-org |
| `campaign:retry_queue:{org}:{campaign_id}` | Per-org |
| `campaign:concurrency:{org}:{campaign_id}` | Per-org |
| `campaign:lock:{campaign_id}` | Global (prevents concurrent executors) |
| `session_memory:{session_id}` | Per-org (session_id is org-scoped) |
| `provider_health:{provider_id}` | Global |
| `suppression:{org}:{phone_e164}` | Per-org |
| `consent:{org}:{contact_id}:{purpose}` | Per-org |
| `localization:{org}` | Per-org |
| `compliance_policy:{org}` | Per-org |
| `lang_eval:{language}:{capability}` | Global |
| `fx_rate:{from}:{to}` | Global |
| `plugin:ratelimit:{org}:{plugin_id}` | Per-org |
| `feature_flag:{flag_key}:{org}` | Per-org |

### 18.3 Redis Failure Behaviour

On Redis failure, the application must degrade gracefully:
- **Session state lost:** call continues from the Postgres checkpoint (at most one in-flight turn is re-processed).
- **Queue lost:** campaign executor falls back to Postgres query for PENDING contacts — slower but correct.
- **Quota counter lost:** reconciliation task rebuilds from Postgres. Brief over-consumption is acceptable; Postgres `usage_records` is the source of truth for billing.
- **Cache lost:** application falls through to Postgres reads — higher latency, no data loss.

No data is permanently lost on Redis failure. Recovery is autonomous.

---

## 19. Object Storage Strategy

### 19.1 Namespace Structure

```
org/{organization_id}/
├── recordings/
│   └── {year}/{month}/{call_id}.{codec}       -- call audio
├── knowledge/
│   └── {kb_id}/
│       └── {doc_id}.{ext}                      -- source documents
│       └── {doc_id}/parsed.txt                 -- intermediate parsed text (deleted after indexing)
├── campaigns/
│   └── {campaign_id}/imports/{job_id}.csv      -- CSV uploads (deleted after successful import)
├── analytics/
│   └── exports/{report_id}.csv                 -- on-demand exports (7-day TTL)
├── consent/
│   └── {consent_id}/{evidence_id}.{ext}        -- consent evidence artifacts
├── data_subject/
│   └── {request_id}/export.zip                 -- subject data export packages
└── invoices/
    └── {fiscal_year}/{invoice_number}.pdf       -- rendered tax invoices
```

### 19.2 Database Stores Metadata Only

The database stores:
- `recordings.storage_ref TEXT` — the S3 object path.
- `documents.source_ref TEXT` — the S3 object path.
- `consent_records.evidence JSONB` with `reference_uri TEXT` — the S3 object path.

Binary content is never stored in PostgreSQL. No `BYTEA` columns for audio, PDF, or image data.

### 19.3 Access Pattern

Presigned URLs are generated by the application layer with a short TTL (e.g., 15 minutes for recordings, 24 hours for invoice PDFs). The URL is never stored in the database — it is generated on-demand from the stored `storage_ref`.

### 19.4 India Region Deployment

For `DataResidencyProfile = 'INDIA_ENTERPRISE'`:
- S3 buckets are provisioned in India-region (e.g., `ap-south-1` on AWS).
- The `region_ref` abstract identifier is mapped to the concrete region in infrastructure configuration — never in domain code.
- Database and Redis are also provisioned in the same region.

Phase 5 DDL must not assume any specific cloud region name. The `region_ref` value `'in-primary'` is the abstraction.

---

## 20. Analytics / ClickHouse Boundary

### 20.1 V1 Analytics Storage — PostgreSQL Only

All V1 analytics projections live in the `analytics` schema in PostgreSQL. ClickHouse is not a V1 dependency.

### 20.2 Migration Readiness — AnalyticsWritePort

The `AnalyticsWritePort` abstraction (Phase 4G) means that analytics projection writes go through a port:
```
AnalyticsEventHandler → AnalyticsWritePort → PostgresAnalyticsAdapter (V1)
                                           → ClickHouseAnalyticsAdapter (V3 future)
```

Switching to ClickHouse is an adapter swap — no event handler, no projection table definition, no business logic changes.

### 20.3 ClickHouse Candidates for Future Migration

| Table | Migration priority | Notes |
|---|---|---|
| `billing.usage_events` | High | Billions of rows at platform scale |
| `billing.cost_entries` | High | Same volume as usage_events |
| `voice.call_sessions` (historical) | Medium | Monthly cold partitions are natural migration units |
| `analytics.*` projections | Low | Postgres handles well for hundreds of concurrent users |
| `audit.audit_events` | Low | Compliance queries need SQL; ClickHouse is less suited |

The cold archive Parquet files (§14.5) are the migration input for ClickHouse — no ETL redesign required.

---

## 21. Naming Conventions

### 21.1 Schema Names

All lowercase, single word: `identity`, `organization`, `voice`, `crm`, `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, `audit`.

No underscores in schema names. No camelCase.

### 21.2 Table Names

`snake_case`, plural, descriptive noun phrase. No generic names ("items", "records", "data").

```
contacts                -- not "contact" or "crm_contacts"
call_sessions           -- not "calls" (ambiguous) or "call_session"
agent_versions          -- not "agents_versions"
campaign_contacts       -- not "campaign_leads"
webhook_deliveries      -- not "webhook_logs"
language_evaluation_records  -- descriptive even if long
```

### 21.3 Column Names

`snake_case`. Consistent across all tables for the same concept:

| Concept | Column name |
|---|---|
| Primary key | `id` |
| Tenant foreign key | `organization_id` |
| Creation time | `created_at` |
| Modification time | `updated_at` |
| Deletion time | `deleted_at` |
| Status | `status` |
| External provider reference | `{provider}_{entity}_ref` |
| Credential reference | `{credential_type}_credential_ref` |
| Monetary amount | `{field}_amount` + `{field}_currency` |
| Phone number | `phone_e164` |
| Idempotency key | `idempotency_key` |
| Version number | `version_number` |
| Logical FK to other schema | `{aggregate_name}_id` |

### 21.4 Primary Key Columns

Always `id UUID NOT NULL DEFAULT gen_uuid_v7()`. Never `{table_name}_id` as the primary key column name — that pattern is for FK columns.

### 21.5 Constraint Names

```
pk_{table}                            -- primary key
uq_{table}_{column(s)}                -- unique constraint
fk_{table}_{column}_{ref_table}       -- foreign key (within schema)
chk_{table}_{column}_{rule}           -- check constraint
```

### 21.6 Index Names

```
idx_{table}_{column(s)}[_{type_suffix}][_{partial}]

Type suffixes:
  _brin     -- for BRIN indexes
  _gin      -- for GIN indexes
  _hnsw     -- for HNSW vector indexes
  _unique   -- when an index enforces uniqueness (vs. the constraint name)

Partial index suffix:
  _active   -- WHERE status = 'ACTIVE'
  _pending  -- WHERE status = 'PENDING'
```

### 21.7 Enum / Reference Data Strategy

**Use `TEXT` columns with application-layer validation, not PostgreSQL `ENUM` types, for domain status fields.** This applies to:
- Call status, conversation status, agent status, deal status, task status, campaign status, invoice status, subscription status, import status, etc.
- Audit action kinds, event topics, provider categories.

**Why `TEXT` over `ENUM`:**
- Adding a new ENUM value requires `ALTER TYPE ... ADD VALUE` — which cannot be run inside a transaction in PostgreSQL, making it harder to deploy atomically.
- ENUMs are hard to remove values from.
- Business status vocabularies evolve.
- The application enforces valid values; the database enforces the type constraint via a `CHECK` against a reference table or a text pattern.

**When to use native PostgreSQL ENUM:** only for genuinely static, binary, or minimal-value sets that will never change in the lifetime of the platform. Example: `direction TEXT CHECK (direction IN ('INBOUND', 'OUTBOUND'))` is acceptable as an inline CHECK; `CREATE TYPE call_direction AS ENUM (...)` is unnecessary given the two-value set.

### 21.8 JSONB Usage — Approved and Prohibited Uses

**Approved JSONB uses:**
| Column | Table | Rationale |
|---|---|---|
| `language_policy` | `agent_versions` | Evolving structure; always read whole |
| `graph_json` | `workflow_definitions` | Large, complex, opaque to queries |
| `snapshot_json` | `agent_versions` | Immutable config snapshot |
| `evidence` | `consent_records` | Variable structure per evidence kind |
| `components` | `tax_rules` | Variable per tax regime |
| `provider_metadata` | `payment_attempts` | Provider-specific, not queried by DB |
| `resource_snapshot` | `audit_events` | Variable per action kind |
| `localization_profile` | `organizations` | Read whole; sub-fields not queried |
| `configuration` | `integration_connections`, `plugin_installations` | Variable per integration type |
| `tax_profile_snapshot` | `invoices` | Point-in-time snapshot |

**Prohibited JSONB uses (use typed columns instead):**
| Prohibited | Use instead |
|---|---|
| Storing monetary amounts in JSONB | Dedicated `_amount NUMERIC`, `_currency CHAR(3)` columns |
| Storing timestamps in JSONB | `TIMESTAMPTZ` columns |
| Storing UUIDs as strings in JSONB | `UUID` columns or typed references |
| Using JSONB as the primary data model for a queryable field | Typed column with proper index |
| Generic `metadata JSONB` columns as catch-all | Explicit columns for known fields; structured extension only |

---

## 22. Migration Strategy

### 22.1 Tool — Alembic

Alembic (Phase 3A §14) remains the migration tool. Each migration file: one logical change, one transaction, a clear description.

### 22.2 Migration File Naming

```
{YYYY}{MM}{DD}{HH}{MM}_{short_description}.py

Examples:
20250115120000_create_identity_schema.py
20250115120100_create_organizations_table.py
20250116090000_add_consent_records_table.py
20250201100000_add_ix_contacts_org_phone.py
```

Timestamp prefix ensures ordering. No sequential integers — they conflict across branches.

### 22.3 Migration Principles

| Principle | Rule |
|---|---|
| **Atomic** | Each migration is one `BEGIN`/`COMMIT` block unless the operation requires non-transactional execution |
| **Backward compatible** | A deployed migration must not break the version of the application currently running (expand/contract pattern) |
| **Reversible** | Every `upgrade()` has a corresponding `downgrade()` unless physically impossible (e.g., partition drop with data) |
| **Non-destructive by default** | `DROP TABLE`, `DROP COLUMN`, `ALTER TYPE ... DROP VALUE` require a three-phase expand/contract migration |
| **No data backfill in migration** | Data migrations are separate, idempotent scripts run by workers — never in the schema migration |
| **Index creation is `CONCURRENTLY`** | All `CREATE INDEX` in migrations use `CREATE INDEX CONCURRENTLY` to avoid table lock |
| **Non-transactional for concurrent indexes** | `CREATE INDEX CONCURRENTLY` cannot run inside a transaction; Alembic supports `with op.get_context().autocommit_block()` |

### 22.4 Expand/Contract Pattern for Breaking Changes

**Removing a column (example):**
1. **Expand:** add the new column (if replacing) or mark old as deprecated in comments.
2. **Deploy application** that stops reading the old column (dual-read if replacing).
3. **Contract:** `DROP COLUMN` after all application instances no longer reference it.

This ensures zero-downtime deployment compatibility.

### 22.5 Large Table Migrations

For tables with >10M rows:
- Schema changes (ADD COLUMN NOT NULL with DEFAULT): PostgreSQL 11+ handles `ADD COLUMN ... DEFAULT <constant>` without a full table rewrite. Use `DEFAULT NULL` then backfill in a worker.
- Indexes: always `CONCURRENTLY`.
- Partition creation for an existing un-partitioned table: this is the most complex migration — requires a new partitioned table, batch copy, cutover via rename. Phase 5B must design this process explicitly for the 9 tables that require partitioning from day one (partitioning retroactively is significantly more complex than starting partitioned).

### 22.6 Zero-Downtime Deployment Rule

The migration runs before the new application version deploys. The application after the migration must be compatible with the pre-migration schema (for the brief period when old pods are still running).

**Prohibited in a migration that is deployed with the application:**
- Renaming a column (use ADD new + deprecate old + DROP in a later migration)
- Changing a column's type in a way that breaks existing queries
- Making a nullable column NOT NULL without a default (blocks reads of old rows until backfilled)

### 22.7 Partition Creation in Migration

RANGE monthly partitions should be created 3 months ahead in a scheduled maintenance function (`billing.create_next_usage_events_partition()`) rather than in ad-hoc migrations. The initial set (24 months of historical + 3 months ahead) is created in the Phase 5B migration. Phase 22 (Deployment) schedules the ongoing creation job.

---

## 23. Reference Data / Seed Strategy

### 23.1 What Needs Seeding

| Data | Schema | When seeded |
|---|---|---|
| System roles (`OWNER`, `ADMIN`, `MEMBER`, `BILLING_ADMIN`, `VIEWER`) | organization | Initial migration |
| Platform permissions (all ~40 permission strings) | organization | Initial migration |
| Role-permission assignments (defaults per system role) | organization | Initial migration |
| Built-in tool definitions (`createLead`, `bookAppointment`, etc.) | voice | Initial migration |
| Platform-default provider configs (empty — configured at deploy time) | voice | Not seeded; configured per environment |
| Default plans + plan versions (Starter, Growth, Enterprise) | billing | Initial migration + environment-specific script |
| Tax categories (HSN/SAC codes for SaaS services) | billing | Initial migration |
| Default tax rule (IN_GST, SaaS-applicable rate) | billing | Initial migration (rate as data, not a constant) |
| Integration definitions (Salesforce, HubSpot, Zoho, Google Calendar, etc.) | integrations | Initial migration |
| Embedding version V1 | knowledge | Initial migration |
| Currency reference (ISO 4217 subset) | billing | Initial migration |
| Country reference (ISO 3166-1 alpha-2 subset) | organization | Initial migration |
| Holiday calendar data (IN-national) | organization | Initial migration (updateable reference) |

### 23.2 Seeding Rules

- Seeds are idempotent: `INSERT ... ON CONFLICT DO NOTHING`.
- Seeds are version-controlled Alembic migrations (not ad-hoc scripts).
- Environment-specific data (actual plans with real prices, payment gateway keys) is not seeded in migrations — it is configured via the admin API or environment-specific scripts outside the migration.
- Seeded system roles have `organization_id IS NULL`; they are platform-global and not modifiable by tenant users.

### 23.3 Reference Table Pattern

Reference tables (countries, currencies, timezones, permissions, tax categories) use:
```sql
CREATE TABLE billing.currencies (
  code       CHAR(3)  PRIMARY KEY,
  name       TEXT     NOT NULL,
  is_active  BOOLEAN  NOT NULL DEFAULT TRUE
);
```
No RLS, readable by all roles. Updated by platform admin operations only, not by tenant APIs.

---

## 24. Backup / Recovery Considerations

### 24.1 Supabase PostgreSQL Backup

Supabase provides point-in-time recovery (PITR) via WAL archiving. V1 relies on Supabase's managed backup infrastructure. Phase 22 (Deployment) must configure:
- PITR retention: minimum 7 days.
- Daily snapshot backup: minimum 30 days.
- Backup encryption: AES-256 (Supabase default).
- Backup storage region: must match `DataResidencyProfile` for India Enterprise deployments.

### 24.2 Redis Backup

Redis is a hot-tier cache, not authoritative. AOF (Append-Only File) persistence is enabled for best-effort durability but is not relied upon for correctness. Recovery rebuilds from Postgres (§18.3).

### 24.3 S3 Backup

S3 versioning is enabled on all buckets. Recordings and documents are retained per the `RetentionProfile`. S3 buckets are in the same region as the primary database for India Enterprise deployments.

### 24.4 Recovery Time and Point Objectives

| Data type | RPO | RTO |
|---|---|---|
| Transactional DB (Postgres) | 0 (WAL continuous) | < 30 minutes |
| Redis hot-tier | Non-authoritative — rebuilt from DB | < 5 minutes |
| S3 binary objects | Versioned — near 0 loss | < 60 minutes for access restoration |
| Analytics projections | Eventual — rebuilt from events | < 24 hours |

---

## 25. India-Region Deployment Considerations

### 25.1 Deployment Profile Mapping

| Profile | PostgreSQL region | Redis region | S3 region | Notes |
|---|---|---|---|---|
| `STANDARD` | Platform default (may be multi-region) | Platform default | Platform default | No specific residency guarantee |
| `INDIA_ENTERPRISE` | India region (abstract: `in-primary`) | India region | India region | Contractual residency commitment |
| `REGIONAL` | Per contract | Per contract | Per contract | Future |

### 25.2 Region-Agnostic Schema

No cloud region name, availability zone, or data centre name appears in any table, column, migration file, or seed. The `organizations.region_ref TEXT` column stores an abstract identifier (e.g., `'in-primary'`) mapped to concrete infrastructure in `platform/infrastructure/config/regions.py`.

### 25.3 India-Specific Schema Considerations

| Field | Table | India consideration |
|---|---|---|
| `timezone` | `organizations` | Default `'Asia/Kolkata'`; must be a valid IANA identifier |
| `locale` | `organizations` | Default `'en-IN'` |
| `currency` | `organizations`, `billing_accounts` | Default `'INR'` at creation |
| `country_code` | `organizations` | Default `'IN'` at creation |
| `phone_country` | `organizations` | Default `'IN'` — affects phone parsing hint |
| `fiscal_year` | `invoice_number_sequences` | April-start fiscal year for India; configurable |
| `gstin` | `tax_profiles` | GSTIN format validation at application layer |
| `place_of_supply` | `invoices`, `tax_profiles` | Indian state code (2 uppercase letters per GST nomenclature) |
| `primary_language` | `organizations` | Default `'en-IN'`; Tamil `'ta-IN'` common choice |
| `supported_languages` | `organizations` | Default `['en-IN', 'ta-IN']` for India region |

---

## 26. Security Considerations

### 26.1 Database Roles Summary

```
app_api          -- Core API and Voice Gateway; per-tenant RLS context
app_worker       -- Background workers; same permissions as app_api
app_readonly     -- Analytics queries; SELECT only on analytics schema
app_migration    -- Alembic runner; bypasses RLS; DDL privileges
app_platform_admin  -- Cross-tenant reads; platform table writes
```

All roles use **scram-sha-256** authentication. Connection strings are stored in the secret manager, never in code or environment variables in production.

### 26.2 Least Privilege

- `app_api` and `app_worker` have no `CREATE`, `DROP`, or `ALTER` privileges.
- `app_readonly` has `SELECT` only on `analytics.*`. No access to `billing`, `audit`, or `crm` schemas.
- `app_migration` runs only during deployments; its credentials are rotated post-deployment.
- `app_platform_admin` has no `DELETE` on audit events or consent records.

### 26.3 Encryption

- **At rest:** Supabase provides AES-256 encryption at the storage layer. No application-layer column-level encryption in V1 (the Supabase storage layer covers all columns).
- **In transit:** TLS 1.2+ enforced for all connections to PostgreSQL, Redis, and S3.
- **`credential_ref` columns:** store opaque reference strings only. The secret manager resolves them. Phase 5 must add a `CHECK` constraint: `credential_ref LIKE 'secret_manager://%'` to prevent accidental plaintext storage.

### 26.4 PII Handling in Schema

Columns containing PII are documented per table in Phase 5B–5I. The database layer does not mask PII — masking is the application layer's responsibility (except in logs, where the Fluent Bit filter masks fields by column name pattern). Phase 5 must tag PII columns with a comment `-- pii: {category}` for automated tooling.

PII categories used:
- `pii:phone` — `phone_e164` columns
- `pii:email` — email address columns
- `pii:name` — full name, first name, last name
- `pii:address` — postal address components
- `pii:financial` — bank account details (none stored directly — only `PaymentMethodRef`)
- `pii:voice` — transcript text, recording references, AI summaries

---

## 27. Performance Considerations

### 27.1 Connection Pooling

Phase 3F §15 specifies PgBouncer in transaction-mode pooling. Phase 5 schema design must be compatible with transaction-mode pooling:
- No `SET LOCAL` configuration that persists beyond a transaction (RLS's `SET LOCAL app.tenant_id` is correctly scoped per transaction).
- No `LISTEN`/`NOTIFY` through the pool (use Redis Pub/Sub instead).
- Prepared statements are session-scoped — use named parameters but do not rely on `PREPARE`/`EXECUTE` through the pool.

### 27.2 N+1 Query Prevention

Domain design uses aggregate repositories that load the full aggregate in one query (with joined child tables). Analytics queries use pre-computed projections. Phase 5 must document the expected query pattern for each table to prevent N+1 patterns in ORM mapping.

### 27.3 Vacuum and Statistics

Append-only partitioned tables require regular `VACUUM` to clear dead tuples from index pages (even append-only tables create dead index entries when a partial segment is upserted). Phase 22 must configure `autovacuum` tuning for high-volume tables.

### 27.4 Projection Freshness

Analytics projections are updated by Celery workers consuming from the event bus. Expected lag: < 60 seconds. Dashboards display a freshness indicator. No analytics query touches transactional tables directly.

---

## 28. Capacity / Scaling Considerations

### 28.1 Expected V1 Scale (per Phase 1 SRS)

| Entity | Expected volume at scale |
|---|---|
| Concurrent calls | Tens of thousands |
| Calls per day | Millions |
| Contacts per large org | Millions |
| Campaign contacts per campaign | Millions |
| Usage events per day | Tens of millions |
| Audit events per day | Millions |
| Document chunks | Hundreds of millions |
| Transcript segments per call | ~100 (per-fragment) |

### 28.2 Table Size Estimates (at maturity)

| Table | Rows/year estimate | Action |
|---|---|---|
| `usage_events` | 10B+ | Monthly partition + ClickHouse migration trigger |
| `audit_events` | 1B+ | Monthly partition |
| `campaign_contacts` | 1B+ | List partition by campaign |
| `transcript_segments` | 500M+ | Monthly partition |
| `document_chunks` | 100M+ | List partition by KB |
| `call_sessions` | 100M+ | Monthly partition |
| `activities` | 50M+ | Monthly partition |
| `webhook_deliveries` | 50M+ | Monthly partition |
| `consent_records` | 10M+ | Monthly partition |

### 28.3 Single-Tenant Scale Limits

PostgreSQL RLS with `SET LOCAL` is efficient but adds a small per-query overhead. At >1000 concurrent tenant connections, connection pool configuration becomes critical. Phase 22 must set `max_connections` and PgBouncer pool sizes per role.

---

## 29. Database Anti-Patterns — Prohibited in This Project

| Anti-pattern | Prohibition | Correct approach |
|---|---|---|
| Cross-schema FK constraints | ❌ PROHIBITED | Logical UUID references; application-layer validation |
| `FLOAT` for monetary amounts | ❌ PROHIBITED | `NUMERIC(18,4)` |
| PostgreSQL `MONEY` type | ❌ PROHIBITED | `NUMERIC(18,4)` |
| Bare monetary numeric column without currency | ❌ PROHIBITED | Always pair `_amount` + `_currency` |
| ENUMs for evolving status values | ❌ PROHIBITED | `TEXT` with CHECK or reference table |
| Hard-coded tax rates in schema defaults or CHECKs | ❌ PROHIBITED | Versioned `tax_rules` rows |
| Hard-coded country/currency/timezone defaults | ❌ PROHIBITED | Application-layer seeding at org creation |
| `BYTEA` for audio, video, or large documents | ❌ PROHIBITED | S3 reference + metadata in DB |
| Generic `metadata JSONB` as default extension mechanism | ❌ DISCOURAGED | Typed columns; JSONB only where genuine flexibility is required |
| Updating append-only tables (other than permitted exceptions) | ❌ PROHIBITED | Enforced by REVOKE |
| Plain SQL secrets or credentials in any column | ❌ PROHIBITED | `credential_ref` opaque reference |
| BigSerial/Integer primary keys | ❌ PROHIBITED | UUIDv7 |
| Mixing embedding dimensions in the same vector column | ❌ PROHIBITED | Embedding version strategy |
| Sharing analytics projections with transactional tables | ❌ PROHIBITED | Separate schema; updated by event projection only |
| ClickHouse as a V1 dependency | ❌ PROHIBITED | PostgreSQL + `AnalyticsWritePort` |
| MongoDB for any purpose | ❌ PROHIBITED | Not in the approved technology stack |
| External vector database (Pinecone, Weaviate, etc.) | ❌ PROHIBITED | pgvector inside PostgreSQL |
| Destructive migration in a single step | ❌ PROHIBITED | Expand/contract pattern |
| `CREATE INDEX` without `CONCURRENTLY` on a live table | ❌ PROHIBITED | Always `CREATE INDEX CONCURRENTLY` in migrations |

---

## 30. Phase 5B–5I Implementation Roadmap

Each Phase 5 sub-document produces the complete DDL (table definitions, indexes, constraints, RLS policies, seeds) for one or more schemas.

| Sub-phase | Schemas covered | Key concerns |
|---|---|---|
| **5B** | `identity`, `organization` | User, Org, Membership, Role, Permission, LocalizationProfile, CompliancePolicy, DataSubjectRequest |
| **5C** | `voice` | Call, Conversation, Turn, Agent, AgentVersion, ToolDefinition, ToolExecution, Recording, Transcript, ProviderConfig, LanguageEvaluationRecord, TenantPhoneNumber — Partitioning for call_sessions + transcript_segments |
| **5D** | `crm` | Contact, Company, Deal, Pipeline, Activity, Task, Note, Appointment, LeadScoreRecord, CRMFieldDefinitionSet, ConsentRecord, ContactSuppression — Special RLS for suppression |
| **5E** | `campaign` | Campaign, CampaignContact, CallJob, ContactList, CsvImportJob, CampaignOutcome — Partitioning for campaign_contacts |
| **5F** | `knowledge`, `workflow` | KnowledgeBase, Document, IngestionJob, DocumentChunk, EmbeddingVersion, WorkflowDefinition, WorkflowExecution, PromptTemplate, PromptExperiment, SessionMemory, CustomerMemory, PronunciationLexicon — pgvector HNSW |
| **5G** | `billing` | BillingAccount, Subscription, Plan, PlanVersion, Invoice, InvoiceLine, TaxLine, PaymentAttempt, Credit, UsageRecord, UsageEvent, CostEntry, QuotaConfig, TaxProfile, TaxRule, TaxCategory, InvoiceNumberSequence, FxRates — Partitioning for usage_events + cost_entries; GST structure |
| **5H** | `integrations`, `webhooks`, `plugins` | IntegrationDefinition, IntegrationConnection, WebhookEndpoint, WebhookDelivery, Plugin, PluginVersion, PluginInstallation — Partitioning for webhook_deliveries |
| **5I** | `analytics`, `audit` | All projection tables, AnalyticsDashboard, AuditEvent — BRIN indexes; audit chain; ClickHouse migration annotations |

**Before starting any sub-phase:** Phase 5A (this document) must be approved. Every subsequent sub-phase must reference and comply with the standards defined here.

**Inter-schema dependency order for migration:** 5B → 5C → 5D → 5E → 5F → 5G → 5H → 5I. Each sub-phase's migrations depend on the prior sub-phases being applied (logical FK targets must exist before they are referenced, even without DB-enforced FKs, for data validation tooling to work correctly).

---

## Phase 5A Status

```
PHASE 5A STATUS

Database architecture:
APPROVED

Tenant isolation:
APPROVED

RLS strategy:
APPROVED

Currency strategy:
APPROVED

GST strategy:
APPROVED

Embedding strategy:
APPROVED

Partitioning strategy:
APPROVED

Migration strategy:
APPROVED

Overall:

PHASE 5B READY
```

**No decisions block Phase 5B.** All Phase 4I blockers are resolved:

- Embedding dimension: `vector(1536)` with explicit `dimensions=1536` API parameter — annotated prominently in §12 and §29.
- Multi-currency: `NUMERIC(18,4)` + `CHAR(3)` pairs, INR default, no implicit currency — §10.
- GST: configuration-driven `tax_rules` table, no rates in schema constants — §11.
- Contact suppression RLS: special three-scope policy designed and documented — §6.4.

**One implementation risk to monitor (non-blocking):** the `campaign_contacts` LIST partition strategy (one child table per campaign) requires an automated partition management solution before campaigns run at scale. Phase 5E must design the partition creation/drop automation as part of the DDL. If automated LIST partition management is not feasible at Phase 5E implementation time, RANGE monthly partitioning on `campaign_contacts.created_at` is the approved fallback — a data lifecycle trade-off (can no longer drop a single campaign's data atomically) but structurally simpler.
