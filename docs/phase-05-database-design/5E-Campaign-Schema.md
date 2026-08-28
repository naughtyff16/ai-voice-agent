# Phase 5E — Campaign Schema
## Physical PostgreSQL Database Design

| | |
|---|---|
| **Phase** | 5E — Campaign Schema Physical Database Design |
| **Schema** | `campaign` |
| **Status** | Draft v1.0 — for approval before Phase 5F |
| **Authority** | Phase 5A (standards) + Phase 5B (constructs) + Phase 4D (DDD) + Phase 4I (eligibility pipeline) |
| **Follows** | Phase 5D (APPROVED, PHASE 5E READY) |
| **Precedes** | Phase 5F — Knowledge/RAG Schema |

---

## 1. Executive Summary

This document delivers the complete physical database design for the `campaign` schema — the outbound campaign execution layer. The design is derived from the Phase 4D Campaign & Outbound Calling DDD (authoritative), with the Phase 4I mandatory eligibility pipeline applied.

**Critical architectural commitment:** Campaign is a *consumer* of CRM, not a source of truth for contacts, consent, or suppression. Every eligibility decision reads from `crm.contact_suppressions` and `crm.consent_records` (or their Redis-cached derivatives). Campaign never duplicates these authoritative CRM records.

**Key design decisions:**

| Decision | Outcome |
|---|---|
| DDD aggregates mapped | Campaign, CampaignContact, ContactList, CsvImportJob, CallJob, CampaignOutcome — 6 aggregates, 6 tables |
| Phase 4I eligibility pipeline | `INELIGIBLE` is a terminal status on `campaign_contacts`; `DEFERRED` records `next_attempt_at` |
| Audience model | CampaignContacts are materialized at campaign start (PREPARING phase); phone is cached for queue use; no CRM PII duplicated beyond what DDD requires |
| `campaign_contacts` partitioning | RANGE monthly on `imported_at` — high-volume, unbounded growth |
| `call_jobs` | Not partitioned in V1 — transient records, cleaned after campaign completion |
| Monetary columns on `campaign_outcomes` | `NUMERIC(18,4)` + `CHAR(3)` pair — Phase 5A §10 |
| Campaign channel | VOICE only in V1 — multi-channel is a future extension (OQ-4D-03) |
| JSONB usage | `scheduling_policy`, `retry_policy`, `concurrency_policy`, `rate_limit_policy` — bounded, always-read-whole policy value objects on campaigns |
| Eligibility caching | Redis-only (suppression and consent cache); PostgreSQL is authoritative, Redis is cache |
| Redis queues | Call Queue and Retry Queue — not in PostgreSQL; reconstructable from `campaign_contacts` |

---

## 2. Scope

**In scope:** `campaign` schema — 6 tables, indexes, constraints, RLS, triggers, grants, seed data.

**Out of scope:** `crm`, `voice`, `billing`, `analytics`, `knowledge`, `workflow`, `identity`, `organization`.

---

## 3. Aggregate → Table Mapping

| Phase 4D Aggregate | Table | Notes |
|---|---|---|
| `Campaign` (AggregateRoot) | `campaign.campaigns` | Campaign configuration and lifecycle |
| `CampaignContact` (AggregateRoot) | `campaign.campaign_contacts` | One row per contact per campaign; partitioned |
| `ContactList` (AggregateRoot) | `campaign.contact_lists` | Reusable named contact collections |
| `CsvImportJob` (AggregateRoot) | `campaign.csv_import_jobs` | Background CSV processing state |
| `CallJob` (AggregateRoot) | `campaign.call_jobs` | Transactional unit of call dispatch; idempotency key |
| `CampaignOutcome` (AggregateRoot) | `campaign.campaign_outcomes` | Post-completion aggregated result; one per campaign |

**Table count:** 6 tables, 1 partitioned (`campaign_contacts`).

**No campaign-specific `campaign_runs` table:** Phase 4D does not define a `CampaignRun` aggregate. The DDD defines execution as a tick-based loop on a single campaign. Campaign progress is tracked via `campaign_contacts` status counts (see §3.1 rationale).

### 3.1 Why No `campaign_runs` Table

Phase 4D §14.2 defines `CampaignApplicationService.handle_campaign_completion_check()` which checks terminal status of `CampaignContacts` directly — there is no `CampaignRun` entity in the DDD. The campaign's `started_at`, `completed_at`, and `cancelled_at` timestamps on the `campaigns` table serve the role of a run record for single-run campaigns. For recurring campaigns (Phase 4D OQ-4D-03), a `campaign_runs` table would be warranted, but recurring semantics are an open question. This is documented as a carry-forward item.

---

## 4. Phase 4I Eligibility Integration

Phase 4I §6.1 mandates a multi-gate eligibility pipeline **before any dial**. This affects `campaign_contacts.status` and `call_jobs`:

**New terminal status: `INELIGIBLE`** (Phase 4I §6.2)
Phase 4D §7.2 defines `DNC_SKIPPED` as the terminal status for DNC contacts. Phase 4I extends this: any contact permanently blocked (consent withdrawn, suppressed, invalid number) becomes `INELIGIBLE` with an `ineligibility_reason` field. `DNC_SKIPPED` is subsumed into `INELIGIBLE` with reason `SUPPRESSED_ORG`.

**Three-way eligibility decision (Phase 4I §6.2):**

| Decision | CampaignContact effect |
|---|---|
| `ELIGIBLE` | Proceed to CallJob creation |
| `DEFERRED(retry_at, reason)` | `status = RETRY_SCHEDULED`, `next_attempt_at = retry_at` |
| `INELIGIBLE(reason, permanent)` | `status = INELIGIBLE`, `ineligibility_reason = reason` |

**Eligibility is checked twice (Phase 4I §6.3):**
1. **At enqueue** (CSV import / audience build) — full pipeline; INELIGIBLE contacts never enter the Redis Call Queue.
2. **At dispatch** — fast re-check of mutable gates (suppression, consent, calling window, quota) via Redis before `CallJob` creation. Re-check reads Redis cache first; PostgreSQL on cache miss.

---

## 5. Column-Level Data Dictionary

### 5.1 `campaign.campaigns`

**Aggregate:** `Campaign` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `name` | TEXT | NOT NULL | — | 1–200 chars |
| `description` | TEXT | NULL | — | 0–1000 chars |
| `status` | TEXT | NOT NULL | `'DRAFT'` | Phase 4D §7.1 lifecycle values |
| `agent_id` | UUID | NOT NULL | — | Logical ref: `voice.agents.id`. Must be PUBLISHED. |
| `agent_version_id` | UUID | NULL | — | Logical ref: `voice.agent_versions.id`. Set when PREPARING. Immutable after. |
| `phone_number_id` | UUID | NOT NULL | — | Logical ref: `voice.tenant_phone_numbers.id`. From-number. |
| `contact_list_id` | UUID | NULL | — | Logical ref: `campaign.contact_lists.id`. Set when list attached. |
| `scheduling_policy` | JSONB | NOT NULL | `'{}'` | `SchedulingPolicy` value object (see §7.1) |
| `concurrency_policy` | JSONB | NOT NULL | `'{}'` | `{max_concurrent_calls: int}` |
| `rate_limit_policy` | JSONB | NOT NULL | `'{}'` | `{max_per_minute: int, window_seconds: int}` |
| `retry_policy` | JSONB | NOT NULL | `'{}'` | `RetryPolicy` value object (see §7.2) |
| `qualification_criteria` | JSONB | NULL | — | Forwarded to Agent; nullable — Agent's own criteria used if null |
| `total_contacts` | INTEGER | NULL | — | Set once when contact list finalized |
| `started_at` | TIMESTAMPTZ | NULL | — | When campaign transitioned to RUNNING |
| `completed_at` | TIMESTAMPTZ | NULL | — | Set once when COMPLETED |
| `cancelled_at` | TIMESTAMPTZ | NULL | — | Set once when CANCELLED |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Campaign status values** (Phase 4D §7.1):
`DRAFT | SCHEDULED | PREPARING | RUNNING | PAUSED | STOPPING | COMPLETED | CANCELLED | FAILED`

**JSONB policy columns are bounded and always read with the Campaign:**

`scheduling_policy` structure:
```json
{
  "start_at": "<iso8601>",
  "end_at": "<iso8601|null>",
  "timezone": "Asia/Kolkata",
  "calling_windows": [
    {"days": ["MON","TUE","WED","THU","FRI"], "start_time": "09:00", "end_time": "20:00"}
  ],
  "holiday_calendar": "IN",
  "is_recurring": false
}
```

`retry_policy` structure:
```json
{
  "max_attempts": 3,
  "backoff_schedule": ["PT30M", "PT2H"],
  "retry_on_outcomes": ["NO_ANSWER", "BUSY"],
  "retry_window_restricted": true
}
```

### 5.2 `campaign.contact_lists`

**Aggregate:** `ContactList` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `name` | TEXT | NOT NULL | — | 1–200 chars |
| `source` | TEXT | NOT NULL | — | `CSV_IMPORT \| CRM_FILTER \| MANUAL` |
| `status` | TEXT | NOT NULL | `'PENDING'` | `PENDING \| BUILDING \| READY \| FAILED` |
| `contact_count` | INTEGER | NULL | — | Set once when READY |
| `csv_import_job_id` | UUID | NULL | — | Logical ref: `campaign.csv_import_jobs.id`. For CSV_IMPORT source. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.3 `campaign.csv_import_jobs`

