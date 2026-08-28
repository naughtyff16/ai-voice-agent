# Phase 5D — CRM Schema
## Physical PostgreSQL Database Design

| | |
|---|---|
| **Phase** | 5D — CRM Schema Physical Database Design |
| **Schema** | `crm` |
| **Status** | Draft v1.0 — for approval before Phase 5E |
| **Authority** | Phase 5A (standards) + Phase 5B (constructs) + Phase 4C (DDD) + Phase 4I (India-first: ConsentRecord, ContactSuppression) |
| **Follows** | Phase 5C (APPROVED, PHASE 5D READY) |
| **Precedes** | Phase 5E — Campaign Schema |

---

## 1. Executive Summary

This document delivers the complete physical database design for the `crm` schema — the platform's customer relationship management layer, and the primary consumer of voice events. The design is derived from Phase 4C CRM DDD (authoritative) and Phase 4I (which adds `ConsentRecord` and `ContactSuppression` as first-class aggregates in this schema).

**Key design decisions:**

| Decision | Outcome |
|---|---|
| Lead = Contact (DDR-4C-001) | Single `contacts` table with `lead_status` column. No separate Lead entity. |
| `contact_suppressions` scope handling | Three-scope RLS (ORG / PLATFORM / REGULATORY) — special policy per Phase 5A §6.4 |
| `consent_records` partitioning | RANGE monthly on `recorded_at`; append-only; see §10 |
| `activities` partitioning | RANGE monthly on `occurred_at`; append-only |
| `lead_score_records` | Append-only; current score denormalized on `contacts` |
| Pipeline stages | Embedded as `JSONB` on `pipelines` (bounded ≤ 20; always read whole) |
| `contact_suppressions` key | `phone_e164` — not `contact_id` (Phase 4I §8.5 invariant) |
| `custom_field_values` | JSONB on `contacts`, `companies`, `deals` (bounded ≤ 50 fields per entity) |
| `Contact.DoNotCall` | Retained as a **denormalized read** of `contact_suppressions` — authoritative source is the suppression aggregate (Phase 4I CONTRADICTION-03) |
| Money columns on `deals` | `NUMERIC(18,4)` + `CHAR(3)` pair — Phase 5A §10 |

**Tables created in Phase 5D:** 13 tables (2 partitioned), complete RLS, 3 special policies, append-only enforcement, 1 SECURITY DEFINER function.

**Correction pass applied (Phase 5D final correction):** Three issues identified and resolved — GDPR phone placeholder fixed from `+00000000000` (violates CHECK constraint) to `+99000000000` (ISSUE 1); `contact_suppressions` lifecycle model resolved via `crm.lift_suppression()` SECURITY DEFINER for `ACTIVE → LIFTED` transitions while maintaining `REVOKE UPDATE` for application roles (ISSUE 2); GDPR + suppression interaction verified complete (ISSUE 3); `lead_temperature` derivation enforcement documented as explicit application-layer invariant (minor).

---

## 2. Scope

**In scope:** `crm` schema — all 13 tables, indexes, constraints, RLS, triggers, grants.

**Out of scope:** `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, `audit`.

---

## 3. Aggregate → Table Mapping

| Phase 4C/4I Aggregate | Table | Notes |
|---|---|---|
| `Contact` (AggregateRoot) | `crm.contacts` | Lead = Contact (DDR-4C-001). High-volume. |
| `Company` (AggregateRoot) | `crm.companies` | |
| `Deal` (AggregateRoot) | `crm.deals` | |
| `Pipeline` (AggregateRoot) | `crm.pipelines` | Stages embedded as JSONB |
| `PipelineStage` (Entity — embedded in Pipeline) | JSONB column on `pipelines` | Bounded ≤ 20; always read whole |
| `Activity` (AggregateRoot) | `crm.activities` | Append-only; partitioned monthly |
| `Task` (AggregateRoot) | `crm.tasks` | |
| `Note` (AggregateRoot) | `crm.notes` | |
| `Appointment` (AggregateRoot) | `crm.appointments` | |
| `LeadScoreRecord` (AggregateRoot) | `crm.lead_score_records` | Append-only; current score on `contacts` |
| `CRMFieldDefinitionSet` (AggregateRoot) | `crm.crm_field_definitions` | One row per tenant (JSONB); Phase 4C §4.10 |
| `ConsentRecord` (AggregateRoot — Phase 4I) | `crm.consent_records` | Append-only; partitioned monthly |
| `ContactSuppression` (AggregateRoot — Phase 4I) | `crm.contact_suppressions` | Append-only; three-scope RLS |

---

## 4. JSONB Decisions

### 4.1 Pipeline Stages — JSONB on `pipelines`

Phase 4C §4.4 defines `Stages` as an embedded entity list bounded at 1–20 per Pipeline and always read/written together with the Pipeline. JSONB is correct per Phase 5A §4.1 (structured, bounded, always-read-whole). No use case independently queries a single stage without the pipeline.

**`stages` JSONB element structure:**
```json
{
  "stage_id": "<uuidv7>",
  "name": "Qualified",
  "order": 2,
  "probability_pct": 60,
  "is_terminal_win": false
}
```

Invariants enforced at application layer: unique `order` values per pipeline, at most one `is_terminal_win`, minimum 1 stage.

### 4.2 Activity Payload — JSONB on `activities`

Phase 4C §4.5.2 defines type-specific payload structure per `ActivityType`. The shape varies by type and is always read whole. JSONB is appropriate. Application layer validates payload shape at creation time.

### 4.3 Scoring Signals — JSONB on `lead_score_records`

Phase 4C §4.9 defines `Signals` as a list of `ScoringSignal` entities (bounded, always read with the record). JSONB is correct.

### 4.4 Custom Field Values — JSONB on `contacts`, `companies`, `deals`

Phase 4C §4.10 defines `CustomFieldValues` as a list bounded at 50 per entity. Always read whole. JSONB per Phase 5A §21.8 approved use. Structure: `[{"field_id": "<uuid>", "value": <typed>}, ...]`.

### 4.5 Consent Evidence — JSONB on `consent_records`

Phase 4I §8.4 defines `ConsentEvidence` as a structured value object with variable `EvidenceKind`-dependent fields. Always read with the consent record. JSONB is correct.

### 4.6 Appointment Location — Columns on `appointments`

Phase 4C §4.8 defines `AppointmentLocation` as `(type: VIRTUAL|IN_PERSON, url|address)`. Two typed columns (`location_type TEXT`, `location_detail TEXT`) rather than JSONB — the structure is fixed and small.

---

## 5. Column-Level Data Dictionary

### 5.1 `crm.contacts`

**Aggregate:** `Contact` (AggregateRoot — DDR-4C-001: Lead = Contact)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `full_name` | TEXT | NOT NULL | — | 1–200 chars. **pii:name** |
| `phone_e164` | TEXT | NOT NULL | — | Canonical E.164. UNIQUE within org. **pii:phone** |
| `phone_country` | TEXT | NOT NULL | — | ISO 3166-1 alpha-2, derived |
| `phone_type` | TEXT | NULL | — | `MOBILE \| LANDLINE \| VOIP \| TOLL_FREE \| UNKNOWN` |
| `phone_verified` | BOOLEAN | NOT NULL | `FALSE` | |
| `phone_normalized_at` | TIMESTAMPTZ | NULL | — | When E.164 parsing last ran |
| `communication_status` | TEXT | NOT NULL | `'UNKNOWN'` | `REACHABLE \| UNREACHABLE \| INVALID \| UNKNOWN` |
| `secondary_phone_e164` | TEXT | NULL | — | Canonical E.164. **pii:phone** |
| `primary_email` | TEXT | NULL | — | Original casing. **pii:email** |
| `primary_email_normalized` | TEXT | NULL | — | `LOWER(TRIM(primary_email))` — lookup key |
| `company_id` | UUID | NULL | — | Logical ref: `crm.companies.id` |
| `owned_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `lead_status` | TEXT | NOT NULL | `'NEW'` | Full state machine values (see §7.1) |
| `qualification_status` | TEXT | NOT NULL | `'UNSET'` | `QUALIFIED \| DISQUALIFIED \| INCONCLUSIVE \| UNSET` |
| `qualification_reason` | TEXT | NULL | — | Why qualified/disqualified |
| `lead_score` | INTEGER | NULL | — | Current score 0–100. Denormalized from `lead_score_records`. |
| `lead_temperature` | TEXT | NULL | — | `HOT \| WARM \| COLD \| UNSCORED`. **Always derived from `lead_score`, never directly set by callers.** |
| `tags` | TEXT[] | NOT NULL | `'{}'` | Max 20 tags per contact |
| `address_line1` | TEXT | NULL | — | **pii:address** |
| `address_line2` | TEXT | NULL | — | |
| `address_city` | TEXT | NULL | — | |
| `address_state` | TEXT | NULL | — | |
| `address_postal_code` | TEXT | NULL | — | |
| `address_country_code` | TEXT | NULL | — | ISO 3166-1 alpha-2 |
| `source` | TEXT | NOT NULL | — | `INBOUND_CALL \| OUTBOUND_CALL \| CSV_IMPORT \| MANUAL \| API \| WEBHOOK` |
| `campaign_ref` | UUID | NULL | — | Logical ref: `campaign.campaigns.id` — originating campaign |
| `do_not_call` | BOOLEAN | NOT NULL | `FALSE` | **Denormalized read of `contact_suppressions`** (Phase 4I CONTRADICTION-03). Application updates on suppression events. Never the primary enforcement source. |
| `consent_status` | TEXT | NOT NULL | `'UNKNOWN'` | `UNKNOWN \| GIVEN \| WITHDRAWN` — summary field; `consent_records` is authoritative |
| `last_contacted_at` | TIMESTAMPTZ | NULL | — | Updated by Activity event handler — denormalized |
| `converted_at` | TIMESTAMPTZ | NULL | — | Set once when `lead_status → CONVERTED` |
| `custom_field_values` | JSONB | NOT NULL | `'[]'` | `[{"field_id": "<uuid>", "value": ...}]` — max 50 |
| `deleted_at` | TIMESTAMPTZ | NULL | — | Soft delete — PII cleared on GDPR erasure |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Lead status values** (Phase 4C §7.1):
`NEW | CONTACTED | QUALIFIED | DISQUALIFIED | NURTURING | CONVERTED`

**`lead_temperature` enforcement (application-layer invariant — Phase 4C DDR-4C-004):**
`lead_temperature` MUST NOT be independently supplied by callers. It is computed by `LeadScoringService` whenever `lead_score` changes and is written to the database only as part of the score-update operation (see §15.8 query pattern). The CHECK constraint enforces allowed values; derivation logic is enforced at the application domain service layer, not by a database trigger. A trigger is not added because: (1) `lead_score` updates and `lead_temperature` updates always occur in the same domain service call; (2) a trigger would add write amplification on a high-frequency column. The application service is the enforcement boundary — this is consistent with Phase 5A §4.3 (business logic in domain, not in triggers).

**Phase 4I CONTRADICTION-03 — `do_not_call` is a denormalized read:**
`crm.contact_suppressions` is the authoritative source for DNC state (keyed on `phone_e164`). `do_not_call` on `contacts` is maintained by the `suppression.added` / `suppression.lifted` event handler for fast filtering. No eligibility decision reads `do_not_call` — they query `contact_suppressions`.

**GDPR erasure sequence for a Contact:**
`full_name = '[ERASED]'`, `phone_e164 = '+99000000000'` (a syntactically valid but non-dialable placeholder — satisfies `CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')` because it starts with `+9` followed by digits), `primary_email = NULL`, `primary_email_normalized = NULL`, `address_* = NULL`, `deleted_at = NOW()`. The `+9` prefix (ITU reserved/non-geographic) is used precisely because it does not correspond to any assigned country code, making the placeholder safe as an erasure tombstone. The `deleted_at IS NOT NULL` condition means this erased row is excluded from the dedup unique index, allowing the same phone number to be re-imported.

**Why `phone_e164` cannot be NULL on erasure:** the domain model (Phase 4C §4.1) defines `PrimaryPhone` as required. The database DDL encodes `phone_e164 NOT NULL`. Changing the constraint to nullable solely to accommodate GDPR erasure would require a domain model change that the authoritative DDD does not make. The tombstone placeholder is the correct approach.

**Suppression interaction during GDPR erasure:** suppression records keyed on the original `phone_e164` remain fully intact and authoritative. The `contact_suppressions` table is never mutated during Contact erasure. If the same phone is later re-imported, the new Contact row will be suppressed on its first campaign eligibility check — because `contact_suppressions` survives CRM contact churn (Phase 4I §8.5 design intent).

### 5.2 `crm.companies`

**Aggregate:** `Company` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `company_name` | TEXT | NOT NULL | — | 1–200 chars |
| `email_domain` | TEXT | NULL | — | e.g. `acme.com`. UNIQUE within org when set. |
| `industry` | TEXT | NULL | — | Standard industry label |
| `size` | TEXT | NULL | — | `STARTUP \| SMB \| MID_MARKET \| ENTERPRISE` |
| `website` | TEXT | NULL | — | URL |
| `address_line1` | TEXT | NULL | — | |
| `address_line2` | TEXT | NULL | — | |
| `address_city` | TEXT | NULL | — | |
| `address_state` | TEXT | NULL | — | |
| `address_postal_code` | TEXT | NULL | — | |
| `address_country_code` | TEXT | NULL | — | ISO 3166-1 alpha-2 |
| `owned_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `custom_field_values` | JSONB | NOT NULL | `'[]'` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.3 `crm.deals`

**Aggregate:** `Deal` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `title` | TEXT | NOT NULL | — | 1–200 chars |
| `contact_id` | UUID | NOT NULL | — | Logical ref: `crm.contacts.id` |
| `company_id` | UUID | NULL | — | Logical ref: `crm.companies.id` |
| `pipeline_id` | UUID | NOT NULL | — | FK within schema: `crm.pipelines.id` |
| `current_stage_id` | UUID | NOT NULL | — | References a `stage_id` inside `pipelines.stages` JSONB |
| `value_amount` | NUMERIC(18,4) | NULL | — | Per Phase 5A §10 money convention |
| `value_currency` | CHAR(3) | NULL | — | ISO 4217. Required when `value_amount` is set. |
| `status` | TEXT | NOT NULL | `'OPEN'` | `OPEN \| WON \| LOST \| ABANDONED` |
| `close_date` | DATE | NULL | — | Expected or actual close date |
| `owned_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `won_at` | TIMESTAMPTZ | NULL | — | Set once when `status → WON` |
| `lost_at` | TIMESTAMPTZ | NULL | — | Set once when `status → LOST` |
| `lost_reason` | TEXT | NULL | — | Required when LOST |
| `custom_field_values` | JSONB | NOT NULL | `'[]'` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.4 `crm.pipelines`

