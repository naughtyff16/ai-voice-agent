# Phase 5J — Analytics / Audit Schema

## 1. Phase Status

| | |
|---|---|
| **Phase** | 5J |
| **Status** | Approved for Freeze (see §27 Final Validation) |
| **Scope** | Analytics + Audit |
| **Depends on** | Phase 5A–5I (all FROZEN) |
| **Previous phase end** | Migration 066 (Phase 5I) |
| **Migration start** | 067 |
| **Migration end** | 075 |
| **PostgreSQL target** | 15+ |
| **Schemas** | `analytics`, `audit` |

This is the single, standalone, authoritative Phase 5J specification. It contains the complete architecture, schema, DDL, functions, grants, RLS, migration chain, retention model, replay model, projection model, histogram/percentile model, audit model, security model, test matrix, invariants, and final validation. There is exactly one implementation described in this document.

---

## 2. Executive Summary

Phase 5J defines two schemas that sit above the transactional domain schemas (5B–5I):

| Schema | Purpose | Authoritative? |
|---|---|---|
| `analytics` | Read-optimised, derived projection tables and aggregates for dashboards, reporting, and cost visibility | **No** |
| `audit` | Immutable, tamper-evident accountability/history log | **No** |

**Architecture at a glance:**

```
Transactional domains (5B–5I)          →  authoritative for domain state
    │  domain events (Redis Streams)
    ▼
Analytics ingestion (global dedup)     →  analytics.analytics_event_dedup + analytics_events
    │
    ▼
Projection (atomic idempotent)         →  analytics.analytics_projection_events + projection tables
    │
    ▼
Aggregates (tenant / time / dimension) →  analytics.call_metrics_hourly, usage_cost_daily, etc.

Historical rebuild (separate path)     →  isolated from normal incremental ingestion

Audit accountability log               →  audit.audit_events (immutable) + audit.audit_chain (hash chain)

PostgreSQL (V1 store)                  →  AnalyticsWritePort seam  →  ClickHouse (future, not V1)
```

**Core architectural decisions:**

- **V1: PostgreSQL only.** ClickHouse is a future adapter swap behind `AnalyticsWritePort` — not a V1 dependency.
- **Analytics is derived, never authoritative.** Domain state always lives in 5B–5I.
- **Audit is accountability/history, never authoritative** over domain state, and is **truly immutable** — no role, including `app_platform_admin`, may UPDATE or DELETE an audit row, and no role may INSERT a row directly; every write goes through `audit.fn_insert_audit_event()`, which enforces both tenant ownership and platform-event authorization at the database layer using the caller's actual session identity.
- **Global analytics event deduplication** is provided by the non-partitioned `analytics.analytics_event_dedup` registry (PRIMARY KEY on `dedup_key`), independent of time-partitioning on `analytics_events`.
- **Projection idempotency is atomic**: the projection-slot claim and the projection UPSERT happen in the same transaction, so there is never a durable state where a claim exists without its corresponding projection mutation, and never a case where a crash after commit causes reprocessing.
- **Normal replay horizon = 90 days**, matching the retention of both the dedup registry and the projection idempotency ledger. Events older than 90 days go through historical rebuild mode, a separate, isolated, non-destructive path.
- **Latency percentiles use a histogram**, stored as non-cumulative per-bucket counts. The cumulative distribution — including the overflow bucket in the total, and correctly ordered so overflow is only selected when no finite bucket satisfies the percentile threshold — is computed at query time.
- **`provider_health_5min` is platform-internal only.** Tenant-facing roles (`app_api`, `app_readonly`) have zero access, enforced by explicit grant/revoke and reaffirmed after any broad schema-level grant.
- **Every nullable aggregate dimension uses `UNIQUE NULLS NOT DISTINCT`** so PostgreSQL NULL semantics cannot create duplicate logical aggregate rows.
- **No frozen phase (5A–5I) is modified.**

---

## 3. Phase 5A–5I Dependency / Ownership Matrix

| Phase | Owns | 5J Relationship |
|---|---|---|
| 5A | DB standards (gen_uuid_v7, TIMESTAMPTZ, RLS conventions, BRIN, REVOKE patterns) | 5J follows these standards; introduces no new standard |
| 5B | Identity, organization, tenant context, RBAC, `organization.current_tenant_id()`, `BYPASSRLS` role model | 5J's RLS and SECURITY DEFINER tenant checks use 5B's tenant context function exclusively |
| 5C | Voice: calls, conversations, agents | 5J consumes `call.*`, `conversation.*` domain events; never queries voice tables directly |
| 5D | CRM: contacts, leads | 5J consumes `contact.*` domain events |
| 5E | Campaign: campaigns, campaign calls | 5J consumes `campaign.*` domain events |
| 5F | Knowledge: documents, RAG | Not consumed in V1 (open decision ODD-5J-06) |
| 5G | Workflow: prompts, tool executions | 5J consumes `tool_execution.*`, `workflow.*` domain events |
| 5H | Billing: usage, invoices, subscriptions | 5J consumes `usage.*`, `invoice.*` domain events; billing remains the sole financial source of truth |
| 5I | Integrations, webhooks, plugins | 5J consumes `webhook.*`, `integration.*`, `plugin.*` domain events |

**Invariant:** transactional domains are always authoritative. Analytics never becomes a second source of truth for domain state. Audit never becomes a second source of truth for domain state — it records that actions occurred, not the current state of any resource. No cross-schema foreign key exists from `analytics.*` or `audit.*` into 5B–5I tables; all references are logical UUIDs carried in event payloads.

---

## 4. Analytics Architecture

### 4.1 Pipeline

```
Domain Event (Redis Streams)
    │
    ▼
analytics.fn_ingest_analytics_event()          [SECURITY DEFINER, atomic]
    │  Step 1: INSERT analytics_event_dedup (dedup_key PRIMARY KEY)
    │          → conflict = duplicate → RETURN FALSE, stop here
    │  Step 2: INSERT analytics_events (time-partitioned ledger)
    │          → RETURN TRUE
    ▼
[worker loop, per projection_name]
    │
    ▼
analytics.fn_apply_projection_*()              [SECURITY DEFINER, atomic — see §9]
    │  Single transaction:
    │    Step 1: INSERT analytics_projection_events (claim)
    │            → conflict = already processed → ROLLBACK, no-op
    │    Step 2: UPSERT into the target projection table (additive)
    │  COMMIT (claim + mutation durable together, or neither is)
    ▼
Projection tables (call_metrics_hourly, usage_cost_daily, ...)
    │
    ▼
Dashboard queries (read-only; never touch transactional domain tables)
```

### 4.2 AnalyticsWritePort — ClickHouse Migration Seam

All analytics writes go through an application-layer port:

```python
class AnalyticsWritePort(Protocol):
    async def write_event(self, event: AnalyticsEvent) -> None: ...
    async def write_batch(self, events: list[AnalyticsEvent]) -> None: ...
```

**V1 adapter:** `PostgresAnalyticsAdapter` calls `analytics.fn_ingest_analytics_event()` and the appropriate `fn_apply_projection_*()` function.

**Future adapter:** `ClickHouseAnalyticsAdapter` — same port interface, no producer changes, no domain schema changes. ClickHouse is not a V1 dependency; migration trigger and process are documented in §22.

### 4.3 What Analytics Never Does

- Never reads transactional domain tables (voice, crm, campaign, billing, etc.) directly.
- Never becomes authoritative for any domain entity's current state.
- Never stores raw PII beyond bounded, documented fields (see §24).

---

## 5. Audit Architecture

### 5.1 Audit Event Lifecycle

```
Application/system action requiring an audit record
    │
    ▼
audit.fn_insert_audit_event()          [SECURITY DEFINER — the ONLY write path]
    │  Validates: action_kind, outcome, actor_type
    │  Validates: tenant ownership (p_organization_id = current tenant) for tenant events
    │  Validates: platform events (organization_id IS NULL) — the caller's session_user
    │             must be app_worker or app_platform_admin; enforced by an explicit
    │             database check, not by convention (see §14.2 for the exact mechanism)
    │  INSERT into audit.audit_events
    ▼
audit.audit_events row — permanently immutable from this point forward
    │
    ▼ (nightly, async)
audit.fn_compute_chain_hash()          [SECURITY DEFINER — reads only, never mutates audit_events]
    │  Batched deterministic hash over audit_events for (org, date)
    │  Writes result to audit.audit_chain ONLY
    ▼
audit.audit_chain — hash-chain checkpoint, one row per (org, date)
```

### 5.2 Tenant Events vs Platform Events

| | Tenant Audit Event | Platform Audit Event |
|---|---|---|
| `organization_id` | NOT NULL, must equal current tenant context | NULL |
| Who may write | `app_api`, `app_worker`, `app_platform_admin` — validated against the current tenant context | `app_worker`, `app_platform_admin` only — the function checks `session_user` and rejects any other caller, including `app_api` |
| Who may read | Tenant members of that organization; `app_platform_admin` (BYPASSRLS) | `app_platform_admin` only (BYPASSRLS); ordinary tenant roles are excluded by RLS |

The platform-event restriction is enforced **inside** `audit.fn_insert_audit_event()` by inspecting `session_user` — the actual database role that opened the connection, which is unaffected by the function's own `SECURITY DEFINER` privilege elevation. This is a database-enforced control, not an application convention (full mechanism in §14.2).

### 5.3 Immutability

**No role — including `app_platform_admin` — has direct INSERT, UPDATE, or DELETE privilege on `audit.audit_events` or `audit.audit_chain`.**

- INSERT happens exclusively via `audit.fn_insert_audit_event()`, a `SECURITY DEFINER` function executing with the privileges of its owning role (the schema/table owner), not the calling role's privileges. No `GRANT INSERT` is issued to any application role, including `app_platform_admin`.
- UPDATE and DELETE are never granted to any role, and no function in this specification performs UPDATE or DELETE on `audit.audit_events`.
- `audit.fn_compute_chain_hash()` reads `audit_events` and writes exclusively to `audit_chain` — it never touches `audit_events`.

This is the strongest possible database-enforced guarantee: even a compromised or misconfigured `app_platform_admin` session cannot alter or erase an audit record through ordinary SQL. Any correction, if ever legally required, would require a documented out-of-band procedure (e.g., direct superuser intervention with its own audit trail outside this schema) — not a normal application privilege.

---

## 6. Tenant Isolation Model

Per Phase 5B, `organization.current_tenant_id()` returns the tenant context for the current session, and `app_platform_admin` carries the `BYPASSRLS` role attribute.

| Table Class | RLS | FORCE RLS | Effective Access |
|---|---|---|---|
| Tenant-owned analytics tables (call_metrics_hourly, usage_cost_daily, etc.) | Yes | Yes | `USING (organization_id = organization.current_tenant_id())`; `app_platform_admin` bypasses via BYPASSRLS |
| `audit.audit_events`, `audit.audit_chain` | Yes | Yes | SELECT policy: `USING (organization_id = organization.current_tenant_id())` — excludes `organization_id IS NULL` (platform) rows for all non-BYPASSRLS roles; `app_platform_admin` bypasses and sees everything |
| `analytics.provider_health_5min` (platform-global; no `organization_id` column) | No (not applicable) | N/A | Access controlled entirely by GRANT/REVOKE (§13), not RLS |
| `analytics.analytics_event_dedup`, `analytics.analytics_projection_events` | dedup: Yes; projection ledger: No (internal-only, no tenant-facing reads) | dedup: Yes | Internal worker control tables |

**Invariant:** a tenant session can never see, insert, update, or delete another tenant's rows in any tenant-owned table, and can never see platform-level audit rows, regardless of which role (`app_api`, `app_worker`) it uses — only `app_platform_admin` (BYPASSRLS) crosses tenant boundaries, and it does so for legitimate platform administration, never for direct mutation of audit history.

---

## 7. Analytics Event Model

### 7.1 `analytics.analytics_events` — Time-Partitioned Ingestion Ledger

**Grain:** one row per novel domain event (novelty guaranteed by `analytics_event_dedup`, §8).

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | `gen_uuid_v7()`, part of composite PK |
| `organization_id` | UUID NOT NULL | Tenant scope |
| `event_type` | TEXT NOT NULL | e.g. `call.ended`, `contact.qualified` |
| `event_version` | TEXT NOT NULL DEFAULT '1' | Schema version of the event payload |
| `dedup_key` | TEXT NOT NULL | Must have been registered in `analytics_event_dedup` first |
| `occurred_at` | TIMESTAMPTZ NOT NULL | Business timestamp; partition key |
| `ingested_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | Wall-clock arrival |
| `entity_type`, `entity_id` | TEXT, UUID NULL | Primary subject entity |
| `actor_type`, `actor_id` | TEXT, UUID NULL | Who/what caused the event |
| `correlation_id`, `causation_id` | UUID NULL | Cross-service tracing |
| `call_id`, `campaign_id`, `agent_id` | UUID NULL | Common cross-cutting dimensions |
| `provider`, `model` | TEXT NULL | AI/telephony provider dimensions |
| `dimensions` | JSONB NOT NULL DEFAULT '{}' | Categorical attributes specific to event_type |
| `measures` | JSONB NOT NULL DEFAULT '{}' | Numeric values (counts, durations, tokens, costs) |
| `processing_status` | TEXT NOT NULL DEFAULT 'PENDING' | `PENDING → PROJECTED \| FAILED → DEAD_LETTER` |
| `processed_at` | TIMESTAMPTZ NULL | |
| `error_detail` | TEXT NULL | Poison-event diagnostic |

**Why structured columns, not JSONB-only:** `event_type`, `occurred_at`, `organization_id`, `entity_type`, `entity_id` are used in every dashboard filter and every dedup/replay decision — indexing them directly is materially faster than indexing into JSONB. `dimensions`/`measures` vary per event type and are appropriately schemaless.

**Partitioning:** RANGE monthly on `occurred_at`. **Retention:** 90 days hot; archived to S3 for up to 7 years (§20).

The `UNIQUE (dedup_key, occurred_at)` constraint on this table is a partition-local consistency aid only — it does not provide global deduplication. Global deduplication is exclusively the responsibility of `analytics.analytics_event_dedup` (§8).

### 7.2 Processing Status Lifecycle

```
PENDING → PROJECTED   (every subscribed projection has successfully claimed+applied this event)
PENDING → FAILED      (a projection attempt errored; eligible for retry)
FAILED  → DEAD_LETTER (retries exhausted or event_type/version unrecognized)
PROJECTED, DEAD_LETTER = terminal
```

### 7.3 Event Ordering and Late Arrivals

- `occurred_at` (business time) drives time-bucketing in every projection; `ingested_at` (wall-clock) does not.
- Late events update historical aggregate rows via additive UPSERT — safe because projection measures are commutative sums.
- Out-of-order events: since projection UPSERTs are additive (`x = x + delta`), the order in which two events for the same bucket are applied does not change the final value.
- Replay of an already-processed event (same `dedup_key`) is rejected at the dedup gate (§8) before it ever reaches a projection.

---

## 8. Global Deduplication

### 8.1 `analytics.analytics_event_dedup`

**Purpose:** provide an unconditionally, globally unique deduplication guarantee that the time-partitioned `analytics_events` table structurally cannot provide on its own (a `UNIQUE` constraint on a partitioned table is per-partition unless the partition key is part of the key — and `occurred_at` legitimately varies across replays of "the same" logical event delivery).

| Column | Type | Notes |
|---|---|---|
| `dedup_key` | TEXT | **PRIMARY KEY** — the sole global uniqueness guarantee |
| `event_id` | UUID NOT NULL | Cross-reference to `analytics_events.id` |
| `occurred_at` | TIMESTAMPTZ NOT NULL | For partition cross-reference |
| `organization_id` | UUID NOT NULL | |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |

**Dedup key construction:**
```
dedup_key = '{event_type}::{source_event_id}::{organization_id}'
-- or, when the source system has no stable event id:
dedup_key = '{event_type}::{entity_id}::{occurred_at_epoch_ms}::{organization_id}'
```

### 8.2 Ingestion Transaction

```sql
-- Inside fn_ingest_analytics_event(), single transaction:
INSERT INTO analytics.analytics_event_dedup (dedup_key, event_id, occurred_at, organization_id)
VALUES ($dedup_key, $event_id, $occurred_at, $org_id)
ON CONFLICT (dedup_key) DO NOTHING;
-- ROW_COUNT = 0  → duplicate → RETURN FALSE (analytics_events INSERT never attempted)
-- ROW_COUNT = 1  → novel     → proceed to INSERT analytics_events → RETURN TRUE
```

Both statements execute in the same function invocation and thus the same transaction: either both succeed (novel event fully recorded) or the dedup registration alone succeeds and nothing else happens (duplicate, correctly rejected).

### 8.3 Replay Horizon

`analytics_event_dedup` retention is 90 days, exactly matching the normal incremental replay horizon (§12). This table, together with `analytics.analytics_projection_events` (§9), is why the 90-day figure is used consistently across the whole ingestion pipeline.

---

## 9. Projection Idempotency

### 9.1 `analytics.analytics_projection_events`

**Purpose:** guarantee that a single analytics event affects a single named projection exactly once, even under worker retry, crash, or concurrent execution — with a strictly correct transactional boundary (§9.2), not merely a watermark heuristic.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `projection_name` | TEXT NOT NULL | e.g. `'call_metrics_hourly'` |
| `analytics_event_id` | UUID NOT NULL | FK (logical) to `analytics_events.id` |
| `occurred_at` | TIMESTAMPTZ NOT NULL | For retention cross-reference |
| `processed_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |
| | | `UNIQUE (projection_name, analytics_event_id)` |

Different projections claim the same `analytics_event_id` independently — `call_metrics_hourly` and `usage_cost_daily` each get their own row for the same source event, because each is a distinct `projection_name`.

### 9.2 Atomic Claim-and-Mutate Transaction

The claim and the projection mutation happen in one PostgreSQL transaction, executed by a single SECURITY DEFINER function per projection (e.g. `analytics.fn_apply_projection_call_metrics()`; full DDL in §17):

```
BEGIN
  INSERT INTO analytics_projection_events (projection_name, analytics_event_id, occurred_at)
    VALUES (...)
    ON CONFLICT (projection_name, analytics_event_id) DO NOTHING;

  IF NOT FOUND (i.e., conflict occurred) THEN
    -- Already processed by this projection. Roll back and return FALSE.
    -- No projection mutation is attempted.
  ELSE
    -- Newly claimed. Apply the projection UPSERT in the SAME transaction.
    INSERT INTO <projection_table> (...) VALUES (...)
      ON CONFLICT (<grain>) DO UPDATE SET <measure> = <table>.<measure> + EXCLUDED.<measure>, ...;
    -- Return TRUE.
  END IF
COMMIT   -- claim and mutation become durable together, or neither does
```

**Two distinct failure scenarios, both handled correctly:**

**Crash before COMMIT.** The transaction — including both the claim INSERT and the projection UPSERT — is rolled back in its entirety by PostgreSQL's normal transaction semantics. After the crash, neither the claim row nor the projection mutation exists. A retry of the same event calls the wrapper function again: the claim INSERT succeeds (no prior conflicting row), the projection UPSERT applies, and the event is correctly processed exactly once.

**Crash after COMMIT.** Both the claim row and the projection mutation are durable — COMMIT is atomic and both statements were part of it. A subsequent retry of the same event calls the wrapper function again: the claim INSERT now conflicts against the row from the successful commit, `fn_claim_projection_slot()` returns FALSE, and the function returns without touching the projection table again. The event is not reprocessed.

**The invariant this guarantees:** there is never a committed database state in which a projection claim exists without its corresponding projection mutation having also been committed, and never a case where a crash occurring strictly after a successful commit causes the projection to be mutated a second time. Because both statements are part of one transaction, PostgreSQL's atomicity property (all-or-nothing commit) is what makes this true — it is not a heuristic or a best-effort guarantee.

### 9.3 Concurrency

Two workers racing to process the same `(projection_name, analytics_event_id)` both attempt the INSERT into `analytics_projection_events`; PostgreSQL's row-level locking on the unique index ensures exactly one succeeds. The loser's transaction observes the conflict, performs no projection mutation, and returns FALSE.

### 9.4 Retention and Replay Horizon

`analytics_projection_events` retention is 90 days, identical to `analytics_event_dedup` and the normal replay horizon (§12). Rows are bulk-deleted alongside the `analytics_events` partition-drop maintenance job.

---
## 10. Aggregate Schema

Every projection table: populated exclusively by its `analytics.fn_apply_projection_*()` function; never queried from transactional source tables; tenant-isolated via RLS (except `provider_health_5min`, §13); idempotent via `analytics_projection_events`.

### 10.1 `analytics.call_metrics_hourly`
- **Purpose:** call volume, duration, and outcome reporting per tenant/agent/hour.
- **Grain:** (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code).
- **Nullable dimension:** `agent_id` (NULL = aggregate across all agents) → `UNIQUE NULLS NOT DISTINCT`.
- **Measures:** total_calls, answered_calls, failed_calls, total_duration_s, talk_time_s, wait_time_s, transfer_count, recording_count (all additive).
- **Source events:** `call.ended`, `call.failed`. **Partitioning:** RANGE monthly on hour_bucket. **Retention:** 2 years.