**Aggregate:** `CsvImportJob` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `contact_list_id` | UUID | NOT NULL | — | Logical ref: `campaign.contact_lists.id` |
| `campaign_id` | UUID | NULL | — | Logical ref: `campaign.campaigns.id`. Nullable — list may be campaign-independent. |
| `status` | TEXT | NOT NULL | `'PENDING'` | `PENDING \| PROCESSING \| COMPLETED \| FAILED` |
| `storage_ref` | TEXT | NOT NULL | — | S3 path of uploaded CSV. `CHECK (storage_ref LIKE 'org/%')` |
| `total_rows` | INTEGER | NULL | — | Set after header parse |
| `processed_rows` | INTEGER | NOT NULL | `0` | Checkpointed per batch |
| `skipped_rows` | INTEGER | NOT NULL | `0` | Invalid / duplicate rows |
| `dnc_skipped_rows` | INTEGER | NOT NULL | `0` | Rows with DNC flag at import time |
| `errors` | JSONB | NOT NULL | `'[]'` | Capped at 100 `ImportRowError` entries: `[{row_number, reason}]` |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.4 `campaign.campaign_contacts` (Partitioned — RANGE monthly on `imported_at`)

**Aggregate:** `CampaignContact` (AggregateRoot — high-volume)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK `(id, imported_at)` |
| `imported_at` | TIMESTAMPTZ | NOT NULL | — | **Partition key.** When this contact was added to the campaign. |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `campaign_id` | UUID | NOT NULL | — | Logical ref: `campaign.campaigns.id` |
| `contact_id` | UUID | NOT NULL | — | Logical ref: `crm.contacts.id`. Resolved via `FindOrCreateContact`. |
| `phone_e164` | TEXT | NOT NULL | — | Cached from CRM at import time — used for queue operations. **pii:phone** |
| `status` | TEXT | NOT NULL | `'PENDING'` | Phase 4D §7.2 + Phase 4I INELIGIBLE values |
| `attempt_count` | INTEGER | NOT NULL | `0` | 0 to max_attempts |
| `max_attempts` | INTEGER | NOT NULL | — | Copied from `campaigns.retry_policy.max_attempts` at enqueue |
| `last_attempt_at` | TIMESTAMPTZ | NULL | — | |
| `next_attempt_at` | TIMESTAMPTZ | NULL | — | Set when RETRY_SCHEDULED or DEFERRED |
| `outcome` | TEXT | NULL | — | `ANSWERED_COMPLETED \| ANSWERED_TRANSFERRED \| NO_ANSWER \| VOICEMAIL \| FAILED \| CANCELLED` |
| `qualification_result` | TEXT | NULL | — | `QUALIFIED \| DISQUALIFIED \| INCONCLUSIVE` |
| `qualification_reason` | TEXT | NULL | — | Why qualified/disqualified |
| `lead_score_at_call` | INTEGER | NULL | — | Snapshot of `crm.contacts.lead_score` at call initiation time |
| `is_dnc` | BOOLEAN | NOT NULL | `FALSE` | Cached from CRM at import time (denormalized) |
| `ineligibility_reason` | TEXT | NULL | — | Phase 4I EligibilityReason value when `status = INELIGIBLE` |
| `call_session_refs` | UUID[] | NOT NULL | `'{}'` | Logical refs: `voice.call_sessions.id`. Max 5. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`status` values** (Phase 4D §7.2 + Phase 4I §6.2):
`PENDING | CALLING | ANSWERED | NO_ANSWER | BUSY | VOICEMAIL | FAILED | RETRY_SCHEDULED | COMPLETED | QUALIFIED | DISQUALIFIED | EXHAUSTED | DNC_SKIPPED | INELIGIBLE`

**`DNC_SKIPPED` preserved for backward compatibility** — it is the original Phase 4D status for contacts suppressed at import time (DNC at import). `INELIGIBLE` is the broader Phase 4I status for any permanent ineligibility discovered at dispatch time.

**Why `phone_e164` is cached on `campaign_contacts`:**
Phase 4D §4.2 explicitly lists `Phone (Value Object — E164PhoneNumber — cached for queue use)` on `CampaignContact`. The Redis Call Queue holds `CampaignContactId` values; when the executor pops an ID from the queue, it needs the phone number for dispatch without a CRM round-trip. This is an intentional DDD-authorized denormalization — not a PII duplication concern, since the campaign already has the relationship to the contact.

### 5.5 `campaign.call_jobs`

**Aggregate:** `CallJob` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `campaign_id` | UUID | NOT NULL | — | Logical ref: `campaign.campaigns.id` |
| `campaign_contact_id` | UUID | NOT NULL | — | Logical ref: `campaign.campaign_contacts.id` |
| `phone_e164` | TEXT | NOT NULL | — | Cached for dispatch. **pii:phone** |
| `attempt_number` | INTEGER | NOT NULL | — | 1-indexed |
| `idempotency_key` | CHAR(64) | NOT NULL | — | SHA-256 of `(campaign_id + campaign_contact_id + attempt_number)` |
| `status` | TEXT | NOT NULL | `'PENDING'` | `PENDING \| DISPATCHED \| SUCCEEDED \| FAILED \| SUPERSEDED` |
| `call_session_id` | UUID | NULL | — | Logical ref: `voice.call_sessions.id`. Set after Voice accepts. |
| `dispatched_at` | TIMESTAMPTZ | NULL | — | |
| `completed_at` | TIMESTAMPTZ | NULL | — | |
| `failure_reason` | TEXT | NULL | — | Set when FAILED |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.6 `campaign.campaign_outcomes`

**Aggregate:** `CampaignOutcome` (AggregateRoot — one per campaign, computed post-completion)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `campaign_id` | UUID | NOT NULL | — | Logical ref: `campaign.campaigns.id` |
| `computed_at` | TIMESTAMPTZ | NOT NULL | — | |
| `total_contacts` | INTEGER | NOT NULL | `0` | |
| `attempted` | INTEGER | NOT NULL | `0` | |
| `answered` | INTEGER | NOT NULL | `0` | |
| `no_answer` | INTEGER | NOT NULL | `0` | |
| `busy` | INTEGER | NOT NULL | `0` | |
| `failed` | INTEGER | NOT NULL | `0` | |
| `voicemail` | INTEGER | NOT NULL | `0` | |
| `dnc_skipped` | INTEGER | NOT NULL | `0` | |
| `ineligible` | INTEGER | NOT NULL | `0` | Phase 4I terminal INELIGIBLE count |
| `exhausted` | INTEGER | NOT NULL | `0` | |
| `qualified` | INTEGER | NOT NULL | `0` | |
| `disqualified` | INTEGER | NOT NULL | `0` | |
| `inconclusive` | INTEGER | NOT NULL | `0` | |
| `answer_rate_pct` | NUMERIC(5,2) | NOT NULL | `0.00` | 0.00–100.00 |
| `qualification_rate_pct` | NUMERIC(5,2) | NOT NULL | `0.00` | 0.00–100.00 |
| `total_call_minutes` | NUMERIC(12,2) | NOT NULL | `0.00` | |
| `total_cost_amount` | NUMERIC(18,4) | NULL | — | Phase 5A money convention |
| `total_cost_currency` | CHAR(3) | NULL | — | ISO 4217 |
| `estimated_revenue_amount` | NUMERIC(18,4) | NULL | — | |
| `estimated_revenue_currency` | CHAR(3) | NULL | — | |
| `roi_pct` | NUMERIC(8,2) | NULL | — | `(revenue - cost) / cost × 100`. Null if no revenue configured. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

---

## 6. Primary Keys

| Table | Primary Key | Notes |
|---|---|---|
| `campaign.campaigns` | `id` | Standard |
| `campaign.contact_lists` | `id` | Standard |
| `campaign.csv_import_jobs` | `id` | Standard |
| `campaign.campaign_contacts` | `(id, imported_at)` | Composite — partition key required |
| `campaign.call_jobs` | `id` | Standard |
| `campaign.campaign_outcomes` | `id` | Standard |

---

## 7. Unique Constraints

| Table | Columns | Condition | Rationale |
|---|---|---|---|
| `campaign.call_jobs` | `idempotency_key` | `WHERE status IN ('PENDING','DISPATCHED')` | Phase 4D §4.5 inv.1: at most one active job per (campaign, contact, attempt) triple |
| `campaign.campaign_outcomes` | `campaign_id` | — | One outcome per campaign |
| `campaign.campaign_contacts` | `(campaign_id, contact_id)` | Included in PK partition — see note | One contact per campaign — see §6.1 |

**§6.1 `(campaign_id, contact_id)` uniqueness on partitioned table:**
PostgreSQL requires the partition key in any UNIQUE constraint on a partitioned table. `(campaign_id, contact_id, imported_at)` cannot be made UNIQUE because `imported_at` varies by row. Uniqueness of `(campaign_id, contact_id)` is enforced at the **application layer** (the `EnqueueContact` use case checks for an existing record before INSERT). This is documented as an application invariant, not a DB constraint.

---

## 8. Check Constraints

