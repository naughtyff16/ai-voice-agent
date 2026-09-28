# Phase 7B — Event Taxonomy & Ownership

## 1. Document Control

| Field | Value |
|---|---|
| Document | `docs/phase-07-event-architecture/7B-Event-Taxonomy-and-Ownership.md` |
| Phase | Phase 7 — Event Architecture |
| Sub-phase | 7B — Event Taxonomy & Ownership |
| Status | Draft for independent review. This document does not declare itself frozen. A separate independent review decides the freeze. |
| Date | 2026-09-27 (freeze-gate remediation applied 2026-09-28: P1-7B-05R, P1-7B-08, P1-7B-09, P1-7B-10, Minor-7B-01, Minor-7B-02; §41) |
| Upstream (frozen, read-only) | 7A Event Architecture & Standards; Phase 6 API design (6A–6M, AIR, AMI, AAM, AEC, AVS, FAR, Phase-6 certificate); Phase 5 database design (migrations 001_5B…112_5H5); Phase 4 domain-driven design (4A–4I) |
| Downstream (not started) | 7C–7L. 7B creates none of them. |
| Owner decisions recorded | OD-7B-01 resolves FOD-7B-01 with Option C (per-conversation durable Billing event). The owner approved it. OD-7B-02 records single-path accounting finalization for EV-079 (§31.5). |
| Architecture | Modular monolith with one PostgreSQL transactional outbox (`audit.domain_event_outbox`) and Redis Streams transport. No microservices. No Kafka. |
| What this document is | The canonical async event catalog, with producer and consumer ownership, per-event payloads (DD-01), the Class-D catalog (DD-15) and the FOD-7B-01 resolution (DD-16). |
| What this document is not | It is not an envelope schema, a JSON schema, a stream topology, a migration, application code or an OpenAPI change. |

### 1.1 Frozen baseline verified by this document

| Artifact | SHA-256 | Lines | Verified |
|---|---|---:|---|
| 7A-Event-Architecture-and-Standards.md | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` | 1086 | Yes (2026-09-27) |
| 6A-API-Architecture-and-Standards.md | `a13e295f8041627751bf0648d4c2b37aa665a096bb79ab758243b1bac69971ab` | 1140 | Yes |
| 6B-Authentication-and-Authorization-API.md | `f8b43a258fee15824fcc6323ac0bcd612ca1cfa4d9278095fc899b776bac6cfe` | 2783 | Yes |
| 6C-Core-Platform-APIs.md | `269b5978a72d5526d2a6ce5a332b6bbf2ba87b6d584a8e8d4b11c1836e26813c` | 1338 | Yes |
| 6D-Voice-Call-Agent-APIs.md | `0971c372de32bd58f01521a3f493b7458b5fd103c9ac28f5a6ff95cd5dfafd42` | 2157 | Yes |
| 6E-AI-Agent-APIs.md | `6c9b500ac2afac65cf8b5c9f237170a72f29d4c468c4991f169c5f52145241bf` | 1785 | Yes |
| 6F-Knowledge-RAG-APIs.md | `8a38ce1f4f3def3b819c0bb3588d66f24d2be2757a5a2f3811a9d3a6a0d7a7f2` | 1457 | Yes |
| 6G-CRM-Leads-APIs.md | `907ca4165290932bc631c0d416bbe3b477a4bad0df8f1c22853ffc5189e56211` | 1386 | Yes |
| 6H-Campaign-APIs.md | `9639498818c48e1a6b9ecbf34312cf94e509929a89fb111f5b4320b695e28c18` | 2832 | Yes |
| 6I-Workflow-APIs.md | `00023a92b86230849fa6ff3ba076350a6e94037feba049ed377603bfdd792dbe` | 1762 | Yes |
| 6J-Integrations-Webhooks-Plugins-APIs.md | `adebb15b6f132816b2adfef5d3b62c93de18f31fbbd5885cafd05fc3640782a9` | 2690 | Yes |
| 6K-Billing-Usage-APIs.md | `db4df2883cdeafb41035176a5c8a5199088044ea00626a52e036fd862fa0d675` | 3936 | Yes |
| 6L-Analytics-Audit-APIs.md | `b268460c4fc954ce2d833415f058201afec7f8c74420d1d9ac7804d6c6ce96e9` | 1388 | Yes |
| 6M-Admin-Platform-APIs.md | `88684f96527fd7ceb14ab88ac5fcc5458d531f993625ddf1b7140ac7ad7dd0f8` | 1136 | Yes |
| API-AUTHORIZATION-MATRIX.md (AAM) | `f61d2d742a3193803c36cf7b9b9f78ce974da35fac94c61ce238b334dfd94843` | 1732 | Yes |
| API-ERROR-CATALOG.md (AEC) | `2505acda65a07d98247bb2cbd5d3e28421bbf6cc75f7cfd0fff1ba07d7f65c7a` | 1404 | Yes |
| API-MASTER-INDEX.md (AMI) | `cb033a2f334aee1563d05e6db535b9d1a17038cf163ff4ea6925313cf9756c38` | 845 | Yes |
| API-VERSIONING-STRATEGY.md (AVS) | `ad3341ce73e5459783e7a00ff8ecb2cf04e1e8a93112ab2565bdbd6813ab222f` | 1741 | Yes |
| FINAL-API-RECONCILIATION.md (FAR) | `5853982e7209d84f097405c6ad149f180013d6351645db3aaa7297553addbc3f` | 2552 | Yes |
| API-IMPLEMENTATION-READINESS.md (AIR) | `81dd63dc3160b1eb642ab524b5159794fdc1f0aec74602987b45eb97097a54e2` | 2484 | Yes |
| PHASE-06-FINAL-VALIDATION-AND-FREEZE.md (certificate) | `574d4c05ec88969c0439359484f62404662d0c58b0c27d85ee2f1aa9fdc37a5a` | 640 | Yes |
| docs/product/PROJECT_ROADMAP.md | `23df5f236b7c9bc3da56c5336b3297471f2a30fe01b8a6e9a748fca54533254e` | 145 | Yes |

Migration baseline: 112 SQL files and 112 Alembic revisions under `docs/phase-05-database-design/5K/migrations/`; root `001_5B`, head `112_5H5`; no migration 113 exists and 7B creates none.

This document does not use Git state as a design or freeze criterion. The baseline is verified by content hash and line count only.

---

## 2. Purpose

7A froze the event architecture: the nine mechanism classes A–I, the single outbox, Redis Streams as transport only, at-least-once delivery with consumer idempotency, and the non-goals. 7A deliberately left four things to 7B:

| 7A deferral | Where 7A defers it | What 7B provides |
|---|---|---|
| DD-01 — per-event payloads | 7A §38 | The per-event payload registry (§24), with source lineage, security marks and 7C binding obligations |
| DD-15 — Class-D consumers and catalog | 7A §38 L948 | The Class-D catalog (§15), with semantic owner, producer and current consumers for every direct stream signal |
| DD-16 — FOD-7B-01 (turn-level Billing usage durability) | 7A §38 L949, §37 L912–L926 | FOD evidence (§29), the owner decision OD-7B-01 (§30) and the resulting contract (§31) |
| Catalog and ownership | 7A §24–§26 OWN rules L581–L585 | The canonical catalog (§11–§19) and the five-owner model (§9, §21–§23) |

7B names what exists, who owns it, who produces it, who consumes it now and later, and what it carries. It does not design how any of it is implemented.

---

## 3. Scope

In scope:

1. Every current async event, signal, realtime message, public webhook boundary, provider callback and async task that the frozen Phase-6 design produces or consumes.
2. Every event name the frozen sources define for the future. These are listed and kept separate from current events.
3. Producer and consumer ownership for each event, using the five owner types (§9).
4. Per-event payload content: field names from the governing source, source lineage, identity sources, and security marks for 7I.
5. Reconciliation of the migration-075 analytics registry in both directions (§25).
6. Reconciliation of Billing usage producers (§26), including the FOD-7B-01 resolution (§29–§31).
7. Traceability from DDD to database to Phase-6 producer to 7A class to 7B event to consumers to the later Phase-7 owner (§38).

---

## 4. Non-Goals

7B does not produce any of the following:

| Non-goal | Owner |
|---|---|
| The common event envelope, the registry schema, JSON schemas, `event_version` rules and field-name binding | 7C |
| Outbox relay design, claim/publish loop, post-commit dispatch | 7D |
| Stream names, sharding, MAXLEN, consumer groups, autoscaling | 7E |
| Consumer inbox and idempotency store design | 7F/7G |
| Retry, DLQ and replay | 7G |
| Public webhook signing, versioning and topic mapping | 7H (6J remains authoritative; 7B does not alter signing or versioning) |
| Payload data classification and retention | 7I |
| Observability | 7J |
| Capacity, backpressure and regional design | 7K |
| Billing implementation, the in-flight usage reaper and reconciliation jobs | 7K/7L |
| Migration 113 or any other migration, SQL or Alembic | Not 7B |
| Application, Python, Redis or Celery code | Not 7B |
| Docker, OpenAPI or SDK changes | Not 7B |
| Any edit to Phase 4, Phase 5, Phase 6, 7A or migration 075 | Not 7B; required amendments are recorded as implementation obligations (IO-7B-*) only |
| Microservices or Kafka | Rejected by 7A |

---

## 5. Authority Hierarchy

7B inherits the 7A authority hierarchy (7A L77–L97) and adds the following event-catalog rules.

| ID | Rule |
|---|---|
| AUTH-7B-01 | A frozen source outranks 7B. 7B records a conflict with a frozen source. It never silently resolves the conflict by editing that source. |
| AUTH-7B-02 | The Phase-6 owner document of a bounded context is authoritative for the names, triggers, producers and current consumers of the events that context owns (6C Identity/Org, 6D Voice, 6E AI Agent, 6F Knowledge, 6G CRM, 6H Campaign, 6I Workflow, 6J Integrations, 6K Billing, 6L Analytics). |
| AUTH-7B-03 | AIR (the implementation-readiness matrix) is authoritative for the route-to-mechanism classification (the 369-route baseline) and for route-level producers. |
| AUTH-7B-04 | Where the AIR consumer column differs from the owner document's consumer statement, the owner document wins. The difference is recorded as a Minor conflict (CNF-*), not a rename or a new consumer. |
| AUTH-7B-05 | A payload stated by a Phase-6 owner document governs. Where Phase 6 gives no fields, the Phase-4 DDD event definition is the lineage source. Phase 4 and Phase 6 fields are never unioned. |
| AUTH-7B-06 | A consumer that Phase 4 names but Phase 6 does not wire is FUTURE, not CURRENT. |
| AUTH-7B-07 | Migration 075 is an analytics vocabulary registry. It is not the global event catalog and not a producer list. |
| AUTH-7B-08 | OD-7B-01 and OD-7B-02 are narrow owner decisions. OD-7B-01 governs only the Billing usage source for turn-level AI usage. OD-7B-02 governs only how a conversation's accounting is finalized (§31.5). Neither overrides 6D, 6K, Phase 5 or 7A globally. The source changes they require are recorded as IO-7B-* obligations for controlled later amendment. |

### 5.1 Authority by semantic concern (P1-7B-01)

7B uses no single global precedence order. Each source is authoritative only for its own semantic concern. When two sources disagree, the concern the disagreement is about decides which source governs. A disagreement that no single concern settles is recorded as a conflict (CNF-*) or an implementation obligation (IO-7B-*). It is never settled by ranking one whole artifact above another.

| ID | Semantic concern | Governing source | What it does not govern |
|---|---|---|---|
| AUTH-C-01 | Product intent: what the product must do, and owner-approved scope choices | `docs/product/PROJECT_ROADMAP.md` together with approved owner decisions | API shape, physical schema and event mechanics |
| AUTH-C-02 | Event-architecture standards: mechanism classes, durability, delivery semantics and the ownership rules 7B applies | 7A (frozen) | Per-event names, producers and payloads (7B owns these, within AUTH-C-03) |
| AUTH-C-03 | API and domain semantics: event names, triggers, producers, current consumers and stated payloads of each bounded context | The Phase-6 owner documents 6A–6M (AUTH-7B-02) | Physical columns and constraints |
| AUTH-C-04 | Physical schema: tables, columns, constraints and what is durably stored today | Phase-5 migrations `001_5B`…`112_5H5` | API semantics and product intent |
| AUTH-C-05 | Reconciliation, indexing and validation: route counts, route-to-mechanism classification, error and authorization indexes, freeze evidence | Phase-6 closure artifacts (AIR, AMI, AAM, AEC, AVS, FAR, certificate); AUTH-7B-03 | Physical schema. A closure artifact never outranks the migrations on what the database stores. It also never outranks an owner document on domain meaning (AUTH-7B-04). |
| AUTH-C-06 | Lineage: where a domain fact originated, and fields Phase 6 does not state | Phase 4 (4A–4I); AUTH-7B-05 | Current producers, consumers and physical schema |
| AUTH-C-07 | Narrow owner decisions | OD-7B-01 (turn-level Billing usage source) and OD-7B-02 (single-path accounting finalization) | Anything outside the scope written in the decision (AUTH-7B-08) |

Two consequences follow. First, a closure artifact does not rank above the database: where AIR or FAR describes a column differently from a migration, the migration governs what is stored (AUTH-C-04), and the difference is recorded (for example CNF-20). Second, the roadmap is not globally last: it governs product intent (AUTH-C-01), and no technical source overrides an approved product-intent decision within that concern.

---

## 6. Frozen Baseline

### 6.1 Route/mechanism baseline (AIR; unchanged by 7B)

| Mechanism (7A class) | Routes |
|---|---:|
| OUTBOX_REQUIRED (A) | 75 |
| OUTBOX_CONDITIONAL (B) | 2 |
| OUTBOX_WORKER_EMITTED (C) | 1 |
| OUTBOX_NONE | 265 |
| DIRECT_REDIS_STREAM (D) | 20 |
| WS_ONLY (F) | 1 |
| PUBLIC_WEBHOOK_DELIVERY (G) | 2 |
| PROVIDER_CALLBACK (H) | 3 |
| EVENT_TRIGGER_UNRESOLVED | 0 |
| **Total** | **369** |

CC-15 (routes with an outbox write, A + B) = 75 + 2 = 77.

These are route counts. Event counts are separate (§8.3). One route can emit several events, and many events are emitted by workers that are not routes.

### 6.2 Outbox baseline (migration `077_5J1.sql`)

| Property | Value |
|---|---|
| Table | `audit.domain_event_outbox` (single outbox; 7A) |
| Event identity | `id` UUIDv7. This is the durable `event_id`/`outbox_event_id`. |
| Columns used by 7B | `event_type`, `event_version` (INT, default 1), `organization_id` (nullable for platform events), `aggregate_type`, `aggregate_id`, `payload` (JSONB, ≤ 262144 bytes), `occurred_at` |
| Status lifecycle | PENDING → CLAIMED → PUBLISHED / FAILED; `max_attempts` = 10 |
| Relay functions | `fn_claim_outbox_events` (SKIP LOCKED), `fn_mark_outbox_published`, `fn_mark_outbox_failed` |
| Tenant guard | `trg_outbox_tenant_check`: a non-NULL `organization_id` must equal the session tenant |
| Delivery | At-least-once. Consumers must be idempotent. No exactly-once claim. |
| Sizing | Sized for "a handful of event types" per aggregate change, not per-turn traffic (6D L1221, L1234) |
| Retention | PUBLISHED 7 days, FAILED 30 days (6J L1578) |
| Audit | Synchronous `fn_insert_audit_event()` in the producing transaction. Audit is not an outbox consumer (6D L1223; 6E L916; 6F L1027). |

Example producer write (6J §37.1 L1488–L1500): `INSERT INTO audit.domain_event_outbox (event_type, organization_id, aggregate_type, aggregate_id, payload) VALUES ('integration.connected', :org_id, 'integration_connection', :connection_id, :payload_jsonb)`, then `fn_claim_outbox_events` → Redis Streams publish → `fn_mark_outbox_published`.

### 6.3 Analytics registry baseline (migration `075_5J.sql`)

Migration 075 registers 25 analytics event types. §25 reconciles them. 7B does not modify 075.

---

## 7. 7A Taxonomy Inheritance

7B adopts the 7A mechanism taxonomy unchanged (7A §9 L210–L231). Every catalog entry in 7B belongs to exactly one primary class A–I (TAX-01). 7B adds no class.

| Class | 7A name | Durable? | 7B catalog section | 7B ID prefix |
|---|---|---|---|---|
| A | Transactional durable domain event | Yes | §12 | EV-001…EV-071 |
| B | Conditional durable domain event | Yes, on the named branch | §13 | EV-072 (plus the secondary B branch of EV-001) |
| C | Worker-emitted durable domain event | Yes | §14 | EV-073…EV-105 |
| D | Direct Redis Stream event | No | §15 | DS-01…DS-19 |
| E | Celery task / command; scheduled trigger | Job row durable; message not a fact | §17 | TSK-* |
| F | Realtime push (WebSocket) | No | §16 | RTM-01…RTM-33 |
| G | Public (outbound) webhook | Delivery row durable | §18 | PWH-01, PWH-02 (+ topic register WHT-01…19) |
| H | Provider callback (inbound) | Dedup row durable | §19 | PCB-01…PCB-03 |
| I | Audit | Yes (immutable) | §20 | Boundary only; audit actions are not catalogued as events |

Inherited 7A rules that 7B applies to every entry:

| 7A rule | How 7B applies it |
|---|---|
| TAX-01 / TAX-02 | One primary class per entry. Callback-surface routes are classified by AIR §18.2, not by route surface. |
| DUR-01…DUR-06 (7A L276–L281) | Classes A/B/C are the only durable domain events. Delivery is at-least-once. 7B makes no exactly-once claim anywhere. |
| RS-01…RS-07 (7A L335–L341) | Redis Streams is transport only. Redis is never a semantic owner (§9). |
| CEL-01…CEL-06 (7A L353–L358) | A task (class E) is never an event. Tasks are listed separately (§17). |
| DEL-05 (7A L478) | Class D and F entries are best-effort and never carry an invariant-bearing fact. The one conflict (FOD-7B-01) is resolved by OD-7B-01 (§30). |
| OWN-01…OWN-05 (7A L581–L585) | The owning bounded context owns the name, meaning, payload and producer. Consumers never redefine an event. No renames. |
| TEN-01…TEN-06 (7A L593–L598) | Every durable entry is organization-scoped or explicitly platform-scoped (§39). |
| SEC-01…SEC-09 (7A L606–L614) | Payload security marks (§24, §39). |
| VOX-04 (7A L735), BIL-08 (7A L753) | Carried into FOD-7B-01 (§29) and resolved by OD-7B-01 (§30–§31). |

---

## 8. Catalog Status Model

### 8.1 Event status (§14 of the 7B spec)

| Status | Meaning |
|---|---|
| CURRENT_PRODUCED | A frozen Phase-6 producer (route or worker) emits the event in V1. Every CURRENT_PRODUCED entry also carries exactly one consumer qualifier: CURRENT_CONSUMED or CURRENT_NO_CONSUMER. |
| CURRENT_CONSUMED | Qualifier. The event is produced in V1 and at least one CURRENT consumer (§8.2) is wired. |
| CURRENT_NO_CONSUMER | Qualifier. The event is produced in V1, but the owner document says "None currently" (or names only FUTURE consumers). The event is still written to the outbox. Unconsumed events are retained and expire under the outbox retention (§6.2). |
| FUTURE_DEFINED | A frozen source defines the name for a future producer. No V1 producer exists. It keeps its name and future owner. It is never labelled current. |
| SUPERSEDED | A name that a frozen source replaced with another name. It is recorded, not re-used. |
| UNWIRED | A name with a defined consumer contract but no wired V1 producer (for example the Billing `TOOL_EXECUTIONS` usage producer, DEP-6K-01). It stays unwired until an owning amendment wires it. |
| CURRENT_CONSUMER_PRODUCER_UNWIRED (CCPU) | A name that a frozen Phase-6 document already consumes in a CURRENT V1 projection, while no frozen Phase-6 producer emits it on the bus. This is a present gap, not a future feature: the consumer is current, and the producer is missing. It is neither CURRENT_PRODUCED nor FUTURE_DEFINED. Each CCPU entry names its consumer evidence and the controlled reconciliation that must resolve it, either by wiring a producer or by amending the consumer to an existing authoritative fact (§32.5; IO-7B-22, IO-7B-23). |
| FAMILY | A wildcard entry (`tool_definition.*`, `data_subject_request.*`, `tool_execution.*`). It counts once. Its members are listed in §28 only where a frozen source names them. |

ANALYTICS_ONLY is a qualifier, not a status. It marks a current signal whose only current consumers are Analytics projections, such as DS-17 `conversation.turn_completed`. An ANALYTICS_ONLY signal must not be used as an authoritative billing or business source.

The 7B IDs (EV-*, DS-*, RTM-*, PWH-*, PCB-*, WHT-*, TSK-*, FUT-*, FAM-*) are local to this document. They are distinct from identically prefixed IDs in other artifacts. For example, AVS L154 uses EV-097 for `invoice.paid`, whereas 7B EV-097 is `campaign.outcome_computed`. Cross-references to AVS always name the artifact.

### 8.2 Consumer status

| Status | Meaning |
|---|---|
| CURRENT | The consumer is wired in the frozen Phase-6 owner document or the consumer's own Phase-6 document. |
| FUTURE | A frozen source names the consumer for later. It is not implemented in V1. |
| NONE CURRENTLY | The owner document says "None currently" (or the equivalent). 7B keeps this wording and invents no consumer. |

### 8.3 Catalog counts (event counts, kept separate from route counts in §6.1)

| Register | Count |
|---|---:|
| Class A events (EV-001…EV-071) | 71 |
| Class B events (EV-072) | 1 |
| Class C events (EV-073…EV-105) | 33 |
| Canonical durable domain events (A + B + C) | 105 |
| Class D direct-stream signals (DS-01…DS-19) | 19 |
| Class F realtime message types (RTM-01…RTM-33) | 33 |
| Class G delivery boundaries (PWH-01…PWH-02) | 2 |
| Class H provider callbacks (PCB-01…PCB-03) | 3 |
| Event families / wildcards (FAM-*) | see §28 |
| Future-defined names (FUT-*) | see §32 |
| Current-consumer / producer-unwired names (CCPU-*) | 2 (§32.5) |

A family entry (for example `tool_definition.*`) counts once in the catalog. Its members are listed in §28 only where a frozen source names them.

---

## 9. Ownership Model

Every event has five owner types. They are separate roles and may be held by different parties.

| Owner type | Definition | Rule |
|---|---|---|
| Semantic owner | The bounded context that owns the aggregate and therefore the event's name and meaning (OWN-01). | Always a bounded context. **Redis, the outbox, Celery, the relay and the webhook engine are never semantic owners.** |
| Producer owner | The component that writes the event: the request transaction (A/B), a named worker (C), a post-commit publisher (D) or the WS hub (F). | Always inside the semantic owner's context, except where a frozen source names a cross-context producer (for example `compliance.eligibility_denied`, produced by the Campaign executor; CNF-07). |
| Schema / payload owner | The owner of the payload content. | The semantic owner. 7B lists the fields. 7C owns the envelope, field binding and `event_version`. |
| Transport owner | The owner of delivery: the outbox relay (7D) and Redis Streams layout (7E) for A/B/C/D, the WS hub for F, the webhook engine for G. | A transport owner never changes meaning. |
| Consumer owner | Each consuming bounded context owns its own handler, idempotency and projection. | A consumer never redefines, renames or re-emits another context's event (OWN-02). |

A bounded context is a module boundary inside the monolith, not a microservice (OWN-03). Cross-context delivery is in-process work reading Redis Streams inside one deployable, not a network contract between services.

---

## 10. Naming Rules

| ID | Rule |
|---|---|
| NAM-01 | 7B uses each event name exactly as the governing frozen source spells it. 7B renames nothing and normalizes nothing (OWN-04, OWN-05). |
| NAM-02 | Different names are different catalog entries even when they look equivalent. `call.initiated` (6D, current bus event) and `call.started` (a current 6J webhook topic and a CCPU Analytics name, CCPU-01; no bus producer) are separate. `call.ended` (bus) and `call.completed` (webhook topic) are separate. The mapping between them belongs to 7H (IO-7B-12). |
| NAM-03 | Where frozen sources spell one fact in more than one form, 7B catalogs the form used by the current producer's owner document and lists every other form with its source in §10.1. No form is renamed. |
| NAM-04 | Public webhook topic names (6J L722–L740) are a separate namespace from internal event names. 7B does not invent a topic and does not alter signing or versioning. |
| NAM-05 | Migration 075 names are analytics vocabulary. Their presence in 075 does not make them current events (AUTH-7B-07). |
| NAM-06 | A wildcard family (`member.*`, `tool_definition.*`, `data_subject_request.*`, `tool_execution.*`) lists only members that a frozen source names. 7B fabricates no members. |
| NAM-07 | A new event name requires a governed amendment to the owning source. 7B introduces no new name. OD-7B-01 uses the existing name `conversation.completed` (4B L925). |

### 10.1 Multi-form names (recorded, not renamed)

| ID | Forms | Sources | 7B catalog form | Disposition |
|---|---|---|---|---|
| NAM-F-01 | `workflow.execution.completed` / `workflow.execution_completed` / `workflow_execution.completed` | 6I L937 and 6K (dotted form); 4E L1003, 4G L591, 6I L1089 (underscore form); 6I L894 (WS message form) | `workflow.execution.completed` (bus, EV-100); `workflow_execution.completed` stays a WS message type (RTM) | The WS form is a different mechanism (F), not a second event. The 4E/4G underscore form is Phase-4 lineage for the same fact. No rename. Minor CNF-01. |
| NAM-F-02 | `call.initiated` / `call.started` | 6D L1228 (`call.initiated`, current); 075 and 6J L722 (`call.started`) | Both kept. `call.initiated` is EV-004. `call.started` is a CURRENT governed webhook topic (WHT-01) and a CCPU Analytics name (CCPU-01). It has no bus producer. | Not merged. The internal source mapping for the topic is pending 7H (IO-7B-12). |
| NAM-F-03 | `call.ended` / `call.completed` | 6D L1230 (`call.ended`); 6J L723 (`call.completed` topic) | `call.ended` is EV-005. `call.completed` is a CURRENT governed webhook topic only (WHT-02). | Not merged. The internal source mapping is pending 7H (IO-7B-12). |
| NAM-F-04 | `contact.suppression_lifted` / `suppression.lifted` | 6G L1015 (`contact.suppression_lifted`); 4I L1411 (`suppression.lifted`) | `contact.suppression_lifted` (current 6G form) | 4I form recorded as lineage. No rename. Minor CNF-02. |
| NAM-F-05 | `campaign.contact_list_attached` / `contact_list.attached` | 6H L1740 | `campaign.contact_list_attached` | 6H states the mapping itself. |
| NAM-F-06 | `invoice.generated` (internal) / `invoice.created` (topic) | 6K L2816–L2827 | `invoice.generated` (EV-102) | Mapping stated by 6K. |
| NAM-F-07 | `contact.created` / `contact.qualified` / `contact.disqualified` (internal) → `lead.created` / `lead.qualified` / `lead.disqualified` (topics) | 6J L726–L728; 6G §30 | Internal names | Topic mapping stated by 6J/6G. 7H owns the serializer. |
| NAM-F-08 | `conversation.started` (4B bus) / `call.conversation_started` (6D) | 4B; 6D L1229 | `call.conversation_started` (EV-074, current) | `conversation.started` on the bus is FUTURE (FUT). Not merged. |
| NAM-F-09 | `call.terminated` / `call.ended` + `call.failed` | 6D L1214 (`call.terminated` as the terminate outcome wording); 6D L1230–L1231 (`call.ended`, `call.failed`) | `call.ended` (EV-005) and `call.failed` (EV-006), chosen by terminate outcome | `call.terminated` is not a separate catalog entry. No rename. Minor CNF-03. |

---

---

## 11. Canonical Event Catalog — Master Index (EV-001…EV-105)

This index lists every canonical durable domain event (classes A, B and C). Columns:

- **Class** is the primary 7A class.
- **Semantic owner** is the owning bounded context (§9).
- **Producer** is the AIR route (AMI ID) or the named worker.
- **Status** follows §8.1: CUR = CURRENT_PRODUCED; +C = CURRENT_CONSUMED; +N = CURRENT_NO_CONSUMER; FAM = FAMILY.

Class D signals are in §15, realtime messages in §16, public webhook boundaries in §18 and provider callbacks in §19.

| EV | Event | Class | Semantic owner | Producer | Status | Detail |
|---|---|---|---|---|---|---|
| EV-001 | `identity.forced_revocation_required` | A (+B branch) | Identity (6B) | 6B-009; 6B-036 (B branch) | CUR +C | §12.1, §13.2 |
| EV-002 | `organization.created` | A | Organization (6C) | 6C-001 | CUR +C | §12.1 |
| EV-003 | `compliance.policy_activated` | A | Compliance (6C) | 6C-030 | CUR +C | §12.1 |
| EV-004 | `call.initiated` | A | Voice (6D) | 6D-001 | CUR +N | §12.2 |
| EV-005 | `call.ended` | A | Voice (6D) | 6D-004; provider-event worker via 6D-021 | CUR +C | §12.2 |
| EV-006 | `call.failed` | A | Voice (6D) | 6D-004; provider-event worker via 6D-021 | CUR +C | §12.2 |
| EV-007 | `call.held` | A | Voice (6D) | 6D-006 | CUR +N | §12.2 |
| EV-008 | `call.resumed` | A | Voice (6D) | 6D-007 | CUR +N | §12.2 |
| EV-009 | `recording.deleted` | A | Voice (6D) | 6D-012 | CUR +C | §12.2 |
| EV-010 | `agent.created` | A | AI Agent (6E) | 6E-001; 6E-007 (clone) | CUR +N | §12.3 |
| EV-011 | `agent.config_updated` | A | AI Agent (6E) | 6E-004 | CUR +N | §12.3 |
| EV-012 | `agent.published` | A | AI Agent (6E) | 6E-005 | CUR +N | §12.3 |
| EV-013 | `agent.deprecated` | A | AI Agent (6E) | 6E-006 | CUR +N | §12.3 |
| EV-014 | `tool_definition.*` | A | AI Agent (6E) | 6E-011 / 6E-013 / 6E-014 | CUR +N, FAM | §12.3, §28 |
| EV-015 | `knowledge_base.created` | A | Knowledge (6F) | 6F-001 | CUR +N | §12.4 |
| EV-016 | `knowledge_base.settings_updated` | A | Knowledge (6F) | 6F-004 | CUR +N | §12.4 |
| EV-017 | `knowledge_base.archived` | A | Knowledge (6F) | 6F-005 | CUR +N | §12.4 |
| EV-018 | `knowledge_base.reindex_triggered` | A | Knowledge (6F) | 6F-006 | CUR +N | §12.4 |
| EV-019 | `document.uploaded` | A | Knowledge (6F) | 6F-008 (`/complete`); 6F-009 (URL/WEBSITE) | CUR +N | §12.4 |
| EV-020 | `document.deleted` | A | Knowledge (6F) | 6F-014 | CUR +C | §12.4 |
| EV-021 | `contact.created` | A | CRM (6G) | 6G-001 | CUR +C | §12.5 |
| EV-022 | `contact.updated` | A | CRM (6G) | 6G-004 | CUR +N | §12.5 |
| EV-023 | `contact.lead_status_changed` | A | CRM (6G) | 6G-005 | CUR +N | §12.5 |
| EV-024 | `contact.qualified` | A | CRM (6G) | 6G-006 (by outcome) | CUR +C | §12.5 |
| EV-025 | `contact.disqualified` | A | CRM (6G) | 6G-006 (by outcome) | CUR +C | §12.5 |
| EV-026 | `contact.converted` | A | CRM (6G) | 6G-007 | CUR +C | §12.5 |
| EV-027 | `contact.owner_assigned` | A | CRM (6G) | 6G-008 | CUR +N | §12.5 |
| EV-028 | `contact.merged` | A | CRM (6G) | 6G-011 | CUR +N | §12.5 |
| EV-029 | `contact.dnc_flagged` | A | CRM (6G) | 6G-013; 6G-075 | CUR +N | §12.5 |
| EV-030 | `suppression.added` | A | CRM (6G) | 6G-013; 6G-075 | CUR +N | §12.5 |
| EV-031 | `contact.suppression_lifted` | A | CRM (6G) | 6G-078 | CUR +N | §12.5 |
| EV-032 | `consent.recorded` | A | CRM (6G) | 6G-023 | CUR +N | §12.5 |
| EV-033 | `company.created` | A | CRM (6G) | 6G-024 | CUR +N | §12.5 |
| EV-034 | `company.updated` | A | CRM (6G) | 6G-027 | CUR +N | §12.5 |
| EV-035 | `deal.created` | A | CRM (6G) | 6G-029 | CUR +C | §12.5 |
| EV-036 | `deal.stage_changed` | A | CRM (6G) | 6G-033 | CUR +N | §12.5 |
| EV-037 | `deal.won` | A | CRM (6G) | 6G-034 | CUR +C | §12.5 |
| EV-038 | `deal.lost` | A | CRM (6G) | 6G-035 | CUR +C | §12.5 |
| EV-039 | `deal.abandoned` | A | CRM (6G) | 6G-036 | CUR +N | §12.5 |
| EV-040 | `activity.recorded` | A | CRM (6G) | 6G-044 | CUR +N | §12.5 |
| EV-041 | `task.created` | A | CRM (6G) | 6G-048 | CUR +N | §12.5 |
| EV-042 | `task.completed` | A | CRM (6G) | 6G-052 | CUR +N | §12.5 |
| EV-043 | `task.cancelled` | A | CRM (6G) | 6G-053 | CUR +N | §12.5 |
| EV-044 | `note.added` | A | CRM (6G) | 6G-055 | CUR +N | §12.5 |
| EV-045 | `note.deleted` | A | CRM (6G) | 6G-061 | CUR +N | §12.5 |
| EV-046 | `appointment.booked` | A | CRM (6G) | 6G-062 | CUR +C | §12.5 |
| EV-047 | `appointment.confirmed` | A | CRM (6G) | 6G-065 | CUR +N | §12.5 |
| EV-048 | `appointment.rescheduled` | A | CRM (6G) | 6G-066 | CUR +N | §12.5 |
| EV-049 | `appointment.cancelled` | A | CRM (6G) | 6G-067 | CUR +N | §12.5 |
| EV-050 | `appointment.completed` | A | CRM (6G) | 6G-068 | CUR +N | §12.5 |
| EV-051 | `appointment.no_show` | A | CRM (6G) | 6G-069 | CUR +N | §12.5 |
| EV-052 | `campaign.created` | A | Campaign (6H) | 6H-001 | CUR +N | §12.6 |
| EV-053 | `campaign.config_updated` | A | Campaign (6H) | 6H-004 | CUR +N | §12.6 |
| EV-054 | `campaign.contact_list_attached` | A | Campaign (6H) | 6H-005 | CUR +N | §12.6 |
| EV-055 | `campaign.scheduled` | A | Campaign (6H) | 6H-006 | CUR +N | §12.6 |
| EV-056 | `campaign.paused` | A | Campaign (6H) | 6H-008 | CUR +N | §12.6 |
| EV-057 | `campaign.resumed` | A | Campaign (6H) | 6H-009 | CUR +N | §12.6 |
| EV-058 | `campaign.stopping` | A | Campaign (6H) | 6H-010 | CUR +N | §12.6 |
| EV-059 | `campaign.cancelled` | A | Campaign (6H) | 6H-011 | CUR +N | §12.6 |
| EV-060 | `import.job_created` | A | Campaign (6H) | 6H-017 | CUR +C | §12.6 |
| EV-061 | `workflow.created` | A | Workflow (6I) | 6I-001 | CUR +N | §12.7 |
| EV-062 | `workflow.draft_updated` | A | Workflow (6I) | 6I-005 | CUR +N | §12.7 |
| EV-063 | `workflow.published` | A | Workflow (6I) | 6I-007 | CUR +N | §12.7 |
| EV-064 | `workflow.archived` | A | Workflow (6I) | 6I-008 | CUR +N | §12.7 |
| EV-065 | `integration.disconnected` | A | Integrations (6J) | 6J-007 | CUR +N | §12.8 |
| EV-066 | `webhook.endpoint_created` | A | Integrations (6J) | 6J-018 | CUR +N | §12.8 |
| EV-067 | `plugin.installed` | A | Integrations (6J) | 6J-032 | CUR +N | §12.8 |
| EV-068 | `plugin.activated` | A | Integrations (6J) | 6J-036 | CUR +N | §12.8 |
| EV-069 | `plugin.suspended` | A | Integrations (6J) | 6J-037 | CUR +N | §12.8 |
| EV-070 | `plugin.uninstalled` | A | Integrations (6J) | 6J-040 | CUR +N | §12.8 |
| EV-071 | `subscription.changed` | A | Billing (6K) | 6K-006 / 6K-007 / 6K-008 | CUR +C | §12.9 |
| EV-072 | `integration.connected` | B | Integrations (6J) | 6J-011 (success branch); connection-activation worker | CUR +N | §13.1 |
| EV-073 | `call.answered` | C | Voice (6D) | Provider-event worker (via 6D-021) | CUR +N | §14.1 |
| EV-074 | `call.conversation_started` | C | Voice (6D) | Internal `StartConversation` (6D §23.4) | CUR +N | §14.1 |
| EV-075 | `call.transferred` | C | Voice (6D) | Provider-event worker (via 6D-021) | CUR +C | §14.1 |
| EV-076 | `conversation.qualification_set` | C | Voice (6D) | Conversation runtime (qualification step) | CUR +C | §14.1 |
| EV-077 | `conversation.sentiment_computed` | C | Voice (6D) | Post-call analysis worker | CUR +N | §14.1 |
| EV-078 | `conversation.summarization_completed` | C | Voice (6D) | Post-call summarization worker | CUR +C | §14.1 |
| EV-079 | `conversation.completed` | C | Voice (6D) | Post-call / accounting-finalization worker (normal path) or Voice stale-conversation reaper / recovery worker (recovery path), both through the same atomic accounting finalization (PRD-27; OD-7B-01 / OD-7B-02; §31.6) | CUR +C (OD-7B-01 / OD-7B-02; IO-7B-01/02) | §14.1, §30–§31 |
| EV-080 | `knowledge_base.reindex_completed` | C | Knowledge (6F) | Reindex worker | CUR +N | §14.2 |
| EV-081 | `document.indexed` | C | Knowledge (6F) | Ingestion worker | CUR +C | §14.2 |
| EV-082 | `document.ingestion_failed` | C | Knowledge (6F) | Ingestion worker | CUR +N | §14.2 |
| EV-083 | `contact.score_updated` | C | CRM (6G) | Lead-scoring worker | CUR +N | §14.3 |
| EV-084 | `campaign.started` | C | Campaign (6H) | Campaign executor (PREPARING→RUNNING) | CUR +C | §14.4 |
| EV-085 | `campaign.completed` | C | Campaign (6H) | Campaign executor | CUR +C | §14.4 |
| EV-086 | `campaign.failed` | C | Campaign (6H) | Campaign executor | CUR +N | §14.4 |
| EV-087 | `campaign.contact.enqueued` | C | Campaign (6H) | Campaign executor | CUR +N | §14.4 |
| EV-088 | `campaign.contact.dnc_skipped` | C | Campaign (6H) | Campaign executor | CUR +N | §14.4 |
| EV-089 | `campaign.contact.ineligible` | C | Campaign (6H) | Campaign executor | CUR +N | §14.4 |
| EV-090 | `campaign.contact.call_attempted` | C | Campaign (6H) | Campaign executor (dialer) | CUR +C | §14.4 |
| EV-091 | `campaign.contact.qualified` | C | Campaign (6H) | Campaign executor (outcome recording) | CUR +C | §14.4 |
| EV-092 | `campaign.contact.disqualified` | C | Campaign (6H) | Campaign executor (outcome recording) | CUR +N | §14.4 |
| EV-093 | `campaign.contact.retry_scheduled` | C | Campaign (6H) | Campaign executor | CUR +N | §14.4 |
| EV-094 | `campaign.contact.exhausted` | C | Campaign (6H) | Campaign executor | CUR +N | §14.4 |
| EV-095 | `import.job_completed` | C | Campaign (6H) | Import worker (route 6H-018) | CUR +N | §14.4 |
| EV-096 | `import.job_failed` | C | Campaign (6H) | Import worker (route 6H-018) | CUR +N | §14.4 |
| EV-097 | `campaign.outcome_computed` | C | Campaign (6H) | Outcome computation worker | CUR +N | §14.4 |
| EV-098 | `compliance.eligibility_denied` | C | Compliance (6C) | Campaign executor (cross-context producer; CNF-07) | CUR +N | §14.5 |
| EV-099 | `workflow.execution.started` | C | Workflow (6I) | Workflow runtime | CUR +N | §14.6 |
| EV-100 | `workflow.execution.completed` | C | Workflow (6I) | Workflow runtime | CUR +C | §14.6 |
| EV-101 | `workflow.execution.failed` | C | Workflow (6I) | Workflow runtime | CUR +N | §14.6 |
| EV-102 | `invoice.generated` | C | Billing (6K) | Invoice generation worker (6K §35) | CUR +C | §14.7 |
| EV-103 | `invoice.paid` | C | Billing (6K) | Payment-provider event processing (via 6K-023) | CUR +C | §14.7 |
| EV-104 | `payment.failed` | C | Billing (6K) | Payment-provider event processing (via 6K-023) | CUR +C | §14.7 |
| EV-105 | `usage.threshold_reached` | C | Billing (6K) | Usage/quota worker | CUR +C | §14.7 |

Index totals: A = 71, B = 1, C = 33, for 105 canonical durable events. Of these, 31 are CURRENT_CONSUMED and 74 are CURRENT_NO_CONSUMER (§32.1).

**Class boundary rule.** EV-005 and EV-006 are Class A because their primary producer is the 6D-004 request transaction. When a provider callback (6D-021) drives the same transition, the provider-event worker writes the same event name. The class does not change and no second catalog entry is created (TAX-01). A consumer deduplicates on the outbox `event_id` and, for the business key, on `call_id` + `ended_at` / `failed_at` (§27).

---

## 12. Class A Catalog — Transactional Durable Domain Events

Every Class A event is written into `audit.domain_event_outbox` inside the same PostgreSQL transaction as its aggregate change and its synchronous audit row (§6.2). If the transaction rolls back, no event exists.

Columns:

- **Route**: the AIR route (AMI ID).
- **Trigger**: the AIR trigger wording.
- **Aggregate**: indicative; 7C binds `aggregate_type`.
- **Current consumers / Future consumers**: per the owner document (AUTH-7B-02, AUTH-7B-06).

### 12.1 Identity, Organization and Compliance

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-001 | `identity.forced_revocation_required` | 6B-009 `POST /api/v1/auth/password/reset/confirm` | Password-change commit | user | Session denylist publisher/worker (6B) | — |
| EV-002 | `organization.created` | 6C-001 `POST /api/v1/organizations` | Organization plus owner membership insert | organization | Compliance default-policy seeding (6C §7.7) | Analytics, Billing (per Phase 4 4A; not wired) |
| EV-003 | `compliance.policy_activated` | 6C-030 `POST /api/v1/organizations/{organization_id}/compliance-policy/{policy_id}/activate` | `compliance_policies` status → ACTIVE | compliance_policy | Active-policy pointer-update consumer (6C) | Campaign eligibility cache (not wired) |

EV-001 is user-scoped. `organization_id` may be NULL (platform-scoped row; 077_5J1 permits NULL). Scope is recorded in §39.

### 12.2 Voice

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-004 | `call.initiated` | 6D-001 `POST /api/v1/calls` | INSERT `call_sessions` (INITIATED) | call_session | None currently | Analytics; Campaign (6D L1228); webhook topic `call.started` via 7H mapping (IO-7B-12) |
| EV-005 | `call.ended` | 6D-004 `POST /api/v1/calls/{call_id}/terminate`; 6D-021 provider path | → ENDED | call_session | CRM `handle_call_completed` (6G L861); Campaign `RecordCallOutcome` (6H L1293); Billing `CALL_MINUTES` (6K L1911); Analytics `call_metrics_hourly`, `agent_utilization_hourly` (6L L790, L797) | Webhook topic `call.completed` via 7H mapping (IO-7B-12) |
| EV-006 | `call.failed` | 6D-004; 6D-021 provider path | → FAILED | call_session | Campaign (6H L1294); Analytics (6L L790); webhook engine, topic `call.failed` (6J §37.2) | — |
| EV-007 | `call.held` | 6D-006 `POST /api/v1/calls/{call_id}/hold` | ACTIVE → HELD | call_session | None currently | CRM, Campaign, Billing, Analytics (6D L1230) |
| EV-008 | `call.resumed` | 6D-007 `POST /api/v1/calls/{call_id}/resume` | HELD → ACTIVE | call_session | None currently | As EV-007 |
| EV-009 | `recording.deleted` | 6D-012 `POST /api/v1/recordings/{recording_id}/delete` | Recording CAS UPDATE → DELETED | recording | Recording-object cleanup worker (6D §16.3a) | — |

6D L1230 labels the consumers of `call.ended` / `call.failed` "all future". The consumers' own frozen documents (6G, 6H, 6K, 6L) wire them as current. Under AUTH-7B-02 the consumer's own document governs its consumer role. This is recorded as Minor CNF-08 with IO-7B-14.

`call.terminated` (6D L1214) is audit/terminate wording, not a separate event (NAM-F-09).

### 12.3 AI Agent

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-010 | `agent.created` | 6E-001 `POST /api/v1/agents`; 6E-007 `POST /api/v1/agents/{agent_id}/clone` | INSERT `agents` | agent | None currently (6D L1227) | Analytics agent-lifecycle projections |
| EV-011 | `agent.config_updated` | 6E-004 `PATCH /api/v1/agents/{agent_id}` | Config update | agent | None currently | As EV-010 |
| EV-012 | `agent.published` | 6E-005 `POST /api/v1/agents/{agent_id}/publish` | Publish | agent | None currently | As EV-010 |
| EV-013 | `agent.deprecated` | 6E-006 `POST /api/v1/agents/{agent_id}/deprecate` | Deprecate | agent | None currently | As EV-010 |
| EV-014 | `tool_definition.*` (FAMILY) | 6E-011 `POST /api/v1/tools`; 6E-013 `PATCH /api/v1/tools/{tool_id}`; 6E-014 `POST /api/v1/tools/{tool_id}/deactivate` | Created / updated / deactivated | tool_definition | None currently (6D L1232) | Analytics tool-usage projections |

### 12.4 Knowledge

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-015 | `knowledge_base.created` | 6F-001 `POST /api/v1/knowledge-bases` | INSERT `knowledge_bases` | knowledge_base | None currently | Analytics |
| EV-016 | `knowledge_base.settings_updated` | 6F-004 `PATCH /api/v1/knowledge-bases/{kb_id}` | Settings update | knowledge_base | None currently | Analytics |
| EV-017 | `knowledge_base.archived` | 6F-005 `POST /api/v1/knowledge-bases/{kb_id}/archive` | → ARCHIVED | knowledge_base | None currently | Analytics |
| EV-018 | `knowledge_base.reindex_triggered` | 6F-006 `POST /api/v1/knowledge-bases/{kb_id}/reindex` | `fn_kb_reindex_begin` | knowledge_base | None currently (the reindex job is a task, §17) | Analytics |
| EV-019 | `document.uploaded` | 6F-008 `POST /api/v1/knowledge-bases/{kb_id}/documents/{document_id}/complete`; 6F-009 `POST /api/v1/knowledge-bases/{kb_id}/documents` (URL/WEBSITE registration) | PENDING → PROCESSING; URL/WEBSITE document registered | document | None currently (ingestion is dispatched as a task, §17) | Analytics |
| EV-020 | `document.deleted` | 6F-014 `DELETE /api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | → DELETED | document | Knowledge `document_count` projection (6F L293) | Analytics |