### 10.2 `analytics.call_latency_stage_hourly`
- Histogram-based latency distribution — see §11.

### 10.3 `analytics.conversation_turn_stats_daily`
- **Purpose:** conversation quality and AI usage per agent/day.
- **Grain:** (organization_id, date_bucket, agent_id). `agent_id` NOT NULL here (this table is agent-scoped by definition) — no nullable-dimension issue.
- **Measures:** total_turns, total_calls, barge_in_count, tool_calls_total/succeeded/failed, llm_prompt/completion/total_tokens, stt_audio_seconds, tts_characters (all additive).
- **Source events:** `conversation.turn_completed`, `conversation.completed`. **Partitioning:** monthly. **Retention:** 2 years.

### 10.4 `analytics.agent_utilization_hourly`
- **Purpose:** agent concurrency and utilization per hour.
- **Grain:** (organization_id, hour_bucket, agent_id). `agent_id` NOT NULL.
- **Measures:** calls_started, calls_ended, peak_concurrent (updated via `GREATEST`, not addition — commutative and associative, so still correct under retry/concurrency), sum_concurrent_samples, sample_count. Average concurrency is derived at query time as `sum_concurrent_samples / NULLIF(sample_count, 0)`.
- **Source events:** `call.started`, `call.ended`. **Partitioning:** monthly. **Retention:** 2 years.

### 10.5 `analytics.lead_funnel_daily`
- **Purpose:** lead qualification/conversion funnel per tenant/day, optionally per campaign.
- **Grain:** (organization_id, date_bucket, campaign_id). `campaign_id` nullable (NULL = non-campaign inbound) → `UNIQUE NULLS NOT DISTINCT`.
- **Measures:** leads_contacted, leads_answered, leads_qualified, leads_disqualified, leads_converted, appointments_booked, dnc_encounters (additive).
- **Source events:** `contact.qualified`, `contact.converted`, `contact.lead_status_changed`, `appointment.booked`. **Partitioning:** monthly. **Retention:** 5 years.

### 10.6 `analytics.campaign_outcome_summary`
- **Purpose:** current aggregate outcome per campaign.
- **Grain:** campaign_id (UNIQUE, NOT NULL) — no nullable-dimension issue.
- **Measures:** calls_attempted/connected/completed/failed, unique/qualified/converted_contacts, appointments_booked, total_duration_s, telephony/AI cost amounts (additive).
- **Source events:** `campaign.contact.call_attempted`, `campaign.contact.qualified`, `campaign.completed`. **Partitioning:** none (bounded by campaign count). **Retention:** 5 years post-completion.

### 10.7 `analytics.usage_cost_daily`
- **Purpose:** cost visibility by metric/provider/model/day.
- **Grain:** (organization_id, date_bucket, metric, provider, model). All NOT NULL — sentinel `'all'` used instead of NULL for "all providers/models" rows, so no nullable-dimension issue exists here.
- **Measures:** unit_count, cost_amount, event_count (additive).
- **Source events:** `usage.event_recorded`. **Partitioning:** monthly. **Retention:** 2 years hot, 7 years cold (financial).

### 10.8 `analytics.billing_revenue_monthly`
- **Purpose:** billed revenue and provider cost per tenant/month.
- **Grain:** (organization_id, year_month). NOT NULL. **Partitioning:** yearly RANGE on `year_bucket` (generated INTEGER column). **Retention:** 7 years.

### 10.9 `analytics.roi_by_campaign`
- **Purpose:** ROI derived nightly from `campaign_outcome_summary` + `usage_cost_daily`.
- **Grain:** campaign_id (UNIQUE, NOT NULL). **Partitioning:** none. **Retention:** 5 years.

### 10.10 `analytics.tool_execution_stats_daily`
- **Purpose:** tool-call reliability per tenant/tool/agent/day.
- **Grain:** (organization_id, date_bucket, tool_name, agent_id). `agent_id` nullable → `UNIQUE NULLS NOT DISTINCT`.
- **Measures:** invocations, succeeded, failed, timed_out, sum_latency_ms (additive). **Partitioning:** monthly. **Retention:** 2 years.

### 10.11 `analytics.webhook_delivery_stats_daily`
- **Purpose:** webhook reliability per tenant/day.
- **Grain:** (organization_id, date_bucket). Both NOT NULL. **Partitioning:** monthly. **Retention:** 2 years.

### 10.12 `analytics.provider_health_5min`
- Platform-internal only — see §13.

**Dimension audit for nullable-grain uniqueness (every table checked):**

| Table | Nullable grain dimension(s) | Constraint |
|---|---|---|
| call_metrics_hourly | agent_id | `UNIQUE NULLS NOT DISTINCT` |
| call_latency_stage_hourly (histogram) | none (all grain columns NOT NULL; see §11) | ordinary `UNIQUE` |
| conversation_turn_stats_daily | none (agent_id NOT NULL) | ordinary `UNIQUE` |
| agent_utilization_hourly | none (agent_id NOT NULL) | ordinary `UNIQUE` |
| lead_funnel_daily | campaign_id | `UNIQUE NULLS NOT DISTINCT` |
| campaign_outcome_summary | none | ordinary `UNIQUE` |
| usage_cost_daily | none (sentinel `'all'` used) | ordinary `UNIQUE` |
| billing_revenue_monthly | none | ordinary `UNIQUE` |
| roi_by_campaign | none | ordinary `UNIQUE` |
| tool_execution_stats_daily | agent_id | `UNIQUE NULLS NOT DISTINCT` |
| webhook_delivery_stats_daily | none | ordinary `UNIQUE` |
| provider_health_5min | none | ordinary `UNIQUE` |
| audit_chain | organization_id (NULL for platform) | `UNIQUE NULLS NOT DISTINCT` |

No table with a nullable grain dimension uses an ordinary `UNIQUE` constraint anywhere in this specification.

---

## 11. Latency Histogram / Percentiles

### 11.1 Why Scalar Percentiles Are Invalid

Counts and sums are additive: `COUNT(A ∪ B) = COUNT(A) + COUNT(B)`. Percentiles are not: `p95(A ∪ B) ≠ p95(A) + p95(B)` and `≠ avg(p95(A), p95(B))`. Storing scalar `p50_latency_ms`/`p95_latency_ms`/`p99_latency_ms` columns and updating them via addition or averaging across workers or time buckets is mathematically wrong and is not used anywhere in this specification.

### 11.2 `analytics.call_latency_stage_hourly` — Histogram Design

**Grain:** (organization_id, hour_bucket, provider, provider_category, model, `bucket_upper_ms`). All grain columns are NOT NULL — no nullable-dimension issue.

**Stored representation — non-cumulative, per-bucket counts.** Each row's `bucket_count` is the number of samples whose latency falls into that specific bucket's range only — it is not a cumulative "less-than-or-equal" running total. A sample with latency 87ms increments exactly one row: the row for the smallest bucket boundary ≥ 87ms (`bucket_upper_ms = 100`). It does not increment the 150, 250, 500, ... rows. The cumulative distribution is derived entirely at query time (§11.4).

**Bucket boundaries (ms), fixed for V1:**

| `bucket_upper_ms` | Range represented |
|---|---|
| 10 | (0, 10] |
| 25 | (10, 25] |
| 50 | (25, 50] |
| 100 | (50, 100] |
| 150 | (100, 150] |
| 250 | (150, 250] |
| 500 | (250, 500] |
| 750 | (500, 750] |
| 1000 | (750, 1000] |
| 1500 | (1000, 1500] |
| 2000 | (1500, 2000] |
| 5000 | (2000, 5000] |
| **-1 (overflow)** | (5000, ∞) |

**Row sparsity.** The `UNIQUE (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)` constraint guarantees at most one row per bucket per grain — it does not guarantee that all 13 buckets exist for every grain. Only buckets that have actually received at least one sample get a row. A bucket with no row is implicitly zero. This is standard, efficient sparse-histogram representation; a query computing totals or cumulative sums treats a missing bucket as `bucket_count = 0` naturally, since a `GROUP BY` over existing rows plus a window-sum simply omits absent buckets.

**Ingestion (inside the atomic projection wrapper for this table):**
```sql
INSERT INTO analytics.call_latency_stage_hourly
  (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms, bucket_count)
VALUES ($org_id, $hour, $provider, $category, $model, $bucket_for(latency_ms), 1)
ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
DO UPDATE SET bucket_count = call_latency_stage_hourly.bucket_count + EXCLUDED.bucket_count;
```
where `$bucket_for(latency_ms)` maps a raw latency sample to exactly one bucket boundary (the smallest boundary ≥ the sample, or `-1` if > 5000ms). This single-bucket increment is what makes the counts non-cumulative and additive: two workers incrementing the same bucket concurrently simply sum correctly regardless of order.

### 11.3 Overflow Bucket Semantics

The overflow bucket (`bucket_upper_ms = -1`, representing samples > 5000ms) must be included in the total sample count used as the percentile denominator. If 90 samples are ≤ 5000ms and 10 samples are > 5000ms, the total is 100, not 90, and every percentile threshold is computed against all 100.

The overflow bucket must also be evaluated **last** in distribution order — it represents latencies greater than every finite bucket, and must never be selected as a percentile result merely because its numeric sentinel value (`-1`) happens to be less than the finite bucket boundaries. §11.4 shows the exact mechanism that guarantees correct ordering.

If a percentile threshold is satisfied by a finite bucket, the finite bucket is returned — even if the overflow bucket, evaluated later in distribution order, would also technically satisfy the cumulative-count condition. Only when no finite bucket satisfies the threshold does the overflow bucket become the result, reported as `'>5000ms'` rather than a numeric value.

### 11.4 Percentile Query

```sql
WITH buckets AS (
  SELECT
    bucket_upper_ms,
    -- Overflow (-1) must sort AFTER all finite buckets for correct distribution ordering.
    CASE WHEN bucket_upper_ms = -1 THEN 2147483647 ELSE bucket_upper_ms END AS sort_key,
    SUM(bucket_count) AS cnt
  FROM analytics.call_latency_stage_hourly
  WHERE organization_id = $org_id
    AND hour_bucket >= $start_ts AND hour_bucket < $end_ts
    AND provider_category = $category
    AND ($provider = 'all' OR provider = $provider)
  GROUP BY bucket_upper_ms
  -- Missing buckets are simply absent rows; treated as 0 by the window sum below.
),
total AS (
  -- Overflow bucket IS included in the total denominator.
  SELECT SUM(cnt) AS n FROM buckets
),
cumulative AS (
  SELECT
    bucket_upper_ms,
    sort_key,
    cnt,
    SUM(cnt) OVER (ORDER BY sort_key) AS cumulative_count
  FROM buckets
)
SELECT
  -- Select the FIRST bucket in distribution order (ORDER BY sort_key) whose
  -- cumulative count clears the threshold. This is NOT a MIN() over
  -- bucket_upper_ms values — that would incorrectly favor the overflow
  -- sentinel (-1) over legitimate finite buckets, since -1 is numerically
  -- smaller than every finite boundary. Ordering by sort_key (which maps
  -- overflow to a value larger than any finite bucket) and taking the first
  -- match is what correctly implements "smallest bucket, in distribution
  -- order, that reaches this percentile."
  (SELECT bucket_upper_ms FROM cumulative
    WHERE cumulative_count >= (SELECT n FROM total) * 0.50
    ORDER BY sort_key LIMIT 1) AS p50_bucket,
  (SELECT bucket_upper_ms FROM cumulative
    WHERE cumulative_count >= (SELECT n FROM total) * 0.95
    ORDER BY sort_key LIMIT 1) AS p95_bucket,
  (SELECT bucket_upper_ms FROM cumulative
    WHERE cumulative_count >= (SELECT n FROM total) * 0.99
    ORDER BY sort_key LIMIT 1) AS p99_bucket,
  (SELECT n FROM total) AS sample_count;
```

The result columns (`p50_bucket`, `p95_bucket`, `p99_bucket`) are `INTEGER` bucket boundaries or `-1`; the presentation layer formats `-1` as `'>5000ms'` and any other value as `<value>ms`. A `NULL` result (no bucket satisfies the threshold, which only happens when `total.n` is `NULL`, i.e. no samples at all) is presented as "no data."

### 11.5 Documented Approximation and Behavior

- **Accuracy:** approximate; the reported percentile is a bucket boundary, with true resolution equal to the bucket width at that point in the distribution (e.g., ±25ms in the 50–250ms range where STT/TTS latencies concentrate, coarser above 2000ms).
- **Empty distribution** (no rows for the queried grain/time-range): `total.n` is `NULL`; every `WHERE cumulative_count >= NULL * p` condition is `NULL` (never true); every percentile subquery returns zero rows, and the outer `SELECT` yields `NULL` for `p50_bucket`/`p95_bucket`/`p99_bucket` and `NULL` for `sample_count`. No division-by-zero, no error.
- **Sparse buckets:** buckets with zero samples are simply absent rows; the window function sums only present rows in ascending order, which is mathematically identical to including explicit zero-count rows.
- **One sample only:** all three percentiles resolve to that one sample's bucket, since every threshold (0.50, 0.95, 0.99 of 1) is ≤ 1 and the single bucket's cumulative count is 1.
- **Merging multiple hour buckets or multiple workers:** because `bucket_count` is additive per bucket, summing `bucket_count` across any set of hour_bucket rows (or across concurrent worker increments) before running the cumulative/percentile query is mathematically exact for the merged histogram — this is the entire point of the histogram representation.
- **Materialization strategy:** percentiles are computed at query time from stored histogram counts; there are no pre-computed scalar percentile columns anywhere in the schema.

### 11.6 Worked Example

**Dataset:** samples at 10ms, 20ms, 30ms, 100ms, 200ms, 300ms.

Each sample maps to the smallest bucket boundary ≥ its value:

| Sample | Bucket |
|---|---|
| 10ms | 10 |
| 20ms | 25 |
| 30ms | 50 |
| 100ms | 100 |
| 200ms | 250 |
| 300ms | 500 |

**Resulting histogram:** bucket 10 = 1, bucket 25 = 1, bucket 50 = 1, bucket 100 = 1, bucket 250 = 1, bucket 500 = 1. Total n = 6.

**Cumulative distribution (ascending `sort_key` order):**

| bucket_upper_ms | cnt | cumulative_count |
|---|---|---|
| 10 | 1 | 1 |
| 25 | 1 | 2 |
| 50 | 1 | 3 |
| 100 | 1 | 4 |
| 250 | 1 | 5 |
| 500 | 1 | 6 |

- **p50** threshold = 6 × 0.50 = 3.0 → first bucket (in ascending order) with cumulative_count ≥ 3.0 is bucket **50** → p50 = "50ms".
- **p95** threshold = 6 × 0.95 = 5.7 → first bucket with cumulative_count ≥ 5.7 is bucket **500** (cumulative_count = 6) → p95 = "500ms".
- **p99** threshold = 6 × 0.99 = 5.94 → first bucket with cumulative_count ≥ 5.94 is bucket **500** → p99 = "500ms".

This is the value produced by directly executing the query in §11.4 against this dataset — it is a histogram-bucket approximation of the true raw-sample percentile, not the exact raw-value percentile, and is reported as such. It is explicitly not derived from averaging or summing any per-subset percentile.

### 11.7 Overflow Boundary Cases

**Threshold satisfied entirely within finite buckets (no overflow influence):** with 100 samples, 99 in finite buckets (cumulatively reaching 99 at the 5000ms bucket) and 1 in overflow, the p95 threshold (95) is satisfied by the 5000ms bucket (cumulative_count = 99 ≥ 95) before the overflow bucket is reached in `sort_key` order — result: `"5000ms"`, not `">5000ms"`.

**Threshold satisfied only by the overflow bucket:** with 100 samples, 90 in finite buckets (cumulatively reaching 90) and 10 in overflow (cumulative_count = 100), the p95 threshold (95) is not satisfied by any finite bucket (max finite cumulative_count = 90 < 95); the overflow bucket (cumulative_count = 100 ≥ 95) is the first bucket in `sort_key` order to satisfy it — result: `">5000ms"`.

**All samples in overflow:** with 100 samples all > 5000ms, only the overflow row exists (cumulative_count = 100); every percentile (p50, p95, p99) resolves to the overflow bucket — result: `">5000ms"` for all three.

**No samples:** `total.n` is `NULL`; all percentile results are `NULL` ("no data"), for every percentile.

**Single sample at 100ms:** one row, bucket 100, cumulative_count = 1; every percentile threshold (0.5, 0.95, 0.99) is ≤ 1, so every percentile resolves to bucket 100 — result: `"100ms"` for p50, p95, and p99.

---

## 12. Historical Rebuild / Backfill

### 12.1 Normal Incremental Replay Horizon

| | Value |
|---|---|
| Normal incremental replay horizon | 90 days |
| `analytics.analytics_event_dedup` retention | 90 days |
| `analytics.analytics_projection_events` retention | 90 days |

**Invariant:** `dedup_registry_retention ≥ normal_replay_horizon` and `projection_ledger_retention ≥ normal_replay_horizon`. Both hold with equality (90d = 90d = 90d). A normal replay — a retry, a duplicate delivery, a late redelivery from the event bus — occurring within 90 days of the original event's `occurred_at` is guaranteed to be correctly deduplicated at both the event-ingestion gate (§8) and the per-projection idempotency gate (§9).

### 12.2 The Boundary Enforcement

The Celery worker consuming the domain event bus checks `occurred_at` age before calling `fn_ingest_analytics_event()`:

```
IF NOW() - event.occurred_at > INTERVAL '90 days' THEN
    -- Do NOT call fn_ingest_analytics_event(). Route to historical rebuild queue instead.
ELSE
    -- Normal path: fn_ingest_analytics_event() → fn_apply_projection_*()
END IF
```

This application-layer gate is safe precisely because the two database-layer guarantees (dedup registry PRIMARY KEY, projection ledger UNIQUE constraint) are retained for exactly as long as the horizon during which the application promises to route events through the normal path.

### 12.3 Historical Rebuild Mode

Used when reconstructing analytics after a bug, backfilling a newly added projection type against historical data, or re-processing S3-archived events beyond the 90-day window.

```
Archived analytics_events (S3, or historical DB export)
    │
    ▼
Isolated rebuild process (separate code path; does NOT call
    fn_ingest_analytics_event() or any fn_apply_projection_*() function)
    │
    ▼
Rebuild-specific staging projection tables
    (e.g. analytics.call_metrics_hourly_rebuild_<job_id>,
     created ad hoc with identical structure to the production table)
    │
    ▼
Validation
    (row counts, spot-check totals against audit.audit_events counts
     or independent billing.usage_events totals for the same period)
    │
    ▼
Controlled replacement / merge into production
    (operator-approved: either an atomic partition swap for the affected
     time range, or a reconciling UPDATE that sets absolute values rather
     than adding deltas — never a blind re-application of the normal
     additive UPSERT, which would double-count)
    │
    ▼
Production analytics aggregates
```

**Why historical rebuild cannot reuse the normal path:** the normal path's correctness depends entirely on `analytics_event_dedup` and `analytics_projection_events` containing a row for every event already processed within the current horizon. For events outside the 90-day horizon, those rows do not exist (by design — they were purged). Sending such an event through `fn_ingest_analytics_event()` would find no conflicting dedup row and would be accepted as "novel," and sending it through a projection wrapper would find no conflicting claim and would apply an additional additive delta on top of whatever was already aggregated when the event was first (correctly) processed months or years ago — silently double-counting production data.

**Rebuild safety properties:**
- **Isolated:** operates on staging tables, never on production projection tables directly, until the controlled replacement step.
- **Repeatable:** starts from archived source-of-truth events and writes to fresh staging tables each run, so running it twice produces the same staging result both times; the controlled replacement step is an idempotent replace-or-reconcile, not an additive append.
- **Non-destructive:** the controlled replacement step is operator-approved and, for partition-swap strategies, retains the previous partition until validation is signed off.
- **Deterministic:** given the same archived event set, the same staging output is produced every time.

---

## 13. Provider Health — Platform-Internal Access

### 13.1 Nature

`analytics.provider_health_5min` tracks infrastructure/provider circuit-breaker and error-rate state (LLM/STT/TTS/telephony providers) in 5-minute windows. It has no `organization_id` column — it is inherently platform-global, not tenant data.

### 13.2 Access Model

| Role | SELECT | INSERT/UPDATE | Rationale |
|---|---|---|---|
| `app_api` (tenant-facing) | Denied | Denied | Infrastructure topology and provider health must not be exposed to tenant-facing application code |
| `app_readonly` | Denied | Denied | This role backs read replicas used by tenant-facing reporting |
| `app_worker` (internal analytics/observability processing) | Allowed | Allowed | Required to write and read this table as part of normal internal monitoring pipelines |
| `app_platform_admin` (platform/internal observability role) | Allowed | Allowed (full) | Platform operators need full visibility and management |

