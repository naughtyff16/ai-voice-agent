# Phase 7G — Retry, DLQ, Poison Handling & Replay — AI Voice Agent Platform

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | `docs/phase-07-event-architecture/7G-Retry-DLQ-Poison-Handling-and-Replay.md` |
| Phase | 7 — Event Architecture |
| Sub-phase | 7G — Retry, DLQ, Poison Handling & Replay (failure recovery between "a durable obligation could not be completed normally" and "that obligation is durably completed, reconciled or explicitly dispositioned") |
| Status | **READY FOR INDEPENDENT FREEZE-GATE REVIEW.** This document does not declare itself approved or frozen; freezing is an independent-review act. |
| Date | 2026-10-07 |
| Remediation | The first independent freeze-gate review, of the version with LF SHA-256 `264ba723d427489e390f89f2d0362bdea6f4d13d50fff17ba53b5b81e6a3a312` / 1653 lines, found P0 = 0 and three P1 freeze blockers: P1-7G-10 (retained R4 alternative replay material could outlive its outbox row and later be classified by a new Redis position without canonical group provenance), P1-7G-11 (R3 backfill reused R2 semantics without a durable failure / parking state machine for an event that has no recovery case) and P1-7G-12 (a generic operator disposition could terminally reject a valid owed parked obligation), plus Minor-7G-08 (the dangling-PEL prefix pre-check does not cover an interior hole). All are remediated in place (§12, §18, §20, §24, §25, §31 – §33, §36, §39, §40, §42, §48 – §51, §53, §55, §56, §58, §59). The review accepted, and this remediation does not reopen: the five-genuine-failure budget, the ledger, park-before-`XACK`, replay-complete material, the retention rule, target-specific horizons, Billing reconciliation, the publisher `FAILED` rules, the R2 internal path, R4 / R5 over the frozen 7E transport, provenance immutability, SIGNAL, DD-13 and the carried 7F blockers. The truncated tail of the work order (validator assertions 35 – 53 and the 150-mutation minimum) is completed in §60 and §61. |
| Owner decisions | OD-7G-01 = A, OD-7G-02 = A, OD-7G-03 = A, OD-7G-04 = A (all decided before authoring; §7, §54). Open owner decisions: **0** |
| Repository baseline | `main` @ `99c787f` ("7F phase freezed"), working tree clean at start |
| Frozen upstream | 7A, 7B, 7C, 7D, 7E, 7F (hashes in §6); the 20 Phase-6 artifacts; Phase-5 migrations `001_5B` … `112_5H5` |
| Preserved owner decisions | OD-7B-01, OD-7B-02, OD-7C-01 … OD-7C-07, OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B, OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B (not reopened) |
| Closes on completion | 7A DD-10 (relay and consumer parts), DD-11, DD-12, DD-14 (7G part), FM-07, RPL-01 … RPL-06 (mechanics), SEC-08 (semantics), T-04, T-10, T-12 (7G part); 7D HO-7G-01 … HO-7G-05; 7E HE-7G-01 … HE-7G-05; 7F HE-7G-7F-01 … HE-7G-7F-10 (§8) |
| Does not begin | 7H, 7I, 7J, 7K, 7L |
| Artifact rule | This is the only new project artifact for 7G. No migration (no migration 113), no application code, no Redis configuration, no edit to any frozen document. Scratch validators run outside the repository. |
| Normative keywords | **MUST**, **MUST NOT**, **SHOULD**, **MAY** carry RFC 2119 meaning. Every rule has a stable ID. |

---

## 2. Purpose

7F froze how a delivered entry becomes a durably completed consumer obligation, and deliberately stopped at every entry that cannot complete: such an entry is `HELD` — pending, unacknowledged, pinning the trim watermark — "for 7G's disposition" (7F STM-05, XAK-07). 7D froze the publisher terminal state `FAILED` and forbade its cleanup before a 7G disposition exists (7D CLN-04). 7E froze the pending-entry mechanics and left idle time, reclaim cadence, poison threshold, DLQ, replay and group-retirement execution to 7G (7E PEL-04, RET-03, BST-04).

7G closes that gap. It defines how a pending entry is redelivered, how a genuine failure is counted, when an event stops being retried, where a parked event lives, how a publisher `FAILED` row is dispositioned and repaired, and how every kind of replay is selected, authorized, bounded, executed and recorded.

The end-to-end property is unchanged: **at-least-once delivery plus idempotent consumer effects**. 7G does not claim exactly-once delivery or exactly-once processing, and no rule in this document may be read as such a claim (7A DEL-04; 7F CPM-01).

---

## 3. Scope

- Consumer redelivery: stale pending-entry reclaim, the idle threshold, the cadence, the safe Redis command subset.
- Consumer failure classification, the authoritative failure count, the bounded retry policy and its delay, dependency gating, crash-loop safety.
- Parking: the PostgreSQL recovery ledger (logical contract), case identity, replay-complete material, parking atomicity, immediate parking, holds, the recovery state machine, retention and cleanup.
- Publisher side: final relay retry timing, terminal `FAILED` disposition, explicit repair / redrive, claim-inflated attempt counts, cleanup interlocks.
- Replay: seven explicit modes, targeted consumer replay, disaster transport replay, future-consumer backfill, owner reconciliation handoff, per-target evidence horizon, canonical origin provenance and its retention, topology generations, group retirement.
- Replay governance: authorization capabilities, high-risk protection, plan and dry-run, throttling, cancellation, result model, audit.
- Tenancy, data residency, SIGNAL exclusion, the public-webhook boundary.
- Handoffs to 7H, 7I, 7J, 7K and 7L; ADRs; implementation obligations; activation blockers; conflicts; findings; validation; freeze gates.

---

## 4. Non-Goals

| Not defined or changed by 7G | Owner |
|---|---|
| Event names, payloads, classes, consumers | 7B |
| Envelope, schema versions, upcasting, lifecycle states | 7C |
| Normal outbox publication, claim, lease, relay loop | 7D |
| Stream keys, groups, route registry, acceptance mechanism, safe-trim rule | 7E |
| Consumer transaction, idempotency guards, `XACK` success contract, ordering, handler-contract cutover | 7F |
| Public webhook HTTP retry, signing, delivery dead-lettering, provider callbacks | 6J / 7H |
| Final field classification, encryption, role and grant names, Redis ACL users | 7I |
| Metric names, labels, SLO thresholds, dashboards | 7J |
| Worker counts, fleet and memory sizing, catch-up capacity, regional disaster-recovery capacity, schedules | 7K |
| Final Phase-7 reconciliation of controlled conflicts | 7L |
| Physical DDL, table and column names, migration number of the recovery ledger | The governed future Phase-5 migration (§49) |

7G creates no consumer, no group, no stream, no route, no tenant-facing API and no Phase-6 route. It adds no envelope key and changes no outbox column.

---

## 5. Authority Model

Authority is concern-specific. There is no "latest document wins" ranking.

| Source | Authoritative for (in 7G) | Not authoritative for |
|---|---|---|
| Executed Phase-5 migrations `001_5B` … `112_5H5` | Physical truth of the outbox (`077_5J1`), every owner guard and every grant | Recovery policy |
| 6A – 6M | Domain semantics; the frozen webhook replay contract (6J §23.3) | Internal event recovery |
| 7A (frozen) | DEL, IDM, RPL, SEC-08, RES, FM-01 … FM-13, §32.3 retention separation | Values and mechanisms deferred to 7G |
| 7B / 7C (frozen) | Consumer registry, event identity, lifecycle states, UV rules | Recovery mechanics |
| 7D (frozen) | Outbox lifecycle, relay dispositions, cleanup predicates, PHY-01 … PHY-12 | `FAILED` disposition, replay |
| 7E (frozen) | PEL mechanics, command facts MF-01 … MF-24, trim watermark, group lifecycle, fault model | Idle time, cadence, poison policy |
| 7F (frozen) | Classification C-1 … C-12, `XACK` contract, evidence horizons, origin provenance semantics | What happens to a `HELD` entry |
| Owner decisions OD-7G-01 … OD-7G-04 | Exactly their approved scope (§7) | Anything outside it |

| ID | Rule |
|---|---|
| AUTH-7G-01 | A question is answered by its concern's owning source. 7G binds only what 7A, 7D, 7E and 7F delegate to it and never weakens a frozen rule. Where 7G adds a precondition to a frozen step (for example an additional condition before `XACK`), the addition is strictly narrowing and is recorded in §58. |
| AUTH-7G-02 | A value chosen by 7G is a technical choice when frozen constraints and the owner decisions leave correctness independent of it. Such a value is configurable, justified where it is set, and tuned by 7K with evidence. |
| AUTH-7G-03 | Where a genuinely new product, business or persistent-architecture trade-off appears, 7G raises an owner decision and stops. §54 records that none arose. |

---

## 6. Frozen Baseline

Verified against the repository at the start of this work and again after completion. Hashes are SHA-256 of the LF-normalized content.