The upload-URL route does **not** emit `document.uploaded`. The `/complete` route (6F-008) is the file-upload producer. The reprocess route emits no event, and no reprocess event exists. 7B creates none.

### 12.5 CRM

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-021 | `contact.created` | 6G-001 `POST /api/v1/contacts` | INSERT `contacts` | contact | Webhook engine, topic `lead.created` (6J L726; governed mapping) | Campaign, Analytics |
| EV-022 | `contact.updated` | 6G-004 `PATCH /api/v1/contacts/{contact_id}` | Update | contact | None currently | Analytics |
| EV-023 | `contact.lead_status_changed` | 6G-005 `POST /api/v1/contacts/{contact_id}/lead-status` | Lead-status transition | contact | None currently | Analytics |
| EV-024 | `contact.qualified` | 6G-006 `POST /api/v1/contacts/{contact_id}/qualify` | Qualification set (qualified outcome; exactly one event) | contact | Webhook engine, topic `lead.qualified` (6J L727) | Analytics |
| EV-025 | `contact.disqualified` | 6G-006 | Qualification set (disqualified outcome; exactly one event) | contact | Webhook engine, topic `lead.disqualified` (6J L728) | Analytics |
| EV-026 | `contact.converted` | 6G-007 `POST /api/v1/contacts/{contact_id}/convert` | Convert | contact | Analytics `lead_funnel` (6L L795) | — |
| EV-027 | `contact.owner_assigned` | 6G-008 `POST /api/v1/contacts/{contact_id}/owner` | Owner assignment | contact | None currently | Analytics |
| EV-028 | `contact.merged` | 6G-011 `POST /api/v1/contacts/{contact_id}/merge` | Merge | contact | None currently | Campaign, Analytics |
| EV-029 | `contact.dnc_flagged` | 6G-013 `POST /api/v1/contacts/{contact_id}/suppress`; 6G-075 `POST /api/v1/suppressions` | Suppression added | contact | None currently | Campaign DNC cache |
| EV-030 | `suppression.added` | 6G-013; 6G-075 | Suppression added | suppression | None currently | Campaign DNC cache |
| EV-031 | `contact.suppression_lifted` | 6G-078 `POST /api/v1/suppressions/{id}/lift` | Suppression lifted | suppression | None currently | Campaign DNC cache |
| EV-032 | `consent.recorded` | 6G-023 `POST /api/v1/contacts/{contact_id}/consent` | INSERT consent record | consent | None currently | Compliance |
| EV-033 | `company.created` | 6G-024 `POST /api/v1/companies` | INSERT `companies` | company | None currently | Analytics |
| EV-034 | `company.updated` | 6G-027 `PATCH /api/v1/companies/{id}` | Update | company | None currently | Analytics |
| EV-035 | `deal.created` | 6G-029 `POST /api/v1/deals` | INSERT `deals` | deal | Webhook engine, topic `deal.created` | Analytics |
| EV-036 | `deal.stage_changed` | 6G-033 `POST /api/v1/deals/{id}/stage` | Stage transition | deal | None currently | Analytics |
| EV-037 | `deal.won` | 6G-034 `POST /api/v1/deals/{id}/win` | → WON | deal | Webhook engine, topic `deal.won` | Analytics |
| EV-038 | `deal.lost` | 6G-035 `POST /api/v1/deals/{id}/lose` | → LOST | deal | Webhook engine, topic `deal.lost` | Analytics |
| EV-039 | `deal.abandoned` | 6G-036 `POST /api/v1/deals/{id}/abandon` | → ABANDONED | deal | None currently | Analytics |
| EV-040 | `activity.recorded` | 6G-044 `POST /api/v1/activities` | INSERT `activities` | activity | None currently | Analytics |
| EV-041 | `task.created` | 6G-048 `POST /api/v1/tasks` | INSERT `tasks` | task | None currently | Analytics |
| EV-042 | `task.completed` | 6G-052 `POST /api/v1/tasks/{id}/complete` | → COMPLETED | task | None currently | Analytics |
| EV-043 | `task.cancelled` | 6G-053 `POST /api/v1/tasks/{id}/cancel` | → CANCELLED | task | None currently | Analytics |
| EV-044 | `note.added` | 6G-055 `POST /api/v1/notes` | INSERT `notes` | note | None currently | Analytics |
| EV-045 | `note.deleted` | 6G-061 `DELETE /api/v1/notes/{id}` | Delete | note | None currently | Analytics |
| EV-046 | `appointment.booked` | 6G-062 `POST /api/v1/appointments` | INSERT `appointments` | appointment | Webhook engine, topic `appointment.booked` | Analytics |
| EV-047 | `appointment.confirmed` | 6G-065 `POST /api/v1/appointments/{id}/confirm` | → CONFIRMED | appointment | None currently | Analytics |
| EV-048 | `appointment.rescheduled` | 6G-066 `POST /api/v1/appointments/{id}/reschedule` | Reschedule | appointment | None currently | Analytics |
| EV-049 | `appointment.cancelled` | 6G-067 `POST /api/v1/appointments/{id}/cancel` | → CANCELLED | appointment | None currently | Analytics |
| EV-050 | `appointment.completed` | 6G-068 `POST /api/v1/appointments/{id}/complete` | → COMPLETED | appointment | None currently | Analytics |
| EV-051 | `appointment.no_show` | 6G-069 `POST /api/v1/appointments/{id}/no-show` | → NO_SHOW | appointment | None currently | Analytics |

The AIR consumer column for 6G reads "Campaign/Analytics/Billing/Webhook/Integrations". 6G itself wires only the consumers listed above (AUTH-7B-04). This is Minor CNF-04.

### 12.6 Campaign

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-052 | `campaign.created` | 6H-001 `POST /api/v1/campaigns` | INSERT `campaigns` | campaign | None currently | Analytics |
| EV-053 | `campaign.config_updated` | 6H-004 `PATCH /api/v1/campaigns/{campaign_id}` | Config update | campaign | None currently | Analytics |
| EV-054 | `campaign.contact_list_attached` | 6H-005 `POST /api/v1/campaigns/{campaign_id}/contact-list` | Attach | campaign | None currently | Analytics |
| EV-055 | `campaign.scheduled` | 6H-006 `POST /api/v1/campaigns/{campaign_id}/schedule` | → SCHEDULED | campaign | None currently (the executor start is a scheduled task, §17) | Analytics |
| EV-056 | `campaign.paused` | 6H-008 `POST /api/v1/campaigns/{campaign_id}/pause` | → PAUSED | campaign | None currently | Analytics |
| EV-057 | `campaign.resumed` | 6H-009 `POST /api/v1/campaigns/{campaign_id}/resume` | → RUNNING | campaign | None currently | Analytics |
| EV-058 | `campaign.stopping` | 6H-010 `POST /api/v1/campaigns/{campaign_id}/stop` | → STOPPING | campaign | None currently | Analytics |
| EV-059 | `campaign.cancelled` | 6H-011 `POST /api/v1/campaigns/{campaign_id}/cancel` | → CANCELLED | campaign | None currently | Analytics |
| EV-060 | `import.job_created` | 6H-017 `POST /api/v1/contact-lists/{contact_list_id}/imports/upload-url` | INSERT import job | import_job | Import worker (6H §13.2) | — |

`campaign.started` is not Class A. It is Class C (EV-084), emitted by the executor on PREPARING → RUNNING (AIR-P0-EVT-03).

### 12.7 Workflow

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-061 | `workflow.created` | 6I-001 `POST /api/v1/workflows` | INSERT `workflows` | workflow | None currently | Analytics |
| EV-062 | `workflow.draft_updated` | 6I-005 `PUT /api/v1/workflows/{workflow_id}/draft` | Draft PUT | workflow | None currently | Analytics |
| EV-063 | `workflow.published` | 6I-007 `POST /api/v1/workflows/{workflow_id}/publish` | Publish | workflow | None currently | Analytics |
| EV-064 | `workflow.archived` | 6I-008 `POST /api/v1/workflows/{workflow_id}/archive` | Archive | workflow | None currently | Analytics |

### 12.8 Integrations, Webhooks and Plugins

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-065 | `integration.disconnected` | 6J-007 `POST /api/v1/integrations/connections/{connection_id}/disconnect` | → DISCONNECTED | integration_connection | None currently | Analytics |
| EV-066 | `webhook.endpoint_created` | 6J-018 `POST /api/v1/webhook-endpoints` | INSERT `webhook_endpoints` | webhook_endpoint | None currently | Analytics |
| EV-067 | `plugin.installed` | 6J-032 `POST /api/v1/plugin-installations` | Installed | plugin_installation | None currently | Analytics |
| EV-068 | `plugin.activated` | 6J-036 `POST /api/v1/plugin-installations/{installation_id}/activate` | Activated | plugin_installation | None currently | Analytics |
| EV-069 | `plugin.suspended` | 6J-037 `POST /api/v1/plugin-installations/{installation_id}/suspend` | Suspended | plugin_installation | None currently | Analytics |
| EV-070 | `plugin.uninstalled` | 6J-040 `DELETE /api/v1/plugin-installations/{installation_id}` | Uninstalled | plugin_installation | None currently | Analytics |

6J §50 states that `integration.*` and `plugin.*` events are not webhook-eligible. The AIR consumer wording "WebhookDispatchService" for these rows is Minor CNF-05 (IO-7B-13). No webhook consumer is recorded.

### 12.9 Billing

| EV | Event | Route | Trigger | Aggregate | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-071 | `subscription.changed` | 6K-006 `POST /api/v1/billing/subscription`; 6K-007 `POST /api/v1/billing/subscription/change-plan`; 6K-008 `POST /api/v1/billing/subscription/cancel` | Subscription transition | subscription | Webhook engine, topic `subscription.changed` (6J §37.2) | Analytics |

**Class A route check:** 3 Identity/Org/Compliance routes (6B-009, 6C-001, 6C-030) + 5 Voice + 8 AI Agent + 7 Knowledge + 30 CRM + 9 Campaign + 4 Workflow + 6 Integrations + 3 Billing = **75**, equal to the AIR OUTBOX_REQUIRED count (§6.1).

---

## 13. Class B Catalog — Conditional Durable Domain Events

A Class B event is written to the outbox in the request transaction only on the named branch. Other branches write no event.

### 13.1 EV-072 `integration.connected`

| Field | Value |
|---|---|
| Semantic owner | Integrations (6J) |
| B route | 6J-011 `GET /api/v1/integrations/oauth/{definition_key}/callback`. `fn_activate_integration_connection` → ACTIVE, on the success branch only. |
| Other producer | The connection-activation worker, after credential validation succeeds, for API_KEY / BASIC / CUSTOM connections (AIR-P0-EVT-04) |
| Non-producers | HTTP create does not activate API_KEY / BASIC / CUSTOM connections and emits no `integration.connected`. An activation failure emits no event. |
| Aggregate | integration_connection |
| Current consumers | None currently. 6J §50: not webhook-eligible. |
| Future consumers | Analytics; plugin capability wiring |
| Class | B (single primary class; the worker path is the same conditional fact on the success branch) |

### 13.2 EV-001 secondary B branch

| Field | Value |
|---|---|
| Route | 6B-036 `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all` |
| Branch | `fn_platform_revoke_all_sessions` revoked ≥ 1 session (`v_count > 0`). With `v_count = 0`, no event. |
| Event | `identity.forced_revocation_required` (EV-001; primary class A via 6B-009) |
| Consumers | As EV-001 |