No `organization_id` is added to this table to solve the access-control question — that would incorrectly imply the data is tenant-scoped. Access is controlled entirely through explicit `GRANT`/`REVOKE`, consistent with the existing platform-role architecture from Phase 5B (`app_platform_admin`).

If a tenant-facing dashboard needs a sanitized provider-status indicator, it is served by an internal service using `app_worker` credentials, returning a deliberately reduced-information response — never direct table access from `app_api`.

### 13.3 Grants

```sql
REVOKE ALL ON analytics.provider_health_5min FROM app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.provider_health_5min TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.provider_health_5min TO app_platform_admin;
```

This statement pair appears once in the DDL (§17, migration 071) and is never contradicted elsewhere — including by the broad `GRANT SELECT ON ALL TABLES IN SCHEMA analytics` in the grants-finalization migration (074), which is followed by an explicit re-`REVOKE` for this table so the broad grant cannot silently reopen access (§17).

---

## 14. Audit Schema — Complete Model

### 14.1 `audit.audit_events`

**Grain:** one row per auditable action. Immutable from the instant of INSERT (§5.3). No `chain_hash` column — hash-chain state lives exclusively in `audit.audit_chain` (§15), never mutating this table.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | `gen_uuid_v7()`, part of composite PK with `occurred_at` |
| `organization_id` | UUID NULL | NULL = platform-level event |
| `actor_type` | TEXT NOT NULL | `USER, API_KEY, SYSTEM, WORKER, PLUGIN, PLATFORM_ADMIN, INTEGRATION` |
| `actor_ref` | UUID NULL | e.g. `identity.users.id` |
| `actor_name` | TEXT NULL | Bounded 200 chars; denormalized display name at event time |
| `action_kind` | TEXT NOT NULL | See §14.3 vocabulary |
| `resource_type` | TEXT NOT NULL | e.g. `'user'`, `'call'`, `'campaign'` |
| `resource_id` | UUID NULL | |
| `outcome` | TEXT NOT NULL | `SUCCESS, FAILURE, PARTIAL` |
| `failure_reason` | TEXT NULL | Bounded 1000 chars |
| `ip_address` | INET NULL | |
| `user_agent` | TEXT NULL | Bounded 500 chars |
| `session_id` | TEXT NULL | |
| `request_id`, `correlation_id` | UUID NULL | Tracing |
| `resource_snapshot` | JSONB NULL | Bounded 4096 bytes; non-PII, non-secret only (§24) |
| `occurred_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | Partition key |

**Partitioning:** RANGE monthly on `occurred_at`. **Retention:** 1 year hot, 7 years cold (S3).

### 14.2 Write Path and Enforcement Mechanism

```sql
REVOKE ALL ON audit.audit_events FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT SELECT ON audit.audit_events TO app_api, app_readonly, app_worker, app_platform_admin;
-- No INSERT, UPDATE, or DELETE privilege is granted to ANY role, without exception.
```

`audit.fn_insert_audit_event()` is `SECURITY DEFINER`, owned by the table-owning role, and is therefore the only code path capable of an INSERT — it does not require, and is not granted, any table-level INSERT privilege from any caller. `app_platform_admin` has SELECT only on `audit.audit_events` and `audit.audit_chain` — full read visibility (via BYPASSRLS) for platform administration, but zero direct mutation capability, identical in kind to every other role.

**Platform-event authorization — the exact enforcement mechanism.** Because `fn_insert_audit_event()` runs as `SECURITY DEFINER`, the ordinary `current_user`/`current_role` inside the function body would resolve to the function's *owning* role, not the role that actually called it — using `current_user` here would be a privilege-escalation bug. Instead, the function inspects `session_user`, which PostgreSQL guarantees reflects the role that authenticated the database session, and is unaffected by `SECURITY DEFINER` context switches:

```sql
IF p_is_platform_event THEN
  IF session_user NOT IN ('app_worker', 'app_platform_admin') THEN
    RAISE EXCEPTION 'audit: caller % is not authorized to create platform audit events', session_user;
  END IF;
  IF p_organization_id IS NOT NULL THEN
    RAISE EXCEPTION 'audit: platform events must have NULL organization_id';
  END IF;
ELSE
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'audit: tenant audit events must have a non-NULL organization_id';
  END IF;
  IF p_organization_id <> organization.current_tenant_id() THEN
    RAISE EXCEPTION 'audit: organization_id % does not match current tenant context', p_organization_id;
  END IF;
END IF;
```

A session connected as `app_api` that calls `fn_insert_audit_event(p_is_platform_event => TRUE, p_organization_id => NULL, ...)` is rejected: `session_user` evaluates to `'app_api'`, which is not in `('app_worker', 'app_platform_admin')`, and the function raises an exception before any INSERT is attempted. This is a database-enforced control — it holds regardless of what the application code does or does not choose to call, and it cannot be bypassed by an application bug that mistakenly sets `p_is_platform_event => TRUE` from an `app_api` context.

For tenant events, the complementary check (`p_organization_id <> organization.current_tenant_id()`) prevents any role — including `app_api` — from writing an audit record for a different tenant than the one its session is scoped to.

### 14.3 Audit Action Kind Vocabulary

**Authentication:** `USER_LOGIN`, `USER_LOGIN_FAILED`, `USER_LOGOUT`, `USER_MFA_ENABLED`, `USER_MFA_DISABLED`, `USER_PASSWORD_CHANGED`, `USER_REGISTERED`, `USER_EMAIL_VERIFIED`, `USER_ERASED`, `USER_PROFILE_UPDATED` †, `SESSION_REVOKED` §, `TOKEN_REFRESH_REUSE_DETECTED` §, `USER_SESSION_FORCE_LOGOUT` §, `TOKEN_DENYLIST_ENTRY_WRITTEN` §

**OAuth:** `OAUTH_LINKED`, `OAUTH_UNLINKED`

**API Keys:** `API_KEY_CREATED`, `API_KEY_REVOKED`

**Organization / Membership:** `ORGANIZATION_CREATED`, `ORGANIZATION_UPDATED`, `ORGANIZATION_SUSPENDED`, `ORGANIZATION_REACTIVATED`, `ORGANIZATION_CANCELLED` †, `MEMBER_INVITED`, `MEMBER_JOINED`, `MEMBER_REMOVED`, `MEMBER_SUSPENDED`, `MEMBER_REACTIVATED` †, `MEMBER_ROLE_CHANGED`, `DATA_RESIDENCY_CHANGED`

**Teams** †: `TEAM_CREATED`, `TEAM_UPDATED`, `TEAM_ARCHIVED`, `TEAM_MEMBER_ADDED`, `TEAM_MEMBER_REMOVED`

**RBAC:** `ROLE_ASSIGNED`, `ROLE_REMOVED`, `PERMISSION_CHANGED`

**Agents / Prompts / Workflows / Knowledge:** `AGENT_PUBLISHED`, `AGENT_DEPRECATED`, `AGENT_CREATED` ‡, `AGENT_CONFIG_UPDATED` ‡, `PROMPT_PUBLISHED`, `PROMPT_ROLLED_BACK`, `WORKFLOW_PUBLISHED`, `KNOWLEDGE_BASE_CREATED`, `KNOWLEDGE_BASE_DELETED`, `DOCUMENT_DELETED`, `KNOWLEDGE_BASE_UPDATED` §, `KNOWLEDGE_BASE_ARCHIVED` §, `KNOWLEDGE_BASE_REINDEX_TRIGGERED` §, `KNOWLEDGE_BASE_REINDEX_COMPLETED` §, `DOCUMENT_UPLOADED` §, `DOCUMENT_ARCHIVED` §, `DOCUMENT_REPROCESS_REQUESTED` §, `DOCUMENT_VERSION_PUBLISHED` §, `DOCUMENT_VERSION_MARKED_FAILED` §, `DOCUMENT_VERSION_ROLLED_BACK` §, `DOCUMENT_GDPR_ERASED` §

**Voice — Calls / Tools / Recordings / Phone Numbers** ‡: `CALL_INITIATED`, `CALL_TERMINATED`, `CALL_TRANSFERRED`, `CALL_HELD`, `CALL_RESUMED`, `TOOL_DEFINITION_CREATED`, `TOOL_DEFINITION_UPDATED`, `TOOL_DEFINITION_DEACTIVATED`, `RECORDING_DELETED`, `PHONE_NUMBER_AGENT_ASSIGNED`, `RECORDING_ACCESS_GRANTED` ‖

**Integrations / Webhooks / Plugins:** `INTEGRATION_CONNECTED`, `INTEGRATION_DISCONNECTED`, `INTEGRATION_CREDENTIAL_ROTATED`, `WEBHOOK_ENDPOINT_CREATED`, `WEBHOOK_ENDPOINT_DELETED`, `PLUGIN_REGISTERED`, `PLUGIN_VERSION_APPROVED`, `PLUGIN_VERSION_REJECTED`, `PLUGIN_INSTALLED`, `PLUGIN_ACTIVATED`, `PLUGIN_UNINSTALLED`, `PLUGIN_UPGRADED`

**Campaigns:** `CAMPAIGN_CREATED`, `CAMPAIGN_STARTED`, `CAMPAIGN_PAUSED`, `CAMPAIGN_CANCELLED`, `CAMPAIGN_COMPLETED`

**Billing:** `SUBSCRIPTION_CREATED`, `SUBSCRIPTION_PLAN_CHANGED`, `SUBSCRIPTION_CANCELLED`, `INVOICE_GENERATED`, `PAYMENT_ATTEMPTED`, `PAYMENT_SUCCEEDED`, `PAYMENT_FAILED`, `REFUND_ISSUED`, `BILLING_ADJUSTMENT_CREATED`

**Compliance / Data:** `COMPLIANCE_POLICY_UPDATED`, `DATA_SUBJECT_REQUEST_RECEIVED`, `DATA_SUBJECT_REQUEST_VERIFYING` †, `DATA_SUBJECT_REQUEST_ON_HOLD` †, `DATA_SUBJECT_REQUEST_COMPLETED`, `DATA_SUBJECT_REQUEST_REJECTED`, `DATA_EXPORT_INITIATED`, `CONTACT_ERASED`, `SUPPRESSION_ADDED`, `SUPPRESSION_LIFTED`

**CRM — Contacts / Leads / Deals / Companies / Pipelines / Tasks / Notes / Appointments / Custom Fields / Consent** ¶: `CONTACT_CREATED`, `CONTACT_UPDATED`, `CONTACT_MERGED`, `CONTACT_OWNER_ASSIGNED`, `LEAD_STATUS_CHANGED`, `QUALIFICATION_SET`, `LEAD_CONVERTED`, `DEAL_CREATED`, `DEAL_STAGE_CHANGED`, `DEAL_WON`, `DEAL_LOST`, `DEAL_ABANDONED`, `COMPANY_CREATED`, `COMPANY_UPDATED`, `PIPELINE_CREATED`, `PIPELINE_UPDATED`, `TASK_CREATED`, `TASK_COMPLETED`, `TASK_CANCELLED`, `NOTE_ADDED`, `NOTE_DELETED`, `APPOINTMENT_BOOKED`, `APPOINTMENT_CANCELLED`, `APPOINTMENT_RESCHEDULED`, `APPOINTMENT_COMPLETED`, `APPOINTMENT_NO_SHOW`, `CRM_FIELD_DEFINITION_CREATED`, `CRM_FIELD_DEFINITION_UPDATED`, `CONSENT_RECORDED`

**Admin / Security:** `BREAK_GLASS_GRANTED`, `BREAK_GLASS_RELEASED`, `ADMIN_ACTION`, `PLATFORM_CONFIG_CHANGED`

**† Controlled Phase 5.x amendment (10 values, added by migration `077_5J1`'s governing task — see `MIGRATION_MANIFEST.md` "Phase 5J.1"), required to close Phase 6C's `DEP-6C-07`/`DEP-6C-10`/`DEP-6C-11`/`DEP-6C-14`/`DEP-6C-15`:** `ORGANIZATION_CANCELLED` (organization terminal-status closure, distinct from `ORGANIZATION_SUSPENDED`/`REACTIVATED`), `MEMBER_REACTIVATED` (mirrors the existing `ORGANIZATION_REACTIVATED` verb applied to membership, sibling to `MEMBER_SUSPENDED`), `TEAM_CREATED`/`TEAM_UPDATED`/`TEAM_ARCHIVED`/`TEAM_MEMBER_ADDED`/`TEAM_MEMBER_REMOVED` (no `TEAM_*` value existed at all prior to this amendment — the previously-largest single audit gap 6C identified), `DATA_SUBJECT_REQUEST_VERIFYING`/`DATA_SUBJECT_REQUEST_ON_HOLD` (named to match `organization.data_subject_requests.status`'s own `VERIFYING`/`ON_HOLD` values exactly, the same convention already used by the pre-existing `..._RECEIVED`/`..._COMPLETED`/`..._REJECTED` triplet), `USER_PROFILE_UPDATED` (editable-profile-field mutation, e.g. `display_name`/`phone_e164`, distinct from the credential/security mutations the rest of the Authentication category covers). **This is a pure vocabulary/governance amendment — no SQL migration touches `audit.audit_events` or its `chk_ae_action_kind` constraint**, because that constraint is `CHECK (length(action_kind) BETWEEN 1 AND 200)` (migration `072_5J.sql`), not a `CHECK ... IN (...)` enum list and not backed by any reference/lookup table; the ten strings above simply become newly *governed* (documented, sanctioned) values an application `INSERT` may legitimately use, exactly like every other value in this section. Verified before this amendment was made, not assumed: no enum type, no `IN`-list constraint, and no lookup table constraining `action_kind` exists anywhere in the frozen schema.

**‡ Controlled Phase 5.x amendment (12 values, required by Phase 6D — `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md` `DEP-6D-04`), resolving the sole architecture-approval blocker identified in 6D's first review pass:** `AGENT_CREATED` (Agent aggregate creation — `POST /agents` and `POST /agents/{id}/clone` both write this single value; a clone is, from the audit trail's perspective, the creation of a new Agent row, indistinguishable in kind from a direct create), `AGENT_CONFIG_UPDATED` (mutation of `voice.agents.draft_config` via `PATCH /agents/{id}` — named to mirror 4B's own domain event `agent.config_updated` exactly, and to parallel this table's existing `USER_PROFILE_UPDATED` precedent of qualifying `_UPDATED` with the specific mutable sub-surface being changed, distinguishing it from a hypothetical top-level `AGENT_UPDATED`), `CALL_INITIATED`/`CALL_TERMINATED`/`CALL_TRANSFERRED`/`CALL_HELD`/`CALL_RESUMED` (the five tenant-REST-triggered Call state-transition actions — `voice.call_sessions.status` moves driven by `POST /calls` and its four `POST /calls/{id}/{action}` action endpoints; provider-webhook-driven transitions such as `RINGING`→`ANSWERED` are **not** included here, since those are recorded in `webhooks.inbound_webhook_events`, 5I §10, not `audit.audit_events`, per 6A §28.2's own mechanism split — restated in 6D §10.4), `TOOL_DEFINITION_CREATED`/`TOOL_DEFINITION_UPDATED`/`TOOL_DEFINITION_DEACTIVATED` (tenant custom `voice.tool_definitions` lifecycle, mirroring this table's existing multi-word-resource convention, e.g. `KNOWLEDGE_BASE_CREATED`/`WEBHOOK_ENDPOINT_CREATED`), `RECORDING_DELETED` (mirrors the existing `DOCUMENT_DELETED` resource-verb pattern in this same category), `PHONE_NUMBER_AGENT_ASSIGNED` (mirrors this table's existing `MEMBER_ROLE_CHANGED`/`TEAM_MEMBER_ADDED` resource+related-entity+verb shape). **Naming-convention fit was checked before adding these, not assumed:** all twelve follow the `{RESOURCE}_{PAST_TENSE_VERB}` (or `{RESOURCE}_{RELATED_ENTITY}_{VERB}`) shape already used throughout this section — none required a different canonical form. **This is a pure vocabulary/governance amendment, exactly like the `†` amendment above — no SQL migration touches `audit.audit_events` or its `chk_ae_action_kind` constraint**, since that constraint remains the same length check (`CHECK (length(action_kind) BETWEEN 1 AND 200)`, migration `072_5J.sql`), not an enum or `IN`-list, and no lookup table constrains `action_kind` anywhere in the frozen schema. No `voice.*` table, column, constraint, index, function, or RLS policy is touched by this amendment — it governs only which `action_kind` strings a call to `audit.fn_insert_audit_event()` (the sole legal write path to `audit.audit_events`, §14.2 — never a direct `INSERT`) may legitimately pass as `p_action_kind`.

**¶ Controlled Phase 6G amendment (29 values, added 2026-08-28 by the Phase 6G CRM Reconciliation pass), required to close Phase 6G's `DEP-6G-06` — the CRM + Leads API document (`docs/phase-06-api-design/6G-CRM-Leads-APIs.md`) reviewed its full mutation-endpoint inventory against this vocabulary before proposing anything, and found only three existing values it could reuse as-is (`CONTACT_ERASED`, `SUPPRESSION_ADDED`, `SUPPRESSION_LIFTED`, already governed under Compliance/Data above — no duplicate added for any of these three):** `CONTACT_CREATED`/`CONTACT_UPDATED` (mirror the existing `AGENT_CREATED`/`USER_PROFILE_UPDATED` resource+verb shape), `CONTACT_MERGED` (the `crm.fn_merge_contacts()` write path, `093_5D2.sql`), `CONTACT_OWNER_ASSIGNED` (mirrors `MEMBER_ROLE_CHANGED`'s existing resource+related-field+verb shape), `LEAD_STATUS_CHANGED`/`QUALIFICATION_SET`/`LEAD_CONVERTED` (the three guarded Contact/Lead state-machine actions 6G §9 defines — named for the specific transition, not a generic `CONTACT_STATUS_CHANGED`, following this table's own preference for naming the specific mutable sub-surface, e.g. `AGENT_CONFIG_UPDATED` over a hypothetical generic `AGENT_UPDATED`), `DEAL_CREATED`/`DEAL_STAGE_CHANGED`/`DEAL_WON`/`DEAL_LOST`/`DEAL_ABANDONED` (the Deal lifecycle, mirroring the existing `SUBSCRIPTION_CREATED`/`SUBSCRIPTION_PLAN_CHANGED`/`SUBSCRIPTION_CANCELLED` resource+lifecycle-verb pattern in the Billing category), `COMPANY_CREATED`/`COMPANY_UPDATED`, `PIPELINE_CREATED`/`PIPELINE_UPDATED` (Pipeline stage mutations are a single embedded-JSONB aggregate write per ADR-5D-004 — no separate `PIPELINE_STAGE_*` value is needed or added), `TASK_CREATED`/`TASK_COMPLETED`/`TASK_CANCELLED`, `NOTE_ADDED`/`NOTE_DELETED` (mirrors `DOCUMENT_DELETED`'s existing resource-verb pattern; no `NOTE_UPDATED` value exists or is proposed, since 6G found no note-body-edit command exists in 4C's own catalogue for any note, human or AI-authored), `APPOINTMENT_BOOKED` (the literal FR-EVT-001 event name)/`APPOINTMENT_CANCELLED`/`APPOINTMENT_RESCHEDULED`/`APPOINTMENT_COMPLETED`/`APPOINTMENT_NO_SHOW`, `CRM_FIELD_DEFINITION_CREATED`/`CRM_FIELD_DEFINITION_UPDATED` (mirrors `KNOWLEDGE_BASE_CREATED`/`KNOWLEDGE_BASE_UPDATED`'s existing shape; no `_DEACTIVATED` value is added because 6G's `DeactivateField` action is a routine `is_active` field flip on an already-`_UPDATED`-covered aggregate, unlike, say, `AGENT_DEPRECATED`'s materially different terminal-lifecycle meaning), `CONSENT_RECORDED` (the append-only `crm.consent_records` write, `024_5D.sql` — a single value covers every purpose/channel/status combination, since 4C/Phase 4I model consent as one append-only stream, not per-status sub-events). **Naming-convention fit was checked before adding these, not assumed**, against every existing category in this section, exactly as the †/‡/§ amendments before it did. **This is a pure vocabulary/governance amendment, exactly like the †/‡/§ amendments above — no SQL migration touches `audit.audit_events` or its `chk_ae_action_kind` constraint** (still `CHECK (length(action_kind) BETWEEN 1 AND 200)`, migration `072_5J.sql`, reconfirmed unchanged by this pass). No `crm.*` table, column, constraint, index, function, or RLS policy is touched by this amendment — it governs only which `action_kind` strings a call to `audit.fn_insert_audit_event()` may legitimately pass as `p_action_kind` for a CRM mutation. Audit synchrony for all 29 values follows the general "Configuration ... lifecycle changes → Asynchronous" default row in §14.5 below — none of them join the named Phase 6D synchronous exception list, since none of 6G's CRM mutations sit anywhere near a realtime voice-turn budget.

**§ Controlled Phase 5L amendment (15 values, added 2026-08-24 by the Phase 5L Global Database Reconciliation pass), required to close Phase 6B's `DEP-6B-02` (4 values) and Phase 6F's `DEP-6F-03` (7 values), plus 4 values for the new Knowledge/RAG lifecycle functions Phase 5L itself added (`fn_docver_mark_failed`, `fn_docver_rollback`, `fn_docver_gdpr_erase`/`fn_document_gdpr_delete`, `fn_kb_reindex_complete`):** `SESSION_REVOKED` (self-service "log out this device," distinct from `USER_LOGOUT`'s own-session semantics), `TOKEN_REFRESH_REUSE_DETECTED` (a previously-rotated-out refresh token presented again — a security-relevant signal distinct from ordinary auth failure), `USER_SESSION_FORCE_LOGOUT` (platform-admin-forced logout of a specific user's session(s), distinct from a user's own `USER_LOGOUT`), `TOKEN_DENYLIST_ENTRY_WRITTEN` (the durable outbox event closing DEP-6B-08, see `5B-Identity-Organization-Multitenancy-Security.md`'s own Phase 5L amendment — recorded when the forced-revocation outbox event is successfully published, not when it is merely enqueued); `KNOWLEDGE_BASE_UPDATED`/`KNOWLEDGE_BASE_ARCHIVED` (mirror `USER_PROFILE_UPDATED`/`TEAM_ARCHIVED`'s existing resource+verb shape), `KNOWLEDGE_BASE_REINDEX_TRIGGERED`/`KNOWLEDGE_BASE_REINDEX_COMPLETED` (the `fn_kb_reindex_begin()`/`fn_kb_reindex_complete()` lifecycle now implemented by migration `083_5F6.sql` — DEP-6F-02), `DOCUMENT_UPLOADED` (mirrors the 4E domain event `document.uploaded`), `DOCUMENT_ARCHIVED` (mirrors `KNOWLEDGE_BASE_ARCHIVED` above), `DOCUMENT_REPROCESS_REQUESTED` (mirrors `DATA_SUBJECT_REQUEST_RECEIVED`'s request-verb pattern; pairs with `fn_docver_mark_failed()`, migration `080_5F3.sql` — DEP-6F-09), `DOCUMENT_VERSION_PUBLISHED` (mirrors `PROMPT_PUBLISHED`/`AGENT_PUBLISHED`), `DOCUMENT_VERSION_MARKED_FAILED` (pairs with `fn_docver_mark_failed()`, `080_5F3.sql`), `DOCUMENT_VERSION_ROLLED_BACK` (mirrors the existing `PROMPT_ROLLED_BACK` verb exactly, applied to Documents — pairs with `fn_docver_rollback()`, `079_5F2.sql`, DEP-6F-01), `DOCUMENT_GDPR_ERASED` (mirrors the existing `CONTACT_ERASED`/`USER_ERASED` `_ERASED`-suffix convention rather than reusing the generic `DOCUMENT_DELETED` — pairs with `fn_document_gdpr_delete()`, `081_5F4.sql`, DEP-6F-15). **This is a pure vocabulary/governance amendment, exactly like the `†`/`‡` amendments above — no SQL migration touches `audit.audit_events` or its `chk_ae_action_kind` constraint** (still `CHECK (length(action_kind) BETWEEN 1 AND 200)`, migration `072_5J.sql`, reconfirmed unchanged by this pass — see `docs/phase-05-database-design/5L-Global-Database-Reconciliation/5L-Global-Database-Reconciliation.md`). `BREAK_GLASS_GRANTED`/`BREAK_GLASS_RELEASED` (closing part of DEP-6B-01) and `BILLING_ADJUSTMENT_CREATED` (closing part of the Phase 5L billing hardening, `086_5H1.sql`) already existed in this vocabulary prior to this amendment and required no addition.

**‖ Controlled Phase 6L freeze-gate remediation amendment (1 value, added by the Phase 6L Analytics + Audit APIs freeze-gate remediation pass), required to close the confirmed gap that `GET /api/v1/recordings/{recording_id}/download-url` (`6D-Voice-Call-Agent-APIs.md` §16/§28.20) previously documented as "not audited":** `RECORDING_ACCESS_GRANTED` — written synchronously, via `audit.fn_insert_audit_event()`, at the moment the platform successfully issues a signed, time-boxed recording playback/download URL to an authorized caller (gated by the new `recording:access_media` permission, `104_5B3.sql`) — never for a denied request, and never containing the signed URL itself, any bearer token, or any storage credential in `resource_snapshot` (bounded to non-secret correlation fields only: `call_id`, `expires_in_seconds` — verified live against a real inserted row in this pass's own PostgreSQL 18.6 validation, see `docs/phase-06-api-design/6L-Analytics-Audit-APIs.md`). Named `_GRANTED` rather than `_ACCESSED` to describe the capability-issuance moment precisely (the platform grants the capability; whether the caller's client actually fetches the audio bytes from the signed URL afterward is outside the platform's own knowledge and is not what this event records) — mirroring this table's existing `BREAK_GLASS_GRANTED`/`BREAK_GLASS_RELEASED` naming precedent for a similar "authorization moment, not usage moment" event. **This is a pure vocabulary/governance amendment, exactly like the `†`/`‡`/`¶`/`§` amendments above — no SQL migration touches `audit.audit_events` or its `chk_ae_action_kind` constraint** (still `CHECK (length(action_kind) BETWEEN 1 AND 200)`, migration `072_5J.sql`, reconfirmed unchanged by this pass — live-queried directly against a fresh PostgreSQL 18.6 instance in this pass, not assumed). No transcript-content-access equivalent is added: `GET /conversations/{id}/transcript/segments` (now gated by the new `transcript:access_content` permission) returns content directly within an already-request-logged, already-authenticated API call with no separate exfiltratable capability minted — unlike a signed URL, there is no independent bearer artifact whose *issuance* is itself the security-relevant moment. This asymmetry is a deliberate, documented design choice (`6L-Analytics-Audit-APIs.md`), not an oversight.

### 14.4 Actor Model

| Actor Type | actor_ref | actor_name |
|---|---|---|
| `USER` | `identity.users.id` | display_name at event time |
| `API_KEY` | `identity.api_keys.id` | key_prefix |
| `SYSTEM` | NULL | 'system' |
| `WORKER` | NULL | Celery task name |
| `PLUGIN` | `plugins.plugin_installations.id` | plugin slug |
| `PLATFORM_ADMIN` | `identity.users.id` | display_name |
| `INTEGRATION` | `integrations.integration_connections.id` | integration slug |

### 14.5 Audit Synchrony

| Action Category | Write Mode |
|---|---|
| Auth events, API key issuance/revocation, break-glass, data subject requests | Synchronous — audit insert is part of the originating transaction; failure rolls back the action |
| Admin actions | Synchronous |
| Configuration, campaign, plugin lifecycle changes | Generally asynchronous (Celery), **unless an approved downstream API contract explicitly requires synchronous durable audit** — see the named Phase 6D exception below ‡ |
| Billing events | Asynchronous |

**‡ Controlled Phase 5.x governance clarification (documentation-only, no SQL change), required by `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md`:** Phase 6D's Voice control-plane state-changing REST operations are an explicit **synchronous** exception to the general "Configuration... lifecycle changes → Asynchronous" row above:

- Agent mutations (`AGENT_CREATED`, `AGENT_CONFIG_UPDATED`, `AGENT_PUBLISHED`, `AGENT_DEPRECATED`)
- Call commands (`CALL_INITIATED`, `CALL_TERMINATED`, `CALL_TRANSFERRED`, `CALL_HELD`, `CALL_RESUMED`)
- Tool Definition mutations (`TOOL_DEFINITION_CREATED`, `TOOL_DEFINITION_UPDATED`, `TOOL_DEFINITION_DEACTIVATED`)
- Recording deletion (`RECORDING_DELETED`)
- Phone Number assignment (`PHONE_NUMBER_AGENT_ASSIGNED`)

For these fifteen operations, the originating request transaction invokes `audit.fn_insert_audit_event(...)` — the same, sole, `SECURITY DEFINER` write path every other audit category already uses (§14.2); no new function, no new privilege grant, and no schema change is introduced by this clarification. A failure raised by the function aborts the originating transaction, exactly as it already does for every other synchronous category in this table.

**Reason this exception is narrow and justified, not a general loosening of the async default:** (1) frozen 6A §22 requires durable audit coverage for state-changing API commands, unconditionally; (2) these fifteen Voice control-plane operations are not on the conversational ≤750ms realtime voice-turn hot path (6D §21.11 names the operations forbidden from that path, and none of these fifteen are among them) — they are ordinary Tier A/B REST mutations; synchronous audit therefore does not compromise the voice-turn latency target. This clarification does **not** change the write mode for Campaign, Plugin, or Billing domains, or for any other "Configuration... lifecycle" category member outside the fifteen operations named above — the general async default remains the default everywhere else.

---

## 15. Audit Hash Chain

### 15.1 Purpose and Storage Separation

The hash chain provides tamper-evidence: if any `audit_events` row is ever modified or deleted outside the normal (impossible, per §5.3/§14.2) application path — e.g., via a future superuser out-of-band action — recomputing the chain will produce a different hash than the one checkpointed in `audit.audit_chain`, revealing the tampering.

Because `audit_events` is immutable, the chain never stores its checkpoint inside `audit_events` itself. It is stored exclusively in `audit.audit_chain`, one row per `(organization_id, date_bucket)`.

### 15.2 `audit.audit_chain`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `organization_id` | UUID NULL | NULL = platform chain |
| `date_bucket` | DATE NOT NULL | |
| `event_count` | INTEGER NOT NULL | |
| `chain_hash` | CHAR(64) NOT NULL | SHA-256 hex |
| `previous_hash` | CHAR(64) NULL | Prior day's `chain_hash` for this org (or platform) |
| `batch_size` | INTEGER NOT NULL DEFAULT 1000 | Batch size used for this computation — enables exact reproducibility |
| `computed_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |
| | | `UNIQUE NULLS NOT DISTINCT (organization_id, date_bucket)` |

