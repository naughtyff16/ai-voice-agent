# Phase 7C — Event Envelope & Schema Versioning — AI Voice Agent Platform

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 7C — Event Envelope & Schema Versioning |
| Phase | 7 — Event Architecture |
| Status | **DRAFT — FREEZE-GATE REMEDIATION APPLIED — BLOCKED ON OD-7C-07 — NOT READY FOR INDEPENDENT REVIEW** |
| Remediation | Freeze-gate findings P1-7C-01 … P1-7C-06 (§51.1). Five RESOLVED; P1-7C-04 OPEN pending owner decision OD-7C-07 (§46.8). Remediated in place; pre-remediation SHA-256 `a583365003581bf6732e18dba91e54d8ec891b89993f61b97cb24b7ce31ff16e` / 2963 lines |
| Date | 2026-09-29 |
| Repository baseline | `main` @ `5f5ddec17dc99e49e688cd1827cc83f2c9bcd797` ("7B approved"), working tree clean at start |
| Frozen upstream | 7A (Event Architecture & Standards), 7B (Event Taxonomy & Ownership) — hashes in §6 |
| Closes on completion | 7A DD-02 (envelope names), DD-03 (registry; INT vs TEXT), DD-22 (compatibility policy); 7B IO-7B-04 (EV-079 envelope and fields), IO-7B-06 (payload names, types and versions) |
| Owner decisions | OD-7C-01 … OD-7C-06 — DECIDED by the owner (§46). OD-7C-07 — **OWNER DECISION REQUIRED** (§46.8) |
| Does not begin | 7D, 7E, 7F, 7G, 7H, 7I, 7J, 7K, 7L |
| Artifact rule | This is the only new or modified project artifact for 7C. No migration, code, Pydantic model, JSON Schema file, OpenAPI, SDK, validator or Redis/Celery artifact is created. Scratch validation runs outside the repository. |

---

## 2. Purpose

7C makes the platform's internal event contract implementation-deterministic. It binds the envelope field names, types and requiredness; the identity, tenant, aggregate, correlation and causation semantics; the V1 schema binding of every durable event EV-001 … EV-105 and of the two consumed Class-D signals (PAY-D-01, PAY-D-02); the EV-079 usage representation; and the meaning, compatibility and rollout rules of the internal `event_version`. It does so without changing any event name, class, owner or count frozen by 7B.

## 3. Scope

- Internal event envelope for durable Classes A, B and C (outbox-backed) and the Class-D signal profile for PAY-D-01 / PAY-D-02.
- Envelope identity (`event_id`), tenant scope (`organization_id`), aggregate identity, occurrence time, correlation and causation.
- Canonical serialization of envelope and payload values (6A §7.5 lineage).
- V1 schema binding for EV-001 … EV-105, PAY-D-01, PAY-D-02 and the EV-079 usage block.
- Internal `event_version` representation, compatibility model, coexistence, rolling deployment, backlog / replay, upcasting and deprecation.
- Schema-registry strategy and its relationship to `analytics.event_schema_versions`.
- Separation of the internal `event_version` from the version axes AX-A … AX-L (API Versioning Strategy §4).

## 4. Non-Goals

- No new, renamed or renumbered event; no change to 7B classes, owners, producers, consumers or counts (EV-001…105, DS-01…19, RTM-01…33, PWH-01…02, PCB-01…03, 19 CURRENT webhook topics, 2 CCPU, 8 FUT, 2 UNW, 3 FAM).
- No change to OD-7B-01 or OD-7B-02. 7C binds representation only.
- No V2 of any event. Every successor shape in this document is labelled **HYPOTHETICAL**.
- No change to the WebSocket envelope (6A §27.3), the webhook envelope (6J §20.1), `X-Platform-Webhook-Version`, `X-Platform-Signature: v1=…` or the canonical signing input.
- Classes E, F, G, H and I are not governed by this envelope.
- No relay, stream, retry, DLQ, consumer-group or retention numbers (7D, 7E, 7G, 7K).
- No PII / sensitivity classification of individual fields beyond the security exclusions (7I).

---

## 5. Authority Model

Authority in 7C is **concern-specific**. Each source is authoritative only for the concern listed against it. No source outranks another outside its own concern, and there is no single ordered precedence list across sources.

| Source | Authoritative for | Not authoritative for |
|---|---|---|
| Executed Phase-5 migrations `001`–`112` (`docs/phase-05-database-design/5K/migrations/`) | Physical schema truth only: tables, column names, types, nullability, defaults, CHECK vocabularies, triggers and function signatures | Event names, classes, owners, payload meaning, compatibility policy, any Phase-7 rule |
| Frozen 7A | Phase-7 standards and invariants (EVT, OUT, REL, RS, IDM, ORD, TEN, SEC, VER, FM, RPL, OBS, DPL) and the items it delegates to 7C (DD-02, DD-03, DD-22) | Physical columns; event taxonomy |
| Frozen 7B | Event taxonomy: names, classes, mechanisms, owners, producers, consumers, payload *meaning* (§24, PAY-D-01/02), the EV-079 contract (§31), IDN / ACC / INV / OCC rules, and OD-7B-01 / OD-7B-02 | Field names, types and versions (delegated to 7C by IO-7B-04 / IO-7B-06) |
| Phase-6 owner documents (6A … 6L, API Versioning Strategy) | Their own domain, API and consumer semantics: 6A §7.5 encoding, WS envelope (6A §27.3), webhook envelope and signature (6J), Billing idempotency and quantities (6K), Analytics projections (6L), and each domain's business meaning | Phase-7 event taxonomy; physical schema where a migration disagrees |
| Closure artifacts (5K execution report / manifest, phase closure notes, 7B reconciliation tables) | Reconciliation, indexing and validation only | Nothing outside what they reconcile; they never override any source above |
| Phase 4 (4A §9.1 DomainEvent, 4B) and Phase 3 (3A §12.4) | Lineage, where not superseded by a concern-owner above | Any concern that a source above already decides |
| OD-7C-01 … OD-7C-06 (§46); OD-7C-07 once decided (§46.8) | Only the exact scope written in each decision | Anything outside that scope |

Rules of application:

1. A question is answered by identifying its concern and reading the one source that owns that concern.
2. Where two sources appear to disagree, the disagreement is resolved by concern ownership, not by document date or sequence. The disagreement is recorded in §49. 7C does not edit the upstream document.
3. 7C binds only what 7A / 7B delegate to it. 7C does not override 7A or 7B.
4. Where the frozen sources left a meaningful choice open, 7C put it to the owner as OD-7C-01 … OD-7C-06. All six are DECIDED (§46). Each applies only within its stated scope. The freeze-gate remediation found one further open choice, the manifest representation of EV-014. It is put to the owner as OD-7C-07 (§46.8) and is not decided.

Correction note: the checkpoint version of this section carried a single numbered precedence table running from the migrations down to Phase 3. That table let a source prevail outside its own concern and is withdrawn. The concern-specific model above replaces it. There is no recency-based precedence anywhere in 7C.

---

## 6. Frozen Input Baseline

Verified at the start of this work (spec §2 gate).

| Item | Expected | Observed | Result |
|---|---|---|---|
| HEAD | `5f5ddec17dc99e49e688cd1827cc83f2c9bcd797` | same; working tree clean | PASS |
| 7A SHA-256 / lines | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` / 1086 | same / 1086 | PASS |
| 7B SHA-256 / lines | `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` / 2207 | same / 2207 | PASS |
| `docs/phase-07-event-architecture/` before 7C | 7A, 7B only | 7A, 7B only | PASS |
| Migrations | 112 files (`001_5B.sql` … `112_5H5.sql`); no `113` | 112; no `113` | PASS |

Cited migrations (read-only):

| Migration | SHA-256 | Cited for |
|---|---|---|
| `001_5B.sql` | `35a2c12ec7bdf68fdc490a6a60824b09c0d56a8851ec2a2c91e68e0f3980ad08` | `set_updated_at()` (`NEW.updated_at = NOW()`): row change time for EV-062 and EV-105 |
| `002_5B.sql` | `53ae74f72f6b73c0b0496fd94644434a51ee417614b9cc65b5b100b453e90dfa` | `identity.sessions.access_token_jti TEXT NULL` (L58) (EV-001 `access_token_jti`) |
| `011_5C.sql` | `54242eabd161453440e47c1e944fb90f2a1e35c3ee52db6447a99ebc3816bd23` | `voice.call_sessions.sessions JSONB` (L27) (EV-007 / EV-008 `session_id`) |
| `029_5E.sql` | `e97e749e7bc28fa38d48ccbc24cd09b44175c1b2ed153f48acd997871a2e6b01` | `campaign.campaigns.scheduling_policy JSONB` (EV-055 `start_at` / `end_at`) |
| `040_5G.sql` | `7e40e372c4d1e5490d107521d3783666aaf81a2351db3f08afd9bffe0f30d1b9` | `workflow.workflow_definitions.updated_at`, trigger `trg_wfd_updated_at` (EV-062 `draft_revision`) |
| `049_5H.sql` | `991ae1c7561afbffac9e1e3ebe368b703b7c49bd35ae12cf11441db241722fb9` | `billing.billing_periods.period_start` / `period_end DATE` (EV-105) |
| `050_5H.sql` | `ada3d087582f04fe48f78d8e9acf42bbe12b34a2ea5a8c2092457c0c91be4367` | `billing.usage_events.quantity NUMERIC(18,4)`; `billing.usage_records` (`billing_period_id`, `metric`, `quantity_used NUMERIC(18,4)`, `updated_at`, `trg_ur_updated_at`) (EV-105) |
| `052_5H.sql` | `e269ee955e9ae1f048b82295c577d1fbe824280c869d25459b9b03433ea9d814` | `billing.quota_configs.soft_limit` / `hard_limit NUMERIC(18,4) NULL`, `unit_label` (EV-105) |
| `065_5I.sql` | `8274167b1ee175ce02933075689280ade474639ed383f02ab013d2520ffb5993` | `plugins.plugin_executions.correlation_id` precedent |
| `068_5J.sql` | `f32d9dc6c0742c2656dd2e9a9677defe0b424c36c7cade5a23a08aef9b394f19` | `analytics.analytics_events`, `analytics.fn_ingest_analytics_event` |
| `070_5J.sql` | `2ca413f41f68f75623a8fb8d812e1aaa5afe1224cc977f35a9443061a60b2863` | `analytics.conversation_turn_stats_daily` |
| `072_5J.sql` | `2ec15fa296e2774eee9f47bb60d62b18a1296b3d40aee7047f58dafdb6f8ff44` | `audit.audit_events.correlation_id` precedent |
| `073_5J.sql` | `586955c138f3c271fa27b13d8b997269a0c3406699e6afe537d4e045aa0c1999` | `analytics.event_schema_versions` DDL |
| `075_5J.sql` | `678ab37141943d27cf6b8bc02c2bb5de8a6892637cb27f8e1655ed0b633860d6` | 25 seed rows, version `'1'`, `ACTIVE` |
| `077_5J1.sql` | `eac7022c4f96993d2e691947d8ebf2fa91ca3db2b9116beaf2c205dd5ee4a990` | `audit.domain_event_outbox` |
| `097_5D5.sql` | `1ebb277a8551b648cec8f085edc0dae5596ad2c54b8b348f58d8323a05f13fe1` | `crm.fn_merge_contacts`: `lead_status` rank (L135 – L143) and field-fill `COALESCE` set (L169 – L180) (EV-028 `field_merge_map`) |
| `100_5G1.sql` | `9b52e7ffac8534faee64f6f9972dc1bc924d95147f3bbc28dd19b30dde2e7f55` | `workflow.fn_publish_workflow(… p_expected_updated_at TIMESTAMPTZ …)` draft-state check (EV-062 `draft_revision`) |
| `102_5H2.sql` | `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` | `usage_events.source_quantity_seconds` (exact-seconds aggregation) |
| `109_5B7.sql` | `a761239d7e63e3d2d982f4dbf7291b81711a24dc051c2577bc44ff46052b0cf3` | `identity.fn_platform_revoke_all_sessions`: revoked-session CAS, outbox payload and audit action (L1116 – L1162) (EV-001) |
| `111_5H4.sql` | `5fe2bc96431236d637dbe2558c0c78d13ab17b7cce647aac3e61db2ac2f4c048` | `billing.fn_is_canonical_usage_metric` (15 canonical metrics, L173 – L198), `billing.fn_resolve_effective_quota` (effective `soft_limit`, L391 – L485; non-canonical metric rejected, L421 – L423) (EV-105) |
| `112_5H5.sql` | `6c3c0e0c546ccfa845822e94781193f6a5516a0176de0ec3bd24449b1abfdb53` | NULL-safe restatement of the same 15 canonical metrics (L137 – L175) (EV-105) |

Other migrations are cited by file and line where a payload field takes its type or CHECK vocabulary from a column (§20).

---

## 7. 7A / 7B Handoff

### 7.1 What 7A delegates to 7C

| 7A item | Delegation (paraphrase of the frozen text) |
|---|---|
| EVT-03 (L289–294) | Every event identifies its type, type-version (the outbox `event_version`, not AX-D), owning aggregate, occurrence time and tenant scope; exact names are 7C's |
| TEN-06 (L593–598) | Tenant field names deferred to 7C |
| VER-03 (L624–631) | "7C MUST define the compatibility policy"; 7A freezes no rule for when the number changes; breaking evolution uses an explicit controlled mechanism defined in 7C |
| VER-07 | No V2 in 7A; INT vs TEXT representation deferred to 7C (F-03 Minor, L1038) |
| OBS-02 (L715–722) | Events are observable by correlation ID and causation ID |
| DD-02 / DD-03 / DD-22 (L934–955) | Envelope names; registry (if any) and INT vs TEXT; compatibility policy |

Rules 7C inherits unchanged and must not weaken: EVT-02 (event_id = outbox id, stable across retries and replay), EVT-04 (payload self-sufficient only as far as the owner's contract states), OUT-01 / OUT-04 / OUT-05 / OUT-07, REL-04, REL-08 (relay never mutates `event_id`, `event_type`, `event_version`, `organization_id` or `payload`), RS-05 (Class D distinguishable; never assumed durable), IDM-02…05, ORD-03 / ORD-04, TEN-01 / TEN-02, SEC-01…09, VER-01 / 02 / 04 / 05 / 06 / 08, FM-11, RPL-01…06, DPL-01…05, ADR-7A-09.

### 7.2 What 7B delegates to 7C

| 7B item | Delegation |
|---|---|
| IO-7B-04 | EV-079 envelope, field names and serialization; inline vs reference-by-ID usage (§31.3 L1423) |
| IO-7B-06 | Field names, types and versions for the §24 payload registry (105 rows) and PAY-D-01 / PAY-D-02 |
| L440 | "7C binds `aggregate_type`" |
| PAY-D-01 (L735) | Whether the agent grain is carried or resolvable from the conversation |
| OCC-07 (§31.7) | Field name and serialization of the EV-079 occurrence time only; meaning fixed by 7B |

---

## 8. Version-Axis Separation

The internal `event_version` is **not** any axis in the API Versioning Strategy (AVS §4). It is a per-`event_type` integer carried by the outbox row (VER-01, VER-08).

| Axis | What it versions | Relationship to internal `event_version` |
|---|---|---|
| AX-A | REST URL major (`/api/v1`) | Independent. An internal version change never requires, implies or is implied by an `/api/v2` (VER-01). |
| AX-D | WebSocket message `version` (6A §27.3) | Independent. AX-D is WebSocket-only (VER-02, VER-08). A Class-F WS message derived from a durable event does not inherit the internal version. |
| AX-E / AX-F | Webhook `version` / `X-Platform-Webhook-Version`; signature scheme `v1=` | Independent and untouched (VER-05, VER-06). |
| Other AVS axes (AX-B, AX-C, AX-G … AX-L) | Their own subjects per AVS §4 | Independent. |

A change to one axis never changes another by implication (AX-R01, AX-R03, AX-R04, AX-R06).

---

## 9. Internal Event Envelope Profiles

7C defines two envelope profiles. Every internal event that 7C governs uses exactly one of them. The profile follows from the event's 7B class; it is never chosen per emission.

| Profile | Covers | Envelope section | `event_id` source | Durable | Carries `durability` |
|---|---|---|---|---|---|
| **DURABLE** | Classes A, B and C: EV-001 … EV-105 (A = 71, B = 1, C = 33; 7B §11) | §10 | Outbox `id` (UUIDv7) | Yes (outbox row) | No |
| **SIGNAL** | Class D signals with a catalogued consumer: PAY-D-01 (DS-17 `conversation.turn_completed`) and PAY-D-02 (DS-19 `tool_execution.*`) | §11 | Producer-generated UUIDv7, once per signal | No (RS-05) | Yes: `"SIGNAL"` |

Not governed by either profile:

| Item | Status |
|---|---|
| Class D DS-01 … DS-16 and DS-18 | No consumer is catalogued in 7B, so no binding is created. If 7B later catalogues a consumer, that signal adopts the SIGNAL profile and receives a V1 binding through a governed 7B + 7C change. |
| Class E (Celery task / command; scheduled trigger) | Not an event envelope. A task message is a command, not a fact. |
| Class F (WebSocket realtime push) | Governed by the WS envelope (6A §27.3, AX-D). §39. |
| Class G (public outbound webhook) | Governed by the webhook envelope (6J §20.1, AX-E / AX-F). §40. |
| Class H (inbound provider callback) | Provider-native. §41. |
| Class I (audit) | Governed by `audit.fn_insert_audit_event()` and the audit schema. The audit log is not the schema registry. |

Rules:

- **PRF-01.** The profile of an event type is fixed by its 7B class: A/B/C → DURABLE; consumed D → SIGNAL.
- **PRF-02.** An event type never has two profiles. A producer never emits the same `event_type` through both the outbox and a direct stream.
- **PRF-03.** Both profiles share the same core metadata names and meanings (§10.2). SIGNAL adds one field, `durability` (OD-7C-06).

---

## 10. Canonical Durable Envelope

### 10.1 Current physical outbox — `audit.domain_event_outbox` (`077_5J1.sql`)

This table records what exists today. It is physical truth and is distinct from the target V1 contract in §10.2.

| Column (line) | Type / default | Envelope relevance |
|---|---|---|
| `id` (L49) | `UUID NOT NULL DEFAULT gen_uuid_v7()`; comment: "doubles as the event's own event_id" | `event_id` |
| `event_type` | `TEXT NOT NULL`; `chk_outbox_event_type_len CHECK (length(event_type) BETWEEN 1 AND 200)` | `event_type` |
| `event_version` (L51) | `INTEGER NOT NULL DEFAULT 1`; comment: "independent of API URL versioning" | `event_version` |
| `organization_id` (L52) | `UUID NULL` (NULL = platform-scoped) | `organization_id` |
| `aggregate_type` (L55) | `TEXT NULL`, free text, no FK; examples `'organization'`, `'compliance_policy'` | `aggregate_type` |
| `aggregate_id` (L58) | `UUID NULL` | `aggregate_id` |
| `payload` (L59, L76) | `JSONB NOT NULL`; `chk_outbox_payload_size CHECK (length(payload::TEXT) <= 262144)` | `payload` |
| `occurred_at` (L60) | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | `occurred_at` |
| `status`, `attempt_count`, `max_attempts` (CHECK 1–20), `available_at`, claim fields, `published_at`, `last_error` | Relay state | Not envelope. Relay bookkeeping (7D). |

Physical facts that 7C does not change:

- **The current outbox has no `correlation_id` column and no `causation_id` column.** OD-7C-04 adds both as future dedicated columns (§10.5). 7C does not create that migration.
- Trigger `trg_outbox_tenant_check` (L104–116) raises if the session tenant context is set and a non-NULL `organization_id` differs from it. A NULL `organization_id` passes.
- Relay functions: `audit.fn_claim_outbox_events`, `audit.fn_mark_outbox_published`, `audit.fn_mark_outbox_failed`.
- No RLS; not partitioned (OUT-07). The table header sizes it for "a handful of event types", not per-turn volume. This is one reason per-turn telemetry is a SIGNAL, not a durable event.
- 6J §37.1's insert example omits `event_version` and `occurred_at` (it relies on defaults) and uses lowercase snake_case `aggregate_type` (`'integration_connection'`). DET-05 and DET-06 make that reliance non-conformant.

### 10.2 V1 durable envelope contract (target)

| # | Envelope field | JSON type (§18) | Required | Nullable | Current physical source | Basis |
|---|---|---|---|---|---|---|
| ENV-01 | `event_id` | UUID (v7) | REQUIRED | NON-NULL | outbox `id` | EVT-02, IDN-01, 077 L49 |
| ENV-02 | `event_type` | string, 1–200, exact 7B canonical name | REQUIRED | NON-NULL | `event_type` | 7B catalogue; 077 CHECK |
| ENV-03 | `event_version` | integer ≥ 1 | REQUIRED | NON-NULL | `event_version` | VER-07; §23 |
| ENV-04 | `organization_id` | UUID | REQUIRED | NULLABLE for EV-001 only; NON-NULL for the other 104 | `organization_id` | TEN-01, TEN-06, 7B L451; §13 |
| ENV-05 | `aggregate_type` | string, lowercase `snake_case` | REQUIRED | NON-NULL | `aggregate_type` (physically NULL-able) | 7B L440; 077 L55; §14 |
| ENV-06 | `aggregate_id` | UUID | REQUIRED | NON-NULL | `aggregate_id` (physically NULL-able) | 077 L58; 4A §9.1; §14 |
| ENV-07 | `occurred_at` | timestamp (§18) | REQUIRED | NON-NULL | `occurred_at` | EVT-03; OCC-01…07; §15 |
| ENV-08 | `payload` | object | REQUIRED | NON-NULL | `payload` | OUT-05; 077 L76; §19 |
| ENV-09 | `correlation_id` | UUID | REQUIRED for rows written after the OD-7C-04 migration is active; absent before | NON-NULL | **none today**; future dedicated column `correlation_id UUID` | OD-7C-04; OBS-02; 3A §12.4; §16 |
| ENV-10 | `causation_id` | UUID | REQUIRED key for rows written after the OD-7C-04 migration is active; absent before | NULLABLE only for a genuine root | **none today**; future dedicated column `causation_id UUID` | OD-7C-04; OBS-02; 4A §9.1; §17 |

The V1 contract is stricter than the physical columns: `aggregate_type` and `aggregate_id` are NULL-able in 077, but every V1 binding requires both, non-null. The stricter contract is enforced by producer validation (§31), not by a new constraint.

### 10.3 Envelope key-set rules

- **KEY-01.** The durable envelope's top-level key set is closed: ENV-01 … ENV-10. A producer emits no other top-level key.
- **KEY-02.** Relay bookkeeping columns (`status`, `attempt_count`, `max_attempts`, `available_at`, claim fields, `published_at`, `last_error`) are never envelope fields. A consumer never reads them to interpret a fact (REL-08; 7D owns them).
- **KEY-03.** A consumer ignores an unknown top-level envelope key and derives no business meaning from it. All business meaning is in `payload`.
- **KEY-04.** The durable envelope never carries `durability`. That key belongs only to the SIGNAL profile (§11).
- **KEY-05.** The relay's wire encoding onto Redis Streams is 7D / 7E's. Whatever encoding they choose must be lossless and must preserve every envelope field name and value in §10.2 exactly.
- **KEY-06.** The internal `event_version` versions the **complete compatibility-relevant contract** of one `event_type` (§23, VRS-08). That contract is the payload schema plus the meaning of every envelope field that affects how the fact is interpreted: organization scope, aggregate identity, occurrence-time meaning and event identity. It does not version relay bookkeeping (KEY-02), Redis stream entry IDs, retry or attempt counters, outbox claim metadata, delivery or publish timestamps, or any other transport-only state (KEY-05). The envelope profile's key set and field names are fixed by this document. A change to the meaning of an interpretation-relevant envelope field is classified by §27.4 like a payload change and can require `event_version` N+1 or a new event type.
- **KEY-07.** Optional envelope addition. A new optional envelope key keeps every current `event_version` only if all four conditions hold: (a) a consumer can ignore the key (KEY-03); (b) an envelope without the key stays valid for consumers: every row written before the key was introduced stays valid without it, and every consumer keeps accepting envelopes with and without it (a producer obligation to populate the key on new rows, such as ENV-09, does not make its absence invalid for a consumer); (c) the key changes the meaning of no existing envelope or payload field; (d) the key exposes no sensitive or PII data that 7I or the owner has not reviewed. If any condition fails, the addition is classified by §27.4. The OD-7C-04 `correlation_id` / `causation_id` addition meets all four: consumers never branch on them (CC-04); rows written before activation keep them absent and stay valid (CC-02); they carry no business meaning and are never dedup, idempotency or ordering keys (CC-05); and they are opaque UUIDs with no PII. It therefore changes no `event_version` and creates no V2. Every consumer accepts envelopes both with and without those keys (§10.5).

### 10.4 Determined rules

| ID | Rule | Basis |
|---|---|---|
| DET-01 | The only renaming between the physical outbox row and the logical envelope is `id` → `event_id`. Every other envelope field keeps its column name. | 077 L49 comment; EVT-02; minimal mapping, no invented vocabulary |
| DET-02 | The vocabulary is `organization_id`. `tenant_id` (4A lineage) is never used in an internal event envelope or payload. | TEN-06; platform vocabulary |
| DET-03 | `organization_id = null` means "explicitly platform-scoped". There is no value meaning "unknown". A producer that cannot determine the organization of an org-scoped event fails its transaction and emits nothing. For the 104 org-scoped events `null` is a contract violation. | TEN-01 ("absent ≠ unknown"); 7B L451 |
| DET-04 | `organization_id` is taken from the trusted producing transaction (the owning row or the authenticated context), never from client input and never from a payload field. A payload field that repeats an organization is informational and is never an authorization input. Consumers verify any referenced resource against the envelope `organization_id`. | TEN-02; 7B §31.1 Scope |
| DET-05 | Producers write `event_version` explicitly on every insert. Relying on the column default `1` is non-conformant, because after a future version change a defaulted insert would silently emit the old version. | VER-04; DPL-05 |
| DET-06 | Producers write `occurred_at` explicitly with the business occurrence time the binding states (§15, §20). The column default `NOW()` is not an acceptable source for any event. For EV-079 it is always the persisted service-end time; recovery `now()`, worker time, Redis delivery time and relay publish time are forbidden. | EVT-03; OCC-01…07 |
| DET-07 | `event_version` is canonically an integer (the executed outbox type). TEXT is a projection used only where a physical TEXT column requires it (Analytics). §23, §24. | 077 L51 (INTEGER); 068 L29 (TEXT); VER-07 / F-03 |
| DET-08 | `event_type` never carries a version suffix. The version is carried only by `event_version`. | VER-01; VER-04 |
| DET-09 | The relay publishes the envelope fields and payload exactly as committed. It never regenerates `event_id`, never re-stamps `occurred_at`, never rewrites `event_version`, never adds or rewrites `correlation_id` / `causation_id` and never edits `payload`. Replay re-delivers the committed row unchanged. | REL-08; RPL-05; EVT-02 |
| DET-10 | Envelope and payload values use the canonical serialization types of §18 (6A §7.5 lineage). | 6A §7.5 |
| DET-11 | PAY-D-01 carries `agent_id`. The Analytics grain is `agent_id NOT NULL` and Analytics never reads Voice-owned tables, so the agent grain cannot be "resolvable from the conversation" at the consumer. | 6L L113, L340, L384; 7B L735 |
| DET-12 | EV-079 carries the AI-duration total as exact seconds (a `NUMERIC(18,4)` decimal string), never as pre-rounded minutes. Conversion to the `AI_MINUTES` unit is Billing's (the 6K catalogue owns the unit). Pre-rounding at the producer would reproduce the FB-6K-06 defect. | 6K FB-6K-06, DEC-6K-02; 102_5H2; 6K L1912; OD-7C-05 |
| DET-13 | EV-079 `occurred_at` equals the persisted service-end time. The payload's `completed_at` equals `occurred_at` by invariant. A mismatch is a contract violation. | OCC-01, OCC-06, OCC-07 |
| DET-14 | Counts (tokens, characters, turns, rows, attempts) are non-negative JSON integers. Precision-sensitive durations and quantities are decimal strings at the owning column's scale. JSON floating-point numbers are never used for money, durations or usage quantities. | 6K `quantity NUMERIC(18,4)`; 6A §7.5 money-string rationale; OD-7C-05 |
| DET-15 | `analytics.event_schema_versions` stays an Analytics-owned registry. 7C does not repurpose it as a platform-wide registry and does not register the 105 durable events in it. | 073/075; OD-7C-03 |
| DET-16 | `analytics.fn_ingest_analytics_event` does not validate the version. Any version check on the Analytics path is the consumer adapter's job, not the function's. | 068 L89–106 |
| DET-17 | DEP-6K-05 stays OPEN. 7C invents no discriminator on EV-100. EV-100's LLM-token fields carry only standalone-attributable usage, per 6K §23.3 and 7B FND-04. Whether the workflow runtime can tell in-turn from standalone execution is a 6E / 6I producer dependency, not a 7C representation gap. | 6K L2020, L2868; 7B L1687, FND-04 |
| DET-18 | The WS envelope (`event_id, event_type, version, timestamp, organization_id, resource_id, sequence, payload`) and the webhook envelope (`id, type, version, occurred_at, organization_id, data.object, request_id`), `X-Platform-Webhook-Version`, `X-Platform-Signature: v1=…` and the signing input `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")` are unchanged. No `v2=` scheme exists. | VER-05, VER-06; 6A §27.3; 6J §20.1, §21.1 |
| DET-19 | Internal events never contain the excluded content listed in §19.3. Opaque, non-secret references are permitted only where the frozen contracts permit them. Adding a sensitive or PII field is never a harmless additive change; it routes to 7I first. | SEC-01…09; 7B PAY-D exclusions |
| DET-20 | Classes E, F, G, H and I are outside this envelope. | 7A classes |