**Class B route check:** 6B-036 + 6J-011 = **2**, equal to AIR OUTBOX_CONDITIONAL.

---

## 14. Class C Catalog — Worker-Emitted Durable Domain Events

A Class C event is written to the outbox by a named worker, in the same transaction as the worker's own state change. The only AIR route classified OUTBOX_WORKER_EMITTED is 6H-018 (import completion, EV-095 / EV-096). All other Class C producers are workers, not routes.

### 14.1 Voice / Conversation

| EV | Event | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|
| EV-073 | `call.answered` | Provider-event worker (from 6D-021 `POST /webhooks/voice/{provider_slug}/events`) | Provider answer fact | None currently | CRM call-history, Billing start-of-metering (6D L1229) |
| EV-074 | `call.conversation_started` | Internal `StartConversation` (6D §23.4) | Conversation opened on an answered call | None currently | As EV-073 |
| EV-075 | `call.transferred` | Provider-event worker (from 6D-021) | Transfer confirmed | Webhook engine, topic `call.transferred` (6J §37.2) | CRM, Campaign, Analytics |
| EV-076 | `conversation.qualification_set` | Conversation runtime (qualification step) | Qualification outcome set | CRM (6G L862); Campaign (6H L1295) | Analytics |
| EV-077 | `conversation.sentiment_computed` | Post-call analysis worker | Sentiment computed | None currently | CRM, Analytics |
| EV-078 | `conversation.summarization_completed` | Post-call summarization worker | Summary persisted | CRM (6G L863) | — |
| EV-079 | `conversation.completed` | Post-call / accounting-finalization worker (normal path); Voice stale-conversation reaper / recovery worker (recovery path); PRD-27 | Authoritative conversation accounting finalization (OD-7B-01 / OD-7B-02; §31.6). Does not assert that the Voice call outcome was successful. | Billing usage ingestion (OD-7B-01; activated through IO-7B-01 / IO-7B-02) | Analytics |

6D L1216 lists `conversation.qualification_set` in the "internal Redis Stream event" row. Its CRM and Campaign consumers (6G L862, 6H L1295) are frozen durable consumers. 7B catalogs it as Class C and records the wording difference as Minor CNF-09.

EV-079 is the only conversation-level durable Billing source. §29–§31 give its contract. `conversation.completed` / EV-079 is emitted exactly once at authoritative conversation accounting finalization. The finalization may be reached through the normal post-call path or the stale/crash recovery path. The event does NOT assert that the Voice call outcome was successful. The call outcome stays in `call.ended` (EV-005) and `call.failed` (EV-006). EV-079 is never emitted per turn.

### 14.2 Knowledge

| EV | Event | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|
| EV-080 | `knowledge_base.reindex_completed` | Reindex worker (6F; AIR 6F-006 note) | Reindex finished | None currently | Analytics |
| EV-081 | `document.indexed` | Ingestion worker | Chunks and embeddings committed | Billing `EMBEDDING_TOKENS` (6K L1916); Knowledge `document_count` projection (6F L293) | Analytics |
| EV-082 | `document.ingestion_failed` | Ingestion worker | Terminal ingestion failure | None currently | Analytics |

### 14.3 CRM

| EV | Event | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|
| EV-083 | `contact.score_updated` | Lead-scoring worker (6G) | Score recomputed | None currently | Campaign prioritisation, Analytics |

### 14.4 Campaign

| EV | Event | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|
| EV-084 | `campaign.started` | Campaign executor | PREPARING → RUNNING (AIR-P0-EVT-03) | Webhook engine, topic `campaign.started` | Analytics |
| EV-085 | `campaign.completed` | Campaign executor | → COMPLETED | Webhook engine, topic `campaign.completed` | Analytics |
| EV-086 | `campaign.failed` | Campaign executor | → FAILED | None currently | Analytics |
| EV-087 | `campaign.contact.enqueued` | Campaign executor | Contact enqueued for dialing | None currently | Analytics |
| EV-088 | `campaign.contact.dnc_skipped` | Campaign executor | Contact skipped by DNC/suppression | None currently | Analytics |
| EV-089 | `campaign.contact.ineligible` | Campaign executor | Contact ineligible (non-DNC eligibility rule) | None currently | Analytics |
| EV-090 | `campaign.contact.call_attempted` | Campaign executor (dialer) | Call attempt placed | Billing `CAMPAIGN_CALLS` (6K L1917) | Analytics |
| EV-091 | `campaign.contact.qualified` | Campaign executor (outcome recording) | Contact outcome qualified | Webhook engine, topic `campaign.contact.qualified` | Analytics |
| EV-092 | `campaign.contact.disqualified` | Campaign executor (outcome recording) | Contact outcome disqualified | None currently | Analytics |
| EV-093 | `campaign.contact.retry_scheduled` | Campaign executor | Retry scheduled | None currently | Analytics |
| EV-094 | `campaign.contact.exhausted` | Campaign executor | Attempts exhausted | None currently | Analytics |
| EV-095 | `import.job_completed` | Import worker (route 6H-018 `POST /api/v1/contact-lists/{contact_list_id}/imports/{import_job_id}/complete`) | Worker terminal state: completed | None currently | Campaign list refresh, Analytics |
| EV-096 | `import.job_failed` | Import worker (route 6H-018) | Worker terminal state: failed | None currently | As EV-095 |
| EV-097 | `campaign.outcome_computed` | Outcome computation worker | Campaign outcome computed | None currently | Analytics `campaign_outcome_summary` (6L L116, L233), once its projection function exists (6L L169; CNF-15, CNF-17) |

6H L1742 describes `campaign.started` in request wording. The executor is the producer (AIR-P0-EVT-03). This is Minor CNF-10. The AIR 6H-018 consumer wording "import consumers (6H §13.3)" is Minor CNF-06.

### 14.5 Compliance (produced by Campaign)

| EV | Event | Semantic owner | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|---|
| EV-098 | `compliance.eligibility_denied` | Compliance (6C) | Campaign executor pre-dial eligibility check | Eligibility denied for a dial attempt | None currently | Compliance reporting, Analytics |

This is the one frozen cross-context producer (§9; CNF-07). Compliance owns the name, meaning and payload. Campaign writes the row inside its own transaction and never redefines the event.

### 14.6 Workflow

| EV | Event | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|
| EV-099 | `workflow.execution.started` | Workflow runtime (6I) | Execution started | None currently | Analytics |
| EV-100 | `workflow.execution.completed` | Workflow runtime (6I L937) | Execution completed | Billing `WORKFLOW_EXECUTIONS` plus standalone `LLM_PROMPT_TOKENS` / `LLM_COMPLETION_TOKENS` (6K L1914–L1915, L1918) | Analytics (6I "required by Analytics"; no 6L projection named; CNF-14) |
| EV-101 | `workflow.execution.failed` | Workflow runtime (6I) | Execution failed | None currently | Analytics |

The WS message forms `workflow_execution.completed` / `workflow_execution.failed` are Class F (RTM-32, RTM-33) and not authoritative (NAM-F-01).

### 14.7 Billing

| EV | Event | Producer | Trigger | Current consumers | Future consumers |
|---|---|---|---|---|---|
| EV-102 | `invoice.generated` | Invoice generation worker (6K §35) | DRAFT → OPEN | Webhook engine, topic `invoice.created` (mapping 6K L2816–L2827) | Analytics |
| EV-103 | `invoice.paid` | Payment-provider event processing (from 6K-023 `POST /api/v1/billing/payment-providers/{provider_slug}/webhook`) | Settlement fact: paid | Webhook engine, topic `invoice.paid` | Analytics |
| EV-104 | `payment.failed` | Payment-provider event processing (from 6K-023) | Settlement fact: failed | Webhook engine, topic `payment.failed` | Dunning (6K), Analytics |
| EV-105 | `usage.threshold_reached` | Usage/quota worker (6K) | Quota threshold crossed | Webhook engine, topic `usage.threshold_reached` | Analytics |

The 6K §35 invoice worker row names "`invoice.created` outbox event". 6K L2816–L2827 fixes `invoice.generated` as the internal name and `invoice.created` as the webhook topic. 7B catalogs the internal name (NAM-F-06) and records the §35 wording as Minor CNF-18.

**Class C route check:** 6H-018 = **1**, equal to AIR OUTBOX_WORKER_EMITTED.

---

## 15. Class D Catalog — Direct Redis Stream Signals (DD-15)

A Class D signal is published to Redis Streams after commit, without an outbox row. It is non-durable and best-effort. It never carries an invariant-bearing fact (DEL-05). It must never be used as a billing, compliance or financial source of truth.

Columns: **DS** · **Signal** · **Semantic owner** · **Producer** · **Trigger** · **Current consumers** · **Status**.

| DS | Signal | Semantic owner | Producer | Trigger | Current consumers | Status |
|---|---|---|---|---|---|---|
| DS-01 | `organization.updated` | Organization (6C) | 6C-003 `PATCH /api/v1/organizations/{organization_id}` | On commit (non-durable) | None currently | CURRENT_PRODUCED, CURRENT_NO_CONSUMER |
| DS-02 | `organization.suspended` | Organization (6C) | 6C-006 `POST /api/v1/organizations/{organization_id}/suspend` | On commit | None currently | CUR +N |
| DS-03 | `organization.cancelled` | Organization (6C) | 6C-007 `POST /api/v1/organizations/{organization_id}/cancel` | On commit | None currently | CUR +N |
| DS-04 | `member.invited` | Organization (6C) | 6C-016 `POST /api/v1/organizations/{organization_id}/invitations` | On commit | None currently | CUR +N |
| DS-05 | `member.role_changed` | Organization (6C) | 6C-010 `POST /api/v1/organizations/{organization_id}/members/{member_id}/role` | On commit | None currently | CUR +N |
| DS-06 | `member.suspended` | Organization (6C) | 6C-011 `POST /api/v1/organizations/{organization_id}/members/{member_id}/suspend` | On commit | None currently | CUR +N |
| DS-07 | `member.reactivated` | Organization (6C) | 6C-012 `POST /api/v1/organizations/{organization_id}/members/{member_id}/reactivate` | On commit | None currently | CUR +N |
| DS-08 | `member.removed` | Organization (6C) | 6C-013 `POST /api/v1/organizations/{organization_id}/members/{member_id}/remove` | On commit | None currently | CUR +N |
| DS-09 | `member.left` | Organization (6C) | 6C-014 `POST /api/v1/organizations/{organization_id}/members/me/leave` | On commit | None currently | CUR +N |
| DS-10 | `ownership.transferred` | Organization (6C) | 6C-015 `POST /api/v1/organizations/{organization_id}/ownership/transfer` | On commit | None currently | CUR +N |
| DS-11 | `team.created` | Organization (6C) | 6C-021 `POST /api/v1/organizations/{organization_id}/teams` | On commit | None currently | CUR +N |
| DS-12 | `team.updated` | Organization (6C) | 6C-023 `PATCH /api/v1/organizations/{organization_id}/teams/{team_id}` | On commit | None currently | CUR +N |
| DS-13 | `team.archived` | Organization (6C) | 6C-024 `POST /api/v1/organizations/{organization_id}/teams/{team_id}/archive` | On commit | None currently | CUR +N |
| DS-14 | `team.member_added` | Organization (6C) | 6C-026 `POST /api/v1/organizations/{organization_id}/teams/{team_id}/members` | On commit | None currently | CUR +N |
| DS-15 | `team.member_removed` | Organization (6C) | 6C-027 `DELETE /api/v1/organizations/{organization_id}/teams/{team_id}/members/{user_id}` | On commit | None currently | CUR +N |
| DS-16 | `data_subject_request.*` | Compliance (6C) | 6C-031 `POST /api/v1/organizations/{organization_id}/data-subject-requests`; 6C-034 `POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/verify`; 6C-035 `POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/hold`; 6C-036 `POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/complete`; 6C-037 `POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/reject` | On commit | None currently | CUR +N, FAMILY. AIR: "family only; member name not catalogued". 7B names no member (NAM-06). |
| DS-17 | `conversation.turn_completed` | Voice / Conversation (6D L1216, L1234; 6K attributes it to 6E, CNF-16) | Conversation runtime, per turn, after the per-turn checkpoint transaction commits | Per completed turn | Analytics token-usage and latency projections (6D L1216; 6L L794) | CUR, ANALYTICS_ONLY (OD-7B-01). **Not authoritative for Billing.** Never assigned an outbox id. Minimum semantic payload: PAY-D-01 (§15.1). |
| DS-18 | `provider.failover_triggered` | Voice (6D §15.5) | Provider-routing layer | Provider failover | None outside Voice ("internal only", 6D L1216) | CUR +N |
| DS-19 | `tool_execution.*` | Voice runtime (6D L1234, L1697–L1699; 6E L145: tool execution "REMAINS 6D-OWNED — READ-ONLY PROJECTION") | In-process turn loop, per tool execution (6D L1234: internal Redis Streams) | Tool execution started, succeeded or failed | Analytics tool projection (6L L457 `tool_execution_stats_daily`; 6L L772 event provenance). The projection population is a 6L parity GAP (6L L744–L750). **Billing is not a consumer.** | CURRENT_PRODUCED, CURRENT_CONSUMED, FAMILY. Minimum semantic payload: PAY-D-02 (§15.1). The Billing `TOOL_EXECUTIONS` usage producer is a separate, unwired item (UNW-01; DEP-6K-01). |

**Class D route check:** DS-01…DS-15 map to 15 routes. DS-16 maps to 5 routes. Total **20**, equal to AIR DIRECT_REDIS_STREAM. DS-17, DS-18 and DS-19 are runtime signals with no route. They are produced by the conversation runtime, not by an HTTP route.

**DS-17 rule (OD-7B-01).** `conversation.turn_completed` stays Class D. It is direct Redis Stream, non-durable and high-frequency. Its only current consumer is Analytics. Billing must not treat it as a source of truth, and no per-turn outbox row is ever written for it. 6K §21.1 L1912–L1915 and §22 L1965–L1971 currently name it as the producer for `AI_MINUTES`, `STT_SECONDS`, `TTS_CHARACTERS`, `LLM_PROMPT_TOKENS` and `LLM_COMPLETION_TOKENS`, with `source_event_id = <outbox_event_id>:<metric>`. A Class D signal has no outbox id, so that identity cannot exist. OD-7B-01 moves the Billing source for these metrics to EV-079 `conversation.completed` (§30). The 6K text change is recorded as IO-7B-02 and is not made here.

Other non-bus signals named by frozen sources are not Class D entries: `transcript.segment_added` (4B §11.7, "not published to event bus"; 6D L1234) and the per-turn WS messages (§16).

### 15.1 Class-D semantic payload registry (P1-7B-06)

A Class D signal that has a current consumer needs a stated minimum meaning, so a consumer does not invent one. This registry lists **semantic** fields only. 7C binds the field names, types and envelope. 7I classifies every field marked [7I]. No entry here is a physical column name. Class D payloads are never Billing-authoritative (OD-7B-01).

| PAY | Signal | Minimum semantic payload | Excluded | Authority |
|---|---|---|---|---|
| PAY-D-01 | DS-17 `conversation.turn_completed` | Conversation reference; turn reference; turn sequence number; agent grain reference (7C decides whether it is carried or resolvable from the conversation); turn latency measures (STT latency, LLM first-token latency, TTS first-audio latency, turn end-to-end latency; 5C `voice.turns`); per-turn usage telemetry (prompt tokens, completion tokens, STT audio seconds, TTS characters); barge-in flag; tool execution references and count; provider and model reference ids [7I]; turn completion time | The caller's spoken text and the agent's response text (5C `voice.turns` text columns). Adding either later needs a 7I classification first. Provider pricing and procurement cost. Secrets, tokens and media bytes. | Analytics only. Not Billing-authoritative. The per-turn usage telemetry is observational; the Billing figure comes only from EV-079 (§31). |
| PAY-D-02 | DS-19 `tool_execution.*` | Tool execution reference; turn reference; tool reference or name [7I]; outcome (started, succeeded, failed or timed out; 6D L1699 folds TIMED_OUT into `.failed`); duration; error code; attempt count | Tool arguments and tool results (6D L1309 marks them sensitive; 6D L1698 does not inline the result). Credentials used by the tool. | Analytics only. Not Billing-authoritative. Billing is not a DS-19 consumer. |

Other current Class D signals have no current consumer (DS-01…DS-16, DS-18). They need no payload registry entry until a consumer is defined; that consumer's owner then adds one through 7C.

---

## 16. Class F Catalog — Realtime WebSocket Messages

Class F messages are delivered to connected clients over the WebSocket gateway. They are non-durable, ordered per session only as far as 6D §29 states, and recoverable only by client resync (`resync.required` → REST reload). A Class F message is never a domain event. No consumer may derive a durable fact from one (DEL-05). Names are kept exactly as frozen; the WS forms are not normalized to the domain names (NAM-F-01, NAM-F-02).

Among the 369 AMI routes, AIR classifies exactly one as WS_ONLY: AMI-6D-005 `POST /api/v1/calls/{call_id}/transfer` (`call.transferring`, no outbox row). The Class F route count is therefore 1. The messages themselves travel over the 4 WebSocket routes in the AMI WS table (AMI L548–L554). These are outside the 369 routes and are not event producers.

| RTM | Message | Direction | Source | Durable counterpart (if any) | Note |
|---|---|---|---|---|---|
| RTM-01 | `session.subscribe` | Client → server | 6D §29.1 | — | Control |
| RTM-02 | `session.subscribed` | Server → client | 6D §29.1 | — | Control |
| RTM-03 | `session.unsubscribe` | Client → server | 6D §29.1 | — | Control |
| RTM-04 | `heartbeat.ping` | Both | 6D §29.1 | — | Control |
| RTM-05 | `heartbeat.pong` | Both | 6D §29.1 | — | Control |
| RTM-06 | `error` | Server → client | 6D §29.2 | — | Control |
| RTM-07 | `resync.required` | Server → client | 6D §29.2 | — | Recovery signal |
| RTM-08 | `call.state_changed` | Server → client | 6D §29.3 | Several call events (EV-004…008, EV-073, EV-075) | Projection of the state machine |
| RTM-09 | `call.answered` | Server → client | 6D §29.3 | EV-073 | Same name, distinct class (NAM-F-02) |
| RTM-10 | `call.held` | Server → client | 6D §29.3 | EV-007 | Same name, distinct class |
| RTM-11 | `call.resumed` | Server → client | 6D §29.3 | EV-008 | Same name, distinct class |
| RTM-12 | `call.transferring` | Server → client | 6D §29.3 | None (WS_ONLY; 6D-005) | No domain event exists or is created |
| RTM-13 | `call.transferred` | Server → client | 6D §29.3 | EV-075 | Same name, distinct class |
| RTM-14 | `call.ended` | Server → client | 6D §29.3 | EV-005 | Same name, distinct class |
| RTM-15 | `call.failed` | Server → client | 6D §29.3 | EV-006 | Same name, distinct class |
| RTM-16 | `conversation.started` | Server → client | 6D §29.4 | EV-074 `call.conversation_started` | WS name ≠ domain name. `conversation.started` (4B L919) is not a durable 7B event (FUT-02). |
| RTM-17 | `turn.utterance_partial` | Server → client | 6D §29.4 | — | High frequency. Carries transcript text: [7I] |
| RTM-18 | `turn.utterance_final` | Server → client | 6D §29.4 | — | Carries transcript text: [7I] |
| RTM-19 | `turn.agent_response_delta` | Server → client | 6D §29.4 | — | High frequency: [7I] |
| RTM-20 | `turn.agent_response_final` | Server → client | 6D §29.4 | — | [7I] |
| RTM-21 | `turn.completed` | Server → client | 6D §29.4 | DS-17 (Class D, Analytics only) | Not billing-authoritative |
| RTM-22 | `conversation.completed` | Server → client | 6D §29.4 | EV-079 | Same name, distinct class. The WS message is not the Billing source. |
| RTM-23 | `tool_execution.started` | Server → client | 6D §29.5 | DS-19 (Class D current) | WS projection of a current Class D signal |
| RTM-24 | `tool_execution.succeeded` | Server → client | 6D §29.5 | DS-19 (Class D current) | WS projection of a current Class D signal |
| RTM-25 | `tool_execution.failed` | Server → client | 6D §29.5 | DS-19 (Class D current) | WS projection of a current Class D signal |
| RTM-26 | `voice.barge_in_detected` | Server → client | 6D §29.6 | — | WS only |
| RTM-27 | `voice.tts_cancelled` | Server → client | 6D §29.6 | — | WS only |
| RTM-28 | `conversation.qualification_set` | Server → client | 6D §29.7 | EV-076 | Same name, distinct class |
| RTM-29 | `workflow_execution.node_entered` | Server → client | 6I L894 | — | Not durable (FOD rule) |
| RTM-30 | `workflow_execution.node_exited` | Server → client | 6I L894 | — | Not durable |
| RTM-31 | `workflow_execution.slot_updated` | Server → client | 6I L894 | — | Not durable. Slot values: [7I] |
| RTM-32 | `workflow_execution.completed` | Server → client | 6I L894 | EV-100 `workflow.execution.completed` | Underscore form kept (NAM-F-01) |
| RTM-33 | `workflow_execution.failed` | Server → client | 6I L894 | EV-101 `workflow.execution.failed` | Underscore form kept |

Count: 28 (6D §29) + 5 (6I L894) = **33**.

**Rule F-1.** Where a WS message shares a name with a durable event (RTM-09, 10, 11, 13, 14, 15, 22, 28), the durable event is authoritative. The WS message is a UI projection. Its absence, duplication or reordering never changes business state.

**Rule F-2.** No WS message is promoted to a durable event by 7B. Per the FOD, `node_entered`, `node_exited` and `slot_updated` stay non-durable.

---

## 17. Class E Catalog — Background Tasks and Commands (not events)

A Class E item is a unit of work dispatched to a worker queue (Celery or a scheduler). A task is an imperative instruction to one worker ("do X"). It is not a fact announced to many consumers. 7B catalogs tasks only so they are not mistaken for events (CEL-01…CEL-06). A task may *emit* a Class C event when it commits a state change. That event is catalogued in §14, not here.

| TSK | Task | Owner | Trigger | Emits (Class C) | Source |
|---|---|---|---|---|---|
| TSK-01 | Document ingestion (parse → chunk → embed) | Knowledge (6F) | Dispatched when EV-019 commits (6F-008 / 6F-009) | EV-081 or EV-082 | 6F ingestion pipeline |
| TSK-02 | Knowledge-base reindex | Knowledge (6F) | Dispatched after 6F-006 (`fn_kb_reindex_begin`) | EV-080 | 6F-006 AIR note |
| TSK-03 | Contact-list import processing | Campaign (6H) | EV-060 `import.job_created` (consumed by the import worker) | EV-095 or EV-096 via 6H-018 | 6H §13.2 |
| TSK-04 | Campaign executor start and dial loop | Campaign (6H) | Scheduler tick for SCHEDULED campaigns | EV-084…EV-094, EV-098 | 6H executor |
| TSK-05 | Campaign outcome computation | Campaign (6H) | Campaign terminal state | EV-097 | 6H |
| TSK-06 | Lead scoring | CRM (6G) | CRM signal or schedule | EV-083 | 6G |
| TSK-07 | Post-call sentiment analysis | Voice (6D) | Conversation end | EV-077 | 6D |
| TSK-08 | Post-call summarization | Voice (6D) | Conversation end | EV-078 | 6D |
| TSK-09 | Invoice generation | Billing (6K) | Billing-period close | EV-102 | 6K §35 |
| TSK-10 | Subscription renewal | Billing (6K) | Period boundary | None (subscription state changes via 6K routes emit EV-071) | 6K |
| TSK-11 | Usage/quota evaluation | Billing (6K) | Usage ingestion | EV-105 | 6K |
| TSK-12 | Storage snapshot (`STORAGE_GB`) | Billing (6K) | Periodic | None (writes `usage_events` directly; not an event) | 6K L1920 |
| TSK-13 | API request aggregation (`API_REQUESTS`) | Billing (6K) | Periodic | None | 6K L1921 |
| TSK-14 | Recording-object cleanup | Voice (6D) | EV-009 `recording.deleted` consumed | None | 6D §16.3a |
| TSK-15 | Webhook delivery and retry | Integrations (6J) | Consumer of webhook-eligible events | None (delivery attempts are records, not events) | 6J |
| TSK-16 | Outbox relay (PENDING → PUBLISHED) | Platform (7D) | Continuous | None; it transports events | 077_5J1; 7D |
| TSK-17 | Outbox retention purge (PUBLISHED 7 days; FAILED 30 days) | Platform (7D / 7K) | Periodic | None | 077_5J1 |
| TSK-18 | Analytics projection refresh | Analytics (6L) | Consumed events / schedule | None | 6L |
| TSK-19 | Session denylist propagation | Identity (6B) | EV-001 consumed | None | 6B |

**Rule E-1.** A task queue message never carries the canonical `event_id` of a new fact. When a task results from an event, it references the triggering `event_id` only for correlation (§27).

**Rule E-2.** The 6D-004 Celery task and other Class E work that also write a durable event write that event through the outbox (Class A or C), never by publishing directly.

---

## 18. Class G — Public Webhook Boundary

Class G is the public, signed HTTP boundary to tenant endpoints. The webhook topic is a Published-Language projection of a canonical domain event (§10.6). It is not a new event. 7B does not invent topics and does not alter signing, versioning, envelope, retry or replay (6J; AUTH-7B-08).

### 18.1 Class G routes (not domain events)

| PWH | Route | Nature |
|---|---|---|
| PWH-01 | 6J-025 `POST /api/v1/webhook-endpoints/{webhook_endpoint_id}/test` | Synthetic test delivery. Not a domain event; no outbox row. |
| PWH-02 | 6J-028 `POST /api/v1/webhook-deliveries/{delivery_id}/replay` | Redelivery of an existing delivery. Not a new domain event; no new outbox row. |

Class G route count = **2**, equal to AIR.

### 18.2 Webhook topic → canonical event mapping (6J L722–L740; 4F §8.4)

| WHT | Topic | Canonical source event | Mapping | Status |
|---|---|---|---|---|
| WHT-01 | `call.started` | Internal source mapping pending 7H (IO-7B-12). Candidate: EV-004 `call.initiated`. Names not merged. | Source mapping pending 7H | CURRENT governed topic (6J L722) |
| WHT-02 | `call.completed` | Internal source mapping pending 7H (IO-7B-12). Candidate: EV-005 `call.ended`. Names not merged. | Source mapping pending 7H | CURRENT governed topic (6J L723) |
| WHT-03 | `call.failed` | EV-006 `call.failed` | Same name | CURRENT |
| WHT-04 | `call.transferred` | EV-075 `call.transferred` | Same name | CURRENT |
| WHT-05 | `lead.created` | EV-021 `contact.created` | Governed Published-Language mapping (NAM-F-05) | CURRENT |
| WHT-06 | `lead.qualified` | EV-024 `contact.qualified` | Governed mapping | CURRENT |
| WHT-07 | `lead.disqualified` | EV-025 `contact.disqualified` | Governed mapping | CURRENT |
| WHT-08 | `deal.created` | EV-035 | Same name | CURRENT |
| WHT-09 | `deal.won` | EV-037 | Same name | CURRENT |
| WHT-10 | `deal.lost` | EV-038 | Same name | CURRENT |
| WHT-11 | `appointment.booked` | EV-046 | Same name | CURRENT |
| WHT-12 | `campaign.started` | EV-084 | Same name | CURRENT |
| WHT-13 | `campaign.completed` | EV-085 | Same name | CURRENT |
| WHT-14 | `campaign.contact.qualified` | EV-091 | Same name | CURRENT |
| WHT-15 | `invoice.created` | EV-102 `invoice.generated` | Governed mapping (6K L2816–L2827; NAM-F-06) | CURRENT (6K §45.1; CNF-11) |
| WHT-16 | `invoice.paid` | EV-103 | Same name | CURRENT (6K §45.1; CNF-11) |
| WHT-17 | `payment.failed` | EV-104 | Same name | CURRENT (6K §45.1; CNF-11) |
| WHT-18 | `usage.threshold_reached` | EV-105 | Same name | CURRENT (6K §45.1; CNF-11) |
| WHT-19 | `subscription.changed` | EV-071 | Same name | CURRENT (6K §45.1; CNF-11) |

Topic count = **19**, equal to 6J / 4F. All **19** are CURRENT governed topics (P1-7B-04). For 17 of them the canonical source event is mapped here. For WHT-01 and WHT-02 the topic is current, but the internal source event that feeds it is not yet mapped; 7H owns that mapping (IO-7B-12). The topic names `call.started` / `call.completed` are not merged with the domain names `call.initiated` / `call.ended`. The topics themselves, their signing and their versioning are unchanged (6J).

The 6J table labels the Billing producers "future 6K". 6K §45.1, frozen later, wires them. This is Minor CNF-11. Under AUTH-7B-02 the producing owner (6K) governs.

**Rule G-1.** `integration.*` and `plugin.*` events are not webhook-eligible (6J §50). EV-065…EV-070 and EV-072 have no topic.

**Rule G-2.** Sensitive-data columns follow 6J L722–L740 and §40. Recording URLs and transcripts are never embedded. Fields marked "Yes" or "Possibly" are routed to 7I for exact classification (IO-7B-07).

---

## 19. Class H — Provider Callback Boundary (inbound, not domain events)

A provider callback is an untrusted inbound HTTP request from an external provider. It is authenticated by provider signature and recorded before any domain effect. The callback itself is never a domain event. The domain events it may lead to are written later by a worker in its own transaction (Class C).

