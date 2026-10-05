# Phase 7D — Transactional Outbox Architecture — AI Voice Agent Platform

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | `docs/phase-07-event-architecture/7D-Transactional-Outbox-Architecture.md` |
| Phase | 7 — Event Architecture |
| Sub-phase | 7D — Transactional Outbox Architecture (outbox and relay implementation architecture inside the existing PostgreSQL outbox schema) |
| Status | **DRAFT — COMPLETE — READY FOR INDEPENDENT REVIEW.** This document does not declare itself frozen. Freezing is an independent-review act. |
| Date | 2026-09-29 (authored); 2026-10-05 (independent freeze-gate remediation, §49.4) |
| Remediation | Independent freeze-gate findings P1-7D-R01 … P1-7D-R04 resolved in place (§49.4); P1-7D-04 retry-budget wording re-checked (§24.1). Pre-remediation LF SHA-256 `86d80300ca128545c04116ce7ba53fe723ee7ae9fde0d5037913c94920fbd90a` / 1518 lines. No owner decision was required. |
| Repository baseline | `main` @ `823181b` ("7C freeze"), working tree clean at start |
| Frozen upstream | 7A, 7B, 7C (hashes in §6); Phase-6 owner and closure documents; Phase-5 migrations `001_5B` … `112_5H5` |
| Owner decisions | OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B — all DECIDED, owner-approved, final (§45). Open owner decisions: **0** |
| Closes on completion | 7A DD-09 (relay polling, batch size, claim lease); 7A DD-21 (mandatory post-commit work dispatch durability, 7D part); 7B IO-7B-10 (relay contract for the 105 durable events and the Class-D publisher contract); 7C DEF-7C-03 (relay batching, 7D part) |
| Does not begin | 7E, 7F, 7G, 7H, 7I, 7J, 7K, 7L |
| Artifact rule | This is the only new or modified project artifact for 7D. No migration, no application code, no SQL, no Redis/Celery artifact, no OpenAPI, no manifest file. Scratch validators run outside the repository. |
| Normative keywords | **MUST**, **MUST NOT**, **SHOULD**, **MAY** carry RFC 2119 meaning. Every rule has a stable ID. |

---

## 2. Purpose

7A fixed what the relay must guarantee (REL-01 … REL-08) and left its design to 7D. 7B fixed which 105 durable events the relay transports and assigned the Class-D publisher contract to 7D (IO-7B-10). 7C fixed the envelope the relay publishes and forbade the relay from validating, repairing, rewriting or upcasting events (DET-09, PV-07, UPC-10).

7D makes the relay implementation-deterministic inside the executed schema of `audit.domain_event_outbox` (`077_5J1.sql`). It defines the producer transaction contract, the row lifecycle, claiming, the claim lease, polling and batching, envelope materialization, the transport port that 7E implements, per-row publish outcomes, the transport availability gate that protects retry budgets during a Redis outage, crash and shutdown behaviour, horizontal scaling, deployment compatibility, cleanup, the Class-D direct-publisher boundary, and the architecture that makes mandatory post-commit work recoverable (DD-21).

## 3. Scope

- Relay execution model, process topology (OD-7D-01), instance identity and ownership boundaries.
- Producer transaction contract for Classes A, B and C, and producer idempotency.
- Outbox row lifecycle, eligibility, claim, concurrency, lease, polling and batching (DD-09).
- Envelope materialization and serialization, and the 7E transport-port boundary.
- Publish outcome classification, partial-batch behaviour, mark-published, mark-failed and deferral.
- Redis-outage behaviour, ambiguous outcomes, crash recovery, graceful shutdown, horizontal scaling and deployment compatibility.
- Outbox cleanup responsibilities.
- The Class-D direct signal publisher boundary.
- Mandatory post-commit work recoverability (DD-21), including asynchronous audit (OD-7D-02) and Voice call-command dispatch (OD-7D-03).
- Security, tenancy, residency and voice-hot-path requirements relevant to the relay.
- Semantic observability emission points, handoffs to 7E / 7F / 7G / 7I / 7J / 7K, ADRs, owner decisions, implementation obligations, findings, failure matrix, validation and freeze gates.

## 4. Non-Goals

7D does not design or decide any of the following.

| Non-goal | Owner |
|---|---|
| Redis stream names, stream count, per-type vs per-context layout, cluster topology, sharding, partition keys, consumer-group names, MAXLEN, TTL, memory sizing, autoscaling, PEL reclaim | 7E |
| Shared inbox schema, consumer dedup implementation, ordering algorithm, consumer transaction model | 7F |
| Final retry delays and counts, DLQ / parked-message architecture, operator replay API and tooling | 7G |
| Webhook delivery architecture, provider-callback processing architecture | 7H |
| Final security / privacy classification, audit-specific security design | 7I |
| Metric names, dashboards, SLOs, alert thresholds, cardinality budgets | 7J |
| Capacity figures, regional deployment topology, global backpressure, disaster recovery | 7K |

7D also does not: create migration 113 or any migration; create a second or per-context outbox; partition the outbox; add RLS; add a broker; introduce Kafka, 2PC or distributed transactions; claim exactly-once delivery; place Redis I/O inside a business transaction; route audio or media through the bus; change any 7C schema or envelope; change the 7B taxonomy; or modify any frozen document.

---

## 5. Authority Model

Authority is **concern-specific**. There is no global "latest document wins" ranking. Conflicts are recorded in §48 and never silently resolved.

| Source | Authoritative for | Not authoritative for |
|---|---|---|
| Executed Phase-5 migrations `001_5B` … `112_5H5` | Physical PostgreSQL truth: columns, types, defaults, CHECKs, indexes, grants, triggers, function signatures and bodies | Event taxonomy, envelope, Phase-7 rules |
| 7A (frozen) | Event-architecture invariants and mechanism standards (DUR, OUT, REL, RS, CEL, AUD, DEL, IDM, ORD, TEN, SEC, VER, FM, RPL, OBS, VOX, BIL, RES, DPL) | Physical schema; per-event taxonomy |
| 7B (frozen) | Taxonomy: event names, classes, producers, consumers, semantic ownership, OD-7B-01 / OD-7B-02 | Envelope field names (7C); physical schema |
| 7C (frozen) | Internal envelope, serialization, version rules, exact manifest bindings, OD-7C-01 … OD-7C-07 | Relay mechanics (7D); stream topology (7E) |
| Phase-6 owner documents 6A – 6M | Bounded-context domain and API semantics, including each flow's post-commit continuation | Relay topology; physical schema where a migration differs |
| AIR, AMI, AAM, AEC, AVS, FAR, Phase-6 certificate | Reconciliation, indexing and validation for their exact concern | Owner semantics that no owner decision settles |
| Phase 4 (4A – 4I) and Phase 3 (3A – 3F) | Lineage where a later frozen owner contract does not supersede it | Anything a source above decides |
| OD-7D-01 … OD-7D-03 (§45) | Only the exact scope written in each decision | Anything outside that scope |

Rules of application:

1. **AUTH-7D-01.** A question is answered by identifying its concern and reading the source that owns that concern.
2. **AUTH-7D-02.** For physical behaviour of the outbox, migration `077_5J1.sql` governs over every prose summary (6C, 6J, 6K, 7A §6.3, 7B §6.2, 7C §10.1). The physical fact table (§8) is derived from the SQL text, not from prose.
3. **AUTH-7D-03.** 7D binds only what 7A delegates to it (§13 REL "Deferred to 7D", DD-09, DD-21) and what 7B / 7C hand to it (IO-7B-10, KEY-05, SIG-R04, DEF-7C-03). 7D never contradicts 7A, 7B or 7C.
4. **AUTH-7D-04.** Where an unresolved conflict materially changed durability, correctness, tenancy, money, compliance or lifecycle behaviour, 7D raised an owner decision (OD-7D-01 … OD-7D-03) and stopped until the owner answered. All three are DECIDED (§45).

---

## 6. Frozen Input Baseline

Verified at the start of this work, against the repository, not against earlier chat memory. Where raw SHA-256 differs only because of CRLF line endings on the working copy, the canonical LF-normalized content hash is compared.

| Item | Expected | Observed (LF-normalized) | Lines | Result |
|---|---|---|---:|---|
| 7A `7A-Event-Architecture-and-Standards.md` | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` | same | 1086 | PASS |
| 7B `7B-Event-Taxonomy-and-Ownership.md` | `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` | same | 2207 | PASS |
| 7C `7C-Event-Envelope-and-Schema-Versioning.md` | `e514e3c4a889775fbc8e9baba3a9ad0558b5228465f240f425d7c762f1d200a0` | same | 3275 | PASS |
| 7C status | APPROVED / FROZEN upstream input; readiness line present; open owner decisions 0 | same | — | PASS |
| 7C counts | 105 semantic durable bindings; 107 exact durable V1 pairs; 4 exact SIGNAL V1 pairs; 111 exact V1 pairs in total; 0 V2 pairs | same (7C §20.8, CSR-02, VRS-07) | — | PASS |
| Phase-6 frozen documents (6A – 6M, AAM, AEC, AMI, AVS, FAR, AIR, certificate) | the 20 hashes registered in 7B §1.1 | all 20 match | — | PASS |
| SQL migrations | 112 (`001_5B.sql` … `112_5H5.sql`) | 112 | — | PASS |
| Alembic revisions | 112 | 112 | — | PASS |
| Alembic root / head | `001_5B` / sole head `112_5H5` | same | — | PASS |
| Alembic chain | one linear chain; 0 missing parents; 0 branches | same (walked root → head: 112 revisions) | — | PASS |
| Migration 113 | absent | absent | — | PASS |
| PostgreSQL baseline | PostgreSQL 18 | PostgreSQL 18 (7A §6.6) | — | PASS |
| `docs/phase-07-event-architecture/` before 7D | 7A, 7B, 7C only | 7A, 7B, 7C only | — | PASS |

Preserved owner decisions (not reopened): OD-7B-01, OD-7B-02, OD-7C-01, OD-7C-02, OD-7C-03, OD-7C-04, OD-7C-05, OD-7C-06, OD-7C-07.

Cited migrations (read-only; LF-normalized SHA-256):

| Migration | SHA-256 | Cited for |
|---|---|---|
| `077_5J1.sql` | `eac7022c4f96993d2e691947d8ebf2fa91ca3db2b9116beaf2c205dd5ee4a990` | The outbox table, indexes, grants, trigger, three relay functions, cleanup note (§8) |
| `109_5B7.sql` | `a761239d7e63e3d2d982f4dbf7291b81711a24dc051c2577bc44ff46052b0cf3` | The only later migration that writes the outbox (`fn_platform_revoke_all_sessions`, EV-001, platform-scoped row) |
| `099_5C1.sql` | read-only | `voice.call_dispatch_keys` and the dispatch-key functions (OD-7D-03, §35.4) |
| `101_5I1.sql` | `e23c58d8cc8e233cfb353371b606c91ecdfc90700ce03fd36046c9e43b1f0d89` | `fn_activate_integration_connection` / `fn_fail_integration_connection` guards (§35) |
| `037_5F.sql`, `083_5F6.sql`, `088_5F8.sql` | read-only | Ingestion-job and reindex-job state, `uq_chunk_position` (§35) |
| `061_5I.sql`, `060_5I.sql`, `062_5I.sql` | read-only | Integration connection status, definition `auth_type`, inbound callback status (§35) |
| `102_5H2.sql` | `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` | Payment-webhook receipt `processing_status` / `next_retry_at` (§35) |
| `094_5D3.sql` | `4bb74bc7dc5ffe5700744411d3ea60d368c95eedadde6daba3a318f3d128d68b` | Consumer-side dedup is separate from the publisher-side outbox (§11) |
| `011_5C.sql` | read-only | `voice.call_sessions.status`, `updated_at`, `trg_cs_updated_at` (§35.5) |

---

## 7. Inputs Inherited from 7A, 7B and 7C

### 7.1 From 7A

| 7A item | Obligation on 7D |
|---|---|
| REL-01 … REL-08 | The relay guarantees; 7D designs how |
| §13 "Deferred to 7D" | Process topology, polling interval, batch size, claim lease duration, publish batching, relay metric names, tuning of Phase-5 defaults |
| DD-09 | Relay polling interval, batch size, claim lock timeout |
| DD-21, CEL-08 … CEL-10, AUD-04a, FM-12, FM-13 | Mandatory post-commit work dispatch durability, with 7G / 7K and per-flow design (7I for audit) |
| DUR-01 … DUR-06, OUT-01 … OUT-07, PR-06, TX-02 | Atomic outbox, single outbox, no external I/O in the producing transaction, no 2PC |
| RS-01 … RS-07, SOT-01 … SOT-04 | Redis is transport only; PostgreSQL outbox state is the authoritative publication obligation |
| FM-01 … FM-13 | Failure invariants the relay must satisfy |
| DPL-01 … DPL-05 | Rolling-deploy compatibility, backlog processable after deploy |
| TEN, SEC, RES, VOX | Tenant, security, residency and voice-latency boundaries |

### 7.2 From 7B

| 7B item | Obligation on 7D |
|---|---|
| IO-7B-10 | Relay contract for all 105 durable events, including the EV-079 row written by the finalization transaction; publisher contract for the 19 current Class-D signals, including the non-durable status of DS-17 and DS-19; relay and publish time are never the Billing occurrence time (OCC-04) |
| TSK-16, TSK-17 | Outbox relay (continuous) and outbox retention purge (periodic) are Platform (7D / 7K) roles |
| §31.2, §31.6 | EV-079 is written only by the finalization worker transaction; the relay "relays the committed outbox row; does not create, alter or time-stamp the business fact" |
| AUD-01 … AUD-05 (7B §20) | Audit is not an outbox consumer; audit does not subscribe to any stream |

### 7.3 From 7C

| 7C item | Obligation on 7D |
|---|---|
| DET-01, DET-09, ADR-7C-01 | The only rename is `id` → `event_id`; the relay publishes committed values exactly |
| KEY-01 … KEY-05 | Closed envelope key set; relay bookkeeping is never an envelope field; the wire encoding is 7D / 7E's and must be lossless and name-preserving |
| CC-01 … CC-03, §10.5 | `correlation_id` / `causation_id` are absent until the OD-7C-04 migration is active; the relay propagates them unchanged once they exist and never derives, overwrites or back-fills them; 7D binds the staged relay rollout (DPC-07) and per-field presence (MAT-10) so that no relay strips a value that is physically present |
| PV-07, UPC-10 | The relay never validates, repairs, rewrites or upcasts events |
| SIG-01 … SIG-11, SIG-R01 … SIG-R06 | SIGNAL envelope; transport of signals is 7D / 7E's |
| §20.8, CSR-02, CSR-09, TDF-01 … TDF-04 | 105 / 107 / 4 / 0; no family, wildcard, regex or prefix key or dispatch |
| DEF-7C-03 | Relay batching, stream names, retries and consumer-group rules (7D, 7E) |

---

## 8. Physical Outbox Fact Table

Derived from the SQL text of `077_5J1.sql` (lines cited) and a search of every migration `078` … `112` for `audit.domain_event_outbox`, `fn_claim_outbox_events`, `fn_mark_outbox_published`, `fn_mark_outbox_failed`, outbox indexes, grants, triggers and cleanup. Migration governs physical behaviour (AUTH-7D-02). 7D changes none of it.

### 8.1 Columns

| Column (077 line) | PostgreSQL type | Null | Default | Notes |
|---|---|---|---|---|
| `id` (L49) | `UUID` | NOT NULL | `gen_uuid_v7()` | Primary key; "doubles as the event's own event_id" |
| `event_type` (L50) | `TEXT` | NOT NULL | — | `chk_outbox_event_type_len` 1 … 200; no pattern CHECK |
| `event_version` (L51) | `INTEGER` | NOT NULL | `1` | "independent of API URL versioning" |
| `organization_id` (L52) | `UUID` | NULL | — | NULL = platform-scoped |
| `aggregate_type` (L55) | `TEXT` | NULL | — | Free text, no FK |
| `aggregate_id` (L58) | `UUID` | NULL | — | — |
| `payload` (L59) | `JSONB` | NOT NULL | — | `chk_outbox_payload_size`: `length(payload::TEXT) <= 262144` |
| `occurred_at` (L60) | `TIMESTAMPTZ` | NOT NULL | `NOW()` | — |
| `status` (L61) | `TEXT` | NOT NULL | `'PENDING'` | `chk_outbox_status`: `PENDING`, `CLAIMED`, `PUBLISHED`, `FAILED` |
| `attempt_count` (L62) | `INTEGER` | NOT NULL | `0` | `chk_outbox_attempt_count`: `>= 0`; no upper bound |
| `max_attempts` (L63) | `INTEGER` | NOT NULL | `10` | `chk_outbox_max_attempts`: `BETWEEN 1 AND 20` |
| `available_at` (L64) | `TIMESTAMPTZ` | NOT NULL | `NOW()` | "claim eligibility; bumped forward on retry backoff" |
| `claimed_by` (L65) | `TEXT` | NULL | — | "publisher worker identifier holding the current claim"; no length CHECK |
| `claimed_at` (L66) | `TIMESTAMPTZ` | NULL | — | — |
| `published_at` (L67) | `TIMESTAMPTZ` | NULL | — | `chk_outbox_published_state`: `(status = 'PUBLISHED') = (published_at IS NOT NULL)` |
| `last_attempt_at` (L68) | `TIMESTAMPTZ` | NULL | — | Set by every claim |
| `last_error` (L69) | `TEXT` | NULL | — | `chk_outbox_last_error_len`: `<= 2000` |

There is **no** `correlation_id` and **no** `causation_id` column today (7C §10.1). There is no `PARTITION BY` (L79) and no RLS (L35–L45, L119).

### 8.2 Indexes (077 L86–L93)

| Index | Definition | Purpose stated in the migration |
|---|---|---|
| `pk_outbox` | `PRIMARY KEY (id)` | Identity |
| `idx_outbox_claim` | `(available_at, id) WHERE status = 'PENDING'` | Primary claim scan |
| `idx_outbox_claimed_stuck` | `(claimed_at) WHERE status = 'CLAIMED'` | Stuck-claim detection / reclaim |
| `idx_outbox_org_type` | `(organization_id, event_type, occurred_at DESC) WHERE organization_id IS NOT NULL` | Observability |
| `idx_outbox_status` | `(status, occurred_at DESC)` | Observability; FAILED visibility |

### 8.3 Grants (077 L124–L127, L163–L164, L184–L185, L224–L225)

| Role | Table privileges | Function EXECUTE |
|---|---|---|
| `app_api` | `INSERT` | none of the three relay functions |
| `app_worker` | `INSERT`, `SELECT` | `fn_claim_outbox_events`, `fn_mark_outbox_published`, `fn_mark_outbox_failed` |
| `app_readonly` | `SELECT` | none |
| `app_platform_admin` | `SELECT`, `UPDATE`, `DELETE` — "manual/emergency intervention only" (L127) | all three |
| `PUBLIC` | none (REVOKE ALL) | none (REVOKE ALL) |

`067_5J.sql` grants `USAGE ON SCHEMA audit` to the four roles. `074_5J.sql` grants `SELECT ON ALL TABLES IN SCHEMA audit` to `app_readonly` and `app_platform_admin`; it runs before `077`, and `077` begins with `REVOKE ALL` and grants explicitly (L124). No migration `078` … `112` changes any outbox grant.

### 8.4 Trigger (077 L104–L117)

`trg_outbox_tenant_check` — `BEFORE INSERT ... FOR EACH ROW EXECUTE FUNCTION audit.fn_outbox_tenant_check()` (SECURITY DEFINER). It raises only when a session tenant context is set **and** the inserted `organization_id` is non-NULL **and** differs from it. A NULL `organization_id`, or an insert with no tenant context, passes. It fires on INSERT only; it does not fire on the relay's function-mediated UPDATEs.

### 8.5 Functions

| Function (line) | Signature | Returns | Grants | Behaviour (from the SQL body) |
|---|---|---|---|---|
| `audit.fn_claim_outbox_events` (L141) | `(p_worker_id TEXT, p_limit INTEGER DEFAULT 50, p_claim_timeout_seconds INTEGER DEFAULT 300)` | `SETOF audit.domain_event_outbox` (all columns, `RETURNING *`) | `app_worker`, `app_platform_admin` | `UPDATE ... SET status='CLAIMED', claimed_by=p_worker_id, claimed_at=NOW(), attempt_count=attempt_count+1, last_attempt_at=NOW() WHERE id IN (SELECT id ... WHERE (status='PENDING' AND available_at <= NOW()) OR (status='CLAIMED' AND claimed_at < NOW() - make_interval(secs => p_claim_timeout_seconds)) ORDER BY available_at ASC, id ASC LIMIT p_limit FOR UPDATE SKIP LOCKED) RETURNING *` |
| `audit.fn_mark_outbox_published` (L173) | `(p_id UUID, p_worker_id TEXT)` | `BOOLEAN` (`true` iff one row updated) | `app_worker`, `app_platform_admin` | CAS: `UPDATE ... SET status='PUBLISHED', published_at=NOW(), claimed_by=NULL, claimed_at=NULL WHERE id=p_id AND claimed_by=p_worker_id AND status='CLAIMED'` |
| `audit.fn_mark_outbox_failed` (L195) | `(p_id UUID, p_worker_id TEXT, p_error TEXT DEFAULT NULL, p_next_attempt_at TIMESTAMPTZ DEFAULT NULL)` | `TEXT`: `NULL` (not this worker's claim / already terminal), `'PENDING'` or `'FAILED'` | `app_worker`, `app_platform_admin` | `SELECT attempt_count, max_attempts ... WHERE id=p_id AND claimed_by=p_worker_id AND status='CLAIMED' FOR UPDATE`; not found → `NULL`. If `attempt_count >= max_attempts` → `FAILED`, else `PENDING`. Sets `last_error = LEFT(COALESCE(p_error,''),2000)`, clears `claimed_by` / `claimed_at`; for `PENDING` sets `available_at = COALESCE(p_next_attempt_at, NOW() + INTERVAL '30 seconds')`; for `FAILED` leaves `available_at` unchanged |
| `audit.fn_outbox_tenant_check` (L104) | trigger function | `TRIGGER` | none (REVOKE ALL FROM PUBLIC) | §8.4 |

All four are `SECURITY DEFINER` with an explicit `search_path`.

### 8.6 Cleanup (077 L227–L239)

Documented, **not scheduled** (no `pg_cron` exists anywhere in the schema):

```sql
DELETE FROM audit.domain_event_outbox WHERE status = 'PUBLISHED' AND published_at    < NOW() - INTERVAL '7 days';
DELETE FROM audit.domain_event_outbox WHERE status = 'FAILED'    AND last_attempt_at < NOW() - INTERVAL '30 days';
```

### 8.7 Later migrations that reference the outbox (`078` … `112`)

| Migration | Reference | Effect on relay behaviour |
|---|---|---|
| `093_5D2.sql` L119 | Comment: SECURITY DEFINER functions with owner BYPASSRLS, "the outbox claim functions already operate under" this | None |
| `094_5D3.sql` L44–L89 | Comment: `crm.event_consumer_dedup` is the consumer-side ledger, "separate from" the publisher-side outbox | None; confirms producer/consumer separation |
| `101_5I1.sql` L741 | Comment: cites the outbox retention note as the "documented cleanup query for an external process" precedent | None |
| `102_5H2.sql` L898–L904, L1731 | Comments: no-RLS precedent; the calling application service writes the outbox row in the same transaction | None |
| `109_5B7.sql` L1073–L1168 | `identity.fn_platform_revoke_all_sessions` inserts one outbox row (`identity.forced_revocation_required`, `organization_id = NULL`) inside its own transaction when ≥ 1 session is revoked | A second producer shape (in-function insert); the relay treats it like every row |
| `110_5C2.sql` L89–L92 | Comment: audit and outbox rows remain API-issued in the same transaction | None |

No migration `078` … `112` alters the outbox table, its indexes, its grants, its trigger or any of the three relay functions.

### 8.8 Physical consequences the design must respect (PHY-*)

| ID | Physical fact | Consequence bound by 7D |
|---|---|---|
| PHY-01 | `attempt_count` is incremented by **every claim**, including the reclaim of an expired claim; `fn_mark_outbox_failed` decides terminal `FAILED` from that claim count, not from a count of real failures | An infrastructure outage or a crash can inflate `attempt_count` without any row-specific failure. §24 and §25 guarantee that no infrastructure-class or ambiguous outcome ever calls `fn_mark_outbox_failed` when it could return `FAILED` (DSP-03) |
| PHY-02 | The claim predicate for expired `CLAIMED` rows has no `attempt_count` bound, and `attempt_count` has no upper CHECK | A row is never stranded by the claim path; reclaim can continue indefinitely. `FAILED` is reached only through `fn_mark_outbox_failed` |
| PHY-03 | There is **no** claim-renewal / lease-extension function | The relay bounds all work for a claimed batch by a conservative local deadline (§17); 7D invents no renewal SQL |
| PHY-04 | The lease duration is **not stored on the row**. Each claimer evaluates `claimed_at < NOW() - p_claim_timeout_seconds` with **its own** parameter | All relay claim loops in one deployment MUST pass the same `p_claim_timeout_seconds` (LSE-05) |
| PHY-05 | `claimed_at = NOW()` is the claim transaction's start time (database clock) | Lease expiry is judged by the database clock. The relay's local deadline starts before its claim transaction begins, so it is conservative (LSE-03) |
| PHY-06 | `fn_claim_outbox_events` returns full rows | The relay projects only the columns it needs from the function's result set (CLM-06); it never reimplements the claim |
| PHY-07 | `fn_mark_outbox_failed` with `p_next_attempt_at = NULL` uses the database time `NOW() + 30 s` | 7D passes `NULL` (no invented backoff); final retry timing is 7G's |
| PHY-08 | `fn_mark_outbox_published` and `fn_mark_outbox_failed` are CAS-guarded on `claimed_by` and `status = 'CLAIMED'` | A late or stale claimant cannot corrupt a newer claim; a CAS miss is an observable no-op |
| PHY-09 | `DELETE` is granted only to `app_platform_admin`, annotated "manual/emergency intervention only"; `app_worker` has no `DELETE` | The relay role cannot clean up; cleanup is a separate operator-invoked responsibility (§31) |
| PHY-10 | The outbox emits no `NOTIFY` and has no trigger other than the INSERT tenant check | Discovery of work is by polling the claim function only (§18) |
| PHY-11 | The claim branch for `PENDING` uses `idx_outbox_claim`; the reclaim branch uses `idx_outbox_claimed_stuck` | Scan cost under large backlogs is a 7K capacity concern; 7D adds no index |
| PHY-12 | `FAILED` cleanup is keyed on `last_attempt_at` (set by the last claim); `PUBLISHED` cleanup on `published_at` | Cleanup never selects `PENDING` or `CLAIMED` rows (CLN-02) |

---

## 9. The Single Outbox

| ID | Rule |
|---|---|
| SGL-01 | `audit.domain_event_outbox` is the only transactional domain-event outbox (OUT-01, ADR-7A-01). No `billing_outbox`, `voice_outbox`, `workflow_outbox`, `campaign_outbox`, `notification_outbox` or any equivalent per-context, per-region or per-class table is introduced. |
| SGL-02 | Classes A, B and C all write the same outbox. Class-C workers write their state change and their outbox row in their **own** short PostgreSQL transaction (OUT-03). |
| SGL-03 | No producer of a Class A, B or C event publishes that event directly to Redis or to any other transport (OUT-03; 7B Rule E-2). Only the relay publishes durable events. |
| SGL-04 | The outbox is not partitioned and carries no RLS (OUT-07). 7D does not change either. |
| SGL-05 | The outbox is not a task queue, an audit feed or a signal buffer. No Class-D signal, Celery command or audit intent is ever written to it (CEL-02, AUD-05, RS-05). |

---

## 10. Producer Transaction Contract

### 10.1 Canonical producing transaction (Classes A, B, C)

```text
BEGIN                                              -- one short PostgreSQL transaction
  1. establish trusted tenant context               -- organization from auth context / owning row (TEN-02, DET-04)
  2. validate authorization and business invariants -- owner rules; 7C producer validation PV-C01 … PV-C13
  3. mutate authoritative domain state              -- owner tables / guarded functions (CAS, state guards)
  4. write mandatory audit                          -- audit.fn_insert_audit_event(...) in THIS transaction
                                                    --   (sync classes; and, by OD-7D-02, every mandatory audit — §36)
  5. insert exactly one outbox row for the fact     -- INSERT INTO audit.domain_event_outbox
                                                    --   event_version and occurred_at written explicitly (DET-05, DET-06)