### 10.5 Correlation and causation persistence (OD-7C-04)

| Phase | Physical state | Envelope | Rule |
|---|---|---|---|
| **Current** (today) | No `correlation_id` / `causation_id` columns in `audit.domain_event_outbox` | Both keys absent | Producers never place either value in `payload`, never invent a stand-in key, and never fabricate a value. |
| **Target** (after the future migration is active) | Dedicated columns `correlation_id UUID` and `causation_id UUID` on `audit.domain_event_outbox` | Both keys present on every newly written row | `correlation_id` is non-null for every new row. `causation_id` is non-null except for a genuine root (§17). |

- **CC-01.** 7C does not author the migration. It is IO-7C-01 for the Phase-5 migration owner. The columns stay physically NULL-able so that rows written before activation remain valid. The mechanism that enforces non-null `correlation_id` on new rows (constraint, trigger or producer validation) is chosen by the migration owner.
- **CC-02.** Rows written before activation keep both keys absent for their whole life. Replay never back-fills them (RPL-05).
- **CC-03.** The relay propagates both columns unchanged into the published envelope once they exist (IO-7C-01). It never derives, overwrites or back-fills them.
- **CC-04.** A consumer never rejects an event, and never branches its business logic, on the presence, absence or value of `correlation_id` or `causation_id`. They are observability fields (OBS-02).
- **CC-05.** Neither field is ever used as a dedup key, idempotency key or ordering key (ORD-03).
- **CC-06.** No `command_id` is introduced. No existing identifier is renamed to act as one.

### 10.6 Durable envelope example (V1, after correlation / causation activation)

```json
{
  "event_id": "01923f4e-7c2a-7b10-9a3e-5d6f7a8b9c0d",
  "event_type": "contact.created",
  "event_version": 1,
  "organization_id": "01923f4e-6a11-7c22-8d33-9e44f5a6b7c8",
  "aggregate_type": "contact",
  "aggregate_id": "01923f4e-7b01-7d02-8e03-9f04a5b6c7d8",
  "occurred_at": "2026-08-21T09:15:30.123456Z",
  "correlation_id": "01923f4e-7a00-7000-8000-000000000001",
  "causation_id": null,
  "payload": { "...": "per the EV-021 binding in §20" }
}
```

In this example the contact is created inside an API request, so `correlation_id` is that request's `request_id` (COR-Q) and `causation_id` is `null` (a genuine root). Before activation the same event carries neither key. §16.3 gives the API-rooted Voice, Voice-rooted and background correlation examples.

---

## 11. Class-D Signal Envelope

The SIGNAL profile (OD-7C-06) uses the same core metadata names and meanings as §10.2 plus one field, `durability`.

| # | Field | JSON type | Required | Nullable | Value / source |
|---|---|---|---|---|---|
| SIG-01 | `event_id` | UUID (v7) | REQUIRED | NON-NULL | Generated by the producer, once per signal (§12.2) |
| SIG-02 | `event_type` | string | REQUIRED | NON-NULL | `conversation.turn_completed` (PAY-D-01) or a `tool_execution.*` member (PAY-D-02; §21) |
| SIG-03 | `event_version` | integer ≥ 1 | REQUIRED | NON-NULL | `1` |
| SIG-04 | `organization_id` | UUID | REQUIRED | NON-NULL | Organization of the conversation |
| SIG-05 | `aggregate_type` | string | REQUIRED | NON-NULL | `conversation` (PAY-D-01) / `tool_execution` (PAY-D-02) |
| SIG-06 | `aggregate_id` | UUID | REQUIRED | NON-NULL | `conversation_id` (PAY-D-01) / tool execution id (PAY-D-02) |
| SIG-07 | `occurred_at` | timestamp | REQUIRED | NON-NULL | Business time of the signal (§21) |
| SIG-08 | `correlation_id` | UUID | REQUIRED | NON-NULL | The call's established root correlation (§16, rule COR-C): the inherited root for an API- or campaign-rooted call; `call_id` only for a Voice-rooted call (COR-V) |
| SIG-09 | `causation_id` | UUID | REQUIRED | NON-NULL | The `turn_id` of the turn that produced the signal (§17) |
| SIG-10 | `durability` | enum, closed: `SIGNAL` | REQUIRED | NON-NULL | Always the literal `"SIGNAL"` |
| SIG-11 | `payload` | object | REQUIRED | NON-NULL | Per §21 |

Rules:

- **SIG-R01.** `correlation_id` and `causation_id` are required from SIGNAL V1. They do not depend on any database column, because the SIGNAL profile has no outbox row.
- **SIG-R02.** `durability = "SIGNAL"` marks the profile only. The class and mechanism of every event type come solely from the frozen 7B registry. `durability` never reclassifies an event: a producer cannot make a signal durable, or a durable event a signal, by setting or omitting it. A SIGNAL envelope whose `event_type` is not a 7B Class-D type, or a durable envelope that carries `durability`, is a contract violation.
- **SIG-R03.** A SIGNAL is published after the producing commit, with no outbox row. It can be lost. No consumer relies on it for a financial, compliance or durable business outcome (RS-05; OD-7B-01 made EV-079 the only Billing source for conversation usage).
- **SIG-R04.** Transport (Redis Streams direct or lighter-weight internal pub/sub, per 6D §24.1–24.2), stream names, trimming and consumer groups belong to 7D / 7E. The encoding must be lossless and name-preserving for every field above.
- **SIG-R05.** The top-level key set is closed: SIG-01 … SIG-11. A consumer ignores an unknown top-level key.
- **SIG-R06.** The only consumer of PAY-D-01 and PAY-D-02 is Analytics (7B §15.1). Billing does not consume either.

---

## 12. Event Identity

### 12.1 Durable `event_id`

- **ID-01.** `event_id` is the outbox row's `id`, a UUIDv7 assigned once at insert, either by the column default `gen_uuid_v7()` or by the producer in the same insert. It is never reassigned (EVT-02, IDN-01).
- **ID-02.** It is stable across relay retry, Redis redelivery, consumer retry and replay. Every delivery of the same fact carries the same `event_id`.
- **ID-03.** It identifies one fact, not one delivery. It is **not**:
  - the Redis stream entry ID (`<ms>-<seq>`), which is transport position and changes if the relay republishes;
  - a delivery ID, delivery attempt number or consumer-group pending-entry ID;
  - the API `request_id`;
  - `correlation_id` or `causation_id`;
  - `aggregate_id`;
  - a Celery task ID, an Analytics row ID, a `billing.usage_events` row ID or a webhook delivery ID;
  - the `event_id` field of a Class-F WebSocket message, which is a separate identifier governed by 6A §27.3.
- **ID-04.** Billing derives `source_event_id` from `event_id`: the plain `event_id` for single-metric events, and `<outbox_event_id>:<METRIC>` for EV-079 (IDN-05; 6K L1961).
- **ID-05.** Dedup by `event_id` is at-least-once safe (IDN-06). Business-key dedup is 7F / 7G's (IDN-09).
- **ID-06.** EV-079 is emitted once per finalization generation (IDN-10). A second emission for the same generation is prevented by the finalization guard (IDN-11, IO-7B-16), not by 7C.

### 12.2 SIGNAL `event_id`

- **ID-07.** A SIGNAL `event_id` is a UUIDv7 generated by the producer once per signal, before the first publish attempt.
- **ID-08.** It is not an outbox ID (there is no outbox row), not a Redis stream entry ID and not a delivery ID.
- **ID-09.** A producer that re-attempts the publish of the same signal reuses the same `event_id`. A new signal always gets a new `event_id`.
- **ID-10.** Derivation of the Analytics `dedup_key` from a signal's `event_id` is 7F's. 7C guarantees only that the `event_id` is stable per signal.

---

## 13. Tenant Scope

- **TEN-C01.** The tenant field is `organization_id` in every envelope and payload. `tenant_id` is never used (DET-02).
- **TEN-C02.** EV-001 `identity.forced_revocation_required` is the only event whose `organization_id` may be `null`, and `null` there means the revocation is explicitly platform-scoped (7B L451, L1070, L1903). It never means "unknown".
- **TEN-C03.** The other 104 durable events and both SIGNAL events carry a non-null `organization_id`.
- **TEN-C04.** `organization_id` comes from the trusted producing transaction (DET-04). The `trg_outbox_tenant_check` trigger rejects a non-null value that differs from the session tenant context.
- **TEN-C05.** An organization value inside a payload (for example EV-002 `organization_id`) is informational. It is never an authorization input. Consumers authorize against the envelope `organization_id` and verify every referenced resource against it (TEN-02).
- **TEN-C06.** EV-030 `suppression.added` and EV-031 `contact.suppression_lifted` are organization-scoped events. `crm.contact_suppressions` also holds `PLATFORM` and `REGULATORY` rows with `organization_id IS NULL` (`chk_sup_scope_org_id`, 024 L82). Because only EV-001 may be platform-scoped (7B), EV-030 / EV-031 are emitted only for `scope = 'ORG'` rows. Platform and regulatory suppressions produce no durable event in V1. This is recorded as a Minor finding (§51), not a change to 7B.

---

## 14. Aggregate Identity

- **AGG-01.** `aggregate_type` is lowercase `snake_case`, singular, and names the owning domain entity. It matches `^[a-z][a-z0-9_]*$`.
- **AGG-02.** `aggregate_id` is the UUID primary key of that entity's owning row.
- **AGG-03.** There is no generic `resource_id` in the internal envelope. (`resource_id` exists only in the WS envelope, which 7C does not govern.)
- **AGG-04.** `aggregate_type` and `aggregate_id` are REQUIRED and NON-NULL in every V1 binding (§10.2).
- **AGG-05.** The aggregate names the entity whose state change is the fact, not the entity that caused it. Referenced entities go in the payload.

V1 aggregate bindings (all 105 durable events and both SIGNAL events):

| Events | `aggregate_type` | `aggregate_id` = |
|---|---|---|
| EV-001 | `user` | `identity.users.id` (`user_id`) |
| EV-002 | `organization` | `organizations.id` |
| EV-003 | `compliance_policy` | `compliance_policies.id` |
| EV-004 … EV-008 | `call_session` | `voice.call_sessions.id` (`call_id`) |
| EV-009 | `recording` | `voice.recordings.id` |
| EV-010 … EV-013 | `agent` | `voice.agents.id` |
| EV-014 | `tool_definition` | `voice.tool_definitions.id` |
| EV-015 … EV-018 | `knowledge_base` | `knowledge.knowledge_bases.id` |
| EV-019 … EV-020 | `document` | `knowledge.documents.id` |
| EV-021 … EV-029 | `contact` | `crm.contacts.id` |
| EV-030 … EV-031 | `suppression` | `crm.contact_suppressions.id` |
| EV-032 | `consent` | `crm.consent_records.id` |
| EV-033 … EV-034 | `company` | `crm.companies.id` |
| EV-035 … EV-039 | `deal` | `crm.deals.id` |
| EV-040 | `activity` | `crm.activities.id` |
| EV-041 … EV-043 | `task` | `crm.tasks.id` |
| EV-044 … EV-045 | `note` | `crm.notes.id` |
| EV-046 … EV-051 | `appointment` | `crm.appointments.id` |
| EV-052 … EV-059 | `campaign` | `campaign.campaigns.id` |
| EV-060 | `import_job` | `campaign.csv_import_jobs.id` |
| EV-061 … EV-064 | `workflow` | `workflow.workflow_definitions.id` |
| EV-065 | `integration_connection` | `integrations.integration_connections.id` |
| EV-066 | `webhook_endpoint` | `webhooks.webhook_endpoints.id` |
| EV-067 … EV-070 | `plugin_installation` | `plugins.plugin_installations.id` |
| EV-071 | `subscription` | `billing.subscriptions.id` |
| EV-072 | `integration_connection` | `integrations.integration_connections.id` |
| EV-073 … EV-075 | `call_session` | `voice.call_sessions.id` (`call_id`) |
| EV-076 … EV-079 | `conversation` | `voice.conversations.id` |
| EV-080 | `knowledge_base` | `knowledge.knowledge_bases.id` |
| EV-081 … EV-082 | `document` | `knowledge.documents.id` |
| EV-083 | `contact` | `crm.contacts.id` |
| EV-084 … EV-086 | `campaign` | `campaign.campaigns.id` |
| EV-087 … EV-094 | `campaign_contact` | `campaign.campaign_contacts.id` |
| EV-095 … EV-096 | `import_job` | `campaign.csv_import_jobs.id` |
| EV-097 | `campaign` | `campaign.campaigns.id` |
| EV-098 | `campaign_contact` | `campaign.campaign_contacts.id` |
| EV-099 … EV-101 | `workflow_execution` | `workflow.workflow_executions.id` |
| EV-102 … EV-103 | `invoice` | `billing.invoices.id` |
| EV-104 | `payment_attempt` | `billing.payment_attempts.id` |
| EV-105 | `organization` | `organizations.id` (the envelope `organization_id`) |
| PAY-D-01 | `conversation` | `voice.conversations.id` |
| PAY-D-02 | `tool_execution` | `voice.tool_executions.id` |

For EV-087 … EV-094 and EV-098 the envelope aggregate is the `campaign_contacts` row. The payload still carries `campaign_id` and `contact_id` as 7B §24 states.

---

## 15. Occurrence Time

### 15.1 Format

- **OCC-C01.** `occurred_at` and every payload timestamp are RFC-3339 UTC strings with a `Z` suffix and **exactly six fractional digits**: `YYYY-MM-DDTHH:MM:SS.ffffffZ`, for example `2026-08-21T09:15:30.123456Z`. Regex: `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$`.
- **OCC-C02.** A value whose microsecond part is zero is still written with six digits (`…:30.000000Z`). Producers format explicitly; a library default that drops or shortens the fraction is non-conformant.
- **OCC-C03.** **Parsing capability is not conformance.** A consumer's parser may be able to read 0–9 fractional digits, a numeric offset or a missing fraction. That capability never makes such a value conformant. A value with other than exactly six fractional digits, or without the `Z` suffix, is non-conformant. Producer validation rejects it before commit. Consumer validation treats it as a contract violation before any side effect. No component truncates, pads, rounds or re-zones a non-conformant value to make it pass.
- **OCC-C04.** Reason for six digits: `TIMESTAMPTZ` stores microseconds; `occurred_at` is part of Billing's `uq_ue_idempotency` key; and OCC-06 requires a reconciliation re-read to yield the same value. A millisecond value would differ from the persisted time. 6A §7.5's `.123Z` is a format example, not a precision rule.

### 15.2 Source

- **OCC-C05.** `occurred_at` is the business time of the fact, captured once by the producer and written explicitly (DET-06).
- **OCC-C06.** Where the owning row has a dedicated business-time column for the transition, `occurred_at` equals that column's persisted value. Examples: `answered_at`, `ended_at`, `converted_at`, `won_at`, `lost_at`, `completed_at`, `paid_at`, `published_at`, `connected_at`, `disconnected_at`, `installed_at`, `activated_at`, `suspended_at`, `uninstalled_at`, `lifted_at`, `recorded_at`, `cancelled_at`, `started_at`, `deleted_at`.
- **OCC-C07.** Where there is no dedicated column, `occurred_at` equals the owning row's `created_at` (creation facts) or `updated_at` (change facts) as written in the same transaction. The value is captured once and reused for the column and the envelope, so the two are equal.
- **OCC-C08.** The per-event source is stated in each §20 binding. A payload timestamp that carries the same instant as `occurred_at` (for example `ended_at` in EV-005) equals it exactly.
- **OCC-C09.** `occurred_at` is never the relay publish time, Redis delivery time or consumer receive time. It is never the column default `NOW()` by omission.
- **OCC-C10.** `occurred_at` is not an ordering key across aggregates (ORD-03). Consumers tolerate reordering (ORD-04).

### 15.3 EV-079 occurrence time

- **OCC-C11.** EV-079 `occurred_at` is the persisted service-end time of the conversation (7B OCC-01 … OCC-07). Its field name is `occurred_at` in the envelope and `completed_at` in the payload. The two are equal (DET-13).
- **OCC-C12.** It is never worker time, recovery `now()`, Redis time or relay time. A recovery path reads the persisted service-end time. It does not stamp a new one.
- **OCC-C13.** If the persisted service-end time is unavailable, no EV-079 is emitted, no synthetic timestamp is created and no Billing side effect occurs. Persisting the service-end time for the recovery path is IO-7C-10.

---

## 16. Correlation Semantics

`correlation_id` is the identity of the **root** of a flow (OD-7C-04). It is established once, at the root, and propagates unchanged to every later hop. No hop replaces an established root (P1-7C-01, §51.1).

### 16.1 Root precedence

The canonical precedence is:

1. An existing **trusted** root `correlation_id` propagates unchanged.
2. Otherwise, if the Voice call session itself is the root, that call's identity is established as the root once.
3. Otherwise, a genuine background or scheduled root mints one UUIDv7 once and persists and propagates it.

"Trusted" means platform-produced: the `correlation_id` of a committed envelope, a value carried by a platform-enqueued task, a value persisted with a platform work item or call session, or the server-assigned `request_id` (6A entry middleware). A client-supplied header or provider-supplied value is never a trusted root.

Selection rules, applied in this order (first match wins):

| Rule | Precedence step | Context | `correlation_id` |
|---|---|---|---|
| **COR-P** | 1 | A producer handling a consumed durable event or SIGNAL | The consumed event's `correlation_id`, unchanged |
| **COR-T** | 1 | A worker executing a task or persisted work item that carries a root (`campaign.call_jobs`, an import job, a reindex job, a platform-enqueued task) | The carried root, unchanged |
| **COR-C** | 1 | Call-scoped work on an existing call session: the Voice runtime, provider status callbacks for that call, the post-call and accounting-finalization workers, the recovery reaper, and every event or signal on aggregates `call_session`, `conversation`, `recording` (EV-004 … EV-009, EV-073 … EV-079, PAY-D-01, PAY-D-02) | The root established when that call session was created (COR-Q, COR-T or COR-V) and persisted and carried with the call (IO-7C-01). It is never re-derived from `call_id` for a call whose root was inherited. |
| **COR-Q** | 1 | A producer inside a platform API request, with no match above | That request's server-assigned `request_id` (6A: `meta.request_id`; UUIDv7) |
| **COR-V** | 2 | A new call session created with no upstream root: an inbound provider event that starts a call | The new call session's `call_id` (`voice.call_sessions.id`), established once when the call session is created and persisted as the call's root |
| **COR-B** | 3 | A genuine background or scheduled root: no request, no consumed event, no carried root, not a call | One UUIDv7 minted once when the root work item is created, persisted with it and propagated; every retry reuses it |

A provider callback is not a trusted root (it is external input). A provider callback for an existing call is call-scoped work and takes COR-C. A provider callback that starts a new call takes COR-V.

### 16.2 Rules

- **COR-01.** The root never changes along a flow. No hop regenerates, replaces or re-derives it. A consumer that emits a follow-on event copies the consumed value (COR-P). A worker copies the carried value (COR-T). An intermediate hop never mints a new one.
- **COR-02.** `call_id` never overwrites an established root. For a Voice-rooted call (COR-V) `correlation_id` equals `call_id`, and for its `call_session` aggregates also `aggregate_id`. For an API-rooted or campaign-rooted call, `correlation_id` is the inherited root, which differs from `call_id`. In every case `call_id` stays available as `aggregate_id` (call-session aggregates) and as the `call_id` payload / call-reference field. They remain separate fields with separate meanings.
- **COR-03.** The link from the context that started a call (API request, campaign call job, inbound callback) to the call is carried by EV-004's `causation_id` (§17). It is not carried by changing the root.
- **COR-04.** Persisting the root with the call session and with every root work item, and carrying it on tasks (COR-C, COR-T, COR-V, COR-B), are implementation obligations (IO-7C-01). 7C creates no column, table or migration for them.
- **COR-05.** `correlation_id` is for observability only (OBS-02; CC-04). It is never an authorization input, dedup key or ordering key.
- **COR-06.** Before the OD-7C-04 migration is active, durable envelopes carry no `correlation_id` (§10.5). SIGNAL envelopes carry it from V1.
- **COR-07.** Activation transition. A consumer handling a durable event that carries no `correlation_id` (committed before activation) uses that consumed event's `event_id` as the root for its follow-on events. This is deterministic across retries and replay, and it is never regenerated.
- **COR-08.** A campaign-rooted call inherits the root of the campaign work that created its `campaign.call_jobs` row (COR-T). If a scheduled dispatcher created the job with no upstream root, COR-B mints the root once for that job. No call gets a new correlation per call.

### 16.3 Examples

**API-rooted Voice flow.** A client calls 6D-001; the entry middleware assigns `request_id` = `A`.

| Hop | Event / signal | Rule | `correlation_id` | `causation_id` | `call_id` |
|---|---|---|---|---|---|
| API request creates the call | EV-004 `call.initiated` | COR-Q | `A` | `null` (CAU-R) | `C` (in `aggregate_id` and payload) |
| Call processing (provider status callback / Voice runtime) | EV-073 `call.answered`, EV-074 `call.conversation_started` | COR-C | `A` | per §17 | `C` |
| Conversation turns | PAY-D-01 `conversation.turn_completed` | COR-C | `A` | `turn_id` (SIG-09) | `C` (payload) |
| Call ends | EV-005 `call.ended` | COR-C | `A` | per §17 | `C` |
| Accounting-finalization worker | EV-079 `conversation.completed` | COR-C | `A` | per §17 | `C` (payload) |
| A consumer worker handling EV-005 or EV-079 emits a follow-on durable event | any follow-on event | COR-P | `A` | the consumed `event_id` (CAU-E) | as bound in that event's payload |

Every hop carries `correlation_id` = `A`. `call_id` = `C` is never substituted for `A`.

**Voice-rooted flow.** An inbound provider event arrives with no upstream root. The call session `C` is created and its root is established once as `C` (COR-V). EV-004 carries `correlation_id` = `C` and `causation_id` = the callback dedup row ID (CAU-04). Every later event and signal of that call carries `C` through COR-C, and every follow-on event carries `C` through COR-P.

**Background flow.** A scheduled job whose work item already carries a root (for example, a campaign job created inside a request) keeps that root (COR-T). A scheduled job with no upstream root mints one UUIDv7 `B` once, when the work item is created, and persists it with the item (COR-B). Every retry of that item reuses `B`. Every event it emits, and every call it creates (COR-08), carries `B`.

Lineage: 3A §12.4 (L884) sets `correlation_id` "= request ID for API calls, call/session ID for voice" at the entry middleware. 6A L656 / L675 make the request ID the correlation ID and describe it as "reused as the call/session correlation ID" for voice. The precedence above is consistent with both: an API-rooted call keeps the request's ID, and the call/session ID is the root only when the call itself is the root. The reconciliation is recorded in §49 (CNF-7C-02).

---

## 17. Causation Semantics

`causation_id` identifies the **immediate** cause of this fact (OD-7C-04): the causing `event_id`, or a stable ID of the causal work item.

Selection rules, applied in this order (first match wins):

| Rule | Context | `causation_id` |
|---|---|---|
| **CAU-E** | The producer is handling a consumed durable event or signal | The consumed `event_id` |
| **CAU-W** | The producer is executing a persisted work item | That work item's stable ID: a job row (`campaign.csv_import_jobs.id`, `knowledge.kb_reindex_jobs.id`, `knowledge.ingestion_jobs.id`, `campaign.call_jobs.id`), the Class-H callback dedup row ID, or for the Voice runtime the `call_id`, or for a SIGNAL the `turn_id` |
| **CAU-R** | A genuine root inside a request or ingress, with no prior cause | `null` |

Rules:

- **CAU-01.** `causation_id` is `null` only under CAU-R. Every non-root event after activation has a non-null value.
- **CAU-02.** It names the immediate cause only. It is not the root (that is `correlation_id`) and not a chain.
- **CAU-03.** It is never used for dedup, idempotency or ordering (CC-05).
- **CAU-04.** EV-004 `call.initiated`: `null` when initiated inside an API request (6D-001); the `call_jobs.id` for a campaign call; the callback dedup row ID for an inbound call.
- **CAU-05.** SIGNAL events carry `causation_id` = `turn_id` from V1 (SIG-09).
- **CAU-06.** The per-producer causation source is materialized in the schema manifest (IO-7C-02). No producer fabricates a causation value.
- **CAU-07.** Before the OD-7C-04 migration is active, durable envelopes carry no `causation_id` (§10.5).

---

## 18. Canonical Serialization Types

Every envelope and payload value uses exactly one of these types. The §20 / §21 / §22 bindings name the type for every field.