```sql
-- campaigns
CHECK (status IN ('DRAFT','SCHEDULED','PREPARING','RUNNING','PAUSED',
                  'STOPPING','COMPLETED','CANCELLED','FAILED'))
CHECK (length(name) BETWEEN 1 AND 200)
CHECK (total_contacts IS NULL OR total_contacts >= 0)
CHECK ((total_cost_amount IS NULL) = (total_cost_currency IS NULL))  -- for outcomes

-- contact_lists
CHECK (source IN ('CSV_IMPORT','CRM_FILTER','MANUAL'))
CHECK (status IN ('PENDING','BUILDING','READY','FAILED'))
CHECK (contact_count IS NULL OR contact_count >= 0)

-- csv_import_jobs
CHECK (status IN ('PENDING','PROCESSING','COMPLETED','FAILED'))
CHECK (processed_rows >= 0 AND skipped_rows >= 0 AND dnc_skipped_rows >= 0)
CHECK (storage_ref LIKE 'org/%')

-- campaign_contacts
CHECK (status IN ('PENDING','CALLING','ANSWERED','NO_ANSWER','BUSY','VOICEMAIL',
                  'FAILED','RETRY_SCHEDULED','COMPLETED','QUALIFIED','DISQUALIFIED',
                  'EXHAUSTED','DNC_SKIPPED','INELIGIBLE'))
CHECK (attempt_count >= 0 AND attempt_count <= 5)
CHECK (max_attempts BETWEEN 1 AND 5)
CHECK (outcome IS NULL OR outcome IN ('ANSWERED_COMPLETED','ANSWERED_TRANSFERRED',
       'NO_ANSWER','VOICEMAIL','FAILED','CANCELLED'))
CHECK (qualification_result IS NULL OR qualification_result IN
       ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE'))
CHECK (lead_score_at_call IS NULL OR (lead_score_at_call >= 0 AND lead_score_at_call <= 100))
-- phone_e164: TEXT NOT NULL — NO database E.164 CHECK constraint.
--   E.164 format validated at INSERT by application layer only.
--   GDPR erasure may set value to [erased]. See ADR-5E-011.
CHECK (cardinality(call_session_refs) <= 5)

-- call_jobs
CHECK (status IN ('PENDING','DISPATCHED','SUCCEEDED','FAILED','SUPERSEDED'))
CHECK (attempt_number >= 1 AND attempt_number <= 5)
-- phone_e164: TEXT NOT NULL — NO database E.164 CHECK constraint.
--   E.164 format validated at INSERT by application layer only.
--   GDPR erasure may set value to [erased]. See ADR-5E-011.

-- campaign_outcomes
CHECK (answer_rate_pct BETWEEN 0 AND 100)
CHECK (qualification_rate_pct BETWEEN 0 AND 100)
CHECK (total_call_minutes >= 0)
CHECK (total_contacts >= 0 AND attempted >= 0)
CHECK ((total_cost_amount IS NULL) = (total_cost_currency IS NULL))
CHECK ((estimated_revenue_amount IS NULL) = (estimated_revenue_currency IS NULL))
```

---

## 9. Index Strategy

### 9.1 `campaign.campaigns`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_campaigns` | `id` | UNIQUE B-tree (PK) | — | PK lookup |
| `idx_camp_org_status` | `(organization_id, status)` | B-tree | — | List campaigns by status |
| `idx_camp_org_created` | `(organization_id, created_at DESC)` | B-tree | — | Recency view |
| `idx_camp_due_for_start` | `(organization_id, status, scheduling_policy->'start_at')` | — | `WHERE status = 'SCHEDULED'` | APScheduler polls for due campaigns |
| `idx_camp_org_running` | `organization_id` | B-tree | `WHERE status IN ('RUNNING','PAUSED','STOPPING')` | Active campaign dashboard |

**Note on `idx_camp_due_for_start`:** The `start_at` is nested in `scheduling_policy` JSONB. A functional index using `(scheduling_policy->>'start_at')::timestamptz` is created for APScheduler's poll query. See §14 DDL.

### 9.2 `campaign.contact_lists`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_contact_lists` | `id` | UNIQUE B-tree (PK) | |
| `idx_cl_org_status` | `(organization_id, status)` | B-tree | |
| `idx_cl_org_created` | `(organization_id, created_at DESC)` | B-tree | |

### 9.3 `campaign.csv_import_jobs`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_csv_import_jobs` | `id` | UNIQUE B-tree (PK) | |
| `idx_cij_contact_list` | `contact_list_id` | B-tree | |
| `idx_cij_campaign` | `campaign_id` | B-tree | `WHERE campaign_id IS NOT NULL` |
| `idx_cij_org_status` | `(organization_id, status)` | B-tree | |

### 9.4 `campaign.campaign_contacts` (Partitioned)

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_campaign_contacts` | `(id, imported_at)` | UNIQUE B-tree (PK) | — | PK lookup |
| `idx_cc_campaign_status` | `(organization_id, campaign_id, status)` | B-tree | — | Status counts per campaign; executor |
| `idx_cc_campaign_retry` | `(campaign_id, next_attempt_at)` | B-tree | `WHERE status = 'RETRY_SCHEDULED'` | Find due retries |
| `idx_cc_campaign_pending` | `(campaign_id, id)` | B-tree | `WHERE status = 'PENDING'` | PREPARING phase — batch enqueue |
| `idx_cc_contact_id` | `(organization_id, contact_id)` | B-tree | — | CRM contact's campaign history |
| `idx_cc_org_time_brin` | `(organization_id, imported_at)` | BRIN | — | Partition-level range scans |

### 9.5 `campaign.call_jobs`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_call_jobs` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_cj_idempotency_active` | `idempotency_key` | PARTIAL UNIQUE B-tree | `WHERE status IN ('PENDING','DISPATCHED')` | Duplicate dispatch prevention |
| `idx_cj_campaign_contact` | `(organization_id, campaign_contact_id)` | B-tree | — | All jobs for a contact |
| `idx_cj_call_session` | `call_session_id` | B-tree | `WHERE call_session_id IS NOT NULL` | `call.ended` → campaign lookup |
| `idx_cj_campaign_active` | `(campaign_id, status)` | B-tree | `WHERE status IN ('PENDING','DISPATCHED')` | Active job count for completion check |

### 9.6 `campaign.campaign_outcomes`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_campaign_outcomes` | `id` | UNIQUE B-tree (PK) | |
| `uq_co_campaign` | `campaign_id` | UNIQUE B-tree | One outcome per campaign |
| `idx_co_org` | `organization_id` | B-tree | |

---

## 10. Partitioning

### 10.1 `campaign.campaign_contacts` — RANGE monthly on `imported_at`

Campaign contacts are high-volume: a single large campaign may import millions of contacts, and a platform with thousands of organizations running monthly campaigns grows rapidly.

```sql
CREATE TABLE campaign.campaign_contacts (...)
PARTITION BY RANGE (imported_at);

-- Partitions created parametrically at migration time:
--   create_monthly_partitions(conn, 'campaign.campaign_contacts', months_ahead=3)
-- Creates current month + 3 months ahead + DEFAULT safety partition.
CREATE TABLE campaign.campaign_contacts_default
  PARTITION OF campaign.campaign_contacts DEFAULT;
```

**Retention:** campaign contacts are retained as long as the campaign is active and for the operational lookback window (12 months). After archival, partitions are dropped. Exact retention policy is set by `CompliancePolicy.RetentionProfile` — not hard-coded.

### 10.2 No Other Campaign Table Requires Day-One Partitioning

| Table | Reasoning |
|---|---|
| `campaigns` | Small — one row per campaign; max tens of thousands per org |
| `contact_lists` | One row per list — small |
| `csv_import_jobs` | One row per import — small |
| `call_jobs` | Transient — completed jobs may be archived post-campaign. V1: no partitioning. |
| `campaign_outcomes` | One row per campaign — small |

`call_jobs` will be re-evaluated for partitioning at Phase 22 (Deployment) based on actual volume data.

---

## 11. RLS Architecture

All campaign tables are tenant-scoped:

```sql
ALTER TABLE campaign.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.<table> FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_<table>_tenant ON campaign.<table>
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

Applied to: `campaigns`, `contact_lists`, `csv_import_jobs`, `campaign_contacts`, `call_jobs`, `campaign_outcomes`.

**Partitioned table note:** RLS policies on `campaign_contacts` apply to the parent table and are automatically inherited by all child partitions.

---

## 12. Cross-Schema Logical References

| Source Table.Column | Target (logical) | Rationale for no FK |
|---|---|---|
| `campaigns.organization_id` | `organization.organizations.id` | Cross-schema |
| `campaigns.agent_id` | `voice.agents.id` | Cross-schema; Voice is authoritative |
| `campaigns.agent_version_id` | `voice.agent_versions.id` | Cross-schema; pinned at start |
| `campaigns.phone_number_id` | `voice.tenant_phone_numbers.id` | Cross-schema |
| `campaigns.contact_list_id` | `campaign.contact_lists.id` | Same schema — FK permitted; aggregate independence |
| `campaigns.created_by` | `identity.users.id` | Cross-schema |
| `contact_lists.csv_import_job_id` | `campaign.csv_import_jobs.id` | Same schema — aggregate independence → logical |
| `csv_import_jobs.contact_list_id` | `campaign.contact_lists.id` | Same schema — FK permitted |
| `csv_import_jobs.campaign_id` | `campaign.campaigns.id` | Same schema — aggregate independence → logical |
| `campaign_contacts.campaign_id` | `campaign.campaigns.id` | Same schema — aggregate independence → logical (millions of rows; no cascade) |
| `campaign_contacts.contact_id` | `crm.contacts.id` | Cross-schema; CRM owns identity |
| `call_jobs.campaign_id` | `campaign.campaigns.id` | Same schema — logical |
| `call_jobs.campaign_contact_id` | `campaign.campaign_contacts.id` | Same schema — logical (partitioned; FK on partitioned parent not enforced) |
| `call_jobs.call_session_id` | `voice.call_sessions.id` | Cross-schema |
| `campaign_outcomes.campaign_id` | `campaign.campaigns.id` | Same schema — FK permitted |

**Same-schema FKs created:**
- `csv_import_jobs.contact_list_id → contact_lists(id) ON DELETE RESTRICT`
- `campaign_outcomes.campaign_id → campaigns(id) ON DELETE RESTRICT`

All other same-schema references remain logical to preserve aggregate independence.

---

## 13. PII Classification

| Table.Column | PII Category | Handling |
|---|---|---|
| `campaign_contacts.phone_e164` | `pii:phone` | Cached from CRM — masked in logs; cleared if contact is GDPR-erased in CRM |
| `call_jobs.phone_e164` | `pii:phone` | Same |

**Minimal PII principle:** Campaign does not store `full_name`, `email`, or `address`. The `phone_e164` cache on `campaign_contacts` and `call_jobs` is explicitly authorized by Phase 4D §4.2 ("`Phone` — cached for queue use"). No other PII is stored.

**GDPR erasure propagation:** when a CRM contact is GDPR-erased, the campaign worker handling the `contact.gdpr_erased` event must clear `campaign_contacts.phone_e164 = '[erased]'` and `call_jobs.phone_e164 = '[erased]'` for rows referencing the erased `contact_id`. The `[erased]` placeholder does not satisfy the `phone_e164 ~ '^\+[1-9][0-9]{6,14}$'` CHECK. Therefore, the CHECK constraint on these campaign columns is intentionally **not** applied — the columns are `TEXT NOT NULL` with only format validation at INSERT time, not at all times. This is documented in ADR-5E-011.

---

## 14. Complete PostgreSQL DDL

### 14.1 Campaign Schema and Functions

```sql
-- ================================================================
-- Migration 027: Campaign schema grant and functions
-- ================================================================