| PCB | Route | Owner | Recording table | Resulting events |
|---|---|---|---|---|
| PCB-01 | 6D-021 `POST /webhooks/voice/{provider_slug}/events` | Voice (6D) | Voice provider-event inbox (6D) | EV-073 `call.answered`, EV-075 `call.transferred`; EV-005 / EV-006 on provider-driven terminal transitions (§11 class boundary rule) |
| PCB-02 | 6J-014 `POST /api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` | Integrations (6J) | `inbound_webhook_events` | None currently. The integration effects are defined by 6J. |
| PCB-03 | 6K-023 `POST /api/v1/billing/payment-providers/{provider_slug}/webhook` | Billing (6K) | Payment-provider event record (6K) | EV-103 `invoice.paid`, EV-104 `payment.failed` |

Class H route count = **3**, equal to AIR.

**Rule H-1.** Provider event IDs are dedup keys for the inbound record only. They are never used as the canonical `event_id` (§27).

**Rule H-2.** A callback's claimed `organization_id` or tenant hint is never trusted for authorization. The owner resolves the tenant from its own stored mapping (the connection route ID or provider resource ID) before writing anything (§39).

**Rule H-3.** Raw provider payloads, signatures, secrets and media never enter a domain event payload.

---

## 20. Class I — Audit Boundary

Audit (`audit.audit_log`) is a synchronous, same-transaction compliance record written by the owning route or worker. It is not a domain event and not an outbox consumer (6D L1223; §6.2).

| Rule | Statement |
|---|---|
| AUD-01 | An audit action name (for example 6D `CALL_TERMINATED`) is never a domain event name. It is not catalogued in §11 (NAM-F-09). |
| AUD-02 | Audit rows are written in the same transaction as the aggregate change, whether or not an outbox row is also written. |
| AUD-03 | No consumer reads audit rows to reconstruct domain events. The outbox is the only durable event source. |
| AUD-04 | Audit does not subscribe to any stream. Removing every stream consumer changes no audit row. |
| AUD-05 | The AIR `NONE` routes (265) may still write audit rows. Having no event does not mean having no audit. |

**Class I route count.** Audit is a per-route property, not an event class with routes. AIR records no route as "audit only instead of event". The event-class route counts in §21.3 therefore sum to 369 without an audit column.

---

## 21. Producer Registry

A producer is the code unit that writes the event row (outbox) or publishes the signal (Redis Stream). The producer is always inside the semantic owner's bounded context, with one exception: EV-098 (§9, CNF-07).

### 21.1 Request-transaction producers (Classes A and B)

| PRD | Producer (owner) | Events | Transaction |
|---|---|---|---|
| PRD-01 | Identity request handlers (6B-009; 6B-036 B branch) | EV-001 | Request transaction |
| PRD-02 | Organization request handler (6C-001) | EV-002 | Request transaction |
| PRD-03 | Compliance request handler (6C-030) | EV-003 | Request transaction |
| PRD-04 | Voice request handlers (6D-001, 004, 006, 007, 012) | EV-004…EV-009 | Request transaction |
| PRD-05 | AI Agent request handlers (6E-001, 004, 005, 006, 007, 011, 013, 014) | EV-010…EV-014 | Request transaction |
| PRD-06 | Knowledge request handlers (6F-001, 004, 005, 006, 008, 009, 014) | EV-015…EV-020 | Request transaction |
| PRD-07 | CRM request handlers (30 routes, §12.5) | EV-021…EV-051 | Request transaction |
| PRD-08 | Campaign request handlers (6H-001, 004, 005, 006, 008, 009, 010, 011, 017) | EV-052…EV-060 | Request transaction |
| PRD-09 | Workflow request handlers (6I-001, 005, 007, 008) | EV-061…EV-064 | Request transaction |
| PRD-10 | Integrations request handlers (6J-007, 011 B, 018, 032, 036, 037, 040) | EV-065…EV-070, EV-072 | Request transaction |
| PRD-11 | Billing request handlers (6K-006, 007, 008) | EV-071 | Request transaction |

### 21.2 Worker producers (Class C, plus the B worker path)

| PRD | Producer (owner) | Events | Transaction |
|---|---|---|---|
| PRD-12 | Voice provider-event worker (from PCB-01) | EV-073, EV-075; EV-005 / EV-006 on the provider path | Worker transaction with the call-state change |
| PRD-13 | Voice `StartConversation` (6D §23.4) | EV-074 | Conversation-open transaction |
| PRD-14 | Conversation runtime (6D), qualification step | EV-076 | Qualification transaction. The live conversation runtime does **not** emit EV-079 (P1-7B-09); it persists and checkpoints conversation accounting state (ACC-01…ACC-03). DS-17 / DS-19 are Class D and belong to PRD-25. |
| PRD-15 | Voice post-call workers (TSK-07, TSK-08) | EV-077, EV-078 | Worker transaction |
| PRD-16 | Knowledge ingestion and reindex workers (TSK-01, TSK-02) | EV-080, EV-081, EV-082 | Worker transaction |
| PRD-17 | CRM lead-scoring worker (TSK-06) | EV-083 | Worker transaction |
| PRD-18 | Campaign executor (TSK-04) | EV-084…EV-094, EV-098 | Executor transaction per state change |
| PRD-19 | Campaign import worker (TSK-03; route 6H-018) | EV-095, EV-096 | Worker terminal-state transaction |
| PRD-20 | Campaign outcome worker (TSK-05) | EV-097 | Worker transaction |
| PRD-21 | Workflow runtime (6I) | EV-099, EV-100, EV-101 | Execution-state transaction |
| PRD-22 | Integrations connection-activation worker | EV-072 (success only) | Activation transaction |
| PRD-23 | Billing workers (TSK-09, TSK-11; PCB-03 processing) | EV-102…EV-105 | Worker transaction |
| PRD-27 | Voice-owned accounting-finalization workers (P1-7B-09; §31.6): (a) the **post-call / accounting-finalization worker** on the normal path; (b) the **Voice stale-conversation reaper / recovery worker** on the recovery path. Both are architectural roles; 7B names no function, module, class or Celery queue. | EV-079 | The single atomic accounting-finalization worker transaction (FIN-1…FIN-4; §31.2, OD-7B-02). Both roles invoke the same operation; the recovery role emits EV-079 only if the conversation is not already finalized. One producer contract, not two producer paths. |

### 21.3 Direct-stream producers (Class D)

| PRD | Producer | Signals |
|---|---|---|
| PRD-24 | Organization / Compliance request handlers (20 routes) | DS-01…DS-16 |
| PRD-25 | Conversation runtime (per turn; in-process turn loop) | DS-17, DS-19 |
| PRD-26 | Voice provider-routing layer | DS-18 |

### 21.4 AIR route-class reconciliation

| AIR class | 7B class | Routes | 7B entries |
|---|---|---|---|
| OUTBOX_REQUIRED | A | 75 | EV-001…EV-071 |
| OUTBOX_CONDITIONAL | B | 2 | EV-072; EV-001 B branch |
| OUTBOX_WORKER_EMITTED | C | 1 | EV-095 / EV-096 (6H-018). Other Class C producers are workers without routes. |
| DIRECT_REDIS_STREAM | D | 20 | DS-01…DS-16 |
| WS_ONLY | F | 1 | RTM-12 (6D-005) |
| PUBLIC_WEBHOOK (test / replay) | G | 2 | PWH-01, PWH-02 |
| PROVIDER_CALLBACK | H | 3 | PCB-01…PCB-03 |
| Job-row only | E | 0 | TSK-* (no route is a pure task producer in AIR) |
| NONE | — | 265 | No event |
| **Total** | | **369** | |

75 + 2 + 1 + 20 + 1 + 2 + 3 + 0 + 265 = **369**, equal to AMI (§3; baseline route counts). Of these, CC-15 routes = 77 (AIR); 7B uses the class counts above and does not recount CC-15.

---

## 22. Consumer Registry

Consumers are listed only where the consumer's own frozen document wires them (AUTH-7B-02). Every consumer must be idempotent on the outbox `event_id` (§27; 6D L1238). None may assume exactly-once delivery.

| CON | Consumer (owner) | Consumes | Purpose | Source |
|---|---|---|---|---|
| CON-01 | Session denylist worker (Identity 6B) | EV-001 | Revoke sessions / access tokens | 6B |
| CON-02 | Compliance default-policy seeding (6C) | EV-002 | Seed default policy | 6C §7.7 |
| CON-03 | Active-policy pointer update (6C) | EV-003 | Update active-policy pointer | 6C |
| CON-04 | CRM call-history handlers (6G) | EV-005, EV-076, EV-078 | Call completion, qualification and summary on the contact | 6G L861–L863 |
| CON-05 | Campaign `RecordCallOutcome` (6H) | EV-005, EV-006, EV-076 | Per-contact attempt outcome | 6H L1293–L1295 |
| CON-06 | Billing usage ingestion (6K) | EV-005, EV-079, EV-081, EV-090, EV-100 | Write `usage_events` | 6K L1909–L1921, L2511; OD-7B-01 |
| CON-07 | Analytics projections (6L) | EV-005, EV-006, EV-026; DS-17 and DS-19 (non-durable) | Hourly call metrics, agent utilisation, lead funnel, token/latency, tool statistics | 6L L457, L772, L790, L794, L795, L797; 6D L1216 |
| CON-08 | Recording-object cleanup (6D) | EV-009 | Delete the stored object | 6D §16.3a |
| CON-09 | Knowledge `document_count` projection (6F) | EV-020, EV-081 | Maintain the count | 6F L293 |
| CON-10 | Webhook engine (6J) | EV-006, EV-021, EV-024, EV-025, EV-035, EV-037, EV-038, EV-046, EV-071, EV-075, EV-084, EV-085, EV-091, EV-102, EV-103, EV-104, EV-105 | Map to WHT-* topics and deliver | 6J L722–L740; 6K §45.1 |
| CON-11 | Campaign import worker (6H) | EV-060 | Process the import | 6H §13.2 |

**Consumed-event union:** EV-001, 002, 003, 005, 006, 009, 020, 021, 024, 025, 026, 035, 037, 038, 046, 060, 071, 075, 076, 078, 079, 081, 084, 085, 090, 091, 100, 102, 103, 104, 105. That is **31** events, equal to the CURRENT_CONSUMED count in §11.

**EV-079 note.** CON-06 is the current consumer of EV-079 by OD-7B-01. 6K's own text still names DS-17 as the source for the AI usage metrics (CNF-16). Until IO-7B-01 and IO-7B-02 land, 7B records the decided consumer role, and the implementation must follow OD-7B-01, not the superseded 6K wording.

**Consumer rules.**

| Rule | Statement |
|---|---|
| CR-01 | A consumer never redefines the name, meaning or payload of an event it consumes (OWN-02). |
| CR-02 | A consumer dedups on `event_id` before any side effect. Business-key dedup (§27) is an additional guard, not a replacement. |
| CR-03 | A consumer re-establishes tenant context from the envelope `organization_id` and checks it against its own stored ownership. The payload `organization_id` alone is never authorization (§39). |
| CR-04 | A consumer must tolerate out-of-order delivery across aggregates. Ordering is guaranteed only as far as 7E defines per stream (IO-7B-08). |
| CR-05 | No consumer may use a Class D or F entry as the source of a billing, compliance or financial fact. |

---

## 23. Ownership Matrices

### 23.1 Per bounded context

| Bounded context | Owned durable events (A/B/C) | Count | Owned Class D | Count |
|---|---|---|---|---|
| Identity (6B) | EV-001 | 1 | — | 0 |
| Organization (6C) | EV-002 | 1 | DS-01…DS-15 | 15 |
| Compliance (6C) | EV-003, EV-098 | 2 | DS-16 | 1 |
| Voice (6D) | EV-004…EV-009, EV-073…EV-079 | 13 | DS-17, DS-18, DS-19 | 3 |
| AI Agent (6E) | EV-010…EV-014 | 5 | — (tool execution is a 6D-owned read-only projection in 6E, 6E L145) | 0 |
| Knowledge (6F) | EV-015…EV-020, EV-080…EV-082 | 9 | — | 0 |
| CRM (6G) | EV-021…EV-051, EV-083 | 32 | — | 0 |
| Campaign (6H) | EV-052…EV-060, EV-084…EV-097 | 23 | — | 0 |
| Workflow (6I) | EV-061…EV-064, EV-099…EV-101 | 7 | — | 0 |
| Integrations (6J) | EV-065…EV-070, EV-072 | 7 | — | 0 |
| Billing (6K) | EV-071, EV-102…EV-105 | 5 | — | 0 |
| Analytics (6L) | — (pure consumer) | 0 | — | 0 |
| **Total** | | **105** | | **19** |

### 23.2 Cross-context flow (producer owner → consumer owner)

| Producer owner | Consumer owner | Events |
|---|---|---|
| Identity | Identity | EV-001 |
| Organization | Compliance | EV-002 |
| Compliance | Compliance | EV-003 |
| Voice | Voice | EV-009 |
| Voice | CRM | EV-005, EV-076, EV-078 |
| Voice | Campaign | EV-005, EV-006, EV-076 |
| Voice | Billing | EV-005, EV-079 |
| Voice | Analytics | EV-005, EV-006; DS-17, DS-19 (non-durable) |
| Voice | Integrations (webhook) | EV-006, EV-075 |
| Knowledge | Knowledge | EV-020, EV-081 |
| Knowledge | Billing | EV-081 |
| CRM | Analytics | EV-026 |
| CRM | Integrations (webhook) | EV-021, EV-024, EV-025, EV-035, EV-037, EV-038, EV-046 |
| Campaign | Campaign | EV-060 |
| Campaign | Billing | EV-090 |
| Campaign | Integrations (webhook) | EV-084, EV-085, EV-091 |
| Workflow | Billing | EV-100 |
| Billing | Integrations (webhook) | EV-071, EV-102, EV-103, EV-104, EV-105 |

**Cycle check.** No two contexts consume each other's events in a loop. Campaign consumes Voice events, and Voice consumes no Campaign event (Campaign starts calls by internal command). Billing, Analytics and the webhook engine are sinks. The event graph is acyclic.

---

## 24. Payload Registry (lineage, not schema)

This registry records the *business meaning* of each event's payload and its lineage. It is not a JSON schema. 7C binds the envelope, field names, types and versions (IO-7B-04, IO-7B-06).

**Marks**

| Mark | Meaning |
|---|---|
| P4 | Fields from the Phase-4 domain-event definition (source line given) |
| PB | No Phase-4 payload. 7C binds the payload from the owner's Phase-6 contract. 7B states only the minimum identifiers. |
| [7I] | Field needs 7I security/PII classification before exposure (IO-7B-07) |
| CRE | Content is referenced by ID only, never embedded |

**Global exclusions (apply to every row).** No access tokens, refresh tokens, provider secrets, API credentials, secret-manager values, signed or presigned URLs, raw media bytes, raw utterance or transcript text, card data or provider raw payloads. Phase-4 field names (`tenant_id`, `doc_id`) are lineage only. The envelope `organization_id` is authoritative for scope (IO-7B-06).

| EV | Event | Lineage | Business payload (indicative) | Marks |
|---|---|---|---|---|
| EV-001 | `identity.forced_revocation_required` | PB | user_id, reason_code | PB; platform-scoped allowed |
| EV-002 | `organization.created` | P4 4A L774 | organization_id, name, slug, plan_tier, owner_user_id | name [7I] |
| EV-003 | `compliance.policy_activated` | PB | policy_id, activated_at | PB |
| EV-004 | `call.initiated` | P4 4B L901 | call_id, direction, from, to, agent_version_id, campaign_lead_ref | from/to [7I] |
| EV-005 | `call.ended` | P4 4B L909 | call_id, ended_at, duration_seconds, outcome | — |
| EV-006 | `call.failed` | P4 4B L910 | call_id, failure_reason, failed_at | — |
| EV-007 | `call.held` | P4 4B L905 | call_id, session_id, held_at | — |
| EV-008 | `call.resumed` | P4 4B L906 | call_id, session_id, resumed_at | — |
| EV-009 | `recording.deleted` | P4 4B L963 | recording_id, deleted_at, deleted_by | CRE (no storage URL) |
| EV-010 | `agent.created` | P4 4B L933 | agent_id, name | — |
| EV-011 | `agent.config_updated` | P4 4B L934 | agent_id, changed_fields | changed_fields: names only [7I] |
| EV-012 | `agent.published` | P4 4B L935 | agent_id, version_id, version_number | — |
| EV-013 | `agent.deprecated` | P4 4B L936 | agent_id | — |
| EV-014 | `tool_definition.*` | PB | tool_id, change kind | PB; no endpoint credentials |
| EV-015 | `knowledge_base.created` | P4 4E L987 | kb_id, name, embedding_model | — |
| EV-016 | `knowledge_base.settings_updated` | PB | kb_id, changed_fields | PB |
| EV-017 | `knowledge_base.archived` | PB | kb_id | PB |
| EV-018 | `knowledge_base.reindex_triggered` | P4 4E L988 | kb_id, triggered_by | — |
| EV-019 | `document.uploaded` | P4 4E L990 | document_id, kb_id, source_type, filename | filename [7I]; no upload URL |
| EV-020 | `document.deleted` | P4 4E L993 | document_id, kb_id, deleted_by | — |
| EV-021 | `contact.created` | P4 4C L852 | contact_id, phone, source, campaign_ref | phone [7I] |
| EV-022 | `contact.updated` | P4 4C L853 | contact_id, changed_fields | field names only [7I] |
| EV-023 | `contact.lead_status_changed` | P4 4C L854 | contact_id, old_status, new_status, changed_by | — |
| EV-024 | `contact.qualified` | P4 4C L855 | contact_id, qualification_reason, qualified_by | reason [7I] |
| EV-025 | `contact.disqualified` | P4 4C L856 | contact_id, qualification_reason, disqualified_by | reason [7I] |
| EV-026 | `contact.converted` | P4 4C L858 | contact_id, converted_at, triggering_deal_id | — |
| EV-027 | `contact.owner_assigned` | P4 4C L861 | contact_id, old_owner, new_owner | — |
| EV-028 | `contact.merged` | P4 4C L859 | primary_id, secondary_id, field_merge_map | map: field names only [7I] |
| EV-029 | `contact.dnc_flagged` | P4 4C L860 | contact_id, flagged_by | — |
| EV-030 | `suppression.added` | PB | suppression_id, contact_id (if any), scope | PB; phone value [7I] |
| EV-031 | `contact.suppression_lifted` | PB | suppression_id, lifted_by | PB |
| EV-032 | `consent.recorded` | PB | consent_id, contact_id, consent_type | PB [7I] |
| EV-033 | `company.created` | PB | company_id | PB |
| EV-034 | `company.updated` | PB | company_id, changed_fields | PB |
| EV-035 | `deal.created` | P4 4C L867 | deal_id, contact_ref, pipeline_id, stage_id, value, currency | deal name [7I] (6J "possibly") |
| EV-036 | `deal.stage_changed` | P4 4C L868 | deal_id, from_stage, to_stage, changed_by | — |
| EV-037 | `deal.won` | P4 4C L869 | deal_id, contact_ref, value, closed_at | — |
| EV-038 | `deal.lost` | P4 4C L870 | deal_id, contact_ref, lost_reason, closed_at | lost_reason [7I] |
| EV-039 | `deal.abandoned` | P4 4C L871 | deal_id, contact_ref, abandoned_at | — |
| EV-040 | `activity.recorded` | P4 4C L877 | activity_id, subject, activity_type, actor_type, occurred_at | subject is a reference, not text |
| EV-041 | `task.created` | P4 4C L878 | task_id, subject, assigned_to, due_at, created_by_type | — |
| EV-042 | `task.completed` | P4 4C L879 | task_id, subject, completed_at | — |
| EV-043 | `task.cancelled` | P4 4C L880 | task_id, subject, cancelled_by | — |
| EV-044 | `note.added` | P4 4C L897 | note_id, subject, author_type, note_source | CRE: note body never embedded |
| EV-045 | `note.deleted` | P4 4C L898 | note_id, subject, deleted_by | — |
| EV-046 | `appointment.booked` | P4 4C L886 | appointment_id, contact_ref, organizer_ref, start, end, source | [7I] (6J "Yes") |
| EV-047 | `appointment.confirmed` | P4 4C L887 | appointment_id, confirmed_at | — |
| EV-048 | `appointment.rescheduled` | P4 4C L891 | appointment_id, old_start, new_start, rescheduled_by | — |
| EV-049 | `appointment.cancelled` | P4 4C L888 | appointment_id, cancellation_reason, cancelled_by | reason [7I] |
| EV-050 | `appointment.completed` | P4 4C L889 | appointment_id, completed_at | — |
| EV-051 | `appointment.no_show` | P4 4C L890 | appointment_id, marked_by | — |
| EV-052 | `campaign.created` | P4 4D L763 | campaign_id, name, agent_id | — |
| EV-053 | `campaign.config_updated` | P4 4D L764 | campaign_id, changed_fields | — |
| EV-054 | `campaign.contact_list_attached` | PB | campaign_id, contact_list_id | PB |
| EV-055 | `campaign.scheduled` | P4 4D L765 | campaign_id, start_at, end_at | — |
| EV-056 | `campaign.paused` | P4 4D L767 | campaign_id, paused_by, paused_at | — |
| EV-057 | `campaign.resumed` | P4 4D L768 | campaign_id, resumed_by, resumed_at | — |
| EV-058 | `campaign.stopping` | P4 4D L769 | campaign_id, initiated_by | — |
| EV-059 | `campaign.cancelled` | P4 4D L771 | campaign_id, cancelled_by, cancelled_at | — |
| EV-060 | `import.job_created` | P4 4D L790 | job_id, campaign_ref, list_ref | No upload URL |
| EV-061 | `workflow.created` | P4 4E L999 | workflow_id, name | — |
| EV-062 | `workflow.draft_updated` | PB | workflow_id, draft revision | PB; no graph body |
| EV-063 | `workflow.published` | P4 4E L1000 | workflow_id, version_id, version_number, published_by | — |
| EV-064 | `workflow.archived` | P4 4E L1001 | workflow_id, archived_by | — |
| EV-065 | `integration.disconnected` | P4 4F L1142 | connection_id, definition_id | No credentials |
| EV-066 | `webhook.endpoint_created` | P4 4F L1148 | webhook_id, topics | No signing secret; URL [7I] if included |
| EV-067 | `plugin.installed` | P4 4F L1157 | installation_id, plugin_id, version_id | — |
| EV-068 | `plugin.activated` | P4 4F L1158 | installation_id, enabled_capabilities | — |
| EV-069 | `plugin.suspended` | P4 4F L1159 | installation_id, reason | — |
| EV-070 | `plugin.uninstalled` | P4 4F L1160 | installation_id | — |
| EV-071 | `subscription.changed` | PB | subscription_id, old_plan, new_plan, status | PB |
| EV-072 | `integration.connected` | P4 4F L1140 | connection_id, definition_id, capabilities | No tokens or secrets |
| EV-073 | `call.answered` | P4 4B L903 | call_id, answered_at | — |
| EV-074 | `call.conversation_started` | P4 4B L904 | call_id, conversation_id | — |
| EV-075 | `call.transferred` | P4 4B L908 | call_id, transfer_confirmed_at | Transfer target number [7I] if added |
| EV-076 | `conversation.qualification_set` | P4 4B L922 | conversation_id, outcome, criteria_matched | criteria_matched [7I] |
| EV-077 | `conversation.sentiment_computed` | P4 4B L926 | conversation_id, sentiment_score | — |
| EV-078 | `conversation.summarization_completed` | P4 4B L927 | conversation_id, summary reference | summary_text [7I-HOLD]: reference-by-ID preferred (CRE) |
| EV-079 | `conversation.completed` | P4 4B L925, extended by OD-7B-01 | conversation_id, call_id, authoritative service-end timestamp (indicative name `completed_at`; the Billing occurrence time, §31.7 — never the worker, reaper, Redis-delivery or outbox-publish time), total_turns, accumulated usage totals (§31.3) | No utterance/transcript text; no call-outcome success assertion (call outcome stays in EV-005 / EV-006); 7C binds names and serialization only (IO-7B-04) |
| EV-080 | `knowledge_base.reindex_completed` | P4 4E L989 | kb_id, new_index_version, document_count | — |
| EV-081 | `document.indexed` | P4 4E L991 | document_id, kb_id, chunk_count, indexed_at, embedding token count | — |
| EV-082 | `document.ingestion_failed` | P4 4E L992 | document_id, kb_id, failure_reason, attempt_count | failure_reason [7I] |
| EV-083 | `contact.score_updated` | P4 4C L857 | contact_id, old_score, new_score, new_temperature, scorer_type, signal_count | — |
| EV-084 | `campaign.started` | P4 4D L766 | campaign_id, agent_version_id, total_contacts | — |
| EV-085 | `campaign.completed` | P4 4D L770 | campaign_id, completed_at, total_contacts, attempted | — |
| EV-086 | `campaign.failed` | P4 4D L772 | campaign_id, failure_reason | — |
| EV-087 | `campaign.contact.enqueued` | P4 4D L778 | campaign_id, contact_id, phone, attempt_number | phone [7I] |
| EV-088 | `campaign.contact.dnc_skipped` | P4 4D L779 | campaign_id, contact_id, phone | phone [7I] |
| EV-089 | `campaign.contact.ineligible` | PB | campaign_id, contact_id, reason_code | PB |
| EV-090 | `campaign.contact.call_attempted` | P4 4D L780 | campaign_id, contact_id, call_id, attempt_number, outcome, attempted_at | — |
| EV-091 | `campaign.contact.qualified` | P4 4D L781 | campaign_id, contact_id, call_id, qualification_reason | reason [7I] |
| EV-092 | `campaign.contact.disqualified` | P4 4D L782 | campaign_id, contact_id, call_id, reason | reason [7I] |
| EV-093 | `campaign.contact.retry_scheduled` | P4 4D L783 | campaign_id, contact_id, next_attempt_at, attempt_count | — |
| EV-094 | `campaign.contact.exhausted` | P4 4D L784 | campaign_id, contact_id, total_attempts | — |
| EV-095 | `import.job_completed` | P4 4D L791 | job_id, total_rows, processed_rows, skipped, dnc_skipped | — |
| EV-096 | `import.job_failed` | P4 4D L792 | job_id, failure_reason, processed_rows | — |
| EV-097 | `campaign.outcome_computed` | P4 4D L798 | campaign_id, qualified, disqualified, answer_rate_pct, roi_pct, total_cost | — |
| EV-098 | `compliance.eligibility_denied` | PB | campaign_id, contact_id, rule_code | PB; Compliance owns the payload |
| EV-099 | `workflow.execution.started` | P4 4E L1002 | execution_id, workflow_version_id, session_ref | — |
| EV-100 | `workflow.execution.completed` | P4 4E L1003 | execution_id, session_ref, total_nodes_visited, exit_node_type, completed_at, LLM token totals | No slot values |
| EV-101 | `workflow.execution.failed` | P4 4E L1004 | execution_id, session_ref, failed_node_id, error | error: code only [7I] |
| EV-102 | `invoice.generated` | P4 4F L1123 | invoice_id, billing_account_id, period, total_due | Financial; no card data |
| EV-103 | `invoice.paid` | PB | invoice_id, paid_at, amount, currency | PB; financial |
| EV-104 | `payment.failed` | PB | payment_attempt_id, invoice_id, failure_code | PB; no card data |
| EV-105 | `usage.threshold_reached` | PB | metric, threshold, period | PB |

Row count = **105**. The indicative fields for EV-079, EV-081, EV-090 and EV-100 include the values 6K needs (`occurred_at` sources and quantities, §26). 7C confirms the exact names.

---

## 25. Migration-075 Analytics Registry Reconciliation

Migration `075_5J.sql` (L9–L35) seeds `analytics.event_schema_versions` with 25 event types, each version `'1'` and status `ACTIVE`. That registry is an analytics schema-registration authority for its own purpose (AUTH-7B-07, NAM-05). A 075 row does not make a name a current event, and a current event does not need a 075 row unless a current Analytics consumer depends on it. 7B does not modify 075.

### 25.1 075 → 7B (every seeded row)