| Type | JSON form | Canonical rule | Example |
|---|---|---|---|
| UUID | string | Lowercase, hyphenated, 36 characters (RFC 9562 text form). Regex `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`. Envelope `event_id` is v7. | `"01923f4e-7c2a-7b10-9a3e-5d6f7a8b9c0d"` |
| timestamp | string | RFC-3339 UTC, `Z`, exactly six fractional digits (§15.1) | `"2026-08-21T09:15:30.123456Z"` |
| date | string | `YYYY-MM-DD`, from a PG `DATE` column; no time, no zone. Regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` | `"2026-09-01"` |
| string | string | UTF-8. Length limits follow the owning column where one exists | `"Acme"` |
| integer | number | JSON integer literal: no fraction, no exponent, no leading `+`, no leading zeros. Range follows the owning column (`INTEGER` 32-bit signed, `BIGINT` 64-bit signed). Consumers parse it into an integer type, never a float. Counts are ≥ 0. | `42` |
| decimal | string | Base-10 string at the **owning column's scale exactly**: `NUMERIC(18,4)` → 4 fractional digits; `NUMERIC(8,2)` / `NUMERIC(5,2)` → 2; `NUMERIC(4,3)` → 3. No exponent, no `+`, no superfluous leading zeros, no `-0`. Non-negative where the binding says so. | `"93.2500"` |
| boolean | boolean | JSON `true` / `false` only | `true` |
| enum | string | Exact, case-sensitive value from a declared vocabulary. Where a DB `CHECK` exists, the vocabulary is exactly that CHECK set. An enum is **closed** unless its binding declares it OPEN. | `"COMPLETED"` |
| array | array | Declared element type. An array declared as a *set* is emitted sorted ascending by canonical string form, with no duplicates. An array declared as a *list* keeps producer order. | `["phone","email"]` |
| object | object | Declared keys only, each with its own type, requiredness and nullability (applied recursively) | `{"total":"93.2500"}` |
| null | `null` | Allowed only for a NULLABLE field. Means "explicitly no value", never "unknown" | `null` |
| money | object | `{"amount": "<decimal, scale 4>", "currency": "<ISO-4217, 3 uppercase letters>"}`. A nullable money field is `null` as a whole, never an object with a null member. | `{"amount":"1234.5000","currency":"INR"}` |
| phone | string | E.164. Regex `^\+[1-9][0-9]{1,14}$`. Always a [7I] field. | `"+919876543210"` |

Rules:

- **SER-01.** **Required / optional** and **nullable / non-null** are separate dimensions. REQUIRED means the key is always present. OPTIONAL means the key may be absent. NULLABLE means the value may be `null`. NON-NULL means it may not. A REQUIRED NULLABLE field is always present and may be `null`. An OPTIONAL NON-NULL field is either absent or carries a value.
- **SER-02.** Absence and `null` are distinct. A consumer never treats an absent OPTIONAL field as `null` or `null` as absent.
- **SER-03.** JSON floating-point numbers are never used for money, durations, usage quantities or any precision-sensitive value (DET-14).
- **SER-04.** Keys are lowercase `snake_case`. Duplicate keys are invalid.
- **SER-05.** Precision-sensitive durations are decimal seconds (`…_seconds`). Latencies from `INTEGER` millisecond columns are integers with a `_ms` suffix.
- **SER-06.** All V1 fields in §20 – §22 are REQUIRED. OPTIONAL is reserved for compatible additions under §28.

---

## 19. Payload Boundary

### 19.1 Size and shape

- **PAY-01.** `payload` is a JSON object (never an array, string or `null`).
- **PAY-02.** The committed payload satisfies the executed CHECK `length(payload::TEXT) <= 262144`. In addition, the producer's canonical JSON encoding of `payload` is at most 262144 bytes of UTF-8. The byte limit is never looser than the CHECK.
- **PAY-03.** No full aggregate snapshot by default. A payload carries the identifiers and changed facts its binding lists. Related entities are referenced by ID, never embedded.
- **PAY-04.** A payload never repeats envelope metadata unless its binding lists the field (for example EV-002 `organization_id`, EV-079 `completed_at`). Payload keys never include `event_id`, `event_type`, `event_version`, `correlation_id`, `causation_id` or `durability`, and no payload key begins with `_`.
- **PAY-05.** A payload value never grants authority. Organization values in a payload are never authorization inputs (TEN-C05).

### 19.2 Self-sufficiency

- **PAY-06.** A payload is self-sufficient only as far as the owner's contract states (EVT-04). A consumer that needs more reads it through the owner's API, never by reaching into another domain's tables.

### 19.3 Security exclusions

Internal event payloads and envelopes never contain:

- access or refresh tokens;
- API secrets, provider credentials or signing secrets;
- secret-manager values;
- signed or presigned URLs;
- raw media;
- transcript or raw utterance text;
- raw provider callback payloads;
- card data.

Opaque, non-secret references are allowed only where the frozen contracts permit them (SEC-01; for example `credential_ref`, `signing_secret_ref`). No V1 binding in §20 – §22 carries one.

A new sensitive or PII field is not automatically compatible because it is optional. It is classified `PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW` (§27) and needs 7I review first. V1 fields that 7B marks [7I] are bound by type in §20 and carry a [7I] handoff note. 7C does not decide their sensitivity.

---

## 20. V1 Durable Schema Registry

This section binds the V1 payload schema of every durable event EV-001 … EV-105 (IO-7B-06). It is the normative V1 source under OD-7C-03; the code-owned manifest (IO-7C-02) is materialized from it later. Every binding here is `event_version = 1`. There is no V2 of any event.

### 20.1 Binding rules

| ID | Rule |
|---|---|
| REG-01 | Every binding states: EV ID, exact 7B `event_type`, class, `event_version` = `1`, `aggregate_type`, `aggregate_id` semantics, organization scope, `occurred_at` source, lineage, [7I] note, compatibility note, and a field table giving for every field its name, JSON type (§18), requiredness, nullability and unit / enum / source. |
| REG-02 | Every V1 field is REQUIRED (SER-06). NULLABLE fields are always present and may be `null`. |
| REG-03 | Nullability follows the owning column. A field sourced from a physically NULL-able column is NON-NULL only when the transition the event records necessarily sets that column (for example `ended_at` on EV-005, `won_at` on EV-037); the binding says so ("set by this transition") and producer validation (§31) enforces it. |
| REG-04 | A field marked **(non-physical)** is a value the producer holds in the producing transaction but that is not a column of the owning row (a previous value, an actor, a count, a declared kind). The producer computes it once; replay re-delivers the committed value (RPL-05). No non-physical field is a stand-in for `correlation_id` or `causation_id` (§10.5). |
| REG-05 | Actor fields named `*_by` are UUID, NULLABLE: the acting user's `identity.users.id`, `null` when the actor is not a user (AI agent, system, worker). An actor field sourced from a NOT NULL column is NON-NULL (EV-063 `published_by`). |
| REG-06 | UUID references are named `<entity>_id`. Where 7B's indicative name differs, §20.2 records the binding; the meaning is unchanged. `*_ref` names are kept where the owning column is `*_ref`. |
| REG-07 | These columns are never bound in V1: `credential_ref`, `signing_secret_ref`, `storage_ref`, `target_url`, `transfer_target`, `summary_text`, `body`, `draft_graph`, `draft_config`, `slots`, `arguments`, `result`, `error_message`, `failure_message`, `evidence`, `custom_field_values`, `configuration`, `errors`, `signals` (contents). Security exclusions: §19.3. |
| REG-08 | Fields 7B marks [7I] are bound by type and marked `[7I]` in the field table. 7C does not classify their sensitivity; 7I does. |
| REG-09 | A type written `string (OPEN code)` is a machine code whose value set is intentionally not closed. The producer assigns the value at the point of the fact, from the source the binding names. Tolerant reader: consumers accept any string value, never reject on an unlisted code, and treat an unknown code as "other". Adding a value is COMPATIBLE (CMP-07); removing or renaming a value a producer emits, or closing the set, is BREAKING (MX-21). Publishing a known-value list (IO-7C-16) is documentation, not a schema change. Every other enum is closed (§18) and bound to one executed CHECK or one named frozen vocabulary (§20.3). |
| REG-10 | Every REQUIRED field of a current V1 binding has a deterministic meaning, name, JSON type, requiredness, nullability and value source (a column, or a deterministic value the producer derives or assigns under a named frozen rule). None of these may be left to an IO. Only the physical implementation (code, storage, producer alignment) may be an IO. A field 7B indicates is never silently omitted: it is bound, or its omission is recorded as a reconciliation (§49). Nothing is guessed. |
| REG-11 | A payload timestamp that records the same instant as `occurred_at` equals it exactly (OCC-C08). |
| REG-12 | Organization scope: `organization_id` is NON-NULL for EV-002 … EV-105 (TEN-C03). EV-001 alone may be `null` (TEN-C02). |

### 20.2 Name bindings (7B indicative name → V1 field)

| 7B §24 indicative name | V1 field name |
|---|---|
| `kb_id` | `knowledge_base_id` |
| `tool_id` | `tool_definition_id` |
| `from` / `to` | `from_number` / `to_number` (phone, [7I]) |
| `phone` | `phone_e164` |
| `job_id` | `import_job_id` |
| `list_ref` | `contact_list_id` |
| `campaign_ref` (EV-060) | `campaign_id` |
| `version_id` | `agent_version_id` / `workflow_version_id` / `plugin_version_id` |
| `policy_id` | `compliance_policy_id` |
| `embedding_model` | `embedding_model_ref` |
| `stage_id` | `current_stage_id` |
| `from_stage` / `to_stage` | `from_stage_id` / `to_stage_id` |
| `contact_ref` (deals, appointments) | `contact_id` |
| `value`, `currency` | `value` (money) |
| `subject` | `subject_type` + `subject_id` |
| `start` / `end` | `scheduled_start` / `scheduled_end` |
| `old_start` / `new_start` | `old_scheduled_start` / `new_scheduled_start` |
| `period` (EV-102) | `billing_period_id` + `period_start` / `period_end` (date) |
| `period` (EV-105) | `period_start` / `period_end` (date) |
| `draft revision` (EV-062) | `draft_revision` (timestamp) |
| `total_due` | `total_due` (money) |
| `amount`, `currency` (EV-103) | `amount_paid` (money) |
| `error` (EV-101) | `error_code` |
| `reason` (EV-069) | `reason_code` |
| `reason` (EV-092) | `qualification_reason` |
| `connection_id` | `integration_connection_id` |
| `webhook_id` | `webhook_endpoint_id` |
| `installation_id` | `plugin_installation_id` |
| `execution_id` | `workflow_execution_id` |
| `primary_id` / `secondary_id` | `primary_contact_id` / `secondary_contact_id` |
| `old_owner` / `new_owner` | `old_owned_by` / `new_owned_by` |
| `scorer_type` | `computed_by` |
| `consent_type` | `purpose` + `channel` + `status` |
| `outcome` (EV-076) | `qualification_outcome` |
| `capabilities` (EV-072) | `enabled_capabilities` |
| `change kind` (EV-014) | `change_kind` |
| `old_plan` / `new_plan` | `old_plan_version_id` / `new_plan_version_id` |
| `filename` | `original_filename` |
| `skipped`, `dnc_skipped` | `skipped_rows`, `dnc_skipped_rows` |
| `embedding token count` | `embedding_tokens` |
| `LLM token totals` (EV-100) | `llm_prompt_tokens`, `llm_completion_tokens` |

### 20.3 Enum vocabularies

All are closed (§18). The vocabulary is exactly the executed CHECK set where one exists, otherwise the named frozen vocabulary in the Source column. Adding a value to any of them is BREAKING (MX-08).

| Enum | Values | Source |
|---|---|---|
| E-DIR | `INBOUND`, `OUTBOUND` | `voice.call_sessions.direction` CHECK |
| E-CALL-OUTCOME | `ANSWERED_COMPLETED`, `ANSWERED_TRANSFERRED`, `NO_ANSWER`, `VOICEMAIL`, `FAILED`, `CANCELLED` | `voice.call_sessions.outcome` CHECK; `campaign.campaign_contacts` `chk_cc_outcome` |
| E-LEAD-STATUS | `NEW`, `CONTACTED`, `QUALIFIED`, `DISQUALIFIED`, `NURTURING`, `CONVERTED` | `crm.contacts.lead_status` CHECK |
| E-TEMPERATURE | `HOT`, `WARM`, `COLD`, `UNSCORED` | `crm.contacts.lead_temperature` CHECK |
| E-CONTACT-SOURCE | `INBOUND_CALL`, `OUTBOUND_CALL`, `CSV_IMPORT`, `MANUAL`, `API`, `WEBHOOK` | `crm.contacts.source` CHECK |
| E-SUBJECT-TYPE | `CONTACT`, `DEAL`, `COMPANY` | `subject_type` CHECK on `crm.activities`, `crm.tasks`, `crm.notes` |
| E-ACTIVITY-TYPE | `CALL`, `EMAIL`, `SMS`, `WHATSAPP`, `MEETING`, `NOTE`, `TASK_COMPLETED`, `STAGE_CHANGE`, `SCORE_CHANGE`, `QUALIFICATION_CHANGE`, `AI_INTERACTION`, `CAMPAIGN_CONTACT` | `crm.activities.activity_type` CHECK |
| E-ACTOR-TYPE | `HUMAN`, `AI_AGENT`, `SYSTEM` | `actor_type` / `created_by_type` / `author_type` CHECKs |
| E-NOTE-SOURCE | `HUMAN`, `AI_SUMMARY`, `AI_INTERACTION`, `SYSTEM` | `crm.notes.note_source` CHECK |
| E-APPOINTMENT-SOURCE | `MANUAL`, `AI_AGENT`, `WORKFLOW` | `crm.appointments.source` CHECK |
| E-CONSENT-PURPOSE | `OUTBOUND_CALL`, `MARKETING`, `TRANSACTIONAL`, `RECORDING`, `FOLLOW_UP`, `WHATSAPP_MESSAGING`, `SMS_MESSAGING`, `EMAIL_MESSAGING`, `DATA_PROCESSING`, `AI_INTERACTION` | `crm.consent_records.purpose` CHECK |
| E-CONSENT-CHANNEL | `VOICE`, `SMS`, `WHATSAPP`, `EMAIL`, `ANY` | `crm.consent_records.channel` CHECK |
| E-CONSENT-STATUS | `GRANTED`, `WITHDRAWN`, `EXPIRED`, `UNKNOWN` | `crm.consent_records.status` CHECK |
| E-SUPPRESSION-SCOPE | `ORG`, `PLATFORM`, `REGULATORY` (V1 emits `ORG` only; TEN-C06) | `crm.contact_suppressions.scope` CHECK |
| E-DOCUMENT-SOURCE | `PDF`, `DOCX`, `TXT`, `CSV`, `URL`, `FAQ`, `WEBSITE` | `knowledge.documents.source_type` CHECK |
| E-SUBSCRIPTION-STATUS | `TRIAL`, `ACTIVE`, `PAST_DUE`, `SUSPENDED`, `CANCELLED` | `billing.subscriptions.status` CHECK |
| E-PAYMENT-PROVIDER | `RAZORPAY`, `CASHFREE`, `STRIPE`, `OTHER` | `billing.payment_attempts.payment_provider` CHECK |
| E-QUALIFICATION-OUTCOME | `QUALIFIED`, `DISQUALIFIED`, `INCONCLUSIVE` | `voice.conversations.qualification_outcome` CHECK |
| E-SCORE-COMPUTED-BY | `RULE_ENGINE`, `AI_AGENT`, `MANUAL` | `crm.lead_score_records.computed_by` CHECK |
| E-TOOL-CHANGE-KIND | `CREATED`, `UPDATED`, `DEACTIVATED` | 7C-declared (no column): the three 6E operations 6E-011 / 6E-013 / 6E-014 behind FAM-01; the member `event_type` names are not frozen (OD-7C-07, §46.8) |
| E-TOOL-STATUS | `RUNNING`, `SUCCEEDED`, `FAILED`, `TIMED_OUT` (`PENDING` is never emitted) | subset of `voice.tool_executions.status` CHECK (PAY-D-02 only) |
| E-DURABILITY | `SIGNAL` | SIGNAL profile only (SIG-10) |
| E-PLAN-TIER | `FREE`, `STARTER`, `GROWTH`, `ENTERPRISE` | 4A L659 `PlanTier` (no column; plan assignment deferred, 6C L101; EV-002 writes `null` in V1) |
| E-MERGE-SOURCE | `PRIMARY`, `SECONDARY` | 7C-declared (no column): which contact of `crm.fn_merge_contacts` (097_5D5) supplied the surviving value |
| E-NODE-TYPE | `GREETING`, `PROMPT`, `LLM`, `DECISION`, `CONDITION`, `BRANCH`, `KNOWLEDGE_SEARCH`, `TOOL_CALL`, `WEBHOOK`, `API_CALL`, `DELAY`, `TRANSFER`, `HUMAN_TRANSFER`, `END_CALL` | 4E §5.1.3 `NodeType` (14 values; 6I L77, §11 closed union; an unknown `node_type` fails the execution, 6I L1035) |

### 20.4 Identity, organization, compliance, Voice, agents, tools and knowledge (EV-001 … EV-020)

#### EV-001 `identity.forced_revocation_required`

- **Envelope:** Class A (+B branch) · `event_version` = `1` · `aggregate_type` = `user` · `aggregate_id` = `user_id` · `organization_id` NULLABLE — `null` = explicitly platform-scoped (TEN-C02); the only such event
- **`occurred_at`:** captured once in the producing transaction and written explicitly (OCC-C05): the transaction time `NOW()` that the revoking transaction writes to `identity.sessions.revoked_at` (109_5B7 L1128), identical for every session it revokes
- **Lineage:** 7B §24 / PB · **[7I]:** `access_token_jti` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** 7B L1070 indicates `user_id` and `reason_code`. The frozen revocation contract (5B L2877 – L2884; 109_5B7 L1140 – L1150) also carries the revoked session IDs and their access-token JTIs, which the event exists to propagate to the JTI denylist (6B ADR-6B-02; 7B SEC-02). V1 binds all four. The admin free-text `reason` is never carried. Reconciliation: CNF-7C-11. Producer alignment: IO-7C-21.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `user_id` | UUID | REQUIRED | NON-NULL | `identity.users.id`; equals `aggregate_id` |
| `reason_code` | string (OPEN code) | REQUIRED | NON-NULL | (non-physical) revocation cause, assigned by the producing path: `PASSWORD_RESET` from `POST /api/v1/auth/password/reset/confirm` (5B L2883; 6B §21.11), or `PLATFORM_SESSIONS_REVOKED` from `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all` (`identity.fn_platform_revoke_all_sessions`, 109_5B7; the action code it audits, L1162). V1 producers emit only these two values. Consumers apply REG-09 |
| `session_ids` | set<UUID> | REQUIRED | NON-NULL | `identity.sessions.id` of every session the transaction revoked (5B L2881; 109_5B7 L1127 – L1147); at least one element, because no event is written when nothing is revoked (109_5B7 L1121 – L1124) |
| `access_token_jti` | set<string> | REQUIRED | NON-NULL | the non-null `identity.sessions.access_token_jti` (002_5B L58) of the revoked sessions; may be empty (109_5B7 L1133, L1148). Opaque revocation identifiers, never a bearer token (5B L2877 – L2884; 6B DEP-6B-08; 7B SEC-02) [7I] |

#### EV-002 `organization.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `organization` · `aggregate_id` = `organization_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `organization.organizations.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4A L774 · **[7I]:** `name` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `organization_id` | UUID | REQUIRED | NON-NULL | `organization.organizations.id`; equals `aggregate_id` and the envelope `organization_id`; informational only (TEN-C05) |
| `name` | string | REQUIRED | NON-NULL | `organization.organizations.name` [7I] |
| `slug` | string | REQUIRED | NON-NULL | `organization.organizations.slug` |
| `plan_tier` | enum (E-PLAN-TIER) | REQUIRED | NULLABLE | (non-physical) plan tier assigned in the creating transaction. `organization.organizations` has no plan column and plan assignment is deferred to the Billing / Usage phase (6C L101), so every V1 producer writes `null`. A non-null value is only ever an E-PLAN-TIER value (IO-7C-13) |
| `owner_user_id` | UUID | REQUIRED | NON-NULL | `organization.organizations.owner_user_id` |

#### EV-003 `compliance.policy_activated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `compliance_policy` · `aggregate_id` = `compliance_policy_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `organization.compliance_policies.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `compliance_policy_id` | UUID | REQUIRED | NON-NULL | `organization.compliance_policies.id`; equals `aggregate_id` |
| `activated_at` | timestamp | REQUIRED | NON-NULL | (non-physical) activation time; equals `occurred_at` (REG-11) |

#### EV-004 `call.initiated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.started_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L901 · **[7I]:** `from_number`, `to_number` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `direction`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id`; equals `aggregate_id` |
| `direction` | enum (E-DIR) | REQUIRED | NON-NULL | `voice.call_sessions.direction` |
| `from_number` | phone | REQUIRED | NON-NULL | `voice.call_sessions.from_number` [7I] |
| `to_number` | phone | REQUIRED | NON-NULL | `voice.call_sessions.to_number` [7I] |
| `agent_version_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.agent_version_id` |
| `campaign_lead_ref` | string | REQUIRED | NULLABLE | `voice.call_sessions.campaign_lead_ref` (TEXT); `null` for non-campaign calls |

#### EV-005 `call.ended`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.ended_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L909 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `outcome`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `ended_at` | timestamp | REQUIRED | NON-NULL | `voice.call_sessions.ended_at`; set by this transition (REG-03); equals `occurred_at` |
| `duration_seconds` | integer | REQUIRED | NON-NULL | `voice.call_sessions.duration_seconds` (INTEGER, whole seconds, ≥ 0); set by this transition |
| `outcome` | enum (E-CALL-OUTCOME) | REQUIRED | NON-NULL | `voice.call_sessions.outcome`; set by this transition |

#### EV-006 `call.failed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.ended_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L910 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `failure_reason` | string (OPEN code) | REQUIRED | NULLABLE | `voice.call_sessions.termination_reason`; known-value list is IO-7C-16 |
| `failed_at` | timestamp | REQUIRED | NON-NULL | `voice.call_sessions.ended_at`; set by this transition; equals `occurred_at` |

#### EV-007 `call.held`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L905 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `session_id` | UUID | REQUIRED | NON-NULL | `session_id` of the last element of `voice.call_sessions.sessions` (011_5C L27; element shape `{session_id, started_at, ended_at, outcome}`, 5C L170 – L177) as read by the hold transaction: the Call Session the hold interrupts (4B L96; `SessionId` is a UUIDv7, 4B L255, L586) |
| `held_at` | timestamp | REQUIRED | NON-NULL | (non-physical) hold time; equals `occurred_at` (REG-11) |

#### EV-008 `call.resumed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L906 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `session_id` | UUID | REQUIRED | NON-NULL | `session_id` of the element the resume transaction appends to `voice.call_sessions.sessions` (011_5C L27; 5C L170 – L177): the new Call Session a resume starts (4B L96) |
| `resumed_at` | timestamp | REQUIRED | NON-NULL | (non-physical) resume time; equals `occurred_at` (REG-11) |

#### EV-009 `recording.deleted`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `recording` · `aggregate_id` = `recording_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.recordings.deleted_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L963 (7B mark CRE) · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `recording_id` | UUID | REQUIRED | NON-NULL | `voice.recordings.id`; equals `aggregate_id` |
| `deleted_at` | timestamp | REQUIRED | NON-NULL | `voice.recordings.deleted_at`; set by this transition; equals `occurred_at` |
| `deleted_by` | UUID | REQUIRED | NULLABLE | `voice.recordings.deleted_by`; `null` when the actor is not a user |

#### EV-010 `agent.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `agent` · `aggregate_id` = `agent_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.agents.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L933 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `agent_id` | UUID | REQUIRED | NON-NULL | `voice.agents.id` |
| `name` | string | REQUIRED | NON-NULL | `voice.agents.name` |

#### EV-011 `agent.config_updated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `agent` · `aggregate_id` = `agent_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.agents.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L934 · **[7I]:** `changed_fields` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `agent_id` | UUID | REQUIRED | NON-NULL | `voice.agents.id` |
| `changed_fields` | set<string> | REQUIRED | NON-NULL | (non-physical) names of the configuration fields changed; names only, never values [7I] |

#### EV-012 `agent.published`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `agent` · `aggregate_id` = `agent_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.agent_versions.published_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L935 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `agent_id` | UUID | REQUIRED | NON-NULL | `voice.agents.id` |
| `agent_version_id` | UUID | REQUIRED | NON-NULL | `voice.agent_versions.id` of the published version |
| `version_number` | integer | REQUIRED | NON-NULL | `voice.agent_versions.version_number` (≥ 1) |

#### EV-013 `agent.deprecated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `agent` · `aggregate_id` = `agent_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.agents.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L936 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `agent_id` | UUID | REQUIRED | NON-NULL | `voice.agents.id` |

#### EV-014 `tool_definition.*`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `tool_definition` · `aggregate_id` = `tool_definition_id` · `organization_id` NON-NULL (TEN-C03); emitted only for organization-owned definitions — built-in rows with `organization_id IS NULL` produce no V1 event (§49)
- **`occurred_at`:** `voice.tool_definitions.created_at` for `CREATED`; `voice.tool_definitions.updated_at` for `UPDATED` / `DEACTIVATED` (OCC-C07)
- **Lineage:** 7B §24 / PB (FAM-01) · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `change_kind`: a new value is BREAKING (§29).
- **Note:** 7B freezes EV-014 as the family `tool_definition.*` (FAM-01) and names no member `event_type`; no frozen source names one. 7C invents none. This payload binding applies to every member. How the code-owned manifest represents the family (exact member names, or a governed family entry) is **OD-7C-07 — OWNER DECISION REQUIRED** (§46.8). Until it is decided, EV-014 cannot be entered in the manifest (§26, CSR-02) and P1-7C-04 stays OPEN (§51.1; IO-7C-17).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `tool_definition_id` | UUID | REQUIRED | NON-NULL | `voice.tool_definitions.id` |
| `change_kind` | enum (E-TOOL-CHANGE-KIND) | REQUIRED | NON-NULL | (non-physical) the 6E operation that produced the fact: 6E-011 create, 6E-013 update, 6E-014 deactivate |

#### EV-015 `knowledge_base.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `knowledge_base` · `aggregate_id` = `knowledge_base_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.knowledge_bases.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4E L987 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.knowledge_bases.id` |
| `name` | string | REQUIRED | NON-NULL | `knowledge.knowledge_bases.name` |
| `embedding_model_ref` | string | REQUIRED | NON-NULL | `knowledge.knowledge_bases.embedding_model_ref` (model identifier, not a credential) |

#### EV-016 `knowledge_base.settings_updated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `knowledge_base` · `aggregate_id` = `knowledge_base_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.knowledge_bases.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.knowledge_bases.id` |
| `changed_fields` | set<string> | REQUIRED | NON-NULL | (non-physical) names of the settings changed; names only |

#### EV-017 `knowledge_base.archived`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `knowledge_base` · `aggregate_id` = `knowledge_base_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.knowledge_bases.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.knowledge_bases.id` |

#### EV-018 `knowledge_base.reindex_triggered`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `knowledge_base` · `aggregate_id` = `knowledge_base_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.kb_reindex_jobs.started_at` (dedicated column, OCC-C06) of the job row inserted by the trigger
- **Lineage:** 7B §24 / 4E L988 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.knowledge_bases.id` |
| `triggered_by` | UUID | REQUIRED | NULLABLE | (non-physical) who triggered the reindex: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-019 `document.uploaded`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `document` · `aggregate_id` = `document_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.documents.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4E L990 · **[7I]:** `original_filename` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `source_type`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `document_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.id` |
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.knowledge_base_id` |
| `source_type` | enum (E-DOCUMENT-SOURCE) | REQUIRED | NON-NULL | `knowledge.documents.source_type` |
| `original_filename` | string | REQUIRED | NULLABLE | `knowledge.documents.original_filename`; never an upload or storage URL [7I] |

#### EV-020 `document.deleted`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `document` · `aggregate_id` = `document_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.documents.deleted_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L993 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `document_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.id` |
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.knowledge_base_id` |
| `deleted_by` | UUID | REQUIRED | NULLABLE | (non-physical) who deleted the document: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

### 20.5 CRM (EV-021 … EV-051)

#### EV-021 `contact.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L852 · **[7I]:** `phone_e164` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `source`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `phone_e164` | phone | REQUIRED | NON-NULL | `crm.contacts.phone_e164` [7I] |
| `source` | enum (E-CONTACT-SOURCE) | REQUIRED | NON-NULL | `crm.contacts.source` |
| `campaign_ref` | UUID | REQUIRED | NULLABLE | `crm.contacts.campaign_ref`; `null` when not created by a campaign |

#### EV-022 `contact.updated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L853 · **[7I]:** `changed_fields` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `changed_fields` | set<string> | REQUIRED | NON-NULL | (non-physical) names of the contact fields changed; names only, never values [7I] |

#### EV-023 `contact.lead_status_changed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L854 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `old_status`, `new_status`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `old_status` | enum (E-LEAD-STATUS) | REQUIRED | NON-NULL | (non-physical) `crm.contacts.lead_status` before the change |
| `new_status` | enum (E-LEAD-STATUS) | REQUIRED | NON-NULL | `crm.contacts.lead_status` after the change |
| `changed_by` | UUID | REQUIRED | NULLABLE | (non-physical) who changed the status: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-024 `contact.qualified`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L855 · **[7I]:** `qualification_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `qualification_reason` | string | REQUIRED | NULLABLE | `crm.contacts.qualification_reason` [7I] |
| `qualified_by` | UUID | REQUIRED | NULLABLE | (non-physical) who qualified the contact: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-025 `contact.disqualified`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L856 · **[7I]:** `qualification_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `qualification_reason` | string | REQUIRED | NULLABLE | `crm.contacts.qualification_reason` [7I] |
| `disqualified_by` | UUID | REQUIRED | NULLABLE | (non-physical) who disqualified the contact: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-026 `contact.converted`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.converted_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L858 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `converted_at` | timestamp | REQUIRED | NON-NULL | `crm.contacts.converted_at`; set by this transition; equals `occurred_at` |
| `triggering_deal_id` | UUID | REQUIRED | NULLABLE | (non-physical) the deal whose win caused the conversion; `null` for a conversion not caused by a deal |

#### EV-027 `contact.owner_assigned`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L861 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `old_owned_by` | UUID | REQUIRED | NULLABLE | (non-physical) `crm.contacts.owned_by` before the change |
| `new_owned_by` | UUID | REQUIRED | NULLABLE | `crm.contacts.owned_by` after the change |

#### EV-028 `contact.merged`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `primary_contact_id` (the surviving contact) · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07) on the surviving row
- **Lineage:** 7B §24 / 4C L859 · **[7I]:** `field_merge_map` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `primary_contact_id` | UUID | REQUIRED | NON-NULL | surviving `crm.contacts.id`; equals `aggregate_id` |
| `secondary_contact_id` | UUID | REQUIRED | NON-NULL | merged-away `crm.contacts.id` |
| `field_merge_map` | object (map) | REQUIRED | NON-NULL | (non-physical) keys: `crm.contacts` column names; values: enum (E-MERGE-SOURCE). Key set: `lead_status`, always present, `SECONDARY` iff the secondary's rank exceeds the primary's (097_5D5 L135 – L143), else `PRIMARY`; and each field-fill column `company_id`, `owned_by`, `secondary_phone_e164`, `primary_email`, `primary_email_normalized`, `address_line1`, `address_line2`, `address_city`, `address_state`, `address_postal_code`, `address_country_code`, `qualification_reason` (097_5D5 L169 – L180), present only when its surviving value is non-null, `PRIMARY` when the primary's pre-merge value is non-null, else `SECONDARY`. `last_contacted_at`, `converted_at`, `tags` and `custom_field_values` are never keys. Field names and provenance only, never field values [7I] |

#### EV-029 `contact.dnc_flagged`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L860 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.contacts.id` |
| `flagged_by` | UUID | REQUIRED | NULLABLE | (non-physical) who flagged the contact: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-030 `suppression.added`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `suppression` · `aggregate_id` = `suppression_id` · `organization_id` NON-NULL; emitted only for `scope = 'ORG'` rows (TEN-C06)
- **`occurred_at`:** `crm.contact_suppressions.recorded_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / PB · **[7I]:** suppressed phone value (not bound in V1) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `scope`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `suppression_id` | UUID | REQUIRED | NON-NULL | `crm.contact_suppressions.id` |
| `contact_id` | UUID | REQUIRED | NULLABLE | `crm.contact_suppressions.contact_id`; `null` for a number-only suppression |
| `scope` | enum (E-SUPPRESSION-SCOPE) | REQUIRED | NON-NULL | `crm.contact_suppressions.scope`; V1 emits only `ORG` (TEN-C06) |

#### EV-031 `contact.suppression_lifted`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `suppression` · `aggregate_id` = `suppression_id` · `organization_id` NON-NULL; emitted only for `scope = 'ORG'` rows (TEN-C06)
- **`occurred_at`:** `crm.contact_suppressions.lifted_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `suppression_id` | UUID | REQUIRED | NON-NULL | `crm.contact_suppressions.id` |
| `lifted_by` | UUID | REQUIRED | NULLABLE | `crm.contact_suppressions.lifted_by_ref`; `null` when the actor is not a user |

#### EV-032 `consent.recorded`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `consent` · `aggregate_id` = `consent_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.consent_records.recorded_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / PB · **[7I]:** event-level [7I] (consent facts) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `purpose`, `channel`, `status`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `consent_id` | UUID | REQUIRED | NON-NULL | `crm.consent_records.id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.consent_records.contact_id` |
| `purpose` | enum (E-CONSENT-PURPOSE) | REQUIRED | NON-NULL | `crm.consent_records.purpose` [7I] |
| `channel` | enum (E-CONSENT-CHANNEL) | REQUIRED | NON-NULL | `crm.consent_records.channel` [7I] |
| `status` | enum (E-CONSENT-STATUS) | REQUIRED | NON-NULL | `crm.consent_records.status` [7I] |

