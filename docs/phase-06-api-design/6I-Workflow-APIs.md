# 6I — Workflow APIs

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6I

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6I-Workflow-APIs.md |
| Phase | 6I (ninth document of Phase 6 — API Design) |
| Depends on (frozen, unmodified) | Phase 1 SRS; Phase 2 HLA; Phase 3D LLD (primary), 3A/3B/3E (secondary); Phase 4E DDD (primary, authoritative domain design), 4A/4B/4G/4H/4I (secondary); Phase 5G DB Design (primary — `workflow`/`prompt`/`memory` schemas), 5A/5B/5J (secondary); Phase 5K migrations `001_5B.sql`…`099_5C1.sql` (executed SQL, authoritative over 5G prose wherever the two differ); Phase 5L Global Database Reconciliation; Phase 6A (binding standards), 6B (auth/API-key model), 6D (Voice call-control boundary, Directive consumption), 6E (Agent/AgentVersion boundary, `workflow_ref`), 6F (Knowledge/RAG in-process port pattern), 6H (Campaign ACL statement) |
| Modifies | **Nothing.** No Phase 5 schema, migration, function, trigger, RLS policy, grant, or index is changed by this document. Two genuine, disclosed production-safety gaps are found (§37, §38) and documented as controlled findings with a minimum-remediation sketch — neither is implemented here. |
| Author scope | Workflow management/read APIs (`WorkflowDefinition`, `WorkflowVersion`), Workflow execution debug/read APIs, and the in-process Voice↔Workflow runtime contract. No Agent CRUD (6E), no Call/audio/provider control (6D), no Knowledge Base/RAG CRUD (6F), no CRM CRUD (6G), no Campaign CRUD/execution (6H), no Prompt Management public API, no Conversation Memory public API, no Integrations/Webhooks/Plugins configuration (6J), no Billing (6K), no Analytics (6L), no Platform Admin (6M). |
| Supersedes | Nothing (6I is a new document) |
| Governs | Nothing downstream directly, but 6J (Integrations/Webhooks) must consume the WEBHOOK/API_CALL node classification fixed here (§23) without redesigning it, and any future Phase that resolves ADR-5G-010 (prompt-version pinning) must reconcile against §27's carry-forward. |
| Date | 2026-08-29 |

---

## 2. Purpose and Scope

This document designs the public, tenant-facing REST API for managing `WorkflowDefinition` (draft/publish/archive lifecycle) and reading `WorkflowVersion`/`WorkflowExecution` state, plus the **in-process** application-service contract the Voice Orchestrator uses to execute a published Workflow during a live call.

**In scope:** Workflow CRUD/lifecycle endpoints, draft-graph editing, structural+semantic validation, publish/archive, version listing, execution debug/list reads, the Voice→Workflow in-process runtime boundary, the Agent→Workflow and Campaign→Workflow boundaries (consumed, not redesigned), node-type config schemas and their cross-context reference classification, expression-safety API contract, realtime execution-progress channel, error catalogue, authorization matrix, and a full adversarial concurrency/security review of the actually-executed Phase 5 SQL.

**Out of scope (owned elsewhere, never redesigned here):** Agent CRUD/publish (6E), Call lifecycle/audio/transfer execution (6D), Knowledge Base/Document CRUD and retrieval internals (6F), CRM CRUD (6G), Campaign CRUD/execution (6H), Prompt Management CRUD (unassigned phase — 4E/5G own the domain, no Phase 6 document yet owns its public API), Conversation Memory public API (unassigned phase), Integration/Webhook/Plugin configuration and credential storage (6J), Billing (6K), Analytics (6L), Platform Admin (6M).

Every capability below is checked against 4E's command/query catalogue and 5G's *executed* migrations before being called `IMPLEMENTATION-READY`. Where no such backing exists, it is marked `DEFERRED`, `EXECUTION-BLOCKED`, or `BLOCKER` per §54.

---

## 3. Source Reconciliation — Executed SQL Wins Over Stale Prose

Three material discrepancies were found between 5G's prose/DDL narrative and the actually-executed migrations (039–046, 076, cross-checked against 099 for pattern precedent). Per this task's governing rule, the executed SQL is authoritative in all three cases:

| # | 5G prose said | Executed migration actually does | Authority |
|---|---|---|---|
| 1 | `uq_we_active_session`: `UNIQUE (session_ref, organization_id) WHERE status='ACTIVE'` on `workflow_executions` | **Invalid on a partitioned table** (a unique index on a partitioned table must include the partition key). `041_5G.sql` replaces it with a **non-unique** `idx_we_active_session` and moves the one-ACTIVE-per-session invariant into `workflow.fn_start_workflow_execution()`, enforced via `pg_advisory_xact_lock` + a guarded `SELECT`-then-`INSERT` (§17). | `041_5G.sql` (executed) |
| 2 | All app roles including `app_platform_admin` may `INSERT`/`UPDATE`/`DELETE` on `workflow_executions` (5G §13) | `041_5G.sql` **REVOKEs INSERT from `app_api`, `app_worker`, AND `app_platform_admin`** — the sole INSERT path is `fn_start_workflow_execution()`. `046_5G.sql`'s later blanket `GRANT ... ALL TABLES IN SCHEMA workflow TO app_platform_admin` silently **re-granted** INSERT to `app_platform_admin`, which `076_5K1.sql` **re-revokes** narrowly (parent table + every existing partition), restoring 041's original intent for `app_platform_admin` specifically. | `041_5G.sql`, `076_5K1.sql` (executed) |
| 3 | Two-step publish (`INSERT workflow_versions` then `SELECT fn_workflow_publish(...)`) is shown as two SQL statements with no explicit transaction wrapper in 5G §16/§17 | 6A §35 (frozen, binding) explicitly lists **"Publish Workflow + WorkflowVersion"** in its named "approved exceptions requiring true same-transaction atomicity" list. This is a Phase 6A architectural mandate, not a 5G artifact — 6I inherits it as a hard requirement on the application-service implementation (§36). | `6A-API-Architecture-and-Standards.md` §35 (frozen) |

No other discrepancy was found between 5G's prose and 039–046/076. `fn_workflow_publish()` and `fn_prompt_set_active()` match their documented bodies verbatim.

---

## 4. Domain Model Recap (Authoritative, Not Redesigned)

### 4.1 Aggregates

```text
WorkflowDefinition   — workflow.workflow_definitions   — mutable draft_graph, status, published_version_id
WorkflowVersion      — workflow.workflow_versions      — immutable graph_json snapshot, child of WorkflowDefinition
WorkflowExecution    — workflow.workflow_executions    — partitioned (RANGE monthly on started_at), per-call runtime state
```

### 4.2 Lifecycle (verbatim from 4E §7.2 / 5G §19 — unmodified)

```text
DRAFT
  ↓ PublishWorkflow                          [graph validates; new WorkflowVersion created; published_version_id set]
PUBLISHED
  ↓ UpdateDraftGraph                         [draft_graph mutates; published_version_id UNCHANGED; live calls unaffected]
PUBLISHED (still)
  ↓ PublishWorkflow (again)                  [new WorkflowVersion created; previous version remains for in-flight executions]
PUBLISHED
  ↓ ArchiveWorkflow
ARCHIVED                                     [terminal — immutable, cannot publish again — INV-WF-02]
```

A live `WorkflowExecution` pins `workflow_version_id` at `StartExecution` and never changes it (INV-WF-03, DB-trigger-enforced) — republishing mid-call never affects an in-flight call.

### 4.3 Node Type Vocabulary — 3D vs. 4E Reconciled

3D §5.2 (`GreetingNode` … `EndCallNode`, 14 classes) and 4E §5.1.3 (`GREETING | PROMPT | LLM | DECISION | CONDITION | BRANCH | KNOWLEDGE_SEARCH | TOOL_CALL | WEBHOOK | API_CALL | DELAY | TRANSFER | HUMAN_TRANSFER | END_CALL`, 14 values) are **identical in membership** — 3D's PascalCase class names map 1:1 onto 4E's `NodeType` enum values. No renaming or collapsing is needed; 4E's UPPER_SNAKE_CASE spelling is used as the wire-format value throughout this document (it is what `draft_graph`/`graph_json` actually store).

### 4.4 Directive Vocabulary — 3D vs. 4E Reconciled (Decision)

3D §12 (`DirectiveKind`) lists seven values: `SPEAK | EXECUTE_TOOL | TRANSFER | TRANSFER_TO_HUMAN | DELAY | END_CALL | CONTINUE`. 4E §9 (`Directive`, the later, authoritative DDD Value Object) lists six: `SPEAK | EXECUTE_TOOL | TRANSFER | END_CALL | WAIT | CONTINUE`.

**Decision (ADR-6I-01):** 4E's six-value `Directive` enum governs, per this project's standing rule that Phase 4 DDD is the authoritative domain design and Phase 3 LLD is reconciled against it, not the reverse. The two 3D values it does not carry forward are folded into 4E's shape via a payload discriminator, not lost:

- 3D's `TRANSFER` (phone number) and `TRANSFER_TO_HUMAN` (queue) both map to 4E's single `TRANSFER` directive, discriminated by `payload.target_type: PHONE_NUMBER | HUMAN_QUEUE`. This preserves the `TRANSFER` vs. `HUMAN_TRANSFER` **node type** distinction (4E §5.1.3 keeps both node types) while using 4E's smaller, authoritative directive vocabulary at the Voice-consumption boundary.
- 3D's `DELAY(ms)` directive maps to 4E's `WAIT` directive, with `payload.duration_ms` carrying the delay (§25).

This mapping is binding for the Voice→Workflow runtime contract (§18) and is not a new invention — it is the minimum reconciliation needed to make 4E's Directive enum expressive enough for 3D's own node catalogue, which 4E never disputes.

---

## 5. Permission Model — Frozen 5B Catalogue Only

5B §17/§30 seeds exactly three Workflow permissions; this document invents none of the forbidden `workflow:execute`/`workflow:admin`/`workflow:delete`/`workflow:test`:

| Permission | OWNER | ADMIN | MEMBER | VIEWER | Grants |
|---|:---:|:---:|:---:|:---:|---|
| `workflow:read` | ✅ | ✅ | ✅ | ✅ | List/get workflows, list/get versions, list/get execution debug reads |
| `workflow:write` | ✅ | ✅ | ✅ | — | Create workflow, update metadata, replace draft graph, validate draft, archive (ADR-6I-02, §8.3) |
| `workflow:publish` | ✅ | ✅ | — | — | Publish a new `WorkflowVersion` |