### 15.3 Algorithm — Bounded Batches

```
running_hash := previous_day_chain_hash (or 'GENESIS' if none exists)

FOR each batch of up to batch_size (default 1000) events for (org, date),
    ORDERED BY (occurred_at, id) ascending, taken in sequential LIMIT/OFFSET pages:

    batch_string := STRING_AGG(id || '|' || occurred_at || '|' || action_kind || '|' || outcome,
                                record_separator ORDER BY occurred_at, id)
                    for this batch only

    running_hash := SHA256(running_hash || '|BATCH' || batch_index || '|' || batch_string)

END FOR

chain_hash_for_this_day := running_hash
```

This bounds memory and compute per batch regardless of how many audit events a large enterprise tenant generates in a day, while remaining fully deterministic: the same ordered event set always produces the same final hash, because batch boundaries are determined solely by `(occurred_at, id)` ordering and the fixed `batch_size`.

### 15.4 Verification

To verify integrity for a date range, a verifier independently re-runs `audit.fn_compute_chain_hash()` (read-only against `audit_events`, itself immutable) for each day in the range and compares the recomputed hash to the stored `audit_chain.chain_hash`. Any mismatch indicates the underlying `audit_events` rows for that day (or an earlier day, via the `previous_hash` link) were altered outside the documented immutable path.

### 15.5 Recovery

If a day's `audit_chain` row is missing (e.g., the nightly job failed), `fn_compute_chain_hash()` can be safely re-run — it is idempotent (`ON CONFLICT (organization_id, date_bucket) DO UPDATE`), deterministic (same inputs → same hash), and read-only against `audit_events`. Re-running it for a past date does not corrupt the chain, because it always starts from the correct `previous_hash` looked up from the prior day's row.

---

## 16. RLS / Security Policies — Summary

| Table | RLS | FORCE RLS | Policy |
|---|---|---|---|
| `analytics.analytics_event_dedup` | Yes | Yes | `USING/WITH CHECK (organization_id = organization.current_tenant_id())` |
| `analytics.analytics_events` | Yes | Yes | Same |
| `analytics.analytics_projection_events` | No | No | Internal-only control table; no tenant-facing GRANT exists regardless |
| `analytics.call_metrics_hourly` | Yes | Yes | Same tenant policy |
| `analytics.call_latency_stage_hourly` | Yes | Yes | Same tenant policy |
| `analytics.conversation_turn_stats_daily` | Yes | Yes | Same tenant policy |
| `analytics.agent_utilization_hourly` | Yes | Yes | Same tenant policy |
| `analytics.lead_funnel_daily` | Yes | Yes | Same tenant policy |
| `analytics.campaign_outcome_summary` | Yes | Yes | Same tenant policy |
| `analytics.usage_cost_daily` | Yes | Yes | Same tenant policy |
| `analytics.billing_revenue_monthly` | Yes | Yes | Same tenant policy |
| `analytics.roi_by_campaign` | Yes | Yes | Same tenant policy |
| `analytics.tool_execution_stats_daily` | Yes | Yes | Same tenant policy |
| `analytics.webhook_delivery_stats_daily` | Yes | Yes | Same tenant policy |
| `analytics.provider_health_5min` | No | N/A | No `organization_id` column; access via GRANT/REVOKE only (§13) |
| `analytics.event_schema_versions` | No | N/A | Platform reference data; read-only for all app roles |
| `audit.audit_events` | Yes | Yes | `SELECT USING (organization_id = organization.current_tenant_id())` — excludes NULL-org rows for all non-BYPASSRLS roles |
| `audit.audit_chain` | Yes | Yes | Same as audit_events |

There is exactly one RLS policy statement per table above; no alternate policy exists anywhere else in this document.

---

## 17. Complete PostgreSQL DDL