GRANT USAGE ON SCHEMA campaign TO app_api, app_worker, app_readonly, app_platform_admin;

-- No SECURITY DEFINER functions required in V1 (no cross-scope data like suppressions)
```

### 14.2 Contact Lists and CSV Import Jobs

```sql
-- ================================================================
-- Migration 028: campaign.contact_lists, campaign.csv_import_jobs
-- ================================================================

CREATE TABLE campaign.contact_lists (
  id                UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID          NOT NULL,
  name              TEXT          NOT NULL,
  source            TEXT          NOT NULL,
  status            TEXT          NOT NULL DEFAULT 'PENDING',
  contact_count     INTEGER       NULL,
  csv_import_job_id UUID          NULL,       -- logical ref: campaign.csv_import_jobs.id
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_contact_lists   PRIMARY KEY (id),
  CONSTRAINT chk_cl_source      CHECK (source IN ('CSV_IMPORT','CRM_FILTER','MANUAL')),
  CONSTRAINT chk_cl_status      CHECK (status IN ('PENDING','BUILDING','READY','FAILED')),
  CONSTRAINT chk_cl_count_nn    CHECK (contact_count IS NULL OR contact_count >= 0)
);

CREATE INDEX idx_cl_org_status  ON campaign.contact_lists (organization_id, status);
CREATE INDEX idx_cl_org_created ON campaign.contact_lists (organization_id, created_at DESC);

CREATE TRIGGER trg_cl_updated_at
  BEFORE UPDATE ON campaign.contact_lists
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE campaign.contact_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.contact_lists FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cl_tenant ON campaign.contact_lists
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON campaign.contact_lists TO app_api, app_worker;


CREATE TABLE campaign.csv_import_jobs (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  contact_list_id  UUID          NOT NULL,
  campaign_id      UUID          NULL,        -- logical ref: campaign.campaigns.id
  status           TEXT          NOT NULL DEFAULT 'PENDING',
  storage_ref      TEXT          NOT NULL,
  total_rows       INTEGER       NULL,
  processed_rows   INTEGER       NOT NULL DEFAULT 0,
  skipped_rows     INTEGER       NOT NULL DEFAULT 0,
  dnc_skipped_rows INTEGER       NOT NULL DEFAULT 0,
  errors           JSONB         NOT NULL DEFAULT '[]',
  created_by       UUID          NOT NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_csv_import_jobs    PRIMARY KEY (id),
  CONSTRAINT fk_cij_contact_list   FOREIGN KEY (contact_list_id) REFERENCES campaign.contact_lists(id) ON DELETE RESTRICT,
  CONSTRAINT chk_cij_status        CHECK (status IN ('PENDING','PROCESSING','COMPLETED','FAILED')),
  CONSTRAINT chk_cij_storage_path  CHECK (storage_ref LIKE 'org/%'),
  CONSTRAINT chk_cij_rows_nn       CHECK (processed_rows >= 0 AND skipped_rows >= 0 AND dnc_skipped_rows >= 0)
);

CREATE INDEX idx_cij_contact_list ON campaign.csv_import_jobs (contact_list_id);
CREATE INDEX idx_cij_campaign     ON campaign.csv_import_jobs (campaign_id)
  WHERE campaign_id IS NOT NULL;
CREATE INDEX idx_cij_org_status   ON campaign.csv_import_jobs (organization_id, status);

CREATE TRIGGER trg_cij_updated_at
  BEFORE UPDATE ON campaign.csv_import_jobs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE campaign.csv_import_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.csv_import_jobs FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cij_tenant ON campaign.csv_import_jobs
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON campaign.csv_import_jobs TO app_api, app_worker;
```

### 14.3 Campaigns

```sql
-- ================================================================
-- Migration 029: campaign.campaigns
-- ================================================================

CREATE TABLE campaign.campaigns (
  id                     UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID          NOT NULL,
  name                   TEXT          NOT NULL,
  description            TEXT          NULL,
  status                 TEXT          NOT NULL DEFAULT 'DRAFT',
  agent_id               UUID          NOT NULL,     -- logical ref: voice.agents.id
  agent_version_id       UUID          NULL,         -- logical ref: voice.agent_versions.id; pinned at PREPARING
  phone_number_id        UUID          NOT NULL,     -- logical ref: voice.tenant_phone_numbers.id
  contact_list_id        UUID          NULL,         -- logical ref: campaign.contact_lists.id
  scheduling_policy      JSONB         NOT NULL DEFAULT '{}',
  concurrency_policy     JSONB         NOT NULL DEFAULT '{}',
  rate_limit_policy      JSONB         NOT NULL DEFAULT '{}',
  retry_policy           JSONB         NOT NULL DEFAULT '{}',
  qualification_criteria JSONB         NULL,
  total_contacts         INTEGER       NULL,
  started_at             TIMESTAMPTZ   NULL,
  completed_at           TIMESTAMPTZ   NULL,
  cancelled_at           TIMESTAMPTZ   NULL,
  created_by             UUID          NOT NULL,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaigns          PRIMARY KEY (id),
  CONSTRAINT chk_camp_status       CHECK (status IN (
    'DRAFT','SCHEDULED','PREPARING','RUNNING','PAUSED',
    'STOPPING','COMPLETED','CANCELLED','FAILED'
  )),
  CONSTRAINT chk_camp_name_len     CHECK (length(name) BETWEEN 1 AND 200),
  CONSTRAINT chk_camp_contacts_nn  CHECK (total_contacts IS NULL OR total_contacts >= 0)
);

COMMENT ON COLUMN campaign.campaigns.agent_id          IS 'logical ref: voice.agents.id — must be PUBLISHED';
COMMENT ON COLUMN campaign.campaigns.agent_version_id  IS 'logical ref: voice.agent_versions.id — pinned at PREPARING, immutable after';
COMMENT ON COLUMN campaign.campaigns.phone_number_id   IS 'logical ref: voice.tenant_phone_numbers.id';

CREATE INDEX idx_camp_org_status  ON campaign.campaigns (organization_id, status);
CREATE INDEX idx_camp_org_created ON campaign.campaigns (organization_id, created_at DESC);
CREATE INDEX idx_camp_org_running ON campaign.campaigns (organization_id)
  WHERE status IN ('RUNNING','PAUSED','STOPPING');

-- Functional index for APScheduler poll: campaigns due for start
CREATE INDEX idx_camp_due_for_start
  ON campaign.campaigns ((scheduling_policy->>'start_at')::timestamptz)
  WHERE status = 'SCHEDULED';

CREATE TRIGGER trg_camp_updated_at
  BEFORE UPDATE ON campaign.campaigns
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE campaign.campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaigns FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_camp_tenant ON campaign.campaigns
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON campaign.campaigns TO app_api, app_worker;
```

### 14.4 Campaign Contacts (Partitioned)

```sql
-- ================================================================
-- Migration 030: campaign.campaign_contacts (partitioned)
-- ================================================================

CREATE TABLE campaign.campaign_contacts (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  imported_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),  -- PARTITION KEY
  organization_id       UUID          NOT NULL,
  campaign_id           UUID          NOT NULL,    -- logical ref: campaign.campaigns.id
  contact_id            UUID          NOT NULL,    -- logical ref: crm.contacts.id
  phone_e164            TEXT          NOT NULL,    -- pii:phone; cached from CRM
  status                TEXT          NOT NULL DEFAULT 'PENDING',
  attempt_count         INTEGER       NOT NULL DEFAULT 0,
  max_attempts          INTEGER       NOT NULL,
  last_attempt_at       TIMESTAMPTZ   NULL,
  next_attempt_at       TIMESTAMPTZ   NULL,
  outcome               TEXT          NULL,
  qualification_result  TEXT          NULL,
  qualification_reason  TEXT          NULL,
  lead_score_at_call    INTEGER       NULL,
  is_dnc                BOOLEAN       NOT NULL DEFAULT FALSE,
  ineligibility_reason  TEXT          NULL,
  call_session_refs     UUID[]        NOT NULL DEFAULT '{}',
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaign_contacts    PRIMARY KEY (id, imported_at),
  CONSTRAINT chk_cc_status           CHECK (status IN (
    'PENDING','CALLING','ANSWERED','NO_ANSWER','BUSY','VOICEMAIL','FAILED',
    'RETRY_SCHEDULED','COMPLETED','QUALIFIED','DISQUALIFIED','EXHAUSTED',
    'DNC_SKIPPED','INELIGIBLE'
  )),
  CONSTRAINT chk_cc_attempt_count    CHECK (attempt_count >= 0 AND attempt_count <= 5),
  CONSTRAINT chk_cc_max_attempts     CHECK (max_attempts BETWEEN 1 AND 5),
  CONSTRAINT chk_cc_outcome          CHECK (outcome IS NULL OR outcome IN (
    'ANSWERED_COMPLETED','ANSWERED_TRANSFERRED','NO_ANSWER','VOICEMAIL','FAILED','CANCELLED'
  )),
  CONSTRAINT chk_cc_qual_result      CHECK (qualification_result IS NULL OR
    qualification_result IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE')),
  CONSTRAINT chk_cc_score_range      CHECK (lead_score_at_call IS NULL OR
    (lead_score_at_call >= 0 AND lead_score_at_call <= 100)),
  CONSTRAINT chk_cc_refs_len         CHECK (cardinality(call_session_refs) <= 5)
  -- NOTE: phone_e164 has NO CHECK constraint here — GDPR erasure may set '[erased]'
  -- Format validation is enforced at INSERT time by application layer only
) PARTITION BY RANGE (imported_at);