| Item | Expected | Observed | Result |
|---|---|---|---|
| `7A-Event-Architecture-and-Standards.md` | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` / 1086 lines | match | PASS |
| `7B-Event-Taxonomy-and-Ownership.md` | `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` / 2207 lines | match | PASS |
| `7C-Event-Envelope-and-Schema-Versioning.md` | `e514e3c4a889775fbc8e9baba3a9ad0558b5228465f240f425d7c762f1d200a0` / 3275 lines | match | PASS |
| `7D-Transactional-Outbox-Architecture.md` | `2714a3eec6eb7c95be50c3b11c2e80c66f3f93a413ebcecfa46c5c79bf9e4de5` / 1572 lines | match | PASS |
| `7E-Redis-Streams-Topology.md` | `671fcebe17bb08da4783c89323235f2bc7819fff3155d0a2d46578c6819a9c93` / 1875 lines | match | PASS |
| `7F-Consumer-Idempotency-and-Ordering.md` | `0f9db999f059486b033f06b40358a2f94978281e026e3e92ba3575adbd1185b1` / 2076 lines | match | PASS |
| Phase-6 frozen artifacts (6A – 6M, AAM, AEC, AMI, AVS, FAR, AIR, certificate) | the 20 hashes and line counts registered in 7B §1.1 | all 20 match | PASS |
| SQL migrations | 112 files, `001_5B` … `112_5H5` | 112 | PASS |
| Alembic revisions | 112, file names equal to the SQL names | 112, equal | PASS |
| Alembic chain | one linear chain, root `001_5B`, sole head `112_5H5`, no branch | root `001_5B`, head `112_5H5`, 0 duplicate `down_revision` | PASS |
| Migration 113 | absent | absent | PASS |
| Phase 7H artifact | absent | absent | PASS |
| Database engine | PostgreSQL 18 | as frozen (5K §5) | PASS |
| Event-transport Redis | Redis Open Source 7.2+ (7E CAP-01); no Redis 8.x-only dependency | as frozen | PASS |

Physical facts 7G relies on, all from `077_5J1` as reproduced in 7D §8: `fn_mark_outbox_failed` with `p_next_attempt_at = NULL` sets `available_at = NOW() + 30 seconds`; `max_attempts` defaults to 10 (`CHECK` 1 … 20); `attempt_count` is incremented by every claim (7D PHY-01); `PUBLISHED` and `FAILED` are never selected by the claim predicate; `DELETE` is granted only to `app_platform_admin`; the documented cleanup predicates are 7 days (`PUBLISHED`, by `published_at`) and 30 days (`FAILED`, by `last_attempt_at`). The `audit` schema today holds `audit.audit_events` (partitioned), `audit.audit_chain` and `audit.domain_event_outbox`; no recovery ledger exists.

---

## 7. Binding Owner Decisions

These four decisions were approved before authoring. 7G applies them and does not reopen them.

| ID | Decision | Binding content | Applied in |
|---|---|---|---|
| OD-7G-01 = A | Classification-aware bounded consumer retry | A budget of **5 durably recorded failed processing attempts** for genuine retryable handler failures. Infrastructure-wide dependency failures, transport / configuration / capability failures and evidence-horizon or reconciliation-required conditions do not consume it. Structurally permanent invalid entries do not spend five retries. After the fifth genuine failure the event is parked. Retry and parking never duplicate the protected business effect. The Redis delivery count is not the authoritative counter. | §10, §11, §14, §22 |
| OD-7G-02 = A | PostgreSQL authoritative parking ledger | One platform / event-operations-owned PostgreSQL parking and recovery ledger in the existing `audit` bounded context. Redis is not the authoritative DLQ; a Redis DLQ stream alone is prohibited; no universal consumer inbox is reintroduced; business idempotency stays domain-owned (7F DD-13 Pattern A); the ledger records transport and consumer recovery state only; a future governed migration implements it; 7G creates none. | §18 – §21, §49 |
| OD-7G-03 = A | 90-day parked / replay metadata retention | Generic parked-event, recovery and replay metadata is retained 90 days. This grants no consumer a 90-day normal replay window: each target stays capped by its frozen 7F evidence horizon. Unresolved parked obligations are never silently deleted merely because 90 days elapsed. | §25, §34 |
| OD-7G-04 = A | Publisher `FAILED` requires explicit repair | A terminal `FAILED` outbox row is never automatically redriven. A redrive needs an explicit privileged repair action after root-cause review, with a durable disposition record, a recorded reason, proven authorization and an audit record. A redrive preserves the original `event_id`, the original immutable envelope and the canonical 7F provenance; it rewrites no history, does not reset the row to `PENDING`, does not reset `attempt_count`. | §27 – §29, §48 |

---

## 8. Upstream Handoffs Closed by 7G

| Handoff | Content | Closed in | Result |
|---|---|---|---|
| 7A DD-10 | Retry delays and counts (relay, consumer, task) | §14, §15 (consumer); §26 (relay) | CLOSED for relay and consumer. The "task" part is not a generic platform value: Celery task retries stay with each owner's frozen contract and the 7D reconcilers (7D §33 – §35); 7G defines none |
| 7A DD-11 | DLQ / parked-message storage and handling | §18 – §24 | CLOSED |
| 7A DD-12 | Replay API / tooling | §30 – §42 | CLOSED (internal operations tooling; no API) |
| 7A DD-13 (7G part) | Shared inbox | §18 (LDG-02) | CLOSED: none reintroduced |
| 7A DD-14 (7G part) | DLQ and replay-metadata retention | §25 | CLOSED (OD-7G-03); sensitivity-driven limits are 7I's |
| 7A DD-21 (7G part) | Mandatory post-commit work | — | Nothing outstanding for 7G: closed architecturally by 7D §33 – §36; 7G adds no mechanism |
| 7A FM-07 | Poison is bounded, isolated, visible, never silently dropped | §14, §17, §21, §22 | CLOSED |
| 7A RPL-01 … RPL-06 | Replay deliberate; idempotent targets; billing / payment / call / webhook safety; authorized and audited; no history rewrite; beyond-horizon uses owner rebuild | §30, §31, §34, §40 – §43 | CLOSED |
| 7A SEC-08; T-04, T-10, T-12 | Privileged, audited operator actions; replay abuse; poison exhaustion; unauthorized replay | §14, §17, §40 – §42 | CLOSED (semantics); final permissions 7I |
| 7D HO-7G-01 | Publisher terminal `FAILED` | §27 | CLOSED |
| 7D HO-7G-02 | Final relay retry timing | §26 | CLOSED: the executed 30-second behaviour is kept |
| 7D HO-7G-03 | Disaster / repair replay from retained `PUBLISHED` rows | §32 | CLOSED |
| 7D HO-7G-04 | Publisher retry state ≠ consumer retry state | §9 | CLOSED |
| 7D HO-7G-05 | `attempt_count` counts claims | §29 | CLOSED |
| 7E HE-7G-01 | PEL reclaim | §12, §13 | CLOSED |
| 7E HE-7G-02 | Publisher terminal `FAILED` (none arise from the V1 transport) | §26 (PUB-05), §27 | CLOSED |
| 7E HE-7G-03 | Trim pause for `XGROUP SETID`, future-group creation, governed replay | §33 (BKL-08 … BKL-10) | CLOSED |
| 7E HE-7G-04 | Disaster replay source | §32 | CLOSED |
| 7E HE-7G-05 | Future-consumer backfill; group retirement | §33, §38 | CLOSED |
| 7F HE-7G-7F-01 | Redelivery safety contract | §12 (RCL-03) | CONSUMED |
| 7F HE-7G-7F-02 | Disposition of `HELD` entries | §10, §22, §24 | CLOSED |
| 7F HE-7G-7F-03 | Same pipeline for redelivered entries | §12 (RCL-02), §31 (TGT-03) | CLOSED |
| 7F HE-7G-7F-04 | Release of the trim pin without losing the event | §20, §21 | CLOSED |
| 7F HE-7G-7F-05 | Evidence horizon per target consumer | §34 | CLOSED |
| 7F HE-7G-7F-06 | Replay targets; CON-10 not safe before IO-7F-21 | §41 | CLOSED |
| 7F HE-7G-7F-07 | Unknown commit and ambiguous guard are safe to redeliver | §10 (FCL-06) | CONSUMED |
| 7F HE-7G-7F-08 | Backfill for a changed handler obligation; disposition for obligation retirement | §33, §38 | CLOSED |
| 7F HE-7G-7F-09 | Billing beyond-horizon entries | §35 | CLOSED |
| 7F HE-7G-7F-10 | Canonical original obligation of replayed events | §36 | CLOSED |
| 7F CNF-7F-12 (7G part) | No physical rebuild queue exists for beyond-horizon events | §24 (`RECONCILIATION_PENDING`), §34 | CLOSED: the recovery ledger is the durable work list handed to the owner's rebuild |
| 7F SHD-05 | Removal of idle consumer names | §12 (RCL-12) | CLOSED |

---

## 9. Retry Domains

Three state models exist. They are never merged, and none reads or writes another's state.

| Domain | What it describes | Where the state lives | Owner | Defined by |
|---|---|---|---|---|
| A — Publisher retry | The relay's attempts to hand a committed outbox row to the transport | `audit.domain_event_outbox`: `status`, `attempt_count`, `max_attempts`, `available_at`, `last_error`, `claimed_by`, `claimed_at` | 7D relay | 7D §15 – §25; 7G §26 – §29 for timing and terminal disposition |
| B — Consumer delivery / reclaim | One group's attempts to complete its obligation for one delivered event | The Redis consumer-group PEL, its idle time and delivery counter (transport state, 7E PEL-06); the 7G recovery ledger where a failure, hold or park must be durable | 7G | §10 – §25 |
| C — Business idempotency | Whether the business effect happened | The owning bounded context: `crm.event_consumer_dedup`, `uq_ue_idempotency`, the Analytics dedup and projection ledgers, domain state machines (7F §28) | Each consuming context | 7F §13 – §17 |

| ID | Rule |
|---|---|
| RDM-01 | `attempt_count`, `available_at`, `last_error` and `FAILED` describe publication only (7D DSP-09). No consumer path reads or writes them. |
| RDM-02 | The recovery ledger never decides whether a business effect happened. Only the owner's guard does (7F CPM-02). A recovery case in any state is never proof that an effect did or did not commit. |
| RDM-03 | The owner's idempotency evidence is never read, written, extended or deleted by a 7G component, except by executing the owner's own handler through the 7F pipeline. |
| RDM-04 | The Redis delivery counter belongs to domain B as telemetry and as a crash-loop safety input only (§17). It is never the poison budget (CNT-02) and never a business input (7F STM-03). |
| RDM-05 | A publisher-side recovery case and a consumer-side recovery case for the same `event_id` are different cases with different identities (§19). Resolving one never resolves the other. |

---

## 10. Consumer Failure Classification

7F classifies a delivery (§12.2, §9) and stops at `HELD`. 7G maps every non-acknowledged 7F outcome to exactly one **recovery class**. The mapping is a total function: an outcome that matches no row is `RETRYABLE_HANDLER_FAILURE` only through row FC-12, never by silence.

### 10.1 Recovery classes

| Class | Meaning | Consumes the OD-7G-01 budget | Automatic handler execution continues | Disposition |
|---|---|---|---|---|
| `RETRYABLE_HANDLER_FAILURE` | A genuine, entry-specific processing failure of a valid, subscribed, supported event, where the same event against the same consumer may succeed later | **Yes** — one unit per durably recorded failed attempt | Yes, until the fifth | §14 |
| `TRANSIENT_DEPENDENCY` | A dependency of the group is unavailable for every entry (owner database, handler-contract store, recovery ledger, or the external store of an IC-5 consumer) | No | No — the dependency gate opens (§16) | Entry stays pending; resumes when the gate closes |
| `PERMANENT_CONTRACT_FAILURE` | The bytes of the entry can never be processed: retry cannot repair them | No | No | Immediate park (§22) |
| `COMPATIBILITY_HOLD` | A legitimate event that the running deployment cannot yet classify or process, and that a deployment can cure | No | No (classification only is repeated) | Bounded hold, then park (§22) |
| `RECONCILIATION_REQUIRED` | The normal handler must not run: the evidence horizon is exceeded or the obligation interval is retired | No | No | Immediate hand-off to owner reconciliation (§22, §34, §35) |
| `TRANSPORT_TOPOLOGY_ANOMALY` | A transport or topology invariant is violated in a way a governed operation, not a retry, repairs | No | No | Hold with a key-level gate, or integrity case (§22, §39) |
| `CRASH_LOOP_SUSPECTED` | The entry has been delivered repeatedly and no worker survived long enough to record any outcome | No (separate technical bound) | Only in isolation (§17) | Isolation, then park |

### 10.2 Mapping from 7F outcomes (first matching row wins)

| Row | 7F outcome / condition | Recovery class | Basis |
|---:|---|---|---|
| FC-01 | C-1, C-2: wrong entry shape; wrong or unknown `fmt` | `PERMANENT_CONTRACT_FAILURE` | The bytes are immutable (7C BR-01); 7F NAK-02 |
| FC-02 | C-3, C-4: `env` unparseable, duplicate keys, envelope field invalid | `PERMANENT_CONTRACT_FAILURE` | Same |
| FC-03 | C-6: the type's route family differs from the key's family | `PERMANENT_CONTRACT_FAILURE` | Wrong family after positive validation; no deployment moves an entry |
| FC-04 | D-06, D-07: payload invalid against the declared version; payload organization differs from the envelope | `PERMANENT_CONTRACT_FAILURE` | 7C CV-08; 7F TEN-7F-02 |
| FC-05 | C-8 or C-10 where the exact pair is in the manifest with lifecycle RETIRED | `PERMANENT_CONTRACT_FAILURE` | A RETIRED pair is deliberately unprocessable (7C RET; 7F VER-7F-08) |
| FC-06 | C-5: `event_type` in no manifest pair; C-8 / C-10 where the exact pair is absent from this build's manifest | `COMPATIBILITY_HOLD` | A stale manifest is cured by deployment (7F KUN-08) |
| FC-07 | `BEYOND_HORIZON` (7F RET-7F-08), including "not determinable" and future-dated events (RET-7F-16) | `RECONCILIATION_REQUIRED` | 7F RET-7F-04 |
| FC-08 | C-11: `OBLIGATION_RETIRED` | `RECONCILIATION_REQUIRED` | 7F HCG-19 |
| FC-09 | C-12: the key is not onboarded for the group | `TRANSPORT_TOPOLOGY_ANOMALY` | 7F TKO-02 |
| FC-10 | `HANDLER_FAILED` where the failure is positively dependency-wide: connection to the owner database, the recovery ledger or the handler-contract store cannot be established or was lost; PostgreSQL reports shutdown, recovery or resource exhaustion (SQLSTATE classes `08`, `53`, `57P`); the commit outcome is unknown because the connection was lost (7F TXA-09); for CON-01 and CON-08 the external store is unreachable, times out or returns a service-wide error | `TRANSIENT_DEPENDENCY` | OD-7G-01; 7F HE-7G-7F-07 |
| FC-11 | `HANDLER_FAILED` not matched by FC-10, where the group's dependency probe (GTE-03) fails immediately after the attempt | `TRANSIENT_DEPENDENCY` | The failure cannot be shown entry-specific while the dependency is unhealthy |
| FC-12 | Every other `HANDLER_FAILED`: constraint failure; a referenced resource not visible in the tenant context (7F TEN-7F-04); an ambiguous guard state (7F EID-06); a domain precondition not met (for example a campaign call with no correlatable job, 7F §28.6); a deadlock or serialization failure that persists beyond the in-attempt retries (RTY-03); an entry-specific external-write rejection of an IC-5 consumer; a handler defect | `RETRYABLE_HANDLER_FAILURE` | OD-7G-01 |

| ID | Rule |
|---|---|
| FCL-01 | Classification is decided by the dispatcher from the 7F outcome, the error category and — only for FC-11 — the dependency probe. It never inspects payload values. |
| FCL-02 | **Default direction.** A handler failure that is not positively dependency-wide is `RETRYABLE_HANDLER_FAILURE` (FC-12). The opposite default would let a deterministic poison event stay pending without bound, which 7A FM-07 forbids. The dependency probe of FC-11 is what prevents an outage from being counted against individual events. |
| FCL-03 | A class is never upgraded to `PERMANENT_CONTRACT_FAILURE` by repetition. Five identical handler failures park the event as poison (§14); they do not relabel it as contract-invalid. |
| FCL-04 | The handler is never executed for an entry of any class other than `RETRYABLE_HANDLER_FAILURE` after the classification is known, and never for deterministic invalid input in order to "prove" that it is permanent. |
| FCL-05 | The classes are disjoint at one evaluation but an entry may change class across deliveries (for example `COMPATIBILITY_HOLD` → processed normally after a deployment). The recovery case records the latest class and the history (§18). |
| FCL-06 | An unknown commit outcome and an ambiguous guard state are both safe to redeliver (7F HE-7G-7F-07). The first is dependency-wide (FC-10) and is not counted; the second is entry-specific (FC-12) and is counted. Neither is ever acknowledged on an assumption. |
| FCL-07 | The safe error category recorded for a failure is a short code from a closed list (for example `CONSTRAINT`, `TENANT_RESOURCE_NOT_VISIBLE`, `GUARD_AMBIGUOUS`, `DOMAIN_PRECONDITION`, `SERIALIZATION_PERSISTENT`, `EXTERNAL_ENTRY_REJECTED`, `HANDLER_DEFECT`, `PAYLOAD_INVALID`, `ENVELOPE_INVALID`, `ENTRY_SHAPE`, `WRONG_FAMILY`, `RETIRED_VERSION`, `UNKNOWN_PAIR`, `BEYOND_HORIZON`, `OBLIGATION_RETIRED`, `KEY_NOT_ONBOARDED`, `CRASH_LOOP`). It never contains payload content, database error text with data, credentials or tenant data (7D DSP-08; 7F NAK-04). |

---

## 11. Authoritative Consumer Failure Count

| ID | Rule |
|---|---|
| CNT-01 | **Authority.** The poison budget of OD-7G-01 is evaluated only against `handler_failure_count`, a durable counter held in the recovery case of the audit-owned ledger (§18). |
| CNT-02 | **Not Redis.** The Redis delivery counter (`XPENDING` delivery count) is never the five-attempt counter, never compared with 5, and never used to decide parking for poison. It is recorded as `max_observed_redis_delivery_count` for diagnostics and feeds only the crash-loop policy (§17). |
| CNT-03 | **Identity.** The counter is scoped by the canonical consumer case identity `(logical_group, event_id, event_type)` (§19). The same event consumed by several groups has one independent counter per group. `organization_id` is carried on the case for security and operations and is never part of a suppression decision: a case of organization A can never count, park or suppress an event of organization B, because `event_id` is unique per event and the organization on the case is copied from that event's validated envelope (TEN-7G-02). |
| CNT-04 | **What increments it.** Exactly one event: a `RETRYABLE_HANDLER_FAILURE` (FC-12) whose failure record has **committed** in PostgreSQL. The increment and the record are one statement in one transaction (RTY-05). |
| CNT-05 | **What never increments it.** The initial delivery by itself; `XAUTOCLAIM` or `XCLAIM`; a transfer of pending ownership; a process crash that left no committed failure record; an infrastructure outage (`TRANSIENT_DEPENDENCY`); an evidence-horizon or retired-obligation classification; an unsupported deployment capability (`COMPATIBILITY_HOLD`); a topology anomaly; a crash-loop suspicion; an operator action; any replay mode other than a failed handler execution inside R2 (TGT-08). |
| CNT-06 | **Bounds.** `0 ≤ handler_failure_count ≤ 5`. The value 5 is fixed by OD-7G-01. It is stored on the case as `failure_budget = 5` when the case is created; it is not a runtime tuning parameter, and changing it is an owner decision. |
| CNT-07 | **Imperfect counting across process death is accepted and stated.** If a worker dies after the handler failed and before the failure record commits, the count is unchanged, so an event may be executed more than five times before it parks. If the commit outcome of the failure record is unknown, the worker does not repeat the record in the same attempt (RTY-06), so one failed attempt can never be counted twice. Neither case affects business safety: every execution runs under the 7F guard and is idempotent (7F CPM-10). The count bounds *recorded* failures; unbounded *unrecorded* deaths are bounded separately by §17. |
| CNT-08 | Two concurrent deliveries of the same event that both fail are two failed processing attempts and may each be recorded. The row lock on the case serialises them, so the count is exact and the fifth-failure transition happens once (RTY-07). |
| CNT-09 | The counter is not reset by a successful retry (the case is then resolved and keeps its history), by a reclaim, by a deployment or by a topology-generation change. A later R2 replay of a parked case starts a new **replay attempt** recorded on the case (`replay_count`); it does not restore automatic retry and does not grant a fresh budget of automatic attempts (TGT-08). |

---

## 12. PEL Reclaim Model

Redelivery in V1 has exactly one automatic mechanism: the **stale-entry sweep**. It serves a crashed consumer's entries, entries whose read reply was lost (7F RDL-10), entries a shutdown left pending (7F SHD-06) and entries left pending after a recorded handler failure (§15).

| ID | Rule |
|---|---|
| RCL-01 | **Mechanism.** Per (physical stream key, logical consumer group), a sweep issues `XAUTOCLAIM <key> <group> <consumer> <min-idle-time> <cursor> COUNT <n>` on the connection to the primary that owns the key, starting at cursor `0-0` and following the returned cursor until it returns `0-0`. One command names one key (7F RDL-02). Normal consumption still uses `XREADGROUP … >` (7F RDL-01, RDL-04); durable reads never carry `NOACK` (7E GRP-07). |
| RCL-02 | **Same pipeline.** Every entry returned by the sweep enters the 7F pipeline at D-01 and is processed under the same validation, classification, tenant, idempotency and `XACK` rules as a first delivery (7F RDL-04, HE-7G-7F-03). Reclaim adds no bypass and no shortcut. |
| RCL-03 | **Reclaim ownership is not business ownership.** Holding a pending entry proves nothing about the effect: a reclaimed entry may already be committed (7F STM-01), may be committed concurrently by its former owner (7F CRP-11), or may never have been started. The owner's guard decides; the sweep relies on 7F CPM-10. |
| RCL-04 | **Who sweeps.** The sweep is run by members of the group itself — every admitted worker, or a dedicated reclaim activity of the same build — under the same handler-contract admission and revalidation as a reader (7F HCG-02 … HCG-04). A process that is not admitted to the group never claims its entries. Worker counts are 7K's. |
| RCL-05 | **Gates.** The sweep runs only while the group's dependency gate is closed (§16) and never on a key that is not onboarded for the group (7F TKO-02). |
| RCL-06 | **Trimmed-prefix pre-check.** Before a sweep issues any claim command on a durable key it reads, with read-only commands, the group's smallest pending ID (`XPENDING <key> <group>`, summary form) and the stream's first entry ID (`XINFO STREAM <key>`). If a pending ID is lower than the first entry ID, the sweep issues **no** claim command on that (key, group) and follows §39. This detects, before any mutation, the case in which entries at the front of the stream were removed while still pending — the only form a missing entry can take through trimming. It does not detect a missing entry inside the current stream range (RCL-07), and 7G does not claim that it does. |
| RCL-07 | **Interior hole; deleted-entry reply.** A pending ID inside the current stream range whose entry is missing can arise only from an ungoverned `XDEL` or an equivalent destruction, which is outside the 7E normal model (7E TF-20); the safe-trim guarantee for the normal model is unchanged. The pre-check does not detect it. In Redis 7.2 `XAUTOCLAIM` removes such a pending ID from the PEL and returns it in its deleted-entries element, and `XCLAIM` likewise removes it. The sweep records each returned ID as a transport-integrity anomaly (§39) immediately. That record is best-effort incident evidence: between the Redis mutation and the durable record there is a residual crash window in which the evidence can be lost. On the SIGNAL key the element is ignored by contract (7E SGR-03); the SIGNAL group has no PEL in V1 (7F SIG-7F-02) and is never swept. |
| RCL-08 | **Delivery count.** After a sweep batch the worker reads the delivery counts of the entries it now owns with the extended form `XPENDING <key> <group> <start> <end> <count> <consumer>` and records the highest value seen on the recovery case when one exists. This is telemetry and crash-loop input only (CNT-02). |
| RCL-09 | **Targeted claim.** `XCLAIM <key> <group> <consumer> <min-idle-time> <id> [<id> …]` is permitted only for (a) a governed repair operation on enumerated IDs (group retirement §38, integrity recovery §39) and (b) the idle-consumer maintenance of RCL-12. It is never the normal redelivery path. |
| RCL-10 | **Safe option subset.** The table below is exhaustive for durable groups. An option is not used merely because Redis exposes it. |
| RCL-11 | **No own-PEL re-read in V1.** A worker does not re-read its own pending entries by explicit ID in order to retry them. A failed entry is retried only when the sweep reclaims it, so there is one redelivery clock (§15). |
| RCL-12 | **Idle consumer names.** `XGROUP DELCONSUMER` is a governed maintenance action (7F SHD-05; 7E GRP-10). A consumer name is removed only when: the deployment platform confirms the instance is terminated; `XINFO CONSUMERS` reports zero pending entries for that name; and the name has been inactive longer than the reclaim idle threshold. Where pending entries remain, they are first transferred by the normal sweep, or by `XCLAIM … JUSTID` to a live member in the maintenance operation. Routine shutdown issues no `DELCONSUMER`. |
| RCL-13 | **Redis baseline.** The sweep uses only Redis 7.2 semantics. `XREADGROUP … CLAIM`, `XNACK`, `XACKDEL`, `XDELEX` and every option introduced after 7.2 are not used (7F §11.2). |
| RCL-14 | The sweep never issues `XADD`, `XDEL`, `XTRIM`, `XGROUP CREATE`, `XGROUP SETID` or `XGROUP DESTROY` (7F CPM-09). Parking is never implemented with `XDEL`. |
| RCL-15 | **Governed-repair preflight.** A governed repair that claims enumerated IDs (RCL-09) first checks, with a read-only `XRANGE <key> <id> <id>` per ID, that each entry exists. An ID whose entry is missing is recorded as a `TRANSPORT_INTEGRITY` case before any claim command names it, so a governed operation never clears a missing ID unrecorded. |

| Command / option | Normal sweep | Governed repair | Disposition and reason |
|---|---|---|---|
| `XAUTOCLAIM` with `<min-idle-time>`, cursor, `COUNT` | **Used** | Used | The default redelivery primitive (7E PEL-02) |
| `XAUTOCLAIM … JUSTID` | Prohibited | Prohibited | Returns no body and does not count the delivery; the sweep must process what it claims |
| `XCLAIM` with `<min-idle-time>` and explicit IDs | Prohibited | **Permitted** (RCL-09) | Targeted, enumerated repair only |
| `XCLAIM … JUSTID` | Prohibited | Permitted only in RCL-12 | Transfers ownership without processing; meaningful only to empty a dead consumer name |
| `XCLAIM … FORCE` | Prohibited | Prohibited | Creates a pending entry for an ID that is not pending: it fabricates an obligation and ownership, and can resurrect an acknowledged entry |
| `XCLAIM … LASTID` | Prohibited | Prohibited | Mutates the group's last-delivered position; it is a replication-internal option and would move the trim watermark input |
| `XCLAIM … RETRYCOUNT` | Prohibited | Prohibited | Overwrites the delivery counter: it fabricates the diagnostic that the crash-loop policy reads |
| `XCLAIM … IDLE` / `TIME` | Prohibited | Prohibited | Overwrites the idle clock: it fabricates the staleness evidence the sweep relies on |
| `XPENDING` (summary and extended, with `IDLE`) | Used (read-only) | Used | Pre-check, delivery counts, enumeration |
| `XINFO STREAM` / `GROUPS` / `CONSUMERS` | Used (read-only) | Used | Pre-check and proofs; never a business input |
| `XRANGE` on a durable key | Not used | Permitted read-only | Source read for backfill and integrity recovery (§33, §39) |

---

## 13. Reclaim Idle Threshold and Cadence

Correctness never depends on these values: a threshold that is too short only produces concurrent duplicate processing, which the owner's guard arbitrates (7F CRP-11, CDP-05); a threshold that is too long only delays recovery. The values below make a healthy handler not routinely stolen.

| ID | Parameter | V1 value | Rule |
|---|---|---|---|
| IDL-01 | `T_start` — local start deadline | 60 s | A worker begins processing a delivered entry within `T_start` of receiving the read or sweep reply. An entry it cannot begin by then is left untouched and pending; it is not started late. This is the consumer analogue of the relay's local deadline (7D LSE-03) and uses a monotonic local timer. |
| IDL-02 | `T_attempt_max` — bound of one processing attempt | 120 s | One attempt — validation, the owner transaction including its in-attempt retries (RTY-03), an IC-5 external write set, the failure record and `XACK` — is bounded by enforced timeouts (statement, transaction, external call). An attempt that reaches the bound is aborted and rolled back; it then counts as a failed attempt under §10. |
| IDL-03 | `T_margin` — safety margin | 120 s | Covers clock granularity, scheduling pauses and the difference between the local timers and the Redis idle clock. |
| IDL-04 | `reclaim_min_idle` — the `XAUTOCLAIM` minimum idle time | **300 s** | **Correctness inequality: `reclaim_min_idle ≥ T_start + T_attempt_max + T_margin`.** Configuration that violates it is rejected at startup. The absolute floor is 60 s. Every member of one group uses the same value; during a change each member uses the larger of the old and new values. |
| IDL-05 | Sweep cadence per (key, group) | every 30 s with random jitter | Each sweep pass scans the whole pending list by cursor. Cadence changes detection latency only. |
| IDL-06 | Sweep batch `COUNT` | 100 | Bounded by the worker's in-flight admission bound (7F RDL-12); a sweep never claims more than the worker can start within `T_start`. |

| ID | Rule |
|---|---|
| IDL-07 | All six values are configuration. The V1 values are conservative startup values, not benchmarks. Production tuning of the threshold, cadence and batch against measured handler latency is a 7K obligation (HE-7K-7G-01) and never changes the inequality of IDL-04. |
| IDL-08 | A change of any timing value never changes poison-budget semantics: the budget counts recorded failures (CNT-04), not elapsed time, sweeps or deliveries. |
| IDL-09 | The idle clock is Redis's own (time since the entry was last delivered or claimed). The sweep never substitutes a client clock and never writes the idle value (RCL-10). |
| IDL-10 | Several members sweeping the same (key, group) concurrently is safe: `XAUTOCLAIM` transfers each stale entry to exactly one caller and resets its idle time, so a second sweep does not see it as stale. |

---

## 14. Consumer Retry Policy (OD-7G-01)

| Recorded genuine failure | Result | Case state after the record |
|---:|---|---|
| 1 | Retry eligible | `OPEN_RETRY`, `handler_failure_count = 1` |
| 2 | Retry eligible | `OPEN_RETRY`, 2 |
| 3 | Retry eligible | `OPEN_RETRY`, 3 |
| 4 | Retry eligible | `OPEN_RETRY`, 4 |
| 5 | **PARK** — no sixth normal-handler execution | `PARKED`, 5, reason `POISON_BUDGET_EXHAUSTED` |

| ID | Rule |
|---|---|
| RTY-01 | **Recovery-case gate.** After D-04 has produced a trusted `event_id` and `event_type`, and before D-09, the dispatcher reads the recovery case of `(logical_group, event_id, event_type)`. The read is mandatory for every entry that is not classified `KNOWN_UNSUBSCRIBED`, and for every entry obtained through the sweep whatever its class. It is a point read on the canonical unique key. A negative result is never cached; an in-memory cache is never the authority for "no case exists". |
| RTY-02 | **Gate outcomes.** No case, or a case in `OPEN_RETRY` or `HOLD`: the pipeline continues. A case in `PARKED`, `REPLAYING` or `RECONCILIATION_PENDING`: the business handler is **not** executed and the entry follows the parked-duplicate path (PAT-07). A case in `RESOLVED`: the pipeline continues — a resolved case is history, the event may legitimately be delivered again, and the owner's guard decides (`ALREADY_COMMITTED`, or processing if the earlier resolution did not commit an effect and the group still owes it). A `RESOLVED` case whose resolution is an explicit terminal rejection (§24.3) is the exception: the handler is not executed and the entry is acknowledged under PAT-07. |
| RTY-03 | **In-attempt retries.** Within one processing attempt the owner transaction MAY be repeated a small bounded number of times (V1: at most 2 repeats) when it fails with a deadlock or serialization failure, inside `T_attempt_max`. These repeats are part of one attempt and are not recorded individually. If the attempt still fails it is one failed attempt (FC-12). |
| RTY-04 | **Failure record.** When an attempt ends as `RETRYABLE_HANDLER_FAILURE`, the owner transaction has already rolled back (7F TXA-08). The worker then runs the **failure-record transaction** against the ledger. It contains no Redis command and no owner-domain statement. |
| RTY-05 | **One atomic statement.** The failure record is an insert-or-update on the canonical identity that, under the row lock of the case: creates the case in `OPEN_RETRY` with `handler_failure_count = 1` if none exists; otherwise, **only if the state is `OPEN_RETRY` or `HOLD`**, sets the state to `OPEN_RETRY` and increments the count; and, when the new count equals `failure_budget`, in the same statement sets the state to `PARKED` with reason `POISON_BUDGET_EXHAUSTED` and `parked_at`. The same transaction stores the replay-complete material (§20) and the origin provenance (§36) whenever the result is `PARKED`. The statement returns the resulting state and count. |
| RTY-06 | **At most one record per attempt.** A worker issues the failure record at most once per processing attempt. If the record fails or its commit outcome is unknown, the worker does not repeat it; the entry stays pending and the count is whatever committed (CNT-07). |
| RTY-07 | **The fifth failure is decided once.** Two workers that both fail the same event at count 4 are serialised by the row lock: the first sets `PARKED` at 5; the second finds the state is no longer `OPEN_RETRY`, changes nothing, reads `PARKED` and takes the parked-duplicate path. Contradictory states for one case are unreachable, the count never exceeds 5, and no handler execution is started for a case that is already `PARKED` (RTY-02). |
| RTY-08 | **After failures 1 – 4** the entry is left pending and is not acknowledged. The worker does nothing further with it; it is retried when the sweep reclaims it (§15). |
| RTY-09 | **After the fifth** the worker follows parking atomicity (§21): the `PARKED` state, the material and the provenance are already committed by RTY-05, and only then is `XACK` issued. |
| RTY-10 | **Success after earlier failures.** When an attempt reaches a 7F acknowledgeable outcome (`DURABLY_COMMITTED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`, `KNOWN_UNSUBSCRIBED`) and the gate found a case in `OPEN_RETRY` or `HOLD`, the worker first commits the case to `RESOLVED` with the matching resolution, and only then issues `XACK`. If that commit fails, no `XACK` is issued; the entry is redelivered, the guard proves `ALREADY_COMMITTED`, and the resolution is completed then. An entry with a non-terminal case is therefore never acknowledged while its case stays open. This narrows 7F XAK-01 without weakening it (CNF-7G-02). |
| RTY-11 | **No effect duplication.** No retry, park or resolution executes an effect outside the owner's guarded transaction. A parked event has, by construction, no committed effect from the failed attempts (each rolled back); whether an effect exists from another path is the guard's knowledge, not the ledger's (RDM-02). |
| RTY-12 | **Poison isolation.** A failing entry never blocks other entries of its stream or group: entries are processed independently (7F CPM-04), a pending entry does not stop `>` reads, and one tenant's failing entry never causes another tenant's entry to be held, parked or acknowledged (7F TEN-7F-08). |

---

## 15. Retry Delay / Backoff

| ID | Rule |
|---|---|
| RTD-01 | **V1 policy: a constant, reclaim-driven delay.** After a recorded failure the entry is simply left pending. Its retry happens when the sweep reclaims it, that is when its Redis idle time reaches `reclaim_min_idle`. The delay between two attempts of one entry is therefore in the interval [`reclaim_min_idle`, `reclaim_min_idle` + one sweep cadence + one scan], measured from its last delivery. With the V1 values that is about 5 to 6 minutes, and a persistently failing event parks about 20 to 25 minutes after its first failure. |
| RTD-02 | **Why constant and not per-entry scheduled.** A per-entry `next_retry_at` would need either a second selection mechanism or a claim that discovers "not due yet", and every such claim resets the entry's idle clock. The constant policy has one clock, needs no due-time column, cannot starve an entry by repeatedly touching it, and is crash-safe by construction: the delay state is the Redis idle time, which survives the worker. Exponential backoff adds nothing for five attempts that the constant delay does not already give. |
| RTD-03 | The delay is deterministic for a given configuration, configurable only through IDL-04 … IDL-06, bounded above by RTD-01, independent of the Redis delivery count, and independent of the failure count. |
| RTD-04 | No worker sleeps holding an entry, a transaction or a connection in order to delay a retry, and no delay is ever a correctness or ordering mechanism (7F ORD-7F-04). |
| RTD-05 | A second stream entry that carries the same event (a republished duplicate) is an independent delivery. It is not delayed by the first entry's failure; if it also fails it is a failed attempt of the same case. This can only bring parking forward, which is safe: parking is lossless and no effect is duplicated. |
| RTD-06 | A dependency gate (§16) suspends sweeps, so time spent with the gate open extends the delay and never consumes budget. |

---

## 16. Infrastructure-Failure Gating

| ID | Rule |
|---|---|
| GTE-01 | Each worker keeps, per logical group, a **dependency gate** in memory with states `CLOSED` and `OPEN`. It is an availability mechanism; correctness never depends on it (compare 7D GATE-01). |
| GTE-02 | **Opening.** The gate opens on the first `TRANSIENT_DEPENDENCY` classification (FC-10, FC-11). One occurrence is enough; there is no threshold to tune. |
| GTE-03 | **Dependency probe.** The probe of a group checks, without touching any event: a trivial statement on the owner database connection path the handler uses; a read of the group's handler-contract record; a trivial statement against the recovery ledger; and, for CON-01 and CON-08, a non-mutating reachability check of the external store. It carries no event data and writes nothing. |
| GTE-04 | **While `OPEN`** the worker issues no `XREADGROUP` and no sweep for the group on any key, so no new entry is moved into the PEL while the handler cannot run. Entries already delivered and not yet started are left pending. Attempts in flight end under their own outcome. |
| GTE-05 | **No budget, no parking.** While the gate is open no failure record is written, no count changes and nothing is parked for poison. An outage therefore never parks a stream and never poisons the events that happened to be in flight. |
| GTE-06 | **Backlog.** Undelivered entries stay in the stream and pending entries stay in the PEL; both are protected from trimming by the watermark (7E TRM-02, TRM-08). Sizing of the retained backlog and catch-up are 7K's (HE-7K-7G-06). |
| GTE-07 | **Closing.** While open, the worker runs the probe with bounded exponential backoff and jitter. On a healthy probe the gate closes and reads and sweeps resume. If the next attempt is again dependency-wide, the gate reopens after at most one attempt per in-flight entry. |
| GTE-08 | **Ledger unavailable.** The recovery ledger is itself a dependency of every durable group: without it the recovery-case gate (RTY-01) cannot be evaluated and no failure can be recorded. If it is unavailable the dependency gate opens. A worker never processes "without the ledger". |
| GTE-09 | **Handler-contract store unavailable.** 7F HCG-04 already makes the member stop reading and deregister; 7G adds only that this is `TRANSIENT_DEPENDENCY` and consumes no budget. |
| GTE-10 | A dependency-wide failure of one group does not open another group's gate. Groups that share the affected dependency open their own gates from their own observations. |

---

## 17. Crash-Loop Safety Policy

A worker that dies before it can report an outcome leaves no failure record, so the OD-7G-01 budget never advances. A deterministic process-crasher could then be redelivered forever. This section bounds that case. It is a technical safety policy, separate from the five genuine handler failures.

| ID | Rule |
|---|---|
| CLP-01 | **Signal.** For an entry obtained by the sweep, `unrecorded_deliveries` = its Redis delivery count minus the delivery count stored on its recovery case at the last durable record of any kind (failure record, hold evaluation, isolation outcome); with no case it is the delivery count itself. The Redis counter is used here as a diagnostic and safety signal only (CNT-02). |
| CLP-02 | **Threshold.** When `unrecorded_deliveries ≥ crash_loop_delivery_threshold` the entry is `CRASH_LOOP_SUSPECTED`. V1 value: **10**, configurable, with a floor of 6 so that it can never coincide with or undercut the budget of 5. With `reclaim_min_idle = 300 s` ten unrecorded deliveries represent at least 45 minutes in which no worker survived the entry. Legitimate inflation (deployments, a lost read reply, a restart during processing) adds one or two deliveries, not ten, and a dependency outage adds none because the gate stops sweeps (GTE-04). |
| CLP-03 | **Isolation.** A suspected entry is not handed to the normal worker pool. The worker that detects it first stores the entry's raw bytes as replay material without decoding them (§20, RPM-06), records a case in `HOLD` with class `CRASH_LOOP_SUSPECTED`, and commits. The entry stays pending and is not acknowledged. |
| CLP-04 | **Pre-recorded isolated attempt.** A dedicated isolation activity processes one suspected entry at a time, in a process that handles nothing else. Before it executes the pipeline it increments and commits `isolation_attempts` on the case. It then runs the unchanged 7F pipeline from D-01. |
| CLP-05 | **Outcome observed.** If the isolated attempt reports any outcome — success, duplicate, any §10 class — the suspicion is cleared: the delivery-count baseline is updated and the entry follows that outcome's normal rule. A reported `RETRYABLE_HANDLER_FAILURE` is recorded and counted like any other. |
| CLP-06 | **No outcome.** If the isolating process dies, the pre-recorded attempt stands without an outcome. When `isolation_attempts` reaches `crash_isolation_limit` (V1 value: **2**, configurable, minimum 1) with no outcome ever observed, the case is parked with reason `CRASH_LOOP` under §21, using the material stored by CLP-03. The handler is not executed again. |
| CLP-07 | A crash-loop park is an operational disposition like any other park (§23): the event is retained in full, visible, and replayable through R2 once the defect is fixed. |
| CLP-08 | The crash-loop bound is `crash_loop_delivery_threshold + crash_isolation_limit` deliveries without a durable outcome. Neither value is the OD-7G-01 budget, and neither is ever added to or compared with `handler_failure_count`. |

---

## 18. Recovery Ledger — Logical Contract (OD-7G-02)

| ID | Rule |
|---|---|
| LDG-01 | **One ledger.** There is one logical, authoritative parking and recovery ledger per region, in PostgreSQL, owned by the Audit / Event Operations bounded context and placed in the existing `audit` schema. It is the authoritative DLQ. |
| LDG-02 | **What it is not.** It is not a universal consumer inbox: it holds no row for an event that was processed without incident, and the absence of a case says nothing about processing. It is not a business-state table and not a replacement for domain idempotency (RDM-02, RDM-03). It is not a mirror of Redis: it records what a worker durably decided, not what Redis currently holds. |
| LDG-03 | **Redis is never the DLQ.** No dead-letter stream, list or key exists as the authoritative parked store. A Redis-only DLQ is prohibited. A Redis structure MAY exist only as a non-authoritative notification that falls through to the ledger. |
| LDG-04 | **Logical components.** The one ledger has six logical components, listed below. A future migration decides whether they are one or several physical relations; they share one owner, one schema, one region and one retention governance, and none is authoritative for anything outside this section. |
| LDG-05 | **Writers.** Rows are written only by event-operations code paths: the dispatcher's failure recorder and parking transaction, the sweep, the publisher-`FAILED` detector, the replay planner and executors, and privileged operator tooling. No owner handler writes it, and no tenant-facing path reads or writes it. |
| LDG-06 | **No payload in normal columns.** Event material is stored only in the replay-material component. No other column holds payload fields, and no error column holds data-bearing error text (FCL-07). |
| LDG-07 | **Append-only history.** State changes of a case are recorded as history entries that are never updated or deleted before the case's retention ends. The original event identity fields of a case are immutable after insert. |

| # | Component | Purpose |
|---|---|---|
| LC-1 | Recovery case | One row per recovery obligation; identity, state, counters, classification, disposition, retention (§18.1) |
| LC-2 | Transport observation | Zero or more per case: each stream entry on which the case's event was observed (physical key, entry ID, topology generation, delivery count, first and last seen, acknowledgement status). Multiple entries never change the case identity (PID-04) |
| LC-3 | Replay material | The immutable replay-complete copy referenced by a case or bound to an operation item (§20); for a **captured source** also the capture record of DSR-12 |
| LC-4 | Origin provenance and backfill grants | The canonical record `O(group, event_id, event_type)` → `origin_contract_generation`, `origin_obligation` (§36); and the immutable backfill grant per (group, `event_id`, `event_type`) (BKL-06, BKL-21) |
| LC-5 | Replay operation and items | The plan, approval, execution state and per-candidate outcome of every replay, backfill, redrive and retirement operation (§42) |
| LC-6 | Case history | Append-only record of every transition, actor, reason reference and outcome (LDG-07) |

### 18.1 Minimum logical fields of a recovery case

| Field | Meaning | Constraint semantics |
|---|---|---|
| `recovery_case_id` | Surrogate identity | Unique, immutable |
| `case_kind` | `CONSUMER`, `CONSUMER_UNIDENTIFIED`, `PUBLISHER_FAILED`, `TRANSPORT_INTEGRITY` | Closed set, immutable |
| `logical_group` | The 7E logical group name; the fixed token `publisher.outbox-relay` for a publisher case | Immutable; part of identity |
| `event_id`, `event_type`, `event_version` | The original event identity from the validated envelope (or the outbox row for a publisher case) | Immutable; `event_id` and `event_type` part of identity; NULL only for `CONSUMER_UNIDENTIFIED` and unresolvable `TRANSPORT_INTEGRITY` cases |
| `identity_digest` | SHA-256 of the raw entry bytes | Identity component of `CONSUMER_UNIDENTIFIED` only |
| `organization_id`, `organization_scope_trusted` | Tenant scope copied from the validated envelope; NULL with `trusted = true` for a platform-scoped event; `trusted = false` when no envelope could be validated | Immutable; never supplied by an operator |
| `stream_family`, `first_physical_key`, `first_redis_entry_id`, `topology_generation` | Where the event was first observed (further observations in LC-2) | Transport metadata only |
| `first_seen_at`, `last_seen_at` | First and latest observation | `last_seen_at ≥ first_seen_at` |
| `handler_failure_count`, `failure_budget` | The authoritative genuine-failure count and its fixed bound | `0 ≤ count ≤ failure_budget`; `failure_budget = 5` |
| `max_observed_redis_delivery_count`, `delivery_count_baseline` | Diagnostics and the crash-loop baseline | `≥ 0`; never compared with the budget |
| `isolation_attempts` | Pre-recorded isolated attempts (§17) | `≥ 0` |
| `failure_class` | Latest recovery class of §10.1 | Closed set |
| `safe_error_category` | Latest safe category code (FCL-07) | Closed list; bounded length; no data |
| `state` | §24 | Closed set; transitions only as in §24 |
| `parked_reason`, `parked_at` | Why and when automatic processing stopped | Both present exactly when the case has ever entered `PARKED` or `RECONCILIATION_PENDING` |
| `origin_contract_generation`, `origin_obligation` | The canonical 7F provenance of the case's event for this group (reference to LC-4) | Required before any R2 replay; `OWED` or `NOT_OWED` |
| `material_ref` | Reference to LC-3 | Required in `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING` |
| `material_state` | `PRESENT`, or `ERASED_UNDER_PRIVACY_RULE` with the erasure reference (RPM-12) | `ERASED_UNDER_PRIVACY_RULE` only in `RECONCILIATION_PENDING` or `RESOLVED` |
| `backfill_grant_ref` | Reference to the backfill grant that makes a `NOT_OWED` event executable for this group (BKL-06) | Present for every case created or attached by R3; never removed while the case is non-terminal |
| `case_class` | Disposition class of §24.4 (`V`, `N`, `I`, `T`, `P`), derived from kind, parked reason, provenance and grant | Derived; decides which terminal resolutions are permitted (MR-18) |
| `disposition`, `disposition_reason_ref`, `disposition_actor`, `disposition_at`, `owner_reconciliation_ref`, `governed_change_ref` | Replay / reconciliation / terminal disposition and its authority | Required in `RESOLVED`; the reason reference is an operator ticket or system reason code, never free text with tenant data; `owner_reconciliation_ref` and `governed_change_ref` are required where §24.4 says so |
| `replay_count`, `last_replay_operation_id`, `last_replay_outcome`, `last_replay_at` | Replay history summary (detail in LC-5) | `replay_count ≥ 0` |
| `transport_ack_state` | `PENDING`, `ACKED`, `ACK_UNCONFIRMED`, `NOT_APPLICABLE` for the latest observed entry | — |
| `resolved_at`, `retention_eligible_at` | Terminal time and the earliest cleanup time | `retention_eligible_at` is NULL while the state is not `RESOLVED`; otherwise `≥ resolved_at + 90 days` |

---

## 19. Parked Case Identity

| ID | Rule |
|---|---|
| PID-01 | **Canonical consumer identity.** A consumer-side case is identified by `(logical_group, event_id, event_type)`. The identity is unique: at most one `CONSUMER` case exists for it, ever, in a region. |
| PID-02 | **Never the Redis entry ID.** A case is never keyed by the entry ID, the stream key, the partition, the topology generation, the consumer name or the delivery count. The same immutable event can occupy several entries through relay republication after an `UNKNOWN` outcome (7D AMB-01), a stale claimant (7D LSE-08), a topology-generation overlap (7E LCY-07) or an operator replay (§32). |
| PID-03 | **One obligation, one case.** All observations of one event for one group attach to the one case. They can never produce two cases with contradictory states for the same logical consumer obligation. |
| PID-04 | **Observations.** Each distinct stream entry on which the event is observed is recorded in LC-2. Observations are transport metadata; adding one never changes the identity, the count rules or the state rules. |
| PID-05 | **Unidentifiable entries.** An entry that fails D-01 … D-04 has no trusted `event_id`. Its case has kind `CONSUMER_UNIDENTIFIED` and identity `(logical_group, identity_digest)`, where the digest is the SHA-256 of the raw entry bytes. Byte-identical duplicates collapse into one case. This digest identifies a recovery case only; it is never a business dedup key (7F EID-02 is unaffected). |
| PID-06 | **Publisher identity.** A publisher-side case has kind `PUBLISHER_FAILED` and identity `(publisher.outbox-relay, event_id, event_type)`; `event_id` is the outbox row `id`. |
| PID-07 | **Integrity identity.** A `TRANSPORT_INTEGRITY` case for a pending ID whose entry is missing has identity `(logical_group, physical_key, redis_entry_id)`. This is the only case kind identified by a transport position, because no event identity is known (§39). |
| PID-08 | **Per group.** In a group move or split the old and the new group each have their own case and their own provenance for the same `event_id` (7F HCG-31 a). |

---

## 20. Replay-Complete Material

| ID | Rule |
|---|---|
| RPM-01 | **Invariant.** A consumer case in `PARKED`, `REPLAYING` or `RECONCILIATION_PENDING` has replay-complete material. The transition into any of those states and the storing of the material commit in the same PostgreSQL transaction, or the transition does not happen. The only exception is a `RECONCILIATION_PENDING` case whose material was erased under RPM-12. |
| RPM-02 | **Definition.** Replay-complete material is the exact stream entry as it was read: the field list — for a well-formed entry the two fields `fmt` and `env` with their exact bytes (7E ENT-01) — plus the SHA-256 of those bytes. It is sufficient to feed the unchanged 7F pipeline at D-01 and to obtain the same classification the transport entry would obtain. |
| RPM-03 | **V1 form.** The material is an immutable copy stored in the recovery ledger in PostgreSQL, in the same region as the case. The physical maximum is bounded by the outbox payload bound plus the envelope (7D §8.1; 7E SIZ-03). |
| RPM-04 | **A reference is acceptable only if it outlives the need.** A case MAY reference a source instead of holding a copy only when that source is immutable and is guaranteed, by an interlock, to outlive the case's replay or reconciliation need. Normal `PUBLISHED` outbox rows are retained only 7 days and therefore never qualify for a consumer case. A `FAILED` outbox row qualifies for its own publisher case exactly while the cleanup interlock of §48 holds. |
| RPM-05 | **No acknowledgement without material.** An entry is never acknowledged for parking because metadata exists. If the material cannot be stored — ledger unavailable, the entry exceeds the configured material bound — the transition fails, no `XACK` is issued and the entry stays pending and visible. |
| RPM-06 | **Raw capture.** Material is captured from the bytes as read, before and independently of decoding, so that an entry that cannot be parsed, or that crashes the decoder, is still preserved exactly. |
| RPM-07 | **Immutability.** Material is never updated, repaired, re-serialized, upcast or normalized. If a later observation of the same case carries different bytes for the same `event_id`, the additional bytes are stored as a further immutable variant on the case and flagged as an integrity anomaly; neither variant is discarded. |
| RPM-08 | **Never Redis, never reconstruction.** Redis is never the retained replay source of a parked case. Material is never reconstructed from logs, audit rows or mutable domain state. |
| RPM-09 | **External store.** If a later physical design places material in object storage, its retention, region and deletion are bound to the ledger row by a governed, transactionally consistent protocol in which the PostgreSQL row is authoritative; an object without its row, or a row without its object, is a detectable defect. The V1 form of RPM-03 needs no such protocol. |
| RPM-10 | **Retention of material.** Material is retained at least as long as the case is non-terminal, and at least as long as any approved or running replay operation references it. After the case is `RESOLVED`, material is retained no longer than the case metadata and MAY be removed earlier under a 7I rule (HE-7I-7G-02). |
| RPM-11 | **Sensitivity.** Material contains the full event envelope and payload and inherits the highest classification of its content. Classification, encryption, redaction, access, and DSR interaction are 7I's (§52.2). Until 7I is frozen the binding minimum is: no tenant-facing access; no copy in logs, metrics, traces or tickets (7E SCY-03); access only through the privileged material-view capability (§40). |
| RPM-12 | **Privacy erasure of material.** Where a frozen privacy rule requires the payload of an unresolved case to be erased, the erasure mechanics are 7I's (HE-7I-7G-03). 7G fixes what must hold: the case is not resolved by the erasure; it moves to `RECONCILIATION_PENDING` with reason `PRIVACY_MATERIAL_ERASED` (T-13); `material_state` becomes `ERASED_UNDER_PRIVACY_RULE` with the erasure reference; and every non-payload field of the case that law and contract permit — identity, group, organization scope, class, provenance, grant, history — is retained. Raw replay is then impossible, so the obligation is decided by the owning domain's reconciliation (R6), never by declaring it terminal in order to delete material. |

---

## 21. Parking Atomicity

There is no distributed transaction between PostgreSQL and Redis (7A TX-02). Parking uses one safe order.

```text
classify PARK_REQUIRED
  → create / update the durable PostgreSQL recovery case        ┐
  → persist replay-complete material and origin provenance      ├ one PostgreSQL transaction
  → COMMIT                                                      ┘
  → XACK the Redis entry