#### EV-033 `company.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `company` · `aggregate_id` = `company_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.companies.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `company_id` | UUID | REQUIRED | NON-NULL | `crm.companies.id` |

#### EV-034 `company.updated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `company` · `aggregate_id` = `company_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.companies.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `company_id` | UUID | REQUIRED | NON-NULL | `crm.companies.id` |
| `changed_fields` | set<string> | REQUIRED | NON-NULL | (non-physical) names of the company fields changed; names only |

#### EV-035 `deal.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `deal` · `aggregate_id` = `deal_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.deals.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L867 · **[7I]:** deal title (not bound in V1; 6J "possibly") · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `deal_id` | UUID | REQUIRED | NON-NULL | `crm.deals.id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.deals.contact_id` |
| `pipeline_id` | UUID | REQUIRED | NON-NULL | `crm.deals.pipeline_id` |
| `current_stage_id` | UUID | REQUIRED | NON-NULL | `crm.deals.current_stage_id` |
| `value` | money | REQUIRED | NULLABLE | `crm.deals.value_amount` NUMERIC(18,4) + `value_currency`; `null` as a whole when no value is set |

#### EV-036 `deal.stage_changed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `deal` · `aggregate_id` = `deal_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.deals.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L868 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `deal_id` | UUID | REQUIRED | NON-NULL | `crm.deals.id` |
| `from_stage_id` | UUID | REQUIRED | NON-NULL | (non-physical) `crm.deals.current_stage_id` before the change |
| `to_stage_id` | UUID | REQUIRED | NON-NULL | `crm.deals.current_stage_id` after the change |
| `changed_by` | UUID | REQUIRED | NULLABLE | (non-physical) who moved the deal: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-037 `deal.won`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `deal` · `aggregate_id` = `deal_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.deals.won_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L869 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `deal_id` | UUID | REQUIRED | NON-NULL | `crm.deals.id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.deals.contact_id` |
| `value` | money | REQUIRED | NULLABLE | `crm.deals.value_amount` + `value_currency`; `null` as a whole when no value is set |
| `closed_at` | timestamp | REQUIRED | NON-NULL | `crm.deals.won_at`; set by this transition; equals `occurred_at` |

#### EV-038 `deal.lost`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `deal` · `aggregate_id` = `deal_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.deals.lost_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L870 · **[7I]:** `lost_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `deal_id` | UUID | REQUIRED | NON-NULL | `crm.deals.id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.deals.contact_id` |
| `lost_reason` | string | REQUIRED | NULLABLE | `crm.deals.lost_reason` [7I] |
| `closed_at` | timestamp | REQUIRED | NON-NULL | `crm.deals.lost_at`; set by this transition; equals `occurred_at` |

#### EV-039 `deal.abandoned`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `deal` · `aggregate_id` = `deal_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.deals.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L871 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `deal_id` | UUID | REQUIRED | NON-NULL | `crm.deals.id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.deals.contact_id` |
| `abandoned_at` | timestamp | REQUIRED | NON-NULL | (non-physical) abandonment time; equals `occurred_at` (REG-11) |

#### EV-040 `activity.recorded`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `activity` · `aggregate_id` = `activity_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.activities.occurred_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L877 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `subject_type`, `activity_type`, `actor_type`: a new value is BREAKING (§29).
- **Note:** 7B lists `occurred_at` among the indicative fields. It is carried once, as the envelope `occurred_at` (= `crm.activities.occurred_at`), and is not repeated as a payload key.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `activity_id` | UUID | REQUIRED | NON-NULL | `crm.activities.id` |
| `subject_type` | enum (E-SUBJECT-TYPE) | REQUIRED | NON-NULL | `crm.activities.subject_type` |
| `subject_id` | UUID | REQUIRED | NON-NULL | `crm.activities.subject_id` |
| `activity_type` | enum (E-ACTIVITY-TYPE) | REQUIRED | NON-NULL | `crm.activities.activity_type` |
| `actor_type` | enum (E-ACTOR-TYPE) | REQUIRED | NON-NULL | `crm.activities.actor_type` |

#### EV-041 `task.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `task` · `aggregate_id` = `task_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.tasks.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L878 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `subject_type`, `created_by_type`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `task_id` | UUID | REQUIRED | NON-NULL | `crm.tasks.id` |
| `subject_type` | enum (E-SUBJECT-TYPE) | REQUIRED | NON-NULL | `crm.tasks.subject_type` |
| `subject_id` | UUID | REQUIRED | NON-NULL | `crm.tasks.subject_id` |
| `assigned_to` | UUID | REQUIRED | NULLABLE | `crm.tasks.assigned_to` |
| `due_at` | timestamp | REQUIRED | NON-NULL | `crm.tasks.due_at` |
| `created_by_type` | enum (E-ACTOR-TYPE) | REQUIRED | NON-NULL | `crm.tasks.created_by_type` |

#### EV-042 `task.completed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `task` · `aggregate_id` = `task_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.tasks.completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L879 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `subject_type`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `task_id` | UUID | REQUIRED | NON-NULL | `crm.tasks.id` |
| `subject_type` | enum (E-SUBJECT-TYPE) | REQUIRED | NON-NULL | `crm.tasks.subject_type` |
| `subject_id` | UUID | REQUIRED | NON-NULL | `crm.tasks.subject_id` |
| `completed_at` | timestamp | REQUIRED | NON-NULL | `crm.tasks.completed_at`; set by this transition; equals `occurred_at` |

#### EV-043 `task.cancelled`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `task` · `aggregate_id` = `task_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.tasks.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L880 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `subject_type`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `task_id` | UUID | REQUIRED | NON-NULL | `crm.tasks.id` |
| `subject_type` | enum (E-SUBJECT-TYPE) | REQUIRED | NON-NULL | `crm.tasks.subject_type` |
| `subject_id` | UUID | REQUIRED | NON-NULL | `crm.tasks.subject_id` |
| `cancelled_by` | UUID | REQUIRED | NULLABLE | (non-physical) who cancelled the task: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-044 `note.added`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `note` · `aggregate_id` = `note_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.notes.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L897 (7B mark CRE body) · **[7I]:** none bound (note body excluded) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `subject_type`, `author_type`, `note_source`: a new value is BREAKING (§29).
- **Note:** `crm.notes.body` is never included.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `note_id` | UUID | REQUIRED | NON-NULL | `crm.notes.id` |
| `subject_type` | enum (E-SUBJECT-TYPE) | REQUIRED | NON-NULL | `crm.notes.subject_type` |
| `subject_id` | UUID | REQUIRED | NON-NULL | `crm.notes.subject_id` |
| `author_type` | enum (E-ACTOR-TYPE) | REQUIRED | NON-NULL | `crm.notes.author_type` |
| `note_source` | enum (E-NOTE-SOURCE) | REQUIRED | NON-NULL | `crm.notes.note_source` |

#### EV-045 `note.deleted`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `note` · `aggregate_id` = `note_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.notes.deleted_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L898 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `subject_type`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `note_id` | UUID | REQUIRED | NON-NULL | `crm.notes.id` |
| `subject_type` | enum (E-SUBJECT-TYPE) | REQUIRED | NON-NULL | `crm.notes.subject_type` |
| `subject_id` | UUID | REQUIRED | NON-NULL | `crm.notes.subject_id` |
| `deleted_by` | UUID | REQUIRED | NULLABLE | (non-physical) who deleted the note: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-046 `appointment.booked`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `appointment` · `aggregate_id` = `appointment_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.appointments.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L886 · **[7I]:** event-level [7I] (contact and schedule) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `source`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `appointment_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.contact_id` [7I] |
| `organizer_ref` | UUID | REQUIRED | NON-NULL | `crm.appointments.organizer_ref` |
| `scheduled_start` | timestamp | REQUIRED | NON-NULL | `crm.appointments.scheduled_start` [7I] |
| `scheduled_end` | timestamp | REQUIRED | NON-NULL | `crm.appointments.scheduled_end` [7I] |
| `source` | enum (E-APPOINTMENT-SOURCE) | REQUIRED | NON-NULL | `crm.appointments.source` |

#### EV-047 `appointment.confirmed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `appointment` · `aggregate_id` = `appointment_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.appointments.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L887 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `appointment_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.id` |
| `confirmed_at` | timestamp | REQUIRED | NON-NULL | (non-physical) confirmation time; equals `occurred_at` (REG-11) |

#### EV-048 `appointment.rescheduled`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `appointment` · `aggregate_id` = `appointment_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.appointments.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L891 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `appointment_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.id` |
| `old_scheduled_start` | timestamp | REQUIRED | NON-NULL | (non-physical) `crm.appointments.scheduled_start` before the change |
| `new_scheduled_start` | timestamp | REQUIRED | NON-NULL | `crm.appointments.scheduled_start` after the change |
| `rescheduled_by` | UUID | REQUIRED | NULLABLE | (non-physical) who rescheduled: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-049 `appointment.cancelled`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `appointment` · `aggregate_id` = `appointment_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.appointments.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L888 · **[7I]:** `cancellation_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `appointment_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.id` |
| `cancellation_reason` | string | REQUIRED | NULLABLE | `crm.appointments.cancellation_reason` [7I] |
| `cancelled_by` | UUID | REQUIRED | NULLABLE | (non-physical) who cancelled: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-050 `appointment.completed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `appointment` · `aggregate_id` = `appointment_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.appointments.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L889 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `appointment_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.id` |
| `completed_at` | timestamp | REQUIRED | NON-NULL | (non-physical) completion time; equals `occurred_at` (REG-11) |

#### EV-051 `appointment.no_show`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `appointment` · `aggregate_id` = `appointment_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.appointments.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4C L890 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `appointment_id` | UUID | REQUIRED | NON-NULL | `crm.appointments.id` |
| `marked_by` | UUID | REQUIRED | NULLABLE | (non-physical) who marked the no-show: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

### 20.6 Campaign, workflow, integrations, webhooks, plugins and subscription (EV-052 … EV-072)

#### EV-052 `campaign.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L763 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `name` | string | REQUIRED | NON-NULL | `campaign.campaigns.name` |
| `agent_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.agent_id` |

#### EV-053 `campaign.config_updated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L764 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `changed_fields` | set<string> | REQUIRED | NON-NULL | (non-physical) names of the campaign fields changed; names only |

#### EV-054 `campaign.contact_list_attached`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `contact_list_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.contact_list_id`; set by this transition |

#### EV-055 `campaign.scheduled`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L765 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `start_at` | timestamp | REQUIRED | NON-NULL | (non-physical) the `start_at` this transition writes into `campaign.campaigns.scheduling_policy` (029_5E; 5E §15.2 L936 – L946; 6H §10.4) |
| `end_at` | timestamp | REQUIRED | NULLABLE | (non-physical) `scheduling_policy` key `end_at` as it stands after this transition (5E L127; 4D L182); `null` when the key is absent or `null` (open-ended); later than `start_at` when present (6H L452, L1790) |

#### EV-056 `campaign.paused`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L767 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `paused_by` | UUID | REQUIRED | NULLABLE | (non-physical) who paused: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |
| `paused_at` | timestamp | REQUIRED | NON-NULL | (non-physical) pause time; equals `occurred_at` (REG-11) |

#### EV-057 `campaign.resumed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L768 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `resumed_by` | UUID | REQUIRED | NULLABLE | (non-physical) who resumed: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |
| `resumed_at` | timestamp | REQUIRED | NON-NULL | (non-physical) resume time; equals `occurred_at` (REG-11) |

#### EV-058 `campaign.stopping`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L769 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `initiated_by` | UUID | REQUIRED | NULLABLE | (non-physical) who initiated the stop: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-059 `campaign.cancelled`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.cancelled_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4D L771 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `cancelled_by` | UUID | REQUIRED | NULLABLE | (non-physical) who cancelled: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |
| `cancelled_at` | timestamp | REQUIRED | NON-NULL | `campaign.campaigns.cancelled_at`; set by this transition; equals `occurred_at` |

#### EV-060 `import.job_created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `import_job` · `aggregate_id` = `import_job_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.csv_import_jobs.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L790 · **[7I]:** none (no upload or storage URL) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `campaign.csv_import_jobs.storage_ref` is never included.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `import_job_id` | UUID | REQUIRED | NON-NULL | `campaign.csv_import_jobs.id` |
| `campaign_id` | UUID | REQUIRED | NULLABLE | `campaign.csv_import_jobs.campaign_id` |
| `contact_list_id` | UUID | REQUIRED | NON-NULL | `campaign.csv_import_jobs.contact_list_id` |

#### EV-061 `workflow.created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `workflow` · `aggregate_id` = `workflow_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_definitions.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4E L999 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_definitions.id` |
| `name` | string | REQUIRED | NON-NULL | `workflow.workflow_definitions.name` |

#### EV-062 `workflow.draft_updated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `workflow` · `aggregate_id` = `workflow_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_definitions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none (no graph body) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** 7B's indicative "draft revision" (7B L1131) is bound as `draft_revision` (§20.2). The draft's `updated_at` is the only draft-state token the frozen sources define: `workflow_definitions` has no `version_number` column and none is invented (6I L1058). `draft_graph` is never included.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_definitions.id` |
| `draft_revision` | timestamp | REQUIRED | NON-NULL | `workflow.workflow_definitions.updated_at` written by this draft-update transaction (`trg_wfd_updated_at`, 040_5G; `set_updated_at()`, 001_5B); equals `occurred_at` (REG-11). It identifies the draft state: the value hashed into the 6I §8.2 weak ETag `hash(id, updated_at)` (6I L1058) and checked by `workflow.fn_publish_workflow` as `p_expected_updated_at` (100_5G1). Consumers compare it for equality only. It is not a counter and promises no ordering |

#### EV-063 `workflow.published`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `workflow` · `aggregate_id` = `workflow_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_versions.published_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L1000 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_definitions.id` |
| `workflow_version_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_versions.id` of the published version |
| `version_number` | integer | REQUIRED | NON-NULL | `workflow.workflow_versions.version_number` (≥ 1) |
| `published_by` | UUID | REQUIRED | NON-NULL | `workflow.workflow_versions.published_by` |

#### EV-064 `workflow.archived`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `workflow` · `aggregate_id` = `workflow_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_definitions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4E L1001 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_definitions.id` |
| `archived_by` | UUID | REQUIRED | NULLABLE | (non-physical) who archived: acting user's `identity.users.id`; `null` when the actor is not a user (REG-05) |

#### EV-065 `integration.disconnected`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `integration_connection` · `aggregate_id` = `integration_connection_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `integrations.integration_connections.disconnected_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4F L1142 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `credential_ref` and `configuration` are never included.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `integration_connection_id` | UUID | REQUIRED | NON-NULL | `integrations.integration_connections.id` |
| `definition_id` | UUID | REQUIRED | NON-NULL | `integrations.integration_connections.definition_id` |

#### EV-066 `webhook.endpoint_created`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `webhook_endpoint` · `aggregate_id` = `webhook_endpoint_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `webhooks.webhook_endpoints.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4F L1148 · **[7I]:** `target_url` if ever added (not bound in V1) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `signing_secret_ref` is never included. `target_url` is not bound in V1; adding it is PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW (§27).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `webhook_endpoint_id` | UUID | REQUIRED | NON-NULL | `webhooks.webhook_endpoints.id` |
| `topics` | set<string> | REQUIRED | NON-NULL | `webhooks.webhook_endpoints.topics` (TEXT[]); values from the 6J webhook topic catalogue |

#### EV-067 `plugin.installed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `plugin_installation` · `aggregate_id` = `plugin_installation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `plugins.plugin_installations.installed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4F L1157 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `plugin_installation_id` | UUID | REQUIRED | NON-NULL | `plugins.plugin_installations.id` |
| `plugin_id` | UUID | REQUIRED | NON-NULL | `plugins.plugin_installations.plugin_id` |
| `plugin_version_id` | UUID | REQUIRED | NON-NULL | `plugins.plugin_installations.plugin_version_id` |

#### EV-068 `plugin.activated`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `plugin_installation` · `aggregate_id` = `plugin_installation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `plugins.plugin_installations.activated_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4F L1158 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `plugin_installation_id` | UUID | REQUIRED | NON-NULL | `plugins.plugin_installations.id` |
| `enabled_capabilities` | set<string> | REQUIRED | NON-NULL | `plugins.plugin_installations.enabled_capabilities` (TEXT[]) |

#### EV-069 `plugin.suspended`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `plugin_installation` · `aggregate_id` = `plugin_installation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `plugins.plugin_installations.suspended_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4F L1159 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `plugin_installation_id` | UUID | REQUIRED | NON-NULL | `plugins.plugin_installations.id` |
| `reason_code` | string (OPEN code) | REQUIRED | NULLABLE | (non-physical) suspension reason code; no column; known-value list is IO-7C-16 |

#### EV-070 `plugin.uninstalled`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `plugin_installation` · `aggregate_id` = `plugin_installation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `plugins.plugin_installations.uninstalled_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4F L1160 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `plugin_installation_id` | UUID | REQUIRED | NON-NULL | `plugins.plugin_installations.id` |

#### EV-071 `subscription.changed`

- **Envelope:** Class A · `event_version` = `1` · `aggregate_type` = `subscription` · `aggregate_id` = `subscription_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `billing.subscriptions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `status`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `subscription_id` | UUID | REQUIRED | NON-NULL | `billing.subscriptions.id` |
| `old_plan_version_id` | UUID | REQUIRED | NON-NULL | (non-physical) `billing.subscriptions.plan_version_id` before the change |
| `new_plan_version_id` | UUID | REQUIRED | NON-NULL | `billing.subscriptions.plan_version_id` after the change |
| `status` | enum (E-SUBSCRIPTION-STATUS) | REQUIRED | NON-NULL | `billing.subscriptions.status` after the change |

#### EV-072 `integration.connected`

- **Envelope:** Class B · `event_version` = `1` · `aggregate_type` = `integration_connection` · `aggregate_id` = `integration_connection_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `integrations.integration_connections.connected_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4F L1140 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `credential_ref`, `configuration` and `external_account_ref` are never included.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `integration_connection_id` | UUID | REQUIRED | NON-NULL | `integrations.integration_connections.id` |
| `definition_id` | UUID | REQUIRED | NON-NULL | `integrations.integration_connections.definition_id` |
| `enabled_capabilities` | set<string> | REQUIRED | NON-NULL | `integrations.integration_connections.enabled_capabilities` (TEXT[]) |

### 20.7 Worker-emitted Class-C events (EV-073 … EV-105)

#### EV-073 `call.answered`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.answered_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L903 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `answered_at` | timestamp | REQUIRED | NON-NULL | `voice.call_sessions.answered_at`; set by this transition; equals `occurred_at` |

#### EV-074 `call.conversation_started`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.conversations.started_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4B L904 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.id` (= `voice.call_sessions.conversation_id`, set by this transition) |

#### EV-075 `call.transferred`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `call_session` · `aggregate_id` = `call_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.call_sessions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L908 · **[7I]:** transfer target if ever added (not bound in V1) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `voice.call_sessions.transfer_target` (pii:phone) is not bound in V1.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` |
| `transfer_confirmed_at` | timestamp | REQUIRED | NON-NULL | (non-physical) time the transfer was confirmed; equals `occurred_at` (REG-11) |

#### EV-076 `conversation.qualification_set`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `conversation` · `aggregate_id` = `conversation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.conversations.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L922 · **[7I]:** `criteria_matched` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `qualification_outcome`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.id` |
| `qualification_outcome` | enum (E-QUALIFICATION-OUTCOME) | REQUIRED | NON-NULL | `voice.conversations.qualification_outcome`; set by this transition |
| `criteria_matched` | set<string> | REQUIRED | NON-NULL | (non-physical) identifiers of the qualification criteria matched; no column; identifiers only, never utterance text [7I] |

#### EV-077 `conversation.sentiment_computed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `conversation` · `aggregate_id` = `conversation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.conversations.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L926 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.id` |
| `sentiment_score` | decimal (scale 3) | REQUIRED | NON-NULL | `voice.conversations.sentiment_score` NUMERIC(4,3); set by this transition |

#### EV-078 `conversation.summarization_completed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `conversation` · `aggregate_id` = `conversation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `voice.conversations.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4B L927 · **[7I]:** `summary_text` [7I-HOLD] (never embedded) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `voice.conversations.summary_text` is never embedded.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.id`; this is the summary reference — consumers read the summary through the Voice owner API (PAY-06) |

#### EV-079 `conversation.completed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `conversation` · `aggregate_id` = `conversation_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** the persisted service-end time of the conversation (OCC-C11 … OCC-C13; 7B OCC-01 … OCC-07)
- **Lineage:** 7B §24 / 4B L925 + OD-7B-01 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** Full schema, invariants and example in §22.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.id` |
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.call_id` |
| `completed_at` | timestamp | REQUIRED | NON-NULL | persisted service-end time of the conversation (OCC-C11); equals `occurred_at` (DET-13) |
| `total_turns` | integer | REQUIRED | NON-NULL | `voice.conversations.total_turns` (≥ 0) |
| `usage` | object | REQUIRED | NON-NULL | usage block; full schema in §22 |

#### EV-080 `knowledge_base.reindex_completed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `knowledge_base` · `aggregate_id` = `knowledge_base_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.kb_reindex_jobs.completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L989 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.knowledge_bases.id` |
| `new_index_version` | integer | REQUIRED | NON-NULL | `knowledge.knowledge_bases.index_version` after the reindex |
| `document_count` | integer | REQUIRED | NON-NULL | `knowledge.knowledge_bases.document_count` (≥ 0) |

#### EV-081 `document.indexed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `document` · `aggregate_id` = `document_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.document_versions.ingestion_completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L991 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `document_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.id` |
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.knowledge_base_id` |
| `chunk_count` | integer | REQUIRED | NON-NULL | `knowledge.document_versions.chunk_count`; set by this transition (≥ 0) |
| `indexed_at` | timestamp | REQUIRED | NON-NULL | `knowledge.document_versions.ingestion_completed_at`; set by this transition; equals `occurred_at` |
| `embedding_tokens` | integer | REQUIRED | NON-NULL | (non-physical) tokens submitted to the embedding model for this document version, counted by the ingestion worker (≥ 0); not `ingestion_jobs.embeddings_produced`, which counts vectors |

#### EV-082 `document.ingestion_failed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `document` · `aggregate_id` = `document_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `knowledge.ingestion_jobs.completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L992 · **[7I]:** `failure_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `document_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.id` |
| `knowledge_base_id` | UUID | REQUIRED | NON-NULL | `knowledge.documents.knowledge_base_id` |
| `failure_reason` | string (OPEN code) | REQUIRED | NULLABLE | (non-physical) failure code; never `ingestion_jobs.error_message`; known-value list is IO-7C-16 [7I] |
| `attempt_count` | integer | REQUIRED | NON-NULL | `knowledge.ingestion_jobs.attempt_count` (≥ 1) |

#### EV-083 `contact.score_updated`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `contact` · `aggregate_id` = `contact_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `crm.lead_score_records.computed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4C L857 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `new_temperature`, `computed_by`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `contact_id` | UUID | REQUIRED | NON-NULL | `crm.lead_score_records.contact_id` |
| `old_score` | integer | REQUIRED | NULLABLE | `crm.lead_score_records.previous_score` (0–100); `null` for a first score |
| `new_score` | integer | REQUIRED | NON-NULL | `crm.lead_score_records.score` (0–100) |
| `new_temperature` | enum (E-TEMPERATURE) | REQUIRED | NULLABLE | `crm.contacts.lead_temperature` after the update |
| `computed_by` | enum (E-SCORE-COMPUTED-BY) | REQUIRED | NON-NULL | `crm.lead_score_records.computed_by` |
| `signal_count` | integer | REQUIRED | NON-NULL | (non-physical) number of signals the score was computed from, counted by the producer from `lead_score_records.signals` (≥ 0); signal contents are never included |

#### EV-084 `campaign.started`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.started_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4D L766 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `agent_version_id` | UUID | REQUIRED | NULLABLE | `campaign.campaigns.agent_version_id` |
| `total_contacts` | integer | REQUIRED | NULLABLE | `campaign.campaigns.total_contacts` (≥ 0) |

#### EV-085 `campaign.completed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4D L770 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `completed_at` | timestamp | REQUIRED | NON-NULL | `campaign.campaigns.completed_at`; set by this transition; equals `occurred_at` |
| `total_contacts` | integer | REQUIRED | NULLABLE | `campaign.campaigns.total_contacts` (≥ 0) |
| `attempted` | integer | REQUIRED | NON-NULL | (non-physical) number of campaign contacts with at least one attempt, counted by the producer in the completing transaction (≥ 0) |

#### EV-086 `campaign.failed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaigns.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L772 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaigns.id` |
| `failure_reason` | string (OPEN code) | REQUIRED | NULLABLE | (non-physical) failure code; no column; known-value list is IO-7C-16 |

#### EV-087 `campaign.contact.enqueued`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L778 · **[7I]:** `phone_e164` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `phone_e164` | phone | REQUIRED | NON-NULL | `crm.contacts.phone_e164` of the contact, read in the producing transaction [7I] |
| `attempt_number` | integer | REQUIRED | NON-NULL | (non-physical) 1-based number of the attempt being enqueued (≥ 1) |

#### EV-088 `campaign.contact.dnc_skipped`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L779 · **[7I]:** `phone_e164` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `phone_e164` | phone | REQUIRED | NON-NULL | `crm.contacts.phone_e164` of the contact [7I] |

#### EV-089 `campaign.contact.ineligible`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `reason_code` | string (OPEN code) | REQUIRED | NON-NULL | `campaign.campaign_contacts.ineligibility_reason`; set by this transition; known-value list is IO-7C-16 |

#### EV-090 `campaign.contact.call_attempted`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.last_attempt_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4D L780 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `outcome`: a new value is BREAKING (§29).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` of the attempt (member of `call_session_refs`) |
| `attempt_number` | integer | REQUIRED | NON-NULL | `campaign.campaign_contacts.attempt_count` after this attempt (≥ 1) |
| `outcome` | enum (E-CALL-OUTCOME) | REQUIRED | NULLABLE | `campaign.campaign_contacts.outcome` (`chk_cc_outcome`); `null` when not yet known |
| `attempted_at` | timestamp | REQUIRED | NON-NULL | `campaign.campaign_contacts.last_attempt_at`; set by this transition; equals `occurred_at` |

#### EV-091 `campaign.contact.qualified`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L781 · **[7I]:** `qualification_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` of the qualifying call |
| `qualification_reason` | string | REQUIRED | NULLABLE | `campaign.campaign_contacts.qualification_reason` [7I] |

#### EV-092 `campaign.contact.disqualified`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L782 · **[7I]:** `qualification_reason` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.call_sessions.id` of the disqualifying call |
| `qualification_reason` | string | REQUIRED | NULLABLE | `campaign.campaign_contacts.qualification_reason` [7I] |

#### EV-093 `campaign.contact.retry_scheduled`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L783 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `next_attempt_at` | timestamp | REQUIRED | NON-NULL | `campaign.campaign_contacts.next_attempt_at`; set by this transition |
| `attempt_count` | integer | REQUIRED | NON-NULL | `campaign.campaign_contacts.attempt_count` (≥ 0) |

#### EV-094 `campaign.contact.exhausted`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_contacts.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L784 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `total_attempts` | integer | REQUIRED | NON-NULL | `campaign.campaign_contacts.attempt_count` (≥ 1) |

#### EV-095 `import.job_completed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `import_job` · `aggregate_id` = `import_job_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.csv_import_jobs.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L791 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `errors` (JSONB) and `storage_ref` are never included.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `import_job_id` | UUID | REQUIRED | NON-NULL | `campaign.csv_import_jobs.id` |
| `total_rows` | integer | REQUIRED | NULLABLE | `campaign.csv_import_jobs.total_rows` (≥ 0) |
| `processed_rows` | integer | REQUIRED | NON-NULL | `campaign.csv_import_jobs.processed_rows` (≥ 0) |
| `skipped_rows` | integer | REQUIRED | NON-NULL | `campaign.csv_import_jobs.skipped_rows` (≥ 0) |
| `dnc_skipped_rows` | integer | REQUIRED | NON-NULL | `campaign.csv_import_jobs.dnc_skipped_rows` (≥ 0) |

#### EV-096 `import.job_failed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `import_job` · `aggregate_id` = `import_job_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.csv_import_jobs.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4D L792 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `import_job_id` | UUID | REQUIRED | NON-NULL | `campaign.csv_import_jobs.id` |
| `failure_reason` | string (OPEN code) | REQUIRED | NULLABLE | (non-physical) failure code; no column; known-value list is IO-7C-16 |
| `processed_rows` | integer | REQUIRED | NON-NULL | `campaign.csv_import_jobs.processed_rows` (≥ 0) |