COMMENT ON COLUMN campaign.campaign_contacts.phone_e164 IS
  'pii:phone — cached from crm.contacts at import time; '
  'GDPR erasure sets to [erased] (no E.164 CHECK applied)';
COMMENT ON COLUMN campaign.campaign_contacts.contact_id IS
  'logical ref: crm.contacts.id — authoritative identity source';
COMMENT ON COLUMN campaign.campaign_contacts.is_dnc IS
  'denormalized from crm.contact_suppressions at import time — re-checked at dispatch';

CREATE INDEX idx_cc_campaign_status
  ON campaign.campaign_contacts (organization_id, campaign_id, status);
CREATE INDEX idx_cc_campaign_retry
  ON campaign.campaign_contacts (campaign_id, next_attempt_at)
  WHERE status = 'RETRY_SCHEDULED';
CREATE INDEX idx_cc_campaign_pending
  ON campaign.campaign_contacts (campaign_id, id)
  WHERE status = 'PENDING';
CREATE INDEX idx_cc_contact_id
  ON campaign.campaign_contacts (organization_id, contact_id);
CREATE INDEX idx_cc_org_time_brin
  ON campaign.campaign_contacts USING BRIN (organization_id, imported_at);

CREATE TRIGGER trg_cc_updated_at
  BEFORE UPDATE ON campaign.campaign_contacts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE campaign.campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaign_contacts FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cc_tenant ON campaign.campaign_contacts
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON campaign.campaign_contacts TO app_api, app_worker;

-- Parametric partition creation via create_monthly_partitions()
CREATE TABLE campaign.campaign_contacts_default
  PARTITION OF campaign.campaign_contacts DEFAULT;
```

### 14.5 Call Jobs

```sql
-- ================================================================
-- Migration 031: campaign.call_jobs
-- ================================================================

CREATE TABLE campaign.call_jobs (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL,
  campaign_id           UUID          NOT NULL,    -- logical ref: campaign.campaigns.id
  campaign_contact_id   UUID          NOT NULL,    -- logical ref: campaign.campaign_contacts.id
  phone_e164            TEXT          NOT NULL,    -- pii:phone; cached for dispatch
  attempt_number        INTEGER       NOT NULL,
  idempotency_key       CHAR(64)      NOT NULL,    -- SHA-256 of (campaign_id+campaign_contact_id+attempt_number)
  status                TEXT          NOT NULL DEFAULT 'PENDING',
  call_session_id       UUID          NULL,        -- logical ref: voice.call_sessions.id
  dispatched_at         TIMESTAMPTZ   NULL,
  completed_at          TIMESTAMPTZ   NULL,
  failure_reason        TEXT          NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_call_jobs            PRIMARY KEY (id),
  CONSTRAINT chk_cj_status           CHECK (status IN ('PENDING','DISPATCHED','SUCCEEDED','FAILED','SUPERSEDED')),
  CONSTRAINT chk_cj_attempt_number   CHECK (attempt_number >= 1 AND attempt_number <= 5)
  -- phone_e164: no E.164 CHECK — GDPR erasure may set '[erased]'
);

COMMENT ON COLUMN campaign.call_jobs.idempotency_key IS
  'SHA-256(campaign_id + campaign_contact_id + attempt_number) — prevents duplicate dispatch';
COMMENT ON COLUMN campaign.call_jobs.call_session_id IS
  'logical ref: voice.call_sessions.id — set when Voice Platform accepts the call';
COMMENT ON COLUMN campaign.call_jobs.phone_e164 IS
  'pii:phone — cached for dispatch; GDPR erasure sets to [erased]';

-- Partial UNIQUE enforces Phase 4D §4.5 inv.1: at most one active job per idempotency key
CREATE UNIQUE INDEX uq_cj_idempotency_active
  ON campaign.call_jobs (idempotency_key)
  WHERE status IN ('PENDING','DISPATCHED');

CREATE INDEX idx_cj_campaign_contact
  ON campaign.call_jobs (organization_id, campaign_contact_id);
CREATE INDEX idx_cj_call_session
  ON campaign.call_jobs (call_session_id)
  WHERE call_session_id IS NOT NULL;
CREATE INDEX idx_cj_campaign_active
  ON campaign.call_jobs (campaign_id, status)
  WHERE status IN ('PENDING','DISPATCHED');

CREATE TRIGGER trg_cj_updated_at
  BEFORE UPDATE ON campaign.call_jobs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE campaign.call_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.call_jobs FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cj_tenant ON campaign.call_jobs
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON campaign.call_jobs TO app_api, app_worker;
```

### 14.6 Campaign Outcomes

```sql
-- ================================================================
-- Migration 032: campaign.campaign_outcomes
-- ================================================================

CREATE TABLE campaign.campaign_outcomes (
  id                          UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id             UUID          NOT NULL,
  campaign_id                 UUID          NOT NULL,
  computed_at                 TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  total_contacts              INTEGER       NOT NULL DEFAULT 0,
  attempted                   INTEGER       NOT NULL DEFAULT 0,
  answered                    INTEGER       NOT NULL DEFAULT 0,
  no_answer                   INTEGER       NOT NULL DEFAULT 0,
  busy                        INTEGER       NOT NULL DEFAULT 0,
  failed                      INTEGER       NOT NULL DEFAULT 0,
  voicemail                   INTEGER       NOT NULL DEFAULT 0,
  dnc_skipped                 INTEGER       NOT NULL DEFAULT 0,
  ineligible                  INTEGER       NOT NULL DEFAULT 0,
  exhausted                   INTEGER       NOT NULL DEFAULT 0,
  qualified                   INTEGER       NOT NULL DEFAULT 0,
  disqualified                INTEGER       NOT NULL DEFAULT 0,
  inconclusive                INTEGER       NOT NULL DEFAULT 0,
  answer_rate_pct             NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
  qualification_rate_pct      NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
  total_call_minutes          NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  total_cost_amount           NUMERIC(18,4) NULL,
  total_cost_currency         CHAR(3)       NULL,
  estimated_revenue_amount    NUMERIC(18,4) NULL,
  estimated_revenue_currency  CHAR(3)       NULL,
  roi_pct                     NUMERIC(8,2)  NULL,
  created_at                  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaign_outcomes    PRIMARY KEY (id),
  CONSTRAINT fk_co_campaign          FOREIGN KEY (campaign_id) REFERENCES campaign.campaigns(id) ON DELETE RESTRICT,
  CONSTRAINT uq_co_campaign          UNIQUE (campaign_id),
  CONSTRAINT chk_co_rates            CHECK (answer_rate_pct BETWEEN 0 AND 100
                                        AND qualification_rate_pct BETWEEN 0 AND 100),
  CONSTRAINT chk_co_minutes          CHECK (total_call_minutes >= 0),
  CONSTRAINT chk_co_counts_nn        CHECK (total_contacts >= 0 AND attempted >= 0),
  CONSTRAINT chk_co_cost_pair        CHECK ((total_cost_amount IS NULL) = (total_cost_currency IS NULL)),
  CONSTRAINT chk_co_revenue_pair     CHECK ((estimated_revenue_amount IS NULL) = (estimated_revenue_currency IS NULL))
);

CREATE INDEX idx_co_org ON campaign.campaign_outcomes (organization_id);

CREATE TRIGGER trg_co_updated_at
  BEFORE UPDATE ON campaign.campaign_outcomes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE campaign.campaign_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaign_outcomes FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_co_tenant ON campaign.campaign_outcomes
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON campaign.campaign_outcomes TO app_api, app_worker;
```

### 14.7 RLS and Grants Finalization

```sql
-- ================================================================
-- Migration 033: Campaign grants finalization
-- ================================================================

GRANT SELECT ON campaign.campaigns         TO app_readonly;
GRANT SELECT ON campaign.contact_lists     TO app_readonly;
GRANT SELECT ON campaign.csv_import_jobs   TO app_readonly;
GRANT SELECT ON campaign.campaign_contacts TO app_readonly;
GRANT SELECT ON campaign.call_jobs         TO app_readonly;
GRANT SELECT ON campaign.campaign_outcomes TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA campaign TO app_platform_admin;
```

---

## 15. Query Patterns

### 15.1 Create Campaign

```sql
-- SET LOCAL app.tenant_id = $org_id
INSERT INTO campaign.campaigns (
  id, organization_id, name, description, status,
  agent_id, phone_number_id, scheduling_policy, concurrency_policy,
  rate_limit_policy, retry_policy, created_by
) VALUES (
  $id, $org_id, $name, $desc, 'DRAFT',
  $agent_id, $phone_number_id,
  $scheduling_policy::jsonb, $concurrency_policy::jsonb,
  $rate_limit_policy::jsonb, $retry_policy::jsonb, $user_id
);
-- RLS: organization_id = current_tenant_id() ✓
-- No duplicate check needed: campaigns have no natural unique key beyond PK
```

### 15.2 Schedule Campaign

```sql
UPDATE campaign.campaigns
SET status = 'SCHEDULED',
    scheduling_policy = scheduling_policy || jsonb_build_object('start_at', $start_at),
    updated_at = NOW()
WHERE id = $campaign_id
  AND organization_id = organization.current_tenant_id()
  AND status IN ('DRAFT');
-- Index: pk_campaigns; RLS ✓
-- Application validates: contact list is READY, start_at in future
```

### 15.3 Start Campaign (PREPARING)

```sql
UPDATE campaign.campaigns
SET status = 'PREPARING',
    agent_version_id = $agent_version_id,   -- pinned now; immutable after
    started_at = NOW(),
    updated_at = NOW()
WHERE id = $campaign_id
  AND organization_id = organization.current_tenant_id()
  AND status IN ('DRAFT','SCHEDULED');