| # | 075 event_type (line) | In 7B catalog | Current producer | Semantic owner | 7B status | Exact name match | Classification / note |
|---|---|---|---|---|---|---|---|
| 1 | `call.ended` (L10) | EV-005 | Yes | Voice | CUR +C | Yes | Matching current event |
| 2 | `call.failed` (L11) | EV-006 | Yes | Voice | CUR +C | Yes | Matching current event |
| 3 | `call.started` (L12) | CCPU-01 | No bus producer | Voice | CURRENT_CONSUMER_PRODUCER_UNWIRED | n/a | Current Analytics consumer (6L L797 `agent_utilization_hourly`) with no bus producer (§32.5). Also a CURRENT webhook topic (WHT-01). Not merged with EV-004 `call.initiated`. Resolution: IO-7B-22. |
| 4 | `conversation.turn_completed` (L13) | DS-17 | Yes (Class D) | Voice | CUR, ANALYTICS_ONLY | Yes | Matching current non-durable signal. Analytics only (OD-7B-01). |
| 5 | `conversation.completed` (L14) | EV-079 | Yes | Voice | CUR +C | Yes | Matching current event. Billing source under OD-7B-01. |
| 6 | `contact.qualified` (L15) | EV-024 | Yes | CRM | CUR +C | Yes | Matching current event |
| 7 | `contact.converted` (L16) | EV-026 | Yes | CRM | CUR +C | Yes | Matching current event |
| 8 | `contact.lead_status_changed` (L17) | EV-023 | Yes | CRM | CUR +N | Yes | Matching current event. No current consumer. |
| 9 | `appointment.booked` (L18) | EV-046 | Yes | CRM | CUR +C | Yes | Matching current event |
| 10 | `campaign.contact.call_attempted` (L19) | EV-090 | Yes | Campaign | CUR +C | Yes | Matching current event |
| 11 | `campaign.contact.qualified` (L20) | EV-091 | Yes | Campaign | CUR +C | Yes | Matching current event |
| 12 | `campaign.completed` (L21) | EV-085 | Yes | Campaign | CUR +C | Yes | Matching current event |
| 13 | `campaign.outcome_computed` (L22) | EV-097 | Yes | Campaign | CUR +N | Yes | Matching current event. CNF-17: `campaign_outcome_summary` has no event wiring. |
| 14 | `usage.event_recorded` (L23) | CCPU-02 | No | Billing | CURRENT_CONSUMER_PRODUCER_UNWIRED | n/a | Current Analytics consumer (6L L792–L793 `usage_cost_daily`) with no Phase-6 producer (CNF-12; §32.5). A present gap, not a future feature. Resolution: IO-7B-23. |
| 15 | `invoice.payment_succeeded` (L24) | FUT-04 | No | Billing | FUTURE_DEFINED | No (current form is `invoice.paid`, EV-103) | Stale or alternate naming. No rename (NAM-01). CNF-19. |
| 16 | `invoice.generated` (L25) | EV-102 | Yes | Billing | CUR +C | Yes | Matching current event (NAM-F-06) |
| 17 | `tool_execution.succeeded` (L26) | DS-19 / RTM-24 | Yes (Class D) | Voice | CUR, CURRENT_CONSUMED (FAM-03) | Yes | Matching current non-durable signal (6D L1234, L1698). Analytics tool projection (6L L457, L772). Not a Billing source; the Billing `TOOL_EXECUTIONS` producer is UNW-01 (DEP-6K-01). |
| 18 | `tool_execution.failed` (L27) | DS-19 / RTM-25 | Yes (Class D) | Voice | CUR, CURRENT_CONSUMED (FAM-03) | Yes | As row 17 (6D L1699) |
| 19 | `webhook.delivery_succeeded` (L28) | FUT-05 | No | Integrations (6J) | FUTURE_DEFINED | n/a | 6J L1919 lists it as an internal delivery meta-event, not webhook-eligible (4F §12.4). No outbox write is specified. |
| 20 | `webhook.delivery_failed` (L29) | FUT-06 | No | Integrations (6J) | FUTURE_DEFINED | n/a | As row 19 |
| 21 | `webhook.delivery_dead_lettered` (L30) | FUT-07 | No | Integrations (6J) | FUTURE_DEFINED | n/a | As row 19 |
| 22 | `provider.failed` (L31) | FUT-08 | No | Voice | FUTURE_DEFINED | n/a | Analytics-only vocabulary. Provider failover is in-process (6D L704). |
| 23 | `provider.failover_triggered` (L32) | DS-18 | Yes (Class D) | Voice | CUR +N | Yes | Matching current non-durable signal ("internal only", 6D L1216) |
| 24 | `provider.circuit_opened` (L33) | FUT-09 | No | Voice | FUTURE_DEFINED | n/a | Analytics-only vocabulary |
| 25 | `provider.circuit_closed` (L34) | FUT-10 | No | Voice | FUTURE_DEFINED | n/a | Analytics-only vocabulary |

**075 totals.**

| Classification | Count |
|---|---:|
| Matching current durable event | 12 |
| Matching current Class D signal (rows 4, 17, 18, 23: DS-17, DS-19 ×2, DS-18) | 4 |
| Current consumer, producer unwired (rows 3, 14: CCPU-01, CCPU-02) | 2 |
| Future-defined (FUT-04…FUT-10) | 7 |
| Unwired family members | 0 |
| **Total** | **25** |

12 + 4 + 2 + 7 + 0 = **25**, equal to the 075 seed. FUT-01 and FUT-03 are retired (§32.2); their names are now CCPU-01 and CCPU-02.

### 25.2 7B → 075 (current events with a current Analytics consumer)

| 7B entry | Current Analytics consumer | In 075 | Registration required now |
|---|---|---|---|
| EV-005 `call.ended` | 6L L790 | Yes | Already registered |
| EV-006 `call.failed` | 6L L790 | Yes | Already registered |
| EV-026 `contact.converted` | 6L L795 | Yes | Already registered |
| DS-17 `conversation.turn_completed` | 6L L794 / 6D L1216 | Yes | Already registered |
| DS-19 `tool_execution.*` | 6L L457, L772 | `.succeeded`, `.failed` yes (rows 17–18); `.started` no | No change now. 6L names the family only. If 7C / 6L bind `.started` as a consumed member, it is registered by a governed 075 amendment (IO-7B-11). |
| CCPU-01 `call.started` | 6L L797 | Yes (row 3) | Registered, but no producer exists (§32.5; IO-7B-22) |
| CCPU-02 `usage.event_recorded` | 6L L792–L793 | Yes (row 14) | Registered, but no producer exists (§32.5; IO-7B-23) |

**Correction (P1-7B-05).** An earlier revision said every current Analytics event has a current producer. That is false. Two names that current 6L projections consume, `call.started` and `usage.event_recorded`, have no current producer. A 075 row is vocabulary: it registers a name for Analytics, and it does not prove that anything produces that name. The two gaps are recorded as CCPU-01 and CCPU-02 (§32.5), with the controlled reconciliations IO-7B-22 and IO-7B-23 (P1-7B-05R).

Every current event with a current Analytics consumer is already in 075, so there is no missing registry coverage for produced events. Events that list Analytics only as a *future* consumer (§12–§14 last column) do not need registration now. When 6L wires such a consumer, the 075 row is added by a governed Phase-5 amendment (IO-7B-11).

---

## 26. Billing Usage Producer Reconciliation

Source: 6K §21.1 (L1909–L1923), §22 identity (L1965–L1971) and usage consumer (L2511). `source_event_id` is the outbox event `id` for a single-metric event, and `<outbox_event_id>:<metric>` for a multi-metric event. Uniqueness is enforced by `uq_ue_idempotency` (5H `102_5H2` remediation, 6K L1963).

| Metric | 6K line | 6K producer (current text) | 7B source after OD-7B-01 | 7B entry | Identity | Status |
|---|---|---|---|---|---|---|
| `CALL_MINUTES` | L1911 | `call.ended` | Unchanged | EV-005 | outbox `id` | Current |
| `AI_MINUTES` | L1912 | `conversation.turn_completed` | `conversation.completed` | EV-079 | `<outbox_event_id>:AI_MINUTES` | Remap (IO-7B-02) |
| `STT_SECONDS` | L1913 | `conversation.turn_completed` | `conversation.completed` | EV-079 | `<outbox_event_id>:STT_SECONDS` | Remap (IO-7B-02) |
| `TTS_CHARACTERS` | L1914 | `conversation.turn_completed` | `conversation.completed` | EV-079 | `<outbox_event_id>:TTS_CHARACTERS` | Remap (IO-7B-02) |
| `LLM_PROMPT_TOKENS` | L1915 | `conversation.turn_completed`; `workflow.execution.completed` | Voice: `conversation.completed`; non-voice: unchanged | EV-079; EV-100 | `<outbox_event_id>:LLM_PROMPT_TOKENS` | Voice remap (IO-7B-02); workflow current |
| `LLM_COMPLETION_TOKENS` | L1916 | Same as above | Same as above | EV-079; EV-100 | `<outbox_event_id>:LLM_COMPLETION_TOKENS` | As above |
| `EMBEDDING_TOKENS` | L1917 | `document.indexed` | Unchanged | EV-081 | outbox `id` | Current |
| `CAMPAIGN_CALLS` | L1918 | `campaign.contact.call_attempted` | Unchanged | EV-090 | outbox `id` | Current |
| `WORKFLOW_EXECUTIONS` | L1919 | `workflow.execution.completed` | Unchanged | EV-100 | `<outbox_event_id>:<metric>` | Current |
| `TOOL_EXECUTIONS` | L1920 | Producer not built | — | UNW-01 | — | UNWIRED (DEP-6K-01). DS-19 is a current Analytics-only signal and is **not** this metric's source. |
| `KNOWLEDGE_RETRIEVALS` | L1921 | Producer not built | — | UNW-02 | — | UNWIRED (DEP-6K-02) |
| `STORAGE_GB` | L1922 | Periodic snapshot | Not an event | TSK-12 | Task-defined | Periodic (Class E) |
| `API_REQUESTS` | L1923 | Periodic aggregation | Not an event | TSK-13 | Task-defined | Periodic (Class E) |

**Result.** Every event-sourced metric has exactly one durable producer, except the two UNWIRED metrics that 6K already records as forward dependencies. No metric is sourced from a Class D or F entry after OD-7B-01. For the five voice metrics moved to EV-079, the durable producer is the single atomic accounting finalization (§31.2, OD-7B-02), run by the Voice-owned post-call / accounting-finalization worker or, on recovery, the Voice stale-conversation reaper / recovery worker (PRD-27, §31.6). The Billing occurrence time of those metrics is the authoritative service-end time (§31.7). EV-079 can only carry totals that were durably accumulated before finalization (§26.1). `CALL_MINUTES` (from EV-005) and `AI_MINUTES` (from EV-079) are different metrics from different events, so they cannot double-charge each other. The `CAMPAIGN_CALLS` and `CALL_MINUTES` overlap is governed by 6K §13.4 and is not changed by 7B.

### 26.1 Durable per-turn accumulation obligation (P1-7B-02)

EV-079 carries accumulated totals (§31.3). Those totals are only as safe as the durable state they are read from. A total held only in process memory or in Redis is lost on a worker crash, a Redis loss or a restart, and a stale-conversation reaper / recovery worker that finalizes the conversation later would then report too little. 7B therefore records the following obligation. It does not create the storage.

**Metric semantics** (units from 6K L1911–L1916; no pricing is implied):

| Metric | Unit (6K) | Meaning accumulated per conversation |
|---|---|---|
| `AI_MINUTES` | minutes | Duration of conversation time handled by the AI agent, up to the last durably checkpointed turn. 6K marks it informational in V1 (L1912). |
| `STT_SECONDS` | seconds | Seconds of caller audio processed by the STT provider. This is audio duration, not STT latency. |
| `TTS_CHARACTERS` | characters | Characters of agent response submitted to the TTS provider for synthesis |
| `LLM_PROMPT_TOKENS` | tokens | Prompt tokens reported by the LLM provider for the conversation's turns |
| `LLM_COMPLETION_TOKENS` | tokens | Completion tokens reported by the LLM provider for the conversation's turns |

**Current durable state (5C `012_5C.sql`; AUTH-C-04).** The conversation record holds prompt, completion and total token counters and a turn counter. It holds no durable accumulator for STT audio seconds, TTS characters or AI minutes. The turn record holds latency measures, including STT latency, which is not STT audio duration. It holds no per-turn token or TTS-character figure. **The current schema does not hold all five metrics.** The conversation start and completion times exist, but the completion time is set only at finalization, so it cannot recover AI minutes after a crash without a checkpointed figure.

| ACC | Obligation | Owner |
|---|---|---|
| ACC-01 | All five metrics are accumulated durably, per conversation, in the same database transaction that checkpoints the completed turn (the per-turn checkpoint transaction). | 6D runtime; physical form by a governed Phase-5 migration (IO-7B-15) |
| ACC-02 | The accumulation is off the provider critical path. It never waits on Billing, never writes `usage_events` and never writes an outbox row per turn (INV-04). | 6D runtime |
| ACC-03 | The accumulated totals survive a worker crash, Redis loss and a process restart. Redis or memory may cache them but is never their record. | 6D runtime; 7K |
| ACC-04 | Finalization (§31.2) reads only these durable totals. It never re-derives usage from Class D signals, WS messages or provider logs. | 6D runtime |
| ACC-05 | Provider and model attribution for each metric is recorded as reference identifiers only. Provider pricing, contract rates and procurement cost are never recorded in the accumulator, in EV-079 or in any Class D payload (6L L792 keeps cost platform-internal). | 6D runtime; 7C; 7I |
| ACC-06 | Column names, types and the migration number are **not** chosen by 7B. They are decided by the governed migration that fulfils IO-7B-15. | Phase-5 amendment |

The existing token counters may serve ACC-01 for the two LLM metrics only if the runtime updates them inside the per-turn checkpoint transaction. That is confirmed or amended through IO-7B-17 (6D amendment); 7B does not assume it.

---

## 27. Event Identity and Deduplication

| ID | Rule |
|---|---|
| IDN-01 | The canonical identity of a durable event is the `audit.domain_event_outbox.id` (UUIDv7, 077_5J1) assigned in the producer's transaction. It becomes the envelope `event_id` (IO-7B-06). |
| IDN-02 | Phase-4 idempotency keys (4G L546–L609) are lineage and business-key guidance only. They are not the event identity. |
| IDN-03 | Provider event IDs (PCB-01…03) are inbound dedup keys for the callback record only (Rule H-1). They are never the canonical `event_id`. |
| IDN-04 | Class D and F entries have no outbox id and therefore no durable identity. No consumer may derive a durable key from them (DS-17 rule). |
| IDN-05 | Billing identity is `source_event_id` = outbox `id` (single metric) or `<outbox_event_id>:<metric>` (multi-metric), unique under `uq_ue_idempotency` (6K L1963–L1971). EV-079 is multi-metric. |
| IDN-06 | Delivery is at-least-once (outbox relay, max_attempts 10, 077_5J1). Consumers dedup on `event_id` (CR-02). **7B makes no exactly-once claim.** |
| IDN-07 | A task that is triggered by an event carries the triggering `event_id` only for correlation (Rule E-1). |
| IDN-08 | When one fact can arrive by two producer paths (EV-005 / EV-006 from 6D-004 or from the provider worker), the state-machine guard makes the transition happen once. Only the transaction that performs the transition writes the outbox row. |
| IDN-09 | Business-key dedup (for example `call_id` + terminal state, `conversation_id` for EV-079) is an additional consumer guard. 7F / 7G own its implementation (IO-7B-09). |
| IDN-10 | **EV-079 identity.** Aggregate identity is `conversation_id`. There is one logical accounting finalization per conversation finalization generation. Transport identity is the outbox UUID (IDN-01). Billing identity is `<outbox_event_id>:<metric>` (IDN-05). The logical invariant: for one conversation accounting-finalization generation, at most one canonical `conversation.completed` Billing event may be committed. |
| IDN-11 | **Finalization guard.** A durable, conversation-level guard records that the conversation's accounting is finalized. It is claimed in the same transaction that writes the EV-079 outbox row. Both protections are required: `<outbox_event_id>:<metric>` stops a redelivered event from being ingested twice, and the guard stops a second logical EV-079 (with a new outbox id) from being written at all. The outbox id alone does not prevent a duplicate logical event. The physical constraint is a future migration obligation (IO-7B-16). |

---

## 28. Event Families (FAM-*)

| FAM | Family | Linked entry | Class | Members named by a frozen source | Count rule |
|---|---|---|---|---|---|
| FAM-01 | `tool_definition.*` | EV-014 | A | AIR names the family for 6E-011 / 6E-013 / 6E-014. No member name is catalogued in 6E. | Counts once (EV-014) |
| FAM-02 | `data_subject_request.*` | DS-16 | D | AIR: "family only; member name not catalogued" | Counts once (DS-16) |
| FAM-03 | `tool_execution.*` | DS-19 | D (current) | `tool_execution.started` / `.succeeded` / `.failed` are named by 6D (L1234 internal Redis Streams; L1697–L1699 WS forms, RTM-23…25). `.succeeded` / `.failed` are also 075 rows. | Counts once (DS-19) |

7B fabricates no family member (NAM-06). If a member is later needed for routing, the owning context names it by amendment and 7C binds its payload. Individually named `member.*` and `team.*` signals (DS-04…DS-15) are separate entries, not a family.

---

## 29. FOD-7B-01 Evidence

FOD-7B-01 (7A §38 L949; 7A §37 L912–L926; VOX-04 L735; BIL-08 L753) asks how turn-level usage reaches Billing durably.

| E | Source | Evidence |
|---|---|---|
| E-01 | 6D L1216 | `conversation.turn_completed` is published directly to Redis Streams after the `voice.turns` INSERT commits. Its consumer is Analytics (token usage and latency). |
| E-02 | 6D L1234 | The per-turn signal is not an outbox event |
| E-03 | 7A DEL-05 L478 | Class D is best-effort and must not carry an invariant-bearing fact |
| E-04 | 6K L1912–L1916 | 6K names `conversation.turn_completed` as the producer of AI_MINUTES, STT_SECONDS, TTS_CHARACTERS and LLM_* |
| E-05 | 6K L1968 | 6K identity is `<outbox_event_id>:<metric>`, which needs an outbox id |
| E-06 | 6K L2511 | The usage ingestion consumer reads "Redis Streams (outbox-published)" |
| E-07 | 4B L925; 075 L14 | `conversation.completed` already exists as a governed name and an analytics registration |

**Conflict.** E-04 to E-06 need an outbox id and durable delivery. E-01 to E-03 show that the signal has neither. Billing-grade usage would therefore depend on a lossy signal, and its idempotency key could not be formed (CNF-16).

| Option | Description | Assessment |
|---|---|---|
| A | Promote `conversation.turn_completed` to an outbox event per turn | Rejected. It creates a per-turn outbox flood, puts outbox writes on the realtime hot path, and conflicts with 6D's Class D design. |
| B | Keep Class D as the Billing source | Rejected. It is lossy (DEL-05) and has no outbox id, so the 6K identity cannot exist. |
| **C** | Keep the turn signal as Class D (Analytics only), and emit one durable `conversation.completed` carrying the accumulated usage | **Chosen by the owner (OD-7B-01).** |

---

## 30. Owner Decision OD-7B-01

**Decision (owner-approved, final):** Option C.

| Part | Decision |
|---|---|
| D-1 | `conversation.turn_completed` stays Class D (DS-17): direct Redis Stream, non-durable, ANALYTICS_ONLY. It is not billing-authoritative and is never assigned an outbox id. |
| D-2 | `conversation.completed` / EV-079 (Class C) is emitted exactly once, as a durable outbox event, at authoritative conversation accounting finalization. The finalization may be reached through the normal post-call path or the stale/crash recovery path. The event does NOT assert that the Voice call outcome was successful (call outcome stays in EV-005 / EV-006). It carries or references the accumulated usage for that conversation. **Clarified by OD-7B-02 (§31.5) and P1-7B-08…10 (§31.6, §31.7):** both paths run through one atomic accounting finalization, executed by a Voice-owned worker (PRD-27), with the authoritative service-end time as the Billing occurrence time. "Exactly once" here means one logical committed event per finalization generation (IDN-10); delivery stays at-least-once (IDN-06). EV-079 records accounting finalization, not call success. |
| D-3 | Billing derives AI_MINUTES, STT_SECONDS, TTS_CHARACTERS and voice LLM_* usage from EV-079, with `source_event_id = <outbox_event_id>:<metric>`. Ingestion is idempotent under `uq_ue_idempotency`. |
| D-4 | No new event name and no migration are created. `conversation.completed` is an existing governed name (4B L925; 075 L14). |
| D-5 | 6D, 6K and 7A are not modified by 7B. The required text changes are recorded as IO-7B-01 (6D), IO-7B-02 (6K), IO-7B-03 (DS-17 wording), IO-7B-13 (AIR) and IO-7B-14 (6D L1230). |

**Invariants (binding on 7C–7L).**

| INV | Invariant | How OD-7B-01 satisfies it |
|---|---|---|
| INV-01 | No loss of billable usage | Usage is accumulated durably in each per-turn checkpoint transaction (§26.1, ACC-01…ACC-03). It is carried by a durable outbox event written in the finalization transaction. A conversation that does not complete normally is finalized by the Voice stale-conversation reaper / recovery worker through the same operation and the same EV-079 (§31.2, §31.6, OD-7B-02; IO-7B-05). |
| INV-02 | No double charge | The durable finalization guard (IDN-11) allows at most one committed logical EV-079 per conversation finalization generation (IDN-10), and `<outbox_event_id>:<metric>` is unique (IDN-05). Both are required. IDN-08 covers call-state transitions (EV-005 / EV-006), not EV-079. |
| INV-03 | No per-turn outbox flood | Turns stay Class D. There is one outbox row per conversation. |
| INV-04 | No hot-path blocking | No outbox write happens per turn. The per-turn usage checkpoint is off the provider critical path (ACC-02). The single outbox write is at the accounting-finalization boundary. |
| INV-05 | No exactly-once claim | Delivery is at-least-once plus idempotent consumers (IDN-06) |

---

## 31. `conversation.completed` Contract (EV-079)

### 31.1 Emission

| Aspect | Contract |
|---|---|
| Semantic owner | Voice / Conversation (6D). Billing is a consumer only. Transport owner: event infrastructure (outbox relay, 7D; Redis Streams, 7E). |
| Producer (PRD-27) | The Voice-owned **post-call / accounting-finalization worker** on the normal path, and the Voice-owned **stale-conversation reaper / recovery worker** on the recovery path. Both invoke the same atomic accounting finalization (§31.2, §31.6, OD-7B-02). The live conversation runtime persists and checkpoints accounting state but does not emit EV-079 (P1-7B-09). |
| Class | C (worker-emitted, outbox; 7A Class C) |
| Boundary | Authoritative conversation accounting finalization (OD-7B-01 D-2 as clarified by OD-7B-02). The worker transaction that claims the finalization guard and finalizes the accumulated usage also writes the outbox row. EV-079 is emitted exactly once at that finalization, whether reached through the normal post-call path or the stale/crash recovery path. It does NOT assert that the Voice call outcome was successful. |
| Billing occurrence time | The authoritative service-end time of the conversation (§31.7). Never the worker, reaper, Redis-delivery or outbox-publish time. |
| Cardinality | Exactly one logical committed event per conversation finalization generation (IDN-10). Never per turn. Delivery is at-least-once (IDN-06); consumers dedup. |
| Aggregate | `conversation` (`aggregate_id` = conversation_id) |
| Scope | Organization-scoped. `organization_id` comes from the owning conversation row, never from the client. |

### 31.2 Single finalization path (normal and recovery)

A conversation can end normally, or it can stop without a normal end: a worker crash, an abandoned session, or a provider failure that ends the call through EV-006. Usage from committed turns in such a conversation must not be lost. Both cases use **one** finalization operation (OD-7B-02):

| Step | Finalization transaction (one database transaction) |
|---|---|
| FIN-1 | Claim the conversation's durable finalization guard (IDN-11), only if it is not already finalized |
| FIN-2 | Finalize the accumulated usage from the durable per-turn totals (§26.1, ACC-04) |
| FIN-3 | Insert exactly one EV-079 outbox row |
| FIN-4 | Commit |

If the guard is already claimed, the operation is a no-op: it writes nothing and emits nothing. The operation is durable, concurrency-safe (two invocations racing on one conversation produce one committed EV-079) and independent of Redis.

| Path | Caller | Result |
|---|---|---|
| Normal | Post-call / accounting-finalization worker (Voice-owned; PRD-27) | Invokes the finalization operation after the live conversation runtime has persisted and checkpointed the conversation's accounting state |
| Recovery | Voice stale-conversation reaper / recovery worker (Voice-owned; PRD-27; scheduling and detection by 7K), for a conversation that stopped without normal finalization | Invokes **the same** finalization operation; EV-079 is emitted only if the conversation is not already finalized. It never writes `usage_events`, never emits a different event, never fabricates an identity and never creates a second Billing path. |

**Corrupt durable state.** If the durable usage state of a conversation, or its authoritative service-end time (§31.7), is missing or inconsistent, recovery synthesizes no charges and no occurrence time. The conversation is routed to reconciliation and alerting (7K / 7J, 7L); Billing receives nothing for it until that is resolved.

7K owns the stale-conversation reaper / recovery worker's detection, schedule and alerting; 7L owns reconciliation (IO-7B-05, IO-7B-18). 7B does not claim the post-call / accounting-finalization worker or the recovery worker exists in V1 today; both are architectural roles whose implementation is routed through IO-7B-17 (6D amendment) and IO-7B-05 (7K).

### 31.3 Usage content (business meaning only; 7C binds names)

| Content | Meaning | Billing metric |
|---|---|---|
| AI duration total | Total AI-handled conversation time | AI_MINUTES |
| STT total | Sum of speech-to-text seconds over committed turns | STT_SECONDS |
| TTS total | Sum of synthesized characters over committed turns | TTS_CHARACTERS |
| LLM prompt total | Sum of prompt tokens over committed turns | LLM_PROMPT_TOKENS |
| LLM completion total | Sum of completion tokens over committed turns | LLM_COMPLETION_TOKENS |
| Service-end time (indicative name `completed_at`) | The authoritative time at which the conversation's metered service ended and became attributable for billing (§31.7); the `occurred_at` source for Billing. Not a call-success signal and not the finalization processing time. | — |
| Provider attribution | Provider and model references for each metric (reference IDs only; no pricing or procurement cost, ACC-05) | — |

The totals must be reproducible from committed conversation state, so that a retry or reconciliation produces the same numbers. The event carries no utterance or transcript text, no provider credentials and no raw provider payload. A reference-by-ID form (usage stored and referenced) is permitted if 7C chooses it (IO-7B-04).

### 31.4 Consumers

| Consumer | Use |
|---|---|
| Billing usage ingestion (CON-06) | Up to five `usage_events` rows per conversation, one per metric, keyed `<outbox_event_id>:<metric>` |
| Analytics | Future consumer only. Current Analytics usage stays on DS-17. |
| WS clients | RTM-22 is a separate Class F message. It is not the Billing source. |

### 31.5 Owner Decision OD-7B-02 — single-path accounting finalization

| Aspect | Record |
|---|---|
| Issue | Independent review found that §31.2 allowed recovery to "emit or reconcile" usage by an unstated path. That left two possible Billing paths and no stated duplicate guard. |
| Ambiguity | Whether a conversation that stops without normal completion is billed through EV-079 or through a separate recovery mechanism |
| Rejected A | The stale-conversation reaper / recovery worker reconciles directly with Billing (writes `usage_events` itself). Rejected: it is a second Billing path that bypasses the outbox, the envelope and the idempotency identity. |
| Rejected B | The stale-conversation reaper / recovery worker emits a different recovery event. Rejected: it creates a second producer contract for the same fact, and Billing would need two ingestion rules. |
| **Selected C** | The normal post-call / accounting-finalization worker and the stale-conversation reaper / recovery worker both invoke the same atomic finalization (FIN-1…FIN-4) and produce the same EV-079 (PRD-27, §31.6). |
| Decision | **RESOLVED (owner-approved remediation directive, final).** |
| Consequences | Durable five-metric accumulator migration obligation (IO-7B-15); durable finalization guard (IDN-11; IO-7B-16); 6D amendment (IO-7B-17); 7K stale-conversation reaper / recovery worker (IO-7B-05); 7F / 7G idempotent Billing ingestion (IO-7B-09); 7C envelope and fields (IO-7B-04); 7J observability of stalled and corrupt conversations (IO-7B-21); 7L reconciliation (IO-7B-18); worker-emitted Class-C producer roles (P1-7B-09, §31.6); service-end Billing occurrence time (P1-7B-10, §31.7) |
| Scope | Narrow. It governs only how a conversation's accounting is finalized and which event carries it. It does not change OD-7B-01 D-1, D-3 or D-4, any EV name or class, or any other producer. |

### 31.6 Trigger semantics and producer roles (P1-7B-08, P1-7B-09)

**Canonical meaning.** `conversation.completed` / EV-079 is emitted exactly once at authoritative conversation accounting finalization. The finalization may be reached through the normal post-call path or the stale/crash recovery path. The event does NOT assert that the Voice call outcome was successful. The call outcome (ended, failed, abandoned) stays in `call.ended` (EV-005) and `call.failed` (EV-006). This does not reopen OD-7B-01 or OD-7B-02; it states their boundary precisely.

**Trigger chain (deterministic).**

| Step | Condition / action |
|---|---|
| TRG-01 | Authoritative conversation accounting state exists: the durable per-turn usage totals (§26.1, ACC-01…ACC-03) and the authoritative service-end time (§31.7), persisted by the live conversation runtime and the call lifecycle |
| TRG-02 | The conversation is not yet finalized (its durable finalization guard, IDN-11, is unclaimed) |
| TRG-03 | Either the **normal finalizer** (post-call / accounting-finalization worker) or the **recovery finalizer** (Voice stale-conversation reaper / recovery worker) invokes the finalization operation |
| TRG-04 | Atomic accounting finalization (FIN-1…FIN-4, §31.2) in one worker database transaction |
| TRG-05 | Exactly one `conversation.completed` outbox row is committed for that finalization generation (IDN-10) |

For any conversation the outcome is determined by the durable state alone: if TRG-02 is false, nothing is emitted; if TRG-01 is not satisfied (missing or corrupt state), nothing is emitted and the conversation goes to reconciliation (§31.2, §31.7); otherwise exactly one committed EV-079 results, whichever finalizer wins the guard. The call outcome, the path taken and the time at which the worker runs do not change the event's meaning.

**What EV-079 asserts and does not assert.**

| EV-079 asserts | EV-079 does not assert |
|---|---|
| The conversation's accounting is finalized for this finalization generation | That the call was successful, answered, completed normally or reached a business outcome |
| The carried usage totals are the durably accumulated totals at finalization | That every turn a caller experienced was durably checkpointed (only committed turns count, §26.1) |
| The Billing occurrence time is the authoritative service-end time (§31.7) | Any processing time (worker, reaper, relay, Redis delivery) |

**Producer roles (Class C is worker-emitted, 7A).**

