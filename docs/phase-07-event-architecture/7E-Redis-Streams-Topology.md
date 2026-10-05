# Phase 7E — Redis Streams Topology — AI Voice Agent Platform

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | `docs/phase-07-event-architecture/7E-Redis-Streams-Topology.md` |
| Phase | 7 — Event Architecture |
| Sub-phase | 7E — Redis Streams Topology (transport topology for the durable A/B/C relay path and the Class-D SIGNAL path) |
| Status | **READY FOR INDEPENDENT FREEZE-GATE REVIEW.** This document does not declare itself approved or frozen; freezing is an independent-review act. |
| Date | 2026-10-05 (authored; owner-decision checkpoint); 2026-10-05 (completed after OD-7E-01 … OD-7E-03 were decided) |
| Owner decisions | OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B — all DECIDED by the owner and RESOLVED (§50). Open owner decisions: **0** |
| Remediation | Independent freeze-gate review of the version with LF SHA-256 `876e2749ca397ed84c953ffaf8ea156781aafc815d886f635e93546564c1cb02` / 1762 lines found P0 = 0 and three P1 freeze blockers plus minor issues: P1-7E-07 (NULL `aggregate_id` partition-0 fallback), P1-7E-08 (connected-replica count did not prove total replica topology), P1-7E-09 (local Claude settings with credential-like content in the review package), Minor-7E-09 (retained-memory wording) and Minor-7E-10 (normalized-versus-raw evidence wording). All were remediated in place (§55.2); owner decisions unchanged. A second independent freeze-gate review of the version with LF SHA-256 `5ef1c6fb93055ddf5b083d43a200288490512f398953e112a23172c7b565c6f9` / 1837 lines confirmed P1-7E-07 … P1-7E-09 resolved and found P1-7E-10 (sole-replica membership did not prove automatic-failover eligibility: `cluster-replica-no-failover` / `nofailover` unchecked) and Minor-7E-11 (CRLF working copies in the review package); both remediated in place, owner decisions unchanged. A third independent freeze-gate review of the version with LF SHA-256 `cc1781783086fc0687c7a206656a2b23ba2d023262b77d287e0cd43f8286ef42` / 1852 lines confirmed P1-7E-07, P1-7E-08 and P1-7E-10 resolved and found P1-7E-11 (`noeviction` was enforced only on current primaries, not on the failover replica); remediated in place, owner decisions unchanged. |
| Repository baseline | `main` @ `ca5b51b` ("7D phase freeze"), working tree clean at start |
| Frozen upstream | 7A, 7B, 7C, 7D (hashes in §6); Phase-6 documents; Phase-5 migrations `001_5B` … `112_5H5` |
| Preserved owner decisions | OD-7B-01, OD-7B-02, OD-7C-01 … OD-7C-07, OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B (not reopened) |
| Closes on completion | 7A DD-04, DD-05 (7E part), DD-06, DD-07, DD-08 (7E part), DD-15 (stream placement); 7B IO-7B-08 (7E states the actual per-stream guarantee; the 7B per-aggregate wording needs a controlled reconciliation, CNF-7E-10); 7D HO-7E-01 … HO-7E-07, IO-7D-22 |
| Does not begin | 7F, 7G, 7H, 7I, 7J, 7K, 7L |
| Artifact rule | This is the only new project artifact for 7E. No migration (no migration 113), no application code, no Redis configuration file, no Helm values, no manifest file, no edit to any frozen document (3F, 5A, 7A – 7D and Phase 6 included). Scratch validators run outside the repository. |
| Normative keywords | **MUST**, **MUST NOT**, **SHOULD**, **MAY** carry RFC 2119 meaning. Every rule has a stable ID. |

---

## 2. Purpose

7D froze the relay and the transport port (`DurableEventTransportPublisher`, TPT-01 … TPT-11) and made `CONFIRMED` conditional on a durable-acceptance mechanism that 7E alone defines (TPT-02, HO-7E-03, ADR-7D-19). 7A deferred stream names and count, sharding, retention, consumer-group layout, memory sizing boundaries and Class-D stream placement to 7E (DD-04 … DD-08, DD-15). 7B deferred per-stream ordering guarantees to 7E (IO-7B-08).

7E makes the Redis Streams transport implementation-deterministic: stream families and keys, the exact route of every one of the 107 durable V1 pairs and the 4 SIGNAL V1 pairs, the stream entry layout, the durable-acceptance criterion, the transport fault model, cluster redirect handling, the per-entry outcome classification, the non-claiming health probe, consumer-group topology and bootstrap, pending-entry mechanics, the ordering contract, safe group-aware trimming, group retirement, topology-generation evolution and the handoffs to 7F, 7G, 7I, 7J and 7K.

## 3. Scope

- Redis deployment role for event transport, eviction and persistence requirements, and the production topology the transport relies on.
- Transport fault model (normal versus outside-normal faults).
- Durable acceptance (`CONFIRMED`) and per-entry outcome classification for the 7D port.
- Stream families, stream namespace, partition and hash-tag strategy, route function and route registry.
- Durable versus SIGNAL separation and Class-D stream placement.
- Stream entry encoding and message size.
- Consumer-group model, current group registry, bootstrap, pending-entry (PEL) mechanics and reclaim capability.
- Per-stream ordering semantics.
- Durable retention (safe-trim watermark), groupless retention, SIGNAL retention, key TTL rules, group retirement, stream lifecycle and topology generations.
- Cluster cross-slot consumption pattern, memory-pressure behaviour, tenancy, security, residency and Voice hot-path boundaries for the transport.
- Failure matrix, handoffs, ADRs, owner decisions, implementation obligations, deferred items, conflicts and findings.

## 4. Non-Goals

| Non-goal | Owner |
|---|---|
| Consumer processing transaction, consumer idempotency, dedup ledger / inbox decision, business-key guards, handler execution order, ack-after-side-effect contract, consumer read loop | 7F |
| Consumer retry counts and delays, delivery-count policy, poison threshold, DLQ / parking, terminal publisher `FAILED` disposition, operator replay and replay tooling, the exact PEL idle threshold | 7G |
| Public webhook delivery topology | 7H |
| Field-level privacy / security classification, payload redaction, DLQ data classification, final operator permission model | 7I |
| Metric names, SLOs, alert thresholds, cardinality budget, dashboards | 7J |
| Capacity figures, partition-count sizing values, memory sizing values, autoscaling thresholds, catch-up sizing, regional failover, backpressure capacity, disaster recovery | 7K |

7E also does not: create any migration; change the outbox, the relay functions, the relay loop or any 7D rule; change any 7C envelope, schema or manifest binding; change the 7B taxonomy, producers or consumers; invent a consumer, a handler or a Class-D payload; claim exactly-once delivery; introduce a global sequence or global ordering; make Redis authoritative; route audio or media through Redis Streams; or modify any frozen document.

---

## 5. Authority Model

Authority is **concern-specific**. There is no "latest document wins" ranking. Conflicts are recorded in §54; a conflict that materially affects durability, delivery correctness, tenant isolation, cost, deployment topology, recovery or production operability, with several valid options, becomes an owner decision (§50) and is not silently resolved.

| Source | Authoritative for (in 7E) | Not authoritative for |
|---|---|---|
| Executed Phase-5 migrations `001_5B` … `112_5H5` | Physical PostgreSQL truth (outbox columns, the payload size CHECK, relay functions) | Redis topology |
| 3F (Deployment Internals) | The inherited Redis deployment baseline: Redis 7.2 image, production Redis Cluster, minimum 3 primaries + 3 replicas, automatic failover, the `{tenant_id}` hash-tag convention, AOF `everysec` + RDB, memory / eviction table | Event-transport durability semantics (7D / 7E); event taxonomy; the event-transport deployment, its eviction policy and its key partitioning, which are governed by the owner-approved exceptions OD-7E-01 = A and OD-7E-03 = B (3F is not edited) |
| 5A | Data-authority rules: Redis is a non-authoritative hot tier; AOF is best-effort and not relied upon for correctness; residency profile mapping | Stream topology |
| 7A (frozen) | Event-architecture invariants: RS-01 … RS-07, DUR, DEL, ORD, SOT, RES, VOX, FM, the DD ownership split | Physical topology choices |
| 7B (frozen) | 105 durable events, their classes, producers, current consumers (CON-01 … CON-11), Class-D catalogue DS-01 … DS-19, PAY-D-01 / PAY-D-02, CR-01 … CR-05 | Envelope names; stream topology |
| 7C (frozen) | Durable and SIGNAL envelopes, 107 exact durable V1 pairs, 4 exact SIGNAL V1 pairs, no wildcard routing (CSR-09, TDF-01 … TDF-06), tenant scope (TEN-C01 … TEN-C06), `event_id` semantics (ID-01 … ID-10) | Transport topology |
| 7D (frozen) | Relay mechanics; the transport port TPT-01 … TPT-11; outcome classes; availability gate; durable-confirmation requirement; Class-D publisher boundary CLD-01 … CLD-11; HO-7E-01 … HO-7E-07 | Redis topology, persistence, replication, confirmation technique (all delegated to 7E) |
| 6A – 6M | Domain and API semantics | Transport topology |
| AIR / FAR / AMI / AAM / AEC / AVS | Their exact reconciliation / indexing concerns only | Transport topology |
| Owner decisions | Only their approved scope | Anything outside it |

Rules of application:

1. **AUTH-7E-01.** A question is answered by its concern's owning source.
2. **AUTH-7E-02.** 7E binds only what 7A, 7B and 7D delegate to it (DD-04 … DD-08, DD-15, IO-7B-08, HO-7E-01 … HO-7E-07, IO-7D-22). 7E never contradicts 7A, 7B, 7C or 7D.
3. **AUTH-7E-03.** Where 3F's inherited Redis baseline and a frozen Phase-7 obligation cannot both hold, and several valid resolutions remain, 7E raises an owner decision. 7E raised OD-7E-01 … OD-7E-03, stopped, and resumed only after the owner decided them (§50). Each decision governs only its approved scope (the event-transport deployment, its acceptance mechanism and its partitioning); it does not redesign unrelated 3F key spaces (CNF-7E-15).

---

## 6. Frozen Baseline

Verified at the start of this work and re-verified before and after completion and after the independent freeze-gate remediation, against the repository, not against chat memory. **Hashes are SHA-256 of the LF-normalized content.** The "Observed" column records LF-normalized content/hash matches; it is not a raw-byte claim (see the line-ending row).

| Item | Expected | Observed | Lines | Result |
|---|---|---|---:|---|
| 7A `7A-Event-Architecture-and-Standards.md` | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` | same | 1086 | PASS |
| 7B `7B-Event-Taxonomy-and-Ownership.md` | `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` | same | 2207 | PASS |
| 7C `7C-Event-Envelope-and-Schema-Versioning.md` | `e514e3c4a889775fbc8e9baba3a9ad0558b5228465f240f425d7c762f1d200a0` | same | 3275 | PASS |
| 7D `7D-Transactional-Outbox-Architecture.md` | `2714a3eec6eb7c95be50c3b11c2e80c66f3f93a413ebcecfa46c5c79bf9e4de5` | same | 1572 | PASS |
| SQL migrations | 112 (`001_5B.sql` … `112_5H5.sql`) | 112 | — | PASS |
| Alembic revisions | 112 | 112 | — | PASS |
| Alembic root / head | `001_5B` / sole head `112_5H5` | same (walked: 1 root, 1 head, 0 missing parents, 0 branch points) | — | PASS |
| Migration 113 | absent | absent | — | PASS |
| Phase-6 frozen artifacts (6A – 6M, AAM, AEC, AMI, AVS, FAR, AIR, certificate) | the 20 hashes and line counts registered in 7B §1.1 | all 20 match | — | PASS |
| PostgreSQL baseline | PostgreSQL 18 | PostgreSQL 18 (7A §6.6, 7D §6) | — | PASS |
| 7F | must not exist | absent | — | PASS |
| `docs/phase-07-event-architecture/` before 7E | 7A, 7B, 7C, 7D only | 7A, 7B, 7C, 7D only | — | PASS |
| Git working tree at start | clean | clean | — | PASS |
| Git working tree at completion | only this 7E file new; nothing modified; no commit | same (`git status --short --untracked-files=all` and `git ls-files --others --exclude-standard` both list only this file) | — | PASS |
| Working-copy line endings of frozen files | evidence wording only | the Windows working copies of 7A, 7B and 7C are checked out with CRLF (`core.autocrlf=true`), so their **raw** working-copy bytes and raw hashes differ from the canonical LF content; their **LF-normalized content/hash matches the frozen baseline** and the LF blobs at `HEAD`. 7D's working copy is LF and matches raw and normalized. 7E does not edit frozen files to change their line endings | — | PASS (LF-normalized) |
| Independent-review package | product files only | built from a clean clone of `HEAD` plus this file; contains no `.claude/` directory, no `.env*`, no credential, key or local-settings file, no validator or scratch file (§56.3) | — | PASS |

Counts carried unchanged from 7C §20.8 and 7D MAN-01: **105** semantic durable bindings (A = 71, B = 1, C = 33); **107** exact durable V1 pairs (104 singletons + 3 EV-014 members); **4** exact SIGNAL V1 pairs; **111** exact V1 pairs in total; **0** V2 pairs. 7B §11 / §32.1: **31** CURRENT_CONSUMED and **74** CURRENT_NO_CONSUMER durable events. 7B §15: **19** semantic Class-D signals, of which **4** exact SIGNAL V1 pairs are bound (PAY-D-01: 1; PAY-D-02: 3).

---

## 7. Upstream Handoffs Closed by 7E

| Handoff | Source obligation | Where 7E answers it | State |
|---|---|---|---|
| 7A DD-04 | Stream names and count; per-type vs per-context layout | §14, §15, §18, §19 | CLOSED: 11 durable family streams + 1 SIGNAL stream at V1 `P_f = 1`; exact key grammar §15.4 |
| 7A DD-05 (7E part) | Sharding, partition keys, cluster topology | §12, §16 | CLOSED: dedicated event-transport cluster (OD-7E-01 = A); `aggregate_id` partitioning with CRC-32 (OD-7E-03 = B); capacity values to 7K |
| 7A DD-06 | MAXLEN / TTL / stream retention | §34 – §37 | CLOSED (mechanism); numeric values routed to 7K |
| 7A DD-07 | Consumer-group names and layout | §28, §29 | CLOSED: 11 durable groups + 1 SIGNAL group; 18 + 1 Redis group placements at V1 |
| 7A DD-08 (7E part) | Autoscaling / memory sizing boundary | §41, §49.5 | CLOSED (safety properties and benchmark list); numbers to 7K |
| 7A DD-15 (stream part) | Class-D stream placement | §17, §19, §36, §43 | CLOSED |
| 7B IO-7B-08 | Per-stream ordering guarantees | §33 | CLOSED for 7E (append order per key only); the 7B per-aggregate wording requires a controlled 7B reconciliation (CNF-7E-10, IO-7E-25) — recorded, not hidden |
| 7D HO-7E-01 | Accept immutable envelope bytes + read-only routing attributes; define routing, names, groups, retention, sharding, sizing without changing 7D semantics | §18 – §22, §28 – §39 | CLOSED |
| 7D HO-7E-02 | Implement `DurableEventTransportPublisher` with per-entry outcomes and a non-claiming probe | §23 – §26 | CLOSED |
| 7D HO-7E-03 | Durable-acceptance mechanism (mandatory; no residual-loss option) | §10, §11, §23 | CLOSED: `XADD` + same-connection `WAITAOF 1 1 <bounded timeout>` (OD-7E-02 = A) |
| 7D HO-7E-04 | Error-classification table, default-to-non-terminal | §25 | CLOSED |
| 7D HO-7E-05 | Accept any entry up to the outbox payload bound | §22 | CLOSED |
| 7D HO-7E-06 | Exact-type route function over 107 pairs; distinct SIGNAL routes | §18 – §20 | CLOSED |
| 7D HO-7E-07 | Redis never authoritative; relay holds no DB transaction during I/O | §9 | CLOSED |
| 7D IO-7D-22 | Stream-router integration: route function, classification table, durable acceptance | §18 – §25 | CLOSED (design); implementation is IO-7E-03 … IO-7E-11 |

---

## 8. Existing Redis Source Facts

Recorded as found. 7E changes none of them.

| ID | Fact | Source |
|---|---|---|
| SRC-01 | Redis image `redis:7.2-alpine` in the local and test compose files; 5A states "Redis 7+ Cluster" | 3F L234, L345; 5A L22 |
| SRC-02 | Production uses Redis Cluster (native sharding + replication), deployed by the Helm chart `infra/helm/redis/values.yaml` with `architecture: cluster` | 3F §16.1 L1221 – L1231 |
| SRC-03 | Minimum production topology: 3 primary shards, 3 replicas (1 per primary), automatic hash-slot assignment, automatic failover ("replica promoted on primary failure in < 30s") | 3F §16.1 L1223 – L1229 |
| SRC-04 | All keys defined in 3B §16, 3C §10 and 3E §16 use `{tenant_id}` as the hash tag; "This is a design constraint that must be honoured when any new Redis key is introduced"; the 3A §6.3 wrapper constructs keys with `{tenant_id}` as the first `{}` segment | 3F §16.2 L1235 – L1243 |
| SRC-05 | Memory table assigns per-key-space eviction policies: sessions `allkeys-lru`, RBAC / API-key cache `volatile-lru`, queue keys and retry queue `noeviction`; an 80 % memory alert | 3F §16.3 L1245 – L1254 |
| SRC-06 | Persistence: AOF with `appendfsync everysec`, plus a `BGSAVE` RDB snapshot every 15 minutes, on a PersistentVolume; daily S3 copy of the RDB snapshot | 3F §11.2 L1007 – L1011 |
| SRC-07 | "Redis is a cache and session store — a Redis restore from backup is almost never the right recovery path"; the DR table lists Redis cluster failure as "Acceptable loss — Redis is a cache, not a source of truth" | 3F §11.2 L1011; §10.1 L968 |
| SRC-08 | Redis is used for cache, queues (Celery broker), sessions, distributed locks and WebSocket presence | 2A L201; 3F §5 compose; 3F L1011 |
| SRC-09 | Redis is a hot tier, never authoritative; "AOF … is enabled for best-effort durability but is not relied upon for correctness. Recovery rebuilds from Postgres" | 5A L26, §18, §24.2 L1458 |
| SRC-10 | Redis keys follow `{purpose}:{organization_id_or_global}:{...}`; 5A §18.2 calls its namespace catalogue "complete"; 3A §6.3 enforces purpose prefixes including `stream:` | 5A §18.2 L1112 – L1114, L281; 3A L538 |
| SRC-11 | For `INDIA_ENTERPRISE`, "Database and Redis are also provisioned in the same region" | 5A §19.4 L1195, §25.1 |
| SRC-12 | Redis exporter alerts on memory > 80 % and on `redis_cluster_state != 1` | 3F §17.1 L1270 – L1271 |
| SRC-13 | Multi-region: active-passive at launch; region 2 diagram shows "Redis Replica — cold standby" | 3F §12.1 L1041 |
| SRC-14 | TLS 1.2+ for all connections to PostgreSQL, Redis and S3 | 5A L1530 |
| SRC-15 | 3A `eventbus/publisher.py` (outbox + Streams publish) and `consumer.py` ("Redis Streams consumer-group base") | 3A L318 – L319, L533 |

---

## 9. Redis Roles and Authority

| ID | Rule |
|---|---|
| ROLE-01 | Redis Streams is transport only for durable A/B/C events and for the 4 bound SIGNAL pairs (7A RS-01). It is never the record of a publication obligation, of a business fact, of consumer progress as business state, or of any retention obligation (RS-02, SOT-02, TPT-10). |
| ROLE-02 | `audit.domain_event_outbox` remains the authoritative publication obligation (SOT-01). A durable entry's presence in a stream never makes an outbox row deletable or "published"; only `fn_mark_outbox_published` after a `CONFIRMED` outcome does (7D DSP-01, CLN-05). |
| ROLE-03 | 7E's durable-acceptance mechanism (§23) makes a **transport handover** safe within the declared fault model (§11). It does **not** make Redis authoritative: recovery from faults outside the declared model reads PostgreSQL (retained `PUBLISHED` rows, 7D CLN-08; owner state), never a Redis backup (RS-02; 5A §24.2). |
| ROLE-04 | No component reads a stream, a stream entry ID, a consumer-group position or a PEL to decide whether an outbox row was published, whether a business fact exists, or whether a consumer side effect happened (TPT-10, RS-02). |
| ROLE-05 | Redis RDB snapshots and their S3 copies (SRC-06) are not an event-recovery source and are never replayed into streams as a recovery mechanism. |
| ROLE-06 | 7E requires no PostgreSQL transaction to be open during any Redis I/O (HO-7E-07, 7D LOOP-01). The adapter never reads or writes PostgreSQL. |

---

## 10. Redis 7.2 Mechanism Facts — What Each Primitive Proves

The acceptance design depends on exactly what each Redis primitive guarantees. 7E states only what the primitive proves and claims nothing stronger. The baseline version is Redis 7.2 (SRC-01).

| ID | Primitive | What it proves | What it does **not** prove |
|---|---|---|---|
| MF-01 | `XADD key * field value …` returning an entry ID | The primary that executed it appended the entry to the stream in its memory and assigned an ID greater than the stream's previous top ID | Nothing about any replica, any disk, survival of a primary crash, or survival of a failover. **An entry ID alone is never `CONFIRMED`** (7D TPT-02, ADR-7D-19). |
| MF-02 | Replication (primary → replica) | The replica applies the primary's write stream asynchronously, in order; a replica's dataset is always a prefix of its primary's command history | That any particular write has reached a replica at any particular time |
| MF-03 | `WAIT numreplicas timeout` | Blocks until **all previous write commands sent on the same connection** have been acknowledged by at least `numreplicas` replicas (received and applied in replica memory), or the timeout expires; returns the number of acknowledging replicas | That the write is on any disk. A `WAIT`-acknowledged write is not rolled back on timeout and is not guaranteed to survive every failover sequence (see MF-09). It covers only writes from the connection that issues it. |
| MF-04 | `WAITAOF numlocal numreplicas timeout` (introduced in Redis 7.2) | Blocks until all previous write commands sent on the same connection have been fsynced to the AOF of the local primary (when `numlocal` = 1) and of at least `numreplicas` replicas, or the timeout expires; returns the pair (local count, replica count). Requires AOF enabled on every node that is counted | Survival of loss of the storage that holds those AOF files. It does not roll back on timeout. It covers only writes from the issuing connection. |
| MF-05 | `min-replicas-to-write N` + `min-replicas-max-lag S` | The primary refuses write commands (error `NOREPLICAS`) while fewer than `N` replicas are connected with replication lag ≤ `S` seconds; this bounds how long an isolated primary keeps accepting writes | That any accepted write is replicated |
| MF-06 | AOF `appendfsync everysec` | The AOF is fsynced about once per second in the background; a process or host crash can lose the most recent writes not yet fsynced (about one second, more if fsync stalls) | Zero loss. **AOF `everysec` is never claimed to be zero-loss** (5A §24.2 calls AOF best-effort). |
| MF-07 | AOF `appendfsync always` | The AOF is fsynced before the server replies to the writes of each event-loop iteration | Survival of storage loss; low per-write cost |
| MF-08 | Redis Cluster automatic failover | After the cluster marks a primary as failed (node timeout), its replica can be promoted by a majority vote of primaries; the promoted dataset is the replica's replicated prefix; the old primary later rejoins as a replica and resynchronizes, discarding writes the new primary does not hold | That writes acknowledged only by the old primary survive |
| MF-09 | Primary restart **without** failover | If a crashed primary restarts and rejoins before it is marked failed, it reloads its own persisted state; with `everysec` that state can miss its most recent writes; its replica may then perform a full resynchronization from the restarted primary and replace its own dataset | That writes the replica had acknowledged (via `WAIT`) survive. **This is why `WAIT` alone is insufficient (hazard H-1, §11.3).** |
| MF-10 | Consumer-group state (`XGROUP`, `XREADGROUP`, `XACK`, `XCLAIM`, `XAUTOCLAIM`) | Group positions, PEL and acknowledgements are stored in the stream key and replicated like other writes; after failover or restart the state is a consistent prefix of history | That an `XACK` or delivery survives failover; a regressed state re-delivers entries (duplicates), it does not skip them |
| MF-11 | `XTRIM key MINID [~] id` / `XADD … MINID` | Removes entries with IDs lower than `id`. With `~`, Redis may remove fewer entries than the exact form, never entries with ID ≥ `id` | Any awareness of consumer groups or PELs: **trimming removes entries regardless of pending state** |
| MF-12 | `XTRIM key MAXLEN [~] n` / `XADD … MAXLEN` | Bounds stream length by removing the oldest entries | Any awareness of consumer groups or PELs |
| MF-13 | `XINFO GROUPS key` (Redis 7.0+ fields include `last-delivered-id`, `entries-read`, `lag`, `pending`) and `XPENDING key group` (summary form returns the smallest and largest pending ID) | Per-group delivery position and pending range | Business processing state |
| MF-14 | `XAUTOCLAIM` / `XCLAIM` with a minimum idle time | Ownership of pending entries idle at least that long can be transferred to another consumer of the same group; the delivery counter increments; in Redis 7, `XAUTOCLAIM` also reports pending IDs whose entries no longer exist | Exactly-once processing; reclaim produces at-least-once redelivery only |
| MF-15 | `XGROUP DELCONSUMER` | Removes a consumer from a group; **any entries still pending for that consumer are removed from the PEL and become unclaimable** | Safety for a consumer that still owns pending entries |
| MF-16 | Multi-key commands in Redis Cluster | Accepted only when all keys hash to the same slot; otherwise `CROSSSLOT` error | A single `XREADGROUP` across keys in different slots |
| MF-17 | `MOVED slot host:port` / `ASK slot host:port` | `MOVED`: the node does not serve the slot; the command was **not executed**. `ASK`: the slot is migrating; the key is served by the target for this command only (after `ASKING`) | That a retry elsewhere is unnecessary |
| MF-18 | `maxmemory-policy` | An **instance-level** configuration. Under `noeviction`, writes that need memory beyond `maxmemory` fail with an `OOM` error. Under `allkeys-*`, any key (including a stream key and all its group state) can be evicted. Under `volatile-*`, only keys with a TTL can be evicted | A per-key-space policy inside one instance; unlimited memory (`noeviction` only turns exhaustion into explicit write errors) |
| MF-19 | `WAITAOF` / `WAIT` timeout argument | A timeout of `0` means **block indefinitely**; a positive timeout (milliseconds) bounds the wait, after which the command returns the counts reached so far | That a returned count below the request is a failure signal by itself (the caller must compare counts) |
| MF-21 | `CLUSTER SHARDS` / `CLUSTER NODES` versus `INFO replication` | `CLUSTER SHARDS` (7.0+) lists every node the cluster knows for a shard, with its role and health (`online`, `failed`, `loading`); `CLUSTER NODES` lists every known node with its flags (for example `master`, `slave <primary-id>`, `fail`, `fail?`, `handshake`) until the node is removed with `CLUSTER FORGET`. `INFO replication` on a primary lists only the replicas **currently connected** to it (`connected_slaves`, `slaveN:ip,port,state,offset,lag`) | That `connected_slaves = 1` means the shard has only one replica: a configured replica that is failed, disconnected or loading is absent from `INFO replication` but still a member of the shard and can later reconnect and become a failover candidate |
| MF-22 | `cluster-replica-no-failover` and the `nofailover` flag | When `cluster-replica-no-failover` is `yes` on a replica, that replica never attempts automatic failover of its primary; Redis Cluster then shows the `nofailover` flag for that node in `CLUSTER NODES`. With `no` (the Redis default) the replica attempts automatic failover when its primary is marked failed | That a healthy, connected sole replica is promotable: membership and health say nothing about failover eligibility; manual promotion (`CLUSTER FAILOVER`) is not automatic failover |
| MF-24 | `maxmemory` on a replica and after promotion | By default a replica does not enforce its own `maxmemory` / eviction while it is a replica (`replica-ignore-maxmemory yes`); it mirrors its primary. `maxmemory-policy` is configured per node and is reported by `INFO memory` (`maxmemory_policy`) on primaries and replicas alike. Once a replica is promoted to primary, **its own** configured `maxmemory-policy` takes effect | That a replica's eviction-capable policy is harmless: it is harmless only until that replica is promoted. Checking the current primary's policy says nothing about the policy that will apply after failover |
| MF-23 | `cluster-replica-validity-factor` | A replica attempts automatic failover only if its data age (time since its last interaction with the primary) does not exceed `cluster-node-timeout × factor + repl-ping-replica-period`; with factor `0` it always attempts. The Redis default factor is `10` | That a replica disconnected from its primary for longer than that window will be automatically promoted when the primary later fails; election is not independent of replica freshness |
| MF-20 | Replica selection on failover | Among several replicas, Redis Cluster prefers the replica with the most advanced replication offset (rank-based election delay); this is a preference, not a strict guarantee that a particular acknowledged replica is the one promoted | That, with more than one replica, the replica that fsynced a given entry is the one promoted |

Facts MF-03, MF-04, MF-06 … MF-10 and MF-19 … MF-24 are stated at the level of the Redis documentation for 7.2. IO-7E-12 requires the chaos suite to demonstrate them against the deployed version before production (§52), and 7E's rules never depend on a property stronger than the one stated.

---
## 11. Transport Fault Model

### 11.1 Principle

| ID | Rule |
|---|---|
| FMD-01 | 7E declares which Redis faults are **inside** the normal durability model. For every fault inside it, a `CONFIRMED` durable entry survives and remains deliverable at least once to every consumer group of its stream. **No normal-path residual-loss window is allowed** (7D HO-7E-03). |
| FMD-02 | For a fault **outside** the declared model, the 7D disaster / repair path applies: retained `PUBLISHED` outbox rows within the cleanup window (7D CLN-08, F7D-21) and owner state, under 7G / 7K procedures. **Normal failover never depends on disaster replay.** |
| FMD-03 | Any fault, inside or outside the model, may produce duplicates. Duplicates of the same `event_id` are allowed (DUR-06, DEL-02). Loss of a `CONFIRMED` entry is allowed only for an outside-model fault. |
| FMD-04 | An availability fault (Redis cannot accept or cannot confirm) is never a loss: the outbox keeps the row and the relay defers it (7D DSP-03, GATE-01 … GATE-08). |

### 11.2 Fault catalogue and classification

Classification under the owner-decided mechanism (OD-7E-02 = A: `XADD` + same-connection `WAITAOF 1 1 <bounded timeout>`, AOF `appendfsync everysec` on every event-transport node, exactly one replica per primary, `min-replicas-to-write 1`; §23.5). Option E0 (`WAIT` only) was ineligible because it fails H-1.

| # | Fault | Classification | Behaviour under the decided mechanism | Loss of `CONFIRMED`? |
|---|---|---|---|---|
| TF-01 | Primary process failure, failover to its replica | Inside | Replica holds every confirmed entry fsynced (MF-04) and is promoted automatically (MF-08), because it is the sole replica, is failover-eligible (TOPO-11: no `nofailover`) and was connected within the lag bound when its primary failed, so its data age is inside the validity window (TOPO-12, MF-23) | No |
| TF-02 | Primary process failure, process restarts before failover (H-1) | Inside | The restarted primary reloads an AOF that contains every confirmed entry, because confirmation requires local fsync (`WAITAOF` local ≥ 1, MF-04) | No |
| TF-03 | Primary node failure (host lost), automatic promotion of its replica | Inside | As TF-01 | No |
| TF-04 | Replica lag | Inside | Confirmation waits; on timeout the outcome is `UNKNOWN` (§25) | No |
| TF-05 | Connection reset after write | Inside | Outcome `UNKNOWN`; republication with the same `event_id` | No (duplicate possible) |
| TF-06 | Cluster `MOVED` | Inside | Command not executed (MF-17); topology refresh; bounded re-issue (§24) | No |
| TF-07 | Cluster `ASK` | Inside | Durable stream keys are never live-migrated (LCY-06); `ASK` on a durable key is a governance anomaly classified `TRANSPORT_UNAVAILABLE` (§24) | No |
| TF-08 | Primary changes during publication | Inside | Confirmation was not obtained on the issuing connection → `UNKNOWN` or `TRANSPORT_UNAVAILABLE` (§24) | No |
| TF-09 | Network timeout after `XADD` | Inside | `UNKNOWN` | No (duplicate possible) |
| TF-10 | Single Redis node restart (primary or replica) | Inside | The other node of the shard holds every confirmed entry; a restarting node reloads its fsynced AOF | No |
| TF-11 | Single replica unavailable | Inside — availability fault | Confirmation impossible on that shard while the required replica count is unmet → non-terminal outcomes; no loss | No |
| TF-12 | Whole shard unavailable, storage intact | Inside — availability fault | `TRANSPORT_UNAVAILABLE`; entries on that shard return when the shard returns | No |
| TF-13 | Cluster partial outage | Inside — availability fault | Per shard as TF-11 / TF-12; gate opens (7D GATE-02) | No |
| TF-14 | Cluster-wide outage, storage intact | Inside — availability fault | Outbox accumulates (7A FM-01); resume after recovery | No |
| TF-15 | Network partition / split-brain | Inside | A primary isolated from its replica cannot obtain replica confirmation → never `CONFIRMED`; `min-replicas-to-write` bounds its accepted writes (MF-05); writes it accepted are discarded on rejoin (MF-08) and were never confirmed | No |
| TF-16 | Simultaneous process restart of a primary **and** its replica, storage intact | Inside | Both nodes fsynced the entry before `CONFIRMED` (`WAITAOF` local ≥ 1 and replica ≥ 1); both reload it from their AOF | No |
| TF-17 | Simultaneous **permanent** loss of a primary and its only replica (both storages), i.e. correlated destruction of every durable copy of the shard | Outside | Disaster path (FMD-02): 7D CLN-08 replay under 7G / 7K | Yes (outside model) |
| TF-18 | Region loss | Outside | 7K regional recovery; 7D CLN-08 replay; RES rules (§46) | Yes (outside model) |
| TF-19 | Correlated storage loss / corruption across nodes of a shard | Outside | Disaster path | Yes (outside model) |
| TF-20 | Operator destructive action (key deletion, `FLUSHALL`, group destruction outside governance, live resharding of durable keys contrary to LCY-06, ungoverned replica-membership change contrary to FMD-09) | Outside — governance violation | Disaster path; 7G / 7I operator controls | Yes (outside model) |
| TF-21 | Relay crash after `CONFIRMED`, before PostgreSQL `fn_mark_outbox_published` | Inside | Entry is durable in the stream; the row stays `CLAIMED`, its lease expires and it is republished with the same `event_id` (7D AMB-02, CRS-06) | No (duplicate possible) |
| TF-23 | The sole replica was disconnected from its primary for longer than the failover-validity window (MF-23), **and then** the primary fails (two faults) | Inside for durability (no loss) — availability fault outside the automatic-failover guarantee | Automatic promotion is **not** guaranteed: the stale replica may refuse to fail over and the shard becomes unavailable. No `CONFIRMED` entry is lost: confirmations stopped when the replica disconnected (`WAITAOF` replicas ≥ 1 unreachable; CAP-04 withdrawn), and every entry confirmed earlier is fsynced in the replica's AOF and in the primary's. Recovery is a governed operator procedure (7K / 7G runbook), not normal automatic failover | No |
| TF-22 | Promoted replica now runs with no replica (its former primary still down) | Inside — availability fault | `min-replicas-to-write 1` refuses new writes (`NOREPLICAS`) and `WAITAOF` cannot reach replica ≥ 1, so nothing new is confirmed until a replica is attached; previously confirmed entries are held by the promoted node's AOF | No |

### 11.3 Hazard H-1 (why `WAIT` alone fails)

A primary appends entry `e` (MF-01); its replica acknowledges `e` in memory (`WAIT 1` returns 1, MF-03); the relay would treat `e` as confirmed. The primary process then crashes and restarts within the cluster node timeout, so no failover happens (MF-09). With `appendfsync everysec`, its reloaded AOF may lack `e` (MF-06). The replica resynchronizes from the restarted primary and adopts a dataset without `e`. `e` is lost although its row is already `PUBLISHED`. This is a normal-model fault (TF-02). Therefore any eligible mechanism MUST require that the primary has fsynced the entry before `CONFIRMED` (FMD-05).

| ID | Rule |
|---|---|
| FMD-05 | An eligible acceptance mechanism requires, per entry: (a) the entry is fsynced on the primary that accepted it, and (b) the entry is held by the replica of that primary. Neither (a) alone nor (b) alone is sufficient. The decided mechanism (`WAITAOF 1 1`, §23.5) requires both (a) and (b) **with fsync on the replica as well**. |

### 11.4 Declared V1 normal transport fault model (OD-7E-02 = A)

| ID | Rule |
|---|---|
| FMD-06 | **Inside the declared V1 normal model:** TF-01 … TF-16, TF-21 and TF-22 (TF-23 is inside for durability but outside the automatic-failover guarantee) — in words: primary process or pod failure after confirmation; primary restart after confirmation (with or without failover); normal automatic failover to the configured single replica, which TOPO-11 / TOPO-12 make failover-eligible; replica lag; single-node restarts; simultaneous process restart of a primary and its replica with storage intact; connection loss and ambiguous acknowledgement (classified `UNKNOWN`); cluster redirects; network partitions; availability outages of a replica, a shard or the whole cluster with storage intact; relay crash after confirmation and before PostgreSQL marking (duplicate republication at worst). For every such fault a `CONFIRMED` entry survives and remains deliverable at least once to every group of its key. |
| FMD-07 | **Outside the declared model (disaster / repair path, FMD-02, 7K / 7G):** TF-17 (correlated destruction of every durable copy of a shard), TF-18 (region loss and multi-region topology events), TF-19 (correlated storage loss or corruption), TF-20 (governance violations). These are never folded into the normal single-primary-failure guarantee and normal failover never depends on them. |
| FMD-08 | **No absolute claim.** 7E does not claim that Redis is strongly consistent or that loss is impossible under every conceivable fault. It claims exactly FMD-06: no loss of a `CONFIRMED` entry for the declared normal faults, which is the property 7D TPT-02 requires. There is no permitted residual-loss window for a normal fault. |
| FMD-10 | **Eviction safety across role change.** Every Redis node that currently owns **or can become primary for** an active-generation durable shard MUST have `maxmemory-policy noeviction` (TOPO-05). In V1 that is the current primary and its sole automatic-failover-eligible replica. Being a replica does not make an eviction-capable configuration safe for future promotion (MF-24). Because every failover candidate is prevalidated as `noeviction` before any entry is confirmed (CAP-05, `shard_capable`, HP-07), normal automatic promotion preserves the durable-stream eviction invariant: a role change MUST NOT turn a previously safe shard into an eviction-capable durable primary. After any topology refresh or failover the adapter refreshes roles and re-runs the capability checks; the newly promoted primary must still report `noeviction` and the shard must again satisfy FMD-09 (exactly one failover-eligible `noeviction` replica) before durable capability is claimed again (CAP-09). A replica with any policy other than `noeviction` is not a safe failover candidate and makes its shard NOT CAPABLE. |
| FMD-09 | **Replica-topology revalidation.** The FMD-06 guarantee is proven for a shard whose **total replica membership is exactly one** — one replica-role member in any state, which is the node whose fsync satisfied `WAITAOF 1 1` — **and whose sole replica is automatic-failover eligible** (TOPO-11: `cluster-replica-no-failover no`, no `nofailover` flag; TOPO-12: validity window). Membership alone does not establish promotability (MF-22): only membership = 1 **and** failover eligibility together make the shard's automatic promotable set exactly that one fsynced replica. A count of *connected* replicas does not prove this (MF-21): a second configured replica that is failed, disconnected or loading could reconnect behind and be promoted instead of the fsynced one (MF-20). Therefore: (a) the capability gate and the health probe prove total membership and failover eligibility per durable shard from cluster topology (CAP-04, HP-05, §23.5.2); (b) adding, removing or changing the failover eligibility of a replica of a durable shard is a **governed topology operation**; (c) a change that would make total replica membership anything other than exactly one is prohibited while the `WAITAOF 1 1` proof is in force, unless a governed 7E amendment first revalidates the confirmation rule (for example `WAITAOF 1 <all replicas>` or restricted failover eligibility) and the chaos suite (IO-7E-12) passes against the new topology; (d) the change procedure never introduces a second promotable replica while durable publication continues — durable claiming is stopped for the affected shard first (relay readiness withdrawn and the 7D gate held open by a failing CAP-04); (e) automatic replica migration is disabled (TOPO-10) so the cluster never changes membership on its own; (f) an ungoverned membership change is a governance violation (TF-20) and is detected at the next capability check (CAP-09), which withdraws durable capability. |

---

## 12. Production Redis Topology

### 12.1 Inherited baseline (unchanged)

Redis 7.2, Redis Cluster, minimum 3 primaries + 3 replicas (one per primary), automatic failover, AOF `everysec` + periodic RDB on persistent volumes (SRC-01 … SRC-06). 7E does not change the shared hot-tier cluster. By owner decision OD-7E-01 = A the event transport runs on a separate, dedicated cluster that reuses the same baseline shape (§12.3).

### 12.2 Requirements on the event-transport deployment

| ID | Requirement |
|---|---|
| TOPO-01 | Redis Cluster mode, **Redis Open Source 7.2 or later** on every node. This is a deployment and startup **prerequisite**, not an optimization: `WAITAOF` (MF-04), on which `CONFIRMED` depends, does not exist before 7.2. |
| TOPO-02 | Every primary that owns a durable stream key has **exactly one** replica in V1 (3F topology; OD-7E-02 = A), counted as total replica-role membership of its shard in any state, not as connected replicas (FMD-09, CAP-04). A different count requires the FMD-09 revalidation first. |
| TOPO-03 | AOF enabled (`appendonly yes`) with `appendfsync everysec` on every primary and every replica of the event-transport cluster, so that `WAITAOF` counts them (MF-04). `appendfsync always` is **not** used (OD-7E-02 = A). |
| TOPO-04 | `min-replicas-to-write` ≥ 1 with a bounded `min-replicas-max-lag` on every node that can own a durable stream key (MF-05). The numeric lag is 7K's. |
| TOPO-05 | `maxmemory-policy noeviction` on **every node** of the event-transport cluster — every primary and every replica, because any replica that can be promoted becomes a primary (FMD-10) — (OD-7E-01 = A; §13.4), with a configured `maxmemory` limit (noeviction is not unlimited memory). The policy is verified on both roles before publication (CAP-05, CAP-07, HP-07). |
| TOPO-06 | A primary and its replica are never scheduled on the same host (pod anti-affinity) and are spread across availability zones where the region has several (3F §10.2 lineage). Otherwise one host failure is a TF-17 event. |
| TOPO-07 | The persistent volumes that hold the AOF survive pod restart (SRC-06). |
| TOPO-08 | No cross-region replica of a durable stream key in the normal path (§46). |
| TOPO-09 | `proto-max-bulk-len` and client query-buffer limits stay at least as large as the maximum entry size (§22). The Redis defaults satisfy this; no lower value is configured. |
| TOPO-10 | Automatic replica migration is disabled on every event-transport node (`cluster-allow-replica-migration no`), so the cluster never moves a replica between shards by itself; replica membership changes only through the governed procedure of FMD-09. |
| TOPO-11 | **Automatic-failover eligibility.** The sole replica of every shard owning an active-generation durable key is automatic-failover eligible: `cluster-replica-no-failover no` on every event-transport replica, and `CLUSTER NODES` MUST NOT report the `nofailover` flag on it. Manual operator promotion does not satisfy this prerequisite. |
| TOPO-12 | **Failover-validity window.** `cluster-replica-validity-factor` is kept at the Redis default `10` (non-zero) as an infrastructure prerequisite, with `cluster-node-timeout` and `repl-ping-replica-period` set by 7K. For the normal single-primary-failure proof this suffices: CAP-04 / HP-05 require the sole replica to be connected within the lag bound, so when its primary fails the replica's data age is about one node timeout, inside the window (any factor ≥ 1), and it is eligible (MF-23). A replica disconnected longer than the window and then hit by a primary failure is TF-23 (no loss; automatic promotion not guaranteed). Changing the factor affects only that extended-outage availability, not the durability of `CONFIRMED` entries (the sole replica holds every confirmed entry), and is routed to 7K (HE-7K-05); it must not change the FMD-09 promotable-set argument. |

### 12.3 Dedicated event-transport Redis Cluster (OD-7E-01 = A)

```text
 Region R (one per active region; an INDIA_ENTERPRISE region has its own instance)
 +------------------------------------------------------------------------------+
 | PostgreSQL (authoritative)        audit.domain_event_outbox                   |
 |        | claim (7D)                                                           |
 |        v                                                                      |
 | Relay loops (7D role) --XADD + same-connection WAITAOF 1 1--+                 |
 | Voice runtime SIGNAL publisher --XADD MAXLEN ~ (no WAITAOF)--+                |
 |                                                              v                |
 |   EVENT-TRANSPORT REDIS CLUSTER (dedicated; noeviction; AOF everysec; 7.2+)   |
 |   +--------------+   +--------------+   +--------------+                      |
 |   | primary A    |   | primary B    |   | primary C    |   exactly 1 replica  |
 |   |  + replica A'|   |  + replica B'|   |  + replica C'|   per primary        |
 |   +--------------+   +--------------+   +--------------+                      |
 |   holds ONLY: 11 durable family stream keys + 1 SIGNAL stream key (g1)        |
 |              and their consumer-group / PEL state                             |
 |        ^ XREADGROUP / XACK / XAUTOCLAIM (7F / 7G)    ^ XINFO / XTRIM (trim)    |
 |   consumer groups (section 29)                  trim worker (section 34)      |
 |                                                                               |
 |   SHARED HOT-TIER REDIS CLUSTER (3F role, unchanged): sessions, caches,       |
 |   queues, Celery broker, locks, presence -- holds NO event stream key         |
 +------------------------------------------------------------------------------+
   no cross-region replication or fan-out of event-transport data (section 46)