```

| ID | Rule |
|---|---|
| PAT-01 | **Park before acknowledge.** `XACK` for a parked entry is issued only after the transaction that makes the case `PARKED` (or `RECONCILIATION_PENDING`, where §22 permits acknowledgement) with its material has returned a successful commit. |
| PAT-02 | **Prohibited order.** "`XACK`, then create the parking record" is prohibited. A crash between the two would lose the obligation. |
| PAT-03 | **Parking failure never acknowledges.** If the parking transaction fails, or its commit outcome is unknown, no `XACK` is issued. The entry stays pending and pins the trim watermark, as 7F NAK-06 intends. |
| PAT-04 | **Crash after commit, before `XACK`.** The entry is redelivered. The recovery-case gate finds the durable `PARKED` case, the handler is not executed, and the duplicate is acknowledged (PAT-07). |
| PAT-05 | **`XACK` returns 0.** The entry was not pending when the command ran (another member acknowledged it, or group state regressed). The parked case is authoritative and unchanged; nothing is re-run; the observation is recorded (7F XAK-08). |
| PAT-06 | **`XACK` error or lost reply.** The acknowledgement state is unknown. Re-issuing `XACK` for the same ID is safe. If it cannot be confirmed the case records `transport_ack_state = ACK_UNCONFIRMED`; a later delivery of the entry takes PAT-07 and reconciles the transport acknowledgement. No business effect is created or repeated in any branch. |
| PAT-07 | **Parked-duplicate path.** For an entry whose case is `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING` (where the entry's acknowledgement is permitted, BIL-04), or `RESOLVED` with a terminal rejection: the worker executes no business handler; records the observation in LC-2 in a short transaction; compares the entry's digest with the stored material and stores a differing variant under RPM-07; commits; and then issues `XACK`. If the short transaction fails, no `XACK` is issued. |
| PAT-08 | **Idempotent.** Parking an already-parked case changes nothing. Any number of duplicates, in any order and concurrently, converge on one case and each is acknowledged at most after the durable record exists. |
| PAT-09 | **Never `XDEL`.** Parking never deletes a stream entry. Removal of acknowledged entries remains exclusively the 7E safe-trim mechanism (7E TRM-01 … TRM-11). |
| PAT-10 | **Trimming after parking is safe.** Once the entry is acknowledged by this group, 7E may trim it when every other group has also acknowledged it. The obligation of this group survives in the ledger with its material (RPM-01); this is the release of the trim pin that 7F HE-7G-7F-04 requires. |
| PAT-11 | **Scope.** A parking acknowledgement affects only the parking group (7E ACK-03). Other groups' obligations for the same entry are untouched. |

---

## 22. Immediate Parking and Holds

| Class / reason | Entered from | Handler retries spent | Case state | Material stored | `XACK` | Automatic re-evaluation |
|---|---|---:|---|---|---|---|
| `PERMANENT_CONTRACT_FAILURE` (FC-01 … FC-05) | Classification | 0 | `PARKED` | Yes, in the same transaction | Yes, after commit | None |
| `POISON_BUDGET_EXHAUSTED` | Fifth recorded failure | 5 | `PARKED` | Yes | Yes, after commit | None |
| `CRASH_LOOP` | §17 | 0 recorded | `HOLD` → `PARKED` | Yes (at suspicion) | Only after `PARKED` commits | Isolation only |
| `COMPATIBILITY_HOLD` (FC-06) | Classification | 0 | `HOLD` | Not yet (the entry is still in the stream) | **No** | At every reclaim: classification only |
| `COMPATIBILITY_HOLD` expired | `HOLD` older than `compat_hold_max_age` | 0 | `PARKED`, reason `UNSUPPORTED_VERSION` | Yes | Yes, after commit | None |
| `RECONCILIATION_REQUIRED` — `BEYOND_HORIZON`, non-Billing (CON-04, CON-07, CON-10) | Owner adapter result | 0 | `RECONCILIATION_PENDING` | Yes | Yes, after commit | None |
| `RECONCILIATION_REQUIRED` — `BEYOND_HORIZON`, Billing (CON-06) | Owner adapter result | 0 | `RECONCILIATION_PENDING` | Yes | **No**, until Billing's terminal decision is recorded (§35) | None |
| `RECONCILIATION_REQUIRED` — `OBLIGATION_RETIRED` | Classification C-11 | 0 | `RECONCILIATION_PENDING` | Yes | Yes, after commit | None |
| `TRANSPORT_TOPOLOGY_ANOMALY` — key not onboarded (FC-09) | Classification C-12 | 0 | `HOLD` | No | **No** | At every reclaim, after onboarding |
| `TRANSPORT_TOPOLOGY_ANOMALY` — missing entry | §39 | 0 | `PARKED` (kind `TRANSPORT_INTEGRITY`) | None exists | Not applicable | None |

| ID | Rule |
|---|---|
| IMP-01 | A deterministic invalid entry is parked at its first classification. It is never passed to the business handler, and it never spends handler retries to prove that it is permanent. |
| IMP-02 | **Compatibility hold.** A held entry stays pending and unacknowledged. At each reclaim only D-01 … D-05 are repeated; the hold evaluation updates the case (`last_seen_at`, delivery-count baseline) and consumes no budget. If the entry now classifies as `SUBSCRIBED_SUPPORTED` it is processed normally; if it now classifies as `KNOWN_UNSUBSCRIBED` the case is resolved and the entry acknowledged (RTY-10). |
| IMP-03 | **Hold is bounded.** A compatibility hold older than `compat_hold_max_age` (V1 value: 24 hours, configurable) is parked with reason `UNSUPPORTED_VERSION`, with the exact material, so that it can be replayed once compatible code exists. The bound exists because a pending entry pins the whole stream's trim watermark. |
| IMP-04 | **Key not onboarded.** The worker stops reading and sweeping that key for the group (a key-level gate) and raises an alert-grade observation. Entries already read from it are held. This is cured by completing 7F TK-1 … TK-6, never by parking each entry, and it never falls back to "known-unsubscribed" (7F TKO-02). |
| IMP-05 | **Reconciliation-required.** The normal handler is not run again. The case moves directly to `RECONCILIATION_PENDING`, which is the durable hand-off to the owner's rebuild or reconciliation mode (§34). |
| IMP-06 | Every immediate park, hold and hand-off is recorded in case history with its class, safe category and actor (the worker identity), and is emitted as a semantic signal (§52.3). None is silent. |
| IMP-07 | A validator defect in a deployment could park valid events as contract-invalid. That is recoverable without loss: the material is exact, and a bulk R2 replay after the fix processes them (§31). The rate of immediate parks per group is therefore an alert-grade signal (§52.3). |

---

## 23. Parking Does Not Mean Business Failure

| ID | Rule |
|---|---|
| PBF-01 | Parking is an operational disposition. It means exactly: the normal consumer obligation is no longer allowed to keep retrying this delivery automatically. |
| PBF-02 | Parking does not mean, and no component may infer from it, that the business fact is invalid, that the customer operation failed, that Billing should reverse anything, that domain state should be mutated, or that the original event is deleted. |
| PBF-03 | The producer's committed fact stands. The outbox row, the audit trail and every other group's processing are unaffected. |
| PBF-04 | Decisions about the business consequence of an unprocessed obligation belong to the owning domain's reconciliation. 7G supplies the durable case, the exact material and the mechanics; it makes no domain decision and calculates nothing. |

---

## 24. Recovery State Machine

### 24.1 States

| State | Meaning | Automatic handler retry | Redis entry | Cleanup-eligible |
|---|---|---|---|---|
| `OPEN_RETRY` | 1 … 4 genuine failures recorded; the sweep will retry | Yes | Pending | No |
| `HOLD` | Pending and unacknowledged; waiting for a deployment, an onboarding or an isolation outcome | No (classification or isolation only) | Pending | No |
| `PARKED` | Automatic processing has stopped; exact material retained; waiting for an explicit replay or disposition | No | Acknowledged or acknowledgement unconfirmed | No |
| `REPLAYING` | An approved operation holds the case while it executes | No | — | No |
| `RECONCILIATION_PENDING` | Handed to the owning domain's rebuild or reconciliation mode | No | Acknowledged, except Billing (§35) | No |
| `RESOLVED` | Terminal: the obligation is completed, reconciled or explicitly dispositioned | No | Acknowledged or not applicable | Yes, at `retention_eligible_at` |

### 24.2 Transitions

| # | From → To | Actor | Preconditions | Durable write | `XACK` allowed | Normal retry afterwards |
|---:|---|---|---|---|---|---|
| T-01 | (none) → `OPEN_RETRY` | Worker (failure recorder) | First recorded `RETRYABLE_HANDLER_FAILURE` | Case inserted, count = 1 | No | Yes |
| T-02 | `OPEN_RETRY` → `OPEN_RETRY` | Worker | Recorded failure 2 … 4 | Count incremented | No | Yes |
| T-03 | `OPEN_RETRY` → `PARKED` | Worker | Recorded failure 5 (RTY-05) | State, reason, material, provenance | Yes, after commit | No |
| T-04 | (none) → `PARKED` | Worker | `PERMANENT_CONTRACT_FAILURE` | Case, material, provenance where the identity is trusted | Yes, after commit | No |
| T-05 | (none) / `OPEN_RETRY` → `HOLD` | Worker | `COMPATIBILITY_HOLD`, key not onboarded, or crash-loop suspicion | Case; material for crash-loop | No | No |
| T-06 | `HOLD` → `OPEN_RETRY` | Worker | The entry became processable and its attempt failed genuinely | Count = 1 (or incremented) | No | Yes |
| T-07 | `HOLD` → `PARKED`; in a group retirement also `OPEN_RETRY` → `PARKED` | Worker / isolation; the retirement executor (GR-6) | Hold expired (IMP-03) or isolation limit reached (CLP-06); or a governed park of a still-pending entry during retirement | State, reason, material | Yes, after commit | No |
| T-08 | (none) / `OPEN_RETRY` / `HOLD` → `RECONCILIATION_PENDING` | Worker | `RECONCILIATION_REQUIRED` | State, reason, material, provenance | Yes after commit; Billing: no (§35) | No |
| T-09 | `OPEN_RETRY` / `HOLD` → `RESOLVED` | Worker | A 7F acknowledgeable outcome was reached (RTY-10) | Resolution = the outcome | Yes, after commit | Not applicable |
| T-10 | `PARKED` → `REPLAYING` | R2 executor | Approved operation bound to the case; compare-and-swap on state | Operation reference | — | No |
| T-11 | `REPLAYING` → `RESOLVED` | R2 executor | Durable outcome `PROCESSED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`, `NOT_OWED` or `KNOWN_UNSUBSCRIBED` | Resolution, outcome | — | Not applicable |
| T-12 | `REPLAYING` → `PARKED` | R2 executor | Outcome `PARKED_AGAIN`, `UNSUPPORTED_VERSION`, `PROVENANCE_MISSING`, `SOURCE_MISSING` or `CANCELLED` before execution; or executor recovery after a crash found no committed effect | Outcome recorded; `replay_count` incremented | — | No |
| T-13 | `REPLAYING` / `PARKED` → `RECONCILIATION_PENDING` | R2 executor; owning domain's reconciliation path; the 7I erasure procedure | Outcome `BEYOND_HORIZON` or `OBLIGATION_RETIRED`; an explicit hand-off requested by the owning domain; or a privacy erasure of the material (RPM-12) | Outcome, reason | — | No |
| T-14 | `RECONCILIATION_PENDING` → `RESOLVED` | Owning domain's reconciliation, through event-operations tooling | The owner recorded a durable terminal decision | Disposition `OWNER_RECONCILED` or `SUPERSEDED_BY_OWNER_RECONCILIATION`, owner reference | Billing: yes, now (§35) | Not applicable |
| T-15 | `PARKED` → `RESOLVED` | An actor holding the authority that §24.4 requires for the case's class | A class-permitted terminal resolution with every reference §24.4 requires; refused otherwise (DAU-01 … DAU-09) | Disposition, reason reference, actor, and the owner or governed-change reference where required | — | Not applicable |
| T-16 | `PARKED` → `REPLAYING` → `RESOLVED` / `PARKED` (publisher case) | Repair publisher | §28 | §28 | Not applicable | No |
| T-17 | (none) → `PARKED` or `RECONCILIATION_PENDING`, by R3 | R3 executor | An R3 item ended in a result that needs later recovery (BKL-14); no case exists for the identity | Case, material, provenance, backfill-grant link, history — in the same transaction as the item result | — | No |
| T-18 | `RESOLVED` → `PARKED` or `RECONCILIATION_PENDING`, by R3 only | R3 executor | A case exists that is `RESOLVED` with a resolution other than a terminal rejection; a later R3 item for the same identity, under a backfill grant, ended in a result that needs recovery (BKL-15) | New history entry; state, reason, material, grant link; `resolved_at` and `retention_eligible_at` cleared | — | No |

### 24.3 Terminal resolutions

| Resolution | Reached by | Meaning |
|---|---|---|
| `PROCESSED` | T-09, T-11 | The handler committed the effect now |
| `ALREADY_COMMITTED` | T-09, T-11 | The owner's guard proved earlier completion |
| `NOT_APPLICABLE` | T-09, T-11 | The owner's authoritative state shows no target (7F XAK-04) |
| `NOT_OWED` / `KNOWN_UNSUBSCRIBED` | T-09, T-11 | The group did not owe the event (origin provenance or classification) |
| `OWNER_RECONCILED` | T-14 | The owning domain completed its rebuild or reconciliation for this obligation |
| `SUPERSEDED_BY_OWNER_RECONCILIATION` | T-14, T-15, always with an owning-domain reconciliation reference (DAU-04) | The owner's reconciliation made processing this event unnecessary |
| `FIX_FORWARD_NO_REDRIVE` | T-15 (publisher case) | The fact is carried forward by a governed fix; the original row is not redriven |
| `REDRIVEN` | T-16 | A publisher `FAILED` row was durably republished by the repair publisher |
| `PERMANENTLY_REJECTED_WITH_REASON` | T-15, only for the classes §24.4 permits | An explicit, reasoned, authorized terminal rejection of a case that cannot represent a valid executable obligation — a **terminal rejection** in the sense of RTY-02 |
| `OBLIGATION_GOVERNED_AWAY` | T-15, only inside a governed retirement operation (§38, DAU-05) | The consumer obligation was formally removed by an owner-approved registry change — also a terminal rejection |

| ID | Rule |
|---|---|
| RSM-01 | No transition exists other than those of §24.2. In particular: there is no transition out of `RESOLVED` except the single governed reopening T-18, which only an R3 item under a backfill grant can take and which never applies to a terminal rejection; there is no transition from `PARKED` back to `OPEN_RETRY` (automatic retry is never restored); and no transition deletes a case. |
| RSM-02 | Every transition is a compare-and-swap on the current state under the case's row lock and writes a history entry (LC-6) in the same transaction. |
| RSM-03 | There is no silent terminal state. No resolution means "dropped": each names a completed effect, a proven absence of obligation, an owner decision, or an explicit reasoned rejection with a named actor. |
| RSM-04 | No state loses the obligation: in every non-terminal state either the entry is still pending in Redis, or the ledger holds the exact material (RPM-01), or both; the one exception is a privacy erasure, after which the case itself stays unresolved for the owner's reconciliation (RPM-12). |

### 24.4 Terminal-disposition authority

Parking is an operational disposition (§23). Ending a parked case without processing it can end a business obligation, and that is not an event-operations decision. Terminal dispositions are therefore constrained by the **class** of the case.

| Class | Definition | Terminal resolutions permitted | Authority and references required |
|---|---|---|---|
| `V` — valid obligation | A `CONSUMER` case with a trusted identity whose origin is `OWED`, or `NOT_OWED` with a backfill grant, parked for `POISON_BUDGET_EXHAUSTED`, `CRASH_LOOP`, `UNSUPPORTED_VERSION` or `BACKFILL_HANDLER_FAILED`, or in `RECONCILIATION_PENDING` for any reason | `PROCESSED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE` (only through R2); `OWNER_RECONCILED`, `SUPERSEDED_BY_OWNER_RECONCILIATION`; `OBLIGATION_GOVERNED_AWAY` | R2: an approved operation. Owner resolutions: the **owning domain's** reconciliation path under `recovery.reconciliation.record`, with an owning-domain reconciliation reference. Governed-away: only inside an approved retirement operation, with the governed registry-change reference and the owner's approval reference. **`PERMANENTLY_REJECTED_WITH_REASON` is not available for this class to any actor.** |
| `N` — proven not owed | A `CONSUMER` case whose canonical origin is `NOT_OWED` and that has no backfill grant | `NOT_OWED`, `KNOWN_UNSUBSCRIBED` | R2, or `recovery.case.disposition`; the ledger verifies the origin record and the absence of a grant |
| `I` — contract-invalid | A case parked for `PERMANENT_CONTRACT_FAILURE` (FC-01 … FC-05), including every `CONSUMER_UNIDENTIFIED` case | `PERMANENTLY_REJECTED_WITH_REASON`; or any R2 result if a later build can process the material | `recovery.case.disposition`, a recorded proof category, and a re-validation at disposition time that still fails (DAU-09). Where the identity is trusted and the origin is `OWED`, additionally an acknowledgement reference from the owning (consuming) domain |
| `T` — transport integrity | A `TRANSPORT_INTEGRITY` case | `PERMANENTLY_REJECTED_WITH_REASON` | `recovery.group.operate` with the incident-reconciliation reference of DGL-05. If the event identity is recovered, the obligation continues as a `CONSUMER` case of its own class |
| `P` — publisher | A `PUBLISHER_FAILED` case | The four dispositions of §27 | `recovery.publisher.redrive`; `FIX_FORWARD_NO_REDRIVE` and `PERMANENTLY_REJECTED_WITH_REASON` need the producing owner's reference; `SUPERSEDED_BY_OWNER_RECONCILIATION` needs an owning-domain reconciliation reference |

| ID | Rule |
|---|---|
| DAU-01 | **Class-aware.** A terminal disposition is permitted only if the pair (case class, resolution) appears in the table above and every required reference is present. Any other request is refused and the refusal is audited. |
| DAU-02 | **A valid obligation is never discarded by event operations.** A generic event-operations actor MUST NOT terminally resolve a class `V` case. A valid owed event that is parked — for `POISON_BUDGET_EXHAUSTED`, a handler defect, an unmet domain precondition, a crash loop or a valid entry-specific external failure — ends only by: a successful replay or an `ALREADY_COMMITTED` proof; the owning domain's reconciliation; an owning-domain approved supersession; or the governed retirement of the handler or group obligation with the required owner approval. |
| DAU-03 | **Permanent rejection is narrow.** `PERMANENTLY_REJECTED_WITH_REASON` may be used without executing an owner handler only where the case cannot represent a valid executable consumer obligation: an unrecoverably malformed entry, an impossible invalid envelope or profile, or an explicitly proven permanent contract-invalid event (class `I`), and a transport-integrity case whose identity cannot be recovered (class `T`). A trusted valid event that merely failed its handler five times is class `V`, and this resolution is not available for it. |
| DAU-04 | **Supersession needs the owner.** `SUPERSEDED_BY_OWNER_RECONCILIATION` and `OWNER_RECONCILED` require an owning-domain reconciliation reference recorded by the owning domain's reconciliation path. An operator reason or ticket alone is insufficient. |
| DAU-05 | **Governed-away is not a free-form disposition.** `OBLIGATION_GOVERNED_AWAY` is valid only inside an approved group- or obligation-retirement operation (§38), bound to the governed 7B / 7E registry change and the owner's approval of it. It cannot be recorded on a parked case outside such an operation. |
| DAU-06 | **Capability scope.** `recovery.case.disposition` permits exactly: `PERMANENTLY_REJECTED_WITH_REASON` on a class `I` case, and `NOT_OWED` / `KNOWN_UNSUBSCRIBED` on a class `N` case. It does not permit resolving a parked case in general, and it permits nothing on a class `V` case. 7I binds principals to capabilities; it cannot widen which transitions exist. |
| DAU-07 | **Enforced in the ledger.** The permitted (class, resolution, required reference) combinations are enforced by the ledger's own constraints or guarded functions (MR-18), not only by tooling, so that no principal with write access can record a prohibited disposition. |
| DAU-08 | **Class is derived, not chosen.** `case_class` is computed from the case kind, the parked reason, the origin provenance and the grant. An operator cannot set or change it. A class changes only when the facts change — for example a class `I` case whose material a later build processes. |
| DAU-09 | **Re-validation before a contract-invalid rejection.** Before a class `I` case is rejected, the tooling runs D-01 … D-07 on the stored material with the current build. If the material now validates, the rejection is refused and the case is an R2 candidate. |

---

## 25. Retention and Cleanup (OD-7G-03)

| ID | Rule |
|---|---|
| PRT-01 | **90 days after resolution.** Generic parked-event, recovery and replay metadata — recovery cases, transport observations, case history, replay operations and their items — is retained for at least 90 days after the case (or operation) reaches a terminal state. `retention_eligible_at = resolved_at + 90 days`. |
| PRT-02 | **Unresolved cases never age out.** A case in `OPEN_RETRY`, `HOLD`, `PARKED`, `REPLAYING` or `RECONCILIATION_PENDING` has no `retention_eligible_at` and is never selected by cleanup, however old it is. Ninety days of age is not a disposition. |
| PRT-03 | **This is not a replay window.** The 90-day figure is metadata retention only. It grants no consumer a 90-day raw-replay window; each target is capped by its own evidence horizon (§34). In particular a parked CRM case older than 30 days is retained and is **not** replayable through the CRM handler. |
| PRT-04 | **Retention separation (7A §32.3).** Ledger retention is independent of outbox cleanup (7 / 30 days), stream retention (7E), dedup-ledger retention (7F §31), webhook dead-letter retention (6J) and audit retention. None implies another. |
| PRT-05 | **Audit history.** The immutable audit records of operator and system recovery actions (§40) live in the frozen audit boundary and follow its separately frozen retention (5J §20), not the 90 days of PRT-01. Deleting a recovery case never deletes its audit records. |
| PRT-06 | **Privacy interaction.** A privacy-erasure requirement is never satisfied by declaring a valid business obligation terminal, and an obligation is never silently dropped to permit material deletion. Payload-erasure mechanics are 7I's (HE-7I-7G-03); the case follows RPM-12: it stays unresolved in `RECONCILIATION_PENDING`, the erasure is recorded, and the non-payload recovery metadata and the owner's reconciliation state that law and contract permit are retained. This is a controlled 7I hand-off, not an owner decision. |

| ID | Cleanup rule |
|---|---|
| PCL-01 | Cleanup is status-aware. It selects only rows with `state = RESOLVED` and `retention_eligible_at <= now()`. |
| PCL-02 | Cleanup never deletes: an unresolved case; a case referenced by an operation that is not terminal; a case whose material or provenance is still required by another case or operation; an origin provenance record or a backfill grant that fails the retirement proof of §36.2; a captured source that an operation still references. |
| PCL-03 | Replay operations and their items become eligible 90 days after the operation is terminal (`COMPLETED`, `CANCELLED`, `STOPPED`) and no item references a non-terminal case. A backfill grant is never deleted with its operation: it is a record of LC-4 with its own lifetime (BKL-21). Material that a recovery case references is retained with that case, not with the operation that first stored it. |
| PCL-04 | Cleanup runs under a privileged maintenance capability, in bounded batches, and writes an audit record of what it removed (counts and identity ranges, never material). Schedules and batch sizes are 7K's. |
| PCL-05 | Cleanup never reads Redis and never uses Redis state as an eligibility criterion, with the single exception of the provenance retirement proof (§36.2), which is a separate governed run. |
| PCL-06 | Cleanup of the ledger never deletes an outbox row, and outbox cleanup never deletes a ledger row (§48). |

---

## 26. Publisher Normal Retry Policy (closes 7D HO-7G-02)

| ID | Rule |
|---|---|
| PUB-01 | **Final V1 relay retry timing.** The relay keeps calling `audit.fn_mark_outbox_failed(id, relay_identity, safe_code, NULL)`. With `p_next_attempt_at = NULL` the executed function sets `available_at = NOW() + 30 seconds` on the database clock (`077_5J1`; 7D PHY-07, POL-03). The 30-second constant delay is the final V1 publisher retry delay. 7G passes no explicit `p_next_attempt_at`. |
| PUB-02 | **Why it is kept.** Nothing in the repository requires another value: under the frozen 7E classification the V1 transport produces no entry-specific rejection (7E CLS-01), so the delay applies only to deferrals (7D DSP-03), which are additionally bounded by the transport availability gate (7D GATE-03) — during an outage the relay does not claim at all. An exponential schedule would add configuration and no safety. A change needs benchmark or production evidence and is a governed 7G / 7K change; it needs no migration, because the parameter already exists. |
| PUB-03 | **`max_attempts` is a bound on claims, not on failures.** The per-row default 10 (`CHECK` 1 … 20) is unchanged and is never set or altered by the relay. It is compared with `attempt_count`, which every claim increments (7D PHY-01). It is therefore **not** "ten genuine publication failures" and no document, metric or runbook may describe it so (§29). |
| PUB-04 | **Terminal path unchanged.** Only a `ROW_REJECTED` outcome may reach the terminal branch of `fn_mark_outbox_failed` (7D DSP-03, DSP-04). `PUBLISHED` and `FAILED` stay terminal for the normal relay: the claim predicate cannot select them and the relay never writes to them (7D LIF-05). No PostgreSQL transaction spans Redis I/O (7D CLM-03). |
| PUB-05 | **Expected V1 volume.** Because 7E enumerates zero `ROW_REJECTED` categories (CLS-01), no transport outcome moves a row to `FAILED` in V1. A `FAILED` row can arise only from a manual `app_platform_admin` intervention (7D DSP-03) or after a future governed 7E amendment. The disposition process below exists regardless, so that any such row is never orphaned. |
| PUB-06 | Publisher retry state stays in the outbox (domain A, §9). The recovery ledger records only the terminal disposition of a `FAILED` row; it never schedules, counts or drives a normal relay attempt. |

---

## 27. Publisher `FAILED` Disposition (OD-7G-04; closes 7D HO-7G-01, 7E HE-7G-02)

| ID | Rule |
|---|---|
| PFD-01 | **Detection.** An event-operations detector periodically selects outbox rows with `status = 'FAILED'` (read-only; `idx_outbox_status`) and inserts, if absent, one `PUBLISHER_FAILED` recovery case per row in state `PARKED` with reason `PUBLISHER_TERMINAL_FAILED`. The case copies `event_id`, `event_type`, `event_version`, `organization_id`, the row's `attempt_count`, `max_attempts`, `last_attempt_at` and its safe `last_error` category. It copies no payload. |
| PFD-02 | **Never automatic.** No component automatically resets, reclaims, republishes or redrives a `FAILED` row. No job, timer, health recovery or deployment causes a redrive. |
| PFD-03 | **The row is never mutated.** A `FAILED` row is never set back to `PENDING` or `CLAIMED`, its `attempt_count`, `max_attempts`, `available_at` and `last_error` are never changed, and its envelope columns are never written (7D LIF-07). The `UPDATE` grant of `app_platform_admin` ("manual/emergency intervention only", `077_5J1`) is not part of any 7G procedure. |
| PFD-04 | **Explicit dispositions.** Every `FAILED` row receives exactly one terminal disposition from the closed set below, recorded on its case by a privileged actor with a reason reference and an audit record. There is no implicit, default or silent disposition, and no `DROP`. |
| PFD-05 | **Review before disposition.** Before any disposition the operator records the root-cause review. The review inspects at least: the safe `last_error` category; the event contract (is the pair in the manifest, is the row conformant); the current transport compatibility (route present, capability gate healthy); the claim history (§29); and the recovery history of the case. |
| PFD-06 | **Not deleted before disposition.** A `FAILED` row is retained until its case holds a recorded terminal disposition (7D CLN-04; §48). |
| PFD-07 | **Handler-contract cutover.** A `FAILED` row of an event type affected by a 7F cutover blocks CUT-5c until its publisher case exists with a recorded disposition or the row is bound to its pre-cutover obligation by its origin provenance (7F HCG-22 d, HCG-28). 7G satisfies this through PFD-01 and §36. |

| Disposition | Meaning | Effect on the outbox row | Case result |
|---|---|---|---|
| `REDRIVE_APPROVED` | The cause is removed and the original event must still reach the transport | Unchanged, stays `FAILED` | §28; `RESOLVED` / `REDRIVEN` on success |
| `FIX_FORWARD_NO_REDRIVE` | The owning producer carries the fact forward through a governed fix (for example a corrected later event); the original bytes are not published | Unchanged | `RESOLVED` / `FIX_FORWARD_NO_REDRIVE` |
| `SUPERSEDED_BY_OWNER_RECONCILIATION` | The owning domain's reconciliation has made publication of this event unnecessary | Unchanged | `RESOLVED` / `SUPERSEDED_BY_OWNER_RECONCILIATION` |
| `PERMANENTLY_REJECTED_WITH_REASON` | The row can never be validly published (for example a non-conformant row that no consumer could accept) and the producer owner accepts that explicitly | Unchanged | `RESOLVED` / `PERMANENTLY_REJECTED_WITH_REASON` |

---

## 28. Publisher `FAILED` Redrive

| ID | Rule |
|---|---|
| PRD-01 | A redrive runs only for a case whose disposition is `REDRIVE_APPROVED`, under an approved operation (§42) with the `recovery.publisher.redrive` capability (§40). |
| PRD-02 | **Repair publisher.** The redrive is performed by a privileged **repair publisher**, a component separate from the relay loop. It reads the `FAILED` row with a plain `SELECT`; it never calls `fn_claim_outbox_events`, `fn_mark_outbox_published` or `fn_mark_outbox_failed`, and it issues no `UPDATE` or `DELETE` on the outbox. |
| PRD-03 | **Same envelope.** It materializes the envelope from the row's eight envelope columns exactly as the relay does (7D §20): same `event_id` (the row `id`), same `event_type`, `event_version`, `organization_id`, `aggregate_type`, `aggregate_id`, `payload`, `occurred_at`. It adds, removes and rewrites nothing. |
| PRD-04 | **Same acceptance contract.** It publishes through the frozen 7E durable transport adapter — exact-type route, `XADD` followed by same-connection `WAITAOF 1 1` — and treats only a 7E `CONFIRMED` outcome as success (7E §23, CL-18). It writes only to an onboarded key of a live generation (TPG-03) and passes relay publication admission before the write (7F HCG-26). |
| PRD-05 | **The original row stays `FAILED`.** After a confirmed redrive the outbox row is unchanged. Its history remains visible exactly as it happened; nothing pretends the row never failed. |
| PRD-06 | **No new fact.** No new outbox row is inserted. A redrive creates no second business fact, no new `event_id` and no new producing transaction. |
| PRD-07 | **Recorded in the ledger.** The confirmed redrive is recorded on the publisher case: the operation, the actor, the transport position (key and entry ID, as transport metadata), the time and the outcome; the case becomes `RESOLVED` / `REDRIVEN`. |
| PRD-08 | **Failure.** If the redrive ends in any outcome other than `CONFIRMED` — including `UNKNOWN` — the case returns to `PARKED` with the outcome recorded, the row stays `FAILED`, and nothing further happens. There is no automatic loop: another attempt needs another explicit repair action. An `UNKNOWN` outcome may have appended the entry; a later explicit redrive then produces a duplicate of the same `event_id`, which consumers absorb. |
| PRD-09 | **Provenance.** The redriven entry is classified by each group from its canonical origin provenance, never from its new Redis ID (§36). |
| PRD-10 | **Consumers.** Every group subscribed to the event's family receives the redriven entry through the normal 7F pipeline; none is bypassed and none is targeted. |

---

## 29. Claim-Inflated Outbox Attempt Counts (closes 7D HO-7G-05)

| ID | Rule |
|---|---|
| CIA-01 | `attempt_count` is increased by every claim: the first claim, a reclaim after lease expiry, a claim that ended in a worker crash, and a claim deferred during an outage (7D PHY-01, LSE-07). A row can therefore reach `FAILED` on its first real `ROW_REJECTED` after earlier claims inflated the count. |
| CIA-02 | No reviewer, tool or rule may assume `attempt_count` equals the number of genuine publication failures, or that a `FAILED` row was rejected `max_attempts` times. |
| CIA-03 | The disposition review (PFD-05) therefore decides from the safe last error, the event contract, the current transport compatibility, the root cause and the recovery history — never from `attempt_count` alone. |
| CIA-04 | This is one reason redrive is never automatic: a row that failed once after nine infrastructure-inflated claims, and a row genuinely rejected ten times, are indistinguishable in the row and need a human or governed system judgement. |
| CIA-05 | 7G requests no schema change to separate the two counts. If a future governed migration adds a genuine-rejection counter, PFD-05 uses it; nothing in 7G depends on it. |

---

## 30. Replay Modes

"Replay" is never one operation. Seven modes exist; each has its own source, target, trigger and authority.

| Mode | Name | Source | Target | Trigger | Fan-out |
|---|---|---|---|---|---|
| R1 | Consumer PEL retry / reclaim | The same Redis entry | The same logical group | Automatic, bounded (§12 – §17) | None |
| R2 | Parked consumer recovery replay | Ledger material of one consumer case | Exactly that case's logical group, through an internal path | Explicit, approved operation | None: no stream write |
| R3 | Future-consumer backfill | An approved immutable source and range | Exactly one logical group, through the internal path | Explicit, approved plan | None: no stream write |
| R4 | Disaster / repair replay of retained `PUBLISHED` rows | Immutable outbox rows | The frozen 7E transport (all subscribed groups) | Explicit, approved operation after an outside-model fault | All groups of the family, by design |
| R5 | Publisher `FAILED` repair / redrive | The immutable `FAILED` outbox row | The frozen 7E transport (all subscribed groups) | OD-7G-04 explicit repair | All groups of the family, by design |
| R6 | Owner rebuild / reconciliation | Owner-domain authoritative state and archives | The owning domain's own rebuild path | Owner decision; hand-off from `RECONCILIATION_PENDING` | None |
| R7 | Public webhook delivery replay | A `webhooks.webhook_deliveries` row | One webhook endpoint | The frozen 6J route (§44) | Not a 7G mode |

| ID | Rule |
|---|---|
| RMD-01 | Every replay is a deliberate action in exactly one mode. R1 is the only automatic mode and never produces a new entry, a new case or a new delivery to another group (7A RPL-01). |
| RMD-02 | No command, tool or request named simply "replay" exists. Every operation record names its mode (§42). |
| RMD-03 | R2 and R3 never write to a stream. R4 and R5 never bypass the 7E acceptance contract. R6 never invokes the normal consumer handler. R7 is never invoked, wrapped or replaced by 7G. |
| RMD-04 | No mode changes an `event_id`, an envelope, an outbox row, an audit row, a delivery history, an idempotency ledger or an origin provenance record (§43). |

**Replay source hierarchy (RMD-05).** A replay reads its event from the first source in this order that exists and that the mode permits: (1) the entry still pending in Redis for the group — R1 only; (2) the immutable replay material of a recovery case — R2; (3) the immutable outbox row (`FAILED`, or `PUBLISHED` inside its retention) — R4, R5, and R3 where approved; (4) retained stream entries read read-only over an approved ID range with trimming paused — R3 only; (5) the owning domain's authoritative state and archives, through the owner's rebuild mode — R6 only. If no permitted source exists the result is `SOURCE_MISSING`. An event is never fabricated from logs, audit rows or mutable domain state and presented as the original.

---

## 31. Targeted Consumer Replay (R2)

A republication to the shared stream would deliver the event to every group of the family: other groups would execute their guards again, groups beyond their evidence horizon would be forced into reconciliation, and a group whose obligation has since changed would have to be protected by provenance alone. R2 therefore never republishes.

| ID | Rule |
|---|---|
| TGT-01 | **Internal target-specific path.** R2 feeds the case's exact material into the dispatcher of the case's own logical group as a **recovery delivery**. No stream entry is written; no other group can observe the replay. |
| TGT-02 | **Target is fixed.** The target group is the case's `logical_group`. An operator cannot redirect a case to another group, and cannot supply an event, an organization or a payload: the only input is the case identity. |
| TGT-03 | **Same pipeline.** A recovery delivery runs the unchanged 7F steps D-01 … D-09 on the stored bytes: entry shape and `fmt`, envelope parse and validation, pair classification against the running build, payload validation against the original version, the tenant gate, the optional pure upcast, the owner idempotency adapter and handler in the owner transaction with the transaction-local tenant context of the validated envelope. It bypasses none of: 7C validation, version support, the evidence-horizon gate (7F RET-7F-08, evaluated inside the owner transaction under the retention barrier), canonical origin provenance, business idempotency, tenant context. |
| TGT-04 | **Obligation from provenance.** The applicable obligation of a recovery delivery is taken only from the case's origin provenance (§36): `NOT_OWED` with no backfill grant → outcome `NOT_OWED`; `NOT_OWED` with a backfill grant linked to the case → the handler may run under the grant, subject to the preconditions of BKL-07; `OWED` with a non-retired origin interval → the handler may run; `OWED` with a retired origin interval → `OBLIGATION_RETIRED`. A recovery delivery has no Redis position, and none is invented for it. A missing provenance is `PROVENANCE_MISSING` and the handler does not run. |
| TGT-05 | **Executor admission.** The R2 executor is an admitted member of the target group under the group's current handler-contract record (7F HCG-02, HCG-03) and revalidates before every item (HCG-04). It does not run while the group is `CLOSED` for a cutover or an onboarding, or while the group's dependency gate is open. |
| TGT-06 | **Success semantics.** D-10 (`XACK`) has no Redis entry to acknowledge. Its place is taken by the case transition: the case becomes `RESOLVED` only after the durable outcome is known (TGT-07 step 8). A replay is never "successful" because it was queued or started. |
| TGT-07 | **Atomicity sequence.** (1) Compare-and-swap the case `PARKED → REPLAYING`, binding it to the approved operation. (2) Verify the case is still eligible: kind `CONSUMER` or `CONSUMER_UNIDENTIFIED`, material present and its digest intact, the target admitted by §41. (3) Verify the running build's capability for the pair. (4) Evaluate the target's evidence horizon as a pre-check (the authoritative gate is step 6). (5) Verify the origin provenance (TGT-04). (6) Execute the 7F pipeline. (7) The owner transaction commits or rolls back. (8) Update the case with the outcome. (9) Only now is the case `RESOLVED`, or returned to `PARKED` / `RECONCILIATION_PENDING` (T-11 … T-13). |
| TGT-08 | **One execution per item; no automatic retry.** Within one operation the handler is executed at most once per case. A genuine handler failure gives outcome `PARKED_AGAIN`: the case returns to `PARKED`, `replay_count` is incremented, and automatic retry is not restored. `handler_failure_count` already equals the budget and is not incremented further. A dependency-wide failure consumes nothing: the item stays unprocessed and the operation pauses (THR-05). |
| TGT-09 | **Crash after the effect committed.** If the executor dies between step 7 and step 8 the case is left `REPLAYING`. The operation's recovery re-runs the item; the owner's guard proves `ALREADY_COMMITTED` (or recomputes the same value), and the case is completed. No duplicate effect is possible, and a `REPLAYING` case is never abandoned: it is always completed by its operation's recovery or by an explicit governed action. |
| TGT-10 | **Duplicate replay requests.** A second request for a case that is `REPLAYING` loses the compare-and-swap and has no effect. A second request for a `RESOLVED` case is rejected; nothing is re-executed. An operation has a unique identity, and re-submitting the same operation is idempotent (PLN-06). |
| TGT-11 | **Unidentified cases.** A `CONSUMER_UNIDENTIFIED` case may be replayed after a decoder fix. If the material then yields a trusted identity, the executor resolves the canonical case identity before the handler may run: it attaches to an existing canonical case or creates it, and determines the origin provenance from the stored first observation (key and entry ID) against the retained obligation intervals of that key. If that cannot be determined, the outcome is `PROVENANCE_MISSING`. |
| TGT-12 | **Cases still pending in Redis** (`OPEN_RETRY`, `HOLD`, Billing `RECONCILIATION_PENDING`) are not R2 candidates. They are served by R1, or by their reconciliation. |

---

## 32. Disaster Transport Replay (R4; closes 7D HO-7G-03, 7E HE-7G-04)

| ID | Rule |
|---|---|
| DSR-01 | **Purpose.** R4 restores durable events that may have been lost from the transport by a fault **outside** the 7E declared fault model (7E FMD-07: TF-17 … TF-20; F7E-21, F7E-22). It is never part of normal delivery and never a substitute for the acceptance guarantee (7D CLN-08; 7E FMD-02). |
| DSR-02 | **Source.** The immutable outbox row in status `PUBLISHED`, still present inside its frozen 7-day retention. The row is read with a plain `SELECT` and is never modified: its status, `published_at` and counters are unchanged. |
| DSR-03 | **Same event.** The repair publisher of §28 materializes the unchanged envelope with the original `event_id` and publishes through the frozen 7E durable acceptance contract to an onboarded key of a live generation. |
| DSR-04 | **All subscribed groups receive it.** This is intended: the fault may have affected every group of the shard. Each group processes the entry through the normal 7F pipeline; a group that already processed the event takes the `ALREADY_COMMITTED` path; a group for which the event is beyond its evidence horizon holds it and 7G hands it to reconciliation (§34). |
| DSR-05 | **Provenance.** Each group classifies the replayed entry from its canonical origin provenance where a record exists. Classification by the entry's position is permitted only under PRV-06, that is only while the original immutable outbox row still exists. For a captured source whose outbox row is gone, DSR-11 applies and the position is never used. The new Redis ID never decides the obligation by itself. |
| DSR-06 | **Fail closed on a missing source.** If the row has been deleted and no approved alternative immutable source holds the event, the candidate's result is `SOURCE_MISSING`. The event is never rebuilt from audit records, logs or application state. |
| DSR-07 | **Approved alternative immutable source: the captured source.** The only alternative source is a **captured source**: replay material in the recovery ledger captured byte-exactly from the immutable outbox row by the governed capture step of an approved operation, while that row still exists. Nothing else qualifies. Because a captured source may outlive its outbox row, it carries the governed metadata of DSR-12, so that it can never be reinterpreted later. |
| DSR-08 | **Scope and plan.** An R4 operation is bounded by an explicit `published_at` range, the affected stream families or shards, and optional event-type and organization filters; it has a dry-run with per-group horizon assessment (§42). "Replay every `PUBLISHED` row" without a bound is not a valid plan. |
| DSR-09 | **Privilege.** R4 needs the `recovery.disaster-replay` capability, an incident reference as its reason, and an audit record (§40). Regional recovery sequencing and throughput are 7K's. |
| DSR-10 | **Publication admission.** While a handler-contract cutover holds publication admission `CLOSED` for an event type (7F HCG-26), the repair publisher issues no write for that type; the item waits. A replay never crosses a cutover boundary unregistered. |
| DSR-11 | **No position fallback once the outbox row is gone.** A shared-stream publication from a captured source whose original outbox row no longer exists MUST NOT rely on Redis-position classification. Before the repair publisher writes such an item, every logical group that can receive the entry — every group registered for, or present on, any live key of the event's family — MUST have an authoritative canonical origin record `O(group, event_id, event_type)`. If even one such group has none, the item's result is `PROVENANCE_MISSING`: the item fails closed and nothing is published to the stream for it. The check and the write are made inside one registered publication attempt (7F HCG-26), so the receiving set cannot change between them. |
| DSR-12 | **Source-capture contract.** The capture of one row is one PostgreSQL transaction that: (a) reads the outbox row under a row lock that conflicts with its deletion, and verifies that it exists and is terminal; (b) stores the byte-exact materialization and its SHA-256; (c) records the original event identity (`event_id`), the event type and version, the organization scope, the stream family, the capture time and the capturing operation; (d) records the registry snapshot: every logical group registered for the family at capture, each with its handler-contract generation; (e) for each such group, links the existing origin record or, where none exists, inserts one under PRV-10; (f) records `provenance_complete` — true only if every snapshot group has an origin record — and names every group that lacks one. |
| DSR-13 | **Completion only while the row exists.** A captured source whose provenance is incomplete may be completed only while its original outbox row still exists. Once the row is deleted, a missing origin is never completed by 7G: it is not fabricated, not reconstructed from `occurred_at`, the capture time, any business timestamp or UUID order, and not inferred from a Redis position. Such a source stays replay-blocked for shared-stream publication; the owner's rebuild mode (R6) remains available. |
| DSR-14 | **Later cutovers and new groups.** A captured source can survive into a later handler-contract cutover or group creation. Every later cutover that affects the event type of a retained captured source, and every creation of a group on its family, must preserve or complete canonical provenance for that source — insert-if-absent, from the contract in force before the switch, and `NOT_OWED` for a group that did not exist — exactly as 7F CUT-5f does for outbox rows (CNF-7G-09, IO-7G-37). Where that was not done, the source is replay-blocked by DSR-11. A group created after the event was produced never acquires the event through R4 merely because the replay happens after its activation. |

---

## 33. Future-Consumer Backfill (R3; closes 7E HE-7G-05, 7F HE-7G-7F-08)

| ID | Rule |
|---|---|
| BKL-01 | **Nothing is owed by default.** When a type is added to a group, or a new group is created, entries at or below the activation boundary are not owed (7F HCG-10, HCG-14; 7E BST-04, GLR-03). They are acknowledged as known-unsubscribed if delivered. They never become owed implicitly. |
| BKL-02 | **Backfill is a separate explicit operation.** It exists only as an approved R3 plan. Deploying a handler, creating a group or changing a registry never causes one. |
| BKL-03 | **A plan specifies** at least: the target logical group; the event type and version scope; the source (BKL-05); the time or ID range; the handler-contract generation under which the backfill executes; the canonical origin treatment (BKL-06); the evidence-horizon feasibility for the target (§34); the organization scope if narrowed; the dry-run candidate count; the expected business effect; the operator or system reason; the rate limit; the stop and cancel behaviour. |
| BKL-04 | **Mechanism.** R3 feeds each selected event to the target group's dispatcher as a recovery delivery, as R2 does: no stream entry is written and no other group is affected. R3 does **not** reuse the R2 case sequence of TGT-07: a backfill candidate normally has no recovery case. Its execution contract is §33.1. |
| BKL-05 | **Source.** In order of preference: retained stream entries of the approved ID range, read with `XRANGE` (read-only) while trimming is paused for the affected keys; retained outbox rows; replay material in the ledger. If the history in the approved range is no longer held by any of them, the candidates are `SOURCE_MISSING` and the backfill of that range requires the owner's rebuild mode (R6). Missing history is never fabricated. |
| BKL-06 | **Origin treatment.** A backfilled event keeps its origin provenance `NOT_OWED`; the record is written insert-if-absent where none exists and is never rewritten (7F HCG-29). What makes the handler run is a separate, immutable **backfill grant** — one insert-if-absent record per (group, `event_id`, `event_type`), naming the operation that granted it — which is the governed 7G act that 7F HCG-30 names. A grant never changes what the group owed historically. |
| BKL-07 | **Preconditions for execution.** The type has an `OPEN` obligation interval for the group in the plan's handler-contract generation, the running build supports the event's version, the target is admitted by §41, and the event is inside the target's evidence horizon. An event that fails one of these gets the matching result (§42.4) and the handler does not run. |
| BKL-08 | **Creating a future group.** A new group on a key that has history is created at an explicit position stated in the governed registry change — the stream boundary `B(K)` captured for the activation (7F HCG-14) — never at `0` merely because the group is new, and never by an unqualified `$` (7E BST-04). Trimming is paused for the affected keys while it is created (7E TRM-07). |
| BKL-09 | **`XGROUP SETID` is not a backfill mechanism.** No 7G replay mode moves a group's position. Rewinding a group would redeliver every type in the range to that group, including types whose evidence horizon the range exceeds. `XGROUP SETID` is reserved for a governed incident repair of a group whose position is provably wrong, and then only: with trimming paused for the affected keys (TRM-07); to an explicit position not below the stream's first entry; after a dry-run that counts the entries that will be redelivered and those beyond the group's horizon; under the `recovery.group.operate` capability with an audit record. Existing groups other than the repaired one are untouched. |
| BKL-10 | **Trim pause.** A pause is requested before the operation's first read or position change, recorded on the operation, and released when the operation is terminal. While paused, the affected keys only grow (7K, HE-7K-7G-04). An operation never relies on "trimming probably has not run". |
| BKL-11 | **No implicit range growth.** The executor processes exactly the candidates fixed by the approved plan. Entries published after the plan's upper bound are not part of it. |

### 33.1 R3 execution contract

An R3 candidate has no recovery case when it starts. Its durable state is its **operation item**, which is `PENDING`, `EXECUTING` or terminal with exactly one result.

| Step | R3 item action |
|---|---|
| BF-1 | **Item fixed.** The approved plan fixes one item per candidate: the target logical group, the `event_id`, the `event_type` and the source reference. |
| BF-2 | **Claim.** The executor moves the item `PENDING → EXECUTING` by compare-and-swap, recording its identity. |
| BF-3 | **Existing case.** If a non-terminal recovery case already exists for (group, `event_id`, `event_type`), R3 does not execute the handler: after BF-4 the grant is linked to that case and the item ends `ATTACHED_TO_EXISTING_CASE`. If a case exists that is `RESOLVED` with a terminal rejection, the handler is not executed and the item ends `TARGET_BLOCKED`: a backfill never overrides a recorded rejection. |
| BF-4 | **Preparation commit** (one PostgreSQL transaction). (a) The exact material read from the source is stored with its SHA-256, bound to the item. (b) The canonical origin is fixed: an existing record governs; if none exists it is determined under BKL-13 and inserted insert-if-absent; if it cannot be determined the item ends `PROVENANCE_MISSING`, nothing else is written and the handler never runs. (c) Where the origin is `NOT_OWED`, the backfill grant is inserted insert-if-absent. |
| BF-5 | **Verification.** The type has an `OPEN` obligation interval for the group in the plan's handler-contract generation, and that generation is still the current one; the running build supports the pair; the target is admitted by §41.1; the horizon pre-check is evaluated. A failed check gives the result of BKL-14 without executing the handler. |
| BF-6 | **Execution.** The handler is executed once through the unchanged 7F pipeline D-01 … D-09 on the stored material, in the tenant context of the validated envelope, with the owner's evidence-horizon gate inside the owner transaction. |
| BF-7 | **Outcome commit** (one ledger transaction). The item result is recorded and, where BKL-14 requires a case, the case is created or attached in the same transaction. |
| BF-8 | **Recovery.** An item found `EXECUTING` after its executor died is re-run from BF-3 by the operation's recovery. |

| Outcome at BF-5 / BF-6 | Case action, in the same transaction as the item result | Item result |
|---|---|---|
| `PROCESSED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE` | None. A successful backfill needs no recovery case | The same |
| Genuine handler failure (FC-12) | Create or attach the canonical `CONSUMER` case → `PARKED`, reason `BACKFILL_HANDLER_FAILED`, `handler_failure_count = 0`; the stored material; the origin provenance link; the backfill-grant link; a history entry (T-17, T-18) | `PARKED_AGAIN` |
| Permanent contract-invalid material (FC-01 … FC-05) | Create or attach a case → `PARKED` with the matching reason (kind `CONSUMER_UNIDENTIFIED` where no identity is trusted); the stored material; the item and grant reference | `PARKED_AGAIN` |
| `BEYOND_HORIZON` | Create or attach the case → `RECONCILIATION_PENDING`; material, provenance, grant link | `BEYOND_HORIZON` |
| Origin `OWED` with a retired origin interval | Create or attach the case → `RECONCILIATION_PENDING`; material, provenance | `OBLIGATION_RETIRED` |
| No `OPEN` interval for the type, or the plan's generation is no longer current | None; the handler does not run | `OBLIGATION_NOT_ACTIVE` |
| Pair not supported by the running build | None; the handler does not run; the item's material stays with the operation | `UNSUPPORTED_VERSION` |
| Target not admitted | None | `TARGET_BLOCKED` |
| Origin not determinable | None; no grant is written | `PROVENANCE_MISSING` |
| Dependency-wide failure | None; the item returns to `PENDING`; the operation pauses (THR-05) | Not terminal |

| ID | Rule |
|---|---|
| BKL-12 | **Before the handler may run** the following are durable or verified: (1) the operation item is fixed (BF-1); (2) the target logical group is fixed; (3) the exact event material is stored and digest-protected (BF-4 a); (4) the canonical origin is fixed, as `NOT_OWED` where appropriate (BF-4 b); (5) the immutable backfill grant exists (BF-4 c); (6) the target capability, the evidence horizon and the handler-contract generation are verified (BF-5, and the owner's gate in BF-6). |
| BKL-13 | **Origin of a candidate.** From a retained stream entry: the classification of that entry at its position under the group's obligation intervals — at or below the activation boundary it is `NOT_OWED`. From an outbox row that still exists: the existing record, or the position-independent determination of PRV-10. From ledger material or a captured source: the existing record only. Nothing is guessed. |
| BKL-14 | **The outcome table above is normative.** An R3 item never becomes terminal with a result that needs later recovery unless the recovery case that carries it — with its exact material, its provenance and its backfill-grant link — exists in the same commit. A result of `PARKED_AGAIN` without a `PARKED` case holding the material is unreachable. |
| BKL-15 | **Create or attach.** The case identity is the canonical `(logical_group, event_id, event_type)`. If no case exists one is inserted (T-17). If a case exists that is `RESOLVED` without a terminal rejection it is reopened (T-18). The operation is idempotent: repeating it finds the existing case and changes nothing, so two executions can never create contradictory states. |
| BKL-16 | **The parked backfill case is an R2 candidate.** It is replayed later through §31. R2 reads the grant from the case (TGT-04), so the fact "historically `NOT_OWED`, explicitly granted as backfill" is never lost and the event is never resolved `NOT_OWED` merely because the R3 operation has ended. |
| BKL-17 | **Crash before the handler.** The item is `EXECUTING` and not terminal; nothing was executed. Recovery re-runs it; the preparation commit is idempotent (material by digest, origin and grant insert-if-absent). |
| BKL-18 | **Crash after the owner effect committed, before the item result.** Recovery executes the same candidate again; the owner's guard returns `ALREADY_COMMITTED` (or recomputes the same value); the item completes with that result. No duplicate effect is possible (7F CPM-10). |
| BKL-19 | **Crash after a handler failure, before the case exists.** The item is still `EXECUTING` and its material is already durable from BF-4, so neither the candidate nor its source disappears. Recovery re-runs the item; it either succeeds or fails again and then establishes the case under BKL-14. |
| BKL-20 | **Crash after the case exists, before the item result.** BF-7 is one transaction, so this state does not arise from a conformant executor. If an implementation ever splits the two writes, recovery finds the existing case by its canonical identity and attaches to it (BKL-15); it never creates a second case. |
| BKL-21 | **Backfill-grant retention.** A grant is retained at least as long as any non-terminal recovery case references it, and beyond that until the provenance-retirement proof of §36.2 holds for its (group, `event_id`, `event_type`). The 90-day cleanup of the granting operation never removes a grant, so a parked backfill case can never become `NOT_OWED` on a later R2 because its operation was cleaned up. |
| BKL-22 | **One execution per attempt.** Within one execution attempt of an item the handler runs at most once. A second execution happens only through recovery after a crash, or through a later explicit R2 of the parked case. There is no automatic retry and no budget of automatic attempts. |

---

## 34. Per-Target Evidence Horizon (closes 7F HE-7G-7F-05)

| Target | Class (7F §31.2) | Normal raw-replay horizon | Measured on | Beyond the horizon |
|---|---|---|---|---|
| CON-04 CRM | RS-LEDGER | **30 days** | Envelope `occurred_at` (7F RET-7F-08, RET-7F-16) | `RECONCILIATION_PENDING`; CRM-owned rebuild or reconciliation |
| CON-06 Billing | RS-RETENTION-BOUNDED | **90 days**, under the retention barrier | The derived row `occurred_at` | `RECONCILIATION_PENDING`; Billing-owned reconciliation (§35) |
| CON-07 Analytics | RS-LEDGER | **90 days**, under the retention barrier | Envelope `occurred_at` | `RECONCILIATION_PENDING`; 5J §12.3 historical rebuild |
| CON-10 Integrations | RS-LEDGER once IO-7F-21 exists | Set by its future claim-ledger migration (7F RET-7F-07) | Chosen by that migration | `RECONCILIATION_PENDING`; Integrations-owned handling. Not a replay target at all before IO-7F-21 |
| CON-01, CON-02, CON-03, CON-05, CON-08, CON-09, CON-11 | RS-STATE | Follows the owner-state / rebuild contract of 7F §28; no time cap | — | Not applicable |

| ID | Rule |
|---|---|
| HZN-01 | Every replay candidate is evaluated **independently for each target consumer**. There is no global replay window. |
| HZN-02 | **Metadata retention never extends a horizon.** A 90-day recovery case does not make a 31-day-old event replayable through the CRM handler, and the existence of exact material does not make a beyond-horizon replay safe: the danger is the owner's missing idempotency evidence, not missing event bytes. |
| HZN-03 | **Authoritative gate.** The decision is the owner adapter's evidence-horizon gate, evaluated inside the owner transaction after the shared retention barrier, with the database clock (7F RET-7F-08, RET-7F-11). The planner's horizon assessment (§42) is a pre-check for the dry-run and never replaces it. |
| HZN-04 | **Beyond the horizon** the normal consumer handler is not invoked, no guard statement and no insert is issued, and the case goes to `RECONCILIATION_PENDING` for the owner's rebuild or reconciliation mode (R6; 7A RPL-06). 7G never "tries anyway". |
| HZN-05 | **Not determinable is beyond.** A candidate whose position relative to the horizon cannot be determined, including a future-dated event (7F RET-7F-16), is treated as beyond the horizon. |
| HZN-06 | A narrower window MAY be imposed by a plan. A wider one cannot be: no capability, approval or reason overrides HZN-04. |
| HZN-07 | In R4 and R5 the event reaches every subscribed group. The dry-run reports, per group, how many candidates are beyond that group's horizon; those are held by that group's own gate and become `RECONCILIATION_PENDING` cases. The plan's approver sees this number before approving. |

---

## 35. Billing Beyond Horizon (closes 7F HE-7G-7F-09)

| ID | Rule |
|---|---|
| BIL-01 | For CON-06, `BEYOND_HORIZON` means: no normal usage insert; no acknowledgement through the Billing handler as if it had succeeded; no duplicate usage and no charge. The adapter issues no statement against `billing.usage_events` (7F RET-7F-09). |
| BIL-02 | The worker records a durable case in `RECONCILIATION_PENDING` with reason `BEYOND_HORIZON`, the exact material and the provenance, in one transaction (§21). |
| BIL-03 | **Ownership split.** Billing owns the financial determination: whether the usage fact was processed and later archived, or was never processed, and what follows (7F IO-7F-34). 7G owns the mechanics: the durable case, the material hand-off, and the final release of the Redis pending entry. 7G never reads the usage archive, never computes a quantity or a charge, and never inserts usage. |
| BIL-04 | **Deferred acknowledgement.** The Redis entry of a Billing beyond-horizon case is **not** acknowledged when the case is recorded. It stays pending — the sweep reclaims it, the recovery-case gate finds `RECONCILIATION_PENDING`, no handler runs and no `XACK` is issued — until Billing's reconciliation records a durable terminal decision on the case (T-14). Only then does 7G acknowledge the entry, citing that recorded disposition. |
| BIL-05 | **Why the financial path differs.** For every other class the ledger alone carries the obligation after the park commit. For the monetary path 7G keeps the second, independent durable copy in the stream until the money decision exists. Correctness does not depend on it (the material is in the ledger either way); it is defence in depth, at the cost of a longer trim pin that 7K sizes (HE-7K-7G-05). |
| BIL-06 | If the stream entry is nevertheless gone when the decision is recorded (`XACK` returns 0), the recorded disposition stands and nothing is repeated (PAT-05). |
| BIL-07 | Until IO-7F-34 exists a Billing beyond-horizon case simply stays `RECONCILIATION_PENDING`. It is never resolved by elapsed time, by cleanup or by an operator choosing to run the normal handler. |

---

## 36. Canonical Origin Provenance (closes 7F HE-7G-7F-10)

### 36.1 Storage, assignment and use

| ID | Rule |
|---|---|
| PRV-01 | **Record.** For each logical group there is at most one origin record `O(group, event_id, event_type)` holding `origin_contract_generation` and `origin_obligation` (`OWED` or `NOT_OWED`) (7F HCG-28). 7G stores it in ledger component LC-4. |
| PRV-02 | **Immutable, insert-if-absent.** The only write is an insert that does nothing when the record exists. There is no update path and no delete path other than the retirement of §36.2. A record is never rewritten by a later cutover, by a replay of any mode, by a topology generation, by a backfill, or by a recovery-case transition. |
| PRV-03 | **What never overrides it.** Not the Redis ID a replayed entry receives; not the current `H_active(g)`; not the latest cutover; not the handler code that currently exists; not an operator input (7F HCG-29). |
| PRV-04 | **Assignment at a cutover** is 7F's (CUT-5f): every outbox row of an affected type that exists at that moment and has no record receives one. 7G provides the storage and the insert-if-absent operation. |
| PRV-05 | **Assignment when an event leaves the stream under 7G.** When a consumer case with a trusted identity moves to `PARKED` or `RECONCILIATION_PENDING`, the same transaction writes the origin record if none exists, from the classification of the entry at its original stream position under the handler-contract record the worker was admitted under: the type is in `A(g, E)` → `OWED`, with the generation in which the applicable obligation interval was opened; the type is in `X(g, E)` → `OWED`, with the generation in which that now-retired interval was opened; otherwise → `NOT_OWED`, with the admitted generation. This is exactly the classification 7F HCG-30 prescribes for an entry without a record, captured before the position is lost. It adds an assignment point; it changes no 7F rule (CNF-7G-05). |
| PRV-06 | **Position fallback only while the outbox row exists (R4, R5).** If a record exists for (group, event) it governs. If none exists **and the original immutable outbox row still exists** at the moment of publication — verified in PostgreSQL inside the registered publication attempt — then no cutover of that type has happened for that group since the row was produced, because 7F CUT-5f gives every existing outbox row of an affected type a record (HCG-28); classification of the replayed entry by its position under the current intervals is then the historically correct answer. This argument is void once the row is deleted: a cutover after the deletion could not have given the event a record. A replay from a captured source whose row is gone therefore requires a canonical origin record for every receiving group (DSR-11) and never uses the position. |
| PRV-07 | **Fail closed.** A replay through the internal path (R2, R3) whose origin is required and cannot be determined has result `PROVENANCE_MISSING`; the handler does not run and nothing is guessed (7F HCG-31 d). |
| PRV-08 | **Per group.** A provenance value is never used without its logical group. In a move or split the old and new group have separate records for the same event, which may legitimately differ (7F HCG-31 a). |
| PRV-09 | **Answerable question.** For any (group, `event_id`, `event_type`) that any replay source can still deliver, the ledger answers: did the group owe this event when it was produced, and under which contract generation. |
| PRV-10 | **Assignment at capture.** While the outbox row exists and a snapshot group has no record, the capture (DSR-12) inserts one, insert-if-absent, with the semantics of 7F HCG-28 / HCG-29: `origin_contract_generation` is the group's contract generation in force, and `origin_obligation` is `OWED` if that contract owes the type for the group, else `NOT_OWED`. It is the correct historical answer for the reason given in PRV-06: a row without a record has seen no cutover of its type for that group. The capture requires the group's handler-contract record to be `OPEN` with no change in progress; otherwise that group is recorded as lacking provenance (DSR-12 f). An existing record is never overwritten. |

### 36.2 Provenance retention

A record is kept while any replay source can still deliver its event to its group. The sources are: a pending Redis entry; a recovery case (parked, replaying or awaiting reconciliation) or its material; a replayable publisher `FAILED` row; a retained `PUBLISHED` row; an approved backfill source; a disaster-repair source.

| ID | Rule |
|---|---|
| PRR-01 | A newer handler-contract generation, a later cutover or a topology-generation change never makes a record retention-eligible (7F HCG-31 c). |
| PRR-02 | **Proof that no replay source remains.** A record `O(g, e, t)` is retention-eligible only when all of the following are proven and recorded: **(P1)** no recovery case of any kind for event `e` is non-terminal, and no ledger replay material for `e` remains; **(P2)** no outbox row with `id = e` exists; **(P3)** no replay, backfill, redrive or retirement operation that is not terminal has `e` in its scope or could select it; **(P4)** for every live physical key `K` of every live generation of the family of `t`, a checkpoint `C(K)` — the stream's `last-generated-id` read after P2 first held — has been passed by the stream's first entry ID (or the stream is empty), which under the safe-trim watermark means every entry that existed at the checkpoint has been delivered to and acknowledged by every group on `K`, including `g`; **(P5)** no approved alternative immutable source (DSR-07) holds `e`. |
| PRR-03 | **Why P2 and P4 together close the transport source.** After P2 the normal relay can no longer publish `e`: it publishes only from outbox rows. A relay attempt that claimed the row earlier cannot append after the checkpoint, because the row was terminal before it could be deleted and a claim loop starts no publication after its local deadline and bounds every exchange by its publish timeout (7D LSE-04, TPT-07). The repair publisher needs the row or ledger material, which P1, P2 and P5 exclude. |
| PRR-04 | The proof reads PostgreSQL state and Redis stream state; it is never satisfied by elapsed time alone. It runs as a separate governed maintenance operation and records its checkpoints and result. |
| PRR-05 | **Default.** Until the proof tooling exists (IO-7G-22) no origin record is deleted. Retaining a record longer than necessary is always safe. |
| PRR-06 | The retirement of a record is itself recorded (counts and identity ranges) so that "no replay source remains" is an auditable statement, as 7F HE-7G-7F-10 requires. |
| PRR-07 | A backfill grant is retired only together with, or after, the origin record of the same (group, `event_id`, `event_type`), under the same proof, and never while a recovery case references it (BKL-21). |

---

## 37. Topology Generations

| ID | Rule |
|---|---|
| TPG-01 | A replay onto a key of generation `g2`, `g3` or later preserves the `event_id`, the event type and version, and the canonical origin obligation of each logical group. |
| TPG-02 | The topology generation is transport metadata only (7E LCY-08). It is recorded in transport observations and in operation items. It creates no new case identity, no new provenance and no new business fact merely because the Redis key changed (7F HCG-31 b). |
| TPG-03 | **Onboarding first.** The repair publisher writes only to a physical key that has completed 7F topology-key onboarding for every subscribed group (TK-1 … TK-6) and is a live write target. It never publishes into a key that is not onboarded, and never into a retired generation. |
| TPG-04 | R2 and R3 have no key at all; they are unaffected by a generation change. |
| TPG-05 | **Old keys and replay sources.** A recovery case never depends on the continued existence of a stream key: its material is in the ledger. Before an old-generation key is retired (7E LCY-07 step 5) every pending entry on it has a 7G terminal disposition or a case with material, exactly as in group retirement (§38). An R3 plan that names an old key as its source must complete, or be cancelled, before that key is deleted; the key's retirement is blocked while a non-terminal operation references it. |
| TPG-06 | Obligation-interval history of a retired key that a later R2 of an unidentified case could need (TGT-11) is kept as 7F TKO-07 prescribes. |

---

## 38. Group Retirement and Retired Obligations (closes 7E RET-03)

A logical group is destroyed only after its obligation has been governed away. Destroying the group discards its pending-entry list; nothing may be discarded merely because the group is being removed.

| Step | Group-retirement action |
|---|---|
| GR-1 | The governed removal of the obligation is recorded (7E RET-01): a 7B / 7E registry change, with the 7F handler-contract cutover for the removal where the group survives for other types. |
| GR-2 | An approved retirement operation is created (§42) under the `recovery.group.operate` capability. |
| GR-3 | The group's consumers are stopped, and the handler-contract registration set is proven empty (7F CUT-4, CUT-5). |
| GR-4 | Trimming is paused for every key the group exists on. |
| GR-5 | The pending list is enumerated in full with `XPENDING` on every key, and every pending entry is read. |
| GR-6 | **Every pending entry receives a terminal 7G disposition**, individually recorded: processed by the group's last admitted build before it stopped; parked with material and then dispositioned; handed to owner reconciliation and resolved; or explicitly resolved `OBLIGATION_GOVERNED_AWAY` with the owner's approval reference. A bulk disposition is permitted only as a plan that enumerates the entries it covers. |
| GR-7 | **Every non-terminal recovery case of the group** — `OPEN_RETRY`, `HOLD`, `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING` — is brought to `RESOLVED` by the same means. A parked case is not abandoned because its group disappears. |
| GR-8 | Only when GR-6 and GR-7 are proven complete is `XGROUP DESTROY` executed on every key the group exists on. |
| GR-9 | The registry is updated, the trim watermark recomputes without the group, trimming is resumed, and the handler-contract lifecycle proceeds as 7E and 7F define. Origin records of the group follow §36.2. |

| ID | Rule |
|---|---|
| GRT-01 | Group retirement is privileged, planned, audited and never automatic (7E RET-02). A group is never destroyed because it is idle, lagging or pinning retention. |
| GRT-02 | 7E RET-03 step 3 says pending entries are "reviewed under the 7G procedure". 7G defines that review as GR-5 … GR-7: an explicit recorded disposition per entry. "The obligation no longer exists" is a reason that may be recorded; it is never an unrecorded default (CNF-7G-04). |
| GRT-03 | If any entry or case cannot be dispositioned, the retirement stops before GR-8 and the group stays. |
| DPE-01 | **Retired obligation.** An entry classified `OBLIGATION_RETIRED` (7F C-11) is never executed under a newer interval, even when the type is active again after a re-add. Canonical provenance governs, not the current `H_active(g)`. |
| DPE-02 | For such an entry 7G decides exactly one of: hand-off to the owner's rebuild path (`RECONCILIATION_PENDING` → `OWNER_RECONCILED`); or an explicit owner-approved terminal disposition (`SUPERSEDED_BY_OWNER_RECONCILIATION`, `PERMANENTLY_REJECTED_WITH_REASON`). It is never acknowledged as known-unsubscribed and never re-armed for the normal handler. |
| DPE-03 | **Retirement of a historical obligation (7F HCG-18).** Condition (2) of HCG-18 — "every such pending entry has a recorded 7G terminal disposition" — is satisfied by a `RESOLVED` case for the entry. Condition (3) — a governed 7G contract that no such entry is delivered again except through the owner's rebuild path — is satisfied by this document: after the interval is retired, any such entry is `OBLIGATION_RETIRED` and follows DPE-02, and no 7G replay mode sends it to the normal handler (TGT-04). |

---

## 39. Dangling PEL Entry / Missing Stream Entry

On a durable key, a pending ID whose entry no longer exists can occur only if an invariant was violated: the safe-trim watermark never removes a pending entry (7E TRM-02, TRM-05), `XDEL` is used by no component, and durable keys have no TTL and no `MAXLEN` (7E TTL-01, TRM-01).

| ID | Rule |
|---|---|
| DGL-01 | **Never forgotten.** A missing entry behind a durable pending ID is never silently dropped from consideration. It is a transport-integrity anomaly. |
| DGL-02 | **Trimmed prefix: detect before clearing.** The sweep's pre-check (RCL-06) detects a missing prefix with read-only commands. On detection the sweep issues no claim command on that (key, group), enumerates the pending IDs below the stream's first entry with `XPENDING` (read-only), records one `TRANSPORT_INTEGRITY` case per ID in state `PARKED` with reason `MISSING_STREAM_ENTRY` (identity PID-07; the consumer name, idle time and delivery count as observed), commits, and raises an alert-grade signal. |
| DGL-03 | **Interior hole: best-effort evidence.** IDs reported in the deleted-entries element of a claim reply are recorded the same way from the reply (RCL-07). Redis has already removed them from the PEL when the reply arrives, so this path has a residual crash window and is incident evidence, not a guarantee. Governed repair operations close that window for the IDs they enumerate (RCL-15). An interior hole is an outside-model incident (7E TF-20) handled under DGL-05. |
| DGL-04 | **Recovery only from an authoritative source.** The event identity behind a missing entry may be recovered only from an authoritative replay source: a transport observation in the ledger that maps the entry ID to an event; the outbox, by a governed R4 over the affected interval; or the owner's rebuild mode. The payload is never fabricated from logs or metrics. |
| DGL-05 | **Fail closed.** If the identity cannot be recovered, the case stays `PARKED` and visible, the affected group and interval are handed to incident reconciliation (7K for the recovery procedure, 7L for the record), and the case is resolved only by an explicit disposition (§24.3). It never ages out (PRT-02). |
| DGL-06 | After the cases are durable, the pending IDs may be released by a governed repair operation. The release is recorded on each case. |
| DGL-07 | **SIGNAL.** On the SIGNAL key, loss by trimming is permitted by contract (7E SGR-03). The SIGNAL group has no PEL in V1; no case is created and nothing is recovered (§45). |

---

## 40. Replay Authorization Model (7A SEC-08, RPL-04; T-04, T-12)

| ID | Rule |
|---|---|
| AUT-01 | **Internal operations tooling only.** V1 recovery, replay, redrive, backfill and group-retirement operations exist only as internal event-operations tooling. 7G creates no tenant-facing replay API, no organization-admin replay endpoint, no Phase-6 route and no OpenAPI change. |
| AUT-02 | **Every operation requires**: an authenticated internal operator or system identity; the capability for that operation (table below); an explicit reason reference; an explicit target scope; an explicit source scope; a dry-run where §42 requires one; an audit record of the request, the approval and the start; and an outcome record. An operation missing any of these does not start. |
| AUT-03 | **Capabilities, not roles.** 7G defines the capabilities an identity must hold. Final role names, grants, the binding to `app_platform_admin` or a narrower principal, and Redis ACL users are 7I's (HE-7I-7G-01). No capability is implied by another unless the table says so. |
| AUT-04 | **Separation.** For R3, R4, R5, group retirement, `XGROUP SETID` repair and any operation whose target is a high-risk group (§41), the approver SHOULD be a different identity from the requester. 7I decides whether this is enforced as a hard control. |
| AUT-05 | **Audit.** Every operator and system recovery action writes an immutable record through the frozen audit boundary, in the same PostgreSQL transaction as the ledger change it describes where one exists (7D OD-7D-02). The record carries: actor; capability used; operation identity and mode; reason reference; source and target scope; candidate counts; outcome. It carries no payload, no material and no secret. |
| AUT-06 | **No raw tooling.** Ad-hoc SQL against the ledger or the outbox, and ad-hoc Redis commands against stream keys, are not a recovery procedure. The operator-only Redis commands (`XGROUP DESTROY`, `XGROUP SETID`, `XGROUP DELCONSUMER`, 7E SCY-05) are issued only by the governed operations of this document. |
| AUT-07 | **Material access is separate.** Reading case metadata does not grant reading replay material. Material is viewed only under `recovery.material.view`, each view is audited, and material is never exported to a ticket, a log or a tenant. |

| Capability | Permits |
|---|---|
| `recovery.case.read` | Reading case metadata, observations, history, operation records |
| `recovery.material.view` | Viewing replay material of one case |
| `recovery.case.disposition` | Exactly two things (DAU-06): `PERMANENTLY_REJECTED_WITH_REASON` on a class `I` (contract-invalid) case, and `NOT_OWED` / `KNOWN_UNSUBSCRIBED` on a class `N` (proven not owed) case. It does not permit resolving a parked case in general and permits nothing on a class `V` case |
| `recovery.reconciliation.record` | Recording an owning domain's terminal reconciliation decision or supersession (T-14, T-15) with its reconciliation reference; held by the owning domain's reconciliation path, never by generic event operations |
| `recovery.replay.plan` | Creating a plan and running a dry-run |
| `recovery.replay.approve` | Approving a plan |
| `recovery.replay.execute` | Starting, cancelling and resuming an approved R2 operation |
| `recovery.backfill` | R3 |
| `recovery.disaster-replay` | R4, including the governed source capture (DSR-07) |
| `recovery.publisher.redrive` | Recording a publisher disposition and running R5 |
| `recovery.group.operate` | Group retirement, idle-consumer maintenance, `XGROUP SETID` repair, integrity release (DGL-06) |
| `recovery.maintenance.cleanup` | Ledger cleanup, provenance retirement, interlocked outbox `FAILED` cleanup |

---

## 41. High-Risk Replay Protection (7A RPL-02, RPL-03)

| ID | Rule |
|---|---|
| HRP-01 | A group is a replay target only if §41.1 admits it. An unlisted or blocked group is never the target of R2 or R3, and an R4 / R5 operation whose family has a blocked subscribed group does not start while that group is activated. |
| HRP-02 | Replay MUST NOT double charge, duplicate usage, create a second payment, create a second physical call, or unintentionally create a duplicate tenant-visible webhook delivery. Each prohibition is met by the owner guard named in §41.1, never by 7G logic. |
| HRP-03 | **Proof before admission.** A group whose handler can trigger an external irreversible action is admitted only when its owning idempotency or state-machine protection is proven in its 7F §28 card. Where that is not proven, the group is blocked. No current consumer performs an external creating call from its handler (7F EXT-05). |
| HRP-04 | A future consumer is added to §41.1 by the same governed change that adds its 7F card. Until then it is not a replay target. |
| HRP-05 | High-risk targets (Billing, Integrations) carry stricter throttles (THR-02) and a mandatory dry-run for any plan with more than one candidate. |

### 41.1 Replay target admission

| Target | Risk | Protection that makes replay safe (7F) | R2 / R3 admission | Condition |
|---|---|---|---|---|
| CON-01 `cg.identity.session-denylist` | Low | IC-5 absolute keyed writes; a repeat can only extend a denylist entry | Admitted | IO-7F-11 |
| CON-02 `cg.compliance.default-policy-seeding` | Low | `uq_compliance_policy_active` conflict form | Admitted | IO-7F-12 |
| CON-03 `cg.compliance.active-policy-pointer` | Low | Lock-then-recompute | Admitted | CNF-7F-02 reconciled |
| CON-04 `cg.crm.call-history` | Medium | `crm.fn_claim_event`; 30-day horizon gate | Admitted inside 30 days | IO-7F-14, IO-7F-33, IO-7F-35 |
| CON-05 `cg.campaign.record-call-outcome` | High (adjacent to call placement) | Job and contact compare-and-swap; the handler places no call — placement is the separate executor path under `uq_cj_idempotency_active` and `voice.call_dispatch_keys` (7F §17); a retry decision is itself guarded | Admitted | CNF-7F-03, CNF-7F-04, CNF-7F-09 reconciled |
| CON-06 `cg.billing.usage-ingestion` | **High (financial)** | `uq_ue_idempotency` with deterministic derivation; 90-day horizon gate under the retention barrier | Admitted inside 90 days; beyond → §35 | IO-7F-16, IO-7F-33, IO-7F-35; EV-079 additionally IO-7B-02, IO-7B-15, IO-7B-16, IO-7B-17 |
| CON-07 `cg.analytics.projections` | Medium | Analytics dedup and projection ledgers; 90-day horizon | Admitted inside 90 days; beyond → 5J §12.3 | IO-7F-17, IO-7F-33, IO-7F-35 |
| CON-08 `cg.voice.recording-object-cleanup` | Medium (external delete) | Absolute delete of a never-reused key | **Blocked** | Until CNF-7F-05 is reconciled |
| CON-09 `cg.knowledge.document-count` | Low | Lock-then-recount | Admitted | CNF-7F-06 reconciled |
| CON-10 `cg.integrations.webhook-engine` | **High (tenant-visible)** | **None today** | **Blocked** | Until IO-7F-21 exists; then admitted inside the horizon its migration sets. A late replay fans out to the endpoints active at processing time (7F §28.11); the plan states this as tenant-visible risk |
| CON-11 `cg.campaign.import-worker` | Low | `PENDING → PROCESSING` compare-and-swap | Admitted | CNF-7F-07 reconciled |
| `sg.analytics.signal-projections` | — | — | **Never** (§45) | — |

"Payment" has no row: no consumer in the registry creates a payment. Payment creation is not an effect of any event handler, so no internal replay can create one.

---

## 42. Replay Plan, Throttling, Cancellation and Results

### 42.1 Plan and dry-run

| ID | Rule |
|---|---|
| PLN-01 | Every R2 operation with more than one case, and every R3, R4, R5 and group-retirement operation, starts from a **plan**. A single-case R2 MAY be requested directly; it is recorded as an operation with one item. |
| PLN-02 | **A plan contains** at least: operation ID; mode; operator or system actor; reason reference; source; target group or groups; event types; version filters; time or position range; organization scope; candidate count; candidates rejected by horizon, per target; candidates requiring reconciliation; candidates with missing provenance; candidates with a missing source; the external / financial risk classification of each target (§41.1); rate and throttle configuration; stop condition. |
| PLN-03 | **Dry-run.** The dry-run computes the candidate set and the counts of PLN-02 without executing any handler, writing any stream entry or changing any case state. Its horizon numbers are a pre-check (HZN-03). |
| PLN-04 | **Bounded.** A plan has explicit bounds on every dimension it selects by, and a maximum candidate count (V1 ceiling: 10 000 per operation; larger work is split into several plans). An unbounded "replay everything" selection is not a valid plan. |
| PLN-05 | **Execution is bound to the plan.** The executor processes exactly the candidate set fixed at approval, identified by case identity or `event_id`. It never widens the selection, and it stops if the plan's fingerprint no longer matches the operation record. A candidate that changed state since the dry-run is re-evaluated individually and gets its true result. |
| PLN-06 | **Operation states**: `DRAFT` → `PLANNED` (dry-run complete) → `APPROVED` → `RUNNING` ⇄ `PAUSED` → `COMPLETED`, `CANCELLED` or `STOPPED` (a stop condition fired). The operation ID is unique; re-submitting the same operation never starts a second execution. |
| PLN-07 | **Organization scope** in a plan only restricts which candidates are selected. It is compared with the organization of each candidate's validated event and never written into anything (§46). |

### 42.2 Throttling

| ID | Rule |
|---|---|
| THR-01 | Every replay operation is rate-limited. No unlimited mode exists. Limits are explicit per operation and per target group. |
| THR-02 | **Conservative V1 startup ceilings** (configurable downward freely; upward only with 7K benchmark evidence, HE-7K-7G-03): 10 items per second per operation; 2 items per second where the target is a high-risk group (CON-06, CON-10); at most one `RUNNING` R2 / R3 operation per target group; at most one `RUNNING` transport-publishing operation (R4, R5) per region. |
| THR-03 | **Normal traffic has priority.** Replay executors are separate activities with their own limiter. They never consume a normal reader's in-flight admission bound and never delay a normal `XREADGROUP` or `XACK`. |
| THR-04 | An operation is paused while the 7K backlog-pressure signal of its target group is raised. Until 7K defines that signal (HE-7K-7G-03), the ceilings of THR-02 apply unchanged and may not be raised. |
| THR-05 | An operation is paused while the target group's dependency gate is open, while the group is `CLOSED` for a cutover or onboarding, and — for R4 / R5 — while the transport capability or publication admission is unavailable. A paused operation consumes no budget and marks no item failed. |
| THR-06 | Correctness never depends on throughput: every item is individually safe under 7F at any rate. |

### 42.3 Cancellation

| ID | Rule |
|---|---|
| CAN-01 | An operation is cancellable between items and between batches. Cancellation stops future items. |
| CAN-02 | Cancellation does not roll back handler effects that already committed, does not rewrite history and does not undo a confirmed transport publication. No transactional rollback of a multi-event replay is promised. |
| CAN-03 | An item that was `REPLAYING` when the operation was cancelled is completed by the operation's recovery (TGT-09) so that its case reaches a definite state; unstarted items get the result `CANCELLED` and their cases stay `PARKED`. |
| CAN-04 | The operation record keeps every item's result and the cancelling actor and reason. A cancelled operation is never resumed implicitly: continuing the remaining work is a new explicit governed action — a new operation whose plan is the unprocessed remainder. |
| CAN-05 | A stop condition (for example the count of `PARKED_AGAIN` results exceeding the plan's bound, or a material digest mismatch) moves the operation to `STOPPED` with the same guarantees as a cancellation. |

### 42.4 Result model

Each candidate ends with exactly one result. Terms follow 7F where 7F has one.

| Result | Meaning | Case afterwards |
|---|---|---|
| `PROCESSED` | The handler committed the effect now | `RESOLVED` |
| `ALREADY_COMMITTED` | The owner's guard proved the effect existed | `RESOLVED` |
| `NOT_APPLICABLE` | The owner's state shows no target (7F XAK-04) | `RESOLVED` |
| `NOT_OWED` | Origin provenance says the group did not owe the event, and no backfill grant covers it | `RESOLVED` |
| `KNOWN_UNSUBSCRIBED` | The pair is legitimate and the group has no obligation for it | `RESOLVED` |
| `BEYOND_HORIZON` | Outside the target's evidence horizon | `RECONCILIATION_PENDING` |
| `RECONCILIATION_REQUIRED` | Another condition requires the owner's reconciliation | `RECONCILIATION_PENDING` |
| `OBLIGATION_RETIRED` | The origin interval is retired | `RECONCILIATION_PENDING` |
| `UNSUPPORTED_VERSION` | The running build cannot process the pair | `PARKED` |
| `PARKED_AGAIN` | The handler failed genuinely, or the material is still contract-invalid, and a `PARKED` recovery case with the exact material now holds the candidate. In R2 the existing case returns to `PARKED`; in R3 the case is created or attached in the same commit (BKL-14) | `PARKED` |
| `ATTACHED_TO_EXISTING_CASE` | R3 only: a non-terminal case already holds this obligation; the grant was linked to it and the handler was not executed by R3 | Unchanged, with the grant linked |
| `OBLIGATION_NOT_ACTIVE` | R3 only: the group has no `OPEN` interval for the type, or the plan's handler-contract generation is no longer current | None |
| `SOURCE_MISSING` | No permitted source holds the event | Unchanged; visible |
| `PROVENANCE_MISSING` | The origin obligation is required and cannot be determined | `PARKED` |
| `TARGET_BLOCKED` | The target is not admitted by §41.1 | Unchanged |
| `CANCELLED` | The operation ended before the item started | Unchanged |
| `PUBLISHED_CONFIRMED` / `PUBLISH_NOT_CONFIRMED` | R4 / R5 only: the 7E outcome of the repair publication | Publisher case `RESOLVED` / `PARKED` |

| ID | Rule |
|---|---|
| RSL-01 | An operation is never reported successful because it was enqueued, started or finished iterating. Its outcome is the multiset of its item results. |
| RSL-02 | For R4 and R5, `PUBLISHED_CONFIRMED` states only that the transport durably accepted the entry. It says nothing about any consumer; each group's processing is visible through the normal consumer signals and any resulting recovery cases. |
| RSL-03 | Every result is recorded on the operation item, and for a case-bound item also on the case (`last_replay_outcome`). |

---

## 43. Replay Must Not Reset Idempotency History (7A RPL-05)

| ID | Rule |
|---|---|
| NRH-01 | No replay mode, operator procedure or tool may: delete a dedup row to force a replay; modify owner state to make an event look new; change an `event_id`; change an `event_version`; rewrite `occurred_at`; change `organization_id`; alter a payload; erase or rewrite canonical origin provenance; reset Billing usage uniqueness; reset Analytics projection or dedup evidence; reset an outbox row; delete or edit a delivery history or an audit row. |
| NRH-02 | If a replay cannot succeed without rewriting historical evidence, raw replay is the wrong tool: the case goes to the owner's reconciliation (R6). |
| NRH-03 | 7G components hold no grant that would allow NRH-01 on owner tables; they act on owner state only by executing the owner's handler through the 7F pipeline (RDM-03). |

---

## 44. Public Webhook Boundary

| ID | Rule |
|---|---|
| WHB-01 | Internal event replay and public webhook delivery replay are different things. The frozen public replay is `POST /api/v1/webhook-deliveries/{delivery_id}/replay` (6J §23.3): it calls `webhooks.fn_replay_webhook_delivery()`, creates a **new** `webhook_deliveries` row linked to the original, keeps the internal domain event identity for tenant dedup, and uses 6J's own retry and dead-letter semantics. |
| WHB-02 | 7G generic recovery never replaces, wraps, calls or imitates that route, and no 7G operation selects a `webhook_deliveries` row as a candidate. A plan whose selection could name a webhook delivery is invalid. |
| WHB-03 | The only contact between 7G and webhooks is CON-10's *creation* of delivery rows as an ordinary consumer, which is blocked as a replay target until its fan-out claim exists (§41.1). Delivery attempts, signing, HTTP retry and delivery dead-lettering are 6J's and 7H's. |
| WHB-04 | The 6J webhook dead-letter store and its 90-day retention (7A §32.3) are unrelated to the 7G recovery ledger. Neither holds the other's records. |

---

## 45. SIGNAL

| ID | Rule |
|---|---|
| SIG-7G-01 | The Analytics SIGNAL consumer `sg.analytics.signal-projections` stays best-effort, `NOACK`, non-authoritative and not guaranteed replayable (7F SIG-7F-01 … SIG-7F-04). |
| SIG-7G-02 | 7G adds no durable DLQ, no recovery case, no retry, no reclaim, no parking and no replay guarantee for SIGNAL entries. The SIGNAL group has no PEL in V1 and is never swept. |
| SIG-7G-03 | SIGNAL history that was trimmed or lost is permitted by contract (7E SGR-03). Nothing recovers it, and SIGNAL is never outboxed to "fix" it. |
| SIG-7G-04 | No 7G replay mode may target the SIGNAL group or publish to a SIGNAL key. |

---

## 46. Tenancy

| ID | Rule |
|---|---|
| TEN-7G-01 | The tenant of a recovery case, a replay item or a redriven entry is the `organization_id` of the **validated original event** (7F TEN-7F-01). It is copied, never derived from a stream key, a group, a plan or an operator input. |
| TEN-7G-02 | No replay request, plan or tool can supply a replacement organization. There is no parameter through which one could be passed into the pipeline. |
| TEN-7G-03 | A platform-scoped event (`organization_id = null`, EV-001) stays platform-scoped through parking and replay. It is never attributed to a tenant. |
| TEN-7G-04 | One organization's recovery case never suppresses, counts against, parks or resolves another organization's event: case identity contains the `event_id`, and every handler execution runs in the tenant context of that event's own envelope with the owner's tenant-checked duplicate proof (7F EID-06). |
| TEN-7G-05 | An organization filter in a plan only restricts selection. It never rewrites event tenancy, and a candidate whose validated organization differs from the filter is simply not selected. |
| TEN-7G-06 | A case whose envelope could not be validated has `organization_scope_trusted = false`. It is never shown, filtered or acted on as belonging to a tenant. |
| TEN-7G-07 | The ledger is platform-internal. No tenant-scoped principal reads it. Final database-role, row-visibility and worker authorization design is 7I's (HE-7I-7G-01). |

---

## 47. Data Residency

| ID | Rule |
|---|---|
| RSD-7G-01 | Every copy created by parking, replay or recovery obeys the frozen region profile (7A RES-01 … RES-03): the recovery ledger and all six components; replay material; operator processing and tooling; the Redis replay target; logs and audit records. |
| RSD-7G-02 | For `INDIA_ENTERPRISE` all of them stay in the contracted region (7A RES-02 names dead-letter and parked messages explicitly). |
| RSD-7G-03 | There is one recovery ledger per region, beside that region's outbox. There is no global replay queue, no cross-region ledger and no cross-region copy of material for convenience. |
| RSD-7G-04 | The repair publisher of a region reads only that region's outbox and ledger and publishes only to that region's event transport (7D RES-7D-01; 7E RSD-01). |
| RSD-7G-05 | Regional disaster-recovery mechanics, including where an R4 runs after a region loss, are 7K's (HE-7K-7G-08) and must satisfy RSD-7G-02. |

---

## 48. Cleanup Interlocks

| ID | Rule |
|---|---|
| ILK-01 | **Publisher `FAILED` cleanup.** The frozen cleanup predicate (`status = 'FAILED' AND last_attempt_at < NOW() - INTERVAL '30 days'`, 7D CLN-02) is unchanged. A `FAILED` row may be deleted by it only when, in addition, the durable condition `publisher_failed_disposition_recorded = true` holds: the row's `PUBLISHER_FAILED` case exists and is `RESOLVED` with one of the four dispositions of §27. |
| ILK-02 | **Redrive material.** While a case has disposition `REDRIVE_APPROVED` and is not yet `RESOLVED`, the row is the redrive source and is not deletable. A row may be deleted before its redrive only if it was first captured under the source-capture contract of DSR-12 (RPM-04); the captured source is then subject to DSR-11. |
| ILK-03 | **A row with no case is not deletable.** The absence of a case means the disposition process never saw the row (PFD-01). |
| ILK-04 | The interlock narrows the frozen predicate; it never widens it and never shortens the 30-day minimum. It is applied by the operator cleanup procedure and its tooling (7D CLN-07), not by a change to `077_5J1`. |
| ILK-05 | **Deleting the outbox row never deletes recovery history.** The publisher case, its history and its audit records follow §25 and remain for at least 90 days after resolution. |
| ILK-06 | **`PUBLISHED` retention.** The 7-day `PUBLISHED` window is frozen (7D CLN-03) and 7G does not lengthen it. An approved, non-terminal R4 operation obtains a source that outlives the row only through the governed capture of DSR-12; it MAY alternatively exclude the rows of its own bounded scope from the operator cleanup run for its duration. Either is explicit, audited and bounded by the operation; neither is a silent or standing extension. Deleting the row after a capture removes the position fallback (PRV-06): from then on the captured source is publishable only with complete canonical provenance (DSR-11). |
| ILK-07 | Once a `PUBLISHED` row is deleted and no captured material exists, every later attempt to replay it reports `SOURCE_MISSING` (DSR-06). |
| ILK-08 | Outbox cleanup never uses Redis state, and stream trimming never uses outbox or ledger state (7D CLN-05; 7E TRM-10). The interlocks above read PostgreSQL only. |

---

## 49. Future Recovery-Ledger Migration Requirement

| ID | Rule |
|---|---|
| MIG-01 | OD-7G-02 requires a physical ledger. It is delivered by **one governed future Phase-5 migration**, owned by the Audit / Event Operations context, in the existing `audit` schema. 7G creates no migration, chooses no migration number, edits no Phase-5 document and does not modify the executed baseline. No migration 113 exists. |
| MIG-02 | Until that migration is executed and validated, **no durable consumer may park, record a failure or run any replay**, and consumer production operation stays blocked (§56). The runtime is never operated "without the ledger". |
| MIG-03 | Table names, column names, types, indexes, partitioning and the function surface are chosen by that migration. It MUST implement the constraint semantics MR-01 … MR-18 below. |

| # | Required constraint semantics |
|---|---|
| MR-01 | **Canonical unique recovery identity:** uniqueness of `(case_kind, logical_group, event_id, event_type)` for `CONSUMER` and `PUBLISHER_FAILED` cases; of `(logical_group, identity_digest)` for `CONSUMER_UNIDENTIFIED`; of `(logical_group, physical_key, redis_entry_id)` for `TRANSPORT_INTEGRITY`. No identity contains the Redis entry ID except the last. |
| MR-02 | **Valid states and transitions:** `state` restricted to the six values of §24; transitions only as in §24.2, enforced so that `RESOLVED` is never left and `PARKED` never returns to `OPEN_RETRY`. |
| MR-03 | **Atomic failure record:** a single-statement insert-or-update that increments the count only in `OPEN_RETRY` / `HOLD` and sets `PARKED` when the count reaches the budget (RTY-05). |
| MR-04 | **Counters:** `0 ≤ handler_failure_count ≤ failure_budget`; `failure_budget = 5`; `isolation_attempts ≥ 0`; `replay_count ≥ 0`; delivery-count fields `≥ 0`. |
| MR-05 | **Timestamps:** `first_seen_at ≤ last_seen_at`; `parked_at` present exactly when the case has entered `PARKED` or `RECONCILIATION_PENDING`; `resolved_at` present exactly in `RESOLVED`. |
| MR-06 | **Immutable original event identity:** `case_kind`, `logical_group`, `event_id`, `event_type`, `event_version`, `organization_id`, `organization_scope_trusted` and `identity_digest` cannot change after insert. |
| MR-07 | **Tenant-safe scope:** `organization_id` nullable (platform scope or untrusted), never defaulted, never operator-writable; no tenant-scoped principal has any privilege on the ledger. |
| MR-08 | **Material present where required:** a case in `PARKED`, `REPLAYING` or `RECONCILIATION_PENDING` of kind `CONSUMER` or `CONSUMER_UNIDENTIFIED` references material, or — in `RECONCILIATION_PENDING` only — a recorded privacy-erasure tombstone (RPM-12); material rows are insert-only with a stored SHA-256. |
| MR-09 | **Canonical provenance:** uniqueness of `(logical_group, event_id, event_type)` in the provenance component; `origin_obligation` restricted to `OWED` / `NOT_OWED`; insert-if-absent only; no `UPDATE` privilege on the correctness columns for any role. |
| MR-10 | **Retention fields:** `retention_eligible_at` NULL unless `state = RESOLVED`, and then `≥ resolved_at + 90 days`; cleanup can select only by it. |
| MR-11 | **Safe error fields:** `failure_class` and `safe_error_category` restricted to the closed lists of §10; bounded length; no free-text error column. |
| MR-12 | **Replay state:** operation states restricted to PLN-06; item states `PENDING`, `EXECUTING` and terminal with exactly one result from §42.4; a case references at most one non-terminal operation; an R3 item result that needs recovery (BKL-14) can be committed only together with its recovery case. |
| MR-13 | **Disposition completeness:** a `RESOLVED` case has a resolution, an actor, a time and — for operator dispositions — a reason reference. |
| MR-14 | **Auditability:** append-only case history; no `UPDATE` or `DELETE` on history rows before retention eligibility. |
| MR-15 | **Publisher interlock:** a queryable, durable form of `publisher_failed_disposition_recorded` usable by the cleanup procedure (ILK-01). |
| MR-16 | **Backfill grant:** an immutable, insert-if-absent record unique per (group, `event_id`, `event_type`), naming the granting operation; not deletable while a recovery case references it; not deleted by operation cleanup (BKL-21). |
| MR-17 | **Captured source:** the capture record of DSR-12 — event identity, type and version, organization scope, family, capture time, capturing operation, the per-group registry snapshot with handler-contract generation and origin link, `provenance_complete` and the list of groups lacking provenance; immutable except for completion while the outbox row exists (DSR-13). |
| MR-18 | **Disposition authority:** the permitted (case class, terminal resolution, required reference) combinations of §24.4 are enforced by constraint or guarded function; `case_class` is derived and not writable; a class `V` case cannot be given `PERMANENTLY_REJECTED_WITH_REASON`; `SUPERSEDED_BY_OWNER_RECONCILIATION` and `OWNER_RECONCILED` cannot be recorded without an owning-domain reconciliation reference; `OBLIGATION_GOVERNED_AWAY` cannot be recorded without a retirement operation and its governed-change reference. |

---

## 50. Implementation-Level Pseudocode

The pseudocode fixes the order of the safety boundaries. An implementation may differ in structure but not in that order.

### 50.1 Entry processing with the recovery-case gate

```text
PROCESS-ENTRY(g, K, entry_id, fields, via_sweep):
    raw := exact bytes of fields                                  -- RPM-06
    cls := 7F classify D-01 … D-05                                -- unchanged 7F
    if cls is KNOWN_UNSUBSCRIBED and not via_sweep:
        XACK K g entry_id; return                                 -- 7F XAK-03
    case := LEDGER-READ(identity_of(g, cls, raw))                 -- RTY-01 (dependency failure → GATE-OPEN)
    if case.state in {PARKED, REPLAYING} or terminal_rejection(case)
       or (case.state = RECONCILIATION_PENDING and ack_permitted(case)):
        PARKED-DUPLICATE(g, K, entry_id, raw, case); return       -- PAT-07
    if case.state = RECONCILIATION_PENDING: return                -- Billing: stay pending (BIL-04)
    if cls in {permanent classes FC-01 … FC-05}: PARK(g, K, entry_id, raw, cls); return
    if cls in {compatibility hold FC-06, key not onboarded FC-09}: HOLD(g, K, entry_id, cls); return
    if cls is OBLIGATION_RETIRED: RECONCILE(g, K, entry_id, raw, cls); return
    outcome := 7F D-06 … D-09 in the owner transaction            -- unchanged 7F; in-attempt retries RTY-03
    if outcome in {DURABLY_COMMITTED, ALREADY_COMMITTED, NOT_APPLICABLE, KNOWN_UNSUBSCRIBED}:
        if case exists (OPEN_RETRY or HOLD):
            commit case → RESOLVED(outcome)   or else return      -- RTY-10: no XACK if this fails
        XACK K g entry_id; return
    if outcome is BEYOND_HORIZON: RECONCILE(g, K, entry_id, raw, outcome); return
    rc := CLASSIFY-FAILURE(outcome, probe)                        -- §10.2
    if rc is TRANSIENT_DEPENDENCY: GATE-OPEN(g); return           -- no record, no count (GTE-05)
    FAILURE-RECORD(g, K, entry_id, raw)                           -- §50.2