| Role | Owner | Responsibility for EV-079 |
|---|---|---|
| Live conversation runtime (6D) | Voice / Conversation | Persists and checkpoints conversation accounting state per turn (ACC-01…ACC-03). Does **not** write the EV-079 outbox row. |
| Post-call / accounting-finalization worker (normal path) | Voice / Conversation | Invokes the atomic accounting finalization after the conversation ends; writes the single EV-079 outbox row inside that worker transaction |
| Voice stale-conversation reaper / recovery worker (recovery path) | Voice / Conversation (detection, schedule and alerting specified by 7K, IO-7B-05) | Invokes the same atomic accounting finalization for a conversation that stopped without normal finalization; EV-079 is emitted only if the conversation is not already finalized |
| Event infrastructure (outbox relay, Redis Streams) | Transport owner (7D relay; 7E streams) | Relays the committed outbox row; does not create, alter or time-stamp the business fact |
| Billing usage ingestion (CON-06) | Billing | Consumer only. Never produces EV-079 and never finalizes a conversation. |

These are architectural roles. 7B names no function, module, class or Celery queue for them; the 6D amendment (IO-7B-17) and 7K (IO-7B-05) specify their implementation.

### 31.7 Billing occurrence time (P1-7B-10)

| OCC | Rule |
|---|---|
| OCC-01 | The Billing occurrence time of EV-079 is the authoritative time at which the conversation's metered service ended / became attributable for billing, not the time at which a delayed worker or recovery reaper happens to process the finalization. It is the `occurred_at` source for every `usage_events` row Billing derives from EV-079. |
| OCC-02 | Normal path: the persisted conversation completion / service-end timestamp recorded in the authoritative conversation state. |
| OCC-03 | Recovery path: the recovery worker reuses the authoritative persisted service-end timestamp from trusted conversation / call lifecycle state. It does not compute a new one. |
| OCC-04 | Never used as the occurrence time: the reaper's current time (`now()`), the worker execution time, the Redis delivery time or the outbox publish / relay time. |
| OCC-05 | If the authoritative service-end timestamp is missing or corrupt: do not invent one, do not default to the recovery time and do not synthesize usage. The conversation is routed to corrupt / incomplete-state reconciliation (7K recovery, 7J observability and operations, 7L final reconciliation). Billing receives nothing for it until that is resolved. |
| OCC-06 | The occurrence time is part of the committed finalization state, so a retry, a duplicate delivery or a reconciliation re-read yields the same value (deterministic Billing-period attribution). Late-usage handling after a Billing period closes stays governed by 6K; 7B does not change it. |
| OCC-07 | 7C defines only the field name and serialization of the occurrence time (IO-7B-04). The business meaning above is fixed by 7B and 7C may not redefine it. |

---

## 32. Current, Future, Unwired and Superseded Register

### 32.1 Counts

| Register | Count |
|---|---:|
| Durable events CURRENT_PRODUCED (EV-001…EV-105) | 105 |
| — CURRENT_CONSUMED | 31 |
| — CURRENT_NO_CONSUMER | 74 |
| Class D current (DS-01…DS-19) | 19 |
| — consumed (DS-17, DS-19; Analytics) | 2 |
| — no consumer | 17 |
| Class D UNWIRED | 0 |
| CURRENT_CONSUMER_PRODUCER_UNWIRED (CCPU-01, CCPU-02) | 2 |
| FUTURE_DEFINED names (FUT-02, FUT-04…FUT-10) | 8 |
| UNWIRED (UNW-01, UNW-02) | 2 |
| FAMILY (FAM-01…FAM-03) | 3 |
| SUPERSEDED | 0 |

Check: 31 + 74 = 105. 2 + 17 = 19 Class D entries, all current (P1-7B-07). SUPERSEDED is 0 because no frozen source retires a name. Alternate Phase-4 forms are recorded as lineage (§10.1), not as superseded entries.

### 32.2 Future-defined names

| FUT | Name | Source | Future owner | Note |
|---|---|---|---|---|
| FUT-02 | `conversation.started` | 4B L919 | Voice | Current fact is EV-074 `call.conversation_started`. The WS form is RTM-16 (NAM-F-08). |
| FUT-04 | `invoice.payment_succeeded` | 075 L24 | Billing | Current Billing form is `invoice.paid` (EV-103). CNF-19. |
| FUT-05 | `webhook.delivery_succeeded` | 075 L28; 6J L1919 | Integrations | Delivery meta-event. Not webhook-eligible. |
| FUT-06 | `webhook.delivery_failed` | 075 L29; 6J L1919 | Integrations | As FUT-05 |
| FUT-07 | `webhook.delivery_dead_lettered` | 075 L30; 6J L1919 | Integrations | As FUT-05 |
| FUT-08 | `provider.failed` | 075 L31 | Voice | Failover is in-process (6D L704) |
| FUT-09 | `provider.circuit_opened` | 075 L33 | Voice | As FUT-08 |
| FUT-10 | `provider.circuit_closed` | 075 L34 | Voice | As FUT-08 |

FUT-01 (`call.started`) and FUT-03 (`usage.event_recorded`) are **retired** by P1-7B-05. Both names have a current consumer in 6L, so FUTURE_DEFINED understated them. They are now CCPU-01 and CCPU-02 (§32.5). The FUT-01 and FUT-03 identifiers are not reused.

### 32.3 Unwired

| UNW | Item | Source | Status |
|---|---|---|---|
| UNW-01 | Billing `TOOL_EXECUTIONS` usage producer (6K metric). It is **not** DS-19: `tool_execution.*` is a current Class D signal (P1-7B-07). | 6K L1920, L2864; DEP-6K-01 | UNWIRED until a 6E / 6I / 6K amendment |
| UNW-02 | `KNOWLEDGE_RETRIEVALS` usage producer (no event name exists; 7B creates none) | 6K L1921, DEP-6K-02 | UNWIRED until a 6F/6E amendment |

### 32.4 Names that are neither current bus events nor future bus events

| Name | Source | Disposition |
|---|---|---|
| `transcript.segment_added` | 4B §11.7; 6D L1234 | "Not published to event bus". Not Class D. |
| `call.terminated` | 6D L1214 | Wording for the terminate outcome. It resolves to EV-005 / EV-006 (NAM-F-09, CNF-03). |
| `call.completed` | 6J L723 | CURRENT governed webhook topic (WHT-02). It is not an internal bus event name. Its internal source mapping is pending 7H (IO-7B-12); the candidate EV-005 `call.ended` is not merged with it (NAM-F-03). |
| `agent.*`, `workflow.execution.*`, `document.*` / `knowledge_base.*` as webhook topics | 6J L1923 (DEC-6J-04) | Forward decision for webhook exposure. The internal events exist (§11), but 7B invents no topic. |
| `workflow_execution.node_entered` / `.node_exited` / `.slot_updated` | 6I L894 | Class F only. Never durable. |

### 32.5 Current consumer, producer unwired (CCPU)

A CCPU name is one that a frozen current consumer already reads, but that no current producer emits under that name. It is neither FUTURE_DEFINED (the consumer is current) nor CURRENT_PRODUCED (there is no producer). 7B invents no producer for either.

| CCPU | Name | Current consumer | Producer state | Resolution owner | Note |
|---|---|---|---|---|---|
| CCPU-01 | `call.started` | 6L L797: `agent_utilization_hourly` reads `call.started` / `call.ended` | No bus producer under this name. The webhook topic `call.started` is CURRENT (WHT-01, 6J L722). | **IO-7B-22**: controlled Voice / Analytics reconciliation (Voice 6D owner + Analytics 6L owner). The webhook topic's internal source stays with 7H (IO-7B-12); IO-7B-12 does not resolve the 6L consumer. | Status stays CCPU (not FUTURE_DEFINED, not CURRENT_PRODUCED). `call.initiated == call.started` is **not** assumed (NAM-F-02, CNF-13). 7B chooses none of the IO-7B-22 options. 075 L12. |
| CCPU-02 | `usage.event_recorded` | 6L L792–L793: `usage_cost_daily` reads `usage.event_recorded` | UNWIRED. No Billing producer emits it. Migration 075 registers the name for Analytics only; it does not provide a producer. | **IO-7B-23**: controlled Billing / Analytics reconciliation (Billing 6K owner + Analytics 6L owner) | Status stays CCPU (not FUTURE_DEFINED). CNF-12. 075 L23. 7B invents no producer and no event, and does not route voice usage through it; voice usage reaches Billing through EV-079 (§31). |

---

## 33. Phase-7 Downstream Ownership

7B fixes *which* events exist, *who* owns and produces them, *who* consumes them and *what* their payload means. It does not fix wire formats, stream layout, retry numbers or classification. Those belong to the later Phase-7 documents, in the order 7A sets (7A §35; 7A L934–L955). 7L reconciles all of Phase 7 (7A L10).

### 33.1 Handoff by Phase-7 document

| Phase-7 owner | Receives from 7B | 7B inputs | 7A DD | Obligation |
|---|---|---|---|---|
| 7C | Envelope field names, payload field names and types, `event_version` policy, the EV-079 usage block, and the field binding of the Class D payload registry (PAY-D-01, PAY-D-02) | §15.1, §24 (105 rows), §27, §31.3 | DD-02, DD-03, DD-22 | IO-7B-04, IO-7B-06 |
| 7D | Outbox relay for all 105 durable events, including the EV-079 row written by the finalization transaction; the publisher contract for the 19 current Class D signals | §11–§15, §21, §31.2 | DD-09, DD-21 (with 7G / 7K) | IO-7B-10 |
| 7E | Stream names, per-stream ordering, consumer-group layout, Class D stream placement | §15, §22, CR-04 | DD-04…DD-08, DD-15 (stream part) | IO-7B-08 |
| 7F / 7G | Consumer inbox / dedup, retry, DLQ, replay | §22, §27 (IDN-*) | DD-10…DD-13 | IO-7B-09 |
| 7H | Internal-event → webhook-topic mapping, including the internal source of the two CURRENT topics `call.started` / `call.completed` (WHT-01, WHT-02) and `invoice.generated` → `invoice.created` | §18 (WHT-01…19) | — (6J owns signing and versioning) | IO-7B-12 |
| 7I | Field-level classification of every [7I] mark and the EV-078 [7I-HOLD] field; audit dispatch | §24, §39, §40.3 | DD-19, DD-14 (retention part) | IO-7B-07 |
| 7J | Event metric names, cardinality, SLOs, alerts; observability of conversations stalled before finalization and of corrupt usage state | §11, §15 (names only), §31.2 | DD-17 | IO-7B-21 |
| 7K / 7L | The Voice stale-conversation reaper / recovery worker as the recovery-path invoker of the shared finalization (§31.2, §31.6, OD-7B-02); corrupt / incomplete service-end state (§31.7 OCC-05); reconciliation of corrupt durable usage state; Phase-7 reconciliation | §31.2, §31.5 | DD-18, DD-20, DD-21 (part) | IO-7B-05, IO-7B-18 |

### 33.2 Implementation obligations (IO-7B-*)

7B modifies no frozen document. Every change that another document must absorb is recorded here. Items that target a frozen Phase-6 document or AIR are **future controlled amendments**. 7B does not perform them.

| IO | Target | Obligation | Source in 7B | Blocks 7B readiness? |
|---|---|---|---|---|
| IO-7B-01 | 6D (controlled amendment) | State that `conversation.completed` (EV-079) is written once per finalization generation, to the outbox, in the accounting-finalization transaction (OD-7B-01 D-2 as clarified by OD-7B-02), and that it carries or references the accumulated usage (§31.3). | §30 D-2, §31 | No. It must land before Billing activates the remap. |
| IO-7B-02 | 6K (controlled amendment) | Remap AI_MINUTES, STT_SECONDS, TTS_CHARACTERS and voice LLM_PROMPT_TOKENS / LLM_COMPLETION_TOKENS to EV-079, with `source_event_id = <outbox_event_id>:<metric>`. Update the 6K L2511 consumer list. | §26, §30 D-3 | No. Same activation condition as IO-7B-01. |
| IO-7B-03 | 6K wording for DS-17 | Record `conversation.turn_completed` as ANALYTICS_ONLY and not billing-authoritative. Correct the 6E attribution to 6D (CNF-16). Record that DS-19 `tool_execution.*` is not a Billing source (P1-7B-07). | §15 DS-17, DS-19, §30 D-5 | No |
| IO-7B-04 | 7C | Bind the EV-079 payload, including the usage block (five metrics, §26.1), and its version. Bind field names for PAY-D-01 and PAY-D-02; 7B chose none. | §15.1, §24, §31.3 | No |
| IO-7B-05 | 7K | Define the Voice stale-conversation reaper / recovery worker (Voice-owned role, PRD-27): detection of conversations that stopped without normal finalization, its schedule and alerting. It invokes the shared finalization operation (FIN-1…FIN-4) and nothing else; EV-079 is emitted only if the conversation is not already finalized. It never writes `usage_events`, never emits a different event, and reuses the persisted service-end time as the occurrence time, never its own `now()` (OD-7B-02, §31.7). | §31.2, §31.5, §31.6, §31.7, INV-01 | No |
| IO-7B-06 | 7C | Bind the envelope: identity, tenant, correlation and causation fields, and the event version representation | §24, §27 | No |
| IO-7B-07 | 7I | Classify every field marked [7I] or [7I-HOLD]. Until 7I closes a field, the field is excluded from any external surface. | §24, §39, §40.3 | No |
| IO-7B-08 | 7E | Fix per-stream ordering guarantees. Consumers already assume only per-aggregate ordering (CR-04). | §22 | No |
| IO-7B-09 | 7F / 7G | Implement event-id dedup plus business-key guards (IDN-06, IDN-08). Billing ingestion of EV-079 is idempotent on `<outbox_event_id>:<metric>` (IDN-05, IDN-10). | §27 | No |
| IO-7B-10 | 7D | Relay contract for the 105 durable events, and the publisher contract for Class D signals, including the non-durable status of DS-17 and DS-19. The EV-079 outbox row is written only by the finalization worker transaction (PRD-27). The relay and publish times are never the Billing occurrence time (OCC-04). | §11, §15, §31.2, §31.7 | No |
| IO-7B-11 | 6L + Phase 5 (controlled amendment) | Add `fn_apply_projection` wiring for `campaign_outcome_summary` (CNF-15, CNF-17). Register any newly consumed event type in `analytics.event_schema_versions` by a governed Phase-5 migration, never by 7B. | §25.2, §32.2 | No |
| IO-7B-12 | 7H | Map internal events to webhook topics: the internal source of the CURRENT topics `call.started` / `call.completed` (WHT-01, WHT-02; candidates EV-004 / EV-005, names not merged) and `invoice.generated` → `invoice.created` (NAM-F-06). Topic names, signing and versioning stay as 6J defines them. | §10, §18 | No |
| IO-7B-13 | AIR (controlled amendment) | Align AIR consumer-column wording with the consumers' own documents (CNF-04, CNF-05, CNF-06) | §12, §14 | No |
| IO-7B-14 | 6D L1230 (controlled amendment) | Align the "all future" consumer wording with the frozen consumer documents (CNF-08) | §12.2 | No |
| IO-7B-15 | Phase 5 (governed migration) | Add durable per-conversation accumulation for all five metrics (ACC-01…ACC-06). Column names, types and the migration number are chosen by that migration, not by 7B. | §26.1 | No. It must land before Billing activates the remap. |
| IO-7B-16 | Phase 5 (governed migration) | Add the durable conversation-level finalization guard as a physical constraint, so at most one EV-079 per finalization generation can commit (IDN-10, IDN-11) | §27 IDN-11, §31.2 | No. Same activation condition. |
| IO-7B-17 | 6D (controlled amendment, OD-7B-01 / OD-7B-02) | State the per-turn checkpoint accumulation (ACC-01) by the live conversation runtime; the shared finalization operation (FIN-1…FIN-4) invoked by the Voice-owned post-call / accounting-finalization worker (normal) and the stale-conversation reaper / recovery worker (recovery) (PRD-27); the EV-079 meaning as accounting finalization, not call success (§31.6); the persisted service-end time as the Billing occurrence time (§31.7); and DS-19 as a current Class D signal that is not a Billing source | §15, §26.1, §31.2, §31.6, §31.7 | No |
| IO-7B-18 | 7L | Reconcile conversations whose durable usage state is missing or corrupt. No charges are synthesized; Billing receives nothing for such a conversation until reconciliation resolves it. | §31.2, §31.5 | No |
| IO-7B-19 | 6K (controlled amendment) | During the controlled 6K amendment implementing OD-7B-01/02, perform a full semantic search for every `conversation.turn_completed` reference and reconcile every Billing-authoritative occurrence to the new `conversation.completed` model while preserving Analytics-only Class-D semantics where appropriate. The line references known to 7B (6K L71, L1913–L1915, L1968, L2013, L2511, L2850) are examples only and are **not exhaustive**; the amendment must not be limited to them. Categories to reconcile: metric producer rows; AI_MINUTES; STT_SECONDS; TTS_CHARACTERS; LLM prompt / completion tokens; Billing idempotency examples (`source_event_id = <outbox_event_id>:<metric>`); Voice / workflow usage ownership rules; ingestion-consumer sections; ADR and traceability references. `TOOL_EXECUTIONS` stays UNWIRED (DEP-6K-01). This is the text change that IO-7B-02 activates. 7B does not modify 6K (Minor-7B-01). | §26, §30 D-3 | No |
| IO-7B-20 | 5H (controlled amendment) | Correct 5H L269 `voice.conversation_turns` to the migrated table `voice.turns` (012_5C.sql), and its source event to EV-079 (CNF-20) | §5.1 AUTH-C-04, §37 | No |
| IO-7B-21 | 7J | Observe conversations stalled before finalization, finalization no-ops, and corrupt usage or missing / corrupt service-end state routed to 7L | §31.2, §31.7 | No |
| IO-7B-22 | Voice (6D) + Analytics (6L) (controlled reconciliation; CCPU-01) | A controlled Voice/Analytics reconciliation MUST determine the authoritative current source for the 6L `agent_utilization_hourly` start signal. It must not assume `call.initiated == call.started`. Permitted outcomes: (1) a governed mapping from an existing Voice event; (2) a real current producer of `call.started`; or (3) a 6L amendment to consume the correct existing event. 7B does not choose among them. Until it closes, CCPU-01 stays CURRENT_CONSUMER_PRODUCER_UNWIRED (not FUTURE_DEFINED). Future ownership: Voice owns the start-signal fact; Analytics owns the projection's consumption; any new event-type registration goes through a governed Phase-5 migration, never 7B. Independent of IO-7B-12 (webhook topic source, 7H). | §25.1, §25.2, §32.5, CNF-13 | No |
| IO-7B-23 | Billing (6K) + Analytics (6L) (controlled reconciliation; CCPU-02) | A controlled Billing/Analytics reconciliation MUST either establish the authoritative producer of `usage.event_recorded` or amend 6L to consume an already-authoritative Billing usage fact. 7B does not choose between them. 7B invents no producer and no event; migration 075 registers the name but does not provide a producer. Until it closes, CCPU-02 stays CURRENT_CONSUMER_PRODUCER_UNWIRED (not FUTURE_DEFINED). Future ownership: Billing owns any usage-recorded fact; Analytics owns `usage_cost_daily` consumption. | §25.1, §25.2, §32.5, CNF-12 | No |

IO count: **23**. None blocks 7B readiness. IO-7B-22 and IO-7B-23 are the CCPU handoffs added by P1-7B-05R; IO-7B-11 and IO-7B-17 are no longer cited as CCPU owners. IO-7B-01, IO-7B-02, IO-7B-17 and IO-7B-19 together are the Phase-6 amendment that OD-7B-01 and OD-7B-02 require. IO-7B-15 and IO-7B-16 are the Phase-5 migration obligations. They are recorded as required, and they are **not** performed by 7B.

---

## 34. ADR Register

ADRs are recorded only where 7B made a real choice between alternatives.

| ADR | Context | Decision | Rejected alternatives | Consequence |
|---|---|---|---|---|
| ADR-7B-01 | A producer can sit in a different context from the fact's owner (for example CNF-07) | Canonical ownership is the **semantic owner** bounded context. The producer is recorded separately (§9, OWN-01…05). | Owner = producing module | `compliance.eligibility_denied` is Compliance-owned and Campaign-produced. No duplicate entry. |
| ADR-7B-02 | Frozen sources mix lifecycle and consumption wording | **Status and qualifier are separate** (§8.1). Status is one of CURRENT_PRODUCED, FUTURE_DEFINED, SUPERSEDED, UNWIRED, CURRENT_CONSUMER_PRODUCER_UNWIRED or FAMILY. CURRENT_CONSUMED, CURRENT_NO_CONSUMER and ANALYTICS_ONLY are qualifiers. | A single flat status list | Counts are additive: 31 + 74 = 105 |
| ADR-7B-03 | AIR and producer documents name consumers that the consumer documents do not wire | **The consumer's own document governs its consumer role** (AUTH-7B-02, AUTH-7B-04). Producer documents govern production. | AIR consumer column as authority | CNF-04, CNF-05, CNF-06 and CNF-08 are Minor, with IO-7B-13 / IO-7B-14 |
| ADR-7B-04 | Migration 075 seeds 25 event types | **075 is an analytics schema-registration authority, not the global catalog** (§25) | 075 as master list; adding 075 rows from 7B | 7B catalogs 105 durable events. 075 rows without a producer stay FUTURE_DEFINED. Registration changes go through Phase 5 (IO-7B-11). |
| ADR-7B-05 | Frozen sources name wildcard families | **A family is a grouping, not an event** (§28). Its members are catalogued individually. A family's status follows its producer, not its name. | Cataloguing `*` as one event | FAM-01…03. `tool_execution.*` is a current Class D signal (DS-19, 6D L1234). The Billing `TOOL_EXECUTIONS` producer is a separate UNWIRED item (UNW-01, DEP-6K-01). |
| ADR-7B-06 | Several facts have Phase-4, WS or webhook-topic spellings | **No rename.** The current Phase-6 bus name is canonical. Other spellings are lineage or other mechanisms (NAM-01, NAM-F-01…09). | Normalizing all spellings | No new names. `call.initiated` ≠ `call.started`; `call.ended` ≠ `call.completed`. The two topics are CURRENT (WHT-01, WHT-02) and their source mapping is 7H's (IO-7B-12). |
| ADR-7B-07 | FOD-7B-01: turn-level usage durability | **Option C** (OD-7B-01): the turn stays Class D, and one durable EV-079 per conversation carries usage | Option A (per-turn outbox); Option B (turn promotion to durable) | §29–§31. IO-7B-01 / IO-7B-02, IO-7B-15. |
| ADR-7B-08 | 7B must state payloads (DD-01) without pre-empting 7C | **The payload registry records business meaning and lineage, not schema** (§24, §15.1) | JSON schemas in 7B | 7C binds names, types and versions (IO-7B-04, IO-7B-06) |
| ADR-7B-09 | Recovery of a conversation that stops without normal completion (P1-7B-03) | **One finalization path** (OD-7B-02): the Voice stale-conversation reaper / recovery worker invokes the same atomic finalization as the normal post-call / accounting-finalization worker and produces the same EV-079, with the persisted service-end time as occurrence time (PRD-27, §31.6, §31.7) | Reaper writes Billing directly; a separate recovery event; recovery-time `now()` as occurrence time | §31.2, §31.5, §31.6, §31.7. IO-7B-05, IO-7B-16, IO-7B-18. |
| ADR-7B-10 | Frozen sources give several authorities for one concern (P1-7B-01) | **Authority is per concern** (§5.1, AUTH-C-01…07): executed migrations win on physical schema; the consumer's document wins on consumption; the producer's document wins on production | One global ranking of documents | CNF-20 is resolved by migration authority (AUTH-C-04), with IO-7B-20 |

ADR count: **10**.

---

## 35. Owner Decision Register

| OD | Question | Decision | Decided by | Status | Recorded in |
|---|---|---|---|---|---|
| OD-7B-01 | FOD-7B-01 (7A DD-16): how turn-level usage reaches Billing durably | Option C. `conversation.turn_completed` stays Class D (DS-17), direct Redis Stream, non-durable, ANALYTICS_ONLY, never assigned an outbox id. `conversation.completed` (EV-079) is the one durable event per conversation, emitted exactly once at authoritative conversation accounting finalization (normal post-call path or stale/crash recovery path); it does NOT assert that the Voice call outcome was successful (P1-7B-08). It carries or references the accumulated usage. Billing uses `<outbox_event_id>:<metric>`, idempotently. The boundary is clarified by OD-7B-02. | Owner | RESOLVED (final) | §29–§31 |
| OD-7B-02 | Independent review (P1-7B-03): how a conversation that stops without normal completion is finalized for Billing | Option C. The Voice-owned post-call / accounting-finalization worker (normal) and the Voice stale-conversation reaper / recovery worker (recovery) both invoke the same atomic finalization (claim guard → finalize usage → one EV-079 outbox row → commit; a no-op if already finalized) (PRD-27, P1-7B-09). Billing occurrence time is the authoritative service-end time, never the finalization processing time (§31.7, P1-7B-10). Recovery never writes `usage_events`, never emits a different event, never fabricates identity. EV-079 means accounting finalization, not call success. Corrupt state (usage or service-end time) synthesizes no charges and goes to 7K / 7J / 7L. | Owner (remediation directive) | RESOLVED (final) | §30 D-2, §31.2, §31.5, §31.6, §31.7 |

Owner decisions in 7B: **2**. New owner decisions required now: **0**.

Every other choice in 7B follows from a frozen source (AUTH-7B-01…08) or is a recorded ADR (§34). No open question needs the owner. The remaining open items are dependencies owned by other documents (§36.3).

---

## 36. Deferred Decisions

### 36.1 7A deferred decisions owned by 7B

| 7A DD | Topic | 7B result | Evidence |
|---|---|---|---|
| DD-01 | Event payload contents per event | **CLOSED** by the payload registry for all 105 durable events and by the Class D payload registry for every consumed Class D signal (PAY-D-01, PAY-D-02). 7C binds field names, types and versions (IO-7B-04, IO-7B-06). | §24 (105 rows), §15.1 |
| DD-15 | Direct-stream Class D consumers and any durability promotion | **CLOSED** for 7B's part: all 19 DS entries have an owner, producer and current consumers. No promotion is made. Any future promotion needs governance. Stream layout stays with 7E (DD-04, DD-07). | §15, §22 |
| DD-16 | FOD-7B-01: `conversation.turn_completed` durability and Billing ingestion | **CLOSED** by OD-7B-01 (Option C), with the single finalization path fixed by OD-7B-02 | §29–§31, §35 |

### 36.2 7A deferred decisions carried to later Phase-7 documents

7B closes none of these. It supplies inputs (§33.1).

| 7A DD | Owner (7A L934–L955) | 7B input |
|---|---|---|
| DD-02 | 7C | §24, §27 |
| DD-03 | 7C | §25 (075 version `'1'` is analytics registration only) |
| DD-04 | 7E | §15, §22 |
| DD-05 | 7E / 7K | §23 |
| DD-06 | 7E | — |
| DD-07 | 7E | §22 |
| DD-08 | 7E / 7K | — |
| DD-09 | 7D | §11 |
| DD-10 | 7G | §22 |
| DD-11 | 7G | — |
| DD-12 | 7G | — |
| DD-13 | 7F / 7G | §27 |
| DD-14 | 7E / 7G / 7I | — |
| DD-17 | 7J | §11, §15 |
| DD-18 | 7K | — |
| DD-19 | 7I | §24 [7I] marks, §15.1 [7I] marks, §40.3 |
| DD-20 | 7K | — |
| DD-21 | 7D / 7G / 7K + per-flow design | §17 (TSK-*), §31.2 |
| DD-22 | 7C | §31.3 |

### 36.3 Upstream dependencies that remain open

| Dependency | Source | 7B disposition | Status |
|---|---|---|---|
| DEP-6K-01 | 6K L1920, L2864 | The Billing `TOOL_EXECUTIONS` usage producer is not built (UNW-01). `tool_execution.*` itself is a current Class D signal (DS-19, FAM-03; 6D L1234) consumed by Analytics only, and it is **not** that metric's source. Billing `TOOL_EXECUTIONS` has no source (§26). 7B creates no producer and does not wire DS-19 to Billing. | OPEN (UNWIRED) |
| DEP-6K-02 | 6K L2865 | `KNOWLEDGE_RETRIEVALS` has no producer and no event name. UNW-02. 7B creates no name. | OPEN (UNWIRED) |
| DEP-6K-05 | 6K L2020, L2868 | Whether `workflow.execution.completed` (EV-100) carries a field that says "invoked inside a voice turn" versus "standalone" is unconfirmed. 6K §23.3 binds the LLM-usage producer-ownership rule: in-turn LLM usage belongs to the voice producer, which is EV-079 after IO-7B-02, and standalone usage belongs to EV-100. 7B records the dependency and **invents no field**. EV-100 stays the standalone workflow source, unchanged. 7C carries the discriminator once 6E / 6I confirm it. | OPEN (dependency, non-blocking in 6K) |

6K §54.5 (capacity quotas, L3676) states its rules without any event or transport. It adds no event to 7B.

Deferred count: **22** (19 carried 7A DDs + 3 open upstream dependencies).

---

## 37. Conflict / Contradiction Scan

### 37.1 Conflict register (CNF-*)

A conflict is recorded when two frozen sources disagree in wording, name or consumer. Each is resolved by the authority order (§5, AUTH-7B-01…08) without a rename or a migration.