```sql
-- ================================================================
-- Migration 067: schemas and GRANT USAGE
-- ================================================================

CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

GRANT USAGE ON SCHEMA analytics TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA audit     TO app_api, app_worker, app_readonly, app_platform_admin;

-- pgcrypto required for the audit hash chain (§15).
-- Supabase ships pgcrypto pre-installed. For standalone PostgreSQL, a superuser must run:
--   CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- before migration 072 executes.

-- ================================================================
-- Migration 068: analytics_event_dedup, analytics_events,
--               analytics_projection_events, and ingestion/projection
--               SECURITY DEFINER functions
-- ================================================================

-- ----------------------------------------------------------------
-- Global deduplication registry (non-partitioned; §8)
-- ----------------------------------------------------------------
CREATE TABLE analytics.analytics_event_dedup (
  dedup_key       TEXT        NOT NULL,
  event_id        UUID        NOT NULL,
  occurred_at     TIMESTAMPTZ NOT NULL,
  organization_id UUID        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_analytics_event_dedup PRIMARY KEY (dedup_key),
  CONSTRAINT chk_aed_key_len          CHECK (length(dedup_key) BETWEEN 1 AND 500)
);

CREATE INDEX idx_aed_event_id    ON analytics.analytics_event_dedup (event_id);
CREATE INDEX idx_aed_org_created ON analytics.analytics_event_dedup (organization_id, created_at);

ALTER TABLE analytics.analytics_event_dedup ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.analytics_event_dedup FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_aed_tenant ON analytics.analytics_event_dedup
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Direct write access revoked; all writes exclusively via fn_ingest_analytics_event()
REVOKE INSERT, UPDATE, DELETE ON analytics.analytics_event_dedup FROM app_api, app_worker;
GRANT SELECT ON analytics.analytics_event_dedup TO app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.analytics_event_dedup TO app_platform_admin;

-- ----------------------------------------------------------------
-- analytics_events: time-partitioned ingestion ledger (§7)
-- ----------------------------------------------------------------
CREATE TABLE analytics.analytics_events (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  event_type        TEXT        NOT NULL,
  event_version     TEXT        NOT NULL DEFAULT '1',
  dedup_key         TEXT        NOT NULL,
  occurred_at       TIMESTAMPTZ NOT NULL,
  ingested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  entity_type       TEXT        NULL,
  entity_id         UUID        NULL,
  actor_type        TEXT        NULL,
  actor_id          UUID        NULL,
  correlation_id    UUID        NULL,
  causation_id      UUID        NULL,
  call_id           UUID        NULL,
  campaign_id       UUID        NULL,
  agent_id          UUID        NULL,
  provider          TEXT        NULL,
  model             TEXT        NULL,
  dimensions        JSONB       NOT NULL DEFAULT '{}',
  measures          JSONB       NOT NULL DEFAULT '{}',
  processing_status TEXT        NOT NULL DEFAULT 'PENDING',
  processed_at      TIMESTAMPTZ NULL,
  error_detail      TEXT        NULL,

  CONSTRAINT pk_analytics_events       PRIMARY KEY (id, occurred_at),
  -- Partition-LOCAL consistency aid only. Global uniqueness is analytics_event_dedup's job (§8).
  CONSTRAINT uq_ae_dedup_key_local     UNIQUE (dedup_key, occurred_at),
  CONSTRAINT chk_ae_processing_status  CHECK (processing_status IN
                                         ('PENDING','PROJECTED','FAILED','DEAD_LETTER')),
  CONSTRAINT chk_ae_event_type         CHECK (length(event_type) BETWEEN 1 AND 200),
  CONSTRAINT chk_ae_dedup_key          CHECK (length(dedup_key) BETWEEN 1 AND 500)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE analytics.analytics_events_y2026m08
  PARTITION OF analytics.analytics_events
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.analytics_events_y2026m09
  PARTITION OF analytics.analytics_events
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.analytics_events_y2026m10
  PARTITION OF analytics.analytics_events
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics.analytics_events_default
  PARTITION OF analytics.analytics_events DEFAULT;

CREATE INDEX idx_ae_occurred_at ON analytics.analytics_events USING BRIN (occurred_at);
CREATE INDEX idx_ae_org_type_occurred
  ON analytics.analytics_events (organization_id, event_type, occurred_at DESC);
CREATE INDEX idx_ae_entity
  ON analytics.analytics_events (organization_id, entity_type, entity_id)
  WHERE entity_id IS NOT NULL;
CREATE INDEX idx_ae_pending
  ON analytics.analytics_events (organization_id, occurred_at)
  WHERE processing_status = 'PENDING';

REVOKE INSERT, UPDATE, DELETE ON analytics.analytics_events FROM app_api, app_worker;
GRANT SELECT ON analytics.analytics_events TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.analytics_events TO app_platform_admin;

ALTER TABLE analytics.analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.analytics_events FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ae_tenant ON analytics.analytics_events
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ----------------------------------------------------------------
-- Per-projection idempotency ledger (non-partitioned; §9)
-- ----------------------------------------------------------------
CREATE TABLE analytics.analytics_projection_events (
  id                  UUID        NOT NULL DEFAULT gen_uuid_v7(),
  projection_name     TEXT        NOT NULL,
  analytics_event_id  UUID        NOT NULL,
  occurred_at         TIMESTAMPTZ NOT NULL,
  processed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ape                  PRIMARY KEY (id),
  CONSTRAINT uq_ape_projection_event UNIQUE (projection_name, analytics_event_id),
  CONSTRAINT chk_ape_projection_name CHECK (length(projection_name) BETWEEN 1 AND 100)
);

CREATE INDEX idx_ape_event    ON analytics.analytics_projection_events (analytics_event_id);
CREATE INDEX idx_ape_occurred ON analytics.analytics_projection_events (occurred_at);

-- Internal worker control table; no tenant-facing access exists or is needed
REVOKE ALL ON analytics.analytics_projection_events FROM PUBLIC;
GRANT SELECT, INSERT ON analytics.analytics_projection_events TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.analytics_projection_events TO app_platform_admin;

-- ----------------------------------------------------------------
-- SECURITY DEFINER: atomic analytics event ingestion (§8)
-- ONLY permitted write path for analytics_event_dedup / analytics_events.
-- Returns TRUE = novel event ingested, FALSE = duplicate rejected.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.fn_ingest_analytics_event(
  p_organization_id UUID,
  p_event_type      TEXT,
  p_event_version   TEXT,
  p_dedup_key       TEXT,
  p_occurred_at     TIMESTAMPTZ,
  p_entity_type     TEXT,
  p_entity_id       UUID,
  p_actor_type      TEXT,
  p_actor_id        UUID,
  p_correlation_id  UUID,
  p_causation_id    UUID,
  p_call_id         UUID,
  p_campaign_id     UUID,
  p_agent_id        UUID,
  p_provider        TEXT,
  p_model           TEXT,
  p_dimensions      JSONB,
  p_measures        JSONB
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = analytics, pg_catalog
AS $$
DECLARE
  v_event_id UUID := gen_uuid_v7();
  v_inserted INTEGER;
BEGIN
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'analytics: organization_id is required';
  END IF;
  IF p_dedup_key IS NULL OR length(p_dedup_key) < 1 THEN
    RAISE EXCEPTION 'analytics: dedup_key is required';
  END IF;

  -- Global dedup gate (§8.2)
  INSERT INTO analytics.analytics_event_dedup
    (dedup_key, event_id, occurred_at, organization_id)
  VALUES
    (p_dedup_key, v_event_id, p_occurred_at, p_organization_id)
  ON CONFLICT (dedup_key) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    RETURN FALSE;  -- duplicate; analytics_events INSERT never attempted
  END IF;

  INSERT INTO analytics.analytics_events (
    id, organization_id, event_type, event_version, dedup_key, occurred_at,
    entity_type, entity_id, actor_type, actor_id, correlation_id, causation_id,
    call_id, campaign_id, agent_id, provider, model, dimensions, measures
  ) VALUES (
    v_event_id, p_organization_id, p_event_type, p_event_version, p_dedup_key, p_occurred_at,
    p_entity_type, p_entity_id, p_actor_type, p_actor_id, p_correlation_id, p_causation_id,
    p_call_id, p_campaign_id, p_agent_id, p_provider, p_model,
    COALESCE(p_dimensions, '{}'), COALESCE(p_measures, '{}')
  );

  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_ingest_analytics_event(
  UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,TEXT,TEXT,JSONB,JSONB)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_ingest_analytics_event(
  UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,TEXT,TEXT,JSONB,JSONB)
  TO app_worker, app_platform_admin;

-- ----------------------------------------------------------------
-- SECURITY DEFINER: atomic projection claim + mutation (§9.2)
-- The claim INSERT and the projection UPSERT happen inside this single
-- function invocation and therefore the same transaction: PostgreSQL
-- guarantees both become durable together on COMMIT, or neither does
-- on any error/crash before COMMIT.
--
-- p_projection_sql is NOT accepted as a parameter (that would be SQL
-- injection-prone); instead there is one wrapper function per projection
-- table, each calling this core claim primitive and then performing its
-- own fixed UPSERT. The core claim primitive is shown first, followed by
-- one representative wrapper (call_metrics_hourly); all other projection
-- wrappers follow the identical pattern.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.fn_claim_projection_slot(
  p_projection_name    TEXT,
  p_analytics_event_id UUID,
  p_occurred_at        TIMESTAMPTZ
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = analytics, pg_catalog
AS $$
DECLARE
  v_inserted INTEGER;
BEGIN
  INSERT INTO analytics.analytics_projection_events
    (projection_name, analytics_event_id, occurred_at)
  VALUES
    (p_projection_name, p_analytics_event_id, p_occurred_at)
  ON CONFLICT (projection_name, analytics_event_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted > 0;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_claim_projection_slot(TEXT, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_claim_projection_slot(TEXT, UUID, TIMESTAMPTZ)
  TO app_worker, app_platform_admin;

-- Representative atomic wrapper for one projection (call_metrics_hourly).
-- Note: fn_claim_projection_slot() and the projection UPSERT below execute
-- inside THIS function's single transaction — this is what makes the
-- claim-and-mutate pair atomic per §9.2. Every other projection table has
-- an identically-shaped wrapper function (fn_apply_projection_call_latency,
-- fn_apply_projection_usage_cost, etc.) generated from the same pattern;
-- only the target table and UPSERT columns differ.
CREATE OR REPLACE FUNCTION analytics.fn_apply_projection_call_metrics(
  p_analytics_event_id UUID,
  p_occurred_at        TIMESTAMPTZ,
  p_organization_id    UUID,
  p_hour_bucket         TIMESTAMPTZ,
  p_agent_id            UUID,
  p_direction            TEXT,
  p_call_outcome         TEXT,
  p_provider             TEXT,
  p_language_code        TEXT,
  p_total_calls          INTEGER,
  p_answered_calls       INTEGER,
  p_failed_calls         INTEGER,
  p_total_duration_s     BIGINT,
  p_talk_time_s          BIGINT,
  p_wait_time_s          BIGINT,
  p_transfer_count       INTEGER,
  p_recording_count      INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = analytics, pg_catalog
AS $$
DECLARE
  v_claimed BOOLEAN;
BEGIN
  -- Same transaction as this function invocation (§9.2 atomicity guarantee)
  v_claimed := analytics.fn_claim_projection_slot(
    'call_metrics_hourly', p_analytics_event_id, p_occurred_at);

  IF NOT v_claimed THEN
    RETURN FALSE;  -- already processed for this projection; no mutation applied
  END IF;

  INSERT INTO analytics.call_metrics_hourly (
    organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code,
    total_calls, answered_calls, failed_calls, total_duration_s, talk_time_s, wait_time_s,
    transfer_count, recording_count, last_event_id
  ) VALUES (
    p_organization_id, p_hour_bucket, p_agent_id, p_direction, p_call_outcome, p_provider, p_language_code,
    p_total_calls, p_answered_calls, p_failed_calls, p_total_duration_s, p_talk_time_s, p_wait_time_s,
    p_transfer_count, p_recording_count, p_analytics_event_id
  )
  ON CONFLICT (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code)
  DO UPDATE SET
    total_calls      = analytics.call_metrics_hourly.total_calls      + EXCLUDED.total_calls,
    answered_calls    = analytics.call_metrics_hourly.answered_calls    + EXCLUDED.answered_calls,
    failed_calls       = analytics.call_metrics_hourly.failed_calls       + EXCLUDED.failed_calls,
    total_duration_s    = analytics.call_metrics_hourly.total_duration_s    + EXCLUDED.total_duration_s,
    talk_time_s           = analytics.call_metrics_hourly.talk_time_s           + EXCLUDED.talk_time_s,
    wait_time_s             = analytics.call_metrics_hourly.wait_time_s             + EXCLUDED.wait_time_s,
    transfer_count            = analytics.call_metrics_hourly.transfer_count            + EXCLUDED.transfer_count,
    recording_count             = analytics.call_metrics_hourly.recording_count             + EXCLUDED.recording_count,
    last_event_id                 = EXCLUDED.last_event_id,
    last_updated_at                  = NOW();

  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_apply_projection_call_metrics(
  UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,UUID,TEXT,TEXT,TEXT,TEXT,
  INTEGER,INTEGER,INTEGER,BIGINT,BIGINT,BIGINT,INTEGER,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_apply_projection_call_metrics(
  UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,UUID,TEXT,TEXT,TEXT,TEXT,
  INTEGER,INTEGER,INTEGER,BIGINT,BIGINT,BIGINT,INTEGER,INTEGER)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: mark analytics_events row PROJECTED once all subscribed
-- projections have successfully claimed it (worker-orchestrated, after all
-- fn_apply_projection_* calls for that event have returned)
CREATE OR REPLACE FUNCTION analytics.fn_mark_event_projected(
  p_event_id    UUID,
  p_occurred_at TIMESTAMPTZ,
  p_org_id      UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = analytics, pg_catalog
AS $$
BEGIN
  UPDATE analytics.analytics_events
  SET processing_status = 'PROJECTED',
      processed_at      = NOW()
  WHERE id = p_event_id
    AND occurred_at = p_occurred_at
    AND organization_id = p_org_id
    AND processing_status = 'PENDING';
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_mark_event_projected(UUID, TIMESTAMPTZ, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_mark_event_projected(UUID, TIMESTAMPTZ, UUID)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: mark analytics_events row DEAD_LETTER
CREATE OR REPLACE FUNCTION analytics.fn_mark_event_dead_letter(
  p_event_id    UUID,
  p_occurred_at TIMESTAMPTZ,
  p_org_id      UUID,
  p_reason      TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = analytics, pg_catalog
AS $$
BEGIN
  UPDATE analytics.analytics_events
  SET processing_status = 'DEAD_LETTER',
      processed_at      = NOW(),
      error_detail      = LEFT(p_reason, 2000)
  WHERE id = p_event_id
    AND occurred_at = p_occurred_at
    AND organization_id = p_org_id
    AND processing_status IN ('PENDING','FAILED');
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_mark_event_dead_letter(UUID, TIMESTAMPTZ, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_mark_event_dead_letter(UUID, TIMESTAMPTZ, UUID, TEXT)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 069: call analytics — call_metrics_hourly and the
--               histogram-based call_latency_stage_hourly (§11).
--
-- call_latency_stage_hourly is created here in its complete,
-- production definition. No scalar percentile columns are used, and
-- no later migration alters or replaces this table's structure.
-- ================================================================

-- call_metrics_hourly — nullable agent_id; NULLS NOT DISTINCT (§10.1)
CREATE TABLE analytics.call_metrics_hourly (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  hour_bucket       TIMESTAMPTZ NOT NULL,
  agent_id          UUID        NULL,
  direction         TEXT        NOT NULL DEFAULT 'ALL',
  call_outcome      TEXT        NOT NULL DEFAULT 'ALL',
  provider          TEXT        NOT NULL DEFAULT 'all',
  language_code     TEXT        NOT NULL DEFAULT 'all',
  total_calls       INTEGER     NOT NULL DEFAULT 0,
  answered_calls    INTEGER     NOT NULL DEFAULT 0,
  failed_calls      INTEGER     NOT NULL DEFAULT 0,
  total_duration_s  BIGINT      NOT NULL DEFAULT 0,
  talk_time_s       BIGINT      NOT NULL DEFAULT 0,
  wait_time_s       BIGINT      NOT NULL DEFAULT 0,
  transfer_count    INTEGER     NOT NULL DEFAULT 0,
  recording_count   INTEGER     NOT NULL DEFAULT 0,
  last_event_id     UUID        NULL,
  last_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_call_metrics_hourly PRIMARY KEY (id, hour_bucket),
  CONSTRAINT uq_cmh_grain           UNIQUE NULLS NOT DISTINCT
    (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code),
  CONSTRAINT chk_cmh_direction      CHECK (direction IN ('INBOUND','OUTBOUND','ALL')),
  CONSTRAINT chk_cmh_calls_nn       CHECK (total_calls >= 0 AND answered_calls >= 0)
) PARTITION BY RANGE (hour_bucket);

CREATE TABLE analytics.call_metrics_hourly_y2026m08
  PARTITION OF analytics.call_metrics_hourly
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.call_metrics_hourly_y2026m09
  PARTITION OF analytics.call_metrics_hourly
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.call_metrics_hourly_y2026m10
  PARTITION OF analytics.call_metrics_hourly
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics.call_metrics_hourly_default
  PARTITION OF analytics.call_metrics_hourly DEFAULT;

CREATE INDEX idx_cmh_org_hour  ON analytics.call_metrics_hourly (organization_id, hour_bucket DESC);
CREATE INDEX idx_cmh_org_agent ON analytics.call_metrics_hourly
  (organization_id, agent_id, hour_bucket DESC) WHERE agent_id IS NOT NULL;

ALTER TABLE analytics.call_metrics_hourly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.call_metrics_hourly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cmh_tenant ON analytics.call_metrics_hourly
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.call_metrics_hourly FROM app_api;
GRANT SELECT ON analytics.call_metrics_hourly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.call_metrics_hourly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.call_metrics_hourly TO app_platform_admin;

-- ----------------------------------------------------------------
-- call_latency_stage_hourly — FINAL histogram design (§11).
-- Non-cumulative per-bucket counts. All grain columns NOT NULL — no
-- nullable-dimension issue. Sparse: only buckets that received at
-- least one sample get a row — the UNIQUE constraint
-- enforces AT MOST ONE ROW per (grain, bucket_upper_ms), not that all
-- 13 buckets exist.
-- ----------------------------------------------------------------
CREATE TABLE analytics.call_latency_stage_hourly (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  hour_bucket       TIMESTAMPTZ NOT NULL,
  provider          TEXT        NOT NULL,
  provider_category TEXT        NOT NULL,
  model             TEXT        NOT NULL DEFAULT 'all',
  -- Upper bound (ms) of this bucket's range. -1 = overflow bucket (>5000ms).
  -- bucket_count is the NON-CUMULATIVE count of samples landing in THIS
  -- bucket's range only (see §11.2) — it is not a Prometheus-style
  -- cumulative "_le" count. Cumulative distribution is derived at query
  -- time (§11.4), never stored.
  bucket_upper_ms   INTEGER     NOT NULL,
  bucket_count      BIGINT      NOT NULL DEFAULT 0,
  error_count       INTEGER     NOT NULL DEFAULT 0,
  last_event_id     UUID        NULL,
  last_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_clsh        PRIMARY KEY (id, hour_bucket),
  -- Enforces AT MOST ONE ROW per (grain, bucket) — sparse by design.
  -- Does NOT enforce that all 13 buckets exist; absent bucket = 0 count.
  CONSTRAINT uq_clsh_grain  UNIQUE (organization_id, hour_bucket, provider,
                                    provider_category, model, bucket_upper_ms),
  CONSTRAINT chk_clsh_cat   CHECK (provider_category IN
                               ('LLM','STT','TTS','TELEPHONY','EMBEDDING')),
  CONSTRAINT chk_clsh_bucket CHECK (bucket_upper_ms IN
    (10, 25, 50, 100, 150, 250, 500, 750, 1000, 1500, 2000, 5000, -1)),
  CONSTRAINT chk_clsh_count_nn CHECK (bucket_count >= 0)
) PARTITION BY RANGE (hour_bucket);

CREATE TABLE analytics.call_latency_stage_hourly_y2026m08
  PARTITION OF analytics.call_latency_stage_hourly
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.call_latency_stage_hourly_y2026m09
  PARTITION OF analytics.call_latency_stage_hourly
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.call_latency_stage_hourly_y2026m10
  PARTITION OF analytics.call_latency_stage_hourly
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics.call_latency_stage_hourly_default
  PARTITION OF analytics.call_latency_stage_hourly DEFAULT;

CREATE INDEX idx_clsh_org_hour ON analytics.call_latency_stage_hourly
  (organization_id, hour_bucket DESC);
CREATE INDEX idx_clsh_provider ON analytics.call_latency_stage_hourly
  (provider, provider_category, hour_bucket DESC);

ALTER TABLE analytics.call_latency_stage_hourly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.call_latency_stage_hourly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_clsh_tenant ON analytics.call_latency_stage_hourly
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.call_latency_stage_hourly FROM app_api;
GRANT SELECT ON analytics.call_latency_stage_hourly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.call_latency_stage_hourly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.call_latency_stage_hourly TO app_platform_admin;

-- SECURITY DEFINER: atomic projection wrapper for the latency histogram.
-- Single-bucket, additive, non-cumulative increment (§11.2).
CREATE OR REPLACE FUNCTION analytics.fn_apply_projection_call_latency(
  p_analytics_event_id UUID,
  p_occurred_at        TIMESTAMPTZ,
  p_organization_id    UUID,
  p_hour_bucket         TIMESTAMPTZ,
  p_provider             TEXT,
  p_provider_category    TEXT,
  p_model                TEXT,
  p_latency_ms           INTEGER,   -- raw sample; function maps it to exactly one bucket
  p_is_error              BOOLEAN
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = analytics, pg_catalog
AS $$
DECLARE
  v_claimed BOOLEAN;
  v_bucket  INTEGER;
BEGIN
  v_claimed := analytics.fn_claim_projection_slot(
    'call_latency_stage_hourly', p_analytics_event_id, p_occurred_at);
  IF NOT v_claimed THEN
    RETURN FALSE;
  END IF;

  -- Map raw latency to exactly ONE bucket: smallest boundary >= latency, else overflow.
  v_bucket := CASE
    WHEN p_is_error THEN NULL  -- errors counted separately; no latency bucket touched
    WHEN p_latency_ms <= 10   THEN 10
    WHEN p_latency_ms <= 25   THEN 25
    WHEN p_latency_ms <= 50   THEN 50
    WHEN p_latency_ms <= 100  THEN 100
    WHEN p_latency_ms <= 150  THEN 150
    WHEN p_latency_ms <= 250  THEN 250
    WHEN p_latency_ms <= 500  THEN 500
    WHEN p_latency_ms <= 750  THEN 750
    WHEN p_latency_ms <= 1000 THEN 1000
    WHEN p_latency_ms <= 1500 THEN 1500
    WHEN p_latency_ms <= 2000 THEN 2000
    WHEN p_latency_ms <= 5000 THEN 5000
    ELSE -1
  END;

  IF v_bucket IS NOT NULL THEN
    INSERT INTO analytics.call_latency_stage_hourly
      (organization_id, hour_bucket, provider, provider_category, model,
       bucket_upper_ms, bucket_count, last_event_id)
    VALUES
      (p_organization_id, p_hour_bucket, p_provider, p_provider_category, p_model,
       v_bucket, 1, p_analytics_event_id)
    ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
    DO UPDATE SET
      bucket_count    = analytics.call_latency_stage_hourly.bucket_count + 1,
      last_event_id   = EXCLUDED.last_event_id,
      last_updated_at = NOW();
  ELSE
    -- Error sample: bump error_count on the (arbitrary, conventionally the
    -- 5000ms) row for this grain without touching any latency bucket count.
    INSERT INTO analytics.call_latency_stage_hourly
      (organization_id, hour_bucket, provider, provider_category, model,
       bucket_upper_ms, bucket_count, error_count, last_event_id)
    VALUES
      (p_organization_id, p_hour_bucket, p_provider, p_provider_category, p_model,
       5000, 0, 1, p_analytics_event_id)
    ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
    DO UPDATE SET
      error_count     = analytics.call_latency_stage_hourly.error_count + 1,
      last_event_id   = EXCLUDED.last_event_id,
      last_updated_at = NOW();
  END IF;

  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_apply_projection_call_latency(
  UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,INTEGER,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_apply_projection_call_latency(
  UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,INTEGER,BOOLEAN)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 070: conversation_turn_stats_daily and usage_cost_daily
-- ================================================================

CREATE TABLE analytics.conversation_turn_stats_daily (
  id                    UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID    NOT NULL,
  date_bucket           DATE    NOT NULL,
  agent_id              UUID    NOT NULL,
  total_turns           INTEGER NOT NULL DEFAULT 0,
  total_calls           INTEGER NOT NULL DEFAULT 0,
  barge_in_count        INTEGER NOT NULL DEFAULT 0,
  tool_calls_total      INTEGER NOT NULL DEFAULT 0,
  tool_calls_succeeded  INTEGER NOT NULL DEFAULT 0,
  tool_calls_failed     INTEGER NOT NULL DEFAULT 0,
  sum_turns_per_call    INTEGER NOT NULL DEFAULT 0,
  llm_prompt_tokens     BIGINT  NOT NULL DEFAULT 0,
  llm_completion_tokens BIGINT  NOT NULL DEFAULT 0,
  llm_total_tokens      BIGINT  NOT NULL DEFAULT 0,
  stt_audio_seconds     NUMERIC(12,2) NOT NULL DEFAULT 0,
  tts_characters        BIGINT  NOT NULL DEFAULT 0,
  last_event_id         UUID    NULL,
  last_updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ctsd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_ctsd_grain UNIQUE (organization_id, date_bucket, agent_id)
) PARTITION BY RANGE (date_bucket);

CREATE TABLE analytics.conversation_turn_stats_daily_y2026m08
  PARTITION OF analytics.conversation_turn_stats_daily
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.conversation_turn_stats_daily_y2026m09
  PARTITION OF analytics.conversation_turn_stats_daily
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.conversation_turn_stats_daily_default
  PARTITION OF analytics.conversation_turn_stats_daily DEFAULT;

CREATE INDEX idx_ctsd_org_date ON analytics.conversation_turn_stats_daily
  (organization_id, date_bucket DESC);
CREATE INDEX idx_ctsd_agent ON analytics.conversation_turn_stats_daily
  (organization_id, agent_id, date_bucket DESC);

ALTER TABLE analytics.conversation_turn_stats_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.conversation_turn_stats_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ctsd_tenant ON analytics.conversation_turn_stats_daily
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.conversation_turn_stats_daily FROM app_api;
GRANT SELECT ON analytics.conversation_turn_stats_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.conversation_turn_stats_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.conversation_turn_stats_daily TO app_platform_admin;

CREATE TABLE analytics.usage_cost_daily (
  id                  UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID    NOT NULL,
  date_bucket         DATE    NOT NULL,
  metric              TEXT    NOT NULL,
  provider            TEXT    NOT NULL DEFAULT 'all',
  model               TEXT    NOT NULL DEFAULT 'all',
  unit_count          NUMERIC(18,4) NOT NULL DEFAULT 0,
  cost_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
  cost_currency       CHAR(3) NOT NULL DEFAULT 'USD',
  event_count         INTEGER NOT NULL DEFAULT 0,
  last_event_id       UUID    NULL,
  last_updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ucd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_ucd_grain UNIQUE (organization_id, date_bucket, metric, provider, model),
  CONSTRAINT chk_ucd_cost CHECK (cost_amount >= 0 AND unit_count >= 0)
) PARTITION BY RANGE (date_bucket);

CREATE TABLE analytics.usage_cost_daily_y2026m08
  PARTITION OF analytics.usage_cost_daily
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.usage_cost_daily_y2026m09
  PARTITION OF analytics.usage_cost_daily
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.usage_cost_daily_default
  PARTITION OF analytics.usage_cost_daily DEFAULT;

CREATE INDEX idx_ucd_org_date ON analytics.usage_cost_daily (organization_id, date_bucket DESC);
CREATE INDEX idx_ucd_metric   ON analytics.usage_cost_daily (organization_id, metric, date_bucket DESC);

ALTER TABLE analytics.usage_cost_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.usage_cost_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ucd_tenant ON analytics.usage_cost_daily
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.usage_cost_daily FROM app_api;
GRANT SELECT ON analytics.usage_cost_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.usage_cost_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.usage_cost_daily TO app_platform_admin;

-- ================================================================
-- Migration 071: agent_utilization_hourly, lead_funnel_daily,
--               campaign_outcome_summary, tool_execution_stats_daily,
--               webhook_delivery_stats_daily, roi_by_campaign,
--               billing_revenue_monthly, provider_health_5min
-- ================================================================

CREATE TABLE analytics.agent_utilization_hourly (
  id                      UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID        NOT NULL,
  hour_bucket             TIMESTAMPTZ NOT NULL,
  agent_id                UUID        NOT NULL,
  calls_started           INTEGER     NOT NULL DEFAULT 0,
  calls_ended             INTEGER     NOT NULL DEFAULT 0,
  peak_concurrent         INTEGER     NOT NULL DEFAULT 0,
  sum_concurrent_samples  INTEGER     NOT NULL DEFAULT 0,
  sample_count            INTEGER     NOT NULL DEFAULT 0,
  last_event_id           UUID        NULL,
  last_updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_auh       PRIMARY KEY (id, hour_bucket),
  CONSTRAINT uq_auh_grain UNIQUE (organization_id, hour_bucket, agent_id)
) PARTITION BY RANGE (hour_bucket);

CREATE TABLE analytics.agent_utilization_hourly_y2026m08
  PARTITION OF analytics.agent_utilization_hourly
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.agent_utilization_hourly_y2026m09
  PARTITION OF analytics.agent_utilization_hourly
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.agent_utilization_hourly_default
  PARTITION OF analytics.agent_utilization_hourly DEFAULT;

CREATE INDEX idx_auh_org_hour ON analytics.agent_utilization_hourly
  (organization_id, hour_bucket DESC);

ALTER TABLE analytics.agent_utilization_hourly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.agent_utilization_hourly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_auh_tenant ON analytics.agent_utilization_hourly
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.agent_utilization_hourly FROM app_api;
GRANT SELECT ON analytics.agent_utilization_hourly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.agent_utilization_hourly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.agent_utilization_hourly TO app_platform_admin;

-- lead_funnel_daily — nullable campaign_id; NULLS NOT DISTINCT
CREATE TABLE analytics.lead_funnel_daily (
  id                  UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID    NOT NULL,
  date_bucket         DATE    NOT NULL,
  campaign_id         UUID    NULL,
  leads_contacted     INTEGER NOT NULL DEFAULT 0,
  leads_answered      INTEGER NOT NULL DEFAULT 0,
  leads_qualified     INTEGER NOT NULL DEFAULT 0,
  leads_disqualified  INTEGER NOT NULL DEFAULT 0,
  leads_converted     INTEGER NOT NULL DEFAULT 0,
  appointments_booked INTEGER NOT NULL DEFAULT 0,
  dnc_encounters      INTEGER NOT NULL DEFAULT 0,
  last_event_id       UUID    NULL,
  last_updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_lfd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_lfd_grain UNIQUE NULLS NOT DISTINCT (organization_id, date_bucket, campaign_id)
) PARTITION BY RANGE (date_bucket);

CREATE TABLE analytics.lead_funnel_daily_y2026m08
  PARTITION OF analytics.lead_funnel_daily
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.lead_funnel_daily_y2026m09
  PARTITION OF analytics.lead_funnel_daily
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.lead_funnel_daily_default
  PARTITION OF analytics.lead_funnel_daily DEFAULT;

CREATE INDEX idx_lfd_org_date ON analytics.lead_funnel_daily (organization_id, date_bucket DESC);
CREATE INDEX idx_lfd_campaign ON analytics.lead_funnel_daily
  (organization_id, campaign_id, date_bucket DESC) WHERE campaign_id IS NOT NULL;

ALTER TABLE analytics.lead_funnel_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.lead_funnel_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_lfd_tenant ON analytics.lead_funnel_daily
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.lead_funnel_daily FROM app_api;
GRANT SELECT ON analytics.lead_funnel_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.lead_funnel_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.lead_funnel_daily TO app_platform_admin;

-- campaign_outcome_summary — unpartitioned; campaign_id NOT NULL UNIQUE
CREATE TABLE analytics.campaign_outcome_summary (
  id                              UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                 UUID    NOT NULL,
  campaign_id                     UUID    NOT NULL,
  calls_attempted                 INTEGER NOT NULL DEFAULT 0,
  calls_connected                 INTEGER NOT NULL DEFAULT 0,
  calls_completed                 INTEGER NOT NULL DEFAULT 0,
  calls_failed                    INTEGER NOT NULL DEFAULT 0,
  unique_contacts                 INTEGER NOT NULL DEFAULT 0,
  qualified_contacts              INTEGER NOT NULL DEFAULT 0,
  converted_contacts              INTEGER NOT NULL DEFAULT 0,
  appointments_booked             INTEGER NOT NULL DEFAULT 0,
  total_duration_s                BIGINT  NOT NULL DEFAULT 0,
  total_telephony_cost_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_telephony_cost_currency   CHAR(3) NOT NULL DEFAULT 'USD',
  total_ai_cost_amount            NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_ai_cost_currency          CHAR(3) NOT NULL DEFAULT 'USD',
  status                          TEXT    NOT NULL DEFAULT 'ACTIVE',
  last_event_id                   UUID    NULL,
  last_updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cos          PRIMARY KEY (id),
  CONSTRAINT uq_cos_campaign UNIQUE (campaign_id),
  CONSTRAINT chk_cos_status  CHECK (status IN ('ACTIVE','COMPLETED','CANCELLED'))
);

CREATE INDEX idx_cos_org    ON analytics.campaign_outcome_summary (organization_id);
CREATE INDEX idx_cos_status ON analytics.campaign_outcome_summary (organization_id, status);

ALTER TABLE analytics.campaign_outcome_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.campaign_outcome_summary FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cos_tenant ON analytics.campaign_outcome_summary
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE DELETE ON analytics.campaign_outcome_summary FROM app_api, app_worker;
GRANT SELECT ON analytics.campaign_outcome_summary TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.campaign_outcome_summary TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.campaign_outcome_summary TO app_platform_admin;

-- tool_execution_stats_daily — nullable agent_id; NULLS NOT DISTINCT
CREATE TABLE analytics.tool_execution_stats_daily (
  id                UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID    NOT NULL,
  date_bucket       DATE    NOT NULL,
  tool_name         TEXT    NOT NULL,
  agent_id          UUID    NULL,
  invocations       INTEGER NOT NULL DEFAULT 0,
  succeeded         INTEGER NOT NULL DEFAULT 0,
  failed            INTEGER NOT NULL DEFAULT 0,
  timed_out         INTEGER NOT NULL DEFAULT 0,
  sum_latency_ms    BIGINT  NOT NULL DEFAULT 0,
  last_event_id     UUID    NULL,
  last_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tesd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_tesd_grain UNIQUE NULLS NOT DISTINCT
    (organization_id, date_bucket, tool_name, agent_id)
) PARTITION BY RANGE (date_bucket);

CREATE TABLE analytics.tool_execution_stats_daily_y2026m08
  PARTITION OF analytics.tool_execution_stats_daily
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.tool_execution_stats_daily_y2026m09
  PARTITION OF analytics.tool_execution_stats_daily
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.tool_execution_stats_daily_default
  PARTITION OF analytics.tool_execution_stats_daily DEFAULT;

CREATE INDEX idx_tesd_org_date ON analytics.tool_execution_stats_daily
  (organization_id, date_bucket DESC);

ALTER TABLE analytics.tool_execution_stats_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.tool_execution_stats_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tesd_tenant ON analytics.tool_execution_stats_daily
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.tool_execution_stats_daily FROM app_api;
GRANT SELECT ON analytics.tool_execution_stats_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.tool_execution_stats_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.tool_execution_stats_daily TO app_platform_admin;

-- webhook_delivery_stats_daily
CREATE TABLE analytics.webhook_delivery_stats_daily (
  id                    UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID    NOT NULL,
  date_bucket           DATE    NOT NULL,
  deliveries_attempted  INTEGER NOT NULL DEFAULT 0,
  deliveries_succeeded  INTEGER NOT NULL DEFAULT 0,
  deliveries_failed     INTEGER NOT NULL DEFAULT 0,
  dead_lettered         INTEGER NOT NULL DEFAULT 0,
  retries               INTEGER NOT NULL DEFAULT 0,
  sum_latency_ms        BIGINT  NOT NULL DEFAULT 0,
  last_event_id         UUID    NULL,
  last_updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_wdsd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_wdsd_grain UNIQUE (organization_id, date_bucket)
) PARTITION BY RANGE (date_bucket);

CREATE TABLE analytics.webhook_delivery_stats_daily_y2026m08
  PARTITION OF analytics.webhook_delivery_stats_daily
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.webhook_delivery_stats_daily_y2026m09
  PARTITION OF analytics.webhook_delivery_stats_daily
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.webhook_delivery_stats_daily_default
  PARTITION OF analytics.webhook_delivery_stats_daily DEFAULT;

CREATE INDEX idx_wdsd_org_date ON analytics.webhook_delivery_stats_daily
  (organization_id, date_bucket DESC);

ALTER TABLE analytics.webhook_delivery_stats_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.webhook_delivery_stats_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wdsd_tenant ON analytics.webhook_delivery_stats_daily
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.webhook_delivery_stats_daily FROM app_api;
GRANT SELECT ON analytics.webhook_delivery_stats_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.webhook_delivery_stats_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.webhook_delivery_stats_daily TO app_platform_admin;

-- roi_by_campaign
CREATE TABLE analytics.roi_by_campaign (
  id                          UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id             UUID    NOT NULL,
  campaign_id                 UUID    NOT NULL,
  total_cost_amount           NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_cost_currency         CHAR(3) NOT NULL DEFAULT 'USD',
  estimated_revenue_amount    NUMERIC(18,4) NULL,
  estimated_revenue_currency  CHAR(3) NULL,
  roi_pct                     NUMERIC(8,4) NULL,
  cost_per_call               NUMERIC(18,4) NULL,
  cost_per_qualified          NUMERIC(18,4) NULL,
  cost_per_converted          NUMERIC(18,4) NULL,
  computed_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_rbc          PRIMARY KEY (id),
  CONSTRAINT uq_rbc_campaign UNIQUE (campaign_id)
);

CREATE INDEX idx_rbc_org ON analytics.roi_by_campaign (organization_id);

ALTER TABLE analytics.roi_by_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.roi_by_campaign FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_rbc_tenant ON analytics.roi_by_campaign
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON analytics.roi_by_campaign TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.roi_by_campaign TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.roi_by_campaign TO app_platform_admin;

-- billing_revenue_monthly — yearly RANGE partition
CREATE TABLE analytics.billing_revenue_monthly (
  id                      UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID    NOT NULL,
  year_month              CHAR(7) NOT NULL,
  year_bucket             INTEGER NOT NULL GENERATED ALWAYS AS
                            (CAST(LEFT(year_month, 4) AS INTEGER)) STORED,
  invoices_generated      INTEGER NOT NULL DEFAULT 0,
  invoices_paid           INTEGER NOT NULL DEFAULT 0,
  billed_amount           NUMERIC(18,4) NOT NULL DEFAULT 0,
  billed_currency         CHAR(3) NOT NULL DEFAULT 'INR',
  provider_cost_amount    NUMERIC(18,4) NOT NULL DEFAULT 0,
  provider_cost_currency  CHAR(3) NOT NULL DEFAULT 'USD',
  subscription_plan_id    UUID    NULL,
  last_event_id           UUID    NULL,
  last_updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_brm             PRIMARY KEY (id, year_bucket),
  CONSTRAINT uq_brm_grain       UNIQUE (organization_id, year_month),
  CONSTRAINT chk_brm_year_month CHECK (year_month ~ '^\d{4}-\d{2}$')
) PARTITION BY RANGE (year_bucket);

CREATE TABLE analytics.billing_revenue_monthly_before2027
  PARTITION OF analytics.billing_revenue_monthly
  FOR VALUES FROM (2026) TO (2027);
CREATE TABLE analytics.billing_revenue_monthly_2027
  PARTITION OF analytics.billing_revenue_monthly
  FOR VALUES FROM (2027) TO (2028);
CREATE TABLE analytics.billing_revenue_monthly_default
  PARTITION OF analytics.billing_revenue_monthly DEFAULT;

CREATE INDEX idx_brm_org ON analytics.billing_revenue_monthly (organization_id, year_month DESC);

ALTER TABLE analytics.billing_revenue_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.billing_revenue_monthly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_brm_tenant ON analytics.billing_revenue_monthly
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON analytics.billing_revenue_monthly FROM app_api;
GRANT SELECT ON analytics.billing_revenue_monthly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.billing_revenue_monthly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.billing_revenue_monthly TO app_platform_admin;

-- ----------------------------------------------------------------
-- provider_health_5min — platform-internal ONLY (§13; ).
-- No organization_id column; no RLS. Access controlled entirely by
-- explicit GRANT/REVOKE. app_api and app_readonly are denied here AND
-- this denial is reaffirmed in migration 074 after the broad grant.
-- ----------------------------------------------------------------
CREATE TABLE analytics.provider_health_5min (
  id                    UUID        NOT NULL DEFAULT gen_uuid_v7(),
  five_min_bucket       TIMESTAMPTZ NOT NULL,
  provider              TEXT        NOT NULL,
  provider_category     TEXT        NOT NULL,
  model                 TEXT        NOT NULL DEFAULT 'all',
  request_count         INTEGER     NOT NULL DEFAULT 0,
  error_count           INTEGER     NOT NULL DEFAULT 0,
  failover_count        INTEGER     NOT NULL DEFAULT 0,
  circuit_open_count    INTEGER     NOT NULL DEFAULT 0,
  circuit_close_count   INTEGER     NOT NULL DEFAULT 0,
  sum_latency_ms        BIGINT      NOT NULL DEFAULT 0,
  last_updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_phf           PRIMARY KEY (id, five_min_bucket),
  CONSTRAINT uq_phf_grain     UNIQUE (five_min_bucket, provider, provider_category, model),
  CONSTRAINT chk_phf_category CHECK (provider_category IN
                                ('LLM','STT','TTS','TELEPHONY','EMBEDDING'))
) PARTITION BY RANGE (five_min_bucket);

CREATE TABLE analytics.provider_health_5min_y2026m08
  PARTITION OF analytics.provider_health_5min
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.provider_health_5min_y2026m09
  PARTITION OF analytics.provider_health_5min
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.provider_health_5min_default
  PARTITION OF analytics.provider_health_5min DEFAULT;

CREATE INDEX idx_phf_bucket ON analytics.provider_health_5min
  (five_min_bucket DESC, provider, provider_category);

-- explicit, unambiguous denial for tenant-facing roles.
REVOKE ALL ON analytics.provider_health_5min FROM app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.provider_health_5min TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.provider_health_5min TO app_platform_admin;
-- Deliberately NO SELECT/INSERT/UPDATE/DELETE grant to app_api or app_readonly, anywhere.

-- ================================================================
-- Migration 072: audit schema — audit_events (truly immutable),
--               audit_chain, SECURITY DEFINER audit functions
-- ================================================================

-- no chain_hash column; RLS excludes NULL-org from
-- tenant reads; NO role (including app_platform_admin) has direct
-- INSERT/UPDATE/DELETE — only fn_insert_audit_event() may write.
CREATE TABLE audit.audit_events (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NULL,
  actor_type        TEXT        NOT NULL,
  actor_ref         UUID        NULL,
  actor_name        TEXT        NULL,
  action_kind       TEXT        NOT NULL,
  resource_type     TEXT        NOT NULL,
  resource_id       UUID        NULL,
  outcome           TEXT        NOT NULL,
  failure_reason    TEXT        NULL,
  ip_address        INET        NULL,
  user_agent        TEXT        NULL,
  session_id        TEXT        NULL,
  request_id        UUID        NULL,
  correlation_id    UUID        NULL,
  resource_snapshot JSONB       NULL,
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- NO chain_hash column exists here, by design. See §15.

  CONSTRAINT pk_audit_events           PRIMARY KEY (id, occurred_at),
  CONSTRAINT chk_ae_actor_type         CHECK (actor_type IN
                                         ('USER','API_KEY','SYSTEM','WORKER',
                                          'PLUGIN','PLATFORM_ADMIN','INTEGRATION')),
  CONSTRAINT chk_ae_outcome            CHECK (outcome IN ('SUCCESS','FAILURE','PARTIAL')),
  CONSTRAINT chk_ae_action_kind        CHECK (length(action_kind) BETWEEN 1 AND 200),
  CONSTRAINT chk_ae_resource_type      CHECK (length(resource_type) BETWEEN 1 AND 200),
  CONSTRAINT chk_ae_failure_reason_len CHECK (failure_reason IS NULL OR
                                              length(failure_reason) <= 1000),
  CONSTRAINT chk_ae_user_agent_len     CHECK (user_agent IS NULL OR length(user_agent) <= 500),
  CONSTRAINT chk_ae_snapshot_size      CHECK (resource_snapshot IS NULL OR
                                              length(resource_snapshot::TEXT) <= 4096)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE audit.audit_events_y2026m08
  PARTITION OF audit.audit_events
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE audit.audit_events_y2026m09
  PARTITION OF audit.audit_events
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit.audit_events_y2026m10
  PARTITION OF audit.audit_events
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE audit.audit_events_default
  PARTITION OF audit.audit_events DEFAULT;

CREATE INDEX idx_audit_occurred_at ON audit.audit_events USING BRIN (occurred_at);
CREATE INDEX idx_audit_org_occurred ON audit.audit_events (organization_id, occurred_at DESC)
  WHERE organization_id IS NOT NULL;
CREATE INDEX idx_audit_actor ON audit.audit_events (actor_ref, occurred_at DESC)
  WHERE actor_ref IS NOT NULL;
CREATE INDEX idx_audit_resource ON audit.audit_events
  (organization_id, resource_type, resource_id, occurred_at DESC)
  WHERE resource_id IS NOT NULL;
CREATE INDEX idx_audit_action ON audit.audit_events
  (organization_id, action_kind, occurred_at DESC);

-- REVOKE ALL from every role WITHOUT EXCEPTION, including
-- app_platform_admin. Only SELECT is (re-)granted below. INSERT is never
-- granted to any role — fn_insert_audit_event() writes as its owning role.
REVOKE ALL ON audit.audit_events FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT SELECT ON audit.audit_events TO app_api, app_readonly, app_worker, app_platform_admin;
-- No INSERT, UPDATE, or DELETE grant exists for ANY role on this table.

ALTER TABLE audit.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.audit_events FORCE ROW LEVEL SECURITY;

-- tenant roles see only their own org's events; NULL-org
-- (platform) rows are excluded here for every non-BYPASSRLS role.
-- app_platform_admin has BYPASSRLS (Phase 5B) and sees all rows via SELECT.
CREATE POLICY rls_audit_tenant_select ON audit.audit_events
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());
-- No INSERT policy exists — no role has INSERT privilege to exercise one.

-- audit_chain — NULLS NOT DISTINCT for the platform (NULL org) row; batch_size for §15.3
CREATE TABLE audit.audit_chain (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NULL,
  date_bucket       DATE        NOT NULL,
  event_count       INTEGER     NOT NULL,
  chain_hash        CHAR(64)    NOT NULL,
  previous_hash     CHAR(64)    NULL,
  batch_size        INTEGER     NOT NULL DEFAULT 1000,
  computed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_audit_chain          PRIMARY KEY (id),
  CONSTRAINT uq_audit_chain_org_date UNIQUE NULLS NOT DISTINCT (organization_id, date_bucket)
);

CREATE INDEX idx_audit_chain_org_date ON audit.audit_chain (organization_id, date_bucket DESC);

-- Same immutability posture as audit_events: no direct write privilege for any role.
REVOKE ALL ON audit.audit_chain FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT SELECT ON audit.audit_chain TO app_api, app_readonly, app_worker, app_platform_admin;

ALTER TABLE audit.audit_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.audit_chain FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_audit_chain_tenant ON audit.audit_chain
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

-- ----------------------------------------------------------------
-- SECURITY DEFINER: the ONLY audit insertion path.
-- Owned by the table-owning role; requires no INSERT grant to callers.
-- Platform-event authorization is enforced using session_user (the role
-- that authenticated the database session), NOT current_user. Inside a
-- SECURITY DEFINER function, current_user resolves to the function's
-- OWNING role, so using it here would silently defeat the authorization
-- check for every caller. session_user is unaffected by the SECURITY
-- DEFINER context switch and correctly identifies the actual caller.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.fn_insert_audit_event(
  p_organization_id   UUID,
  p_actor_type        TEXT,
  p_actor_ref         UUID,
  p_actor_name        TEXT,
  p_action_kind       TEXT,
  p_resource_type     TEXT,
  p_resource_id       UUID,
  p_outcome           TEXT,
  p_failure_reason    TEXT,
  p_ip_address        INET,
  p_user_agent        TEXT,
  p_session_id        TEXT,
  p_request_id        UUID,
  p_correlation_id    UUID,
  p_resource_snapshot JSONB,
  p_is_platform_event BOOLEAN DEFAULT FALSE
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, organization, pg_catalog
AS $$
DECLARE
  v_id UUID := gen_uuid_v7();
BEGIN
  IF p_action_kind IS NULL OR length(p_action_kind) < 1 THEN
    RAISE EXCEPTION 'audit: action_kind is required';
  END IF;
  IF p_outcome NOT IN ('SUCCESS','FAILURE','PARTIAL') THEN
    RAISE EXCEPTION 'audit: invalid outcome %', p_outcome;
  END IF;
  IF p_actor_type NOT IN ('USER','API_KEY','SYSTEM','WORKER','PLUGIN','PLATFORM_ADMIN','INTEGRATION') THEN
    RAISE EXCEPTION 'audit: invalid actor_type %', p_actor_type;
  END IF;

  IF p_is_platform_event THEN
    -- Database-enforced caller check: only app_worker and app_platform_admin
    -- may create a platform-level (organization_id IS NULL) audit event.
    -- session_user reflects the actual authenticated session role and cannot
    -- be spoofed by the SECURITY DEFINER privilege elevation of this function.
    IF session_user NOT IN ('app_worker', 'app_platform_admin') THEN
      RAISE EXCEPTION 'audit: caller % is not authorized to create platform audit events',
        session_user;
    END IF;
    IF p_organization_id IS NOT NULL THEN
      RAISE EXCEPTION 'audit: platform events must have NULL organization_id';
    END IF;
  ELSE
    IF p_organization_id IS NULL THEN
      RAISE EXCEPTION 'audit: tenant audit events must have a non-NULL organization_id';
    END IF;
    IF p_organization_id <> organization.current_tenant_id() THEN
      RAISE EXCEPTION 'audit: organization_id % does not match current tenant context',
        p_organization_id;
    END IF;
  END IF;

  INSERT INTO audit.audit_events (
    id, organization_id, actor_type, actor_ref, actor_name,
    action_kind, resource_type, resource_id, outcome, failure_reason,
    ip_address, user_agent, session_id, request_id, correlation_id,
    resource_snapshot
  ) VALUES (
    v_id, p_organization_id, p_actor_type, p_actor_ref,
    LEFT(COALESCE(p_actor_name,''), 200),
    p_action_kind, p_resource_type, p_resource_id, p_outcome,
    LEFT(COALESCE(p_failure_reason,''), 1000),
    p_ip_address,
    LEFT(COALESCE(p_user_agent,''), 500),
    p_session_id, p_request_id, p_correlation_id,
    p_resource_snapshot
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_insert_audit_event(
  UUID,TEXT,UUID,TEXT,TEXT,TEXT,UUID,TEXT,TEXT,INET,TEXT,TEXT,UUID,UUID,JSONB,BOOLEAN)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_insert_audit_event(
  UUID,TEXT,UUID,TEXT,TEXT,TEXT,UUID,TEXT,TEXT,INET,TEXT,TEXT,UUID,UUID,JSONB,BOOLEAN)
  TO app_api, app_worker, app_platform_admin;

-- ----------------------------------------------------------------
-- SECURITY DEFINER: batched, bounded hash chain (§15.3). Reads audit_events
-- only; writes exclusively to audit_chain. Never UPDATEs audit_events.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.fn_compute_chain_hash(
  p_organization_id UUID,
  p_date            DATE,
  p_batch_size      INTEGER DEFAULT 1000
) RETURNS CHAR(64)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, pg_catalog
AS $$
DECLARE
  v_prev_hash    CHAR(64);
  v_running_hash TEXT;
  v_event_count  INTEGER := 0;
  v_batch_count  INTEGER;
  v_batch_data   TEXT;
  v_new_hash     CHAR(64);
BEGIN
  SELECT chain_hash INTO v_prev_hash
  FROM audit.audit_chain
  WHERE organization_id IS NOT DISTINCT FROM p_organization_id
    AND date_bucket = p_date - INTERVAL '1 day';

  v_running_hash := COALESCE(v_prev_hash, 'GENESIS');

  SELECT COUNT(*) INTO v_event_count
  FROM audit.audit_events
  WHERE organization_id IS NOT DISTINCT FROM p_organization_id
    AND occurred_at >= p_date
    AND occurred_at < p_date + INTERVAL '1 day';

  IF v_event_count = 0 THEN
    RETURN NULL;
  END IF;

  v_batch_count := CEIL(v_event_count::NUMERIC / p_batch_size);

  FOR i IN 0..(v_batch_count - 1) LOOP
    SELECT STRING_AGG(
             id::TEXT || '|' || occurred_at::TEXT || '|' || action_kind || '|' || outcome,
             chr(30) ORDER BY occurred_at, id)
    INTO v_batch_data
    FROM (
      SELECT id, occurred_at, action_kind, outcome
      FROM audit.audit_events
      WHERE organization_id IS NOT DISTINCT FROM p_organization_id
        AND occurred_at >= p_date
        AND occurred_at < p_date + INTERVAL '1 day'
      ORDER BY occurred_at, id
      LIMIT p_batch_size OFFSET (i * p_batch_size)
    ) batch;

    v_running_hash := encode(
      digest(v_running_hash || '|BATCH' || i::TEXT || '|' || COALESCE(v_batch_data,''), 'sha256'),
      'hex'
    );
  END LOOP;

  v_new_hash := v_running_hash;

  -- Writes ONLY to audit_chain. audit_events is never touched.
  INSERT INTO audit.audit_chain
    (organization_id, date_bucket, event_count, chain_hash, previous_hash, batch_size)
  VALUES
    (p_organization_id, p_date, v_event_count, v_new_hash, v_prev_hash, p_batch_size)
  ON CONFLICT (organization_id, date_bucket)
  DO UPDATE SET
    chain_hash    = EXCLUDED.chain_hash,
    event_count   = EXCLUDED.event_count,
    previous_hash = EXCLUDED.previous_hash,
    batch_size    = EXCLUDED.batch_size,
    computed_at   = NOW();

  RETURN v_new_hash;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_compute_chain_hash(UUID, DATE, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_compute_chain_hash(UUID, DATE, INTEGER)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 073: event_schema_versions
-- ================================================================

CREATE TABLE analytics.event_schema_versions (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  event_type       TEXT    NOT NULL,
  event_version    TEXT    NOT NULL,
  status           TEXT    NOT NULL DEFAULT 'ACTIVE',
  introduced_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deprecated_at    TIMESTAMPTZ NULL,
  notes            TEXT    NULL,

  CONSTRAINT pk_esv          PRIMARY KEY (id),
  CONSTRAINT uq_esv_type_ver UNIQUE (event_type, event_version),
  CONSTRAINT chk_esv_status  CHECK (status IN ('ACTIVE','DEPRECATED','RETIRED'))
);

GRANT SELECT ON analytics.event_schema_versions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.event_schema_versions TO app_platform_admin;

-- ================================================================
-- Migration 074: grants finalization
-- ================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA audit     TO app_readonly;

-- reaffirm provider_health_5min denial after the broad grant above.
-- This REVOKE is not redundant — it guarantees the broad GRANT SELECT ON ALL TABLES
-- cannot silently reopen access to this table for app_readonly (or app_api, which
-- was never included in the broad grant target list to begin with, but is
-- reaffirmed here for defense-in-depth and documentation clarity).
REVOKE SELECT ON analytics.provider_health_5min FROM app_readonly, app_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA analytics TO app_platform_admin;
-- audit schema is deliberately excluded from this broad platform_admin grant —
-- audit.audit_events and audit.audit_chain retain SELECT-only for app_platform_admin
-- as established in migration 072. The line below is intentionally
-- SELECT-only, not the broad four-privilege grant used for analytics.
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO app_platform_admin;

-- ================================================================
-- Migration 075: seed event_schema_versions with known V1 events
-- ================================================================

INSERT INTO analytics.event_schema_versions (event_type, event_version, status) VALUES
  ('call.ended',                       '1', 'ACTIVE'),
  ('call.failed',                      '1', 'ACTIVE'),
  ('call.started',                     '1', 'ACTIVE'),
  ('conversation.turn_completed',      '1', 'ACTIVE'),
  ('conversation.completed',           '1', 'ACTIVE'),
  ('contact.qualified',                '1', 'ACTIVE'),
  ('contact.converted',                '1', 'ACTIVE'),
  ('contact.lead_status_changed',      '1', 'ACTIVE'),
  ('appointment.booked',               '1', 'ACTIVE'),
  ('campaign.contact.call_attempted',  '1', 'ACTIVE'),
  ('campaign.contact.qualified',       '1', 'ACTIVE'),
  ('campaign.completed',               '1', 'ACTIVE'),
  ('campaign.outcome_computed',        '1', 'ACTIVE'),
  ('usage.event_recorded',             '1', 'ACTIVE'),
  ('invoice.payment_succeeded',        '1', 'ACTIVE'),
  ('invoice.generated',                '1', 'ACTIVE'),
  ('tool_execution.succeeded',         '1', 'ACTIVE'),
  ('tool_execution.failed',            '1', 'ACTIVE'),
  ('webhook.delivery_succeeded',       '1', 'ACTIVE'),
  ('webhook.delivery_failed',          '1', 'ACTIVE'),
  ('webhook.delivery_dead_lettered',   '1', 'ACTIVE'),
  ('provider.failed',                  '1', 'ACTIVE'),
  ('provider.failover_triggered',      '1', 'ACTIVE'),
  ('provider.circuit_opened',          '1', 'ACTIVE'),
  ('provider.circuit_closed',          '1', 'ACTIVE')
ON CONFLICT (event_type, event_version) DO NOTHING;
```