COMMIT
-- only after COMMIT: post-commit work (Celery enqueue, provider dispatch, Class-D signal publish, email)
```

### 10.2 Rules

| ID | Rule |
|---|---|
| PTX-01 | State change, mandatory audit and outbox row commit in the **same** transaction or none of them commits (DUR-01, PR-02). |
| PTX-02 | Inside the producing transaction there is **no** Redis call, Celery broker call, HTTP request, object-storage request, telephony provider call, email request, webhook call, secret-manager call or any other external API request (DUR-04, 6A §35, PR-06). |
| PTX-03 | No publish-before-commit (DUR-02). No "commit state, then try to insert the outbox row" (a second transaction for the outbox row is non-conformant). |
| PTX-04 | Redis availability never gates the commit (DUR-03). A producer never checks transport health before committing. |
| PTX-05 | Where a flow needs external I/O, it uses sequential short transactions with the I/O between them (TX-01, AIR §12.2 TX-NET), and the outbox row is written in the transaction that commits the fact. |
| PTX-06 | A guarded `SECURITY DEFINER` function may write the outbox row inside its own transaction (`109_5B7.sql` precedent). That is the same producing transaction. |
| PTX-07 | A producer never writes relay bookkeeping (`status`, `attempt_count`, `max_attempts`, `available_at`, claim fields, `published_at`, `last_error`); the column defaults apply. Status transitions happen only through the three relay functions (OUT-02). |
| PTX-08 | Post-commit work that is mandatory (§33) is never made durable by the enqueue itself; its recoverability comes from the durable state committed in steps 3–5 (CEL-08 … CEL-10). |

---

## 11. One Fact → One Outbox Row (Producer Idempotency)

| ID | Rule |
|---|---|
| IDP-01 | One committed business fact produces exactly one outbox row and therefore one `event_id` (OUT-04, EVT-02). |
| IDP-02 | The outbox itself does **not** guarantee producer idempotency. `id` is generated per insert; two inserts produce two events. Producer idempotency comes from the owning domain. |
| IDP-03 | The owning domain prevents duplicate production with one of: the HTTP `Idempotency-Key` contract (6A §16.2); a job or work-row identity; a state-machine CAS guard (only the transaction that performs the transition writes the row, 7B IDN-08); a unique constraint; a finalization guard (EV-079, IDN-11 / IO-7B-16); or an equivalent owner mechanism. |
| IDP-04 | HTTP retries, worker retries, reconciliation re-dispatch (§35) and replay never create a second logical fact. A reconciler re-dispatches **work**; the work's own guarded transition decides whether a fact is produced. |
| IDP-05 | **Producer idempotency ≠ consumer idempotency.** Producer idempotency stops a second logical fact being committed. Consumer idempotency (7F; IDM-02, IDN-06) makes redelivery of the same `event_id` harmless. The relay produces duplicates of the same `event_id` by design (§26); it never produces a new `event_id` for an existing fact. |
| IDP-06 | Consumer-side dedup ledgers (`crm.event_consumer_dedup`, `094_5D3.sql`; analytics, billing and callback ledgers) are separate from the publisher-side outbox and are 7F's. 7D creates no inbox. |

---

## 12. Durable Event Counts and the Non-Interpreting Relay

| ID | Rule |
|---|---|
| MAN-01 | 7D preserves **105** semantic durable EV bindings (EV-001 … EV-105; A = 71, B = 1, C = 33), **107** exact durable V1 manifest pairs, **4** exact SIGNAL V1 pairs, **111** exact V1 pairs in total and **0** V2 pairs (7C §20.8, CSR-02, VRS-07). |
| MAN-02 | EV-014 is one semantic binding with exactly three runtime `event_type` values: `tool_definition.created`, `tool_definition.updated`, `tool_definition.deactivated` (OD-7C-07, TDF-01 … TDF-04). |
| MAN-03 | The relay never synthesizes, rewrites, normalizes or suffixes an `event_type`; it publishes the committed value. It therefore never emits the family identifier `tool_definition.*` or any other pattern string on its own account. |
| MAN-04 | The relay performs no wildcard, regex, prefix or family dispatch (CSR-09). Routing is by exact `event_type` through the 7E route function (TPT-05). A 7E route function has no family, wildcard, regex or prefix key and resolves none; a committed row whose `event_type` has no route (for example a non-conformant literal `tool_definition.*`, which producer validation PV-C02 must already have rejected) receives the non-terminal `RELAY_CAPABILITY` outcome (§22) and is never published or dropped. |
| MAN-05 | **The relay is not a domain schema interpreter.** It does not read the manifest to decide whether a row is publishable, does not validate payloads, does not check enum values, does not compare `event_version` to any "latest" version, and does not upcast (PV-07, UPC-10, DET-09). Producer validation (IO-7C-04) owns conformance. |
| MAN-06 | The structural information the relay needs is only what the physical row already guarantees (§8.1 NOT NULL columns and CHECKs) plus a route. Nothing in the relay depends on domain payload semantics. |

---

## 13. Relay Execution Model and Topology (OD-7D-01 = A)

### 13.1 Decision applied

The relay is a **dedicated runtime role** of the modular monolith (OD-7D-01 = A, §45.1): the same repository and the same deployable image, started through its own entrypoint, run as its own workload of one or more stateless replicas. It is an execution role, **not** a microservice and **not** a bounded context (OWN-03; 6D L136; 6J L58). The outbox table, the relay functions and the event contracts are unchanged.

### 13.2 Rules

| ID | Rule |
|---|---|
| TOP-01 | The relay runs as its own process role with its own entrypoint, in the monolith's codebase and image. It shares domain-free platform libraries (database access, transport adapter, telemetry) and imports no bounded-context domain logic. |
| TOP-02 | One or more stateless replicas. PostgreSQL outbox state is the only correctness state (SOT-01; §22.4 of 7A). A replica holds no durable local state; losing any replica loses no event. |
| TOP-03 | Correctness rests only on `fn_claim_outbox_events` (`FOR UPDATE SKIP LOCKED`), the claim lease, and the CAS mark functions. There is **no leader election**, **no Redis distributed lock**, **no etcd / ZooKeeper**, **no leader-election database row** and **no singleton requirement** (§16.4). |
| TOP-04 | Relay correctness and cadence do not depend on Celery or Celery Beat. The relay's loop is a continuous in-process loop, not a scheduled task. |
| TOP-05 | The relay is not hosted in API request-serving processes and is not coupled to API pod scaling. |
| TOP-06 | `voice_gateway` and every voice media-path process **MUST NOT** host the relay (VOX-02, VOX-03). |
| TOP-07 | The relay connects to PostgreSQL as `app_worker` (the role that holds `EXECUTE` on the three relay functions and `SELECT` on the table, §8.3). It needs no `INSERT`, `UPDATE` or `DELETE`, sets no tenant context and bypasses nothing (the functions are `SECURITY DEFINER`). |
| TOP-08 | The relay exposes no public or internal API route. It is not reachable from `/api/v1/*` or `/api/internal/v1/*` (077 L134). |
| TOP-09 | The relay handles `SIGTERM` by the graceful-shutdown contract (§28). |
| TOP-10 | Replica count, CPU and memory sizing, placement and autoscaling are 7K's (DD-08, DD-20). Deployment manifests are an implementation obligation (IO-7D-01), not a 7D artifact. |

### 13.3 Ownership boundaries

| Component | Owns | Does not own |
|---|---|---|
| Producing domain (request handler, guarded function, worker) | The fact, its payload, producer validation, the producing transaction, producer idempotency | Publication, transport, retry of publication |
| Outbox (`audit.domain_event_outbox`) | The durable publication obligation (SOT) | Business state; consumer progress |
| Relay (this document) | Claiming, materialization, handing envelopes to the transport port, per-row outcome recording, availability gating | Event meaning, schema validation, stream topology, consumer processing, retry timing policy beyond the executed function default |
| Transport adapter (7E implementation of the 7D port) | Route resolution, stream entry layout, the Redis commands, per-entry acknowledgement classification | Publication obligation; outbox state |
| Consumers (7F) | Idempotent processing, dedup, ordering tolerance | Relay behaviour |
| Cleanup (§31) | Deleting rows that are past their documented windows | Publication |
| Mandatory-work reconcilers (§33 – §35) | Re-dispatching owner work from durable owner state | The outbox |

---

## 14. Relay Instance Identity

| ID | Rule |
|---|---|
| RID-01 | Each **claim loop** has one relay identity string, passed as `p_worker_id` to `fn_claim_outbox_events` and to both mark functions (the physical `claimed_by`). A process that runs several claim loops gives each loop its own identity. |
| RID-02 | The identity contains a random component of at least 122 bits (a UUIDv4) generated when the claim loop starts. It is therefore unique across concurrent replicas and is never reused after a restart. |
| RID-03 | The identity is stable for the claim loop's lifetime. |
| RID-04 | Form: `relay/<runtime-role>/<region-tag>/<uuid-v4>` — a fixed role label, the deployment's region tag (§39), and the random component. It contains no tenant-provided value, no payload value, no business identifier, no credential and no host secret. It is safe to log. |
| RID-05 | The identity is never used as, derived from or copied into `event_id`, `correlation_id`, `causation_id`, a Redis stream entry ID, a Celery task ID or any envelope field (KEY-02; 7C ID-03). |
| RID-06 | A relay identity never issues a new claim while it still holds unresolved rows from its previous claim whose local deadline has not passed (§19 step ordering). This makes self-reclaim of a row whose outcome is still pending impossible, so the `attempt_count` snapshot a loop holds for its own claimed rows is current (DSP-03). |
| RID-07 | No schema change is needed: `claimed_by` is `TEXT` with no length CHECK (§8.1). |

---

## 15. Outbox Row Lifecycle

```text
                 producer INSERT (committed)
                           │
                           ▼
                      ┌─────────┐   fn_claim_outbox_events           ┌─────────┐
          ┌──────────►│ PENDING │───(available_at <= NOW())─────────►│ CLAIMED │
          │           └─────────┘   attempt_count += 1               └────┬────┘
          │                ▲                                               │
          │                │  fn_mark_outbox_failed → 'PENDING'            │ claim expires
          │                │  (attempt_count < max_attempts;               │ (claimed_at < NOW() − lease)
          │                │   available_at = p_next_attempt_at            │ → re-claimable by any loop
          │                │   or NOW()+30 s)                              │   (attempt_count += 1)
          │                └───────────────────────────────────────────────┤
          │                                                                │
          │     fn_mark_outbox_published (CAS)                             │
          │  ┌─────────────┐◄─────────────────────────────────────────────┤
          │  │  PUBLISHED  │   terminal; cleanup after 7 days (published_at)│
          │  └─────────────┘                                               │
          │                     fn_mark_outbox_failed → 'FAILED'           │
          │  ┌─────────────┐◄─────────────────────────────────────────────┘
          │  │   FAILED    │   terminal publisher-side state (attempt_count >= max_attempts);
          │  └─────────────┘   visible; 7G disposition; cleanup rule CLN-04
          │
          └── (no function moves FAILED or PUBLISHED back; only 7G-governed operator action could)
```

| ID | Rule |
|---|---|
| LIF-01 | `PENDING` → `CLAIMED` only through `fn_claim_outbox_events`. |
| LIF-02 | `CLAIMED` → `PUBLISHED` only through `fn_mark_outbox_published` after a CONFIRMED transport outcome (DSP-01). |
| LIF-03 | `CLAIMED` → `PENDING` or `FAILED` only through `fn_mark_outbox_failed`, under the disposition rules of §24. |
| LIF-04 | `CLAIMED` (expired) → `CLAIMED` (new claimant) only through `fn_claim_outbox_events`. |
| LIF-05 | `PUBLISHED` and `FAILED` are terminal for the relay. The relay never claims them (the claim predicate cannot select them) and never writes to them. |
| LIF-06 | The relay never issues a raw `SELECT … FOR UPDATE`, `UPDATE` or `DELETE` against the outbox. It never writes a "release all claims" statement. |
| LIF-07 | Envelope columns (`id`, `event_type`, `event_version`, `organization_id`, `aggregate_type`, `aggregate_id`, `payload`, `occurred_at`) are never written after the producing insert (REL-08, DET-09, BR-01). |

---

## 16. Claiming

### 16.1 Eligibility (bound to `077` L154–L155)

A row is eligible exactly when:

```text
(status = 'PENDING' AND available_at <= NOW())
OR
(status = 'CLAIMED' AND claimed_at < NOW() - make_interval(secs => p_claim_timeout_seconds))
```

evaluated by the database with the database clock. `PUBLISHED` and `FAILED` rows are never eligible. Rows are selected in `ORDER BY available_at ASC, id ASC`, at most `p_limit`, with `FOR UPDATE SKIP LOCKED`.

### 16.2 Claim transaction

| ID | Rule |
|---|---|
| CLM-01 | The relay claims only by calling `audit.fn_claim_outbox_events(p_worker_id, p_limit, p_claim_timeout_seconds)`. It never reproduces the claim predicate in application SQL (REL-02, OUT-02). |
| CLM-02 | The claim runs in its own short, database-only transaction: begin, call the function, read the returned rows, commit. No other statement, no Redis call and no other external I/O occurs in it. |
| CLM-03 | The claim transaction commits **before** any transport publication. No row lock is held during Redis I/O (REL-03). |
| CLM-04 | The relay passes `p_limit` and `p_claim_timeout_seconds` explicitly on every call, from its configuration (§18). It never relies on the function defaults implicitly, so the value it uses for its local deadline is exactly the value the database used. |
| CLM-05 | The claim performs no per-event domain read. The relay reads nothing outside the outbox. |
| CLM-06 | The relay projects only the columns it needs from the function's result set: the eight envelope columns, `attempt_count`, `max_attempts` and `claimed_at` (for local accounting). It reads `payload` as text (MAT-08). Projection from a set-returning function is not a reimplementation of the claim. |
| CLM-07 | If the claim transaction fails (connection error, timeout, serialization error), the relay assumes nothing was claimed by it that it can act on, backs off (§18, POL-06) and retries. Any row the failed transaction did claim and commit is recovered by lease expiry (§17). |

### 16.3 Concurrency

`FOR UPDATE SKIP LOCKED` inside the function makes concurrent claims by different loops disjoint: a row locked by one claimer's in-flight claim transaction is skipped by the others. Once a claim commits, the row is `CLAIMED` and is not eligible again until its lease expires. The CAS mark functions then ensure only the current claimant can complete it.

### 16.4 No leader election

A leader, mutex or singleton adds no correctness the physical functions do not already provide: disjoint claiming (SKIP LOCKED), bounded ownership (lease), and exclusive completion (CAS on `claimed_by`). A leader would add a single point of liveness failure. 7D therefore uses none (TOP-03, ADR-7D-05). A distributed lock in Redis would additionally make publication correctness depend on the transport being healthy, which REL-07 forbids.

---

## 17. Claim Lease

| ID | Rule |
|---|---|
| LSE-01 | A claim expires when `claimed_at < NOW() - p_claim_timeout_seconds` as evaluated by the database inside a later claim call (PHY-04, PHY-05). Expiry is not an event; an expired claim is simply re-selectable. |
| LSE-02 | No claim-renewal or lease-extension function exists (PHY-03). 7D invents none. |
| LSE-03 | **Local deadline.** Each claim loop starts a monotonic timer immediately before it begins the claim transaction. Its local deadline for that batch is `lease − safety_margin`, where `lease` is the `p_claim_timeout_seconds` it passed and `safety_margin` is a configured value (7J / 7K tune it). Because the timer starts before the transaction whose start time becomes `claimed_at`, the local deadline is conservative relative to the database clock. The local deadline never extends the database lease; it only stops the relay from acting late. |
| LSE-04 | After the local deadline passes, the loop does not start a new publication for any row of that batch and does not call `fn_mark_outbox_failed` for any row of that batch (§24 DSP-06). It **may** still call `fn_mark_outbox_published` for a row whose transport outcome was CONFIRMED before or after the deadline: the CAS either succeeds (the claim is still its own) or is a no-op. |
| LSE-05 | Every claim loop of one relay deployment passes the **same** `p_claim_timeout_seconds`. During a configuration change of the lease, each loop's local deadline uses the smaller of the old and new values until every loop runs the new value. A loop with a shorter lease than another would reclaim that loop's rows early and cause duplicate publication (not loss). |
| LSE-06 | The configured lease must exceed the relay's bounded per-batch work time (transport publish timeout plus mark time) with margin. The transport adapter enforces a publish timeout shorter than the local deadline (TPT-07). |
| LSE-07 | **Process death after claim.** The rows stay `CLAIMED` until the lease expires, then any loop reclaims them. Nothing is lost. If the dead process had already published some of them, they are published again with the same `event_id` (duplicate, allowed). |
| LSE-08 | **Work exceeding the lease.** A slow publish or a paused process can outlive the lease. Another loop may then reclaim and publish the same rows. The late loop's `fn_mark_outbox_published` / `fn_mark_outbox_failed` CAS calls return `false` / `NULL` and change nothing. The outcome is at most a duplicate delivery. |
| LSE-09 | **Why duplicates are acceptable and loss is not.** Durable delivery is at-least-once (DUR-06, DEL-01) and consumers are idempotent on `event_id` (IDM-02). A lost committed fact violates DUR-05 and REL-06. Every lease rule above therefore resolves doubt toward republication. |

---

## 18. Polling, Batch and Lease Values (DD-09)

| ID | Item | V1 baseline | Basis |
|---|---|---|---|
| POL-01 | Claim batch size (`p_limit`) | **50** — the executed Phase-5 default, preserved as the V1 initial baseline | `077` L143; F-09 (7A) |
| POL-02 | Claim lease (`p_claim_timeout_seconds`) | **300 s** — the executed Phase-5 default, preserved as the V1 initial baseline | `077` L144; F-09 |
| POL-03 | Retry backoff on `fn_mark_outbox_failed` | Database default `NOW() + 30 s` by passing `p_next_attempt_at = NULL` | `077` L218; final policy is 7G's (DD-10) |
| POL-04 | `max_attempts` | Per-row column default **10** (CHECK 1 … 20); the relay never changes it | `077` L63, L74 |
| POL-05 | Work-available cadence | **Immediate continuation:** when a claim returns at least one row, the loop claims again as soon as that batch's dispositions are recorded, with no idle wait | 7D architecture rule; no number needed |
| POL-06 | Idle cadence | When a claim returns zero rows, the loop waits a **bounded, configurable idle delay with random jitter** before the next claim. The delay may grow by bounded backoff across consecutive empty claims and resets on the first non-empty claim. The numeric values are configuration; they are benchmarked and set with 7J (latency SLO) and 7K (capacity) before production (IO-7D-09). 7D hardcodes no millisecond value. | PR-10 (standards now, numbers later); no frozen source gives an idle interval |
| POL-07 | Changing POL-01 / POL-02 | Allowed only with benchmark or production evidence recorded by 7K; LSE-05 governs a lease change | 7A §38 DD-09; F-09 |

DD-09 is **CLOSED** for 7D: the batch size and lease keep their source-backed Phase-5 defaults as V1 baseline, and the polling cadence is an adaptive architecture rule whose numeric tuning is explicitly routed to 7J / 7K without affecting correctness.

Publish batching is separate from claim batching (§22.1).

---

## 19. Canonical Relay Loop

### 19.1 Pseudocode (normative order; names are illustrative, not code)

```text
relay_identity := "relay/<role>/<region>/<uuid-v4>"        -- RID-01..RID-04, per claim loop
gate := CLOSED                                              -- transport availability gate (§25)

while not shutdown_requested:                               -- §28

    if gate == OPEN:
        wait(probe_backoff_with_jitter)                     -- no claim while OPEN (GATE-03)
        if transport.health_probe() == HEALTHY:             -- non-claiming probe (GATE-04)
            gate := CLOSED
        continue

    t0 := monotonic_now()                                   -- LSE-03
    deadline := t0 + lease_seconds - safety_margin

    BEGIN                                                   -- short, DB-only (CLM-02)
        rows := SELECT <projected columns>
                FROM audit.fn_claim_outbox_events(relay_identity, batch_size, lease_seconds)
    COMMIT                                                  -- before any Redis I/O (CLM-03)
      on DB error: backoff(db_backoff_with_jitter); continue   -- CLM-07

    if rows is empty:
        idle_wait_with_jitter(); continue                   -- POL-06

    entries := []
    for row in rows:
        env := materialize(row)                             -- §20; never validates payload
        if env is RELAY_CAPABILITY_FAILURE:                 -- defect in this relay build, not the row
            outcome[row] := RELAY_CAPABILITY; continue
        route := transport.route_for(env)                   -- 7E exact-type route (TPT-05)
        if route is NONE:
            outcome[row] := RELAY_CAPABILITY; continue      -- never dropped, never FAILED
        entries.append(row, env, route)

    if monotonic_now() < deadline:
        results := transport.publish(entries, timeout < deadline - now)   -- OUTSIDE any DB txn
    else:
        results := NOT_ATTEMPTED for every entry            -- LSE-04

    for entry in entries: outcome[entry.row] := classify(results[entry])   -- §22

    if any outcome is TRANSPORT_UNAVAILABLE or UNKNOWN-due-to-connection:
        gate := OPEN                                        -- GATE-02

    BEGIN                                                   -- short, DB-only progress transaction(s)
        for row with outcome CONFIRMED:
            ok := fn_mark_outbox_published(row.id, relay_identity)        -- DSP-01
            if not ok: observe(MARK_PUBLISHED_CAS_MISS)                   -- DSP-02
        if monotonic_now() < deadline:
            for row with outcome ROW_REJECTED:
                fn_mark_outbox_failed(row.id, relay_identity, safe_code, NULL)   -- DSP-04
            for row with outcome in {TRANSPORT_UNAVAILABLE, NOT_ATTEMPTED, UNKNOWN, RELAY_CAPABILITY}:
                if row.attempt_count < row.max_attempts:
                    fn_mark_outbox_failed(row.id, relay_identity, safe_code, NULL) -- DSP-03 → 'PENDING'
                -- else: no call; the lease expires (never terminal)           -- DSP-03
    COMMIT
      on DB error: observe(MARK_TX_FAILED); rows stay CLAIMED → lease recovery (DSP-07)

    -- next iteration claims immediately (POL-05); RID-06 holds because this batch is resolved or abandoned
```

### 19.2 Loop invariants

| ID | Invariant |
|---|---|
| LOOP-01 | No PostgreSQL transaction is open while the transport is called (REL-03, PR-06). |
| LOOP-02 | The claim transaction commits before publication; the progress transaction starts after publication returns. |
| LOOP-03 | No Redis `MULTI` / `EXEC`, Lua script or pipeline is used to make PostgreSQL state atomic with Redis state. There is no 2PC and no distributed transaction (TX-02). |
| LOOP-04 | Every claimed row ends the iteration in exactly one of: marked `PUBLISHED`, released to `PENDING`, moved to `FAILED` by a ROW_REJECTED outcome, or left `CLAIMED` for lease expiry. None is dropped. |
| LOOP-05 | A loop holds at most one claimed batch at a time (RID-06). |

---

## 20. Envelope Materialization and Serialization

### 20.1 Mapping (7C §10.2, DET-01)

| Envelope key | Source | Rule |
|---|---|---|
| `event_id` | `id` | The only rename (DET-01). Lowercase hyphenated UUID text (7C §18). Never regenerated. |
| `event_type` | `event_type` | Committed value, byte-for-byte. Never renamed, normalized, suffixed or pattern-expanded. |
| `event_version` | `event_version` | JSON integer literal (VRS-01, VRS-04). Never changed. |
| `organization_id` | `organization_id` | UUID text, or JSON `null` when the column is NULL (EV-001 platform scope). The key is always present. Never derived from payload. |
| `aggregate_type` | `aggregate_type` | Committed value; JSON `null` if the column is NULL. Key always present. |
| `aggregate_id` | `aggregate_id` | UUID text; JSON `null` if NULL. Key always present. |
| `occurred_at` | `occurred_at` | RFC-3339 UTC with `Z` and exactly six fractional digits (OCC-C01), produced by the shared formatter (IO-7C-12). Never re-stamped. |
| `payload` | `payload` | The committed JSON value, carried without semantic change (MAT-08). |
| `correlation_id` | future column (OD-7C-04 / IO-7C-01) | Absent today. After activation: MAT-10. |
| `causation_id` | future column (OD-7C-04 / IO-7C-01) | Absent today. After activation: MAT-10. |

### 20.2 Rules

| ID | Rule |
|---|---|
| MAT-01 | The top-level key set is closed (KEY-01). The relay adds no key: no `durability` (KEY-04), no `attempt_count`, no `status`, no `published_at`, no relay identity, no stream name, no timestamp of its own (KEY-02). |
| MAT-02 | The relay never regenerates `event_id`, never rewrites `event_type` or `event_version`, never changes `organization_id`, never re-stamps `occurred_at` and never edits `payload` (REL-08, DET-09). |
| MAT-03 | The relay never injects tenant fields from payload and never reads tenant identity from payload (PR-07, TEN-02). |
| MAT-04 | Nullable envelope values are emitted as JSON `null`; keys are not stripped (SER-01, SER-02). The relay never "fixes" a NULL `aggregate_type` or `aggregate_id` (both are REQUIRED NON-NULL by 7C, enforced by producer validation, not by the relay). |
| MAT-05 | Timestamps are not rounded or truncated; `TIMESTAMPTZ` stores microseconds, which the six-digit form represents exactly (OCC-C04). |
| MAT-06 | The relay does not recalculate, round, normalize, reorder semantically or re-serialize any business value: no Billing quantity, money, decimal string, enum or identifier is touched (BIL-01 … BIL-03; 7C §18). |
| MAT-07 | The relay does not upcast, downcast or translate versions (UPC-10). A row at any `event_version` is materialized identically. |
| MAT-08 | **Lossless payload.** The relay obtains `payload` as PostgreSQL's text rendering of the committed `JSONB` value (for example by projecting `payload::text` from the claim function's result set) or through a driver path that never decodes JSON numbers into binary floating point. It embeds that JSON value unchanged. It never parses numbers into floats, never drops or adds keys and never pretty-prints into a different value. (`JSONB` itself already canonicalized key order and whitespace at commit time; the committed `JSONB` value is the value the relay preserves.) |
| MAT-09 | The materialized envelope is serialized once to UTF-8 JSON bytes. Those exact bytes are what the transport port carries (TPT-03). |
| MAT-10 | **Correlation / causation (future, contingent on IO-7C-01; rollout DPC-07).** Until the OD-7C-04 columns exist, both keys are absent from every envelope and the relay never invents, derives, back-fills or moves them into payload (CC-02, CC-03, COR-06, CAU-07). Once the columns exist, a column-aware relay build applies, per row: (a) `correlation_id` is present iff its column value is non-NULL, carrying the exact committed value; (b) `causation_id` is present iff its column value is non-NULL (exact committed value), or iff `correlation_id` is non-NULL (then JSON `null`, a genuine root, CAU-R); (c) a row with both columns NULL — every historical row written before producer activation — carries neither key for its whole life (CC-02) and replay never back-fills it (BR-05). The relay **never omits a value that is physically present** (CC-03). A row with `correlation_id` NULL and `causation_id` non-NULL is a producer contract violation (PV-C13): the relay still publishes the present `causation_id` unchanged, omits only the absent `correlation_id`, repairs nothing and reports a contract anomaly; the IO-7C-01 migration owner is asked to make that combination structurally impossible (IO-7D-12). |
| MAT-11 | Materialization never logs the payload (SEC-7D-02). |
| MAT-12 | A materialization failure can only come from a defect in the relay build, because every column it reads is guaranteed by the physical schema. It is classified `RELAY_CAPABILITY` (non-terminal; §22), never `ROW_REJECTED`, so a relay defect can never burn a row to `FAILED`. |

---

## 21. Transport Port Boundary (7E)

7D defines the port; 7E implements it for Redis Streams. 7D chooses no stream name, count, layout, group, shard, partition key, MAXLEN or TTL.

### 21.1 Port contract — `DurableEventTransportPublisher` (logical name)

```text
route_for(envelope_view) -> Route | NONE
    envelope_view exposes read-only: event_type, event_version, organization_id,
    aggregate_type, aggregate_id (derived from the same committed row)

publish(entries: list[(event_id, route, envelope_bytes)], timeout) -> map[event_id -> Outcome]
    Outcome ∈ { CONFIRMED(transport_ref),            -- 7E durable-acceptance criterion met for this entry (TPT-02)
                ROW_REJECTED(category),          -- definite, entry-specific, per 7E classification
                TRANSPORT_UNAVAILABLE(category), -- definite, not accepted, infrastructure-wide
                NOT_ATTEMPTED,                   -- never sent
                UNKNOWN(category) }              -- sent; acceptance not determinable

health_probe() -> HEALTHY | UNHEALTHY            -- non-claiming, carries no event
```

### 21.2 Rules

| ID | Rule |
|---|---|
| TPT-01 | The port returns **one outcome per submitted entry**. There is no batch-level success. |
| TPT-02 | **`CONFIRMED` means durable acceptance.** `CONFIRMED` means that the 7E-defined transport durability / acceptance criterion required by the frozen durable at-least-once contract (DUR-05, DUR-06, DEL-01, REL-07) has been satisfied **for this entry**: once confirmed, the entry survives every fault in 7E's declared transport fault model, including normal primary failover, and is delivered at least once to the consumers of its route. A Redis `XADD` entry ID by itself is **not** declared sufficient by 7D. 7E defines the mechanism that establishes the property (HO-7E-03); 7D chooses no Redis topology, persistence, replication or confirmation technique. If the 7E mechanism cannot establish the property for an entry (for example its durability confirmation fails or times out), the entry is **not** `CONFIRMED`: it is `UNKNOWN` or another non-terminal class per the 7E classifier (TPT-08), and the row is never marked `PUBLISHED` on that attempt. `transport_ref` (for example the stream entry ID) is transport position only; it never replaces `event_id` (7C ID-03) and is not stored in the outbox. |
| TPT-03 | The envelope bytes are carried unchanged. 7E may place them in a stream entry under field names it chooses, and may add transport metadata outside the envelope bytes, but it never alters, splits, re-encodes lossy, or adds keys inside the envelope (KEY-05). |
| TPT-04 | Transport metadata never contains payload content, never overrides `organization_id`, and never carries relay bookkeeping as an interpretable fact (KEY-02). |
| TPT-05 | `route_for` is deterministic, is a function of exact `event_type` (and, if 7E chooses, other read-only envelope attributes), is defined for all 107 exact durable V1 pairs, and has no family, wildcard, regex or prefix key (CSR-09). It resolves no family identifier. `NONE` is a non-terminal outcome for the relay (MAN-04). |
| TPT-06 | A Class-D SIGNAL is never routed to a durable-event route and a durable envelope is never routed to a signal route (RS-05). The two publishers use distinct port instances (§32). |
| TPT-07 | The adapter enforces a publish timeout supplied by the relay that is shorter than the loop's remaining local deadline (LSE-06). |
| TPT-08 | The adapter classifies every transport error into exactly one outcome class. **Any error it does not positively classify as ROW_REJECTED is reported as TRANSPORT_UNAVAILABLE or UNKNOWN** (default-to-non-terminal). 7E provides the classification table (HO-7E-04). Until it does, no outcome is ROW_REJECTED. |
| TPT-09 | The adapter must accept any entry up to the outbox's physical payload bound (262144 bytes of payload plus envelope) without a size rejection (HO-7E-05). |
| TPT-10 | Redis is never the authoritative record of the publication obligation (RS-02, SOT-02). The relay never reads a stream to decide whether a row was published. |
| TPT-11 | The transport endpoint used by a relay deployment is in the same region as the PostgreSQL outbox it drains (§39). |

---

## 22. Publish Batching and Per-Row Outcome Classification

### 22.1 Claim batching ≠ transport batching

| ID | Rule |
|---|---|
| PBT-01 | A claim batch is a unit of claiming only. It is **not** a business unit and **not** an atomic publication unit. |
| PBT-02 | The adapter **may** pipeline the entries of one claim batch (for example several `XADD` commands in one round trip) purely as an efficiency measure. Pipelining implies no all-or-nothing semantics: each entry keeps its own outcome. |
| PBT-03 | The relay never marks a whole batch `PUBLISHED` because some commands succeeded, and never marks a row `PUBLISHED` because a different row succeeded. |
| PBT-04 | No `MULTI` / `EXEC` transaction or script is required or relied on for correctness (LOOP-03). |

### 22.2 Outcome classes

| Class | Meaning | Examples (7E classifies exactly) | Terminal risk |
|---|---|---|---|
| `CONFIRMED` | Per-entry durable acceptance under the 7E criterion (TPT-02) | `XADD` accepted **and** the 7E durability confirmation succeeded for that entry; an entry ID alone is insufficient | — (row becomes `PUBLISHED`) |
| `ROW_REJECTED` | Definite, entry-specific rejection that another attempt of the same entry would also meet, and that is not infrastructure-wide | A 7E-enumerated entry-specific rejection | Consumes the retry budget; may reach `FAILED` |
| `TRANSPORT_UNAVAILABLE` | Definitely not accepted, because the transport is unavailable or misconfigured for everyone | Connection refused, DNS failure, authentication/configuration failure, cluster down, out-of-memory refusal, read-only replica | Never terminal |
| `NOT_ATTEMPTED` | The entry was never sent | Connection failed before this entry; local deadline passed; shutdown | Never terminal |
| `UNKNOWN` | The entry may or may not have been accepted | Timeout after send; connection reset after send; lost reply | Never terminal |
| `RELAY_CAPABILITY` | This relay build cannot handle the row, through no fault of the row's durable content | No route for the `event_type` (new producer / old relay, or a non-conformant row); materialization defect (MAT-12) | Never terminal |

Rule OUTC-01: unclassifiable errors are never `ROW_REJECTED` (TPT-08). Rule OUTC-02: an `UNKNOWN` outcome never becomes `CONFIRMED` and never becomes a permanent drop.

---

## 23. Partial Batch Behaviour

The canonical four-row case:

| Row | Transport result | Classified outcome | Relay action | Resulting row state | Duplicate possible? | Loss possible? |
|---|---|---|---|---|---|---|
| A | `XADD` accepted and the 7E durable-acceptance criterion met for this entry (TPT-02) | `CONFIRMED` | `fn_mark_outbox_published(A, id)` | `PUBLISHED` (if the CAS succeeds); if the CAS misses, stays with the newer claimant | Yes, only if the mark fails or the CAS misses | No |
| B | Redis returned a definite error that 7E classifies entry-specific | `ROW_REJECTED` | `fn_mark_outbox_failed(B, id, safe_code, NULL)` | `PENDING` (+30 s) or, at `attempt_count >= max_attempts`, `FAILED` (7G) | Not from this attempt | No — `FAILED` is visible and retained (CLN-04) |
| C | Command sent, reply lost / timed out | `UNKNOWN` | If `attempt_count < max_attempts`: `fn_mark_outbox_failed(C, id, 'PUBLISH_OUTCOME_UNKNOWN', NULL)` → `PENDING`; else no call (lease expiry) | `PENDING` or `CLAIMED` → re-claimed | Yes (if Redis did accept it) | No |
| D | Not sent because the connection failed before it | `NOT_ATTEMPTED` | Same as C with code `NOT_ATTEMPTED`; the gate opens | `PENDING` or `CLAIMED` → re-claimed after the gate closes | No | No |

| ID | Rule |
|---|---|
| PRB-01 | No row is silently dropped: every row ends in one of the four LOOP-04 states. |
| PRB-02 | No row is marked `PUBLISHED` unless its own outcome is `CONFIRMED`. |
| PRB-03 | Unknown outcomes favour duplicate risk over loss risk. |
| PRB-04 | A connection-level failure affecting part of a batch opens the availability gate (§25), so the remaining claimed rows are not re-tried in a tight loop. |
| PRB-05 | An entry for which `XADD` returned an entry ID but the 7E durability confirmation failed or timed out is `UNKNOWN` (as row C), never `CONFIRMED` (TPT-02). |

---

## 24. Progress Recording: Mark-Published, Mark-Failed and Deferral

| ID | Rule |
|---|---|
| DSP-01 | **CONFIRMED → mark published.** For each `CONFIRMED` row, the relay calls `audit.fn_mark_outbox_published(row.id, relay_identity)`. It uses no other statement to record publication (REL-05, OUT-02). |
| DSP-02 | **Mark-published CAS miss.** If the function returns `false`, the claim is no longer this loop's (it expired and another loop reclaimed it, or an operator intervened). The relay records the anomaly (`MARK_PUBLISHED_CAS_MISS`), does not rewrite the row, and does nothing else. The newer claimant will publish again (duplicate, allowed). |
| DSP-03 | **Deferral (non-terminal).** For `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED`, `UNKNOWN` and `RELAY_CAPABILITY`: if the row's `attempt_count` (as returned by this loop's own claim) is `< max_attempts`, the relay calls `fn_mark_outbox_failed(row.id, relay_identity, safe_code, NULL)`, which — because this loop holds the claim and no other path changes `attempt_count` while it does (RID-06, PHY-08) — deterministically returns `'PENDING'` with `available_at = NOW() + 30 s`. If `attempt_count >= max_attempts`, the relay makes **no** database call for that row and the claim lease expires (§17). Deferral therefore can never produce `FAILED`. The only other physical writer of `attempt_count` is a manual `app_platform_admin` UPDATE (`077` L127, "manual/emergency intervention only"); such intervention is outside this guarantee and is governed by the 7G / 7I operator procedure. |
| DSP-04 | **ROW_REJECTED → budget-respecting failure.** The relay calls `fn_mark_outbox_failed(row.id, relay_identity, safe_code, NULL)`. The function returns `'PENDING'` (retry after the database backoff) or `'FAILED'` (terminal, `attempt_count >= max_attempts`). The relay respects the result and redesigns no retry timing (DD-10 is 7G's). |
| DSP-05 | **Mark-failed CAS miss.** A `NULL` return means the row is no longer this loop's. The relay records the anomaly and does nothing else. |
| DSP-06 | **After the local deadline** (LSE-04) the relay makes no `fn_mark_outbox_failed` call for the batch. Unresolved rows stay `CLAIMED` and are recovered by lease expiry. |
| DSP-07 | **Progress transaction.** Mark calls run in one or more short database-only transactions after publication returns. Grouping several mark calls into one transaction is permitted; if that transaction fails, every row in it stays `CLAIMED` and is recovered by lease expiry (duplicates only). The relay **may** retry a failed progress transaction while the local deadline allows; repeated calls are safe because both functions are CAS-guarded. |
| DSP-08 | `safe_code` passed as `p_error` is a short, non-sensitive category code (for example `TRANSPORT_UNAVAILABLE`, `PUBLISH_OUTCOME_UNKNOWN`, `NOT_ATTEMPTED`, `NO_ROUTE`, `RELAY_DEFECT`, or a 7E row-rejection category). It never contains payload content, Redis error text with data, credentials or tenant data (SEC-7D-03). The function truncates to 2000 characters. |
| DSP-09 | **Publisher retry state ≠ consumer retry state.** `attempt_count`, `available_at`, `last_error` and `FAILED` describe only the relay's attempts to hand the event to the transport. Consumer attempts, pending-entry redelivery, consumer DLQ and parking are 7E / 7F / 7G state and never read or write these columns. |

### 24.1 Why the disposition rules protect the retry budget

`attempt_count` counts claims (PHY-01). If deferral outcomes called `fn_mark_outbox_failed` unconditionally, every row that had been claimed `max_attempts` times across outages or crashes would move to terminal `FAILED` on the next infrastructure hiccup, with no row-specific cause — a **terminal-FAILED storm**. DSP-03 makes that impossible: only a `ROW_REJECTED` outcome, which by TPT-08 requires a positive entry-specific classification, can reach the terminal branch of `fn_mark_outbox_failed`.

**What `max_attempts` does and does not count.** `attempt_count` physically counts claims (PHY-01), not entry-specific failures. A row whose count was inflated by earlier crashes, lease expiries or outage-onset batches can reach terminal `FAILED` on a later `ROW_REJECTED` after fewer than `max_attempts` real entry-specific rejections. `max_attempts` is therefore a bound on claims at the moment a row-specific rejection is recorded, not a pure count of row-specific failures. 7D keeps the safe property — `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED`, `UNKNOWN` and `RELAY_CAPABILITY` never move a row to `FAILED` — and creates no migration. Whether terminal disposition must account for claim inflation is 7G's terminal retry / disposition policy (HO-7G-05). `FAILED` rows are retained until that disposition exists (CLN-04), so the effect is never loss.

---

## 25. Transport Availability Gate (Redis Outage vs Event-Specific Failure)

### 25.1 The distinction

| Global infrastructure failure | Event-specific failure |
|---|---|
| Redis unavailable, DNS failure, connection refused or reset, authentication or transport configuration unavailable, cluster down, memory refusal, read-only failover state | One entry rejected for a reason specific to that entry and classified `ROW_REJECTED` by 7E |
| Outcome class `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED` or `UNKNOWN` | Outcome class `ROW_REJECTED` |
| Opens the gate; rows deferred (DSP-03); **no retry budget consumed toward FAILED** | Row budget consumed through `fn_mark_outbox_failed`; may reach `FAILED` (7G) |

### 25.2 Gate states

```text
   CLOSED ──(batch exchange reports a connection-level TRANSPORT_UNAVAILABLE / UNKNOWN)──► OPEN
     ▲                                                                                     │
     └───────────────(health_probe() == HEALTHY)◄───── probe with bounded backoff + jitter ┘
```

| ID | Rule |
|---|---|
| GATE-01 | Each claim loop keeps its own gate state in memory. The gate is an availability optimization, not a correctness mechanism; correctness never depends on Redis health (REL-07). |
| GATE-02 | The gate opens as soon as a batch exchange reports a connection-level `TRANSPORT_UNAVAILABLE`, a connection-level `UNKNOWN` (timeout or reset of the exchange), or `NOT_ATTEMPTED` caused by a connection failure. One such batch is enough: there is no threshold to tune, because the relay cannot tell a partial outage from a total one. |
| GATE-03 | While the gate is OPEN the loop makes **no claim**. Rows stay `PENDING` (or `CLAIMED` until their lease expires) and their `attempt_count` does not grow. |
| GATE-04 | While OPEN the loop calls the port's non-claiming `health_probe()` with bounded exponential backoff and jitter (values configured with 7J / 7K). The probe carries no event and touches no outbox row. |
| GATE-05 | On a HEALTHY probe the gate closes and the next iteration claims normally. If that batch fails at connection level again, the gate re-opens after at most one batch. |
| GATE-06 | Per outage onset, each claim loop affects at most one in-flight batch: those rows receive one extra `attempt_count` from their claim and are deferred without terminal risk. |
| GATE-07 | During an outage, PostgreSQL keeps accepting business commits and outbox rows (DUR-03, FM-01). The relay never blocks, slows or rolls back a producer. |
| GATE-08 | When Redis recovers, publication resumes from the oldest eligible rows (`ORDER BY available_at, id`). Catch-up rate, fleet-level backpressure and capacity during catch-up are 7K's. |
| GATE-09 | Row-specific rejections do not open the gate. If 7E reports the same `ROW_REJECTED` category for every entry of consecutive batches, that pattern is surfaced for operators (OBS-7D-10) and 7E must re-examine its classification (HO-7E-04); the relay still never escalates a non-row-specific error to `ROW_REJECTED`. |

This section is freeze-critical: it is the mechanism that satisfies REL-07 and FM-01 under the physical claim-count semantics of PHY-01.

---

## 26. Ambiguous Outcomes and Database Failure after Publication

| ID | Case | Required behaviour |
|---|---|---|
| AMB-01 | Redis accepted `XADD` but the reply is lost | Outcome `UNKNOWN` → deferral (DSP-03). The row is published again later with the **same** `event_id`. Duplicate allowed; loss impossible. |
| AMB-02 | Relay crashes immediately after publication, before `fn_mark_outbox_published` | Row stays `CLAIMED`; lease expires; another loop republishes the same `event_id`. |
| AMB-03 | Redis publication `CONFIRMED`, then PostgreSQL unavailable for the mark | The progress transaction fails (DSP-07); the row stays `CLAIMED`; the relay may retry the mark within its deadline; otherwise lease expiry and republication. `event_id` unchanged. |
| AMB-04 | Never | The relay never treats `UNKNOWN` as `CONFIRMED`, never drops an `UNKNOWN` row, never reads Redis to decide whether a row was published, and never claims exactly-once (DEL-04, §20.1 of 7A). |
| AMB-05 | Consumers | Duplicates of the same `event_id` are handled by idempotent consumers (7F; IDM-02, FM-03, FM-04). |

---

## 27. Relay Crash Recovery Matrix

| # | Crash point | PostgreSQL row state after the crash | Possible Redis state | Recovery path | Duplicate possible? | Loss possible? | Next owner |
|---:|---|---|---|---|---|---|---|
| CRS-01 | Before claim | `PENDING` | Nothing | Any loop claims it normally | No | No | — |
| CRS-02 | During the claim transaction (before commit) | `PENDING` (claim rolled back) | Nothing | Claimed again normally | No | No | — |
| CRS-03 | After claim commit, before publication | `CLAIMED` by the dead identity | Nothing | Lease expires (DB clock); reclaimed (`attempt_count` +1) | No | No | — |
| CRS-04 | During publication (some entries sent) | `CLAIMED` | Some entries may exist | Lease expiry → republish all unmarked rows | Yes | No | 7F (dedup) |
| CRS-05 | After Redis accepted, before the ack was observed | `CLAIMED` | Entry exists | Lease expiry → republish | Yes | No | 7F |
| CRS-06 | After the ack, before mark-published | `CLAIMED` | Entry exists | Lease expiry → republish | Yes | No | 7F |
| CRS-07 | During the mark-published transaction | `CLAIMED` (transaction rolled back) or `PUBLISHED` (committed) | Entry exists | If `CLAIMED`: lease expiry → republish; if `PUBLISHED`: done | Yes (first case) | No | 7F |
| CRS-08 | After mark-published commit | `PUBLISHED` | Entry exists | None needed | No | No | — |
| CRS-09 | While handling a failure (during `fn_mark_outbox_failed`) | `CLAIMED` (rolled back) or `PENDING` / `FAILED` (committed) | Maybe (for `UNKNOWN`) | `CLAIMED` → lease expiry; `PENDING` → normal claim; `FAILED` → 7G disposition | Yes (`UNKNOWN`) | No | 7G for `FAILED` |
| CRS-10 | During graceful shutdown | Resolved rows as recorded; unresolved rows `CLAIMED` | Maybe | Lease expiry for unresolved rows (§28) | Yes | No | — |

Invariant CRS-INV: at every crash point the PostgreSQL row is `PENDING`, `CLAIMED`, `PUBLISHED` or `FAILED`; a `CLAIMED` row always becomes eligible again by lease expiry; therefore no committed row is ever lost (DUR-05, REL-06).

---

## 28. Graceful Shutdown

| ID | Rule |
|---|---|
| SHD-01 | On `SIGTERM` (or the platform's stop signal) the loop stops claiming new batches immediately. |
| SHD-02 | It lets the in-flight transport exchange for the current batch complete, bounded by the smaller of the remaining shutdown grace period and the batch's local deadline. |
| SHD-03 | It records known outcomes: `fn_mark_outbox_published` for `CONFIRMED` rows; the §24 dispositions for the rest while the deadline allows. |
| SHD-04 | Rows it cannot resolve stay `CLAIMED` and are recovered by the normal claim lease. |
| SHD-05 | There is no "release all claims" statement. The only release path used is `fn_mark_outbox_failed` under DSP-03, which already exists. |
| SHD-06 | A row published but not marked before exit is published again later (duplicate, allowed). No row is lost. |
| SHD-07 | The workload's termination grace period is configured to cover one bounded batch exchange plus the progress transaction (IO-7D-01); the value is 7K's. |
| SHD-08 | Readiness reports not-ready once shutdown starts; liveness does not depend on Redis health (a Redis outage must not restart relay replicas in a loop). |

---

## 29. Horizontal Scaling

| ID | Rule |
|---|---|
| SCL-01 | Any number of relay replicas, each running one or more claim loops with distinct identities, may run concurrently. `SKIP LOCKED` makes their claims disjoint; the lease bounds ownership; CAS makes completion exclusive (§16). |
| SCL-02 | There is no global relay singleton and no global ordering guarantee (ORD-01, ORD-05). Two events of the same aggregate may be published by different loops in either order; consumers tolerate reordering (ORD-04). |
| SCL-03 | Claim order is `available_at, id` across all tenants. A tenant producing a burst can add latency for others but can never affect another tenant's correctness or cause loss. Fairness and per-tenant capacity are 7K's. |
| SCL-04 | Adding or removing replicas needs no coordination, no rebalancing and no configuration change other than LSE-05's uniform lease. |
| SCL-05 | Database connection budgets for relay replicas are part of 7K's connection sizing (3F L1166). |

---

## 30. Deployment Compatibility and Old Backlog

| ID | Rule |
|---|---|
| DPC-01 | There is no simultaneous-deploy assumption (DPL-01). Producers, relays and consumers deploy independently. |
| DPC-02 | The relay is transport-generic. It never drops, fails or rewrites a committed row because its `event_type` or `event_version` is absent from, older than or newer than anything the relay build "knows". It has no "latest manifest" check (MAN-05). |
| DPC-03 | **Old producer → new relay → old consumer.** Backlog committed by the old producer is materialized exactly as committed and published; the old consumer receives what the old producer wrote. |
| DPC-04 | **New producer → old relay → new consumer.** The old relay materializes new rows identically (it copies columns). If a new `event_type` has no route in the old relay's 7E route function, the row is `RELAY_CAPABILITY` (non-terminal) and waits until a relay with the route runs. Nothing is lost or failed. |
| DPC-05 | Committed history is immutable (BR-01). Version compatibility, coexistence and rollout order are 7C's (§34, §35 of 7C); the relay transports every version unchanged. |
| DPC-06 | During a rolling relay deploy, old and new replicas run together safely under SCL-01 as long as LSE-05 holds. |
| DPC-07 | **OD-7C-04 staged relay rollout (CC-03).** Consumer tolerance of missing keys (KEY-07, CC-04) exists for historical rows; it never authorizes a relay to strip values from new rows. **Stage 1** — the governed future Phase-5 migration (IO-7C-01) adds nullable `correlation_id` / `causation_id` columns; existing rows stay NULL. **Stage 2** — deploy column-aware relay builds that read both columns and apply MAT-10: omit the keys only where the columns are NULL, include the exact committed values where present. **Stage 3** — verify that every active relay replica runs a column-aware build (deployment gate, IO-7D-12). **Stage 4** — only then activate producer population / enforcement for newly produced rows. Producer population before Stage 3 completes is prohibited. After Stage 4, a relay build that would omit populated values MUST NOT run: deploying, scaling up or rolling back to such a build is prohibited (compare 7C RD-R05). **Stage 5** — historical pre-activation rows publish without the keys forever; replay never back-fills them (CC-02, BR-05). |

---

## 31. Outbox Cleanup

| ID | Rule |
|---|---|
| CLN-01 | Cleanup is a separate responsibility from publication. The relay role never deletes (it has no `DELETE` grant, PHY-09). |
| CLN-02 | Cleanup deletes only rows selected by the two documented predicates (§8.6): `status = 'PUBLISHED' AND published_at < NOW() - 7 days`; `status = 'FAILED' AND last_attempt_at < NOW() - 30 days`. It **never** deletes `PENDING` rows, `CLAIMED` rows (active or expired) or any otherwise publishable row. |
| CLN-03 | The 7-day and 30-day windows are the frozen Phase-5 documented values (`077` L227–L238; 7B TSK-17). 7D does not change them. |
| CLN-04 | `FAILED` rows are deleted only after the 7G disposition process for publisher-side terminal failures exists and has recorded a disposition for them. Until 7G is frozen, `FAILED` rows are retained. This never shortens the documented window; it only prevents the 30-day predicate from destroying an undispositioned publication obligation (FM-07: never silently dropped). |
| CLN-05 | Cleanup never uses Redis state as a criterion. The presence of a stream entry never makes a row deletable; PostgreSQL status alone decides (RS-02). |
| CLN-06 | Outbox cleanup is **not** business retention, audit retention, Redis stream retention, DLQ retention, replay retention or dedup-ledger retention (OUT-06, §32.3 of 7A). |
| CLN-07 | **Privilege.** Under the executed grants, only `app_platform_admin` can delete, and `077` L127 annotates that grant "manual/emergency intervention only". V1 cleanup is therefore an operator-invoked maintenance operation run under that existing grant, using exactly the documented predicates, batched to bound lock time, and audited by the operator procedure (IO-7D-10). Automating cleanup under a narrower role requires a future governed change owned by the Phase-5 owner and 7K (Minor-7D-01); 7D creates none. |
| CLN-08 | `PUBLISHED` rows retained for 7 days are a **disaster / repair** replay source for transport faults outside 7E's declared fault model (F7D-21). They are never a substitute for the durable-acceptance guarantee of TPT-02. 7G / 7K own that procedure. |

---

## 32. Class-D Direct Signal Publisher Boundary

| ID | Rule |
|---|---|
| CLD-01 | The Class-D publisher is a separate component from the durable relay. It has no outbox row, no claim, no lease, no mark function and no durable retry (DEL-05, RS-05). |
| CLD-02 | Class D is best-effort and non-durable. A process crash after the producing commit may lose the signal; that is the contract (FM-01, SIG-R03). |
| CLD-03 | No Class-D signal is ever inserted into the outbox, to "fix" durability or for any other reason (SGL-05; OD-7B-01 D-1). |
| CLD-04 | A signal is published only after the transaction it reports on has committed (DS-01 … DS-16: the request transaction; DS-17: the per-turn checkpoint transaction; DS-18, DS-19: the runtime transition). |
| CLD-05 | Publication never blocks the producer: it is bounded, non-blocking and fire-and-forget from the producer's point of view. On the voice runtime it never adds waiting to the turn loop (VOX-03). Any in-process re-attempt is bounded, is not a durability promise, and reuses the same signal `event_id` (ID-09). Language such as "retry" in a Class-D implementation never implies durable delivery. |
| CLD-06 | On transport unavailability the signal is dropped and counted (OBS-7D-14); it is never queued to disk, never routed to the outbox and never re-sent after restart. |
| CLD-07 | The four exact SIGNAL V1 pairs — `conversation.turn_completed` (PAY-D-01), `tool_execution.started`, `tool_execution.succeeded`, `tool_execution.failed` (PAY-D-02) — use exactly the 7C SIGNAL envelope (SIG-01 … SIG-11), including `durability = "SIGNAL"`, a producer-generated UUIDv7 `event_id` generated once before the first publish attempt, and the correlation / causation rules SIG-08 / SIG-09. The publisher carries the envelope bytes unchanged (SIG-R04). |
| CLD-08 | Billing does not consume PAY-D-01 or PAY-D-02 (SIG-R06, OD-7B-01). Nothing in the Class-D publisher routes a signal to a Billing consumer, and no signal is ever a Billing source (BIL-07, IDN-04). |
| CLD-09 | The other current Class-D signals (DS-01 … DS-16, DS-18) have no catalogued consumer and no 7C binding (DEF-7C-02). 7D invents no payload or envelope for them. The publisher mechanics above apply once 7B / 7C bind a SIGNAL schema through a governed change; until then 7D places no emission contract on them (Minor-7D-02). |
| CLD-10 | Signals use transport routes distinct from durable-event routes (TPT-06). The Class-D publisher shares no gate state with the durable relay; a Redis outage drops signals by contract and never affects the durable path. |
| CLD-11 | The Class-D publisher never carries audio, PCM, media frames or per-frame events (RS-06, VOX-02). |

---

## 33. Mandatory Post-Commit Work (DD-21) — Architecture

### 33.1 The gap

```text
DB COMMIT ──► process dies (or the Celery broker — Redis, HLA §7.1 — is unavailable) ──► task never reaches a broker
```

Broker retries begin only after a broker holds the task (CEL-10). A one-shot `commit(); celery.delay()` therefore cannot make mandatory work durable. Because the Celery broker is Redis, a Redis outage produces this gap for **every** post-commit enqueue attempted during the outage, not only on a crash.

### 33.2 Rules

| ID | Rule |
|---|---|
| PCW-01 | Post-commit work whose loss would violate a frozen business, security, audit, billing, compliance or lifecycle invariant is **mandatory**. Its correctness never depends solely on a one-shot in-process enqueue after commit (CEL-08). |
| PCW-02 | The recovery source is always durable state committed in the producing transaction: an owner state row, a job / work row, a dispatch-key row, an inbound-receipt row, or a durable outbox event consumed into work (CEL-09). |
| PCW-03 | Recovery is performed by an **owner-domain reconciler**: owner code, running as the owner's worker role (or the owner's narrow role, e.g. `app_voice_reconciler`), triggered by an APScheduler timer (CEL-07) — never a REST hop. Schedules and staleness thresholds are 7K's. |
| PCW-04 | The reconciler selects candidates only with existing columns (status plus an existing timestamp). 7D adds no column, state or table. |
| PCW-05 | The reconciler's action is either (a) re-dispatch of the same owner work, or (b) an owner-defined frozen transition (for example a terminal fallback). It never creates a fact outside the owner's guarded transition and never writes the outbox except through that transition's own transaction. |
| PCW-06 | Re-dispatch is safe under duplication: the owner work is guarded by a CAS transition, a unique constraint or a guarded function (named per flow in §35). Two reconcilers, or a reconciler and a delayed original task, may both dispatch; only one effect commits. |
| PCW-07 | Each re-dispatch establishes tenant context from the durable row's own `organization_id`, never from a payload or a task argument alone (TEN-02). |
| PCW-08 | A staleness threshold affects only the volume of duplicate work, never correctness. |
| PCW-09 | An enqueue failure after commit (crash, broker or Redis outage) never rolls back, and is never reported as failure of, the committed operation. The committed state is the truth; the reconciler completes the work. |
| PCW-10 | Reconcilers are observable (OBS-7D-16): candidates found, re-dispatched, resolved by fallback. |
| PCW-11 | 7D creates **no** generic task-outbox table. Every mandatory flow in §34 has source-backed durable state, or an owner-approved mechanism (OD-7D-02, OD-7D-03) routed through governed obligations. |
| PCW-12 | Reconciler messages are commands, not events (CEL-02). They carry identifiers only and never a new `event_id` (7B Rule E-1). |
| PCW-13 | Explicitly best-effort work (loss violates no frozen invariant) may stay best-effort (CEL-09). Residual effects of owner-designated best-effort steps are recorded, not reclassified (Minor-7D-03). |

---

## 34. Post-Commit Continuation Inventory

Sources searched: AIR §12.5 (all 29 routes with a post-commit continuation), AIR §18.1 (all 84 AUDIT_ASYNC routes), AIR §34.5 (AIR-P0-EVT-01 … 04), 7B §17 (TSK-01 … TSK-19), 7B §21.2 (worker producers), and the owner documents 6A – 6M, 3B, 3C cited per row. "Mandatory" follows PCW-01.

| Flow | Owner doc | Route / worker | Committed state | Post-commit work | Mandatory? | Invariant violated if lost | Durable job / work row | Scannable durable state | Outbox event that can trigger it | Selected recovery mechanism | 7D responsibility | 7G / 7I / 7K | OD? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PCI-01 | 6B | AMI-6B-001 register | user `PENDING_VERIFICATION` | verification email | No — notification | None; user re-requests via AMI-6B-007 | — | — | — | Best-effort (user-retriable) | Classify | — | No |
| PCI-02 | 6B | AMI-6B-007 resend verification | none | email | No | None; user re-invokes | — | — | — | Best-effort | Classify | — | No |
| PCI-03 | 6B | AMI-6B-008 reset request | reset token | reset email | No | None; user re-requests (always 200) | — | — | — | Best-effort | Classify | — | No |
| PCI-04 | 6B | AMI-6B-009 reset confirm | password set, sessions revoked | Redis access-token denylist step | Yes | Security (revoked tokens honoured) | — | — | EV-001 `identity.forced_revocation_required` (same transaction) | Outbox event consumed into work: CON-01 / TSK-19 denylist worker | Relay delivers EV-001 at-least-once | 7F idempotent consumer | No |
| PCI-05 | 6C | AMI-6C-001 organization create | org + owner membership | compliance default-policy seeding (second transaction) | Yes | Lifecycle / compliance default | — | — | EV-002 `organization.created` | Outbox event consumed into work (CON-02) | Relay delivers EV-002 | 7F | No |
| PCI-06 | 6C | AMI-6C-030 policy activate | policy ACTIVE | active-policy pointer update | Yes | Compliance | — | — | EV-003 `compliance.policy_activated` | Outbox event consumed into work (CON-03) | Relay delivers EV-003 | 7F | No |
| PCI-07 | 6D | AMI-6D-001 `POST /calls` | `call_sessions` INITIATED + audit + EV-004 | `TelephonyPort.place_call()` | Yes | Lifecycle; CONCURRENT_CALLS capacity (6K §54.5) | `voice.call_dispatch_keys` (exists; API path not yet wired) | `call_sessions.status`, `updated_at` | — (EV-004 is the fact, not a dispatch trigger) | **OD-7D-03 = B**: durable dispatch key for API placement (§35.4) | Architecture + obligations IO-7D-13 / IO-7D-14 | 7K schedules reconciler; 7J alerts | **OD-7D-03** |
| PCI-08 | 6D | AMI-6D-004 terminate | `CANCELLED` (from RINGING) or `WRAP_UP` (from ANSWERED/ACTIVE) | `TelephonyPort.hangup()` | Yes | Lifecycle (WRAP_UP has no tenant exit); capacity | — | `call_sessions.status`, `updated_at` | — | **OD-7D-03**: stale-command reconciliation (§35.5) | Architecture + IO-7D-15 | 7K / 7J | **OD-7D-03** |
| PCI-09 | 6D | AMI-6D-005 transfer | `TRANSFERRING` | `TelephonyPort.transfer()` | Yes | Lifecycle (TRANSFERRING has no tenant exit); capacity | — | same | — | Stale-command reconciliation (§35.5) | same | same | **OD-7D-03** |
| PCI-10 | 6D | AMI-6D-006 hold | `ON_HOLD` | `TelephonyPort.hold()` | Yes | Platform / provider divergence | — | same | — | Stale-command reconciliation; frozen hold-timeout reaper remains (3B §18.2) | same | same | **OD-7D-03** |
| PCI-11 | 6D | AMI-6D-007 resume | `ACTIVE` | `TelephonyPort.resume()` | Yes | Platform / provider divergence | — | same | — | Stale-command reconciliation (§35.5) | same | same | **OD-7D-03** |
| PCI-12 | 6D | AMI-6D-012 recording delete | recording deleted + audit + EV-009 | object-storage cleanup | Yes | Privacy / storage | — | recording row | EV-009 `recording.deleted` | Outbox event consumed into work (CON-08 / TSK-14) | Relay delivers EV-009 | 7F; 7I | No |
| PCI-13 | 6D / 6J | AMI-6D-021 voice provider events | `webhooks.inbound_webhook_events` `RECEIVED` (dedup insert) | async domain processing after fast-ACK | Yes | Call lifecycle facts | inbound event row | `status = 'RECEIVED'` (`chk_iwe_status`, `062_5I`) | — | Durable-state reconciliation: stale `RECEIVED` rows re-dispatched; processing CAS `RECEIVED → PROCESSING` | Bind recovery source | 7H processing design; 7K schedule | No |
| PCI-14 | 6F | AMI-6F-005 archive KB | KB `ARCHIVED` | none except audit (6F §27 L903; CNF-7D-06) | — | — | — | — | — | Audit only → OD-7D-02 | Classify | — | No |
| PCI-15 | 6F | AMI-6F-006 reindex | KB `REINDEXING`, `kb_reindex_jobs` `BUILDING` (`fn_kb_reindex_begin`) | worker rebuild | Yes | Lifecycle (KB stuck REINDEXING; further reindex 409) | `knowledge.kb_reindex_jobs` | `status = 'BUILDING'`, `started_at` | — | Re-dispatch rebuild for (`knowledge_base_id`, `generation`); `uq_chunk_position` makes re-insert of a generation's chunks conflict-safe; completion only via `fn_kb_reindex_complete` / `fn_kb_reindex_fail` | Bind | 7K | No |
| PCI-16 | 6F | AMI-6F-008 upload complete | document `PENDING → PROCESSING` + EV-019 | ingestion pipeline | Yes | Lifecycle (document stuck PROCESSING) | none yet (the worker's first stage creates version + job) | `documents.status = 'PROCESSING'` with no current version / job | EV-019 `document.uploaded` (fact) | Durable-state reconciliation: re-dispatch ingestion for PROCESSING documents without an active job; the first stage's version insert is constraint-protected and stage transitions are CAS (INV-05) | Bind | 7K | No |
| PCI-17 | 6F | AMI-6F-009 URL / WEBSITE register | document PROCESSING + EV-019 | crawl + ingestion | Yes | Lifecycle | as PCI-16 | as PCI-16 | EV-019 | As PCI-16 | Bind | 7K | No |
| PCI-18 | 6F | AMI-6F-012 reprocess | new `document_versions` PENDING + `ingestion_jobs` (attempt n) | ingestion pipeline | Yes | Lifecycle | `knowledge.ingestion_jobs` | `status = 'PENDING'`, `created_at` (`037_5F`) | none (AIR-P0-EVT-02 = C) | Re-dispatch ingestion for stale PENDING jobs; worker CAS `PENDING → EXTRACTING` | Bind | 7K | No |
| PCI-19 | 6F | AMI-6F-014 delete document | chunks deleted, versions `GDPR_ERASED` (`storage_ref = 'ERASED'`), document `DELETED` | S3 object deletion (step 4) | No — owner-designated "best-effort" (6F §23.4) | Residual: object bytes may remain unreferenced | — | none (reference erased in the same transaction) | EV-020 (fact) | Best-effort by frozen owner contract; residual routed to 7I (Minor-7D-03) | Classify, record | 7I | No |
| PCI-20 | 6H | AMI-6H-007 campaign start | `PREPARING`, `agent_version_id` pinned | `prepare_campaign_contacts_task` | Yes | Lifecycle (campaign stuck PREPARING) | — | `campaigns.status = 'PREPARING'`, `updated_at` | none (AIR-P0-EVT-03 = B) | Durable-state reconciliation: re-enqueue prepare for stale PREPARING campaigns; safe because `campaign.fn_enqueue_contact` (`098_5E1`) is idempotent under redelivered materialization, `total_contacts` is set once and `PREPARING → RUNNING` is CAS (6H L377) | Bind | 7K | No |
| PCI-21 | 6H | AMI-6H-018 import complete | `csv_import_jobs` PENDING (upload confirmed) | import processing | Yes | Lifecycle | `campaign.csv_import_jobs` | `status`, progress checkpoints | EV-060 (TSK-03 trigger) | Frozen 3C stale `CsvImportJob` reaper (APScheduler) marks FAILED when no progress within its timeout (3C L660) | Record | 7K | No |
| PCI-22 | 6J | AMI-6J-004 create integration (API_KEY / BASIC / CUSTOM) | connection `CONNECTING` (credential stored first) | credential validation / activation | Yes | Lifecycle (CONNECTING forever) | — | `integration_connections.status = 'CONNECTING'` joined to `integration_definitions.auth_type IN ('API_KEY','BASIC','CUSTOM')`, `updated_at` | none until success (EV-072) | Re-dispatch activation for stale non-OAuth CONNECTING rows; `fn_activate_integration_connection` accepts only `CONNECTING` / `DEGRADED`, so a duplicate activation raises and writes no second EV-072; `fn_fail_integration_connection` for definite failure. OAuth2 CONNECTING rows are excluded (they await the user's OAuth callback) | Bind | 7K | No |
| PCI-23 | 6J | AMI-6J-007 disconnect | `DISCONNECTED` + EV-065 | secret / provider revocation | No — owner "best-effort" (6J §42.1) | Residual credential in secret manager | — | — | — | Best-effort; residual → 7I (Minor-7D-03) | Classify | 7I | No |
| PCI-24 | 6J | AMI-6J-013 sync | none durable (SETNX lock only; DEP-6J-06 V1 scope) | Celery sync task | No | None; user re-triggers | — | — | — | Best-effort (user-retriable) | Classify | — | No |
| PCI-25 | 6J | AMI-6J-014 provider callback | `inbound_webhook_events` `RECEIVED` | async processing after fast-ACK | Yes | Integration facts | inbound event row | `status = 'RECEIVED'` | — | As PCI-13 | Bind | 7H; 7K | No |
| PCI-26 | 6J | AMI-6J-025 test delivery | none (synthetic) | test delivery | No | None; user re-invokes | — | — | — | Best-effort | Classify | 7H | No |
| PCI-27 | 6J | AMI-6J-040 plugin uninstall | installation `UNINSTALLED` + EV-070 | secret purge after overlap | No — owner "best-effort" (6J §42.3) | Residual credential | — | — | — | Best-effort; residual → 7I (Minor-7D-03) | Classify | 7I | No |
| PCI-28 | 6K | AMI-6K-023 payment webhook | receipt `RECEIVED` (`102_5H2`) | async settlement processing | Yes | Money | payment-webhook receipt | `processing_status IN ('RECEIVED','RETRY_PENDING')`, `next_retry_at` (`chk_pwr_retry_scheduling`) | — | Durable-state reconciliation: stale RECEIVED and due RETRY_PENDING receipts re-dispatched; owner guarded functions settle once | Bind | 7H; 7K | No |
| PCI-29 | 6M | AMI-6M-010 refund reserve | `billing.refunds` PENDING | provider refund + settlement | Yes | Money | `billing.refunds` | `status = 'PENDING'` | — | Owner reconciliation worker (`app_billing_reconciler`) polls the provider by the reservation idempotency key and settles via guarded functions (6M §19) | Record | 7K | No |
| PCI-30 | 6D / 7B | Call end → accounting finalization (EV-079 normal path) | conversation ended; durable per-turn totals | post-call / accounting-finalization worker | Yes | Billing (INV-01) | durable finalization guard (IO-7B-16) | conversation state | — | Voice stale-conversation reaper / recovery worker invokes the same finalization (OD-7B-02; IO-7B-05) | Relay delivers EV-079 once committed | 7K (reaper) | No |
| PCI-31 | 6D | Call end → sentiment / summarization (TSK-07 / TSK-08) | call ended + EV-005 | post-call analysis | No — `summary_text` is "nullable until post-call summarization completes" (6D L1558); no frozen invariant | — | — | — | EV-005 `call.ended` ("post-`call.ended` only", 6D L1060) | Consumption of durable EV-005 where the owner binds it; otherwise best-effort | Relay delivers EV-005 | 7F | No |
| PCI-32 | 6H | APScheduler `SCHEDULED → PREPARING` | `PREPARING` | prepare task | Yes | Lifecycle | — | as PCI-20 | — | As PCI-20 | Bind | 7K | No |
| PCI-33 | 6D §28.10a / 6H | Campaign dispatch (TSK-04) | `call_dispatch_keys` RESERVED / CLAIMED / SUBMITTING / AMBIGUOUS | provider placement | Yes | Lifecycle; no double dial | `voice.call_dispatch_keys` | `dispatch_state`, `claim_expires_at` (`idx_cdk_reconciliation`) | — | Existing: RESERVED / expired CLAIMED / pre-submission FAILED re-claimable; SUBMITTING / AMBIGUOUS reconciliation-only | Record | 7K | No |
| PCI-34 | 6K §54.5 | Capacity release | reservations vs session state | ReleaseCapacity | Yes | Capacity | reservation store (reconciled to Postgres) | `call_sessions` terminal state; dispatch state | — | Existing periodic capacity reconciler (6K §54.5 rule 8) | Record | 7K | No |
| PCI-35 | 6J | Webhook delivery (TSK-15) | delivery rows | HTTP delivery | Yes | Tenant delivery (at-least-once) | `webhooks.webhook_deliveries` | delivery status / claim | EV consumed by WebhookDispatchService | Existing durable delivery rows | Relay delivers events | 7H | No |
| PCI-36 | 6K | Invoice generation, renewal, storage snapshot, API aggregation (TSK-09, 10, 12, 13) | billing state | periodic work | Yes | Money | billing rows | periods, subscriptions | — | Existing periodic scans over durable state (scheduled, not enqueued after a commit) | Record | 7K | No |
| PCI-37 | 6K | Usage / quota evaluation (TSK-11) | usage ingested | threshold evaluation | Yes | Money / quota | usage rows | usage records | durable usage events (consumed) | Runs from durable-event consumption | Relay delivers events | 7F | No |
| PCI-38 | 3B | Stale voice-session reaper | sessions | force FAILED + EV-006 | Yes | Lifecycle | — | session / call state | — | Existing APScheduler reaper (3B §18.2) | Record | 7K | No |
| PCI-39 | 5J §14.5 / AIR §18.1 | 84 AUDIT_ASYNC routes + worker-origin mandatory audit | business mutation | audit write by post-commit Celery task | Yes | Audit (AUD-04, AUD-04a) | none | none that can reconstruct actor / purpose | 7B AUD-04 forbids audit from streams | **OD-7D-02 = A**: same-transaction audit (§36) | Architecture + IO-7D-16 | 7I audit security | **OD-7D-02** |
| PCI-40 | 7B §15 | Class-D signals (DS-01 … DS-19) | producing commit | direct publish | No — best-effort by contract | None (DEL-05) | — | — | — | None (CLD-02) | §32 | 7E | No |

Inventory totals: 40 flows. Mandatory: 29 (PCI-04 … PCI-13, PCI-15 … PCI-18, PCI-20 … PCI-22, PCI-25, PCI-28 … PCI-30, PCI-32 … PCI-39). Not mandatory: 11 (PCI-01 … PCI-03, PCI-14, PCI-19, PCI-23, PCI-24, PCI-26, PCI-27, PCI-31, PCI-40). Every mandatory flow has a selected recovery mechanism (§35); none is left one-shot.

---

## 35. Recovery Mechanism per Mandatory Flow

### 35.1 Mechanism families used

| Family (CEL-09) | Flows |
|---|---|
| Outbox event consumed into work | PCI-04, PCI-05, PCI-06, PCI-12, PCI-35, PCI-37 |
| Existing durable job / work row, re-dispatched by an owner reconciler | PCI-15, PCI-18, PCI-33 |
| Durable state-machine reconciliation scan | PCI-13, PCI-16, PCI-17, PCI-20, PCI-22, PCI-25, PCI-28, PCI-32 |
| Existing frozen reaper / reconciler | PCI-21, PCI-29, PCI-30, PCI-34, PCI-36, PCI-38 |
| Owner-approved mechanism (OD-7D-03) | PCI-07 (durable dispatch key), PCI-08 … PCI-11 (stale-command reconciliation) |
| Owner-approved mechanism (OD-7D-02) | PCI-39 (same-transaction audit) |

### 35.2 Rules common to the reconciliation flows

| ID | Rule |
|---|---|
| REC-01 | Knowledge ingestion (PCI-16, PCI-17, PCI-18) and reindex (PCI-15): the worker's stage transitions are CAS updates keyed on the expected current status, so a duplicate dispatch of the same job finds the status already advanced and stops (INV-05; IO-7D-17). |
| REC-02 | Campaign preparation (PCI-20, PCI-32): re-enqueue is safe because materialization writes only through `campaign.fn_enqueue_contact`, `total_contacts` is set once, and `PREPARING → RUNNING` / `PREPARING → FAILED` are CAS transitions. |
| REC-03 | Integration activation (PCI-22): re-dispatch reads the credential through the stored `credential_ref`; activation and failure go only through the two guarded functions; OAuth2 rows are never selected. |
| REC-04 | Inbound callbacks (PCI-13, PCI-25, PCI-28): re-dispatch never re-verifies against a new body; it processes the stored, already-verified record under its owner's CAS (`RECEIVED → PROCESSING`), and payment receipts respect `next_retry_at`. |
| REC-05 | No reconciler writes the outbox directly. When a re-dispatched job produces a Class-C fact, the worker's own transition transaction writes the outbox row (SGL-02). |

### 35.3 Why no flow needs a new table

Every mandatory flow already commits a durable, scannable state in its producing transaction or has a frozen reaper, except PCI-07 (whose durable dispatch-key table exists but is not yet wired to the API path — §35.4) and PCI-39 (audit, closed by OD-7D-02 without storage). No generic task-outbox is required (PCW-11).

### 35.4 Initial call placement — durable dispatch key for `POST /calls` (OD-7D-03 = B)

**Physical verification of `voice.call_dispatch_keys` and the frozen 6D contract (performed before relying on it):**

| # | Finding | Source |
|---|---|---|
| DK-V1 | The table exists: `dispatch_idempotency_key CHAR(64)` primary key, tenant-scoped (`organization_id`, RLS), `payload_fingerprint` computed in the function, immutable `provider_request_ref`, states `RESERVED → CLAIMED → SUBMITTING → CONFIRMED / AMBIGUOUS / FAILED`, reconciliation provenance fields, index `idx_cdk_reconciliation` over `RESERVED`, `CLAIMED`, `SUBMITTING`, `AMBIGUOUS` | `099_5C1.sql` L205–L357 |
| DK-V2 | `voice.fn_initiate_outbound_call_idempotent(...)` inserts the dispatch-key row and the `call_sessions` INITIATED row in one transaction, replays idempotently on the same key, rejects a cross-tenant replay and returns `IDEMPOTENCY_KEY_REUSE_MISMATCH` for a same-tenant fingerprint mismatch. It accepts a NULL `campaign_lead_ref`. It is granted to **`app_api`** and `app_worker` | `099_5C1.sql` L476–L580 |
| DK-V3 | `fn_claim_dispatch_for_provider_submission` re-claims only `RESERVED`, `FAILED` or an expired `CLAIMED` row, never `SUBMITTING`; `fn_begin_provider_submission` commits `CLAIMED → SUBMITTING` **before** `TelephonyPort.place_call()`; the claim / begin / record functions are granted to **`app_worker` only**; reconciliation of `SUBMITTING` / `AMBIGUOUS` is restricted to `app_voice_reconciler` (provider evidence) and `app_platform_admin` (operator) | `099_5C1.sql` L596–L1070 |
| DK-V4 | The frozen 6D contract applies this protocol only to the in-process campaign caller: "a *separate* contract for a caller `POST /api/v1/calls` never serves" | 6D §28.10a L1428 |
| DK-V5 | `POST /calls` admission: the use case assigns `call_id`, calls `AcquireCapacity(reservation_id = call_id)` **before** the insert, and on refusal returns 429 with **nothing inserted**; the capacity store is outside the database transaction | 6D §42.2 L2017–L2024; 6K §54.4, §54.5 |
| DK-V6 | `fn_initiate_outbound_call_idempotent` generates `call_session_id` **inside** the function (`v_id := voice.fn_new_uuid_v7()`); it accepts no caller-assigned id | `099_5C1.sql` L491 |

**Assessment.**

1. **Double-dial safety is guaranteed by the existing model for exactly the window this decision closes.** Automatic (re-)dispatch is possible only from `RESERVED`, an expired `CLAIMED`, or a pre-submission `FAILED` row — states in which the database proves the provider was never contacted, because `SUBMITTING` is committed before any provider call (DK-V3). A crash between the `POST /calls` commit and provider submission leaves the row `RESERVED` (or `CLAIMED`), which is safely dispatchable. Provider-side ambiguity is **never** resolved by redialling: `SUBMITTING` and `AMBIGUOUS` rows are resolved only through provider evidence or an operator, never re-claimed. No frozen-source evidence shows the decision cannot be implemented safely, so 7D continues (owner instruction).
2. **The existing schema is not sufficient as-is for the API path.** DK-V5 and DK-V6 conflict: the capacity admission contract needs the call id before the insert and inserts nothing on refusal, while the reservation function creates the id internally; calling the external capacity store inside the reservation transaction is forbidden (PTX-02). In addition (DK-V3), the request role `app_api` cannot claim or begin submission, so provider submission for an API-created call must run in a worker role.
3. Therefore, per the owner's instruction, 7D records: a **governed future Phase-5 schema amendment** (IO-7D-13) and a **6D contract reconciliation** (IO-7D-14). 7D creates no migration.

**Binding requirements on those obligations (VDK-*):**

| ID | Requirement |
|---|---|
| VDK-01 | The dispatch identity for an API-created call is durable (a `voice.call_dispatch_keys` row committed in the same transaction as the INITIATED `call_sessions` row), server-authoritative (computed by the server, never accepted as a client-chosen key value), tenant-scoped, and identifies exactly one logical provider-dispatch intent. |
| VDK-02 | It is bound to the canonical `call_session_id` that the server generates for a NEW request (VDK-05 step 3): the dispatch key is derived from, or bound one-to-one to, that canonical id (for example a versioned, domain-separated hash of `organization_id` and `call_session_id`), never from the client's `Idempotency-Key`. HTTP retry stability is provided first by the frozen HTTP idempotency contract (VDK-05 steps 1–2), which returns the original response — and therefore the original `call_session_id` — without creating anything; recovery stability is provided by the durable dispatch row itself. |
| VDK-03 | It is never `event_id`, `correlation_id`, `causation_id`, a Celery task id or an in-memory flag. `payload_fingerprint` verification applies unchanged. |
| VDK-04 | `POST /calls` commits the reservation; provider submission (claim → begin → `place_call()` → record) runs afterwards in a Voice worker role that holds the `app_worker` grants, under the unchanged Step 2–4 protocol. The request still returns once its transaction commits (Tier B unchanged). |
| VDK-05 | **Exact `POST /calls` ordering (6D §42.2; 6A §16.2; 6K §54.5).** (1) Resolve the HTTP `Idempotency-Key` under the frozen API idempotency contract. (2) If it is a replay, return the cached original response: no capacity acquisition, no new `call_session_id`, no provisional id, no dispatch row, no provider call. (3) If it is new, the server generates the canonical `call_session_id`. (4) Call `AcquireCapacity(organization_id, CONCURRENT_CALLS, reservation_id = canonical call_session_id)`. (5) Only on `ADMITTED` or `ALREADY_HELD`, begin the short PostgreSQL transaction. (6) In it, the future Phase-5 API reservation path (IO-7D-13) accepts that exact server-assigned canonical `call_session_id` and atomically creates the `voice.call_sessions` row with that id and the `voice.call_dispatch_keys` row bound to that same id, together with the required audit and the required `call.initiated` outbox row under their owner contracts. (7) If the transaction fails, `ReleaseCapacity(canonical call_session_id)` runs exactly once; if the process dies after step 4 and before commit, the 6K §54.5 rule 8 reconciler releases the orphan reservation after the setup grace period. (8) If capacity refuses (`REFUSED_AT_LIMIT`, `REFUSED_NOT_CONFIGURED`, `UNAVAILABLE`), no database transaction runs, no session or dispatch row is created and the provider is never contacted. No other ordering is permitted. |
| VDK-06 | A reconciler (Voice-owned, scheduled by 7K) dispatches API-created reservations that are `RESERVED` or have an expired `CLAIMED` lease. It re-applies the calling-window, compliance and capacity gates at dispatch time, and it resolves a reservation older than a maximum dispatch age (a 6D runtime value, not an API value) to the frozen `INITIATED → FAILED` transition with capacity release instead of dialling late. |
| VDK-07 | `SUBMITTING` and `AMBIGUOUS` API reservations are never auto-dispatched. They are resolved by `fn_reconcile_dispatch_from_provider` (provider callback correlation via `provider_request_ref`, where the adapter echoes it — a disclosed dependency, `099` L302) or `fn_reconcile_dispatch_by_operator`. While unresolved the capacity slot stays held (6K §54.5 rule 8) and the condition is alerted (7J), so it is bounded by reconciliation, never permanently stranded. |
| VDK-08 | Until IO-7D-13 and IO-7D-14 land, the API placement path is not implementation-ready for pre-dispatch recovery; implementation of AMI-6D-001 dispatch (roadmap P9) is blocked on them. This is an implementation dependency, not an open 7D design question. |
| VDK-09 | The canonical `call_session_id` is the single identifier used for `AcquireCapacity`, `ReleaseCapacity`, the `voice.call_sessions` row and the dispatch-key binding. A dispatch row bound to any other id, or a capacity reservation keyed by any other id, is non-conformant. |

### 35.5 In-call commands — evidence-based stale-command reconciliation (OD-7D-03 = B, in-call part)

Durable source: `voice.call_sessions.status` and `updated_at` (`011_5C.sql`, maintained by `trg_cs_updated_at`). Owner: Voice. Scheduler: APScheduler (7K). The reconciler never repeats a provider command blindly and never calls `place_call()`. It never fabricates provider success, never completes a session solely because time elapsed, and never releases or causes release of capacity for a call that provider evidence shows active.

#### 35.5.1 Adapter command-recovery capability contract

| ID | Rule |
|---|---|
| VCC-01 | For every production telephony adapter and for each of `hangup`, `transfer`, `hold` and `resume`, the adapter declares and contract-tests at least one recovery capability before that command is enabled for that adapter: **CAP-A — safely repeatable:** the provider operation is documented and tested as safely repeatable, with a definite response that distinguishes "applied" from "already in the requested or ended state" (a definite "call already ended / not found" response is evidence that the call has ended); **CAP-B — evidence query:** the adapter can query or correlate the authoritative provider state of the call (ringing, active, held, transferring, transferred, ended) before deciding whether the command is still needed (6D §28.10a already recognizes a provider lookup as an evidence source, `PROVIDER_LOOKUP`); **CAP-C — another frozen or owner-approved deterministic provider-evidence mechanism**, recorded by the Voice owner. |
| VCC-02 | No capability is assumed for any provider, Exotel included. Frozen sources give no evidence that any provider command is idempotent, and the frozen `TelephonyPort` (4B L1275: `place_call`, `answer`, `hold`, `resume`, `transfer`, `hangup`) has no status-query method, so CAP-B for any adapter requires the governed 4B / 6D port amendment recorded in IO-7D-15. |
| VCC-03 | A command without a declared, tested capability is not enabled for that adapter. Because `hangup`, `transfer`, `hold` and `resume` back frozen 6D endpoints, an adapter is admitted to production for tenants only when all four commands carry a declared, tested capability; 7D adds no route, no error code and no degraded mode. |
| VCC-04 | Alerting is observability only: an alert is never counted as recovery of mandatory work. |
| VCC-05 | Provider evidence is: a processed provider callback for the call (the PCI-13 path), a CAP-B query or correlation result, a definite CAP-A response, or a CAP-C result. Elapsed time is never evidence. |

#### 35.5.2 Per-command resolution

Candidates are sessions in a command-pending state whose `updated_at` is older than the 6D reconciliation grace. Each candidate is resolved only from provider evidence and the frozen transition table.

| Command | Committed state | Provider evidence → action |
|---|---|---|
| terminate from `ANSWERED` / `ACTIVE` | `WRAP_UP` (non-terminal, no tenant exit; capacity held) | Call active → issue `hangup()` under the declared capability (CAP-A repeat, or a single issue after CAP-B / CAP-C evidence) and re-check evidence; call ended → frozen `WRAP_UP → COMPLETED`, releasing capacity exactly once (6K §54.5 rule 7); evidence unobtainable → the session stays `WRAP_UP` with capacity held and reconciliation retries (VSC-06). `WRAP_UP` is never completed by elapsed time and never remains stranded once evidence is obtainable. |
| terminate from `RINGING` | `CANCELLED` (terminal) | Candidates are sessions that entered `CANCELLED` by the terminate command within a look-back window covering the provider's maximum ring duration (status plus `updated_at`). Call still ringing or active → issue `hangup()` under its declared capability until provider evidence shows the call ended; call ended → done. The platform state is never revived (a terminal call accepts no commands, 4B §5.1 invariant 2); late provider callbacks are absorbed by that guard. Capacity was released by the frozen terminal transition when the call was not known to be active; the reconciler never re-acquires it, ends the physical leg on evidence and records each divergence (OBS-7D-18; Minor-7D-09). |
| transfer | `TRANSFERRING` (non-terminal, no tenant exit; capacity held) | Transferred → frozen `TRANSFERRING → TRANSFERRED`; call active with no transfer in progress or completed → frozen `TRANSFERRING → ACTIVE` ("transfer failed") — the transfer is never re-issued automatically; transfer in progress → re-check later; call ended → frozen provider-event path (PCI-13); evidence unobtainable → stays, capacity held, retry (VSC-06). |
| hold | `ON_HOLD` | Held → nothing (the frozen hold-timeout path, `ON_HOLD → ABANDONED`, applies normally); active and not held → issue `hold()` under the declared capability; the reconciliation grace is shorter than the hold timeout so the frozen reaper never abandons an un-held live call on divergence alone (IO-7D-15); call ended → provider-event path; evidence unobtainable → retry (VSC-06). |
| resume | `ACTIVE` | Provider still holding → issue `resume()` under the declared capability; not held → nothing; call ended → provider-event path; evidence unobtainable → retry (VSC-06). |

| ID | Rule |
|---|---|
| VSC-01 | A provider callback always wins: reconciler transitions are CAS updates guarded on the stale status, so a concurrent provider-driven transition makes the reconciler a no-op. |
| VSC-02 | The reconciler issues a command only under a declared capability: CAP-A (safely repeatable), or after CAP-B / CAP-C evidence shows the command is still needed. It never repeats a command blindly (VCC-01). |
| VSC-03 | Capacity is released only by a terminal transition reached on provider evidence (6K §54.5 rule 7) or by a frozen path (the hold timeout); the capacity reconciler remains the backstop (rule 8). The reconciler never releases or causes release of capacity while provider evidence shows the call active, and never completes a session because time elapsed. |
| VSC-04 | Grace, look-back and evidence windows are 6D runtime configuration (as DEP-6D-05 timers are); 7D sets no value and does not touch DEP-6D-05 or DEP-6D-10. |
| VSC-05 | Only frozen Voice transitions are used; 7D invents no state or transition. |
| VSC-06 | **Provider unavailability.** While evidence cannot be obtained, the session stays in its committed state with capacity held, reconciliation retries with bounded backoff (7A FM-09) and the condition is alerted; it resolves automatically when evidence becomes obtainable. This is the same conservative rule 6K §54.5 rule 8 applies to `SUBMITTING` / `AMBIGUOUS` dispatches. No owner-approved fallback is required, because no path completes a session without evidence. |
| VSC-07 | **Determinism.** For every committed in-call command, the outcome is fully determined by provider evidence plus the frozen transition table; every mandatory in-call path (terminate from `RINGING`, terminate from `ANSWERED` / `ACTIVE`, transfer, hold, resume) is recovered for every enabled adapter (VCC-03). |

---

## 36. Mandatory Audit Recoverability (OD-7D-02 = A)

| ID | Rule |
|---|---|
| AUD-7D-01 | Every mandatory audit record is written by `audit.fn_insert_audit_event(...)` inside the originating PostgreSQL business transaction — the request transaction, the guarded function's transaction, or the worker's own transaction — so the business mutation and its audit record commit or roll back together. |
| AUD-7D-02 | Scope: the 84 routes AIR §18.1 classifies `AUDIT_ASYNC`, and every mandatory audit that a worker would otherwise write after its commit (for example the "Billing events → Asynchronous" default of 5J §14.5). No mandatory audit record depends only on a post-commit Celery enqueue. |
| AUD-7D-03 | No new audit-intent table, no migration (113 or any other), no audit dispatcher and no second audit pipeline. The sole write path `audit.fn_insert_audit_event()` (5J §14.2), the immutable `audit.audit_events` and the nightly hash chain are unchanged (AUD-02). |
| AUD-7D-04 | The audit call is a database function; it adds no external I/O to the transaction (PTX-02). |
| AUD-7D-05 | It is not placed on the raw voice media / audio hot path. None of the 84 routes is a per-turn or per-frame operation; the voice turn loop is untouched (VOX-03). 5J's ‡ exception already audits the Voice control-plane operations synchronously. |
| AUD-7D-06 | Frozen exceptions are preserved: `AUDIT_DOMAIN/PROVIDER_PROCESSING` (AMI-6D-021, AMI-6J-014, AMI-6K-023) keeps its audit in the provider-fact processing transaction (already same-transaction); `AUDIT_CONDITIONAL` branches and `AUDIT_NONE` routes are unchanged. No frozen source requires any of the 84 routes to be asynchronous — 5J §14.5 states asynchrony as a general default ("Generally asynchronous") — so no route is excepted. |
| AUD-7D-07 | An audit write failure now rolls back the business mutation for these routes, exactly as for `AUDIT_SYNC` (AUD-03). |
| AUD-7D-08 | **Documentation alignment (governed, not performed by 7D):** 5J §14.5 rows "Configuration, campaign, plugin lifecycle changes → Generally asynchronous" and "Billing events → Asynchronous"; AIR §18.1 counts (`AUDIT_SYNC` 94 → 178, `AUDIT_ASYNC` 84 → 0; Σ 369 unchanged); and the audit statement marked asynchronous in each owner document whose routes are in the AIR §18.1 `AUDIT_ASYNC` set are reconciled by a controlled documentation-only amendment (IO-7D-16), following the precedent of the ‡ and ❖ clarifications. |
| AUD-7D-09 | Audit remains outside the event bus: it never consumes outbox events and never subscribes to streams (AUD-05; 7B AUD-04). |
| AUD-7D-10 | Audit content, redaction and security semantics remain 7I's. |

Result: the pre-enqueue audit-loss gap (FM-13, AUD-04a, T-13) is closed: there is no post-commit enqueue left on which a mandatory audit record depends.

---

## 37. Security

| ID | Rule |
|---|---|
| SEC-7D-01 | The relay and the Class-D publisher never log, export or place in metrics: access or refresh tokens, API credentials, provider credentials, signing secrets, secret-manager values, signed URLs, raw media, transcript text, raw provider callback payloads or tenant payloads (SEC-01, SEC-04, SEC-07). |
| SEC-7D-02 | Payload logging is **off by default**. No production configuration enables it without 7I-approved redaction. |
| SEC-7D-03 | Relay logs carry only: `event_id`, `event_type`, `event_version`, the organization scope in the representation 7I prescribes (until 7I, the organization UUID or "platform" in internal operational logs only, never in metrics and never on a tenant-visible surface), relay identity, claim / publish state, `attempt_count`, `max_attempts`, and a safe error category (DSP-08). |
| SEC-7D-04 | The relay does not inspect payloads, so it neither detects nor strips sensitive content; exclusion is guaranteed upstream by producer validation (7C §19.3, PV-C12). |
| SEC-7D-05 | The relay's PostgreSQL credential (for `app_worker`, preferably a distinct credential for the relay workload) and its Redis credential come from the secret manager; they never appear in logs, envelopes or telemetry. |
| SEC-7D-06 | The relay exposes no API surface (TOP-08). |
| SEC-7D-07 | Operator cleanup under `app_platform_admin` (CLN-07) and any operator action on `FAILED` rows are privileged and audited operations (SEC-08, RPL-04); their design is 7G / 7I's. |
| SEC-7D-08 | Final field classification, redaction and DSR interaction are 7I's (DD-19). |

## 38. Tenancy

| ID | Rule |
|---|---|
| TEN-7D-01 | The relay publishes `organization_id` exactly from the committed outbox row. The trusted origin is the producing transaction's tenant context, guarded on insert by `trg_outbox_tenant_check` (TEN-02). |
| TEN-7D-02 | The relay never derives tenant identity from payload and never accepts a tenant override from transport configuration, routing or metadata (TPT-04). |
| TEN-7D-03 | A NULL `organization_id` is published as JSON `null` and means "explicitly platform-scoped" (only EV-001 today, TEN-C02). |
| TEN-7D-04 | The relay authorizes no business action and sets no tenant context. Consumers re-establish tenant context from the envelope and verify referenced resources (TEN-02, TEN-04; 7F / 7I). |
| TEN-7D-05 | Relay telemetry is tenant-safe: no metric label carries an arbitrary tenant id unless 7J permits it (TEN-05). |

## 39. Data Residency

| ID | Rule |
|---|---|
| RES-7D-01 | There is no global cross-region event bus (RES-03). A relay deployment drains exactly one regional PostgreSQL outbox and publishes only to the transport in the same region. |
| RES-7D-02 | Each relay deployment carries a region tag in its configuration for both its database and its transport, and refuses to start if they differ (IO-7D-11). The region tag is part of the relay identity (RID-04). |
| RES-7D-03 | For `INDIA_ENTERPRISE` tenants, every copy in scope — outbox rows, stream entries, relay logs, dropped-signal counters and any replay copy — stays in the contracted region (RES-02). |
| RES-7D-04 | The relay design has no global coordination (no leader, no global lock, no cross-region claim), so it is region-compatible by construction. Regional topology, failover and disaster recovery are 7K's (DD-18). |

## 40. Voice Hot Path

| ID | Rule |
|---|---|
| VOX-7D-01 | No audio, PCM, media frame or per-frame event passes through the outbox, the relay, the Class-D publisher or Redis Streams (VOX-02, RS-06). |
| VOX-7D-02 | Nothing on the conversational hot path waits for relay publication, consumer processing or a REST hop (VOX-03, CON-04). Voice producers write their outbox row in their transaction and return. |
| VOX-7D-03 | There is no per-turn outbox row (INV-03). DS-17 is a Class-D signal published non-blockingly (CLD-05). |
| VOX-7D-04 | The relay never runs in `voice_gateway` or any media-path process (TOP-06). |
| VOX-7D-05 | OD-7D-02's same-transaction audit does not touch the turn loop (AUD-7D-05). |
| VOX-7D-06 | ≤ 750 ms remains a target, not a guarantee (VOX-01). Nothing in 7D claims otherwise. |

---

## 41. Observability Emission Points

### 41.1 Reconciliation of 7A wording (CNF-7D-01)

7A §13 lists "relay metrics names" among the items deferred to 7D, while 7A §29 and DD-17 defer "names, cardinality budgets, dashboards and alert thresholds" to 7J, and 7B §33.1 routes event metric names to 7J. Resolved by concern: **7D defines what the relay exposes (semantic emission points); 7J owns final names, cardinality policy, SLOs, dashboards and alert thresholds.** 7D fixes no metric name.

### 41.2 Semantic emission points

| ID | Emission point (semantic) | Kind | Notes |
|---|---|---|---|
| OBS-7D-01 | Eligible backlog count | Gauge | Rows `PENDING` and due, plus expired `CLAIMED` (7A OBS-06) |
| OBS-7D-02 | Oldest eligible event age | Gauge | now − `occurred_at` / `available_at` of the oldest eligible row (OBS-04) |
| OBS-7D-03 | Claimed count per batch; batch size used | Distribution | — |
| OBS-7D-04 | Expired-claim reclaim count | Counter | Rows claimed whose previous status was `CLAIMED` |
| OBS-7D-05 | Publish outcome counts by class | Counter | `CONFIRMED`, `ROW_REJECTED`, `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED`, `UNKNOWN`, `RELAY_CAPABILITY` |
| OBS-7D-06 | Transport availability gate state and transitions | Gauge / counter | CLOSED / OPEN, probe results |
| OBS-7D-07 | Claim duration, publish duration, mark-progress duration | Distribution | — |
| OBS-7D-08 | Terminal `FAILED` count and current `FAILED` rows | Counter / gauge | Handoff to 7G |
| OBS-7D-09 | CAS misses on mark-published / mark-failed | Counter | Indicates lease expiry or intervention |
| OBS-7D-10 | Repeated identical `ROW_REJECTED` categories across batches | Counter | GATE-09 |
| OBS-7D-11 | `RELAY_CAPABILITY` by sub-cause (`NO_ROUTE`, `RELAY_DEFECT`) | Counter | Deployment-compatibility signal (DPC-04) |
| OBS-7D-12 | Contract anomalies observed without repair | Counter | e.g. MAT-10 case |
| OBS-7D-13 | Publication latency (publish time − `occurred_at`) | Distribution | Never used as a Billing time (OCC-04) |
| OBS-7D-14 | Class-D signals published / dropped | Counter | CLD-06 |
| OBS-7D-15 | Cleanup rows deleted by predicate | Counter | CLN-07 |
| OBS-7D-16 | Mandatory-work reconciler: candidates, re-dispatched, fallback-resolved, per flow | Counter | PCW-10 |
| OBS-7D-17 | Trace / log correlation fields | Log / trace | `event_id`, `event_type`, `event_version`, relay identity; `correlation_id` / `causation_id` once present (OBS-01, OBS-02) |
| OBS-7D-18 | Voice stale-command reconciliation: evidence obtained / unobtainable, commands issued under declared capability, `CANCELLED`-but-ringing divergences, sessions held pending evidence | Counter / gauge | §35.5 |

### 41.3 Cardinality

| ID | Rule |
|---|---|
| OBS-7D-C1 | Metric labels never carry raw `event_id`, `call_id`, `contact_id`, payload values or arbitrary tenant ids unless 7J explicitly permits it (TEN-05). Those values may appear in structured logs and traces under 7J / 7I policy. |
| OBS-7D-C2 | Bounded labels only: outcome class, gate state, relay role, region tag, `event_type` (bounded by the 107-pair manifest), safe error category. |

---

## 42. Failure Matrix

| ID | Failure | Starting state | Authoritative state | Duplicate allowed? | Loss allowed? | Required recovery | Responsible |
|---|---|---|---|---|---|---|---|
| F7D-01 | PostgreSQL unavailable before claim | Rows `PENDING` | PostgreSQL (unreachable) | — | No | Claim fails (CLM-07); loop backs off and retries; producers also cannot commit, so no new fact exists to lose | 7D; 7K (DB availability) |
| F7D-02 | Redis unavailable before claim | Rows `PENDING`; gate CLOSED | PostgreSQL outbox | No | No | First batch fails at connection level → gate OPEN (GATE-02); no further claims (GATE-03); rows deferred without terminal risk (DSP-03) | 7D |
| F7D-03 | Process dies after claim | Rows `CLAIMED` | PostgreSQL outbox | Yes | No | Lease expiry (DB clock) → reclaim (LSE-07) | 7D |
| F7D-04 | Redis unavailable after claim | Rows `CLAIMED` | PostgreSQL outbox | Yes (if partially accepted) | No | Outcomes `TRANSPORT_UNAVAILABLE` / `NOT_ATTEMPTED` / `UNKNOWN` → deferral (DSP-03); gate OPEN | 7D |
| F7D-05 | One `XADD` fails definitively (entry-specific) | Row `CLAIMED` | PostgreSQL outbox | No | No | `ROW_REJECTED` → `fn_mark_outbox_failed` → `PENDING` (+30 s) or `FAILED` at budget (DSP-04) | 7D; 7G (FAILED disposition) |
| F7D-06 | `XADD` result unknown | Row `CLAIMED` | PostgreSQL outbox | Yes | No | `UNKNOWN` → deferral; republish same `event_id` (AMB-01) | 7D; 7F (dedup) |
| F7D-07 | Partial Redis pipeline success | Batch `CLAIMED` | PostgreSQL outbox | Yes | No | Per-row outcomes (§23); only `CONFIRMED` rows marked published | 7D |
| F7D-08 | Publish succeeds, DB mark fails | Row `CLAIMED`; entry in stream | PostgreSQL outbox | Yes | No | Mark retried within deadline; else lease expiry → republish (AMB-03) | 7D; 7F |
| F7D-09 | Mark-published CAS loses | Row reclaimed by another loop | PostgreSQL outbox | Yes | No | Record anomaly; newer claimant publishes again (DSP-02) | 7D |
| F7D-10 | Claim expires during slow publish | Row `CLAIMED` (expired) | PostgreSQL outbox | Yes | No | Another loop reclaims; late CAS calls are no-ops (LSE-08) | 7D |
| F7D-11 | Two relay replicas contend | Rows `PENDING` | PostgreSQL outbox | No | No | `SKIP LOCKED` makes claims disjoint (§16.3) | 7D |
| F7D-12 | Stale relay process resumes (e.g. long pause) | Its rows reclaimed by others | PostgreSQL outbox | Yes | No | Local deadline stops new work (LSE-04); marks CAS-miss harmlessly | 7D |
| F7D-13 | Deployment with old backlog | Rows of older / newer versions | PostgreSQL outbox | No | No | Transport-generic materialization; no version gate (DPC-02 … DPC-05) | 7D; 7C (compatibility) |
| F7D-14 | Unsupported / corrupt outbox row (no route, relay defect, non-conformant value) | Row `CLAIMED` | PostgreSQL outbox | No | No | `RELAY_CAPABILITY` → deferral, never terminal; contract anomaly reported; never repaired (MAN-04, MAT-12, CV-11) | 7D; producer owner fixes forward; 7G operator handling |
| F7D-15 | Global Redis outage | Backlog grows | PostgreSQL outbox | No | No | Gate OPEN; commits continue (GATE-07); resume after probe success (GATE-08); **no terminal-FAILED storm** (§24.1) | 7D; 7K (catch-up) |
| F7D-16 | Graceful shutdown with claims | Batch `CLAIMED` | PostgreSQL outbox | Yes | No | §28: finish bounded exchange, record outcomes, leave the rest to lease expiry | 7D |
| F7D-17 | DB commit → process death before mandatory Celery enqueue | Owner state committed | Owner PostgreSQL state | Duplicate dispatch allowed | No | Owner reconciler over durable state (§33 – §35) | 7D (architecture); owners; 7K (schedule) |
| F7D-18 | Mandatory async-audit pre-enqueue loss | — | — | — | No | Eliminated: audit written in the originating transaction (OD-7D-02, §36) | 7D; 7I |
| F7D-19 | Cleanup runs during backlog | Mixed statuses | PostgreSQL outbox | — | No | Cleanup predicates select only old `PUBLISHED` and dispositioned old `FAILED` rows (CLN-02, CLN-04) | 7D; 7G |
| F7D-20 | Outbox grows during extended Redis outage | Large `PENDING` backlog | PostgreSQL outbox | — | No | Rows retained (cleanup never touches them); oldest-age and backlog visible (OBS-7D-01, -02); capacity and catch-up are 7K's | 7K; 7J |
| F7D-21 | Redis primary failover, or another fault inside 7E's declared transport fault model, after an entry was `CONFIRMED` and its row marked `PUBLISHED` | Rows `PUBLISHED` | PostgreSQL outbox (the obligation is discharged only by a durable `CONFIRMED`) | Yes | No | Prevented by construction: `CONFIRMED` requires the 7E durable-acceptance property (TPT-02, HO-7E-03), so normal failover cannot lose a confirmed entry. Replay of `PUBLISHED` rows still inside the cleanup window (CLN-08, HO-7G-03) is disaster / repair capability for faults outside the declared fault model, never a substitute for the acceptance guarantee | 7E; 7G / 7K (disaster repair) |
| F7D-22 | Relay loops configured with different leases | Rows `CLAIMED` | PostgreSQL outbox | Yes | No | LSE-05 requires one fleet-wide lease; the minimum governs during changes | 7D; 7K |
| F7D-23 | New producer, old relay without a route | Row `CLAIMED` | PostgreSQL outbox | No | No | `RELAY_CAPABILITY` deferral until a relay with the route runs (DPC-04) | 7D; 7E |
| F7D-24 | Redis outage breaks post-commit enqueue for mandatory work | Owner state committed | Owner PostgreSQL state | Duplicate dispatch allowed | No | PCW-09: no rollback or failure report; reconciler completes it after recovery | Owners; 7K |
| F7D-25 | Class-D publish during Redis outage | Signal in memory | None (non-durable) | — | **Yes, by contract** | Dropped and counted (CLD-06); never outboxed | 7D (contract); 7E |
| F7D-26 | API call reservation crashes before provider submission | Dispatch key `RESERVED` / `CLAIMED` | PostgreSQL | No double dial | No | Dispatch reconciler (VDK-06); `SUBMITTING` / `AMBIGUOUS` reconciliation-only (VDK-07) | Voice (6D); 7K |
| F7D-27 | HTTP replay of `POST /calls` while capacity is full | Original call committed | HTTP idempotency record + PostgreSQL | No | No | Replay resolved first; cached original response; no `AcquireCapacity`, so never a 429 for a replay (VDK-05 steps 1–2) | Voice (6D) |
| F7D-28 | Process dies after `AcquireCapacity`, before the reservation transaction commits | Reservation held; no session row | PostgreSQL (no session) | No | No | 6K §54.5 rule 8 orphan release after the setup grace period; no dispatch row exists, so the provider is never contacted (VDK-05 step 7) | 6K; 7K |
| F7D-29 | Terminate from `ANSWERED` / `ACTIVE` commits `WRAP_UP`; process dies before `hangup()` | `WRAP_UP`; capacity held | `voice.call_sessions` + provider evidence | No | No | Evidence-based reconciliation (§35.5.2): call active → hangup under declared capability; call ended → frozen `WRAP_UP → COMPLETED`; never completed by elapsed time | Voice (6D); 7K |
| F7D-30 | Terminate from `RINGING` commits `CANCELLED`; process dies before `hangup()` | `CANCELLED` (terminal); physical leg may ring | Provider evidence | No | No | Cancellation reconciliation (§35.5.2): hangup under declared capability until provider evidence shows the call ended; platform state is not revived | Voice (6D); 7K |
| F7D-31 | Provider unreachable during command reconciliation | Command-pending state | `voice.call_sessions` | No | No | State and capacity held; reconciliation retries with bounded backoff (7A FM-09); resolves automatically when evidence is obtainable (VSC-06) | Voice (6D); 7K |

---

## 43. Handoffs

### 43.1 To 7E (Redis topology)

| ID | 7E receives / must provide |
|---|---|
| HO-7E-01 | Already-materialized internal envelopes as immutable UTF-8 JSON bytes plus read-only routing attributes (§21). 7E defines stream routing, stream names, group topology, retention, sharding and Redis sizing without changing 7D durability semantics. |
| HO-7E-02 | An implementation of `DurableEventTransportPublisher` meeting TPT-01 … TPT-11, with a per-entry outcome for every entry and a non-claiming health probe. |
| HO-7E-03 | **Durable acceptance mechanism (mandatory).** For the durable A/B/C path, 7E MUST define the mechanism by which a transport acceptance is durable enough to satisfy the frozen at-least-once contract (TPT-02): an accepted-and-confirmed entry survives normal failover and every fault in 7E's declared transport fault model, and is delivered at least once. 7E chooses the Redis topology, persistence, replication and confirmation technique. A residual transport-loss window is **not** an available 7E choice for the durable path. Until 7E provides the mechanism, the adapter classifies no outcome as `CONFIRMED` (TPT-08) and the relay is not production-ready (IO-7D-22). |
| HO-7E-04 | The error-classification table mapping transport errors to outcome classes; any error not positively entry-specific maps to a non-terminal class (TPT-08, GATE-09). |
| HO-7E-05 | Acceptance of any entry up to the outbox's physical payload bound without size rejection (TPT-09). |
| HO-7E-06 | An exact-type route function covering the 107 durable V1 pairs, with no family / wildcard / regex / prefix keys (TPT-05); distinct signal routes for the 4 SIGNAL pairs (TPT-06). |
| HO-7E-07 | 7E may not make Redis authoritative for anything (RS-01, RS-02, TPT-10) and may not require the relay to hold a database transaction during I/O. |

### 43.2 To 7F (consumers)

| ID | 7F receives |
|---|---|
| HO-7F-01 | At-least-once durable delivery: duplicates of the same `event_id` are expected (§26, CRS matrix). |
| HO-7F-02 | No ordering guarantee across loops, aggregates or types (SCL-02). |
| HO-7F-03 | 7F owns consumer claim / ack processing, the consumer transaction, idempotency, dedup, ordering tolerance and the shared-inbox decision. 7D does not solve duplicate consumer effects. |

### 43.3 To 7G (retry, DLQ, replay)

| ID | 7G receives |
|---|---|
| HO-7G-01 | Publisher-side terminal `FAILED` rows (`ROW_REJECTED` at budget), their `last_error` safe category and their retention rule (CLN-04: not deleted before a 7G disposition exists). |
| HO-7G-02 | Final relay retry timing policy (`p_next_attempt_at`; today `NULL` → database 30 s) (DD-10). |
| HO-7G-03 | Disaster / repair replay from retained `PUBLISHED` rows after a transport fault outside 7E's declared fault model (F7D-21, CLN-08); not part of normal delivery; operator authorization and audit (RPL-04). |
| HO-7G-04 | The distinction publisher retry state vs consumer retry state (DSP-09); consumer failures, poison messages, DLQ / parking and replay are 7G's. |
| HO-7G-05 | Terminal disposition policy that accounts for `attempt_count` counting claims rather than entry-specific failures (§24.1): a `ROW_REJECTED` row may reach `FAILED` with a claim-inflated count; 7G decides review / re-drive policy. No migration is implied by 7D. |

### 43.4 To 7I (security / privacy)

| ID | 7I receives |
|---|---|
| HO-7I-01 | Field sensitivity, payload redaction and the organization-scope representation in logs (SEC-7D-03). |
| HO-7I-02 | Security semantics of the same-transaction audit (OD-7D-02) and audit content. |
| HO-7I-03 | Operator authorization for cleanup, `FAILED` disposition and replay; DLQ sensitivity. |
| HO-7I-04 | Residual privacy / credential effects of owner-designated best-effort steps (Minor-7D-03). |

### 43.5 To 7J (observability)

| ID | 7J receives |
|---|---|
| HO-7J-01 | The semantic emission points OBS-7D-01 … OBS-7D-17 and the cardinality rules OBS-7D-C1, OBS-7D-C2. |
| HO-7J-02 | Final metric names, dashboards, SLOs, alert thresholds and cardinality budgets (7D fixes none). |
| HO-7J-03 | Alerting for gate OPEN duration, oldest-eligible age, `FAILED` rows, `RELAY_CAPABILITY`, dispatch keys in `SUBMITTING` / `AMBIGUOUS`, stale command states and reconciler fallbacks. |

### 43.6 To 7K (recovery, capacity, regional topology)

| ID | 7K receives |
|---|---|
| HO-7K-01 | Relay replica count, sizing, placement, autoscaling and database connection budget (TOP-10, SCL-05). |
| HO-7K-02 | Extended-outage catch-up and global backpressure (GATE-08, F7D-20). |
| HO-7K-03 | Regional topology and disaster recovery for the region-local relay (RES-7D-01 … RES-7D-04). |
| HO-7K-04 | Schedules and staleness thresholds of all mandatory-work reconcilers (PCW-03), including the Voice dispatch and stale-command reconcilers (VDK-06, §35.5) and the stale-conversation reaper (IO-7B-05). |
| HO-7K-05 | Benchmarks for idle delay, probe backoff, safety margin and any change to batch size or lease (POL-06, POL-07). |

---

## 44. ADR Register

| ADR | Context | Decision | Rejected alternatives | Consequence |
|---|---|---|---|---|
| ADR-7D-01 | 7A OUT-01 | The existing `audit.domain_event_outbox` is the only outbox for Classes A / B / C | Per-context or per-class outboxes | SGL-01 … SGL-05 |
| ADR-7D-02 | Topology left open by 7A §13 / AIR §32; sources lean differently | Dedicated relay runtime role, same image, own entrypoint (OD-7D-01 = A) | Celery-managed relay; in-process loop in API pods | §13 |
| ADR-7D-03 | Claim logic exists in the executed function | Claim only through `fn_claim_outbox_events` | Application-side `SELECT … FOR UPDATE SKIP LOCKED` + `UPDATE` | CLM-01 |
| ADR-7D-04 | No transaction may span external I/O | Short claim transaction → publish outside any transaction → short progress transaction | Holding the claim transaction through Redis I/O; Redis `MULTI` / 2PC | LOOP-01 … LOOP-03 |
| ADR-7D-05 | Concurrent relays | No leader election, no distributed lock | Leader row, Redis lock, etcd / ZooKeeper | §16.4 |
| ADR-7D-06 | Ambiguity cannot be removed | At-least-once; resolve every doubt toward duplicate, never loss | Exactly-once claims; dropping unknown outcomes | §26, LSE-09 |
| ADR-7D-07 | `attempt_count` counts claims (PHY-01) | Six outcome classes; unclassified errors default to non-terminal; deferral calls `fn_mark_outbox_failed` only when it must return `PENDING` | Marking every failed publish via `fn_mark_outbox_failed` | §22, §24 |
| ADR-7D-08 | REL-07 under outage | Per-loop availability gate: open on the first connection-level failure, no claims while open, non-claiming probe | Threshold-tuned breaker; claiming to probe | §25 |
| ADR-7D-09 | Pipelining | Efficiency only; one outcome per row | All-or-nothing batch marking | §22.1, §23 |
| ADR-7D-10 | Relay vs schema | Schema-agnostic relay; exact-type routing; no manifest gate | Relay-side validation or version gating | MAN-04, MAN-05, DPC-02 |
| ADR-7D-11 | Lossless wire encoding (KEY-05) | Single rename `id` → `event_id`; payload carried as committed JSON text; one serialization | Decode/re-encode through native floats | §20 |
| ADR-7D-12 | DD-09 | Keep batch 50 and lease 300 s; adaptive polling with configured idle delay | Invented tuning numbers | §18 |
| ADR-7D-13 | DD-21 | Owner reconcilers over durable owner state; no generic task-outbox | New task-outbox table | §33 – §35 |
| ADR-7D-14 | Async-audit gap | Same-transaction audit (OD-7D-02 = A) | Audit-intent table; hybrid | §36 |
| ADR-7D-15 | Voice call-command gap | Durable dispatch key for `POST /calls` with the exact replay-first, capacity-before-transaction ordering bound to one canonical `call_session_id` (VDK-05, VDK-09); evidence-based stale-command reconciliation for in-call commands under a per-adapter recovery-capability contract (OD-7D-03 = B; §35.5) | Terminate-only reconciliation; best-effort acceptance; provisional capacity for replays; time-based completion | §35.4, §35.5 |
| ADR-7D-16 | Cleanup | Separate, operator-invoked, documented predicates only; `FAILED` retained until 7G disposition | Relay-driven deletion; Redis-state-driven deletion | §31 |
| ADR-7D-17 | Class D | Separate non-durable publisher, never outboxed | Outboxing signals | §32 |
| ADR-7D-18 | Residency | Region-local relay, region tag check | Global relay / cross-region publication | §39 |
| ADR-7D-19 | Transport confirmation boundary (P1-7D-R01) | `CONFIRMED` = the 7E-defined durable acceptance that satisfies the frozen at-least-once contract; an `XADD` entry ID alone is insufficient; no residual-loss option on the durable path | Entry ID as confirmation; a 7E-chosen residual loss window covered by replay | TPT-02, HO-7E-03, F7D-21 |
| ADR-7D-20 | OD-7C-04 relay rollout (P1-7D-R02) | Staged rollout: columns → column-aware relays → verify all replicas → producer activation; per-field presence; no relay strips a present value | Old relays tolerated after activation | DPC-07, MAT-10 |
| ADR-7D-21 | In-call command recovery (P1-7D-R04) | Per-adapter recovery-capability contract (CAP-A / CAP-B / CAP-C) gating command enablement, and evidence-only resolution with conservative hold during provider unavailability | Idempotency-only re-issue with time-based completion; alert-only handling | §35.5 |

ADR count: **21**.

---

## 45. Owner Decision Register

All three decisions were raised by 7D (source gap or conflict, several legitimate options, material impact), presented as packets, and answered by the owner. They are **DECIDED · RESOLVED · owner-approved · final**. Each applies only to its stated scope.

### 45.1 OD-7D-01 — Relay execution topology

| Item | Record |
|---|---|
| Question | Which execution topology does the outbox relay use? |
| Source gap / conflict | 7A §13 and AIR §32 assign topology to Phase 7; 6K L2518 describes the publisher as "Continuous (Celery worker pool)"; 6C L257 names "the platform's existing outbox-publisher worker (3A `eventbus/publisher.py`)"; 3F defines three workloads (api, voice_gateway, Celery worker) and none for a relay (CNF-7D-02) |
| Options | **A** dedicated relay runtime role; **B** Celery-managed relay on the worker deployment; **C** in-process loop inside API (and/or worker) instances |
| Pros / cons | A: isolated from Celery Beat and pool contention, clean shutdown, independent scaling / an additional workload. B: no new workload, matches 6K wording / depends on Beat or broker self-rescheduling, visibility-timeout interaction, pool contention. C: no new workload / couples relay to HTTP scaling and latency |
| Correctness impact | None between options (SKIP LOCKED + lease + CAS) |
| Operational impact | Workload, scaling and shutdown behaviour differ |
| Migration impact | None |
| Recommended | A |
| **Selected** | **A** |
| Status | DECIDED · RESOLVED · owner-approved |
| Owner requirements carried | One or more stateless replicas; correctness from PostgreSQL state, SKIP LOCKED, lease and CAS; no leader election; no Redis distributed lock; no Celery Beat dependency; no coupling to API pod scaling; voice_gateway / media-path processes never host the relay; clean SIGTERM behaviour; still a modular monolith — a runtime role, not a microservice or bounded context |
| Applied in | §13 (TOP-01 … TOP-10), §28, ADR-7D-02 |

### 45.2 OD-7D-02 — Mandatory asynchronous audit durability

| Item | Record |
|---|---|
| Question | How is the pre-enqueue audit-loss gap (AUD-04a, FM-13) closed for the 84 `AUDIT_ASYNC` routes? |
| Source gap / conflict | 5J §14.5 makes configuration / campaign / plugin / billing audit "generally asynchronous (Celery)"; AIR §18.1 records 84 routes as post-commit Celery writes "retried; not best-effort"; 7A AUD-04a shows broker retries cannot cover the pre-enqueue window; no durable state can reconstruct actor / purpose; 7B AUD-04 forbids driving audit from streams (CNF-7D-04) |
| Options | **A** same-transaction audit (documentation-only alignment; no migration); **B** durable audit work-intent table (future migration, dispatcher); **C** hybrid |
| Correctness impact | A and B both close the gap; A couples mutation success to the audit insert |
| Operational impact | A: one extra DB write per request, no new component. B: new table, dispatcher, cleanup |
| Migration impact | A: none. B: a governed Phase-5 migration |
| Recommended | A |
| **Selected** | **A** |
| Status | DECIDED · RESOLVED · owner-approved |
| Owner constraints carried | No audit-intent table, no migration 113, no audit dispatcher, no second audit pipeline; mutation and mandatory audit succeed or roll back together; AUDIT_ASYNC documentation reconciled as a governed alignment obligation; not on the raw voice media path; explicitly frozen exceptions preserved |
| Applied in | §36 (AUD-7D-01 … AUD-7D-10), PCI-39, IO-7D-16, ADR-7D-14 |

### 45.3 OD-7D-03 — Voice call-command pre-dispatch recovery

| Item | Record |
|---|---|
| Question | How does Voice recover call commands committed but never sent to the provider (AMI-6D-001 `place_call`; AMI-6D-004 … 007)? |
| Source gap / conflict | 6D §23.3 dispatches `TelephonyPort` calls after commit with no durable intent; AIR §12.5 cites a "dispatch reconciler" for AMI-6D-001, but 6D §28.10a states that protocol serves only the in-process campaign caller (CNF-7D-03); INITIATED, TRANSFERRING and WRAP_UP have no tenant exit and hold CONCURRENT_CALLS capacity |
| Options | **A** Voice stale-command reconciliation, never auto re-dial; **B** durable dispatch key for `POST /calls` plus A for in-call commands; **C** accept as best-effort |
| Correctness impact | B closes the placement gap without double dial; A alone fails stale placements; C leaves stranded sessions |
| Migration impact | B: possible governed Phase-5 amendment (verified in §35.4: needed) |
| Recommended | A |
| **Selected** | **B** (owner) — durable dispatch key for initial `POST /calls` placement, plus stale-command reconciliation for hangup / transfer / hold / resume |
| Status | DECIDED · RESOLVED · owner-approved |
| Owner constraints carried | No migration 113 in 7D; verify existing schema first (done: insufficient as-is, §35.4 DK-V1 … DK-V6); record a governed future Phase-5 amendment and 6D reconciliation (IO-7D-13, IO-7D-14); dispatch identity durable, server-authoritative, one intent, stable, never `event_id` / `correlation_id`, not in-memory; no auto-redial of ambiguous placements; in-call commands re-issued only when provably idempotent, otherwise frozen fallback transitions (as remediated by P1-7D-R04: a command is issued only under a declared, tested adapter capability — safely repeatable, or after provider evidence shows it is still needed — and every fallback transition requires provider evidence, VCC-01, VSC-02, VSC-03); capacity never permanently stranded |
| Safety check | Safe redispatch is guaranteed for `RESERVED` / expired `CLAIMED` / pre-submission `FAILED` rows; `SUBMITTING` / `AMBIGUOUS` are reconciliation-only. No frozen-source evidence shows the decision cannot be implemented safely, so no STOP was required |
| Applied in | §35.4 (VDK-01 … VDK-09), §35.5 (VCC-01 … VCC-05, VSC-01 … VSC-07), PCI-07 … PCI-11, IO-7D-13 … IO-7D-15, ADR-7D-15, ADR-7D-21; remediated by P1-7D-R03 and P1-7D-R04 (§49.4) without reopening the decision |

### 45.4 Summary

| OD | Selected | Status |
|---|---|---|
| OD-7D-01 | A — dedicated relay runtime role | DECIDED · RESOLVED |
| OD-7D-02 | A — same-transaction mandatory audit | DECIDED · RESOLVED |
| OD-7D-03 | B — durable dispatch key for `POST /calls` + stale-command reconciliation | DECIDED · RESOLVED |

Preserved upstream decisions, not reopened: OD-7B-01, OD-7B-02, OD-7C-01 … OD-7C-07.

Current open owner decisions: **0**.

---

## 46. Implementation Obligations

Design only; 7D implements none. "Blocking" means blocking the named implementation step, not 7D readiness.

| IO | Obligation | Owner | Trigger / dependency | Phase | Blocking? |
|---|---|---|---|---|---|
| IO-7D-01 | Relay runtime role: entrypoint, workload definition, readiness / liveness, termination grace (TOP-01 … TOP-10, SHD-07, SHD-08) | Platform event infrastructure; 7K sizing | OD-7D-01 | P7 relay build | Blocks relay go-live |
| IO-7D-02 | Relay loop per §19 with the loop invariants LOOP-01 … LOOP-05 | Platform event infrastructure | IO-7D-01 | P7 | Blocks relay go-live |
| IO-7D-03 | Relay identity per claim loop (RID-01 … RID-07) | Platform event infrastructure | — | P7 | Blocks relay go-live |
| IO-7D-04 | Envelope materializer: lossless payload path (MAT-08), shared six-digit timestamp formatter (IO-7C-12), closed key set | Platform event infrastructure | IO-7C-12 | P7 | Blocks relay go-live |
| IO-7D-05 | Transport adapter implementing the port (TPT-01 … TPT-11) | 7E / Platform | 7E design | P7 | Blocks relay go-live |
| IO-7D-06 | Outcome classifier and per-row accounting; partial-batch handling (§22 – §24) | Platform event infrastructure | IO-7D-05, HO-7E-04 | P7 | Blocks relay go-live |
| IO-7D-07 | Availability gate and health probe (§25) | Platform event infrastructure | IO-7D-05 | P7 | Blocks relay go-live |
| IO-7D-08 | Configuration: batch 50, lease 300 s, fleet-uniform lease (LSE-05), safety margin, idle delay, probe backoff | Platform; 7K | — | P7 | Blocks relay go-live |
| IO-7D-09 | Benchmark and set idle delay, probe backoff and safety margin before production (POL-06) | 7J / 7K | IO-7D-02 | P21 / P23 | Blocks production tuning only |
| IO-7D-10 | Operator cleanup procedure under the existing grant, documented predicates, batching, audit, `FAILED` gated by 7G disposition (CLN-04, CLN-07) | Platform operations; 7G; 7I | 7G | P7 / ops | Non-blocking |
| IO-7D-11 | Region binding: region tag on DB and transport config; refuse to start on mismatch (RES-7D-02) | Platform; 7K | 7K topology | P7 | Blocks relay go-live |
| IO-7D-12 | OD-7C-04 rollout (DPC-07, MAT-10): (a) to the IO-7C-01 migration owner — nullable columns, and make `correlation_id IS NULL AND causation_id IS NOT NULL` structurally impossible for rows written after Stage 4; (b) the column-aware relay build; (c) the Stage 3 deployment gate verifying that every active relay replica is column-aware before producer activation, and a guard preventing old relay builds after Stage 4; (d) 7C traceability CC-02, CC-03, CC-04, BR-05 | Phase-5 database owner; Platform; producing domains | IO-7C-01 | Future governed migration + relay release | Blocks producer activation of correlation / causation (Stage 4) |
| IO-7D-13 | Governed future Phase-5 amendment: an API-call reservation path on `voice.call_sessions` / `voice.call_dispatch_keys` that accepts the exact server-assigned canonical `call_session_id` (VDK-05 step 6, VDK-09) and atomically creates the session row with that id and the dispatch-key row bound to it, keeping the tenant check and `payload_fingerprint` verification. Not migration 113 by 7D | Phase-5 database owner; Voice | OD-7D-03 | Future governed migration | Blocks AMI-6D-001 dispatch implementation (P9) |
| IO-7D-14 | 6D contract reconciliation for `POST /calls` dispatch key: VDK-01 … VDK-09 (the exact replay-first, capacity-before-transaction ordering of VDK-05; dispatch identity bound to the canonical id; worker-role submission; gates at dispatch; maximum dispatch age) | Voice (6D owner) | IO-7D-13 | Controlled 6D amendment | Blocks AMI-6D-001 dispatch implementation (P9) |
| IO-7D-15 | Voice command-recovery capability contract and reconciler (§35.5): for each supported telephony adapter, declare and contract-test CAP-A / CAP-B / CAP-C for `hangup`, `transfer`, `hold` and `resume` before the command is enabled (VCC-01 … VCC-03); no adapter, Exotel included, is assumed capable; governed 4B / 6D port amendment for any CAP-B evidence operation (the frozen `TelephonyPort` has none); the evidence-based reconciler of §35.5.2; grace and look-back values (reconciliation grace shorter than the hold timeout; look-back covering the maximum ring duration) | Voice (6D / 4B owner); 7K schedule | OD-7D-03 | Controlled 6D / 4B amendment + adapter onboarding | Blocks enabling each command for each adapter and AMI-6D-004 … 007 recovery implementation (P9) |
| IO-7D-16 | OD-7D-02: implement same-transaction audit in every producer of the 84 routes and worker-origin mandatory audit; governed documentation alignment of 5J §14.5, AIR §18.1 and owner audit columns | Each owning domain; 5J / AIR owners; 7I | OD-7D-02 | Owner phases P8 – P20 | Blocks production emission of those routes |
| IO-7D-17 | Owner reconcilers and CAS-guarded workers for PCI-13, PCI-15 … PCI-18, PCI-20, PCI-22, PCI-25, PCI-28, PCI-32 (REC-01 … REC-05) | Each owning domain; 7K schedule | — | Owner phases | Blocks the owning flow's production readiness |
| IO-7D-18 | Telemetry instrumentation OBS-7D-01 … OBS-7D-17 with 7J names | Platform; 7J | 7J | P21 | Non-blocking for 7D |
| IO-7D-19 | Integration tests: disjoint claims under concurrency, CAS misses, lease expiry, partial batches, deferral never producing `FAILED`, lossless materialization | Platform | IO-7D-02 | P7 | Blocks relay go-live |
| IO-7D-20 | Chaos / failure tests for F7D-01 … F7D-31 and CRS-01 … CRS-10 (Redis kill, DB kill, SIGKILL at each crash point, pause beyond lease) | Platform; 7K | IO-7D-19 | P7 / P23 | Blocks relay go-live |
| IO-7D-21 | Class-D publisher for the 4 SIGNAL pairs (CLD-01 … CLD-11) | Voice / Tools; Platform | IO-7C-08 | P9 | Non-blocking for 7D |
| IO-7D-22 | 7E stream-router integration: route function over the 107 pairs, error-classification table, and the durable-acceptance mechanism that alone permits `CONFIRMED` (TPT-02, HO-7E-02 … HO-7E-06) | 7E | 7E | P7 | Blocks relay go-live |

IO count: **22**.

---

## 47. Deferred Items

Each item is routed to an owner. None leaves durability behaviour open to interpretation: every item below is either a numeric value whose change cannot affect correctness, or a design that belongs to another owner under a 7D contract already stated.

| ID | Item | Owner | Why safe to defer |
|---|---|---|---|
| DEF-7D-01 | Stream names, layout, groups, MAXLEN, TTL, sharding, sizing | 7E | 7D fixes the port contract (§21) |
| DEF-7D-02 | Final relay retry delays; `FAILED` disposition; replay tooling | 7G | Current behaviour is the executed default; `FAILED` is retained (CLN-04) |
| DEF-7D-03 | Metric names, SLOs, alerts, dashboards | 7J | Emission points fixed (§41) |
| DEF-7D-04 | Idle delay, probe backoff, safety margin values | 7J / 7K | Affect latency only (POL-06, LSE-03) |
| DEF-7D-05 | Replica count, autoscaling, catch-up rate, regional topology | 7K | Correctness is replica-count-independent (SCL-01) |
| DEF-7D-06 | Reconciler schedules and staleness thresholds | 7K | Affect duplicate volume only (PCW-08) |
| DEF-7D-07 | Field classification, redaction, organization-scope log form | 7I | Payload logging is off (SEC-7D-02) |
| DEF-7D-08 | SIGNAL bindings for DS-01 … DS-16, DS-18 | 7B / 7C | No consumer exists (CLD-09) |
| DEF-7D-09 | Automated cleanup under a narrower role | Phase-5 owner / 7K | Operator procedure works under existing grants (CLN-07) |

---

## 48. Conflict Register

| CNF | Sources | Conflict | Resolution | Severity |
|---|---|---|---|---|
| CNF-7D-01 | 7A §13 vs 7A §29, DD-17; 7B §33.1 | "Relay metrics names" deferred to 7D vs names deferred to 7J | By concern: 7D emission points, 7J names (§41.1) | Minor |
| CNF-7D-02 | 6K L2518; 6C L257; 3F; 7A §13; AIR §32 | Relay topology described as Celery pool / 3A worker vs delegated to Phase 7 | OD-7D-01 = A | Resolved by OD |
| CNF-7D-03 | AIR §12.5 (AMI-6D-001) vs 6D §28.10a L1428 | AIR cites a dispatch reconciler for `POST /calls`; 6D limits the protocol to the campaign caller | Owner document governs; gap closed by OD-7D-03 = B | Resolved by OD |
| CNF-7D-04 | 5J §14.5; AIR §18.1 vs 7A AUD-04a | Async audit "retried; not best-effort" vs pre-enqueue loss | OD-7D-02 = A | Resolved by OD |
| CNF-7D-05 | `077` L127 vs `077` L233–L236; 7B TSK-17 | DELETE "manual/emergency intervention only" vs periodic cleanup by "whichever operational process" | Operator-invoked periodic cleanup under the existing grant (CLN-07); automation deferred (Minor-7D-01) | Minor |
| CNF-7D-06 | AIR §12.5 (AMI-6F-005) vs 6F §27 L903 | AIR lists a Celery ingestion/index job for KB archive; 6F lists only async audit | Owner document governs; PCI-14 | Minor |
| CNF-7D-07 | 7C PV-07 vs the requirement that the relay never emits `tool_definition.*` | Relay may not validate, yet must not emit a family identifier | Relay never synthesizes `event_type`; producer validation rejects the literal; exact-type routing makes such a row non-publishable and non-terminal (MAN-03, MAN-04) | Minor (no contradiction) |
| CNF-7D-08 | 6F §23.4; 6J §42.1, §42.3 vs 7A CEL-08 | Owner-designated best-effort cleanup steps have no reconciliation source | Frozen owner classification stands; residual routed to 7I (Minor-7D-03) | Minor |
| CNF-7D-09 | 6D L625 | Describes an "outbox-publisher's consumer-group mechanism"; the relay publishes to streams and is not a consumer-group member | Wording only; routed to 7E | Minor |

CNF count: **9**. None was silently resolved; the three that materially affected durability, compliance or lifecycle became owner decisions.

---

## 49. Findings

### 49.1 Severity definitions

| Severity | Definition (examples) |
|---|---|
| P0 | Violates a frozen invariant outright: a second outbox; modifying a frozen migration or document; creating migration 113; publishing A/B/C before commit; Redis inside a producer transaction; direct A/B/C Redis publication; claiming exactly-once; silently dropping committed events; starting 7E |
| P1 | Can lose a committed fact or corrupt correctness: a crash window that loses a row; partial-batch handling that marks unpublished rows published; a Redis outage that burns rows to terminal `FAILED`; an unrecovered mandatory pre-enqueue gap; inability to publish compatible backlog; claim / CAS behaviour contradicting the migration; cleanup that deletes publishable rows; ambiguous tenancy or residency; silently choosing an unresolved owner tradeoff |
| Minor | Naming, non-binding operational refinement, benchmark tuning, documentation clarity that does not affect correctness |

### 49.2 P1 findings raised and resolved during authoring

| ID | Finding | Resolution | Status |
|---|---|---|---|
| P1-7D-01 | Relay topology was unsettled with conflicting source wording (CNF-7D-02); choosing silently would take an owner tradeoff | OD-7D-01 = A | RESOLVED |
| P1-7D-02 | Mandatory async audit had an unrecoverable pre-enqueue window with no durable reconstruction source | OD-7D-02 = A; §36 | RESOLVED |
| P1-7D-03 | Voice call commands had an unrecovered pre-dispatch window; AIR's cited reconciler does not apply to `POST /calls` | OD-7D-03 = B; §35.4, §35.5; IO-7D-13 … IO-7D-15 | RESOLVED (design); implementation dependency recorded |
| P1-7D-04 | `attempt_count` counts claims (PHY-01): calling `fn_mark_outbox_failed` for infrastructure failures would burn rows to terminal `FAILED` during a Redis outage | Outcome classes, default-to-non-terminal, DSP-03, availability gate | RESOLVED |
| P1-7D-05 | Lease is not stored on the row (PHY-04): relays with different leases would reclaim each other's work early | LSE-05 fleet-uniform lease | RESOLVED (duplicates only, never loss) |
| P1-7D-06 | A transport that loses acknowledged entries on failover could leave a `PUBLISHED` row undelivered | Superseded and strengthened by P1-7D-R01: `CONFIRMED` requires the 7E durable-acceptance property (TPT-02, HO-7E-03); replay of retained `PUBLISHED` rows is disaster / repair only (CLN-08) | RESOLVED |

### 49.3 Minor findings

| ID | Finding | Disposition |
|---|---|---|
| Minor-7D-01 | Routine cleanup has no least-privilege automated role (CNF-7D-05) | CLN-07 operator procedure; automation via a future governed change (DEF-7D-09) |
| Minor-7D-02 | DS-01 … DS-16 and DS-18 have no SIGNAL binding | CLD-09; 7B / 7C when a consumer is catalogued |
| Minor-7D-03 | Owner-designated best-effort steps (6F S3 deletion with reference erased; 6J secret revocation and purge) have no reconciliation source | Recorded; 7I assesses residual (HO-7I-04) |
| Minor-7D-04 | 6K L2518 "Celery worker pool" wording is superseded for topology by OD-7D-01 | Documentary reconciliation by the 6K owner |
| Minor-7D-05 | AIR §12.5 citations for AMI-6D-001 and AMI-6F-005 | AIR controlled amendment |
| Minor-7D-06 | 6D L625 consumer-group wording (CNF-7D-09) | 7E |
| Minor-7D-07 | 7A §13 / §29 metric-name wording (CNF-7D-01) | Resolved by concern |
| Minor-7D-08 | Idle delay, probe backoff and safety margin values unset | IO-7D-09 |
| Minor-7D-09 | A `CANCELLED`-from-`RINGING` call whose provider leg still rings is terminal, so 6K §54.5 rule 8's drift clause (non-terminal sessions) does not cover it; its capacity was released by the frozen terminal transition | §35.5.2 ends the physical leg on evidence and records the divergence (OBS-7D-18); documentary note for the 6K / 6D owners |

### 49.4 Independent freeze-gate review findings (remediated 2026-10-05)

| ID | Finding | Resolution | Status |
|---|---|---|---|
| P1-7D-R01 | Transport `CONFIRMED` boundary insufficient and internally contradictory: TPT-02 treated a Redis `XADD` entry ID as `CONFIRMED`, while HO-7E-03 let 7E leave the acceptance point open or declare a residual loss window | TPT-02 now requires the 7E durable-acceptance property; §22.2, PRB-05, HO-7E-03 (no residual-loss option on the durable path), F7D-21, CLN-08, HO-7G-03, IO-7D-22, ADR-7D-19; G-58, G-59 | RESOLVED |
| P1-7D-R02 | DPC-07 allowed an old relay to publish new rows without populated correlation / causation values, contrary to 7C CC-03 | DPC-07 staged rollout (Stages 1–5), MAT-10 per-field presence (no relay omits a present value), IO-7D-12, §7.3, ADR-7D-20; G-60, G-61 | RESOLVED |
| P1-7D-R03 | VDK-05 allowed an HTTP replay of `POST /calls` to acquire provisional capacity before discovering the existing session, contrary to 6D §42.2 (a replay could return 429) | VDK-02, VDK-05 exact eight-step ordering, VDK-09, IO-7D-13, IO-7D-14, F7D-27, F7D-28, ADR-7D-15; G-62 … G-64 | RESOLVED |
| P1-7D-R04 | Mandatory Voice hangup / control recovery was incomplete for adapters whose commands are not proven idempotent (`WRAP_UP` stranding; `RINGING → CANCELLED` physical divergence) | §35.5 adapter capability contract VCC-01 … VCC-05, evidence-based per-command resolution, VSC-01 … VSC-07, IO-7D-15, F7D-29 … F7D-31, OBS-7D-18, ADR-7D-21; G-65 … G-68. No OD-7D-04 was required: the capability contract gates enablement, no path completes a session without provider evidence, and provider unavailability follows frozen 7A FM-09 with the 6K §54.5 rule 8 conservative-hold precedent, so no new owner tradeoff is taken | RESOLVED |

Re-check of P1-7D-04 (retry budget): the safe property is unchanged; §24.1 now states explicitly that `attempt_count` counts claims, that `max_attempts` is not a pure count of row-specific failures, and that terminal disposition policy is 7G's (HO-7G-05).

Totals: **P0 = 0. P1 = 0 open (10 resolved: P1-7D-01 … P1-7D-06 and P1-7D-R01 … P1-7D-R04). Minor = 9.**

---

## 50. Validation Results

### 50.1 Validator

A scratch semantic validator was built **outside the repository** (session scratchpad; not added to git). It checks semantics, not only headings: frozen hashes and line counts of 7A / 7B / 7C and the 20 Phase-6 documents; 112 SQL / 112 Alembic, root, sole head, linear chain, no 113; no 7E file; only the 7D file changed; the physical facts quoted in §8 against the text of `077_5J1.sql` (defaults 50 / 300 / 10, the 30-second backoff, CAS predicates, status set, grants, cleanup predicates); and 80+ semantic assertions over this document's rules (single outbox, producer atomicity, claim / publish separation, at-least-once, no exactly-once claim, deferral never terminal, gate behaviour, partial batch, old backlog, Class-D separation, counts 105 / 107 / 4 / 0, inventory and recovery coverage, owner decisions closed, findings, readiness line).

| Run | Result |
|---|---|
| Clean run against this document | PASS — 0 failures |
| Checks executed | 213 (114 required normative statements, 46 negation-aware affirmative-violation scans, 13 forbidden patterns, 40 structural / physical / repository checks). Rebuilt and rerun after the 2026-10-05 remediation; the earlier 179-check result is SUPERSEDED |

### 50.2 Adversarial mutation harness

| Measure | Value |
|---|---|
| Mutations | 128 |
| Detected (validator FAIL) | 128 |
| Missed | 0 |
| Harness errors | 0 |
| No-op mutations (mutation did not change the document) | 0 |

The catalogue covers the 80 required mutation families (outbox replacement, per-context outbox, migration 113, publish-before-commit, Redis in producer transaction, direct A/B/C publish, raw claim SQL, SKIP LOCKED removal, transaction held during publish, exactly-once claim, identity / version / tenant / payload rewrites, backlog dropping, whole-batch marking, unknown-as-success, unknown-as-drop, claim loss, lease removal, leader election, distributed lock, premature mark, DB-failure loss, retry-budget burn, outage blocking commits, FAILED deletion, cleanup of PENDING / CLAIMED, retention conflation, Redis as truth, stream ID as event_id, payload-derived tenant, payload logging, audio / media on the bus, synchronous consumer waits, Billing calculation, upcasting, backlog rejection, EV-014 wildcard / member changes, count changes, Class-D outboxing / Billing / durability, one-shot campaign / integration / ingestion / audit dispatch, Celery-retry claims, invented task-outbox, stream names / groups / DLQ / inbox design, 7E start, frozen-file edits, global relay, INDIA_ENTERPRISE locality, FAILED storm, per-row status loss, shutdown discarding claims, process-clock lease, invented renewal SQL, 7J names / SLOs, invented polling numbers, changed defaults, open P0 / P1 / owner decisions / checkpoint while READY, validator in repo, FROZEN status) plus 7D-specific additions (auto-redial of SUBMITTING, reissue of non-idempotent commands, fingerprint removal, same-transaction audit reverted, lease non-uniformity, deferral calling mark-failed at budget). The remediation added M101 … M128: `XADD` entry ID alone treated as `CONFIRMED`; a 7E residual-loss window on the durable path; a `PUBLISHED` row lost in normal failover; an old relay stripping populated `correlation_id` or `causation_id`; producer population before every relay understands the columns; a historical row given fabricated values; an HTTP replay acquiring capacity again or returning 429; a dispatch row bound to an id other than the canonical `call_session_id`; capacity acquired before replay resolution or a transaction begun before admission; `WRAP_UP` left stranded; no cancellation contract for a ringing leg; alert-only recovery; `COMPLETED` synthesized from elapsed time; capacity released while the provider call is active; a command enabled without a declared capability; Exotel assumed idempotent; a P1 reopened while READY; failed durability confirmation treated as `CONFIRMED`; Stage 3 verification removed; `max_attempts` mis-described; elapsed time treated as evidence; and hidden or removed remediation gates.

---

## 51. Freeze Gates

| Gate | Check | Result | Evidence |
|---|---|---|---|
| G-01 | 7A hash exact | PASS | §6 |
| G-02 | 7B hash exact | PASS | §6 |
| G-03 | 7C hash exact | PASS | §6 |
| G-04 | Phase-6 frozen files unchanged | PASS | §6 (20 / 20) |
| G-05 | 112 SQL | PASS | §6 |
| G-06 | 112 Alembic | PASS | §6 |
| G-07 | Root `001_5B` | PASS | §6 |
| G-08 | Head `112_5H5` | PASS | §6 |
| G-09 | One linear chain | PASS | §6 |
| G-10 | No migration 113 | PASS | §6 |
| G-11 | No 7E | PASS | §6, §50 |
| G-12 | Only 7D changed / new | PASS | §1, §50 |
| G-13 | Single outbox preserved | PASS | §9 |
| G-14 | Outbox physical facts match migration | PASS | §8 (validator cross-check) |
| G-15 | Claim function contract exact | PASS | §8.5, §16 |
| G-16 | Mark-published contract exact | PASS | §8.5, DSP-01, DSP-02 |
| G-17 | Mark-failed contract exact | PASS | §8.5, DSP-03 … DSP-05 |
| G-18 | Producer atomicity preserved | PASS | PTX-01 |
| G-19 | No external I/O in producer transaction | PASS | PTX-02 |
| G-20 | Claim transaction short | PASS | CLM-02 |
| G-21 | Redis publish outside DB transaction | PASS | CLM-03, LOOP-01 |
| G-22 | Mark-progress transaction separate | PASS | LOOP-02, DSP-07 |
| G-23 | At-least-once only | PASS | ADR-7D-06, §26 |
| G-24 | Duplicate-over-loss preserved | PASS | LSE-09, PRB-03 |
| G-25 | Expired claim recovery deterministic | PASS | §17, CRS matrix |
| G-26 | Multiple relays safe | PASS | §16.3, §29 |
| G-27 | No leader required | PASS | TOP-03, §16.4 |
| G-28 | Partial-batch behaviour deterministic | PASS | §23 |
| G-29 | Unknown publish outcome deterministic | PASS | AMB-01, DSP-03 |
| G-30 | Redis outage does not lose events | PASS | §25, F7D-15 |
| G-31 | Redis outage does not burn all rows terminal | PASS | §24.1, DSP-03, GATE-03 |
| G-32 | Old backlog publishable | PASS | §30 |
| G-33 | Envelope immutable | PASS | MAT-01 … MAT-07 |
| G-34 | Event identity stable | PASS | MAT-02, RID-05 |
| G-35 | Tenant preserved | PASS | §38 |
| G-36 | 105 semantic durable bindings preserved | PASS | MAN-01 |
| G-37 | 107 durable exact manifest pairs preserved | PASS | MAN-01, MAN-02 |
| G-38 | 4 SIGNAL pairs preserved | PASS | MAN-01, CLD-07 |
| G-39 | V2 count zero | PASS | MAN-01 |
| G-40 | Class D remains non-durable | PASS | §32 |
| G-41 | Mandatory post-commit inventory exhaustive | PASS | §34 (40 flows; AIR §12.5 29 / 29, AIR §18.1 84 / 84, 7B TSK / PRD rows) |
| G-42 | Each mandatory flow has a recovery mechanism or blocking finding | PASS | §35 (29 / 29; in-call commands under VSC-07) |
| G-43 | Async-audit pre-enqueue gap addressed | PASS | §36, OD-7D-02 |
| G-44 | Cleanup safe | PASS | §31 |
| G-45 | Region / residency boundary preserved | PASS | §39 |
| G-46 | 7E boundary respected | PASS | §4, §21, §43.1 |
| G-47 | 7F boundary respected | PASS | §11, §43.2 |
| G-48 | 7G boundary respected | PASS | DSP-04, DSP-09, §43.3 |
| G-49 | Observability handoff deterministic | PASS | §41, §43.5 |
| G-50 | Implementation obligations complete | PASS | §46 (22) |
| G-51 | Current owner decisions = 0 | PASS | §45.4 |
| G-52 | P0 = 0 | PASS | §49 |
| G-53 | P1 = 0 | PASS | §49 |
| G-54 | Adversarial validator clean | PASS | §50.1 |
| G-55 | All mutations detected | PASS | §50.2 |
| G-56 | No checkpoint marker | PASS | whole document |
| G-57 | Exact readiness line present | PASS | §52 |
| G-58 | `CONFIRMED` requires the 7E durable acceptance property | PASS | TPT-02, §22.2, PRB-05 |
| G-59 | No residual-loss option on the normal durable path | PASS | HO-7E-03, F7D-21, CLN-08 |
| G-60 | OD-7C-04 staged relay rollout is compatible with CC-03 | PASS | DPC-07, IO-7D-12 |
| G-61 | New rows never lose populated correlation / causation at the relay | PASS | MAT-10 |
| G-62 | HTTP replay resolves before capacity acquisition | PASS | VDK-05 steps 1–2, F7D-27 |
| G-63 | No provisional capacity for an HTTP replay | PASS | VDK-05 step 2 |
| G-64 | Canonical `call_session_id` used for capacity and dispatch reservation | PASS | VDK-05 steps 3–6, VDK-09, IO-7D-13 |
| G-65 | `WRAP_UP` stale-command recovery deterministic | PASS | §35.5.2, VSC-06, VSC-07, F7D-29 |
| G-66 | `RINGING` cancellation provider divergence deterministic | PASS | §35.5.2, F7D-30 |
| G-67 | Adapter command-recovery capability contract deterministic | PASS | VCC-01 … VCC-05, IO-7D-15 |
| G-68 | All mandatory Voice command paths recovered or owner-blocked | PASS | VSC-07, PCI-07 … PCI-11 |

Gates: **68**. PASS: **68**. FAIL: **0**.

---

## 52. Freeze-Gate Status

| Item | Value |
|---|---|
| P0 findings | 0 |
| P1 findings | 0 open (P1-7D-01 … P1-7D-06 and P1-7D-R01 … P1-7D-R04 resolved) |
| Minor findings | 9 (Minor-7D-01 … Minor-7D-09) |
| Current owner decisions | 0 (OD-7D-01 = A, OD-7D-02 = A, OD-7D-03 = B, all DECIDED) |
| ADRs | 21 |
| Implementation obligations | 22 |
| Conflicts recorded | 9 |
| Frozen baselines | 7A / 7B / 7C hashes exact; 20 Phase-6 hashes exact; 112 migrations, head `112_5H5`, no 113 |
| Counts | 105 semantic durable bindings; 107 exact durable V1 pairs; 4 exact SIGNAL V1 pairs; V2 = 0 |
| Next step | Independent review of 7D. 7E is not started by this document. This document is not frozen. |

**7D TRANSACTIONAL OUTBOX ARCHITECTURE = READY FOR INDEPENDENT REVIEW**