| CNF | Sources | Conflict | Resolution | Severity |
|---|---|---|---|---|
| CNF-01 | 4E L1003, 4G L591, 6I L937, L1089, L894 | Workflow completion appears as dotted, underscore and WS forms | `workflow.execution.completed` is the bus name (EV-100). The WS form is Class F. No normalization (NAM-F-01). | Minor |
| CNF-02 | 4I L1411; 6G | `suppression.lifted` versus `contact.suppression_lifted` | The current 6G form is canonical. The 4I form is lineage. | Minor |
| CNF-03 | 6D L1214 | "call.terminated" wording | Not an entry. It resolves to EV-005 / EV-006 by outcome (§32.4). | Minor |
| CNF-04 | AIR 6G consumer column | AIR names Campaign / Analytics / Billing / Webhook / Integrations | 6G wires fewer consumers. The consumer document governs (ADR-7B-03). IO-7B-13. | Minor |
| CNF-05 | AIR 6J rows; 6J §50 | "WebhookDispatchService" for `integration.*` / `plugin.*` | Not webhook-eligible (Rule G-1). No webhook consumer. IO-7B-13. | Minor |
| CNF-06 | AIR 6H-018 | "import consumers (6H §13.3)" wording | No additional consumer is recorded. IO-7B-13. | Minor |
| CNF-07 | 6H; 6C | `compliance.eligibility_denied` is produced outside its owner | Owner Compliance, producer Campaign executor (ADR-7B-01) | Minor |
| CNF-08 | 6D L1230 | "all future" consumers versus consumers wired in 6G, 6H, 6K, 6L | The consumer documents govern. IO-7B-14. | Minor |
| CNF-09 | 6D L1216; 6G L862; 6H L1295 | `qualification_set` wording versus a frozen durable consumer | Class C with current consumers | Minor |
| CNF-10 | 6H L1742 | `campaign.started` described in request wording | Class C from the executor (AIR-P0-EVT-03) | Minor |
| CNF-11 | 6J L1912–L1915; 6K §45.1 | 6J labels Billing topics "future 6K". 6K wires them. | The producing owner (6K) governs. WHT-15…19 are CURRENT. | Minor |
| CNF-12 | 075 L23; 6L L792–L793 | `usage.event_recorded` is a projection source with no producer | CCPU-02 (§32.5): the 6L consumer is current and the producer is UNWIRED. No producer is invented. IO-7B-23 (controlled Billing / Analytics reconciliation; P1-7B-05R). | Minor |
| CNF-13 | 6L L797 | `agent_utilization_hourly` names `call.started` as a source | `call.started` is CCPU-01 (§32.5): the 6L consumer is current and no bus producer emits the name. It is not merged with `call.initiated` (NAM-F-02). That projection input stays unfed until the controlled Voice / Analytics reconciliation IO-7B-22 determines its authoritative source (P1-7B-05R). IO-7B-12 governs only the webhook topic source. | Minor |
| CNF-14 | 6I | "required by Analytics" for EV-100, with no 6L projection | Analytics is recorded as a future consumer only | Minor |
| CNF-15 | 6L L169 | `fn_apply_projection` is missing for `campaign_outcome_summary` | IO-7B-11 | Minor |
| CNF-16 | 6K L2511; 6D L1216, L1234 | 6K treats `conversation.turn_completed` as a Billing source and attributes it to 6E | Resolved by OD-7B-01 and OD-7B-02: DS-17 is ANALYTICS_ONLY, the 6D owner is kept, and IO-7B-02 / IO-7B-03 / IO-7B-19 apply | Minor (resolved) |
| CNF-17 | 6L L116, L233; 075 L22 | `campaign_outcome_summary` has no wired event, although EV-097 exists | EV-097 stays CURRENT_NO_CONSUMER. IO-7B-11. | Minor |
| CNF-18 | 6K §35; 6K L2816–L2827 | The worker row names an "`invoice.created` outbox event" | The internal name is `invoice.generated`, and `invoice.created` is the topic (NAM-F-06) | Minor |
| CNF-19 | 075 L24; 6K | `invoice.payment_succeeded` versus the current `invoice.paid` (EV-103) | FUT-04. No rename (NAM-01). | Minor |
| CNF-20 | 5H L269; 012_5C.sql | 5H names the Voice turn table `voice.conversation_turns`; the executed migration creates `voice.turns` | The executed migration governs the physical name (AUTH-C-04). 7B cites `voice.turns` and chooses no new column. 5H wording is corrected by IO-7B-20. | Minor |

CNF count: **20**. P0: **0**. P1: **0**. Minor: **20**. No conflict requires a rename, a migration or an owner decision.

### 37.2 Conflict checks

| Check | Method | Result |
|---|---|---|
| Duplicate event name | Every EV name is unique across EV-001…105. No EV name equals a DS name, an RTM name used as a bus event, a FUT name or a CCPU name. | PASS. 105 unique durable names. DS-17 `conversation.turn_completed` has no EV entry. |
| Near-duplicate / alias name | NAM-F-01…09 pairs checked: `call.initiated` / `call.started`, `call.ended` / `call.completed`, `invoice.generated` / `invoice.created`, `invoice.paid` / `invoice.payment_succeeded`, workflow forms, suppression forms | PASS. Each pair is either different mechanisms or current + future/lineage. None is merged. |
| Producer conflict | Every EV has exactly one semantic owner and one producer registry row (PRD-01…27; EV-079 moved from PRD-14 to PRD-27 by P1-7B-09). EV-005 / EV-006 have two write paths (6D-004, provider-event worker) inside one owner and one class. | PASS. No event has two owning contexts. |
| Producer existence | Every CURRENT_PRODUCED event maps to an AIR route or a named worker. UNWIRED, CCPU and FUTURE_DEFINED entries have no producer and are not counted as produced. No producer is invented for CCPU-01 or CCPU-02. | PASS. 105 / 105. |
| Payload conflict | One §24 row per EV. No two names carry the same fact with different payload meaning. Phase-4 field names (`tenant_id`, `doc_id`) are lineage for `organization_id` / `document_id`. | PASS |
| Payload security | No row embeds a token, secret, signed URL, raw media, raw transcript or card data (§24 global exclusions, §39) | PASS. Unclear fields are marked [7I]. |
| Consumer conflict | Consumer roles are taken from the consumer's own document (ADR-7B-03). AIR / producer wording differences are CNF-04, 05, 06, 08. | PASS (Minor wording only) |
| Consumer determinism | CON-01…11 give 31 consumed events. Future consumers are shown only in the "future" column. | PASS |
| Billing double-count | Voice usage comes from EV-079 only (after IO-7B-02). Recovery uses the same finalization and the same EV-079 (OD-7B-02), guarded by IDN-11. Standalone workflow LLM usage comes from EV-100 only (6K §23.3; DEP-6K-05). Identity is `<outbox_event_id>:<metric>`. Neither DS-17 nor DS-19 is a Billing source. | PASS |
| Class conflict | No event is catalogued in two primary classes. EV-001 has a B branch inside one entry (§13.2). | PASS |

---

## 38. Traceability Matrix

Each durable event is traced along the chain DDD → DB → Phase-6 producer → 7A class → 7B event → consumers → Phase-7 owner. Every row derives from registers already stated:

| Column | Source register |
|---|---|
| Event, context, producer, class | §11 |
| Consumers | §22 |
| 075 row | §25 |
| Webhook topic | §18.2 |
| 7I | §24 marks |

The DB path is the outbox table (§6.2) with the transaction in which the row is written. The Phase-7 owners are always 7C (envelope / payload), 7D (relay) and 7E (stream). The matrix adds 7F / 7G where a current consumer exists, 7H where a webhook topic exists, 7I where a payload field is marked [7I], and 7K / 7L for EV-079 (§31.2).

### 38.1 Durable events (EV-001…EV-105)