```

### 50.2 Failure record and the fifth failure

```text
FAILURE-RECORD(g, K, entry_id, raw):                              -- at most once per attempt (RTY-06)
    BEGIN                                                         -- ledger only; no Redis, no owner statement
      (state, count) := atomic insert-or-update on (g, event_id, event_type):
            absent                → OPEN_RETRY, count = 1
            OPEN_RETRY or HOLD    → OPEN_RETRY, count = count + 1
            otherwise             → unchanged
            if count = failure_budget (5) → PARKED, reason POISON_BUDGET_EXHAUSTED
      record transport observation (K, entry_id, delivery count)
      if state = PARKED: store material(raw); insert-if-absent origin provenance
    COMMIT                                                        -- failure or unknown outcome: stop, no XACK
    if state = PARKED: XACK K g entry_id                          -- PAT-01: only after the commit
    else: leave the entry pending                                 -- retried by the sweep (RTD-01)
```

### 50.3 Parking

```text
PARK(g, K, entry_id, raw, reason):
    BEGIN
      insert-if-absent case → PARKED(reason), parked_at
      store material(raw)                                         -- RPM-01: same transaction
      insert-if-absent origin provenance where the identity is trusted
      record transport observation, history entry
    COMMIT                                                        -- on failure: return; the entry stays pending (PAT-03)
    r := XACK K g entry_id                                        -- never before the commit (PAT-02)
    if r = 0: record observation                                  -- PAT-05
    on error / lost reply: re-issue; else mark ACK_UNCONFIRMED    -- PAT-06