(`BILLING_ADMIN` has no Workflow permissions at all — omitted above, matches 5B's full matrix.)

**ADR-6I-02 (classification of Archive):** `ArchiveWorkflow` is classified under `workflow:write`, not a new permission. Rationale: unlike `PublishWorkflow` (which creates a new immutable, execution-pinnable artifact — the reason `workflow:publish` exists as its own gate, per 5B), `ArchiveWorkflow` only flips `status` on the definition itself — a definition-level lifecycle mutation of the same *kind* as `UpdateDraftGraph`, which is already `workflow:write`. A MEMBER who can build and edit a Workflow can also retire one they no longer want live; only publishing a version that live calls will actually run is gated behind the stronger `workflow:publish` permission. This is a judgment call, recorded as an ADR per the governing task's instruction rather than inventing `workflow:delete`/`workflow:admin`.

---

## 6. Public API Surface

### 6.1 Resource Model

```text
POST    /api/v1/workflows                                  workflow:write
GET     /api/v1/workflows                                  workflow:read
GET     /api/v1/workflows/{workflow_id}                    workflow:read
PATCH   /api/v1/workflows/{workflow_id}                    workflow:write   (name/description only)
PUT     /api/v1/workflows/{workflow_id}/draft               workflow:write   (full draft_graph replace)
POST    /api/v1/workflows/{workflow_id}/validate            workflow:write
POST    /api/v1/workflows/{workflow_id}/publish             workflow:publish
POST    /api/v1/workflows/{workflow_id}/archive             workflow:write

GET     /api/v1/workflows/{workflow_id}/versions            workflow:read
GET     /api/v1/workflows/{workflow_id}/versions/{version_id}  workflow:read

GET     /api/v1/workflow-executions                         workflow:read
GET     /api/v1/workflow-executions/{execution_id}          workflow:read

WS      /ws/v1/workflow-executions/{execution_id}            workflow:read   (realtime progress, §39)
```

**Explicitly rejected / not exposed as tenant REST (§9):**

```text
POST /workflow-executions              — StartExecution is Voice-Orchestrator-internal only (§18)
POST /workflow-executions/{id}/advance — AdvanceCursor is runtime-internal only
PATCH /workflow-executions/{id}/slots  — UpdateSlots is runtime-internal only
POST /workflow-executions/{id}/complete|fail — internal only
POST /workflows/{id}/trigger           — no WorkflowTrigger aggregate exists (§55)
DELETE on any Workflow/Version/Execution resource — no destructive delete command exists anywhere in 4E/5G
```

### 6.2 Granular Node/Edge Endpoints — Rejected

Per ADR-5G-001 (`draft_graph` is one JSONB unit, embedded entities, no separate node/edge tables), 6I does **not** expose `POST /workflows/{id}/nodes`, `PATCH /workflows/{id}/nodes/{node_id}`, `POST /workflows/{id}/edges`, etc. A relational-looking per-node API over a JSONB-embedded aggregate would force the API layer to reimplement whole-graph read-modify-write semantics anyway (every node mutation still requires loading, mutating, and rewriting the entire `draft_graph` column) while inventing granular optimistic-concurrency and partial-validation problems the DB was explicitly designed not to have (ADR-5G-001's own rejected-alternative reasoning). `PUT /workflows/{id}/draft` (§8) is the single coherent model.

### 6.3 Delete Semantics

Per 6A §7.6: `workflow_definitions`/`workflow_versions`/`workflow_executions` are all **terminal-status resources**, not soft-delete resources. No `DELETE` verb is exposed on any of the three. `ArchiveWorkflow` is the terminal-state action for definitions; `WorkflowVersion` and `WorkflowExecution` have no delete command in 4E at all (§54, §15).

---

## 7. Voice→Workflow Runtime Contract — Internal, Not REST

4E §5.2/§14.2 and 3D §6 name the commands `StartExecution`, `AdvanceCursor`, `UpdateSlots`, `CompleteExecution`, `FailExecution`. These are **in-process application-service methods** consumed by the Voice Orchestrator (implementing 4B's `WorkflowExecutionPort`), never public REST actions. Exposing them as `POST /workflow-executions/{id}/advance` would let a tenant-facing client directly drive a call's conversational cursor and slot state — turning the platform's own call-control engine into a client-controlled input surface, which no frozen source (4E, 5G, 6D) authorizes and which breaks the "no distributed transactions, no client-controlled hot-path state" invariant this project holds everywhere else (Voice's own call-control actions in 6D are similarly narrow and never expose raw state mutation).

### 7.1 `WorkflowRuntimeService` (in-process; implements 4B's `WorkflowExecutionPort`)

```python
class WorkflowRuntimeService(Protocol):
    async def resolve_published_workflow_version(
        self, workflow_definition_id: WorkflowId, tenant_id: TenantId,
    ) -> WorkflowVersionRef:
        """§19 — resolves the CURRENT published_version_id for a WorkflowDefinition.
        Raises WORKFLOW_NOT_FOUND / WORKFLOW_ARCHIVED / WORKFLOW_NEVER_PUBLISHED.
        Called once, before StartExecution — never re-resolved mid-call."""

    async def start_workflow_execution(
        self, workflow_version_id: WorkflowVersionId, session_ref: SessionId, tenant_id: TenantId,
    ) -> ExecutionId:
        """Wraps workflow.fn_start_workflow_execution() (§17). Pins workflow_version_id
        for the life of the execution (INV-WF-03)."""

    async def evaluate_next_directive(
        self, session_id: SessionId, latest_utterance: str,
    ) -> WorkflowDirective:
        """The per-turn hot-path entry point (4E §14.2, 3D §6.4). Loads Redis hot-tier
        state, evaluates the current node against the PINNED WorkflowVersion.graph_json,
        advances the cursor, returns a Directive. Never re-resolves workflow_version_id."""

    async def checkpoint_workflow_execution(self, execution_id: ExecutionId) -> None:
        """Async — DDR-4E-002: once per completed Turn, never per internal node-step,
        never on the LLM/STT/TTS response path (§28)."""

    async def complete_workflow_execution(self, execution_id: ExecutionId) -> None: ...
    async def fail_workflow_execution(self, execution_id: ExecutionId, reason: str) -> None: ...

    async def get_workflow_execution(
        self, execution_id: ExecutionId, tenant_id: TenantId,
    ) -> WorkflowExecutionDetailDTO:
        """Public face of both the REST debug endpoint (§32) and any future
        in-process consumer — one implementation, per 4E's own DRY precedent (6F §20)."""
```

`StartExecution` is never re-triggered by a duplicate `evaluate_next_directive` call — the Voice Orchestrator calls `start_workflow_execution` exactly once at call-setup, immediately after `resolve_published_workflow_version`, both inside the same call-initiation code path that already exists in 6D (never inside the per-turn loop).

---

## 8. Draft Graph Update Shape

### 8.1 Decision: Full Replace, Not Granular PATCH

**Decision (ADR-6I-03):** `PUT /api/v1/workflows/{workflow_id}/draft` accepts the complete `{entry_node_id, nodes[], edges[]}` graph and replaces `draft_graph` wholesale, mirroring the DB column's own atomic-JSONB-write shape (5G §6.1, ADR-5G-001). No `PATCH`/JSON-Merge-Patch semantics are defined for the draft graph — a bespoke partial-merge algorithm over a graph structure (node array plus edge array, both containing nested objects) has no unambiguous merge semantics for array elements (is a node missing from the PATCH body deleted, or untouched? JSON Merge Patch's null-means-delete convention does not extend cleanly to array-of-objects), and 6A §7.3 reserves `PUT` precisely for "genuinely full-replace semantics (e.g., replacing a workflow's entire draft graph)" — citing this exact resource.

### 8.2 Concurrency: `If-Match` Required

```text
GET  /api/v1/workflows/{id}          → ETag: "<hash(id, updated_at)>"   (6A §17.2 weak validator)
PUT  /api/v1/workflows/{id}/draft     → requires If-Match; mismatch → 412 PRECONDITION_FAILED
```

The client must have read the current `WorkflowDefinition` (and therefore its `updated_at`-derived ETag) before submitting a full-replace draft update — this is 6I's instance of 6A ADR-6A-08's weak-ETag concurrency model (no dedicated `version_number` column exists on `workflow_definitions`, and none is added here).

### 8.3 What `PATCH /workflows/{id}` Covers

Metadata only — `name`, `description`. Never `status`, `draft_graph`, or `published_version_id` (all three are state-machine-guarded per 6A §8.3/§17.2 and only mutate via the draft/validate/publish/archive action endpoints).

### 8.4 Server-Owned Fields

`workflow_id`, `organization_id`, `status`, `published_version_id`, `created_by`, `created_at`, `updated_at` are never client-writable on any request — Pydantic `extra="forbid"` (6A §22) makes supplying them a `422`, not a silent ignore.

---

## 9. Validate vs. Publish

### 9.1 Two Distinct Operations

`POST /workflows/{id}/validate` runs the full structural+expression validator against the **current `draft_graph`** without creating a `WorkflowVersion` — it exists purely to support the visual builder's "show me my errors before I try to publish" UX. `POST /workflows/{id}/publish` **always** re-runs the identical validation, tied to the exact draft state at the moment of publish, not to any previously-returned validation result or client-held token. There is no `validation_token`/"proof of prior validation" concept anywhere in this design — a client cannot skip re-validation by presenting an old result, closing the exact hazard the governing task warns against (§33).

### 9.2 Structured Validation Result

```json
{
  "data": {
    "valid": false,
    "errors": [
      {
        "code": "WORKFLOW_UNREACHABLE_NODE",
        "severity": "ERROR",
        "node_id": "0193f2f0-...",
        "edge_id": null,
        "path": "nodes[3]",
        "message": "Node 'confirm_appointment' is not reachable from the entry node."
      },
      {
        "code": "WORKFLOW_UNBOUNDED_CYCLE",
        "severity": "ERROR",
        "node_id": "0193f2f1-...",
        "edge_id": "0193f2f2-...",
        "path": "edges[7]",
        "message": "Cycle through node 'clarify_intent' has no LLM node with max_turns set on the cycle path."
      }
    ],
    "warnings": []
  },
  "meta": { "request_id": "..." }
}
```

`WorkflowValidationResultDTO` never collapses to a single generic `"invalid graph"` string (§62). `severity` is `ERROR | WARNING` — a `WARNING` (e.g., an `END_CALL` node with no `qualification_outcome` set) does not block publish; any `ERROR` does.

---

## 10. Graph Invariants — Server-Side, Authoritative

All ten invariants from 4E §5.1/§7.2 plus 5G's DB-enforced pair are validated **server-side**, never trusting the visual builder's own client-side checks:

| # | Invariant | Enforced at draft `validate`/`publish` | Enforced at runtime (defense-in-depth) |
|---|---|:---:|:---:|
| 1 | Entry node exists in `nodes[]` | ✅ | ✅ (fail execution if corrupted) |
| 2 | Every edge `source_node_id` exists | ✅ | ✅ |
| 3 | Every edge `target_node_id` exists | ✅ | ✅ |
| 4 | No unreachable nodes (DFS from entry) | ✅ | — (structural, not a runtime concern) |
| 5 | No unconstrained cycles — every cycle path contains an LLM node with `max_turns` set | ✅ | ✅ (`turn_count_at_node` hard-enforced regardless of graph, §12) |
| 6 | `DECISION` has exactly two outgoing edges (true/false) | ✅ | ✅ |
| 7 | `END_CALL` has zero outgoing edges | ✅ | ✅ |
| 8 | Published `WorkflowVersion.graph_json` is immutable | N/A (DB trigger, §36) | N/A |
| 9 | `ARCHIVED` workflow cannot publish | ✅ (`fn_workflow_publish` precondition) | N/A |
| 10 | Node `config` is valid for its `node_type` (discriminated union, §11) | ✅ | ✅ (unknown/malformed config → fail execution safely, §49) |

**Publish-time-only, stronger checks (§14):** referenced KB IDs exist/ready (6F), tool names are allow-listed (6E), transfer targets are well-formed, expression grammar is safe (§11).

---

## 11. Node Type Catalogue — Discriminated Config Union

Every node's `config` is validated against a **strict, `node_type`-discriminated Pydantic model** — never `dict[str, Any]` merely because persistence is JSONB (§62). Unknown fields are rejected (`extra="forbid"`), preventing a node config from smuggling a server-only or cross-context field.

| `node_type` | Config model | Key fields | Reference classification (§65) |
|---|---|---|---|
| `GREETING` | `GreetingNodeConfig` | `greeting_template: str (≤2000 chars)` | none |
| `PROMPT` | `PromptNodeConfig` | `prompt_ref: UUID`, `inject_position: SYSTEM\|USER` | logical-only (§27) |
| `LLM` | `LlmNodeConfig` | `prompt_ref: UUID`, `tools_enabled: bool`, `kb_ids: UUID[] (≤10)`, `max_turns: int\|null (1–50)` | `prompt_ref` logical-only; `kb_ids` pinned-by-ID, live-resolved content (§21) |
| `DECISION` | `DecisionNodeConfig` | `condition_expression: str (≤500 chars)`, `true_edge: UUID`, `false_edge: UUID` | none |
| `CONDITION` | `ConditionNodeConfig` | `conditions: list[{expression: str, target_edge: UUID}] (≤10)`, `default_edge: UUID` | none |
| `BRANCH` | `BranchNodeConfig` | `slot_name: str`, `branches: dict[str, UUID] (≤20)`, `default_edge: UUID` | none |
| `KNOWLEDGE_SEARCH` | `KnowledgeSearchNodeConfig` | `kb_ids: UUID[] (1–10)`, `query_template: str (≤500 chars)`, `result_slot: str`, `top_k: int (1–20)` | pinned-by-ID, live-resolved content (§21) |
| `TOOL_CALL` | `ToolCallNodeConfig` | `tool_name: str (allow-listed, §22)`, `argument_template: dict (≤4KB serialized)`, `on_success_edge: UUID`, `on_failure_edge: UUID` | pinned-by-name, live-resolved definition (§65) |
| `WEBHOOK` | `WebhookNodeConfig` | `url_template: str`, `method: GET\|POST`, `payload_template: dict (≤4KB)`, `timeout_ms: int (1000–10000)`, `result_slot: str` | **execution-blocked**, §23 |
| `API_CALL` | `ApiCallNodeConfig` | `method: GET\|POST\|PUT\|PATCH`, `url_template: str`, `headers: dict[str,str] (≤10 keys, no secret values)` | **execution-blocked**, §23 |
| `DELAY` | `DelayNodeConfig` | `duration_ms: int (0–5000)` | none |
| `TRANSFER` | `TransferNodeConfig` | `number_expression: str (≤200 chars)` | logical (resolved via safe expression against slots/session) |
| `HUMAN_TRANSFER` | `HumanTransferNodeConfig` | `queue_id: str`, `announcement_template: str (≤1000 chars)` | logical-only, `queue_id` existence not validated by 6I (6D-owned) |
| `END_CALL` | `EndCallNodeConfig` | `farewell_template: str (≤1000 chars)`, `qualification_outcome: QUALIFIED\|DISQUALIFIED\|null` | none |

**Mass-assignment protection:** no config model accepts a raw secret, a raw file path, a Python dotted-import path, or a class name — `tool_name` is a string looked up against an allow-list (§22), never a code reference the runtime could `importlib.import_module()`.

---

## 12. Cycle / Loop Protection

**Publish-time:** the graph validator runs Tarjan/DFS cycle detection over the full node/edge set; for every detected cycle, at least one node on the cycle path must be `node_type=LLM` with `config.max_turns` set to a non-null integer in `[1, 50]` (INV per 4E §5.1 inv.4, 5G ADR-5G-001 reasoning). A cycle with no such guard is rejected: `WORKFLOW_UNBOUNDED_CYCLE`.

**Runtime, defense-in-depth:** `WorkflowExecution.turn_count_at_node[node_id]` (5G `workflow_executions.turn_count_at_node JSONB`) is checked and incremented on every entry to an LLM node, independent of whether the publish-time validator ever ran correctly against this exact graph (a corrupted/manually-edited `graph_json`, or a future migration bug, must not translate into an infinite per-call loop). When the counter reaches `max_turns`, the engine **force-advances** past the node (per DDR from 4E §5.2 inv.3) rather than re-entering it — if no outgoing edge exists that doesn't loop back, the execution fails deterministically with `WORKFLOW_NODE_EXECUTION_FAILED` / `reason=MAX_TURNS_EXCEEDED_NO_EXIT` rather than spinning.

An LLM node with `max_turns=null` participating in a cycle is a publish-time rejection, never a runtime-discovered surprise.

---

## 13. Graph Size / Payload Limits

No limit is stated in 4E or 5G beyond "rarely exceeds a few hundred nodes" (4E §5.1) and the 6A §15/§36 platform-wide anti-DoS defaults. 6I sets the following, framed as this document's own binding decision (not a restated frozen number):

| Limit | Value | Rationale |
|---|---:|---|
| Max nodes per graph | 300 | "a few hundred" (4E §5.1), rounded to a concrete, enforceable ceiling |
| Max edges per graph | 900 | ~3 edges/node average upper bound (DECISION/CONDITION/BRANCH fan-out) |
| Max `draft_graph`/`graph_json` serialized size | 512 KB | Comfortably inside JSONB/TOAST economics at 5A's documented column-size guidance; well under 6A §36's 5MB response ceiling with headroom for the publish snapshot round-trip |
| Max single node `config` serialized size | 8 KB | Bounds `argument_template`/`payload_template`/templates; a legitimate node config has no reason to approach this |
| Max `condition_expression` / `query_template` / `*_expression` string length | 500 chars | Matches 6A §15's 500-char search-string cap, reused for consistency rather than inventing a second number |
| Max `CONDITION.conditions` / `BRANCH.branches` entries | 10 / 20 | Bounds per-node fan-out; a legitimate business decision tree rarely exceeds this without needing a sub-workflow (not modeled) |
| Max `kb_ids` per `LLM`/`KNOWLEDGE_SEARCH` node | 10 | Matches 6F §16's own `kb_ids` bound exactly (§21) — the Workflow node never asks for more than 6F's retrieval endpoint itself permits |
| Max slots per execution / max single slot value size | 100 slots / 4 KB per value | Bounds `workflow_executions.slots JSONB`; consistent with 4E's "SlotMap ~10–50 pairs" expectation with headroom |

`PUT /workflows/{id}/draft` returns `422 WORKFLOW_GRAPH_INVALID` (with `details.violated_limit`) for any request exceeding these — enforced before the DFS/cycle validator runs, so a pathological graph cannot even reach the O(V+E) validation pass.

---

## 14. Reference Validation — Draft vs. Publish

**Draft validation** (`PUT .../draft`, `POST .../validate`): purely structural — invariants 1–7, 10 (config shape), size limits. A `prompt_ref`/`kb_ids`/`tool_name` that doesn't (yet) exist is **not** rejected while editing — the builder must be usable while a tenant is still creating the KB or tool the node will eventually reference, mirroring 6E's own "format-validated only at draft/PATCH time" stance for `Agent.workflow_ref` (§19).

**Publish validation** (`POST .../publish`) — everything draft-validates, **plus**, verified in-process (never via internal REST, per the top-level constraint):

| Reference | Check | Failure code |
|---|---|---|
| `prompt_ref` (PROMPT/LLM nodes) | UUID format only — no existence check (§27, ADR-5G-010 carry-forward: no in-process existence-check port exists for Prompt Management, same class of gap as 6E's `DEP-6E-02`) | — (non-blocking by design) |
| `kb_ids` (LLM/KNOWLEDGE_SEARCH) | Exists, belongs to the same tenant, `status != ARCHIVED`, via 6F's in-process `KnowledgeApplicationService` (never 6F's REST endpoint — 6F §20/ADR-6F-05) | `WORKFLOW_REFERENCE_NOT_READY` |
| `top_k` on `KNOWLEDGE_SEARCH` | ≤ 6F's own `top_k` ceiling (20) — 6I never asks 6F for more than 6F itself permits | `WORKFLOW_NODE_CONFIG_INVALID` |
| `tool_name` (TOOL_CALL) | Exists in the tenant's `ToolPermissions` allow-list (4E policy `ToolMustBePermitted`) via 6E's tool registry, in-process | `WORKFLOW_NODE_CONFIG_INVALID` |
| `condition_expression` / all expression fields | Whitelist grammar compiles cleanly (§16) | `WORKFLOW_EXPRESSION_INVALID` |
| `TRANSFER`/`HUMAN_TRANSFER` targets | Well-formed E.164 (TRANSFER) or non-empty `queue_id` (HUMAN_TRANSFER) — existence of the queue/number is 6D's runtime concern, not publish-time verifiable here | `WORKFLOW_NODE_CONFIG_INVALID` if malformed |
| `WEBHOOK`/`API_CALL` nodes | See §23 — publish is **rejected outright** while these node types remain execution-blocked | `WORKFLOW_REFERENCE_NOT_READY` |

If a required dependency cannot be verified as safely executable, publish fails — a syntactically valid but operationally unusable `WorkflowVersion` is never created (governing task §64).

---

## 15. Reference Snapshot / Immutability Semantics at Publish

| Reference | Pinned into `graph_json`? | Resolved | Consequence of later change |
|---|---|---|---|
| `prompt_ref` (PromptId, not PromptVersionId) | Yes — the ID itself is frozen | Live, at LLM-node-evaluation time, against `prompt.active_versions[environment]` | ADR-5G-010 — see §27; the *content* rendered can drift between calls even though the pinned graph never changes |
| `kb_ids` | Yes — the IDs themselves are frozen | Live, at `KNOWLEDGE_SEARCH`/LLM-node-evaluation time, against the KB's *current* document set | Documents added/removed after publish are reflected in every future search — this is 6F's own documented behavior (KB content is not versioned), inherited unchanged |
| `tool_name` | Yes | Live, against the tenant's current `ToolPermissions`/`ToolDefinition` at TOOL_CALL-evaluation time | A tool revoked after publish causes the node to fail deterministically at runtime (`WORKFLOW_NODE_EXECUTION_FAILED`), routed to `on_failure_edge` if one exists |
| `TRANSFER`/`HUMAN_TRANSFER` targets | Yes (expression/queue_id as authored) | Live, evaluated against `slots`/`session` at TRANSFER-evaluation time | No caching — always current call state |
| `graph_json` structure itself (nodes/edges/config) | Frozen, byte-for-byte, forever | N/A | This is the one thing that never drifts — INV-WF-01 |

Nothing in this table is invented — it follows directly from 4E §5.1's decision that only `graph_json` is snapshotted, and every ID inside it is a **logical reference**, resolved live by whichever bounded context owns that reference, exactly as 6E already documents for `Agent.workflow_ref` and `Agent.prompt_ref`.

---

## 16. Expression Safety — P0 Security Boundary

### 16.1 Grammar (from 4E §5.3 / 3D §5.5, reproduced as the binding API contract)

**Permitted:** `slots.<name>`, `session.<field>`, `tool_results.<tool>.<field>`; string/numeric/boolean literals; `== != > < >= <=`; `and or not`; `in` (against a literal list); `is null` / `is not null`; whitelisted calls `len()`, `str()`, `int()` only.

**Forbidden, unconditionally:** `eval`/`exec`/`import`/dynamic attribute access beyond the three allowed namespaces/any function not in the three-item whitelist/assignment/lambda/comprehensions/`__`-prefixed names.

### 16.2 Compilation Model

The evaluator (3D §5.5, 4E §5.3) is a whitelist-based AST walker over a restricted grammar — **never** Python `eval()`/`exec()`, and never a dynamic-import-capable interpreter. This is P0: a workflow condition expression is 100% user-authored, tenant-controlled input, and reaching arbitrary code execution from it would be a full platform compromise.

### 16.3 Validation Points (DDR-4E-006, unmodified — defense-in-depth is mandatory, not optional)

| Point | What runs | Failure behavior |
|---|---|---|
| **Draft `validate`/`publish`** | Full grammar compile + whitelist AST check on every expression field in the graph | `422 WORKFLOW_EXPRESSION_INVALID`, `details.node_id`/`details.field`, deterministic per-expression message |
| **Runtime, every evaluation** | The *exact same* compiler runs again against the pinned `graph_json` — never trusts that publish-time validation ran, or ran correctly, against this exact stored bytes | Fail-closed: `WORKFLOW_NODE_EXECUTION_FAILED`, execution routed to `FAILED` if no safe fallback edge exists — **never** falls back to permissive evaluation |

### 16.4 Limits (this document's own decision, since no source sets one)

| Limit | Value |
|---|---:|
| Max expression length | 500 chars (§13) |
| Max AST node count | 200 |
| Max nesting depth | 10 |
| Max evaluation time budget | 5 ms (pure CPU, in-process — enforced by a wall-clock guard around the evaluator call, not a language-level timeout) |

A malformed/oversized expression is rejected at validate/publish time; if one somehow reaches runtime (corrupted `graph_json`), the evaluator raises internally and the node fails per §49 — it never partially evaluates or falls back to a laxer parser.

### 16.5 Deterministic Error Responses

```json
{ "error": { "code": "WORKFLOW_EXPRESSION_INVALID", "message": "Expression uses a forbidden construct.",
  "details": { "node_id": "...", "field": "condition_expression", "reason": "call to 'os.system' is not in the whitelist" },
  "request_id": "...", "retryable": false } }
```

---

## 17. Execution Start — Idempotency and Concurrency (Adversarial Review)

### 17.1 The Actual Mechanism (not 5G's stale prose — §3, discrepancy #1/#2)

`workflow.fn_start_workflow_execution(p_organization_id, p_workflow_version_id, p_session_ref, p_started_at)` is `SECURITY DEFINER`, `SET search_path = workflow, organization, public, pg_catalog` (correctly includes `public` for its own unqualified `gen_uuid_v7()` call — no search-path defect of the `076_5K1` class exists here, verified). It is the **sole legal INSERT path** — `INSERT` is revoked from `app_api`, `app_worker`, and `app_platform_admin` alike on `workflow_executions` (§3, §38).

Internally: (1) validates `p_organization_id = organization.current_tenant_id()` — explicit tenant check inside the `SECURITY DEFINER` boundary, not merely trusted from the caller's argument (§34); (2) validates the referenced `workflow_version_id` exists for that tenant; (3) takes `pg_advisory_xact_lock(hashtext(org_id || ':' || session_ref))` — serializing concurrent calls for the *same* `(org, session)` pair for the duration of the transaction; (4) `SELECT ... WHERE status='ACTIVE' LIMIT 1`; if found, `RAISE EXCEPTION`; else `INSERT`.

### 17.2 Adversarial Cases

| Case | Outcome | Mechanism |
|---|---|---|
| Two simultaneous `StartExecution` for the same session | The second blocks on the advisory lock until the first's transaction commits, then its own `SELECT` sees the first's now-committed `ACTIVE` row and raises `fn_start_workflow_execution: session % already has an ACTIVE workflow execution`. **This is an exception, not an idempotent replay** — the caller receives an error, not the existing execution's ID back. | `pg_advisory_xact_lock` (transaction-scoped) + guarded SELECT/INSERT |
| Same session, two different `WorkflowVersion`s requested concurrently | Same serialization — whichever acquires the lock first wins; the loser's request (for a *different* version) is still rejected with the same "already ACTIVE" exception, not silently substituted | Same |
| Same tenant, retry after an application-level timeout (the original request actually succeeded) | **Resolved 2026-08-29 (§63) — no longer exception-based.** `100_5G1.sql` revised `fn_start_workflow_execution()` to return `TABLE(execution_id, execution_started_at, outcome)` with `outcome IN ('STARTED','REPLAYED_EXISTING','VERSION_CONFLICT')` — a retry for the same session and the same `workflow_version_id` now gets `REPLAYED_EXISTING` with the original `execution_id` back directly, as an ordinary return value, not an exception the caller must catch and reconcile. Live-proven, including under genuine two-connection simultaneity (§63). | Deterministic function return value — no application-layer catch-and-reconcile logic required |
| Worker crashes after `INSERT` commits but before the caller ever learns the `execution_id` (e.g., network drop on the RPC response) | The row is durably `ACTIVE`. A blind retry of `StartExecution` hits "already ACTIVE" (previous row). Recovery is: catch the exception, then `SELECT` the existing `ACTIVE` execution for `(org, session_ref)` via the ordinary tenant-scoped `SELECT` grant (no `SECURITY DEFINER` needed for a read) and resume from it. | Same pattern as above |
| Execution already `COMPLETED`, and a duplicate/late "start" event arrives | The advisory lock + `SELECT ... WHERE status='ACTIVE'` predicate does **not** find the `COMPLETED` row (correct — it is not `ACTIVE`), so a **new** execution is created for the same session. This is **the intended, correct behavior** for a genuinely new call/session — Workflow's uniqueness is "at most one `ACTIVE` execution per session," never "at most one execution ever per session." A caller must ensure `session_ref` genuinely identifies a *new* call (Voice's own `call_sessions.id` is already unique per call — this is Voice's concern, not Workflow's, per the logical-reference boundary). | By design |
| Two different Workflows mistakenly both attempt `StartExecution` against the same `session_ref` | The second is rejected as "already ACTIVE" regardless of which `WorkflowVersion` it names — the invariant is keyed purely on `(organization_id, session_ref)`, not on workflow identity. This correctly prevents a session from ever running two Workflow graphs concurrently, even by application misconfiguration. | Same |
| Cross-tenant `organization_id` spoof via the RPC argument | `IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN RAISE EXCEPTION` — the function does not trust its own caller-supplied tenant argument; it cross-checks against the session's actual `SET LOCAL app.tenant_id` (§34). | Explicit in-function tenant check |

**Residual, disclosed risk:** the advisory lock key is `hashtext(org_id::text || ':' || session_ref::text)` — a 32-bit hash into PostgreSQL's global advisory-lock namespace. A hash collision with an unrelated advisory lock elsewhere in the platform is astronomically unlikely but not mathematically impossible; this is inherited from the executed migration as-is (not a 6I-introduced risk, and not worth a schema change to close).

---

## 18. Voice→Workflow Runtime Contract — Directive Production

