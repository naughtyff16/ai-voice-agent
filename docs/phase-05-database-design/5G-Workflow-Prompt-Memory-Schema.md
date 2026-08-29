# Phase 5G — Workflow / Prompt Management / Conversation Memory Schema
## Physical PostgreSQL Database Design

| | |
|---|---|
| **Phase** | 5G — Workflow / Prompt Management / Conversation Memory Schema |
| **Schemas** | `workflow`, `prompt`, `memory` |
| **Status** | Draft v1.0 — for approval before Phase 5H |
| **Authority** | Phase 5A + Phase 5B + Phase 4E (DDD — §5, §6, §7, §8, §18) |
| **Follows** | Phase 5F (APPROVED, PHASE 5G READY) |
| **Precedes** | Phase 5H — Billing / Usage Schema |

---

## 1. Executive Summary

This document delivers the complete physical database design for three bounded contexts:

| Schema | DDD Context | Aggregates |
|---|---|---|
| `workflow` | Workflow Engine | `WorkflowDefinition`, `WorkflowExecution` |
| `prompt` | Prompt Management | `PromptTemplate`, `PromptExperiment` |
| `memory` | Conversation Memory | `SessionMemory`, `CustomerMemory` |

**Critical DDD decisions applied here:**

| Decision | Outcome |
|---|---|
| `WorkflowDefinition.DraftGraph` | Embedded as `draft_graph JSONB` — entire graph is always read/written as a unit at publish time (Phase 4E §5.1 rationale) |
| `WorkflowDefinition.Versions` | Separate `workflow_versions` table — bounded at ~50 per workflow but `version_id` is independently queryable for execution pinning |
| `WorkflowExecution.NodeExecutionHistory` | Embedded as `node_execution_history JSONB` — bounded by call length; always read with execution |
| `WorkflowExecution.Slots` | Embedded as `slots JSONB` — accumulated monotonically, always read whole |
| `PromptTemplate.Versions` | Separate `prompt_versions` table — independently queryable by environment assignment |
| `SessionMemory.Turns` | Redis hot-tier during call; `turns JSONB` column on Postgres for post-call checkpoint |
| `CustomerMemory.Facts` | `facts JSONB` — bounded at ~100 facts, always read whole |
| Partitioning | `workflow_executions`: RANGE monthly on `started_at` |
| No per-node tables | Phase 4E §5.1 explicit rationale: graph embedded in JSONB |

**Tables created in Phase 5G:** 8 tables (1 partitioned), complete RLS, 2 SECURITY DEFINER functions, immutability triggers.

---

## 2. Scope

**In scope:**
- `workflow` schema: `workflow_definitions`, `workflow_versions`, `workflow_executions`
- `prompt` schema: `prompt_templates`, `prompt_versions`, `prompt_experiments`
- `memory` schema: `session_memories`, `customer_memories`

**Out of scope (other phases):**
- `voice.*`, `crm.*`, `campaign.*`, `knowledge.*` — frozen
- `billing.*`, `analytics.*`, `audit.*` — Phase 5H+

---

## 3. Bounded Context Ownership

### 3.1 Workflow Context Owns
- Workflow definition (name, description, status, draft graph, published version reference)
- Workflow versions (immutable published graph snapshots)
- Workflow execution state (cursor, slots, node history) — durable checkpoint; Redis carries hot-tier

### 3.2 Prompt Context Owns
- Prompt template (name, status, draft content, variable schema, active version per environment)
- Prompt versions (immutable published content + schema)
- Prompt experiments (A/B variant routing configuration)

### 3.3 Memory Context Owns
- Session memory (per-call turn list + summary) — durable post-call record; Redis is hot-tier during call
- Customer memory (cross-call facts + last summary) — permanent per-contact store

### 3.4 What Phase 5G Does NOT Own

| Owned by | Phase 5G must NOT duplicate |
|---|---|
| Phase 5C (Voice) | `call_sessions`, `conversations`, `agents`, `agent_versions` |
| Phase 5D (CRM) | `contacts`, `consent_records`, `contact_suppressions` |
| Phase 5E (Campaign) | `campaigns`, `campaign_contacts`, `call_jobs` |
| Phase 5F (Knowledge) | `knowledge_bases`, `documents`, `document_chunks` |

---

## 4. Aggregate → Table Mapping

| Phase 4E Aggregate | Table | Storage notes |
|---|---|---|
| `WorkflowDefinition` (AggregateRoot) | `workflow.workflow_definitions` | `draft_graph JSONB`; `published_version_id` is publication gate |
| `WorkflowVersion` (Entity — child of WorkflowDefinition) | `workflow.workflow_versions` | Separate table; `graph_json JSONB` immutable after write |
| `WorkflowExecution` (AggregateRoot) | `workflow.workflow_executions` | Partitioned RANGE monthly; `slots JSONB`, `node_execution_history JSONB` |
| `PromptTemplate` (AggregateRoot) | `prompt.prompt_templates` | `draft_content TEXT`, `draft_variable_schema JSONB`, `active_versions JSONB` |
| `PromptVersion` (Entity — child of PromptTemplate) | `prompt.prompt_versions` | Separate table; `content TEXT` + `variable_schema JSONB` immutable after publish |
| `PromptExperiment` (AggregateRoot) | `prompt.prompt_experiments` | `variants JSONB` — bounded 2–4 variants; always read whole |
| `SessionMemory` (AggregateRoot) | `memory.session_memories` | `turns JSONB` — post-call checkpoint; Redis is hot-tier during call |
| `CustomerMemory` (AggregateRoot) | `memory.customer_memories` | `facts JSONB` — bounded ~100 facts; always read whole |

**Why no separate node/edge tables (ADR-5G-001):**
Phase 4E §5.1 explicitly states the rationale for JSONB graph embedding: "The full graph is embedded (not split across tables) because (a) it is always read and written as a whole unit at publish time, and (b) even large workflows rarely exceed a few hundred nodes, which fits comfortably in a JSONB column." No DDD entity defines `WorkflowNode` or `WorkflowEdge` as independently addressable aggregates with their own lifecycle. They are embedded entities within `DraftGraph`.

---

## 5. Domain Invariants

| # | Invariant | DDD Source | Enforcement |
|---|---|---|---|
| INV-WF-01 | `WorkflowVersion.GraphJson` is immutable once written | Phase 4E §5.1 inv.8 | `BEFORE UPDATE` trigger on `workflow_versions.graph_json` |
| INV-WF-02 | `ARCHIVED` workflow definitions cannot be published again | Phase 4E §5.1 inv.7 | `fn_workflow_publish()` precondition: `status != 'ARCHIVED'` |
| INV-WF-03 | `WorkflowExecution.WorkflowVersionRef` is pinned at start and immutable | Phase 4E §5.2 inv.1 | `BEFORE UPDATE` trigger on `workflow_executions.workflow_version_id` |
| INV-WF-04 | A COMPLETED or FAILED Execution is immutable | Phase 4E §5.2 inv.4 | `BEFORE UPDATE` trigger: rejects mutation when `OLD.status IN ('COMPLETED','FAILED')` |
| INV-WF-05 | `published_version_id` on `workflow_definitions` may only reference a version of that workflow | Phase 5G design (analogous to INV-12 in Phase 5F) | `fn_workflow_publish()` verifies `workflow_version.workflow_definition_id = p_workflow_id` |
| INV-PM-01 | `PromptVersion.Content` is immutable once published | Phase 4E §6.1 inv.1 | `BEFORE UPDATE` trigger on `prompt_versions.content` |
| INV-PM-02 | `PromptVersion.VariableSchema` is immutable once published | Phase 4E §6.1 inv.2 | Same trigger |
| INV-PM-03 | `ActiveVersionByEnvironment` must reference a published version of the same prompt | Phase 4E §6.1 inv.3 | `fn_prompt_set_active()` verifies existence |
| INV-PM-04 | Experiment variant weights must sum to 100 | Phase 4E §6.2 inv.1 | CHECK constraint on `prompt_experiments.variants` |
| INV-MEM-01 | `SessionMemory.SequenceNo` is monotonically increasing — no gaps, no duplicates | Phase 4E §8.1 inv.1 | Application layer; Redis enforces during call |
| INV-MEM-02 | A COMPLETED SessionMemory's `turns` list is immutable; `summary` may still be set | Phase 4E §8.1 inv.2 | `BEFORE UPDATE` trigger: rejects `turns` change when `status = 'COMPLETED'` |
| INV-MEM-03 | `CustomerMemory.MemoryFact.Key` is unique within a CustomerMemory | Phase 4E §8.1 inv on Facts | Application layer enforces via upsert; JSONB key uniqueness validated at write |

---

## 6. Table Dictionary

### 6.1 `workflow.workflow_definitions`

**Aggregate:** `WorkflowDefinition` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `name` | TEXT | NOT NULL | — | 1–200 chars; unique within tenant |
| `description` | TEXT | NULL | — | 0–500 chars |
| `status` | TEXT | NOT NULL | `'DRAFT'` | `DRAFT \| PUBLISHED \| ARCHIVED` |
| `published_version_id` | UUID | NULL | — | Logical ref: `workflow.workflow_versions.id`. Publication gate. NULL = no published version yet. |
| `draft_graph` | JSONB | NOT NULL | `'{}'` | `DraftGraph` — `{entry_node_id, nodes: [...], edges: [...]}`. Mutable. |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`draft_graph` JSONB structure:**
```json
{
  "entry_node_id": "<uuid>",
  "nodes": [
    {"node_id": "<uuid>", "node_type": "LLM", "label": "Main", "config": {...}}
  ],
  "edges": [
    {"edge_id": "<uuid>", "source_node_id": "<uuid>", "target_node_id": "<uuid>",
     "condition": {"expression": "slots.intent == 'buy'", "on_slot": null}}
  ]
}
```

**Why `draft_graph` is JSONB:** Phase 4E §5.1 explicit DDD rationale — always read/written as a whole unit. Nodes and edges are embedded entities, not independent aggregates.

### 6.2 `workflow.workflow_versions`

**Entity:** `WorkflowVersion` (child of WorkflowDefinition — separate table)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref; for RLS |
| `workflow_definition_id` | UUID | NOT NULL | — | FK → `workflow_definitions(id)` CASCADE |
| `version_number` | INTEGER | NOT NULL | — | Monotonically increasing per workflow. **Immutable.** |
| `graph_json` | JSONB | NOT NULL | — | Immutable snapshot of `DraftGraph` at publish time (INV-WF-01). |
| `published_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id`. **Immutable.** |
| `published_at` | TIMESTAMPTZ | NOT NULL | — | **Immutable.** |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`graph_json` is immutable after write** (INV-WF-01). A `BEFORE UPDATE` trigger raises an exception if `graph_json`, `version_number`, `published_by`, or `published_at` changes.