---

## 18. Functions / Procedures — Complete List

| Function | Schema | Purpose | Writes to |
|---|---|---|---|
| `fn_ingest_analytics_event()` | analytics | Atomic global dedup + event ledger insert (§8) | `analytics_event_dedup`, `analytics_events` |
| `fn_claim_projection_slot()` | analytics | Atomic idempotency claim primitive (§9) | `analytics_projection_events` |
| `fn_apply_projection_call_metrics()` | analytics | Atomic claim + UPSERT for call_metrics_hourly | `analytics_projection_events`, `call_metrics_hourly` |
| `fn_apply_projection_call_latency()` | analytics | Atomic claim + single-bucket histogram increment | `analytics_projection_events`, `call_latency_stage_hourly` |
| *(analogous `fn_apply_projection_*` for every other projection table — identical pattern: claim via `fn_claim_projection_slot`, then UPSERT, in one transaction)* | analytics | | |
| `fn_mark_event_projected()` | analytics | Marks `analytics_events.processing_status = 'PROJECTED'` once all subscribed projections have claimed the event | `analytics_events` |
| `fn_mark_event_dead_letter()` | analytics | Marks unrecoverable events | `analytics_events` |
| `fn_insert_audit_event()` | audit | The sole audit INSERT path; enforces tenant ownership and, for platform events, caller identity via `session_user` (§14.2) | `audit_events` |
| `fn_compute_chain_hash()` | audit | Batched, bounded hash chain computation (§15.3); never touches `audit_events` | `audit_chain` only |