#### EV-097 `campaign.outcome_computed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign` · `aggregate_id` = `campaign_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `campaign.campaign_outcomes.computed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4D L798 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_outcomes.campaign_id` |
| `qualified` | integer | REQUIRED | NON-NULL | `campaign.campaign_outcomes.qualified` (≥ 0) |
| `disqualified` | integer | REQUIRED | NON-NULL | `campaign.campaign_outcomes.disqualified` (≥ 0) |
| `answer_rate_pct` | decimal (scale 2) | REQUIRED | NON-NULL | `campaign.campaign_outcomes.answer_rate_pct` NUMERIC(5,2) |
| `roi_pct` | decimal (scale 2) | REQUIRED | NULLABLE | `campaign.campaign_outcomes.roi_pct` NUMERIC(8,2); may be negative |
| `total_cost` | money | REQUIRED | NULLABLE | `campaign.campaign_outcomes.total_cost_amount` NUMERIC(18,4) + currency; `null` as a whole when not computed |

#### EV-098 `compliance.eligibility_denied`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `campaign_contact` · `aggregate_id` = `campaign_contacts.id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** captured once in the producing transaction and written explicitly (OCC-C05; no dedicated column on the owning row)
- **Lineage:** 7B §24 / PB (Compliance owns) · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `campaign_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.campaign_id` |
| `contact_id` | UUID | REQUIRED | NON-NULL | `campaign.campaign_contacts.contact_id` |
| `rule_code` | string (OPEN code) | REQUIRED | NON-NULL | (non-physical) denying compliance rule code; known-value list is IO-7C-16 |

#### EV-099 `workflow.execution.started`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `workflow_execution` · `aggregate_id` = `workflow_execution_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_executions.started_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L1002 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_execution_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.id` |
| `workflow_version_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.workflow_version_id` |
| `session_ref` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.session_ref` |

#### EV-100 `workflow.execution.completed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `workflow_execution` · `aggregate_id` = `workflow_execution_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_executions.completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / 4E L1003 · **[7I]:** none (no slot values) · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Note:** `slots` is never included. No discriminator is defined (DEP-6K-05 stays OPEN; §43).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_execution_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.id` |
| `session_ref` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.session_ref` |
| `total_nodes_visited` | integer | REQUIRED | NON-NULL | (non-physical) nodes visited by the execution, counted by the runtime (≥ 1) |
| `exit_node_type` | enum (E-NODE-TYPE) | REQUIRED | NON-NULL | (non-physical) `node_type` of the node at which the execution completed, read from the execution's pinned graph |
| `completed_at` | timestamp | REQUIRED | NON-NULL | `workflow.workflow_executions.completed_at`; set by this transition; equals `occurred_at` |
| `llm_prompt_tokens` | integer | REQUIRED | NON-NULL | (non-physical) standalone-attributable LLM prompt tokens only (DET-17; DEP-6K-05 OPEN) (≥ 0) |
| `llm_completion_tokens` | integer | REQUIRED | NON-NULL | (non-physical) standalone-attributable LLM completion tokens only (DET-17; DEP-6K-05 OPEN) (≥ 0) |

#### EV-101 `workflow.execution.failed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `workflow_execution` · `aggregate_id` = `workflow_execution_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `workflow.workflow_executions.updated_at` of the changing transaction (OCC-C07)
- **Lineage:** 7B §24 / 4E L1004 · **[7I]:** `error_code` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `workflow_execution_id` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.id` |
| `session_ref` | UUID | REQUIRED | NON-NULL | `workflow.workflow_executions.session_ref` |
| `failed_node_id` | UUID | REQUIRED | NULLABLE | `workflow.workflow_executions.current_node_id` at failure |
| `error_code` | string (OPEN code) | REQUIRED | NULLABLE | (non-physical) error code only, never a message; known-value list is IO-7C-16 [7I] |

#### EV-102 `invoice.generated`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `invoice` · `aggregate_id` = `invoice_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `billing.invoices.created_at` of the creating transaction (OCC-C07)
- **Lineage:** 7B §24 / 4F L1123 · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `invoice_id` | UUID | REQUIRED | NON-NULL | `billing.invoices.id` |
| `billing_account_id` | UUID | REQUIRED | NON-NULL | `billing.invoices.billing_account_id` |
| `billing_period_id` | UUID | REQUIRED | NULLABLE | `billing.invoices.billing_period_id` |
| `period_start` | date | REQUIRED | NULLABLE | `billing.billing_periods.period_start` of `billing_period_id`; `null` iff `billing_period_id` is `null` |
| `period_end` | date | REQUIRED | NULLABLE | `billing.billing_periods.period_end` of `billing_period_id`; `null` iff `billing_period_id` is `null` |
| `total_due` | money | REQUIRED | NON-NULL | `billing.invoices.total_due_amount` NUMERIC(18,4) + `total_due_currency` |

#### EV-103 `invoice.paid`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `invoice` · `aggregate_id` = `invoice_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `billing.invoices.paid_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `invoice_id` | UUID | REQUIRED | NON-NULL | `billing.invoices.id` |
| `paid_at` | timestamp | REQUIRED | NON-NULL | `billing.invoices.paid_at`; set by this transition; equals `occurred_at` |
| `amount_paid` | money | REQUIRED | NON-NULL | `billing.invoices.amount_paid_amount` + `amount_paid_currency` |

#### EV-104 `payment.failed`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `payment_attempt` · `aggregate_id` = `payment_attempt_id` · `organization_id` NON-NULL (TEN-C03)
- **`occurred_at`:** `billing.payment_attempts.completed_at` (dedicated column, OCC-C06)
- **Lineage:** 7B §24 / PB · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. Closed enum(s) `payment_provider`: a new value is BREAKING (§29).
- **Note:** `failure_message`, `provider_transaction_id` and `payment_method_ref` are never included. No card data.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `payment_attempt_id` | UUID | REQUIRED | NON-NULL | `billing.payment_attempts.id` |
| `invoice_id` | UUID | REQUIRED | NON-NULL | `billing.payment_attempts.invoice_id` |
| `payment_provider` | enum (E-PAYMENT-PROVIDER) | REQUIRED | NON-NULL | `billing.payment_attempts.payment_provider` |
| `failure_code` | string (OPEN code) | REQUIRED | NULLABLE | `billing.payment_attempts.failure_code`; known-value list is IO-7C-16 |

#### EV-105 `usage.threshold_reached`

- **Envelope:** Class C · `event_version` = `1` · `aggregate_type` = `organization` · `aggregate_id` = `organization_id` (the envelope `organization_id`) · `organization_id` NON-NULL (TEN-C03)
- **Producer and trigger:** the 5H serialized usage aggregation transaction that inserts or updates the `billing.usage_records` row for (`organization_id`, `billing_period_id`, `metric`) (5H L281 – L289, L481; QP-06 L1894 – L1903), with the outbox insert in the same transaction (7B L1865). The event is written when, and only when, that write moves `quantity_used` from a value ≤ S to a value > S. S is the non-NULL effective `soft_limit` that `billing.fn_resolve_effective_quota(organization_id, metric)` returns in the same transaction (111_5H4 L391, L485); the pre-write value is `0` for a new row. No event is written when S is NULL ("no warning threshold", 111_5H4 L240), when no quota row resolves, or for a metric outside the canonical set (the resolver rejects it, 111_5H4 L421 – L423). `hard_limit` is never the threshold: 6K binds this event to the soft-limit crossing (6K L2061, L2824). One write produces at most one event per metric.
- **`occurred_at`:** `billing.usage_records.updated_at` written by the crossing write (OCC-C07): the inserted `DEFAULT NOW()` for a new row, or the `updated_at = NOW()` of the aggregation upsert (QP-06; `trg_ur_updated_at`, 050_5H L61). This is the aggregation transaction's time, never relay, worker-retry, Redis or webhook time.
- **Lineage:** 7B §24 / PB (7B L1174) · **[7I]:** none · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30. `metric` is OPEN (REG-09): adding a canonical metric is COMPATIBLE (CMP-07); removing or renaming an emitted metric, or closing the set, is BREAKING (MX-21).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `metric` | string (OPEN code) | REQUIRED | NON-NULL | `billing.usage_records.metric` of the crossing row. V1 producers emit only a value for which `billing.fn_is_canonical_usage_metric` is true: `CALL_MINUTES`, `AI_MINUTES`, `STT_SECONDS`, `TTS_CHARACTERS`, `LLM_PROMPT_TOKENS`, `LLM_COMPLETION_TOKENS`, `EMBEDDING_TOKENS`, `CAMPAIGN_CALLS`, `WORKFLOW_EXECUTIONS`, `TOOL_EXECUTIONS`, `KNOWLEDGE_RETRIEVALS`, `STORAGE_GB`, `API_REQUESTS`, `ACTIVE_AGENTS`, `ACTIVE_PHONE_NUMBERS` (111_5H4 L173 – L198; restated in 112_5H5 L137 – L175; 5H §11.1). OPEN because 6K §21.1 governs usage metrics as not a closed enum (ADR-5H-002). Consumers apply REG-09 |
| `threshold` | decimal (scale 4) | REQUIRED | NON-NULL | (non-physical) S, the effective `soft_limit` crossed (NUMERIC(18,4); 052_5H; 111_5H4). Unit: the canonical unit of `metric` (6K §21.1 L1908 – L1922; for example minutes for `CALL_MINUTES`, tokens for `LLM_PROMPT_TOKENS`), the unit `quantity_used` and `soft_limit` share for that metric. `metric` determines the unit, so there is no separate unit field. Never `hard_limit`, the current usage or a percentage |
| `period_start` | date | REQUIRED | NON-NULL | `billing.billing_periods.period_start` (049_5H L51) of the crossing row's `billing_period_id` (050_5H L49): the billing period whose usage crossed S |
| `period_end` | date | REQUIRED | NON-NULL | `billing.billing_periods.period_end` (049_5H L52) of the same period; later than `period_start` (049_5H L60) |

### 20.8 Registry summary

| Measure | Value |
|---|---|
| Durable bindings | 105 (EV-001 … EV-105), each `event_version` = `1` |
| By class | A = 71 (EV-001 … EV-071; EV-001 with a B branch), B = 1 (EV-072), C = 33 (EV-073 … EV-105) |
| Payload fields bound | 341 (all REQUIRED; 58 NULLABLE) |
| Fields marked (non-physical) | 59 |
| Fields marked [7I] | 26 |
| V2 bindings | 0 |
| Platform-scoped events | 1 (EV-001) |

---

## 21. Class-D Payload Schema Registry

SIGNAL-profile V1 bindings for the two consumed Class-D signals (§11). Their only consumer is Analytics (SIG-R06). Neither is a Billing source (OD-7B-01). Both are `event_version` = `1`.

### 21.1 PAY-D-01 — DS-17 `conversation.turn_completed`