| EV | Event | DDD context (semantic owner) | Phase-6 producer | 7A class | DB path | 075 row | Consumers | Webhook topic | Phase-7 owners |
|---|---|---|---|---|---|---|---|---|---|
| EV-001 | `identity.forced_revocation_required` | Identity (6B) | 6B-009; 6B-036 (B branch) | A (+B branch) | `audit.domain_event_outbox` (request txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-002 | `organization.created` | Organization (6C) | 6C-001 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G, 7I |
| EV-003 | `compliance.policy_activated` | Compliance (6C) | 6C-030 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-004 | `call.initiated` | Voice (6D) | 6D-001 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-005 | `call.ended` | Voice (6D) | 6D-004; provider-event worker via 6D-021 | A | `audit.domain_event_outbox` (request txn) | Yes | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-006 | `call.failed` | Voice (6D) | 6D-004; provider-event worker via 6D-021 | A | `audit.domain_event_outbox` (request txn) | Yes | Current (§22) | `call.failed` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-007 | `call.held` | Voice (6D) | 6D-006 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-008 | `call.resumed` | Voice (6D) | 6D-007 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-009 | `recording.deleted` | Voice (6D) | 6D-012 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-010 | `agent.created` | AI Agent (6E) | 6E-001; 6E-007 (clone) | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-011 | `agent.config_updated` | AI Agent (6E) | 6E-004 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-012 | `agent.published` | AI Agent (6E) | 6E-005 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-013 | `agent.deprecated` | AI Agent (6E) | 6E-006 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-014 | `tool_definition.*` | AI Agent (6E) | 6E-011 / 6E-013 / 6E-014 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-015 | `knowledge_base.created` | Knowledge (6F) | 6F-001 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-016 | `knowledge_base.settings_updated` | Knowledge (6F) | 6F-004 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-017 | `knowledge_base.archived` | Knowledge (6F) | 6F-005 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-018 | `knowledge_base.reindex_triggered` | Knowledge (6F) | 6F-006 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-019 | `document.uploaded` | Knowledge (6F) | 6F-008 (`/complete`); 6F-009 (URL/WEBSITE) | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-020 | `document.deleted` | Knowledge (6F) | 6F-014 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-021 | `contact.created` | CRM (6G) | 6G-001 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | `lead.created` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-022 | `contact.updated` | CRM (6G) | 6G-004 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-023 | `contact.lead_status_changed` | CRM (6G) | 6G-005 | A | `audit.domain_event_outbox` (request txn) | Yes | None current | — | 7C, 7D, 7E |
| EV-024 | `contact.qualified` | CRM (6G) | 6G-006 (by outcome) | A | `audit.domain_event_outbox` (request txn) | Yes | Current (§22) | `lead.qualified` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-025 | `contact.disqualified` | CRM (6G) | 6G-006 (by outcome) | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | `lead.disqualified` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-026 | `contact.converted` | CRM (6G) | 6G-007 | A | `audit.domain_event_outbox` (request txn) | Yes | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-027 | `contact.owner_assigned` | CRM (6G) | 6G-008 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-028 | `contact.merged` | CRM (6G) | 6G-011 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-029 | `contact.dnc_flagged` | CRM (6G) | 6G-013; 6G-075 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-030 | `suppression.added` | CRM (6G) | 6G-013; 6G-075 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-031 | `contact.suppression_lifted` | CRM (6G) | 6G-078 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-032 | `consent.recorded` | CRM (6G) | 6G-023 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-033 | `company.created` | CRM (6G) | 6G-024 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-034 | `company.updated` | CRM (6G) | 6G-027 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-035 | `deal.created` | CRM (6G) | 6G-029 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | `deal.created` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-036 | `deal.stage_changed` | CRM (6G) | 6G-033 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-037 | `deal.won` | CRM (6G) | 6G-034 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | `deal.won` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-038 | `deal.lost` | CRM (6G) | 6G-035 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | `deal.lost` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-039 | `deal.abandoned` | CRM (6G) | 6G-036 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-040 | `activity.recorded` | CRM (6G) | 6G-044 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-041 | `task.created` | CRM (6G) | 6G-048 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-042 | `task.completed` | CRM (6G) | 6G-052 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-043 | `task.cancelled` | CRM (6G) | 6G-053 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-044 | `note.added` | CRM (6G) | 6G-055 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-045 | `note.deleted` | CRM (6G) | 6G-061 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-046 | `appointment.booked` | CRM (6G) | 6G-062 | A | `audit.domain_event_outbox` (request txn) | Yes | Current (§22) | `appointment.booked` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-047 | `appointment.confirmed` | CRM (6G) | 6G-065 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-048 | `appointment.rescheduled` | CRM (6G) | 6G-066 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-049 | `appointment.cancelled` | CRM (6G) | 6G-067 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-050 | `appointment.completed` | CRM (6G) | 6G-068 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-051 | `appointment.no_show` | CRM (6G) | 6G-069 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-052 | `campaign.created` | Campaign (6H) | 6H-001 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-053 | `campaign.config_updated` | Campaign (6H) | 6H-004 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-054 | `campaign.contact_list_attached` | Campaign (6H) | 6H-005 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-055 | `campaign.scheduled` | Campaign (6H) | 6H-006 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-056 | `campaign.paused` | Campaign (6H) | 6H-008 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-057 | `campaign.resumed` | Campaign (6H) | 6H-009 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-058 | `campaign.stopping` | Campaign (6H) | 6H-010 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-059 | `campaign.cancelled` | Campaign (6H) | 6H-011 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-060 | `import.job_created` | Campaign (6H) | 6H-017 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-061 | `workflow.created` | Workflow (6I) | 6I-001 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-062 | `workflow.draft_updated` | Workflow (6I) | 6I-005 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-063 | `workflow.published` | Workflow (6I) | 6I-007 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-064 | `workflow.archived` | Workflow (6I) | 6I-008 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-065 | `integration.disconnected` | Integrations (6J) | 6J-007 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-066 | `webhook.endpoint_created` | Integrations (6J) | 6J-018 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-067 | `plugin.installed` | Integrations (6J) | 6J-032 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-068 | `plugin.activated` | Integrations (6J) | 6J-036 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-069 | `plugin.suspended` | Integrations (6J) | 6J-037 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-070 | `plugin.uninstalled` | Integrations (6J) | 6J-040 | A | `audit.domain_event_outbox` (request txn) | No | None current | — | 7C, 7D, 7E |
| EV-071 | `subscription.changed` | Billing (6K) | 6K-006 / 6K-007 / 6K-008 | A | `audit.domain_event_outbox` (request txn) | No | Current (§22) | `subscription.changed` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-072 | `integration.connected` | Integrations (6J) | 6J-011 (success branch); connection-activation worker | B | `audit.domain_event_outbox` (conditional) | No | None current | — | 7C, 7D, 7E |
| EV-073 | `call.answered` | Voice (6D) | Provider-event worker (via 6D-021) | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-074 | `call.conversation_started` | Voice (6D) | Internal `StartConversation` (6D §23.4) | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-075 | `call.transferred` | Voice (6D) | Provider-event worker (via 6D-021) | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | `call.transferred` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-076 | `conversation.qualification_set` | Voice (6D) | Conversation runtime (qualification step) | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G, 7I |
| EV-077 | `conversation.sentiment_computed` | Voice (6D) | Post-call analysis worker | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-078 | `conversation.summarization_completed` | Voice (6D) | Post-call summarization worker | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G, 7I |
| EV-079 | `conversation.completed` | Voice (6D) | Post-call / accounting-finalization worker (normal) or Voice stale-conversation reaper / recovery worker (recovery), same atomic finalization (PRD-27; OD-7B-01 / OD-7B-02) | C | `audit.domain_event_outbox` (finalization worker txn) | Yes | Current (§22) | — | 7C, 7D, 7E, 7F/7G, 7K/7L |
| EV-080 | `knowledge_base.reindex_completed` | Knowledge (6F) | Reindex worker | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-081 | `document.indexed` | Knowledge (6F) | Ingestion worker | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-082 | `document.ingestion_failed` | Knowledge (6F) | Ingestion worker | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-083 | `contact.score_updated` | CRM (6G) | Lead-scoring worker | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-084 | `campaign.started` | Campaign (6H) | Campaign executor (PREPARING→RUNNING) | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | `campaign.started` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-085 | `campaign.completed` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | Yes | Current (§22) | `campaign.completed` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-086 | `campaign.failed` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-087 | `campaign.contact.enqueued` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-088 | `campaign.contact.dnc_skipped` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-089 | `campaign.contact.ineligible` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-090 | `campaign.contact.call_attempted` | Campaign (6H) | Campaign executor (dialer) | C | `audit.domain_event_outbox` (worker txn) | Yes | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-091 | `campaign.contact.qualified` | Campaign (6H) | Campaign executor (outcome recording) | C | `audit.domain_event_outbox` (worker txn) | Yes | Current (§22) | `campaign.contact.qualified` | 7C, 7D, 7E, 7F/7G, 7H, 7I |
| EV-092 | `campaign.contact.disqualified` | Campaign (6H) | Campaign executor (outcome recording) | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-093 | `campaign.contact.retry_scheduled` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-094 | `campaign.contact.exhausted` | Campaign (6H) | Campaign executor | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-095 | `import.job_completed` | Campaign (6H) | Import worker (route 6H-018) | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-096 | `import.job_failed` | Campaign (6H) | Import worker (route 6H-018) | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-097 | `campaign.outcome_computed` | Campaign (6H) | Outcome computation worker | C | `audit.domain_event_outbox` (worker txn) | Yes | None current | — | 7C, 7D, 7E |
| EV-098 | `compliance.eligibility_denied` | Compliance (6C) | Campaign executor (cross-context producer; CNF-07) | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-099 | `workflow.execution.started` | Workflow (6I) | Workflow runtime | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E |
| EV-100 | `workflow.execution.completed` | Workflow (6I) | Workflow runtime | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | — | 7C, 7D, 7E, 7F/7G |
| EV-101 | `workflow.execution.failed` | Workflow (6I) | Workflow runtime | C | `audit.domain_event_outbox` (worker txn) | No | None current | — | 7C, 7D, 7E, 7I |
| EV-102 | `invoice.generated` | Billing (6K) | Invoice generation worker (6K §35) | C | `audit.domain_event_outbox` (worker txn) | Yes | Current (§22) | `invoice.created` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-103 | `invoice.paid` | Billing (6K) | Payment-provider event processing (via 6K-023) | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | `invoice.paid` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-104 | `payment.failed` | Billing (6K) | Payment-provider event processing (via 6K-023) | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | `payment.failed` | 7C, 7D, 7E, 7F/7G, 7H |
| EV-105 | `usage.threshold_reached` | Billing (6K) | Usage/quota worker | C | `audit.domain_event_outbox` (worker txn) | No | Current (§22) | `usage.threshold_reached` | 7C, 7D, 7E, 7F/7G, 7H |

Rows: **105**. Consumed: **31**. No current consumer: **74**. 075 rows: **12**. Current webhook topics in this table: **17** (EV-mapped). Current governed webhook topics in total: **19**, adding WHT-01 `call.started` and WHT-02 `call.completed`, whose source mapping is pending 7H (§18.2). Rows routed to 7I: **25**.

### 38.2 Class D signals (DS-01…DS-19)

Class D signals have no outbox row (DB path: none, post-commit publish). All 19 are current (P1-7B-07).

| DS | Signal | Semantic owner | Producer | 7A class | Consumers | Phase-7 owners |
|---|---|---|---|---|---|---|
| DS-01 | `organization.updated` | Organization | 6C-003 | D | None | 7D (publisher), 7E |
| DS-02 | `organization.suspended` | Organization | 6C-006 | D | None | 7D (publisher), 7E |
| DS-03 | `organization.cancelled` | Organization | 6C-007 | D | None | 7D (publisher), 7E |
| DS-04 | `member.invited` | Organization | 6C-016 | D | None | 7D (publisher), 7E |
| DS-05 | `member.role_changed` | Organization | 6C-010 | D | None | 7D (publisher), 7E |
| DS-06 | `member.suspended` | Organization | 6C-011 | D | None | 7D (publisher), 7E |
| DS-07 | `member.reactivated` | Organization | 6C-012 | D | None | 7D (publisher), 7E |
| DS-08 | `member.removed` | Organization | 6C-013 | D | None | 7D (publisher), 7E |
| DS-09 | `member.left` | Organization | 6C-014 | D | None | 7D (publisher), 7E |
| DS-10 | `ownership.transferred` | Organization | 6C-015 | D | None | 7D (publisher), 7E |
| DS-11 | `team.created` | Organization | 6C-021 | D | None | 7D (publisher), 7E |
| DS-12 | `team.updated` | Organization | 6C-023 | D | None | 7D (publisher), 7E |
| DS-13 | `team.archived` | Organization | 6C-024 | D | None | 7D (publisher), 7E |
| DS-14 | `team.member_added` | Organization | 6C-026 | D | None | 7D (publisher), 7E |
| DS-15 | `team.member_removed` | Organization | 6C-027 | D | None | 7D (publisher), 7E |
| DS-16 | `data_subject_request.*` | Compliance | 5 routes (§15) | D | None | 7D (publisher), 7E |
| DS-17 | `conversation.turn_completed` | Voice / Conversation (ANALYTICS_ONLY) | Conversation runtime (per turn) | D | Analytics (current; PAY-D-01) | 7C (PAY-D-01), 7D (publisher), 7E, 7F/7G, 7I |
| DS-18 | `provider.failover_triggered` | Voice | Provider-routing layer | D | None | 7D (publisher), 7E |
| DS-19 | `tool_execution.*` | Voice runtime (6D) | Conversation runtime (in-process turn loop) | D | Analytics (current; PAY-D-02). Billing is not a consumer. | 7C (PAY-D-02), 7D (publisher), 7E, 7F/7G, 7I |

---

## 39. Security / Tenancy Check

### 39.1 Tenancy (7A TEN-01…TEN-06, L593–L598)

| Check | 7A rule | Result |
|---|---|---|
| Every durable entry is organization-scoped or explicitly platform-scoped | TEN-01 | PASS. 104 entries are organization-scoped. EV-001 `identity.forced_revocation_required` is user-scoped and may be platform-scoped: `organization_id` may be NULL by design (077_5J1 permits NULL; §12.1). NULL means platform scope, never "unknown". |
| Organization context originates from the producing transaction | TEN-02 | PASS. Class A / B events are written in the owner's request transaction under its tenant context. Class C workers load the aggregate first and take the organization from it. `trg_outbox_tenant_check` applies (§6.2). |
| The payload `organization_id` alone is never authorization | TEN-02, TEN-04 | PASS. CR-03: a consumer re-establishes tenant context from the envelope and checks it against its own stored ownership. Rule H-2: provider callback tenant hints are resolved through the owner's stored mapping. |
| No cross-tenant fan-out | TEN-03 | PASS. No consumer in CON-01…11 is platform-scoped except the EV-001 revocation consumer, which acts on the named user only. |
| Consumers do not bypass RLS or owner invariants | TEN-04 | PASS. Consumers call the owner's guarded functions (for example, Billing usage insertion keyed by `source_event_id`). "The event said so" is never authorization. |
| Tenant-safe observability | TEN-05 | Deferred to 7J (DD-17). 7B supplies names only. |
| Envelope tenant field names | TEN-06 | Deferred to 7C (IO-7B-06) |
| Class D signals | TEN-02, TEN-03 | PASS. DS-* are published after commit by the owner, with the owner's tenant context. Non-durable. Neither DS-17 nor DS-19 carries billing authority (§15.1). |
| Accounting finalization | TEN-02 | PASS. The post-call / accounting-finalization worker and the stale-conversation reaper / recovery worker both take `organization_id` from the owning conversation row inside the finalization transaction (§31.1, §31.2). The recovery worker never takes tenant context from a Class D signal or a Redis key. |
| Public webhooks | 6J (signing, versioning unchanged) | PASS. 7B invents no tenant webhook topic (19 CURRENT topics, equal to 6J / 4F; WHT-01 / WHT-02 source mapping pending 7H). It does not alter signing or versioning. Delivery is per subscribing organization (6J). |

### 39.2 Payload security (7A SEC-01…SEC-09, L606–L614)

| Check | 7A rule | Result |
|---|---|---|
| No access tokens, refresh tokens, provider secrets, API credentials or secret-manager values | SEC-01 | PASS. §24 global exclusions. Integration events (EV-065…EV-072) carry connection / credential **references** only. |
| Non-bearer identifiers only where the owner contract requires them | SEC-02 | PASS. EV-001 carries user_id and a reason code. Any JTI list is the 6B contract, never logged beyond need. |
| Minimum PII; IDs over names, phones and emails | SEC-03 | PASS with 7I routing. 25 payload rows carry a [7I] mark (EV-002, 004, 011, 019, 021, 022, 024, 025, 028, 030, 032, 035, 038, 046, 049, 066, 075, 076, 078, 082, 087, 088, 091, 092, 101). They are routed to 7I rather than exposed by assumption (IO-7B-07). |
| No raw media bytes, no transcripts, no signed / presigned URLs | SEC-04 | PASS. Recording and transcript content is CRE (referenced by ID only). EV-078 `summary_text` is [7I-HOLD]: excluded from every external surface until 7I classifies it. |
| No raw utterance or transcript data in Billing events | OD-7B-01; SEC-03 | PASS. EV-079 carries usage quantities and identifiers only (§31.3). No Billing consumer reads DS-17 or DS-19. |
| Class D semantic payloads (PAY-D-01, PAY-D-02) | SEC-03, SEC-04 | PASS. PAY-D-01 excludes the caller's spoken text and the agent's response text. PAY-D-02 excludes tool arguments, tool results and credentials (6D L1309). Provider / model references and tool names carry [7I]. Neither payload is Billing-authoritative (§15.1). |
| Usage accumulator and finalization | SEC-03, SEC-06 | PASS. Attribution is by reference identifier only; no pricing or procurement cost is recorded (ACC-05). Recovery synthesizes no charges and no occurrence time from missing or corrupt state (§31.2, §31.7 OCC-05). |
| Handlers do not bypass authorization | SEC-05 | PASS (same as TEN-04) |
| Internal-only fields never leak outward | SEC-06 | PASS. WHT mapping is owned by 7H (IO-7B-12). `integration.*` / `plugin.*` are not webhook-eligible (Rule G-1). Cost fields stay platform-internal (6L DEC-6L-02). |
| Logs and metrics | SEC-07 | Deferred to 7J. Payload logging is off by default (7A). |
| Operator replay / DLQ actions | SEC-08 | Deferred to 7G |
| India-region residency | SEC-09 | Unchanged. 7B adds no store and no region. |

Security / tenancy result: **no P0 or P1 finding**. Open classification work is routed to 7I (IO-7B-07) and does not block 7B.

---

## 40. Validation / Adversarial Evidence

Validation was run by a scratch validator held outside the repository (spec §70). No validator, script or intermediate file was placed in the project. The validator reads this document, the §1.1 baseline artifacts, the Phase-5 migration directory and the AMI route table. It does not read Git state; Git state is not a design or freeze criterion.

### 40.1 Baseline verification

| Check | Expected | Result |
|---|---|---|
| 7A SHA-256 and line count | `699108f9…d79712`, 1086 lines | PASS (exact) |
| Phase-6 artifacts (6A–6M, AAM, AEC, AMI, AVS, FAR, AIR, certificate) SHA-256 and line counts | §1.1 values | PASS. All 20 exact. |
| PROJECT_ROADMAP SHA-256 and line count | §1.1 value | PASS (exact) |
| SQL migrations (`docs/phase-05-database-design/5K/migrations/`) | 112 files | PASS. 112. |
| Alembic revisions (`down_revision` header per migration) | 112, a single chain | PASS. 112 `down_revision` declarations (110 in the `-- down_revision:` header form; 108_5B6 and 109_5B7 state `down_revision = '…'` in their header comment). Root `001_5B` (`down_revision: None`). Head `112_5H5` (`down_revision: 111_5H4`). |
| Migration 113 | Absent | PASS. Absent. |
| Route classification (AIR) | A 75 / B 2 / C 1 / D 20 / F 1 / G 2 / H 3 / NONE 265 = 369 | PASS. §21.4 restates it unchanged. |
| CC-15 | 77 | PASS. Unchanged; OD-7B-01 adds no route write. |
| EVENT_TRIGGER_UNRESOLVED | 0 | PASS |
| `docs/phase-07-event-architecture/` contents | 7A and 7B only | PASS. No 7C–7L file exists. |

### 40.2 Structural and consistency checks

| V | Check | Result |
|---|---|---|
| V-01 | §1.1 baseline SHA-256 and line counts (22 artifacts) | PASS |
| V-02 | Migrations: 112 SQL, 112 revisions, root, head, no 113 | PASS |
| V-03 | Phase-7 directory holds 7A and 7B only | PASS |
| V-04 | Sections 1–42 present in order; no continuation marker | PASS |
| V-05 | §21.4 route arithmetic = 369 with AIR class values; CC-15 = 77; EVENT_TRIGGER_UNRESOLVED = 0 | PASS |
| V-06 | §11: EV-001…EV-105 contiguous and unique; names unique; one class per row in {A, B, C}; A 71 / B 1 / C 33; owner and producer present; no transport named as owner; +C 31 / +N 74 | PASS |
| V-07 | §24: 105 rows; names equal §11; every row has a deterministic field list (no blank, TBD or ambiguous entry) | PASS |
| V-08 | §38.1: 105 rows; names and classes equal §11; consumer column agrees with +C / +N; no durable row labelled best-effort or non-durable | PASS |
| V-09 | Forbidden catalog names absent (`call.started`, `call.completed`, `invoice.created`, `usage.event_recorded`, `suppression.lifted`, `conversation.turn_completed` as a durable EV, any reprocess or raw-media event); 8 FUT names, none catalogued as current; `contact.suppression_lifted` present | PASS |
| V-10 | Producer rules: EV-019 not produced by the upload-url route; EV-084 Class C from the executor; EV-072 on activation success only | PASS |
| V-11 | Class D: DS-01…DS-19; non-durable statement; DS-17 ANALYTICS_ONLY, not billing-authoritative, never an outbox id, no PII in its row; no DS row labelled durable | PASS |
| V-12 | Class F: RTM-01…RTM-33; underscore WS forms kept; Rule F-2 (no promotion); "never a domain event" | PASS |
| V-13 | Payload security: no token, secret, signed-URL or presigned-URL field in §24; no secret-like literal anywhere; 7B does not freeze the envelope | PASS |
| V-14 | CR-01…CR-05 present (CR-01 "never redefines"); CON-01…CON-11 each name an owner; bounded context is not a microservice | PASS |
| V-15 | OD-7B-01 owner-approved Option C and RESOLVED; two OD rows; DD-16 CLOSED; EV-079 Class C; identity `<outbox_event_id>:<metric>`; INV-01…INV-05 (loss, duplicate, flood, hot path, no exactly-once); §31.2 loss rule and IO-7B-05; every "exactly-once" mention is negated | PASS |
| V-16 | `call.initiated` / `call.started` not merged (CCPU-01; WHT-01); ADR-7B-04 (075 is not the global catalog) | PASS |
| V-17 | Every CNF, IO-7B, ADR-7B, DD, DS, FUT, UNW, FAM, RTM, CCPU, WHT, ACC and PAY-D reference resolves to a definition (FUT-01 / FUT-03 only as retired identifiers); CNF-01…20, IO-7B-01…23, ADR-7B-01…10 and DD-01…22 all defined; PRD-01…27, TRG-01…05 and OCC-01…07 all defined | PASS |
| V-18 | Stated counts equal counted rows: IO 23, ADR 10, deferred 22, CNF 20 (P0 0, P1 0), owner decisions 2 / new 0, §38 totals (105 / 31 / 74 / 12 / 17 EV-mapped topics / 25), 19 governed topics in total | PASS |
| V-19 | §41 totals P0 = 0 and P1 = 0; P1-7B-01…07, P1-7B-05R and P1-7B-08…10 all RESOLVED; Minor-7B-01 and Minor-7B-02 RESOLVED; §42 GATE-01…GATE-46 all PASS, and no gate is PASS while a finding it depends on is OPEN; readiness line present; no freeze claim | PASS |
| V-20 | Every cited route (`6X-NNN` + method + path) equals its AMI path | PASS |
| V-21 | P1-7B-01: §5.1 states no single global precedence order; AUTH-C-01…07 present; AUTH-C-04 (physical schema) is governed by the Phase-5 migrations, so no closure artifact ranks above the database; CNF-20 resolved by AUTH-C-04 | PASS |
| V-22 | P1-7B-02: §26.1 gives semantics for all five metrics (`AI_MINUTES`, `STT_SECONDS`, `TTS_CHARACTERS`, `LLM_PROMPT_TOKENS`, `LLM_COMPLETION_TOKENS`); ACC-01…06, ACC-01 covers all five; the current schema is stated not to hold all five; §31.3 carries all five; IO-7B-15 defined | PASS |
| V-23 | P1-7B-03: FIN-1…FIN-4; already-finalized is a no-op; the stale-conversation reaper / recovery worker calls the same operation and never writes `usage_events`; corrupt state synthesizes no charges; IDN-11 requires both protections; INV-02 cites IDN-11 and IDN-05; §31.2 has no "emits or reconciles"; OD-7B-02 RESOLVED in §31.5 and §35 | PASS |
| V-24 | P1-7B-04: WHT-01…WHT-19 each CURRENT; §18.2 states 19 CURRENT topics; §32.4 marks `call.completed` a CURRENT topic; §38 states 19 governed topics | PASS |
| V-25 | P1-7B-05: CCPU-01 (`call.started`) and CCPU-02 (`usage.event_recorded`) defined; §32.1 CCPU count 2; §25.1 rows for both names are CURRENT_CONSUMER_PRODUCER_UNWIRED; neither name is a FUT entry; CCPU-01 is routed to IO-7B-22 and CCPU-02 to IO-7B-23 | PASS |
| V-26 | P1-7B-06: PAY-D-01 and PAY-D-02 defined for the two consumed Class D signals; no utterance or transcript field in either minimum payload; both state not Billing-authoritative; DD-01 cites §15.1 | PASS |
| V-27 | P1-7B-07: DS-19 is CURRENT_PRODUCED and not UNWIRED; Class D UNWIRED count 0; UNW-01 is the Billing `TOOL_EXECUTIONS` producer and not DS-19; §26 `TOOL_EXECUTIONS` stays UNWIRED; DEP-6K-01 OPEN (UNWIRED) | PASS |
| V-28 | P1-7B-05R: IO-7B-22 (Voice + Analytics, CCPU-01) and IO-7B-23 (Billing + Analytics, CCPU-02) defined, each with its owners, its permitted resolution options (three for IO-7B-22, two for IO-7B-23), "7B does not choose" and a status that stays CCPU; §32.5, §25.1, §25.2, CNF-12 and CNF-13 cite IO-7B-22 / IO-7B-23; no CCPU row cites IO-7B-11 or IO-7B-17 as its handoff; IO-7B-12 cited for CCPU-01 only as the webhook-topic mapping; `call.initiated == call.started` not assumed | PASS |
| V-29 | P1-7B-08: no EV-079 row, trigger, D-2, §31.1 boundary or §35 row contains "successful" / "successfully"; the canonical sentence (authoritative conversation accounting finalization; does not assert a successful call outcome) is present in §14.1, §30 D-2, §31.1 and §31.6; the call outcome is stated to stay in EV-005 / EV-006; TRG-01…05 defined; EV-079 never per turn | PASS |
| V-30 | P1-7B-09: PRD-27 defined with the post-call / accounting-finalization worker and the Voice stale-conversation reaper / recovery worker; §11, §14.1 and §31.1 name PRD-27 as the EV-079 producer; PRD-14 states the conversation runtime does not emit EV-079; Billing is consumer only; outbox relay (7D) and Redis Streams (7E) are transport only; no function, module, class or queue name is introduced for either worker | PASS |
| V-31 | P1-7B-10: OCC-01…07 defined; occurrence time = authoritative service-end timestamp; recovery reuses the persisted timestamp; reaper `now()`, worker execution time, Redis delivery time and outbox publish / relay time are each stated forbidden; missing or corrupt state goes to 7K / 7J / 7L with nothing sent to Billing; deterministic across retries; 7C binds name and serialization only | PASS |
| V-32 | Minor-7B-01: IO-7B-19 requires a full semantic search of 6K, states its line list is examples only and not exhaustive, lists the search categories, and states 7B does not modify 6K | PASS |
| V-33 | Minor-7B-02: M-07 mutates `usage.event_recorded` (CCPU-02) into FUTURE_DEFINED and is detected by V-25; no CCPU name appears as FUTURE_DEFINED or as a FUT entry | PASS |

### 40.3 Sensitive-data and 7I handling

This subsection is the reference target of Rule G-2 (§18) and §39.

| Rule | Handling in 7B |
|---|---|
| Global exclusions | No access token, refresh token, provider secret, API credential, secret-manager value, signed or presigned URL, or raw media byte appears in any payload row (§24). V-13 checks field names and scans the whole document for secret-like literals. |
| References over content | Recordings, transcripts and documents are referenced by ID. EV-019 carries no upload URL. EV-066 carries no signing secret. Integration events carry credential references only. |
| Unclear classification | 25 payload rows carry a [7I] mark (§39.2 list). The field is named for lineage only. It is not cleared for any external surface until 7I classifies it (IO-7B-07). |
| Held field | EV-078 `summary_text` is [7I-HOLD]. It is excluded from every external surface, including webhooks, until 7I classifies it. |
| Billing events | EV-079 carries usage quantities and identifiers only. No utterance, transcript or raw provider payload (§31.3). |
| Class D | DS-17 carries no PII and no text content. It is ANALYTICS_ONLY. DS-19 carries no tool arguments or results. Both minimum payloads are in §15.1 with [7I] marks. |
| Webhooks | Sensitive-data columns of 6J L722–L740 apply unchanged. Recording URLs and transcripts are never embedded. "Yes" / "Possibly" fields go to 7I. 7H owns the topic mapping (IO-7B-12). |
| Tenancy | The payload `organization_id` is never authorization (CR-03, Rule H-2, §39.1). |

### 40.4 Adversarial mutations

Each mutation was applied to an in-memory copy of this document or of the baseline environment. The validator was re-run on every copy. A mutation counts as detected only when the check named below fails. The clean document and environment pass every check.

| M | Mutation (spec §70) | Detecting check | Result |
|---|---|---|---|
| M-01 | 7A SHA changed | V-01 | DETECTED |
| M-02 | Phase-6 AIR SHA changed | V-01 | DETECTED |
| M-03 | Migration 113 added | V-02 | DETECTED |
| M-04 | Event route classification count changed (D 20 → 21) | V-05 | DETECTED |
| M-05 | CC-15 changed from 77 | V-05 | DETECTED |
| M-06 | Current event omitted from §11 | V-06 | DETECTED |
| M-07 | `usage.event_recorded` (CCPU-02) incorrectly reclassified as FUTURE_DEFINED | V-25, V-33 | DETECTED |
| M-08 | Event name silently normalized (`call.ended` → `call.completed`) | V-09 | DETECTED |
| M-09 | Producer owner removed | V-06 | DETECTED |
| M-10 | Consumer owner removed | V-14 | DETECTED |
| M-11 | Event class missing | V-06 | DETECTED |
| M-12 | One event assigned two primary classes | V-06 | DETECTED |
| M-13 | Class D signal labelled outbox durable | V-11 | DETECTED |
| M-14 | Class A event labelled best-effort | V-08 | DETECTED |
| M-15 | No-current-consumer event given an invented consumer | V-08 | DETECTED |
| M-16 | Current payload left ambiguous | V-07 | DETECTED |
| M-17 | Raw PII added to `conversation.turn_completed` | V-11 | DETECTED |
| M-18 | Signed URL placed in a payload | V-13 | DETECTED |
| M-19 | Token / secret added to a payload | V-13 | DETECTED |
| M-20 | Common envelope fields frozen in 7B | V-13 | DETECTED |
| M-21 | Redis made semantic owner | V-06 | DETECTED |
| M-22 | Consumer redefines producer semantics | V-14 | DETECTED |
| M-23 | Bounded context treated as mandatory microservice | V-14 | DETECTED |
| M-24 | FOD left unresolved while READY | V-15 | DETECTED |
| M-25 | Owner choice fabricated | V-15 | DETECTED |
| M-26 | Billing uses `outbox_event_id` with no outbox event (EV-079 made Class D) | V-06 | DETECTED |
| M-27 | Billable usage can be lost (loss rule removed) | V-15 | DETECTED |
| M-28 | Duplicate replay can double-charge (INV-02 removed) | V-15 | DETECTED |
| M-29 | Solution blocks the Voice hot path | V-15 | DETECTED |
| M-30 | Solution claims exactly-once | V-15 | DETECTED |
| M-31 | `call.started` and `call.initiated` merged without authority | V-16 | DETECTED |
| M-32 | Underscore workflow WS name normalized | V-12 | DETECTED |
| M-33 | Analytics registry treated as the canonical producer list (ADR-7B-04 removed) | V-17 | DETECTED |
| M-34 | `document.uploaded` moved to the upload-url route | V-10 | DETECTED |
| M-35 | Reprocess event invented | V-09 | DETECTED |
| M-36 | `campaign.started` moved to the HTTP start transaction | V-10 | DETECTED |
| M-37 | `integration.connected` moved before activation success | V-10 | DETECTED |
| M-38 | All Class D signals promoted to durable | V-11 | DETECTED |
| M-39 | Realtime WS messages made durable events | V-12 | DETECTED |
| M-40 | Raw voice media catalogued as a bus event | V-09 | DETECTED |
| M-41 | P0 > 0 but READY | V-19 | DETECTED |
| M-42 | P1 > 0 but READY | V-19 | DETECTED |
| M-43 | Owner decision required but READY | V-18 | DETECTED |
| M-44 | FOD unresolved but READY (GATE-23 not PASS) | V-19 | DETECTED |
| M-45 | Frozen Phase-6 source (6D) modified | V-01 | DETECTED |
| M-46 | Global document ranking reintroduced in §5.1 | V-21 | DETECTED |
| M-47 | Closure artifact ranked above the database (AUTH-C-04 governed by AIR / FAR) | V-21 | DETECTED |
| M-48 | STT accumulator omitted | V-22 | DETECTED |
| M-49 | TTS accumulator omitted | V-22 | DETECTED |
| M-50 | LLM prompt-token accumulator omitted | V-22 | DETECTED |
| M-51 | LLM completion-token accumulator omitted | V-22 | DETECTED |
| M-52 | `AI_MINUTES` omitted | V-22 | DETECTED |
| M-53 | Current schema claimed to hold all five metrics | V-22 | DETECTED |
| M-54 | Recovery writes Billing (`usage_events`) directly | V-23 | DETECTED |
| M-55 | Finalization worker and recovery worker both emit EV-079 (no-op rule removed) | V-23 | DETECTED |
| M-56 | Outbox id alone claimed to prevent duplicates (INV-02) | V-23 | DETECTED |
| M-57 | Finalization guard removed (FIN-1) | V-23 | DETECTED |
| M-58 | Webhook topic `call.started` labelled FUTURE | V-24 | DETECTED |
| M-59 | Webhook topic `call.completed` labelled FUTURE | V-24 | DETECTED |
| M-60 | "17 current" webhook topics stated | V-24 | DETECTED |
| M-61 | `call.started` Analytics input labelled purely FUTURE | V-25 | DETECTED |
| M-62 | `usage.event_recorded` gap hidden (CCPU-02 removed) | V-25 | DETECTED |
| M-63 | DS-17 payload omitted (PAY-D-01 removed) | V-26 | DETECTED |
| M-64 | Raw `utterance_text` added to the DS-17 payload | V-26 | DETECTED |
| M-65 | DS-17 labelled Billing-authoritative | V-26 | DETECTED |
| M-66 | DS-19 labelled UNWIRED because of DEP-6K-01 | V-27 | DETECTED |
| M-67 | `TOOL_EXECUTIONS` labelled wired | V-27 | DETECTED |
| M-68 | OD-7B-02 OPEN while READY | V-23 | DETECTED |
| M-69 | Recovery loss handling ambiguous while READY | V-23 | DETECTED |
| M-70 | Duplicate model ambiguous while READY (IDN-11 dual protection removed) | V-23 | DETECTED |
| M-71 | CCPU-01 handoff pointed back to IO-7B-11 (IO-7B-22 citation removed) | V-28 | DETECTED |
| M-72 | CCPU-02 handoff pointed back to IO-7B-17 (IO-7B-23 citation removed) | V-28 | DETECTED |
| M-73 | IO-7B-22 resolution options deleted | V-28 | DETECTED |
| M-74 | 7B selects a CCPU-01 option (`call.initiated == call.started` asserted) | V-16, V-28 | DETECTED |
| M-75 | EV-079 trigger reworded to "successful conversation completion" | V-29 | DETECTED |
| M-76 | Canonical EV-079 meaning sentence removed from §31.6 | V-29 | DETECTED |
| M-77 | EV-079 emitted per turn | V-29 | DETECTED |
| M-78 | Conversation runtime restored as EV-079 producer in §14.1 | V-30 | DETECTED |
| M-79 | PRD-27 row removed | V-17, V-30 | DETECTED |
| M-80 | Billing named as EV-079 producer | V-30 | DETECTED |
| M-81 | Recovery path uses the reaper's `now()` as occurrence time | V-31 | DETECTED |
| M-82 | Outbox publish time permitted as occurrence time | V-31 | DETECTED |
| M-83 | Missing service-end timestamp synthesized instead of routed to reconciliation | V-31 | DETECTED |
| M-84 | OCC-06 (retry determinism) removed | V-31 | DETECTED |
| M-85 | IO-7B-19 line list stated exhaustive | V-32 | DETECTED |
| M-86 | M-07 reverted to "future event labelled current" | V-33 | DETECTED |
| M-87 | P1-7B-05R left OPEN while READY | V-19 | DETECTED |
| M-88 | P1-7B-10 left OPEN while READY | V-19 | DETECTED |
| M-89 | Minor-7B-01 left OPEN while its gate is PASS | V-19 | DETECTED |
| M-90 | GATE-43 FAIL while the readiness line remains | V-19 | DETECTED |

Mutations: **90**. Detected: **90**. Undetected: **0**.

---

## 41. Findings Register

No P0 or P1 finding remains open. The seven P1 findings raised by the first independent review, and the four P1 findings and two Minor findings raised by the freeze-gate review (P1-7B-05R, P1-7B-08, P1-7B-09, P1-7B-10, Minor-7B-01, Minor-7B-02), are resolved in this revision (§41.1, §41.2). Every FND entry below is Minor. None needs a rename or a new owner decision, and none blocks 7B readiness. Future migrations and controlled amendments they imply are routed obligations (IO-7B-15, IO-7B-16), not 7B work.

| FND | Sev | Finding | Disposition |
|---|---|---|---|
| FND-01 | Minor | CNF-01…CNF-20: wording, attribution and naming differences between frozen sources (§37.1) | Resolved in 7B by the authority rules (AUTH-7B-01…08). The sources are not edited. |
| FND-02 | Minor | DEP-6K-01: the Billing `TOOL_EXECUTIONS` usage producer is not built (6K L1920, L2864; UNW-01). DS-19 `tool_execution.*` is a current Class D signal and is not that producer. | Carried OPEN. Stays UNWIRED until a 6E / 6I / 6K amendment. 7B invents no event and does not wire DS-19 to Billing. |
| FND-03 | Minor | DEP-6K-02: the `KNOWLEDGE_RETRIEVALS` usage producer has no event (6K L1921, L2865; UNW-02) | Carried OPEN. Stays UNWIRED until a 6F / 6E amendment. 7B invents no event. |
| FND-04 | Minor | DEP-6K-05: the workflow LLM-token usage field on EV-100 is a dependency (6K L2020, L2868) | Carried OPEN. EV-100 stays standalone for workflow tokens. The 6K §23.3 ownership rule keeps voice and workflow tokens apart, so there is no double count. 7B invents no field. |
| FND-05 | Minor | OD-7B-01 and OD-7B-02 require text changes to 6D, 6K, AIR, 5H and the DS-17 wording | Recorded as IO-7B-01, 02, 03, 13, 14, 17, 19 and 20. They are future controlled amendments and are not performed by 7B. |
| FND-06 | Minor | The recovery path is decided (OD-7B-02: the Voice stale-conversation reaper / recovery worker calls the same finalization; PRD-27), but that worker, the durable accumulators, the persisted service-end timestamp and the finalization guard are not built | Routed: recovery worker to 7K (IO-7B-05), worker roles and occurrence time to 6D (IO-7B-17), accumulators to Phase 5 (IO-7B-15), guard constraint to Phase 5 (IO-7B-16), reconciliation to 7L (IO-7B-18). 7B does not claim they exist in V1. |
| FND-07 | Minor | 25 payload rows have fields whose classification is unclear, and EV-078 `summary_text` is held | Routed to 7I (IO-7B-07). The fields are not exposed by assumption. |
| FND-08 | Minor | CURRENT webhook topics `call.started` and `call.completed` (WHT-01, WHT-02) need an internal source mapping | Topics stay CURRENT. The mapping is routed to 7H (IO-7B-12). No topic invented, and signing and versioning are unchanged. |

Totals: P0 = **0**. P1 = **0**. Open Minor = **8** (FND-01 covers the 20 CNF entries); all are routed and non-blocking. Resolved P1: **11** (§41.1: P1-7B-01…07, P1-7B-05R, P1-7B-08…10). Resolved Minor: **2** (§41.2).

### 41.1 Independent-review P1 findings (resolved)

| P1 | Finding | Resolution | Evidence | Status |
|---|---|---|---|---|
| P1-7B-01 | One global document ranking let a closure artifact outrank the executed database schema | Authority is per semantic concern (AUTH-C-01…07). Physical schema is governed by the migrations (AUTH-C-04). CNF-20 recorded. | §5.1, ADR-7B-10, CNF-20, IO-7B-20, V-21 | RESOLVED |
| P1-7B-02 | EV-079 totals had no durable source for STT seconds, TTS characters and AI minutes | Five-metric semantics and the durable per-turn accumulation obligation (ACC-01…06). 7B chooses no column. | §26.1, §31.3, IO-7B-15, V-22 | RESOLVED |
| P1-7B-03 | Recovery could emit or reconcile usage by an unstated second path, with no duplicate guard | OD-7B-02: one atomic finalization (FIN-1…FIN-4) for the normal-path worker and the stale-conversation reaper / recovery worker; finalization guard (IDN-11) plus `<outbox_event_id>:<metric>` | §31.2, §31.5, §35, IDN-10, IDN-11, INV-01, INV-02, IO-7B-16, V-23 | RESOLVED |
| P1-7B-04 | Webhook topics `call.started` / `call.completed` were labelled FUTURE although 6J governs them as current | Both are CURRENT (WHT-01, WHT-02); 19 CURRENT topics; source mapping pending 7H | §18.2, §32.4, §38 totals, IO-7B-12, V-24 | RESOLVED |
| P1-7B-05 | `call.started` and `usage.event_recorded` have current 6L consumers but were labelled FUTURE_DEFINED | New status CURRENT_CONSUMER_PRODUCER_UNWIRED (CCPU-01, CCPU-02); FUT-01 / FUT-03 retired | §25, §32.5, ADR-7B-02, V-25 | RESOLVED |
| P1-7B-05R | The CCPU rows routed their producer gap to IO-7B-11 / IO-7B-17, which do not own it, so the obligation was not actionable | IO-7B-22 (Voice + Analytics: CCPU-01, three permitted options, 7B does not choose) and IO-7B-23 (Billing + Analytics: CCPU-02, two permitted options, 7B does not choose). Every CCPU reference relinked. IO-7B-12 kept for the CCPU-01 webhook topic only. Status stays CCPU. | §25.1, §25.2, §32.5, §33.2, CNF-12, CNF-13, V-28 | RESOLVED |
| P1-7B-06 | DD-01 was closed for durable events only; consumed Class D signals had no stated payload | Class D semantic payload registry (PAY-D-01, PAY-D-02), with exclusions and [7I] marks | §15.1, DD-01, §39.2, V-26 | RESOLVED |
| P1-7B-07 | DS-19 was labelled UNWIRED by conflating it with the Billing `TOOL_EXECUTIONS` producer | DS-19 is a current Class D signal (6D L1234); only the Billing producer is UNWIRED (UNW-01, DEP-6K-01) | §15, §28, §32.1, §32.3, §26, DEP-6K-01, V-27 | RESOLVED |
| P1-7B-08 | EV-079 was described as marking a "successful" conversation, which asserts a call outcome that accounting finalization does not know | Canonical meaning: authoritative conversation accounting finalization; it does not assert a successful call outcome. The outcome stays in EV-005 / EV-006. TRG-01…05 fix the trigger chain. | §14.1, §30 D-2, §31.1, §31.6, §35, V-29 | RESOLVED |
| P1-7B-09 | EV-079 was attributed to the conversation runtime, but Class C (7A) is worker-emitted | PRD-27: post-call / accounting-finalization worker (normal path) and Voice stale-conversation reaper / recovery worker (recovery path), one atomic finalization. The runtime does not emit EV-079 (PRD-14). Billing is consumer only; 7D / 7E are transport. No implementation name invented. | §11, §14.1, §21.2, §31.1, §31.6, IO-7B-17, V-30 | RESOLVED |
| P1-7B-10 | The Billing occurrence time of EV-079 was undefined, so recovery could stamp usage with the reaper's clock | OCC-01…07: occurrence time = authoritative service-end timestamp; recovery reuses the persisted value; worker, reaper, Redis and outbox times forbidden; missing state goes to reconciliation; deterministic on retry | §24, §31.3, §31.7, IO-7B-05, IO-7B-10, IO-7B-21, V-31 | RESOLVED |

### 41.2 Freeze-gate Minor findings (resolved)

| Minor | Finding | Resolution | Evidence | Status |
|---|---|---|---|---|
| Minor-7B-01 | IO-7B-19 listed 6K lines as if the list were the full amendment scope | IO-7B-19 requires a full semantic search of 6K; the line list is examples only and not exhaustive; the search categories are listed; 7B does not modify 6K | §33.2 IO-7B-19, V-32 | RESOLVED |
| Minor-7B-02 | M-07 mutated `usage.event_recorded` as a future event labelled current, which contradicts its CCPU status | M-07 now reclassifies CCPU-02 as FUTURE_DEFINED and is detected by V-25 / V-33 | §40.4 M-07, V-33 | RESOLVED |

---

## 42. 7B Freeze-Gate Readiness

Gates follow spec §74 in order. "PASS" means the gate was checked by the §40 validator or against the named section.

| Gate | Requirement | Status | Evidence |
|---|---|---|---|
| GATE-01 | Frozen 7A SHA exact | PASS | §40.1, V-01 |
| GATE-02 | Frozen Phase-6 hashes exact | PASS | §40.1, V-01 |
| GATE-03 | No Phase-6 modification | PASS | V-01 (all 20 Phase-6 hashes exact) |
| GATE-04 | No 7A modification | PASS | V-01 |
| GATE-05 | 112 SQL migrations | PASS | V-02 |
| GATE-06 | 112 Alembic revisions | PASS | V-02 |
| GATE-07 | Head `112_5H5` | PASS | V-02 |
| GATE-08 | No 113 | PASS | V-02 |
| GATE-09 | 369 route classifications unchanged | PASS | §21.4, V-05 |
| GATE-10 | EVENT_TRIGGER_UNRESOLVED remains 0 | PASS | §6, V-05 |
| GATE-11 | CC-15 remains 77 | PASS | §6, §21.4, V-05 |
| GATE-12 | Every current event has a semantic owner | PASS | §11, V-06 |
| GATE-13 | Every current event has a producer | PASS | §11, §21, V-06 |
| GATE-14 | Every current event has a mechanism class | PASS | §11, V-06 |
| GATE-15 | Every current event has a deterministic domain payload or an explicit blocker | PASS | §24, V-07 |
| GATE-16 | Current consumers deterministic | PASS | §22, V-08 |
| GATE-17 | Future consumers marked future | PASS | §22, §32 |
| GATE-18 | Unwired producers remain unwired | PASS | §32 (UNW-01, UNW-02), §26, V-27 |
| GATE-19 | No event-name conflict unresolved | PASS | §37, V-09 |
| GATE-20 | No producer conflict unresolved | PASS | §37, V-10 |
| GATE-21 | No payload conflict unresolved | PASS | §37, V-07 |
| GATE-22 | No consumer conflict unresolved | PASS | §37, V-14 |
| GATE-23 | FOD-7B-01 RESOLVED | PASS | §30, §35 (OD-7B-01, OD-7B-02), V-15 |
| GATE-24 | Billing loss model deterministic | PASS | INV-01, §26.1 (ACC-01…06), §31.2, V-15, V-22, V-23 |
| GATE-25 | Billing duplicate model deterministic | PASS | INV-02, IDN-05, IDN-10, IDN-11, V-15, V-23 |
| GATE-26 | Billing source identity exists under the selected architecture | PASS | EV-079 Class C outbox; `<outbox_event_id>:<metric>`; V-15 |
| GATE-27 | No owner decision required now | PASS | §35, V-18 |
| GATE-28 | P0 = 0 | PASS | §41, V-19 |
| GATE-29 | P1 = 0 | PASS | §41, V-19 |
| GATE-30 | Only 7B created | PASS | V-03 |
| GATE-31 | Authority is per semantic concern; no closure artifact ranks above the database (P1-7B-01) | PASS | §5.1, V-21 |
| GATE-32 | Five-metric semantics and durable accumulation obligation stated (P1-7B-02) | PASS | §26.1, V-22 |
| GATE-33 | Normal and recovery paths converge on one finalization; one logical EV-079 (P1-7B-03, OD-7B-02) | PASS | §31.2, §31.5, V-23 |
| GATE-34 | 19 governed webhook topics, all CURRENT (P1-7B-04) | PASS | §18.2, V-24 |
| GATE-35 | Current-consumer / unwired-producer names explicit (P1-7B-05) | PASS | §32.5, V-25 |
| GATE-36 | DD-01 complete for consumed Class D signals; no Billing consumer depends on DS-17 (P1-7B-06) | PASS | §15.1, V-26 |
| GATE-37 | DS-19 current; `TOOL_EXECUTIONS` unwired (P1-7B-07) | PASS | §15, §32, V-27 |
| GATE-38 | OD-7B-01 preserved and OD-7B-02 recorded RESOLVED | PASS | §35, V-15, V-23 |
| GATE-39 | No exactly-once claim; delivery at-least-once | PASS | IDN-06, INV-05, V-15 |
| GATE-40 | CCPU obligations actionable: each CCPU name routed to an owning IO with options; 7B chooses none (P1-7B-05R) | PASS | §32.5, IO-7B-22, IO-7B-23, V-28 |
| GATE-41 | EV-079 means accounting finalization and asserts no call outcome (P1-7B-08) | PASS | §31.6 (TRG-01…05), V-29 |
| GATE-42 | EV-079 producer is a Class C worker role; runtime does not emit; Billing consumer only (P1-7B-09) | PASS | PRD-27, §31.6, V-30 |
| GATE-43 | Billing occurrence time deterministic and path-independent (P1-7B-10) | PASS | §31.7 (OCC-01…07), V-31 |
| GATE-44 | Billing loss and duplicate models remain deterministic after the producer and occurrence-time changes | PASS | INV-01, INV-02, IDN-10, IDN-11, OCC-05, OCC-06, V-23, V-31 |
| GATE-45 | IO-7B-19 requires a full semantic search and is not exhaustive (Minor-7B-01) | PASS | §33.2, V-32 |
| GATE-46 | M-07 mutates the CCPU status, not a FUTURE label (Minor-7B-02) | PASS | §40.4, V-33 |

Gates: **46**. PASS: **46**. FAIL: **0**.

**Readiness.** All 46 gates pass. FOD-7B-01 is resolved by OD-7B-01 (Option C), and single-path accounting finalization by OD-7B-02. P1-7B-01…07, P1-7B-05R and P1-7B-08…10 are resolved, as are Minor-7B-01 and Minor-7B-02. P0 = 0, P1 = 0, and no owner decision is required now. The open items are Minor and are routed to named owners (§33).

7B EVENT TAXONOMY & OWNERSHIP = READY FOR INDEPENDENT REVIEW