```

| ID | Rule |
|---|---|
| DEP-01 | Durable Redis Streams **and their consumer-group / PEL state** live only on a dedicated event-transport Redis Cluster, one per active region. |
| DEP-02 | The event-transport cluster holds only the stream keys of §15.4 (durable and SIGNAL) and no session, cache, queue, lock, presence or Celery-broker key. The shared hot-tier cluster (3F) holds no event stream key. |
| DEP-03 | The event-transport cluster follows TOPO-01 … TOPO-12: Redis Open Source 7.2+, Redis Cluster mode, minimum 3 primaries (failover voting) with exactly 1 automatic-failover-eligible replica each (`cluster-replica-no-failover no`), AOF `everysec` on all nodes, `noeviction` on every node including every failover replica, `min-replicas-to-write 1`, anti-affinity, persistent volumes, region-local. |
| DEP-04 | The SIGNAL stream key lives on the same event-transport cluster, on its own key (§17); SIGNAL writes never use `WAITAOF` (SEP-06). Memory exhaustion of the event-transport cluster therefore drops signals (SPB-02) but cannot affect the session tier of the shared cluster. |
| DEP-05 | The event-transport cluster has its own credentials (SCY-05), its own endpoints and network policy (reachable from relay, SIGNAL publisher, consumers, trim worker and provisioning only) and its own exporter. |
| DEP-06 | Capacity, scaling, headroom, alarms and production sizing of the event-transport cluster are 7J / 7K's (HE-7K-02, HE-7K-07). `noeviction` is not unlimited memory (MEM-02). |
| DEP-07 | This decision is a governed exception to 3F's single-cluster Redis assumption for the event-transport concern only. 3F is not edited; its documentary reconciliation is IO-7E-22. 3F's other key spaces are not redesigned by 7E (CNF-7E-15). |

---

## 13. Eviction Policy

### 13.1 The conflict

3F §16.3 (SRC-05) assigns `allkeys-lru` to session keys, `volatile-lru` to the RBAC / API-key cache and `noeviction` to queue keys, inside one Redis Cluster (SRC-02). `maxmemory-policy` is an instance-level setting (MF-18), and Redis Cluster places keys by hash slot, so every node of the shared cluster holds keys of every key space. **A per-key-space eviction policy cannot be implemented inside one cluster.** The table describes intent, not an implementable configuration (CNF-7E-01).

### 13.2 Consequence for durable streams

| ID | Rule |
|---|---|
| EVC-01 | A durable stream key MUST NOT be evictable while it exists. Under any `allkeys-*` policy a stream key — including all its consumer groups and PELs — can be evicted (MF-18). **Durable streams therefore MUST NOT be placed on any instance whose policy is `allkeys-*`.** |
| EVC-02 | Durable stream keys never carry a TTL (§37). Under a `volatile-*` policy they are therefore not eviction candidates; under `noeviction` nothing is evicted. |
| EVC-03 | Eviction of a durable stream is never acceptable, in any configuration, for any duration. |
| EVC-04 | When memory is exhausted under a non-evicting configuration, `XADD` fails with `OOM`; that outcome is `TRANSPORT_UNAVAILABLE` (§25, §41), never `ROW_REJECTED`. |

### 13.3 Can durable streams share the deployment that carries evictable caches?

Only if the whole shared cluster ran a policy that cannot evict a TTL-less key (`volatile-*` or `noeviction`), which would change 3F's session-key policy, make cache eviction depend on application TTL discipline and let durable backlog compete with the Voice session tier for memory. Frozen sources did not settle it, so 7E raised OD-7E-01. **The owner decided OD-7E-01 = A: durable streams do not share the hot-tier deployment.**

### 13.4 Selected policy (OD-7E-01 = A)

| ID | Rule |
|---|---|
| EVC-05 | The dedicated event-transport cluster (DEP-01) runs `maxmemory-policy noeviction` on every node, replicas included. No durable stream key and no consumer-group / PEL state can be evicted, before or after a failover (FMD-10). |
| EVC-06 | At the memory limit, write commands that need memory fail with `OOM`; the durable outcome is `TRANSPORT_UNAVAILABLE` under the 7D non-terminal deferral contract (EVC-04, CL-09, MEM-02). Existing durable entries and group state are never removed to make room. |
| EVC-07 | Prohibited alternatives (not chosen by the owner): placing durable streams on the shared cluster under `volatile-lru`, under `noeviction`, or on any deployment whose policy can evict a durable stream key. |
| EVC-08 | The shared hot-tier cluster's own eviction policy, including 3F §16.3's per-key-space intent for campaign queues and sessions, is outside 7E. Its existing impossibility (one instance-level policy per node, MF-18) is an inherited conflict handed to the 3F owner and 7K (CNF-7E-15, IO-7E-22); 7E does not redesign those key spaces. |

---

## 14. Stream Families

### 14.1 Decision (ADR-7E-01)

Durable events are grouped into **one logical stream per 7B semantic owner bounded context** (7B §23.1). The family of an exact `event_type` is a fixed attribute of its route-registry row (§18); it is not computed from a name prefix.

| Logical stream | Family token | 7B semantic owner | Semantic EVs | Exact V1 pairs | Current groups (§29) |
|---|---|---|---:|---:|---:|
| LS-D-IDN | `identity` | Identity (6B) | 1 | 1 | 1 |
| LS-D-ORG | `organization` | Organization (6C) | 1 | 1 | 1 |
| LS-D-CMP | `compliance` | Compliance (6C) | 2 | 2 | 1 |
| LS-D-VOX | `voice` | Voice (6D) | 13 | 13 | 6 |
| LS-D-AGT | `agent` | AI Agent (6E) | 5 | 7 | 0 |
| LS-D-KNW | `knowledge` | Knowledge (6F) | 9 | 9 | 2 |
| LS-D-CRM | `crm` | CRM (6G) | 32 | 32 | 2 |
| LS-D-CPN | `campaign` | Campaign (6H) | 23 | 23 | 3 |
| LS-D-WFL | `workflow` | Workflow (6I) | 7 | 7 | 1 |
| LS-D-INT | `integrations` | Integrations (6J) | 7 | 7 | 0 |
| LS-D-BIL | `billing` | Billing (6K) | 5 | 5 | 1 |
| **Durable total** | | | **105** | **107** | **18 subscriptions (11 logical groups)** |

Each durable family has `P_f = 1` partition in generation `g1` (OD-7E-03 = B, §16), so V1 has exactly **11 durable stream keys and 1 SIGNAL stream key**.
| LS-S-VOX | `voice` (SIGNAL profile) | Voice runtime (6D) | DS-17, DS-19 | 4 | 1 |

Notes: EV-098 `compliance.eligibility_denied` is produced by the Campaign executor but owned by Compliance (7B CNF-07); it routes to LS-D-CMP by its semantic owner. EV-071 `subscription.changed` is owned by Billing and routes to LS-D-BIL. The Analytics context (6L) owns no event and therefore no stream.

### 14.2 Alternatives evaluated

| Alternative | Evaluation | Disposition |
|---|---|---|
| One stream for all 107 pairs | Every group reads every entry; one key (or one key per partition) concentrates all traffic; one offline group pins retention for all families; no per-family operability | Rejected |
| One stream per exact `event_type` (107 logical streams) | Precise subscription, but 107 × partitions keys, 31 × consumers group placements spread over many keys, many more read calls (§40); 76 no-consumer pairs each need separate retention handling | Rejected |
| One stream per consumer (duplicate publication) | Multi-stream partial publication and multiple acceptance obligations per row (§27) | Rejected (ADR-7E-02) |
| **One stream per semantic owner context** | Bounded key count (11 durable families); aligns with 7B ownership; a group subscribes to the few families it needs; one record per event | **Chosen** |

A group subscribed to a family stream receives every entry of that stream, including types it has no handler for; it acknowledges those without side effect under 7F's rules (GRP-08).

---

## 15. Stream Namespace

### 15.1 Components

| Component | Value | Rule |
|---|---|---|
| Purpose prefix | `stream` | 3A §6.3 purpose prefix for Redis Streams (SRC-10). |
| Profile | `d` (DURABLE) or `s` (SIGNAL) | Separates the two 7C profiles at the key level (§17). |
| Topology generation | `g1` for V1 | Transport axis only; never `event_version` (§39, LCY-08). |
| Family token | one of the 11 durable tokens, or `voice` under profile `s` | From §14.1. |

### 15.2 Rules

| ID | Rule |
|---|---|
| NS-01 | Every stream key is a fixed string built only from the components above plus the scope literal `global` and the partition index (§15.4). No key contains an `event_type`, a payload value, an `event_id`, a user-controlled value, a pod name or a deployment revision. |
| NS-02 | No stream key contains a wildcard, a glob, a regex or the literal `tool_definition.*` or `tool_execution.*`. |
| NS-03 | The set of durable keys and the set of SIGNAL keys are disjoint by construction (profile component). |
| NS-04 | Stream keys are not tenant authority and are never parsed to obtain an `organization_id` (§44). |
| NS-05 | Stream keys are added to the Redis namespace catalogue by a documentary reconciliation of 5A §18.2 (IO-7E-22); 7E does not edit 5A. |

### 15.3 Group and consumer naming

Defined in §28.

### 15.4 Physical key grammar (OD-7E-03 = B)

```text
durable key  := "stream:global:d:" <gen> ":" <family> ":{d." <gen> "." <family> "." <p> "}"
SIGNAL key   := "stream:global:s:" <gen> ":voice:{s." <gen> ".voice." <p> "}"
<gen>        := "g1"                         (V1)
<family>     := identity | organization | compliance | voice | agent | knowledge
              | crm | campaign | workflow | integrations | billing
<p>          := decimal partition index, 0 <= p < P_f   (V1: P_f = 1, so p = 0)
```

| ID | Rule |
|---|---|
| NS-06 | The Redis Cluster hash tag is the brace-enclosed `d.<gen>.<family>.<p>` (or `s.<gen>.voice.<p>`); the slot of a key is `CRC16-XMODEM(hash tag) mod 16384` (standard Redis Cluster key hashing). Each partition key therefore has a fixed, computable slot. |
| NS-07 | The scope literal `global` means "platform event-transport keyspace shared by tenants (transport co-location only, §44)". It is never an organization identifier and never a tenant. No key contains `{<organization_id>}` or `{tenant_id}`: the event-transport keys are the owner-approved exception to 3F §16.2 (OD-7E-03 = B; CNF-7E-02). |
| NS-08 | The V1 key set is exactly the 12 keys below. |

| Logical stream | V1 physical key (`g1`, `p = 0`) | Hash slot | Shard under an even 3-way slot split (illustrative) |
|---|---|---:|---|
| LS-D-IDN | `stream:global:d:g1:identity:{d.g1.identity.0}` | 11812 | C |
| LS-D-ORG | `stream:global:d:g1:organization:{d.g1.organization.0}` | 16343 | C |
| LS-D-CMP | `stream:global:d:g1:compliance:{d.g1.compliance.0}` | 1024 | A |
| LS-D-VOX | `stream:global:d:g1:voice:{d.g1.voice.0}` | 1361 | A |
| LS-D-AGT | `stream:global:d:g1:agent:{d.g1.agent.0}` | 8402 | B |
| LS-D-KNW | `stream:global:d:g1:knowledge:{d.g1.knowledge.0}` | 14106 | C |
| LS-D-CRM | `stream:global:d:g1:crm:{d.g1.crm.0}` | 16093 | C |
| LS-D-CPN | `stream:global:d:g1:campaign:{d.g1.campaign.0}` | 2317 | A |
| LS-D-WFL | `stream:global:d:g1:workflow:{d.g1.workflow.0}` | 10460 | B |
| LS-D-INT | `stream:global:d:g1:integrations:{d.g1.integrations.0}` | 13875 | C |
| LS-D-BIL | `stream:global:d:g1:billing:{d.g1.billing.0}` | 9920 | B |
| LS-S-VOX | `stream:global:s:g1:voice:{s.g1.voice.0}` | 14922 | C |

The shard column assumes the default even split (slots 0 – 5460 → A, 5461 – 10922 → B, 10923 – 16383 → C) and is illustrative only. Which shard owns which slot is cluster configuration: before provisioning, empty slots MAY be reassigned to balance load (moving empty slots involves no data, LCY-06); that placement is a 7K decision (HE-7K-01).

---

## 16. Partition / Hash-Tag Strategy (OD-7E-03 = B)

### 16.1 The conflict and the decision

3F §16.2 requires `{tenant_id}` as the first hash tag of every new Redis key (SRC-04). Applied literally to event streams it would mean one stream per tenant per family, a consumer group per tenant per subscription, unbounded key and group counts and hot-tenant shard concentration. 7E raised OD-7E-03 (CNF-7E-02). **The owner decided OD-7E-03 = B:** a fixed number of partitions per durable family, partitioned by `aggregate_id`, as a deliberate governed exception to the 3F blanket `{tenant_id}` rule for the dedicated event-transport deployment. 3F is not edited (IO-7E-22). Per-tenant streams are not used; `organization_id` is not the durable partition key; one unpartitioned stream per family is the V1 starting **configuration** (`P_f = 1`), not a hard-coded architecture.

### 16.2 Rules

| ID | Rule |
|---|---|
| PRT-01 | The partition of an entry is a deterministic function of the read-only, **valid non-null** `aggregate_id` routing attribute of 7D's `envelope_view`, the entry's family and the active topology generation (§16.3). It never uses payload fields, secrets, Redis load, consumer availability, time, randomness or a language-runtime hash (for example Python `hash()`, Java `hashCode()`, or any seeded or per-process hash). |
| PRT-02 | EV-001's `organization_id = null` needs no special partition rule: partitioning reads `aggregate_id` (`user_id`, non-null, 7C EV-001), never `organization_id`. EV-001 routes to LS-D-IDN like any other row of its pair. No fake organization ID, no zero UUID and no payload-derived organization is used (RTE-06). |
| PRT-03 | The partition count `P_f` of a family is a constant of a topology generation. It never changes in place; a change creates a new generation under LCY-05 … LCY-07 and requires 7K approval from measurement (HE-7K-01). |
| PRT-04 | **Partition affinity is not ordering.** A stable `aggregate_id` → partition mapping guarantees only that, within one topology generation, all entries of one aggregate target the same partition key. It does **not** guarantee per-aggregate business, commit or causal order (§33, ORD-7E-06). |
| PRT-05 | A partition is transport co-location only, never tenant authority (§44). |
| PRT-06 | `organization_id` is never used to choose a durable partition, and no durable key is tenant-scoped. |
| PRT-07 | **No partition exists for a NULL `aggregate_id`.** PF-1 is defined only for a valid non-null V1 `aggregate_id` (7C ENV-06, AGG-04). A committed row whose `aggregate_id` is NULL (physically possible, because the outbox column is nullable) is contract-invalid: `route_for` returns `NONE` for it before any partition is computed (RTE-09), so 7D classifies it `RELAY_CAPABILITY` (non-terminal; 7D MAN-04, MAT-04, F7D-14). There is no fallback partition, no zero UUID, no substitute attribute and no repair. |

### 16.3 Partition function `PF-1`

```text
partition(aggregate_id, family, gen) -> integer p, 0 <= p < P
    -- PRECONDITION: aggregate_id is a valid non-null UUID (7C ENV-06, AGG-04).
    -- route_for establishes it before calling (RTE-09); PF-1 has no NULL branch and no fallback value.
    P := PARTITION_COUNT[gen][family]          -- g1: 1 for all 11 families (§16.4)
    b := the 16 octets of aggregate_id in RFC 9562 binary layout
         (network byte order, i.e. the 32 hex digits of the canonical text, in order)
    h := CRC32(b)                              -- CRC-32/ISO-HDLC, see below, as unsigned 32-bit
    return h mod P