**No `updated_at` column:** workflow versions are immutable reference data. No mutation after creation.

### 6.3 `workflow.workflow_executions` (Partitioned — RANGE monthly on `started_at`)

**Aggregate:** `WorkflowExecution` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | Part of composite PK `(id, started_at)` |
| `started_at` | TIMESTAMPTZ | NOT NULL | — | **Partition key.** |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `workflow_version_id` | UUID | NOT NULL | — | Logical ref: `workflow.workflow_versions.id`. **Pinned and immutable (INV-WF-03).** |
| `session_ref` | UUID | NOT NULL | — | Logical ref: `voice.call_sessions.id` — the Phase 4B SessionId |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| COMPLETED \| FAILED` |
| `current_node_id` | UUID | NULL | — | Current cursor position. Updated on each turn advance. |
| `slots` | JSONB | NOT NULL | `'{}'` | `SlotMap` — `{slot_name: slot_value}`. Monotonically accumulated. |
| `turn_count_at_node` | JSONB | NOT NULL | `'{}'` | `{node_id: turn_count}` — for `max_turns` enforcement. |
| `node_execution_history` | JSONB | NOT NULL | `'[]'` | Bounded list of `NodeExecution` entities. Always read whole with execution. |
| `completed_at` | TIMESTAMPTZ | NULL | — | Set once when COMPLETED or FAILED. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`node_execution_history` JSONB element structure:**
```json
{
  "node_execution_id": "<uuid>",
  "node_id": "<uuid>",
  "entered_at": "<iso8601>",
  "exited_at": "<iso8601|null>",
  "directive": "SPEAK",
  "slot_updates": {"caller_name": "Priya"}
}
```

**Why `node_execution_history` is JSONB:** Phase 4E §5.2 defines it as an embedded list bounded by call length (a call has ~10–50 turns; each produces ~1–3 node executions). It is always read with the execution aggregate and never independently queried by `NodeExecutionId`. JSONB is appropriate per Phase 5A §4.1.

**Partition rationale:** executions are high-volume (one per call session), append/update-heavy, and retention-bounded. RANGE monthly on `started_at` mirrors the call_sessions partitioning strategy from Phase 5C.

**Redis hot-tier:** during an active call, the latest execution state is in Redis (`workflow_exec:{session_id}` key). PostgreSQL receives a checkpoint write after each turn completes (async Celery task — not in the LLM/STT response path). Phase 4E §14.2 and §18 confirm this two-tier model.

### 6.4 `prompt.prompt_templates`

**Aggregate:** `PromptTemplate` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `name` | TEXT | NOT NULL | — | 1–200 chars; unique within tenant |
| `description` | TEXT | NULL | — | 0–500 chars |
| `status` | TEXT | NOT NULL | `'DRAFT'` | `DRAFT \| PUBLISHED \| ARCHIVED` |
| `draft_content` | TEXT | NULL | — | Jinja2 template string (max 50000 chars). Mutable draft. |
| `draft_variable_schema` | JSONB | NOT NULL | `'[]'` | `list[PromptVariable]` — draft schema for editing. Mutable. |
| `active_versions` | JSONB | NOT NULL | `'{}'` | `{environment: version_number}` — `ActiveVersionByEnvironment`. Updated via `SetActiveVersion`. |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`draft_variable_schema` JSONB element:**
```json
{"name": "caller_name", "type": "STRING", "required": true, "default_value": null}
```

**`active_versions` JSONB:**
```json
{"local": 1, "staging": 2, "production": 2}
```

**Why `active_versions` is JSONB:** `ActiveVersionByEnvironment` is a bounded dict (3 environments: `local | staging | production`). Always read whole with the template. Mutated atomically via the `SetActiveVersion` command. JSONB is appropriate.

### 6.5 `prompt.prompt_versions`

**Entity:** `PromptVersion` (child of PromptTemplate — separate table)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref; for RLS |
| `prompt_template_id` | UUID | NOT NULL | — | FK → `prompt_templates(id)` CASCADE |
| `version_number` | INTEGER | NOT NULL | — | Monotonically increasing per template. **Immutable.** |
| `content` | TEXT | NOT NULL | — | Jinja2 template string. **Immutable after publish (INV-PM-01).** |
| `variable_schema` | JSONB | NOT NULL | — | Immutable `list[PromptVariable]` snapshot (INV-PM-02). |
| `published_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id`. **Immutable.** |
| `published_at` | TIMESTAMPTZ | NOT NULL | — | **Immutable.** |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Content and schema immutability (INV-PM-01, INV-PM-02):** a `BEFORE UPDATE` trigger raises an exception if `content`, `variable_schema`, `version_number`, `published_by`, or `published_at` changes. No `updated_at` column — no mutations after creation.

### 6.6 `prompt.prompt_experiments`

**Aggregate:** `PromptExperiment` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `prompt_template_id` | UUID | NOT NULL | — | Logical ref: `prompt.prompt_templates.id`. Aggregate independence → logical. |
| `name` | TEXT | NOT NULL | — | 1–200 chars |
| `status` | TEXT | NOT NULL | `'DRAFT'` | `DRAFT \| ACTIVE \| COMPLETED \| CANCELLED` |
| `variants` | JSONB | NOT NULL | — | `list[ExperimentVariant]` — 2–4 variants (INV-PM-04). Always read whole. |
| `assignment_basis` | TEXT | NOT NULL | `'SESSION_ID'` | `SESSION_ID \| USER_ID` |
| `started_at` | TIMESTAMPTZ | NULL | — | Set when ACTIVE |
| `completed_at` | TIMESTAMPTZ | NULL | — | Set when COMPLETED or CANCELLED |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`variants` JSONB element:**
```json
{
  "variant_id": "<uuid>",
  "label": "control",
  "prompt_version_id": "<uuid>",
  "weight_pct": 50
}
```

**CHECK on variants:** the invariant "weights sum to 100" is a function of the JSONB array contents. This is validated at application layer by `CreateExperiment` and `AdjustVariantWeights` use cases. A DB-level CHECK cannot sum array elements portably without a custom function. Documented as application-enforced invariant.

### 6.7 `memory.session_memories`

**Aggregate:** `SessionMemory` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `session_ref` | UUID | NOT NULL | — | Logical ref: `voice.call_sessions.id` (Phase 4B `SessionId`) |
| `conversation_ref` | UUID | NOT NULL | — | Logical ref: `voice.conversations.id` |
| `contact_ref` | UUID | NULL | — | Logical ref: `crm.contacts.id`. Set if contact matched. |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| COMPLETED \| SUMMARIZED` |
| `compression_level` | TEXT | NOT NULL | `'NONE'` | `NONE \| SUMMARIZED \| COMPRESSED` |
| `turns` | JSONB | NOT NULL | `'[]'` | `list[MemoryTurn]` — post-call checkpoint. Immutable when `status = 'COMPLETED'`. **pii:voice** |
| `summary` | TEXT | NULL | — | LLM-generated narrative. Set by async summarization task. **pii:voice** |
| `started_at` | TIMESTAMPTZ | NOT NULL | — | |
| `completed_at` | TIMESTAMPTZ | NULL | — | Set on call end. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Redis hot-tier:** during an active call, turns are appended to Redis (`session_memory:{session_id}` as a RLIST) via fire-and-forget. After the call ends, the `conversation.completed` event triggers a Celery worker that reads the Redis turn list, writes the full `turns JSONB` to Postgres, and kicks off LLM summarization (DDR-4E-005). The Postgres row exists before the call ends (created by `BeginSessionMemory`), with `turns = '[]'` until post-call checkpoint.

**`turns` JSONB element:**
```json
{"turn_id": "<uuid>", "sequence_no": 1, "speaker": "CALLER", "text": "Hello, I'd like to..."}
```

**`turns` immutability when COMPLETED (INV-MEM-02):** a `BEFORE UPDATE` trigger raises an exception if `turns` changes after `status = 'COMPLETED'`. The `summary` field may still be set by the async summarization task after `COMPLETED` status.

### 6.8 `memory.customer_memories`

**Aggregate:** `CustomerMemory` (AggregateRoot)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref |
| `contact_ref` | UUID | NOT NULL | — | Logical ref: `crm.contacts.id`. UNIQUE within org. |
| `facts` | JSONB | NOT NULL | `'[]'` | `list[MemoryFact]` — bounded ~100 facts. **pii:potential** |
| `last_call_summary` | TEXT | NULL | — | Summary from most recent call. Updated by `memory.session_summarized` event. **pii:voice** |
| `last_call_at` | TIMESTAMPTZ | NULL | — | When the last call occurred. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**`facts` JSONB element:**
```json
{
  "key": "caller_name",
  "value": "Priya Sharma",
  "confidence": 0.95,
  "source": "CALL:session_id_xyz",
  "recorded_at": "2026-03-15T10:30:00Z"
}
```

**One `CustomerMemory` per contact per tenant** — UNIQUE on `(organization_id, contact_ref)`.

**Fact key uniqueness (INV-MEM-03):** the application layer maintains key uniqueness within the `facts` array via upsert semantics — on `UpdateFact`, if a key already exists, the existing fact is updated (or supplemented per Phase 4E §8.1 confidence rules). JSONB does not enforce key uniqueness within an array at DB level; this is an application-enforced invariant.

---

## 7. JSONB Justification Summary

| Column | Table | Why JSONB | Size bound |
|---|---|---|---|
| `draft_graph` | `workflow_definitions` | Phase 4E §5.1: always read/written as unit at publish time; nodes/edges are embedded entities | ~few hundred nodes; rarely > 100KB |
| `node_execution_history` | `workflow_executions` | Phase 4E §5.2: bounded by call length; always read with execution; never queried by NodeExecutionId | ~10–50 entries per call |
| `slots` | `workflow_executions` | SlotMap — always read whole; accumulated monotonically | ~10–50 slot key-value pairs |
| `turn_count_at_node` | `workflow_executions` | Dict of node_id→count; always read whole | ~10–50 entries |
| `graph_json` | `workflow_versions` | Immutable snapshot of DraftGraph at publish time | Same as `draft_graph` |
| `draft_variable_schema` | `prompt_templates` | Variable schema — bounded, always read with template during editing | ≤ 50 variables |
| `active_versions` | `prompt_templates` | Dict of 3 environments → version numbers | 3 entries always |
| `variable_schema` | `prompt_versions` | Immutable snapshot of variable schema at publish time | ≤ 50 variables |
| `variants` | `prompt_experiments` | ExperimentVariant list — 2–4 entries, always read whole | 2–4 entries |
| `turns` | `session_memories` | MemoryTurn list — bounded by call length; always read whole for context assembly | ~10–100 turns per call |
| `facts` | `customer_memories` | MemoryFact list — bounded at ~100 per contact; always read whole | ≤ 100 entries |