```

### 50.4 Stale-entry sweep

```text
SWEEP(g, K):                                                      -- every cadence, per (key, group); admitted member only
    if gate(g) is OPEN or K not onboarded: return
    lo := smallest pending ID   (XPENDING K g)                    -- read-only
    first := first entry ID     (XINFO STREAM K)                  -- read-only
    if lo exists and lo < first: INTEGRITY(g, K); return          -- RCL-06: no claim command
    cursor := 0-0
    repeat:
        (cursor, entries, deleted) := XAUTOCLAIM K g me reclaim_min_idle cursor COUNT n
        for id in deleted: record TRANSPORT_INTEGRITY case        -- RCL-07
        counts := XPENDING K g <range of entries> n me            -- diagnostics only (RCL-08)
        for e in entries:
            if unrecorded_deliveries(e, counts) ≥ crash_loop_delivery_threshold: ISOLATE(e); continue
            PROCESS-ENTRY(g, K, e.id, e.fields, via_sweep = true) -- same pipeline (RCL-02)
    until cursor = 0-0
```

### 50.5 Targeted consumer replay (R2)

```text
REPLAY-CASE(op, case):                                            -- op APPROVED, executor admitted (TGT-05)
    if not CAS(case: PARKED → REPLAYING, op): return              -- duplicate request: no effect (TGT-10)
    if not eligible(case) or target_blocked(case.group): finish(TARGET_BLOCKED or …); return
    raw := material(case); verify digest
    cls := 7F classify D-01 … D-05 on raw                         -- current build
    obligation := origin provenance(case)                         -- TGT-04; missing → PROVENANCE_MISSING
    if obligation = NOT_OWED and no backfill grant: finish(NOT_OWED); return
    if origin interval retired: finish(OBLIGATION_RETIRED); return
    outcome := 7F D-06 … D-09 in the owner transaction            -- horizon gate inside (HZN-03)
    finish(map(outcome))                                          -- T-11 / T-12 / T-13; no XACK exists