```

| Parameter | Value |
|---|---|
| Algorithm | CRC-32/ISO-HDLC (the CRC-32 of IEEE 802.3, zlib, PNG) |
| Polynomial | `0x04C11DB7` (reflected `0xEDB88320`) |
| Initial value / input and output reflection / final XOR | `0xFFFFFFFF` / reflected in, reflected out / `0xFFFFFFFF` |
| Check value | `CRC32("123456789") = 0xCBF43926` |
| Input | exactly the 16 octets of a valid non-null UUID (not the text form, so upper- or lower-case text renderings give the same input). PF-1 is undefined for NULL and is never called with it (PRT-07, RTE-09) |
| Result | `h` as an unsigned 32-bit integer; `p = h mod P` using unsigned arithmetic |

Test vectors (every implementation MUST reproduce them):

| `aggregate_id` | `CRC32` (hex) | `CRC32` (decimal) | `p` for `P = 1` | `p` for `P = 4` | `p` for `P = 8` |
|---|---|---:|---:|---:|---:|
| `01923f4e-7b01-7d02-8e03-9f04a5b6c7d8` | `3ab24ab5` | 984763061 | 0 | 1 | 5 |
| `01923f4e-7c2a-7b10-9a3e-5d6f7a8b9c0d` | `1a4ace71` | 441110129 | 0 | 1 | 1 |
| `123e4567-e89b-12d3-a456-426614174000` | `ac87a5f0` | 2894570992 | 0 | 0 | 0 |
| `ffffffff-ffff-ffff-ffff-ffffffffffff` | `3fb3c61a` | 1068746266 | 0 | 2 | 2 |
| `00000000-0000-0000-0000-000000000000` | `ecbb4b55` | 3971697493 | 0 | 1 | 5 |

### 16.4 V1 partition counts

| Generation | Family | `P_f` | Basis |
|---|---|---:|---|
| `g1` | each of the 11 durable families | 1 | OD-7E-03 = B: start at one partition per family until 7K capacity evidence justifies more (7A §32.2 forbids invented sizing numbers) |
| `g1` | SIGNAL (`voice`) | 1 | Non-durable; same key grammar; any later partitioning reuses PF-1 under a new generation |

V1 therefore has 11 durable keys and 1 SIGNAL key (NS-08). A later generation with `P_f > 1` reuses PF-1 and the grammar of §15.4 unchanged; only `PARTITION_COUNT` and `<gen>` change, through LCY-07.

### 16.5 Alternatives (owner decision record)

Per-tenant streams (literal 3F), partitioning by `organization_id`, and one permanently unpartitioned stream per family were evaluated in §50.3 and not chosen.

---

## 17. Durable versus SIGNAL Separation

| ID | Rule |
|---|---|
| SEP-01 | Durable A/B/C envelopes are written only to profile-`d` keys; SIGNAL envelopes only to profile-`s` keys (7D TPT-06, 7A RS-05, 7C PRF-02). |
| SEP-02 | The durable relay uses the `DurableEventTransportPublisher` port instance; the Class-D publisher uses a separate signal publisher instance with its own route table (§19), its own connection pool and no shared gate state (7D CLD-10). |
| SEP-03 | The entry format marker differs (`durable.v1` versus `signal.v1`, §21). A consumer that reads a marker of the wrong profile treats it as a transport defect and never processes it as the other profile. |
| SEP-04 | No consumer group subscribes to both a profile-`d` key and a profile-`s` key under the same group name. Analytics uses distinct groups for its durable and SIGNAL obligations (§29). |
| SEP-05 | The 4 SIGNAL pairs never appear in the durable route registry and the 107 durable pairs never appear in the SIGNAL route registry (§18, §19). |
| SEP-06 | SIGNAL publication never uses the durable-acceptance mechanism (§23) and never runs on the Voice hot path with a durability wait (§47). |

---
## 18. Durable Route Registry (107 exact V1 pairs)

### 18.1 Rules

| ID | Rule |
|---|---|
| RR-01 | The registry is keyed by the exact (`event_type`, `event_version`) pair. Every one of the 107 exact durable V1 pairs of 7C §20.8 / CSR-02 appears **exactly once**. No other durable pair appears. |
| RR-02 | EV-014 contributes three rows, one per member (`tool_definition.created`, `tool_definition.updated`, `tool_definition.deactivated`; TDF-03). The literal `tool_definition.*` is **never** a registry key, a route key, a stream key, a runtime `event_type` or a matcher (TDF-01, CSR-09). |
| RR-03 | There is no family, wildcard, regex, prefix or glob row and no fallback route. A committed row whose exact pair has no registry row receives `NONE` from `route_for` and the relay classifies it `RELAY_CAPABILITY` (non-terminal; 7D MAN-04, DPC-04). |
| RR-04 | Every row routes to exactly one durable logical stream. Fan-out to several consumers is by consumer groups on that one stream (§27), never by a second route. |
| RR-05 | The "current groups" column is derived only from 7B CON-01 … CON-11 (§29). It lists who must receive the event; it is not a routing input. Routing does not depend on consumer availability. |
| RR-06 | 76 rows (74 semantic events, with EV-014 counted as its 3 members) have no current consumer. They are still routed and published (7D requires every durable event to be transported); their retention is §35 or §34 depending on whether their stream has groups. |
| RR-07 | Adding, removing or changing a row is a governed 7E change, deployed before any producer emits a new pair (7C rollout; 7D DPC-04). A new `event_version` of an existing type adds a row for the new pair on the **same** logical stream; it never renames a stream (LCY-09). |

### 18.2 Registry

Columns: route row · EV · exact `event_type` · `event_version` · class · family · logical stream · current consumer groups (7B consumer).

| Row | EV | `event_type` | Ver | Class | Family | Logical stream | Current groups |
|---|---|---|---:|---|---|---|---|
| R-001 | EV-001 | `identity.forced_revocation_required` | 1 | A | `identity` | LS-D-IDN | `cg.identity.session-denylist` (CON-01) |
| R-002 | EV-002 | `organization.created` | 1 | A | `organization` | LS-D-ORG | `cg.compliance.default-policy-seeding` (CON-02) |
| R-003 | EV-003 | `compliance.policy_activated` | 1 | A | `compliance` | LS-D-CMP | `cg.compliance.active-policy-pointer` (CON-03) |
| R-004 | EV-004 | `call.initiated` | 1 | A | `voice` | LS-D-VOX | — (CURRENT_NO_CONSUMER) |
| R-005 | EV-005 | `call.ended` | 1 | A | `voice` | LS-D-VOX | `cg.crm.call-history` (CON-04), `cg.campaign.record-call-outcome` (CON-05), `cg.billing.usage-ingestion` (CON-06), `cg.analytics.projections` (CON-07) |
| R-006 | EV-006 | `call.failed` | 1 | A | `voice` | LS-D-VOX | `cg.campaign.record-call-outcome` (CON-05), `cg.analytics.projections` (CON-07), `cg.integrations.webhook-engine` (CON-10) |
| R-007 | EV-007 | `call.held` | 1 | A | `voice` | LS-D-VOX | — (CURRENT_NO_CONSUMER) |
| R-008 | EV-008 | `call.resumed` | 1 | A | `voice` | LS-D-VOX | — (CURRENT_NO_CONSUMER) |
| R-009 | EV-009 | `recording.deleted` | 1 | A | `voice` | LS-D-VOX | `cg.voice.recording-object-cleanup` (CON-08) |
| R-010 | EV-010 | `agent.created` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-011 | EV-011 | `agent.config_updated` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-012 | EV-012 | `agent.published` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-013 | EV-013 | `agent.deprecated` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-014 | EV-014 | `tool_definition.created` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-015 | EV-014 | `tool_definition.updated` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-016 | EV-014 | `tool_definition.deactivated` | 1 | A | `agent` | LS-D-AGT | — (CURRENT_NO_CONSUMER) |
| R-017 | EV-015 | `knowledge_base.created` | 1 | A | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-018 | EV-016 | `knowledge_base.settings_updated` | 1 | A | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-019 | EV-017 | `knowledge_base.archived` | 1 | A | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-020 | EV-018 | `knowledge_base.reindex_triggered` | 1 | A | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-021 | EV-019 | `document.uploaded` | 1 | A | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-022 | EV-020 | `document.deleted` | 1 | A | `knowledge` | LS-D-KNW | `cg.knowledge.document-count` (CON-09) |
| R-023 | EV-021 | `contact.created` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-024 | EV-022 | `contact.updated` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-025 | EV-023 | `contact.lead_status_changed` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-026 | EV-024 | `contact.qualified` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-027 | EV-025 | `contact.disqualified` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-028 | EV-026 | `contact.converted` | 1 | A | `crm` | LS-D-CRM | `cg.analytics.projections` (CON-07) |
| R-029 | EV-027 | `contact.owner_assigned` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-030 | EV-028 | `contact.merged` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-031 | EV-029 | `contact.dnc_flagged` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-032 | EV-030 | `suppression.added` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-033 | EV-031 | `contact.suppression_lifted` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-034 | EV-032 | `consent.recorded` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-035 | EV-033 | `company.created` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-036 | EV-034 | `company.updated` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-037 | EV-035 | `deal.created` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-038 | EV-036 | `deal.stage_changed` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-039 | EV-037 | `deal.won` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-040 | EV-038 | `deal.lost` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-041 | EV-039 | `deal.abandoned` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-042 | EV-040 | `activity.recorded` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-043 | EV-041 | `task.created` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-044 | EV-042 | `task.completed` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-045 | EV-043 | `task.cancelled` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-046 | EV-044 | `note.added` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-047 | EV-045 | `note.deleted` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-048 | EV-046 | `appointment.booked` | 1 | A | `crm` | LS-D-CRM | `cg.integrations.webhook-engine` (CON-10) |
| R-049 | EV-047 | `appointment.confirmed` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-050 | EV-048 | `appointment.rescheduled` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-051 | EV-049 | `appointment.cancelled` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-052 | EV-050 | `appointment.completed` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-053 | EV-051 | `appointment.no_show` | 1 | A | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-054 | EV-052 | `campaign.created` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-055 | EV-053 | `campaign.config_updated` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-056 | EV-054 | `campaign.contact_list_attached` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-057 | EV-055 | `campaign.scheduled` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-058 | EV-056 | `campaign.paused` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-059 | EV-057 | `campaign.resumed` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-060 | EV-058 | `campaign.stopping` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-061 | EV-059 | `campaign.cancelled` | 1 | A | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-062 | EV-060 | `import.job_created` | 1 | A | `campaign` | LS-D-CPN | `cg.campaign.import-worker` (CON-11) |
| R-063 | EV-061 | `workflow.created` | 1 | A | `workflow` | LS-D-WFL | — (CURRENT_NO_CONSUMER) |
| R-064 | EV-062 | `workflow.draft_updated` | 1 | A | `workflow` | LS-D-WFL | — (CURRENT_NO_CONSUMER) |
| R-065 | EV-063 | `workflow.published` | 1 | A | `workflow` | LS-D-WFL | — (CURRENT_NO_CONSUMER) |
| R-066 | EV-064 | `workflow.archived` | 1 | A | `workflow` | LS-D-WFL | — (CURRENT_NO_CONSUMER) |
| R-067 | EV-065 | `integration.disconnected` | 1 | A | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-068 | EV-066 | `webhook.endpoint_created` | 1 | A | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-069 | EV-067 | `plugin.installed` | 1 | A | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-070 | EV-068 | `plugin.activated` | 1 | A | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-071 | EV-069 | `plugin.suspended` | 1 | A | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-072 | EV-070 | `plugin.uninstalled` | 1 | A | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-073 | EV-071 | `subscription.changed` | 1 | A | `billing` | LS-D-BIL | `cg.integrations.webhook-engine` (CON-10) |
| R-074 | EV-072 | `integration.connected` | 1 | B | `integrations` | LS-D-INT | — (CURRENT_NO_CONSUMER) |
| R-075 | EV-073 | `call.answered` | 1 | C | `voice` | LS-D-VOX | — (CURRENT_NO_CONSUMER) |
| R-076 | EV-074 | `call.conversation_started` | 1 | C | `voice` | LS-D-VOX | — (CURRENT_NO_CONSUMER) |
| R-077 | EV-075 | `call.transferred` | 1 | C | `voice` | LS-D-VOX | `cg.integrations.webhook-engine` (CON-10) |
| R-078 | EV-076 | `conversation.qualification_set` | 1 | C | `voice` | LS-D-VOX | `cg.crm.call-history` (CON-04), `cg.campaign.record-call-outcome` (CON-05) |
| R-079 | EV-077 | `conversation.sentiment_computed` | 1 | C | `voice` | LS-D-VOX | — (CURRENT_NO_CONSUMER) |
| R-080 | EV-078 | `conversation.summarization_completed` | 1 | C | `voice` | LS-D-VOX | `cg.crm.call-history` (CON-04) |
| R-081 | EV-079 | `conversation.completed` | 1 | C | `voice` | LS-D-VOX | `cg.billing.usage-ingestion` (CON-06) |
| R-082 | EV-080 | `knowledge_base.reindex_completed` | 1 | C | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-083 | EV-081 | `document.indexed` | 1 | C | `knowledge` | LS-D-KNW | `cg.billing.usage-ingestion` (CON-06), `cg.knowledge.document-count` (CON-09) |
| R-084 | EV-082 | `document.ingestion_failed` | 1 | C | `knowledge` | LS-D-KNW | — (CURRENT_NO_CONSUMER) |
| R-085 | EV-083 | `contact.score_updated` | 1 | C | `crm` | LS-D-CRM | — (CURRENT_NO_CONSUMER) |
| R-086 | EV-084 | `campaign.started` | 1 | C | `campaign` | LS-D-CPN | `cg.integrations.webhook-engine` (CON-10) |
| R-087 | EV-085 | `campaign.completed` | 1 | C | `campaign` | LS-D-CPN | `cg.integrations.webhook-engine` (CON-10) |
| R-088 | EV-086 | `campaign.failed` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-089 | EV-087 | `campaign.contact.enqueued` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-090 | EV-088 | `campaign.contact.dnc_skipped` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-091 | EV-089 | `campaign.contact.ineligible` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-092 | EV-090 | `campaign.contact.call_attempted` | 1 | C | `campaign` | LS-D-CPN | `cg.billing.usage-ingestion` (CON-06) |
| R-093 | EV-091 | `campaign.contact.qualified` | 1 | C | `campaign` | LS-D-CPN | `cg.integrations.webhook-engine` (CON-10) |
| R-094 | EV-092 | `campaign.contact.disqualified` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-095 | EV-093 | `campaign.contact.retry_scheduled` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-096 | EV-094 | `campaign.contact.exhausted` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-097 | EV-095 | `import.job_completed` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-098 | EV-096 | `import.job_failed` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-099 | EV-097 | `campaign.outcome_computed` | 1 | C | `campaign` | LS-D-CPN | — (CURRENT_NO_CONSUMER) |
| R-100 | EV-098 | `compliance.eligibility_denied` | 1 | C | `compliance` | LS-D-CMP | — (CURRENT_NO_CONSUMER) |
| R-101 | EV-099 | `workflow.execution.started` | 1 | C | `workflow` | LS-D-WFL | — (CURRENT_NO_CONSUMER) |
| R-102 | EV-100 | `workflow.execution.completed` | 1 | C | `workflow` | LS-D-WFL | `cg.billing.usage-ingestion` (CON-06) |
| R-103 | EV-101 | `workflow.execution.failed` | 1 | C | `workflow` | LS-D-WFL | — (CURRENT_NO_CONSUMER) |
| R-104 | EV-102 | `invoice.generated` | 1 | C | `billing` | LS-D-BIL | `cg.integrations.webhook-engine` (CON-10) |
| R-105 | EV-103 | `invoice.paid` | 1 | C | `billing` | LS-D-BIL | `cg.integrations.webhook-engine` (CON-10) |
| R-106 | EV-104 | `payment.failed` | 1 | C | `billing` | LS-D-BIL | `cg.integrations.webhook-engine` (CON-10) |
| R-107 | EV-105 | `usage.threshold_reached` | 1 | C | `billing` | LS-D-BIL | `cg.integrations.webhook-engine` (CON-10) |

### 18.3 Registry totals

| Measure | Value |
|---|---:|
| Rows (exact durable V1 pairs) | 107 |
| Distinct EV IDs | 105 |
| EV-014 member rows | 3 |
| Rows with ≥ 1 current group | 31 |
| Rows with no current group | 76 (74 semantic events; EV-014 as 3 rows) |
| Family / wildcard / regex / prefix rows | 0 |
| Rows routed to a SIGNAL stream | 0 |
| `event_version` ≠ 1 | 0 |

---

## 19. SIGNAL Route Registry (4 exact V1 pairs) and Unbound Class-D Signals

### 19.1 Registry

| Row | DS / PAY | `event_type` | Ver | Logical stream | Current group | Durability |
|---|---|---|---:|---|---|---|
| S-001 | DS-17 / PAY-D-01 | `conversation.turn_completed` | 1 | LS-S-VOX | `sg.analytics.signal-projections` (CON-07) | SIGNAL — best-effort, droppable |
| S-002 | DS-19 / PAY-D-02 | `tool_execution.started` | 1 | LS-S-VOX | `sg.analytics.signal-projections` (CON-07) | SIGNAL — best-effort, droppable |
| S-003 | DS-19 / PAY-D-02 | `tool_execution.succeeded` | 1 | LS-S-VOX | `sg.analytics.signal-projections` (CON-07) | SIGNAL — best-effort, droppable |
| S-004 | DS-19 / PAY-D-02 | `tool_execution.failed` | 1 | LS-S-VOX | `sg.analytics.signal-projections` (CON-07) | SIGNAL — best-effort, droppable |

### 19.2 Rules

| ID | Rule |
|---|---|
| SR-01 | Exactly these 4 rows. Each uses the 7C SIGNAL envelope (SIG-01 … SIG-11, `durability = "SIGNAL"`). The literal `tool_execution.*` is never a route, key or matcher (CSR-09). |
| SR-02 | The only current consumer is Analytics (7C SIG-R06; 7B CON-07). **Billing never consumes any SIGNAL stream** and no Billing group is ever created on a profile-`s` key (7D CLD-08; 7B CR-05; OD-7B-01). |
| SR-03 | SIGNAL rows have no outbox row, no relay, no durable acceptance, no durable retry and no replay (7D CLD-01 … CLD-06). |
| SR-04 | **DS-01 … DS-16 and DS-18 have no 7C SIGNAL binding and no consumer.** 7E creates **no** route, stream, group, payload or family member for them (7D CLD-09, DEF-7D-08; 7C §9). Their publisher has no active emission contract until a governed 7B + 7C change binds them; that change then adds rows here through a governed 7E change. |
| SR-05 | The 7E counts are: 19 semantic Class-D signals (7B), of which 4 exact SIGNAL V1 pairs are routed. These two numbers are never conflated. |

---

## 20. Route Function

```text
route_for(envelope_view) -> Route | NONE
    key := (envelope_view.event_type, envelope_view.event_version)      -- exact pair
    row := DURABLE_ROUTE_REGISTRY[key]                                   -- exact lookup, §18
    if row is absent: return NONE                                        -- relay → RELAY_CAPABILITY (reason NO_ROUTE)
    if envelope_view.aggregate_id is NULL:                               -- contract-invalid row (7C ENV-06, AGG-04)
        record_contract_anomaly(INVALID_ROUTING_ATTRIBUTE)               -- safe fields only (RTE-09)
        return NONE                                                      -- relay → RELAY_CAPABILITY; nothing is sent
    family := row.family                                                 -- e.g. "voice"
    gen    := ACTIVE_GENERATION                                          -- "g1" in V1
    p      := partition(envelope_view.aggregate_id, family, gen)         -- PF-1, §16.3 (valid non-null aggregate_id)
    key    := "stream:global:d:" + gen + ":" + family + ":{d." + gen + "." + family + "." + p + "}"   -- §15.4
    return Route(generation = gen, logical_stream = row.logical_stream, partition = p, physical_key = key)