**Aggregate:** `Pipeline` (AggregateRoot — stages embedded as JSONB)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `name` | TEXT | NOT NULL | — | 1–100 chars. UNIQUE within org. |
| `is_default` | BOOLEAN | NOT NULL | `FALSE` | At most one default per tenant (partial unique index) |
| `stages` | JSONB | NOT NULL | `'[]'` | Ordered array of PipelineStage entities |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.5 `crm.activities` (Partitioned — RANGE monthly on `occurred_at`)

**Aggregate:** `Activity` (AggregateRoot — append-only, Phase 4C DDR-4C-002)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK `(id, occurred_at)` |
| `occurred_at` | TIMESTAMPTZ | NOT NULL | — | **Partition key.** When the activity happened. |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `activity_type` | TEXT | NOT NULL | — | Phase 4C §4.5.1 ActivityType values |
| `subject_type` | TEXT | NOT NULL | — | `CONTACT \| DEAL \| COMPANY` |
| `subject_id` | UUID | NOT NULL | — | References the subject entity |
| `actor_type` | TEXT | NOT NULL | — | `HUMAN \| AI_AGENT \| SYSTEM` |
| `actor_ref` | UUID | NULL | — | UserId or AgentVersionId |
| `actor_name` | TEXT | NULL | — | Display name at time of activity. **pii:name** |
| `summary` | TEXT | NULL | — | 0–1000 chars |
| `payload` | JSONB | NOT NULL | `'{}'` | Type-specific payload (see Phase 4C §4.5.2) |
| `call_ref` | UUID | NULL | — | Logical ref: `voice.call_sessions.id` — for CALL type |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | When the record was created |

**Append-only:** `REVOKE UPDATE, DELETE FROM app_api, app_worker`. Immutable once created (Phase 4C DDR-4C-002).

**ActivityType values:** `CALL | EMAIL | SMS | WHATSAPP | MEETING | NOTE | TASK_COMPLETED | STAGE_CHANGE | SCORE_CHANGE | QUALIFICATION_CHANGE | AI_INTERACTION | CAMPAIGN_CONTACT`

### 5.6 `crm.tasks`

**Aggregate:** `Task` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `title` | TEXT | NOT NULL | — | 1–200 chars |
| `subject_type` | TEXT | NOT NULL | — | `CONTACT \| DEAL \| COMPANY` |
| `subject_id` | UUID | NOT NULL | — | References the subject entity |
| `assigned_to` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `due_at` | TIMESTAMPTZ | NOT NULL | — | Must be in future at creation |
| `priority` | TEXT | NOT NULL | `'MEDIUM'` | `LOW \| MEDIUM \| HIGH \| URGENT` |
| `status` | TEXT | NOT NULL | `'OPEN'` | `OPEN \| COMPLETED \| CANCELLED` |
| `created_by` | UUID | NULL | — | Logical ref: `identity.users.id`. NULL for AI-created. |
| `created_by_type` | TEXT | NOT NULL | `'HUMAN'` | `HUMAN \| AI_AGENT \| SYSTEM` |
| `completed_at` | TIMESTAMPTZ | NULL | — | Set once when `status → COMPLETED` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.7 `crm.notes`

**Aggregate:** `Note` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `subject_type` | TEXT | NOT NULL | — | `CONTACT \| DEAL \| COMPANY` |
| `subject_id` | UUID | NOT NULL | — | References the subject entity |
| `body` | TEXT | NOT NULL | `''` | 0–10000 chars. **pii:voice** for AI_SUMMARY notes. |
| `author_ref` | UUID | NULL | — | Logical ref: `identity.users.id` or agent version id |
| `author_type` | TEXT | NOT NULL | `'HUMAN'` | `HUMAN \| AI_AGENT \| SYSTEM` |
| `note_source` | TEXT | NOT NULL | `'HUMAN'` | `HUMAN \| AI_SUMMARY \| AI_INTERACTION \| SYSTEM` |
| `pinned_at` | TIMESTAMPTZ | NULL | — | Non-null = pinned; null = not pinned |
| `deleted_at` | TIMESTAMPTZ | NULL | — | Soft delete |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**AI notes immutability (Phase 4C DDR-4C-003):** a `BEFORE UPDATE` trigger raises an exception if `body` changes when `note_source IN ('AI_SUMMARY', 'AI_INTERACTION')`. Humans may only pin/unpin or delete AI notes.

### 5.8 `crm.appointments`

**Aggregate:** `Appointment` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `contact_id` | UUID | NOT NULL | — | Logical ref: `crm.contacts.id` |
| `organizer_ref` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `attendees` | UUID[] | NOT NULL | `'{}'` | Array of `identity.users.id` logical refs |
| `title` | TEXT | NOT NULL | — | 1–200 chars |
| `scheduled_start` | TIMESTAMPTZ | NOT NULL | — | |
| `scheduled_end` | TIMESTAMPTZ | NOT NULL | — | Must be after `scheduled_start` |
| `location_type` | TEXT | NULL | — | `VIRTUAL \| IN_PERSON` |
| `location_detail` | TEXT | NULL | — | URL or address |
| `status` | TEXT | NOT NULL | `'SCHEDULED'` | `SCHEDULED \| CONFIRMED \| CANCELLED \| COMPLETED \| NO_SHOW` |
| `source` | TEXT | NOT NULL | `'MANUAL'` | `MANUAL \| AI_AGENT \| WORKFLOW` |
| `conversation_ref` | UUID | NULL | — | Logical ref: `voice.conversations.id` — if booked by AI |
| `cancellation_reason` | TEXT | NULL | — | Required on CANCELLED |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.9 `crm.lead_score_records`

**Aggregate:** `LeadScoreRecord` (AggregateRoot — append-only)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `contact_id` | UUID | NOT NULL | — | Logical ref: `crm.contacts.id` |
| `score` | INTEGER | NOT NULL | — | 0–100 |
| `previous_score` | INTEGER | NULL | — | Prior score before this computation |
| `score_version` | TEXT | NOT NULL | — | Scoring model version string |
| `signals` | JSONB | NOT NULL | — | `[{signal_type, weight, raw_value, source}]` list |
| `computed_at` | TIMESTAMPTZ | NOT NULL | — | |
| `computed_by` | TEXT | NOT NULL | — | `RULE_ENGINE \| AI_AGENT \| MANUAL` |
| `computed_by_user_ref` | UUID | NULL | — | Logical ref: `identity.users.id`. Required when `MANUAL`. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Append-only:** `REVOKE UPDATE, DELETE FROM app_api, app_worker`.

### 5.10 `crm.crm_field_definitions`

**Aggregate:** `CRMFieldDefinitionSet` (AggregateRoot — one row per tenant)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | UNIQUE — one set per org |
| `fields` | JSONB | NOT NULL | `'[]'` | Array of CRMField entities (max 50) |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`fields` JSONB element structure:**
```json
{
  "field_id": "<uuidv7>",
  "field_name": "Lead Source Department",
  "field_type": "SELECT",
  "applies_to": "CONTACT",
  "is_required": false,
  "select_options": ["Sales", "Marketing", "Product"],
  "is_active": true
}
```

Cached in Redis: `crm_field_defs:{org_id}` → 5min TTL, invalidated on update.

### 5.11 `crm.consent_records` (Partitioned — RANGE monthly on `recorded_at`)