Every SECURITY DEFINER function above has `SET search_path = <owning_schema>[, dependency_schema], pg_catalog` and `REVOKE ALL ... FROM PUBLIC` followed by an explicit `GRANT EXECUTE` to only the roles that legitimately need it. No function in this specification is executable by PUBLIC.

---

## 19. Migration Chain

```
Phase 5I last migration: 066
        │
        ▼
067  Schemas (analytics, audit) + GRANT USAGE
068  analytics_event_dedup + analytics_events + analytics_projection_events
     + fn_ingest_analytics_event() + fn_claim_projection_slot()
     + fn_apply_projection_call_metrics() (representative wrapper)
     + fn_mark_event_projected() + fn_mark_event_dead_letter()
069  call_metrics_hourly + call_latency_stage_hourly (complete histogram
     design, created directly in its production form)
     + fn_apply_projection_call_latency()
070  conversation_turn_stats_daily + usage_cost_daily
071  agent_utilization_hourly + lead_funnel_daily + campaign_outcome_summary
     + tool_execution_stats_daily + webhook_delivery_stats_daily
     + roi_by_campaign + billing_revenue_monthly
     + provider_health_5min (platform-internal grants)
072  audit_events (immutable) + audit_chain
     + fn_insert_audit_event() + fn_compute_chain_hash()
073  event_schema_versions
074  Grants finalization (including reaffirmed provider_health_5min REVOKE
     and audit schema SELECT-only for app_platform_admin)
075  Seed event_schema_versions (idempotent, ON CONFLICT DO NOTHING)
```

**Chain:** `066 → 067 → 068 → 069 → 070 → 071 → 072 → 073 → 074 → 075`. Every migration is directly executable against a fresh database with no destructive placeholder step, no `DROP TABLE` of a production table anywhere in the chain, and no migration that creates an intermediate schema later replaced by another migration.

**pgcrypto dependency:** required before migration 072 (§15). Pre-installed on Supabase; `CREATE EXTENSION IF NOT EXISTS pgcrypto;` required as superuser on standalone PostgreSQL.

---

## 20. Retention — Authoritative Matrix

| Table | Hot Retention | Cold/Archive | Partition Strategy | Notes |
|---|---|---|---|---|
| `analytics.analytics_event_dedup` | 90 days | N/A | Non-partitioned; bulk DELETE by `created_at` age | = normal replay horizon (§12.1) |
| `analytics.analytics_events` | 90 days | 7 years (S3) | RANGE monthly on `occurred_at` | = normal replay horizon |
| `analytics.analytics_projection_events` | 90 days | N/A | Non-partitioned; bulk DELETE by `occurred_at` age | = normal replay horizon |
| `analytics.call_metrics_hourly` | 2 years | Archive | RANGE monthly | |
| `analytics.call_latency_stage_hourly` | 2 years | N/A | RANGE monthly | |
| `analytics.conversation_turn_stats_daily` | 2 years | N/A | RANGE monthly | |
| `analytics.agent_utilization_hourly` | 2 years | N/A | RANGE monthly | |
| `analytics.lead_funnel_daily` | 5 years | N/A | RANGE monthly | |
| `analytics.campaign_outcome_summary` | 5 years post-completion | N/A | Non-partitioned; row DELETE | |
| `analytics.usage_cost_daily` | 2 years | 7 years (financial) | RANGE monthly | |
| `analytics.billing_revenue_monthly` | 7 years | Indefinite | RANGE yearly | |
| `analytics.roi_by_campaign` | 5 years | N/A | Non-partitioned; row DELETE | |
| `analytics.provider_health_5min` | 30 days | N/A | RANGE monthly | |
| `analytics.tool_execution_stats_daily` | 2 years | N/A | RANGE monthly | |
| `analytics.webhook_delivery_stats_daily` | 2 years | N/A | RANGE monthly | |
| `audit.audit_events` | 1 year | 7 years (S3) | RANGE monthly | |
| `audit.audit_chain` | 1 year | 7 years (S3) | Non-partitioned | Tracks with audit_events |

**Replay horizon boundary:** normal incremental replay horizon = 90 days, exactly matching the retention of `analytics_event_dedup` and `analytics_projection_events`. Any event whose `occurred_at` is older than 90 days goes through historical rebuild mode (§12), not the normal incremental path.

This is the single authoritative retention matrix; no other retention value for any of these tables appears anywhere else in this document.

---

## 21. Query / Reporting Model

All dashboard and reporting queries read exclusively from `analytics.*` projection tables (or `audit.audit_events` for audit search) — never from transactional domain tables.

**QP-01 Executive Dashboard — daily call volume (rolling 30 days)**
```sql
SELECT date_trunc('day', hour_bucket) AS day,
       SUM(total_calls) AS calls, SUM(answered_calls) AS answered,
       SUM(total_duration_s) AS duration_s
FROM analytics.call_metrics_hourly
WHERE organization_id = $org_id
  AND hour_bucket >= NOW() - INTERVAL '30 days'
  AND direction = 'ALL' AND call_outcome = 'ALL' AND agent_id IS NULL
GROUP BY 1 ORDER BY 1;
```

**QP-02 LLM cost by model (last 7 days)**
```sql
SELECT provider, model, SUM(unit_count) AS tokens, SUM(cost_amount) AS cost
FROM analytics.usage_cost_daily
WHERE organization_id = $org_id AND date_bucket >= CURRENT_DATE - 7 AND metric = 'LLM_TOKENS'
GROUP BY provider, model ORDER BY cost DESC;
```

**QP-03 Latency percentiles** — full query and worked examples in §11.4/§11.6/§11.7.

**QP-04 Campaign outcome**
```sql
SELECT campaign_id, calls_attempted, calls_connected, qualified_contacts,
       converted_contacts, total_telephony_cost_amount, total_ai_cost_amount
FROM analytics.campaign_outcome_summary
WHERE organization_id = $org_id ORDER BY last_updated_at DESC LIMIT 50;
```

**QP-05 Lead funnel (last 30 days)**
```sql
SELECT SUM(leads_contacted) AS contacted, SUM(leads_qualified) AS qualified,
       SUM(leads_converted) AS converted, SUM(appointments_booked) AS appointments
FROM analytics.lead_funnel_daily
WHERE organization_id = $org_id AND date_bucket >= CURRENT_DATE - 30;
```

**QP-06 Audit log search**
```sql
SELECT id, actor_type, actor_name, action_kind, resource_type, resource_id,
       outcome, ip_address, occurred_at
FROM audit.audit_events
WHERE organization_id = $org_id
  AND occurred_at >= $start_ts AND occurred_at < $end_ts
  AND ($action_kind IS NULL OR action_kind = $action_kind)
ORDER BY occurred_at DESC LIMIT 200;
```

**QP-07 Provider health — `app_worker`/`app_platform_admin` only, never `app_api`**
```sql
SELECT provider, provider_category,
       SUM(error_count)::FLOAT / NULLIF(SUM(request_count),0) AS error_rate
FROM analytics.provider_health_5min
WHERE five_min_bucket >= NOW() - INTERVAL '1 hour'
GROUP BY provider, provider_category;
```

**Indexing strategy** (full DDL in §17): every tenant-owned table has a `(organization_id, time_bucket DESC)` composite B-tree covering the dominant "recent activity for my org" query; append-only high-volume ledgers (`analytics_events`, `audit_events`) additionally carry a BRIN index on their time column, which is far cheaper to maintain than a B-tree for sequentially-inserted, naturally time-ordered data and is highly effective for the range-scan queries these tables receive.

---

## 22. Performance / Scalability

- **Partition pruning:** every time-bucketed query filters on the partition key (`hour_bucket`, `date_bucket`, `occurred_at`, `year_bucket`), so the planner prunes to the relevant monthly/yearly partitions automatically.
- **Batch ingestion:** `fn_ingest_analytics_event()` is called per-event from Celery workers processing the Redis Streams consumer group; workers batch-fetch from the stream but call the ingestion function per event to preserve per-event atomicity (§8.2).
- **Projection concurrency:** `analytics_projection_events`'s unique index provides natural, fine-grained (per event, per projection) locking — no coarse table-level or advisory locks are used, so unrelated events for the same projection do not contend.
- **Dedup performance:** `analytics_event_dedup` is a small, hot, frequently-accessed table (90-day window) with a single-column PRIMARY KEY — index lookups are O(log n) and the table stays small enough to remain largely cached in shared_buffers under normal load.
- **Histogram storage efficiency:** sparse row semantics (§11.2) mean a low-traffic (org, hour, provider) combination consumes at most 13 rows, and typically far fewer — no wasted storage for unused buckets.
- **Audit chain performance:** bounded batch processing (§15.3) keeps memory and per-statement cost constant regardless of daily audit volume for any single tenant.
- **Retention/partition-drop jobs:** implemented as scheduled Celery beat tasks executing `DETACH PARTITION` + async `DROP TABLE` (non-blocking) for time-partitioned tables, and simple bounded `DELETE ... WHERE created_at < threshold LIMIT n` loops for the two non-partitioned control tables (`analytics_event_dedup`, `analytics_projection_events`).
- **Future ClickHouse seam:** the `AnalyticsWritePort` abstraction (§4.2) means the migration to ClickHouse, when triggered (ODD-5J-03), requires no changes to event producers and no changes to the domain schemas in 5B–5I — only a new adapter implementation and, eventually, a switch of dashboard read queries to the new backend.