```

| ID | Rule |
|---|---|
| RTE-01 | `route_for` is a pure, deterministic function of the exact pair, the read-only routing attributes and the configured active topology generation. The same envelope under the same generation always maps to the same key. |
| RTE-02 | Lookup is exact-match on the pair. There is no regex, prefix, glob, family or fallback matching (7D TPT-05, MAN-04; 7C CSR-09). |
| RTE-03 | `route_for` never reads the payload, never parses the envelope bytes, never reads secrets, Redis load, consumer availability, the clock or a random source. |
| RTE-04 | `route_for` never resolves a SIGNAL pair; the signal publisher has its own exact table (§19). A durable `route_for` call for a SIGNAL `event_type` returns `NONE`. |
| RTE-05 | A row whose `event_type` is a non-conformant literal such as `tool_definition.*` gets `NONE` (7D MAN-04) and is never published to a guessed stream. |
| RTE-06 | `organization_id = null` (EV-001, platform-scoped; 7C TEN-C02) is a valid input. Routing never reads `organization_id`: EV-001's family is fixed by its registry row (LS-D-IDN) and its partition by its non-null `aggregate_id` (`user_id`) through PF-1. That is the explicit platform-scope route; no fake organization, no zero UUID and no payload-derived organization is used. |
| RTE-07 | The route registry and the route function are part of the relay build (7D DPC-04): an older relay without a row returns `NONE` and defers; nothing is lost or failed. |
| RTE-08 | The Redis Cluster target shard of a route is the primary that currently owns the hash slot of `physical_key` (NS-06), resolved from the adapter's slot map; routing never depends on which shard that is. |
| RTE-09 | **Routing-attribute validation (NULL `aggregate_id`).** After the exact-pair lookup and before computing any partition, `route_for` validates the routing attributes 7E needs. If `aggregate_id` is NULL: (1) `route_for` returns `NONE` and produces no Route; (2) nothing is sent — no `XADD`, no `WAITAOF`, so the entry can never become `CONFIRMED` and its row is never marked `PUBLISHED`; (3) the 7D relay maps `NONE` to the non-terminal `RELAY_CAPABILITY` outcome and defers the row (7D MAN-04, DSP-03, F7D-14); (4) the adapter records a contract anomaly with internal reason `INVALID_ROUTING_ATTRIBUTE` and safe fields only (`event_id`, `event_type`, `event_version`), never payload (7D OBS-7D-11, OBS-7D-12, DSP-08); (5) the producer owner fixes forward; (6) the committed event is never rewritten (7D MAT-04, LIF-07); (7) partition 0 is never substituted; (8) no zero UUID is manufactured; (9) `organization_id` is never used instead; (10) payload fields are never used instead; (11) the case is never `ROW_REJECTED`; (12) the row is never moved to `FAILED`. `NO_ROUTE` and `INVALID_ROUTING_ATTRIBUTE` are internal reason codes inside the single frozen `RELAY_CAPABILITY` class; no new outcome is introduced. |

---

## 21. Stream Entry Format

### 21.1 Durable entry

```text
XADD <physical durable key> * fmt "durable.v1" env <envelope bytes>
```

| Field | Value | Encoding | Rule |
|---|---|---|---|
| `fmt` | the ASCII string `durable.v1` | ASCII bytes | Transport entry-format marker. A transport-axis value; never `event_version`; never business data. |
| `env` | the exact UTF-8 JSON envelope bytes produced once by the relay (7D MAT-09) | raw bytes in one Redis bulk string (binary-safe) | Carried unchanged: never split, re-encoded, re-serialized, compressed, escaped, base64-encoded or modified (7D TPT-03, 7C KEY-05). |

### 21.2 SIGNAL entry

```text
XADD <physical signal key> MAXLEN ~ <N_signal> * fmt "signal.v1" env <SIGNAL envelope bytes>
```

Same two fields; `fmt` is `signal.v1`; `env` is the SIGNAL envelope bytes carried unchanged (7C SIG-R04). `N_signal` is §36.

### 21.3 Rules

| ID | Rule |
|---|---|
| ENT-01 | An entry has exactly two fields, `fmt` and `env`, in that order. No other field is written. |
| ENT-02 | No envelope value is duplicated into a transport field (no copied `event_type`, `event_id`, `organization_id`, `aggregate_id`, `occurred_at`). The envelope inside `env` is the only source of every envelope value, so transport metadata cannot disagree with it. |
| ENT-03 | Transport metadata never contains payload content, never overrides or substitutes `organization_id`, never carries relay bookkeeping and never becomes event identity (7D TPT-04; 7C KEY-02). |
| ENT-04 | The Redis stream entry ID is **transport position only**. It is not `event_id`, not a dedup key, not an ordering key across streams and not stored in the outbox (7C ID-03; 7D TPT-02). |
| ENT-05 | `transport_ref` returned with `CONFIRMED` is the string `<physical key>/<entry ID>`. It is used only in logs and traces for diagnostics; it is never persisted in PostgreSQL and never used to decide publication (7D TPT-02, TPT-10). |
| ENT-06 | Consumers obtain `event_id`, `event_type`, `event_version`, `organization_id` and every other envelope value by parsing `env`. A JSON parser that decodes numbers into binary floating point MUST NOT be used for business values (7C §18; 7D MAT-08); this is a 7F implementation rule. |
| ENT-07 | A change to the entry layout is a new format marker (for example `durable.v2`) under a governed 7E change with consumer tolerance deployed first. It is never an `event_version` change and never changes the envelope. |
| ENT-08 | The adapter never logs `env` (7D SEC-7D-02; §45). |

---

## 22. Message Size

| ID | Rule |
|---|---|
| SIZ-01 | The outbox bound is `chk_outbox_payload_size: length(payload::TEXT) <= 262144` (077 L76). PostgreSQL `length(text)` counts **characters**, not bytes. A UTF-8 character is at most 4 bytes, so a valid committed payload's text can be up to **1 048 576 bytes**. |
| SIZ-02 | The adapter MUST accept every entry whose `env` is the materialization of a valid committed row: payload text up to 262144 characters (≤ 1 048 576 UTF-8 bytes) plus the envelope overhead (the fixed key set, identifiers, timestamps and optional correlation / causation). 7E defines **no** entry-size limit below that. (7D TPT-09 states the bound as "262144 bytes"; 7E sizes to the stricter physical maximum — CNF-7E-11.) |
| SIZ-03 | Redis bulk strings are limited by `proto-max-bulk-len` (default 512 MB), far above SIZ-02. TOPO-09 forbids configuring it, or the client query-buffer limit, below the maximum entry size. A size rejection caused by such a misconfiguration is a configuration-wide `TRANSPORT_UNAVAILABLE`, never `ROW_REJECTED` (§25). |
| SIZ-04 | Memory: a stream stores each entry once, regardless of how many groups read it; a PEL stores only IDs, consumer names, delivery times and counts. Retained durable backlog memory is approximately the sum of retained entry sizes plus per-entry overhead. For a durable key with an active registered group there is intentionally **no time or length ceiling** that may remove entries the group still needs (§34), so retained memory is **not** bounded by retention: a stale or offline group lets the backlog grow until the group catches up, its obligation is governed out and the group retired (§38), or Redis reaches its configured `maxmemory`. Under `noeviction` that limit produces explicit write refusal (`OOM` → `TRANSPORT_UNAVAILABLE`, §41); the relay defers and the PostgreSQL outbox backlog grows instead. Only groupless durable keys (§35) and SIGNAL keys (§36) are bounded by their retention. No destructive ceiling is introduced. Sizing and headroom are 7K's (HE-7K-02). |
| SIZ-05 | Large entries are not split across entries. One durable event is one stream entry. |

---

## 23. Durable Acceptance (`CONFIRMED`)

### 23.1 Definition

| ID | Rule |
|---|---|
| ACC-01 | `CONFIRMED(transport_ref)` for one entry means: the entry was appended by `XADD` on the primary that owns its key **and** the 7E durability acknowledgement for that same entry succeeded on that same primary's issuing connection: `WAITAOF 1 1 <bounded timeout>` returned local ≥ 1 **and** replicas ≥ 1 (§23.5). Once confirmed, the entry survives every inside-model fault (§11) and remains available for at-least-once delivery to every consumer group of its stream. |
| ACC-02 | **`XADD` alone is never `CONFIRMED`** (MF-01; 7D TPT-02, PRB-05). An entry ID with a failed, partial or timed-out acknowledgement is `UNKNOWN`. |
| ACC-03 | **`CONFIRMED` ≠ consumed.** It does not mean any group read, processed or acknowledged the entry, that Billing or Analytics processed it, that a webhook was delivered or that any side effect happened (§42). |
| ACC-04 | Acceptance never waits for any consumer group, any `XACK` or any consumer availability (§42). |
| ACC-05 | The acknowledgement `WAITAOF 1 1` (§23.5) satisfies FMD-05: local fsync on the primary and fsync on its replica. |

### 23.2 Per-entry outcome

| ID | Rule |
|---|---|
| ACC-06 | The adapter returns exactly one outcome per submitted entry (7D TPT-01): `CONFIRMED`, `ROW_REJECTED`, `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED` or `UNKNOWN` (§25). A batch or pipeline is never confirmed as a unit (7D PBT-01 … PBT-03). |
| ACC-07 | Entries routed to the same primary MAY be pipelined on one connection as `XADD e1 … XADD ek` followed by one `WAITAOF 1 1`. Because `WAITAOF` covers all previous writes on that connection (MF-03, MF-04) and replication offsets are monotonic, a successful acknowledgement confirms each preceding `XADD` that returned an entry ID; each entry still receives its own outcome, and an `XADD` that returned an error is classified individually (§25). |
| ACC-08 | Entries routed to different primaries are published on different connections with their own acknowledgement; the result on one primary never affects the outcome of an entry on another. |

### 23.3 Connection affinity

| ID | Rule |
|---|---|
| AFF-01 | The acknowledgement command (`WAITAOF 1 1`, §23.5) MUST be sent on the **same connection**, to the **same node**, that executed the `XADD` it is meant to cover, and after that `XADD` in the connection's command order. Pipelining (sending `WAITAOF` before the `XADD` replies are read) is permitted, because Redis executes one connection's commands in order, so `WAITAOF` always covers every `XADD` sent before it on that connection. An acknowledgement on another connection or another node proves nothing about the entry and MUST NOT produce `CONFIRMED`. |
| AFF-02 | The adapter holds one dedicated connection per primary per publish exchange. No other client shares that connection during the exchange. |
| AFF-03 | If the connection breaks after an `XADD` reply and before the acknowledgement reply, every entry written on it in that exchange is `UNKNOWN`. |
| AFF-04 | If a failover occurs between `XADD` and the acknowledgement, the acknowledgement either fails on the demoted node or reports insufficient counts; the entries are `UNKNOWN`. |
| AFF-05 | The Redis Cluster client used by the adapter MUST support sending the keyless `WAITAOF` command on an explicitly chosen node connection, the same one that carried the `XADD`s. A client that routes keyless commands to an arbitrary node, or that hides connection identity, MUST NOT be used for the durable adapter; if no conforming client is available the relay is not production-ready (IO-7E-08 blocker). |

### 23.4 What acceptance never relies on

| ID | Rule |
|---|---|
| ACC-09 | No Redis `MULTI` / `EXEC`, Lua script or function is used for acceptance (7D LOOP-03, PBT-04). |
| ACC-10 | No PostgreSQL transaction is open during acceptance (7D LOOP-01). |
| ACC-11 | Acceptance never reads a stream back to "verify" an entry (TPT-10); verification-by-read cannot prove survival of a later fault. |
| ACC-12 | RDB snapshots, S3 backups and cross-region copies are never part of acceptance. |

### 23.5 Acknowledgement command, thresholds and adapter algorithm (OD-7E-02 = A)

#### 23.5.1 Rules

| ID | Rule |
|---|---|
| WAO-01 | The durability acknowledgement is `WAITAOF 1 1 <timeout_ms>` sent on the **same client connection to the same primary** that executed the preceding `XADD`(s) (AFF-01). |
| WAO-02 | **Success criterion.** The reply is a two-element array `[numlocal, numreplicas]`. Durability is established for the covered entries **only if `numlocal ≥ 1` and `numreplicas ≥ 1`**. Any other reply — including `[1, 0]`, `[0, 1]`, `[0, 0]` — is a shortfall. |
| WAO-03 | **Timeout is never success.** `timeout_ms` is a positive integer (never `0`, which would block indefinitely, MF-19) no greater than the remaining publish timeout supplied by the relay (7D TPT-07) minus a configured margin; if no positive value fits, the batch is not sent (`NOT_ATTEMPTED`). When it expires `WAITAOF` returns the counts reached; a shortfall is `UNKNOWN`. The client socket read timeout is longer than `timeout_ms`; if the socket times out first, the outcome is `UNKNOWN`. |
| WAO-04 | **Per shard, never across shards.** A `WAITAOF` result applies only to `XADD`s issued earlier on that same connection. A result obtained on one shard's connection MUST NOT be used to confirm an entry routed to another shard. |
| WAO-05 | **Shortfall or uncertainty → `UNKNOWN`.** If an `XADD` returned an entry ID (or may have been executed) and the WAO-02 criterion is not positively established for it, the entry is `UNKNOWN` (CL-12 … CL-17, CL-20). The relay then never marks its row `PUBLISHED` (7D PRB-02, PRB-05); a later attempt republishes the same `event_id` (duplicate, allowed; consumer idempotency, 7F). |
| WAO-06 | **No terminal outcome from confirmation failure.** No `WAITAOF` result, timeout or error ever yields `ROW_REJECTED` (CLS-01). |
| WAO-07 | **No other mechanism.** No `WAIT`-only confirmation, no `appendfsync always`, no `MULTI` / `EXEC`, no Lua or function, no Redis-side dedup, no read-back verification and no distributed transaction is used to establish or "improve" acceptance (ACC-09 … ACC-12). |
| WAO-08 | The stream entry ID returned by `XADD` is transport position only (ENT-04). `event_id` inside `env` remains the immutable idempotency identity. |

#### 23.5.2 Startup and deployment capability gate

| ID | The adapter MUST refuse to claim durable-transport capability (and the relay MUST NOT start publishing durable rows) if any of these is not established |
|---|---|
| CAP-01 | Every event-transport node runs Redis Open Source **7.2 or later** (`INFO server` `redis_version`). |
| CAP-02 | The `WAITAOF` command is available (`COMMAND INFO WAITAOF` returns it) and permitted for the relay's ACL user. |
| CAP-03 | AOF is enabled on every primary and every replica that owns or replicates a durable key (`INFO persistence` `aof_enabled:1`; last AOF write status OK). |
| CAP-04 | **Total shard replica membership is exactly one, and that replica is the one the primary replicates to.** For every shard that owns at least one active-generation durable key, `shard_capable` (below) proves from cluster topology (`CLUSTER SHARDS`, cross-checked with `CLUSTER NODES`, queried on the shard's primary): (1) exactly one primary-role member; (2) total replica-role members = exactly 1, counting members in **any** state; (3) no second replica member exists in online, failed, `fail?`, loading, handshake, disconnected or any other recoverable or configured state; (4) the sole replica is online; and, from `INFO replication` on the primary and the replica: (5) the sole replica is connected and within the lag bound; (6) AOF is enabled and healthy on the primary and on the sole replica (CAP-03); (7) the replica reported by the primary's `INFO replication` is the same node as the topology's sole replica (same announced endpoint) and the replica reports that primary as its master; (8) the sole replica is automatic-failover eligible: `CLUSTER NODES` shows no `nofailover` flag on it (runtime-observable), and the deployment attestation of CAP-07 has verified `cluster-replica-no-failover no` on it (TOPO-11). `INFO replication` alone (for example `connected_slaves = 1`) is never proof of (2) or (3). Any failure → not capable (CL-21: `TRANSPORT_UNAVAILABLE` before any durable write) (TOPO-02, FMD-09, MF-21). |
| CAP-05 | Every primary **and every sole replica** of every active-generation durable shard reports `maxmemory_policy:noeviction` (`INFO memory`, read on each node; enforced inside `shard_capable`). Any other value on either node — `allkeys-*`, `volatile-*` or anything else — makes the shard NOT CAPABLE (TOPO-05, FMD-10). Checking primaries alone is never sufficient. |
| CAP-06 | Cluster state is OK and every durable key slot of the active generation has an online primary (`CLUSTER INFO`, `CLUSTER SHARDS`). |
| CAP-07 | The deployment-verification step (IO-7E-01, run by the operations role with `CONFIG GET`) has confirmed `appendfsync everysec`, `min-replicas-to-write 1`, `cluster-allow-replica-migration no`, `cluster-replica-no-failover no`, `cluster-replica-validity-factor` non-zero (default `10`, TOPO-12), the configured `maxmemory` **and** `maxmemory-policy noeviction` on **every event-transport Redis node** (primaries and replicas alike) for the deployed configuration revision. The relay credential needs no `CONFIG` privilege: startup relies on this attestation, and runtime checks use the observable `nofailover` flag (CAP-04 (8), HP-05). |
| CAP-08 | **Startup precondition.** The relay entrypoint establishes CAP-01 … CAP-07 through the adapter before it starts any claim loop; until then it reports not-ready, retries the check with backoff and claims nothing. This is a precondition of the transport adapter and does not alter the 7D loop (liveness still does not depend on Redis, 7D SHD-08). |
| CAP-09 | **After startup.** CAP-01 … CAP-06 are re-checked by the health probe (HP-01 … HP-08), and after every topology refresh or failover the roles are refreshed and the checks re-run against the new primary and its replica (FMD-10). If capability is lost, `publish` returns `TRANSPORT_UNAVAILABLE` (CL-21), the 7D gate opens, and the probe stays UNHEALTHY until capability returns; no row can become `FAILED` (CLS-01). |

Shard membership check used by CAP-04 and HP-05 (normative):

```text
shard_capable(shard) -> bool          -- for every shard owning >= 1 active-generation durable key slot
    topo  := CLUSTER SHARDS on the shard's primary, cross-checked with CLUSTER NODES
    members   := every node listed for the shard in EITHER view, in ANY state
    primaries := [n in members where n.role == primary]
    replicas  := [n in members where n.role == replica]     -- online, failed, fail?, loading, handshake, disconnected: all count
    if count(primaries) != 1: return false
    if count(replicas)  != 1: return false                  -- TOTAL membership == 1 (never "connected replicas")
    r    := replicas[0]
    if r.health != online: return false
    info := INFO replication on primaries[0]
    if info.connected_slaves != 1: return false
    if endpoint(info.slave0) != endpoint(r): return false   -- same replica in topology and replication views
    if info.slave0.state != online or info.slave0.lag > LAG_BOUND: return false
    if ROLE on r does not name primaries[0] as its master with link up: return false
    p := primaries[0]
    if maxmemory_policy(p) != "noeviction": return false     -- INFO memory on the current primary (TOPO-05)
    if maxmemory_policy(r) != "noeviction": return false     -- INFO memory on the failover candidate (FMD-10)
    if attestation(p).maxmemory_policy != "noeviction" or attestation(r).maxmemory_policy != "noeviction": return false   -- CAP-07
    if "nofailover" in r.flags: return false                  -- CLUSTER NODES flag; TOPO-11 automatic-failover eligibility
    if attestation(r).cluster_replica_no_failover != "no": return false   -- CAP-07 deployment verification (CONFIG GET by operations role)
    if not aof_healthy(primaries[0]) or not aof_healthy(r): return false
    return true
capability_established() := CAP-01 … CAP-03, CAP-05 … CAP-07 hold and shard_capable(s) for every durable shard s
```

Decision table (each case is one durable shard; "capable" requires every condition):

| Case | Primary members | Replica members (state) | Primary `connected_slaves` | Replication view names the topology replica | Lag within bound | AOF healthy on both | `nofailover` flag absent | `cluster-replica-no-failover` attested `no` | Primary `maxmemory_policy` | Replica `maxmemory_policy` | Result |
|---|---:|---|---:|---|---|---|---|---|---|---|---|
| T-01 | 1 | 1 (online) | 1 | yes | yes | yes | yes | yes | noeviction | noeviction | CAPABLE |
| T-02 | 1 | 0 | 0 | n/a | n/a | yes | n/a | n/a | noeviction | n/a | NOT CAPABLE |
| T-03 | 1 | 2 (online, online) | 2 | yes | yes | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-04 | 1 | 2 (online, failed) | 1 | yes | yes | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-05 | 1 | 2 (online, loading) | 1 | yes | yes | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-06 | 1 | 2 (online, disconnected) | 1 | yes | yes | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-07 | 1 | 1 (loading) | 0 | no | n/a | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-08 | 1 | 1 (online) | 1 | no | yes | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-09 | 1 | 1 (online) | 1 | yes | no | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-10 | 1 | 1 (online) | 1 | yes | yes | no | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-11 | 2 | 1 (online) | 1 | yes | yes | yes | yes | yes | noeviction | noeviction | NOT CAPABLE |
| T-12 | 1 | 1 (online) | 1 | yes | yes | yes | no | yes | noeviction | noeviction | NOT CAPABLE |
| T-13 | 1 | 1 (online) | 1 | yes | yes | yes | yes | no | noeviction | noeviction | NOT CAPABLE |
| T-14 | 1 | 1 (online) | 1 | yes | yes | yes | yes | yes | allkeys-lru | noeviction | NOT CAPABLE |
| T-15 | 1 | 1 (online) | 1 | yes | yes | yes | yes | yes | noeviction | allkeys-lru | NOT CAPABLE |
| T-16 | 1 | 1 (online) | 1 | yes | yes | yes | yes | yes | noeviction | volatile-lru | NOT CAPABLE |

Role change (post-failover) sequence for one shard whose primary P and replica R were both `noeviction` and CAPABLE (T-01):

| Step | State after automatic failover | Promoted primary `maxmemory_policy` | Replica members of the shard | Result |
|---|---|---|---|---|
| RC-01 | R promoted; former primary P still down | noeviction | 0 | NOT CAPABLE |
| RC-02 | P rejoined as the sole replica, online, connected, within lag, AOF healthy, failover-eligible | noeviction | 1 (noeviction) | CAPABLE |
| RC-03 | P rejoined as the sole replica but reports an eviction-capable policy | noeviction | 1 (allkeys-lru) | NOT CAPABLE |

Because R was prevalidated as `noeviction` before any entry was confirmed (T-01), promotion can never produce an eviction-capable durable primary; a hypothetical promoted primary reporting any other policy fails `shard_capable` like T-14. Capability is re-established only at RC-02, when the whole post-failover topology again satisfies FMD-09 and FMD-10.

T-04 … T-06 are the cases a connected-replica check would wrongly accept: `connected_slaves = 1`, yet a second configured replica exists and could later be promoted. T-12 and T-13 are a seemingly healthy sole replica that is not automatic-failover eligible (`nofailover` flag, or `cluster-replica-no-failover yes` attested); they are never CAPABLE. T-14 … T-16 are eviction-policy failures: the policies shown are illustrative, and every value other than `noeviction`, on the primary or on its failover replica, is NOT CAPABLE.

#### 23.5.3 Adapter algorithm (normative order)

```text
publish(entries: list[(event_id, route, envelope_bytes)], timeout) -> map[event_id -> Outcome]
    -- called by the 7D relay loop after its claim transaction committed (7D §19); no DB txn is open
    deadline := now() + timeout
    outcome  := {}                                        -- exactly one outcome per event_id at return
    if not capability_established():                      -- §23.5.2; configuration-wide (7D §22.2)
        for e in entries: outcome[e.event_id] := TRANSPORT_UNAVAILABLE           -- CL-21; gate opens
        return outcome

    -- 1. group the claimed batch (up to 50 rows, 7D POL-01) by target primary
    groups := map[primary_node -> ordered list of entries]
    for e in entries:                                     -- route already resolved by route_for (§20)
        node := slot_map.primary_for(slot(e.route.physical_key))   -- NS-06, RTE-08
        groups[node].append(e)

    -- 2. one transport batch per primary connection; shards are independent (ACC-08, WAO-04)
    for (node, batch) in groups (MAY run concurrently across nodes):
        pending_ack := {}                                 -- per primary batch; never shared across shards
        t_ms := remaining_ms(deadline) - margin_ms
        if t_ms < 1:                                      -- no positive WAITAOF timeout fits (WAO-03)
            outcome[e] := NOT_ATTEMPTED for every e in batch; continue                 -- CL-01
        conn := dedicated_connection(node)                -- AFF-02: not shared during the exchange
        try:
            pipeline on conn:
                for e in batch:
                    XADD e.route.physical_key * fmt "durable.v1" env e.envelope_bytes   -- §21.1, no MAXLEN
                WAITAOF 1 1 t_ms                          -- WAO-01, WAO-03 (positive, bounded)
            read replies in order
        except connection failure:
            outcome[e] := NOT_ATTEMPTED for entries never written to the socket      -- CL-01
            outcome[e] := UNKNOWN for entries already written                         -- CL-12, CL-13, CL-17
            continue
        except client read timeout:
            outcome[e] := UNKNOWN for every entry of this batch not yet classified; continue   -- CL-15

        redirected := []
        for e, reply in zip(batch, xadd_replies):
            if reply is entry_id:          pending_ack[e] := entry_id
            elif reply is MOVED:           redirected.append(e)                  -- RED-01 (not executed)
            else:                          outcome[e] := classify_error(reply)  -- §25 (never ROW_REJECTED)

        (numlocal, numreplicas) or error := waitaof_reply
        for e in pending_ack:
            if waitaof_reply is array and numlocal >= 1 and numreplicas >= 1:
                outcome[e] := CONFIRMED(e.route.physical_key + "/" + pending_ack[e])   -- CL-18
            else:
                outcome[e] := UNKNOWN                                           -- CL-14 / CL-15 / CL-16 (WAO-05)

        -- 3. MOVED: refresh slot map; re-issue once on the NEW owner's connection, with its own WAITAOF
        if redirected not empty and now() < deadline:
            slot_map.refresh()
            regroup redirected by new primary; repeat step 2 once for them       -- RED-01, RED-02
        for e in redirected still unclassified: outcome[e] := TRANSPORT_UNAVAILABLE

    for e in entries not in outcome: outcome[e] := NOT_ATTEMPTED                -- e.g. deadline reached
    return outcome                                                              -- 7D §22 classifies; 7D §24 marks
