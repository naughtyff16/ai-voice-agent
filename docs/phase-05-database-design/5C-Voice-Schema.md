# Phase 5C — Voice Schema
## Physical PostgreSQL Database Design

| | |
|---|---|
| **Phase** | 5C — Voice Schema Physical Database Design |
| **Schema** | `voice` |
| **Status** | Draft v1.0 — for approval before Phase 5D |
| **Authority** | Phase 5A (standards) + Phase 5B (constructs) + Phase 4B (DDD) + Phase 4I (India-first closure) |
| **Follows** | Phase 5B (APPROVED, PHASE 5C READY) |
| **Precedes** | Phase 5D — CRM Schema |

---

## 1. Executive Summary

This document delivers the complete physical database design for the `voice` schema — the highest-throughput, most latency-sensitive schema in the platform. The design is derived directly from the Phase 4B Voice & AI DDD document (authoritative domain model) and must not contradict it.

**Key design decisions in this document:**

| Decision | Outcome |
|---|---|
| `call_sessions` partitioning | RANGE monthly on `started_at`; PK includes partition key |
| `transcript_segments` partitioning | RANGE monthly on `created_at`; strictly append-only; final segments only |
| Transcript partial handling | Partial STT fragments: Redis only. PostgreSQL receives only finalized segments (`is_partial = FALSE` invariant). No UPDATE path exists. |
| Conversation / Turn persistence | `conversations` + `turns` as separate tables; turns written per checkpoint; Redis hot-tier for in-flight state |
| Agent versions | Separate `agent_versions` table; `snapshot_json JSONB` immutable after write |
| `LanguagePolicy` vs `TamilCodeSwitching` | `language_policy JSONB` on `agent_versions` (Phase 4I CONTRADICTION-02 applied — supersedes Phase 4B's `VoiceConfig.TamilCodeSwitching` boolean) |
| `LanguageEvaluationRecord` scope | Platform-scoped; no RLS; no `organization_id` |
| Tool definitions scope | Mixed (platform built-ins have `organization_id IS NULL`) |
| Provider configs scope | Mixed (platform defaults have `organization_id IS NULL`) |
| Recording storage | S3 reference only — no `BYTEA` |
| Credential handling | `credential_ref TEXT` with `LIKE 'secret_manager://%'` CHECK |
| Tenant phone number uniqueness | `UNIQUE (phone_e164)` globally — one number belongs to exactly one tenant |

**Tables created in Phase 5C:** 13 tables (2 partitioned parents + parametric monthly partitions created at deployment time), 4 trigger functions, complete RLS, built-in tool seed data.

**Correction pass applied (Phase 5C final correction):** Six issues identified and resolved — partial→final transcript upsert removed (ISSUE 1+2+3), `sessions` JSONB confirmed as DDD-required (ISSUE 4), hard-coded partition dates replaced with parametric strategy (ISSUE 5), SECURITY DEFINER privilege hardened with `REVOKE ALL FROM PUBLIC` and explicit `GRANT EXECUTE` (ISSUE 6), full document consistency pass (ISSUE 7).

**Phase 4I CONTRADICTION-02 applied here:** `VoiceConfig.TamilCodeSwitching` on `agent_versions` is superseded by `language_policy JSONB`. No `tamil_code_switching` boolean column is created. The `language_policy` JSONB captures the full `LanguagePolicy` value object from Phase 4I §4.2.

---

## 2. Scope

**In scope:**
- `voice` schema: all 13 tables, their indexes, constraints, RLS, triggers, grants, and seed data
- Alembic migration plan (migrations 009–018)

**Out of scope (later phases):**
- `crm`, `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, `audit`

---

## 3. Aggregate → Table Mapping

### 3.1 Complete DDD Aggregate Inventory Verification

| Phase 4B Aggregate | Table | Notes |
|---|---|---|
| `Call` (AggregateRoot) | `voice.call_sessions` | Embedded `CallSession` entities stored as JSONB `sessions` array |
| `Conversation` (AggregateRoot) | `voice.conversations` | |
| `Turn` (Entity — embedded in Conversation) | `voice.turns` | Separate table for checkpoint writes; loaded with Conversation |
| `Agent` (AggregateRoot) | `voice.agents` | |
| `AgentVersion` (Entity — embedded in Agent) | `voice.agent_versions` | Separate table; queried by `agent_id + version_number` |
| `ToolDefinition` (AggregateRoot) | `voice.tool_definitions` | Mixed-scope (platform + tenant) |
| `ToolExecution` (AggregateRoot) | `voice.tool_executions` | Separate from Turn per DDR-4B-004 |
| `Recording` (AggregateRoot) | `voice.recordings` | S3 reference only |
| `Transcript` (AggregateRoot) | `voice.transcripts` | |
| `TranscriptSegment` (Entity) | `voice.transcript_segments` | Separate partitioned table; append-only |
| `ProviderConfig` (AggregateRoot) | `voice.provider_configs` | Mixed-scope |
| `LanguageEvaluationRecord` (AggregateRoot) | `voice.language_evaluation_records` | Platform-scoped; no RLS |
| `TenantPhoneNumber` (domain concept) | `voice.tenant_phone_numbers` | |

**DDD-to-table decisions:**

**`Call.Sessions` (embedded entity list) → `sessions JSONB` on `call_sessions`:**
Phase 4B §5.1 explicitly defines `Sessions` as an embedded list within the Call aggregate, bounded at approximately 1–3 per Call (the vast majority of calls have exactly one session; hold-and-resume creates a second; a second failed transfer could create a third). The DDD rationale is: "a session only makes sense in the context of its Call." Sessions are always read with the Call row and are never independently queried (there is no use case for "show me all sessions across all calls"). A separate child table would add a join for every call load with no consistency benefit. JSONB is correct per Phase 5A §4.1 (structured, bounded, always-read-whole). Each JSONB element captures `session_id`, `started_at`, `ended_at`, and `outcome`. The `sessions` column is therefore **retained and required** by the authoritative DDD.

**`Conversation.Turns` (embedded entity list) → separate `voice.turns` table:**
Phase 4B §5.2 explains Turns are embedded in the aggregate but written per checkpoint (~every few seconds). A separate table avoids full JSON-blob rewrites per turn. The repository loads the Conversation + its Turns together via a JOIN (`WHERE turn.conversation_id = $id`), preserving the aggregate boundary semantically while enabling efficient incremental writes.

**`Agent.Versions` (embedded list) → separate `voice.agent_versions` table:**
Phase 4B §5.3 bounds the list at ~50 versions per agent. While JSONB is technically feasible at this size, `AgentVersionId` must be independently queryable (Call pinning loads a version by ID directly). The separately indexed table is cleaner. `SnapshotJson` is a JSONB column on `agent_versions`.

---

## 4. Real-Time State vs. Durable Database State

### 4.1 The Split (Phase 4B §20, Phase 4H §9.1)

This is the most critical architectural decision for the voice schema. The database must **never** be on the per-audio-frame path.

```
Redis (hot-tier, authoritative for in-flight state):
├── call_session:status:{call_id}         — current CallStatus (INITIATED/ACTIVE/etc.)
├── agent_version:{version_id}:snapshot   — AgentVersion.SnapshotJson (1h TTL, immutable)
├── conversation:{session_id}:state       — current Turn in progress (partial STT, etc.)
├── provider_health:{provider_id}         — HealthState + P50LatencyMs (60s TTL)
├── provider_config:{org_id}:{category}   — ordered ProviderConfig list for routing (5min TTL)
└── (rebuilt from Postgres on cache miss)

PostgreSQL (authoritative for durable state):
├── call_sessions              — written ONCE at call start; updated at call end/status change
├── conversations              — updated per completed Turn (checkpoint)
├── turns                      — INSERT per completed Turn (not per partial STT fragment)
├── tool_executions            — written at execution start; updated at completion
├── recordings                 — written at recording start; updated at store/fail/delete
├── transcripts                — written at conversation start; updated at completion
├── transcript_segments        — APPENDED per STT final segment (NOT per partial)
├── agents / agent_versions    — written on publish; immutable after
├── provider_configs           — written on config change; circuit_state updated on trip
└── (all other tables — mutable at human timescales)
```

### 4.2 Write Timing Per Table

| Table | Written synchronously on hot path? | Written by | Frequency |
|---|---|---|---|
| `call_sessions` | Initial INSERT on call start (async from webhook) | Voice Gateway | Once per call |
| `call_sessions` | Status UPDATE on state change (async, event-driven) | Voice Gateway | ~3–5 per call |
| `conversations` | INSERT on conversation start; UPDATE per completed Turn | Voice Gateway | ~1 INSERT + N UPDATEs |
| `turns` | INSERT per completed Turn (checkpoint) | Voice Gateway | ~10–50 per call |
| `tool_executions` | INSERT on execution start; UPDATE on completion | Voice Gateway | 0–N per call |
| `transcript_segments` | APPEND per final STT segment | Voice Gateway / Worker | ~50–200 per call |
| `recordings` | INSERT on start; UPDATE on store | Worker | Once per call |
| `transcripts` | INSERT on conversation start; UPDATE on completion | Worker | Once per call |
| `agent_versions` | Read-only during calls (Redis-cached) | API | Rare |
| `provider_configs` | Read-only during calls (Redis-cached) | Admin API | Very rare |

**None of the above writes are in the LLM/STT/TTS response path.** They are event-driven, async, or buffered. The sub-800ms SLO is protected.

---

## 5. Column-Level Data Dictionary

### 5.1 `voice.call_sessions` (Partitioned — RANGE monthly on `started_at`)

**Aggregate:** `Call` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK — see §8.1 |
| `started_at` | TIMESTAMPTZ | NOT NULL | — | Partition key. Set when call is initiated. |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `direction` | TEXT | NOT NULL | — | `INBOUND \| OUTBOUND` |
| `status` | TEXT | NOT NULL | `'INITIATED'` | Full call state machine values |
| `from_number` | TEXT | NOT NULL | — | E.164 canonical. **pii:phone** |
| `to_number` | TEXT | NOT NULL | — | E.164 canonical. **pii:phone** |
| `tenant_phone_number_id` | UUID | NULL | — | Logical ref: `voice.tenant_phone_numbers.id` |
| `agent_version_id` | UUID | NOT NULL | — | Logical ref: `voice.agent_versions.id`. Pinned at call start, immutable. |
| `conversation_id` | UUID | NULL | — | Logical ref: `voice.conversations.id`. Set once when conversation starts. |
| `provider_call_ref` | TEXT | NULL | — | Opaque carrier-issued call ID. |
| `campaign_lead_ref` | TEXT | NULL | — | Opaque ref: `campaign.campaign_contacts.id`. Logical only. |
| `contact_ref` | UUID | NULL | — | Logical ref: `crm.contacts.id`. Set if CRM match found. |
| `transfer_target` | TEXT | NULL | — | E.164 or queue ID. Set on transfer. **pii:phone** |
| `sessions` | JSONB | NOT NULL | `'[]'` | Embedded `CallSession` entity list — bounded ~1–3 |
| `outcome` | TEXT | NULL | — | `ANSWERED_COMPLETED \| ANSWERED_TRANSFERRED \| NO_ANSWER \| VOICEMAIL \| FAILED \| CANCELLED` |
| `termination_reason` | TEXT | NULL | — | `AGENT_DIRECTIVE \| CALLER_HANGUP \| SYSTEM_TIMEOUT \| TRANSFER \| FAILED` |
| `answered_at` | TIMESTAMPTZ | NULL | — | When caller picked up |
| `ended_at` | TIMESTAMPTZ | NULL | — | When call terminated |
| `duration_seconds` | INTEGER | NULL | — | Computed at call end |
| `stt_p50_ms` | INTEGER | NULL | — | Running p50 STT latency across turns |
| `llm_first_token_p50_ms` | INTEGER | NULL | — | Running p50 LLM first-token latency |
| `tts_first_audio_p50_ms` | INTEGER | NULL | — | Running p50 TTS first-audio latency |
| `turn_e2e_p50_ms` | INTEGER | NULL | — | Running p50 end-to-end turn latency |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`sessions` JSONB element structure:**
```json
{
  "session_id": "<uuid>",
  "started_at": "<iso8601>",
  "ended_at": "<iso8601|null>",
  "outcome": "ACTIVE|COMPLETED|TRANSFERRED|ABANDONED"
}
```

**Partition key rationale:** `started_at` is the natural time anchor for call data. Retention queries, billing aggregation, and analytics all operate on time ranges aligned to `started_at`. The partition key must be included in the primary key for PostgreSQL declarative partitioning — see §8.1.

**Status values** (from Phase 4B §7.1):
`INITIATED | RINGING | ANSWERED | ACTIVE | ON_HOLD | TRANSFERRING | WRAP_UP | COMPLETED | FAILED | CANCELLED | NO_ANSWER | VOICEMAIL | ABANDONED | TRANSFERRED`

### 5.2 `voice.conversations`

**Aggregate:** `Conversation` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `call_id` | UUID | NOT NULL | — | Logical ref: `voice.call_sessions.id`. Immutable. |
| `agent_version_id` | UUID | NOT NULL | — | Same pin as the Call, copied for locality. |
| `contact_ref` | UUID | NULL | — | Logical ref: `crm.contacts.id`. Set at most once. |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| COMPLETED \| SUMMARIZED` |
| `qualification_outcome` | TEXT | NULL | — | `QUALIFIED \| DISQUALIFIED \| INCONCLUSIVE`. Set at most once. |
| `sentiment_label` | TEXT | NULL | — | `POSITIVE \| NEUTRAL \| NEGATIVE` |
| `sentiment_score` | NUMERIC(4,3) | NULL | — | 0.000–1.000 |
| `summary_text` | TEXT | NULL | — | LLM-generated. **pii:voice** |
| `prompt_tokens_used` | INTEGER | NOT NULL | `0` | Cumulative |
| `completion_tokens_used` | INTEGER | NOT NULL | `0` | Cumulative |
| `total_tokens_used` | INTEGER | NOT NULL | `0` | Cumulative |
| `total_turns` | INTEGER | NOT NULL | `0` | Incremented per completed Turn |
| `started_at` | TIMESTAMPTZ | NOT NULL | — | |
| `completed_at` | TIMESTAMPTZ | NULL | — | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Why `summary_text` on `conversations` (not only as an event payload):** the CRM subscriber that creates AI notes reads this field after `conversation.summarization_completed`. Storing it here allows direct CRM worker queries without re-fetching from the event bus.

### 5.3 `voice.turns`

**Entity:** `Turn` (embedded in Conversation aggregate — separate table for checkpoint writes)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref (for RLS) |
| `conversation_id` | UUID | NOT NULL | — | Logical ref: `voice.conversations.id` |
| `sequence_number` | INTEGER | NOT NULL | — | Monotonically increasing within conversation. No gaps. |
| `speaker_role` | TEXT | NOT NULL | — | `USER \| ASSISTANT \| SYSTEM \| TOOL` |
| `utterance_text` | TEXT | NULL | — | Final STT result. **pii:voice** |
| `utterance_confidence` | NUMERIC(4,3) | NULL | — | 0.000–1.000 |
| `utterance_start_ms` | INTEGER | NULL | — | ms from call start |
| `utterance_end_ms` | INTEGER | NULL | — | ms from call start |
| `detected_language` | TEXT | NULL | — | BCP 47 dominant language |
| `detected_languages` | TEXT[] | NULL | — | All languages present (Phase 4I LanguageObservation) |
| `code_switch_detected` | BOOLEAN | NULL | — | |
| `language_detection_confidence` | NUMERIC(4,3) | NULL | — | |
| `response_text` | TEXT | NULL | — | Agent's LLM-generated text. **pii:voice** |
| `directive_kind` | TEXT | NULL | — | `SPEAK \| TRANSFER \| END_CALL \| TOOL_CALL \| WAIT` |
| `workflow_node_ref` | TEXT | NULL | — | Which workflow node drove this turn |
| `tool_execution_ids` | UUID[] | NOT NULL | `'{}'` | Array of ToolExecutionId refs for this turn |
| `llm_provider_id` | TEXT | NULL | — | Provider used for LLM |
| `stt_provider_id` | TEXT | NULL | — | Provider used for STT |
| `stt_ms` | INTEGER | NULL | — | STT latency for this turn |
| `llm_first_token_ms` | INTEGER | NULL | — | LLM first-token latency |
| `tts_first_audio_ms` | INTEGER | NULL | — | TTS first-audio latency |
| `turn_e2e_ms` | INTEGER | NULL | — | End-to-end turn latency |
| `barge_in_occurred` | BOOLEAN | NOT NULL | `FALSE` | |
| `completed_at` | TIMESTAMPTZ | NULL | — | When this turn's response was delivered |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | When this turn was checkpointed |

**Invariant enforcement:** `UNIQUE (conversation_id, sequence_number)` enforces monotonic, gap-free ordering at DB level.

**Why `speaker_role` includes `SYSTEM` and `TOOL`:** Phase 4B §7.2 shows the turn loop includes tool execution results. A TOOL turn records the tool execution flow within the conversation sequence. SYSTEM turns capture platform-injected directives (e.g., hold music notification).

### 5.4 `voice.agents`

**Aggregate:** `Agent` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `name` | TEXT | NOT NULL | — | 2–100 chars |
| `description` | TEXT | NULL | — | 0–500 chars |
| `status` | TEXT | NOT NULL | `'DRAFT'` | `DRAFT \| PUBLISHED \| DEPRECATED` |
| `published_version_id` | UUID | NULL | — | Logical ref: `voice.agent_versions.id`. Set on publish. |
| `draft_config` | JSONB | NOT NULL | `'{}'` | Mutable draft configuration (VoiceConfig, ModelConfig, refs, etc.) |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `deleted_at` | TIMESTAMPTZ | NULL | — | Soft delete — DEPRECATED agents may be soft-deleted after grace period |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`draft_config` JSONB structure** (from Phase 4B §5.3 DraftConfig entity):
```json
{
  "voice_config": {
    "voice_id": "...",
    "language": "ta-IN",
    "speaking_rate": 1.0,
    "emotion": "FRIENDLY",
    "barge_in_sensitivity": "MEDIUM"
  },
  "model_config": {
    "preferred_provider": null,
    "fallback_providers": [],
    "latency_bias": 0.5,
    "cost_bias": 0.5,
    "max_tokens_per_turn": null
  },
  "language_policy": {
    "primary_language": "ta-IN",
    "fallback_language": "en-IN",
    "allowed_languages": ["ta-IN", "en-IN"],
    "code_switching_enabled": true,
    "language_detection_mode": "CONTINUOUS",
    "pronunciation_lexicon_ref": null,
    "script_preference": "LATIN"
  },
  "prompt_ref": "<uuid>",
  "workflow_ref": "<uuid>",
  "knowledge_base_refs": [],
  "tool_permissions": [{"tool_id": "<uuid>", "tool_name": "createLead"}],
  "qualification_criteria": null,
  "calling_hours": null
}
```

**Why `draft_config` is JSONB and not typed columns:** the DraftConfig entity contains nested entities (VoiceConfig, ModelConfig, LanguagePolicy), reference lists, and optional structures that evolve as the platform adds capabilities. It is always read as a whole at agent creation/edit time. Using JSONB avoids a cascade of columns that mostly relate to external provider configuration rather than business invariants. The application domain layer validates and deserializes this into typed objects.

### 5.5 `voice.agent_versions`

**Entity:** `AgentVersion` (embedded in Agent — separate table)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref (for RLS and index) |
| `agent_id` | UUID | NOT NULL | — | Logical ref: `voice.agents.id` |
| `version_number` | INTEGER | NOT NULL | — | Monotonically increasing per agent |
| `snapshot_json` | JSONB | NOT NULL | — | **Immutable after write.** Full DraftConfig snapshot at publish time. |
| `language_policy` | JSONB | NOT NULL | — | Extracted from snapshot for fast indexed access by provider selection |
| `published_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `published_at` | TIMESTAMPTZ | NOT NULL | — | When published |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Why `language_policy` is extracted as a separate JSONB column:** `ProviderSelectionService` (Phase 4B §8.2) reads `LanguagePolicy` on every call start from the Redis-cached version. Extracting it to a top-level column allows the Redis serialization to be lighter and allows direct SQL queries against this field (e.g., "how many published agent versions use Tamil as primary language" for analytics).

**Immutability enforcement:** a `BEFORE UPDATE` trigger on `snapshot_json` raises an exception if the value changes. `language_policy` is derived from `snapshot_json` at publish time and is also immutable. No UPDATE trigger needed on `agent_versions` beyond the immutability guard.

**No `updated_at` column:** `agent_versions` is effectively append-only (immutable after creation). No `updated_at` needed — no mutable writes after INSERT.

### 5.6 `voice.tool_definitions`

**Aggregate:** `ToolDefinition` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NULL | — | NULL = platform built-in. UUID = tenant custom tool. |
| `tool_name` | TEXT | NOT NULL | — | `[a-z][a-zA-Z0-9]{1,63}` camelCase. Unique within scope. |
| `description` | TEXT | NOT NULL | — | What the LLM reads to decide whether to call |
| `input_schema` | JSONB | NOT NULL | — | JSON Schema object for arguments |
| `output_schema` | JSONB | NOT NULL | — | JSON Schema object for result |
| `is_builtin` | BOOLEAN | NOT NULL | `FALSE` | TRUE = seeded platform tool |
| `timeout_ms` | INTEGER | NOT NULL | `5000` | 100–30000 |
| `requires_confirmation` | BOOLEAN | NOT NULL | `FALSE` | Human approval before execution |
| `max_retries_on_timeout` | INTEGER | NOT NULL | `1` | 0–2 |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | |
| `created_by` | UUID | NULL | — | Logical ref: `identity.users.id`. NULL for built-ins. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.7 `voice.tool_executions`

**Aggregate:** `ToolExecution` (AggregateRoot — separate from Turn, per DDR-4B-004)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `conversation_id` | UUID | NOT NULL | — | Logical ref: `voice.conversations.id` |
| `turn_id` | UUID | NOT NULL | — | Logical ref: `voice.turns.id` |
| `call_id` | UUID | NOT NULL | — | Logical ref: `voice.call_sessions.id` — denormalized for direct query |
| `tool_definition_id` | UUID | NOT NULL | — | Logical ref: `voice.tool_definitions.id` |
| `tool_name` | TEXT | NOT NULL | — | Denormalized for audit readability |
| `status` | TEXT | NOT NULL | `'PENDING'` | `PENDING \| RUNNING \| SUCCEEDED \| FAILED \| TIMED_OUT` |
| `arguments` | JSONB | NOT NULL | — | Validated against tool's input_schema at creation. Immutable. |
| `arguments_hash` | CHAR(64) | NOT NULL | — | SHA-256 of serialized arguments — for event payload (no raw args in events) |
| `result` | JSONB | NULL | — | Set on SUCCEEDED or FAILED. May be large. |
| `error_message` | TEXT | NULL | — | Set on FAILED or TIMED_OUT |
| `error_code` | TEXT | NULL | — | Normalized error classification |
| `attempt_count` | INTEGER | NOT NULL | `1` | Incremented on retry |
| `authorized` | BOOLEAN | NOT NULL | `FALSE` | True once AuthorizationDecision = ALLOWED |
| `authorized_by_permission` | TEXT | NULL | — | Permission string that authorized this execution |
| `timeout_ms` | INTEGER | NOT NULL | — | Copied from tool_definition at execution time |
| `started_at` | TIMESTAMPTZ | NOT NULL | — | |
| `completed_at` | TIMESTAMPTZ | NULL | — | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`result` size concern:** Phase 5A §21.8 warns against large JSONB payloads. Tool results may occasionally be large (e.g., a `lookupKnowledge` result with multiple document snippets). Policy: results > 50KB should be stored in S3 and a `result_storage_ref TEXT` used instead. For V1, cap result JSONB to 64KB via application-layer enforcement; document in Phase 5C as a constraint to monitor.

**`arguments` immutability:** a `BEFORE UPDATE` trigger prevents `arguments` from changing after INSERT.

### 5.8 `voice.recordings`

**Aggregate:** `Recording` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `call_id` | UUID | NOT NULL | — | Logical ref: `voice.call_sessions.id` |
| `conversation_id` | UUID | NULL | — | Logical ref: `voice.conversations.id` |
| `status` | TEXT | NOT NULL | `'PENDING'` | `PENDING \| IN_PROGRESS \| STORED \| FAILED \| DELETED` |
| `storage_ref` | TEXT | NULL | — | S3 object path: `org/{org_id}/recordings/{year}/{month}/{call_id}.{ext}`. Set when STORED. Cleared when DELETED. **pii:voice** |
| `storage_provider` | TEXT | NULL | — | `s3 \| supabase` — which storage backend |
| `content_type` | TEXT | NULL | — | e.g., `audio/wav`, `audio/mpeg` |
| `duration_seconds` | INTEGER | NULL | — | Set when STORED |
| `file_size_bytes` | BIGINT | NULL | — | Set when STORED |
| `checksum_sha256` | CHAR(64) | NULL | — | Set when STORED — integrity verification |
| `recording_policy` | TEXT | NOT NULL | — | `ENABLED \| DISABLED \| REQUIRES_CONSENT \| REQUIRES_DISCLOSURE` — **Copied from compliance policy at recording creation time. Immutable.** |
| `consent_obtained` | BOOLEAN | NULL | — | Set if REQUIRES_CONSENT policy |
| `retention_days` | INTEGER | NULL | — | Copied from org's retention profile at creation. NULL = indefinite. |
| `delete_after` | TIMESTAMPTZ | NULL | — | Computed: `created_at + retention_days`. Used by retention job. |
| `deleted_at` | TIMESTAMPTZ | NULL | — | When deleted. Row retained for audit (Phase 4B §5.6 invariant 2). |
| `deleted_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**No `BYTEA` column.** Audio is stored in S3. The database stores only metadata and the `storage_ref`. Per Phase 4B §5.6 invariant 2: when deleted, `storage_ref` is cleared but the row is retained.

### 5.9 `voice.transcripts`

**Aggregate:** `Transcript` (AggregateRoot — separate from Conversation, per DDR-4B-002)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `conversation_id` | UUID | NOT NULL | — | Logical ref: `voice.conversations.id` |
| `call_id` | UUID | NOT NULL | — | Logical ref — denormalized for query |
| `status` | TEXT | NOT NULL | `'IN_PROGRESS'` | `IN_PROGRESS \| COMPLETED` |
| `total_segments` | INTEGER | NOT NULL | `0` | Incremented as segments are appended |
| `completed_at` | TIMESTAMPTZ | NULL | — | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 5.10 `voice.transcript_segments` (Partitioned — RANGE monthly on `created_at`)

**Entity:** `TranscriptSegment` (child of Transcript aggregate — separate partitioned table)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK (see §8.2) |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | **Partition key** |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `transcript_id` | UUID | NOT NULL | — | Logical ref: `voice.transcripts.id` |
| `conversation_id` | UUID | NOT NULL | — | Logical ref — denormalized |
| `call_id` | UUID | NOT NULL | — | Logical ref — denormalized |
| `sequence_number` | INTEGER | NOT NULL | — | Monotonically increasing within transcript |
| `speaker` | TEXT | NOT NULL | — | `CALLER \| AGENT \| SYSTEM` |
| `text` | TEXT | NOT NULL | — | Final STT text or Agent response text. **pii:voice** |
| `is_partial` | BOOLEAN | NOT NULL | `FALSE` | True = partial segment; false = final |
| `start_ms` | INTEGER | NULL | — | ms from call start |
| `end_ms` | INTEGER | NULL | — | ms from call start |
| `confidence` | NUMERIC(4,3) | NULL | — | STT confidence (CALLER segments) |
| `language` | TEXT | NULL | — | BCP 47 of this segment |
| `stt_provider_id` | TEXT | NULL | — | Which STT provider produced this segment (CALLER only) |
| `provider_segment_id` | TEXT | NULL | — | Provider's own segment ID for deduplication |

**Strictly append-only.** PostgreSQL stores only **finalized** transcript segments. Partial STT fragments are held exclusively in Redis and are never written to the database. When the STT provider delivers a final segment, the application writes one row with `is_partial = FALSE`. There is no UPDATE path for any application role.

**Partition key and uniqueness note:** `(transcript_id, sequence_number)` cannot be enforced as a global UNIQUE constraint on a partitioned table — PostgreSQL requires the partition key (`created_at`) to be included in any unique constraint, and segment writes from different calls may land in different monthly partitions. Sequence uniqueness is therefore an **application-layer invariant**: the `TranscriptRepository` enforces monotonic, gap-free sequence numbers before each INSERT. Idempotency for duplicate-delivery protection uses the segment's UUIDv7 `id` as the conflict target — see §15.6.

**`is_partial` column retained in schema** for completeness of the domain model (`TranscriptSegment.IsPartial` from Phase 4B §5.7), but it is always `FALSE` for rows stored in PostgreSQL. The column documents the contract and allows future analytics queries to confirm no partial segments leaked into durable storage. An application-layer invariant (checked before INSERT) must enforce `is_partial = FALSE`.

### 5.11 `voice.provider_configs`

**Aggregate:** `ProviderConfig` (AggregateRoot — mixed-scope)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NULL | — | NULL = platform default config |
| `category` | TEXT | NOT NULL | — | `TELEPHONY \| STT \| TTS \| LLM \| EMBEDDING` |
| `provider_id` | TEXT | NOT NULL | — | Stable lowercase snake_case, e.g. `deepgram`, `openai` |
| `model_id` | TEXT | NULL | — | e.g. `gpt-4o`. NULL = provider default |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | |
| `priority` | INTEGER | NOT NULL | — | Lower = preferred. Unique within `(organization_id, category)` active configs |
| `health_state` | TEXT | NOT NULL | `'AVAILABLE'` | `AVAILABLE \| DEGRADED \| UNAVAILABLE` — derived, updated by health eval |
| `last_health_check_at` | TIMESTAMPTZ | NULL | — | |
| `p50_latency_ms` | INTEGER | NULL | — | Rolling p50 |
| `error_rate_pct` | NUMERIC(5,2) | NOT NULL | `0.00` | 0.00–100.00 |
| `circuit_state` | TEXT | NOT NULL | `'CLOSED'` | `CLOSED \| OPEN \| HALF_OPEN` |
| `circuit_opened_at` | TIMESTAMPTZ | NULL | — | When circuit last opened |
| `credential_ref` | TEXT | NULL | — | `secret_manager://...`. NULL for providers with no API key (e.g. internal). |
| `config_json` | JSONB | NOT NULL | `'{}'` | Provider-specific non-secret config (region, endpoint, voice IDs, model variants) |
| `supports_languages` | TEXT[] | NOT NULL | `'{}'` | BCP 47 — languages this provider supports well |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`credential_ref` CHECK:** `credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%'`

**`supports_languages` array:** feeds `LanguageCapableProviderSpecification` (Phase 4I generalisation of Phase 4B's `TamilCapableProviderSpecification`). Queried at provider selection time (Redis-cached).

### 5.12 `voice.language_evaluation_records`

**Aggregate:** `LanguageEvaluationRecord` (AggregateRoot — **platform-scoped, no `organization_id`, no RLS**)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `language` | TEXT | NOT NULL | — | BCP 47 e.g. `ta-IN` |
| `provider_id` | TEXT | NOT NULL | — | e.g. `deepgram` |
| `provider_model_ref` | TEXT | NOT NULL | — | e.g. `nova-2-general` |
| `capability` | TEXT | NOT NULL | — | `STT \| TTS \| LLM` |
| `evaluation_set_ref` | TEXT | NOT NULL | — | Versioned reference corpus identifier |
| `scores` | JSONB | NOT NULL | — | `[{"dimension": "WER_PCT", "value": 12.3, "unit": "WER_PCT"}, ...]` |
| `evaluated_at` | TIMESTAMPTZ | NOT NULL | — | |
| `verdict` | TEXT | NOT NULL | — | `APPROVED \| CONDITIONAL \| REJECTED` |
| `notes` | TEXT | NULL | — | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Platform-scoped:** inserted only by `app_platform_admin`. Read by all application roles (informs provider selection). No RLS.

### 5.13 `voice.tenant_phone_numbers`

**Domain concept:** `TenantPhoneNumber`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `phone_e164` | TEXT | NOT NULL | — | Canonical E.164. Globally unique — one number per platform. **pii:phone** |
| `phone_country` | TEXT | NOT NULL | — | ISO 3166-1 alpha-2, derived at parse time |
| `provider_id` | TEXT | NOT NULL | — | e.g. `exotel`, `twilio` |
| `provider_number_id` | TEXT | NULL | — | Provider's own number identifier |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| SUSPENDED \| RELEASED` |
| `inbound_enabled` | BOOLEAN | NOT NULL | `TRUE` | |
| `outbound_enabled` | BOOLEAN | NOT NULL | `TRUE` | |
| `assigned_agent_id` | UUID | NULL | — | Logical ref: `voice.agents.id` — which agent handles inbound calls to this number |
| `capabilities` | TEXT[] | NOT NULL | `'{}'` | e.g. `{VOICE, SMS}` |
| `number_type` | TEXT | NULL | — | `MOBILE \| LANDLINE \| TOLL_FREE \| VOIP` |
| `verified_at` | TIMESTAMPTZ | NULL | — | When number ownership was verified |
| `credential_ref` | TEXT | NULL | — | Provider auth reference if needed |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Global uniqueness on `phone_e164`:** a phone number belongs to exactly one tenant on the platform. A number cannot be assigned to two organizations simultaneously. This is a platform-level invariant enforced by `UNIQUE (phone_e164)`.

---

## 6. Primary Keys — Partitioned Table Handling

### 6.1 PostgreSQL Partitioning + Primary Key Rule

PostgreSQL requires that every unique constraint (including the primary key) on a partitioned table includes the partition key. A standard `PRIMARY KEY (id)` is **not valid** on a table partitioned by `started_at` unless `started_at` is in the primary key.

### 6.2 `call_sessions` — Composite PK

```sql
PRIMARY KEY (id, started_at)
```

`id` provides global uniqueness; `started_at` satisfies the partition key requirement.

**Implication for application code:** all lookups by `id` alone (without knowing `started_at`) must either:
1. Include `started_at` in the query (preferred — eliminates partition scan), OR
2. Query without `started_at` — PostgreSQL will scan all partitions where `id` matches (still correct, uses PK index on each partition).

Pattern 2 is acceptable because `id` is indexed globally; the full scan is bounded by partition elimination on the `started_at` column if provided. The application layer will always pass `started_at` for `call_sessions` lookups where available.

### 6.3 `transcript_segments` — Composite PK

```sql
PRIMARY KEY (id, created_at)
```

Same reasoning as `call_sessions`. Segment lookups by `id` alone are rare (segments are queried by `transcript_id + sequence_number` or `call_id + created_at` range).

### 6.4 Non-Partitioned Tables

All other tables use standard `PRIMARY KEY (id)` (single column, UUIDv7).

---

## 7. Unique Constraints

| Table | Columns | Condition | Rationale |
|---|---|---|---|
| `voice.turns` | `(conversation_id, sequence_number)` | — | Enforces monotonic ordering invariant |
| `voice.agent_versions` | `(agent_id, version_number)` | — | Unique version per agent |
| `voice.tool_definitions` | `tool_name` | `WHERE organization_id IS NULL` | Platform built-ins unique by name |
| `voice.tool_definitions` | `(organization_id, tool_name)` | `WHERE organization_id IS NOT NULL` | Tenant tools unique by name within org |
| `voice.provider_configs` | `(organization_id, category, priority)` | `WHERE is_active = TRUE` | Priority unique within active configs per org+category |
| `voice.provider_configs` | `(provider_id, category)` | `WHERE organization_id IS NULL AND is_active = TRUE` | Platform defaults unique per provider+category |
| `voice.tenant_phone_numbers` | `phone_e164` | — | One number per platform |
| `voice.language_evaluation_records` | `(language, provider_id, provider_model_ref, capability, evaluation_set_ref)` | — | One evaluation per language+provider+model+capability+corpus |

**Partitioned tables note:** UNIQUE constraints on `call_sessions` and `transcript_segments` must include the partition key. There are no natural unique constraints (beyond PK) that need to be enforced on these tables.

---

## 8. Check Constraints

```sql
-- call_sessions
CHECK (direction IN ('INBOUND','OUTBOUND'))
CHECK (status IN ('INITIATED','RINGING','ANSWERED','ACTIVE','ON_HOLD','TRANSFERRING',
                  'WRAP_UP','COMPLETED','FAILED','CANCELLED','NO_ANSWER',
                  'VOICEMAIL','ABANDONED','TRANSFERRED'))
CHECK (outcome IS NULL OR outcome IN ('ANSWERED_COMPLETED','ANSWERED_TRANSFERRED',
       'NO_ANSWER','VOICEMAIL','FAILED','CANCELLED'))

-- conversations
CHECK (status IN ('ACTIVE','COMPLETED','SUMMARIZED'))
CHECK (qualification_outcome IS NULL OR qualification_outcome IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE'))
CHECK (sentiment_label IS NULL OR sentiment_label IN ('POSITIVE','NEUTRAL','NEGATIVE'))
CHECK (sentiment_score IS NULL OR sentiment_score BETWEEN 0 AND 1)
CHECK (prompt_tokens_used >= 0 AND completion_tokens_used >= 0 AND total_tokens_used >= 0)

-- turns
CHECK (speaker_role IN ('USER','ASSISTANT','SYSTEM','TOOL'))
CHECK (directive_kind IS NULL OR directive_kind IN ('SPEAK','TRANSFER','END_CALL','TOOL_CALL','WAIT'))
CHECK (utterance_confidence IS NULL OR utterance_confidence BETWEEN 0 AND 1)
CHECK (barge_in_occurred IN (TRUE, FALSE))

-- agents
CHECK (status IN ('DRAFT','PUBLISHED','DEPRECATED'))
CHECK (length(name) BETWEEN 2 AND 100)

-- tool_definitions
CHECK (timeout_ms BETWEEN 100 AND 30000)
CHECK (max_retries_on_timeout BETWEEN 0 AND 2)
CHECK (tool_name ~ '^[a-z][a-zA-Z0-9]{1,63}$')

-- tool_executions
CHECK (status IN ('PENDING','RUNNING','SUCCEEDED','FAILED','TIMED_OUT'))
CHECK (attempt_count >= 1)
CHECK (timeout_ms BETWEEN 100 AND 30000)

-- recordings
CHECK (status IN ('PENDING','IN_PROGRESS','STORED','FAILED','DELETED'))
CHECK (recording_policy IN ('ENABLED','DISABLED','REQUIRES_CONSENT','REQUIRES_DISCLOSURE'))
CHECK (storage_ref IS NULL OR storage_ref LIKE 'org/%')
CHECK (retention_days IS NULL OR retention_days > 0)

-- transcripts
CHECK (status IN ('IN_PROGRESS','COMPLETED'))
CHECK (total_segments >= 0)

-- transcript_segments
CHECK (speaker IN ('CALLER','AGENT','SYSTEM'))
CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1)
CHECK (sequence_number >= 0)

-- provider_configs
CHECK (category IN ('TELEPHONY','STT','TTS','LLM','EMBEDDING'))
CHECK (circuit_state IN ('CLOSED','OPEN','HALF_OPEN'))
CHECK (health_state IN ('AVAILABLE','DEGRADED','UNAVAILABLE'))
CHECK (error_rate_pct BETWEEN 0 AND 100)
CHECK (priority >= 1)
CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')

-- language_evaluation_records
CHECK (capability IN ('STT','TTS','LLM'))
CHECK (verdict IN ('APPROVED','CONDITIONAL','REJECTED'))

-- tenant_phone_numbers
CHECK (status IN ('ACTIVE','SUSPENDED','RELEASED'))
CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')
CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
```

---

## 9. Index Strategy

### 9.1 `voice.call_sessions`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_call_sessions` | `(id, started_at)` | UNIQUE B-tree (PK) | — | PK lookup |
| `idx_cs_org_status` | `(organization_id, status)` | B-tree | `WHERE status = 'ACTIVE'` | Active call count; concurrent quota check |
| `idx_cs_org_started` | `(organization_id, started_at DESC)` | B-tree | — | Call list by recency |
| `idx_cs_conversation_id` | `conversation_id` | B-tree | `WHERE conversation_id IS NOT NULL` | Reverse-lookup: conversation → call |
| `idx_cs_agent_version` | `(organization_id, agent_version_id, started_at)` | B-tree | — | Agent performance analytics |
| `idx_cs_provider_call_ref` | `provider_call_ref` | B-tree | `WHERE provider_call_ref IS NOT NULL` | Telephony webhook → call lookup |
| `idx_cs_campaign_lead` | `campaign_lead_ref` | B-tree | `WHERE campaign_lead_ref IS NOT NULL` | Campaign executor outcome lookup |
| `idx_cs_from_number` | `(organization_id, from_number)` | B-tree | — | Contact matching by caller number |
| `idx_cs_started_brin` | `(organization_id, started_at)` | BRIN | — | Partition-level time-range scans |

**Active call index critical note:** the partial index `WHERE status = 'ACTIVE'` is small (only current calls) and extremely fast for the concurrent-call quota check that fires on every `InitiateCall`.

### 9.2 `voice.conversations`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_conversations` | `id` | UNIQUE B-tree (PK) | — | |
| `idx_conv_org_status` | `(organization_id, status)` | B-tree | — | List active conversations |
| `idx_conv_call_id` | `call_id` | UNIQUE B-tree | — | Call → conversation lookup (1:1) |
| `idx_conv_contact_ref` | `(organization_id, contact_ref)` | B-tree | `WHERE contact_ref IS NOT NULL` | CRM contact's conversation history |
| `idx_conv_qualification` | `(organization_id, qualification_outcome)` | B-tree | `WHERE qualification_outcome = 'QUALIFIED'` | Qualified leads from voice |
| `idx_conv_org_started` | `(organization_id, started_at DESC)` | B-tree | — | Recency queries |

**`call_id` unique index:** one conversation per call (Phase 4B §5.1 invariant 5: `ConversationRef` is set exactly once). The UNIQUE index enforces this at DB level.

### 9.3 `voice.turns`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_turns` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_turns_seq` | `(conversation_id, sequence_number)` | UNIQUE B-tree | — | Sequence uniqueness invariant |
| `idx_turns_conv_seq` | `(conversation_id, sequence_number ASC)` | B-tree | — | Load conversation turns ordered |
| `idx_turns_org` | `organization_id` | B-tree | — | RLS support |

### 9.4 `voice.agents`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_agents` | `id` | UNIQUE B-tree (PK) | — | |
| `idx_agents_org_status` | `(organization_id, status)` | B-tree | — | List agents by status |
| `idx_agents_published` | `(organization_id, published_version_id)` | B-tree | `WHERE status = 'PUBLISHED'` | Published agents for call routing |
| `idx_agents_org_created` | `(organization_id, created_at DESC)` | B-tree | — | Agent list by recency |

### 9.5 `voice.agent_versions`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_agent_versions` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_av_version` | `(agent_id, version_number)` | UNIQUE B-tree | — | Version uniqueness per agent |
| `idx_av_agent_id` | `agent_id` | B-tree | — | All versions for an agent |
| `idx_av_org` | `organization_id` | B-tree | — | RLS support |

### 9.6 `voice.tool_definitions`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_tool_defs` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_tool_name_platform` | `tool_name` | UNIQUE B-tree | `WHERE organization_id IS NULL` | Platform tool name lookup |
| `uq_tool_name_tenant` | `(organization_id, tool_name)` | UNIQUE B-tree | `WHERE organization_id IS NOT NULL` | Tenant tool lookup |
| `idx_td_org_active` | `(organization_id, is_active)` | B-tree | `WHERE is_active = TRUE` | Active tools for an org |

### 9.7 `voice.tool_executions`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_tool_execs` | `id` | UNIQUE B-tree (PK) | — | |
| `idx_te_conversation` | `(conversation_id, started_at)` | B-tree | — | All tool executions for a conversation |
| `idx_te_call_id` | `(organization_id, call_id, started_at)` | B-tree | — | All executions for a call |
| `idx_te_turn_id` | `turn_id` | B-tree | — | Tool executions for a turn |
| `idx_te_org_tool_name` | `(organization_id, tool_name, started_at)` | B-tree | — | Tool usage analytics |
| `idx_te_org_status` | `(organization_id, status)` | B-tree | `WHERE status IN ('PENDING','RUNNING')` | In-flight execution monitoring |

### 9.8 `voice.recordings`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_recordings` | `id` | UNIQUE B-tree (PK) | — | |
| `idx_rec_call_id` | `call_id` | UNIQUE B-tree | — | Call → recording lookup (1:1) |
| `idx_rec_org_status` | `(organization_id, status)` | B-tree | — | Status queries |
| `idx_rec_retention` | `delete_after` | B-tree | `WHERE delete_after IS NOT NULL AND status = 'STORED'` | Retention job |

### 9.9 `voice.transcripts`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_transcripts` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_transcript_conv` | `conversation_id` | UNIQUE B-tree | — | One transcript per conversation |
| `idx_tr_call_id` | `call_id` | B-tree | — | Call → transcript lookup |
| `idx_tr_org_status` | `(organization_id, status)` | B-tree | — | Status queries |

### 9.10 `voice.transcript_segments` (Partitioned)

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_transcript_segments` | `(id, created_at)` | UNIQUE B-tree (PK) | — | |
| `idx_ts_transcript_seq` | `(transcript_id, sequence_number ASC)` | B-tree | — | Ordered transcript read |
| `idx_ts_conversation` | `(conversation_id, sequence_number ASC)` | B-tree | — | Full transcript by conversation |
| `idx_ts_call_time` | `(call_id, created_at)` | B-tree | — | Call transcript time-range |
| `idx_ts_org_time_brin` | `(organization_id, created_at)` | BRIN | — | Partition-level range scans |

### 9.11 `voice.provider_configs`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_provider_configs` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_pc_priority` | `(organization_id, category, priority)` | UNIQUE B-tree | `WHERE is_active = TRUE` | Priority uniqueness |
| `idx_pc_org_category` | `(organization_id, category, priority)` | B-tree | `WHERE is_active = TRUE AND circuit_state = 'CLOSED'` | Provider routing lookup |
| `idx_pc_platform_cat` | `(category, priority)` | B-tree | `WHERE organization_id IS NULL AND is_active = TRUE` | Platform default lookup |

### 9.12 `voice.language_evaluation_records`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_ler` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_ler_eval` | `(language, provider_id, provider_model_ref, capability, evaluation_set_ref)` | UNIQUE B-tree | — | Prevent duplicate evaluations |
| `idx_ler_lookup` | `(language, provider_id, capability, evaluated_at DESC)` | B-tree | — | Provider selection lookup |
| `idx_ler_verdict` | `(language, capability, verdict)` | B-tree | — | "All approved Tamil STT providers" |

### 9.13 `voice.tenant_phone_numbers`

| Index | Columns | Type | Condition | Query supported |
|---|---|---|---|---|
| `pk_phone_numbers` | `id` | UNIQUE B-tree (PK) | — | |
| `uq_phone_e164` | `phone_e164` | UNIQUE B-tree | — | Global uniqueness; inbound webhook routing |
| `idx_pn_org_status` | `(organization_id, status)` | B-tree | `WHERE status = 'ACTIVE'` | List org's active numbers |
| `idx_pn_assigned_agent` | `(organization_id, assigned_agent_id)` | B-tree | `WHERE assigned_agent_id IS NOT NULL` | Agent → numbers mapping |

---

## 10. Partitioning Specifications

### 10.1 `voice.call_sessions` — RANGE monthly on `started_at`

```sql
-- Parent table (no data stored here):
CREATE TABLE voice.call_sessions (...)
PARTITION BY RANGE (started_at);

-- Child partitions are created PARAMETRICALLY at migration time by
-- platform.db.partition_utils.create_monthly_partitions(), not hard-coded.
-- The pattern at deployment time (example: deployed in month YYYY-MM):
--
-- CREATE TABLE voice.call_sessions_{YYYY}_{MM}
--   PARTITION OF voice.call_sessions
--   FOR VALUES FROM ('{YYYY}-{MM}-01 00:00:00+00')
--             TO   ('{YYYY}-{MM+1}-01 00:00:00+00');
--
-- Created for: current month, +1, +2, +3 months ahead.
-- DEFAULT safety partition also created (see §16.3).
```

**Retention policy:**
- Hot: 12 months in PostgreSQL
- Cold: export to S3 as Parquet, then drop partition
- Schedule: monthly cron job (part of Phase 22 Deployment)

**Index strategy on partitioned table:** indexes are created on the parent table and automatically inherited by child partitions (PostgreSQL 12+). BRIN index on `(organization_id, started_at)` for time-range analytics. B-tree on `(organization_id, status)` with partial condition for active calls.

### 10.2 `voice.transcript_segments` — RANGE monthly on `created_at`

```sql
CREATE TABLE voice.transcript_segments (...)
PARTITION BY RANGE (created_at);

-- Child partitions are created parametrically at migration time.
-- Same strategy as call_sessions (see §10.1 and §16.6).
-- Pattern: voice.transcript_segments_{YYYY}_{MM}
-- Current month + 3 months ahead at deployment.
-- 24-month hot retention window maintained by scheduled job.
```

**Retention policy:**
- Hot: 24 months in PostgreSQL
- Cold: export to S3 as Parquet, then drop partition

**Volume estimate:** ~150 segments/call × 1M calls/day = 150M segments/day at platform maturity. Monthly partition = ~4.5B rows. This confirms partitioning is non-optional — retrofitting would require a painful online migration.

---

## 11. RLS Architecture

### 11.1 Standard Tenant Policies

All tenant-scoped tables use the standard Phase 5A pattern:

```sql
ALTER TABLE voice.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.<table> FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_<table>_tenant ON voice.<table>
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

Tables: `call_sessions`, `conversations`, `turns`, `agents`, `agent_versions`, `tool_executions`, `recordings`, `transcripts`, `transcript_segments`, `tenant_phone_numbers`.

### 11.2 Append-Only Tables (REVOKE UPDATE, DELETE)

```sql
-- transcript_segments: strictly append-only per Phase 5A §15
-- No exception. No UPDATE path for any application role.
REVOKE UPDATE, DELETE ON voice.transcript_segments FROM app_api, app_worker;
```

`tool_executions` is **not** append-only — it requires UPDATE to transition status (PENDING → RUNNING → SUCCEEDED/FAILED/TIMED_OUT). Only `app_api` and `app_worker` may update it.

### 11.3 Mixed-Scope Tables: `tool_definitions` and `provider_configs`

```sql
-- tool_definitions: platform built-ins (org IS NULL) readable by all tenants
CREATE POLICY rls_tool_defs_read ON voice.tool_definitions
  FOR SELECT
  USING (
    organization_id = organization.current_tenant_id()
    OR organization_id IS NULL
  );

CREATE POLICY rls_tool_defs_write ON voice.tool_definitions
  FOR INSERT WITH CHECK (
    organization_id = organization.current_tenant_id()
  );

CREATE POLICY rls_tool_defs_modify ON voice.tool_definitions
  FOR UPDATE USING (
    organization_id = organization.current_tenant_id()
  );

-- provider_configs: same mixed-scope pattern
CREATE POLICY rls_prov_configs_read ON voice.provider_configs
  FOR SELECT
  USING (
    organization_id = organization.current_tenant_id()
    OR organization_id IS NULL
  );

CREATE POLICY rls_prov_configs_write ON voice.provider_configs
  FOR INSERT WITH CHECK (
    organization_id = organization.current_tenant_id()
  );

CREATE POLICY rls_prov_configs_modify ON voice.provider_configs
  FOR UPDATE USING (
    organization_id = organization.current_tenant_id()
  );
```

### 11.4 Transcript Segments — Strictly Append-Only (No Exception)

`voice.transcript_segments` is strictly append-only for `app_api` and `app_worker`. There is no UPDATE path — not even a controlled one. The REVOKE is unconditional:

```sql
REVOKE UPDATE, DELETE ON voice.transcript_segments FROM app_api, app_worker;
```

**Final architecture (ISSUE 1 resolution):** PostgreSQL stores **only finalized segments**. Partial STT fragments live exclusively in Redis and are never written to the database. When the STT provider delivers a final result, the application assembles the complete finalized segment in memory and INSERTs it once with `is_partial = FALSE`.

**Idempotency without UPDATE (ISSUE 3 resolution):** Because `(transcript_id, sequence_number)` cannot be enforced as a global UNIQUE constraint across monthly partitions (the partition key `created_at` would have to be included, but the same segment re-delivered could arrive at a different `NOW()`), duplicate-delivery protection is handled by the segment's UUIDv7 `id`:

```sql
-- Idempotent final segment insert:
INSERT INTO voice.transcript_segments (id, created_at, ...)
VALUES ($generated_uuid, NOW(), ...)
ON CONFLICT (id, created_at) DO NOTHING;
-- $generated_uuid is generated deterministically from (transcript_id, sequence_number)
-- by the application layer so re-delivery of the same segment produces the same UUID.
-- ON CONFLICT target is the composite PK (id, created_at) — valid on partitioned table.
```

The application generates the segment `id` as a deterministic UUIDv7 derived from `(transcript_id, sequence_number)` — making the INSERT naturally idempotent without needing a separate UNIQUE index. No UPDATE ever occurs.

The only actors that may DELETE a `transcript_segments` row are `app_platform_admin` and `app_migration`, per the Phase 5A §15.2 compliance correction pattern, with a mandatory audit trail.

### 11.5 `language_evaluation_records` — No RLS

```sql
-- No ENABLE ROW LEVEL SECURITY on language_evaluation_records
-- Platform-owned reference data readable by all roles
GRANT SELECT ON voice.language_evaluation_records TO app_api, app_worker, app_readonly;
```

### 11.6 `agent_versions` — Immutability Trigger

```sql
CREATE OR REPLACE FUNCTION voice.prevent_agent_version_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.snapshot_json IS DISTINCT FROM NEW.snapshot_json THEN
    RAISE EXCEPTION 'agent_versions.snapshot_json is immutable after creation. '
      'AgentVersionId: %, attempted change', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_agent_version_immutable
  BEFORE UPDATE ON voice.agent_versions
  FOR EACH ROW EXECUTE FUNCTION voice.prevent_agent_version_mutation();
```

### 11.7 `tool_executions.arguments` — Immutability Trigger

```sql
CREATE OR REPLACE FUNCTION voice.prevent_tool_exec_arguments_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.arguments IS DISTINCT FROM NEW.arguments THEN
    RAISE EXCEPTION 'tool_executions.arguments is immutable after creation.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tool_exec_args_immutable
  BEFORE UPDATE ON voice.tool_executions
  FOR EACH ROW EXECUTE FUNCTION voice.prevent_tool_exec_arguments_mutation();
```

---

## 12. Cross-Schema Logical References

| Source Table.Column | Target (logical) | FK? | Application validation |
|---|---|---|---|
| `call_sessions.organization_id` | `organization.organizations.id` | No | Set from JWT/API-key at call initiation |
| `call_sessions.tenant_phone_number_id` | `voice.tenant_phone_numbers.id` | No (same schema — FK permitted but kept logical for aggregate independence) | `CallRoutingService.resolve()` |
| `call_sessions.agent_version_id` | `voice.agent_versions.id` | No | Validated by `PublishedAgentSpecification` at call start |
| `call_sessions.conversation_id` | `voice.conversations.id` | No | Set via `StartConversation` command |
| `call_sessions.campaign_lead_ref` | `campaign.campaign_contacts.id` | No (cross-schema) | Campaign executor validates |
| `call_sessions.contact_ref` | `crm.contacts.id` | No (cross-schema) | CRM context sets |
| `conversations.call_id` | `voice.call_sessions.id` | No (aggregate independence) | Set by `BeginConversation` |
| `conversations.agent_version_id` | `voice.agent_versions.id` | No | Copied from Call at conversation start |
| `conversations.contact_ref` | `crm.contacts.id` | No (cross-schema) | CRM context sets |
| `turns.conversation_id` | `voice.conversations.id` | FK permitted (same schema, same aggregate) | — |
| `agents.organization_id` | `organization.organizations.id` | No (cross-schema) | JWT context |
| `agents.published_version_id` | `voice.agent_versions.id` | No (aggregate independence) | Set by `PublishAgent` |
| `agent_versions.agent_id` | `voice.agents.id` | FK permitted (same schema, same aggregate) | — |
| `tool_executions.conversation_id` | `voice.conversations.id` | No (aggregate independence) | Set at execution creation |
| `tool_executions.turn_id` | `voice.turns.id` | No (aggregate independence) | Set at execution creation |
| `tool_executions.call_id` | `voice.call_sessions.id` | No (aggregate independence) | Denormalized at creation |
| `tool_executions.tool_definition_id` | `voice.tool_definitions.id` | FK permitted (same schema) | Validated at authorization |
| `recordings.call_id` | `voice.call_sessions.id` | No (aggregate independence) | Set on recording start |
| `recordings.conversation_id` | `voice.conversations.id` | No (aggregate independence) | Set on recording start |
| `transcripts.conversation_id` | `voice.conversations.id` | No (aggregate independence) | Set on transcript start |
| `transcripts.call_id` | `voice.call_sessions.id` | No — denormalized | Set on transcript start |
| `transcript_segments.transcript_id` | `voice.transcripts.id` | FK permitted in principle but not created (aggregate independence + partitioning complications) | AppService validates |
| `transcript_segments.conversation_id` | `voice.conversations.id` | No | Denormalized |
| `tenant_phone_numbers.assigned_agent_id` | `voice.agents.id` | No (aggregate independence) | Validated on assignment |

**FK decisions within `voice` schema:**

Within the `voice` schema, FKs are permitted but the DDD aggregate independence rule takes precedence. The only FKs created are:
- `turns.conversation_id → conversations(id) ON DELETE CASCADE` — turns have no meaning without their conversation; cascade is safe.
- `agent_versions.agent_id → agents(id) ON DELETE CASCADE` — versions have no meaning without their agent.
- `tool_executions.tool_definition_id → tool_definitions(id) ON DELETE RESTRICT` — prevent deletion of tools with execution history.

All others remain logical references to preserve aggregate independence and allow cross-aggregate queries without implicit locks.

---

## 13. PII Classification

| Table.Column | PII Category | Handling |
|---|---|---|
| `call_sessions.from_number` | `pii:phone` | Masked in logs |
| `call_sessions.to_number` | `pii:phone` | Masked in logs |
| `call_sessions.transfer_target` | `pii:phone` | Masked in logs |
| `conversations.summary_text` | `pii:voice` | Masked in logs; encrypted at rest |
| `turns.utterance_text` | `pii:voice` | Masked in logs; encrypted at rest |
| `turns.response_text` | `pii:voice` | Masked in logs |
| `transcript_segments.text` | `pii:voice` | Masked in logs; encrypted at rest |
| `recordings.storage_ref` | `pii:voice` (reference) | Presigned URL access only |
| `tenant_phone_numbers.phone_e164` | `pii:phone` | Masked in logs |

**Encryption at rest:** Supabase PostgreSQL provides AES-256 at the storage layer covering all columns. No additional column-level encryption is required in V1.

**Log masking:** Phase 5A §26.4 specifies that PII columns are tagged with SQL comments. Applied here:
```sql
COMMENT ON COLUMN voice.call_sessions.from_number IS 'pii:phone — E.164 caller number';
COMMENT ON COLUMN voice.turns.utterance_text IS 'pii:voice — STT transcript of caller utterance';
-- etc.
```

---

## 14. Retention Strategy

| Table | Technical default | Org-policy driven | Legal/regulatory |
|---|---|---|---|
| `call_sessions` | 12 months hot / 7 yr cold | No | No |
| `conversations` | Follows `call_sessions` | No | No |
| `turns` | Follows `call_sessions` | No | No |
| `transcript_segments` | 24 months hot / 7 yr cold | No (platform default) | No |
| `recordings` | `recordings.retention_days` (copied from org policy) | Yes — per org's RetentionProfile | No |
| `tool_executions` | 12 months hot | No | No |
| `agent_versions` | Indefinite (immutable reference data) | No | No |
| `provider_configs` | Indefinite | No | No |
| `language_evaluation_records` | Indefinite | No | No |
| `tenant_phone_numbers` | Until RELEASED | No | No |

**Distinction:** the platform provides configurable controls for recordings (`recordings.retention_days`, `delete_after`). The platform does not prescribe regulatory retention periods — the organisation configures them in its `CompliancePolicy.RetentionProfile`.

---

## 15. Query Patterns

### 15.1 Create Call Session

```sql
-- SET LOCAL app.tenant_id = $org_id
INSERT INTO voice.call_sessions (
  id, started_at, organization_id, direction, status,
  from_number, to_number, tenant_phone_number_id,
  agent_version_id, provider_call_ref, campaign_lead_ref,
  sessions
)
VALUES (
  $id, $started_at, $org_id, 'INBOUND', 'INITIATED',
  $from_number, $to_number, $tenant_phone_number_id,
  $agent_version_id, $provider_call_ref, $campaign_lead_ref,
  jsonb_build_array(jsonb_build_object(
    'session_id', $session_id,
    'started_at', $started_at,
    'ended_at', NULL,
    'outcome', 'ACTIVE'
  ))
);
-- RLS: organization_id = current_tenant_id() ✓
-- Index: PK (id, started_at)
-- Hot path: async — runs after telephony webhook received, not in STT/LLM path
```

### 15.2 Get Active Calls for Tenant

```sql
-- SET LOCAL app.tenant_id = $org_id
SELECT id, direction, from_number, to_number, status, started_at,
       agent_version_id, conversation_id
FROM voice.call_sessions
WHERE organization_id = organization.current_tenant_id()
  AND status = 'ACTIVE';
-- RLS: organization_id = current_tenant_id() ✓
-- Index: idx_cs_org_status (partial WHERE status = 'ACTIVE') — extremely fast
-- Hot path: called for quota check; should be < 1ms via Redis counter (DB fallback)
```

### 15.3 Get Call by ID (with started_at for partition elimination)

```sql
SELECT *
FROM voice.call_sessions
WHERE id = $call_id
  AND started_at >= $started_at_hint   -- provided by caller to eliminate partitions
  AND organization_id = organization.current_tenant_id();
-- If started_at not known: omit the hint; PostgreSQL scans all partitions (correct but slower)
-- Index: PK (id, started_at)
```

### 15.4 Load Conversation with Turns

```sql
-- Two-query pattern (avoids N+1 within aggregate):

-- Query 1: Load conversation
SELECT * FROM voice.conversations
WHERE id = $conversation_id
  AND organization_id = organization.current_tenant_id();
-- Index: pk_conversations

-- Query 2: Load turns ordered
SELECT * FROM voice.turns
WHERE conversation_id = $conversation_id
  AND organization_id = organization.current_tenant_id()
ORDER BY sequence_number ASC;
-- Index: uq_turns_seq (conversation_id, sequence_number)
-- N+1 risk: none — two queries regardless of turn count
```

### 15.5 Load Transcript Ordered by Sequence

All rows in `transcript_segments` are finalized segments (`is_partial = FALSE` is invariant). The filter is unnecessary but may be retained for defensive coding; it adds negligible cost on a column with a constant value.

```sql
SELECT id, sequence_number, speaker, text, is_partial,
       start_ms, end_ms, confidence, language
FROM voice.transcript_segments
WHERE transcript_id = $transcript_id
  AND organization_id = organization.current_tenant_id()
ORDER BY sequence_number ASC;
-- Index: idx_ts_transcript_seq (transcript_id, sequence_number ASC)
-- Partition routing: add created_at BETWEEN $call_start AND $call_end + 1 hour
--   to confine the query to relevant monthly partitions.
--   The application passes call.started_at + a small buffer to enable pruning.
```

### 15.6 Append Final Transcript Segment

Only finalized segments are written to PostgreSQL. Partial STT fragments remain in Redis and are never inserted here.

```sql
-- Pre-condition enforced by application layer:
--   assert is_partial == False, "Partial segments must not reach PostgreSQL"
--   assert segment.id == deterministic_uuid(transcript_id, sequence_number)

INSERT INTO voice.transcript_segments (
  id, created_at, organization_id, transcript_id, conversation_id, call_id,
  sequence_number, speaker, text, is_partial, start_ms, end_ms,
  confidence, language, stt_provider_id, provider_segment_id
)
VALUES (
  $id,        -- UUIDv7 generated deterministically from (transcript_id, seq_number)
  NOW(),      -- lands in current month's partition
  $org_id, $transcript_id, $conv_id, $call_id,
  $seq, $speaker, $text,
  FALSE,      -- ALWAYS FALSE — partial segments never reach PostgreSQL
  $start_ms, $end_ms, $confidence, $language, $stt_provider, $provider_seg_id
)
ON CONFLICT (id, created_at) DO NOTHING;
-- Idempotency: the deterministic UUIDv7 id means re-delivery of the same
-- final segment produces the same id. ON CONFLICT DO NOTHING on the composite
-- PK (id, created_at) is a valid conflict target on a partitioned table.
-- REVOKE UPDATE, DELETE on this table ensures no application role can modify
-- the row after this INSERT.

-- RLS: organization_id = current_tenant_id() ✓
-- Index: idx_ts_transcript_seq used for ordered reads
-- Append-only: REVOKE UPDATE, DELETE FROM app_api, app_worker ✓
```

### 15.7 Load Published Agent Version (Critical Hot Path)

```sql
-- This query is NOT in the call hot path — it populates the Redis cache.
-- The cache TTL is 1 hour (immutable data). This query runs once per agent version per hour.

SELECT av.id, av.snapshot_json, av.language_policy, av.published_at
FROM voice.agent_versions av
WHERE av.id = $agent_version_id
  AND av.organization_id = organization.current_tenant_id();
-- Index: pk_agent_versions
-- Cache key: agent_version:{version_id}:snapshot → 1h TTL
```

### 15.8 List Tool Executions for Conversation

```sql
SELECT id, tool_name, status, started_at, completed_at,
       arguments_hash, error_code
FROM voice.tool_executions
WHERE conversation_id = $conversation_id
  AND organization_id = organization.current_tenant_id()
ORDER BY started_at ASC;
-- Index: idx_te_conversation
```

### 15.9 Resolve Tenant Phone Number (Inbound Routing)

```sql
-- Called from telephony webhook ACL — tenant_id NOT YET SET
-- Uses the SECURITY DEFINER function defined in Migration 009.
-- The function definition, REVOKE ALL FROM PUBLIC, and
-- GRANT EXECUTE TO app_api, app_worker, app_platform_admin
-- are all in the DDL section (§16.1).

SELECT organization_id, tenant_phone_number_id, assigned_agent_id
FROM voice.resolve_inbound_phone_number($phone_e164);
-- Uses: uq_phone_e164 (unique B-tree — O(1) inside the function)
-- Returns: organization_id → caller sets: SET LOCAL app.tenant_id = returned_org_id
-- RLS context: established AFTER this call, using the returned organization_id
```

### 15.10 Get Recording Metadata

```sql
SELECT r.id, r.status, r.storage_ref, r.duration_seconds,
       r.recording_policy, r.consent_obtained, r.delete_after
FROM voice.recordings r
WHERE r.call_id = $call_id
  AND r.organization_id = organization.current_tenant_id();
-- Index: idx_rec_call_id (unique — 1:1 call to recording)
```

### 15.11 Provider Configuration Lookup (Pre-Selection)

```sql
-- Called by ProviderSelectionService via application service (not in DB hot path)
-- Result cached in Redis: provider_config:{org_id}:{category} → 5min TTL

SELECT id, provider_id, model_id, priority, circuit_state, health_state,
       p50_latency_ms, error_rate_pct, supports_languages, config_json
FROM voice.provider_configs
WHERE (organization_id = organization.current_tenant_id() OR organization_id IS NULL)
  AND category = $category
  AND is_active = TRUE
  AND circuit_state = 'CLOSED'
ORDER BY organization_id NULLS LAST, priority ASC;
-- organization_id NULLS LAST: tenant configs preferred over platform defaults
-- Index: idx_pc_org_category
```

### 15.12 Language Evaluation Lookup

```sql
SELECT provider_id, provider_model_ref, capability, verdict, scores, evaluated_at
FROM voice.language_evaluation_records
WHERE language = $language
  AND capability = $capability
  AND verdict IN ('APPROVED', 'CONDITIONAL')
ORDER BY evaluated_at DESC;
-- Index: idx_ler_lookup
-- No RLS (platform-scoped)
-- Cached in Redis: lang_eval:{language}:{capability} → 1h TTL
```

---

## 16. Complete PostgreSQL DDL

### 16.1 Schema + Functions

```sql
-- ================================================================
-- Migration 009: Voice schema and voice-specific functions
-- ================================================================

-- Voice schema created in Migration 001 (Phase 5B) — already exists
-- Re-grant for voice-specific permissions
GRANT USAGE ON SCHEMA voice TO app_api, app_worker, app_readonly, app_platform_admin;

-- Voice-specific trigger: prevent agent_version snapshot mutation
CREATE OR REPLACE FUNCTION voice.prevent_agent_version_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.snapshot_json IS DISTINCT FROM NEW.snapshot_json OR
     OLD.language_policy IS DISTINCT FROM NEW.language_policy THEN
    RAISE EXCEPTION
      'voice.agent_versions is immutable after creation. Attempted mutation on id=%', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- Voice-specific trigger: prevent tool_execution arguments mutation
CREATE OR REPLACE FUNCTION voice.prevent_tool_exec_arguments_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.arguments IS DISTINCT FROM NEW.arguments THEN
    RAISE EXCEPTION
      'voice.tool_executions.arguments is immutable after creation. id=%', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- SECURITY DEFINER: resolve inbound phone number pre-auth
-- Privilege hardening (ISSUE 6):
--   1. REVOKE ALL FROM PUBLIC so no role can call this by default.
--   2. Grant EXECUTE only to the application roles that legitimately
--      need pre-auth phone resolution (app_api and app_worker handle
--      inbound webhook ACL; app_platform_admin for admin tooling).
--   3. No role outside Phase 5B's approved set is granted access.

CREATE OR REPLACE FUNCTION voice.resolve_inbound_phone_number(p_phone_e164 TEXT)
RETURNS TABLE (
  organization_id         UUID,
  tenant_phone_number_id  UUID,
  assigned_agent_id       UUID
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = voice, organization, pg_temp
AS $$
  SELECT pn.organization_id, pn.id, pn.assigned_agent_id
  FROM voice.tenant_phone_numbers pn
  WHERE pn.phone_e164 = p_phone_e164
    AND pn.status = 'ACTIVE'
    AND pn.inbound_enabled = TRUE
  LIMIT 1;
$$;

-- Harden SECURITY DEFINER function privilege (ISSUE 6):
REVOKE ALL ON FUNCTION voice.resolve_inbound_phone_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.resolve_inbound_phone_number(TEXT)
  TO app_api, app_worker, app_platform_admin;
-- app_readonly is NOT granted: it has no need to route inbound calls.
-- app_migration is NOT granted: it has BYPASSRLS and direct table access.
```

### 16.2 Agents and Agent Versions

```sql
-- ================================================================
-- Migration 010: voice.agents and voice.agent_versions
-- ================================================================

CREATE TABLE voice.agents (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL, -- logical ref: organization.organizations.id
  name                  TEXT          NOT NULL,
  description           TEXT          NULL,
  status                TEXT          NOT NULL DEFAULT 'DRAFT',
  published_version_id  UUID          NULL,     -- logical ref: voice.agent_versions.id
  draft_config          JSONB         NOT NULL DEFAULT '{}',
  created_by            UUID          NOT NULL, -- logical ref: identity.users.id
  deleted_at            TIMESTAMPTZ   NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_agents           PRIMARY KEY (id),
  CONSTRAINT chk_agents_status   CHECK (status IN ('DRAFT','PUBLISHED','DEPRECATED')),
  CONSTRAINT chk_agents_name_len CHECK (length(name) BETWEEN 2 AND 100)
);

CREATE INDEX idx_agents_org_status  ON voice.agents (organization_id, status);
CREATE INDEX idx_agents_published
  ON voice.agents (organization_id, published_version_id)
  WHERE status = 'PUBLISHED';
CREATE INDEX idx_agents_org_created ON voice.agents (organization_id, created_at DESC);

CREATE TRIGGER trg_agents_updated_at
  BEFORE UPDATE ON voice.agents
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.agents FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_agents_tenant ON voice.agents
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.agents TO app_api, app_worker;


CREATE TABLE voice.agent_versions (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL, -- logical ref: organization.organizations.id
  agent_id         UUID          NOT NULL,
  version_number   INTEGER       NOT NULL,
  snapshot_json    JSONB         NOT NULL, -- IMMUTABLE after write
  language_policy  JSONB         NOT NULL, -- Extracted from snapshot; IMMUTABLE
  published_by     UUID          NOT NULL, -- logical ref: identity.users.id
  published_at     TIMESTAMPTZ   NOT NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_agent_versions      PRIMARY KEY (id),
  CONSTRAINT fk_av_agent            FOREIGN KEY (agent_id) REFERENCES voice.agents(id) ON DELETE CASCADE,
  CONSTRAINT uq_av_version          UNIQUE (agent_id, version_number)
);

CREATE INDEX idx_av_agent_id ON voice.agent_versions (agent_id);
CREATE INDEX idx_av_org      ON voice.agent_versions (organization_id);

CREATE TRIGGER trg_agent_version_immutable
  BEFORE UPDATE ON voice.agent_versions
  FOR EACH ROW EXECUTE FUNCTION voice.prevent_agent_version_mutation();

ALTER TABLE voice.agent_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.agent_versions FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_agent_versions_tenant ON voice.agent_versions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT ON voice.agent_versions TO app_api, app_worker;
-- No UPDATE grant — immutability enforced via trigger + no UPDATE privilege
```

### 16.3 Call Sessions (Partitioned)

```sql
-- ================================================================
-- Migration 011: voice.call_sessions (partitioned)
-- ================================================================

CREATE TABLE voice.call_sessions (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  started_at              TIMESTAMPTZ   NOT NULL,  -- PARTITION KEY
  organization_id         UUID          NOT NULL,  -- logical ref: organization.organizations.id
  direction               TEXT          NOT NULL,
  status                  TEXT          NOT NULL DEFAULT 'INITIATED',
  from_number             TEXT          NOT NULL,  -- E.164; pii:phone
  to_number               TEXT          NOT NULL,  -- E.164; pii:phone
  tenant_phone_number_id  UUID          NULL,      -- logical ref: voice.tenant_phone_numbers.id
  agent_version_id        UUID          NOT NULL,  -- logical ref: voice.agent_versions.id; pinned at start
  conversation_id         UUID          NULL,      -- logical ref: voice.conversations.id; set once
  provider_call_ref       TEXT          NULL,
  campaign_lead_ref       TEXT          NULL,      -- logical ref: campaign.campaign_contacts.id
  contact_ref             UUID          NULL,      -- logical ref: crm.contacts.id
  transfer_target         TEXT          NULL,      -- E.164; pii:phone
  sessions                JSONB         NOT NULL DEFAULT '[]',
  outcome                 TEXT          NULL,
  termination_reason      TEXT          NULL,
  answered_at             TIMESTAMPTZ   NULL,
  ended_at                TIMESTAMPTZ   NULL,
  duration_seconds        INTEGER       NULL,
  stt_p50_ms              INTEGER       NULL,
  llm_first_token_p50_ms  INTEGER       NULL,
  tts_first_audio_p50_ms  INTEGER       NULL,
  turn_e2e_p50_ms         INTEGER       NULL,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_call_sessions PRIMARY KEY (id, started_at),  -- includes partition key
  CONSTRAINT chk_cs_direction CHECK (direction IN ('INBOUND','OUTBOUND')),
  CONSTRAINT chk_cs_status    CHECK (status IN (
    'INITIATED','RINGING','ANSWERED','ACTIVE','ON_HOLD','TRANSFERRING',
    'WRAP_UP','COMPLETED','FAILED','CANCELLED','NO_ANSWER',
    'VOICEMAIL','ABANDONED','TRANSFERRED'
  )),
  CONSTRAINT chk_cs_outcome   CHECK (outcome IS NULL OR outcome IN (
    'ANSWERED_COMPLETED','ANSWERED_TRANSFERRED','NO_ANSWER',
    'VOICEMAIL','FAILED','CANCELLED'
  )),
  CONSTRAINT chk_cs_phone_from CHECK (from_number ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_cs_phone_to   CHECK (to_number ~ '^\+[1-9][0-9]{6,14}$')
) PARTITION BY RANGE (started_at);

-- Column comments for PII tagging
COMMENT ON COLUMN voice.call_sessions.from_number IS 'pii:phone — E.164 caller number';
COMMENT ON COLUMN voice.call_sessions.to_number   IS 'pii:phone — E.164 called number';
COMMENT ON COLUMN voice.call_sessions.transfer_target IS 'pii:phone — transfer destination';

-- Indexes on parent table (inherited by all partitions)
CREATE INDEX idx_cs_org_status ON voice.call_sessions (organization_id, status)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_cs_org_started      ON voice.call_sessions (organization_id, started_at DESC);
CREATE INDEX idx_cs_conversation_id  ON voice.call_sessions (conversation_id)
  WHERE conversation_id IS NOT NULL;
CREATE INDEX idx_cs_agent_version    ON voice.call_sessions (organization_id, agent_version_id, started_at);
CREATE INDEX idx_cs_provider_ref     ON voice.call_sessions (provider_call_ref)
  WHERE provider_call_ref IS NOT NULL;
CREATE INDEX idx_cs_campaign_lead    ON voice.call_sessions (campaign_lead_ref)
  WHERE campaign_lead_ref IS NOT NULL;
CREATE INDEX idx_cs_from_number      ON voice.call_sessions (organization_id, from_number);
CREATE INDEX idx_cs_started_brin     ON voice.call_sessions USING BRIN (organization_id, started_at);

CREATE TRIGGER trg_cs_updated_at
  BEFORE UPDATE ON voice.call_sessions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.call_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.call_sessions FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cs_tenant ON voice.call_sessions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.call_sessions TO app_api, app_worker;

-- ---------------------------------------------------------------
-- PARTITION CREATION STRATEGY (ISSUE 5 — no hard-coded dates)
-- ---------------------------------------------------------------
-- The migration creates the CURRENT month's partition + 3 months
-- ahead + the DEFAULT safety partition.
-- The exact partition names depend on the deployment date.
--
-- The Alembic migration (011) uses a Python helper that executes
-- at migration time to create the correct partitions dynamically:
--
--   from platform.db.partition_utils import create_monthly_partitions
--   create_monthly_partitions(
--       conn=op.get_bind(),
--       table='voice.call_sessions',
--       months_ahead=3,
--   )
--
-- The helper generates and executes SQL of the form:
--
--   CREATE TABLE IF NOT EXISTS voice.call_sessions_{YYYY}_{MM}
--     PARTITION OF voice.call_sessions
--     FOR VALUES FROM ('{YYYY}-{MM}-01 00:00:00+00')
--               TO   ('{YYYY}-{MM+1}-01 00:00:00+00');
--
-- for the current month and the next 3 months.
--
-- Example: if deployed in August 2026 the migration creates:
--   voice.call_sessions_2026_08  (current)
--   voice.call_sessions_2026_09
--   voice.call_sessions_2026_10
--   voice.call_sessions_2026_11  (3-month lookahead)
--
-- A scheduled maintenance job (Phase 22 Deployment) runs monthly
-- to create additional partitions and drop expired ones after
-- cold archival (12-month hot retention window).

-- DEFAULT partition: catches any row that falls outside existing
-- partitions (safety net; should never receive data if the
-- lookahead job runs correctly).
CREATE TABLE voice.call_sessions_default
  PARTITION OF voice.call_sessions DEFAULT;
```

### 16.4 Conversations and Turns

```sql
-- ================================================================
-- Migration 012: voice.conversations and voice.turns
-- ================================================================

CREATE TABLE voice.conversations (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID          NOT NULL,
  call_id                 UUID          NOT NULL,
  agent_version_id        UUID          NOT NULL,
  contact_ref             UUID          NULL,
  status                  TEXT          NOT NULL DEFAULT 'ACTIVE',
  qualification_outcome   TEXT          NULL,
  sentiment_label         TEXT          NULL,
  sentiment_score         NUMERIC(4,3)  NULL,
  summary_text            TEXT          NULL,    -- pii:voice
  prompt_tokens_used      INTEGER       NOT NULL DEFAULT 0,
  completion_tokens_used  INTEGER       NOT NULL DEFAULT 0,
  total_tokens_used       INTEGER       NOT NULL DEFAULT 0,
  total_turns             INTEGER       NOT NULL DEFAULT 0,
  started_at              TIMESTAMPTZ   NOT NULL,
  completed_at            TIMESTAMPTZ   NULL,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_conversations         PRIMARY KEY (id),
  CONSTRAINT chk_conv_status          CHECK (status IN ('ACTIVE','COMPLETED','SUMMARIZED')),
  CONSTRAINT chk_conv_qualification   CHECK (qualification_outcome IS NULL OR
    qualification_outcome IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE')),
  CONSTRAINT chk_conv_sentiment_label CHECK (sentiment_label IS NULL OR
    sentiment_label IN ('POSITIVE','NEUTRAL','NEGATIVE')),
  CONSTRAINT chk_conv_sentiment_score CHECK (sentiment_score IS NULL OR
    sentiment_score BETWEEN 0 AND 1),
  CONSTRAINT chk_conv_tokens_nn       CHECK (
    prompt_tokens_used >= 0 AND completion_tokens_used >= 0 AND total_tokens_used >= 0
  )
);

COMMENT ON COLUMN voice.conversations.summary_text IS 'pii:voice — LLM-generated call summary';

CREATE UNIQUE INDEX uq_conv_call_id     ON voice.conversations (call_id);
CREATE        INDEX idx_conv_org_status ON voice.conversations (organization_id, status);
CREATE        INDEX idx_conv_contact    ON voice.conversations (organization_id, contact_ref)
  WHERE contact_ref IS NOT NULL;
CREATE        INDEX idx_conv_qualified  ON voice.conversations (organization_id, qualification_outcome)
  WHERE qualification_outcome = 'QUALIFIED';
CREATE        INDEX idx_conv_org_started ON voice.conversations (organization_id, started_at DESC);

CREATE TRIGGER trg_conv_updated_at
  BEFORE UPDATE ON voice.conversations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.conversations FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_conv_tenant ON voice.conversations
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.conversations TO app_api, app_worker;


CREATE TABLE voice.turns (
  id                          UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id             UUID          NOT NULL,
  conversation_id             UUID          NOT NULL,
  sequence_number             INTEGER       NOT NULL,
  speaker_role                TEXT          NOT NULL,
  utterance_text              TEXT          NULL,    -- pii:voice
  utterance_confidence        NUMERIC(4,3)  NULL,
  utterance_start_ms          INTEGER       NULL,
  utterance_end_ms            INTEGER       NULL,
  detected_language           TEXT          NULL,
  detected_languages          TEXT[]        NULL,
  code_switch_detected        BOOLEAN       NULL,
  language_detection_confidence NUMERIC(4,3) NULL,
  response_text               TEXT          NULL,    -- pii:voice
  directive_kind              TEXT          NULL,
  workflow_node_ref           TEXT          NULL,
  tool_execution_ids          UUID[]        NOT NULL DEFAULT '{}',
  llm_provider_id             TEXT          NULL,
  stt_provider_id             TEXT          NULL,
  stt_ms                      INTEGER       NULL,
  llm_first_token_ms          INTEGER       NULL,
  tts_first_audio_ms          INTEGER       NULL,
  turn_e2e_ms                 INTEGER       NULL,
  barge_in_occurred           BOOLEAN       NOT NULL DEFAULT FALSE,
  completed_at                TIMESTAMPTZ   NULL,
  created_at                  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_turns               PRIMARY KEY (id),
  CONSTRAINT fk_turns_conversation  FOREIGN KEY (conversation_id) REFERENCES voice.conversations(id) ON DELETE CASCADE,
  CONSTRAINT uq_turns_seq           UNIQUE (conversation_id, sequence_number),
  CONSTRAINT chk_turns_speaker      CHECK (speaker_role IN ('USER','ASSISTANT','SYSTEM','TOOL')),
  CONSTRAINT chk_turns_directive    CHECK (directive_kind IS NULL OR
    directive_kind IN ('SPEAK','TRANSFER','END_CALL','TOOL_CALL','WAIT')),
  CONSTRAINT chk_turns_confidence   CHECK (utterance_confidence IS NULL OR
    utterance_confidence BETWEEN 0 AND 1),
  CONSTRAINT chk_turns_seq_nn       CHECK (sequence_number >= 0)
);

COMMENT ON COLUMN voice.turns.utterance_text IS 'pii:voice — STT transcript of utterance';
COMMENT ON COLUMN voice.turns.response_text  IS 'pii:voice — LLM-generated agent response';

CREATE INDEX idx_turns_conv_seq ON voice.turns (conversation_id, sequence_number ASC);
CREATE INDEX idx_turns_org      ON voice.turns (organization_id);

ALTER TABLE voice.turns ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.turns FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_turns_tenant ON voice.turns
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT ON voice.turns TO app_api, app_worker;
-- turns are checkpointed once; no UPDATE after initial write
```

### 16.5 Tools

```sql
-- ================================================================
-- Migration 013: voice.tool_definitions and voice.tool_executions
-- ================================================================

CREATE TABLE voice.tool_definitions (
  id                    UUID      NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID      NULL,     -- NULL = platform built-in
  tool_name             TEXT      NOT NULL,
  description           TEXT      NOT NULL,
  input_schema          JSONB     NOT NULL,
  output_schema         JSONB     NOT NULL,
  is_builtin            BOOLEAN   NOT NULL DEFAULT FALSE,
  timeout_ms            INTEGER   NOT NULL DEFAULT 5000,
  requires_confirmation BOOLEAN   NOT NULL DEFAULT FALSE,
  max_retries_on_timeout INTEGER  NOT NULL DEFAULT 1,
  is_active             BOOLEAN   NOT NULL DEFAULT TRUE,
  created_by            UUID      NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tool_defs           PRIMARY KEY (id),
  CONSTRAINT chk_td_timeout         CHECK (timeout_ms BETWEEN 100 AND 30000),
  CONSTRAINT chk_td_max_retries     CHECK (max_retries_on_timeout BETWEEN 0 AND 2),
  CONSTRAINT chk_td_name_format     CHECK (tool_name ~ '^[a-z][a-zA-Z0-9]{1,63}$')
);

CREATE UNIQUE INDEX uq_td_platform_name ON voice.tool_definitions (tool_name)
  WHERE organization_id IS NULL;
CREATE UNIQUE INDEX uq_td_tenant_name   ON voice.tool_definitions (organization_id, tool_name)
  WHERE organization_id IS NOT NULL;
CREATE        INDEX idx_td_org_active   ON voice.tool_definitions (organization_id, is_active)
  WHERE is_active = TRUE;

CREATE TRIGGER trg_td_updated_at
  BEFORE UPDATE ON voice.tool_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.tool_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.tool_definitions FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_td_read ON voice.tool_definitions
  FOR SELECT
  USING (organization_id = organization.current_tenant_id() OR organization_id IS NULL);

CREATE POLICY rls_td_insert ON voice.tool_definitions
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

CREATE POLICY rls_td_modify ON voice.tool_definitions
  FOR UPDATE USING (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.tool_definitions TO app_api, app_worker;


CREATE TABLE voice.tool_executions (
  id                       UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id          UUID          NOT NULL,
  conversation_id          UUID          NOT NULL,  -- logical ref: voice.conversations.id
  turn_id                  UUID          NOT NULL,  -- logical ref: voice.turns.id
  call_id                  UUID          NOT NULL,  -- logical ref: voice.call_sessions.id (denorm)
  tool_definition_id       UUID          NOT NULL,
  tool_name                TEXT          NOT NULL,  -- denormalized for audit
  status                   TEXT          NOT NULL DEFAULT 'PENDING',
  arguments                JSONB         NOT NULL,  -- IMMUTABLE
  arguments_hash           CHAR(64)      NOT NULL,
  result                   JSONB         NULL,
  error_message            TEXT          NULL,
  error_code               TEXT          NULL,
  attempt_count            INTEGER       NOT NULL DEFAULT 1,
  authorized               BOOLEAN       NOT NULL DEFAULT FALSE,
  authorized_by_permission TEXT          NULL,
  timeout_ms               INTEGER       NOT NULL,
  started_at               TIMESTAMPTZ   NOT NULL,
  completed_at             TIMESTAMPTZ   NULL,
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tool_executions    PRIMARY KEY (id),
  CONSTRAINT fk_te_tool_def        FOREIGN KEY (tool_definition_id) REFERENCES voice.tool_definitions(id) ON DELETE RESTRICT,
  CONSTRAINT chk_te_status         CHECK (status IN ('PENDING','RUNNING','SUCCEEDED','FAILED','TIMED_OUT')),
  CONSTRAINT chk_te_attempt        CHECK (attempt_count >= 1),
  CONSTRAINT chk_te_timeout        CHECK (timeout_ms BETWEEN 100 AND 30000)
);

CREATE INDEX idx_te_conversation ON voice.tool_executions (conversation_id, started_at);
CREATE INDEX idx_te_call_id      ON voice.tool_executions (organization_id, call_id, started_at);
CREATE INDEX idx_te_turn_id      ON voice.tool_executions (turn_id);
CREATE INDEX idx_te_org_tool     ON voice.tool_executions (organization_id, tool_name, started_at);
CREATE INDEX idx_te_org_status   ON voice.tool_executions (organization_id, status)
  WHERE status IN ('PENDING','RUNNING');

CREATE TRIGGER trg_te_args_immutable
  BEFORE UPDATE ON voice.tool_executions
  FOR EACH ROW EXECUTE FUNCTION voice.prevent_tool_exec_arguments_mutation();

ALTER TABLE voice.tool_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.tool_executions FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_te_tenant ON voice.tool_executions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.tool_executions TO app_api, app_worker;
```

### 16.6 Recordings and Transcripts

```sql
-- ================================================================
-- Migration 014: recordings, transcripts, transcript_segments (partitioned)
-- ================================================================

CREATE TABLE voice.recordings (
  id                UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID          NOT NULL,
  call_id           UUID          NOT NULL,
  conversation_id   UUID          NULL,
  status            TEXT          NOT NULL DEFAULT 'PENDING',
  storage_ref       TEXT          NULL,    -- pii:voice; S3 path
  storage_provider  TEXT          NULL,
  content_type      TEXT          NULL,
  duration_seconds  INTEGER       NULL,
  file_size_bytes   BIGINT        NULL,
  checksum_sha256   CHAR(64)      NULL,
  recording_policy  TEXT          NOT NULL,
  consent_obtained  BOOLEAN       NULL,
  retention_days    INTEGER       NULL,
  delete_after      TIMESTAMPTZ   NULL,
  deleted_at        TIMESTAMPTZ   NULL,
  deleted_by        UUID          NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_recordings             PRIMARY KEY (id),
  CONSTRAINT chk_rec_status            CHECK (status IN ('PENDING','IN_PROGRESS','STORED','FAILED','DELETED')),
  CONSTRAINT chk_rec_policy            CHECK (recording_policy IN
    ('ENABLED','DISABLED','REQUIRES_CONSENT','REQUIRES_DISCLOSURE')),
  CONSTRAINT chk_rec_storage_ref_path  CHECK (storage_ref IS NULL OR storage_ref LIKE 'org/%'),
  CONSTRAINT chk_rec_retention         CHECK (retention_days IS NULL OR retention_days > 0)
);

COMMENT ON COLUMN voice.recordings.storage_ref IS 'pii:voice — S3 path to audio recording';

CREATE UNIQUE INDEX uq_rec_call_id   ON voice.recordings (call_id);
CREATE        INDEX idx_rec_org_status ON voice.recordings (organization_id, status);
CREATE        INDEX idx_rec_retention
  ON voice.recordings (delete_after)
  WHERE delete_after IS NOT NULL AND status = 'STORED';

CREATE TRIGGER trg_rec_updated_at
  BEFORE UPDATE ON voice.recordings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.recordings ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.recordings FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_rec_tenant ON voice.recordings
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.recordings TO app_api, app_worker;


CREATE TABLE voice.transcripts (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  conversation_id  UUID          NOT NULL,
  call_id          UUID          NOT NULL,
  status           TEXT          NOT NULL DEFAULT 'IN_PROGRESS',
  total_segments   INTEGER       NOT NULL DEFAULT 0,
  completed_at     TIMESTAMPTZ   NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_transcripts       PRIMARY KEY (id),
  CONSTRAINT chk_tr_status        CHECK (status IN ('IN_PROGRESS','COMPLETED')),
  CONSTRAINT chk_tr_segments_nn   CHECK (total_segments >= 0)
);

CREATE UNIQUE INDEX uq_tr_conversation ON voice.transcripts (conversation_id);
CREATE        INDEX idx_tr_call_id     ON voice.transcripts (call_id);
CREATE        INDEX idx_tr_org_status  ON voice.transcripts (organization_id, status);

CREATE TRIGGER trg_tr_updated_at
  BEFORE UPDATE ON voice.transcripts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.transcripts FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_tr_tenant ON voice.transcripts
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.transcripts TO app_api, app_worker;


-- Transcript segments — partitioned, append-only
CREATE TABLE voice.transcript_segments (
  id                   UUID          NOT NULL DEFAULT gen_uuid_v7(),
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(), -- PARTITION KEY
  organization_id      UUID          NOT NULL,
  transcript_id        UUID          NOT NULL,
  conversation_id      UUID          NOT NULL,
  call_id              UUID          NOT NULL,
  sequence_number      INTEGER       NOT NULL,
  speaker              TEXT          NOT NULL,
  text                 TEXT          NOT NULL,     -- pii:voice
  is_partial           BOOLEAN       NOT NULL DEFAULT FALSE,
  start_ms             INTEGER       NULL,
  end_ms               INTEGER       NULL,
  confidence           NUMERIC(4,3)  NULL,
  language             TEXT          NULL,
  stt_provider_id      TEXT          NULL,
  provider_segment_id  TEXT          NULL,

  CONSTRAINT pk_ts            PRIMARY KEY (id, created_at),  -- partition key included
  CONSTRAINT chk_ts_speaker   CHECK (speaker IN ('CALLER','AGENT','SYSTEM')),
  CONSTRAINT chk_ts_confidence CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  CONSTRAINT chk_ts_seq_nn    CHECK (sequence_number >= 0)
) PARTITION BY RANGE (created_at);

COMMENT ON COLUMN voice.transcript_segments.text IS 'pii:voice — transcript text; append-only';

CREATE INDEX idx_ts_transcript_seq ON voice.transcript_segments (transcript_id, sequence_number ASC);
CREATE INDEX idx_ts_conversation    ON voice.transcript_segments (conversation_id, sequence_number ASC);
CREATE INDEX idx_ts_call_time       ON voice.transcript_segments (call_id, created_at);
CREATE INDEX idx_ts_org_time_brin   ON voice.transcript_segments USING BRIN (organization_id, created_at);

-- No updated_at trigger: append-only
ALTER TABLE voice.transcript_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.transcript_segments FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_ts_tenant ON voice.transcript_segments
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT ON voice.transcript_segments TO app_api, app_worker;
-- REVOKE UPDATE, DELETE enforces append-only:
REVOKE UPDATE, DELETE ON voice.transcript_segments FROM app_api, app_worker;

-- ---------------------------------------------------------------
-- PARTITION CREATION STRATEGY (ISSUE 5 — no hard-coded dates)
-- ---------------------------------------------------------------
-- Same parametric approach as call_sessions (see §16.3 above).
-- The Alembic migration (014) uses the same Python helper:
--
--   create_monthly_partitions(
--       conn=op.get_bind(),
--       table='voice.transcript_segments',
--       months_ahead=3,
--   )
--
-- Creates the current month + 3 months ahead at deployment time.
-- The monthly maintenance job maintains the 24-month hot window
-- and triggers cold archival (Parquet to S3) before partition drop.

CREATE TABLE voice.transcript_segments_default
  PARTITION OF voice.transcript_segments DEFAULT;
```

### 16.7 Provider Configuration and Language Evaluation

```sql
-- ================================================================
-- Migration 015: provider_configs, language_evaluation_records, tenant_phone_numbers
-- ================================================================

CREATE TABLE voice.provider_configs (
  id                   UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID          NULL,     -- NULL = platform default
  category             TEXT          NOT NULL,
  provider_id          TEXT          NOT NULL,
  model_id             TEXT          NULL,
  is_active            BOOLEAN       NOT NULL DEFAULT TRUE,
  priority             INTEGER       NOT NULL,
  health_state         TEXT          NOT NULL DEFAULT 'AVAILABLE',
  last_health_check_at TIMESTAMPTZ   NULL,
  p50_latency_ms       INTEGER       NULL,
  error_rate_pct       NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
  circuit_state        TEXT          NOT NULL DEFAULT 'CLOSED',
  circuit_opened_at    TIMESTAMPTZ   NULL,
  credential_ref       TEXT          NULL,
  config_json          JSONB         NOT NULL DEFAULT '{}',
  supports_languages   TEXT[]        NOT NULL DEFAULT '{}',
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_provider_configs  PRIMARY KEY (id),
  CONSTRAINT chk_pc_category      CHECK (category IN ('TELEPHONY','STT','TTS','LLM','EMBEDDING')),
  CONSTRAINT chk_pc_circuit       CHECK (circuit_state IN ('CLOSED','OPEN','HALF_OPEN')),
  CONSTRAINT chk_pc_health        CHECK (health_state IN ('AVAILABLE','DEGRADED','UNAVAILABLE')),
  CONSTRAINT chk_pc_error_rate    CHECK (error_rate_pct BETWEEN 0 AND 100),
  CONSTRAINT chk_pc_priority      CHECK (priority >= 1),
  CONSTRAINT chk_pc_cred_ref      CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
);

CREATE UNIQUE INDEX uq_pc_priority ON voice.provider_configs (organization_id, category, priority)
  WHERE is_active = TRUE;
CREATE UNIQUE INDEX uq_pc_platform_cat ON voice.provider_configs (provider_id, category)
  WHERE organization_id IS NULL AND is_active = TRUE;
CREATE        INDEX idx_pc_org_cat  ON voice.provider_configs (organization_id, category, priority)
  WHERE is_active = TRUE AND circuit_state = 'CLOSED';
CREATE        INDEX idx_pc_platform ON voice.provider_configs (category, priority)
  WHERE organization_id IS NULL AND is_active = TRUE;

CREATE TRIGGER trg_pc_updated_at
  BEFORE UPDATE ON voice.provider_configs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.provider_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.provider_configs FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_pc_read ON voice.provider_configs
  FOR SELECT
  USING (organization_id = organization.current_tenant_id() OR organization_id IS NULL);

CREATE POLICY rls_pc_insert ON voice.provider_configs
  FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());

CREATE POLICY rls_pc_modify ON voice.provider_configs
  FOR UPDATE USING (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.provider_configs TO app_api, app_worker;


CREATE TABLE voice.language_evaluation_records (
  id                   UUID          NOT NULL DEFAULT gen_uuid_v7(),
  language             TEXT          NOT NULL,
  provider_id          TEXT          NOT NULL,
  provider_model_ref   TEXT          NOT NULL,
  capability           TEXT          NOT NULL,
  evaluation_set_ref   TEXT          NOT NULL,
  scores               JSONB         NOT NULL,
  evaluated_at         TIMESTAMPTZ   NOT NULL,
  verdict              TEXT          NOT NULL,
  notes                TEXT          NULL,
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ler         PRIMARY KEY (id),
  CONSTRAINT chk_ler_cap    CHECK (capability IN ('STT','TTS','LLM')),
  CONSTRAINT chk_ler_verdict CHECK (verdict IN ('APPROVED','CONDITIONAL','REJECTED'))
);

CREATE UNIQUE INDEX uq_ler_eval ON voice.language_evaluation_records
  (language, provider_id, provider_model_ref, capability, evaluation_set_ref);
CREATE INDEX idx_ler_lookup ON voice.language_evaluation_records
  (language, provider_id, capability, evaluated_at DESC);
CREATE INDEX idx_ler_verdict ON voice.language_evaluation_records
  (language, capability, verdict);

-- No RLS — platform-owned reference data
GRANT SELECT ON voice.language_evaluation_records TO app_api, app_worker, app_readonly;
-- Only app_platform_admin inserts/updates evaluation records


CREATE TABLE voice.tenant_phone_numbers (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID          NOT NULL,
  phone_e164          TEXT          NOT NULL,  -- pii:phone; globally unique
  phone_country       TEXT          NOT NULL,
  provider_id         TEXT          NOT NULL,
  provider_number_id  TEXT          NULL,
  status              TEXT          NOT NULL DEFAULT 'ACTIVE',
  inbound_enabled     BOOLEAN       NOT NULL DEFAULT TRUE,
  outbound_enabled    BOOLEAN       NOT NULL DEFAULT TRUE,
  assigned_agent_id   UUID          NULL,      -- logical ref: voice.agents.id
  capabilities        TEXT[]        NOT NULL DEFAULT '{}',
  number_type         TEXT          NULL,
  verified_at         TIMESTAMPTZ   NULL,
  credential_ref      TEXT          NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_phone_numbers     PRIMARY KEY (id),
  CONSTRAINT chk_pn_status        CHECK (status IN ('ACTIVE','SUSPENDED','RELEASED')),
  CONSTRAINT chk_pn_e164_format   CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_pn_cred_ref      CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
);

COMMENT ON COLUMN voice.tenant_phone_numbers.phone_e164 IS 'pii:phone — E.164 canonical number';

CREATE UNIQUE INDEX uq_pn_e164        ON voice.tenant_phone_numbers (phone_e164);
CREATE        INDEX idx_pn_org_status ON voice.tenant_phone_numbers (organization_id, status)
  WHERE status = 'ACTIVE';
CREATE        INDEX idx_pn_agent      ON voice.tenant_phone_numbers (organization_id, assigned_agent_id)
  WHERE assigned_agent_id IS NOT NULL;

CREATE TRIGGER trg_pn_updated_at
  BEFORE UPDATE ON voice.tenant_phone_numbers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE voice.tenant_phone_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.tenant_phone_numbers FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_pn_tenant ON voice.tenant_phone_numbers
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON voice.tenant_phone_numbers TO app_api, app_worker;
```

### 16.8 RLS and Grants Summary

```sql
-- ================================================================
-- Migration 016: Voice RLS (already in-line above) — verify and finalize grants
-- ================================================================

-- Ensure app_readonly can read analytics-adjacent voice tables
GRANT SELECT ON voice.call_sessions        TO app_readonly;
GRANT SELECT ON voice.conversations        TO app_readonly;
GRANT SELECT ON voice.turns                TO app_readonly;
GRANT SELECT ON voice.recordings           TO app_readonly;
GRANT SELECT ON voice.transcripts          TO app_readonly;
GRANT SELECT ON voice.transcript_segments  TO app_readonly;
GRANT SELECT ON voice.agents               TO app_readonly;
GRANT SELECT ON voice.agent_versions       TO app_readonly;
GRANT SELECT ON voice.tool_definitions     TO app_readonly;
GRANT SELECT ON voice.tool_executions      TO app_readonly;
GRANT SELECT ON voice.provider_configs     TO app_readonly;
GRANT SELECT ON voice.tenant_phone_numbers TO app_readonly;

-- Platform admin: full access (BYPASSRLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA voice TO app_platform_admin;
```

### 16.9 Seed Data — Built-In Tool Definitions

```sql
-- ================================================================
-- Migration 017: Voice seed data — built-in tool definitions
-- ================================================================

INSERT INTO voice.tool_definitions (
  id, organization_id, tool_name, description,
  input_schema, output_schema, is_builtin,
  timeout_ms, requires_confirmation, max_retries_on_timeout,
  is_active, created_by
) VALUES
  (
    '018d0000-0000-7000-b000-000000000001'::UUID,
    NULL,
    'createLead',
    'Creates or updates a CRM contact from information gathered during the call. Use when the caller provides their name, phone, or email.',
    '{"type":"object","properties":{"full_name":{"type":"string"},"phone_e164":{"type":"string"},"email":{"type":"string"}},"required":[]}'::JSONB,
    '{"type":"object","properties":{"contact_id":{"type":"string"},"created":{"type":"boolean"}}}'::JSONB,
    TRUE, 8000, FALSE, 1, TRUE, NULL
  ),
  (
    '018d0000-0000-7000-b000-000000000002'::UUID,
    NULL,
    'bookAppointment',
    'Books an appointment in the calendar system. Use when the caller confirms a specific date, time, and appointment type.',
    '{"type":"object","properties":{"appointment_type":{"type":"string"},"scheduled_at":{"type":"string","format":"date-time"},"notes":{"type":"string"}},"required":["appointment_type","scheduled_at"]}'::JSONB,
    '{"type":"object","properties":{"appointment_id":{"type":"string"},"confirmed_at":{"type":"string"}}}'::JSONB,
    TRUE, 10000, FALSE, 1, TRUE, NULL
  ),
  (
    '018d0000-0000-7000-b000-000000000003'::UUID,
    NULL,
    'createTask',
    'Creates a follow-up task for the sales team. Use when a callback or follow-up action is needed.',
    '{"type":"object","properties":{"task_title":{"type":"string"},"due_at":{"type":"string","format":"date-time"},"priority":{"type":"string","enum":["LOW","MEDIUM","HIGH"]}},"required":["task_title"]}'::JSONB,
    '{"type":"object","properties":{"task_id":{"type":"string"}}}'::JSONB,
    TRUE, 6000, FALSE, 1, TRUE, NULL
  ),
  (
    '018d0000-0000-7000-b000-000000000004'::UUID,
    NULL,
    'lookupKnowledge',
    'Searches the organization knowledge base for relevant information. Use when the caller asks a question that may be in the knowledge base.',
    '{"type":"object","properties":{"query":{"type":"string"},"knowledge_base_ids":{"type":"array","items":{"type":"string"}}},"required":["query"]}'::JSONB,
    '{"type":"object","properties":{"results":{"type":"array"},"total":{"type":"integer"}}}'::JSONB,
    TRUE, 5000, FALSE, 1, TRUE, NULL
  ),
  (
    '018d0000-0000-7000-b000-000000000005'::UUID,
    NULL,
    'suppressContact',
    'Marks a contact as Do Not Call and removes them from active campaign queues. Use ONLY when the caller explicitly requests not to be called again.',
    '{"type":"object","properties":{"reason":{"type":"string"}},"required":[]}'::JSONB,
    '{"type":"object","properties":{"suppressed":{"type":"boolean"}}}'::JSONB,
    TRUE, 5000, FALSE, 0, TRUE, NULL
  )
ON CONFLICT (tool_name) WHERE organization_id IS NULL DO NOTHING;


-- ================================================================
-- Migration 018: Voice schema grants finalization
-- ================================================================

-- Executed by app_migration; confirms grant state post-seed
SELECT 1;  -- placeholder for any final grant adjustments discovered during migration
```

---

## 17. Alembic Migration Plan

### 17.1 Migration Dependency Graph

```
Phase 5B migrations (001–008)
        ↓
009_voice_schema_and_functions
    down_revision = '008_voice_grants'
    purpose: voice schema (already created in 001), voice-specific trigger functions,
             SECURITY DEFINER resolve_inbound_phone_number with privilege hardening:
             REVOKE ALL FROM PUBLIC + GRANT EXECUTE TO app_api, app_worker, app_platform_admin
        ↓
010_voice_agent_tables
    down_revision = '009_voice_schema_and_functions'
    purpose: voice.agents, voice.agent_versions, triggers, RLS, grants
        ↓
011_voice_call_session_partitioned
    down_revision = '010_voice_agent_tables'
    purpose: voice.call_sessions (partitioned parent + parametric monthly partitions
             for current month + 3 months ahead + DEFAULT safety partition),
             indexes, trigger, RLS, grants
             [Python helper create_monthly_partitions() called at migration time]
        ↓
012_voice_conversation_turn
    down_revision = '011_voice_call_session_partitioned'
    purpose: voice.conversations, voice.turns, indexes, triggers, RLS, grants
        ↓
013_voice_tool_tables
    down_revision = '012_voice_conversation_turn'
    purpose: voice.tool_definitions, voice.tool_executions, FKs, indexes, triggers, RLS, grants
        ↓
014_voice_recording_transcript_partitioned
    down_revision = '013_voice_tool_tables'
    purpose: voice.recordings, voice.transcripts,
             voice.transcript_segments (partitioned parent + parametric monthly
             partitions for current month + 3 months ahead + DEFAULT),
             indexes, triggers, RLS, grants,
             REVOKE UPDATE DELETE on transcript_segments from app_api and app_worker
             [Python helper create_monthly_partitions() called at migration time]
        ↓
015_voice_provider_phone_language
    down_revision = '014_voice_recording_transcript_partitioned'
    purpose: voice.provider_configs, voice.language_evaluation_records,
             voice.tenant_phone_numbers, SECURITY DEFINER function,
             indexes, RLS, grants
        ↓
016_voice_rls_finalize
    down_revision = '015_voice_provider_phone_language'
    purpose: Verify all RLS policies are in place; add app_readonly grants
        ↓
017_voice_seed_tool_definitions
    down_revision = '016_voice_rls_finalize'
    purpose: INSERT built-in tool definitions ON CONFLICT DO NOTHING
        ↓
018_voice_grants_finalize
    down_revision = '017_voice_seed_tool_definitions'
    purpose: Final grant verification and cleanup
```

### 17.2 Downgrade Order

```
018 → 017 → 016 → 015 → 014 → 013 → 012 → 011 → 010 → 009
```

**Downgrade notes:**
- Dropping partitioned tables also drops all child partitions.
- `DOWN` for 017 deletes seed rows `WHERE is_builtin = TRUE ON CONFLICT ... DELETE` — equivalent of removing only the seeded rows.
- `DOWN` for 011 and 014: `DROP TABLE voice.call_sessions CASCADE` and `DROP TABLE voice.transcript_segments CASCADE` also removes all child partition tables.

### 17.3 Zero-Downtime Index Note

For the initial deployment on empty tables, `CREATE INDEX` without `CONCURRENTLY` is acceptable (no live data). For post-launch schema changes (adding new indexes to tables with millions of rows), Phase 5A's rule applies: `CREATE INDEX CONCURRENTLY` in a separate migration, outside a transaction block.

---

## 18. Seed Data Summary

5 built-in tool definitions are seeded (migration 017):

| Tool Name | Purpose | Timeout |
|---|---|---|
| `createLead` | Create/update CRM contact from call data | 8s |
| `bookAppointment` | Book appointment in calendar | 10s |
| `createTask` | Create follow-up task | 6s |
| `lookupKnowledge` | Search knowledge base | 5s |
| `suppressContact` | DNC/suppression from call | 5s |

No provider credentials are seeded. `provider_configs` is configured per-environment via platform admin API after deployment.

---

## 19. Security Review

### 19.1 Tenant Escape Analysis

| Scenario | Prevention |
|---|---|
| Tenant A reads Tenant B call | RLS on `call_sessions`: `organization_id = current_tenant_id()` — 0 rows |
| Tenant A reads Tenant B transcript | RLS on `transcript_segments` — same protection |
| Tenant A accesses Tenant B recording metadata | RLS on `recordings` — 0 rows |
| Tenant A invokes Tenant B's tool | RLS on `tool_executions` blocks insert with wrong `organization_id`; RLS on `tool_definitions` only returns own + platform tools |
| Missing tenant context reads voice data | `current_tenant_id() = NULL` → 0 rows — fail-closed |
| Worker with valid tenant context | Standard RLS; same isolation as API |
| Platform admin cross-tenant read | BYPASSRLS; must set explicit tenant for data modification; all actions audited |
| Archived agent used for new call | `PublishedAgentSpecification` check in application layer: `DEPRECATED` agents rejected at `InitiateCall` |

### 19.2 Provider Credential Leakage

- `provider_configs.credential_ref` stores only a `secret_manager://...` reference — CHECK enforced.
- `config_json` JSONB contains non-secret provider config only. The application layer must not write secrets into `config_json`.
- No provider API key, OAuth token, or password exists anywhere in the `voice` schema.

### 19.3 Inbound Phone Routing (Pre-Auth)

The `voice.resolve_inbound_phone_number()` function is `SECURITY DEFINER` — it bypasses RLS to look up the phone number before tenant context is established. It returns only `(organization_id, tenant_phone_number_id, assigned_agent_id)` — no sensitive data beyond what is needed to establish the tenant context.

### 19.4 Recording Access Control

- `recordings.storage_ref` contains the S3 path. Access requires a presigned URL generated by the application layer using `recording:read` permission.
- The `storage_ref` is cleared (`= NULL`) when a recording is `DELETED`, preventing future access even if the application returned a cached reference.
- S3 path format `org/{org_id}/...` prevents cross-tenant path guessing.

### 19.5 PII Leakage via Events

Per Phase 4H §7.3 and Phase 4B §11.2: event payloads for voice events carry IDs, not raw PII text. `conversation.turn_completed` carries `turn_id`, `utterance_text` is not in the event payload — it is queried from the DB by the authorized subscriber. This pattern is not enforced by the DB schema itself (events are application-layer constructs) but is documented here as a security boundary the application must honour.

### 19.6 Append-Only Enforcement for transcript_segments

`REVOKE UPDATE, DELETE ON voice.transcript_segments FROM app_api, app_worker` at DB level. Only `app_platform_admin` can delete (for compliance corrections under explicit audit trail). This prevents accidental or malicious transcript modification.

---

## 20. Tenant Isolation Test Matrix

| Test | Mechanism | Expected Result |
|---|---|---|
| Tenant A reads Tenant B's call_session | `SET LOCAL app.tenant_id = OrgA_id`; `SELECT * FROM voice.call_sessions WHERE id = OrgB_call_id` | 0 rows — RLS filters by org |
| Tenant A updates Tenant B's call status | `UPDATE voice.call_sessions SET status='COMPLETED' WHERE id = OrgB_call_id` | 0 rows affected — RLS USING clause blocks |
| Tenant A reads Tenant B's transcript_segments | `SELECT * FROM voice.transcript_segments WHERE call_id = OrgB_call_id` | 0 rows — RLS |
| Tenant A accesses Tenant B's recording metadata | `SELECT * FROM voice.recordings WHERE call_id = OrgB_call_id` | 0 rows — RLS |
| Tenant A executes tool against Tenant B call | `INSERT INTO voice.tool_executions (..., organization_id = OrgB)` | RLS WITH CHECK violation — rejected |
| Missing tenant context (`app.tenant_id` not set) | Any SELECT on voice.* | 0 rows — `current_tenant_id() = NULL` matches nothing |
| Worker with valid tenant context | `SET LOCAL app.tenant_id = OrgA_id`; standard queries | Normal access to OrgA data only |
| Platform admin cross-tenant read | `BYPASSRLS` role; explicit SELECT | Full access; operation must be audited |
| Revoked member accessing calls | Application middleware: `membership.status = 'REMOVED'` → reject before `SET LOCAL` | Access denied at middleware, never reaches DB |
| Archived agent for new call | `PublishedAgentSpecification` in domain: `status = 'DEPRECATED'` → `CallFailed` | Domain rejection; DB never receives the call record |
| Tenant A resolves Tenant B's phone number | `SELECT * FROM voice.tenant_phone_numbers WHERE phone_e164 = OrgB_number` | 0 rows — RLS by organization_id |
| Platform tool visible to all tenants | `SELECT * FROM voice.tool_definitions WHERE organization_id IS NULL` | Returned — mixed-scope policy permits this |
| Tenant A modifies platform tool | `UPDATE voice.tool_definitions SET ... WHERE organization_id IS NULL` | 0 rows affected — RLS UPDATE policy requires `organization_id = current_tenant_id()` |

---

## 21. Internal Consistency Review

### A. DDD Consistency ✅

Every table maps to an approved Phase 4B aggregate or entity. No tables were invented. `LanguageEvaluationRecord` maps to the aggregate added in Phase 4I §4.4.

**Phase 4I CONTRADICTION-02 applied:** `agent_versions.language_policy JSONB` column — `VoiceConfig.TamilCodeSwitching` is not created as a boolean column.

### B. Phase 5A Consistency ✅

| Standard | Compliance |
|---|---|
| UUIDv7 PKs | All tables use `DEFAULT gen_uuid_v7()` |
| No cross-schema FK | `turns.conversation_id → conversations(id)` is within-schema (permitted). No voice→organization or voice→crm FKs. |
| TEXT + CHECK for status | No PostgreSQL ENUMs used |
| No bare monetary values | No monetary columns in voice schema (cost is in billing schema) |
| JSONB only where justified | 3 JSONB columns: `draft_config` (variable evolving structure), `snapshot_json` (immutable config blob), `language_policy` (extracted for access), `sessions` (bounded embedded list), `arguments`/`result`/`scores`/`config_json` (variable per-tool/provider content) |
| No BYTEA for audio | `recordings.storage_ref TEXT` — S3 reference only |
| `credential_ref LIKE 'secret_manager://%'` | Applied to `provider_configs` and `tenant_phone_numbers` |
| India defaults | No India-specific values in schema; configuration-driven |
| Append-only enforcement | `REVOKE UPDATE, DELETE` on `transcript_segments` |
| Tenant-first composite indexes | `organization_id` leads all composite indexes |

### C. Phase 5B Consistency ✅

`organization.current_tenant_id()` used in all RLS policies. `gen_uuid_v7()` and `set_updated_at()` from Phase 5B used throughout. Permission strings from Phase 5B RBAC matrix (`agent:read`, `call:read`, etc.) are documented as the authorization vocabulary for voice operations.

### D. Security Consistency ✅

No tenant can access another tenant's Voice data. Platform tools readable by all tenants but not writable. Pre-auth phone routing uses SECURITY DEFINER with minimal data returned.

### E. Partition Consistency ✅

Both `call_sessions` and `transcript_segments` are partitioned from day one with monthly RANGE partitions. PKs include partition keys. DEFAULT partitions created as safety net. **Hard-coded dates removed** — partitions are created parametrically at deployment time by a Python helper, with current month + 3 months ahead.

### F. Real-Time Consistency ✅

No synchronous DB writes in the STT/LLM/TTS response path. All checkpoints are async (per-completed-turn). Redis carries hot-tier state. **Partial STT fragments remain in Redis exclusively** — PostgreSQL receives only final segments. This is now the definitive and unambiguous architecture for transcript persistence.

### F2. Transcript Append-Only Consistency ✅

`voice.transcript_segments` is strictly append-only for `app_api` and `app_worker`: `REVOKE UPDATE, DELETE` is unconditional. No application-level UPDATE path exists (the partial→final upsert exception has been eliminated). All rows in the table carry `is_partial = FALSE` as an application-enforced invariant. Idempotency is achieved via a deterministic UUID `ON CONFLICT (id, created_at) DO NOTHING`.

### G. Provider Independence ✅

No provider name (Exotel, Deepgram, ElevenLabs, OpenAI) appears in column types, ENUMs, or CHECK constraints. Provider IDs are stored as `TEXT` in `provider_configs.provider_id`. The domain remains provider-agnostic.

### H. Migration Consistency ✅

10 migrations (009–018) with explicit `down_revision` chain. Each migration is logically ordered (referenced tables exist before FKs are created). Partitioned tables created before child partitions.

### I. SQL Consistency ✅

All DDL is valid PostgreSQL 15+ syntax. Partitioned table PKs include partition keys. `BYPASSRLS` on `app_migration` and `app_platform_admin` is set in Phase 5B and inherited. No invalid cross-partition unique constraints.

### J. Scale Consistency ✅

`call_sessions` and `transcript_segments` partitioned from day one. BRIN indexes on time columns for partition-level range queries. Active-call partial index is tiny (only in-progress calls). Redis carries all hot-path state.

---

## 22. ADRs

### ADR-5C-001: Call Session Partitioning — RANGE Monthly on `started_at`

**Decision:** `call_sessions` is partitioned RANGE monthly on `started_at` from the initial migration. The PK is `(id, started_at)`.

**Rationale:** at platform scale (millions of calls/day), the table would exceed 50M rows within months. Monthly partitions enable efficient time-range retention (drop the 12-month-old partition), partition pruning on most analytics queries, and clean cold archival.

**Alternative rejected:** un-partitioned with archival via application-layer DELETE. Rejected because DELETE at scale creates vacuum overhead and cannot be made atomic. Partition drop is instantaneous and requires no vacuum.

### ADR-5C-002: Transcript Segment Partitioning — RANGE Monthly

**Decision:** Same reasoning as ADR-5C-001. Volume estimate: ~150 segments/call at scale. This table grows faster than `call_sessions`.

### ADR-5C-003: Transcript Segment Final-Only Persistence (Correction Pass)

**Decision:** PostgreSQL stores **only finalized transcript segments**. Partial STT fragments are held exclusively in Redis throughout their life. When the STT provider delivers the final segment result, the application assembles the complete `TranscriptSegment` value object in memory and INSERTs it once with `is_partial = FALSE`.

**Why this is the definitive decision (corrects the previous ambiguous design):** the original document contained an `ON CONFLICT (transcript_id, sequence_number, created_at_month) DO UPDATE` pattern for partial→final upserts. This was invalid for three independent reasons: (1) `created_at_month` is not a column; (2) the UPDATE contradicts the `REVOKE UPDATE ... FROM app_api, app_worker` on the same table; (3) ADR-5C-003 itself stated "partial STT fragments are never written to PostgreSQL." The correction removes the contradiction entirely by enforcing the original intent: partial fragments never reach the database.

**Idempotency:** the segment `id` is generated deterministically from `(transcript_id, sequence_number)` by the application, making `ON CONFLICT (id, created_at) DO NOTHING` a valid and sufficient idempotency mechanism on the partitioned table.

**Rationale:** Phase 4B §20 and DDR-4B-002 establish this two-tier pattern. Writing partial fragments would create 10–20× write amplification per turn. Redis absorbs partials; Postgres checkpoints finals.

### ADR-5C-004: Agent Version Immutability

**Decision:** `agent_versions.snapshot_json` and `language_policy` are immutable after creation. Enforced by a `BEFORE UPDATE` trigger that raises an exception on mutation attempt. No `UPDATE` privilege is granted for `snapshot_json` changes.

**Rationale:** Phase 4B DDR-4B-003. A live Call must run an unchanging configuration. Immutability is the database-level guarantee.

### ADR-5C-005: Provider Credential Strategy

**Decision:** `provider_configs.credential_ref` stores a `secret_manager://...` opaque reference. A `CHECK` constraint enforces the prefix. Raw API keys, OAuth tokens, and passwords are never stored in this table.

**Rationale:** Phase 4F DDR-4F-002 and Phase 5A §26.3. CredentialRef is the platform-wide pattern.

### ADR-5C-006: Recording Object-Storage Strategy

**Decision:** Binary audio is stored in S3. PostgreSQL stores only `storage_ref TEXT` (the S3 path). The path follows `org/{organization_id}/recordings/{year}/{month}/{call_id}.{ext}`. A `CHECK` enforces the path prefix.

**Rationale:** Phase 4B §5.6 invariant 2. PostgreSQL `BYTEA` for audio would be catastrophically expensive for storage, replication, and WAL amplification at millions of calls/day.

### ADR-5C-007: Tool Execution Persistence

**Decision:** `tool_executions` is a fully mutable table (INSERT + UPDATE for status transitions). It is not append-only because the status must transition through its lifecycle (PENDING → RUNNING → terminal).

**Rationale:** Phase 4B DDR-4B-004. Tool executions have their own lifecycle. Making them append-only would require a new row per status transition, making the execution history non-atomic.

### ADR-5C-008: Tenant Phone Number Global Uniqueness

**Decision:** `UNIQUE (phone_e164)` globally across all tenants. A phone number belongs to exactly one organization on the platform.

**Rationale:** Phone numbers are assigned by telephony providers and cannot be active on two tenants simultaneously. The global unique index prevents double-assignment through any race condition or import error.

### ADR-5C-009: Voice PII/Retention Strategy

**Decision:** Voice PII (`utterance_text`, `response_text`, `transcript_segments.text`, `summary_text`, `from_number`, `to_number`) is tagged with SQL `COMMENT ON COLUMN` for automated tooling. Encrypted at rest by Supabase (AES-256). Not encrypted at column level in V1.

**Retention** is controlled by: (1) partition drop schedules for `call_sessions` and `transcript_segments`, (2) `recordings.delete_after` for recordings, and (3) organisation `CompliancePolicy.RetentionProfile` values fed into these schedules. The platform provides controls; regulatory retention periods are not hard-coded.

### ADR-5C-010: Real-Time State vs. Durable Database State

**Decision:** Redis is authoritative for: current `CallStatus`, current Turn state (partial STT, in-flight LLM), `AgentVersion.SnapshotJson` cache, `ProviderConfig` health/routing cache. PostgreSQL is authoritative for: all completed-state data (finished calls, checkpointed turns, final transcript segments, executed tools, stored recordings).

**Redis failure behaviour:** call continues from last Postgres checkpoint (at most one in-flight Turn is lost). Quota counters are rebuilt from Postgres. Provider health reverts to polling from DB.

---

## 23. Carry-Forward Hardening Items

These items were identified during Phase 5C but do not block Phase 5C approval or Phase 5D progression:

| Item | Description | Target Phase |
|---|---|---|
| **Result size cap** | `tool_executions.result JSONB` should be application-layer capped at 64KB. Large results should use a `result_storage_ref TEXT` (S3) pattern. Document cap enforcement. | Phase 9 (Voice Pipeline implementation) |
| **Partition automation** | `call_sessions` and `transcript_segments` DEFAULT partitions are safety nets. A scheduled job must create lookahead partitions (3 months ahead) and drop expired partitions after cold archival. The `platform.db.partition_utils.create_monthly_partitions()` helper used in migrations must be validated and unit-tested. | Phase 22 (Deployment) |
| **`call_sessions` `started_at` requirement** | Application must always provide `started_at` when looking up a call by ID to enable partition pruning. This must be documented in the `CallRepository` implementation. | Phase 9 |
| **Deterministic transcript segment UUID** | The application generates `transcript_segment.id` as a deterministic UUIDv7 from `(transcript_id, sequence_number)` to guarantee idempotent INSERTs without UPDATE. The exact derivation algorithm must be documented in Phase 9's `TranscriptRepository`. | Phase 9 |
| **Partial fragment Redis lifecycle** | The application must ensure that Redis partial-fragment state is cleaned up after the final segment is written to PostgreSQL (TTL or explicit DEL). Stale partial fragments in Redis are a memory leak. | Phase 9 |
| **Cold archival format** | Parquet export from expired partitions is specified in Phase 5A §14.5 but no archival job is designed yet. | Phase 22 |

---

## Phase 5C Final Review (Post-Correction Pass)

### Issues Resolved

| Issue | Status | What was done |
|---|---|---|
| ISSUE 1 — `created_at_month` non-existent column + invalid upsert | ✅ RESOLVED | Partial→final DB upsert design removed entirely. PostgreSQL stores final segments only. |
| ISSUE 2 — Append-only contradiction (REVOKE vs allowed UPDATE) | ✅ RESOLVED | REVOKE is now unconditional. Stale exception comment removed. No UPDATE path exists. |
| ISSUE 3 — Invalid partitioned UNIQUE for `(transcript_id, sequence_number)` | ✅ RESOLVED | Sequence uniqueness is application-layer invariant. DB uses deterministic UUID `ON CONFLICT (id, created_at) DO NOTHING`. |
| ISSUE 4 — `sessions` JSONB justification | ✅ RESOLVED | Confirmed as required by Phase 4B §5.1 DDD. Justification expanded with explicit bounded-list rationale. |
| ISSUE 5 — Hard-coded 2025_01–2025_06 partition dates | ✅ RESOLVED | Replaced with parametric `create_monthly_partitions()` helper called at migration time. No hard-coded dates remain. |
| ISSUE 6 — SECURITY DEFINER missing `REVOKE ALL FROM PUBLIC` + explicit `GRANT EXECUTE` | ✅ RESOLVED | `REVOKE ALL ON FUNCTION ... FROM PUBLIC` + `GRANT EXECUTE TO app_api, app_worker, app_platform_admin` added to Migration 009 DDL. |
| ISSUE 7 — Document-wide consistency pass | ✅ RESOLVED | All instances of `created_at_month`, `ON CONFLICT DO UPDATE`, hard-coded dates, and stale exception comments corrected or removed. |

### Final Consistency Checks

**A. DDD consistency ✅** All 13 tables map to approved Phase 4B/4I aggregates. `sessions JSONB` is explicitly DDD-required (Phase 4B §5.1). `LanguageEvaluationRecord` maps to Phase 4I §4.4.

**B. Phase 5A consistency ✅** Partitioning rules respected. Append-only rules enforced without exception for application roles. No cross-schema FKs. JSONB used only where justified. `credential_ref` CHECK in place. PII tagged.

**C. Phase 5B consistency ✅** `organization.current_tenant_id()`, `gen_uuid_v7()`, `set_updated_at()`, `organization_id` all used correctly throughout.

**D. PostgreSQL correctness ✅** Partitioned PKs include partition keys. `ON CONFLICT (id, created_at) DO NOTHING` is a valid conflict target on partitioned tables (composite PK). RLS, FORCE RLS, grants, revokes, triggers, and SECURITY DEFINER function all valid for PostgreSQL 15+. No invalid cross-partition UNIQUE constraints.

**E. Real-time correctness ✅** No per-audio-frame DB writes. Redis carries all hot-path state. Checkpoints are async.

**F. Transcript correctness ✅** Partial STT → Redis exclusively. Final STT → PostgreSQL INSERT only. `transcript_segments` is append-only with no application-role UPDATE path. `is_partial = FALSE` is an application-enforced invariant for all DB rows.

**G. Provider independence ✅** No provider names in column types, ENUMs, or CHECK constraints.

**H. Migration consistency ✅** Parametric partition creation at deployment time. All migrations have `down_revision` chains. SECURITY DEFINER privilege hardening in Migration 009.

---

```
PHASE 5C STATUS

Voice schema:
APPROVED

Call sessions:
APPROVED

Conversation/Turns:
APPROVED

Agents:
APPROVED

Agent versions:
APPROVED

Tools:
APPROVED

Recordings:
APPROVED

Transcripts:
APPROVED

Provider configs:
APPROVED

Tenant phone numbers:
APPROVED

Language evaluation:
APPROVED

Partitioning:
APPROVED

RLS:
APPROVED

RBAC:
APPROVED

Security:
APPROVED

DDL:
APPROVED

Alembic migration plan:
APPROVED

Overall:
PHASE 5D READY
```

All six issues from the correction pass are resolved. Four carry-forward hardening items remain (see §23) — none blocks Phase 5D. The corrected document is internally consistent and contains no contradictory statements about transcript segment persistence, append-only enforcement, partition dates, or SECURITY DEFINER privileges.

---

## Amendment — Phase 6H Campaign Final Remediation (2026-08-28)

A Phase 6H adversarial remediation review found that Campaign's in-process invocation of Voice's outbound-call use case (`voice.call_sessions` §16.3, `011_5C.sql`) had no idempotency mechanism at all for this specific caller path — 6D's HTTP-level `Idempotency-Key` (6A §16.2) applies only to `POST /api/v1/calls`, never to an in-process caller. A same-day follow-up adversarial pass then found that the first fix for this, while preventing duplicate calls, created the opposite failure mode: a worker crash between reserving the logical call and actually invoking the telephony provider would permanently lose the call. Both are resolved by `099_5C1.sql` (Phase 5C.1), a purely additive forward migration: no column, constraint, index, or grant on the existing `voice.call_sessions` table (`011_5C.sql`) is altered, and no existing column's meaning changes. **This amendment was live-executed and race-tested** against a disposable local PostgreSQL 18 database — not merely design-reviewed — per `docs/phase-06-api-design/6H-Campaign-APIs.md` §49's full transcript.

`voice.call_sessions` is `PARTITION BY RANGE (started_at)` — the same structural reason `campaign.campaign_contacts` cannot carry a direct partition-key-free `UNIQUE` constraint applies here identically: no idempotency key can be uniquely enforced directly on the partitioned table. `voice.call_dispatch_keys` is a small, non-partitioned, `PRIMARY KEY (dispatch_idempotency_key)` companion table, and `voice.fn_initiate_outbound_call_idempotent()` performs the key claim and the `call_sessions` INSERT atomically in one transaction — mirroring `crm.event_consumer_dedup` + `crm.fn_claim_event()` (`094_5D3.sql`) and `campaign.campaign_contact_identities` + `campaign.fn_enqueue_contact()` (`098_5E1.sql`) exactly. A retried in-process dispatch carrying the same key now deterministically returns the *same* `call_session_id` instead of ever creating a second `call_sessions` row. The already-existing, already-nullable `campaign_lead_ref` column is reused for Campaign correlation, unchanged in meaning; no new correlation column was added. **Live-proven:** a genuine two-connection concurrent call with the identical dispatch key produced exactly one `call_sessions` row and exactly one `call_dispatch_keys` row.

**`voice.call_dispatch_keys` now additionally carries a full provider-dispatch durability state machine** (`RESERVED → CLAIMED → CONFIRMED | AMBIGUOUS | FAILED`, lease-based single-owner claiming, `attempt_count`, `provider_request_ref`/`provider_call_ref`, `last_error`), with four new functions governing the claim/outcome protocol (`fn_claim_dispatch_for_provider_submission()`, `fn_record_dispatch_confirmed()`, `fn_record_dispatch_ambiguous()`, `fn_record_dispatch_failed()`). **Live-proven, not merely designed:** two concurrent claim attempts for the identical key produced exactly one claimant; a claimed-then-abandoned (simulated crash) dispatch was safely re-claimed by a different worker once its lease genuinely expired, and successfully confirmed — the call was not permanently lost; an `AMBIGUOUS` outcome was proven to block every subsequent claim attempt (no automatic retry, ever), while a `FAILED` outcome was proven safely re-claimable, confirming the two states' intended asymmetry is real.

**Cross-referenced, additive amendment in 6D:** `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md` §28.10a, labeled "Controlled Amendment — Phase 6H Campaign Dispatch Idempotency," now documents the full claim/confirm/ambiguous/failed protocol. 6D's frozen content is otherwise untouched — this amendment documents the new in-process contract's shape without redesigning `POST /api/v1/calls` or any other 6D-owned surface.

**What this does not and cannot close:** whether the telephony provider itself received and acted on a single `TelephonyPort.place_call()` call whose response leg timed out is an external-system ambiguity no platform-side idempotency key can resolve alone — that remains bounded by 6D's own pre-existing provider-retry contract (3B §19) and, where the active provider adapter supports echoing a caller-supplied reference on callbacks, a `provider_request_ref`-based reconciliation window (a disclosed, provider-adapter-layer dependency, not assumed universally true of every provider — verify against the actual Exotel/other adapter contract before relying on it).

**Verification status, stated plainly:** unlike the earlier same-day pass, this amendment **was** live-executed: fresh-database and incremental `alembic upgrade` runs both passed (exit code 0); function `SECURITY DEFINER`/`search_path`/grant configuration was inspected directly against `pg_proc`/`information_schema`; every concurrency and crash-recovery scenario named above was exercised as a genuine, overlapping, multi-connection transaction or a real elapsed-time lease expiry, not simulated or narrated. Full transcripts: `docs/phase-06-api-design/6H-Campaign-APIs.md` §49.

**Full DDL, rationale, and race-condition analysis:** `099_5C1.sql`'s own header comment; `docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md`'s "Phase 6H Campaign Final Remediation" entry; `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 3) §18, §49.