No generic `metadata JSONB` escape hatches exist in this schema.

---

## 8. Unique Constraints

| Table | Columns | Condition | Rationale |
|---|---|---|---|
| `workflow.workflow_definitions` | `(organization_id, name)` | — | Unique workflow name per tenant |
| `workflow.workflow_versions` | `(workflow_definition_id, version_number)` | — | Unique version per workflow |
| `workflow.workflow_executions` | `(session_ref, organization_id)` | `WHERE status = 'ACTIVE'` | At most one active execution per session |
| `prompt.prompt_templates` | `(organization_id, name)` | — | Unique prompt name per tenant |
| `prompt.prompt_versions` | `(prompt_template_id, version_number)` | — | Unique version per template |
| `memory.session_memories` | `session_ref` | — | One session memory per call session |
| `memory.customer_memories` | `(organization_id, contact_ref)` | — | One customer memory per contact per tenant |

---

## 9. Check Constraints

```sql
-- workflow_definitions
CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED'))
CHECK (length(name) BETWEEN 1 AND 200)
CHECK (description IS NULL OR length(description) <= 500)

-- workflow_versions
CHECK (version_number >= 1)

-- workflow_executions
CHECK (status IN ('ACTIVE','COMPLETED','FAILED'))

-- prompt_templates
CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED'))
CHECK (length(name) BETWEEN 1 AND 200)
CHECK (draft_content IS NULL OR length(draft_content) <= 50000)

-- prompt_versions
CHECK (version_number >= 1)
CHECK (length(content) <= 50000)

-- prompt_experiments
CHECK (status IN ('DRAFT','ACTIVE','COMPLETED','CANCELLED'))
CHECK (assignment_basis IN ('SESSION_ID','USER_ID'))

-- session_memories
CHECK (status IN ('ACTIVE','COMPLETED','SUMMARIZED'))
CHECK (compression_level IN ('NONE','SUMMARIZED','COMPRESSED'))

-- customer_memories: no status column — always active
```

---

## 10. Index Strategy

### 10.1 `workflow.workflow_definitions`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_workflow_defs` | `id` | UNIQUE B-tree (PK) | |
| `uq_wfd_name` | `(organization_id, name)` | UNIQUE B-tree | |
| `idx_wfd_org_status` | `(organization_id, status)` | B-tree | |
| `idx_wfd_published_version` | `published_version_id` | B-tree | `WHERE published_version_id IS NOT NULL` |

### 10.2 `workflow.workflow_versions`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_workflow_versions` | `id` | UNIQUE B-tree (PK) | |
| `uq_wv_version_number` | `(workflow_definition_id, version_number)` | UNIQUE B-tree | |
| `idx_wv_org` | `organization_id` | B-tree | RLS support |

### 10.3 `workflow.workflow_executions` (Partitioned)

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_workflow_execs` | `(id, started_at)` | UNIQUE B-tree (PK) | |
| `uq_we_active_session` | `(session_ref, organization_id)` | PARTIAL UNIQUE B-tree | `WHERE status = 'ACTIVE'` |
| `idx_we_session_ref` | `(session_ref, organization_id)` | B-tree | — |
| `idx_we_org_status` | `(organization_id, status)` | B-tree | `WHERE status = 'ACTIVE'` |
| `idx_we_version` | `(organization_id, workflow_version_id, started_at DESC)` | B-tree | Version analytics |
| `idx_we_brin` | `(organization_id, started_at)` | BRIN | Partition-level range scans |

### 10.4 `prompt.prompt_templates`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_prompt_templates` | `id` | UNIQUE B-tree (PK) | |
| `uq_pt_name` | `(organization_id, name)` | UNIQUE B-tree | |
| `idx_pt_org_status` | `(organization_id, status)` | B-tree | |

### 10.5 `prompt.prompt_versions`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_prompt_versions` | `id` | UNIQUE B-tree (PK) | |
| `uq_pv_version_number` | `(prompt_template_id, version_number)` | UNIQUE B-tree | |
| `idx_pv_template` | `prompt_template_id` | B-tree | |
| `idx_pv_org` | `organization_id` | B-tree | RLS support |

### 10.6 `prompt.prompt_experiments`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_prompt_experiments` | `id` | UNIQUE B-tree (PK) | |
| `idx_pe_org_status` | `(organization_id, status)` | B-tree | `WHERE status = 'ACTIVE'` |
| `idx_pe_template` | `(organization_id, prompt_template_id)` | B-tree | |

### 10.7 `memory.session_memories`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_session_memories` | `id` | UNIQUE B-tree (PK) | |
| `uq_sm_session_ref` | `session_ref` | UNIQUE B-tree | One per session |
| `idx_sm_contact_ref` | `(organization_id, contact_ref)` | B-tree | `WHERE contact_ref IS NOT NULL` |
| `idx_sm_org_status` | `(organization_id, status)` | B-tree | |

### 10.8 `memory.customer_memories`

| Index | Columns | Type | Condition |
|---|---|---|---|
| `pk_customer_memories` | `id` | UNIQUE B-tree (PK) | |
| `uq_cm_contact_ref` | `(organization_id, contact_ref)` | UNIQUE B-tree | One per contact per tenant |

---

## 11. Partitioning

### 11.1 `workflow.workflow_executions` — RANGE monthly on `started_at`

One execution per call; at platform scale (millions of calls/day) this table grows unboundedly. RANGE monthly mirrors Phase 5C `call_sessions` partitioning.

```sql
CREATE TABLE workflow.workflow_executions (...)
PARTITION BY RANGE (started_at);

-- Partitions created parametrically:
--   create_monthly_partitions(conn, 'workflow.workflow_executions', months_ahead=3)
CREATE TABLE workflow.workflow_executions_default
  PARTITION OF workflow.workflow_executions DEFAULT;
```

Retention: follows call_sessions (12 months hot). PK includes partition key: `(id, started_at)`.

### 11.2 No Other Phase 5G Table Requires Day-One Partitioning

| Table | Reasoning |
|---|---|
| `workflow_definitions` | Bounded — one row per workflow definition; at most hundreds of thousands |
| `workflow_versions` | Bounded — max ~50 versions per workflow |
| `prompt_templates` | Bounded — small per tenant |
| `prompt_versions` | Bounded |
| `prompt_experiments` | Bounded |
| `session_memories` | One per call — grows with calls, but primary store is summarized. Post-call summarization keeps the table from growing unboundedly. Revisit at scale if `turns JSONB` size is a concern. |
| `customer_memories` | One per contact — small |

---

## 12. RLS Architecture

Standard tenant policy applied to all tables:

```sql
ALTER TABLE <schema>.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <schema>.<table> FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_<table>_tenant ON <schema>.<table>
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

Applied to all 8 tables.

---

## 13. Grants / Revokes

```sql
-- Standard application grants
GRANT SELECT, INSERT, UPDATE ON workflow.workflow_definitions    TO app_api, app_worker;
GRANT SELECT, INSERT          ON workflow.workflow_versions       TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE  ON workflow.workflow_executions     TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE  ON prompt.prompt_templates         TO app_api, app_worker;
GRANT SELECT, INSERT          ON prompt.prompt_versions           TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE  ON prompt.prompt_experiments        TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE  ON memory.session_memories         TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE  ON memory.customer_memories        TO app_api, app_worker;

-- app_readonly: analytics
GRANT SELECT ON ALL TABLES IN SCHEMA workflow TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA prompt   TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA memory   TO app_readonly;