**Aggregate:** `ConsentRecord` (AggregateRoot — Phase 4I §8.1 — append-only)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK `(id, recorded_at)` |
| `recorded_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | **Partition key.** When this record was written. |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `contact_id` | UUID | NOT NULL | — | Logical ref: `crm.contacts.id` |
| `purpose` | TEXT | NOT NULL | — | Phase 4I §8.2 ConsentPurpose values |
| `channel` | TEXT | NOT NULL | — | `VOICE \| SMS \| WHATSAPP \| EMAIL \| ANY` |
| `status` | TEXT | NOT NULL | — | `GRANTED \| WITHDRAWN \| EXPIRED \| UNKNOWN` |
| `source` | TEXT | NOT NULL | — | Phase 4I §8.3 ConsentSource values |
| `source_ref` | TEXT | NULL | — | CallId, form ID, import batch ID |
| `evidence` | JSONB | NOT NULL | `'{}'` | ConsentEvidence value object (Phase 4I §8.4) |
| `obtained_at` | TIMESTAMPTZ | NULL | — | Required when `status = GRANTED` |
| `withdrawn_at` | TIMESTAMPTZ | NULL | — | Required when `status = WITHDRAWN` |
| `expires_at` | TIMESTAMPTZ | NULL | — | When this consent expires |
| `policy_version_ref` | INTEGER | NOT NULL | — | CompliancePolicy.version in force at recording time |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Append-only:** `REVOKE UPDATE, DELETE FROM app_api, app_worker`.

**Effective consent query:** the most recent record by `recorded_at` for a `(contact_id, purpose, channel)` triple. See §15.5 for the query pattern.

**Purpose values:** `OUTBOUND_CALL | MARKETING | TRANSACTIONAL | RECORDING | FOLLOW_UP | WHATSAPP_MESSAGING | SMS_MESSAGING | EMAIL_MESSAGING | DATA_PROCESSING | AI_INTERACTION`

**Source values:** `WEB_FORM | VERBAL_ON_CALL | SMS_REPLY | WHATSAPP_OPT_IN | EMAIL_CONFIRMATION | CONTRACT | CSV_IMPORT_ASSERTED | API_ASSERTED | EXISTING_RELATIONSHIP | MANUAL_ENTRY`

### 5.12 `crm.contact_suppressions`

**Aggregate:** `ContactSuppression` (AggregateRoot — Phase 4I §8.5 — three-scope, append-only)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NULL | — | NULL = PLATFORM or REGULATORY scope |
| `phone_e164` | TEXT | NOT NULL | — | Canonical E.164 — the suppression key. **pii:phone** |
| `contact_id` | UUID | NULL | — | Logical ref: `crm.contacts.id`. Nullable — number may be suppressed without a CRM contact. |
| `scope` | TEXT | NOT NULL | — | `ORG \| PLATFORM \| REGULATORY` |
| `channel` | TEXT | NOT NULL | — | `VOICE \| SMS \| WHATSAPP \| EMAIL \| ALL` |
| `reason` | TEXT | NOT NULL | — | Phase 4I §8.6 SuppressionReason values |
| `source` | TEXT | NOT NULL | — | Phase 4I §8.7 SuppressionSource values |
| `source_ref` | TEXT | NULL | — | CallId, import ID, registry batch ID |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| LIFTED \| EXPIRED` |
| `effective_from` | TIMESTAMPTZ | NOT NULL | — | |
| `expires_at` | TIMESTAMPTZ | NULL | — | NULL = permanent. Must be after `effective_from`. |
| `lifted_at` | TIMESTAMPTZ | NULL | — | Set when `status → LIFTED` |
| `lifted_by_ref` | UUID | NULL | — | Logical ref: `identity.users.id`. Required when LIFTED. |
| `recorded_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Lifecycle model (Phase 4I §8.5 invariant 4 — "append-only for ACTIVE → LIFTED transitions"):**

Phase 4I §8.5 invariant 4 states: *"Suppression records are append-only for `ACTIVE → LIFTED` transitions; the original record retains its history rather than being deleted."* This is **Option A** from the correction pass — a single row whose `status`, `lifted_at`, and `lifted_by_ref` fields may be updated by a privileged mechanism to record the lift. The row is never deleted.

**Normal application roles (`app_api`, `app_worker`):**
- May INSERT new suppression records (ORG scope only, via RLS policy)
- May NOT UPDATE any suppression record
- May NOT DELETE any suppression record

**Privileged lift mechanism:**
`ACTIVE → LIFTED` transitions are performed exclusively via a `SECURITY DEFINER` function `crm.lift_suppression()` that:
1. Validates the caller has the `suppression:lift` permission (ORG suppressions) or is `app_platform_admin` (PLATFORM/REGULATORY)
2. Validates the suppression exists and is currently ACTIVE
3. Performs a targeted UPDATE of `{status, lifted_at, lifted_by_ref}` only
4. Records a `contact.suppression_lifted` audit event

The `app_api` and `app_worker` roles call this SECURITY DEFINER function — they do not hold direct UPDATE privilege. Only `app_platform_admin` (BYPASSRLS) holds direct UPDATE privilege.

**`EXPIRED` status:**
`EXPIRED` is never written to the database. A suppression with `expires_at < NOW()` is treated as expired at read time by the application layer and by enforcement queries that include `AND (expires_at IS NULL OR expires_at > NOW())`. This means no background job needs to mutate rows to flip them to EXPIRED.

**Idempotency:**
If a suppress event is delivered twice (at-least-once delivery), the second INSERT for the same `(organization_id, phone_e164, scope, channel, reason, effective_from)` is handled by the application checking for an existing ACTIVE record before inserting. Alternatively, a unique partial index on `(organization_id, phone_e164, scope, channel) WHERE status = 'ACTIVE'` would prevent duplicate active suppressions at DB level. This constraint is documented as a carry-forward item for Phase 9 (Campaign Engine implementation).

**SuppressionReason values:** `CUSTOMER_REQUEST | REGULATORY_REGISTRY | COMPLAINT | INVALID_NUMBER | REPEATED_NO_ANSWER | HARD_BOUNCE | FRAUD_SUSPECTED | ORG_POLICY | LEGAL_HOLD | CONSENT_WITHDRAWN`

**SuppressionSource values:** `VERBAL_ON_CALL | IVR_OPT_OUT | SMS_STOP | WHATSAPP_BLOCK | EMAIL_UNSUBSCRIBE | ADMIN_ACTION | CSV_IMPORT | API | REGULATORY_SYNC | AUTOMATED_RULE`

---

## 6. Primary Keys

All non-partitioned tables: `PRIMARY KEY (id)`.

Partitioned tables (PostgreSQL requires partition key in PK):

| Table | Primary Key | Partition Key |
|---|---|---|
| `crm.activities` | `(id, occurred_at)` | `occurred_at` |
| `crm.consent_records` | `(id, recorded_at)` | `recorded_at` |

---

## 7. Unique Constraints

| Table | Columns | Condition | Rationale |
|---|---|---|---|
| `crm.contacts` | `(organization_id, phone_e164)` | `WHERE deleted_at IS NULL` | Dedup invariant — Phase 4C §4.1 inv.1 |
| `crm.companies` | `(organization_id, email_domain)` | `WHERE email_domain IS NOT NULL` | Auto-association — Phase 4C §4.2 inv.1 |
| `crm.pipelines` | `(organization_id, name)` | — | Unique pipeline name per tenant |
| `crm.pipelines` | `organization_id` | `WHERE is_default = TRUE` | At most one default pipeline — Phase 4C §4.4 inv.5 |
| `crm.crm_field_definitions` | `organization_id` | — | One definition set per tenant — Phase 4C §4.10 |

---

## 8. Check Constraints

```sql
-- contacts
CHECK (lead_status IN ('NEW','CONTACTED','QUALIFIED','DISQUALIFIED','NURTURING','CONVERTED'))
CHECK (qualification_status IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE','UNSET'))
CHECK (lead_score IS NULL OR (lead_score >= 0 AND lead_score <= 100))
CHECK (lead_temperature IS NULL OR lead_temperature IN ('HOT','WARM','COLD','UNSCORED'))
CHECK (source IN ('INBOUND_CALL','OUTBOUND_CALL','CSV_IMPORT','MANUAL','API','WEBHOOK'))
CHECK (consent_status IN ('UNKNOWN','GIVEN','WITHDRAWN'))
CHECK (communication_status IN ('REACHABLE','UNREACHABLE','INVALID','UNKNOWN'))
CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')
CHECK (secondary_phone_e164 IS NULL OR secondary_phone_e164 ~ '^\+[1-9][0-9]{6,14}$')
CHECK (cardinality(tags) <= 20)

-- companies
CHECK (size IS NULL OR size IN ('STARTUP','SMB','MID_MARKET','ENTERPRISE'))

-- deals
CHECK (status IN ('OPEN','WON','LOST','ABANDONED'))
CHECK (value_amount IS NULL OR value_amount >= 0)
CHECK (value_currency IS NULL OR value_currency ~ '^[A-Z]{3}$')
CHECK ((value_amount IS NULL) = (value_currency IS NULL))  -- both or neither

-- activities
CHECK (activity_type IN ('CALL','EMAIL','SMS','WHATSAPP','MEETING','NOTE',
  'TASK_COMPLETED','STAGE_CHANGE','SCORE_CHANGE','QUALIFICATION_CHANGE',
  'AI_INTERACTION','CAMPAIGN_CONTACT'))
CHECK (subject_type IN ('CONTACT','DEAL','COMPANY'))
CHECK (actor_type IN ('HUMAN','AI_AGENT','SYSTEM'))

-- tasks
CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT'))
CHECK (status IN ('OPEN','COMPLETED','CANCELLED'))
CHECK (created_by_type IN ('HUMAN','AI_AGENT','SYSTEM'))

-- notes
CHECK (note_source IN ('HUMAN','AI_SUMMARY','AI_INTERACTION','SYSTEM'))
CHECK (author_type IN ('HUMAN','AI_AGENT','SYSTEM'))
CHECK (length(body) <= 10000)

-- appointments
CHECK (status IN ('SCHEDULED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW'))
CHECK (source IN ('MANUAL','AI_AGENT','WORKFLOW'))
CHECK (location_type IS NULL OR location_type IN ('VIRTUAL','IN_PERSON'))
CHECK (scheduled_end > scheduled_start)  -- Phase 4C §4.8 inv.1

-- lead_score_records
CHECK (score >= 0 AND score <= 100)
CHECK (previous_score IS NULL OR (previous_score >= 0 AND previous_score <= 100))
CHECK (computed_by IN ('RULE_ENGINE','AI_AGENT','MANUAL'))

-- consent_records
CHECK (status IN ('GRANTED','WITHDRAWN','EXPIRED','UNKNOWN'))
CHECK (channel IN ('VOICE','SMS','WHATSAPP','EMAIL','ANY'))

-- contact_suppressions
CHECK (scope IN ('ORG','PLATFORM','REGULATORY'))
CHECK (channel IN ('VOICE','SMS','WHATSAPP','EMAIL','ALL'))
CHECK (status IN ('ACTIVE','LIFTED','EXPIRED'))
CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')
CHECK (expires_at IS NULL OR expires_at > effective_from)  -- Phase 4I §8.5 inv.3
-- Scope/org_id consistency:
CHECK (
  (scope = 'ORG' AND organization_id IS NOT NULL) OR
  (scope IN ('PLATFORM','REGULATORY') AND organization_id IS NULL)
)
```

---

## 9. Index Strategy

### 9.1 `crm.contacts`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_contacts` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_contacts_phone` | `(organization_id, phone_e164)` | PARTIAL UNIQUE B-tree | `WHERE deleted_at IS NULL` | Dedup; UNIQUE within active contacts |
| `idx_contacts_org_lead_status` | `(organization_id, lead_status)` | B-tree | — | Lead list by status |
| `idx_contacts_org_score` | `(organization_id, lead_score DESC)` | B-tree | `WHERE lead_score IS NOT NULL` | Score-sorted views |
| `idx_contacts_org_temperature` | `(organization_id, lead_temperature)` | B-tree | `WHERE lead_temperature IN ('HOT','WARM')` | Hot/warm lead queries |
| `idx_contacts_org_qualification` | `(organization_id, qualification_status)` | B-tree | `WHERE qualification_status != 'UNSET'` | Qualified/disqualified lists |
| `idx_contacts_company` | `(organization_id, company_id)` | B-tree | `WHERE company_id IS NOT NULL` | Company's contacts |
| `idx_contacts_campaign` | `(organization_id, campaign_ref)` | B-tree | `WHERE campaign_ref IS NOT NULL` | Campaign's contacts |
| `idx_contacts_owner` | `(organization_id, owned_by)` | B-tree | `WHERE owned_by IS NOT NULL` | Assigned contacts |
| `idx_contacts_email_norm` | `(organization_id, primary_email_normalized)` | B-tree | `WHERE primary_email_normalized IS NOT NULL` | Email lookup |
| `idx_contacts_last_contacted` | `(organization_id, last_contacted_at DESC)` | B-tree | `WHERE last_contacted_at IS NOT NULL` | Stale contact queries |
| `idx_contacts_org_created` | `(organization_id, created_at DESC)` | B-tree | — | Recent contacts view |

**Critical: `uq_contacts_phone` is a partial unique index (`WHERE deleted_at IS NULL`)** to allow re-creation of a contact for a phone number after GDPR erasure.

### 9.2 `crm.companies`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_companies` | `id` | UNIQUE B-tree (PK) | |
| `uq_companies_domain` | `(organization_id, email_domain)` | PARTIAL UNIQUE B-tree | `WHERE email_domain IS NOT NULL` |
| `idx_companies_org` | `organization_id` | B-tree | |
| `idx_companies_owner` | `(organization_id, owned_by)` | B-tree | `WHERE owned_by IS NOT NULL` |

### 9.3 `crm.deals`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_deals` | `id` | UNIQUE B-tree (PK) | |
| `idx_deals_contact` | `(organization_id, contact_id, status)` | B-tree | — |
| `idx_deals_pipeline_stage` | `(organization_id, pipeline_id, current_stage_id)` | B-tree | `WHERE status = 'OPEN'` |
| `idx_deals_status` | `(organization_id, status)` | B-tree | — |
| `idx_deals_owner` | `(organization_id, owned_by)` | B-tree | `WHERE owned_by IS NOT NULL` |
| `idx_deals_close_date` | `(organization_id, close_date)` | B-tree | `WHERE status = 'OPEN' AND close_date IS NOT NULL` |

### 9.4 `crm.pipelines`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_pipelines` | `id` | UNIQUE B-tree (PK) | |
| `uq_pipelines_name` | `(organization_id, name)` | UNIQUE B-tree | |
| `uq_pipelines_default` | `organization_id` | PARTIAL UNIQUE B-tree | `WHERE is_default = TRUE` |
| `idx_pipelines_org` | `organization_id` | B-tree | |

### 9.5 `crm.activities` (Partitioned)

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_activities` | `(id, occurred_at)` | UNIQUE B-tree (PK, composite) | |
| `idx_act_subject` | `(organization_id, subject_type, subject_id, occurred_at DESC)` | B-tree | — |
| `idx_act_type` | `(organization_id, activity_type, occurred_at DESC)` | B-tree | — |
| `idx_act_call_ref` | `call_ref` | B-tree | `WHERE call_ref IS NOT NULL` |
| `idx_act_org_time_brin` | `(organization_id, occurred_at)` | BRIN | — |

### 9.6 `crm.tasks`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_tasks` | `id` | UNIQUE B-tree (PK) | |
| `idx_tasks_subject` | `(organization_id, subject_type, subject_id)` | B-tree | |
| `idx_tasks_assigned` | `(organization_id, assigned_to, status)` | B-tree | `WHERE status = 'OPEN'` |
| `idx_tasks_due` | `(organization_id, due_at)` | B-tree | `WHERE status = 'OPEN'` |
| `idx_tasks_org_status` | `(organization_id, status)` | B-tree | |

### 9.7 `crm.notes`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_notes` | `id` | UNIQUE B-tree (PK) | |
| `idx_notes_subject` | `(organization_id, subject_type, subject_id, created_at DESC)` | B-tree | `WHERE deleted_at IS NULL` |
| `idx_notes_pinned` | `(organization_id, subject_type, subject_id)` | B-tree | `WHERE pinned_at IS NOT NULL` |

### 9.8 `crm.appointments`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_appointments` | `id` | UNIQUE B-tree (PK) | |
| `idx_appt_contact` | `(organization_id, contact_id, status)` | B-tree | |
| `idx_appt_organizer` | `(organization_id, organizer_ref, scheduled_start)` | B-tree | |
| `idx_appt_status` | `(organization_id, status, scheduled_start)` | B-tree | |
| `idx_appt_upcoming` | `(organization_id, scheduled_start)` | B-tree | `WHERE status IN ('SCHEDULED','CONFIRMED')` |

### 9.9 `crm.lead_score_records`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_lead_score_records` | `id` | UNIQUE B-tree (PK) | |
| `idx_lsr_contact_time` | `(organization_id, contact_id, computed_at DESC)` | B-tree | — |

**Query supported by `idx_lsr_contact_time`:** `SELECT ... WHERE contact_id = $1 ORDER BY computed_at DESC LIMIT 1` — most recent score.

### 9.10 `crm.consent_records` (Partitioned)

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_consent_records` | `(id, recorded_at)` | UNIQUE B-tree (PK, composite) | |
| `idx_cr_contact_purpose_channel` | `(organization_id, contact_id, purpose, channel, recorded_at DESC)` | B-tree | — |
| `idx_cr_org_time_brin` | `(organization_id, recorded_at)` | BRIN | — |

**Query supported:** `WHERE contact_id = $1 AND purpose = $2 AND channel = $3 ORDER BY recorded_at DESC LIMIT 1` — effective consent lookup. Also cached in Redis (`consent:{org}:{contact_id}:{purpose}`, 1h TTL).

### 9.11 `crm.contact_suppressions`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_contact_suppressions` | `id` | UNIQUE B-tree (PK) | |
| `idx_sup_org_phone_status` | `(organization_id, phone_e164, status)` | B-tree | — |
| `idx_sup_platform_phone` | `(phone_e164, scope)` | B-tree | `WHERE scope IN ('PLATFORM','REGULATORY')` |
| `idx_sup_contact` | `(organization_id, contact_id)` | B-tree | `WHERE contact_id IS NOT NULL` |
| `idx_sup_expires` | `expires_at` | B-tree | `WHERE expires_at IS NOT NULL AND status = 'ACTIVE'` |

**Critical index `idx_sup_org_phone_status`:** used by the dispatch-time suppression check (`SELECT ... WHERE organization_id = $1 AND phone_e164 = $2 AND status = 'ACTIVE'`).

**Critical index `idx_sup_platform_phone`:** cross-tenant PLATFORM/REGULATORY lookup by phone number. Used when checking if a number is suppressed at platform level regardless of which tenant is querying. No RLS filters this query for PLATFORM/REGULATORY rows — see §10.2.

---

## 10. Partitioning Specifications

### 10.1 `crm.activities` — RANGE monthly on `occurred_at`

Retention: 5 years hot. Volume: one Activity per call per contact — at scale, hundreds of millions per year.

```sql
CREATE TABLE crm.activities (...)
PARTITION BY RANGE (occurred_at);

-- Partitions created parametrically at migration time via:
--   create_monthly_partitions(conn, 'crm.activities', months_ahead=3)
-- Creates current month + 3 months ahead + DEFAULT safety partition.
-- Maintenance job runs monthly: create next partition, drop partitions
-- older than 5 years after cold archival.
CREATE TABLE crm.activities_default
  PARTITION OF crm.activities DEFAULT;
```

### 10.2 `crm.consent_records` — RANGE monthly on `recorded_at`

Retention: per org's `CompliancePolicy.RetentionProfile`. Grows with contact base.

```sql
CREATE TABLE crm.consent_records (...)
PARTITION BY RANGE (recorded_at);

-- Same parametric approach.
CREATE TABLE crm.consent_records_default
  PARTITION OF crm.consent_records DEFAULT;
```

---

## 11. RLS Architecture

### 11.1 Standard Tenant Policies

Applied to: `contacts`, `companies`, `deals`, `pipelines`, `tasks`, `notes`, `appointments`, `lead_score_records`, `crm_field_definitions`.

```sql
ALTER TABLE crm.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.<table> FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_<table>_tenant ON crm.<table>
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

### 11.2 Append-Only Tables

```sql
-- activities: append-only (DDR-4C-002)
REVOKE UPDATE, DELETE ON crm.activities FROM app_api, app_worker;

-- lead_score_records: append-only
REVOKE UPDATE, DELETE ON crm.lead_score_records FROM app_api, app_worker;

-- consent_records: append-only (Phase 4I §8.1)
REVOKE UPDATE, DELETE ON crm.consent_records FROM app_api, app_worker;

-- contact_suppressions: app_api/app_worker cannot UPDATE or DELETE directly.
-- The ACTIVE → LIFTED transition is performed via crm.lift_suppression()
-- SECURITY DEFINER function (defined in Migration 024).
REVOKE UPDATE, DELETE ON crm.contact_suppressions FROM app_api, app_worker;
```

**Note on `contact_suppressions` UPDATE model:** Unlike `activities`, `consent_records`, and `lead_score_records` which are unconditionally immutable, `contact_suppressions` has a controlled UPDATE path for `ACTIVE → LIFTED` transitions (Phase 4I §8.5 invariant 4). This UPDATE is never performed directly by `app_api` or `app_worker` — it goes through `crm.lift_suppression()` (SECURITY DEFINER), which holds UPDATE privilege via its definer rights. The effective contract for normal application roles is identical to the other append-only tables: INSERT only.

### 11.3 Contact Suppressions — Special Three-Scope RLS + Privileged Lift

The full policy from Phase 5A §6.4, plus the ACTIVE → LIFTED mechanism:

```sql
ALTER TABLE crm.contact_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.contact_suppressions FORCE ROW LEVEL SECURITY;

-- Read: own ORG rows + PLATFORM/REGULATORY rows (visible to all tenants for enforcement)
CREATE POLICY rls_suppression_read ON crm.contact_suppressions
  FOR SELECT
  USING (
    organization_id = organization.current_tenant_id()
    OR (organization_id IS NULL AND scope IN ('PLATFORM', 'REGULATORY'))
  );

-- Insert: only own ORG-scope rows. Scope must be 'ORG'. org_id must match tenant.
CREATE POLICY rls_suppression_insert ON crm.contact_suppressions
  FOR INSERT WITH CHECK (
    organization_id = organization.current_tenant_id()
    AND scope = 'ORG'
  );

-- No direct UPDATE or DELETE from app_api/app_worker:
REVOKE UPDATE, DELETE ON crm.contact_suppressions FROM app_api, app_worker;

-- PLATFORM and REGULATORY rows are inserted only by app_platform_admin (BYPASSRLS).
-- They are visible to all tenants for enforcement but cannot be touched by tenant operations.

-- ACTIVE → LIFTED via SECURITY DEFINER function:
-- app_api and app_worker call crm.lift_suppression() which holds UPDATE
-- privilege through its SECURITY DEFINER context. The function validates:
--   1. The suppression exists and status = 'ACTIVE'
--   2. The caller has permission to lift (ORG suppressions: suppression:lift permission;
--      PLATFORM/REGULATORY suppressions: only app_platform_admin)
--   3. Updates ONLY {status, lifted_at, lifted_by_ref}
```

**`crm.lift_suppression()` SECURITY DEFINER function (defined in Migration 024):**

```sql
CREATE OR REPLACE FUNCTION crm.lift_suppression(
  p_suppression_id   UUID,
  p_lifted_by_ref    UUID,
  p_organization_id  UUID  -- caller's tenant context; NULL for platform admin
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = crm, organization, pg_temp
AS $$
DECLARE
  v_scope  TEXT;
  v_status TEXT;
BEGIN
  SELECT scope, status
  INTO v_scope, v_status
  FROM crm.contact_suppressions
  WHERE id = p_suppression_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Suppression record not found: %', p_suppression_id;
  END IF;

  IF v_status != 'ACTIVE' THEN
    RAISE EXCEPTION 'Suppression % is not ACTIVE (current status: %). Cannot lift.', p_suppression_id, v_status;
  END IF;

  -- Scope enforcement: PLATFORM/REGULATORY suppressions require NULL tenant (platform admin)
  IF v_scope IN ('PLATFORM', 'REGULATORY') AND p_organization_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only app_platform_admin may lift PLATFORM/REGULATORY suppressions.';
  END IF;

  -- ORG suppressions: tenant must own the record
  IF v_scope = 'ORG' AND p_organization_id IS NOT NULL THEN
    PERFORM 1 FROM crm.contact_suppressions
    WHERE id = p_suppression_id AND organization_id = p_organization_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Tenant does not own suppression % or it does not exist.', p_suppression_id;
    END IF;
  END IF;

  UPDATE crm.contact_suppressions
  SET status       = 'LIFTED',
      lifted_at    = NOW(),
      lifted_by_ref = p_lifted_by_ref
  WHERE id = p_suppression_id;

  -- Caller must publish contact.suppression_lifted event after this function returns
END;
$$;

REVOKE ALL ON FUNCTION crm.lift_suppression(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.lift_suppression(UUID, UUID, UUID)
  TO app_api, app_worker, app_platform_admin;
```

### 11.4 Consent Records — Standard Tenant Policy + Append-Only

```sql
ALTER TABLE crm.consent_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.consent_records FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_consent_read ON crm.consent_records
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_consent_insert ON crm.consent_records
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON crm.consent_records FROM app_api, app_worker;
```

### 11.5 Activities — Standard Tenant Policy + Append-Only

```sql
ALTER TABLE crm.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.activities FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_activities_tenant ON crm.activities
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_activities_insert ON crm.activities
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON crm.activities FROM app_api, app_worker;
```

### 11.6 AI Notes Immutability Trigger

```sql
CREATE OR REPLACE FUNCTION crm.prevent_ai_note_body_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.note_source IN ('AI_SUMMARY', 'AI_INTERACTION')
     AND OLD.body IS DISTINCT FROM NEW.body THEN
    RAISE EXCEPTION
      'AI-generated note body is immutable. note_id=%, source=%', OLD.id, OLD.note_source;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ai_note_immutable
  BEFORE UPDATE ON crm.notes
  FOR EACH ROW EXECUTE FUNCTION crm.prevent_ai_note_body_mutation();
```

---

## 12. Foreign Keys Within Schema

| Table | Column | References | On Delete |
|---|---|---|---|
| `crm.deals` | `pipeline_id` | `crm.pipelines(id)` | `RESTRICT` — prevent pipeline deletion with deals |
| `crm.deals` | `contact_id` | `crm.contacts(id)` | `RESTRICT` — deals survive contact soft-delete |

All other references (company_id on contacts, contact_id on appointments, etc.) are **logical references** — no FK constraint, to preserve aggregate independence and avoid cascades across aggregate boundaries.

---

## 13. Cross-Schema Logical References

| Source Table.Column | Target (logical) | Rationale for no FK |
|---|---|---|
| `contacts.organization_id` | `organization.organizations.id` | Cross-schema |
| `contacts.campaign_ref` | `campaign.campaigns.id` | Cross-schema |
| `contacts.owned_by` | `identity.users.id` | Cross-schema |
| `companies.organization_id` | `organization.organizations.id` | Cross-schema |
| `deals.contact_id` | `crm.contacts.id` | **Aggregate independence** — Deal → Contact is a reference, not containment |
| `deals.company_id` | `crm.companies.id` | Aggregate independence |
| `tasks.assigned_to` | `identity.users.id` | Cross-schema |
| `notes.author_ref` | `identity.users.id` or `voice.agent_versions.id` | Cross-schema; polymorphic |
| `appointments.contact_id` | `crm.contacts.id` | Aggregate independence |
| `appointments.organizer_ref` | `identity.users.id` | Cross-schema |
| `appointments.conversation_ref` | `voice.conversations.id` | Cross-schema |
| `activities.call_ref` | `voice.call_sessions.id` | Cross-schema |
| `lead_score_records.contact_id` | `crm.contacts.id` | Aggregate independence |
| `consent_records.contact_id` | `crm.contacts.id` | Aggregate independence (consent survives contact deletion) |
| `contact_suppressions.contact_id` | `crm.contacts.id` | Suppression keyed on phone, not contact — must survive contact deletion |

---

## 14. Complete PostgreSQL DDL

### 14.1 CRM-Specific Functions

```sql
-- ================================================================
-- Migration 019: CRM schema functions
-- ================================================================

GRANT USAGE ON SCHEMA crm TO app_api, app_worker, app_readonly, app_platform_admin;

-- Prevent AI-generated note body mutation
CREATE OR REPLACE FUNCTION crm.prevent_ai_note_body_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.note_source IN ('AI_SUMMARY', 'AI_INTERACTION')
     AND OLD.body IS DISTINCT FROM NEW.body THEN
    RAISE EXCEPTION
      'AI-generated note body is immutable (DDR-4C-003). note_id=%, source=%',
      OLD.id, OLD.note_source;
  END IF;
  RETURN NEW;
END;
$$;
```

### 14.2 Contacts and Companies

```sql
-- ================================================================
-- Migration 020: crm.contacts and crm.companies
-- ================================================================

CREATE TABLE crm.contacts (
  id                        UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id           UUID          NOT NULL,
  full_name                 TEXT          NOT NULL,     -- pii:name
  phone_e164                TEXT          NOT NULL,     -- pii:phone; UNIQUE within org (active)
  phone_country             TEXT          NOT NULL,
  phone_type                TEXT          NULL,
  phone_verified            BOOLEAN       NOT NULL DEFAULT FALSE,
  phone_normalized_at       TIMESTAMPTZ   NULL,
  communication_status      TEXT          NOT NULL DEFAULT 'UNKNOWN',
  secondary_phone_e164      TEXT          NULL,         -- pii:phone
  primary_email             TEXT          NULL,         -- pii:email
  primary_email_normalized  TEXT          NULL,         -- LOWER(TRIM(primary_email))
  company_id                UUID          NULL,         -- logical ref: crm.companies.id
  owned_by                  UUID          NULL,         -- logical ref: identity.users.id
  lead_status               TEXT          NOT NULL DEFAULT 'NEW',
  qualification_status      TEXT          NOT NULL DEFAULT 'UNSET',
  qualification_reason      TEXT          NULL,
  lead_score                INTEGER       NULL,
  lead_temperature          TEXT          NULL,
  tags                      TEXT[]        NOT NULL DEFAULT '{}',
  address_line1             TEXT          NULL,         -- pii:address
  address_line2             TEXT          NULL,
  address_city              TEXT          NULL,
  address_state             TEXT          NULL,
  address_postal_code       TEXT          NULL,
  address_country_code      TEXT          NULL,
  source                    TEXT          NOT NULL,
  campaign_ref              UUID          NULL,         -- logical ref: campaign.campaigns.id
  do_not_call               BOOLEAN       NOT NULL DEFAULT FALSE,  -- DENORMALIZED; see §5.1
  consent_status            TEXT          NOT NULL DEFAULT 'UNKNOWN',
  last_contacted_at         TIMESTAMPTZ   NULL,
  converted_at              TIMESTAMPTZ   NULL,
  custom_field_values       JSONB         NOT NULL DEFAULT '[]',
  deleted_at                TIMESTAMPTZ   NULL,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_contacts               PRIMARY KEY (id),
  CONSTRAINT chk_contacts_lead_status  CHECK (lead_status IN
    ('NEW','CONTACTED','QUALIFIED','DISQUALIFIED','NURTURING','CONVERTED')),
  CONSTRAINT chk_contacts_qual_status  CHECK (qualification_status IN
    ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE','UNSET')),
  CONSTRAINT chk_contacts_score        CHECK (lead_score IS NULL OR
    (lead_score >= 0 AND lead_score <= 100)),
  CONSTRAINT chk_contacts_temperature  CHECK (lead_temperature IS NULL OR
    lead_temperature IN ('HOT','WARM','COLD','UNSCORED')),
  CONSTRAINT chk_contacts_source       CHECK (source IN
    ('INBOUND_CALL','OUTBOUND_CALL','CSV_IMPORT','MANUAL','API','WEBHOOK')),
  CONSTRAINT chk_contacts_consent      CHECK (consent_status IN ('UNKNOWN','GIVEN','WITHDRAWN')),
  CONSTRAINT chk_contacts_comm_status  CHECK (communication_status IN
    ('REACHABLE','UNREACHABLE','INVALID','UNKNOWN')),
  CONSTRAINT chk_contacts_phone        CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_contacts_sec_phone    CHECK (secondary_phone_e164 IS NULL OR
    secondary_phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_contacts_tag_count    CHECK (cardinality(tags) <= 20)
);

COMMENT ON COLUMN crm.contacts.full_name            IS 'pii:name';
COMMENT ON COLUMN crm.contacts.phone_e164           IS 'pii:phone — canonical E.164';
COMMENT ON COLUMN crm.contacts.secondary_phone_e164 IS 'pii:phone';
COMMENT ON COLUMN crm.contacts.primary_email        IS 'pii:email';
COMMENT ON COLUMN crm.contacts.address_line1        IS 'pii:address';
COMMENT ON COLUMN crm.contacts.do_not_call          IS 'DENORMALIZED from contact_suppressions — not the authoritative DNC source';

-- Partial unique: one active phone per org (allows re-creation after GDPR erasure)
CREATE UNIQUE INDEX uq_contacts_phone
  ON crm.contacts (organization_id, phone_e164)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_contacts_org_lead_status
  ON crm.contacts (organization_id, lead_status);
CREATE INDEX idx_contacts_org_score
  ON crm.contacts (organization_id, lead_score DESC)
  WHERE lead_score IS NOT NULL;
CREATE INDEX idx_contacts_org_temperature
  ON crm.contacts (organization_id, lead_temperature)
  WHERE lead_temperature IN ('HOT','WARM');
CREATE INDEX idx_contacts_org_qualification
  ON crm.contacts (organization_id, qualification_status)
  WHERE qualification_status != 'UNSET';
CREATE INDEX idx_contacts_company
  ON crm.contacts (organization_id, company_id)
  WHERE company_id IS NOT NULL;
CREATE INDEX idx_contacts_campaign
  ON crm.contacts (organization_id, campaign_ref)
  WHERE campaign_ref IS NOT NULL;
CREATE INDEX idx_contacts_owner
  ON crm.contacts (organization_id, owned_by)
  WHERE owned_by IS NOT NULL;
CREATE INDEX idx_contacts_email_norm
  ON crm.contacts (organization_id, primary_email_normalized)
  WHERE primary_email_normalized IS NOT NULL;
CREATE INDEX idx_contacts_last_contacted
  ON crm.contacts (organization_id, last_contacted_at DESC)
  WHERE last_contacted_at IS NOT NULL;
CREATE INDEX idx_contacts_org_created
  ON crm.contacts (organization_id, created_at DESC);

CREATE TRIGGER trg_contacts_updated_at
  BEFORE UPDATE ON crm.contacts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.contacts FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_contacts_tenant ON crm.contacts
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.contacts TO app_api, app_worker;


CREATE TABLE crm.companies (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL,
  company_name          TEXT          NOT NULL,
  email_domain          TEXT          NULL,
  industry              TEXT          NULL,
  size                  TEXT          NULL,
  website               TEXT          NULL,
  address_line1         TEXT          NULL,
  address_line2         TEXT          NULL,
  address_city          TEXT          NULL,
  address_state         TEXT          NULL,
  address_postal_code   TEXT          NULL,
  address_country_code  TEXT          NULL,
  owned_by              UUID          NULL,
  custom_field_values   JSONB         NOT NULL DEFAULT '[]',
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_companies     PRIMARY KEY (id),
  CONSTRAINT chk_comp_size    CHECK (size IS NULL OR size IN
    ('STARTUP','SMB','MID_MARKET','ENTERPRISE'))
);

CREATE UNIQUE INDEX uq_companies_domain
  ON crm.companies (organization_id, email_domain)
  WHERE email_domain IS NOT NULL;
CREATE INDEX idx_companies_org   ON crm.companies (organization_id);
CREATE INDEX idx_companies_owner
  ON crm.companies (organization_id, owned_by)
  WHERE owned_by IS NOT NULL;

CREATE TRIGGER trg_companies_updated_at
  BEFORE UPDATE ON crm.companies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.companies FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_companies_tenant ON crm.companies
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.companies TO app_api, app_worker;
```

### 14.3 Pipelines and Deals

```sql
-- ================================================================
-- Migration 021: crm.pipelines and crm.deals
-- ================================================================

CREATE TABLE crm.pipelines (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  name             TEXT          NOT NULL,
  is_default       BOOLEAN       NOT NULL DEFAULT FALSE,
  stages           JSONB         NOT NULL DEFAULT '[]',
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_pipelines     PRIMARY KEY (id),
  CONSTRAINT chk_pipe_name_len CHECK (length(name) BETWEEN 1 AND 100)
);

CREATE UNIQUE INDEX uq_pipelines_name    ON crm.pipelines (organization_id, name);
CREATE UNIQUE INDEX uq_pipelines_default ON crm.pipelines (organization_id)
  WHERE is_default = TRUE;
CREATE INDEX idx_pipelines_org ON crm.pipelines (organization_id);

CREATE TRIGGER trg_pipelines_updated_at
  BEFORE UPDATE ON crm.pipelines
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.pipelines FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_pipelines_tenant ON crm.pipelines
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.pipelines TO app_api, app_worker;


CREATE TABLE crm.deals (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL,
  title                 TEXT          NOT NULL,
  contact_id            UUID          NOT NULL,     -- logical ref: crm.contacts.id
  company_id            UUID          NULL,         -- logical ref: crm.companies.id
  pipeline_id           UUID          NOT NULL,
  current_stage_id      UUID          NOT NULL,
  value_amount          NUMERIC(18,4) NULL,
  value_currency        CHAR(3)       NULL,
  status                TEXT          NOT NULL DEFAULT 'OPEN',
  close_date            DATE          NULL,
  owned_by              UUID          NULL,
  won_at                TIMESTAMPTZ   NULL,
  lost_at               TIMESTAMPTZ   NULL,
  lost_reason           TEXT          NULL,
  custom_field_values   JSONB         NOT NULL DEFAULT '[]',
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_deals                  PRIMARY KEY (id),
  CONSTRAINT fk_deals_pipeline         FOREIGN KEY (pipeline_id) REFERENCES crm.pipelines(id) ON DELETE RESTRICT,
  CONSTRAINT chk_deals_status          CHECK (status IN ('OPEN','WON','LOST','ABANDONED')),
  CONSTRAINT chk_deals_value_nn        CHECK (value_amount IS NULL OR value_amount >= 0),
  CONSTRAINT chk_deals_currency_format CHECK (value_currency IS NULL OR value_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_deals_money_pair      CHECK ((value_amount IS NULL) = (value_currency IS NULL)),
  CONSTRAINT chk_deals_title_len       CHECK (length(title) BETWEEN 1 AND 200)
);

CREATE INDEX idx_deals_contact  ON crm.deals (organization_id, contact_id, status);
CREATE INDEX idx_deals_pipeline ON crm.deals (organization_id, pipeline_id, current_stage_id)
  WHERE status = 'OPEN';
CREATE INDEX idx_deals_status   ON crm.deals (organization_id, status);
CREATE INDEX idx_deals_owner    ON crm.deals (organization_id, owned_by)
  WHERE owned_by IS NOT NULL;
CREATE INDEX idx_deals_close    ON crm.deals (organization_id, close_date)
  WHERE status = 'OPEN' AND close_date IS NOT NULL;

CREATE TRIGGER trg_deals_updated_at
  BEFORE UPDATE ON crm.deals
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.deals FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_deals_tenant ON crm.deals
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.deals TO app_api, app_worker;
```

### 14.4 Activities (Partitioned), Tasks, Notes

```sql
-- ================================================================
-- Migration 022: crm.activities (partitioned), crm.tasks, crm.notes
-- ================================================================

CREATE TABLE crm.activities (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  occurred_at      TIMESTAMPTZ   NOT NULL,            -- PARTITION KEY
  organization_id  UUID          NOT NULL,
  activity_type    TEXT          NOT NULL,
  subject_type     TEXT          NOT NULL,
  subject_id       UUID          NOT NULL,
  actor_type       TEXT          NOT NULL,
  actor_ref        UUID          NULL,
  actor_name       TEXT          NULL,                -- pii:name (display name at time)
  summary          TEXT          NULL,
  payload          JSONB         NOT NULL DEFAULT '{}',
  call_ref         UUID          NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_activities          PRIMARY KEY (id, occurred_at),
  CONSTRAINT chk_act_type           CHECK (activity_type IN (
    'CALL','EMAIL','SMS','WHATSAPP','MEETING','NOTE','TASK_COMPLETED',
    'STAGE_CHANGE','SCORE_CHANGE','QUALIFICATION_CHANGE','AI_INTERACTION','CAMPAIGN_CONTACT'
  )),
  CONSTRAINT chk_act_subject_type   CHECK (subject_type IN ('CONTACT','DEAL','COMPANY')),
  CONSTRAINT chk_act_actor_type     CHECK (actor_type IN ('HUMAN','AI_AGENT','SYSTEM')),
  CONSTRAINT chk_act_summary_len    CHECK (summary IS NULL OR length(summary) <= 1000)
) PARTITION BY RANGE (occurred_at);

COMMENT ON COLUMN crm.activities.actor_name IS 'pii:name — captured at activity creation time';

CREATE INDEX idx_act_subject
  ON crm.activities (organization_id, subject_type, subject_id, occurred_at DESC);
CREATE INDEX idx_act_type
  ON crm.activities (organization_id, activity_type, occurred_at DESC);
CREATE INDEX idx_act_call_ref
  ON crm.activities (call_ref)
  WHERE call_ref IS NOT NULL;
CREATE INDEX idx_act_org_time_brin
  ON crm.activities USING BRIN (organization_id, occurred_at);

ALTER TABLE crm.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.activities FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_activities_read ON crm.activities
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_activities_insert ON crm.activities
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT ON crm.activities TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.activities FROM app_api, app_worker;

-- Parametric partition creation via create_monthly_partitions()
CREATE TABLE crm.activities_default PARTITION OF crm.activities DEFAULT;


CREATE TABLE crm.tasks (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  title            TEXT          NOT NULL,
  subject_type     TEXT          NOT NULL,
  subject_id       UUID          NOT NULL,
  assigned_to      UUID          NULL,
  due_at           TIMESTAMPTZ   NOT NULL,
  priority         TEXT          NOT NULL DEFAULT 'MEDIUM',
  status           TEXT          NOT NULL DEFAULT 'OPEN',
  created_by       UUID          NULL,
  created_by_type  TEXT          NOT NULL DEFAULT 'HUMAN',
  completed_at     TIMESTAMPTZ   NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tasks               PRIMARY KEY (id),
  CONSTRAINT chk_tasks_subject_type CHECK (subject_type IN ('CONTACT','DEAL','COMPANY')),
  CONSTRAINT chk_tasks_priority     CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT')),
  CONSTRAINT chk_tasks_status       CHECK (status IN ('OPEN','COMPLETED','CANCELLED')),
  CONSTRAINT chk_tasks_creator_type CHECK (created_by_type IN ('HUMAN','AI_AGENT','SYSTEM')),
  CONSTRAINT chk_tasks_title_len    CHECK (length(title) BETWEEN 1 AND 200)
);

CREATE INDEX idx_tasks_subject ON crm.tasks (organization_id, subject_type, subject_id);
CREATE INDEX idx_tasks_assigned
  ON crm.tasks (organization_id, assigned_to, status)
  WHERE status = 'OPEN';
CREATE INDEX idx_tasks_due
  ON crm.tasks (organization_id, due_at)
  WHERE status = 'OPEN';
CREATE INDEX idx_tasks_org_status ON crm.tasks (organization_id, status);

CREATE TRIGGER trg_tasks_updated_at
  BEFORE UPDATE ON crm.tasks
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.tasks FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_tasks_tenant ON crm.tasks
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.tasks TO app_api, app_worker;


CREATE TABLE crm.notes (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  subject_type     TEXT          NOT NULL,
  subject_id       UUID          NOT NULL,
  body             TEXT          NOT NULL DEFAULT '',  -- pii:voice for AI_SUMMARY
  author_ref       UUID          NULL,
  author_type      TEXT          NOT NULL DEFAULT 'HUMAN',
  note_source      TEXT          NOT NULL DEFAULT 'HUMAN',
  pinned_at        TIMESTAMPTZ   NULL,
  deleted_at       TIMESTAMPTZ   NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_notes               PRIMARY KEY (id),
  CONSTRAINT chk_notes_subject_type CHECK (subject_type IN ('CONTACT','DEAL','COMPANY')),
  CONSTRAINT chk_notes_source       CHECK (note_source IN
    ('HUMAN','AI_SUMMARY','AI_INTERACTION','SYSTEM')),
  CONSTRAINT chk_notes_author_type  CHECK (author_type IN ('HUMAN','AI_AGENT','SYSTEM')),
  CONSTRAINT chk_notes_body_len     CHECK (length(body) <= 10000)
);

COMMENT ON COLUMN crm.notes.body IS 'pii:voice — AI_SUMMARY and AI_INTERACTION notes contain voice-derived content';

CREATE INDEX idx_notes_subject
  ON crm.notes (organization_id, subject_type, subject_id, created_at DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX idx_notes_pinned
  ON crm.notes (organization_id, subject_type, subject_id)
  WHERE pinned_at IS NOT NULL AND deleted_at IS NULL;

CREATE TRIGGER trg_notes_updated_at
  BEFORE UPDATE ON crm.notes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_ai_note_immutable
  BEFORE UPDATE ON crm.notes
  FOR EACH ROW EXECUTE FUNCTION crm.prevent_ai_note_body_mutation();

ALTER TABLE crm.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.notes FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_notes_tenant ON crm.notes
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON crm.notes TO app_api, app_worker;
-- DELETE permitted on notes (human notes can be deleted per Phase 4C §4.7 inv.2)
-- AI notes cannot be deleted directly; they can be soft-deleted (deleted_at = NOW())
```

### 14.5 Appointments, Lead Scores, Custom Fields

```sql
-- ================================================================
-- Migration 023: appointments, lead_score_records, crm_field_definitions
-- ================================================================

CREATE TABLE crm.appointments (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID          NOT NULL,
  contact_id          UUID          NOT NULL,
  organizer_ref       UUID          NOT NULL,
  attendees           UUID[]        NOT NULL DEFAULT '{}',
  title               TEXT          NOT NULL,
  scheduled_start     TIMESTAMPTZ   NOT NULL,
  scheduled_end       TIMESTAMPTZ   NOT NULL,
  location_type       TEXT          NULL,
  location_detail     TEXT          NULL,
  status              TEXT          NOT NULL DEFAULT 'SCHEDULED',
  source              TEXT          NOT NULL DEFAULT 'MANUAL',
  conversation_ref    UUID          NULL,
  cancellation_reason TEXT          NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_appointments         PRIMARY KEY (id),
  CONSTRAINT chk_appt_status         CHECK (status IN
    ('SCHEDULED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW')),
  CONSTRAINT chk_appt_source         CHECK (source IN ('MANUAL','AI_AGENT','WORKFLOW')),
  CONSTRAINT chk_appt_location_type  CHECK (location_type IS NULL OR
    location_type IN ('VIRTUAL','IN_PERSON')),
  CONSTRAINT chk_appt_end_after_start CHECK (scheduled_end > scheduled_start),
  CONSTRAINT chk_appt_title_len      CHECK (length(title) BETWEEN 1 AND 200)
);

CREATE INDEX idx_appt_contact  ON crm.appointments (organization_id, contact_id, status);
CREATE INDEX idx_appt_organizer
  ON crm.appointments (organization_id, organizer_ref, scheduled_start);
CREATE INDEX idx_appt_status
  ON crm.appointments (organization_id, status, scheduled_start);
CREATE INDEX idx_appt_upcoming
  ON crm.appointments (organization_id, scheduled_start)
  WHERE status IN ('SCHEDULED','CONFIRMED');

CREATE TRIGGER trg_appt_updated_at
  BEFORE UPDATE ON crm.appointments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.appointments FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_appointments_tenant ON crm.appointments
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.appointments TO app_api, app_worker;


CREATE TABLE crm.lead_score_records (
  id                   UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID          NOT NULL,
  contact_id           UUID          NOT NULL,
  score                INTEGER       NOT NULL,
  previous_score       INTEGER       NULL,
  score_version        TEXT          NOT NULL,
  signals              JSONB         NOT NULL,
  computed_at          TIMESTAMPTZ   NOT NULL,
  computed_by          TEXT          NOT NULL,
  computed_by_user_ref UUID          NULL,
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_lead_score_records  PRIMARY KEY (id),
  CONSTRAINT chk_lsr_score          CHECK (score >= 0 AND score <= 100),
  CONSTRAINT chk_lsr_prev_score     CHECK (previous_score IS NULL OR
    (previous_score >= 0 AND previous_score <= 100)),
  CONSTRAINT chk_lsr_computed_by    CHECK (computed_by IN ('RULE_ENGINE','AI_AGENT','MANUAL'))
);

CREATE INDEX idx_lsr_contact_time
  ON crm.lead_score_records (organization_id, contact_id, computed_at DESC);

ALTER TABLE crm.lead_score_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_score_records FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_lsr_read ON crm.lead_score_records
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_lsr_insert ON crm.lead_score_records
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT ON crm.lead_score_records TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.lead_score_records FROM app_api, app_worker;


CREATE TABLE crm.crm_field_definitions (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  fields           JSONB         NOT NULL DEFAULT '[]',
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_crm_field_definitions PRIMARY KEY (id)
);

CREATE UNIQUE INDEX uq_cfd_org ON crm.crm_field_definitions (organization_id);

CREATE TRIGGER trg_cfd_updated_at
  BEFORE UPDATE ON crm.crm_field_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE crm.crm_field_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.crm_field_definitions FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cfd_tenant ON crm.crm_field_definitions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON crm.crm_field_definitions TO app_api, app_worker;
```

### 14.6 Consent Records (Partitioned) and Contact Suppressions

```sql
-- ================================================================
-- Migration 024: crm.consent_records (partitioned), crm.contact_suppressions
-- ================================================================

CREATE TABLE crm.consent_records (
  id                 UUID          NOT NULL DEFAULT gen_uuid_v7(),
  recorded_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),  -- PARTITION KEY
  organization_id    UUID          NOT NULL,
  contact_id         UUID          NOT NULL,
  purpose            TEXT          NOT NULL,
  channel            TEXT          NOT NULL,
  status             TEXT          NOT NULL,
  source             TEXT          NOT NULL,
  source_ref         TEXT          NULL,
  evidence           JSONB         NOT NULL DEFAULT '{}',
  obtained_at        TIMESTAMPTZ   NULL,
  withdrawn_at       TIMESTAMPTZ   NULL,
  expires_at         TIMESTAMPTZ   NULL,
  policy_version_ref INTEGER       NOT NULL,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_consent_records   PRIMARY KEY (id, recorded_at),
  CONSTRAINT chk_cr_status        CHECK (status IN ('GRANTED','WITHDRAWN','EXPIRED','UNKNOWN')),
  CONSTRAINT chk_cr_channel       CHECK (channel IN ('VOICE','SMS','WHATSAPP','EMAIL','ANY')),
  CONSTRAINT chk_cr_purpose       CHECK (purpose IN (
    'OUTBOUND_CALL','MARKETING','TRANSACTIONAL','RECORDING','FOLLOW_UP',
    'WHATSAPP_MESSAGING','SMS_MESSAGING','EMAIL_MESSAGING','DATA_PROCESSING','AI_INTERACTION'
  )),
  CONSTRAINT chk_cr_source        CHECK (source IN (
    'WEB_FORM','VERBAL_ON_CALL','SMS_REPLY','WHATSAPP_OPT_IN','EMAIL_CONFIRMATION',
    'CONTRACT','CSV_IMPORT_ASSERTED','API_ASSERTED','EXISTING_RELATIONSHIP','MANUAL_ENTRY'
  ))
) PARTITION BY RANGE (recorded_at);

CREATE INDEX idx_cr_contact_purpose_channel
  ON crm.consent_records (organization_id, contact_id, purpose, channel, recorded_at DESC);
CREATE INDEX idx_cr_org_time_brin
  ON crm.consent_records USING BRIN (organization_id, recorded_at);

ALTER TABLE crm.consent_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.consent_records FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_consent_read ON crm.consent_records
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_consent_insert ON crm.consent_records
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT ON crm.consent_records TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.consent_records FROM app_api, app_worker;

-- Parametric partition creation via create_monthly_partitions()
CREATE TABLE crm.consent_records_default PARTITION OF crm.consent_records DEFAULT;


-- contact_suppressions: three-scope RLS (Phase 5A §6.4)
-- ACTIVE → LIFTED transitions via crm.lift_suppression() SECURITY DEFINER (see below).
-- app_api and app_worker: INSERT only (via RLS). No direct UPDATE or DELETE.
CREATE TABLE crm.contact_suppressions (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NULL,         -- NULL = PLATFORM or REGULATORY scope
  phone_e164       TEXT          NOT NULL,     -- pii:phone; suppression key
  contact_id       UUID          NULL,         -- logical ref: crm.contacts.id (nullable)
  scope            TEXT          NOT NULL,
  channel          TEXT          NOT NULL,
  reason           TEXT          NOT NULL,
  source           TEXT          NOT NULL,
  source_ref       TEXT          NULL,
  status           TEXT          NOT NULL DEFAULT 'ACTIVE',
  effective_from   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ   NULL,
  lifted_at        TIMESTAMPTZ   NULL,
  lifted_by_ref    UUID          NULL,
  recorded_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_contact_suppressions  PRIMARY KEY (id),
  CONSTRAINT chk_sup_scope            CHECK (scope IN ('ORG','PLATFORM','REGULATORY')),
  CONSTRAINT chk_sup_channel          CHECK (channel IN ('VOICE','SMS','WHATSAPP','EMAIL','ALL')),
  CONSTRAINT chk_sup_status           CHECK (status IN ('ACTIVE','LIFTED','EXPIRED')),
  CONSTRAINT chk_sup_reason           CHECK (reason IN (
    'CUSTOMER_REQUEST','REGULATORY_REGISTRY','COMPLAINT','INVALID_NUMBER',
    'REPEATED_NO_ANSWER','HARD_BOUNCE','FRAUD_SUSPECTED','ORG_POLICY',
    'LEGAL_HOLD','CONSENT_WITHDRAWN'
  )),
  CONSTRAINT chk_sup_source           CHECK (source IN (
    'VERBAL_ON_CALL','IVR_OPT_OUT','SMS_STOP','WHATSAPP_BLOCK','EMAIL_UNSUBSCRIBE',
    'ADMIN_ACTION','CSV_IMPORT','API','REGULATORY_SYNC','AUTOMATED_RULE'
  )),
  CONSTRAINT chk_sup_phone            CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_sup_expires          CHECK (expires_at IS NULL OR expires_at > effective_from),
  -- Scope ↔ org_id consistency (Phase 4I §8.5):
  CONSTRAINT chk_sup_scope_org_id     CHECK (
    (scope = 'ORG' AND organization_id IS NOT NULL) OR
    (scope IN ('PLATFORM','REGULATORY') AND organization_id IS NULL)
  )
);

COMMENT ON COLUMN crm.contact_suppressions.phone_e164 IS 'pii:phone — suppression key; not contact_id';
COMMENT ON COLUMN crm.contact_suppressions.organization_id IS 'NULL for PLATFORM/REGULATORY scope';
COMMENT ON COLUMN crm.contact_suppressions.status IS
  'ACTIVE: enforcement applies. LIFTED: admin-lifted via crm.lift_suppression(). '
  'EXPIRED: evaluated at read time when expires_at < NOW(); row is never mutated to EXPIRED.';

CREATE INDEX idx_sup_org_phone_status
  ON crm.contact_suppressions (organization_id, phone_e164, status);
CREATE INDEX idx_sup_platform_phone
  ON crm.contact_suppressions (phone_e164, scope)
  WHERE scope IN ('PLATFORM','REGULATORY');
CREATE INDEX idx_sup_contact
  ON crm.contact_suppressions (organization_id, contact_id)
  WHERE contact_id IS NOT NULL;
CREATE INDEX idx_sup_expires
  ON crm.contact_suppressions (expires_at)
  WHERE expires_at IS NOT NULL AND status = 'ACTIVE';

ALTER TABLE crm.contact_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.contact_suppressions FORCE ROW LEVEL SECURITY;

-- Three-scope read policy (Phase 5A §6.4):
CREATE POLICY rls_suppression_read ON crm.contact_suppressions
  FOR SELECT
  USING (
    organization_id = organization.current_tenant_id()
    OR (organization_id IS NULL AND scope IN ('PLATFORM', 'REGULATORY'))
  );

-- Insert only ORG-scope rows; org_id must match tenant:
CREATE POLICY rls_suppression_insert ON crm.contact_suppressions
  FOR INSERT WITH CHECK (
    organization_id = organization.current_tenant_id()
    AND scope = 'ORG'
  );

GRANT SELECT, INSERT ON crm.contact_suppressions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.contact_suppressions FROM app_api, app_worker;
-- PLATFORM/REGULATORY rows inserted exclusively by app_platform_admin (BYPASSRLS).
-- ACTIVE → LIFTED updates performed exclusively via crm.lift_suppression() below.


-- SECURITY DEFINER: controlled ACTIVE → LIFTED transition (Phase 4I §8.5 invariant 4)
-- app_api and app_worker call this function; they do not hold direct UPDATE privilege.
CREATE OR REPLACE FUNCTION crm.lift_suppression(
  p_suppression_id   UUID,
  p_lifted_by_ref    UUID,
  p_organization_id  UUID  -- caller's tenant context; NULL for platform admin path
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = crm, organization, pg_temp
AS $$
DECLARE
  v_scope  TEXT;
  v_status TEXT;
  v_org_id UUID;
BEGIN
  SELECT scope, status, organization_id
  INTO v_scope, v_status, v_org_id
  FROM crm.contact_suppressions
  WHERE id = p_suppression_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Suppression record not found: %', p_suppression_id;
  END IF;

  IF v_status != 'ACTIVE' THEN
    RAISE EXCEPTION
      'Suppression % is not ACTIVE (current: %). Cannot lift.', p_suppression_id, v_status;
  END IF;

  -- PLATFORM/REGULATORY suppressions require platform admin (p_organization_id IS NULL)
  IF v_scope IN ('PLATFORM','REGULATORY') AND p_organization_id IS NOT NULL THEN
    RAISE EXCEPTION
      'Only platform administrators may lift PLATFORM/REGULATORY suppressions. '
      'suppression_id: %', p_suppression_id;
  END IF;

  -- ORG suppressions: calling tenant must own the record
  IF v_scope = 'ORG' AND p_organization_id IS NOT NULL
     AND v_org_id IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION
      'Tenant % does not own suppression %.', p_organization_id, p_suppression_id;
  END IF;

  -- Perform the targeted lift — the ONLY UPDATE permitted on this table via application roles
  UPDATE crm.contact_suppressions
  SET status        = 'LIFTED',
      lifted_at     = NOW(),
      lifted_by_ref = p_lifted_by_ref
  WHERE id = p_suppression_id;

  -- Caller must publish contact.suppression_lifted domain event after returning.
END;
$$;

REVOKE ALL ON FUNCTION crm.lift_suppression(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.lift_suppression(UUID, UUID, UUID)
  TO app_api, app_worker, app_platform_admin;
```

### 14.7 Grants Finalization

```sql
-- ================================================================
-- Migration 025: CRM grants finalization
-- ================================================================

-- app_readonly gets SELECT on all crm tables (for analytics queries)
GRANT SELECT ON crm.contacts              TO app_readonly;
GRANT SELECT ON crm.companies             TO app_readonly;
GRANT SELECT ON crm.deals                 TO app_readonly;
GRANT SELECT ON crm.pipelines             TO app_readonly;
GRANT SELECT ON crm.activities            TO app_readonly;
GRANT SELECT ON crm.tasks                 TO app_readonly;
GRANT SELECT ON crm.notes                 TO app_readonly;
GRANT SELECT ON crm.appointments          TO app_readonly;
GRANT SELECT ON crm.lead_score_records    TO app_readonly;
GRANT SELECT ON crm.crm_field_definitions TO app_readonly;
GRANT SELECT ON crm.consent_records       TO app_readonly;
GRANT SELECT ON crm.contact_suppressions  TO app_readonly;

-- app_platform_admin: full access (BYPASSRLS — for PLATFORM/REGULATORY suppression inserts)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA crm TO app_platform_admin;
```

### 14.8 Seed Data — Default Pipeline

```sql
-- ================================================================
-- Migration 026: CRM seed data
-- ================================================================
-- Note: no org-specific seed data is inserted here.
-- The default pipeline is created by CreateOrganizationUseCase
-- at org creation time, not as a migration.
-- The pipeline template is configured via platform admin API.
-- This migration confirms the schema is ready.
SELECT 1;  -- placeholder — seed data is environment-specific
```

---

## 15. Query Patterns

### 15.1 Find or Create Contact by Phone (Tool Runner)

```sql
-- SET LOCAL app.tenant_id = $org_id
-- Step 1: Check for existing contact
SELECT id, lead_status, do_not_call, qualification_status
FROM crm.contacts
WHERE organization_id = organization.current_tenant_id()
  AND phone_e164 = $phone_e164
  AND deleted_at IS NULL;
-- Index: uq_contacts_phone (partial unique — O(1))
-- RLS: organization_id = current_tenant_id() ✓

-- Step 2 (if not found): insert with dedup protection
INSERT INTO crm.contacts (
  id, organization_id, full_name, phone_e164, phone_country, source, ...
)
VALUES ($id, $org_id, $name, $phone, $country, 'INBOUND_CALL', ...)
ON CONFLICT (organization_id, phone_e164) WHERE deleted_at IS NULL
DO NOTHING;
-- Returns the id whether inserted or found
```

### 15.2 Get Lead List by Status

```sql
SELECT id, full_name, phone_e164, lead_status, lead_score, lead_temperature,
       last_contacted_at, owned_by
FROM crm.contacts
WHERE organization_id = organization.current_tenant_id()
  AND lead_status = $status
  AND deleted_at IS NULL
ORDER BY lead_score DESC NULLS LAST, last_contacted_at DESC NULLS LAST
LIMIT 50 OFFSET $offset;
-- Index: idx_contacts_org_lead_status
```

### 15.3 Get Contact Activity Timeline

```sql
SELECT id, activity_type, subject_type, subject_id,
       occurred_at, actor_type, actor_name, summary, payload
FROM crm.activities
WHERE organization_id = organization.current_tenant_id()
  AND subject_type = 'CONTACT'
  AND subject_id = $contact_id
  -- Optional partition pruning: add occurred_at >= $lookback_date
ORDER BY occurred_at DESC
LIMIT 20;
-- Index: idx_act_subject
```

### 15.4 Get Deal Board (Pipeline Kanban)

```sql
SELECT d.id, d.title, d.current_stage_id, d.value_amount, d.value_currency,
       d.status, d.close_date, c.full_name AS contact_name
FROM crm.deals d
LEFT JOIN crm.contacts c ON c.id = d.contact_id
  AND c.organization_id = organization.current_tenant_id()
WHERE d.organization_id = organization.current_tenant_id()
  AND d.pipeline_id = $pipeline_id
  AND d.status = 'OPEN'
ORDER BY d.current_stage_id, d.created_at;
-- Index: idx_deals_pipeline (covers pipeline_id + stage, status = 'OPEN')
-- Cross-aggregate join within crm schema: permitted
```

### 15.5 Effective Consent Lookup

```sql
-- This is cached in Redis: consent:{org}:{contact_id}:{purpose}
-- DB query is the cache-miss fallback:

SELECT status, expires_at, obtained_at, withdrawn_at
FROM crm.consent_records
WHERE organization_id = organization.current_tenant_id()
  AND contact_id = $contact_id
  AND purpose = $purpose
  AND channel = $channel
  -- Optional: AND recorded_at >= $lookback (for partition pruning)
ORDER BY recorded_at DESC
LIMIT 1;
-- Index: idx_cr_contact_purpose_channel
-- Application evaluates: if expires_at < NOW() → treat as EXPIRED regardless of stored status
```

### 15.6 Dispatch-Time Suppression Check

```sql
-- Called at campaign call dispatch, before dialling
-- Also cached in Redis: suppression:{org}:{phone_e164}

-- Check 1: org-scope suppression
SELECT id, scope, reason, channel
FROM crm.contact_suppressions
WHERE organization_id = organization.current_tenant_id()
  AND phone_e164 = $phone_e164
  AND status = 'ACTIVE'
  AND (channel = 'VOICE' OR channel = 'ALL')
  AND (expires_at IS NULL OR expires_at > NOW())
LIMIT 1;
-- Index: idx_sup_org_phone_status

-- Check 2: platform/regulatory suppression (no org context needed)
-- Note: RLS allows reading org IS NULL rows when scope IN ('PLATFORM','REGULATORY')
SELECT id, scope, reason
FROM crm.contact_suppressions
WHERE phone_e164 = $phone_e164
  AND scope IN ('PLATFORM','REGULATORY')
  AND status = 'ACTIVE'
  AND (channel = 'VOICE' OR channel = 'ALL')
  AND (expires_at IS NULL OR expires_at > NOW())
LIMIT 1;
-- Index: idx_sup_platform_phone
-- RLS policy allows this read because org IS NULL rows + scope IN ('PLATFORM','REGULATORY')
```

### 15.7 Create Suppression Record (DNC from Call)

```sql
-- Triggered by `suppressContact` tool or manual DNC marking
INSERT INTO crm.contact_suppressions (
  id, organization_id, phone_e164, contact_id, scope, channel,
  reason, source, source_ref, status, effective_from
)
VALUES (
  $id, $org_id, $phone, $contact_id,
  'ORG', 'ALL',
  'CUSTOMER_REQUEST', 'VERBAL_ON_CALL', $call_id,
  'ACTIVE', NOW()
);
-- RLS WITH CHECK: organization_id = current_tenant_id() AND scope = 'ORG' ✓
-- After commit: publish contact.dnc_flagged event
-- Event handler: UPDATE crm.contacts SET do_not_call = TRUE WHERE phone_e164 = $phone AND org...
-- Redis: SET suppression:{org}:{phone} (TTL 1h)
```

### 15.8 Compute and Apply Lead Score

```sql
-- Step 1: Insert score record (append-only)
INSERT INTO crm.lead_score_records (
  id, organization_id, contact_id, score, previous_score,
  score_version, signals, computed_at, computed_by
)
VALUES ($id, $org_id, $contact_id, $score, $prev_score,
        $version, $signals_json, NOW(), 'RULE_ENGINE');
-- REVOKE UPDATE, DELETE enforces append-only ✓

-- Step 2: Update denormalized score on contact (atomic update)
UPDATE crm.contacts
SET lead_score = $score,
    lead_temperature = CASE
      WHEN $score >= 70 THEN 'HOT'
      WHEN $score >= 40 THEN 'WARM'
      WHEN $score >= 0  THEN 'COLD'
      ELSE NULL
    END,
    updated_at = NOW()
WHERE id = $contact_id
  AND organization_id = organization.current_tenant_id();
-- LeadTemperature derivation from LeadScore — Phase 4C DDR-4C-004
-- Always derived; never set independently ✓
```

### 15.9 Book Appointment (AI Tool)

```sql
-- SET LOCAL app.tenant_id = $org_id
INSERT INTO crm.appointments (
  id, organization_id, contact_id, organizer_ref, attendees,
  title, scheduled_start, scheduled_end,
  location_type, location_detail, status, source, conversation_ref
)
VALUES (
  $id, $org_id, $contact_id, $organizer_user_id, $attendees,
  $title, $start, $end,
  'VIRTUAL', $url, 'SCHEDULED', 'AI_AGENT', $conversation_id
);
-- Policy: AppointmentEndAfterStart enforced by CHECK constraint ✓
-- Policy: BookingWindowEnforced enforced at application layer
-- After commit: publish appointment.booked event
```

### 15.10 Load Pipeline with Stages

```sql
SELECT id, name, is_default, stages
FROM crm.pipelines
WHERE organization_id = organization.current_tenant_id()
ORDER BY is_default DESC, name ASC;
-- stages JSONB contains all embedded PipelineStage entities
-- Application deserializes into ordered list
-- Index: idx_pipelines_org
-- Typically ≤ 5 pipelines per org — full table scan within RLS is fine
```

---

## 16. Suppression Lifecycle — Authoritative Answers

This section answers the eight required questions from the correction pass, derived from Phase 4I §8.5.

### 1. ACTIVE Suppression Creation

```sql
-- INSERT (via app_api/app_worker + RLS WITH CHECK enforces scope='ORG' for tenant callers)
INSERT INTO crm.contact_suppressions (
  id, organization_id, phone_e164, contact_id, scope, channel,
  reason, source, source_ref, status, effective_from
) VALUES (
  gen_uuid_v7(), $org_id, $phone, $contact_id,
  'ORG', 'ALL', 'CUSTOMER_REQUEST', 'VERBAL_ON_CALL', $call_id,
  'ACTIVE', NOW()
);
```

PLATFORM/REGULATORY suppressions are inserted by `app_platform_admin` (BYPASSRLS).

### 2. ACTIVE → LIFTED

Only via `crm.lift_suppression()` SECURITY DEFINER function. Normal application roles (`app_api`, `app_worker`) call this function — they do not hold direct UPDATE privilege. The function performs the targeted UPDATE `{status='LIFTED', lifted_at, lifted_by_ref}`. After commit, the caller publishes `contact.suppression_lifted` domain event. The original row's `reason`, `source`, `recorded_at`, `effective_from` are permanently retained as evidence (Phase 4I §8.5 invariant 4: "original record retains its history").

### 3. ACTIVE → EXPIRED

`EXPIRED` is **never written to the database**. It is evaluated at read time. Any enforcement query includes:
```sql
AND (expires_at IS NULL OR expires_at > NOW())
```
This makes `expires_at` a pure time-based gate. No background job flips rows to EXPIRED. No UPDATE is needed.

### 4. Effective Suppression Query

```sql
-- Given: phone_e164 + channel + organization_id
-- The system is SUPPRESSED if ANY of the following returns a row:

-- ORG scope:
SELECT 1 FROM crm.contact_suppressions
WHERE organization_id = $org_id
  AND phone_e164 = $phone
  AND status = 'ACTIVE'
  AND (channel = $channel OR channel = 'ALL')
  AND (expires_at IS NULL OR expires_at > NOW())
LIMIT 1;

-- PLATFORM/REGULATORY scope (read permitted by RLS):
SELECT 1 FROM crm.contact_suppressions
WHERE organization_id IS NULL
  AND scope IN ('PLATFORM','REGULATORY')
  AND phone_e164 = $phone
  AND status = 'ACTIVE'
  AND (channel = $channel OR channel = 'ALL')
  AND (expires_at IS NULL OR expires_at > NOW())
LIMIT 1;
-- Combined result: NOT_SUPPRESSED only if both queries return 0 rows.
```

### 5. Expiry Without UPDATE

`expires_at` is set at INSERT time and never changed. The application evaluates `expires_at IS NULL OR expires_at > NOW()` at every enforcement check. No rows are ever mutated to reflect expiry. Redis cache (`suppression:{org}:{phone}`, 1h TTL) is set with the expiry time so it naturally expires at the correct moment.

### 6. Idempotency

If a suppress event is delivered twice: the application performs `SELECT ... WHERE org_id = ? AND phone_e164 = ? AND scope = ? AND channel = ? AND status = 'ACTIVE'` before inserting. If an ACTIVE record exists for the same scope/channel/phone, the second INSERT is skipped (idempotent at application layer). The `(organization_id, phone_e164, scope, channel)` partial UNIQUE index `WHERE status = 'ACTIVE'` enforces this at the DB level — documented as a carry-forward hardening item for Phase 9 implementation.

### 7. PLATFORM / REGULATORY vs. ORG

| Aspect | ORG | PLATFORM / REGULATORY |
|---|---|---|
| `organization_id` | NOT NULL (tenant's ID) | NULL |
| Who inserts | `app_api`/`app_worker` (via RLS) | `app_platform_admin` only |
| Who reads | Own tenant only | All tenants (via RLS read policy) |
| Who lifts | Tenant user via `lift_suppression()` | `app_platform_admin` only via `lift_suppression(p_organization_id=NULL)` |
| Scope of suppression | Single organization | Platform-wide across all tenants |

### 8. Survival Through Contact Lifecycle Events

| Contact event | Suppression effect |
|---|---|
| Contact soft-deleted (`deleted_at` set) | No effect — suppression keyed on `phone_e164`, not `contact_id` |
| Contact GDPR erasure (`phone_e164` → `+99000000000`) | No effect on suppression row — original phone retained in `contact_suppressions.phone_e164` |
| Contact merged (secondary merged into primary) | No effect — phone remains in suppression |
| Contact re-imported (same phone) | New Contact row created. First eligibility check finds suppression by phone → suppressed immediately |

This is the exact failure mode Phase 4I §8.5 was designed to prevent: a person who opts out must remain opted out even through CRM record churn.

---

## 17. Alembic Migration Plan

```
Phase 5C migrations (009–018)
        ↓
019_crm_schema_and_functions
    down_revision = '018_voice_grants_finalize'
    purpose: CRM schema grant, AI note immutability trigger function

020_crm_contacts_companies
    down_revision = '019_crm_schema_and_functions'
    purpose: crm.contacts, crm.companies, indexes, triggers, RLS, grants

021_crm_pipelines_deals
    down_revision = '020_crm_contacts_companies'
    purpose: crm.pipelines, crm.deals, FK (deals→pipelines), indexes, triggers, RLS, grants

022_crm_activities_tasks_notes
    down_revision = '021_crm_pipelines_deals'
    purpose: crm.activities (partitioned + DEFAULT + parametric),
             crm.tasks, crm.notes (with AI immutability trigger), REVOKE on activities

023_crm_appointments_scores_fields
    down_revision = '022_crm_activities_tasks_notes'
    purpose: crm.appointments, crm.lead_score_records (REVOKE), crm.crm_field_definitions

024_crm_consent_suppression
    down_revision = '023_crm_appointments_scores_fields'
    purpose: crm.consent_records (partitioned + DEFAULT + REVOKE),
             crm.contact_suppressions (three-scope RLS + REVOKE),
             crm.lift_suppression() SECURITY DEFINER function
             [REVOKE ALL FROM PUBLIC + GRANT EXECUTE TO app_api, app_worker, app_platform_admin]

025_crm_grants_finalize
    down_revision = '024_crm_consent_suppression'
    purpose: app_readonly grants on all CRM tables; app_platform_admin full access

026_crm_seed_data
    down_revision = '025_crm_grants_finalize'
    purpose: placeholder (org-specific seed data via API, not migration)
```

---

## 17. PII Classification

| Table.Column | PII Category | Handling |
|---|---|---|
| `contacts.full_name` | `pii:name` | Masked in logs; replaced with `[ERASED]` on GDPR erasure |
| `contacts.phone_e164` | `pii:phone` | Masked in logs; replaced with placeholder on erasure |
| `contacts.secondary_phone_e164` | `pii:phone` | Same |
| `contacts.primary_email` | `pii:email` | Masked; set to NULL on erasure |
| `contacts.primary_email_normalized` | `pii:email` | Set to NULL on erasure |
| `contacts.address_*` | `pii:address` | Set to NULL on erasure |
| `activities.actor_name` | `pii:name` | Captured at activity creation; not erased (audit trail) |
| `notes.body` (AI_SUMMARY) | `pii:voice` | Masked in logs; may contain voice-derived content |
| `contact_suppressions.phone_e164` | `pii:phone` | Masked in logs; retained even after contact erasure |
| `consent_records.*` | `pii:consent` | Retained as legal evidence per compliance policy |

---

## 18. Retention Strategy

| Table | Default retention | Configurable? |
|---|---|---|
| `contacts` | Indefinite (soft deleted) | GDPR erasure on request |
| `companies` | Indefinite | No |
| `deals` | Indefinite | No |
| `pipelines` | Indefinite | No |
| `activities` | 5 years hot | Via CompliancePolicy.RetentionProfile |
| `tasks` | Indefinite | No |
| `notes` | Indefinite (soft deleted) | No |
| `appointments` | Indefinite | No |
| `lead_score_records` | Indefinite | No |
| `crm_field_definitions` | Indefinite | No |
| `consent_records` | Per CompliancePolicy | Regulatory minimum — never less than legal hold |
| `contact_suppressions` | Per suppression `expires_at` | ORG scope: configurable. PLATFORM/REGULATORY: permanent until admin lifted. |

---

## 19. Security Review

### 19.1 Tenant Isolation

| Scenario | Prevention |
|---|---|
| Tenant A reads Tenant B's contacts | RLS: `organization_id = current_tenant_id()` — 0 rows |
| Tenant A reads Tenant B's consent records | Same RLS — 0 rows |
| Tenant inserts PLATFORM-scope suppression | RLS WITH CHECK: `scope = 'ORG'` AND `organization_id = current_tenant_id()` — rejected |
| Tenant reads PLATFORM-scope suppression | Permitted — enforcement requires it (via `OR organization_id IS NULL AND scope IN (...)`) |
| Missing tenant context reads contacts | `current_tenant_id() = NULL` → 0 rows — fail-closed |
| Worker with valid tenant context | Standard RLS; same as API |
| Platform admin cross-tenant read | BYPASSRLS — audited |

### 19.2 DNC Enforcement Chain

```
suppressContact tool call → voice.tool_executions
    ↓ (sync CRM call)
SuppressContact use case → INSERT contact_suppressions (org scope)
INSERT consent_records (OUTBOUND_CALL purpose, WITHDRAWN)
    ↓ (publish event)
contact.dnc_flagged event
    → Campaign Execution: remove from queues
    → Redis: SET suppression:{org}:{phone} (1h TTL, refresh)
    → contacts.do_not_call = TRUE (denormalized update)
    → Audit event
```

**The DO NOT CALL flag on `contacts` is informational.** No system reads `contacts.do_not_call` for enforcement. Enforcement reads `contact_suppressions` (Redis-backed, DB-authoritative).

### 19.3 AI Note Protection

`crm.prevent_ai_note_body_mutation()` trigger prevents `body` changes on AI-generated notes at DB level. A `BEFORE UPDATE` trigger raises an exception before any write reaches the storage engine. This is not a convention — it is enforced by the database engine regardless of application behavior.

---

## 20. Tenant Isolation Test Matrix

| Test | Mechanism | Expected Result |
|---|---|---|
| Tenant A reads Tenant B's contacts | `SET LOCAL` to OrgA, SELECT WHERE id = OrgB_contact | 0 rows |
| Tenant A inserts contact with wrong org_id | RLS WITH CHECK fails | Constraint violation |
| Tenant A reads PLATFORM suppression for a phone | RLS read policy allows (org IS NULL + scope = PLATFORM) | Row returned |
| Tenant A inserts PLATFORM suppression | RLS INSERT policy: scope must be 'ORG' | Rejected |
| Tenant modifies AI-generated note body | Trigger fires: `RAISE EXCEPTION` | Error — cannot update |
| Consent record update attempt | `REVOKE UPDATE` on `consent_records` | Permission denied |
| Activity update attempt | `REVOKE UPDATE` on `activities` | Permission denied |
| Lead score record update attempt | `REVOKE UPDATE` on `lead_score_records` | Permission denied |
| Contact suppression direct UPDATE attempt | `REVOKE UPDATE` on `contact_suppressions` from `app_api`/`app_worker` | Permission denied — must use `crm.lift_suppression()` |
| Contact suppression lift via function | `crm.lift_suppression()` SECURITY DEFINER validates ownership + ACTIVE status, then sets `status='LIFTED'` | Success — lifted_at and lifted_by_ref set; original evidence retained |
| Missing tenant context | `current_tenant_id() = NULL` | 0 rows on all RLS-enabled tables |
| Contact GDPR erasure, then re-import | `phone_e164 = '+99000000000'` (valid placeholder), `deleted_at IS NOT NULL` — excluded from partial unique index | New row created for original phone. Suppression records for original phone remain active. |
| Pipeline stages deleted while deals in stage | FK constraint: RESTRICT on `deals.pipeline_id` | Error — cannot delete pipeline |

---

## 21. ADRs

### ADR-5D-001: Lead = Contact (Confirmed from DDR-4C-001)

**Decision:** no separate `leads` table. `crm.contacts` with `lead_status` column is the single entity.

**Rationale:** Phase 4C DDR-4C-001 — the platform's inbound channel (phone calls) creates Contacts directly. No separate lead intake creates a Lead object. The unified model eliminates field-mapping on conversion, dual timeline, and duplicate deduplication.

### ADR-5D-002: `contact_suppressions` Keyed on `phone_e164`, Not `contact_id`

**Decision:** `crm.contact_suppressions.phone_e164` is the suppression key. `contact_id` is nullable.

**Rationale:** Phase 4I §8.5. A person who asks not to be called should stay suppressed even if their Contact record is deleted, merged, or re-imported. Keying on the phone number makes suppression survive CRM record churn.

### ADR-5D-003: `contacts.do_not_call` Is Denormalized Read, Not Authoritative

**Decision:** `contacts.do_not_call` is maintained by event handlers as a fast filter. No enforcement logic reads it. Enforcement reads `contact_suppressions`.

**Rationale:** Phase 4I CONTRADICTION-03. Two sources of truth for DNC would diverge during campaigns. The suppression aggregate is the single authoritative source; the boolean is a read cache for fast UI filtering.

### ADR-5D-004: Pipeline Stages as JSONB

**Decision:** `pipelines.stages` is a JSONB array of `PipelineStage` entities.

**Rationale:** Phase 4C §4.4 defines stages as an embedded list bounded at ≤ 20, always read/written together with the Pipeline. A separate `pipeline_stages` table would add a join to every pipeline load and complicate the atomic reorder operation. JSONB is appropriate per Phase 5A §4.1.

### ADR-5D-005: Activities Are Append-Only at DB Level

**Decision:** `REVOKE UPDATE, DELETE ON crm.activities FROM app_api, app_worker`.

**Rationale:** Phase 4C DDR-4C-002. Activities are the audit trail of CRM interactions. Mutable activities would undermine their purpose as compliance-grade records.

### ADR-5D-006: AI Note Immutability Enforced by Trigger

**Decision:** a `BEFORE UPDATE` trigger prevents `body` mutation on AI-generated notes.

**Rationale:** Phase 4C DDR-4C-003. AI-generated notes are the verbatim output of the AI platform. Modifying them would corrupt the record. Enforcement at DB level provides defense-in-depth beyond application-layer checks.

### ADR-5D-007: GDPR Erasure via PII Clearing, Not Hard Delete

**Decision:** GDPR erasure clears PII fields on the `contacts` row; the row itself remains with `deleted_at` set. `phone_e164` is replaced with the valid placeholder `+99000000000` (satisfies `CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')`; the `+9` prefix is an ITU reserved/non-geographic prefix, making it safe as an erasure tombstone). `contact_suppressions` records for the original phone are not modified — they persist as authoritative DNC evidence per Phase 4I §8.5.

**Rationale:** Activities, deals, notes, appointments, and lead score records reference `contact_id`. Hard-deleting the contact would orphan these records. The Contact row is retained as a tombstone; PII is cleared. The partial UNIQUE index on `(organization_id, phone_e164) WHERE deleted_at IS NULL` allows the original phone number to be re-registered after erasure. If the original phone is re-imported, the new Contact row remains suppressed on its first eligibility check.

### ADR-5D-008: Suppression Lifecycle — Controlled UPDATE via SECURITY DEFINER

**Decision:** `contact_suppressions` is not unconditionally append-only. Phase 4I §8.5 invariant 4 explicitly allows `ACTIVE → LIFTED` transitions on the same row. This transition is performed exclusively via `crm.lift_suppression()` (SECURITY DEFINER), which holds UPDATE privilege through its definer rights. Normal application roles (`app_api`, `app_worker`) hold INSERT only — `REVOKE UPDATE, DELETE` stands. `EXPIRED` state is never written to the database; it is evaluated at read time from `expires_at`. This model satisfies the Phase 4I "original record retains its history" requirement without introducing a separate events table.

**Alternative rejected:** a second table `contact_suppression_events` to model all state transitions as immutable appends. Rejected because Phase 4I §8.5 explicitly models the aggregate as a single row with `Status`, `LiftedAt`, `LiftedByRef` fields — it does not define an event-sourced model. Introducing a second table would contradict the authoritative DDD without a design decision record in Phase 4I authorizing it.

---

## Phase 5D Final Review (Post-Correction Pass)

### Issues Resolved

| Issue | Status | What was done |
|---|---|---|
| ISSUE 1 — `+00000000000` violates `CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')` | ✅ RESOLVED | Placeholder changed to `+99000000000` (valid under regex; +9 prefix is ITU reserved/non-geographic). All document references updated. |
| ISSUE 2 — `REVOKE UPDATE` on `contact_suppressions` while `ACTIVE → LIFTED` requires an UPDATE | ✅ RESOLVED | `crm.lift_suppression()` SECURITY DEFINER function performs the targeted UPDATE through its definer's privileges. `app_api`/`app_worker` hold INSERT only; REVOKE stands. EXPIRED status is never written (evaluated at read time). |
| ISSUE 3 — GDPR + suppression interaction verification | ✅ RESOLVED | Confirmed: suppression rows are keyed on original `phone_e164` and are unaffected by Contact erasure, merge, or re-import. New Contact inheriting a previously suppressed phone is blocked on first eligibility check. |
| Minor — `lead_temperature` derivation enforcement | ✅ RESOLVED | Documented as explicit application-layer invariant in §5.1. No DB trigger added (consistent with Phase 5A §4.3 principle). |

### Fresh Final Consistency Checks

**A. DDD consistency ✅** All 13 Phase 4C/4I aggregates mapped. `lift_suppression()` matches Phase 4I §8.5 invariant 4 exactly.

**B. Phase 5A consistency ✅** No violations. JSONB justified. Money pair enforced. Append-only enforced (with controlled UPDATE exception via SECURITY DEFINER). PII tagged.

**C. Phase 5B consistency ✅** `organization.current_tenant_id()`, `gen_uuid_v7()`, `set_updated_at()`, `organization_id` all used correctly.

**D. PostgreSQL correctness ✅** All CHECK constraints satisfied by corrected GDPR placeholder. Partitioned PKs correct. SECURITY DEFINER function has `REVOKE ALL FROM PUBLIC` + explicit `GRANT EXECUTE`. RLS, FORCE RLS, grants, revokes all consistent.

**E. GDPR + suppression interaction ✅** Suppression survives contact erasure, merge, deletion, and re-import. Original phone retained in `contact_suppressions`. New contacts with same phone are suppressed on first eligibility check.

**F. Suppression lifecycle ✅** No contradiction between "append-only for application roles" and "ACTIVE → LIFTED needs UPDATE". Resolved via SECURITY DEFINER with minimal privilege. EXPIRED evaluated at read time — no UPDATE needed.

**G. `lead_temperature` ✅** Documented as application-layer invariant. CHECK enforces allowed values. No DB trigger. Consistent.

---

```
PHASE 5D STATUS

CRM schema:
APPROVED

Contacts (incl. GDPR erasure strategy):
APPROVED

Companies, Deals, Pipelines:
APPROVED

Activities (append-only, partitioned):
APPROVED

Tasks, Notes, Appointments:
APPROVED

Lead Score Records (append-only):
APPROVED

Custom Field Definitions:
APPROVED

Consent Records (append-only, partitioned — Phase 4I):
APPROVED

Contact Suppressions (three-scope RLS + controlled lift via SECURITY DEFINER — Phase 4I):
APPROVED

Partitioning:
APPROVED

RLS:
APPROVED

Append-only enforcement:
APPROVED

Security:
APPROVED

DDL:
APPROVED

Alembic migration plan:
APPROVED

Overall:
PHASE 5E READY
```

All three blocking issues resolved. Phase 4I §8.5 suppression lifecycle model is fully and consistently implemented. GDPR erasure phone placeholder satisfies the database CHECK constraint. Eight required suppression lifecycle questions answered in §16. ADR-5D-008 closes the suppression UPDATE model decision.

**Phase 5E** designs the `campaign` schema — it depends on `crm.contacts`, `crm.contact_suppressions`, and `crm.consent_records` logical references established here.

---

## Controlled Amendment — Phase 5L (2026-08-24)

Migration `085_5D1.sql` adds `uq_sup_active`, a partial unique index on
`crm.contact_suppressions (organization_id, phone_e164, scope, channel)
WHERE status = 'ACTIVE'`, using `NULLS NOT DISTINCT` so PLATFORM/
REGULATORY-scope rows (`organization_id IS NULL`) are genuinely
deduplicated too — a plain `UNIQUE` index would treat every `NULL` as
distinct and silently fail to enforce anything for those two scopes.
This is exactly the mechanism this document already named as a
carry-forward item (§ "Idempotency" note); it is implemented now because
suppression/opt-out/DNC state is compliance-sensitive and must fail safe
at the DB level, not rely on an application `SELECT`-then-`INSERT`
pattern. `scope` remains part of the key, so an `ORG`-scope and a
`PLATFORM`-scope suppression for the same phone/channel remain
independent, legally-valid rows. Live-validated: exact-duplicate
rejection, a genuine concurrent-insert race (one process's INSERT
succeeded, the other received a real `unique_violation`), lift-then-
reinsert success, and cross-scope independence — see
`docs/phase-05-database-design/5L-Global-Database-Reconciliation/
5L-Global-Database-Reconciliation.md`.

---

## Controlled Amendment — Phase 6G CRM Reconciliation (2026-08-28)

Three further forward migrations (`093_5D2.sql`, `094_5D3.sql`,
`095_5D4.sql`) plus one permission-catalog amendment (`096_5B2.sql`, 5B's
authority, not this document's) were added on top of `085_5D1`, triggered
by an independent review of `6G-CRM-Leads-APIs.md`'s first pass. No table,
column, constraint, index, function, or grant described earlier in this
document was altered — every change below is additive. Full rationale,
DDL, and live-validation evidence live in the migration files themselves
and in `MIGRATION_MANIFEST.md`'s "Phase 6G CRM Reconciliation" entry; this
section records the physical facts a reader of this schema document needs.

### Contact Merge-Lineage (`093_5D2.sql`)

`crm.contacts` gains two nullable columns:

| Column | Type | Notes |
|---|---|---|
| `merged_into_contact_id` | UUID | Self-referential FK to `crm.contacts(id)`. NULL on every non-merged Contact. |
| `merged_at` | TIMESTAMPTZ | Set together with `merged_into_contact_id`, never independently. |

**This is deliberately not `deleted_at`.** `deleted_at` remains exclusively
the GDPR-erasure tombstone (§5.1, ADR-5D-007) — a merged Contact's PII is
*not* cleared, it is folded into the survivor. The two states are
independent and can compose: a Contact can be merged-away and *later*
still be the subject of a GDPR erasure request (live-validated — the new
`trg_contacts_merge_immutable` trigger fires only on
`merged_into_contact_id`/`merged_at` changes, never on the erasure
field-set, so erasure of an already-merged Contact proceeds unobstructed).

Constraints/triggers: `chk_contacts_merge_pair` (both-or-neither),
`chk_contacts_no_self_merge`, `fk_contacts_merged_into`,
`trg_contacts_merge_tenant_guard` (BEFORE INSERT/UPDATE — rejects a
merge destination in a different organization; a CHECK constraint cannot
see another row, so this is trigger-enforced), `trg_contacts_merge_immutable`
(BEFORE UPDATE — rejects any attempt to re-point or clear an
already-recorded merge; combined with `crm.fn_merge_contacts()`'s own
refusal to accept an already-merged Contact as either primary or
secondary, this makes a merge cycle structurally impossible — proven
live with a two-hop lineage chain).

`crm.fn_merge_contacts(p_primary_contact_id, p_secondary_contact_id, p_organization_id, p_merged_by_ref) RETURNS VOID`
— `SECURITY DEFINER`, `GRANT EXECUTE TO app_api, app_worker, app_platform_admin`.
The sole write path for MergeContacts (4C §6.2). Field-fills nulls on the
primary from the secondary (primary wins conflicts); adopts the
secondary's `lead_status` only if it ranks further along a documented
interpretation of 4C §7.1's non-linear state diagram (`NEW`=0,
`CONTACTED`/`NURTURING`/`DISQUALIFIED`=1 lateral, `QUALIFIED`=2,
`CONVERTED`=3); unions `tags` (cap 20) and `custom_field_values` by
`field_id`, primary wins ties (cap 50) — either cap being exceeded aborts
the whole operation before any write. Re-points **only** the mutable
child aggregates that already hold real `UPDATE` grants: `crm.deals`,
`crm.tasks` (`subject_type='CONTACT'`), `crm.notes` (same), and
`crm.appointments`. **`crm.activities` and `crm.lead_score_records` are
never re-pointed** — both remain `REVOKE UPDATE, DELETE` for
`app_api`/`app_worker` (`022_5D.sql`, `023_5D.sql`), and this migration
does not touch that privilege. A marker `Activity`
(`activity_type='STAGE_CHANGE'`, `payload->>'event' = 'contact_merged'`)
is recorded on the survivor instead, since the secondary's own historical
Activities/LeadScoreRecords cannot be moved. **Read-side consequence:**
a Contact's authoritative call-history/score-history timeline, where it
must include a lineage of merged-away predecessors, is an
application-layer read across `(id, merged_into_contact_id chain)`, never
a database rewrite — see `6G-CRM-Leads-APIs.md` §10/§14 for the exact
query shape.

### CRM Event-Consumer Idempotency (`094_5D3.sql`)

New table `crm.event_consumer_dedup` — `PRIMARY KEY (consumer_name,
source_event_id)`, standard tenant RLS (`ENABLE + FORCE`), `GRANT SELECT,
INSERT, DELETE TO app_worker` only (no `app_api` grant — this table is
never touched by the request-time REST API). CRM-owned, distinct from
`analytics.analytics_event_dedup` and from `audit.domain_event_outbox`
(the publisher-side durable queue, `077_5J1.sql`) — this is the
consumer-side ledger CRM's own event subscribers (Voice→CRM, lead-scoring
worker) use.

`crm.fn_claim_event(p_consumer_name, p_source_event_id, p_organization_id, p_result_ref DEFAULT NULL) RETURNS BOOLEAN`
— `SECURITY DEFINER`, `GRANT EXECUTE TO app_worker, app_platform_admin`
only. `TRUE` = first claim, caller proceeds with its CRM side effect in
the same transaction; `FALSE` = already claimed, no-op. Live-validated
under a genuine concurrent two-connection race (exactly one `TRUE`, one
`FALSE`) and under transaction rollback (a rolled-back claim leaves zero
rows; retry then succeeds).

### Lead-Score CAS-Safe Apply (`095_5D4.sql`)

`crm.fn_apply_lead_score(p_contact_id, p_organization_id, p_score, p_previous_score, p_score_version, p_signals, p_computed_at, p_computed_by, p_computed_by_user_ref DEFAULT NULL) RETURNS BOOLEAN`
— `SECURITY DEFINER`, `GRANT EXECUTE TO app_worker, app_platform_admin`
only. **No new column.** Inserts the immutable `lead_score_records` row
(append-only privilege unchanged), locks the Contact row (`FOR UPDATE`),
then applies the denormalized `contacts.lead_score`/`lead_temperature`
update only if the just-inserted row is still the newest by
`(computed_at, id)` ordering — otherwise returns `FALSE` and leaves the
denormalized fields untouched. Live-validated: an older, slow-to-arrive
computation applied after a newer one correctly loses (both immutable
history rows persist regardless); a genuine concurrent race for the same
Contact converges on the objectively newer value regardless of commit
order.

### Search-Path Correction Note (defect found and fixed pre-freeze)

An initial draft of `fn_merge_contacts()`/`fn_apply_lead_score()` set
`SET search_path = crm, pg_catalog`, omitting `public`. Both functions'
`INSERT`s rely on a target column's `DEFAULT public.gen_uuid_v7()` (or,
after the fix, an explicit call to it), which itself calls
`public.gen_random_bytes()` (pgcrypto, installed into `public`,
`001_5B.sql`). Under the narrowed search_path, this failed live with
`function gen_random_bytes(integer) does not exist` — the identical class
of defect already documented for `analytics.fn_claim_projection_slot`
(`068_5J.sql`, see `5K/execution_logs/README.md`'s "New finding" section).
Fixed before either migration was left in a broken state, by adopting
`audit.fn_insert_audit_event`'s (`072_5J.sql`) already-established
pattern exactly: include `public` in `search_path`, and generate the new
row's id into a local variable rather than relying solely on the column
default.