```

| ID | Rule |
|---|---|
| ALG-01 | The relay's claim batch (7D: a unit of claiming only, PBT-01) is split into one transport batch per target primary. A 50-row claim touching, for example, the `voice`, `crm` and `campaign` keys produces one pipelined exchange per primary owning those keys' slots, each ending with its own `WAITAOF 1 1`; every `event_id` still receives its own outcome. |
| ALG-02 | Several keys on the same primary MAY share one exchange and one `WAITAOF` (it covers every earlier write on the connection, MF-04). Entries on different primaries never share one. |
| ALG-03 | Concurrency across primaries is allowed; the result of one primary's exchange never changes another's outcomes. |
| ALG-04 | After `publish` returns, 7D alone records progress: `fn_mark_outbox_published` for `CONFIRMED`; deferral or lease expiry for `UNKNOWN`, `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED` (7D DSP-01 … DSP-07). The adapter never touches PostgreSQL (ROLE-06). |
| ALG-06 | `publish` receives only entries that obtained a Route from `route_for`; an entry without a valid Route (including any NULL-`aggregate_id` row) never reaches `XADD`. If an implementation defect passed one, the adapter returns `NOT_ATTEMPTED` with a defect anomaly (CL-19) and sends nothing. |
| ALG-05 | The relay's local deadline and lease (7D LSE-03 … LSE-06) bound `timeout`; because `WAITAOF` under `everysec` can wait for an fsync cycle, the lease and safety margin must cover it. 7K benchmarks the interaction (HE-7K-08); 7E fixes no throughput number. |

---

## 24. Cluster Redirects and Failover Handling

| ID | Rule |
|---|---|
| RED-01 | `MOVED` on `XADD`: the command was not executed (MF-17). The adapter refreshes its slot map and MAY re-issue that `XADD` once, on the new owner's connection, within the same publish call and remaining timeout; the acknowledgement for it is then sent on that new connection (AFF-01). If the re-issue cannot complete in time, the entry is `TRANSPORT_UNAVAILABLE` (no write happened) — never `ROW_REJECTED`. |
| RED-02 | At most one topology refresh and one re-issue per entry per publish call. Repeated redirects are `TRANSPORT_UNAVAILABLE`. The bound is fixed so behaviour is deterministic; it never consumes outbox retry budget (all such outcomes are non-terminal, 7D DSP-03). |
| RED-03 | `ASK` on a durable key: durable stream keys are never live-migrated (LCY-06), so `ASK` indicates an ungoverned slot migration. The adapter does **not** follow it for durable writes; the entry is `TRANSPORT_UNAVAILABLE` and an anomaly is recorded (§49.4). The SIGNAL publisher drops and counts on `ASK`. |
| RED-04 | `READONLY` (write sent to a replica), `CLUSTERDOWN`, `TRYAGAIN`, `MASTERDOWN`, `LOADING`: definite non-acceptance → `TRANSPORT_UNAVAILABLE` and a topology refresh. |
| RED-05 | Redirects and failovers never produce `ROW_REJECTED` and never burn an outbox row's budget: every redirect-related outcome is non-terminal. |
| RED-06 | The adapter's slot map is refreshed on any redirect, on any connection error, and by the health probe (§26). A stale map can only cause `MOVED` (handled by RED-01), never a write to a wrong key. |

---

## 25. Outcome Classification Table (HO-7E-04)

Default rule (7D TPT-08, OUTC-01): **anything not positively classified below as `ROW_REJECTED` is `TRANSPORT_UNAVAILABLE` (definitely not accepted) or `UNKNOWN` (may have been accepted).**

| # | Condition | Was the entry possibly written? | Outcome | Gate (7D GATE-02) |
|---|---|---|---|---|
| CL-01 | Entry never sent (connection failed earlier in the exchange, local deadline, shutdown, adapter encoding defect before send) | No | `NOT_ATTEMPTED` | Opens if connection-caused |
| CL-02 | Connection refused, DNS failure, TLS failure | No | `TRANSPORT_UNAVAILABLE` | Opens |
| CL-03 | Authentication / ACL failure (`NOAUTH`, `WRONGPASS`, `NOPERM`) | No | `TRANSPORT_UNAVAILABLE` (configuration-wide) | Opens |
| CL-04 | `CLUSTERDOWN`, cluster state not OK | No | `TRANSPORT_UNAVAILABLE` | Opens |
| CL-05 | `MOVED` not resolved within RED-01 / RED-02 | No | `TRANSPORT_UNAVAILABLE` | Opens |
| CL-06 | `ASK` on a durable key | No | `TRANSPORT_UNAVAILABLE` + anomaly | Opens |
| CL-07 | `READONLY`, `MASTERDOWN`, `LOADING`, `TRYAGAIN`, `BUSY` | No | `TRANSPORT_UNAVAILABLE` | Opens |
| CL-08 | `NOREPLICAS` (min-replicas not met) | No | `TRANSPORT_UNAVAILABLE` | Opens |
| CL-09 | `OOM` (memory refusal under non-evicting policy) | No | `TRANSPORT_UNAVAILABLE` (§41) | Opens |
| CL-10 | `WRONGTYPE` (key holds a non-stream value) | No | `TRANSPORT_UNAVAILABLE` (keyspace defect affecting every entry of the route) + anomaly | Opens |
| CL-11 | Size / protocol rejection of a valid entry (misconfigured limit, TOPO-09) | No | `TRANSPORT_UNAVAILABLE` (configuration-wide) | Opens |
| CL-12 | Timeout after `XADD` was sent, before its reply | Maybe | `UNKNOWN` | Opens |
| CL-13 | Connection reset after `XADD` was sent | Maybe | `UNKNOWN` | Opens |
| CL-14 | `XADD` returned an ID; `WAITAOF 1 1` returned `numlocal < 1` or `numreplicas < 1` | Yes | `UNKNOWN` | Opens (a shortfall means replica or persistence capability is missing, which is not entry-specific) |
| CL-15 | `XADD` returned an ID; `WAITAOF` timeout elapsed with a shortfall, or the client read timed out first | Yes | `UNKNOWN` | Opens |
| CL-16 | `XADD` returned an ID; `WAITAOF` returned an error (for example AOF disabled on the primary, command not permitted, node demoted to replica) | Yes | `UNKNOWN` + capability anomaly (CAP-*) | Opens |
| CL-17 | `XADD` returned an ID; connection broke before the `WAITAOF` reply | Yes / maybe | `UNKNOWN` | Opens |
| CL-18 | `XADD` returned an ID and the `WAITAOF 1 1` issued afterwards on the same connection returned `numlocal ≥ 1` and `numreplicas ≥ 1` | Yes | `CONFIRMED(<key>/<entry ID>)` | — |
| CL-21 | Adapter capability not established (CAP-01 … CAP-07 failed: Redis < 7.2, `WAITAOF` unavailable, AOF disabled, replica topology wrong, sole replica not automatic-failover eligible (`nofailover` / `cluster-replica-no-failover yes`), `maxmemory-policy` other than `noeviction` on a durable primary or on its failover replica); nothing is sent, even if `XADD` would currently succeed | No | `TRANSPORT_UNAVAILABLE` (configuration-wide, as 7D §22.2 lists configuration failures) | Opens; probe UNHEALTHY |
| CL-19 | Route present but resolves to an invalid key (adapter defect) | No | `NOT_ATTEMPTED` + defect anomaly | No (not a connection failure) |
| CL-20 | Any unrecognized error | Unknown | `UNKNOWN` | Opens |

| ID | Rule |
|---|---|
| CLS-01 | **7E enumerates zero `ROW_REJECTED` categories for V1.** No Redis response to a valid entry produced from a committed row is specific to that entry: `XADD *` with two fields cannot fail on content, size limits are above the physical maximum (SIZ-03), and every key-level, configuration-level or capacity-level error affects every entry of its route. Therefore the adapter never returns `ROW_REJECTED`, and no transport outcome can move a row to `FAILED` (7D DSP-04 remains available only if a future governed 7E amendment proves an entry-specific category). |
| CLS-02 | A pattern of identical non-terminal categories is surfaced for operators (7D GATE-09; §49.4), never escalated to `ROW_REJECTED`. |
| CLS-03 | An `UNKNOWN` never becomes `CONFIRMED` and never becomes a drop (7D OUTC-02). Republication creates a duplicate entry with the same `event_id`, which consumers deduplicate (7F). |
| CLS-04 | Error text from Redis is never copied into `last_error`; only the 7D safe category code is (7D DSP-08). |

---

## 26. Health Probe

### 26.1 Contract

`health_probe() -> HEALTHY | UNHEALTHY` answers one question: **can the transport currently satisfy the durable-acceptance contract for every durable key of the active generation?** It never claims outbox rows, never writes a stream entry, never writes a business event and never writes any key (7D GATE-04).

### 26.2 Checks (all must pass for HEALTHY)

| # | Check | Command family (read-only) |
|---|---|---|
| HP-01 | Connection and authentication to the cluster seed nodes succeed under the relay's credential | connect, `AUTH`, `PING` |
| HP-02 | `cluster_state:ok` | `CLUSTER INFO` |
| HP-03 | Routing table and shard membership refreshed: every slot of the target set (§26.3) has exactly one primary, marked online, and the full member list of each target shard (every node in any state) is enumerated with its `CLUSTER NODES` flags, including `nofailover` | `CLUSTER SHARDS`, `CLUSTER NODES` |
| HP-04 | Each target primary answers, reports role `master`, and is writable-capable (not `LOADING`) | `PING`, `ROLE` |
| HP-05 | `shard_capable` holds for every target shard: total replica membership exactly one in any state (no second online, failed, loading or disconnected replica), that replica online, connected, within the lag bound, and identical to the replica in the primary's replication view, and the sole replica carries no `nofailover` flag in `CLUSTER NODES` (automatic-failover eligible, TOPO-11) (CAP-04, TOPO-02, FMD-09). A connected-replica count alone never satisfies HP-05; a `nofailover` flag on the sole replica makes the probe UNHEALTHY, exactly as it makes CAP-04 fail | `CLUSTER SHARDS` / `CLUSTER NODES` for membership; `INFO replication` and `ROLE` for connection, identity and lag |
| HP-06 | AOF is enabled and its last write status is OK on each target primary and each counted replica | `INFO persistence` |
| HP-07 | Each target primary is below its `maxmemory` limit (a full non-evicting node would refuse `XADD` with `OOM`) and reports `maxmemory_policy:noeviction`, **and its sole replica also reports `maxmemory_policy:noeviction`** (the replica need not enforce `maxmemory` while it is a replica; its configured policy must be safe when its role changes, FMD-10). An eviction-capable policy on the primary or on the replica makes the probe UNHEALTHY before another durable publication is attempted | `INFO memory` on the primary and on its replica |
| HP-08 | Capability prerequisites still hold: Redis 7.2+ on target nodes and `WAITAOF` available (CAP-01, CAP-02) | `INFO server`, `COMMAND INFO` |

| ID | Rule |
|---|---|
| HPR-01 | `PING` alone is never sufficient. A probe that cannot verify HP-05 or HP-06 returns UNHEALTHY. |
| HPR-02 | The probe returns UNHEALTHY if **any** target shard fails a check. One unhealthy shard therefore pauses durable claiming for that relay loop until it recovers (7D gate is per loop, not per route). This is conservative: no loss, at most one batch of `attempt_count` inflation per outage onset (7D GATE-06), and no `ROW_REJECTED` exists (CLS-01). The availability cost of one-shard pauses is a 7K concern (HE-7K-05). |
| HPR-03 | The probe does not test consumer groups; consumer availability never affects acceptance (§42). |
| HPR-04 | The probe interval and backoff are 7J / 7K values (7D GATE-04). |
| HPR-05 | The probe is never run by the SIGNAL publisher and never on the Voice hot path (§47). |

### 26.3 Target set

The target set is the set of primaries (and their replicas) that currently own the hash slots of the active generation's durable keys: in V1 the 11 durable keys of §15.4 (NS-08). During a generation migration (LCY-07) it is the union of both generations' durable keys. The SIGNAL key is not a probe target (HPR-05).

---
## 27. Fan-Out Model (ADR-7E-02)

| ID | Rule |
|---|---|
| FAN-01 | **One record, group fan-out.** A durable event is published once, as one entry in one stream key (§18, §20). Each independent consumer obligation reads it through its **own** consumer group on that key. |
| FAN-02 | Redis distributes the entries of one group among that group's consumers; it does not copy an entry to several consumers of the same group. Therefore two independent obligations (for example Billing usage ingestion and Analytics projections) MUST NEVER share one group; sharing would deliver each entry to only one of them (F7E-28). |
| FAN-03 | Per-consumer duplicate publication (one entry per consumer stream) is rejected: it would turn one outbox row into several transport writes with several acceptance outcomes, making per-row `CONFIRMED` (7D TPT-01) either impossible or partial, and multiplying memory. No frozen evidence requires it. |
| FAN-04 | A new consumer obligation is added by creating a new group on the existing stream key(s) (§30), never by adding a route. |

---

## 28. Consumer Group Model

| ID | Rule |
|---|---|
| GRP-01 | A **logical consumer group** represents exactly one 7B consumer obligation (one CON entry, or a 7B-catalogued SIGNAL consumer). All worker replicas of that obligation join the same group as distinct consumers. |
| GRP-02 | Independent obligations use independent groups (FAN-02). Several handlers of one CON entry share its group **only** while one dispatcher in that consumer is responsible for completing every required handler for an entry before that entry is acknowledged; if 7F designs independently acknowledged handlers inside one CON, each such handler needs its own group through a governed 7E registry change **before** activation (HE-7F-06). |
| GRP-03 | Group name format: `cg.<owner>.<obligation>` for durable groups and `sg.<owner>.<obligation>` for SIGNAL groups; lowercase ASCII letters, digits, hyphen and dot only; fixed in the registry (§29). |
| GRP-04 | Group names never contain a pod ID, host name, replica index, deployment revision, image tag, release version, tenant ID, user-controlled input or timestamp. Group identity is stable across restarts, rolling deploys, scale-to-zero and scale-out. |
| GRP-05 | One logical group subscribes to one or more family streams. On each stream key it subscribes to, the Redis group has the same name. Under PF-1 partitioning (OD-7E-03 = B) the group exists on every partition key of each subscribed family; the logical group spans partitions and each key keeps its own Redis group state. In V1 (`P_f = 1`) each subscription is exactly one key. |
| GRP-06 | Consumer names (members inside a group) MAY be instance-specific: `<runtime-role>/<region-tag>/<instance-uuid>`. They contain no tenant data, credential or secret. |
| GRP-07 | Durable groups MUST NOT read with `NOACK`. `NOACK` removes the PEL guarantee and would let the trim watermark (§34) pass undelivered-and-unprocessed entries. SIGNAL groups MAY use `NOACK` (loss allowed). |
| GRP-08 | A group acknowledges every entry delivered to it, including entries of types it has no handler for. For an unsubscribed type there is no handler obligation; the acknowledgement timing for such entries is a 7F rule (HE-7F-03). An unacknowledged entry pins retention for its stream (§34). |
| GRP-09 | Groups are created only by the provisioning step (§30), never lazily by a consumer at runtime with `$`. |
| GRP-10 | A consumer member that is removed (`XGROUP DELCONSUMER`) MUST first have zero pending entries (its entries claimed by another member), because deletion makes its pending entries unclaimable (MF-15). |

---

## 29. Current Consumer-Group Registry

Derived **only** from 7B §22 CON-01 … CON-11 and 7C SIG-R06. No future consumer is invented. CCPU names (`call.started`, `usage.event_recorded`; 7B §32.5) are not in the 107-pair manifest, have no route and no group.

### 29.1 Durable groups

| Group | 7B consumer | Owner | Exact types it must receive (current) | Subscribed logical streams | Status |
|---|---|---|---|---|---|
| `cg.identity.session-denylist` | CON-01 | Identity (6B) | `identity.forced_revocation_required` | LS-D-IDN | CURRENT |
| `cg.compliance.default-policy-seeding` | CON-02 | Compliance (6C) | `organization.created` | LS-D-ORG | CURRENT |
| `cg.compliance.active-policy-pointer` | CON-03 | Compliance (6C) | `compliance.policy_activated` | LS-D-CMP | CURRENT |
| `cg.crm.call-history` | CON-04 | CRM (6G) | `call.ended`, `conversation.qualification_set`, `conversation.summarization_completed` | LS-D-VOX | CURRENT |
| `cg.campaign.record-call-outcome` | CON-05 | Campaign (6H) | `call.ended`, `call.failed`, `conversation.qualification_set` | LS-D-VOX | CURRENT |
| `cg.billing.usage-ingestion` | CON-06 | Billing (6K) | `call.ended`, `conversation.completed`, `document.indexed`, `campaign.contact.call_attempted`, `workflow.execution.completed` | LS-D-VOX, LS-D-KNW, LS-D-CPN, LS-D-WFL | CURRENT (EV-079 by OD-7B-01) |
| `cg.analytics.projections` | CON-07 (durable part) | Analytics (6L) | `call.ended`, `call.failed`, `contact.converted` | LS-D-VOX, LS-D-CRM | CURRENT |
| `cg.voice.recording-object-cleanup` | CON-08 | Voice (6D) | `recording.deleted` | LS-D-VOX | CURRENT |
| `cg.knowledge.document-count` | CON-09 | Knowledge (6F) | `document.deleted`, `document.indexed` | LS-D-KNW | CURRENT |
| `cg.integrations.webhook-engine` | CON-10 | Integrations (6J) | `call.failed`, `call.transferred`, `contact.created`, `contact.qualified`, `contact.disqualified`, `deal.created`, `deal.won`, `deal.lost`, `appointment.booked`, `campaign.started`, `campaign.completed`, `campaign.contact.qualified`, `subscription.changed`, `invoice.generated`, `invoice.paid`, `payment.failed`, `usage.threshold_reached` | LS-D-VOX, LS-D-CRM, LS-D-CPN, LS-D-BIL | CURRENT |
| `cg.campaign.import-worker` | CON-11 | Campaign (6H) | `import.job_created` | LS-D-CPN | CURRENT |

### 29.2 SIGNAL group

| Group | 7B consumer | Owner | Exact types | Subscribed logical stream | Status |
|---|---|---|---|---|---|
| `sg.analytics.signal-projections` | CON-07 (SIGNAL part; DS-17, DS-19) | Analytics (6L) | `conversation.turn_completed`, `tool_execution.started`, `tool_execution.succeeded`, `tool_execution.failed` | LS-S-VOX | CURRENT (best-effort; PD2-03: `tool_execution.started` must be registered by Analytics before it is consumed — an Analytics-side rule, not a transport rule) |

### 29.3 Per-stream view

| Logical stream | Groups |
|---|---|
| LS-D-IDN | `cg.identity.session-denylist` |
| LS-D-ORG | `cg.compliance.default-policy-seeding` |
| LS-D-CMP | `cg.compliance.active-policy-pointer` |
| LS-D-VOX | `cg.crm.call-history`, `cg.campaign.record-call-outcome`, `cg.billing.usage-ingestion`, `cg.analytics.projections`, `cg.voice.recording-object-cleanup`, `cg.integrations.webhook-engine` |
| LS-D-AGT | none |
| LS-D-KNW | `cg.billing.usage-ingestion`, `cg.knowledge.document-count` |
| LS-D-CRM | `cg.analytics.projections`, `cg.integrations.webhook-engine` |
| LS-D-CPN | `cg.billing.usage-ingestion`, `cg.integrations.webhook-engine`, `cg.campaign.import-worker` |
| LS-D-WFL | `cg.billing.usage-ingestion` |
| LS-D-INT | none |
| LS-D-BIL | `cg.integrations.webhook-engine` |
| LS-S-VOX | `sg.analytics.signal-projections` |

Totals: 11 logical durable groups; 18 (durable group, logical stream) subscriptions; 1 SIGNAL group with 1 subscription. With `P_f = 1` in `g1`, the physical Redis group placements are exactly **18 on the 11 durable keys and 1 on the SIGNAL key (19 in total)**; with `P_f > 1` in a later generation they become `Σ subscriptions × P_f` and nothing else changes. Every one of the 31 CURRENT_CONSUMED events reaches every 7B consumer that consumes it (cross-checked against §18.2 and 7B §22 consumed-event union). No Billing group exists on LS-S-VOX.

---

## 30. Group Bootstrap

| ID | Rule |
|---|---|
| BST-01 | **Current V1 groups are created before relay activation.** A provisioning step creates every §29 group on every physical key of its subscribed streams with `XGROUP CREATE <key> <group> 0 MKSTREAM` — start position `0`, never `$`. |
| BST-02 | Relay activation for a generation is gated: no relay publishes to a key whose registered groups do not all exist (IO-7E-13 deployment gate). |
| BST-03 | If a registered current group is found missing on a key after activation (incident), it is recreated at the oldest retained position (`0`), never `$`. Nothing was trimmed meanwhile, because the trim worker refuses to trim a key with a missing registered group (TRM-03). Re-delivered entries are duplicates handled by 7F. |
| BST-04 | **A future consumer** added after V1 gets a group through a governed registry change that states its start position explicitly. Historical backfill is a 7G replay decision; 7E applies no default backfill and never creates a new group at `0` on a stream with history merely because the group is new. During its creation the trim worker is paused for the affected keys (TRM-07). |
| BST-05 | SIGNAL group `sg.analytics.signal-projections` is created at `0` with `MKSTREAM` before the SIGNAL publisher is activated; loss before creation is permitted by contract. |
| BST-06 | Group creation is idempotent: `BUSYGROUP` (already exists) is success for provisioning; provisioning never resets an existing group's position (`XGROUP SETID` is never part of provisioning). |

---

## 31. Pending Entries (PEL) and Reclaim

| ID | Rule |
|---|---|
| PEL-01 | An entry delivered to a group consumer by `XREADGROUP` stays in that group's PEL until the group acknowledges it (`XACK`). Unacknowledged entries remain pending across consumer crashes and restarts. |
| PEL-02 | Abandoned ownership is reclaimable: another consumer of the **same** group takes over pending entries idle for at least a minimum idle time with `XAUTOCLAIM` (or `XCLAIM`), which increments the entry's delivery counter (MF-14). `XPENDING` exposes per-entry idle time and delivery count. |
| PEL-03 | Reclaim produces at-least-once redelivery. It never creates exactly-once processing (7A DEL-04). |
| PEL-04 | The minimum idle time, reclaim cadence, delivery-count limits, poison threshold, DLQ and parking are **7G's** (HE-7G-01). 7E fixes none of them. |
| PEL-05 | Durable PEL entries are never removed by trimming (§34) and never removed by `DELCONSUMER` while owned (GRP-10). |
| PEL-06 | PEL contents are transport state, not business state (ROLE-04). |

---

## 32. Acknowledgement (`XACK`) Boundary

| ID | Rule |
|---|---|
| ACK-01 | 7E defines **no** acknowledgement timing. In particular 7E does **not** define "acknowledge immediately after `XREADGROUP`". The processing transaction and when `XACK` is issued relative to side effects are **7F's** (HE-7F-02). |
| ACK-02 | An entry is **transport-complete for a group** only when that group has acknowledged it according to 7F. Until then it is pending (if delivered) or undelivered, and it is protected from trimming (§34). |
| ACK-03 | One group's acknowledgement never affects another group's obligation for the same entry. |

---

## 33. Ordering Contract (answers IO-7B-08; the 7B wording conflict is recorded in ORD-7E-10)

| ID | Guarantee or non-guarantee |
|---|---|
| ORD-7E-01 | **Stream append order.** Within one physical stream key, entry IDs are strictly increasing in the order the owning primary accepted the `XADD`s. This is the only order Redis Streams provides here. |
| ORD-7E-02 | **Group delivery order.** A group's `XREADGROUP ... >` delivers never-delivered entries of one key in ascending entry-ID order across the group as a whole. Different consumers of the group process concurrently, and reclaimed entries are redelivered later, so **processing order is not guaranteed even within one key**. |
| ORD-7E-03 | **No business-occurrence order.** Append order is not `occurred_at` order. |
| ORD-7E-04 | **No `event_id` order.** UUIDv7 `event_id` values are not transport positions and not an ordering guarantee. |
| ORD-7E-05 | **No database-commit order and no outbox-claim order.** Several relay loops publish disjoint claimed batches concurrently (7D SCL-01, SCL-02); a later-committed row can be appended before an earlier one. |
| ORD-7E-06 | **No same-aggregate causal order.** Partitioning by `aggregate_id` (PF-1) guarantees only **partition affinity**: within one topology generation all entries of one aggregate target the same key. It is **not** an aggregate sequence guarantee. 7D allows concurrent claim loops with `SKIP LOCKED` (7D SCL-01, SCL-02), so two events of one aggregate can reach Redis in an order different from their business or commit order, and a republished duplicate of an older event can be appended after newer ones (7D AMB-01). Redis preserves append order once commands arrive (ORD-7E-01); it cannot reconstruct an order already changed upstream. 7E therefore guarantees **no per-aggregate ordering**. |
| ORD-7E-07 | **No cross-stream or global order.** There is no global sequence, no central sequencer, no Redis `INCR` event sequence and no total order across keys, families or partitions (7A ORD-01). |
| ORD-7E-08 | Entry IDs embed the primary's millisecond clock but are transport positions only; they are never used as `occurred_at`, never as a business cursor and never compared across keys for ordering. |
| ORD-7E-09 | **Consumer rule (handed to 7F).** Consumer correctness MUST NOT depend on a guarantee the relay and transport cannot provide: consumers MUST NOT rely on arrival order, including within one aggregate; they use the owner's state machine, version or guarded transitions (7A ORD-02 … ORD-04). Any consumer-side ordering algorithm is 7F's (HE-7F-04). |
| ORD-7E-10 | **Recorded conflict, not resolved by 7E.** 7B IO-7B-08 says consumers "already assume only per-aggregate ordering", and 7B CR-04 says ordering is guaranteed "only as far as 7E defines per stream". The actual guarantee is ORD-7E-01 / ORD-7E-02 (append order per key) with no per-aggregate ordering (ORD-7E-06), which is consistent with frozen 7A ORD-05 and 7D SCL-02 but contradicts the IO-7B-08 wording. 7E does not edit 7B and does not treat the selection of `aggregate_id` partitioning as resolving the wording. The 7B text needs a controlled reconciliation describing the actual guarantee (CNF-7E-10, IO-7E-25), and 7F must design to ORD-7E-09 (HE-7F-04). |

---

## 34. Durable Retention — Safe-Trim Watermark (ADR-7E-08)

### 34.1 Rules

| ID | Rule |
|---|---|
| TRM-01 | **No blind `MAXLEN` and no time-only trimming on a durable key that has a group.** `XADD` to durable keys carries no `MAXLEN` / `MINID` option. Durable keys are trimmed only by the trim worker under the watermark below. |
| TRM-02 | **Watermark.** For durable key `K`, for every group `g` present on `K`: `bound(g) = min( smallest pending ID of g (if g has pending entries), the ID immediately after last-delivered-id of g )`. `W(K) = min over all present groups of bound(g)`. The trim worker issues `XTRIM K MINID W(K)` (exact or `~`; the `~` form never removes an ID ≥ `W`, MF-11). |
| TRM-03 | **Registered groups first.** If any group registered for `K` (§29, or a governed future registration) is absent from `K`, the trim worker does **not** trim `K` and records an anomaly. |
| TRM-04 | **Unregistered groups still pin.** A group present on `K` but not in the registry still participates in `W(K)`; its presence is an anomaly for operators, never a reason to ignore it. |
| TRM-05 | **Why it is safe.** Every entry with ID < `W(K)` has been delivered to every present group (it is ≤ each last-delivered-id) and is not pending in any group (it is below each smallest pending ID); because durable groups never use `NOACK` (GRP-07), "delivered and not pending" means "acknowledged". An entry is therefore never removed merely because it is old, because the stream is long, or because another group acknowledged it. |
| TRM-06 | **Race safety.** Between reading group state and `XTRIM`, each group's last-delivered-id only advances and every newly pending entry has an ID above the previous last-delivered-id, so `W(K)` computed earlier is still a safe bound. The only operations that can move a group backwards (`XGROUP SETID`, group re-creation) are governed (BST-03, TRM-07). |
| TRM-07 | **Governed operations pause trimming.** `XGROUP SETID` on a durable group (7G replay), future-group creation (BST-04) and group recreation (BST-03) are performed only with trimming paused for the affected keys. |
| TRM-08 | **Offline groups.** A group with no running consumer keeps its last-delivered-id and PEL; entries it has not acknowledged stay retained however long it is offline. |
| TRM-09 | A retention **floor** (keep entries at least a minimum age even after all groups acknowledged them, for diagnostics) MAY be configured by 7G / 7K. There is no retention **ceiling** that removes unacknowledged entries. |
| TRM-10 | Trimming never reads or depends on outbox state, and outbox cleanup never depends on stream state (7D CLN-05). |
| TRM-11 | The trim worker is a platform maintenance role with read access to group state and `XTRIM` on durable keys only; it is not hosted in the relay loop, in API request processes or in Voice media processes. Its cadence is 7K's; correctness does not depend on cadence. |

### 34.2 Memory consequence

A durable key's size is bounded by its slowest group. A stale or offline group grows memory without bound until it catches up or is retired (§38); the memory-exhaustion behaviour is §41. Sizing and backpressure are 7K's (HE-7K-03).

---

## 35. Retention of Durable Streams with No Consumer Group

| ID | Rule |
|---|---|
| GLR-01 | LS-D-AGT and LS-D-INT have no current group. With no group there is no consumer-delivery obligation to protect. Their keys are trimmed by the trim worker by entry age: `XTRIM K MINID ~ <ID for now − T_groupless>`. `T_groupless` is a 7K value. |
| GLR-02 | Transport retention is **not** business retention, audit retention, outbox retention (7-day `PUBLISHED` window), replay retention, DLQ retention or dedup-ledger retention (7A RS-03, §32.3). |
| GLR-03 | A future consumer does not gain entries published before its activation unless 7G decides a backfill (BST-04). |
| GLR-04 | The moment any group (registered or not) exists on a key, that key switches to watermark trimming (§34) and age-only trimming stops. |
| GLR-05 | Durable streams that do have groups also carry types with no consumer (for example `call.initiated` on LS-D-VOX); those entries are trimmed by the watermark after every group has acknowledged them (GRP-08). |

---

## 36. SIGNAL Stream Retention

| ID | Rule |
|---|---|
| SGR-01 | SIGNAL keys are bounded by approximate length trimming on every write: `XADD <key> MAXLEN ~ N_signal * …`. `N_signal` is a 7K value. |
| SGR-02 | Memory bound ≈ `N_signal` × (maximum SIGNAL entry size + per-entry overhead) per key. SIGNAL envelopes are small, fixed-shape objects (7C §21). |
| SGR-03 | When the Analytics SIGNAL group lags by more than the retained length, unread or pending SIGNAL entries are trimmed and lost. **This is accepted by contract** (7C SIG-R03; 7D CLD-02). `XAUTOCLAIM` reports such vanished pending IDs (MF-14); the consumer discards them. |
| SGR-04 | SIGNAL processing is never durability-authoritative: no Billing, compliance or financial outcome depends on it (7B CR-05; 7C PD1-02). |
| SGR-05 | SIGNAL trimming never touches a durable key (disjoint key sets, NS-03). |

---

## 37. Key TTL Rules

| ID | Rule |
|---|---|
| TTL-01 | **Durable stream keys never have a TTL.** No `EXPIRE`, `PEXPIRE`, `EXPIREAT` or `SET … EX` is ever applied to a durable key. Key expiry would delete every entry, every group and every PEL at once. |
| TTL-02 | Provisioning and the trim worker verify that durable keys report no TTL; a durable key found with a TTL is persisted back (`PERSIST`) and reported as an anomaly. |
| TTL-03 | SIGNAL keys also carry no TTL in V1: their memory is bounded by `MAXLEN ~` (SGR-01), and key expiry would delete the Analytics group and cause `NOGROUP` errors. A SIGNAL key MAY be deleted only through the stream lifecycle (§39). |
| TTL-04 | Stream retention is never implemented by key TTL. |

---

## 38. Group Retirement (ADR-7E-09)

| ID | Rule |
|---|---|
| RET-01 | A group is retired **only** when its 7B consumer obligation is formally removed or migrated by a governed change (7B registry change, or a 7E registry change for a handler split under GRP-02). |
| RET-02 | A group is **never** deleted automatically because no consumer heartbeat is seen, because its deployment is scaled to zero, because a worker is temporarily absent, because its lag is large, or because it pins retention. |
| RET-03 | Retirement sequence: (1) governed removal recorded; (2) consumers of the obligation stopped; (3) the group's pending entries are reviewed under the 7G procedure (dropping them is acceptable only because the obligation no longer exists); (4) `XGROUP DESTROY` on every key the group exists on; (5) registry updated; (6) the trim watermark recomputes without it. |
| RET-04 | Operational execution and authorization of retirement are 7G / 7K's; operator permissions are 7I's (HE-7I-03). |
| RET-05 | A stale group that pins retention is surfaced (lag, oldest pending age, safe-trim lag; §49.4) so that the governed decision can be taken before memory exhaustion (§41). |

---

## 39. Stream and Partition Lifecycle; Topology Generations (ADR-7E-10)

| ID | Rule |
|---|---|
| LCY-01 | **Creation.** Durable keys of a generation are created by provisioning with their groups (BST-01). Groupless durable keys MAY be created by the first `XADD`. |
| LCY-02 | **Normal operation.** Keys are written by the relay (durable) or the SIGNAL publisher (signal), read by groups, trimmed only by §34 – §36. |
| LCY-03 | **Rolling deployment.** Relays, consumers and the trim worker deploy independently (7A DPL-01). A route-registry change ships in the relay build; consumers tolerate entries of types they do not handle (GRP-08). |
| LCY-04 | **Live keys are never renamed** (`RENAME` is never used on a stream key). |
| LCY-05 | **Topology generation.** A change to partition count, partition function, key grammar or family assignment creates a new generation `g<n+1>` with new keys. It never reapplies `hash mod new_N` to existing keys. Within one generation, PF-1 and every `P_f` are immutable, so a live aggregate's partition never silently changes while consumers depend on that generation. |
| LCY-06 | **No live resharding of durable keys.** Slot migration of a non-empty durable stream key is prohibited, because the migrated copy on the target is not covered by the source connection's acknowledgement. Cluster capacity is added by moving **empty** slots to new shards and placing the next generation's keys on them. |
| LCY-07 | **Generation migration.** (1) Provision `g<n+1>` keys and all their registered groups at `0` (BST-01). (2) Deploy relays configured for `g<n+1>`; relays still on `g<n>` keep publishing to `g<n>` keys, which consumers still read. (3) Deployment gate: verify no relay runs `g<n>` configuration. (4) Drain: every group on every `g<n>` key has lag 0 and an empty PEL. (5) Retire `g<n>`: destroy groups, delete keys. Consumers read both generations until step 5. No entry is lost; duplicates remain possible as always. |
| LCY-08 | The topology generation is a transport axis. It is **not** `event_version`, not a 7C schema version and never appears in the envelope. A partition change never bumps `event_version` (7C KEY-06). |
| LCY-09 | A new `event_version` of an existing type never creates, renames or moves a stream; it adds a route row on the same logical stream (RR-07). |
| LCY-10 | **Draining and retirement of a family** (for example after a governed taxonomy change) follow LCY-07 steps 4 – 5 for that family's keys. |

---

## 40. Cross-Slot Consumption

| ID | Rule |
|---|---|
| XSL-01 | A single `XREADGROUP` with several stream keys is valid in Redis Cluster only if all keys share a hash slot (MF-16). 7E does not assume that keys of different families, partitions or generations share a slot. |
| XSL-02 | The cluster-compatible pattern is **one read operation per physical key (or per set of keys sharing one hash tag), on the connection to that key's primary, multiplexed by the consumer application**. The read loop, blocking strategy and concurrency are 7F's (HE-7F-01). |
| XSL-03 | No component relies on `CROSSSLOT` being absent. A `CROSSSLOT` error is a consumer implementation defect. |
| XSL-04 | The trim worker and the health probe operate per key / per node and use no multi-key command across slots. |

---

## 41. Memory Pressure

| ID | Rule |
|---|---|
| MEM-01 | Memory pressure never evicts a durable entry (EVC-01 … EVC-03). |
| MEM-02 | When a node holding durable keys reaches its memory limit, `XADD` fails with `OOM`. The outcome is `TRANSPORT_UNAVAILABLE` for every affected entry, never `ROW_REJECTED`; the relay gate opens; the outbox keeps the rows (7D DSP-03, GATE-01 … GATE-08). |
| MEM-03 | Recovery from memory exhaustion never deletes unacknowledged durable data: memory is freed only by consumers acknowledging entries and the trim worker removing entries below the watermark (§34), or by adding capacity. Whether an individual consumer command is accepted at the memory limit follows Redis's per-command out-of-memory rules, so operating headroom is required; sizing it is 7K's (HE-7K-02). |
| MEM-04 | SIGNAL `XADD` under `OOM` fails and the signal is dropped and counted (7D CLD-06). |
| MEM-05 | Capacity, alert thresholds and catch-up after memory relief are 7K / 7J's. 7E's safety property is: memory pressure can delay durable transport but can never lose a committed or confirmed event. |

---

## 42. Consumer Availability; Acceptance ≠ Consumption

| ID | Rule |
|---|---|
| AVL-01 | An offline current group does not block producers, the relay or Redis acceptance. Its lag grows; its entries stay retained (TRM-08). |
| AVL-02 | Publication never waits for any group to read or acknowledge (ACC-04). |
| AVL-03 | `CONFIRMED` means the event safely entered the transport under the 7E durability model. It does not mean Billing, Analytics or any consumer processed it, that all groups acknowledged it, that a webhook was delivered, or that any business side effect completed (ACC-03). |
| AVL-04 | A long-offline group eventually causes memory exhaustion (§34.2, §41), which pauses durable transport for all families on the affected nodes without loss. Preventing that through capacity, alerting and the governed retirement path is 7K / 7J / 7G's; 7E forbids automatic group deletion (RET-02). |

---

## 43. SIGNAL Publisher Transport Rules

| ID | Rule |
|---|---|
| SPB-01 | The SIGNAL publisher issues one `XADD … MAXLEN ~ N_signal` per signal to the LS-S-VOX key, with a short bounded timeout; no acknowledgement command, no `WAIT`, no `WAITAOF`, no health probe. |
| SPB-02 | On any error, timeout, redirect or `OOM`, the signal is dropped and counted. Any in-process re-attempt is bounded and reuses the same signal `event_id` (7D CLD-05; 7C ID-09). No disk queue, no outbox, no durable retry, no replay (7D CLD-06). A SIGNAL whose `aggregate_id` is NULL violates 7C SIG-06; it is dropped and counted as a contract anomaly, never written with a substitute partition. |
| SPB-03 | Publication is non-blocking from the producer's point of view; on the Voice runtime it adds no waiting to the turn loop (7D CLD-05, VOX-03). |
| SPB-04 | The SIGNAL publisher uses its own client and connection pool, distinct from the durable adapter (SEP-02). |

---

## 44. Tenancy

| ID | Rule |
|---|---|
| TNY-01 | A stream key, a partition and a consumer group are **not** tenant authority. Consumers establish tenant context from the envelope `organization_id` and their own ownership checks (7B CR-03; 7C TEN-C05; 7D TEN-7D-04). |
| TNY-02 | No component derives `organization_id` from a key, a partition index or a group name, and no partition ID replaces `organization_id`. |
| TNY-03 | Where several tenants share a stream key, that is **transport co-location only**. It grants no cross-tenant read authority to any business path; every consumer is a platform-internal worker that applies tenant checks per entry. |
| TNY-04 | EV-001 (`organization_id = null`) is consumed by `cg.identity.session-denylist` as an explicitly platform-scoped fact (7C TEN-C02); it is never attributed to a tenant. |
| TNY-05 | Tenant-level fairness across shared streams (a burst tenant delaying others) is a capacity concern (7K, HE-7K-04); it never affects correctness. |

---

## 45. Security

| ID | Rule |
|---|---|
| SCY-01 | A stream entry contains only `fmt` and `env` (ENT-01). Outside the frozen envelope it carries no credential, access token, refresh token, provider secret, signing secret, signed URL, raw media, raw audio, raw transcript, tool arguments or tool results. Inside the envelope, exclusion is guaranteed upstream by producer validation (7C §19.3, PV-C12; 7D SEC-7D-04). |
| SCY-02 | Transport metadata (`fmt`, keys, group names, consumer names) is non-sensitive by construction (NS-01, GRP-04, GRP-06). |
| SCY-03 | Stream bodies (`env`) are never logged by the adapter, the SIGNAL publisher, the trim worker or provisioning, and never placed in metrics (7D SEC-7D-01, SEC-7D-02). Consumers follow 7I for any payload logging. |
| SCY-04 | Redis connections use TLS (SRC-14) and per-role credentials from the secret manager (7D SEC-7D-05). |
| SCY-05 | Least privilege by role, using Redis ACL users with command and key-pattern restrictions: relay — `XADD` on durable keys plus `WAITAOF` and read-only cluster / info / `COMMAND INFO` commands; SIGNAL publisher — `XADD` on SIGNAL keys only; consumers — `XREADGROUP`, `XACK`, `XAUTOCLAIM`, `XCLAIM`, `XPENDING`, `XINFO` on their subscribed keys; trim worker — `XINFO`, `XPENDING`, `XTRIM`, `PERSIST`, `TTL` on stream keys; provisioning — `XGROUP CREATE`. `XGROUP DESTROY`, `XGROUP SETID`, `XGROUP DELCONSUMER`, `DEL` and `FLUSH*` on stream keys are operator-only. The final permission model is 7I's (HE-7I-03). |
| SCY-06 | Co-tenancy of entries in shared streams (§44) is recorded for 7I's classification (HE-7I-01). |

---

## 46. Data Residency

| ID | Rule |
|---|---|
| RSD-01 | The event transport used by a relay deployment is in the same contracted region as the PostgreSQL outbox it drains (7D TPT-11, RES-7D-01). |
| RSD-02 | There is no global cross-region event stream and no cross-region fan-out in the normal path (7A RES-03). |
| RSD-03 | For `INDIA_ENTERPRISE`, every stream entry, PEL, trimmed-entry remnant in AOF / RDB files, Redis persistence volume and backup copy of the event transport stays in the contracted region (7A RES-02; 5A §19.4). |
| RSD-04 | 3F's region-2 "Redis Replica — cold standby" (SRC-13) MUST NOT carry durable stream keys of an `INDIA_ENTERPRISE` region outside that region. Any cross-region copy of event-transport data requires a governed 7K decision that satisfies RES-02 (CNF-7E-13). |
| RSD-05 | Regional failover and disaster recovery of the transport are 7K's (HE-7K-06). |

---

## 47. Voice Hot Path

| ID | Rule |
|---|---|
| VHP-01 | Durable acceptance (§23) applies only to the outbox relay. STT, LLM, TTS, barge-in, raw WebSocket media and the turn loop never wait for stream durability, for any acknowledgement command or for the health probe. |
| VHP-02 | PAY-D-01 and PAY-D-02 signals are published by SPB-01 … SPB-04: bounded, non-blocking, droppable; never a durability wait. |
| VHP-03 | No audio, PCM, media frame or per-frame event is written to any stream (7A RS-06; 7D VOX-7D-01). |
| VHP-04 | ≤ 750 ms remains a target, not a guarantee (7A VOX-01). |
| VHP-05 | Durable streams live on the dedicated event-transport cluster (OD-7E-01 = A), so durable backlog, `noeviction` exhaustion and AOF settings of that cluster cannot evict or block the Voice session tier on the shared cluster. `appendfsync` stays `everysec` (OD-7E-02 = A). SIGNAL publication to the event-transport cluster is non-blocking and droppable (SPB-01 … SPB-03). |

---
## 48. Failure Matrix

"Model" column: **Inside** = inside the declared V1 normal transport fault model (FMD-06) under the decided mechanism (`XADD` + same-connection `WAITAOF 1 1`, AOF `everysec`, one replica per primary, `noeviction`); **Outside** = disaster / repair path (FMD-02, FMD-07); **Contract** = loss permitted by the SIGNAL contract; **Defect** = prohibited configuration or implementation error that a rule prevents.

| ID | Failure | Transport state | `CONFIRMED` event lost? | Duplicate possible? | Relay outcome | Consumer impact | Recovery owner | Model |
|---|---|---|---|---|---|---|---|---|
| F7E-01 | Primary dies before `XADD` | No entry | No (none confirmed) | No | `NOT_ATTEMPTED` / `TRANSPORT_UNAVAILABLE`; gate opens | None | 7D deferral; Redis failover | Inside |
| F7E-02 | Primary dies after `XADD`, before acknowledgement | Entry may exist on promoted replica, or not | No (never confirmed) | Yes | `UNKNOWN` | Possible duplicate later | 7D deferral; 7F dedup | Inside |
| F7E-03 | Primary dies after `CONFIRMED` | Entry fsynced on primary and on its replica (`WAITAOF` [≥ 1, ≥ 1]); survives promotion or restart | No | Yes (group state may regress, MF-10) | `CONFIRMED` (row `PUBLISHED`) | Possible redelivery | Redis failover; 7F dedup | Inside |
| F7E-04 | Replica unavailable | Primary up; confirmation impossible | No | Yes (if written) | `TRANSPORT_UNAVAILABLE` (`NOREPLICAS`) or `UNKNOWN` | None (reads continue from primary) | Redis ops; 7K | Inside (availability) |
| F7E-05 | `WAITAOF` timeout (shortfall at the bounded timeout) | Entry written, durability not established | No | Yes | `UNKNOWN` | Possible duplicate | 7D; 7F | Inside |
| F7E-06 | Connection reset, ambiguous `XADD` | Unknown | No | Yes | `UNKNOWN` | Possible duplicate | 7D; 7F | Inside |
| F7E-07 | `MOVED` during publish | Not executed on old node | No | No (from `MOVED` itself) | Re-issue once (RED-01) or `TRANSPORT_UNAVAILABLE` | None | 7E adapter | Inside |
| F7E-08 | `ASK` during reshard / failover | Ungoverned migration of a durable key | No | No | `TRANSPORT_UNAVAILABLE` + anomaly (RED-03) | None | 7E / ops (LCY-06) | Inside |
| F7E-09 | `cluster_state` not OK | Writes refused | No | No | `TRANSPORT_UNAVAILABLE`; probe UNHEALTHY | Reads may fail; lag grows | Redis ops; 7K | Inside (availability) |
| F7E-10 | One shard unavailable (storage intact) | That shard's keys unavailable | No | Yes | Mixed per entry; gate opens; probe UNHEALTHY (HPR-02) | Groups on that shard lag | Redis ops; 7K | Inside (availability) |
| F7E-11 | Entire Redis cluster unavailable (storage intact) | All writes refused | No | No | `TRANSPORT_UNAVAILABLE`; outbox absorbs (7A FM-01) | All groups lag; producers unaffected | 7D gate; 7K catch-up | Inside (availability) |
| F7E-12 | Durable stream memory pressure | Non-evicting node at limit | No | No | `TRANSPORT_UNAVAILABLE` (`OOM`) | Lag grows; memory is recovered only by acknowledgement + watermark trimming or added capacity (MEM-03) | 7K capacity; 7G retirement if stale group | Inside |
| F7E-13 | SIGNAL stream memory pressure | Bounded by `MAXLEN ~`; node `OOM` refuses signal writes | n/a (signals) | n/a | Signal dropped and counted | Analytics gaps | 7K | Contract |
| F7E-14 | Consumer group offline | Group position frozen | No | No | Unaffected | Lag grows; entries retained (TRM-08) | 7J observe; 7K capacity | Inside |
| F7E-15 | Consumer crashes with pending entries | Entries in PEL | No | Yes (reclaim) | Unaffected | Reclaimed by another member after 7G idle threshold | 7F / 7G | Inside |
| F7E-16 | Trim while PEL exists | Watermark ≤ smallest pending ID | No | No | Unaffected | None | 7E trim worker | Inside |
| F7E-17 | Stale group pins retention | Memory grows | No | No | Unaffected until `OOM` (F7E-12) | Others unaffected until `OOM` | 7G governed retirement; 7K | Inside |
| F7E-18 | Topology-generation change | Two generations live during LCY-07 | No | Yes (as always) | Relays per generation config | Consumers read both until drained | 7E / 7K | Inside |
| F7E-19 | Consumer added after stream has events | Future group start position explicit (BST-04); missing current group recreated at `0` (BST-03) | No | Yes (recreation) | Unaffected | Backfill only by 7G decision | 7G | Inside |
| F7E-20 | Consumer removed | Governed retirement (RET-03) | No (obligation removed) | No | Unaffected | Other groups unaffected | 7G / 7K | Inside |
| F7E-21 | Whole primary + replica shard lost (both storages: correlated destruction of every durable copy) | Shard data gone | **Yes** (outside model) | Yes (repair replay) | Rows already `PUBLISHED` | Groups on that shard lose entries | 7G / 7K disaster replay from retained `PUBLISHED` rows (7D CLN-08) | Outside |
| F7E-22 | Region lost | Region transport gone | Yes | Yes | n/a | n/a | 7K regional recovery | Outside |
| F7E-23 | Valid payload of 262144 characters (≤ 1 048 576 bytes) | Accepted (SIZ-02) | No | No | `CONFIRMED` when acknowledged | Normal | — | Inside |
| F7E-24 | Malformed / unroutable exact `event_type` | No route | No | No | `NONE` → `RELAY_CAPABILITY` (non-terminal) | None | Producer owner fixes forward; 7G operator | Inside |
| F7E-40 | Committed row with NULL `aggregate_id` (contract-invalid; column physically nullable) | No Route; no `XADD`; never `CONFIRMED` | No | No | `route_for` → `NONE` → `RELAY_CAPABILITY` (non-terminal, deferred; reason `INVALID_ROUTING_ATTRIBUTE`); never `ROW_REJECTED`, never `FAILED`, never partition 0 (PRT-07, RTE-09) | None until fixed forward | Producer owner fixes forward; 7G operator handling | Inside |
| F7E-25 | Platform-scoped EV-001 | Routed to LS-D-IDN via explicit platform rule (RTE-06) | No | As normal | Normal | `cg.identity.session-denylist` processes as platform-scoped | — | Inside |
| F7E-26 | Split-brain / partition | Isolated primary cannot confirm (TF-15) | No | Yes | `UNKNOWN` / `TRANSPORT_UNAVAILABLE` | Possible duplicates | Redis failover; 7F | Inside |
| F7E-27 | SIGNAL publish fails | No entry | n/a | n/a | Dropped and counted (SPB-02) | Analytics gap | — | Contract |
| F7E-28 | Group accidentally shares independent obligations | Entries split among obligations | Effective loss for each obligation | — | Unaffected | **Defect**: each obligation misses entries | Prevented by GRP-01, GRP-02, FAN-02 and the registry check (IO-7E-14) | Defect (P1 class) |
| F7E-29 | Primary crash and restart before failover (H-1) | Restarted primary reloads AOF containing confirmed entries | No (FMD-05) | Yes | As normal | Possible redelivery | Redis | Inside |
| F7E-30 | Simultaneous restart of primary and replica, storages intact | Both reload AOFs that contain every confirmed entry (both fsynced before `CONFIRMED`) | No | Yes (group state may regress) | Transport unavailable during restart → non-terminal | Possible redelivery | Redis | Inside |
| F7E-31 | Durable group read with `NOACK` | Entries leave no PEL | Possible effective loss | — | Unaffected | **Defect** | Prevented by GRP-07 | Defect (P1 class) |
| F7E-32 | `DELCONSUMER` on a member with pending entries | Pending entries become unclaimable | Effective loss for that group | — | Unaffected | **Defect** | Prevented by GRP-10 | Defect (P1 class) |
| F7E-33 | TTL applied to a durable key | Key would expire | Would lose all | — | — | **Defect** | Prevented by TTL-01, TTL-02 | Defect (P0 class if it expired) |
| F7E-34 | Registered group missing on a key | Trimming refused (TRM-03) | No | Yes (on recreation at `0`) | Unaffected | Group recreated (BST-03) | 7E provisioning | Inside |
| F7E-35 | Relay crash after `CONFIRMED`, before `fn_mark_outbox_published` (TF-21) | Entry durable in stream; row `CLAIMED` | No | Yes | Lease expiry → republish same `event_id` (7D CRS-06) | Duplicate; 7F dedup | 7D; 7F | Inside |
| F7E-36 | `WAITAOF` issued on a different connection or node than the `XADD` | Would prove nothing about the entry | Would risk loss | — | Prohibited: AFF-01, WAO-01, WAO-04; the algorithm (§23.5.3) issues it only on the `XADD`'s connection | — | IO-7E-08, IO-7E-09 tests | Defect (P0 class if it produced `CONFIRMED`) |
| F7E-37 | Capability missing (Redis < 7.2, no `WAITAOF`, AOF off, total shard replica membership ≠ 1, replica identity mismatch, replica migration enabled, `maxmemory-policy` ≠ `noeviction` on a durable primary **or on its failover replica**) | Adapter refuses capability (CAP-01 … CAP-09) | No | No | `TRANSPORT_UNAVAILABLE` (CL-21); startup not-ready | Lag grows | Platform ops | Inside (availability) |
| F7E-38 | Replica membership changed to > 1 without FMD-09 revalidation | A non-fsynced replica could be promoted | Could lose | — | Prohibited (FMD-09 governed procedure; TOPO-10 disables automatic migration); CAP-04 and HP-05 count total membership, report not capable, so nothing further is confirmed | Lag grows | Governed 7E amendment + IO-7E-12 | Defect (prevented) |
| F7E-41 | One connected replica plus a second configured replica that is failed, loading or disconnected (`connected_slaves = 1`) | Second member could reconnect behind and be promoted | No (nothing confirmed) | No | `shard_capable` false (T-04 … T-06) → `TRANSPORT_UNAVAILABLE` (CL-21) before any durable write; probe UNHEALTHY | Lag grows | Platform ops: governed removal (`CLUSTER FORGET`) or FMD-09 amendment | Inside (availability) |
| F7E-42 | Sole replica exists and is healthy, but automatic failover is disabled (`cluster-replica-no-failover yes`, `nofailover` flag) | Capability unavailable; no durable `XADD` attempted while the gate is down | No (nothing confirmed; outbox obligation retained) | No | `shard_capable` false (T-12, T-13) → `TRANSPORT_UNAVAILABLE` (CL-21), non-terminal; never `ROW_REJECTED`, never `FAILED`; probe UNHEALTHY; startup not-ready | Lag grows | Platform ops: set `cluster-replica-no-failover no` (TOPO-11) via the governed procedure | Inside (availability) |
| F7E-43 | Sole, otherwise healthy replica has `maxmemory-policy` ≠ `noeviction` (for example `allkeys-lru`, `volatile-lru`) while the primary is `noeviction` | Shard NOT CAPABLE; no durable `XADD` attempted while capability is down, even though `XADD` on the primary would succeed | No (nothing confirmed; outbox obligation retained; no eviction path accepted) | No | `shard_capable` false (T-15, T-16) → `TRANSPORT_UNAVAILABLE` (CL-21), non-terminal; never `ROW_REJECTED`, never `FAILED`; no outbox row is altered; probe UNHEALTHY (HP-07); startup not-ready | Lag grows | Platform ops: set `maxmemory-policy noeviction` on the replica (TOPO-05, CAP-07) | Inside (availability) |
| F7E-39 | `WAITAOF` called with timeout `0` | Would block indefinitely (MF-19) | No | — | Prohibited by WAO-03 (positive bounded timeout) | — | IO-7E-09 | Defect (prevented) |

---

## 49. Handoffs

### 49.1 To 7F (consumers)

| ID | 7F receives |
|---|---|
| HE-7F-01 | Stream families, logical streams, the route registry (§18), the V1 physical key set (§15.4, NS-08), PF-1 for later generations, and the cross-slot read constraint (§40). 7F owns the read loop. |
| HE-7F-02 | The group registry (§29) and PEL mechanics (§31). 7F owns the processing transaction, dedup / inbox, business-key idempotency and `XACK` timing (ACK-01). |
| HE-7F-03 | GRP-08: every delivered entry, including unsubscribed types, must eventually be acknowledged; 7F defines when. |
| HE-7F-04 | Ordering semantics ORD-7E-01 … ORD-7E-10: append order per key only; `aggregate_id` partition affinity is not an aggregate sequence guarantee; consumer correctness must not depend on per-aggregate arrival order; any consumer-side ordering algorithm is 7F's. The 7B IO-7B-08 / CR-04 wording conflict stays open for a controlled 7B reconciliation (CNF-7E-10, IO-7E-25); 7F must not rely on that wording. |
| HE-7F-05 | At-least-once delivery with duplicates from republication (CLS-03), reclaim (PEL-03), group-state regression after failover (MF-10) and group recreation (BST-03). |
| HE-7F-06 | GRP-02: if 7F gives several handlers of one CON entry independent acknowledgement, each needs its own group through a governed 7E registry change before activation. |
| HE-7F-07 | ENT-06: parse `env` without binary-float decoding of business values; reject a wrong-profile `fmt` (SEP-03). |

### 49.2 To 7G (retry, DLQ, replay)

| ID | 7G receives |
|---|---|
| HE-7G-01 | PEL reclaim capability (`XAUTOCLAIM` / `XCLAIM`, delivery counter, idle time; PEL-02). 7G owns idle threshold, retry timing, delivery-count policy, poison threshold, DLQ and parking. |
| HE-7G-02 | Publisher terminal `FAILED` rows: under CLS-01 the transport produces none in V1; any that arise (operator action) remain 7G's disposition (7D HO-7G-01). |
| HE-7G-03 | Stream retention boundaries (§34 – §36), including the trim pause required for `XGROUP SETID` and future-group creation (TRM-07). |
| HE-7G-04 | Disaster replay source for outside-model faults (F7E-21, F7E-22): retained `PUBLISHED` outbox rows (7D CLN-08). |
| HE-7G-05 | Future-consumer backfill policy (BST-04) and governed group retirement execution (RET-03). |

### 49.3 To 7I (security / privacy)

| ID | 7I receives |
|---|---|
| HE-7I-01 | Stream co-tenancy model (TNY-03) for classification. |
| HE-7I-02 | Payload-logging prohibition for transport components (SCY-03). |
| HE-7I-03 | Group / stream operator permissions (SCY-05) and the operator-only command list. |
| HE-7I-04 | DLQ sensitivity inputs for entries moved out of PELs by 7G. |

### 49.4 To 7J (observability) — semantic telemetry, no names or thresholds

Cluster health; shard health; replica availability and lag; `WAITAOF` confirmation latency; `WAITAOF` shortfalls (`[local, replicas]` below `[1, 1]`), timeouts and errors; capability-gate failures by check (CAP-01 … CAP-07); `XADD` latency; per-key stream length and memory; per-group lag (`lag`, `entries-read`); PEL size; oldest pending age; safe-trim lag (distance between `W(K)` and the stream's oldest entry, and between the top entry and `W(K)`); trim counts; registered-group-missing and unregistered-group anomalies (TRM-03, TRM-04); TTL anomalies (TTL-02); `MOVED` / `ASK` rate; outcome counts by class (CL-01 … CL-20); routing failures (`NONE`); SIGNAL published / dropped counts; probe results by check (HP-01 … HP-07). Labels follow 7D OBS-7D-C1 / C2 (no raw `event_id` or tenant id unless 7J permits).

### 49.5 To 7K (capacity, recovery, regional)

| ID | 7K receives |
|---|---|
| HE-7K-01 | Partition-count sizing per family for generations after `g1` (V1 `P_f = 1`; PF-1 fixed), slot-to-shard placement of keys before provisioning (§15.4), and the generation-migration procedure (LCY-07). |
| HE-7K-02 | Memory capacity for retained durable backlog (SIZ-04, §34.2), `N_signal` (SGR-01) and `T_groupless` (GLR-01). |
| HE-7K-03 | Stream growth under offline / stale groups; backpressure; catch-up after outage and after `OOM` (MEM-05, AVL-04). |
| HE-7K-04 | Tenant fairness on shared streams (TNY-05). |
| HE-7K-05 | Availability impact of per-loop gating on one-shard outages (HPR-02), including the post-failover window with no replica (TF-22, Minor-7E-08), replica re-attachment automation, the extended-disconnection case TF-23 and the values of `cluster-node-timeout`, `repl-ping-replica-period` and any change to `cluster-replica-validity-factor` (TOPO-12); `min-replicas-max-lag`, `WAITAOF` timeout and probe interval values. |
| HE-7K-06 | Regional topology, regional failover and disaster replay beyond the declared model (FMD-02, RSD-04, F7E-21, F7E-22). |
| HE-7K-07 | Autoscaling of consumers and relays; event-transport cluster node sizing, headroom and alarms (DEP-06); trim-worker cadence (TRM-11). |
| HE-7K-08 | **Benchmarks required before production** (7E fixes no throughput number): `XADD` throughput; `WAITAOF 1 1` confirmation latency under `appendfsync everysec`; batches per shard; interaction with the 7D claim batch of 50; relay lease / local-deadline / safety-margin margin against `WAITAOF` waits (ALG-05); consumer lag; memory growth; thresholds for moving to `P_f > 1`. |

---

## 50. Owner Decision Register

7E paused at an owner-decision checkpoint with the three packets below, without applying any recommendation. The owner then decided all three. The packets are kept unchanged below each decision as the decision record; the options not chosen are historical analysis, not design.

| OD | Topic | Owner decision | Status | Applied in |
|---|---|---|---|---|
| OD-7E-01 | Event-transport deployment isolation and eviction policy | **A** — dedicated event-transport Redis Cluster per active region, `maxmemory-policy noeviction` | **DECIDED — RESOLVED** | §12.2, §12.3 (DEP-01 … DEP-07), §13.4 (EVC-05 … EVC-08), §41, §47, CAP-05, HP-07, ADR-7E-14 |
| OD-7E-02 | Durable acceptance mechanism and normal fault model | **A** — `XADD` + same-connection `WAITAOF 1 1 <bounded timeout>`; AOF on with `appendfsync everysec`; one replica per primary; Redis Open Source 7.2+ prerequisite | **DECIDED — RESOLVED** | §10 (MF-19, MF-20), §11.2 – §11.4 (FMD-05 … FMD-09), §12.2, §23.1, §23.5 (WAO-*, CAP-*, ALG-*), §25, §26, §48, ADR-7E-15 |
| OD-7E-03 | Stream partitioning and hash tag versus 3F `{tenant_id}` | **B** — fixed partitions per durable family, partitioned by `aggregate_id`; `P_f = 1` per family in V1; governed exception to the 3F blanket rule | **DECIDED — RESOLVED** | §14.1, §15.4 (NS-06 … NS-08), §16 (PRT-01 … PRT-06, PF-1), §20, §28, §29, §33 (ORD-7E-06, ORD-7E-10), ADR-7E-16 |

Open owner decisions: **0**.

### 50.1 OD-7E-01 — Event-transport deployment isolation and eviction policy

**Owner decision: Option A — RESOLVED.** Binding scope: durable Redis Streams and their consumer-group state live on a dedicated, region-local event-transport Redis Cluster with `noeviction`; they never share the deployment whose primary purpose is ephemeral sessions / cache / state; memory exhaustion yields explicit, non-terminal write failures; capacity remains 7J / 7K's; 3F is not modified.

| Field | Content |
|---|---|
| Question | Where do durable event streams (and the 4 SIGNAL pairs) physically live, and under which instance-level `maxmemory-policy`? |
| Source evidence | 3F §16.1 (one production Redis Cluster, 3 + 3) SRC-02, SRC-03; 3F §16.3 per-key-space eviction table SRC-05; 2A L201 / 3F L1011 — the same Redis carries caches, sessions, Celery broker, locks, presence SRC-08; 3F §10.1 "acceptable loss" SRC-07; 5A §18, §24.2 SRC-09; 7D TPT-02, HO-7E-03; 7A RS-01 … RS-03. |
| Conflict / gap | `maxmemory-policy` is per instance (MF-18) and Redis Cluster mixes all key spaces on every node, so 3F §16.3 is not implementable in one cluster (CNF-7E-01). Under `allkeys-lru` (3F's session policy) a durable stream key with all its groups can be evicted, which EVC-01 forbids. |
| Option A (**chosen**) | **Dedicated event-transport Redis Cluster per region**, `noeviction`, holding only durable and SIGNAL stream keys, with its own persistence / acknowledgement configuration (OD-7E-02), credentials and network policy. The shared hot-tier cluster keeps its 3F role; its policy stays a 3F / 7K matter. |
| Option B (not chosen) | **Shared cluster, cluster-wide `volatile-lru`** (or `volatile-ttl`). Invariant: every cache / session key carries a TTL (application-enforced); stream, queue and Celery-broker keys never carry a TTL and are therefore never evicted; when no volatile key remains, writes fail with `OOM`. 3F §16.3 amended to one policy. |
| Option C (not chosen) | **Shared cluster, cluster-wide `noeviction`.** Caches rely only on TTL expiry; at the memory limit every write fails, including session and cache writes. |
| Pros | A: complete blast-radius isolation; stream backlog cannot evict or starve Voice session state; persistence settings (AOF on all nodes, possible `appendfsync always`) affect only event traffic; clean capacity accounting. B: no new infrastructure; protects TTL-less keys. C: no new infrastructure; nothing is ever evicted. |
| Cons | A: second cluster per region (Redis Cluster needs ≥ 3 primaries for failover voting; with 3F's 1-replica layout, 6 more nodes per region); more operations, monitoring, secrets, network policy. B: correctness of every cache key now depends on application TTL discipline (a TTL-less cache key becomes unevictable); durable backlog from an offline consumer consumes memory the session tier needs, evicting session/cache keys first and then causing `OOM` on hot-path writes; a shared AOF / fsync configuration for acceptance (OD-7E-02) applies to all hot-tier writes. C: as B, but memory exhaustion immediately fails session and cache writes — Voice degradation. |
| Durability impact | A, B, C all satisfy EVC-01 if configured as stated. B depends on TTL discipline staying correct for non-stream keys only; a mis-set TTL on a stream key would be caught by TTL-02 but is a P0-class risk window. |
| Latency impact | A: none on Voice. B / C: stream growth and acknowledgement-related persistence settings can raise Voice session-tier latency (cache eviction → PostgreSQL fallback; or `OOM`). |
| Capacity impact | A: separate, predictable event memory budget. B / C: shared budget with unbounded stream growth under offline groups. |
| Cost impact | A: additional cluster nodes and storage per region (including the India region). B / C: none. |
| Migration / deployment impact | A: new Helm release, endpoints, network policy, secrets, exporter, runbooks; 3F unchanged except a documentary note. B / C: change the shared cluster's policy; audit every existing key space for TTLs; amend 3F §16.3. |
| Recommendation (at checkpoint) | **A — dedicated event-transport Redis Cluster per region with `noeviction`.** The owner decided A. |

### 50.2 OD-7E-02 — Durable acceptance mechanism and normal fault model

**Owner decision: Option A — RESOLVED.** Binding scope: `WAITAOF 1 1 <bounded timeout>` on the `XADD`'s connection; AOF enabled with `appendfsync everysec` (not `always`); one replica per primary in V1 (two replicas not required); Redis Open Source 7.2+ as a capability prerequisite; timeouts never imply success; uncertain outcomes are `UNKNOWN`; no Redis error is terminal for an outbox row; throughput is benchmarked by 7K.

| Field | Content |
|---|---|
| Question | Which Redis 7.2 mechanism makes an entry `CONFIRMED`, with which replica count and persistence settings, and therefore which faults are inside the normal model? |
| Source evidence | 7D TPT-02, HO-7E-03, PRB-05, F7D-21, ADR-7D-19; 3F §11.2 AOF `everysec` SRC-06; 3F §16.1 1 replica per primary SRC-03; 5A §24.2 "AOF best-effort, not relied upon" SRC-09; facts MF-01 … MF-09. |
| Conflict / gap | 3F / 5A treat Redis persistence as best-effort; 7D requires zero normal-path loss after `CONFIRMED` (CNF-7E-03). `WAIT` alone fails hazard H-1 (§11.3). Several eligible mechanisms remain, differing in survivable double faults, latency, throughput, availability and cost. |
| Option E0 (ineligible, shown for transparency) | `XADD` + `WAIT 1` + `min-replicas-to-write 1`. Fails H-1 (TF-02): a primary restart without failover can erase a `WAIT`-acknowledged entry. **Does not satisfy TPT-02.** |
| Option A (**chosen**) | `XADD` + **`WAITAOF 1 1`** on the same connection; `appendonly yes` with `appendfsync everysec` on every event node; `min-replicas-to-write 1`; 3F topology (1 replica per primary). `CONFIRMED` iff local = 1 and replicas ≥ 1. |
| Option B (not chosen) | As A, but **`appendfsync always`** on every event node (each write fsynced before reply). `WAITAOF 1 1` then waits mainly for the replica's fsync. |
| Option C (not chosen) | **Two replicas per primary.** C1: `WAITAOF 1 1` (any one replica fsynced) — a single replica outage no longer blocks confirmation. C2: `WAITAOF 1 2` (both replicas fsynced) — survives permanent loss of the primary plus one replica. |

Fault comparison:

| Fault | E0 | A | B | C1 | C2 |
|---|---|---|---|---|---|
| One primary node failure + promotion (TF-01, TF-03) | Survives | Survives | Survives | Survives | Survives |
| Primary process crash + restart before failover (TF-02, H-1) | **Loses** | Survives | Survives | Survives | Survives |
| Replica lag (TF-04) | `UNKNOWN` on timeout | `UNKNOWN` on timeout | `UNKNOWN` on timeout | `UNKNOWN` on timeout | `UNKNOWN` on timeout |
| Single replica unavailable (TF-11) | Shard cannot confirm | Shard cannot confirm | Shard cannot confirm | **Still confirms** | Shard cannot confirm |
| Simultaneous restart of primary and replica, storage intact (TF-16) | Loses (≈ last second) | Survives | Survives | Survives | Survives |
| Permanent loss of primary + its (one) fsynced replica (TF-17) | Loses | Loses (outside) | Loses (outside) | May lose (outside) | **Survives** |
| Region loss (TF-18) | Loses | Loses (outside) | Loses (outside) | Loses (outside) | Loses (outside) |

| Field | Content |
|---|---|
| Latency | E0 ≈ one replication round trip. A: confirmation waits for the next background fsync on primary and replica (order of the `everysec` cadence, up to about a second; must be benchmarked). B: each write pays a disk fsync (milliseconds per event-loop batch) — lower confirmation latency, higher Redis CPU / IOPS. C: as A (C1) or slowest of two replicas (C2). |
| Operational complexity | A: AOF on all event nodes, `WAITAOF`-capable client with node-pinned connections (AFF-05). B: plus disk IOPS sizing for per-write fsync. C: plus a third node per shard, larger elections, more storage. |
| Redis 7.2 support | `WAITAOF` exists from 7.2 (baseline). `WAIT`, `min-replicas-*` long supported. |
| Relay throughput | One acknowledgement per pipeline per primary per batch (ACC-07). A / C: throughput per relay loop ≈ batch entries per primary per fsync cadence; scaled by more relay loops (7D SCL-01). B: higher per-loop throughput. Values are 7K benchmarks. |
| Voice hot path | None under any option: acknowledgement is relay-only (VHP-01). Under OD-7E-01 options B / C, option B here (`appendfsync always`) would also slow every hot-tier write on the shared cluster. |
| Deployment cost | A: none beyond OD-7E-01. B: faster disks / IOPS. C: +50 % event-cluster nodes. |
| Normal model with A (now binding, §11.4) | Inside: TF-01 … TF-16, TF-21, TF-22. Outside: TF-17 … TF-20. |
| Recommendation (at checkpoint) | **Option A** (`WAITAOF 1 1`, `appendfsync everysec` on all event nodes, `min-replicas-to-write 1`, 1 replica per primary). The owner decided A. |

### 50.3 OD-7E-03 — Stream partitioning and hash-tag strategy versus the 3F `{tenant_id}` rule

**Owner decision: Option B — RESOLVED.** Binding scope: fixed partitions per durable family keyed by `aggregate_id`; no per-tenant streams; `organization_id` is not the partition key; `P_f = 1` per family in V1 (not a permanent hard-coded single stream); deterministic language-independent partition function (fixed in §16.3 as PF-1: CRC-32/ISO-HDLC over the 16 UUID octets of a valid non-null `aggregate_id`, which the option-B row below described only as an example; a NULL `aggregate_id` gets no route, PRT-07); partition-count changes only through topology generations; partition affinity is not per-aggregate ordering.

| Field | Content |
|---|---|
| Question | How are the 11 durable families and the SIGNAL family laid out across Redis Cluster hash slots, and is the event bus an approved exception to 3F §16.2? |
| Source evidence | 3F §16.2 "must be honoured when any new Redis key is introduced" SRC-04; 5A layer 4 / §18.2 `{purpose}:{organization_id_or_global}:…` SRC-10; 7A DD-05 (partition keys deferred to 7E / 7K), ORD-05; 7C TEN-C02 (EV-001 null organization); 7A §32.2 (no invented figures). |
| Conflict / gap | Literal compliance means per-tenant streams; deviation breaks an explicit 3F constraint whose rationale (same-slot multi-key operations) does not apply to single-key `XADD` (CNF-7E-02). Materially different scalability, isolation and operating cost. |

Symbols: `T` = number of tenants; `F` = 11 durable families; `S` = 18 (durable group, family) subscriptions; `P` = partitions per family.

| Option | Physical key grammar (generation `g1`) | Keys | Redis groups | Pros | Cons |
|---|---|---|---|---|---|
| A — per-tenant streams (literal 3F; **not chosen**) | `stream:{<organization_id>}:d:g1:<family>`; EV-001 → `stream:{platform}:d:g1:identity`; SIGNAL `stream:{<organization_id>}:s:g1:voice` | ≈ `T × F` (+1 platform) | ≈ `T × S` | Obeys 3F literally; per-tenant co-location | Group and key explosion; every new tenant needs groups provisioned at `0` before its first event (BST-01) and every tenant offboarding needs governed retirement; consumers must discover and poll thousands of keys (no cross-slot multi-key read); a hot tenant is pinned to one slot and one shard; health probe must cover every shard; per-key overhead dominates memory |
| B — fixed partitions per family (**chosen**) | `stream:global:d:g1:<family>:{d.g1.<family>.<p>}` with `p = H(aggregate_id) mod P_f`; null `aggregate_id` (non-conformant row) → no route: `NONE` → 7D `RELAY_CAPABILITY` (correction P1-7E-07 by independent freeze review; the checkpoint packet had proposed a partition-0 fallback, which frozen 7C ENV-06 / AGG-04 and 7D MAT-04 / F7D-14 forbid); SIGNAL `stream:global:s:g1:voice:{s.g1.voice.<p>}` with `p = H(aggregate_id) mod P_s`; `H` a fixed, documented hash (for example CRC-32 of the canonical UUID text) | `Σ P_f` | `Σ (subscriptions × P_f)` | Bounded keys and groups; even spread including hot tenants and campaign bursts; EV-001 needs no special case (`aggregate_id = user_id`); generation migration for growth (LCY-07) | Breaks 3F letter (needs exception); multi-tenant co-location in a key (transport only, §44); needs `P_f` values |
| B′ — variant: partition by organization (**not chosen**) | as B with `p = H(organization_id) mod P_f`; EV-001 (`null`) → explicit platform partition `p = 0` | as B | as B | Tenant co-location per partition | A hot tenant concentrates on one partition / shard; explicit platform rule needed |
| C — one key per family (**not chosen**) | `stream:global:d:g1:{d.g1.<family>}`; SIGNAL `stream:global:s:g1:{s.g1.voice}` | 11 + 1 | 18 + 1 | Simplest; fewest keys and reads | Each family bound to one shard's throughput (Voice, CRM and Campaign families are the high-volume ones); growth only by a generation migration to B; breaks 3F letter |

| Field | Content |
|---|---|
| Durability impact | None between options: acceptance is per entry and per primary in all of them. |
| Latency impact | Not on Voice. Consumer read fan-in: A ≫ B > C. |
| Capacity impact | A: memory and CPU overhead per key and group; hot-tenant shard skew. B: spread controlled by `P_f`. C: single-shard ceiling per family. |
| Cost impact | A: highest operating cost (provisioning per tenant). B / C: low. |
| Migration impact | Changing later from C to B, or changing `P_f`, uses the generation procedure (LCY-07); from A to anything is a full re-provisioning. |
| Numeric values | 7A §32.2 forbids invented sizing figures. Under B the owner either approves `P_f = 1` for every family in `g1` (B mechanics with C's initial footprint) with 7K setting larger values for a later generation from measurements, or supplies sourced `P_f` values now. |
| Recommendation (at checkpoint) | **B** (fixed partitions, partition by `aggregate_id`, approved event-bus exception to 3F §16.2), with **`P_f = 1` for all families in `g1`** until 7K measurement justifies a new generation. The owner decided B. |

### 50.4 Preserved decisions (not reopened)

OD-7B-01, OD-7B-02, OD-7C-01 … OD-7C-07, OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B. 7E does not weaken P1-7D-R01 (no `CONFIRMED` without 7E durable acceptance; enforced by ACC-02, WAO-02 … WAO-05 and OD-7E-02 = A), P1-7D-R02, P1-7D-R03 or P1-7D-R04 (7E touches none of the correlation / causation rollout, `POST /calls` ordering or Voice command recovery).

---

## 51. ADR Register

### 51.1 Decided by 7E

| ADR | Context | Decision | Rejected alternatives | Consequence |
|---|---|---|---|---|
| ADR-7E-01 | DD-04 layout | One durable logical stream per 7B semantic owner context (11) plus one SIGNAL stream | Single stream; per-type streams; per-consumer streams | §14 |
| ADR-7E-02 | Fan-out | One record per event, fan-out by consumer groups | Per-consumer duplicate publication | §27 |
| ADR-7E-03 | RS-05 / TPT-06 | Durable / SIGNAL separation by key profile, format marker, route table and port instance | Shared keys with a type filter | §17 |
| ADR-7E-04 | KEY-05 / TPT-03 | Two-field entry: `fmt` marker + exact envelope bytes; no duplicated envelope values | Field-per-envelope-key layout; compressed or base64 envelope | §21 |
| ADR-7E-05 | DD-07 | One group per 7B consumer obligation; stable names; registry-derived | Group per pod, per deployment, per tenant, or one group per domain | §28, §29 |
| ADR-7E-06 | Bootstrap | Current groups created at `0` before relay activation; future groups with an explicit 7G start position | Lazy creation at `$` | §30 |
| ADR-7E-07 | IO-7B-08 | Ordering = per-key append order only; no per-aggregate, global, `event_id` or `occurred_at` order | Promising per-aggregate order | §33 |
| ADR-7E-08 | DD-06 | Group-aware watermark trimming for durable keys with groups; age trimming only for groupless durable keys; `MAXLEN ~` for SIGNAL | Blind `MAXLEN` / TTL on durable keys | §34 – §36 |
| ADR-7E-09 | Stale groups | Governed group retirement only | Automatic deletion on inactivity | §38 |
| ADR-7E-10 | Evolution | Topology generations; no in-place re-partitioning; no live resharding of durable keys | `hash mod new_N` in place; slot migration of live keys | §39 |
| ADR-7E-11 | Redirects | `MOVED` re-issue once on the new owner's connection; `ASK` on durable keys → non-terminal anomaly; node-pinned acknowledgement | Following redirects with acknowledgement on another connection; classifying redirects as row failures | §23.3, §24 |
| ADR-7E-12 | HO-7E-04 | Zero `ROW_REJECTED` categories in V1; default to non-terminal | Treating size, key or capacity errors as row-specific | §25 |
| ADR-7E-13 | Health probe | Non-writing probe verifying cluster state, primaries, required replicas, persistence and memory on the target shards; any failing shard → UNHEALTHY | `PING`-only probe; probe by writing an event | §26 |

### 51.2 Decided through owner decisions

| ADR | Context | Decision | Rejected alternatives | Consequence |
|---|---|---|---|---|
| ADR-7E-14 | CNF-7E-01; OD-7E-01 = A | Dedicated, region-local event-transport Redis Cluster with `noeviction` on every node (every primary and every failover replica, verified on both roles before publication and after every role change) for durable streams, their group state and the SIGNAL key | Shared cluster under `volatile-lru`; shared cluster under `noeviction`; any eviction-capable placement | §12.3, §13.4, EVC-05 … EVC-08, FMD-10, CAP-05, HP-07 |
| ADR-7E-15 | HO-7E-03; OD-7E-02 = A | `CONFIRMED` iff `XADD` returned an entry ID and the subsequent `WAITAOF 1 1 <bounded timeout>` on the same connection returned local ≥ 1 and replicas ≥ 1; AOF `everysec` on all nodes; one replica per primary, proven as total shard replica membership of exactly one from cluster topology (not a connected-replica count) — the replica that fsynced the entry — which is automatic-failover eligible (`cluster-replica-no-failover no`, no `nofailover` flag, validity factor kept at the default) with no automatic replica migration, and every node eligible for promotion already carrying `maxmemory-policy noeviction` (FMD-10, CAP-05), kept so by governed topology changes (FMD-09, CAP-04, TOPO-10 … TOPO-12); Redis 7.2+ capability gate; declared V1 normal fault model FMD-06 | `XADD` ID alone; `WAIT` only (hazard H-1); `appendfsync always`; two replicas per primary in V1 | §11, §23.5, §25, §26, §48 |
| ADR-7E-16 | CNF-7E-02; OD-7E-03 = B | Fixed partitions per durable family keyed by valid non-null `aggregate_id` through PF-1 (CRC-32/ISO-HDLC over the 16 UUID octets, `mod P_f`); a NULL `aggregate_id` gets no route (`NONE` → 7D `RELAY_CAPABILITY`, no fallback partition); `P_f = 1` per family in `g1`; key grammar of §15.4; governed exception to 3F §16.2 | Per-tenant streams; `organization_id` partitioning; a permanent single stream per family; runtime hashes; any partition-0 fallback for NULL `aggregate_id` (forbidden, P1-7E-07) | §15.4, §16, §20 |
| ADR-7E-17 | 7D PBT-01 … PBT-03 with multi-shard routing | A claim batch is split into one pipelined transport batch per target primary, each confirmed only by its own `WAITAOF`; one outcome per `event_id` | One `WAITAOF` for the whole claim batch; cross-shard confirmation; `MULTI` / `EXEC` | §23.5.3 (ALG-01 … ALG-05) |

ADR count: **17**.

---

## 52. Implementation Obligations

Design only; 7E implements none. "Blocking" means blocking the named implementation step.

| IO | Obligation | Owner | Dependency | Blocking? |
|---|---|---|---|---|
| IO-7E-01 | Dedicated event-transport Redis Cluster per active region (DEP-01 … DEP-07, TOPO-01 … TOPO-12): Redis Open Source 7.2+, cluster mode, ≥ 3 primaries with exactly 1 replica each (total membership), automatic replica migration disabled (TOPO-10), `cluster-replica-no-failover no` configured and verified on every event-transport replica (TOPO-11), `cluster-replica-validity-factor` kept non-zero at the default `10` (TOPO-12), governed replica-membership change procedure (FMD-09), `maxmemory-policy noeviction` configured and verified with `CONFIG GET` on every event-transport node, replicas included (TOPO-05, CAP-07), with a configured `maxmemory`, AOF `appendfsync everysec` on all nodes, `min-replicas-to-write 1`, anti-affinity, persistent volumes; plus the deployment-verification step of CAP-07 | Platform infrastructure; 7K sizing | OD-7E-01 = A, OD-7E-02 = A | Blocks relay go-live |
| IO-7E-02 | Stream provisioning: create durable keys and groups at `0` with `MKSTREAM` per generation (BST-01, BST-06) | Platform event infrastructure | IO-7E-14 | Blocks relay go-live |
| IO-7E-03 | Route registry artifact (code-owned) reproducing §18.2 and §19.1 exactly | Platform event infrastructure | 7C IO-7C-02 manifest | Blocks relay go-live |
| IO-7E-04 | CI check: the route registry covers exactly the 107 durable pairs and 4 SIGNAL pairs of the 7C manifest, with no pattern keys and no overlap | Platform event infrastructure | IO-7E-03 | Blocks relay go-live |
| IO-7E-05 | `route_for` implementation (RTE-01 … RTE-09, including the NULL-`aggregate_id` guard returning `NONE`), PF-1 (§16.3) and the §15.4 key grammar | Platform event infrastructure | OD-7E-03 = B | Blocks relay go-live |
| IO-7E-06 | SIGNAL route table and publisher transport (SPB-01 … SPB-04) | Voice / Platform | 7D IO-7D-21 | Non-blocking for relay |
| IO-7E-07 | Entry encoder (`fmt`, `env`; ENT-01 … ENT-08) | Platform event infrastructure | — | Blocks relay go-live |
| IO-7E-08 | Cluster client selection proving that `XADD` and `WAITAOF` run on the same node-pinned connection (AFF-01 … AFF-05, WAO-01, WAO-04) and redirect handling (RED-01 … RED-06) | Platform event infrastructure | OD-7E-02 = A | **Blocks relay go-live if no conforming client exists** |
| IO-7E-09 | Adapter `publish` per §23.5.3: per-primary batching, `WAITAOF 1 1` with positive bounded timeout, success criterion WAO-02, per-entry outcomes (ACC-01 … ACC-11, WAO-01 … WAO-08, ALG-01 … ALG-05) | Platform event infrastructure | OD-7E-02 = A | Blocks relay go-live |
| IO-7E-10 | Outcome classifier per CL-01 … CL-21 and CLS-01 … CLS-04 | Platform event infrastructure | IO-7E-09 | Blocks relay go-live |
| IO-7E-11 | Health probe HP-01 … HP-08 (HP-03 / HP-05 enumerate total shard membership), HPR-01 … HPR-05, target set §26.3 | Platform event infrastructure | IO-7E-26 | Blocks relay go-live |
| IO-7E-12 | Chaos suite demonstrating MF-03, MF-04, MF-06 … MF-10 on the deployed Redis version and every inside-model fault of FMD-06 (TF-01 … TF-16, TF-21, TF-22) with zero loss of `CONFIRMED` entries, including the H-1 restart-before-failover case | Platform; 7K | IO-7E-09 | Blocks relay go-live |
| IO-7E-13 | Relay activation gate: refuse publication to keys whose registered groups are missing (BST-02); generation configuration gate (LCY-07 step 3) | Platform event infrastructure | IO-7E-02 | Blocks relay go-live |
| IO-7E-14 | Group registry artifact reproducing §29 exactly, with a CI check against 7B CON-01 … CON-11 and the rule that no two obligations share a group (GRP-01, GRP-02, FAN-02) | Platform event infrastructure | — | Blocks consumer go-live |
| IO-7E-15 | Safe-trim worker (TRM-01 … TRM-11, GLR-01 … GLR-05, TTL-02) | Platform event infrastructure; 7K cadence | IO-7E-14 | Blocks production retention (until it runs, nothing is trimmed — safe but unbounded) |
| IO-7E-16 | SIGNAL trim configuration (`N_signal`, SGR-01) | Platform; 7K | 7K | Non-blocking |
| IO-7E-17 | Stream / group lifecycle tooling: generation migration, drain verification, governed retirement, trim pause (LCY-07, RET-03, TRM-07) | Platform; 7G / 7K | 7G | Blocks the first generation change / retirement |
| IO-7E-18 | Telemetry for §49.4 with 7J names | Platform; 7J | 7J | Non-blocking for 7E |
| IO-7E-19 | Redis ACL users and credentials per role (SCY-05) | Platform; 7I | 7I | Blocks production |
| IO-7E-20 | 7F consumer integration: per-key read loop (XSL-02), `NOACK` prohibition (GRP-07), `DELCONSUMER` rule (GRP-10), unsubscribed-type acknowledgement (GRP-08) | 7F / consuming domains | 7F | Blocks consumer go-live |
| IO-7E-21 | 7G reclaim integration (`XAUTOCLAIM` idle threshold, delivery counts, poison handling; PEL-02 … PEL-04) | 7G | 7G | Blocks consumer go-live |
| IO-7E-22 | Documentary reconciliation (controlled amendments by the owners, not by 7E): 3F §11.2, §16.1 – §16.3 noting the dedicated event-transport cluster and the OD-7E-03 hash-tag exception; 3F §16.3's shared-cluster eviction impossibility for its own key spaces (CNF-7E-15); 5A §18.2 namespace catalogue; 3A §6.3 wrapper scope; 6D L625 wording | 3F / 5A / 3A / 6D owners; 7K | OD-7E-01 = A, OD-7E-03 = B | Non-blocking for 7E |
| IO-7E-23 | 7K sizing and benchmarks: HE-7K-08 list (`XADD` throughput, `WAITAOF` latency, batches per shard, batch-50 interaction, lease / deadline margin, consumer lag, memory growth, `P_f` thresholds), memory headroom, `T_groupless`, `N_signal`, lag bounds, timeouts | 7K | 7K | Blocks production tuning only |
| IO-7E-24 | Region binding of the event transport (RSD-01 … RSD-04) with the relay region tag (7D IO-7D-11) | Platform; 7K | 7K | Blocks relay go-live |
| IO-7E-25 | Controlled 7B reconciliation of IO-7B-08 / CR-04 wording to the actual guarantee (append order per key; partition affinity is not per-aggregate ordering; ORD-7E-06, ORD-7E-10). 7E does not edit 7B | 7B owner (controlled amendment); 7F | 7F design | Non-blocking for 7E; 7F MUST design to ORD-7E-09 regardless |
| IO-7E-26 | Startup capability gate CAP-01 … CAP-09 in the relay entrypoint and adapter, including `shard_capable` with total shard membership, replica-identity matching automatic-failover eligibility (`nofailover` flag absent; `cluster-replica-no-failover no` attested) and `maxmemory_policy:noeviction` on the primary and on its failover replica, re-run after every role change; tests reproduce decision-table cases T-01 … T-16 and RC-01 … RC-03 (§23.5.2) | Platform event infrastructure | IO-7E-01 | Blocks relay go-live |
| IO-7E-27 | PF-1 conformance: every routing implementation reproduces the §16.3 test vectors and the CRC-32 check value; CI rejects any runtime / seeded hash; a test proves a NULL-`aggregate_id` row gets `NONE` (→ `RELAY_CAPABILITY`), issues no `XADD` and is never marked `PUBLISHED` or `FAILED` | Platform event infrastructure | IO-7E-05 | Blocks relay go-live |

IO count: **27**.

---

## 53. Deferred Items

| ID | Item | Owner | Reason | Activation condition |
|---|---|---|---|---|
| DEF-7E-01 | PEL idle threshold, retry timing, delivery-count limits, poison, DLQ, parking | 7G | 7G scope; no effect on transport safety (PEL-01 … PEL-05 hold for any value) | 7G design |
| DEF-7E-02 | `T_groupless`, `N_signal`, retention floor | 7K | Numbers only; durable safety does not depend on them (§34) | 7K capacity design |
| DEF-7E-03 | `P_f` values for generations after `g1` | 7K | Numbers only; generation procedure fixed (LCY-07) | 7K measurement |
| DEF-7E-04 | `min-replicas-max-lag`, `WAITAOF` timeout value (always positive and bounded, WAO-03), probe interval / backoff | 7J / 7K | Values only; outcomes for any value are fixed by §25 | Benchmarks (IO-7E-12) |
| DEF-7E-05 | Final metric names, SLOs, alerts | 7J | 7J scope | 7J design |
| DEF-7E-06 | Final operator permission model and payload classification | 7I | 7I scope; SCY-01 … SCY-05 binding meanwhile | 7I design |
| DEF-7E-07 | Routes for DS-01 … DS-16, DS-18 | 7B / 7C then 7E | No binding and no consumer exists (SR-04) | Governed 7B + 7C binding |
| DEF-7E-08 | Future-consumer backfill policy | 7G | Governed replay decision (BST-04) | First future consumer |

No deferred item leaves durability or routing behaviour open: the three items that would have (deployment / eviction, acceptance mechanism, partition / hash tag) were decided by the owner (OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B) and are fully specified in §12, §13, §16 and §23.

---

## 54. Conflict Register

| CNF | Sources | Conflict | Resolution | Severity |
|---|---|---|---|---|
| CNF-7E-01 | 3F §16.3 vs Redis instance-level `maxmemory-policy` (MF-18); 7D TPT-02 | Per-key-space eviction table not implementable in one cluster; `allkeys-lru` could evict durable streams | **Resolved by OD-7E-01 = A** for the event-transport concern: dedicated `noeviction` cluster (§12.3, §13.4). The shared-cluster remainder is CNF-7E-15 | Resolved (owner decision) |
| CNF-7E-02 | 3F §16.2 `{tenant_id}` rule; 5A layer 4 vs scalable event-bus partitioning | Literal compliance means per-tenant streams and group explosion | **Resolved by OD-7E-03 = B**: governed exception for event-transport keys; `aggregate_id` partitioning (§15.4, §16). 3F not edited; documentary reconciliation IO-7E-22 | Resolved (owner decision) |
| CNF-7E-03 | 3F §10.1 / §11.2 "acceptable loss", 5A §24.2 "AOF best-effort" vs 7D TPT-02 / HO-7E-03 | Redis persistence described as best-effort vs zero normal-path loss after `CONFIRMED` | By concern: Redis stays non-authoritative (ROLE-01 … ROLE-05); acceptance is **OD-7E-02 = A** (`WAITAOF 1 1`, §23.5) with the declared normal model FMD-06; outside-model faults use the 7D CLN-08 repair path | Resolved (owner decision) |
| CNF-7E-04 | 6D L625 "the outbox-publisher's consumer-group mechanism" (7D CNF-7D-09, Minor-7D-06) | Relay described as a consumer-group participant | The relay only writes (`XADD`) and is never a group member; the 6D per-call WebSocket replay buffer is a Class-F buffer outside the 7E namespace. Documentary reconciliation IO-7E-22 | Minor |
| CNF-7E-05 | 6C L258, L628 "existing consumer-group mechanism … retry/redelivery semantics (3A §6.3)" | Generic wording | Consistent with §28 / §31; retry policy is 7G's | Minor (no contradiction) |
| CNF-7E-06 | 4G L678 "consumer group: analytics" | Phase-4 lineage | Consistent with one group per obligation (`cg.analytics.projections`) | Minor (no contradiction) |
| CNF-7E-07 | 4H ISSUE-08 consumer-group restriction for `user.registered` | Phase-4 event not in the 7B catalogue | Superseded by 7B; no route, no group | Minor |
| CNF-7E-08 | 5J L2472 "Celery workers processing the Redis Streams consumer group" | Consumer implementation wording | Consumer runtime is 7F's; group identity per §28 | Minor |
| CNF-7E-09 | 5A §18.2 "Redis Namespace Catalogue (Complete)" vs new stream keys | Catalogue predates 7E | Stream keys use the 3A `stream:` purpose (NS-05); documentary reconciliation IO-7E-22 | Minor |
| CNF-7E-10 | 7B IO-7B-08 "consumers already assume only per-aggregate ordering" vs 7A ORD-03 / ORD-05, 7D SCL-02 | Implied per-aggregate ordering, which the frozen relay (concurrent claim loops, `SKIP LOCKED`) cannot provide and which `aggregate_id` partition affinity does not create | **Not resolved by 7E.** 7E states the actual guarantee (ORD-7E-01, ORD-7E-02, ORD-7E-06, ORD-7E-10); 7F designs to ORD-7E-09 (HE-7F-04); the 7B wording needs a controlled reconciliation (IO-7E-25). 7B is not edited | **Open — controlled reconciliation** (non-blocking for 7E; see Minor-7E-04) |
| CNF-7E-11 | 7D TPT-09 "262144 bytes" vs 077 CHECK `length(payload::TEXT)` (characters) | Bytes vs characters | 7E accepts the physical maximum (≤ 1 048 576 UTF-8 bytes of payload text; SIZ-01, SIZ-02) | Minor |
| CNF-7E-12 | 7C SIG-R04 ("Redis Streams direct or lighter-weight internal pub/sub") | SIGNAL transport alternative | 7A RS-01 fixes Redis Streams for Class D; Analytics needs group reads; SIGNAL uses Redis Streams (§19) | Minor (resolved by 7A) |
| CNF-7E-13 | 3F §12.1 region-2 "Redis Replica — cold standby" vs 7A RES-02 / RES-03 | Cross-region copy of stream data | RSD-04: no cross-region copy of event-transport data without a governed 7K decision | Minor (routed to 7K) |
| CNF-7E-14 | 3A §6.3 wrapper `{tenant_id}` first-segment enforcement vs stream keys | Wrapper behaviour | Resolved by OD-7E-03 = B: event-transport keys use the §15.4 grammar and are written by the event-transport adapter against the dedicated cluster, not through the 3A cache wrapper; wrapper documentation reconciled by IO-7E-22 | Resolved (owner decision) |
| CNF-7E-15 | 3F §16.3 per-key-space eviction intent (sessions `allkeys-lru`, campaign queue and retry-queue keys `noeviction`) on the **shared** hot-tier cluster vs instance-level `maxmemory-policy` (MF-18) | The impossibility affects non-event key spaces too (for example campaign queues) | Outside 7E's scope: 7E does not redesign those key spaces (EVC-08, DEP-07). Inherited conflict handed to the 3F owner and 7K (IO-7E-22) | Open — handed off (non-blocking for 7E) |

CNF count: **15**. None silently resolved. CNF-7E-01 … CNF-7E-03 and CNF-7E-14 are resolved by the owner decisions; CNF-7E-10 (7B ordering wording) and CNF-7E-15 (shared-cluster eviction for non-event key spaces) remain open as controlled, handed-off conflicts that do not block 7E.

---

## 55. Findings

### 55.1 Severity

| Severity | Examples |
|---|---|
| P0 | Residual normal-failover loss allowed; `XADD` alone `CONFIRMED`; evictable durable stream; migration 113; frozen 7A – 7D modified; 7F started; Billing via SIGNAL; Redis authoritative; cross-region global bus; wildcard routing |
| P1 | Trim can lose a current group's entries; independent consumers share a group; bootstrap skips retained entries; non-deterministic topology; one shard failure loses `CONFIRMED` entries; valid large event rejected; redirects burn retry budget; durable / SIGNAL overlap; incomplete group registry; partition change loses traffic; unsafe memory pressure; owner choice silently made |
| Minor | Naming, future tuning values, wording, non-binding estimates |

### 55.2 Findings

| ID | Finding | Disposition | Status |
|---|---|---|---|
| P1-7E-01 | 3F per-key-space eviction cannot be implemented in one cluster; durable streams could be evicted under `allkeys-lru` | OD-7E-01 = A; §12.3, §13.4 | RESOLVED |
| P1-7E-02 | `WAIT`-only acceptance loses confirmed entries under H-1; acceptance mechanism was a real tradeoff | OD-7E-02 = A; §11, §23.5 | RESOLVED |
| P1-7E-03 | 3F `{tenant_id}` hash-tag rule conflicts with scalable event-bus partitioning | OD-7E-03 = B; §15.4, §16 | RESOLVED |
| P1-7E-04 | Found while completing §23.5: a `WAITAOF` timeout of `0` blocks indefinitely (MF-19), which would let one stalled confirmation outlive the relay lease | WAO-03 (positive, bounded timeout; socket timeout longer), F7E-39 | RESOLVED |
| P1-7E-05 | Found while completing §23.5: classifying "capability missing" as `NOT_ATTEMPTED` would not reliably open the 7D gate (GATE-02 opens on connection-caused `NOT_ATTEMPTED` only) | CL-21 classifies it `TRANSPORT_UNAVAILABLE` (7D §22.2 configuration failure); CAP-08 startup precondition | RESOLVED |
| P1-7E-06 | Found while completing §11.4: adding replicas would let a non-fsynced replica be promoted (MF-20), so `WAITAOF 1 1` would silently stop proving FMD-06 | FMD-09 revalidation rule; CAP-04, HP-05 treat replica count ≠ 1 as not capable; F7E-38 (the check itself was strengthened by P1-7E-08) | RESOLVED |
| P1-7E-07 | **Found by independent freeze-gate review.** PF-1 mapped a NULL `aggregate_id` to partition 0 as a "deterministic fallback", so a contract-invalid row (7C ENV-06 / AGG-04 require a non-null `aggregate_id`; the physical column is nullable) could be appended, durability-confirmed and marked `PUBLISHED`, contrary to 7D MAT-04 (no repair) and F7D-14 (non-conformant row → non-terminal `RELAY_CAPABILITY`) | PF-1 now has a valid-non-null precondition and no NULL branch; `route_for` returns `NONE` for a NULL `aggregate_id` before any partition is computed, so 7D defers the row as `RELAY_CAPABILITY` with internal reason `INVALID_ROUTING_ATTRIBUTE`; no `XADD`, never `CONFIRMED`, `ROW_REJECTED` or `FAILED`, no partition 0, no zero UUID, no `organization_id` or payload substitute (PRT-01, PRT-07, RTE-09, ALG-06, F7E-40, §50.3 correction, ADR-7E-16, IO-7E-05, IO-7E-27) | RESOLVED |
| P1-7E-08 | **Found by independent freeze-gate review.** CAP-04 and HP-05 checked only that a primary had exactly one *connected* replica (`INFO replication`), which does not prove the FMD-09 topology: a second configured replica that is failed, disconnected or loading is invisible to `connected_slaves` yet can reconnect behind and be promoted | CAP-04 / HP-05 now prove total shard replica membership of exactly one in any state from `CLUSTER SHARDS` / `CLUSTER NODES`, that the sole replica is online, connected, within lag and identical to the replica in the primary's replication view, with AOF healthy on both (`shard_capable`, decision table T-01 … T-11); FMD-09 makes replica-membership changes governed; TOPO-10 disables automatic replica migration (MF-21, HP-03, F7E-37, F7E-38, F7E-41, ADR-7E-15, IO-7E-01, IO-7E-11, IO-7E-26). `WAITAOF 1 1` and OD-7E-02 = A are unchanged | RESOLVED |
| P1-7E-09 | **Found by independent freeze-gate review (repository / package integrity).** The reviewed ZIP contained `.claude/settings.local.json`, a local Claude Code settings file with local paths, tool-permission configuration and credential-like assignments. It is untracked and excluded from `git status` only by a user-global ignore rule, so a ZIP of the working directory picked it up | The independent-review package is now built from a clean clone of `HEAD` plus this file only, and its file list is scanned for `.claude/`, `.env*`, keys, credential files and scratch files (§56.3). The local file is not committed, not copied and its values are not reproduced anywhere. The owner is advised to rotate any real or reused credential it contains | RESOLVED |
| P1-7E-10 | **Found by independent freeze-gate review (second review).** CAP-04 / HP-05 proved exactly one healthy, connected, identity-matched, AOF-healthy replica, but not that it is **automatic-failover eligible**. With `cluster-replica-no-failover yes` the replica never attempts automatic failover and carries the `nofailover` flag (MF-22), so a topology violating the automatic-failover model of SRC-03, TF-01, TF-03, FMD-06, FMD-09, DEP-03, ADR-7E-15, G-18 and G-21 could pass every check and confirm entries. FMD-09 also derived "only promotable node" from membership alone | TOPO-11 makes eligibility normative (`cluster-replica-no-failover no`, no `nofailover` flag; manual promotion does not count); TOPO-12 records `cluster-replica-validity-factor` (default `10`) and its exact relationship to the normal model (TF-23 for extended disconnection: no loss, automatic promotion not guaranteed, availability routed to 7K); CAP-04 item (8), CAP-07 attestation, `shard_capable` flag and attestation checks, decision-table cases T-12 / T-13, HP-03 / HP-05 runtime flag check (startup and runtime agree), CL-21, F7E-42; FMD-09 now requires membership = 1 **and** eligibility; MF-22, MF-23, TF-01, ADR-7E-15, IO-7E-01, IO-7E-26, HE-7K-05, G-18, G-21 updated. Failure → `TRANSPORT_UNAVAILABLE` before any durable write; never `ROW_REJECTED` or `FAILED`. OD-7E-02 = A and `WAITAOF 1 1` unchanged | RESOLVED |
| P1-7E-11 | **Found by independent freeze-gate review (third review).** TOPO-05 and EVC-05 required `noeviction` on every event-transport node, but the capability proof enforced it only on current primaries: CAP-05 and HP-07 read the policy on primaries only, CAP-07 attested `maxmemory` but not `maxmemory-policy`, and `shard_capable` did not check the replica's policy. A shard with a `noeviction` primary and an `allkeys-lru` replica could therefore confirm entries; after normal automatic failover the promoted node's own policy takes effect (MF-24), so durable stream and group state would no longer be protected from eviction, contrary to OD-7E-01 = A and the `CONFIRMED` boundary | FMD-10 states the role-change invariant (every node that owns or can become primary for a durable shard is `noeviction`; a role change never yields an eviction-capable durable primary; checks re-run after failover); TOPO-05 and EVC-05 name replicas explicitly; CAP-05 covers every primary and every sole replica; CAP-07 attests `maxmemory-policy noeviction` with `CONFIG GET` on every event-transport node; `shard_capable` reads the policy on both nodes; HP-07 checks the replica at runtime; decision-table cases T-14 … T-16 and role-change cases RC-01 … RC-03; CL-21, F7E-37, F7E-43; MF-24, DEP-03, ADR-7E-14, ADR-7E-15, IO-7E-01, IO-7E-26, G-18, G-21, G-46, G-47 updated. Failure → `TRANSPORT_UNAVAILABLE` before any durable write; never `ROW_REJECTED` or `FAILED`. OD-7E-01 = A unchanged; automatic failover not disabled | RESOLVED |
| Minor-7E-01 | 7D TPT-09 states the bound in bytes; the physical CHECK counts characters (CNF-7E-11) | SIZ-01, SIZ-02 size to the physical maximum | Resolved |
| Minor-7E-02 | 6D L625 consumer-group wording (CNF-7E-04; carried from 7D Minor-7D-06) | IO-7E-22 | Resolved (documentary handoff) |
| Minor-7E-03 | 5A §18.2 catalogue completeness (CNF-7E-09) | IO-7E-22 | Resolved (documentary handoff) |
| Minor-7E-04 | 7B IO-7B-08 / CR-04 per-aggregate ordering wording conflicts with the actual guarantee (CNF-7E-10) | 7E states the true guarantee (ORD-7E-06, ORD-7E-10); 7F bound by ORD-7E-09 (HE-7F-04); controlled 7B reconciliation IO-7E-25 | **Open — controlled reconciliation**, non-blocking for 7E (no 7E rule depends on the 7B wording, and no consumer may rely on it) |
| Minor-7E-05 | `tool_execution.started` registration in Analytics (7C PD2-03) is an Analytics-side precondition for consuming that SIGNAL row | Recorded in §29.2; no transport change | Resolved (routed) |
| Minor-7E-06 | Under the default even slot split, the `voice` and `campaign` keys (high-volume families) hash to the same third of the slot space (§15.4) | Slot placement of empty slots before provisioning is a 7K decision (HE-7K-01); no correctness effect | Resolved (routed to 7K) |
| Minor-7E-07 | 3F §16.3's eviction impossibility also affects shared-cluster key spaces such as campaign queues (CNF-7E-15) | Handed to the 3F owner and 7K (IO-7E-22); not redesigned in 7E | Open — handed off, non-blocking for 7E |
| Minor-7E-09 | **Found by independent freeze-gate review.** SIZ-04 claimed that worst-case retained durable memory "is bounded by retention", contradicting §34.2: a key with an active registered group has no ceiling that may remove entries the group still needs | SIZ-04 corrected: growth continues until the group catches up, is governed out, or `maxmemory` is reached, where `noeviction` refuses writes (`OOM` → `TRANSPORT_UNAVAILABLE`) and the outbox backlog grows; no destructive ceiling introduced | Resolved |
| Minor-7E-10 | **Found by independent freeze-gate review.** The completion report described 7A – 7D as "byte-identical to HEAD", but the Windows working copies of 7A, 7B and 7C are CRLF (`core.autocrlf=true`); only their LF-normalized content matches | Evidence wording corrected to "LF-normalized content/hash matches frozen baseline" (§6); frozen files are not edited | Resolved |
| Minor-7E-11 | **Found by independent freeze-gate review (second review).** The review ZIP held CRLF working-tree copies of tracked files (created under `core.autocrlf=true`) while the `HEAD` blobs are LF, so `git status` on a Linux extraction reported tracked files as modified although LF-normalized content was identical | The review clone is now created with `core.autocrlf false` and `git reset --hard HEAD` before the LF-only 7E file is copied; every tracked file in the archive is checked to reproduce its `HEAD` blob byte-for-byte, and `git status` / `ls-files --others` run on the extracted package show only the 7E file (§56.3). Frozen documents and `.gitattributes` are not touched | Resolved |
| Minor-7E-08 | With exactly one replica per primary (OD-7E-02 = A), a shard that has just failed over has no replica until one is reattached (TF-22); `WAITAOF 1 1` cannot succeed there, and because the probe is all-or-nothing per relay loop (HPR-02) durable claiming pauses until the shard regains a replica. No loss and no terminal outcome result | Accepted consequence of the owner decision; replica re-attachment automation and the availability budget are 7K's (HE-7K-05) | Resolved (routed to 7K) |

Totals: **P0 = 0. P1 = 0 open (11 resolved: P1-7E-01 … P1-7E-11, of which P1-7E-07 … P1-7E-11 were found by independent freeze-gate reviews). Minor = 11** (9 resolved or routed; Minor-7E-04 and Minor-7E-07 open as controlled, non-blocking reconciliations).

---

## 56. Validation Results

### 56.1 Semantic validator

A scratch semantic validator was run **outside the repository** (session scratchpad; not added to git). It checks contracts, not headings: 332 assertion sites (991 assertions executed on the final document, plus a sentence-level scan for unnegated claims) covering the frozen hashes and line counts of 7A – 7D and the 20 Phase-6 artifacts registered in 7B §1.1; 112 SQL / 112 Alembic, root `001_5B`, sole head `112_5H5`, linear chain, no migration 113, no 7F, and that the only repository change is this file; route-table equality against the 7C manifest (107 exact pairs, EV-014 as its three members, version 1, each exactly once, no pattern key); family of every route equal to its 7B semantic owner; per-consumer event sets equal to 7B CON-01 … CON-11; the consumed-event union (31) and the 76 no-consumer rows; the 4 SIGNAL pairs, their single Analytics group, durable / SIGNAL disjointness, no Billing on SIGNAL, no route for the 17 unbound Class-D signals; the group inventory (11 + 1 groups, 18 + 1 placements, per-stream view, name rules); the 12 V1 keys, their grammar and their hash slots recomputed with CRC16-XMODEM; PF-1 parameters and every test vector recomputed with CRC-32; the acceptance contract (`XADD` alone never `CONFIRMED`, same-connection `WAITAOF 1 1`, thresholds `[≥ 1, ≥ 1]`, positive bounded timeout, per-shard confirmation, a single `CONFIRMED` assignment in the algorithm gated on the `WAITAOF` result, no `MULTI` / Lua / `MAXLEN` in the algorithm); the classifier (21 rows, none `ROW_REJECTED`, `CONFIRMED` only in CL-18); the fault model (22 rows, inside / outside classification, no inside loss); the capability gate; eviction / deployment rules; retention (watermark, no blind `MAXLEN` on durable `XADD`, no durable TTL, governed retirement); ordering (append order only, partition affinity is not aggregate order, the 7B conflict kept open); tenancy, security, residency, Voice and SIGNAL rules; phase boundaries; unnegated-claim detection for exactly-once, global / per-aggregate order, strong consistency, zero-loss, eviction, `XADD`-alone, cross-region and per-tenant claims; owner-decision status; findings totals; markers; the 70 freeze gates; and the exact readiness line.

After the independent freeze-gate review (which found that the earlier 811-assertion validator had missed P1-7E-07 and P1-7E-08), the validator was extended so those defects cannot pass: PF-1 must carry the valid-non-null precondition and contain no NULL branch, `return 0` or fallback; no sentence may map a NULL `aggregate_id` to partition 0; `route_for` must hold the NULL guard after the exact lookup and before partitioning, returning `NONE` and never a Route; RTE-09, PRT-07, ALG-06 and F7E-40 must keep the NULL row away from `XADD`, `CONFIRMED`, `ROW_REJECTED`, `FAILED` and partition 0 and on the non-terminal `RELAY_CAPABILITY` path; CAP-04 and HP-05 must prove total shard replica membership from `CLUSTER SHARDS` / `CLUSTER NODES` (never `connected_slaves` alone); `shard_capable` must derive replicas from all members in any state, require exactly one, check replica identity, health, lag and AOF; every row of decision table T-01 … T-11 is recomputed against a reference model of the rule and a hidden failed / loading / disconnected second replica must be NOT CAPABLE; FMD-09 governance and TOPO-10 must be present; SIZ-04 must state that retained memory is not bounded by retention; a raw "byte-identical" claim fails whenever the raw working-copy bytes of a frozen file differ from the frozen hash; the findings P1-7E-07 … P1-7E-09 and Minor-7E-09 / Minor-7E-10 must be recorded as independent-review findings; and the repository / package checks of §56.3 (G-12) must hold.

After the second independent freeze-gate review (the 268-site / 909-execution validator had missed P1-7E-10), it was extended again: TOPO-11 must make automatic-failover eligibility normative with `cluster-replica-no-failover no` and no `nofailover` flag, and must not be weakened; CAP-07 and IO-7E-01 must configure and verify the setting; CAP-04 must carry item (8); `shard_capable` must contain both the `nofailover` flag check and the deployment-attestation check; the decision table (now T-01 … T-13, recomputed against the reference model with two eligibility inputs) must contain an otherwise-healthy sole replica with the `nofailover` flag and one with `cluster-replica-no-failover yes` attested, both NOT CAPABLE; HP-03 / HP-05 must check the flag at runtime; FMD-09 must derive the promotable set from membership = 1 **and** eligibility and must not contain the membership-only wording; G-18 and G-21 evidence must cite failover eligibility; F7E-42 must show no durable `XADD`, retained obligation, non-terminal `TRANSPORT_UNAVAILABLE`, never `ROW_REJECTED` / `FAILED`; CL-21, ADR-7E-15, IO-7E-26, TF-01, TF-23, TOPO-12, MF-22 and MF-23 must carry the eligibility and validity-factor statements; the P1-7E-10 record must exist and be resolved; and every tracked file in the review package must reproduce its `HEAD` blob byte-for-byte (Minor-7E-11).

After the third independent freeze-gate review (the 298-site / 943-execution validator had not detected that the replica's eviction policy was unchecked, P1-7E-11), it was extended again: TOPO-05 must require `noeviction` on every event-transport node, primaries and replicas; CAP-05 must cover every primary and every sole replica and the primary-only wording must be absent; CAP-07 must attest `maxmemory-policy noeviction` with `CONFIG GET` on every event-transport node; `shard_capable` must check the policy of the primary and of the replica (runtime read and attestation) before `return true`; HP-07 must check the replica and go UNHEALTHY on an eviction-capable policy; FMD-10 must state the role-change invariant and the post-failover re-check; the decision table (now T-01 … T-16, recomputed against the reference model with both policies as inputs) must contain a fully healthy `noeviction` / `noeviction` shard that is CAPABLE and an eviction-capable primary, an `allkeys-lru` replica and a `volatile-lru` replica that are NOT CAPABLE; the role-change table RC-01 … RC-03 is recomputed so that no post-failover state with an eviction-capable promoted primary or replica can be declared CAPABLE; F7E-43 must show NOT CAPABLE, no durable `XADD`, retained obligation and non-terminal `TRANSPORT_UNAVAILABLE`, never `ROW_REJECTED` / `FAILED`; F7E-37 and CL-21 must name the failover replica; the evidence of G-18, G-21, G-46 and G-47 must cite replica eviction safety; EVC-05, DEP-03, CAP-09, MF-24, ADR-7E-14, ADR-7E-15, IO-7E-01 and IO-7E-26 must carry the invariant; and the P1-7E-11 record must exist and be resolved. The assertions for P1-7E-07, P1-7E-08 and P1-7E-10 are unchanged and still pass.

Result on the final document: **991 assertions executed, 0 failures.**

### 56.2 Adversarial mutation harness

A scratch harness applied **217 semantic mutations** (the original 140, plus 32 added after the first independent freeze-gate review, 21 after the second and 24 after the third; none removed) to the document text (and, for repository-integrity mutations, to an in-memory overlay of the repository: a modified 7C / 7D, an added migration 113, an added 7F file, a validator placed in the repository). Every mutation is a targeted semantic change, including the 100 required by the 7E work order (from "`XADD` alone = `CONFIRMED`" to "final line says FROZEN") and additional targeted mutations for OD-7E-01 (shared or evictable placement, `appendfsync`, `noeviction` removal), OD-7E-02 (`WAITAOF` on another connection, thresholds weakened, timeout `0`, timeout treated as success, cross-shard confirmation, `CONFIRMED` before `WAITAOF`, Redis 7.2 prerequisite removed, capability gate removed, replica-count revalidation removed), OD-7E-03 (per-tenant keys, `organization_id` partitioning, runtime hash, wrong test vector, wrong hash slot, `P_f` changed in place) and the ordering conflict (an inserted false ordering guarantee derived from partition affinity; CNF-7E-10 marked resolved). The 32 remediation mutations cover P1-7E-07 (PF-1 NULL → `return 0`, guard removed from `route_for`, NULL row sent to `XADD`, NULL row `CONFIRMED`, guard returning a Route, partition-0 wording, `ROW_REJECTED`, `FAILED`, `organization_id` substitute), P1-7E-08 (CAP-04 / HP-05 reverted to a connected-replica test, a connected-plus-failed replica marked CAPABLE, membership enumeration removed, `== 1` relaxed to `>= 1`, an extra configured replica accepted, identity check removed, replicas filtered to online only, governance and replica-migration rules weakened), P1-7E-09 / G-12 (`.claude/settings.local.json`, `.env`, a private key or a scratch validator added to the review package; an extra untracked artifact; a stale 7E copy in the package), Minor-7E-09 / Minor-7E-10 (the false retention bound and the false raw-identity evidence statement restored) and a reopened P1. For text mutations the harness simulates a package rebuilt from the mutated text, so a mutation is never caught merely because the package copy differs. The 21 mutations of the second remediation cover P1-7E-10 (`cluster-replica-no-failover yes`; the invariant weakened to either value; a healthy `nofailover` replica marked CAPABLE; T-01 given the `nofailover` flag yet left CAPABLE; the flag check and the attestation check each deleted from `shard_capable`; the HP-05 runtime check and the HP-03 flag enumeration deleted; deployment verification of the setting deleted from CAP-07 and from IO-7E-01; CAP-04 item (8) deleted; FMD-09 restored to membership-only promotability; durable publication allowed while the eligibility check fails; the eligibility failure classified `ROW_REJECTED` / `FAILED`; G-18 and G-21 evidence stripped of eligibility; TOPO-12 deleted; TF-23 claiming guaranteed automatic promotion; ADR-7E-15 stripped; P1-7E-10 left open) and Minor-7E-11 (a CRLF working copy placed in the review package). The 24 mutations of the third remediation cover P1-7E-11: the sole replica set to `allkeys-lru` or to `volatile-lru` while the shard stays CAPABLE; T-15 / T-16 marked CAPABLE; an eviction-capable primary (T-14) marked CAPABLE; the replica check removed from CAP-05 and CAP-05 restored to primary-only wording; `maxmemory-policy` removed from the CAP-07 all-node attestation; the replica-policy check and the primary-policy check each deleted from `shard_capable`; the replica check deleted from HP-07; durable publication allowed while the replica policy is unsafe; a post-failover shard with an `allkeys-lru` replica, and a promoted `allkeys-lru` primary, each left CAPABLE; the failure classified `ROW_REJECTED` and `FAILED`; eviction-safety evidence stripped from G-18, G-21, G-46 and G-47; TOPO-05 weakened to primaries; FMD-10 reversed; the post-failover re-check removed; P1-7E-11 left open.

| Measure | Result |
|---|---:|
| Clean-document checks | 0 failures |
| Mutations | 217 |
| Detected (validator FAIL) | 217 |
| Missed | 0 |
| Harness errors | 0 |
| No-op mutations | 0 |

Each detected mutation was also checked to fail on the assertion it targets (not by collateral damage to unrelated text); for the 77 remediation mutations (141 … 217) the harness enforces this automatically with an expected-assertion tag per mutation.

### 56.3 Repository and independent-review package integrity (P1-7E-09, G-12)

| Check | Result |
|---|---|
| Source working tree `git status --short --untracked-files=all` | only `?? docs/phase-07-event-architecture/7E-Redis-Streams-Topology.md` |
| Source working tree `git ls-files --others --exclude-standard` | only the 7E file |
| Local `.claude/settings.local.json` in the developer workspace | present, untracked, ignored only by a user-global ignore rule; **not** committed, **not** copied into the package; its contents are not reproduced here |
| Package construction | clean clone of `HEAD` with `core.autocrlf false` and `git reset --hard HEAD` (LF working tree), remote removed, plus this LF-only file; zipped with its `.git` directory so the reviewer can run Git commands. No frozen document and no `.gitattributes` is changed |
| Tracked files in the archive versus `HEAD` | every tracked file reproduces its `HEAD` blob byte-for-byte (Git blob id recomputed from the archive bytes); no CRLF working copies (Minor-7E-11) |
| `git status --short --untracked-files=all`, run on a fresh extraction of the ZIP | only `?? docs/phase-07-event-architecture/7E-Redis-Streams-Topology.md` |
| `git ls-files --others --exclude-standard`, run on a fresh extraction of the ZIP | only the 7E file |
| Package product file list | exactly the `HEAD` tree plus this file (no extra, none missing) |
| Archive file-list scan | no `.claude/`, `settings.local.json`, `.env*`, key or certificate files, credential / `.netrc` / `.pgpass` files, validator, harness or scratch files |
| Credential-value scan (counts only) | the credential-like values in the local settings file do not occur in any credential context in the package; the only byte match was a coincidental 4-character substring inside a UUID in a committed Phase-5 execution log |
| 7E copy in the package | identical to the validated document |

---

## 57. Freeze Gates

| Gate | Check | Result | Evidence |
|---|---|---|---|
| G-01 | 7A hash exact | PASS | §6 |
| G-02 | 7B hash exact | PASS | §6 |
| G-03 | 7C hash exact | PASS | §6 |
| G-04 | 7D hash exact | PASS | §6 |
| G-05 | Phase-6 frozen docs unchanged | PASS | §6 (20 / 20 hashes and line counts) |
| G-06 | 112 SQL | PASS | §6 |
| G-07 | 112 Alembic | PASS | §6 |
| G-08 | Root `001_5B` | PASS | §6 |
| G-09 | Sole head `112_5H5` | PASS | §6 |
| G-10 | No migration 113 | PASS | §6 |
| G-11 | No 7F | PASS | §6 |
| G-12 | Only 7E changed / new | PASS | §6, §56.3 (git status and `ls-files --others --exclude-standard` list only this file; review package = `HEAD` + this file, no `.claude/` or secret-bearing local file) |
| G-13 | Redis remains non-authoritative | PASS | §9 ROLE-01 … ROLE-06 |
| G-14 | Production topology explicit | PASS | §12.2, §12.3 DEP-01 … DEP-07 (OD-7E-01 = A) |
| G-15 | Normal fault model explicit | PASS | §11.2 TF-01 … TF-22; §11.4 FMD-06 … FMD-09 |
| G-16 | Durable acceptance deterministic | PASS | §23.5 WAO-01 … WAO-08, ALG-01 … ALG-05 (OD-7E-02 = A) |
| G-17 | `XADD` alone insufficient | PASS | ACC-02, MF-01, WAO-02 |
| G-18 | Normal primary failover cannot lose `CONFIRMED` | PASS | TF-01 … TF-03, FMD-05, FMD-06; promotable set proven to be the single fsynced replica by total membership = 1 **and** automatic-failover eligibility (FMD-09, CAP-04 (8), TOPO-11, TOPO-12); the failover candidate is eviction-safe: `noeviction` proven on the replica before confirmation, so the promoted primary cannot evict a `CONFIRMED` entry (FMD-10, CAP-05) |
| G-19 | One per-entry outcome | PASS | ACC-06 … ACC-08, ALG-01 |
| G-20 | Cluster redirects non-terminal | PASS | §24 RED-01 … RED-06, CL-05, CL-06 |
| G-21 | Health probe validates durable capability | PASS | §26 HP-01 … HP-08 (HP-03 / HP-05 total shard membership, replica identity, `nofailover` flag; HP-07 `noeviction` on the primary and on its replica), §23.5.2 `shard_capable` and T-01 … T-16, RC-01 … RC-03, §26.3, CAP-09 |
| G-22 | Stream namespace explicit | PASS | §15.1, §15.4 |
| G-23 | Stream count / layout explicit | PASS | §14.1, NS-08 (11 durable + 1 SIGNAL keys at `P_f = 1`) |
| G-24 | Partition key explicit | PASS | §16 PF-1 (valid non-null `aggregate_id`, no NULL fallback), PRT-06, PRT-07, RTE-09 |
| G-25 | Hash-tag behaviour explicit | PASS | NS-06, NS-07, §15.4 slot table |
| G-26 | EV-001 platform routing explicit | PASS | RTE-06, PRT-02 |
| G-27 | 107 durable exact routes | PASS | §18 |
| G-28 | 4 SIGNAL exact routes | PASS | §19 |
| G-29 | No wildcard | PASS | RR-02, RR-03, RTE-02, SR-01 |
| G-30 | No durable / SIGNAL overlap | PASS | SEP-05, §18, §19 |
| G-31 | Current consumer-group registry complete | PASS | §29 |
| G-32 | Independent consumers have independent groups | PASS | GRP-01, GRP-02, FAN-02 |
| G-33 | Group bootstrap safe | PASS | BST-01 … BST-06 |
| G-34 | No invented future consumers | PASS | §29 (7B-derived only) |
| G-35 | PEL mechanics defined | PASS | §31 |
| G-36 | `XACK` semantics deferred to 7F | PASS | ACK-01 … ACK-03 |
| G-37 | Per-stream ordering truthfully defined | PASS | ORD-7E-01, ORD-7E-02 |
| G-38 | No global ordering | PASS | ORD-7E-07 |
| G-39 | No unsupported aggregate-order claim | PASS | ORD-7E-06, PRT-04, ORD-7E-10 (7B wording conflict kept open, CNF-7E-10) |
| G-40 | Durable retention safe | PASS | §34 |
| G-41 | No blind `MAXLEN` loss | PASS | TRM-01, §21.1 |
| G-42 | No unsafe durable TTL | PASS | TTL-01 … TTL-04 |
| G-43 | PEL blocks unsafe trim | PASS | TRM-02, TRM-05 |
| G-44 | Group retirement governed | PASS | RET-01 … RET-05 |
| G-45 | SIGNAL retention bounded and best-effort | PASS | §36 |
| G-46 | Memory pressure cannot silently evict durable events | PASS | EVC-05, EVC-06, MEM-01, MEM-02; no automatic-failover candidate may carry an eviction-capable policy: `noeviction` verified on every durable primary and its replica (FMD-10, CAP-05, HP-07, T-14 … T-16) |
| G-47 | Eviction / deployment conflict resolved | PASS | OD-7E-01 = A; §13.4; TOPO-05 operationally enforced on replicas as well as primaries (CAP-05, CAP-07 all-node attestation, HP-07, F7E-43); CNF-7E-01 resolved, shared-cluster remainder handed off (CNF-7E-15) |
| G-48 | Cross-slot behaviour deterministic | PASS | §40 |
| G-49 | Topology-generation evolution deterministic | PASS | §39 LCY-05 … LCY-09, PRT-03 |
| G-50 | Redis outage does not affect DB commit | PASS | §41, §42, 7D GATE-07 |
| G-51 | Tenant authority envelope / DB based | PASS | §44 |
| G-52 | India residency preserved | PASS | §46 |
| G-53 | Voice hot path unaffected | PASS | §47 |
| G-54 | Payload security preserved | PASS | §45, ENT-01 … ENT-08 |
| G-55 | 7F boundary respected | PASS | §4, §32, §49.1 |
| G-56 | 7G boundary respected | PASS | §4, PEL-04, §49.2 |
| G-57 | 7I boundary respected | PASS | §4, SCY-05, §49.3 |
| G-58 | 7J boundary respected | PASS | §4, §49.4 |
| G-59 | 7K boundary respected | PASS | §4, ALG-05, §49.5 |
| G-60 | ADR register complete | PASS | §51 (17) |
| G-61 | IO register complete | PASS | §52 (27) |
| G-62 | Conflicts recorded | PASS | §54 (15) |
| G-63 | Deferred items correctly owned | PASS | §53 |
| G-64 | Open owner decisions = 0 | PASS | §50 (OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B, all resolved and unchanged by the remediation) |
| G-65 | P0 = 0 | PASS | §55 |
| G-66 | P1 = 0 | PASS | §55 (11 raised, 11 resolved, including P1-7E-07 … P1-7E-11 from independent reviews) |
| G-67 | Validator clean | PASS | §56.1 |
| G-68 | All mutations detected | PASS | §56.2 |
| G-69 | No temporary checkpoint marker | PASS | the §0 checkpoint block was removed |
| G-70 | Readiness line exact | PASS | §58 |

Gates: **70**. PASS: **70**. FAIL: **0**.

---

## 58. Freeze-Gate Status

| Item | Value |
|---|---|
| P0 findings | 0 |
| P1 findings | 0 open (P1-7E-01 … P1-7E-11 resolved; P1-7E-07 … P1-7E-11 found by independent freeze-gate reviews and remediated) |
| Minor findings | 11 (Minor-7E-01 … Minor-7E-11; Minor-7E-04 and Minor-7E-07 open as controlled, non-blocking reconciliations) |
| Owner decisions | OD-7E-01 = A, OD-7E-02 = A, OD-7E-03 = B — all resolved; open: 0 |
| ADRs | 17 |
| Implementation obligations | 27 |
| Conflicts recorded | 15 (CNF-7E-10 and CNF-7E-15 open as controlled handoffs) |
| Frozen baselines | 7A / 7B / 7C / 7D hashes exact; 20 Phase-6 hashes exact; 112 SQL + 112 Alembic, head `112_5H5`, no 113, no 7F |
| Counts | 105 semantic durable; 107 exact durable V1 pairs routed; 4 exact SIGNAL V1 pairs routed; 111 total; V2 = 0; 11 durable + 1 SIGNAL stream keys; 11 durable + 1 SIGNAL groups; 18 + 1 Redis group placements |
| Next step | Independent freeze-gate review of 7E. This document does not declare itself approved or frozen and does not begin 7F. |

**PHASE 7E = READY FOR INDEPENDENT FREEZE-GATE REVIEW**