-- app_platform_admin: full access (BYPASSRLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA prompt   TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA memory   TO app_platform_admin;

-- No REVOKE needed for normal tables — standard UPDATE is appropriate.
-- Immutability is enforced by triggers, not privilege revocation, because
-- lifecycle mutations (e.g. execution cursor advance) require UPDATE.
-- Exception: workflow_versions and prompt_versions have no UPDATE grant
-- (app roles receive only INSERT) — immutability is belt-and-suspenders
-- via trigger + no UPDATE privilege.
REVOKE UPDATE, DELETE ON workflow.workflow_versions FROM app_api, app_worker;
REVOKE UPDATE, DELETE ON prompt.prompt_versions    FROM app_api, app_worker;
```

---

## 14. Immutability Triggers

```sql
-- 14.1 workflow_versions: GraphJson and identity fields immutable (INV-WF-01)
CREATE OR REPLACE FUNCTION workflow.prevent_wf_version_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.graph_json IS DISTINCT FROM NEW.graph_json OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.published_by IS DISTINCT FROM NEW.published_by OR
     OLD.published_at IS DISTINCT FROM NEW.published_at THEN
    RAISE EXCEPTION
      'workflow_versions fields are immutable. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- 14.2 workflow_executions: workflow_version_id pinned at creation (INV-WF-03)
-- And COMPLETED/FAILED executions are immutable (INV-WF-04)
CREATE OR REPLACE FUNCTION workflow.prevent_execution_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.workflow_version_id IS DISTINCT FROM NEW.workflow_version_id THEN
    RAISE EXCEPTION
      'workflow_executions.workflow_version_id is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.status IN ('COMPLETED','FAILED') THEN
    RAISE EXCEPTION
      'COMPLETED or FAILED workflow_executions are immutable. execution_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- 14.3 prompt_versions: content and identity immutable (INV-PM-01, INV-PM-02)
CREATE OR REPLACE FUNCTION prompt.prevent_pv_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.content IS DISTINCT FROM NEW.content OR
     OLD.variable_schema IS DISTINCT FROM NEW.variable_schema OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.published_by IS DISTINCT FROM NEW.published_by OR
     OLD.published_at IS DISTINCT FROM NEW.published_at THEN
    RAISE EXCEPTION
      'prompt_versions fields are immutable. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- 14.4 session_memories: turns immutable when COMPLETED (INV-MEM-02)
CREATE OR REPLACE FUNCTION memory.prevent_completed_turns_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'COMPLETED' AND OLD.turns IS DISTINCT FROM NEW.turns THEN
    RAISE EXCEPTION
      'session_memories.turns is immutable after status=COMPLETED. session_memory_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
```

## 15. SECURITY DEFINER Functions

### 15.1 `fn_workflow_publish()` — Publish a Workflow Version

```sql
CREATE OR REPLACE FUNCTION workflow.fn_workflow_publish(
  p_workflow_id         UUID,
  p_new_version_id      UUID,
  p_organization_id     UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, pg_temp
AS $$
BEGIN
  -- Verify version belongs to THIS workflow and THIS tenant (analogous to INV-12)
  IF NOT EXISTS (
    SELECT 1 FROM workflow.workflow_versions
    WHERE id                    = p_new_version_id
      AND workflow_definition_id = p_workflow_id       -- ownership check
      AND organization_id       = p_organization_id
  ) THEN
    RAISE EXCEPTION
      'fn_workflow_publish: version does not belong to this workflow or tenant. '
      'workflow_id: %, version_id: %', p_workflow_id, p_new_version_id;
  END IF;

  -- Verify the workflow exists, belongs to tenant, and is not ARCHIVED (INV-WF-02)
  IF NOT EXISTS (
    SELECT 1 FROM workflow.workflow_definitions
    WHERE id              = p_workflow_id
      AND organization_id = p_organization_id
      AND status         != 'ARCHIVED'
  ) THEN
    RAISE EXCEPTION
      'fn_workflow_publish: workflow not found, not owned by tenant, or ARCHIVED. '
      'workflow_id: %', p_workflow_id;
  END IF;

  -- Set published_version_id and update status to PUBLISHED
  UPDATE workflow.workflow_definitions
  SET published_version_id = p_new_version_id,
      status               = 'PUBLISHED',
      updated_at           = NOW()
  WHERE id              = p_workflow_id
    AND organization_id = p_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_workflow_publish(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_workflow_publish(UUID, UUID, UUID)
  TO app_api, app_worker, app_platform_admin;
```

### 15.2 `fn_prompt_set_active()` — Set Active Version for Environment

```sql
CREATE OR REPLACE FUNCTION prompt.fn_prompt_set_active(
  p_prompt_id       UUID,
  p_version_number  INTEGER,
  p_environment     TEXT,
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = prompt, organization, pg_temp
AS $$
BEGIN
  -- Verify version exists and belongs to this template and tenant (INV-PM-03)
  IF NOT EXISTS (
    SELECT 1 FROM prompt.prompt_versions
    WHERE prompt_template_id = p_prompt_id
      AND version_number     = p_version_number
      AND organization_id    = p_organization_id
  ) THEN
    RAISE EXCEPTION
      'fn_prompt_set_active: version % not found for prompt % and tenant.',
      p_version_number, p_prompt_id;
  END IF;

  IF p_environment NOT IN ('local','staging','production') THEN
    RAISE EXCEPTION 'Invalid environment: %. Must be local, staging, or production.', p_environment;
  END IF;

  UPDATE prompt.prompt_templates
  SET active_versions = jsonb_set(
        active_versions,
        ARRAY[p_environment],
        to_jsonb(p_version_number)
      ),
      updated_at = NOW()
  WHERE id              = p_prompt_id
    AND organization_id = p_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION prompt.fn_prompt_set_active(UUID, INTEGER, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION prompt.fn_prompt_set_active(UUID, INTEGER, TEXT, UUID)
  TO app_api, app_worker, app_platform_admin;
```

---

## 16. Complete PostgreSQL DDL

### 16.1 Schemas and Functions

```sql
-- ================================================================
-- Migration 039: Phase 5G schemas and all functions/triggers
-- ================================================================

GRANT USAGE ON SCHEMA workflow TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA prompt   TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA memory   TO app_api, app_worker, app_readonly, app_platform_admin;

-- All trigger function definitions (§14) and SECURITY DEFINER functions (§15) go here.
```

### 16.2 Workflow Tables

```sql
-- ================================================================
-- Migration 040: workflow.workflow_definitions and workflow_versions
-- ================================================================

CREATE TABLE workflow.workflow_definitions (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL,
  name                  TEXT          NOT NULL,
  description           TEXT          NULL,
  status                TEXT          NOT NULL DEFAULT 'DRAFT',
  published_version_id  UUID          NULL,
  draft_graph           JSONB         NOT NULL DEFAULT '{}',
  created_by            UUID          NOT NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_workflow_definitions    PRIMARY KEY (id),
  CONSTRAINT chk_wfd_status             CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
  CONSTRAINT chk_wfd_name_len           CHECK (length(name) BETWEEN 1 AND 200),
  CONSTRAINT chk_wfd_desc_len           CHECK (description IS NULL OR length(description) <= 500)
);

CREATE UNIQUE INDEX uq_wfd_name        ON workflow.workflow_definitions (organization_id, name);
CREATE        INDEX idx_wfd_org_status ON workflow.workflow_definitions (organization_id, status);
CREATE        INDEX idx_wfd_pub_ver    ON workflow.workflow_definitions (published_version_id)
  WHERE published_version_id IS NOT NULL;

CREATE TRIGGER trg_wfd_updated_at
  BEFORE UPDATE ON workflow.workflow_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE workflow.workflow_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.workflow_definitions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wfd_tenant ON workflow.workflow_definitions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON workflow.workflow_definitions TO app_api, app_worker;


CREATE TABLE workflow.workflow_versions (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID          NOT NULL,
  workflow_definition_id  UUID          NOT NULL,
  version_number          INTEGER       NOT NULL,
  graph_json              JSONB         NOT NULL,
  published_by            UUID          NOT NULL,
  published_at            TIMESTAMPTZ   NOT NULL,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_workflow_versions     PRIMARY KEY (id),
  CONSTRAINT fk_wv_definition         FOREIGN KEY (workflow_definition_id)
    REFERENCES workflow.workflow_definitions(id) ON DELETE CASCADE,
  CONSTRAINT uq_wv_version_number     UNIQUE (workflow_definition_id, version_number),
  CONSTRAINT chk_wv_version_number    CHECK (version_number >= 1)
);

CREATE INDEX idx_wv_org ON workflow.workflow_versions (organization_id);

CREATE TRIGGER trg_wv_immutable
  BEFORE UPDATE ON workflow.workflow_versions
  FOR EACH ROW EXECUTE FUNCTION workflow.prevent_wf_version_mutation();

ALTER TABLE workflow.workflow_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.workflow_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wv_tenant ON workflow.workflow_versions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON workflow.workflow_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON workflow.workflow_versions FROM app_api, app_worker;


-- ================================================================
-- Migration 041: workflow.workflow_executions (partitioned)
-- ================================================================

CREATE TABLE workflow.workflow_executions (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  started_at              TIMESTAMPTZ   NOT NULL,            -- PARTITION KEY
  organization_id         UUID          NOT NULL,
  workflow_version_id     UUID          NOT NULL,            -- pinned (INV-WF-03)
  session_ref             UUID          NOT NULL,
  status                  TEXT          NOT NULL DEFAULT 'ACTIVE',
  current_node_id         UUID          NULL,
  slots                   JSONB         NOT NULL DEFAULT '{}',
  turn_count_at_node      JSONB         NOT NULL DEFAULT '{}',
  node_execution_history  JSONB         NOT NULL DEFAULT '[]',
  completed_at            TIMESTAMPTZ   NULL,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_workflow_executions   PRIMARY KEY (id, started_at),
  CONSTRAINT chk_we_status            CHECK (status IN ('ACTIVE','COMPLETED','FAILED'))
) PARTITION BY RANGE (started_at);

COMMENT ON COLUMN workflow.workflow_executions.workflow_version_id IS
  'Pinned at execution start (INV-WF-03) — immutable. Enforced by trigger.';
COMMENT ON COLUMN workflow.workflow_executions.session_ref IS
  'logical ref: voice.call_sessions.id — Phase 4B SessionId';

CREATE UNIQUE INDEX uq_we_active_session
  ON workflow.workflow_executions (session_ref, organization_id)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_we_session_ref
  ON workflow.workflow_executions (session_ref, organization_id);
CREATE INDEX idx_we_org_active
  ON workflow.workflow_executions (organization_id, status)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_we_version
  ON workflow.workflow_executions (organization_id, workflow_version_id, started_at DESC);
CREATE INDEX idx_we_brin
  ON workflow.workflow_executions USING BRIN (organization_id, started_at);

CREATE TRIGGER trg_we_updated_at
  BEFORE UPDATE ON workflow.workflow_executions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_we_immutable
  BEFORE UPDATE ON workflow.workflow_executions
  FOR EACH ROW EXECUTE FUNCTION workflow.prevent_execution_mutation();

ALTER TABLE workflow.workflow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.workflow_executions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_we_tenant ON workflow.workflow_executions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON workflow.workflow_executions TO app_api, app_worker;

-- Parametric monthly partitions via create_monthly_partitions()
CREATE TABLE workflow.workflow_executions_default
  PARTITION OF workflow.workflow_executions DEFAULT;
```

### 16.3 Prompt Tables

```sql
-- ================================================================
-- Migration 042: prompt.prompt_templates, prompt_versions, prompt_experiments
-- ================================================================

CREATE TABLE prompt.prompt_templates (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID          NOT NULL,
  name                    TEXT          NOT NULL,
  description             TEXT          NULL,
  status                  TEXT          NOT NULL DEFAULT 'DRAFT',
  draft_content           TEXT          NULL,
  draft_variable_schema   JSONB         NOT NULL DEFAULT '[]',
  active_versions         JSONB         NOT NULL DEFAULT '{}',
  created_by              UUID          NOT NULL,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_prompt_templates    PRIMARY KEY (id),
  CONSTRAINT chk_pt_status          CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
  CONSTRAINT chk_pt_name_len        CHECK (length(name) BETWEEN 1 AND 200),
  CONSTRAINT chk_pt_draft_len       CHECK (draft_content IS NULL OR
    length(draft_content) <= 50000)
);

CREATE UNIQUE INDEX uq_pt_name        ON prompt.prompt_templates (organization_id, name);
CREATE        INDEX idx_pt_org_status ON prompt.prompt_templates (organization_id, status);

CREATE TRIGGER trg_pt_updated_at
  BEFORE UPDATE ON prompt.prompt_templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE prompt.prompt_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt.prompt_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pt_tenant ON prompt.prompt_templates
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON prompt.prompt_templates TO app_api, app_worker;


CREATE TABLE prompt.prompt_versions (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID          NOT NULL,
  prompt_template_id  UUID          NOT NULL,
  version_number      INTEGER       NOT NULL,
  content             TEXT          NOT NULL,
  variable_schema     JSONB         NOT NULL,
  published_by        UUID          NOT NULL,
  published_at        TIMESTAMPTZ   NOT NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_prompt_versions      PRIMARY KEY (id),
  CONSTRAINT fk_pv_template          FOREIGN KEY (prompt_template_id)
    REFERENCES prompt.prompt_templates(id) ON DELETE CASCADE,
  CONSTRAINT uq_pv_version_number    UNIQUE (prompt_template_id, version_number),
  CONSTRAINT chk_pv_version_number   CHECK (version_number >= 1),
  CONSTRAINT chk_pv_content_len      CHECK (length(content) <= 50000)
);

CREATE INDEX idx_pv_template ON prompt.prompt_versions (prompt_template_id);
CREATE INDEX idx_pv_org      ON prompt.prompt_versions (organization_id);

CREATE TRIGGER trg_pv_immutable
  BEFORE UPDATE ON prompt.prompt_versions
  FOR EACH ROW EXECUTE FUNCTION prompt.prevent_pv_mutation();

ALTER TABLE prompt.prompt_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt.prompt_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pv_tenant ON prompt.prompt_versions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON prompt.prompt_versions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON prompt.prompt_versions FROM app_api, app_worker;


CREATE TABLE prompt.prompt_experiments (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID          NOT NULL,
  prompt_template_id  UUID          NOT NULL,     -- logical ref (aggregate independence)
  name                TEXT          NOT NULL,
  status              TEXT          NOT NULL DEFAULT 'DRAFT',
  variants            JSONB         NOT NULL,
  assignment_basis    TEXT          NOT NULL DEFAULT 'SESSION_ID',
  started_at          TIMESTAMPTZ   NULL,
  completed_at        TIMESTAMPTZ   NULL,
  created_by          UUID          NOT NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_prompt_experiments    PRIMARY KEY (id),
  CONSTRAINT chk_pe_status            CHECK (status IN ('DRAFT','ACTIVE','COMPLETED','CANCELLED')),
  CONSTRAINT chk_pe_assignment_basis  CHECK (assignment_basis IN ('SESSION_ID','USER_ID'))
);

CREATE INDEX idx_pe_org_active  ON prompt.prompt_experiments (organization_id, status)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_pe_template    ON prompt.prompt_experiments (organization_id, prompt_template_id);

CREATE TRIGGER trg_pe_updated_at
  BEFORE UPDATE ON prompt.prompt_experiments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE prompt.prompt_experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt.prompt_experiments FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pe_tenant ON prompt.prompt_experiments
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON prompt.prompt_experiments TO app_api, app_worker;
```

### 16.4 Memory Tables

```sql
-- ================================================================
-- Migration 043: memory.session_memories and memory.customer_memories
-- ================================================================

CREATE TABLE memory.session_memories (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  session_ref      UUID          NOT NULL,
  conversation_ref UUID          NOT NULL,
  contact_ref      UUID          NULL,
  status           TEXT          NOT NULL DEFAULT 'ACTIVE',
  compression_level TEXT         NOT NULL DEFAULT 'NONE',
  turns            JSONB         NOT NULL DEFAULT '[]',   -- pii:voice (post-call checkpoint)
  summary          TEXT          NULL,                    -- pii:voice
  started_at       TIMESTAMPTZ   NOT NULL,
  completed_at     TIMESTAMPTZ   NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_session_memories    PRIMARY KEY (id),
  CONSTRAINT uq_sm_session_ref      UNIQUE (session_ref),
  CONSTRAINT chk_sm_status          CHECK (status IN ('ACTIVE','COMPLETED','SUMMARIZED')),
  CONSTRAINT chk_sm_compression     CHECK (compression_level IN ('NONE','SUMMARIZED','COMPRESSED'))
);

COMMENT ON COLUMN memory.session_memories.turns   IS 'pii:voice — turn text transcripts';
COMMENT ON COLUMN memory.session_memories.summary IS 'pii:voice — LLM-generated call summary';
COMMENT ON COLUMN memory.session_memories.session_ref IS
  'logical ref: voice.call_sessions.id — Phase 4B SessionId';
COMMENT ON COLUMN memory.session_memories.conversation_ref IS
  'logical ref: voice.conversations.id';
COMMENT ON COLUMN memory.session_memories.contact_ref IS
  'logical ref: crm.contacts.id — set if contact matched during call';

CREATE INDEX idx_sm_contact_ref ON memory.session_memories (organization_id, contact_ref)
  WHERE contact_ref IS NOT NULL;
CREATE INDEX idx_sm_org_status  ON memory.session_memories (organization_id, status);

CREATE TRIGGER trg_sm_updated_at
  BEFORE UPDATE ON memory.session_memories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_sm_turns_immutable
  BEFORE UPDATE ON memory.session_memories
  FOR EACH ROW EXECUTE FUNCTION memory.prevent_completed_turns_mutation();

ALTER TABLE memory.session_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory.session_memories FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_sm_tenant ON memory.session_memories
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON memory.session_memories TO app_api, app_worker;


CREATE TABLE memory.customer_memories (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  contact_ref      UUID          NOT NULL,
  facts            JSONB         NOT NULL DEFAULT '[]',   -- pii:potential
  last_call_summary TEXT         NULL,                    -- pii:voice
  last_call_at     TIMESTAMPTZ   NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_customer_memories   PRIMARY KEY (id),
  CONSTRAINT uq_cm_contact_ref      UNIQUE (organization_id, contact_ref)
);

COMMENT ON COLUMN memory.customer_memories.facts           IS 'pii:potential — customer facts extracted from calls';
COMMENT ON COLUMN memory.customer_memories.last_call_summary IS 'pii:voice — summary from last call';
COMMENT ON COLUMN memory.customer_memories.contact_ref IS
  'logical ref: crm.contacts.id — authoritative contact identity';

CREATE TRIGGER trg_cm_updated_at
  BEFORE UPDATE ON memory.customer_memories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE memory.customer_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory.customer_memories FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cm_tenant ON memory.customer_memories
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON memory.customer_memories TO app_api, app_worker;
```

### 16.5 Grants Finalization

```sql
-- ================================================================
-- Migration 044: Phase 5G grants finalization
-- ================================================================
GRANT SELECT ON ALL TABLES IN SCHEMA workflow TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA prompt   TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA memory   TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA prompt   TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA memory   TO app_platform_admin;
```

---

## 17. Query Patterns

### QP-01: Create Workflow

```sql
-- SET LOCAL app.tenant_id = $org_id
INSERT INTO workflow.workflow_definitions
  (id, organization_id, name, description, status, draft_graph, created_by)
VALUES ($id, $org_id, $name, $desc, 'DRAFT', '{}', $user_id);
```

### QP-02: Update Draft Graph

```sql
UPDATE workflow.workflow_definitions
SET draft_graph = $new_graph_json, updated_at = NOW()
WHERE id = $workflow_id
  AND organization_id = organization.current_tenant_id()
  AND status IN ('DRAFT','PUBLISHED');  -- ARCHIVED cannot be edited
```

### QP-03: Publish Workflow Version

```sql
-- Step 1: Snapshot DraftGraph into a new WorkflowVersion
INSERT INTO workflow.workflow_versions
  (id, organization_id, workflow_definition_id, version_number, graph_json, published_by, published_at)
VALUES ($ver_id, $org_id, $workflow_id, $next_version_number,
        (SELECT draft_graph FROM workflow.workflow_definitions WHERE id = $workflow_id
         AND organization_id = organization.current_tenant_id()),
        $user_id, NOW());

-- Step 2: Set published_version_id via SECURITY DEFINER (verifies ownership)
SELECT workflow.fn_workflow_publish($workflow_id, $ver_id, $org_id);
```

### QP-04: Retrieve Published Workflow Version for Execution

```sql
SELECT wv.id, wv.graph_json, wv.version_number
FROM workflow.workflow_versions wv
JOIN workflow.workflow_definitions wd ON wd.id = wv.workflow_definition_id
  AND wd.organization_id = organization.current_tenant_id()
  AND wd.published_version_id = wv.id  -- only the current published version
WHERE wv.id = $version_id
  AND wv.organization_id = organization.current_tenant_id();
-- Cached in Redis: workflow_version:{version_id}:graph → 1h TTL (immutable data)
```

### QP-05: Start Workflow Execution

```sql
INSERT INTO workflow.workflow_executions
  (id, started_at, organization_id, workflow_version_id, session_ref, status,
   current_node_id, slots, turn_count_at_node, node_execution_history)
VALUES ($id, NOW(), $org_id, $version_id, $session_ref, 'ACTIVE',
        $entry_node_id, '{}', '{}', '[]');
-- unique partial index prevents duplicate active execution for same session
```

### QP-06: Claim and Advance Execution (Per-Turn Checkpoint)

```sql
-- Redis is authoritative during the call (no SELECT FOR UPDATE in hot path)
-- Post-turn checkpoint (async Celery task):
UPDATE workflow.workflow_executions
SET current_node_id        = $next_node_id,
    slots                  = $updated_slots,
    turn_count_at_node     = $updated_turn_count,
    node_execution_history = $updated_history,
    updated_at             = NOW()
WHERE id           = $execution_id
  AND started_at  >= $started_at_hint    -- partition pruning
  AND organization_id = organization.current_tenant_id()
  AND status = 'ACTIVE';                 -- optimistic: no-op if already completed
-- Index: pk_workflow_executions (id, started_at)
```

### QP-07: Complete Execution

```sql
UPDATE workflow.workflow_executions
SET status       = 'COMPLETED',
    completed_at = NOW(),
    updated_at   = NOW()
WHERE id = $execution_id
  AND started_at >= $started_at_hint
  AND organization_id = organization.current_tenant_id()
  AND status = 'ACTIVE';
-- After: trigger blocks any further UPDATE via INV-WF-04
```

### QP-08: Publish Prompt Version

```sql
-- Step 1: Insert immutable version row
INSERT INTO prompt.prompt_versions
  (id, organization_id, prompt_template_id, version_number,
   content, variable_schema, published_by, published_at)
VALUES ($ver_id, $org_id, $template_id, $next_version_number,
        (SELECT draft_content FROM prompt.prompt_templates
         WHERE id = $template_id AND organization_id = organization.current_tenant_id()),
        (SELECT draft_variable_schema FROM prompt.prompt_templates
         WHERE id = $template_id AND organization_id = organization.current_tenant_id()),
        $user_id, NOW());

-- Step 2: Update template status
UPDATE prompt.prompt_templates
SET status = 'PUBLISHED', updated_at = NOW()
WHERE id = $template_id AND organization_id = organization.current_tenant_id();
```

### QP-09: Resolve Active Prompt Version for Environment

```sql
SELECT pv.id, pv.content, pv.variable_schema, pv.version_number
FROM prompt.prompt_templates pt
JOIN prompt.prompt_versions pv ON pv.prompt_template_id = pt.id
  AND pv.version_number = (pt.active_versions->>$environment)::integer
  AND pv.organization_id = organization.current_tenant_id()
WHERE pt.id = $template_id
  AND pt.organization_id = organization.current_tenant_id()
  AND pt.status != 'ARCHIVED';
-- Cached in Redis: prompt:{prompt_id}:{environment}:active → prompt_version_id (TTL 5m)
-- Invalidated by prompt.rolled_back and prompt.version_published events
```

### QP-10: Load Customer Memory

```sql
SELECT id, facts, last_call_summary, last_call_at
FROM memory.customer_memories
WHERE organization_id = organization.current_tenant_id()
  AND contact_ref = $contact_id;
-- Index: uq_cm_contact_ref (O(1))
```

### QP-11: Upsert Customer Memory (Post-Call Summarization)

```sql
INSERT INTO memory.customer_memories
  (id, organization_id, contact_ref, facts, last_call_summary, last_call_at)
VALUES ($id, $org_id, $contact_id, $facts_json, $summary, NOW())
ON CONFLICT (organization_id, contact_ref) DO UPDATE
SET facts            = $updated_facts_json,   -- application-managed upsert per fact key
    last_call_summary = EXCLUDED.last_call_summary,
    last_call_at     = NOW(),
    updated_at       = NOW();
```

### QP-12: GDPR Erase Customer Memory

```sql
UPDATE memory.customer_memories
SET facts             = '[]',               -- all facts erased
    last_call_summary = NULL,
    last_call_at      = NULL,
    updated_at        = NOW()
WHERE organization_id = organization.current_tenant_id()
  AND contact_ref = $contact_id;
-- session_memories: turns JSONB cleared, summary cleared (async event handler)
-- crm.contacts remains the authoritative row — memory is derived data
```

---

## 18. Concurrency Analysis

### 18.1 Two Workers Advancing the Same Execution

**Problem:** two Celery workers checkpoint the same execution after adjacent turns.

**Solution:** Redis serializes the per-turn state update (`workflow_exec:{session_id}` key with Redis SET NX/WATCH pattern). The Postgres checkpoint is fire-and-forget. The `ACTIVE` status check (`WHERE status = 'ACTIVE'`) in the UPDATE prevents a COMPLETED execution from being clobbered. The checkpoint is idempotent — writing the same state again has no semantic effect.

### 18.2 Duplicate Execution Start

**Problem:** two events trigger `StartExecution` for the same session.

**Solution:** `UNIQUE (session_ref, organization_id) WHERE status = 'ACTIVE'` prevents two active executions for the same session. The second INSERT raises a unique violation; the application catches it and loads the existing execution.

### 18.3 Workflow Published Concurrently

**Problem:** two API requests both publish a workflow simultaneously.

**Solution:** `fn_workflow_publish()` runs an UPDATE that takes a row lock. Only one succeeds; the second sees the already-PUBLISHED state in the precondition and can either succeed (same version — idempotent) or be treated as a new version request.

### 18.4 Duplicate Prompt Version Publish

**Problem:** two requests publish the same prompt draft simultaneously.

**Solution:** `UNIQUE (prompt_template_id, version_number)` prevents duplicate version numbers. The second INSERT raises a unique violation. Application handles idempotently.

### 18.5 Concurrent Customer Memory Update

**Problem:** two post-call summarization tasks update the same customer's facts.

**Solution:** `ON CONFLICT DO UPDATE` is atomic. The application-layer `UpdateFact` applies the confidence-based merge rule before the JSONB write. The UPSERT ensures last-writer-wins at the row level. For a high-frequency contact, this is acceptable — the memory context assembler reads the latest state from the final write.

---

## 19. Workflow Lifecycle

```
DRAFT
  ↓ PublishWorkflow → new WorkflowVersion created; published_version_id set
PUBLISHED
  ↓ UpdateDraftGraph → draft_graph mutates; published_version_id unchanged; live calls unaffected
PUBLISHED (again) ↓ PublishWorkflow → new version; previous version remains for in-flight executions
  ↓ ArchiveWorkflow
ARCHIVED (terminal — cannot be re-published; INV-WF-02)
```

**Version pinning on execution (INV-WF-03):** when `StartExecution` is called, `workflow_version_id` is set and permanently pinned. Even if the workflow is re-published mid-call, the running execution continues on its pinned version. The immutability trigger prevents any change to `workflow_version_id` after creation.

**Rollback:** not a separate operation. The `PublishWorkflow` command takes the current `draft_graph`. To "rollback," a user restores an old `graph_json` into `draft_graph` and re-publishes, creating a new version with the older content.

---

## 20. Prompt Lifecycle

```
DRAFT
  ↓ PublishPromptVersion → new PromptVersion created (immutable); template status → PUBLISHED
PUBLISHED
  ↓ SetActiveVersion(env, version) → active_versions[env] updated
  ↓ RollbackPrompt(env, target) → active_versions[env] = old_version_number
  ↓ ArchivePromptTemplate → status = ARCHIVED
ARCHIVED (terminal)
```

**Multiple environments:** `active_versions` allows different version numbers per environment. A version in `production` = 3 and `staging` = 4 means production uses version 3, staging uses version 4. Both are independently selectable.

**A/B experiments:** `prompt_experiments` overlays the `active_versions` routing. When an active experiment exists for a prompt, the `ExperimentAssignmentService` deterministically routes sessions to variants, bypassing `active_versions` for that prompt. After experiment completion, routing reverts to `active_versions`.

---

## 21. Conversation Memory

### 21.1 Hot Tier vs. Durable Tier

| Store | Contents | TTL | Authority |
|---|---|---|---|
| Redis `session_memory:{session_id}` | Live turn RLIST during call | Call duration + grace | Hot-tier only |
| `memory.session_memories.turns` | Post-call checkpoint JSONB | Permanent | Durable authority |
| `memory.customer_memories.facts` | Cross-call extracted facts | Permanent | Durable authority |

**Why Redis for in-call turns (DDR-4E-005):** `append_turn()` is called after every voice turn — potentially 50 times per call. A Postgres write per turn would add significant pressure at tens of thousands of concurrent calls. Redis absorbs the writes; Postgres receives one batch at call end.

### 21.2 Post-Call Flow

```
call.ended
    ↓ (async Celery)
1. Read Redis session_memory:{session_id} → full turn list
2. Checkpoint to memory.session_memories (turns JSONB, status = 'COMPLETED')
3. Redis key deleted (or TTL expires)
4. SummarizeSession use case: LLM generates summary
5. UPDATE session_memories SET summary = ..., status = 'SUMMARIZED'
6. UpdateCustomerMemory: extract facts, update customer_memories
7. Publish memory.session_summarized → CRM creates AI_SUMMARY Note
```

---

## 22. GDPR / PII

| Column | PII Category | Erasure strategy |
|---|---|---|
| `session_memories.turns` | `pii:voice` | `SET turns = '[]', summary = NULL` |
| `session_memories.summary` | `pii:voice` | Set to NULL |
| `customer_memories.facts` | `pii:potential` | `SET facts = '[]'` |
| `customer_memories.last_call_summary` | `pii:voice` | Set to NULL |
| `workflow_executions.slots` | `pii:potential` | Slots may contain caller name, intent; cleared on GDPR request |
| `workflow_executions.node_execution_history` | `pii:potential` | Same |

**GDPR propagation trigger:** `contact.gdpr_erased` event triggers:
1. `memory.customer_memories`: clear facts and summary for the `contact_ref`
2. `memory.session_memories`: clear `turns` and `summary` for all sessions where `contact_ref` matches
3. `workflow.workflow_executions`: clear `slots` and `node_execution_history` for sessions associated with the contact — this is a best-effort propagation via logical `session_ref` linkage (application locates sessions, then clears execution state)

**Cross-table asynchronous erasure:** PostgreSQL rows across schemas are cleared by an async event handler. The handler is idempotent (a second delivery of the same event finds already-cleared fields).

**No PII in prompt or workflow configuration:** prompt content should not contain real customer data (it is a template). Workflow `graph_json` contains node configuration and expressions, not customer-specific data. These are not erased on contact GDPR requests.

---

## 23. Migration Plan

```
Phase 5F migrations (034–038, 043, 044)
        ↓
NOTE: Phase 5F used migrations 034–038, 043, 044
Phase 5G uses: 039–042, 045–046 (continuing the chain)

039_phase5g_schemas_and_functions
    down_revision = '044_knowledge_grants_finalize'
    purpose: GRANT USAGE on workflow/prompt/memory schemas;
             all trigger functions (§14);
             fn_workflow_publish() SECURITY DEFINER;
             fn_prompt_set_active() SECURITY DEFINER;
             REVOKE ALL FROM PUBLIC + GRANT EXECUTE on both SECURITY DEFINER functions

040_workflow_definitions_and_versions
    down_revision = '039_phase5g_schemas_and_functions'
    purpose: workflow.workflow_definitions, workflow.workflow_versions,
             FK (versions→definitions CASCADE), immutability triggers,
             REVOKE UPDATE DELETE on versions, indexes, RLS, grants

041_workflow_executions_partitioned
    down_revision = '040_workflow_definitions_and_versions'
    purpose: workflow.workflow_executions (partitioned RANGE monthly on started_at),
             DEFAULT safety partition, parametric monthly partitions,
             execution immutability trigger, indexes, RLS, grants

042_prompt_tables
    down_revision = '041_workflow_executions_partitioned'
    purpose: prompt.prompt_templates, prompt.prompt_versions (REVOKE UPDATE DELETE),
             prompt.prompt_experiments,
             FK (versions→templates CASCADE), immutability triggers, indexes, RLS, grants

045_memory_tables
    down_revision = '042_prompt_tables'
    purpose: memory.session_memories (UNIQUE on session_ref),
             memory.customer_memories (UNIQUE on org+contact_ref),
             session turns immutability trigger, indexes, RLS, grants

046_phase5g_grants_finalize
    down_revision = '045_memory_tables'
    purpose: app_readonly grants; app_platform_admin full access
```

**Downgrade order:** 046 → 045 → 042 → 041 → 040 → 039

---

## 24. Seed Data

No platform-owned seed data is required for Phase 5G. Workflow definitions, prompt templates, and memory records are tenant-created. System prompts are configured via the platform admin API (prompt templates created per organization at onboarding), not as migration seed data.

---

## 25. ADRs

### ADR-5G-001: Workflow Graph as Embedded JSONB

**Decision:** `draft_graph` and `graph_json` (published snapshot) are JSONB columns on `workflow_definitions` and `workflow_versions` respectively. No separate `workflow_nodes` or `workflow_edges` tables are created.

**Rationale:** Phase 4E §5.1 explicit DDD decision: "The full graph is embedded (not split across tables) because (a) it is always read and written as a whole unit at publish time, and (b) even large workflows rarely exceed a few hundred nodes." Nodes and edges are embedded entities with no independent lifecycle. Querying a specific node requires loading the whole graph — a separate table provides no query benefit.

**Alternative rejected:** relational `workflow_nodes` and `workflow_edges` tables. Rejected because: (1) not authorized by the DDD, (2) graph publishing (which needs the whole graph for validation) would require a join across all nodes and edges, (3) graph edits (add/remove node + update connected edges) would require multi-row transactions, adding lock contention.

### ADR-5G-002: Workflow Execution Persisted with Embedded NodeHistory

**Decision:** `workflow_executions` embeds `node_execution_history`, `slots`, and `turn_count_at_node` as JSONB. Redis carries the hot-tier during active calls. PostgreSQL receives a per-turn checkpoint asynchronously.

**Rationale:** Phase 4E §5.2 and §18. Execution state updates occur after every voice turn — a synchronous Postgres write per turn would be in the LLM/STT/TTS response path. Redis absorbs the hot-tier state; Postgres checkpoints keep recovery possible after a crash.

### ADR-5G-003: Separate WorkflowVersion Table (Not Embedded in Definition)

**Decision:** `workflow_versions` is a separate table rather than embedded JSONB on `workflow_definitions`.

**Rationale:** `workflow_version_id` is independently queryable — used as the pinned reference on `workflow_executions`. If versions were embedded in the definition's JSONB, every execution load would require fetching the whole definition and deserializing all versions to find the pinned one. A separate table allows direct PK lookup of a specific version.

**Why not the same reasoning applies to WorkflowNode:** Nodes are never independently queried by NodeId from outside the aggregate. The cursor (`current_node_id`) is just a UUID stored on the execution; the node's data is read from the `graph_json` at execution time. No SQL query ever says `SELECT * FROM workflow_nodes WHERE id = $current_node_id`.

### ADR-5G-004: Prompt Active Versions as JSONB

**Decision:** `prompt_templates.active_versions` is a `JSONB` dict of `{environment: version_number}`.

**Rationale:** `ActiveVersionByEnvironment` has exactly 3 environment keys (`local | staging | production`). Always read whole with the template. Mutated atomically via `fn_prompt_set_active()`. JSONB is appropriate for this bounded dict per Phase 5A §4.1.

### ADR-5G-005: Session Memory Turns in Redis During Call, Checkpointed to Postgres

**Decision:** during a call, turns are appended to Redis only (`append_turn()` is fire-and-forget per DDR-4E-005). After call end, the full turn list is checkpointed to `memory.session_memories.turns JSONB`.

**Rationale:** per Phase 4E DDR-4E-005: writing to Postgres after every turn would add ~50 writes/call to the per-turn hot path at platform scale. Maximum data loss on Redis failure: 1 in-flight turn.

### ADR-5G-006: CustomerMemory Facts as Embedded JSONB

**Decision:** `customer_memories.facts` is a `JSONB` array bounded at ~100 facts per contact.

**Rationale:** Phase 4E §8.1 defines Facts as a list always read whole for context assembly. No use case queries a specific fact by key without loading the CustomerMemory. A separate `customer_memory_facts` table would add a join to every memory load with no benefit.

### ADR-5G-007: Workflow Executions Partitioned RANGE Monthly

**Decision:** `workflow_executions` is partitioned RANGE monthly on `started_at`. PK includes partition key: `(id, started_at)`.

**Rationale:** one execution per call session. At millions of calls/day, this table grows unboundedly. Same partitioning rationale and strategy as Phase 5C `call_sessions` and Phase 5F `workflow_executions`.

### ADR-5G-008: SECURITY DEFINER for Workflow Publication and Prompt Active Version

**Decision:** `fn_workflow_publish()` and `fn_prompt_set_active()` are SECURITY DEFINER functions. Application roles cannot directly UPDATE `published_version_id` on `workflow_definitions` or `active_versions` on `prompt_templates`.

**Rationale:** consistent with Phase 5F `fn_docver_publish()` pattern. Both functions enforce ownership invariants (version belongs to the correct parent entity and tenant) before applying the update. Direct UPDATE access would allow arbitrary publication bypassing these invariants.

### ADR-5G-009: Memory GDPR Erasure — Best-Effort Asynchronous

**Decision:** GDPR erasure of memory is triggered by the `contact.gdpr_erased` CRM event and processed asynchronously. The handler clears `session_memories.turns/summary` and `customer_memories.facts/last_call_summary` for the affected contact. Cross-schema linkage uses the logical `contact_ref` UUID. Workflow execution slot clearance is best-effort via session_ref linkage.

**Rationale:** memory tables span multiple schemas. A synchronous single-transaction erasure across schemas would require distributed locking. The async event-handler approach is consistent with the platform's event-driven architecture. GDPR erasure does not need to be real-time; reasonable completion SLA (24h) is sufficient.

### ADR-5G-010: No Prompt Version Pinning in WorkflowExecution

**OPEN DESIGN DECISION:** Phase 4E §5.1.4 shows Workflow nodes reference `prompt_ref: PromptId` (not `PromptVersionId`). The active version for the environment is resolved at execution time from `active_versions`. This means if the active version changes mid-call, subsequent LLM nodes might use a different prompt version than the call started with.

**Mitigating factor:** the Workflow Version's `graph_json` is pinned and immutable. The `prompt_ref` (PromptId, not PromptVersionId) in the node config is part of the pinned graph. The resolved version may vary if `SetActiveVersion` is called mid-call. Phase 4E §14.3 shows the render path uses `active_versions` at render time — this design is consistent with the authoritative DDD.

**Consequence:** deterministic replay of an exact call requires the `active_versions` state at the time of the call. This is an analytics/audit concern, not a runtime correctness concern (the agent experiences the latest approved prompt version in the configured environment). Documented as a carry-forward item for Phase 9.

---

## 26. Security Matrix

| Scenario | Mechanism | Expected Result |
|---|---|---|
| Tenant A reads Tenant B's workflows | RLS | 0 rows |
| Tenant A reads Tenant B's executions | RLS | 0 rows |
| Tenant A reads Tenant B's session memory | RLS | 0 rows |
| Tenant A reads Tenant B's customer memory | RLS | 0 rows |
| Tenant A publishes Tenant B's workflow | `fn_workflow_publish()`: `organization_id` check | RAISE EXCEPTION |
| Version from Workflow B published on Workflow A | `fn_workflow_publish()`: `workflow_definition_id` check | RAISE EXCEPTION |
| Published workflow version mutated | Immutability trigger | RAISE EXCEPTION |
| Published prompt version mutated | Immutability trigger | RAISE EXCEPTION |
| Execution workflow_version_id changed | Immutability trigger | RAISE EXCEPTION |
| COMPLETED execution mutated | Immutability trigger | RAISE EXCEPTION |
| Completed session memory turns changed | Immutability trigger | RAISE EXCEPTION |
| Secret stored in prompt content | No secret columns; content validated by PromptValidationService | Application-layer rejection |
| Prompt injection via workflow expression | Expression whitelist validated at publish + runtime | Rejected at publish (DECISION node) |
| Cross-tenant memory access | RLS | 0 rows |
| Missing tenant context | `current_tenant_id() = NULL` | 0 rows all tables |
| Memory poisoning | CustomerMemory updated only by authorized post-call event handlers | Application-layer control |

---

## 27. Test Matrix

### Tenant Isolation

```text
Tenant A reads Tenant B workflow → 0 rows
Tenant A reads Tenant B execution → 0 rows
Tenant A reads Tenant B session memory → 0 rows
Tenant A reads Tenant B customer memory → 0 rows
Tenant A publishes Tenant B workflow → EXCEPTION (fn_workflow_publish)
Version from wrong workflow published → EXCEPTION (fn_workflow_publish ownership check)
```

### Version Integrity

```text
Published workflow version graph_json UPDATE → trigger RAISE EXCEPTION
Published prompt version content UPDATE → trigger RAISE EXCEPTION
Published prompt version variable_schema UPDATE → trigger RAISE EXCEPTION
Execution workflow_version_id UPDATE → trigger RAISE EXCEPTION
COMPLETED execution state UPDATE → trigger RAISE EXCEPTION (INV-WF-04)
COMPLETED session memory turns UPDATE → trigger RAISE EXCEPTION (INV-MEM-02)
ARCHIVED workflow → PublishWorkflow → fn_workflow_publish EXCEPTION (INV-WF-02)
```

### Concurrency

```text
Two workers start execution for same session → unique violation; second finds existing ACTIVE
Two workers checkpoint same execution → last-writer-wins on JSONB (Redis serializes hot path)
Duplicate workflow publish event → version_number UNIQUE violation; idempotent
Duplicate prompt publish event → version_number UNIQUE violation; idempotent
```

### Memory

```text
Session memory isolation: Tenant A cannot read Tenant B's session memory
Customer memory isolation: Tenant A cannot read Tenant B's customer memory
Memory erasure: facts cleared on GDPR request; row retained as tombstone
Summary erasure: last_call_summary set to NULL on GDPR request
Turns erasure: turns JSONB set to '[]' for completed sessions on GDPR request
```

### GDPR

```text
contact.gdpr_erased → customer_memories.facts = '[]' ✓
contact.gdpr_erased → session_memories with contact_ref cleared ✓
contact.gdpr_erased → workflow_executions slots cleared (best-effort) ✓
Second delivery of gdpr_erased event → idempotent (already-empty fields) ✓
```

---

## 28. Carry-Forward Items

| Item | Description | Target Phase |
|---|---|---|
| **Prompt version pinning in executions** | ADR-5G-010: resolve whether `graph_json` should store `prompt_version_id` instead of `prompt_id` for deterministic replay. | Phase 9 |
| **`workflow_executions` partition automation** | `create_monthly_partitions()` helper must be unit-tested; maintenance job for 12-month rolling window. | Phase 22 |
| **Execution `started_at` in all lookups** | Application must always provide `started_at` to enable partition pruning on `workflow_executions`. Document in `WorkflowExecutionRepository`. | Phase 9 |
| **Session memory `turns` JSONB size** | At 100 turns × ~200 chars/turn, a session memory row is ~20KB — acceptable. Monitor for long calls. | Phase 22 |
| **CustomerMemory fact conflict resolution** | Phase 4E §8.1 inv.3 (confidence-based fact replacement) is application-layer logic; document in `MemoryApplicationService`. | Phase 9 |
| **A/B experiment analytics** | `prompt_experiments` stores configuration only; analytics (assignment counts, conversion rates) go to Phase 5H analytics schema. | Phase 5H |
| **Workflow trigger model** | Phase 4E does not define a `WorkflowTrigger` aggregate — workflow execution is started by `StartExecution` command from the Voice Orchestrator. If campaign-triggered workflows are required (OQ-4D-03), a trigger entity may be needed. | Future phase |
| **Memory compression** | `compression_level = 'COMPRESSED'` is modelled but the compression algorithm is not defined. | Phase 9 |

---

## 29. Final Consistency Review

### Phase 5A ✅
UUIDv7 PKs; no cross-schema FKs to voice/crm/campaign/knowledge; TEXT+CHECK for all status columns; no monetary columns in 5G; JSONB justified for all columns; PII tagged; `workflow_executions` partitioned RANGE monthly with partition key in PK; immutability via triggers (not broad privilege revocation for mutable tables); migration chain continues from 5F.

### Phase 5B ✅
`organization.current_tenant_id()`, `gen_uuid_v7()`, `set_updated_at()` throughout. ENABLE + FORCE ROW LEVEL SECURITY on all 8 tables. SECURITY DEFINER functions: REVOKE ALL FROM PUBLIC + GRANT EXECUTE.

### Phase 5C ✅
Voice remains authoritative for calls, conversations, agents. `session_ref` and `conversation_ref` in `session_memories` are logical UUID references (no FK). `workflow_executions.session_ref` is logical (no FK). Agent version references KB IDs and workflow IDs via `snapshot_json` — Phase 5G does not own agents.

### Phase 5D ✅
CRM remains authoritative for contacts. `contact_ref` in `session_memories` and `customer_memories` are logical references. No contact PII duplicated in memory tables (only extracted facts and summaries keyed by `contact_ref`).

### Phase 5E ✅
Campaign remains authoritative for campaigns and call jobs. No campaign tables or data in Phase 5G.

### Phase 5F ✅
Knowledge remains authoritative for knowledge_bases, documents, chunks. `KNOWLEDGE_SEARCH` workflow node type references KB IDs (stored inside `graph_json` JSONB); no FK to `knowledge.knowledge_bases`. Phase 5G does not own any knowledge data.

### Phase 4E DDD ✅
All six Phase 4E aggregates in the three bounded contexts are mapped:
- Workflow: `WorkflowDefinition` → `workflow_definitions`, `WorkflowVersion` → `workflow_versions`, `WorkflowExecution` → `workflow_executions`
- Prompt: `PromptTemplate` → `prompt_templates`, `PromptVersion` → `prompt_versions`, `PromptExperiment` → `prompt_experiments`
- Memory: `SessionMemory` → `session_memories`, `CustomerMemory` → `customer_memories`

No tables are added that are not in the DDD. No DDD aggregate is omitted.

---

```
PHASE 5G STATUS

Workflow schema:
APPROVED

Workflow lifecycle:
APPROVED

Prompt Management schema:
APPROVED

Prompt lifecycle:
APPROVED

Conversation Memory schema:
APPROVED

Memory lifecycle:
APPROVED

JSONB usage:
APPROVED (all 11 JSONB columns justified against Phase 5A rules and Phase 4E DDD)

Partitioning:
APPROVED (workflow_executions RANGE monthly; no other table requires V1 partitioning)

Immutability:
APPROVED (triggers on workflow_versions, prompt_versions, executions, session memory turns;
          REVOKE UPDATE on workflow_versions and prompt_versions; SECURITY DEFINER for lifecycle)

RLS:
APPROVED (all 8 tables with ENABLE + FORCE; organization.current_tenant_id())

RBAC:
APPROVED (Phase 5B permission system; no new permissions in schema)

Security:
APPROVED

GDPR / PII:
APPROVED (PII tagged; erasure propagation documented; async handler pattern)

DDL:
APPROVED

Indexes:
APPROVED

Migration Plan:
APPROVED (039–042, 045–046; continues from 5F chain)

Open Design Decision:
ADR-5G-010 — Prompt version pinning in workflow execution (not blocking V1 runtime;
documented as carry-forward for Phase 9)

Overall:
PHASE 5H READY
```

All Phase 4E Knowledge & RAG, Workflow, Prompt Management, and Conversation Memory bounded contexts are now fully designed. ADR-5G-010 is the only open design decision — it does not block V1 runtime correctness and is documented as Phase 9 carry-forward. Eight ADRs close all significant architectural decisions. Phase 5H will design the Billing / Usage schema.

---

## 30. Controlled Reconciliation Amendment — Phase 6I Blocker Remediation (2026-08-29)

**This section is an additive amendment, not a rewrite.** Nothing above this line is edited — the eight ADRs, the DDL, and the "PHASE 5H READY" status block all remain exactly as originally approved and describe the schema as it stood through migration `099_5C1`.

`docs/phase-06-api-design/6I-Workflow-APIs.md`'s own Phase 6I Blocker Remediation pass found four genuine gaps in this document's physical design that no prior phase (5G itself, 5K, 5K.1, or 5L) had identified: (1) no durable per-attempt idempotency claim existed for side-effecting Workflow nodes (`TOOL_CALL`/`TRANSFER`/`HUMAN_TRANSFER`); (2) the per-turn checkpoint `UPDATE` (§17.6/QP-06) had no defense against an older Turn's checkpoint committing after a newer one; (3) `app_platform_admin` retained an unqualified `UPDATE`/`DELETE` grant on `workflow_definitions`/`workflow_versions`/`workflow_executions` and `prompt.prompt_versions` sufficient to bypass `fn_workflow_publish()`'s own ownership guard and this document's own immutability triggers; (4) the immutability triggers on `workflow_versions`/`prompt_versions` (§14.1/§14.3) guarded content/version-number/publish-metadata fields but never their own identity columns (`workflow_definition_id`/`prompt_template_id`, `organization_id`) — the exact class of hardening this document's own `workflow_executions` trigger (§14.2, `prevent_execution_mutation()`) already received via the 5K correction pass, never applied symmetrically here.

**Migration:** `5K/migrations/100_5G1.sql`, Alembic revision `100_5G1`, `down_revision = '099_5C1'` — additive only, no row 001-099 touched. Adds `workflow.node_execution_claims` (a durable `CLAIMED → SUBMITTING → SUCCEEDED|FAILED|AMBIGUOUS` state machine, five guarded `SECURITY DEFINER` functions) and `workflow.workflow_executions.checkpoint_seq BIGINT` (a monotonic per-execution Turn counter, CAS-guarded by a new `fn_checkpoint_workflow_execution()` and, as a second, unconditional layer, by a hardened `prevent_execution_mutation()`); revises `fn_start_workflow_execution()` to return a deterministic outcome instead of raising on a benign duplicate-active-session race, and to reject starting against an `ARCHIVED` `WorkflowDefinition`; reduces `app_platform_admin` to `SELECT`-only on the four affected tables; hardens `prevent_wf_version_mutation()`/`prevent_pv_mutation()`'s identity-column coverage; and adds a new `prevent_archived_definition_mutation()` trigger making `ARCHIVED` unconditionally terminal on `workflow_definitions`.

**Live-validated** on genuine PostgreSQL 16.10 (fresh `001→100` and incremental `099→100`, both exit 0, single head), including genuine multi-connection concurrency races for every one of the four defects — see `5K/MIGRATION_MANIFEST.md`'s "Phase 6I Blocker Remediation (2026-08-29)" entry and `6I-Workflow-APIs.md` §63 for the complete record and raw evidence file list. This amendment does not change this document's approved schema philosophy (JSONB-embedded graph, Redis-hot/Postgres-checkpoint execution state, `SECURITY DEFINER`-guarded lifecycle transitions) — it closes four gaps in how faithfully the original design's own stated invariants were actually enforced.

**Extended twice more, same day, same file (`100_5G1.sql` amended in place a second and third time — never applied to production, per the migration's own stated policy):**

*Second pass* (`6I-Workflow-APIs.md` §64) closed three further gaps its own first pass' new capabilities had introduced: `app_api`/`app_worker` still held raw `INSERT` on `workflow_versions` and unrestricted `UPDATE` on `workflow_definitions`, sufficient to bypass guarded publishing entirely (closed: `INSERT` revoked, `UPDATE` re-granted only on `name`/`description`/`draft_graph`, the original `fn_workflow_publish()` dropped and replaced by one guarded `fn_publish_workflow()`, with a companion `fn_archive_workflow()`); `fn_start_workflow_execution()`'s `ARCHIVED` check was an unlocked read with no real serialization point against `ArchiveWorkflow` (closed: `FOR SHARE OF wd`); and four of the five side-effect functions never validated their caller-supplied tenant argument at all, while the fifth never validated its caller-supplied execution/checkpoint/node identity against reality (both closed).

*Third pass* (`6I-Workflow-APIs.md` §65) closed two further gaps in the second pass' own new capabilities:

- **Side-effect failure rule**, now the final, binding shape: `CLAIMED → FAILED` is allowed for a definite pre-submission failure (the side effect was never attempted) and remains safely reclaimable; `SUBMITTING → FAILED` is forbidden for any ordinary runtime worker (it previously was permitted, letting an uncertain or already-successful post-submission outcome be turned into an automatically-retryable state — the defect this pass closes); `SUBMITTING → AMBIGUOUS` remains required and allowed for any uncertain post-submission outcome; `SUBMITTING → SUCCEEDED` remains allowed on a definite, known success. There is no ordinary-worker path from `SUBMITTING` to a reclaimable state at all, in any of the three passes' final state.
- **Publish rule**, now the final, binding shape: the exact-draft concurrency precondition (`fn_publish_workflow()`'s `p_expected_updated_at`) is **mandatory** — no default, and an explicit `NULL` guard inside the function body. No `NULL`-bypass route exists; every runtime publication must supply the row's real current `updated_at` or the call is rejected outright.

Both extensions live-validated identically (fresh/incremental PostgreSQL 16, full regression, zero defects reintroduced) — see `5K/MIGRATION_MANIFEST.md`'s "Phase 6I FINAL Blocker Remediation" and "Phase 6I FINAL MICRO-REMEDIATION" entries and `6I-Workflow-APIs.md` §64/§65 for the complete record. One non-blocking product-policy question (whether `app_platform_admin` should retain its frozen, `041_5G.sql`-era `EXECUTE` grant on `fn_start_workflow_execution`) was reviewed and left open for the product owner — the function's own safety does not depend on which roles may call it, so this is not a schema or security gap.
