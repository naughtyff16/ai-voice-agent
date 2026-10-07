# Phase 7F — Consumer Idempotency & Ordering — AI Voice Agent Platform

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | `docs/phase-07-event-architecture/7F-Consumer-Idempotency-and-Ordering.md` |
| Phase | 7 — Event Architecture |
| Sub-phase | 7F — Consumer Idempotency & Ordering (processing contract between "Redis Stream entry delivered" and "consumer obligation durably completed + `XACK`") |
| Status | **READY FOR INDEPENDENT FREEZE-GATE REVIEW.** This document does not declare itself approved or frozen; freezing is an independent-review act. |
| Date | 2026-10-06 |
| Remediation | The first independent freeze-gate review of the version with LF SHA-256 `e0a29ca1d23112e97b2a27074ae6d09ad4d035c3c2d17aab96c804c71d0d7b5c` / 1680 lines found P0 = 0 and two P1 freeze blockers: P1-7F-11 (a change of a group's handler obligation was not rolling-deployment safe: a stale worker could acknowledge a newly required type as known-unsubscribed) and P1-7F-12 (Billing's idempotency evidence is retention-bounded, yet CON-06 was classed as indefinitely replay-safe). Both are remediated in place (§10.4, §12.2, §23, §31, §42.3). The review accepted, and this remediation does not reopen: the DD-13 closure (Pattern A), the SIGNAL `NOACK` decision, the `XACK` contract, the crash and concurrency model, the ordering contract and every existing activation blocker. A second independent freeze-gate review, of the version with LF SHA-256 `38cefe5c846651b0eabb268256a4f84482145522403e447c0f625c2f832a5bbe` / 1829 lines, confirmed P1-7F-11 and P1-7F-12 resolved and found two further P1 freeze blockers: P1-7F-13 (the handler-contract cutover used the group's delivery position as its boundary, so a removal could discard already-published owed entries and an addition could silently make already-published entries owed) and P1-7F-14 (the evidence-horizon check was not coordinated with concurrent evidence retirement). Both are remediated in place (§10.4, §12.2, §31, §34.9 – §34.11, §42.3). A third independent freeze-gate review, of the version with LF SHA-256 `085296e449e34653f8cb0e5485042571c4e5b1659a936aa9a06e7e1f51aeff84` / 1882 lines, confirmed P1-7F-11 … P1-7F-14 resolved and found P1-7F-15 (the Redis position cutover did not fence events already committed to the transactional outbox, so a delayed pre-cutover event could cross the obligation boundary), P1-7F-16 (the handler-contract record was normative for every read, but its implementation obligation did not block generation-1 go-live) and Minor-7F-17 (the Analytics dedup retention basis was stated as `occurred_at`; the frozen cleanup uses `created_at`). All three are remediated in place (§10.4, §31.1, §32, §34.9, §34.12, §35, §39, §42). A fourth independent freeze-gate review, of the version with LF SHA-256 `b1f3eccfe930ba8d8b92e3f2267b23f82137455bb32d57baebd59f9e7dedf527` / 1959 lines, confirmed P1-7F-11 … P1-7F-16 and Minor-7F-17 resolved and found P1-7F-17 (the outbox `PUBLISHED` state did not prove publication quiescence: a stale or ambiguous pre-cutover relay attempt could append above the Redis boundary and acquire the wrong handler obligation) and P1-7F-18 (a topology-generation key could become readable or writable before its per-key handler-contract intervals were provisioned). Both are remediated in place (§10.4, §10.5, §11, §12.2, §33, §34.9, §34.12, §36, §39, §41, §42). A fifth independent freeze-gate review, of the version with LF SHA-256 `7fbdb158d5c1051e673edf460cae7c02975c1e5c26e181bc1a9ff6d7f33f4912` / 2051 lines, confirmed P1-7F-11 … P1-7F-18 resolved and found P1-7F-19 (pre-cutover provenance was recorded again at every cutover with the meaning of that cutover, so after two cutovers of one type the same historical event could carry contradictory answers to "was it owed?") and Minor-7F-20 (the key-not-onboarded row C-12 was shadowed by C-10). Both are remediated in place (§10.4 terms, HCG-28 … HCG-31, CUT-5f, §12.2, §23, §33, §34.9, §34.12, §36, §42). |
| Owner decisions | None raised by 7F. DD-13 is closed technically (§14): frozen constraints leave one compatible architecture. Open owner decisions: **0** |
| Repository baseline | `main` @ `1cea65e` ("7E Phase Approved"), working tree clean at start |
| Frozen upstream | 7A, 7B, 7C, 7D, 7E (hashes in §6); Phase-6 documents; Phase-5 migrations `001_5B` … `112_5H5` |
| Preserved owner decisions | OD-7B-01, OD-7B-02, OD-7C-01 … OD-7C-07, OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B, OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B (not reopened) |
| Closes on completion | 7A DD-13 (7F part: no shared inbox is needed); 7B IO-7B-09 (7F part); 7C CV-06 and the processing part of CV-07, ID-10; 7D HO-7F-01 … HO-7F-03; 7E HE-7F-01 … HE-7F-07, IO-7E-20 (design) |
| Carries open | 7E CNF-7E-10 / IO-7E-25 (7B ordering wording) — **not** resolved by 7F (§41) |
| Does not begin | 7G, 7H, 7I, 7J, 7K, 7L |
| Artifact rule | This is the only new project artifact for 7F. No migration (no migration 113), no application code, no Redis configuration, no edit to any frozen document. Scratch validators run outside the repository. |
| Normative keywords | **MUST**, **MUST NOT**, **SHOULD**, **MAY** carry RFC 2119 meaning. Every rule has a stable ID. |

---

## 2. Purpose

7A defines 7F as "consumer idempotency and ordering patterns; inbox decision" (7A §35, F-05). 7E froze the transport: one stream key per semantic owner family, one consumer group per 7B consumer obligation, pending-entry lists, and an ordering guarantee limited to append order within one key (ORD-7E-01 … ORD-7E-10). 7E deliberately defined no acknowledgement timing (7E ACK-01).

7F closes the gap between an entry being delivered to a group and that group's obligation being durably complete. It makes consumer processing implementation-deterministic under duplicate publication, duplicate delivery, concurrent delivery attempts, reclaim races, consumer crashes, Redis failover and group-state regression, group recreation, delayed delivery, reordered delivery, topology-generation changes, rolling deployments and schema-version coexistence.

The end-to-end property is **at-least-once delivery plus idempotent consumer effects**. 7F does not claim exactly-once delivery or exactly-once processing, and no rule in this document may be read as such a claim (7A DEL-04, §20.1).

---

## 3. Scope

- The durable consumer processing model, the processing state model and the dispatch sequence that realises 7C CV-01 … CV-07.
- The cluster-safe read loop over the frozen 7E key and group registry.
- The idempotency taxonomy, the inbox / dedup architecture decision (7A DD-13), transaction atomicity rules, event-id dedup and business-key idempotency.
- Handler-contract generations: the active obligation of a group versus the capability of a build, worker admission, and the closed-group cutover for adding, removing or moving an obligation (§10.4).
- The exact `XACK` contract, including duplicates, unsubscribed types, failures and a zero result.
- Concurrent-duplicate analysis and the crash-point matrix.
- The ordering / reordering contract and a per-consumer reorder audit of every current consumer.
- Known-unsubscribed, invalid and unsupported entries; version coexistence and upcasting.
- External side effects, multi-handler obligations, tenant context, the idempotency-evidence horizon of every consumer (including retention-bounded effect rows), graceful shutdown.
- A per-consumer correctness matrix for CON-01 … CON-11 and the SIGNAL part of CON-07, with activation classification.
- Handoffs to 7G, 7H, 7I, 7J, 7K and 7L; ADRs; implementation obligations; conflicts; findings; validation; freeze gates.

---

## 4. Non-Goals

| Not defined by 7F | Owner |
|---|---|
| Minimum PEL idle time, reclaim cadence, delivery-attempt threshold, poison threshold, retry delay or backoff, DLQ storage, parking, replay API, replay rate limits, replay authorization, future-consumer backfill | 7G |
| Public webhook delivery retry and signing, provider-callback processing, plugin delivery | 7H |
| Final Redis ACLs, worker permissions, field classification, payload logging policy | 7I |
| Metric names, labels, cardinality, SLOs, alert thresholds | 7J |
| Worker counts, concurrency, batch size, block duration, backpressure, catch-up sizing | 7K |
| Physical DDL, column names and migration numbers of any new owner-local guard | The governed Phase-5 migration of the owning context |
| Any change to event names, payloads, classes, consumers, stream keys, groups or routes | 7B / 7C / 7E governed changes |

7F creates no consumer, wires no CCPU name, binds no unbound Class-D signal and creates no group for LS-D-AGT or LS-D-INT.

---

## 5. Authority Model

Authority is concern-specific. There is no "latest document wins" ranking.

| Source | Authoritative for (in 7F) | Not authoritative for |
|---|---|---|
| Executed Phase-5 migrations `001_5B` … `112_5H5` | Physical truth of every constraint, function and grant a consumer guard relies on | Processing order, acknowledgement timing |
| 6A – 6M | Domain semantics of each consumer's effect, its state machine and its API-visible behaviour | Transport acknowledgement |
| 7A (frozen) | IDM-01 … IDM-06, ORD-01 … ORD-06, DEL-01 … DEL-05, RPL-01 … RPL-06, PR-06, PR-07, TX-01, TX-02, SOT-01, SOT-02 | Per-consumer mechanisms |
| 7B (frozen) | CON-01 … CON-11, CR-01 … CR-05, IDN-01 … IDN-11, the §9 ownership model, EV-079 contract | Ordering guarantee wording (CNF-7E-10) |
| 7C (frozen) | Envelope profiles, CV-01 … CV-11, UV-01 … UV-09, COX, RD, UPC, RET, ADP, ID-01 … ID-10, TEN-C01 … TEN-C06 | Idempotency mechanism |
| 7D (frozen) | Duplicate sources on the publish side (AMB, CRS), HO-7F-01 … HO-7F-03 | Consumer transactions |
| 7E (frozen) | Keys, groups, entry format, PEL mechanics, ordering guarantee, trimming, GRP-01 … GRP-10, XSL-01 … XSL-04 | When `XACK` is issued |
| Owner decisions | Only their approved scope | Anything outside it |

Rules of application:

1. **AUTH-7F-01.** A question is answered by its concern's owning source. Where a Phase-6 document describes a consumer effect in a form that is not safe under the frozen 7E delivery guarantee, 7F states the safety property the effect must satisfy and the minimum owner-local mechanism that satisfies it, records the conflict (§41) and classifies the consumer's activation (§35). 7F does not edit the Phase-6 document and does not redefine the domain's business meaning.
2. **AUTH-7F-02.** 7F binds only what 7A, 7B, 7C, 7D and 7E delegate to it. It never weakens a frozen rule.
3. **AUTH-7F-03.** Where two materially different viable designs remain for a persistent, monetary, tenancy, external-behaviour or reliability concern, 7F raises an owner decision and stops. §14 and §38 record why no such decision arose.

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
| Phase-6 frozen artifacts (6A – 6M, AAM, AEC, AMI, AVS, FAR, AIR, certificate) | the 20 hashes and line counts registered in 7B §1.1 | all 20 match | PASS |
| `docs/product/PROJECT_ROADMAP.md` | hash and line count registered in 7B §1.1 | match | PASS |
| SQL migrations | 112 files, `001_5B` … `112_5H5` | 112 | PASS |
| Alembic revisions | 112, file names equal to the SQL names | 112, equal | PASS |
| Alembic chain | one linear chain, root `001_5B`, sole head `112_5H5`, no branch | root `001_5B`, head `112_5H5`, 0 duplicate `down_revision` | PASS |
| Migration 113 | absent | absent | PASS |
| Phase 7G artifact | absent | absent | PASS |
| Database engine | PostgreSQL 18 | as frozen | PASS |
| Event-transport Redis | Redis Open Source 7.2+ (7E CAP-01, IO-7E-01) | as frozen | PASS |

Binding 7E decisions used here: OD-7E-01 = A (dedicated per-region event-transport cluster, `noeviction`); OD-7E-02 = A (`XADD` + same-connection `WAITAOF 1 1`); OD-7E-03 = B (fixed partitions per family by `aggregate_id`; `P_f = 1` in V1).

---

## 7. Upstream Handoffs Closed by 7F

| Handoff | Content | Closed in | Result |
|---|---|---|---|
| 7A IDM-01 | Stable `event_id` across redelivery and replay | §16 (EID-01) | CLOSED |
| 7A IDM-02 | Same-`event_id` redelivery harmless: same-transaction dedup record or naturally idempotent effect | §13, §15, §28 | CLOSED per consumer |
| 7A IDM-03 | Mandatory domain protection for Billing, CRM, webhook delivery, call placement, workflow | §17, §28 (CON-04, CON-05, CON-06, CON-10) | CLOSED; CON-10 needs an owner-local guard (§35) |
| 7A IDM-04 | Tenant scope in dedup identity where the ledger requires it | §16 (EID-05, EID-06), §30 | CLOSED |
| 7A IDM-05 | Ledger retention ≥ protected replay horizon | §31 | CLOSED (semantic invariant; values 7G / 7I) |
| 7A IDM-06 / DD-13 / F-05 | Shared inbox decision | §14 | CLOSED: no shared inbox |
| 7A ORD-01 … ORD-06 | No global order; no implicit dependency; tolerate reordering | §21, §22 | CLOSED per consumer |
| 7A RPL-02 | Handlers replay-safe | §21, §28 (replay-safety row) | CLOSED; replay mechanics are 7G's |
| 7B §22, CR-01 … CR-05 | Consumer registry and consumer rules | §10, §28 | CLOSED |
| 7B IDN-01 … IDN-11, IO-7B-09 | Event-id dedup plus business-key guards; EV-079 Billing identity | §16, §17, §28 (CON-06) | CLOSED (7F part) |
| 7B §31 | `conversation.completed` contract | §28 (CON-06) | PRESERVED unchanged |
| 7C §32 CV-06, CV-07 | Idempotency guard, handler side effects, acknowledgement | §12, §15, §18 | CLOSED |
| 7C UV-01 … UV-09 | Unknown-version handling | §24 | PRESERVED; disposition handed to 7G |
| 7C ID-10 | Analytics `dedup_key` derivation for a SIGNAL `event_id` | §29 (SIG-7F-05) | CLOSED |
| 7C RD-01 … RD-R07 | Mixed-build rollout | §25 | CLOSED (consumer-side gate) |
| 7D HO-7F-01 … HO-7F-03 | Duplicates of the same `event_id`; no ordering; consumer transaction and inbox decision are 7F's | §14, §15, §19, §21 | CLOSED |
| 7E HE-7F-01 | Read loop under the cross-slot rule | §11 | CLOSED |
| 7E HE-7F-02 | Processing transaction, dedup / inbox, business-key idempotency, `XACK` timing | §14 – §18 | CLOSED |
| 7E HE-7F-03 | Acknowledgement of unsubscribed types | §23 | CLOSED |
| 7E HE-7F-04 | Design to the actual ordering guarantee | §21, §22 | CLOSED; CNF-7E-10 stays open (§41) |
| 7E HE-7F-05 | Duplicates from republication, reclaim, group-state regression, group recreation | §19, §20 | CLOSED |
| 7E HE-7F-06 | Multi-handler rule under one group | §27 | CLOSED |
| 7E HE-7F-07 | Safe decoding of the entry representation | §12 | CLOSED |
| 7E IO-7E-20 | Consumer integration: per-key read loop, `NOACK` prohibition, `DELCONSUMER` rule, unsubscribed acknowledgement | §11, §23, §32 | CLOSED (design); implementation is IO-7F-01 … IO-7F-06 |
| 7E IO-7E-25 | Controlled 7B ordering-wording reconciliation | §41 (CNF-7F-01) | **OPEN — carried to 7L; not resolved by 7F** |

---

## 8. Consumer Processing Model

| ID | Rule |
|---|---|
| CPM-01 | **Guarantee.** The durable consumer path provides at-least-once delivery plus idempotent consumer effects. It never provides, and never claims, exactly-once delivery or exactly-once processing. A consumer MAY achieve a local once-only effect inside one PostgreSQL transaction; that is a local property and MUST NOT be described as distributed exactly-once (7A §20.1). |
| CPM-02 | **Authority.** The owning domain's durable state (PostgreSQL constraint, ledger, state machine, or the frozen external store named in §26) is authoritative for whether a business effect happened. The Redis pending-entry list is transport state only (7E PEL-06). |
| CPM-03 | **One dispatcher per logical group.** Each of the 11 durable groups and the SIGNAL group is served by one dispatcher implementation. For one delivered entry the dispatcher makes exactly one classification (§12), runs at most one owner processing attempt and issues at most one acknowledgement decision per delivery. |
| CPM-04 | **One owner transaction per entry.** The local effects of one entry are applied in one owner PostgreSQL transaction. A transaction never contains effects of two entries: entries of different organizations need different tenant contexts (§30), and one failing entry must not roll back another. Entries may be *read* in batches. |
| CPM-05 | **No transaction across the read.** No PostgreSQL transaction is open while a worker is blocked in, or waiting for, `XREADGROUP`. |
| CPM-06 | **No transaction across external I/O.** No PostgreSQL transaction is held open across an external network call in order to make Redis, PostgreSQL or a provider appear atomic (7A PR-06). No XA, no two-phase commit, no Redis `MULTI` coupled to a PostgreSQL transaction (7A TX-02). |
| CPM-07 | **Acknowledge last.** `XACK` is the last step and is issued only after the durable success boundary of §18. A crash between commit and `XACK` produces redelivery, which the idempotency guard absorbs. |
| CPM-08 | **Concurrency is expected.** Members of one group process concurrently, and one entry can be processed by two members at once after a reclaim. Correctness never depends on single-threaded processing, on a worker count or on a batch size (7K sets numbers). |
| CPM-09 | **The dispatcher never repairs.** It never rewrites, re-publishes, defaults, coerces or deletes an entry (7C CV-09, CV-11). It never issues `XADD`, `XDEL`, `XTRIM` or any `XGROUP` subcommand. |
| CPM-10 | **Redelivery safety contract.** Any legitimate redelivery of a valid event may be attempted again, at any time and by any member of the group, without duplicating the protected business effect. This is the contract 7G relies on (§36). |

---

## 9. Delivery / Processing State Model

States describe one delivery of one entry to one group. They are conceptual; they are not a table.

| State | Meaning | Redis PEL | Owner database |
|---|---|---|---|
| `DELIVERED` | `XREADGROUP` returned the entry to a member | Pending for that member | Unchanged |
| `CLASSIFIED` | Entry shape, `fmt`, envelope and pair classified (§12) | Pending | Unchanged |
| `VALIDATED` | Subscribed and supported; payload valid against the original version; tenant gate passed | Pending | Unchanged |
| `PROCESSING` | Owner transaction open (or naturally idempotent external effect in progress, §26) | Pending | Uncommitted |
| `DURABLY_COMMITTED` | Durable success boundary reached (§18, XAK-01) | Pending | Committed |
| `ACK_PENDING` | `XACK` issued or about to be issued; result not yet known | Pending or removed | Committed |
| `ACKED` | `XACK` returned ≥ 1 for the entry | Removed | Committed |

Alternate branches:

| Branch | Entered from | Meaning | Business effect | `XACK` |
|---|---|---|---|---|
| `ALREADY_COMMITTED` | `PROCESSING` | The authoritative guard proves this event's obligation was completed earlier | None now | Yes (XAK-02) |
| `NOT_APPLICABLE` | `PROCESSING` | Subscribed, valid, but the owner's authoritative state shows the event has no target in this domain (for example a non-campaign call for CON-05) | None, by domain rule | Yes (XAK-04) |
| `KNOWN_UNSUBSCRIBED` | `CLASSIFIED` | A legitimate platform event of this stream family that this group has no handler for (§23) | None | Yes (XAK-03) |
| `INVALID_CONTRACT` | `CLASSIFIED` | Malformed envelope, duplicate keys, invalid field, invalid payload | None | **No** |
| `UNSUPPORTED_VERSION` | `CLASSIFIED` | Unknown or RETIRED version, or an unknown type | None | **No** |
| `TRANSPORT_ANOMALY` | `DELIVERED` | Wrong entry shape, wrong or unknown `fmt`, a pair that cannot belong to this stream family | None | **No** |
| `HANDLER_FAILED` | `PROCESSING` | Transaction failed, guard state ambiguous, tenant or domain check failed, or an external effect did not reach durable acceptance | None committed (rolled back), or partial idempotent external writes that will be repeated | **No** |
| `BEYOND_HORIZON` | `PROCESSING` | The event is older than the consumer's guaranteed idempotency-evidence horizon (§31, RET-7F-08) | None: no guard statement and no insert is issued | **No** |
| `OBLIGATION_RETIRED` | `CLASSIFIED` | The entry lies inside a retired obligation interval of its type (HCG-19) | None | **No** |
| `HELD` | Any non-acknowledged branch | The entry stays pending for 7G's disposition | None | **No** (7F never success-acknowledges it) |

| ID | Rule |
|---|---|
| STM-01 | A PEL entry existing does not mean the side effect is incomplete: the effect may be committed and only the acknowledgement lost. |
| STM-02 | A PEL entry disappearing does not prove the side effect occurred. Only the owner's durable guard state proves it. |
| STM-03 | No consumer reads the PEL, the delivery counter or the entry ID to decide a business outcome. |
| STM-04 | `ACKED` is reachable only through `DURABLY_COMMITTED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE` or `KNOWN_UNSUBSCRIBED`. |
| STM-05 | `INVALID_CONTRACT`, `UNSUPPORTED_VERSION`, `TRANSPORT_ANOMALY`, `HANDLER_FAILED`, `BEYOND_HORIZON` and `OBLIGATION_RETIRED` always lead to `HELD`. 7G alone decides what later happens to a `HELD` entry. |

---

## 10. Current Consumer Registry

Reproduced from 7E §29 and 7B §22. 7F adds no group, no consumer and no event type. CCPU names (`call.started`, `usage.event_recorded`) are not in the manifest and have no handler. DS-01 … DS-16 and DS-18 have no binding and no consumer.

### 10.1 Durable groups

| # | Group | CON | Owner | Exact event types | Subscribed logical streams |
|---:|---|---|---|---|---|
| 1 | `cg.identity.session-denylist` | CON-01 | Identity (6B) | `identity.forced_revocation_required` | LS-D-IDN |
| 2 | `cg.compliance.default-policy-seeding` | CON-02 | Compliance (6C) | `organization.created` | LS-D-ORG |
| 3 | `cg.compliance.active-policy-pointer` | CON-03 | Compliance (6C) | `compliance.policy_activated` | LS-D-CMP |
| 4 | `cg.crm.call-history` | CON-04 | CRM (6G) | `call.ended`, `conversation.qualification_set`, `conversation.summarization_completed` | LS-D-VOX |
| 5 | `cg.campaign.record-call-outcome` | CON-05 | Campaign (6H) | `call.ended`, `call.failed`, `conversation.qualification_set` | LS-D-VOX |
| 6 | `cg.billing.usage-ingestion` | CON-06 | Billing (6K) | `call.ended`, `conversation.completed`, `document.indexed`, `campaign.contact.call_attempted`, `workflow.execution.completed` | LS-D-VOX, LS-D-KNW, LS-D-CPN, LS-D-WFL |
| 7 | `cg.analytics.projections` | CON-07 (durable part) | Analytics (6L) | `call.ended`, `call.failed`, `contact.converted` | LS-D-VOX, LS-D-CRM |
| 8 | `cg.voice.recording-object-cleanup` | CON-08 | Voice (6D) | `recording.deleted` | LS-D-VOX |
| 9 | `cg.knowledge.document-count` | CON-09 | Knowledge (6F) | `document.deleted`, `document.indexed` | LS-D-KNW |
| 10 | `cg.integrations.webhook-engine` | CON-10 | Integrations (6J) | `call.failed`, `call.transferred`, `contact.created`, `contact.qualified`, `contact.disqualified`, `deal.created`, `deal.won`, `deal.lost`, `appointment.booked`, `campaign.started`, `campaign.completed`, `campaign.contact.qualified`, `subscription.changed`, `invoice.generated`, `invoice.paid`, `payment.failed`, `usage.threshold_reached` | LS-D-VOX, LS-D-CRM, LS-D-CPN, LS-D-BIL |
| 11 | `cg.campaign.import-worker` | CON-11 | Campaign (6H) | `import.job_created` | LS-D-CPN |

Totals: **11** durable logical groups; **18** (group, logical stream) subscriptions; consumed durable union = **31** event types, equal to 7B §22.

### 10.2 SIGNAL group

| Group | CON | Owner | Exact event types | Subscribed logical stream |
|---|---|---|---|---|
| `sg.analytics.signal-projections` | CON-07 (SIGNAL part; DS-17, DS-19) | Analytics (6L) | `conversation.turn_completed`, `tool_execution.started`, `tool_execution.succeeded`, `tool_execution.failed` | LS-S-VOX |

Totals: **1** SIGNAL group with 1 subscription. No Billing group exists on LS-S-VOX and none may be created (7E SR-02).

### 10.3 Registry rules

| ID | Rule |
|---|---|
| REG-7F-01 | The **active handler obligation** `H_active(g)` of a group is the event-type set of its governed handler contract (§10.4). In V1 (contract generation 1) it is exactly the event types in the group's row above, active from the beginning of every subscribed key. A group owes nothing for any other type. |
| REG-7F-02 | The subscription registry is a code-owned artifact that reproduces §10.1 and §10.2 exactly and is checked in CI against the 7E route registry and the 7C manifest (IO-7F-03). It has no wildcard, prefix, regex or family entry (7C CSR-09). The registry compiled into a build states what that build is **capable** of (`H_capable`, §10.4); it is never, by itself, the authority for what is **active**. |
| REG-7F-03 | A group reads every physical key of each subscribed logical stream in every live topology generation (7E GRP-05, LCY-07). In V1 that is one key per subscription (`g1`, `p = 0`). A key is read only once it is onboarded in the group's handler-contract record (TKO-02). |
| REG-7F-04 | Adding an event type to a group, removing one, adding a group, splitting a group or moving an obligation is a governed 7B / 7E registry change **and** a handler-contract cutover under §10.4, completed before activation. 7F never does it implicitly, and deploying new code never changes `H_active(g)` by itself. |

### 10.4 Handler-contract generations and cutover

A group's handler obligation can change over the platform's life (a type is added, removed or moved). During a rolling deployment two builds with different compiled handler sets can be members of one group, and Redis gives an entry to either. A worker that decided "known-unsubscribed" from its own compiled handler set would acknowledge an entry the group has just started to owe. Separately, a consumer group's delivery position says nothing about what is already in the stream: a group can have an empty pending list while entries it has never received sit behind it. Finally, the stream is not the whole of what has been produced: under 7D a committed outbox row can stay `PENDING` or `CLAIMED` for an unbounded time before it reaches Redis. The rules below remove all three hazards. Obligations are position intervals; a change first fences production at the outbox and drains it, then takes its boundary from the stream itself; and it is made only through a stop-the-group cutover. Correctness is primary; no zero-downtime change of a handler contract is attempted.

| Term | Meaning |
|---|---|
| Obligation interval | For a group `g`, a type `t` and a physical key `K`: the pair `active_from(g, t, K)` and `inactive_after(g, t, K)`. Both are Redis entry IDs used purely as transport position, never as business time. `active_from` is an exclusive lower bound. `inactive_after` is an inclusive upper bound and is `NULL` while the interval is open. A type can have several intervals over time. Every interval is kept in the handler-contract record with a status: `OPEN`, `DRAINING` or `RETIRED`. For every V1 type, and for a key created after a type's activation, `active_from` is the beginning of the key. |
| `A(g, E)` | The obligation that applies to one entry `E` read from key `K`: every type `t` that has a non-retired interval on `K` with `E.id > active_from(g, t, K)` and (`inactive_after(g, t, K)` is `NULL` or `E.id <= inactive_after(g, t, K)`). It is evaluated per entry from the intervals; it is never derived from `H_active(g)` alone. One rule takes precedence over the position: an entry that has a canonical origin provenance record `O(g, event_id, event_type)` is evaluated from that record's `origin_obligation`, whatever Redis ID it carries, whatever key or topology generation it arrives on, and however many cutovers have happened since (HCG-28 … HCG-31). |
| `H_active(g)` | The types `g` owes for entries published from now on: the types that have an `OPEN` interval. It is authoritative only as recorded in the handler-contract record, with a contract generation number `c(g)`. |
| `H_draining(g)` | The types that have a `DRAINING` interval: `g` no longer owes them for new entries, but still owes them for every entry at or below the removal boundary, whenever that entry is delivered. |
| `H_required(g)` | `H_active(g)` ∪ `H_draining(g)`: every type a worker of `g` can still be required to execute. |
| `B(K)` | The stream cutover boundary of key `K`: the stream's own `last-generated-id` (`XINFO STREAM K`), read from the stream at the cutover. It is never the consumer group's `last-delivered-id`. |
| Publication fence | An owner-boundary state, held under PostgreSQL authority, during which no new `audit.domain_event_outbox` row of an affected event type can commit (HCG-21). |
| Pre-fence set | With the fence established: the rows of `audit.domain_event_outbox` of an affected `event_type` whose status is not `PUBLISHED`. It is finite and cannot grow (HCG-22). |
| Publication admission | Per affected event type, a state (`OPEN` or `CLOSED`) that every relay transport attempt for a row of that type checks, and registers under, immediately before it issues its transport write (HCG-26). |
| Canonical origin provenance `O(g, event_id, event_type)` | One immutable record per logical group, event and type. It holds at least: the logical group `g`; `event_id`; `event_type`; `origin_contract_generation`; and `origin_obligation`, which is `OWED` or `NOT_OWED`. It answers, once and for all, "did group `g` owe this event when it was produced?" (HCG-28). A per-cutover list of the events a cutover touched may exist as an audit or index structure; it carries no correctness meaning. |
| `H_capable(build, g)` | The event types for which a worker build contains a conformant handler and guard for `g` (its compiled registry, REG-7F-02). |
| Handler-contract record | One record per logical group per region: contract generation, state (`OPEN` or `CLOSED`), every obligation interval with its status (current and historical), and the registrations of admitted members. |

| ID | Rule |
|---|---|
| HCG-01 | **Authority.** The obligation intervals, and therefore `H_active(g)`, `H_draining(g)` and `A(g, E)`, are read from the handler-contract record and from nothing else. They are never inferred from the handlers compiled into a build, from a deployment revision or from the mere presence of code. |
| HCG-02 | **Admission.** A worker may enter the durable read loop of `g` only when the record is `OPEN` and `H_required(g)` ⊆ `H_capable(build, g)`. A worker that cannot execute every active obligation and every still-draining historical obligation MUST NOT read from the group. |
| HCG-03 | **Registration.** Admission is: (1) read the record; (2) evaluate HCG-02; (3) register as a member under the record's generation; (4) read the record again; (5) start reading only if it is still `OPEN` at the same generation — otherwise deregister without issuing any read. |
| HCG-04 | **Revalidation.** Before every `XREADGROUP` command a member confirms that the record is still `OPEN` at the generation it was admitted under. If it is not, or the record cannot be read, the member issues no further read, brings its in-flight entries to a safe boundary (SHD-02) and deregisters. It fails closed. |
| HCG-05 | **Classification uses the interval that applies to the entry.** Rows C-7 … C-11 of §12.2 are evaluated against `A(g, E)`, computed from the obligation intervals of the record the member was admitted under and the entry's own position. `KNOWN_UNSUBSCRIBED` is never decided from a worker's local handler set, and never from the current `H_active(g)` alone. |
| HCG-06 | **Capable but not owed.** A handler executes only for a type in `A(g, E)`. A handler that is compiled into a build but whose type is not in `A(g, E)` MUST NOT execute. |
| HCG-07 | **Generation 1 exists before the first read.** There is one processing model from first go-live. Before the first durable `XREADGROUP` of a group, its generation-1 handler-contract record exists and contains: state `OPEN`; contract generation 1; one `OPEN` obligation interval for every §10 type of the group on every subscribed V1 key, with `active_from` at the beginning of the key and `inactive_after = NULL`; an empty `H_draining(g)`; and the registration set of HCG-03 / HCG-16, initially empty. The record is created by provisioning (IO-7F-31), never by a worker. There is no static or bootstrap mode: a worker that finds no record, or cannot read it, is not admitted, and it never falls back to its compiled registry. The compiled registry must still equal §10 (REG-7F-02, SHD-08); that is a build check, not a source of authority. Until IO-7F-32 is delivered the intervals are immutable: no type is added to, removed from or moved between groups. |
| HCG-08 | **Closed-group cutover.** An obligation interval is opened or closed only through the steps CUT-1 … CUT-8a below, in that order: producer / outbox publication fence first, Redis stream-position boundary second. A closed interval is retired only through CUT-9. |
| HCG-09 | **Why no incompatible reader exists.** Between CUT-5 and CUT-8 no member of `g` is registered, so none is reading. Every member admitted afterwards is admitted against the new generation, and a build that is not capable of all of `H_required(g)` fails HCG-02. A member that validated just before CUT-4 and was then delayed is still registered; it blocks CUT-5 until it has stopped. No worker is ever permitted to read under an incompatible active handler contract. |
| HCG-10 | **Addition.** Adding type `D` opens a new interval with `active_from(g, D, K) = B(K)`. Every entry that already exists in the stream at the cutover — acknowledged, pending, or not yet delivered to the group at all — has an ID at or below `B(K)` and is not owed; whenever it is delivered it is `KNOWN_UNSUBSCRIBED`. Entries above `B(K)` are owed. Entries at or below `B(K)` never become owed implicitly; backfilling them is exclusively a governed 7G decision (HE-7G-7F-08; 7E BST-04). `B(K)` is captured only after the publication fence has drained every pre-fence outbox row of `D` (HCG-20 … HCG-23), so no event of `D` that was committed before the cutover can first reach the stream above `B(K)` and become owed without a 7G decision. |
| HCG-11 | **Removal.** Removing type `T` sets `inactive_after(g, T, K) = B(K)` on its open interval; the interval becomes `DRAINING` and `T` moves from `H_active(g)` to `H_draining(g)`. Nothing is deleted from the record. Every entry at or below `B(K)` remains owed and is processed normally whenever it is delivered — including entries the group had not yet received at the cutover, pending entries reclaimed later, and entries delivered again after a regression. Entries above `B(K)` are `KNOWN_UNSUBSCRIBED`. No drain is required before the switch and none is assumed: an empty pending list does not mean the group has received the published backlog. `B(K)` is captured only after the publication fence has drained every pre-fence outbox row of `T` (HCG-20 … HCG-23), so no event of `T` that was committed under the old contract can first reach the stream above `B(K)` and be acknowledged as known-unsubscribed. |
| HCG-12 | **Producer gate.** Where a producer or route change is part of the same feature, the producer is not enabled to emit the type before CUT-8 has completed for every group that gains it. Entries emitted earlier lie at or below the boundary, are acknowledged as known-unsubscribed and would need a 7G backfill. More generally, production of every type whose obligation changes is fenced from CUT-5a until CUT-8a (HCG-21): no producer of such a type commits an outbox row between the fence and the reopening of the group, and emission resumes only under the new obligation contract. |
| HCG-13 | **Other gates do not cover this.** KUN-08 protects against a stale manifest, and VER-7F-05 … VER-7F-07 protect new versions of a type that is already in the active obligation. Neither protects a change of the obligation itself: a type that is already an ACTIVE manifest pair is known to every build. Handler-set evolution is protected only by HCG-02 … HCG-09. |
| HCG-14 | **Group split or obligation move.** A split into independent acknowledgement lifecycles needs a governed 7E group-registry change (MHO-05). The move uses **one** boundary value `B(K)` per key for both groups: (a) old group — its interval for the moved effect is closed with `inactive_after = B(K)`; it owes the effect through `B(K)` and keeps draining it (HCG-11); (b) new group — it is provisioned on `K` at exactly `B(K)` (7E BST-04: explicit start position) and its interval has `active_from = B(K)`, so it starts strictly after `B(K)`. The new group is never started from the old group's `last-delivered-id`, and the two values are never chosen separately; therefore there is neither a gap nor an overlap, and every entry position is owed by exactly one of the two groups; (c) whether entries at or below `B(K)` are also backfilled into the new group is a 7G decision, never implicit; (d) idempotency continuity — the moved effect keeps its owner guard identity (the same ledger key including the same consumer identifier, the same unique key, the same state guard), so that an event already processed under the old group is `ALREADY_COMMITTED` if it reaches the new group; (e) no overlap in time — both groups are `CLOSED` for the cutover, and both intervals are written in the same atomic write; (f) publication fence — the event types of the moved effect are fenced and their pre-fence outbox rows are drained before the single boundary is captured (HCG-20 … HCG-23). Two Redis group names never, by themselves, make two executions of the same side effect safe. |
| HCG-15 | **Ownership of a change.** 7E owns the physical group-registry change. 7G owns backfill execution and the disposition of pending entries. 7F owns the consumer-effect correctness of the transition (this section). |
| HCG-16 | **Record properties.** One authoritative record per group per region; linearizable reads and writes; it preserves every obligation interval, including closed ones, until that interval is retired, and keeps retired intervals as history. Registrations are removed only by the member itself or by a governed operator step after the deployment platform confirms the instance is terminated — never by elapsed time alone and never by reading a Redis consumer list. The record is not stored in the event-transport stream keyspace (7E DEP-02) without a governed 7E change. Its physical form is IO-7F-31; 7F creates no table and no migration. |
| HCG-17 | **Boundary source and stability.** `B(K)` is read from the stream on the primary that owns `K`. It is a transport position, not a time. Before CUT-8 the cutover confirms that the shard's failover replica (7E TOPO-02) reports a `last-generated-id` at or above `B(K)`; otherwise it waits or captures again. Redis gives every new entry an ID greater than the serving node's `last-generated-id`, so a node that has reached `B(K)` can never later assign an ID at or below it. A node clock that moves backwards across a reload is an operational anomaly outside this rule (HE-7K-7F-06). The boundary is captured only after the outbox drain proof of CUT-5c: a Redis position alone is not an end-to-end production boundary (HCG-20). |
| HCG-18 | **Retirement of a historical obligation.** A `DRAINING` interval may be marked `RETIRED` only when, for every affected physical key: (1) the group's `last-delivered-id` has reached or passed `inactive_after`; (2) the group has no pending entry at or below `inactive_after`, or every such pending entry has a recorded 7G terminal disposition; (3) the stream no longer holds any entry at or below `inactive_after`, or a governed 7G contract guarantees that no such entry is delivered to this group again except through the owner's rebuild path — so that no group recreation or replay can reintroduce an owed entry without its handler. The three conditions are proven from Redis state and recorded dispositions, never from elapsed time. Until then the type stays in `H_draining(g)`, no build without its handler is admitted (HCG-02), and its handler code MUST NOT be deleted. |
| HCG-19 | **Retired interval.** A retired interval stays in the record as history. An entry that nevertheless arrives at a position inside a retired interval of its type is neither executed nor treated as known-unsubscribed: it is `OBLIGATION_RETIRED` → `HELD` (row C-11), for 7G and the owner's rebuild path. |
| HCG-20 | **Two boundaries, in this order.** A handler-obligation cutover needs (1) a producer / outbox **publication fence** under PostgreSQL authority and then (2) the Redis **stream-position boundary** `B(K)`. The second alone is not sufficient. Frozen 7D lets a committed outbox row stay `PENDING` or `CLAIMED` while Redis is unavailable, across a relay crash, through lease expiry and reclaim, and through an `UNKNOWN` outcome followed by republication, so PostgreSQL publication can lag Redis arbitrarily and an event committed before the cutover could otherwise reach the stream at any later position. |
| HCG-21 | **Publication fence.** For every affected event type the owning producer context establishes a fence with this property: once it is established, no new outbox row of that type can commit until the fence is released. It is established and checked under PostgreSQL authority: every producing transaction of the type takes the type's fence barrier shared (a transaction-scoped advisory lock) and reads the durable fence state before it inserts its outbox row; the cutover sets the state to `FENCED` under the same barrier taken exclusive, so it waits for every in-flight producing transaction and none can slip past it. A fenced producing transaction never commits its state change without its outbox row (7A PR-02) and never emits around the fence; it waits or fails as the owner's contract defines. The fence is not based on `occurred_at`, on UUID order or on any Redis ID. Its physical form is part of IO-7F-32; 7F adds no envelope key, changes no outbox column and creates no migration. |
| HCG-22 | **Pre-fence set and drain proof.** With the fence established, the pre-fence set of a type is exactly the rows of `audit.domain_event_outbox` with that `event_type` whose status is not `PUBLISHED`; it is finite and cannot grow. The cutover waits while the 7D relay drains it. CUT-6 may run only when, for every affected type: (a) no row is `PENDING`; (b) no row is `CLAIMED`; (c) a row whose last transport outcome was `UNKNOWN` is not treated as settled because Redis may already hold its entry — it is settled only when the relay has marked it `PUBLISHED` under the frozen 7D contract (7D LIF-02, AMB-04); (d) every `FAILED` row has a recorded 7G disposition that either resolves it before the cutover or binds it to the pre-cutover obligation interval for any later replay (HE-7G-7F-10) — otherwise the cutover stays blocked. The proof reads PostgreSQL outbox state only; it never reads Redis to decide whether a row was published. It is never satisfied by elapsed time. |
| HCG-23 | **Why the three layers close the gap.** `PUBLISHED` is a statement about the outbox row, not about every transport attempt. 7D LSE-08 lets a slow or paused relay loop outlive its lease; another loop may then reclaim the row, publish it and mark it `PUBLISHED`, while the first loop's already-started or ambiguous transport attempt can still append a duplicate of the same `event_id`. `status = PUBLISHED` alone therefore does not prove that no late transport write exists, and neither does the producer fence alone. The proof has four parts. (1) The producer fence prevents any new commit on the pre-cutover side (HCG-21). (2) The outbox drain settles the durable publication obligation of every pre-fence row (HCG-22). (3) Relay publication quiescence ensures that no normal relay attempt for an affected type that started before the capture can still issue a Redis write after it (HCG-26, HCG-27). (4) Every governed later replay is classified by its canonical origin provenance, not by the Redis ID it receives (HCG-28 … HCG-31). Therefore `B(K)` safely separates normal post-quiescence transport publication under the old and under the new handler contract, and no event produced on the pre-cutover side can later be interpreted as post-cutover merely because a duplicate or a republication receives a Redis ID greater than `B(K)`. |
| HCG-24 | **Producer coordination; V1 uses the fence.** Stopping the consumers does not stop the producers. V1 has no contract-generation marker that travels producer → outbox → Redis, and 7F adds none. Every producer of an affected type (7B §21) must take part in the fence. If an affected producer cannot be safely fenced — for example because its owner cannot accept the pause — the obligation change cannot proceed under V1 and stays blocked until a governed upstream design exists (DEF-7F-12). |
| HCG-25 | **Abandoning a cutover; later replays.** Until CUT-7 has been written, a cutover may be abandoned (for example when the transport is unavailable and the relay cannot drain): the fence is released and the group is reopened at the unchanged generation; nothing is lost because no interval changed. After CUT-7 the cutover is completed, never rolled back. Between CUT-5a and CUT-8a the fence is released only by such an abandonment. A later 7G replay of a pre-fence row — a `FAILED` row, or a retained `PUBLISHED` row replayed for disaster repair (7D CLN-08) — never crosses the boundary by accident: it carries its recorded pre-cutover disposition (HE-7G-7F-10). An abandonment also reopens relay publication admission (HCG-26). A cutover that cannot prove publication quiescence (HCG-27) is abandoned before CUT-7. |
| HCG-26 | **Relay publication admission.** Every relay transport attempt for a row of an affected type passes publication admission immediately before it issues its transport write: (1) read the admission state of the type; (2) if it is `OPEN`, register the attempt (relay identity, type, and the node-pinned connection of the exchange; 7E AFF-02); (3) read the state again; (4) issue the transport write only if it is still `OPEN` — otherwise deregister without writing and leave the row to the frozen 7D deferral path, which is non-terminal, so nothing is failed or lost. An attempt deregisters only when it has reached a terminal local transport state: every command of the exchange has received its reply, or the adapter has closed the exchange's connection and the owning primary no longer reports that connection, so that no buffered command of the attempt can still execute. A check made at claim time is not sufficient: a loop that was paused after its claim must pass admission when it resumes. Registration and deregistration are short operations of their own; no PostgreSQL transaction is held open across transport I/O (7A PR-06; 7D). This is a requirement on the relay runtime that frozen 7D does not contain. It is recorded as a controlled 7D reconciliation (CNF-7F-13) and blocks the first handler-obligation change (IO-7F-36), not initial go-live. |
| HCG-27 | **Publication quiescence proof.** After the outbox drain proof the cutover closes publication admission for every affected type and continues only when the set of registered attempts for those types is empty. The registration of a dead relay process is removed only by a governed operator step after the deployment platform confirms the process is terminated and the primary no longer reports its connection — never by elapsed time alone. No affected publication attempt may be in flight or ambiguous when `B(K)` is captured. The outbox settlement of HCG-22 is then checked again; if it no longer holds, admission is reopened and the drain is repeated, or the cutover is abandoned (HCG-25). If quiescence cannot be proven, the cutover is abandoned before CUT-7. |
| HCG-28 | **Canonical origin provenance: identity and assignment.** For each logical group there is at most one origin record `O(g, event_id, event_type)` per event and type, holding `origin_contract_generation` and `origin_obligation` (`OWED` or `NOT_OWED`). It is assigned at CUT-5f, with the group closed and before the switch: for every outbox row of an affected type that exists at that moment, whatever its status (retained `PUBLISHED` rows and `FAILED` rows included) — **if an origin record already exists it is left unchanged; otherwise** one is written with `origin_contract_generation` = the generation in force before the switch and `origin_obligation` = `OWED` if that pre-switch contract owes the type for `g`, else `NOT_OWED`. This is the historically correct answer: a row without a record has seen no cutover of its type for `g` since it was produced (every such cutover would have given it a record), so the contract in force before this switch owes it exactly as the contract in force at its production did. A cutover never records "every retained event is on the pre-side of this cutover" as a correctness fact. Without the origin records the cutover stays blocked. |
| HCG-29 | **Immutability; the first assignment wins.** Once `O(g, event_id, event_type)` exists, no later cutover overwrites, reinterprets or supplements it. The write is insert-if-absent; there is no update path. A later cutover may note, for audit, that it saw the event, but it never changes `origin_contract_generation` or `origin_obligation` and never creates a second correctness record. Correctness is never decided by: the latest cutover; the latest membership in a per-cutover list; the Redis ID; the current `H_active(g)`; or the handler code that currently exists. For one `(group, event_id, event_type)` there is therefore exactly one answer, across two, three or any number of handler-contract generations. |
| HCG-30 | **Classification by origin.** For an entry with an origin record: `origin_obligation = NOT_OWED` — the group does not owe it; it is not in `A(g, E)` and not in `X(g, E)`, even when its Redis ID lies inside an open interval of its type. `origin_obligation = OWED` — the group owes it under the obligation interval of its type that was open in `origin_contract_generation`; if that interval is not `RETIRED` the type is in `A(g, E)` and the event is processed normally, even when its Redis ID lies above `inactive_after`; if that interval is `RETIRED` the type is in `X(g, E)`: `OBLIGATION_RETIRED` → `HELD` (HCG-19). It is never executed under a different, newer interval of the same type, and deleted handler code is never resurrected automatically. An entry without an origin record is classified by the physical-key obligation interval. A 7G explicit backfill decision is the only way a `NOT_OWED` event is later processed, and it is a governed 7G act, not a classification result. |
| HCG-31 | **Scope and lifetime.** (a) Origin provenance is per logical group: in a move or split the old and the new group each have their own record for the same `event_id`, and it may correctly be `OWED` for one and `NOT_OWED` for the other; a provenance value without the logical group identity is never used. (b) Transport topology generation does not touch it: an event replayed onto a `g2` or later key keeps the origin record of its logical group, and no key or generation change rewrites it. (c) An origin record is durable until 7G records that no replay source can still deliver that event to the group (HE-7G-7F-10). A later cutover, or the existence of a newer contract generation, never shortens that lifetime or retires an earlier record. (d) An event whose origin cannot be determined is never replayed to the group through the normal handler. |

| Step | Closed-group cutover action |
|---|---|
| CUT-1 | **Prepare.** The governed 7B / 7E registry change is approved. For a type new to the platform, its manifest pair and 7E route row are deployed (7E RR-07). For an addition, the handler and its guard exist, with a §28 card for the new (consumer, type) and passing tests (IO-7F-07 … IO-7F-10). |
| CUT-2 | **Capability rollout.** Deploy to every member a build whose `H_capable` contains the future `H_required(g)`: every type that stays active, every added type, every draining type, and — for a removal — the type being removed, which becomes draining. No interval has changed yet, so a new handler does not execute (HCG-06). |
| CUT-3 | **Capability proof.** A deployment gate proves that every build that is running or can start as a member of `g` is capable of the future `H_required(g)`, and that incapable revisions can no longer start. |
| CUT-4 | **Close.** Set the record to `CLOSED`. New admissions are refused (HCG-03); admitted members stop at their next revalidation (HCG-04). |
| CUT-5 | **Quiesce proof.** Continue only when the group's registration set is empty (HCG-16). |
| CUT-5a | **Publication fence.** For every affected event type, establish the publication fence at the owning producer boundary (HCG-21, HCG-24). For a type that is not yet produced, its producer simply stays disabled. |
| CUT-5b | **Pre-fence set.** Identify the pre-fence set of every affected type from PostgreSQL outbox state (HCG-22). |
| CUT-5c | **Outbox drain proof.** Let the 7D relay drain. Continue only when HCG-22 (a) – (d) hold for every affected type: no `PENDING` row, no `CLAIMED` row, no `UNKNOWN` outcome treated as settled, every `FAILED` row under a recorded 7G disposition. |
| CUT-5d | **Close relay publication admission.** Set publication admission to `CLOSED` for every affected type (HCG-26). New transport attempts for those types are refused; their rows stay deferred under 7D. |
| CUT-5e | **Publication quiescence proof.** Continue only when no registered publication attempt for an affected type remains (HCG-27). If that cannot be proven, abandon before CUT-7. |
| CUT-5f | **Re-check and provenance.** Check HCG-22 (a) – (d) again on the affected outbox rows, and assign canonical origin provenance to every affected outbox row that has none, leaving every existing origin record unchanged (HCG-28, HCG-29). |
| CUT-6 | **Boundary capture.** Only after CUT-5f. For each affected key read the stream cutover boundary `B(K)` from the stream itself (`XINFO STREAM K`, `last-generated-id`). The group's `last-delivered-id` and the state of its pending list are not used: they describe what the group has received, not what has been published. |
| CUT-7 | **Switch.** Write the next generation in one atomic write. Addition: a new `OPEN` interval with `active_from = B(K)` and `inactive_after = NULL`. Removal: the type's open interval gets `inactive_after = B(K)` and status `DRAINING`; no interval and no type is deleted. |
| CUT-8 | **Open.** After the boundary-stability check (HCG-17), set the record to `OPEN` at the new generation. Members start and are admitted under HCG-02 and HCG-03. The publication fence is still held. |
| CUT-8a | **Release.** Only after CUT-8 is complete: release the publication fence and reopen relay publication admission. Producers resume under the new obligation contract, and only now may a producer or route that is part of the same feature be enabled (HCG-12). |
| CUT-9 | **Historical-obligation retirement (removal and move only; later, separate step).** When HCG-18 holds for every affected key, mark the `DRAINING` interval `RETIRED` in a new generation, through CUT-3 … CUT-5 and CUT-8. Only after that may a later release delete the handler code. |

### 10.5 Topology-generation key onboarding

Obligation intervals are per (group, type, physical key). 7E LCY-07 step 1 provisions the keys and Redis groups of a new topology generation, but it knows nothing of the handler-contract record. If a new key were written and read before its intervals exist, no interval would apply to its entries and they could be classified as known-unsubscribed. The rules below close that gap. 7F does not edit 7E.

| ID | Rule |
|---|---|
| TKO-01 | **Rule.** A new-generation durable key MUST NOT carry consumer-visible production traffic, and MUST NOT be read by any consumer, before its obligation intervals exist in the handler-contract record of every logical group subscribed to its family. The statement that a later key "starts at the beginning of the key" is realised only by this provisioning; it is never assumed. |
| TKO-02 | **Key admission.** A worker reads a physical key only if the record it was admitted under lists that key for its group (the key is *onboarded*). RDL-14 and REG-7F-03 apply to onboarded keys only. An entry read from a key that is not onboarded is never `KNOWN_UNSUBSCRIBED`; it is held (row C-12). |
| TKO-03 | **Complete active intervals.** Onboarding a key writes, for every type of `H_active(g)` that is routed to the key's family, exactly one `OPEN` interval on the new key with `active_from` at the beginning of the key and `inactive_after = NULL`. No active type may be omitted: the write is rejected unless the new intervals equal that set. |
| TKO-04 | **No reopening.** A type that is only in `H_draining(g)`, or that has only `RETIRED` intervals, MUST NOT receive an interval on a new key merely because the key was created. On the new key such a type is simply not owed. |
| TKO-05 | **Order.** Onboarding follows TK-1 … TK-8 below, in that order. |
| TKO-06 | **Relay gate.** No relay configured for the new generation is enabled (7E LCY-07 step 2) before TK-6 has proven, for every subscribed group, that the record lists the key with complete intervals and that every running member was admitted under that generation. |
| TKO-07 | **Old generation.** The intervals of old-generation keys stay valid while those keys are live and draining, and consumers keep reading both generations as 7E freezes it. An old-key interval is retired only after 7E has retired that key (LCY-07 steps 4 – 5: lag 0, empty PEL, groups destroyed, keys deleted), through a governed lifecycle generation (TK-9). Interval history is kept where a 7G replay still needs it; canonical origin provenance is not affected by a topology generation at all (HCG-31). |
| TKO-08 | **Serialization.** A handler-obligation cutover (HCG-08) and a topology-key onboarding or old-key retirement are mutually exclusive per affected logical group. The record carries a single change-in-progress marker; a second governed change of the same group does not start until the first has completed or been abandoned. 7F defines no concurrent merge of the two. |
| TKO-09 | **Controlled lifecycle handoff.** 7E LCY-07 step 1 alone is not sufficient once obligations are per key. The combined ordering TK-1 … TK-9 is a controlled 7E / 7K lifecycle reconciliation (CNF-7F-14, HE-7K-7F-08). The first topology-generation change is blocked until IO-7F-37 is delivered. |
| TKO-10 | **V1.** Only `g1` keys exist. Each group's generation-1 record lists exactly its `g1` keys with the intervals of HCG-07. |

| Step | Topology-key onboarding action |
|---|---|
| TK-1 | **Provision (7E).** 7E provisions the new stream key and all registered groups at the required start position (LCY-07 step 1; BST-01). The key is in no consumer's read set and no relay writes to it. |
| TK-2 | **Serialize.** Take the change-in-progress marker of every logical group subscribed to the key's family (TKO-08). If a handler-obligation cutover of such a group is in progress, wait for it to finish. |
| TK-3 | **Close and quiesce.** Close each such group and prove its registration set empty (CUT-4, CUT-5). |
| TK-4 | **Write the intervals.** In one atomic write per group, add the key to the record with one `OPEN` interval per active type (TKO-03) and none for a draining or retired type (TKO-04). |
| TK-5 | **Open.** Open each group at the new record generation (CUT-8). Members are admitted again; their read set now includes the new, still empty key. |
| TK-6 | **Admission proof.** Prove for every subscribed group that the record is complete and readable, lists the key with complete intervals, and that every running member was admitted under it and reads the key. Release the markers. |
| TK-7 | **Enable relays (7E).** Only now may 7E LCY-07 step 2 enable relays that publish to the new generation. |
| TK-8 | **Migration.** Consumers read both generations until 7E drains and retires the old one (LCY-07 steps 3 – 5). |
| TK-9 | **Old-key interval retirement (later, separate governed change).** After 7E has retired the old keys, a lifecycle generation written under the marker (TK-2 … TK-5) retires their intervals (TKO-07). |

---

## 11. Cluster-Safe Read Loop

### 11.1 Rules

| ID | Rule |
|---|---|
| RDL-01 | **Normal durable read.** `XREADGROUP GROUP <group> <consumer> [COUNT <n>] [BLOCK <ms>] STREAMS <one physical key> >`, sent on the connection to the primary that owns that key's hash slot. |
| RDL-02 | **One key per command.** Each read command names exactly one physical stream key. A command MAY name several keys only when all of them carry the same hash tag and that is proven from the 7E key grammar (7E XSL-01, XSL-02). In V1 every key has its own hash tag (`d.g1.<family>.0`), so no two V1 keys share a slot by construction and every V1 read names one key. |
| RDL-03 | **No `NOACK` on durable groups.** A durable read never carries `NOACK` (7E GRP-07). |
| RDL-04 | **`>` only.** Normal reads use the special ID `>`. Reading a member's own pending entries by explicit ID, `XAUTOCLAIM` and `XCLAIM` are redelivery mechanisms whose policy is 7G's (§36). An entry obtained through them enters the same pipeline at §12 step D-01 and is processed under the same rules. |
| RDL-05 | **Consumer name.** Each process instance uses a consumer name of the 7E GRP-06 form `<runtime-role>/<region-tag>/<instance-uuid>`, generated once at process start and never reused by another instance. It contains no tenant data, credential or secret. |
| RDL-06 | **Key set from the registry.** The keys a group reads are computed from the subscription registry (REG-7F-03) and the configured live generations. They are never discovered with `SCAN` or `KEYS` and never derived from an entry. |
| RDL-07 | **Application multiplexing.** The consumer runs an independent read activity per physical key. A slow, blocked, redirected or failing key never stops reads on the group's other keys. Fairness and concurrency numbers are 7K's. |
| RDL-08 | **Bounded block.** `BLOCK` uses a finite duration so that shutdown (§32) and topology refresh are observed. The value is 7K's. Correctness does not depend on it. |
| RDL-09 | **Redirects and failover.** On `MOVED`, `ASK`, a connection loss or a failover the consumer refreshes its slot map and re-issues the read. Re-issuing a `>` read is always safe: entries already delivered are in the PEL and are not returned again by `>`. |
| RDL-10 | **Lost read reply.** If the connection is lost after Redis delivered entries but before the client received them, those entries stay pending for this consumer and are unknown to it. They are recovered only by 7G's redelivery. No entry is lost. |
| RDL-11 | **Missing group.** `NOGROUP` stops reads on that key and raises an anomaly. A consumer never creates a group (7E GRP-09) and never changes a group position. |
| RDL-12 | **Read admission.** A consumer does not read more entries than it is prepared to process before its next read (in-flight bound; the number is 7K's). An entry that was read is always classified; it is never silently dropped by the client. |
| RDL-13 | **`CROSSSLOT`.** A `CROSSSLOT` error is an implementation defect (7E XSL-03). |
| RDL-14 | **Generations.** During a generation migration (7E LCY-07) the consumer reads the keys of both generations until the old generation is retired. An event can therefore be delivered from either generation; the idempotency guard is keyed on `event_id`, never on the key or the generation. RDL-14 alone does not make a new-generation key readable: a worker reads a key only after that key is onboarded in the handler-contract record it was admitted under (TKO-02), and no relay writes to it before that (TKO-06). |

### 11.2 Redis command boundary (V1 = Redis 7.2 semantics)

| Command | Available since | Used by 7F V1 | Note |
|---|---|---|---|
| `XREADGROUP` (`GROUP`, `COUNT`, `BLOCK`, `STREAMS`, `>`; `NOACK` on the SIGNAL group only) | 5.0 | Yes | RDL-01 … RDL-04, SIG-7F-02 |
| `XACK` | 5.0 | Yes | §18 |
| `XAUTOCLAIM`, `XCLAIM`, `XPENDING` | 6.2 / 5.0 / 5.0 | No — capability reserved for 7G | 7E PEL-02, HE-7G-01 |
| `XINFO` | 5.0 | Diagnostics, and the governed cutover's boundary capture (`XINFO STREAM`, CUT-6) and retirement proof (HCG-18) | Never a business input |
| `XREADGROUP … CLAIM`, `XNACK`, `XACKDEL`, `XDELEX` and any other command or option introduced after Redis 7.2 | post-7.2 | **No — FUTURE ONLY** | V1 does not depend on any of them. Adopting one is a governed 7E / 7F change after the transport minimum is raised. |

### 11.3 Read-loop pseudocode

```text
READ-LOOP(group g, consumer c)                          -- one activity per physical key
    admitted := ADMIT(build, g)                         -- §34.9; HCG-02, HCG-03
    if admitted is NOT_ADMITTED: return                 -- an incompatible build never reads
    for each key K in keys_of(g, live_generations):     -- RDL-06, RDL-14
        spawn READ-KEY(g, c, K)

READ-KEY(g, c, K):
    while not shutdown_requested:                       -- §32
        wait until in_flight(K) < admission_bound       -- RDL-12; no DB transaction is open here
        BEFORE-EACH-READ(c, g, admitted)                -- HCG-04; stops this activity if the contract changed
        reply := XREADGROUP GROUP g c COUNT n BLOCK t STREAMS K >     -- RDL-01, RDL-02, RDL-03
        on MOVED / ASK / connection loss: refresh slot map; continue  -- RDL-09
        on NOGROUP: raise anomaly; stop this key                      -- RDL-11
        for each (entry_id, fields) in reply:
            hand (K, entry_id, fields) to PROCESS-ENTRY(g, K, entry_id, fields)   -- §34.1
```

---

## 12. Consumer Validation / Dispatch Sequence

### 12.1 Steps

The dispatcher applies these steps to every delivered entry, in this order. They realise 7C CV-01 … CV-07 and 7E ENT-06, SEP-03.

| Step | 7C | Action | Failure outcome |
|---|---|---|---|
| D-01 | — | Entry shape: exactly two fields, `fmt` then `env` (7E ENT-01). | `TRANSPORT_ANOMALY` |
| D-02 | — | `fmt` equals `durable.v1` on a profile-`d` key (`signal.v1` on a profile-`s` key). Any other value, including the other profile's marker, is never processed as either profile (7E SEP-03). | `TRANSPORT_ANOMALY` |
| D-03 | CV-01 | Parse `env`: strict UTF-8; one JSON object; a duplicate key at any depth is invalid; numbers are decoded without binary floating point for business values (7E ENT-06, 7C §18). | `INVALID_CONTRACT` |
| D-04 | CV-02 | Validate the envelope fields of the profile (7C §10 or §11), including the `event_version` form (VRS-04) and the absence of `durability` on a durable envelope (SIG-R02). | `INVALID_CONTRACT` |
| D-05 | CV-03 | Classify the pair (`event_type`, `event_version`) with the decision table of §12.2. | per §12.2 |
| D-06 | CV-04 | Subscribed and supported only: validate the payload against the schema of the **original** version. Unknown payload keys are ignored (CPT-05, CPT-06). | `INVALID_CONTRACT` |
| D-07 | — | Tenant gate (§30): take `organization_id` from the validated envelope; check the payload organization value, where the schema defines one, equals it. | `INVALID_CONTRACT` |
| D-08 | CV-05 | Optional pure in-memory upcast (§25). | None: the upcast is pure and total for a supported pair. A pair with neither a native handler nor an upcast chain is not in `S(g)` and was already classified `UNSUPPORTED_VERSION` at D-05 |
| D-09 | CV-06 | Owner idempotency adapter: guard, then handler side effects, in the owner transaction (§15). | `HANDLER_FAILED` |
| D-10 | CV-07 | `XACK` under §18. | `ACK_PENDING` (XAK-08, XAK-09) |

### 12.2 Classification decision table (first matching row wins)

`M` is the platform manifest (7C CSR-02) keyed by exact pair, with each pair's route family (7E §18.2) and lifecycle state (7C RET-01). `A(g, E)` is the handler obligation that applies to the entry (§10.4): every type with a non-retired obligation interval on the key that contains the entry's position (`E.id > active_from` and, where the interval is closed, `E.id <= inactive_after`). It therefore includes a draining type for entries at or below its removal boundary, and excludes an added type for entries at or below its activation boundary. It comes from the handler-contract record the worker was admitted under, never from the handlers compiled into the build and never from the current `H_active(g)` alone. `X(g, E)` is the set of types that have a **retired** interval containing the entry's position (HCG-19). An entry that has a canonical origin provenance record for `g` is evaluated from its `origin_obligation` instead of its position (HCG-30): `NOT_OWED` puts its type in neither set; `OWED` puts it in `A(g, E)`, or in `X(g, E)` once its origin interval is retired. A key `K` is *onboarded* for `g` when the admitted record lists it (TKO-02). `S(g)` is the set of exact pairs the running build declares it supports (7C COX-06); admission guarantees that the build has a handler for every type of `H_required(g)` (HCG-02). `F(K)` is the family of the key being read.

| Row | Condition | Class | `XACK` |
|---:|---|---|---|
| C-1 | D-01 fails | `TRANSPORT_ANOMALY` | No |
| C-2 | D-02 fails | `TRANSPORT_ANOMALY` | No |
| C-3 | D-03 fails | `INVALID_CONTRACT` | No |
| C-4 | D-04 fails | `INVALID_CONTRACT` | No |
| C-5 | `event_type` appears in no pair of `M` | `UNSUPPORTED_VERSION` (unknown type, 7C UV-07) | No |
| C-6 | `event_type` is in `M` but its route family ≠ `F(K)` | `TRANSPORT_ANOMALY` (impossible stream-family / type combination) | No |
| C-7 | `event_type` ∈ `A(g, E)` and the pair ∈ `S(g)` and its lifecycle is ACTIVE or DEPRECATED | `SUBSCRIBED_SUPPORTED` → continue at D-06 | per §18 |
| C-8 | `event_type` ∈ `A(g, E)` and row C-7 does not hold (version unknown to this build, or RETIRED) | `UNSUPPORTED_VERSION` | No |
| C-9 | `event_type` ∉ `A(g, E)` and `event_type` ∉ `X(g, E)` and the exact pair ∈ `M` with lifecycle ACTIVE or DEPRECATED and `K` is onboarded for `g` | `KNOWN_UNSUBSCRIBED` | Yes (§23) |
| C-10 | `event_type` ∉ `A(g, E)` and `event_type` ∉ `X(g, E)` and `K` is onboarded for `g` and the exact pair is absent from this build's `M`, or RETIRED | `UNSUPPORTED_VERSION` | No |
| C-11 | `event_type` ∈ `X(g, E)`: the entry lies inside a retired obligation interval of its type | `OBLIGATION_RETIRED` | No |
| C-12 | `K` is not onboarded for `g` in the handler-contract record the worker was admitted under | `TRANSPORT_ANOMALY` (key not onboarded; TKO-02) | No |

| ID | Rule |
|---|---|
| DSQ-01 | Subscription is decided on `event_type` (rows C-7, C-8) **before** the unsubscribed rows (C-9, C-10). A subscribed type with an unsupported version can therefore never be classified `KNOWN_UNSUBSCRIBED`. |
| DSQ-02 | Rows C-1 … C-4 precede every pair lookup. An entry whose envelope cannot be parsed or validated has no trusted `event_type` and can never be classified `KNOWN_UNSUBSCRIBED`. |
| DSQ-03 | Lookups are exact-match on the pair. No prefix, pattern, nearest-version or default-handler matching exists (7C UV-02, CSR-09). |
| DSQ-04 | A failure in D-01 … D-08 causes no side effect, no repair, no partial apply and no success acknowledgement (7C CV-08). |
| DSQ-05 | Idempotency (D-09) is never evaluated before D-03 … D-07 have passed. An entry that fails validation makes no claim in any ledger. |
| DSQ-06 | The dispatcher records a semantic observation for every non-`SUBSCRIBED_SUPPORTED` class with safe fields only (class, group, key, and, when trusted, `event_type` and `event_version`). It never logs `env` (7E ENT-08, SCY-03). |
| DSQ-07 | "Not in the applicable obligation" (rows C-9, C-10) means the group does not owe that type at that entry position — it was added after the entry, or removed before it. It never means "this build lacks the handler": a build that lacks a handler for an active type is not admitted to the group at all (HCG-02), so it cannot classify anything. |
| DSQ-08 | A type that is in a build's compiled handler set but not in `A(g, E)` is not executed (HCG-06). |
| DSQ-09 | Rows C-9 and C-10 apply only to an entry read from an onboarded key. An entry from a key that is not onboarded matches neither of them, whatever its type and version, and therefore reaches row C-12; row C-10 never swallows it. |

---

## 13. Idempotency Taxonomy

Every current consumer uses exactly one primary class. No class is a `SELECT`-then-`INSERT` check.

| Class | Name | Mechanism | Proof that a duplicate is "already processed" | Concurrency arbiter |
|---|---|---|---|---|
| IC-1 | Ledger claim | Atomic `INSERT … ON CONFLICT DO NOTHING` into a primary-key or unique-backed owner ledger, **in the same transaction** as the effect | The claim returns "not inserted" and the committed ledger row is visible in the caller's tenant context | The unique index: the second inserter waits for the first transaction and then observes the conflict |
| IC-2 | Deterministic-key insert | The effect row itself carries a unique key derived only from the immutable event; `INSERT … ON CONFLICT DO NOTHING` | Every row the event derives is present after the transaction | The unique index |
| IC-3 | Guarded transition | Conditional `UPDATE … WHERE <current state>` (compare-and-swap) on the owner's state machine; dependent writes in the same transaction and only when the transition won | The row is already in the target (or a later) state | The row lock: the loser re-evaluates the predicate and updates 0 rows |
| IC-4 | Authoritative recomputation | The event is a trigger. The handler locks the consumer-side row, then recomputes the derived value from the owner's authoritative committed state in a later statement (§15, TXA-05) | Not needed: every execution converges to the authoritative value | The row lock plus a fresh statement snapshot after the lock |
| IC-5 | Naturally idempotent external write | An absolute, key-addressed external operation whose repetition leaves the same end state (set a key; delete an object by exact key) | Not needed: the operation is simply repeated | The external store's per-key semantics |

| ID | Rule |
|---|---|
| IDT-01 | A consumer is called idempotent only when §28 names the exact constraint, function or guarded statement that makes it so. |
| IDT-02 | An in-memory cache, a Redis key or a bloom filter is never an idempotency guard and never proof of prior processing. It MAY be used only as an optimisation that falls through to the authoritative guard. |
| IDT-03 | IC-5 is permitted only for the two consumers whose frozen effect is an external absolute write (CON-01, CON-08). It is never used for a counter, an append or a provider call that creates something. |

---

## 14. Inbox / Dedup Architecture Decision (7A DD-13)

### 14.1 Question

7A DD-13 defers "Inbox (consumer dedup) schema, if any shared one is needed" to 7F / 7G. 7A IDM-06 freezes that per-context ledgers exist and that 7A mandates the property, not a universal inbox table.

### 14.2 Candidate patterns

| Pattern | Description |
|---|---|
| A | Domain-owned idempotency: each consumer uses its owning context's ledger, unique constraint, guarded transition, recomputation or natural idempotency. A missing guard is added as an owner-local obligation. No cross-domain inbox table. |
| B | Universal shared inbox: one platform-level receipt store keyed by consumer obligation, event identity and tenant scope, used by all contexts in place of their own mechanisms. |
| C | Hybrid: a shared platform receipt layer plus owner-local business-key guards. |

### 14.3 Elimination against frozen constraints

| # | Frozen constraint | Effect on B | Effect on C |
|---:|---|---|---|
| E-1 | 7B §9 (ownership model, "Consumer owner"): "Each consuming bounded context owns its own handler, idempotency and projection." | A platform-owned receipt store would own every context's idempotency state. **Incompatible.** | The shared receipt layer is platform-owned idempotency state. **Incompatible.** |
| E-2 | 7A IDM-03: Billing protection is `source_event_id` under the frozen usage constraint; CRM protection is `crm.event_consumer_dedup` + `crm.fn_claim_event`. These are mandatory. | Cannot replace them. **Incompatible as a replacement.** | Adds a second claim in front of a mandatory one; gives no additional protection. |
| E-3 | 7A IDM-06: per-context ledgers are frozen facts. Analytics ingestion is reachable only through `analytics.fn_ingest_analytics_event` (`app_worker` holds no direct `INSERT` on `analytics.analytics_event_dedup`, `068_5J`). | Cannot replace the Analytics gate. | Redundant with it. |
| E-4 | `094_5D3` header: CRM consumer idempotency is CRM-owned persistence "rather than a cross-context write into Analytics". The governed precedent rejects a cross-context dedup write. | A universal table is a cross-context write for every consumer. | Same. |
| E-5 | CON-01 and CON-08 complete through an external absolute write (IC-5). A receipt committed before the write can suppress the effect after a crash; a receipt committed after it adds nothing (§15, TXA-02, TXA-03). | Unsafe or useless for them. | Unsafe or useless for them. |
| E-6 | EV-001 may carry `organization_id = null` (7C TEN-C02). A tenant-scoped shared store under row-level security cannot hold it without a tenancy exception. | Requires a new tenancy exception. | Same. |
| E-7 | 5A §1.2: a new table is placed in the owning context's existing schema; cross-schema coupling is by logical reference only. | A platform inbox written by every context is a new shared write surface. | Same. |
| E-8 | Per-consumer audit (§28): 10 of 11 durable consumers already have, or need only, an owner-local mechanism with no new table. Exactly one (CON-10) needs a new physical guard, and it is owned by one context. | No consumer needs a shared table. | No consumer needs a shared layer. |
| E-9 | 5A §1.4 principle 2 (frozen architectural principle): "Every table belongs to exactly one bounded context and therefore exactly one schema. No shared tables." | A universal inbox written and read by every context is a shared table. **Incompatible.** | The shared receipt layer is a shared table. **Incompatible.** |

### 14.4 Result

| ID | Decision |
|---|---|
| INB-01 | **DD-13 is closed: no shared inbox is needed and none is created.** Pattern A is the only pattern compatible with frozen 7B §9, 7A IDM-03 and 7A IDM-06. Patterns B and C are eliminated by E-1 … E-7 and E-9 (in particular 7B §9 and 5A §1.4 principle 2, "No shared tables"); they are not rejected as a preference. |
| INB-02 | Because one compatible design remains, this is a technical closure, not an owner decision (AUTH-7F-03). §38 records it. |
| INB-03 | Each consumer's guard is the one named in §28. Existing mechanisms are preserved exactly: `crm.fn_claim_event` (`094_5D3`), `uq_ue_idempotency` with the `<outbox_event_id>:<metric>` scheme (`050_5H`, `102_5H2`), `analytics.fn_ingest_analytics_event` and `analytics.fn_claim_projection_slot` (`068_5J`, `076_5K1`). None is replaced by an application-level pre-check. |
| INB-04 | The single missing physical guard (CON-10) is an **Integrations-owned** obligation in the existing `webhooks` schema, delivered by a governed Phase-5 migration (§35, IO-7F-21). 7F states the required properties only; it defines no DDL and assigns no migration number. |
| INB-05 | Shared **code** is permitted and required: one dispatcher library and one adapter contract (IO-7F-01, IO-7F-04). Shared code is not shared idempotency state. |
| INB-06 | A future consumer that lacks an owner-local guard adds one in its own context under the same rules. Introducing a shared inbox later would be a governed change to 7B §9 and 7A IDM-06 and an owner decision at that time. |

---

## 15. Transaction Atomicity Rules

| ID | Rule |
|---|---|
| TXA-01 | **One transaction.** For a local PostgreSQL effect, the idempotency guard and every local mutation the entry requires — including any outbox row the handler emits (7A PR-02) — are in one transaction. Either all commit or none does. |
| TXA-02 | **Prohibited: marker first.** Committing a dedup marker in one transaction and the effect in a later one is prohibited: a crash between them suppresses the effect permanently. |
| TXA-03 | **Prohibited: effect first.** Committing the effect in one transaction and the dedup marker in a later one is prohibited: a crash between them repeats the effect. |
| TXA-04 | **Prohibited: check then act.** `SELECT` "was this processed?" followed by the effect and a later marker insert is prohibited as the guard. Two concurrent deliveries both pass the check. A pre-check MAY exist only as an optimisation in front of an atomic guard. |
| TXA-05 | **Lock-then-recompute (IC-4).** The handler first locks the consumer-side row (`SELECT … FOR NO KEY UPDATE` or an equivalent row lock), then reads the authoritative state and writes the derived value in **subsequent statements** of the same `READ COMMITTED` transaction, so each of those statements takes its snapshot after the lock was obtained. A single statement that computes the value from a snapshot taken before it waited for the lock is not sufficient. Under `REPEATABLE READ` or `SERIALIZABLE` a serialization failure is `HANDLER_FAILED`. |
| TXA-06 | **Tenant context inside the transaction.** The tenant context is set transaction-locally (§30) before the first tenant-scoped statement and ends with the transaction. |
| TXA-07 | **No Redis and no external call inside.** The owner transaction contains no Redis command and no external network call. `XACK` is issued after `COMMIT` returns success. |
| TXA-08 | **Failure is total.** A deadlock, serialization failure, constraint failure or handler error rolls the whole transaction back, including the guard. The entry is `HANDLER_FAILED`; nothing is acknowledged. |
| TXA-09 | **Unknown commit outcome.** If the connection is lost while `COMMIT` is in flight, the outcome is unknown. The entry is not acknowledged on an assumption. It is acknowledged only after a later attempt proves completion through the guard (`ALREADY_COMMITTED`) or completes it. |
| TXA-10 | **Functions keep atomicity.** `SECURITY DEFINER` guard functions (`crm.fn_claim_event`, `analytics.fn_ingest_analytics_event`, `analytics.fn_claim_projection_slot`) run inside the caller's transaction; their inserts commit or roll back with it. |
| TXA-11 | **Multi-row effects.** When one event derives several rows (Billing metrics, webhook deliveries), all rows are written in the one transaction of TXA-01. Where each row is also individually idempotent (IC-2), a retry after any partial state inserts exactly the missing rows and no others. |
| TXA-12 | **Follow-up transactions.** Where a frozen owner contract splits an obligation into a first transaction and a later follow-up transaction, completion is decided from durable state, not from "this is the first delivery" (§27, MHO-04). |

---

## 16. Event-ID Dedup

| ID | Rule |
|---|---|
| EID-01 | The dedup identity of a durable event is its immutable envelope `event_id` (the outbox row `id`; 7C ID-01, ID-02). It is identical across relay retry, republication, reclaim, group recreation, generation migration and replay. |
| EID-02 | The dedup identity is never the Redis entry ID, the delivery counter, the stream key, the partition, the consumer name, `correlation_id`, `causation_id`, `aggregate_id` or a hash of the envelope bytes (7C ID-03; 7E ENT-04). |
| EID-03 | A ledger claim (IC-1) is scoped to the consumer obligation: the key contains a stable consumer identifier and the `event_id` (for example `crm.event_consumer_dedup` primary key `(consumer_name, source_event_id)`). Two obligations never share a claim. |
| EID-04 | Billing forms `source_event_id` from `event_id`: the bare `event_id` for a single-metric event and `<outbox_event_id>:<metric>` for every row of a multi-metric event (7B IDN-05; 6K §22.2). The `metric` column is not part of `uq_ue_idempotency`; the suffix is what separates the rows. |
| EID-05 | Where the owner ledger's key contains the tenant (`uq_ue_idempotency` includes `organization_id`; the Analytics `dedup_key` ends with `::{organization_id}`), the consumer supplies the validated envelope `organization_id` (7A IDM-04). |
| EID-06 | **Duplicate proof is tenant-checked.** Where the ledger key does not contain the tenant (`crm.event_consumer_dedup`), a "not inserted" result is accepted as a duplicate only after the adapter reads the existing ledger row in its own tenant context and finds it visible with the same `organization_id`. If it is not visible, the state is ambiguous: `HANDLER_FAILED`, no acknowledgement. An event of organization A can therefore never be acknowledged as a duplicate of an event of organization B. |
| EID-07 | Upcasting never changes the dedup identity: the original `event_id` and the original `event_version` are used (§25). |
| EID-08 | A consumer whose class is IC-3, IC-4 or IC-5 needs no event-id ledger: its guard is state-based and absorbs both transport and logical duplicates. No ledger is added "for uniformity". |

---

## 17. Business-Key Idempotency

Two different problems are kept separate.

| Problem | Definition | Protection |
|---|---|---|
| Transport duplicate | The same immutable `event_id` arrives again | Event-id dedup (§16) or a state-based guard |
| Logical duplicate | The same business fact is represented by a second event with a different `event_id` | The owning domain's business identity or state machine. An event-id ledger alone cannot stop it (7B IDN-09, IDN-11) |

| ID | Rule |
|---|---|
| BKG-01 | There is no generic business-key formula. Each guard below is the owning domain's own identity. |
| BKG-02 | Where the producer's state machine guarantees one committed event per business fact (7B IDN-08, IDN-10, IDN-11), that producer-side guard is the logical-duplicate protection, and the consumer adds the event-id guard. Both are required where 7B says so (EV-079: 7B INV-02). |
| BKG-03 | Where the consumer's own effect is a state transition, the transition guard (IC-3) is itself the business-key guard: a second event for the same fact finds the state already advanced. |
| BKG-04 | 7F does not invent a consumer-side uniqueness constraint the schema does not have. Where none exists and the producer guard is the protection, §28 says so. |

| Business fact | Events | Logical-duplicate guard | Evidence |
|---|---|---|---|
| Conversation accounting finalization | `conversation.completed` | Producer: durable finalization guard, one committed EV-079 per finalization generation (IDN-10, IDN-11; physical constraint is IO-7B-16). Consumer: `<outbox_event_id>:<metric>` under `uq_ue_idempotency`. The frozen payload carries no generation, so no consumer-side conversation-level key is constructible; none is invented. | 7B §27, §30 INV-02, §31.2; 7C §22 |
| Call terminal transition | `call.ended`, `call.failed` | Producer: the call state machine performs the terminal transition once; only that transaction writes the outbox row (IDN-08). Consumers add their own guards (CON-04 claim, CON-05 CAS, CON-06 unique key, CON-07 dedup key). | 7B IDN-08 |
| Campaign attempt outcome | `call.ended`, `call.failed` | `campaign.call_jobs` CAS `status = 'DISPATCHED'` keyed by `call_session_id`, plus `campaign.campaign_contacts` CAS `status = 'CALLING'`, one transaction | 6H §24.1 |
| Campaign dispatch (call placement) | (not an event consumer effect) | `uq_cj_idempotency_active`; `voice.call_dispatch_keys` primary key | 6H §18; `099_5C1` |
| Campaign attempt usage | `campaign.contact.call_attempted` | Producer: one event per attempt from the CON-05 transition. Consumer: bare `event_id` under `uq_ue_idempotency`. | 6H §24.1; 6K §22.2 |
| Workflow execution completion | `workflow.execution.completed` | Producer: execution terminal transition. Consumer: `<outbox_event_id>:<metric>`. DEP-6K-05 discriminator stays OPEN (7C §43) and is not decided here. | 7C §43; 6K §22.2 |
| Default policy seeding | `organization.created` | `uq_compliance_policy_active` (at most one ACTIVE policy per organization) | `004_5B` |
| Webhook delivery creation | 17 types of CON-10 | One fan-out per (`event_id`, obligation): owner-local claim **required, absent today** (§35). Tenants dedup on the stable webhook `event_id` (6J L844). | `063_5I`; 6J §37.2 |
| Import start | `import.job_created` | `campaign.csv_import_jobs.status` CAS `PENDING → PROCESSING` | 6H §13.1, §13.2; `028_5E` |

---

## 18. `XACK` Contract

`XACK <physical key> <group> <entry id> [<entry id> …]`, sent to the primary that owns the key, for entry IDs this member received from that key and group.

| ID | Name | Rule |
|---|---|---|
| XAK-01 | ACK-SUCCESS | For a subscribed, supported, valid event, `XACK` MAY be issued only after the obligation's durable success boundary: **(a)** the idempotency guard and the local side effects committed atomically in the owner transaction (TXA-01); **or (b)** a durable owner-specific work-intent or state transition committed that owns the remaining work (§26, EXT-02); **or (c)** a naturally idempotent external write (IC-5) definitively succeeded for every item the event requires (§26, EXT-04). |
| XAK-02 | ACK-DUPLICATE | When a redelivery finds the same event already processed, the member verifies that from the authoritative durable guard state (§13 "proof" column; EID-06), performs no business side effect, and then issues `XACK`. An in-memory cache, a Redis key or the fact that the entry was seen before is never sufficient. |
| XAK-03 | ACK-UNSUBSCRIBED | A `KNOWN_UNSUBSCRIBED` entry (row C-9) is acknowledged after classification, without an owner transaction and without any ledger claim (§23). |
| XAK-04 | ACK-NOT-APPLICABLE | A subscribed, valid event that the owner's authoritative state shows has no target in this domain is acknowledged after that determination. The determination is made from authoritative state that cannot be falsely negative because of processing order (§22). "Row not found yet" is not such a determination. |
| XAK-05 | ACK-NEVER-BEFORE-COMMIT | `XACK` before the durable success boundary is prohibited. In particular the sequence "`XACK`, then commit the database side effect" is prohibited: a crash after the acknowledgement would lose the obligation. |
| XAK-06 | ACK-FAILURE | No success acknowledgement is issued when: the entry shape or `fmt` is wrong; envelope parsing or validation fails; the profile is wrong; payload validation fails; the type is unknown; a version is unknown or RETIRED; the pair cannot belong to the stream family; the tenant or domain check fails; the handler transaction fails; an external effect that defines the success boundary fails before durable acceptance; the commit outcome is unknown; the idempotency state is ambiguous; or the event is beyond the consumer's guaranteed idempotency-evidence horizon (RET-7F-08). The entry stays pending (`HELD`). |
| XAK-07 | No disposition here | 7F defines no retry delay, no attempt limit, no poison threshold and no dead-letter destination for a `HELD` entry. 7G does (§36). 7F never acknowledges an entry in order to "drop" it. |
| XAK-08 | ACK RESULT = 0 | `XACK` returning 0 for an entry means it was not pending for the group when the command ran (acknowledged by another member after a reclaim, or group state regressed or was recreated). The member treats the delivery as finished, records an observation, and does nothing else. It MUST NOT re-run the handler, undo anything or fail the delivery. The committed domain effect stands. |
| XAK-09 | ACK error or timeout | If `XACK` fails or its reply is lost, the acknowledgement state is unknown. Re-issuing `XACK` for the same ID is safe (the command is idempotent) and is not a business retry. If it still cannot be confirmed, the entry is left pending; a later delivery takes the `ALREADY_COMMITTED` path and acknowledges. |
| XAK-10 | Independence | Transport acknowledgement state and domain completion are independent. Losing an acknowledgement (failover, 7E MF-10) re-delivers the entry and never re-applies the effect. |
| XAK-11 | Batching | One `XACK` MAY carry several IDs of the same key only if every one of them has individually reached an acknowledgeable state. An ID in any `HELD` branch is never included. |
| XAK-12 | Scope | A group's acknowledgement affects only that group (7E ACK-03). A member never acknowledges on behalf of another group and never acknowledges an ID it did not receive. |

---

## 19. Concurrent Duplicate Processing

Duplicates are not assumed to be sequential. Two members W1 and W2 can hold the same event at the same time (reclaim while the first owner is still running; republication appended twice; two generations).

| Class | What both workers do | Database / store arbitration | Result |
|---|---|---|---|
| IC-1 | Both `BEGIN`, both attempt the ledger insert | The unique index admits one speculative insert; the other waits on the first transaction. If the first commits, the second sees the conflict (`FALSE`), performs no effect and takes XAK-02. If the first rolls back, the second inserts and becomes the processor. | One effect |
| IC-2 | Both insert the same deterministic rows | Same index behaviour per row; with one transaction per event (TXA-11) the waiting worker inserts 0 rows after the first commits | One row set |
| IC-3 | Both issue the conditional `UPDATE` | The row lock serialises them; after the first commits the second re-evaluates `WHERE <state>` against the new row version and updates 0 rows; its dependent statements are skipped | One transition |
| IC-4 | Both lock the consumer-side row | The lock serialises them; the later holder recomputes from a snapshot taken after the lock and writes the freshest authoritative value | Convergent value |
| IC-5 | Both issue the same absolute external write | The store applies the same end state twice | Same end state |

| ID | Rule |
|---|---|
| CDP-01 | The rejected pattern is: `SELECT` processed marker; if absent, perform the side effect; `INSERT` the marker. Both workers pass the `SELECT`. It is never the guard (TXA-04). |
| CDP-02 | A worker that loses the race acknowledges only through XAK-02, that is, after it has observed the winner's **committed** guard state. It never acknowledges because "someone else has it". |
| CDP-03 | If the winner later rolls back, the loser (or a later delivery) becomes the processor. No effect is lost because nothing was acknowledged on an uncommitted claim. |
| CDP-04 | An advisory lock, a Redis lock or a per-key in-process mutex MAY reduce wasted work. None is a correctness mechanism, and none may be required for correctness. |
| CDP-05 | A reclaimed entry's former owner may still commit and acknowledge. Its `XACK` and the new owner's `XACK` are both harmless (XAK-08). |

---

## 20. Crash-Point Analysis

One entry `E` with `event_id = e`, delivered to group `g`. "Next delivery" means a later redelivery under 7G's policy, or a delivery after group-state regression or recreation.

| # | Crash / event point | Redis PEL state | Database state | Business effect happened? | What the next delivery does | Duplicate effect possible? | Why not |
|---:|---|---|---|---|---|---|---|
| CRP-01 | Before `XREADGROUP` | `E` undelivered; group position unchanged | Unchanged | No | Another member (or the restarted one) reads `E` with `>` | No | Nothing was started |
| CRP-02 | Immediately after delivery / PEL insertion | Pending for the crashed member | Unchanged | No | Redelivered; processed from D-01 | No | No transaction existed |
| CRP-03 | After validation, before the database transaction | Pending | Unchanged | No | Redelivered; validation is pure and repeats identically | No | Validation writes nothing (DSQ-04) |
| CRP-04 | After `BEGIN` of the idempotency transaction | Pending | Transaction aborted by connection loss | No | Redelivered; guard starts clean | No | PostgreSQL rolled back the open transaction |
| CRP-05 | After the idempotency claim, before the side effect | Pending | Claim uncommitted → rolled back with the transaction | No | Redelivered; claim succeeds again; effect applied | No | Claim and effect share one transaction (TXA-01); a claim never commits alone (TXA-02) |
| CRP-06 | After the side-effect statements, before `COMMIT` | Pending | All statements rolled back | No | Redelivered; full processing | No | Nothing committed |
| CRP-07 | During `COMMIT` | Pending | Either fully committed or fully rolled back; unknown to the worker | Unknown to the worker; exactly one of the two | Redelivered; guard decides: committed → `ALREADY_COMMITTED` → `XACK`; not committed → process | No | Commit is atomic; the worker never acknowledges on an assumption (TXA-09) |
| CRP-08 | Immediately after `COMMIT`, before `XACK` | Pending | Committed (guard + effect) | **Yes, once** | Redelivered; guard proves prior completion; no effect; `XACK` (XAK-02) | No | The committed guard state is authoritative; **this is the critical invariant** |
| CRP-09 | During `XACK` | Pending or removed (unknown) | Committed | Yes, once | If still pending: redelivered → `ALREADY_COMMITTED` → `XACK`. If removed: nothing | No | `XACK` is idempotent; the effect is guarded (XAK-09, XAK-10) |
| CRP-10 | After `XACK` | Removed | Committed | Yes, once | Nothing in the normal path. A later regression or replay re-delivers → `ALREADY_COMMITTED` | No | Guard evidence outlives the acknowledgement (§31) |
| CRP-11 | Old consumer still processing while 7G reclaims `E` to another consumer | Pending, now owned by the new member; the old member still holds `E` in memory | One of the two transactions commits first | Yes, once | The second transaction blocks on, or re-evaluates against, the first's committed guard and applies nothing (§19). Both may `XACK`; one returns 0 (XAK-08) | No | The database, not PEL ownership, arbitrates (CDP-02, CDP-05) |
| CRP-12 | Redis group-state regression (failover; 7E MF-10) makes a committed and acknowledged `E` pending or undelivered again | Regressed: `E` pending again or re-delivered by `>` | Committed | Yes, once (earlier) | Delivered again → `ALREADY_COMMITTED` → `XACK` | No | The acknowledgement was transport state only (STM-01, STM-02) |
| CRP-13 | A registered group is recreated at `0` (7E BST-03) and the retained history is delivered again | Every retained entry is undelivered for the new group | Committed for everything processed before | Yes, once each (earlier) | Each retained entry is delivered again → guard → `ALREADY_COMMITTED` → `XACK`; entries never processed are processed now | No | Same guard; evidence retention must cover this horizon (§31, RET-7F-03) |

**Critical invariant (CRI-01).** "Database `COMMIT` succeeded and `XACK` did not happen" is a safe state. It results only in a harmless redelivery that takes the duplicate path. The converse state — `XACK` happened and the commit did not — is unreachable because `XACK` is issued only after `COMMIT` returns success (XAK-05, TXA-07).

For the two IC-5 consumers the same table holds with "the external absolute write returned success" in place of `COMMIT`, and "the write is repeated with the same end state" in place of `ALREADY_COMMITTED` (§26).

---

## 21. Ordering / Reordering Contract

### 21.1 The guarantee 7F designs to

7F designs to 7E ORD-7E-01 … ORD-7E-10 exactly: append order within one physical key is the only order; group processing is concurrent; reclaimed entries arrive later; a republished duplicate of an older event can be appended after newer ones; `aggregate_id` partition affinity is not an aggregate sequence. **There is no per-aggregate processing-order guarantee.** 7F does not rely on the 7B IO-7B-08 / CR-04 wording (§41, CNF-7F-01).

### 21.2 Rejected assumptions

Each of the following is false on this platform. No consumer may depend on any of them.

| # | Rejected assumption | Why it is false |
|---:|---|---|
| RA-1 | Redis append order equals business occurrence order | Concurrent relay loops and republication change it (7E ORD-7E-03, ORD-7E-05) |
| RA-2 | The Redis entry ID is a business sequence | It is transport position only (7E ENT-04, ORD-7E-08) |
| RA-3 | A UUIDv7 `event_id` is an ordering key | It identifies a fact; it orders nothing (7E ORD-7E-04; 7C ID-03) |
| RA-4 | The same partition gives per-aggregate ordering | Partition affinity is not a sequence (7E ORD-7E-06) |
| RA-5 | The same consumer group processes in order | Members run concurrently; reclaims arrive late (7E ORD-7E-02) |
| RA-6 | Sorting by `occurred_at` makes effects safe | Timestamps do not establish transport order and are not a version (7A ORD-03) |
| RA-7 | An earlier database commit arrives first | `SKIP LOCKED` claim loops publish disjoint batches concurrently (7D SCL-02; 7E ORD-7E-05) |

### 21.3 Rules

| ID | Rule |
|---|---|
| ORD-7F-01 | A consumer MUST be correct when, for two valid events E1 and E2 of the same aggregate with E1 produced first, E2 is processed before E1, concurrently with E1, or E1 is processed twice with E2 in between. |
| ORD-7F-02 | Every current consumer effect is proven in §22 to belong to one of the classes OC-1 … OC-5. A consumer whose correctness needs an order the transport cannot give is a P1 freeze blocker; 7F found none remaining (§42). |
| ORD-7F-03 | **No reorder buffer.** 7F defines no buffering, sequencing, windowing or re-sorting of entries. |
| ORD-7F-04 | **No delay as ordering.** A sleep, a delay, a retry-later or "leave it pending until the other event arrives" is never the mechanism that makes an effect correct. A handler that cannot apply an effect yet stores what it can as an independent fact and lets the complementary handler converge (OC-4, OC-5), or reports `HANDLER_FAILED` for a genuine failure. |
| ORD-7F-05 | **No timestamp ordering.** `occurred_at`, the entry ID and the `event_id` are never compared to decide which of two effects wins. A business time value MAY be merged with a commutative operator that is part of the field's own meaning (for example "latest contact time" as a maximum); that is a commutative merge (OC-1), not an ordering of effects. |
| ORD-7F-06 | **Current-value fields are recomputed.** A consumer field that holds "the current value" of something another aggregate owns is written by authoritative recomputation (IC-4), never by copying the value an event carried. A late older event then recomputes the same current value. |
| ORD-7F-07 | **Handlers are self-sufficient.** No handler assumes that the handler of another event type has already run (for example that `call.ended` created the contact before `conversation.qualification_set` arrives). Each handler resolves what it needs through the owner's idempotent find-or-create or read port. |
| ORD-7F-08 | Version numbers do not imply recency or delivery order (7C COX-05). |

### 21.4 Ordering-proof classes

| Class | Name | Property |
|---|---|---|
| OC-1 | Commutative effect | Applying the effects in any order gives the same final state (additive sums, set union, maximum) |
| OC-2 | Monotonic state transition | A guarded transition can only move forward; a stale transition updates 0 rows |
| OC-3 | Version / state guard | The write applies only when the authoritative state still matches the event |
| OC-4 | Append-only independent facts | Each event adds its own row; rows do not depend on each other |
| OC-5 | Authoritative recomputation | The event triggers recalculation from owner state; the event's own value is not written |

---

## 22. Per-Consumer Ordering Analysis

Every (consumer, event type) pair of §10 has its own row (CON-10's 17 types share one row). "Adversarial case" is the reordering 7F tested the design against.

| CON | Event type | Class | Guard | Adversarial case and result |
|---|---|---|---|---|
| CON-01 | `identity.forced_revocation_required` | OC-1 | Set union of denylisted JTIs; each write is an absolute `SET` with a fixed TTL not shorter than the access-token lifetime | Two revocations for one user processed in reverse, or one repeated late: the denylist is the union; a repeat can only extend an entry's expiry, never shorten protection. Entries are never removed by an event. |
| CON-02 | `organization.created` | OC-3 | `uq_compliance_policy_active` | The seed arrives after the owner already activated a policy manually: the insert conflicts and seeds nothing; the owner's policy is not replaced. |
| CON-03 | `compliance.policy_activated` | OC-5 | Lock the organization row, then set the pointer from `compliance_policies WHERE status = 'ACTIVE'` | Activation of P1 then P2; the P1 event is processed last: the handler recomputes and writes P2 (the ACTIVE policy), not P1. The pointer cannot regress to an archived policy. |
| CON-04 | `call.ended` | OC-4 + OC-1 | `crm.fn_claim_event`; activity row appended once; `last_contacted_at` merged as a maximum | An older call's `call.ended` arrives after a newer one: both activities exist; `last_contacted_at` stays at the later time. |
| CON-04 | `conversation.qualification_set` | OC-5 | `crm.fn_claim_event`; contact resolved by idempotent find-or-create; qualification written by lock-then-recompute from the Voice owner read port | Arrives before `call.ended` created the contact: the handler finds-or-creates the same contact (ORD-7F-07). Two qualification events for one conversation in reverse order: both recompute the current authoritative outcome. |
| CON-04 | `conversation.summarization_completed` | OC-4 | `crm.fn_claim_event`; one AI-summary note per event | Arrives before `call.ended`: contact resolved by find-or-create; the note is an independent fact. |
| CON-05 | `call.ended` | OC-2 | `call_jobs` CAS `status = 'DISPATCHED'` and `campaign_contacts` CAS `status = 'CALLING'`, one transaction | A delayed `call.ended` of attempt 1 arrives while the contact is `CALLING` for attempt 2: the job of attempt 1 is no longer `DISPATCHED`, so 0 rows change and attempt 2 is untouched. |
| CON-05 | `call.failed` | OC-2 | Same transaction shape as `call.ended` with the failed outcome | `call.failed` and a duplicate `call.ended` for the same job: the first wins the job CAS; the second changes nothing. |
| CON-05 | `conversation.qualification_set` | OC-4 + OC-5 | Qualification stored as a fact under an attempt-identity guard; contact status derived by one order-independent function evaluated by both handlers (§28, CON-05; CNF-7F-03) | Arrives before `call.ended` (contact still `CALLING`) or after it (contact already terminal): both orders reach the same final status. The frozen 6H guard `status = 'ANSWERED'` alone would lose the qualification in both orders; 7F does not accept it (P1-7F-01). |
| CON-06 | `call.ended` | OC-4 | `uq_ue_idempotency`, bare `event_id` | Usage rows of different calls in any order: independent rows; aggregation is a sum. |
| CON-06 | `conversation.completed` | OC-4 | `uq_ue_idempotency`, `<outbox_event_id>:<metric>` per row, all rows in one transaction | EV-079 before or after `call.ended` of the same call: different metrics, independent rows. A duplicate after a partial write: only the missing rows insert. |
| CON-06 | `document.indexed` | OC-4 | `uq_ue_idempotency`, bare `event_id` | Arrives after `document.deleted`: the embedding usage was really consumed; the row is recorded regardless. |
| CON-06 | `campaign.contact.call_attempted` | OC-4 | `uq_ue_idempotency`, bare `event_id` | Attempts 2 and 1 in reverse: two independent rows. |
| CON-06 | `workflow.execution.completed` | OC-4 | `uq_ue_idempotency`, `<outbox_event_id>:<metric>` per row | Any order with other usage: independent rows. |
| CON-07 | `call.ended` | OC-1 | `analytics_event_dedup` key; projection claim; additive upsert bucketed by `occurred_at` | Late event: it updates its own historical bucket additively (5J §7.3). |
| CON-07 | `call.failed` | OC-1 | Same | Same |
| CON-07 | `contact.converted` | OC-1 | Same; `lead_funnel_daily` additive measure | Same. Projection applier is outstanding (§35); its contract is additive or `GREATEST` only. |
| CON-08 | `recording.deleted` | OC-2 | Recording row is terminally `DELETED`; object delete by exact key is absolute | No second event type exists for the aggregate in this group. A repeat deletes an absent object: success. |
| CON-09 | `document.indexed` | OC-5 | Lock the knowledge-base row, then recompute `document_count` from `knowledge.documents` | `document.deleted` processed before `document.indexed` of the same document: the recount after the delete already excludes it; the late `indexed` recounts and still excludes it. A plain `+1 / −1` would drift and could violate `chk_kb_doc_count_nn`; 7F does not accept it (P1-7F-03). |
| CON-09 | `document.deleted` | OC-5 | Same | Same. Several `document.indexed` for one document (new versions) never inflate the count. |
| CON-10 | each of its 17 types | OC-4 | One fan-out per `event_id` (owner-local claim, §35); each delivery row is an independent fact | `deal.won` delivered to the engine before `deal.created`: two independent delivery sets. Internal arrival order is not a tenant-visible webhook sequence: 6J and 6A §28.1 give no ordering guarantee, and tenants order by their own means. |
| CON-11 | `import.job_created` | OC-2 | `csv_import_jobs.status` CAS `PENDING → PROCESSING` | The event is delivered twice, or after the completion route already started the job: the CAS admits one start. |

The 17 CON-10 types are: `call.failed`, `call.transferred`, `contact.created`, `contact.qualified`, `contact.disqualified`, `deal.created`, `deal.won`, `deal.lost`, `appointment.booked`, `campaign.started`, `campaign.completed`, `campaign.contact.qualified`, `subscription.changed`, `invoice.generated`, `invoice.paid`, `payment.failed`, `usage.threshold_reached`. All 17 use the same handler and the same analysis.

SIGNAL (`sg.analytics.signal-projections`): all four types are OC-1 (additive or `GREATEST` projections bucketed by `occurred_at`; §29).

---

## 23. Known-Unsubscribed Entries

A group subscribed to a family stream receives every entry of that stream (7E §14.2). 7E GRP-08 requires each to be acknowledged eventually; an unacknowledged entry pins the stream's retention (7E TRM-02).

| ID | Rule |
|---|---|
| KUN-01 | An entry is `KNOWN_UNSUBSCRIBED` only when **all** of these hold: (1) entry shape valid (D-01); (2) `fmt` valid for the key's profile (D-02); (3) envelope parses (D-03); (4) envelope fields valid for the profile (D-04); (5) the exact pair (`event_type`, `event_version`) is in the platform manifest with lifecycle ACTIVE or DEPRECATED; (6) the pair's route family equals the family of the key it was read from; (7) the `event_type` is not in the group's active handler obligation `A(g, E)` at the entry's position (§10.4) — the absence of a handler in the local build is never the reason; (8) the entry does not lie inside a retired obligation interval of that type (HCG-19); (9) the key it was read from is onboarded for the group (TKO-02); (10) it has no canonical origin provenance record for the group with `origin_obligation = OWED` (HCG-30). This is exactly row C-9 of §12.2. |
| KUN-02 | For such an entry the group performs no payload handling, opens no owner transaction, sets no tenant context, makes no ledger claim and causes no owner-domain side effect. |
| KUN-03 | The entry is acknowledged after classification (XAK-03). No event-id claim is needed merely to skip it. |
| KUN-04 | The following are **never** `KNOWN_UNSUBSCRIBED` and are never acknowledged as such: a malformed or unparseable envelope; a wrong or unknown `fmt`; a wrong profile; corrupt encoding; an unknown `event_type`; a subscribed `event_type` with an unsupported or RETIRED version; an unsubscribed `event_type` whose exact pair is absent from the manifest or RETIRED; a pair whose route family differs from the stream's family. Each stays pending (`HELD`) for 7G. |
| KUN-05 | "Not for me" is a positive classification result, not a default. The dispatcher has no fall-through branch that acknowledges an entry it could not classify. |
| KUN-06 | The payload of an unsubscribed entry is not validated by this group (the subscribing groups validate it). The envelope is. |
| KUN-07 | A legitimate known-unsubscribed entry is never left pending: leaving it would pin retention for the whole stream with no obligation to protect. |
| KUN-08 | Because classification uses the manifest embedded in the running build, every group that reads a family stream needs a build whose manifest contains every pair routable to that family before a producer emits a new pair (§25, VER-7F-06). A stale build classifies the new pair under row C-10 and holds it; that is safe (nothing is lost or wrongly acknowledged) and is cleared by deploying the manifest. This rule covers a stale manifest only: it gives no protection when a group's handler obligation changes for a pair every build already knows. That case is governed by §10.4 (HCG-13). |
| KUN-09 | A worker can acknowledge a type as known-unsubscribed only while it is admitted under a handler contract in which the group does not owe that type at that position. A worker that lacks a handler for an active type is never admitted (HCG-02), so it can never acknowledge that type as "not for me". |

---

## 24. Invalid / Unsupported Entries

| ID | Rule |
|---|---|
| NAK-01 | `TRANSPORT_ANOMALY`, `INVALID_CONTRACT` and `UNSUPPORTED_VERSION` entries cause no business side effect, no ledger claim, no repair and no success acknowledgement (7C CV-08, UV-03). |
| NAK-02 | The entry is preserved unchanged in the stream and stays in the group's PEL. 7F never deletes, rewrites or republishes it (7C UV-04, BR-07). |
| NAK-03 | A consumer never guesses a version: it never selects the nearest or greatest known version, never falls back to a default handler, never applies part of the event and never downcasts (7C UV-02, UPC-08). |
| NAK-04 | An observation records class, group, key and — only when the envelope was trusted — `event_type` and `event_version`. It contains no field values (7C UV-05). |
| NAK-05 | A contract violation is a producer defect fixed in the producer; the committed event is never rewritten (7C CV-11). |
| NAK-06 | While such an entry is pending it pins the stream's trim watermark (7E TRM-02). That is the frozen, intended behaviour: the entry is protected until 7G disposes of it. 7F adds no bypass. |
| NAK-07 | The eventual disposition of a `HELD` entry (redelivery timing, parking, dead-lettering, operator action) is 7G's (HE-7G-7F-02). |

---

## 25. Version Coexistence / Upcasting

The 7C order is preserved exactly:

```text
original envelope parse (D-03)
  → original-version envelope validation (D-04)
  → supported-pair check (D-05)
  → original payload validation (D-06)
  → optional pure deterministic upcast (D-08)
  → idempotency guard (D-09)
  → handler (D-09)
```

| ID | Rule |
|---|---|
| VER-7F-01 | The idempotency identity is always the original immutable `event_id` (EID-07). An upcast event and its original are the same fact for every guard. |
| VER-7F-02 | Upcasting creates no event, changes no `event_id` and no `event_version`, persists nothing, publishes nothing and never makes an unsupported version supported (7C UPC-03, UPC-09). Every record a consumer writes carries the original version (7C ADP-09). |
| VER-7F-03 | Idempotency is never evaluated before the original-version validation has passed (DSQ-05). |
| VER-7F-04 | There is no downcast (7C UPC-08). |
| VER-7F-05 | **Mixed builds — group admission gate.** A consumer build enters a group's read loop only if its declared supported set `S(g)` contains every pair that the manifest marks ACTIVE or DEPRECATED for every type of `H_required(g)`. The check runs at startup, before the first `XREADGROUP`; a build that fails it does not read. Redis distributes entries to any member, so correctness cannot depend on which member receives an entry; the gate therefore keeps a build without N + 1 support out of the group entirely. This gate concerns versions of types already in the active obligation; a change of the obligation itself is gated separately by HCG-02 … HCG-09. |
| VER-7F-06 | **Consumer first, producer second (7C RD-01 … RD-03).** For a BREAKING change of type T to N + 1: (1) deploy every group that handles T with support for N and N + 1, and deploy the updated manifest to every group that reads T's family stream; (2) a deployment gate verifies that no running member of any such group lacks it; (3) only then is the producer switched. The gate is verified from deployment state, never by routing entries to particular workers. |
| VER-7F-07 | Rolling a consumer back to a build without N + 1 support is prohibited while an N + 1 event can still reach it (7C RD-R05); VER-7F-05 enforces it at startup. The same holds for a build that is not capable of the group's active obligation: HCG-02 keeps it out. |
| VER-7F-08 | If an unsupported version nevertheless reaches a member, it is `UNSUPPORTED_VERSION` (row C-8): no effect, no acknowledgement, an alert-grade observation (7C UV-08), and 7G disposition. A member with support later processes it normally. |

---

## 26. External Side Effects

| ID | Rule |
|---|---|
| EXT-01 | No PostgreSQL transaction is open across an external network call (CPM-06). |
| EXT-02 | **Durable-intent pattern (preferred).** Where the frozen owner architecture has a durable local work-intent or state machine, the consumer transaction commits the idempotency guard and that intent; `XACK` follows; a separate owner worker performs the external I/O under its own idempotency and state machine. The intent's existence is the durable acceptance. |
| EXT-03 | An acknowledged event's remaining external work is owned by the intent's worker and its own recovery. It is not re-driven by the event. |
| EXT-04 | **Direct idempotent external write (IC-5).** Where the frozen owner architecture makes the consumer itself perform an absolute external write and has no local intent table, the stream entry is the durable intent: it stays pending until the write definitively succeeds, and `XACK` is issued only then. The write must be key-addressed and absolute, "already in the target state" must be success, and any authoritative pre-check is a short read that ends before the I/O. |
| EXT-05 | An external call that creates something (places a call, sends a message, charges) is never made directly from an event handler under EXT-04. It needs the durable-intent pattern with the owner's own idempotency key. No current consumer makes such a call. |
| EXT-06 | 7F does not redesign provider integrations. Provider semantics, retries, signing and egress control are 7H's. |

| CON | External I/O in the consumer? | Pattern | Durable-acceptance boundary |
|---|---|---|---|
| CON-01 | Yes — shared hot-tier Redis denylist writes | EXT-04 | Every required `SET` acknowledged by the hot-tier Redis |
| CON-02 | No | — | Owner transaction commit |
| CON-03 | No | — | Owner transaction commit |
| CON-04 | No (Voice owner reads are in-process reads, not network I/O) | — | Owner transaction commit |
| CON-05 | No | — | Owner transaction commit, including any owed retry decision (MHO-04) |
| CON-06 | No | — | Owner transaction commit of every derived row |
| CON-07 | No | EXT-02 (ledger as intent) | `analytics.analytics_events` row committed; projections are driven from the ledger |
| CON-08 | Yes — object-storage delete | EXT-04 | Provider confirms deletion or definitive absence of the exact object key |
| CON-09 | No | — | Owner transaction commit |
| CON-10 | No in the consumer; HTTPS delivery is the separate 6J delivery worker | EXT-02 | `webhooks.webhook_deliveries` rows (status `PENDING`) and the fan-out claim committed |
| CON-11 | No in the consumer; file processing is the separate import task | EXT-02 | Job state transition committed (or proven already advanced) |

---

## 27. Multi-Handler Obligations

One Redis entry has one acknowledgement per group (7E GRP-02).

| ID | Rule |
|---|---|
| MHO-01 | Within one group, every mandatory sub-effect of an entry either commits atomically in the one owner transaction, or is durably converted into an owner-local work-intent whose existence represents acceptance, **before** `XACK`. |
| MHO-02 | `XACK` is never issued after the first of several mandatory sub-effects. |
| MHO-03 | There is no in-memory fan-out after acknowledgement. Work that exists only in process memory when `XACK` is issued is lost on a crash and is therefore prohibited for a mandatory sub-effect. |
| MHO-04 | **State-derived completion.** Where a frozen owner contract performs a mandatory follow-up in a second transaction (CON-05 retry scheduling, 6H §24.2), the handler decides completion from durable state on every delivery, including the duplicate path: if the first transaction is found already committed and the follow-up is still owed, the handler performs the follow-up (it is itself CAS-guarded) and only then acknowledges. "The first statement updated 0 rows" is not, by itself, proof that the whole obligation is complete. The owner MAY instead place the follow-up in the first transaction. |
| MHO-05 | Two handlers that need independent retry or acknowledgement lifecycles are independent obligations. They need separate Redis groups through a governed 7E registry change before activation (7E GRP-02, HE-7F-06). 7F fakes no such independence inside one group. The split itself is a handler-contract cutover with a stop point, a start position, a backfill decision, guard continuity and no overlapping execution (HCG-14). |
| MHO-06 | 7F found no current CON entry that needs a group split. |

| CON | Sub-effects of one entry | How MHO-01 is met |
|---|---|---|
| CON-04 | One handler per event type; each handler's claim, CRM writes and CRM outbox rows | One transaction |
| CON-05 | Job CAS, contact CAS, outbox rows; owed retry decision | One transaction, plus state-derived follow-up (MHO-04) |
| CON-06 | Up to five rows for `conversation.completed`; up to three for `workflow.execution.completed` | One transaction (TXA-11) |
| CON-07 | Ledger ingest; one or more projections | Ingest commits the ledger row with `processing_status = 'PENDING'` (durable intent); each projection is claim-and-mutate in one transaction, driven from the ledger |
| CON-10 | One delivery row per matching endpoint | Claim and all rows in one transaction |
| Others | Single effect | One transaction or one absolute external write set |

---

## 28. Durable Consumer Matrix

Normative. One card per current durable consumer; every card has the same attribute rows. A statement that a consumer is idempotent always names the exact constraint, function or guarded statement. Where the frozen schema provides no sufficient mechanism, the card says so and §35 classifies the activation.

Replay-safety classes (§31): **RS-STATE** — the guard evidence cannot expire ahead of the effect: either the authoritative state is subject to no retention, archival or partition retirement, or the guard row is the very row the effect mutates, so that without it the effect cannot be applied at all; redelivery is safe at any time. **RS-LEDGER** — the guard evidence is a dedup ledger with a retention period; raw redelivery is safe only inside the guaranteed evidence horizon. **RS-RETENTION-BOUNDED** — the guard evidence is the effect rows themselves, which the owner later retires from PostgreSQL (archival, partition drop); raw redelivery is safe only inside the guaranteed evidence horizon. For the last two classes an event beyond the horizon is `HELD` and goes to the owner's rebuild or reconciliation mode, never through the normal handler (RET-7F-04, RET-7F-08).

### 28.1 Summary

| CON | Group | Class | Guard (exact) | Ordering class | Transaction boundary | Activation (§35) |
|---|---|---|---|---|---|---|
| CON-01 | `cg.identity.session-denylist` | IC-5 | Absolute `SET` of `auth:revoked_jti:{jti}` with fixed TTL | OC-1 | None (external absolute writes) | IMPLEMENTATION OBLIGATION |
| CON-02 | `cg.compliance.default-policy-seeding` | IC-2 | `uq_compliance_policy_active` (`004_5B`) | OC-3 | One transaction | IMPLEMENTATION OBLIGATION |
| CON-03 | `cg.compliance.active-policy-pointer` | IC-4 | Lock `organization.organizations` row, recompute from `compliance_policies.status = 'ACTIVE'` | OC-5 | One transaction | UPSTREAM CONTROLLED RECONCILIATION REQUIRED |
| CON-04 | `cg.crm.call-history` | IC-1 | `crm.fn_claim_event` / `pk_event_consumer_dedup` (`094_5D3`) | OC-4, OC-1, OC-5 | One transaction | IMPLEMENTATION OBLIGATION |
| CON-05 | `cg.campaign.record-call-outcome` | IC-3 | `call_jobs` CAS + `campaign_contacts` CAS (6H §24.1) | OC-2, OC-4 + OC-5 | One transaction + state-derived follow-up | UPSTREAM CONTROLLED RECONCILIATION REQUIRED |
| CON-06 | `cg.billing.usage-ingestion` | IC-2 | `uq_ue_idempotency` (`050_5H`), `<outbox_event_id>:<metric>` | OC-4 | One transaction per event | Domain logic READY for four types, conditional on the evidence-horizon gate; GOVERNED MIGRATION REQUIRED for `conversation.completed` |
| CON-07 | `cg.analytics.projections` | IC-1 | `analytics.fn_ingest_analytics_event`, `analytics.fn_claim_projection_slot` (`068_5J`, `076_5K1`) | OC-1 | Ingest transaction; one transaction per projection | IMPLEMENTATION OBLIGATION |
| CON-08 | `cg.voice.recording-object-cleanup` | IC-5 | Recording row terminally `DELETED`; object delete by exact key | OC-2 | None (short read, then external delete) | UPSTREAM CONTROLLED RECONCILIATION REQUIRED |
| CON-09 | `cg.knowledge.document-count` | IC-4 | Lock `knowledge.knowledge_bases` row, recount from `knowledge.documents` | OC-5 | One transaction | UPSTREAM CONTROLLED RECONCILIATION REQUIRED |
| CON-10 | `cg.integrations.webhook-engine` | IC-1 | **No physical guard exists**; an Integrations-owned fan-out claim is required | OC-4 | One transaction | GOVERNED MIGRATION REQUIRED |
| CON-11 | `cg.campaign.import-worker` | IC-3 | `csv_import_jobs.status` CAS `PENDING → PROCESSING` (`028_5E`) | OC-2 | One transaction | UPSTREAM CONTROLLED RECONCILIATION REQUIRED |

### 28.2 CON-01 — Identity session denylist

| Attribute | Value |
|---|---|
| CON ID | CON-01 |
| Group | `cg.identity.session-denylist` |
| Owning bounded context | Identity (6B) |
| Exact event type(s) | `identity.forced_revocation_required` |
| Idempotency class | IC-5 |
| Existing frozen persistence primitive | Redis hot-tier key `auth:revoked_jti:{jti}` (6B §12.2, §12.4). The sessions are already durably `REVOKED` in the producing transaction (`109_5B7`); the consumer writes no PostgreSQL row. |
| Event-id dedup mechanism | None needed (EID-08). The effect is an absolute keyed write. |
| Business-key / state guard | The key is the JTI itself. Writing the same JTI again leaves the same denylist membership. |
| Transaction boundary | No PostgreSQL transaction. |
| Side effect(s) | For each element of payload `access_token_jti`: `SET auth:revoked_jti:{jti}` with the fixed 6B TTL, which is never shorter than the access-token lifetime, so a repeat can only extend an entry. An empty set is a valid no-op. |
| External I/O | Yes: the shared hot-tier Redis cluster (a different deployment from the event transport, 7E DEP-02). |
| Durable-acceptance boundary for external work | Every required `SET` acknowledged by the hot-tier Redis (EXT-04). The denylist is non-authoritative, best-effort hot-tier state by frozen design (7A SOT-02; 6B §13.5). |
| Concurrency-race protection | Two workers issue the same absolute writes; the end state is identical. |
| Duplicate-delivery behaviour | The writes are repeated; membership is unchanged; expiry is not shortened. |
| Same logical fact, different `event_id` | Two revocations of the same sessions: union of the same JTIs; harmless. |
| Out-of-order behaviour | OC-1 (set union). No event removes a denylist entry. |
| Stale-event behaviour | A very late event denylists already-expired tokens: no effect on any valid credential. |
| ACK success condition | All required writes acknowledged. |
| ACK-on-duplicate condition | Same as success: the writes are repeated and acknowledged. No stored "processed" flag is consulted. |
| No-ACK / error condition | Any write not acknowledged (hot-tier unavailable, timeout); payload invalid; `fmt` or envelope invalid. Partial writes are harmless and are repeated. |
| Replay-safety classification | RS-STATE (absolute writes; safe at any time). |
| Implementation obligation | IO-7F-11: fixed TTL ≥ access-token lifetime; acknowledge only after every write; platform-scoped handling of `organization_id = null` (no tenant context, no tenant-scoped database write; 7C TEN-C02, 7E TNY-04). |
| Frozen evidence | 7B CON-01, §12.1 L451; 7C EV-001 (§20.4), TEN-C02; 6B §12.2, §12.4, §13.5; 7D PCI-04; 7E R-001. |

### 28.3 CON-02 — Compliance default-policy seeding

| Attribute | Value |
|---|---|
| CON ID | CON-02 |
| Group | `cg.compliance.default-policy-seeding` |
| Owning bounded context | Compliance (6C) |
| Exact event type(s) | `organization.created` |
| Idempotency class | IC-2 |
| Existing frozen persistence primitive | `organization.compliance_policies` with partial unique index `uq_compliance_policy_active ON (organization_id) WHERE status = 'ACTIVE'` (`004_5B`). |
| Event-id dedup mechanism | None separate. The unique index on the effect row is the guard. |
| Business-key / state guard | At most one ACTIVE policy per organization. The seed is `INSERT … ON CONFLICT (organization_id) WHERE status = 'ACTIVE' DO NOTHING`. |
| Transaction boundary | One transaction: tenant context, the guarded insert, commit. |
| Side effect(s) | One ACTIVE default policy row (India-first defaults, 5B §25.1) when the organization has none. |
| External I/O | No. |
| Durable-acceptance boundary for external work | Not applicable. |
| Concurrency-race protection | The partial unique index: one inserter wins; the other waits and then inserts nothing. 6C §7.7 also permits a pre-check ("does a policy exist?"); under 7F that pre-check is advisory only and is never the guard (TXA-04). |
| Duplicate-delivery behaviour | The insert conflicts and writes nothing. |
| Same logical fact, different `event_id` | An organization is created once (producer). A second event would still conflict on the index. |
| Out-of-order behaviour | OC-3. One event type; the only competing writer is the owner's manual activation, which the same index arbitrates. |
| Stale-event behaviour | The seed arrives after a policy is already ACTIVE: no-op; the active policy is never replaced. |
| ACK success condition | The transaction committed with the row inserted. |
| ACK-on-duplicate condition | The transaction committed with 0 rows inserted because an ACTIVE policy exists for the organization (the conflict is the proof). |
| No-ACK / error condition | Transaction failure; tenant gate failure; payload organization ≠ envelope organization; organization row not visible in the tenant context. |
| Replay-safety classification | RS-STATE. |
| Implementation obligation | IO-7F-12: use the atomic conflict form; tenant context from the envelope `organization_id` (6C's "from the event payload" wording is reconciled by CNF-7F-08). |
| Frozen evidence | 7B CON-02; 6C §7.7 (L229 – L258); `004_5B` L44; 7C EV-002; 7D PCI-05; 7E R-002. |

### 28.4 CON-03 — Compliance active-policy pointer

| Attribute | Value |
|---|---|
| CON ID | CON-03 |
| Group | `cg.compliance.active-policy-pointer` |
| Owning bounded context | Compliance (6C) |
| Exact event type(s) | `compliance.policy_activated` |
| Idempotency class | IC-4 |
| Existing frozen persistence primitive | `organization.organizations.compliance_policy_id` (`003_5B`), a non-authoritative denormalized pointer; `organization.compliance_policies.status = 'ACTIVE'` is the sole authority (6C §12.2). |
| Event-id dedup mechanism | None needed (EID-08). |
| Business-key / state guard | Lock-then-recompute (TXA-05): lock the organization row, then set the pointer to the `id` of the policy whose `status = 'ACTIVE'` for that organization (or `NULL` if none). The event's `compliance_policy_id` is not written. |
| Transaction boundary | One `READ COMMITTED` transaction: tenant context, row lock, recompute, commit. |
| Side effect(s) | The pointer equals the currently ACTIVE policy. |
| External I/O | No. Cache invalidation is not this consumer's work (6C §21: it is synchronous in the activation request). |
| Durable-acceptance boundary for external work | Not applicable. |
| Concurrency-race protection | The row lock serialises handlers; the later holder reads a snapshot taken after the lock and writes the freshest authoritative value. |
| Duplicate-delivery behaviour | Recomputes the same value. |
| Same logical fact, different `event_id` | Recomputes the same value. |
| Out-of-order behaviour | OC-5. The frozen 6C text describes an unconditional `UPDATE … SET compliance_policy_id = :new_id`; with reordered delivery that statement writes an archived policy after a newer one. 7F does not accept it (P1-7F-04) and requires the recomputation above. |
| Stale-event behaviour | A late older activation recomputes the current ACTIVE policy; the pointer cannot regress. |
| ACK success condition | The transaction committed. |
| ACK-on-duplicate condition | Same: the recomputation committed (it may change nothing). |
| No-ACK / error condition | Transaction failure; organization row not visible in the tenant context; tenant gate failure. |
| Replay-safety classification | RS-STATE. |
| Implementation obligation | IO-7F-13; controlled 6C reconciliation of the unconditional-update wording (CNF-7F-02). |
| Frozen evidence | 7B CON-03; 6C §12.2 (L616 – L628), §20, §21; `003_5B` L31; `004_5B` L44; 7C EV-003; 7D PCI-06; 7E R-003. |

### 28.5 CON-04 — CRM call history

| Attribute | Value |
|---|---|
| CON ID | CON-04 |
| Group | `cg.crm.call-history` |
| Owning bounded context | CRM (6G) |
| Exact event type(s) | `call.ended`, `conversation.qualification_set`, `conversation.summarization_completed` |
| Idempotency class | IC-1 |
| Existing frozen persistence primitive | `crm.event_consumer_dedup`, primary key `(consumer_name, source_event_id)`, and `crm.fn_claim_event(consumer_name, event_id, organization_id)` (`094_5D3`). |
| Event-id dedup mechanism | `crm.fn_claim_event` called once, in the same transaction as the side effect, with the frozen subscriber names `crm.call_ended_subscriber`, `crm.qualification_set_subscriber`, `crm.summarization_completed_subscriber`. It is an atomic primary-key claim, not a `SELECT`-before-`INSERT`; it is not replaced by an application pre-check. |
| Business-key / state guard | Contact resolution by CRM's idempotent find-or-create (partial unique index `uq_contacts_phone`, 6G L218). The call-terminal fact is single by the Voice state machine (7B IDN-08). No consumer-side uniqueness on the activity's call reference exists in the schema and none is invented (BKG-04). |
| Transaction boundary | One transaction per event: tenant context, claim, CRM writes, any CRM outbox rows, commit. |
| Side effect(s) | `call.ended`: find-or-create contact, `RecordActivity(CALL)`, `last_contacted_at` merged as a maximum. `conversation.qualification_set`: `SetQualificationStatus` with the conversation's current authoritative outcome (lock the contact row, then read it through the Voice owner read port). `conversation.summarization_completed`: `AddNote(source = AI_SUMMARY)`; the summary text is read through the Voice owner API (7C PAY-06). |
| External I/O | No. Voice owner reads are in-process reads. |
| Durable-acceptance boundary for external work | Not applicable. |
| Concurrency-race protection | `pk_event_consumer_dedup`: the second claimant waits for the first transaction, then receives `FALSE`. If the first rolls back, the claim rolls back with it and the event is retryable. |
| Duplicate-delivery behaviour | `fn_claim_event` returns `FALSE`; no CRM write. |
| Same logical fact, different `event_id` | Not stopped by the ledger. Protected by the producer's single terminal transition (IDN-08) for `call.ended`; qualification is a recomputation (harmless); a second summarization event would add a second note — the producer (post-call summarization worker) is the guard. |
| Out-of-order behaviour | OC-4 (activity, note), OC-1 (`last_contacted_at`), OC-5 (qualification). Every handler is self-sufficient (ORD-7F-07). |
| Stale-event behaviour | A late older `call.ended` adds its activity and cannot lower `last_contacted_at`. A late older qualification recomputes the current value. |
| ACK success condition | The transaction committed with the claim and the effect. A handler whose business rule yields a legitimate no-op still commits its claim. |
| ACK-on-duplicate condition | `fn_claim_event` returned `FALSE` **and** the existing ledger row is visible in the caller's tenant context with the same `organization_id` (EID-06). |
| No-ACK / error condition | Transaction failure; the Voice owner read cannot resolve the call or conversation in the tenant; claim `FALSE` with no visible ledger row (ambiguous); tenant gate failure; event beyond the 30-day evidence horizon (`BEYOND_HORIZON`, RET-7F-08). |
| Replay-safety classification | RS-LEDGER. The documented ledger retention is 30 days (`094_5D3`); an event beyond that horizon is `HELD` by the evidence-horizon gate (RET-7F-08) and needs a CRM-owned rebuild or reconciliation path, not raw redelivery (§31). |
| Implementation obligation | IO-7F-14: claim-in-transaction; duplicate tenant check; maximum merge for `last_contacted_at`; lock-then-recompute for qualification; handler self-sufficiency. |
| Frozen evidence | 7B CON-04; 6G §23.1 (L861 – L863), §27 (L945); `094_5D3` (whole file); 7A IDM-03; 7C EV-005, EV-076, EV-078, PAY-06; 7E R-005. |

### 28.6 CON-05 — Campaign `RecordCallOutcome`

| Attribute | Value |
|---|---|
| CON ID | CON-05 |
| Group | `cg.campaign.record-call-outcome` |
| Owning bounded context | Campaign (6H) |
| Exact event type(s) | `call.ended`, `call.failed`, `conversation.qualification_set` |
| Idempotency class | IC-3 |
| Existing frozen persistence primitive | `campaign.call_jobs` (`chk_cj_status`, `031_5E`; lookup by `call_session_id`) and `campaign.campaign_contacts` (`chk_cc_status`, `chk_cc_qual_result`, `030_5E`). |
| Event-id dedup mechanism | None (EID-08): no Campaign event ledger exists and none is needed. The state guard below absorbs transport and logical duplicates. |
| Business-key / state guard | 6H §24.1: `UPDATE call_jobs … WHERE status = 'DISPATCHED'`; only if it changed one row, `UPDATE campaign_contacts … WHERE status = 'CALLING'`. Both in one transaction, both CAS-guarded. Qualification: stored as a fact (`qualification_result`, `qualification_reason`) under an attempt-identity guard; contact status computed by one order-independent function of the outcome fact and the qualification fact, evaluated by both handlers. |
| Transaction boundary | One transaction for the outcome (job CAS, contact CAS, the `campaign.contact.call_attempted` outbox row and any other Campaign outbox row). The retry decision of 6H §24.2 is either in that transaction or a state-derived follow-up (MHO-04). |
| Side effect(s) | Job terminal status; contact outcome, status, `attempt_count`, `call_session_refs`; retry scheduling where owed; qualification result. |
| External I/O | No. Call placement is the separate executor path with its own dispatch keys (6H §18); it is not an effect of this consumer. |
| Durable-acceptance boundary for external work | Not applicable. |
| Concurrency-race protection | Row locks on the job and the contact: the loser re-evaluates the status predicate and updates 0 rows, and skips its dependent statements. |
| Duplicate-delivery behaviour | Job CAS updates 0 rows; the contact is not touched; then the handler checks whether a follow-up is still owed (MHO-04) before acknowledging. |
| Same logical fact, different `event_id` | Same as a transport duplicate: the job is no longer `DISPATCHED`. |
| Out-of-order behaviour | `call.ended` / `call.failed`: OC-2. `conversation.qualification_set`: the frozen statement `… WHERE status = 'ANSWERED'` (6H §24.3) is order-dependent and, because 6H §24.1 never sets `ANSWERED`, matches in neither order. 7F does not accept it (P1-7F-01) and requires the order-independent form above (OC-4 + OC-5). |
| Stale-event behaviour | A delayed outcome of a superseded attempt changes nothing. A qualification of a superseded attempt changes nothing (attempt-identity guard). |
| ACK success condition | The outcome transaction committed **and** no follow-up is owed for this attempt. |
| ACK-on-duplicate condition | The job is found in a terminal status for this `call_session_id`, the contact is not left in a transient status owed a retry decision by this attempt, and (for qualification) the stored qualification fact is present or the event is proven stale. |
| No-ACK / error condition | Transaction failure; the call is campaign-originated (Voice owner record) but no job can be correlated — this is **not** `NOT_APPLICABLE`; tenant gate failure. A call that the Voice owner record shows is not campaign-originated is `NOT_APPLICABLE` and is acknowledged (XAK-04). |
| Replay-safety classification | RS-STATE. |
| Implementation obligation | IO-7F-15: state-derived completion; campaign-origin determination from the Voice owner record instead of the 6H "0 rows → commit" shortcut; order-independent qualification. Controlled 6H reconciliation: CNF-7F-03 (qualification), CNF-7F-04 (orphaned outcome), CNF-7F-09 (outbox rows inside the transaction). |
| Frozen evidence | 7B CON-05; 6H §16.1, §23.3, §24.1 – §24.4 (L1293 – L1372), §32; 4D §7.1 – §7.2 (L264 – L267, L636 – L644); `030_5E` L31 – L34; `031_5E` L25; `011_5C` L24 (`campaign_lead_ref`); 7C EV-005, EV-006, EV-076, EV-090; 7E R-005, R-006. |

### 28.7 CON-06 — Billing usage ingestion

| Attribute | Value |
|---|---|
| CON ID | CON-06 |
| Group | `cg.billing.usage-ingestion` |
| Owning bounded context | Billing (6K) |
| Exact event type(s) | `call.ended`, `conversation.completed`, `document.indexed`, `campaign.contact.call_attempted`, `workflow.execution.completed` |
| Idempotency class | IC-2 |
| Existing frozen persistence primitive | `billing.usage_events` with `uq_ue_idempotency UNIQUE (organization_id, source_system, source_event_id, occurred_at)` (`050_5H`). `metric` is **not** part of the key. `UPDATE` and `DELETE` are revoked from `app_worker`. |
| Event-id dedup mechanism | `INSERT … ON CONFLICT (organization_id, source_system, source_event_id, occurred_at) DO NOTHING` with `source_event_id` = the bare `event_id` for a single-metric event (`call.ended`, `document.indexed`, `campaign.contact.call_attempted`) and `<outbox_event_id>:<metric>` for every row of a multi-metric event (`conversation.completed`, `workflow.execution.completed`). |
| Business-key / state guard | For `conversation.completed`: the producer-side finalization guard (7B IDN-11) allows one committed EV-079 per finalization generation; the consumer adds `<outbox_event_id>:<metric>`. Both are required (7B INV-02). Billing never ingests from `conversation.turn_completed` (OD-7B-01; 7B CR-05). |
| Transaction boundary | One transaction per event containing every row the event derives (up to five for `conversation.completed`: `AI_MINUTES`, `STT_SECONDS`, `TTS_CHARACTERS`, `LLM_PROMPT_TOKENS`, `LLM_COMPLETION_TOKENS`). |
| Side effect(s) | Append-only `usage_events` rows. `usage_records` aggregation and quota counters are separate Billing jobs (5H §12; 6K §25.2), not effects of this consumer. |
| External I/O | No. |
| Durable-acceptance boundary for external work | Not applicable. |
| Concurrency-race protection | The unique index, per row. A concurrent second transaction waits, then inserts 0 rows. |
| Duplicate-delivery behaviour | Every insert conflicts; 0 rows. |
| Same logical fact, different `event_id` | Not stopped by `uq_ue_idempotency`. Prevented by the producers' single terminal transitions (IDN-08) and, for EV-079, by the finalization guard (IDN-11, IO-7B-16). No consumer-side conversation key is constructible from the frozen payload and none is invented (BKG-04). |
| Out-of-order behaviour | OC-4. Each row is an independent fact; aggregation is a sum over rows, so arrival order never changes a charge. |
| Stale-event behaviour | Inside the guaranteed evidence horizon a late event inserts its rows with its own business `occurred_at`; late usage after a period closes is governed by 6K (billing adjustments), unchanged by 7F. **Beyond the horizon the event takes no insert path at all:** it is `BEYOND_HORIZON` → `HELD` (RET-7F-08, RET-7F-09). |
| ACK success condition | The transaction committed; every derived row is present (inserted now or already present). |
| ACK-on-duplicate condition | The transaction committed with all inserts conflicting. The conflict key contains `organization_id`, so the proof is tenant-scoped. |
| No-ACK / error condition | Transaction failure; payload invalid (including EV-079 invariants USG-01 … USG-08); tenant gate failure; the event's `occurred_at` is beyond the guaranteed evidence horizon, or its position relative to the horizon cannot be determined (`BEYOND_HORIZON`; resolved by Billing-owned reconciliation, never by the normal handler). |
| Replay-safety classification | RS-RETENTION-BOUNDED. `uq_ue_idempotency` absorbs a duplicate only while the original row is still in PostgreSQL. 5H keeps raw `usage_events` 90 days hot, archives them to S3 thereafter and partitions monthly so that partitions can be dropped (5H §12 L292; ADR-5H-010). After that the uniqueness evidence is gone and a normal insert would create a second usage fact. Raw redelivery or replay through this consumer is therefore safe only inside the guaranteed hot horizon; this applies to all five event types. The S3 archive is not idempotency evidence for the handler (RET-7F-09). |
| Implementation obligation | IO-7F-16: **derivation determinism** — for every row, `source_system`, `source_event_id`, `occurred_at`, `metric` and the quantity are pure functions of the immutable envelope and payload and the fixed 6K mapping (`occurred_at` = `ended_at`, `completed_at`, `indexed_at`, `attempted_at` respectively; never a clock). A redelivery therefore computes the identical key. Changing the mapping is a governed change, because it changes the dedup key. One transaction per event. **Evidence-horizon gate (IO-7F-33):** before any insert the handler checks the rows' `occurred_at` against the guaranteed hot horizon with the database clock; outside it, or in doubt, it issues no insert and returns `BEYOND_HORIZON`. The check is taken under the shared retention barrier of `billing.usage_events`, and partition retirement takes the same barrier exclusively (IO-7F-35; RET-7F-11 … RET-7F-14). The handler never queries the S3 archive. Resolution of held events is the Billing-owned reconciliation path (IO-7F-34). |
| Frozen evidence | 7B CON-06, §26, §27 IDN-05 / IDN-10 / IDN-11, §30, §31; 6K §21.1, §22.1 – §22.3, §35 (L1909 – L1971, L2511); 5H §12 L292, §19 L447, ADR-5H-010 L2192; `050_5H` L16; `102_5H2` header item 3; 7A IDM-03; 7C §22 (USG-09), EV-005, EV-081, EV-090, EV-100; 7E R-005, SR-02. |

### 28.8 CON-07 — Analytics projections (durable part)

| Attribute | Value |
|---|---|
| CON ID | CON-07 |
| Group | `cg.analytics.projections` |
| Owning bounded context | Analytics (6L) |
| Exact event type(s) | `call.ended`, `call.failed`, `contact.converted` |
| Idempotency class | IC-1 |
| Existing frozen persistence primitive | `analytics.analytics_event_dedup` (primary key `dedup_key`), `analytics.analytics_events`, `analytics.analytics_projection_events` (`uq_ape_projection_event`), functions `analytics.fn_ingest_analytics_event`, `analytics.fn_claim_projection_slot`, `analytics.fn_apply_projection_call_metrics`, `analytics.fn_apply_projection_call_latency` (`068_5J`, `069_5J`, `076_5K1`). |
| Event-id dedup mechanism | `fn_ingest_analytics_event` with `dedup_key = '{event_type}::{event_id}::{organization_id}'` (5J §8.1): the dedup insert and the ledger insert are atomic inside the function. No second Analytics inbox is created. |
| Business-key / state guard | Per projection: `fn_claim_projection_slot(projection_name, analytics_event_id)` and the additive upsert in one transaction (5J §9.2). |
| Transaction boundary | Ingest: one transaction. Each projection: one claim-and-mutate transaction. |
| Side effect(s) | A ledger row (`processing_status = 'PENDING'`); then additive projection upserts (`call_metrics_hourly`; `agent_utilization_hourly`; `lead_funnel_daily`). |
| External I/O | No. |
| Durable-acceptance boundary for external work | The committed ledger row is the owner-local work-intent for the projections (EXT-02): the Analytics projection loop is driven from `PENDING` ledger rows, not from the stream entry. |
| Concurrency-race protection | `pk_analytics_event_dedup` for ingest; `uq_ape_projection_event` for each projection. |
| Duplicate-delivery behaviour | `fn_ingest_analytics_event` returns `FALSE`; nothing is inserted; projections are not triggered by the duplicate. |
| Same logical fact, different `event_id` | A different `event_id` gives a different `dedup_key` and would be counted. Prevented by the producers (IDN-08). |
| Out-of-order behaviour | OC-1. Measures are additive (or `GREATEST` for `peak_concurrent`), bucketed by business `occurred_at` (5J §7.3). No projection may derive a measure from arrival order. |
| Stale-event behaviour | A late event updates its own historical bucket. An event older than the 90-day horizon is not sent through the normal path (5J §12.2): it is `HELD` for the owner's rebuild mode (§31). |
| ACK success condition | The ingest transaction committed with `TRUE`. |
| ACK-on-duplicate condition | `fn_ingest_analytics_event` returned `FALSE` and the dedup row is visible in the caller's tenant context (the key itself ends with the organization). |
| No-ACK / error condition | Transaction failure; the Analytics adapter finds the pair unregistered or RETIRED in `analytics.event_schema_versions` (7C ADP-05: handled as an unknown version); event beyond the dedup horizon; tenant gate failure. |
| Replay-safety classification | RS-LEDGER (90 days, 5J §8.3, §9.4, §12; rebuild mode beyond it). |
| Implementation obligation | IO-7F-17: 7C adapter before ingest; projection loop driven from `PENDING` rows; projection appliers for `agent_utilization_hourly` and `lead_funnel_daily` built as claim-and-mutate in one transaction with additive or `GREATEST` measures only (no applier function exists for them today; `app_worker` holds the needed grants, so no migration is implied). |
| Frozen evidence | 7B CON-07, §25; 5J §4.1, §7.2 – §7.3, §8, §9, §10.4 – §10.5, §12; `068_5J`; `076_5K1` L120 – L165; 6L L457, L790 – L797; 7C §24 (ADP-01 … ADP-11); 7E R-005, R-006. |

### 28.9 CON-08 — Voice recording-object cleanup

| Attribute | Value |
|---|---|
| CON ID | CON-08 |
| Group | `cg.voice.recording-object-cleanup` |
| Owning bounded context | Voice (6D) |
| Exact event type(s) | `recording.deleted` |
| Idempotency class | IC-5 |
| Existing frozen persistence primitive | `voice.recordings` (row retained with `status = 'DELETED'`, `storage_ref` cleared, `chk_rec_storage_ref_path`; `014_5C`). No cleanup-intent table exists. |
| Event-id dedup mechanism | None needed (EID-08). |
| Business-key / state guard | Authoritative pre-check: the recording row is visible in the envelope's tenant context with `status = 'DELETED'`. The delete targets the exact object key of that recording. |
| Transaction boundary | A short read transaction for the pre-check, ended before the delete call. No transaction spans the provider call. |
| Side effect(s) | Delete of one stored object. |
| External I/O | Yes: object storage. |
| Durable-acceptance boundary for external work | The provider confirms deletion, or definitively reports that the exact key does not exist (EXT-04). An ambiguous response, a timeout or an access error is not acceptance. |
| Concurrency-race protection | Two workers delete the same key; the end state is "absent". |
| Duplicate-delivery behaviour | The delete is repeated; "already absent" is success. |
| Same logical fact, different `event_id` | The producer's CAS `STORED → DELETED` (6D §16.3a) admits one event per recording. A second would repeat the same delete. |
| Out-of-order behaviour | OC-2. `DELETED` is terminal and the row is never re-stored. |
| Stale-event behaviour | A very late repeat deletes an absent object. This is safe only because an object key is never reused for another recording (obligation below). |
| ACK success condition | The durable-acceptance boundary above is reached. |
| ACK-on-duplicate condition | Same as success: the delete is repeated and confirmed absent. No stored flag is consulted. |
| No-ACK / error condition | Recording row not visible in the tenant, or not `DELETED`; no trusted cleanup reference available; provider failure or ambiguity. |
| Replay-safety classification | RS-STATE, conditional on object keys never being reused. |
| Implementation obligation | IO-7F-18. **Blocking gap (P1-7F-05):** 6D §16.3a hands the object key to the worker as `_internal_cleanup_ref` in the event payload, but the frozen 7C V1 payload of `recording.deleted` carries only `recording_id`, `deleted_at`, `deleted_by`, 7C REG-07 never binds `storage_ref`, and the row's `storage_ref` is cleared in the producing transaction. Under the frozen contracts the worker has no durable trusted source for the key. 7F does not guess one and does not derive it from untrusted input. The remedy is an upstream governed change (CNF-7F-05); the consumer is not activated before it. Provider-specific deletion semantics (for example versioned buckets) are 7H's. |
| Frozen evidence | 7B CON-08; 6D §16.3a (L754 – L803); `014_5C` L14, L32; 5C §5.8 L389 (key format); 7C EV-009 (§20.4), REG-07 (L614); 7D PCI-12; 7E R-009. |

### 28.10 CON-09 — Knowledge `document_count`

| Attribute | Value |
|---|---|
| CON ID | CON-09 |
| Group | `cg.knowledge.document-count` |
| Owning bounded context | Knowledge (6F) |
| Exact event type(s) | `document.deleted`, `document.indexed` |
| Idempotency class | IC-4 |
| Existing frozen persistence primitive | `knowledge.knowledge_bases.document_count INTEGER NOT NULL DEFAULT 0` with `chk_kb_doc_count_nn` (`035_5F`); `knowledge.documents` (`status`, `deleted_at`; `036_5F`). No Knowledge event ledger exists. |
| Event-id dedup mechanism | None needed (EID-08). |
| Business-key / state guard | Lock-then-recompute (TXA-05): lock the knowledge-base row named by payload `knowledge_base_id`, then set `document_count` to the count of that knowledge base's documents that the Knowledge owner defines as counted, read from `knowledge.documents`. Both tables are Knowledge's own. |
| Transaction boundary | One `READ COMMITTED` transaction: tenant context, row lock, recount, commit. |
| Side effect(s) | `document_count` equals the authoritative count. |
| External I/O | No. |
| Durable-acceptance boundary for external work | Not applicable. |
| Concurrency-race protection | The knowledge-base row lock; the later holder counts from a snapshot taken after the lock. |
| Duplicate-delivery behaviour | Recounts the same value. |
| Same logical fact, different `event_id` | Recounts the same value. `document.indexed` is emitted for every version that becomes READY (6F §12.2), so several events per document are normal; a recount never inflates. |
| Out-of-order behaviour | OC-5. An increment / decrement projection is not idempotent, drifts under duplicates, counts a re-indexed document twice and can drive the column below zero when a delete is processed first. 7F does not accept it (P1-7F-03). |
| Stale-event behaviour | A late event recounts the current state. |
| ACK success condition | The transaction committed. |
| ACK-on-duplicate condition | Same: the recount committed (it may change nothing). |
| No-ACK / error condition | Transaction failure; knowledge-base row not visible in the tenant context; tenant gate failure. |
| Replay-safety classification | RS-STATE. |
| Implementation obligation | IO-7F-19. The exact counted predicate (which `documents.status` values count) is Knowledge-owner semantics and is bound by a controlled 6F reconciliation (CNF-7F-06). 7F fixes only that it is a pure function of committed `knowledge.documents` state. |
| Frozen evidence | 7B CON-09; 6F §9 L293, §12.2 (L434), §31 (L1022 – L1024); 4E §4.1 invariant 4 (L201); `035_5F` L19, L27; `036_5F`; 7C EV-020, EV-081; 7E R-022, R-083. |

### 28.11 CON-10 — Integrations webhook engine

| Attribute | Value |
|---|---|
| CON ID | CON-10 |
| Group | `cg.integrations.webhook-engine` |
| Owning bounded context | Integrations (6J) |
| Exact event type(s) | `call.failed`, `call.transferred`, `contact.created`, `contact.qualified`, `contact.disqualified`, `deal.created`, `deal.won`, `deal.lost`, `appointment.booked`, `campaign.started`, `campaign.completed`, `campaign.contact.qualified`, `subscription.changed`, `invoice.generated`, `invoice.paid`, `payment.failed`, `usage.threshold_reached` |
| Idempotency class | IC-1 (required) |
| Existing frozen persistence primitive | `webhooks.webhook_deliveries` (partitioned by `created_at`; primary key `(id, created_at)`; `063_5I`) and `webhooks.webhook_endpoints`. **There is no unique constraint on (`event_id`, `webhook_endpoint_id`) and no fan-out ledger.** A plain unique constraint on the delivery table is not possible: it is partitioned by `created_at`, and a governed replay intentionally creates a second row with the same `event_id` (`fn_replay_webhook_delivery`). |
| Event-id dedup mechanism | **Absent today.** Required: an Integrations-owned, non-partitioned, primary-key-backed fan-out claim keyed by the consumer obligation and the `event_id`, carrying `organization_id`, claimed atomically in the same transaction as the delivery inserts — the same shape as `crm.event_consumer_dedup` (`094_5D3`) and `campaign.campaign_contact_identities` (`098_5E1`). |
| Business-key / state guard | One fan-out per (`event_id`, obligation). The claim is recorded even when no endpoint matches, so a later redelivery cannot fan out to endpoints created afterwards. `webhook_deliveries.event_id` is the envelope `event_id`, stable across retries and replays, and is the tenant's dedup key (6J §20.1 L779, L844). |
| Transaction boundary | One transaction: tenant context, claim, one `INSERT` per matching ACTIVE endpoint of the same organization (status `PENDING`), commit. |
| Side effect(s) | Delivery rows. HTTPS delivery is performed later by the 6J delivery worker (`fn_claim_delivery`, `fn_delivery_succeeded`, `fn_delivery_failed`). |
| External I/O | None in the consumer. |
| Durable-acceptance boundary for external work | The committed delivery rows and claim (EXT-02). Delivery attempts, retries, signing and dead-lettering are the delivery worker's and 7H's. |
| Concurrency-race protection | The claim's primary key (once it exists). Without it two concurrent deliveries both insert a full set of rows. |
| Duplicate-delivery behaviour | With the claim: `FALSE`, no rows. **Without it: a second full set of delivery rows, that is, duplicate tenant-visible webhooks.** |
| Same logical fact, different `event_id` | Two delivery sets with different webhook `event_id` values; prevented only by the producers. |
| Out-of-order behaviour | OC-4. Internal arrival order is not a tenant webhook sequence (6A §28.1). |
| Stale-event behaviour | A late event fans out to the endpoints ACTIVE at processing time; 6J defines no historical matching. |
| ACK success condition | The transaction committed with the claim and all delivery rows. |
| ACK-on-duplicate condition | The claim returned "already claimed" and the claim row is visible in the caller's tenant context. |
| No-ACK / error condition | Transaction failure; tenant gate failure; **always, until the claim exists** (the consumer is not activated). |
| Replay-safety classification | RS-LEDGER once the claim exists (retention ≥ the redelivery and replay horizon, §31). Not replay-safe today. |
| Implementation obligation | IO-7F-20 (handler) and IO-7F-21 (governed Phase-5 migration, Integrations-owned, in the `webhooks` schema; DDL, names and number chosen by that migration). The operator replay path (`fn_replay_webhook_delivery`) is a deliberate, separate action and is not blocked by the claim. Topic mapping WHT-01 / WHT-02 stays pending 7H (IO-7B-12). |
| Frozen evidence | 7B CON-10, §18.2; 6J §18.10, §19.1 (L722 – L740), §20.1 (L779 – L808), §23.3 (L904 – L905), §37.2 (L1507), §38; `063_5I` L5 – L36; 7A IDM-03, RPL-03; 7E §29.1. |

### 28.12 CON-11 — Campaign import worker

| Attribute | Value |
|---|---|
| CON ID | CON-11 |
| Group | `cg.campaign.import-worker` |
| Owning bounded context | Campaign (6H) |
| Exact event type(s) | `import.job_created` |
| Idempotency class | IC-3 |
| Existing frozen persistence primitive | `campaign.csv_import_jobs.status` (`chk_cij_status`: `PENDING`, `PROCESSING`, `COMPLETED`, `FAILED`; `028_5E`); `campaign.contact_lists.status`. |
| Event-id dedup mechanism | None needed (EID-08). |
| Business-key / state guard | The job state machine: the only start is the CAS `UPDATE csv_import_jobs SET status = 'PROCESSING' … WHERE id = :import_job_id AND status = 'PENDING'` (6H §13.2). Whatever triggers a start — this consumer, the completion route (6H-018) or a reaper — goes through that CAS, so at most one start exists per job. |
| Transaction boundary | One transaction: tenant context, read the job, CAS only when the owner's start precondition holds, commit. |
| Side effect(s) | At most the `PENDING → PROCESSING` transition. Row processing is the separate checkpointed import task (6H §13.3), which is Class E work, not an effect of this consumer. |
| External I/O | None in the consumer. |
| Durable-acceptance boundary for external work | The committed job state (EXT-02): the job row is the durable intent of the import task, with its own stale-job recovery (6H §13.3; 3C §6.3). |
| Concurrency-race protection | The row lock and the status predicate: one CAS wins. |
| Duplicate-delivery behaviour | The job is no longer `PENDING`: 0 rows; nothing starts. |
| Same logical fact, different `event_id` | One event per job row (producer insert). A second would meet the same CAS. |
| Out-of-order behaviour | OC-2. The job status only moves forward. |
| Stale-event behaviour | A late event for a `PROCESSING`, `COMPLETED` or `FAILED` job changes nothing. |
| ACK success condition | The transaction committed, whether or not the CAS changed a row. |
| ACK-on-duplicate condition | The job row is visible in the tenant context and is not owed a start by this consumer (already advanced, or still `PENDING` with the upload not yet confirmed — its start is then owned by the completion route). |
| No-ACK / error condition | Transaction failure; job row not visible in the tenant context (the event is written in the job's creating transaction, so absence is an anomaly); tenant gate failure. |
| Replay-safety classification | RS-STATE. |
| Implementation obligation | IO-7F-22. Frozen sources disagree on what triggers processing: 7B TSK-03 names this event, while 6H §13.1 has the completion route perform `PENDING → PROCESSING` and enqueue the task after the upload is verified; the event is emitted earlier, at upload-URL creation (6H-017). 7F fixes only the safety rule — a single CAS-guarded start, never started merely because the event arrived — and hands the trigger wording to a controlled 6H / 7B reconciliation (CNF-7F-07). |
| Frozen evidence | 7B CON-11, §12.6 L541, §17 TSK-03; 6H §13.1 – §13.3 (L600 – L649); `028_5E` L33 – L52; 7C EV-060; 7E R-062. |

---

## 29. SIGNAL Consumer Semantics

`sg.analytics.signal-projections` is the only SIGNAL group. It is treated separately from every durable consumer.

| ID | Rule |
|---|---|
| SIG-7F-01 | The SIGNAL path is best-effort, non-authoritative and Analytics-only. Entries may be lost before, during or after consumption (7C SIG-R03; 7E SGR-03, SGR-04). 7F does not upgrade it to durable, adds no outbox persistence and makes no promise that every SIGNAL entry is eventually processed. |
| SIG-7F-02 | **V1 read and acknowledgement approach.** The SIGNAL group reads with `XREADGROUP GROUP sg.analytics.signal-projections <consumer> … NOACK STREAMS <LS-S-VOX key> >` and issues no `XACK`. This is a technical decision inside the frozen contract: 7E GRP-07 permits `NOACK` for SIGNAL groups, loss is permitted, and without a PEL a crashed or slow Analytics consumer cannot accumulate pending SIGNAL state on the `noeviction` event-transport cluster that also carries the durable streams. It changes no frozen reliability semantic. |
| SIG-7F-03 | `NOACK` is permitted **only** on this SIGNAL group. It is never used on a durable group (RDL-03). |
| SIG-7F-04 | A SIGNAL entry is decoded and classified with the same steps D-01 … D-07 against the SIGNAL profile (`fmt = signal.v1`, 7C §11, the 4 SIGNAL pairs). An entry that fails any step, or whose pair Analytics has not registered (7C ADP-05, ADP-07: `tool_execution.started` until IO-7C-11), is dropped and counted. There is no retry, no reclaim, no dead-letter and no 7G disposition for SIGNAL entries. |
| SIG-7F-05 | **Dedup key (closes 7C ID-10).** A valid SIGNAL is ingested through `analytics.fn_ingest_analytics_event` with `dedup_key = '{event_type}::{event_id}::{organization_id}'`, the same form as the durable part. A producer re-attempt that reuses the signal's `event_id` (7C ID-09) is therefore absorbed. This is deduplication of what arrives, not a delivery guarantee. |
| SIG-7F-06 | SIGNAL projections follow the same claim-and-mutate contract as durable ones (additive or `GREATEST`, bucketed by `occurred_at`). An ingest or projection failure drops the signal's contribution; it is counted, not retried from the stream. |
| SIG-7F-07 | **Billing never consumes SIGNAL.** No Billing group reads LS-S-VOX, and no Billing, compliance or financial outcome depends on DS-17 or DS-19 (OD-7B-01; 7B CR-05; 7E SR-02). Analytics token or latency figures derived from signals are never a Billing source. |
| SIG-7F-08 | The durable group `cg.analytics.projections` and the SIGNAL group are different groups on disjoint keys (7E SEP-04). A defect in one path never causes the other to acknowledge or drop anything. |

---

## 30. Tenant Context

Detailed security design is 7I's. 7F fixes the processing rules that keep idempotency tenant-safe.

| ID | Rule |
|---|---|
| TEN-7F-01 | The tenant of an entry is the `organization_id` of its **validated envelope** (7C TEN-C05; 7B CR-03; 7A PR-07). It is never taken from a stream key, partition, group name or consumer name (7E TNY-01, TNY-02) and never from arbitrary payload content. |
| TEN-7F-02 | Where a payload schema carries an organization value (for example EV-002), it must equal the envelope value; a mismatch fails D-07 (`INVALID_CONTRACT`). Frozen consumer texts that say "organization from the event payload" (6C §7.7, §12.2) are read as the envelope value (CNF-7F-08). |
| TEN-7F-03 | Before any tenant-scoped statement, the owner transaction sets the tenant context transaction-locally to the envelope `organization_id` (the `organization.current_tenant_id()` mechanism every owner table's row-level-security policy uses). The context ends with the transaction; it is never set at session level on a pooled connection. |
| TEN-7F-04 | Every resource an event references is resolved inside that tenant context. A referenced resource that is not visible there is a tenant or domain mismatch: `HANDLER_FAILED`, no acknowledgement, no effect. It is never treated as "not applicable". |
| TEN-7F-05 | Dedup identity includes the tenant wherever the owner ledger does (EID-05). Where it does not, duplicate proof is tenant-checked (EID-06). An event of organization A can neither claim nor suppress an event of organization B. |
| TEN-7F-06 | No consumer bypasses row-level security for convenience. `SECURITY DEFINER` guard functions are used only as frozen, with the envelope `organization_id` as their organization argument. |
| TEN-7F-07 | The only platform-scoped event is EV-001 with `organization_id = null` (7C TEN-C02). CON-01 processes it without a tenant context and performs no tenant-scoped database write. No other consumer accepts a null organization: for any other type it fails D-04. |
| TEN-7F-08 | Shared streams are transport co-location only (7E TNY-03). One tenant's failing entry is held on its own; it never causes another tenant's entry to be acknowledged, dropped or rolled back (CPM-04). |
| TEN-7F-09 | Final Redis ACLs, database role scoping for workers and payload logging rules are 7I's (HE-7I-7F-01 … HE-7I-7F-03). |

---

## 31. Idempotency Retention Boundary

### 31.1 Rules

"Idempotency evidence" means whatever durable state a guard reads to recognise a duplicate: a dedup ledger, the effect rows themselves, or a state-machine row. The "guaranteed evidence horizon" of a consumer is the period for which the platform guarantees that evidence is still in PostgreSQL.

| ID | Rule |
|---|---|
| RET-7F-01 | **Invariant.** Idempotency evidence, whatever its physical form, MUST survive at least as long as the redelivery and replay horizon for which it is expected to protect the side effect (7A IDM-05). The rule applies to **every finite evidence mechanism** — a ledger, effect rows under a retention policy, a partition that can be dropped — not only to a table called a ledger. Two properties are required and are proven separately: the **admission rule** (RET-7F-08) — an event outside the evidence horizon never enters the normal handler; and the **retirement-race rule** (RET-7F-11 … RET-7F-13) — the evidence protecting an already-admitted attempt cannot disappear before that attempt's guard-and-effect transaction reaches commit or rollback. |
| RET-7F-02 | 7F invents no numeric retention value. Frozen values are cited as they are: Analytics dedup and projection ledgers 90 days (5J §8.3, §9.4, §12.1); the CRM ledger's documented housekeeping period 30 days (`094_5D3`); Billing raw `usage_events` 90 days hot, then S3 archive (5H §12 L292). 7F does not generalise any of these numbers to another consumer. |
| RET-7F-03 | The horizon the evidence must cover includes every source of redelivery: PEL redelivery, republication within the outbox `PUBLISHED` retention, group-state regression, recreation of a group at `0` over the retained stream (7E BST-03), generation overlap, and 7G replay. 7G and 7I own those horizon values; each evidence owner must show its retention is not shorter (HE-7G-7F-05). |
| RET-7F-04 | For an RS-LEDGER or RS-RETENTION-BOUNDED consumer, raw redelivery of an event older than the guaranteed evidence horizon is **not** safe: the evidence may be gone and the effect would repeat. Such an event is not processed through the normal path; it is `HELD`, and the owner's rebuild or reconciliation mode applies (Analytics: 5J §12.3 historical rebuild, which never calls the normal ingest functions; Billing: RET-7F-09). |
| RET-7F-05 | **Unqualified RS-STATE is restricted.** A consumer is RS-STATE only when its evidence cannot expire ahead of the effect: either the authoritative state is subject to no retention, archival or partition retirement, or the guard row is the very row the effect mutates, so that when it is gone the effect cannot be applied at all. A consumer whose effect creates rows, and whose guard is the continued presence of those rows under a retention policy, is not RS-STATE; it is RS-RETENTION-BOUNDED. |
| RET-7F-06 | Evidence cleanup never retires evidence that is still inside its guaranteed horizon, and replay never rewrites evidence to make a replay "fit" (7A RPL-05). A partitioned evidence table is retired per partition only when every row of that partition is beyond the guaranteed horizon. Every retirement runs under the exclusive retention barrier and re-checks eligibility after acquiring it (RET-7F-12); being "outside the horizon" at some earlier moment is not sufficient. |
| RET-7F-07 | The retention of the CON-10 claim is chosen by its governed migration under RET-7F-01 and RET-7F-03 (IO-7F-21). |
| RET-7F-08 | **Evidence-horizon gate (admission rule).** Every RS-LEDGER and RS-RETENTION-BOUNDED consumer decides, before its guard statement, whether the event is inside the guaranteed evidence horizon. The gate is evaluated inside the owner transaction, **after** the shared retention barrier has been acquired (RET-7F-11), with the database clock read at that moment (`clock_timestamp()`, not the transaction start time) and the immutable business time the evidence retention is measured on (the envelope `occurred_at`; for Billing the derived row `occurred_at`, which is the partition key). Inside: normal path. Outside, or not determinable: `BEYOND_HORIZON` → `HELD` — no guard statement, no insert, no effect, no acknowledgement. The clock is used only for this admission gate; it never orders effects and never enters a dedup key. The comparison is conservative: any doubt is `HELD`. A time check that is not taken under the barrier is not sufficient. |
| RET-7F-09 | **Billing (CON-06) is RS-RETENTION-BOUNDED.** `billing.usage_events` is both the effect and the evidence. `uq_ue_idempotency` absorbs a duplicate only while the original row is in PostgreSQL; once the row has left the hot tier, `INSERT … ON CONFLICT DO NOTHING` finds nothing and would insert a second usage fact. The S3 archive is not idempotency evidence for the normal handler: no frozen architecture defines a lookup against it, `ON CONFLICT` does not consult it, and the normal handler MUST NOT query it. A Billing event beyond the guaranteed hot horizon therefore never takes the normal insert path. It is `HELD`; a Billing-owned reconciliation path — one able to tell a usage fact that was processed and later archived from one that was never processed — resolves it (IO-7F-34); 7G owns the replay mechanics. 7F adds no Billing receipt or tombstone table and no migration; a longer-lived Billing receipt ledger would be a later governed design (DEF-7F-10). |
| RET-7F-10 | The 5H rule that raw `usage_events` are not deleted while referenced by open or finalized invoices is unchanged. 7F relies only on the guaranteed minimum horizon, never on rows that happen to be retained longer. |
| RET-7F-11 | **Retention barrier.** Every finite evidence store has one owner-local retention barrier: a fixed PostgreSQL advisory-lock key defined by the owning context, always taken transaction-scoped. Every transaction that issues a guard statement against that evidence — the consumer handler transaction and, for Analytics, each projection claim-and-mutate transaction — acquires the barrier in **shared** mode (`pg_advisory_xact_lock_shared`) before the gate of RET-7F-08. Every operation that retires evidence acquires it in **exclusive** mode (`pg_advisory_xact_lock`). Shared holders coexist with each other; the exclusive holder waits until every admitted transaction has ended and blocks new ones while it runs. The barrier is released only by commit or rollback. It needs no new table and no migration. |
| RET-7F-12 | **Retirement side.** Evidence cleanup or partition retirement runs as: begin; acquire the **exclusive** barrier of that evidence store; **re-check eligibility after acquiring it**, with the database clock read at that moment — only evidence whose evidence time is older than the guaranteed horizon at that instant is eligible; retire exactly that; commit. A retirement that does not acquire the barrier, or that computed its eligibility before acquiring it, is prohibited. This binds the CRM ledger housekeeping (`crm.event_consumer_dedup`), the Analytics dedup and projection ledger cleanup and its partition maintenance, the Billing `usage_events` partition detach, drop and archive step, and the cleanup of the CON-10 claim once it exists. |
| RET-7F-13 | **Why the race is closed.** Let `H` be the guaranteed horizon. A handler reads the clock `t_h` after obtaining the shared barrier and proceeds only if `occurred_at ≥ t_h − H`. A retirement reads the clock `t_c` after obtaining the exclusive barrier and retires only evidence with evidence time `< t_c − H`. The evidence time is the timestamp the frozen cleanup of each store actually uses: Billing `usage_events` rows — the row `occurred_at` (partition key, 5H); Analytics `analytics_projection_events` — `occurred_at` (5J §20 L2381); Analytics `analytics_event_dedup` — `created_at` (5J §20 L2379); the CRM ledger — `processed_at` (`094_5D3`). For the first two the evidence time equals the event's `occurred_at`. For the last two it is the start time of the transaction that created the evidence, and RET-7F-16 guarantees that this is never earlier than the event's `occurred_at`. So for every store the evidence time is never earlier than the event's `occurred_at`; in particular the frozen `created_at` cleanup of the Analytics dedup registry is conservative for the normal ingestion path — it retires a row no earlier than an `occurred_at`-based cleanup would — and it is not changed. The barrier makes the two critical sections disjoint. If the retirement finished first, then `t_c < t_h`, so everything it retired had evidence time `< t_c − H < t_h − H ≤ occurred_at`: the admitted event's own evidence was not retired. If the handler obtained the barrier first, the retirement cannot begin until the handler's transaction has committed or rolled back, so the evidence is present for the whole guard and effect. In neither order can a duplicate be accepted as novel. No timing probability is relied on. |
| RET-7F-14 | **Billing partitions.** A `usage_events` key always routes to exactly one partition, by its `occurred_at`. A partition — the default partition included — is detached, dropped or archived only under the exclusive barrier and only when it is wholly eligible (RET-7F-06, RET-7F-12). The default partition therefore cannot become a path by which a duplicate is reinserted after its original partition was retired: an event old enough for its partition to have been retired is outside the horizon at every later instant and fails the gate before any insert. |
| RET-7F-15 | **One coordination authority; no retention value changed.** The handler and its cleanup use the same barrier key in the same database. A cleanup path that bypasses it (ad-hoc SQL, a different key, a separate tool) is prohibited. The barrier neither shortens nor lengthens any frozen retention value: the Analytics 90-day contract, the CRM 30-day housekeeping period and the Billing 90-day hot period are unchanged. A technically equivalent owner-local mechanism is acceptable only if the owner proves the same property as RET-7F-13 for it. |
| RET-7F-16 | **Future-dated events fail closed.** Where a store's evidence time is the creating transaction's start time (`analytics.analytics_event_dedup.created_at`, `crm.event_consumer_dedup.processed_at`), the handler treats an event whose `occurred_at` is later than its own transaction start time (`now()`) as not determinable: `BEYOND_HORIZON` → `HELD`. Evidence created by a conformant handler therefore always has an evidence time that is not earlier than the event's `occurred_at`. No frozen contract states that inequality by itself, so it is enforced rather than assumed. A store whose evidence time is the event's own `occurred_at` (Billing rows, the Analytics projection ledger) needs no such rule. The CON-10 claim's evidence time is chosen by its migration under the same requirement. |

### 31.2 Per-consumer evidence horizon

| CON | Class | Idempotency evidence | Guaranteed evidence horizon | Beyond the horizon |
|---|---|---|---|---|
| CON-01 | RS-STATE | None needed: absolute external writes | Unbounded | Not applicable |
| CON-02 | RS-STATE | The ACTIVE row of `organization.compliance_policies` (unpartitioned; no retention retirement in the frozen schema) | Unbounded | Not applicable |
| CON-03 | RS-STATE | None needed: recomputed from authoritative state | Unbounded | Not applicable |
| CON-04 | RS-LEDGER | `crm.event_consumer_dedup` | 30 days (`094_5D3`, documented housekeeping) | `HELD`; CRM-owned rebuild or reconciliation |
| CON-05 | RS-STATE | The job and contact rows the effect itself mutates | Unbounded for safety: without the rows no effect can be applied, and the entry is not acknowledged as applied | Not applicable |
| CON-06 | RS-RETENTION-BOUNDED | The `billing.usage_events` rows under `uq_ue_idempotency` | 90 days hot (5H §12 L292; ADR-5H-010), measured on the row `occurred_at` | `HELD`; Billing-owned reconciliation (RET-7F-09); no normal insert |
| CON-07 | RS-LEDGER | `analytics.analytics_event_dedup` (retired by `created_at`), `analytics.analytics_projection_events` (retired by `occurred_at`) | 90 days for both (5J §12.1, §20 L2379, L2381) | `HELD`; 5J §12.3 historical rebuild |
| CON-08 | RS-STATE | None needed: absolute delete of a never-reused key | Unbounded | Not applicable |
| CON-09 | RS-STATE | None needed: recount from authoritative state | Unbounded | Not applicable |
| CON-10 | RS-LEDGER (once IO-7F-21 exists) | The Integrations-owned fan-out claim | Chosen by its governed migration (RET-7F-07) | `HELD`; Integrations-owned handling |
| CON-11 | RS-STATE | The job row the effect itself mutates | Unbounded for safety | Not applicable |

---

## 32. Graceful Shutdown / Consumer Lifecycle

| ID | Rule |
|---|---|
| SHD-01 | On a shutdown signal the consumer stops issuing new `XREADGROUP` commands. A read that is blocked returns at its bounded block duration (RDL-08) or is cancelled. |
| SHD-02 | In-flight entries are allowed to reach a safe boundary within a bounded drain period (the value is 7K's): either `ACKED`, or left pending with no open transaction. |
| SHD-03 | An entry whose transaction committed is acknowledged before exit when possible. If the process exits first, the entry is pending with a committed effect — the safe state of CRI-01. |
| SHD-04 | An entry whose transaction has not committed when the drain period ends is rolled back and left pending. |
| SHD-05 | A consumer never issues `XGROUP DELCONSUMER` for itself or for another member while that member has pending entries (7E GRP-10). Routine shutdown issues no `DELCONSUMER` at all; removing idle consumer names is a governed 7G / 7K maintenance action. |
| SHD-06 | Entries left pending by a stopped or crashed consumer are recovered only by 7G's redelivery mechanism. 7F defines no idle time and no reclaim cadence. |
| SHD-07 | Shutdown never depends on a post-7.2 command (no negative acknowledgement exists in V1). |
| SHD-08 | **Startup.** Before the first read a consumer: verifies its supported set against the manifest (VER-7F-05); verifies its subscription registry equals the frozen registry (REG-7F-02); generates a fresh consumer name (RDL-05). It then performs handler-contract admission (HCG-02, HCG-03): the record must be `OPEN` and `H_required(g)` ⊆ `H_capable(build, g)`. The generation-1 record must already exist (HCG-07); if the record is missing or unreadable the worker is not admitted, and there is no fallback to the compiled registry. It creates no group and changes no group position. A build that fails any check does not read. |
| SHD-09 | **Scale-in and rolling deploy.** Removing instances is a shutdown per SHD-01 … SHD-06. Group names are stable across it (7E GRP-04). |
| SHD-10 | A member removes its handler-contract registration only after its read activities have stopped and its in-flight entries have reached a safe boundary (HCG-04, HCG-16). A registration is never removed while the member can still issue a read. |

---

## 33. Failure Matrix

"Retry owner": **Normal** = a later normal `>` read or the same attempt continues; **7G** = redelivery and disposition are 7G's. "Loss" means loss of a durable consumer obligation.

| ID | Failure / situation | Business side effect? | DB outcome | `XACK`? | Redis PEL state | Retry owner | Duplicate-safe? | Data loss possible? |
|---|---|---|---|---|---|---|---|---|
| F7F-01 | Redis read timeout (`BLOCK` elapsed, nothing delivered) | No | None | No | Unchanged | Normal | Yes | No |
| F7F-02 | Connection loss before delivery | No | None | No | Unchanged | Normal | Yes | No |
| F7F-03 | Connection loss after delivery, reply not received (RDL-10) | No | None | No | Pending for this member | 7G | Yes | No |
| F7F-04 | Malformed or wrong `fmt` (C-2) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-05 | Malformed JSON in `env` (C-3) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-06 | Duplicate JSON keys (C-3) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-07 | Unknown event type (C-5) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-08 | Wrong stream-family event (C-6) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-09 | Unsupported version of a subscribed type (C-8) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-10 | RETIRED version (C-8 / C-10) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-11 | Payload validation failure (D-06) | No | None | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-12 | Tenant mismatch (D-07 or TEN-7F-04) | No | Rolled back if a transaction was open | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-13 | First delivery succeeds | Yes, once | Committed | Yes | Removed | — | Yes | No |
| F7F-14 | Duplicate after commit | No (already done) | Guard read; nothing written | Yes (XAK-02) | Removed | — | Yes | No |
| F7F-15 | Duplicate arrives before the first transaction commits | Once (by the first) | The second waits on the guard, then writes nothing | Both, after the commit is observed | Removed | — | Yes | No |
| F7F-16 | Two consumers process the same event concurrently | Once | One commit wins (§19) | Both; one may return 0 | Removed | — | Yes | No |
| F7F-17 | Business-key logical duplicate with a new `event_id` | Depends on the fact: stopped where a state guard exists; otherwise stopped at the producer (§17) | Guarded statement changes 0 rows, or independent row | Yes | Removed | — | Per §17 | No |
| F7F-18 | Database deadlock or serialization failure | No | Rolled back entirely | No | Pending | 7G | Yes | No |
| F7F-19 | Unique-claim conflict (the guard working) | No | Nothing written by the loser | Yes, after proof (XAK-02) | Removed | — | Yes | No |
| F7F-20 | Handler constraint failure | No | Rolled back, including the claim | No | Pending (`HELD`) | 7G | Yes | No |
| F7F-21 | Process crash before commit | No | Rolled back | No | Pending | 7G | Yes | No |
| F7F-22 | Process crash after commit | Yes, once | Committed | No | Pending | 7G → duplicate path | Yes | No |
| F7F-23 | Process crash before `XACK` | Yes, once | Committed | No | Pending | 7G → duplicate path | Yes | No |
| F7F-24 | `XACK` succeeds | Yes, once | Committed | Yes | Removed | — | Yes | No |
| F7F-25 | `XACK` returns 0 | Yes, once (not repeated) | Committed; untouched | Counted as finished (XAK-08) | Not pending | — | Yes | No |
| F7F-26 | Redis disconnect during `XACK` | Yes, once | Committed | Unknown; re-issued or left (XAK-09) | Pending or removed | Normal, else 7G → duplicate path | Yes | No |
| F7F-27 | Group recreation at `0` | No new effect for processed events | Guard read | Yes, per entry | Rebuilt, then removed | Normal | Yes, inside evidence retention (§31) | No |
| F7F-28 | Redis group-state regression | No new effect | Guard read | Yes | Regressed, then removed | Normal or 7G | Yes | No |
| F7F-29 | Out-of-order older event | Per §22: convergent | Guarded statement or recomputation | Yes | Removed | — | Yes | No |
| F7F-30 | Future / newer state already present | None, or recomputed to the same value | 0 rows changed or same value | Yes | Removed | — | Yes | No |
| F7F-31 | External-intent commit succeeds, downstream external work not finished | Intent recorded; external work pending in the owner's state machine | Committed | Yes | Removed | Owner worker (not the event) | Yes | No |
| F7F-32 | Graceful shutdown with pending entries | None lost | Open transactions rolled back | Only for committed entries | Pending for the stopped member | 7G | Yes | No |
| F7F-33 | Known-unsubscribed entry (C-9) | No | None | Yes (XAK-03) | Removed | — | Yes | No |
| F7F-34 | Subscribed event with no domain target, proven from authoritative state | No | Read only | Yes (XAK-04) | Removed | — | Yes | No |
| F7F-35 | Commit outcome unknown (connection lost during `COMMIT`) | Unknown to the worker | Committed or rolled back | No | Pending | 7G → guard decides | Yes | No |
| F7F-36 | IC-5 external write partially applied, then failure | Partial absolute writes | None | No | Pending | 7G → writes repeated | Yes | No |
| F7F-37 | Event older than an RS-LEDGER consumer's guaranteed evidence horizon (CON-04, CON-07, CON-10) | No | None | No | Pending (`HELD`) | Owner rebuild mode / 7G | Yes | No |
| F7F-38 | SIGNAL entry invalid, unregistered, or its ingest fails | No | None or rolled back | n/a (`NOACK`) | No PEL | None | Yes | Loss permitted by contract |
| F7F-39 | Build without required version support starts | No | None | No | Unchanged (it never reads, VER-7F-05) | Deployment | Yes | No |
| F7F-40 | CON-10 delivered a duplicate while no fan-out claim exists | **Would be a duplicate delivery set** | Would commit twice | — | — | Prevented: the consumer is not activated before IO-7F-21 (§35) | Not until IO-7F-21 | No |
| F7F-41 | Billing event redelivered or replayed after its `usage_events` idempotency evidence may have left PostgreSQL hot retention | No: no normal usage insert, no second usage fact, no charge | None (the gate precedes any insert) | No | Pending (`HELD`) | Billing-owned reconciliation; 7G replay mechanics | Yes | No |
| F7F-42 | Stale worker lacks a newly active handler | No | None | No | Unchanged (it is never admitted: HCG-02) | Deployment | Yes | No |
| F7F-43 | Worker still contains the handler of a removed type; entry above the removal boundary | No: the handler does not execute (HCG-06); above `inactive_after` the type is known-unsubscribed | None | Yes (XAK-03) | Removed | — | Yes | No |
| F7F-44 | Active obligation would change while mixed incompatible worker builds remain | No | None | No | Unchanged (the cutover does not pass CUT-3 or CUT-5) | Deployment | Yes | No |
| F7F-45 | Group split in which the old and the new obligation could both execute one effect | No second effect: one owner per entry position, and the moved effect keeps its guard identity (HCG-14) | Second attempt, if any, is `ALREADY_COMMITTED` | Yes, after proof (XAK-02) | Removed | Cutover plan (7E / 7G / 7F) | Yes | No |
| F7F-46 | Type added to a group: entry delivered at or below the activation boundary | No: not owed before activation (HCG-10) | None | Yes (XAK-03) | Removed | 7G, only by an explicit backfill decision | Yes | No |
| F7F-47 | Removal while the group's pending list is empty but the stream holds entries it has not yet received | Yes, once each: entries at or below `B(K)` stay owed under the draining interval and are processed when delivered (HCG-11) | Committed | Yes, after durable success | Removed | Normal | Yes | No |
| F7F-48 | Addition while an undelivered backlog exists | No: every entry already in the stream is at or below `B(K)` and is not owed (HCG-10) | None | Yes (XAK-03) | Removed | 7G, only by an explicit backfill decision | Yes | No |
| F7F-49 | A build without the handler of a draining type tries to join; or the handler code would be deleted before the interval is retired | No | None | No | Unchanged (never admitted: HCG-02; deletion only after HCG-18 / CUT-9) | Deployment | Yes | No |
| F7F-50 | Group move with different old-stop and new-start positions | One effect per entry position: prevented, because one value `B(K)` closes the old interval and starts the new group (HCG-14) | Committed once | Yes | Removed | Cutover plan (7E / 7G / 7F) | Yes | No |
| F7F-51 | Entry arrives inside a retired obligation interval of its type | No | None | No | Pending (`HELD`) | 7G; owner rebuild path | Yes | No |
| F7F-52 | Evidence retirement starts after a handler passed the horizon gate and before its guard ran | Once at most: the retirement waits on the exclusive barrier until the handler transaction ends, so the guard sees the evidence | Handler commits or rolls back with the evidence present | Yes, after commit or proof | Removed | — | Yes | No |
| F7F-53 | Evidence retirement completes first; a handler that was waiting then proceeds | No new effect from a duplicate: the gate is evaluated after the barrier with a fresh clock; an event now outside the horizon is held, and an event still inside it still has its evidence (RET-7F-13) | None, or the normal guarded path | Only through the normal guard | Pending if beyond the horizon; removed otherwise | Normal; else owner reconciliation / 7G | Yes | No |
| F7F-54 | Billing partition detach or drop races a CON-06 insert | No second usage fact: same barrier; the default partition is not a reinsert path (RET-7F-14) | One row set at most | Yes, after commit or proof | Removed | — | Yes | No |
| F7F-55 | CRM or Analytics cleanup runs without the retention barrier, or without re-checking eligibility under it | Would allow a duplicate to be accepted as novel | — | — | — | Prohibited (RET-7F-12, RET-7F-15); go-live blocked until IO-7F-35 | Not until IO-7F-35 | No |
| F7F-56 | Removal: an event of the removed type was committed to the outbox before the cutover and is still `PENDING` | Yes, once: the cutover waits at CUT-5c until the row is `PUBLISHED`, so its entry lies at or below `B(K)` and stays owed (HCG-22, HCG-23) | Committed | Yes, after durable success | Removed | Normal | Yes | No |
| F7F-57 | Addition: an event of the added type was committed to the outbox before the cutover and is still `PENDING` | No: it is published before `B(K)` is captured, so it lies at or below the boundary and is not owed (HCG-10, HCG-23) | None | Yes (XAK-03) | Removed | 7G, only by an explicit backfill decision | Yes | No |
| F7F-58 | A producer would keep committing outbox rows of an affected type while the boundary is captured | Prevented: the publication fence admits no new row of the type between CUT-5a and CUT-8a (HCG-21) | — | — | — | Producer owner; cutover blocked if the producer cannot be fenced (HCG-24) | Yes | No |
| F7F-59 | A pre-fence row is `CLAIMED`, or its last transport outcome was `UNKNOWN` | No boundary is captured: the row is unresolved until the relay marks it `PUBLISHED` (HCG-22 b, c) | — | — | — | 7D relay; the cutover waits or is abandoned (HCG-25) | Yes | No |
| F7F-60 | A replayable `FAILED` pre-fence row, or a retained `PUBLISHED` row replayed for repair, would be published after the cutover | Processed only under its recorded pre-cutover disposition; it never crosses the boundary by accident (HCG-22 d, HCG-25) | Per the 7G disposition | Per the 7G disposition | — | 7G (HE-7G-7F-10) | Yes | No |
| F7F-61 | The fence would be released, or producers resumed, before the interval switch and the reopening are complete | Prevented: release is CUT-8a, after CUT-8 (HCG-12, HCG-25) | — | — | — | Cutover procedure | Yes | No |
| F7F-62 | A durable worker starts while its group has no handler-contract record, or the record is unreadable | No | None | No | Unchanged (it is not admitted and issues no read: HCG-07, SHD-08) | Provisioning (IO-7F-31) | Yes | No |
| F7F-63 | A stale relay claimant's already-started attempt would append a duplicate after another claimant marked the row `PUBLISHED` (7D LSE-08) | No wrong obligation: the attempt is a registered publication attempt, so `B(K)` is not captured until it is terminal (HCG-26, HCG-27); its duplicate lies at or below `B(K)` | Consumer guard absorbs the duplicate | Yes, after proof | Removed | Cutover waits or is abandoned | Yes | No |
| F7F-64 | An `UNKNOWN` transport attempt resolves after its outbox row became `PUBLISHED` | Same as F7F-63: the attempt must be terminal before the capture; it cannot land above `B(K)` | Consumer guard absorbs the duplicate | Yes, after proof | Removed | Cutover waits or is abandoned | Yes | No |
| F7F-65 | A retained `PUBLISHED` row, or a `FAILED` row, of a pre-cutover event is deliberately replayed after the cutover | Classified from its canonical origin provenance, whatever its new Redis ID: `NOT_OWED` if it predates an addition, `OWED` if it predates a removal (HCG-30) | Per the origin obligation | Per the origin obligation | Removed | 7G (HE-7G-7F-10) | Yes | No |
| F7F-66 | Relay publication quiescence cannot be established | No interval changes: the cutover is abandoned before CUT-7; fence and admission are released (HCG-25, HCG-27) | None | — | — | Cutover procedure | Yes | No |
| F7F-67 | A new-generation key would receive an event before its intervals exist | Prevented: no relay for the new generation is enabled before TK-6 (TKO-06) | — | — | — | 7E / 7K lifecycle (HE-7K-7F-08) | Yes | No |
| F7F-68 | A consumer would begin reading a new key before the record lists it | No read is issued: a key is read only when onboarded (TKO-02); an entry from a key that is not onboarded is never acknowledged as unsubscribed | None | No | Pending (`HELD`) if such an entry were ever read | Lifecycle procedure | Yes | No |
| F7F-69 | An active type has no interval on a new key | Prevented: the onboarding write is rejected unless it has one `OPEN` interval per active type (TKO-03) | — | — | — | Lifecycle procedure | Yes | No |
| F7F-70 | A draining or removed type would get a fresh `OPEN` interval on a new-generation key | Prevented (TKO-04): on the new key the type is not owed | None | Yes (XAK-03) for its entries on the new key | Removed | — | Yes | No |
| F7F-71 | A topology-generation onboarding and a handler-obligation cutover would change the same record at once | Prevented: one change-in-progress marker per group (TKO-08) | — | — | — | Whichever change holds the marker finishes first | Yes | No |
| F7F-72 | An old-generation interval would be retired while the old key is still live | Prevented: retirement only after 7E has retired the key (TKO-07, TK-9) | — | — | — | Lifecycle procedure | Yes | No |
| F7F-73 | A `D` event predates the addition of `D` (generation 2); `D` is removed in generation 3; the event is replayed afterwards | No: its origin record, written at the addition, says `NOT_OWED`; the removal cutover left it unchanged (HCG-29) | None | Yes (XAK-03) | Removed | 7G replay; backfill only by an explicit decision | Yes | No |
| F7F-74 | A `T` event predates the removal of `T` (generation 2); `T` is re-added in generation 3; the event is replayed afterwards | Yes, once, under its original obligation: its origin record says `OWED` and the re-addition did not rewrite it; held as `OBLIGATION_RETIRED` if its origin interval is already retired (HCG-30) | Committed, or none if held | Yes after durable success; No if held | Removed, or pending if held | 7G replay | Yes | No |
| F7F-75 | An event of `D` was produced while `D` was active between an addition and a later removal; replayed after the removal | Yes, once: the removal cutover found no earlier record and assigned `OWED` from the pre-switch contract (HCG-28) | Committed | Yes, after durable success | Removed | 7G replay | Yes | No |
| F7F-76 | An event was produced during an inactive gap; the type is re-added later; the event is replayed | No: assigned `NOT_OWED` at the re-addition, and no later cutover changes it | None | Yes (XAK-03) | Removed | 7G; only an explicit backfill decision makes it processed | Yes | No |
| F7F-77 | An event survives three or more handler-contract cutovers of its type | One immutable origin obligation: the first assignment; no later cutover adds a second answer (HCG-29) | Per the origin obligation | Per the origin obligation | Removed | 7G replay | Yes | No |
| F7F-78 | The same event is replayed onto a key of a later topology generation | Unchanged: origin provenance belongs to the logical group, not to a key or a topology generation (HCG-31) | Per the origin obligation | Per the origin obligation | Removed | 7G replay | Yes | No |

---

## 34. Implementation-Level Pseudocode

The pseudocode fixes the order of the safety boundary. An implementation may differ in structure but not in that order.

### 34.1 Normal subscribed durable event

```text
PROCESS-ENTRY(g, K, entry_id, fields):
    class, env := CLASSIFY(g, K, fields)                -- §12.1 D-01 … D-05, §12.2; pure; no DB; no claim
    if class == KNOWN_UNSUBSCRIBED: goto ACK            -- §34.5
    if class != SUBSCRIBED_SUPPORTED: HOLD(entry_id, class); return       -- §34.6; no XACK
    VALIDATE-PAYLOAD(env)                               -- D-06, original version
    org := TENANT-GATE(env)                             -- D-07
    evt := UPCAST-IF-NEEDED(env)                        -- D-08; pure; event_id unchanged
    outcome := OWNER-ADAPTER(g, evt, org)               -- D-09; §34.1a
    if outcome in {DURABLY_COMMITTED, ALREADY_COMMITTED, NOT_APPLICABLE}: goto ACK
    HOLD(entry_id, HANDLER_FAILED); return              -- no XACK
ACK:
    n := XACK K g entry_id                              -- D-10; only reached after the durable boundary
    if n == 0: observe(ACK_RESULT_ZERO)                 -- XAK-08; nothing is re-run
```

```text
OWNER-ADAPTER(g, evt, org):                             -- §34.1a, ledger-claim form (IC-1)
    BEGIN                                               -- owner PostgreSQL transaction
    SET LOCAL tenant context := org                     -- TEN-7F-03
    claimed := atomic_claim(consumer_name(g, evt), evt.event_id, org)     -- INSERT … ON CONFLICT DO NOTHING
    if not claimed:
        proven := guard_row_visible_in_tenant(evt.event_id, org)          -- EID-06
        ROLLBACK
        return ALREADY_COMMITTED if proven else HANDLER_FAILED
    apply_local_side_effects(evt)                       -- includes any outbox row of this handler
    COMMIT                                              -- claim + effects atomic (TXA-01)
    return DURABLY_COMMITTED
    on any error: ROLLBACK; return HANDLER_FAILED       -- claim rolls back with the effect (TXA-08)
```

The other classes replace the two guard lines only: IC-2 inserts the deterministic rows with `ON CONFLICT DO NOTHING` (0 rows inserted with all rows present → `ALREADY_COMMITTED`); IC-3 issues the conditional `UPDATE` and applies dependent statements only when it changed a row; IC-4 locks the row and recomputes. In every class `COMMIT` precedes `XACK`.

### 34.2 Already-processed duplicate

```text
read E (event_id = e) again
CLASSIFY, VALIDATE-PAYLOAD, TENANT-GATE                 -- identical results; no writes
BEGIN
  SET LOCAL tenant context
  claimed := atomic_claim(…, e, org)                    -- returns FALSE: committed guard row exists
  proven  := guard_row_visible_in_tenant(e, org)        -- authoritative proof (XAK-02)
ROLLBACK                                                -- nothing to commit
-- no business effect is performed
XACK K g entry_id                                       -- only because proven == TRUE
```

### 34.3 Concurrent duplicate

```text
W1: BEGIN; atomic_claim(e)  -> inserted (uncommitted)
W2: BEGIN; atomic_claim(e)  -> blocks on the unique index (W1's uncommitted row)
W1: apply_local_side_effects; COMMIT
W2: unblocks -> claim returns FALSE -> guard_row_visible_in_tenant(e) == TRUE -> ROLLBACK
W1: XACK entry_id   -> 1
W2: XACK entry_id   -> 0 or 1 (XAK-08); no effect is re-run
-- if W1 had rolled back instead: W2's claim inserts, W2 applies the effect and commits
-- the rejected form — SELECT marker; if absent: effect; INSERT marker — lets both workers pass the SELECT
```

### 34.4 Crash after commit, before `XACK`

```text
W1: BEGIN; atomic_claim(e) -> inserted; apply effects; COMMIT       -- durable
W1: ** crash **                                                      -- XACK never sent; E stays pending
(7G redelivery, at a time and by a mechanism 7G defines)
W2: read E -> CLASSIFY -> VALIDATE -> BEGIN; atomic_claim(e) -> FALSE; proven -> ROLLBACK
W2: XACK entry_id                                                    -- duplicate path (§34.2)
-- effect count: exactly one
```

### 34.5 Known-unsubscribed event

```text
CLASSIFY(g, K, fields):
    D-01 entry shape ok; D-02 fmt ok; D-03 env parses; D-04 envelope fields valid
    pair := (env.event_type, env.event_version)
    if env.event_type in A(g, E): return SUBSCRIBED_SUPPORTED or UNSUPPORTED_VERSION -- C-7 / C-8 first; active obligation, not the local handler set
    if env.event_type in X(g, E): return OBLIGATION_RETIRED                           -- C-11; retired interval; held, never acknowledged
    if pair in M and lifecycle(pair) in {ACTIVE, DEPRECATED} and family(pair) == F(K):
        return KNOWN_UNSUBSCRIBED                                                     -- C-9
    return UNSUPPORTED_VERSION or TRANSPORT_ANOMALY                                  -- C-5 / C-6 / C-10
-- for KNOWN_UNSUBSCRIBED: no payload handling, no tenant context, no transaction, no claim
XACK K g entry_id
```

### 34.6 Unsupported version

```text
CLASSIFY -> UNSUPPORTED_VERSION                         -- C-5, C-8 or C-10
-- no upcast attempt, no nearest-version guess, no downcast, no default handler
-- no transaction, no claim, no side effect
observe(UNSUPPORTED_VERSION, group, key, event_type, event_version)   -- no field values
HOLD(entry_id)                                          -- entry stays pending; NO XACK
-- disposition: 7G (HE-7G-7F-02)
```

### 34.7 External durable-intent consumer

```text
-- consumer (event transaction)
BEGIN
  SET LOCAL tenant context
  claimed := atomic_claim(…, e, org)
  if claimed: INSERT durable owner work-intent rows (state PENDING)   -- e.g. webhook_deliveries
COMMIT                                                  -- intent durable
XACK K g entry_id                                       -- after COMMIT, before any external call

-- separate owner worker (not the event consumer; its own state machine and idempotency)
claim one PENDING intent  ->  COMMIT                    -- short transaction
perform external I/O                                    -- no PostgreSQL transaction is open here
record outcome on the intent  ->  COMMIT                -- short transaction
```

### 34.8 Direct idempotent external write (IC-5: CON-01, CON-08)

```text
CLASSIFY, VALIDATE-PAYLOAD, TENANT-GATE
authoritative pre-check in a short read transaction, then END that transaction   -- CON-08 only
for each required absolute write w:                     -- no PostgreSQL transaction is open
    result := external_absolute_write(w)                -- SET key / DELETE exact object key
    if result is not definitive success (or definitive "already in target state"):
        HOLD(entry_id, HANDLER_FAILED); return          -- NO XACK; writes done so far are harmless
XACK K g entry_id                                       -- only after every write succeeded
```

### 34.9 Handler-contract admission and applicable obligation

```text
ADMIT(build, g):                                        -- before the first XREADGROUP; HCG-02, HCG-03
    rec := read handler-contract record of g            -- authoritative; never the compiled handler set
    if rec is missing or unreadable: return NOT_ADMITTED               -- generation 1 is a record too; no bootstrap mode (HCG-07)
    if rec.state != OPEN: return NOT_ADMITTED
    if not (rec.H_required is a subset of H_capable(build, g)): return NOT_ADMITTED   -- active + draining; incapable build never reads
    register(member, g, rec.generation)
    rec2 := read handler-contract record of g
    if rec2.state != OPEN or rec2.generation != rec.generation:
        deregister(member, g); return NOT_ADMITTED
    return ADMITTED(rec.generation, rec.intervals)

BEFORE-EACH-READ(member, g, admitted):                  -- HCG-04
    rec := read handler-contract record of g
    if rec is unreadable or rec.state != OPEN or rec.generation != admitted.generation:
        stop reading; bring in-flight entries to a safe boundary; deregister(member, g)

APPLICABLE-OBLIGATION(admitted, K, entry_id, event_id, event_type): -- A(g, E); HCG-05
    if K is not onboarded in admitted.intervals: return KEY-NOT-ONBOARDED          -- row C-12; held; never unsubscribed (TKO-02)
    o := CANONICAL-ORIGIN(admitted.group, event_id, event_type)                  -- O(g, event_id, event_type): at most one record (HCG-28, HCG-29)
    if o exists and o.origin_obligation == NOT_OWED: return { }                   -- historically not owed; never by the Redis ID, the key or a later cutover
    if o exists and o.origin_obligation == OWED: return HISTORICAL-OWED(o)        -- { event_type } while the interval open in o.origin_contract_generation is not RETIRED; else OBLIGATION_RETIRED (HCG-30)
    return { t : some interval I of (t, K) in admitted.intervals has
                 I.status != RETIRED
                 and entry_id > I.active_from
                 and (I.inactive_after is NULL or entry_id <= I.inactive_after) }
-- a type whose RETIRED interval contains entry_id is in X(g, E): OBLIGATION_RETIRED, held (row C-11)
```

### 34.10 Finite-evidence consumer under the retention barrier (CON-06 shown)

```text
CON-06-ADAPTER(evt, org):
    rows := DERIVE-ROWS(evt)                            -- pure; deterministic key and occurred_at (IO-7F-16)
    BEGIN
    SET LOCAL tenant context := org
    ACQUIRE-SHARED-RETENTION-BARRIER(billing.usage_events)        -- RET-7F-11; waits for a running retirement
    t := clock_timestamp()                              -- read after the barrier; never the transaction start time
    if not INSIDE-EVIDENCE-HORIZON(rows.occurred_at, t):          -- RET-7F-08; any doubt is outside
        ROLLBACK
        return BEYOND_HORIZON                           -- HELD; no INSERT was issued; no XACK; Billing reconciliation
    INSERT rows ON CONFLICT (organization_id, source_system, source_event_id, occurred_at) DO NOTHING
    COMMIT                                              -- releases the barrier
    return DURABLY_COMMITTED or ALREADY_COMMITTED       -- then, and only then, XACK (§34.1)
-- the S3 archive is never read here
-- CON-04, CON-07 (ingest and each projection) and CON-10 use the same shape with their own barrier and guard statement
```

### 34.11 Evidence retirement under the retention barrier

```text
RETIRE-EVIDENCE(store):                                 -- ledger cleanup or partition retirement; RET-7F-12
    BEGIN
    ACQUIRE-EXCLUSIVE-RETENTION-BARRIER(store)          -- waits until every admitted handler transaction has ended
    t := clock_timestamp()                              -- read after the barrier
    eligible := evidence of store with evidence_time < t - GUARANTEED-HORIZON(store)   -- re-checked now, not earlier
    retire eligible                                     -- DELETE rows; DETACH or DROP only a wholly eligible partition
    COMMIT                                              -- releases the barrier
```

### 34.12 Handler-obligation cutover with publication fence

```text
CUTOVER(g, change):                                     -- HCG-08; the order is normative
    prepare; capability rollout; capability proof       -- CUT-1 … CUT-3
    close(g); wait until registrations(g) is empty      -- CUT-4, CUT-5
    for each affected type t: ESTABLISH-PUBLICATION-FENCE(t)           -- CUT-5a; PostgreSQL authority
    for each affected type t: wait until OUTBOX-DRAINED(t)             -- CUT-5b, CUT-5c; may be abandoned here (HCG-25)
    for each affected type t: CLOSE-PUBLICATION-ADMISSION(t)           -- CUT-5d
    wait until PUBLICATION-ATTEMPTS(affected types) is empty           -- CUT-5e; abandon if it cannot be proven
    re-check OUTBOX-DRAINED(t) for each affected type; ASSIGN-CANONICAL-ORIGIN(g, affected types)   -- CUT-5f
    for each affected key K: B(K) := last-generated-id of XINFO STREAM K   -- CUT-6; never the group's last-delivered-id
    write the next generation with its intervals at B(K)               -- CUT-7; one atomic write
    boundary-stability check; open(g)                   -- CUT-8
    for each affected type t: RELEASE-PUBLICATION-FENCE(t)             -- CUT-8a; producers resume under the new contract
    for each affected type t: OPEN-PUBLICATION-ADMISSION(t)            -- CUT-8a

OUTBOX-DRAINED(t):                                      -- HCG-22; reads PostgreSQL outbox state only
    rows := rows of audit.domain_event_outbox with event_type = t and status != PUBLISHED
    return no row in rows is PENDING
       and no row in rows is CLAIMED                    -- a row whose last outcome was UNKNOWN is still CLAIMED or PENDING
       and every FAILED row in rows has a recorded 7G disposition

ASSIGN-CANONICAL-ORIGIN(g, affected types):             -- CUT-5f; HCG-28, HCG-29; group closed, before the switch
    for each outbox row r of an affected type, whatever its status:
        if CANONICAL-ORIGIN(g, r.event_id, r.event_type) exists: continue            -- preserved unchanged; never overwritten
        insert O(g, r.event_id, r.event_type) with
            origin_contract_generation := the generation in force before the switch
            origin_obligation := OWED if r.event_type is in H_active(g) before the switch else NOT_OWED

RELAY-TRANSPORT-ATTEMPT(row of type t):                 -- HCG-26; no PostgreSQL transaction is open anywhere in this procedure
    if PUBLICATION-ADMISSION(t) != OPEN: defer the row per 7D; return
    REGISTER-ATTEMPT(relay, t, connection)
    if PUBLICATION-ADMISSION(t) != OPEN: DEREGISTER-ATTEMPT; defer the row per 7D; return
    transport write on that connection                  -- 7E durable acceptance, unchanged
    when the attempt is in a terminal local transport state: DEREGISTER-ATTEMPT   -- replies received, or connection closed and gone from the primary

PRODUCER-TRANSACTION(t):                                -- HCG-21; every producer of an affected type
    BEGIN
    ACQUIRE-SHARED-PUBLICATION-FENCE(t)
    if FENCE-STATE(t) == FENCED: ROLLBACK; wait or fail per the owner contract   -- never commit without the outbox row
    business state change
    INSERT the audit.domain_event_outbox row of type t
    COMMIT
```

### 34.13 Topology-generation key onboarding

```text
ONBOARD-KEY(K_new, family):                             -- TKO-05; the order is normative
    7E provisions K_new and its registered groups       -- TK-1; nobody reads or writes K_new yet
    for each group g subscribed to family:
        take CHANGE-IN-PROGRESS(g)                      -- TK-2; excludes a handler-obligation cutover of g
        close(g); wait until registrations(g) is empty  -- TK-3
        write next generation: add K_new with one OPEN interval (beginning of key, NULL) per type of H_active(g) in family
                                                        -- TK-4; no interval for a DRAINING or RETIRED type
        open(g)                                         -- TK-5
    prove every subscribed group lists K_new with complete intervals and every member reads it   -- TK-6
    release CHANGE-IN-PROGRESS markers
    7E enables relays for the new generation            -- TK-7; never earlier
```

---

## 35. Consumer-Specific Activation Classification

This section separates two things. **Domain-specific readiness** (§35.2) says whether the owning context's own handler primitive is sufficient. **Common event-platform go-live prerequisites** (§35.1) apply to every durable consumer regardless of its domain readiness. A consumer is production-activatable only when its §35.2 row is satisfied **and** every prerequisite of §35.1 is delivered; a domain-readiness label never means "deployable" by itself.

### 35.1 Common event-platform go-live prerequisites

| Prerequisite | Obligations | Applies to | Blocks |
|---|---|---|---|
| Dispatcher, read loop, registry, adapter contract, processing transaction, `XACK` adapter | IO-7F-01 … IO-7F-06 | Every durable consumer | Go-live |
| Handler-contract record with its generation-1 content, admission, registration and revalidation | IO-7F-31 (HCG-07) | Every durable consumer: no durable worker issues its first `XREADGROUP` without its group's generation-1 record | Go-live |
| Classification tests, startup and shutdown checks, Redis command conformance | IO-7F-24, IO-7F-26, IO-7F-30 | Every durable consumer | Go-live |
| Per-consumer conformance, race, crash and out-of-order tests | IO-7F-07 … IO-7F-10 | Each durable consumer | That consumer's go-live |
| Evidence-horizon gate and retention barrier | IO-7F-33, IO-7F-35 | CON-04, CON-06, CON-07, and CON-10 once its claim exists | That consumer's go-live |
| 7G redelivery integration, 7J telemetry, 7I worker security | IO-7F-27, IO-7F-28, IO-7F-29 | Every durable consumer | Production operation |
| Closed-group cutover with publication fence, relay publication admission and quiescence, canonical origin provenance | IO-7F-32, IO-7F-36 | Any group whose handler obligation is to change | The first handler-obligation change (not initial go-live) |
| Topology-generation key onboarding | IO-7F-37 | Any family that gets a new topology generation | The first topology-generation change (not initial go-live) |

### 35.2 Domain-specific readiness

Classes: **READY** — the domain logic is implementable with existing frozen primitives (production activation still waits for §35.1); **IMPLEMENTATION OBLIGATION** — no schema change, but a named handler obligation must be met before go-live; **GOVERNED MIGRATION REQUIRED** — a physical guard is absent and must be added by a governed Phase-5 migration before activation; **UPSTREAM CONTROLLED RECONCILIATION REQUIRED** — a frozen upstream text must be reconciled by its owner before activation. A consumer is never called ready because a generic pattern exists.

| CON | Domain-specific readiness | What is missing | Blocking item(s), in addition to §35.1 |
|---|---|---|---|
| CON-01 | IMPLEMENTATION OBLIGATION | Handler obligation only: fixed TTL, acknowledge after every write, platform-scoped handling | IO-7F-11 |
| CON-02 | IMPLEMENTATION OBLIGATION | The atomic conflict form must be used; the pre-check alone is not accepted | IO-7F-12 |
| CON-03 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | 6C describes an unconditional pointer overwrite; lock-then-recompute is required | IO-7F-13; CNF-7F-02 |
| CON-04 | IMPLEMENTATION OBLIGATION | Existing ledger is sufficient; handler obligations (tenant-checked duplicate proof, maximum merge, recomputed qualification, self-sufficient handlers); evidence-horizon gate and retention barrier | IO-7F-14, IO-7F-33, IO-7F-35 |
| CON-05 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | Qualification write-back is order-dependent in 6H; orphaned-outcome shortcut; state-derived follow-up | IO-7F-15; CNF-7F-03, CNF-7F-04, CNF-7F-09 |
| CON-06 | Domain logic READY for `call.ended`, `document.indexed`, `campaign.contact.call_attempted`, `workflow.execution.completed`, on the finite-evidence condition that the evidence-horizon gate and the retention barrier are in place (RET-7F-08, RET-7F-09, RET-7F-11); GOVERNED MIGRATION REQUIRED for `conversation.completed` | For all five types: the handler is a safe path only inside the guaranteed 90-day hot evidence horizon; beyond it events are held for Billing-owned reconciliation. For EV-079 additionally: the durable accumulator and the finalization guard do not exist yet (7B IO-7B-15, IO-7B-16), and 6K still names the superseded source (IO-7B-02) | IO-7F-16, IO-7F-33, IO-7F-34, IO-7F-35; IO-7B-02, IO-7B-15, IO-7B-16, IO-7B-17 |
| CON-07 | IMPLEMENTATION OBLIGATION | Projection appliers for `agent_utilization_hourly` and `lead_funnel_daily`; projection loop from `PENDING` rows; registry rows for consumed pairs (IO-7C-11); evidence-horizon gate and retention barrier | IO-7F-17, IO-7F-33, IO-7F-35; IO-7C-06, IO-7C-11 |
| CON-08 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | No durable trusted source of the object key under the frozen 7C payload | IO-7F-18; CNF-7F-05 (its remedy may itself need a governed migration or a governed 7C change) |
| CON-09 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | Recount instead of increment / decrement; counted predicate to be bound by 6F | IO-7F-19; CNF-7F-06 |
| CON-10 | GOVERNED MIGRATION REQUIRED | No physical idempotency guard for delivery creation; evidence-horizon gate and retention barrier once the claim exists | IO-7F-20, IO-7F-21, IO-7F-33, IO-7F-35 |
| CON-11 | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | Trigger wording conflict between 7B TSK-03 and 6H §13.1 | IO-7F-22; CNF-7F-07 |
| CON-07 SIGNAL part | IMPLEMENTATION OBLIGATION | `NOACK` reader; Analytics registration of `tool_execution.started` (IO-7C-11) | IO-7F-23 |

No migration is created by 7F and no migration number is assigned. Migration 113 does not exist.

These classifications hold for handler-contract generation 1 (§10.4), whose record is itself a go-live prerequisite (§35.1, IO-7F-31). Any later change of a group's handler obligation is a closed-group cutover with a publication fence (HCG-08, HCG-20) and is blocked until IO-7F-32 is delivered (HCG-07).

---

## 36. Downstream Handoffs

7E already issued `HE-7G-01` … `HE-7G-05`, `HE-7I-01` … `HE-7I-04` and `HE-7K-01` … `HE-7K-08`. The handoffs issued by 7F carry the infix `7F` so that identifiers stay unique.

### 36.1 To 7G (retry, DLQ, poison, replay)

| ID | 7G receives |
|---|---|
| HE-7G-7F-01 | **The safety contract.** Any legitimate redelivery of a valid event can be attempted again, by any member, at any time inside the guard-evidence horizon, without duplicating the protected business effect (CPM-10, §19, §20). 7G may therefore choose idle time, reclaim cadence and redelivery mechanism (`XAUTOCLAIM`, `XCLAIM`, own-PEL re-read) freely. |
| HE-7G-7F-02 | **`HELD` entries.** `TRANSPORT_ANOMALY`, `INVALID_CONTRACT`, `UNSUPPORTED_VERSION` and `HANDLER_FAILED` entries stay pending and unacknowledged (§24, XAK-06). 7G owns their classification as transient or poison, attempt limits, delay, parking, dead-lettering and operator handling. 7F never acknowledges one to remove it. |
| HE-7G-7F-03 | **Same pipeline.** A redelivered or reclaimed entry enters at D-01 and is processed under the same rules; 7G adds no bypass around validation or the guard. |
| HE-7G-7F-04 | **Pinning.** A `HELD` entry pins the stream's trim watermark (7E TRM-02). The mechanism that eventually releases it (for example parking with a durable record, then acknowledgement) is 7G's and must not lose the event. |
| HE-7G-7F-05 | **Evidence horizon, per target consumer.** A raw replay, backfill or redelivery window is capped by the guaranteed guard-evidence horizon of **each target consumer** in §31.2, never by one global value: CON-04 30 days; CON-06 and CON-07 90 days; CON-10 as set by its migration; the RS-STATE consumers have no cap. An event beyond a target's horizon MUST NOT be sent through that consumer's normal handler; it goes to the owner's rebuild or reconciliation mode (RET-7F-04, RET-7F-08). 7G owns replay mechanics, authorization, rate and any narrower window. |
| HE-7G-7F-06 | **Replay targets.** Every current durable consumer is replay-safe under §28 once its §35 blocker is cleared. CON-10 is not a safe replay target before IO-7F-21. Webhook replay through `fn_replay_webhook_delivery` remains a separate, deliberate 6J action (7A RPL-03). |
| HE-7G-7F-07 | **Unknown commit and ambiguous guard state** are reported as `HANDLER_FAILED` (TXA-09, EID-06); they are safe to redeliver. |
| HE-7G-7F-08 | **Backfill for a changed handler obligation.** When a type is added to a group, or an obligation is moved to a new group, entries at or below the activation boundary are not owed (HCG-10, HCG-14). Whether they are backfilled, from which position and by which mechanism is a 7G decision; it is never implicit. 7G also owns the terminal disposition of pending entries, and any no-redelivery contract, that the retirement of a historical obligation relies on (HCG-18). |
| HE-7G-7F-09 | **Billing beyond-horizon entries.** A CON-06 entry classified `BEYOND_HORIZON` stays pending. 7G owns the mechanics that hand it to the Billing-owned reconciliation path and release the entry afterwards without losing it; Billing owns the financial decision (RET-7F-09). |
| HE-7G-7F-10 | **Canonical original obligation of replayed events.** Every replayable `FAILED` outbox row, and every retained `PUBLISHED` row that 7G / 7K may deliberately select for disaster or repair replay (7D CLN-08), keeps its **original handler-contract side**. The semantic requirement is 7F's; storage and tooling are 7G's. 7G retains and resolves, for each logical group, the canonical mapping `(group, event_id, event_type)` → `origin_contract_generation` → `origin_obligation` (HCG-28) — not merely "this event was on the pre-side of cutover C". The retained provenance is durable and sufficient to answer "did group `g` owe `event_id` E when it was produced, and under which contract generation?". A replay uses that canonical value regardless of: the Redis ID assigned during replay; any later handler-contract cutover; the topology generation it is replayed onto; and the current `H_active(g)`. It is never classified by its new stream position alone, and an existing origin record is never overwritten by a replay or by a later cutover (HCG-29). 7G keeps a record for as long as any replay source can still deliver the event to the group and records when none can, which is the only condition for retiring it (HCG-31). Before a cutover, 7G either resolves each pre-fence `FAILED` row or leaves it under this provenance. Without the origin provenance the handler-obligation cutover stays blocked (HCG-22 d, HCG-25, HCG-28), and an event whose origin cannot be determined is not replayed to the group through the normal handler. |

### 36.2 To 7H (external delivery)

| ID | 7H receives |
|---|---|
| HE-7H-7F-01 | CON-10's boundary: 7F defines durable acceptance into `webhooks.webhook_deliveries` only. Delivery attempts, retry, signing, egress control, topic payload rendering and the WHT-01 / WHT-02 source mapping are 7H's. |
| HE-7H-7F-02 | CON-08's provider semantics: what "deleted" and "definitively absent" mean per storage provider, including versioned storage. |

### 36.3 To 7I (security / privacy)

| ID | 7I receives |
|---|---|
| HE-7I-7F-01 | Worker database roles and the per-entry tenant-context rule (TEN-7F-03) for final permission design. |
| HE-7I-7F-02 | Consumer Redis permissions: `XREADGROUP` and `XACK` on subscribed keys only in the normal path; no `XGROUP`, `XDEL`, `XTRIM` or `XADD` (CPM-09). |
| HE-7I-7F-03 | Observation content rules: no `env`, no field values, safe identifiers only (DSQ-06, NAK-04). |
| HE-7I-7F-04 | Classification of any internal cleanup reference chosen to resolve CNF-7F-05. |

### 36.4 To 7J (observability) — semantic events only, no names or thresholds

Per group and key: entries read; classification counts by class (C-1 … C-12); known-unsubscribed acknowledgements; held entries by class; handler outcomes (`DURABLY_COMMITTED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`, `HANDLER_FAILED`); duplicate rate; ambiguous-guard and unknown-commit occurrences; tenant-mismatch occurrences; `XACK` results including zero results and errors; time from delivery to durable commit and to acknowledgement; in-flight count; unsupported-version alerts (7C UV-08); startup-gate refusals (VER-7F-05); handler-contract admission refusals, revalidation stops, cutover state changes and registrations (§10.4); beyond-horizon classifications by consumer (RET-7F-08); retention-barrier waits and retirement runs per evidence store (RET-7F-11, RET-7F-12); draining intervals and their retirement (HCG-18); publication-fence establishment and release, size and age of a pre-fence set, and abandoned cutovers (HCG-21 … HCG-25); publication-admission state, registered publication attempts and quiescence waits (HCG-26, HCG-27); number of canonical origin records and classifications made from them, by origin obligation (HCG-28 … HCG-31); key onboarding steps and entries held as key-not-onboarded (§10.5); entries held as `OBLIGATION_RETIRED`; SIGNAL entries read, dropped by reason, ingested; beyond-horizon events. HE-7J-7F-01 hands this list to 7J, which owns names, labels, cardinality and thresholds.

### 36.5 To 7K (capacity)

| ID | 7K receives |
|---|---|
| HE-7K-7F-01 | Read-loop numbers: `COUNT`, `BLOCK`, admission bound, per-key concurrency, worker counts (RDL-07, RDL-08, RDL-12). Correctness holds for any value. |
| HE-7K-7F-02 | Drain period for shutdown (SHD-02) and catch-up sizing after an outage. |
| HE-7K-7F-03 | Lock contention of the lock-then-recompute consumers (CON-03, CON-09) under burst load on one organization or knowledge base. |
| HE-7K-7F-04 | Analytics projection-loop cadence and the stale-job reaper referenced by CON-11. |
| HE-7K-7F-05 | Unavailability of a group during a closed-group cutover (CUT-4 … CUT-8): lag grows and entries stay retained (7E TRM-08); sizing and scheduling of the window are 7K's. |
| HE-7K-7F-06 | Node clock discipline on the event-transport cluster, which the boundary-stability rule HCG-17 assumes; and the duration for which an exclusive retention barrier pauses the handlers of one evidence store during cleanup or partition retirement (RET-7F-11). |
| HE-7K-7F-07 | The duration for which a publication fence pauses the producers of an affected type during a cutover (CUT-5a … CUT-8a), relay drain time under load, and the scheduling of such windows. |
| HE-7K-7F-08 | **Combined topology-generation lifecycle.** 7E LCY-07 step 1 is not sufficient by itself once handler obligations are per key. 7E / 7K lifecycle tooling and the 7F handler-contract tooling execute the combined order TK-1 … TK-9 (§10.5): provision; serialize; close; write per-key intervals; open; admission proof; only then enable new-generation relays; later retire old-key intervals after 7E has retired the keys. 7E is not edited; the reconciliation is CNF-7F-14. |

### 36.6 To 7L (final reconciliation)

| ID | 7L receives |
|---|---|
| HE-7L-7F-01 | CNF-7F-01 (the 7B ordering wording; 7E CNF-7E-10, IO-7E-25) — still open. |
| HE-7L-7F-02 | CNF-7F-02 … CNF-7F-09: the controlled reconciliations of 6C, 6D / 7C, 6F, 6H and 7B listed in §41. |
| HE-7L-7F-03 | The activation register of §35 as the consumer go-live checklist. |

---

## 37. ADR Register

Facts already decided upstream (stream families, group fan-out, entry format, ordering guarantee, envelope, upcasting rules, EV-079 finalization) are referenced, not re-decided.

| ADR | Decision | Alternatives rejected | Rules |
|---|---|---|---|
| ADR-7F-01 | **Durable consumer processing model:** read one key → classify → validate → one owner transaction per entry → commit → `XACK`; at-least-once plus idempotent effects, never exactly-once | Batch transaction over several entries; processing inside the read; any exactly-once construction; XA or two-phase commit | CPM-01 … CPM-10, §12, §34 |
| ADR-7F-02 | **Inbox / dedup architecture (7A DD-13):** no shared inbox; domain-owned idempotency; existing ledgers preserved; one owner-local guard added for CON-10 | Universal shared inbox (B); shared receipt layer plus owner guards (C) — both eliminated by frozen 7B §9, 7A IDM-03, IDM-06 | INB-01 … INB-06 |
| ADR-7F-03 | **Acknowledge after durable success**, never before | `XACK` on read; `XACK` before commit; `XACK` to drop a failed entry | XAK-01 … XAK-12, CRI-01 |
| ADR-7F-04 | **Same-transaction local idempotency:** guard and effect commit together | Marker first; effect first; check-then-act; cache as guard | TXA-01 … TXA-12, IDT-01 … IDT-03 |
| ADR-7F-05 | **Event-id dedup and business-key idempotency are separate concerns**; no generic business-key formula; no invented consumer constraint | One generic key for all contexts; event-id ledger as the only protection | EID-01 … EID-08, BKG-01 … BKG-04 |
| ADR-7F-06 | **No per-aggregate ordering dependency:** each effect proven commutative, monotonic, guarded, append-only or recomputed; no reorder buffer; no delay or timestamp ordering | Relying on partition affinity; sorting by `occurred_at`; entry-ID sequencing; sleeping until the other event arrives | ORD-7F-01 … ORD-7F-08, §22 |
| ADR-7F-07 | **Known-unsubscribed entries are acknowledged after positive classification**; nothing else is | Leaving them pending; acknowledging anything "not for me"; validating foreign payloads | KUN-01 … KUN-08, DSQ-01, DSQ-02 |
| ADR-7F-08 | **Cluster-safe per-key read loop** on Redis 7.2 primitives, multiplexed by the application | Multi-key cross-slot reads; `NOACK` on durable groups (prohibited); post-7.2 commands | RDL-01 … RDL-14, §11.2 |
| ADR-7F-09 | **Multi-handler rule:** all mandatory sub-effects atomic or converted to durable intents before `XACK`; completion derived from durable state; independent lifecycles need separate groups | Acknowledging after the first handler; in-memory fan-out after acknowledgement; faked independence inside one group | MHO-01 … MHO-06 |
| ADR-7F-10 | **SIGNAL consumer:** `NOACK` read, no `XACK`, drop-and-count on failure, Analytics dedup key from the signal `event_id`; never Billing-authoritative | Pending-entry based SIGNAL processing; durable promotion; retries from the stream | SIG-7F-01 … SIG-7F-08 |
| ADR-7F-11 | **External side effects:** durable local intent then separate worker; direct external write only when absolute and key-addressed, with the stream entry as the intent | Open transaction around a network call; inbox marker then external call; creating external calls from a handler | EXT-01 … EXT-06 |
| ADR-7F-12 | **Versioning and idempotency:** validate the original version first; identity is the original `event_id`; mixed builds controlled by a group admission gate | Idempotency before validation; upcast-derived identity; routing by worker capability; downcast | VER-7F-01 … VER-7F-08 |
| ADR-7F-13 | **Authoritative recomputation by lock-then-recompute** for derived current-value fields (CON-03, CON-09, qualification) | Copying the event's value; increment / decrement deltas; single-statement recompute from a pre-lock snapshot | TXA-05, ORD-7F-06 |
| ADR-7F-14 | **Tenant-checked duplicate proof** where a ledger key lacks the tenant | Trusting a bare "already claimed" result | EID-06, TEN-7F-05 |
| ADR-7F-15 | **A zero `XACK` result is final for the delivery** and never re-runs an effect | Re-processing to "make the acknowledgement work" | XAK-08 … XAK-10 |
| ADR-7F-16 | **Handler-contract generations with a closed-group cutover:** the active obligation `H_active(g)` is authoritative and separate from build capability; a worker reads only when capable of all of it; obligations are per-type, per-key position intervals with a lower and an upper bound; classification uses the interval that contains the entry's position; a change is made only with the group closed and quiesced, behind a producer / outbox publication fence that is drained first, after relay publication quiescence, with one immutable canonical origin obligation per group and event assigned for later replays, and then at a boundary read from the stream itself; the generation-1 record is a prerequisite of the first read; a removed obligation keeps draining until it is provably retired | Deciding known-unsubscribed from the local handler set; rolling a handler change through a live group; relying on the manifest or version gates; implicit backfill; overlapping old and new groups; the group's delivery position as the cutover boundary; a Redis-only boundary without an outbox fence; treating `PUBLISHED` as proof that no late transport write exists; classifying a replay by its new Redis ID; re-recording every retained event as "pre" at each cutover; latest-cutover-wins provenance; an envelope contract-generation marker in V1; a static bootstrap mode for generation 1; deleting a removed handler at the cutover | HCG-01 … HCG-31, CUT-1 … CUT-9, DSQ-07, KUN-09 |
| ADR-7F-17 | **Finite idempotency evidence is gated:** every consumer whose evidence can be retired (ledger or retention-bounded effect rows) processes an event through its normal handler only inside the guaranteed evidence horizon; beyond it the event is held for the owner's reconciliation; Billing is RS-RETENTION-BOUNDED | Treating retained effect rows as permanent evidence; treating the S3 archive as a dedup guard (it is not one); a new Billing tombstone table in this phase | RET-7F-01 … RET-7F-10, §31.2 |
| ADR-7F-18 | **Retention barrier:** a horizon check alone is not atomic with evidence retirement; handler transactions take an owner-local PostgreSQL advisory-lock barrier shared and re-check the horizon after it, and every retirement takes it exclusive and re-checks eligibility after it | A standalone time check; relying on cleanup timing; lengthening or shortening frozen retention values to hide the race; a new table | RET-7F-11 … RET-7F-15, §34.10, §34.11 |
| ADR-7F-19 | **Topology-generation key onboarding:** a new-generation key gets complete per-key intervals for the active types, and is admitted to the consumers' read set, before any relay may publish to it; draining and retired types are not reopened; onboarding and handler-obligation cutovers are mutually exclusive per group | Relying on 7E LCY-07 step 1 and RDL-14 alone; implicit "beginning of key" intervals; concurrent merge of a cutover and a topology change | TKO-01 … TKO-10, TK-1 … TK-9, C-12 |

ADR count: **19**.

---

## 38. Owner Decision Register

| ID | Question | Status |
|---|---|---|
| OD-7B-01, OD-7B-02 | EV-079 as the Billing source; single-path accounting finalization | Preserved; not reopened |
| OD-7C-01 … OD-7C-07 | Versioning, upcasting, schema location, correlation, EV-079 usage form, SIGNAL envelope, EV-014 members | Preserved; not reopened |
| OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B | Outbox relay decisions | Preserved; not reopened |
| OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B | Dedicated cluster; `WAITAOF` acceptance; partitioning | Preserved; not reopened |
| (candidate) OD-7F-01 — shared inbox versus domain-owned idempotency | Evaluated in §14. **Not raised:** frozen 7B §9, 7A IDM-03 and 7A IDM-06 eliminate patterns B and C, leaving one compatible design (AUTH-7F-03, INB-02). It is recorded here so that the closure is visible and can be challenged by the independent review. | Closed technically; no owner decision outstanding |

Open owner decisions raised by 7F: **0**.

The upstream reconciliations of §41 are not 7F owner decisions. Each belongs to the governed-change process of the document that owns the concern (6C, 6D / 7C, 6F, 6H, 7B) and blocks only the activation of the named consumer (§35). Where such a reconciliation offers its owner several options (for example the remedy of CNF-7F-05, or the terminal-status function of CNF-7F-03), 7F selects none of them; it fixes only the safety property the chosen option must satisfy.

---

## 39. Implementation Obligations

Design only; 7F implements none. Every obligation has an owner, a dependency and an activation condition ("blocks" names the step that may not go live without it).

| IO | Obligation | Owner | Dependency | Activation condition |
|---|---|---|---|---|
| IO-7F-01 | Shared consumer dispatcher library: steps D-01 … D-10, the §12.2 decision table, semantic observations | Platform event infrastructure | 7C IO-7C-02, IO-7C-05 | Blocks every consumer go-live |
| IO-7F-02 | Cluster-safe per-key read multiplexer (RDL-01 … RDL-14), two-generation reads | Platform event infrastructure | 7E IO-7E-02, IO-7E-08 | Blocks every consumer go-live |
| IO-7F-03 | Code-owned subscription registry equal to §10; CI check against the 7E route registry and the 7C manifest; no pattern entries | Platform event infrastructure | 7E IO-7E-03, IO-7E-04; 7C IO-7C-03 | Blocks every consumer go-live |
| IO-7F-04 | Owner-local idempotency adapter contract: one call per entry returning `DURABLY_COMMITTED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`, `BEYOND_HORIZON` or `HANDLER_FAILED` | Platform event infrastructure; each consuming context | IO-7F-01 | Blocks every consumer go-live |
| IO-7F-05 | Durable processing transaction helper: one transaction per entry, transaction-local tenant context, `READ COMMITTED`, no Redis or external call inside (TXA-01 … TXA-12) | Platform event infrastructure | IO-7F-04 | Blocks every consumer go-live |
| IO-7F-06 | `XACK` adapter implementing XAK-01 … XAK-12, including the zero result and the lost reply | Platform event infrastructure | IO-7F-01 | Blocks every consumer go-live |
| IO-7F-07 | Per-consumer conformance tests reproducing each §28 card | Each consuming context | IO-7F-01 … IO-7F-06 | Blocks that consumer's go-live |
| IO-7F-08 | Concurrent-duplicate race tests on two real connections per consumer (§19, §34.3) | Each consuming context | IO-7F-07 | Blocks that consumer's go-live |
| IO-7F-09 | Crash-point tests CRP-01 … CRP-13, with the crash-after-commit-before-`XACK` case mandatory for every consumer | Each consuming context | IO-7F-07 | Blocks that consumer's go-live |
| IO-7F-10 | Out-of-order tests for every row of §22, including the adversarial case stated there | Each consuming context | IO-7F-07 | Blocks that consumer's go-live |
| IO-7F-11 | CON-01 handler obligations (§28.2) | Identity | IO-7F-01 | Blocks CON-01 go-live |
| IO-7F-12 | CON-02 atomic conflict-form seeding (§28.3) | Compliance | IO-7F-01 | Blocks CON-02 go-live |
| IO-7F-13 | CON-03 lock-then-recompute pointer (§28.4) | Compliance | IO-7F-01; CNF-7F-02 | Blocks CON-03 go-live |
| IO-7F-14 | CON-04 handler obligations (§28.5) | CRM | IO-7F-01 | Blocks CON-04 go-live |
| IO-7F-15 | CON-05 state-derived completion, campaign-origin determination, order-independent qualification (§28.6) | Campaign | IO-7F-01; CNF-7F-03, CNF-7F-04, CNF-7F-09 | Blocks CON-05 go-live |
| IO-7F-16 | CON-06 derivation determinism and one transaction per event (§28.7) | Billing | IO-7F-01; for `conversation.completed` also 7B IO-7B-02, IO-7B-15, IO-7B-16, IO-7B-17 | Blocks CON-06 go-live; the EV-079 handler additionally waits for the 7B obligations |
| IO-7F-17 | CON-07 adapter, projection loop from `PENDING` ledger rows, outstanding projection appliers (§28.8) | Analytics | IO-7F-01; 7C IO-7C-06, IO-7C-11 | Blocks CON-07 go-live |
| IO-7F-18 | CON-08 handler: authoritative pre-check, absolute delete, never-reused object keys (§28.9) | Voice | IO-7F-01; CNF-7F-05 | Blocks CON-08 go-live |
| IO-7F-19 | CON-09 lock-then-recount (§28.10) | Knowledge | IO-7F-01; CNF-7F-06 | Blocks CON-09 go-live |
| IO-7F-20 | CON-10 handler: claim and delivery rows in one transaction; claim recorded for zero matches (§28.11) | Integrations | IO-7F-01; IO-7F-21 | Blocks CON-10 go-live |
| IO-7F-21 | **Governed Phase-5 migration (Integrations-owned, `webhooks` schema):** a non-partitioned, primary-key-backed fan-out claim keyed by consumer obligation and `event_id`, carrying `organization_id` under row-level security, with a claim function or statement usable inside the handler transaction, and a retention meeting §31. DDL, names and the migration number are chosen by that migration, not by 7F. | Integrations; Phase-5 governed amendment | — | Blocks CON-10 go-live |
| IO-7F-22 | CON-11 single CAS-guarded start; no start merely because the event arrived (§28.12) | Campaign | IO-7F-01; CNF-7F-07 | Blocks CON-11 go-live |
| IO-7F-23 | SIGNAL consumer: `NOACK` reader, drop-and-count, dedup key per SIG-7F-05 | Analytics | IO-7F-01; 7E IO-7E-06; 7C IO-7C-11 | Blocks SIGNAL projection go-live; does not block any durable consumer |
| IO-7F-24 | Classification tests: every row C-1 … C-10; a known-unsubscribed entry is acknowledged; a malformed, unknown, unsupported, RETIRED or wrong-family entry is never acknowledged | Platform event infrastructure | IO-7F-01 | Blocks every consumer go-live |
| IO-7F-25 | Schema-version rollout compatibility: startup admission gate (VER-7F-05) and the deployment gate before a producer switch (VER-7F-06) | Platform event infrastructure; release engineering | 7C IO-7C-03, IO-7C-05 | Blocks the first BREAKING change |
| IO-7F-26 | Graceful shutdown and startup checks (SHD-01 … SHD-09) | Platform event infrastructure | IO-7F-02 | Blocks every consumer go-live |
| IO-7F-27 | 7G reclaim integration: redelivered and reclaimed entries enter at D-01; `HELD` entries are exposed to 7G's disposition without a 7F-side acknowledgement | Platform event infrastructure; 7G | 7G design | Blocks production operation of durable consumers (an entry held by a crashed member is otherwise never redelivered) |
| IO-7F-28 | 7J telemetry integration for the semantic events of §36.4 | Platform event infrastructure; 7J | 7J design | Blocks production operation |
| IO-7F-29 | 7I worker security integration: database roles, Redis permissions, observation content | Platform; 7I | 7I design | Blocks production operation |
| IO-7F-30 | Redis command conformance check in CI: no command or option introduced after Redis 7.2; no `NOACK` outside the SIGNAL reader; no multi-key read across hash tags; no `XGROUP`, `XDEL`, `XTRIM`, `XADD` in consumer code | Platform event infrastructure | IO-7F-02 | Blocks every consumer go-live |
| IO-7F-31 | Handler-contract record per group and region with the properties of HCG-16, holding per-type, per-key obligation intervals (lower and upper bound, status, history); admission and registration (HCG-02, HCG-03); revalidation before every read (HCG-04); admission against `H_required(g)`; classification against the interval applicable to each entry (HCG-05, HCG-06, HCG-19). The generation-1 record of each of the 11 durable groups is provisioned before that group's first read, with the content HCG-07 lists; a worker without a readable record is never admitted and there is no bootstrap mode. Its physical form is chosen by this obligation under governance; 7F creates no table and no migration; if the chosen form needs a Phase-5 migration, that migration is governed separately and lands before any consumer goes live | Platform event infrastructure | IO-7F-01, IO-7F-02 | Blocks every durable consumer go-live. |
| IO-7F-32 | Closed-group cutover procedure CUT-1 … CUT-9 with its deployment gates, the publication fence in every producer of an affected type (shared fence barrier and durable fence state in the producing transaction; HCG-21), the pre-fence set and outbox drain proof (HCG-22), abandonment (HCG-25), boundary capture from the stream (never the group's delivery position), boundary-stability check (HCG-17) and retirement proof (HCG-18), and tests for: a removal with an empty pending list and undelivered backlog losing nothing; an addition not making the existing backlog owed; a draining handler not deletable; a move with one boundary having neither gap nor overlap; a `PENDING`, a `CLAIMED` and an `UNKNOWN`-outcome pre-cutover outbox row each blocking the boundary capture; a pre-cutover event never appearing above the boundary; an incapable build refused; a stale worker never acknowledging a newly active type; a removed handler never executing; pre-boundary entries not owed; a split without overlapping effects | Platform event infrastructure; release engineering; the consuming context | IO-7F-31; 7E registry change; 7G (HE-7G-7F-08) | Blocks the first change of any group's handler obligation |
| IO-7F-33 | Evidence-horizon gate (RET-7F-08) in every RS-LEDGER and RS-RETENTION-BOUNDED consumer, with tests that an event beyond the horizon issues no guard statement and no insert and is not acknowledged, including the Billing case of a dropped `usage_events` partition | Billing, CRM, Analytics, Integrations | IO-7F-04 | Blocks go-live of CON-04, CON-06, CON-07 and CON-10 |
| IO-7F-34 | Billing-owned reconciliation path for `BEYOND_HORIZON` usage events, able to tell an already-processed archived usage fact from a never-processed one. Designed by Billing; not designed by 7F | Billing; 7G for replay mechanics | 7G design (HE-7G-7F-09) | Blocks any raw replay or backfill into CON-06 beyond the guaranteed hot horizon. Does not block normal CON-06 go-live, because such events are held |
| IO-7F-35 | Retention barrier (RET-7F-11 … RET-7F-15) implemented on **both** sides of every finite evidence store with the same barrier key: the consumer handler transaction (shared, then horizon re-check with `clock_timestamp()`) and the cleanup or partition-retirement worker (exclusive, then eligibility re-check). Tests reproduce both orders of RET-7F-13 on real connections, including a Billing partition retirement racing an insert and a CRM and an Analytics cleanup racing a claim | CRM and its ledger housekeeping; Billing and its `usage_events` partition retirement; Analytics and its ledger cleanup, including the projection loop; Integrations and its claim cleanup | IO-7F-33 | Blocks go-live of CON-04, CON-06 and CON-07, and of CON-10 once its claim exists, until both the consumer and its cleanup or retirement worker implement the same coordination contract |
| IO-7F-36 | Relay publication admission and quiescence (HCG-26, HCG-27): cutover-aware admission checked and registered immediately before every transport write of an affected type, deregistration only at a terminal local transport state, no PostgreSQL transaction across transport I/O; insert-if-absent assignment of canonical origin provenance and its precedence in classification (HCG-28 … HCG-31). Tests: a stale claimant whose attempt started before the cutover cannot append above `B(K)`; an `UNKNOWN` attempt blocks the capture until terminal; a loop paused after its claim is refused on resume; a replayed event is classified by its canonical origin, not by its new ID; an origin record survives an add-then-remove and a remove-then-re-add of its type unchanged; no update path exists | Platform event infrastructure (relay runtime, under the controlled 7D reconciliation CNF-7F-13); 7G for replay provenance | IO-7F-31, IO-7F-32; 7D reconciliation; 7G design (HE-7G-7F-10) | Blocks the first change of any group's handler obligation. Does not block initial go-live |
| IO-7F-37 | Topology-generation key onboarding (TKO-01 … TKO-10, TK-1 … TK-9): per-key interval provisioning in the handler-contract record, key admission in the read loop, the relay-enable gate, the change-in-progress marker, old-key interval retirement. Tests: a new key is neither read nor written before its intervals exist; every active type has an interval; no draining type is reopened; onboarding and a cutover cannot overlap; an old-key interval cannot be retired while the key is live | Platform event infrastructure; 7E / 7K lifecycle tooling | IO-7F-31; 7E LCY-07 tooling; CNF-7F-14 | Blocks the first topology-generation change. Does not block initial go-live |

IO count: **37**.

---

## 40. Deferred Items

| ID | Item | Owner | Reason | Activation condition |
|---|---|---|---|---|
| DEF-7F-01 | PEL idle time, reclaim cadence, redelivery mechanism, attempt limits, poison threshold, retry delay, DLQ, parking | 7G | 7G scope; 7F safety holds for any value (CPM-10) | 7G design |
| DEF-7F-02 | Replay API, authorization, rate limits, windows, future-consumer backfill | 7G | 7G scope | 7G design |
| DEF-7F-03 | Read `COUNT`, `BLOCK`, admission bound, concurrency, worker counts, drain period | 7K | Numbers only | 7K capacity design |
| DEF-7F-04 | Metric names, labels, SLOs, alert thresholds | 7J | 7J scope | 7J design |
| DEF-7F-05 | Final Redis ACLs, worker database roles, payload logging policy | 7I | 7I scope | 7I design |
| DEF-7F-06 | Retention values of any new ledger and the replay horizon values | Owning migration; 7G / 7I | 7F fixes the invariant only (§31) | The governed migration; 7G |
| DEF-7F-07 | Webhook delivery mechanics, provider deletion semantics | 7H | 7H scope | 7H design |
| DEF-7F-08 | Adoption of any post-7.2 Redis consumer command | 7E / 7F governed change | V1 minimum is Redis 7.2 | Transport minimum raised |
| DEF-7F-09 | Consumers for LS-D-AGT, LS-D-INT, CCPU names and unbound Class-D signals | 7B governed change | No current consumer exists | A 7B registry change |
| DEF-7F-10 | A longer-lived Billing receipt or tombstone ledger that would extend CON-06's evidence horizon | Billing; governed Phase-5 design | Not needed for safety: beyond-horizon events are held (RET-7F-09) | A later governed design |
| DEF-7F-11 | Zero-downtime change of a group's handler obligation | 7F / 7E governed change | The closed-group cutover is the V1 mechanism; correctness is primary | A later governed design |
| DEF-7F-12 | A contract-generation marker that travels producer → outbox → Redis, as an alternative to the publication fence | 7C / 7D / 7F governed change | V1 has no such marker; adding one would change the frozen envelope or outbox | A later governed design |

---

## 41. Conflict Register

None is silently resolved. 7F edits no frozen document. "Blocks" names what may not be activated before the owner reconciles the text.

| CNF | Sources | Conflict | 7F position | Status |
|---|---|---|---|---|
| CNF-7F-01 | 7B IO-7B-08 and CR-04 versus 7E ORD-7E-06, ORD-7E-09, ORD-7E-10 (7E CNF-7E-10, IO-7E-25) | 7B says consumers "already assume only per-aggregate ordering" and that ordering is guaranteed "only as far as 7E defines per stream"; the actual guarantee is append order within one key, with no per-aggregate ordering | 7F designs to ORD-7E-09 only (§21). The 7B wording is **not** made correct by 7F's design and stays a conflict. Amendment needed (for the 7B owner, through IO-7E-25): IO-7B-08 — "7E fixes the per-stream guarantee: append order within one physical stream key only; `aggregate_id` partition affinity is not an aggregate sequence; there is no per-aggregate processing-order guarantee"; CR-04 — "A consumer must tolerate out-of-order delivery, including between events of the same aggregate; no ordering is guaranteed beyond append order within one stream key (7E §33)". | **Open — controlled reconciliation; carried to 7L.** Non-blocking for 7F |
| CNF-7F-02 | 6C §12.2 (L626) versus 7A ORD-04, 7E ORD-7E-09 | 6C specifies an unconditional `UPDATE organizations SET compliance_policy_id = :new_id`; a late older event regresses the pointer | Lock-then-recompute from the ACTIVE policy (§28.4) | Open — controlled 6C reconciliation; blocks CON-03 |
| CNF-7F-03 | 6H §24.3 versus 6H §24.1, 6H §16.1, 4D §7.1 L264 – L267, 4D §7.2 | The qualification write-back is guarded by `status = 'ANSWERED'`, but §24.1 never sets `ANSWERED` (it maps `ANSWERED_COMPLETED` to `COMPLETED`); 4D states both that a qualified contact becomes `QUALIFIED` and that `ANSWERED_COMPLETED` is always `COMPLETED` | 7F requires the final status to be one order-independent function of the outcome fact and the qualification fact, evaluated by both handlers (§28.6). 7F does not choose that function: 6H §23.3 ("`status ∈ {QUALIFIED, DISQUALIFIED}`") indicates the candidate "a QUALIFIED or DISQUALIFIED qualification wins over `COMPLETED`", but the choice is Campaign-owner semantics | Open — controlled 6H reconciliation; blocks the CON-05 qualification handler |
| CNF-7F-04 | 6H §24.1 (L1315) versus XAK-04 | 6H commits a no-op when no job is found for the `call_session_id` ("orphaned event"); after 7F that would acknowledge an outcome whose job correlation has merely not been recorded yet | Not-applicable only when the Voice owner record shows a non-campaign call; a campaign call without a correlatable job is not acknowledged (§28.6) | Open — controlled 6H reconciliation; blocks CON-05 |
| CNF-7F-05 | 6D §16.3a versus 7C EV-009 schema and 7C REG-07 | 6D hands the object key to the cleanup worker in the payload field `_internal_cleanup_ref`; the frozen V1 payload has no such field, `storage_ref` is never bound, and the row's `storage_ref` is cleared in the producing transaction | 7F guesses no key. The owner must provide a durable trusted source of the key through a governed change (non-selected examples: a governed 7C payload change with 7I classification; a Voice-owned durable cleanup intent written in the delete transaction; a proven deterministic derivation from retained row fields). Whatever is chosen must satisfy §28.9 | Open — controlled 6D / 7C reconciliation; blocks CON-08 |
| CNF-7F-06 | 6F §9 L293 and 4E §4.1 invariant 4 versus IDM-02, ORD-04 | The count is described as "updated by" consuming the two events (an increment / decrement reading); that is neither idempotent nor order-safe, and `document.indexed` repeats per version | Lock-then-recount (§28.10); the counted predicate is to be bound by 6F | Open — controlled 6F reconciliation; blocks CON-09 |
| CNF-7F-07 | 7B TSK-03 / CON-11 versus 6H §13.1 – §13.2 | 7B names `import.job_created` as the trigger of import processing; 6H has the completion route perform `PENDING → PROCESSING` and enqueue the task after upload verification, while the event is emitted at upload-URL creation | A single CAS-guarded start regardless of trigger (§28.12) | Open — controlled 6H / 7B reconciliation; blocks CON-11 |
| CNF-7F-08 | 6C §7.7, §12.2 ("organization_id from the event payload") versus 7C TEN-C05, 7B CR-03 | Tenant context source | The validated envelope `organization_id`; the payload value must equal it (TEN-7F-02) | Open — documentary 6C reconciliation; non-blocking (the values are equal by schema) |
| CNF-7F-09 | 6H §24.1 comment ("Domain events … published AFTER commit, never inside it") versus 7A PR-02, 7B §14 (Class C is written in the worker's own transaction) | Whether `campaign.contact.call_attempted` is written inside the outcome transaction | The outbox row is inserted inside the transaction (TXA-01); "published after commit" describes relay publication | Open — documentary 6H reconciliation; non-blocking |
| CNF-7F-10 | 6K §21.1, §22.2, §35 versus OD-7B-01 (7B CNF-16, IO-7B-02) | 6K still names `conversation.turn_completed` as the source of the voice usage metrics and describes per-turn rows | 7F follows OD-7B-01: EV-079 only (§28.7). Already recorded upstream; not a new conflict | Open upstream (IO-7B-02); blocks the EV-079 handler |
| CNF-7F-11 | 6C §7.7 point 4 (pre-check "or" unique index) versus TXA-04 | 6C offers a `SELECT`-then-skip pre-check as an idempotency option | Only the unique-index conflict form is the guard (§28.3) | Open — documentary 6C reconciliation; the safe form is already available, so CON-02 is not blocked by the text |
| CNF-7F-12 | 5J §12.2 ("route to historical rebuild queue") versus the frozen schema | No physical rebuild queue exists | Beyond-horizon events are `HELD`; the rebuild is the owner's 5J §12.3 process (RET-7F-04, HE-7G-7F-05) | Open — handed to 7G / Analytics; non-blocking |
| CNF-7F-13 | 7D relay runtime (LSE-08, AMB-01 … AMB-04) versus HCG-26, HCG-27 | Frozen 7D lets a stale or ambiguous transport attempt append a duplicate after the row is `PUBLISHED`, and has no cutover-aware publication admission | 7F requires publication admission and quiescence before a handler-obligation boundary is captured (HCG-26, HCG-27). 7D is not edited and its normal operation is unchanged; the relay runtime addition is to be reconciled by the 7D owner | Open — controlled 7D reconciliation; blocks the first handler-obligation change (IO-7F-36); non-blocking for initial go-live |
| CNF-7F-14 | 7E LCY-07 (generation migration) versus §10.5 | LCY-07 step 1 provisions keys and groups and step 2 deploys relays; nothing provisions per-key handler-contract intervals or gates the relays on them | The combined order TK-1 … TK-9 (TKO-05, TKO-06). 7E is not edited; the lifecycle tooling is to be reconciled by the 7E / 7K owners (HE-7K-7F-08) | Open — controlled 7E / 7K reconciliation; blocks the first topology-generation change (IO-7F-37); non-blocking for initial go-live |

CNF count: **14**. Open: 14. Silently resolved: 0.

---

## 42. Findings Register

### 42.1 Severity

| Severity | Meaning |
|---|---|
| P0 | Catastrophic correctness, security, data-loss or financial-integrity issue |
| P1 | Freeze blocker: a rule that permits a duplicate or lost consumer effect, a false idempotency or ordering claim, an acknowledgement before durable success, a consumer hidden without a real guard, or an owner choice silently made |
| Minor | Non-blocking; explicitly dispositioned |

### 42.2 P1 findings — found by the per-consumer audit and the self-review, all resolved in this document

"Resolved" means the 7F design no longer permits the defect. Where the remedy needs an upstream change, the consumer is blocked in §35 until it lands; 7F does not call that consumer ready.

| ID | Finding | Resolution | Evidence | Status |
|---|---|---|---|---|
| P1-7F-01 | CON-05 qualification write-back depends on arrival order and, as frozen, matches in neither order | Order-independent form mandated; frozen statement not accepted; activation blocked pending CNF-7F-03 | §22, §28.6, §35 | RESOLVED in 7F |
| P1-7F-02 | CON-10 has no physical idempotency guard: a redelivery creates duplicate tenant-visible deliveries | Owner-local fan-out claim required; GOVERNED MIGRATION REQUIRED; consumer not activated before IO-7F-21 | §28.11, §35, F7F-40 | RESOLVED in 7F |
| P1-7F-03 | CON-09 increment / decrement projection is not idempotent and not order-safe | Lock-then-recount | §22, §28.10 | RESOLVED in 7F |
| P1-7F-04 | CON-03 unconditional pointer overwrite regresses on a late older activation | Lock-then-recompute from the ACTIVE policy | §22, §28.4 | RESOLVED in 7F |
| P1-7F-05 | CON-08 has no durable trusted source of the object key under the frozen 7C payload | Gap stated; no key guessed; activation blocked pending CNF-7F-05 | §28.9, §35 | RESOLVED in 7F (blocker recorded) |
| P1-7F-06 | CON-05 retry scheduling is a second transaction; with either acknowledgement timing a crash could leave the contact stuck, because the duplicate path skipped the follow-up | State-derived completion (MHO-04) | §27, §28.6 | RESOLVED in 7F |
| P1-7F-07 | CON-02 pre-check option is check-then-act | Only the unique-index conflict form is accepted | §28.3, TXA-04 | RESOLVED in 7F |
| P1-7F-08 | Self-review: a single-statement recompute can write a stale value after waiting for the row lock | Lock first, recompute in subsequent statements (TXA-05) | §15 | RESOLVED in 7F |
| P1-7F-09 | Self-review: the CRM ledger key has no tenant component; a bare `FALSE` could acknowledge another tenant's event as a duplicate | Tenant-checked duplicate proof (EID-06) | §16, §28.5 | RESOLVED in 7F |
| P1-7F-10 | Self-review: CON-04 handlers were implicitly ordered (contact created by `call.ended`; qualification value copied from the event) | Handler self-sufficiency and recomputed current value (ORD-7F-06, ORD-7F-07) | §21, §22, §28.5 | RESOLVED in 7F |

### 42.3 P1 findings — independent freeze-gate review

| ID | Finding | Resolution | Evidence | Status |
|---|---|---|---|---|
| P1-7F-11 | Mixed handler / subscription contract generations could acknowledge a newly required event as `KNOWN_UNSUBSCRIBED`: classification used the running build's own handler set, and neither the stale-manifest rule nor the version gate covers a change of a group's obligation set | Active obligation `H_active(g)` separated from build capability `H_capable`; admission only when capable of the whole active obligation; classification against the active obligation at the entry's position; closed-group cutover with an explicit boundary for additions, a drain condition for removals, and a plan for splits; no implicit backfill | §10.4 (HCG-01 … HCG-16, CUT-1 … CUT-9), §12.2, DSQ-07, DSQ-08, KUN-01, KUN-08, KUN-09, VER-7F-05, SHD-08, SHD-10, MHO-05, F7F-42 … F7F-46, §34.9, IO-7F-31, IO-7F-32 | RESOLVED |
| P1-7F-12 | Billing `usage_events` retention can remove the physical idempotency evidence before a later raw replay; CON-06 was classed as indefinitely replay-safe and the retention rules covered only formal ledgers | CON-06 reclassified RS-RETENTION-BOUNDED; the invariant extended to every finite evidence mechanism; evidence-horizon gate before any insert; beyond-horizon events held for Billing-owned reconciliation; the S3 archive is not a guard; per-consumer horizon handed to 7G | §31 (RET-7F-01 … RET-7F-10, §31.2), §28.7, §35, F7F-41, §34.10, HE-7G-7F-05, HE-7G-7F-09, IO-7F-33, IO-7F-34 | RESOLVED |
| P1-7F-13 | The handler obligation cutover used the group's delivery position rather than a true stream cutover interval, allowing removal loss and implicit addition backfill: with an empty pending list and undelivered backlog, a removed type's already-published entries became known-unsubscribed, and an added type's already-published entries became owed | Obligations are per-type, per-key position intervals with `active_from` and `inactive_after`; the boundary `B(K)` is the stream's own `last-generated-id`; a removal closes the interval at `B(K)` and keeps it draining; admission requires capability for active and draining obligations; handler code is deleted only after a proven retirement; a move uses one boundary for the old stop and the new start | §10.4 (terms, HCG-05, HCG-10, HCG-11, HCG-14, HCG-17 … HCG-19, CUT-6, CUT-7, CUT-9), §12.2 (C-9 … C-11), KUN-01, §34.9, F7F-47 … F7F-51, IO-7F-31, IO-7F-32 | RESOLVED |
| P1-7F-14 | The finite-evidence admission check was not coordinated with concurrent evidence retirement: cleanup could retire the evidence after the horizon check passed and before the guard ran, so a duplicate could be accepted as novel | Owner-local retention barrier: handler transactions take it shared and evaluate the gate after it with a fresh database clock; every cleanup and partition retirement takes it exclusive and re-checks eligibility after it; proof for both orders; Billing default partition covered; no retention value changed | RET-7F-01, RET-7F-06, RET-7F-08, RET-7F-11 … RET-7F-15, §34.10, §34.11, F7F-52 … F7F-55, IO-7F-35 | RESOLVED |
| P1-7F-15 | The Redis position cutover did not fence already-committed transactional-outbox events, allowing delayed pre-cutover events to cross the consumer obligation boundary: a `PENDING` or `CLAIMED` row published after the boundary would be acknowledged as unsubscribed after a removal, or become owed after an addition | Producer / outbox publication fence under PostgreSQL authority, established before the boundary is captured; finite pre-fence set; drain proof with no `PENDING` or `CLAIMED` row, no `UNKNOWN` outcome treated as settled and every `FAILED` row under a 7G disposition; producers resume only after the group reopens; cutover blocked if a producer cannot be fenced; abandonment before the switch | §10.4 (HCG-08, HCG-10 … HCG-12, HCG-14, HCG-17, HCG-20 … HCG-25, CUT-5a … CUT-5c, CUT-6, CUT-8a), §34.12, F7F-56 … F7F-61, HE-7G-7F-10, IO-7F-32 | RESOLVED |
| P1-7F-16 | The handler-contract record was normative for every read but its implementation obligation did not block generation-1 consumer go-live | One processing model from first go-live: the generation-1 record is provisioned before the first read; no bootstrap mode and no fallback to the compiled registry; IO-7F-31 blocks every durable consumer go-live; domain-specific readiness separated from common event-platform prerequisites | HCG-07, SHD-08, §34.9, §35.1, §35.2, IO-7F-31, F7F-62 | RESOLVED |
| P1-7F-17 | The outbox `PUBLISHED` state did not prove publication quiescence; a stale or ambiguous pre-cutover relay attempt could append above the Redis boundary and acquire the wrong handler obligation | HCG-23 rewritten without the false implication; relay publication admission and a quiescence proof before the boundary is captured; outbox settlement re-checked; pre-cutover provenance recorded and given precedence over the Redis position; HE-7G-7F-10 defines the provenance a replay must carry; abandonment if quiescence cannot be proven; the relay-runtime addition recorded as a controlled 7D reconciliation | HCG-23, HCG-25 … HCG-28, CUT-5d … CUT-5f, CUT-6, CUT-8a, §34.9, §34.12, F7F-63 … F7F-66, HE-7G-7F-10, CNF-7F-13, IO-7F-36 | RESOLVED |
| P1-7F-18 | Topology-generation keys could become readable or writable before their per-key handler-contract intervals were provisioned, so an active type's entries on a new key could be acknowledged as unsubscribed | Topology-key onboarding: complete `OPEN` intervals for the active types before the key enters any read set; relays enabled only after an admission proof; no reopening of draining or retired types; key admission in the read loop and row C-12; mutual exclusion with handler-obligation cutovers; old-key intervals retired only after 7E retires the key; controlled 7E / 7K handoff | §10.5 (TKO-01 … TKO-10, TK-1 … TK-9), REG-7F-03, RDL-14, §12.2 C-9, C-12, KUN-01, §34.9, §34.13, F7F-67 … F7F-72, HE-7K-7F-08, CNF-7F-14, IO-7F-37 | RESOLVED |
| P1-7F-19 | Repeated handler-contract cutovers could assign contradictory PRE provenance to the same historical event, allowing a later cutover to rewrite whether that event was originally owed (add then remove made a never-owed event owed; remove then re-add made an owed event not owed) | One immutable canonical origin record per (group, event, type) with `origin_contract_generation` and `origin_obligation`; insert-if-absent assignment from the pre-switch contract; the first assignment wins and nothing overwrites it; classification by origin with the retired-interval rule kept; per logical group; untouched by topology generations; retained until 7G proves no replay source remains | §10.4 terms, HCG-28 … HCG-31, CUT-5f, §12.2, KUN-01, §34.9, §34.12, F7F-73 … F7F-78, HE-7G-7F-10, IO-7F-36 | RESOLVED |

### 42.4 Minor findings

| ID | Finding | Disposition |
|---|---|---|
| Minor-7F-01 | 7B ordering wording conflict (CNF-7F-01) | Open — controlled reconciliation; carried to 7L; no 7F rule depends on the wording |
| Minor-7F-02 | CON-11 trigger wording conflict (CNF-7F-07) | Open — controlled reconciliation; safety rule fixed |
| Minor-7F-03 | 6C "organization from the payload" wording (CNF-7F-08) | Open — documentary; envelope value binding |
| Minor-7F-04 | 6H "published after commit" comment (CNF-7F-09) | Open — documentary |
| Minor-7F-05 | 6H orphaned-outcome shortcut (CNF-7F-04) | Open — controlled reconciliation; safe rule fixed |
| Minor-7F-06 | Analytics projection appliers for two projections and a physical rebuild intake do not exist | Routed: IO-7F-17, CNF-7F-12 |
| Minor-7F-07 | CRM, Billing and Analytics have no consumer-side business-key constraint for a second logical event; they rely on the producers' guards | Accepted: that is the frozen 7B design (IDN-08, IDN-11, INV-02); no constraint is invented |
| Minor-7F-08 | The Billing dedup key depends on the stability of the event-to-row mapping | Routed: IO-7F-16 makes a mapping change a governed change |
| Minor-7F-09 | Handoff identifiers `HE-7G-*` were already used by 7E | 7F uses the infix `7F` (§36) |
| Minor-7F-10 | A group running a stale manifest holds a new pair of an unsubscribed type (KUN-08) | Safe; cleared by deployment; prevented by VER-7F-06 |
| Minor-7F-11 | The CON-01 denylist lives on best-effort hot-tier Redis | Accepted: frozen 6B design (§13.5); sessions are durably revoked in PostgreSQL |
| Minor-7F-12 | 6K still names the superseded Billing source (CNF-7F-10) | Already routed upstream (IO-7B-02) |
| Minor-7F-13 | The physical form of the handler-contract record is not fixed by 7F | Routed: IO-7F-31, under the properties of HCG-16; no change of any group's obligation is permitted before it exists (HCG-07) |
| Minor-7F-14 | A group is unavailable during a closed-group cutover | Accepted: correctness over availability; entries stay retained (7E TRM-08); sizing to 7K (HE-7K-7F-05) |
| Minor-7F-15 | The boundary-stability rule assumes a node clock does not move backwards across a reload | Routed: HE-7K-7F-06; the replica check of HCG-17 covers failover |
| Minor-7F-16 | An exclusive retention barrier pauses the handlers of one evidence store while a cleanup or partition retirement runs | Accepted: correctness over availability; duration to 7K (HE-7K-7F-06) |
| Minor-7F-17 | The Analytics dedup retention proof used `occurred_at` even though the frozen dedup cleanup uses `created_at` | Corrected: RET-7F-13 uses each store's actual evidence timestamp; RET-7F-16 makes the needed inequality hold by failing closed on future-dated events; the frozen 5J cleanup and the 90-day horizon are unchanged |
| Minor-7F-18 | A publication fence pauses the producers of an affected type for the duration of a cutover, and some producers may not tolerate that | Accepted: correctness over availability; such a change stays blocked (HCG-24); duration to 7K (HE-7K-7F-07); alternative design deferred (DEF-7F-12) |
| Minor-7F-19 | Publication admission adds a control check to relay transport attempts, and the canonical origin records of a high-volume type can be numerous | Accepted: both exist only to make a handler-obligation change safe; sizing to 7K (HE-7K-7F-07); their physical form and indexing are 7G's and IO-7F-36's (HCG-28) |
| Minor-7F-20 | The key-not-onboarded row C-12 was shadowed by C-10: an entry from a key that is not onboarded matched C-10 first (still held, but under the wrong class) | Corrected: C-10 now applies only to an onboarded key (DSQ-09), so such an entry reaches C-12; the no-acknowledgement result is unchanged |

P0: **0**. P1 open: **0** (19 found, 19 resolved). Minor: **20**.

---

## 43. Validation Results

A semantic validator was built and run outside the repository. The version that accompanied the first submission (31 checks) did not model a change of a group's handler obligation or the expiry of idempotency evidence and therefore missed P1-7F-11 and P1-7F-12; it was extended with V-32 and V-33, and V-20, V-24 and V-26 were adapted. That 33-check version in turn did not model the difference between a group's delivery position and the stream's contents, or the interleaving of a horizon check with evidence retirement, and missed P1-7F-13 and P1-7F-14; V-34 and V-35 were added, both built around small executable models, and V-16, V-20, V-32 and V-33 were adapted. That 35-check version modeled only what is already in Redis and did not check that the record obligation gates initial go-live, and so missed P1-7F-15 and P1-7F-16; V-36 and V-37 were added and V-32 and V-35 adapted. That 37-check version accepted the claim that `PUBLISHED` rows have no later transport write and had no model of a new topology-generation key, and so missed P1-7F-17 and P1-7F-18; V-38 and V-39 were added and V-20, V-32 and V-36 adapted. That 39-check version modeled one cutover only and did not test successive handler-contract cutovers of one type, and so missed P1-7F-19; V-40 was added, with an executable multi-generation model, and V-38 and V-39 adapted. It reads the repository (the frozen documents, the migrations directory, the Alembic revisions and this document) and cross-checks structured content against the frozen registries; it is not a keyword scan.

| # | Check | Method | Result |
|---:|---|---|---|
| V-01 | 7A – 7E hashes and line counts | LF-normalized SHA-256 and line count of each file against the baseline and against §6 | PASS |
| V-02 | Phase-6 frozen artifacts and the roadmap | The hashes and line counts parsed from 7B §1.1, recomputed | PASS |
| V-03 | 112 SQL and 112 Alembic, equal names | Directory listing | PASS |
| V-04 | Root `001_5B`, sole head `112_5H5`, linear | `revision` / `down_revision` graph | PASS |
| V-05 | No migration 113; no 7G artifact; no other Phase-7 artifact | Directory listing | PASS |
| V-06 | Only the 7F artifact is new or modified | `git status --porcelain` | PASS |
| V-07 | Exactly 11 durable groups and 1 SIGNAL group | §10 tables parsed | PASS |
| V-08 | Group names, CON ids, event sets and streams equal 7E §29; no CON in two groups | Set equality per group against the parsed 7E tables | PASS |
| V-09 | Event sets equal 7B §22 | 7B CON rows mapped through the 7E route registry (EV → type; DS → SIGNAL type) | PASS |
| V-10 | Consumed durable union = 31 types | Set equality | PASS |
| V-11 | Billing never consumes SIGNAL; no CCPU; no unbound Class-D type; no invented group anywhere in the document | Set intersections against 7E §18.2, §19.1; scan of every group name | PASS |
| V-12 | Every durable consumer has a card with every required attribute row, the registry group and the registry event set | §28 cards parsed | PASS |
| V-13 | Every card matches an independent reference model: idempotency class, exact guard statement per attribute, no re-applied duplicate, acknowledgement only at a durable boundary; the §28.1 summary agrees | Cross-table equality and per-attribute checks | PASS |
| V-14 | Every physical object a card names exists in the executed migrations; the absent CON-10 guard and the absent CON-08 reference are declared; the repository facts behind them hold | Identifier lookup in the SQL files; 7C and 7B text checks | PASS |
| V-15 | Every (consumer, type) pair has a reorder row with a valid class equal to the reference model | §22 parsed against §10 | PASS |
| V-16 | Pseudocode order: claim → effect → `COMMIT` → `XACK`; no acknowledgement on a hold path; no external call inside a transaction; single-key read without `NOACK` | Statement order per block | PASS |
| V-17 | Crash matrix has the 13 points, none allows a duplicate effect, and the commit-before-`XACK` invariant is stated | §20 parsed | PASS |
| V-18 | Atomicity, acknowledgement, concurrency, multi-handler, external-effect and state rules are present with the correct polarity | Rule rows parsed | PASS |
| V-19 | No false exactly-once, per-aggregate-order, timestamp-order or entry-ID-sequence claim; ordering rules intact | Negation-aware statement scan; rule parse | PASS |
| V-20 | Classification table order and outcomes; dispatch steps; known-unsubscribed and invalid-entry rules; state branches | §9, §12, §23, §24 parsed | PASS |
| V-21 | Read-loop rules; `NOACK` only for the SIGNAL group | Rule parse and statement scan | PASS |
| V-22 | No post-7.2 command is used by V1; no 7G command in pseudocode; shutdown rules | §11.2 table and code blocks parsed | PASS |
| V-23 | No reclaim, retry, poison or DLQ number; no invented retention value | Numeric scan of statements | PASS |
| V-24 | Every implementation obligation has owner, dependency and activation condition; required obligations present | §39 parsed | PASS |
| V-25 | Owner-decision register complete, open = 0; inbox decision recorded with its elimination evidence; no universal inbox | §14, §38 parsed | PASS |
| V-26 | P0 / P1 / Minor, ADR, IO, CNF, gate and harness counts agree everywhere; every gate PASS | Counts recomputed from the tables | PASS |
| V-27 | Activation table covers every CON, agrees with the summary, and blocks the consumers whose cards cite a conflict or a missing guard | Cross-table equality | PASS |
| V-28 | Every conflict is open; CNF-7F-01 is not marked resolved | Status parse | PASS |
| V-29 | Tenant, SIGNAL and version rules; failure matrix; handoffs; frozen evidence anchors (cited lines contain the cited text) | Rule parse; line lookup in the frozen documents | PASS |
| V-30 | Readiness line appears once, last, and only when every other check passes; no approval or freeze self-declaration | Tail and status parse | PASS |
| V-31 | 7C order preserved: original validation → upcast → idempotency → handler | §25 block parsed | PASS |
| V-32 | Handler / subscription-set evolution (P1-7F-11): classification against the active obligation, never a local handler set; admission only when capable of the whole active obligation; revalidation before every read; cutover step order; addition boundary without implicit backfill; removal drain; split plan; no reliance on the stale-manifest or version gates; nine rollout scenarios evaluated from the parsed rules | §10.4, §11.3, §12.2, §23, §25, §32, §33, §34.5, §34.9 parsed; scenario evaluation | PASS |
| V-33 | Finite idempotency evidence (P1-7F-12): replay class of every consumer against a reference; CON-06 retention-bounded; horizon gate precedes the insert; beyond-horizon events held; the S3 archive never a guard; per-target replay cap handed to 7G; CON-06 readiness qualified; the frozen 5H and 5A lines contain the cited text; replay-after-retirement scenario evaluated | §9, §14, §18, §28, §31, §33, §34.10, §35, §36, §45 parsed; line lookup in 5H, 5A, `050_5H` | PASS |
| V-34 | Position-interval cutover (P1-7F-13): lower and upper bound per type and key; `A(g, E)` from the interval containing the entry; boundary from the stream's `last-generated-id`, never the group's delivery position; removal keeps the interval draining; admission against active plus draining obligations; retirement conditions before handler deletion; one boundary for a move. An executable model with pending = 0, last-delivered = 50 and stream tail = 100 is run with the parameters parsed from the rules: a removed type's entry 75 must stay owed, an added type's entry 75 must not be owed, and a moved effect must have neither gap nor overlap | §10.4, §12.2, §23, §33, §34.9 parsed; model execution | PASS |
| V-35 | Retention barrier (P1-7F-14): shared barrier before the gate in every finite-evidence handler; clock read after the barrier; exclusive barrier and eligibility re-check in every retirement; CRM, Analytics, Billing partitions and the CON-10 claim covered; default partition not a reinsert path; no retention value changed. An executable interleaving model enumerates handler / retirement orders with the parameters parsed from the rules and pseudocode and must find no order in which a duplicate is accepted as novel | §31, §34.10, §34.11, §33, §35, §39 parsed; model execution | PASS |
| V-36 | Outbox publication fence (P1-7F-15): fence established before the boundary is captured and released only after the group reopens; fence property under PostgreSQL authority; pre-fence set; drain proof covering `PENDING`, `CLAIMED`, `UNKNOWN` and `FAILED`; producer coordination; abandonment. An executable model with one outbox row committed before the cutover and the stream tail at 100 is run with the parameters parsed from the rules and the step order: after a removal the event must stay owed, after an addition it must not become owed, a producer must not be able to commit during the capture, and a replayed `FAILED` row must not cross unguarded | §10.4, §33, §34.12, §36, §39 parsed; model execution; 7D status and rule anchors | PASS |
| V-37 | Generation-1 record prerequisite (P1-7F-16): the record with its listed content exists before the first read; no bootstrap mode; a missing or unreadable record means not admitted in the rule, the startup check and the pseudocode; IO-7F-31 blocks every durable consumer go-live and IO-7F-32 only the first change; domain readiness separated from common prerequisites; no consumer described as production-activatable without them. Also the Analytics evidence-time basis (Minor-7F-17) against the frozen 5J lines | §10.4, §32, §34.9, §35, §39, §45, §46 parsed; line lookup in 5J | PASS |
| V-38 | Relay publication quiescence and replay provenance (P1-7F-17): HCG-23 no longer equates `PUBLISHED` with "no later duplicate"; publication admission checked and registered immediately before the transport write and re-checked; deregistration only at a terminal local transport state; admission closed and attempts proven empty before the boundary; outbox re-check; provenance content and its precedence over the Redis position; 7G handoff content. An executable model of 7D LSE-08 (relay A's attempt outlives its lease, relay B publishes and marks `PUBLISHED`) is run with the parameters parsed from the rules and step order: A's write must not land above `B(K)`, and a deliberately replayed pre-cutover event must be classified by its recorded side for both an addition and a removal | §10.4, §12.2, §33, §34.9, §34.12, §36, §39, §41 parsed; model execution; 7D LSE-08 and 7E AFF-02 anchors | PASS |
| V-39 | Topology-generation key onboarding (P1-7F-18): key admission; complete active intervals; no reopening of draining or retired types; step order with the relay gate after the admission proof; serialization with cutovers; old-key interval retirement after the key. An executable model of `cg.billing.usage-ingestion` and `call.ended` on a new `g2` key is run with the parameters parsed from the rules and step order: the entry must be owed, never acknowledged as unsubscribed, never read or written before the intervals exist | §10.3, §10.5, §11, §12.2, §33, §34.9, §34.13, §36, §39, §41 parsed; model execution; 7E LCY-07 anchor | PASS |
| V-40 | Canonical origin provenance across successive cutovers (P1-7F-19) and the C-12 ordering (Minor-7F-20): one record per (group, event, type) with origin generation and origin obligation; insert-if-absent assignment from the pre-switch contract; no overwrite; precedence over position, key and later cutovers; retired-interval rule; per-group scope; topology invariance; retention. An executable model runs generation 1 (D inactive, E0 produced), generation 2 (D added, E1 produced), generation 3 (D removed), replays E0 and E1, then generation 4 (D re-added) and replays again, with the parameters parsed from the rules and pseudocode: E0 must be `NOT_OWED` and E1 `OWED` at every point. It also runs remove-then-re-add, a three-cutover case, a move between two groups and a replay onto a later topology generation, and checks that an entry from a key that is not onboarded reaches C-12 | §10.4, §12.2, §23, §33, §34.9, §34.12, §36, §39, §45 parsed; model execution | PASS |

Validator result: **40 checks, 2243 assertions, 0 failures.**

---

## 44. Mutation Harness

A scratch harness outside the repository applied targeted semantic mutations to an in-memory copy of this document (and, for repository-integrity mutations, to an in-memory overlay of the repository listing) and re-ran the validator. A mutation counts as detected only when the check it targets fails. Whitespace and formatting mutations are not used.

The 206 mutations of the first submission, the 78 added after the first independent review, the 56 added after the second, the 48 added after the third and the 44 added after the fourth are all retained and were re-run. Coverage includes every mutation required for this phase: acknowledgement before commit; removal of the event-id guard; atomic insert replaced by check-then-act; marker committed before the effect; effect committed before the marker; duplicate re-applies the effect; business-key guard removed; concurrent duplicate both apply; crash after commit duplicates; `NOACK` on a durable group; exactly-once claim; partition affinity as aggregate order; `occurred_at` sorting; entry ID as business sequence; stale policy activation regresses the pointer; duplicate Billing multi-metric usage; partial Billing retry double counts; duplicate Analytics projection; duplicate CRM effect; duplicate Campaign outcome; duplicate import start; reordered document events corrupt the count; unknown or unsupported subscribed version acknowledged; malformed envelope acknowledged as unsubscribed; legitimate unsubscribed type not acknowledged; one group for two independently acknowledged obligations; cross-slot multi-key read; a post-7.2 command required; reclaim policy defined in 7F; external call inside an open transaction; acknowledgement before the durable external-work intent; tenant A suppresses tenant B; upcast changes `event_id`; idempotency before original-version validation; downcast; CNF-7E-10 marked resolved; universal inbox adopted without decision; a consumer without a physical guard hidden; an owner decision left open while ready; final line says approved or frozen.

Mutations added for the independent-review findings, each targeted at V-32 or V-33: a type added to a group while an old worker may still read and acknowledge it as unsubscribed; the local handler set used instead of the active obligation (rule, table and pseudocode forms); the admission gate removed (rule, read loop, startup); activation before every member is proven capable or quiesced; registrations cleared by timeout; revalidation removed; a removed type still executable by a stale worker; drain condition removed; handler code deleted before the cutover; a split with overlapping execution, a new guard identity or a start position at `0`; pre-cutover entries treated as owed without a 7G decision; reliance on the stale-manifest rule or on the version gate; producer enabled before the cutover; CON-06 reclassified as unbounded; the evidence-horizon gate deleted (rule, card and pseudocode forms); the insert placed before the gate; a dropped partition followed by a replay that inserts again; the S3 archive treated as dedup evidence or read by the handler; a beyond-horizon event on the normal path; the held disposition or the Billing reconciliation removed; the retention invariant narrowed to ledgers; a global replay cap; CON-06 readiness without the finite-evidence condition; the horizon table row removed while the retention gate still passes; the frozen 5H retention line altered.

Mutations added after the second independent review, each targeted at V-34 or V-35: with pending = 0, last-delivered = 50 and stream tail = 100, a removal after which entry 75 is acknowledged as unsubscribed; the same state for an addition, after which entry 75 becomes owed; the boundary changed back to the group's `last-delivered-id` (rule, step and term forms); `inactive_after` removed; the interval lookup removed from classification so that only the current `H_active` is consulted; admission against the active set only; the removed handler deleted right after the cutover; retirement by elapsed time; a retired-interval entry acknowledged as unsubscribed; a move whose old stop and new start differ in either direction; the horizon check passing, cleanup deleting the evidence and the guard then accepting the duplicate; a Billing partition detached between gate and insert; an Analytics dedup row removed between the age check and the ingest function; a CRM claim row removed between the horizon check and the claim; the cleanup not acquiring the barrier; the consumer not acquiring it; the cleanup not re-checking eligibility after acquiring it; the gate evaluated before the barrier or with the transaction start time; the default partition as a reinsert path; a frozen retention value changed to hide the race.

Mutations added after the third independent review, each targeted at V-36 or V-37 (V-35 for the Analytics basis): an event of a removed type committed before the cutover, `PENDING` through the boundary capture, later published above it and acknowledged as unsubscribed; the same for an added type, later executed as newly owed; a producer that keeps committing outbox rows while the boundary is captured; the drain proof ignoring a `CLAIMED` row; ignoring an `UNKNOWN` outcome; a replayable `FAILED` row crossing the cutover later; the outbox drain proof removed while the Redis interval proof is kept; the boundary captured before the producers are fenced; producers resumed before the switch and the reopening are complete; the fence based on `occurred_at`; a producer allowed to emit around the fence; an unfenceable producer not blocking the change; the generation-1 record initialisation deleted; a first `XREADGROUP` permitted with no record; a fallback to the compiled registry; IO-7F-31 changed back to blocking only the first change; CON-06 described as ready for production activation without the common prerequisites; the Analytics dedup registry modeled as retired by `occurred_at`; the future-dated rule removed.

Mutations added after the fourth independent review, each targeted at V-38 or V-39: relay A starts a transport attempt, its lease expires, relay B publishes and marks the row `PUBLISHED`, the boundary is captured and A later appends above it; the same for an added obligation, with the event executed; the relay-quiescence step removed; the boundary captured while a publication registration is still active; `PUBLISHED` treated as proof that no late transport write exists; admission checked only at claim time; deregistration before the attempt is terminal; registrations cleared by timeout; a retained pre-cutover `PUBLISHED` event replayed after the cutover and classified solely by its new Redis ID; original-contract provenance removed from the 7G handoff or from the provenance record; the provenance lookup removed from classification; a `g2` stream and group created with no handler-contract intervals, an active event published and classified as known-unsubscribed; a `g2` read started before interval provisioning; a `g2` relay started before interval provisioning; one active type omitted from the new-key interval set; a draining removed type given a new `OPEN` interval on `g2`; a topology migration run concurrently with a handler-obligation cutover; the `g1` interval retired before 7E retires `g1`.

Mutations added after the fifth independent review, each targeted at V-40: the latest provenance record wins; an earlier origin record overwritten during a later cutover; D added then removed and the old E0 classified as owed; T removed then re-added and the original E0 classified as not owed; `origin_contract_generation` erased; `origin_obligation` erased; provenance keyed by `event_id` without the group; a topology generation replacing origin provenance; canonical provenance retired because a newer contract generation exists; classification by Redis ID although a canonical record exists; the ambiguous per-cutover side lookup restored; an owed event with a retired origin interval executed under a newer interval; the assignment taken from the post-switch contract; every retained event re-recorded as pre-side at each cutover; C-12 left behind a C-10 rule that swallows entries from a key that is not onboarded.

| Measure | Value |
|---|---:|
| Total mutations | 456 |
| Detected | 456 |
| Missed | 0 |
| Harness errors | 0 |
| No-ops | 0 |

---

## 45. Freeze Gates

A gate passes only when the cited evidence substantively proves it.

| Gate | Check | Result | Evidence |
|---|---|---|---|
| G-01 | 7A – 7E hashes and line counts exact | PASS | §6; V-01 |
| G-02 | Phase-6 frozen artifacts unchanged | PASS | §6; V-02 |
| G-03 | 112 SQL + 112 Alembic; root `001_5B`; sole head `112_5H5` | PASS | §6; V-03, V-04 |
| G-04 | No migration 113 | PASS | §6; V-05 |
| G-05 | No 7G artifact; only the 7F artifact is new | PASS | V-05, V-06 |
| G-06 | All 11 durable groups represented, exactly | PASS | §10.1; V-07, V-08 |
| G-07 | Event sets equal 7E §29 and 7B §22; union = 31 | PASS | §10; V-08 … V-10 |
| G-08 | SIGNAL handled separately | PASS | §10.2, §29 |
| G-09 | No invented consumer; no CCPU; no unbound Class-D consumer | PASS | §4, §10; V-11 |
| G-10 | Every durable consumer has a concurrency-safe guard, or is blocked from activation | PASS | §19, §28 (concurrency rows), §35 |
| G-11 | Every durable effect is idempotent under same-event redelivery, by a named mechanism | PASS | §13, §28 (duplicate rows); V-12 … V-14 |
| G-12 | Business-key guards identified where event-id is insufficient | PASS | §17, §28 (logical-duplicate rows) |
| G-13 | Local dedup / effect atomicity proven | PASS | TXA-01 … TXA-04, TXA-10, TXA-11; §34.1 |
| G-14 | `XACK` only after durable success | PASS | XAK-01, XAK-05; §34; V-16 |
| G-15 | Crash after commit before `XACK` is safe | PASS | CRP-08, CRI-01; §34.4; V-17 |
| G-16 | Concurrent duplicate race safe | PASS | §19; §34.3 |
| G-17 | Ordering assumptions conform to 7E | PASS | §21 (RA-1 … RA-7, ORD-7F-01 … ORD-7F-08); V-19 |
| G-18 | Every consumer has a reorder analysis | PASS | §22; V-15 |
| G-19 | No current consumer depends on an order the transport cannot give | PASS | §22; P1-7F-01, P1-7F-03, P1-7F-04, P1-7F-10 resolved |
| G-20 | Known-unsubscribed entries do not pin streams, and known-unsubscribed is decided from the group's active obligation, never from a stale local handler set | PASS | KUN-01, KUN-03, KUN-07, KUN-09, XAK-03; HCG-05; V-32 |
| G-21 | Poison, malformed and unsupported entries are never success-acknowledged (unchanged by the remediation) | PASS | §12.2, KUN-04, NAK-01, XAK-06; V-20 |
| G-22 | Version / upcast order conforms to 7C | PASS | §25; DSQ-05; V-31 |
| G-23 | Durable groups do not use `NOACK` | PASS | RDL-03, SIG-7F-03; V-21 |
| G-24 | Read loop is cluster-safe | PASS | RDL-01, RDL-02, RDL-13 |
| G-25 | No V1 dependency on Redis later than 7.2 | PASS | §11.2; V-22 |
| G-26 | Multi-handler semantics conform to 7E GRP-02 | PASS | §27 |
| G-27 | SIGNAL never becomes Billing-authoritative | PASS | SIG-7F-07; V-11 |
| G-28 | No transaction spans external I/O | PASS | CPM-06, TXA-07, EXT-01; §34.7, §34.8 |
| G-29 | Tenant isolation preserved in processing and dedup | PASS | §30, EID-05, EID-06; V-29 |
| G-30 | Every finite idempotency-evidence horizon is modeled: the invariant covers ledgers and retention-bounded effect rows and states both the admission rule and the retirement-race rule; each consumer has a class and a horizon; no number invented or changed | PASS | RET-7F-01, RET-7F-04, RET-7F-05, RET-7F-08, RET-7F-09, RET-7F-11, RET-7F-15; §31.2; V-33, V-35 |
| G-31 | Inbox decision closed with evidence; no universal inbox created | PASS | §14 |
| G-32 | 7G boundary respected | PASS | §4, XAK-07, §36.1; V-23 |
| G-33 | 7H boundary respected | PASS | §4, EXT-06, §36.2 |
| G-34 | 7I boundary respected | PASS | §4, TEN-7F-09, §36.3 |
| G-35 | 7J boundary respected | PASS | §4, §36.4 |
| G-36 | 7K boundary respected | PASS | §4, RDL-07, RDL-08, §36.5 |
| G-37 | 7B ordering-wording conflict kept open | PASS | CNF-7F-01; V-28 |
| G-38 | Every implementation obligation has owner, dependency, activation condition | PASS | §39; V-24 |
| G-39 | Every consumer has a domain-specific readiness classification; none is called deployable on a generic pattern; domain readiness is separated from the common event-platform prerequisites; CON-06 readiness carries the finite-evidence condition | PASS | §35.1, §35.2; V-27, V-33, V-37 |
| G-40 | No false idempotency or exactly-once claim | PASS | CPM-01, IDT-01; V-19 |
| G-41 | P0 = 0 | PASS | §42 |
| G-42 | P1 open = 0, including P1-7F-11 … P1-7F-19 | PASS | §42.2, §42.3 |
| G-43 | All owner decisions resolved | PASS | §38; V-25 |
| G-44 | Semantic validator passes | PASS | §43 |
| G-45 | Mutation harness: 0 missed, 0 errors, 0 no-ops | PASS | §44 |
| G-46 | Counts agree everywhere | PASS | V-26 |
| G-47 | Handler / subscription-set evolution is safe by **all three layers**: (1) a PostgreSQL producer / outbox publication fence with a drain proof; (2) relay publication quiescence for normal transport attempts and recorded pre-cutover provenance for governed replays; (3) a Redis stream-position boundary; no worker reads under an incompatible active handler contract; no event committed before a cutover can first reach the stream above the boundary; a stale or ambiguous relay attempt cannot append above it; a replay is classified by its canonical origin provenance, not by its new Redis ID; an addition does not implicitly backfill entries already in the stream or already in the outbox; a removal does not discard already-published owed entries, nor events already committed to the outbox, even with an empty pending list and undelivered backlog; a historical removal interval stays executable until it is provably drained and retired; a move or split has one exact positional boundary | PASS | §10.4 (HCG-02 … HCG-31, CUT-1 … CUT-9); §12.2 C-9 … C-11; §34.12; F7F-42 … F7F-51, F7F-56 … F7F-66; V-32, V-34, V-36, V-38 |
| G-48 | Finite idempotency-evidence replay safety: the horizon gate rejects events beyond a consumer's guaranteed evidence horizon, and evidence retirement cannot race an admitted processing transaction (shared / exclusive retention barrier with re-checks on both sides); Billing cannot create a second usage fact after hot retention or across a partition retirement | PASS | RET-7F-08, RET-7F-09, RET-7F-11 … RET-7F-14; §34.10, §34.11; F7F-41, F7F-52 … F7F-55; HE-7G-7F-05; V-33, V-35 |
| G-49 | Startup and admission: no durable worker issues a read without its group's generation-1 handler-contract record; there is no bootstrap mode; the record obligation blocks every durable consumer go-live | PASS | HCG-01 … HCG-04, HCG-07; SHD-08; §34.9; §35.1; IO-7F-31; F7F-62; V-32, V-37 |
| G-50 | Topology generations: every new key has complete active intervals in every subscribed group's record before any consumer read and before any relay write; no draining or retired obligation is reopened on a new key; topology-key onboarding and handler-obligation cutovers are serialized per group; an old-key interval outlives its key | PASS | §10.5 (TKO-01 … TKO-10, TK-1 … TK-9); §12.2 C-12; §34.13; F7F-67 … F7F-72; V-39 |
| G-51 | Successive handler-contract generations: one event has one immutable original obligation per logical group; a later cutover cannot overwrite, reinterpret or duplicate it; replay after any number of add / remove cycles is deterministic; an owed event whose origin interval is retired is held, not executed under a newer interval; topology generations do not alter origin provenance; it is retained until 7G proves no replay source remains | PASS | HCG-28 … HCG-31; CUT-5f; §12.2; §34.9, §34.12; F7F-73 … F7F-78; HE-7G-7F-10; V-40 |

Gates: **51**. PASS: **51**. FAIL: **0**.

---

## 46. Freeze-Gate Status

| Item | Value |
|---|---|
| P0 findings | 0 |
| P1 findings | 0 open (P1-7F-01 … P1-7F-19 found and resolved; P1-7F-11 … P1-7F-19 found by the independent freeze-gate reviews) |
| Minor findings | 20 (Minor-7F-01 … Minor-7F-20) |
| Owner decisions | None raised by 7F; open: 0 |
| ADRs | 19 |
| Implementation obligations | 37 |
| Conflicts recorded | 14 (all open as controlled reconciliations; CNF-7F-01 carried to 7L) |
| Consumers | 11 durable logical groups, 1 SIGNAL group; 31 consumed durable event types |
| Inbox decision | No shared inbox; domain-owned idempotency (DD-13 closed) |
| Activation | No consumer is production-activatable before the common prerequisites of §35.1, including its generation-1 handler-contract record (IO-7F-31). Domain-specific readiness — Domain logic READY: CON-06 for four types, on the finite-evidence condition (evidence-horizon gate and retention barrier). IMPLEMENTATION OBLIGATION: CON-01, CON-02, CON-04, CON-07. GOVERNED MIGRATION REQUIRED: CON-10; CON-06 for `conversation.completed`. UPSTREAM CONTROLLED RECONCILIATION REQUIRED: CON-03, CON-05, CON-08, CON-09, CON-11 |
| Frozen baselines | 7A – 7E hashes exact; 20 Phase-6 hashes exact; 112 SQL + 112 Alembic; root `001_5B`; sole head `112_5H5`; no migration 113; no 7G artifact |
| Next step | Independent freeze-gate review of 7F. This document does not declare itself approved or frozen and does not begin 7G. |

**PHASE 7F = READY FOR INDEPENDENT FREEZE-GATE REVIEW**