-- After: enqueue prepare_campaign_contacts_task(campaign_id) to Celery
```

### 15.4 Claim Next Eligible Contact for Dispatch

```sql
-- Phase 4D §15.5 DDR-4D-003: Redis queue is authoritative for dispatch order.
-- This is the fallback / reconciliation query when Redis is cold:
SELECT id, imported_at, contact_id, phone_e164, attempt_count, max_attempts
FROM campaign.campaign_contacts
WHERE campaign_id = $campaign_id
  AND organization_id = organization.current_tenant_id()
  AND status = 'PENDING'
  AND imported_at >= $partition_start  -- partition pruning
ORDER BY id
LIMIT $batch_size;
-- Index: idx_cc_campaign_pending
-- NOTE: Redis Call Queue (BLPOP) is the primary dispatch mechanism.
-- This query rebuilds the queue on Redis failure (DDR-4D-003).
```

### 15.5 Create Call Job Idempotently

```sql
-- INSERT with partial unique conflict detection:
INSERT INTO campaign.call_jobs (
  id, organization_id, campaign_id, campaign_contact_id, phone_e164,
  attempt_number, idempotency_key, status
)
VALUES ($id, $org_id, $campaign_id, $cc_id, $phone, $attempt, $ikey, 'PENDING')
ON CONFLICT (idempotency_key) WHERE status IN ('PENDING','DISPATCHED') DO NOTHING;
-- If DO NOTHING fires: existing PENDING/DISPATCHED job detected; skip dispatch.
-- RETURNING id tells the caller whether the insert succeeded.
-- Index: uq_cj_idempotency_active ✓
```

### 15.6 Check CRM Suppression at Dispatch (Application-Layer Pattern)

Campaign NEVER reads suppression directly from `crm.contact_suppressions` during the hot dispatch path. It reads from Redis:

```python
# Redis fast path (hot path):
suppressed = await redis.get(f"suppression:{org_id}:{phone_e164}")
if suppressed:
    # Mark INELIGIBLE; do not dispatch

# On Redis miss (cold path — application service, not DDL):
# Call ContactLookupPort.is_suppressed(phone, org_id)
# which queries crm.contact_suppressions via the CRM application service
```

The `crm.contact_suppressions` table is **never accessed directly by Campaign SQL**. Campaign queries CRM via a port interface (application layer). This maintains bounded context independence.

### 15.7 Consume `call.ended` Event

```sql
-- Step 1: Find the CallJob by call_session_id
SELECT id, campaign_contact_id, campaign_id, organization_id, attempt_number
FROM campaign.call_jobs
WHERE call_session_id = $call_session_id
  AND organization_id = organization.current_tenant_id();
-- Index: idx_cj_call_session

-- Step 2: Update CallJob status
UPDATE campaign.call_jobs
SET status = 'SUCCEEDED', completed_at = NOW(), updated_at = NOW()
WHERE id = $call_job_id
  AND organization_id = organization.current_tenant_id();

-- Step 3: Update CampaignContact with outcome
UPDATE campaign.campaign_contacts
SET outcome = $outcome,
    status = CASE $outcome
      WHEN 'ANSWERED_COMPLETED' THEN 'COMPLETED'
      WHEN 'NO_ANSWER' THEN 'NO_ANSWER'
      WHEN 'VOICEMAIL' THEN 'VOICEMAIL'
      ELSE 'FAILED'
    END,
    attempt_count = attempt_count + 1,
    last_attempt_at = NOW(),
    call_session_refs = call_session_refs || ARRAY[$call_session_id::uuid],
    updated_at = NOW()
WHERE id = $campaign_contact_id
  AND imported_at >= $imported_at_hint  -- partition pruning
  AND organization_id = organization.current_tenant_id();
-- Both updates in one transaction; publish domain events after commit
```

### 15.8 Schedule Retry

```sql
UPDATE campaign.campaign_contacts
SET status = 'RETRY_SCHEDULED',
    next_attempt_at = $next_attempt_at,
    updated_at = NOW()
WHERE id = $campaign_contact_id
  AND imported_at >= $imported_at_hint
  AND organization_id = organization.current_tenant_id()
  AND status IN ('NO_ANSWER','BUSY','VOICEMAIL','FAILED');
-- After: ZADD campaign:retry_queue:{org}:{campaign_id} next_attempt_at.unix cc_id
-- Index: idx_cc_campaign_retry used for finding due retries
```

### 15.9 Mark Contact INELIGIBLE (Phase 4I)

```sql
UPDATE campaign.campaign_contacts
SET status = 'INELIGIBLE',
    ineligibility_reason = $reason,  -- EligibilityReason enum value
    updated_at = NOW()
WHERE id = $campaign_contact_id
  AND imported_at >= $imported_at_hint
  AND organization_id = organization.current_tenant_id()
  AND status NOT IN ('QUALIFIED','DISQUALIFIED','COMPLETED','EXHAUSTED',
                     'DNC_SKIPPED','INELIGIBLE');
-- Only terminal non-blocked statuses are protected
```

### 15.10 Complete Campaign (Completion Check)

```sql
-- Completion check: are all contacts terminal?
SELECT COUNT(*) FILTER (WHERE status NOT IN (
  'QUALIFIED','DISQUALIFIED','COMPLETED','EXHAUSTED','DNC_SKIPPED','INELIGIBLE'
)) AS non_terminal_count
FROM campaign.campaign_contacts
WHERE campaign_id = $campaign_id
  AND organization_id = organization.current_tenant_id();
-- Also check: no PENDING or DISPATCHED call jobs remain
SELECT COUNT(*) FROM campaign.call_jobs
WHERE campaign_id = $campaign_id
  AND organization_id = organization.current_tenant_id()
  AND status IN ('PENDING','DISPATCHED');

-- If both = 0: transition campaign to COMPLETED
UPDATE campaign.campaigns
SET status = 'COMPLETED', completed_at = NOW(), updated_at = NOW()
WHERE id = $campaign_id
  AND organization_id = organization.current_tenant_id()
  AND status IN ('RUNNING','STOPPING');
-- After: enqueue compute_campaign_outcome_task(campaign_id)
```

---

## 16. Concurrency Design

### 16.1 Duplicate Dispatch Prevention

**Problem:** Two Celery workers pop the same `CampaignContactId` from the Redis Call Queue (at-least-once delivery).

**Solution:** Partial UNIQUE index `uq_cj_idempotency_active` on `call_jobs (idempotency_key) WHERE status IN ('PENDING','DISPATCHED')`. The second worker's `INSERT ... ON CONFLICT DO NOTHING` returns 0 rows inserted → skips dispatch. This is an `O(1)` DB check with no locking.

### 16.2 Concurrent Campaign Start

**Problem:** Two API requests both try to start the same campaign simultaneously.

**Solution:** Optimistic UPDATE: `WHERE status IN ('DRAFT','SCHEDULED')`. Only one transaction succeeds (the second sees `0 rows updated`). The campaign aggregate's state machine is enforced at the DB level via the CHECK constraint + UPDATE predicate.

### 16.3 Executor Tick Race

**Problem:** Two executor ticks run for the same campaign simultaneously.

**Solution (Phase 4D §15.5):** Distributed lock `campaign:lock:{campaign_id}` via Redis SETNX with TTL. The DB is not used for lock coordination. If Redis is unavailable, both ticks may run — the idempotency key on `call_jobs` prevents double-dispatch.

### 16.4 `call.ended` Delivered Twice

**Problem:** Event bus delivers `call.ended` twice for the same call.

**Solution:** The `call_jobs` status check — `UPDATE ... WHERE id = $job_id AND status = 'DISPATCHED'`. The second delivery finds `status = 'SUCCEEDED'` and exits with 0 rows updated. No duplicate processing occurs. Idempotency at the domain layer.

### 16.5 Campaign Completion Race

**Problem:** Multiple workers check completion simultaneously and all attempt the COMPLETED transition.

**Solution:** `UPDATE campaigns SET status = 'COMPLETED' WHERE id = $id AND status IN ('RUNNING','STOPPING')`. Only one transaction commits the row change. Others see 0 rows updated and skip. No advisory lock needed.

---

## 17. Audience Model — Questions Answered

### Q1: New CRM state vs. snapshot at campaign run start?

**Answer:** Campaign contacts are materialized (snapshot) at `PREPARING` phase. The `phone_e164` and `contact_id` are snapshotted. If a contact's phone changes in CRM after campaign start, the campaign uses the snapshotted phone — this is correct because the campaign was built for a specific audience.

### Q2: Contact becomes DNC after audience creation?

**Answer:** The dispatch-time eligibility re-check (Phase 4I §6.3) catches this. Before creating a `CallJob`, the executor checks Redis `suppression:{org}:{phone}`. If a new suppression was added after audience build, the dispatch-time check fails and the contact is marked `INELIGIBLE(SUPPRESSED_ORG)`. The campaign never calls a suppressed contact even if they were eligible at import time.

### Q3: Consent withdrawn after audience creation?

**Answer:** Same pattern — dispatch-time consent re-check via Redis `consent:{org}:{contact_id}:{purpose}`. If consent is withdrawn, the contact becomes `INELIGIBLE(CONSENT_WITHDRAWN)`.

### Q4: Contact deleted/GDPR-erased after audience creation?

**Answer:** The CRM publishes a `contact.gdpr_erased` event. A campaign subscriber clears `phone_e164 = '[erased]'` on matching `campaign_contacts` and `call_jobs` rows. The contact's status is set to `INELIGIBLE(PHONE_INVALID)` — no further calls are attempted. Suppression records for the original phone remain active in `crm.contact_suppressions`, so even re-imported contacts with the same phone are blocked.

---

## 18. Alembic Migration Plan

```
Phase 5D migrations (019–026)
        ↓
027_campaign_schema_and_functions
    down_revision = '026_crm_seed_data'
    purpose: GRANT USAGE on campaign schema; any campaign-specific functions

028_campaign_contact_lists_csv_jobs
    down_revision = '027_campaign_schema_and_functions'
    purpose: campaign.contact_lists, campaign.csv_import_jobs,
             FK (csv_import_jobs.contact_list_id → contact_lists),
             indexes, triggers, RLS, grants