- **Envelope:** SIGNAL profile (§11) · `durability` = `"SIGNAL"` · `event_version` = `1` · `aggregate_type` = `conversation` · `aggregate_id` = `conversation_id` · `organization_id` NON-NULL · `correlation_id` = the call's established root (COR-C; equals `call_id` only for a Voice-rooted call, COR-V) · `causation_id` = `turn_id` (CAU-05)
- **`event_id`:** producer UUIDv7, generated once per signal (ID-07 … ID-09); not an outbox ID, Redis entry ID or delivery ID
- **`occurred_at`:** `voice.turns.completed_at` of the turn; set by the turn-completion transition
- **Lineage:** 7B PAY-D-01 (L735), DS-17 · **[7I]:** `llm_provider_ref`, `stt_provider_ref` · **Compatibility:** V1 baseline; no V2. Changes follow §27 – §30.
- **Excluded:** turn text, transcript, raw utterance, prompt or completion text, audio, pricing, cost, rate, credentials, signed URLs.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.turns.conversation_id`; equals `aggregate_id` |
| `turn_id` | UUID | REQUIRED | NON-NULL | `voice.turns.id`; equals `causation_id` |
| `sequence_number` | integer | REQUIRED | NON-NULL | `voice.turns.sequence_number` (≥ 0) |
| `agent_id` | UUID | REQUIRED | NON-NULL | (non-physical) agent of the conversation (DET-11); required because the Analytics grain is `agent_id NOT NULL` and Analytics never reads Voice tables |
| `stt_ms` | integer | REQUIRED | NULLABLE | `voice.turns.stt_ms` (milliseconds, latency) |
| `llm_first_token_ms` | integer | REQUIRED | NULLABLE | `voice.turns.llm_first_token_ms` (milliseconds) |
| `tts_first_audio_ms` | integer | REQUIRED | NULLABLE | `voice.turns.tts_first_audio_ms` (milliseconds) |
| `turn_e2e_ms` | integer | REQUIRED | NULLABLE | `voice.turns.turn_e2e_ms` (milliseconds) |
| `llm_prompt_tokens` | integer | REQUIRED | NON-NULL | (non-physical) LLM prompt tokens for this turn, per-turn runtime counter (≥ 0; IO-7C-08) |
| `llm_completion_tokens` | integer | REQUIRED | NON-NULL | (non-physical) LLM completion tokens for this turn, per-turn runtime counter (≥ 0; IO-7C-08) |
| `stt_audio_seconds` | decimal (scale 4) | REQUIRED | NON-NULL | (non-physical) seconds of audio submitted to STT for this turn (not latency; ≥ 0; IO-7C-08) |
| `tts_characters` | integer | REQUIRED | NON-NULL | (non-physical) characters submitted to TTS for this turn (≥ 0; IO-7C-08) |
| `barge_in_occurred` | boolean | REQUIRED | NON-NULL | `voice.turns.barge_in_occurred` |
| `tool_execution_ids` | list<UUID> | REQUIRED | NON-NULL | `voice.turns.tool_execution_ids` in execution order; empty list when none |
| `tool_execution_count` | integer | REQUIRED | NON-NULL | (non-physical) length of `tool_execution_ids` (≥ 0) |
| `llm_provider_ref` | string | REQUIRED | NULLABLE | `voice.turns.llm_provider_id` (TEXT provider identifier, not a credential) [7I] |
| `stt_provider_ref` | string | REQUIRED | NULLABLE | `voice.turns.stt_provider_id` (TEXT provider identifier, not a credential) [7I] |
| `completed_at` | timestamp | REQUIRED | NON-NULL | `voice.turns.completed_at`; set by the turn-completion transition (REG-03); equals `occurred_at` |

Rules:

- **PD1-01.** `stt_audio_seconds` is emitted at scale 4 (`NUMERIC(18,4)` usage scale). `analytics.conversation_turn_stats_daily.stt_audio_seconds` is `NUMERIC(12,2)`; reducing scale is the Analytics projection's job, not the producer's (§49, Minor).
- **PD1-02.** The per-turn counters are telemetry. They never feed Billing. EV-079's conversation totals are accumulated independently of signal delivery (IO-7C-07), because a SIGNAL can be lost (SIG-R03).
- **PD1-03.** A missing latency measurement is `null`, never `0`.

### 21.2 PAY-D-02 — DS-19 `tool_execution.*`

Members: `tool_execution.started`, `tool_execution.succeeded`, `tool_execution.failed`. A timed-out execution is `tool_execution.failed` with `status` = `TIMED_OUT`. All three members share this one binding.

- **Envelope:** SIGNAL profile (§11) · `durability` = `"SIGNAL"` · `event_version` = `1` · `aggregate_type` = `tool_execution` · `aggregate_id` = `tool_execution_id` · `organization_id` NON-NULL · `correlation_id` = the call's established root (COR-C; equals `call_id` only for a Voice-rooted call, COR-V) · `causation_id` = `turn_id` (CAU-05)
- **`event_id`:** producer UUIDv7, generated once per signal (ID-07 … ID-09); each member emission is a separate signal with its own `event_id`
- **`occurred_at`:** `voice.tool_executions.started_at` for `.started`; `voice.tool_executions.completed_at` for `.succeeded` and `.failed`
- **Lineage:** 7B PAY-D-02, DS-19 · **[7I]:** `tool_name` · **Compatibility:** V1 baseline; no V2. Closed enum `status`: a new value is BREAKING (§29).
- **Excluded:** tool arguments, tool results, error messages, credentials, secrets, signed URLs.

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `tool_execution_id` | UUID | REQUIRED | NON-NULL | `voice.tool_executions.id`; equals `aggregate_id` |
| `turn_id` | UUID | REQUIRED | NON-NULL | `voice.tool_executions.turn_id`; equals `causation_id` |
| `tool_definition_id` | UUID | REQUIRED | NON-NULL | `voice.tool_executions.tool_definition_id` |
| `tool_name` | string | REQUIRED | NON-NULL | `voice.tool_executions.tool_name` [7I] |
| `status` | enum (E-TOOL-STATUS) | REQUIRED | NON-NULL | `voice.tool_executions.status`; `.started` → `RUNNING`; `.succeeded` → `SUCCEEDED`; `.failed` → `FAILED` or `TIMED_OUT` |
| `duration_ms` | integer | REQUIRED | NULLABLE | (non-physical) `completed_at` − `started_at` in whole milliseconds (≥ 0); `null` for `.started` |
| `error_code` | string (OPEN code) | REQUIRED | NULLABLE | `voice.tool_executions.error_code`; `null` except on `.failed` |
| `attempt_count` | integer | REQUIRED | NON-NULL | `voice.tool_executions.attempt_count` (≥ 1) |

Rules:

- **PD2-01.** The member-to-`status` mapping above is exact. Any other pairing is a contract violation.
- **PD2-02.** `agent_id` is not carried in V1. `analytics.tool_execution_stats_daily.agent_id` is NULL-able (071), so the grain does not require it. Adding it later is an optional non-sensitive addition (§28) and is recorded as a deferred item (§48).
- **PD2-03.** `tool_execution.started` is not among the 25 rows seeded by 075. Analytics must register it before consuming it (IO-7B-11, IO-7C-11). Until then the Analytics adapter treats it as an unregistered type, never as a known one.
- **PD2-04.** PAY-D-02 is not a Billing source. The Billing TOOL_EXECUTIONS producer is UNWIRED (DEP-6K-01); 7C does not wire it.

---

## 22. EV-079 Schema

EV-079 `conversation.completed` is the Class-C accounting-finalization fact for one conversation (OD-7B-01; 7B §31). It records that the conversation's usage is final. It does **not** assert that the call succeeded; call outcome is EV-005 / EV-006. It is the only Billing source for conversation usage. Usage is carried inline (OD-7C-05).

### 22.1 Envelope and top-level payload

- **Envelope:** DURABLE profile (§10) · Class C · `event_version` = `1` · `aggregate_type` = `conversation` · `aggregate_id` = `conversation_id` · `organization_id` NON-NULL · `event_id` = outbox `id`
- **`occurred_at`:** the persisted service-end time (OCC-C11 … OCC-C13). Never worker time, recovery `now()`, Redis time or relay time. No persisted service-end time → no EV-079 (IO-7C-10).

| Field | JSON type | Required | Nullable | Unit / enum / source |
|---|---|---|---|---|
| `conversation_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.id` |
| `call_id` | UUID | REQUIRED | NON-NULL | `voice.conversations.call_id` |
| `completed_at` | timestamp | REQUIRED | NON-NULL | persisted service-end time of the conversation (OCC-C11); equals `occurred_at` (DET-13) |
| `total_turns` | integer | REQUIRED | NON-NULL | `voice.conversations.total_turns` (≥ 0) |
| `usage` | object | REQUIRED | NON-NULL | usage block; full schema in §22 |

### 22.2 `usage` object

`usage` has exactly five keys. Each is a metric object `{total, breakdown}`.

| Key | JSON type | Required | Nullable | `total` type | `quantity` type | Unit |
|---|---|---|---|---|---|---|
| `ai_duration_seconds` | object (metric) | REQUIRED | NON-NULL | decimal (scale 4) | decimal (scale 4) | seconds of AI service time; exact, never pre-rounded minutes (DET-12) |
| `stt_audio_seconds` | object (metric) | REQUIRED | NON-NULL | decimal (scale 4) | decimal (scale 4) | seconds of audio submitted to STT; not latency |
| `tts_characters` | object (metric) | REQUIRED | NON-NULL | integer | integer | characters submitted to TTS |
| `llm_prompt_tokens` | object (metric) | REQUIRED | NON-NULL | integer | integer | LLM prompt tokens |
| `llm_completion_tokens` | object (metric) | REQUIRED | NON-NULL | integer | integer | LLM completion tokens |

Metric object:

| Field | JSON type | Required | Nullable | Rule |
|---|---|---|---|---|
| `total` | decimal (scale 4) for `*_seconds`; integer for counts | REQUIRED | NON-NULL | ≥ 0; the conversation total for the metric |
| `breakdown` | array (set) of breakdown items | REQUIRED | NON-NULL | empty iff `total` is zero |

Breakdown item (exactly these three keys, no others):

| Field | JSON type | Required | Nullable | Rule |
|---|---|---|---|---|
| `provider_ref` | string | REQUIRED | NON-NULL | provider identifier (as in `voice.turns.llm_provider_id`); reference only, never a credential |
| `model_ref` | string | REQUIRED | NULLABLE | model identifier; `null` when the provider exposes no model distinction for the metric |
| `quantity` | same type as the metric's `total` | REQUIRED | NON-NULL | > 0 |

### 22.3 Invariants

| ID | Invariant |
|---|---|
| USG-01 | `completed_at` equals envelope `occurred_at` exactly (DET-13). |
| USG-02 | For every metric, the sum of `breakdown[*].quantity` equals `total` exactly. Decimal metrics are summed in exact decimal arithmetic at scale 4, never in floating point. |
| USG-03 | A breakdown supports any number of providers and models. Each unit is attributed to exactly one (`provider_ref`, `model_ref`) pair; no unit is counted twice. The per-metric attribution source is materialized with the accumulator (IO-7C-07). |
| USG-04 | Breakdown items are unique by (`provider_ref`, `model_ref`) and sorted ascending by `provider_ref`, then `model_ref` (`null` first). Zero-quantity items are omitted, so `breakdown` is empty iff `total` is zero. |
| USG-05 | `tts_characters`, `llm_prompt_tokens` and `llm_completion_tokens` totals and quantities are non-negative JSON integers. They are never decimal strings and never floats. |
| USG-06 | `ai_duration_seconds` and `stt_audio_seconds` totals and quantities are decimal strings at scale 4. They are never JSON numbers. |
| USG-07 | No pricing, cost, rate, margin, currency, invoice line, transcript, raw provider response, credential or signed URL appears anywhere in the payload. |
| USG-08 | The totals are the conversation's accumulated usage (IO-7C-07). They are not rebuilt from PAY-D-01 signals, which can be lost (SIG-R03). |
| USG-09 | Billing forms `source_event_id` = `<outbox_event_id>:<METRIC>` per metric (ID-04; 6K L1961), where `<outbox_event_id>` is the envelope `event_id` and `<METRIC>` is the 6K catalogue metric code for that usage key (for `ai_duration_seconds`, `AI_MINUTES`). The key has no provider or model component; the breakdown never forms part of it. The mapping from usage key to 6K metric code, and seconds-to-minutes conversion, are Billing's (DET-12). |
| USG-10 | LLM usage of workflow executions inside a conversation turn is in EV-079. EV-100 carries only standalone-attributable LLM usage (DET-17; DEP-6K-05 OPEN). |

### 22.4 Example (V1, before correlation / causation activation)

```json
{
  "event_id": "01923f50-1a2b-7c3d-8e4f-5a6b7c8d9e0f",
  "event_type": "conversation.completed",
  "event_version": 1,
  "organization_id": "01923f4e-6a11-7c22-8d33-9e44f5a6b7c8",
  "aggregate_type": "conversation",
  "aggregate_id": "01923f4f-0001-7002-8003-000400050006",
  "occurred_at": "2026-08-21T09:21:04.518200Z",
  "payload": {
    "conversation_id": "01923f4f-0001-7002-8003-000400050006",
    "call_id": "01923f4e-ff01-7f02-8f03-9f04afb0c1d2",
    "completed_at": "2026-08-21T09:21:04.518200Z",
    "total_turns": 14,
    "usage": {
      "ai_duration_seconds": {
        "total": "312.4800",
        "breakdown": [
          { "provider_ref": "llm_provider_a", "model_ref": "model_a1", "quantity": "200.0000" },
          { "provider_ref": "llm_provider_b", "model_ref": "model_b2", "quantity": "112.4800" }
        ]
      },
      "stt_audio_seconds": {
        "total": "141.2500",
        "breakdown": [
          { "provider_ref": "stt_provider_a", "model_ref": null, "quantity": "141.2500" }
        ]
      },
      "tts_characters": {
        "total": 4180,
        "breakdown": [
          { "provider_ref": "tts_provider_a", "model_ref": "voice_model_1", "quantity": 4180 }
        ]
      },
      "llm_prompt_tokens": {
        "total": 18230,
        "breakdown": [
          { "provider_ref": "llm_provider_a", "model_ref": "model_a1", "quantity": 12000 },
          { "provider_ref": "llm_provider_b", "model_ref": "model_b2", "quantity": 6230 }
        ]
      },
      "llm_completion_tokens": {
        "total": 2915,
        "breakdown": [
          { "provider_ref": "llm_provider_a", "model_ref": "model_a1", "quantity": 1900 },
          { "provider_ref": "llm_provider_b", "model_ref": "model_b2", "quantity": 1015 }
        ]
      }
    }
  }
}
```

Billing keys for this example: `01923f50-1a2b-7c3d-8e4f-5a6b7c8d9e0f:AI_MINUTES` and one key per further 6K metric code. The provider and model values in the example are illustrative placeholders.

---

## 23. Event Version Representation

The internal `event_version` is the version of one `event_type`'s **complete compatibility-relevant contract** (KEY-06, VRS-08). It is carried by the outbox column `event_version INTEGER NOT NULL DEFAULT 1` (077 L51) and by SIG-03 on the SIGNAL profile.

Correction note (P1-7C-02): the checkpoint text of this section and of VRS-08, CMP-06 and BRK-06 said that the version describes the **payload schema only** and that an envelope change never changes an `event_version`. That contradicted the compatibility treatment of the envelope semantics it governs (MX-12, MX-14, MX-15: aggregate, organization scope and `occurred_at` meaning) and is withdrawn. The scope below replaces it.

**Versioned by `event_version`** (the complete compatibility-relevant contract of one `event_type`):

- the payload schema: field names, §18 JSON types, requiredness, nullability, units and scale, closed-enum sets and their meaning, OPEN-code tolerance, set / list semantics and default or absence meaning;
- identity semantics: what `event_id` identifies, and what each identifying payload field refers to;
- organization / tenant semantics: whether `organization_id` is organization-scoped or platform-scoped for the type, and what the organization of the fact is;
- aggregate semantics: what `aggregate_type` names and what `aggregate_id` identifies;
- occurrence-time semantics: which business moment `occurred_at` records and its source;
- any other envelope field whose meaning affects how a consumer interprets the fact.

**Not versioned by `event_version`:** relay bookkeeping (`status`, `attempt_count`, `max_attempts`, `available_at`, claim fields, `published_at`, `last_error`; KEY-02), Redis stream entry IDs, retry or attempt counters, outbox claim metadata, delivery or publish timestamps, the wire encoding (KEY-05) and any other transport-only state. A change to any of these never changes an `event_version`.

A change inside the versioned contract is classified by §27 (the matrix §27.3 and the category rules §27.4). An envelope addition that meets all four KEY-07 conditions is COMPATIBLE and keeps every version; the OD-7C-04 `correlation_id` / `causation_id` columns are such an addition and create no V2.

| ID | Rule |
|---|---|
| VRS-01 | On the wire `event_version` is a JSON integer literal (§18 integer) in the range 1 … 2147483647, the positive range of the executed `INTEGER` column. |
| VRS-02 | The version is scoped to one `event_type`. Versions of different types are never compared, ordered or combined. There is no platform-wide event version and no version shared by a group of types. |
| VRS-03 | Versions of one type are consecutive from 1. A new version is always N + 1, where N is the greatest number already defined for that type in the manifest. A number is never skipped, reused or reassigned, even after retirement (RET-05). |
| VRS-04 | Exactly one wire form is valid. See the table below. |
| VRS-05 | The version is never encoded in `event_type` (DET-08) and never in a payload key or payload value (PAY-04). |
| VRS-06 | Producers write the version explicitly on every event (DET-05). The column default is never relied on. |
| VRS-07 | Every one of the 105 durable types and both SIGNAL bindings (PAY-D-01, PAY-D-02) is at `event_version` = `1`. No other version of any type exists. |
| VRS-08 | The version describes the complete compatibility-relevant contract of the type: the payload schema and the meaning of every interpretation-relevant envelope field (organization scope, aggregate, occurrence time, identity). Relay bookkeeping, Redis stream IDs, retry counters, claim metadata, delivery timestamps and transport encoding are not versioned by it (KEY-02, KEY-05, KEY-06). A change to the meaning of an interpretation-relevant envelope field is classified by §27.4 exactly like a payload change. |
| VRS-09 | The SIGNAL profile uses the same representation (SIG-03). |
| VRS-10 | The version is a single integer. It is not semantic versioning. There is no minor, patch, pre-release or build component, and a compatible change never changes the number (OD-7C-01). |

**VRS-04 wire values:**

| Wire value of `event_version` | Verdict | Reason |
|---|---|---|
| `1` | VALID | JSON integer ≥ 1 within range |
| `"1"` | INVALID | string; TEXT is an Analytics projection only (§24) |
| `1.0` | INVALID | fraction part; not an integer literal (§18) |
| `1e0` | INVALID | exponent form |
| `true` / `false` | INVALID | boolean. A validator in a language where the boolean type is an integer subtype excludes booleans explicitly. |
| `0`, `-1` | INVALID | below 1 |
| `null` or key absent | INVALID | REQUIRED, NON-NULL (ENV-03, SIG-03) |
| `"v1"`, `"V1"`, `"1.0"` | INVALID | string forms; no prefix, no dotted form |
| `2147483648` | INVALID | outside the `INTEGER` range |

A malformed version is a contract violation (UV-06). It is never coerced, trimmed or parsed leniently into a valid one.

---

## 24. Analytics TEXT-Version Adapter

Analytics stores the version as TEXT: `analytics.analytics_events.event_version TEXT NOT NULL DEFAULT '1'` (068 L29) and `analytics.event_schema_versions.event_version TEXT NOT NULL` (073). The executed ingest function `analytics.fn_ingest_analytics_event` performs no version check (068 L89–106; DET-16). The adapter below is the consumer-side bridge (IO-7C-06). It is owned by Analytics.

| ID | Rule |
|---|---|
| ADP-01 | The integer on the envelope is canonical (DET-07). TEXT is a physical projection for Analytics columns only. |
| ADP-02 | The adapter validates the envelope first (§32 steps 1–4). It then projects the version with the decimal string form of the integer: `1` → `'1'`. No other formatting is used. |
| ADP-03 | Any TEXT version the adapter reads back or compares must match `^[1-9][0-9]*$` and be ≤ 2147483647. `'01'`, `'v1'`, `'V1'`, `'1.0'`, `' 1'`, `'1 '` and `''` are invalid. They are never normalized into `'1'`. |
| ADP-04 | Version validation happens in the adapter, before `fn_ingest_analytics_event` is called. The function is not relied on for it (DET-16). |
| ADP-05 | The adapter looks up the row for (`event_type`, projected version) in `analytics.event_schema_versions` and acts on its status as in the table below. |
| ADP-06 | The adapter never inserts or updates `analytics.event_schema_versions`. `app_worker` holds SELECT only on that table (073 grants). Registration is an Analytics administrative change (IO-7C-11). |
| ADP-07 | `tool_execution.started` (PAY-D-02) has no seeded row (PD2-03). Until IO-7C-11 registers it, the adapter treats it as a missing row, never as a known type. |
| ADP-08 | TEXT never appears on the internal envelope. A producer never emits `"1"` because Analytics stores TEXT. |
| ADP-09 | The version stored by Analytics is the event's original `event_version`, even when the consumer upcast the event in memory (UPC-09). |
| ADP-10 | `analytics.analytics_events` has `correlation_id UUID NULL` and `causation_id UUID NULL` (068). The adapter copies the envelope values when the keys are present and stores `NULL` when the envelope lacks them (durable rows written before OD-7C-04 activation). It never derives, fabricates or substitutes a value (for example it never copies `event_id` or `aggregate_id` into either column). |
| ADP-11 | A consequence of ADP-05: any (`event_type`, version) that Analytics consumes but has not registered is not ingested. IO-7C-11 must register every pair Analytics consumes before its projection is enabled. |

**ADP-05 status handling:**

| Registry row for (`event_type`, version) | Adapter action |
|---|---|
| `ACTIVE` | Ingest. |
| `DEPRECATED` | Ingest, and emit an observability signal (type and version only, no values). The version is still inside its coexistence window (§34). |
| `RETIRED` | Do not ingest. Handle as an unknown version (§33); disposition per 7G. |
| No row | Do not ingest. Handle as an unknown version (§33); disposition per 7G. |

---

## 25. Analytics Registry Reconciliation

### 25.1 Physical registry — `analytics.event_schema_versions` (`073`)

| Column | Type / default |
|---|---|
| `id` | `UUID NOT NULL DEFAULT gen_uuid_v7()` |
| `event_type` | `TEXT NOT NULL` |
| `event_version` | `TEXT NOT NULL` |
| `status` | `TEXT NOT NULL DEFAULT 'ACTIVE'`; `chk_esv_status CHECK (status IN ('ACTIVE','DEPRECATED','RETIRED'))` |
| `introduced_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` |
| `deprecated_at` | `TIMESTAMPTZ NULL` |
| `notes` | `TEXT NULL` |

- Unique key: `uq_esv_type_ver UNIQUE (event_type, event_version)`. There is no `retired_at` column.
- Grants: SELECT to `app_api`, `app_worker`, `app_readonly`; SELECT, INSERT, UPDATE to `app_platform_admin`.
- Seed (`075`): 25 rows, every one at `event_version = '1'` and `status = 'ACTIVE'`. The seed is migration content. It does not prove what rows exist in any deployed database today.

### 25.2 Rules

| ID | Rule |
|---|---|
| ARR-01 | `analytics.event_schema_versions` is the Analytics ingest registry. It is not the platform schema registry (OD-7C-03; DET-15). Its rows neither define nor prove any internal schema. |
| ARR-02 | 7C does not register the 105 durable events or the PAY-D signals in it, does not change any row, and does not change its DDL. |
| ARR-03 | Its status names are the same words as the lifecycle states in §38. Analytics mirrors the platform lifecycle of the pairs it consumes (IO-7C-11). The mirror follows the manifest; it never leads it. A status change made only in this table never changes a platform lifecycle state. |
| ARR-04 | There is no `retired_at` column. 7C does not require one. Retirement time, if Analytics needs it, is an Analytics change. |
| ARR-05 | 7B §25.1 already reconciles all 25 seeded names: 12 are durable events (EV-005, EV-006, EV-023, EV-024, EV-026, EV-046, EV-079, EV-085, EV-090, EV-091, EV-097, EV-102); 4 are Class-D signal names (DS-17 `conversation.turn_completed` = PAY-D-01; DS-19 `tool_execution.succeeded` and `tool_execution.failed` = PAY-D-02 members; DS-18 `provider.failover_triggered`, which has no 7C binding); 2 are CCPU names (`call.started` CCPU-01, `usage.event_recorded` CCPU-02); and 7 are FUT names (`invoice.payment_succeeded` FUT-04, the three `webhook.delivery_*` rows FUT-05…07, and `provider.failed`, `provider.circuit_opened`, `provider.circuit_closed` FUT-08…10). 7C binds a V1 schema only for the 12 durable events and the PAY-D members. A seeded name without a 7C binding has no internal schema, and its row creates none. 7C adds no rename (7B NAM-01). |
| ARR-06 | 6L L124 and 6L L823 (row 13) say `analytics.event_schema_versions` was "NOT FOUND" in the executed migrations 067–104. That is stale: `073` creates the table. 6L is not edited. The discrepancy is recorded in §49 and §51. It has no API effect, because 6L exposes no endpoint that depends on the finding. |

---

## 26. Canonical Schema Registry Strategy

OD-7C-03 = A: schemas are code-owned and version-controlled.

| ID | Rule |
|---|---|
| CSR-01 | §10, §11 and §20 – §22 of this document are the normative V1 source for every internal event and SIGNAL schema. |
| CSR-02 | The code-owned manifest (IO-7C-02) is keyed by (`event_type`, integer `event_version`). For each key it carries: profile and class; `aggregate_type` and `aggregate_id` semantics; organization scope; `occurred_at` source; causation source (CAU-06); the payload schema (field names, §18 types, requiredness, nullability, enums, scale); lifecycle status (§38); and the [7I] marks. Every manifest entry is an exact (`event_type`, version) pair. 104 of the 105 durable bindings have an exact frozen name and enter the manifest directly. EV-014 `tool_definition.*` is a frozen 7B family (FAM-01) with no frozen member names; how the manifest represents it is OD-7C-07 (§46.8), not decided, and P1-7C-04 stays OPEN until it is. Until then no entry for EV-014 exists, and no claim is made that all 105 bindings are registered as exact pairs. |
| CSR-03 | CI conformance checks (IO-7C-03) prove that every producer emits, and every consumer declares support for, only (`event_type`, version) pairs in the manifest, and that the manifest reproduces the V1 baseline of this document. |
| CSR-04 | There is no database-backed platform schema registry, no schema-registry service and no network lookup at produce or consume time. |
| CSR-05 | `analytics.event_schema_versions` is not canonical (ARR-01). |
| CSR-06 | A COMPATIBLE change (§28) amends the existing manifest entry for the same (`event_type`, N). Its history is the version-control history. There is no wire-level schema revision field. |
| CSR-07 | A BREAKING change (§29) adds a new entry for N + 1. The entry for N stays until N is RETIRED (§38), and stays in history afterwards. |
| CSR-08 | Before IO-7C-02 is delivered, this document is the only source. After it is delivered, the manifest is the single machine-readable source. It must reproduce the V1 baseline here exactly, and every later change record in it carries its §27 classification. A change to the envelope profile (key set, field names, field types), to a profile rule or to a rule in this document still requires a 7C amendment; the amendment does not replace the §27 classification of each affected type (CMP-06). |

---

## 27. Compatibility Model

OD-7C-01 = A: only a breaking change bumps `event_version`.

### 27.1 Classes

| Class | Meaning | Effect on `event_version` |
|---|---|---|
| **COMPATIBLE** | Meets every condition of CPT-01 | Unchanged (N) |
| **BREAKING** | Same fact, changed shape that an existing consumer or the existing backlog cannot tolerate | N + 1 (§29) |
| **SEMANTIC_NEW_EVENT** | The fact itself changes | A new `event_type` starting at 1, by a governed 7B change (§30) |
| **PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW** | Adds or changes sensitive, PII or [7I]-class content, or anything near §19.3 | Blocked until 7I and the owner review it; then reclassified |

### 27.2 Rules

- **CMP-01.** Every proposed change to an internal event or SIGNAL schema is exactly one of the four classes above.
- **CMP-02.** The change is classified before it is implemented. The classification is recorded with the manifest change (CSR-08).
- **CMP-03.** A change made of several parts takes the most restrictive class of its parts: PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW, then SEMANTIC_NEW_EVENT, then BREAKING, then COMPATIBLE.
- **CMP-04.** A change that the matrix does not list is BREAKING unless every CPT-01 condition is shown to hold. It is escalated instead where §30 (the fact changes) or §42 (sensitive content) applies.
- **CMP-05.** A PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW change is not implemented while in that class. After 7I and the owner review it, it is reclassified as COMPATIBLE, BREAKING or SEMANTIC_NEW_EVENT and follows that class. Content listed in §19.3 is never permitted, whatever the review.
- **CMP-06.** A change to the envelope (§10, §11) is classified by what it changes (VRS-08). (a) A change to the meaning of an interpretation-relevant envelope field of one or more event types (organization scope, aggregate, occurrence time, identity) is classified per type by §27.4 like a payload change: BREAKING (N + 1 of each affected type) or SEMANTIC_NEW_EVENT. (b) A new optional envelope key that meets all four KEY-07 conditions is COMPATIBLE and keeps every `event_version`; the OD-7C-04 `correlation_id` / `causation_id` addition is this case. (c) A change to relay bookkeeping or transport-only state is not a schema change and never changes an `event_version`. (d) A change to the envelope profile itself (its key set, a field name or a field type) additionally needs a 7C amendment; it is still classified per affected type by (a) or (b).
- **CMP-07.** These are not schema changes: a new value of an OPEN code (REG-09) or publication of its known values; adding a consumer; an editorial clarification that changes no field, type, rule or meaning.

### 27.3 Change matrix

| # | Change | Class |
|---|---|---|
| MX-01 | Add an OPTIONAL, non-sensitive, meaning-preserving payload field that meets CPT-01 | COMPATIBLE |
| MX-02 | Add a REQUIRED payload field | BREAKING |
| MX-03 | Remove a payload field | BREAKING |
| MX-04 | Rename a payload field | BREAKING |
| MX-05 | Change a field's §18 JSON type | BREAKING |
| MX-06 | Change a field's nullability, in either direction (reader semantics: CAT-06) | BREAKING |
| MX-07 | Change a field's requiredness, in either direction | BREAKING |
| MX-08 | Add a value to a closed enum | BREAKING |
| MX-09 | Change the meaning or derivation of an existing field while keeping its name | BREAKING |
| MX-10 | Remove a closed-enum value, or narrow a range, length or other constraint | BREAKING |
| MX-11 | Change the fact the event records | SEMANTIC_NEW_EVENT |
| MX-12 | Change the aggregate the event is about (`aggregate_type` or the meaning of `aggregate_id`) so that the fact concerns a different entity (CAT-12 (a)). Re-identifying the same entity is CAT-12 (b), BREAKING | SEMANTIC_NEW_EVENT |
| MX-13 | Change the emission trigger or cardinality (for example once per conversation → once per turn) | SEMANTIC_NEW_EVENT |
| MX-14 | Change the organization scope (organization-scoped ↔ platform-scoped), or the organization the fact is attributed to (CAT-11 (a)). A representation change for the same organization is CAT-11 (b), BREAKING | SEMANTIC_NEW_EVENT |
| MX-15 | Change the `occurred_at` source or the occurrence-time meaning (CAT-13) | BREAKING |
| MX-16 | Add a field, or widen an existing one, so that it carries sensitive, PII or [7I]-class content, or anything near §19.3 | PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW |
| MX-17 | Change the unit, scale or format of an existing field (for example seconds → minutes, scale 4 → scale 2) | BREAKING |
| MX-18 | EVENT level: split one event type into several event types, or merge several event types into one. This is not a field split or merge; splitting one FIELD into several is CAT-18 and merging several FIELDS into one is CAT-19 | SEMANTIC_NEW_EVENT |
| MX-19 | Change the class, mechanism or owning domain of an event | SEMANTIC_NEW_EVENT |
| MX-20 | Add an OPTIONAL, non-sensitive, meaning-preserving key inside an existing object field that meets CPT-01 | COMPATIBLE |
| MX-21 | Close an OPEN code into an enum, or change an array between *set* and *list* semantics | BREAKING |

### 27.4 Required change categories

Remediation (P1-7C-03): the checkpoint matrix above did not name every change category that the 7C contract requires, and it offered an EVENT split or merge (MX-18) where a FIELD split or merge was required. The table below classifies all 21 required categories. Each row is normative and gives one class for each stated condition. The MX rows stay in force. Where a CAT row and an MX row both apply, they give the same class. MX-13, MX-19 and MX-21 are additional categories beyond the 21.

"Field" in this table means a payload field, a key inside an object field, or an interpretation-relevant envelope field (VRS-08, CMP-06 (a)). A change to an envelope field also needs a 7C amendment (CMP-06 (d)). A change made of several categories takes the most restrictive class (CMP-03). Every BREAKING row creates N + 1 (§29). Every SEMANTIC_NEW_EVENT row creates a new `event_type` through 7B (§30), never an N + 1.

| # | Category | Class | Exact condition | Matrix / rule |
|---|---|---|---|---|
| CAT-01 | Add optional field | COMPATIBLE | Only when every CPT-01 condition holds: the field is OPTIONAL and non-sensitive, the meaning of the existing contract is unchanged, and a consumer that ignores it reaches the same outcome. A sensitive field is CAT-16. If any other CPT-01 condition fails, the change is BREAKING (CMP-04). | MX-01, MX-20, CPT-01 |
| CAT-02 | Add required field | BREAKING | Always. Events committed at N do not carry the field (CPT-02). | MX-02 |
| CAT-03 | Remove field | BREAKING | Always, whether the field was REQUIRED or OPTIONAL. The removed name is never reused (CPT-01 (g)). | MX-03 |
| CAT-04 | Rename field | BREAKING | Always, even when the type and meaning stay the same. | MX-04 |
| CAT-05 | Change JSON type | BREAKING | Always, including a widening (for example integer → string, or decimal string → number). | MX-05 |
| CAT-06 | Change nullability | BREAKING | **Both directions are BREAKING, according to reader semantics.** (a) REQUIRED non-null → nullable: a consumer of N relies on the binding's NON-NULL (SER-01) and reads the field as never `null`, so a newly emitted `null` makes it fail or decide wrongly. This holds even though the committed backlog stays valid. (b) OPTIONAL or nullable → REQUIRED non-null: events committed at N that omit the field or carry `null` become invalid under N (CPT-02). A requiredness change follows the same rule (MX-07). | MX-06, MX-07 |
| CAT-07 | Change enum vocabulary | BREAKING (closed enum) | (a) Adding a value to a closed enum is BREAKING (MX-08). (b) Removing a closed-enum value is BREAKING (MX-10). (c) Renaming a closed-enum value is BREAKING (MX-04 / MX-10). (d) Changing the meaning of a closed-enum value is BREAKING (MX-09), or SEMANTIC_NEW_EVENT when NEV-02 answers yes. (e) A new value of a field that §20 – §22 marks OPEN (REG-09) is not a schema change (CMP-07) and keeps `event_version`, which is the same outcome as COMPATIBLE; consumers apply the tolerant-reader rule of REG-09. (f) Closing an OPEN code into an enum is BREAKING (MX-21). | MX-08, MX-10, MX-21, REG-09 |
| CAT-08 | Change units | BREAKING | Always. This covers the unit, scale, precision or format of an existing field (for example seconds → minutes). | MX-17 |
| CAT-09 | Change business meaning | SEMANTIC_NEW_EVENT | Whenever NEV-02 answers yes: a consumer adapted to the new layout would still draw a wrong business conclusion because the fact is different. The fact gets a new `event_type` (§30). It is never disguised as N + 1 (NEV-08). If NEV-02 answers no, and only the derivation of one field changes while the fact stays the same, the change is not CAT-09. It is MX-09, BREAKING. | MX-11, MX-09, NEV-02 |
| CAT-10 | Move field between nesting levels | BREAKING | Always, even with unchanged name, type and meaning. This covers payload → envelope, envelope → payload, top level → inside an object, inside an object → top level, and one object → another object. | MX-03 + MX-01 (a move is a removal plus an addition) |
| CAT-11 | Change tenant / organization semantics | SEMANTIC_NEW_EVENT or BREAKING | (a) **SEMANTIC_NEW_EVENT** when the same fact can no longer be safely interpreted, because the same underlying occurrence would be attributed to a different tenant or scope class under the new rule. This covers organization-scoped ↔ platform-scoped, attribution to a different organization (for example the acting organization instead of the owning one), or a change to what `organization_id` means for the type. (b) **BREAKING** when every occurrence is still attributed to the same organization, with an identical `organization_id` value under N and N + 1, and only the representation changes. This covers the name, type, location or format of an organization-referencing field. Either way, TEN-C02 / TEN-C03 continue to apply, and EV-001 stays the only platform-scoped type unless 7B changes it. | MX-14 |
| CAT-12 | Change aggregate semantics | SEMANTIC_NEW_EVENT or BREAKING | (a) **SEMANTIC_NEW_EVENT** when the fact becomes about a different entity. Either `aggregate_id` identifies a different entity instance for the same occurrence, or `aggregate_type` names a different kind of entity. (b) **BREAKING** when every occurrence still identifies the same entity instance, and only the label or identifier form changes. Examples are an `aggregate_type` string renamed for the same entity kind, or `aggregate_id` switched to another identifier that maps 1:1 to the same entity. | MX-12 |
| CAT-13 | Change occurrence-time meaning | BREAKING | Always, with N + 1. This covers a change to the `occurred_at` source column, to the clock, to the moment it represents (for example "request accepted" → "row committed"), or to its precision. If the emission trigger or cardinality also changes, MX-13 applies as well, and CMP-03 makes the change SEMANTIC_NEW_EVENT. | MX-15 |
| CAT-14 | Change event identity semantics | BREAKING | Always, with N + 1. This covers the meaning of `event_id` (one UUIDv7 per occurrence, §12) and of any payload identifier that consumers use for deduplication or joins. A change to the envelope `event_id` rule also needs a 7C amendment (CMP-06 (d)). | MX-09 |
| CAT-15 | Change money representation | BREAKING | Always, even when the numeric value is equal. This covers a change to the §18 money type (decimal string ↔ number ↔ integer minor units), to the scale, to the currency field or its presence, or to rounding. | MX-05, MX-17 |
| CAT-16 | Introduce sensitive-data exposure | PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW | Any added field, widened field or changed derivation that would carry sensitive, PII or [7I]-class content. It is reclassified only after review (CMP-05). Content listed in §19.3 is never permitted. | MX-16 |
| CAT-17 | Scalar → array/object | BREAKING | Always, and in both directions (array/object → scalar). | MX-05 |
| CAT-18 | Split one field into several | BREAKING, unless the stated condition holds | **COMPATIBLE only when all of these hold:** (i) the original field keeps its name, type, requiredness, nullability, unit and meaning; (ii) the original stays authoritative, the new fields never contradict it, and a producer never emits a disagreement; (iii) every new field is OPTIONAL, non-sensitive and derived only from the original value; (iv) each new field meets CPT-01. Otherwise the change is BREAKING. A split that removes or narrows the original is always BREAKING (CAT-03). This row is the FIELD split. Splitting an EVENT type is MX-18. | CAT-01, CAT-03, MX-09 |
| CAT-19 | Merge several fields into one | BREAKING, unless the stated condition holds | **COMPATIBLE only when all of these hold:** (i) every original field stays present, with its name, type, requiredness, nullability, unit and meaning unchanged; (ii) the originals stay authoritative, the merged field never contradicts them, and a producer never emits a disagreement; (iii) the merged field is OPTIONAL, non-sensitive and derived only from the originals; (iv) it meets CPT-01. Otherwise the change is BREAKING. A merge that removes any original field is always BREAKING (CAT-03). This row is the FIELD merge. Merging EVENT types is MX-18. | CAT-01, CAT-03, MX-09 |
| CAT-20 | Add optional nested object | COMPATIBLE, only when the stated condition holds | **COMPATIBLE only when all of these hold:** (i) the object key is OPTIONAL, and a consumer that ignores the whole object reaches the same outcome; (ii) every key inside it is non-sensitive; (iii) no existing field moves into it (a move is CAT-10) and no existing semantics change; (iv) it meets CPT-01. Otherwise the change takes the class of the condition that fails (CMP-03): sensitive content is CAT-16, and a changed meaning is CAT-09 or MX-09. After the object is in the manifest, adding a REQUIRED key inside it is CAT-02. | MX-01, MX-20 |
| CAT-21 | Change default behavior | BREAKING | BREAKING whenever an omitted, absent or `null` value gains a different meaning. One example is an absent OPTIONAL field that meant "not provided" (SER-02) and now means `false` or `0`. Another is a producer that now emits a different value for the same underlying state. A default that never reaches an emitted event and changes no emitted value is not a schema change. | MX-09, SER-02, CPT-05 |

- **CAT-R01.** All 21 categories above are classified. A proposed change is matched against every CAT and MX row, and it takes the most restrictive class that applies (CMP-03).
- **CAT-R02.** FIELD split and merge (CAT-18, CAT-19) and EVENT split and merge (MX-18) are different categories. Neither stands in for the other.
- **CAT-R03.** P1-7C-03 is RESOLVED by this section. It required no owner decision.

---

## 28. Compatible Changes

- **CPT-01.** A change is COMPATIBLE only if all of these hold:
  - (a) the added field or key is OPTIONAL (SER-01), never REQUIRED;
  - (b) it is non-sensitive: not PII, not [7I]-class and nothing listed in §19.3. Otherwise the change is MX-16;
  - (c) no existing field changes its name, type, unit, scale, requiredness, nullability, enum set or meaning;
  - (d) no consumer has to act on it to stay correct: a consumer that ignores it reaches the same outcome as before;
  - (e) the fact, cardinality, `occurred_at` source, aggregate and organization scope are unchanged;
  - (f) the payload still meets PAY-01 … PAY-04: at most 262144 bytes, no full aggregate snapshot, no repeated envelope metadata;
  - (g) the name has never been used before in that event type's history.
- **CPT-02.** **Backlog-validity invariant.** Every event ever committed at (`event_type`, N) must validate against the current schema of (`event_type`, N). This is why adding a REQUIRED field, removing a field and narrowing a constraint are BREAKING: each would make committed events invalid under their own version.
- **CPT-03.** A COMPATIBLE change keeps the same `event_version` (OD-7C-01).
- **CPT-04.** The manifest entry is amended (CSR-06) before any producer emits the new field.
- **CPT-05.** Consumers ignore unknown COMPATIBLE OPTIONAL fields (OD-7C-01). A consumer that uses the new field treats its absence as "not provided" (SER-02). It never reads absence as `null`, and never substitutes a default that changes an outcome, because events committed before the change do not carry the field.
- **CPT-06.** The producer schema is closed: a producer emits only the keys in the current manifest entry. The consumer schema is tolerant: a consumer accepts unknown payload keys. A removed name is never reused (CPT-01 (g)).
- **CPT-07.** Adding a closed-enum value is BREAKING here (MX-08). 6A §31.1 treats enum additions on the public API as additive. The difference is recorded in §49. It follows from CPT-02 and from consumers that switch on closed values.
- **CPT-08.** Example — HYPOTHETICAL: adding an OPTIONAL non-sensitive string field to EV-021 `contact.created` keeps `event_version` = 1. No such field is added by 7C.
- **CPT-09.** In §27.4, CAT-01 and CAT-20 are the COMPATIBLE categories. CAT-18 and CAT-19 are COMPATIBLE only when every stated condition holds. The KEY-07 optional envelope addition, including the OD-7C-04 `correlation_id` / `causation_id` addition, is COMPATIBLE and keeps every `event_version` (CMP-06 (b)). A new OPEN-code value (CAT-07 (e)) is not a schema change (CMP-07). Every other category is not COMPATIBLE.

---

## 29. Breaking Changes

- **BRK-01.** A BREAKING change creates version N + 1 of the same `event_type`, where N is the greatest version already defined for that type (VRS-03). Numbers are contiguous and never reused.
- **BRK-02.** N + 1 is a new manifest entry (CSR-07). The entry for N is kept until N is RETIRED.
- **BRK-03.** Each fact is emitted exactly once, at exactly one version. A producer never dual-publishes the same fact at N and N + 1, and never emits a compatibility copy (OD-7C-02).
- **BRK-04.** Rollout follows §35: consumers first, then the producer.
- **BRK-05.** Approval: the producing domain owner and the owner of every consumer that 7B lists for the type.
- **BRK-06.** A BREAKING change to the meaning of an interpretation-relevant envelope field (CMP-06 (a)) creates N + 1 of every affected `event_type`, exactly like a payload BREAKING change; a change to the envelope profile itself also needs a 7C amendment (CMP-06 (d)). The OD-7C-04 correlation / causation addition is not BREAKING (KEY-07) and creates no N + 1. No BREAKING envelope change is planned.
- **BRK-07.** No N + 1 exists for any type today. Every type is at 1 (VRS-07).
- **BRK-08.** Example — HYPOTHETICAL: renaming a payload field of EV-021 `contact.created` would create `contact.created` version 2 (N + 1 with N = 1); 7C defines no such version.
- **BRK-09.** BRK-01 … BRK-05 apply to every BREAKING row of §27.4: CAT-02 … CAT-08, CAT-10, CAT-11 (b), CAT-12 (b), CAT-13, CAT-14, CAT-15, CAT-17, CAT-21, and CAT-18 / CAT-19 when their condition fails. They apply equally when the changed field is an interpretation-relevant envelope field (CMP-06 (a)), for example a changed `occurred_at` meaning. An N + 1 is never used for a SEMANTIC_NEW_EVENT change (NEV-08).

---

## 30. New Event vs New Version

- **NEV-01.** The `event_type` names the fact. The `event_version` names the shape of that fact.
- **NEV-02.** **Test.** Ask whether a consumer written for the existing type, after it has adapted to the new field layout, would still draw a wrong business conclusion because the thing that happened is different. If yes, the change is SEMANTIC_NEW_EVENT. If no, it is BREAKING or COMPATIBLE.
- **NEV-03.** A SEMANTIC_NEW_EVENT change needs a governed 7B change that creates a new `event_type`. Its first version is 1.
- **NEV-04.** The old type is deprecated and retired (§38). It is never repurposed (VER-04).
- **NEV-05.** Alternative C of OD-7C-01, "every change is a new type", was rejected. It would multiply catalogue entries under 7B governance for changes that do not change the fact, and it would break the continuity of the fact for consumers.
- **NEV-06.** A new type never carries a version suffix (`…_v2`, `….v2`) (DET-08).
- **NEV-07.** 7C adds no event type.
- **NEV-08.** A change to the business fact (CAT-09, CAT-11 (a), CAT-12 (a), MX-11, MX-13, MX-18, MX-19) creates a new `event_type` through a governed 7B change (NEV-03). It is never disguised as N + 1 of the existing type. N + 1 is only for a BREAKING change of the same fact (§29). A proposed N + 1 whose NEV-02 answer is yes is rejected and reclassified as SEMANTIC_NEW_EVENT.

---

## 31. Producer Validation

Producer validation is IO-7C-04.

- **PV-01.** A durable producer validates the complete envelope and payload before the producing transaction commits. A SIGNAL producer validates before the first publish attempt.
- **PV-02.** The checks:

| Check | What is validated |
|---|---|
| PV-C01 | Envelope key set: exactly ENV-01 … ENV-10 for the current persistence phase (§10.5), or SIG-01 … SIG-11 |
| PV-C02 | The 7B class and profile of the type. `durability` is present only on SIGNAL and equals `"SIGNAL"` (SIG-R02) |
| PV-C03 | `event_version` has the VRS-04 valid form and equals this producer build's target version for the type |
| PV-C04 | Organization scope (TEN-C02, TEN-C03) |
| PV-C05 | `aggregate_type` and `aggregate_id` per the binding (§14) |
| PV-C06 | `occurred_at` source and six-digit format (§15) |
| PV-C07 | Closed payload key set of the manifest entry, and every REQUIRED key present |
| PV-C08 | §18 types, nullability, enum vocabularies and decimal scale |
| PV-C09 | Canonical serialization (§18; no duplicate keys, no JSON float for precision-sensitive values) |
| PV-C10 | Binding invariants (for example USG-01 … USG-10, DET-13) |
| PV-C11 | Size (PAY-02) |
| PV-C12 | Security exclusions (§19.3) and PAY-04 |
| PV-C13 | `correlation_id` / `causation_id` follow the persistence phase (§10.5) and §16 / §17, and never appear in `payload` |

- **PV-03.** A producer build targets exactly one version per `event_type`. During a rollout, instances of different builds may run at the same time (RD-R03).
- **PV-04.** A durable validation failure rolls back the producing transaction. No outbox row is written.
- **PV-05.** A SIGNAL validation failure means the signal is not published, and an observability record is written. It is never silent.
- **PV-06.** A producer never repairs an invalid event (no trimming, defaulting, coercion or key dropping) to make it pass.
- **PV-07.** The relay never validates, repairs or rewrites events (DET-09).
- **PV-08.** Validation errors name the event type, version, field path and rule ID. They never contain field values.
- **PV-09.** Database CHECK constraints are a backstop only. They do not replace PV-C01 … PV-C13.

---

## 32. Consumer Validation

Consumer validation and dispatch are IO-7C-05. A consumer processes every delivery in this order:

| Step | Action |
|---|---|
| CV-01 | Parse the envelope. Duplicate keys make it invalid. |
| CV-02 | Validate the envelope fields (§10 or §11), including the `event_version` form (VRS-04). A malformed version is a violation (UV-06). |
| CV-03 | Look up (`event_type`, `event_version`) in the consumer's declared supported set (COX-06). An unknown type goes to 7E's unknown-type handling (UV-07). An unknown version goes to §33. |
| CV-04 | Validate the payload against the schema of the **original** version. Unknown payload keys are ignored (CPT-05, CPT-06). |
| CV-05 | Optionally upcast in memory (§37). |
| CV-06 | Apply the 7F idempotency guard, then the handler's side effects. |
| CV-07 | Acknowledge per 7E. |

- **CV-08.** A failure in CV-01 … CV-05 causes no side effect, no repair, no partial apply and no success acknowledgement. The event is routed per 7G and an observability record is written.
- **CV-09.** A consumer never fixes, defaults or coerces a field to make an event valid.
- **CV-10.** The presence or absence of `correlation_id` / `causation_id` never affects validation or processing (CC-04). Unknown top-level keys are ignored (KEY-03, SIG-R05).
- **CV-11.** A contract violation is a producer defect. The fix is made in the producer. The committed event is never rewritten (DET-09).

---

## 33. Unknown-Version Handling

- **UV-01.** An unknown version is a well-formed `event_version` (VRS-04 valid) of a known `event_type` that is not in the consumer's supported set, or that is RETIRED.
- **UV-02.** The consumer never guesses. It never selects the nearest or the greatest version it knows, never falls back to a default handler, never applies part of the event and never downcasts.
- **UV-03.** It performs no side effect, never drops the event silently and never acknowledges it as successfully processed.
- **UV-04.** The event is held or routed as 7G defines, and it is preserved unchanged.
- **UV-05.** An observability signal records the type, version, consumer and stream. It contains no field values.
- **UV-06.** A malformed `event_version` (any VRS-04 INVALID form) is a contract violation handled by CV-08, not an unknown version.
- **UV-07.** An unknown `event_type` is handled by 7E. It causes no side effect.
- **UV-08.** In a conformant rollout (§35) an unknown version never reaches a consumer. If one does, it raises an alert.
- **UV-09.** The Analytics adapter's RETIRED and missing-row cases (ADP-05) are handled the same way.

---

## 34. Version Coexistence

- **COX-01.** A consumer supports every version of a type it consumes that can still reach it: a version still produced by any running producer build, still in the outbox or a stream, pending, in a DLQ or parking area, or inside a replay window (7G / 7K).
- **COX-02.** Support means either a native handler for that version or an upcast chain (§37) from it to a version the consumer handles natively.
- **COX-03.** Coexistence is per type. Versions of different types are independent (VRS-02).
- **COX-04.** A version's coexistence window ends only when it is RETIRED (§38).
- **COX-05.** A version number never implies recency or delivery order. An event at N may be delivered after an event at N + 1 of the same type, and the consumer handles each on its own terms.
- **COX-06.** Each consumer declares its supported set of (`event_type`, version) pairs in code. CI checks the set against the manifest (IO-7C-03).

---

## 35. Rolling Deployment

A BREAKING change to type T from N to N + 1 is deployed in this order:

| Step | Action |
|---|---|
| RD-01 | Deploy every consumer of T with support for both N and N + 1 (native or upcast). |
| RD-02 | Verify that every consumer group of T runs a build that supports both versions. |
| RD-03 | Switch the producer build to target N + 1. |
| RD-04 | Keep support for N while any N event can still be delivered (COX-01). |
| RD-05 | Mark N DEPRECATED when the producer switch is complete, and RETIRED when RET-03 holds (§38). |

- **RD-R01.** Consumers are upgraded before producers.
- **RD-R02.** There is no dual-write and no dual-publish (BRK-03).
- **RD-R03.** While producer instances of both builds run, each instance emits each fact once, at its own build's version.
- **RD-R04.** Rolling a producer back to N is safe. Events already committed at N + 1 stay as they are and are still consumed.
- **RD-R05.** Rolling a consumer back to a build without N + 1 support is prohibited while any N + 1 event can still reach it.
- **RD-R06.** Stream checkpoints, consumer-group handling and pause or drain procedures are 7E's.
- **RD-R07.** Database migrations follow DPL-01 … DPL-05.

---

## 36. Backlog and Replay

- **BR-01.** A committed durable event is immutable. Its envelope and payload are never rewritten (DET-09).
- **BR-02.** Replay re-delivers the exact committed fields (RPL-05). SIGNAL events are not durable and are not replayable from an outbox (SIG-R03).
- **BR-03.** Events are never re-emitted at a new version to upgrade a backlog.
- **BR-04.** Old versions in a backlog or replay are handled natively or by upcast (§34, §37).
- **BR-05.** Rows written before OD-7C-04 activation carry no `correlation_id` / `causation_id`. Replay never back-fills them (CC-02).
- **BR-06.** Replay windows and retention are 7G / 7K's.
- **BR-07.** A committed event that violates its contract is never repaired. The producer is fixed forward.

---

## 37. Upcasting

OD-7C-02 = B: constrained consumer-side upcasting.

- **UPC-01.** Upcasting is optional. A consumer may instead handle each supported version natively.
- **UPC-02.** An upcaster runs only after the event has passed validation against its original version (CV-04).
- **UPC-03.** It works in memory only. Its output is never persisted, never written to an outbox and never republished.
- **UPC-04.** It is pure: no I/O, database, network, clock, random source, environment variable or configuration read.
- **UPC-05.** It is deterministic: the same input always gives the same output.
- **UPC-06.** It preserves information. Every fact in the N event is carried into the N + 1 form, and it adds only values that are fully determined by the N event. If the N + 1 shape needs information the N event does not contain, no upcaster exists for that step and the consumer handles N natively.
- **UPC-07.** Each upcaster converts one step, N → N + 1. Steps are chained for larger gaps.
- **UPC-08.** There is no downcasting.
- **UPC-09.** Envelope metadata is unchanged, including `event_id` and `event_version`. Every record the consumer writes uses the original version (ADP-09).
- **UPC-10.** Producers and the relay never upcast.
- **UPC-11.** Upcaster code may be shared as a library, but each consumer decides whether to invoke it.
- **UPC-12.** An upcaster never adds content listed in §19.3 or any sensitive or PII value.

---

## 38. Deprecation and Retirement

- **RET-01.** Lifecycle states of an (`event_type`, version) pair:

| State | Meaning |
|---|---|
| ACTIVE | Produced by a current producer build and consumed |
| DEPRECATED | No longer targeted by any current producer build; still supported by consumers because instances can still be delivered |
| RETIRED | No longer supported; no instance can still be delivered |

- **RET-02.** A version becomes DEPRECATED when the producer switch to N + 1 is complete (RD-05).
- **RET-03.** A version becomes RETIRED only when all of these hold:
  - (a) no running producer build targets it;
  - (b) no instance remains in the outbox, a stream, a pending list, a DLQ or a parking area;
  - (c) every replay window that could re-deliver it has passed, or 7G excludes it from replay;
  - (d) the producing owner and every consumer owner approve.
- **RET-04.** A RETIRED version that is nevertheless delivered is handled as an unknown version (§33).
- **RET-05.** A retired version stays in the manifest history. Its number is never reused.
- **RET-06.** Retiring an event **type** is a governed 7B change, not a 7C version action.
- **RET-07.** Every current pair is at version 1 and ACTIVE.
- **RET-08.** Analytics mirrors lifecycle states in `analytics.event_schema_versions` (IO-7C-11; ARR-03). There is no `retired_at` column (ARR-04).
- **RET-09.** DEPRECATED returns to ACTIVE only when the producer is rolled back to that version (RD-R04). RETIRED is terminal.

---

## 39. WebSocket Boundary (AX-D)

- **WSB-01.** The WebSocket envelope of 6A §27.3 (`event_id, event_type, version, timestamp, organization_id, resource_id, sequence, payload`) is unchanged (DET-18).
- **WSB-02.** The WS `version` is AX-D. It is independent of the internal `event_version` (VER-02, VER-08). An internal version change never changes a WS `version`, and a WS version change never changes an internal one.
- **WSB-03.** The WS `event_id` is a separate identifier governed by 6A §27.3 (ID-03). It is not the internal `event_id`.
- **WSB-04.** A Class-F message derived from an internal event is a projection defined by its owner (7B RTM entries; 7H). The internal envelope is never forwarded verbatim.
- **WSB-05.** Internal-only fields (`correlation_id`, `causation_id`, `durability`, `event_version`, internal aggregate fields) are not exposed on WebSocket unless a WS contract lists them. 7C adds none.
- **WSB-06.** 7C adds no WS message, field or version. A WS name that matches an internal `event_type` (for example RTM-24 `tool_execution.succeeded`) implies no shared schema or version.

---

## 40. Webhook Boundary (AX-E, AX-F)

- **WHB-01.** The webhook envelope of 6J §20.1 (`id, type, version, occurred_at, organization_id, data.object, request_id`) and the `X-Platform-Webhook-Version` header are unchanged.
- **WHB-02.** The signature header `X-Platform-Signature: v1=…` and the signing input `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")` are unchanged. No `v2=` scheme exists (VER-06).
- **WHB-03.** The 19 CURRENT webhook topics are unchanged. Topics evolve only through the AX-E successor rule (VER-05).
- **WHB-04.** 7C defines no mapping from the internal `event_id` to the webhook `id`. The webhook `id` is governed by 6J §20.1 and 7H.
- **WHB-05.** Internal-only fields are never exposed in a webhook body unless the topic's contract lists them. 7C adds none.
- **WHB-06.** An internal `event_version` change never changes a webhook topic, topic version or signature scheme. A webhook-visible change follows AX-E rules in its own right.