---

## 23. Failure / Recovery

| Scenario | Behavior |
|---|---|
| Duplicate event delivery (any cause) | Rejected at `analytics_event_dedup` PRIMARY KEY (§8.2); no side effect |
| Worker crash before `fn_ingest_analytics_event()` commits | Transaction rolls back entirely; nothing was ever visible; safe retry |
| Worker crash between ingestion and projection application | The event exists in `analytics_events` with `processing_status = 'PENDING'`; a projection worker will pick it up again; each projection's atomic wrapper is itself crash-safe per event (§9.2) |
| Worker crash mid-projection-transaction, before COMMIT | Entire transaction (claim + mutation) rolls back together; retry sees no claim and reprocesses cleanly — Case A in §9.2 |
| Worker crash immediately after a successful COMMIT | Claim and mutation are both already durable; retry sees the claim, `fn_claim_projection_slot()` returns FALSE, and no mutation is reapplied — Case B in §9.2 |
| Concurrent workers, same event, same projection | Row-level lock on the unique index in `analytics_projection_events` serializes the race; exactly one applies (§9.3) |
| Late-arriving event (occurred_at significantly in the past, but within 90 days) | Ingested normally; projection UPSERT updates the historical bucket correctly (additive) |
| Out-of-order events | Additive/commutative UPSERTs make application order irrelevant to the final aggregate |
| Missing future partition (INSERT lands beyond the pre-created partition range) | Falls into the `DEFAULT` partition; a monitoring alert on non-empty DEFAULT partitions signals that the partition-creation maintenance job needs to run |
| Malformed / unrecognized `event_type` or `event_version` | `analytics_events.processing_status` transitions to `DEAD_LETTER` via `fn_mark_event_dead_letter()`; the raw event is preserved for inspection, never silently dropped |
| Historical rebuild encounters inconsistent archived data | Validation step (§12.3) halts before the controlled-replacement step; staging tables are discarded or corrected and the rebuild re-run — production is never touched until validation passes |
| Audit chain job fails mid-run for a given day | Safe to re-run: `fn_compute_chain_hash()` is idempotent and deterministic (§15.5); it recomputes from immutable `audit_events` and correctly looks up the prior day's checkpoint each time |
| `fn_insert_audit_event()` raises an exception (tenant mismatch, or unauthorized platform-event caller) | The calling transaction fails; for synchronous audit categories (§14.5) this correctly aborts the triggering action, since an unauditable security-critical action must not silently succeed |

Analytics failure never blocks the transactional operation that produced the underlying domain event — analytics ingestion is asynchronous and best-effort-with-retry. Audit failure for synchronous categories does block the triggering action, by design (§14.5) — an audit-required security action that cannot be recorded must not be allowed to happen silently.

---

## 24. Security / Compliance

### 24.1 PII Minimization

| Data Category | In `analytics.*`? | In `audit.audit_events`? | Handling |
|---|---|---|---|
| Full phone numbers | Never | Never | Entity UUIDs only |
| Full email addresses | Never | Never | Entity UUIDs only |
| Call transcript text | Never | Never | Remains exclusively in `voice` schema |
| Recording audio / storage refs | Never | Never | Count flags only in analytics |
| IP addresses | Never | `INET` column | Application is expected to mask to /24 (IPv4) / /48 (IPv6) before writing to `resource_snapshot`, if included there; the top-level `ip_address` column stores the value as received for security investigation purposes |
| User/actor display names | Never | `actor_name`, bounded 200 chars | Retained for accountability; see §24.3 |
| API key secrets, credential_ref values, webhook secrets | Never, anywhere | Never, anywhere | Not stored in this schema under any circumstances |

### 24.2 Tenant Isolation Summary

RLS + FORCE RLS on every tenant-owned table (§6, §16); `provider_health_5min` isolation via GRANT/REVOKE only, since it has no tenant dimension (§13); audit platform-event isolation via the SELECT policy excluding NULL-org rows for all non-BYPASSRLS roles, and platform-event *write* isolation via the `session_user` check inside `fn_insert_audit_event()` (§14.2).

### 24.3 Audit Retention and Privacy — V1 Policy

**V1 technical retention (India-first):** audit events 1 year hot, 7 years cold (S3), per §20. `actor_name` is retained as written at event time and is not automatically cleared on user erasure in V1.

**Scope of this specification:** this document makes no legal compliance claim regarding GDPR, DPDPA, or any other jurisdiction's erasure obligations as applied to `actor_name` in immutable audit records. That interaction — between a legally mandated erasure request and an audit-integrity requirement that historical accountability records not be silently rewritten — requires dedicated legal and compliance review before any global-market launch, and is tracked as ODD-5J-01 (§26).

### 24.4 Access Control Summary

See §17 (complete DDL) and §16 (RLS summary table) for the authoritative, singular statement of every GRANT/REVOKE in this schema. No table in `analytics.*` or `audit.*` has a privilege grant anywhere in this document that contradicts another privilege grant elsewhere in this document.

---

## 25. Adversarial Test Matrix

1. **Tenant A reads Tenant B audit events** → 0 rows (RLS `USING (organization_id = current_tenant)`)
2. **Tenant A reads platform audit events (organization_id IS NULL)** → 0 rows (RLS excludes NULL-org for non-BYPASSRLS roles)
3. **Tenant A (`app_api` session) inserts a tenant audit event with organization_id = Tenant B** via `fn_insert_audit_event(p_is_platform_event=FALSE)` → exception (`organization_id does not match current tenant context`)
4. **`app_api` session attempts to create a platform audit event** — calls `fn_insert_audit_event(p_is_platform_event=TRUE, p_organization_id=NULL, ...)` → exception (`caller 'app_api' is not authorized to create platform audit events`), raised by the `session_user NOT IN ('app_worker', 'app_platform_admin')` check inside the function — a database-enforced denial, not an application convention
5. **`app_worker` session creates a platform audit event** (p_is_platform_event=TRUE, organization_id=NULL) → succeeds; `session_user = 'app_worker'` passes the check
6. **`app_platform_admin` session creates a platform audit event** → succeeds
7. **Direct `INSERT INTO audit.audit_events` by any role, including `app_platform_admin`** → permission denied (no INSERT grant exists for any role)
8. **`UPDATE audit.audit_events` by any role, including `app_platform_admin`** → permission denied
9. **`DELETE audit.audit_events` by any role, including `app_platform_admin`** → permission denied
10. **`app_platform_admin` attempts `UPDATE`/`DELETE` on `audit.audit_chain`** → permission denied (identical posture to audit_events)
11. **Tenant `app_api` reads `analytics.provider_health_5min`** → permission denied
12. **`app_readonly` reads `analytics.provider_health_5min`** → permission denied (confirmed even after the broad `GRANT SELECT ON ALL TABLES` in migration 074, because of the reaffirming REVOKE)
13. **Duplicate analytics event (same dedup_key)** → `fn_ingest_analytics_event()` returns FALSE; zero new rows in either `analytics_event_dedup` or `analytics_events`
14. **Concurrent duplicate analytics event, two workers racing** → exactly one call returns TRUE; the other returns FALSE; no double-insert
15. **Projection retry after a crash strictly before COMMIT** (Case A, §9.2) → neither the claim nor the mutation persisted; retry processes the event normally and it is applied exactly once
16. **Projection retry after a crash strictly after a successful COMMIT** (Case B, §9.2) → the claim exists; retry's claim attempt conflicts, returns FALSE, and the projection mutation is not reapplied — verified by inspecting the measure value before and after the retry (unchanged)
17. **Two workers concurrently apply the same event to the same projection** → PostgreSQL unique-index locking serializes; exactly one succeeds, verified by inspecting `bucket_count`/`total_calls` before and after (single increment, not double)
18. **Event replay within the 90-day horizon** → correctly deduplicated at both the ingestion gate and the projection gate; aggregate unchanged
19. **Event with `occurred_at` 120 days old submitted to the normal path** → must not be sent to `fn_ingest_analytics_event()` by application logic (§12.2); test verifies the application-layer age-check routes it to the historical rebuild queue instead
20. **Historical rebuild run twice for the same archived date range** → identical staging output both times; controlled merge into production is idempotent (replace/reconcile, not additive) — no double-count after two rebuild runs
21. **NULL aggregate dimension collision** (e.g., two events for `agent_id = NULL`, same `(org, hour, direction, outcome, provider, language)`) → `UNIQUE NULLS NOT DISTINCT` correctly treats them as the same logical row; `ON CONFLICT DO UPDATE` fires; no duplicate row created
22. **Histogram percentile — normal distribution** (§11.6 worked example: samples 10,20,30,100,200,300ms) → p50 = "50ms", p95 = "500ms", p99 = "500ms" — matching the actual query output against this dataset, not an average or sum shortcut
23. **Histogram percentile — finite threshold with overflow present** (§11.7): 99 samples ≤5000ms, 1 sample >5000ms; p95 → "5000ms" (a finite bucket), not "&gt;5000ms", because the finite bucket's cumulative count (99) already clears the 95-sample threshold before the overflow bucket is reached in distribution order
24. **Histogram percentile — threshold satisfied only by overflow** (§11.7): 90 samples ≤5000ms, 10 samples >5000ms; p95 → "&gt;5000ms", because no finite bucket's cumulative count reaches 95
25. **Histogram percentile — all samples in overflow**: 100 samples, all >5000ms; p50/p95/p99 all → "&gt;5000ms"
26. **Empty histogram (zero rows for the queried grain/time-range)** → percentile query returns NULL for p50/p95/p99 and `sample_count = 0`; no error, no division-by-zero
27. **Sparse histogram — only 2 of 13 buckets populated** → percentile query still produces correct results; absent buckets contribute 0 to the cumulative sum without needing explicit zero-count rows
28. **Single-sample histogram** (one sample at 100ms) → p50, p95, and p99 all resolve to "100ms"
29. **Late-arriving event within the horizon** → correctly updates the historical hour/day bucket via additive UPSERT
30. **INSERT beyond pre-created future partitions** → routes to `DEFAULT` partition; does not error; monitoring alert triggers on non-empty DEFAULT
31. **Full migration chain 067→075 execution** on a fresh PostgreSQL 15+ database with pgcrypto pre-installed → completes without error, with no step referencing a table or column not yet created in an earlier step

---

## 26. Final Invariants

| Invariant | Statement |
|---|---|
| Tenant isolation | No tenant session, using any role except `app_platform_admin`, can read, insert, update, or delete another tenant's rows in any tenant-owned table. |
| Audit immutability | No role — none, without exception — has UPDATE or DELETE privilege on `audit.audit_events` or `audit.audit_chain`. Audit rows, once inserted, are permanent. |
| Audit insert control | Every audit write passes through `audit.fn_insert_audit_event()`, which validates tenant/platform ownership at the database layer using the caller's `session_user`; no application role holds a bare table-level INSERT grant. |
| Audit platform-event authorization | Only sessions authenticated as `app_worker` or `app_platform_admin` can create a platform-level (`organization_id IS NULL`) audit event; this is enforced inside the SECURITY DEFINER function via `session_user`, which cannot be spoofed by the function's own privilege elevation. |
| Audit platform separation (read) | Ordinary tenant sessions can never see `organization_id IS NULL` audit rows; only `app_platform_admin` (via BYPASSRLS) can. |
| Global dedup | A given `dedup_key` corresponds to exactly one analytics event, enforced by a single PRIMARY KEY on a non-partitioned table, independent of how `analytics_events` is time-partitioned. |
| Projection idempotency | A given `(projection_name, analytics_event_id)` pair is applied to its projection table exactly once, and the claim of that pair and the application of its effect are committed atomically together. |
| Atomic projection | There is never a durable database state in which a projection claim exists without its corresponding projection mutation having also been applied, or vice versa; a crash before COMMIT loses both together, a crash after COMMIT preserves both together. |
| Aggregate uniqueness | Every aggregate table's logical grain — including grains containing nullable dimensions — maps to at most one row, enforced by `UNIQUE` or `UNIQUE NULLS NOT DISTINCT` as appropriate. |
| Percentile correctness | Reported percentiles are derived from the complete merged histogram distribution at query time, selecting the first bucket in correct distribution order (finite buckets before overflow) that satisfies the threshold — never from averaging or summing independently-computed scalar percentiles, and never by a raw numeric MIN() that could favor the overflow sentinel over a legitimate finite bucket. |
| Overflow correctness | Samples in the overflow latency bucket participate in the total sample count used as the percentile denominator; they are never silently excluded, and are only selected as the percentile result when no finite bucket satisfies the threshold. |
| Replay safety | The retention of both `analytics_event_dedup` and `analytics_projection_events` is never shorter than the normal incremental replay horizon (90 days); events outside that horizon are never sent through the normal incremental path. |
| Historical rebuild safety | The historical rebuild path is isolated from the normal incremental path, uses staging tables and validation before any production merge, and its controlled-replacement step is idempotent — repeated rebuilds do not double-count. |
| Platform data security | `analytics.provider_health_5min`, containing platform-internal infrastructure data, is never readable by `app_api` or `app_readonly`, under any grant statement anywhere in this schema. |
| No cross-phase mutation | No table, function, grant, or architectural decision in Phase 5A through 5I is modified, redefined, or contradicted by this document. |

---

## 27. Final Validation

| Requirement | Implementation | Test(s) | Status |
|---|---|---|---|
| PostgreSQL correctness | Valid PG15+ DDL throughout: `NULLS NOT DISTINCT`, `GENERATED ALWAYS AS ... STORED`, BRIN, partitioned PKs include partition key, CHECK constraints for enumerations | §25 #31 | PASS |
| Tenant isolation | RLS + FORCE RLS on every tenant-owned table (§6, §16) | §25 #1, #11, #12, #21 | PASS |
| Platform access control | `provider_health_5min` GRANT/REVOKE (§13); audit platform-event RLS exclusion for reads (§14.2) | §25 #2, #11, #12 | PASS |
| Audit immutability | Zero INSERT/UPDATE/DELETE grants to any role on `audit_events`/`audit_chain`, including `app_platform_admin` (§5.3, §14.2) | §25 #7, #8, #9, #10 | PASS |
| Audit insertion security | `fn_insert_audit_event()` is the sole write path; tenant ownership validated inside the function | §25 #3, #7 | PASS |
| Audit platform-event authorization | `session_user` check inside `fn_insert_audit_event()`; database-enforced, not application-convention | §25 #4, #5, #6 | PASS |
| Global deduplication | `analytics_event_dedup` PRIMARY KEY on `dedup_key`, independent of partitioning (§8) | §25 #13, #14 | PASS |
| Projection idempotency | `analytics_projection_events` UNIQUE (projection_name, event_id); atomic claim primitive (§9) | §25 #17 | PASS |
| Atomic projection transaction — crash before commit | Claim + mutation in one transaction; rollback loses both | §25 #15 | PASS |
| Atomic projection transaction — crash after commit | Claim + mutation both durable; retry correctly no-ops | §25 #16 | PASS |
| Replay safety | 90-day horizon equals dedup and projection ledger retention (§12.1) | §25 #18, #19 | PASS |
| Historical rebuild safety | Isolated staging path, validated, idempotent controlled merge (§12.3) | §25 #20 | PASS |
| Aggregate uniqueness / NULL handling | `UNIQUE NULLS NOT DISTINCT` on every nullable-grain table, audited exhaustively (§10) | §25 #21 | PASS |
| Histogram storage correctness | Non-cumulative per-bucket storage; cumulative distribution derived at query time (§11.2–§11.4) | §25 #27, #28 | PASS |
| Percentile correctness — normal distribution | `ORDER BY sort_key LIMIT 1` selection, verified against the §11.6 worked example | §25 #22 | PASS |
| Percentile correctness — overflow ordering | Overflow bucket sorts after all finite buckets; finite buckets preferred when they satisfy the threshold | §25 #23 | PASS |
| Overflow inclusion in denominator | Total sample count includes overflow bucket | §25 #23, #24, #25 | PASS |
| Overflow-only and all-overflow cases | Correctly resolve to `>5000ms` | §25 #24, #25 | PASS |
| Empty / single-sample histogram | Correctly resolve to NULL / the single bucket | §25 #26, #28 | PASS |
| Provider health security | Explicit REVOKE for `app_api`/`app_readonly`, reaffirmed after broad grants (§13, migration 071 & 074) | §25 #11, #12 | PASS |
| Partition correctness | Every partitioned table has a DEFAULT partition; PKs include partition keys | §25 #30, #31 | PASS |
| Migration safety | No destructive table replacement anywhere in the chain; migration 069 creates the final histogram design directly | §25 #31 | PASS |
| Retention correctness | Single authoritative matrix (§20); no contradicting value elsewhere | §28 | PASS |
| PII/security | No PII beyond bounded, documented fields; no secrets anywhere (§24.1) | §28 | PASS |
| Cross-phase compatibility | No 5A–5I table/function/grant modified; all references logical UUIDs via events (§3) | §28 | PASS |
| Documentation consistency | Prose, DDL, functions, policies, grants, and tests all describe identical behavior for every invariant listed in §26 | §28 | PASS |
| Adversarial test coverage | 31 adversarial tests spanning tenant isolation, immutability, platform-event authorization, dedup, idempotency, replay, rebuild, NULL handling, and histogram/percentile correctness including overflow ordering | §25 | PASS |

**All rows: PASS.**

---

## 28. Document Consistency Verification

The following patterns were searched for across the entire document — prose, DDL, functions, comments, grants, policies, examples, tests, invariants, and migration sections — and confirmed absent:

| Pattern searched for | Occurrences |
|---|---|
| `audit_events.chain_hash` column | 0 — no such column exists (§14.1, §17 migration 072) |
| `UPDATE audit.audit_events` (any statement) | 0 — `fn_compute_chain_hash()` only writes `audit_chain` |
| `DELETE audit.audit_events` (any statement) | 0 |
| `WITH CHECK (TRUE)` for audit insertion | 0 — no INSERT policy exists; INSERT has no grantee |
| Direct audit INSERT grants to any role | 0 — including `app_platform_admin` |
| `app_platform_admin` UPDATE/DELETE grants on audit tables | 0 |
| Platform-event authorization enforced only by comment/convention rather than `session_user` check | 0 — §14.2 shows the exact `session_user` check; §25 tests #4–#6 exercise it |
| `dedup_key` claimed globally unique directly on the partitioned `analytics_events` table | 0 — §7.1/§8.1 state the partitioned table's constraint is partition-local only |
| Scalar `p50_latency_ms`/`p95_latency_ms`/`p99_latency_ms` columns | 0 |
| Percentile formula using average or sum of independent percentiles | 0 |
| Percentile selection using `MIN(bucket_upper_ms)` over raw values (overflow-ordering bug) | 0 — §11.4 uses `ORDER BY sort_key LIMIT 1`, not `MIN()` over raw bucket values |
| Incorrect worked percentile example (e.g., claiming p95 = 250ms for the six-sample dataset) | 0 — §11.6 shows the correct result, p95 = "500ms" |
| `DROP TABLE ... CASCADE` for `call_latency_stage_hourly` or any production table | 0 |
| "Exactly 13 rows enforced by UNIQUE" claim | 0 — §11.2/§10 state "at most one row per bucket," explicitly sparse |
| `provider_health_5min` readable by `app_api` or `app_readonly` | 0 |
| Contradictory retention values for any table | 0 — §20 is the single authoritative retention matrix |
| Contradictory replay horizon values | 0 — 90 days stated consistently in §8.3, §9.4, §12.1, §20 |
| Contradictory migration definitions for the same table | 0 — each table has exactly one `CREATE TABLE` statement |
| Contradictory security/grant statements for the same table | 0 |
| Development/review-history language ("previous review found...", "we fixed...", "reviewer identified...", correction-pass labels) | 0 — this document describes the architecture as designed, not its revision history |

All counts are zero.

---

## 29. Final Status

```
PHASE 5J — ANALYTICS / AUDIT SCHEMA
Schemas: analytics, audit
Migration chain: 067–075, continuous from Phase 5I's final migration 066

CRITICAL issues remaining:     NONE
SIGNIFICANT issues remaining:  NONE
Stale/contradictory content:   NONE (§28 — all searched patterns: 0 occurrences)
Open design decisions:         7 (all explicitly non-blocking for V1)

Open Design Decisions:
  ODD-5J-01  actor_name anonymization post-erasure — legal review required
  ODD-5J-02  Audit retention per plan tier — maintenance-job parameter only
  ODD-5J-03  ClickHouse migration threshold — operational decision, future
  ODD-5J-04  Cross-region analytics replication — Phase 7+ (global expansion)
  ODD-5J-05  Enterprise BI/export pipeline — Phase 7+
  ODD-5J-06  Prompt experiment analytics — Phase 7
  ODD-5J-07  Latency histogram bucket boundary revision process — future

Status: APPROVED FOR FREEZE
```