-- crash between the owner commit and finish(): the operation's recovery re-runs the item;
-- the guard returns ALREADY_COMMITTED and finish() completes the case (TGT-09).
```

### 50.6 Future-consumer backfill item (R3)

```text
BACKFILL-ITEM(op, item):                                          -- op APPROVED; item fixed (BF-1)
    if not CAS(item: PENDING → EXECUTING): return                 -- BF-2; recovery re-enters here (BF-8)
    existing := LEDGER-READ(item.group, item.event_id, item.event_type)
    BEGIN                                                         -- BF-4: preparation commit
      raw := read source; store material(raw, sha256) bound to item
      origin := existing origin record, else determine (BKL-13) and insert-if-absent
      if origin undeterminable: ROLLBACK; finish-item(PROVENANCE_MISSING); return
      if origin = NOT_OWED: insert-if-absent backfill grant(item.group, event_id, event_type, op)
    COMMIT
    if existing is non-terminal: link grant to existing; finish-item(ATTACHED_TO_EXISTING_CASE); return   -- BF-3
    if existing is a terminal rejection: finish-item(TARGET_BLOCKED); return
    if target_blocked or no OPEN interval or generation changed or pair unsupported:
        finish-item(TARGET_BLOCKED | OBLIGATION_NOT_ACTIVE | UNSUPPORTED_VERSION); return               -- BF-5
    outcome := 7F D-01 … D-09 on raw, in the owner transaction    -- BF-6: once; horizon gate inside
    if outcome is dependency-wide failure: item → PENDING; pause op; return
    BEGIN                                                         -- BF-7: outcome commit, ledger only
      if outcome needs recovery (BKL-14):
          create-or-attach case(item.group, event_id, event_type) → PARKED | RECONCILIATION_PENDING
              with material, origin link, grant link, history    -- T-17 / T-18; idempotent (BKL-15)
      item → terminal(result(outcome))
    COMMIT                                                        -- one transaction: no result without its case
-- crash anywhere before the outcome commit: the item is still EXECUTING and its material is durable;
-- recovery re-runs it. After an owner commit the guard returns ALREADY_COMMITTED (BKL-17 … BKL-20).
```

### 50.7 Source capture and shared-stream publication from a captured source (R4)

```text
CAPTURE(op, outbox_id):                                           -- DSR-12; one PostgreSQL transaction
    BEGIN
      row := SELECT … FROM audit.domain_event_outbox WHERE id = outbox_id FOR SHARE   -- conflicts with deletion
      if row absent: ROLLBACK; result SOURCE_MISSING; return
      store material(materialize(row), sha256); record identity, type, version, scope, family, capture time, op
      for g in groups registered for family(row.event_type):
          if O(g, row.id, row.event_type) exists: link it
          else if contract(g) is OPEN and no change in progress:
              insert-if-absent O(g, …) := (generation(g), OWED if contract(g) owes the type else NOT_OWED)   -- PRV-10
          else: mark g as lacking provenance
      provenance_complete := every snapshot group has O
    COMMIT

PUBLISH-FROM-SOURCE(op, item):                                    -- repair publisher
    register publication attempt for the type                     -- 7F HCG-26; refused while admission is CLOSED
    if outbox row of item still exists: position fallback permitted (PRV-06)
    else:                                                         -- captured source, row gone
        for g in every group registered for or present on a live key of the family:
            if O(g, event_id, event_type) absent:
                deregister; finish-item(PROVENANCE_MISSING); return                    -- DSR-11: nothing is published
    XADD + WAITAOF 1 1 through the frozen 7E adapter; deregister; finish-item(by 7E outcome)