029_campaign_campaigns
    down_revision = '028_campaign_contact_lists_csv_jobs'
    purpose: campaign.campaigns, functional index on scheduling_policy->start_at,
             indexes, trigger, RLS, grants

030_campaign_contacts_partitioned
    down_revision = '029_campaign_campaigns'
    purpose: campaign.campaign_contacts (partitioned parent + DEFAULT partition),
             parametric monthly partitions via create_monthly_partitions(),
             indexes, trigger, RLS, grants

031_campaign_call_jobs
    down_revision = '030_campaign_contacts_partitioned'
    purpose: campaign.call_jobs, partial UNIQUE idempotency index,
             indexes, trigger, RLS, grants

032_campaign_outcomes
    down_revision = '031_campaign_call_jobs'
    purpose: campaign.campaign_outcomes, FK (outcomes.campaign_id → campaigns),
             unique constraint, indexes, trigger, RLS, grants

033_campaign_grants_finalize
    down_revision = '032_campaign_outcomes'
    purpose: app_readonly grants; app_platform_admin full access
```

**Downgrade order:** 033 → 032 → 031 → 030 → 029 → 028 → 027

---

## 19. Security Review

### 19.1 DNC Bypass Impossibility

Campaign NEVER calls `UPDATE crm.contact_suppressions`. Campaign NEVER reads `crm.contacts.do_not_call` for enforcement (it's a denormalized read). The dispatch path reads from Redis suppression cache, backed by `crm.contact_suppressions` via the CRM port. A bug in Campaign code cannot bypass CRM's authoritative suppression because Campaign has no write access to CRM schema and reads only through an application-layer port.

### 19.2 Cross-Tenant Campaign Access

RLS on all campaign tables: `organization_id = current_tenant_id()`. A tenant cannot read, write, or enumerate another tenant's campaigns, contacts, or call jobs.

### 19.3 Stale Audience Eligibility

The dispatch-time re-check (Phase 4I §6.3) makes stale eligibility safe. A contact marked eligible at import time but suppressed at dispatch time is blocked at dispatch — even if they are already in the Redis Call Queue. The idempotency key check on `call_jobs` + the INELIGIBLE status transition ensures no call is placed.

### 19.4 Phone PII in Campaign Contacts

`phone_e164` is cached for queue operations only (Phase 4D §4.2). It is never included in event payloads (Phase 4H §7.3 — PII must not leak through events). Campaign does not expose phone via any API that doesn't verify the caller owns the campaign's organization. GDPR erasure propagation clears the phone in-place.

### 19.5 Tenant Isolation Test Matrix

| Test | Mechanism | Expected Result |
|---|---|---|
| Tenant A reads Tenant B's campaign | RLS on campaigns | 0 rows |
| Tenant A reads Tenant B's campaign contacts | RLS on campaign_contacts | 0 rows |
| Tenant A tries to start Tenant B's campaign | RLS UPDATE predicate | 0 rows affected |
| Missing tenant context | `current_tenant_id() = NULL` | 0 rows on all tables |
| Duplicate CallJob dispatch | Partial UNIQUE on idempotency_key | INSERT DO NOTHING |
| `call.ended` delivered twice | UPDATE WHERE status = 'DISPATCHED' | Second update: 0 rows |
| DNC contact attempts to get dispatched | Dispatch-time suppression check | INELIGIBLE; no CallJob created |
| GDPR-erased contact in campaign | phone_e164 = '[erased]'; status = INELIGIBLE | No call placed |
| Worker calling CRM suppression table directly | Bounded context boundary — Campaign reads via port | Port validates; no direct SQL |

---

## 20. Carry-Forward Hardening Items

| Item | Description | Target Phase |
|---|---|---|
| **Recurring campaign runs table** | OQ-4D-03: when recurring campaigns are designed, a `campaign_runs` table will be needed. `campaigns` currently has no run concept beyond single-run timestamps. | Phase 9 (Campaign Engine implementation) |
| **`call_jobs` partitioning** | At scale, `call_jobs` may need partitioning. Re-evaluate at Phase 22 with actual volume data. | Phase 22 (Deployment) |
| **`(campaign_id, contact_id)` DB uniqueness** | App-layer invariant only. A partial UNIQUE index `(campaign_id, contact_id, imported_at_truncated_month)` may be feasible but is complex. Evaluate if duplicate enqueue becomes a production issue. | Phase 9 |
| **OQ-4D-01 DNC proof logging** | Should dispatch-time DNC checks be logged as evidence? Would require a `campaign_compliance_events` table. Pending legal determination. | Phase 9 / Legal |
| **GDPR event subscriber** | `contact.gdpr_erased` subscriber that clears `phone_e164` in campaign_contacts and call_jobs is an application-layer concern — documented here, implemented in Phase 9. | Phase 9 |
| **`create_monthly_partitions()` validation** | The partition helper must be unit-tested. | Phase 22 |

---

## 21. ADRs

### ADR-5E-001: Campaign Lifecycle — 9 States Including PREPARING and STOPPING

**Decision:** The campaign status machine from Phase 4D §7.1 is implemented as-is: `DRAFT | SCHEDULED | PREPARING | RUNNING | PAUSED | STOPPING | COMPLETED | CANCELLED | FAILED`. No states are merged or simplified.

**Rationale:** `PREPARING` separates contact list materialization (which may be slow for large CSV imports) from `RUNNING` (when the executor begins dispatching). `STOPPING` allows graceful in-flight call completion without launching new calls.

### ADR-5E-002: Audience — Materialized Snapshot at PREPARING

**Decision:** CampaignContacts are created during the `PREPARING` phase by processing the ContactList. Phone numbers are snapshotted. The audience is not a live CRM query at dispatch time.

**Rationale:** Phase 4D §4.2 defines `CampaignContact.Phone` as "cached for queue use." A live CRM query at each dispatch would require a CRM read for every call — millions of CRM queries per campaign. Snapshot is correct and scales. Dispatch-time eligibility re-check (Phase 4I §6.3) ensures stale snapshots don't bypass DNC/consent checks.

### ADR-5E-003: Eligibility Authority — CRM Owns Consent and Suppression

**Decision:** Campaign never creates, updates, or stores authoritative consent or suppression records. Campaign reads these from CRM via application-layer ports (Redis-cached, Postgres-authoritative).

**Rationale:** Phase 5D is the authoritative design for consent and suppression. Duplicating these in Campaign would create two sources of truth that can diverge.

### ADR-5E-004: Three-Way Eligibility Decision (Phase 4I)

**Decision:** `INELIGIBLE` is added as a terminal status on `campaign_contacts` (alongside `DNC_SKIPPED`) to represent permanent blocks discovered at dispatch time (consent withdrawn, platform suppression, invalid number). `DNC_SKIPPED` is retained for import-time DNC blocks.

**Rationale:** Phase 4I §6.2 mandates the three-way `ELIGIBLE/DEFERRED/INELIGIBLE` result. A boolean was insufficient. The `ineligibility_reason` column records the Phase 4I `EligibilityReason` enum value.

### ADR-5E-005: No `campaign_runs` Table

**Decision:** Phase 4D has no `CampaignRun` aggregate. The single-execution model uses timestamps on `campaigns` directly. Recurring campaigns (OQ-4D-03) are out of scope for V1.

**Rationale:** Adding a table not in the authoritative DDD would be premature normalization. Carry-forward item created.

### ADR-5E-006: `campaign_contacts` Partitioned RANGE Monthly on `imported_at`

**Decision:** The contacts table is partitioned from day one. Other campaign tables are not partitioned in V1.

**Rationale:** A single large campaign can import millions of contacts in a month. At platform scale (thousands of organizations), this table grows without bound. Day-one partitioning is mandatory for the same reasons as voice transcripts.

### ADR-5E-007: Redis Queues Are Not PostgreSQL Tables

**Decision:** Call Queue and Retry Queue are Redis data structures. They are not persisted in PostgreSQL campaign tables.

**Rationale:** Phase 4D DDR-4D-003: Redis queues are reconstructable from `campaign_contacts.status` on failure. Making them PostgreSQL tables would serialize the executor tick on DB writes per dispatched call — incompatible with the sub-5-second tick interval at thousands of concurrent calls.

### ADR-5E-008: Campaign ↔ Voice Boundary — Logical References Only

**Decision:** `call_jobs.call_session_id` is a `UUID` logical reference to `voice.call_sessions.id`. No FK constraint exists. Campaign does not own Voice call state.

**Rationale:** Phase 5A cross-schema FK prohibition. Campaign consumes Voice events asynchronously; the call state may not yet exist in PostgreSQL when Campaign receives the dispatch acknowledgment.

### ADR-5E-009: Idempotency via Partial UNIQUE on `call_jobs`

**Decision:** `UNIQUE (idempotency_key) WHERE status IN ('PENDING','DISPATCHED')` is the primary idempotency mechanism for dispatch. `ON CONFLICT DO NOTHING` is the application pattern.

**Rationale:** Phase 4D DDR-4D-001: idempotency key is a domain concept. The partial unique index makes the invariant "at most one active job per attempt" enforceable at the DB level, not just the application level. Terminal-status jobs with the same key are permitted (history retention).

### ADR-5E-010: No Day-One Partitioning for `call_jobs`

**Decision:** `call_jobs` is not partitioned in V1. Re-evaluated at Phase 22.

**Rationale:** `call_jobs` are transient — they complete within seconds of dispatch and are potentially archived post-campaign. Without real volume data, partitioning would be premature. The campaign-contact-level indexes are sufficient for V1 operational queries.

### ADR-5E-011: Phone PII CHECK Constraint Omitted for GDPR Erasure

**Decision:** `campaign_contacts.phone_e164` and `call_jobs.phone_e164` do NOT have `CHECK (phone_e164 ~ '^\+...\$')`. Format validation is enforced at INSERT time by the application layer only.

**Rationale:** GDPR erasure sets `phone_e164 = '[erased]'` which does not satisfy E.164 format. The CHECK would block erasure updates. Unlike `crm.contacts.phone_e164` which uses a tombstone placeholder that satisfies the regex (ADR-5D-007 in Phase 5D), Campaign's derived/cached phone column does not need to maintain the E.164 invariant post-erasure since it serves only the call dispatch function (which the INELIGIBLE status already prevents from running).

### ADR-5E-012: Campaign Concurrency — Distributed Lock in Redis, Not Advisory Lock in Postgres

**Decision:** executor tick concurrency is controlled via Redis SETNX lock. DB-level advisory locks are not used.

**Rationale:** Phase 4D §23 risk analysis: a Redis lock is sufficient because: (1) Redis is always available in the execution path (it carries the Call Queue); (2) the idempotency key on `call_jobs` provides a second-layer guarantee; (3) PostgreSQL advisory locks do not survive Celery worker crashes cleanly.

---

## Phase 5E Final Consistency Review

### A. Phase 5A Consistency ✅

| Standard | Compliance |
|---|---|
| UUIDv7 PKs | All tables use `DEFAULT gen_uuid_v7()` |
| No cross-schema FK | Only within-schema FKs (`csv_import_jobs.contact_list_id`, `campaign_outcomes.campaign_id`). All cross-schema references are logical UUIDs. |
| TEXT + CHECK for status | No PostgreSQL ENUMs used |
| Money columns | `NUMERIC(18,4)` + `CHAR(3)` pair on `campaign_outcomes`. No bare monetary values. |
| JSONB only where justified | Four policy JSONB columns: each is a bounded value object always read whole with the Campaign aggregate. `errors` JSONB on `csv_import_jobs` is bounded at 100 entries. |
| Append-only | No append-only tables required by Phase 4D (activities are in CRM). `call_jobs` is mutable (lifecycle transitions). `campaign_contacts` is mutable (status machine). |
| PII | `phone_e164` tagged in COMMENT ON. Minimal PII — only campaign-operation-required fields. |
| Partitioning | `campaign_contacts` partitioned RANGE monthly. No other table requires V1 partitioning. |
| Migration standards | 7 migrations (027–033) with explicit `down_revision` chain. |

### B. Phase 5B Consistency ✅

`organization.current_tenant_id()`, `gen_uuid_v7()`, `set_updated_at()` used throughout. All RLS uses `ENABLE + FORCE`.

### C. Phase 5C Consistency ✅

Voice remains authoritative for `voice.call_sessions`, `voice.agents`, `voice.agent_versions`, `voice.tenant_phone_numbers`. Campaign references these via logical UUIDs only. Campaign does not write to Voice schema.

### D. Phase 5D Consistency ✅

CRM remains authoritative for contacts, consent, suppression. Campaign never writes to `crm.*`. Consent and suppression are read via application-layer ports (Redis-first, Postgres-authoritative). `crm.contact_suppressions` is the DNC authority — Campaign does not query `crm.contacts.do_not_call`.

### E. Event Boundaries ✅

Campaign publishes events (`campaign.started`, `campaign.contact.call_attempted`, etc.). Campaign consumes Voice events (`call.ended`, `conversation.qualification_set`) and CRM events (`contact.dnc_flagged`, `contact.gdpr_erased`) via event subscribers. No circular dependencies.

### F. Scale ✅

`campaign_contacts` (high-volume) is separated from `campaigns` (configuration). `campaign_contacts` is partitioned. Redis carries queue state. PostgreSQL carries authoritative durable state.

### G. SQL Validity ✅

All DDL is valid PostgreSQL 15+. Partitioned table PK includes partition key. Functional index on JSONB field is valid. Partial UNIQUE index on `call_jobs` is valid.

### H. Migration Validity ✅

7 migrations with explicit dependency chain. FK targets exist before FKs are created. Partitioned table created before DEFAULT partition.

---

```
PHASE 5E STATUS