---

## 41. Provider Callback Boundary

- **PCV-01.** Class-H provider callbacks (7B PCB-01 … PCB-03) keep their provider-native formats. 7C defines no schema for them.
- **PCV-02.** A raw provider callback payload is never placed in an internal event (§19.3).
- **PCV-03.** A fact derived from a callback is emitted under its own §20 binding (for example EV-004 `call.initiated` for an inbound call). Its `causation_id` after activation is the callback dedup row ID (CAU-W, CAU-04).
- **PCV-04.** Provider identifiers are carried only where a binding lists them.
- **PCV-05.** Class-E tasks and commands are not events and carry no internal envelope. A task may carry `correlation_id` (COR-T).
- **PCV-06.** Class-I audit records are written through `audit.fn_insert_audit_event()`. They are not internal events, not governed by this envelope and not a schema registry.

---

## 42. Security and Privacy

- **SP-01.** Internal event payloads and envelopes never contain:
  - access or refresh tokens;
  - API secrets, provider credentials or signing secrets;
  - secret-manager values;
  - signed or presigned URLs;
  - raw media;
  - transcript or raw utterance text;
  - raw provider callback payloads;
  - card data.
- **SP-02.** PV-C12 enforces SP-01 at the producer on every version.
- **SP-03.** Opaque, non-secret references are allowed only where the frozen contracts permit them. No V1 binding carries one (§19.3).
- **SP-04.** A new sensitive or PII field is never COMPATIBLE merely because it is OPTIONAL. It is MX-16, PROHIBITED_UNTIL_SECURITY_OR_OWNER_REVIEW, and needs 7I review first.
- **SP-05.** V1 fields marked [7I]: 26 durable fields (§20.8) and 3 SIGNAL fields (`llm_provider_ref`, `stt_provider_ref`, `tool_name`; §21), 29 in total. 7C binds their types; 7I decides their sensitivity.
- **SP-06.** No full aggregate snapshots (PAY-03).
- **SP-07.** EV-079 carries no pricing, cost, rate, margin, transcript, raw provider response, credential or signed URL (OD-7C-05).
- **SP-08.** An upcaster never adds sensitive content (UPC-12).
- **SP-09.** Validation errors and observability records carry no field values (PV-08, UV-05).
- **SP-10.** The envelope `organization_id` is the only authorization scope (DET-04, PAY-05).
- **SP-11.** The same exclusions and checks apply to every version of every type, not only V1.
- **SP-12.** Payload size is at most 262144 bytes (PAY-02).

---

## 43. EV-100 and DEP-6K-05

- **E100-01.** DEP-6K-05 stays OPEN. It does not block 7C.
- **E100-02.** EV-100 `workflow.execution.completed` carries only standalone-attributable LLM tokens in `llm_prompt_tokens` and `llm_completion_tokens` (DET-17).
- **E100-03.** In-turn LLM usage is carried by EV-079 (USG-10). The two are never counted twice.
- **E100-04.** No discriminator is defined: no `execution_context`, no `in_turn` flag. If one is added later, an OPTIONAL non-sensitive field is MX-01, a REQUIRED one is MX-02, and a change to what the token fields count is MX-09.
- **E100-05.** Whether the workflow runtime can tell in-turn from standalone execution is a 6E / 6I producer dependency (IO-7C-09), not a 7C representation gap.

---

## 44. Traceability

| Source requirement | Where 7C satisfies it |
|---|---|
| 7A EVT-02; 7B IDN-01 (event identity) | §12 |
| 7A EVT-03 (type, type-version, aggregate, occurrence) | §10, §14, §15, §23 |
| 7A TEN-01, TEN-06 (tenant scope) | §13; DET-02, DET-03 |
| 7A VER-01 … VER-08 (version axes, no repurposing) | §8, §23, §30, §39, §40 |
| 7A VER-03 / DD-22 (compatibility policy) | §27 – §38 |
| 7A DD-02 (envelope names) | §10, §11 |
| 7A DD-03 (registry; INT vs TEXT) | §23 – §26 |
| 7A OBS-02 (correlation / causation) | §10.5, §16, §17 |
| 7A DPL-01 … DPL-05 (deployment) | §35 |
| 7A RPL-05 (replay) | §36 |
| 7A SEC-01 … SEC-03 (secrets, identifiers, minimum PII) | §19.3, §42 |
| 7B IO-7B-04 (EV-079 envelope and fields) | §22 |
| 7B IO-7B-06 (payload names, types, versions) | §20, §21 |
| 7B L440 (aggregate) | §14 |
| 7B L735 (PAY-D-01 agent grain) | §21.1; DET-11 |
| 7B OCC-01 … OCC-07 | §15.3; OCC-C11 … OCC-C13 |
| 7B §25.1 (075 reconciliation) | §25; ARR-05 |
| OD-7C-01 | §27 – §30 |
| OD-7C-02 | §32, §35, §37 |
| OD-7C-03 | §26 |
| OD-7C-04 | §10.5, §16, §17 |
| OD-7C-05 | §22 |
| OD-7C-06 | §11, §12.2 |
| AVS axes AX-A … AX-L | §8, §39, §40 |
| EV-001 … EV-105 | §20.4 – §20.7 |
| PAY-D-01, PAY-D-02 | §21 |
| EV-079 usage | §22 |
| P1-7C-01 (correlation root precedence) | §16.1, §16.2 (COR-01 … COR-08), §16.3; CNF-7C-02; ADR-7C-19 |
| P1-7C-02 (`event_version` scope) | §23 (KEY-06, KEY-07, VRS-08), CMP-06, BRK-06, NEV-08; ADR-7C-20 |
| P1-7C-03 (21 change categories) | §27.4 (CAT-01 … CAT-21, CAT-R01 … CAT-R03), CPT-09, BRK-09, NEV-08; ADR-7C-21 |
| P1-7C-04 (EV-014 manifest representation) | CSR-02; §46.8 OD-7C-07 (OPEN) |
| P1-7C-05 (EV-062 `draft_revision`) | §20 EV-062 binding |
| P1-7C-06 (EV-105 schema) | §20 EV-105 binding |

---

## 45. ADR Register

| ADR | Decision | Context | Consequence | Basis |
|---|---|---|---|---|
| ADR-7C-01 | The logical envelope keeps the outbox column names. The only rename is `id` → `event_id`. | 7A DD-02 delegates envelope names to 7C. The executed outbox (077) already names every field. | No mapping layer beyond one rename. The relay publishes exactly what was committed. | DET-01, DET-09, §10 |
| ADR-7C-02 | Two envelope profiles, DURABLE and SIGNAL. The profile follows from the 7B class. | Classes A/B/C are outbox-backed. Consumed Class-D signals have no outbox row. | One set of core metadata names across both profiles. An event type never has two profiles. | PRF-01 … PRF-03, §9 |
| ADR-7C-03 | The internal `event_version` is a JSON integer. TEXT is an Analytics projection only. | The outbox column is `INTEGER` (077 L51); the Analytics columns are `TEXT` (068, 073). | One canonical wire form. Analytics owns a validating adapter. | DET-07, §23, §24 |
| ADR-7C-04 | Only a BREAKING change bumps `event_version`. | OD-7C-01 = A. | COMPATIBLE additions keep the version. Consumers ignore unknown compatible optional fields. | §27, §28, §29 |
| ADR-7C-05 | Upcasting is optional, consumer-side, in memory, pure, deterministic and lossless. Events are never rewritten and producers never dual-publish. | OD-7C-02 = B. | Consumers handle old versions natively or by upcast. The backlog stays immutable. | §32, §35, §37 |
| ADR-7C-06 | Schemas are code-owned and version-controlled. 7C is the normative V1 source; the manifest is materialized later. There is no database registry. | OD-7C-03 = A. | IO-7C-02 and IO-7C-03 deliver the manifest and CI conformance. `analytics.event_schema_versions` is not canonical. | §26 |
| ADR-7C-07 | `correlation_id` and `causation_id` become future outbox columns (`UUID`). They are never in the payload and never fabricated. There is no `command_id`. | OD-7C-04 = B. The current outbox has neither column. | Rows written before activation carry neither key. Activation is IO-7C-01. | §10.5, §16, §17 |
| ADR-7C-08 | EV-079 carries its usage inline. AI duration is decimal-string seconds; STT audio is decimal seconds; TTS characters and tokens are non-negative integers; attribution is reference-only and multi-provider. | OD-7C-05 = A. | Billing reads one self-contained fact. No pricing, cost, rate or margin crosses the bus. | §22, DET-12 |
| ADR-7C-09 | Class-D signals use the same core metadata plus `durability = "SIGNAL"`. The signal `event_id` is a producer UUIDv7 generated once per signal. | OD-7C-06 = A. | `durability` has no column and never reclassifies an event. A Redis entry ID is never an `event_id`. | §11, §12.2 |
| ADR-7C-10 | `analytics.event_schema_versions` is the Analytics ingest registry only. 7C neither registers events in it nor changes it. | 073 creates it; 075 seeds 25 rows. | Registration and lifecycle mirroring are IO-7C-11. | ARR-01 … ARR-06 |
| ADR-7C-11 | `occurred_at` comes from the binding's domain source, captured once. It is never relay, worker, Redis or recovery time. | 7A EVT-03; 7B OCC-01 … OCC-07. | No persisted source → no event (EV-079: OCC-C13; IO-7C-10). | §15 |
| ADR-7C-12 | Canonical serialization: decimals are strings at the column's exact scale; timestamps are RFC-3339 UTC with six fractional digits; no JSON floats for precision-sensitive values. | 6A §7.5 lineage; money and usage precision. | Byte-stable values across producers. The formatter is IO-7C-12. | §18, SER-03 |
| ADR-7C-13 | Every V1 field is REQUIRED, with nullability stated explicitly. OPTIONAL is reserved for later COMPATIBLE additions. | Absence and `null` must never be confused. | Consumers can rely on every V1 key being present. | SER-01, SER-02, SER-06 |
| ADR-7C-14 | Adding a value to a closed enum is BREAKING for internal events. | Committed events must stay valid under their version (CPT-02), and consumers switch on closed values. | Deliberately stricter than 6A §31.1 for the public API (CNF-7C-01). OPEN codes are used where the vocabulary is not closed. | MX-08, REG-09 |
| ADR-7C-15 | A changed fact is a new `event_type` created by a governed 7B change. A type never carries a version suffix. | 7A VER-04: no silent repurposing. | The version names the shape; the type names the fact. | §30 |
| ADR-7C-16 | An unknown or retired version is never guessed at. It is held or routed per 7G with no side effect. | Mixed-version deployments and replay. | No nearest-version fallback, no partial apply and no downcast. | §33 |
| ADR-7C-17 | EV-100 carries standalone-attributable LLM tokens only. DEP-6K-05 stays OPEN. | In-turn usage belongs to EV-079. | No double counting and no discriminator in V1. | §43, DET-17 |
| ADR-7C-18 | 7C defines no second version of any event. | 7A VER-07. Every type is at 1. | Every successor shape in this document is HYPOTHETICAL. | VRS-07, BRK-07 |
| ADR-7C-19 | Correlation root precedence: (1) an existing trusted root propagates unchanged; (2) otherwise a Voice call that is itself the root establishes it once; (3) otherwise a background root mints one UUIDv7 once. The root never changes within a flow, and `call_id` never overwrites an established root. | P1-7C-01: the checkpoint precedence let a Voice hop replace an API or campaign root. 6A L675 keeps the request ID for an API-initiated call. | One correlation value per causal flow. It is persisted with the call session or root work item, and no hop re-derives it (IO-7C-01). | §16.1, COR-01 … COR-08 |
| ADR-7C-20 | `event_version` versions the complete compatibility-relevant contract: the payload schema plus the meaning of every interpretation-relevant envelope field. It excludes relay bookkeeping, Redis IDs, retry counters, claim metadata, delivery timestamps and transport state. A new optional envelope key that meets the four KEY-07 conditions keeps every version. | P1-7C-02: "payload schemas; not the envelope" contradicted the treatment of envelope semantics. OD-7C-01 = A is unchanged. | The OD-7C-04 `correlation_id` / `causation_id` addition is COMPATIBLE and needs no V2. A changed business fact is a new event type, never N + 1 (NEV-08). | KEY-06, KEY-07, VRS-08, CMP-06, NEV-08 |
| ADR-7C-21 | All 21 required change categories are classified, each with an exact condition. FIELD split and merge are distinct from EVENT split and merge. | P1-7C-03: the checkpoint matrix lacked several categories and substituted an event split for a field split. | Every proposed change is matched against the CAT and MX rows and takes the most restrictive class (CMP-03). | §27.4, CAT-R01 … CAT-R03 |

---

## 46. Owner Decision Register

OD-7C-01 … OD-7C-06 were taken by the owner before this document was completed. Each is **DECIDED**, **RESOLVED** and owner-approved, and none is reopened by the remediation. OD-7C-07 (§46.8) was raised by the remediation of P1-7C-04. It is **OWNER DECISION REQUIRED** and no option is selected.

### 46.1 OD-7C-01 — What bumps `event_version`

| Item | Record |
|---|---|
| Question | Which schema changes require a new `event_version`? |
| Source gap | 7A VER-03 and DD-22 require a compatibility policy but define none. The outbox carries only an integer defaulting to 1. |
| Alternatives | **A** — only BREAKING changes bump the version. **B** — every schema change bumps it. **C** — every change is a new event type (rejected). |
| Selected | **A** |
| Status | DECIDED · RESOLVED · owner-approved |
| Rationale | Compatible optional additions are safe for tolerant consumers. Bumping on every change would force needless consumer releases and coexistence windows. Alternative C would break continuity of the fact and multiply 7B entries. |
| Scope | Internal DURABLE and SIGNAL event contracts: the payload schema plus the meaning of every interpretation-relevant envelope field (KEY-06, VRS-08). Not relay bookkeeping or transport-only state, not AX-A … AX-L. Remediation clarification (P1-7C-02): the checkpoint scope read "payload schemas; not the envelope". The selected option A is unchanged; only the extent of the contract it versions was made explicit. |
| Consequences | COMPATIBLE changes keep N (§28). BREAKING changes create N + 1 (§29). Consumers ignore unknown COMPATIBLE OPTIONAL fields. A new sensitive or PII field is never COMPATIBLE on the grounds that it is optional; it needs 7I (MX-16). |
| Implementation obligations | IO-7C-02 (classification recorded with every manifest change), IO-7C-03, IO-7C-05. |
| Downstream owner | Every producing domain owner; Platform event infrastructure. |

### 46.2 OD-7C-02 — How consumers handle older versions

| Item | Record |
|---|---|
| Question | How does a consumer process events of a version other than the one it handles natively? |
| Source gap | 7A DPL-02 … DPL-04 require tolerance and a processable backlog, but define no mechanism. |
| Alternatives | **A** — native handlers only. **B** — constrained consumer-side upcasting. **C** — mandatory upcasting for every version. |
| Selected | **B** |
| Status | DECIDED · RESOLVED · owner-approved |
| Rationale | Optional upcasting lets consumers keep one handler without rewriting history. Constraints keep it safe. Mandatory upcasting would force lossy conversions where information is missing. |
| Scope | Consumers of internal events. Producers and the relay never upcast. |
| Consequences | An upcast runs only after validation against the original version. It is pure, deterministic, information-preserving and has no side effects. Events are never rewritten. Producers never dual-publish. |
| Implementation obligations | IO-7C-05. |
| Downstream owner | Each consuming domain owner; Platform event infrastructure (shared library). |

### 46.3 OD-7C-03 — Where schemas live

| Item | Record |
|---|---|
| Question | What is the canonical source of internal event schemas? |
| Source gap | 7A DD-03 asks whether a registry exists. `analytics.event_schema_versions` exists but serves Analytics only. |
| Alternatives | **A** — code-owned, version-controlled schemas. **B** — a database registry. **C** — documentation only. |
| Selected | **A** |
| Status | DECIDED · RESOLVED · owner-approved |
| Rationale | Schemas change with the code that emits them and are reviewed with it. A database registry would add a runtime dependency and a second source of truth. Documentation alone cannot be enforced in CI. |
| Scope | All internal DURABLE and SIGNAL schemas. |
| Consequences | 7C is the normative V1 source until the manifest exists; the manifest then reproduces it exactly. There is no global database registry. `analytics.event_schema_versions` stays Analytics-only. |
| Implementation obligations | IO-7C-02, IO-7C-03, IO-7C-11. |
| Downstream owner | Platform event infrastructure; Analytics for its own registry. |

### 46.4 OD-7C-04 — Correlation and causation persistence

| Item | Record |
|---|---|
| Question | Where are `correlation_id` and `causation_id` carried for durable events? |
| Source gap | 7A OBS-02 requires both. The executed outbox (077) has neither column. |
| Alternatives | **A** — a payload `_meta` object. **B** — outbox columns. **C** — A first, then B. **D** — logs only (rejected). |
| Selected | **B** |
| Status | DECIDED · RESOLVED · owner-approved |
| Rationale | Metadata belongs on the envelope, not in the business payload (PAY-04). Columns are queryable and stay out of payload schemas. A then B would create a migration of meaning. Logs cannot be joined to replayed events. |
| Scope | The DURABLE envelope. The SIGNAL envelope carries both keys directly (§11). |
| Consequences | Future `correlation_id UUID` and `causation_id UUID` columns. 7C creates no migration. Values never go in the payload and are never fabricated. `correlation_id` is the root and propagates unchanged; it is required after activation. `causation_id` is the immediate cause (an `event_id` or a stable work-item ID) and is null only for a genuine root. There is no `command_id`. |
| Implementation obligations | IO-7C-01. |
| Downstream owner | Phase-5 database owner (migration); every producing domain (propagation). |

### 46.5 OD-7C-05 — EV-079 usage representation

| Item | Record |
|---|---|
| Question | How does EV-079 carry conversation usage? |
| Source gap | 7B IO-7B-04 requires the EV-079 fields. 6K FB-6K-06 shows the defect of pre-rounded minutes. |
| Alternatives | **A** — inline usage in the payload. **B** — a reference to usage held elsewhere. **C** — both. |
| Selected | **A** |
| Status | DECIDED · RESOLVED · owner-approved |
| Rationale | One self-contained fact is replayable and needs no second read at Billing time. A reference would couple Billing to a mutable store. Both would create two sources. |
| Scope | EV-079 `conversation.completed` only. |
| Consequences | AI duration is decimal-string seconds, never pre-rounded minutes. STT audio duration is decimal seconds. TTS characters and tokens are non-negative integers. Provider and model attribution is reference-only and supports several providers or models. No pricing, cost, rate, margin, transcript, raw response, credential or signed URL. |
| Implementation obligations | IO-7C-07, IO-7C-10. |
| Downstream owner | Voice (producer); Billing (consumer). |