```

---

## 51. Failure Matrix

Columns: **State** = the authoritative state; **Auto** = automatic retry; **Budget** = effect on the OD-7G-01 poison budget; **Park** = whether the case is parked; **Replay** / **Recon** = whether an explicit replay or owner reconciliation follows; **Record** = `History` (automatic transition recorded in case history and emitted as a signal) or `Audit` (privileged action recorded through the audit boundary); **Loss** = loss of a durable obligation possible; **Dup** = duplicate business effect possible.

### 51.1 Consumer retry and reclaim

| ID | Case | State | Auto | Budget | Park | `XACK` | Replay | Recon | Record | Loss | Dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| F7G-01 | Worker crashes right after delivery | PEL (transport); owner state unchanged | Yes — sweep after `reclaim_min_idle` | None | No | No | No | No | — | No | No |
| F7G-02 | Worker crashes during validation | PEL | Yes — sweep | None | No | No | No | No | — | No | No (validation writes nothing) |
| F7G-03 | Worker crashes during the handler | PEL; owner transaction rolled back | Yes — sweep | None (no committed record, CNT-07) | No | No | No | No | — | No | No |
| F7G-04 | Worker crashes after the business commit, before `XACK` | Owner guard (committed) | Yes — sweep → `ALREADY_COMMITTED` | None | No | Yes, on the redelivery | No | No | — | No | No (7F CRI-01) |
| F7G-05 | Stale consumer's entry reclaimed while it is still running | Owner guard arbitrates | Yes | None | No | Both may; one returns 0 | No | No | — | No | No (7F CRP-11) |
| F7G-06 | Two sweep workers contend for the same stale entries | PEL | Yes | None | No | Per entry | No | No | — | No | No (`XAUTOCLAIM` gives each entry to one caller, IDL-10) |
| F7G-07 | Redis delivery count inflated (deployments, lost replies) | Ledger count, not Redis | Yes | **None** (CNT-02) | Not by the count | Per outcome | No | No | Diagnostic field | No | No |
| F7G-08 | Owner database outage | Owner database; PEL | Suspended — dependency gate open | **None** (GTE-05) | No | No | No | No | Signal | No | No |
| F7G-09 | Handler-contract store outage | Handler-contract record | Suspended — member stops reading (7F HCG-04) | None | No | No | No | No | Signal | No | No |
| F7G-10 | Genuine retryable handler failure 1 – 4 | Ledger case `OPEN_RETRY` | Yes — sweep | +1 per committed record | No | No | No | No | History | No | No |
| F7G-11 | Fifth genuine failure | Ledger case `PARKED` | **No** — no sixth execution | Reaches 5 | **Yes** | Yes, after the park commit | R2, explicit | Possible | History | No | No |
| F7G-12 | Permanent malformed event | Ledger case `PARKED` | No | None | Yes, immediately | Yes, after commit | R2 after a fix | Possible | History | No | No |
| F7G-13 | Unsupported version (pair unknown to this build) | Ledger case `HOLD` | Classification only | None | After `compat_hold_max_age` | No while held; yes after park | R2 after park | No | History | No | No |
| F7G-14 | Beyond the evidence horizon | Ledger case `RECONCILIATION_PENDING` | No | None | Hand-off | Yes after commit; Billing: deferred | No raw replay | **Yes** | History | No | No (no guard statement runs) |
| F7G-15 | Retired obligation (C-11) | Ledger case `RECONCILIATION_PENDING` | No | None | Hand-off | Yes, after commit | No | Yes, or explicit disposition | History | No | No |
| F7G-16 | Topology anomaly: key not onboarded | Handler-contract record; ledger `HOLD` | No; key-level gate | None | No | No | No | No | History + alert | No | No |
| F7G-17 | Deterministic process crash loop | Ledger case `HOLD` → `PARKED` | Isolation only | **None** (separate bound, §17) | Yes, after the isolation limit | Yes, after commit | R2 after a fix | Possible | History + alert | No | No |
| F7G-18 | Two workers both fail the same event at count 4 | Ledger row lock | — | Exactly 5 | Once | By either, after commit | — | — | History | No | No (RTY-07) |
| F7G-19 | Failure-record commit outcome unknown | Whatever committed | Yes — sweep | 0 or +1, never +2 (RTY-06) | Only if it committed at 5 | Only on a later delivery that reads `PARKED` | — | — | History if committed | No | No |
| F7G-20 | Recovery ledger unavailable | — | Suspended — dependency gate (GTE-08) | None | No | No | No | No | Signal | No | No |
| F7G-21 | Success after earlier failures, but the case-resolution commit fails | Owner guard (committed) | Yes — redelivery → `ALREADY_COMMITTED` → resolve | None | No | Only after the case is `RESOLVED` (RTY-10) | No | No | History | No | No |

### 51.2 Parking

| ID | Case | State | Auto | Budget | Park | `XACK` | Replay | Recon | Record | Loss | Dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| F7G-22 | Parking transaction fails | PEL; no case change | Entry reclaimed later; parking re-attempted | Unchanged | Not yet | **No** (PAT-03) | — | — | Signal | No | No |
| F7G-23 | Parking commits, then `XACK` | Ledger `PARKED` | No | — | Yes | Yes | R2 | — | History | No | No |
| F7G-24 | Process dies after the parking commit, before `XACK` | Ledger `PARKED` | Redelivery only to acknowledge | — | Already | Yes, on the duplicate path (PAT-04) | R2 | — | History | No | No (handler not executed) |
| F7G-25 | `XACK` returns 0 after parking | Ledger `PARKED` | No | — | Already | Treated as finished (PAT-05) | R2 | — | Observation | No | No |
| F7G-26 | `XACK` connection lost after parking | Ledger `PARKED` | Re-issue; else `ACK_UNCONFIRMED` | — | Already | Unknown → reconciled later (PAT-06) | R2 | — | Observation | No | No |
| F7G-27 | Another Redis entry of the same event arrives after `PARKED` | Ledger `PARKED` (one case) | No | — | Already; no second case | Yes, after the observation commits (PAT-07) | R2 | — | Observation | No | No |
| F7G-28 | Stream trims the entry after parking | Ledger material | — | — | Already | — | R2 from material | — | — | No (RPM-01) | No |
| F7G-29 | Replay material cannot be stored | PEL | Entry reclaimed later | Unchanged | **No** — transition refused | **No** (RPM-05) | — | — | Signal + alert | No | No |
| F7G-30 | A parked case is older than 90 days and unresolved | Ledger `PARKED` | No | — | Stays parked | — | Per horizon | Possible | — | **No** — never cleaned (PRT-02) | No |
| F7G-31 | Pending ID whose stream entry is missing | Ledger `TRANSPORT_INTEGRITY` case | No | None | Yes (integrity) | Not applicable | Only from an authoritative source | Incident | History + alert | Outside-model fault; never silent | No |

### 51.3 Publisher

| ID | Case | State | Auto | Budget | Park | `XACK` | Replay | Recon | Record | Loss | Dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| F7G-32 | `ROW_REJECTED`, budget not reached | Outbox row `PENDING`, `available_at` + 30 s | Yes — normal relay (PUB-01) | Publisher domain only | No | n/a | No | No | — | No | No |
| F7G-33 | A claim-inflated `attempt_count` reaches `FAILED` on a first real rejection | Outbox row `FAILED`; publisher case | **No** | n/a | Publisher case `PARKED` | n/a | R5 only if approved | Possible | Audit on disposition | No | No |
| F7G-34 | `FAILED` row without a disposition | Outbox row `FAILED`; publisher case `PARKED` | No | n/a | Yes | n/a | No | No | Visible signal | No — retained (ILK-03) | No |
| F7G-35 | Explicit redrive succeeds | Row still `FAILED`; case `RESOLVED` / `REDRIVEN` | No | n/a | — | n/a | R5 done | No | Audit | No | No (same `event_id`; 7F guards) |
| F7G-36 | Explicit redrive fails or is `UNKNOWN` | Row still `FAILED`; case back to `PARKED` | **No loop** (PRD-08) | n/a | Yes | n/a | Another explicit action | No | Audit | No | No |
| F7G-37 | Cleanup tries to delete a `FAILED` row before its disposition | Outbox row | — | n/a | — | n/a | — | — | Audit of the refused run | No — refused (ILK-01) | No |

### 51.4 Replay

| ID | Case | State | Auto | Budget | Park | `XACK` | Replay | Recon | Record | Loss | Dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| F7G-38 | Replay target inside its horizon | Owner guard | No | None | `RESOLVED` on success | None (no entry) | R2 → `PROCESSED` or `ALREADY_COMMITTED` | No | Audit | No | No |
| F7G-39 | Replay target beyond its horizon | Owner horizon gate | No | None | `RECONCILIATION_PENDING` | None | **Refused** (HZN-04) | Yes | Audit | No | No |
| F7G-40 | Canonical provenance missing | Ledger | No | None | Stays `PARKED` | None | `PROVENANCE_MISSING`; handler not run | Possible | Audit | No | No |
| F7G-41 | Source envelope missing | — | No | None | Unchanged | None | `SOURCE_MISSING`; nothing fabricated | Owner rebuild | Audit | Reported, never hidden | No |
| F7G-42 | Replay after a later handler cutover | Origin provenance | No | None | Per result | None / per group | Classified by origin, not by the new Redis ID or `H_active` | — | Audit | No | No |
| F7G-43 | Replay after a topology-generation change | Origin provenance (per logical group) | No | None | Per result | Per group | Same `event_id`, same obligation (TPG-01) | — | Audit | No | No |
| F7G-44 | Duplicate replay request | Ledger compare-and-swap | No | None | — | None | Second request has no effect (TGT-10) | — | Audit | No | No |
| F7G-45 | Operator cancels midway | Operation record | No | None | Unstarted cases stay `PARKED` | None | Stops future items; nothing rolled back | — | Audit | No | No |
| F7G-46 | Process dies after the replayed effect commits | Owner guard | Operation recovery only | None | `RESOLVED` after recovery | None | Re-run → `ALREADY_COMMITTED` (TGT-09) | — | Audit | No | No |
| F7G-47 | A public webhook delivery is selected by generic replay | — | — | — | — | — | **Invalid plan** (WHB-02); 6J route only | — | Audit of the rejection | No | No |
| F7G-48 | Billing replay would duplicate usage | `uq_ue_idempotency` inside 90 days; horizon gate beyond | No | None | Per result | None | Inside: `ALREADY_COMMITTED`. Beyond: refused | Billing | Audit | No | No |
| F7G-49 | A replay would cause a second physical call | Campaign job compare-and-swap; dispatch keys | No | None | Per result | None | The handler places no call; a stale outcome changes 0 rows | — | Audit | No | No |
| F7G-50 | Tenant scope mismatch (filter or supplied organization differs from the event) | Validated envelope | No | None | — | None | Candidate not selected; no override exists (TEN-7G-02) | — | Audit | No | No |
| F7G-51 | Replay targets CON-10 before its fan-out claim exists | §41.1 | No | None | Unchanged | None | `TARGET_BLOCKED` | — | Audit | No | No |

### 51.5 Group lifecycle

| ID | Case | State | Auto | Budget | Park | `XACK` | Replay | Recon | Record | Loss | Dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| F7G-52 | Pending entry exists during group retirement | PEL + recorded disposition | No | None | Per GR-6 | Per disposition | Possible | Possible | Audit | No — retirement stops otherwise (GRT-03) | No |
| F7G-53 | Parked case exists during group retirement | Ledger | No | None | Until dispositioned (GR-7) | — | Possible before destroy | Possible | Audit | No | No |
| F7G-54 | `XGROUP SETID` or a backfill read while trimming is active | — | — | — | — | — | **Refused**: trim pause first (BKL-08 … BKL-10) | — | Audit | No | No |
| F7G-55 | Old key removed while a replay source references it | Operation record | — | — | — | — | Key retirement blocked while a non-terminal operation references it (TPG-05); cases never depend on a key | — | Audit | No | No |
| F7G-56 | SIGNAL entry lost or trimmed | None (non-durable) | No | None | No | n/a | None (§45) | No | Counted by 7F | **Permitted by contract** | No |

### 51.6 Cases added by the independent freeze-gate review

| ID | Case | State | Auto | Budget | Park | `XACK` | Replay | Recon | Record | Loss | Dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| F7G-57 | Captured R4 source; its outbox row is deleted; type `D` is later added to group G; the source is replayed | Canonical origin (ledger) | No | None | — | Per group | Published only if every receiving group has an origin record; G's record says `NOT_OWED`, so G acknowledges it as not owed. With no record for G: `PROVENANCE_MISSING`, nothing published (DSR-11) | R6 if the event is needed | Audit | No | No — the new Redis position never makes it owed |
| F7G-58 | Captured R4 source of an originally owed event; row deleted; the type is later removed from the group; replayed above the removal boundary | Canonical origin `OWED`, written at capture (PRV-10) | No | None | Per result | Per group | Processed under its origin interval, or `OBLIGATION_RETIRED` → reconciliation; never `NOT_OWED` by position | Possible | Audit | No | No |
| F7G-59 | One currently subscribed group has no origin record for a captured source whose row is gone | Ledger | No | None | — | None | **Not published**: `PROVENANCE_MISSING`, fail closed (DSR-11) | R6 | Audit | No | No |
| F7G-60 | A group is created after the capture and before the replay | Ledger | No | None | — | Per group | `NOT_OWED` record written at group creation (DSR-14), or the source is replay-blocked; the new group never acquires the old event | — | Audit | No | No |
| F7G-61 | R3 handler fails genuinely; no recovery case existed | Ledger case `PARKED`, created in the item's outcome commit (T-17) | No | None (count 0) | Yes | None | `PARKED_AGAIN`; later R2 under the linked grant | Possible | Audit | No | No |
| F7G-62 | R3 crash before the handler | Operation item `EXECUTING` | Operation recovery | None | No | None | Item re-run; preparation is idempotent (BKL-17) | — | Audit | No | No |
| F7G-63 | R3 crash after the owner effect commits, before the item result | Owner guard | Operation recovery | None | No | None | Re-run → `ALREADY_COMMITTED`; item completes (BKL-18) | — | Audit | No | No |
| F7G-64 | R3 crash after the handler failed, before the case exists | Operation item `EXECUTING`; material durable | Operation recovery | None | On the re-run, if it fails again | None | Candidate and source cannot disappear (BKL-19) | — | Audit | No | No |
| F7G-65 | R3 crash after the case exists, before the item result | Ledger case (canonical identity) | Operation recovery | None | Already | None | Recovery attaches to the existing case; no second case (BKL-20) | — | Audit | No | No |
| F7G-66 | The R3 operation is cleaned up after 90 days while its parked case is unresolved | Backfill grant (LC-4) | No | None | Stays parked | None | Grant retained; R2 still runs under it, never `NOT_OWED` (BKL-21) | — | — | No | No |
| F7G-67 | A generic operator tries to reject permanently a valid owed case parked for `POISON_BUDGET_EXHAUSTED` | Ledger (class `V`) | No | None | Stays parked | None | **Refused** (DAU-02, DAU-03) | Owner reconciliation is the path | Audit of the refusal | No | No |
| F7G-68 | `SUPERSEDED_BY_OWNER_RECONCILIATION` requested without an owning-domain reconciliation reference | Ledger | No | None | Stays parked | None | Refused (DAU-04) | — | Audit of the refusal | No | No |
| F7G-69 | `OBLIGATION_GOVERNED_AWAY` requested outside a governed retirement | Ledger | No | None | Stays parked | None | Refused (DAU-05) | — | Audit of the refusal | No | No |
| F7G-70 | A privacy rule requires erasing the material of an unresolved valid case | Ledger case `RECONCILIATION_PENDING` | No | None | Not resolved | None | Raw replay no longer possible | **Yes** — owner decides (RPM-12) | Audit | No — the obligation is retained | No |
| F7G-71 | A pending ID inside the stream range has no entry (ungoverned `XDEL`) | Best-effort `TRANSPORT_INTEGRITY` case from the claim reply | No | None | Integrity case | Not applicable | Only from an authoritative source | Incident | History + alert | Outside-model fault; residual evidence window stated (RCL-07) | No |

---

## 52. Downstream Handoffs

Handoffs issued by 7G carry the infix `7G`.

### 52.1 To 7H (external delivery)

| ID | 7H receives |
|---|---|
| HE-7H-7G-01 | The boundary of §44: 7G never replays a webhook delivery; public replay stays the frozen 6J route with its own retry and dead-letter semantics. 7H owns external delivery mechanics. |
| HE-7H-7G-02 | CON-10 as a consumer becomes a 7G replay target only after IO-7F-21; a replayed internal event fans out to endpoints active at processing time, which 7H must account for in tenant-visible semantics. |

### 52.2 To 7I (security / privacy)

| ID | 7I receives |
|---|---|
| HE-7I-7G-01 | Final roles, grants and principals for the capabilities of §40, including whether requester ≠ approver is a hard control (AUT-04), the database roles of the recovery workers, and the Redis ACL users for the sweep (`XAUTOCLAIM`, `XPENDING`, `XINFO`) and for the operator-only commands (7E SCY-05). |
| HE-7I-7G-02 | Sensitivity classification of the recovery ledger and of stored replay material; encryption at rest; redaction; column or blob access; the payload-view permission and its audit (RPM-11, AUT-07). |
| HE-7I-7G-03 | Retention and DSR interaction: whether material must be erased earlier than case metadata, and the rule for an erasure request that touches an unresolved case (PRT-06). |
| HE-7I-7G-04 | Reason and ticket requirements for each operation, and the required audit contents (AUT-05). |
| HE-7I-7G-05 | Data-residency controls for the ledger, material, tooling and operator access (§47). |
| HE-7I-7G-06 | Confirmation that no tenant-facing surface exposes a recovery case or material, and the representation of organization scope in recovery logs (7D SEC-7D-03). |

### 52.3 To 7J (observability) — semantic signals only, no names or thresholds

Per group and key unless stated: PEL reclaim attempts and reclaim successes (entries claimed); pending age (oldest, and distribution); genuine handler failure count per recorded failure and its distribution; Redis delivery count observed; crash-loop suspected, isolation attempts and isolation outcomes; dependency-gate open and close, with the dependency; parking created, by reason; immediate parking by reason; poison-threshold parking; compatibility holds created, cleared and expired; key-not-onboarded holds; parking commit failure; material-store refusal; `XACK` after parking; `XACK` zero result or error after parking and `ACK_UNCONFIRMED` cases; open parked-case count and age; reconciliation-pending count and age by owner; publisher `FAILED` count by disposition and undispositioned age; publisher redrive requested, succeeded and failed; replay operation created, approved, started, paused, stopped, cancelled and completed, by mode; replay outcome classes (§42.4); horizon rejects by target; missing provenance; missing replay source; target-blocked results; group-retirement operations and their per-entry dispositions; dangling-PEL (missing stream entry) anomalies; material digest mismatches; replay throttling and pause time; replay cancellation; trim pauses held by operations; canonical provenance records written, and retirement runs with their proofs; ledger cleanup runs. HE-7J-7G-01 hands this list to 7J. No signal carries a raw tenant payload, a material fragment or an unbounded tenant label (7D OBS-7D-C1, C2).

### 52.4 To 7K (capacity) — 7G correctness is independent of every value below

| ID | 7K receives |
|---|---|
| HE-7K-7G-01 | Reclaim worker count; sweep batch size; sweep cadence tuning; the final benchmarked idle threshold against measured handler latency (IDL-07). |
| HE-7K-7G-02 | The cost of the per-entry recovery-case read (RTY-01) on the normal path. |
| HE-7K-7G-03 | Replay worker count, batch size, throughput and rate limits; the backlog-pressure signal that pauses replay (THR-04); any raising of the THR-02 ceilings. |
| HE-7K-7G-04 | Stream growth while a trim pause is held (BKL-10), and maintenance windows for group retirement and `XGROUP SETID` repair. |
| HE-7K-7G-05 | The trim pin caused by held entries: compatibility holds up to `compat_hold_max_age`, key-not-onboarded holds, and Billing beyond-horizon entries held until Billing's decision (BIL-05). |
| HE-7K-7G-06 | Backlog retained during a dependency outage and catch-up after it (GTE-06). |
| HE-7K-7G-07 | Parking-table growth; replay-material storage growth; unresolved-case capacity; the 90-day resolved-case storage estimate; provenance-record growth; cleanup schedules and batch sizes (PCL-04). |
| HE-7K-7G-08 | Regional disaster-replay throughput and sequencing; where an R4 executes after a region loss (RSD-7G-05). |
| HE-7K-7G-09 | Isolation-activity capacity for crash-loop entries (§17). |
| HE-7K-7G-10 | The incident procedure for an unrecoverable missing entry (DGL-05). |

### 52.5 To 7L (final reconciliation)

| ID | 7L receives |
|---|---|
| HE-7L-7G-01 | CNF-7G-01 … CNF-7G-09 (§58). |
| HE-7L-7G-02 | The activation register of §56 as the recovery go-live checklist. |
| HE-7L-7G-03 | The 7F activation blockers that 7G carries forward unchanged (§56.2). |

---

## 53. ADR Register

Frozen upstream facts (at-least-once delivery, the outbox, the transport, the `XACK` success contract, the evidence horizons, origin provenance semantics) are referenced, not re-decided.

| ADR | Decision | Alternatives rejected | Rules |
|---|---|---|---|
| ADR-7G-01 | **Classification-aware bounded retry** (OD-7G-01): five durably recorded genuine handler failures park an event; dependency, capability, horizon and topology conditions consume nothing; permanent input parks at once | One undifferentiated attempt limit; unlimited retry; counting every delivery | §10, §14, §22 |
| ADR-7G-02 | **The authoritative retry count is a ledger counter, not the Redis delivery count** | Parking on `XPENDING` delivery count; `XCLAIM RETRYCOUNT` manipulation | CNT-01 … CNT-09 |
| ADR-7G-03 | **Reclaim by `XAUTOCLAIM` stale-entry sweep** with a restricted option subset and a read-only dangling pre-check | Own-PEL re-read loops; `XCLAIM` as the normal path; `FORCE`, `LASTID`, `RETRYCOUNT`, `IDLE`; post-7.2 commands | RCL-01 … RCL-14, IDL-01 … IDL-10 |
| ADR-7G-04 | **Constant reclaim-driven retry delay** with one clock | Per-entry `next_retry_at`; exponential backoff; sleeping workers | RTD-01 … RTD-06 |
| ADR-7G-05 | **Dependency gate**: a broad outage stops reads and sweeps and writes no failure record | Counting outage failures; parking during an outage; consuming into the PEL without bound | GTE-01 … GTE-10 |
| ADR-7G-06 | **Crash-loop bound separate from the poison budget**, using the Redis delivery count only as a safety signal, with pre-recorded isolated attempts | Unbounded redelivery of a process-crasher; folding crashes into the five failures | CLP-01 … CLP-08 |
| ADR-7G-07 | **One authoritative PostgreSQL recovery ledger in the `audit` context** (OD-7G-02) | A Redis DLQ stream; per-domain parking tables; a universal inbox | LDG-01 … LDG-07 |
| ADR-7G-08 | **Canonical case identity `(logical_group, event_id, event_type)`**; Redis entries are observations | Keying by entry ID; one case per entry | PID-01 … PID-08 |
| ADR-7G-09 | **Park before `XACK`, with replay-complete material in the same commit** | `XACK` then record; metadata-only parking; `XDEL` as parking; relying on outbox retention | RPM-01 … RPM-11, PAT-01 … PAT-11 |
| ADR-7G-10 | **90-day retention counted from resolution** (OD-7G-03); **unresolved cases never expire** | Age-based deletion of parked cases; one global replay window | PRT-01 … PRT-06, PCL-01 … PCL-06 |
| ADR-7G-11 | **Publisher `FAILED` is repaired only explicitly** (OD-7G-04), through a separate repair publisher | Automatic redrive; an operator `UPDATE` back to `PENDING` | PFD-01 … PFD-07, PRD-01 … PRD-10 |
| ADR-7G-12 | **`FAILED` outbox history is never mutated or reset**; the 30-second relay delay is kept | Resetting `attempt_count`; inserting a new outbox row; a new backoff schedule | PUB-01 … PUB-06, CIA-01 … CIA-05 |
| ADR-7G-13 | **Targeted consumer replay through an internal path**, never by republishing to the shared stream | Republish-and-let-everyone-dedupe; a per-consumer replay stream | TGT-01 … TGT-12 |
| ADR-7G-14 | **Seven explicit replay modes and a fixed source hierarchy**; nothing is fabricated | A single generic replay; reconstruction from audit or state | RMD-01 … RMD-05, DSR-01 … DSR-10 |
| ADR-7G-15 | **Evidence horizon enforced per target by the owner's own gate**; beyond it only owner reconciliation; Billing's entry is released only after Billing's decision | A global window; override by approval; 7G computing usage | HZN-01 … HZN-07, BIL-01 … BIL-07 |
| ADR-7G-16 | **Canonical origin provenance stored in the ledger, insert-if-absent, also assigned when an event leaves the stream under 7G; retired only by proof** | Classifying a replay by its new position; latest-cutover-wins; time-based deletion | PRV-01 … PRV-09, PRR-01 … PRR-06 |
| ADR-7G-17 | **Backfill is an explicit plan with a backfill grant**; `XGROUP SETID` is not a backfill mechanism | Creating a new group at `0`; rewinding a group; implicit backfill on deploy | BKL-01 … BKL-11 |
| ADR-7G-18 | **Group retirement requires a recorded terminal disposition for every pending entry and every open case before `XGROUP DESTROY`** | Destroying a group with pending entries; "the obligation is gone" as a silent default | GR-1 … GR-9, GRT-01 … GRT-03, DPE-01 … DPE-03 |
| ADR-7G-19 | **SIGNAL is excluded from durable recovery** | A SIGNAL DLQ; outboxing signals | SIG-7G-01 … SIG-7G-04 |
| ADR-7G-20 | **Replay is capability-authorized, planned, dry-run, throttled, cancellable and audited** | Ad-hoc SQL or Redis commands; unbounded selection | AUT-01 … AUT-07, PLN, THR, CAN, RSL |
| ADR-7G-21 | **No generic tenant-facing or organization-admin replay API**; internal operations tooling only; the 6J webhook replay stays separate | A Phase-6 replay route; reusing the webhook replay route | AUT-01, WHB-01 … WHB-04 |
| ADR-7G-22 | **A captured R4 source carries its own canonical provenance; shared-stream replay from it fails closed if any receiving group lacks an origin record; position fallback only while the outbox row exists** | Classifying captured material by its new Redis position; reconstructing provenance from timestamps; lengthening `PUBLISHED` retention | DSR-11 … DSR-14, PRV-06, PRV-10 |
| ADR-7G-23 | **R3 has its own durable item state machine: preparation commit, one execution, and an outcome commit that creates the recovery case in the same transaction; the backfill grant outlives its operation** | Reusing the R2 `PARKED → REPLAYING` sequence for a candidate with no case; a result without a case; a grant owned by the operation | BF-1 … BF-8, BKL-12 … BKL-22, T-17, T-18 |
| ADR-7G-24 | **Terminal dispositions are class- and authority-constrained: event operations cannot end a valid owed obligation** | A generic "resolve any parked case" capability; a ticket as authority for supersession; governed-away as a free-form disposition; resolving a case in order to erase material | DAU-01 … DAU-09, RPM-12, PRT-06 |

ADR count: **24**.

---

## 54. Owner Decision Register

| ID | Question | Status |
|---|---|---|
| OD-7G-01 | Consumer poison policy | **DECIDED = A** — classification-aware bounded consumer retry, five durably recorded genuine handler failures |
| OD-7G-02 | Authoritative parking store | **DECIDED = A** — one PostgreSQL parking / recovery ledger in the existing `audit` bounded context |
| OD-7G-03 | Parked / replay metadata retention | **DECIDED = A** — 90 days; no consumer gains a 90-day replay window; unresolved obligations are not silently deleted |
| OD-7G-04 | Publisher `FAILED` handling | **DECIDED = A** — explicit privileged repair only; never automatic; history never reset |
| OD-7B-01, OD-7B-02; OD-7C-01 … OD-7C-07; OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B; OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B | Upstream decisions | Preserved; not reopened |

Open owner decisions raised by 7G: **0**.

The following were evaluated and are technical choices, not owner decisions (AUTH-7G-02): the crash-loop threshold and isolation limit (§17); the idle threshold, cadence and batch (§13); the constant retry delay (§15); the compatibility-hold bound (§22); the replay startup ceilings (§42.2); the deferred acknowledgement of Billing beyond-horizon entries (§35), which changes no financial outcome; the choice of an internal path for targeted replay (§31), which frozen 7F horizons and provenance rules make the only path that cannot disturb other groups. Each is configurable or is justified by a frozen constraint where it is set. The controlled reconciliations of §58 belong to the governed-change process of the document that owns the concern.

---

## 55. Implementation Obligations

Design only; 7G implements none. "Blocks" names the step that may not go live without the obligation.

| IO | Obligation | Owner | Dependency | Blocks |
|---|---|---|---|---|
| IO-7G-01 | **Governed Phase-5 migration: the audit-owned recovery ledger** with the constraint semantics MR-01 … MR-18. DDL, names and the migration number are chosen by that migration, not by 7G | Audit / Event Operations; Phase-5 governed amendment | 7I classification input (HE-7I-7G-02) | Every durable consumer's production operation; all parking, failure recording and replay |
| IO-7G-02 | Recovery-case repository: point read by canonical identity, the atomic failure record, compare-and-swap transitions, append-only history | Platform event infrastructure | IO-7G-01 | Every durable consumer's production operation |
| IO-7G-03 | Replay-material durable storage: raw capture, digest, immutability, variants, bound check (§20) | Platform event infrastructure | IO-7G-01; 7I | Parking; every replay from material |
| IO-7G-04 | Consumer failure recorder and failure classifier (§10.2), at most one record per attempt | Platform event infrastructure | IO-7G-02; 7F IO-7F-04 | Consumer retry go-live |
| IO-7G-05 | PEL reclaim worker: `XAUTOCLAIM` sweep, option conformance, dangling pre-check, delivery-count read, CI check that no prohibited option or post-7.2 command is used. Verifies on the deployed Redis version how claim commands treat a pending ID whose entry is missing | Platform event infrastructure | 7F IO-7F-02, IO-7F-27, IO-7F-30 | Production operation of durable consumers |
| IO-7G-06 | Timing configuration with the startup check of IDL-04 and the local start and attempt deadlines | Platform event infrastructure | IO-7G-05 | Production operation |
| IO-7G-07 | Dependency-wide read gate and dependency probe per group (§16) | Platform event infrastructure; each consuming context for its probe | IO-7G-04 | Consumer retry go-live |
| IO-7G-08 | Poison-budget evaluator: the recovery-case gate before D-09 and the fifth-failure transition (RTY-01 … RTY-09) | Platform event infrastructure | IO-7G-02 | Consumer retry go-live |
| IO-7G-09 | Parking transaction (case, material, provenance, observation in one commit) | Platform event infrastructure | IO-7G-02, IO-7G-03, IO-7G-20 | Parking go-live |
| IO-7G-10 | Park-before-`XACK` adapter, including the zero result, the lost reply and `ACK_UNCONFIRMED`; and the resolve-before-`XACK` rule of RTY-10 in the 7F `XACK` adapter | Platform event infrastructure | IO-7G-09; 7F IO-7F-06 | Parking go-live |
| IO-7G-11 | Duplicate parked-entry acknowledgement path (PAT-07) with digest comparison | Platform event infrastructure | IO-7G-09 | Parking go-live |
| IO-7G-12 | Hold handling: compatibility hold, hold expiry, key-not-onboarded key gate (§22) | Platform event infrastructure | IO-7G-02 | Consumer retry go-live |
| IO-7G-13 | Crash-loop detector and isolation activity with pre-recorded attempts (§17) | Platform event infrastructure | IO-7G-05, IO-7G-03 | Production operation |
| IO-7G-14 | Publisher `FAILED` detector and disposition tooling (§27), including the review record | Platform event infrastructure; event operations | IO-7G-01 | Any outbox `FAILED` cleanup; the first 7F handler-obligation cutover that meets a `FAILED` row |
| IO-7G-15 | Publisher `FAILED` repair publisher: read-only on the outbox, 7D materialization, 7E acceptance, publication admission (§28) | Platform event infrastructure | 7E IO-7E adapter; 7F IO-7F-36 for admission | R5 and R4 |
| IO-7G-16 | Replay planner and dry-run with the plan contents of PLN-02 and the bounds of PLN-04 | Platform event infrastructure | IO-7G-01 | Every planned replay |
| IO-7G-17 | Targeted consumer replay executor (R2): recovery delivery into the group dispatcher, the sequence of TGT-07, operation recovery | Platform event infrastructure; each consuming context for conformance tests | IO-7G-16, IO-7G-20; 7F IO-7F-01, IO-7F-31 | R2 |
| IO-7G-18 | Future-consumer backfill executor (R3): the item state machine BF-1 … BF-8, the preparation and outcome commits, create-or-attach of the recovery case in the item's outcome transaction, source readers, trim-pause integration; tests for the four crash windows BKL-17 … BKL-20 | Platform event infrastructure | IO-7G-17, IO-7G-35; 7E trim worker pause; 7F IO-7F-32 | The first backfill |
| IO-7G-19 | Disaster outbox replay executor (R4), publishing only under PRV-06 or DSR-11 | Platform event infrastructure; 7K | IO-7G-15, IO-7G-16, IO-7G-34 | R4 |
| IO-7G-20 | Canonical provenance storage and lookup: insert-if-absent, no update path, park-time assignment (PRV-05), classification precedence | Platform event infrastructure | IO-7G-01; 7F IO-7F-31, IO-7F-36 | Parking go-live; every replay; the first handler-obligation cutover |
| IO-7G-21 | Evidence-horizon adapter use in replay and the planner pre-check (§34) | Platform event infrastructure; CRM, Billing, Analytics, Integrations | 7F IO-7F-33, IO-7F-35 | Replay into CON-04, CON-06, CON-07, CON-10 |
| IO-7G-22 | Provenance-retirement proof P1 … P5 with recorded checkpoints (§36.2) | Platform event infrastructure | IO-7G-20 | Any deletion of an origin record (none is deleted before it) |
| IO-7G-23 | Billing reconciliation hand-off: material access for the Billing reconciliation path, the decision record (T-14), deferred acknowledgement (§35) | Billing; platform event infrastructure | 7F IO-7F-34 | Resolution of any Billing beyond-horizon case |
| IO-7G-24 | Owner reconciliation hand-off for CRM, Analytics and Integrations beyond-horizon and retired-obligation cases | CRM, Analytics, Integrations; platform event infrastructure | 5J §12.3 rebuild; owner designs | Resolution of those cases |
| IO-7G-25 | Group-retirement executor GR-1 … GR-9 and the governed `XGROUP` operations (destroy, delconsumer maintenance, `SETID` repair, integrity release) | Platform event infrastructure; event operations | IO-7G-01; 7E registry tooling | The first group retirement |
| IO-7G-26 | Replay cancellation, stop conditions and resume-as-new-operation (§42.3) | Platform event infrastructure | IO-7G-16 | Every planned replay |
| IO-7G-27 | Replay throttle configuration with the THR-02 ceilings and the pause conditions | Platform event infrastructure | IO-7G-16 | Every planned replay |
| IO-7G-28 | Cleanup: status-aware ledger cleanup and the interlocked outbox `FAILED` cleanup procedure (§25, §48) | Event operations | IO-7G-01, IO-7G-14 | Any ledger cleanup; any outbox `FAILED` cleanup |
| IO-7G-29 | Immutable operator audit through the audit boundary for every action of §40 | Platform; 7I | 7I design | Every operator action |
| IO-7G-30 | 7I authorization integration: capabilities bound to principals, material-view control | Platform; 7I | 7I design | Production operation |
| IO-7G-31 | 7J telemetry integration for the signals of §52.3 | Platform event infrastructure; 7J | 7J design | Production operation |
| IO-7G-32 | 7K benchmark and capacity integration for §52.4, including the idle-threshold benchmark | Platform; 7K | 7K design | Raising any startup ceiling; production tuning |
| IO-7G-33 | Conformance tests: every row of §51; the fifth-failure race on two real connections; park-commit-then-crash; parking failure never acknowledging; a duplicate after `PARKED` never executing the handler; R2 crash after commit; horizon refusal per target; provenance fail-closed; no stream write by R2 / R3 | Platform event infrastructure; each consuming context | IO-7G-02 … IO-7G-17 | The go-live of the function each test covers |
| IO-7G-34 | Governed source capture (DSR-12) with the registry snapshot, capture-time provenance assignment (PRV-10) and `provenance_complete`; the publish-time gate that refuses a captured source whose row is gone unless every receiving group has an origin record (DSR-11); tests for both counterexamples (F7G-57, F7G-58) and for one group lacking provenance (F7G-59) | Platform event infrastructure | IO-7G-03, IO-7G-20; 7F IO-7F-31 | Any capture; any replay from a captured source |
| IO-7G-35 | Backfill grant as an LC-4 record with its own lifetime; grant link on recovery cases; grant-aware R2 (TGT-04); grant retirement under the provenance proof (BKL-21, PRR-07) | Platform event infrastructure | IO-7G-01, IO-7G-20, IO-7G-22 | The first backfill; cleanup of any R3 operation |
| IO-7G-36 | Class-aware disposition enforcement: derived `case_class`, the permitted (class, resolution, reference) combinations enforced in the ledger (MR-18), re-validation before a contract-invalid rejection (DAU-09), audited refusals, the privacy-erasure hand-off of RPM-12 | Platform event infrastructure; 7I | IO-7G-01, IO-7G-29 | Any operator terminal disposition |
| IO-7G-37 | Provenance completion for retained captured sources at every later handler-contract cutover and group creation (DSR-14): the cutover's provenance step enumerates captured sources of the affected types as well as outbox rows | Platform event infrastructure, under the controlled 7F reconciliation CNF-7G-09 | 7F IO-7F-32, IO-7F-36; IO-7G-34 | Replay of a captured source across a cutover or group creation (it stays replay-blocked until then); does not block initial go-live |

IO count: **37**.

---

## 56. Activation Blockers

### 56.1 Recovery function readiness

Classes: **ARCHITECTURE READY** — fully specified here; **IMPLEMENTATION PREREQUISITE** — needs the named obligations and no schema change beyond the ledger; **GOVERNED MIGRATION REQUIRED** — cannot run before a governed Phase-5 migration; **UPSTREAM CONTROLLED RECONCILIATION REQUIRED** — a frozen upstream text or runtime must be reconciled by its owner first.

| Function | 7G architecture | Blocking class | Blocking items |
|---|---|---|---|
| Recovery ledger | READY | **GOVERNED MIGRATION REQUIRED** | IO-7G-01 |
| Stale-entry reclaim (R1) | READY | IMPLEMENTATION PREREQUISITE (and the ledger, for the recovery-case gate) | IO-7G-01, IO-7G-02, IO-7G-05, IO-7G-06 |
| Failure recording, bounded retry, parking | READY | GOVERNED MIGRATION REQUIRED + IMPLEMENTATION PREREQUISITE | IO-7G-01 … IO-7G-04, IO-7G-07 … IO-7G-12, IO-7G-20 |
| Crash-loop isolation | READY | IMPLEMENTATION PREREQUISITE | IO-7G-13 |
| Publisher `FAILED` disposition and cleanup interlock | READY | GOVERNED MIGRATION REQUIRED + IMPLEMENTATION PREREQUISITE | IO-7G-01, IO-7G-14, IO-7G-28 |
| Publisher redrive (R5) and disaster replay (R4) | READY | IMPLEMENTATION PREREQUISITE; UPSTREAM CONTROLLED RECONCILIATION REQUIRED for publication admission once a cutover has occurred, and for replay of a captured source across a later cutover or group creation | IO-7G-15, IO-7G-16, IO-7G-19, IO-7G-34; 7F CNF-7F-13 / IO-7F-36; CNF-7G-09 / IO-7G-37 |
| Targeted consumer replay (R2) | READY | IMPLEMENTATION PREREQUISITE | IO-7G-16, IO-7G-17, IO-7G-20, IO-7G-21 |
| Future-consumer backfill (R3) | READY | IMPLEMENTATION PREREQUISITE; depends on the 7F cutover procedure | IO-7G-18, IO-7G-35; 7F IO-7F-32 |
| Owner reconciliation hand-off (R6) | READY (mechanics) | IMPLEMENTATION PREREQUISITE in each owning domain | IO-7G-23, IO-7G-24; 7F IO-7F-34 |
| Group retirement | READY | IMPLEMENTATION PREREQUISITE | IO-7G-25 |
| Provenance retirement | READY | IMPLEMENTATION PREREQUISITE (no record is deleted before it) | IO-7G-22 |
| Operator authorization and audit | READY (semantics) | Depends on 7I | IO-7G-29, IO-7G-30 |
| Operator terminal disposition (class-aware) | READY | GOVERNED MIGRATION REQUIRED (MR-18) + IMPLEMENTATION PREREQUISITE | IO-7G-01, IO-7G-36 |

No durable consumer runs in production with retry, parking or replay before the ledger physically exists with its constraints (MIG-02). 7G creates no migration.

### 56.2 7F activation blockers carried forward unchanged

7G replay solves none of these. A consumer that is not activatable under 7F §35 is not made activatable, and is not a replay target, because 7G exists.

| Consumer | 7F classification | Blocking items (7F) | Effect in 7G |
|---|---|---|---|
| CON-03 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | IO-7F-13; CNF-7F-02 | Not a replay target before reconciliation |
| CON-05 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | IO-7F-15; CNF-7F-03, CNF-7F-04, CNF-7F-09 | Same |
| CON-08 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | IO-7F-18; CNF-7F-05 | Blocked (§41.1) |
| CON-09 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | IO-7F-19; CNF-7F-06 | Not a replay target before reconciliation |
| CON-10 | GOVERNED MIGRATION REQUIRED | IO-7F-20, IO-7F-21 | Blocked (§41.1); its horizon comes from that migration |
| CON-11 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | IO-7F-22; CNF-7F-07 | Not a replay target before reconciliation |
| CON-06, `conversation.completed` (Billing EV-079) | GOVERNED MIGRATION REQUIRED | IO-7B-02, IO-7B-15, IO-7B-16, IO-7B-17 | EV-079 is not a replay candidate for CON-06 before them |

The 7F common prerequisites (7F §35.1) also stand; 7G supplies the design that IO-7F-27 waits for.

---

## 57. Deferred Items

| ID | Item | Owner | Reason | Activation condition |
|---|---|---|---|---|
| DEF-7G-01 | Physical DDL, names and migration number of the recovery ledger | Governed Phase-5 migration | 7G defines the logical contract only | IO-7G-01 |
| DEF-7G-02 | Final roles, grants, Redis ACL users, hard separation of requester and approver | 7I | 7I scope | 7I design |
| DEF-7G-03 | Classification, encryption, redaction and DSR rules for material | 7I | 7I scope | 7I design |
| DEF-7G-04 | Metric names, labels, thresholds, dashboards | 7J | 7J scope | 7J design |
| DEF-7G-05 | Worker counts, benchmarked timing values, replay rates, storage sizing, schedules | 7K | Numbers only; correctness is independent | 7K design |
| DEF-7G-06 | Regional disaster-recovery sequencing for R4 | 7K | 7K scope | 7K design |
| DEF-7G-07 | Per-entry scheduled or exponential consumer backoff | 7G governed change | Not needed for five attempts; the constant delay is simpler and safer (RTD-02) | Production evidence |
| DEF-7G-08 | A relay retry schedule other than 30 seconds | 7G / 7K governed change | No evidence requires it (PUB-02) | Benchmark or production evidence |
| DEF-7G-09 | A genuine-rejection counter on the outbox | Phase-5 governed amendment | Not needed: disposition never trusts `attempt_count` (CIA-05) | A later governed design |
| DEF-7G-10 | An external object store for replay material | Governed change with 7I and 7K | The V1 form is a PostgreSQL copy (RPM-03) | Storage evidence from 7K |
| DEF-7G-11 | The CRM-owned and Integrations-owned rebuild paths for beyond-horizon cases | CRM; Integrations | Owner-domain design | Owner design; until then such cases stay `RECONCILIATION_PENDING` |
| DEF-7G-12 | Any tenant-visible or organization-admin view of recovery state | Product / governed Phase-6 change | Explicitly out of V1 (AUT-01) | A later owner decision |
| DEF-7G-13 | Adoption of post-7.2 Redis commands for redelivery | 7E / 7F / 7G governed change | V1 minimum is Redis 7.2 | Transport minimum raised |

---

## 58. Conflict Register

None is silently resolved. 7G edits no frozen document.

| CNF | Sources | Tension | 7G position | Status |
|---|---|---|---|---|
| CNF-7G-01 | 7D CLN-02 (cleanup predicate) versus §48 | The frozen predicate would delete an old `FAILED` row regardless of disposition | The interlock narrows the predicate in the operator procedure, as 7D CLN-04 already requires; `077_5J1` is unchanged | Open — documentary 7D reconciliation; non-blocking (7D anticipated it) |
| CNF-7G-02 | 7F XAK-01, §34 pseudocode versus RTY-01, RTY-10 | 7F processes an entry without consulting any recovery state and acknowledges right after the owner commit | 7G adds a recovery-case read before D-09 and requires an open case to be resolved before `XACK`. Both are strictly narrowing; no 7F rule is weakened. 7F is not edited | Open — controlled 7F / dispatcher reconciliation through IO-7G-08, IO-7G-10; blocks consumer retry go-live until implemented |
| CNF-7G-03 | 7E SCY-05 (consumers hold `XAUTOCLAIM`, `XCLAIM`, `XPENDING`, `XINFO`) versus 7F HE-7I-7F-02 (normal path: `XREADGROUP` and `XACK` only) | Which principal holds the reclaim commands | The sweep is run by admitted group members (RCL-04) and needs `XAUTOCLAIM`, `XPENDING`, `XINFO`; `XCLAIM` and the operator-only commands belong to governed operations | Open — handed to 7I (HE-7I-7G-01); non-blocking |
| CNF-7G-04 | 7E RET-03 step 3 ("dropping them is acceptable only because the obligation no longer exists") versus GR-6, GRT-02 | Whether pending entries may be dropped at retirement without a record | An explicit recorded disposition per entry; the stated reason may be recorded but is never an unrecorded default | Open — documentary 7E reconciliation; non-blocking (narrowing) |
| CNF-7G-05 | 7F HCG-28 (origin provenance assigned at CUT-5f for outbox rows) versus PRV-05 | An event parked by 7G leaves the stream and may outlive its outbox row, so a later cutover could not give it a record | 7G writes the record, insert-if-absent, when the event leaves the stream, using the classification 7F HCG-30 prescribes for an entry without a record. No 7F rule changes | Open — controlled 7F reconciliation carried to 7L; blocks the first handler-obligation cutover together with IO-7F-36 / IO-7G-20; non-blocking for initial go-live |
| CNF-7G-06 | 7F HCG-26 (relay publication admission) and CNF-7F-13 versus the repair publisher | The repair publisher is a second transport writer that frozen 7D does not know | It passes the same publication admission and never writes while admission is `CLOSED` (PRD-04, DSR-10) | Open — joined to the controlled 7D reconciliation CNF-7F-13; blocks R4 / R5 across a cutover |
| CNF-7G-07 | 7F CNF-7F-12 / 5J §12.2 ("route to historical rebuild queue") | No physical rebuild queue exists | `RECONCILIATION_PENDING` cases in the recovery ledger are the durable work list handed to the owner's rebuild | Closed for 7G's part; the Analytics rebuild process itself stays 5J's |
| CNF-7G-08 | 7E MF-14 ("`XAUTOCLAIM` also reports pending IDs whose entries no longer exist") versus DGL-01 | The command removes such IDs from the PEL while reporting them, so a crash between the reply and a durable record could lose the evidence | For a trimmed prefix the read-only pre-check of RCL-06 records the anomaly before any claim command runs. For an interior hole — an outside-model fault (7E TF-20) — the reply element is best-effort evidence with a stated residual crash window (RCL-07); governed repairs close it for enumerated IDs (RCL-15). The deployed behaviour is verified under IO-7G-05 | Resolved in this document within the frozen normal model; the residual window is stated, not hidden |
| CNF-7G-09 | 7F HCG-28 / CUT-5f (provenance assigned to outbox rows that exist at a cutover) versus DSR-12 … DSR-14 | A captured R4 source can outlive its outbox row; a later cutover or group creation would then see no row to assign provenance to | 7G gives the captured source complete provenance at capture and refuses to publish it without a record for every receiving group (DSR-11), so the gap can only block a replay, never misclassify one. For such sources to stay replayable, every later cutover and group creation must also enumerate retained captured sources of the affected types (DSR-14). 7F is not edited | Open — controlled 7F reconciliation carried to 7L (IO-7G-37); blocks only replay of a captured source across a later cutover or group creation; non-blocking for initial go-live |

CNF count: **9**. Open: 7. Closed or resolved in this document: 2. Silently resolved: 0.

---

## 59. Findings

### 59.1 Severity

**P0** — a rule that can lose a durable obligation or duplicate a protected business effect. **P1** — a freeze blocker: an ambiguity or gap that makes an implementation non-deterministic or unsafe. **Minor** — does not block the freeze.

### 59.2 P1 findings raised and resolved during authoring

| ID | Finding | Resolution |
|---|---|---|
| P1-7G-01 | A duplicate stream entry arriving after its event was parked would have run the handler again, because 7F consults no recovery state | Recovery-case gate before D-09 (RTY-01, RTY-02) and the parked-duplicate path (PAT-07) |
| P1-7G-02 | Acknowledging right after a successful retry could leave a case `OPEN_RETRY` forever with no pending entry | An open case is resolved before `XACK` (RTY-10) |
| P1-7G-03 | Redis 7.x claim commands clear a pending ID whose entry is missing while reporting it; a crash could lose that evidence | Read-only dangling pre-check before any claim command (RCL-06, DGL-02) |
| P1-7G-04 | A parked event loses its stream position, and its outbox row may be deleted before a later cutover, so no origin record could ever be assigned | Origin provenance written when the event leaves the stream (PRV-05) |
| P1-7G-05 | A per-entry due time discovered by claiming would reset the idle clock and could delay an entry indefinitely | One reclaim-driven clock; no due-time column (RTD-01, RTD-02) |
| P1-7G-06 | A worker that dies before recording any outcome never advances the poison budget | Separate crash-loop bound with pre-recorded isolated attempts (§17) |
| P1-7G-07 | Republishing a parked event to the shared stream would disturb every other group, including groups beyond their horizon | Internal target-specific path for R2 and R3 (§31, §33) |
| P1-7G-08 | A 90-day parked CRM case could be mistaken for a 90-day CRM replay window | HZN-02, PRT-03; the owner's gate is authoritative |
| P1-7G-09 | An unclassified handler error counted during an outage would park many valid events | Dependency probe after an unclassified failure (FC-11) and the dependency gate (§16) |

### 59.3 Minor findings

| ID | Finding | Disposition |
|---|---|---|
| Minor-7G-01 | The recovery-case read adds one point read per non-unsubscribed entry on the normal path | Accepted for correctness; cost handed to 7K (HE-7K-7G-02) |
| Minor-7G-02 | Held entries (compatibility, key not onboarded, Billing beyond horizon) pin the trim watermark | Bounded or governed; sizing handed to 7K (HE-7K-7G-05) |
| Minor-7G-03 | All timing values and replay ceilings are conservative startup values without benchmark evidence | Explicitly configurable; 7K obligation (IO-7G-32) |
| Minor-7G-04 | Requester / approver separation is a SHOULD until 7I decides | HE-7I-7G-01 |
| Minor-7G-05 | No CRM-owned or Integrations-owned rebuild path is designed yet | DEF-7G-11; such cases stay `RECONCILIATION_PENDING` and are never lost |
| Minor-7G-06 | The exact treatment of a missing pending entry by claim commands must be confirmed on the deployed Redis version | IO-7G-05; the pre-check makes the design safe either way |
| Minor-7G-07 | A recorded failure is counted even when two deliveries of one event fail concurrently, so parking can come sooner than five sequential attempts | Stated (CNT-08, RTD-05); safe because parking is lossless |

### 59.4 Independent freeze-gate review findings

Found by the first independent review of the version with LF SHA-256 `264ba723d427489e390f89f2d0362bdea6f4d13d50fff17ba53b5b81e6a3a312` / 1653 lines. P0 = 0.

| ID | Finding | Resolution |
|---|---|---|
| P1-7G-10 | Retained R4 alternative replay material could outlive the original outbox row and later be classified by a new Redis position without canonical historical group provenance | Position fallback is permitted only while the outbox row exists (PRV-06); the capture carries a registry snapshot and complete provenance (DSR-12, PRV-10); a shared-stream replay from a captured source whose row is gone fails closed with `PROVENANCE_MISSING` if any receiving group lacks an origin record (DSR-11); later cutovers and group creations must complete provenance or the source stays replay-blocked (DSR-13, DSR-14, CNF-7G-09); F7G-57 … F7G-60 |
| P1-7G-11 | Future-consumer R3 backfill reused R2 semantics without defining how an event with no existing recovery case is durably parked or recovered after failure | A separate R3 execution contract: item state machine, preparation commit, one execution, and an outcome commit that creates or attaches the recovery case with its material, provenance and grant in the same transaction (§33.1, T-17, T-18); four crash windows proven (BKL-17 … BKL-20); the backfill grant outlives its operation (BKL-21, PCL-03); R2 honours the grant (TGT-04); F7G-61 … F7G-66; §50.6 |
| P1-7G-12 | Generic recovery-case disposition could terminally reject a valid owed parked consumer obligation without an owning-domain reconciliation or governed obligation-removal decision | Class-aware disposition authority (§24.4, DAU-01 … DAU-09): a class `V` case cannot be permanently rejected by anyone and ends only by replay, owner reconciliation, owner-approved supersession or governed retirement; supersession needs an owner reconciliation reference; governed-away only inside a retirement; `recovery.case.disposition` narrowed; privacy erasure never resolves an obligation (RPM-12, PRT-06); MR-18; F7G-67 … F7G-70 |
| Minor-7G-08 | The dangling-PEL prefix pre-check does not cover every arbitrary interior missing-entry hole; the wording claimed more than the check proves | Wording corrected to the frozen normal model (RCL-06, RCL-07, DGL-02, DGL-03, CNF-7G-08): the pre-check covers a trimmed prefix; an interior hole is an outside-model fault whose claim-reply evidence is best-effort with a stated residual crash window; a governed-repair preflight is added (RCL-15); F7G-71 |

### 59.5 Strict self-review after remediation

Each area was attacked again against the repaired document. "Holds" means no P0 or P1 was found.

| Area | Result | Basis |
|---|---|---|
| Park / `XACK` race | Holds | PAT-01 … PAT-08 |
| Replay / handler race | Holds | A stream duplicate of a `REPLAYING` case takes the parked-duplicate path (RTY-02, PAT-07); the owner's guard arbitrates |
| Duplicate replay request | Holds | TGT-10; PLN-06 |
| R3 failure recovery | Fixed (P1-7G-11) | §33.1 |
| R4 source retention / provenance | Fixed (P1-7G-10) | DSR-11 … DSR-14 |
| Handler cutover after outbox cleanup | Holds for parked cases (PRV-05), for pending entries (classified by their own position) and for captured sources (DSR-11) | §36 |
| Operator terminal-disposition authority | Fixed (P1-7G-12) | §24.4 |
| Consumer crash loop | Holds | §17 |
| Redis delivery-count misuse | Holds | CNT-02, CLP-08 |
| Poison counter lost on process crash | Holds; stated | CNT-07 |
| Unresolved parking retention | Holds | PRT-02 |
| Replay-material lifetime | Holds; grant and captured-source lifetimes added | RPM-10, PCL-02, PCL-03 |
| `FAILED` cleanup race | Holds | ILK-01 … ILK-03; capture holds a row lock (DSR-12 a) |
| Claim-inflated publisher attempts | Holds | §29 |
| Cross-group replay fan-out | Holds | TGT-01; R4 / R5 fan-out is by design and provenance-gated |
| Cross-tenant replay | Holds | §46 |
| Evidence-horizon bypass | Holds | HZN-03, HZN-06 |
| Canonical provenance loss | Fixed for captured sources (P1-7G-10); otherwise holds | §36 |
| Handler-cutover replay | Holds | PRV-06, DSR-10 |
| Topology-generation replay | Holds | §37 |
| Group-retirement loss | One Minor found: the state machine had no transition for parking a still-pending `OPEN_RETRY` entry during retirement | Minor-7G-09; T-07 extended |
| Backfill / trim race | Holds | BKL-08 … BKL-10 |
| Public webhook boundary | Holds | §44 |
| Billing duplicate financial effect | Holds | §35; `uq_ue_idempotency` plus the horizon gate |
| Duplicate call-placement risk | Holds | §41.1 (CON-05) |
| Operator replay / disposition abuse | Fixed for disposition (P1-7G-12); replay holds | §40, §24.4 |

| ID | Finding | Disposition |
|---|---|---|
| Minor-7G-09 | GR-6 lets a retirement park a still-pending entry, but T-07 named only `HOLD → PARKED` | T-07 extended to the governed `OPEN_RETRY → PARKED` during retirement |

### 59.6 Totals

P1 findings raised in total: **12** (P1-7G-01 … P1-7G-12). P1 findings resolved: **12**. P1 findings open: **0**. P0 findings: **0**. Minor findings: **9**. Owner decisions open: **0**.

---

## 60. Validation Results

A semantic validator and a mutation harness were built and run outside the repository (scratch directory; nothing added to the repository). The validator reads the repository read-only. After the first independent review it was rebuilt: every safety rule now has its own check keyed by its rule ID, the truncated work-order assertions 35 – 53 were added, and checks for P1-7G-10, P1-7G-11 and P1-7G-12 were added.

| Group | Checks | What is verified | Result |
|---|---:|---|---|
| Repository baseline | 21 | LF-normalized SHA-256 and line count of 7A – 7F; the 20 Phase-6 artifacts (hash and line count) and that the Phase-6 folder holds exactly those 20; 112 SQL migrations; 112 Alembic revisions with names equal to the SQL names; root `001_5B`; sole head `112_5H5`; no duplicate `down_revision`, no orphan; a walk of the chain from the root reaching the head over 112 revisions; no migration 113; no 7H artifact; the Phase-7 folder holds 7A … 7G only; the working tree differs from `HEAD` only by this document; `HEAD` is still `99c787f` (nothing committed); PostgreSQL 18 baseline statement | 21 / 21 PASS |
| Rule checks | 285 | One check per safety rule or register row: the rule must exist and contain every phrase that carries its guarantee. Covers §9 – §49, the three new rule families (DSR-11 … DSR-14 and PRV-10; BF-4, BF-7 and BKL-12 … BKL-22; DAU-01 … DAU-09), the new migration requirements MR-16 … MR-18, the transitions T-15, T-17 and T-18, the new failure-matrix rows and the three finding rows | 285 / 285 PASS |
| Structural and table checks | 61 | Sections 1 … 63 contiguous; no placeholder; rule IDs unique; every table row has its header's column count; every reference to a 7G rule ID resolves; section references in range; stated counts equal the rows present (24 ADRs, 37 obligations, 9 conflicts, 18 migration requirements, 18 transitions, 71 failure-matrix rows); every obligation has a "Blocks" cell; the final line; all 62 gates `PASS`; no self-declared approval or freeze; no exactly-once claim; P0 / P1 totals agree in §1, §59.6, G-52 and §63; the four owner decisions decided = A and none open; the retry table; the class, disposition, horizon, replay-mode, result, admission, capability and resolution tables; the R3 outcome table; the pseudocode order for parking, the recovery-case gate, R3 and R4; the carried 7F blockers; DD-13; every 7A / 7D / 7E / 7F handoff to 7G; the 64 required failure-matrix cases; the 21 required ADR topics; the 32 required obligations | 61 / 61 PASS |
| **Total** | **367** | | **367 / 367 PASS** |

**Work-order assertions.** Each numbered assertion is proven by named checks; all pass.

| # | Assertion | Proving checks |
|---:|---|---|
| 1 – 9 | Frozen 7A – 7F and Phase-6 hashes; 112 migrations and revisions; root; sole head; no migration 113; no 7H artifact; only 7G is new | Repository baseline (21 checks) |
| 10 – 13 | OD-7G-01 … OD-7G-04 = A | Owner-decision checks |
| 14 – 18 | Five durable genuine failures; Redis count not authoritative; infrastructure failures uncounted; permanent input not retried; the fifth failure parks | CNT-01, CNT-02, CNT-04, CNT-06, GTE-05, FC-10, IMP-01, RTY-05, RTY-07 and the retry and class tables |
| 19 – 24 | Park commit before `XACK`; parking failure never acknowledges; Redis-only DLQ prohibited; one audit-owned ledger; identity includes group and event; material before acknowledgement | PAT-01, PAT-03, LDG-03, LDG-01, PID-01, PID-02, RPM-01, RPM-05 |
| 25 – 30 | Unresolved case never ages out; 90 days after resolution; target-specific horizon; CRM not granted 90 days; beyond-horizon never enters the handler; Billing reconciliation | PRT-02, PRT-01, HZN-01, HZN-02, PRT-03, the horizon table, HZN-04, BIL-01, BIL-03, BIL-04 |
| 31 – 34 | Relay never claims `FAILED`; no automatic redrive; no reset to `PENDING`; no `attempt_count` reset | PUB-04, PFD-02, PFD-03, PRD-05 |
| 35 | Publisher redrive preserves canonical provenance | PRD-09 |
| 36 | The original `FAILED` outbox history is not rewritten | PRD-05, PRD-06 |
| 37 | Claim-inflated `attempt_count` is not treated as the true failure count | CIA-02, CIA-03, PUB-03 |
| 38 | Public webhook replay remains separate | WHB-01, WHB-02, WHB-04 |
| 39 | Generic replay is not tenant-facing | AUT-01 |
| 40 | Consumer replay is target-specific | TGT-01, RMD-03 |
| 41 | Disaster `PUBLISHED` replay uses an immutable source | DSR-02, DSR-07 |
| 42 | A missing replay source fails closed | DSR-06, ILK-07, the source-hierarchy check |
| 43 | Future-consumer backfill is explicit | BKL-01, BKL-02 |
| 44 | Trimming is paused where `XGROUP SETID` / future-group operations require it | BKL-08, BKL-09, BKL-10 |
| 45 | Group retirement reviews and dispositions the PEL before destroy | GR-5, GR-6, GR-7, GR-8 |
| 46 | Canonical provenance is immutable | PRV-02, PRV-03 |
| 47 | A topology generation cannot rewrite provenance | TPG-01, TPG-02, PRV-02 |
| 48 | Replay cannot rewrite the event envelope or history | RMD-04, NRH-01, RPM-07 |
| 49 | SIGNAL is not made durable | SIG-7G-01, SIG-7G-02, SIG-7G-03 |
| 50 | No exactly-once claim exists | Exactly-once check |
| 51 | P0 / P1 totals agree everywhere | Totals check |
| 52 | All owner decisions are closed | Owner-decision checks |
| 53 | The final READY line appears only if every gate passes | Final-line check and gate check |
| Finding P1-7G-10 | Captured-source provenance | DSR-11, DSR-12, DSR-13, DSR-14, PRV-06, PRV-10 and the R4 pseudocode check |
| Finding P1-7G-11 | R3 durable state machine | BKL-12, BKL-14, BKL-17 … BKL-21, T-17, the R3 outcome-table and pseudocode checks |
| Finding P1-7G-12 | Class-aware disposition authority | DAU-02 … DAU-06, MR-18, the class `V` row and the capability row |

**The validator fails the previously reviewed version.** Run against the reviewed version (LF SHA-256 `264ba723d427489e390f89f2d0362bdea6f4d13d50fff17ba53b5b81e6a3a312`, kept as a scratch copy), the same validator reports 83 failing document checks: P1-7G-10 is detected by 7 of its 7 checks, P1-7G-11 by 10 of 10 and P1-7G-12 by 8 of 8; assertions 41, 51 and 53 also fail there, as expected for a document without the captured-source contract, the totals and the final line.

**Validator defects found while building it** (none changed a rule of this document): in the first version, an ID pattern that did not recognise handoff identifiers, mutation kills measured against a non-clean baseline, and two checks too weak to detect a reversed rule; in the rebuilt version, one check too weak to detect "parking means business failure", and three mutation anchors that occurred more than once in the document, so that a mutation could land on a rule other than the intended one. The harness now refuses an anchor that is not unique.

Not validated by tooling, and stated as such: the behaviour of Redis claim commands toward a pending ID whose entry is missing on the deployed version (IO-7G-05); every timing value and replay ceiling against real load (IO-7G-32); the physical enforceability of MR-01 … MR-18, which is the future migration's validation.

---

## 61. Mutation Harness

Each mutation reverses or removes one safety property in a scratch copy of this document. A mutation counts as killed only when the **intended** check — the check named for that mutation in the harness — fails on the mutated text and passes on the unmutated text. The harness refuses, as a harness error, an anchor that is missing or occurs more than once, a duplicate mutation name and an unknown intended check; it reports a mutation that changes nothing as a no-op.

| Area | Mutations | Examples |
|---|---:|---|
| Retry and counting | 29 | Budget changed to 3; Redis delivery count as the five-attempt budget; `XAUTOCLAIM` counted as a genuine failure; a database outage classified or counted against the budget; six normal handler executions; five retries required for malformed bytes; uncommitted failure counted; double counting; a duplicate of a parked event re-running the handler; crash-loop threshold equal to the budget |
| Reclaim | 16 | `FORCE`, `LASTID`, `RETRYCOUNT`, `JUSTID`, `IDLE` permitted; idle inequality removed; `NOACK` on durable reads; reclaim bypassing 7F validation; post-7.2 commands; `XDEL` as parking; the interior-hole wording overclaiming |
| Parking and ledger | 34 | `XACK` before the park commit; a parking database failure followed by `XACK`; Redis-only DLQ; universal inbox; ledger authoritative for business completion; 7G deleting owner dedup state; logical group removed from the recovery identity; metadata parked without replay material; an unsupported version silently upcast; missing bytes reconstructed from mutable domain state; a crash after the parking commit causing a duplicate effect |
| Retention and horizon | 17 | An unresolved parked case deleted at day 90; CRM granted a 90-day replay window; raw replay of Billing beyond its horizon; a Billing entry acknowledged before financial reconciliation; an approval overriding the horizon |
| Publisher | 23 | `FAILED` reset to `PENDING`; automatic redrive; a second outbox event or a new `event_id` for a redrive; `attempt_count` treated as the genuine failure count; `FAILED` deleted before its disposition; redrive losing canonical provenance; `FAILED` history rewritten |
| Replay | 57 | A parked consumer replay republished to every group; canonical provenance bypassed; the latest Redis ID used as the obligation; a topology generation rewriting provenance; `occurred_at`, `organization_id` or payload mutated; a future consumer getting history automatically; `XGROUP SETID` without a trim pause; a group destroyed with an unresolved PEL; provenance deleted because a newer handler generation exists; a crash after a replayed owner commit causing a duplicate effect; a missing source not failing closed |
| Boundaries, tenancy, authorization | 17 | Generic replay invoking the public-webhook replay path; SIGNAL made durable; cross-tenant replay; `INDIA_ENTERPRISE` material leaving the region; replay with no actor, reason or audit; generic replay exposed to tenants or administrators |
| Finding P1-7G-10 | 17 | The `PUBLISHED` row deleted while retained R4 material keeps the position fallback; an obligation added afterwards acquiring the old event; material with no provenance classified by its new Redis position; an originally owed event becoming `NOT_OWED` by position after a removal; the PRV-06 fallback with the outbox row gone; R4 publishing while one subscribed group has `PROVENANCE_MISSING`; provenance fabricated from business timestamps |
| Finding P1-7G-11 | 20 | An R3 handler failure with no recovery case; `PARKED_AGAIN` without material; the R3 operation cleaned up while a parked case still needs its grant; a crash after the owner commit repeating the effect; a crash after the failure losing the candidate; the grant disappearing before R2 recovery; R3 reusing the R2 sequence |
| Finding P1-7G-12 | 18 | A generic operator permanently rejecting a `POISON_BUDGET_EXHAUSTED` valid owed event; `SUPERSEDED` without owner reconciliation; `recovery.case.disposition` resolving every parked class; a privacy cleanup rejecting a valid obligation in order to erase material; governed-away used outside a governed retirement; authority enforced by tooling only |
| Governance and structure | 16 | A migration created; an owner decision flipped or reopened; self-declared freeze; text after the final READY line; READY with a failing gate; exactly-once claimed; P0 / P1 totals disagreeing; a carried 7F blocker dropped; DD-13 reopened |
| **Total** | **264** | **264 killed by their intended check; 0 missed; 0 harness errors; 0 no-ops** |

The 60 mutations of the first run are all retained (several were sharpened so that their anchor is unique). Every mutation named in the work order's required minimum list is present.

---

## 62. Freeze Gates

| Gate | Requirement | Result | Evidence |
|---|---|---|---|
| G-01 | Frozen 7A – 7F unchanged (hash and line count) | PASS | §6 |
| G-02 | 20 frozen Phase-6 artifacts unchanged | PASS | §6 |
| G-03 | 112 SQL migrations, 112 Alembic revisions, one linear chain, root `001_5B`, sole head `112_5H5` | PASS | §6 |
| G-04 | No migration 113; no migration, application code or Redis configuration created | PASS | §1, §49 |
| G-05 | No Phase 7H artifact; 7G is the only new artifact | PASS | §1, §6 |
| G-06 | OD-7G-01 … OD-7G-04 recorded as decided = A; open owner decisions = 0 | PASS | §7, §54 |
| G-07 | At-least-once plus idempotent effects preserved; no exactly-once claim | PASS | §2 |
| G-08 | Three retry domains kept separate | PASS | §9 |
| G-09 | Deterministic failure classification covering every 7F non-acknowledged outcome | PASS | §10 |
| G-10 | Poison threshold = five durably recorded genuine handler failures | PASS | §11, §14 |
| G-11 | Redis delivery count is not the authoritative threshold | PASS | CNT-02, CLP-08 |
| G-12 | Infrastructure failures consume no poison budget and park nothing | PASS | FC-10, FC-11, GTE-05 |
| G-13 | Permanent invalid entries do not spend five retries | PASS | IMP-01 |
| G-14 | The fifth qualifying failure parks; no sixth handler execution | PASS | RTY-05, RTY-07 |
| G-15 | Reclaim uses Redis 7.2 primitives; dangerous options dispositioned | PASS | §12 |
| G-16 | Idle threshold and cadence defined with a correctness inequality | PASS | §13 |
| G-17 | Retry delay deterministic, bounded, crash-safe, not disturbing the PEL | PASS | §15 |
| G-18 | Crash-loop policy bounded and separate from OD-7G-01 | PASS | §17 |
| G-19 | One audit-owned PostgreSQL recovery ledger; Redis-only DLQ prohibited; no universal inbox | PASS | §18 |
| G-20 | Recovery identity includes the logical group and the event identity; never the entry ID alone | PASS | §19 |
| G-21 | Replay-complete material exists before any parking acknowledgement | PASS | RPM-01, RPM-05 |
| G-22 | Park commit precedes `XACK`; a parking failure never acknowledges; no `XDEL` | PASS | §21 |
| G-23 | Deterministic state machine; no state loses the obligation | PASS | §24 |
| G-24 | Resolved metadata retained 90 days; an unresolved case never ages out | PASS | §25 |
| G-25 | Publisher 30-second retry kept; `max_attempts` not described as genuine failures | PASS | §26, §29 |
| G-26 | Normal relay never claims `FAILED`; `FAILED` never automatically redriven | PASS | PUB-04, PFD-02 |
| G-27 | Redrive never resets `FAILED` to `PENDING`, never resets `attempt_count`, inserts no new outbox row | PASS | PFD-03, PRD-05, PRD-06 |
| G-28 | Seven replay modes distinguished; source hierarchy fixed; nothing fabricated | PASS | §30 |
| G-29 | Targeted consumer replay does not fan out to other groups | PASS | §31 |
| G-30 | Disaster replay fails closed on a missing source | PASS | DSR-06, ILK-07 |
| G-31 | Backfill explicit only; `XGROUP SETID` governed with trim pause | PASS | §33 |
| G-32 | Per-target evidence horizon preserved; CRM not granted 90 days | PASS | §34 |
| G-33 | Beyond-horizon never enters the normal handler; Billing uses reconciliation | PASS | HZN-04, §35 |
| G-34 | Canonical origin provenance immutable, insert-if-absent, fail-closed, retained until proof | PASS | §36 |
| G-35 | Topology generation is transport metadata only; no replay into a key that is not onboarded | PASS | §37 |
| G-36 | Group retirement dispositions every pending entry and open case before `XGROUP DESTROY` | PASS | §38 |
| G-37 | Missing stream entry never silently forgotten | PASS | §39 |
| G-38 | Internal operations tooling only; no tenant or admin replay API; no Phase-6 route | PASS | AUT-01 |
| G-39 | High-risk targets protected; CON-10 blocked before IO-7F-21 | PASS | §41 |
| G-40 | Plan, dry-run, throttle, cancellation and result model defined | PASS | §42 |
| G-41 | Replay never resets idempotency history | PASS | §43 |
| G-42 | Public webhook replay boundary preserved | PASS | §44 |
| G-43 | SIGNAL excluded from durable recovery | PASS | §45 |
| G-44 | Tenancy and data residency preserved | PASS | §46, §47 |
| G-45 | Cleanup interlocks for `FAILED` and `PUBLISHED` defined | PASS | §48 |
| G-46 | Governed ledger migration requirement recorded with constraint semantics; go-live blocked until it exists | PASS | §49, §56 |
| G-47 | Failure matrix covers every required case | PASS | §51 (71 rows) |
| G-48 | Handoffs to 7H, 7I, 7J, 7K, 7L issued; no downstream scope taken | PASS | §52, §4 |
| G-49 | ADR (24), implementation-obligation (37), activation-blocker, conflict (9) and findings registers complete | PASS | §53, §55, §56, §58, §59 |
| G-50 | 7F activation blockers carried forward unchanged | PASS | §56.2 |
| G-51 | Every upstream handoff addressed to 7G closed or consumed | PASS | §8 |
| G-52 | P0 = 0; 12 P1 findings raised, 12 resolved, 0 open | PASS | §59.6 |
| G-53 | A captured R4 source cannot cross handler-contract evolution without complete canonical provenance | PASS | DSR-12 … DSR-14, PRV-10, CNF-7G-09 |
| G-54 | A shared-stream R4 item fails closed if any receiving group lacks the required provenance; position fallback only while the outbox row exists | PASS | DSR-11, PRV-06, F7G-57 … F7G-60 |
| G-55 | R3 has a complete durable success / failure / crash state machine | PASS | §33.1, T-17, T-18, BKL-17 … BKL-20, §50.6 |
| G-56 | An R3 failure preserves the exact material and its backfill grant; the grant outlives its operation | PASS | BKL-14, BKL-16, BKL-21, PCL-03 |
| G-57 | Generic operators cannot discard a valid owed consumer obligation | PASS | DAU-02, DAU-06, MR-18 |
| G-58 | Terminal dispositions are class- and authority-constrained; privacy erasure never resolves an obligation | PASS | §24.4, RPM-12, PRT-06 |
| G-59 | The dangling-entry wording claims no more than the frozen normal model supports | PASS | RCL-06, RCL-07, RCL-15, DGL-03 |
| G-60 | The full semantic validator passes, including assertions 35 – 53 and the checks for P1-7G-10 … P1-7G-12 | PASS | §60 |
| G-61 | At least 150 semantic mutations, each failing its intended check; 0 missed, 0 harness errors, 0 no-ops | PASS | §61 |
| G-62 | The validator fails the previously reviewed version on P1-7G-10, P1-7G-11 and P1-7G-12 | PASS | §60 |

---

## 63. Freeze-Gate Status

- This document is the only new artifact of Phase 7G. No frozen document, migration, application code or configuration was changed, and nothing was committed.
- Owner decisions OD-7G-01 … OD-7G-04 are applied as decided. Open owner decisions: 0.
- Every freeze gate G-01 … G-62 was recomputed from the repaired document and passes. P0 = 0; open P1 = 0.
- The architecture is complete for review; it is not runnable until the governed recovery-ledger migration (IO-7G-01) and the implementation obligations of §55 are delivered (§56).
- This document does not declare itself approved or frozen. That decision belongs to the independent freeze-gate review.
- Phase 7H has not been started.

**PHASE 7G = READY FOR INDEPENDENT FREEZE-GATE REVIEW**