Campaign schema:
APPROVED

Campaign lifecycle:
APPROVED

Audience:
APPROVED

Eligibility:
APPROVED

Consent integration:
APPROVED

Suppression integration:
APPROVED

Campaign runs:
APPROVED (no runs table required — documented as carry-forward for recurring campaigns)

Contact attempts:
APPROVED

Voice integration:
APPROVED

RLS:
APPROVED

RBAC:
APPROVED (uses Phase 5B permission system; no new permissions created in schema)

Security:
APPROVED

Partitioning:
APPROVED

DDL:
APPROVED

Indexes:
APPROVED

Migration plan:
APPROVED

Overall:
PHASE 5F READY
```

**No blocking issues found.** All Phase 4D aggregates mapped to tables. Phase 4I eligibility pipeline integrated via `INELIGIBLE` terminal status and three-way eligibility decision. Campaign remains a consumer — never an owner — of CRM consent and suppression. Voice boundary maintained via logical UUID references and event consumption. 12 ADRs close all significant architectural decisions.

**Phase 5F** designs the `knowledge` schema — the RAG (retrieval-augmented generation) bounded context.

---

## Amendment — Phase 6H Campaign Final Remediation (2026-08-28)

A Phase 6H adversarial remediation review found two genuine production-safety defects in the outbound-dispatch path this document's original text had left as accepted, unmitigated residual risk rather than closed invariants, plus (in a same-day follow-up adversarial pass) a SECURITY DEFINER `search_path` defect and two genuine cross-tenant/cross-campaign ownership-verification gaps in the first version of the fix itself. All are resolved by `098_5E1.sql` (Phase 5E.1), a purely additive forward migration — no table, column, constraint, index, or grant in `027_5E.sql`–`033_5E.sql` above is altered. **This amendment was live-executed and race-tested** against a disposable local PostgreSQL 18 database — not merely design-reviewed — per `docs/phase-06-api-design/6H-Campaign-APIs.md` §49's full transcript.

**§7.1's `(campaign_id, contact_id)` "application-layer-only" note is superseded.** `campaign.campaign_contact_identities` — a small, non-partitioned table whose literal primary key *is* `(campaign_id, contact_id)` — now provides true, database-enforced global uniqueness for this business identity, without needing `campaign_contacts`' own partition key at all. `campaign.fn_enqueue_contact()` performs the identity claim and the `campaign_contacts` row insert atomically, in one transaction, mirroring `crm.event_consumer_dedup` + `crm.fn_claim_event()` (`094_5D3.sql`) exactly. A duplicate/redelivered materialization attempt for the same `(campaign_id, contact_id)` is now a safe, idempotent no-op — it can never produce two `CampaignContact` rows, and therefore can never produce two independently-idempotency-tracked `CallJob` dial targets for the same real-world Contact. **Live-proven, not merely designed:** a genuine two-connection concurrent race for the identical `(campaign_id, contact_id)` produced exactly one winner and zero duplicate rows in either table.

**§16 ("Concurrency Design")'s duplicate-dispatch analysis is extended, not replaced.** §16.1's `call_jobs` partial-unique-index analysis remains exactly correct and unchanged — it is still the layer that prevents two workers from creating two active `CallJob` rows for the *same already-reserved* attempt. What was missing is the layer *before* that: nothing previously serialized a `campaigns.status` read against a concurrent `PauseCampaign`/`StopCampaign` write, so a dispatch attempt could complete its `CallJob` INSERT moments after a Pause/Stop had already durably committed. `campaign.fn_reserve_dispatch()` closes this by taking `SELECT ... FOR UPDATE` on the specific `campaigns` row, then (deterministic order) the specific `campaign_contacts` row, before ever inserting into `call_jobs` — because `PauseCampaign`/`StopCampaign`/`ResumeCampaign`/`CancelCampaign` are themselves plain `UPDATE campaigns ... WHERE id = $1` statements, this makes the two code paths mutually exclusive on the same row via PostgreSQL's own row-level locking, with no new locking scheme introduced. **Live-proven under both orderings:** a reservation already holding the row lock when a concurrent Pause arrived was allowed to complete (Pause's own `UPDATE` genuinely blocked ~1.5 seconds, observed, waiting for the reservation's transaction to commit, then proceeded); a reservation attempted after Pause had already committed was correctly and immediately refused (`CAMPAIGN_NOT_RUNNING`). Full analysis, race-by-race: `docs/phase-06-api-design/6H-Campaign-APIs.md` §16–§18, §22.5, §32.

**Two genuine tenant/campaign-ownership defects found by live adversarial testing of the first version of this fix, not by inspection alone, and closed in this same migration:** `fn_enqueue_contact()` originally trusted `p_organization_id` without ever confirming `p_campaign_id` belonged to it — because this function is `SECURITY DEFINER` (its owner bypasses RLS entirely, identical to `crm.fn_merge_contacts()`'s own documented posture), this explicit lookup is the *entire* tenant-isolation guarantee for this function, not one layer among several, and its absence was a real, live-reproduced cross-tenant write before the fix. `fn_reserve_dispatch()` separately never confirmed the targeted `CampaignContact` belonged to the claimed `campaign_id` (only to the claimed `organization_id`), which would have let a mismatched same-tenant `(campaign_id, campaign_contact_id)` pair create a `call_jobs` row referencing the wrong campaign. Both are now explicit, mandatory predicates; re-tested live afterward and confirmed correctly rejected.

**Full DDL, rationale, and race-condition analysis:** `098_5E1.sql`'s own header comment; `docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md`'s "Phase 6H Campaign Final Remediation" entry; `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 3), §49.

**Verification status, stated plainly:** this amendment, unlike the earlier same-day pass, **was** live-executed: a fresh-database `alembic upgrade head` (001→099) and an incremental upgrade from an existing `097_5D5` database both passed (exit code 0); function `search_path`/`SECURITY DEFINER`/grant configuration was inspected directly against `pg_proc`/`information_schema`; the concurrency and cross-tenant scenarios above were exercised as genuine, overlapping, multi-connection transactions, not simulated sequentially. Full transcripts: `docs/phase-06-api-design/6H-Campaign-APIs.md` §49.