### 46.6 OD-7C-06 — Class-D signal envelope

| Item | Record |
|---|---|
| Question | Which envelope do consumed Class-D signals use? |
| Source gap | 7B catalogues PAY-D-01 and PAY-D-02 as consumed Class-D signals without an envelope. |
| Alternatives | **A** — the same core metadata plus a marker. **B** — a separate envelope. **C** — payload only, with no envelope. |
| Selected | **A** |
| Status | DECIDED · RESOLVED · owner-approved |
| Rationale | One set of metadata names for all consumers. A separate envelope would split tooling. A bare payload loses identity, tenant scope and correlation. |
| Scope | SIGNAL profile (PAY-D-01, PAY-D-02 and any Class-D signal that later gains a catalogued consumer). |
| Consequences | `durability = "SIGNAL"`; no database column; `durability` never reclassifies. The `event_id` is a producer UUIDv7 generated once per signal. It is not an outbox ID, a Redis entry ID or a delivery ID. |
| Implementation obligations | IO-7C-04, IO-7C-08. |
| Downstream owner | Voice and Tools (producers); Analytics (consumer). |

### 46.7 Summary

| OD | Selected | Status |
|---|---|---|
| OD-7C-01 | A — breaking-only bump | DECIDED · RESOLVED |
| OD-7C-02 | B — constrained consumer-side upcasting | DECIDED · RESOLVED |
| OD-7C-03 | A — code-owned schemas | DECIDED · RESOLVED |
| OD-7C-04 | B — future outbox columns | DECIDED · RESOLVED |
| OD-7C-05 | A — inline EV-079 usage | DECIDED · RESOLVED |
| OD-7C-06 | A — same core metadata plus `durability` | DECIDED · RESOLVED |
| OD-7C-07 | None — OWNER DECISION REQUIRED (§46.8) | OPEN |

Current open owner decisions: **1** (OD-7C-07).

### 46.8 OD-7C-07 — EV-014 manifest representation

**OD-7C-07 — OWNER DECISION REQUIRED.** No option is selected. 7C does not select one, and the document does not proceed to independent review until the owner answers.

| Item | Record |
|---|---|
| Question | How should the code-owned schema manifest represent the already-frozen EV-014 `tool_definition.*` family when exact member event names are not frozen? |
| Exact conflict | 7B freezes EV-014 as the family `tool_definition.*` (FAM-01) and names no member `event_type`. OD-7C-03 and CSR-02 key every manifest entry by an exact (`event_type`, integer `event_version`) pair. Producer validation (PV), consumer declaration and dispatch (CV) and CI conformance (IO-7C-03) are keyed the same way. A wildcard is not an emitted `event_type`, and 7B ADR-7B-05 rejects cataloguing `*` as one event. The EV-014 payload is bound (§20), but the `event_type` under which it is emitted is not determined. EV-014 therefore cannot be entered in the manifest. |
| Source evidence | 7B L227 (§8.1 FAMILY: members are listed "only where a frozen source names them"). 7B L286 NAM-06 ("7B fabricates no members"). 7B L287 NAM-07 (a new event name requires a governed amendment to the owning source). 7B L333 (EV-014 `tool_definition.*`, CUR +N, FAM). 7B L476 (§12.3: 6E-011 / 6E-013 / 6E-014; "Created / updated / deactivated"). 7B L1083 (lineage: tool_id, change kind). 7B L1318 FAM-01 ("No member name is catalogued in 6E"). 7B L1621 ADR-7B-05 (a family is a grouping, not an event). 6E L914 and 6D L1232 (`tool_definition.*` "(created/updated/deactivated)": the three kinds in words, in family form). AIR L1315 – L1317 (AMI-6E-011 / 013 / 014, OUTBOX_REQUIRED, "6E L914 family form"). Phase 4 names no tool-definition event. 077 L50, L72 (`event_type TEXT NOT NULL`, length 1 – 200, no pattern CHECK). 7C: EV-014 binding (§20), CSR-02, §46.3, IO-7C-17. |
| Why 7C cannot decide | A member name needs a governed amendment to the owning source (7B NAM-06, NAM-07, AUTH-7B-02), and 7C may not change 7B or 6E. The alternative is a manifest that matches patterns, which changes the exact-pair keying that OD-7C-03 was approved with (CSR-02, PV, CV, IO-7C-03). That is a material change beyond the approved scope of OD-7C-03. A family entry can reject arbitrary members only with a closed member list, and a closed member list is the information that is missing. |
| Status | **OWNER DECISION REQUIRED** · OPEN · no option selected |

**Options**

| Option | Description | Pros | Cons |
|---|---|---|---|
| **A** — controlled 7B amendment that names the members | The owner names the exact member `event_type` values in a governed amendment to 7B FAM-01 and the EV-014 catalogue row. Per NAM-07 and AUTH-7B-02, the owning 6E source (6E L914) is amended with them. 7C then enters one exact pair per member at version 1. Each pair uses the §20 EV-014 payload, and producer validation requires `change_kind` to match the member. | Keeps OD-7C-03 and CSR-02 exactly as approved. PV, CV, CI and Analytics (ADP) all keep exact pairs. The names come from the owner, not from 7C. No pattern matching enters the manifest. | Needs a change to frozen 7B, and to 6E, outside 7C. EV-014 cannot be emitted under this contract until the amendment lands. |
| **B** — governed family entry in the manifest | The manifest gains a family-entry kind with: the canonical identifier `tool_definition.*`; version 1; one shared payload (the §20 EV-014 binding); a member matching rule; producer conformance; CI validation; and on each event the concrete member as the runtime `event_type`. | Needs no 7B change for the manifest mechanism. | Changes OD-7C-03 beyond its approved scope: CSR-02 keying, PV / CV dispatch and IO-7C-03 CI all become pattern-aware. Rejecting arbitrary `tool_definition.<x>` members requires a closed member list, so B still needs A's names. Without that list, B accepts any member (§50.2, mutation 99). Analytics still registers exact pairs only (ADP, IO-7C-11). One shared version means that a BREAKING change to the payload versions every member together. |
| **C** — hold EV-014 emission until members are named | No manifest entry and no EV-014 outbox row until names exist; the §20 payload binding stays. The source basis is that EV-014 has no current consumer (6E L914, 6D L1232, 7B L476). | Invents no name, changes nothing in the manifest, and loses nothing that is consumed today. | Departs from AIR OUTBOX_REQUIRED for AMI-6E-011 / 013 / 014 and from the 7B CUR status of EV-014 (7B L333), so C is itself an owner-level deviation. Tool-definition changes made before the names land are never emitted, and there is no backfill. It still ends in A. |

**Impacts**

| Impact | Record |
|---|---|
| Migration | None for any option. `event_type` is free `TEXT` with no pattern CHECK (077 L50, L72). No migration 113, and no registry table. |
| Runtime | **A:** the producers of 6E-011 / 6E-013 / 6E-014 emit the named member with the EV-014 payload, and consumers dispatch on the exact pair. **B:** producers emit a concrete member, and the producer validator and consumer dispatcher need family matching. **C:** the three routes write no EV-014 row until names exist. In every option, an emitted event carries a concrete member as its `event_type` and never the literal `tool_definition.*`. |
| Registry | For the code-owned manifest (IO-7C-02): **A** gives the 104 exact pairs plus one exact pair per named member. **B** gives the 104 exact pairs plus one family entry of a new entry kind. **C** gives the 104 exact pairs and no EV-014 entry. `analytics.event_schema_versions` stays Analytics-only (DET-15, ARR-01) in every option, and it registers an exact pair only when Analytics consumes it (IO-7C-11). |
| Compatibility | No EV-014 event has been emitted under this contract, so no option changes an emitted contract. Under A or B every member starts at `event_version` = 1 with the §20 payload and no V2. Any later change is classified by §27.4. A new business fact is a new `event_type` through a governed 7B change, never an N + 1 (NEV-03, NEV-08). |

| Item | Record |
|---|---|
| Recommendation | **A.** It is the only option that keeps OD-7C-03 and CSR-02 exactly as approved and gives every EV-014 event an exact pair. 6E L914 already describes the three kinds in words (created / updated / deactivated). Whether those become the member names is the owner's decision; 7C does not choose them. |
| Consequence for this document | Until the owner answers: EV-014 has no manifest entry; IO-7C-17 is blocked; P1-7C-04 stays OPEN (§51.1); and this document is **NOT READY FOR INDEPENDENT REVIEW** (§52). |
| Downstream owner | The owner (decision). AI Agent (6E), which owns the names. Platform event infrastructure (manifest). |

---

## 47. Implementation Obligations

These obligations are placed on later phases and owners. 7C does not deliver any of them.

| IO | Obligation | Owner | Must be complete before |
|---|---|---|---|
| IO-7C-01 | Add `correlation_id UUID` and `causation_id UUID` to `audit.domain_event_outbox` by a new migration, and propagate both per §16 / §17. Persist the established root with each call session (COR-C, COR-V) and with each root work item (COR-T, COR-B), and carry it on tasks, so that no hop re-derives or replaces it (COR-01, COR-04) | Phase-5 database owner; every producing domain | Any consumer relies on either key for durable events |
| IO-7C-02 | Materialize the code-owned manifest keyed by (`event_type`, integer version), reproducing §20 – §22 exactly (CSR-02, CSR-08) | Platform event infrastructure | Producer validation (IO-7C-04) is enabled |
| IO-7C-03 | CI conformance: producers emit and consumers declare only manifest pairs; manifest equals the V1 baseline (CSR-03, COX-06) | Platform event infrastructure | The first BREAKING change |
| IO-7C-04 | Producer validation PV-C01 … PV-C13 | Each producing domain (shared library) | Production emission under this contract |
| IO-7C-05 | Consumer dispatcher CV-01 … CV-07, unknown-version handling (§33) and optional upcasting (§37) | Platform event infrastructure; each consumer | The first BREAKING change |
| IO-7C-06 | Analytics TEXT-version adapter (§24) | Analytics | Analytics ingests internal events |
| IO-7C-07 | EV-079 usage accumulator, independent of SIGNAL delivery (USG-08, PD1-02) | Voice | EV-079 is emitted with usage |
| IO-7C-08 | PAY-D-01 / PAY-D-02 producers and per-turn counters | Voice; Tools | Analytics consumes the signals |
| IO-7C-09 | DEP-6K-05: whether the workflow runtime can tell in-turn from standalone execution (§43) | Workflow; Billing | Any EV-100 discriminator is proposed |
| IO-7C-10 | Persist the service-end time on the recovery path so that EV-079 can be emitted (OCC-C13) | Voice | Recovered conversations are billed |
| IO-7C-11 | Register every (`event_type`, version) that Analytics consumes, including `tool_execution.started`, and mirror lifecycle states (ADP-07, ADP-11, ARR-03) | Analytics | Analytics projection of that pair is enabled |
| IO-7C-12 | Shared six-digit UTC timestamp formatter (§15.1, §18) | Platform event infrastructure | Production emission under this contract |
| IO-7C-13 | EV-002 `organization.created` `plan_tier`: the source of a non-null value. V1 is deterministic without it: every V1 producer writes `null` (§20, EV-002) | Organization; Billing | EV-002 is emitted with a non-null value (not required for V1 emission) |
| IO-7C-14 | EV-062 `workflow.draft_updated` draft-revision source. **CLOSED by the 7C remediation**: bound as `draft_revision` in §20 (EV-062 binding; P1-7C-05) | Workflow | — |
| IO-7C-15 | EV-105 `usage.threshold_reached` `metric` vocabulary, which limit `threshold` is, `occurred_at` source and usage period. **CLOSED by the 7C remediation**: bound in §20 (EV-105 binding; P1-7C-06) | Billing | — |
| IO-7C-16 | Known-value lists for OPEN codes (`reason_code`, `failure_reason`, `error_code`, `failure_code`, `rule_code`, `metric`). For `metric`, the V1 value set is already fixed by `billing.fn_is_canonical_usage_metric` (§20, EV-105) | Each owning domain | Optional; publication is not a schema change (CMP-07) |
| IO-7C-17 | Enter EV-014 `tool_definition.*` (7B FAM-01) in the code-owned manifest as OD-7C-07 decides. **Blocked on OD-7C-07 (§46.8)**, which is OWNER DECISION REQUIRED | Owner; AI Agent (6E); platform event infrastructure | EV-014 is emitted under this contract |
| IO-7C-18 | EV-055 `campaign.scheduled` schedule-window source keys in `scheduling_policy`. **CLOSED by the 7C remediation**: bound as `start_at` / `end_at` in §20 (EV-055 binding) | Campaign | — |
| IO-7C-19 | Source key of `session_id` in `voice.call_sessions.sessions` (EV-007, EV-008). **CLOSED by the 7C remediation**: bound in §20 (EV-007 and EV-008 bindings) | Voice | — |
| IO-7C-20 | EV-028 `contact.merged` `field_merge_map` key set and value vocabulary. **CLOSED by the 7C remediation**: bound in §20 (EV-028 binding; E-MERGE-SOURCE) | CRM | — |
| IO-7C-21 | Identity producers (`fn_platform_revoke_all_sessions`, 109_5B7, and the password-reset confirm path) emit the EV-001 V1 binding: `user_id`, `reason_code`, the revoked session IDs and their access-token JTIs (§20, EV-001; CNF-7C-11) | Identity | EV-001 is emitted under this contract |

---

## 48. Deferred Items

| ID | Item | Deferred to | Reason |
|---|---|---|---|
| DEF-7C-01 | `agent_id` on PAY-D-02 (PD2-02) | A later COMPATIBLE change (§28) | The Analytics grain does not require it; its column is NULL-able (071). |
| DEF-7C-02 | SIGNAL bindings for DS-01 … DS-16 and DS-18 | A governed 7B + 7C change when a consumer is catalogued | No consumer is catalogued (§9). |
| DEF-7C-03 | Relay batching, stream names, retries and consumer-group rules | 7D, 7E | Outside 7C scope. |
| DEF-7C-04 | Idempotency guard and dedup ledgers | 7F | Referenced by CV-06 only. |
| DEF-7C-05 | DLQ, parking and replay windows, and disposition of unknown or retired versions | 7G, 7K | Referenced by §33, §36 and RET-03. |
| DEF-7C-06 | Projection of internal events to WebSocket and webhook messages | 7H | §39, §40. |
| DEF-7C-07 | Sensitivity classification of the 29 [7I] fields, and review of any MX-16 change | 7I | SP-05. |
| DEF-7C-08 | Events for platform and regulatory suppressions (TEN-C06) | A governed 7B change | Only EV-001 may be platform-scoped. |
| DEF-7C-09 | Events for built-in tool definitions (EV-014) | A governed 7B change | Built-in rows have no organization. |
| DEF-7C-10 | An EV-100 discriminator | DEP-6K-05 (IO-7C-09) | E100-04. |
| DEF-7C-11 | Opaque non-secret references in payloads | A frozen contract that permits them, plus 7I | No V1 binding carries one (SP-03). |
| DEF-7C-12 | `retired_at` in `analytics.event_schema_versions` | Analytics, if needed | ARR-04. |

---

## 49. Conflict Register

Conflicts are resolved by concern ownership (§5). 7C edits no upstream document.

| ID | Sources | Conflict | Resolution in 7C | Severity |
|---|---|---|---|---|
| CNF-7C-01 | 6A §31.1; 7C MX-08 | 6A treats enum additions on the public API as additive. 7C treats a closed-enum addition to an internal event as BREAKING. | Different concerns: 6A governs the public API; 7C governs internal events. CPT-02 requires the stricter rule. OPEN codes cover vocabularies that grow. | Minor |
| CNF-7C-02 | 6A L656 / L675; 3A §12.4; 7C §16 | 6A describes the request ID as reused as the voice call/session correlation ID. 3A sets "call/session ID for voice". Taken alone, the latter could be read as replacing an API request's root with `call_id`. | Resolved by §16.1 precedence (P1-7C-01). An API-initiated call keeps the request ID as its root, which is what 6A L675 states; the call/session ID is the root only when the call itself is the root (inbound, COR-V). No hop replaces an established root. | Minor (aligned) |
| CNF-7C-03 | 6L L124, 6L L823 (row 13); 073 | 6L says `analytics.event_schema_versions` was not found in migrations 067–104. `073` creates it. | 6L is stale on this point. 6L is not edited. No API effect (ARR-06). | Minor |
| CNF-7C-04 | 070 L18 `analytics.conversation_turn_stats_daily.stt_audio_seconds NUMERIC(12,2)`; 7C PD1-01 scale 4 | The signal carries scale 4; the Analytics column holds scale 2. | The producer emits the usage scale. Reducing scale is the Analytics projection's job. | Minor |
| CNF-7C-05 | 011 L44–L45, 020 L54 (`{6,14}` digits); 7C §18 phone (`{1,14}`) | The column CHECKs are stricter than the §18 E.164 pattern. | Where a phone value is read from a column with a CHECK, the column governs the value. §18 never widens what a column accepts. | Minor |
| CNF-7C-06 | 7B EV-014 family; `tools.tool_definitions` built-in rows with `organization_id IS NULL` | 7B catalogues the family without distinguishing built-in rows. Only EV-001 may be platform-scoped. | V1 emits EV-014 only for organization-owned definitions. Built-in rows produce no V1 event (DEF-7C-09). | Minor |
| CNF-7C-07 | 7B EV-030 / EV-031; 024 `chk_sup_scope_org_id` | Suppressions include `PLATFORM` and `REGULATORY` rows with no organization. | V1 emits only for `scope = 'ORG'` rows (TEN-C06; DEF-7C-08). | Minor |
| CNF-7C-08 | 6K L2816 – L2827 (via 7B NAM-F-06) | `invoice.created` versus `invoice.generated`. | Inherited, already recorded by 7B (NAM-F-06). 7C binds EV-102 `invoice.generated`. No new action. | Minor (inherited) |
| CNF-7C-09 | 6K L2511; 6D L1216, L1234 (via 7B CNF-16) | DS-17 attribution and Billing use. | Inherited, resolved by 7B CNF-16 and OD-7B-01 / OD-7B-02. 7C binds DS-17 as SIGNAL, Analytics-only. No new action. | Minor (inherited) |
| CNF-7C-10 | 6K `AI_MINUTES` source (`conversation.turn_completed`) | The 6K source of `AI_MINUTES` is superseded by OD-7B-01. | Inherited. 7C binds the AI duration on EV-079 as decimal seconds (DET-12); Billing converts to `AI_MINUTES`. No new action. | Minor (inherited) |
| CNF-7C-11 | 7B L1070 (EV-001 indicative fields); 5B L2877 – L2884; 109_5B7 L1140 – L1150 | 7B indicates `user_id` and `reason_code` for EV-001. The frozen revocation contract also carries the revoked session IDs and their access-token JTIs, which EV-001 exists to propagate to the JTI denylist. | 7B's list is indicative, not exhaustive. V1 binds all four fields (§20, EV-001), and the admin free-text `reason` is never carried. The producers are aligned by IO-7C-21. 7B is not edited. | Minor |

**Not a conflict.** The 25 names seeded by `075` are already reconciled by 7B §25.1: 12 durable events and 13 names that are not durable events (4 Class-D signal names, 2 CCPU, 7 FUT). 7C adds nothing to that reconciliation (ARR-05).

---

## 50. Validation Results

Validation ran outside the repository, in a scratch directory. No validator, harness or script was added to the project.

### 50.1 Validator status

**NOT YET RERUN against this remediated checkpoint.**

The earlier validator run (80 mutations, 80 / 80 detected, clean run PASS) was made against the **pre-remediation** document (SHA-256 `a583365003581bf6732e18dba91e54d8ec891b89993f61b97cb24b7ce31ff16e`, 2963 lines). That result is **PRE-REMEDIATION / SUPERSEDED**. It does not validate the current text and is not evidence for any gate below.

Still outstanding (§53):

- rebuild the external validator for the remediated content;
- run mutations 1 – 114 (the 80 earlier mutations plus 81 – 114 for P1-7C-01 … P1-7C-06);
- rerun gates 1 – 47.

### 50.2 Baseline checks made during remediation

These were checked by direct inspection during the remediation, not by the validator:

| Check | Result |
|---|---|
| Frozen 7A SHA-256 `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` | Unchanged |
| Frozen 7B SHA-256 `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` | Unchanged |
| Migrations | 112 SQL / 112 Alembic; root `001_5B`; sole head `112_5H5`; no migration 113 |
| Phase 7D | Absent |
| Files changed | This document only |

---

## 51. Findings

| Severity | Count |
|---|---|
| P0 | **0** |
| P1 | **1** (P1-7C-04, OPEN) |
| Minor | **11** |

### 51.1 Freeze-gate P1 findings

These findings were raised against the pre-remediation document (SHA-256 `a583365…`, 2963 lines). The document was remediated in place. The old wording is quoted as evidence.

| ID | Finding | Status | Remediation | Evidence |
|---|---|---|---|---|
| P1-7C-01 | Correlation root precedence changes correlation mid-flow. | **RESOLVED** | §16.1 precedence: an existing trusted root is propagated unchanged (COR-P, COR-T, COR-C, COR-Q). `call_id` becomes the root only for a genuinely Voice-rooted call (COR-V). A new root is minted once only when none exists (COR-B). No hop regenerates or replaces a root (COR-01, COR-02, COR-08). §16.3 shows an API-rooted Voice flow carrying `A` on every hop | Old SIG-08: "The call session's `call_id` (§16, rule COR-V)". Old PAY-D envelopes: "`correlation_id` = `call_id` (COR-V)". Now: §16.1 – §16.3, SIG-08, §21; CNF-7C-02; ADR-7C-19 |
| P1-7C-02 | `event_version` scope contradicts compatibility treatment of envelope semantics. | **RESOLVED** | `event_version` versions the complete compatibility-relevant contract of one `event_type`: payload, envelope semantics, occurrence time, aggregate, organization scope and identity (KEY-06, VRS-08). The optional OD-7C-04 envelope addition is COMPATIBLE and needs no N + 1 (KEY-07, CPT-09, BRK-06). BREAKING envelope changes get N + 1 (BRK-06); business-fact changes get a new type (NEV-08) | Old KEY-06: "versions the **payload schema** of one `event_type`". Old VRS-08: "describes the payload schema only". Now: §23, CMP-06, CPT-09, BRK-06, BRK-09, NEV-08; ADR-7C-20 |
| P1-7C-03 | Required compatibility-change categories missing. | **RESOLVED** | §27.4 classifies all 21 categories (CAT-01 … CAT-21), including nesting move, identity, money, scalar → object / array, field split, field merge and default behaviour. FIELD split and merge (CAT-18, CAT-19) are separate from EVENT split and merge (MX-18) (CAT-R02) | Old MX-18: "Split one event into several, or merge several into one \| SEMANTIC_NEW_EVENT", with no field-level categories. Now: §27.4, CAT-R01 … CAT-R03; ADR-7C-21 |
| P1-7C-04 | EV-014 wildcard family incompatible with exact manifest claim. | **OPEN** | Frozen sources do not determine how EV-014 is represented in the exact manifest. 7B freezes EV-014 only as `tool_definition.*`. 6D, 6E and AIR use the same family form. No frozen source names a member `event_type`; 7B FAM-01 says no member name is catalogued, and 7B NAM-06 forbids fabricated members. No member name is invented here. Owner decision OD-7C-07 is required (§46.8) | Old EV-014 note: "The concrete member `event_type` names of the `tool_definition.*` family are not catalogued in 7B (FAM-01); they are IO-7C-17. Every member uses this one binding." Now: CSR-02; EV-014 binding note; §46.8; IO-7C-17 |
| P1-7C-05 | EV-062 draft_revision silently omitted from frozen semantic payload. | **RESOLVED** | EV-062 `workflow.draft_updated` binds `draft_revision` as a timestamp sourced from `workflow.workflow_definitions.updated_at`, the frozen draft-state token | Old EV-062 note: "V1 binds `workflow_id` only (IO-7C-14)". Now: §20 EV-062 binding; IO-7C-14 closed |
| P1-7C-06 | EV-105 current schema not implementation-deterministic. | **RESOLVED** | EV-105 `usage.threshold_reached`: `metric` is bound to the 15 canonical usage metrics (`billing.fn_is_canonical_usage_metric`); `threshold` is the effective `soft_limit` (`billing.fn_resolve_effective_quota`), and `hard_limit` is never the threshold; `period_start` / `period_end` come from `billing.billing_periods`; `occurred_at` is the authoritative crossing write, `billing.usage_records.updated_at` | Old EV-105 wording: `occurred_at` "source is IO-7C-15"; metric "vocabulary is IO-7C-15"; threshold "which limit is IO-7C-15"; period "(non-physical) … (IO-7C-15)". Now: §20 EV-105 binding; IO-7C-15 closed |

The EV-001 … EV-105 bindings were also scanned for unresolved mandatory bindings (TBD, unresolved, unknown, deferred, unbound type, occurrence source or enum vocabulary). The deterministic-source fixes made during the remediation are in §20. One remaining hit is intentional: EV-002 `plan_tier` is "deferred" to IO-7C-13, and V1 writes a deterministic `null`.

### 51.2 Minor findings

| ID | Finding | Handling |
|---|---|---|
| MIN-7C-01 | 6L L124 and L823 (row 13) say `analytics.event_schema_versions` is not found; `073` creates it | CNF-7C-03; 6L is not edited |
| MIN-7C-02 | EV-014 built-in tool definitions (`organization_id IS NULL`) produce no V1 event | CNF-7C-06; DEF-7C-09 |
| MIN-7C-03 | Platform and regulatory suppressions produce no V1 event (TEN-C06) | CNF-7C-07; DEF-7C-08 |
| MIN-7C-04 | Closed-enum additions are stricter for internal events than 6A §31.1 is for the public API | CNF-7C-01 |
| MIN-7C-05 | The 3A / 6A correlation wording is reconciled by the §16.1 precedence: the call/session is the Voice root only when the call itself is the root | CNF-7C-02 |
| MIN-7C-06 | `stt_audio_seconds` scale 4 on the signal versus `NUMERIC(12,2)` in Analytics | CNF-7C-04 |
| MIN-7C-07 | Phone column CHECKs `{6,14}` are stricter than the §18 pattern `{1,14}` | CNF-7C-05 |
| MIN-7C-08 | `fn_ingest_analytics_event` performs no version validation | DET-16; ADP-04; IO-7C-06 |
| MIN-7C-09 | `tool_execution.started` is not seeded in `analytics.event_schema_versions` | PD2-03; ADP-07; IO-7C-11 |
| MIN-7C-10 | The recovery path has no persisted service-end time, so EV-079 cannot be emitted for it | OCC-C13; IO-7C-10 |
| MIN-7C-11 | 59 V1 fields have no physical column and are held by the producer in the producing transaction. Each has a deterministic source (REG-04, REG-10) | REG-04; remaining obligations IO-7C-13, IO-7C-16, IO-7C-21 |

P1-7C-04 blocks independent review until OD-7C-07 is decided (§46.8).

---

## 52. Freeze-Gate Status

**NOT READY FOR INDEPENDENT REVIEW — BLOCKED ON OD-7C-07.**

| Item | Current value |
|---|---|
| P0 | 0 |
| P1 | 1 (P1-7C-04 OPEN) |
| Resolved remediation P1s | P1-7C-01, P1-7C-02, P1-7C-03, P1-7C-05, P1-7C-06 |
| Current open owner decisions | 1 (OD-7C-07, EV-014 manifest representation) |
| Validator | NOT YET RERUN against this checkpoint (§50.1) |
| Gates 1 – 47 | NOT YET RERUN. The earlier "all 42 gates pass" result is PRE-REMEDIATION / SUPERSEDED |

Gate 39 (P1 = 0) and gate 40 (current owner decisions = 0) cannot pass until OD-7C-07 is decided and P1-7C-04 is resolved.

**7C EVENT ENVELOPE & SCHEMA VERSIONING = NOT READY FOR INDEPENDENT REVIEW — blocked on OD-7C-07 (§46.8).**

---

## 53. TEMPORARY — Current Checkpoint (remove before READY)

> **TEMPORARY CONTINUATION NOTE.** This section records a work checkpoint. It MUST be removed before this document is marked READY.

**Completed**

- Baseline verification (§50.2)
- Targeted frozen-source searches
- P1-7C-01 RESOLVED
- P1-7C-02 RESOLVED
- P1-7C-03 RESOLVED
- P1-7C-05 RESOLVED
- P1-7C-06 RESOLVED
- Current-event determinism scan and fixes (§20; §51.1)
- OD-7C-07 decision packet written (§46.8)

**Blocked**

- P1-7C-04 / OD-7C-07

**Not yet completed**

- Owner answer for OD-7C-07
- Final EV-014 manifest representation
- Validator rebuild and rerun
- Mutations 1 – 114, including 81 – 114
- Final rerun of gates 1 – 47
- Final SHA-256 and line count
- Final 83-item report
- Removal of this temporary note
- READY status

**Next actions, in order**

1. Receive the owner decision for OD-7C-07.
2. Implement that decision only.
3. Resolve P1-7C-04.
4. Rebuild and rerun the external validator.
5. Run mutations 1 – 114 at least.
6. Run all final gates.
7. Remove this temporary checkpoint note.
8. Mark READY only if P0 = 0, P1 = 0 and open owner decisions = 0.
