# Phase 7H — External Event Delivery — AI Voice Agent Platform

---

## 0. Status, Scope and Authority Declaration

| Field | Value |
|---|---|
| Document | `docs/phase-07-event-architecture/7H-External-Event-Delivery.md` |
| Phase | 7 — Event Architecture |
| Sub-phase | 7H — External delivery: public webhooks, provider-callback processing boundary, plugin callouts (7A §35) |
| Nature | Architecture and design. No application code, no SQL, no migration, no Redis configuration, no API route, no edit to any frozen document. |
| Status | **READY FOR INDEPENDENT FREEZE-GATE RE-REVIEW.** This document does not declare itself approved or frozen; freezing is an independent-review act, and Phase 7 as a whole is frozen only after 7L. |
| Date | 2026-10-10 |
| Remediation | The first independent freeze-gate review, of the version with LF SHA-256 `f5394451a6bc1bcc8827f7e88d5b4510cc79e698365184c2c9dd8006cdf42e65` / 1945 lines, **rejected** it: P0 = 0 and six P1 freeze blockers, where that version had reported P1 = 0. They are P1-7H-R01 (no durable processing facts for an acknowledged provider callback), P1-7H-R02 (the organization-status check was not serialized against suspension, and "no HTTP after suspension" was not achievable as stated), P1-7H-R03 (recursive replay multiplies the quota and extends retention; the "200 requests per event" bound was false), P1-7H-R04 (one attempt number could name two different claims), P1-7H-R05 (a scheme-host-port digest does not identify the destination) and P1-7H-R06 (a fail-closed plugin rule was imposed without an owner decision), plus Minor-7H-R01 (billing money representation) and Minor-7H-R02 (successor-topic deduplication). All are remediated in place; the reasoning for each is in §26 and the ledger in §24.2. Sections changed: §0, §1.3, §1.4, §3.1, §4.2, §5.3, §6.2, §7.2, §8, §9.4, §9.6, §11, §12.2, §13, §14.2, §14.5, §14.6, §15, §17, §18, §19, §20.2, §21 – §26, Appendix A. The review's other findings of the first version are not reopened. |
| Second remediation | The second independent review, of the version with LF SHA-256 `0f2dc030e5e373e49740dfbff52d8e086ae149bee1b185b39d3fe6456298bedd` / 2382 lines, accepted the first remediation in substance and found P0 = 0 and **two P1**: P1-7H-R07 (new: signing references and destination could come from different endpoint configuration generations; previous-secret grace not proven at hand-off; zero-grace cutover overstated) and P1-7H-R05 (incomplete: attribution of an attempt to the configuration change rested on comparing times against an audit record 6J labels asynchronous). It also found Minor-7H-R03 (the 200-request automatic bound stated unconditionally) and asked for formal disposition of two policy points (replay body lifetime; accounting of a missed admission window). Owner decisions OD-7H-12 … OD-7H-15 were obtained first. Remediated in place: §3.1, §6.2, §8, §9.4, §10.1, §10.1.1, §13.3, §13.5.1, §14.5, §14.5.1, §14.6, §16.2, §17, §18 (traces 15, 25, 27, 28), §19, §20, §22 – §26, Appendix A. |
| Third remediation | The third independent review, of the version with LF SHA-256 `e85c17406a1576e2e75b933719f25ec16f97d29ebd811d1085253475bbe01849` / 2556 lines, accepted the closure of the earlier seven P1 in substance and found P0 = 0 and **two new P1**: P1-7H-R08 (guarantee C1 was asserted, but the admission took no lock that conflicts with an endpoint mutation, so an admission could commit after a rotation or `PATCH` while recording the earlier revision) and P1-7H-R09 (an unresolvable previous secret silently suppressed `X-Platform-Signature-Previous` inside an active grace, and dual signing stopped up to 6 s before the published expiry without approval). It also found Minor-7H-R04 (abandonment of an admission described as a change to an append-only record) and Minor-7H-R05 (the zero-grace residual described as giving an attacker nothing), and asked for an explicit decision on the `ENDPOINT_GONE` accounting. Owner decisions OD-7H-16 … OD-7H-18 were obtained first. Remediated in place: §0, §1.4, §4.2, §6.2, §6.3, §8.2, §8.3, §9.3, §9.4, §9.6, §10.1, §10.1.1, §10.1.2 (new), §13.3, §13.5, §14.2.1, §14.2.2 (new), §14.3, §14.5, §14.5.1, §17, §18 (traces 15, 16, 27, 28; new 29, 30), §19, §20.2, §22 – §26, Appendix A. |
| Repository baseline | `main` @ `bbb70d1` ("D0 completed"), working tree clean at start |
| Frozen upstream | Phases 1 – 6 (the 20 Phase-6 artifacts); Phase-5 migrations `001_5B` … `112_5H5`; 7A – 7G (hashes in §1.1); D0 foundation (`backend/`) |
| Owner decisions | OD-7H-01 … OD-7H-07, decided before authoring; OD-7H-08 … OD-7H-11, decided during the first remediation; OD-7H-12 … OD-7H-15, decided during the second remediation; OD-7H-16 … OD-7H-18, decided during the third remediation; all by the owner on 2026-10-10 (§22). Open owner decisions: **0** |
| Preserved owner decisions | AIR-OD-01 … 03, AIR-P0-EVT-01 … 04, AVS-OD-01 … 11, OD-7B-01, OD-7B-02, OD-7C-01 … 07, OD-7D-01 … 03, OD-7E-01 … 03, OD-7G-01 … 04, OD-D0-01, OD-D0-02 (none reopened) |
| Closes on completion | 7B IO-7B-12 (topic source mapping); 7C DEF-7C-06 (webhook projection part); 7D PCI-13 / 25 / 26 / 28 / 35 (processing-design part); 7F HE-7H-7F-01; 7G HE-7H-7G-01, HE-7H-7G-02; 7A §18 deferral (worker concurrency model, jitter, endpoint-health policy disposition); 7A T-08, T-09 |
| Does not close | 7F HE-7H-7F-02 (storage-provider deletion semantics): out of external *event* delivery; carried to 7L unchanged (§23.5) |
| Does not begin | 7I, 7J, 7K, 7L, D1, Phase 8 |
| Artifact rule | This is the only new project artifact for 7H. No migration 113 is created. Every migration dependency is described as a logical requirement (§17) and is **not implemented**. |
| Normative keywords | **MUST**, **MUST NOT**, **SHOULD**, **MAY** carry RFC 2119 meaning. Every rule has a stable ID. |

### 0.1 How to read the provenance of each statement

Every rule and table row carries one of five provenance tags. A reader must never have to guess which kind of statement they are reading.

| Tag | Meaning | May 7H or an implementer change it? |
|---|---|---|
| **[FROZEN]** | Restates a frozen Phase 1 – 7G contract or an executed migration fact, with its source | No. Only a governed amendment of the owning source can. |
| **[OD]** | Applies an owner decision OD-7H-nn (§22) | No. Only the owner can. |
| **[7H]** | A Phase-7H design rule derived from frozen contracts, inside the space they leave open | Only by amending 7H before freeze, or by a governed amendment after. |
| **[REC]** | An implementation recommendation. Correctness does not depend on the value. | Yes, by the named later owner (usually 7K). |
| **[LATER]** | An obligation that belongs to 7I, 7J, 7K, 7L or an implementation phase | It is that phase's to design. 7H states the constraint only. |

### 0.2 What is designed versus what exists

Nothing in this document is implemented. D0 provides configuration loading, PostgreSQL and Redis lifecycle, health probes, logging with redaction, the error envelope and request correlation (`backend/README.md` "What exists today"). It contains no event pipeline, no relay, no consumer, no delivery worker and no egress adapter. Where this document says a component "does" something, it means "is required to do" once built.

Several mechanisms below depend on a future governed Phase-5 migration (§17.3). They are marked `SCHEMA GAP — CONTROLLED FUTURE MIGRATION REQUIRED`. Until that migration exists, the webhook engine is **not activatable** (§17.5). No such migration has been written or executed.

All validation recorded in §25 is static: reading of frozen documents and SQL text, plus read-only repository commands. No runtime test, database statement or HTTP request was executed.

---

## 1. Source Inventory and Approved Architecture Dependencies

### 1.1 Frozen baseline verified at start (read-only commands, executed)

| Check | Result |
|---|---|
| `HEAD`; working tree | `bbb70d1`; clean |
| Phase-7 folder before 7H | 7A … 7G only |
| Phase-6 folder | 20 artifacts |
| SQL migrations under `docs/phase-05-database-design/5K/migrations/` | 112; first `001_5B.sql`, last `112_5H5.sql`; no `113*` |
| Alembic revisions under `5K/alembic/versions/` | 112 files; names equal the SQL names; one root (`001_5B`, `down_revision = None`); sole head `112_5H5`; no duplicate `down_revision`; no orphan |
| PostgreSQL baseline | 18 (6J §63; 7A §6.3; D0 refuses < 16 and treats 18 as baseline) |

| Frozen Phase-7 artifact | LF-normalized SHA-256 | Lines |
|---|---|---:|
| `7A-Event-Architecture-and-Standards.md` | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` | 1086 |
| `7B-Event-Taxonomy-and-Ownership.md` | `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` | 2207 |
| `7C-Event-Envelope-and-Schema-Versioning.md` | `e514e3c4a889775fbc8e9baba3a9ad0558b5228465f240f425d7c762f1d200a0` | 3275 |
| `7D-Transactional-Outbox-Architecture.md` | `2714a3eec6eb7c95be50c3b11c2e80c66f3f93a413ebcecfa46c5c79bf9e4de5` | 1572 |
| `7E-Redis-Streams-Topology.md` | `671fcebe17bb08da4783c89323235f2bc7819fff3155d0a2d46578c6819a9c93` | 1875 |
| `7F-Consumer-Idempotency-and-Ordering.md` | `0f9db999f059486b033f06b40358a2f94978281e026e3e92ba3575adbd1185b1` | 2076 |
| `7G-Retry-DLQ-Poison-Handling-and-Replay.md` | `0213cc09f2e6a1b13be331575e3c5878ab320ab357d752cbcc27f252cd21f0e4` | 1920 |

### 1.2 Sources read

Read in full or by targeted section, as listed. "Section" means the parts that govern 7H were read line by line; the rest of the file was located by heading outline and keyword search, not read end to end. This distinction is deliberate: the Phase 5 – 7 corpus is about 8 MB.

| Source | Parts read line by line |
|---|---|
| 7A | §1 – §12, §16 – §39 (all standards, registers, threat review) |
| 7B | §18 (Class G), §19 (Class H), §20; every `7H` reference; NAM-F rules; IO-7B-12, IO-7B-22; traceability rows of the 19 topic sources |
| 7C | §20 schema bindings of EV-004, 005, 006, 021, 024, 025, 035, 037, 038, 046, 071, 075, 084, 085, 091, 102 – 105; §40, §41; DET-18; DEF-7C-06 |
| 7D | Post-commit continuation inventory rows PCI-13, 25, 26, 28, 35; every `7H` reference |
| 7E | Route registry rows bound to `cg.integrations.webhook-engine`; §29 group registry row |
| 7F | §10.4 (handler-contract generations, `H_active`, `H_capable`, `A(g,E)`, `O(g, event_id, event_type)`), §26 (external side effects), §27, §28.11 (CON-10), §36.2 |
| 7G | §7, §9, §10, §14, §15, §30, §40, §41, §44, §52, §56 |
| 6A | §21, §28, §35 |
| 6B | Credential types table and internal-token sections (L131 – L348, L458); permission strings |
| 6C | Event section §20 (internal-bus-only classification); suspension references |
| 6D | §10.4, §24.2, §24.3, §42.3b; callback references |
| 6J | §17 – §30, §35.3, §36, §37 – §46, §50, §54, §56, §57 |
| 6K | §45; webhook-receipt sections by search |
| 6M | Webhook rows of §25 inventory, §55, `DBGAP-6M-04`, `DBGAP-6M-10` |
| AVS | AX table; SG-01 … SG-09; CM-WH-01 … CM-WH-12; §27.5 rows |
| AEC, AMI, AIR | Rows of AMI-6J-014, 018, 025, 028, AMI-6D-021, AMI-6K-023; AIR §18, §18.2, J1 – J4 classification, DEP-6J-07 |
| 5I | §3 – §25, §35, §38; QP-07 … QP-09 |
| SQL | `062_5I`, `063_5I`, `064_5I`, `065_5I` (structure), `066_5I`, `101_5I1` (header, webhook parts), `109_5B7` Part G, `003_5B` (status CHECKs), `001_5B` (roles) |
| 4F | §8 (webhook aggregates, services, topic catalogue), §9 (plugin context) |
| 4A | Organization status invariants |
| D0 | `backend/README.md`; `backend/docs/D0-FINDINGS-AND-RECONCILIATIONS.md` §1, §6; module inventory |
| Product | `PROJECT_ROADMAP.md`, `ARCHITECTURE_PRINCIPLES.md`, `TECH_STACK.md` |

Not read line by line, and therefore not relied on beyond the citations other frozen documents make to them: 6E, 6F, 6G (except §30 references), 6H, 6I, 6L (except the cost-confidentiality rule as restated in 7A BIL-05), FAR, Phase 1 – 3 (except keyword hits for topic names).

### 1.3 Requirement inventory

| # | Requirement | Source | Frozen rule | 7H implication | Conflict or gap |
|---:|---|---|---|---|---|
| 1 | Public webhooks are external delivery, not the bus | 7A WH-01, WH-02; 6A §28.3 | Driven from committed events; never synchronous in a business transaction | §4 flow; BND-02 | — |
| 2 | Signing contract | 6J §21.1 – §21.2; AVS SG-01 … SG-09; 7A WH-03, WH-06 … WH-12; 7C WHB-02 | `HMAC-SHA256(secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")`, `X-Platform-Signature: v1={hex}` | §9, §10 preserve it byte for byte | — |
| 3 | Dual-signature rotation | 6J §21.1, §21.3; ADR-6J-07; `101_5I1` | `X-Platform-Signature-Previous` while `previous_secret_expires_at` is in the future | SIG-05 … SIG-08 | — |
| 4 | Topic catalog | 6J §19.1; 4F §8.4; 7B §18.2; AVS AX-E | 19 topics, all version 1; additive only; successor topic for breaking change | §5 matrix | CNF-7H-03, CNF-7H-04 |
| 5 | Envelope | 6J §20.1 – §20.2; 7C WHB-01 | `id, type, version, occurred_at, organization_id, data.object, request_id` | §9.2 | CNF-7H-01, CNF-7H-02 |
| 6 | Delivery guarantee | 6J §22.1; 7A DEL-01, DEL-04 | At-least-once; never exactly-once | §7, §8; no exactly-once claim | — |
| 7 | Ordering | 6J §22.2; 6A §28.1; 7A ADR-7A-12 | Not guaranteed globally, per endpoint or per type | §16 | — |
| 8 | Retry schedule | 6J §22.3; 4F §8.1.1 | 0, 30 s, 60 s, 5 m, 30 m, 2 h, 8 h, 24 h; `max_attempts` 1 – 10 default 7 | §13.2 | Attempts 9 – 10 undefined → OD-7H-04 |
| 9 | Response classification | 6J §22.4 | 2xx success; 3xx not followed; 4xx, 429, 5xx, network failures retryable; only exhaustion reaches `DEAD_LETTER` | §9.6, Matrix F | CNF-7H-06 (`Retry-After` wording) |
| 10 | Delivery state vocabulary | `063_5I` `chk_wd_status`; 5I §13 | `PENDING, DELIVERING, DELIVERED, FAILED, DEAD_LETTER, CANCELLED` | §8 uses only these | CNF-7H-07 (`FAILED` unreachable) |
| 11 | Delivery immutability | `fn_wd_identity_immutable`; 5I INV-WH-04; 4F §8.2 inv. 1 | `payload_json`, `payload_hash`, `event_id`, `event_type`, `webhook_endpoint_id`, `organization_id` immutable | Body fixed at intent creation (HTP-04) | CNF-7H-01 |
| 12 | Replay | 6J §23.3; `fn_replay_webhook_delivery` (`063_5I`, `101_5I1`); 7G WHB-01 … 04 | New row, same `event_id`, `replay_of_delivery_id`; only from `DEAD_LETTER` / `DELIVERED`; idempotent while a replay is open | §13.5 | Endpoint status unchecked → OD-7H-03; recursion and lineage → OD-7H-10 (CNF-7H-15) |
| 13 | Fan-out consumer | 7F §28.11 (CON-10); 7E §29; 6J §37.2 | One transaction: claim + one row per matching ACTIVE endpoint; `XACK` after commit; blocked until IO-7F-21 | §7 | SCHEMA GAP (MR-7H-01) |
| 14 | Fan-out time authority | 7F §28.11 "stale-event behaviour"; 7G HE-7H-7G-02 | A late or replayed event fans out to endpoints ACTIVE at processing time; the claim prevents a second fan-out | SUB-02 | — |
| 15 | Disable semantics | 6J §18.6, §18.8; 4F §8.1 inv. 3; ADR-6J-02 | `DELETE` = disable; non-ACTIVE endpoint receives no new deliveries; deliveries already `PENDING` / `DELIVERING` complete normally | §6.3 | — |
| 16 | Egress control | 6J §30.3; ADR-6J-06; 5I ADR-5I-009 | One shared adapter: https only, private / link-local / metadata blocked, resolve-then-pin per request, TLS verified against hostname, port 443, 2 MB cap, no transaction held | §14.3 | — |
| 17 | Provider callbacks | 7A CB-01 … CB-07; 6J §24; 6D §10.4; 6K §30; 7B §19 | Verify → dedup → fast ACK → async processing; tenant from platform-held state | §11 | SCHEMA GAP (MR-7H-09); CNF-7H-09; no durable processing facts → OD-7H-08 (CNF-7H-14) |
| 18 | Plugins | 6J §25 – §30; 4F §9; AVS SG-06; 7A WH-10 | External HTTPS services; distinct signed canonical input; capability intersection; no auto-retry of non-GET | §12 | CNF-7H-10 |
| 19 | No transaction across I/O | 6A §35; 7A PR-06, DUR-04; 7F EXT-01 | Sequential short transactions | §4, §17.2 | — |
| 20 | Tenant context | 7A TEN-01 … TEN-04; 6J §31 | From trusted state, never from payload; RLS not bypassed | §14.1 | SCHEMA GAP (MR-7H-02) |
| 21 | Roles | `001_5B`, `062_5I`, `063_5I`, `101_5I1`, `109_5B7` | `app_api`, `app_worker` non-BYPASSRLS; delivery UPDATE / DELETE revoked from app roles; since 109 `app_platform_admin` is SELECT-only on deliveries | §17 | SCHEMA GAP (MR-7H-07) |
| 22 | Cross-tenant admin replay | 6M §55; `DBGAP-6M-04` | NOT BUILT — FUTURE | §14.3 | — |
| 23 | Commercial | 6J §46, §57 J4; AIR L1546, L1752 | Not a V1 metric; FAR-classified FUTURE | §20 | — |
| 24 | Retention | 6J §22.6, §41; 5I §14, §23 | `DELIVERED` 30 days; `DEAD_LETTER` 90 days; ops-owned purge | §17.4 | CNF-7H-05; SCHEMA GAP (MR-7H-07) |
| 25 | Internal replay boundary | 7G §30 (R7), §41.1, §44 | 7G never selects a delivery row; CON-10 blocked as replay target until its claim exists | §13.6 | — |
| 26 | Contract generations | 7F §10.4 | `H_active(g)` authoritative and separate from `H_capable(build, g)`; per-type per-key intervals; `O(g, event_id, event_type)` immutable | §16.3 | — |
| 27 | Sensitive data | 6J §39, §40; 7A SEC-01 … SEC-07, BIL-05; 6K §24, §45.1 | No transcript, recording, signed URL, secret, cost or margin in any webhook body | §5.3, Matrix H | — |
| 28 | Voice hot path | 7A VOX-01 … VOX-03; 6D §21 | ≤ 750 ms is a target; nothing on the media path waits on events or REST | PLG-09 | — |

### 1.4 Conflict register

A conflict is recorded when two frozen sources disagree or one is ambiguous on a point 7H must implement. 7H edits no frozen source. Each row names the rule that resolves it and whether an upstream erratum is owed.

| ID | Conflict | Sources | Resolution in 7H | Basis | Upstream action |
|---|---|---|---|---|---|
| CNF-7H-01 | Envelope `request_id` is described as "the delivery attempt's own correlation ID", but `payload_json` is immutable across attempts and copied verbatim by replay | 6J §20.1 vs `fn_wd_identity_immutable`, 4F §8.2 inv. 1, 6J §23.3 | `request_id` is generated once when the delivery intent is created. It is constant across every attempt of that delivery and across replays of it. Per-attempt identity is internal (`delivery_id`, `attempt_number`) | The DB-enforced immutability is a Phase-5 data fact (7A AUTH order 3) and cannot be satisfied otherwise | Erratum to the 6J §20.1 note (ERR-7H-03); 7L |
| CNF-7H-02 | Envelope example shows `id` as `evt_` + UUID; the header table says `X-Platform-Event-Id` is `webhook_deliveries.event_id` "(= envelope `id`)" | 6J §20.1 example vs §21.1 header table; 7C WHB-04 assigns the mapping to 7H | Body `id` and `X-Platform-Event-Id` carry the **identical** string: `evt_` followed by the lower-case canonical UUID of `event_id`. `X-Platform-Delivery-Id` and `request_id` are bare UUIDs, as their examples show | Only reading under which both frozen statements hold | None; fixed here before first delivery (HTP-06) |
| CNF-7H-03 | 4F maps `lead.created` to `contact.created` "with source = AI"; 6J, 6G and 7B map every `contact.created`; the frozen `source` enum has no `AI` value | 4F §8.4 vs 6J §19.1, 6G §30, 7B WHT-05, 7C E-CONTACT-SOURCE, 7F CON-10 | No source filter. Every `contact.created` is eligible for `lead.created` | 7A AUTH-02: 6J / 6G own the semantics; 7B and 7F froze the unfiltered binding | Capacity consequence (bulk imports) handed to 7K (HE-7K-7H-03) |
| CNF-7H-04 | 7B left the internal source of `call.started` / `call.completed` "pending 7H", yet 4F fixes it | 7B WHT-01, WHT-02 vs 4F §8.4 L873 – L874, 4I L1402 | `call.started` ← EV-004 `call.initiated`; `call.completed` ← EV-005 `call.ended`. Names are not merged. Closes IO-7B-12 | 4F is the governed catalogue 6J reuses "verbatim" | 7E / 7F registry change needed before delivery (AB-7H-03) |
| CNF-7H-05 | Dead-letter retention: 30 days in 4F; 90 days in 5I, 6A and 6J (which says the sources "agree exactly") | 4F §8.2 inv. 3 vs 5I §14, 6A §28.1, 6J §22.6 | 90 days | Phase 5 owns the data fact; 6A and 6J restate it | Note for 7L |
| CNF-7H-06 | `Retry-After` is "honored" yet "never extended beyond" the next backoff step | 6J §22.4 | `wait = min(step, max(jittered_wait, retry_after))`: it can only move the attempt later inside the jitter window, never past the step and never earlier (XRT-06) | Only reading under which both clauses have effect | None |
| CNF-7H-07 | `FAILED` is a legal delivery status and 6M reads `status = 'FAILED'`, but no function sets it | `chk_wd_status`; 6M §55 vs `063_5I` functions | 7H defines no transition into `FAILED`. A failed attempt returns the row to `PENDING` or ends in `DEAD_LETTER`. The 6M "failed" view returns no rows in V1 | Frozen functions are the only writers | Note for 7L / 6M |
| CNF-7H-08 | Stored response preview: "first 2KB" in 6A; 512 characters in 4F, 5I and the DB CHECK | 6A §28.1 vs `chk_wd_preview_length` | 512 characters | DB CHECK | Note for 7L |
| CNF-7H-09 | 6J states inbound `FAILED` is terminal and processing is a CAS; the frozen function re-transitions a `FAILED` row and returns no claim result | 6J §24.4, 7D PCI-13 vs `fn_update_inbound_event_status` (`062_5I`) | Duplicate processing is prevented by the owning domain's guards, not by the status function. Stale-row recovery needs MR-7H-09 | 7F Pattern A (domain-owned idempotency) | SCHEMA GAP |
| CNF-7H-10 | `plugin_executions.idempotency_key` exists, but no frozen contract says an idempotency key is transmitted to the plugin | `065_5I` vs 6J §25, §30.5 | 7H transmits nothing new. Ambiguous plugin timeouts are not auto-retried (PLG-07) | 6J §30.5; 6A §21 | NOT SPECIFIED; HE-7L-7H-04 |
| CNF-7H-11 | HTTP method and `Content-Type` of a webhook delivery are not stated | 6J §20 – §21 | `POST`, `Content-Type: application/json; charset=utf-8` (HTP-01) | The envelope is JSON; the signature covers the raw body | None |
| CNF-7H-12 | 7B WHT-05 cites NAM-F-05 for the `lead.*` mapping; the matching rule is NAM-F-07 | 7B §18.2 vs §10 | Read as NAM-F-07 | Editorial | Note for 7L |
| CNF-7H-13 | Organization status is `ACTIVE / SUSPENDED / DELETED` in 4A and `ACTIVE / SUSPENDED / CANCELLED` in the database | 4A §3 vs `003_5B` `chk_orgs_status`, `105_5B4` | Database vocabulary: `CANCELLED` is the terminal state | Phase 5 owns the data fact | None |
| CNF-7H-14 | 7D requires callback recovery to process "the stored, already-verified record", and 6J acknowledges before normalization; the frozen receipt row stores identifiers only and the raw payload is not retained | 7D REC-04, PCI-13, PCI-25; 6J §24.1, §24.4, §40.4 vs `062_5I` `inbound_webhook_events` columns; contrast `102_5H2` `payment_webhook_receipts` | A minimal verified, normalized processing input is committed with the receipt before the 2xx (§11.2, §11.3). Extraction of that input moves before the acknowledgement; full domain processing stays after it. Raw payload still not retained | OD-7H-08 | Erratum ERR-7H-05 to 6J §24.1 / §24.4; SCHEMA GAP MR-7H-09 |
| CNF-7H-15 | The replay function accepts a replay as a parent, the 10-per-24-hour quota is per delivery and outside the function, and each replay restarts retention | 6J §23.3, §22.6 vs `fn_replay_webhook_delivery` (`063_5I`, `101_5I1`) | Lineage quota and lineage window enforced inside the function (§13.5.1) | OD-7H-10 | Errata ERR-7H-01 (extended), ERR-7H-06; SCHEMA GAP MR-7H-08 |
| CNF-7H-16 | A plugin rate limit is required, in Redis, with no stated behaviour when Redis is unreachable | 6J §25.3, §16.1 row 4; 4F §9.3; 3E §16 | Refuse the callout (PLG-15) | OD-7H-11 | Erratum ERR-7H-08 to 6J §25.3 |
| CNF-7H-17 | Receivers deduplicate on the event ID; a successor topic would deliver a second body with the same event ID to an endpoint subscribed to both | 6J §21.2 rule 4 vs AVS CM-WH-02, CM-WH-05 | No successor topic exists. 7H defines **no** dual delivery and records the constraint the future governed change must settle (VER-7H-06) | Not decidable in 7H without changing a frozen receiver rule | HE-7L-7H-06 |
| CNF-7H-18 | 6J and AIR label endpoint creation and update audit "Async"; 7D requires every such mandatory audit to be written in the originating business transaction | 6J §36.2; AIR §18.1 (AMI-6J-018, 020 … 023 `AUDIT_ASYNC`) vs 7D §36 AUD-7D-01, AUD-7D-02, AUD-7D-07 (OD-7D-02 = A) | Same transaction (DST-05). 7H correlates by `config_revision`, so its evidence holds under either reading (DST-08) | 7D is the later frozen source and an owner decision on exactly this point | Documentation alignment already owed as 7D IO-7D-16; noted for 7L |
| CNF-7H-19 | 6J describes a zero-grace rotation as an "immediate hard cutover" and says the worker "checks the expiry on every send"; an asynchronous sender cannot make a database change take effect at the instant bytes leave the host | 6J §21.1, §21.3 vs 6A §35, 7A PR-06 | Coherent revision at admission, last-instant re-check, hard bound of 6 s, stated residual (SIG-14 … SIG-16) | OD-7H-12 | Erratum ERR-7H-09 |
| CNF-7H-20 | The 6J retry table classifies receiver and network outcomes only; it does not say whether a claim that ends without any request spends an attempt | 6J §22.3, §22.4 | Counted, with its own category and origin; one uncounted re-admission after a configuration change (HTP-18, HTP-19) | OD-7H-13, OD-7H-15, OD-7H-18 | Erratum ERR-7H-10 |
| CNF-7H-21 | The 20-endpoint limit is a product-configurable placeholder with no stated enforcement point; the schema has no constraint | 6J §45.2 vs `062_5I` | The automatic bound is stated as 10 × N, and as 200 only under authoritative enforcement (§20.2) | Minor-7H-R03 | IO-7H-17; note for 7L |
| CNF-7H-22 | 6J requires both signatures for the whole grace and forbids signing with an expired previous secret, but states neither how an asynchronous sender establishes "not yet expired" at hand-off nor what happens when the previous secret cannot be resolved while it is still required | 6J §21.1, §21.3, ADR-6J-07 vs 6A §35, 7A PR-06 | The full grace is honoured, tested on the database clock at the final re-check with a remaining-time hand-off guard (SIG-06, SIG-07); a required but unresolvable previous secret is a `NOT_SENT` failed attempt, never a current-only send (SIG-18) | OD-7H-16, OD-7H-17 | Errata ERR-7H-09 and ERR-7H-10, both revised |

---

## 2. Scope and Exclusions

### 2.1 In scope

1. The boundary between internal events, public outbound webhooks, inbound provider callbacks and plugin callouts (§3, §4).
2. Which internal events are externally eligible, and the public projection of each (§5, §15).
3. Subscription and destination lifecycle, and the moment each becomes authoritative (§6).
4. Durable fan-out, idempotency and the delivery state machine (§7, §8).
5. The public HTTP protocol, signing preservation and credential separation (§9, §10).
6. The provider-callback trust boundary and the plugin-callout bridge (§11, §12).
7. Retry, terminal handling and replay, reconciled with 7G (§13).
8. Tenant isolation, outbound network controls, privacy baseline (§14).
9. Ordering and contract-generation compatibility (§16).
10. Persistence capability, schema gaps and activation blockers (§17).
11. Deterministic recovery traces (§18); telemetry contract (§19); commercial constraints (§20).
12. Matrices A – J (§21); owner decisions (§22); handoffs (§23); adversarial review (§24); freeze evidence (§25).

### 2.2 Exclusions

| Not defined or changed by 7H | Owner |
|---|---|
| Event names, classes, producers, consumers | 7B |
| Internal envelope, schema versions, compatibility policy | 7C |
| Outbox, relay, publication | 7D |
| Streams, groups, route registry, acceptance | 7E |
| Consumer transaction, guards, `XACK` contract, handler-contract generations | 7F |
| Consumer retry budget, parking ledger, internal replay modes R1 – R6 | 7G |
| Public routes, permissions, error codes, the signing scheme, the topic catalog | 6J, 6A, 6B, AEC, AVS |
| Telephony provider adapter internals, Exotel wire format, call admission | 6D, Phase 9 |
| Payment-provider settlement | 6K, Phase 20 |
| Field-level classification, redaction, DSR interaction, final roles and grants | 7I |
| Metric names, dashboards, alert thresholds, SLOs | 7J |
| Worker counts, concurrency values, fairness mechanism, regional topology | 7K |
| A plugin runtime, a marketplace, any in-process plugin code | Not in V1 (6J §25.1, J3) |
| Any new microservice | Prohibited: modular monolith (7A OWN-03; 6J L58) |

---

## 3. Terminology and External-Delivery Responsibilities

### 3.1 Nine identities that are never conflated

| Identity | What it names | Physical carrier | Stable across | Changes when |
|---|---|---|---|---|
| **Event identity** | One committed business fact | `audit.domain_event_outbox.id` = internal `event_id`; copied to `webhook_deliveries.event_id` | Relay retry, redelivery, internal replay, every delivery, every attempt, every public replay | Never (7A EVT-02) |
| **Endpoint identity** | One tenant destination resource | `webhooks.webhook_endpoints.id`; copied to `webhook_deliveries.webhook_endpoint_id` (immutable) | Edits of URL, topics, secret, status | Never. A "new destination" is a new endpoint row |
| **Subscription** | The fact that an endpoint lists a topic | The `topics TEXT[]` value of the endpoint row. There is no subscription row and no subscription version column | — | A `PATCH` of `topics` |
| **Delivery identity** | One obligation to deliver one event to one endpoint | `webhook_deliveries.id` (with partition key `created_at`); public `X-Platform-Delivery-Id` | Every claim and every attempt of that delivery | A public replay creates a new delivery with `replay_of_delivery_id` |
| **Replay lineage identity** | The family of one fan-out (or test) delivery and every replay descended from it | The lineage root's delivery ID, recorded on every descendant and on a lineage anchor (MR-7H-08). Absent from the frozen schema | Every replay generation | Never |
| **Claim identity** | One period during which one worker owned the delivery | (`delivery_id`, `claim_seq`). `claim_seq` is 1, 2, 3 … per delivery, assigned by the claim under the delivery's row lock (MR-7H-02). Absent from the frozen schema | — | Every claim, whether or not anything was sent |
| **Admission identity** | One final pre-send authorization within a claim | (`delivery_id`, `claim_seq`, `admission_seq`), with `admission_seq` 1 or 2 (HTP-18; MR-7H-06). Absent from the frozen schema | — | The single permitted re-admission after a configuration change |
| **Configuration revision** | One state of an endpoint's delivery configuration: URL, timeout, both signing-secret references, previous-secret expiry | (`endpoint_id`, `config_revision`), increased in every transaction that changes one of them (§14.5.1; MR-7H-11). Absent from the frozen schema | Every attempt admitted under it | Every such change |
| **Attempt identity** | One HTTP request that was made, or may have been made | (`delivery_id`, `attempt_number`). `attempt_number` is the value of `attempt_count` **after** the increment that the closing of a claim performs. It is assigned when a claim is closed, never when it is opened. Internal only | — | Every closure that spends the budget |

**TRM-01 [7H].** No document, log field, metric or API field may use "event" to mean a delivery or an attempt, "delivery" to mean an attempt, or "attempt" to mean a claim.

**TRM-02 [FROZEN / 7H].** The frozen schema has no subscription identity, no subscription version and no endpoint configuration version (`062_5I`, `101_5I1`; ADR-6A-08). 7H introduces no subscription version: "subscription version" here means "the `topics` value visible to the fan-out transaction's snapshot". 7H does require a future internal `config_revision` for the endpoint's delivery configuration (MR-7H-11). It identifies configuration states for coherence and evidence. It does **not** pin a delivery to a configuration, so OD-7H-01 = A is unchanged: a pending delivery still follows the endpoint's current configuration.

**TRM-03 [7H].** A claim is not an attempt. A claim that ends without the budget being spent (the organization was not `ACTIVE` at admission) has a claim identity and **no** attempt identity. While a claim is open, every log line and span refers to (`delivery_id`, `claim_seq`); an `attempt_number` exists only once the claim has been closed. The earlier draft's definition, "`attempt_count` before the attempt + 1", is withdrawn: it gave two different claims the same attempt number (P1-7H-R04, §26.4).

### 3.2 Components (logical; all inside the modular monolith)

| ID | Component | Owning context | Runs as | Defined by |
|---|---|---|---|---|
| CMP-01 | Webhook fan-out consumer | Integrations (6J) | Durable consumer of group `cg.integrations.webhook-engine` (CON-10) | 7F §28.11; §7 here |
| CMP-02 | Projection registry and per-topic serializers | Integrations (6J), with read ports provided by each producing context | In-process library used by CMP-01 and the test route | 6J §20.2, §40.1; §5.3, §15 here |
| CMP-03 | Delivery dispatcher | Integrations (6J) | Worker (7B TSK-15) | 6J §22; §8, §9 here |
| CMP-04 | Delivery maintenance sweeps (stale-claim release, hold expiry, cancellation of deliveries of a `CANCELLED` organization) | Integrations (6J) | Scheduled worker | §8.4 here |
| CMP-05 | Egress-control adapter | Integrations (6J); shared library | In-process port | 6J §30.3, ADR-6J-06 |
| CMP-06 | Provider-callback ingress | The owning context of each route: Voice (6D-021), Integrations (6J-014), Billing (6K-023) | HTTP route | 6J §24; 6D §10.4; 6K §30 |
| CMP-07 | Inbound processor and inbound recovery sweep | Same owning contexts | Worker | 7D PCI-13, 25, 28; §11 here |
| CMP-08 | Plugin callout executor | Integrations (6J); invoked in-process by the Workflow / tool runtime | In-process port | 6J §30.4 |

**CMP-R1 [FROZEN].** None of these is a separately deployed service. A bounded context is a contract boundary, not a deployment boundary (7A OWN-03).

---

## 4. Logical Architecture and Bounded-Context Ownership

### 4.1 Boundary diagram

```
                         PLATFORM TRUST BOUNDARY
 ┌───────────────────────────────────────────────────────────────────────────────┐
 │                                                                               │
 │  Owning context (Voice / CRM / Campaign / Billing)                            │
 │   one short PostgreSQL transaction: state change + outbox row   [7D]          │
 │        │ COMMIT                                                               │
 │        ▼                                                                      │
 │   Relay ──► Redis Streams (transport only)                      [7D, 7E]      │
 │        │                                                                      │
 │        ▼                                                                      │
 │   CMP-01 fan-out consumer (cg.integrations.webhook-engine)      [7F CON-10]   │
 │     one PostgreSQL transaction, tenant context from envelope:                 │
 │       fan-out claim  +  one webhook_deliveries row (PENDING)                  │
 │       per endpoint ACTIVE and subscribed in that snapshot                     │
 │        │ COMMIT, then XACK                                                    │
 │        ▼                                                                      │
 │   CMP-03 dispatcher: claim ─► load ─► [no transaction] HTTPS ─► record        │
 │        │                         via CMP-05 egress adapter                    │
 └────────┼──────────────────────────────────────────────────────────────────────┘
          │  A. PUBLIC WEBHOOK  (platform signs: webhook canonical input)
          ▼
   Tenant-owned HTTPS endpoint (untrusted destination)


   External provider (Exotel, payment, integration)        untrusted source
          │  B. PROVIDER CALLBACK  (provider signs: provider-native scheme)
 ┌────────▼──────────────────────────────────────────────────────────────────────┐
 │  CMP-06 ingress: verify ─► resolve tenant from platform state ─► dedup row    │
 │                  + minimal normalized processing input (one transaction)      │
 │                  ─► 2xx fast ACK                                              │
 │  CMP-07 processing: owner ACL ─► owner transaction (state + outbox row)       │
 │        └──────────────► joins the top of this diagram as an ordinary event    │
 │                                                                               │
 │  Workflow / tool runtime ─► CMP-08 plugin callout executor ─► CMP-05          │
 └────────┬──────────────────────────────────────────────────────────────────────┘
          │  C. PLUGIN CALLOUT  (platform signs: plugin canonical input)
          ▼
   Plugin developer's HTTPS service (untrusted destination)
```

**BND-01 [FROZEN].** A, B and C are three contracts with three canonical signing inputs, three credential namespaces and three failure models (6A §28.3; 7A PR-04, WH-10; AVS SG-06). No shared "generic signature policy" exists.

**BND-02 [FROZEN].** A provider callback never becomes a tenant webhook directly. It can only cause an owner state change whose outbox row then travels the normal path (7A CB-05; 7B §19; 7C PCV-02, PCV-03).

**BND-03 [FROZEN].** An internal event is not customer-visible by default. Only the 19 governed topics are externally eligible (7A WH-04; 6J §19.1).

**BND-04 [7H].** No plugin is notified of internal events in V1. No frozen source defines a plugin event subscription (§12.1).

### 4.2 The end-to-end flow, arrow by arrow

Each arrow lists the ten required facts. "Ack safe?" answers whether the upstream party may treat its obligation as discharged once the arrow completes.

| # | Arrow | 1 Owner | 2 Data | 3 Durability boundary | 4 Auth / tenant boundary | 5 Transaction guarantee | 6 Idempotency | 7 Retry owner | 8 On crash | 9 Ack safe? | 10 Frozen source |
|---:|---|---|---|---|---|---|---|---|---|---|---|
| F1 | Domain action → domain transaction | Producing context | Command | None yet | Authenticated principal; `app.tenant_id` set from the verified credential | — | Route `Idempotency-Key` where the route requires it | Caller | Nothing committed | No | 6A §16, §23, §35 |
| F2 | Domain transaction → outbox row | Producing context | State change + one outbox row | **PostgreSQL commit** | `trg_outbox_tenant_check` | State and row commit together or not at all | One fact, one row (7D §11) | None: rollback leaves nothing | Rolled back; no event exists | Yes: the HTTP response may be sent after commit | 7A DUR-01; 7D §10 |
| F3 | Outbox → Redis publication | Relay (7D) | Materialized internal envelope | Outbox row stays until `PUBLISHED`; Redis acceptance per 7E §23 | Relay role; no tenant payload interpretation | Claim → publish → mark, three steps, no transaction across Redis | Stable `event_id`; duplicates expected | Relay; terminal `FAILED` per 7G §27 | Lease expires; another relay republishes | Mark-published only after `CONFIRMED` | 7D §15 – §26; 7E §23 |
| F4 | Redis → fan-out consumer | CMP-01 | Stream entry | The pending-entry list of the group | Tenant context established from the trusted envelope `organization_id` (7F §30) | None across Redis and PostgreSQL | See F5 | 7G R1 reclaim; budget OD-7G-01 | Entry stays pending; reclaimed | No | 7F §11, §12; 7G §12 – §14 |
| F5 | Consumer → subscription eligibility → durable delivery intent | CMP-01 | Fan-out claim + delivery rows | **PostgreSQL commit** of claim and all rows | RLS with the envelope's tenant; endpoints of that organization only | One transaction (7F TXA; MHO-01) | Fan-out claim, primary-key backed (MR-7H-01) | 7G | Rolled back; entry redelivered; claim absent, so fan-out runs once | **`XACK` only after this commit** (INV-ACK) | 7F §28.11, XAK-01; 7G RTY-10 |
| F6 | Delivery intent → dispatch admission | CMP-03 | Claimed delivery identity; then the destination attributes | Claim: row moves `PENDING → DELIVERING`, `claim_seq + 1`, claim record. Admission: admission record with the destination fingerprint, committed **before** any byte is sent | Claim is cross-tenant by design and share-locks each organization row (ADM-01); the returned `organization_id` sets the tenant context for the later steps; admission re-checks the organization under the same lock and reads the endpoint row under its own share lock (ELK-01) | Two short transactions (claim; admission), neither open during HTTP | Fence = `claim_seq` | CMP-04 stale-claim release | Row stays `DELIVERING` until the lease expires, then is released | n/a | `063_5I`; MR-7H-02, MR-7H-03, MR-7H-06 |
| F7 | Dispatch → HTTPS attempt | CMP-03 via CMP-05 | Exact stored body bytes + headers, to exactly the admitted destination | None: the network is not durable | TLS to the pinned, validated address; signature is the authentication | **No transaction open**; must start within `T_admit` of admission | Receiver deduplicates on event ID | CMP-03 schedule | Outcome unknown; see F8 | n/a | 6A §35; 6J §21, §30.3 |
| F8 | Attempt → outcome recording | CMP-03 | Classified outcome | **PostgreSQL commit** of the fenced closure, which assigns the attempt number | Tenant context of the delivery | One short transaction | Fence: a late or duplicate report changes nothing | CMP-04 if the record is lost | Stale-claim release spends one attempt (OD-7H-05); a duplicate HTTP request is possible | n/a | `063_5I`; MR-7H-03, MR-7H-06 |
| F9 | Outcome → retry or terminal | CMP-03 / CMP-04 | `next_attempt_at` or terminal status | Same commit as F8 | — | DB forces `DEAD_LETTER` at `max_attempts` | — | Bounded by `max_attempts` ≤ 10 | — | n/a | `fn_delivery_failed` (FIX-02) |
| F10 | Terminal → audit and observability | Integrations | Audit rows for privileged and system actions; telemetry for attempts | Audit row in the same transaction where the frozen contract makes it synchronous | — | 6J §36 synchrony per action | — | 7D OD-7D-02 for async audit | Recovered per 7A AUD-04a | n/a | 6J §36; 7A §19 |

### 4.3 The acknowledgement invariant

**INV-ACK [FROZEN, restated as binding for 7H].** The fan-out consumer issues `XACK` for an entry only after one PostgreSQL transaction has durably committed (a) the fan-out claim for that event and (b) every delivery row owed in that snapshot, or after it has proven from a visible claim row that this already happened (7F §28.11 "ACK success condition", "ACK-on-duplicate condition"; XAK-01; MHO-01 … MHO-03; 7G RTY-10).

Proof that no acknowledged event lacks its intents:

1. The only code path to `XACK` passes the commit of F5 or the duplicate proof.
2. The claim and the rows are in one transaction, so "claim present" implies "rows present" for the snapshot that transaction saw.
3. A zero-match fan-out still commits the claim, so "no endpoint matched" is a recorded outcome, not an absence (7F §28.11).
4. No delivery is created in process memory after `XACK` (7F MHO-03).

**INV-NOSPAN [FROZEN].** No single transaction spans PostgreSQL and Redis, or PostgreSQL and the remote HTTP call (7A PR-06, DUR-04; 6A §35; 7F EXT-01). F5, F6, F8 are separate short PostgreSQL transactions; F4 and F7 hold none.

**INV-NOEXACT [FROZEN].** Nothing in this document claims exactly-once delivery or processing across PostgreSQL, Redis, HTTP and a customer system (7A DEL-04; 6J §22.1).

---

## 5. Internal-to-External Event Eligibility

### 5.1 Externalization policy

| ID | Rule |
|---|---|
| ELG-01 [FROZEN] | An internal event is externally eligible only if a governed webhook topic maps to it. The catalog is the 19 topics of 6J §19.1 / 4F §8.4, plus the synthetic `platform.test` (6J §18.10). 7H adds none. |
| ELG-02 [FROZEN] | The topic is a Published-Language projection of the canonical event. It is not a new event, and the internal name is never exposed where it differs (7B §18; NAM-02). |
| ELG-03 [FROZEN] | `integration.*`, `plugin.*`, `webhook.*` and every other internal event are internal-only (7B Rule G-1; 6J §50). `webhook.delivery_*` meta-events are never webhook-eligible. |
| ELG-04 [7H] | Eligibility is decided from a code-owned **topic map**: exact pairs (`event_type`, `event_version`) → (`topic`, `topic version`, serializer). It has no wildcard, prefix or family entry (same discipline as 7C CSR-09 and 7F REG-7F-02). An internal pair absent from the map produces no delivery. |
| ELG-05 [7H] | The topic map is evaluated only inside the fan-out transaction of CMP-01, for an entry the 7F pipeline has already classified as owed. It never decides whether the group owes the event: that is `A(g, E)` (7F §10.4). |
| ELG-06 [FROZEN] | Platform-scoped events (no `organization_id`) are never delivered as webhooks (6J §20.1: `organization_id` "always present"). All 19 source events are organization-scoped (7C TEN-C03 on each binding). |
| ELG-07 [7H] | No suppression rule exists in V1 beyond endpoint status and organization status (§14.2). No frozen contract makes any of the 19 topics conditional on DNC or consent state; see §14.3. |
| ELG-08 [FROZEN] | Delivery guarantee for every eligible topic is at-least-once under the 6J retry contract (7A §20.2 row G). |

### 5.2 Matrix B — Internal event → external delivery eligibility

Columns common to every row and therefore not repeated: eligible principals = the organization that owns the event, through endpoints it configured; subscription capability = topic listed in the endpoint's `topics`; configuration permission = `webhook:manage`, read = `webhook:read` (6J §18, §32); tenant check = fan-out runs under the envelope's tenant context and matches only that organization's endpoints; guarantee = at-least-once; public replay = 6J §23.3; internal replay = guarded by the fan-out claim (§13.6); audit = privileged and system actions only (§14.6), an ordinary delivery writes no audit row.

| WHT | External topic (v1) | Internal event (v1) | Producer | Class | Mapping source | Sensitivity (6J §19.1) | Suppressible? | In CON-10 `H_active` gen 1? |
|---|---|---|---|---|---|---|---|---|
| 01 | `call.started` | EV-004 `call.initiated` | Voice 6D | A | 4F §8.4; CNF-7H-04 | No | No | **No** — AB-7H-03 |
| 02 | `call.completed` | EV-005 `call.ended` | Voice 6D | A | 4F §8.4; 4I L1402 | No (references only) | No | **No** — AB-7H-03 |
| 03 | `call.failed` | EV-006 `call.failed` | Voice 6D | A | 7B | No | No | Yes |
| 04 | `call.transferred` | EV-075 `call.transferred` | Voice 6D | C | 7B | No | No | Yes |
| 05 | `lead.created` | EV-021 `contact.created` | CRM 6G | A | 6J, 6G §30; CNF-7H-03 | Yes | No | Yes |
| 06 | `lead.qualified` | EV-024 `contact.qualified` | CRM 6G | A | 6J, 6G | Yes | No | Yes |
| 07 | `lead.disqualified` | EV-025 `contact.disqualified` | CRM 6G | A | 6J, 6G | Yes | No | Yes |
| 08 | `deal.created` | EV-035 | CRM 6G | A | 7B | Possibly | No | Yes |
| 09 | `deal.won` | EV-037 | CRM 6G | A | 7B | Possibly | No | Yes |
| 10 | `deal.lost` | EV-038 | CRM 6G | A | 7B | Possibly | No | Yes |
| 11 | `appointment.booked` | EV-046 | CRM 6G | A | 7B | Yes | No | Yes |
| 12 | `campaign.started` | EV-084 | Campaign 6H | C | 7B | No | No | Yes |
| 13 | `campaign.completed` | EV-085 | Campaign 6H | C | 7B | No | No | Yes |
| 14 | `campaign.contact.qualified` | EV-091 | Campaign 6H | C | 7B | Yes | No | Yes |
| 15 | `invoice.created` | EV-102 `invoice.generated` | Billing 6K | C | 6K §45.1 | Financial | No | Yes |
| 16 | `invoice.paid` | EV-103 | Billing 6K | C | 6K §45.1 | Financial | No | Yes |
| 17 | `payment.failed` | EV-104 | Billing 6K | C | 6K §45.1 | Financial | No | Yes |
| 18 | `usage.threshold_reached` | EV-105 | Billing 6K | C | 6K §45.1 | No | No | Yes |
| 19 | `subscription.changed` | EV-071 | Billing 6K | A | 6K §45.1 | No | No | Yes |
| — | `platform.test` | none (synthetic; no outbox row) | Webhooks 6J route 6J-025 | G | 6J §18.10 | No | n/a | n/a |

Every other catalogued event (the remaining 86 of 7B's 105, every Class D signal and every Class F message) is **internal-only**. In particular `agent.*`, `workflow.execution.*`, `document.*`, `knowledge_base.*`, `conversation.*`, `recording.*`, `tool_execution.*`, `organization.*`, `identity.*`, `integration.*`, `plugin.*` and `webhook.*` have no topic (6J §19.1 "not currently in the governed catalog"; 6C §20 "internal bus only"). Compliance-family events (consent, DNC, suppression) have no topic: NOT FOUND in 6J §19.1.

### 5.3 Public projection — V1 `data.object` baseline (OD-7H-07 = minimal)

| ID | Rule |
|---|---|
| PRJ-01 [FROZEN] | `data.object` is built by a per-topic serializer that is an explicit allow-list. It is never a row dump and never the internal envelope or payload forwarded verbatim (6J §20.2, §40.1; 7A WH-05; 7C WSB-04, WHB-05). |
| PRJ-02 [OD] | The V1 baseline contains only: identifiers, timestamps, enums / codes and amounts taken from the frozen 7C V1 payload, plus fields that a frozen contract names explicitly (6J §20.1 example, 6J §40.2, 6K §45.1). Free-text fields are excluded. |
| PRJ-03 [7H] | A field a frozen contract names but the internal payload does not carry is obtained through a **projection read port** provided by the producing context, called in-process inside the fan-out transaction under the event's tenant context. It reads only the allow-listed columns of the one resource the event identifies. It is a database read, not network I/O (7F §26 treats owner in-process reads the same way). |
| PRJ-04 [7H] | Port-read fields reflect the owner's state **at fan-out time**, not at event time, and are then frozen into `payload_json`. Retries and public replays resend those bytes unchanged. Every port-read field is declared nullable; if the resource or value is not visible, the field is `null` and the delivery is still created. |
| PRJ-05 [7H] | Adding a field later is an additive change (AVS CM-WH-01, non-breaking). Removing or repurposing one is prohibited without a successor topic (CM-WH-02, CM-WH-03). This is why the baseline starts minimal. |
| PRJ-06 [FROZEN] | Never present in any body: transcripts, recordings, call content, signed or presigned URLs, secrets or secret references, provider transaction IDs, raw provider error text, GSTIN / address snapshots, provider cost, margin, internal function names, `webhook_endpoint_id`, `attempt_count`, `claimed_by`, `payload_hash` (6J §20.2, §39, §40; 6K §45.1; 7A SEC-01, SEC-04, BIL-05). |
| PRJ-07 [LATER] | 7I may **narrow** this baseline before activation after field-level classification (7B IO-7B-07). It may not widen it without the additive-change process. |
| PRJ-08 [7H] | **Money and decimals.** The internal `money` type is one object, `{"amount": "<decimal, scale 4>", "currency": "<ISO-4217>"}`, nullable only as a whole (7C §18). No internal payload has a top-level `currency` key. A monetary or decimal value is always rendered publicly as a **JSON string** holding the plain decimal with exactly four fractional digits (`"1234.5000"`): never a JSON number, never an exponent, never rounded or re-scaled. A currency is a JSON string of three upper-case letters. Counts and durations (`duration_seconds`, `total_contacts`, `attempted`) are JSON integers. Where a frozen public contract names an amount and its currency as two keys (6K §45.1), the amount key takes the `amount` member and the `currency` key takes the `currency` member **of the same money object**; the two are present together or `null` together. Where no frozen contract splits them (`deal.won`), the money object is forwarded unchanged, or `null` as a whole. |

| Topic | `data.object` fields (V1) | From internal payload | From projection read port | Explicitly excluded from the payload |
|---|---|---|---|---|
| `call.started` | `call_id`, `direction` | both | — | `from_number`, `to_number` (6J marks the topic non-sensitive), `agent_version_id`, `campaign_lead_ref` |
| `call.completed` | `call_id`, `status`, `duration_seconds`, `direction` (exactly the 6J §20.1 example) | `call_id`, `duration_seconds` | `status`, `direction` (`voice.call_sessions`) | `outcome` (additive later) |
| `call.failed` | `call_id`, `failure_reason` (open code), `failed_at` | all | — | — |
| `call.transferred` | `call_id`, `transfer_confirmed_at` | all | — | transfer target (not bound in V1) |
| `lead.created` | `contact_id`, `phone_number`, `name`, `email`, `source` | `contact_id`, `phone_number` (= `phone_e164`), `source` | `name`, `email` (6J §40.2 "where captured") | `campaign_ref` |
| `lead.qualified` | `contact_id`, `phone_number`, `name`, `email` | `contact_id` | `phone_number`, `name`, `email` | `qualification_reason`, `qualified_by` |
| `lead.disqualified` | `contact_id` | `contact_id` | — | `qualification_reason`, `disqualified_by` (6J §40.2 lists no contact fields for this topic) |
| `deal.created` | `deal_id`, `contact_id`, `pipeline_id` | all | — | deal title |
| `deal.won` | `deal_id`, `contact_id`, `value` (`amount`, `currency`; nullable as a whole), `closed_at` | all | — | — |
| `deal.lost` | `deal_id`, `contact_id` | both | — | `lost_reason` |
| `appointment.booked` | `appointment_id`, `contact_id`, `scheduled_start`, `scheduled_end`, `phone_number`, `name` | first four | `phone_number`, `name` (6J §40.2) | `organizer_ref`, title, location |
| `campaign.started` | `campaign_id`, `total_contacts` | both | — | `agent_version_id` |
| `campaign.completed` | `campaign_id`, `completed_at`, `total_contacts`, `attempted` | all | — | — |
| `campaign.contact.qualified` | `campaign_contact_id` (= aggregate ID), `campaign_id`, `contact_id`, `call_id` | all | — | `qualification_reason` |
| `invoice.created` | `invoice_id`, `invoice_number`, `total_due`, `currency`, `status` (exactly 6K §45.1) | `invoice_id`; `total_due` ← `total_due.amount`; `currency` ← `total_due.currency` (the internal `total_due` is a NON-NULL money object, 7C EV-102) | `invoice_number`, `status` | `billing_account_id`, `billing_period_id`, `period_start`, `period_end`, tax snapshot |
| `invoice.paid` | `invoice_id`, `invoice_number`, `total_due`, `currency`, `status` (exactly 6K §45.1) | `invoice_id` (the internal payload carries `paid_at` and the money object `amount_paid`, not `total_due`; 7C EV-103) | `invoice_number`, `status`, and `total_due` + `currency` from `billing.invoices.total_due_amount` / `total_due_currency`, rendered per PRJ-08 | `amount_paid`, `paid_at` (additive later) |
| `payment.failed` | `payment_attempt_id`, `invoice_id`, `failure_code` (exactly 6K §45.1) | all | — | `payment_provider`, provider transaction ID, failure message |
| `subscription.changed` | `subscription_id`, `status`, `old_plan_version_id`, `new_plan_version_id` | all | — | — |
| `usage.threshold_reached` | `metric`, `threshold`, `period_start` | all | — | current usage, hard limit |
| `platform.test` | `message`, `triggered_by` (fixed text per 6J §18.10) | n/a | n/a | — |

Public field names follow the frozen text where one exists (`phone_number`, `name` in 6J §19.1; billing names in 6K §45.1; call names in the 6J §20.1 example) and otherwise reuse the frozen 7C payload key unchanged.

**Requiredness and nullability of the billing topics.** Every key listed for a topic is always present in `data.object`; a value that is unavailable is `null`, never omitted.

| Topic | Key | JSON type | Nullable | Source |
|---|---|---|---|---|
| `invoice.created`, `invoice.paid` | `invoice_id` | string (UUID) | No | internal payload |
| | `invoice_number` | string | Yes (port read) | `billing.invoices` |
| | `total_due` | string, decimal scale 4 | `invoice.created`: No. `invoice.paid`: Yes (port read) | PRJ-08 |
| | `currency` | string, 3 upper-case letters | Null exactly when `total_due` is null | PRJ-08 |
| | `status` | string (invoice status code) | Yes (port read) | `billing.invoices` |
| `payment.failed` | `payment_attempt_id`, `invoice_id` | string (UUID) | No | internal payload |
| | `failure_code` | string (open code) | Yes (7C EV-104: NULLABLE) | internal payload |
| `usage.threshold_reached` | `metric` | string (open code) | No | internal payload |
| | `threshold` | string, decimal scale 4 | No | internal payload |
| | `period_start` | string (date) | No | internal payload |

No topic carries a provider cost, a margin, a tax line, a GSTIN, an address snapshot, a provider transaction ID or raw provider error text (PRJ-06).

---

## 6. Subscription and Destination Lifecycle

### 6.1 Ownership and configuration (all [FROZEN]: 6J §18, §21.3, §32; `062_5I`; `101_5I1`)

| Concern | Contract |
|---|---|
| Owner | The organization. `webhook_endpoints.organization_id` NOT NULL; RLS `rls_we_tenant`, forced |
| Configuration actors | Principals holding `webhook:manage` (create, patch, enable, disable, delete, rotate, test); `webhook:read` to list and read. The registering user is recorded in `created_by_ref` and has no continuing role |
| Event selection | `topics TEXT[]`, non-empty; each value validated against the 19-topic catalog at the application layer (`422 WEBHOOK_TOPIC_INVALID`) |
| Endpoint validation | `https://` only (DB CHECK); full egress validation at registration and on every `PATCH` of `target_url` (`422 WEBHOOK_URL_UNSAFE`) |
| Activation | A created endpoint is `ACTIVE` immediately |
| Verification | **NOT SPECIFIED.** `endpoint_verified_at` exists and no frozen flow sets it. 7H defines no verification gate; the column stays NULL in V1. The test route (6J §18.10) is the tenant's verification tool |
| Limits | 20 endpoints per organization (placeholder default, 6J §45.2); 19 topics maximum per endpoint |
| Enable / disable | Ordinary UPDATE of `status`; `disabled_at` set on disable |
| Deletion | `DELETE` is an alias of disable (ADR-6J-02). Hard deletion is platform-admin / compliance only and has no tenant route |
| System suspension | `SUSPENDED` exists; **no function reaches or leaves it** (DEP-6J-07, FUTURE — NON-BLOCKING). 7H activates no auto-suspension (§13.7) |
| Secret rotation | `fn_rotate_webhook_secret`: current → previous with expiry, new → current, one guarded call; grace 0 – 86400 s, default 3600 |
| Payload version | One version per topic (all 1). An endpoint selects a version only by subscribing to a topic string; a future `X.v2` is a different topic (AVS CM-WH-05) |

### 6.2 When each thing becomes authoritative

| ID | Rule |
|---|---|
| SUB-01 [FROZEN] | **Which endpoints receive an event** is decided once, in the fan-out transaction, from the endpoints of the event's organization that are `ACTIVE` and list the topic in that transaction's snapshot (6J §37.2; 7F §28.11). |
| SUB-02 [FROZEN] | A late, redelivered or internally replayed event is matched against the endpoints active **at processing time**. There is no historical matching (7F §28.11; 7G HE-7H-7G-02). Once the claim exists, no later processing of the same event re-matches at all, so an endpoint created afterwards never receives that event. |
| SUB-03 [FROZEN] | The **endpoint identity** and the **body** of a delivery are fixed at intent creation and are immutable (`fn_wd_identity_immutable`). `max_attempts` is copied from the endpoint at that moment and is not re-read. |
| SUB-04 [OD] | **Destination attributes are read live, as one coherent revision, at each admission** (OD-7H-01 = A; OD-7H-12). `target_url`, `timeout_ms`, `signing_secret_ref`, `previous_signing_secret_ref` and `previous_secret_expires_at` are read together, from one row version identified by its `config_revision`, in the admission transaction of every attempt (HTP-15), under a share lock on the endpoint row that serializes the read against every configuration change (ELK-01), and that revision is re-checked immediately before the request is signed (HTP-17). A delivery is bound to an endpoint resource, not to a URL string and not to a revision. |
| SUB-05 [7H] | A delivery never moves to a different **endpoint resource**. `webhook_endpoint_id` cannot change, and replay copies it. An edit of `target_url` is a documented, audited (`WEBHOOK_ENDPOINT_UPDATED`), egress-revalidated change to the same resource by a principal holding `webhook:manage`; remaining attempts of pending deliveries follow it. This is public behaviour, not a silent side effect, and it is recorded per attempt (SUB-06). |
| SUB-06 [7H] | Every admission records the `config_revision` it used and that revision's **keyed fingerprint of the complete effective destination** (scheme, host, port, path and query), committed before the request is sent (§14.5.1). The revision ties the attempt to the audited change that introduced the destination; the fingerprint shows what the destination was without storing it. The earlier scheme-host-port digest (first review) and the earlier correlation by audit time (second review) are both withdrawn (P1-7H-R05). It depends on MR-7H-06, MR-7H-10 and MR-7H-11. |

### 6.3 Lifecycle outcomes

| Situation | Outcome | Tag / source |
|---|---|---|
| Multiple endpoints subscribed to one event | One delivery row per endpoint, each with its own `id`, `request_id` and retry lifecycle, all with the same `event_id` | [FROZEN] 6J §37.2 |
| Duplicate registration (same URL and topics twice) | Two endpoints, two deliveries per event. No uniqueness constraint exists on (`organization_id`, `target_url`). The create route requires `Idempotency-Key`, which protects against request retries only | [FROZEN] `062_5I`; 6J §18.3 |
| Concurrent `PATCH` | `If-Match` required; one writer wins (6J §18.5) | [FROZEN] |
| `PATCH` of `topics` while an event is in flight | Decided by the fan-out snapshot (SUB-01). A topic removed before the snapshot: no delivery. Removed after: the delivery already exists and completes | [7H] from SUB-01 |
| `PATCH` of `target_url` with pending deliveries | Remaining attempts go to the new URL (SUB-04). An attempt admitted before the change whose re-check runs after it is not sent to the old URL; it is re-admitted once under the new revision (HTP-18). A change that commits after the re-check returned is the residual of SIG-15 | [OD] OD-7H-01, OD-7H-12, OD-7H-15 |
| Endpoint disabled (or `DELETE`) with pending or in-flight deliveries | They complete normally: retries continue to exhaustion or success. No new delivery is created | [FROZEN] 6J §18.8; 4F §8.1 inv. 3 |
| Endpoint disabled, then a public replay is requested | Rejected: `422 WEBHOOK_REPLAY_NOT_ALLOWED` | [OD] OD-7H-03; ERR-7H-01 |
| Endpoint not ACTIVE, test delivery requested | Rejected: `409 STATE_CONFLICT` | [OD] OD-7H-06; ERR-7H-02 |
| Endpoint row hard-deleted by the platform while deliveries are pending | The admission finds no endpoint row under the delivery's tenant context. The claim is closed as a failed attempt: `ENDPOINT_GONE`, `NOT_SENT`, origin PLATFORM, one attempt spent. The frozen schedule continues and the delivery reaches `DEAD_LETTER` only by exhaustion. No HTTP is sent and nothing is billable. There is no direct transition to `CANCELLED`. This applies only to a row actually removed by an authorized platform operation; a tenant's disable or `DELETE` leaves the row in place (see the disable row above). A replay of such a delivery is refused (`422 WEBHOOK_REPLAY_NOT_ALLOWED`) for as long as no endpoint exists to receive it | [OD] OD-7H-18; only exhaustion reaches `DEAD_LETTER` (6J §22.4) |
| Secret rotated while a delivery is pending | The next attempt is admitted under the post-rotation revision and signs with that revision's current secret, and also with its previous secret on every request handed to the network before `previous_secret_expires_at` (SIG-06) | [FROZEN] 6J §21.1; [OD] OD-7H-12, OD-7H-16 |
| A signing secret the attempt requires cannot be resolved | Failed attempt, `SECRET_UNAVAILABLE`, `NOT_SENT`, origin PLATFORM; one attempt spent. This holds for the current secret and equally for a previous secret whose grace is still running at the final re-check: the request is **not** sent current-only (SIG-18). Nothing is sent unsigned. A previous secret that is absent or expired is not required, and current-only is then correct | [OD] OD-7H-13, OD-7H-17 |
| Destination change during an internal replay | Not applicable: the claim prevents a second fan-out (SUB-02) | [FROZEN] |
| Destination change before a public replay | The replay goes to the same endpoint resource with its current attributes (SUB-04), if it is ACTIVE | [OD] |
| Organization suspended or cancelled | §14.2 | [OD] OD-7H-02 |
| The user who registered the endpoint is removed | No effect. The endpoint belongs to the organization; `created_by_ref` is historical | [FROZEN] ownership model |

---

## 7. Durable Fan-out and Idempotency

### 7.1 The fan-out transaction (CMP-01)

This restates the frozen CON-10 card (7F §28.11) and adds only the steps 7F assigned to 7H (topic mapping and rendering).

```
on entry E, already validated and classified OWED by the 7F pipeline (and past the 7G recovery-case gate):

  BEGIN                                            -- one PostgreSQL transaction, role app_worker
    set tenant context := envelope.organization_id -- 7F §30; never from payload
    claimed := INSERT fan-out claim (obligation, event_id, organization_id)
               ON CONFLICT DO NOTHING RETURNING     -- MR-7H-01
    if not claimed:
        require the claim row is visible in this tenant context
        COMMIT; return ALREADY_COMMITTED            -- then XACK (7F ACK-on-duplicate)
    (topic, serializer) := topic_map[(event_type, event_version)]        -- ELG-04
    endpoints := SELECT … FROM webhooks.webhook_endpoints
                 WHERE status = 'ACTIVE' AND topics @> ARRAY[topic]      -- RLS limits to this tenant
    object := serializer(payload, projection read ports)                 -- PRJ-01 … PRJ-04
    for each endpoint:
        body := serialize_once(envelope{id, type, version, occurred_at,
                                        organization_id, data.object, request_id := new UUIDv7})
        require byte_length(body) <= 262144                              -- 6J §45.2
        INSERT webhooks.webhook_deliveries (organization_id, webhook_endpoint_id, event_type := topic,
               event_id, payload_json := body, payload_hash := sha256(body),
               status 'PENDING', max_attempts := endpoint.max_attempts, next_attempt_at := now())
    record matched-endpoint count on the claim
  COMMIT                                           -- durable acceptance (7F EXT-02)
  XACK                                             -- only now (INV-ACK)
```

| ID | Rule |
|---|---|
| FAN-01 [FROZEN] | Claim and all rows commit in one transaction. The consumer performs no HTTP, no secret-manager call and no Redis call inside it. |
| FAN-02 [FROZEN] | The claim is recorded even when no endpoint matches. |
| FAN-03 [7H] | `webhook_deliveries.event_type` stores the **external topic**, not the internal event name (6J §20.1: `type` ← `webhook_deliveries.event_type`, "one of §19's governed topics"). The internal name is recoverable from the topic map and from the outbox row by `event_id`. |
| FAN-04 [7H] | The envelope `occurred_at` is the internal envelope's `occurred_at` (6J §20.1; 7C §15). It is never the fan-out time, the delivery-row time or the attempt time. |
| FAN-05 [7H] | Rows are created whatever the organization's status is. Organization status gates dispatch, not intent creation (OD-7H-02; §14.2). |
| FAN-06 [7H] | A body larger than 262144 bytes is a handler failure of that entry and follows 7G classification (FC-12). With the PRJ-02 baseline no topic can approach this size; the check is a guard, not an expected path. |
| FAN-07 [FROZEN] | Any failure before commit rolls the whole transaction back: no claim, no rows, no `XACK`. The entry is retried under 7G. |

### 7.2 Idempotency ownership

**IDM-7H-01 [FROZEN].** Idempotency of fan-out is owned by the Integrations context, in its own schema, by a primary-key-backed claim keyed by the consumer obligation and `event_id` and carrying `organization_id` (7F §28.11; 7F DD-13 Pattern A). 7H adds no global inbox and reuses no other context's ledger.

**IDM-7H-02 [FROZEN].** A plain unique constraint on `webhook_deliveries (event_id, webhook_endpoint_id)` is not possible and not wanted: the table is partitioned by `created_at`, and a public replay deliberately creates a second row with the same pair (7F §28.11).

**Conceptual uniqueness invariants**

| ID | Invariant | Enforced by |
|---|---|---|
| UQ-01 | At most one fan-out per (`obligation`, `event_id`) | Claim primary key (MR-7H-01) |
| UQ-02 | Within one fan-out, at most one row per endpoint | The endpoint SELECT returns each endpoint once; rows are inserted in the same transaction as the claim |
| UQ-03 | At most one open replay per original delivery | `fn_replay_webhook_delivery` returns the existing `PENDING` / `DELIVERING` replay (`063_5I`) |
| UQ-04 | At most one open claim of a delivery | `SKIP LOCKED` claim + fence on `claim_seq` (MR-7H-02, MR-7H-03) |
| UQ-06 | One claim identity per claim and one attempt identity per spent attempt | (`delivery_id`, `claim_seq`) and (`delivery_id`, `attempt_number`); DSM-07 (MR-7H-06) |
| UQ-07 | At most 10 replays per lineage per 24 hours, exactly, under concurrency | Lineage anchor row lock inside the replay function (MR-7H-08) |
| UQ-05 | At most one inbound row per (`organization_id`, `provider_slug`, `provider_event_id`) | `uq_iwe_org_provider_event` (`062_5I`) |

**IDM-7H-03 [7H].** What these invariants do **not** prevent, and what the platform therefore never promises: a second HTTP request for the same delivery after an ambiguous network outcome or a worker crash (§18 traces 7, 8); two events with different `event_id` for what a tenant considers one fact (producer responsibility, 7D §11). The receiver's dedup key is the event ID (6J §21.2 rule 4).

### 7.3 Four different things that are all called "again"

| | A. Reprocessing to reconstruct a missing intent | B. Retrying an existing failed delivery | C. Operator / tenant redelivery | D. Internal business-event replay |
|---|---|---|---|---|
| What repeats | The fan-out transaction | One HTTP attempt of the same delivery row | A **new** delivery row for the same event and endpoint | Delivery of the internal event to consumer groups |
| Trigger | Redis redelivery or 7G R1 reclaim, after a crash before commit | The 6J backoff schedule; stale-claim release | `POST /api/v1/webhook-deliveries/{delivery_id}/replay` | 7G R2 – R5, explicit and approved |
| Authorization | None: automatic | None: automatic | `webhook:manage` of the owning organization | 7G capabilities (`recovery.*`), internal tooling only |
| Guard | Claim absent → runs once | Fence on `claim_seq`; `max_attempts` | Function guards; endpoint and organization ACTIVE (OD-7H-03); 10 per delivery and 10 per lineage per 24 h; lineage window (OD-7H-10) | Claim present → no rows |
| Identity | Same `event_id`; delivery IDs created for the first time | Same `event_id`, same delivery ID, new attempt number | Same `event_id`, **new** delivery ID, `replay_of_delivery_id` set | Same `event_id`; no new delivery |
| Provenance | 7G recovery case, if any | Attempt record | `WEBHOOK_DELIVERY_REPLAYED` audit (sync); `replay_count`, `last_replayed_at` on the original | 7G operation record; `O(g, event_id, event_type)` |
| New external obligation? | The first and only one | No | Yes, deliberately | **No** |
| Re-executes the business action? | No | No | No | No (7G RTY-11; RMD-04) |

**IDM-7H-04 [FROZEN].** None of A – D re-executes the originating business action. Each starts from an already committed fact.

---

## 8. External Delivery State Machine

### 8.1 States

Only the frozen vocabulary of `chk_wd_status` is used. No value is added.

| Status | Meaning in 7H | Terminal? |
|---|---|---|
| `PENDING` | Intent exists; no attempt in progress. Dispatch-eligible when `next_attempt_at <= now()` **and** the organization is `ACTIVE`. A `PENDING` row of a non-ACTIVE organization is **held**: "held" is a derived condition, not a status (OD-7H-02) | No |
| `DELIVERING` | One worker owns an attempt; `claimed_by`, `claimed_at` set | No |
| `DELIVERED` | A 2xx response was recorded | Yes |
| `DEAD_LETTER` | `attempt_count` reached `max_attempts` | Yes; replayable |
| `CANCELLED` | Closed without delivery by a governed system action (§8.4) | Yes; not replayable (frozen function guard) |
| `FAILED` | Not reachable in V1 (CNF-7H-07) | — |

### 8.2 Matrix D — transitions

"TX owner" names the component whose transaction performs the transition. "Needs" names the logical migration requirement where the frozen functions are insufficient; a transition marked this way is **designed, not implemented**. "Fence" means the caller's `claim_seq` equals the delivery's current `claim_seq` and the row is `DELIVERING` (DSM-01).

| T | From | Trigger | Guard | TX owner | Persistent effects | Next | Recovery if the actor dies | Needs |
|---|---|---|---|---|---|---|---|---|
| T-01 | (none) | Owed eligible event processed by CMP-01 | Claim won; endpoint `ACTIVE` and subscribed in the snapshot | CMP-01 | Fan-out claim; row with immutable identity and body; `next_attempt_at = now()` | `PENDING` | Before commit: nothing exists, entry redelivered. After commit: entry redelivered, the fan-out claim proves completion | MR-7H-01 |
| T-02 | (none) | Test route 6J-025 | Endpoint `ACTIVE` (OD-7H-06) and organization `ACTIVE`, both checked under the organization share lock; 10 per hour per endpoint | Request transaction | Row with `event_type = 'platform.test'`, fresh `event_id`; it is its own lineage root | `PENDING` | Request fails; the user re-invokes (7D PCI-26: no durable obligation) | MR-7H-08 |
| T-03 | (none) | Replay route 6J-028 | §13.5: parent `DEAD_LETTER` or `DELIVERED`; no open replay of that parent; per-delivery and per-lineage quotas; lineage window; endpoint and organization `ACTIVE` | Request transaction (function) | New row copying endpoint, topic, `event_id`, body, hash, `max_attempts`, lineage root; parent's `replay_count`, `last_replayed_at`; lineage anchor; sync audit | `PENDING` | Transaction atomic; a retried request returns the open replay | MR-7H-08 |
| T-04 | `PENDING` | Dispatcher claim | Due; row not locked; organization row share-locked and `ACTIVE` in the claiming statement (ADM-01) | CMP-03 | `DELIVERING`; `claim_seq + 1`; `claimed_by`, `claimed_at`; claim record C(d, k) | `DELIVERING` | T-08 | MR-7H-02 |
| T-04a | `DELIVERING` | Admission: the final pre-send authorization. At most two per claim (HTP-18) | Fence; organization row share-locked and `ACTIVE`; endpoint row present and **share-locked for the read** (ELK-01); for the second admission, an observed revision mismatch of the first | CMP-03 | Inserts the admission record A(d, k, j): `admitted_at`, `config_revision`, destination fingerprint and key ID, whether a previous-secret signature is planned (§14.5.1, SIG-06). For j = 2 the same transaction first inserts the abandonment record AB(d, k, 1) (`CONFIG_CHANGED`, `NOT_SENT`, the revision found); A(d, k, 1) itself is not touched (DSM-07 H3, H7). **No status change and no attempt spent** | `DELIVERING` (admitted) | T-08; the effective admission record shows where the request may have gone | MR-7H-03, MR-7H-06, MR-7H-11 |
| T-05 | `DELIVERING` (admitted) | 2xx received inside the deadline | Fence | CMP-03 | `DELIVERED`, response code, preview, `attempt_count + 1`, `completed_at`, claim cleared; closure record X(d, k) with `attempt_number`; endpoint `last_delivery_at` (best effort; its own statement after the closure commits, skipped if the row is locked: ELK-05) | `DELIVERED` | T-08: counted and retried; duplicate HTTP possible | MR-7H-03, MR-7H-06 |
| T-06 | `DELIVERING` | Any classified failure (Matrix F), before or after admission | Fence; `attempt_count + 1 < max_attempts` | CMP-03 | `attempt_count + 1`, code, preview, `failure_reason` category, `next_attempt_at` per §13.2, claim cleared; closure record with `attempt_number` and send state | `PENDING` | T-08 | MR-7H-03, MR-7H-06 |
| T-07 | `DELIVERING` | Any classified failure | Fence; `attempt_count + 1 >= max_attempts` (DB-forced) | CMP-03 | `DEAD_LETTER`, `completed_at`, claim cleared; closure record | `DEAD_LETTER` | T-08 | MR-7H-03, MR-7H-06 |
| T-08 | `DELIVERING` | Stale-claim release sweep | `claimed_at` older than the claim lease | CMP-04 | Exactly the effects of T-06 or T-07 with category `CLAIM_EXPIRED` (spends one attempt, OD-7H-05); closure record with `attempt_number`, `closed_by = SWEEP`, send state `UNCERTAIN` if A(d, k) exists and `NOT_SENT` if it does not | `PENDING` or `DEAD_LETTER` | The sweep is stateless and repeatable; a second sweeper skips locked rows | MR-7H-03, MR-7H-06 |
| T-09 | `DELIVERING` (not admitted) | Admission finds the organization not `ACTIVE` | Fence; the organization row is share-locked and its status is not `ACTIVE` in that same transaction | CMP-03 (inside the admission function) | Claim cleared; **`attempt_count` unchanged**; closure record with disposition `RELEASED_ORG_NOT_ACTIVE`, send state `NOT_SENT`, **no `attempt_number`** | `PENDING` (held) | T-08 would spend one attempt; bounded | MR-7H-03, MR-7H-06 |
| T-10 | `PENDING` | Cancellation sweep: organization is `CANCELLED` | Organization row share-locked and `CANCELLED` in the same transaction | CMP-04 | `CANCELLED`, `completed_at`, `failure_reason` = `ORG_CANCELLED`; audit row | `CANCELLED` | Repeatable; skips rows no longer `PENDING` | MR-7H-05 |
| T-11 | `PENDING` | Hold-expiry sweep | Organization row share-locked and not `ACTIVE`, **and** row `created_at` older than 90 days (OD-7H-02) | CMP-04 | `CANCELLED`, `completed_at`, `failure_reason` = `HOLD_EXPIRED`; audit row | `CANCELLED` | Repeatable | MR-7H-05 |
| T-12 | `PENDING` | Operator cancellation (5I §13 "operator action") | — | — | — | — | — | **NOT BUILT in V1**: no route, no function, and platform-admin DML was narrowed to SELECT (`109_5B7`) |

### 8.3 Safety of every transition under repetition

| ID | Rule |
|---|---|
| DSM-01 [7H] | **Fence.** T-04a, T-05, T-06, T-07 and T-09 act only if the row is `DELIVERING` **and** its current `claim_seq` equals the `claim_seq` returned to that worker by T-04. `claim_seq` increases by exactly one at every claim and never otherwise, so a worker whose claim was closed by the sweep (T-08), whatever happened since, can never match again. A non-matching call changes nothing and reports that. The frozen `fn_delivery_succeeded` / `fn_delivery_failed` check only `status = 'DELIVERING'`; used alone they allow a late report to overwrite another worker's claim (§24 ADV-02). |
| DSM-02 [7H] | **Lease.** The claim lease `T_claim_lease` is strictly greater than the maximum attempt duration plus the outcome-recording budget. A worker abandons an attempt, without recording, when its own deadline `T_attempt_max` passes, and `T_attempt_max < T_claim_lease`. [REC] `T_claim_lease = 300 s` (the same value as the frozen outbox claim default, `077_5J1`), `T_attempt_max = 60 s`; 7K tunes both, keeping the inequality. |
| DSM-03 [7H] | **Claim identity.** `claimed_by` is unique per worker process start (it includes a fresh random component). It is evidence of who held a claim. It is not the fence; `claim_seq` is. |
| DSM-04 [FROZEN] | **Ceiling.** `DEAD_LETTER` is forced by the database when the new count reaches `max_attempts`, whatever the caller asks (5I FIX-02). |
| DSM-05 [7H] | **One budget, spent at closure.** `attempt_count` is the only retry budget. It changes only inside the transaction that closes a claim with T-05, T-06, T-07 or T-08, by exactly one, and that transaction assigns `attempt_number` = the new value. T-09 closes a claim without changing it. Redis delivery counts and Celery retry counts are not inputs. |
| DSM-06 [7H] | **The durable row is the truth; a queue message is a hint.** The dispatcher obtains work by claiming due rows from PostgreSQL. A task message enqueued after fan-out may shorten latency but carries no obligation: if it is lost, the next claim poll finds the row (7A CEL-08 … CEL-10; 7D PCI-35 "existing durable delivery rows"). |
| DSM-07 [7H] | **Claim, admission and attempt history invariants** (the future append-only records of MR-7H-06). Four record kinds exist, for delivery d, claim sequence k and admission sequence j: **C(d, k)**, the claim event; **A(d, k, j)**, an admission event; **AB(d, k, 1)**, the abandonment event of admission 1; **X(d, k)**, the closure event. "A(d, k)" without j means admission 1. Every one of them is **inserted once and never updated**; the only mutable state is on the delivery row itself (`status`, `claim_seq`, `attempt_count`, the claim columns). **H1** C(d, k) exists for every k from 1 to the delivery's `claim_seq`, with no gap. **H2** At most one claim of d is open (has no X), and one is open exactly when the row is `DELIVERING`. **H3** A claim has at most two admissions, A(d, k, 1) and A(d, k, 2), each inserted once, only through the fence, only while C(d, k) is open and before X(d, k). A(d, k, 2) exists exactly when AB(d, k, 1) exists; both are inserted by the same transaction, AB first. AB(d, k, 1) carries `CONFIG_CHANGED`, `NOT_SENT`, the revision that was found and its own time, and requires A(d, k, 1). No AB exists for admission 2: if its re-check also fails, the closure X(d, k) with `CONFIG_CHANGED`, `NOT_SENT` is the record that nothing was sent under it. An admission that has an AB is never used to send. **H4** X(d, k) is inserted at most once and only through the fence. **H5** `attempt_number` is non-NULL on X(d, k) exactly when the closure spent the budget; non-NULL values are 1, 2, 3 … without gap in increasing k; their count equals `attempt_count`; (`delivery_id`, `attempt_number`) is unique. A, AB and a re-admission never carry or change an attempt number. **H6** The **effective admission** of a claim is A(d, k, 2) if it exists, otherwise A(d, k, 1). Send state is `SENT` only if the claim has an effective admission and the request was handed to the network under it; a sweep closure is `UNCERTAIN` if any admission exists and `NOT_SENT` otherwise, and `UNCERTAIN` refers to the effective admission. **H7** No runtime role can insert a record outside the guarded functions, and nothing, the guarded functions included, updates or deletes any of the four record kinds; abandonment is therefore an inserted event, not a change to A. Records are removed only with their delivery by the retention purge. |

**Worked example (the case of P1-7H-R04).** Delivery d has `attempt_count = 0`, `claim_seq = 0`.

| Step | Action | `claim_seq` | `attempt_count` | Records written |
|---:|---|---:|---:|---|
| 1 | W1 claims (T-04) | 1 | 0 | C(d, 1) |
| 2 | The organization is suspended | 1 | 0 | — |
| 3 | W1 calls admission; the organization is not `ACTIVE` (T-09) | 1 | 0 | X(d, 1): `RELEASED_ORG_NOT_ACTIVE`, `NOT_SENT`, `attempt_number` NULL |
| 4 | The organization is reactivated; W2 claims (T-04) | 2 | 0 | C(d, 2) |
| 5 | W2 is admitted (T-04a) | 2 | 0 | A(d, 2): fingerprint F, `admitted_at` |
| 6 | W2 sends; 200; records (T-05) | 2 | 1 | X(d, 2): `DELIVERED`, `SENT`, `attempt_number` 1 |

Two claims, one attempt. Claim 1 has no attempt identity, so nothing shares identity (d, 1) in the attempt space, and the evidence says explicitly that claim 1 sent nothing. Had W2 crashed after step 5, the sweep would have written X(d, 2) with `CLAIM_EXPIRED`, `UNCERTAIN`, `attempt_number` 1 (OD-7H-05 preserved), and the next claim would be k = 3 producing `attempt_number` 2.

### 8.4 Maintenance sweeps (CMP-04)

| Sweep | Selects | Action | Bound |
|---|---|---|---|
| Stale-claim release | `DELIVERING` with `claimed_at < now() - T_claim_lease` | T-08 | One attempt per release; ends at `max_attempts` |
| Cancelled-organization closure | `PENDING` rows of organizations in `CANCELLED` | T-10 | Each row once |
| Hold expiry | `PENDING` rows of non-ACTIVE organizations older than 90 days | T-11 | Each row once |

All three must find rows across tenants. `app_worker` cannot do that with ordinary SELECTs under forced RLS, so each is a guarded cross-tenant function in the same class as the frozen worker functions (`101_5I1` "WORKER/SYSTEM FUNCTIONS"). They depend on MR-7H-03 and MR-7H-05.

### 8.5 No unrecoverable state

Claim: every durable delivery is either terminal or has a mechanism that will move it without human action. This holds **once the requirements of §17.3 exist**; it does not hold on the frozen schema alone (§17.5).

| Non-terminal condition | What moves it | Bound |
|---|---|---|
| `PENDING`, organization `ACTIVE`, due | T-04 by any dispatcher poll | Dispatcher availability |
| `PENDING`, organization `ACTIVE`, not yet due | Becomes due at `next_attempt_at` | ≤ 24 h per step |
| `PENDING`, organization `SUSPENDED` | Reactivation makes it claimable; otherwise T-11 | ≤ 90 days from creation |
| `PENDING`, organization `CANCELLED` | T-10 | Sweep cadence |
| `DELIVERING`, worker alive | T-05 / T-06 / T-07 / T-09 | `T_attempt_max` |
| `DELIVERING`, worker dead or partitioned | T-08 | `T_claim_lease` + sweep cadence |

Total HTTP attempts for one delivery are bounded by `max_attempts` ≤ 10. Total lifetime of an unsuspended delivery is bounded by the schedule sum (§13.2). There is no state from which the only exit is manual SQL.

---

## 9. HTTP Webhook Request and Response Contract

### 9.1 Request

| ID | Rule |
|---|---|
| HTP-01 [7H] | Method `POST`. `Content-Type: application/json; charset=utf-8`. Not stated by a frozen source (CNF-7H-11); fixed here because the envelope is JSON and the signature covers the raw body. |
| HTP-02 [FROZEN] | The request carries no `Authorization` header, no cookie and no platform credential. The signature is the authentication (6J §17 table). |
| HTP-03 [FROZEN] | The request line targets the endpoint's `target_url` as read at this attempt (SUB-04), through the egress adapter (§14.3). |
| HTP-04 [FROZEN] | **The body is the stored `payload_json`, byte for byte.** It was serialized exactly once, at intent creation, and is immutable. No attempt, retry or replay re-serializes, pretty-prints, reorders, re-encodes or compresses it (6J §21.1; 7A WH-07, WH-08; 4F §8.2 inv. 1). |
| HTP-05 [7H] | **Byte-level canonicalization.** `body_bytes` = the UTF-8 encoding of the stored `payload_json` text. The serializer emits valid UTF-8 JSON with no byte-order mark and no NUL. The worker builds one immutable byte buffer per attempt; that same buffer object is the input to the HMAC and the HTTP body. `Content-Length` is its length. `Transfer-Encoding: chunked` and `Content-Encoding` are not used for the request. There is therefore no code path on which the signed bytes and the sent bytes can differ. |
| HTP-06 [7H] | **Event identifier string.** The envelope `id` and the header `X-Platform-Event-Id` carry the identical string `evt_` + lower-case canonical UUID of `webhook_deliveries.event_id` (CNF-7H-02). It is the receiver's dedup key and is identical across every attempt and every public replay of the event. |
| HTP-07 [REC] | `User-Agent` identifies the platform's webhook sender generically. It carries no version, host or tenant detail. |
| HTP-08 [7H] | No header other than those of §9.3, `Content-Type`, `Content-Length`, `Host`, `User-Agent` and transport-mandated headers is sent. No tenant-supplied custom header exists in the frozen endpoint resource, so none is sent. |

### 9.2 Envelope (all [FROZEN]: 6J §20.1; 7C WHB-01)

| Field | Value | Fixed when |
|---|---|---|
| `id` | HTP-06 | Intent creation |
| `type` | The external topic (FAN-03) | Intent creation |
| `version` | Topic schema version; `1` for every topic | Intent creation |
| `occurred_at` | Internal `occurred_at`, ISO 8601 UTC | Intent creation |
| `organization_id` | The delivery's `organization_id`; always present | Intent creation |
| `data.object` | §5.3 projection | Intent creation |
| `request_id` | A UUIDv7 generated for this delivery (CNF-7H-01). Constant across attempts and replays | Intent creation |

No `sequence` field exists; ordering is not guaranteed (6J §20.1, §22.2).

### 9.3 Headers (all [FROZEN]: 6J §21.1)

| Header | Value | Varies per |
|---|---|---|
| `X-Platform-Signature` | `v1={hex}` computed with the current secret | Attempt (timestamp changes) |
| `X-Platform-Signature-Previous` | `v1={hex}` computed with the previous secret; present on every request handed to the network while `now() < previous_secret_expires_at`, as established on the database clock at the final re-check (SIG-06), and on no request after it. A request is never sent without it while it is required (SIG-18) | Attempt |
| `X-Platform-Timestamp` | The Unix-seconds value used in the signature input | Attempt |
| `X-Platform-Event-Id` | HTP-06 | Never |
| `X-Platform-Delivery-Id` | `webhook_deliveries.id`, bare UUID | Delivery; new on public replay |
| `X-Platform-Webhook-Version` | The envelope `version` | Topic |

No other `X-Platform-*` header is defined or sent. In particular no attempt-number header and no successor signature header exist (AVS SG-04, CM-WH-12).

### 9.4 Per-attempt procedure (CMP-03)

```
1. CLAIM       (transaction 1)  claim due rows of ACTIVE organizations (organization rows share-locked)
               → (delivery_id, created_at, organization_id, claim_seq, claimed_by)        -- inserts C(d, k)
2. LOAD        (transaction 2, tenant context := organization_id; read only)
                 delivery: payload_json, event_id, event_type          -- the immutable body only
               COMMIT / close
3. ADMIT       start the local admission timer, then (transaction 3, guarded function, fence k, READ COMMITTED):
                 share-lock the organization row; status ACTIVE?   no → T-09 in this transaction; stop
                 lock the delivery row; check the fence
                 ONE locking read of the endpoint row, FOR SHARE (ELK-01): config_revision r, target_url,
                   timeout_ms, signing_secret_ref, previous_signing_secret_ref,
                   previous_secret_expires_at e, destination fingerprint and key ID
                                      -- the latest committed row version, held against every
                                      -- mutation of the endpoint until this transaction commits
                 endpoint row absent → return ENDPOINT_GONE (closed by step 8 as a failed attempt, OD-7H-18)
                 plan_previous := previous ref present AND e > db_now()
                 j = 2 → insert AB(d, k, 1) first
                 insert A(d, k, j): r, fingerprint, key ID, admitted_at := db_now(), plan_previous
               COMMIT                 -- releases both share locks; no transaction or lock is held from here on
4. SECRETS     resolve the secret named by r's signing_secret_ref; if plan_previous, the one named by
               r's previous_signing_secret_ref            -- by reference; in memory only
               current secret unavailable  → failed attempt SECRET_UNAVAILABLE (role CURRENT), NOT_SENT
               previous secret unavailable → note it and go on to step 5; the header is never
                                             dropped here (SIG-18)
5. RE-CHECK    start the local hand-off timer, then (transaction 4, read only, guarded, no lock):
                 read the endpoint's current config_revision r' and db_now()
               r' ≠ r → DO NOT SEND with r:
                         j = 1 → back to step 3 once, as admission j = 2 (uncounted, OD-7H-15)
                         j = 2 → failed attempt CONFIG_CHANGED, NOT_SENT
               if plan_previous:  rem := e − db_now()                  -- database clock only
                   rem ≤ 0                          → the grace is over: emit_previous := false
                                                      (current-only is now correct)
                   rem > 0, previous secret missing → failed attempt SECRET_UNAVAILABLE (role PREVIOUS),
                                                      NOT_SENT (OD-7H-17)
                   rem > 0, previous secret in hand → emit_previous := true
               else emit_previous := false
6. SIGN        ts := current Unix seconds, taken now, for this attempt only
               input := b"ts=" + ascii(ts) + b"." + body_bytes
               sig_current := hex(HMAC-SHA256(current_secret, input))
               if emit_previous: sig_previous := hex(HMAC-SHA256(previous_secret, input))  -- same ts, same bytes
7. SEND        admission timer ≥ T_admit → do not send → failed attempt ADMISSION_EXPIRED, NOT_SENT
               hand-off timer ≥ T_handoff → do not send; repeat step 5 (a re-check, not a re-admission)
               emit_previous AND hand-off timer ≥ rem → do not send; discard both signatures; repeat step 5
                                      -- OD-7H-16: never current-only before e, never previous after e
               egress adapter: resolve → validate → pin → TLS(hostname) → POST body_bytes
               to exactly r's target_url; total deadline := r's timeout_ms; redirects never followed
8. RECORD      (transaction 5, tenant context) fenced closure X(d, k)      → T-05 / T-06 / T-07
```

| ID | Rule |
|---|---|
| HTP-09 [FROZEN] | A fresh timestamp is taken for **every** attempt, including retries and replays; a signature is never reused (6J §23.3; the 5-minute window of §21.2 would otherwise reject it). |
| HTP-10 [FROZEN] | Timeout: `timeout_ms` of the endpoint (1000 – 30000, default 10000). Exceeding it is a failed attempt, identical to a non-2xx (6J §22.3). |
| HTP-11 [7H] | `timeout_ms` is the **total** deadline of step 7: DNS, connect, TLS, request write, response headers and the response-body read up to the cap. A slow-drip response cannot extend it. |
| HTP-12 [7H] | Secrets and the signing input exist only in the worker's memory for the duration of steps 4 – 7. |
| HTP-15 [OD] | **One coherent configuration generation** (OD-7H-12). Everything an attempt uses from the endpoint comes from the single row version returned by the locking read of step 3 (ELK-01) and is identified by its `config_revision` r: destination, timeout, both signing-secret references, the previous secret's expiry and the destination fingerprint. The worker reads no endpoint attribute anywhere else. Secrets are resolved **after** admission, by the references that belong to r, so a destination from one generation can never be combined with a secret from another. The earlier procedure, which loaded the references in one transaction and the destination in a later one, is withdrawn (P1-7H-R07). |
| HTP-16 [OD] | **Admission validity** (OD-7H-09). The worker starts a monotonic timer immediately **before** it issues each admission call. It may hand a request to the network only while that timer is below `T_admit` = 6 s. Starting the timer before the call makes the bound conservative: the admission commit can only be later than the timer's start. A worker that misses the window does not send and closes the claim as a failed attempt `ADMISSION_EXPIRED`, `NOT_SENT` (OD-7H-13). |
| HTP-17 [OD] | **Last-instant re-check** (OD-7H-12). After the secrets are in hand and immediately before signing and hand-off, the worker reads the endpoint's current `config_revision` in a short read-only transaction. If it differs from r, the request is **not sent with r**. The worker starts a hand-off timer before the re-check; if `T_handoff` elapses before the request is handed to the egress adapter, it re-checks again. [REC] `T_handoff` = 1 s; 7K may tune it. `T_handoff` is a design target enforced by a local timer; it is **not** a guaranteed bound on exposure (SIG-15). The re-check takes no lock: it is a plain committed read, and what it guarantees is C2, not C1. The database time it returns also decides whether the previous secret's grace is still running (SIG-06), and for that purpose it may be repeated within one admission. |
| HTP-18 [OD] | **Re-admission after a configuration change** (OD-7H-15). On the first mismatch of a claim the worker performs **at most one** further admission, j = 2, under the same fenced claim. The admission function, called with j = 2, first inserts the abandonment event AB(d, k, 1) (`CONFIG_CHANGED`, `NOT_SENT`, the revision that was found, no attempt spent; the earlier record A(d, k, 1) is not modified) and then performs a complete step 3: the organization share lock and status check, a fresh coherent generation read under the endpoint share lock, the previous-signature planning and a new admission record with its own identity (d, k, 2), all in one transaction. Steps 4 – 7 are then repeated in full, including secret resolution by the new references, the per-attempt egress validation of the new destination, a fresh 6 s timer and a fresh re-check. If the re-check of admission 2 also finds a mismatch, the claim is closed as **one failed attempt** `CONFIG_CHANGED`, `NOT_SENT`, and the next attempt follows the frozen schedule. There is no admission 3. Re-admission does not extend the claim: `claimed_at` is unchanged, the worker's `T_attempt_max` still runs from the claim, and a claim that outlives its lease is closed by the sweep under OD-7H-05 exactly as before. No request is ever handed to the network under a revision the worker has observed to be outdated. |
| HTP-19 [OD] | **Accounting of claims that end without a request** (OD-7H-13, OD-7H-15, OD-7H-17, OD-7H-18). A claim that sends nothing spends one attempt and is recorded `NOT_SENT` with its own category and a failure origin, never as a receiver failure: `ADMISSION_EXPIRED`; `SECRET_UNAVAILABLE`, for the current secret or for a previous secret that is still required (OD-7H-17); `ENDPOINT_GONE`, for an endpoint row removed by a platform operation (OD-7H-18) (all three origin PLATFORM), `CONFIG_CHANGED` after the single re-admission (origin TENANT_CONFIGURATION), and the destination-side `DNS_FAILURE`, `DESTINATION_BLOCKED`, `CONNECT_REFUSED` (origin DESTINATION, frozen by 6J §22.4). The only claim that sends nothing **and** spends nothing is the organization hold (T-09). All of them use the frozen schedule and the `max_attempts` ceiling; none can loop. Should delivery ever be metered, a `NOT_SENT` closure is never a billable request (COM-07). |

### 9.5 Request and response size controls

| Control | Value | Source |
|---|---|---|
| Request body | ≤ 262144 bytes, enforced before INSERT | [FROZEN] 6J §45.2 |
| Request headers | Fixed set of §9.1 / §9.3; all values are platform-generated and of bounded length | [7H] |
| Response buffered | ≤ 2 MB, then the read is aborted | [FROZEN] 6J §30.3 |
| Response stored | First 512 characters, sanitized as untrusted content | [FROZEN] `chk_wd_preview_length`; CNF-7H-08 |
| Response headers | Read only for status and `Retry-After`; not stored | [7H] |

### 9.6 Response acceptance

All [FROZEN] from 6J §22.4 unless tagged. The classification is closed: no response makes a delivery skip to `DEAD_LETTER`.

| Observation | Outcome | Category recorded |
|---|---|---|
| 200 – 299, headers received inside the deadline | Success → `DELIVERED`. The body is not interpreted | — |
| 300 – 399 | Failed attempt. **Never followed** | `REDIRECT_NOT_FOLLOWED` |
| 400 – 499 except 429 | Failed attempt; retried on the schedule | `HTTP_4XX` |
| 429 | Failed attempt; `Retry-After` handled per XRT-06 | `HTTP_429` |
| 500 – 599 | Failed attempt | `HTTP_5XX` |
| 1xx only, or a status outside 100 – 599, or an unparseable response | Failed attempt | `MALFORMED_RESPONSE` [7H] |
| Response larger than the 2 MB buffer cap after a 2xx status line was received | **Success**: the status was received; the body is irrelevant and the read is abandoned [7H] | — |
| Timeout at any stage | Failed attempt | `TIMEOUT` |
| DNS failure; connection refused; connection reset; TLS failure | Failed attempt, network class | `DNS_FAILURE`, `CONNECT_REFUSED`, `CONNECTION_RESET`, `TLS_FAILURE` |
| Destination rejected by the egress policy at delivery time | Failed attempt; **no request is sent** [7H] | `DESTINATION_BLOCKED` |

**HTP-13 [FROZEN].** A receiver that accepted the request but whose response was lost is indistinguishable from a timeout. The delivery is retried and the receiver sees the event again; it must deduplicate on the event ID (6J §22.1, §21.2 rule 4).

**HTP-14 [7H].** The recorded `failure_reason` is one category code from the closed list above (plus `ENDPOINT_GONE`, `SECRET_UNAVAILABLE`, `ADMISSION_EXPIRED`, `CONFIG_CHANGED`, `CLAIM_EXPIRED`, `ORG_CANCELLED`, `HOLD_EXPIRED`). Each closure also carries a failure origin from the closed set `RECEIVER`, `DESTINATION`, `PLATFORM`, `TENANT_CONFIGURATION`, so a platform-side or configuration-side non-send is never presented as a receiver failure (HTP-19). It never contains a URL, a header value, a secret, an exception message with data or response content. Response content goes only to the bounded preview field. The closure of a `SECRET_UNAVAILABLE` additionally records, as an internal detail, which secret role could not be resolved (CURRENT or PREVIOUS); it never records a reference or a value.

### 9.7 Receiver idempotency support

[FROZEN] 6J §21.2: the receiver verifies over raw bytes with constant-time comparison; during a rotation falls back to `X-Platform-Signature-Previous`; rejects a timestamp more than 5 minutes old; and treats the event ID as its idempotency key. 7H changes none of it.

---

## 10. Existing Signature Scheme Preservation

### 10.1 Rules

| ID | Rule |
|---|---|
| SIG-01 [FROZEN] | Public webhook: `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")`, header `X-Platform-Signature: v1={hex}` (6J §21.1 – §21.2; AVS SG-01; 7A WH-07). |
| SIG-02 [FROZEN] | Plugin callout: HMAC-SHA256 with the installation's own secret over `ts={unix_timestamp}.{method}.{canonical_request_path}.{raw_body}`, same header family (6J §25.3; AVS SG-06; 7A WH-10). |
| SIG-03 [FROZEN] | The webhook canonical-input builder is never used for plugin callouts and the plugin builder is never used for webhooks (7A WH-10). They are two separate functions with no shared "generic sign" entry point that takes the canonical form as a parameter. |
| SIG-04 [FROZEN] | No `v2`, no new algorithm, no JSON canonicalization, no new signature header, no in-place change (AVS SG-03, SG-04, SG-09; CM-WH-07 … CM-WH-12). |
| SIG-05 [OD] | **Key selection is by admitted generation.** An attempt signs with the secret named by the `signing_secret_ref` of the configuration revision it was admitted under (HTP-15), and that revision has been re-checked as still current immediately before signing (HTP-17). This holds for delayed retries and for public replays. The earlier wording, "the secret that is current when the attempt is made", claimed more than an asynchronous sender can guarantee and is replaced by SIG-14 … SIG-16 and §10.1.1. |
| SIG-06 [OD] | **Previous-secret signature: the full grace is honoured** (OD-7H-16). Let e be `previous_secret_expires_at` of the admitted revision r. `X-Platform-Signature-Previous` is emitted on a request exactly when all of these hold: (a) r has a `previous_signing_secret_ref`; (b) at admission, by the database clock, `e > admitted_at`, so the signature is planned and the previous secret is resolved; (c) at the final re-check the revision is still r and, by the database clock, `rem = e − db_now() > 0`; (d) the request is handed to the egress adapter while the hand-off timer, started before that re-check, is below `rem`; (e) the previous secret is in hand. It is computed over the identical input as the current signature (same timestamp, same bytes). If (a) – (c) hold and (e) does not, the request is **not sent** (SIG-18). If (c) holds and (d) cannot be met, the request is not sent yet: the worker re-checks, and sends current-only only once a re-check shows `rem ≤ 0`. There is no interval before e during which dual signing is withheld: the earlier condition `e > admitted_at + T_admit` is withdrawn. |
| SIG-07 [7H] | **Why this is safe without comparing wall clocks across machines.** The worker starts its hand-off timer at local instant h0 and only **then** issues the re-check, which reads `db_now()` at a real instant not earlier than h0. So e lies at least `rem` after h0, and a request handed off while the timer is below `rem` is handed off before e. Conversely, a re-check that returns `rem ≤ 0` proves that e has passed, because the instant at which the answer is used is never earlier than the `db_now()` it carries. Hence no request is handed off current-only before e while a previous secret is configured, and no previous-secret signature is computed for a hand-off after e. Only elapsed time is compared with elapsed time; the worker's wall clock is never compared with e. Assumptions, stated as assumptions: the worker's monotonic clock and the database clock advance at the same rate over the re-check-to-hand-off interval, and the database clock is not stepped during it. What this does **not** cover is SIG-17. **Cost:** a request whose re-check lands in the last instants of the grace may be re-checked again and so delayed, by at most the remaining grace plus one re-check; if that carries the claim past `T_admit` it closes `ADMISSION_EXPIRED`, `NOT_SENT` (OD-7H-13). [REC] The worker may subtract a small safety margin from `rem` for clock-rate error; inside that margin it **waits**, it does not send current-only, so the margin never shortens the grace. |
| SIG-08 [7H] | **Overlapping rotations.** S1 → S2 (grace) produces revision r+1 = (current S2, previous S1, expiry e1). S2 → S3 before e1 produces r+2 = (current S3, previous S2, expiry e2); S1 is gone from the row (single generation, 6J §64). A worker never holds "cached references": it has only the references of the revision it was admitted under. Admitted under r+2, it can sign with S3 and S2 only. Admitted under r+1 and re-checked after r+2 committed, it does not send with r+1 (HTP-17). S1 can be used after r+2 only inside the residual of SIG-15. The grace of S1 ends when r+2 commits, whatever e1 was: 6J §21.3 and its test 31 define that a second rotation discards the first previous secret, and the tenant causes that by its own request. Under r+2 the required previous secret is S2, until e2 (SIG-06, SIG-18). |
| SIG-09 [7H] | A signing secret is obtained from the secret manager by reference. A value may be held in worker memory keyed by its reference for a short bounded time; this cannot select a wrong secret, because a reference names one immutable secret value and each rotation creates a new reference (6J §21.3). An unavailable secret is never substituted by a value held under a different reference. A secret is never written to a row, log, span, metric, audit record, task argument or error. |
| SIG-14 [OD] | **What is guaranteed about a configuration change** (a `PATCH` of `target_url` or `timeout_ms`, or a rotation; each increments `config_revision` in its own transaction, committing at `t_x`). **C1** Every admission that commits after `t_x` records the new revision; no attempt is admitted on the old one after `t_x`. This holds because the admission reads the endpoint row under a share lock that conflicts with the mutation's row lock and keeps it until its own commit (ELK-01, ELK-02). It would not hold for a plain read, which is what the version reviewed third specified (P1-7H-R08). **C2** Every re-check that starts after `t_x` sees the new revision; a worker that has seen it never sends with the old one. **C3** Destination, timeout and secret references of one request always belong to one revision. **C4** A request under the old revision is handed to the network no later than 6 s after `t_x`: by C1 its admission committed before `t_x`, and HTP-16 bounds hand-off to 6 s after admission. C4 is the only hard time bound, and it rests on C1, not on the re-check. |
| SIG-15 [OD] | **What is not guaranteed.** A change can commit after a worker's re-check returned and before its request is handed to the network. That request is sent with the earlier revision: the earlier URL, signed with the earlier secret. The re-check narrows this exposure to the re-check-to-hand-off interval, which the worker keeps short with a local timer ([REC] 1 s), but that interval is **not a guaranteed bound**: it depends on the worker not stalling, and a pre-send database read cannot say what is current at the instant bytes leave the host. The guaranteed bound is C4. A request already handed off continues for up to its `timeout_ms`. |
| SIG-16 [OD] | **Zero-grace rotation.** 6J §21.3 calls `grace_period_seconds = 0` an "immediate hard cutover". With an asynchronous sender it is immediate for every attempt admitted or re-checked after the rotation commits (C1, C2), and subject to the residual of SIG-15 for a request whose re-check completed just before. In that residual a request may carry a signature made with the secret that was just rotated out, and none made with the new one. What that does and does not mean: (i) it discloses nothing about the new secret, and holding the old secret gives no access to the new one; (ii) a receiver that has already revoked the old secret rejects the request, which is then retried under the new revision; (iii) the platform **cannot** guarantee that every receiver has revoked the old secret at that instant, so a receiver that still trusts it accepts a delivery signed with a key the tenant has just asked to retire; a tenant rotating because the old secret was exposed must revoke it at the receiver and must not rely on the platform's cutover instant for that; (iv) the same residual applies to a destination change, where the concern is of a different kind: the event body is delivered to the **earlier** destination, a confidentiality consequence that has nothing to do with the secrecy of an HMAC key; (v) the residual is narrowed by the last-instant re-check and bounded, as a hard limit, by C4: nothing under the old revision is handed off later than 6 s after the change commits. The owner accepted this residual (OD-7H-12). It is not claimed to be harmless. The frozen wording is reconciled by ERR-7H-09; 6J is not edited here. |
| SIG-17 [OD] | **What is not guaranteed at the grace boundary** (OD-7H-16). The test of SIG-06 (c) – (d) and the physical hand-off are not atomic. A worker frozen by its host between its final timer check and the connect call can hand off, after e, a request carrying a previous-secret signature that was computed before e. Such a signature is never *computed* after a re-check has shown the grace over, and the egress adapter treats the same deadline as a condition for starting to connect (as in ADM-06), but a freeze placed exactly there is outside the guarantee. The clock-rate and clock-step conditions of SIG-07 are assumptions, not enforced facts. A request handed off before e may reach the receiver after e. Otherwise a positive grace is honoured in full. The approved zero-grace residual (SIG-15, SIG-16) is a separate matter and is not used to justify shortening any positive grace. |
| SIG-18 [OD] | **A required previous secret that cannot be resolved** (OD-7H-17). Four situations are distinguished and never merged. **(1) Not configured:** r has no `previous_signing_secret_ref` (never rotated, or rotated with zero grace). Current-only is correct. **(2) Expired:** `e ≤ admitted_at` at admission, or `rem ≤ 0` at a re-check, on the database clock. Current-only is correct (6J §21.1), whether or not the reference or the secret-manager entry still exists. **(3) Deliberately ineligible before expiry:** no such situation exists. OD-7H-16 withdrew the only one this document had defined, the 6 s early cutoff. **(4) Valid, required, unavailable:** (a) – (c) of SIG-06 hold and the secret manager did not return the previous secret. The claim is closed as one failed attempt: `SECRET_UNAVAILABLE`, `NOT_SENT`, origin PLATFORM, internal secret role PREVIOUS; no HTTP request, nothing billable, frozen backoff, the `max_attempts` ceiling, `DEAD_LETTER` only by exhaustion, replay as for any dead letter. The worker never turns (4) into a current-only send. Whether (2) or (4) applies is decided at the re-check, by the database clock, not by the worker's clock and not at the moment resolution failed. [REC] Resolution may be re-tried inside the admission window before the re-check decides. |

#### 10.1.1 Configuration cutover — worked interleavings

| Case | Interleaving | Outcome under HTP-15 … HTP-18 and SIG-05 … SIG-16 |
|---|---|---|
| **A. Zero-grace rotation** | (1) Worker is admitted under r (S1). (2) Tenant rotates to S2, grace 0; commits at `t_x`, revision r+1. (3) Worker re-checks | If the re-check starts after `t_x`: mismatch; not sent with S1; re-admitted once under r+1 and signed with S2. If the re-check completed before `t_x`: sent, signed with S1, handed off within the residual of SIG-15 and in any case within 6 s of `t_x` |
| **B. Destination edit during secret resolution** | (1) Worker is admitted under r (URL A, S1) and starts resolving S1. (2) Tenant changes the URL to B and rotates to S2: r+1, r+2. (3) Worker re-checks | Mismatch. Nothing is sent to A, and nothing is sent to B with S1: the worker has only r's values and discards them. Re-admission reads r+2 as one row version: URL B, S2, its expiry. The first version could have combined B with S1 because it read references and destination in two transactions |
| **C. Grace expiry during a delay** | (1) Admission under r: previous S1 valid until e, so the previous signature is planned. (2) Secret resolution is slow. (3) e passes. (4) Worker reaches the re-check | The re-check returns `rem ≤ 0`: the grace is over on the database clock and the request is signed with the current secret only, which is what 6J prescribes after e. If instead `rem > 0` but too small to hand off in, the worker does not send, re-checks, and sends current-only once `rem ≤ 0`. A worker that overran 6 s sends nothing (`ADMISSION_EXPIRED`). No previous-secret signature is computed after a re-check has shown the grace over (SIG-06, SIG-07; residual SIG-17) |
| **D. Overlapping rotations** | (1) S1 → S2 with grace: r+1. (2) S2 → S3 before the grace ends: r+2. (3) A worker admitted under r+1 proceeds | Its re-check sees r+2: not sent. Re-admission under r+2 signs with S3 and, if valid, S2. S1 is never used by a worker that has seen r+2 |
| **E. Change after the re-check** | (1) Re-check returns r. (2) A change commits. (3) Worker hands off | Sent under r. This is the residual of SIG-15. The records show it exactly: the admission names r, and the audit row of r+1 has a commit after that re-check |
| **F. Two changes during one claim** | Mismatch at admission 1; mismatch again at admission 2 | One failed attempt `CONFIG_CHANGED`, `NOT_SENT`; the next attempt on the frozen schedule reads the then-current revision |
| **G. Previous secret unavailable inside the grace** | (1) Admission under r+1 = (S2, previous S1, e), 20 minutes before e. (2) The secret manager returns S2 and fails for S1. (3) Re-check: revision r+1, `rem > 0` | Nothing is sent. One failed attempt `SECRET_UNAVAILABLE`, `NOT_SENT`, origin PLATFORM, role PREVIOUS (SIG-18). The next attempt on the frozen schedule resolves again |
| **H. Previous secret unavailable, grace already over** | As G, but the re-check returns `rem ≤ 0` | Situation (2), not (4): sent with S2 only. A purged previous secret after e is the expected state (SEC-7H-04) |
| **I. Mutation racing the admission itself** | (1) The admission takes the endpoint share lock and reads r. (2) A rotation requests the row lock | The rotation waits until the admission commits, then commits r+1 at `t_x`, after the admission. In the other order the admission waits and reads r+1. No admission commits after `t_x` recording r (C1; ELK-02; trace 29) |

#### 10.1.2 Grace-boundary policy — assessment and decision (OD-7H-16)

The version reviewed third planned a previous-secret signature only if `e > admitted_at + T_admit`. Dual signing therefore stopped up to 6 s before the published `previous_secret_expires_at`. That had no approval as a reduction of the grace which the rotate-secret response discloses to the tenant (6J §21.3), and the zero-grace residual approved in OD-7H-12 does not cover it. The two options put to the owner:

| | A. Keep the early cutoff, as a policy amendment | B. Keep the full grace (**approved**) |
|---|---|---|
| Rule | Dual-sign only if the grace outlasts the admission window | Dual-sign every request handed off before e, proven at the final re-check on the database clock (SIG-06, SIG-07) |
| Grace 1 s | No request is ever dual-signed | Every request handed off within that second is dual-signed; none goes current-only before e |
| Grace 3 s | No request is ever dual-signed | Honoured for the full 3 s |
| Grace 6 s | No request is ever dual-signed (an admission under the new revision is never 6 s before e) | Honoured for the full 6 s |
| Grace 3600 s (default) | Dual-signed for the first 3594 s; current-only for the last 6 s | Dual-signed for the full 3600 s |
| Current-only request before e | Yes, during the last 6 s | Never |
| Previous-secret signature after e | Never | Never knowingly; residual SIG-17 |
| Effect on timing at the boundary | None | A request may be delayed by at most the remaining grace plus one re-check, or end `ADMISSION_EXPIRED` after 6 s |
| Published 6J promise | Shortened; needs an erratum reducing the grace | Unchanged |

For a very short grace, how many requests fall inside it under B depends on how quickly an attempt passes admission, secret resolution and re-check. B does not promise that some attempt will be handed off inside a 1 s grace. It promises that no request handed off inside the grace goes without the previous signature. B was recommended and approved. The 6 s admission ceiling (HTP-16) and the last-instant revision re-check (HTP-17) are unchanged.

### 10.2 Matrix C — trust boundaries and credentials

No credential in this table is accepted in place of another. Each row has its own verifier code path.

| Aspect | 1. Provider inbound callback | 2. Platform outbound webhook | 3. Platform → plugin callout | 4. Internal service token | 5. Tenant API key |
|---|---|---|---|---|---|
| Signer / issuer | The external provider | The platform (CMP-03) | The platform (CMP-08) | The central internal token issuer (6B §17.2) | Issued by the platform to a tenant |
| Verifier | CMP-06 through the owning context's provider adapter | The tenant's receiver | The plugin | Platform internal routes `/api/internal/v1/*` | Platform public API |
| Trust boundary crossed | Internet → platform | Platform → tenant system | Platform → plugin developer system | None: inside the platform | Tenant system → platform |
| Canonical bytes | Provider-native scheme over the raw request body (per provider; AVS AX-G). Exotel's exact scheme: **NOT SPECIFIED** by a frozen source | `ts={ts}.{raw body}` | `ts={ts}.{method}.{canonical path}.{raw body}` | RS256 JWT | Opaque key, compared against a stored hash (6B) |
| Identity asserted | "This request comes from provider P for connection / account X" | "This body comes from the platform, for this endpoint" | "This request comes from the platform, for this installation" | `service_id`, optional `on_behalf_of_organization` | The API key's organization and scope ceiling |
| Tenant binding | Resolved from platform-held state the verified request references (connection route ID, call, payment). Never from a payload field (7A CB-06; 6J ADR-6J-10) | The endpoint row's `organization_id`; the secret is per endpoint | `X-Platform-Tenant-Id`, built from the same context as the payload; the secret is per installation | Claim set by the issuer, not the caller | The key record |
| Replay protection | Durable dedup on the provider event ID; provider timestamp or nonce where supplied (6J §24.2) | Timestamp in the signed input; receiver's 5-minute window; event-ID dedup | Same window discipline (6J §25.3) | `exp` 5 minutes, `jti` (6B §11.2) | Not a signed request; TLS only |
| Credential owner | Provider and tenant connection | Tenant (per endpoint) | Tenant (per installation) | Platform | Tenant |
| Storage | `credential_ref` → secret manager | `signing_secret_ref`, `previous_signing_secret_ref` → secret manager | `plugin_installations.credential_ref` → secret manager | Issuer private key; verifiers hold the public key | Hash only |
| Rotation / revocation | Connection credential rotation (6J §12.4); disconnect | `rotate-secret` with dual-signature grace; disable | `rotate-credential`; suspend; uninstall | Short expiry; no denylist (6B §12.4) | Revoke the key (6B) |
| Logging | Never the signature header value, the secret or the raw payload | Never the secret, the signature or the body | Never the secret, the signature or the body | Never the token | Never the key |
| On verification failure | Reject before any state change; no row is written (7A CB-02) | Receiver's concern | Plugin's concern | 401 | 401 |

| ID | Rule |
|---|---|
| SIG-10 [7H] | A provider-callback route never accepts a tenant API key, a JWT or an internal token as authentication, and ignores any that are present (7A CB-02). |
| SIG-11 [7H] | A webhook signing secret authorizes nothing inbound. No platform route verifies a request with a `signing_secret_ref`, so possession of it cannot publish an event, call an API or replay a delivery. |
| SIG-12 [7H] | A plugin installation secret authorizes nothing inbound either. A plugin gains no tenant authority from `X-Platform-Tenant-Id`: the platform sets that header; it never reads an organization identifier from a plugin response as authority (PLG-05). |
| SIG-13 [7H] | The three secret-manager namespaces (integration `credential_ref`, webhook `signing_secret_ref`, plugin `credential_ref`) are disjoint. The component that resolves one kind never resolves another kind for the same call. |

---

## 11. Provider Callback Trust Boundary

7H does not redesign any provider subsystem. It fixes the boundary every callback route obeys and the recovery of accepted callbacks.

### 11.1 Routes (all [FROZEN]: 7B §19; AIR §18.2)

| Route | Owner | Durable receipt | Tenant resolution | Resulting events |
|---|---|---|---|---|
| 6D-021 `POST /webhooks/voice/{provider_slug}/events` | Voice | `webhooks.inbound_webhook_events` | From the platform-held call / number state the verified event references | EV-073, EV-075; EV-005 / EV-006 on provider-driven terminal transitions; inbound-call admission under FAR-OD-05 |
| 6J-014 `POST /api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` | Integrations | `webhooks.inbound_webhook_events` | Route segment selects the candidate connection; its `organization_id` is trusted only after verification (ADR-6J-10) | None currently |
| 6K-023 `POST /api/v1/billing/payment-providers/{provider_slug}/webhook` | Billing | `billing.payment_webhook_receipts` (`102_5H2`), written only by role `app_billing_webhook_ingress` | From the payment attempt the verified event references | EV-103, EV-104 |

### 11.2 Ingress sequence (OD-7H-08)

```
1. size and rate guards (pre-identity)                        -- 6J §24.4, §24.6 (a), (b), (d)
2. retain the exact raw request-body bytes
3. routing lookup only (which credential could verify this)   -- no trust yet
4. verify the provider signature over the raw bytes            -- failure → reject; NOTHING is written
5. resolve the organization from platform-held state           -- failure → reject; nothing is written
6. derive provider_event_id (provider-native; else SHA-256(provider_slug || "." || raw verified bytes))
7. EXTRACT the processing input: the owning context's adapter reads, from the verified bytes only,
   the closed set of normalized fields its command needs (CPU only; no I/O; bounded time and size)
8. ONE transaction, tenant context of step 5:
     INSERT receipt … ON CONFLICT DO NOTHING RETURNING id
     if a row was returned: INSERT its processing input (same transaction)
   COMMIT                                                      -- the durability boundary
9. respond 2xx                                                 -- identical for new and duplicate
10. optionally hand a wake-up hint to processing               -- a hint, never the obligation
```

**Why step 7 moved before the acknowledgement.** The frozen receipt row (`062_5I`) holds `provider_slug`, `provider_event_id`, `event_type`, a signature flag and a status. It holds none of the facts a domain command needs (which call, what state, what duration). The raw payload is deliberately not retained (5I ADR-5I-010; 6J §40.4). If the request process ends after step 9, nothing durable says what the callback reported, and a re-dispatched task has nothing to process. 7D REC-04 requires that recovery "processes the stored, already-verified record"; on the frozen schema no such record exists for these two routes (CNF-7H-14). Billing already solved this the same way: `billing.payment_webhook_receipts` stores normalized, verified fields and a hash of the raw bytes, and never the raw payload (`102_5H2`).

| ID | Rule |
|---|---|
| CBK-01 [FROZEN] | Verification precedes every state change. An unverified request writes no row, changes no state and triggers no processing (7A CB-02; 6J §24.6 step 4). |
| CBK-02 [FROZEN] | Verification operates on the raw bytes; the body is not parsed and re-serialized first (7A WH-08, WH-11). Extraction (step 7) runs only after verification succeeded, and reads the same retained bytes. |
| CBK-03 [FROZEN] | The tenant is never taken from a payload field, a query parameter or a header the provider or an attacker controls (7A CB-06; 7B Rule H-2). |
| CBK-04 [OD] | **Durable processing input.** A receipt that owes processing is committed together with its **processing input**: the minimum verified, normalized facts from which the owning context can rebuild its command. Both are in one transaction, before the 2xx. The enqueue after the acknowledgement is a latency hint only; it is never what makes the work durable, and its loss loses nothing. |
| CBK-05 [FROZEN + OD] | The 2xx acknowledges **durable receipt of the callback and of its processing input**. It does not mean the event was processed, a call was admitted, a payment was settled or any domain event was produced (6J §24.4; 7A CB-04). |
| CBK-06 [FROZEN] | Processing translates the provider fact through the owning context's anti-corruption layer into that context's own command and state change. Any domain event is written to the outbox in that transaction (7A CB-05; 6D §10.4). Raw provider payloads, signatures and secrets never enter an event (7B Rule H-3). |
| CBK-07 [FROZEN] | The provider event ID is the dedup key of the inbound row only. It is never the canonical `event_id` (7B Rule H-1). The resulting event's `causation_id` is the inbound row ID (7C PCV-03). |
| CBK-08 [7H] | **A provider callback cannot inject a tenant event.** Ingress writes only a receipt and its processing input, for the organization it resolved from platform state after verification. Which domain event, if any, results is decided by the owning context from its own state machine. A callback that references a call, connection or payment the organization does not own fails resolution at step 5. |
| CBK-09 [7H] | **Processing idempotency is domain-owned; the processing claim only reduces duplicates.** A guarded compare-and-set moves a receipt `RECEIVED → PROCESSING` and tells the caller whether it won (MR-7H-09). Two workers that both process one receipt, for example after a stale `PROCESSING` re-dispatch, are made harmless by the owner's guards: call-state compare-and-set and dispatch keys (6D), guarded settlement functions (6K). The frozen `fn_update_inbound_event_status` is not a claim and is not relied on as one (CNF-7H-09). |
| CBK-10 [OD] | **Recovery of accepted receipts** (7D PCI-13, PCI-25, PCI-28). A sweep finds receipts stale in `RECEIVED` or `PROCESSING` and re-dispatches them. The processor loads the stored processing input under the receipt's tenant context and rebuilds the command from it and from current platform state. It needs nothing from the request process. For Billing the frozen `RECEIVED` / `RETRY_PENDING` + `next_retry_at` model applies unchanged. |
| CBK-11 [FROZEN] | The platform never asks a provider to retry. A provider's own retry of an accepted event is absorbed at step 8: the insert returns no row, the first stored processing input stands and is never overwritten. |
| CBK-12 [FROZEN] | Callback ingress is not subject to tenant API quotas; its limits are the layered guards of 6J §24.6 (7A CB-07). |
| CBK-13 [7H] | Audit evidence: the receipt row (provider, event type, status, times, bounded failure reason) and the hash of the verified raw bytes are the durable evidence. The raw payload is not retained by default (5I ADR-5I-010), and OD-7H-08 does not change that. Domain-level audit rows are written by processing, not by the fast ACK (AIR §18.1 `AUDIT_DOMAIN/PROVIDER_PROCESSING`). |
| CBK-14 [LATER] | Exotel-specific signature verification, field mapping and decline signalling are Telephony ACL work in Phase 9 behind the provider abstraction (6D §10.4; 7A §6.6). 7H constrains them by CBK-01 … CBK-22. |

### 11.3 The processing input

| ID | Rule |
|---|---|
| CBK-15 [OD] | **Content.** A provider-neutral record with a closed schema per (owning context, normalized event kind), carrying a schema version. It contains only what the command needs: the normalized event kind; the provider's reference to the platform resource (call, connection, payment); provider-reported timestamps; coded state values and numeric measures. It never contains the raw payload, a signature, a secret, a token, media, a signed URL or free text. Personal data appears only where the command cannot be built without it (for example the two numbers of a provider-originated inbound call). Its size is bounded; [REC] 8 KB. |
| CBK-16 [OD] | **Atomicity and immutability.** Written once, in the receipt's transaction. Never updated. A duplicate callback never replaces it. |
| CBK-17 [OD] | **Extraction failure is still durable.** If the verified bytes cannot be turned into a valid processing input, the receipt is committed without one, already in `FAILED` with a category code. It is not processed and not retried (6J §24.4: a shape-invalid payload is terminal; "never silently dropped without a durable row"). |
| CBK-18 [OD] | **Lifetime.** The processing input is deleted in the same transaction that moves its receipt to `PROCESSED` or `SKIPPED`. For a receipt that ends `FAILED` after extraction, the input is kept for diagnosis until a period 7I sets (HE-7I-7H-07) and is deleted earlier by erasure. An input whose receipt is not terminal is **never** deleted by age: it is owed work. |
| CBK-19 [OD] | **Isolation and access.** Forced RLS on `organization_id`. Written by the ingress role in the resolved tenant context; read only by the owning context's processing worker in that tenant context. Not returned by `GET /inbound-webhook-events` or any tenant or platform-admin surface. Encrypted at rest at field level; the mechanism and key custody are 7I's (HE-7I-7H-07). Never logged. |
| CBK-20 [OD] | **Erasure.** The organization erasure path deletes that organization's processing inputs with the rest of its integration data. A processing input is covered by the same residency rule as its receipt (RES-7H-01). |
| CBK-21 [7H] | **Bounded processing.** A deterministic rejection by the owner (the referenced resource is in a state that makes the fact inapplicable) ends the receipt in `SKIPPED` or `FAILED` at once. A transient failure leaves the receipt to the sweep. The number of processing attempts is bounded by a count the owning context sets; exhaustion ends in `FAILED`, visibly, with the input retained under CBK-18. No receipt is retried without bound and none disappears silently. |
| CBK-22 [7H] | **What recovery restores, and what it cannot.** Recovery preserves the *facts*: a recovered `call ended` event still closes the session, releases capacity and feeds billing. It cannot restore *timeliness*: a provider-originated inbound-call event processed minutes late cannot answer that call. The owning command decides from current state whether a late fact still applies. |

### 11.4 Recovery by route

| Route | Durable source for reprocessing | Status on the frozen schema | After OD-7H-08 |
|---|---|---|---|
| 6K-023 payment webhook | Normalized columns of `billing.payment_webhook_receipts` (`normalized_event_kind`, `provider_transaction_id`, `settled_amount`, `settled_currency`, `event_occurred_at`, `provider_failure_code`, `payload_hash`); written by `fn_record_payment_webhook_receipt` under role `app_billing_webhook_ingress` | **Recoverable today** by design (`102_5H2`): `RECEIVED` / `RETRY_PENDING`, `next_retry_at`, guarded settlement | Unchanged. No migration requirement from 7H |
| 6D-021 voice provider events | None beyond identifiers | **Not recoverable** after a crash between the 2xx and execution | Processing input committed with the receipt (MR-7H-09). Independent of it, 7D §35.5 lets a reconciler use a provider status query where an adapter has that capability; no adapter is assumed to (7D VCC-02), so it is not relied on |
| 6J-014 integration callbacks | None beyond identifiers | **Not recoverable** | Processing input committed with the receipt (MR-7H-09). No frozen source defines a domain effect for a generic integration callback today (7B PCB-02: "none currently"); a provider adapter that defines none extracts no input and its receipts end `SKIPPED` |

---

## 12. Plugin Callout Bridge

### 12.1 What frozen sources define

| Question | Answer | Source |
|---|---|---|
| Which internal events are eligible for plugin notification? | **None.** No frozen source defines a plugin event subscription, a plugin topic or an event-to-plugin fan-out. `plugin.*` and `integration.*` events are internal-only | NOT FOUND in 4F §9, 5I §17 – §20, 6J §25 – §30; 7B Rule G-1 |
| What triggers a callout? | An invocation by a platform code path that holds a capability reference: a workflow `WEBHOOK` / `API_CALL` / plugin-capability node, or tool execution | 6J §28.4, §30; 4F §9.3 |
| Synchronous or asynchronous? | Synchronous request / response from the caller's point of view, bounded by `manifest.timeout_ms` ≤ 30000. `webhook_callback_url` is declared in the manifest for asynchronous results, but no frozen contract defines an inbound plugin-result route | 6J §25.3, §26.3; NOT SPECIFIED for the async result path |
| Plugin identity | `plugins.slug` + pinned `plugin_version_id`; manifest immutable after approval | 5I INV-PLUG-01, 02 |
| Installation permissions | RBAC `plugin:install` / `plugin:manage` for management; `enabled_capabilities ⊆ manifest.capabilities` for invocation | 6J §28 |

**PLG-01 [7H].** Because no event subscription exists, CMP-01 never fans out to plugins and no delivery row targets a plugin. A plugin learns of platform facts only through a callout a workflow or tool makes, or by being the tenant's own webhook receiver like any other HTTPS endpoint.

### 12.2 Rules

| ID | Rule |
|---|---|
| PLG-02 [FROZEN] | Effective authority = capability registry ∩ `manifest.capabilities` ∩ `installation.enabled_capabilities` ∩ the invoking path's own authorization. Every layer narrows. The check runs at every invocation, not only at activation (6J §28.3). |
| PLG-03 [FROZEN] | A workflow node pins `plugin_installation_id` and `plugin_version_id`. A mismatch after an upgrade fails closed with `PLUGIN_VERSION_PINNED_MISMATCH` (6J §30.5; ADR-6J-09). |
| PLG-04 [FROZEN] | Signing per SIG-02 with the installation's secret. Every callout goes through the egress adapter; a redirect is never followed with the signature or credentials (6J §25.3, §30.3). |
| PLG-05 [FROZEN] | The platform sets `X-Platform-Tenant-Id` from the same request context that built the payload. It is information for the plugin, not an enforcement mechanism (6J §25.3). **[7H]** A plugin response is data returned to the invoking node. No field of it is ever used as an organization identifier, a permission or a credential by the platform. |
| PLG-06 [FROZEN] | Payload: only the fields the invoking service constructs for that capability call. Never a row dump, another tenant's data, an integration credential, a signed URL, a transcript or a recording (6J §25.4, §40). Response: captured, capped (2 MB buffered; 64 KB into a workflow slot), normalized to 6J error classes; the caller never sees a raw provider body (6J §30.5). |
| PLG-07 [FROZEN] | **No automatic retry of a non-GET callout by any platform layer** (6A §21; 6J §30.5). A timeout or lost response is returned to the caller as a normalized failure; the workflow's own `on_failure_edge` decides what happens. The idempotency boundary of a re-evaluated node is 6I's `node_execution_claims`. |
| PLG-08 [FROZEN] | Rate limit: Redis token bucket per (`organization_id`, `plugin_id`), enforced before the call; an installation override may only lower it (6J §25.3). Timeout: `manifest.timeout_ms`, not negotiable. What happens when the bucket cannot be consulted is not frozen (CNF-7H-16) and is fixed by PLG-15 … PLG-18. |
| PLG-09 [7H] | **Voice hot path.** A plugin callout is never made from the audio frame loop or from any code that the media path waits on (7A VOX-02, VOX-03). Where a tool or workflow node invoked during a live call uses a plugin, it runs as that runtime's asynchronous tool execution under its own timeout; the latency budget and what the agent says while waiting are owned by 6D / 6I and Phases 9, 13 and 17. 7H adds no blocking HTTP dependency to the turn loop and defines none. |
| PLG-10 [FROZEN] | Suspension, uninstall, upgrade: an installation that is not `ACTIVE` fails closed at the next invocation (`PLUGIN_DISABLED`, `PLUGIN_NOT_INSTALLED`). Uninstall is never blocked by a reference; the secret-manager entry is purged; execution history survives (6J §42.3, ADR-6J-04). |
| PLG-11 [FROZEN] | Compensation: none is defined. A side effect a plugin performed before a timeout is not compensated by the platform. Deprecated versions keep running for pinned installations (6J §29.2). |
| PLG-12 [7H] | Durable evidence of a callout is the `plugins.plugin_executions` row (`PENDING → RUNNING → SUCCEEDED / FAILED / TIMED_OUT`), written by the invoking service around the call, never inside a transaction that spans it. Previews are bounded and treated as untrusted content. |
| PLG-13 [7H] | An organization that is not `ACTIVE` makes no plugin callouts: the invoking runtimes do not execute for a suspended organization (4A: a suspended organization's resources are denied). 7H states the constraint; enforcement belongs to those runtimes. |
| PLG-14 | No arbitrary-code plugin runtime, sandbox or marketplace is designed (6J §25.1; J3 FUTURE). |
| PLG-15 [OD] | **Rate-limit store unavailable: fail closed** (OD-7H-11). If the executor cannot obtain a decision from the rate limiter (Redis unreachable, timed out or erroring), it **does not call the plugin**. The plugin rate limit is never bypassed and no local or approximate limiter substitutes for it. |
| PLG-16 [OD] | **Result.** The refusal is returned through the existing result contract as a normalized, retryable failure: the fallback class `INTEGRATION_OPERATION_FAILED` with `retryable = true` (6J §35.3), never `INTEGRATION_RATE_LIMITED`, which means the provider or the tenant's own limit refused, and never a new code. A workflow node takes its `on_failure_edge` (6I §22); a tool invoked during a call receives the failure as its tool result at once, so nothing waits on Redis in a live turn. |
| PLG-17 [OD] | **Bounded retries, no storm.** Because nothing was sent, re-asking the limiter is not a retry of a non-GET call and PLG-07 is not engaged. The executor may re-ask the limiter a small fixed number of times with jittered backoff, all inside the callout's own `manifest.timeout_ms`; [REC] at most 2 re-asks. A process-wide circuit breaker on the limiter, of the shared kind 6A §21 already prescribes, then opens: while it is open every callout is refused immediately without touching Redis, and one probe per interval tests recovery. Retries above the executor belong to the invoking runtime's own bounded policy; 7H adds none. |
| PLG-18 [OD] | **Evidence.** Each refused callout writes its `plugins.plugin_executions` row with status `FAILED`, no HTTP status and the category `RATE_LIMITER_UNAVAILABLE`, so the refusal is durable and attributable to an installation and capability. The breaker's opening and closing are recorded once per transition as operational events and signals (§19.3), not once per callout. |

---

## 13. Retry, DLQ, Failure and Replay Integration

### 13.1 Five retry domains, never merged

7G §9 froze domains A – C for internal events. 7H adds the external ones. No domain reads or writes another's counters.

| Domain | Describes | State lives in | Budget | Owner | Contract |
|---|---|---|---|---|---|
| A. Publisher retry | Relay → Redis | Outbox row | `max_attempts` of the outbox row | 7D relay | 7D §15 – §25; 7G §26 – §29 |
| B. Consumer delivery / reclaim | The fan-out consumer completing its obligation | PEL + 7G recovery ledger | 5 genuine failures (OD-7G-01) | 7G | 7G §10 – §25 |
| C. Business idempotency | Whether the fan-out happened | Fan-out claim | — | Integrations | 7F §28.11 |
| **D. External delivery retry** | HTTP attempts of one delivery | `webhook_deliveries` row | Endpoint `max_attempts` (1 – 10), copied at creation | CMP-03 / CMP-04 | 6J §22; §13.2 here |
| **E. Provider-callback ingress** | Dedup and processing of one received callback | Receipt row **and its processing input**; owner state | Provider-initiated retries are absorbed; platform recovery is the stale sweep over the stored input, with a bounded processing-attempt count | CMP-06 / CMP-07 | 6J §24; 7D PCI-13, 25, 28; §11 here |
| **F. Plugin-callout retry** | One callout | `plugin_executions` row; 6I node claim | None automatic | The invoking runtime | 6J §30.5; 6A §21 |
| **G. Operator / tenant redelivery** | A new delivery of an old event | New `webhook_deliveries` row; lineage anchor | 10 per delivery and 10 per lineage per 24 h, inside the root's retention window; then domain D for the new row | Tenant, via 6J-028 | 6J §23.3 |

| ID | Rule |
|---|---|
| XRT-01 [7H] | The OD-7G-01 budget of 5, the 7G reclaim delay, the 7G recovery ledger and the 7G failure classes apply to domain B only. They are never applied to an HTTP delivery. |
| XRT-02 [FROZEN] | The 6J webhook dead-letter state is unrelated to the 7G recovery ledger. Neither holds the other's records (7G WHB-04). A delivery in `DEAD_LETTER` is not a parked event, and a parked fan-out entry has no delivery rows. |
| XRT-03 [FROZEN] | An HTTP retry never re-executes the fan-out, and the fan-out never re-executes the business action. |

### 13.2 External delivery schedule

| Attempt n | Wait before it (the "step") | Tag |
|---:|---|---|
| 1 | 0 | [FROZEN] 6J §22.3 |
| 2 | 30 s | [FROZEN] |
| 3 | 60 s | [FROZEN] |
| 4 | 5 min | [FROZEN] |
| 5 | 30 min | [FROZEN] |
| 6 | 2 h | [FROZEN] |
| 7 | 8 h | [FROZEN] |
| 8 | 24 h | [FROZEN] |
| 9 | 24 h | [OD] OD-7H-04 |
| 10 | 24 h | [OD] OD-7H-04 |

Elapsed time from creation to the last attempt, excluding attempt durations: default 7 attempts ≈ 10 h 37 min; 8 attempts ≈ 34 h 37 min; 10 attempts ≈ 82 h 37 min.

| ID | Rule |
|---|---|
| XRT-04 [7H] | After a failed attempt whose new count is n − 1, `next_attempt_at = now() + wait(n)`, computed by the worker and passed to the outcome function; the database enforces only the ceiling (5I §14). |
| XRT-05 [REC] | **Jitter within the schedule** (delegated to 7H by 7A §18). `jittered_wait(n)` is drawn uniformly from [`step(n)` × (1 − J), `step(n)`] with J ≤ 0.10. Jitter only shortens; a wait never exceeds its step, so the frozen schedule remains the upper bound. 7K may tune J inside that range. |
| XRT-06 [7H] | **`Retry-After`** (429 only): `wait = min(step(n), max(jittered_wait(n), retry_after))`. An absent, unparseable, negative or past-dated value is ignored. A receiver can therefore push an attempt later only inside the jitter window and can never extend a delivery's lifetime or bring an attempt forward (CNF-7H-06). |
| XRT-07 [FROZEN] | Exhaustion is the only path to `DEAD_LETTER`. No status code, error class or count of identical failures short-circuits it. |
| XRT-08 [7H] | A stale-claim release counts as one attempt and uses the same schedule (OD-7H-05). |
| XRT-09 [7H] | **Dependency gating before claim.** A dispatcher does not claim while a dependency every attempt needs is known to be down for it: the secret manager or the egress path. This keeps a platform-side outage from spending tenants' attempts. It is a pre-claim check only: a failure discovered after the claim is an ordinary failed attempt, so the bound of §8.5 is unaffected. |

### 13.3 Matrix F — failure classification and recovery

| Failure | Detected by | Request sent? | Counts an attempt? | Result | Duplicate HTTP possible? | Recovery owner |
|---|---|---|---|---|---|---|
| Connection refused | Egress adapter | No | Yes | T-06 / T-07, `CONNECT_REFUSED` | No | Schedule |
| DNS failure | Egress adapter | No | Yes | `DNS_FAILURE` | No | Schedule |
| Destination blocked by policy (private, link-local, metadata, rebinding) | Egress adapter | No | Yes | `DESTINATION_BLOCKED` | No | Schedule; tenant fixes DNS or URL |
| TLS verification failure | Egress adapter | No (handshake only) | Yes | `TLS_FAILURE` | No | Schedule |
| TCP reset before the request was fully written | Egress adapter | Partially | Yes | `CONNECTION_RESET` | Unlikely; receiver may have seen a truncated request | Schedule |
| TCP reset or timeout after the request was written | Egress adapter | Yes | Yes | `CONNECTION_RESET` / `TIMEOUT` | **Yes** | Schedule; receiver dedup |
| HTTP 2xx | Worker | Yes | Yes (final) | T-05 | No further attempt | — |
| HTTP 3xx | Worker | Yes | Yes | `REDIRECT_NOT_FOLLOWED` | No | Schedule; tenant fixes URL |
| HTTP 4xx (not 429) | Worker | Yes | Yes | `HTTP_4XX` | Receiver rejected it | Schedule |
| HTTP 429 | Worker | Yes | Yes | `HTTP_429`; XRT-06 | Receiver rejected it | Schedule |
| HTTP 5xx | Worker | Yes | Yes | `HTTP_5XX` | **Yes** if the receiver acted before failing | Schedule; receiver dedup |
| Malformed response | Worker | Yes | Yes | `MALFORMED_RESPONSE` | **Yes** | Schedule; receiver dedup |
| Receiver accepted, response lost | Appears as timeout or reset | Yes | Yes | `TIMEOUT` | **Yes** | Schedule; receiver dedup |
| Worker crash before send | CMP-04 | No | Yes (OD-7H-05) | T-08, `CLAIM_EXPIRED` | No | CMP-04 |
| Worker crash after send, before record | CMP-04 | Yes | Yes | T-08 | **Yes** | CMP-04; receiver dedup |
| Current signing secret of the admitted revision unavailable | Worker | No | Yes (OD-7H-13) | `SECRET_UNAVAILABLE`, `NOT_SENT`, origin PLATFORM, role CURRENT | No | Schedule |
| Previous signing secret unavailable while its grace is still running at the re-check | Worker; decided at the re-check | No | Yes (OD-7H-17) | `SECRET_UNAVAILABLE`, `NOT_SENT`, origin PLATFORM, role PREVIOUS. Never a current-only send | No | Schedule; operational alert |
| Previous signing secret unavailable, grace over at the re-check | Re-check | Yes, current-only | Yes, as whatever the attempt's outcome is | T-05 / T-06 / T-07 | As for any attempt | Not a failure: situation (2) of SIG-18 |
| Grace about to end: hand-off before expiry cannot be assured | Worker's hand-off timer against `rem` | Not yet | No, unless the admission window is then missed | Re-check repeated; then dual-signed or, once expired, current-only | No | The same claim (OD-7H-16) |
| Endpoint mutation in progress when the admission reads the endpoint | Admission function (lock wait) | No | No | The admission waits for the mutation's commit and records the new revision. If the wait exceeds its lock timeout or the admission window: `ADMISSION_EXPIRED`, `NOT_SENT`, which is counted | No | The same claim; ELK-05 |
| Configuration changed between admission and send, first time in the claim | Re-check | No | **No** (OD-7H-15) | AB(d, k, 1) inserted (`CONFIG_CHANGED`, `NOT_SENT`); one re-admission | No | The same claim |
| Configuration changed again after the re-admission | Re-check | No | Yes | `CONFIG_CHANGED`, `NOT_SENT`, origin TENANT_CONFIGURATION | No | Schedule |
| Configuration changed after the re-check returned | Not detected | Yes, under the earlier revision | Yes, as whatever the attempt's outcome is | T-05 / T-06 / T-07 | As for any attempt | Residual of SIG-15; evidenced by the admission's revision |
| Endpoint row absent (hard-deleted by a platform operation) | Admission function | No | Yes (OD-7H-18) | `ENDPOINT_GONE`, `NOT_SENT`, origin PLATFORM | No | Exhaustion; replay refused while no endpoint exists |
| Organization not `ACTIVE` at admission | Admission function | No | **No**: no attempt number is assigned | T-09 (held) | No | Reactivation, T-10, T-11 |
| Organization left `ACTIVE` after admission committed | Not detected by the worker | Possibly, within 6 s of the change (ADM-05) | Yes, as whatever the attempt's outcome is | T-05 / T-06 / T-07 | As for any attempt | Bounded residual window; evidenced (TEN-7H-08) |
| Admission window missed (worker stalled more than 6 s) | Worker | No | Yes | `ADMISSION_EXPIRED`, `NOT_SENT` | No | Schedule |
| PostgreSQL unavailable at record time | Worker | Yes or no | Yes, later | Outcome not recorded; T-08 after the lease | **Yes** if it was sent | CMP-04 |
| Internal event replay after the claim exists | CMP-01 | n/a | n/a | No rows | No | — |
| Public replay request | Route 6J-028 | n/a | New delivery, own budget | T-03 | The receiver sees the event again by design | Tenant |

### 13.4 Terminal handling

| Terminal | Tenant-visible through | Retained | Next action available |
|---|---|---|---|
| `DELIVERED` | `GET /webhook-deliveries` | 30 days | Public replay |
| `DEAD_LETTER` | Same; platform-admin read-only view (6M) | 90 days | Public replay |
| `CANCELLED` | Same | NOT SPECIFIED → not purged until 7I sets it (HE-7I-7H-05) | None (not replayable under the frozen function) |

### 13.5 Public redelivery (domain G)

[FROZEN] from 6J §23.3 and `fn_replay_webhook_delivery`, except the rows tagged otherwise.

| Aspect | Contract |
|---|---|
| Who | A principal of the owning organization with `webhook:manage`. Authenticated as any public API call; the function additionally requires the caller's tenant context to equal the organization (`101_5I1` tenant-forgery guard) |
| What (the **parent**) | A `DEAD_LETTER` or `DELIVERED` delivery still inside its own retention. The frozen function accepts **any** such row, including a row that is itself a replay |
| Effect | A new row: same endpoint, topic, `event_id`, body and hash; fresh `id`; `replay_of_delivery_id` = the parent; `PENDING`, due now; its own `max_attempts` budget |
| Parent | Unchanged except `replay_count` and `last_replayed_at` |
| Signature | Fresh timestamp and signature at send; current secret (SIG-05) |
| Idempotency | A second request while a replay of the same parent is open returns that replay |
| Per-delivery rate | 10 replays of one parent per 24 h → `429 WEBHOOK_REPLAY_RATE_LIMITED` |
| Per-lineage rate [OD] | 10 replays per **lineage** per 24 h, counted across every descendant → the same `429` (OD-7H-10; ERR-7H-06) |
| Lineage window [OD] | A replay is created only while the lineage is open: `now()` < root `created_at` + 30 days if the root ended `DELIVERED`, + 90 days if it ended `DEAD_LETTER`. Otherwise `422 WEBHOOK_REPLAY_NOT_ALLOWED` (OD-7H-10; ERR-7H-01) |
| Endpoint not `ACTIVE` [OD] | `422 WEBHOOK_REPLAY_NOT_ALLOWED` (OD-7H-03), checked with the endpoint row share-locked (ELK-03). An endpoint row that no longer exists is refused the same way (OD-7H-18): a delivery dead-lettered as `ENDPOINT_GONE` is not replayable while its endpoint is absent |
| Organization not `ACTIVE` [OD] | Refused under the organization share lock (ADM-01). Normally unreachable: a suspended organization's principals are denied (4A) |
| Audit | `WEBHOOK_DELIVERY_REPLAYED`, synchronous: an audit failure rolls the replay back (AIR §18.1). Every replay is therefore attributable to an actor |
| Cross-tenant platform-admin replay | NOT BUILT — FUTURE (6M `DBGAP-6M-04`). No platform principal can redeliver another tenant's event in V1 |
| `CANCELLED` deliveries | Not replayable: the frozen guard admits only `DEAD_LETTER` and `DELIVERED` |

#### 13.5.1 Replay lineage (OD-7H-10)

**What the frozen function allows.** `fn_replay_webhook_delivery` (`063_5I`, re-issued in `101_5I1`) checks the parent's status, returns an open replay of that parent if one exists, and inserts. It does not ask whether the parent is itself a replay. The 10-per-24-hour limit is an application-layer quota per delivery ID (6J §23.3) and is not in the function. Consequences, each from the SQL as written:

1. **Recursion.** A replay that reaches `DELIVERED` is a legal parent. So are its replays, without limit of depth.
2. **Quota multiplication.** Each descendant has its own quota of 10. A root yields 10 children, they yield 100, they yield 1,000: 10^g deliveries in generation g, all inside the same 24 hours, because a replay to a healthy endpoint completes in seconds and the "one open replay" rule is per parent.
3. **Retention extension.** Each descendant is a new row with a new `created_at` and the full copied `payload_json`. Replaying the newest descendant shortly before its purge keeps the original body alive for another 30 or 90 days, indefinitely.
4. **Concurrency.** Two requests naming the **same** parent serialize on the parent's row lock, and the second returns the open replay. Two requests naming **different** descendants of one root share no lock. A quota checked in the application before the function call is also racy for one parent: two requests can both read "9 used", and after the first replay completes the second creates an eleventh.

| ID | Rule |
|---|---|
| LIN-01 [OD] | **Lineage.** The root of a lineage is a delivery created by fan-out or by the test route (`replay_of_delivery_id` is NULL). Every replay belongs to the lineage of its parent. Each replay row records the root's delivery ID and creation time; a lineage anchor record holds them, with the root's terminal status, after the root itself is purged (MR-7H-08). |
| LIN-02 [OD] | **Both quotas are enforced inside the replay transaction**, under the lineage anchor's row lock: fewer than 10 replays of this parent, and fewer than 10 replays in this lineage, created in the preceding 24 hours. Every replay of a lineage takes the same anchor lock, so the counts cannot be raced, whichever descendants the concurrent requests name. The frozen per-delivery quota is preserved unchanged. |
| LIN-03 [OD] | **Lineage window.** Eligibility to replay ends with the root's own retention: 30 days from the root's creation for a `DELIVERED` root, 90 days for a `DEAD_LETTER` root (6J §22.6). A descendant never extends it: the window is computed from the root's creation time held on the anchor, not from any descendant. |
| LIN-04 [OD] | **Retention is per row and never chained.** Each row, root or descendant, is purged by its own status and creation time under the frozen 30 / 90-day rule (MR-7H-07). 7H changes no frozen per-delivery retention and cancels no active replay to shorten it. Because no replay can be created after the lineage window closes, body retention is not indefinite. **Consequence, not an approved policy:** a copy of a body can exist until 120 days after the creation of a `DELIVERED` root (a replay created on the last day that itself dead-letters) and 180 days after the creation of a `DEAD_LETTER` root. The owner approved the 30 / 90-day replay **eligibility** of the root (OD-7H-10). The owner did **not** approve 120 or 180 days as a data-retention period. Whether replay copies must be purged earlier, on a lineage-anchored deadline, and how erasure reaches them, is 7I's decision (OD-7H-14; HE-7I-7H-08). **The public replay route is not activatable in production until 7I has recorded that decision** (AB-7H-08). |
| LIN-05 [7H] | **Resulting bound.** A lineage holds at most 10 replays per rolling 24 hours for at most 30 (or 90) days: at most 310 (or 910) replay deliveries over its whole life, each an authenticated, audited request by a tenant principal, each with its own automatic budget of at most `max_attempts` requests. |
| LIN-06 [7H] | The lineage root is internal. No response field, header or route is added; `replay_of_delivery_id` remains the only lineage information a tenant sees. |
| LIN-07 [7H] | A test delivery is a root like any other. Replays of it follow LIN-01 … LIN-05. |

### 13.6 Internal replay and the webhook engine

| ID | Rule |
|---|---|
| XRP-01 [FROZEN] | 7G never selects, wraps or imitates a webhook delivery. R7 is the 6J route only (7G §30, §44). |
| XRP-02 [FROZEN] | CON-10 is not a 7G replay target until its fan-out claim exists (7G §41.1). After that it is a high-risk target: stricter throttles and a mandatory dry-run (7G HRP-05). |
| XRP-03 [7H] | With the claim present, R2 – R5 reaching CON-10 produce no delivery row for an event that was already fanned out. Replaying an internal event after its external delivery succeeded therefore sends nothing (§18 trace 18). |
| XRP-04 [7H] | **Claim retention bounds the guarantee.** The claim ledger's retention is set by the governed migration (7F IO-7F-21) and is CON-10's evidence horizon (7G §34). [REC] 90 days, equal to OD-7G-03. A replay of an event older than that horizon is `RECONCILIATION_REQUIRED` (7G FC-07) and never reaches the handler, so an expired claim cannot cause a second fan-out. |
| XRP-05 [FROZEN] | For an event that was **never** fanned out (for example parked and later replayed under R2), the fan-out matches endpoints active at replay time (SUB-02). The replay plan states this as tenant-visible risk (7G §41.1). The envelope's `occurred_at` tells the receiver the fact is old. |
| XRP-06 [7H] | Replay never bypasses authorization: an internal replay delivers only to endpoints the owning organization configured, under that organization's tenant context, and a public replay requires `webhook:manage`. No replay path accepts a destination as a parameter. |

### 13.7 Endpoint health

**XRT-10 [FROZEN].** Automatic endpoint suspension (20 consecutive dead letters, 6J §22.5) is DEP-6J-07, FUTURE — NON-BLOCKING. No function reaches `SUSPENDED`. 7H does not activate it and assigns no threshold. A permanently broken endpoint costs at most `max_attempts` requests per event; the dispatcher's per-endpoint in-flight cap (COM-05) keeps it from occupying capacity. The policy remains available to a later governed change (HE-7K-7H-04).

---

## 14. Tenant Isolation, Security and Privacy Constraints

7I performs the cross-cutting security review. The controls below are the baseline 7H requires in order to be safe by construction; none is deferred.

### 14.1 Organization isolation

| ID | Rule |
|---|---|
| TEN-7H-01 [FROZEN] | The fan-out consumer establishes its tenant context from the trusted envelope `organization_id` and never from the payload (7A TEN-02; 7F §30). It matches only endpoints visible under that context. |
| TEN-7H-02 [FROZEN] | Every tenant table involved (`webhook_endpoints`, `webhook_deliveries`, `inbound_webhook_events`, `plugin_installations`, `plugin_executions`) has forced RLS on `organization_id = organization.current_tenant_id()`. No runtime role is a superuser or has BYPASSRLS (`001_5B`; D0 refuses to start otherwise). 7H asks for no change to that. |
| TEN-7H-03 [7H] | A delivery row's `organization_id` and its endpoint's `organization_id` are equal by construction: the row is inserted from an endpoint read under the same tenant context in the same transaction. The dispatcher reads the delivery and, at admission, the endpoint under the delivery's tenant context, so an endpoint of another organization is not visible to it and the attempt fails closed (`ENDPOINT_GONE`). |
| TEN-7H-04 [7H] | The dispatcher and the sweeps operate across tenants only through guarded functions that return **identifiers** (delivery ID, partition key, organization ID, claim sequence). No cross-tenant function returns a body, a URL or a secret reference. Bodies and endpoints are read afterwards under the specific tenant context. |
| TEN-7H-05 [7H] | One worker process handles deliveries of many organizations. Tenant context is set per transaction and never carried in process-global state between deliveries. Secrets, bodies and URLs of one delivery are never reused for another. |
| TEN-7H-06 [FROZEN] | A tenant-facing surface (delivery list / detail) shows only that organization's rows and never `claimed_by`, `payload_hash`, a secret or an authentication header (6J §23.1). |

### 14.2 Organization status (OD-7H-02 = hold while suspended; OD-7H-09 = bounded window)

| Organization status | New eligible events | `PENDING` deliveries | Claimed deliveries (`DELIVERING`) | Public replay / test | Evidence |
|---|---|---|---|---|---|
| `ACTIVE` | Fan-out creates rows | Dispatched on schedule | Admitted, sent, recorded | Allowed (endpoint `ACTIVE`) | — |
| `SUSPENDED` | Fan-out **still creates rows** (FAN-05) | **Held**: not claimable; `attempt_count` untouched; schedule time keeps elapsing | Not yet admitted: released uncounted at admission (T-09). Admitted before the suspension committed: may be sent inside the residual window of ADM-05, then recorded | Refused in-function under the same lock | Rows, claim, admission and closure records retained |
| `SUSPENDED` → `ACTIVE` | — | Claimable again immediately; rows whose `next_attempt_at` is in the past are due now | — | — | — |
| `SUSPENDED`, row older than 90 days | — | `CANCELLED`, reason `HOLD_EXPIRED` (T-11) | — | — | Row retained; one audit row per organization per sweep run |
| `CANCELLED` (terminal) | Fan-out still creates rows; they are closed by the next sweep | `CANCELLED`, reason `ORG_CANCELLED` (T-10) | As for `SUSPENDED` | Refused | Row retained; audit row |

#### 14.2.1 Synchronization with the organization status change

The frozen status-changing functions (`fn_platform_suspend_organization`, `fn_platform_reactivate_organization` and the cancellation path; `105_5B4`, `107_5B5`) each run `SELECT status … FROM organization.organizations WHERE id = … FOR UPDATE`, then `UPDATE`, then commit. That row lock is the only serialization point the platform has for organization status, and 7H uses it. A status predicate in a query does **not** by itself conflict with that lock: under `READ COMMITTED` a plain read sees the last committed status and proceeds, so the dispatcher could read `ACTIVE`, the suspension could commit, and the dispatcher could then commit its claim. The earlier draft's claim that "the same statement" serialized the two was wrong (P1-7H-R02, §26.2).

| ID | Rule |
|---|---|
| ADM-01 [OD] | **Share lock at every admission point.** Each function that lets work proceed for an organization takes a row-level `FOR SHARE` lock on that organization's row and evaluates its status **under that lock**, in the same transaction as the decision it guards. The admission points are: the dispatch claim (T-04); the final pre-send admission (T-04a / T-09); the replay function (T-03); the test route (T-02); the cancellation and hold-expiry sweeps (T-10, T-11). `FOR SHARE` conflicts with the `FOR UPDATE` and with the row update of the status-changing functions, and not with other `FOR SHARE` holders, so dispatchers never block each other. |
| ADM-02 [7H] | **What the lock gives.** For any admission point P and any status change S of the same organization, exactly one of two orders is possible. Either P's transaction commits before S can acquire its lock, so S commits after P; or S holds the lock first, P waits (or skips), and when P obtains the row it re-evaluates the row's latest committed version and sees the new status. PostgreSQL re-checks the selection condition against the updated row version after a lock wait in `READ COMMITTED`, so P cannot act on the pre-change status. There is no interleaving in which P observes `ACTIVE`, S commits, and P then commits its decision. |
| ADM-03 [7H] | **Waiting and skipping.** The dispatch claim locks delivery rows `FOR UPDATE SKIP LOCKED` and organization rows `FOR SHARE SKIP LOCKED`: an organization whose status is being changed at that instant is skipped for this poll and picked up by the next. The claim therefore never waits on any lock. The admission, replay and test functions take the organization lock without `SKIP LOCKED` and wait; the status-changing transaction is short. |
| ADM-04 [7H] | **Lock order and absence of deadlock.** Any function that can wait acquires its row locks in one global order: organization (share) → lineage anchor → delivery → endpoint (share). The claim and the sweeps never wait. The status-changing functions lock only the organization row and no delivery or endpoint row. No cycle is possible: the only exclusive locker of an organization row holds nothing else, and no waiter holds a lock that a claim or sweep would wait for. The endpoint row's place in this order is proven in §14.2.2. |
| ADM-05 [OD] | **The guarantee** (replaces the earlier absolute statement). Let `t_s` be the commit time of a transaction that moves an organization out of `ACTIVE`. **G1** No dispatch claim for that organization commits after `t_s`. **G2** No admission (T-04a) for it commits after `t_s`; an admission attempted after `t_s` executes T-09 instead. **G3** A request is initiated only within `T_admit` = 6 s of its own admission (HTP-16). Hence no request for that organization is **initiated** after `t_s` + 6 s. **G4** Every request ends within its `timeout_ms` ≤ 30 s of initiation. Hence no request for that organization is **in progress** after `t_s` + 36 s. **G5** The requests that can start inside the window are only those whose admission committed before `t_s` and which had not yet been sent: at most one per delivery already in `DELIVERING` for that organization, itself bounded by the per-organization dispatch cap (COM-04). **G6** No replay or test delivery for that organization is created after `t_s`. |
| ADM-06 [7H] | **What is not guaranteed.** A request admitted before `t_s` may be initiated up to 6 s after `t_s`. The platform cannot recall bytes already sent, and a database lock cannot be held across the HTTP call (INV-NOSPAN), so a zero window is not achievable. G3 also assumes that a worker which passes its local timer check hands the request to the network without an unbounded stall. A process frozen by its host between that check and the connect call is outside the bound; the check is therefore placed immediately before the egress adapter call, and the adapter treats the same deadline as a condition for starting to connect. |
| ADM-07 [7H] | **No transaction across HTTP.** The admission transaction commits, releasing the share lock, before signing and sending begin. Nothing in ADM-01 … ADM-06 keeps a PostgreSQL transaction or lock open during network I/O. |
| ADM-08 [7H] | Reactivation needs no special handling: after it commits, claims succeed again. A reactivation racing a hold-expiry or cancellation sweep is serialized by the same lock, so a row is cancelled only if the organization was not `ACTIVE` when the cancellation committed. |
| ADM-09 [7H] | The organization row lock requires a privilege the dispatcher role does not have on `organization.organizations`. The lock is therefore taken inside the guarded functions of §17.3, never by an ad-hoc statement of the worker. |

| ID | Rule |
|---|---|
| TEN-7H-07 [OD] | After an organization leaves `ACTIVE`, no new claim, admission, replay or test delivery is committed for it, and no HTTP request is initiated for it later than 6 s after that change committed (ADM-05). This is the exact form of OD-7H-02's "no HTTP while not `ACTIVE`", as approved in OD-7H-09. |
| TEN-7H-08 [7H] | The residual window is evidenced, not hidden: an attempt sent inside it has an admission record whose `admitted_at` precedes the organization audit event's time, and a closure record whose time follows it. |
| TEN-7H-09 [7H] | Suspension is not destruction. No delivery row, claim, admission or closure record, endpoint, secret reference or fan-out claim is deleted or altered because an organization is suspended. Cancellation changes `status`, `completed_at` and `failure_reason` only; the identity and body stay immutable. |
| TEN-7H-10 [7H] | On reactivation after a long suspension a backlog becomes due at once. It is released under the per-organization and per-endpoint caps of §20 so that it cannot starve other tenants; receivers see old `occurred_at` values and deduplicate normally. |

#### 14.2.2 Synchronization with endpoint configuration changes (P1-7H-R08)

**What the frozen mutators lock** (static reading of the SQL). `webhooks.fn_rotate_webhook_secret` (`101_5I1` L1245 – L1282) runs `SELECT signing_secret_ref … FROM webhooks.webhook_endpoints WHERE id = … AND organization_id = … FOR UPDATE`, then one `UPDATE` of the three secret columns, and returns. It reads no organization row and no delivery row. `PATCH`, enable, disable and the `DELETE` alias are ordinary `UPDATE` statements by `app_api` under RLS (`062_5I` L34; 6J §18.5 – §18.8), each taking the row's update lock. Hard deletion is a `DELETE` by `app_platform_admin` (`062_5I` L36; `109_5B7` Part G narrowed `webhook_deliveries` only, not endpoints). `webhook_deliveries` has no foreign key to `webhook_endpoints` (`063_5I`), so none of these touches a delivery row. `audit.fn_insert_audit_event` (`072_5J`) inserts and takes no row lock or advisory lock. No migration other than `062_5I` and `101_5I1` references `webhook_endpoints`. A plain `READ COMMITTED` read conflicts with none of these locks. The version reviewed third had the admission read the endpoint that way, so the admission could read revision r, a rotation could commit r+1, and the admission could then commit recording r. Guarantee C1 was asserted without a mechanism.

| ID | Rule |
|---|---|
| ELK-01 [7H] | **Share lock for the admission read.** The admission function reads the endpoint with a single row-locking statement, `FOR SHARE`, selecting by endpoint ID and organization ID, and takes every configuration value it returns or records from the row version **that statement** returns. It holds the lock until the admission transaction commits, which is after the admission record is inserted. The function runs at `READ COMMITTED`. No other statement of the worker reads a configuration value. |
| ELK-02 [7H] | **What the lock gives.** `FOR SHARE` conflicts with the `FOR UPDATE` of the rotation function, with the row lock of any `UPDATE` and with `DELETE`. It does not conflict with other `FOR SHARE` holders, so admissions of different deliveries to one endpoint never block each other. For an admission P and a mutation M of the same endpoint, M committing at `t_x`, exactly three orders exist. (i) P locks first: M waits for P's commit, so P commits before `t_x`, and the revision r it recorded was current when it committed. (ii) M locks first: P waits; when M commits, PostgreSQL re-fetches the latest committed row version for the locking statement and P reads r+1. If M was a delete, P finds no row: `ENDPOINT_GONE`. If M rolled back, P reads r, which is still current. (iii) M committed before P's statement began: P reads r+1. In no order does P commit after `t_x` having recorded r. This is C1 of SIG-14, and it does not rely on the re-check. |
| ELK-03 [7H] | **Other readers that decide on the endpoint.** The replay function and the test path, which already required the endpoint "with its row locked", take the same `FOR SHARE` lock (MR-7H-08). A share lock is sufficient for their existence and status check and does not block admissions. |
| ELK-04 [7H] | **Deadlock freedom.** Endpoint share locks are taken last in the global order of ADM-04, and a transaction holding one acquires no further row lock: the admission then only inserts its records; the replay then inserts the new delivery, updates the parent it already holds and inserts its audit row. The exclusive lockers of an endpoint row (rotation, `PATCH`, enable, disable, hard delete) hold no organization, anchor or delivery lock, and after the endpoint row they only insert an audit row. So a holder of an endpoint lock never waits for another row lock, and every wait-for chain that reaches an endpoint lock ends there. Pairings checked: admission against rotation, `PATCH`, disable and delete (one waits for the other, and the one waited for holds nothing the waiter needs released first); admission against suspension (the suspension waits for the organization share lock; an admission holding that lock never waits for the suspension); replay against admission (both share); replay against rotation (as admission against rotation); the claim and the sweeps (they never wait and never touch an endpoint row); two mutators (serialized on the one row). No transaction upgrades an endpoint share lock to an update lock, because neither the admission nor the replay writes the endpoint row. |
| ELK-05 [7H] | **Rules that keep ELK-04 true.** (a) The best-effort `last_delivery_at` touch (T-05) is **not** part of the closure transaction: it is its own statement after the closure commits, it skips the row if the row is locked, and it runs with no delivery lock held. Otherwise a closure would wait on the endpoint row while holding a delivery row. (b) Any future function that needs an organization row and an endpoint row (for example the endpoint-count enforcement of IO-7H-17) takes the organization first. (c) An endpoint-mutating transaction writes its audit row after the endpoint statement and takes no other row lock. (d) The admission's wait for the endpoint lock is bounded by a lock timeout below `T_admit` ([REC]; value 7K). A timed-out admission has inserted nothing; the worker closes the claim `ADMISSION_EXPIRED`, `NOT_SENT` (OD-7H-13). The admission timer was started before the call, so time spent waiting only makes the 6 s bound more conservative. |
| ELK-06 [7H] | **Short transactions.** The share lock lives only inside the admission transaction: lock, read, insert, commit. It is released before secret resolution, the re-check, signing and HTTP (INV-NOSPAN; ADM-07). A tenant's rotation or `PATCH` is therefore delayed only by the admissions in progress at that instant. PostgreSQL does not promise that a waiting writer is served before share lockers that arrive later, so under a continuous overlap of admissions to one endpoint a mutation could wait longer. The per-endpoint in-flight cap (COM-05) bounds that overlap; measuring it and setting the mutation-side timeout is 7K's (HE-7K-7H-07). This is a latency matter for the mutation, not a correctness matter for C1. |
| ELK-07 [7H] | **What the lock does not give.** It serializes admissions with mutations. It says nothing about a mutation that commits after the admission has committed: that request proceeds under r until its re-check (C2) or, if the mutation commits after the re-check, is sent under r inside the residual of SIG-15 and the bound C4. The independent last-instant re-check is unchanged, and physical network hand-off is not atomic with any database state. Endpoint `status` is not part of the configuration revision: a disable waits briefly for admissions in progress and then commits, and deliveries already created "complete normally" as before (6J §18.8). |
| ELK-08 [7H] | **Isolation.** The lock is taken inside the guarded admission function, by endpoint ID **and** the delivery's organization ID, under that tenant's context. The dispatcher role gains no table privilege from it, and no endpoint of another organization can be locked or read through it. |

At an isolation level stricter than `READ COMMITTED` the locking read would fail with a serialization error instead of returning the newer version. The call would then insert nothing and be handled as in ELK-05 (d). It would never return a stale revision. The function is nevertheless specified at `READ COMMITTED`.

### 14.3 Other tenancy and compliance situations

| Situation | Outcome | Basis |
|---|---|---|
| Endpoint `DISABLED` by the tenant ("paused") | No new delivery; pending and in-flight complete; replay and test refused | [FROZEN] 6J §18.8; [OD] OD-7H-03, OD-7H-06 |
| Tenant loses a feature entitlement | **No entitlement gates webhooks in V1.** No frozen plan feature, quota metric or permission ties webhook delivery to a plan (NOT FOUND in 6K; 6J J4 FUTURE). Nothing changes | NOT SPECIFIED; no rule invented |
| The registering user is removed | No effect (§6.3) | [FROZEN] |
| Endpoint secret rotated with grace 0 ("revoked") | No attempt admitted or re-checked after the rotation commits signs with the old secret. A request already past its re-check is the residual of SIG-15 and SIG-16 | [FROZEN] 6J §21.3; [OD] OD-7H-12 |
| DNC / consent state of a contact changes | No effect on webhook delivery. No frozen contract conditions any of the 19 topics on DNC or consent. A webhook delivers the tenant's own data to the tenant's own system; it is not an outbound contact attempt. Compliance flows stay auditable through the audit boundary (7A RES-04) | NOT SPECIFIED for webhooks; HE-7I-7H-03 |
| Erasure or legal-retention request touching data inside a retained `payload_json` | **DEFERRED BY FROZEN CONTRACT** to 7I (7A §25 "DSR interaction with retained events"; 5I ODD-5I-04 "requires legal review"). 7H guarantees only that the body is never widened after creation and that port-read fields reflect state at fan-out, so data erased before fan-out is not resurrected | HE-7I-7H-02 |
| Platform administrator attempts cross-tenant redelivery | Not possible. The replay function requires the caller's tenant context to equal the organization and is not granted to the platform-admin role; platform-admin DML on deliveries is revoked (`109_5B7`). Read-only inspection exists (6M) | [FROZEN] 6M `DBGAP-6M-04`, `DBGAP-6M-10` |
| Platform administrator hard-deletes an endpoint | Each later claim of a pending delivery is closed `ENDPOINT_GONE`, `NOT_SENT`, origin PLATFORM, one attempt each, on the frozen schedule; `DEAD_LETTER` by exhaustion only; no HTTP; replay refused while the row is absent. A tenant's disable is a different case and leaves the row | [OD] OD-7H-18 |

### 14.4 Outbound network controls

The egress adapter (CMP-05) is the only code allowed to open a connection to a tenant-configured or plugin-declared URL (6J ADR-6J-06). A tenant-controlled URL is never trusted.

| Control | Rule | Tag |
|---|---|---|
| Scheme | `https` only; enforced by the DB CHECK, at registration, at every `PATCH` and at every attempt | [FROZEN] 6J §30.3 |
| Credentials in URLs | A `target_url` containing a userinfo component (`user:pass@`) is rejected as unsafe (`422 WEBHOOK_URL_UNSAFE`) at registration and treated as `DESTINATION_BLOCKED` at delivery. The platform never extracts credentials from a URL and never sends an `Authorization` header derived from one | [7H]; within the frozen code's stated scope ("fails SSRF validation") |
| Query strings | Allowed (tenants commonly embed a routing token). The query string is treated as a secret: never logged, traced or shown outside the endpoint resource itself | [7H] |
| Address blocking | Loopback, link-local, RFC 1918, IPv6 unique-local, unspecified, multicast and cloud-metadata addresses are rejected. No allow-list exists in V1 (J2 FUTURE) | [FROZEN] |
| IPv4 / IPv6 | Every A and AAAA result is evaluated; IPv4-mapped IPv6 is unwrapped and evaluated as IPv4. **[7H]** If any address in the answer set is blocked, the destination is rejected: the adapter does not pick a "good" address out of a mixed answer | [FROZEN] + [7H] |
| DNS rebinding | Resolve fresh at every attempt, validate, then connect to the validated address ("resolve-then-pin"). No resolution result is reused across attempts | [FROZEN] |
| TLS | SNI and `Host` are the original hostname; the certificate is verified against that hostname. Verification is never disabled, per endpoint or globally | [FROZEN] |
| Redirects | A 3xx on a webhook delivery is **never followed**. No credential or signature header crosses a redirect in any adapter call | [FROZEN] 6J §22.4, §30.3 |
| Port | 443 only for webhooks | [FROZEN] |
| Proxy / egress routing | All adapter traffic leaves through the platform's controlled egress path. If that path uses a forward proxy, address validation and pinning are enforced at the point that actually opens the TCP connection, not only before the proxy. The adapter never uses environment-provided proxy settings implicitly | [7H]; topology is 7K's |
| Timeouts and size | §9.4, §9.5 | [FROZEN] |
| Rate and abuse | Bounded work per event (§20.2); per-endpoint in-flight cap; test and replay quotas | [7H] |

### 14.5 Secrets and encryption

| ID | Rule |
|---|---|
| SEC-7H-01 [FROZEN] | Rows hold only opaque `secret_manager://` references (DB CHECKs). Raw secrets exist in the secret manager and transiently in worker memory. A signing secret is shown to the tenant exactly once (6J §18.3, §21.3). |
| SEC-7H-02 [7H] | Only the dispatcher resolves webhook signing secrets, and only by the references of the revision it was admitted under; only the plugin executor resolves plugin secrets; only provider adapters resolve integration credentials (SIG-13). The fan-out consumer resolves none. The dispatcher does not hold the destination-evidence key; the endpoint-mutating service does (DST-03). |
| SEC-7H-03 [FROZEN] | Transport is TLS with verification. At-rest encryption of PostgreSQL and the secret manager is a platform property owned by deployment (Phase 22) and reviewed in 7I. |
| SEC-7H-04 [7H] | The previous secret's secret-manager entry is purged after its grace window by the application service (6J §21.3), and **not before** `previous_secret_expires_at` has passed: a purge inside the grace turns every attempt of that endpoint into situation (4) of SIG-18. The dispatcher never signs with a previous secret after a re-check has shown its grace over, even if the reference and the entry are still present. |

#### 14.5.1 Effective-destination evidence and configuration revisions

The questions this evidence must answer, after the fact and without storing a readable URL: *to exactly which destination was this attempt directed; under which configuration change did the endpoint come to have that destination; and who made that change?*

**Authoritative identity of a configuration change.** Each endpoint carries a `config_revision`: an integer that starts at 1 when the endpoint is created and increases by exactly one in every transaction that changes any of `target_url`, `timeout_ms`, `signing_secret_ref`, `previous_signing_secret_ref` or `previous_secret_expires_at`. The increment happens in the mutating transaction, under the endpoint's row lock. An admission reads the row under a conflicting share lock (ELK-01), so the revision it records is the latest one committed when the admission itself commits. Two changes of one endpoint therefore cannot commit with the same revision, and the order of revisions **is** the order in which the changes took effect. (`endpoint_id`, `config_revision`) is the identity of one configuration state. It is absent from the frozen schema (MR-7H-11). It is internal: the public `ETag` contract of 6J §18.4 and §34 (derived from `updated_at`; ADR-6A-08) is unchanged.

| ID | Rule |
|---|---|
| DST-01 [7H] | **Canonical effective destination.** From `target_url`: the lower-cased scheme; the host in lower-case ASCII (A-label form), without a trailing dot; the port as an explicit decimal number (443 when the URL gives none); the path exactly as stored, octet for octet, with an empty path written as `/`; and the query exactly as stored, with "no query" distinguished from "empty query". Percent-encoding is **not** decoded or re-normalized and dot-segments are not collapsed: two URLs that differ in any of these are different requests to the receiver and must have different evidence. A fragment is never sent and is excluded. A URL with userinfo is rejected before this point (§14.4). |
| DST-02 [7H] | **Fingerprint.** `HMAC-SHA256(K, encode("7h-dest-v1", organization_id, webhook_endpoint_id, scheme, host, port, path, query))`, where `encode` length-prefixes each component so that no two different tuples produce the same input, and `K` is the destination-evidence key identified by a key ID (MR-7H-10). Binding the organization and endpoint into the input means equal URLs of two tenants, or of two endpoints, do not produce equal fingerprints. |
| DST-03 [7H] | **Privacy boundary.** The fingerprint is not reversible and, without `K`, cannot be tested against guessed URLs. `K` lives in the secret manager and is used only by the service that mutates endpoints and by an authorized investigation function; the dispatcher does not need it. It is never readable through a tenant route, a log or a database row. The path and the query are stored **nowhere** outside `webhook_endpoints.target_url` itself: not in a history record, an audit row, a log, a span or a metric. Host and port may be stored in clear beside the fingerprint for operations (LOG-7H-02). |
| DST-04 [7H] | **The fingerprint belongs to the revision and is written with it.** The transaction that creates an endpoint or changes its `target_url` stores, on the endpoint row, the fingerprint of the new destination and its key ID, together with the new `config_revision`. A change that does not touch `target_url` (a timeout change, a rotation) increments the revision and keeps the stored fingerprint. The database refuses a change of `target_url` that does not also supply a fingerprint. One row version therefore always holds a matching (revision, destination, fingerprint, key ID). |
| DST-05 [7H] | **The audit record of a change is written in the same transaction as the change.** 7D AUD-7D-01 and AUD-7D-02 (owner decision OD-7D-02 = A) require every mandatory audit record, including the 84 routes that 6J and AIR label `AUDIT_ASYNC`, to be written by `audit.fn_insert_audit_event()` inside the originating business transaction. Endpoint creation and update are among them. The audit row of a configuration change therefore commits or rolls back with the change, and carries: the endpoint ID; the new `config_revision` and the previous one; which attribute classes changed (destination, timeout, signing secret); the new fingerprint and key ID and, for a destination change, the previous fingerprint. It carries no URL, path, query or secret reference value. 6J §36.2 still prints "Async" for these actions; that wording awaits the documentation alignment 7D recorded as IO-7D-16 (CNF-7H-18). |
| DST-06 [7H] | **The admission names the revision.** Every admission record carries the `config_revision`, fingerprint and key ID it read from the endpoint row, in the same transaction, before the request is sent (HTP-15). Because the admission reads a committed row version, the revision it records was created by a transaction that had already committed, and so had its audit row. |
| DST-07 [7H] | **Correlation is by revision, never by time.** An attempt is attributed to a configuration change by the equality (`endpoint_id`, `config_revision`) between its admission record and the audit row. No timestamp comparison is involved. The three times that exist are informational: *mutation time* is the endpoint row's `updated_at`, which is the start time of the mutating transaction (`NOW()` in `set_updated_at`, `001_5B`) and therefore not a reliable commit order between concurrent transactions; *admission time* is `admitted_at`, the database clock inside the admission transaction; *audit time* is the audit row's own timestamp, identical in meaning to mutation time because it is the same transaction. |
| DST-08 [7H] | **Robustness if an implementation still materializes audit late.** Should the audit row of revision r+1 be written after an attempt was admitted under r+1 (contrary to DST-05), attribution is unaffected: both carry r+1. A duplicated audit row carries the same (`endpoint_id`, revision) and is recognizable as a duplicate. Audit rows written out of order are ordered by revision. What a late-audit implementation **cannot** survive is a crash between the mutation's commit and the audit write followed by a second change: the row's fingerprint for r+1 is then overwritten by r+2 and the audit of r+1 could not be rebuilt. This is exactly the loss 7A AUD-04a forbids and 7D closes by putting the write in the transaction. An implementation that does not follow 7D AUD-7D-01 for endpoint mutations is non-conformant (AB-7H-02). |
| DST-09 [7H] | **What the closure adds.** The closure records the send state, the address the connection was pinned to (when a connection was attempted), and the category. A redirect response is recorded as sent-and-refused (`REDIRECT_NOT_FOLLOWED`); the `Location` value is never stored, because it is attacker- or tenant-controlled and may carry secrets. |
| DST-10 [7H] | **Evidence-key rotation.** A new key ID is used for fingerprints computed from then on, that is, for revisions created after the rotation. A revision keeps the fingerprint and key ID it was created with; an admission copies both. So an admission's fingerprint always equals its revision's fingerprint, across any number of key rotations, and correlation never depends on comparing fingerprints made under different keys. Old keys are retained, for verification only, while any record references them. |
| DST-11 [7H] | **Authorized investigation.** Reading history records and audit rows follows their existing access rules (tenant RLS; platform access under 6B / 6M break-glass). Confirming a candidate URL against a fingerprint requires use of `K` and is a separate, audited capability whose holder 7I assigns (HE-7I-7H-09). A tenant can always see its own current `target_url`; no surface shows a tenant, or anyone, a past URL. |

| Case | Admission record | Closure send state | Address connected | Reading |
|---|---|---|---|---|
| Sent, answered | Revision r, fingerprint F | `SENT` | Recorded | Sent to the destination of r |
| Sent, redirect returned | r, F | `SENT`, `REDIRECT_NOT_FOLLOWED` | Recorded | Sent to F; nothing sent to the redirect target |
| DNS failure | r, F | `NOT_SENT`, `DNS_FAILURE` | None | Directed at F; nothing sent |
| Blocked by egress policy | r, F | `NOT_SENT`, `DESTINATION_BLOCKED` with the rule code | None (a blocked internal address is not stored) | Directed at F; nothing sent |
| TLS failure | r, F | `NOT_SENT`, `TLS_FAILURE` | Recorded | Connected, no request written |
| Admission window missed | r, F | `NOT_SENT`, `ADMISSION_EXPIRED` | None | Nothing sent |
| Secret unavailable (current, or a required previous) | r, F | `NOT_SENT`, `SECRET_UNAVAILABLE`, with the secret role | None | Nothing sent |
| Configuration changed, re-admitted | A(d, k, 1): r, F. AB(d, k, 1): `CONFIG_CHANGED`, `NOT_SENT`. A(d, k, 2): r′, F′ | By the outcome under admission 2 | Per that outcome | Nothing sent under r; whatever was sent went to F′ |
| Configuration changed twice | A(d, k, 1), AB(d, k, 1), A(d, k, 2); no AB for admission 2 | X(d, k): `NOT_SENT`, `CONFIG_CHANGED`, one attempt | None | Nothing sent under either admission |
| Worker died after an admission | Latest admission: r, F | `UNCERTAIN`, `CLAIM_EXPIRED` (by the sweep) | Unknown | May have been sent to the destination of the **latest** admission, and to nothing else |
| Worker died before any admission | None | `NOT_SENT`, `CLAIM_EXPIRED` | None | Certainly nothing sent |
| Organization not `ACTIVE` at admission | None for that admission | `NOT_SENT`, `RELEASED_ORG_NOT_ACTIVE` | None | Certainly nothing sent |
| Endpoint row absent | None | `NOT_SENT`, `ENDPOINT_GONE` | None | Certainly nothing sent |

Because an admission record commits before the first byte, every request that was or may have been sent has a committed revision and fingerprint. A request with no admission record cannot exist (DSM-07 H6).

### 14.6 Audit

Audit rows are accountability records written through `audit.fn_insert_audit_event()` (7A AUD-02). An ordinary delivery attempt is not an audit event; its evidence is the delivery row and its claim, admission and closure records.

| Action | Audit token | Synchrony | Source |
|---|---|---|---|
| Endpoint created / updated / enabled / disabled (incl. `DELETE`) | `WEBHOOK_ENDPOINT_CREATED` / `_UPDATED` / `_ENABLED` / `_DISABLED`. A change of the delivery configuration additionally carries the new and previous `config_revision`, the changed attribute classes and the destination fingerprint(s) with key ID (DST-05; ERR-7H-07) | **Same transaction as the mutation** (7D AUD-7D-01, AUD-7D-02; OD-7D-02 = A). 6J §36.2 prints "Async"; its alignment is pending as 7D IO-7D-16 (CNF-7H-18) | [FROZEN] 6J §36.2 (tokens); [FROZEN] 7D §36 (synchrony); [7H] (content) |
| Plugin callout refused because the limiter is unavailable | No audit row per callout; the `plugin_executions` row is the evidence (PLG-18) | — | [OD] OD-7H-11 |
| Secret rotated | `WEBHOOK_SECRET_ROTATED`, carrying the new `config_revision` | Sync | [FROZEN]; [7H] (revision) |
| Public replay | `WEBHOOK_DELIVERY_REPLAYED` | Sync | [FROZEN] |
| Test delivery | NOT SPECIFIED: 6J §36.2 lists no token. The delivery row (`platform.test`) is the evidence | — | — |
| Organization suspended / reactivated / cancelled | Existing organization audit actions | Per the owning function | [FROZEN] `105_5B4`, `107_5B5` |
| System cancellation of held or cancelled-organization deliveries (T-10, T-11) | One audit row per organization per sweep run, with reason and count, written in the same transaction as the status changes. Needs a vocabulary token in the existing style (proposed `WEBHOOK_DELIVERY_CANCELLED`) | Sync with the sweep transaction | [7H]; vocabulary extension ERR-7H-04 |
| Failed and dead-lettered deliveries | No audit row. Evidence: the delivery row (retained 90 days) and its claim, admission and closure records | — | [FROZEN] 6J §22.6; MR-7H-06 |
| Plugin and integration management actions | 6J §36.2 tokens | Per 6J | [FROZEN] |

**AUD-7H-01 [FROZEN].** No audit row carries a secret, a resolved credential, a body or a signed URL (6J §36.3).

### 14.7 Logging and residency

| ID | Rule |
|---|---|
| LOG-7H-01 [FROZEN] | Never logged, traced, put in a metric label or an error: signing secrets, resolved credentials, `Authorization` values, signature header values, tokens, URL userinfo or query strings, request or response bodies, signed media URLs, transcript or recording content (7A SEC-01, SEC-04, SEC-07; 6J §44.4; D0 redaction pipeline). |
| LOG-7H-02 [7H] | A destination is logged as scheme, host and port only. An error is logged as its category code (HTP-14). |
| RES-7H-01 [FROZEN] | For `INDIA_ENTERPRISE` tenants, delivery rows, bodies, claim, admission and closure records, fan-out claims, lineage anchors, callback processing inputs, logs and inbound receipts stay in the contracted region. No cross-region event bus exists (7A RES-02, RES-03). |
| RES-7H-02 [LATER] | Whether an `INDIA_ENTERPRISE` tenant's webhook destination itself may be outside the contracted region is a tenant-directed transfer question: NOT SPECIFIED by a frozen source. Handed to 7I (HE-7I-7H-04). The egress path and its proxy run in-region regardless. |

---

## 15. Payload / Schema Versioning

| ID | Rule |
|---|---|
| VER-7H-01 [FROZEN] | Three independent axes: internal `event_version` (7C), webhook topic version (AVS AX-E: topic string `X.vN`, envelope `version`, `X-Platform-Webhook-Version`), signature scheme (AX-F, `v1=`). None follows `/api/v1` and none follows another (7A VER-01, VER-08; 7C WHB-06). |
| VER-7H-02 [7H] | The topic map is keyed by the exact internal pair (`event_type`, `event_version`). A new internal version is a new key and needs its own entry and serializer before it can be externalized. Until then it produces no delivery, and the consumer's handling of an unsupported pair is 7C / 7F / 7G's (`COMPATIBILITY_HOLD`). |
| VER-7H-03 [FROZEN] | An internal `event_version` change never changes a topic, a topic version or the signature (7C WHB-06). The serializer absorbs it: a V2 internal payload must still render the same V1 public object, or a successor topic is required. |
| VER-7H-04 [FROZEN] | Additive public field: allowed in place (CM-WH-01); receivers are tolerant readers. Breaking change or envelope change: successor topic `X.vN` only; the predecessor keeps its schema and is never removed or repurposed (CM-WH-02 … CM-WH-06). No successor topic exists today. |
| VER-7H-05 [7H] | A body is rendered once with the serializer of the build that ran the fan-out and is then immutable. Deliveries created before a serializer change keep their old body through every retry and replay. A receiver can therefore see old-shape and new-shape bodies of the same topic interleaved during and after a rollout; with additive-only changes both are valid V1. |
| VER-7H-06 [7H] | **Successor topics: nothing is delivered twice by 7H, and one question is left to governance.** No successor topic exists and the route rejects any topic outside the 19, so in V1 an endpoint receives at most one body per event. The earlier draft said an endpoint subscribed to both `X` and `X.vN` would receive two deliveries with the same event ID. That is withdrawn: the frozen receiver rule is to deduplicate on the event ID (6J §21.2 rule 4), so a conforming receiver would process whichever body arrived first and silently discard the other, which could be the successor it migrated to (Minor-7H-R02; CNF-7H-17). 7H changes neither the event identity nor the signing contract to work around this. |
| VER-7H-06a [LATER] | **Precondition for the first successor topic.** The governed AX-E change that introduces any `X.vN` must, before the topic becomes subscribable, settle the per-endpoint rule, because it is a public-contract choice: either (i) at most one delivery per event and endpoint **per topic family**, rendered with the highest version that endpoint subscribes to, which keeps the event-ID dedup rule intact; or (ii) an amended receiver rule that deduplicates on event ID **and** `type`, which changes frozen 6J §21.2. 7H's fan-out is compatible with (i) without schema change: the fan-out claim is per event, and the endpoint selection already runs once per endpoint. Until that change decides, a topic-map entry for a successor is not deployable (HE-7L-7H-06). |
| VER-7H-07 [FROZEN] | Retirement of a topic string is prohibited (CM-WH-04). "Retirement of old external payload versions" therefore has no V1 procedure: an old topic keeps delivering. |

---

## 16. Ordering and Contract-Generation Compatibility

### 16.1 Ordering

| ID | Rule |
|---|---|
| ORD-7H-01 [FROZEN] | External delivery has **no ordering guarantee**: not global, not per endpoint, not per topic, not per resource (6J §22.2; 6A §28.1). |
| ORD-7H-02 [7H] | The internal per-key ordering of 7E / 7F does not survive the bridge and is not a promise to tenants. Fan-out transactions of different entries commit independently; deliveries are claimed concurrently; retries reorder them by hours. `call.started` may arrive after `call.completed`. |
| ORD-7H-03 [FROZEN] | A receiver that needs order uses `occurred_at`, or reads current state from the REST API (6J §22.2). |
| ORD-7H-04 [7H] | No component may introduce an ordering dependency to "fix" this: no per-endpoint serialization, no blocking of delivery n + 1 on delivery n. That would let one failing delivery block a tenant's stream. |

### 16.2 The generations that exist

| Generation | Exists? | Where | Changes by |
|---|---|---|---|
| Internal event contract (`event_type`, `event_version`) | Yes | 7C manifest | 7C compatibility process |
| Handler-contract generation `c(g)` of `cg.integrations.webhook-engine` | Yes | 7F handler-contract record | 7F closed-group cutover (CUT-1 … CUT-9) |
| Public topic version | Yes (all 1) | Topic string; envelope `version` | AX-E successor topic |
| Subscription version | **No** | — | — (TRM-02) |
| Endpoint configuration revision | **Not in the frozen schema; required** | A future `config_revision` on the endpoint row (MR-7H-11) | Every change of URL, timeout, signing references or previous-secret expiry. It does not pin deliveries (OD-7H-01 = A) |
| Signing secret generation | Two at most: current and previous | Endpoint row | `rotate-secret` |

### 16.3 How `H_active(g)` and `H_capable(build, g)` govern the bridge

7H uses these exactly as 7F §10.4 defines them and extends neither.

| ID | Rule |
|---|---|
| GEN-7H-01 [FROZEN] | What the webhook engine **owes** is `A(g, E)`, computed from the handler-contract record's obligation intervals. It is never inferred from the handlers, the topic map or the serializers compiled into a build (7F HCG-01, HCG-05). |
| GEN-7H-02 [FROZEN] | A worker build may read from the group only if `H_required(g) ⊆ H_capable(build, g)` (HCG-02). For this group, "capable of type T" means the build contains a conformant handler for T: the claim logic **and** a topic-map entry and serializer for every (T, version) pair in the manifest. |
| GEN-7H-03 [7H] | The topic map is part of `H_capable`, never part of `H_active`. Deploying a build with a new topic-map entry changes what the build can do and changes nothing about what the group owes (REG-7F-04: "deploying new code never changes `H_active(g)` by itself"). |
| GEN-7H-04 [FROZEN] | An entry with a canonical origin record `O(g, event_id, event_type)` is evaluated from that record's `origin_obligation`, whatever stream position or generation it arrives on (HCG-28 … HCG-31). For the webhook engine: a replayed event that the group did **not** owe when it was produced (`NOT_OWED`) is never fanned out, even if the group owes that type today. |
| GEN-7H-05 [7H] | Generation 1 of this group contains the 17 types of 7F §28.11. EV-004 `call.initiated` and EV-005 `call.ended` are **not** in it. Delivering `call.started` and `call.completed` requires a governed 7B / 7E registry change that binds R-004 and R-005 to the group, and a 7F addition cutover (AB-7H-03). 7H performs neither. |
| GEN-7H-06 [FROZEN] | An addition has an activation boundary and no implicit backfill (7F HCG; CUT). Tenant-visible consequence: `call.started` / `call.completed` deliveries begin with events published after the boundary. Calls before it produce none unless an approved R3 backfill is run, which would match endpoints active at backfill time (XRP-05). |

### 16.4 Compatibility examples with old and new deployments running together

**Example 1 — adding the two call topics (handler-contract change).**
Build N: `H_capable` = 17 types. Build N+1: 19 types (adds handlers, topic-map entries and serializers for EV-004, EV-005).

| Step | State | What happens to a `call.ended` entry |
|---|---|---|
| Before any change | Record generation 1; all members build N | The group is not bound to that route (7E registry); no entry is delivered to it |
| CUT-2: N+1 rolled out, mixed N / N+1 | Record still generation 1 | Nothing changes. The new handler does not execute: no interval is open for the type (HCG-06). Old and new members behave identically |
| All members N+1; registry change and cutover performed with the group closed | Record generation 2; interval opens at boundary B | Entries above B are owed and fanned out. Entries at or below B are `KNOWN_UNSUBSCRIBED` |
| A build-N worker starts after the cutover | — | Not admitted: `H_required` ⊄ `H_capable(N)`. It never reads, so it cannot acknowledge a `call.ended` entry as unsubscribed |

**Example 2 — additive public field (serializer change, no contract change).**
Build N renders `call.failed` with three fields; build N+1 adds a fourth. Both builds are capable of the same types; the record does not change; both are admitted and run together. An event processed by an N member gets a three-field body, one processed by an N+1 member a four-field body. The claim guarantees each event is rendered once. Both bodies are valid V1 (VER-7H-05). No stop point is needed.

**Example 3 — a breaking public change.**
Not deployable in place. It requires a successor topic (catalog change in the owning sources), then a build whose topic map renders both strings (VER-7H-06). Until tenants subscribe to the successor, behaviour is unchanged.

**Example 4 — internal `event_version` 2 of an eligible type appears.**
The producer starts emitting V2 only after the 7C process says consumers are ready. A webhook-engine build without a (type, 2) topic-map entry is not capable of that pair. Its entries are held by 7F / 7G (`COMPATIBILITY_HOLD`), not acknowledged and not externalized with the wrong serializer. After a capable build is deployed they are processed normally.

**Example 5 — first activation of the dispatcher.**
No dispatcher build exists today. The fenced functions of §17.3 exist before the first dispatcher runs, so there is never a period in which fenced and unfenced workers share the table. If the claim contract is ever changed later, the same rule applies as for a handler-contract cutover: all dispatchers stop, the change is made, capable dispatchers start.

**Example 6 — redelivery after a key rotation.**
A delivery created under secret S1 dead-letters. The tenant rotates to S2 with a one-hour grace, and two hours later replays. The replay is signed with S2 only (SIG-05, SIG-06). The body is the original bytes; the event ID is unchanged; the delivery ID is new.

---

## 17. Database Persistence and Transaction Requirements

### 17.1 Matrix G — what the frozen schema can and cannot represent

Static reading of the SQL text. Nothing was executed.

| Required durable state | Frozen object | Verdict |
|---|---|---|
| Destination registration | `webhooks.webhook_endpoints` (`062_5I`) | PRESENT |
| Subscription state | `webhook_endpoints.topics`, `status`; GIN index `idx_we_org_topics` (partial, `ACTIVE`) | PRESENT |
| Subscription / endpoint versions | None; `updated_at` only | ABSENT; **not required** (OD-7H-01 = A; TRM-02) |
| Secret references and rotation | `signing_secret_ref`, `previous_signing_secret_ref`, `previous_secret_expires_at`; `fn_rotate_webhook_secret` (`101_5I1`) | PRESENT |
| Delivery intent | `webhooks.webhook_deliveries` (`063_5I`), immutable identity trigger | PRESENT |
| Event-to-subscription deduplication | None. No unique key on (`event_id`, `webhook_endpoint_id`); none possible on the partitioned table | **SCHEMA GAP** — MR-7H-01 (= 7F IO-7F-21) |
| Dispatch claim usable by the worker | `fn_claim_delivery` returns `SETOF UUID` only: no partition key, no organization. `app_worker` has no BYPASSRLS and the table has forced RLS, so the worker cannot read a claimed row without already knowing its organization. The function also has no organization-status guard | **SCHEMA GAP** — MR-7H-02 |
| Fenced outcome recording | `fn_delivery_succeeded` / `fn_delivery_failed` test `status = 'DELIVERING'` only. No claim sequence exists | **SCHEMA GAP** — MR-7H-02, MR-7H-03 |
| Serialization against organization status changes | `fn_claim_delivery` reads no organization state and takes no organization lock; the status functions lock the organization row `FOR UPDATE` (`107_5B5`) | **SCHEMA GAP** — MR-7H-02, MR-7H-03 |
| Stale-claim recovery | `claimed_at` exists; 5I §34 says "detectable via claimed_at column; worker timeout logic". No function releases a stale claim and no runtime role can find one across tenants | **SCHEMA GAP** — MR-7H-03 |
| Pre-send admission and uncounted release (organization hold) | None | **SCHEMA GAP** — MR-7H-03 |
| Effective-destination evidence | None | **SCHEMA GAP** — MR-7H-06, MR-7H-10 |
| Coherent endpoint configuration revision | None. `updated_at` is the mutating transaction's start time (`set_updated_at`, `001_5B`), not a commit order, and is also touched by non-configuration updates | **SCHEMA GAP** — MR-7H-11 |
| Serialization of an admission against endpoint mutations | None. No frozen function reads the endpoint under a lock on behalf of a delivery; `fn_rotate_webhook_secret` takes `FOR UPDATE` and nothing takes a conflicting share lock | **SCHEMA GAP** — MR-7H-03 (function behaviour; no new column) |
| Stored destination fingerprint per revision | None | **SCHEMA GAP** — MR-7H-11, MR-7H-10 |
| Replay lineage and lineage-wide quota | `replay_of_delivery_id` names the parent only; the function has no quota and no lineage | **SCHEMA GAP** — MR-7H-08 |
| Cancellation | `CANCELLED` is a legal status; no function reaches it; app roles have no UPDATE; platform-admin DML revoked (`109_5B7`) | **SCHEMA GAP** — MR-7H-05 |
| Claim, admission and attempt history | Only `attempt_count`, `claimed_by`, `claimed_at` and `last_*` columns on the delivery row; each claim overwrites the last | **SCHEMA GAP** — MR-7H-06 |
| Retry eligibility and scheduling | `next_attempt_at`, `idx_wd_pending` | PRESENT |
| Terminal success / failure | `DELIVERED`, `DEAD_LETTER`, `completed_at` | PRESENT |
| Retention purge | Windows are documented; no purge function; **no runtime role holds DELETE** on deliveries after `109_5B7` | **SCHEMA GAP** — MR-7H-07 |
| Operator / tenant redelivery | `fn_replay_webhook_delivery`, `replay_of_delivery_id`, `replay_count`, `last_replayed_at` | PRESENT; endpoint / organization guard absent → MR-7H-08 |
| Replay lineage | `replay_of_delivery_id`, `idx_wd_replay` | PRESENT |
| Inbound receipt and dedup | `webhooks.inbound_webhook_events`, `uq_iwe_org_provider_event`; `billing.payment_webhook_receipts` | PRESENT |
| Durable callback processing facts | Billing: PRESENT (`payment_webhook_receipts` normalized columns and `payload_hash`, `102_5H2`). Voice and generic integrations: **none**. `inbound_webhook_events` has `provider_slug`, `provider_event_id`, `event_type`, `signature_header`, `signature_valid`, `raw_payload_ref` (not populated by default), `status`, times and `failure_reason` | **SCHEMA GAP** — MR-7H-09 |
| Inbound stale-receipt recovery | No cross-tenant discovery function for `inbound_webhook_events`; status function is not a claim; no processing-attempt count | **SCHEMA GAP** — MR-7H-09 |
| Plugin installation and execution evidence | `plugins.plugin_installations`, `plugins.plugin_executions` (`065_5I`, `101_5I1`) | PRESENT |
| Audit evidence | `audit.fn_insert_audit_event()`; open-text `action_kind` | PRESENT; one new token (ERR-7H-04) |
| Auto-suspension of endpoints | `SUSPENDED` value only | ABSENT; **not required** (DEP-6J-07 FUTURE) |
| Test-delivery marker | `event_type = 'platform.test'`; `is_test` is derived in the API response | PRESENT (derived) |
| Correlation of a delivery to the originating trace | No correlation column on deliveries | ABSENT; carried by MR-7H-06 (optional column) and by `event_id` join to the outbox |

### 17.2 Transaction boundaries

| # | Transaction | Role | Contains | Never contains |
|---:|---|---|---|---|
| TX-1 | Fan-out (T-01) | `app_worker`, tenant context | Claim, projection reads, delivery inserts | Redis, HTTP, secret manager |
| TX-2 | Dispatch claim (T-04) | Dispatcher role via guarded function | Organization share locks; row state change; claim record | Anything else |
| TX-3 | Load | Dispatcher role, tenant context | Read of the immutable delivery body | Writes; any I/O; any endpoint attribute |
| TX-3a | Admission (T-04a / T-09), at most twice per claim | Dispatcher role via guarded function, `READ COMMITTED` | Organization share lock; delivery row lock and fence check; **one locking read of the endpoint row, `FOR SHARE`** (revision, URL, timeout, both secret references, expiry, fingerprint), held to commit (ELK-01); previous-signature planning; insertion of the admission record (for the second admission, first the abandonment record AB of the first), or the uncounted release with its closure | Secret-manager calls, DNS, HTTP; any write to the endpoint row. It commits, releasing every lock, before secret resolution |
| — | Secret resolution by the admitted revision's references | none | **No transaction is open** | — |
| TX-3b | Last-instant re-check (HTP-17); may repeat within one admission | Dispatcher role via guarded read | Plain committed read of the endpoint's current `config_revision` and the database time; no row lock | Writes; locks; any I/O |
| — | Signing, HTTPS | none | **No transaction and no lock is held** | — |
| TX-4 | Closure (T-05 … T-07) | Dispatcher role via guarded function | Fenced state change + closure record | HTTP; the endpoint `last_delivery_at` touch (ELK-05 a) |
| TX-5 | Sweeps (T-08, T-10, T-11) | Sweep role via guarded functions | State changes + closure / audit records | HTTP |
| TX-6 | Replay (T-03), test (T-02) | `app_api`, tenant context | Organization share lock; lineage anchor lock; parent lock; endpoint share lock (ELK-03); guarded insert; sync audit (replay) | HTTP |
| TX-7 | Callback receipt | Route role (`app_api`, or `app_billing_webhook_ingress`) | Dedup insert **and the processing input** | Provider calls, domain processing |
| TX-8 | Callback processing | Owning context's worker role | Processing claim; then owner state + outbox row + terminal receipt status + deletion of the processing input | Provider calls |

**PER-01 [FROZEN].** No transaction spans external I/O, and no two-phase commit exists (7A PR-06).
**PER-02 [7H].** No runtime role gains superuser, BYPASSRLS or raw UPDATE / DELETE on deliveries for any of this. Cross-tenant work is done only by narrow guarded functions, following the frozen pattern of `fn_claim_delivery`. Final roles and grants are 7I's (HE-7I-7H-01). Migration privileges stay separate from runtime privileges.

### 17.3 SCHEMA GAP — CONTROLLED FUTURE MIGRATION REQUIRED

Each item is a **logical requirement**. Names, DDL, function signatures, physical record shapes and the migration number are chosen by the governed, Integrations-owned Phase-5 migration, which requires owner approval when it is authored. 7H writes no SQL and creates no migration 113. Migrations `001` – `112` are not modified; frozen functions are left in place and superseded, never edited. **None of the items below exists.**

| ID | Missing capability | Governing contract | Logical delta | Uniqueness / idempotency | RLS and roles | Forward compatibility; rollback | Blocks activation? |
|---|---|---|---|---|---|---|---|
| MR-7H-01 | Fan-out claim | 7F §28.11, IO-7F-21; 7G §41.1 | A non-partitioned claim record keyed by the consumer obligation and `event_id`, carrying `organization_id`, the matched-endpoint count and the claim time; retention ≥ CON-10's evidence horizon ([REC] 90 days) | Primary key = the claim identity; insert-if-absent | Forced RLS on `organization_id`; INSERT / SELECT for `app_worker` in tenant context | New table. Rollback: drop, only while the consumer is not activated | **Yes** (already frozen as a blocker) |
| MR-7H-02 | Usable, guarded dispatch claim with a claim sequence | 6J §22; OD-7H-02, OD-7H-09; DSM-01 | (a) A per-delivery `claim_seq`, starting at 0, increased by exactly one by each claim under the delivery's row lock. (b) A claim function that selects due `PENDING` rows whose organization row it has share-locked and found `ACTIVE` (the status condition is part of the locking query so that it is re-evaluated after any lock wait; isolation `READ COMMITTED` or stricter), sets `DELIVERING`, `claimed_by`, `claimed_at`, increments `claim_seq`, writes the claim record C(d, k), and returns (delivery ID, `created_at`, `organization_id`, `claim_seq`, `claimed_by`). It must permit a fair selection across organizations (COM-04) | Delivery rows `FOR UPDATE SKIP LOCKED`; organization rows `FOR SHARE SKIP LOCKED` (ADM-03) | Guarded function; EXECUTE for the dispatcher role only; returns identifiers, never a body, URL or secret reference | New column and function; frozen `fn_claim_delivery` stays but is not used by the dispatcher. Rollback: drop both while no dispatcher runs | **Yes** |
| MR-7H-03 | Admission, fenced closure and stale-claim release | 6J §22.3; OD-7H-02, OD-7H-05, OD-7H-09, OD-7H-12, OD-7H-13, OD-7H-15, OD-7H-16, OD-7H-17, OD-7H-18 | (a) **Admission function** (T-04a / T-09): share-locks the organization row; checks the fence; if the organization is not `ACTIVE`, returns the row to `PENDING` with `attempt_count` unchanged and writes the closure `RELEASED_ORG_NOT_ACTIVE`; otherwise reads **one** endpoint row version with a single `FOR SHARE` locking statement, at `READ COMMITTED`, held to commit (`config_revision`, URL, timeout, both signing references, previous-secret expiry, stored fingerprint and key ID; ELK-01), reports `ENDPOINT_GONE` if no row exists, computes whether a previous-secret signature is planned (`e > db_now()`, SIG-06 b), inserts the admission record with its `admission_seq`, and returns that coherent generation including the expiry. Called for a second admission of the same claim, it first inserts the abandonment record AB(d, k, 1) (HTP-18), never modifying A(d, k, 1), and refuses a third. It acquires row locks only in the order organization → delivery → endpoint and writes nothing to the endpoint row (ELK-04). (a2) A guarded **re-check read** of the current `config_revision` and database time (MR-7H-11 c). (b) **Closure functions** (T-05 … T-07) that act only through the fence, increment `attempt_count`, assign `attempt_number`, write the closure record (including, for `SECRET_UNAVAILABLE`, the secret role), do not touch the endpoint row (ELK-05 a) and report whether they changed a row. (c) **Release function** (T-08) for rows whose `claimed_at` is older than a lease parameter, with the effects of a failed attempt and a closure whose send state follows DSM-07 H6 | Fence = `claim_seq`. At most two admissions and exactly one closure per claim (DSM-07 H3, H4). Release uses `SKIP LOCKED` | Guarded functions; dispatcher and sweep roles. The unfenced frozen functions are no longer executable by the dispatcher role. The uncounted release is reachable only through the admission function and only when the database itself finds the organization not `ACTIVE`, so it cannot be used as a free retry | New functions. Rollback: drop while no dispatcher runs | **Yes** |
| MR-7H-04 | *(merged into MR-7H-03 (a): the uncounted release is part of the admission function)* | — | — | — | — | — | — |
| MR-7H-05 | System cancellation | 5I §13 (`PENDING → CANCELLED`); OD-7H-02 | Functions that move `PENDING` rows to `CANCELLED` with a reason code, in bounded batches, with the organization row share-locked: (a) organization `CANCELLED`; (b) organization not `ACTIVE` and row older than the hold limit. Each writes its audit row in the same transaction | Acts on `PENDING` only; repeatable | Guarded; sweep role | New functions. Rollback: drop; already-cancelled rows stay cancelled | **Yes** |
| MR-7H-06 | Claim, admission and closure history | Owner constraint (auditable suspension, cancellation, failed-delivery and replay history); DSM-07; §14.5.1; OD-7H-15 | Append-only records per claim: **C** (delivery ID and partition key, `organization_id`, `claim_seq`, `claimed_by`, `claimed_at`, `attempt_count` at claim); **A**, one per admission (`admission_seq` 1 or 2, `admitted_at`, `config_revision`, destination fingerprint and key ID copied from the endpoint row, destination host and port, whether a previous-secret signature is planned); **AB**, the abandonment event of admission 1, a separate inserted record (`abandoned_at`, `CONFIG_CHANGED`, `NOT_SENT`, the revision found), never a column updated on A; **X** (`closed_at`, closer, disposition, send state, category code, failure origin, for `SECRET_UNAVAILABLE` the secret role (CURRENT or PREVIOUS), response status, duration, address connected to, whether a previous-secret signature was emitted, `attempt_number` or NULL); optionally the internal `correlation_id`. Written only inside the functions of MR-7H-02 and MR-7H-03, in the same transaction as the state change they describe | Unique (`delivery_id`, `claim_seq`) for C and for X; unique (`delivery_id`, `claim_seq`, `admission_seq`) for A, with `admission_seq` ≤ 2; unique (`delivery_id`, `claim_seq`) for AB, which requires A(d, k, 1) and is required by A(d, k, 2); unique (`delivery_id`, `attempt_number`) where not NULL; invariants DSM-07 H1 – H7 | Forced RLS; no INSERT for any runtime role outside the guarded functions; no UPDATE or DELETE by any runtime role, and no guarded function updates or deletes a history record (the retention purge of MR-7H-07 is the only remover); tenant exposure only if 7I approves | New records, partitioned with deliveries. Rollback: drop | **Yes** |
| MR-7H-07 | Retention purge | 6J §22.6, §41; 5I §23; OD-7H-10 | A guarded purge for `DELIVERED` older than 30 days and `DEAD_LETTER` older than 90 days, with their history records; `CANCELLED` and held rows are not purged until 7I sets a rule; fan-out claims and lineage anchors purged after their horizons. The purge is by each row's own status and `created_at`; a descendant never delays the purge of its root or of any other row | Repeatable | Guarded; maintenance role, not the dispatcher | New function. Rollback: drop | No for first activation; **yes** before the first retention deadline (30 days after go-live) |
| MR-7H-08 | Replay and test guards; replay lineage | OD-7H-03, OD-7H-06, OD-7H-10; 6J §23.3 | (a) **Lineage fields** on every replay row: the lineage root's delivery ID and creation time, copied from the parent (or the parent itself when it is a root). (b) A **lineage anchor**: one non-partitioned record per (organization, lineage root), created by the first replay, holding the root's creation time and its terminal status at that moment; it survives the root's purge. (c) The replay function, in this order: share-lock the organization and require `ACTIVE`; lock the lineage anchor (creating it if absent); lock the parent; apply the frozen guards (status, open replay); require the endpoint row to exist and be `ACTIVE`, with the row share-locked (ELK-03; an absent row is refused, OD-7H-18); require the **lineage window** (§13.5); require fewer than 10 replays of this **parent** and fewer than 10 replays in this **lineage** created in the last 24 hours, both counted under the locks just taken; insert. (d) The test path performs its organization and endpoint checks under the same locks | The anchor lock serializes every replay of one lineage, whichever descendant is the parent, so both quotas are exact under concurrency. Same idempotency as today for a repeated request | Same grants (`app_api`, tenant-forgery guard retained) | Supersedes the frozen function body through a new migration; signature unchanged so the route does not change. No existing row needs backfill (no delivery exists). Rollback: restore the previous body | **Yes** |
| MR-7H-09 | Durable callback processing input and receipt recovery | OD-7H-08; 7D PCI-13, PCI-25, REC-04; 6J §24 | For `webhooks.inbound_webhook_events` (routes 6D-021 and 6J-014; Billing needs nothing): (a) a **processing-input** record per receipt, written in the receipt's transaction, with a schema version, a hash of the verified raw bytes, field-level encryption, and no raw payload (CBK-15 … CBK-20); (b) a guarded **processing claim** `RECEIVED → PROCESSING` that reports whether the caller won, records when processing started and counts processing attempts; (c) terminal transitions that delete the processing input in the same transaction (CBK-18); (d) a guarded cross-tenant **stale-receipt discovery** returning identifiers only (receipt ID, `organization_id`) for rows stale in `RECEIVED` or `PROCESSING`; (e) deletion of processing inputs by the organization erasure path | Receipt uniqueness unchanged (`uq_iwe_org_provider_event`); one processing input per receipt, write-once; effects stay idempotent through domain guards (CBK-09) | Forced RLS on `organization_id`. INSERT by the ingress role in tenant context; SELECT by the owning processing worker in tenant context; no tenant or platform-admin read path; identifiers only from the cross-tenant function | New record and functions; the frozen status function stays. Rollback: drop only while no callback route is live | **Yes**: routes 6D-021 and 6J-014 must not acknowledge callbacks in production without it |
| MR-7H-10 | Destination-evidence key | §14.5.1 | Not a database object: a platform-held secret used by the endpoint-mutating service to compute destination fingerprints, with a key ID stored beside every fingerprint | — | Held in the secret manager; never in a row; not available to the dispatcher or to a tenant-facing read path | Rotation adds a key ID for later revisions; old keys are kept for verification while records reference them | **Yes** (with MR-7H-11) |
| MR-7H-11 | Endpoint configuration revision and stored destination fingerprint | OD-7H-12; DST-04 … DST-06; HTP-15, HTP-17 | On `webhooks.webhook_endpoints`: (a) a `config_revision`, 1 at creation, increased by exactly one, by the database, in any transaction that changes `target_url`, `timeout_ms`, `signing_secret_ref`, `previous_signing_secret_ref` or `previous_secret_expires_at`, including changes made through the frozen `fn_rotate_webhook_secret`; unchanged by updates of other columns such as `last_delivery_at`, `topics` or `status`; (b) the destination fingerprint and its key ID, required at creation and required to be supplied by any statement that changes `target_url`, otherwise preserved; (c) a guarded read returning the current `config_revision` and the database time, for the re-check; (d) every path that changes a configuration column does so by a row update in the same transaction as the increment (true of any `UPDATE` and of `fn_rotate_webhook_secret`), because the conflict between that row lock and the admission's share lock is what makes C1 hold (ELK-02) | The increment is under the endpoint's row lock, so the revisions of one endpoint are unique and totally ordered by commit | Same RLS and grants as the endpoint row; the fingerprint is non-secret; the revision is internal and not part of the public resource or its `ETag` | New columns and trigger; no delivery or dispatcher exists yet, so nothing is backfilled for evidence. Rollback: drop while no dispatcher runs | **Yes** |

Partition maintenance for `webhook_deliveries` (monthly partitions were created for four months from the migration date, plus a DEFAULT partition) is an operations obligation of 5I; rows landing in the DEFAULT partition are still correct. It is handed to 7K (HE-7K-7H-05). Any new partition must receive the same DML revocation (`109_5B7` runbook note).

### 17.4 Retention (no new duration is invented)

| Data | Retention | Source |
|---|---|---|
| `DELIVERED` deliveries | 30 days | [FROZEN] 5I §23; 6J §22.6 |
| `DEAD_LETTER` deliveries | 90 days | [FROZEN] 5I §14; 6J §22.6; CNF-7H-05 |
| `CANCELLED` deliveries | NOT SPECIFIED → retained until 7I decides | HE-7I-7H-05 |
| Held `PENDING` deliveries | Until reactivation, or cancelled at 90 days | [OD] OD-7H-02 |
| Claim, admission and closure records | Follow their delivery | [7H] |
| Replay descendants | Each by its own status and creation time under the frozen 30 / 90-day rule; never chained to another row. Resulting lifetime of a body copy: up to 120 days (`DELIVERED` root) or 180 days (`DEAD_LETTER` root) from the root's creation. This is a stated consequence, **not an owner-approved retention period**; the final rule is 7I's (LIN-04; OD-7H-14) | [FROZEN] per-row rule; [LATER] 7I |
| Lineage anchors | Until the lineage window has closed and its last possible descendant has been purged | [7H] |
| Fan-out claims | Set by the governed migration; [REC] 90 days | 7F IO-7F-21; XRP-04 |
| Inbound receipts | No dedicated TTL (general observability retention) | [FROZEN] 6J §41 |
| Callback processing inputs | Deleted with the transition to `PROCESSED` / `SKIPPED`; after `FAILED`, until the period 7I sets; never by age while the receipt is not terminal; deleted by erasure | [OD] OD-7H-08; HE-7I-7H-07 |
| Plugin executions | No dedicated TTL | [FROZEN] 6J §41 |

Each retention is independent of Redis retention, outbox cleanup and the 7G ledger (7A §32.3).

### 17.5 Activation blockers

| ID | Function | Blocking class | Blocked by |
|---|---|---|---|
| AB-7H-01 | Webhook fan-out (CMP-01) | GOVERNED MIGRATION REQUIRED | MR-7H-01; 7F IO-7F-20, IO-7F-21; the 7F common prerequisites (7F §35.1) and the 7G recovery ledger (7G §56.1) |
| AB-7H-02 | Delivery dispatch (CMP-03, CMP-04), and the replay and test routes | GOVERNED MIGRATION REQUIRED + IMPLEMENTATION PREREQUISITE + UPSTREAM CONTROLLED RECONCILIATION REQUIRED | MR-7H-02, MR-7H-03, MR-7H-05, MR-7H-06, MR-7H-08, MR-7H-10, MR-7H-11; the egress adapter; endpoint mutations auditing in their own transaction (7D AUD-7D-01; IO-7D-16); ERR-7H-01, ERR-7H-02, ERR-7H-06, ERR-7H-07, ERR-7H-09, ERR-7H-10 (the last two as revised by the third remediation) consolidated; the endpoint lock protocol of §14.2.2 and the grace-boundary and required-secret behaviour of SIG-06 and SIG-18 proven by IO-7H-20 and IO-7H-21; the purge discipline of SEC-7H-04; 7I final grants |
| AB-7H-08 | The public replay route in production | DEFERRED 7I DECISION REQUIRED | 7I's recorded decision on the retention, erasure and lineage-anchored purge of replay copies (OD-7H-14; HE-7I-7H-08). Until it exists the route stays disabled even if every migration requirement is met |
| AB-7H-03 | `call.started` / `call.completed` delivery | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | Governed 7B / 7E registry change binding R-004 and R-005 to the group; 7F addition cutover |
| AB-7H-04 | Provider-callback routes 6D-021 and 6J-014 (ingress **and** processing) | GOVERNED MIGRATION REQUIRED + UPSTREAM CONTROLLED RECONCILIATION REQUIRED | MR-7H-09; ERR-7H-05 consolidated into 6J §24; 7I encryption and retention rules for the processing input (HE-7I-7H-07). Until then a callback acknowledged with 2xx can be lost, so these routes must not serve production traffic. Route 6K-023 is not blocked by 7H |
| AB-7H-05 | Retention purge | GOVERNED MIGRATION REQUIRED | MR-7H-07 |
| AB-7H-06 | Plugin callouts | IMPLEMENTATION PREREQUISITE | Egress adapter; 6I execution block ADR-6I-04 as recorded in 6J DEP-6J-12; the fail-closed limiter behaviour of PLG-15 … PLG-18; ERR-7H-08 consolidated |
| AB-7H-07 | Any successor topic `X.vN` | UPSTREAM CONTROLLED RECONCILIATION REQUIRED | The governed AX-E change must first settle VER-7H-06a |

Without AB-7H-01 and AB-7H-02 cleared, no webhook is sent. A partial activation (fan-out without dispatch, or dispatch on the unfenced frozen functions) is prohibited: the first accumulates rows nothing can move, and the second cannot read its own claims and has an unrecoverable `DELIVERING` state.

### 17.6 Implementation obligations

| ID | Obligation |
|---|---|
| IO-7H-01 | Topic map and per-topic serializers exactly as §5.2, §5.3; a test asserts each `data.object` key set equals the table and that no excluded field can appear. |
| IO-7H-02 | Projection read ports in Voice, CRM and Billing returning only the allow-listed columns. |
| IO-7H-03 | Single-buffer signing and sending (HTP-05); a test proves the bytes passed to the HMAC and to the socket are the same object, and reproduces the 6J §64 dual-signature fixture. |
| IO-7H-04 | Two separate canonical-input builders (SIG-03); a test proves neither accepts the other's inputs. |
| IO-7H-05 | Egress adapter with the full 6J §60.6 adversarial matrix plus the mixed-answer and userinfo cases of §14.4. |
| IO-7H-06 | Dispatcher with fence, lease inequality, dependency gate and per-organization / per-endpoint caps. |
| IO-7H-07 | Sweeps (stale claim, cancelled organization, hold expiry, inbound receipts). |
| IO-7H-08 | Failure-injection tests for the 30 traces of §18. |
| IO-7H-09 | Closed category-code list (HTP-14) enforced at the recording boundary. |
| IO-7H-10 | Callback ingress conformance for all three routes (CBK-01 … CBK-05), including "no row on failed verification". |
| IO-7H-11 | Per-adapter processing-input schemas (closed, versioned, size-bounded) and command builders that take only a stored input and current platform state (CBK-15, CBK-10); a test kills the process after the 2xx and proves the command is rebuilt (§26.1 scenario). |
| IO-7H-12 | Organization-lock protocol tests: the two interleavings of §26.2 driven with controlled transaction ordering, proving G1, G2 and the 6 s bound. |
| IO-7H-13 | Claim / admission / closure history with invariants DSM-07 H1 – H7 checked by a property test over random interleavings of claim, admission, closure, sweep and suspension. |
| IO-7H-14 | Destination fingerprint: canonicalization vectors (path and query variants, default port, host case, IDN) and the "same host, different path" case of §26.5. |
| IO-7H-15 | Replay lineage: concurrent replays of sibling descendants cannot exceed 10 per lineage; a replay after the lineage window is refused; a recursive chain is bounded (§26.3 scenario). |
| IO-7H-16 | Plugin limiter outage: refusal without a callout, breaker opening, bounded re-asks, durable `plugin_executions` evidence (§26.6 scenario). |
| IO-7H-17 | Authoritative, concurrency-safe enforcement of the endpoint-count limit at endpoint creation and enabling (two concurrent creations at the limit must not both succeed). Until it exists, the automatic bound is 10 × N with N unbounded by the database (§20.2). |
| IO-7H-18 | Configuration-coherence tests: cases A – I of §10.1.1 and traces 27 – 30, driven with controlled ordering of rotation, `PATCH`, admission, re-check and hand-off; assertions that no request combines values of two revisions, that no previous-secret signature is produced after its expiry, and that a claim never has a third admission. |
| IO-7H-19 | Endpoint mutations write their audit row in the mutating transaction with the revision and fingerprint (DST-05); a `PATCH` of `target_url` without a fingerprint is refused; the injections of trace 25. |
| IO-7H-20 | Endpoint lock protocol (§14.2.2), driven with controlled transaction ordering on separate connections: (i) the admission stops after its `FOR SHARE`; a rotation, a `PATCH` and a hard delete must each block until it commits, and the admission record must name the pre-change revision; (ii) the rotation stops after its `FOR UPDATE`; the admission must block, and after the rotation commits must record the new revision (after a rollback, the old one; after a delete, `ENDPOINT_GONE`); (iii) concurrent admissions of two deliveries to one endpoint do not block each other; (iv) a probe running admission, replay, rotation, `PATCH`, disable, suspension, the claim and the sweeps concurrently reports no deadlock; (v) a closure never waits on an endpoint row; (vi) a stalled mutator produces a lock timeout, no admission record and `ADMISSION_EXPIRED`. |
| IO-7H-21 | Grace boundary and required secret (SIG-06, SIG-07, SIG-17, SIG-18), with an injectable database clock and secret manager: graces of 1 s, 3 s, 6 s and 3600 s each dual-sign every request handed off before expiry and none after; a re-check returning less remaining time than the hand-off needs produces a repeated re-check and never a current-only request before expiry; a previous secret unavailable inside the grace produces no request and one `SECRET_UNAVAILABLE` attempt with role PREVIOUS; the same fault after expiry produces a current-only request; both signatures of a dual-signed request verify over identical bytes and timestamp (the 6J §64 fixture). |
| IO-7H-22 | Append-only history: after trace 28 the store holds C, A(·, 1), AB(·, 1), A(·, 2) and X, each still in its first row version; an UPDATE or DELETE of a history record by any runtime role or guarded function is refused. |

---

## 18. Failure-Mode Traces and Recovery

These are **documented architecture scenario traces**, written as failure injections against the design. None was executed: no runtime exists. Each must become an executed test under IO-7H-08. Traces that depend on a §17.3 requirement say so; before that requirement exists the trace describes designed behaviour only.

Notation: `E` = one internal event with `event_id` e; `D` = one delivery row with `id` d for endpoint `P`; `W1`, `W2` = dispatcher workers; ✂ = injected fault. "Intervene" lists who **may** act; in every trace the system converges without anyone acting unless stated.

### Trace 1 — domain transaction rolls back before the event is persisted
1. Producer transaction updates state and inserts the outbox row. ✂ Rollback (constraint failure, crash or audit failure).
- **Durable:** nothing. **Retried:** only the caller's own request, under its `Idempotency-Key`. **Stable identity:** none was created. **Duplicate HTTP:** no; no delivery can exist.
- **Intervene:** the caller. **Audit:** none (a synchronous audit row rolls back with it). **Signal:** the API error response.
- **Convergence:** state and event are both absent (7A DUR-01). No externalization of an uncommitted fact is possible, because fan-out reads only stream entries, which originate only from committed rows.

### Trace 2 — outbox publication succeeds, publisher acknowledgement fails
1. Relay claims row e and publishes; Redis accepts. ✂ Relay crashes before mark-published.
2. Lease expires; another relay republishes e (7D §26). Two stream entries carry e.
3. CMP-01 processes the first: claim inserted, rows created, commit, `XACK`.
4. CMP-01 processes the second: claim conflict → `ALREADY_COMMITTED` → `XACK`. No rows.
- **Durable:** outbox row; one claim; one row per endpoint. **Retried:** publication only. **Stable identity:** e. **Duplicate HTTP:** no.
- **Intervene:** nobody. **Signal:** relay republish count; fan-out duplicate count. **Depends on:** MR-7H-01.

### Trace 3 — the consumer receives the same event twice, concurrently
1. Two members of the group hold entries for e (republish, or a reclaim racing the original owner).
2. Both begin TX-1. Both attempt the claim insert. The primary key admits one; the other blocks, then sees the conflict after the first commits.
3. Winner inserts rows and commits. Loser commits nothing new and acknowledges on the visible claim.
- **Durable:** one claim, one row set. **Duplicate HTTP:** no. **Signal:** claim-conflict count. **Depends on:** MR-7H-01. Without it, this trace produces two full row sets (7F §28.11), which is why activation is blocked.

### Trace 4 — consumer crashes before persisting the delivery intent
1. CMP-01 begins TX-1, inserts the claim and some rows. ✂ Process dies before commit.
2. PostgreSQL rolls TX-1 back: no claim, no rows. No `XACK` was sent; the entry stays pending.
3. 7G reclaim redelivers it; TX-1 runs in full and commits; `XACK`.
- **Durable after step 2:** the outbox row and the pending entry. **Retried:** the fan-out transaction. **Stable identity:** e; delivery IDs are created for the first time in step 3. **Duplicate HTTP:** no.
- **Intervene:** nobody; after five genuine failures 7G parks the entry and an operator with `recovery.*` capabilities acts under 7G. **Signal:** pending age; reclaim count.
- **Convergence:** the claim and rows are atomic, so a partial fan-out is unobservable.

### Trace 5 — consumer crashes after persisting the intent, before `XACK`
1. TX-1 commits (claim + rows). ✂ Process dies before `XACK`.
2. The dispatcher may already be delivering the rows: they are committed.
3. The entry is reclaimed. TX-1: claim conflict, claim visible → `ALREADY_COMMITTED` → `XACK`.
- **Durable:** claim, rows. **Retried:** only the acknowledgement. **Duplicate HTTP:** no. **Signal:** `ALREADY_COMMITTED` outcomes.
- **Convergence:** INV-ACK holds in both orders: an event is never acknowledged without its intents, and intents never wait on the acknowledgement.

### Trace 6 — delivery worker crashes before sending HTTP
1. W1 claims D: `DELIVERING`, `claim_seq` 1, C(d, 1). ✂ W1 dies during load, before admission. No A(d, 1) exists, so nothing was sent.
2. D stays `DELIVERING`. After `T_claim_lease`, the sweep releases it: `attempt_count + 1`, category `CLAIM_EXPIRED`, `PENDING` with the next step's wait (or `DEAD_LETTER` at the ceiling).
3. W2 claims D when due and delivers.
- **Durable:** D; C(d, 1); then X(d, 1) `CLAIM_EXPIRED`, `NOT_SENT`, `attempt_number` 1. **Retried:** the attempt. **Stable identity:** e, d. **Duplicate HTTP:** no. The absence of an admission record proves nothing was sent; the release still spends one attempt, because OD-7H-05 keeps one budget for every released stale claim.
- **Intervene:** nobody. **Signal:** stale-claim releases; age of oldest `DELIVERING`. **Depends on:** MR-7H-02, MR-7H-03.

### Trace 7 — worker sends HTTP and crashes before recording the response
1. W1 claims D (`claim_seq` 1), is admitted (A(d, 1), fingerprint F), sends the request; the receiver processes it and returns 200. ✂ W1 dies before the closure transaction.
2. Sweep releases D after the lease (counted). W2 claims and sends again with a new timestamp and signature, the same body, the same event ID and the same delivery ID.
3. Receiver recognises the event ID and does not re-apply its effect; returns 200. W2 records `DELIVERED`.
- **Durable:** D; X(d, 1) `CLAIM_EXPIRED`, `UNCERTAIN`, `attempt_number` 1 (toward F); X(d, 2) `DELIVERED`, `attempt_number` 2. **Duplicate HTTP:** **yes, one**. **Stable identity:** e and d are identical in both requests.
- **Intervene:** nobody. **Signal:** stale-claim release followed by success.
- **Convergence:** at-least-once; the receiver's event-ID dedup makes the duplicate harmless (6J §21.2 rule 4). The platform makes no stronger promise.

### Trace 8 — customer receives the webhook but the response is lost
1. W1 sends; the receiver commits its effect; ✂ the response is dropped in transit; W1's deadline passes.
2. W1 records a failed attempt `TIMEOUT` (fenced, TX-4). D → `PENDING`, next step.
3. The next attempt is delivered and answered. `DELIVERED`.
- **Durable:** D; claim, admission and closure records. **Duplicate HTTP:** **yes**. **Stable identity:** e, d.
- **Signal:** `TIMEOUT` category followed by success for the same delivery. **Convergence:** as trace 7. This case is indistinguishable, from the platform's side, from a receiver that never got the request.

### Trace 9 — two delivery workers race for the same delivery
Case A, simultaneous claim: both call the claim; `SKIP LOCKED` gives D to exactly one. The other receives other rows or none.
Case B, slow worker versus release:
1. W1 claims D: `claim_seq` 1, C(d, 1). It is admitted, A(d, 1) with fingerprint F, and then stalls (GC pause, partition) beyond the lease.
2. The sweep closes claim 1: X(d, 1) `CLAIM_EXPIRED`, `UNCERTAIN`, `attempt_number` 1. W2 claims D: `claim_seq` 2, C(d, 2); is admitted, A(d, 2); sends.
3. W1 resumes. Its admission timer (6 s) and its own deadline `T_attempt_max` < `T_claim_lease` have long passed, so it does not send and does not record (HTP-16, DSM-02). If, through a host freeze placed exactly between its timer check and the connect call, it does send and then reports, its report carries `claim_seq` 1; the row's current `claim_seq` is 2; nothing changes (DSM-01).
4. W2 records X(d, 2) under `claim_seq` 2 with `attempt_number` 2.
- **Durable:** D with W2's outcome; C, A, X for both claims. **Duplicate HTTP:** possible only in the anomaly of step 3 (one extra request, to F). **Stable identity:** e, d.
- **Evidence:** claim 1 is recorded as `UNCERTAIN` toward F, which is exactly what is known.
- **Signal:** fence-mismatch count (should be near zero; a sustained rate means the lease inequality is violated).
- **Depends on:** MR-7H-02, MR-7H-03, MR-7H-06. With the unfenced frozen functions, W1's late failure report would clear W2's claim and W2's success would then silently change nothing, losing a recorded success (ADV-02).

### Trace 10 — Redis unavailable, PostgreSQL available
1. Producers commit; outbox rows accumulate `PENDING` (7A FM-01). No stream entry, so no new fan-out.
2. **Existing deliveries continue**: the dispatcher's work source is PostgreSQL (DSM-06). Retries, replays and test deliveries proceed. Plugin callouts cannot take a rate-limit token (the bucket is in Redis). By owner decision OD-7H-11 the executor refuses the callout rather than call unmetered (PLG-15 … PLG-18; trace 26), returning a normalized retryable failure to the invoking runtime.
3. Redis returns; the relay drains the outbox; fan-out resumes; consumers deduplicate.
- **Durable:** everything in PostgreSQL. **Retried:** publication. **Duplicate HTTP:** no. **Signal:** outbox backlog age; relay gate open; fan-out lag.
- **Convergence:** delivery of new events is delayed, never lost. `occurred_at` is unaffected.

### Trace 11 — PostgreSQL unavailable, Redis available
1. Producers cannot commit: no new events. CMP-01 cannot open TX-1: entries stay pending; 7G classifies this as `TRANSIENT_DEPENDENCY`, opens the dependency gate and spends no budget (7G FC-10).
2. Dispatcher cannot claim. A worker that was mid-attempt may complete the HTTP request but cannot record it.
3. PostgreSQL returns. The unrecorded attempts are released by the sweep after the lease (counted) and retried.
- **Durable:** pending entries in Redis; rows as last committed. **Duplicate HTTP:** **yes** for attempts that were in flight at the outage. **Signal:** dependency gate open; readiness failing (D0 `/health/ready`); stale `DELIVERING` count after recovery.
- **Convergence:** bounded by one extra attempt per in-flight delivery.

### Trace 12 — receiver temporarily unavailable
1. Attempts 1 – 3 fail (`CONNECT_REFUSED` or `HTTP_5XX`); waits 30 s, 60 s, 5 min.
2. Receiver recovers; attempt 4 succeeds → `DELIVERED`.
- **Durable:** D; four closure records with attempt numbers 1 – 4. **Duplicate HTTP:** only if a 5xx receiver had acted before failing. **Intervene:** nobody. **Signal:** attempts-per-delivery distribution.

### Trace 13 — receiver permanently rejects the request
1. Every attempt returns 400 (for example the receiver verifies with the wrong secret).
2. After `max_attempts` attempts the database forces `DEAD_LETTER` (default 7 attempts, about 10 h 37 min after creation).
3. The tenant sees it in `GET /webhook-deliveries` with `last_response_code`, the bounded preview and `failure_reason = HTTP_4XX`; fixes the receiver; calls replay. A new delivery d′ with the same e is created and succeeds.
- **Durable:** D in `DEAD_LETTER` for 90 days; d′. **Stable identity:** e across d and d′. **Duplicate HTTP:** no (every earlier request was rejected).
- **Intervene:** the tenant (`webhook:manage`). **Audit:** `WEBHOOK_DELIVERY_REPLAYED`. **Signal:** dead-letter count.
- **Convergence:** bounded work; no automatic resurrection; nothing is dropped silently.

### Trace 14 — receiver returns 429 repeatedly
1. Each attempt returns 429 with `Retry-After: 86400`.
2. Each wait is `min(step, max(jittered, 86400))` = the step. The receiver's header cannot stretch the schedule.
3. The delivery dead-letters on the normal schedule.
- **Durable:** D. **Duplicate HTTP:** no. **Signal:** `HTTP_429` share per destination host.
- **Convergence:** a receiver cannot pin a delivery slot indefinitely (6J §22.4) and cannot be hammered: at most `max_attempts` requests per delivery.

### Trace 15 — signing secret changes while a delivery is pending
1. D is `PENDING` in a 2-hour backoff. The tenant rotates S1 → S2 with a 1-hour grace: revision r → r+1 = (current S2, previous S1, expiry e).
2. Case A, the attempt is admitted inside the grace: the admission reads r+1 as one row version under the share lock; `e > admitted_at`, so the previous signature is planned and S1 is resolved. The re-check finds r+1 and `rem > 0`, and the request is handed off inside `rem`. It carries S2 in `X-Platform-Signature` and S1 in `X-Platform-Signature-Previous`. A receiver still on S1 accepts. This holds up to e itself, not up to 6 s before it (OD-7H-16).
3. Case B, the attempt is admitted after e, or its re-check finds `rem ≤ 0`: signed with S2 only. A receiver still on S1 rejects (4xx); the schedule continues; once the receiver deploys S2 a later attempt succeeds.
4. Case C, the secret manager cannot return S1 while `rem > 0`: nothing is sent; `SECRET_UNAVAILABLE`, `NOT_SENT`, role PREVIOUS (trace 30).
- **Durable:** D; the admission record names r+1 and whether a previous-secret signature was planned; the closure notes whether one was emitted. **Stable identity:** e, d; the body bytes are unchanged, only the key differs.
- **Intervene:** the tenant. **Audit:** `WEBHOOK_SECRET_ROTATED`, synchronous, carrying revision r+1. **Signal:** 4xx rise on one endpoint after a rotation.
- A rotation that commits while the attempt is between admission and send: trace 27. A rotation that races the admission itself: trace 29.

### Trace 16 — destination is deleted while a request is in flight
1. W1 was admitted for endpoint P and is sending. The tenant calls `DELETE` (→ `DISABLED`).
2. The in-flight request completes and is recorded normally (6J §18.8 "complete normally").
3. If it failed, later attempts still run: the delivery existed before the disable. No new delivery is created for P by later events; replay and test for P are refused.
4. Variant, platform hard delete of the row (an authorized platform operation, not the tenant's `DELETE`): a delete arriving while an admission holds the share lock waits for that admission to commit. Every later admission finds no row and its claim is closed `ENDPOINT_GONE`, `NOT_SENT`, origin PLATFORM, one attempt (OD-7H-18). The schedule runs to `DEAD_LETTER` by exhaustion. A replay of that dead letter is refused with `422` while the endpoint does not exist.
- **Durable:** D; the endpoint row (soft delete). **Duplicate HTTP:** no. **Audit:** `WEBHOOK_ENDPOINT_DISABLED`.

### Trace 17 — tenant is suspended during retry backoff
1. D1 is `PENDING`, due in 30 minutes. D2 was claimed by W1 one second ago (`claim_seq` 1, not yet admitted). D3 was claimed and **admitted** by W2 two seconds ago and W2 is about to send. A platform administrator suspends the organization; the suspension commits at `t_s`.
2. **D1.** At its due time the claim's locking query finds the organization row not `ACTIVE` and does not select D1. `attempt_count` and `claim_seq` are unchanged.
3. **D2.** W1 calls admission after `t_s`. The function share-locks the organization row, reads `SUSPENDED`, and executes T-09: D2 → `PENDING`, `attempt_count` unchanged, X(d2, 1) `RELEASED_ORG_NOT_ACTIVE`, no attempt number. Nothing is sent.
4. **D3.** W2's admission committed before `t_s`. Its timer shows 2 s, below 6 s, so it sends. The request starts no later than `t_s` + 6 s and ends within `timeout_ms`. Its closure is recorded normally with an attempt number. This is the residual window of ADM-05, and the records show it: A(d3, 1).`admitted_at` < `t_s` < X(d3, 1).`closed_at`.
5. Variant of step 4: W2 stalls 7 s after admission. Its timer check fails; it does not send; it closes the claim `ADMISSION_EXPIRED`, `NOT_SENT` (one attempt spent). D3 returns to `PENDING` and is then held.
6. Case A, reactivated after 10 days: D1, D2, D3 are immediately claimable (their `next_attempt_at` is in the past) and are delivered under the fairness caps. The receiver sees an `occurred_at` ten days old.
7. Case B, still suspended 90 days after a row's creation: the hold-expiry sweep sets `CANCELLED`, reason `HOLD_EXPIRED`, and writes the audit row.
8. Case C, the organization is cancelled: the sweep sets `CANCELLED`, reason `ORG_CANCELLED`.
- **Durable:** all rows throughout; claim, admission and closure records; audit rows for suspension and for cancellation. **Duplicate HTTP:** no.
- **Intervene:** the platform administrator (reactivate). **Signal:** held-delivery count and age per organization status; attempts closed after an organization status change.
- **Depends on:** MR-7H-02, MR-7H-03, MR-7H-05, MR-7H-06.

### Trace 18 — internal event replayed after an external delivery succeeded
1. E was fanned out; D reached `DELIVERED`.
2. An operator runs a 7G R4 disaster replay that republishes E to the transport (same e).
3. CMP-01 receives it. Origin provenance, if present, is consulted (7F HCG-28); the event is owed. TX-1: claim conflict → `ALREADY_COMMITTED` → `XACK`.
- **Durable:** the original claim and D. **Duplicate HTTP:** **no**. No new delivery row.
- **Intervene:** the 7G operator (`recovery.disaster-replay`). **Audit:** the 7G operation record. **Signal:** `ALREADY_COMMITTED` during a replay operation.
- **Boundary:** if E is older than the claim-retention horizon, 7G classifies it `RECONCILIATION_REQUIRED` and the handler does not run (XRP-04). An expired claim therefore cannot produce a second fan-out.

### Trace 19 — operator requests redelivery of a terminal failure
1. D is `DEAD_LETTER`. A tenant principal with `webhook:manage` posts the replay.
2. The function share-locks the organization (must be `ACTIVE`), locks the lineage anchor (D is a root, so the anchor is created now with D's creation time and terminal status), locks D, and checks: D's status and retention, the open-replay rule, the endpoint `ACTIVE`, the lineage window (90 days from D's creation, because D ended `DEAD_LETTER`), and both 24-hour quotas. It inserts d′ (`replay_of_delivery_id = d`, lineage root = d), bumps `replay_count`, and the audit row commits in the same transaction.
3. A double-click or network retry returns d′ again.
4. d′ is delivered with a fresh timestamp and signature, the same body and event ID, a new delivery ID.
- **Durable:** D unchanged except replay metadata; d′. **Stable identity:** e. **Duplicate HTTP:** the receiver sees e again by design.
- **Intervene:** the owning tenant only. A platform administrator cannot (§14.3). **Audit:** `WEBHOOK_DELIVERY_REPLAYED` with actor. **Signal:** replay count.
- **Variants:** endpoint disabled → `422 WEBHOOK_REPLAY_NOT_ALLOWED`; eleventh replay of this delivery, or of this lineage, in 24 h → `429`; lineage window closed → `422`; delivery purged → `404`. Replaying d′ itself: trace 24.

### Trace 20 — old and new consumers run concurrently during a contract rollout
This is §16.4 Example 1 as a trace.
1. Group at generation 1. Builds N (17 types) and N+1 (19 types) run together. A `call.failed` entry processed by either is fanned out identically; the claim makes the result independent of which member took it.
2. The group is closed, the registry change and the cutover to generation 2 are performed, the boundary B is recorded.
3. A straggler N worker tries to start: not admitted (`H_required` ⊄ `H_capable`).
4. A `call.ended` entry above B is fanned out by an N+1 member. One at or below B is `KNOWN_UNSUBSCRIBED`.
- **Durable:** the handler-contract record; claims. **Duplicate HTTP:** no. **Signal:** admission refusals by build.
- **Convergence:** no entry is acknowledged as unsubscribed by a build that merely lacks the handler (7F P1-7F-11's failure cannot recur here).

### Trace 21 — callback provider retries an already accepted inbound event
1. Provider posts event x. Ingress verifies, resolves the organization, extracts the processing input, commits the receipt and the input together (the insert returns a row), answers 2xx, hands a wake-up hint to processing.
2. ✂ The provider did not see the 2xx and posts x again, twice, nearly simultaneously.
3. Each request verifies and resolves. Each receipt insert hits the unique key and returns no row; no second processing input is written and the first is not replaced. Both answer the same 2xx.
4. Processing of the first receipt runs once; the owner's guards make a second run harmless if a stale-receipt sweep re-dispatches it.
- **Durable:** one receipt, one processing input; the owner's state change and outbox row. **Stable identity:** (`organization_id`, `provider_slug`, x) for the receipt; the resulting domain event has its own `event_id` with `causation_id` = the receipt ID.
- **Duplicate side effect:** no. **Intervene:** nobody. **Signal:** duplicate-receipt count per provider.
- **Injection variants:** bad signature → rejected, no row; unknown call or connection → rejected, no row; valid signature for organization A referencing organization B's resource → resolution fails, no row.

### Trace 22 — plugin callout times out after completing its side effect
1. A workflow node invokes capability c of installation I. The executor takes a rate-limit token, writes the execution row (`RUNNING`), signs with I's secret and calls the plugin.
2. The plugin performs its side effect. ✂ Its response does not arrive within `manifest.timeout_ms`.
3. The executor records `TIMED_OUT` and returns a normalized failure to the workflow runtime. **The platform does not retry** (PLG-07).
4. The workflow's `on_failure_edge` decides. If the workflow itself re-runs the node, the plugin is called again; whether the plugin deduplicates is the plugin's contract, because no frozen contract transmits an idempotency key (CNF-7H-10).
- **Durable:** the execution row with its outcome; 6I's node claim. **Duplicate side effect:** possible only if the workflow explicitly retries; never from an automatic platform retry.
- **Intervene:** the workflow author (design of the failure edge); the tenant (suspend or uninstall). **Signal:** plugin timeout count per plugin and capability.
- **Convergence:** the outcome is recorded as ambiguous (`TIMED_OUT`), not as failure-with-no-effect. The platform does not claim the side effect did not happen.

### Trace 23 — request process dies after the callback's 2xx, before any processing (P1-7H-R01)
1. Provider posts a verified `call ended` event for call c. Ingress commits the receipt r (`RECEIVED`) together with its processing input {kind: call ended, provider call reference, ended-at, duration} and answers 2xx.
2. ✂ The process is killed before the wake-up hint is sent. The broker never hears of r. The provider, having its 2xx, never sends the event again.
3. Later the stale-receipt sweep finds r still `RECEIVED`, obtains (r, organization) from the guarded discovery function, and dispatches processing.
4. The processor wins the processing claim (`RECEIVED → PROCESSING`), reads the processing input under the tenant context, and the Voice command builder turns it into the `CallEnded` command. The owner transaction applies the call-state compare-and-set, writes the `call.ended` outbox row, sets r `PROCESSED` and deletes the processing input, all together.
5. ✂ Variant: the processor dies after step 4's claim and before the owner transaction. r stays `PROCESSING`; the sweep re-dispatches it later; the input is still there; step 4 repeats. Variant: it dies after the owner transaction committed: r is `PROCESSED`, nothing is owed.
- **Durable at every point after step 1:** r and its input, until the same transaction that completes the work.
- **Retried:** processing only. The provider is never asked again. **Stable identity:** r; the resulting event has `causation_id` = r.
- **Duplicate side effect:** no (call-state CAS). **Intervene:** nobody; after the bounded processing attempts r ends `FAILED`, visibly.
- **Signal:** age of the oldest non-terminal receipt; stale-receipt re-dispatches.
- **On the frozen schema** step 4 is impossible: r holds no duration and no call reference, and the raw payload was not kept. **Depends on:** MR-7H-09.

### Trace 24 — a replay is replayed, concurrently (P1-7H-R03)
1. Root R (fan-out delivery) is `DELIVERED` on day 0. The tenant replays it ten times during day 1; all ten children reach `DELIVERED`. Lineage count in the last 24 h: 10.
2. Two requests arrive together, one to replay child C3 and one to replay child C7. Each child has used 0 of its own per-delivery quota.
3. Both transactions share-lock the organization, then both request the lineage anchor's row lock. One obtains it, counts 10 replays in the lineage in the last 24 h, and is refused: `429 WEBHOOK_REPLAY_RATE_LIMITED`. The other then obtains the lock, counts the same 10, and is refused too.
4. On day 2 the count has aged out. A replay of C3 is accepted (lineage count 1, parent count 1). On day 31 any replay in this lineage is refused with `422 WEBHOOK_REPLAY_NOT_ALLOWED`: the root was `DELIVERED` and its 30-day window has closed, whatever the age of the newest descendant.
- **Durable:** the rows created, each naming R as lineage root; the anchor; one synchronous audit row per accepted replay.
- **Bound:** at most 10 accepted replays per rolling 24 h and none after day 30; the last body copy is purged within its own retention.
- **On the frozen function** step 3 accepts both, step 4's day-31 request is accepted, and each generation multiplies by ten. **Depends on:** MR-7H-08.

### Trace 25 — the tenant edits the URL between two attempts, and the audit is examined (P1-7H-R05)
1. Endpoint P is created with `target_url` `https://hooks.example/in?token=A`: revision 1, fingerprint F_A. The creating transaction also writes the audit row (revision 1, F_A).
2. Attempt 1 of D is admitted: A(d, 1, 1) = (revision 1, F_A). It fails with 503.
3. The tenant patches P to `https://hooks.example/other?token=B`: same scheme, host and port. One transaction sets the URL, sets revision 2 and fingerprint F_B on the row, and writes the audit row (revision 2, previous revision 1, destination changed, new F_B, previous F_A, actor).
4. Attempt 2 is admitted: A(d, 2, 1) = (revision 2, F_B). It succeeds.
- **Attribution:** attempt 2's admission says revision 2. The audit row with (P, revision 2) names the actor who authorized that destination. No timestamp is compared.
- **Same host, different path and query:** F_A ≠ F_B, so the records show the two attempts went to different destinations; neither path nor token appears in any record.
- **Injected: the audit is delayed.** Suppose an implementation, against DST-05, wrote the audit of revision 2 only after step 4. Attempt 2 still carries revision 2 and is attributed as soon as the row exists. Its lateness changes nothing, because nothing is ordered by audit time.
- **Injected: duplicate or reordered audit.** Two audit rows for (P, 2) are the same change. Rows for revisions 3 and 2 arriving in that order are ordered by revision.
- **Injected: two rapid changes.** A → B (revision 2) → C (revision 3) within a second. Each has its own transaction, revision, fingerprint and audit row. An attempt admitted in between names revision 2 and F_B; one admitted after names 3 and F_C.
- **Injected: crash between mutation and audit.** Under DST-05 there is no such point: they are one transaction, so both exist or neither does. An implementation that enqueues the audit after commit and crashes, and then sees change 3, could not rebuild the audit of revision 2 (its fingerprint is no longer on the row). That implementation violates 7D AUD-7D-01 and 7A AUD-04a and is not activatable (DST-08).
- **Injected: evidence-key rotation** between steps 1 and 4. Revision 1 keeps F_A under key ID 1; revision 2 is fingerprinted under key ID 2. Each admission copies its revision's fingerprint and key ID, so admission and audit still match exactly.
- **Verification:** an authorized investigator given a candidate URL recomputes the fingerprint under the recorded key ID and compares.
- **Depends on:** MR-7H-06, MR-7H-10, MR-7H-11; 7D IO-7D-16.

### Trace 26 — the rate-limit store is down when a workflow calls a plugin (P1-7H-R06)
1. Redis is unreachable. A workflow node invokes a plugin capability.
2. The executor asks the limiter: error. It re-asks at most twice with jittered backoff inside the callout's time budget: still unavailable. The breaker opens.
3. **No request is sent to the plugin.** The executor writes the execution row `FAILED`, category `RATE_LIMITER_UNAVAILABLE`, and returns `INTEGRATION_OPERATION_FAILED`, `retryable = true`.
4. The node takes its `on_failure_edge`. Further callouts in this process are refused immediately while the breaker is open, without touching Redis. A probe closes the breaker when Redis answers; callouts resume under the normal limit.
- **Durable:** one execution row per refused callout. **Duplicate side effect:** none; nothing was sent.
- **Intervene:** nobody. **Signal:** limiter-unavailable refusals; breaker open time.
- **What is never done:** calling the plugin unmetered.

### Trace 27 — zero-grace rotation races an attempt (P1-7H-R07)
Endpoint P is at revision 5: current secret S1, no previous secret.
1. W1 claims D and is admitted: A(d, 1, 1) = (revision 5, …). It resolves S1 by revision 5's reference.
2. The tenant rotates to S2 with `grace_period_seconds = 0`. `fn_rotate_webhook_secret` locks the row, installs S2, clears the previous reference; the row becomes revision 6. The transaction, with its synchronous audit row (revision 6), commits at `t_x`.
3. **Sub-case 1: W1's re-check starts after `t_x`.** It reads revision 6 ≠ 5. W1 does not sign or send. It re-admits once: the admission function inserts AB(d, 1, 1) (`CONFIG_CHANGED`, `NOT_SENT`, uncounted) and then A(d, 1, 2) = (revision 6, …). W1 resolves S2, re-checks (still 6), signs with S2 and sends. The closure spends attempt 1. S1 was never used after `t_x`.
4. **Sub-case 2: W1's re-check returned revision 5 just before `t_x`.** W1 signs with S1 and hands off. The request is under revision 5 and reaches the receiver after the rotation. This is the residual of SIG-15. A receiver that has removed S1 rejects it (4xx), and attempt 2 is admitted under revision 6 and signed with S2. A receiver that still trusts S1 accepts it, which the platform cannot prevent (SIG-16). The records show the order: A(d, 1, 1) names revision 5; the audit row of revision 6 was committed after W1's re-check.
5. **Sub-case 3: W1 stalls for 7 s after admission.** Its admission timer has expired. It sends nothing: `ADMISSION_EXPIRED`, `NOT_SENT`, one attempt (OD-7H-13).
- **Step 2 cannot overlap step 1's admission:** had the rotation requested its lock while the admission held the share lock, it would have waited for the admission's commit (trace 29).
- **Hard bound:** in no sub-case is a request under revision 5 handed off later than `t_x` + 6 s.
- **Not claimed:** that the cutover is instantaneous, or that the re-check-to-hand-off interval is bounded by a guarantee.
- **Durable:** every admission with its revision; the rotation's audit row. **Duplicate HTTP:** no.
- **Depends on:** MR-7H-03, MR-7H-06, MR-7H-11; ERR-7H-09.

### Trace 28 — the configuration changes twice during one claim (OD-7H-15)
1. W1 claims D (`claim_seq` 3; `attempt_count` 2) and is admitted under revision 8. Before its re-check the tenant changes the URL: revision 9.
2. Re-check: mismatch. Re-admission: AB(d, 3, 1) is inserted (`CONFIG_CHANGED`, `NOT_SENT`, uncounted), then A(d, 3, 2) = (revision 9, new fingerprint). The organization lock and status check run again; the new destination will get its own egress validation at send; the secret is resolved by revision 9's reference; a fresh 6 s timer starts.
3. Before the second re-check the tenant rotates the secret: revision 10.
4. Second re-check: mismatch. There is no admission 3. W1 closes the claim: X(d, 3) `CONFIG_CHANGED`, `NOT_SENT`, origin `TENANT_CONFIGURATION`, `attempt_number` 3. D returns to `PENDING` with the frozen backoff for attempt 4.
5. Attempt 4 is admitted under whatever revision is then current.
- **Durable:** C(d, 3); A(d, 3, 1); AB(d, 3, 1); A(d, 3, 2); X(d, 3) with `CONFIG_CHANGED`, which is the record that nothing was sent under admission 2. Five inserts and no update of any of them. **Budget:** exactly one attempt spent for the claim; `attempt_count` 2 → 3.
- **Never sent:** nothing went to revision 8's destination or with revision 9's secret after each was known to be outdated.
- **Lease:** `claimed_at` did not move. Had the two re-admissions taken longer than `T_attempt_max`, W1 would have abandoned without recording and the sweep would have closed claim 3 under OD-7H-05 (`CLAIM_EXPIRED`, send state `UNCERTAIN` because an admission exists, one attempt).
- **Crash variant:** W1 dies after writing A(d, 3, 2). The sweep closes claim 3 as `UNCERTAIN` toward revision 9's destination, the latest admission.

### Trace 29 — a rotation races the admission itself (P1-7H-R08)
Endpoint P is at revision 5 (S1). W1 has claimed D.
1. **Order 1.** W1's admission takes the organization share lock, the delivery lock and then the endpoint share lock, and reads revision 5. The tenant's rotation calls `fn_rotate_webhook_secret`; its `FOR UPDATE` blocks. W1 inserts A(d, 1, 1) = (revision 5) and commits. The rotation proceeds and commits revision 6 at `t_x`, after the admission. W1's re-check, which starts later, reads 6: nothing is sent with S1; one uncounted re-admission under 6 (trace 27, sub-case 1).
2. **Order 2.** The rotation holds its `FOR UPDATE` first. W1's locking read blocks while its admission timer runs. The rotation commits; W1's statement returns the new row version; A(d, 1, 1) = (revision 6, S2's reference). Nothing was ever admitted under 5.
3. **On the version reviewed third** (plain read): W1 reads 5 without waiting; the rotation commits 6; W1 commits A = (revision 5) after `t_x`. C1 is false, and C4's premise "admitted before `t_x`" has no basis. That interleaving can no longer be scheduled: the read is now the statement that blocks or is blocked.
4. ✂ Variant: the rotation's session stalls while holding the lock. W1's lock timeout fires; nothing was inserted; the claim closes `ADMISSION_EXPIRED`, `NOT_SENT` (one attempt). ✂ Variant: W1 dies while holding the share lock. Its transaction aborts, the lock is released, no admission exists, the rotation proceeds, and the sweep later closes the claim `CLAIM_EXPIRED`, `NOT_SENT`.
5. Variant: a platform hard delete instead of a rotation. Order 1: the delete waits, the admission commits, and the request may be sent to a destination that existed when it was admitted. Order 2: the admission finds no row: `ENDPOINT_GONE`.
- **Durable:** the admission, with the revision that was current at its commit; the rotation's audit row. **Duplicate HTTP:** no.
- **Not claimed:** anything about a rotation that commits after the admission committed. That is C2, SIG-15 and C4.
- **Signal:** admission lock waits and lock timeouts. **Depends on:** MR-7H-03, MR-7H-11.

### Trace 30 — the previous secret is unavailable inside the grace, and at its edge (P1-7H-R09)
Endpoint P is at revision 6 = (current S2, previous S1, expiry e), rotated with a 3600 s grace.
1. **Unavailable, grace running.** Twenty minutes before e, W1 is admitted under 6 with the previous signature planned. The secret manager returns S2 and fails for S1. The re-check returns revision 6 and `rem` ≈ 1200 s. W1 sends nothing and closes the claim: X `SECRET_UNAVAILABLE`, `NOT_SENT`, origin PLATFORM, role PREVIOUS, one attempt. The version reviewed third sent this request with S2 only; a receiver still on S1 would have rejected a delivery inside a grace it had been promised.
2. **Later attempts.** The frozen schedule continues. If S1 becomes resolvable, the next attempt is dual-signed. If it stays unresolvable for the whole grace, each attempt inside the grace spends one attempt; the first attempt after e is admitted with no previous signature planned, or finds `rem ≤ 0`, and is sent with S2 only. For a delivery created at the rotation with the default `max_attempts` 7, the sixth attempt falls about 2 h 37 min after creation, after the 1 h grace. An endpoint with a small `max_attempts` can dead-letter first, and the tenant replays.
3. **Unavailable, grace over.** W1 is admitted 2 s before e; resolution of S1 fails; the re-check, 3 s later, returns `rem ≤ 0`. Situation (2), not (4): sent with S2 only.
4. **At the edge, secret in hand.** Grace 3 s. W1 is admitted 1 s after the rotation, resolves both secrets, and re-checks with `rem` = 0.4 s. If it hands off within 0.4 s of starting that re-check, the request is dual-signed. If not, it does not send, re-checks, finds `rem ≤ 0`, and sends with S2 only, after e. Under the withdrawn rule no request of this endpoint would have been dual-signed at all.
5. **Overlapping rotation.** S2 → S3 commits before W1's re-check: revision 7. Mismatch; nothing is sent under 6; re-admission under 7, whose required previous secret is S2. S1 is no longer part of any current configuration.
- **Never done:** a current-only request before e while a previous secret is configured; a previous-secret signature computed after a re-check showed the grace over.
- **Tenant-visible:** `failure_reason = SECRET_UNAVAILABLE`; no secret, reference or role detail beyond what 7I approves (HE-7I-7H-10). **Alert:** every `SECRET_UNAVAILABLE` with role PREVIOUS is a platform fault (a purge before expiry, or a secret-manager fault) and is signalled to 7J.
- **Durable:** A with the planning flag; X with category, origin and role. **Duplicate HTTP:** no. **Depends on:** MR-7H-03, MR-7H-06, MR-7H-11; ERR-7H-09, ERR-7H-10.

---

## 19. Observability and Operational Handoff

7J designs metric names, cardinality budgets, dashboards and alerts. 7H fixes what must be observable and what must never be recorded. No threshold is assigned here.

### 19.1 Identifiers every hop makes available

| Identifier | Fan-out | Dispatch attempt | Outcome | Replay | Callback | Plugin |
|---|---|---|---|---|---|---|
| Internal `event_id` | ✓ | ✓ | ✓ | ✓ | (resulting event) | — |
| Internal `event_type` / version and external topic | ✓ | ✓ | ✓ | ✓ | — | — |
| Delivery ID | created | ✓ | ✓ | old and new | — | — |
| Claim sequence | — | ✓ | ✓ | — | — | — |
| Attempt number | — | — (not yet assigned) | ✓ when the closure spent the budget | — | — | — |
| Destination fingerprint and key ID | — | ✓ from admission | ✓ | — | — | — |
| Lineage root | — | — | — | ✓ | — | — |
| `organization_id` | ✓ | ✓ | ✓ | ✓ | after verification | ✓ |
| Endpoint ID | ✓ | ✓ | ✓ | ✓ | — | — |
| Producer context; consumer group | ✓ | — | — | — | owning context | invoking context |
| `correlation_id`, `causation_id` (7C §16, §17) | ✓ (from the envelope) | ✓ if MR-7H-06 carries it, else by `event_id` | ✓ | request's own | receipt ID as causation | `plugin_executions.correlation_id` |
| Replay / redelivery provenance | 7G operation ID when applicable | — | — | `replay_of_delivery_id`, actor | — | — |

**OBS-7H-01 [FROZEN].** `organization_id` and other per-tenant identifiers appear in traces, structured logs and audit records. They are **never** Prometheus label values (6J §44; 7A TEN-05).

### 19.2 End-to-end trace

```
API request (request_id, trace)                         D0 correlation middleware
  → PostgreSQL transaction                              owner
  → outbox row (event_id, correlation_id)               7D OBS-7D emission points
  → Redis publication                                   7D / 7E
  → integration consumer (group, entry, event_id)       7F / 7G
  → durable delivery (delivery_id, endpoint_id)         §7
  → HTTP attempt (delivery_id, attempt_number)          §9
  → result (class, category, status, duration)          §8
```

The join key across the bridge is `event_id`: it is on the outbox row, in the stream entry, on every delivery row and in the public envelope and header. Within the delivery subsystem the key is the delivery ID. A tenant's support reference is the envelope `request_id` together with `X-Platform-Delivery-Id`.

### 19.3 Semantic signals handed to 7J (HE-7J-7H-01)

Per topic and outcome class unless stated; never per organization as a metric label: fan-out transactions committed, zero-match fan-outs, duplicate (claim-conflict) fan-outs, rows created per fan-out; fan-out lag (commit time − `occurred_at`); deliveries by status; `PENDING` backlog and age of the oldest due row; held backlog and age by organization status; `DELIVERING` count and age of the oldest; attempts by outcome class and category code; attempt duration; attempts per delivery at completion; time from creation to terminal state; next-eligibility distribution; `Retry-After` observed; dual-signature attempts; `SECRET_UNAVAILABLE` closures split by secret role; re-checks repeated at a grace boundary; admission lock waits and lock timeouts on the endpoint row; stale-claim releases, split by whether an admission existed; fence mismatches; uncounted releases; admissions, admission-window misses and attempts closed after an organization status change; re-check mismatches, re-admissions, claims closed `CONFIG_CHANGED`, hand-off timer overruns; closures by failure origin and by send state; attempts sent under a revision superseded before their closure; cancellations by reason; dead letters; replays requested, refused by reason (per-delivery quota, per-lineage quota, lineage window, inactive endpoint), completed; lineage depth; test deliveries; egress rejections by rule; DNS, TLS and connect failure rates; dependency-gate open time; purge runs; inbound receipts by provider and status, duplicate receipts, verification failures, resolution failures, stale-receipt re-dispatches, age of the oldest non-terminal receipt, processing attempts per receipt, extraction failures; plugin executions by plugin, capability and status, scope denials, rate-limit refusals, limiter-unavailable refusals, limiter breaker open time, timeouts.

The existing 6J §44 metric names remain the starting vocabulary; 7J reconciles names.

### 19.4 Never recorded

[FROZEN] 7A SEC-01, SEC-04, SEC-07; 6J §44.4; D0 redaction (§6 notes): webhook signing secrets; authorization credentials; signature header values; raw or sensitive payloads; signed media capabilities; unredacted recording or transcript content; tokens; URL credentials and query strings. **[7H]** Additionally: the signing input, response bodies beyond the bounded stored preview, and full destination URLs (host only).

### 19.5 Deferred with enough detail not to be lost

| To | Item |
|---|---|
| 7J | Names and cardinality for §19.3; dashboards; the alert conditions for: oldest due `PENDING` age, oldest `DELIVERING` age exceeding the lease, fence-mismatch rate above zero, dead-letter rate, held backlog growth, verification-failure bursts per provider, any `SECRET_UNAVAILABLE` closure with role PREVIOUS (a platform fault by definition, SIG-18), admission lock-wait time on endpoint rows |
| 7K | Dispatcher and sweep worker counts; claim batch size and poll cadence; `T_claim_lease`, `T_attempt_max`, J; per-organization and per-endpoint caps; egress pool; SLO calculations for delivery latency. 7H assigns no threshold |

---

## 20. Commercial and Capacity Constraints

### 20.1 Commercial treatment

| Question | Answer | Source |
|---|---|---|
| Is external delivery billed? | No. Not a V1 metric | [FROZEN] 6J §46, J4; AIR L1752 (FAR-classified FUTURE) |
| Organization entitlement? | None gates webhooks or plugins in V1 | NOT FOUND in 6K |
| Do retry attempts count toward usage? | No usage is recorded at all | [FROZEN] 6J §46.2 |
| Separate plugin quotas? | No billing quota. An operational rate limit exists (`manifest.rate_limit_per_minute`, narrowable per installation) | [FROZEN] 6J §25.3 |
| Platform-admin overrides? | None defined for webhook limits. Quota overrides in 6M concern billing metrics, which webhooks are not | NOT SPECIFIED |
| Could it be billed later? | The raw facts (delivery rows, execution rows) are durable; 6K would define `source_system` and `source_event_id` | [FROZEN] 6J §46 |

| ID | Rule |
|---|---|
| COM-01 [FROZEN] | 7H writes nothing to `billing.usage_events`, defines no metric and computes no charge. |
| COM-02 [FROZEN] | No client-supplied value is a price, a quota or a billed quantity. Should delivery ever be metered, the quantity would be counted server-side from platform rows (7A BIL-01, BIL-02). |
| COM-03 [FROZEN] | Provider cost and margin never appear in a webhook body or a plugin payload (7A BIL-05; 6K §24). |
| COM-07 [OD] | A claim closed `NOT_SENT` is never a billable outbound request, should delivery ever be metered (OD-7H-13). 7H still defines no metric (COM-01). |

### 20.2 Bounded work

Two budgets exist and are never added into one number: the **automatic** budget, which the platform spends without anyone asking, and the **manual** budget, which only authenticated tenant actions can spend.

**Automatic budget (no human action).**

| Source of work | Bound | Tag |
|---|---|---|
| Requests per delivery | ≤ `max_attempts` ≤ 10 | [FROZEN] |
| Fan-out deliveries per event | = N, the number of the organization's endpoints that are `ACTIVE` and subscribed to the topic in the fan-out snapshot. N has **no database-enforced maximum**: `062_5I` puts no constraint on endpoints per organization, and 6J §45.2 gives 20 as a placeholder default that is product configuration, "not hard-coded" | [FROZEN] 6J §45.2; `062_5I` |
| **Automatic requests per event** | ≤ the sum, over those N deliveries, of each delivery's own `max_attempts` (1 – 10, copied from its endpoint at creation); hence ≤ 10 × N. With the placeholder limit this is 200 **only if** the endpoint-count limit is enforced authoritatively and concurrency-safely when endpoints are created and enabled. No frozen source specifies that enforcement (CNF-7H-21; IO-7H-17). Per delivery, spread over at most about 82 h 37 min of schedule time (longer if the organization is held) | derived; conditional |
| Request size; response read | ≤ 256 KB; ≤ 2 MB and ≤ `timeout_ms` ≤ 30 s | [FROZEN] |
| Claim lifetime; admission validity | ≤ `T_claim_lease`; ≤ 6 s | [7H]; [OD] |
| Stale-claim loops | Each release spends one attempt | [OD] OD-7H-05 |
| Uncounted releases (T-09) | Possible only while the organization is not `ACTIVE`, and a not-`ACTIVE` organization's rows are not claimable, so at most one per delivery per suspension | [OD] |
| Uncounted re-admissions (HTP-18) | At most one per claim; a second configuration change in the same claim spends an attempt | [OD] OD-7H-15 |
| Claims closed without a request (`ADMISSION_EXPIRED`, `SECRET_UNAVAILABLE`, `ENDPOINT_GONE`, `CONFIG_CHANGED`) | Each spends one attempt and follows the frozen schedule; none loops | [OD] OD-7H-13, OD-7H-15, OD-7H-17, OD-7H-18 |
| Re-checks repeated at a grace boundary (SIG-06) | Inside one admission window: ≤ 6 s, then `ADMISSION_EXPIRED` | [OD] OD-7H-16 |
| Wait for the endpoint share lock at admission | ≤ the admission lock timeout, itself below 6 s | [7H] ELK-05 |
| Held deliveries | ≤ 90 days | [OD] OD-7H-02 |
| Internal fan-out retries | 5 genuine failures, then parked | [FROZEN] OD-7G-01 |
| Callback ingress and processing | Layered limits; 1 MB body; processing attempts bounded per receipt (CBK-21) | [FROZEN]; [7H] |
| Plugin callouts | Rate limit per (organization, plugin); refused when the limiter is unavailable; no automatic retry of a sent call | [FROZEN]; [OD] OD-7H-11 |

**Manual budget (each unit is an authenticated, authorized, audited tenant request).**

| Source of work | Bound | Tag |
|---|---|---|
| Replays per parent | ≤ 10 per 24 h; one open at a time | [FROZEN] |
| Replays per lineage | ≤ 10 per 24 h; lineage open ≤ 30 days (`DELIVERED` root) or ≤ 90 days (`DEAD_LETTER` root) → ≤ 310 or ≤ 910 replay deliveries per lineage in total | [OD] OD-7H-10 |
| Requests per replay delivery | ≤ `max_attempts` ≤ 10 (its own automatic budget) | [FROZEN] |
| Test deliveries | ≤ 10 per hour per endpoint, each a new lineage root | [FROZEN] |

**Correction of earlier drafts.** The first version stated that one event causes at most 200 outbound requests. That figure describes only the automatic budget, and only under the endpoint-count condition stated above (Minor-7H-R03). With manual replay, one event and one endpoint can cause up to 10 + 910 × 10 = 9,110 requests over the life of a lineage, and without the lineage rule of OD-7H-10 the frozen function allows growth limited only by the tenant API rate limit (§13.5.1). Until MR-7H-08 exists the lineage rule is not enforced; this is one reason the dispatcher is not activatable (AB-7H-02).

The volume of **events** is not bounded by 7H: it follows tenant activity. A contact import or a large campaign produces one `lead.created` or `campaign.contact.qualified` per contact (CNF-7H-03).

### 20.3 Fairness

| ID | Rule |
|---|---|
| COM-04 [7H] | **Per-tenant fairness is required.** One organization's backlog (an import burst, a reactivation after suspension, a dead endpoint) must not delay other organizations' deliveries without bound. The frozen `fn_claim_delivery` orders globally by `next_attempt_at`, which gives no such protection; the claim of MR-7H-02 must allow a selection that bounds the share of one organization per batch. The mechanism and its values are 7K's (HE-7K-7H-01). |
| COM-05 [7H] | **Per-endpoint in-flight cap.** The dispatcher bounds concurrent attempts to one endpoint, so a slow receiver holds at most that many workers for at most `timeout_ms` each. Value: 7K. |
| COM-06 [7H] | Fairness and caps are throughput controls only. They never reorder for correctness, never drop a delivery and never consume attempts. |

---

## 21. Cross-Phase Reconciliation Matrices

Matrices B, C, D, F and G are placed where they are used: **B** §5.2, **C** §10.2, **D** §8.2, **F** §13.3, **G** §17.1. A, E, H, I and J follow.

### 21.1 Matrix A — source contract reconciliation

| Frozen contract | Source | Preserved in 7H by |
|---|---|---|
| Eight distinct mechanisms; Phase 7 implements, does not redesign | AIR §18 | §4.1, BND-01 |
| Classification counts: `PUBLIC_WEBHOOK_DELIVERY` 2, `PROVIDER_CALLBACK` 3 | AIR §18.2; 7A §6.1 | §11.1; T-02, T-03 (the two Class G routes) |
| Modular monolith; bounded context ≠ microservice | 7A OWN-03; 6J L58 | CMP-R1 |
| State and event commit together | 7A DUR-01; 7D §10 | F2; trace 1 |
| No transaction across external I/O | 6A §35; 7A PR-06 | INV-NOSPAN; §17.2 |
| At-least-once; no exactly-once claim | 7A DEL-01, DEL-04; 6J §22.1 | INV-NOEXACT; IDM-7H-03 |
| Stable `event_id` across retry, redelivery, replay | 7A EVT-02, IDM-01 | §3.1; HTP-06 |
| Webhooks are external delivery from committed events | 7A WH-01, WH-02 | BND-02; §7 |
| Only governed topics are eligible; scoped projection | 7A WH-04, WH-05; 6J §19, §20.2 | §5 |
| Signing contract, raw-body rule, timestamp source | 7A WH-06 … WH-09; 6J §21; AVS SG-01 | §9.3, §9.4, SIG-01 |
| Plugin canonical input differs; builders not shared | 7A WH-10; AVS SG-06 | SIG-02, SIG-03 |
| No signature change, no successor header | 7A WH-12; AVS SG-03 … SG-09 | SIG-04 |
| Dual-signature rotation | 6J §21.1, §21.3; AVS SG-07 | SIG-05 … SIG-09, SIG-14 … SIG-16; §10.1.1 (cutover wording reconciled by ERR-7H-09) |
| Rotation changes three endpoint columns atomically | `fn_rotate_webhook_secret` (`101_5I1`) | HTP-15; MR-7H-11 (revision incremented by the same transaction) |
| Mandatory audit in the originating transaction | 7D §36 AUD-7D-01, AUD-7D-02 (OD-7D-02 = A) | DST-05; CNF-7H-18 |
| Topic evolution by successor topic only | AVS CM-WH-01 … 06; 7A VER-05 | §15 |
| Envelope shape | 6J §20.1; 7C WHB-01 | §9.2 |
| Retry schedule, timeout, classification | 6J §22.3, §22.4; 6A §21 | §9.6, §13.2 |
| Dead-letter and delivered retention | 6J §22.6; 5I §14, §23 | §17.4 |
| Replay as a new row with the same `event_id` | 6J §23.3; 7A RPL-03 | §13.5 |
| Disable semantics; `DELETE` = disable | 6J §18.6, §18.8; ADR-6J-02 | §6.3 |
| Egress adapter contract | 6J §30.3; ADR-6J-06 | §14.4 |
| Callback: verify, dedup, fast ACK, async | 7A CB-01 … CB-07; 6J §24 | §11 (extraction of the processing input moved before the ACK: ERR-7H-05) |
| Callback recovery processes the stored, verified record | 7D REC-04, PCI-13, PCI-25, PCI-28 | CBK-04, CBK-10; §11.4 |
| Organization status changes lock the organization row | `105_5B4`, `107_5B5` | ADM-01 … ADM-09 |
| Plugin rate limit enforced before the callout | 6J §25.3; 4F §9.3 | PLG-08, PLG-15 … PLG-18 |
| Callback tenant resolution | 6J ADR-6J-10; 7B Rule H-2 | CBK-03, CBK-08 |
| Voice callbacks use the shared inbound mechanism | 6D §10.4; 6J §24.5 | §11.1 |
| Payment receipts and dedicated ingress role | 6K; `102_5H2` | §11.1; CBK-10 |
| Plugins are external HTTP services | 4F §9.3; 5I §24; 6J §25.1 | PLG-14 |
| Plugin authority intersection; version pinning | 6J §28.3, §30.5 | PLG-02, PLG-03 |
| No auto-retry of non-GET | 6A §21; 6J §30.5 | PLG-07 |
| CON-10 transaction, claim, ACK rules | 7F §28.11, §26, §27 | §7.1; INV-ACK |
| Domain-owned idempotency; no shared inbox | 7F DD-13 Pattern A; 7A IDM-06 | IDM-7H-01 |
| `H_active` vs `H_capable`; intervals; origin record | 7F §10.4 | §16.3 |
| 7G budget, ledger, classes apply to consumers only | 7G §9, §10, §14 | XRT-01, XRT-02 |
| 7G never replays a delivery; CON-10 admission | 7G §30, §41.1, §44 | §13.6 |
| Late / replayed event fans out to currently active endpoints | 7F §28.11; 7G HE-7H-7G-02 | SUB-02; XRP-05 |
| Tenant context from trusted state; RLS not bypassed | 7A TEN-01 … TEN-04 | §14.1; PER-02 |
| No secrets, signed URLs, media in events or bodies | 7A SEC-01, SEC-04; 6J §39, §40 | PRJ-06; §19.4 |
| Cost and margin internal | 7A BIL-05; 6K §24; 6L DEC-6L-02 | PRJ-06; COM-03 |
| No bus or REST hop on the voice media path | 7A VOX-02, VOX-03 | PLG-09 |
| India residency | 7A RES-01 … RES-03 | RES-7H-01 |
| Metrics carry no tenant label | 6J §44; 7A TEN-05 | OBS-7H-01 |
| Webhook usage not billed in V1 | 6J J4; AIR L1752 | §20.1 |
| Cross-tenant admin replay not built; delivery DML narrowed | 6M `DBGAP-6M-04`, `-10`; `109_5B7` | §14.3; §13.5 |
| Runtime readiness vs schema gate | OD-D0-01 | Unaffected; 7H adds no readiness claim |
| Topic source of `call.started` / `call.completed` | 4F §8.4; 7B IO-7B-12 | CNF-7H-04; §5.2 |

### 21.2 Matrix E — idempotency and duplicate recovery

| Repeated path | What repeats | Owning guard | Result of the repeat | Residual duplicate |
|---|---|---|---|---|
| Producer request retried | The request | Route `Idempotency-Key` (6A §16); one fact one row (7D §11) | One event | None |
| Relay republishes | Stream entry | Fan-out claim | `ALREADY_COMMITTED` | None |
| Redis redelivery / reclaim | Entry delivery | Fan-out claim | `ALREADY_COMMITTED` or first execution | None |
| Concurrent fan-out workers | TX-1 | Claim primary key | One winner | None |
| Crash before fan-out commit | TX-1 | Atomic transaction | Runs once later | None |
| Crash after commit, before `XACK` | Acknowledgement | Claim | `ALREADY_COMMITTED` | None |
| Internal replay R2 – R5 | Entry or internal dispatch | Claim; origin record; evidence horizon | No rows | None inside the horizon; beyond it the handler does not run |
| Two dispatchers claim | Claim | `SKIP LOCKED` | Disjoint sets | None |
| Late report from a released worker | Outcome write | Fence on `claim_seq` | No change | None in state; one extra HTTP request only if the worker also violated its deadline |
| A claim released uncounted, then claimed again | Claim | `claim_seq` advances; no attempt number is issued for the released claim (DSM-07 H5) | Two claim identities, one attempt identity | None |
| Replay of a replay; concurrent replays of sibling descendants | Replay creation | Lineage anchor lock; per-lineage and per-delivery quotas; lineage window | Refused beyond 10 per 24 h or after the root's window | None beyond the stated manual budget |
| Callback processing after the request process died | Callback processing | Stored processing input; processing claim; domain guards | Command rebuilt and applied once | None if the guard holds |
| Stale-claim release after a sent request | HTTP attempt | `max_attempts`; receiver dedup on event ID | Counted retry | **One extra HTTP request** |
| Lost response / ambiguous outcome | HTTP attempt | Same | Counted retry | **Extra HTTP request(s)** |
| Public replay requested twice | Replay creation | Open-replay check in the function | Same replay ID | None |
| Public replay (intended) | Delivery | Rate limit; receiver dedup | New delivery | The receiver sees the event again by design |
| Test delivery | Delivery | 10 per hour; each intentionally distinct | New delivery each time | By design |
| Provider retries a callback | Receipt insert | Unique (`organization_id`, `provider_slug`, `provider_event_id`) | No row, same 2xx | None |
| Stale-receipt re-dispatch | Callback processing | Owning domain's guards (CBK-09) | No second effect | None if the guard holds |
| Workflow re-runs a plugin node | Callout | 6I `node_execution_claims`; the plugin's own contract | Second call | Possible at the plugin (CNF-7H-10) |
| Subscription changed mid-flight | — | Fan-out snapshot | One consistent decision | None |

**Invariant against accidental duplicate delivery rows:** for one event and one endpoint, the rows that can exist are exactly (a) at most one created by fan-out, guaranteed by UQ-01 and UQ-02, and (b) rows created by explicit public replay, each carrying `replay_of_delivery_id`. A row with a `NULL` `replay_of_delivery_id` that duplicates another for the same (`event_id`, `webhook_endpoint_id`) is therefore an invariant violation and a detectable anomaly, not an expected outcome.

### 21.3 Matrix H — security and privacy exposure

| Sensitive family | Present in internal state / event | Permitted public projection | Prohibited in any webhook body or plugin payload |
|---|---|---|---|
| Call media | Recordings, transcripts, turn content | `call_id` only; the tenant fetches through 6D's authenticated endpoints | Transcript text, recording bytes, **any signed or presigned URL**, base64 media |
| Call party numbers | `from_number`, `to_number` in `call.initiated` | None in V1 | Both numbers |
| Contact identity | `phone_e164`; name and email in CRM state | `phone_number`, `name`, `email` on `lead.created` / `lead.qualified`; `phone_number`, `name` on `appointment.booked` (6J §40.2) | Any other contact attribute; notes; score signals |
| Qualification and loss reasons | Free text in CRM / Campaign events | None in V1 | `qualification_reason`, `lost_reason` |
| Deal data | Value, title, pipeline | IDs; `value` on `deal.won` | Deal title; any embedded contact text |
| Appointment data | Schedule, organizer, title, location | IDs and the two timestamps | Organizer reference, title, location |
| Financial | Invoice totals, tax snapshot, provider transaction | `invoice_number`, `total_due`, `currency`, `status`; `failure_code` (6K §45.1) | GSTIN, addresses, tax lines, card data, `provider_transaction_id`, provider error text |
| Platform commercial | Provider procurement cost, margin, cost entries | None | All of it (7A BIL-05; 6K §24) |
| Usage | Usage records, limits | `metric`, `threshold`, `period_start` | Hard limit, current usage, pricing |
| Identity and security | Sessions, JTIs, API keys, audit rows | None: not webhook-eligible | Everything |
| Integration and plugin | Credential refs, OAuth state, configuration | None: not webhook-eligible | Every `*_ref`, token, secret |
| Delivery internals | `claimed_by`, `payload_hash`, attempt counts, endpoint ID | None | All |
| Compliance | Consent, DNC, suppression | None: no topic exists | Everything |
| Provider callbacks | Raw provider payload, provider signature | None: never forwarded (BND-02) | Everything |

A webhook body is delivered only to an endpoint of the organization that owns the event. No projection contains another organization's data, because the serializer and its read ports run under the event's tenant context with RLS in force.

### 21.4 Matrix I — API and event contract traceability

| Frozen API obligation | Route(s) | Canonical event / artifact | 7H boundary |
|---|---|---|---|
| Register a destination | 6J-018 `POST /webhook-endpoints` | Endpoint row; internal `webhook.endpoint_created` (not eligible) | §6.1; egress validation §14.4 |
| Read / list destinations | 6J-017, 6J-019 | — | Unchanged |
| Update a destination | 6J-020 `PATCH` | Endpoint row | SUB-04 (OD-7H-01) |
| Disable / delete / enable | 6J-021, 6J-022, 6J-023 | Endpoint `status` | §6.3 |
| Rotate secret | 6J-024 | `fn_rotate_webhook_secret` | SIG-05 … SIG-08 |
| Test delivery | 6J-025 (`PUBLIC_WEBHOOK_DELIVERY`) | `platform.test` delivery row | T-02; OD-7H-06; ERR-7H-02 |
| List / read deliveries | 6J-026, 6J-027 | Delivery rows | §9.2 (`payload_json` is the exact body); §14.1 |
| Replay a delivery | 6J-028 (`PUBLIC_WEBHOOK_DELIVERY`) | New delivery row | §13.5, §13.5.1; OD-7H-03, OD-7H-10; ERR-7H-01, ERR-7H-06 |
| Inbound integration callback | 6J-014 (`PROVIDER_CALLBACK`) | Receipt row and processing input | §11; OD-7H-08; ERR-7H-05 |
| Inbound-event observability | `GET /inbound-webhook-events` | Receipt rows | CBK-13 |
| Voice provider callback | 6D-021 (`PROVIDER_CALLBACK`) | Receipt row and processing input → EV-073, EV-075, EV-005, EV-006 | §11; OD-7H-08; CBK-14 |
| Payment provider webhook | 6K-023 (`PROVIDER_CALLBACK`) | `payment_webhook_receipts` → EV-103, EV-104 | §11; CBK-10 |
| Platform-admin delivery diagnostics | 6M `GET /platform-admin/webhooks/failed`, `/dead-letter` | Read-only | §14.3; CNF-7H-07 |
| Plugin install / activate / upgrade / suspend / uninstall | 6J §27, §29 | Installation rows; internal `plugin.*` (not eligible) | §12 |
| Workflow plugin / webhook node execution | 6I §23, §67; 6J §30 (in-process, no route) | `plugin_executions` | §12; PLG-07, PLG-09 |
| Call lifecycle producers | 6D-001, 6D-004, provider path | EV-004, EV-005, EV-006, EV-075 | Topics 01 – 04; AB-7H-03 for 01, 02 |
| CRM producers | 6G-001, 6G-006, 6G-029, 6G-034, 6G-035, 6G-062 | EV-021, 024, 025, 035, 037, 038, 046 | Topics 05 – 11 |
| Campaign producers (executor) | 6H worker paths | EV-084, EV-085, EV-091 | Topics 12 – 14 |
| Billing producers | 6K-006 / 007 / 008; invoice and payment workers; usage aggregation | EV-071, EV-102 … EV-105 | Topics 15 – 19 |
| Every other producing route (the rest of the 77 outbox-creating routes) | 6B … 6M | Internal events | Internal-only; no 7H surface |

7H adds no route, no permission and no error code. It needs two controlled errata to existing error-row text (§22.3).

### 21.5 Matrix J — deferred responsibilities

Detailed in §23. Summary so that none can be lost:

| To | IDs | Subject |
|---|---|---|
| 7I | HE-7I-7H-01 … 10 | Roles and grants for the guarded functions; DSR and retained bodies; DNC / consent confirmation; cross-border destinations; `CANCELLED` retention; field classification of the §5.3 baseline and history-record exposure; callback processing-input encryption and retention; lineage-anchored purge; destination-evidence key custody; tenant-safe failure categories. **HE-7I-7H-08 blocks replay activation** |
| 7J | HE-7J-7H-01, 02 | Signals of §19.3; alert conditions of §19.5 |
| 7K | HE-7K-7H-01 … 07 | Fairness mechanism and caps; worker, lease and jitter values; import and reactivation bursts; endpoint-health policy; partition maintenance; egress topology and regional placement; the hand-off target and the cost of the added per-attempt transactions |
| 7L | HE-7L-7H-01 … 08 | Conflict register; errata; activation register; unspecified plugin items; the unclosed 7F handoff; the successor-topic rule; the remediation's added conflicts and errata |

---

## 22. Owner Decision Register

OD-7H-01 … OD-7H-07 were put to the owner on 2026-10-10 before the affected sections were written. OD-7H-08 … OD-7H-11 were put to the owner on 2026-10-10 during the remediation of the first independent review, and the owner then restated them in writing with the refinements recorded below. OD-7H-12 … OD-7H-15 were put to the owner on 2026-10-10 during the remediation of the second independent review and confirmed by the owner in writing, with the conditions recorded below. OD-7H-16 … OD-7H-18 were put to the owner on 2026-10-10 during the remediation of the third independent review, answered, and then confirmed by the owner in writing with the conditions recorded below. Each was decided as shown. **Approved: 18. Pending: 0.**

| ID | Subject | Decision | Status |
|---|---|---|---|
| OD-7H-01 | Destination authority for an existing delivery | A: live endpoint configuration | APPROVED |
| OD-7H-02 | Organization not `ACTIVE` | A: hold while suspended | APPROVED |
| OD-7H-03 | Replay toward an inactive endpoint | A: reject | APPROVED |
| OD-7H-04 | Backoff before attempts 9 and 10 | A: 24 h each | APPROVED |
| OD-7H-05 | Released stale claim | A: spends one attempt | APPROVED |
| OD-7H-06 | Test delivery to an inactive endpoint | A: reject | APPROVED |
| OD-7H-07 | V1 `data.object` baseline | A: minimal | APPROVED |
| OD-7H-08 | Durable callback processing facts | A: normalized input in the receipt transaction | APPROVED |
| OD-7H-09 | Suspension guarantee | A: bounded window, 6 s admission validity, 30 s maximum timeout | APPROVED |
| OD-7H-10 | Replay lineage | A: 10 per lineage per 24 h; window = the root's own retention (30 / 90 days) | APPROVED |
| OD-7H-11 | Plugin rate-limit store unavailable | A: fail closed | APPROVED |
| OD-7H-12 | Configuration cutover (URL edit, rotation) | B: coherent revision at admission plus a last-instant revision re-check; 6 s admission deadline kept | APPROVED |
| OD-7H-13 | Platform-side pre-send failures | A: spend one attempt, `NOT_SENT`, own category | APPROVED |
| OD-7H-14 | Lifetime of replayed body copies | A: delegated to 7I, with a mandatory activation gate | APPROVED |
| OD-7H-15 | Configuration change detected between admission and hand-off | B: one uncounted re-admission per claim; a second change spends an attempt | APPROVED |
| OD-7H-16 | Dual signing at the grace boundary | B: the full configured grace; validity proven on the database clock at the final re-check; no early cutoff | APPROVED |
| OD-7H-17 | Required previous secret unavailable | A: do not send; `SECRET_UNAVAILABLE`, `NOT_SENT`, PLATFORM, one attempt | APPROVED |
| OD-7H-18 | Endpoint row hard-deleted (`ENDPOINT_GONE`) | A: one failed attempt per claim, `NOT_SENT`, PLATFORM; `DEAD_LETTER` by exhaustion only | APPROVED |

### OD-7H-01 — Destination authority for an existing delivery — **decided: A**

1. **Missing requirement.** A delivery row stores `webhook_endpoint_id` and no destination attribute. 6J defines disable-while-pending (§18.8) but is silent on a `PATCH` of `target_url` while deliveries are pending.
2. **Why an owner choice.** It changes where tenant data is sent after a configuration edit and whether a schema change is needed.
3. **Alternatives.** A: bind to the endpoint resource, read URL, timeout and secret live at each attempt. B: pin a destination generation; after a URL change, close older pending deliveries as `CANCELLED`. C: snapshot the URL on each delivery.
4. **Security / isolation.** In all three the destination is chosen by a principal of the same organization with `webhook:manage`, and is egress-validated. B and C do not prevent exfiltration by a compromised manager, who can replay delivered history to the new URL in any option.
5. **Reliability / operations.** A lets a tenant repair a broken URL for pending deliveries. B loses them unless replayed, and `CANCELLED` is not replayable today. C keeps retrying a URL the tenant has abandoned.
6. **Cost.** A needs no migration. B and C do.
7. **Preferred.** A, with the edit audited and destination evidence recorded per attempt (SUB-05, SUB-06).
8. **Approved.** A. Applied in §6.2, §6.3.

### OD-7H-02 — Organization not `ACTIVE` — **decided: A (hold while suspended)**

1. **Missing requirement.** No frozen source states the effect of organization suspension or cancellation on webhook fan-out or pending deliveries.
2. **Why an owner choice.** It is a product and compliance policy: whether a suspended tenant keeps receiving data, and whether events during suspension are lost.
3. **Alternatives.** A: keep creating rows, send nothing while not `ACTIVE`, resume uncounted on reactivation, cancel at 90 days or on organization cancellation. B: suspension does not affect webhooks. C: create nothing and cancel pending rows.
4. **Security / isolation.** A and C stop egress for an organization suspended for abuse. B does not.
5. **Reliability / operations.** A is lossless within 90 days and produces a release burst on reactivation. C loses events irrecoverably.
6. **Cost.** A needs the claim guard, the uncounted release and the cancellation functions (MR-7H-02, 04, 05). B needs nothing.
7. **Preferred.** A.
8. **Approved.** A. Applied in §8, §14.2.

### OD-7H-03 — Replay toward an endpoint that is not `ACTIVE` — **decided: A (reject)**

1. **Conflict.** 6J §18.8 and 4F §8.1: a non-ACTIVE endpoint "receives no new deliveries". The replay function creates a new delivery and does not check endpoint status.
2. **Why an owner choice.** Either reading changes a public route's behaviour.
3. **Alternatives.** A: refuse with the existing `422 WEBHOOK_REPLAY_NOT_ALLOWED`. B: allow, treating replay as an explicit privileged exception.
4. **Security.** A makes "disabled" mean no new traffic by any path.
5. **Reliability.** A requires the check inside the function to be race-free against a concurrent disable (MR-7H-08).
6. **Cost.** A small controlled erratum (ERR-7H-01) and a function-body change.
7. **Preferred.** A.
8. **Approved.** A. Applied in §13.5.

### OD-7H-04 — Backoff before attempts 9 and 10 — **decided: A (24 h each)**

1. **Missing requirement.** 6J §22.3 defines waits up to attempt 8; `max_attempts` may be 9 or 10.
2. **Why an owner choice.** It is a tenant-visible retry semantic not frozen anywhere.
3. **Alternatives.** A: 24 h for both. B: keep doubling (48 h, 96 h).
4. **Security.** None.
5. **Reliability.** A bounds a 10-attempt delivery to about 82 h 37 min; B to about 178 h 37 min, holding rows much longer.
6. **Cost.** Negligible either way.
7. **Preferred.** A: the last frozen step is the schedule's ceiling, as 6J §22.4's own wording implies.
8. **Approved.** A. Applied in §13.2.

### OD-7H-05 — Attempt accounting for a released stale claim — **decided: A (count)**

1. **Missing requirement.** 5I notes that a stale claim is "detectable"; no contract says what a release costs.
2. **Why an owner choice.** It decides whether a delivery can dead-letter after fewer confirmed sends, against whether work is strictly bounded.
3. **Alternatives.** A: count one attempt. B: do not count; add a separate crash-release counter and limit.
4. **Security.** A removes a loop a delivery that crashes workers could otherwise sustain.
5. **Reliability.** A may dead-letter earlier under repeated crashes; the tenant can replay.
6. **Cost.** B needs an extra column and limit.
7. **Preferred.** A: consistent with "a timeout is a failed attempt" (6J §22.3) and keeps one budget (DSM-05).
8. **Approved.** A. Applied in §8.2 T-08, §13.2.

### OD-7H-06 — Test delivery to an endpoint that is not `ACTIVE` — **decided: A (reject)**

1. **Missing requirement.** The test route creates a real delivery; no error is defined for a non-ACTIVE endpoint.
2. **Why an owner choice.** Public route behaviour.
3. **Alternatives.** A: `409 STATE_CONFLICT`. B: allow, as a documented exception.
4. **Security.** A is consistent with OD-7H-03.
5. **Reliability.** Under A a tenant enables, then tests.
6. **Cost.** A one-line erratum (ERR-7H-02).
7. **Preferred.** A.
8. **Approved.** A. Applied in §6.3, §8.2 T-02.

### OD-7H-07 — V1 `data.object` baseline — **decided: A (minimal)**

1. **Missing requirement.** Exact field lists are frozen only for the five billing topics and one example; 6J §40.2 gives sensitivity classes for the rest.
2. **Why an owner choice.** It is data exposure to external systems.
3. **Alternatives.** A: identifiers, timestamps, enums, amounts, plus only fields a frozen contract names. B: also free-text and descriptive fields read from the owning context.
4. **Security / privacy.** B would expose fields 7B routed to 7I before that classification exists.
5. **Reliability.** None.
6. **Cost.** A needs fewer read ports.
7. **Preferred.** A: widening later is non-breaking, narrowing later is not.
8. **Approved.** A. Applied in §5.3.

### OD-7H-08 — Durable callback processing facts — **decided: A**

1. **Conflict.** 7D REC-04 requires recovery to process "the stored, already-verified record"; 6J §24 acknowledges before normalization; `inbound_webhook_events` stores identifiers only and the raw payload is not retained (CNF-7H-14).
2. **Why an owner choice.** Every fix either stores more than today or changes what the 2xx means.
3. **Alternatives.** A: commit a minimal verified, normalized processing input with the receipt, before the 2xx. B: retain the encrypted raw payload for providers whose processing is mandatory. C: keep identifiers and re-query the provider on loss.
4. **Security / privacy.** A stores the least; B stores whole provider payloads; C stores nothing but cannot be made general.
5. **Reliability.** A and B are lossless after the 2xx. C depends on a provider query capability the frozen telephony port does not have (7D VCC-02).
6. **Cost / latency.** A adds CPU-only extraction before the acknowledgement. B adds an object-store write on the acknowledgement path.
7. **Preferred.** A; it is the pattern Billing already uses (`102_5H2`).
8. **Approved.** A, with the owner's conditions: same durable transaction as the receipt, before the 2xx; signature verification, tenant isolation, domain idempotency, encryption, data minimization, retention and erasure preserved; raw payload not retained by default; a controlled 6J erratum and a future migration documented. Applied in §11.2 – §11.4; MR-7H-09; ERR-7H-05.

### OD-7H-09 — Suspension guarantee — **decided: A (bounded window)**

1. **Conflict.** OD-7H-02 said no HTTP is sent while an organization is not `ACTIVE`. That cannot be exact: a status check cannot be held valid across an HTTP call without holding a database lock across it, which INV-NOSPAN forbids.
2. **Why an owner choice.** It replaces an absolute policy statement with a bounded one.
3. **Alternatives.** A: share-lock the organization row at the claim and at a final pre-send admission; allow a request admitted before the suspension to start within a fixed validity window. B: the same, plus a best-effort abort signal for requests already in flight.
4. **Security.** A gives a hard, small bound. B shortens typical exposure but guarantees nothing more.
5. **Reliability.** B adds a Redis dependency to suspension and more ambiguous-outcome attempts.
6. **Cost.** A adds one short write transaction per attempt (the admission).
7. **Preferred.** A.
8. **Approved.** A, with a **6-second** admission validity window and the frozen 30-second maximum timeout; real row-lock synchronization with suspension; a precisely defined admission point; no new admission after the suspension commits; no transaction open across HTTP. Applied in §9.4, §14.2.1 (ADM-01 … ADM-09), §8.2.

### OD-7H-10 — Replay lineage — **decided: A (lineage quota and root window)**

1. **Conflict.** The frozen function accepts a replay as a parent; the frozen quota is per delivery; each replay restarts retention (CNF-7H-15).
2. **Why an owner choice.** Any family-wide limit is tenant-visible and narrows what the frozen route accepts.
3. **Alternatives.** A: keep the per-delivery quota and eligibility; add a per-lineage quota and a lineage window. B: only originals are replayable. C: no family rule; document the consequence.
4. **Security / privacy.** A and B bound both traffic and payload lifetime. C bounds neither.
5. **Reliability.** A needs a lock that every replay of a lineage shares.
6. **Cost.** A and B need a migration.
7. **Preferred.** A.
8. **Approved.** A, with the owner's constraint on the window: at most 10 replays per lineage per 24 hours, enforced transactionally, retaining the frozen per-delivery quota; the lineage window follows the existing 6J retention of the **root** (30 days for a `DELIVERED` root, 90 days for a `DEAD_LETTER` root); a descendant can neither extend the root's replay eligibility nor retain the original body indefinitely; the quota must be concurrency-safe. Applied in §13.5, §13.5.1 (LIN-01 … LIN-07), §20.2; MR-7H-08; ERR-7H-01, ERR-7H-06.

### OD-7H-11 — Plugin rate-limit store unavailable — **decided: A (fail closed)**

1. **Missing requirement.** 6J §25.3 requires the limit and names Redis; nothing says what happens when Redis cannot be consulted (CNF-7H-16). The first version of this document imposed fail-closed without authority; that is corrected here by an actual decision.
2. **Why an owner choice.** It trades workflow availability against abuse and capacity protection.
3. **Alternatives.** A: refuse callouts. B: a bounded per-process fallback limit. C: call without limiting.
4. **Security.** Only A guarantees a plugin is never called past its declared limit.
5. **Reliability.** Under A, plugin-dependent workflows and tools fail for the duration of a Redis outage; under B the cluster-wide limit is approximate; under C a plugin can be flooded.
6. **Cost / latency.** A is the simplest; a breaker keeps refusals immediate.
7. **Preferred.** A.
8. **Approved.** A, with the owner's conditions: a normalized retryable failure through the existing workflow / tool-result contract; never bypass the limit; bounded retries; failures recorded; no retry storm. Applied in §12.2 (PLG-15 … PLG-18); ERR-7H-08.

### OD-7H-12 — Configuration cutover — **decided: B (coherent revision and last-instant re-check)**

1. **Conflict.** 6J §21.3 calls a zero-grace rotation an "immediate hard cutover" and §21.1 says the worker checks the expiry "on every send". A sender that may not hold a database lock across HTTP cannot make a committed change effective at the instant bytes leave the host (CNF-7H-19). The earlier procedure also read references and destination in different transactions (P1-7H-R07).
2. **Why an owner choice.** It replaces "immediate" with a bounded guarantee and a stated residual.
3. **Alternatives.** A: one coherent revision read at admission; the 6 s admission bound is the only protection. B: the same, plus a re-check of the revision immediately before hand-off.
4. **Security.** In the residual a request may be signed with a secret that was just rotated out. It reveals nothing about the new secret. A receiver that has revoked the old one rejects the request and it is retried; a receiver that has not yet revoked it accepts it, which the sender cannot prevent. A destination change has the separate consequence that the body may reach the earlier destination. (This item originally said the residual "adds no capability to an attacker". That was an overstatement, corrected under Minor-7H-R05 without changing the decision; see SIG-16.)
5. **Reliability.** B costs one more database read per attempt and, after a change, a re-admission.
6. **Cost.** B needs a guarded re-check read; both need the revision (MR-7H-11).
7. **Preferred by the author.** A. **The owner chose B.**
8. **Approved.** B, with the owner's conditions: one coherent revision covering URL, timeout, both signing-secret references and the grace expiry; re-check immediately before network hand-off and no send with stale configuration; the 6 s admission deadline preserved; the residual race documented precisely, with **no claim that the approximately one-second exposure is a strict bound**; a controlled reconciliation of 6J's zero-grace wording without editing 6J; previous-secret validity checked at signing / hand-off; overlapping rotations unable to cause stale-secret emission. Applied in §9.4 (HTP-15, HTP-17), §10.1 (SIG-05 … SIG-09, SIG-14 … SIG-16), §10.1.1; MR-7H-11; ERR-7H-09.

### OD-7H-13 — Platform-side pre-send failures — **decided: A (spend one attempt)**

1. **Missing requirement.** 6J §22.3 – §22.4 classify receiver and network outcomes. Nothing says whether a claim that ends without any request, for a reason on the platform's side, spends an attempt (CNF-7H-20). OD-7H-05 concerns a released stale claim only and does not decide this.
2. **Why an owner choice.** It decides whether a tenant's retry budget can be consumed by platform degradation.
3. **Alternatives.** A: count, with a distinct category and send state. B: do not count; add a separate pre-send counter, limit and backoff.
4. **Security.** A leaves no loop for a delivery the platform cannot send.
5. **Reliability.** Under A a delivery can dead-letter after fewer real sends when the platform is degraded; the tenant can replay.
6. **Cost.** B needs an extra counter and schedule.
7. **Preferred.** A.
8. **Approved.** A, with the owner's conditions: `ADMISSION_EXPIRED` and `SECRET_UNAVAILABLE` count against `max_attempts` with send state `NOT_SENT`; the frozen schedule, bounded attempts, terminal `DEAD_LETTER` and authorized replay preserved; never classified as receiver-side failures; explicit observability, platform attribution and tenant-safe information; no outbound usage charge for a request never sent; configuration-revision mismatches reconciled without a further unapproved accounting policy (done by OD-7H-15). Applied in HTP-16, HTP-19, §13.3, COM-07; ERR-7H-10. `ENDPOINT_GONE` was first placed under this decision by the author; it now has its own explicit decision, OD-7H-18. `SECRET_UNAVAILABLE` for a required previous secret is OD-7H-17.

### OD-7H-14 — Lifetime of replayed body copies — **decided: A (7I decides, gated)**

1. **Point to settle.** OD-7H-10 fixed the root's replay eligibility at 30 / 90 days. Each replay row keeps its own frozen 30 / 90-day retention, so a body copy can exist up to 120 / 180 days after the root's creation. That figure was a consequence, and the earlier report presented it next to an owner approval it did not have.
2. **Why an owner choice.** It is a personal-data retention question.
3. **Alternatives.** A: state the consequence, assign the final rule to 7I, block replay activation until 7I decides. B: decide now that every copy is purged with its root.
4. **Privacy.** B is the tightest. A leaves the question open but cannot be skipped.
5. **Reliability.** B leaves a late replay little time and would cancel one still retrying at the deadline.
6. **Cost.** B needs a lineage-anchored purge and cancellation path.
7. **Preferred.** A.
8. **Approved.** A, with the owner's conditions: 7H documents the 120 / 180-day consequence without claiming owner approval of longer personal-data retention; the final retention, deletion, erasure and lineage-anchored purge belong to 7I; production replay activation stays blocked until that is formally resolved; the 30 / 90-day root eligibility is preserved; no frozen per-delivery retention is changed and no active replay is prematurely cancelled. Applied in LIN-04, §17.4, AB-7H-08, HE-7I-7H-08.

### OD-7H-15 — Configuration change between admission and hand-off — **decided: B (one uncounted re-admission)**

1. **Point to settle.** OD-7H-12's re-check can stop an attempt because the tenant changed the endpoint. That is neither a receiver failure nor a platform failure, so OD-7H-13 does not decide its accounting.
2. **Why an owner choice.** It is a retry-accounting policy.
3. **Alternatives.** A: close the claim as one failed attempt `CONFIG_CHANGED`. B: re-admit once under the same claim without spending an attempt; spend one only if the configuration changes again.
4. **Security.** Neither sends under a revision known to be outdated.
5. **Reliability.** B delivers sooner after an edit; it needs more than one admission identity per claim and a hard cap.
6. **Cost.** B adds the admission sequence to the history model.
7. **Preferred by the author.** A. **The owner chose B.**
8. **Approved.** B, with the owner's ten requirements: the abandoned admission recorded `CONFIG_CHANGED` / `NOT_SENT`; re-admission reloads a coherent revision; organization status, egress validation, secret validity, fencing and the final re-check are all repeated; each admission has a distinct durable identity and the attempt budget stays unambiguous; a further change after the one re-admission spends one failed attempt on the existing schedule; no unlimited loop and no indefinite lease reset; a crashed or stale claim remains under OD-7H-05; OD-7H-09, OD-7H-12 and OD-7H-13 preserved; no request under a revision known to be outdated; migration, invariants, failure injections and gates recorded. Applied in HTP-18, HTP-19, T-04a, DSM-07 H3 – H6, MR-7H-03, MR-7H-06, traces 27 and 28.

### OD-7H-16 — Dual signing at the grace boundary — **decided: B (keep the full grace)**

1. **Point to settle.** 6J §21.1 and §21.3 promise both signatures for the whole configured grace and none with the previous secret after it; the rotate-secret response publishes `previous_secret_expires_at`. The second remediation planned the previous signature only if the grace outlasted the 6 s admission window, so dual signing stopped up to 6 s early (CNF-7H-22). The third review held that the zero-grace residual of OD-7H-12 does not authorize shortening a positive grace.
2. **Why an owner choice.** One option changes a published promise to tenants.
3. **Alternatives.** A: keep the early cutoff as an explicit amendment of 6J. B: honour the full grace, proving validity on the database clock at the final re-check and delaying, never downgrading, a request that cannot be handed off before expiry.
4. **Security.** Neither signs knowingly with an expired secret. B has the non-atomic check-to-hand-off residual of SIG-17.
5. **Reliability.** A gives a grace of 6 s or less no dual-signed request at all and removes the last 6 s of every longer one. B can delay a boundary request by about one re-check, or end it `ADMISSION_EXPIRED`.
6. **Cost.** B adds a comparison in the worker and a possibly repeated re-check; no schema beyond MR-7H-03 and MR-7H-11.
7. **Preferred.** B (§10.1.2).
8. **Approved.** B, with the owner's nine conditions: configured graces of 1 s, 3 s, 6 s and 3600 s honoured without a blanket early cutoff; `previous_secret_expires_at` validated against the PostgreSQL clock at the final revision re-check; a previous signature only while that secret is valid at the governed signing / hand-off boundary; if expiry occurs before a safe hand-off, the previous signature is omitted and current-only signing applies after expiry; the 6 s admission ceiling and the last-instant re-check preserved; never knowingly sign with an expired previous secret; no send under an invalidated revision; the residual timing race documented without any claim of atomicity; the 6 s early cutoff withdrawn from ERR-7H-09 and every affected rule reconciled. Applied in §9.3, §9.4, SIG-06, SIG-07, SIG-17, §10.1.1 (case C), §10.1.2, traces 15 and 30; ERR-7H-09.

### OD-7H-17 — Required previous secret unavailable — **decided: A (do not send)**

1. **Missing requirement.** 6J requires dual signing during the grace and says nothing about a previous secret the secret manager cannot return (CNF-7H-22). The second remediation dropped the header and sent current-only, on the author's own authority.
2. **Why an owner choice.** It is tenant-visible retry behaviour, and a choice between a published promise and immediacy.
3. **Alternatives.** A: no request; one failed attempt `SECRET_UNAVAILABLE`. B: send current-only, recorded as degraded.
4. **Security.** A never emits a delivery that a receiver inside its promised grace must treat as badly signed.
5. **Reliability.** Under A a receiver already on the new secret also waits for the retry, and a long fault inside a long grace can exhaust a small `max_attempts`. Under B a receiver still on the old secret rejects the request anyway.
6. **Cost.** A needs no schema beyond a secret-role detail on the closure.
7. **Preferred.** A.
8. **Approved.** A, with the owner's conditions: `failure_reason = SECRET_UNAVAILABLE`, `send_state = NOT_SENT`, `failure_origin = PLATFORM`; exactly one failed attempt under OD-7H-13; the existing backoff and `max_attempts` ceiling; terminal `DEAD_LETTER` and authorized replay preserved; no HTTP request and no outbound usage charge; tenant-safe failure evidence and operational alerts; the header never silently omitted while dual signing is required; an unavailable previous secret distinguished from an expired one, for which current-only is correct; byte-identical HMAC input and the existing headers preserved. Applied in §9.4 steps 4 – 5, SIG-18, HTP-19, §13.3, SEC-7H-04, trace 30; ERR-7H-10.

### OD-7H-18 — Endpoint row hard-deleted — **decided: A (spend one attempt)**

1. **Point to settle.** A claim whose endpoint row no longer exists was counted as a failed attempt by the author's extension of OD-7H-13, not by a question put to the owner.
2. **Why an owner choice.** It is retry accounting, and it decides how such a delivery ends.
3. **Alternatives.** A: `ENDPOINT_GONE`, one attempt per claim, `DEAD_LETTER` by exhaustion. B: close the delivery `CANCELLED` at the first such admission.
4. **Security.** Neither sends anything.
5. **Reliability.** A spends up to `max_attempts` claims that cannot succeed, over the frozen schedule. B would add a direct `DELIVERING → CANCELLED` path, and `CANCELLED` is not replayable.
6. **Cost.** A needs nothing new.
7. **Preferred.** A.
8. **Approved.** A, with the owner's conditions: `failure_reason = ENDPOINT_GONE`, `send_state = NOT_SENT`, `failure_origin = PLATFORM`; one failed attempt per affected claim; the frozen schedule and `max_attempts` ceiling; `DEAD_LETTER` only through normal exhaustion; no new direct `DELIVERING → CANCELLED` transition; no HTTP and no outbound usage charge; fencing, history and tenant isolation preserved; applicable only when the row was actually hard-deleted by an authorized platform operation, never to a tenant's disable; no promise of a successful replay while the endpoint does not exist. Applied in §6.3, HTP-19, §13.3, §13.5, §14.3, trace 16; ERR-7H-01, ERR-7H-10.

### 22.2 Decisions deliberately **not** raised, and why

| Question | Why it is not an owner decision here |
|---|---|
| External delivery guarantee | Frozen: at-least-once (6J §22.1) |
| 4xx / 5xx / 429 / 3xx classification | Frozen (6J §22.4) |
| Signing-key selection and rotation | Frozen (6J §21.1, §21.3) |
| Subscription snapshot vs live re-evaluation | Frozen: fan-out-time snapshot, no historical matching (7F §28.11; 7G HE-7H-7G-02) |
| Historical-event redelivery | Frozen (6J §23.3) |
| Sensitive media in payloads | Frozen: never (6J §39, §40) |
| Endpoint verification | No contract requires it; none added |
| Commercial treatment | Frozen FUTURE (J4) |
| Topic source of the two call topics | Fixed by 4F §8.4; delegated to 7H by IO-7B-12 without an owner decision |
| `lead.created` source filter | Resolved by the authority order (CNF-7H-03) |
| DSR and retained bodies; cross-border destinations; `CANCELLED` retention | Deferred by frozen contract to 7I; 7H takes the non-destructive default |
| The additive schema of §17.3 | Logical requirements only; the governed migration itself needs owner approval when authored |

### 22.3 Controlled compatibility errata

7H edits no frozen document. Each erratum is narrow, follows from an owner decision or a DB-enforced fact, and is to be consolidated into its owning document by a later controlled pass (the same treatment D0 used for OD-D0-02).

| ID | Owning document | Erratum | Follows from |
|---|---|---|---|
| ERR-7H-01 | 6J §35.3; AEC row AMI-6J-028 | `422 WEBHOOK_REPLAY_NOT_ALLOWED` also applies when the delivery's endpoint no longer exists or is not `ACTIVE`, when its organization is not `ACTIVE`, and when the delivery's replay lineage window has closed. No new code, status or route | OD-7H-03, OD-7H-10, OD-7H-18 |
| ERR-7H-02 | AEC row AMI-6J-025; 6J §18.10 | `409 STATE_CONFLICT` (existing platform-wide code) is returned when the endpoint is not `ACTIVE` | OD-7H-06 |
| ERR-7H-03 | 6J §20.1 | The `request_id` note should read "the delivery's correlation ID, fixed at creation" | CNF-7H-01 |
| ERR-7H-04 | 5J §14.3 audit vocabulary (open TEXT) | Add the token for system cancellation of deliveries (proposed `WEBHOOK_DELIVERY_CANCELLED`) | OD-7H-02 |
| ERR-7H-05 | 6J §24.1, §24.4 | The adapter extracts a minimal normalized processing input from the verified bytes **before** the dedup insert, and that input commits with the receipt before the 2xx. Shape validation therefore precedes the acknowledgement; a shape-invalid payload is still recorded, as `FAILED`. Domain processing stays after the acknowledgement. 6J §40.4 (raw payload not retained) is unchanged | OD-7H-08 |
| ERR-7H-06 | 6J §23.3, §35.3, §45.2; AEC row AMI-6J-028 | `429 WEBHOOK_REPLAY_RATE_LIMITED` also applies at more than 10 replays per replay lineage per 24 hours. The per-delivery limit is unchanged. Both limits are enforced inside the replay function | OD-7H-10 |
| ERR-7H-07 | 6J §36.3 (audit snapshot allow-list); 6J §36.2 | The audit row of endpoint creation and of every change of the delivery configuration carries the new and previous `config_revision`, the changed attribute classes, and the keyed destination fingerprint(s) with key ID. No URL, path, query or secret-reference value is added. These rows are written in the mutating transaction, as 7D AUD-7D-01 already requires (the "Async" label of §36.2 is aligned by 7D IO-7D-16, not by 7H) | DST-05; P1-7H-R05 |
| ERR-7H-08 | 6J §25.3 | When the rate-limit store cannot be consulted, the callout is refused and returned as `INTEGRATION_OPERATION_FAILED` with `retryable = true`. No new code | OD-7H-11 |
| ERR-7H-09 | 6J §21.1, §21.3 | "Immediate hard cutover" for `grace_period_seconds = 0`, and "checks the expiry on every send", are to be read as: a rotation takes effect for every delivery attempt admitted or re-checked after the rotation commits; a request whose final re-check completed before that commit may still be sent under the earlier configuration, and is handed to the network no later than 6 seconds after the commit. For a positive grace, `X-Platform-Signature-Previous` is emitted on every request handed to the network before `previous_secret_expires_at`, the expiry being tested against the database clock at the final re-check; the grace is not shortened. The earlier clause of this erratum, that the header "stops being emitted up to 6 seconds before `previous_secret_expires_at`", is **withdrawn** (OD-7H-16). The final check and the physical hand-off are not atomic. No header, algorithm or signing input changes | OD-7H-12, OD-7H-16 |
| ERR-7H-10 | 6J §22.4 | The classification table gains the outcomes that end a claim without a request: `ADMISSION_EXPIRED`; `SECRET_UNAVAILABLE`, for the current secret or for a previous secret still inside its grace (the request is not sent current-only); `ENDPOINT_GONE`, for an endpoint row removed by a platform operation (all three platform side); and `CONFIG_CHANGED` after one uncounted re-admission (tenant configuration). Each spends one attempt and follows the same schedule; none is a receiver failure. The rule that only `max_attempts` exhaustion reaches `DEAD_LETTER` is unchanged | OD-7H-13, OD-7H-15, OD-7H-17, OD-7H-18 |

---

## 23. Deferred Obligations for 7I – 7L

Handoffs issued by 7H carry the infix `7H`.

### 23.1 To 7I (security, privacy, compliance)

| ID | 7I receives |
|---|---|
| HE-7I-7H-01 | Final roles, grants and ownership for the guarded functions of §17.3 (dispatcher, sweep and maintenance principals); confirmation that no cross-tenant function returns a body, URL or secret reference (TEN-7H-04); whether the frozen unfenced functions are revoked from the dispatcher role. |
| HE-7I-7H-02 | The rule for an erasure or legal-hold request that touches a retained `payload_json`, a claim, admission or closure record, or a held delivery (5I ODD-5I-04; 7A §25). Constraint from 7H: bodies are immutable and are never widened after creation. |
| HE-7I-7H-03 | Confirmation that no DNC / consent state must suppress any of the 19 topics, or the governed rule if one must. |
| HE-7I-7H-04 | Whether an `INDIA_ENTERPRISE` tenant's webhook or plugin destination may resolve outside the contracted region (RES-7H-02). |
| HE-7I-7H-05 | Retention of `CANCELLED` deliveries and of claim, admission and closure records beyond their delivery; until set, `CANCELLED` rows are not purged. |
| HE-7I-7H-06 | Field-level classification of the §5.3 baseline (7B IO-7B-07). 7I may narrow it before activation. Also: whether claim, admission and closure records are exposed on any tenant surface, and sanitization rules for the stored response preview. |
| HE-7I-7H-07 | The callback processing input (CBK-15 … CBK-20): field-level encryption mechanism and key custody; classification of each adapter's input schema; the diagnostic retention period after a `FAILED` receipt; confirmation that the organization erasure path deletes inputs; confirmation that no tenant or platform-admin surface reads them. |
| HE-7I-7H-08 | **Blocking for replay activation (AB-7H-08; OD-7H-14).** The final retention, deletion, erasure and lineage-anchored purge behaviour of replay copies. Inputs from 7H: eligibility ends with the root's 30 / 90-day window (LIN-03); the frozen per-row retention then allows a copy to exist up to 120 / 180 days from the root's creation (LIN-04); the owner has approved neither figure as a retention period. Constraints from the owner: do not silently change the frozen per-delivery retention; do not prematurely cancel an active replay delivery. |
| HE-7I-7H-09 | Custody, access control and rotation procedure of the destination-evidence key, and who may run a fingerprint verification (DST-03, DST-10, DST-11). |
| HE-7I-7H-10 | The failure-origin and category codes shown to tenants in `failure_reason` (HTP-14, HTP-19): confirmation that platform-side and configuration-side categories are tenant-safe; and the retention of abandonment records (AB). Also whether the secret role of a `SECRET_UNAVAILABLE` closure (CURRENT / PREVIOUS) may be shown to a tenant; until 7I decides, it is internal. |

### 23.2 To 7J (observability)

| ID | 7J receives |
|---|---|
| HE-7J-7H-01 | The semantic signal list of §19.3, the identifier table of §19.1 and the never-recorded list of §19.4. Names, labels and cardinality are 7J's; no signal may carry an organization label. |
| HE-7J-7H-02 | The alert conditions of §19.5 without thresholds, and the trace chain of §19.2. Added by the third remediation: an alert on any `SECRET_UNAVAILABLE` closure with role PREVIOUS, and visibility of admission lock waits on endpoint rows. |

### 23.3 To 7K (capacity, backpressure, topology)

7H correctness is independent of every value below.

| ID | 7K receives |
|---|---|
| HE-7K-7H-01 | The per-organization fairness mechanism and the per-endpoint in-flight cap (COM-04, COM-05). |
| HE-7K-7H-02 | Dispatcher and sweep worker counts, claim batch size, poll cadence, `T_claim_lease`, `T_attempt_max` (keeping `T_attempt_max < T_claim_lease` and both above the 30 s timeout ceiling), jitter fraction J ≤ 0.10, the dependency-gate probe. |
| HE-7K-7H-03 | Load shapes: contact-import and campaign bursts producing one delivery per contact per endpoint (CNF-7H-03); the release burst after a long suspension (TEN-7H-10); catch-up after a Redis or PostgreSQL outage. |
| HE-7K-7H-04 | Whether and how to implement endpoint auto-suspension (DEP-6J-07), as a later governed change. |
| HE-7K-7H-05 | Partition maintenance of `webhook_deliveries`; growth of deliveries, history records, fan-out claims, lineage anchors, processing inputs and inbound receipts; purge cadence and batch size. |
| HE-7K-7H-06 | Egress path topology, proxy placement, connection pooling and regional placement (§14.4), preserving validate-then-pin at the connecting hop. |
| HE-7K-7H-07 | `T_handoff` (the re-check-to-hand-off target, [REC] 1 s) and the cost of the additional per-attempt transactions (admission write, re-check read, occasional second admission). `T_admit` = 6 s is fixed by owner decision and is not 7K's to change. Added by the third remediation: the admission's lock timeout on the endpoint row (below `T_admit`); the mutation-side wait under overlapping admissions (ELK-06); the cost of repeated re-checks at a grace boundary; and any clock-rate safety margin of SIG-07, which may only delay a request and never shorten a grace. |

### 23.4 To 7L (final reconciliation)

| ID | 7L receives |
|---|---|
| HE-7L-7H-01 | CNF-7H-01 … CNF-7H-13 (§1.4). |
| HE-7L-7H-02 | ERR-7H-01 … ERR-7H-04 (§22.3) for consolidation. |
| HE-7L-7H-03 | The activation register of §17.5 and the migration requirements of §17.3 as the external-delivery go-live checklist, together with 7F IO-7F-20 / IO-7F-21 and the governed registry change for the two call topics. |
| HE-7L-7H-04 | Plugin items no frozen source specifies: the asynchronous result path for `webhook_callback_url`; whether an idempotency key is transmitted to plugins (CNF-7H-10). The rate-limit-store outage behaviour is no longer open: it is OD-7H-11 with ERR-7H-08. |
| HE-7L-7H-06 | The successor-topic rule of VER-7H-06a (CNF-7H-17): no `X.vN` may be made subscribable before the governed AX-E change chooses between one delivery per topic family and an amended receiver dedup rule. |
| HE-7L-7H-07 | CNF-7H-14 … CNF-7H-16 and errata ERR-7H-05 … ERR-7H-08, added by the remediation. |
| HE-7L-7H-08 | CNF-7H-18 … CNF-7H-21 and errata ERR-7H-07 (revised), ERR-7H-09, ERR-7H-10, added by the second remediation; and the dependency of AB-7H-02 on 7D IO-7D-16 (endpoint audit in the mutating transaction). |
| HE-7L-7H-09 | CNF-7H-22; errata ERR-7H-01, ERR-7H-09 and ERR-7H-10 as revised by the third remediation (the 6 s early-cutoff clause of ERR-7H-09 is withdrawn and must not be consolidated); owner decisions OD-7H-16 … OD-7H-18. |
| HE-7L-7H-05 | 7F HE-7H-7F-02 (per-provider meaning of "deleted" for recording objects) is not closed by 7H. |

### 23.5 Handoffs received and their disposition

| Received | From | Disposition |
|---|---|---|
| IO-7B-12 | 7B | **Closed**: CNF-7H-04; §5.2. Delivery still gated by AB-7H-03 |
| DEF-7C-06 (webhook part) | 7C | **Closed**: §5.3, §15. The WebSocket projection part is not 7H's (Class F is the realtime contract's) |
| PCI-13, 25, 28 | 7D | **Closed** (processing design): §11, CBK-09, CBK-10; schedule to 7K; MR-7H-09 |
| PCI-26 | 7D | **Closed**: T-02; no durable obligation |
| PCI-35 | 7D | **Closed**: DSM-06; §8 |
| HE-7H-7F-01 | 7F | **Closed**: §7 – §9, §13 |
| HE-7H-7F-02 | 7F | **Not closed**: HE-7L-7H-05 |
| HE-7H-7G-01 | 7G | **Closed**: §13.5, §13.6 |
| HE-7H-7G-02 | 7G | **Closed**: SUB-02, XRP-05 |
| 7A §18 deferral | 7A | Worker concurrency model (§8.3, COM-05) and jitter (XRT-05) defined; egress pool to 7K; endpoint-health policy dispositioned (XRT-10) |
| 7A T-08, T-09 | 7A | **Closed**: §11 (forged callback, callback replay) |

---

## 24. Adversarial Review Findings

### 24.1 Self-review findings (first version)

A written adversarial pass was made against the draft. Each item states a concrete exploit or failure, what the frozen schema or a naive design would do, and the correction now in the document. Severity is the severity the issue **would have had** uncorrected. "Status" is its status in this document.

| ID | Sev. | Exploit / failure path | Correction | Status |
|---|---|---|---|---|
| ADV-01 | P1 | **Dispatcher cannot read its own claims.** `fn_claim_delivery` returns bare UUIDs. The table is partitioned on `created_at` and RLS-forced; `app_worker` has no BYPASSRLS. A worker holding only an ID cannot SELECT the row without the organization, so every claimed row would sit in `DELIVERING` forever | MR-7H-02 returns identifiers including `organization_id`; activation blocked until then (AB-7H-02) | Resolved in design; **schema gap recorded** |
| ADV-02 | P1 | **Lost success under unfenced functions.** W1 stalls; D is released and re-claimed by W2; W1's late `fn_delivery_failed` matches `status = 'DELIVERING'` and clears W2's claim; W2's `fn_delivery_succeeded` then updates 0 rows silently. A delivered webhook is recorded as failed and re-sent | Fence on a per-delivery claim sequence (DSM-01); lease inequality (DSM-02); MR-7H-02, MR-7H-03 | Resolved in design |
| ADV-03 | P1 | **Unrecoverable `DELIVERING`.** A worker crash leaves the row claimed; no frozen function releases it and no role can find it across tenants | Stale-claim release sweep (T-08), counted (OD-7H-05) | Resolved in design |
| ADV-04 | P1 | **Duplicate tenant-visible webhooks on every redelivery or internal replay.** Without a dedup key each redelivery inserts a full row set (already 7F P1; restated because the bridge depends on it) | MR-7H-01; activation blocked | Resolved in design |
| ADV-05 | P1 | **Replay to a disabled endpoint, and the disable / replay race.** An application-level status check followed by the insert lets a concurrent disable slip between them | Guard inside the replay function with the endpoint row locked (MR-7H-08; OD-7H-03) | Resolved in design |
| ADV-06 | P1 | **Egress continues for a suspended organization**, and a check-then-send race around the suspension commit | First version: a status predicate in the claiming statement, which the independent review showed does not serialize against the status change (P1-7H-R02). Now: organization row share lock at the claim and at a final admission; uncounted release at admission; a 6 s residual window stated exactly (ADM-01 … ADM-09; OD-7H-09) | Resolved in design after remediation |
| ADV-07 | P1 | **Signed bytes differ from sent bytes** if the worker re-serializes JSON read from the row, or if an HTTP client re-encodes or compresses | Single immutable buffer for HMAC and body; no content encoding (HTP-05); test obligation IO-7H-03 | Resolved |
| ADV-08 | P1 | **Provider callback as tenant-event injection.** A valid signature for connection A with a payload naming organization B, or an unsigned request with an internal API key | Tenant only from platform state after verification; no credential substitution; no row on failure (CBK-01, CBK-03, CBK-08; SIG-10) | Resolved |
| ADV-09 | P1 | **Replay bypassing authorization.** An internal replay parameterized with a destination, or a platform operator redelivering another tenant's event | No replay path takes a destination; internal replay matches only the organization's own endpoints under its tenant context; cross-tenant replay does not exist (XRP-06; §14.3) | Resolved |
| ADV-10 | P1 | **Second fan-out after claim expiry.** A disaster replay of an event older than the claim's retention finds no claim and fans out again | The claim retention is the evidence horizon; beyond it 7G classifies `RECONCILIATION_REQUIRED` and the handler does not run (XRP-04) | Resolved |
| ADV-11 | P1 | **Plugin inherits tenant authority** by echoing or altering an organization identifier in its response | The platform never reads authority from a plugin response (PLG-05; SIG-12) | Resolved |
| ADV-12 | P1 | **SSRF by mixed DNS answers or rebinding.** A hostname returns one public and one private address; or resolves publicly at registration and privately at delivery | Reject if any address is blocked; resolve and pin per attempt; delivery-time block is a failed attempt with no request (§14.4) | Resolved |
| ADV-13 | P1 | **Credential leak through the URL.** `https://user:pass@host/` stored as `target_url`, then logged or converted into an `Authorization` header | Userinfo rejected; query string treated as secret; host-only logging (§14.4; LOG-7H-02) | Resolved |
| ADV-14 | P1 | **`Retry-After` used to pin a delivery** or to pull attempts forward | `min(step, max(jittered, retry_after))` (XRT-06) | Resolved |
| ADV-15 | Minor | **Stored content injection.** A receiver returns markup in its response; the preview is shown in a dashboard | Preview bounded at 512 characters and treated as untrusted; sanitization rule to 7I (HE-7I-7H-06) | Baseline set; detail deferred |
| ADV-16 | Minor | **Test route as an internal-network probe** using the response preview as an oracle | Same egress controls as any delivery; 10 per hour; preview bounded | Resolved |
| ADV-17 | Minor | **Reactivation flood.** Ninety days of held deliveries become due together and starve other tenants | Fairness and caps (COM-04, COM-05; TEN-7H-10); values to 7K | Constraint set; values deferred |
| ADV-18 | Minor | **Backlog retargeting.** A compromised `webhook:manage` principal edits the URL and receives pending deliveries | Accepted by OD-7H-01: the same principal can replay delivered history in any option. Mitigated by audit, egress validation and per-attempt destination evidence | Accepted by owner decision |
| ADV-19 | Minor | **Platform outage spends tenants' attempts.** A secret-manager outage after claim counts attempts | Pre-claim dependency gate (XRT-09); post-claim failures still count, keeping the work bound. The first version decided this on its own authority; it is now owner decision OD-7H-13 | Resolved by owner decision |
| ADV-20 | Minor | **Projection staleness.** Port-read fields show state at fan-out, which can be later than the event (for example an invoice already `PAID` inside `invoice.created`) | Stated as contract (PRJ-04); receivers that need current state read the API (6J §22.2) | Accepted, stated |
| ADV-21 | Minor | **Unmetered plugin callouts when Redis is down** | First version set fail-closed without authority (P1-7H-R06). Now an approved owner decision: OD-7H-11; PLG-15 … PLG-18; ERR-7H-08 | Resolved by owner decision |

Unbounded-work check: §20.2 lists every loop and its bound, separating the automatic budget from the manual one. No automatic retry is unbounded.

### 24.2 Independent review ledger

Three independent freeze-gate reviews have examined this document. The first version reported "Open P1: 0" and the first review found six. The first remediation reported them closed and the second review found one of those closures incomplete and one new P1. The second remediation reported them closed, and the third review found two further P1 in sections that remediation had rewritten. All three self-assessments were therefore wrong at the time they were made. The ledger records every independently identified finding, the evidence that it was real, and where it is closed. The reasoning for each P1 is in §26.

| ID | Review | Severity | Finding | Evidence that it was real | Closed by | Evidence of closure | Status |
|---|---|---|---|---|---|---|---|
| P1-7H-R01 | 1 | P1 | An acknowledged provider callback could be lost: nothing durable held its processing facts | `062_5I` `inbound_webhook_events` has no content column; raw payload not retained (5I ADR-5I-010) | OD-7H-08; CBK-04, CBK-10, CBK-15 … CBK-22; §11.2 – §11.4; MR-7H-09; ERR-7H-05; AB-7H-04 | §26.1; trace 23 | **CLOSED** (design); activation gated. Re-verified in review 2 and again here |
| P1-7H-R02 | 1 | P1 | The organization-status check was not serialized against suspension; "no HTTP after suspension" was unachievable as stated | `107_5B5` locks the organization row `FOR UPDATE`; the first version's claim took no organization lock | OD-7H-09; ADM-01 … ADM-09; T-04, T-04a, T-09; HTP-16; TEN-7H-07, TEN-7H-08; MR-7H-02, MR-7H-03 | §26.2; trace 17 | **CLOSED** (design); activation gated |
| P1-7H-R03 | 1 | P1 | Recursive replay multiplied the quota and extended retention; "200 requests per event" was false | `fn_replay_webhook_delivery` (`063_5I` L133 – L151, `101_5I1`) accepts any `DELIVERED` row as parent and holds no quota | OD-7H-10; LIN-01 … LIN-07; §13.5, §13.5.1; §20.2; MR-7H-07, MR-7H-08; ERR-7H-01, ERR-7H-06 | §26.3; trace 24 | **CLOSED** (design); activation gated. The body-lifetime consequence is dispositioned separately below |
| P1-7H-R04 | 1 | P1 | One attempt number could name two different claims | First version: attempt number = `attempt_count` before the attempt + 1, while T-09 left `attempt_count` unchanged | §3.1 (claim, admission and attempt identities, TRM-03); DSM-01, DSM-05, DSM-07; MR-7H-02, MR-7H-06 | §26.4 | **CLOSED** (design); activation gated. Extended, not reopened, by the admission identity of OD-7H-15 |
| P1-7H-R05 | 1 and 2 | P1 | (1) A scheme-host-port digest cannot identify the destination. (2) Attribution of an attempt to the configuration change compared times against an audit record 6J labels asynchronous | (1) Two URLs on one host had equal evidence. (2) First remediation's DST-05; `updated_at` is transaction start time (`001_5B` L75 – L83); 6J §36.2 | SUB-06; DST-01 … DST-11; HTP-15; MR-7H-06, MR-7H-10, MR-7H-11; ERR-7H-07; 7D AUD-7D-01 (CNF-7H-18) | §26.5; trace 25 with its six injections | **CLOSED** (design); activation gated |
| P1-7H-R06 | 1 | P1 | A fail-closed plugin rule was imposed without an owner decision | 6J §25.3 and §16.1 state the limit and nothing about an unavailable store | OD-7H-11; PLG-15 … PLG-18; ERR-7H-08 | §26.6; trace 26 | **CLOSED** by owner decision |
| P1-7H-R07 | 2 | P1 | Signing references and destination could come from different configuration generations; previous-secret grace was not proven at hand-off; zero-grace cutover was overstated | First remediation's §9.4 read references in transaction 2 and the destination in transaction 3; `fn_rotate_webhook_secret` (`101_5I1` L1245 – L1282) changes three columns atomically, with no revision | OD-7H-12, OD-7H-15; HTP-15, HTP-17, HTP-18; SIG-05 … SIG-09, SIG-14 … SIG-16; §10.1.1; MR-7H-03, MR-7H-06, MR-7H-11; ERR-7H-09 | §26.7; traces 27, 28; cases A – F | **CLOSED** (design), with a residual stated in SIG-15 and approved in OD-7H-12; activation gated |
| Minor-7H-R01 | 1 | Minor | Billing projection treated `currency` as a top-level internal field and left types open | 7C §18 `money` is one object; 7C EV-102, EV-103 | PRJ-08; billing rows and requiredness table in §5.3 | §5.3 | **CLOSED** |
| Minor-7H-R02 | 1 | Minor | Dual delivery to an endpoint subscribed to a topic and its successor defeats event-ID dedup | 6J §21.2 rule 4 | VER-7H-06, VER-7H-06a; CNF-7H-17; AB-7H-07; HE-7L-7H-06 | §15 | **CLOSED** as a recorded precondition for a future governed change |
| Minor-7H-R03 | 2 | Minor | The 200-request automatic bound was stated unconditionally | 6J §45.2: the endpoint limit is a product-configurable placeholder; `062_5I` has no constraint | §20.2 rewritten as 10 × N, 200 only under enforced limit; CNF-7H-21; IO-7H-17 | §20.2 | **CLOSED** |
| Policy-1 | 2 | Clarification | The 120 / 180-day body lifetime was reported beside an owner approval it did not have | First remediation's LIN-04 and report | OD-7H-14; LIN-04; §17.4; AB-7H-08; HE-7I-7H-08 | §13.5.1; §17.5 | **DISPOSITIONED**: delegated to 7I, replay activation gated |
| Policy-2 | 2 | Clarification | A missed admission window spent an attempt on the author's own authority | First remediation's HTP-16; OD-7H-05 does not cover it | OD-7H-13; HTP-16, HTP-19; ERR-7H-10 | §9.4; §13.3 | **DISPOSITIONED** by owner decision |
| P1-7H-R08 | 3 | P1 | Guarantee C1 (no admission on the old revision after a change commits) had no mechanism: the admission read the endpoint without a lock | Second remediation's TX-3a and MR-7H-03 ("one read of the endpoint row version"); `fn_rotate_webhook_secret` takes `FOR UPDATE` (`101_5I1` L1265 – L1268), with which a plain `READ COMMITTED` read does not conflict | ELK-01 … ELK-08 (§14.2.2); ADM-04; SIG-14; HTP-15; §9.4 step 3; TX-3a; MR-7H-03, MR-7H-08, MR-7H-11; IO-7H-20 | §26.8; trace 29; case I | **CLOSED** (design); activation gated |
| P1-7H-R09 | 3 | P1 | An unresolvable previous secret silently suppressed `X-Platform-Signature-Previous` inside an active grace; dual signing stopped up to 6 s before the published expiry without approval | Second remediation's §9.4 step 4 ("previous secret unavailable → `emit_previous := false`; continue") and SIG-06 (b); 6J §21.1 L811 – L818, §21.3 L833, ADR-6J-07 | OD-7H-16, OD-7H-17; §9.4 steps 3 – 7; SIG-06, SIG-07, SIG-17, SIG-18; §10.1.2; HTP-19; SEC-7H-04; §13.3; MR-7H-03, MR-7H-06; ERR-7H-09, ERR-7H-10; IO-7H-21 | §26.9; traces 15, 30; cases C, G, H | **CLOSED** (design) by owner decision, with the residual of SIG-17 stated; activation gated |
| Minor-7H-R04 | 3 | Minor | History was called append-only while an abandonment was described as recorded on the first admission | Second remediation's DSM-07 H3 / H7, HTP-18 and MR-7H-06 ("A … and, when abandoned, the abandonment") | A separate inserted abandonment event AB(d, k, 1); DSM-07 H3, H6, H7; T-04a; HTP-18; MR-7H-06; IO-7H-22 | §8.3; trace 28 | **CLOSED** |
| Minor-7H-R05 | 3 | Minor | SIG-16 and OD-7H-12 item 4 said the zero-grace residual gives an attacker nothing | Text of SIG-16 in the version reviewed third | SIG-16 rewritten; OD-7H-12 item 4 corrected; trace 27 step 4 | §10.1 | **CLOSED** |
| Policy-3 | 3 | Clarification | The `ENDPOINT_GONE` accounting rested on the author's extension of OD-7H-13 | OD-7H-13 item 8, last sentence, in the version reviewed third | OD-7H-18; §6.3; §13.3; §13.5; §14.3; ERR-7H-01, ERR-7H-10 | §22 | **DISPOSITIONED** by owner decision |
| Policy-4 | 3 | Clarification | The 6 s early end of dual signing was not an approved reduction of the grace | ERR-7H-09 in the version reviewed third | OD-7H-16; §10.1.2; ERR-7H-09 revised | §10.1.2 | **DISPOSITIONED** by owner decision: the early cutoff is withdrawn |

**Open P0: 0. Open P1: 0.** Every P1 of §24.1 and §24.2 is closed in the design. Closure in the design is not implementation: each depends on schema or code that does not exist, recorded as activation blockers in §17.5. P1-7H-R07 is closed with a residual race that the document states and the owner approved; it is not claimed away. P1-7H-R08 is closed by a lock, not by the re-check. P1-7H-R09 is closed with the residual of SIG-17, stated and approved in OD-7H-16. Open Minor: ADV-15, ADV-17 (deferred details with named owners) and the upstream notes CNF-7H-05, 07, 08, 12.

### 24.3 Regression check of the remediations

Each remediation was checked against the contracts it could have disturbed, and after the second, and again after the third, remediation every earlier closure was re-read against the changed sections. Static reasoning only.

| Contract or earlier closure | Could a remediation have changed it? | Result |
|---|---|---|
| OD-7H-01 (live destination) | The admission reads the URL live, as part of one revision, and records revision and fingerprint | Preserved (HTP-15, DST-06). The revision identifies a state; it does not pin a delivery (TRM-02) |
| OD-7H-02, OD-7H-09 (hold; 6 s bound) | Admission may now run twice per claim | Preserved: each admission takes the organization share lock and has its own 6 s timer; G1 – G6 of ADM-05 are unchanged |
| OD-7H-03, OD-7H-06 (reject replay / test to an inactive endpoint) | The replay function gained locks and quotas | Preserved; the endpoint check is still under a row lock |
| OD-7H-04 (backoff 9 – 10) | Not touched | Preserved |
| OD-7H-05 (released stale claim spends an attempt) | Re-admission adds a second admission per claim | Preserved: re-admission does not move `claimed_at`; every sweep closure spends an attempt (DSM-07 H5; HTP-18) |
| OD-7H-07 (minimal baseline) | Billing rows were made precise | Preserved; no field was added |
| OD-7H-08 (callback processing input); R01 | Not touched by the second remediation | Preserved: no acknowledged callback lacks its processing input (CBK-04) |
| OD-7H-10 (lineage quota and window); R03 | LIN-04 was reworded | Preserved: quotas and the 30 / 90-day eligibility unchanged; only the description of the body lifetime changed |
| OD-7H-11 (fail closed); R06 | Not touched | Preserved: no fail-open path (PLG-15) |
| R04 (claim and attempt identities) | An admission sequence was added | Preserved and extended: an attempt number is still issued only at closure; abandoned admissions carry none (DSM-07 H5) |
| R05 first part (full-destination fingerprint) | The fingerprint moved from "computed at admission" to "stored with the revision and copied at admission" | Preserved: same canonical form and key; the admission still commits it before sending |
| No worker can close another worker's claim | Fence unchanged | Preserved (DSM-01); re-admission uses the same `claim_seq` |
| No transaction across HTTP, Redis or the secret manager | Two short transactions were added (re-check; second admission) | Preserved: both commit before signing (§17.2). The endpoint share lock added by the third remediation lives only inside the admission transaction and is released before secret resolution (ELK-06) |
| Raw-body HMAC and dual-secret rotation | Key selection is by admitted revision; the previous-secret rule was changed twice | Signing input, headers and algorithm unchanged (SIG-01 … SIG-04). After the third remediation the emission rule equals 6J's: both signatures on every request handed off before the expiry, none with the previous secret after it (SIG-06). The earlier 6 s narrowing is withdrawn |
| Per-attempt SSRF validation of a changed URL | Re-admission introduces a new destination inside one claim | Preserved: the egress adapter resolves, validates and pins at every send, including after a re-admission (HTP-18; §14.4) |
| No credential or query string in destination evidence | The audit row now carries revision and fingerprint | Preserved (DST-03, DST-05) |
| 7F consumer acknowledgement and handler generations | Not touched | Preserved (INV-ACK; §16.3) |
| 7G bounded consumer retry and replay | Not touched | Preserved (XRT-01, XRT-02; §13.6) |
| Delivery status vocabulary | Admissions, re-admission and holding add no status | Preserved |
| The 19-topic catalog; successor-topic governance | Not touched by the second remediation | Preserved (VER-7H-06a) |
| Billing money projection (Minor-7H-R01) | Not touched | Preserved (PRJ-08) |
| India residency and sensitive-data boundaries | New column values: revision, fingerprint, key ID | Covered by RES-7H-01; none is a URL or secret |
| No new delivery for a disabled endpoint | Endpoint `status` is deliberately not part of the configuration revision | Preserved (SUB-01; §6.3): disabling does not abort or re-admit pending deliveries, which "complete normally" as 6J §18.8 requires |
| No platform-admin cross-tenant replay | Not touched | Preserved (§14.3) |
| No new route, public error code, event name, topic or signing header | Errata extend descriptions; categories are internal `failure_reason` codes | Preserved (§22.3) |
| R01 callback acknowledgement durability | The third remediation did not touch §11 | Preserved (CBK-04; trace 23) |
| R02 suspension concurrency; ADM-01 … ADM-09 | The admission now takes a third lock (endpoint, share) after the organization and delivery locks | Preserved: the organization lock is still first and still held to commit; G1 – G6 unchanged; the new lock adds no cycle (ELK-04) |
| R03 replay lineage and quotas | The replay's endpoint check is now specified as a share lock and refuses an absent endpoint | Preserved: lock order organization → anchor → parent → endpoint; both quotas still counted under the anchor lock |
| R04 claim / attempt / admission identity; OD-7H-15 | The abandonment became its own inserted record | Preserved: still at most two admissions and one uncounted re-admission per claim; attempt numbers still issued only at closure; uniqueness extended to AB |
| R05 destination audit correlation | The admission reads the revision under a lock | Preserved and strengthened: the recorded revision is the latest committed at the admission's commit (DST-06) |
| R06 plugin limiter fail-closed | Not touched | Preserved (PLG-15) |
| R07 coherent signing configuration | Step 3 became a locking read; steps 4 – 7 changed for the grace boundary | Preserved: all values still come from one row version (C3); secrets are still resolved after admission, by that revision's references |
| OD-7H-13 (pre-send failures spend an attempt) | `SECRET_UNAVAILABLE` now also covers a required previous secret; `ENDPOINT_GONE` moved to its own decision | Preserved; extended only by OD-7H-17 and OD-7H-18 |
| OD-7H-12 residual and the 6 s ceiling | Grace-boundary re-checks can repeat inside an admission | Preserved: `T_admit` still caps every hand-off; the revision re-check still precedes every signing |
| Minor-7H-R01 … R03 | Not touched | Preserved (PRJ-08; VER-7H-06a; §20.2) |
| 7I replay-retention gate (AB-7H-08); 7E / 7F registry prerequisite for the two call topics (AB-7H-03); schema activation prerequisites | Not touched, except that AB-7H-02 gained conditions | Preserved |

---

## 25. Freeze-Gate Evidence and Final Status

### 25.1 Validation performed

Every check is a **static architectural check**: comparison of this document against frozen text and SQL. The only executed commands were read-only repository commands (file listing, hashing, text search, `git status`). **No database, Redis, HTTP or application test was executed, and none is claimed.**

| # | Check | Result | Evidence |
|---:|---|---|---|
| 1 | 6J and 7A – 7G governing sections reread against the draft | Done | §1.2 |
| 2 | Every 7H guarantee compared with those documents | No 7H rule exceeds or weakens a frozen guarantee | Matrix A |
| 3 | Each transaction and acknowledgement boundary challenged | INV-ACK, INV-NOSPAN hold; three gaps found and recorded | §4.3; ADV-01 … 03 |
| 4 | Duplicate event and duplicate HTTP simulated | Rows: prevented by the claim. HTTP: possible, bounded, stated | Matrix E; traces 2 – 9 |
| 5 | Replay cannot bypass authorization | Holds | XRP-06; ADV-09 |
| 6 | Provider callbacks cannot inject tenant events | Holds | CBK-08; ADV-08 |
| 7 | Plugin callouts cannot inherit excess authority | Holds | PLG-02, PLG-05; ADV-11 |
| 8 | External payload minimization | Minimal baseline; exclusions listed per topic | §5.3; Matrix H |
| 9 | Recovery of every non-terminal delivery state | Holds once §17.3 exists; does not hold on the frozen schema alone | §8.5; §17.5 |
| 10 | Concurrency and uniqueness invariants | UQ-01 … UQ-05; fence | §7.2; §8.3 |
| 11 | Rollout and contract-generation compatibility | Six examples; 7F terms unextended | §16 |
| 12 | Destination URL restrictions | Frozen adapter plus three 7H clarifications | §14.4 |
| 13 | Unbounded work or retry | None | §20.2 |
| 14 | Public API and signature compatibility | No route, code, permission, header or scheme added; ten controlled errata | Matrix I; §22.3 |
| 15 | Producer / consumer coverage against Phase-6 readiness | 19 topics traced to producers; 17 bound to the group, 2 not | §5.2; Matrix I |
| 16 | No frozen source changed | Verified after authoring and again after remediation (§25.3) | §25.3 |
| 17 | Remediation of the nine independent P1 findings (six from the first review; one new and one re-opened in the second; two new in the third) and five Minor findings | Each re-derived from the frozen SQL and text; point-by-point analysis per P1 | §24.2, §26 |
| 18 | The remediations regress no approved decision, frozen contract or earlier closure | Checked contract by contract, after each remediation | §24.3 |
| 19 | Stale wording of superseded designs removed | Searched for the superseded terms (load-step references, single admission per claim, digest of scheme-host-port, correlation by audit time, unconditional 200, fence on `claimed_by` / `claimed_at`, the `T_admit` grace margin, the unlocked endpoint read, suppression of the previous-signature header, abandonment recorded on the admission) | §25.3 |
| 20 | Lock behaviour of every frozen endpoint mutator read from the SQL (`062_5I`, `063_5I`, `072_5J`, `101_5I1`, `107_5B5`, `109_5B7`) | Rotation: `FOR UPDATE` on the endpoint row only. Other mutations: plain `UPDATE` / `DELETE`. No delivery foreign key. The audit insert takes no lock. The organization functions lock only the organization row | §14.2.2; §26.8 |

### 25.2 Completion conditions

| Condition | Met? | Where |
|---|---|---|
| Authoritative source contracts reconciled | Yes | §1.3, §1.4, Matrix A |
| Webhook, internal-event, callback and plugin boundaries explicit | Yes | §4, §10.2 |
| Every essential delivery state has a recoverable definition | Yes, as designed; dependent on §17.3 | §8.5 |
| Duplicate internal processing and ambiguous external delivery addressed | Yes | §7, Matrix E, §18 |
| Internal and outbound signing and authentication separate | Yes | §10 |
| Tenant isolation and payload confidentiality preserved | Yes | §14, §5.3 |
| Durability and acknowledgement boundaries defined | Yes | §4.2, §4.3, §17.2 |
| Retry and replay compatible with 7G | Yes | §13 |
| Contract-generation compatibility preserved | Yes | §16.3 |
| No missing schema capability disguised as implemented | Yes | §17.1, §17.3, §17.5 |
| No owner decision silently unresolved | Yes: eighteen approved, none pending | §22 |
| Handoffs to 7I – 7L specific and traceable | Yes | §23 |
| Frozen documents and D0 unchanged | Yes | §25.3 |
| Open substantive P0 = 0 and P1 = 0 | Yes | §24 |

### 25.3 Repository integrity after authoring

Verified by read-only commands after the last edit of this document, including all three remediations: the working tree differs from `HEAD` (`bbb70d1`) only by this one new file; the LF-normalized SHA-256 of 7A – 7G equal §1.1; the migration folder holds 112 SQL files and no `113*`; no file under `backend/`, `infra/` or `.github/` changed.

### 25.4 What this document does not claim

- It does not claim that any component, function, table, index, role or check described here exists. All of them are designed only.
- It does not claim that any trace of §18 was run.
- It does not claim exactly-once delivery.
- It does not declare Phase 7H approved or frozen.

### 25.5 Final status

`PHASE 7H = READY FOR INDEPENDENT FREEZE-GATE RE-REVIEW`

---

## 26. Remediation of the First Independent Review

One subsection per P1 found by the three independent reviews (§26.1 – §26.6 first review; §26.5 extended and §26.7 added by the second; §26.8 and §26.9 added by the third). Each gives, in this order: (1) the failing interleaving or counterexample; (2) the frozen-source and physical-schema evidence; (3) the corrected invariant and rule; (4) transaction boundaries and authoritative state; (5) recovery after a crash at each boundary; (6) tenant isolation, authorization, privacy and audit; (7) the logical schema or implementation requirement; (8) the activation dependency; (9) a deterministic scenario for a future test; (10) why the failure can no longer occur. All of it is static reasoning. Nothing was executed.

### 26.1 P1-7H-R01 — durability after the callback acknowledgement

1. **Counterexample.** A provider posts a verified "call ended, 127 seconds" event. Ingress inserts the receipt and answers 2xx. The process is killed before the task is enqueued. The provider, holding its 2xx, never resends. The first version's CBK-10 said a sweep would "re-dispatch" the stale receipt, but the re-dispatched worker would hold only (`provider_slug`, `provider_event_id`, `event_type`). The duration and the call reference existed only in the dead process. The call is never closed, its capacity slot is never released and its minutes are never billed.
2. **Evidence.** `webhooks.inbound_webhook_events` (`062_5I` L38 – L57): `id, organization_id, provider_slug, provider_event_id, event_type, signature_header, signature_valid, raw_payload_ref, status, received_at, processed_at, failure_reason`. No column carries event content. `raw_payload_ref` is not populated by default (5I §10, ADR-5I-010; 6J §40.4). 6J §24.1 orders the pipeline "Fast ACK → INSERT → Normalize", and §24.4 places shape validation "after dedup-insert". 7D REC-04 nevertheless requires that recovery "processes the stored, already-verified record". By contrast `billing.payment_webhook_receipts` (`102_5H2` L949 – L1024) stores `normalized_event_kind`, `provider_transaction_id`, `settled_amount`, `settled_currency`, `event_occurred_at`, `provider_failure_code` and `payload_hash`, with the comment "raw payload itself never stored".
3. **Corrected rule.** A receipt that owes processing commits together with its processing input, before the 2xx (CBK-04, CBK-16). The enqueue is a hint (CBK-04). The input is minimal, normalized, verified, schema-closed and holds no raw payload (CBK-15).
4. **Boundaries and authority.** One transaction (TX-7), in the tenant context resolved after verification, inserts the receipt and its input. Its commit is the durability boundary; the 2xx follows it. The authoritative record of what is owed is the pair (receipt in `RECEIVED` or `PROCESSING`, processing input). Processing is one owner transaction (TX-8) that applies the command, writes any outbox row, sets the terminal receipt status and deletes the input.
5. **Crash analysis.** Before the TX-7 commit: nothing exists, no 2xx was sent, the provider retries, the dedup key makes the retry clean. After the commit and before the 2xx: the provider retries; the insert returns no row; the same 2xx is returned; the first input stands. After the 2xx and before any processing: the sweep finds the receipt and processing rebuilds the command from the stored input (trace 23). During processing, before the owner commit: the receipt stays `PROCESSING`, the sweep re-dispatches, the input is still present. After the owner commit: receipt terminal, input gone, nothing owed.
6. **Isolation, authorization, privacy, audit.** Verification and tenant resolution are unchanged and still precede every write (CBK-01, CBK-03). The input sits under forced RLS on the resolved organization, is read only by the owning context's worker in that tenant context, and is exposed on no tenant or platform-admin surface (CBK-19). It contains no raw payload, signature, secret or free text, and personal data only where the command needs it (CBK-15). It is encrypted at field level and deleted on completion and on erasure (CBK-18 … CBK-20). The receipt keeps a hash of the verified bytes as evidence (CBK-13).
7. **Requirement.** MR-7H-09: processing-input record, processing claim with attempt count, terminal transitions that delete the input, guarded stale-receipt discovery, erasure hook. Erratum ERR-7H-05 moves minimal extraction before the acknowledgement in 6J §24.
8. **Activation.** AB-7H-04: routes 6D-021 and 6J-014 do not serve production traffic before MR-7H-09 and ERR-7H-05. Billing's route is not affected.
9. **Test scenario.** Send a verified call-ended callback; assert 2xx; terminate the process with the task broker disconnected so that no message exists anywhere; start a fresh worker and the sweep; assert the session reaches its terminal state with the reported duration, exactly one `call.ended` outbox row exists with `causation_id` = the receipt, the receipt is `PROCESSED` and no processing input remains. Repeat with the kill placed after the processing claim.
10. **Why it is eliminated.** The facts needed to rebuild the command are committed before the provider is told the callback was accepted. From that commit until the transaction that completes the work, they exist in PostgreSQL and nowhere else is needed. No step depends on process memory or on a broker message.

**Differences between the three routes.** Billing already satisfies this by frozen design. Voice and generic integrations gain it through MR-7H-09. For Voice, recovery restores facts, not timeliness (CBK-22); a provider status query, where an adapter has one, remains an additional and independent source under 7D §35.5, and is not relied on because no adapter is assumed to have it (7D VCC-02).

### 26.2 P1-7H-R02 — organization suspension concurrency

1. **Failing interleavings.** (A) Dispatcher reads the organization as `ACTIVE` inside its claim; the suspension commits; the dispatcher commits its claim. The first version asserted the predicate being "in the same statement" prevented this. It does not: a `READ COMMITTED` read takes no lock on the organization row and does not conflict with the suspension. (B) A worker loads `ACTIVE`, closes its transaction, the suspension commits, the worker sends. No design that releases its locks before HTTP can prevent (B) entirely.
2. **Evidence.** `organization.fn_platform_suspend_organization` (`107_5B5`): `SELECT status … FROM organization.organizations WHERE id = p_organization_id FOR UPDATE`, then `UPDATE … SET status = 'SUSPENDED'`. The frozen `fn_claim_delivery` (`063_5I`) references no organization table. 6A §35 and 7A PR-06 forbid a transaction across external I/O.
3. **Corrected rule.** Every admission point share-locks the organization row and evaluates status under that lock (ADM-01). A second admission point, the final pre-send admission, is added (T-04a). A request may start only within 6 s of its admission (HTP-16). The guarantee is G1 – G6 of ADM-05, not an absolute.
4. **Boundaries and authority.** The authoritative state is the organization row's committed status. The claim transaction and the admission transaction each hold the share lock until they commit, then release it; neither is open during HTTP (ADM-07). The serialization point is the row lock that the frozen status functions already take.
5. **Crash analysis.** A dispatcher that dies holding the share lock: its transaction aborts, the lock is released, no claim or admission was committed. A worker that dies after admission: the claim expires and the sweep closes it as `UNCERTAIN` with one attempt spent; the row returns to `PENDING` and, the organization being suspended, is held. A status-changing transaction that dies: it rolls back, the status is unchanged, waiting admissions proceed against `ACTIVE`.
6. **Isolation, authorization, privacy, audit.** The lock is taken only inside guarded functions; the dispatcher role gains no privilege on the organization table (ADM-09). Suspension and reactivation keep their own audit rows; an attempt inside the residual window is identifiable from its admission and closure times against that audit row (TEN-7H-08).
7. **Requirement.** MR-7H-02 (claim with the organization share lock in the locking query), MR-7H-03 (admission function containing the uncounted release). The lock order and the no-wait rule are ADM-03, ADM-04.
8. **Activation.** AB-7H-02.
9. **Test scenario.** Two connections. (i) Connection S begins the suspension and stops after its `FOR UPDATE`; the dispatcher's claim runs and must return no row of that organization without waiting; S commits; a second claim returns none. (ii) The dispatcher claims first and stops before commit; S's `FOR UPDATE` must block; the dispatcher commits; S proceeds; the worker's admission then executes T-09 and nothing is sent. (iii) Admission commits, then S commits, with the worker's timer forced to 5 s and to 7 s: it sends in the first case and closes `ADMISSION_EXPIRED` in the second.
10. **Why it is eliminated.** Interleaving (A) requires the dispatcher to commit a decision made on `ACTIVE` after the suspension commits. With a share lock held from the status read to the commit, the suspension's lock request must wait for that commit, or, if it came first, the dispatcher's query skips or re-reads the row and sees the new status. Interleaving (B) is not eliminated and the document no longer says it is: it is bounded to requests admitted before the suspension and started within 6 s of admission, lasting at most 30 s, and the owner approved exactly that bound (OD-7H-09).

### 26.3 P1-7H-R03 — replay lineage amplification

1. **Counterexample.** Root R is `DELIVERED`. The tenant replays R ten times; each child is `DELIVERED` within seconds. Each child is then replayed ten times, and so on. After g generations there are 10^g deliveries, all within one day. On day 29 the newest descendant is replayed, and again 29 days later, keeping the original body alive without end. Two concurrent requests naming different children share no lock.
2. **Evidence.** `webhooks.fn_replay_webhook_delivery` (`063_5I` L133 – L151; re-issued in `101_5I1`): the only parent guard is `v_orig.status NOT IN ('DEAD_LETTER','DELIVERED')`; the only duplicate guard is an open replay with `replay_of_delivery_id = p_delivery_id`; it never reads the parent's own `replay_of_delivery_id`; it holds no count. 6J §23.3 defines the limit as "10 replays per delivery per 24 hours (application-layer quota)". Retention is per row by status (6J §22.6).
3. **Corrected rule.** LIN-01 … LIN-07: lineage root recorded on every replay; per-delivery and per-lineage quotas of 10 per 24 hours, both checked inside the replay transaction under the lineage anchor's lock; lineage window equal to the root's own retention; per-row purge never chained.
4. **Boundaries and authority.** One request transaction (TX-6). The authoritative state for the quotas is the set of replay rows of the lineage, read under the anchor lock. The authoritative state for the window is the root's creation time and terminal status held on the anchor.
5. **Crash analysis.** The replay is one transaction including its synchronous audit row: it either commits wholly or not at all. A retried request finds the open replay and returns it.
6. **Isolation, authorization, privacy, audit.** Unchanged authorization (`webhook:manage`, tenant-forgery guard). Every accepted replay has an audit row with its actor. Payload lifetime is bounded at 120 or 180 days from the root's creation (LIN-04). The lineage root is internal and exposes nothing new (LIN-06).
7. **Requirement.** MR-7H-08 (lineage fields, anchor, in-function quotas and window), MR-7H-07 (per-row purge). Errata ERR-7H-01 (extended), ERR-7H-06.
8. **Activation.** AB-7H-02: the replay route is not enabled without MR-7H-08.
9. **Test scenario.** Create a root and ten delivered replays. Issue, simultaneously, one replay request for each of two different children: both must be refused with 429. Advance the clock 24 hours: one is accepted. Advance to day 31 with a `DELIVERED` root: every replay in the lineage is refused with 422, including replays of a descendant created on day 30. Repeat with a `DEAD_LETTER` root and day 91.
10. **Why it is eliminated.** Every replay of a lineage must take the same row lock before it counts, so the lineage count cannot be raced, and it cannot exceed 10 per 24 hours whatever the shape of the tree. Because eligibility is tied to the root's creation time and not to any descendant, replaying a descendant cannot move the deadline. The frozen per-delivery quota is still enforced, now inside the same transaction.

**Budgets kept apart.** The automatic budget is `max_attempts` per delivery and is untouched. The manual budget is the replay quota. §20.2 now states both and no longer sums them into a false universal bound.

### 26.4 P1-7H-R04 — attempt and claim identity

1. **Counterexample.** `attempt_count` = 0. W1 claims; under the first version this is "attempt 1". The organization is suspended; T-09 releases without incrementing. W2 later claims and sends; this is also "attempt 1". Two different operations, by different workers, at different times, one of which sent nothing, share the identity (`delivery_id`, 1), and the first version's attempt-record uniqueness, patched with an undefined "outcome sequence", could not say which was which.
2. **Evidence.** First version §3.1: "`attempt_number` = `attempt_count` before the attempt + 1"; T-09: "`attempt_count` unchanged"; MR-7H-06: "Unique on (delivery, `attempt_number`, outcome sequence)". The frozen table has no claim counter: `claimed_by` and `claimed_at` are overwritten by each claim and cleared by each outcome (`063_5I`).
3. **Corrected rule.** Two identities (§3.1, TRM-03): a claim identity (`delivery_id`, `claim_seq`) for every claim, and an attempt identity (`delivery_id`, `attempt_number`) assigned at closure only when the budget is spent. Invariants DSM-07 H1 – H7. The fence is `claim_seq` (DSM-01).
4. **Boundaries and authority.** `claim_seq` and `attempt_count` are columns of the delivery row and change only under its row lock: `claim_seq` in the claim transaction, `attempt_count` in the closure transaction. History records are written in those same transactions, so the row and its history cannot disagree.
5. **Crash analysis.** Crash after the claim commits: C(d, k) exists and is open; the sweep closes it, with send state decided by whether A(d, k) exists. Crash after admission: A(d, k) exists; the sweep's closure is `UNCERTAIN`. Crash during a closure transaction: it rolls back; the claim stays open; the sweep closes it later. In every case each k ends with exactly one closure.
6. **Isolation, authorization, privacy, audit.** History records carry `organization_id` under forced RLS, are written only by guarded functions and are never updated (H7). They contain no body, URL or secret.
7. **Requirement.** MR-7H-02 (claim sequence), MR-7H-03 (fenced admission, closure, release), MR-7H-06 (records and uniqueness).
8. **Activation.** AB-7H-02.
9. **Test scenario.** The worked example of §8.3, asserting after each step the values of `claim_seq`, `attempt_count` and the exact set of records; then its crash variant. A property test asserts H1 – H7 after arbitrary interleavings.
10. **Why it is eliminated.** An attempt number is no longer predicted when a claim opens; it is issued when a claim closes and only if the budget is spent. A claim that sends nothing and spends nothing receives none. OD-7H-05 holds because every sweep closure spends the budget and so receives a number; OD-7H-02 holds because T-09 spends nothing and receives none.

### 26.5 P1-7H-R05 — effective-destination evidence and audit correlation

Closed in two steps. The first remediation fixed the fingerprint. The second review found that correlation with the configuration change still rested on comparing times. Both are stated here.

1. **Counterexamples.** (a) *Digest too coarse.* An endpoint's URL changes from `https://hooks.example/in?token=A` to `https://hooks.example/other?token=B`. A scheme-host-port digest is identical before and after. (b) *Correlation by time.* The first remediation's DST-05 attributed an attempt to "the audit row with the same fingerprint and the greatest time not after the admission". The tenant changes A → B; the change commits; the audit record is written later; an attempt is admitted under B before the audit row exists. At that moment no audit row for B precedes the admission, so the rule finds nothing or, after an A → B → A sequence, the wrong row. The rule also had no defined meaning for "time": the endpoint's `updated_at` is the mutating transaction's start time, not its commit.
2. **Evidence.** First version SUB-06: "a digest of the scheme-host-port actually contacted". `webhook_endpoints` (`062_5I`, `101_5I1`) keeps only the current `target_url`; `trg_we_updated_at` calls `set_updated_at()`, which sets `NEW.updated_at = NOW()` (`001_5B` L75 – L83), the transaction start time. No version or revision column exists (6J §18.4, §34; ADR-6A-08). 6J §36.2 lists `WEBHOOK_ENDPOINT_CREATED` and `WEBHOOK_ENDPOINT_UPDATED` as "Async". 7D §36 (OD-7D-02 = A; AUD-7D-01, AUD-7D-02, AUD-7D-07) requires every mandatory audit record, the `AUDIT_ASYNC` routes included, to be written inside the originating business transaction, and records the documentation alignment as IO-7D-16.
3. **Revised invariants.** DST-01 … DST-11. In short: (i) every configuration state has the identity (`endpoint_id`, `config_revision`), assigned in the mutating transaction under the row lock; (ii) the fingerprint of a destination is stored on the row with the revision that introduced it; (iii) the audit row of a change is written in that same transaction and carries the revision; (iv) every admission records the revision and fingerprint it read; (v) attribution is the equality of (`endpoint_id`, `config_revision`), never a comparison of times.
4. **Transactions and locks.** Mutation transaction: `UPDATE` of the endpoint (row lock), revision + 1, fingerprint and key ID when the URL changes, and the audit insert; one commit, which is the configuration change's durable commit point. Admission transaction: one read of the committed endpoint row version and the insert of the admission record. A reader can only see a revision whose transaction, and therefore whose audit row, has committed.
5. **Crash and concurrency.** Crash before the mutation commits: no revision, no audit, no change. Crash after: both exist. Two concurrent `PATCH` requests: `If-Match` and the row lock admit one at a time; each gets its own revision. Duplicate or out-of-order audit materialization, if an implementation produced it, is harmless (DST-08). An implementation that separated the audit from the mutation would be exposed to the loss AUD-04a names; it is non-conformant and gated.
6. **Privacy, isolation, authorization.** No URL, path or query enters an audit row or a history record (DST-03, DST-05). Fingerprints are keyed and bound to organization and endpoint. History records and audit rows keep their existing tenant scoping. Recomputing a fingerprint for a candidate URL is a separate audited capability (DST-11).
7. **Dependencies.** MR-7H-11 (revision, stored fingerprint, the refusal of a URL change without one), MR-7H-06 (admission record), MR-7H-10 (key); ERR-7H-07 (audit snapshot content); 7D IO-7D-16 (same-transaction audit for these routes). Activation: AB-7H-02.
8. **Test scenarios.** Trace 25 with each injection. Assert: after A → B with the audit write artificially delayed, the attempt's admission names revision 2 and is attributed to the revision-2 audit row once present; after A → B → A the third state has revision 3 and its own audit row although its fingerprint equals revision 1's; killing the process between the `UPDATE` and the audit insert leaves neither; a `PATCH` of `target_url` without a fingerprint is refused; after an evidence-key rotation each admission's fingerprint still equals its revision's.
9. **Why it closes the defect.** The link between an attempt and the change that authorized its destination is now an identifier created inside the change itself and copied into the attempt's evidence before sending. It does not depend on when anything was written or read. Delayed, duplicated or reordered audit rows cannot alter it, and A → B → A is three distinct revisions.

### 26.6 P1-7H-R06 — plugin rate-limit store outage

1. **Defect.** The first version's trace 10 required fail-closed and tagged it as a 7H rule. No frozen contract says so, and no owner had decided it.
2. **Evidence.** 6J §25.3: the limit is "enforced platform-side, before the HTTP callout, via a Redis token bucket". 6J §16.1 row 4 and 4F §9.3 restate it. None of them, nor 6A §20 or §21, states what happens when the bucket cannot be read.
3. **Corrected rule.** OD-7H-11, approved: PLG-15 … PLG-18.
4. **Boundaries and authority.** The decision to call is made by the executor from the limiter's answer. No answer means no call. The durable record of a refusal is the `plugin_executions` row, written outside any transaction that spans I/O.
5. **Crash analysis.** A crash before the limiter answers: nothing was sent and nothing is owed. A crash after a refusal is recorded: the row stands. The breaker is process-local state; a restarted process starts closed and re-learns the outage within its bounded re-asks.
6. **Isolation, authorization, privacy, audit.** The refusal is per (organization, plugin) call and reveals nothing of other tenants. Evidence is per callout in the execution row; breaker transitions are operational events (PLG-18).
7. **Requirement.** Implementation only (IO-7H-16). Erratum ERR-7H-08.
8. **Activation.** AB-7H-06.
9. **Test scenario.** Trace 26: with the limiter unreachable, assert zero requests reach the plugin, the result is the normalized retryable failure, one execution row per invocation exists with the category, the limiter is contacted at most three times before the breaker opens and not at all while it is open.
10. **Why it is closed.** The behaviour is no longer an assumption of this document. It is an owner decision with its availability cost stated: plugin-dependent workflows and tools fail for the duration of a Redis outage, by choice.

### 26.7 P1-7H-R07 — coherent signing configuration and rotation safety (second review)

1. **Counterexamples.** The first remediation's procedure read the signing references in transaction 2, resolved secrets, and read the destination in transaction 3. **A.** The worker reads S1; the tenant rotates to S2 with zero grace; the worker is admitted and sends signed with S1, although nothing in its admission was stale. **B.** The worker reads the references and starts resolving; the tenant changes the URL and rotates; the worker is admitted with the new URL and signs with the old secret: a request that corresponds to no configuration the tenant ever had. **C.** The worker sees the previous secret as valid, resolution is slow, the grace expires, and the worker still emits `X-Platform-Signature-Previous`. **D.** After S1 → S2 → S3, a worker holding references from the first generation emits S1.
2. **Evidence.** `fn_rotate_webhook_secret` (`101_5I1` L1245 – L1282) updates `signing_secret_ref`, `previous_signing_secret_ref` and `previous_secret_expires_at` in one statement under `FOR UPDATE`; with `p_grace_period_seconds = 0` it sets both previous columns to NULL. `PATCH` is an ordinary `UPDATE` (6J §18.5). 6J §21.1: "the delivery worker checks the expiry on every send"; §21.3: `0` "disables the grace window entirely — immediate hard cutover". The frozen row has no revision. 6A §35 forbids a transaction across the HTTP call or the secret-manager call.
3. **Revised invariants.** HTP-15 (one coherent generation, read once at admission; secrets resolved afterwards by that generation's references); HTP-17 (re-check of the revision immediately before signing); HTP-18 (at most one uncounted re-admission); SIG-05 … SIG-09 and SIG-14 … SIG-16 (key selection by admitted generation; previous-secret conditions; guarantees C1 – C4 and the stated residual).
4. **Transactions and locks.** Admission: one guarded transaction that share-locks the organization, reads one endpoint row version and writes the admission record. Secret resolution: no transaction. Re-check: one read-only transaction. Signing and sending: no transaction, no lock. The rotation and the `PATCH` each take the endpoint row lock for their own short transaction and increment the revision there.
5. **Crash and concurrency.** A worker that dies at any point after an admission leaves an open claim; the sweep closes it under OD-7H-05, with send state `UNCERTAIN` toward the latest admission's destination. A rotation that rolls back leaves the revision unchanged and the re-check passes. Concurrent rotation and `PATCH` are serialized by the row lock into two revisions.
6. **Privacy, isolation, authorization.** Only a principal with `webhook:manage` can create a revision; each revision has an audit row in the same transaction. The worker handles references and secret values only in memory. No secret, reference value or URL enters a history record.
7. **Dependencies.** MR-7H-11 (`config_revision`); MR-7H-03 (admission returns the coherent generation; guarded re-check; re-admission); MR-7H-06 (per-admission identity). Erratum ERR-7H-09. Activation: AB-7H-02.
8. **Test scenarios.** Trace 27 (three sub-cases) and trace 28. Case B: pause the worker after admission, apply a URL change and a rotation, resume: assert no request reaches either URL signed with the old secret, and the request after re-admission carries the new URL with the new secret. Case C: set the grace to end 3 s after admission: assert no previous-secret header; set it to end 10 s after and delay secret resolution by 7 s: assert nothing is sent (`ADMISSION_EXPIRED`). Case D: two rotations between admission and re-check: assert S1 is never emitted.
9. **Why it closes the defect, and what remains.** Cases B and D required values from two different row versions; the worker now has values from exactly one, identified by a revision, and resolves secrets only after it knows which references that revision names. Case C required a previous-secret signature after expiry; the signature is planned only if the grace outlasts the latest instant at which this admission can hand off, measured on the database clock. Case A is reduced, not eliminated: a worker that re-checks after the rotation never sends with S1, and a request under the old revision is never handed off more than 6 s after the rotation; but a rotation that commits after the re-check returned and before hand-off is not seen. That residual is stated in SIG-15, approved as OD-7H-12, and reconciled with 6J's wording by ERR-7H-09. The document does not claim an instantaneous cutover, and does not claim the re-check-to-hand-off interval as a guaranteed bound.

### 26.8 P1-7H-R08 — admission versus endpoint mutation (third review)

1. **Failing interleaving.** The endpoint is at revision r. (i) The admission share-locks the organization and reads the endpoint with a plain read: r. (ii) `fn_rotate_webhook_secret` (or a `PATCH`) takes the row lock, writes r+1 and commits at `t_x`; nothing made it wait. (iii) The admission inserts A = (r) and commits after `t_x`. SIG-14 C1 said this could not happen. C4's derivation ("it was admitted before `t_x`") therefore had no basis either: the request was bounded only by 6 s from an admission that was already stale when it committed.
2. **Evidence.** `101_5I1` L1265 – L1280: `SELECT … FOR UPDATE` on the endpoint row, then `UPDATE`; no organization lock. `062_5I` L34, L36: `UPDATE` for `app_api` and `app_worker`, `DELETE` for `app_platform_admin` only; `109_5B7` Part G narrows `webhook_deliveries` only. `063_5I`: no foreign key from deliveries to endpoints. `072_5J`: the audit insert function takes no lock. `107_5B5` L369 – L371, L429 – L431: the organization functions lock the organization row only. The version reviewed third: TX-3a "one read of the endpoint row version"; MR-7H-03 (a) "reads one endpoint row version"; no lock named.
3. **Corrected invariant.** For every endpoint mutation committing at `t_x` and every admission of a delivery of that endpoint: the admission either commits before `t_x`, or records the post-mutation revision (or `ENDPOINT_GONE` after a delete). ELK-01, ELK-02; C1 of SIG-14.
4. **Locks, transactions, commit boundaries.** Admission transaction, `READ COMMITTED`: organization `FOR SHARE` → delivery row lock and fence → endpoint `FOR SHARE` (one statement, which also returns the values) → inserts → commit, which releases everything. Mutation transaction: endpoint row lock → revision + 1 → audit insert → commit. The two row locks conflict, so the two transactions are totally ordered at the endpoint row. Nothing is held across secret resolution or HTTP (ELK-06). A weaker "read-linearization" guarantee (the admission's revision was current at some instant during the admission) was considered and rejected: it is what the plain read already gave, it does not support C4, and the strict form costs one row lock inside a transaction that already exists, with no owner-facing behaviour change.
5. **Crash recovery.** A worker or connection that dies holding the share lock: the transaction aborts, the lock is released, no admission exists; the sweep closes the claim `CLAIM_EXPIRED`, `NOT_SENT`. A mutator that dies holding its lock: it rolls back, the revision is unchanged, and a waiting admission reads r, which is still current. A mutator that stalls: the admission's lock timeout fires, nothing is inserted, `ADMISSION_EXPIRED`.
6. **Tenant isolation and credentials.** The lock is taken inside the guarded function, by endpoint ID and organization ID, under the delivery's tenant context (ELK-08). No privilege is added to the dispatcher role. No secret is read in the transaction; references are returned as before and resolved after the commit.
7. **Requirements.** MR-7H-03 (a): the locking read, the isolation level, the lock order, no write to the endpoint. MR-7H-08: the replay and test endpoint check as a share lock. MR-7H-11 (d). Implementation: ELK-05 (the `last_delivery_at` touch outside the closure transaction; the lock timeout). No new column or table.
8. **Tests.** IO-7H-20 (i) – (vi); trace 29; case I.
9. **Why it is closed without the re-check.** The failing interleaving needs step (ii) to complete between the admission's read and its commit. The read is now the statement that holds a lock the mutation must wait for, so (ii) cannot complete in that interval; and if the mutation holds its lock first, the read waits and returns the new version. C1 holds for every admission by lock conflict alone. The re-check remains what it was: a second, independent narrowing for changes that commit **after** an admission, with its own approved residual (SIG-15). Deadlock freedom is ELK-04: endpoint locks are last in the global order and their holders acquire no further row lock.

### 26.9 P1-7H-R09 — previous signing secret during the grace (third review)

1. **Failing interleavings.** (a) Rotation S1 → S2 with a 3600 s grace. Ten minutes later an attempt is admitted; the secret manager returns S2 and fails for S1; the version reviewed third set `emit_previous := false` and sent with S2 only. A receiver still deployed with S1, 50 minutes inside the deadline the rotate-secret response gave it, rejects the delivery. (b) Grace 3 s (or 1 s, or 6 s): `e > admitted_at + 6 s` is false for every admission under the new revision, so no request is ever dual-signed. Grace 3600 s: every request admitted in the last 6 s goes current-only before e.
2. **Evidence.** 6J §21.1 (L811 – L818): two signatures while "`NOW() < previous_secret_expires_at`"; the header is "present ONLY during an active grace window"; an expired previous secret "is never signed with". 6J §21.3 (L833): "for `grace_period_seconds` following rotation … the platform genuinely signs every outbound delivery with **both** secrets". ADR-6J-07: the defect it closed was a grace that provided "no actual grace at all". 6J §64 tests 29 – 32. `101_5I1` L1275 – L1277: the expiry is `NOW() + grace` on the database clock. The version reviewed third: §9.4 step 4; SIG-06 (b), (d); ERR-7H-09's "up to 6 seconds before".
3. **Corrected invariants.** SIG-06: both signatures on every request handed off before e. SIG-07: the proof, on the database clock and elapsed time. SIG-18: four situations; a required but unavailable previous secret is a `NOT_SENT` failed attempt. SIG-17: the residual.
4. **Locks, transactions, commit boundaries.** No lock is added for this finding. The admission (TX-3a) returns e as part of the coherent revision and plans the signature if `e > db_now()`. Secret resolution holds no transaction. The re-check (TX-3b) returns the database time; `rem = e − db_now()` decides between "expired" and "still required". The hand-off guard compares the local hand-off timer with `rem`. Nothing is open during signing or HTTP.
5. **Crash recovery.** A worker that dies at any point after admission leaves an open claim, closed by the sweep under OD-7H-05. Nothing about the grace is persisted that a successor must honour: the next claim reads the row again. A worker that dies before sending because the previous secret was missing has sent nothing; the sweep records `UNCERTAIN` only because an admission exists, which over-states, and never under-states, what may have been sent.
6. **Tenant isolation and credentials.** Secrets are resolved by the references of the admitted revision of the delivery's own endpoint (SEC-7H-02) and exist in memory only. An unavailable secret is never replaced by a value held under another reference (SIG-09). The closure records a category, an origin and a secret **role**, never a reference or a value. The tenant sees `SECRET_UNAVAILABLE`; exposure of the role is 7I's (HE-7I-7H-10).
7. **Requirements.** MR-7H-03 (a): the planning rule `e > db_now()`, and the expiry returned. MR-7H-06: the secret role on X. SEC-7H-04: no purge of a previous secret before its expiry. ERR-7H-09 revised (early cutoff withdrawn); ERR-7H-10 revised. An operational alert through HE-7J-7H-02. No new column on the endpoint.
8. **Tests.** IO-7H-21; trace 30; cases C, G, H; the 6J §64 dual-signature fixture for byte identity.
9. **Why it is closed, and how it fits the 6J retry semantics.** The suppression path no longer exists: step 4 cannot clear the previous signature, and step 5 has exactly three outcomes for a planned previous signature (expired → current-only; required and missing → no send; required and present → both). The early cutoff no longer exists: the only quantity compared with the expiry is the database clock, at the re-check, with a hand-off guard that delays rather than downgrades. `SECRET_UNAVAILABLE` is not one of the receiver or network outcomes of 6J §22.4. It is a platform-side non-send under OD-7H-13 and OD-7H-17: it spends one attempt, uses the frozen schedule and reaches `DEAD_LETTER` only by exhaustion, so XRT-07 and the 6J rule that only exhaustion dead-letters are intact (ERR-7H-10). XRT-09 keeps a known secret-manager outage from spending attempts at all, by not claiming. The closure does not lean on the revision re-check of HTP-17, which concerns configuration changes: this finding is closed by the planning rule, the `rem` test and the no-send rule. What remains is SIG-17, stated and approved in OD-7H-16.

---

## Appendix A — ADR Register

| ID | Decision | Basis | Consequence |
|---|---|---|---|
| ADR-7H-01 | The bridge from internal events to webhooks is the frozen CON-10 consumer plus a separate dispatcher; no new service | 7A OWN-03; 7F §28.11 | Two workers, one context |
| ADR-7H-02 | The durable delivery row is the work source; a queue message is only a latency hint | 7A CEL-08 … CEL-10; 7D PCI-35 | Dispatch survives loss of any message |
| ADR-7H-03 | A delivery is bound to an endpoint resource; destination attributes are read at attempt time | OD-7H-01 | No snapshot columns |
| ADR-7H-04 | "Held" is a derived condition of `PENDING`, not a new status | OD-7H-02; `chk_wd_status` | No vocabulary change |
| ADR-7H-05 | One attempt budget; every release of an ambiguous claim spends it | OD-7H-05; 6J §22.3 | Strictly bounded work |
| ADR-7H-06 | Outcome writes are fenced by a per-delivery claim sequence | ADV-02; P1-7H-R04 | One new column; new functions |
| ADR-7H-15 | A claim and an attempt are different identities; an attempt number is issued at closure, only when the budget is spent | P1-7H-R04; OD-7H-02, OD-7H-05 | A claim that sent nothing has no attempt identity |
| ADR-7H-16 | Organization status is synchronized through a share lock on the organization row at every admission point, with a final admission before each send | P1-7H-R02; OD-7H-09; `107_5B5` | Bounded 6 s residual window; no lock across HTTP |
| ADR-7H-17 | Destination evidence is a keyed fingerprint of the complete canonical destination, committed before the send | P1-7H-R05; OD-7H-01 | Path and query stay confidential; edits are attributable |
| ADR-7H-18 | A callback receipt commits with a minimal normalized processing input; the enqueue is only a hint | P1-7H-R01; OD-7H-08; `102_5H2` precedent | Extraction precedes the 2xx; raw payload still not retained |
| ADR-7H-19 | Replay is limited per lineage as well as per delivery, inside the replay transaction, and the lineage window is the root's own retention | P1-7H-R03; OD-7H-10 | A lineage anchor record; manual and automatic budgets stated separately |
| ADR-7H-20 | A plugin is never called when its rate limiter cannot be consulted | P1-7H-R06; OD-7H-11 | Plugin-dependent work fails during a limiter outage |
| ADR-7H-21 | An attempt uses one coherent endpoint configuration revision, read once at admission and re-checked immediately before signing; secrets are resolved after admission by that revision's references | P1-7H-R07; OD-7H-12 | A future `config_revision`; a stated residual for a change that commits after the re-check |
| ADR-7H-22 | Attribution of an attempt to a configuration change is by revision identity, never by timestamps; the audit of a change is in the change's transaction | P1-7H-R05; 7D OD-7D-02 | Delayed, duplicated or reordered audit cannot break attribution |
| ADR-7H-23 | A claim that sends nothing spends one attempt, except the organization hold and one re-admission after a configuration change | OD-7H-13, OD-7H-15 | One budget; no pre-send loop; at most two admissions per claim |
| ADR-7H-24 | The lifetime of replayed body copies is a stated consequence handed to 7I, and replay activation waits for 7I's decision | OD-7H-14 | A privacy decision cannot be skipped by activating the route |
| ADR-7H-25 | The admission reads the endpoint under a share lock held to its commit; endpoint locks come last in the global lock order | P1-7H-R08; `101_5I1` `fn_rotate_webhook_secret` | C1 holds by lock conflict; a mutation may wait for admissions in progress |
| ADR-7H-26 | The configured grace is honoured in full: previous-secret validity is decided on the database clock at the final re-check, and a boundary request is delayed, never downgraded | P1-7H-R09; OD-7H-16; 6J §21.1, §21.3 | No early cutoff; a non-atomic residual at hand-off (SIG-17) |
| ADR-7H-27 | A request is never sent current-only while a previous secret is still required; an unresolvable required secret is a `NOT_SENT` failed attempt | P1-7H-R09; OD-7H-17 | Deliveries wait for the retry during a secret-manager fault inside a grace |
| ADR-7H-28 | Abandonment of an admission is its own inserted history record; no history record is ever updated | Minor-7H-R04; OD-7H-15 | One more record kind (AB) |
| ADR-7H-29 | A hard-deleted endpoint costs one failed attempt per claim and ends by exhaustion; there is no direct cancellation | OD-7H-18 | No new transition; replay refused while the endpoint is absent |
| ADR-7H-07 | The public body is rendered once at fan-out and never again | `fn_wd_identity_immutable`; 6J §21.1 | Signed bytes equal sent bytes; `request_id` fixed |
| ADR-7H-08 | Public fields absent from the internal payload come from owner read ports at fan-out and are nullable | 6K §45.1; 6J §40.2; 7A EVT-04 | Fan-out-time semantics, stated |
| ADR-7H-09 | The V1 public projection is minimal and only grows additively | OD-7H-07; AVS CM-WH-01 | Narrowing never needed |
| ADR-7H-10 | Cross-tenant runtime work happens only through guarded functions that return identifiers | TEN-7H-04; `101_5I1` function classes | No BYPASSRLS runtime role |
| ADR-7H-11 | No plugin event notification in V1 | NOT FOUND in frozen sources | Plugins are reached only by callouts |
| ADR-7H-12 | 7G's consumer retry model is never applied to HTTP delivery | 7G §9, §44 | Two independent failure stores |
| ADR-7H-13 | External delivery has no ordering guarantee and no component may add one | 6J §22.2 | No head-of-line blocking |
| ADR-7H-14 | The topic map is part of build capability, never of the active obligation | 7F REG-7F-04, HCG-01 | Deploying code never changes what is owed |