Restated compactly (full contract in §7): `evaluate_next_directive(session_id, utterance)` loads Redis hot-tier state (or DB on cache miss), parses the **pinned** `WorkflowVersion.graph_json` (never re-resolves `published_version_id`), dispatches to the current node's `NodeExecutor` (3D §6.2's open/closed registry), applies slot updates, advances the cursor, schedules an async checkpoint (§28), and returns exactly one `Directive` (§4.4) to the Voice Orchestrator. This loop runs entirely in-process inside the same pod handling the call's WebSocket connection — there is no HTTP hop, no internal REST call, and no Celery round trip on this path (checkpointing is the only async step, and it is fire-and-forget from the turn's perspective, per DDR-4E-002).

---

## 19. Agent → Workflow Boundary

6E (frozen) stores `Agent.draft_config.workflow_ref: UUID, nullable` — **format-validated only**, existence unverified by 6E design (`DEP-6E-03`, explicitly marked "ownership belongs to 6I"). `workflow_ref` is a **`WorkflowDefinitionId`**, not a `WorkflowVersionId` — this is the same "pin the definition, live-resolve the version" pattern 6I already uses for `prompt_ref` (§15), and it is frozen into `AgentVersion.snapshot_json` unchanged, permanently, at Agent-publish time (6E §16).

### 19.1 Two-Stage Resolution (this document's contribution — closes `DEP-6E-03`)

```text
AgentVersion.snapshot_json.workflow_ref   (WorkflowDefinitionId — frozen forever at Agent publish)
        ↓  live, at call-start time
resolve_published_workflow_version(workflow_definition_id, tenant_id)   (§7.1)
        ↓  returns the CURRENT published_version_id
StartExecution(that WorkflowVersionId, session_ref)
        ↓  pinned for the rest of this one call (INV-WF-03)
```

6I supplies `resolve_published_workflow_version()` as the in-process query that closes `DEP-6E-03` — but since 6E is frozen and its own publish-time flow does not call it (existence is "format-validated only" at Agent-publish, by 6E's own explicit design choice), **the port now exists for consumption but is not invoked by 6E's publish path**. This is disclosed as a controlled, non-blocking cross-phase carry-forward (§54), not a 6I defect — 6I is not authorized to amend 6E.

### 19.2 Workflow Archived After AgentVersion References It

If a Workflow is archived after an `AgentVersion` was published referencing its ID, `resolve_published_workflow_version()` returns `WORKFLOW_ARCHIVED` on the **next** call attempt using that AgentVersion — the call fails to start its Workflow-governed portion deterministically (mapped to a Voice-side call-setup failure, per 6D's own error-normalization convention) rather than silently falling back to no-workflow behavior or resurrecting the archived graph. An **in-progress** call at the moment of archiving is unaffected — its `WorkflowExecution` already pinned a `workflow_version_id` before the archive and continues unchanged (§20's Race analysis formalizes why this is safe).

### 19.3 Workflow Republished Mid-Call

No effect on any in-flight `WorkflowExecution` — `resolve_published_workflow_version()` is called exactly once, at call start, never again during the call (§7.1, §18). The next **new** call resolves the newly-published version.

---

## 20. Campaign → Workflow Boundary — ACL

6H (frozen) states plainly: *"A future Workflow node calls Campaign's own public application services (`CreateCampaign`, `StartCampaign`) through an ACL — 6H does not design that ACL."* 6I designs it now, narrowly:

### 20.1 The ACL Contract

```python
class CampaignAclPort(Protocol):
    """In-process only — never campaign.* table writes, never a REST hop.
    Wraps exactly the two 6H-approved public application services named
    above; invents no new Campaign capability, bypasses no eligibility/
    idempotency/safety model 6H already defined."""
    async def create_campaign_via_workflow(
        self, cmd: CreateCampaignCommand, tenant_id: TenantId, triggering_execution_id: ExecutionId,
    ) -> CampaignId: ...
    async def start_campaign_via_workflow(
        self, campaign_id: CampaignId, tenant_id: TenantId, triggering_execution_id: ExecutionId,
    ) -> None: ...
```

A hypothetical future `TOOL_CALL` node whose `tool_name` maps to one of these two capabilities (allow-listed exactly like any other tool, §22) invokes `CampaignAclPort`, which internally calls 6H's own `CreateCampaign`/`StartCampaign` use cases unchanged — 6H's own eligibility pipeline (4I mandatory eligibility), DNC/consent checks, idempotency keys, and audit trail all fire exactly as they would for a REST-triggered call, because the underlying use case is identical.

### 20.2 What 6I Does Not Do

No `campaign.*` table is ever written from Workflow. No Campaign state transition is invented. No 6H idempotency/safety guarantee is bypassed — the ACL is a thin in-process adapter, not a parallel code path. **No node type in 4E's §5.1.3 vocabulary is a dedicated "Campaign" node** — this capability, if built, is exposed as an ordinary `TOOL_CALL` node whose tool happens to be Campaign-backed, exactly like any CRM tool already is (4E §16.9). No new node type is introduced by this document.

### 20.3 Classification

`EXECUTION-BLOCKED / CONTRACT-DEFINED` — 4E/5G define no concrete tool named `createCampaign`/`startCampaign` in any tool registry today; this section documents the contract shape a future tool definition would bind to, per the governing task's explicit instruction not to fabricate a complete contract where 4E/6H leave it unspecified.

---

## 21. `KNOWLEDGE_SEARCH` Node → 6F Boundary

Resolves `DEP-6F-11` (6F's own disclosed deferral: *"Workflow `KNOWLEDGE_SEARCH` node's use of the same in-process port — DEFERRED TO 6I — Same `KnowledgeSearchPort` resolution rule (6F §20) applies; 6I must reference this document rather than re-specify it"*).

### 21.1 In-Process Only

`KNOWLEDGE_SEARCH` and `LLM` (when `tools_enabled` implies a knowledge lookup) nodes call `KnowledgeApplicationService.search_knowledge()` **as a Python method inside the same process** — identical in kind to `WorkflowExecutionPort`/`PromptRenderPort`/`ConversationMemoryPort` (4E §19; 6F ADR-6F-05). Never 6F's public REST endpoint, never an internal HTTP hop — an HTTP round trip here would consume the entire Tier E tool-execution sub-budget (150ms p50 / 400ms p95, 6A §11) on transport alone.

### 21.2 Publish-Time Validation (repeats §14 for completeness)

`kb_ids` exist, belong to the tenant, and are not `ARCHIVED`, checked via the same in-process service. `top_k` is capped at 6F's own ceiling (20) — 6I never widens what 6F itself permits.

### 21.3 Runtime Failure Behavior (uses 4E/3D semantics, invents nothing new)

Per 6F's own documented behavior for the identical port (*"a mid-call `lookupKnowledge` invocation against an archived/nonexistent KB degrades to an empty result, not a call failure"*): a `KNOWLEDGE_SEARCH` node whose retrieval returns nothing (empty KB, all referenced KBs archived post-publish, or a transient retrieval error) does **not** fail the Workflow execution — it sets `result_slot` to an empty `RetrievalContext` (empty `formatted_text`, empty `citations`) and advances via `CONTINUE`, exactly as 3D §16.2's sequence diagram shows. A DECISION/CONDITION node downstream that branches on the retrieved content's presence (e.g., `retrieved_context is not null`) is the graph author's own mechanism for handling "nothing found" — the engine itself never treats empty retrieval as an error condition.

---

## 22. `TOOL_CALL` Node Boundary

4E/3D already define a unified `ToolDefinition`/`ToolExecution`/`ToolRunner` registry (4B §5.4/§5.5, reused verbatim by 4E §19/§16.9) — 6I does not turn each tool into its own service, and does not redesign `ToolDefinition`/`ToolExecution` (6E-owned, §21.5 of 6E explicitly excludes Workflow-context tool execution from its own scope and defers it here).

| Requirement | How it's met |
|---|---|
| Input arguments schema-validated | `argument_template` is rendered against current `slots` (Jinja2-style, per 4E §5.1.4) then validated against the tool's own `input_schema` (6E-owned `ToolDefinition.input_schema`) before invocation |
| Tool identity allow-listed | `tool_name` must exist in the Agent's `ToolPermissions` (4E policy `ToolMustBePermitted`), checked at publish time (§14) and again at runtime (defense-in-depth, §49) |
| Tenant-authorized execution | `AuthorizeAndStartToolExecution` (4B/6E-owned use case) performs its own authorization check — 6I calls it, never bypasses it |
| Bounded, serializable result | Tool result is written into a single named slot; 5C §36's own documented cap (`tool_executions.result JSONB` application-layer-capped at 64KB, with a `result_storage_ref` S3 pattern for larger payloads) is inherited unchanged — a Workflow slot never holds more than that cap |
| Deterministic failure branch | `on_failure_edge` is the node's own explicit failure route (4E §5.1.4); if absent, the execution fails per §49 |
| Auditability | Every `TOOL_CALL` node invocation creates a `voice.tool_executions` row exactly as any other tool invocation does (6D/6E-owned audit trail — no separate Workflow-owned audit path is invented) |

**No arbitrary code path invocation:** `tool_name` is a string key into the tenant's `ToolDefinition` catalogue — never a dotted Python import path, class name, or file path. There is no code anywhere in this design that resolves `tool_name` via `importlib`/`getattr`/`eval`.

**P0 finding — no durable per-attempt idempotency:** see §30. `voice.tool_executions` (5C §5.7/§9.7, verified against the executed DDL) has **no idempotency key, no unique constraint tying a row to a stable `(execution_id, node_id, attempt)` identity** — it is a plain INSERT-at-start/UPDATE-at-completion table. A retried `TOOL_CALL` node evaluation after a crash creates a **new** `tool_executions` row and re-invokes the tool, with no platform-level protection against a non-idempotent tool being called twice. This is not a 6I-introduced gap — it is inherited from 5C/4B as-is — but it is a real, disclosed BLOCKER for any tool that is not independently idempotent (§30).

---

## 23. `WEBHOOK` / `API_CALL` Nodes — Execution-Blocked

6J (Integrations/Webhooks/Plugins) is **not designed yet**. Per the governing task's explicit instruction, 6I does not invent 6J's connector infrastructure. 5I (Integrations/Webhooks/Plugins schema) provides `webhooks.webhook_endpoints`/`webhook_deliveries` for **outbound platform→tenant** notification delivery (6A §28.1) — a fundamentally different mechanism from a Workflow node making an **outbound, tenant-configured, arbitrary-URL** HTTP call at call time. No existing frozen infrastructure gives `WEBHOOK`/`API_CALL` nodes a safe execution path today.

### 23.1 Decision: Option A — Contract-Defined, Execution-Blocked

**Decision (ADR-6I-04):** `WEBHOOK` and `API_CALL` node types are **accepted in `draft_graph`** (a tenant may author and save them while building a graph — the visual builder is not crippled) but **publish is rejected** (`422 WORKFLOW_REFERENCE_NOT_READY`, `details.reason=INTEGRATION_BINDING_UNRESOLVED`) for any graph containing one, until 6J defines the credential-binding and egress-control infrastructure these nodes require. This is Option C from the governing task's three offered choices (draft-acceptable, publish-blocked), chosen over Option A (fully blocked even in draft — needlessly limits the builder) and Option B (route through an existing generic port — no such port exists yet; fabricating one would be exactly the "pretend 6I owns it" the governing task forbids).

### 23.2 Required Controls Before These Nodes May Publish (disclosed dependency on 6J, not designed here)

```text
scheme allow-list (https only)              no loopback / link-local / RFC1918 unless enterprise allow-list
DNS rebinding defense (resolve-then-pin)    cloud metadata-service IP blocking (169.254.169.254 and equivalents)
bounded timeout (already modeled: 1000-10000ms on WebhookNodeConfig, §11)
bounded response size                        redirect policy (bounded count, re-validated per hop)
secret resolution via 6J credential store   — never a raw secret in graph JSON (§46)
audit trail                                  no DB transaction held during the external call (6A §35, universal rule)
```

Until 6J supplies the credential-reference type and the egress-control adapter implementing these controls, **no WEBHOOK/API_CALL node executes** — not because 6I chooses to gate it arbitrarily, but because no safe implementation exists in any frozen source. Marking these "implementation-ready" today would be exactly the SSRF engine the governing task warns against.

---

## 24. `TRANSFER` / `HUMAN_TRANSFER` / `END_CALL` → 6D Boundary

Workflow never implements telephony transfer itself. The `WorkflowRuntimeService.evaluate_next_directive()` result is a `Directive` (§4.4) consumed by the Voice Orchestrator, which then invokes **6D's own existing call-control mechanism** — the same in-process application service backing 6D's `POST /calls/{id}/transfer` REST action endpoint (6D §11's `ACTIVE → TRANSFERRING` transition) — never a second, Workflow-owned call-control path. `END_CALL` similarly produces a directive consumed by Voice's existing call-termination path (`POST /calls/{id}/terminate`'s in-process equivalent), carrying `qualification_outcome` through to CRM exactly as 4E §23 Open Question OQ-4E-07 anticipates (resolved via the Voice Platform's `conversation.qualification_set` event, not a second Workflow-owned signal — avoiding the duplicate-qualification-signal risk that Open Question names).

No second call-control API is invented anywhere in this document.

---

## 25. `DELAY` Node — Realtime Safety

**Decision (ADR-6I-05):** a `DELAY` node's `duration_ms` (capped 0–5000ms, §13) is implemented as a `WAIT` directive (§4.4) returned to the Voice Orchestrator — **never** a `sleep()` call inside the Workflow engine's own evaluation path, and never held across a DB transaction. The Voice Orchestrator, which already owns the per-turn timing loop, is responsible for realizing the wait (e.g., scheduling the next turn evaluation after the delay) exactly as it already handles TTS playback timing — this is 6D's runtime concern, not a new blocking primitive introduced by 6I.

The 5-second cap is a **hard validation ceiling** at publish time (`422 WORKFLOW_NODE_CONFIG_INVALID` above it) — a malicious or buggy workflow cannot configure an effectively unbounded per-turn delay, closing the exact DoS vector the governing task names. No source document sets this number; 6I sets it here as its own binding decision, chosen to stay well inside the Tier E per-turn latency budget (6A §11's 1500ms p95 full-turn ceiling) even in combination with other node evaluation costs.

---

## 26. `LLM` Node → 6E / Model Router

The `LLM` node config (`prompt_ref`, `tools_enabled`, `kb_ids`, `max_turns`) never re-implements provider routing — model/provider selection is entirely 6E/4B's Model Router's responsibility, consumed identically to how the rest of the Voice turn loop consumes it. Workflow supplies **which** prompt, **which** tools are enabled, and **which** KBs are in scope for this node; it never names a specific LLM provider/model in `graph_json` — doing so would violate the platform's Provider Independence principle (`ARCHITECTURE_PRINCIPLES.md`) and would silently override the Agent/AgentVersion-pinned model configuration 6E already owns, which no frozen source authorizes. If an `LLM` node's `tools_enabled=true`, the set of tools actually callable is still bounded by the Agent's `ToolPermissions` (6E-owned) — a Workflow node cannot widen what the Agent's own configuration permits.

---

## 27. Prompt References — ADR-5G-010 Carried Forward, Not Silently Fixed

5G's own ADR-5G-010 (§25, "No Prompt Version Pinning in WorkflowExecution") and 5L's Global Reconciliation (§G.34) both classify this as **Category C — deferred**, explicitly confirming *"no 'deterministic replay' requirement found anywhere in frozen SRS or 4E DDD"* and that it is *"not required by any frozen SRS/DDD text found."* 6I inspected `graph_json`'s actual structure (5G §6.1) and confirms:

1. **What is stored:** a `PROMPT`/`LLM` node's `config.prompt_ref` is a **`PromptId`**, never a `PromptVersionId` (5G §6.1's `draft_graph`/`graph_json` JSON shape, confirmed against 4E §5.1.4's table).
2. **Runtime resolution:** at every `LLM` node evaluation, the currently-`active_versions[environment]` `PromptVersion` is resolved **live** (4E §14.3, 5G QP-09) — not the version active at the time the Workflow was published, and not the version active at the time the call started.
3. **Impact — live call consistency:** if `SetActiveVersion` changes the active prompt version *mid-call* (an operator rolls back or promotes a prompt while calls are in flight), subsequent `LLM` node evaluations in the *same, already-active* call can render a **different** prompt version than earlier turns in that same call used. This is a real, disclosed behavior — not a bug 6I is asked to silently patch.
4. **Impact — replay/debugging:** the execution debug view (§32) can show which `prompt_ref` a node referenced, but **cannot** show which exact `PromptVersion` content was actually rendered for a historical turn unless the `active_versions` state at that historical moment is separately reconstructed from `prompt.prompt_versions.published_at` timestamps and audit history — this is an analytics/audit-tooling gap, not a runtime-correctness defect (5G's own framing, reused verbatim because it is accurate).
5. **Impact — republishing/rollback:** republishing a Workflow does not touch prompt resolution at all (the two are orthogonal); rolling back a `PromptVersion`'s `active_versions[environment]` takes effect on the **very next** `LLM` node evaluation across every Workflow that references that Prompt, platform-wide — this is 5G's own documented, intended behavior for prompt rollback (4E §16.6 sequence diagram), not something 6I introduces or should reverse.

**6I does not invent a schema migration to pin `prompt_version_id` into `graph_json`.** Doing so would be exactly the "fix a V1 correctness problem you haven't proven exists against frozen requirements" the governing task forbids — no frozen SRS/DDD requirement for deterministic replay exists, per 5L's own explicit confirmation. This item remains carried forward to Phase 9, unchanged.

---

## 28. Execution Hot State — Redis vs. PostgreSQL

| Tier | Store | Contents | TTL | Authority |
|---|---|---|---|---|
| Hot | Redis `workflow:state:{session_id}` (3D §6.3) | `current_node_id`, `slots`, `turn_count_at_node` | Call duration + 10 min grace | Authoritative **during** the call — every per-turn read/write hits Redis, never Postgres, on the hot path |
| Durable | PostgreSQL `workflow.workflow_executions` | Full aggregate — `current_node_id`, `slots`, `turn_count_at_node`, `node_execution_history`, `status` | Permanent (12-month hot retention, matching `call_sessions`) | Authoritative **for recovery and debug** — checkpointed once per completed Turn (DDR-4E-002), never per internal node-step, never synchronously on the LLM/STT/TTS response path |

**Checkpoint cadence:** once per Turn, via an async Celery task enqueued at the end of `evaluate_next_directive()` — never awaited by the turn loop itself (§7.1, §36).

**What the debug API promises (§32):** the PostgreSQL row is the record `GET /workflow-executions/{id}` reads — it is **explicitly not real-time** for an `ACTIVE` execution; it lags the live Redis state by up to one Turn's worth of async-checkpoint latency (typically sub-second, but never contractually "current"). The response for an `ACTIVE` execution carries `checkpoint_lag_disclosed: true` semantics (documented in the DTO, §62) rather than silently presenting stale data as live.

**Recovery on Redis loss:** if the Redis key is lost or expires mid-call (pod eviction, Redis failover, TTL misconfiguration), the **next** `evaluate_next_directive()` call misses cache and reloads from the last PostgreSQL checkpoint (up to one Turn stale) — this is safe for **pure** node re-evaluation (the worst case is repeating one Turn's worth of computation, per DDR-4E-002's own accepted cost) but is **not** safe for a Turn that already fired a side-effecting node (§30) — that is the genuine gap, addressed there, not glossed over here as "Redis prevents duplicates."

---

## 29. Redis Failure / Execution Recovery — Deterministic Behavior

| Scenario | Required behavior |
|---|---|
| Redis unavailable before `StartExecution` | `StartExecution` itself does not touch Redis (§17 — pure Postgres via `fn_start_workflow_execution`); the execution starts normally. The *first* `evaluate_next_directive()` call then fails to warm the Redis cache and falls through to the Postgres-load path below. |
| Redis unavailable mid-call | Each `evaluate_next_directive()` call independently attempts Redis first, falls back to loading the last Postgres checkpoint on miss/error, and proceeds — **at the cost of losing any state accumulated since the last checkpoint** (up to one Turn) if the *previous* Turn's checkpoint write never completed. A pure re-evaluation of that lost Turn is safe (DDR-4E-002); a Turn that fired a side-effecting node and then lost its checkpoint before Redis could persist the advanced cursor is the scenario §30 must close — the engine must **not** blindly resume from the stale (pre-side-effect) cursor and re-fire the same side effect. |
| Hot execution key expires unexpectedly (TTL misconfiguration) | Treated identically to "Redis unavailable mid-call" — reload from Postgres checkpoint, same caveat above. |
| Worker restarts | The next Turn's `evaluate_next_directive()` call is stateless from the worker's perspective (all state lives in Redis/Postgres, never in-process) — a restarted worker resumes correctly for any Turn that has no in-flight side effect. |
| Celery checkpoint delayed | The Postgres row is stale by however long the delay is; the live call is unaffected (Redis remains authoritative for the call itself) — only the debug API (§32) shows lag, disclosed per §28. |
| PostgreSQL checkpoint older than Redis's hot state | Expected, normal condition during any active call — not an error. |
| Duplicate checkpoint delivery (Celery at-least-once redelivery) | The checkpoint UPDATE (§37) must be safe against being applied twice with identical content — a plain `SET current_node_id=$x, slots=$y, ...` is naturally idempotent for identical inputs; the ordering hazard (§37) is the real risk, not duplication of an identical write. |

**Binding rule, restated from the governing task:** the platform must **never** restart a Workflow execution from the entry node, and must **never** blindly repeat a side-effecting node's action, merely because Redis disappeared. Where the platform cannot prove a side-effecting Turn's outcome (Redis lost *and* the Postgres checkpoint for that Turn never landed), the correct, minimum-safe behavior is to **fail the execution** (`FailExecution`, `reason=CHECKPOINT_UNRECOVERABLE_AFTER_SIDE_EFFECT`) rather than guess — this is the same conservative posture `099_5C1.sql`'s `SUBMITTING`/`AMBIGUOUS` states already establish for Voice's own outbound-dispatch side effects, and Workflow inherits the identical philosophy even though (per §30) it does not yet inherit the identical *mechanism*.

---

## 30. Side-Effecting Node Idempotency — P0 Finding (RESOLVED — see §63)

> **Status update (2026-08-29, Phase 6I Blocker Remediation pass):** the gap proven in §30.1 below is now **RESOLVED** by migration `100_5G1.sql` — `workflow.node_execution_claims` plus five guarded functions, live-validated on genuine PostgreSQL 16.10 including a true two-connection concurrent-duplicate-claim race. §30.1's proof stands unchanged as the record of what was found; §63 documents the closure and its live evidence. `TOOL_CALL`/`TRANSFER`/`HUMAN_TRANSFER` are no longer blocked pending this fix; `WEBHOOK`/`API_CALL` remain execution-blocked pending 6J regardless (ADR-6I-04, unchanged — this is a separate, still-open dependency).

### 30.1 The Gap, Proven Against Actually-Executed Schema

Nodes `TOOL_CALL`, `WEBHOOK`, `API_CALL`, `TRANSFER`, `HUMAN_TRANSFER` can each produce an irreversible external or business side effect. 6I inspected every durable table `workflow`/`voice` schema exposes for a per-node-execution claim mechanism and found **none**:

- `workflow.workflow_executions.node_execution_history` is an **embedded, non-unique JSONB array**, checkpointed asynchronously, once per Turn (§28) — it records history, it does not **claim** an attempt before the side effect fires.
- `voice.tool_executions` (5C §5.7/§9.7, verified against executed DDL `013_5C.sql`) has **no idempotency key and no unique constraint** tying a row to a stable `(execution_id, node_id, attempt)` identity — it is a plain `INSERT`-at-start/`UPDATE`-at-completion table, confirmed by reading its actual `CREATE TABLE`.
- No `workflow`-schema table analogous to `voice.call_dispatch_keys` (the `RESERVED → CLAIMED → SUBMITTING → CONFIRMED|AMBIGUOUS|FAILED` state machine `099_5C1.sql` had to build specifically to stop Voice's own outbound-dial side effect from firing twice) exists for Workflow-triggered side effects.

**Concrete failure scenario (proven, not hypothetical):** a `TOOL_CALL` node's tool succeeds (e.g., a non-idempotent "charge card"/"create order"/"send SMS" tool) → the worker crashes before the Turn's checkpoint reaches Redis or Postgres → the next `evaluate_next_directive()` call for this session (whether from a genuine retry or from Redis-miss recovery, §29) re-evaluates the **same, not-yet-advanced** cursor → the same `TOOL_CALL` node fires again → the tool executes a second time, with **nothing in the current schema preventing it.**

**Do not dismiss with "Redis prevents duplicates."** Redis is not durable across the exact failure window that matters (a crash between the side effect succeeding and any state update — Redis or Postgres — reflecting that success), which is precisely the class of defect `099_5C1.sql`'s design notes call out as the reason a *durable, pre-side-effect commit boundary* (their `SUBMITTING` state) was required, not merely a Redis flag.

### 30.2 Classification and Minimum Remediation

**BLOCKER** for any Workflow graph containing `TOOL_CALL`, `WEBHOOK`, `API_CALL`, `TRANSFER`, or `HUMAN_TRANSFER`, until closed. **Not blocking** for graphs composed only of `GREETING`/`PROMPT`/`LLM` (without `tools_enabled` firing a side-effecting tool)/`DECISION`/`CONDITION`/`BRANCH`/`KNOWLEDGE_SEARCH`/`DELAY`/`END_CALL` — every one of those is either pure computation or an idempotent-by-nature read, safely re-evaluable per DDR-4E-002's own accepted "repeat one Turn's computation" cost model.

**Minimum controlled remediation (sketch, not implemented here — a future, additive-only schema amendment):** a new `workflow.node_execution_claims` table, structurally modeled on `voice.call_dispatch_keys`'s proven state machine:

```text
workflow.node_execution_claims (
  execution_id UUID, node_id UUID, turn_count_at_node INTEGER,   -- composite identity
  claim_state  TEXT  -- CLAIMED -> SUBMITTING -> SUCCEEDED | FAILED | AMBIGUOUS
  side_effect_ref TEXT NULL   -- e.g. tool_executions.id, once known
)
```

A side-effecting `NodeExecutor` would be required to: (1) `CLAIM` before rendering `argument_template`; (2) transition to `SUBMITTING` in a durable commit **strictly before** invoking the tool/webhook/transfer (mirroring `fn_begin_provider_submission()`'s exact pattern); (3) record `SUCCEEDED`/`FAILED`/`AMBIGUOUS` after the call returns or times out. A retry finding an existing `SUBMITTING`/`AMBIGUOUS` claim for the same `(execution_id, node_id, turn_count_at_node)` **never** re-fires the side effect — it either waits for reconciliation or fails the execution closed, exactly as `099_5C1.sql` already does for outbound dial attempts.

This is disclosed here as the required shape of the fix; it is **not** designed to completion or implemented in this document (no application code, per the governing task's constraint) — it is carried forward as a named `BLOCKER` in §54's dependency table, to be resolved by a controlled Phase 5.x amendment before any tenant is allowed to publish a Workflow containing one of the five listed node types against a production tenant with a non-idempotent tool bound to it.

---

## 31. Node Execution History — Storage Bounds

`node_execution_history` (5G §6.3) is bounded by call length in practice (~10–50 Turns × 1–3 node executions each, per 4E §5.2's own sizing note) but **has no hard schema-level cap**. 6I sets an application-layer ceiling consistent with §13's philosophy:

| Bound | Value |
|---|---:|
| Max `node_execution_history` entries retained per execution | 500 (well above any plausible legitimate call; a runaway loop is caught by `turn_count_at_node`/`max_turns` long before this, §12) |
| Max call duration (existing Voice-owned ceiling, inherited) | Per 6D's own call-duration cap — not restated/altered here |

List endpoints (`GET /workflow-executions`) **never** inline `node_execution_history` or `slots` — see §32's summary/detail DTO split.

---

## 32. Execution Debug API

`GetWorkflowExecution` (4E §13) is explicitly a **debug view**. 6I classifies it precisely:

| Aspect | Decision |
|---|---|
| Audience | Tenant-facing (not admin-only) — this is the same tenant that owns the Workflow and the call; the debug data belongs to them |
| Permission | `workflow:read` |
| API key eligible? | **No** for the detail endpoint (`GET /workflow-executions/{id}`) — even though `workflow:read` is otherwise API-key-eligible for list/get-workflow/get-version reads, the *execution* detail view can surface `slots`/`tool_results`/model output containing phone numbers, names, CRM data, and knowledge snippets (§45). Per 6B's own API-key-restriction posture (never assume a key may access everything merely because it holds a matching permission string) and the governing task's explicit instruction, `GET /workflow-executions/{id}` requires a **user session token**, not an API key. `GET /workflow-executions` (list, summary-only, §32.2) **is** API-key-eligible, since the summary DTO carries no slot/tool-output content. |
| Restricted during `ACTIVE` calls? | No additional restriction beyond the checkpoint-lag disclosure (§28) — an `ACTIVE` execution's debug view is simply stale-by-up-to-one-Turn, not blocked |
| Redaction | See §32.3 |

### 32.1 `WorkflowExecutionSummaryDTO` (list endpoint)

```json
{ "execution_id": "...", "workflow_version_id": "...", "session_ref": "...",
  "status": "ACTIVE", "current_node_id": "...", "started_at": "...", "completed_at": null }
```

No `slots`, no `node_execution_history`, no `turn_count_at_node` — bounded, safe for high-volume listing.

### 32.2 `WorkflowExecutionDetailDTO` (single-resource debug endpoint)

Everything in the summary, plus `slots` (redacted, §32.3), `node_execution_history` (capped at the most recent 100 entries with `has_more`/link to a paginated sub-resource if more exist — never the unbounded full list inlined, per 6A §10.2's 20-item anti-embedding rule extended here to 100 given the debug-specific nature of this endpoint), `turn_count_at_node`.

### 32.3 Redaction Rules

| Field class | Rule |
|---|---|
| `slots` values matching a known PII shape (phone/email patterns) | Masked to last-4/last-2 unless the caller holds a stronger, explicitly-audited "reveal PII" capability — no such capability is defined in this document, so **masking is unconditional** for `GET /workflow-executions/{id}` as designed here |
| Tool call arguments/results | Same masking; additionally, any field name matching `*_secret`/`*_token`/`*_credential`/`authorization`/`api_key` is **never** included at all, structurally (Pydantic response model allow-list, 6A §10.2) — not masked, absent |
| Model output text (LLM node `SPEAK` directives) | Not redacted by default (it is the agent's own spoken content, not raw system prompt/credentials) — but hidden system prompts (`PromptVersion.content`) are **never** included in this DTO at all; only the rendered *output*, never the template |
| `node_execution_history[].directive.payload` for `TRANSFER` | Phone number masked to last-4 digits |

Nothing in `WorkflowExecutionDetailDTO` ever includes a raw `credential_ref`, `signing_secret_ref`, or authorization header value — these are structurally absent per 6A §10.2's response-model allow-list mechanism, not merely documented as "don't include them."

---

## 33. Execution List Filters — Index-Driven Only

Checked against `041_5G.sql`'s actual indexes:

| Filter | Backing index | Exposed? |
|---|---|---|
| `status` | `idx_we_org_active (organization_id, status) WHERE status='ACTIVE'` | Yes — but only `status=ACTIVE` is index-optimal; `status=COMPLETED`/`FAILED` falls back to the BRIN index below (acceptable for a bounded historical range query, not for an unbounded full scan) |
| `session_ref` | `idx_we_session_ref (session_ref, organization_id)` | Yes |
| `workflow_version_id` | `idx_we_version (organization_id, workflow_version_id, started_at DESC)` | Yes |
| `started_at` range | `idx_we_brin (organization_id, started_at)` — BRIN, partition-pruning-friendly | Yes, **required** alongside any other filter for non-`ACTIVE` queries, to bound the partition scan — the API rejects (`422`) a `status`-only filter for a terminal status with no `started_at` range on a tenant with many partitions, per 6A §13's "no unindexed sort/filter forcing a sequential scan" rule |

No arbitrary JSONB `slots.*` filter is exposed — no index supports it (5G §10.3 lists no GIN index on `slots`), and 6A §15 forbids exposing an unindexed filter regardless of client demand.

**Pagination:** cursor, never `OFFSET` (6A §14, mandatory for this exact class of partitioned, high-volume table — matches `call_sessions`/`usage_events` precedent named in 6A §13/§14).

---

## 34. Workflow Definition List Filters

Checked against `040_5G.sql`'s indexes: `uq_wfd_name (organization_id, name)` UNIQUE, `idx_wfd_org_status (organization_id, status)`. Exposed filters: `status` (index-backed), `name` (exact-match only, via the unique index — **no** prefix/fuzzy/full-text search is exposed, since no GIN/trigram index exists on `workflow_definitions.name`; a client wanting "search by partial name" gets `422 VALIDATION_ERROR` documented as unsupported, not a silent full-table `ILIKE` scan). Ordering defaults to `created_at DESC` per 6A §14.3.

---

## 35. RLS / Tenant Isolation — SECURITY DEFINER Review

Every Workflow/Prompt table has `ENABLE + FORCE ROW LEVEL SECURITY` with the standard `organization.current_tenant_id()` policy (5G §12, verified in `040`/`041`/`042`/`045_5G.sql`). Because `fn_workflow_publish()`, `fn_start_workflow_execution()`, and `fn_prompt_set_active()` are all `SECURITY DEFINER` (bypassing RLS by design, owner-privilege execution), **each was individually checked for an explicit, in-function tenant/ownership check** — RLS provides zero protection inside a `SECURITY DEFINER` body:

| Function | Cross-tenant check | Cross-aggregate ownership check | Verdict |
|---|---|---|---|
| `fn_workflow_publish(workflow_id, new_version_id, org_id)` | `WHERE id=p_workflow_id AND organization_id=p_organization_id` on both the version-ownership `EXISTS` and the definition-status `EXISTS` | `workflow_definition_id = p_workflow_id` on the version — a version from a *different* Workflow cannot be published onto this one | ✅ Safe |
| `fn_start_workflow_execution(org_id, version_id, session_ref, started_at)` | `IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN RAISE` — explicitly cross-checks the caller-supplied argument against the session's actual tenant context, not merely trusting the argument | `workflow_versions WHERE id=p_workflow_version_id AND organization_id=p_organization_id` | ✅ Safe |
| `fn_prompt_set_active(prompt_id, version_number, environment, org_id)` | `WHERE prompt_template_id=p_prompt_id AND organization_id=p_organization_id` on the version-existence check | Same clause enforces the version belongs to the named prompt | ✅ Safe |

**Adversarial probes attempted (§59), all closed:**

| Probe | Result |
|---|---|
| Tenant A publishes Tenant B's workflow (`p_workflow_id` from B, `p_organization_id`=A) | `fn_workflow_publish`'s definition-ownership `EXISTS` fails (no row matches `id=B's workflow AND organization_id=A`) → exception |
| A `WorkflowVersion` from Workflow X published under Workflow Y (same tenant, different workflow) | `workflow_definition_id = p_workflow_id` check fails → exception |
| `fn_start_workflow_execution` called with a caller-forged `p_organization_id` while the actual session is a different tenant | Explicit `organization.current_tenant_id()` cross-check fails → exception, closing the exact "SECURITY DEFINER trusts caller argument" hazard the governing task names |
| `ARCHIVED` workflow republished | `status != 'ARCHIVED'` precondition in `fn_workflow_publish` fails → exception (INV-WF-02) |

---

## 36. Publish Concurrency — Adversarial Review, Resolved

6A §35 (frozen) already classifies **"Publish Workflow + WorkflowVersion"** as a mandatory same-transaction-atomicity operation. This is the binding requirement 6I's `PublishWorkflow` application-service implementation must satisfy — the two SQL statements shown in 5G's QP-03 (INSERT `workflow_versions`, then `SELECT fn_workflow_publish(...)`) are **one database transaction**, not two round trips. 6I additionally specifies the one implementation detail 5G/4E leave unstated: **how the next `version_number` is computed without a race.**

### 36.1 Required Transaction Shape (this document's contribution, not a schema change)

```sql
BEGIN;
  SELECT id, draft_graph, status, published_version_id
    FROM workflow.workflow_definitions
    WHERE id = $workflow_id AND organization_id = $org_id
    FOR UPDATE;                                        -- serializes concurrent publishers on THIS workflow row
  -- reject here if status = 'ARCHIVED' (defense-in-depth; fn_workflow_publish rejects too)
  SELECT COALESCE(MAX(version_number), 0) + 1
    FROM workflow.workflow_versions
    WHERE workflow_definition_id = $workflow_id;        -- safe: the FOR UPDATE above already serializes this
  INSERT INTO workflow.workflow_versions (..., version_number, graph_json) VALUES (..., $next, $draft_graph_read_above);
  SELECT workflow.fn_workflow_publish($workflow_id, $new_version_id, $org_id);   -- raises on ARCHIVED/ownership mismatch
COMMIT;                                                  -- or ROLLBACK on any exception above, discarding the INSERT too
```

The `SELECT ... FOR UPDATE` on `workflow_definitions` is the serialization point — it is not new schema, it is a transaction-discipline requirement on the application service, exactly the kind of thing 6A §17.3 already says the API layer is responsible for getting right on top of Phase 5's guarded functions.

### 36.2 Race Resolution

| Race | Outcome under the required transaction shape |
|---|---|
| **A — two users publish the same draft concurrently** | Second `FOR UPDATE` blocks until the first transaction commits or rolls back. The second then re-reads `draft_graph`/`published_version_id` fresh (not the values it read before blocking) and computes its own `next` `version_number` from the now-updated `MAX`. No `UNIQUE (workflow_definition_id, version_number)` collision is possible — the row lock, not the unique constraint, is the actual defense; the constraint is the backstop if some future code path skips the lock. |
| **B — publish racing `UpdateDraftGraph`** | `UpdateDraftGraph`'s own `UPDATE workflow_definitions SET draft_graph=... WHERE id=...` (5G QP-02) takes an ordinary row-level write lock on the same row a concurrent publish's `FOR UPDATE` already holds — whichever transaction started first blocks the other until commit. The publish transaction's snapshot of `draft_graph` (read inside its own `FOR UPDATE`) is therefore always either fully-before or fully-after any concurrent draft edit — never a torn read. |
| **C — publish racing `ArchiveWorkflow`** | Same row lock serializes the two. If Archive commits first, the publish transaction's own `fn_workflow_publish` call sees `status='ARCHIVED'` and raises — and because the `INSERT INTO workflow_versions` happened **inside the same transaction**, the `RAISE EXCEPTION` rolls back that INSERT too. **No orphan `WorkflowVersion` is created.** |
| **D — publish fails after the `workflow_versions` INSERT but before `fn_workflow_publish()` returns** | Same answer as C — single transaction means any failure after the INSERT (including an unrelated connection drop) rolls back the whole transaction, including the INSERT. An orphaned, never-published, immutable `WorkflowVersion` **cannot** exist under this transaction shape. It **could** exist under the two-round-trip interpretation of 5G's bare QP-03 SQL — which is exactly why 6A §35's atomicity requirement is binding and non-optional here, not a nice-to-have. |

**Verdict:** publish semantics are safe **only if** the application service honors 6A §35's mandatory single-transaction requirement and includes the `FOR UPDATE` lock this section adds. Both are disclosed here as binding implementation requirements on the (not-yet-written) `WorkflowApplicationService.publish_workflow()` — 6A §35 already made the transaction-boundary requirement binding; §36.1's lock is 6I's own necessary addition to make the version-number computation race-free, since no source before this document specified it.

---

## 37. Checkpoint Concurrency — Stale-Write Race — RESOLVED (§63)

> **Status update (2026-08-29, Phase 6I Blocker Remediation pass):** §37.1's race and §37.2's originally-disclosed residual recovery-ordering risk are now **fully closed at the PostgreSQL level** by migration `100_5G1.sql`'s `workflow_executions.checkpoint_seq` column plus the guarded `fn_checkpoint_workflow_execution()` CAS function and a hardened `prevent_execution_mutation()` trigger that rejects `checkpoint_seq` moving backward unconditionally — live-proven even against the `postgres` superuser bypassing every grant, and against a genuine two-connection race where the older Turn's checkpoint is deliberately delayed past the newer Turn's commit. See §63 for the live evidence. §37.1/§37.2 below are retained verbatim as the original problem analysis; they are no longer the current state of the system.

### 37.1 The Race (as originally found — see status update above for resolution)

Turn N's checkpoint is delayed (slow Celery worker); Turn N+1's checkpoint commits first; Turn N's delayed checkpoint then commits **after**. Under a naive `UPDATE ... SET current_node_id=$x, slots=$y WHERE id=$execution_id AND status='ACTIVE'` (5G QP-06), **the `ACTIVE` status predicate alone does not prevent this** — both checkpoints target the same row while it remains `ACTIVE`, and whichever commits *last* wins, regardless of which Turn it actually represents. Turn N's stale `current_node_id`/`slots`/`turn_count_at_node`/`history` could silently overwrite Turn N+1's newer state in PostgreSQL.

### 37.2 Resolution

No monotonic checkpoint-sequence column exists in the executed schema, and none is added here (out of scope for a documentation-only phase). **The actual safety net is architectural, not a DB column:** Redis is the sole state authority *during* the call (§28) — the checkpoint write is a **write-behind cache flush to a durable record for recovery/debug purposes**, never read back to drive the live call's next Turn while the call is still `ACTIVE`. A stale Postgres checkpoint overwriting a newer one therefore **cannot** move a *live* call backward — the live call keeps reading/writing Redis regardless of what Postgres shows.

**Where this *does* matter:** Redis-loss recovery (§29) reads the Postgres checkpoint as the recovery source of truth. If checkpoints can commit out of order, recovery could resume from Turn N's state even though Turn N+1 already happened live (and was lost with Redis) — the call would appear to "rewind" by one Turn on recovery. **This is a genuine, disclosed residual risk**, not resolved by architecture alone: the checkpoint write path must serialize per-execution (e.g., a single Celery task queue key per `execution_id`, guaranteeing FIFO delivery for that execution's checkpoints) to prevent out-of-order commits reaching Postgres in the first place. This ordering guarantee is a **worker/queue-configuration requirement**, disclosed here as mandatory for the implementation, not a claim this document can verify was actually built (Celery task ordering per routing key is a standard, achievable pattern, but no source in Phase 3/4/5 documents it for this specific queue) — flagged in §54 as `NON-BLOCKING` (the live-call correctness is protected by Redis regardless; only the *debug/recovery* path is exposed to this ordering hazard) but real.

**Verdict:** checkpointing is safe for live-call correctness (Redis is authoritative, never overwritten by a stale Postgres write) but is **not proven safe for post-Redis-loss recovery** unless per-execution checkpoint ordering is guaranteed at the queue layer — this is stated as a requirement, not claimed as already resolved.

---

## 38. Admin Direct-DML Bypass Review — RESOLVED (§63)

> **Status update (2026-08-29, Phase 6I Blocker Remediation pass):** every finding in this section is now **RESOLVED** by migration `100_5G1.sql` — `app_platform_admin` reduced to `SELECT`-only on `workflow_definitions`, `workflow_versions`, `workflow_executions` (parent and every partition), and `node_execution_claims`; `prompt_versions` given the identical treatment; both immutability triggers hardened to guard identity columns. This was previously classified `NON-BLOCKING` because the actor is a trusted, non-tenant-reachable role — it is now closed outright rather than left as an accepted risk. See §63 for the live evidence (all nine previously-exploitable vectors now return `permission denied`).

Following the same least-privilege analysis `076_5K1.sql` and `099_5C1.sql` already applied elsewhere in this platform, 6I performed a fresh review of `app_platform_admin`'s actual grants on the three Workflow tables (per `046_5G.sql`'s blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO app_platform_admin`, as narrowed only for `workflow_executions` INSERT by `076_5K1.sql`):

| Question | Answer | Evidence |
|---|---|---|
| Can direct admin UPDATE change an ACTIVE execution's cursor? | Yes, structurally possible (`UPDATE` grant retained) — but `trg_we_immutable` blocks it only for `workflow_version_id` and terminal-status transitions; a plain `current_node_id`/`slots` field UPDATE on an `ACTIVE` row is **not** blocked by any trigger. This mirrors ordinary application-layer checkpoint writes (§37) and is not, by itself, a new hazard beyond what any runtime role can already do — `app_platform_admin` is not more dangerous here than `app_worker`. | `041_5G.sql` trigger body |
| Can direct admin DELETE remove an ACTIVE execution? | Yes — `DELETE` is granted, and no trigger blocks `DELETE` (only `BEFORE UPDATE` triggers exist). A destructive admin `DELETE FROM workflow_executions WHERE id=...` would silently remove the durable record of an in-flight call's Workflow state with zero guard. | `046_5G.sql` grant; absence of a `BEFORE DELETE` guard anywhere in 039–046 |
| Can direct admin INSERT bypass `fn_start_workflow_execution()`? | **No** — `076_5K1.sql` specifically re-revoked `INSERT` from `app_platform_admin` on `workflow_executions` (and every existing partition), closing exactly this gap. Already fixed. | `076_5K1.sql` |
| Can direct admin UPDATE mutate `workflow_definitions.status`/`published_version_id` bypassing `fn_workflow_publish()`'s guards? | **Yes, and this is a real finding.** `app_platform_admin` holds an ordinary `UPDATE` grant on `workflow_definitions` (never revoked, unlike the `workflow_executions` INSERT case). A direct `UPDATE workflow.workflow_definitions SET status='PUBLISHED', published_version_id=<any UUID>' WHERE id=$id` bypasses `fn_workflow_publish()`'s ownership check (version-belongs-to-this-workflow, tenant match) entirely — and since `app_platform_admin` is `BYPASSRLS`, it can read/reference a `WorkflowVersion` belonging to a **different tenant or a different workflow** and point `published_version_id` at it directly, no trigger or constraint stops it. | `040_5G.sql` grant; no `BEFORE UPDATE` guard on `workflow_definitions` analogous to the version/execution immutability triggers |
| Can direct admin DELETE destroy immutable historical `WorkflowVersion`s? | **Yes.** `046_5G.sql` grants `DELETE` on `workflow_versions` to `app_platform_admin` without qualification — `REVOKE UPDATE, DELETE ... FROM app_api, app_worker` (`040_5G.sql`) never touches `app_platform_admin`. An admin `DELETE FROM workflow.workflow_versions WHERE id=...` permanently destroys an immutable, potentially still-execution-pinned historical artifact, with **no** trigger preventing it (the existing `trg_wv_immutable` is `BEFORE UPDATE` only, never `BEFORE DELETE`). | `046_5G.sql`; `039_5G.sql` trigger scope |
| Can a direct admin UPDATE the identity columns (`workflow_definition_id`, `organization_id`) of an existing `WorkflowVersion` row, reassigning it to a different workflow/tenant? | **Yes.** `trg_wv_immutable` (039_5G.sql) checks only `graph_json`, `version_number`, `published_by`, `published_at` for change — it does **not** guard `workflow_definition_id` or `organization_id`. This is the exact class of gap the *corrected* `prevent_execution_mutation()` trigger (039_5G.sql, per §3's discrepancy table) was specifically hardened to close for `workflow_executions` (adding `session_ref`/`organization_id` immutability) — the equivalent hardening was never applied to `prevent_wf_version_mutation()` or `prevent_pv_mutation()` (prompt_versions has the identical gap on `prompt_template_id`/`organization_id`). | `039_5G.sql`, both trigger bodies, read side-by-side |

### 38.1 Classification and Minimum Remediation

**Findings 4, 5, and 6 above are a genuine, disclosed production-safety gap**, structurally identical in kind to the two defects `076_5K1.sql` and `099_5C1.sql` were each written specifically to close elsewhere in this platform — this is not a novel category of concern for this codebase, it is the same category recurring in a schema those two migrations never touched.

**Minimum controlled remediation (sketch, not implemented here):**

```sql
-- (a) Revoke the unqualified admin bypass, mirroring 076_5K1.sql's own precedent exactly:
REVOKE UPDATE, DELETE ON workflow.workflow_definitions FROM app_platform_admin;  -- force all definition
REVOKE DELETE ON workflow.workflow_versions FROM app_platform_admin;             -- and version mutation
REVOKE DELETE ON prompt.prompt_versions FROM app_platform_admin;                 -- through guarded paths
-- (b) Harden the two existing triggers to also guard identity columns, mirroring the
--     already-corrected workflow_executions trigger's own pattern:
--     ADD workflow_definition_id / organization_id checks to prevent_wf_version_mutation()
--     ADD prompt_template_id / organization_id checks to prevent_pv_mutation()
-- (c) If a genuine emergency admin need for definition/version correction exists, expose it
--     only through a new, narrowly-scoped SECURITY DEFINER function (never a raw grant),
--     exactly as 099_5C1.sql's fn_reconcile_dispatch_by_operator() does for its own domain.
```

**Classified `NON-BLOCKING` for V1**, not `BLOCKER`: `app_platform_admin` is a trusted, break-glass-style operational role (5B), not tenant-reachable, and no observed frozen document treats this class of admin bypass as a hard V1 gate for the other bounded contexts it also affects (5J/6E's own admin-DML reviews carry equivalent findings forward as documentation, not migrations, until a dedicated hardening pass — matching `076`/`099`'s own pattern of being separate, later, narrowly-scoped corrective migrations rather than blocking the original phase). Recorded here, honestly, as a real gap — not dismissed, not treated as a launch blocker either. See §54.

---

## 39. Execution Completion / Failure Immutability

`trg_we_immutable` (§3's corrected version) rejects **any** UPDATE once `status IN ('COMPLETED','FAILED')` — not just a `status`-field change, the entire row becomes unconditionally immutable (INV-WF-04). `current_node_id`, `slots`, `node_execution_history`, `completed_at`, `workflow_version_id`, `session_ref` are all frozen at the moment of completion. No runtime path can "reopen" a terminal execution — 4E defines no such command (`RetryExecution` does not exist in the catalogue), and none is invented here. A workflow that needs to "retry" after failure does so by **starting a new `WorkflowExecution`** for a new call attempt, never by resurrecting the old one.

---

## 40. Tool/Webhook Side-Effect Crash Matrix

| Failure | Required behavior | Currently guaranteed? |
|---|---|---|
| Crash before node begins | Safe retry | ✅ (pure re-evaluation, DDR-4E-002) |
| Crash after pure node evaluation (DECISION/CONDITION/BRANCH/KNOWLEDGE_SEARCH) | Safe retry | ✅ |
| Crash before tool network request | Safe retry | ✅ (no side effect fired yet) |
| Tool succeeds, response lost | No blind duplicate if tool may be non-idempotent | ❌ — §30 BLOCKER, no durable claim exists |
| Tool succeeds, checkpoint lost | Side-effect reconciliation/idempotency required | ❌ — §30 BLOCKER |
| Provider/webhook timeout | Ambiguous unless contract proves no side effect | ❌ for WEBHOOK/API_CALL (execution-blocked anyway, §23); tool timeout behavior inherits whatever 6E's `ToolExecution.TIMED_OUT`/retry contract already provides (not redesigned here) |
| Redis lost after side effect | No restart-from-entry duplication | ✅ never restarts from entry (§29) — but ❌ may re-fire the *specific* side-effecting node, same §30 gap |
| Duplicate Celery task (checkpoint redelivery) | No duplicate external side effect | ✅ for the checkpoint write itself (idempotent field-set UPDATE); N/A for node re-execution, which is §30's concern, not the checkpoint's |
| Stale Postgres checkpoint | Must not move execution backward | ✅ for the live call (Redis-authoritative, §37); ⚠️ disclosed residual risk for post-Redis-loss recovery ordering (§37.2) |
| Workflow republished mid-call | Execution stays pinned | ✅ (INV-WF-03, DB-trigger-enforced, unconditional) |

No row in this matrix is described as "exactly once" — per the governing task's explicit instruction, that language is reserved for a mechanism this platform actually has (none of the five side-effecting node types currently qualifies, per §30/§23).

---

## 41. Workflow Realtime Progress

Per 6A ADR-6A-05/§27, a non-audio realtime channel for Workflow execution progress is defined using 6A's generic JSON envelope — never Socket.IO, never audio, never authoritative over PostgreSQL/Redis (§28 remains the state authority; this channel is a **push notification of state that already exists**, not a second source of truth).

```text
WS /ws/v1/workflow-executions/{execution_id}
```

| Aspect | Decision |
|---|---|
| Auth | JWT via query param/subprotocol at connect (6A §27.2), tenant resolved identically to REST |
| Authorization | `workflow:read`, re-verified on subscribe per 6A §27.4 — a permission revoked mid-connection blocks the *next* resubscribe, does not force-close an existing subscription (6A's own documented, inherited trade-off) |
| Event names | `workflow_execution.node_entered`, `workflow_execution.node_exited`, `workflow_execution.slot_updated`, `workflow_execution.completed`, `workflow_execution.failed` — all wrapped in 6A §27.3's generic envelope (`event_id`, `event_type`, `version`, `timestamp`, `organization_id`, `resource_id`, `sequence`, `payload`) |
| Snapshot vs. delta | On subscribe, the server sends one snapshot event (current `status`/`current_node_id`) before streaming deltas — consistent with needing a starting point for `sequence` gap detection (6A §27.3) |
| Backpressure / rate limits | Per-connection 5-concurrent cap (6A §20/§27.2, platform-wide, not a new number); high-frequency `node_entered`/`node_exited` events on a pathological rapid-cycling graph are throttled/coalesced server-side rather than flooding the socket — a specific coalescing window is an implementation detail, not fixed here |
| Reconnect | Client-side exponential backoff (6A §27.2); **non-voice channels MAY support resume-from-sequence** (6A explicitly allows this for non-audio channels) — the server tracks the last N sequence numbers per execution to support a bounded resume window |
| Authoritative? | No — a dropped WS connection never affects the underlying `WorkflowExecution`; the client simply reconnects and re-syncs via the snapshot event plus a `GET /workflow-executions/{id}` catch-up read if needed |

Audio is never carried on this channel — it exists purely for progress/observability UX (visual builder "watch a test call run" style features, §53), never for call control.

---

## 42. Audit Events

### 42.1 Governed Vocabulary — What Exists, What's Missing

5J §14.3 already governs `WORKFLOW_PUBLISHED`. It does **not** govern `WORKFLOW_CREATED`, `WORKFLOW_DRAFT_UPDATED`, or `WORKFLOW_ARCHIVED` — checked directly against the full governed list, all four categories (base, †, ‡, ¶, §) inspected, none contains them.

### 42.2 6I's Documentation-Only Amendment (following the established †/‡/¶/§ pattern exactly)

**Decision (ADR-6I-06):** three new governed `action_kind` values are added, following the identical governance pattern 6D/6G/5L already used — a **pure vocabulary amendment**, no SQL migration, since `chk_ae_action_kind` remains `CHECK (length(action_kind) BETWEEN 1 AND 200)`, not an enum:

- `WORKFLOW_CREATED` — mirrors `AGENT_CREATED`'s existing resource+verb shape.
- `WORKFLOW_DRAFT_UPDATED` — mirrors `AGENT_CONFIG_UPDATED`'s existing "qualify `_UPDATED` with the specific mutable sub-surface" convention (the draft graph, not the whole definition).
- `WORKFLOW_ARCHIVED` — mirrors `KNOWLEDGE_BASE_ARCHIVED`/`TEAM_ARCHIVED`'s existing shape exactly.

`WORKFLOW_PUBLISHED` is reused as-is (already governed) for `POST /workflows/{id}/publish`. `POST /workflows/{id}/validate` is **not** audited — it is a non-mutating, read-derived operation, consistent with the platform's existing convention of only auditing state-changing endpoints (6A §22).

### 42.3 Audit Synchrony — New Named Exception (following the 6D ‡ / 6E precedent)

**Decision (ADR-6I-07):** the four Workflow-definition-level state-changing endpoints (`create`, `draft` replace, `publish`, `archive`) are added to the **synchronous** audit exception list, alongside Agent mutations, for the identical reason 6D/6E's own `‡` amendment already gives: (1) 6A §22 requires unconditional durable audit coverage for state-changing commands; (2) none of these four operations sit on the realtime voice-turn hot path (they are ordinary Tier A/B REST mutations, editing/publishing a definition, never touched during a live call's per-turn loop). This does not change the async default for any other domain's "Configuration... lifecycle" category — it is as narrow as the precedent it follows.

---

## 43. Domain Events — Durable vs. Telemetry

4E §11.2's full Workflow event catalogue is preserved. 6I classifies each by volume/purpose, per the governing task's explicit instruction not to flood the transactional outbox with high-frequency per-turn events:

| Event | Classification | Mechanism |
|---|---|---|
| `workflow.created` | Durable business event | `audit.domain_event_outbox` INSERT, same transaction as the definition create |
| `workflow.draft_updated` | Durable business event | Same |
| `workflow.published` | Durable business event | Same |
| `workflow.archived` | Durable business event | Same |
| `workflow.execution.started` | Durable business event | Outbox INSERT in the same transaction as `fn_start_workflow_execution()`'s caller (application-layer, immediately after the function returns, still inside the request's own transaction where practical) |
| `workflow.execution.completed` | Durable business event — explicitly named by 4E §25 as required by Billing (LLM token usage) and Analytics | Outbox INSERT, synchronous with `CompleteExecution` |
| `workflow.execution.failed` | Durable business event | Outbox INSERT, synchronous with `FailExecution` |
| `workflow.node.entered` / `workflow.node.exited` / `workflow.slot_updated` | **Operational/realtime telemetry — never the transactional outbox** | Delivered only via the WS channel (§41) and/or a high-frequency analytics stream outside `audit.domain_event_outbox`; 4E §11.2 itself already annotates `workflow.node_entered` as *"internal, high frequency — not published to external bus"* — 6I extends the identical treatment to `node_exited`/`slot_updated` for the same reason |

**Rationale, restated for the specific hazard named by the governing task:** a call with 30 Turns × 2–3 node traversals each would write 60–90 outbox rows per call if node-level events were transactional — at platform scale (the SRS's own "tens of thousands of concurrent calls" framing) this is exactly the write-amplification 4E already flagged as unacceptable for `node_entered`, and 6I applies the same reasoning symmetrically to its two undocumented siblings rather than treating the omission as silence-equals-permission.

---

## 44. Voice Latency Budget for Workflow Node Evaluation

Reusing 6A §11's Tier E per-stage breakdown, never inventing a parallel budget:

| Workflow-internal step | Budget (informed by 6A §11 Tier E) |
|---|---|
| Pure node evaluation (DECISION/CONDITION/BRANCH/GREETING/DELAY dispatch) | <5 ms — in-process, no I/O |
| Expression evaluation (§16) | <5 ms, hard-bounded (§16.4) |
| Redis state load/save (per Turn) | Falls inside 6A's existing Redis command budget (2ms connect / 2s command ceiling, §21) — no new number |
| `KNOWLEDGE_SEARCH` node | Inherits 6F's own stated sub-budget exactly: "Tool execution: 150ms p50 / 400ms p95" (6F §21, itself derived from 6A §11 Tier E) — not a new number |
| `TOOL_CALL` node | Same Tier E tool-execution sub-budget (150ms p50 / 400ms p95) |
| `LLM` node | Inherits the Tier E LLM time-to-first-token budget (250ms p50 / 500ms p95) — Workflow adds no overhead beyond its own <5ms dispatch cost |
| Checkpoint scheduling (enqueue only, not completion) | Fire-and-forget, effectively 0ms added to the Turn — the actual checkpoint write happens fully outside the Turn's response path (DDR-4E-002, §28) |

**Binding rule, restated:** heavy Workflow execution history is never synchronously persisted to PostgreSQL before a spoken response — 3D/4E's Redis-hot/Postgres-checkpoint split is preserved exactly as designed; nothing in this document adds a synchronous DB write to the per-turn hot path.

---

## 45. GDPR / PII in Workflow Execution

5G §22/ADR-5G-009 (best-effort, asynchronous, `contact.gdpr_erased`-triggered) is preserved unchanged. 6I confirms the debug API (§32) never defeats this: `slots`/`node_execution_history` cleared by the async GDPR handler are reflected in `GET /workflow-executions/{id}` on the **next** read after the handler completes (no separate cache holds a pre-erasure copy that could leak stale PII — the debug endpoint reads directly from the current row, and Redis's own hot-tier state for a since-completed execution has already expired per its TTL, §28). An **`ACTIVE`** execution's Redis hot-tier `slots` are **not** touched by the async GDPR handler (5G §22 scopes erasure to `workflow_executions` rows, i.e., the durable/checkpointed state) — this is a disclosed, inherited limitation: GDPR erasure against a still-live call's in-memory slots is best-effort and lags until the next checkpoint/completion, exactly as 5G's own `ADR-5G-009` already frames it ("does not need to be real-time; reasonable completion SLA (24h) is sufficient"). 6I adds nothing beyond faithfully surfacing this existing posture through the debug API rather than contradicting it.

---

## 46. Secret Handling in Graph JSON

No node config field in §11's discriminated union accepts a raw secret. `ToolCallNodeConfig.argument_template`, `WebhookNodeConfig.payload_template`, and `ApiCallNodeConfig.headers` are all validated to **reject** any value matching a credential-shaped pattern (bearer token, API-key-looking string, `secret_manager://`-shaped reference embedded as a literal rather than resolved) — the platform's existing convention (5I ADR-5I-002, `credential_ref` opaque references only) is inherited: a node that needs a credential must reference it via a logical `credential_ref` resolved by the owning integration/secret infrastructure (6J, for `WEBHOOK`/`API_CALL` — hence §23's execution-blocked status; 6E's `ToolDefinition` credential model, for `TOOL_CALL`) at **execution** time, never store the resolved secret value inside `draft_graph`/`graph_json` itself. Since `graph_json` is immutable forever once published (INV-WF-01), a secret accidentally frozen into it — like 6E's own documented warning about `AgentVersion.snapshot_json` — could never be redacted, only rendered permanently unreadable by destroying the whole version (unsupported by any command). Publish-time validation (§14) rejects any node config containing a detected raw-secret-shaped literal, closing this off before it can ever become permanent.

---

## 47. Error Catalogue

| Code | HTTP | When |
|---|---:|---|
| `WORKFLOW_NOT_FOUND` | 404 | Missing or cross-tenant workflow ID (never distinguished, 6A §7.4) |
| `WORKFLOW_ARCHIVED` | 409 | Mutation attempted (draft update, publish) against an `ARCHIVED` workflow |
| `WORKFLOW_NOT_EDITABLE` | 409 | Reserved for a future stronger-than-`ARCHIVED` lock state — currently unused (DRAFT/PUBLISHED are both editable per 4E §7.2); documented for completeness, not currently reachable |
| `WORKFLOW_GRAPH_INVALID` | 422 | Any of the ten invariants (§10) or a size limit (§13) violated |
| `WORKFLOW_ENTRY_NODE_INVALID` | 422 | Entry node missing/malformed |
| `WORKFLOW_EDGE_INVALID` | 422 | Dangling source/target |
| `WORKFLOW_UNREACHABLE_NODE` | 422 | Invariant 4 |
| `WORKFLOW_UNBOUNDED_CYCLE` | 422 | Invariant 5 (§12) |
| `WORKFLOW_NODE_CONFIG_INVALID` | 422 | Discriminated-union validation failure (§11) or malformed transfer target (§14) |
| `WORKFLOW_EXPRESSION_INVALID` | 422 | §16 |
| `WORKFLOW_VERSION_NOT_FOUND` | 404 | Missing/cross-tenant version ID |
| `WORKFLOW_VERSION_MISMATCH` | 409 | A version ID supplied that doesn't belong to the named workflow (mirrors `fn_workflow_publish`'s own internal check surfaced to the API caller only if ever exposed — not currently client-triggerable since publish never takes a client-supplied version ID) |
| `WORKFLOW_PUBLISH_CONFLICT` | 409 | `fn_workflow_publish` raised (archived, ownership mismatch) — surfaced generically, never leaking cross-tenant existence |
| `WORKFLOW_EXECUTION_NOT_FOUND` | 404 | Missing/cross-tenant execution ID |
| `WORKFLOW_EXECUTION_ALREADY_ACTIVE` | 409 | `fn_start_workflow_execution`'s "already ACTIVE" exception, surfaced to the internal caller (§17) — never client-reachable, since `StartExecution` isn't a public endpoint |
| `WORKFLOW_EXECUTION_TERMINAL` | 409 | Any internal attempt to mutate a `COMPLETED`/`FAILED` execution (§39) |
| `WORKFLOW_NODE_EXECUTION_FAILED` | — (internal directive, not an HTTP response) | Runtime node failure (§12, §22, §49) |
| `WORKFLOW_EXTERNAL_ACTION_AMBIGUOUS` | — (internal) | A side-effecting node's outcome could not be determined (§29, §40) — reserved terminology, currently unreachable pending §30's remediation, since no node type today has an `AMBIGUOUS`-capable executor |
| `WORKFLOW_REFERENCE_NOT_READY` | 422 | Publish-time dependency unresolved — unready KB, disallowed tool, execution-blocked WEBHOOK/API_CALL (§14, §23) |
| `IDEMPOTENCY_KEY_REUSE_MISMATCH` | 409 | §51 |
| `PRECONDITION_FAILED` | 412 | `If-Match` mismatch (§8.2) |

No synonym is invented where a 6A global code already fits (`VALIDATION_ERROR`, `AUTHORIZATION_DENIED`, `RATE_LIMIT_EXCEEDED`, `INTERNAL_ERROR` are reused, not restated above).

---

## 48. Authorization Matrix

| Endpoint | Permission | Session token | API key | Internal-only | Tenant ownership check |
|---|---|:---:|:---:|:---:|---|
| `POST /workflows` | `workflow:write` | ✅ | ✅ | — | N/A (create) |
| `GET /workflows` | `workflow:read` | ✅ | ✅ | — | RLS |
| `GET /workflows/{id}` | `workflow:read` | ✅ | ✅ | — | RLS + app-layer ownership (6A §22 IDOR defense) |
| `PATCH /workflows/{id}` | `workflow:write` | ✅ | ✅ | — | RLS |
| `PUT /workflows/{id}/draft` | `workflow:write` | ✅ | ✅ | — | RLS + `If-Match` |
| `POST /workflows/{id}/validate` | `workflow:write` | ✅ | ✅ | — | RLS |
| `POST /workflows/{id}/publish` | `workflow:publish` | ✅ | ✅ | — | RLS + `fn_workflow_publish` (§35) |
| `POST /workflows/{id}/archive` | `workflow:write` | ✅ | ✅ | — | RLS |
| `GET /workflows/{id}/versions` | `workflow:read` | ✅ | ✅ | — | RLS |
| `GET /workflows/{id}/versions/{vid}` | `workflow:read` | ✅ | ✅ | — | RLS |
| `GET /workflow-executions` | `workflow:read` | ✅ | ✅ | — | RLS, summary DTO only (§32.1) |
| `GET /workflow-executions/{id}` | `workflow:read` | ✅ | **❌** | — | RLS; **API key excluded** (§32, PII exposure) |
| `WS /ws/v1/workflow-executions/{id}` | `workflow:read` | ✅ | — (WS auth is JWT-only per 6A §27.2, no API-key WS flow exists platform-wide) | — | Re-verified on subscribe |
| `resolve_published_workflow_version`, `start_workflow_execution`, `evaluate_next_directive`, `checkpoint_*`, `complete_*`, `fail_*` (§7) | N/A — not HTTP-reachable | — | — | ✅ (Voice Orchestrator, in-process, internal service principal per 6A §23.4 when crossing a process boundary) | Enforced inside `fn_start_workflow_execution` (§17, §35) |

`app_platform_admin`/break-glass handling: identical to every other tenant-scoped route per 6B's own documented break-glass contract (`X-Break-Glass-Grant` header required) — no Workflow-specific admin override endpoint is introduced.

---

## 49. Invalid / Corrupted Published Graph — Runtime Defense

Even though `WorkflowVersion.graph_json` is immutable, a manually-corrupted row (direct DB intervention, or a future migration bug) must never become arbitrary execution:

| Condition | Behavior |
|---|---|
| Unknown `node_type` string in `graph_json` | `NodeExecutorRegistry.get()` finds no registered executor → execution fails safely (`WORKFLOW_NODE_EXECUTION_FAILED`, `reason=UNKNOWN_NODE_TYPE`), never an unhandled exception propagating out of the Voice worker |
| Missing target node (edge points to a `node_id` absent from `graph_json.nodes`) | Same — fails the execution deterministically rather than crashing the turn loop |
| Invalid TOOL_CALL/KB reference discovered only at runtime (never caught at publish because the reference was valid at publish time and later revoked) | Routed to `on_failure_edge` if present (TOOL_CALL) or empty-result `CONTINUE` (KNOWLEDGE_SEARCH, §21.3) — never a hard crash |
| Expression fails the runtime whitelist re-check (§16.3) | Fail-closed, `WORKFLOW_NODE_EXECUTION_FAILED` |
| Any other unhandled exception inside a `NodeExecutor` | Caught at the `WorkflowExecutionService.evaluate_node()` boundary, converted to `FailExecution`, never allowed to propagate into and crash the shared Voice worker process handling other tenants' concurrent calls |

---

## 50. API Idempotency

Per 6A §16, applied selectively:

| Endpoint | Idempotency-Key required? | Semantics |
|---|---|---|
| `POST /workflows` | Optional, recommended | Same key + same payload → replay the original create response; same key + different payload → `409 IDEMPOTENCY_KEY_REUSE_MISMATCH` |
| `POST /workflows/{id}/publish` | Optional, recommended | Same key + same draft fingerprint (derived from the `If-Match` ETag actually published, §51/§52) → replay the original `WorkflowVersionDTO`; same key + a draft that has since changed (different ETag) → `409 IDEMPOTENCY_KEY_REUSE_MISMATCH`. **Disclosed limitation:** this replay guarantee is only as strong as 6A's Redis-primary/DB-backstop idempotency store (ADR-6A-07) — there is **no dedicated DB-level uniqueness constraint** backing "publish idempotency" the way `call_jobs.idempotency_key` backs call dispatch; Redis is the sole guarantee here, not a backstop, since 5G has no idempotency column on `workflow_versions`. This is disclosed, not silently assumed to be as strong as 6A's stronger-precedent flows. |
| `POST /workflows/{id}/archive` | Optional | Same key replays the (already-terminal, side-effect-free-to-repeat) archive result — archiving an already-`ARCHIVED` workflow a second time with the same key is a natural no-op regardless, since `status='ARCHIVED'` is itself idempotent to re-apply |
| `PUT /workflows/{id}/draft` | Not required | Already protected by `If-Match` (§8.2) — a genuine duplicate submission with the same ETag either succeeds identically (same source state, same result) or is naturally rejected as a stale precondition on the second attempt (ETag changed after the first succeeded) |

---

## 51. ETag / Optimistic Concurrency

Per 6A §17.2/ADR-6A-08: `WorkflowDefinition`'s only available concurrency token is the weak `hash(id, updated_at)` ETag — **no dedicated `version_number` column exists on `workflow_definitions`**, and none is invented here (that would be a Phase 5 schema change, out of this document's authority). `If-Match` is required for `PATCH /workflows/{id}` and `PUT /workflows/{id}/draft` (§8.2). Publishing (§52) also requires it.

---

## 52. Publish Against Exact Draft

**Decision (ADR-6I-08):** `POST /workflows/{id}/publish` **requires `If-Match`** against the `WorkflowDefinition`'s current ETag, exactly addressing the named hazard (user A loads draft revision X, user B updates the draft to revision Y, user A clicks Publish without having seen Y). A mismatched `If-Match` returns `412 PRECONDITION_FAILED` — the publish never silently snapshots a draft revision the caller never saw. This is 6I's own explicit choice, since 5G's bare `PublishWorkflow` command (4E §12.2) carries no precondition token at all — 6I adds one, using 6A's existing ETag mechanism rather than inventing a new concept.

---

## 53. WorkflowVersion Retention

No delete command exists for `WorkflowVersion` in 4E's catalogue, and none is exposed here (§6.3). Retention implications, stated plainly: active/historical `WorkflowExecution`s reference `workflow_version_id` by logical UUID for their entire (permanent, 12-month-hot) lifetime — a hard-deleted version would orphan every execution debug view that ever ran it. Audit/debugging (§32) depends on the version graph remaining readable indefinitely. An `ARCHIVED` `WorkflowDefinition` retains **every** one of its historical `WorkflowVersion`s unchanged — archiving the definition never touches the versions table.

---

## 54. Dependencies / Deferred Items — Full Register

| # | Item | Classification | Notes |
|---|---|---|---|
| 1 | ADR-5G-010 — prompt-version pinning for deterministic replay | `DEFERRED` (Phase 9, per 5G/5L's own explicit carry-forward) | §27 — not required by any frozen SRS/DDD text, per 5L §G.34's direct confirmation |
| 2 | `workflow_executions` partition automation (`create_monthly_partitions()` maintenance job) | `NON-BLOCKING` | 5G §28 carry-forward, App/ops concern, no API-blocking impact |
| 3 | `started_at` required on every execution lookup for partition pruning | `NON-BLOCKING` — documented requirement on `WorkflowExecutionRepository` | §33 |
| 4 | `WorkflowTrigger` aggregate absence | `RESOLVED — confirmed absent by design` | §55 — no trigger endpoint is exposed, per 5G's own explicit statement that 4E defines none |
| 5 | `WEBHOOK`/`API_CALL` node execution — dependency on 6J | `EXECUTION-BLOCKED` | §23 — draft-acceptable, publish-blocked, until 6J supplies credential-binding + egress controls. Unaffected by the 2026-08-29 remediation — the durable claim mechanism these two node types would eventually use now exists (`workflow.node_execution_claims`), but SSRF/credential/egress controls remain 6J's separate, still-open dependency (6I §25/ADR-6I-04). |
| 6 | Side-effecting node (`TOOL_CALL`/`WEBHOOK`/`API_CALL`/`TRANSFER`/`HUMAN_TRANSFER`) crash-retry idempotency | **`RESOLVED` (2026-08-29)** | §30/§63 — `100_5G1.sql`'s `workflow.node_execution_claims` + five guarded functions, live-validated including a genuine concurrent-duplicate-claim race. `TOOL_CALL`/`TRANSFER`/`HUMAN_TRANSFER` are implementation-ready; `WEBHOOK`/`API_CALL` remain gated by item 5 above regardless. |
| 7 | `app_platform_admin` direct-DML bypass of `fn_workflow_publish()`'s guards via raw UPDATE on `workflow_definitions`, and unguarded DELETE/identity-column mutation on `workflow_versions`/`prompt_versions` | **`RESOLVED` (2026-08-29)** | §38/§63 — `100_5G1.sql` reduced `app_platform_admin` to `SELECT`-only on all four affected tables and hardened both immutability triggers; live-proven closed for all nine originally-exploitable vectors. |
| 8 | Checkpoint-ordering guarantee for post-Redis-loss recovery | **`RESOLVED` (2026-08-29)** | §37/§63 — `checkpoint_seq` CAS + hardened trigger now make PostgreSQL itself reject any backward move, closing this at the DB level rather than depending on queue-ordering discipline. |
| 9 | `DEP-6E-03` (Agent `workflow_ref` existence validation) | `RESOLVED` — port supplied, not consumed by frozen 6E | §19 — the in-process query now exists; 6E's own frozen publish flow does not call it, a cross-phase carry-forward, not a 6I defect |
| 10 | Campaign-triggered-Workflow / Workflow-triggered-Campaign ACL | `EXECUTION-BLOCKED / CONTRACT-DEFINED` | §20 — no concrete tool binding exists in any frozen tool registry today |
| 11 | Publish idempotency-key replay strength | `NON-BLOCKING`, disclosed | §50 — Redis-only guarantee, no DB-level backstop uniqueness constraint exists for this specific flow, unlike `call_jobs`/`usage_events` |
| 12 | Billing dependency (`workflow.execution_completed` LLM token cost) | `NON-BLOCKING` | 6K not started; 4E §25 already names this as required Billing input — 6I's `workflow.execution.completed` domain event (§43) is the exact contract 6K will consume |
| 13 | Analytics/realtime telemetry dependency for node-level events | `NON-BLOCKING` | 6L not started; §43's telemetry classification is the contract 6L will consume when it exists |
| 14 | Admin debug/override dependency (viewing/force-completing a stuck execution) | `NON-BLOCKING` | 6M not started; no admin-specific Workflow endpoint is designed here beyond the standard break-glass header mechanism (§48) |

---

## 55. WorkflowTrigger — Confirmed Absent, Not Invented

5G §28 states plainly: *"Phase 4E does not define a WorkflowTrigger aggregate. Workflow execution is started by StartExecution from the Voice Orchestrator."* 6I preserves this exactly. No `POST /workflows/{id}/trigger`, no cron trigger, no event trigger, no campaign trigger, no webhook-triggered workflow is exposed anywhere in this document. Future trigger models belong to a future domain amendment (Phase 9+) or a 6J/Workflow extension — not fabricated here to fill a perceived product gap.

---

## 56. Strict Phase 5 Reconciliation

| Capability | DDD command/query | Physical support | API surface | Status |
|---|---|---|---|---|
| `CreateWorkflow` | 4E §12.2 | `040_5G.sql` (INSERT) | `POST /workflows` | IMPLEMENTATION-READY |
| `UpdateDraftGraph` | 4E §12.2 | `040_5G.sql` (`draft_graph` UPDATE) | `PUT /workflows/{id}/draft` | IMPLEMENTATION-READY |
| `ValidateGraph` | 4E §14.2 (`ValidateGraphUseCase`) | Application-layer only, no DB table needed | `POST /workflows/{id}/validate` | IMPLEMENTATION-READY |
| `PublishWorkflow` | 4E §12.2 | `039`/`040_5G.sql` (`fn_workflow_publish`) | `POST /workflows/{id}/publish` | IMPLEMENTATION-READY, **conditional** on the application service honoring 6A §35's single-transaction requirement + §36.1's row lock |
| `ArchiveWorkflow` | 4E §12.2 | `040_5G.sql` (`status` UPDATE, ordinary grant, no SECURITY DEFINER function exists) | `POST /workflows/{id}/archive` | IMPLEMENTATION-READY |
| `GetWorkflow` | 4E §13 | `040_5G.sql` | `GET /workflows/{id}` | IMPLEMENTATION-READY |
| `ListWorkflows` | 4E §13 | `040_5G.sql` indexes | `GET /workflows` | IMPLEMENTATION-READY |
| `GetWorkflowVersion` | 4E §13 | `040_5G.sql` | `GET /workflows/{id}/versions/{vid}` | IMPLEMENTATION-READY |
| `ListWorkflowVersions` | 4E §13 (implied) | `040_5G.sql` indexes | `GET /workflows/{id}/versions` | IMPLEMENTATION-READY |
| `StartExecution` | 4E §12.2 | `041_5G.sql` (`fn_start_workflow_execution`) | In-process only, §7/§18 | IMPLEMENTATION-READY, **conditional** on the application-layer "already-ACTIVE = benign replay" handling disclosed in §17.2 |
| `EvaluateNextDirective` | 4E §14.2 | Redis hot-tier (3D §6.3) + `graph_json` read | In-process only, §7/§18 | IMPLEMENTATION-READY |
| `AdvanceCursor` / `UpdateSlots` (checkpoint) | 4E §12.2 | `041_5G.sql` (per-turn UPDATE) | In-process only, §7 | IMPLEMENTATION-READY, **with the disclosed ordering caveat**, §37 |
| `CompleteExecution` | 4E §12.2 | `041_5G.sql` (`status` UPDATE, `trg_we_immutable`) | In-process only, §7 | IMPLEMENTATION-READY |
| `FailExecution` | 4E §12.2 | Same | In-process only, §7 | IMPLEMENTATION-READY |
| `GetWorkflowExecution` | 4E §13 | `041_5G.sql` | `GET /workflow-executions/{id}` | IMPLEMENTATION-READY, redacted (§32) |
| `ListWorkflowExecutions` | 4E §13 (implied) | `041_5G.sql` indexes | `GET /workflow-executions` | IMPLEMENTATION-READY |
| TOOL_CALL/WEBHOOK/API_CALL/TRANSFER/HUMAN_TRANSFER side-effect execution | 4E §5.1.4 | **No durable idempotency claim table exists** | Node config accepted; execution gated | **BLOCKER** for non-idempotent targets (§30); WEBHOOK/API_CALL additionally `EXECUTION-BLOCKED` (§23) |

No capability above is called `IMPLEMENTATION-READY` unconditionally where a genuine, disclosed gap exists — every conditional entry names its exact condition.

---

## 57. Concurrency Matrix — Full

| Race | Serialization mechanism | Loser behavior | Residual risk |
|---|---|---|---|
| Create same-name workflow concurrently | `uq_wfd_name (organization_id, name)` UNIQUE index | `409` (unique violation surfaced as `VALIDATION_ERROR`/`STATE_CONFLICT`) | None |
| Two users update same draft (`PUT .../draft`) | `If-Match` (§8.2) | `412 PRECONDITION_FAILED` on the stale writer | None — lost-update problem structurally closed by ETag |
| Update vs. publish | Row `FOR UPDATE` inside publish's transaction (§36.1) | Whichever started second blocks, then proceeds against fresh state | None, given the required transaction shape is honored |
| Publish vs. publish | Same row lock + `uq_wv_version_number` backstop | Second serializes behind the first, computes a fresh `next` version_number | None |
| Publish vs. archive | Same row lock | Whichever commits second either publishes onto a since-archived definition (rejected by `fn_workflow_publish`, whole transaction rolls back, §36.2 Race C) or archives a since-republished definition (succeeds — archiving is compatible with any status per §54's Archive semantics) | None — no orphan version possible |
| Archive vs. draft update — **corrected 2026-08-29 (§63)** | Ordinary row-level write lock (both are plain UPDATEs on the same row) PLUS, since `100_5G1.sql`, a `BEFORE UPDATE` `prevent_archived_definition_mutation()` trigger | **Not** "whichever commits second wins" (that prior wording was a genuine self-contradiction against ARCHIVED's terminal-immutability claim, corrected in this pass). If the draft UPDATE's own `WHERE status IN ('DRAFT','PUBLISHED')` predicate is evaluated first and Archive commits first, the draft UPDATE affects zero rows once it proceeds (live-proven, two genuine connections). If a draft UPDATE somehow reached the row anyway (a hypothetical future code path with no such predicate), the trigger rejects it unconditionally regardless of role/grant — live-proven even against the `postgres` superuser. Archive committing second (after a draft update) is unaffected — it succeeds normally. | None — closed at the DB level, not merely by API-layer WHERE-clause discipline |
| Archive vs. new execution start | `resolve_published_workflow_version()` (§7.1) checks `status` at call-start time, independent of the archive's own row lock — a call that resolved *before* archive committed proceeds normally (pins its version, §19.3); a call resolving *after* sees `ARCHIVED` and fails closed | Deterministic based on which committed first; no execution is ever started against a definition the resolver itself observed as archived | None |
| Republish during active execution | INV-WF-03 trigger — `workflow_version_id` is immutable on the execution row, full stop | N/A — not a race, a hard invariant | None |
| Duplicate execution start (same session) | `pg_advisory_xact_lock` + guarded SELECT/INSERT inside `fn_start_workflow_execution` (§17) | Second caller receives an exception, must reconcile via `GET` (application-layer responsibility, disclosed) | Disclosed reconciliation behavior not yet implemented, §54 item |
| Two runtime workers advance the same execution (checkpoint race) | Redis is the sole live-call authority (§28); Postgres checkpoint ordering is a queue-configuration requirement, not DB-enforced | Live call unaffected either way; historical/recovery view may show a transient ordering artifact | Disclosed, §37.2 |
| Out-of-order Postgres checkpoints | Same as above | Same | Disclosed, §37.2 |
| Redis loss during active execution | Fallback to last Postgres checkpoint (§29) | Pure-node Turns safely re-evaluate; side-effecting Turns are the §30 gap | `BLOCKER` for side-effecting nodes, §30 |
| Duplicate side-effect node delivery | **None exists today** | Side effect fires twice | `BLOCKER`, §30 |
| Complete vs. late checkpoint | `trg_we_immutable` rejects any UPDATE once `status IN ('COMPLETED','FAILED')` | The late checkpoint's UPDATE is rejected by the trigger — it cannot resurrect a terminal execution's mutable fields | None — INV-WF-04 closes this cleanly |
| Fail vs. late checkpoint | Same trigger, same reasoning | Same | None |
| GDPR erase vs. active execution | 5G ADR-5G-009 — best-effort, async, scoped to durable rows only | An `ACTIVE` execution's live Redis `slots` are not touched until checkpoint/completion | Disclosed, inherited, §45 |

---

## 58. Strict Security Review — Adversarial Exploit Attempts

| Attempt | Verdict |
|---|---|
| Tenant A publishes Tenant B's workflow | **Closed** — `fn_workflow_publish`'s ownership `EXISTS` check, §35 |
| Tenant A starts an execution using Tenant B's `WorkflowVersion` | **Closed** — `fn_start_workflow_execution`'s tenant-match `EXISTS`, §17/§35 |
| A `WorkflowVersion` published under a workflow it doesn't belong to | **Closed** — `workflow_definition_id` ownership check inside `fn_workflow_publish` |
| An `ARCHIVED` workflow republished | **Closed** — `status != 'ARCHIVED'` precondition, INV-WF-02 |
| `app_api` directly mutates an immutable `WorkflowVersion` (`graph_json`) | **Closed** — `trg_wv_immutable` + `REVOKE UPDATE` from `app_api`/`app_worker` |
| `app_platform_admin` bypasses `fn_start_workflow_execution()` via direct INSERT | **Closed** — `076_5K1.sql`'s narrow re-revoke |
| `app_platform_admin` bypasses `fn_workflow_publish()`'s guard via direct UPDATE on `workflow_definitions`, or DELETEs/reassigns an immutable `WorkflowVersion` | **Closed 2026-08-29** — `100_5G1.sql` reduced `app_platform_admin` to `SELECT`-only; identity-reassignment additionally rejected by the hardened trigger even for the `postgres` superuser. §38/§63. |
| Runtime worker changes a pinned `workflow_version_id` mid-execution | **Closed** — `trg_we_immutable`'s explicit `IS DISTINCT FROM` check |
| Runtime worker updates a `COMPLETED` execution | **Closed** — `trg_we_immutable`'s terminal-status check |
| A malicious workflow expression attempts Python code execution | **Closed** — whitelist AST evaluator, never `eval()`/`exec()`, validated at both publish and runtime (§16) |
| A `WEBHOOK` node targets `169.254.169.254` (cloud metadata service) | **N/A — the node type cannot currently execute at all** (§23, execution-blocked pending 6J); once 6J exists, §23.2's required controls (metadata-IP blocking explicitly named) must be verified before this can be reopened |
| A `TOOL_CALL` node's `tool_name` invokes an arbitrary code path | **Closed** — `tool_name` is a string key into an allow-listed registry, never a dotted import path/class name (§22) |
| Workflow graph JSON stores a plaintext API secret | **Mitigated, not eliminated** — publish-time detection of credential-shaped literals (§46) catches the common case; a sufficiently obfuscated secret is not detectable by pattern-matching alone — disclosed, matches the honesty level 6E applies to its own equivalent `qualification_criteria` gap |
| The debug API exposes credentials/tool auth headers | **Closed** — structurally absent from the response model allow-list (§32.3), never merely masked |
| A stale Postgres checkpoint rewinds a live execution | **Closed 2026-08-29** — `checkpoint_seq` CAS + hardened trigger reject any backward move unconditionally, live-proven against a genuine two-connection out-of-order-commit race and against the `postgres` superuser. §37/§63. |
| Redis loss causes a side effect to repeat | **Closed 2026-08-29** — `workflow.node_execution_claims`' durable `SUBMITTING` boundary means a lost Redis cursor can no longer cause a second invocation of an already-in-flight or already-succeeded side effect; a recovering worker observes the claim's durable state before any re-invocation. §30/§63. |

**Status update (2026-08-29):** both exploit classes previously left open by this section are now closed by migration `100_5G1.sql`, live-validated on genuine PostgreSQL 16.10 (§63). No exploit in this table remains in a "NOT closed" state as of this pass.

---

## 59. Architecture Decision Records

| ID | Decision | Alternatives considered | Rationale (condensed) | Status |
|---|---|---|---|---|
| ADR-6I-01 | 4E's 6-value `Directive` enum governs over 3D's 7-value `DirectiveKind`; `TRANSFER_TO_HUMAN`/`DELAY` folded in via payload discriminators | Adopt 3D's larger enum instead; invent a third, merged vocabulary | DDD supersedes LLD per project convention; minimal reconciliation preserves both node-type distinctness and directive-consumption simplicity (§4.4) | Decided |
| ADR-6I-02 | `ArchiveWorkflow` classified under `workflow:write`, not a new permission | Invent `workflow:archive`; require `workflow:publish` | Definition-level lifecycle mutation, same kind as draft editing; publishing (creating an executable artifact) is the stronger gate, not archiving | Decided |
| ADR-6I-03 | Full-replace `PUT /workflows/{id}/draft`, no granular node/edge endpoints, no PATCH/JSON-Merge-Patch on the graph | Twelve granular mutation endpoints; JSON Merge Patch | Matches ADR-5G-001's JSONB-as-one-unit design; array-of-objects merge semantics are ambiguous; 6A §7.3 explicitly anticipates PUT for exactly this resource | Decided |
| ADR-6I-04 | `WEBHOOK`/`API_CALL` — draft-acceptable, publish-blocked (Option C) | Fully block even in draft; fabricate a generic port | Preserves builder usability without pretending 6I owns SSRF/credential infrastructure that belongs to 6J | Decided |
| ADR-6I-05 | `DELAY` node → `WAIT` directive, realized by the Voice Orchestrator's own turn timing, never a `sleep()` in the engine; 5-second hard cap | Unbounded delay; engine-internal blocking sleep | Closes the DoS vector named by the governing task; keeps the engine non-blocking | Decided |
| ADR-6I-06 | Add `WORKFLOW_CREATED`/`WORKFLOW_DRAFT_UPDATED`/`WORKFLOW_ARCHIVED` to 5J's governed `action_kind` vocabulary, documentation-only | Reuse a generic `WORKFLOW_UPDATED`; skip audit for draft updates | Matches the established †/‡/¶/§ amendment pattern exactly; `chk_ae_action_kind` is length-only, no migration needed | Decided |
| ADR-6I-07 | Workflow definition-level mutations join the synchronous-audit exception list | Leave them on the async default | Matches the 6D/6E precedent's own stated reasoning (not on the voice hot path; durable audit required unconditionally by 6A §22) | Decided |
| ADR-6I-08 | `POST /workflows/{id}/publish` requires `If-Match` | No precondition (silently publish whatever draft is current) | Closes the "publish a draft revision you never saw" hazard the governing task names explicitly | Decided |
| ADR-6I-09 | No durable node-execution idempotency claim table exists; side-effecting nodes are gated (`BLOCKER`) rather than approved as production-ready | Approve as-is, relying on Redis; silently assume `voice.tool_executions` already has dedup | Proven false by direct inspection of the executed DDL (§30, §22); honesty over false approval | Decided |
| ADR-6I-10 | `GET /workflow-executions/{id}` excluded from API-key eligibility; `GET /workflow-executions` (summary) remains eligible | Allow API keys on both; block both | PII-bearing detail view vs. PII-free summary — matches 6B's own "never assume a key may access everything" posture | Decided |

---

## 60. Phase 6I Acceptance Criteria

- [x] Public Workflow management/read API designed, derived from 4E's command/query catalogue and 5G's executed physical schema (§6, §56)
- [x] Draft/publish/archive lifecycle preserved exactly as 4E/5G define it, no invented states (§4.2)
- [x] All 14 node types preserved, reconciled against both 3D and 4E, discriminated-union config schemas defined (§4.3, §11)
- [x] Expression safety treated as a P0 boundary — whitelist grammar, dual validation, limits, deterministic errors (§16)
- [x] Only the frozen `workflow:read`/`write`/`publish` permissions used, no invented permission (§5)
- [x] Internal runtime commands (`StartExecution`/`AdvanceCursor`/`UpdateSlots`/`Complete`/`Fail`) kept off the public REST surface (§7)
- [x] Voice→Workflow in-process runtime contract fully specified (§7, §18)
- [x] Agent→Workflow boundary resolved (`DEP-6E-03` closed with a supplied, if unconsumed, port) (§19)
- [x] Campaign→Workflow ACL designed narrowly, consuming 6H's own approved use cases only (§20)
- [x] KNOWLEDGE_SEARCH→6F boundary resolved (`DEP-6F-11` closed) (§21)
- [x] TOOL_CALL boundary designed without turning tools into services (§22)
- [x] WEBHOOK/API_CALL honestly classified execution-blocked, not prematurely designed (§23)
- [x] TRANSFER/HUMAN_TRANSFER/END_CALL routed through 6D's existing call-control, no second call-control API (§24)
- [x] DELAY node made realtime-safe with a hard, disclosed cap (§25)
- [x] LLM node routes through the existing Model Router, no parallel router invented (§26)
- [x] ADR-5G-010 carried forward, not silently fixed (§27)
- [x] Redis/Postgres two-tier execution state fully specified, including failure/recovery behavior (§28, §29)
- [x] Side-effecting node idempotency gap found, proven against executed DDL, and classified as a genuine BLOCKER with a remediation sketch — not dismissed (§30)
- [x] Execution debug API designed with explicit redaction and API-key exclusion (§32)
- [x] Execution/definition list filters limited to actually-indexed columns (§33, §34)
- [x] Every Workflow `SECURITY DEFINER` function individually reviewed for tenant/ownership checks and search-path completeness (§17, §35)
- [x] Publish concurrency adversarially reviewed against 6A §35's atomicity mandate, with the missing version-number-lock detail supplied (§36)
- [x] Checkpoint stale-write race adversarially reviewed, resolved for the live call, disclosed as a residual risk for recovery ordering (§37)
- [x] `app_platform_admin` direct-DML bypass reviewed and a genuine, disclosed gap found and classified (§38)
- [x] Terminal-execution immutability confirmed against the actual trigger body (§39)
- [x] Full crash matrix produced for side-effecting nodes, no "exactly once" language used without a mechanism to back it (§40)
- [x] Realtime, non-audio WS channel designed per 6A's own generic envelope (§41)
- [x] Audit `action_kind` gap found and closed via the established documentation-only amendment pattern (§42)
- [x] Domain events classified durable vs. telemetry, explicitly avoiding outbox flooding (§43)
- [x] Voice latency budget for every Workflow-internal step traced to 6A §11, no new numbers invented where an existing one applies (§44)
- [x] GDPR/PII propagation into Workflow execution state confirmed against 5G's own ADR (§45)
- [x] Secret handling in graph JSON closed structurally, not just documented (§46)
- [x] Full, HTTP-code-mapped error catalogue produced (§47)
- [x] Full per-endpoint authorization matrix, including API-key eligibility, produced (§48)
- [x] Runtime defense against corrupted/invalid published graphs specified (§49)
- [x] Idempotency-Key behavior specified per mutating endpoint, with honesty about which have a DB-level backstop and which don't (§50)
- [x] ETag/optimistic concurrency and publish-against-exact-draft resolved (§51, §52)
- [x] WorkflowVersion retention/no-delete confirmed (§53)
- [x] Full dependency/deferred-item register produced with honest classification, no genuine gap called "non-blocking" without justification (§54)
- [x] WorkflowTrigger confirmed absent, not invented (§55)
- [x] Full Phase 5 capability-reconciliation table produced (§56)
- [x] Full concurrency matrix produced, no hand-waved race (§57)
- [x] Full adversarial security review produced, two genuine open items disclosed rather than approved away (§58)
- [x] No Phase 5 schema, migration, function, or grant modified (§1, §3)
- [x] No 6A–6H content contradicted or silently amended (§3, §20, §21, §24)
- [x] No 6J/6K/6L/6M capability prematurely designed (§23, §54)

---

## 61. Final Approval Status

### PHASE 6I STATUS (as of the original pass, superseded below): ~~APPROVED WITH TWO DISCLOSED, NON-SILENT FINDINGS~~

**This verdict was invalid governance and is retracted, not merely amended.** A document carrying an open `BLOCKER` (§30, as originally classified) cannot simultaneously be "APPROVED" — the original text is struck through above and kept only for audit trail, per the Phase 6I Blocker Remediation pass's own instruction to correct this contradiction rather than paper over it.

### PHASE 6I STATUS (2026-08-29, Phase 6I Blocker Remediation pass): **APPROVED / FROZEN**

Both genuine findings the original pass correctly discovered but left open are now **RESOLVED**, live-validated on genuine PostgreSQL 16.10, via the single additive migration `100_5G1.sql`:

1. **§30 — Side-effecting node idempotency.** `workflow.node_execution_claims` (a `CLAIMED → SUBMITTING → SUCCEEDED|FAILED|AMBIGUOUS` durable claim, structurally mirroring `voice.call_dispatch_keys`) plus five guarded functions. Live-proven under a genuine two-connection concurrent-duplicate-claim race (§63, test C1): exactly one claimant ever wins, exactly one durable row ever exists for a given `(execution, Turn, node)` identity. `TOOL_CALL`/`TRANSFER`/`HUMAN_TRANSFER` are now `IMPLEMENTATION-READY`; `WEBHOOK`/`API_CALL` remain `EXECUTION-BLOCKED` pending 6J (§23/§54 item 5, unchanged — a separate, still-open dependency this migration does not and cannot close).
2. **§38 — `app_platform_admin` direct-DML bypass.** Reduced to `SELECT`-only on `workflow_definitions`, `workflow_versions`, `workflow_executions` (parent and every partition — a defensive per-partition privilege loop, itself a live-discovered necessity in this same pass), `node_execution_claims`, and `prompt_versions`. Live-proven closed for all nine originally-named exploit vectors (§63, test suite T6).

Two further items §37 had left as a disclosed, non-blocking residual risk are also now fully closed rather than merely mitigated: the stale/out-of-order checkpoint race (a new `checkpoint_seq` CAS plus a hardened, unconditional trigger guard, live-proven against a genuine two-connection out-of-order-commit race and against the `postgres` superuser), and the Archive-vs-draft-update concurrency-matrix self-contradiction §57 originally carried (now corrected in place, live-proven both via the ordinary WHERE-clause path and via a new terminal-immutability trigger).

Everything else — draft/publish/archive lifecycle, node-type catalogue and validation, expression safety, the Voice/Agent/Campaign/Knowledge cross-context boundaries, execution debug/list reads, realtime progress, audit, GDPR propagation, and the full concurrency/security adversarial review — remains as designed in the original pass, reconciled against the actually-executed SQL (not stale prose, §3), and does not modify, contradict, or prematurely extend any frozen Phase 1–6H document. See §63 for the complete live-validation record.

---

## 62. Implementation Summary

**1. Files created**
- `docs/phase-06-api-design/6I-Workflow-APIs.md` (this document)

**2. Files modified**
- None. Phase 1–5 and Phase 6A–6H untouched, as required.

**3. Major architecture decisions**
- Cohesive resource model (`/workflows`, `/workflows/{id}/draft`, `/workflows/{id}/versions`, `/workflow-executions`) — no granular node/edge CRUD, no destructive DELETE, no `WorkflowTrigger` endpoint (§6, §55, ADR-6I-03).
- Internal runtime commands kept strictly off the public REST surface — `WorkflowRuntimeService` is the sole Voice-consumption contract, in-process, never HTTP (§7).
- 3D/4E node-type and directive-vocabulary discrepancies reconciled explicitly, DDD-governs-over-LLD, with a documented payload-discriminator mapping rather than silent invention (§4.3, §4.4, ADR-6I-01).

**4. Security decisions**
- Expression safety enforced as a dual (publish + runtime) whitelist-AST boundary, with hard length/complexity/time limits this document itself sets (§16).
- WEBHOOK/API_CALL honestly classified execution-blocked pending 6J, rather than a fabricated SSRF-control story (§23).
- Two genuine, disclosed production-safety findings — side-effecting node idempotency (§30) and admin direct-DML bypass (§38) — proven against actual executed SQL, not asserted from prose, each with a minimum-remediation sketch and neither implemented here.

**5. Concurrency decisions**
- Publish atomicity resolved by combining 6A §35's already-binding same-transaction mandate with this document's own missing piece: a `SELECT ... FOR UPDATE` lock for race-free version-number computation (§36).
- `fn_start_workflow_execution`'s actual advisory-lock mechanism (not 5G's stale unique-index prose) fully reverse-engineered and adversarially tested against eight named race scenarios (§17).
- Checkpoint stale-write race resolved for the live call (Redis-authoritative) with an honestly disclosed residual ordering risk for post-loss recovery (§37).

**6. Cross-context boundary decisions**
- Agent→Workflow: two-stage resolution (pinned `WorkflowDefinitionId` → live `published_version_id` → per-execution-pinned `WorkflowVersionId`) supplied, closing `DEP-6E-03` as a port, disclosed as unconsumed by frozen 6E (§19).
- Campaign→Workflow: narrow in-process ACL wrapping 6H's own approved `CreateCampaign`/`StartCampaign` use cases, no `campaign.*` writes, no new node type (§20).
- Knowledge→Workflow: `DEP-6F-11` closed by reference to 6F's own in-process port and documented empty-result-on-failure behavior, not re-specified (§21).

**7. Dependencies / open items** (§54, full detail)
- `BLOCKER`: side-effecting node idempotency (§30).
- `NON-BLOCKING`, disclosed: admin DML bypass (§38), checkpoint-ordering guarantee (§37.2), publish idempotency-key DB backstop strength (§50).
- `DEFERRED`: ADR-5G-010 prompt-version pinning (Phase 9, per 5G/5L's own explicit, confirmed-non-required classification).
- `EXECUTION-BLOCKED`: WEBHOOK/API_CALL nodes (6J dependency, §23); Campaign ACL tool binding (6H/6J dependency, §20).

**8. Conflicts discovered with prior phases**
- Three discrepancies between 5G's narrative prose and the actually-executed 5G/5K.1 migrations (§3) — all resolved in favor of executed SQL, per the governing rule, none requiring a new migration to reconcile (the executed SQL was already correct; 5G's prose was simply stale).
- No conflict found with 6A–6H's own content — every boundary statement 6E/6F/6H made about deferring to 6I (`DEP-6E-03`, `DEP-6F-11`, the Campaign ACL statement) is consumed here exactly as those documents framed it, with no retroactive edit to any of them.

---

## 63. Phase 6I Blocker Remediation (2026-08-29) — Live-Validated Resolution

This section records the remediation pass that closed §30 (side-effecting node idempotency), §37 (checkpoint stale-write race), §38 (admin direct-DML bypass), and the §57/§20-22 Archive-vs-draft-update concurrency-matrix contradiction — all via one additive migration, live-tested on genuine PostgreSQL 16.10. Nothing in §1-§62 above was rewritten to pretend these were designed correctly the first time; each affected section carries an explicit status-update note pointing here, and the original analysis is preserved as the record of what was found.

### 63.1 Migration

`docs/phase-05-database-design/5K/migrations/100_5G1.sql`, Alembic revision `100_5G1`, `down_revision = '099_5C1'`. Single additive migration; no row 001-099 edited, renumbered, or reordered. `alembic/versions/100_5G1.py` wraps it via the same `run_frozen_sql()` pattern as every prior revision; `downgrade()` raises `NotImplementedError` (forward-only, matching the whole package) — live-confirmed to raise correctly and to leave the database cleanly at `100_5G1` afterward (no partial state).

### 63.2 Side-Effect Node Safety (closes §30)

**Stable identity across worker restart:** `(organization_id, workflow_execution_id, target_checkpoint_seq, node_id)`, where `target_checkpoint_seq` is the `workflow_executions.checkpoint_seq` value the *currently-evaluating* Turn will commit as (last-committed + 1) — reproducible after a crash without any external counter, because a retried evaluation of the same not-yet-committed Turn always recomputes the identical value until that Turn's checkpoint actually lands. A single Turn cannot legitimately revisit the same `node_id` twice without first producing an outward-facing Directive (4E's own cycle-safety invariant), so this composite key is safe as a hard uniqueness constraint.

**Claim state machine:** `CLAIMED → SUBMITTING → SUCCEEDED | FAILED | AMBIGUOUS` (`FAILED` also reachable directly from `CLAIMED`) — structurally identical to `voice.call_dispatch_keys` (`099_5C1.sql`). `SUBMITTING` is the durable, pre-side-effect commit boundary (`fn_begin_node_submission()`): the caller's mandatory contract is call this, confirm `began=TRUE`, and only then invoke the actual tool/transfer/webhook side effect. Once `SUBMITTING` commits, no automatic reclaim occurs at any lease staleness — live-proven (test T5.4/T5.9, and concurrency test C1).

**Submission boundary:** enforced by `fn_begin_node_submission()`'s own CAS (`claim_state='CLAIMED' AND claimed_by=$worker AND claim_expires_at > NOW()`), matching `fn_begin_provider_submission()`'s exact pattern.

**Retry rules:** `FAILED` (a proven pre-acceptance/pre-submission failure) is safely reclaimable (test T5.10/T5.11) — an expired-lease `CLAIMED` row (side effect never began) is also safely reclaimable (test T5.12) — `SUBMITTING`/`AMBIGUOUS` are never auto-reclaimed under any staleness (tests T5.4, T5.9).

**Ambiguity/reconciliation:** `AMBIGUOUS` (timeout/crash-after-submitting-with-no-further-evidence) is a hard stop for automatic retry. No function in `100_5G1.sql` transitions `AMBIGUOUS` back to `CLAIMED`/`SUBMITTING` — resolving an `AMBIGUOUS` claim requires an application-layer reconciliation process (analogous to `voice.fn_reconcile_dispatch_from_provider()`/`fn_reconcile_dispatch_by_operator()`) that this schema-only migration does not itself define. **Disclosed forward dependency**, not designed here — no frozen source defines a Workflow-side reconciliation UI/process yet; carried forward as a `NON-BLOCKING` item (§54).

**TOOL_CALL / `voice.tool_executions`:** Option B (§8) adopted — `voice.tool_executions` is unmodified; `node_execution_claims.downstream_ref` holds an opaque reference to it (e.g. `tool_executions.id::text`) once known. No FK, no schema touch to 5C/6D/6E's own table.

**TRANSFER / HUMAN_TRANSFER:** 6D already provides a natural idempotency backstop independent of this migration — `POST /calls/{id}/transfer`'s own `TransferOnlyOncePerCall` policy (4B §9, cited verbatim in 6D §11) rejects a second transfer attempt against a call that has already left `ACTIVE`. The new claim table's `SUBMITTING` boundary is additional defense-in-depth and an audit-correlation point (via `downstream_ref`), not the sole safety net for these two node types — 6D's own state-machine guard is. No second Voice call-control state machine is introduced.

**WEBHOOK / API_CALL:** unaffected — still `EXECUTION-BLOCKED` pending 6J (ADR-6I-04, unchanged, §54 item 5). The durable primitive 6J will eventually need is now documented and exists; 6J still separately owns SSRF/credential/egress controls.

### 63.3 Checkpoint Ordering (closes §37)

`workflow.workflow_executions.checkpoint_seq BIGINT NOT NULL DEFAULT 0` — durable, monotonic, per-execution. Enforced non-decreasing by two independent layers: (a) `fn_checkpoint_workflow_execution()`'s own CAS WHERE-clause (`checkpoint_seq < p_checkpoint_seq`), returning `APPLIED | STALE_CHECKPOINT | EXECUTION_TERMINAL | NOT_FOUND`; (b) a hardened `prevent_execution_mutation()` trigger rejecting `NEW.checkpoint_seq < OLD.checkpoint_seq` unconditionally, regardless of caller or grant. Layer (b) was live-proven to hold even for the `postgres` superuser bypassing every privilege and RLS policy (test T4.3) — this is the strongest form of the guarantee the governing task asked for: PostgreSQL itself rejects a stale checkpoint, not merely "the application is supposed to send them in order."

`fn_complete_workflow_execution()`/`fn_fail_workflow_execution()` are the new sole legal terminal-state transitions, replacing direct `UPDATE` (now revoked from every runtime role on this table, §63.4).

### 63.4 Workflow/Admin Privilege Hardening (closes §38)

Final grant posture, live-confirmed via `information_schema.role_table_grants` after the fix (and after discovering and closing a partition-level gap — see §63.6):

| Table | `app_api` / `app_worker` | `app_platform_admin` | `app_readonly` |
|---|---|---|---|
| `workflow.workflow_definitions` | SELECT, INSERT, UPDATE (draft/metadata/archive mutations, unchanged) | **SELECT only** (was SELECT/INSERT/UPDATE/DELETE) | SELECT |
| `workflow.workflow_versions` | SELECT, INSERT (unchanged, `040_5G.sql`) | **SELECT only** (was SELECT/INSERT/UPDATE/DELETE) | SELECT |
| `workflow.workflow_executions` (parent + every partition) | SELECT (INSERT via `fn_start_workflow_execution` only, unchanged; **UPDATE now revoked** — mutation is guarded-function-only) | **SELECT only** (INSERT already revoked by `076_5K1.sql`; UPDATE/DELETE now also revoked) | SELECT |
| `workflow.node_execution_claims` (new) | SELECT (all mutation via the five guarded functions) | **SELECT only** | SELECT |
| `prompt.prompt_versions` | SELECT, INSERT (unchanged, `042_5G.sql`) | **SELECT only** (was SELECT/INSERT/UPDATE/DELETE) | SELECT |

No new PostgreSQL role was created — every new function is `EXECUTE`-granted only to `app_api`/`app_worker`, the two existing roles already granted for the equivalent Voice-side pattern. No new guarded admin-override function was added; a future 6M-owned administrative correction is the disclosed path for any legitimate emergency need (§16 of the remediation brief, honored as written).

### 63.5 WorkflowVersion Immutability (identity + delete)

`prevent_wf_version_mutation()` and (the disclosed sibling gap) `prevent_pv_mutation()` now also guard `workflow_definition_id`/`prompt_template_id` and `organization_id` — live-proven to reject a reassignment attempt even for the `postgres` superuser (tests in `..._10_6i_version_identity_trigger_superuser.txt`). Combined with the SELECT-only privilege reduction (§63.4), no runtime role can DELETE or identity-reassign a `WorkflowVersion`/`PromptVersion` through any path.

### 63.6 Archive Immutability (closes the §57/§20-22 contradiction)

Legal transitions unchanged (`DRAFT`/`PUBLISHED → ARCHIVED`, terminal). What changed: a new `workflow.prevent_archived_definition_mutation()` `BEFORE UPDATE` trigger rejects any further mutation of `name`/`description`/`draft_graph`/`published_version_id`/`status` once `status = 'ARCHIVED'`, unconditionally. Race outcomes, live-proven via a genuine two-thread/two-connection test (C4):

- **Draft/metadata update admitted first, then Archive:** both succeed in that order — the draft update's own commit precedes Archive's; no invariant violated (matches the corrected concurrency-matrix wording, §57).
- **Archive commits first, a queued draft update was waiting on the row lock:** once unblocked, the draft update's own `WHERE status IN ('DRAFT','PUBLISHED')` predicate excludes the now-`ARCHIVED` row — **zero rows affected**, live-confirmed (`b_result={'rowcount': 0}`).
- **A hypothetical future code path with no such WHERE-clause guard:** the trigger itself rejects the UPDATE outright, live-proven even for the `postgres` superuser (`ERROR: workflow_definitions: ARCHIVED is terminal`).
- **Archive vs. Publish:** unchanged from the original §36 analysis (same row lock serializes the two; `fn_workflow_publish()`'s own `status != 'ARCHIVED'` precondition, combined with the single-transaction requirement, prevents an orphaned version either way).

### 63.7 Execution Start Idempotency (closes the §17.2/§26 disclosed gap)

`fn_start_workflow_execution()` (DROP + CREATE, return-type change) now returns `TABLE(execution_id, execution_started_at, outcome)`, `outcome IN ('STARTED','REPLAYED_EXISTING','VERSION_CONFLICT')`, instead of raising on the benign duplicate-active-session race. Live-proven under **genuine simultaneity** (test C3b, two real threads/connections racing with no artificial ordering): the race resolves to a single execution id, with exactly one caller observing `STARTED` and the other `REPLAYED_EXISTING`. A request for a *different* `workflow_version_id` against an already-`ACTIVE` session now returns `VERSION_CONFLICT` (same execution id, no silent substitution) rather than raising. The function additionally now rejects (raises) when the `WorkflowVersion`'s parent `WorkflowDefinition` is `ARCHIVED` — closing the resolve-then-archive-then-start race at the durable serialization point (live-proven, test T1.4).

### 63.8 PostgreSQL 16 Validation

No Docker engine available in this environment (reconfirmed). Native PostgreSQL 16.10 built from the EDB binaries-only distribution (`postgresql-16.10-1-windows-x64-binaries.zip`), installed at `C:\Users\Dell\pgval16\pgsql`, `initdb` + `pg_ctl start -o "-p 5433"` run directly (no elevation required), `trust` auth for local loopback only — matching the prior `PG16_MIGRATION_VALIDATION_REPORT.md` pass's own documented approach exactly. `pgvector` 0.8.0 built from source via the same MSVC 14.51.36231 (Visual Studio 18 Community) toolchain and installed into the PG16 tree; `plpgsql`/`vector`/`pgcrypto`/`pg_stat_statements` all confirmed loadable before any migration ran. Alembic `1.19.1` / SQLAlchemy `2.0.52` / `psycopg[binary]` `3.3.4` in a throwaway `uv`-managed Python 3.12 venv, identical versions to the prior pass.

| Check | Result | Evidence |
|---|---|---|
| Fresh `001_5B → … → 099_5C1 → 100_5G1` | **PASS, exit 0**, single head `100_5G1` | `execution_logs/20260829T020000Z_12_..._14_*.txt` |
| Incremental: pin at `099_5C1`, then apply `100_5G1` alone | **PASS, exit 0** for both steps | `execution_logs/20260829T020000Z_15/16_*.txt` |
| `alembic history` | Single linear 100-entry chain, `<base> → 001_5B → … → 100_5G1`, no branch | `execution_logs/20260829T020000Z_17_*.txt` |
| `alembic heads` / `current` | `100_5G1 (head)` in both fresh and incremental databases | Same batch |
| `downgrade()` | Raises `NotImplementedError` as designed; failed-downgrade transaction rolls back cleanly, DB remains at `100_5G1` | `execution_logs/20260829T020000Z_18_*.txt` |

### 63.9 Concurrency / Failure-Injection Test Matrix — Actual Results

| # | Scenario | Mechanism exercised | Result |
|---|---|---|---|
| 1 | Two genuine connections race to claim the identical `(execution, Turn, node)` identity | `fn_claim_node_execution()` unique-constraint + `ON CONFLICT DO NOTHING` | **PASS** — exactly one winner, one durable row |
| 2 | Second worker claims while lease valid | Same | **PASS** — `NOT_CLAIMABLE_CLAIMED` |
| 3 | Claim → begin submission → a different worker attempts to claim while `SUBMITTING` | `fn_begin_node_submission()` + reclaim predicate | **PASS** — `NOT_CLAIMABLE_SUBMITTING`, never reclaimed |
| 4 | Record `SUCCEEDED` with `downstream_ref`; a later claim attempt | `fn_record_node_succeeded()` | **PASS** — `NOT_CLAIMABLE_SUCCEEDED`, `downstream_ref` readable |
| 5 | Independent node in the same Turn | Composite identity key | **PASS** — independently claimable |
| 6 | Begin submission → `AMBIGUOUS` (timeout) → reclaim attempt | `fn_record_node_ambiguous()` | **PASS** — never auto-reclaimed |
| 7 | Claim → `FAILED` (pre-submission local abort) → retry | `fn_record_node_failed()` + reclaim | **PASS** — safe retry allowed |
| 8 | 5-second lease expires with no submission attempted → reclaim | Reclaim predicate | **PASS** — safely reclaimable, same claim row reused |
| 9 | Forged `organization_id` argument on claim/checkpoint/start functions | Explicit in-function tenant check | **PASS** — exception, all three functions |
| 10 | Direct DML on `node_execution_claims` as `app_api` | Grant revoke | **PASS** — permission denied |
| 11 | Sequential checkpoint seq=1 then seq=2 | CAS | **PASS** — both `APPLIED` |
| 12 | Delayed seq=1 arrives after seq=2 already applied | CAS | **PASS** — `STALE_CHECKPOINT`, state unchanged |
| 13 | Duplicate delivery of already-applied seq=2 | CAS | **PASS** — `STALE_CHECKPOINT`, idempotent no-op |
| 14 | Checkpoint after `COMPLETED` | CAS | **PASS** — `EXECUTION_TERMINAL` |
| 15 | Checkpoint on nonexistent execution / wrong partition (`started_at`) hint | CAS | **PASS** — `NOT_FOUND` in both cases |
| 16 | Direct raw `UPDATE workflow_executions` as `app_api` | Grant revoke | **PASS** — permission denied |
| 17 | Direct raw `UPDATE` moving `checkpoint_seq` backward, as `postgres` superuser | Hardened trigger | **PASS** — rejected unconditionally |
| 18 | **Genuine two-connection race**: seq=2 (fast) commits before delayed seq=1's UPDATE is even issued | CAS, real concurrency | **PASS** — final state seq=2, seq=1 gets `STALE_CHECKPOINT` |
| 19 | **Genuine two-connection race**: duplicate `StartExecution`, sequential | Advisory lock + CAS | **PASS** — `STARTED` then `REPLAYED_EXISTING`, same id |
| 20 | **Genuine two-thread race**: simultaneous `StartExecution`, no ordering bias | Advisory lock + CAS | **PASS** — single execution id, exactly one `STARTED` + one `REPLAYED_EXISTING` |
| 21 | **Genuine two-thread race**: Archive commits first, queued draft update proceeds after | Row lock + trigger | **PASS** — 0 rows affected, state unchanged |
| 22 | Raw `UPDATE` on an `ARCHIVED` definition as `postgres` superuser | Terminal-immutability trigger | **PASS** — rejected unconditionally |
| 23-31 | `app_platform_admin`: UPDATE/DELETE/INSERT on `workflow_definitions`, `workflow_versions` (×2), `workflow_executions` (×2), `prompt_versions` | Grant revoke | **PASS, all 9** — permission denied; legitimate SELECT confirmed still working |
| 32-33 | `workflow_versions`/`prompt_versions` identity-column reassignment as `postgres` superuser | Hardened identity trigger | **PASS, both** — rejected unconditionally |
| 34-38 | Tenant isolation: Org A sees only its own rows; Org B sees 0 of Org A's workflows/executions/claims; no tenant context set → 0 rows on all three tables | RLS, fail-closed | **PASS, all 5** |

**38/38 PASS.** Every command and raw output is preserved under `docs/phase-05-database-design/5K/execution_logs/20260829T020000Z_*.txt` (files `01`-`19`) and is genuine, live output — not fabricated or asserted from reading the SQL alone.

### 63.10 Documentation Reconciled

- `docs/phase-05-database-design/5K/migrations/100_5G1.sql` — new.
- `docs/phase-05-database-design/5K/alembic/versions/100_5G1.py` — new.
- `docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md` — new table row 100, new top-of-log section "Phase 6I Blocker Remediation (2026-08-29)".
- `docs/phase-06-api-design/6I-Workflow-APIs.md` (this document) — status-update notes added to §30, §37, §38; §57's Archive row corrected in place (the prior wording is struck through, not silently replaced); §58's two "NOT closed" rows updated to "Closed"; §54's dependency table updated (items 5-8 reclassified); §17.2's disclosed-gap row updated to reflect the deterministic-outcome fix; §61's invalid "APPROVED WITH BLOCKER" verdict retracted (struck through, kept for audit trail) and replaced with a dated, unconditional **APPROVED / FROZEN**; this §63 added.

No edit was made to `4E-Knowledge-RAG-Workflow-Tools.md`, `5G-Workflow-Prompt-Memory-Schema.md`'s own body text (a separate, small carry-forward note is the only touch — see that document's own amendment marker near its ADR list), or to any 6A-6H document.

### 63.11 Remaining Dependencies (legitimate, unaffected by this pass)

- ADR-5G-010 — prompt-version pinning for deterministic replay (Phase 9, per 5G/5L's own confirmed non-requirement).
- `WEBHOOK`/`API_CALL` execution — still blocked pending 6J's SSRF/credential/egress controls (§23, ADR-6I-04).
- `AMBIGUOUS`-claim reconciliation process/UI — schema primitive now exists (`claim_state='AMBIGUOUS'`, `idx_nec_ambiguous`); the application-layer reconciliation workflow is not designed in this schema-only pass (disclosed, `NON-BLOCKING`).
- Billing/Analytics/Admin consumption of `workflow.execution.completed` and node-level telemetry (6K/6L/6M, not started).
- Campaign ACL tool binding (6H/6J dependency, §20, unaffected).

### 63.12 Remaining Blockers

**NONE.**

### 63.13 Final Verdict

**APPROVED — PHASE 6I READY TO FREEZE**

---

**STOP — Phase 6I complete (including the 2026-08-29 Blocker Remediation pass, §63). Phase 6J not started.**
