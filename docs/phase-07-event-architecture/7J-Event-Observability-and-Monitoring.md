# Phase 7J — Event Observability & Monitoring — AI Voice Agent Platform

Telemetry, distributed tracing, service-level indicators, alerting, security monitoring and operational diagnostics for the frozen event architecture.

## 1. Document Authority and Freeze Baseline

| Item | Value |
|---|---|
| Phase | 7J — Event Observability & Monitoring |
| File | `docs/phase-07-event-architecture/7J-Event-Observability-and-Monitoring.md` |
| Kind | Architecture specification. No code, no migration, no runtime service, no configuration file is created by this phase |
| Depends on | Frozen Phase 1 – 6, frozen 7A – 7I, frozen D0, migrations `001` – `112` |
| Does not begin | 7K, 7L, D1, Phase 8 |
| Status of this document | Revised after the first to sixth independent freeze-gate reviews (§1.1a, §34.4 – §34.9). For independent re-review. Not approved, not frozen (§35.6) |
| Owner decisions | OD-7J-01 … OD-7J-15, all approved by the platform owner on 2026-10-12 (§29) |

### 1.1 Frozen baseline verified at start (read-only commands, executed)

| Check | Result |
|---|---|
| 7I file identity | `7I-Event-Security-and-Compliance.md`: 4,043 LF lines, no CR byte, SHA-256 `01a2ac34f5aef77f671a8c538207da7ebb5b61f09a4d527d931bf99fdac36d91`. Matches the approved identity |
| 7I owner decisions present | OD-7I-01 … OD-7I-31 (§25 of 7I) |
| 7I handoffs to 7J | HE-7J-7I-01 … HE-7J-7I-16 (7I §27.1). All sixteen are present; none is taken from an earlier draft |
| Working tree | Clean at commit `ed3f34a` before authoring |
| SQL migrations | 112 files under `docs/phase-05-database-design/5K/migrations`, `001_5B.sql` … `112_5H5.sql` |
| Alembic revisions | 112 files; exactly one with `down_revision = None` (`001_5B`); exactly one revision that no other names as its parent (`112_5H5`); no parent named twice |
| Migration 113 | Absent |

SHA-256 of the nine frozen Phase 7 documents, in both representations (re-verified after authoring, §35.5). **Raw** is the hash of the file's bytes as they are on disk in the working tree. **LF-normalized** is the hash after removing every carriage return, which is the content git stores (`git ls-files --eol` reports `i/lf` for all nine). 7A, 7B and 7C are checked out with CRLF line endings in this working tree (`w/crlf`), so their two hashes differ; 7D – 7I are LF on disk and their two hashes are equal. The first version of this document printed the raw column only and did not say so (Minor-7J-R01). The LF-normalized value is the baseline to compare against across platforms. No frozen file was changed to normalize it.

| Document | Lines | On disk | SHA-256, LF-normalized (baseline) | SHA-256, raw bytes on disk |
|---|---:|---|---|---|
| 7A | 1,086 | CRLF | `699108f956bbd0e09ca7ab38fa4846498edf7e461713e5a44add886733d79712` | `936bbfe118bfea9216d8fd4fdd2bfec29ef618269bb0d495c521f7afe64c60b4` |
| 7B | 2,207 | CRLF | `1bd7a054263b142c3f8c3f79d531906305ccaf0dec225e4d3865056605715e6c` | `7bb8f8f365e11786cdec6dbe22a2b6f7f3d8f43f46e859f74b1a552b9b017430` |
| 7C | 3,275 | CRLF | `e514e3c4a889775fbc8e9baba3a9ad0558b5228465f240f425d7c762f1d200a0` | `258b2266a76d008c697cd2acdf98f4e2ddc138b749c52478dd1c1e8d0dab77e5` |
| 7D | 1,572 | LF | `2714a3eec6eb7c95be50c3b11c2e80c66f3f93a413ebcecfa46c5c79bf9e4de5` | same |
| 7E | 1,875 | LF | `671fcebe17bb08da4783c89323235f2bc7819fff3155d0a2d46578c6819a9c93` | same |
| 7F | 2,076 | LF | `0f9db999f059486b033f06b40358a2f94978281e026e3e92ba3575adbd1185b1` | same |
| 7G | 1,920 | LF | `0213cc09f2e6a1b13be331575e3c5878ab320ab357d752cbcc27f252cd21f0e4` | same |
| 7H | 2,729 | LF | `219da2deaa3a5740b975e9b6566b45a996065a1136e1bbf30959242c47843795` | same |
| 7I | 4,043 | LF | `01a2ac34f5aef77f671a8c538207da7ebb5b61f09a4d527d931bf99fdac36d91` | same |

### 1.1a Revision history of this document

| Version | Identity | Outcome |
|---|---|---|
| First submission | 2,744 LF lines; SHA-256 `6ae406984bf2dcd1cb2e46fad8bdfe642abc4f43ce0bda347520a69b1167ed71` | Independent freeze-gate review: **not approved**. P0 0; P1 4 (P1-7J-R01 … R04); Minor 2 |
| Second submission | 3,321 LF lines; SHA-256 `da25445de3b6223461f5248c23e0044c0ba27279b3ee60cc21a7b9fad70bf030` | Second independent review: the four P1 and two Minor findings substantially resolved; **not approved**. P0 0; P1 3 (P1-7J-R05 … R07); new Minor 0 |
| Third submission | 3,485 LF lines; SHA-256 `a1af32699f20eda52a12001356f71445073f249cac1cdbfa80ae3568577e6a6d` | Third independent review: findings R05 … R07 substantially resolved; **not approved**. P0 0; P1 3 (P1-7J-R08 … R10); new Minor 0 |
| Fourth submission | 3,663 LF lines; SHA-256 `36d3a4f641870fc2f08294993be89eb3664dcb9a47ce7dcdf84c7ca2a236d635` | Fourth independent review: R08 … R10 substantially resolved; **not approved**. P0 0; P1 2 (P1-7J-R11, R12); new Minor 0; two owner confirmations required, which the owner gave together with a third decision (OD-7J-11 … OD-7J-13) |
| Fifth submission | 3,829 LF lines; SHA-256 `7661317a204005f877fc355469e0ef13a1c0c509f956e65685eb8ad48795143d` | Fifth independent review: R11 and R12 substantially resolved; **not approved**. P0 0; P1 1 (P1-7J-R13); Minor 2 (Minor-7J-R03, R04); one owner-policy clarification required, which the owner gave together with a retention decision (OD-7J-14, OD-7J-15) |
| Sixth submission | 3,969 LF lines; SHA-256 `a0ef8af9ce4fb5233013335c2da72c5dd8fa83715e97db01ca98f98c26498e27` | Sixth independent review: R13 and both Minor findings closed in design; **not approved**. P0 0; P1 1 (P1-7J-R14); new Minor 0 |
| This version | Reported with the completion report (a file cannot contain its own hash) | Remediation of that P1 finding (§34.9). For independent re-review |

### 1.2 Provenance of each statement

| Tag | Meaning |
|---|---|
| **[FROZEN]** | Stated by a frozen source, cited. 7J restates it and does not change it |
| **[OD-7J-nn]** | Decided by the platform owner in this phase (§29) |
| **[7J]** | A design rule of this document, consistent with the frozen sources |
| **[CAND]** | A candidate numeric value. Not a commitment. It is provisional until 7K measures it and the owner approves it (OD-7J-01) |
| **[7K]** / **[7L]** | Belongs to that phase; 7J states only the constraint |

### 1.3 What is designed versus what exists

| Thing | State today |
|---|---|
| Structured logging and redaction (`backend/voice_agent/platform/infrastructure/observability/logging.py`, `redaction.py`) | **EXISTS** (frozen D0). Not modified |
| OpenTelemetry tracing, Prometheus metrics, collectors, dashboards, alert rules | **DESIGNED** in 3E §14 and 3F §17 – §19. No metrics or tracing module exists in `backend/`, and `infra/` holds only Docker files |
| The relay, the stream gateway, the consumers, the recovery ledger, the dispatcher, the erasure journal, the subject index, the content access guard | **DESIGNED** in 7D – 7I. None exists. Each is behind its frozen activation gate |
| Every metric, span, log field, alert, dashboard, principal, function and gate named in this document | **DESIGNED HERE.** None exists. Nothing in this document reports a runtime observation |

A metric in this document is a contract for a future emission. Where its source component is itself only designed, the row names the gate that must open first (§32).

---

## 2. Scope, Goals and Non-Goals

### 2.1 In scope

The observability model of the pipeline: domain transaction → transactional outbox → relay → Redis Streams → stream gateway and consumer-group dispatch → handler → domain guard → completion evidence → acknowledgement → retry, parking and recovery → webhook, callback and plugin execution → audit, retention and privacy lifecycle. For that pipeline: the telemetry architecture and its trust boundaries; a named metric catalogue with a label allow-list and a cardinality budget; service-level indicators with exact formulas; candidate objectives; the trace and log contracts; the boundary between telemetry and immutable audit; security and privacy signals; alerts, dashboards and runbooks; retention and residency of telemetry; the behaviour of the monitoring system when it fails; verification requirements; implementation requirements and activation gates; handoffs to 7K and 7L.

### 2.2 Goals

| ID | Goal |
|---|---|
| G-01 | An operator can tell, for each stage, whether it is healthy, delayed, failed, intentionally held, or **unknown because the measurement is unavailable** |
| G-02 | Every figure about an obligation comes from the store that is authoritative for that obligation |
| G-03 | No telemetry surface discloses one tenant's data to another tenant, and no metric carries a tenant or entity identifier |
| G-04 | Telemetry never decides, completes, acknowledges, resolves or erases anything |
| G-05 | A monitoring failure delays an operator's knowledge. It never delays a voice call, a commit, a publication or an acknowledgement |

### 2.3 Non-goals

| Not done here | Where it belongs |
|---|---|
| Any change to an event, an envelope, a stream key, a group, a retry rule, a retention period or a security rule of 7A – 7I | Frozen; unchanged |
| Tenant-facing monitoring routes, status pages or exports | No frozen API contract exists; none is created (§22.4) |
| Product analytics (6L projections, tenant dashboards) | 6L. A 6L projection is a consumer whose health 7J observes; its content is not 7J's |
| Capacity, sizing, instance counts, benchmark results, final thresholds | 7K |
| Consolidation of errata into frozen documents | 7L and the owning phases |
| A new observability product, vendor or external telemetry destination | None is introduced (§5.6) |
| Observability of the owning contexts' business logic beyond what the event pipeline needs | The owning contexts |

---

## 3. Source-Contract Traceability

### 3.1 Sources read for this document

| Source | Sections used | What 7J takes from it |
|---|---|---|
| SRS | NFR-PERF-001, -002; NFR-AVAIL-001; NFR-SEC-005; NFR-OBS-001, -002 | The only approved numeric performance requirements; the obligation to emit logs, metrics, traces and audit |
| 3E | §14.1 – §14.6 | OpenTelemetry SDK, mandatory span attributes, `platform_` metric convention, dashboards as code, alert rules as code, health endpoints |
| 3F | §17 – §20 | Infrastructure metrics; Alertmanager routing; Fluent Bit log pipeline; log retention (§18.3); cluster-wide collector; sampling (§19.2); synthetic monitoring |
| 4G | §12.2 | Indicative lag figures (not objectives; 7A CON-05) |
| 4I | §9.1 | Residency profiles; `LOGS` as a residency scope item |
| Migrations | `001_5B`, `008_5B`, `016_5C`, `025_5D`, `062_5I`, `063_5I`, `072_5J`, `077_5J1` | Role catalogue; grants of `app_readonly`; outbox status vocabulary; outbox grants; audit write path |
| 6A | §25 | Request and correlation identity; sampling; metric naming; the `tenant_id` label (§30, CNF-7J-02) |
| 6J | §44 | Webhook, plugin and integration metric vocabulary; the corrected no-tenant-label rule |
| 7A | §29 (OBS-01 … OBS-08), TEN-05, SEC-01 … SEC-09, CON-05, DD-17 | Per-hop observability duties; tenant-safe observability; lag figures are not objectives |
| 7B | §31.2, §31.7, IO-7B-21 | Observability of conversations stalled before finalization and of corrupt usage state |
| 7C | §16, §17 | `correlation_id` and `causation_id` semantics; no tracing field in the envelope |
| 7D | §41 (OBS-7D-01 … -18, C1, C2), §43.5, GATE-01 … -09, CLD-01 … -07, CLN-01 … -07, PCW-01 … -12 | Relay emission points; gate; Class-D; cleanup; reconcilers |
| 7E | §14, §15, §25 (CL-01 … CL-21), CAP-01 … -07, HP-01 … -07, WAO-01 … -08, TRM-02 … -08, TTL-01 … -03, MEM-01 … -04, §29, §49.4, ENT-01 … -08 | Transport semantics, the closed outcome vocabulary, the group registry, the two-field entry |
| 7F | §36.4, classification C-1 … C-12, XAK-01 … -09 | Consumer signals; the commit and acknowledgement boundaries |
| 7G | §10.1, §14, §22, §24, §30, §42.4, §52.3 | Recovery classes, case states, replay modes, result model |
| 7H | §8 (T-04 … T-11), DSM-01 … DSM-07 (H1 – H7), §9.6, HTP-14, HTP-19, §13.3 Matrix F, MR-7H-02, -03, -06, -07, §19.1 – §19.5, PLG-15 … -18, CBK rules | Delivery states, the claim, admission, abandonment and closure records, the three send states, category codes, failure origins, the never-recorded list, the alert conditions |
| 7I | §9.5 – §9.7, §10.6, §11.5, §14.7 – §14.8, §18.3, §19, §24.2, §27.1 | Gateway, accounting, completion evidence, redaction rules, sealing, content guard, journal, residency, audit kinds, gates, the sixteen handoffs |

### 3.2 Frozen identifiers this document relies on

| Fact | Value | Source |
|---|---|---|
| Durable event types | 107 exact pairs | 7E §14.1 |
| SIGNAL event types | 4 exact pairs | 7D CLD-07 |
| Durable stream families / keys in V1 | 11 / 11 (`P_f = 1`) | 7E §14.1 |
| SIGNAL stream keys in V1 | 1 | 7E §14.1 |
| Durable logical groups / subscriptions | 11 / 18 | 7E §29 |
| SIGNAL groups | 1 | 7E §29.2 |
| Consuming contexts with their own principal | 9 | 7I CTX-01 |
| Public webhook topics | 19 | 7I §11.2 |
| Outbox statuses | `PENDING`, `CLAIMED`, `PUBLISHED`, `FAILED` | `077_5J1` `chk_outbox_status` |
| Relay publish outcome classes | `CONFIRMED`, `ROW_REJECTED`, `TRANSPORT_UNAVAILABLE`, `NOT_ATTEMPTED`, `UNKNOWN`, `RELAY_CAPABILITY` | 7D OBS-7D-05 |
| Consumer classification classes | C-1 … C-12 | 7F §11 |
| Handler outcomes | `DURABLY_COMMITTED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`, `HANDLER_FAILED` | 7F §36.4 |
| Recovery classes | Seven (7G §10.1) | 7G |
| Case states | `OPEN_RETRY`, `HOLD`, `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING`, `RESOLVED` | 7G §24.1 |
| Replay modes | R1 … R6 (R7 is the public webhook replay) | 7G §30 |
| Delivery statuses used in V1 | `PENDING`, `DELIVERING`, `DELIVERED`, `DEAD_LETTER`, `CANCELLED` | 7H §8.1 |
| Delivery failure origins | `RECEIVER`, `DESTINATION`, `PLATFORM`, `TENANT_CONFIGURATION` | 7H HTP-14 |
| Closure send states | `SENT`, `NOT_SENT`, `UNCERTAIN` | 7H DSM-07 H6; T-08 |
| Closure attempt number | Non-NULL exactly when the closure spent the budget; NULL for `RELEASED_ORG_NOT_ACTIVE` (T-09) | 7H DSM-07 H5; MR-7H-06 |
| Delivery row timestamps | `created_at`, `claimed_at`, `completed_at`; **no `occurred_at`** | `063_5I` |
| Callback receipt statuses | `RECEIVED`, `PROCESSING`, `PROCESSED`, `FAILED`, `SKIPPED` | `062_5I` `chk_iwe_status` |
| Subject-index certification states | `FROM_ORIGIN`, `FROM_T0`, `NOT_CERTIFIED` | 7I HLD-24 |

---

## 4. Complete Incoming Handoff Inventory

Status values. **CLOSED**: a specific 7J contract (metric, span, log rule, alert, runbook or test) satisfies the handoff; the contract is enforceable when its source component exists, and the row names it. **BLOCKED**: the 7J contract cannot be completed until a named dependency is decided or built; the row names the owner and the condition that cannot be bypassed.

Security classification of a signal: **AGG** aggregate, safe on general operational dashboards; **RST** restricted internal (carries or implies an internal diagnostic detail; restricted dashboards only); **SEC** security-monitoring record (security role only, §22.2).

### 4.1 From 7A and 7B

| Handoff | Frozen source | Required signal | Emission boundary | Authoritative source | Consumer | Class | 7J rule | Verification | Status |
|---|---|---|---|---|---|---|---|---|---|
| H-7A-01 | 7A DD-17; §29 | Names, cardinality budgets, objectives, alerts for the event chain | Every hop | Per signal, §8 | SRE | AGG | §7 – §11, §23 | VT-7J-01 … -12 | CLOSED |
| H-7A-02 | 7A TEN-05 | Tenant-safe observability; governance of tenant identifiers in metrics | Metric registration | Label allow-list | All | — | LBL-01 … LBL-10: **7J permits no tenant identifier in any metric** | VT-7J-13, -14 | CLOSED |
| H-7A-03 | 7A CON-05 | 4G §12.2 figures are indicative; 7J owns objectives | — | — | Owner | — | SLO-01 … SLO-06; OD-7J-01 | VT-7J-44 | CLOSED |
| H-7A-04 | 7A OBS-01 … OBS-08 | Per-hop identity, correlation, producer context, age, attempts, lag, failure reason, replay visibility | Each hop | Envelope; ledger | SRE | RST | TRC-01 … TRC-15; SP-01 … SP-21; LOG-01 … LOG-16 | VT-7J-20 … -27 | CLOSED |
| H-7A-05 | 7A SEC-01, -04, -07 | No secret, personal data or signed URL in logs, metrics or traces | Emission | — | Security | — | LOG-08 … LOG-14; TRC-10; §13.4 scanner | VT-7J-15 … -19 | CLOSED |
| H-7B-01 | 7B IO-7B-21; §31.2, §31.7 | Conversations stalled before finalization; finalization no-ops; corrupt usage or missing service-end state | Voice finalization worker and reaper | Voice-owned durable accounting state | Voice owner; SRE | AGG | M-146 … M-148; AL-46 | VT-7J-34 | **BLOCKED**: the durable accumulator and finalization guard are migration obligations IO-7B-15 and IO-7B-16 that do not exist. Owner: Voice (6D). The three metrics have no source until they do; the finalization worker may not be activated without them (AG-7J-04) |
| H-7B-02 | 7B Signal Class D; 7D CLD-06 | SIGNAL published and dropped, distinct from durable loss | SIGNAL publisher | Publisher process | SRE | AGG | M-015; SLI exclusions (SLI-R-06) | VT-7J-35 | CLOSED |

### 4.2 From 7D

| Handoff | Frozen source | Required signal | Emission boundary | Authoritative source | Class | 7J rule | Status |
|---|---|---|---|---|---|---|---|
| HO-7J-01 | 7D §43.5 | Emission points OBS-7D-01 … -17 and C1, C2. **§41.2 also defines OBS-7D-18; it is covered** (CNF-7J-01) | See the eighteen rows below | — | — | Rows below | CLOSED |
| HO-7J-02 | 7D §43.5 | Final names, dashboards, objectives, thresholds, budgets | — | — | — | §8, §9, §11, §22, §23 | CLOSED |
| HO-7J-03 | 7D §43.5 | Alerts: gate OPEN duration, oldest-eligible age, `FAILED` rows, `RELAY_CAPABILITY`, dispatch keys `SUBMITTING` / `AMBIGUOUS`, stale command states, reconciler fallbacks | — | — | — | AL-01 … AL-08, AL-44, AL-45 | CLOSED |
| OBS-7D-01 | §41.2 | Eligible backlog (`PENDING` and due, plus expired `CLAIMED`) | Database read by the observer | `audit.domain_event_outbox` | AGG | M-001 | CLOSED |
| OBS-7D-02 | §41.2 | Oldest eligible age | Database read, database clock | Outbox | AGG | M-002; CLK-02 | CLOSED |
| OBS-7D-03 | §41.2 | Claimed count per batch; batch size | After the claim transaction returns | Relay | AGG | M-003 | CLOSED |
| OBS-7D-04 | §41.2 | Expired-claim reclaims | Claim returns a row previously `CLAIMED` | Relay | AGG | M-004 | CLOSED |
| OBS-7D-05 | §41.2 | Publish outcomes by class | After the 7E adapter returns a per-entry outcome | Relay | AGG | M-005 | CLOSED |
| OBS-7D-06 | §41.2 | Gate state and transitions; probe results | Gate transition; probe return | Relay | AGG | M-006, M-007, M-008 | CLOSED |
| OBS-7D-07 | §41.2 | Claim, publish, mark durations | Around each stage, monotonic clock | Relay | AGG | M-009 | CLOSED |
| OBS-7D-08 | §41.2 | Terminal `FAILED` count and current rows | Mark-failed commit; database read | Outbox | AGG | M-010, M-011 | CLOSED |
| OBS-7D-09 | §41.2 | CAS misses on mark-published and mark-failed | Function returns "not changed" | Relay | AGG | M-012 | CLOSED |
| OBS-7D-10 | §41.2 | Repeated identical `ROW_REJECTED` across batches | Batch end (GATE-09) | Relay | AGG | M-013 | CLOSED |
| OBS-7D-11 | §41.2 | `RELAY_CAPABILITY` by sub-cause | Outcome classification | Relay | AGG | M-005 (`outcome`), M-014 | CLOSED |
| OBS-7D-12 | §41.2 | Contract anomalies observed without repair | Materialization | Relay | AGG | M-016 | CLOSED |
| OBS-7D-13 | §41.2 | Publication latency | Database-derived, one clock | Outbox (`published_at − occurred_at`) | AGG | M-017 (accounted, §6.4); CLK-03 | CLOSED |
| OBS-7D-14 | §41.2 | Class-D published and dropped | SIGNAL publisher | Publisher | AGG | M-015 | CLOSED |
| OBS-7D-15 | §41.2 | Cleanup rows deleted by predicate | Cleanup commit | Maintenance | AGG | M-018 | CLOSED |
| OBS-7D-16 | §41.2 | Mandatory-work reconciler: candidates, re-dispatched, fallback-resolved, per flow | Reconciler run | Owner reconcilers | AGG | M-019 | CLOSED |
| OBS-7D-17 | §41.2 | Trace and log correlation fields | Every relay span and log line | Envelope | RST | TRC-05, LOG-03 | CLOSED |
| OBS-7D-18 | §41.2; §35.5 | Voice stale-command reconciliation: evidence obtained or unobtainable, commands issued, `CANCELLED`-but-ringing divergences, sessions held pending evidence | Voice reconciler | Voice owner state | AGG | M-020, M-021; AL-45 | CLOSED |
| OBS-7D-C1 | §41.3 | No raw `event_id`, `call_id`, `contact_id`, payload value or tenant id in a label "unless 7J permits" | Registration | — | — | LBL-01: **7J grants no such permission** | CLOSED |
| OBS-7D-C2 | §41.3 | Bounded labels only | Registration | — | — | LBL-02, §9.1 | CLOSED |

### 4.3 From 7E (§49.4)

| Handoff | Required signal | Emission boundary | Authoritative source | Class | 7J rule | Status |
|---|---|---|---|---|---|---|
| H-7E-01 | Cluster health; shard health; replica availability and lag | Observer poll; relay probe | Redis `CLUSTER INFO`, `CLUSTER SHARDS`, `INFO replication` | AGG | M-030 … M-033 | CLOSED |
| H-7E-02 | `WAITAOF` confirmation latency; shortfalls below `[1, 1]`; timeouts; errors | Adapter, after each `WAITAOF` reply or timeout | Relay adapter | AGG | M-034, M-035 | CLOSED |
| H-7E-03 | Capability-gate failures by check CAP-01 … CAP-07 | Adapter capability evaluation | Adapter | AGG | M-036 | CLOSED |
| H-7E-04 | `XADD` latency; outcome counts by class CL-01 … CL-21 | Adapter, per entry | Adapter | AGG | M-037, M-038 | CLOSED |
| H-7E-05 | Per-key stream length and memory | Observer poll (`XLEN`, `MEMORY USAGE`) | Redis | AGG | M-039, M-040 | CLOSED |
| H-7E-06 | Per-group lag (`lag`, `entries-read`); PEL size; oldest pending age | Observer poll (`XINFO GROUPS`, `XPENDING` summary and one-entry extended form) | Redis | AGG | M-041 … M-044; RDO-01 … RDO-06 | CLOSED |
| H-7E-07 | Safe-trim lag on both sides of `W(K)`; trim counts | Trim worker, in the run that computes `W(K)` | Trim worker | AGG | M-045 … M-047 | CLOSED. Emitted by the trim worker, which already holds the privilege; the observer is not given `XINFO STREAM` (RDO-03) |
| H-7E-08 | Registered-group-missing and unregistered-group anomalies (TRM-03, TRM-04) | Trim worker; observer comparison with the registry | Redis and the 7E registry | AGG | M-048, M-049; AL-12 | CLOSED |
| H-7E-09 | TTL anomalies (TTL-02) | Provisioning; trim worker | Redis | AGG | M-050 | CLOSED |
| H-7E-10 | `MOVED` / `ASK` rate; routing failures (`NONE`) | Adapter | Adapter | AGG | M-051, M-052 | CLOSED |
| H-7E-11 | SIGNAL published and dropped | SIGNAL publisher | Publisher | AGG | M-015 | CLOSED |
| H-7E-12 | Probe results by check HP-01 … HP-07 | Relay `health_probe()` return | Relay | AGG | M-008 | CLOSED |

### 4.4 From 7F (HE-7J-7F-01; §36.4)

| Handoff | Required signal | Emission boundary | Authoritative source | Class | 7J rule | Status |
|---|---|---|---|---|---|---|
| H-7F-01 | Entries read; classification counts C-1 … C-12; known-unsubscribed acknowledgements; held entries by class | After classification, before any handler | Consumer worker | AGG | M-060, M-061, M-062 | CLOSED |
| H-7F-02 | Handler outcomes; duplicate rate; ambiguous-guard and unknown-commit occurrences | After the owner transaction's outcome is known | Consumer worker; owner database | AGG | M-063, M-064, M-065 | CLOSED |
| H-7F-03 | Tenant-mismatch occurrences | Classification D-step that detects it | Consumer worker; the resulting recovery case | SEC | M-066; AL-30 | CLOSED |
| H-7F-04 | `XACK` results, zero results and errors | After the gateway returns the acknowledgement result | Gateway | AGG | M-067 | CLOSED |
| H-7F-05 | Time from delivery to durable commit, and from commit to acknowledgement; in-flight count | Two separate observations (§17.2) | Consumer worker; gateway | AGG | M-068 (receipt to commit), M-085 with M-086 (occurrence to completion), M-069, M-070 | CLOSED |
| H-7F-06 | Unsupported-version alerts (7C UV-08); startup-gate refusals (VER-7F-05); handler-contract admission refusals, revalidation stops, cutover state changes, registrations | Worker start; admission; cutover transition | Handler-contract record | AGG | M-071 … M-074; AL-16 | CLOSED |
| H-7F-07 | Beyond-horizon classifications; retention-barrier waits and retirement runs; draining intervals and their retirement | Owner adapter result; retirement run | Owner evidence stores | AGG | M-075, M-076, M-077 | CLOSED |
| H-7F-08 | Publication-fence establishment and release; size and age of a pre-fence set; abandoned cutovers; publication-admission state; registered publication attempts; quiescence waits | Cutover procedure steps | Handler-contract record | AGG | M-078 … M-081 | CLOSED |
| H-7F-09 | Canonical origin records and classifications made from them; key-onboarding steps; entries held as key-not-onboarded; entries held as `OBLIGATION_RETIRED` | Provenance write; onboarding step; classification C-11, C-12 | Ledger; registry | AGG | M-082, M-083, M-062 (`held_class`) | CLOSED |
| H-7F-10 | SIGNAL entries read, dropped by reason, ingested | SIGNAL consumer | Analytics SIGNAL consumer | AGG | M-084 | CLOSED |

### 4.5 From 7G (HE-7J-7G-01; §52.3)

| Handoff | Required signal | Emission boundary | Authoritative source | Class | 7J rule | Status |
|---|---|---|---|---|---|---|
| H-7G-01 | PEL reclaim attempts and successes; pending age (oldest and distribution); Redis delivery count observed | Sweep run; observer poll | Redis; sweep worker | AGG | M-090, M-091, M-044, M-092 | CLOSED |
| H-7G-02 | Genuine handler failure count per recorded failure and its distribution | The failure-record transaction commits (RTY-04) | Recovery ledger | AGG | M-093 | CLOSED |
| H-7G-03 | Crash-loop suspected; isolation attempts and outcomes | Sweep decision; isolation end | Ledger | AGG | M-094 | CLOSED |
| H-7G-04 | Dependency-gate open and close, with the dependency | Gate transition | Worker | AGG | M-095, M-096 | CLOSED |
| H-7G-05 | Parking created by reason; immediate parking; poison-threshold parking; compatibility holds created, cleared, expired; key-not-onboarded holds; parking commit failure; material-store refusal | Parking transaction commit or failure | Ledger | AGG | M-097, M-098, M-099 | CLOSED |
| H-7G-06 | `XACK` after parking; zero result or error after parking; `ACK_UNCONFIRMED` | After parking commit, acknowledgement result | Gateway; ledger | AGG | M-100 | CLOSED |
| H-7G-07 | Open parked-case count and age; reconciliation-pending count and age by owner | Database read by the observer | Ledger | AGG | M-101, M-102, M-103 | CLOSED |
| H-7G-08 | Publisher `FAILED` by disposition and undispositioned age; redrive requested, succeeded, failed | Database read; redrive operation item | Outbox; ledger | AGG | M-011, M-104, M-105 | CLOSED |
| H-7G-09 | Replay operation lifecycle by mode; outcome classes of §42.4; horizon rejects; missing provenance; missing source; target-blocked; throttling and pause time; cancellation; trim pauses held by operations | Operation and item transitions | Ledger | AGG | M-106 … M-110 | CLOSED |
| H-7G-10 | Group-retirement operations and per-entry dispositions; dangling-PEL anomalies; material digest mismatches; canonical provenance records and retirement runs; ledger cleanup runs | Operation step; material read; cleanup commit | Ledger | AGG / SEC (digest mismatch) | M-111 … M-115; AL-21, AL-22 | CLOSED |

### 4.6 From 7H (HE-7J-7H-01, HE-7J-7H-02; §19.1 – §19.5)

| Handoff | Required signal | Emission boundary | Authoritative source | Class | 7J rule | Status |
|---|---|---|---|---|---|---|
| H-7H-01 | Fan-out: transactions committed, zero-match, duplicate, rows per fan-out, fan-out lag | Fan-out transaction commit | Fan-out consumer; delivery rows | AGG | M-120, M-121, M-122 (accounted) | CLOSED |
| H-7H-02 | Deliveries by status; `PENDING` backlog and oldest due age; held backlog and age by organization status; `DELIVERING` count and oldest age | Database read by the observer | `webhooks.webhook_deliveries` | AGG | M-123 … M-127 | CLOSED |
| H-7H-03 | Attempts by outcome class and category; attempt duration; attempts per delivery at completion; creation-to-terminal time; `Retry-After` observed; next-eligibility distribution | Closure record commit | Dispatcher; closure records | AGG | M-128 … M-132; M-144; M-163; M-165 … M-169 | CLOSED |
| H-7H-04 | Dual-signature attempts; `SECRET_UNAVAILABLE` closures split by secret role; grace-boundary re-checks; admissions, window misses, re-check mismatches, re-admissions, `CONFIG_CHANGED`, hand-off overruns; superseded-revision sends | Admission function; closure record | Dispatcher | **RST** for `secret_role` | M-133 (admissions, re-admissions), M-162 (abandonments), M-134, M-135; AL-26 | CLOSED. `secret_role` exists only on the restricted series M-134 and never on a tenant surface (7I TVF-02, TVF-05) |
| H-7H-05 | Admission lock waits and timeouts on the endpoint row; stale-claim releases; fence mismatches; uncounted releases; cancellations by reason; dead letters | Admission; sweep; closure | Dispatcher; sweeper | AGG | M-136 … M-139; M-161 (claims); M-164 (uncounted releases); M-128 `send_state` including `UNCERTAIN` | CLOSED |
| H-7H-06 | Replays requested, refused by reason, completed; lineage depth; test deliveries | Replay route transaction | API; delivery rows | AGG | M-140, M-141 | CLOSED |
| H-7H-07 | Egress rejections by rule; DNS, TLS, connect failure rates; dependency-gate open time; purge runs | Egress adapter; dispatcher | Dispatcher | AGG; rule code RST | M-142, M-128 (`category`), M-096, M-143 | CLOSED |
| H-7H-08 | Inbound receipts by provider and status; duplicates; verification failures; resolution failures; stale-receipt re-dispatches; oldest non-terminal receipt age; processing attempts; extraction failures | Receipt commit; sweep | Receipt rows | AGG | M-149 … M-155; AL-28, AL-29 | CLOSED |
| H-7H-09 | Plugin executions by plugin, capability and status; scope denials; rate-limit refusals; limiter-unavailable refusals; breaker open time; timeouts | `plugin_executions` row write; breaker transition | `plugins.plugin_executions` | AGG | M-156 … M-160 | CLOSED, with the `plugin_key` bound of LBL-08 |
| H-7H-10 | Alert conditions of §19.5; identifier table §19.1; trace chain §19.2; never-recorded list §19.4 | — | — | — | AL-23 … AL-29; TRC-12 … TRC-15; SP-14 … SP-19; LOG-08 | CLOSED |

### 4.7 From 7I (HE-7J-7I-01 … -16; §27.1)

| Handoff | Required signal (abridged from the frozen row) | Emission boundary | Authoritative source | Class | 7J rule | Status |
|---|---|---|---|---|---|---|
| HE-7J-7I-01 | Refused recovery requests; self-approval attempts; unmasked-material requests, denials, accesses; capability grants and revocations; erasure runs and lag; egress refusals by policy; ACL parity failures; break-glass on PostgreSQL or Redis | The audit row of the action or refusal commits (AUD-7I-07); infrastructure access log for break-glass | Audit rows; ledger; infrastructure access log | SEC | M-170 … M-176; AL-31 … AL-33 | CLOSED |
| HE-7J-7I-02 | Safe metrics: label allow-list RED-07; a CI check | Metric registration; build | Label registry | — | LBL-01 … LBL-10; IR-7J-04 | CLOSED |
| HE-7J-7I-03 | Restricted trace and log attributes (RED-01, RED-05); where TVF-05 diagnostics may be seen | Emission; sink routing | — | RST | TRC-09 … TRC-11; LOG-04 … LOG-07; TQA-01 … TQA-16 | CLOSED |
| HE-7J-7I-04 | Redis anomalies: connection attempt from a consumer-worker segment; group command under an unassigned member name; unexpected stream-length drop; entries with no matching outbox row where HRD-01 is adopted; ACL digest mismatch | Network policy; gateway; observer; provisioning | Network deny log; Redis; ACL source | SEC | M-177 … M-180; AL-34, AL-35 | CLOSED for four signals. **BLOCKED** for two: (a) the consumer-segment connection attempt has no named log source until 7K fixes the network topology (HE-7K-7I-04; owner 7K); (b) the unknown-origin entry check exists only if HRD-01 is adopted (HE-7K-7I-07; owner 7K). Neither blocks prevention, which is GWY-13, GWY-14 |
| HE-7J-7I-05 | Cross-tenant attempts: tenant-scope mismatch in a consumer; payload organization differing from the envelope; non-empty tenant setting at pool checkout; tenant-context cardinality per connection | Consumer classification; pool checkout hook | Consumer; connection pool | SEC | M-066, M-181, M-182, M-183; AL-30 | CLOSED |
| HE-7J-7I-06 | Secret-pattern scanning of log sinks | Node filter and in-region scheduled scan | Log sink | SEC | SCN-01 … SCN-07; M-184; AL-36 | CLOSED |
| HE-7J-7I-07 | Key-service unavailability by purpose; decrypt on `REPLAY_MATERIAL` outside an item or a live grant; `SECRET_UNAVAILABLE` with role PREVIOUS | Key-service client; key-service audit log; closure record | Key service; closure records | SEC / RST | M-185, M-186, M-134; AL-26, AL-37 | CLOSED |
| HE-7J-7I-08 | Audit-write failure rate; time since the last hash-chain run; open erasure steps and age; bodies past the lineage deadline; material within 14 days of its limit, at it, past it; holds past review date; day-83 job outcomes | Audit function failure; chain job; database reads | Audit tables; retention stores | AGG / SEC | M-190 … M-197; AL-38, AL-41 | CLOSED |
| HE-7J-7I-09 | Gateway authorization refusals by identity; gateway availability; acknowledgement refusals for missing evidence; unaccounted-obligation cases opened; reconciler watermark age; `PUBLISHED` rows held past 7 days and their age; `ATTESTED` verifications failed | Gateway decision; reconciler run; database read | Gateway; accounting and position records; ledger | SEC | M-200 … M-208; AL-17 … AL-20 | CLOSED |
| HE-7J-7I-10 | Journal append failures and latency; steps waiting at `INTENT_REQUESTED` or `INTENT_DURABLE` and their age; delete or overwrite attempts on the journal prefix; checkpoint age; quarantine state of every database incarnation; EV-097 admissions rejected by PV-7I-01 | Journal writer; object-store access log; database read | Journal store; step table | SEC | M-210 … M-216, M-230; AL-39, AL-40 | CLOSED |
| HE-7J-7I-11 | Second-remediation signals: `42501` under `app_platform_admin` on a 5I object and under a context principal on another context's object; admission with no audit row for its `config_revision`; `COMPLETION_EVIDENCE_UNATTRIBUTED` cases; completion refusals by cause; pairs `GONE`; pairs reaching `T_obl`; rows `PUBLISHED` without a position; batches waiting on the journal; approaching and missed deadlines; incarnation-mismatch refusals; token or proof refusals by cause; guard-column state with no provenance row | Guarded function refusal; database error class; invariant query | Database | SEC | M-203, M-204, M-205, M-207, M-217 … M-222; AL-19, AL-33 | CLOSED |
| HE-7J-7I-12 | Third-remediation signals: `42501` on `organization.organizations` by column; lifecycle proof refusals by cause; calls to a frozen three-argument signature; status or residency change with no provenance or audit row; erasure-operation refusals; self-approval; `APPROVED` erasure operations not executed and their age; `gdpr_erasure` disconnects with no completed operation; provisioning refusals; issuer availability | Guarded function refusal; invariant query | Database; authorization issuer | SEC | M-219 … M-226; AL-33 | CLOSED |
| HE-7J-7I-13 | Fourth-remediation signals: `42501` under `app_platform_admin` on an authorization-root relation; `ACTIVE` membership or role change with no tenant-path audit row; refused update of an approved plugin version; request-function proof refusals; refused edge out of `ON_HOLD`; status and registry hold that disagree; request holds by age; erasure waits on the hold gate; residency pair with no provenance row | Guarded function refusal; invariant query | Database | SEC | M-219, M-220, M-222, M-227 … M-229; AL-33 | CLOSED |
| HE-7J-7I-14 | Fifth-remediation indicators: index relations `UNVERIFIED` by age; hold placements refused for that reason; request holds with an empty contact set and with more than one contact; rows `SKIPPED_HELD` by store and reason; unattributed rows by store and share of new rows unattributed; retention-decision records by status and age; exceptions in force; determinations; index completeness failures by relation | Database reads | Subject index; hold registry; decision records | AGG | M-231 … M-238, M-244, M-245. The frozen row says "by organization": 7J reports counts of organizations in each state and never an organization label (LBL-01); per-organization detail is a case-bound query (§22.3) | CLOSED |
| HE-7J-7I-15 | Sixth-remediation indicators: open unauthorized-retention incidents by age and escalation level; periodic compliance count; sealed items by store; time between deadline and seal; decision records opened with less than 48 hours to the deadline; exceptions authorized, expired, refused; historical-association reviews; rows skipped as held by path kind; holds whose closure spans more than one contact; inspections of sealed content; index key versions in `VERIFY`; key-read failures; edges under a compromised version; lock-cycle aborts | Database reads; sealing and inspection functions | Incident records; vault; index | SEC | M-237, M-240 … M-250, M-253; AL-42, AL-43. **No indicator closes an incident** (PRV-04) | CLOSED |
| HE-7J-7I-16 | Seventh-remediation indicators: rows past their content deadline with content still present, by store and age (CAG-12), and time from deadline to erasure or seal; guard denials by path and access code; `DEADLINE_UNKNOWN`; `42501` on a content column by role; pre-handoff aborts; sealed items by basis; inspections bound to a hold record; platform holds by scope type and age and review dates passed; rows skipped as held by hold kind and basis; decision records by reason, `LEGACY_HISTORY_UNKNOWN` included; organizations by certification state, demotions and failed certifications by cause, hold placements refused as not certified | Guard function; database reads | Content stores; registry; certification records | SEC | M-196, M-219, M-227, M-232, M-234, M-237, M-241, M-247, M-251 … M-257, M-259 … M-262; AL-41, AL-43. **The guard is the control; the alert is not** (PRV-05) | CLOSED |

### 4.8 Coverage summary

| Source | Handoff rows | CLOSED | BLOCKED (wholly or in part) |
|---|---:|---:|---:|
| 7A, 7B | 7 | 6 | 1 (H-7B-01) |
| 7D | 23 | 23 | 0 |
| 7E | 12 | 12 | 0 |
| 7F | 10 | 10 | 0 |
| 7G | 10 | 10 | 0 |
| 7H | 10 | 10 | 0 |
| 7I | 16 | 15 | 1 (HE-7J-7I-04, two of six signals) |
| **Total** | **88** | **86** | **2** |

No row is closed by a general statement. Every CLOSED row names a metric, span rule, log rule, alert or test defined in this document.

---
## 5. Observability Architecture and Trust Boundaries

### 5.1 Stack

[FROZEN] 3E §14, 3F §17 – §19, 6A §25: OpenTelemetry SDK; Prometheus; Grafana dashboards as code; Grafana Tempo behind a cluster-wide OpenTelemetry Collector; `structlog` JSON to standard output, collected by a Fluent Bit DaemonSet into the cloud provider's log service with cold storage; Alertmanager routing to a pager receiver and a chat receiver. 7J adds no product and no external destination. The one structural addition is a second Prometheus instance holding only SLO aggregates (OD-7J-03; §27.2).

### 5.2 Logical architecture

```
                         REGION (one complete stack per region; nothing below crosses a region boundary)
 ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐
 │  EVENT PLANE (frozen 7D–7I; unchanged)                                                                    │
 │                                                                                                           │
 │  producers ─► PostgreSQL outbox ─► relay ─► Redis Streams ─► stream gateway ─► consumer workers           │
 │      │              │                │            │                │                  │                   │
 │      │              │                │            │                │                  ├─► recovery ledger │
 │      │              │                │            │                │                  └─► fan-out ─► dispatcher ─► egress
 │      │(B1)          │                │(B1)        │                │(B3)              │(B3,B4)     │(B5)    │
 │      ▼              │                ▼            │                ▼                  ▼            ▼        │
 │  ┌─────────────── in-process instrumentation: counters, histograms, spans, structured log lines ───────┐  │
 │  │  no network call on the request, audio, commit, publish or acknowledge path (ISO-01 … ISO-06)       │  │
 │  └───────┬───────────────────────────┬──────────────────────────────┬──────────────────────────────────┘  │
 │          │ /metrics (pull)           │ OTLP, bounded queue,         │ stdout                              │
 │          │                           │ drop on full                 │                                     │
 │          │      ┌────────────────────┼──────────────┐               │                                     │
 │  (B2,B4) │      │  state observer    │              │               │                                     │
 │  PostgreSQL ◄───┤  (read-only,       │              │               │                                     │
 │  aggregate-only │  aggregate-only    │              │               │                                     │
 │  functions      │  functions;        │              │               │                                     │
 │  Redis ◄────────┤  payload-free      │              │               │                                     │
 │  group-level    │  Redis commands)   │              │               │                                     │
 │  commands       └─────────┬──────────┘              │               │                                     │
 │                           │ /metrics                │               │                                     │
 │          ▼                ▼                         ▼               ▼                                     │
 │   ┌──────────────────────────────┐        ┌──────────────────┐   ┌─────────────────────────────────────┐  │
 │   │ Prometheus (raw, 30 days)    │        │ OTel Collector   │   │ Fluent Bit ─► log service           │  │
 │   │  ├─ recording rules          │        │ allow-list +     │   │   ├─ application class              │  │
 │   │  └─ alert rules ─────────┐   │        │ tail sampling    │   │   ├─ security class (restricted)    │  │
 │   └──────┬───────────────────┼───┘        └────────┬─────────┘   │   └─ cold storage                   │  │
 │          │ federation of     │                     ▼             └─────────────────┬───────────────────┘  │
 │          │ SLO aggregates    │              ┌─────────────┐                        │                      │
 │          ▼                   │              │ Tempo       │                        │                      │
 │   ┌─────────────────────┐    │              │ (14 days)   │                        │                      │
 │   │ Prometheus (SLO     │    │              └──────┬──────┘                        │                      │
 │   │ history, 13 months) │    │                     │                               │                      │
 │   └──────────┬──────────┘    ▼                     │                               │                      │
 │              │        ┌──────────────┐             │                               │                      │
 │              │        │ Alertmanager │             │                               │                      │
 │              │        └──────┬───────┘             │                               │                      │
 │              ▼               │                     ▼                               ▼                      │
 │   ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
 │   │ Grafana (aggregate dashboards)        restricted query broker (case-bound; §22.3)                  │  │
 │   └────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────┬────────────────────────────────────────────────────────────┘
                                                │ minimal notification only (NTF-01 … NTF-14)
                                                ▼
                               pager receiver, chat receiver, external dead-man heartbeat
```

`B1` … `B6` are the instrumentation boundaries of §5.3. The audit path is not in this diagram on purpose: a mandatory audit row is written by `audit.fn_insert_audit_event()` inside the transaction of the change (7I AUD-7I-01) and never passes through any box above.

### 5.3 Matrix — Observability architecture components

| ID | Component | Boundary | Emits or holds | Trust and privilege | Exists |
|---|---|---|---|---|---|
| OC-01 | Instrumentation in producers and relay | B1 | Relay counters and histograms; producer-side event anchor span; log lines | Runs with the workload's own identity. Adds no credential | DESIGNED |
| OC-02 | Instrumentation in Redis transport adapters | B2 | 7E outcome classes, `WAITAOF` results, redirects, capability and probe results | Same as the relay or publisher that owns the adapter. Never logs `env` (7E ENT-08) | DESIGNED |
| OC-03 | Instrumentation in consumer execution | B3 | Classification, handler outcome, commit and acknowledgement timings, spans | Consumer worker's context identity. No Redis credential (7I GWY-13) | DESIGNED |
| OC-04 | Instrumentation in completion and recovery | B4 | Gateway decisions; ledger transitions; replay items; reconciler classifications | Gateway, sweeper and tooling identities | DESIGNED |
| OC-05 | Instrumentation in external delivery | B5 | Fan-out, admission, attempt closure, callback receipt, plugin execution | Dispatcher, sweeper, callback and executor identities | DESIGNED |
| OC-06 | Security and privacy telemetry | B6 | Security-class log records; counters derived from guarded-function refusals and invariant queries | Emitted by the component that observed the fact; routed to the security sink | DESIGNED |
| OC-07 | State observer (exporter) | B2, B4, B6 | Gauges read from the authoritative stores; accounted totals maintained and read through the folds of §6.4 | **Own principals, content-free; read-only except for the observation-accounting relations** (OBP-01 … OBP-09; AOA-08) | DESIGNED |
| OC-08 | Exporters and collectors | — | Prometheus scrape; OpenTelemetry Collector; Fluent Bit | In the `observability` namespace (3F §19.1). No database or Redis credential except OC-07's | DESIGNED (3F) |
| OC-09 | Region-local monitoring storage | — | Prometheus (raw), Prometheus (SLO history), Tempo, log service and cold storage | In region (7I RSY-11). Each store has its own credentials | DESIGNED |
| OC-10 | Dashboards and alert evaluator | — | Grafana; Prometheus rules; Alertmanager | Read access to OC-09 only | DESIGNED |
| OC-11 | Authorized investigation tools | — | The restricted query broker of §22.3; the redacted recovery views of 7I §13.5 (unchanged) | Named individuals; case-bound; every query recorded (OD-7J-05) | DESIGNED |
| OC-12 | Notification egress | — | Rendered minimal notifications; dead-man heartbeat | Fixed server-side templates (OD-7J-04) | DESIGNED |

### 5.4 Observer principals

| ID | Rule |
|---|---|
| OBP-01 [7J] | **The observer is a separate workload with its own two credentials**, one for PostgreSQL and one for Redis, held in the secret manager and readable by the observer workload alone (the 7I ROL-01 pattern). |
| OBP-02 [7J] | **The PostgreSQL observer principal holds `EXECUTE` on a closed set of aggregate-only functions and nothing else.** Each function is `SECURITY DEFINER`, owned by the migration role, has a fixed `search_path`, checks `session_user`, takes no argument that selects an organization or an entity, and returns only counts, bucket counts, ages computed on the database clock and closed enumeration codes. It returns no identifier, no payload and no free text. The principal has no table privilege, no `SELECT` on any content column, sets no tenant context and is a member of no role. **Its one write path** is `EXECUTE` on the accounting fold functions of §6.4, which write only the observation-accounting relations (obligation records, cohort totals, final rows, corrections, run records), read identifiers and timestamps and never content, and return counts (AOA-04, AOA-08). No other function it can call writes anything. |
| OBP-03 [7J] | **`app_readonly`, `app_worker`, `app_api` and `app_platform_admin` are never used by any telemetry component.** Physical fact: `app_readonly` holds `SELECT` on tenant tables including `identity.sessions`, `voice.transcripts`, `crm.contacts` (`008_5B`, `016_5C`, `025_5D`) and on `audit.domain_event_outbox`, payload included (`077_5J1` L126). An exporter connected as that role could read event payloads and personal data; the telemetry system would then be a path for event content, which 7I RSY-11 says it must never be. The observer functions of OBP-02 are a governed-migration requirement (IR-7J-10). Until they exist no database-derived metric of this document can be emitted, and no existing role may be substituted (AG-7J-02). |
| OBP-04 [7J] | **The Redis observer is payload-free by command.** It needs: `XINFO GROUPS`, `XINFO CONSUMERS`, `XPENDING` (summary form, and the extended form limited to one entry), `XLEN`, `MEMORY USAGE`, `TTL`, `INFO`, `CLUSTER INFO`, `CLUSTER SHARDS`, `PING`. It is denied `XINFO STREAM`, `XRANGE`, `XREVRANGE`, `XREAD`, `XREADGROUP`, `XAUTOCLAIM`, `XCLAIM`, `XACK`, `XADD`, `XDEL`, `XTRIM`, every `XGROUP` subcommand, and everything 7I RDS-10 denies. |
| OBP-05 [7J] | **Why `XINFO STREAM` is denied.** Its reply contains the first and last entries of the stream with their field values, that is, the `env` of two events. 7I RED-08 allows `XINFO` and `XPENDING` output to be recorded on the understanding that it is class `INT`; the `STREAM` subcommand does not meet that. The two signals that would need it (oldest entry position; distance to the watermark) are emitted by the trim worker, which already computes `W(K)` under its own frozen privilege (7E TRM-02). Whether the deployed Redis version can scope an ACL to a subcommand is verified, not assumed (VT-7J-33); if it cannot, the observer is not given `XINFO` at all and the group-level figures are emitted by the obligation reconciler, which already issues `XINFO GROUPS` and `XPENDING` (7I ACC-16). |
| OBP-06 [7J] | The observer's Redis user is an addition to 7I Matrix 6 and is recorded as a controlled erratum (ERR-7J-06). It is provisioned with the governed ACL set, is included in the parity digest (7I RDS-15), and connects only from the observer's network segment. |
| OBP-07 [7J] | **No observer, collector, dashboard, alert rule or investigation tool can acknowledge an entry, move a cursor, write a recovery case, record a completion, place or release a hold, or write an audit row.** No telemetry principal holds any such privilege, in PostgreSQL, in Redis, in the key service or in the secret manager (VT-7J-31). |
| OBP-08 [7J] | Observer reads use the primary for every figure that an alert of class integrity, security or privacy depends on. A replica may serve diagnostic figures only, and a figure read from a replica carries the replica's replay lag as its own freshness (EVD-03). |
| OBP-09 [7J] | Observer queries are bounded: each has a statement timeout, runs outside any business transaction, takes no row lock, and its cost is a 7K budget (HE-7K-7J-04). A query that times out yields "no evidence", never zero (EVD-02). |

### 5.5 How telemetry is emitted, collected, buffered, stored, queried, protected and deleted

| Signal | Emitted | Collected | Buffered | Stored | Queried by | Protected by | Deleted |
|---|---|---|---|---|---|---|---|
| Process metrics | In-memory counters and histograms; one registry module (3E §14.2) | Prometheus scrape of `/metrics` | In the process: the current value only. A missed scrape loses resolution, never a count | Prometheus, raw, region-local | Grafana; alert rules | Label allow-list (§9); network policy; read-only data source | 30 days (OD-7J-03) |
| State metrics | Observer reads the authoritative store | Prometheus scrape of the observer | None. Each scrape is a fresh read or a cached read with its age exported | Same | Same | OBP-01 … OBP-09 | 30 days |
| Accounted observations | Obligation records and event-time cohort totals in PostgreSQL, one record per obligation identity (§6.4); the observer runs the folds and exports the results | Prometheus scrape of the observer | In PostgreSQL: records, totals and final rows survive observer, exporter and Prometheus restarts | Window and cohort Gauges and fold-time cumulative histograms in Prometheus, raw, region-local; window and final-cohort values also in SLO history | Grafana; alert rules; SLO reports | AOA-03, AOA-04, AOA-08; no content read | Obligation records per AOA-23; hourly cohort rows 45 days [CAND]; exported samples 30 days raw |
| SLO aggregates | Recording rules over raw series | Federation of the `slo:` series only | Prometheus local storage | SLO-history Prometheus, region-local | SLO reports; dashboard A | Bounded dimensions only (§27.2) | 13 months |
| Spans | OpenTelemetry SDK | OTLP to the cluster Collector | SDK batch queue, bounded, drop on full, drops counted (M-273) | Tempo, region-local | Restricted query broker | Attribute allow-list at the SDK and at the Collector (TRC-09) | 14 days |
| Application logs | `structlog` to standard output | Fluent Bit tail | Fluent Bit buffer, bounded | Log service 30 days; cold 90 days (3F §18.3) | Restricted query broker | D0 redaction; node-level masking; LOG rules | Per 3F §18.3 |
| Security-monitoring records | `structlog` with `sink_class = security` | Fluent Bit routing by that field | Same | Security log class: 90 days hot, 2 years cold (3F §18.3) | Security role only | Separate log group and credentials | Per 3F §18.3 |
| Alerts | Prometheus rules | Alertmanager | Alertmanager | Alert history, region-local | SRE | Minimal external payload (NTF) | 13 months |
| Audit rows | **Not telemetry.** `audit.fn_insert_audit_event()` in the transaction | — | — | `audit.audit_events` | 6L, 6M | 5J; 7I §19 | 5J §20 |

### 5.6 Rules that keep monitoring off the critical path

| ID | Rule |
|---|---|
| ISO-01 [7J] | **No synchronous telemetry export.** Incrementing a counter and observing a histogram are in-memory operations. Spans are queued to a bounded in-memory queue and exported by a background task. Log lines are written to standard output. No code path of the event plane waits on a collector, on Prometheus, on Tempo, on the log service or on Alertmanager. |
| ISO-02 [FROZEN + 7J] | **The live audio path is untouched.** No instrumentation added by 7J runs in the raw-WebSocket audio loop. The SIGNAL publisher already may not add waiting to the turn loop (7D CLD-05); its counters are in-memory. NFR-PERF-001 is preserved by construction: 7J adds no network call and no lock to that path. |
| ISO-03 [7J] | **Telemetry failure is swallowed at the boundary.** An exception raised by the metrics registry, the tracer, a span processor or a log handler inside event-plane code is caught at the instrumentation call, counted (M-273, where the counter itself is available) and discarded. It never propagates into a claim, a publish, a handler, a commit, an acknowledgement, a parking or an erasure. |
| ISO-04 [7J] | **Bounded memory.** Every telemetry queue has a fixed capacity and drops the newest item when full. No queue grows with backlog. Values are [7K] (HE-7K-7J-06). |
| ISO-05 [7J] | **No readiness coupling.** The readiness probe of an event-plane workload (3E §14.6) does not depend on any telemetry backend. A workload with no collector is ready. |
| ISO-06 [7J] | **The reverse does not hold for controls.** Where a frozen rule requires a durable write before an action (an audit row, a journal intent, an accounting row), that write is part of the action and its failure blocks the action exactly as frozen. Those writes are not telemetry and ISO-03 does not apply to them. |

### 5.7 Faults of the telemetry system itself

Handled in §25. Summary of the direction of every fault: the event plane continues; the affected figures become **unknown**; an independent path reports the blindness.

---

## 6. Canonical Telemetry Principles

| ID | Principle |
|---|---|
| PRN-01 [7J] | **Evidence, never authority.** No metric, log line, span or alert is an input to any decision of the event plane. No component reads Prometheus, Tempo or a log sink to decide whether to publish, process, acknowledge, park, resolve, replay, hold, seal or erase. |
| PRN-02 [7J] | **Authoritative source per fact.** A figure about a durable obligation is read from the store that owns that obligation: the outbox for publication, the accounting and position records for acknowledgement, the ledger for recovery, the delivery rows for webhooks, the receipts for callbacks, the journal and step tables for erasure. A process counter may describe activity; it never describes what is owed. |
| PRN-03 [7J] | **Five states.** Every health statement is one of `HEALTHY`, `DELAYED`, `FAILED`, `HELD` (intentionally, by a frozen rule) or `UNKNOWN` (the measurement is unavailable). `UNKNOWN` is never rendered, alerted, aggregated or reported as `HEALTHY` (EVD-01 … EVD-07). |
| PRN-04 [7J] | **A boundary has one meaning.** Each counter is incremented at exactly one named point, after the fact it counts has become true. "Published" is counted after durable confirmation; "committed" after the owner transaction commits; "acknowledged" after the gateway reports the acknowledgement result. |
| PRN-05 [7J] | **One clock per subtraction.** A duration or an age is computed from two readings of one clock (CLK-01 … CLK-06). |
| PRN-06 [FROZEN] | **Tenant-safe.** No tenant sees another tenant's event data on any telemetry surface (7A TEN-05). No tenant has access to internal telemetry at all in V1 (§22.4). |
| PRN-07 [FROZEN + 7J] | **Minimized.** Telemetry carries identity, type, version, closed category codes, counts and durations (7I RED-01, RED-05). It never carries a payload, a body, material, a processing input, a header value or a secret. |
| PRN-08 [7J] | **Closed vocabularies.** Every label value and every category code is a member of a closed set defined by a frozen source or by this document. A value outside the set is rejected before emission (LBL-06). |
| PRN-09 [FROZEN] | **Detection is not prevention.** Every security and privacy signal in this document observes a control that 7I enforces elsewhere. None is relied on as the control (7I HE-7J-7I-11 … -16). |
| PRN-10 [7J] | **Activity is not completion.** Replay, redrive, parking, sealing, cancellation and hand-off to reconciliation are counted as what they are. None is counted as successful processing or as completed erasure. |
| PRN-11 [7J] | **Duplicates are expected.** Delivery is at least once. Counters of attempts and deliveries count every attempt; indicators of obligations are derived from stores keyed by obligation identity, so a redelivery cannot count twice (DUP-01 … DUP-05). |

### 6.1 Evidence freshness and expected sources

| ID | Rule |
|---|---|
| EVD-01 [7J] | Every state metric family names an **evidence source** from the closed set: `outbox`, `ledger`, `delivery`, `receipt`, `accounting`, `journal`, `retention`, `index`, `redis_group`, `redis_cluster`, `trim`. For each source the observer exports the time of its last complete, successful read (M-270) and a count of failed reads (M-271). |
| EVD-02 [7J] | **A failed read exports nothing for the figures it would have produced.** The observer does not export `0`, does not repeat the previous value as if it were current, and does not fill a gap. The series go stale and Prometheus drops them. |
| EVD-03 [7J] | A figure is **fresh** when `time() - max by (source) (M-270)` is below the freshness bound `T_fresh` of its source ([CAND] three scrape intervals; [7K]). |
| EVD-04 [7J] | **Every alert and every indicator over a state metric is written against fresh evidence only.** The canonical form is `(<predicate>) and on () (<fresh(source)>)`, where `fresh(source)` is the label-preserving expression of EVD-09. An absent or stale source therefore yields `UNKNOWN` and the blindness alert for that exact source, never a silent "no problem". |
| EVD-05 [7J] | A dashboard panel over a state metric shows the freshness of its source next to the value, and renders a stale or absent value as "no evidence" with its age, never as zero and never as the last known value without that age. |
| EVD-06 [7J] | An indicator computed over a window that contains stale intervals reports those intervals as **unmeasured**, separately from good and bad (SLI-R-04). |
| EVD-07 [7J] | A group that cannot be read (missing, `NOGROUP`, Redis unreachable) has no lag figure. Its lag is `UNKNOWN`, and a missing registered group is itself a critical condition (AL-12). Zero lag is exported only when a successful `XINFO GROUPS` reply reported zero. |
| EVD-08 [7J] | **Trusted expected registry.** What must be reporting is not learned from what is reporting. A governed, code-owned registry file lists every expected evidence source, every expected workload component (and, for consumers, every expected (component, group) pair from 7E §29), every expected Redis shard of the active topology generation, and **every mandatory accounting stream with each of its two fold kinds** (EVD-13). From it the build generates Prometheus recording rules that emit one constant series per entry: `platform_telemetry_expected_source{source, state}`, `platform_telemetry_expected_component{component, group, state}`, `platform_telemetry_expected_shard{shard, state}`, `platform_telemetry_expected_stream{stream, fold_kind, state}` (M-286 … M-289), and, per component and per stream fold, its permitted age (`…_expected_component_max_age_seconds`, `…_expected_stream_max_age_seconds`). **These series are produced by the rule evaluator, independently of the observer and of every workload, source and stream they describe**, so they exist when the thing they name is silent. The source of truth is the registry file in the repository, generated beside the 7E group registry and the stream definitions of §6.4; a change to it is a reviewed change and a `PLATFORM_CONFIG_CHANGED` audit event (M-282). |
| EVD-09 [7J] | **Deterministic, label-preserving absence detection.** A source is unexpectedly missing when its expected series has no fresh counterpart: `platform_telemetry_expected_source{state="EXPECTED"} unless on (source) ((time() - max by (source) (platform_telemetry_evidence_last_success_timestamp_seconds)) < T_fresh)`. The result carries the `source` label of the missing source, whether its series is stale or has disappeared entirely, and whatever the other ten sources are doing. `fresh(s)` in every other expression of this document is the complement for one source: `((time() - max by (source) (…{source="s"})) < T_fresh)`. **A bare `absent(M-270)` or `absent(M-272)` is not used anywhere**: it is false as long as any one series of the metric exists and so proves nothing per label. |
| EVD-10 [7J] | **States of an expected entry.** `EXPECTED`: must report; absence alerts. `DISABLED`: intentionally not reporting, for a named reason, with an expiry time in the registry after which the build fails until it is renewed or restored; absence does not alert, and the entry is listed on dashboard I as disabled with its expiry. `RETIRED`: removed from the registry by a governed change (a retired group, a retired topology generation's shard); no series is generated. Anything that reports and is in none of these states is **unregistered** and is shown, never ignored (the 7E TRM-04 pattern). A component being replaced (rolling deploy, new instance, failover of a shard's primary) keeps its registry identity, because entries name a logical component, a group or a shard position, never an instance or a node. |
| EVD-11 [7J] | **Topology change.** A new topology generation, a new group or a new component is added to the registry in the same governed change that introduces it, in state `DISABLED` until its activation and `EXPECTED` from then. A registry that names something not yet deployed alerts; one that omits something deployed shows it as unregistered. Neither is silent. |
| EVD-12 [7J] | **No samples is not success.** A ratio whose denominator has no samples in an interval is undefined for that interval. It is reported as *idle* only when fresh evidence shows there was nothing owed (for example M-001 = 0 from a fresh `outbox` read), and as *unmeasured* otherwise. Neither counts as good time toward an indicator being established (SLI-R-04). |
| EVD-13 [7J] | **Accounting-stream blindness is detected per stream, from outside the stream.** The top-level `accounting` evidence source being fresh says only that the observer read the accounting relations; it says nothing about whether each stream's fold ran. Every mandatory stream therefore has two registry entries, one per fold kind (`routine`, `completeness`), each with a permitted age. A stream fold is unexpectedly missing when its expected series has no fresh counterpart: `platform_telemetry_expected_stream{state="EXPECTED"} unless on (stream, fold_kind) ((time() - max by (stream, fold_kind) (platform_telemetry_observation_fold_last_success_timestamp_seconds)) < on (stream, fold_kind) platform_telemetry_expected_stream_max_age_seconds)`. The result carries the `stream` and `fold_kind` of exactly the missing fold, whether its last-success series is stale or has disappeared, and whatever the other streams are doing. **Idle is not absent:** a fold that runs and finds nothing to do commits a run record and advances its last-success time, so a stream with no traffic stays fresh; only a fold that did not run, did not commit or was not exported goes stale. States follow EVD-10: a stream is `DISABLED` (with reason and expiry) until its source records exist and its gate opens, `EXPECTED` from activation, and `RETIRED` only by a governed change that also retires every indicator reading it. An indicator whose stream is missing has state `UNKNOWN` and is not reported (AOA-24); a stream's disappearance can never read as zero obligations or as a good ratio, because no reported figure is taken from a series that is not fresh (EVD-04) and the window state is itself a series whose absence is `UNKNOWN`. |

### 6.2 Clocks

| ID | Rule |
|---|---|
| CLK-01 [7J] | An age of a database row is computed inside PostgreSQL as the database clock minus a column of that row, in the observer function. The observer never subtracts a database timestamp from its own wall clock. |
| CLK-02 [7J] | OBS-7D-02, the oldest eligible age, is `clock_timestamp() − least(available_at)` over eligible rows, evaluated in the database. For an expired claim the reference is the row's `available_at`, not `claimed_at`. |
| CLK-03 [7J] | OBS-7D-13, publication latency, is `published_at − occurred_at` of one outbox row, both PostgreSQL timestamps written by PostgreSQL. `occurred_at` is copied into the row's obligation record at registration and the difference is computed and bucketed in the database when the record is closed (§6.4). The relay's wall clock, the observer's clock, the fold's commit time and the Prometheus scrape time are not inputs. Every other accounted duration is likewise the difference of two stored PostgreSQL timestamps: an origin time held in the obligation record and the stored time of the closing fact. |
| CLK-04 [FROZEN] | A Redis entry ID is a transport position. It is never read as a time and never compared with a PostgreSQL timestamp (7E ENT-04; 7I ACC-04, ACC-16). No metric, alert or runbook in this document derives a duration from an entry ID. |
| CLK-05 [7J] | A pending entry's idle time is the value Redis reports in `XPENDING` (a duration measured by one Redis node). It is exported as reported. |
| CLK-06 [7J] | In-process stage durations use a monotonic clock. Clock offset between a node and its time source is itself monitored (M-279); a node beyond the bound makes its wall-clock-derived log timestamps suspect and is flagged, and no indicator in this document depends on such a timestamp. |
| CLK-07 [7J] | **A duration whose two ends are on different clocks is not measured.** The time between publication (a database timestamp) and receipt by a consumer worker (a worker's clock) is such a duration; no durable record of receipt exists. It is not exported as a per-event metric. Its effect is contained in the end-to-end duration of SLI-17, whose two ends are both database timestamps. **A position record's `recorded_at`, a Redis entry ID and a worker's wall clock are never used in place of an event's `occurred_at`** (CLK-04): where the outbox row is gone, the origin time is the one preserved in the obligation record (AOA-19), and where none was preserved the obligation is unmeasured, not approximated. |

### 6.3 Duplicate emission

| ID | Rule |
|---|---|
| DUP-01 [7J] | Process counters are per process and are summed across instances. A restart resets a counter; `rate()` and `increase()` absorb the reset. No dashboard or alert reads a raw process-counter value. |
| DUP-02 [7J] | A counter of **attempts** (claims, publications, deliveries to a consumer, HTTP attempts, replay items) counts each attempt, including repeats. Its name says so. It is an **activity counter**: a process that dies between the fact and the increment loses that increment (DUP-05). |
| DUP-03 [7J] | **Three evidence grades, never mixed.** (a) *Activity counters and histograms*: process-emitted, approximate under crashes, used for rates, diagnosis and provisional alerts. (b) *State figures*: gauges read from the authoritative store on each scrape; exact at the instant of the read. (c) *Accounted figures*: kept durably in PostgreSQL, one obligation record per obligation identity, attributed to the event-time cohort of the obligation's origin (§6.4). Every indicator of §10 states which grade its numerator and denominator are. **A reported window of a per-obligation indicator is grade (c) only, read as window Gauges computed in the database**; it is never built from an observer's memory, from a process counter, or from the difference of cumulative counter samples. |
| DUP-04 [7J] | **Replicated exporters never multiply a logical observation.** Two observer replicas export the same state figures and the same accounted totals, because both read the same rows. Every query over an observer series first removes the replica dimension with `max without (instance)` (for ages, gauges, and for accounted cumulative counters and buckets, whose replicas differ only by read time and are monotone), and only then applies `rate`, `increase`, a difference or `histogram_quantile`. `sum` across observer instances is prohibited, by a build check on rule and dashboard files (IR-7J-04). |
| DUP-05 [7J] | A crash between a fact becoming true and a process-counter increment loses one increment. This is accepted for grade (a) and is why no obligation indicator uses grade (a) for its exactness. |
| DUP-06 [7J] | Accounted records and cohort totals are durable and do not reset on an observer or exporter restart. They return to an earlier state only when the database itself is restored to an earlier point; that is an accounting epoch change (AOA-14). |

### 6.4 Authoritative observation accounting

Two earlier versions of this section were unsound and are withdrawn. The first derived histograms from an observer's in-memory watermark (P1-7J-R01). The second counted each observation once, durably, but (a) read an obligation's original event time from the outbox row at the moment of completion, although 7I ACC-06 lets that row be deleted once a recovery case exists (P1-7J-R05), and (b) called the difference of two cumulative counter samples an exact 28-day total, although a counter moves when the fold commits and not when the event happened (P1-7J-R06). The rules below replace both. A third version kept those two corrections and contradicted itself in three places, which the third independent review found (§34.6): it forbade finalizing a cohort hour that overlaps an unmeasured interval while defining the window as the trailing 672 final hours and expecting unmeasured hours to be counted inside it (P1-7J-R08); it gave one single-close record to a delivery whose three milestones feed three histograms (P1-7J-R09); and it excluded held deliveries from SLI-11 without saying how a delivery that was already counted is moved (P1-7J-R10). AOA-01 … AOA-04, AOA-11 … AOA-14, AOA-18 and AOA-20 … AOA-24 are corrected, and AOA-26 … AOA-28 are added. The fourth review found that AOA-27 as then written read an audit row's `occurred_at` as the time a status change took effect, although that column holds the start of the transaction (P1-7J-R11), and began the eligibility interval at the delivery's creation although the indicator begins at the event (P1-7J-R12). AOA-27 is rewritten under owner decisions OD-7J-11 … OD-7J-13 (§34.7). The fifth review found that the rewritten AOA-27 (e) did not prove that its evaluation cutoff precedes the snapshot of the evidence read (P1-7J-R13); the cutoff protocol, the zero-denominator rule and the strict verdict rule of OD-7J-14 are in AOA-27 (d), (e), (h) as they now stand (§34.8). The sixth review found that the listing could not establish the status at the start of a window once the transitions before it had been removed, and that the current status was allowed to stand in for it (P1-7J-R14); AOA-27 (c), (d), (e) and (g) now rest on a per-organization baseline and never on the current status (§34.9). **Nothing in this section exists**; it needs a governed migration (IR-7J-41, IR-7J-47) and is gated (AG-7J-13).

**The model in one paragraph.** For each stream the database keeps one payload-free **obligation record** per obligation identity. It is created ("registered") while the source row that carries the obligation's original timestamp still exists, and it stores that timestamp. It is later "closed" with the time and class of whatever ended the obligation. Counts are kept per **event-time cohort**: the UTC hour that contains the obligation's origin time. Every UTC hour has a row in the stream's hour ledger. An hour becomes **final** once nothing visible can still change the figures an indicator reads from it, and is then either **measured** or, where observations were permanently lost, **unmeasured**; hours are finalized in order, so the final hours have no gap. A reported window is the 672 consecutive hours that end at the last final hour: sums over its measured hours and a count of its unmeasured ones, computed in the database. Prometheus carries those figures; it does not produce them.

| ID | Rule |
|---|---|
| AOA-01 [7J] | **Stream.** An accounted figure is defined by a stream: an obligation identity; an **origin time** read from a named column of a named source row; **exactly one kind of closing fact**, with its own stored PostgreSQL time and a closed class set; bounded dimensions. A measurement with several independently timed milestones is therefore several streams, one per milestone, each with its own records (AOA-28); it is never one stream with several closes. The streams of V1 are in the table below: eight. A stream whose obligations have no separate closing fact (a count of closure records) has only an origin. |
| AOA-02 [7J] | **Identity and uniqueness.** The governed migration provides, per stream, an insert-only-then-close **obligation record** whose primary key is (stream, obligation identity). Registration inserts it once; a second registration of the same identity, by any replica, at any time, in any order, inserts nothing. Closing is a single compare-and-set from open to closed; a second close changes nothing. **One record therefore yields at most one closing observation, and every histogram family is fed by the one close of one stream.** Where one close yields two durations (M-167 and M-168, both from the close of `webhook_first_closure`), each is the difference between that single closing time and an origin time stored in the same record, and both are observed in the closing transaction. The three milestones of a delivery `d` are three records in three streams, (`webhook_first_claim`, `d`), (`webhook_first_admission`, `d`) and (`webhook_terminal`, `d`), each closed once and independently of the others. This primary key, and nothing in observer memory, is the uniqueness boundary. |
| AOA-03 [7J] | **What an obligation record holds, and what it never holds.** The stream; the identity (for example logical group and `event_id`); `origin_at`; the cohort hour derived from it; the bounded dimension codes; and, once closed, `closed_at`, the closing class and the latency bucket. A record of `webhook_first_closure` also holds the delivery's `created_at`, its deadline `decide_by`, its `eligibility`, the closed code of the basis on which it was settled and the database time of that settlement (AOA-27). **No payload, no body, no envelope, no organization identifier, no subject key, no free text.** It is the payload-free obligation measurement source: it carries the original event time forward after the source row is gone. Stored dimension codes are fixed at registration with one exception: `eligibility` is settled once, from the provisional `active_throughout` to `active_throughout`, `held_interval` or `uncertain`, by the compare-and-set of AOA-27, which moves the record's counts in the same transaction when the class changes. The cohort hour of a record never changes. |
| AOA-04 [7J] | **The fold.** A guarded function per stream, `SECURITY DEFINER`, owned by the migration role, callable by the observer principal only. One call is one transaction: take the stream's lock without waiting (a second caller returns "busy"); **register** a bounded batch of source rows that have no obligation record, copying `origin_at` from the source row inside the database; for `webhook_first_closure`, **evaluate eligibility** (AOA-27); **close** a bounded batch of open obligation records whose closing fact now exists; update the hourly totals, or append corrections where the hour is final (AOA-22), for exactly the records it inserted, closed or reclassified; **maintain the hour ledger**: insert the missing hour rows up to the current hour, append any unmeasured declaration its run records prove (AOA-11, AOA-14) and, in a completeness fold, finalize hours in order (AOA-20); record the run. It returns counts. It reads identifiers, status codes and timestamps and never a content column. For the webhook streams that is: from the delivery row `id`, `organization_id` (passed inside the function to the lifecycle listing of AOA-27; never stored and never returned), `event_id`, `event_type`, the replay and test markers, `status`, the `failure_reason` category, `created_at`, `completed_at`; from a claim record `claim_seq` and `claimed_at`; from an admission record `claim_seq`, `admission_seq` and `admitted_at`; from a closure record `claim_seq`, `attempt_number`, `closed_at` and the closure fields of §19.2. It never reads a body, a body hash, a URL, a destination fingerprint, host, port or address, a `config_revision`, a response preview or a secret reference, and it reads no row of `audit.audit_events`. It writes only the accounting relations of this section, on which no login role has any privilege, and **it contains no statement that inserts into, updates, deletes from or row-locks any relation outside them**; the governed migration asserts that by a scan of the function bodies, and VT-7J-110 proves it by comparing every source relation before and after. |
| AOA-05 [7J] | **No cursor decides correctness.** Work is found by "has no obligation record" and "is open and has a closing fact", never by "is newer than a stored time". A source row that becomes visible late, or several rows with one timestamp, are found whenever they are visible. To bound cost the routine fold looks back a window `L` ([CAND] 1 hour; [7K]) on the source's timestamp; a **completeness fold**, at least once a day, has no lookback and examines every retained source row and every open obligation record, in bounded batches. |
| AOA-06 [7J] | **Replicas.** Both observer replicas call the fold and export the results. The lock lets one fold run at a time; the primary key and the compare-and-set make the outcome independent of which ran. Both then read identical figures. Queries apply DUP-04. |
| AOA-07 [7J] | **Restart and crash.** The observer keeps nothing between calls. A crash before the fold's commit rolls back records and totals together; after it, both are committed. A restarted observer calls the fold again. Nothing is lost and nothing is counted twice. |
| AOA-08 [7J] | **Privilege.** The observer principal holds `EXECUTE` on the fold functions and on the read functions of AOA-21, in addition to its other read functions (OBP-02). It holds no table privilege, reads no content, sets no tenant context, and can change nothing but the accounting relations, which no event-plane code reads (PRN-01). It cannot acknowledge, park, resolve, hold or erase anything (OBP-07). Every function is cross-tenant by nature and returns counts by bounded dimension only; none takes or returns an organization. |
| AOA-09 [7J] | **The event plane is not touched.** No producing transaction, mark-published call, handler transaction, ledger function or closure function writes an accounting row. Accounting is a later, separate transaction by the observer and reads committed rows without `FOR UPDATE`. If it fails or is never deployed, events are published, processed and delivered exactly as before; only the measurement is missing. |
| AOA-10 [7J] | **Cleanup and retention never wait for accounting.** A source row is deleted by its frozen rule whether or not it was registered. Making cleanup wait for a measurement record would let monitoring delay retention (PRN-01). |
| AOA-11 [7J] | **When registration was impossible, the loss is declared, and only then.** Let `R_min` be the shortest guaranteed life among a stream's origin source and the sources of its closing facts (the stream table), and `m` a safety margin ([CAND]; [7K]). A source row can have been deleted unseen only if two consecutive committed **completeness** folds of the stream started more than `R_min − m` apart. The fold establishes that from its own durable run records, never from a timeout, an alert or an operator's statement. It then appends one **unmeasured declaration**, cause `REGISTRATION_GAP`, covering every cohort hour that overlaps the origin interval of the rows that may be missing: from the start of the earlier fold minus `B` and the settle delay, to the start of the later fold minus `R_min`, plus `m`. No hour the earlier fold could have finalized lies inside it (F1, F2). It adds the interval to M-285. It does not estimate or back-fill. A declaration is a statement of **permanent** loss: it is append-only and is never withdrawn, shortened or overridden by later evidence. **A fold that is merely late declares nothing.** While every completeness-fold gap stays below `R_min − m`, every source row is still there to be registered; the affected hours stay open, not final, and they are measured when the fold catches up (AOA-20). The rule is sufficient and not necessary: it may declare an hour unmeasured in which nothing was in fact lost, and never the reverse, with the one exception recorded as RR-7J-09 (a row both past-dated to before the declared interval and deleted unregistered). Obligations that still have a durable case are not lost from view (AOA-19). |
| AOA-12 [7J] | **Measurement completeness and assessment are two different properties of a cohort hour.** *Assessment*: an hour is `OPEN` until the fold finalizes it and `FINAL` from then on. *Measurement*: a final hour is `MEASURED` (registration and closing were shown complete for it under AOA-20) or `UNMEASURED` (an unmeasured declaration of AOA-11 or AOA-14 overlaps it), with the declaration's cause. An hour that is not final has no measurement value: it has not been assessed yet, which is neither. **A partially measured hour is never complete, and an unmeasured hour is never an empty one**: its figure is absent, not zero. Each stream exports the time of its last routine and completeness fold (M-283), its unregistered backlog and oldest age (M-284), its declared unmeasured time and its unmeasured hours by cause (M-285), and its finalization watermark (M-292). Whether those series are present at all is checked from outside the stream (EVD-13). |
| AOA-13 [7J] | **Two exports, with different meanings.** (a) *Window and cohort figures* (M-290, M-291, M-294, M-295): Gauges read from the database, already attributed to event time. These are the only source of a reported indicator. (b) *Fold-time cumulative histograms* (M-017, M-085, M-122, M-131, M-165 … M-168, as `_bucket`, `_count`, `_sum`) and the cumulative closure counter (M-144): each observation is added when its fold commits. They are exact in count and **approximate in time by the fold lag**; they serve graphs, quantile estimates and provisional alerts, and are **never** used for a reported window. Each family has one stream and one close behind it: M-165 `webhook_first_claim`; M-166 `webhook_first_admission`; M-131 `webhook_terminal`; M-167 and M-168 the single close of `webhook_first_closure`. Bucket boundaries are fixed in the stream definition, at most 12 per family (LBL-09); a native histogram is not assumed. A fold-time series is never restated: an observation made while a record was `active_throughout` stays in that series if the record is reclassified later (AOA-27). Only the window figures are restated, and only by counted corrections. |
| AOA-14 [7J] | **Accounting epoch; a restore is a declared, permanent gap.** A restore of the database to an earlier point returns obligation records, hour rows, totals, final rows, corrections and declarations to that point together, consistent with the restored sources, and what happened in the lost timeline is no longer in the database at all. The epoch of a stream is the database incarnation its fold runs under: the identifier of 7I JRN-12, which changes on every restore, point-in-time recovery and promotion, is reported by the running instance and not by restored content, and is compared by every guarded function with the activation relation. The fold is such a function and does not run on a database that has not been activated. Every run record stores the incarnation it committed under, and each stream exports its epoch. The first fold of a stream after activation therefore finds its last run record under another incarnation and appends an unmeasured declaration, cause `RESTORE_GAP`, for every cohort hour from the hour containing that last run record's start time minus `B` and the settle delay (a lower bound of the restore point that is in the restored database itself) to the hour containing its own start time. Those hours are permanently unmeasured in every stream. The restored hour ledger is continued from where the restore left it: nothing is renumbered and no hour is skipped. No hour that was final in the restored ledger lies inside the declared interval, because a final hour ended more than `B` plus the settle delay before the start of the fold that finalized it (F1; the settle delay is never longer than `G`). A window that contains such hours is evaluated under AOA-21 and AOA-24. The fold-time counters of AOA-13 (b) move backwards at a restore; no reported figure reads them. |
| AOA-15 [7J] | **Withdrawn: the difference of cumulative counter samples is not an event-time window.** A counter sample taken at scrape time `t` contains every observation folded by `t`, whenever its event happened. The difference between samples 28 days apart is therefore "observations folded in those 28 days", which differs from "obligations that originated in those 28 days" by every observation folded late across either boundary, and it breaks at an epoch change. The worked comparison is in §34.5. Reported windows are computed under AOA-18 … AOA-22 only. |
| AOA-16 [7J] | **Bounded cost.** The routine fold is an index range over the lookback with a row limit; the completeness fold is chunked. Both need indexes that do not exist today (`077_5J1` L88 – L93 has none on `published_at`) and are part of IR-7J-41. One small obligation record exists per obligation for the life given in AOA-23. Cohort totals are one row per (stream, dimension tuple, cohort hour) for a bounded number of hours. All of it is 7K's to measure (HE-7K-7J-14). |
| AOA-17 [7J] | **Duplicates, replay, groups and generations create no extra obligation.** The identity is the obligation, not the attempt, the entry, the key or the generation. An outbox row confirmed twice, or published to keys of two topology generations (7I ACC-19), is one publication obligation. A (logical group, `event_id`) pair is one processing obligation however many times the entry was delivered, redelivered, reclaimed or replayed by R1, R2 or R4, and whichever generation's key carried it; accounting, completion evidence and cases are all keyed that way (7I ACC-14). A group that gains a type later owes nothing for earlier events unless 7G grants a backfill: its origin obligation is `NOT_OWED` (7F HCG-28 … HCG-31) and an R3 backfill is counted as a replay item (M-107), never as a first-processing obligation. A public webhook replay (R7) is a new delivery and is excluded from the first-attempt streams by predicate. |
| AOA-18 [7J] | **Event-time cohorts.** Every accounted indicator names its **semantic time**: the origin time of AOA-01 for that stream (§10.2 lists it per indicator). An obligation belongs to the cohort hour that contains its `origin_at` and to no other, whenever it was registered, closed, reclassified or folded. Totals are kept per (stream, dimension tuple, cohort hour): obligations registered; obligations closed, by closing class; obligations closed with latency at or below each bucket boundary. A fold that handles obligations from many different hours in one batch adds each to its own cohort hour. **At every committed state a record is counted in exactly one dimension tuple of its one cohort hour.** The hour never changes. The tuple changes only by the eligibility move of AOA-27, which takes the record's counts out of the old tuple and puts them into the new one in the transaction that changes the record. |
| AOA-19 [7J] | **Registration happens while the origin timestamp exists; an unresolved obligation never leaves view.** An obligation is registered from the source row that holds its origin time, which the frozen rules keep for a minimum time (the table below). From then on its `origin_at` is in the obligation record and no longer depends on the source row. For the processing stream this is what survives outbox cleanup: 7I ACC-06 lets the outbox row be deleted once every owed group has an accounting row **or a recovery case**, and a case is not a completion and holds no `occurred_at` (7G §18.1). The obligation record stays **open** for as long as no closing fact exists, with no time limit, exactly as an unresolved case never ages out (7G PRT-02). Independently of accounting, every non-terminal recovery case of kind `CONSUMER` is counted from the ledger itself; a case with no obligation record (registration was missed under AOA-11) is counted as `UNREGISTERED_CASE` in M-086 and aged from its `first_seen_at`; having no surviving origin time it has no cohort hour, and it is counted as unattributed (AOA-26). |
| AOA-20 [7J] | **Finalization: every hour is finalized, in order, as measured or as unmeasured.** The fold keeps one row for **every** UTC hour of a stream from the hour of its activation (the hour ledger, AOA-26). Hours become final strictly in order: `H` can be finalized only when the hour before it is final. `H` is finalized **`MEASURED`** when all of the following hold on the database clock: (F1) the finalizing fold started after the end of `H` plus the largest boundary `B` the stream's indicators use plus a grace `G` ([CAND] 1 hour; [7K]; the settle delay is never longer than `G`); (F2) a completeness fold started after the end of `H` plus `B` plus a settle delay and committed, leaving no visible source row with an origin in `H` unregistered, no open record in `H` whose closing fact already exists and, for `webhook_first_closure`, no record in `H` whose eligibility is unsettled (AOA-27); (F3) every upstream stream is final for `H`, **measured or unmeasured**, or the time is past the end of `H` plus `B` plus `G` plus the upstream's permitted watermark lag `T_final_lag` (the upstream is then `UNKNOWN` and alerting on its own account, and whatever it lets through later reaches `H` as a correction); (F4) no obligation of `H` is still **unclassified**, that is, open with neither an accounting row nor a recovery case, which 7I ACC-17 bounds by `T_obl`; (F5) no unmeasured declaration overlaps `H`. `H` is finalized **`UNMEASURED`** when F1 holds, a declaration overlaps `H`, and a completeness fold has committed after that declaration was appended. F2, F3 and F4 are not required for it, because nothing can make that hour complete. In both cases the fold writes one immutable final row: for a measured hour the registered, not-owed and closed-within-boundary counts per dimension tuple and bucket boundary; for an unmeasured hour the measurement, the cause, and whatever was observed, stored as `observed` counts that no window sums. **An hour that satisfies neither set stays open.** A late fold, a completeness fold that has not yet run and an unclassified pair are temporarily unavailable evidence: they make the watermark old and the window `UNKNOWN` (AOA-24), and no passing of time turns them into an unmeasured hour. F3 orders finalization and passes nothing on: **an upstream hour being unmeasured does not make the downstream hour unmeasured**, because every stream registers from its own source rows under its own folds, and F3 cannot block for ever, whether the upstream's evidence is permanently incomplete (the upstream hour is then finalized unmeasured) or its fold is dead (the lag bound applies). **An obligation that is open at finalization is counted as valid and not good**, which is correct for every "within `B`" indicator: it did not close within `B` and nothing later can change that. Open obligations therefore never block finalization, and never vanish from it. |
| AOA-21 [7J] | **Windows: exactly 672 consecutive UTC hours.** The finalization watermark `w` of a stream is the end of the last hour of the unbroken final prefix of its hour ledger. Because hours are finalized in order, every hour before `w` is final, and the watermark advances across an unmeasured hour exactly as across a measured one. The reported window of an indicator is the 672 consecutive UTC cohort hours `[w − 672 h, w)`, every one of them, whatever its measurement. No hour is skipped, and no older hour is taken in place of an unmeasured one. A read function (AOA-26) returns, per indicator and bounded scope: `w`; the number of `MEASURED` and of `UNMEASURED` hours among the 672, whose sum is always 672 (an hour before the stream's activation has no ledger row and counts as unmeasured); the sums of final registered, not-owed and good counts **over the measured hours only**; the signed post-final corrections of AOA-22 that fall on measured hours of the window; the `excluded_held` count (AOA-27); the number of unattributed obligations that may belong to the window (AOA-26); and the window's state. **An unmeasured hour contributes nothing to the numerator or the denominator, from its final row, from its observed counts or from corrections, and contributes one to `unmeasured_hours`.** The observer exports these as Gauges (M-290, M-291, M-295). The figure is the same whichever replica reads it, after any restart, and does not depend on when Prometheus scraped. |
| AOA-22 [7J] | **After finalization every change is an appended, signed correction with its provenance; a final row is never updated.** Two things reach an hour that is already final. (a) *A late registration*: an obligation whose source row became visible late, or whose producer assigned an origin time in the past (7B OCC-01 … OCC-04 make the `occurred_at` of EV-079 the service-end time, which can precede insertion by hours): `+1 registered` on its dimension tuple and, if it also closed within a boundary, `+1 good` for that boundary. (b) *A reclassification*: a final-hour obligation later classified not owed (`+1 not_owed`), or moved at its settlement out of the provisional `active_throughout` class into `held_interval` or `uncertain` (AOA-27): `−1 registered` on the old tuple and `+1 registered` on the new one and, if it had been counted good, `−1 good` and `+1 good` likewise, all in the one transaction that changes the record. Each entry is appended with the stream, the hour, the dimension tuple, the kind, the sign, a closed reason code (`LATE_REGISTRATION`, `NOT_OWED`, `ELIGIBILITY_RECLASSIFIED`), the fold run, the epoch and the database time; nothing is ever deleted from or changed in that list. A window includes the signed corrections of its measured hours, so the figure is right, and the correction is also exported (M-293) so that a restated window is visible as restated. A correction that falls on an unmeasured final hour is kept with the hour's observed counts and enters no window (M-293 kind `into_unmeasured`); it never makes the hour measured. **For every dimension tuple and hour, the final count plus its corrections is never negative**: a `−1` is issued only by the compare-and-set that moves one record out of a tuple in which that same record was counted `+1`, by the final row or by an earlier correction. The read function checks this and returns `UNKNOWN` with the invariant alert of AL-60 rather than a negative or a clamped figure. Unmeasured declarations never fall on a final hour (AOA-11, AOA-14), so no final row's measurement is ever changed. |
| AOA-23 [7J] | **Lifetime of the accounting data.** An open obligation record lives until it is closed. A closed record is removed by the maintenance principal once its cohort hour is final and [CAND] 7 days have passed, and never later than the last frozen record of the same identity is removed (the completion record under 7I CEV-15, the accounting and position records under ACC-11, or the resolved case under 7G PRT-01). **No identifier is therefore kept by accounting longer than a frozen relation already keeps the same identifier.** Hour-ledger rows, cohort totals, final rows, correction entries, unmeasured declarations, unattributed counts and run records hold counts, closed codes and times and no identifier; they are kept [CAND] 45 days, which covers the window, finalization and re-reading; the 13-month history is the SLO-history store (§27.2). |
| AOA-24 [7J] | **State of a window, and what each state may be used for.** Evaluated in this order. `UNKNOWN`: the finalization watermark is older than its permitted lag, or the stream's fold evidence is absent (EVD-13), or the read function's own check fails (measured plus unmeasured hours is not 672; a count is negative). No figure is reported. `NOT_ESTABLISHED`: unmeasured hours exceed [CAND] 2% of the window (more than 13 of 672), or an unattributed obligation may belong to the window. The window is reported as neither met nor breached; its sums are exported for diagnosis only. `ESTABLISHED_PARTIAL`: 1 to 13 unmeasured hours and nothing unattributed. The measured ratio is shown, always with the number of hours it covers ("667 of 672 hours measured") and the cause of the rest, as *measured* for those hours and *unavailable* for the others (SLO-07). **It is never shown or reported as "met", and it moves no error budget in either direction** (EB-05). `ESTABLISHED`: no unmeasured hour and nothing unattributed. This is the only state in which an objective is reported met or breached, a budget is consumed, exhausted or cleared, a freeze is ended, or an indicator's measurement reliability is counted as validated (EB-01, EB-11). **Missing evidence therefore cannot make a window healthy**: an unmeasured hour is never counted as an hour without failures, is never replaced by a measured hour, and keeps the window out of every verdict until it has left the 672 hours (OD-7J-11). Two further conditions apply to SLI-11. A window that contains a delivery settled `uncertain` for want of trustworthy lifecycle evidence (basis `EVIDENCE_FAULT` or `EVIDENCE_UNAVAILABLE`, AOA-27 g) is `NOT_ESTABLISHED`. A window with every hour measured that contains a delivery settled `uncertain` on a timing band is `ESTABLISHED_UNCERTAIN`: its eligible counts, its uncertain counts and the two bounds are published, and it gives no verdict and moves no budget, exactly as `ESTABLISHED_PARTIAL` does (OD-7J-14; AOA-27 h; EB-05). A window with no proven-eligible delivery reports no ratio at all (AOA-27 h). |
| AOA-25 [7J] | **Erasure and holds.** An obligation record contains no content and no subject key. A privacy erasure of a case's material leaves the case and its obligation record in place until the owning domain's reconciliation ends the obligation (7G PRT-06, RPM-12); the record then closes with the class of that resolution. A legal hold has nothing to preserve or pause here. The identifiers in open records are class `PID`, live inside PostgreSQL with no login-role privilege, are never exported, and end under AOA-23. |
| AOA-26 [7J] | **The PostgreSQL representation and the read contract.** Logical requirement; names and DDL belong to the governed migration (IR-7J-41, IR-7J-47). (a) *Hour ledger*: one row per (stream, cohort hour) for every hour from the stream's activation hour, with `assessment` (`OPEN`, `FINAL`) and, for a final row, `measurement` (`MEASURED`, `UNMEASURED`), the cause, the finalizing run and the epoch. Every fold inserts the missing rows up to the current hour. A final row rejects update and delete, and a row cannot become final while the row of the previous hour is open; both are enforced in the database. (b) *Unmeasured declarations*: append-only (stream, first hour, last hour, cause `REGISTRATION_GAP` or `RESTORE_GAP`, the run records that prove it, epoch, database time). (c) *Hourly totals* (changed only while the hour is open), *final rows* (immutable) and *signed correction entries* (append-only), each by (stream, dimension tuple, cohort hour). (d) *Unattributed obligations*: an obligation whose origin time no surviving row holds (a delivery of class `UNMEASURABLE`; an `UNREGISTERED_CASE`) has no cohort hour and is never given one by guess. It is counted per stream under the hour of the one timestamp it does have (the delivery's `created_at`; the case's `first_seen_at`), which is never earlier than its origin. It may therefore belong to a window exactly when that timestamp is at or after the window's start, and while one such obligation exists the window is `NOT_ESTABLISHED` (AOA-24). (e) *Run records*: per committed fold its kind, start and commit time, incarnation and counts. (f) *Read function*: `STABLE`, `SECURITY DEFINER`, executable by the observer principal only. For one indicator it returns, per bounded scope, exactly `window_end`, `hours` (always 672), `measured_hours`, `unmeasured_hours`, `registered`, `not_owed`, `good`, `correction_registered`, `correction_not_owed`, `correction_good`, `excluded_held`, `uncertain_registered`, `uncertain_good`, `unattributed` and `state`. It takes no organization and returns no identifier and no cohort hour. Its testable properties: `measured_hours + unmeasured_hours = 672`; each sum equals the sum of final rows, and each correction the sum of correction entries, over the `MEASURED` hours of `[window_end − 672 h, window_end)` and over nothing else; `registered + correction_registered ≥ 0`; `0 ≤ good + correction_good ≤ (registered + correction_registered) − (not_owed + correction_not_owed)`; two calls on one committed state return the same rows whoever calls. The function returns counts; where it or a recording rule forms a ratio or a bound, a zero denominator yields an absent value (SQL `NULL`; no sample), never 0, 1, `NaN` or an infinity (AOA-27 h). No login role has any privilege on (a) – (e). |
| AOA-27 [OD-7J-12, OD-7J-13] | **Eligibility of a webhook delivery: the event-to-deadline window, lifecycle evidence that bounds when a status change took effect, three classes, one settlement.** Stream `webhook_first_closure` only. **(a) Window.** The eligibility window of delivery `d` is `W = [occurred_at, occurred_at + B)`: it begins at the event's `occurred_at` held in the record as `origin_at`, never at the delivery's `created_at`, and ends at `decide_by = occurred_at + B`, stored at registration with the `B` then in force and never recomputed. It is the same interval the indicator measures. It does not depend on when fan-out created the row, on any claim or admission, or on when the first closure came. **(b) Four different instants of a status change.** The *start* of the lifecycle transaction: this is what `audit.audit_events.occurred_at` holds, because the column defaults to `NOW()` and `audit.fn_insert_audit_event` never supplies it (`072_5J`), and what `organizations.updated_at` holds (`set_updated_at()`, `001_5B`). The *lock*: the moment the transaction holds the organization row's exclusive lock (`FOR UPDATE` in `107_5B5`; the row lock of the compare-and-swap `UPDATE` of 6C §7.6). The *update*: the statement that changes `status`, under that lock. The *commit*: the moment the new status becomes visible to every other transaction, which is the moment 7H ADM-05 means by `t_s` and the only one at which the change is **effective**. No frozen relation records the commit, and no transaction can record its own. **7J never treats a stored time as the commit time.** **(c) Lifecycle evidence** (the refinement of 7I STP-11 approved in OD-7J-13; ERR-7J-15; IR-7J-48). For every committed change of an organization's `status`, the provenance row that 7I's lifecycle functions already write in the transition's transaction carries two further values: a **transition sequence** `k`, per organization, increasing by exactly one, assigned under the organization row lock; and `locked_at`, the database's `clock_timestamp()` read inside that transaction after the lock is held. Because every transition of one organization holds the same row lock until it commits, transition `k + 1` cannot obtain the lock before transition `k` has committed. Hence, writing `c_k` for the unknown commit instant of transition `k`: `locked_at_k < c_k < locked_at_(k+1)`, and **sequence order is commit order**. A rolled-back transaction leaves no row and uses no sequence number. The row is written only inside the lifecycle functions, on a relation no login role can touch (7I STP-11, OLC-01), under a unique (organization, sequence) constraint, so no caller can manufacture, reorder or skip one. **Baseline and removal.** Each organization also has one **baseline**: `base_seq`, `base_state` and `covered_from`, with this meaning and no other: every transition with a sequence above `base_seq` is retained, and at every instant from `covered_from` until transition `base_seq + 1` takes effect the status was `base_state`. It is first written as sequence 0. For an organization that exists when the evidence is installed, the governed migration writes it while holding that organization's row lock, with `base_state` the status it reads under the lock, whatever that is, and `covered_from` the clock read after the lock is held. For an organization created later, the creation transaction writes it with `base_state = ACTIVE` (7I OLC-03). **Nothing is assumed about an organization's status before its `covered_from`.** Old transitions are removed only by the Organization context's guarded maintenance function, never by the fold. Holding the organization row's share lock (the lock 7H's admission points take; an organization whose row is locked is skipped for that pass), it can do two things. *Confirm*: where the latest transition has no confirmation yet, record `confirm_at`, the clock read after the lock is held; the lock proves that this transition took effect before `confirm_at`. *Remove a prefix* up to transition `k`: permitted only when an instant `u_k` that is certainly later than the effect of `k`, namely the `locked_at` of transition `k + 1` or, if `k` is the latest, its `confirm_at`, is older than the evidence lifetime (OD-7J-15: [CAND] 45 days). In one transaction it deletes the transitions up to `k` and sets `base_seq = k`, `base_state` = the to-state of `k`, `covered_from = u_k`. So `covered_from` only moves forward; it is always an instant from which the status is proved, never merely the time of the earliest retained row; and it is always older than the lifetime, so every instant of the last 45 days stays covered. The sequence continues from its last value. **(d) What the fold may read.** One Organization-owned listing function, `SECURITY DEFINER`, `VOLATILE`, procedural, executable only by the owner role of the accounting folds. Its body is two statements, in this order. The first assigns `cutoff := clock_timestamp()`. The second is one query that reads, for one organization and one time range: the organization's baseline (`base_seq`, `base_state`, `covered_from`); the last retained transition whose `locked_at` is before the range, if there is one; every retained transition whose `locked_at` is inside the range; the first retained transition whose `locked_at` is after the range, if there is one (each with its transition sequence, from-state and to-state codes, `locked_at` and an opaque row reference); and the organization's current status, which serves only the consistency check of (g) and is **never evidence of a past status**. The result is bounded: the transitions of the range and at most two more. It returns those rows together with `cutoff`. It raises and returns nothing unless the transaction's isolation level is `READ COMMITTED`. It returns no cause, principal, permission, request, session, key version, reason or `session_user`. The observer principal cannot call it and never chooses the organization: the fold takes the organization from the delivery row it is evaluating, inside the database. 7J reads no audit row for this purpose, holds no privilege on `audit.audit_events` or on the provenance relation, and changes nothing in either. **(e) Bounds on the effective instant.** For each transition the fold stores, in accounting and keyed by the opaque row reference, a **sighting**: a database clock value read by a separate, later statement, after the listing call that first returned that committed row has itself returned, so `c_k < seen_at_k`. With `hi_k` the earliest of `seen_at_k` and `locked_at_(k+1)`: `locked_at_k < c_k < hi_k`. The **band** of transition `k` is the open interval `(locked_at_k, hi_k)`. Inside a band the organization's status is not known. Outside the bands, and at or after `covered_from`, it is known exactly: the to-state of the latest retained transition whose band lies before that instant or, where no retained transition precedes it, `base_state`. Before `covered_from` nothing is known. The status at the start of a window is thus established in one of three ways and no other: by the last retained transition before the window; by the baseline, when the window begins at or after `covered_from` and no retained transition precedes it; or it is not established. The first retained transition after the window confirms the chain (its sequence and from-state must continue what precedes it) and bounds the last band, and it proves that no transition took effect between the window and its own `locked_at`. **The absence of a transition proves a continuous status only forward from the baseline or from a retained transition, and the organization's current status is never read as a past status**: transitions that are no longer retained, or not yet visible, may lie between the window and the evaluation. **The evaluation cutoff `t_e` is the `cutoff` the listing function returns, and nothing else.** "Took effect" has one meaning here: the instant `c_k` from which a new snapshot contains the transition. `t_e` is a clock value read by a statement that finished before the evidence query began. At `READ COMMITTED`, a query inside a `VOLATILE` function takes its snapshot when that query starts, so the evidence snapshot is acquired after `t_e` was read, and every transition with `c_k` before `t_e` is in it. Conversely, a transition the query does not return has `c_k` after `t_e`. The status from the last returned band up to `t_e` is therefore certain. **No clock value read during or after the evidence query is ever a cutoff**: such a value can be later than commits its snapshot does not contain, which is the defect of the previous text (P1-7J-R13). `statement_timestamp()` is the time the client's command was received; it precedes the snapshot of a top-level statement but says nothing reliable about the order of an inner query's snapshot and a later commit, and it is not used. `transaction_timestamp()` and `NOW()` are the transaction's start and are not used. The fold calls the listing function as a statement of its own, never from inside a larger query, and never reuses a result across calls. The fold and the listing function are both `VOLATILE`: a `STABLE` or `IMMUTABLE` declaration would let the inner query run on the calling statement's older snapshot, and the migration's assertion block rejects one. A transaction at `REPEATABLE READ` or `SERIALIZABLE` keeps the snapshot of its first statement for its whole life, which is why the listing function refuses to run there. The proof needs nothing from the fold after the listing returns: however long the fold is then delayed, it classifies against `t_e`, and everything that commits in the meantime is after `t_e`. **A sequence number orders transitions; it never places one before or after a wall-clock deadline. Only the bounds do** (OD-7J-13 conditions 7 – 9). **(f) The three classes.** A record is settled at the first evaluation whose `t_e` is at or after `decide_by` plus the settle delay. An evaluation with an earlier `t_e` settles nothing and the record waits for a later fold: a delayed statement, a lock wait or a slow fold postpones a settlement and cannot falsify one. `held_interval`: at some instant of `W` the organization is certainly not `ACTIVE`. `active_throughout`: at every instant of `W` it is certainly `ACTIVE`. `uncertain`: neither is proved, which happens exactly when `W` meets a band and contains no certainly non-`ACTIVE` instant, basis `TIMING_BAND`. Nothing is assumed in either direction. **(g) Evidence that cannot be trusted or read.** A gap in an organization's sequence, a current status that disagrees with its last transition's to-state, or an uncounted release (7H T-09) for an organization with no transition out of `ACTIVE`: basis `EVIDENCE_FAULT`, class `uncertain`, and the provenance integrity alarm of 7I STP-11. A window that begins before `covered_from` (the evidence was removed under the retention policy, or the window precedes the organization's sequence-0 baseline): basis `EVIDENCE_UNAVAILABLE`, class `uncertain`, whatever the retained transitions or the current status would suggest (OD-7J-15; IR-7J-48). A returned set that does not continue the baseline (the first transition above it is not `base_seq + 1`, or its from-state is not `base_state`), or a from-state that is not the preceding to-state: basis `EVIDENCE_FAULT`. Clock values that contradict the order the row lock imposes (a `locked_at` not later than that of the preceding sequence number; a `cutoff` or a sighting earlier than a `locked_at` it must follow): basis `EVIDENCE_FAULT`, class `uncertain`; a clock step is also alerted from outside (M-279, CLK-06). A window containing either is `NOT_ESTABLISHED` (AOA-24). A listing that fails makes the fold fail as a whole and go stale (EVD-13); it never falls back to `active_throughout`. **(h) Effect on SLI-11.** The reported ratio is read from the tuple (`topic`, `active_throughout`) alone, numerator and denominator together. `held_interval` deliveries are in neither and are reported as `excluded_held`. `uncertain` deliveries are in neither and are reported as `uncertain_registered` and `uncertain_good`; with `gA`, `vA` the good and valid counts of the active tuple and `gU`, `vU` those of the uncertain one, the ratio that any assignment of the uncertain deliveries could produce lies between `gA / (vA + vU − gU)` and `(gA + gU) / (vA + gU)`. These bounds are published with the counts as diagnostics. **They are never turned into a verdict** (OD-7J-14): while a measured hour of the window holds a delivery settled `uncertain`, the window is `ESTABLISHED_UNCERTAIN` (timing band) or `NOT_ESTABLISHED` (evidence fault or unavailable), no objective is reported met or breached on it, and no budget moves (AOA-24; EB-05). **Zero denominators.** The ratio and both bounds are defined only when `vA > 0`; both bound denominators are then at least `vA`. When `vA = 0` (no traffic; or every delivery held; or every delivery uncertain) the ratio and the bounds are absent: not 0, not 1, not `NaN`, not an infinity. No verdict is given and no budget moves on such a window; it is shown as having no proven-eligible deliveries, and `excluded_held` and the uncertain counts say why. **(i) Why a settlement is final.** A transition the evidence query did not return took effect after `t_e` (e), which is after the end of `W`; whatever its audit row or its `locked_at` says, it cannot have changed the status inside `W`. A transition the query returned has its band fixed by what that query returned. So no later evidence can show that a settled `active_throughout` delivery was held, or the reverse, and a settled class is not revised: one compare-and-set, storing class, basis and `t_e`. A band that later evidence would have narrowed leaves the delivery `uncertain`; that is conservative and deterministic. A removal cannot contradict a settlement either: it replaces transitions by a baseline that states the same status from a later instant, in one transaction, so an evidence query sees the state before the removal or after it and never a mixture, and the later state proves less, never something different. **(j) The move and its counts.** A record is counted `active_throughout` provisionally from registration. Settlement confirms it or moves it once. In the same transaction, if the record's cohort hour is open, the hour's totals for the old tuple are decreased and those of the new tuple increased by one registered and by whatever closed and bucket counts it had contributed; if the hour is final, the signed pair of AOA-22 (b) is appended. An hour cannot be finalized measured while one of its records is unsettled (F2), so a pair on a final hour arises only for a delivery registered late into it: `+1` in the provisional class and, if it settles elsewhere, `−1` and `+1`, all in that fold. A second evaluation, the other replica or a re-run fold finds the record settled and changes nothing; a crash rolls the record and the counts back together. At every committed state each delivery is counted in exactly one of the three tuples of its one hour; the three sum to the registered deliveries; no count is negative (AOA-22). **(k) What it does not touch.** The delivery row, its status, `attempt_count`, claim, admission and closure records, their retention, the organization row and every lifecycle and audit relation are read through the functions named here, or not at all, and never written. An uncounted release remains what 7H makes it: not an attempt, not a closure of this obligation, and not by itself evidence of when a hold began. No organization identifier is stored in or exported from accounting. **(l) The trade-off the owner approved** (OD-7J-12 condition 16). Exclusion is of the whole delivery. A brief qualifying suspension inside `W` therefore also removes from SLI-11 a delivery that was already delayed, or already closed in time, while the organization was active. The active-time diagnostic M-296 shows that delay separately. A suspension that takes effect only after `decide_by` excludes nothing: the delivery had already missed `B` and stays valid and not good. |
| AOA-28 [7J] | **Webhook milestones: three streams, one record each, and no milestone that did not happen.** For every delivery `d` the fold registers three records from the delivery row, each with `origin_at = created_at`. Replay and test deliveries are included: these are stage timings of delivery rows and back no first-attempt indicator. `webhook_first_claim` closes `FIRST_CLAIMED` at the `claimed_at` of the claim record with `claim_seq = 1`, which is unique per delivery (7H MR-7H-06); claims with other sequence numbers are not read, so a second claim cannot redefine the first. `webhook_first_admission` closes `FIRST_ADMITTED` at the `admitted_at` of the admission record with the lowest (`claim_seq`, `admission_seq`). That record is the earliest admission, because the claims of one delivery are strictly sequential and all records of a claim are committed before the next claim exists (7H DSM-07 H2, H3); a re-admission in the same claim and the admissions of later claims find the record closed. `webhook_terminal` closes at `completed_at`, with class `DELIVERED`, `DEAD_LETTER` or `CANCELLED`, when the row reaches that status; a terminal status has no exit in V1 (7H §8.1) and a public replay is a new row with its own three records. **A milestone that never happened is never observed.** A delivery that became terminal with no claim record closes its first-claim record `NEVER_CLAIMED`. One that became terminal with no admission record (cancelled while held; dead-lettered by failures that all preceded admission; released uncounted and then cancelled) closes its first-admission record `NEVER_ADMITTED`. Both close at `completed_at`, enter no bucket, and are counted beside the histogram (M-165, M-166). An uncounted release (7H T-09) is not an admission and closes neither record: after a reactivation the first admission of a later claim is the earliest admission, and M-166 records it from `created_at`, suspension time included, as a stage timing and not as an objective. An open record whose delivery row has already been purged is closed `SOURCE_GONE` and observes nothing; that can happen only inside a declared registration gap (AOA-11). Replicas, restart and crash are as AOA-06 and AOA-07; cleanup after the close is irrelevant, because the record holds everything the observation needed. The three streams back no reported indicator: they have cohort hours and a watermark like every stream, no window is read from them, and they are upstream of nothing (F3). |

**Streams.**

| Stream | Obligation identity | Origin time (`origin_at`) and its source | Guaranteed life of that source | Closing fact and its time | Closing classes | Dimensions | Upstream for F3 |
|---|---|---|---|---|---|---|---|
| `outbox_publication` | Outbox row `id` (the `event_id`) | `occurred_at` of the outbox row, registered when the row is visible, whatever its status | While unpublished, unlimited (7D CLN-02 never deletes `PENDING` or `CLAIMED`); after publication at least 7 days | Status `PUBLISHED`: `published_at`. Status `FAILED`: `last_attempt_at`, class `FAILED` | `PUBLISHED`, `FAILED` | `family` | — |
| `consumer_completion` | (logical group, `event_id`) for every `PUBLISHED` outbox row and every group whose registration covers one of its recorded positions (the owed set of 7I ACC-02, ACC-15, read through the payload-free listing of ACC-03) | `occurred_at` of that outbox row | At least 7 days after publication, and for as long as the pair has neither an accounting row nor a case (7I ACC-06) | A completion record: its commit time (7I CEV-03). An accounting row of kind `UNSUBSCRIBED`. A recovery case reaching `RESOLVED`: `resolved_at` | `COMPLETED` (completion record exists, whatever its origin); `NOT_OWED` (`UNSUBSCRIBED`, or resolution `NOT_OWED` / `KNOWN_UNSUBSCRIBED`, or origin obligation `NOT_OWED`); `RECONCILED` (`OWNER_RECONCILED`, `SUPERSEDED_BY_OWNER_RECONCILIATION`); `REJECTED` (`PERMANENTLY_REJECTED_WITH_REASON`); `GOVERNED_AWAY` | `group`, `origin` (`delivery` or `recovery`, from the completion origin) | `outbox_publication` |
| `webhook_fanout` | Delivery `id`, non-replay, non-test | `occurred_at` of the outbox row of the delivery's `event_id` (the delivery row has no `occurred_at`, `063_5I`), read at registration. If that row is already gone, the `origin_at` held by the `consumer_completion` record of (webhook-engine group, `event_id`), which is the same `occurred_at` | At least 7 days after publication; fan-out normally follows within seconds. A delivery for which neither survives is class `UNMEASURABLE`: it has no cohort hour and is counted as unattributed (AOA-26) | The delivery row itself: `created_at` | `CREATED`, `UNMEASURABLE` | `topic` | `consumer_completion` of the webhook-engine group |
| `webhook_first_closure` | Delivery `id`, non-replay, non-test | The same event `occurred_at`, found as for `webhook_fanout` or in the delivery's own `webhook_fanout` record; the delivery's `created_at` and the decision deadline `decide_by` are stored beside it (AOA-27) | As above for the origin; the closure records live with the delivery (30 days at least, 7H MR-7H-07) | The closure record with `attempt_number = 1` (7H DSM-07 H5): `closed_at`. The delivery becoming `CANCELLED` with no counted closure: `completed_at`, class `CANCELLED_UNATTEMPTED` | `FIRST_CLOSED`, `CANCELLED_UNATTEMPTED`, `UNMEASURABLE` | `topic`, `eligibility` (three values; the one dimension settled after registration, once: AOA-27) | `webhook_fanout` |
| `webhook_first_claim` | Delivery `id` | `created_at` of the delivery | With the delivery (30 days at least, 7H MR-7H-07) | The claim record with `claim_seq = 1`: `claimed_at`. Or the row terminal with no claim record: `completed_at` | `FIRST_CLAIMED`; `NEVER_CLAIMED`, `SOURCE_GONE` (no observation) | — | — |
| `webhook_first_admission` | Delivery `id` | `created_at` of the delivery | With the delivery | The admission record with the lowest (`claim_seq`, `admission_seq`): `admitted_at`. Or the row terminal with no admission record: `completed_at` | `FIRST_ADMITTED`; `NEVER_ADMITTED`, `SOURCE_GONE` (no observation) | — | — |
| `webhook_terminal` | Delivery `id` | `created_at` of the delivery | With the delivery | The row reaching `DELIVERED`, `DEAD_LETTER` or `CANCELLED`: `completed_at` | `DELIVERED`, `DEAD_LETTER`, `CANCELLED`; `SOURCE_GONE` (no observation) | `status` | — |
| `webhook_closures` | (delivery `id`, `claim_seq`) | `closed_at` of the closure record: the stream has an origin only | With the delivery | — | The eight closure classes of §19.2 | `closure_class` | — |

Eight streams. The earlier `webhook_stages` stream, which gave one single-close record three closing facts, is withdrawn and replaced by the three milestone streams (AOA-28); the metrics they feed (M-131, M-165, M-166) keep their names. Every stream is in the expected registry with both of its fold kinds (EVD-08, EVD-13), sixteen entries in all, generated from this table, so each of the three new streams is monitored for absence on its own by AL-59.

---

## 7. Metric Naming and Classification

### 7.1 Naming

| ID | Rule |
|---|---|
| MN-01 [FROZEN] | Prefix `platform_` (3E §14.2; 6A §25). |
| MN-02 [7J] | Event-plane metrics: `platform_event_<area>_<thing>_<unit-or-suffix>`. External-delivery metrics keep the frozen stems `platform_webhook_`, `platform_plugin_`, `platform_integration_` (6J §44). Telemetry self-metrics: `platform_telemetry_`. |
| MN-03 [7J] | Suffix by type: Counter `_total`; Histogram a base unit (`_seconds`, `_entries`, `_rows`); Gauge a noun and unit, never `_total`; a timestamp Gauge `_timestamp_seconds`. |
| MN-04 [7J] | Base units only: seconds, bytes, entries, rows, ratio. |
| MN-05 [7J] | **A rate, a ratio or a percentage is never emitted as a metric.** It is a recording rule over counters (§10). This applies to every "success rate", "error rate" and "duplicate rate" named by a frozen handoff. |
| MN-06 [7J] | A metric name is registered once, in the single registry module (3E §14.2), with its type, unit, label set and the closed value set of each label. Registration elsewhere fails the build (IR-7J-04). |

### 7.2 Types

| Fact | Type | Example |
|---|---|---|
| Something happened | Counter | publish outcomes, parks, refusals |
| How much is there now | Gauge | backlog, PEL size, open cases, held rows |
| How old is the oldest | Gauge (seconds) | oldest eligible age, oldest pending age |
| How long did it take, as one process saw it | Histogram (activity) | publish stage duration, receipt-to-commit |
| How long did each obligation take, exactly once | Histogram exported from durable accounted totals (§6.4) | publication latency, end-to-end completion, webhook first closure |
| When did a check last succeed | Gauge (`_timestamp_seconds`) | evidence freshness, hash-chain run |
| Which state is it in | Gauge with a closed `state` label, value 1 for the current state | relay gate, quarantine |
| How often relative to something | Recording rule | every rate and ratio |

### 7.3 Tiers

| Tier | Meaning | Rule |
|---|---|---|
| **C** | Critical correctness indicator. The V1 minimum set | Must be emitted, scraped and alert-wired before the component it describes is activated (§32) |
| **D** | Diagnostic | May be added after activation. Its absence opens no gate. It still obeys every label and privacy rule |

### 7.4 Reconciliation of frozen metric names

| Frozen name (source) | Problem | 7J disposition |
|---|---|---|
| `platform_webhook_deliveries_total{status}` (6J §44.2) | None if it counts terminal transitions | **Kept** as a Counter of deliveries reaching a status (M-123). Current counts by status are a separate Gauge (M-124, M-127) |
| `webhook_delivery_success_rate` (3E §14.2 with `tenant_id`; 6A §25; 6J §44.2) | A rate as a metric (MN-05); no `platform_` prefix; a tenant label in 3E | **Not emitted.** Replaced by the recording rule `slo:webhook_platform_success:ratio` over M-128. CNF-7J-03, ERR-7J-02 |
| `platform_webhook_delivery_duration_seconds` (6J §44.2) | Ambiguous: attempt or delivery | **Kept** for the HTTP attempt (M-129). Creation-to-terminal is M-131 |
| `platform_webhook_delivery_attempts_total{attempt_number}` (6J §44.2) | 6J names one label. 7H later fixed that a closure may have **no** attempt number (T-09) and has one of three send states (DSM-07 H6). One counter cannot carry both without inventing an attempt number | **Kept** as the counter of *counted* closures by `category`, `origin`, `send_state` (M-128). The frozen `attempt_number` breakdown is kept on the sibling `platform_webhook_attempts_by_number_total{attempt_number, closure_class}` (M-163), which by definition has only closures that spent an attempt. Uncounted releases are M-164. CNF-7J-13, ERR-7J-14 |
| `platform_webhook_endpoints_suspended_total` (6J §44.2) | A current count named `_total` | **Compatibility rule:** emitted as the Gauge `platform_webhook_endpoints_suspended` (D tier). The frozen name is not emitted. ERR-7J-03 |
| `platform_webhook_replays_total` (6J §44.2) | None | **Kept** (M-140) |
| `platform_webhook_dead_letter_total` (3E §14.4 alert) | None | **Kept** as the `DEAD_LETTER` value of M-123; the frozen alert expression is re-expressed in AL-25 |
| `platform_plugin_executions_total{plugin_key,capability,status}` and the other 6J §44.3 names | `plugin_key` is bounded only by governance (LBL-08) | **Kept**, under LBL-08 (M-156 … M-158) |
| `platform_plugin_installations_by_version{plugin_key,semver}` (6J §44.3) | `semver` is unbounded | **Not emitted as a metric.** It is a query on `plugins.plugin_installations`. ERR-7J-04 |
| `platform_integration_connections_total{definition_key,status}` (6J §44.1, "gauge") | A Gauge named `_total` | **Compatibility rule:** emitted as the Gauge `platform_integration_connections` (D tier). ERR-7J-03 |
| `plugin_invocation_duration_seconds{plugin_id,tenant_id}` (3E §14.2) | Tenant and entity labels | **Not emitted.** M-157 replaces it. ERR-7J-02 |
| `platform_http_requests_total{…,tenant_id}` (3E §14.2; 6A §25) | Tenant label | Outside the event plane. 7J records the conflict and does not adopt the label (CNF-7J-02, ERR-7J-01); the correction of the API metric belongs to the 6A owner through 7L |

---
## 8. Full Metrics Catalogue

Reading the tables. **T**: `C` Counter, `G` Gauge, `H` Histogram. **Labels**: only the listed labels exist on the metric; each is defined, with its closed value set and size, in §9.1. `region_class` is an external label of the regional stack and is on every series; it is not repeated. **S**: label-value combinations per emitting instance (for a Histogram, before buckets). **I**: the instance class that emits it (§9.3). **Tier**: §7.3. **Dash**: dashboard letter of §22. **Alert**: the alert of §23 that reads it. The semantic definition and the emission boundary are given together in one cell, as "definition — counted at".

**Source and grade.** A source marked "(activity)" is a process counter or histogram: approximate under crashes (DUP-02). "Observer" with "one read" is a state figure: exact at the read. "Observer, from accounted totals" is exported from durable cumulative totals with one increment per obligation identity (§6.4); it is the only source of an exact per-obligation distribution or count. Instance class `P` is a constant series generated by Prometheus recording rules from the expected registry (EVD-08).

Every name below is designed. None is emitted today.

### 8.1 PostgreSQL outbox and relay

Owner: platform event infrastructure. Evidence source for state metrics: `outbox`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-001 | `platform_event_outbox_eligible_rows` | G | rows | Observer | Rows `PENDING` with `available_at <= now`, plus rows `CLAIMED` whose lease has expired — one database read | `family` | 11 | X | C | A, B | AL-02 |
| M-002 | `platform_event_outbox_oldest_eligible_age_seconds` | G | s | Observer | Age of the oldest eligible row, database clock (CLK-02); absent when no row is eligible and the read succeeded with zero rows is exported as `0` — one database read | `family` | 11 | X | C | A, B | AL-01 |
| M-003 | `platform_event_relay_claim_batch_rows` | H | rows | Relay | Rows returned by one claim call — after the claim transaction returns | `relay_role` | 2 | R | D | B | — |
| M-004 | `platform_event_relay_reclaimed_rows_total` | C | rows | Relay | Claimed rows whose previous status was `CLAIMED` — after the claim returns | `relay_role` | 2 | R | D | B | AL-06 |
| M-005 | `platform_event_relay_publish_outcomes_total` | C | entries | Relay | Per-entry result of one publication attempt, by 7D outcome class. `CONFIRMED` only after the 7E criterion `WAITAOF` ≥ `[1, 1]` was positively established (7E WAO-02) — after the adapter returns the outcome | `family`, `outcome` | 66 | R | C | A, B | AL-03, AL-04 |
| M-006 | `platform_event_relay_gate_state` | G | 1 | Relay | 1 for the current gate state of this claim loop, `CLOSED` or `OPEN` — on every loop iteration | `state` | 2 | R | C | A, B | AL-03 |
| M-007 | `platform_event_relay_gate_transitions_total` | C | 1 | Relay | Gate transitions — at the transition | `to_state` | 2 | R | D | B | — |
| M-008 | `platform_event_transport_probe_results_total` | C | 1 | Relay | Result of one non-claiming health probe, per check HP-01 … HP-07 — after the probe returns | `check`, `result` | 14 | R | C | C | AL-09 |
| M-009 | `platform_event_relay_stage_duration_seconds` | H | s | Relay | Wall time of one stage of one batch, monotonic clock — at the end of the stage | `stage` | 3 | R | D | B | — |
| M-010 | `platform_event_outbox_failed_total` | C | rows | Relay | Rows moved to terminal `FAILED` — after mark-failed commits and reports a changed row | `family` | 11 | R | C | B, E | AL-05 |
| M-011 | `platform_event_outbox_failed_rows` | G | rows | Observer | Current `FAILED` rows by 7G disposition state (`UNDISPOSITIONED`, `DISPOSITIONED`) — one database read | `family`, `disposition` | 22 | X | C | B, E | AL-05 |
| M-012 | `platform_event_relay_cas_miss_total` | C | rows | Relay | Mark calls that changed no row (lease expired or intervention) — after the mark function returns | `operation` | 2 | R | C | B | AL-06 |
| M-013 | `platform_event_relay_repeated_rejection_batches_total` | C | 1 | Relay | Batches in which every entry got the same `ROW_REJECTED` category as the previous batch (GATE-09) — at batch end | `family` | 11 | R | D | B | AL-07 |
| M-014 | `platform_event_relay_capability_total` | C | entries | Relay | `RELAY_CAPABILITY` results by sub-cause `NO_ROUTE`, `RELAY_DEFECT` — at outcome classification | `family`, `cause` | 22 | R | C | B | AL-04 |
| M-015 | `platform_event_signal_total` | C | entries | SIGNAL publisher | Class-D signals by result `PUBLISHED`, `DROPPED_TRANSPORT`, `DROPPED_BOUND` — after the publish attempt ends. **Never an input to a durable-loss indicator** | `event_type`, `result` | 12 | V | D | C | — |
| M-016 | `platform_event_relay_contract_anomaly_total` | C | rows | Relay | Rows materialized with an observed contract anomaly and published unrepaired (7D MAT-10) — at materialization | `family`, `anomaly` | 44 | R | D | B | AL-07 |
| M-017 | `platform_event_outbox_publication_latency_seconds` | H | s | Observer, fold-time cumulative from accounted records (§6.4, stream `outbox_publication`) | `published_at − occurred_at` of each outbox row that reached `PUBLISHED`, once per row, computed in the database (CLK-03). **Exact in count; attributed to the time its fold committed, so approximate in time by the fold lag (AOA-13 b).** For graphs, quantile estimates and provisional alerts. The reported window is M-290, never this series. Replicas are combined with `max without (instance)` (DUP-04). Never a Billing time (7B OCC-04) — in the fold transaction that closes the row's obligation record | `family` | 11 | X | C | A, B | AL-01 |
| M-018 | `platform_event_outbox_cleanup_rows_total` | C | rows | Maintenance | Rows deleted, by the predicate that selected them (`PUBLISHED_AGED`, `FAILED_AGED`) — after the cleanup transaction commits | `predicate` | 2 | T | D | B | — |
| M-019 | `platform_event_reconciler_actions_total` | C | 1 | Owner reconcilers | Mandatory-work reconciler results per flow: `CANDIDATE`, `REDISPATCHED`, `FALLBACK_RESOLVED` — at the end of each candidate | `flow`, `action` | 90 | T | C | B | AL-44 |
| M-020 | `platform_event_voice_command_reconcile_total` | C | 1 | Voice reconciler | Stale-command reconciliation results: `EVIDENCE_OBTAINED`, `EVIDENCE_UNOBTAINABLE`, `COMMAND_ISSUED`, `CANCELLED_BUT_RINGING` — per session evaluated | `result` | 4 | T | C | B | AL-45 |
| M-021 | `platform_event_voice_dispatch_held` | G | rows | Observer | Dispatch keys in `SUBMITTING` or `AMBIGUOUS`, and sessions held pending provider evidence, with the oldest age as a second series `…_oldest_age_seconds` — one database read | `state` | 6 | X | C | B | AL-45 |
| M-022 | `platform_event_outbox_eligible_overdue_rows` | G | rows | Observer | Open obligation records of stream `outbox_publication` (rows not yet `PUBLISHED` or `FAILED`) whose age since `origin_at` exceeds the publication boundary of SLI-01, on the database clock — one read of the accounting records | `family` | 11 | X | C | B | AL-01 |

### 8.2 Redis durability and cluster topology

Owner: platform event infrastructure. Evidence source: `redis_cluster`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-030 | `platform_event_redis_cluster_ok` | G | 1 | Observer | 1 when `CLUSTER INFO` reports `cluster_state:ok` — each poll | — | 1 | X | C | A, C | AL-09 |
| M-031 | `platform_event_redis_shard_capable` | G | 1 | Observer | 1 when the shard meets 7E `shard_capable` as far as the observer's commands can see it (one online primary, exactly one replica, replica connected) — each poll | `shard` | 8 | X | C | C | AL-09 |
| M-032 | `platform_event_redis_replica_connected` | G | 1 | Observer | 1 when the shard's sole replica is online and linked — each poll | `shard` | 8 | X | C | C | AL-10 |
| M-033 | `platform_event_redis_replica_lag_seconds` | G | s | Observer | Replica lag as reported by the primary's `INFO replication` — each poll | `shard` | 8 | X | C | C | AL-10 |
| M-034 | `platform_event_redis_waitaof_duration_seconds` | H | s | Relay adapter | Time from sending `WAITAOF` to its reply or timeout — after the reply or timeout | `shard` | 8 | R | C | C | AL-08 |
| M-035 | `platform_event_redis_waitaof_results_total` | C | 1 | Relay adapter | One per `WAITAOF`: `CONFIRMED`, `SHORTFALL_LOCAL`, `SHORTFALL_REPLICA`, `TIMEOUT`, `ERROR`, `CONNECTION_LOST` — after the reply or timeout | `shard`, `result` | 48 | R | C | A, C | AL-08 |
| M-036 | `platform_event_redis_capability_failures_total` | C | 1 | Adapter | Capability evaluation failures by check CAP-01 … CAP-07 — at evaluation | `check` | 7 | R | C | C | AL-09 |
| M-037 | `platform_event_redis_xadd_duration_seconds` | H | s | Relay adapter | Time from sending `XADD` to its reply — after the reply | `shard` | 8 | R | D | C | — |
| M-038 | `platform_event_redis_publish_class_total` | C | entries | Relay adapter | Per-entry 7E classification CL-01 … CL-21 — at classification | `cl_class` | 21 | R | D | C | — |
| M-039 | `platform_event_stream_length_entries` | G | entries | Observer | `XLEN` of the key — each poll | `profile`, `family` | 12 | X | C | C | AL-13, AL-35 |
| M-040 | `platform_event_stream_memory_bytes` | G | bytes | Observer | `MEMORY USAGE` of the key (sampled) — each poll | `profile`, `family` | 12 | X | D | C | AL-13 |
| M-050 | `platform_event_stream_ttl_anomaly_total` | C | 1 | Provisioning; trim worker | Durable key found with a TTL and persisted back (7E TTL-02) — at detection | `family` | 11 | T | C | C | AL-14 |
| M-051 | `platform_event_redis_redirects_total` | C | 1 | Adapter | `MOVED` and `ASK` replies — at the reply | `kind` | 2 | R | D | C | — |
| M-052 | `platform_event_route_failures_total` | C | entries | Relay | Rows whose route resolved to `NONE` — at routing | `family` | 11 | R | C | B | AL-04 |

### 8.3 Stream and group backlog, pending entries, trimming

Owner: platform event infrastructure. Evidence sources: `redis_group`, `trim`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-041 | `platform_event_group_lag_entries` | G | entries | Observer | `lag` from `XINFO GROUPS`. Exported only from a successful reply (EVD-07) — each poll | `group`, `family` | 19 | X | C | A, C | AL-15 |
| M-042 | `platform_event_group_entries_read` | G | entries | Observer | `entries-read` from `XINFO GROUPS`; used to detect a cursor that stopped moving, never as a time — each poll | `group`, `family` | 19 | X | C | C | AL-15, AL-18 |
| M-043 | `platform_event_group_pending_entries` | G | entries | Observer | `pending` from `XINFO GROUPS` — each poll | `group`, `family` | 19 | X | C | A, C | AL-11 |
| M-044 | `platform_event_group_oldest_pending_idle_seconds` | G | s | Observer | Idle time of the oldest pending entry as Redis reports it (CLK-05) — each poll | `group`, `family` | 19 | X | C | A, C | AL-11 |
| M-045 | `platform_event_trim_untrimmed_below_watermark_entries` | G | entries | Trim worker | Entries below `W(K)` not yet trimmed — at the end of a trim run | `family` | 11 | T | D | C | — |
| M-046 | `platform_event_trim_pinned_entries` | G | entries | Trim worker | Entries at or above `W(K)`: retained because a group has not delivered or acknowledged them — at the end of a trim run | `family` | 11 | T | C | C | AL-13 |
| M-047 | `platform_event_trim_entries_total` | C | entries | Trim worker | Entries removed by `XTRIM` — after the command returns | `family` | 11 | T | D | C | — |
| M-048 | `platform_event_group_registered_missing` | G | 1 | Trim worker; observer | Count of (registered group, key) pairs absent from Redis (7E TRM-03) — each run or poll | `family` | 11 | X | C | A, C | AL-12 |
| M-049 | `platform_event_group_unregistered_present` | G | 1 | Trim worker; observer | Count of groups present on a key and absent from the registry (TRM-04) — each run or poll | `family` | 11 | X | C | C | AL-12 |

### 8.4 Consumer processing and idempotency

Owner: platform event infrastructure for the pipeline metrics; each consuming context for its handler outcomes.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-060 | `platform_event_consumer_entries_read_total` | C | entries | Consumer | Entries delivered to this worker, new or reclaimed — on receipt from the gateway | `group`, `delivery` | 24 | C | D | D | — |
| M-061 | `platform_event_consumer_classification_total` | C | entries | Consumer | Classification result C-1 … C-12 — after classification, before any handler | `group`, `class` | 144 | C | C | D | AL-16 |
| M-062 | `platform_event_consumer_held_entries` | G | entries | Observer | Cases in `HOLD` by held class (`COMPATIBILITY`, `KEY_NOT_ONBOARDED`, `CRASH_LOOP_ISOLATION`) and cases `RECONCILIATION_PENDING` for `OBLIGATION_RETIRED` — one ledger read | `group`, `held_class` | 48 | X | C | D, E | AL-16 |
| M-063 | `platform_event_consumer_handler_outcomes_total` | C | events | Consumer | Outcome of one handler attempt. `DURABLY_COMMITTED` only after the owner transaction's commit returned success; `ALREADY_COMMITTED` after the durable guard proved it. **An acknowledgement is not counted here** — after the outcome is known | `group`, `event_type`, `outcome` | 124 | C | C | A, D | AL-15 (SLO) |
| M-064 | `platform_event_consumer_ambiguous_guard_total` | C | events | Consumer | Guard state could not be determined — at the guard read | `group` | 12 | C | C | D | AL-16 |
| M-065 | `platform_event_consumer_unknown_commit_total` | C | events | Consumer | Owner commit outcome unknown (connection lost during commit) — at the commit call | `group` | 12 | C | C | D | AL-16 |
| M-066 | `platform_event_consumer_tenant_mismatch_total` | C | events | Consumer | Tenant-scope mismatch found during classification or handling; each also opens a recovery case (7I AUD-7I-09) — at detection | `group`, `kind` | 24 | C | C | G | AL-30 |
| M-067 | `platform_event_ack_results_total` | C | entries | Gateway | Result of one acknowledgement request as the gateway observed it: `ACKED`, `ZERO`, `ERROR`, `TIMEOUT`, `REFUSED` — after `XACK` returns, or at refusal | `group`, `result` | 60 | G | C | D, G | AL-17 |
| M-068 | `platform_event_consumer_delivery_to_commit_seconds` | H | s | Consumer (activity) | **Handler execution only**: from receipt of the entry by this worker to the owner transaction's commit return, on the worker's monotonic clock. It does not include time in the outbox or in the stream and is never reported as event processing latency (SLI-04, not SLI-17) — at commit return. Observed only for `DURABLY_COMMITTED` | `group` | 12 | C | C | D | — |
| M-069 | `platform_event_commit_to_ack_seconds` | H | s | Consumer | From commit return to the gateway's acknowledgement result `ACKED`, monotonic clock — at the result | `group` | 12 | C | C | D | AL-17 |
| M-070 | `platform_event_consumer_in_flight` | G | entries | Consumer | Entries received and not yet finished by this worker — continuously | `group` | 12 | C | D | D | — |
| M-084 | `platform_event_signal_consumer_total` | C | entries | SIGNAL consumer | SIGNAL entries `READ`, `INGESTED`, `DROPPED` by reason — at each outcome | `result` | 6 | C | D | D | — |
| M-085 | `platform_event_consumer_completion_latency_seconds` | H | s | Observer, fold-time cumulative from accounted records (stream `consumer_completion`) | **End to end**: the completion record's commit time minus the obligation record's `origin_at`, which is the event's `occurred_at` copied from the outbox row at registration and therefore still present after the outbox row is deleted (AOA-19). Once per (group, `event_id`), for closing class `COMPLETED`; `origin = delivery` or `recovery` by the completion's origin. Exact in count, fold-time in attribution (AOA-13 b); the reported window is M-290 — in the fold transaction that closes the record | `group`, `origin` | 24 | X | C | A, D | AL-15 |
| M-086 | `platform_event_obligations_overdue` | G | pairs | Observer | **Unresolved processing obligations, from records that survive outbox cleanup.** Open obligation records of stream `consumer_completion` older than the group's boundary, by disposition: `UNCLASSIFIED` (no accounting row and no case yet), `OPEN_RETRY`, `HOLD`, `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING` (the state of the pair's recovery case). Plus `UNREGISTERED_CASE`: non-terminal `CONSUMER` cases in the recovery ledger that have no obligation record, at any age. A case being open is never a completion; a pair leaves this figure only when a closing fact exists — one read of the accounting records and of the ledger | `group`, `disposition` | 84 | X | C | A, D | AL-15, AL-20 |

### 8.5 Handler-contract generation and cutover

Owner: platform event infrastructure. Evidence source: `ledger` (handler-contract record).

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-071 | `platform_event_consumer_unsupported_version_total` | C | events | Consumer | Entries classified `UNSUPPORTED_VERSION` (C-5, C-8, C-10; 7C UV-08) — at classification | `group` | 12 | C | C | D | AL-16 |
| M-072 | `platform_event_consumer_startup_refusals_total` | C | 1 | Consumer | Worker start refused by the startup or handler-capability gate (VER-7F-05) — at refusal | `group`, `cause` | 72 | C | C | D | AL-16 |
| M-073 | `platform_event_handler_admission_total` | C | 1 | Consumer | Handler-contract admission results and revalidation stops — at the decision | `group`, `result` | 48 | C | C | D | AL-16 |
| M-074 | `platform_event_cutover_transitions_total` | C | 1 | Tooling | Cutover state changes and generation registrations — after the transition commits | `group`, `to_state` | 120 | T | D | D | — |
| M-075 | `platform_event_consumer_beyond_horizon_total` | C | events | Consumer | Beyond-horizon results of the owner adapter (RET-7F-08) — at the result | `group` | 12 | C | C | D, E | AL-20 |
| M-076 | `platform_event_retention_barrier_runs_total` | C | 1 | Maintenance | Retention-barrier waits and evidence-store retirement runs (RET-7F-11, -12) — at run end | `store`, `result` | 18 | T | D | D | — |
| M-077 | `platform_event_draining_intervals` | G | 1 | Observer | Draining intervals open, with the oldest age as `…_oldest_age_seconds` (HCG-18) — one read | `group` | 24 | X | D | D | — |
| M-078 | `platform_event_publication_fence_total` | C | 1 | Tooling | Publication fences established, released, and cutovers abandoned (HCG-21 … -25) — after the step commits | `event` | 3 | T | D | D | — |
| M-079 | `platform_event_pre_fence_set_entries` | G | entries | Observer | Size of the open pre-fence set — one read | `group` | 12 | X | D | D | — |
| M-080 | `platform_event_pre_fence_set_age_seconds` | G | s | Observer | Age of the oldest open pre-fence set, database clock — one read | `group` | 12 | X | C | D | AL-16 |
| M-081 | `platform_event_publication_admission_total` | C | 1 | Relay; tooling | Registered publication attempts by admission state, and quiescence waits (HCG-26, -27) — at each decision | `state` | 4 | R | D | D | — |
| M-082 | `platform_event_origin_provenance_total` | C | 1 | Consumer; tooling | Canonical origin records written, and classifications made from them (HCG-28 … -31) — after the write or classification | `group`, `event` | 24 | C | D | D | — |
| M-083 | `platform_event_key_onboarding_total` | C | 1 | Tooling | Key-onboarding steps completed — after the step commits | `step` | 6 | T | D | D | — |

### 8.6 Retry, parking and dead-letter

Owner: platform event infrastructure. Evidence source: `ledger`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-090 | `platform_event_pel_reclaim_attempts_total` | C | 1 | Sweep | `XAUTOCLAIM` calls issued through the gateway — after the call returns | `group` | 12 | T | D | E | — |
| M-091 | `platform_event_pel_reclaimed_entries_total` | C | entries | Sweep | Entries claimed by a reclaim — after the call returns | `group` | 12 | T | D | E | — |
| M-092 | `platform_event_redis_delivery_count` | H | 1 | Consumer | Redis delivery count reported with a delivered entry — on receipt | `group` | 12 | C | D | E | — |
| M-093 | `platform_event_handler_failures_recorded_total` | C | events | Consumer | **Genuine handler failures**: one per failure-record transaction that committed and changed the case (7G RTY-04, RTY-05), by resulting count 1 … 5. Dependency-gated attempts, holds and crash-loop suspicions are not counted here — after the failure record commits | `group`, `failure_number` | 60 | C | C | E | AL-21 |
| M-094 | `platform_event_crash_loop_total` | C | events | Sweep | Crash-loop suspicion raised, isolation attempted, isolation outcome — at each step | `group`, `event` | 48 | T | C | E | AL-21 |
| M-095 | `platform_event_dependency_gate_state` | G | 1 | Consumer; dispatcher | 1 while this worker's dependency gate is open, by dependency (`OWNER_DB`, `CONTRACT_STORE`, `LEDGER`, `EXTERNAL_STORE`, `KEY_SERVICE`, `SECRET_MANAGER`, `GATEWAY`) — continuously | `group`, `dependency` | 84 | C | C | E | AL-15 (inhibit) |
| M-096 | `platform_event_dependency_gate_open_seconds_total` | C | s | Consumer; dispatcher | Accumulated time with a gate open — on each loop iteration | `group`, `dependency` | 84 | C | D | E, F | — |
| M-097 | `platform_event_parked_total` | C | events | Consumer; sweep; reconciler | Cases entering `PARKED`, by reason. Includes immediate parks and the fifth-failure park — after the parking transaction commits | `group`, `reason` | 144 | C | C | A, E | AL-21 |
| M-098 | `platform_event_holds_total` | C | events | Consumer | Holds created, cleared and expired, by held class — after the case transaction commits | `group`, `held_class`, `event` | 108 | C | D | E | — |
| M-099 | `platform_event_parking_failures_total` | C | events | Consumer | Parking that could not be completed: `COMMIT_FAILED`, `MATERIAL_STORE_REFUSED`, `KEY_SERVICE_UNAVAILABLE` — at the failure. The entry stays pending | `group`, `cause` | 36 | C | C | E | AL-22 |
| M-100 | `platform_event_ack_after_parking_total` | C | entries | Gateway | Acknowledgement results for parked entries, with `ACK_UNCONFIRMED` — after the result | `group`, `result` | 48 | G | C | E | AL-17 |
| M-101 | `platform_event_recovery_cases` | G | cases | Observer | Non-terminal cases by state and recovery class — one ledger read | `group`, `case_state`, `recovery_class` | 420 | X | C | A, E | AL-20 |
| M-102 | `platform_event_recovery_oldest_case_age_seconds` | G | s | Observer | Age of the oldest non-terminal case in each state, database clock — one ledger read | `group`, `case_state` | 60 | X | C | A, E | AL-20 |
| M-103 | `platform_event_reconciliation_pending_oldest_age_seconds` | G | s | Observer | Age of the oldest `RECONCILIATION_PENDING` case by owning context. **Not successful processing** (PRN-10) — one ledger read | `context` | 9 | X | C | E | AL-20 |
| M-104 | `platform_event_outbox_failed_undispositioned_oldest_age_seconds` | G | s | Observer | Age of the oldest `FAILED` row with no 7G disposition — one database read | `family` | 11 | X | C | E | AL-05 |
| M-105 | `platform_event_publisher_redrive_total` | C | rows | Tooling | Redrive requested, succeeded (`PUBLISHED_CONFIRMED`), failed (`PUBLISH_NOT_CONFIRMED`) — after the operation item is recorded | `result` | 3 | T | C | E | AL-22 |

### 8.7 Recovery operations and replay

Owner: platform event infrastructure (event operations). Evidence source: `ledger`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-106 | `platform_event_replay_operations_total` | C | 1 | Tooling | Operation lifecycle transitions (`CREATED`, `APPROVED`, `REJECTED`, `STARTED`, `PAUSED`, `STOPPED`, `CANCELLED`, `COMPLETED`, `EXPIRED`) by mode R2 … R6 — after the ledger transition commits | `mode`, `event` | 45 | T | C | E | AL-47 |
| M-107 | `platform_event_replay_item_results_total` | C | items | Tooling | One per operation item, by the result of 7G §42.4. **A replay item is never counted in M-005 as an original publication nor in M-063 as an original handler outcome**; the handler execution it causes is counted in M-063 with `delivery = replay` on M-060 — after the item result is recorded | `mode`, `result` | 90 | T | C | E | AL-22, AL-47 |
| M-108 | `platform_event_replay_paused_seconds_total` | C | s | Tooling | Accumulated throttle and pause time of running operations — on each scheduler tick | `mode` | 5 | T | D | E | — |
| M-109 | `platform_event_trim_pauses_held` | G | 1 | Observer | Trim pauses currently held by operations, with the oldest age as `…_oldest_age_seconds` — one read | `family` | 22 | X | C | C, E | AL-13 |
| M-110 | `platform_event_replay_operations_active` | G | 1 | Observer | Operations in a non-terminal state, by mode — one ledger read | `mode`, `state` | 25 | X | D | E | AL-47 |
| M-111 | `platform_event_group_retirement_dispositions_total` | C | entries | Tooling | Per-entry dispositions of a governed group retirement — after each is recorded | `group`, `disposition` | 60 | T | D | E | — |
| M-112 | `platform_event_dangling_pel_total` | C | entries | Sweep | Pending entries whose stream entry is missing (7G §39); each opens a `TRANSPORT_INTEGRITY` case — at detection | `group` | 12 | T | C | E, G | AL-19 |
| M-113 | `platform_event_material_digest_mismatch_total` | C | 1 | Tooling; consumer | Replay material whose digest did not verify on read — at verification | `group` | 12 | T | C | E, G | AL-22 |
| M-114 | `platform_event_provenance_runs_total` | C | 1 | Maintenance | Provenance retirement runs and their proofs, by result — at run end | `result` | 3 | T | D | E | — |
| M-115 | `platform_event_ledger_cleanup_rows_total` | C | rows | Maintenance | Ledger rows removed by cleanup — after the cleanup commits | `component` | 6 | T | D | E | — |
| M-116 | `platform_event_recovery_cohort_cases` | G | cases | Observer | For cases that entered `PARKED` between 28 days plus `T` ago and `T` ago (`T` = the SLI-09 target), the count by outcome: `RESOLVED_WITHIN_T`, `RESOLVED_LATE`, `UNRESOLVED`, `RECONCILIATION_PENDING`. Recomputed from the ledger on each read; stateless — one ledger read | `outcome` | 4 | X | C | E | AL-20 |

### 8.8 Gateway authorization and completion evidence

Owner: platform event infrastructure; security for the alerts. Evidence source: `accounting`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-200 | `platform_event_gateway_refusals_total` | C | 1 | Gateway | Requests refused before any Redis command was built, by cause: `UNBOUND_GROUP`, `UNBOUND_KEY`, `UNAUTHENTICATED`, `TOKEN_INVALID`, `TOKEN_EXPIRED`, `TOKEN_REPLAYED_OTHER_SCOPE`, `NOT_PEL_OWNER`, `OPERATION_NOT_PERMITTED` — at refusal | `context`, `cause` | 72 | G | C | G | AL-17 |
| M-201 | `platform_event_gateway_instances_ready` | G | 1 | Gateway | 1 per instance that holds a valid Redis credential, a readable binding registry and a reachable evidence function — continuously | — | 1 | G | C | A, G | AL-48 |
| M-202 | `platform_event_gateway_ack_refused_no_evidence_total` | C | entries | Gateway | Acknowledgement requests refused because no completion record, case, unsubscribed determination or attestation existed (7I GWY-08) — at refusal | `group` | 12 | G | C | G | AL-17 |
| M-203 | `platform_event_unaccounted_cases_total` | C | cases | Reconciler; consumer | Class `V` cases opened, by reason `OBLIGATION_UNACCOUNTED`, `COMPLETION_EVIDENCE_UNATTRIBUTED` — after the case transaction commits | `group`, `reason` | 24 | T | C | A, G | AL-18 |
| M-204 | `platform_event_completion_refusals_total` | C | 1 | Context principals | `fn_record_completion` raised, by cause (`PRINCIPAL`, `TENANT_CONTEXT`, `CLAIM_MISMATCH`, `CODE_INVALID`, `EXPIRED`) — at the database error, counted by the caller from the error class | `group`, `cause` | 60 | C | C | G | AL-17 |
| M-205 | `platform_event_obligation_classification_total` | C | pairs | Reconciler | Exact-position classification of an unaccounted pair (`UNDELIVERED`, `PENDING`, `GONE`, `UNKNOWN`), and pairs that reached `T_obl` — at classification. Advisory history (7I ACC-20) | `group`, `result` | 60 | T | C | G | AL-18 |
| M-206 | `platform_event_obligation_reconciler_watermark_age_seconds` | G | s | Observer | Database clock minus the reconciler's last completed run — one read | — | 1 | X | C | A, G | AL-18 |
| M-207 | `platform_event_outbox_published_held_rows` | G | rows | Observer | `PUBLISHED` rows older than 7 days held by the cleanup interlock (7I ACC-06), their oldest age as `…_oldest_age_seconds`, and `PUBLISHED` rows with no position record as `…_without_position` — one read | `family` | 33 | X | C | B, G | AL-18, AL-19 |
| M-208 | `platform_event_attested_verification_failed_total` | C | 1 | Owner verification | Independent checks of attested groups that failed (7I ACC-08) — at the check | `group` | 2 | T | C | G | AL-18 |

### 8.9 External webhooks

Owner: Integrations (6J) for semantics; platform event infrastructure for emission. Evidence source: `delivery`. The ten figures of the 7H claim, admission and closure taxonomy are mapped in §19.2; a claim, an admission, an abandonment, an uncounted release and a counted closure are never counted by one another's metric.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-120 | `platform_webhook_fanout_total` | C | 1 | Fan-out consumer | Fan-out transactions by result `COMMITTED`, `ZERO_MATCH`, `CLAIM_CONFLICT` — after the transaction ends | `topic`, `result` | 60 | C | C | F | — |
| M-121 | `platform_webhook_fanout_rows` | H | rows | Fan-out consumer | Delivery rows created by one fan-out — after commit | — | 1 | C | D | F | — |
| M-122 | `platform_webhook_fanout_lag_seconds` | H | s | Observer, fold-time cumulative from accounted records (stream `webhook_fanout`) | Delivery `created_at` minus the event's `occurred_at` (read at registration from the outbox row or, if that row is gone, from the upstream obligation record; the delivery row has none), once per non-replay, non-test delivery. A delivery for which neither survives is counted in `platform_webhook_fanout_lag_unmeasurable_total` and in no bucket. Fold-time in attribution (AOA-13 b) — in the fold transaction | `topic` | 40 | X | C | F | AL-23 |
| M-123 | `platform_webhook_deliveries_total` | C | 1 | Fan-out; dispatcher; sweeper (activity) | **Delivery row transitions into a status** (frozen name, 6J §44.2): `PENDING` at creation, and the terminal `DELIVERED`, `DEAD_LETTER`, `CANCELLED`. A return from `DELIVERING` to `PENDING` is a closure (M-128, M-164), not a transition counted here — after the transition commits | `status`, `topic` | 80 | D | C | A, F | AL-25 |
| M-124 | `platform_webhook_pending_due_rows` | G | rows | Observer | `PENDING` rows due now whose organization is `ACTIVE` (dispatch-eligible) — one read | — | 1 | X | C | A, F | AL-23 |
| M-125 | `platform_webhook_oldest_due_pending_age_seconds` | G | s | Observer | Age past `next_attempt_at` of the oldest dispatch-eligible row, database clock — one read | — | 1 | X | C | A, F | AL-23 |
| M-126 | `platform_webhook_held_rows` | G | rows | Observer | `PENDING` rows held because the organization is not `ACTIVE`, by organization status, with the oldest age as `…_oldest_age_seconds`. **`HELD`, not failed** — one read | `org_status` | 6 | X | C | F | AL-27 |
| M-127 | `platform_webhook_delivering_rows` | G | rows | Observer | `DELIVERING` rows, with the oldest claim age as `…_oldest_age_seconds` — one read | — | 2 | X | C | F | AL-24 |
| M-128 | `platform_webhook_delivery_attempts_total` | C | closures | Dispatcher; sweeper (activity) | **Counted closures only**: one per closure record X whose `attempt_number` is not NULL (7H DSM-05, H5), by the frozen category code (7H §9.6, HTP-14; `SUCCESS` for a 2xx), failure origin as recorded, and send state `SENT`, `NOT_SENT` or `UNCERTAIN` exactly as recorded (DSM-07 H6). An uncounted release is never counted here (M-164). Frozen name, 6J §44.2 — after the closure commits | `category`, `origin`, `send_state` | 270 | D | C | A, F | AL-25, AL-26 |
| M-129 | `platform_webhook_delivery_duration_seconds` | H | s | Dispatcher | Wall time of one HTTP attempt, from hand-off to result (frozen name, 6J §44.2) — at the result | `outcome_class` | 4 | D | D | F | — |
| M-130 | `platform_webhook_attempts_at_completion` | H | attempts | Dispatcher | `attempt_count` of a delivery when it becomes terminal — after the terminal transition | `status` | 3 | D | D | F | — |
| M-131 | `platform_webhook_creation_to_terminal_seconds` | H | s | Observer, fold-time cumulative (stream `webhook_terminal`) | `completed_at − created_at`, once per delivery, at the single close of its (`webhook_terminal`, delivery) record when the row reaches `DELIVERED`, `DEAD_LETTER` or `CANCELLED` (AOA-28). A later change cannot add an observation: the record is closed and terminal statuses have no exit — in the fold transaction | `status` | 3 | X | D | F | — |
| M-132 | `platform_webhook_retry_after_seconds` | H | s | Dispatcher | `Retry-After` values observed and the resulting next-eligibility delay — at closure | `kind` | 2 | D | D | F | — |
| M-133 | `platform_webhook_admissions_total` | C | admissions | Dispatcher (activity) | Admission records A inserted (7H T-04a), by `admission_seq` 1 or 2 and by whether a previous-secret signature was planned. `admission_seq = 2` is a re-admission after a configuration change (HTP-18). An admission spends no attempt — after the admission function commits | `admission_seq`, `previous_planned` | 4 | D | C | F | — |
| M-134 | `platform_webhook_secret_unavailable_total` | C | closures | Dispatcher | Closures with category `SECRET_UNAVAILABLE`, by secret role. **Restricted series: internal dashboards G only; never on any tenant surface** (7I TVF-02) — after the closure commits | `secret_role` | 2 | D | C | G | AL-26 |
| M-135 | `platform_webhook_recheck_events_total` | C | 1 | Dispatcher (activity) | Events between admission and hand-off: `RECHECK_MISMATCH`, `GRACE_RECHECK_REPEATED`, `HANDOFF_OVERRUN`, `SENT_UNDER_SUPERSEDED_REVISION`, `DUAL_SIGNATURE_EMITTED` — at each | `event` | 5 | D | D | F | — |
| M-136 | `platform_webhook_admission_lock_wait_seconds` | H | s | Dispatcher | Wait for the endpoint-row lock in admission, with timeouts counted as `…_timeouts_total` — after the lock is taken or times out | — | 2 | D | C | F | AL-24 |
| M-137 | `platform_webhook_stale_claim_releases_total` | C | closures | Sweeper (activity) | Closures written by the sweep (7H T-08, `CLAIM_EXPIRED`, one attempt spent), by the send state the sweep recorded: `UNCERTAIN` when an admission existed, `NOT_SENT` when none did — after the release commits | `send_state` | 2 | T | C | F | AL-24 |
| M-138 | `platform_webhook_fence_events_total` | C | 1 | Dispatcher | Fence mismatches and uncounted releases — at the function result | `event` | 2 | D | C | F, G | AL-24 |
| M-139 | `platform_webhook_cancellations_total` | C | 1 | Sweeper | Cancellations by reason (`ORG_CANCELLED`, `HOLD_EXPIRED`) — after commit | `reason` | 2 | T | D | F | — |
| M-140 | `platform_webhook_replays_total` | C | 1 | API | Public replays (R7) requested, refused by reason, completed (frozen name, 6J §44.2). **Never counted as a new business event** — after the request transaction | `result` | 7 | A | D | F | AL-47 |
| M-141 | `platform_webhook_lineage_depth` | H | 1 | API | Lineage depth of a created replay; test deliveries are counted as `platform_webhook_test_deliveries_total` — after commit | — | 2 | A | D | F | — |
| M-142 | `platform_webhook_egress_rejections_total` | C | 1 | Egress adapter | Destinations rejected by the egress policy, by rule class (the internal rule code is a restricted log field, not a label) — at rejection | `rule_class`, `phase` | 16 | D | C | F, G | AL-32 |
| M-143 | `platform_event_retention_runs_total` | C | 1 | Maintenance | Purge and erasure runs by store and result — at run end | `store`, `result` | 18 | T | C | H | AL-41 |
| M-144 | `platform_webhook_closures_accounted_total` | C | closures | Observer, fold-time cumulative (stream `webhook_closures`) | Every closure record X, once per (delivery, `claim_seq`), in exactly one closure class of §19.2. Exact in count, fold-time in attribution; the reported window for SLI-12a, -12b, -12c is M-295 — in the fold transaction | `closure_class` | 8 | X | C | F | AL-25 |
| M-145 | `platform_webhook_first_closure_overdue_rows` | G | rows | Observer | Open obligation records of stream `webhook_first_closure` whose eligibility is `active_throughout`, older than the SLI-11 boundary since `origin_at`, and whose delivery is not held at the read (its organization is `ACTIVE`; a held row is in M-126, EXT-03). A delivery that missed the boundary before its organization was suspended stays valid and not good in the SLI-11 cohort and returns to this figure on reactivation — one read of the accounting records; the organization status is read inside the function and never returned | — | 1 | X | C | F | AL-23 |

### 8.10 Provider callbacks

Owner: the receiving context (Voice 6D, Integrations 6J). Evidence source: `receipt`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-150 | `platform_callback_receipts_total` | C | receipts | Ingress; processor | Receipts reaching a status. `RECEIVED` only after the receipt row committed, which is before the provider is acknowledged — after the transition commits | `provider`, `status` | 40 | A | C | F | AL-29 |
| M-151 | `platform_callback_duplicates_total` | C | 1 | Ingress | Callbacks recognized as duplicates of an existing receipt — at the dedup result | `provider` | 8 | A | D | F | — |
| M-152 | `platform_callback_verification_failures_total` | C | 1 | Ingress | Signature or authenticity verification failed; nothing is stored beyond the frozen contract — at the failure | `provider`, `cause` | 32 | A | C | F, G | AL-28 |
| M-153 | `platform_callback_processing_failures_total` | C | 1 | Processor | Resolution and extraction failures — at the failure | `provider`, `kind` | 16 | T | C | F | AL-29 |
| M-149 | `platform_callback_acknowledgements_total` | C | responses | Ingress (activity) | 2xx acknowledgements returned to a provider, by what they rested on: `RECEIPT_COMMITTED` (returned on the code path after the receipt transaction committed), `DUPLICATE_OF_RECEIPT` (an existing receipt was found), `NO_RECEIPT` (any other path; must be zero) — when the response is returned | `provider`, `basis` | 24 | A | C | F | AL-29 |
| M-154 | `platform_callback_redispatch_total` | C | 1 | Sweeper | Stale-receipt re-dispatches, and processing attempts per receipt as `platform_callback_processing_attempts` (Histogram) — at re-dispatch; at terminal | `provider` | 16 | T | D | F | — |
| M-155 | `platform_callback_oldest_nonterminal_age_seconds` | G | s | Observer | Age of the oldest receipt in `RECEIVED` or `PROCESSING`, database clock — one read | `provider`, `status` | 16 | X | C | A, F | AL-29 |

### 8.11 Plugin executions and dependencies

Owner: Integrations (6J). Evidence source: `plugins.plugin_executions`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-156 | `platform_plugin_executions_total` | C | 1 | Executor | Execution rows reaching a terminal status (frozen name, 6J §44.3); the category `RATE_LIMITER_UNAVAILABLE` is a status value here — after the row is written | `plugin_key`, `capability`, `status` | 2000 | C | C | F | AL-49 |
| M-157 | `platform_plugin_execution_duration_seconds` | H | s | Executor | Wall time of one callout (frozen name) — at the result | `plugin_key` | 50 | C | D | F | — |
| M-158 | `platform_plugin_scope_denied_total` | C | 1 | Executor | Scope denials (frozen name) — at the denial | `plugin_key` | 50 | C | D | F, G | — |
| M-159 | `platform_plugin_limiter_refusals_total` | C | 1 | Executor | Refusals by the rate limiter (`LIMITED`) and because the limiter gave no decision (`UNAVAILABLE`, fail closed, 7H PLG-15) — at the refusal | `result` | 2 | C | C | F | AL-49 |
| M-160 | `platform_plugin_limiter_breaker_open_seconds_total` | C | s | Executor | Accumulated time with the limiter breaker open — each loop | — | 1 | C | C | F | AL-49 |
| M-161 | `platform_webhook_claims_total` | C | claims | Dispatcher (activity) | Claim records C written (7H T-04): one per claim, whatever happens to it afterwards — after the claim transaction commits | — | 1 | D | C | F | — |
| M-162 | `platform_webhook_abandonments_total` | C | records | Dispatcher (activity) | Abandonment records AB written (7H T-04a, HTP-18): the first admission of a claim abandoned for `CONFIG_CHANGED`, `NOT_SENT`. Not a closure and not an attempt — after the second admission's transaction commits | — | 1 | D | C | F | — |
| M-163 | `platform_webhook_attempts_by_number_total` | C | closures | Dispatcher; sweeper (activity) | Counted closures by the attempt number the closure assigned, clamped, and by closure class. Defined only for closures with a non-NULL `attempt_number`; no value is fabricated for any other closure — after the closure commits | `attempt_number`, `closure_class` | 42 | D | D | F | — |
| M-164 | `platform_webhook_claim_releases_uncounted_total` | C | closures | Dispatcher (activity) | Closures that spent no attempt (7H T-09): disposition `RELEASED_ORG_NOT_ACTIVE`, send state `NOT_SENT`, `attempt_number` NULL. Never an HTTP attempt and never in any attempt metric — after the admission function commits the release | `disposition` | 2 | D | C | F | AL-27 |
| M-165 | `platform_webhook_creation_to_first_claim_seconds` | H | s | Observer, fold-time cumulative (stream `webhook_first_claim`) | `claimed_at` of the claim with `claim_seq = 1` minus the delivery's `created_at`, once per delivery, at the single close of its (`webhook_first_claim`, delivery) record; later claims are not read. A delivery that became terminal with no claim is counted in `…_never_claimed_total` and in no bucket (AOA-28) — in the fold transaction | — | 2 | X | D | F | — |
| M-166 | `platform_webhook_creation_to_first_admission_seconds` | H | s | Observer, fold-time cumulative (stream `webhook_first_admission`) | `admitted_at` of the admission record with the lowest (`claim_seq`, `admission_seq`) minus `created_at`, once per delivery, at the single close of its (`webhook_first_admission`, delivery) record; re-admissions and later claims' admissions are not observed. A delivery that became terminal with no admission is counted in `…_never_admitted_total` and in no bucket (AOA-28) — in the fold transaction | — | 2 | X | D | F | — |
| M-167 | `platform_webhook_creation_to_first_closure_seconds` | H | s | Observer, fold-time cumulative (stream `webhook_first_closure`) | `closed_at` of the closure with `attempt_number = 1` minus the delivery's `created_at` held in the obligation record, once per delivery, at that record's single close. `eligibility` is the record's class at that close: its settled class, or `active_throughout` while provisional (AOA-27); the series is not restated — in the fold transaction | `topic`, `eligibility` | 60 | X | C | F | AL-23 |
| M-168 | `platform_webhook_event_to_first_closure_seconds` | H | s | Observer, fold-time cumulative (stream `webhook_first_closure`) | The same closure's `closed_at` minus the obligation record's `origin_at` (the event's `occurred_at`), observed in the same closing transaction as M-167. Fold-time in attribution; the reported window for SLI-11 is M-290 — in the fold transaction | `topic`, `eligibility` | 60 | X | C | F | AL-23 |
| M-169 | `platform_webhook_claim_to_handoff_seconds` | H | s | Dispatcher (activity) | From the claim's return to the hand-off of the request to the egress adapter, on the worker's monotonic clock. **7H records no hand-off timestamp** (MR-7H-06), so this is an activity estimate and backs no indicator — at hand-off | — | 1 | D | D | F | — |
| M-296 | `platform_webhook_held_active_time_to_first_closure_seconds` | H | s | Observer, fold-time cumulative (stream `webhook_first_closure`) | **Diagnostic for excluded deliveries; backs no indicator and no objective** (OD-7J-12 conditions 14, 15). For a delivery settled `held_interval`, at its single close: the time from the event's `occurred_at` to the first counted closure's `closed_at`, less the time in between at which the organization was certainly not `ACTIVE` (AOA-27 e). Observed only when the bands in that span are too short to move the value to another bucket; otherwise counted in `…_unmeasurable_total` and in no bucket. No value is derived from an audit timestamp — in the fold transaction | `topic` | 21 | X | D | F | — |

### 8.12 Voice accounting finalization (7B IO-7B-21)

Owner: Voice (6D). **No source exists until IO-7B-15 and IO-7B-16** (H-7B-01).

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-146 | `platform_event_voice_unfinalized_conversations` | G | rows | Observer | Conversations ended and not accounting-finalized, with the oldest age as `…_oldest_age_seconds` — one read | — | 2 | X | C | B | AL-46 |
| M-147 | `platform_event_voice_finalization_total` | C | 1 | Finalization worker; reaper | Finalization results `FINALIZED`, `NOOP_ALREADY_FINALIZED`, by path `NORMAL`, `RECOVERY` — after the atomic finalization returns | `path`, `result` | 4 | T | C | B | — |
| M-148 | `platform_event_voice_corrupt_accounting_total` | C | 1 | Finalization worker; reaper | Conversations routed to reconciliation for corrupt usage state or a missing or corrupt service-end time. Nothing is sent to Billing for them (7B OCC-05) — at the routing decision | `cause` | 3 | T | C | B | AL-46 |

### 8.13 Audit integrity and security

Owner: security. Records behind these counters are security-class (§13.3). Evidence sources: audit tables, guarded-function refusals, infrastructure access logs.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-170 | `platform_event_recovery_refusals_total` | C | 1 | Tooling | Refused recovery requests, approvals and executions by cause, `SELF_APPROVAL` included — after the refusal's audit row commits (7I AUD-7I-07) | `mode`, `cause` | 60 | T | C | G | AL-31 |
| M-171 | `platform_event_material_view_total` | C | 1 | View service | Unmasked-material view events: `REQUESTED`, `APPROVED`, `DENIED`, `ACCESSED`, `EXPIRED` — after the audit row commits and, for `ACCESSED`, before release (7I AUD-7I-06) | `event` | 5 | T | C | G | AL-31 |
| M-172 | `platform_event_capability_changes_total` | C | 1 | Tooling | Recovery capability grants and revocations — after the audit row commits | `event` | 2 | T | D | G | — |
| M-174 | `platform_event_egress_policy_refusals_total` | C | 1 | Mutation path; dispatcher | Destinations refused by residency or egress policy, at configuration and at delivery — at refusal | `phase`, `policy` | 8 | D | C | G | AL-32 |
| M-175 | `platform_event_redis_acl_parity_failures` | G | nodes | Provisioning check | Nodes whose ACL digest differs from the governed digest (7I RDS-15) — each parity check | — | 1 | T | C | G | AL-34 |
| M-176 | `platform_event_break_glass_total` | C | 1 | Infrastructure access-log watcher; 6M | Break-glass use on PostgreSQL, Redis, or through the 6M functions — on the access-log record or the audit row | `surface` | 3 | T | C | G | AL-33 |
| M-177 | `platform_event_redis_denied_segment_connections_total` | C | 1 | Network-policy log watcher | Connection attempts to event Redis from a consumer-worker segment. **BLOCKED** (H-7I-04 a) | — | 1 | T | C | G | AL-34 |
| M-178 | `platform_event_gateway_member_anomaly_total` | C | 1 | Observer | Consumer names present in a group that the gateway did not assign (`XINFO CONSUMERS` compared with the gateway's member registry) — each poll | `group` | 12 | X | C | G | AL-17 |
| M-179 | `platform_event_stream_length_drop_total` | C | 1 | Observer | A stream's `XLEN` fell between two polls by more than the trim worker reported trimming in that interval — each poll | `family` | 11 | X | C | G | AL-35 |
| M-180 | `platform_event_unknown_origin_entries_total` | C | entries | Origin check | Entries with no matching outbox row. **BLOCKED** (H-7I-04 b) | `family` | 11 | T | D | G | AL-35 |
| M-181 | `platform_event_payload_org_mismatch_total` | C | events | Consumer | Payload organization differing from the envelope organization — at validation | `group` | 12 | C | C | G | AL-30 |
| M-182 | `platform_db_pool_tenant_setting_at_checkout_total` | C | 1 | Connection pool hook | A connection checked out with a non-empty tenant setting — at checkout, before use; the connection is discarded | `principal_class` | 16 | A | C | G | AL-30 |
| M-183 | `platform_db_tenant_contexts_per_connection` | H | 1 | Connection pool hook | Number of distinct tenant contexts set on one connection between checkout and check-in — at check-in | `principal_class` | 16 | A | D | G | AL-30 |
| M-184 | `platform_telemetry_secret_scan_findings_total` | C | 1 | Scanner | Pattern matches found in a log sink, by pattern class. The matched text is never recorded — at detection | `sink_class`, `pattern_class` | 24 | T | C | G | AL-36 |
| M-185 | `platform_event_key_service_failures_total` | C | 1 | Key-service client | Key-service calls that failed or timed out, by purpose — at the failure | `purpose`, `operation` | 24 | C | C | G | AL-37 |
| M-186 | `platform_event_key_use_outside_grant_total` | C | 1 | Key-service audit watcher | Decrypt on `REPLAY_MATERIAL` or `SEALED_CONTENT` with no live item or grant, and any use outside a key's permitted purpose — on the key-service audit record | `purpose` | 8 | T | C | G | AL-37 |
| M-190 | `platform_audit_write_failures_total` | C | 1 | Every writer | `audit.fn_insert_audit_event()` raised; the enclosing change rolled back (7I AUD-7I-01) — at the error | `principal_class` | 16 | A | C | G | AL-38 |
| M-191 | `platform_audit_chain_last_success_timestamp_seconds` | G | s | Chain job | Time of the last hash-chain run that completed and verified — at run end | — | 1 | T | C | G | AL-38 |
| M-219 | `platform_db_permission_denied_total` | C | 1 | Every database client | SQLSTATE `42501` received, by the principal class of the session and the object class refused (`INTEGRATIONS_5I`, `OTHER_CONTEXT_GUARD`, `GUARD_COLUMN`, `ORGANIZATION_ROW`, `AUTHORIZATION_ROOT`, `CONTENT_COLUMN`, `ERASURE_FUNCTION`, `REQUEST_STATUS`, `OTHER`). The object name and the statement are never recorded — at the error | `principal_class`, `object_class` | 144 | A | C | G | AL-33 |
| M-220 | `platform_event_invariant_violations` | G | rows | Observer | Rows found by a fixed list of invariant queries: admission with no audit row for its `config_revision`; guard-column state with no provenance row; organization status or residency change with no provenance or audit row; `ACTIVE` membership or role change with no tenant-path audit row; request status disagreeing with its registry hold; `gdpr_erasure` disconnect with no completed operation; an erased state with no durable journal intent; an unaccounted pair whose outbox row is gone (`capture_source_missing`) — one read per invariant | `invariant` | 12 | X | C | G | AL-33 |
| M-221 | `platform_event_proof_refusals_total` | C | 1 | Guarded-function callers | A transition, lifecycle, request or provisioning function refused a token or an action proof, by cause (`MISSING`, `WRONG_CODE`, `EXPIRED`, `CONSUMED`, `WRONG_ACTION`, `WRONG_ORGANIZATION`, `REVOKED_SESSION`, `INCARNATION`) — at the error | `function_class`, `cause` | 48 | A | C | G | AL-33 |
| M-222 | `platform_event_closed_path_calls_total` | C | 1 | Database clients | Calls refused on a closed path: a frozen three-argument lifecycle signature; an update of an approved plugin version; a refused edge out of `ON_HOLD` — at the error | `path` | 6 | A | C | G | AL-33 |
| M-223 | `platform_event_org_erasure_refusals_total` | C | 1 | Tooling | Refused organization-erasure requests, approvals and executions by cause, `SELF_APPROVAL` included — after the audit row commits | `cause` | 8 | T | C | G, H | AL-31 |
| M-224 | `platform_event_org_erasure_approved_oldest_age_seconds` | G | s | Observer | Age of the oldest erasure operation `APPROVED` and not executed — one read | — | 1 | X | C | H | AL-41 |
| M-225 | `platform_event_provisioning_refusals_total` | C | 1 | Provisioning | Enterprise or residency provisioning refused, by cause — at refusal | `cause` | 6 | T | C | G | AL-33 |
| M-226 | `platform_event_authorization_issuer_up` | G | 1 | Tooling | 1 when the platform authorization issuer answered its health check — each check | — | 1 | T | C | G | AL-48 |
| M-230 | `platform_event_ev097_admission_rejected_total` | C | 1 | Campaign producer | EV-097 admissions rejected by PV-7I-01 — at rejection | — | 1 | A | D | G | — |

### 8.14 Retention and erasure

Owner: privacy and security; platform event infrastructure for emission. Evidence sources: `journal`, `retention`.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-173 | `platform_event_erasure_runs_total` | C | 1 | Erasure functions | Erasure runs by store and result; the lag of each run is M-253 — after the run's audit row commits | `store`, `result` | 18 | T | C | H | AL-41 |
| M-192 | `platform_event_erasure_steps_open` | G | steps | Observer | Erasure steps not `VERIFIED` or `WITHDRAWN`, by journal state — one read | `journal_state`, `kind` | 12 | X | C | H | AL-39 |
| M-193 | `platform_event_erasure_oldest_step_age_seconds` | G | s | Observer | Age of the oldest open step in each journal state, database clock — one read | `journal_state` | 6 | X | C | H | AL-39, AL-41 |
| M-194 | `platform_event_bodies_past_lineage_deadline` | G | rows | Observer | Webhook bodies and previews present past their lineage or `CANCELLED` deadline — one read | `kind` | 2 | X | C | H | AL-41 |
| M-195 | `platform_event_material_by_deadline_band` | G | rows | Observer | Replay material by distance to its limit: `WITHIN_14_DAYS`, `AT_LIMIT`, `PAST_LIMIT` — one read | `band` | 3 | X | C | H | AL-41 |
| M-197 | `platform_event_day83_job_total` | C | 1 | Day-83 job | Outcomes of the day-83 re-validation job (OD-7I-11) — at run end | `outcome` | 4 | T | C | H | AL-41 |
| M-210 | `platform_event_journal_append_failures_total` | C | 1 | Journal writer | Journal appends that were not durably confirmed — at the failure. Erasure waits (7I JRN-20) | `record_type` | 12 | T | C | H | AL-39 |
| M-211 | `platform_event_journal_append_duration_seconds` | H | s | Journal writer | Time to a durably confirmed append — at confirmation | — | 1 | T | C | H | AL-39 |
| M-212 | `platform_event_journal_waiting_steps` | G | steps | Observer | Steps and time-based batches at `INTENT_REQUESTED` or `INTENT_DURABLE`, with the nearest erasure deadline among them as `…_nearest_deadline_seconds` — one read | `journal_state`, `kind` | 8 | X | C | H | AL-39 |
| M-213 | `platform_event_journal_last_append_timestamp_seconds` | G | s | Journal writer | Time of the last confirmed append — at confirmation | — | 1 | T | C | H | AL-39 |
| M-214 | `platform_event_journal_tamper_attempts_total` | C | 1 | Object-store access-log watcher | Delete or overwrite attempts on the journal prefix — on the access-log record | `operation` | 2 | T | C | G, H | AL-40 |
| M-215 | `platform_event_journal_checkpoint_age_seconds` | G | s | Observer | Database clock minus the time of the last checkpoint — one read | — | 1 | X | C | H | AL-39 |
| M-216 | `platform_event_database_incarnation_state` | G | 1 | Restore reconciler; observer | 1 for the current state of this database incarnation: `ACTIVE`, `QUARANTINED`, `RECONCILING`, `FAILED_CLOSED` — continuously | `state` | 4 | X | C | H | AL-40 |
| M-217 | `platform_event_erasure_deadline_rows` | G | rows | Observer | Erasure obligations by distance to their deadline: `APPROACHING`, `MISSED` — one read | `store`, `band` | 12 | X | C | H | AL-41 |
| M-218 | `platform_event_incarnation_refusals_total` | C | 1 | Guarded-function callers | A guarded function refused on an incarnation mismatch (a worker that survived a restore) — at the error | `function_class` | 6 | A | C | H | AL-40 |
| M-251 | `platform_event_content_overdue_rows` | G | rows | Observer | Rows past their content deadline whose content is still present (the overdue-unprocessed count of 7I CAG-12) — one read | `store` | 6 | X | C | H | AL-41 |
| M-252 | `platform_event_content_overdue_oldest_age_seconds` | G | s | Observer | Age past the deadline of the oldest such row — one read | `store` | 6 | X | C | H | AL-41 |
| M-253 | `platform_event_deadline_to_disposition_seconds` | H | s | Retention pass | From a row's content deadline to its erasure or its seal, database clock — in the erasing or sealing transaction | `store`, `disposition` | 12 | T | C | H | AL-41 |
| M-254 | `platform_event_content_guard_denials_total` | C | 1 | Guarded content functions | Content reads or copies denied by the guard, by path and access code (7I CAG-15) — at the denial | `path`, `access_code` | 60 | A | C | G, H | AL-43 |
| M-255 | `platform_event_content_deadline_unknown_total` | C | 1 | Guarded content functions | Reads refused as `DEADLINE_UNKNOWN` — at the refusal | `path` | 10 | A | C | H | AL-43 |
| M-256 | `platform_event_pre_handoff_aborts_total` | C | 1 | Dispatcher; API | Operations aborted before an external handoff because the deadline passed (7I CAG-10) — at the abort | `path` | 10 | D | D | H | — |
| M-258 | `platform_event_key_retirement_blocked` | G | versions | Observer | Key versions whose retirement is blocked by a retained or held record that references them (7I HLD-08, KEY-19) — one read | `purpose` | 8 | X | D | H | — |
| M-262 | `platform_event_retention_pass_last_success_timestamp_seconds` | G | s | Retention pass | Time of the last completed retention pass, per store — at pass end | `store` | 6 | T | C | H | AL-41 |

### 8.15 Legal holds, sealing and subject-index certification

Owner: privacy and security. Evidence sources: `retention`, `index`. **No series carries an organization, a subject key or a hold identifier.** Where the frozen handoff says "by organization", the series counts organizations in a state.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-196 | `platform_event_holds_past_review` | G | holds | Observer | `PLATFORM` holds whose review date has passed. The hold stays in force (7I HLD-05) — one read | `scope_type` | 3 | X | C | H | AL-42 |
| M-227 | `platform_event_holds_active` | G | holds | Observer | Active holds by kind (`REQUEST`, `PLATFORM`) and scope type, with the oldest age as `…_oldest_age_seconds` — one read | `hold_kind`, `scope_type` | 12 | X | C | H | — |
| M-228 | `platform_event_hold_gate_wait_seconds` | H | s | Erasure functions | Time an erasure or purge transaction waited on the organization hold gate — after the lock is taken | — | 1 | T | D | H | — |
| M-229 | `platform_event_request_function_refusals_total` | C | 1 | API | Data-subject request functions that refused, by cause — at the error | `cause` | 8 | A | C | G, H | AL-33 |
| M-231 | `platform_event_index_relations_unverified` | G | 1 | Observer | Count of (organization, relation) pairs in verification state `UNVERIFIED`, with the oldest age as `…_oldest_age_seconds` — one read | `relation_class` | 20 | X | C | H | AL-43 |
| M-232 | `platform_event_hold_placement_refusals_total` | C | 1 | Hold functions | Hold placements refused, by reason (`INDEX_UNVERIFIED`, `NOT_CERTIFIED`, `PROOF`, `OTHER`) — after the refusal's audit row commits | `hold_kind`, `reason` | 8 | T | C | H | AL-43 |
| M-233 | `platform_event_request_holds_by_contact_set` | G | holds | Observer | Request holds by size class of their contact set: `EMPTY`, `ONE`, `MANY` — one read | `size_class` | 3 | X | C | H | AL-43 |
| M-234 | `platform_event_rows_skipped_held_total` | C | rows | Erasure functions | Rows a pass skipped as held, by store, hold kind, basis and path kind — in the pass | `store`, `hold_kind`, `path_kind` | 72 | T | C | H | — |
| M-235 | `platform_event_unattributed_rows` | G | rows | Observer | Content-bearing rows with no attribution reference — one read | `store` | 6 | X | C | H | AL-43 |
| M-236 | `platform_event_content_rows_created_total` | C | rows | Writers | New content-bearing rows, by whether they were created attributed. Denominator of the unattributed share — after commit | `store`, `attributed` | 12 | A | D | H | — |
| M-237 | `platform_event_retention_decisions` | G | records | Observer | Retention-decision records by status and reason (`LEGACY_HISTORY_UNKNOWN` included), with the oldest age as `…_oldest_age_seconds` and those opened with under 48 hours to the deadline as `…_late_opened` — one read | `status`, `reason` | 72 | X | C | H | AL-42 |
| M-238 | `platform_event_index_completeness_failures_total` | C | 1 | Completeness check | Subject-index completeness failures by relation class — at the check | `relation_class` | 10 | T | C | H | AL-43 |
| M-240 | `platform_event_unauthorized_retention_incidents` | G | incidents | Observer | Open unauthorized-retention incidents by age band and escalation level. **Open until a disposition closes it; no metric and no alert closes it** (7I SEAL-05) — one read | `age_band`, `escalation_level` | 16 | X | C | A, H | AL-42 |
| M-241 | `platform_event_sealed_items` | G | rows | Observer | Sealed items by store and basis (`HELD`, `UNDECIDED`, `EXCEPTION`). **Sealed is not erased** — one read | `store`, `basis` | 18 | X | C | H | AL-42 |
| M-242 | `platform_event_sealing_backlog_rows` | G | rows | Observer | Rows eligible for sealing and not yet sealed, with the oldest age as `…_oldest_age_seconds` — one read | `store` | 12 | X | C | H | AL-41 |
| M-243 | `platform_event_seal_failures_total` | C | 1 | Sealing function | Sealing that could not complete: `JOURNAL`, `VAULT_WRITE`, `KEY_SERVICE` — at the failure. Content stays denied in its store (7I CAG-12) | `cause` | 3 | T | C | H | AL-41 |
| M-244 | `platform_event_retention_exceptions_total` | C | 1 | Decision functions | Exceptions authorized, expired, refused by reason; currently in force as the Gauge `platform_event_retention_exceptions_in_force` — after the audit row commits | `event` | 7 | T | C | H | AL-42 |
| M-245 | `platform_event_association_reviews_total` | C | 1 | Decision functions | Historical-association reviews opened, confirmed, released; determinations recorded — after the audit row commits | `event` | 4 | T | D | H | — |
| M-246 | `platform_event_holds_multi_contact_closure` | G | holds | Observer | Holds whose identity closure spans more than one contact — one read | — | 1 | X | D | H | — |
| M-247 | `platform_event_sealed_inspection_total` | C | 1 | Inspection function | Sealed-content inspections: `REQUESTED`, `APPROVED`, `DENIED`, `ACCESSED`, by binding (`DECISION`, `HOLD`) — after the audit row commits and, for `ACCESSED`, before any byte is released | `event`, `binding` | 8 | T | C | G, H | AL-43 |
| M-248 | `platform_event_index_key_versions_verify` | G | versions | Observer | Index key versions in `VERIFY`, with the edge count under them as `…_edges`, and edges under a compromised version as `…_compromised_edges` — one read | — | 3 | X | C | H | AL-43 |
| M-249 | `platform_event_index_key_read_failures_total` | C | 1 | Hold function; resolver | Failures to read an index key — at the failure. The index is then never read as "no match" (7I HLD-19) | — | 1 | T | C | H | AL-43 |
| M-250 | `platform_event_erasure_lock_cycle_aborts_total` | C | 1 | Erasure functions | Erasure transactions aborted by a lock cycle — at the abort | `store` | 6 | T | D | H | — |
| M-257 | `platform_event_sealed_restore_attempts_total` | C | 1 | Database clients; restore reconciler | Attempts to return sealed content to its store, refused (7I SEAL-10), and restore-time re-seals — at the refusal or re-seal | `kind` | 2 | T | C | G, H | AL-43 |
| M-259 | `platform_event_organizations_by_certification` | G | organizations | Observer | Count of organizations in each certification state `FROM_ORIGIN`, `FROM_T0`, `NOT_CERTIFIED` — one read | `cert_state` | 3 | X | C | H | AL-43 |
| M-260 | `platform_event_certification_changes_total` | C | 1 | Certification functions | Certifications recorded, demoted, withdrawn; `FROM_T0` limits accepted — after the audit row commits | `event` | 4 | T | C | H | AL-43 |
| M-261 | `platform_event_certification_failures_total` | C | 1 | Certification functions | Failed certifications by cause — at the failure | `cause` | 6 | T | C | H | AL-43 |

### 8.16 Monitoring subsystem health

Owner: SRE.

| ID | Name | T | Unit | Source | Definition — counted at | Labels | S | I | Tier | Dash | Alert |
|---|---|---|---|---|---|---|---:|---|---|---|---|
| M-270 | `platform_telemetry_evidence_last_success_timestamp_seconds` | G | s | Observer | Time of the last complete, successful read of an evidence source (EVD-01) — at read end | `source` | 11 | X | C | I | AL-50 |
| M-271 | `platform_telemetry_evidence_read_failures_total` | C | 1 | Observer | Failed or timed-out reads of an evidence source, by cause — at the failure | `source`, `cause` | 44 | X | C | I | AL-50 |
| M-272 | `platform_telemetry_heartbeat_timestamp_seconds` | G | s | Every event-plane workload | Time of the workload's last main-loop iteration (claim loop, read loop, dispatch loop, sweep, pass). `group` is the consumer group for a consumer worker and `none` otherwise — each iteration | `component`, `group` | 32 | W | C | I | AL-51 |
| M-273 | `platform_telemetry_dropped_total` | C | items | Every workload; collector | Spans, log lines and instrumentation errors dropped or swallowed (ISO-03, ISO-04), by signal and cause — at the drop | `signal`, `cause` | 12 | W | C | I | AL-52 |
| M-274 | `platform_telemetry_export_queue_ratio` | G | ratio | Every workload | Fill of the span export queue — continuously | — | 1 | W | D | I | — |
| M-275 | `platform_telemetry_label_rejections_total` | C | 1 | Registry | Observations refused because a label value was outside its closed set (LBL-06) — at the refusal | `metric_group` | 16 | W | C | I | AL-53 |
| M-276 | `platform_telemetry_series_by_group` | G | series | Cardinality job | Active series per metric group, from the Prometheus TSDB status — each run | `metric_group` | 16 | X | C | I | AL-53 |
| M-277 | `platform_telemetry_watchdog` | G | 1 | Prometheus rule | Constant 1. The always-firing alert built on it is the dead-man signal (§25.2) | — | 1 | X | C | I | AL-54 |
| M-278 | `platform_telemetry_notification_failures_total` | C | 1 | Alertmanager | Notifications that a receiver did not accept — at the failure | `receiver_class` | 4 | X | C | I | AL-55 |
| M-279 | `platform_telemetry_clock_offset_seconds` | G | s | Node agent | Offset of the node clock from its time source — each check | — | 1 | W | C | I | AL-56 |
| M-280 | `platform_telemetry_restricted_queries_total` | C | 1 | Query broker | Restricted-telemetry query grants and refusals, by tier and result — after the access record is written (TQA-08) | `tier`, `result` | 12 | T | C | G, I | AL-57 |
| M-281 | `platform_telemetry_slo_federation_lag_seconds` | G | s | SLO-history Prometheus | Age of the newest federated SLO aggregate — each scrape | — | 1 | X | C | I | AL-58 |
| M-282 | `platform_telemetry_config_changes_total` | C | 1 | Deployment path | Changes to a telemetry sink, an export destination, an alert route, a notification template or the label registry — after the `PLATFORM_CONFIG_CHANGED` audit row commits | `object_class` | 6 | T | C | G, I | AL-57 |
| M-283 | `platform_telemetry_observation_fold_last_success_timestamp_seconds` | G | s | Observer | Time of the last committed fold of a stream, per fold kind. A fold that found nothing to do still commits and advances this (EVD-13) — after the fold returns | `stream`, `fold_kind` | 16 | X | C | I | AL-59 |
| M-284 | `platform_telemetry_observation_unaccounted` | G | rows | Observer | Per stream: visible source rows with no obligation record; the age of the oldest as `…_oldest_age_seconds`; open obligation records as `…_open_records`; and the stream's `…_accounting_epoch` (AOA-14). For `webhook_first_closure` also `platform_telemetry_observation_unsettled_oldest_window_age_seconds`: the age, since the start of its eligibility window, of the oldest record not yet settled, which shows before the fact that a record is approaching the lifetime of its lifecycle evidence (AOA-27 c, g) — one read | `stream` | 33 | X | C | I | AL-59, AL-60 |
| M-285 | `platform_telemetry_observation_unmeasured_seconds_total` | C | s | Observer, from the run records and declarations | Accumulated length of declared unmeasured intervals (AOA-11, AOA-14), and `…_unmeasured_cohort_hours_total` by `cause` (`REGISTRATION_GAP`, `RESTORE_GAP`): cohort hours finalized `UNMEASURED`. Durable; read from PostgreSQL. A late fold adds nothing here; only a declaration of permanent loss does — in the fold that appends the declaration or finalizes the hour | `stream`, `cause` | 24 | X | C | I | AL-59 |
| M-286 | `platform_telemetry_expected_source` | G | 1 | Prometheus recording rule generated from the expected registry (EVD-08) | Constant 1 per evidence source that must be reporting, with its registry state — every rule evaluation | `source`, `state` | 11 | P | C | I | AL-50 |
| M-287 | `platform_telemetry_expected_component` | G | 1 | Prometheus recording rule generated from the expected registry | Constant 1 per (component, group) that must be heart-beating, with its state; and `platform_telemetry_expected_component_max_age_seconds` with the heartbeat age permitted for it — every rule evaluation | `component`, `group`, `state` | 64 | P | C | I | AL-51 |
| M-288 | `platform_telemetry_expected_shard` | G | 1 | Prometheus recording rule generated from the expected registry | Constant 1 per shard position of the active topology generation that owns a durable key — every rule evaluation | `shard`, `state` | 8 | P | C | I | AL-08, AL-09 |
| M-289 | `platform_telemetry_expected_stream` | G | 1 | Prometheus recording rule generated from the expected registry (EVD-08, EVD-13) | Constant 1 per mandatory accounting stream and fold kind, with its registry state; and `platform_telemetry_expected_stream_max_age_seconds` with the permitted age of that fold — every rule evaluation | `stream`, `fold_kind`, `state` | 32 | P | C | I | AL-59 |
| M-290 | `platform_event_slo_window_obligations` | G | obligations | Observer | **The reported event-time window.** For one indicator and scope, over the 672 consecutive cohort hours that end at the stream's finalization watermark (AOA-21): the sums over its measured hours `registered`, `not_owed`, `good`; the signed post-final corrections on those hours `correction_registered`, `correction_not_owed`, `correction_good` (a value can be negative; the sum with its final count cannot); for SLI-11 `excluded_held` (deliveries of those hours settled `held_interval`) and `uncertain_registered`, `uncertain_good` (those settled `uncertain`, from which the two bounds of AOA-27 h are computed); `unmeasured_hours`; `unattributed`. Computed in the database; independent of fold time and of scrape time. Scopes: `family` for SLI-01, `topic` for SLI-11, `group` for SLI-17 — one read of the window function | `indicator`, `scope`, `part` | 473 | X | C | A, I | AL-60 |
| M-291 | `platform_event_slo_window_state` | G | 1 | Observer | 1 for the current state of an indicator's window: `ESTABLISHED`, `ESTABLISHED_PARTIAL`, `ESTABLISHED_UNCERTAIN`, `NOT_ESTABLISHED`, `UNKNOWN` (AOA-24). Only `ESTABLISHED` carries a verdict. Its absence is read as `UNKNOWN` — one read of the window function | `indicator`, `scope`, `state` | 230 | X | C | A, I | AL-60 |
| M-292 | `platform_event_slo_cohort_final_through_timestamp_seconds` | G | s | Observer | The finalization watermark of a stream: the end of the last hour of the unbroken final prefix of its hour ledger (AOA-21). It advances across measured and unmeasured final hours alike and stops at the first open hour — one read | `stream` | 8 | X | C | I | AL-59, AL-60 |
| M-293 | `platform_event_slo_post_final_corrections_total` | C | obligations | Observer, from the durable correction entries | Correction entries appended to already final cohort hours (AOA-22), by kind: `registered`, `not_owed`, `good` (late registration or classification); `eligibility_moved` (an obligation settled out of the provisional `active_throughout` class after its hour was final, which is one `−1` and one `+1` in the database, AOA-27 j); `into_unmeasured` (entries on an unmeasured hour, which enter no window). A restated window is visible here — in the fold transaction | `stream`, `kind` | 40 | X | C | I | AL-60 |
| M-294 | `platform_event_slo_cohort_final_obligations` | G | obligations | Observer | The `registered`, `not_owed` and `good` counts of the most recently finalized cohort hour per indicator and scope when that hour is `MEASURED`; for an `UNMEASURED` hour no count is exported (EVD-02). Beside it, per stream, that hour's end as `platform_event_slo_cohort_final_hour_timestamp_seconds` and its measurement as `platform_event_slo_cohort_final_hour_measured` (1 or 0). Sampled by the SLO-history store as the per-cohort record (§27.2) — one read | `indicator`, `scope`, `part` | 145 | X | C | I | — |
| M-295 | `platform_event_slo_window_closures` | G | closures | Observer | Sums of closure records by closure class over the measured hours of the 672 consecutive cohort hours that end at the watermark of stream `webhook_closures` (cohort by `closed_at`), with the late-registered corrections as `…_corrections` and the window's unmeasured hours as `…_unmeasured_hours`. The reported window of SLI-12a, -12b, -12c — one read of the window function | `closure_class` | 17 | X | C | F, I | AL-60 |

### 8.17 Minimum critical set for V1

The V1 minimum is every Tier **C** metric of the component being activated, as listed per gate in §32. Counts by tier are in §9.4 (computed from the tables above).

---
## 9. Cardinality and Cost Policy

### 9.1 Label allow-list

A label not in this table does not exist. A value not in the label's closed set is not emitted (LBL-06).

| Label | Closed value set | Size | Source of the set |
|---|---|---:|---|
| `region_class` | The abstract region class of the stack (external label; one value per stack) | 1 | 4I §9.2 `RegionRef` class, never a cloud region name |
| `family` | The 11 durable family tokens | 11 | 7E §14.1 |
| `profile` | `d`, `s` | 2 | 7E §15.1 |
| `event_type` | The 107 durable and 4 SIGNAL exact types. Used only where the table restricts the combinations | 111 | 7E §14.1; 7D CLD-07 |
| `group` | The 11 durable groups and 1 SIGNAL group | 12 | 7E §29 |
| `context` | The 9 consuming contexts | 9 | 7I CTX-01 |
| `topic` | The 19 public topics and `platform.test` | 20 | 7I §11.2; 7H T-02 |
| `outcome` (relay) | The six classes of OBS-7D-05 | 6 | 7D §41.2 |
| `outcome` (handler) | The four handler outcomes | 4 | 7F §36.4 |
| `class` | C-1 … C-12 | 12 | 7F §11 |
| `cl_class` | CL-01 … CL-21 | 21 | 7E §25 |
| `check` | CAP-01 … CAP-07, or HP-01 … HP-07 | 7 | 7E |
| `recovery_class` | The seven recovery classes | 7 | 7G §10.1 |
| `case_state` | The five non-terminal case states | 5 | 7G §24.1 |
| `reason` (parking) | The closed parking and case reasons of 7G §22, plus `OBLIGATION_UNACCOUNTED`, `COMPLETION_EVIDENCE_UNATTRIBUTED` | ≤ 12 | 7G §22; 7I ERR-7I-10, ERR-7I-15 |
| `mode` | R2 … R6 | 5 | 7G §30 |
| `result` (replay item) | The results of 7G §42.4 | 18 | 7G §42.4 |
| `status` (delivery) | The five V1 statuses | 5 | 7H §8.1 |
| `status` (receipt) | The five receipt statuses | 5 | `062_5I` |
| `category` | The closed category codes of 7H §9.6 and HTP-14, plus `SUCCESS` | ≤ 18 | 7H HTP-14 |
| `origin` | `RECEIVER`, `DESTINATION`, `PLATFORM`, `TENANT_CONFIGURATION`, and `NONE` for success | 5 | 7H HTP-14 |
| `send_state` | `SENT`, `NOT_SENT`, `UNCERTAIN`, exactly as the closure records it. `UNCERTAIN` is never folded into another value, into `other`, or dropped | 3 | 7H DSM-07 H6; T-08 |
| `closure_class` | `DELIVERED`, `SENT_FAILED_EXTERNAL`, `SENT_FAILED_PLATFORM`, `NOT_SENT_PLATFORM`, `NOT_SENT_EXTERNAL`, `UNCERTAIN`, `UNCOUNTED_RELEASE`, `UNCLASSIFIED` (§19.2) | 8 | 7J, from 7H closure fields |
| `admission_seq` | `1`, `2` | 2 | 7H DSM-07 H3 |
| `eligibility` | `active_throughout`, `held_interval`, `uncertain`. `uncertain` is never folded into either of the others | 3 | 7J (SLI-11; AOA-27; OD-7J-12 condition 11) |
| `stream`, `fold_kind`, `origin` (completion) | The eight streams of §6.4 (`outbox_publication`, `consumer_completion`, `webhook_fanout`, `webhook_first_closure`, `webhook_first_claim`, `webhook_first_admission`, `webhook_terminal`, `webhook_closures`); `routine`, `completeness`; `delivery`, `recovery` | 8; 2; 2 | 7J |
| `indicator`, `scope`, `part`, window `state`, `cause` (unmeasured), `kind` (correction) | The accounted indicators `SLI-01`, `SLI-11`, `SLI-12a`, `SLI-12b`, `SLI-12c`, `SLI-17`; the indicator's one bounded scope value (a `family`, a `topic`, a `group`, or `all`); `registered`, `not_owed`, `good`, `correction_registered`, `correction_not_owed`, `correction_good`, `excluded_held`, `uncertain_registered`, `uncertain_good`, `unmeasured_hours`, `unattributed`; `ESTABLISHED`, `ESTABLISHED_PARTIAL`, `ESTABLISHED_UNCERTAIN`, `NOT_ESTABLISHED`, `UNKNOWN`; `REGISTRATION_GAP`, `RESTORE_GAP`; `registered`, `not_owed`, `good`, `eligibility_moved`, `into_unmeasured`. **A cohort hour is never a label**: cohorts are aggregated in the database and only window sums and the latest final hour are exported | 6; ≤ 20; 11; 5; 2; 5 | 7J |
| `disposition` (obligation) | `UNCLASSIFIED`, `OPEN_RETRY`, `HOLD`, `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING`, `UNREGISTERED_CASE` | 7 | 7G §24.1; 7J |
| `attempt_number` | `1`, `2`, `3`, `4`, `5`, `6_plus` (clamped). Present **only** on M-163, whose observations all have a real attempt number (7H DSM-07 H5). No metric invents one for a closure that has none | 6 | 7J |
| `secret_role` | `CURRENT`, `PREVIOUS`. **Restricted series only** (M-134) | 2 | 7H HTP-14 |
| `provider` | Registered callback provider families, from the adapter registry in code | ≤ 8 | 7H §11 |
| `plugin_key` | Keys of the platform-curated plugin catalogue, capped (LBL-08) | ≤ 50 | 6J §26 |
| `capability` | Manifest capability codes from the platform registry | ≤ 8 | 6J §26.3 |
| `store` | Content-bearing event stores: delivery body, replay material, callback input, outbox payload, sealed vault, journal | 6 | 7I §14 |
| `hold_kind`, `scope_type`, `basis`, `cert_state`, `journal_state`, `band`, `age_band`, `escalation_level`, `path`, `access_code`, `path_kind`, `relation_class` | Closed sets of 7I §14.7 – §14.8 | each ≤ 10 | 7I |
| `principal_class` | Database principal classes (the roles of 7I §7.3, by class, never a login name of a person) | ≤ 16 | 7I §7.3 |
| `object_class`, `function_class`, `invariant`, `cause`, `kind`, `event`, `state`, `stage`, `operation`, `predicate`, `disposition`, `dependency`, `held_class`, `delivery`, `phase`, `policy`, `rule_class`, `surface`, `purpose`, `sink_class`, `pattern_class`, `signal`, `source`, `component`, `metric_group`, `tier`, `receiver_class`, `flow`, `shard`, `to_state`, `result`, `anomaly`, `failure_number`, `admitted`, `attributed`, `size_class`, `binding`, `record_type`, `org_status`, `outcome_class`, `step` | Closed sets defined in the registry module with the metric; each named in §8 | each ≤ 30 | 7J |

### 9.2 Rules

| ID | Rule |
|---|---|
| LBL-01 [FROZEN + 7J] | **Never a label, on any metric, in any environment:** an organization or tenant identifier; a user, contact, call, conversation, event, delivery, receipt, endpoint, installation, recovery-case, operation, hold, request or correlation identifier; a host name, URL, IP address or destination; a pod, consumer or member name beyond what Prometheus adds as `instance`; an exception message or any free text; a provider's raw response; a secret, a reference to a secret, or personal data (7A TEN-05; 7D OBS-7D-C1; 7H OBS-7H-01; 7I RED-07). 7D OBS-7D-C1 leaves 7J the power to permit a tenant identifier. **7J does not use it: no exception exists.** |
| LBL-02 [7J] | Only the labels of §9.1, each with its closed set. |
| LBL-03 [7J] | A per-tenant question ("how many deliveries has organization X pending") is answered by a case-bound query on the authoritative table through the frozen APIs or the restricted tools (§22.3). It is never answered by a metric. |
| LBL-04 [7J] | Where a frozen handoff asks for a figure "by organization" or "by identity" (HE-7J-7I-09, -14), the metric counts organizations or identities in a state. The identity itself is in the security-class record. |
| LBL-05 [7J] | `event_type` appears only on metrics whose table row bounds the combinations (publish outcomes by family, SIGNAL by type, handler outcomes by subscribed pair). It never multiplies with `group` beyond the subscribed pairs of 7E §29. |
| LBL-06 [7J] | **Runtime guard.** The registry validates every label value against the closed set before the observation. A value outside the set is not coerced into a new series: the observation is recorded under the reserved value `other` where the row allows it, otherwise dropped, and M-275 is incremented. The raw value is never logged. |
| LBL-07 [7J] | **Build guard.** A static check fails the build when: a metric is registered outside the registry module; a label name is not in §9.1; a label's value set is not a literal closed set; a label name matches a deny pattern (`*_id`, `*id`, `tenant*`, `org*`, `user*`, `contact*`, `call*`, `url`, `host*`, `email`, `phone`, `message`, `error`, `exception`); a metric's declared maximum exceeds the per-metric limit (IR-7J-04). |
| LBL-08 [7J] | **`plugin_key` is bounded by governance, not by nature.** No tenant can create a plugin (6J §26: no tenant-facing creation route in V1), so the set is the platform's catalogue. The registry loads the catalogue keys at start and caps the set at [CAND] 50; a key beyond the cap is recorded as `other` and M-275 is incremented. If a tenant-facing plugin creation route is ever introduced, `plugin_key` leaves the allow-list in that same change (HE-7L-7J-03). `definition_key` (6J §44.1) follows the same rule. |
| LBL-09 [7J] | Histogram bucket boundaries are fixed per metric in the registry. Bucket count is at most [CAND] 12. A native histogram is not assumed. |
| LBL-10 [7J] | Alertmanager grouping and inhibition use only labels of §9.1. The frozen `group_by: [alertname, tenant_id, service]` of 3F §17.2 names a label that no metric may carry; alerts are grouped by `alertname`, `region_class`, `component` (ERR-7J-05). |

### 9.3 Instance classes and the series formula

`series(metric) = S × B × I`, where `S` is the label combinations of §8, `B` is 1 for a Counter or Gauge and `buckets + 3` for a Histogram, and `I` is the number of emitting instances.

| Class | Emitter | Candidate instances `I` |
|---|---|---:|
| X | State observer (two replicas, both scraped; queries use `max`) | 2 |
| R | Relay claim loops | 3 |
| G | Stream gateway | 2 |
| C | Consumer workers. A worker belongs to one group, so for a metric labelled `group` the cluster total is `S × instances per group` | 4 per group |
| D | Webhook dispatcher | 4 |
| A | API and ingress processes | 6 |
| T | Tooling, sweeper, maintenance, trim, reconcilers | 2 |
| V | Voice runtime (SIGNAL publisher) | 10 |
| W | Every event-plane workload | 80 |
| P | Prometheus recording rules generated from the expected registry (EVD-08); one evaluator | 1 |

Every instance count is a **[CAND]** used only to size the budget. None is a deployment decision; instance counts are 7K's (HE-7K-7J-01).

### 9.4 Candidate budget (computed from the §8 tables)

Catalogue totals: **262 metrics**: 142 Counters, 92 Gauges, 28 Histograms; **197 Tier C, 65 Tier D** (232 in the first version; 22 added by the remediation of §34.4 and 7 by that of §34.5; none added by that of §34.6, which changes label sets and stream counts of existing metrics only; one, M-296, added by that of §34.7). `S × B` summed per instance class, with `B = 15` for every Histogram:

| Class | Σ (S × B) per instance | × I | Worst-case series |
|---|---:|---:|---:|
| X | 5,691 | 2 | 11,382 |
| R | 584 | 3 | 1,752 |
| G | 193 | 2 | 386 |
| C | 4,556 | 4 | 18,224 |
| D | 623 | 4 | 2,492 |
| A | 708 | 6 | 4,248 |
| T | 1,275 | 2 | 2,550 |
| V | 12 | 10 | 120 |
| W | 62 | 80 | 4,960 |
| P | 115 | 1 | 115 |
| **Event plane, worst case** | | | **46,229** |

This is an upper bound in which every permitted label combination is populated on every instance. The remediation of §34.6 raised it from 43,683 by 450: `stream` has eight values instead of six (M-283, M-284, M-285, M-289, M-292, M-293), `part` nine instead of seven (M-290), the window `state` four instead of three (M-291), and M-165, M-166, M-285, M-293, M-294 and M-295 each gained a bounded companion or label. The remediation of §34.7 raised it from 44,133 by 2,002: `eligibility` has three values instead of two (M-167, M-168: two Histograms of 60 combinations each), `part` eleven instead of nine (M-290), and M-296 is new. The remediation of §34.8 added 92: the window `state` has five values instead of four (M-291). The remediation of §34.9 added 2: one companion series on M-284. The observer's per-instance sum is now 5,691 against the 6,000 candidate limit per workload instance, which makes the observer, with M-156's group, the first place 7K must look. It is arithmetic over the catalogue, not a measurement. Secondary series that a row describes in its definition (an `…_oldest_age_seconds` companion) add at most [CAND] 10%.

| Limit | Candidate value | Status |
|---|---|---|
| Per metric, label combinations per instance | 2,000 | [CAND]; M-156 sits at the limit and is the first to revisit |
| Per metric, series cluster-wide | 10,000 | [CAND] |
| Per workload instance, all event-plane metrics | 6,000 | [CAND] |
| Regional event-plane budget | 60,000 active series | [CAND]; leaves about 1.3 times the computed worst case |
| SLO-history instance | 2,000 series | [CAND] (§27.2) |

All five are REQUIRES BENCHMARK and go to 7K (HE-7K-7J-01). 7J does not assert that Prometheus as sized in 3F carries them.

### 9.5 Detection and response

| Stage | Mechanism |
|---|---|
| Build | LBL-07. A change that adds a label, widens a set or raises a declared maximum needs an explicit change to the registry, reviewed against this section |
| Start-up | The registry computes the declared maximum of every metric and refuses to start a workload whose total exceeds the per-workload limit. This is a telemetry-configuration defect; the refusal applies to the registry's initialization, and the workload then runs **without metrics** and reports it (M-273), because a workload that does not start would turn a monitoring defect into an outage (ISO-05) |
| Run time | LBL-06, and a per-metric cap on distinct label combinations held in memory; beyond the cap new combinations go to `other` |
| Scrape | A Prometheus `sample_limit` per scrape target and a `label_limit`; a target over the limit fails its scrape as a whole, which makes its figures `UNKNOWN` and raises AL-53, never a partial truth |
| Continuous | M-276 by metric group against the budget (AL-53) |
| Response | Runbook RB-17: identify the group from M-276 and M-275; the offending series is dropped by a relabel rule in region; the registry defect is fixed forward. Event processing is never paused for a cardinality incident |

---

## 10. Event Lifecycle SLIs

### 10.1 Rules common to every indicator

| ID | Rule |
|---|---|
| SLI-R-01 [OD-7J-01] | Each indicator states its numerator, denominator, exclusions, authoritative source and window. An indicator without all five is not reported. |
| SLI-R-02 [7J] | **An event is good only when the fact that defines "good" is durably recorded** in the authoritative store. A scheduled retry, a park, a hold, a hand-off to reconciliation, a seal and a missing measurement are never "good". |
| SLI-R-03 [7J + OD-7J-12] | **Intentionally held is a third outcome.** A delivery of a suspended organization, an entry behind an open dependency gate, an erasure step paused by a recorded hold: each is excluded from both numerator and denominator of the performance indicator of its stage, and is counted in its own held figure with its own age. Exclusion never hides it. For SLI-11 the exclusion is of the whole delivery and is decided once, from lifecycle evidence, over the event-to-deadline window `[occurred_at, occurred_at + B)`: excluded when the organization is proved not `ACTIVE` at some instant of it, including before fan-out; kept when it is proved `ACTIVE` throughout; and classed `uncertain`, which is neither, when the evidence cannot say (AOA-27). A hold that takes effect only after the deadline excludes nothing. |
| SLI-R-04 [7J] | **Unmeasured is a fourth outcome.** For a state or activity indicator, an evaluation interval with stale evidence (EVD-03, EVD-09), or in which a ratio's denominator had no samples and fresh evidence does not show that nothing was owed (EVD-12), is unmeasured, and an indicator whose unmeasured share of the window exceeds [CAND] 2% is **not established** for that window: it is reported as neither met nor breached (OD-7J-02 condition 5). For an accounted indicator the unit is the cohort hour, and an hour is unmeasured only by a declaration of permanent loss (a registration gap, AOA-11; a restore gap, AOA-14) or because it precedes the stream's activation. Such an hour is final, stays one of the 672 consecutive hours of every window that covers it, contributes nothing to either sum and one to `unmeasured_hours` (AOA-21). It is never read as an hour with zero obligations and is never replaced by an older measured hour. An hour whose evidence is only late is not unmeasured: it is not final yet and the window waits for it. The state of an accounted window is one of these (AOA-24; SLI-11 has one more, `ESTABLISHED_UNCERTAIN`, for timing-band uncertainty): `ESTABLISHED` with no unmeasured hour; `ESTABLISHED_PARTIAL` with 1 to 13, shown as measured over the hours it covers and used for no verdict and no budget movement; `NOT_ESTABLISHED` above [CAND] 2% or with an unattributed obligation; `UNKNOWN`, with no figure, when the finalization watermark is too old or the stream's evidence is absent. |
| SLI-R-05 [7J] | A receiver's fault is not the platform's. The closure classes of §19.2 decide, from frozen closure fields, which outcomes are the platform's; an indicator states which classes it counts and they are disjoint. |
| SLI-R-06 [FROZEN + 7J] | Class-D drops are excluded from every durable indicator. They are loss the contract permits (7D CLD-02) and are reported only as SIGNAL activity. |
| SLI-R-07 [7J] | Replay and redrive are excluded from the publication and first-processing indicators. They have their own indicators (SLI-09, SLI-10) and their own dimension value or stream (AOA-17). |
| SLI-R-08 [7J] | Quantiles come from Histograms by `histogram_quantile`. A quantile is an estimate bounded by its bucket: it is reported with the bucket boundaries it falls between and is never quoted with more precision. An objective on a latency is therefore expressed as "the share of observations at or below a bucket boundary", which for an accounted stream is an exact ratio of two durable counters. |
| SLI-R-09 [7J] | **No survivorship.** A latency distribution of finished work contains only obligations that finished. Every accounted latency indicator is therefore a **cohort ratio**: its denominator is every obligation that originated in the window's cohort hours, registered when it began and not when it ended, and an obligation still open when its cohort hour becomes final is valid and not good (AOA-20). No obligation leaves the denominator because a source row was cleaned up, because a recovery case was opened, or because time passed. The state figures M-022, M-086 and M-145 show at any moment the open obligations that are already older than the boundary; they feed alerts and dashboards and are not added to the cohort ratio, which already contains them. |
| SLI-R-10 [7J] | **Evidence grade is stated per indicator** (DUP-03): `accounted` (exact, once per obligation), `state` (exact at the read) or `activity` (process counters, approximate under crashes). An indicator built on `activity` evidence is labelled estimated (SLO-07) and is not used where an `accounted` figure exists. |
| SLI-R-11 [7J] | **One name, one interval.** No indicator, metric or panel describes one interval with another's name. In particular "processing latency", "delivery latency" and "first attempt" are never used without the two timestamps that bound them (§10.3). |
| SLI-R-12 [7J] | **Every accounted indicator names its time dimension, and it is event time.** The semantic time is a stored PostgreSQL timestamp of the obligation: `occurred_at` for SLI-01, SLI-11 and SLI-17; the closure's `closed_at` for SLI-12a, -12b, -12c. An obligation is attributed to the cohort hour of that time. The time at which a fold committed, the time at which Prometheus scraped, and the time at which a report was evaluated are never the time dimension of a reported figure (AOA-15). `occurred_at` is the event's business occurrence time by frozen definition (7A OBS-04 "event age (now − `occurred_at`)"; 7D OBS-7D-13; 7B OCC-01 … OCC-04), including where a producer sets it earlier than the insertion, as for EV-079. |
| SLI-R-13 [7J] | **A window is 672 consecutive final cohort hours.** The reported window is the 672 consecutive UTC cohort hours that end at the finalization watermark of the indicator's stream (AOA-20, AOA-21). All of them are final; each is measured or unmeasured. The sums are taken over the measured ones, and wherever this section says "the window's final cohort hours" in a numerator or a denominator it means those measured hours. Hours that are not final yet are not in the window; its end is the watermark, and its age is shown with the figure. A final cohort row is immutable; an obligation that reaches a final hour later, or changes class in it, is a counted, signed correction (AOA-22), included in the window and shown as a restatement. |

### 10.2 Matrix — SLI definitions

"Grade" is the evidence grade of SLI-R-10. Reporting window: 28 days rolling (OD-7J-02). The indicators changed by the first independent review (SLI-01, -03, -04, -06, -08, -09, -11, -12a/b/c, -13, -14, -15, and the new SLI-17) have a full measurement contract in §10.4.

| ID | Indicator | Good (numerator) | Valid (denominator) | Exclusions | Source | Grade |
|---|---|---|---|---|---|---|
| SLI-01 | Outbox publication latency | Obligations of the window's final cohort hours closed `PUBLISHED` with `published_at − occurred_at` at or below the boundary `B` | Every outbox row whose `occurred_at` falls in those hours, whatever its status | None | M-290 (stream `outbox_publication`) | accounted |
| SLI-02 | Eligible event age | Evaluation intervals in which the oldest eligible age is at or below the target | Evaluation intervals with fresh `outbox` evidence | None. An open gate explains the age; it does not excuse it | M-002 | state |
| SLI-03 | Durable transport availability | Evaluation intervals in which, for **every** expected shard, either durable confirmations occurred with no unconfirmed result, or nothing was owed to that shard | Evaluation intervals with fresh `outbox` and `redis_cluster` evidence | None | M-035 per shard; M-001; M-031 | activity + state |
| SLI-04 | Handler execution latency (receipt to owner commit) | Handler executions whose receipt-to-commit time is at or below the boundary | Executions ending `DURABLY_COMMITTED` | Replay items. **Not an event-processing latency** | M-068 | activity |
| SLI-05 | Consumer durable completion | Handler attempts ending `DURABLY_COMMITTED`, `ALREADY_COMMITTED` or `NOT_APPLICABLE` | Those plus `HANDLER_FAILED` | Attempts not executed because a gate was open or the entry was held; `KNOWN_UNSUBSCRIBED` | M-063 | activity |
| SLI-06 | Acknowledgement after commit | Acknowledgements `ACKED` whose commit-to-acknowledgement time is at or below the boundary | Handler outcomes that permit acknowledgement (`DURABLY_COMMITTED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`) | None | M-069; M-063 | activity |
| SLI-07 | Oldest outstanding valid obligation | Evaluation intervals in which, for every expected group, the oldest pending idle time and the count of overdue outstanding pairs are within target | Intervals with fresh `redis_group` and `accounting` evidence | Groups with a governed retirement in progress; pairs with disposition `HELD` (shown separately) | M-044; M-086 | state |
| SLI-08 | Time to a recovery case for an unaccounted obligation | Class `V` cases of reason `OBLIGATION_UNACCOUNTED` opened within `T_obl` plus one reconciler period of the pair's position `recorded_at` | All such cases opened in the window | None | Ledger and position records, through an observer function | state |
| SLI-09 | Recovery resolution within target | Cohort cases with outcome `RESOLVED_WITHIN_T` | The whole cohort: every case that entered `PARKED` between 28 days plus `T` ago and `T` ago | None. `RECONCILIATION_PENDING` and unresolved cases are in the denominator and not in the numerator | M-116 | state |
| SLI-10 | Replay correctness | Replay items ending `PROCESSED`, `ALREADY_COMMITTED`, `NOT_APPLICABLE`, `NOT_OWED`, `KNOWN_UNSUBSCRIBED`, `PUBLISHED_CONFIRMED` | All items with a result other than `CANCELLED` | None | M-107 | activity |
| SLI-11 | Webhook time to first counted closure, from the event | Deliveries settled `active_throughout`, of events whose `occurred_at` falls in the window's final cohort hours, whose first counted closure came at or below `B` after that `occurred_at` | All deliveries of those hours settled `active_throughout`, including those with no counted closure yet: final counts plus signed corrections of that one class | Replays; test deliveries; class `held_interval` (reported as `excluded_held`); class `uncertain` (reported as `uncertain_registered` and `uncertain_good`, with the two bounds they give; while one exists in the window no verdict is given, OD-7J-14). A delivery is in exactly one of the three classes (AOA-27). Unmeasurable deliveries (unattributed: the window is not established while one may belong to it) | M-290 (stream `webhook_first_closure`) | accounted |
| SLI-12a | Platform hand-off capability | Counted closures, closed in the window's final cohort hours, in which a request was handed to the network: classes `DELIVERED`, `SENT_FAILED_EXTERNAL`, `SENT_FAILED_PLATFORM` | Those plus `NOT_SENT_PLATFORM` and `UNCERTAIN` | `NOT_SENT_EXTERNAL` (the destination or the tenant's configuration prevented the send); `UNCOUNTED_RELEASE` (not an attempt) | M-295 | accounted |
| SLI-12b | Absence of platform-origin failure | Counted closures in classes `DELIVERED`, `SENT_FAILED_EXTERNAL`, `NOT_SENT_EXTERNAL` | All counted closures: those plus `SENT_FAILED_PLATFORM`, `NOT_SENT_PLATFORM`, `UNCERTAIN`, `UNCLASSIFIED` | `UNCOUNTED_RELEASE` | M-295 | accounted |
| SLI-12c | Receiver acceptance (not a platform objective) | Closures in class `DELIVERED` | `DELIVERED` plus `SENT_FAILED_EXTERNAL` plus `SENT_FAILED_PLATFORM` | Everything not sent or uncertain | M-295 | accounted |
| SLI-13 | Callback acknowledged only on a durable receipt | Acknowledgements with basis `RECEIPT_COMMITTED` or `DUPLICATE_OF_RECEIPT` | All 2xx acknowledgements returned | Callbacks that failed verification (never acknowledged as received) | M-149 | activity |
| SLI-14 | Audit and journal completeness | Evaluation intervals with: the hash-chain run inside its period and verified; every invariant of M-220 at zero | Intervals with fresh evidence for those sources | None | M-191, M-220 | state |
| SLI-15 | Retention deadline compliance | Rows erased or sealed at or before their content deadline plus the pass cadence | Rows dispositioned in the window, plus rows whose content is still present beyond deadline plus cadence | Rows under a recorded hold or an unexpired exception (held; M-234). A sealed row counts as dispositioned **and remains an open incident where it is one** (7I SEAL-04) | M-253; M-251, M-252 | activity + state |
| SLI-16 | Security-control enforcement availability | Evaluation intervals in which the gateway, the authorization issuer, the key service and the journal store each made their decision or failed closed | Intervals with fresh evidence | None. A control that failed open is a bad interval and a critical incident | M-201, M-226, M-185, M-210 | activity + state |
| SLI-17 | **End-to-end event processing latency**, per group | Obligations (group, event) of the window's final cohort hours closed `COMPLETED` with completion commit time minus the event's `occurred_at` at or below `B` | Every obligation registered for the group in those hours, minus those classified `NOT_OWED`. Open, parked, reconciliation-pending, reconciled, rejected and late-completed obligations are all in it | `NOT_OWED` only | M-290 (stream `consumer_completion`); M-086 for the open ones at any moment | accounted |

### 10.3 The intervals, and what measures each

**An event's journey through a consuming group.**

| Interval | From (clock) | To (clock) | Measured by | Grade | May back an objective |
|---|---|---|---|---|---|
| (a) Occurrence to durable publication | Outbox `occurred_at` (database) | Outbox `published_at` (database) | M-017 | accounted | Publication only (SLI-01) |
| (b) Publication to receipt by a consumer worker | `published_at` (database) | Worker receipt (worker clock) | **Not measured per event.** The two ends are on different clocks and no durable record of receipt exists (CLK-07). Waiting is visible as group lag and pending idle time (M-041, M-044) | — | No |
| (c) Receipt to authoritative handler commit | Worker receipt (worker monotonic) | Owner commit return (same clock) | M-068 | activity | Handler execution only (SLI-04) |
| (d) Occurrence to final owner-domain completion | Outbox `occurred_at` (database) | Completion record commit time (database) | M-085 | accounted | **Yes: the only one that may back an event-processing objective (SLI-17)** |

Worked example. An event occurs at t = 0, is published at t = 0.2 s, waits in the stream because the group is stalled, is received at t = 30.2 s and commits at t = 30.25 s. Interval (c) is 0.05 s and SLI-04 records 0.05 s. Interval (d) is 30.25 s and SLI-17 records 30.25 s, which is over a 5-second boundary. If the group never recovered, the event would never enter M-085; from t = 5 s it is one overdue pair in M-086 and is counted valid and not good by SLI-17 (SLI-R-09).

**A webhook delivery.**

| Timestamp | Authoritative source | Exists today |
|---|---|---|
| Event occurrence | `audit.domain_event_outbox.occurred_at`, by the delivery's `event_id` | Yes; deleted with the outbox row (7 days at least) |
| Fan-out delivery creation | `webhooks.webhook_deliveries.created_at` | Yes |
| First delivery claim | `claimed_at` of claim record C with `claim_seq = 1` | No (7H MR-7H-06) |
| First valid admission | `admitted_at` of the delivery's earliest admission record A | No (MR-7H-06) |
| First HTTP hand-off | **Not recorded.** MR-7H-06 stores `closed_at` and a duration on the closure, and no hand-off time | Never durable; an activity estimate only (M-169) |
| First claim closure that spent an attempt | `closed_at` of closure X with `attempt_number = 1` | No (MR-7H-06) |
| Final delivery completion | `webhooks.webhook_deliveries.completed_at` | Yes |

| Interval | Metric | Grade |
|---|---|---|
| Event occurrence to delivery creation (fan-out lag) | M-122 | accounted |
| Creation to first claim | M-165 | accounted |
| Creation to first admission | M-166 | accounted |
| Claim to hand-off, per claim | M-169 | activity (estimate) |
| Creation to first counted closure | M-167 | accounted |
| Event occurrence to first counted closure | M-168 | accounted |
| Creation to terminal status | M-131 | accounted |
| Age of due, not yet closed deliveries | M-125, M-145 | state |

M-122 alone is fan-out lag. M-125 alone is the age of what is waiting. Neither is a first-attempt latency; that is M-167 (from creation) and M-168 (from the event), read with M-145.

### 10.4 Measurement contracts of the changed indicators

In an activity-grade contract, `Δ` of a process counter means its increase over the trailing 28 days: an estimate in process time, labelled as such (SLI-R-10), used only where no objective needs an exact event-time window. No accounted indicator is written with `Δ`.

Each block gives: numerator; denominator; time origin and destination; inclusion and exclusion sets; duplicate and replay semantics; source; behaviour during a monitoring outage; censoring and incomplete-window policy; a worked counterexample; the validation scenario.

**SLI-01 — Outbox publication latency.**

| Item | Contract |
|---|---|
| Semantic time | The outbox row's `occurred_at`. An obligation belongs to the cohort hour containing it (AOA-18) |
| Numerator | Over the window's final cohort hours: obligations of stream `outbox_publication` closed `PUBLISHED` with `published_at − origin_at ≤ B`. Read as `M-290{indicator="SLI-01", part="good"} + …{part="correction_good"}` |
| Denominator | Over the same hours: every obligation registered, that is, every outbox row whose `occurred_at` falls in them, whatever its status. Read as `…{part="registered"} + …{part="correction_registered"}` |
| Time origin, destination | `occurred_at`; `published_at`. Both PostgreSQL, same row; `occurred_at` is copied into the obligation record at registration |
| Included | Every outbox row. A row still unpublished when its cohort hour becomes final, and a row that ended `FAILED`, are valid and not good |
| Excluded | Nothing. R4 republication adds no row. An R5 redrive of a `FAILED` row does not reopen its obligation: it failed to publish within `B` and stays not good |
| Duplicates, replay | One outbox row is one obligation whatever the number of confirmed entries, relays or topology generations (AOA-17) |
| Source | Final cohort rows and corrections of the stream, through the window function (accounted) |
| Monitoring outage | Prometheus down: nothing is lost; the window is read from the database when scraping resumes. Observer down: cohorts do not become final, the watermark ages, and the window goes `UNKNOWN`; rows are registered when the observer returns unless deleted first (AOA-11) |
| Censoring, incomplete window | No separate censoring term is needed: an unpublished row is in the denominator from its registration. Unmeasured hours per SLI-R-04; state per AOA-24 |
| Counterexample | In one cohort hour 1,000 rows are published under `B`; then Redis fails and 500 rows of that hour wait for an hour. A histogram of published rows shows 1,000 of 1,000. This indicator's cohort is 1,000 of 1,500 (67%) at finalization, and stays so whether or not the 500 are published later |
| Validation | VT-7J-63 … VT-7J-66, VT-7J-87 |

**SLI-03 — Durable transport availability.**

| Item | Contract |
|---|---|
| Numerator | Evaluation intervals (1 m) in which every expected shard `s` satisfies: (`increase(M-035{shard=s, result!="CONFIRMED"}[1m]) == 0` and `increase(M-035{shard=s, result="CONFIRMED"}[1m]) > 0`) or (no entry was routed to `s` and `M-001 == 0` for the families routed to `s`, from fresh evidence) |
| Denominator | Evaluation intervals in which `outbox` and `redis_cluster` evidence were fresh and every expected shard had fresh M-031 |
| Time origin, destination | Not a duration |
| Included | Every expected shard of the active generation (M-288) |
| Excluded | None |
| Duplicates, replay | A republished entry is a new confirmation attempt and counts as one |
| Source | M-035 by `shard` (activity); M-001, M-031 (state) |
| Monitoring outage | No relay samples and no fresh evidence: the interval is not in the denominator (unmeasured) |
| Censoring, incomplete window | An interval with eligible rows and no confirmation on a shard is **bad**, not undefined (EVD-12) |
| Counterexample | Shard A: 9,990 confirmations. Shard B: 10 attempts, all `SHORTFALL_REPLICA`. Regional ratio 99.9%, "good". Per shard: B is bad, so the interval is bad. With the gate open and 500 rows waiting, there are zero attempts: a ratio is undefined; this indicator records a bad interval |
| Validation | VT-7J-69, VT-7J-70 |

**SLI-04 — Handler execution latency.**

| Item | Contract |
|---|---|
| Numerator | `Δ M-068_bucket{le=B}` per group |
| Denominator | `Δ M-068_count` per group |
| Time origin, destination | Worker receipt of the entry; owner transaction commit return. One worker, monotonic clock |
| Included | Executions that ended `DURABLY_COMMITTED` |
| Excluded | Replay items; duplicates (no owner effect to time) |
| Duplicates, replay | Each execution is one observation; a retried execution is another |
| Source | M-068 (activity) |
| Monitoring outage | Lost for the outage; estimated |
| Censoring, incomplete window | Not an obligation indicator; it describes handler speed and has no censoring term. **It is never used for an end-to-end objective** |
| Counterexample | The 30.25-second event of §10.3 contributes 0.05 s here. Reporting this as processing latency is exactly the defect corrected |
| Validation | VT-7J-71 |

**SLI-17 — End-to-end event processing latency.**

| Item | Contract |
|---|---|
| Semantic time | The event's `occurred_at`, as preserved in the obligation record of (group, `event_id`) |
| Numerator | Over the window's final cohort hours, for group `g`: obligations closed `COMPLETED` with completion commit time `− origin_at ≤ B`. `M-290{indicator="SLI-17", scope=g, part="good"} + …{part="correction_good"}` |
| Denominator | Over the same hours: obligations registered for `g`, minus those classified `NOT_OWED`. `(registered + correction_registered) − (not_owed + correction_not_owed)` |
| Time origin, destination | `occurred_at` of the outbox row, copied into the obligation record while the row exists; commit time of the completion record (7I CEV-03). Both PostgreSQL. Never a position `recorded_at`, a Redis entry ID or a worker clock (CLK-07) |
| Included, and how each is counted | Open at finalization, whatever the reason (`UNCLASSIFIED` cannot occur by F4; `OPEN_RETRY`, `HOLD`, `PARKED`, `REPLAYING`, `RECONCILIATION_PENDING`): valid, not good. `COMPLETED` after `B`, by a normal delivery or by a recovery item: valid, not good. `RECONCILED`, `REJECTED`, `GOVERNED_AWAY`: valid, not good; the effect did not arrive by processing within `B`. **Opening a recovery case never closes an obligation** |
| Excluded | `NOT_OWED` only: an accounting row of kind `UNSUBSCRIBED`, a case resolved `NOT_OWED` or `KNOWN_UNSUBSCRIBED`, or an origin obligation of `NOT_OWED` (7F HCG-30). Nothing is excluded for being held: a compatibility hold or an open dependency gate makes the event late, and it is counted late |
| Duplicates, replay, groups, generations | One obligation per (logical group, `event_id`) by the record's primary key. Redelivery, reclaim, duplicate handler runs, R2 replay, R4 republication and a second topology generation's key cannot add one (AOA-17). An R3 backfill for a group that did not owe the event is not an obligation here |
| Source | Final cohort rows and corrections of stream `consumer_completion`, through the window function (accounted). Unresolved obligations are also visible at any moment in M-086 (state) |
| Monitoring outage | As SLI-01. If the observer was down longer than the outbox row's guaranteed life, pairs may be unregistered: their cohort hours are unmeasured, and any that have a recovery case are still counted in M-086 as `UNREGISTERED_CASE` (AOA-19) |
| Censoring, incomplete window | Inherent in the cohort: an unfinished obligation is in the denominator from registration. State per AOA-24 |
| Counterexample A (case survives outbox cleanup) | Day 0: E is published; group G fails five times; a case is `PARKED`. The obligation record (G, E) was registered on Day 0 with `origin_at` = E's `occurred_at`. Day 8: the outbox row is deleted under ACC-06, because G has a case. Day 10: the record is still open; M-086 `PARKED` = 1; E is in the denominator of its Day-0 cohort hour and not in the numerator. The outbox row's deletion changed nothing in either figure |
| Counterexample B (completion after cleanup) | Day 12: an approved R2 replay commits; `fn_record_completion` writes the completion record with origin `RECOVERY_ITEM`. The fold closes the record `COMPLETED` at that commit time. Latency = commit time − the record's `origin_at` = about 12 days: valid, not good for a 5-second boundary; observed in M-085 with `origin="recovery"`. The outbox row was not needed, and no position time stood in for `occurred_at` |
| Validation | VT-7J-71, VT-7J-72, VT-7J-83 … VT-7J-86 |

**SLI-06 — Acknowledgement after commit.**

| Item | Contract |
|---|---|
| Numerator | `Δ M-069_bucket{le=B, group=g}` (acknowledgements `ACKED` within `B` of the commit) |
| Denominator | `Δ M-063{group=g, outcome=~"DURABLY_COMMITTED\|ALREADY_COMMITTED\|NOT_APPLICABLE"}` |
| Time origin, destination | Owner commit return; gateway result `ACKED`. One worker, monotonic clock |
| Included | Every outcome that permits acknowledgement |
| Excluded | None. A refused, zero-result or unconfirmed acknowledgement is in the denominator and not in the numerator |
| Duplicates, replay | A duplicate delivery is its own outcome and its own acknowledgement |
| Source | Activity counters. Estimated |
| Monitoring outage | Lost for the outage |
| Censoring, incomplete window | The first version divided by `ACKED` acknowledgements only, so a commit that was never acknowledged vanished. It now stays in the denominator |
| Counterexample | 1,000 commits; 900 acknowledged in 10 ms; 100 never acknowledged because the gateway refuses. Old formula: 900 of 900. This one: 900 of 1,000 |
| Validation | VT-7J-07, VT-7J-73 |

**SLI-08 — Time to a recovery case for an unaccounted obligation.**

| Item | Contract |
|---|---|
| Numerator | Cases of reason `OBLIGATION_UNACCOUNTED` with `case created_at − position recorded_at ≤ T_obl + one reconciler period` |
| Denominator | All cases of that reason created in the window |
| Time origin, destination | Earliest position `recorded_at` of the pair; case creation time. Both PostgreSQL (7I ACC-17) |
| Included | Reconciler-opened cases |
| Excluded | Poison parks (the park and the fifth failure are one transaction; there is no interval to measure) |
| Duplicates, replay | One case per (group, event) (7I ACC-07) |
| Source | Ledger and position records, counted by an observer function (state) |
| Monitoring outage | Recomputed from the ledger when the observer returns; cases are retained |
| Censoring, incomplete window | **This indicator cannot see an obligation that never got a case.** It measures the timeliness of detection that happened, not its completeness. Completeness rests on the design of 7I ACC-16 and ACC-17 and is tested by injection (VT-7J-46), and the reconciler's own liveness is M-206. This limit is stated wherever the indicator is shown |
| Counterexample | The reconciler is stopped for a day: no case is opened, so the old formula has 0 of 0 and reports nothing wrong. Here M-206 is stale, the reconciler source is unmeasured, and the window is not established |
| Validation | VT-7J-46 |

**SLI-09 — Recovery resolution within target.**

| Item | Contract |
|---|---|
| Numerator | `M-116{outcome="RESOLVED_WITHIN_T"}` |
| Denominator | `Σ M-116` over all four outcomes |
| Time origin, destination | The case's transition to `PARKED`; its transition to `RESOLVED`. Ledger history, PostgreSQL |
| Included | Every case that entered `PARKED` in the cohort interval, which ends `T` before now, so every member has had at least `T` to resolve |
| Excluded | None. Approval waiting time is inside the interval and is shown separately |
| Duplicates, replay | A case is one cohort member however many replay operations touched it |
| Source | Stateless cohort read of the ledger (state) |
| Monitoring outage | Recomputed on the next read; nothing is lost while the ledger retains the cases |
| Censoring, incomplete window | The first version's denominator ("cases older than the target, or resolved") let quickly resolved recent cases in and kept slow recent ones out. A fixed cohort removes that bias |
| Counterexample | 10 cases parked; 9 resolved in an hour, 1 still open after 10 days, `T` = 3 days. Counting only resolved cases: 9 of 9. Cohort: 9 of 10 |
| Validation | VT-7J-74 |

**SLI-11 — Webhook time to first counted closure, from the event.**

| Item | Contract |
|---|---|
| Semantic time | The event's `occurred_at`, as preserved in the delivery's obligation record |
| Numerator | Over the window's final cohort hours: obligations of stream `webhook_first_closure` counted in the tuple (`topic`, `active_throughout`), closed `FIRST_CLOSED` with `closed_at − origin_at ≤ B`. `M-290{indicator="SLI-11", part="good"} + …{part="correction_good"}`, the correction being signed |
| Denominator | Over the same hours and the same tuple: obligations registered, including those still open at finalization. `registered + correction_registered`, signed, never negative (AOA-22). Numerator and denominator are read from the one tuple, so they describe the same deliveries. `excluded_held` and `uncertain_registered` are the other two tuples, and the three together are every registered delivery of those hours |
| Time origin, destination | `occurred_at` of the event's outbox row, read when the delivery is registered; `closed_at` of the closure record with `attempt_number = 1`. Both PostgreSQL |
| Included | Non-replay, non-test deliveries whose organization is proved `ACTIVE` at every instant of the eligibility window `[occurred_at, occurred_at + B)` (AOA-27 f). A delivery that passed `decide_by` unclosed while its organization was active is included for good, as valid and not good, whatever happens to the organization afterwards |
| Excluded | `held_interval` deliveries: the organization is proved not `ACTIVE` at some instant of that window, whether before fan-out, before a claim, between claim and admission, or after a closure that fell inside the window. `uncertain` deliveries: the lifecycle evidence cannot place a status change on one side of the window's bounds, or cannot be trusted. Neither class is inferred from an audit timestamp, and neither is assumed. A delivery is settled once and its counts move once (AOA-27 j). `UNMEASURABLE` deliveries, which have no cohort hour (AOA-26). Uncounted releases are not attempts and do not close the obligation |
| Duplicates, replay | One first counted closure per delivery (`attempt_number` is unique per delivery, 7H DSM-07 H5). A public replay is a new delivery and is excluded by predicate |
| Source | Final cohort rows and signed corrections of the stream (accounted). M-145 shows what is waiting now and is not held (state); M-126 shows what is held; M-167 is the same closure measured from creation |
| Monitoring outage | As SLI-01 |
| Censoring, incomplete window | Inherent in the cohort |
| Bounds under uncertainty; zero denominators | With `gA`, `vA` from the active tuple and `gU`, `vU` from the uncertain one, and only when `vA > 0`: lower bound `gA / (vA + vU − gU)`, upper bound `(gA + gU) / (vA + gU)`; the point `gA / vA` lies between them. They are diagnostics: with any uncertain delivery in the window there is no verdict (OD-7J-14; AOA-27 h). When `vA = 0`, whether because there was no traffic, every delivery was held, or every delivery was uncertain, the ratio and both bounds are absent, and the window gives no verdict and moves no budget. No 0/0, `NaN` or infinity is ever reported, and an empty eligible population is never an objective met |
| Counterexample | Fan-out lag is 0.1 s (M-122). The dispatcher is down, so nothing is claimed for 10 minutes. M-122 says "fast"; M-125 is an age, not a distribution. Here every delivery of that cohort hour is registered at creation, is open and older than `B` (M-145), and at finalization is valid and not good; after recovery M-168 records about 600 s for each. If one of those organizations is suspended at minute 5, its deliveries stay valid and not good: they missed `B` (30 s as a candidate) while the organization was active. Separately: event at 12:00:00, organization suspended at 12:00:05 and reactivated at 12:00:20, delivery created at 12:00:25, first counted closure at 12:00:35. The window is 12:00:00 to 12:00:30 and the organization is certainly suspended at 12:00:20, the reactivation's `locked_at`: `held_interval`, excluded once, counted in `excluded_held`. A window that began at `created_at` would have seen no suspension and counted a platform miss |
| Validation | VT-7J-75, VT-7J-87, VT-7J-111 … VT-7J-132 |

**SLI-12a, SLI-12b, SLI-12c — three different statements about a delivery attempt.**

| Item | Contract |
|---|---|
| What each measures | **12a**: of the attempts where sending was the platform's to do, in how many did it hand a request to the network. **12b**: of all counted attempts, how many did not fail for a platform reason. **12c**: of the requests that were sent, how many the receiver accepted. They are not equivalent and none substitutes for another |
| Semantic time | The closure's `closed_at`. A closure belongs to the cohort hour containing it. The stream has an origin only: a closure is complete when written |
| Classes (§19.2) | Each closure record is in exactly one class. The seven counted classes and the uncounted release are disjoint and complete |
| 12a numerator, denominator | `DELIVERED + SENT_FAILED_EXTERNAL + SENT_FAILED_PLATFORM` over that plus `NOT_SENT_PLATFORM + UNCERTAIN` |
| 12b numerator, denominator | `DELIVERED + SENT_FAILED_EXTERNAL + NOT_SENT_EXTERNAL` over all seven counted classes |
| 12c numerator, denominator | `DELIVERED` over `DELIVERED + SENT_FAILED_EXTERNAL + SENT_FAILED_PLATFORM` |
| Excluded | 12a: `NOT_SENT_EXTERNAL`, `UNCOUNTED_RELEASE`, `UNCLASSIFIED` (alerted). 12b: `UNCOUNTED_RELEASE`. 12c: everything not sent, and `UNCERTAIN` |
| Duplicates, replay | One closure per (delivery, `claim_seq`) by its unique key (7H MR-7H-06). Replay deliveries are included: they are real attempts |
| Source | Window sums of closure classes over final cohort hours of stream `webhook_closures` (M-295), with late-registered closures as corrections. The activity counter M-128 and the fold-time counter M-144 give the same split for graphs and alerting only |
| Monitoring outage | As SLI-01 |
| Censoring, incomplete window | These are per-closure ratios; a delivery never claimed has no closure and is covered by SLI-11's cohort |
| Worked example | The table below |
| Validation | VT-7J-76, VT-7J-77 |

| Closure | Class | 12a | 12b | 12c |
|---|---|---|---|---|
| 2xx received (T-05) | `DELIVERED` | good | good | good |
| Receiver returned 500 after the request was sent | `SENT_FAILED_EXTERNAL` | good | good | not good |
| DNS failure, nothing sent | `NOT_SENT_EXTERNAL` | excluded | good | excluded |
| Signing secret unavailable, nothing sent | `NOT_SENT_PLATFORM` | not good | not good | excluded |
| Admission window missed (`ADMISSION_EXPIRED`) | `NOT_SENT_PLATFORM` | not good | not good | excluded |
| Configuration changed again after the one re-admission (`CONFIG_CHANGED` closure) | `NOT_SENT_EXTERNAL` | excluded | good | excluded |
| Claim released, organization not active (T-09, no attempt) | `UNCOUNTED_RELEASE` | not counted | not counted | not counted |
| Sweep closed a claim that had an admission (`UNCERTAIN`) | `UNCERTAIN` | not good | not good | excluded |
| Sweep closed a claim with no admission (`CLAIM_EXPIRED`, `NOT_SENT`) | `NOT_SENT_PLATFORM` | not good | not good | excluded |

With one closure of each of the eight counted rows above: 12a = 2 of 6 (33%); 12b = 4 of 8 (50%); 12c = 1 of 2 (50%). The receiver's 500 is good in 12a and 12b and not good in 12c; it is in no excluded set of an indicator that also counts it. The first version's formula placed it in both the numerator and the exclusions.

**SLI-13 — Callback acknowledged only on a durable receipt.**

| Item | Contract |
|---|---|
| Numerator | `Δ M-149{basis=~"RECEIPT_COMMITTED\|DUPLICATE_OF_RECEIPT"}` |
| Denominator | `Δ M-149` over all three bases |
| Time origin, destination | Not a duration |
| Included | Every 2xx acknowledgement returned to a provider |
| Excluded | Requests that failed verification, which are never acknowledged as received |
| Duplicates, replay | A duplicate callback is acknowledged on the existing receipt and counts as good |
| Source | M-149 (activity). The first version's numerator and denominator were the same count of committed receipts, so it could only ever be 100% |
| Monitoring outage | Lost for the outage; the durable cross-check is M-155 (a receipt that exists and is stuck) |
| Censoring, incomplete window | An acknowledgement with no receipt is a code defect and an invariant violation (AL-29 at any occurrence); the indicator is not an objective with a budget (SLO-06) |
| Counterexample | 1,000 callbacks; a defect returns 200 before the receipt transaction for 5 of them and the process then dies. Receipts committed: 995, all "good" under the old formula. This one: 995 of 1,000, and `NO_RECEIPT` = 5 raises the alert |
| Validation | VT-7J-78 |

**SLI-14 — Audit and journal completeness.**

| Item | Contract |
|---|---|
| Numerator | Evaluation intervals (1 h) in which the last hash-chain run is inside its period and verified, and every invariant series of M-220 is zero |
| Denominator | Intervals in which the evidence for those series was fresh |
| Time origin, destination | Not a duration |
| Included | The fixed invariant list of M-220, including "erased state with no durable journal intent" |
| Excluded | None |
| Duplicates, replay | Not applicable |
| Source | M-191; M-220 (state) |
| Monitoring outage | Unmeasured; the chain job's own table still records its runs (MON-05) |
| Censoring, incomplete window | The first version included "audit-write failures left unresolved". A failed audit write rolls its change back (7I AUD-7I-01), so nothing is left unresolved and the term measured availability, not completeness. It is removed here and stays alerted (AL-38) |
| Counterexample | The observer cannot read the invariant queries for 6 hours. Zero violations were exported, because nothing was. The old reading: complete. This one: 6 unmeasured intervals |
| Validation | VT-7J-52 |

**SLI-15 — Retention deadline compliance.**

| Item | Contract |
|---|---|
| Numerator | `Δ M-253_bucket{le=cadence}` (rows erased or sealed within the pass cadence of their deadline) |
| Denominator | `Δ M-253_count` `+ Σ M-251` restricted to rows older than deadline plus cadence (M-252 gives the oldest) at the window's end |
| Time origin, destination | The row's content deadline (7I CAG-02); the erasing or sealing transaction's database time |
| Included | Every content-bearing event-store row whose deadline passed |
| Excluded | Rows under a recorded hold or an unexpired exception: held, counted in M-234 |
| Duplicates, replay | A row is erased or sealed once |
| Source | M-253 (activity, estimated); M-251, M-252 (state). The exact per-row record is the journal (7I JRN-22), which no telemetry role reads |
| Monitoring outage | Dispositions during the outage are missing from M-253; the overdue state figure is exact again at the next read |
| Censoring, incomplete window | The first version divided by "rows whose deadline fell in the window", which no metric counted, and omitted rows still waiting. The overdue rows are now in the denominator. Not an objective (SLO-06) |
| Counterexample | The retention pass stops. No disposition is observed, so a ratio of dispositions is 0 of 0. Here M-251 grows and every overdue row is valid and not good |
| Validation | VT-7J-39 |

### 10.5 Distinctions the formulas enforce

| Statement | How it is enforced |
|---|---|
| A receiver's HTTP 500 is not an internal outage | Class `SENT_FAILED_EXTERNAL` is good in SLI-12a and SLI-12b and not good only in SLI-12c, which is not a platform objective |
| A suspension hold is not a processor failure | Held rows are in M-126; an uncounted release is `UNCOUNTED_RELEASE` and in no attempt indicator; a delivery whose organization is proved not `ACTIVE` inside its event-to-deadline window is `held_interval`, outside SLI-11's numerator and denominator alike (AOA-27) |
| An audit timestamp is not a commit time | `audit.audit_events.occurred_at` is the start of its transaction (`072_5J`). Eligibility reads no audit row; it uses the transition sequence and the post-lock clock of the lifecycle evidence, as bounds (AOA-27 b, c, e) |
| A sequence number is not a time | Sequence order is commit order for one organization; whether a change took effect before a deadline is decided only by the bounds `locked_at < commit < hi` (AOA-27 e) |
| A clock read after a snapshot is not a cutoff | The evaluation cutoff is read by a statement that finishes before the evidence query starts; a later clock value certifies nothing about what that snapshot contains (AOA-27 e) |
| No eligible traffic is not success | With no proven-eligible delivery the ratio is absent, not 100% (AOA-27 h; EVD-12) |
| Not proved is not assumed | A delivery whose window meets a band is `uncertain`: in neither the eligible nor the held population, and bounding the ratio both ways (AOA-27 f, h) |
| A hold does not excuse an earlier miss | A delivery that passed `decide_by` unclosed while its organization was active stays valid and not good; a suspension that takes effect afterwards moves nothing (AOA-27 i, l) |
| An unmeasured hour is not an empty hour | A final hour is `MEASURED` or `UNMEASURED`; the second contributes no count and one unmeasured hour, and the window still spans 672 consecutive hours (AOA-12, AOA-21) |
| Late evidence is not lost evidence | An hour whose fold is late stays open and makes the window `UNKNOWN`; only a declaration proved from run records makes an hour unmeasured (AOA-11, AOA-20) |
| One delivery, three milestones, three records | First claim, first admission and terminal status are three streams with one close each; a milestone that did not happen is not observed (AOA-28) |
| A dependency-gated event is not a handler failure | M-093 counts only committed failure records; a gated attempt writes none (7G §10.1) and is out of SLI-05. Its delay still counts in SLI-17, because the event is late whatever the reason |
| `RECONCILIATION_PENDING` is not success | Not in the numerator of SLI-09 or SLI-17; in both denominators |
| A recovery case is not a completion | An obligation record closes only on a completion record, an `UNSUBSCRIBED` accounting row or a terminal case resolution; an open case leaves it open and in the denominator (AOA-19, SLI-17) |
| Outbox cleanup removes no obligation | The origin time is in the obligation record from registration; 7I ACC-06 can delete the outbox row without changing M-086 or any cohort (AOA-19) |
| Fold time is not event time | Cohort by the obligation's origin time; windows from final cohorts in the database (AOA-15, AOA-18, SLI-R-12) |
| Unreadable is not zero lag | EVD-07, EVD-09; SLI-07 denominator requires fresh evidence |
| No samples is not success | EVD-12; SLI-03 |
| A Class-D drop is not durable loss | SLI-R-06 |
| A successful `XACK` is not successful processing | SLI-05 and SLI-17 read handler outcomes and completion records; SLI-06 reads acknowledgements; neither feeds the other |
| A replay is not a new business event | SLI-R-07; AOA-17; M-107 is separate from M-005 and M-063 |
| Handler speed is not event latency | SLI-04 versus SLI-17 (§10.3) |
| A latency of finished work is not the latency of all work | SLI-R-09: cohort denominators contain every obligation from registration |

---

## 11. SLO and Error-Budget Definitions

### 11.1 Rules

| ID | Rule |
|---|---|
| SLO-01 [OD-7J-01] | **No numeric event-pipeline objective in this document is binding.** Each is `PROPOSED` and `REQUIRES BENCHMARK`. It becomes `APPROVED` only by the owner's explicit decision after 7K has measured it. |
| SLO-02 [FROZEN] | The approved numeric requirements are those of the SRS and nothing else: NFR-PERF-001 (voice response under 800 ms p50 where the provider chain allows), NFR-PERF-002 (API p99 under 300 ms for non-voice CRUD under nominal load), NFR-AVAIL-001 (core voice path 99.9% monthly). They are preserved and are not event-delivery objectives. |
| SLO-03 [FROZEN + OD-7J-01] | The 4G §12.2 figures are indicative (7A CON-05). They are used below as **starting candidates** and are not validated for applicability. |
| SLO-04 [OD-7J-01] | Separate objectives exist for publication, consumer processing, external delivery and recovery. They are never combined into one percentage. Security and privacy deadline compliance is not an error-budget objective at all (SLO-06). |
| SLO-05 [OD-7J-01] | Operational alerts use **provisional thresholds**, documented as such in §23. A provisional threshold is not a guarantee and is never described to a customer. |
| SLO-06 [OD-7J-01] | **Invariants are not objectives.** Durable-obligation integrity, tenant isolation, acknowledgement integrity, audit completeness, journal-before-erasure and content-deadline denial have no error budget and no target below 100%. Their alerts (§23, class INVARIANT) are in force from activation and do not wait for any objective to be approved. |
| SLO-07 [7J] | A reported figure is labelled with its evidence class: **measured** (from fresh authoritative evidence), **estimated** (a quantile within a bucket; a sampled figure), or **unavailable**. The three are never merged into one number. |

### 11.2 Matrix — Candidate objectives

Every row has rollout status **PROPOSED / REQUIRES BENCHMARK**. Targets are candidates for 7K to test, not commitments. "Source" names where the candidate value came from.

| ID | Class | Indicator | User impact when missed | Candidate target | Source of the candidate | Exclusions | Validation in 7K |
|---|---|---|---|---|---|---|---|
| SLO-P1 | Publication | SLI-01 | Every downstream effect of an event is late | 99% of rows published within 2 s | 7J estimate, set below the tightest 4G figure (5 s end to end) to leave time for consumption. Unbenchmarked | As SLI-01 | Normal load, peak load, Redis durability shortfall, catch-up after an outage |
| SLO-P2 | Publication | SLI-02 | Events are stuck before transport | Oldest eligible age at or below 30 s in 99.9% of minutes | 7J estimate | — | Dependency outage and catch-up |
| SLO-P3 | Publication | SLI-03 | The transport cannot durably accept on some shard | 99.9% of measured minutes good on every expected shard | 7J estimate | As SLI-03 | Replica loss; AOF stall; failover |
| SLO-C1 | Consumer | **SLI-17** (occurrence to completion), group `cg.crm.call-history` | Supervisor's call history is stale | 99% of owed pairs completed within 5 s of the event's `occurred_at` | 4G §12.2 (`call.ended` → CRM Activity) | As SLI-17 | Per group, at peak |
| SLO-C2 | Consumer | **SLI-17**, group `cg.billing.usage-ingestion` | Usage record late (quota enforcement itself is real-time elsewhere, 4G) | 99% within 10 s | 4G §12.2 | As SLI-17 | Per group, at peak |
| SLO-C3 | Consumer | **SLI-17**, group `cg.analytics.projections` | Dashboards stale | 99% within 60 s | 4G §12.2 | As SLI-17 | Per group |
| SLO-C4 | Consumer | SLI-05, every group | Events fail and retry | 99.9% of attempts complete | 7J estimate | As SLI-05 | Fault injection |
| SLO-C5 | Consumer | SLI-07 | An obligation is outstanding too long | Oldest outstanding at or below the group-lag bound in 99.9% of minutes | The bound is 7K's (HE-7K-7I-06) | As SLI-07 | Consumer recovery after outage |
| SLO-D1 | External delivery | SLI-11 (event occurrence to first counted closure) | Tenant integrations receive events late | 99% of eligible deliveries have their first counted closure within 30 s of the event | 4G §12.2 (event → webhook delivery) | As SLI-11 | Fan-out and dispatch at peak |
| SLO-D2 | External delivery | SLI-12b (absence of platform-origin failure); SLI-12a is reported beside it; SLI-12c has no objective because it depends on the receiver | Deliveries fail for platform reasons | 99.9% of counted closures without a platform-origin failure | 7J estimate | As SLI-12b | Secret-manager and egress faults |
| SLO-D3 | External delivery | SLI-13 | A provider callback is acknowledged and lost | 100% (an invariant; listed for completeness, governed by SLO-06) | 7H CBK rules | — | Crash between receipt and acknowledgement |
| SLO-R1 | Recovery | SLI-08 | A lost obligation stays undetected | 100% of unaccounted pairs have a case by `T_obl` plus one reconciler period (an invariant under 7I ACC-17) | 7I ACC-17; `T_obl` is 7K's | — | Injected acknowledgement without evidence |
| SLO-R2 | Recovery | SLI-09 | Parked work waits for people | 90% of parked cases resolved within 3 business days | 7J estimate; depends on roster (7I OPA-18) | As SLI-09 | Operational drill, not a load test |
| SLO-R3 | Recovery | SLI-10 | A replay does not finish its work | 99% of items reach an obligation-closing result | 7J estimate | — | Replay drills per mode |

Not objectives, and deliberately absent from the table: SLI-14, SLI-15 and SLI-16. They are governed by SLO-06 and by the frozen deadlines of 7I.

### 11.3 Error-budget governance (OD-7J-02)

| ID | Rule |
|---|---|
| EB-01 [OD-7J-02] | **Applies only to an objective that is `APPROVED`** and whose measurement reliability has been validated (the indicator was established, SLI-R-04, in at least [CAND] 3 of the last 4 windows; for an accounted indicator "established" here means `ESTABLISHED`, with no unmeasured hour, and never `ESTABLISHED_PARTIAL`). Until then no budget exists and nothing in this section takes effect. |
| EB-02 [OD-7J-02] | **Window.** 28 days, rolling, evaluated every hour. For an accounted indicator the window is the 672 consecutive cohort hours that end at its stream's finalization watermark (SLI-R-13), so it advances by exactly one hour as each further hour becomes final, measured or unmeasured, and `good` and `valid` are the window sums the database returns over its measured hours (M-290, M-295), signed corrections included. A budget figure is computed from them only while the window is `ESTABLISHED`, which requires that all 672 hours are measured (AOA-24). For a state or activity indicator, "valid" and "good" count evaluation intervals or events over the trailing 28 days from the `slo:` recording rules. In both cases, for target `T`: `budget = (1 − T) × valid`, `consumed = valid − good`, `remaining = 1 − consumed / budget`. No budget figure is derived from the difference of cumulative counter samples (AOA-15). |
| EB-03 [OD-7J-02] | **Burn rate** over a period `p` is `(bad_p / valid_p) / (1 − T)`. A burn rate of 1 spends exactly the budget in 28 days. |
| EB-04 [OD-7J-02] | **Multi-window burn-rate alerts.** Fast burn: burn rate above 14.4 over 1 hour **and** above 14.4 over 5 minutes (2% of the budget in an hour). Slow burn: above 6 over 6 hours **and** over 30 minutes (5% in six hours). Trend: above 1 over 3 days **and** over 6 hours (ticket). The factors are the conventional ones for a 28- to 30-day window and are [CAND] until 7K confirms the alert volume they produce. Each requires both windows, so a short spike does not page and a recovered burn clears quickly. |
| EB-05 [OD-7J-02, OD-7J-11, OD-7J-14] | **Exhaustion.** `remaining ≤ 0` on two consecutive hourly evaluations, with the indicator established for the window (for an accounted indicator: `ESTABLISHED`). A window whose state is `ESTABLISHED_PARTIAL`, `ESTABLISHED_UNCERTAIN`, `NOT_ESTABLISHED` or `UNKNOWN` (AOA-24) cannot exhaust a budget, cannot show it healthy and cannot clear it. **The budget state and the change-freeze evidence found at the last `ESTABLISHED` evaluation are preserved as they were**: a freeze in force is not lifted, silently or otherwise, by a window that could not be measured or classified; the window's own state is shown in place of a verdict, and a blindness incident with a named recovery owner is open instead (OD-7J-02 condition 5; OD-7J-11 conditions 2 – 6, 9). An unmeasured hour is never treated as an hour without failures and never as an hour of failures. This can last until the hour has left the window, up to 28 days, which the owner has accepted (OD-7J-11 condition 8). For SLI-11, a delivery settled `uncertain` has the same effect for as long as its cohort hour is in the window: the two bounds of AOA-27 (h) are published and **are not a verdict**, whether or not they agree (OD-7J-14). **A window with `valid = 0` has no budget figure**: `remaining` is not computed (it would be 0/0), nothing is consumed, exhausted or cleared, and the preserved state stands; no traffic is not evidence of health. Invariant, security, privacy and durability alerts do not depend on any of this (SLO-06; OD-7J-11 condition 7). |
| EB-06 [OD-7J-02] | **Effect of exhaustion: a controlled change freeze** on nonessential production changes to the service that owns the objective (EB-10). |
| EB-07 [OD-7J-02] | **Always allowed during a freeze:** security fixes; privacy fixes; data-loss prevention; reliability fixes aimed at the exhausted objective; emergency rollback. No approval beyond the normal change process is needed for these. |
| EB-08 [OD-7J-02] | **Any other change during a freeze** needs an accountable approval by the decision authority of EB-10, recorded with the change (who, what, why, the objective affected) in the change-management record. That record is the audit trail of the exception. |
| EB-09 [OD-7J-02] | **A freeze stops changes. It stops nothing else.** It never stops, slows or sheds live voice traffic, durable event publication or processing, reconciliation, recovery operations, replay under an approved plan, retention passes, sealing or erasure. No automation acts on budget state. Every durability, security and privacy control stays in force unchanged. |
| EB-10 [OD-7J-02] | **Ownership.** |
| | Publication objectives (SLO-P*): service owner platform event infrastructure; freeze scope the relay, the transport adapter, the outbox functions and the event Redis configuration. |
| | Consumer objectives (SLO-C*): service owner the consuming context of the group; freeze scope that context's handlers and the shared consumer pipeline. |
| | External-delivery objectives (SLO-D*): service owner Integrations (6J); freeze scope fan-out, dispatcher, egress adapter, callback ingress. |
| | Recovery objectives (SLO-R*): service owner event operations; freeze scope the tooling and ledger functions. |
| | Decision authority for a freeze exception: the engineering owner of the service and, for anything touching security or privacy controls, the security owner. Final authority: the platform owner. |
| EB-11 [OD-7J-02] | **Recovery criteria.** The freeze ends when `remaining > 0` for [CAND] 24 consecutive hourly evaluations with the indicator established (for an accounted indicator: `ESTABLISHED` at each of them), and a written review exists that names the cause and the corrective action. A window with an unmeasured hour cannot end a freeze; while one persists, a change goes through the exception of EB-08. |
| EB-12 [OD-7J-02] | **Internal governance, not a contract.** An objective and its budget are internal reliability governance. No objective in this document is a customer-facing service-level agreement, and none may be quoted as one. A customer commitment is a separate commercial decision. |

---
## 12. Distributed Tracing

### 12.1 The constraint, and the mechanism that fits it

The frozen 7C envelope has no tracing field (7C §16 and §17 define `correlation_id` and `causation_id`; no trace field is bound), and a stream entry has exactly the two fields `fmt` and `env` (7E ENT-01). A webhook request carries a fixed set of platform headers (7H §9.1, §9.3). **7J adds no field to the envelope, to the stream entry or to the webhook request**, and so cannot carry a W3C `traceparent` across the outbox, the stream or the delivery row.

The asynchronous boundary is crossed by **derivation instead of propagation** (TRC-01 … TRC-04): every hop that handles an event can compute the same trace context from the event's own identity, which every hop already has (7A OBS-01).

| ID | Rule |
|---|---|
| TRC-01 [7J] | **Event trace identity.** For an event with `event_id` *E*: `event_trace_id = first 16 bytes of SHA-256("7j-trace-v1" ‖ canonical text of E)`; `anchor_span_id = bytes 17 … 24 of the same digest`. Both are non-zero by construction (a zero result is replaced by a fixed constant and counted). |
| TRC-02 [7J] | **Why a digest and not the UUID itself.** `event_id` is a UUIDv7 (7C §18): its leading bits are a timestamp and its variant bits are fixed. A ratio sampler decides from the low bits of the trace ID; with fixed variant bits those values fall in a narrow band and a ratio would sample all events or none. The digest is uniform, so one deterministic ratio gives the same decision at every hop. |
| TRC-03 [7J] | **Event anchor span.** The producer, in the process that commits the outbox row and after the commit returns, emits one span named `event.create` with trace ID `event_trace_id` and span ID `anchor_span_id`, carrying a **span link** to the span of the request or job that produced it. If the process dies between the commit and the emission, no anchor exists: later hops still compute and use the same IDs, the trace simply has no root, and the evidence that the event was created is the outbox row. No hop waits for, or looks up, an anchor. |
| TRC-04 [7J] | **Per-event hop spans** (publish of one entry, handler execution, one delivery attempt) are created in trace `event_trace_id` with the anchor as their remote parent: they act on that one event and the relation is genuine. **Batch spans** (a relay claim batch, an `XREADGROUP` batch, an acknowledgement batch, a sweep run, a replay operation, a retention pass) are their own traces and carry **span links** to the anchors of the events they contain, capped at [CAND] 32 links, with the batch size as an attribute. A batch is not a child of any one event and no event is a child of a batch. |
| TRC-05 [FROZEN + 7J] | **`correlation_id` and `causation_id` are attributes, not trace structure.** `correlation_id` identifies the root of a flow and never changes along it (7C COR-01); `causation_id` names the immediate cause (CAU-02). A consumer that emits a follow-on event creates that event's own anchor (TRC-03) and links it to the consumed event's anchor, which is what `causation_id` states. A whole flow is found by `correlation_id`; one event's journey by `event_trace_id`. Before the OD-7C-04 migration is active, durable envelopes carry neither field (COR-06, CAU-07); the trace design does not depend on them, because TRC-01 uses `event_id` only. |
| TRC-06 [7J] | **No inbound trust.** A `traceparent` or any trace header on a client request, a provider callback or a plugin response is never adopted as a parent. It may be recorded as a link attribute after validation of its syntax, and it never affects a sampling decision. |
| TRC-07 [7J] | **No outbound propagation to third parties.** No `traceparent`, `tracestate` or baggage is sent to a webhook receiver, a plugin or a provider. The tenant's support reference is the frozen pair of envelope `request_id` and `X-Platform-Delivery-Id` (7H §19.2). |
| TRC-08 [7J] | **Baggage is not used** in the event plane. Nothing is propagated that a downstream system could log. |

### 12.2 Correlation semantics

| Value | Authoritative meaning | Metric label | General log (application class) | Restricted log and trace | Audit |
|---|---|---|---|---|---|
| `event_id` | The only business-event identity (7C; 7I ACC-14) | Never | No | Yes | Yes, where the audit kind records it |
| `event_type`, `event_version` | Type and schema version | `event_type` under LBL-05 | Yes | Yes | Yes |
| `request_id` | Server-assigned at entry (6A §25) | Never | Yes (it identifies a request, not a tenant) | Yes | Yes |
| `correlation_id` | Root of a flow; observability only, never authorization, dedup or ordering (7C COR-05) | Never | No | Yes | — |
| `causation_id` | Immediate cause | Never | No | Yes | — |
| Outbox claim | (relay identity, claim time): which relay held the lease | `relay_role` only | Relay role | Relay instance | — |
| Transport position | `<physical key>/<entry ID>` (7E ENT-05; persisted only in the position record, 7I ACC-13). Never a time, never an identity | Never | No | Yes (class `INT`) | — |
| Consumer-group identity | Logical group name from the registry | `group` | Yes | Yes, plus member name | Yes |
| Recovery case | (logical group, `event_id`, `event_type`) | Never | No | Case reference | Yes |
| Delivery identity | Delivery ID; claim sequence; attempt number | `attempt_number` clamped only | No | Yes | Yes |
| Replay lineage | Operation ID and mode (7G); `replay_of_delivery_id` and lineage root (7H) | `mode` only | Mode | Yes | Yes |
| `organization_id` | Trusted envelope scope | **Never** | **No** | Yes: the UUID, or `platform`, or `untrusted` (7I RED-06) | Yes |

### 12.3 Matrix — Span catalogue

Kinds follow OpenTelemetry. "Rel." is the relation to the event anchor: **P** remote parent; **L** span link; **—** none.

| ID | Span name | Kind | Emitted by | Rel. | Begins — ends | Error status when |
|---|---|---|---|---|---|---|
| SP-01 | `event.create` | PRODUCER | Producer process | anchor; L to the request span | Instant, after the producing commit returns | Never (a failed commit emits nothing) |
| SP-02 | `outbox.claim` | INTERNAL | Relay | L (batch) | Claim call — return | The claim call raised |
| SP-03 | `transport.publish` | PRODUCER | Relay adapter | P | Before `XADD` — after the per-entry outcome is known | Outcome other than `CONFIRMED` |
| SP-04 | `transport.confirm` | CLIENT | Relay adapter | L (batch per shard) | `WAITAOF` sent — reply or timeout | Shortfall, timeout, error |
| SP-05 | `outbox.mark` | INTERNAL | Relay | L (batch) | Mark call — return | CAS miss on a confirmed entry; the call raised |
| SP-06 | `gateway.read` | CLIENT | Gateway | L (batch) | `XREADGROUP` or `XAUTOCLAIM` — return | Redis error; refusal |
| SP-07 | `consumer.process` | CONSUMER | Consumer | P | Entry received — outcome known | `HANDLER_FAILED`; classification other than supported or known-unsubscribed |
| SP-08 | `consumer.owner_tx` | INTERNAL | Consumer | child of SP-07 | Owner transaction begin — commit or rollback return | Rollback; unknown commit |
| SP-09 | `gateway.ack` | CLIENT | Gateway | L (batch) | Evidence check — `XACK` result | Refusal; zero result; error |
| SP-10 | `recovery.failure_record` | INTERNAL | Consumer | P | Failure-record transaction | The record did not commit |
| SP-11 | `recovery.park` | INTERNAL | Consumer; sweep; reconciler | P | Parking transaction | Parking failed |
| SP-12 | `recovery.operation` | INTERNAL | Tooling | L (batch) | Operation start — terminal state | Any item not obligation-closing |
| SP-13 | `recovery.replay_item` | CONSUMER (R2, R3) or PRODUCER (R4, R5) | Tooling | P, plus L to SP-12 | Item start — result recorded | Result not obligation-closing |
| SP-14 | `webhook.fanout` | INTERNAL | Fan-out consumer | child of SP-07 | Fan-out transaction | Rollback |
| SP-15 | `webhook.dispatch` | INTERNAL | Dispatcher | P (to the event of the delivery) | Claim — closure committed | Closure category other than `SUCCESS` with origin `PLATFORM` |
| SP-16 | `webhook.attempt` | CLIENT | Dispatcher | child of SP-15 | Hand-off to the egress adapter — result | Any failed attempt (the origin attribute says whose) |
| SP-17 | `callback.receive` | SERVER | Ingress | — (L from the resulting event's anchor) | Request received — acknowledgement sent | Verification failed; receipt not committed |
| SP-18 | `callback.process` | INTERNAL | Processor | L to SP-17 by receipt | Processing claim — terminal status | `FAILED` |
| SP-19 | `plugin.execute` | CLIENT | Executor | child of the invoking span | Execution row `RUNNING` — terminal | `FAILED`, `TIMED_OUT` |
| SP-20 | `retention.pass` | INTERNAL | Maintenance | — | Pass start — end | Any batch failed; journal unavailable |
| SP-21 | `obligation.reconcile` | INTERNAL | Reconciler | L (cases opened, capped) | Run start — end | Redis unreadable (`UNKNOWN`) |

### 12.4 Attribute allow-list

| ID | Rule |
|---|---|
| TRC-09 [FROZEN + 7J] | **Allow-list, applied twice.** A span attribute is emitted only if its key is in the table below (7I RED-05). The SDK wrapper of the event plane refuses any other key. The Collector repeats the check and drops any attribute whose key is not listed, for spans of the event-plane services. The frozen Collector configuration of 3F §19.1 uses `allow_all_keys: true` with a list of blocked values; that is a deny-list and does not meet RED-05. The event-plane pipeline uses an allow-list; this is a controlled erratum to the configuration example, not to the stack (ERR-7J-07). |
| TRC-10 [FROZEN] | **Never an attribute, an event or a status description:** a payload or any payload field; a webhook or callback body; a header value; a signature; a secret, a credential or a secret reference; a presigned or signed URL; a URL beyond scheme, host and port; a query string; a phone number, an email address, a name; transcript or recording content; replay material; a key-service output; an exception message (7A SEC-01, SEC-04; 7H §19.4; 7I RED-01 … RED-05). |
| TRC-11 [7J] | **Exceptions.** `record_exception` is not used in event-plane code. A failure sets the span status to error and the attribute `error.category` to a closed code (7G FCL-07; 7H HTP-14). No stack trace and no message is attached (7I RED-04). |

| Attribute key | Value | Class |
|---|---|---|
| `event.id`, `event.type`, `event.version` | Identity (7A OBS-01) | Restricted |
| `event.correlation_id`, `event.causation_id` | 7C §16, §17, when present | Restricted |
| `tenant.id` | Organization UUID, `platform` or `untrusted` (3E §14.1; 7I RED-06) | Restricted |
| `request.id` | Server-assigned | Restricted |
| `messaging.system`, `messaging.operation` | `redis`; `publish`, `receive`, `process`, `settle` | Internal |
| `messaging.destination.name` | Logical stream name (never a payload-derived value) | Internal |
| `messaging.consumer.group.name` | Registry group name | Internal |
| `transport.ref` | `<key>/<entry ID>` (7E ENT-05) | Restricted (`INT`) |
| `event.outcome`, `event.class`, `error.category`, `failure.origin` | Closed codes | Internal |
| `delivery.id`, `delivery.claim_seq`, `delivery.attempt_number` | 7H §19.1 | Restricted |
| `endpoint.id` | Endpoint UUID | Restricted |
| `net.peer.scheme_host_port` | Scheme, host, port only (7H LOG-7H-02) | Restricted |
| `http.response.status_code` | Integer | Internal |
| `recovery.case_ref`, `recovery.operation_id`, `recovery.mode` | 7G | Restricted |
| `batch.size`, `retry.number`, `redis.delivery_count` | Integers | Internal |
| `secret.role` | `CURRENT`, `PREVIOUS`, on SP-15 only (7I TVF-05) | Restricted |
| `egress.rule_code` | Internal rule code (7I TVF-05) | Restricted |
| `sampling.reason` | `ratio`, `voice`, `fault`, `recovery`, `security` | Internal |
| `worker.role`, `region.class`, `service.name`, `handler.contract_generation`, `topology.generation` | Bounded | Internal |

### 12.5 Retries, duplicates, replay

| ID | Rule |
|---|---|
| TRC-12 [7J] | **A retry is a new span, never a continuation.** Each processing attempt of an entry is its own SP-07 in the same event trace, with `retry.number` from the ledger's failure count and `redis.delivery_count` as delivered. Each HTTP attempt is its own SP-16 under its own SP-15. Sibling attempts under one parent show the retry history. |
| TRC-13 [7J] | **A duplicate delivery** produces SP-07 with `event.outcome = ALREADY_COMMITTED`. It is not an error span. |
| TRC-14 [7J] | **A replay item** (R2, R3) is SP-13 in the event's trace with `recovery.mode` and `recovery.operation_id`, linked to SP-12. A republication (R4, R5) is SP-13 of kind PRODUCER followed by ordinary SP-06 … SP-09 spans in each group, which are distinguishable from the original processing only by the earlier completion; this is why SP-13 is linked, not parent. **A public webhook replay** (R7) creates a new delivery whose SP-15 belongs to the same event trace and carries `delivery.id` of the new row; the lineage is on the delivery row (7H), not in trace structure. |
| TRC-15 [7J] | A span never represents an obligation. A missing span proves nothing; the obligation's state is in its store (PRN-02). |

### 12.6 Sampling (OD-7J-06)

| ID | Rule |
|---|---|
| SMP-01 [FROZEN] | Staging 100%. Production: voice-call traces 100%; API requests 10% baseline rising to 100% on a 5xx or a p99 breach; background tasks 25%; a Collector tail sampler that keeps any trace containing an error span (3F §19.2; 6A §25). Unchanged. |
| SMP-02 [OD-7J-06] | **Event-pipeline hops: 25% baseline** for healthy events, proposed, matching the frozen background-task rate. It is a sampling policy, not a capacity statement; the volume it produces is 7K's to measure (HE-7K-7J-05). |
| SMP-03 [OD-7J-06, conditions 1, 11] | **Deterministic and consistent.** The decision is `ratio(event_trace_id) < 0.25` on the uniform digest of TRC-01. Every hop computes the same answer for the same event with no propagated flag, on every retry and in every replay. A policy change takes effect by configuration at each workload; during a rollout two hops may disagree for the same event, which yields a partial trace and no other effect. |
| SMP-04 [OD-7J-06, condition 9] | **Events of a voice call are sampled at 100%** (frozen): an event whose producing context is a call-scoped flow (7C COR-C, COR-V) is always sampled. The decision is made by the producer from its own context and, at later hops, from the event type's membership in the call-scoped set of the manifest, which is a closed list in code. |
| SMP-05 [OD-7J-06, conditions 4, 5, 12] | **Fault capture has three parts, because a head ratio cannot see a failure that has not happened yet.** |
| | (a) *Hop-local tail decision.* For an event that the ratio did not select, the hop still builds its spans in memory, unexported, in a bounded per-attempt buffer. When the hop's outcome is known it exports them if the outcome is in the fault set, with `sampling.reason = fault`; otherwise it discards them. The buffer lives for one attempt and is bounded in spans and bytes ([7K]); when full it keeps the newest spans. |
| | (b) *Forward marking from durable state.* Once durable fault state exists for an event, every later hop samples it at 100%, deciding from state that hop already reads: a recovery case exists for (group, event) (the mandatory gate read of 7G RTY-01); the entry's Redis delivery count is above 1; the delivery's `attempt_count` is above 0; the work is an operation item of R2 … R5. No new stored flag and no envelope field is needed. |
| | (c) *Collector tail sampling* (frozen) keeps a whole trace that contains an error span, within the Collector's decision window. It helps when the failing hop and the earlier hops fall inside one window, and it is not relied on beyond that. |
| SMP-06 [OD-7J-06] | **The fault set**, always exported: any span with error status; relay outcomes `UNKNOWN`, `ROW_REJECTED`, `RELAY_CAPABILITY`; CAS miss on a confirmed entry; classification other than C-7 and C-9; `HANDLER_FAILED`; ambiguous guard; unknown commit; tenant mismatch; payload-organization mismatch; any gateway refusal; acknowledgement `ZERO`, `ERROR`, `REFUSED`; parking, hold and hand-off to reconciliation; every recovery operation and item; unaccounted-obligation and unattributed-evidence cases; webhook closures with origin `PLATFORM`; `SECRET_UNAVAILABLE`; fence mismatch; stale-claim release; egress refusal; callback verification failure; content-guard denial on a work-creating path; journal append failure. |
| SMP-07 [OD-7J-06, condition 6] | **What is not recovered.** For an event outside the 25%, the spans of hops that completed healthily before the fault were discarded when those hops ended. They cannot be reconstructed and this document does not claim otherwise. What exists for those hops is their authoritative record: the outbox row and its position record, the accounting row, the ledger history, the closure records. An investigation starts from those (§24), not from the trace. |
| SMP-08 [OD-7J-06, conditions 7, 8] | **No mandatory alert depends on a trace.** Every alert of §23 reads counters, state metrics or audit-derived counters. Traces serve diagnosis only. If the Collector or Tempo is down, every alert still fires. |
| SMP-09 [OD-7J-06, conditions 11, 13] | **Buffering and backpressure.** The SDK queue and the hop-local buffer are bounded and drop when full (ISO-04); drops are counted (M-273). The Collector's own queues are bounded; under pressure it sheds ratio-sampled spans before fault-sampled ones, by the `sampling.reason` attribute. Nothing in this chain can block a claim, a handler, a commit or an acknowledgement (ISO-01). |
| SMP-10 [OD-7J-06, condition 10] | Sampling never changes what a span may contain: TRC-09 … TRC-11 apply to fault-sampled spans exactly as to any other. A fault is not a reason to capture a payload. |
| SMP-11 [OD-7J-03; OD-7J-08; OD-7J-09] | Every trace is kept 14 days, fault-sampled or not, and then expires. An incident record (2 years) holds a timeline, closed codes and counts and **no event, delivery, call or correlation identifier** (RET-7J-08). Spans that must outlive 14 days are kept only as preserved evidence under the scoped, authorized procedure of §27.6, never by extending trace retention. |

---

## 13. Structured Logging and Redaction

### 13.1 Basis

[FROZEN] D0 provides the `structlog` pipeline with a redaction processor, bounded fields and a fail-closed handler (`logging.py`, `redaction.py`); 3F §18.3 adds a node-level masking filter. 7J defines the schema event-plane code uses on top of that pipeline. It does not modify D0.

### 13.2 Matrix — Canonical log fields and their classification

Classes: **G** globally safe (application log class); **R** internal restricted (restricted sink access, §22.3); **S** sensitive (security-class sink only); **P** prohibited (never emitted).

| Field | Content | Class | Bound |
|---|---|---|---|
| `timestamp` | UTC, from the process clock | G | — |
| `severity` | Closed levels | G | — |
| `service`, `component`, `worker_role` | Bounded names from the registry | G | — |
| `region_class` | Abstract region class | G | — |
| `event` (log event name) | A closed, code-defined name such as `relay.publish.outcome` | G | Closed set |
| `event_category` | Family, or a closed safe category of the event | G | Closed set |
| `outcome_class` | Closed outcome code | G | Closed set |
| `failure_code` | Closed category code (7G FCL-07; 7H HTP-14; the causes of §8) | G | Closed set |
| `operation_stage` | Closed stage name | G | Closed set |
| `retry_mode`, `recovery_mode` | `R1` … `R7`, attempt class | G | Closed set |
| `duration_ms`, `count`, `batch_size`, `attempt_number` | Numbers | G | — |
| `group`, `family`, `event_type`, `event_version` | Registry values | G | Closed set |
| `request_id` | Server-assigned request identity | G | UUID format enforced |
| `trace_id`, `span_id` | Trace reference | R | Hex format enforced |
| `event_id`, `correlation_id`, `causation_id` | 7C identities | R | UUID format enforced |
| `organization_id` | UUID, `platform` or `untrusted` | R | Three forms only |
| `delivery_id`, `endpoint_id`, `receipt_id`, `case_ref`, `operation_id`, `claim_seq` | Entity references | R | Format enforced |
| `transport_ref` | `<key>/<entry ID>` | R | Format enforced |
| `destination` | Scheme, host, port | R | Parsed and rebuilt; never the raw string |
| `secret_role`, `egress_rule_code`, `pinned_address_class`, `lock_wait_ms` | The internal diagnostics of 7I TVF-05 | R | Closed sets |
| `principal_class`, `sqlstate` | Database principal class; five-character code | R | Closed set; format |
| `actor_ref`, `approver_ref` | Operator account reference in security events | S | Format enforced |
| `security_signal` | Closed signal code of §20 | S | Closed set |
| Payload, payload field, `env`, webhook body, callback body, processing input, replay material | — | **P** | — |
| Recording or transcript content; customer phone, email, name | — | **P** | — |
| Access, refresh or bearer token; API key; signing secret; credential; secret reference value; raw key-service output | — | **P** | — |
| Presigned or signed URL; URL path or query string; header value; signature value; signing input | — | **P** | — |
| Receiver response body or preview; unredacted provider error; exception message; stack trace of event-plane code with local values; SQL text with values | — | **P** | — |
| Normalized subject key (phone or email digest input), contact graph content, hold subject scope | — | **P** | — |

### 13.3 Rules

| ID | Rule |
|---|---|
| LOG-01 [7J] | An event-plane log line is produced through one logging helper that accepts only the fields of §13.2, by name, with a typed value. An unknown field name is rejected at the call; it is not passed to the pipeline to be filtered. |
| LOG-02 [7J] | **Sink class.** Every line has `sink_class`: `application` or `security`. A line containing a class S field, or the `security_signal` field, is `security`. Routing by that field happens at the node (3F §18.1 Fluent Bit); the two classes go to separate log groups with separate credentials and the retention of 3F §18.3. |
| LOG-03 [FROZEN + 7J] | The correlation fields of OBS-7D-17 (`event_id`, `event_type`, `event_version`, relay identity; `correlation_id`, `causation_id` once present) are on every relay line at class R. |
| LOG-04 [FROZEN] | Class R fields are present only in logs whose sink is restricted (7I RED-01, RED-06). Both log groups of LOG-02 are restricted sinks in the sense of RED-06: neither is readable by a tenant or exported to support tooling. The `application` class is additionally queryable by on-call SRE without a case reference **only through views that drop class R fields** (§22.2). |
| LOG-05 [7J] | **Errors are categories.** Event-plane code catches an exception at its boundary and logs `failure_code` from a closed mapping. The exception's message, arguments and chained causes are not logged. An unmapped exception logs `failure_code = UNCLASSIFIED` and the exception's type name only (7I RED-03, RED-04). |
| LOG-06 [7J] | **Normalization.** Strings are valid UTF-8 with invalid sequences replaced; control characters, bidirectional overrides and zero-width characters are removed; identifiers are validated against their format and replaced by `[INVALID]` when they do not match, so an attacker-controlled value cannot pose as an identifier. |
| LOG-07 [7J] | **Truncation.** Each field has a maximum length fixed in the helper; D0's global bounds (`MAX_STRING_LENGTH`, `MAX_EVENT_FIELDS`, `MAX_RENDERED_EVENT_LENGTH`) remain the outer limit. A truncated value is marked. |
| LOG-08 [FROZEN] | **Never logged**, whatever the level and whatever the environment: everything of class P above (7A SEC-01, SEC-04, SEC-07; 6J §44.4; 7H §19.4; 7I RED-01 … RED-04, PVW-05). Payload logging is off and no production configuration enables it (7D SEC-7D-02). `XRANGE` and `XREADGROUP` output is never logged; `XINFO GROUPS` and `XPENDING` output may be (7I RED-08). |
| LOG-09 [7J] | **Injection.** Output is one JSON object per line, produced by the JSON renderer; values are JSON-escaped, so a line break or a quote in a value cannot start a new record or a new field. No log line is built by string concatenation. No value is ever rendered by a consumer of the log as HTML, Markdown, a link or terminal control. |
| LOG-10 [7J] | **Debug level carries no more data.** It may carry more events, at the same field classes. There is no "verbose payload" mode. |
| LOG-11 [7J] | **Rate.** Repeating conditions are logged once per state change with a count on the next line, not once per occurrence: a gate that is open logs its opening and closing; a dependency outage does not log each gated entry. Per-occurrence figures are metrics. |
| LOG-12 [FROZEN] | Retention and storage: application class 30 days hot, 90 days cold; security class 90 days hot, 2 years cold; infrastructure 14 and 30 days (3F §18.3). In region (7I RSY-11). Not changed by 7J (OD-7J-03 condition 4). |
| LOG-13 [7J] | A log line is never the record of a mandatory audit action. Where an action is audited, the audit row is the record and the log line, if any, is a pointer (§14). |
| LOG-14 [7J] | The gateway, the relay, the publishers, the trim worker, provisioning and the observer never log `env` or any part of an entry (7E ENT-08; 7I GWY-12, RED-02). |
| LOG-15 [7J] | **Subject-index and hold work logs counts and closed codes only.** No normalized key, no digest of one, no contact reference set and no hold scope is logged to make a metric or an investigation easier. Investigation of one subject is a case-bound procedure through the 7I functions. |
| LOG-16 [7J] | Log volume per workload is bounded by a token bucket in the helper ([7K]); lines beyond it are dropped and counted (M-273). Security-class lines are exempt from the bucket and are bounded by LOG-11. |

### 13.4 Secret-pattern scanning of log sinks (HE-7J-7I-06)

| ID | Rule |
|---|---|
| SCN-01 [7J] | A detective control. It does not replace LOG-01 … LOG-08. |
| SCN-02 [7J] | **Two places.** At the node: the frozen masking filter (3F §18.3) replaces matches before a line leaves the node and increments a counter. In the sink: a scheduled in-region job samples both log classes and the trace store's attribute values for the same patterns. |
| SCN-03 [7J] | **Patterns:** the classes of 7I PVW-03 (authorization and bearer values; three-part base64url tokens; `secret_manager://` references; `key=`, `token=`, `password=`, `secret=`, `signature=` values; long opaque base64 or hexadecimal runs; the platform's own signature header format) and of PVW-04 (E.164 numbers; email addresses), plus URL query strings and presigned-URL parameter names. |
| SCN-04 [7J] | A finding records the sink class, the pattern class, the emitting service and the log event name. **It never records the matched text**, and the scanner writes no copy of the line. |
| SCN-05 [7J] | The scanner has read access to the sinks it scans and to nothing else. It runs in region. |
| SCN-06 [7J] | **Response** (AL-36, runbook RB-11 pattern): treat the value as compromised if it is a credential (rotate through the frozen rotation paths); remove the line from the hot and cold sink by the sink's own deletion procedure, recorded in the incident; fix the emitting code; add a regression test of class VT-7J-15. A personal-data finding is a privacy incident for the privacy owner. |
| SCN-07 [7J] | A scanner that has not completed a run within its period is itself alerted (AL-51 through its heartbeat). |

---

## 14. Immutable Audit Separation

### 14.1 Matrix — Audit versus telemetry

| Concern | Metrics | Traces | Logs | Immutable audit |
|---|---|---|---|---|
| Purpose | Aggregate health, indicators, alerting | Diagnosis of one journey | Diagnosis; security monitoring | Accountability: who did what, under which authority |
| Durability | Best-effort; a scrape can be missed | Best-effort; sampled; drop on backpressure | Best-effort; bounded buffers | **Transactional**: commits or rolls back with the change (7I AUD-7I-01) |
| Retention | 30 days raw; 13 months SLO aggregates (OD-7J-03) | 14 days (OD-7J-03) | 3F §18.3 by class | 5J §20, independent of all of the above |
| Tenant visibility | None | None | None | Per 6L and 6M DEC-6M-03; tenant-scoped rows are attributable to the tenant (7I AUD-7I-05) |
| Access control | Dashboard roles (§22.2) | Restricted query broker (§22.3) | Restricted query broker; security role for the security class | The frozen 6L and 6M routes; no role has insert, update or delete on audit tables (`072_5J`) |
| Personal information | None, by the label allow-list | Restricted identifiers only; no content (TRC-09, TRC-10) | Restricted identifiers only; no content (§13.2) | Identifiers, capability names, counts, category codes; `resource_snapshot` non-personal by construction (7I RED-10) |
| Reprocessing | Recomputed from raw series within 30 days | None | None | Never rewritten; the hash chain is computed nightly (5J §15) |
| Evidence integrity | None claimed | None claimed | None claimed; the security class is access-controlled, not tamper-evident | Only write path `audit.fn_insert_audit_event()`; hash chain; no direct DML |
| Failure behaviour | Figures become `UNKNOWN`; the event plane continues (ISO-01) | Spans dropped; counted | Lines dropped; counted | **The change does not happen** (AUD-7I-01); a refusal stays refused if its audit row fails (AUD-7I-07) |

### 14.2 Rules

| ID | Rule |
|---|---|
| AUD-7J-01 [FROZEN] | A mandatory audit record is written inside the originating PostgreSQL transaction by `audit.fn_insert_audit_event()`. 7J adds no asynchronous audit and no second audit store (7I AUD-7I-01, AUD-7I-02). |
| AUD-7J-02 [7J] | **A metric increment is never the audit.** For every counter in §8 whose definition says "after the audit row commits", the order is: audit row commits, then the counter is incremented. If the process dies in between, the audit row exists and the counter is one short (DUP-05). The reverse order is prohibited. |
| AUD-7J-03 [7J] | **A counter never gates an action.** No function reads a metric to decide whether an audit row was written. |
| AUD-7J-04 [FROZEN] | **Recovery after a crash between commit and telemetry.** The category "mandatory asynchronous audit" is empty: OD-7D-02 moved all 84 `AUDIT_ASYNC` routes and every worker-origin mandatory audit into the originating transaction (7D §36; 7I §19.1, §19.3). So for every mandatory audit, the change and its audit both committed or neither did. A crash after that commit and before any telemetry was emitted loses telemetry only; the durable source from which the fact can be recovered is the audit row itself, in `audit.audit_events`, together with the state row it describes. Nothing has to be re-derived from telemetry, and nothing can be. This is an argument from frozen rules; no runtime test of it was executed. |
| AUD-7J-05 [7J] | **Conformance is still owed.** 7D IO-7D-16 requires the 84 routes to be implemented that way; until it is done for a route, that route's audit durability is unproven. 7J's part is the detective check: M-220 counts state changes that have no audit row, and AL-33 fires on any. That check finds a violation; it does not repair one, and it is not a substitute for IO-7D-16. |
| AUD-7J-06 [7J] | **The security-class log is not an audit trail** and is never presented as immutable evidence. It is access-controlled operational evidence with the retention of 3F §18.3. Where 7I requires accountability for an action, an audit kind exists for it (7I §19.4) and the security-class line only points to it. |
| AUD-7J-07 [OD-7J-05] | **The record of a restricted telemetry query** is an audit event of the platform scope, proposed kinds `TELEMETRY_RESTRICTED_ACCESS_GRANTED`, `_DENIED`, written through `audit.fn_insert_audit_event()` by the tooling principal before the grant is released (§22.3). It needs the caller-list change that 7I already requires for the tooling principal (7I AUD-7I-10, IR-15) and the vocabulary extension of 7I ERR-7I-06; it adds no table and no second trail. |
| AUD-7J-08 [7J] | Audit-derived metrics (M-170 … M-172, M-223, M-244, M-247, M-260, M-280, M-282) are counters incremented by the writer after its audit commit. They are not computed by scanning audit tables, and the observer has no read access to audit rows. |
| AUD-7J-09 [7J] | Audit integrity itself is monitored by M-190 (write failures), M-191 (hash-chain run), M-220 (state change without audit) and AL-38. A failed hash-chain verification is a security incident; the alert does not, and cannot, repair the chain. |

---
## 15. PostgreSQL Outbox Observability

### 15.1 What each state looks like

| State | Evidence | Reading |
|---|---|---|
| HEALTHY | `outbox` evidence fresh; M-002 small; M-005 mostly `CONFIRMED`; gate `CLOSED` | Committed events are being published |
| DELAYED | M-002 and M-001 rising; gate `CLOSED`; outcomes still `CONFIRMED` | Publication is slower than production (capacity, or a slow transport) |
| FAILED | M-010 or M-011 non-zero; M-014 or M-052 non-zero; M-016 non-zero | Rows are terminal, unroutable or anomalous; each needs a disposition, not a retry |
| HELD | Gate `OPEN` (M-006) with M-002 rising | The relay is deliberately not claiming (7D GATE-03). Rows are safe in PostgreSQL. This is the designed response to a transport fault |
| UNKNOWN | `outbox` evidence stale (AL-50), or no relay heartbeat (AL-51) | Nothing can be said about backlog. Not healthy |

### 15.2 Rules

| ID | Rule |
|---|---|
| OBX-01 [7J] | **Backlog and age come from the table, not from the relay.** A relay that is down exports nothing; the backlog it is not draining is still visible, because the observer reads the outbox directly (PRN-02). The relay's own counters describe relay activity only. |
| OBX-02 [7J] | **"Published" is counted once durability is confirmed.** M-005 `CONFIRMED` is incremented after 7E's criterion is positively established and the adapter has returned (7E WAO-02, CL-18). It is not incremented when `XADD` returns an ID, and a `WAITAOF` timeout is `UNKNOWN`, never `CONFIRMED` (WAO-03). |
| OBX-03 [7J] | **`CONFIRMED` is still an attempt count.** A row confirmed by a relay whose lease had expired is confirmed twice (7I ACC-18). The obligation count is the number of rows `PUBLISHED`, which is a table fact and is what M-017 accounts, once per row (§6.4). |
| OBX-04 [7J] | A row marked `PUBLISHED` without a position record violates the invariant of 7I ACC-18 and is counted in M-207 (`…_without_position`); any non-zero value is AL-19. |
| OBX-05 [7J] | `attempt_count` on an outbox row is inflated by claims (7G §29) and is never used as a failure count in any metric or alert. |
| OBX-06 [7J] | `RELAY_CAPABILITY` is a deployment-compatibility signal (7D DPC-04), non-terminal, and is alerted separately from transport unavailability (AL-04): the remedy is a relay deployment, not a Redis repair. |
| OBX-07 [7J] | Cleanup is observed as cleanup (M-018). A falling row count caused by cleanup is never read as progress in publication. Rows held past 7 days by the accounting interlock (7I ACC-06) are a held state with their own figure (M-207), not a cleanup failure. |
| OBX-08 [7J] | Mandatory-work reconcilers and the Voice stale-command reconciler (OBS-7D-16, -18) are observed per flow. A reconciler that resolves by **fallback** is doing what the frozen design allows and is also evidence that the primary dispatch path failed; a sustained fallback rate is AL-44. Dispatch keys in `SUBMITTING` or `AMBIGUOUS` hold a capacity slot until reconciled (7D VDK-07); their count and age are M-021 and AL-45. |

---

## 16. Redis Streams and Group Observability

### 16.1 Rules

| ID | Rule |
|---|---|
| RDO-01 [7J] | **Three different questions, three different sources.** *Can the transport durably accept?* is answered by the relay adapter's confirmation results (M-035) and the capability and probe checks (M-036, M-008). *Is a group progressing?* by `XINFO GROUPS` (M-041 … M-044). *Is every obligation accounted for?* by PostgreSQL accounting and position records (§20.2). None answers another's question. |
| RDO-02 [7J] | **Idle, stalled and unavailable are distinguished by evidence**, per group: |
| | *Idle*: fresh evidence; lag 0; pending 0. Healthy. |
| | *Working*: fresh evidence; `entries-read` advancing; pending bounded. |
| | *Stalled*: fresh evidence; lag above 0 or pending above 0; `entries-read` not advancing over the evaluation window, or the oldest pending idle time above the reclaim threshold with no reclaim. AL-15 or AL-11. |
| | *Gated*: as stalled, with a dependency gate open for the group (M-095). `HELD`; the dependency's own alert is the page (§23.5). |
| | *Unavailable*: no worker heartbeat for the group (AL-51) while entries are pending or lag exists. |
| | *Unknown*: `redis_group` evidence stale, or the group is missing. AL-50, AL-12. |
| RDO-03 [7J] | The observer issues only the commands of OBP-04. Safe-trim figures come from the trim worker (M-045, M-046). |
| RDO-04 [7J] | **Trim pressure is retention, not loss.** M-046 growing means a group is pinning the stream (7E TRM-08). With `noeviction` the end state is `OOM` on `XADD`, which pauses publication without losing a committed event (7E MEM-02). AL-13 is therefore an availability warning with a deadline, not a data-loss alert; the alert names the pinning group from M-041 and M-044. |
| RDO-05 [7J] | A drop in `XLEN` is legitimate only when the trim worker reported it (M-047). A drop the trim worker did not report is M-179 and AL-35 (7I HE-7J-7I-04). |
| RDO-06 [7J] | Redis diagnostics cost is bounded: `XINFO GROUPS` per key per poll (12 keys in V1); `XPENDING` summary per (group, key) (19 in V1); one one-entry extended `XPENDING` per (group, key) for the oldest idle time; `MEMORY USAGE` with sampling and at a lower cadence. The cadence and its cost on the primaries are 7K's (HE-7K-7J-04). No diagnostic command scans a stream or a PEL. |
| RDO-07 [7J] | SIGNAL keys are observed for length and for the Analytics group's presence only. SIGNAL figures never enter a durable indicator or a durable alert (7I ACC-12). |

### 16.2 Durability signals

| Signal | Meaning | Not to be read as |
|---|---|---|
| `WAITAOF` `SHORTFALL_REPLICA` | The replica did not confirm the AOF write: the entry is `UNKNOWN` and will be republished (7E CL-14) | A lost event. The outbox row is still unpublished |
| `WAITAOF` `TIMEOUT` | Confirmation did not arrive in time: `UNKNOWN` (CL-15) | Success, or failure |
| Capability check failed | The cluster does not meet CAP-01 … CAP-07; the adapter reports `RELAY_CAPABILITY`-class non-terminal outcomes (CL-21) | A relay bug |
| Probe unhealthy | The gate stays open (7D GATE-04) | Evidence about any consumer |
| Replica lag high | Durability confirmation will slow or fall short | Consumer lag |

---

## 17. Consumer Execution and Idempotency

### 17.1 Rules

| ID | Rule |
|---|---|
| CNS-01 [FROZEN + 7J] | **Idempotency stays domain-owned.** No metric, span or log is read by a handler or a guard. Duplicate detection is the guard's result, reported as `ALREADY_COMMITTED` (7F XAK-02); the "duplicate rate" of 7F §36.4 is the recording rule `ALREADY_COMMITTED / all handler outcomes` per group (MN-05). |
| CNS-02 [7J] | A rising duplicate rate is not a fault by itself: it follows redelivery, reclaim and replay. It is read together with reclaim counts (M-091) and replay activity (M-107). A rising duplicate rate with neither is a signal of acknowledgements not taking effect (AL-17). |
| CNS-03 [7J] | Classification outcomes are reported for every entry, before any handler. `KNOWN_UNSUBSCRIBED` (C-9) is a normal, acknowledged outcome and is excluded from failure figures. C-1 … C-6, C-8, C-10, C-12 are anomalies or version conditions and feed AL-16. C-11 is a hand-off to reconciliation. |
| CNS-04 [7J] | Tenant mismatch (M-066, M-181) is a security signal, never a handler failure, and never counted in M-093. It produces a recovery case and a security record (7I AUD-7I-09). |
| CNS-05 [7J] | Handler-contract generation and cutover are observed as state: the generation a worker was admitted under is a span and log attribute, never a label; admission refusals and revalidation stops are counted (M-073); an open pre-fence set has an age (M-080); an abandoned cutover is an event (M-078). A worker refused at start (M-072) exports the refusal before it exits, and its absence then shows as a missing heartbeat. |
| CNS-06 [7J] | Held entries are held, not failed: key-not-onboarded, compatibility hold, crash-loop isolation and obligation-retired are in M-062 with their ages in M-102, and are excluded from SLI-05. |

### 17.2 The two boundaries

| Boundary | Fact that makes it true | Where it is measured | What it proves |
|---|---|---|---|
| **Durable completion** | The owner transaction commits the guard, the effect and the completion record together (7F TXA-01; 7I CEV-06) | Consumer worker: M-063 at commit return; M-068 | The business effect exists once, with evidence |
| **Transport acknowledgement** | The gateway found evidence, committed the accounting row, then `XACK` returned (7I GWY-08, GWY-10) | Gateway: M-067; consumer: M-069 | The transport copy may be forgotten |

| ID | Rule |
|---|---|
| CNS-07 [7J] | The two are separate metrics from separate components and are never summed, substituted or compared as one. A handler outcome is never inferred from an acknowledgement; an acknowledgement is never inferred from a handler outcome. |
| CNS-08 [7J] | **Commit without acknowledgement** (crash in between; lost reply): M-063 has the commit; the entry stays pending and shows in M-043 and M-044; redelivery takes the duplicate path. This is delay, not loss, and is expected in small numbers. |
| CNS-09 [7J] | **Acknowledgement without commit** must not occur: the gateway refuses without evidence (M-202). If Redis shows an entry gone with no accounting row, PostgreSQL finds it (§20.2). An `ACKED` count higher than the number of accounting rows written in the same period is a contradiction checked by the recording rule `platform_event:ack_without_accounting` and is AL-17. |
| CNS-10 [7J] | `XACK` returning zero (7F XAK-08) is counted as `ZERO`. It is normal after a reclaim by another member. A sustained zero rate with no reclaim activity is a group-state regression signal (AL-17). |

---

## 18. Recovery, Replay and Dead-Letter Monitoring

| ID | Rule |
|---|---|
| RCV-01 [FROZEN + 7J] | **Only genuine failures count against the poison budget, and only they are counted as handler failures.** M-093 increments when a failure-record transaction commits and changes the case (7G RTY-04 … RTY-06). A dependency-gated entry, a hold, a crash-loop suspicion and a failed parking write no such record and are counted elsewhere (M-095, M-098, M-094, M-099). |
| RCV-02 [7J] | **Parked is not processed and not lost.** M-097 counts parks; M-101 and M-102 show what is still open. A park is the designed outcome of five genuine failures or of an unprocessable entry (7G §23). |
| RCV-03 [7J] | **`RECONCILIATION_PENDING` is a hand-off, never success.** It has its own count and age by owning context (M-101, M-103), is excluded from every success numerator (SLI-09), and has no automatic end: it ends only when the owning domain records its result (7G T-14). |
| RCV-04 [7J] | **The seven replay modes are never merged.** R1 is observed as reclaim (M-090, M-091). R2 … R6 are operations with a mode label (M-106, M-107). R7 is the public webhook replay (M-140). No metric is named or labelled simply "replay". |
| RCV-05 [7J] | **A replay does not look like new business.** A replay item is counted in M-107 by its result. A handler execution it causes is an ordinary M-063 outcome for that group, and is reconcilable with the item results of the same period. A republication by R4 or R5 is counted in M-107 as `PUBLISHED_CONFIRMED` or `PUBLISH_NOT_CONFIRMED`, and **not** in M-005 or SLI-01 … SLI-03, because the repair publisher is a different emitter (SLI-R-07). No event-count dashboard sums M-107 into "events produced". |
| RCV-06 [7J] | An operation is reported by the multiset of its item results (7G RSL-01). "Completed" (M-106) says the operation ended, never that it succeeded. |
| RCV-07 [7J] | **Recovery material health.** Material unavailable at parking (M-099) leaves the entry pending. A digest mismatch on read (M-113) is an integrity event: the item ends without processing and a security record is written. `SOURCE_MISSING` and `PROVENANCE_MISSING` (M-107) are AL-22: an obligation exists and its source does not. |
| RCV-08 [7J] | Source capture for an unaccounted obligation (7I ACC-05; 7G DSR-12) either commits with the case or does not happen; a capture that cannot be made because the outbox row is gone is, by the cleanup interlock (ACC-06), an invariant violation, counted in M-220 and alerted as AL-19. |
| RCV-09 [7J] | Refused and unauthorized recovery requests, self-approval attempts and material-view events are security signals (§20.1 rows 10 – 12), counted after their audit row (AUD-7J-02). |
| RCV-10 [7J] | Replay throttling and pause time (M-108) and trim pauses held by operations (M-109) are visible because a long-held trim pause is trim pressure with a human cause (RDO-04). |
| RCV-11 [7J] | Publisher `FAILED` rows are observed until dispositioned (M-011, M-104). A `FAILED` row is retained and is not deleted before a disposition exists (7D CLN-04). |

---

## 19. External Webhook, Callback and Plugin Telemetry

### 19.1 Rules

| ID | Rule |
|---|---|
| EXT-01 [FROZEN] | No signal carries an organization label; endpoint, delivery and installation identifiers are trace, log and audit fields only (7H OBS-7H-01). |
| EXT-02 [7J] | **Whose failure it was is always recorded and always shown.** Every closure carries a failure origin (7H HTP-14). Dashboards split every delivery-failure panel by closure class (§19.2). Receiver and destination failures are the tenant's integration behaving badly and are never summed into a platform error rate (SLI-R-05). |
| EXT-03 [7J] | **Held deliveries are held.** A `PENDING` row of an organization that is not `ACTIVE` is not dispatch-eligible (7H §8.1). It is in M-126 by organization status, never in M-124, M-125 or M-145 while it is held, and never in a failure figure because of the hold. Its growth is AL-27, a warning addressed to the account-lifecycle owner, not to on-call. Whether the hold also takes the delivery out of SLI-11 is decided by AOA-27: yes when the organization is proved not `ACTIVE` inside the delivery's event-to-deadline window; no when the hold took effect only after the deadline, in which case the miss stays in the cohort and the row stays out of M-145 only for as long as it is held; and `uncertain` when the evidence cannot say. |
| EXT-04 [7J] | **`DELIVERING` older than the claim lease** is a stale claim. The sweep closes it with `CLAIM_EXPIRED` and spends one attempt (7H T-08, OD-7H-05). M-127 shows the oldest; M-137 counts the sweep's closures by the send state it recorded. |
| EXT-05 [FROZEN + 7J] | **Three send states, kept apart.** `SENT`: an effective admission exists and the worker handed the request to the network, whatever came back, including a timeout or a reset the worker itself observed (7H Matrix F: "receiver accepted, response lost" is a sent request). `NOT_SENT`: certainly nothing was sent. `UNCERTAIN`: the sweep closed a claim that had an admission, so the request may or may not have gone to the destination of the effective admission (7H DSM-07 H6; T-08). **`UNCERTAIN` is its own value on every metric, class, log field, span attribute and panel.** It is never reported as `SENT`, as `NOT_SENT`, as `other`, or dropped. A rising `UNCERTAIN` count means dispatcher processes are dying between admission and closure. |
| EXT-06 [OD-7J-07] | **`SECRET_UNAVAILABLE` with role PREVIOUS is a platform fault by definition** (7H SIG-18): either a previous secret was purged before its expiry or the secret manager failed. It pages at SEV2 on the **first** occurrence (AL-26), with no rate threshold. The role appears only on the restricted series M-134, on SP-15 and in restricted logs; the tenant sees `SECRET_UNAVAILABLE` with origin `PLATFORM` and nothing about the role (7I TVF-01, TVF-02). `SECRET_UNAVAILABLE` with role CURRENT is alerted on a sustained rate. Both are class `NOT_SENT_PLATFORM`. |
| EXT-07 [7J] | Fence mismatches (M-138) should be zero in steady state; any sustained non-zero rate is AL-24 (7H §19.5). Admission lock waits and timeouts on the endpoint row (M-136) are visible as required by HE-7J-7H-02. |
| EXT-08 [7J] | **Callbacks: the receipt is the obligation.** `RECEIVED` is counted after the receipt row commits and before the provider is acknowledged; the acknowledgement is counted separately by what it rested on (M-149). A receipt that stays `RECEIVED` or `PROCESSING` is recovered by the sweep (7H CBK-10); its age is M-155 and AL-29. A burst of verification failures per provider (M-152) is AL-28: it can be an attack, a provider key rotation or a platform misconfiguration, and the runbook distinguishes them. |
| EXT-09 [7J] | A duplicate callback (M-151) is normal and is not a failure. An extraction failure is a durable `FAILED` receipt (7H CBK-17), counted in M-153. |
| EXT-10 [7J] | **Plugins: the execution row is the evidence** (7H PLG-12). A limiter that gives no decision makes the executor refuse (PLG-15): M-159 `UNAVAILABLE` and M-160 show it. That refusal is fail-closed behaviour and is counted as a platform dependency fault, not as a plugin fault and not as a tenant's rate limit. |
| EXT-11 [7J] | Egress refusals (M-142, M-174) are both a security signal and a tenant-configuration fact. The internal rule code is a restricted log and span attribute, never a label (7I TVF-05). |
| EXT-12 [7J] | The vocabulary of 6J §44 is the starting point and is reconciled in §7.4. |
| EXT-13 [7J] | **A claim is not an attempt, an admission is not an attempt, and a release is not an attempt.** The figures of §19.2 keep the four record kinds of 7H DSM-07 apart. In particular the uncounted release of T-09 changes no budget and is never counted as an HTTP attempt, a failed attempt or a retry. |

### 19.2 Matrix — Claim, admission and closure taxonomy (7H §8, DSM-07, HTP-14, HTP-19, MR-7H-06)

7H's future append-only history has four record kinds per delivery `d` and claim sequence `k`: the claim **C**(d, k); an admission **A**(d, k, j) with j = 1 or 2; the abandonment **AB**(d, k, 1) of admission 1; the closure **X**(d, k). A closure carries a disposition, a send state, a category code, a failure origin and `attempt_number`, which is NULL exactly when the closure spent no attempt (DSM-07 H5). 7J observes each kind as itself.

| # | Figure | 7H fact | Metric | Grade |
|---:|---|---|---|---|
| 1 | Claims | Every C(d, k) (T-04) | M-161 | activity |
| 2 | Admissions | Every A(d, k, j) (T-04a) | M-133, `admission_seq` 1 and 2 | activity |
| 3 | Re-admissions | A(d, k, 2), which exists exactly when AB(d, k, 1) exists (H3) | M-133 `admission_seq = 2` | activity |
| 4 | Abandonment records | AB(d, k, 1): `CONFIG_CHANGED`, `NOT_SENT`, no attempt spent | M-162 | activity |
| 5 | Counted attempt closures | X with `attempt_number` not NULL (T-05, T-06, T-07, T-08) | M-128; M-163; M-144 (seven counted classes) | activity; accounted |
| 6 | Uncounted claim releases | X with disposition `RELEASED_ORG_NOT_ACTIVE`, `NOT_SENT`, `attempt_number` NULL (T-09) | M-164; M-144 class `UNCOUNTED_RELEASE` | activity; accounted |
| 7 | `SENT` closures | Send state `SENT` (H6) | M-128 `send_state = SENT` | activity |
| 8 | `NOT_SENT` closures | Send state `NOT_SENT` | M-128 `send_state = NOT_SENT`; M-164 | activity |
| 9 | `UNCERTAIN` closures | Send state `UNCERTAIN`: a sweep closure of a claim that had an admission (T-08) | M-128 `send_state = UNCERTAIN`; M-137; M-144 class `UNCERTAIN` | activity; accounted |
| 10 | Terminal delivery transitions | Row status `DELIVERED` (T-05), `DEAD_LETTER` (T-07, or T-08 at the ceiling), `CANCELLED` (T-10, T-11) | M-123 | activity |

Consistency checks that follow from DSM-07 and are evaluated as recording rules over the accounted and activity figures: closures never exceed claims (H1, H4); re-admissions equal abandonments (H3); counted closures with `SENT` never exceed admissions (H6); `DELIVERED` closures equal `DELIVERED` transitions. A sustained violation is a telemetry or implementation defect and is shown on dashboard F; it is not an event-plane alarm.

**Closure classes.** Every closure record is assigned exactly one class, by the first matching row. The inputs are frozen closure fields only.

| Order | Condition on the closure X | Class | Counted attempt |
|---:|---|---|---|
| 1 | `attempt_number` is NULL (disposition `RELEASED_ORG_NOT_ACTIVE`) | `UNCOUNTED_RELEASE` | No |
| 2 | Send state `UNCERTAIN` | `UNCERTAIN` | Yes |
| 3 | Send state `SENT` and category `SUCCESS` (a 2xx, T-05) | `DELIVERED` | Yes |
| 4 | Send state `SENT`, any other category, origin `PLATFORM` | `SENT_FAILED_PLATFORM` | Yes |
| 5 | Send state `SENT`, any other category, origin `RECEIVER`, `DESTINATION` or `TENANT_CONFIGURATION` | `SENT_FAILED_EXTERNAL` | Yes |
| 6 | Send state `NOT_SENT` and (origin `PLATFORM`, or category `CLAIM_EXPIRED`) | `NOT_SENT_PLATFORM` | Yes |
| 7 | Send state `NOT_SENT`, origin `DESTINATION` or `TENANT_CONFIGURATION` | `NOT_SENT_EXTERNAL` | Yes |
| 8 | Anything else (a combination 7H does not permit, for example `NOT_SENT` with origin `RECEIVER`, which HTP-19 excludes) | `UNCLASSIFIED` | Yes |

| ID | Rule |
|---|---|
| CLO-01 [7J] | The classes are disjoint by the ordered match and complete by row 8. `UNCLASSIFIED` must be zero; any occurrence is alerted (AL-25) because it means a closure was written outside the frozen vocabulary. |
| CLO-02 [7J] | Row 6 names `CLAIM_EXPIRED` explicitly. A sweep closure with no admission follows a worker that died before admitting: a platform event. The sections of 7H cited above fix the origin of the HTP-19 categories and do not print one for `CLAIM_EXPIRED`; 7J therefore classifies by the category and does not rely on, or invent, an origin for it (CNF-7J-14). |
| CLO-03 [7J] | The class is computed where the closure is counted: in the dispatcher or sweeper for the activity figures, and in the database fold for the accounted figure, from the same eight rows held in one code-owned table. It is never stored on the closure record and changes nothing in 7H. |
| CLO-04 [7J] | `secret_role` remains a restricted diagnostic of `SECRET_UNAVAILABLE` closures only (M-134; class R in logs and spans). `attempt_number`, claim sequence and admission sequence are class R references in logs and spans and are never labels, except the clamped `attempt_number` of M-163. |

---

## 20. Security and Privacy Monitoring

### 20.1 Matrix — Security signals and responses

Severity is the default of §23.1 when the signal is credible; routine expected denials do not page (ALR-06). "Safe dimensions" are the only labels. Runbooks are in §24.

| # | Signal | Source | Severity | Safe dimensions | Detection method | Alert owner | Runbook | Audit evidence | Recovery action |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | Cross-tenant read or write attempt | Consumer classification; RLS refusal | SEV1 if any effect is suspected; else SEV2 | `group`, `kind` | M-066, M-181 > 0 | Security | RB-05, RB-11 | Recovery case (7I AUD-7I-09); security record | The entry is parked as a case; the owner reconciles. The authorization layer already denied it |
| 2 | Invalid PostgreSQL tenant context | Guarded function refusal | SEV2 | `function_class`, `cause` | M-221 by cause | Security | RB-11 | Refusal's audit row where one exists | None automatic; investigate the caller |
| 3 | Non-empty tenant setting at pool checkout | Pool checkout hook | SEV1 | `principal_class` | M-182 > 0 | Security | RB-11 | Security record with the connection discarded | Connection discarded before use; pool recycled |
| 4 | Unauthorized `SECURITY DEFINER` invocation | Database `42501`; `session_user` check | SEV2 | `principal_class`, `object_class` | M-219 by class | Security | RB-11 | Database log; security record | None; the call was refused |
| 5 | Platform-admin privilege escalation attempt | `42501` under the platform-admin class on a closed object | SEV1 | `principal_class`, `object_class` | M-219 `AUTHORIZATION_ROOT`, `INTEGRATIONS_5I`, `ORGANIZATION_ROW` | Security | RB-11 | Database log; 6M audit rows | Credential review and rotation |
| 6 | Unauthorized membership or role mutation | Invariant query | SEV1 | `invariant` | M-220 "membership or role change with no tenant-path audit row" > 0 | Security | RB-11 | The absence of the audit row is the finding | Owner-context reconciliation; credential review |
| 7 | Organization lifecycle-proof failure | Lifecycle function refusal | SEV2 | `function_class`, `cause` | M-221, M-222 | Security | RB-11 | Refusal audit row | None; refused |
| 8 | Residency-policy violation | Provisioning refusal; egress policy; region-tag start check | SEV1 | `cause`, `policy` | M-225, M-174; a workload refusing to start on a region mismatch (7I RSY-02) shows as AL-51 | Security and privacy owner | RB-11 | `RESIDENCY_PROFILE_ASSIGNED` or the refusal row | None automatic |
| 9 | Unauthorized integration erasure | Erasure-operation refusal; invariant | SEV1 | `cause`, `invariant` | M-223; M-220 "`gdpr_erasure` disconnect with no completed operation" | Security and privacy owner | RB-11 | Operation audit rows | Owner reconciliation |
| 10 | Unauthorized recovery replay | Ledger refusal | SEV2 | `mode`, `cause` | M-170 by cause | Security | RB-11 | `EVENT_RECOVERY_REFUSED` | None; refused |
| 11 | Self-approval of a dual-control operation | Ledger or operation refusal | SEV2 | `mode`, `cause` | M-170 or M-223 with `SELF_APPROVAL` > 0 | Security | RB-11 | Refusal audit row | None; refused. A page is not permission to self-approve (ALR-12) |
| 12 | Recovery material access without approval | View service denial; key-service audit | SEV1 for a decrypt outside a grant; SEV2 for a denied request | `event`, `purpose` | M-171 `DENIED`; M-186 > 0 | Security | RB-11 | `EVENT_MATERIAL_VIEW_DENIED`; key-service log | Key and credential review |
| 13 | Illegal Redis group command | Gateway refusal; member anomaly | SEV1 | `context`, `cause`, `group` | M-200 `UNBOUND_GROUP`; M-178 > 0 | Security | RB-05 | Security record; cases opened by the reconciler | §20.2 |
| 14 | Redis ACL digest mismatch | Parity check | SEV1 | — | M-175 > 0 | Security | RB-05 | `PLATFORM_CONFIG_CHANGED` history | Node kept out of traffic (7I RDS-15); ACL reapplied from the governed source |
| 15 | Secret-manager failure | Client | SEV2 sustained | `purpose`, `operation` | M-185; M-134 `CURRENT` | SRE | RB-09 | Closure records | Dependency restored; deliveries retry on schedule |
| 16 | Previous signing secret unexpectedly unavailable | Dispatcher closure | SEV2, first occurrence | `secret_role` (restricted) | M-134 `PREVIOUS` > 0 | SRE and security | RB-09 | Closure record with the role; rotation audit row | RB-09 |
| 17 | Unauthorized key-service access | Key-service audit watcher | SEV1 | `purpose` | M-186 > 0 | Security | RB-11 | Key-service audit log | Key review; grant revocation |
| 18 | Journal manipulation or verification failure | Object-store access log; reconciler | SEV1 | `operation`, `state` | M-214 > 0; M-216 `FAILED_CLOSED` | Security and privacy owner | RB-13, RB-14 | Journal records are the evidence | Fail closed (7I JRN-16) |
| 19 | Retention deadline breach | Observer | SEV1 | `store`, `band` | M-217 `MISSED`; M-251 > 0 past the pass cadence | Privacy and security owner | RB-12 | Incident record (7I SEAL-04) where sealed | RB-12 |
| 20 | Unauthorized sealed-content access | Inspection function; content guard; `42501` | SEV1 | `event`, `path`, `object_class` | M-247 `DENIED`; M-257; M-219 `CONTENT_COLUMN` | Privacy and security owner | RB-16 | `SEALED_CONTENT_ACCESS_*` | None; refused |
| 21 | Abnormal event volume or replay activity | Counters | SEV3; SEV2 with a second signal | `family`, `mode` | M-005 rate against its own trailing baseline; M-106, M-107, M-140 rates | Security and SRE | RB-11 | Operation audit rows | Operation paused through the frozen operation controls (7G §42) by an authorized operator |
| 22 | Unauthorized telemetry sink or configuration change | Deployment path; configuration drift check | SEV1 | `object_class` | M-282 with no matching approved change; a drift check of exporter destinations against the governed list | Security | RB-17 | `PLATFORM_CONFIG_CHANGED` | Configuration restored from the governed source; exposure assessed |

| ID | Rule |
|---|---|
| SECM-01 [FROZEN] | **Detection does not replace prevention.** Every row observes a control enforced elsewhere. An attempted cross-tenant read is denied by RLS and the guarded functions whether or not any telemetry backend is running. |
| SECM-02 [7J] | Security counters are derived from the enforcing component's own result (a refusal, an error class), never from parsing another component's logs, except where the source is an infrastructure log by nature (break-glass, object-store access, key-service audit, network policy). |
| SECM-03 [7J] | A security-class record carries the closed signal code, the principal class, the actor reference where an operator is involved, and identifiers at class R. It carries no payload and no statement text. |
| SECM-04 [7J] | Expected denials are not incidents. An ordinary `401`, `403` or `404` on a tenant API route, a failed login, an expired token: none is in this matrix and none pages (OD-7J-07). The signals above are refusals on paths that no correct workload ever takes. |
| SECM-05 [7J] | Database error classes are counted by the client that received them (M-219). The object name is mapped to a closed class in code; an unmapped object is `OTHER`, and a sustained `OTHER` rate is itself reviewed. |

### 20.2 Redis gateway and consumer integrity monitoring

| Condition | Signal | Source | What it shows |
|---|---|---|---|
| Gateway authorization failure | M-200 by cause | Gateway | A caller asked for something it is not bound to |
| Gateway credential health | M-201; M-185 for the token key; AL-48 | Gateway | The gateway cannot serve; consumers idle, publication continues (7I GWY-15) |
| Registered versus requested group mismatch | M-200 `UNBOUND_GROUP`, `UNBOUND_KEY` | Gateway | An attempt outside the binding registry (GWY-04) |
| Invalid delivery-bound token | M-200 `TOKEN_INVALID`; M-204 `CODE_INVALID` | Gateway; database | The token did not authenticate |
| Expired token | M-200 `TOKEN_EXPIRED`; M-204 `EXPIRED` | Gateway; database | A slow handler, or a replay of an old token (CEV-11) |
| Replayed token | M-200 `TOKEN_REPLAYED_OTHER_SCOPE`; M-204 `CLAIM_MISMATCH` | Gateway; database | A token presented for another event, group or organization (CEV-10). Re-presenting it for its own pair is a no-op and is not counted |
| Completion-evidence mismatch | M-204 by cause; M-203 `COMPLETION_EVIDENCE_UNATTRIBUTED` | Database; consumer | An event-keyed guard says "done" with no acceptable completion (CEV-09) |
| Missing durable completion evidence | M-202 | Gateway | An acknowledgement was asked for with nothing to support it |
| Unexpected group cursor movement | M-205 `GONE` with M-203 `OBLIGATION_UNACCOUNTED` | Reconciler | The cursor passed an entry that has no accounting row |
| Unexpected `XACK` or `NOACK` behaviour | `platform_event:ack_without_accounting` (CNS-09); M-205 `GONE` | Rule; reconciler | Redis shows less owed than PostgreSQL does |
| Unaccounted obligations | M-203; M-206; M-207 | Reconciler; observer | Cases opened; reconciler age; rows held by the interlock |
| Exact transport-position reconciliation | M-205 by result | Reconciler | The classification of 7I ACC-16, by position, never by time |
| Re-drive from the durable PostgreSQL source | M-107 with mode R2 for class `V` cases | Tooling | The captured outbox row went back through the 7F pipeline (ACC-05) |
| Privileged gateway break-glass | M-176 `REDIS`; M-175 | Access-log watcher | Administrative access outside every runtime identity (RDS-11) |
| Consumer context credential failure | M-200 `UNAUTHENTICATED`; M-185; M-219 | Gateway; client | A context cannot authenticate, or its principal is refused |

| ID | Rule |
|---|---|
| GIM-01 [FROZEN] | **Redis ACLs do not scope by group.** They scope by command and key (7I §9.3, RR-02). No monitoring in this document assumes Redis would refuse a command for the wrong group. The refusal is the gateway's (GWY-04); the detection that does not depend on the gateway is PostgreSQL accounting (ACC-09). |
| GIM-02 [FROZEN + 7J] | **Position, never time.** Reconciliation compares the recorded entry ID with the group's `last-delivered-id` as IDs, and asks `XPENDING` for that exact ID (ACC-16). No metric, alert or runbook infers a transport position from `published_at`, from an entry ID's time component, or from any clock (CLK-04). The withdrawn time comparison of ACC-04 is not reintroduced as a monitoring heuristic. |
| GIM-03 [7J] | **Detection must survive a lying Redis and a lying gateway.** The alert of record for a lost obligation is AL-18, built on M-203 and M-206, which come from PostgreSQL and the reconciler under the deadline of ACC-17 on the database clock. Redis-derived figures (M-041 … M-044, M-178, M-179) are corroboration and early warning. If they disagree with PostgreSQL, PostgreSQL is believed. |
| GIM-04 [7J] | **The monitoring system holds no gateway power.** It cannot acknowledge, read entries, move a cursor, mint a token, record a completion or write an accounting row (OBP-07). The observer's Redis user is not the gateway's and is not the reconciler's unless OBP-05's fallback applies, in which case the figures are emitted by the reconciler itself and no new credential exists. |

**Telling the causes apart.** The same Redis symptom (an entry no longer pending, with the cursor past it) has six causes. They are distinguished by durable PostgreSQL records, in this order:

| Cause | Distinguishing evidence (all in PostgreSQL) | Result |
|---|---|---|
| Normal completion | An accounting row of kind `COMPLETION`, `UNSUBSCRIBED` or `ATTESTED` for (group, event) | Nothing to do |
| Consumer recovery (parked) | A recovery case in a state that permits acknowledgement; accounting kind `CASE` | Visible in M-101 |
| Replay | An operation item for the event with a recorded result; completion origin `RECOVERY_ITEM` (CEV-13) | Visible in M-107 |
| Legitimate group retirement | A registration record closed at a boundary at or above the position, with the operation reference, and a recorded disposition (ACC-15; 7G §38) | Not owed above the boundary; owed at or below it until dispositioned |
| Topology-generation cutover | The position's own generation and key, with that generation's registration (ACC-19); every pending entry on a retired key has a 7G terminal disposition | Accounted per generation |
| Redis trim | Trim removes only entries below `W(K)`, which every present group has delivered and acknowledged (7E TRM-05). A trimmed entry that was properly processed has its accounting row | Nothing to do |
| **None of the above** | No accounting row and no case for a covered position, classified `GONE` or past `T_obl` | **Unaccounted obligation**: source capture, class `V` case, security signal (ACC-05). Whether the cause was malicious acknowledgement, a defect, an ungoverned `XDEL` or break-glass is an investigation (RB-05); the recovery does not wait for it (ACC-09) |

---

## 21. Retention, Sealing and Legal-Hold Monitoring

### 21.1 Rules

| ID | Rule |
|---|---|
| PRV-01 [FROZEN + 7J] | **A journal outage stays fail-closed.** When an append is not durably confirmed, steps and time-based batches wait at `INTENT_REQUESTED` (7I JRN-20, JRN-29). M-210, M-212 and M-213 show it and AL-39 pages at once. No alert, runbook, operator or automation authorizes an unjournaled deletion, and RB-13 says so in its forbidden actions. |
| PRV-02 [7J] | **Deadlines keep running while erasure waits.** M-212 exports the nearest erasure deadline among the waiting work, so the page states how long remains. When a deadline passes while the journal is still down, the breach is real and is reported as one (AL-41); the outage explains it and does not excuse it. |
| PRV-03 [7J] | **A missing journal intent for a committed erasure** would violate 7I JRN-07. It is checked by an invariant query in M-220 (erased state with no `INTENT_DURABLE` history) and is SEV1. |
| PRV-04 [FROZEN] | **An alert is not a resolution, and no indicator closes an incident** (7I HE-7J-7I-15). An unauthorized-retention incident stays open in M-240 until a disposition function closes it. Acknowledging the page, silencing the alert or the passage of time changes nothing in M-240. |
| PRV-05 [FROZEN] | **The guard is the control; the overdue count is not** (7I HE-7J-7I-16). Content past its deadline is denied by the content access guard whether or not the retention pass, the journal, the vault or any alert is working (CAG-09, CAG-12). M-251 measures how much content is waiting for its disposition; it does not protect it. |
| PRV-06 [FROZEN + 7J] | **Sealed is not erased.** M-241 counts sealed items; SLI-15 counts a seal as a timely disposition of the deadline and the incident stays open where 7I says it is one (RR-10). No dashboard, report or indicator adds sealed items to erased items or labels sealing as completed erasure. |
| PRV-07 [7J] | **Held is not overdue.** A row excluded from erasure by a recorded hold or an unexpired exception is counted in M-234 by hold kind and path kind, and is not in M-251 as a failure of the pass. A hold never disappears from monitoring: active holds (M-227), holds past their review date (M-196; the hold stays in force, HLD-05), and sealed items with basis `HELD` (M-241) are standing panels with no time filter. |
| PRV-08 [7J] | **No subject data in telemetry.** Hold and index monitoring exports counts and closed codes. No normalized phone or email key, no digest of one, no contact identifier, no hold scope value and no organization identifier is a label, a log field or a span attribute (LOG-15). |
| PRV-09 [7J] | **Investigation of one subject or one hold** is done only through the 7I functions under their own authorization (`retention.hold.manage`, operator action proofs, dual control where 7I requires it), bound to a case. The restricted telemetry broker gives no path to subject keys or to the registry. |
| PRV-10 [7J] | **Restore.** M-216 exports the incarnation state. A database incarnation that is not `ACTIVE` must have no event-plane workload serving from it; a heartbeat from a workload whose incarnation check failed is M-218 and AL-40. Restore does not bring back telemetry: the telemetry stores are separate, keep their own history across a database restore, and are never an input to reconciliation (7I JRN-13 reads the journal). |
| PRV-11 [7J] | **Certification.** M-259 shows organizations by certification state. A demotion or a failed certification (M-260, M-261) is alerted, because from that moment hold placement and erasure for that organization are refused by AB-7I-16's rule, and the refusals (M-232) follow. `FROM_T0` organizations produce `LEGACY_HISTORY_UNKNOWN` decision records (M-237) while a subject hold exists; that volume is expected and staffed (7I HE-7K-7I-16), and is shown, not alerted, below its own threshold. |

### 21.2 Matrix — Privacy monitoring coverage

| Area (assignment §11) | Item | Metric | Alert |
|---|---|---|---|
| Erasure journal | Write availability; write latency | M-210, M-213; M-211 | AL-39 |
| | Missing journal intent | M-220 (invariant) | AL-33 (SEV1) |
| | Erasure step age; outstanding backlog | M-193; M-192 | AL-39, AL-41 |
| | Restore quarantine status; completeness proof | M-216 | AL-40 |
| | Incarnation mismatch; worker surviving a restore | M-218 | AL-40 |
| | Time-based erasure failure | M-173, M-143 (`result`) | AL-41 |
| | Deadline escalation | M-217; M-212 (nearest deadline) | AL-41 |
| Material and body retention | Days to material deadline; past-due material | M-195 | AL-41 |
| | Past-due bodies; lineage and `CANCELLED` body-erasure lag | M-194; M-253 | AL-41 |
| | `FAILED` callback processing-input erasure | M-173, M-251 (`store = callback input`) | AL-41 |
| | Legal-hold blocking | M-234 | — (held) |
| | Per-object erasure outcomes | M-173 by store and result (counts; the per-object record is the journal's, JRN-22) | AL-41 |
| | Key-reference retirement blocks | M-258 | — |
| Sealed content | Eligible content awaiting sealing; backlog and age | M-242 | AL-41 |
| | Sealing worker availability | M-262; heartbeat M-272 | AL-41, AL-51 |
| | Vault write failures | M-243 | AL-41 |
| | Access attempts denied after deadline | M-254, M-255 | AL-43a |
| | Unauthorized attempts to inspect sealed content | M-247 `DENIED`; M-219 `CONTENT_COLUMN` | AL-43a |
| | Sealed-content restoration attempts | M-257 | AL-43a |
| | Unauthorized overdue-retention incident age | M-240 | AL-42 |
| Legal holds and subject index | Active request holds; active platform holds | M-227 | — |
| | Hold-placement refusals | M-232 | AL-43b |
| | Index completeness; verification failure | M-231, M-238 | AL-43b |
| | Key-version comparability | M-248, M-249 | AL-43b |
| | Historical attribution uncertainty | M-237 (`reason`), M-235 | AL-42 |
| | Dual-controlled review approvals and denials | M-245, M-244 | — |
| | Certification states; demotion; legacy limitations | M-259, M-260, M-261; M-237 `LEGACY_HISTORY_UNKNOWN` | AL-43b |

---
## 22. Dashboards and Access Control

### 22.1 Matrix — Dashboard definitions

Dashboards are versioned files provisioned as code (3E §14.3). Every panel reads Prometheus; no dashboard reads a database, Redis, Tempo or a log sink directly. Every panel over a state metric shows the freshness of its evidence source (EVD-05). Default time range is 6 hours unless stated; the SLO panels use 28 days.

| Dash | Audience | Access tier | Panels (source metrics) | Aggregation | Freshness | Interpretation caveats | Alert links | Drill-down |
|---|---|---|---|---|---|---|---|---|
| **A — Event Platform Overview** | On-call SRE; engineering leads | T0 | Stage state tiles in the five states of PRN-03 (publication, transport, consumption, recovery, delivery, privacy, monitoring); oldest eligible age (M-002); publish outcomes (M-005); cluster and shard state (M-030, M-031); worst group lag and pending age (M-041, M-044); open cases (M-101); unresolved processing obligations by disposition (M-086); unaccounted cases (M-203); the state of each accounted indicator's window (M-291); due webhook age (M-125); open retention incidents (M-240); firing alerts by class | `max` for ages and states; `sum` of rates | Evidence freshness per tile | A green tile needs fresh evidence. A tile with stale evidence is grey "no evidence", never green | All SEV1 and SEV2 | To dashboards B – I only |
| **B — Transactional Outbox & Relay** | Platform event infrastructure | T0 | Eligible backlog and age by family (M-001, M-002); publication latency distribution (M-017); claim batch and reclaims (M-003, M-004); outcomes by class (M-005); gate state and transitions (M-006, M-007); stage durations (M-009); `FAILED` rows and undispositioned age (M-011, M-104); CAS misses (M-012); capability and route failures (M-014, M-052); anomalies (M-013, M-016); cleanup and interlock holds (M-018, M-207); reconcilers (M-019 … M-021); Voice finalization (M-146 … M-148) | Per family; relay instances summed | `outbox` | Backlog is a table fact; relay counters stop when the relay stops. A falling row count can be cleanup | AL-01 … AL-07, AL-44 … AL-46 | Case-bound query by `event_type` and time through the broker |
| **C — Redis Streams & Consumers** | Platform event infrastructure | T0 | Cluster, shard and replica state (M-030 … M-033); `WAITAOF` duration and results (M-034, M-035); capability and probe checks (M-036, M-008); stream length and memory (M-039, M-040); group lag, entries-read, pending, oldest idle (M-041 … M-044); trim (M-045 … M-047); group registration (M-048, M-049); TTL anomalies (M-050); redirects (M-051); SIGNAL activity (M-015) | Per shard; per (group, family) | `redis_cluster`, `redis_group`, `trim` | Lag is shown only from a successful read. SIGNAL panels are separate and labelled best-effort | AL-08 … AL-15 | None beyond the panels; Redis content is never shown |
| **D — Consumer Execution & Ordering** | Platform event infrastructure; consuming contexts | T0 | Entries read (M-060); classification (M-061); handler outcomes and duplicate ratio (M-063); ambiguous guard, unknown commit (M-064, M-065); **end-to-end completion latency and overdue obligations (M-085, M-086), shown apart from** handler execution, receipt to commit (M-068), and commit-to-acknowledgement (M-069); acknowledgement results (M-067); in-flight (M-070); version and admission (M-071 … M-073); cutover, fences, pre-fence age (M-074, M-078 … M-081); holds (M-062); horizon and draining (M-075, M-077) | Per group | Process metrics; `ledger` for holds | Commit and acknowledgement are two panels and are never stacked. Handler execution time is not event latency: the end-to-end panel is M-085 with its overdue term M-086. `KNOWN_UNSUBSCRIBED` is normal | AL-15 … AL-17 | Case-bound trace search by group and time |
| **E — Retry, DLQ & Replay** | Event operations; platform event infrastructure | T0 | Genuine failures by number (M-093); parks by reason (M-097); holds (M-098); crash-loop (M-094); dependency gates (M-095, M-096); open cases by state and class, oldest ages (M-101, M-102); reconciliation pending by owner (M-103); parking failures (M-099); operations and item results by mode (M-106, M-107, M-110); throttle and trim pauses (M-108, M-109); digest mismatches, dangling PEL (M-113, M-112); redrive (M-105) | Per group; per mode | `ledger` | Parked and reconciliation-pending are not success. Replay results are not new events. Gated work is held | AL-20 … AL-22, AL-47 | The redacted recovery views of 7I §13.5 (unchanged), under 7I's own authorization |
| **F — External Delivery** | Integrations; on-call SRE | T0 | Fan-out results and lag (M-120 … M-122); delivery transitions (M-123); due backlog and age (M-124, M-125); held rows by organization status (M-126); `DELIVERING` and stale claims (M-127, M-137); **the taxonomy of §19.2 as ten separate series**: claims (M-161), admissions and re-admissions (M-133), abandonments (M-162), counted closures by category, origin and the three send states (M-128), by attempt number (M-163), uncounted releases (M-164), exact closure classes (M-144); the stage latencies, each named by its two timestamps: creation to first claim, to first admission, to first counted closure, event to first counted closure, creation to terminal (M-165 … M-168, M-131), and for excluded deliveries the active-time diagnostic (M-296), with the overdue term (M-145) and the activity estimate of claim to hand-off (M-169); SLI-12a, -12b, -12c as three panels; attempt duration (M-129); re-check events and lock waits (M-135, M-136); fence events (M-138); replays (M-140); callback acknowledgements by basis (M-149); egress refusals by rule class (M-142); callbacks (M-150 … M-155); plugins (M-156 … M-160) | Per topic; per provider; per plugin key | `delivery`, `receipt` | Receiver and destination failures are not platform failures. Held is not failed. An uncounted release is not an attempt. `UNCERTAIN` is its own series and is never merged. No panel is titled "delivery latency" without its two timestamps. No per-tenant panel exists | AL-23 … AL-29, AL-49 | Case-bound query by delivery or endpoint through the broker; tenant-visible detail stays on the frozen 6J routes |
| **G — Security & Authorization** | Security | **T3** | Tenant-isolation signals (M-066, M-181 … M-183); gateway refusals and member anomalies (M-200, M-202, M-178); completion refusals (M-204); unaccounted cases and classification (M-203, M-205); recovery and erasure refusals (M-170, M-223); material views (M-171); permission denials and proof refusals (M-219, M-221, M-222); invariant violations (M-220); ACL parity, break-glass (M-175, M-176); key service (M-185, M-186); secret role split (M-134); audit health (M-190, M-191); scanner findings (M-184); telemetry configuration changes and restricted queries (M-282, M-280) | Counts by closed class | Process metrics; `accounting` | Aggregate counts only; the affected organization and the actor are in the security-class record. A zero here is not proof of no attempt if the emitting component was down | AL-17 … AL-19, AL-30 … AL-38, AL-57 | Security-class log query (T3) |
| **H — Privacy, Retention & Compliance** | Privacy and security owner; event operations | **T3** | Journal availability, latency, waiting steps, nearest deadline (M-210 … M-213); checkpoint and incarnation state (M-215, M-216); erasure steps (M-192, M-193); overdue content and time to disposition (M-251 … M-253); bodies and material by band (M-194, M-195, M-217); sealing backlog and failures (M-242, M-243); sealed items by basis (M-241); open incidents by age and escalation (M-240); guard denials (M-254, M-255); inspections (M-247); holds, reviews passed, skipped-as-held (M-227, M-196, M-234); decisions and exceptions (M-237, M-244); index verification, key versions, certification (M-231, M-238, M-248, M-259 … M-261); retention pass freshness (M-262) | Per store; counts of organizations by state | `journal`, `retention`, `index` | Sealed is not erased. Held is not overdue. An incident closes only by a disposition. Hold panels have no time filter | AL-39 … AL-43 | The 7I functions under their own authorization; never the telemetry broker |
| **I — Observability Infrastructure** | SRE | T0 | **Expected versus reporting**: every registry entry (sources, components by group, shards) with its state `EXPECTED`, `DISABLED` (with expiry) or missing, and anything reporting that is unregistered (M-286 … M-288 against M-270, M-272, M-031); evidence freshness and read failures (M-270, M-271); heartbeats (M-272); **accounting streams, expected versus reporting**: every mandatory stream and fold kind from the registry against its last routine and completeness fold (M-289 against M-283), so a stream whose series has vanished is shown as missing and not as blank; per stream the unregistered backlog and oldest age, open records, unmeasured seconds and cohort hours, accounting epoch, finalization watermark and post-final corrections (M-284, M-285, M-292, M-293); per accounted indicator the window state `ESTABLISHED`, `ESTABLISHED_PARTIAL`, `ESTABLISHED_UNCERTAIN`, `NOT_ESTABLISHED` or `UNKNOWN` (M-291), with the measured and unmeasured hours of its 672, the cause of the unmeasured ones, the unattributed count and, for SLI-11, `excluded_held`, the `uncertain` counts with the two bounds they give, and the eligibility corrections (M-290, M-285, M-293); drops and queue fill (M-273, M-274); label rejections and series by group against budget (M-275, M-276); scrape health and target limits; rule evaluation duration and failures; Alertmanager notification failures (M-278); watchdog (M-277); clock offset (M-279); federation lag (M-281); collector and Tempo ingestion; log pipeline lag | Per component; per source | Self | This dashboard is served by the system it describes; the dead-man path (§25.2) is the independent check | AL-50 … AL-58 | Collector and Prometheus self-metrics |

### 22.2 Matrix — Access tiers (OD-7J-05)

| Tier | What it reaches | Who | Authentication | Case reference | Recorded |
|---|---|---|---|---|---|
| **T0** Aggregate dashboards | Dashboards A – F and I. Aggregates over the label allow-list; no identifier of any tenant or entity can appear, by construction (§9) | On-call SRE; platform engineers (read) | Named individual account; SSO; MFA | Not required | Sign-in |
| **T1** Application-log views | Application-class logs **through views that drop every class R field** (§13.2): event names, closed codes, counts, durations, `request_id` | On-call SRE | Named individual account; MFA | Not required | Sign-in and query text |
| **T2** Restricted logs and traces | Class R fields: `organization_id`, `event_id`, `correlation_id`, entity references, `transport_ref`, the TVF-05 diagnostics; all spans | Holders of the SRE-investigator or security role, least privilege | Named individual account; MFA fresh at grant | **Required** for any query scoped to one organization, one event, one delivery, one case or one actor, and for any query returning class R fields | Grant and every query (TQA-08) |
| **T3** Security monitoring | Security-class log group; dashboards G and H | Security role; privacy and security owner | Named individual account; MFA fresh | Required for a query scoped to one organization or one actor | Grant and every query |
| **T4** Customer material | Unmasked replay material (7I §13.5); sealed content (7I SEAL-08) | As 7I defines | As 7I defines | As 7I defines, with **dual control** | 7I audit kinds |

T4 is listed to mark the boundary. It is not a telemetry tier: no telemetry role, grant or tool reaches it, and nothing in 7J changes 7I's procedure (OD-7J-05 condition 12).

### 22.3 Restricted query authorization (OD-7J-05)

| ID | Rule |
|---|---|
| TQA-01 [OD-7J-05, conditions 2, 7] | **Named individuals only.** No shared account, no service account and no API key reads T2 or T3. A workload identity cannot hold a telemetry-reader role. |
| TQA-02 [conditions 3, 14] | **Roles.** `telemetry.restricted.read` (T2) and `telemetry.security.read` (T3) are granted to named people by the security owner, recorded as `PLATFORM_CONFIG_CHANGED`, and reviewed on a fixed period ([CAND] quarterly). Neither is implied by `app_platform_admin`, by any 6M permission or by any tenant role; a 6M platform administrator has no telemetry access by virtue of that role. |
| TQA-03 [condition 4] | **A case-bound grant.** Before a T2 or T3 query that is scoped to a tenant, an entity or an actor, or that returns class R fields, the operator obtains a grant from the restricted query broker by stating: an incident or ticket reference, which the broker validates for existence and open state in the tracker (the 7I OPA-06 pattern); a purpose from a closed list (`INCIDENT`, `SECURITY_INVESTIGATION`, `PRIVACY_REQUEST`, `DEFECT_DIAGNOSIS`, `EVIDENCE_PRESERVATION`); the scope (one organization, or one identifier, or a bounded component and time range); a time range no longer than [CAND] 7 days. |
| TQA-04 [condition 4] | **The grant bounds the query.** The broker rewrites or rejects any query that is not inside the granted scope and time range. A grant is for one operator, is not transferable, and lasts at most [CAND] 8 hours, after which a new grant is needed. |
| TQA-05 [condition 7] | **No unrestricted cross-tenant browsing.** A T2 query with no organization or identifier predicate may return class G fields only. A query that enumerates organizations, or that groups by `organization_id`, is rejected at T2 and allowed at T3 only under a grant with purpose `SECURITY_INVESTIGATION`. |
| TQA-06 [condition 8] | The broker, the stores and the query results stay in region. Results are rendered in the in-region tool; bulk export of class R results is not offered. An incident record receives closed codes and counts only; identifiers leave the hot tiers only as preserved evidence (§27.6). |
| TQA-07 [condition 11] | **Read-only by construction.** The broker's credentials are read credentials for Tempo and for the two log groups. It holds no database credential other than the tooling principal's right to write the audit row of TQA-08, no Redis credential, no key-service permission and no secret-manager permission beyond its own. A telemetry role confers no ability to change business, Redis, recovery or audit state (OBP-07). |
| TQA-08 [conditions 5, 6] | **Independently protected record.** A grant, or its refusal, is an audit row (`TELEMETRY_RESTRICTED_ACCESS_GRANTED`, `_DENIED`; AUD-7J-07) carrying: operator, role, purpose, ticket reference, scope type and the scope's identifier, time range, time of grant, outcome. It is written **before** the grant is released; if the write fails there is no grant. Each query under a grant is recorded in the security-class log with the grant reference, the query's scope and time range, the row count returned and the outcome. **Neither record contains the query's results.** Operators with T2 cannot read, alter or delete either record: the audit row is under 5J's controls and the security-class log group is T3. |
| TQA-09 [condition 13] | **Sessions.** A tool session ends after [CAND] 30 minutes idle and at most 8 hours; MFA is re-checked at each grant. |
| TQA-10 [condition 13] | **Revocation.** Removing a role takes effect at the next query: the broker re-validates the role, the grant and the ticket's open state on every query (the 7I MAT-04 pattern). Closing the ticket ends its grants. |
| TQA-11 [condition 13] | **Emergency investigation.** During a SEV1 or SEV2 incident the incident reference itself is a valid case reference from the moment the incident is opened, so no one waits for a ticket. Nothing else is relaxed: the grant is still named, scoped, time-bound and recorded. |
| TQA-12 [condition 13] | **If the audit write is unavailable** (for example the database is the incident): the broker falls back to writing the grant record to the security-class log group and to the incident record, both of which it can only append to; it marks the grant `AUDIT_DEFERRED`; and it backfills the audit row when the database returns, with the original time. If neither the audit function nor the security-class log accepts the record, **no grant is issued**. T0 and T1, which need no grant, remain available throughout. |
| TQA-13 [condition 10] | **No tenant access.** No tenant principal, API key or tenant administrator reaches any tier. A tenant's view of its own deliveries, audit rows and analytics is the frozen 6J, 6L and 6K surface and nothing more. |
| TQA-14 [condition 9] | T3 is separately granted. Holding T2 does not grant T3. The security-class log group has its own credentials, which the T2 path does not hold. |
| TQA-15 [7J] | Access to the telemetry stores other than through Grafana (T0) and the broker (T1 – T3) is closed by network policy and by the stores' own credentials. Direct store access is infrastructure break-glass, logged and alerted (AL-57). |
| TQA-16 [7J] | The broker is a function of the event-operations tooling workload that 7I already requires (7I §7.3, IR-10). It is not a new product and exposes no public route. It does not exist; until it does, T2 and T3 access is not available and no class R field may be queried by anyone (AG-7J-06). |

### 22.4 Tenant-facing surfaces

| ID | Rule |
|---|---|
| TFS-01 [7J] | **7J creates no tenant-facing monitoring capability**: no route, no status feed, no export, no embedded dashboard. No frozen API contract exists for one. |
| TFS-02 [FROZEN] | A tenant sees its own delivery outcomes through the frozen 6J DTOs with the failure origin of 7I OD-7I-08, and its own analytics through 6L. Tenant dashboards never show a worker identity, a secret role, an egress rule code, a history record or a recovery case (7I RED-12). |
| TFS-03 [7J] | No internal dashboard is shared with, screenshotted for or exported to a tenant as a routine practice. Internal dashboards may show platform-side figures that have no tenant meaning, including provider and plugin failure classes; procurement cost and platform-basis cost are **not** telemetry of this document at all (they are 6K data; 7I OD-7I-14), so no dashboard above can reveal them. |
| TFS-04 [7L] | A future tenant-facing operational capability is a new owner decision and a new API contract (HE-7L-7J-08). |

---

## 23. Alerting Policy

### 23.1 Severities (OD-7J-07)

| Level | Definition (by impact) | Response | Routing |
|---|---|---|---|
| **SEV1** | A durable obligation, a tenant boundary, an audit or journal guarantee, a privacy deadline or a residency commitment is, on credible evidence, violated or at immediate risk; or publication or transport has stopped with material service impact; or monitoring of those controls is blind | Immediate page, any hour. Acknowledge within [CAND] 5 minutes; escalate to the secondary at 5 minutes and to the incident manager at 15 | Pager, primary and secondary; the security owner for security and privacy classes; the privacy owner for privacy deadlines |
| **SEV2** | A fault that will become SEV1 if not handled within hours, or a platform fault with contained impact: a stalled group, durability shortfalls with the gate holding, a required secret unavailable, a dependency of a control failing closed | Immediate page, any hour. Acknowledge within [CAND] 15 minutes; escalate at 15 | Pager, primary |
| **SEV3** | Degradation with no integrity risk: lag, growing backlog, approaching capacity, retries, parked work accumulating, a provider or receiver failing | Ticket and chat; business hours | Chat receiver; ticket |
| **SEV4** | Information: a state change worth a record | Recorded | Chat or dashboard annotation |

Acknowledgement and escalation times are [CAND] and belong to the on-call policy; the classification by impact is approved (OD-7J-07).

### 23.2 Alert classes

| Class | Covers | Default severity |
|---|---|---|
| AVL | Platform availability of the event plane | SEV2; SEV1 with material impact |
| PUB | Event publication failures | SEV2 |
| CON | Consumer processing failures | SEV3; SEV2 when a group is stalled |
| INT | Data-loss or durable-obligation integrity risk | SEV1 |
| RCV | Replay and recovery failures | SEV2 or SEV3 |
| EXT | External provider, receiver and plugin failures | SEV3 |
| SEC | Security incidents | SEV1 or SEV2 |
| PRV | Privacy and compliance incidents | SEV1 or SEV2 |
| OBS | Observability-system failures | SEV1 when a mandatory control is unobserved; otherwise SEV2 or SEV3 |

### 23.3 Rules

| ID | Rule |
|---|---|
| ALR-01 [OD-7J-01, condition 8] | **Threshold status.** Every alert carries one of: **INV** (an invariant: any occurrence, or any occurrence beyond a fixed grace, is the condition; in force from activation; independent of any SLO approval); **FROZEN** (a value fixed by a frozen source); **PROV** (a provisional candidate threshold, documented as such, to be confirmed by 7K; not a guarantee). |
| ALR-02 [7J] | Every alert over a state metric is conditioned on fresh evidence (EVD-04). Its blindness counterpart is AL-50. |
| ALR-03 [OD-7J-07, condition 3] | An alert on a rate or an age uses a sustained condition (a `for` duration). An INV alert on an occurrence does not. |
| ALR-04 [OD-7J-02] | SLO burn-rate alerts (EB-04) exist only for an `APPROVED` objective. Before approval, the PROV threshold alert on the same indicator is the operational alert. |
| ALR-05 [OD-7J-07, condition 4] | INT, SEC and PRV alerts page regardless of the state of any performance objective or error budget. |
| ALR-06 [OD-7J-07, condition 2] | No page for an ordinary invalid login, rejected API request or expected authorization denial (SECM-04). |
| ALR-07 [OD-7J-07, condition 5] | **Deduplication and grouping.** One notification per (alert, `region_class`, deduplication key of §23.4). Grouping labels are `alertname`, `region_class`, `component` (LBL-10). Repeat interval for an unresolved page: [CAND] 4 hours for SEV1 and SEV2 (3F §17.2 value). |
| ALR-08 [OD-7J-07, condition 5] | **Dependency-aware inhibition** (§23.5) suppresses symptoms of a paged cause. **It never suppresses an INT, SEC or PRV alert**, and it never suppresses a blindness alert. |
| ALR-09 [7J] | An alert never acts. No alert rule, webhook receiver or automation acknowledges an entry, resolves a case, closes an incident, releases a hold, erases, seals, stops processing or sheds traffic (OD-7J-07 condition 12; PRN-01). |
| ALR-10 [OD-7J-07, condition 10] | Every SEV1 and SEV2 alert names a runbook of §24, its authoritative evidence source, and its recovery evidence: the durable fact that shows the condition ended. An alert clearing is not that fact. |
| ALR-11 [7J] | A silenced or acknowledged alert remains visible on dashboard A with who silenced it and until when. A silence on an INT, SEC or PRV alert needs the incident reference and expires in at most [CAND] 4 hours. |
| ALR-12 [OD-7J-07, condition 7] | **A page is not an approval.** No alert, severity or urgency relaxes 7I dual control: requester and approver stay different people (OD-7I-05), and an on-call engineer paged for a replay cannot approve their own request. |
| ALR-13 [7J] | Alert rules are code, reviewed, and their expressions are tested against recorded series (VT-7J-08). A rule that fails to evaluate is itself alerted (AL-54 family). |

### 23.4 Matrix — Alert rulebook

**Expression templates.** Predicates are written over the metric IDs of §8. An ID stands for the metric name of its §8 row; `M-nnn…_suffix` stands for the companion series that row names; `T_*` stands for a configured threshold; `fresh(s)` stands for the expression of EVD-09 for source `s`. Substituting those four gives PromQL that must compile: every rule file is compiled and unit-tested before use (VT-7J-08), and AL-08, AL-09, AL-50, AL-51, AL-59 and AL-60 are written out in full below because their correctness depends on their exact vector matching. No expression uses `absent()` on an unqualified metric, and no durability or blindness expression aggregates away the label it reports on. "AL-43" elsewhere in this document denotes AL-43a and AL-43b together. "fresh(s)" means the evidence source `s` is fresh (EVD-03). `T_*` are named thresholds whose values are [CAND] and set with 7K. Routing: **P1** pager primary and secondary; **P** pager primary; **S** security owner; **V** privacy owner; **C** chat and ticket.

| Alert | Class | Indicator | Predicate | Window | Threshold (status) | Sev | Route | Dedup key | Runbook | Recovery evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| AL-01 | PUB | Oldest eligible outbox age; overdue eligible rows | `M-002 > T_age_outbox and fresh(outbox)`; `sum(M-022) > 0 and fresh(outbox)` | 5 m | `T_age_outbox` 60 s (PROV); page at 10× (PROV) | SEV3; SEV2 at the page level | C; P | `family` | RB-01 | M-002 below threshold with M-005 `CONFIRMED` flowing; M-022 at zero |
| AL-02 | PUB | Eligible backlog growing | `deriv(M-001[15m]) > 0` for the whole window, with `M-001 > T_backlog` | 15 m | PROV | SEV3 | C | `family` | RB-01 | Backlog falling; age falling |
| AL-03 | AVL | Relay transport gate OPEN | `max(M-006{state="OPEN"}) == 1` on every relay | 2 m | Any full-fleet open for 2 m (PROV); 10 m | SEV2; SEV1 at 10 m | P; P1 | `region_class` | RB-02 | Gate `CLOSED` and M-002 falling |
| AL-04 | PUB | Unroutable or incompatible rows | `increase(M-014[10m]) > 0 or increase(M-052[10m]) > 0` | 10 m | Any (INV) | SEV2 | P | `family`, `cause` | RB-01 | No new occurrences after the relay or route deployment; rows published |
| AL-05 | PUB | Publisher `FAILED` rows | `M-011{disposition="UNDISPOSITIONED"} > 0`; `M-104 > T_failed_age` | 5 m | Any (INV) for the ticket; age PROV for the page | SEV3; SEV2 | C; P | `family` | RB-01 | Every `FAILED` row has a 7G disposition |
| AL-06 | PUB | CAS misses on confirmed entries | `rate(M-012[10m]) > T_cas` | 10 m | PROV | SEV3 | C | `operation` | RB-01 | Rate at baseline; lease and safety margin reviewed |
| AL-07 | PUB | Repeated rejection; contract anomaly | `increase(M-013[30m]) > 0 or increase(M-016[30m]) > 0` | 30 m | Any (INV) | SEV3 | C | `family` | RB-01 | Cause fixed forward; no new occurrences |
| AL-08 | INT | Redis durability confirmation failing, **per shard** | (a) `(sum by (shard) (rate(platform_event_redis_waitaof_results_total{result!="CONFIRMED"}[5m])) / sum by (shard) (rate(platform_event_redis_waitaof_results_total[5m]))) > T_waitaof`. (b) `(sum by (shard) (increase(platform_event_redis_waitaof_results_total{result!="CONFIRMED"}[5m])) > 0) unless on (shard) (sum by (shard) (increase(platform_event_redis_waitaof_results_total{result="CONFIRMED"}[5m])) > 0)`. Neither expression aggregates across shards: each result series carries its own `shard`, so traffic on one shard cannot dilute another | 5 m | (a) PROV; (b) any shard with unconfirmed results and no confirmation in the window (INV) | (a) SEV2; (b) SEV1 | P; P1 | `shard` | RB-02 | For that shard: confirmations resumed with no unconfirmed result; replica and AOF checks pass |
| AL-09 | AVL | Cluster, shard, capability or probe unhealthy; an expected shard with no capability evidence | `platform_event_redis_cluster_ok == 0`; `platform_event_redis_shard_capable == 0`; `increase(platform_event_redis_capability_failures_total[5m]) > 0`; `platform_telemetry_expected_shard{state="EXPECTED"} unless on (shard) (platform_event_redis_shard_capable == 1)` | 1 m | Any (FROZEN: 3F §17.1 `redis_cluster_state` critical; INV for capability and for a silent expected shard) | SEV1 | P1 | `shard`, `check` | RB-02 | All checks pass on every expected shard; probe HEALTHY |
| AL-10 | AVL | Replica unavailable or lagging | `M-032 == 0 or M-033 > T_replica_lag` | 2 m | Unavailable (INV); lag PROV | SEV2 | P | `shard` | RB-02 | Replica linked and within the bound |
| AL-11 | CON | Oldest pending age; PEL growth | `M-044 > T_pending_idle and fresh(redis_group)`; `deriv(M-043[30m]) > 0` | 10 m; 30 m | PROV | SEV3; SEV2 past the group-lag bound | C; P | `group` | RB-04 | Pending entries acknowledged or parked; M-044 below threshold |
| AL-12 | INT | Missing or unregistered consumer group | `M-048 > 0`; `M-049 > 0` | 1 m | Any (INV) | SEV1 (missing); SEV2 (unregistered) | P1; P | `family` | RB-03 | Group present per the registry through governed provisioning; trim resumed |
| AL-13 | AVL | Safe-trim pressure | `M-046` and `M-040` against `maxmemory` headroom; `M-109…_oldest_age_seconds > T_trim_pause` | 15 m | Memory above 80% (FROZEN: 3F §17.1); others PROV | SEV3; SEV2 at 90% | C; P | `family` | RB-03 | Pinning group progressing; memory below threshold |
| AL-14 | INT | TTL on a durable key | `increase(M-050[5m]) > 0` | 5 m | Any (INV) | SEV1 | P1 | `family` | RB-03 | Key reports no TTL; cause identified |
| AL-15 | CON | Consumer group not progressing; unresolved obligations | `M-041 > 0 and delta(M-042[10m]) == 0 and fresh(redis_group)`, unless a gate is open (§23.5); `sum by (group) (M-086{disposition="UNCLASSIFIED"}) > T_overdue and fresh(accounting)`; `sum by (group) (M-086{disposition="UNREGISTERED_CASE"}) > 0` | 10 m | PROV; an unregistered case any (INV: an obligation exists that accounting did not register) | SEV2 | P | `group` | RB-03; RB-17 for unregistered cases | `entries-read` advancing; lag falling; `UNCLASSIFIED` at zero. Parked and reconciliation-pending obligations stay visible in M-086 until a closing fact exists; they are AL-20's subject, not cleared by this alert |
| AL-16 | CON | Contract, version and classification anomalies | `increase(M-061{class!~"C-7\|C-9"}[15m]) > T_class`; `increase(M-072[15m]) > 0`; `M-080 > T_fence_age`; `increase(M-064[15m]) + increase(M-065[15m]) > T_ambig` | 15 m | PROV; startup refusal any (INV) | SEV3; SEV2 for a startup refusal of every worker of a group | C; P | `group`, `class` | RB-03 | Compatible deployment present; holds cleared |
| AL-17 | INT, SEC | Gateway proof mismatch; illegal or unsupported acknowledgement | `increase(M-200{cause=~"UNBOUND_.*\|TOKEN_INVALID\|TOKEN_REPLAYED_OTHER_SCOPE"}[5m]) > 0`; `increase(M-178[5m]) > 0`; `platform_event:ack_without_accounting > 0`; `rate(M-202[10m]) > T_noevid`; `rate(M-204[10m]) > T_complref` | 5 m | First three any (INV); last two PROV | SEV1; SEV2 | P1, S; P | `context`, `cause` | RB-05 | No further refusals of that cause; reconciler run clean (M-203 flat, M-206 fresh) |
| AL-18 | INT | Unaccounted obligations | `increase(M-203[15m]) > 0`; `M-206 > T_recon_age`; `deriv(M-207[1h]) > 0` | 15 m | Case opened: any (INV); reconciler age and growth PROV | SEV1; SEV2 | P1, S; P | `group`, `reason` | RB-05 | Every class `V` case resolved through R2 or owner reconciliation; reconciler current |
| AL-19 | INT | Transport-integrity violation | `M-207…_without_position > 0`; `increase(M-112[15m]) > 0`; `M-220{invariant="capture_source_missing"} > 0` | 5 m | Any (INV) | SEV1 | P1, S | `family`; `group` | RB-05, RB-07 | Invariant queries return zero; cases dispositioned |
| AL-20 | RCV | Parked-case and reconciliation backlog | `sum(M-101{case_state="PARKED"}) > T_parked`; `M-102 > T_case_age`; `M-103 > T_recon_owner_age` | 30 m | PROV | SEV3; SEV2 past the 7I material deadline band (M-195 `WITHIN_14_DAYS` > 0) | C; P | `group`; `context` | RB-06 | Cases `RESOLVED`; none approaching the material limit |
| AL-21 | CON | Repeated handler failure; poisoning | `rate(M-093[10m]) > T_fail`; `increase(M-097{reason="POISON_BUDGET_EXHAUSTED"}[15m]) > T_poison`; `increase(M-094[15m]) > 0` | 10 – 15 m | PROV; crash-loop any (INV) | SEV3; SEV2 on a burst across types | C; P | `group` | RB-06 | Failure rate at baseline; parked items replayed or dispositioned |
| AL-22 | RCV | Recovery source or material failure | `increase(M-107{result=~"SOURCE_MISSING\|PROVENANCE_MISSING"}[1h]) > 0`; `increase(M-113[1h]) > 0`; `increase(M-099[10m]) > 0`; `increase(M-105{result="failed"}[1h]) > 0` | 10 m – 1 h | Any (INV) | SEV2; SEV1 for a digest mismatch | P; P1, S | `group`, `result` | RB-07 | Each affected case has a recorded disposition |
| AL-23 | EXT | Webhook dispatch delayed | `M-125 > T_due_age and fresh(delivery)`; `M-145 > 0 and fresh(delivery)`; `M-124` growing | 5 m | 30 s (PROV, from 4G); page at 10× | SEV3; SEV2 | C; P | `region_class` | RB-08 | M-125 below threshold; M-145 at zero; closures flowing |
| AL-24 | EXT | Stale claims; uncertain sends; fence mismatch; admission lock | `M-127…_oldest_age_seconds > claim lease`; `increase(M-128{send_state="UNCERTAIN"}[15m]) > T_uncertain`; `rate(M-138[10m]) > 0`; `M-136` high quantile above `T_lock` | 10 – 15 m | Lease (FROZEN: 7H `T_claim_lease`, value 7K); uncertain PROV; fence any sustained (INV); lock PROV | SEV2; SEV3 | P; C | `region_class` | RB-08 | No `DELIVERING` row older than the lease; `UNCERTAIN` closures at baseline; fence mismatches zero |
| AL-25 | EXT | Dead-letter rate; unclassifiable closures | `increase(M-123{status="DEAD_LETTER"}[10m]) > 10`, read with the class split of M-144; `increase(M-144{closure_class="UNCLASSIFIED"}[15m]) > 0` | 10 – 15 m | 10 in 10 m (FROZEN: 3E §14.4); class split PROV; unclassified any (INV) | SEV3; SEV2 when the platform classes (`NOT_SENT_PLATFORM`, `SENT_FAILED_PLATFORM`, `UNCERTAIN`) dominate or any closure is unclassified | C; P | `topic`; `closure_class` | RB-08 | Platform-class dead letters stopped; affected deliveries replayable by the tenant; `UNCLASSIFIED` at zero |
| AL-26 | SEC, EXT | Signing secret unavailable | `increase(M-134{secret_role="PREVIOUS"}[5m]) > 0`; `rate(M-134{secret_role="CURRENT"}[10m]) > T_secret` | 5 m; 10 m | PREVIOUS: first occurrence (INV, 7H SIG-18); CURRENT PROV | SEV2 | P, S | `secret_role` (in region only; not in the external notification) | RB-09 | Secret resolvable; no purge before expiry found, or the purge corrected and audited |
| AL-27 | EXT | Held backlog growth; uncounted releases | `deriv(M-126[6h]) > 0` and oldest age above `T_held`; `rate(M-164[1h])` for information | 6 h | PROV | SEV4; SEV3 near the 90-day hold expiry (7H OD-7H-02) | C | `org_status` | RB-08 | Not an on-call matter: lifecycle owner informed |
| AL-28 | SEC, EXT | Callback verification failure burst | `rate(M-152[5m])` above `T_verify` and above its trailing baseline | 5 m | PROV | SEV3; SEV2 when sustained for one provider with zero successes | C; P | `provider` | RB-10 | Verification succeeding; cause classified (attack, provider rotation, misconfiguration) |
| AL-29 | EXT, INT | Callback receipt stuck; acknowledgement without a receipt | `M-155 > T_receipt_age and fresh(receipt)`; `increase(M-149{basis="NO_RECEIPT"}[5m]) > 0` | 10 m; 5 m | Age PROV; acknowledgement without receipt any (INV) | SEV2; SEV1 | P; P1 | `provider`, `status` | RB-10 | No non-terminal receipt older than the bound; `NO_RECEIPT` at zero and the code path fixed |
| AL-30 | SEC | Tenant-isolation signal | `increase(M-066[5m]) > 0 or increase(M-181[5m]) > 0 or increase(M-182[5m]) > 0` | 5 m | Any (INV) | SEV1 | P1, S | `group`; `principal_class` | RB-11 | Case reconciled; cause removed; pool verified clean |
| AL-31 | SEC | Unauthorized recovery, self-approval, material access | `increase(M-170{cause="SELF_APPROVAL"}[15m]) > 0`; `rate(M-170[1h]) > T_refuse`; `increase(M-171{event="DENIED"}[1h]) > T_view` | 15 m; 1 h | Self-approval any (INV); rates PROV | SEV2 | P, S | `mode`, `cause` | RB-11 | Reviewed against the audit rows; credentials and grants confirmed |
| AL-32 | SEC | Egress and residency refusals | `rate(M-142[15m]) > T_egress`; `increase(M-174{policy="RESIDENCY"}[15m]) > 0` | 15 m | Rate PROV; residency at delivery time any (INV) | SEV3; SEV2 | C; P, S | `rule_class`, `policy` | RB-11 | Destination configuration corrected by the tenant, or the attempt classified |
| AL-33 | SEC | Privilege and authorization-proof violations | `increase(M-219{object_class!="OTHER"}[10m]) > 0` for the classes of §20.1 rows 4 – 6, 20; `M-220 > 0`; `increase(M-176[5m]) > 0`; `rate(M-221[10m]) > T_proof`; `increase(M-222[10m]) > 0`; `increase(M-225[1h]) > 0` | 5 – 10 m | Invariant queries and break-glass any (INV); proof-refusal rate PROV | SEV1 for M-220, M-176 and the admin classes; else SEV2 | P1, S; P, S | `object_class`; `invariant` | RB-11 | Invariant queries return zero; credential review recorded |
| AL-34 | SEC | Redis ACL parity; denied segment | `M-175 > 0`; `increase(M-177[5m]) > 0` | 1 m | Any (INV). M-177 is BLOCKED (H-7I-04 a) | SEV1 | P1, S | `region_class` | RB-05 | Digest equal on every node; node readmitted only then |
| AL-35 | INT, SEC | Unexplained stream shrink; unknown-origin entries | `increase(M-179[5m]) > 0`; `increase(M-180[15m]) > 0` | 5 m | Any (INV). M-180 is BLOCKED (H-7I-04 b) | SEV1 | P1, S | `family` | RB-05 | Reconciler run complete for the affected key; cases dispositioned |
| AL-36 | SEC | Secret or personal data found in a sink | `increase(M-184[1h]) > 0` | 1 h | Any (INV) | SEV2; SEV1 for a credential class | P, S; V for personal data | `sink_class`, `pattern_class` | RB-11 | Value rotated; line removed; emitter fixed; regression test added |
| AL-37 | SEC | Key service | `rate(M-185[5m]) > T_keysvc`; `increase(M-186[5m]) > 0` | 5 m | Rate PROV; use outside a grant any (INV) | SEV2; SEV1 | P; P1, S | `purpose` | RB-07, RB-11 | Key service answering; grants reviewed |
| AL-38 | INT | Mandatory audit integrity | `rate(M-190[5m]) > 0` sustained; `time() - M-191 > T_chain`; a failed chain verification | 5 m; 1 h | Audit-write failure sustained (INV); chain period 26 h (PROV, nightly job per 5J §15) | SEV1 | P1, S | `principal_class` | RB-11 | Audit writes succeeding; chain verified through the present |
| AL-39 | PRV | Erasure journal unavailable | `increase(M-210[5m]) > 0`; `M-212 > 0 and time() - M-213 > T_journal`; `M-215 > T_checkpoint` | 5 m | First failed append (INV, 7I JRN-29 "at once"); others PROV | SEV1 | P1, S, V | `region_class` | RB-13 | Appends confirmed; waiting steps drained; no deadline passed, or each breach recorded |
| AL-40 | PRV, INT | Restore completeness; journal tampering; incarnation | `M-216{state="FAILED_CLOSED"} == 1`; `increase(M-214[5m]) > 0`; `increase(M-218[5m]) > 0` | 1 m | Any (INV) | SEV1 | P1, S, V | `state`; `operation` | RB-14 | Reconciliation complete and verified (7I JRN-26); activation record issued |
| AL-41 | PRV | Overdue erasure; retention deadline | `M-217{band="MISSED"} > 0`; `M-251 > 0 and M-252 > T_pass_cadence`; `M-195{band="PAST_LIMIT"} > 0`; `M-194 > 0` past cadence; `time() - M-262 > T_pass`; `M-242…_oldest_age_seconds > T_seal`; `increase(M-243[15m]) > 0`; `M-224 > T_approved` | 15 m | A missed deadline (INV); cadence-relative thresholds PROV | SEV1 for a missed deadline; SEV2 for a stopped pass or a failing seal | P1, V, S; P, V | `store` | RB-12 | Rows erased or sealed with journal completion; each breach recorded as an incident |
| AL-42 | PRV | Privacy-retention incident | `M-240 > 0` (opens and repeats by escalation level); `M-196 > 0`; `M-237…_late_opened > 0`; expiring exceptions | 15 m | Any (INV); escalation intervals 7, 30, 90 days ([REC] in 7I HE-7K-7I-15, 7K fixes) | SEV1 at opening and at each escalation; SEV3 for a passed review date | P1, V, S; C | `escalation_level` | RB-12 | A disposition function closed the incident (7I SEAL-10). **Not** the alert clearing |
| AL-43a | PRV, SEC | Illegal sealed-content access; guard anomalies | `increase(M-247{event="DENIED"}[15m]) > 0`; `increase(M-257[15m]) > 0`; `increase(M-219{object_class="CONTENT_COLUMN"}[15m]) > 0`; `rate(M-254[15m])` above baseline; `increase(M-255[15m]) > 0` | 15 m | Denied inspection, restore attempt and `42501` any (INV); guard denial rate PROV | SEV1; SEV3 for the rate | P1, V, S; C | `path` | RB-16 | Reviewed against the audit rows; credential review |
| AL-43b | PRV | Subject-index certification and completeness | `increase(M-261[1h]) > 0`; `increase(M-260{event="DEMOTED"}[1h]) > 0`; `increase(M-238[1h]) > 0`; `M-231…_oldest_age_seconds > T_unverified`; `increase(M-249[15m]) > 0`; `M-248…_compromised_edges > 0`; `increase(M-232[1h]) > 0` | 15 m – 1 h | Failure, demotion, compromised version any (INV); ages PROV | SEV2; SEV1 for a compromised key version | P, V; P1, V, S | `relation_class`; `cause` | RB-15 | Relation verified; certification restored by the governed procedure |
| AL-44 | PUB | Reconciler fallbacks | `rate(M-019{action="FALLBACK_RESOLVED"}[1h]) > T_fallback` | 1 h | PROV | SEV3 | C | `flow` | RB-01 | Primary dispatch path restored |
| AL-45 | PUB | Voice dispatch held; stale commands | `M-021…_oldest_age_seconds > T_dispatch`; `increase(M-020{result=~"EVIDENCE_UNOBTAINABLE\|CANCELLED_BUT_RINGING"}[15m]) > 0` | 15 m | PROV | SEV3; SEV2 for a divergence | C; P | `state` | RB-01 | Keys reconciled by provider evidence or by an operator (7D VDK-07) |
| AL-46 | PUB | Unfinalized or corrupt Voice accounting | `M-146…_oldest_age_seconds > T_finalize`; `increase(M-148[1h]) > 0` | 1 h | PROV; corrupt state any (INV). **BLOCKED** (H-7B-01) | SEV3; SEV2 | C; P | `cause` | RB-01 | Conversations finalized, or routed and reconciled; nothing synthesized |
| AL-47 | SEC, RCV | Abnormal replay activity | Rates of M-106, M-107, M-140 above trailing baseline; an operation `STARTED` with no matching `APPROVED` (rule over M-106) | 15 m | Baseline PROV; start without approval (INV) | SEV3; SEV1 | C; P1, S | `mode` | RB-11 | Operation paused by an authorized operator; audit rows reviewed |
| AL-48 | AVL | Gateway or authorization issuer unavailable | `sum(M-201) == 0`; `sum(M-201) < 2`; `M-226 == 0` | 2 m | Zero instances (INV); below two PROV | SEV2; SEV3 | P; C | `component` | RB-03 | Instances ready; consumers reading |
| AL-49 | EXT | Plugin limiter unavailable | `rate(M-159{result="UNAVAILABLE"}[10m]) > 0` sustained; breaker open | 10 m | PROV | SEV3 | C | `region_class` | RB-08 | Limiter answering; breaker closed |
| AL-50 | OBS | **An expected evidence source is not reporting** (monitoring blindness, per source) | `platform_telemetry_expected_source{state="EXPECTED"} unless on (source) ((time() - max by (source) (platform_telemetry_evidence_last_success_timestamp_seconds)) < T_fresh)`. Fires with the `source` label of each missing or stale source, whether or not other sources report (EVD-09). No unqualified `absent()` | 3 scrapes | `T_fresh` PROV; the alert itself INV | SEV1 for `outbox`, `accounting`, `ledger`, `journal`, `retention`, `redis_group`; SEV2 otherwise | P1; P | `source` | RB-17 | That source's read succeeding; dependent panels fresh |
| AL-51 | OBS | **An expected workload component is not heart-beating** | `platform_telemetry_expected_component{state="EXPECTED"} unless on (component, group) ((time() - max by (component, group) (platform_telemetry_heartbeat_timestamp_seconds)) < on (component, group) platform_telemetry_expected_component_max_age_seconds)`. Fires with the `component` and `group` of each missing one; instances and replacements do not matter | 3 scrapes | Per-component permitted age from the registry (PROV); the alert itself INV | SEV2; SEV1 for relay, gateway, obligation reconciler, retention pass, journal writer, state observer | P; P1 | `component`, `group` | RB-17, and the stage runbook | Heartbeat present for that (component, group); stage state known |
| AL-52 | OBS | Telemetry being dropped | `rate(M-273[10m]) > T_drop` | 10 m | PROV | SEV3; SEV2 when security-class lines are dropped | C; P | `signal`, `cause` | RB-17 | Drop rate zero |
| AL-53 | OBS | Cardinality over budget | `M-276` above the group budget; `increase(M-275[10m]) > 0`; a scrape failing its sample limit | 10 m | Budget PROV; label rejection any (INV) | SEV3; SEV2 when a scrape of a Tier C target fails | C; P | `metric_group` | RB-17 | Series below budget; offending registration fixed |
| AL-54 | OBS | Dead-man: alert evaluation or routing stopped | The always-firing watchdog stops arriving at the external heartbeat receiver | Receiver-side timeout | Fixed by the heartbeat receiver (PROV) | SEV1 | External heartbeat pages P1 | `region_class` | RB-17 | Watchdog arriving; a test alert delivered end to end |
| AL-55 | OBS | Notification delivery failing | `rate(M-278[10m]) > 0` | 10 m | Any sustained (INV) | SEV2 | The other receiver class; in-region console | `receiver_class` | RB-17 | Notifications accepted |
| AL-56 | OBS | Clock offset | `abs(M-279) > T_clock` | 5 m | PROV | SEV3 | C | `component` | RB-17 | Offset within bound |
| AL-57 | SEC, OBS | Telemetry configuration or access anomaly | `increase(M-282[5m]) > 0` with no approved change; destination drift; direct store access; `rate(M-280{result="denied"}[1h]) > T_qdeny` | 5 m | Unapproved change and drift any (INV); rate PROV | SEV1; SEV3 | P1, S; C | `object_class` | RB-17 | Configuration equals the governed source; exposure assessed |
| AL-58 | OBS | SLO aggregate history at risk | `M-281 > T_fed`; a gap in an `slo:` series approaching 30 days from expiry | 1 h | PROV | SEV3 | C | `region_class` | RB-17 | Aggregates backfilled from raw series before those expire |
| AL-59 | OBS | **An expected accounting-stream fold is not reporting**; accounting behind; permanent loss declared | (a) `platform_telemetry_expected_stream{state="EXPECTED"} unless on (stream, fold_kind) ((time() - max by (stream, fold_kind) (platform_telemetry_observation_fold_last_success_timestamp_seconds)) < on (stream, fold_kind) platform_telemetry_expected_stream_max_age_seconds)`. Fires with the `stream` and `fold_kind` of each missing fold, for each of the sixteen registry entries on its own, whether its series is stale or gone, and whatever the other streams and the `accounting` source are doing. (b) `platform_telemetry_observation_unaccounted_oldest_age_seconds > T_fold`. (c) `increase(platform_telemetry_observation_unmeasured_seconds_total[1h]) > 0` or `increase(platform_telemetry_observation_unmeasured_cohort_hours_total[1h]) > 0` | 3 scrapes; 10 m; 1 h | (a) the registry's permitted age per fold (PROV); the alert itself INV. (b) PROV. (c) any (INV) | (a) SEV2; SEV1 when the fold missing is the completeness fold of a stream that backs a reported indicator and its age is inside the safety margin `m` of `R_min` (a declaration of permanent loss is imminent, AOA-11). (b) SEV3; SEV2 inside that margin. (c) SEV2 | P; P1; C | `stream`, `fold_kind`; `cause` | RB-17 | That stream's routine and completeness folds both fresh; backlog folded; a late fold caught up with no declaration, or the declared hours finalized unmeasured with their cause; nothing back-filled |
| AL-60 | OBS | An accounted indicator cannot be reported, is only partly measured, or was restated | `platform_event_slo_window_state{state="UNKNOWN"} == 1`; `platform_event_slo_window_state{state="NOT_ESTABLISHED"} == 1`; `platform_event_slo_window_state{state="ESTABLISHED_PARTIAL"} == 1`; `platform_event_slo_window_state{state="ESTABLISHED_UNCERTAIN"} == 1`; `platform_telemetry_observation_unsettled_oldest_window_age_seconds > T_unsettled` (an unsettled delivery is nearing the lifetime of its lifecycle evidence; `T_unsettled` is set well below it); `platform_event_slo_window_obligations{part="unattributed"} > 0`; `platform_event_slo_window_obligations{indicator="SLI-11", part="uncertain_registered"} > T_uncertain`; an expected indicator with no state series at all: `platform_telemetry_expected_stream{state="EXPECTED", fold_kind="completeness"} unless on (stream) (time() - platform_event_slo_cohort_final_through_timestamp_seconds < T_final_lag)`; `increase(platform_event_slo_post_final_corrections_total[1d]) > T_corrections` | 30 m; 1 d | Watermark lag, correction volume and the uncertain share PROV; `UNKNOWN` sustained, and a failed read-function check (a negative count; hours not summing to 672) (INV) | SEV3; SEV2 when an approved objective's window is `UNKNOWN` for longer than [CAND] 6 hours, or the read-function check fails | C; P | `indicator`, `scope`; `stream` | RB-17 | Watermark within its lag; state `ESTABLISHED`, or `ESTABLISHED_PARTIAL` with every unmeasured hour tied to a recorded declaration and its incident; corrections explained (late-visible rows, past-dated origins, not-owed classification, eligibility moves); a high uncertain share traced to a slow fold or a long lifecycle transaction, or to an evidence fault with its 7I integrity alarm |

### 23.5 Inhibition and storm control

| Cause paged | Symptoms inhibited while it fires | Never inhibited |
|---|---|---|
| AL-09 or AL-08 (Redis unhealthy; durability failing) | AL-01, AL-02 (backlog and age, expected under an open gate), AL-03 at SEV2, AL-11, AL-15, AL-23, and all burn-rate alerts of publication and consumer objectives | AL-12, AL-14, AL-17, AL-18, AL-19, AL-35 |
| An owner database dependency gate open for a group (M-095) with its dependency alert firing | AL-11, AL-15, AL-21 for that group | AL-17, AL-18 |
| AL-48 (gateway down) | AL-11, AL-15 for every group | AL-18 (the deadline of 7I ACC-17 still applies) |
| AL-39 (journal down) | AL-41's cadence-relative conditions (stopped pass, sealing backlog) | AL-41's missed-deadline condition; AL-42 |
| Key service or secret manager unavailable (AL-37 rate; M-185) | AL-22 parking failures; AL-26 CURRENT; AL-23 | AL-26 PREVIOUS; AL-37 use outside a grant |
| AL-50 for a source | Every threshold alert over **that same source** (they cannot evaluate; ALR-02), matched on equal `source` | AL-50 for any other source; AL-51; AL-54; AL-59; AL-60; every INT, SEC and PRV alert |

| ID | Rule |
|---|---|
| STM-01 [7J] | **One page per cause.** A prolonged Redis outage produces AL-09 (or AL-08) once, re-notified on the repeat interval, with the outbox age shown in region as the measure of what is waiting. It does not produce a page per family, per group or per minute. |
| STM-02 [7J] | **A dependency-gated consumer raises no handler-failure alert**, because it records no failure (RCV-01), and its stall alert is inhibited by the dependency's own alert. If the dependency alert is not firing while the gate is open, the stall alert is not inhibited: an open gate with no visible cause is itself the finding. |
| STM-03 [7J] | Inhibition is expressed with labels of §9.1 only, and its rules are tested (VT-7J-41). |
| STM-04 [7J] | When the cause clears, inhibited alerts are evaluated normally; catch-up lag after recovery is expected and has its own thresholds through `T_*` values that 7K sets for catch-up (HE-7K-7J-07). |
| STM-05 [7J] | **Inhibition is a closed list.** Each inhibition rule names one cause alert and a fixed list of target alert names, matched on equal `region_class` and, where both carry it, equal `group`, `shard` or `source`. The permitted targets are exactly those of the table above. The build rejects an inhibition rule whose target is any alert of class INT, SEC or PRV, AL-50, AL-51, AL-54, AL-59 or AL-60, or that matches targets by a pattern instead of by name. A Redis outage therefore cannot hide a journal outage, a tenant-isolation signal, an unaccounted obligation or an unrelated blind source. |

### 23.6 External notification contract (OD-7J-04)

| ID | Rule |
|---|---|
| NTF-01 [OD-7J-04] | **Fields that may leave the region**, and no others: alert ID (for example `AL-18`); severity; `region_class`; component or alert class; a bounded outcome or failure classification from a closed set; one generic link to the in-region dashboard or runbook. |
| NTF-02 [conditions 1, 2, 3] | **Never in an external notification:** an organization, tenant, user, event, contact, call, delivery, case or correlation identifier; a tenant destination URL or host; a secret; an exception message; personal data; a payload; a credential; any free text; any label value that is not in the closed sets of NTF-01. |
| NTF-03 [condition 5] | **Templates are allow-lists.** One fixed template per receiver class, rendered by Alertmanager in region. A template references only the named fields of NTF-01; it never iterates over "all labels" or "all annotations". Alert rules may define only the annotations `runbook` and `dashboard`, whose values are constants. |
| NTF-04 [condition 6] | **Build check.** The build fails if: a template references a field outside NTF-01; a rule defines any other annotation; an annotation or link contains a template expression over a label; a rule's labels include a name outside §9.1. A rendered-output test renders every alert with hostile label values and asserts that only NTF-01 fields appear (VT-7J-42). |
| NTF-05 [condition 10] | **Links** are fixed paths to a dashboard or a runbook page. They carry no token, no identifier, no query parameter and no signed component. |
| NTF-06 [condition 9] | A recipient reads detail only after authenticating to the in-region tools under §22.2. The notification grants nothing. |
| NTF-07 [condition 7] | **Content-free tier.** For a stack whose contracts prohibit sanitized metadata egress, the notification is the single fixed sentence "check the in-region console" with the severity, provided that sentence is itself permitted. The tier is a per-stack configuration value, changed only as a `PLATFORM_CONFIG_CHANGED`. |
| NTF-08 [condition 8] | **In-region-only tier.** Where no external notification is permitted, alerts go to an authorized in-region notification mechanism. **No such mechanism is selected by this document**, because selecting one is a new product or destination that needs the owner's approval. Until one is approved and built, a stack bound by such a contract cannot be activated (AG-7J-09). |
| NTF-09 [condition 4] | Detail stays in region: Alertmanager, its history, Grafana, the broker. |
| NTF-10 [condition 11] | Notification is asynchronous and downstream of alert evaluation. A failing pager or chat receiver cannot affect a claim, a publication, a handler, an acknowledgement or an audit write: none of them calls Alertmanager. |
| NTF-11 [condition 12] | **Delivery failure and fallback.** A notification a receiver did not accept is retried by Alertmanager, counted (M-278) and alerted through the other receiver class (AL-55). If both external classes fail, the alert remains visible on the in-region console and on dashboard A, and the dead-man path (AL-54) pages independently when routing as a whole stops. |
| NTF-12 [condition 12] | **Routing health** is tested by a scheduled synthetic alert of a fixed test ID that must arrive end to end ([CAND] daily); its absence is AL-54's secondary condition. |
| NTF-13 [condition 13] | 3F §17.2 groups by `tenant_id` and shows a free-form annotation style. Both are superseded for event-plane alerts by LBL-10 and NTF-03, as controlled errata (ERR-7J-05, ERR-7J-08). 3F is not edited. |
| NTF-14 [condition 14] | The notification contract is the same for every residency profile unless NTF-07 or NTF-08 applies. It never weakens 7I RSY-11: metrics, logs and traces stay in region in every tier. |

---

## 24. Incident Response and Runbooks

Common to every runbook. **Permissions:** T0 to read dashboards; T2 or T3 with a case-bound grant for anything tenant- or event-specific (§22.3); recovery actions only through the frozen 7G operations under 7I §13 authorization, with dual control where 7I requires it. **Forbidden in every runbook:** issuing `XACK`, `XDEL`, `XTRIM`, `XCLAIM`, `XAUTOCLAIM`, `XGROUP SETID`, `XGROUP CREATE` or `XGROUP DESTROY` by hand; updating or deleting an outbox row, a delivery row, a receipt, a recovery case, an accounting, position or completion record, a hold, a journal object or an audit row by hand; using break-glass credentials as a recovery path (7G AUT-06; 7I RDS-11); self-approving an operation; treating a cleared alert as recovery.

### RB-01 — PostgreSQL outbox backlog is growing

- **Trigger:** AL-01, AL-02, AL-04 … AL-07, AL-44 … AL-46.
- **Impact:** every downstream effect of new events is late. Nothing is lost: rows are committed and retained (7D GATE-07, CLN-02).
- **Authoritative source:** `audit.domain_event_outbox` through the observer figures M-001, M-002, M-011; relay state M-005, M-006.
- **Investigate:** dashboard B. Is the gate open (then RB-02)? Are outcomes `CONFIRMED` but slow (capacity)? `RELAY_CAPABILITY` or `NONE` routes (a relay or route deployment is behind)? `FAILED` rows (7G disposition)? Is the relay alive (AL-51)?
- **Permissions:** T0; T2 grant to look at specific rows by `event_type` and time.
- **Forbidden:** marking rows published; deleting or editing rows; lowering durability confirmation to catch up; restarting producers.
- **Containment:** none needed for data; scale relay instances within 7K's limits.
- **Recovery:** fix the cause (transport, deployment, capacity). `FAILED` rows: 7G §27 disposition and, where chosen, R5 redrive under dual control.
- **Validate:** M-002 below threshold and falling; M-005 `CONFIRMED` rate above production rate; M-207 `…_without_position` zero.
- **Closure evidence:** the age series; for `FAILED` rows, each row's recorded disposition.

### RB-02 — Redis cannot confirm durable publication

- **Trigger:** AL-03, AL-08, AL-09, AL-10.
- **Impact:** publication paused by design; outbox grows; consumers drain what is already in the streams. No committed event is lost.
- **Authoritative source:** the adapter's per-entry outcomes (M-035, M-038); probe and capability checks (M-008, M-036); cluster state (M-030 … M-033).
- **Investigate:** dashboard C. Which check fails: replica missing or lagging, AOF disabled or failing, memory at limit (`OOM`), cluster state, a wrong replica topology?
- **Permissions:** T0; infrastructure role for the cluster itself.
- **Forbidden:** disabling `WAITAOF`; accepting `[1, 0]`; adding a second replica or changing `maxmemory-policy` outside the governed topology; deleting stream data to free memory; closing the relay gate by hand; marking `UNKNOWN` rows published.
- **Containment:** the open gate is the containment. Watch outbox age and database capacity.
- **Recovery:** restore the replica, AOF or memory headroom; for memory, the remedy is consumer progress and trimming below the watermark, or capacity (7E MEM-03).
- **Validate:** probe HEALTHY; gate `CLOSED`; `CONFIRMED` ratio restored; M-002 falling.
- **Closure evidence:** capability checks passing on every shard; the backlog drained; `UNKNOWN` rows republished and marked.

### RB-03 — Consumer group stops making progress

- **Trigger:** AL-12, AL-13, AL-14, AL-15, AL-16, AL-48.
- **Impact:** that group's effects stop; its entries pin the stream.
- **Authoritative source:** `XINFO GROUPS` figures (M-041 … M-044); worker heartbeats (M-272); the group registry; handler-contract admission (M-072, M-073).
- **Investigate:** apply RDO-02. Workers absent, refused at start, or running with a gate open? Gateway ready (M-201)? Group missing or unregistered (M-048, M-049)?
- **Permissions:** T0; T2 grant for worker logs.
- **Forbidden:** recreating a group at `$`; `XGROUP SETID`; deleting an "unknown" group to unpin trimming; acknowledging to clear lag; bypassing the gateway.
- **Containment:** none automatic. If memory pressure approaches (AL-13), prioritise restoring the pinning group.
- **Recovery:** restore workers or their dependency; deploy compatible code for a version hold; a missing group is restored only by governed provisioning with trimming paused (7E TRM-07, BST rules); key onboarding completes a key-not-onboarded hold.
- **Validate:** `entries-read` advancing; pending bounded; M-048 zero.
- **Closure evidence:** group present per the registry; lag at zero or falling; no hold older than its bound.

### RB-04 — PEL grows while handler failures remain low

- **Trigger:** AL-11 with M-093 flat.
- **Impact:** entries delivered and not finished: workers are dying, hanging, gated, or their acknowledgements are not taking effect.
- **Authoritative source:** M-043, M-044; M-095; M-094; M-067, M-069, M-202; reclaim figures M-090, M-091.
- **Investigate:** gate open (then the dependency)? Crash-loop suspected (M-094)? Commits succeeding (M-063) while acknowledgements are refused or zero (M-067, M-202)? Sweep running (heartbeat)?
- **Permissions:** T0; T2 grant.
- **Forbidden:** manual `XACK` or `XCLAIM`; raising the poison budget; disabling the gateway's evidence check.
- **Containment:** none; entries are retained.
- **Recovery:** restore the dependency; fix the crashing handler (isolation parks the entry, 7G §17); if commits succeed and acknowledgements are refused for missing evidence, treat as RB-05.
- **Validate:** M-044 below threshold; reclaimed entries completing.
- **Closure evidence:** pending count at baseline; every isolated entry parked or processed.

### RB-05 — Missing obligation evidence after a suspected unauthorized acknowledgement

- **Trigger:** AL-17, AL-18, AL-19, AL-34, AL-35.
- **Impact:** an event may have left Redis for a group without being processed. Possible business loss for that group until recovered; possible compromise of the gateway or its credential.
- **Authoritative source:** PostgreSQL only: accounting rows, position records, registration records, completion records, recovery cases (7I ACC-01 … ACC-20). Redis is corroboration (GIM-03).
- **Investigate:** dashboard G. Apply the cause table of §20.2 to the affected pairs. Check M-175, M-176, M-178, M-179 for how. Use a T3 grant for the security-class records of the refusals and of the reconciler's cases.
- **Permissions:** T3 with an incident reference; R2 operations under 7I §13 (dual control for the high-risk groups, OPA-07).
- **Forbidden:** re-publishing the event to "be safe" outside R4; writing an accounting or completion row; resetting a cursor; inferring delivery from `published_at` or an entry ID's time; waiting for the forensic conclusion before recovering.
- **Containment:** rotate the gateway's Redis credential (7I RDS-13) if compromise is credible; keep the node with an ACL mismatch out of traffic.
- **Recovery:** the reconciler has captured the outbox row and opened a class `V` case (ACC-05). Recover through R2: the bytes go through the 7F pipeline and the guard decides. `COMPLETION_EVIDENCE_UNATTRIBUTED` cases are resolved only by the owning domain's reconciliation (CEV-09).
- **Validate:** each case `RESOLVED` with a completion record or an owner reconciliation; reconciler run after the fix opens no new case; interlock-held rows released.
- **Closure evidence:** case histories; the audit rows of the operations; a clean reconciler run.

### RB-06 — Handler repeatedly fails with poison input

- **Trigger:** AL-20, AL-21.
- **Impact:** specific events are not processed for one group; other entries are unaffected (7G RTY-12).
- **Authoritative source:** the recovery ledger: cases, failure counts, reasons, history.
- **Investigate:** dashboard E: one type or many; one group or many; started with a deployment? The redacted material view (7I MAT-01) shows which validation step failed, without content.
- **Permissions:** `recovery.*` capabilities of 7I §13; unmasked material only under MAT-02 dual control.
- **Forbidden:** editing material; lowering validation to pass; deleting cases; rejecting a class `V` case; replaying before the fix.
- **Containment:** parking is the containment.
- **Recovery:** fix forward; R2 replay of the parked cases (bulk after a validator defect, 7G IMP-07); a genuinely invalid event gets a reasoned disposition where 7G §24.4 permits.
- **Validate:** replay item results obligation-closing (M-107); M-101 falling.
- **Closure evidence:** every case `RESOLVED` with its resolution; none past the material deadline band.

### RB-07 — Recovery source material is missing or corrupted

- **Trigger:** AL-19, AL-22, AL-37.
- **Impact:** an obligation exists and its replay source does not, or cannot be trusted.
- **Authoritative source:** the ledger's material record and digest; the replay source hierarchy of 7G RMD-05; the outbox row if still retained; the owner domain's own state.
- **Investigate:** which result: `SOURCE_MISSING`, `PROVENANCE_MISSING`, digest mismatch, key service unavailable, material erased by a privacy deadline (7I OD-7I-06, -12)?
- **Permissions:** event operations; security for a digest mismatch.
- **Forbidden:** reconstructing an event from logs, traces or metrics; fabricating provenance; marking the case resolved without a source.
- **Containment:** a digest mismatch is a security incident: preserve the case and stop operations on that group's material.
- **Recovery:** use the next permitted source (outbox row for R4; owner reconciliation R6). Where no source exists, the case goes to the owning domain's reconciliation; the outcome is `OWNER_RECONCILED` or a reasoned disposition, never a silent close.
- **Validate:** each affected case has a recorded disposition and its reference.
- **Closure evidence:** case histories; the owner's reconciliation reference.

### RB-08 — Webhook dispatch stuck in DELIVERING

- **Trigger:** AL-23, AL-24, AL-25, AL-27, AL-49.
- **Impact:** tenant integrations receive events late or not at all.
- **Authoritative source:** `webhooks.webhook_deliveries` and the claim, admission and closure records (7H).
- **Investigate:** dashboard F. Dispatcher alive? Sweep alive (stale claims are released by it, T-08)? Which closure class dominates (§19.2): the platform classes `NOT_SENT_PLATFORM`, `SENT_FAILED_PLATFORM`, `UNCERTAIN` (ours), or `SENT_FAILED_EXTERNAL`, `NOT_SENT_EXTERNAL` (theirs)? `UNCERTAIN` rising means dispatcher processes die between admission and closure; each such request may have reached the receiver. Uncounted releases and held rows are not faults. Claims without admissions point at the admission function or its locks; admissions without closures point at the send or record step.
- **Permissions:** T0; T2 grant for a delivery or endpoint.
- **Forbidden:** setting a delivery's status by hand; clearing a claim; resending outside the frozen replay route; disabling egress validation; treating held rows as stuck.
- **Containment:** none for receiver-side failures; they retry on the frozen schedule.
- **Recovery:** restore the dispatcher, sweep or dependency. Dead letters are replayable by the tenant through the frozen route.
- **Validate:** no `DELIVERING` row older than the lease; due age below threshold.
- **Closure evidence:** closure records for the affected deliveries.

### RB-09 — Previous webhook signing secret unexpectedly unavailable

- **Trigger:** AL-26.
- **Impact:** deliveries to endpoints in a rotation grace period close `SECRET_UNAVAILABLE` and spend attempts; receivers still verifying with the previous secret could reject. A platform fault by definition (7H SIG-18).
- **Authoritative source:** closure records with the secret role (restricted); the endpoint's rotation audit rows; the secret manager's own audit log.
- **Investigate:** was a previous secret purged before its expiry (7H SEC-7H-04 forbids it)? Is the secret manager failing (M-185)? One endpoint or many?
- **Permissions:** T3 grant (the role is restricted diagnostic information); secret-manager audit read.
- **Forbidden:** telling the tenant which role failed, or anything beyond category and origin (7I TVF-02); sending unsigned; re-creating a secret value by hand; extending or shortening the grace window.
- **Containment:** if the secret manager is failing, deliveries retry on schedule.
- **Recovery:** restore secret-manager availability; if a purge happened early, that is a defect in the purge path: stop the purge job, fix it, and record the incident. Affected dead letters are replayable.
- **Validate:** M-134 `PREVIOUS` flat; attempts for the affected endpoints closing normally.
- **Closure evidence:** the purge-path finding; the secret manager's audit trail.

### RB-10 — Provider callback receipt stuck after acknowledgement

- **Trigger:** AL-28, AL-29.
- **Impact:** a provider was told "received" and the fact has not been applied (call status, billing webhook).
- **Authoritative source:** the receipt rows and their stored processing inputs (7H CBK-10).
- **Investigate:** sweep alive? Key service available (the input is encrypted)? Owner context rejecting deterministically (then `SKIPPED` or `FAILED` is correct)? For verification bursts: one provider, source pattern, a recent provider key rotation?
- **Permissions:** T0; T2 grant for a receipt.
- **Forbidden:** asking the provider to resend as the fix; processing from logs; deleting a receipt; setting its status by hand.
- **Containment:** none; the receipt is durable.
- **Recovery:** restore the sweep or dependency; the processor rebuilds the command from the stored input and current state.
- **Validate:** no non-terminal receipt older than the bound.
- **Closure evidence:** receipts terminal with their status and category.

### RB-11 — Unauthorized replay or material-access attempt (and other authorization signals)

- **Trigger:** AL-30 … AL-33, AL-36, AL-37, AL-38, AL-47, and §20.1 rows 1 – 12, 17, 21.
- **Impact:** an attempt was refused. Assess whether any related action succeeded.
- **Authoritative source:** the audit rows of the refusals (7I AUD-7I-07, OPA-14); the security-class records; the database log for `42501`.
- **Investigate:** who (actor reference at T3), what capability, which target; is it an operator mistake, a tool defect or a stolen credential? Are there successful operations by the same actor nearby?
- **Permissions:** T3 with the incident reference.
- **Forbidden:** granting the capability to make the alert stop; approving one's own request; viewing material to "check" without MAT-02.
- **Containment:** revoke the actor's grants or rotate the workload credential when compromise is credible.
- **Recovery:** none for the refused action. For a tenant-isolation signal: the entry is already a case; the owner reconciles. For an audit-integrity failure: restore the audit path before the gated actions resume (they are refused meanwhile).
- **Validate:** no further refusals of that pattern; invariant queries zero.
- **Closure evidence:** the review record; credential or grant changes with their audit rows.

### RB-12 — Privacy erasure deadline missed

- **Trigger:** AL-41, AL-42.
- **Impact:** data is retained past an authorized limit. A compliance incident for the privacy and security owner.
- **Authoritative source:** the step tables and journal for request-driven erasure; the content stores and their deadlines for time-based erasure; incident records (7I SEAL-04).
- **Investigate:** dashboard H. Why: journal down (RB-13), pass stopped, hold or exception in force (then it is held, not missed), uncertain material awaiting a decision, sealing failing?
- **Permissions:** T3; `retention.hold.manage` for decisions, dual control as 7I requires.
- **Forbidden:** deleting without a journal intent; releasing a hold to meet a deadline; marking a step complete; closing the incident because content was sealed; extending an exception automatically.
- **Containment:** the content access guard already denies ordinary access to the overdue content (7I CAG-01). Confirm it (M-254 shows denials).
- **Recovery:** restore the blocked path so erasure or sealing runs; uncertain material follows the 7I decision procedure (HLD-18, HLD-22).
- **Validate:** M-251 zero for the store; M-217 `MISSED` zero; incident dispositioned.
- **Closure evidence:** journal completion records; the disposition that closed the incident. The breach itself stays on record.

### RB-13 — Independent erasure journal unavailable

- **Trigger:** AL-39.
- **Impact:** every erasure, hold release and key destruction waits (7I JRN-20). Deadlines keep running.
- **Authoritative source:** the journal store; step states `INTENT_REQUESTED`, `INTENT_DURABLE`; M-212's nearest deadline.
- **Investigate:** object store reachable? Credential or key valid? Sequence writer fenced or stuck?
- **Permissions:** T3; infrastructure role for the store.
- **Forbidden:** **erasing without a journal record**; writing journal objects by hand; pointing the writer at another store; deleting or overwriting anything under the journal prefix; treating this page as authority to skip the journal.
- **Containment:** fail closed is the containment. Inform the privacy owner of the nearest deadline.
- **Recovery:** restore the store, credential or key; the writer finds its record by nonce and continues (JRN-09).
- **Validate:** appends confirmed; waiting steps draining; checkpoint advancing.
- **Closure evidence:** journal sequence contiguous; a list of any deadlines that passed, each recorded as a breach.

### RB-14 — Restore quarantine cannot establish completeness

- **Trigger:** AL-40.
- **Impact:** a recovered database cannot be put into service; activating it could resurrect erased data.
- **Authoritative source:** the journal chain from the restored `journal_applied_through` to the head; the restore reconciler's report (7I JRN-13, JRN-26).
- **Investigate:** which proof failed: gap, authentication, head mismatch, backup older than coverage, re-application failure, a row contradicting its journal evidence?
- **Permissions:** restore reconciler identity; security and privacy owners.
- **Forbidden:** activating the incarnation; bypassing the incarnation check; editing restored rows by hand; shortening the journal; serving any traffic from the database.
- **Containment:** quarantine is the containment (JRN-16).
- **Recovery:** resolve the specific failure; choose a restore point inside journal coverage; rerun reconciliation.
- **Validate:** the verification assertions of JRN-26 pass.
- **Closure evidence:** the reconciliation report and the activation record with its audit row.

### RB-15 — Subject-index certification fails

- **Trigger:** AL-43b.
- **Impact:** for the affected organization, hold placement with subject scope and data-subject erasure are refused (7I AB-7I-16). Nothing is erased wrongly; work waits.
- **Authoritative source:** the certification and verification records (7I HLD-19, HLD-24); completeness check results.
- **Investigate:** which relation; backfill incomplete, a trigger missing, a key version unreadable or compromised?
- **Permissions:** T3; the certification functions' own authorization.
- **Forbidden:** treating an unverified index as "no match"; forcing a certification state; logging or exporting subject keys to debug; proceeding with erasure for that organization.
- **Containment:** refusals are the containment.
- **Recovery:** complete the backfill or repair, rerun verification, re-certify by the governed procedure; a compromised key version follows 7I HLD-20.
- **Validate:** relation `VERIFIED`; organization certified; refusals stop.
- **Closure evidence:** certification audit rows.

### RB-16 — Unauthorized sealed-content read attempt

- **Trigger:** AL-43a.
- **Impact:** an attempt to read content past its deadline was refused. Assess the actor.
- **Authoritative source:** `SEALED_CONTENT_ACCESS_*` audit rows; guard denial counts; database `42501` on content columns.
- **Investigate:** which path and access code; a normal product path hitting the guard (expected, counted) or a direct attempt on a content column or the vault (not expected)?
- **Permissions:** T3.
- **Forbidden:** inspecting the sealed content to investigate, except through 7I SEAL-08 with its dual control; restoring sealed content to its store; granting a content privilege.
- **Containment:** credential review and rotation for the principal class involved.
- **Recovery:** none for the refused read.
- **Validate:** no further denied attempts of that kind.
- **Closure evidence:** the review; credential changes with their audit rows.

### RB-17 — Monitoring pipeline itself stops reporting

- **Trigger:** AL-50 … AL-58.
- **Impact:** operators are blind for the affected signals. **The event plane is unaffected** (ISO-01). The state of every dependent stage is `UNKNOWN`, not healthy.
- **Authoritative source:** the event plane's own stores, read through the frozen tools; the observer's and collectors' own health.
- **Investigate:** dashboard I if it loads. Start from the "expected versus reporting" panel: the alert names the exact `source`, or the `component` and `group`, or the `shard` that is silent, and the other entries are unaffected by it. Then which part failed: observer credentials, one observer function, a scrape, Prometheus, Alertmanager, a receiver, the Collector, Tempo, the log pipeline, a clock, a cardinality limit? For AL-59: the alert names the `stream` and `fold_kind`. Is that one fold failing, slow, not scheduled, or not exported, while the other streams and the `accounting` source are healthy? A stream with no traffic still commits its fold and stays fresh, so "idle" is never the explanation for a missing fold. Was the observer down longer than a source's guaranteed life (then registration was lost, the cohort hours are unmeasured and the stream says so; obligations with a recovery case are still in M-086 as `UNREGISTERED_CASE`)? For AL-60: which indicator is `UNKNOWN` or `NOT_ESTABLISHED`, and is its finalization watermark stuck on an upstream stream (AOA-20 F3) or on unclassified obligations (F4)? If the page came from the external dead-man (AL-54) and dashboard I does not load, the whole in-region alerting path is down: go straight to containment.
- **Registry states:** an entry that is intentionally silent must be `DISABLED` in the registry with a reason and an expiry, by a reviewed change; it is never silenced by deleting its alert or by removing the entry while the thing still runs. A retired group, component or shard leaves the registry in the same governed change that retires it.
- **Permissions:** SRE; infrastructure role.
- **Forbidden:** declaring a stage healthy because nothing is alerting; back-filling metrics by hand; inserting, editing or deleting obligation records, cohort totals, final rows or corrections by hand; estimating lost observations; finalizing a cohort hour by hand; marking a window established that is not; reporting a figure for an indicator whose state is `UNKNOWN`; pausing event processing or delaying any cleanup until monitoring or accounting returns; widening an observer's privileges to restore a figure; pointing telemetry at a destination outside the governed list.
- **Containment:** for a blind mandatory control (journal, accounting, retention), assign a person to check the authoritative store directly on a fixed interval until evidence is fresh.
- **Recovery:** restore the failed component; rotate an expired credential through the secret manager; drop an offending series in region.
- **Validate:** every `EXPECTED` registry entry has a fresh counterpart (AL-50, AL-51 and AL-09's expected-shard condition all clear); every expected stream's routine and completeness folds are fresh (AL-59 (a) clear for every `stream` and `fold_kind`), every stream's unregistered backlog is back under `T_fold`, each finalization watermark is within its lag and each accounted indicator's window state is as its unmeasured hours dictate; watchdog arriving; a synthetic alert delivered end to end.
- **Closure evidence:** a statement of the blind interval, by source, component or shard, and of any unmeasured accounting interval by stream (M-285), attached to every indicator window it touched (SLI-R-04).

---

## 25. Observability Infrastructure Health

### 25.1 Matrix — Behaviour under telemetry faults

| Fault | Event plane | What becomes UNKNOWN | How it is noticed | Buffer and drop |
|---|---|---|---|---|
| Prometheus unavailable | Continues | Everything alert-driven | AL-54 (dead-man stops arriving) | Process counters keep counting in memory; resolution for the gap is lost; state gauges for the gap are lost |
| Metrics exporter (observer) crashes | Continues | All state metrics | AL-50 per source; AL-51 for the observer | None; next read is fresh |
| A workload's `/metrics` unreachable | Continues | That workload's activity | Scrape `up == 0`; AL-51 | Counters retained until the process restarts |
| OpenTelemetry Collector unavailable | Continues | Traces | Collector self-metrics; M-273 | SDK queue bounded; drops newest; counted |
| Tempo unavailable | Continues | Trace search | Collector export failures | Collector queue bounded; fault-sampled spans shed last (SMP-09) |
| Log sink unavailable | Continues | Log search | Fluent Bit output errors; M-273 | Fluent Bit buffer bounded; then drop; security-class lines are retained preferentially |
| Alert evaluator unavailable | Continues | All alerts | AL-54 | — |
| Alertmanager or a receiver unavailable | Continues | Notification | AL-55; AL-54; NTF-11 | Alertmanager retries |
| Time synchronization fails on a node | Continues; durations are monotonic, ages are database-clock (CLK-01) | Wall-clock log timestamps of that node | AL-56 | — |
| A monitoring credential expires | Continues | The figures that credential reads | AL-50; M-271 cause `AUTH` | — |
| Cardinality exceeds budget | Continues | The over-limit target, as a whole (§9.5) | AL-53 | New combinations go to `other` or are dropped |
| Redis or PostgreSQL unavailable for collection | That is an event-plane incident with its own alerts | The state metrics of that source | AL-50; and AL-09 or the database's own alerts | — |
| A region fails over | Per 7K | The failed region's stack is gone with it; the surviving region has its own complete stack | AL-54 for the failed region | Telemetry history of the failed region is not replicated across regions |
| A replica is stale | Continues | Diagnostic figures read from it | Replica lag exported as the figure's freshness (OBP-08) | — |
| An alert is delayed | Continues | — | Rule evaluation duration and lag on dashboard I | — |
| A healthy workload produces no telemetry | Continues | That workload | AL-51 (heartbeat absent while the workload is scheduled to run) | — |

### 25.2 Rules

| ID | Rule |
|---|---|
| MON-01 [7J] | **Missing telemetry proves nothing.** No absence of a metric, a span, a log line or an alert is evidence that an obligation was processed, that a recovery succeeded, that an erasure completed or that a control held. |
| MON-02 [7J] | **Heartbeats.** Every event-plane loop exports the time of its last iteration (M-272). "Should be running" is known from the deployment's expected components, so a workload that never started is detected as well as one that stopped. |
| MON-03 [7J] | **Absent-signal detection** is explicit: every expected source, component, group and shard is listed in the trusted registry and compared, label by label, with what reports (EVD-08 … EVD-11; AL-50, AL-51, AL-09). **No rule relies on `absent()` of an unqualified metric**, which is false while any one series of that metric exists. A rule that would be silently true on missing data is rewritten against fresh evidence (EVD-04). |
| MON-04 [7J] | **Dead-man path.** An always-firing watchdog alert is sent continuously to an external heartbeat receiver of the class that 3F §20.3 already establishes for external synthetic monitoring. If it stops arriving, that receiver pages. Its payload is content-free. This is the one check that does not depend on Prometheus, Alertmanager or the region's network being healthy. |
| MON-05 [7J] | **Independent verification of mandatory controls.** For the journal, the accounting reconciler, the retention pass and the audit hash chain, the component itself records its last successful run in its own durable store (the checkpoint, the watermark, the pass record, the chain table). Those records exist whether or not telemetry does, and RB-17's containment reads them directly. |
| MON-06 [7J] | **Sampling fallback.** Under Collector pressure, ratio-sampled spans are shed first; fault-sampled spans last (SMP-09). The baseline ratio may be lowered by configuration during an incident; the fault set is not reducible by configuration. |
| MON-07 [7J] | **Collector and worker restart.** A Collector restart loses its in-memory queue. A worker restart loses its unexported spans and resets its counters. Neither affects any durable state, and `rate()` absorbs the counter reset (DUP-01). |
| MON-08 [7J] | **Regional failover.** Each region has a complete, independent stack. No cross-region federation, remote write or trace export exists (§27.4). After a failover the surviving region's dashboards describe the surviving region; the failed region's last known state is not presented as current. Expectations and drills are 7K's (HE-7K-7J-08). |
| MON-09 [7J] | **Telemetry system compromise.** An attacker who controls the telemetry stack can read class R telemetry and can hide or forge alerts. They cannot change event-plane state, because no telemetry principal can (OBP-07). Mitigations: T2 and T3 access is recorded outside the stack's own control (TQA-08); configuration changes are audited and drift is checked (M-282, AL-57); the dead-man path is external (MON-04); mandatory controls keep their own durable run records (MON-05); content never enters telemetry (PRN-07). Residual: RR-7J-01. |
| MON-10 [7J] | **Audit is outside this section.** Nothing here applies to the audit path: an audit write that fails blocks its change (ISO-06). |

---
## 26. Performance and Capacity Constraints

7J states the bounds that the design must respect and the measurements 7K owes. **No figure in this section has been measured.** Every number is [CAND].

| ID | Concern | Constraint | Candidate | To 7K |
|---|---|---|---|---|
| PRF-01 | Live audio path | No instrumentation added by 7J executes in the raw-WebSocket audio loop; no network call, lock or allocation proportional to load is added to the turn loop (ISO-02; 7D CLD-05; NFR-PERF-001) | Zero added synchronous I/O (a design rule, verified by VT-7J-48) | HE-7K-7J-02 |
| PRF-02 | Instrumentation overhead on event-plane hops | Bounded CPU per event for counters, histogram observations and span creation | At most 2% of per-event CPU at the 25% ratio | HE-7K-7J-02 |
| PRF-03 | Metric series | §9.4 | 60,000 regional budget | HE-7K-7J-01 |
| PRF-04 | Span volume | Spans per event at the baseline ratio, plus the fault set; hop-local buffer size | About 6 to 10 spans per sampled event across the pipeline; buffer per attempt bounded | HE-7K-7J-05 |
| PRF-05 | Log volume | Token bucket per workload (LOG-16); state-change logging (LOG-11) | One line per state change, not per entry | HE-7K-7J-06 |
| PRF-06 | Retention storage | Raw metrics 30 days; SLO aggregates 13 months; traces 14 days; logs per 3F §18.3; alert history 13 months | — | HE-7K-7J-09 |
| PRF-07 | Prometheus scrape cost | Scrape interval 15 s (3E §14.5); per-target sample limit | 15 s | HE-7K-7J-01 |
| PRF-08 | Database polling cost | Observer functions: statement timeout; index-supported predicates only; no sequential scan of a content table; ages and counts from partial indexes that the governed migration provides; read cadence at or above the scrape interval with the read's age exported | Each function under 100 ms at the primary | HE-7K-7J-04 |
| PRF-09 | Expensive forensic queries | Not available on dashboards. A T2 or T3 query is bounded in time range and scope (TQA-03) and runs against the telemetry stores, never against the event plane's primary database. Authoritative-table investigation uses the frozen tools and the read replica where the question allows | Time range at most 7 days per grant | HE-7K-7J-04 |
| PRF-10 | Redis diagnostics overhead | RDO-06. No scan of a stream or a PEL; `MEMORY USAGE` sampled | 12 `XINFO GROUPS` and 38 `XPENDING` per poll in V1 | HE-7K-7J-04 |
| PRF-11 | Exporter connections | The observer holds a small fixed pool to PostgreSQL and one connection per shard to Redis; it never draws from a workload's pool | Fixed, single digits | HE-7K-7J-04 |
| PRF-12 | Alert evaluation | Rule groups evaluate inside their interval; evaluation lag is on dashboard I | Interval 15 s to 1 m by class | HE-7K-7J-03 |
| PRF-13 | Tenant fairness | Telemetry cost is per event, not per tenant label, so one tenant's volume cannot multiply series. One tenant's burst can raise span and log volume; the bounded queues and the token bucket drop excess without affecting other tenants' processing (ISO-04). Dropped telemetry is not attributable per tenant in metrics, by design | — | HE-7K-7J-06 |
| PRF-14 | Catch-up after an outage | Telemetry volume scales with the catch-up rate; thresholds during catch-up are separate `T_*` values (STM-04) | — | HE-7K-7J-07 |
| PRF-15 | Subject-index and erasure observability | Index and retention reads are counts from maintained state, never a scan of content tables or of the index per scrape | — | HE-7K-7J-10 |
| PRF-16 | Observation accounting (§6.4) | The fold reads committed rows without row locks, never blocks a relay, consumer, dispatcher or cleanup, and is bounded per call; one obligation record per obligation for the life of AOA-23; hourly cohort rows per (stream, dimension tuple); window read functions sum at most 672 hourly rows per scope | Routine fold every scrape interval at most; completeness fold daily; lookback 1 hour; hourly cohort rows kept 45 days | HE-7K-7J-14 |

---

## 27. Data Residency and Retention

### 27.1 Matrix — Retention and access classes

| Data | Retention | Authority | Store | Access | Identifiers held |
|---|---|---|---|---|---|
| Raw metrics | 30 days | OD-7J-03 | Prometheus, in region | T0 | None, by the label allow-list |
| SLO aggregates | 13 months | OD-7J-03 | SLO-history Prometheus, in region | T0 | None |
| Traces | 14 days | OD-7J-03 | Tempo, in region | T2 | Class R references (pseudonymous, linkable) |
| Application logs | 30 days hot; 90 days cold | 3F §18.3 [FROZEN] | Log service and cold storage, in region | T1 (views without class R); T2 | Class R references |
| Security-monitoring records, hot | 90 days | 3F §18.3 [FROZEN] | Security log group, in region | T3 | Class R references; operator reference (class S) |
| Security-monitoring records, cold | 2 years | 3F §18.3 [FROZEN]; content limited by OD-7J-08 | Cold storage, in region | T3 | **None** (RET-7J-06) |
| Infrastructure logs | 14 days hot; 30 days cold | 3F §18.3 [FROZEN] | In region | SRE | None from the event plane |
| Alert history | 13 months | OD-7J-03 | Alertmanager history, in region | T0 | None |
| Incident records | 2 years | OD-7J-03 | Incident tracker, in region | SRE; security | **None** of event, delivery, call or correlation level (RET-7J-08) |
| Preserved evidence | Life of its authorizing hold or preservation order (§27.6) | OD-7J-09 | Dedicated prefix of the approved in-region object storage | Named, purpose-bound, case-specific (EVP-11) | As captured, scoped |
| Immutable audit evidence | 5J §20 | [FROZEN] | `audit.audit_events`; cold archive in region (7I RSY-10) | 6L, 6M | Per 7I RED-10 |

Telemetry retention is set by its own purpose. It is not derived from business-event, recording, outbox, replay-material or audit retention, and none of those is changed by this document.

### 27.2 SLO aggregate history (OD-7J-03)

| ID | Rule |
|---|---|
| RET-7J-01 [OD-7J-03, conditions 1, 2] | **Mechanism.** A second Prometheus instance in the same region and namespace class, logically separate, with its own storage and its own 13-month retention. It federates only series whose name begins `slo:` (the recording rules of §10 and §11). It scrapes nothing else. This is the same product already approved by 3E and 3F; no vendor or destination is added. |
| RET-7J-02 [conditions 2, 3; OD-7J-08 condition 14] | **Content.** An `slo:` series, and every window or cohort series the history store keeps (M-290, M-291, M-294, M-295), may carry only `region_class`, `family`, `group`, `topic`, `provider`, `store`, `closure_class`, `indicator`, `scope`, `part`, `state`, and an indicator name. It never carries `event_type`, `plugin_key`, a cohort hour, an identifier or any label outside that list. A rule that would produce another label fails the build check of LBL-07. An SLO aggregate therefore cannot be joined to a customer: it has no dimension finer than a group, a family or a topic (VT-7J-55). |
| RET-7J-03 [condition 9] | **History of accounted indicators comes from the database, not from raw series.** The history store samples the window Gauges (M-290, M-291, M-295) and the latest-final-cohort Gauges (M-294) at every evaluation; each final cohort hour is exported for at least one hour, so it is sampled before the next one replaces it. The 30-day raw retention is therefore not an input to any accounted window: the 28-day figure is computed in PostgreSQL from final cohort rows, which are kept [CAND] 45 days (AOA-23). A post-final correction (AOA-22) changes the window Gauge from then on and is itself recorded (M-293); **a sample already written to the history store is never rewritten**, so a past window that was later corrected is identified by the correction counter moving for its hours and is restated in the next report, not edited in place. For state and activity indicators, the `slo:` recording rules are evaluated on raw series and federated within one scrape; a daily job recomputes each for the day that is [CAND] 7 days old and reports gaps (M-281, AL-58). A gap found after the raw data expired is an unmeasured interval (SLI-R-04), never interpolated. |
| RET-7J-04 [condition 8] | **Expiry and its verification.** Each store expires by its own time-based retention. A weekly verification asserts, per store, that no sample, span or log object older than its limit plus one compaction period is readable, and records the result as a platform audit event (proposed kind `TELEMETRY_RETENTION_VERIFIED`, with counts and no content). A failed verification is AL-57. |
| RET-7J-05 [condition 8; OD-7J-08 condition 11] | **Backups, replicas and restore.** Prometheus, Tempo and the log service are not backed up beyond their own retention; where a store's durability mechanism keeps replicas or snapshots, those share the store's retention and expire with it. Restoring a telemetry store from a snapshot is followed by the store's retention pass **before** it is opened to queries, so expired data is not served; the snapshot's age is recorded with the restore. A telemetry store is never restored to recover event state, because it holds none. No telemetry is replicated to another region. |

### 27.3 Minimization and the 90-day limit (OD-7J-08)

| ID | Rule |
|---|---|
| RET-7J-06 [OD-7J-08, conditions 5, 7] | **The cold security record is a projection written at the node.** 3F §18.1 writes the cold copy in parallel with the hot copy. For the security class, the cold output receives only: a timestamp truncated to the minute; `service`, `component`, `region_class`; the security signal code; the outcome and failure codes; `principal_class`; counts. It receives **no** `event_id`, `correlation_id`, `causation_id`, delivery, endpoint, receipt, case or operation reference, no `trace_id`, no `transport_ref`, **no `organization_id` and no operator reference**. The projection is applied when the line is written, so the cold tier never held those fields and nothing has to be removed later. The approval text lists what a cold record may keep; 7J applies it strictly, which is narrower than the option first offered (that option kept organization and operator references). Accountability for an operator's action is the immutable audit row, with 5J's retention, and is unaffected. |
| RET-7J-07 [condition 5] | The application-class cold copy (90 days) keeps class R fields, because its total life is inside the 90-day limit. It receives the same projection as RET-7J-06 if 3F's cold period for that class is ever lengthened. |
| RET-7J-08 [condition 5] | **Incident records** (2 years) contain a timeline, alert IDs, closed codes, counts, decisions and the references of audit rows and of preserved-evidence records. They contain no event, delivery, call or correlation identifier and no organization identifier in free text; the incident tool's template has no field for them. Where an identifier must be kept, it is kept as preserved evidence (§27.6) and the incident record cites the evidence reference. |
| RET-7J-09 [condition 6] | **Maximum ordinary lifetime of a subject-linkable reference in telemetry: 90 days** (the security hot tier and the application cold tier). Traces hold them 14 days. This is an upper limit on ordinary telemetry. It does not delay, and is not a substitute for, any earlier erasure that 7I or the owning contexts require of their own stores. |
| RET-7J-10 [condition 8] | **A UUID is not anonymous.** `event_id`, a delivery ID, and a `correlation_id` that equals a `call_id` (7C COR-V) are pseudonymous references that identify a person for as long as any retained system maps them to that person. This document classifies them as linkable (class R) and never describes them as anonymous or as non-personal. |
| RET-7J-11 [condition 16] | **No subject lookup is built for observability.** Telemetry is never indexed by contact, phone, email or any subject key, and no tool resolves a subject to "all its events" for monitoring. A T2 search takes an organization or one entity identifier (TQA-03); it does not take a subject. |
| RET-7J-12 [condition 10] | **Automated, idempotent, auditable, recoverable.** Expiry is the stores' own time-based retention; the cold projection is a stateless transform at write time; neither keeps progress state that a crash could corrupt, and re-running either changes nothing. Verification is RET-7J-04. A node that restarts resumes the projection with the next line; a line is never written to the cold security tier unprojected, because the projecting filter is the only path to that output and its failure drops the line and counts it (M-273) instead of passing it through. |
| RET-7J-13 [conditions 12, 13] | Nothing here erases, shortens or touches immutable audit, recovery material, durable obligations, the erasure journal or a 7I hold. An authoritative record is never deleted because its identifier appears in an expiring telemetry record. |
| RET-7J-14 [7J] | **Obligation records and cohort totals are not telemetry.** They live in PostgreSQL, in region with the database, with no privilege for any login role. An obligation record holds an obligation identifier (class `PID`), its origin time and closed codes, and no content; it lives while the obligation is open and, once closed, no longer than the frozen records of the same identity (AOA-23). It is never exported, logged or queryable through any telemetry tier. Cohort totals, final rows and corrections hold counts by bounded dimension and no identifier. What Prometheus receives from them is counts. |

### 27.4 Residency

| ID | Rule |
|---|---|
| RSD-7J-01 [FROZEN] | Logs, traces and metrics are in region; `LOGS` is a residency scope item (4I §9.1; 7I RSY-11). |
| RSD-7J-02 [7J] | **One complete telemetry stack per region.** Collectors, Prometheus (both instances), Tempo, the log groups, cold storage, Alertmanager, Grafana, the broker and the evidence prefix are all in the region of the event plane they observe. Each telemetry workload carries the region tag and refuses to start if its tag differs from its targets' (the 7I RSY-02 pattern). |
| RSD-7J-03 [7J] | **No cross-region path:** no remote write, no federation across regions, no trace or log forwarding, no global dashboard that queries another region's stores, no cross-region replica of a telemetry store. A cross-region view, if ever wanted, is a new owner decision. |
| RSD-7J-04 [7J] | **Export destinations are a governed closed list** per stack: the in-region stores, and the notification receivers of §23.6 with their minimal payload. Any other exporter, sink, remote endpoint or vendor agent is a configuration the build rejects and the drift check alerts on (M-282, AL-57). An `INDIA_ENTERPRISE` tenant's residency cannot be bypassed by sending telemetry to a foreign service, because no such destination can be configured without failing both checks and without the owner's approval. |
| RSD-7J-05 [7J] | Telemetry is not treated as harmless because it has no payload. Class R references and operational metadata are sensitive, are access-controlled (§22) and are in region. |
| RSD-7J-06 [7L] | Operator access to in-region telemetry from a workstation outside the region follows the position 7I records for tooling access (RSY-09; HE-7L-7I-06): what reaches the workstation is the rendered result of a case-bound query. Whether that is a transfer is the same contract question and is handed to 7L with it (HE-7L-7J-06). |

### 27.5 Data-subject erasure and telemetry (OD-7J-08)

| ID | Rule |
|---|---|
| DSE-01 [OD-7J-08, conditions 1, 2] | Telemetry holds no direct identifier and no content (§13.2, TRC-10). What it can hold about a person is a pseudonymous reference to something of theirs: an event, a delivery, a call used as a correlation root. |
| DSE-02 [conditions 8, 9] | **Linkability, evaluated.** Such a reference identifies a person only through a retained mapping from that resource to the person. The mappings are in the owning contexts (for example call session to contact) and nowhere in telemetry. When the owning context's erasure removes or irreversibly anonymizes that mapping, the telemetry reference no longer leads to the person. |
| DSE-03 [condition 9] | **Two retained mappings exist outside the owning contexts and are stated.** (a) The erasure journal holds, per erasure record, the set of resource references, encrypted, readable only by the restore reconciler identity (7I JRN-03, JRN-04, JRN-18). (b) Audit rows of the request and of `CONTACT_ERASED` hold the identifiers 5J and 7I define. Neither is reachable by any telemetry role (TQA-07), and telemetry holds no subject key to join on. Within the 90 days a party holding both the journal's decrypt permission and T2 access could relate a journal resource reference to telemetry lines. That combination is two separately granted, separately audited authorities; it is recorded as RR-7J-05, not described as impossible. |
| DSE-04 [condition 9] | **What the owning contexts owe.** Each owning context's erasure function (5C – 5G; 7I HLD-14, HE-7L-7I-11) must sever or irreversibly anonymize the mapping from its resources to the erased subject. 7J cannot verify this, because those functions are not designed yet. It is a named dependency (IR-7J-38) and a gate (AG-7J-10). |
| DSE-05 [conditions 9, 18] | **If a context cannot sever a mapping** while reporting the subject erased, telemetry references to that context's resources stay linkable for up to 90 days. That would be a weaker privacy guarantee than the owner approved. It is not accepted here: it must be brought to the owner as a decision before that context's erasure is reported complete (AG-7J-10). No such case is known today; none can be ruled out until HE-7L-7I-11 is done. |
| DSE-06 [condition 9] | **Per-subject telemetry deletion is not adopted, and its requirement is named.** Should DSE-05 arise, the alternative is an accelerated purge: given the resource identifiers of one erasure step, delete matching lines and spans from the hot tiers, as a journaled step. It would need: deletion by identifier in Tempo and in the log service (provider-dependent and unverified); a registered erasure step in the 7I journal design; a resource-identifier list handed to a telemetry component, which is itself a new exposure. It is recorded as IR-7J-39, **not designed and not approved**, so that it cannot be mistaken for existing. |
| DSE-07 [condition 6] | An erasure report for a subject states telemetry accurately: "no content and no direct identifier; pseudonymous references to the subject's erased resources may persist in restricted telemetry for at most 90 days and are not resolvable to the subject once the owning context's mapping is erased". It does not say telemetry was erased. |
| DSE-08 [condition 17] | All of the above is identical for every residency profile, and all stores are in region (§27.4). |

### 27.6 Evidence preservation outside ordinary telemetry (OD-7J-09)

| ID | Rule |
|---|---|
| EVP-01 [OD-7J-09, condition 1] | **Ordinary telemetry always expires on schedule.** No legal hold, incident or investigation extends the retention of Prometheus, Tempo or a log group, for any organization or for the region. |
| EVP-02 [conditions 2, 15] | **Trigger.** A scoped evidence capture is requested when (a) a `PLATFORM` hold of 7I (HLD-02, HLD-23) is placed and its matter needs operational evidence, or (b) an incident-preservation order is recorded for a security or privacy incident. A capture never creates, changes or releases a 7I registry hold; 7I's `REQUEST` and `PLATFORM` semantics are unchanged. |
| EVP-03 [conditions 7, 10] | **Authorization.** A capture needs a request by one named person holding `retention.hold.manage` (for a hold) or the security owner's incident authority (for an order), and an approval by a different named person, each with an operator action proof (the 7I pattern). The approval is recorded by an audit row **before** the capture runs. |
| EVP-04 [conditions 3, 8, 9] | **Scope.** The capture names one organization, or a set of entity identifiers, a component set and a time range. The broker executes exactly that scope under a grant of purpose `EVIDENCE_PRESERVATION`. A capture never copies a whole regional log group or trace dataset, and never returns another organization's lines: every captured record is checked for the scoped organization or identifier, and a record that does not match is excluded and counted. |
| EVP-05 [condition 4] | **What is captured.** The original scoped log records and spans as stored (which by construction hold no payload), not a summary; with a manifest: the source store, the query, the time range, the count of records, a digest of each object and of the whole set, the capture time, the capturing principal, the authorization reference, and a statement of which part of the requested range had already expired when the capture ran. Category codes alone are not assumed to be sufficient. |
| EVP-06 [conditions 5, 6, 18, 20] | **Where it lives.** A dedicated prefix of the already approved in-region object storage, with its own credentials, its own encryption key (a new key purpose, `PRESERVED_EVIDENCE`, in the 7I hierarchy; ERR-7J-13), write-once objects, and no lifecycle expiry of its own. It is not an index of the telemetry system and is not queryable through T0 – T3. No new storage product, vendor or API is introduced. |
| EVP-07 [condition 10] | **Durable record.** One audit row per capture (proposed kinds `TELEMETRY_EVIDENCE_PRESERVED`, `_PRESERVATION_FAILED`): authorization, source, capture time, scope type, integrity digest, responsible principal, evidence reference. The row holds no captured content. |
| EVP-08 [condition 12] | **Before the source expires.** A capture must complete before the earliest expiry of any in-scope source; for traces that is at most 14 days after the data was written. The capture is started when the hold or order is recorded, not later. Its deadline is computed and shown. Because EVP-01 forbids freezing expiry, this is a deadline and not a lock: data already older than its retention when the obligation became known is gone, and the manifest says so (EVP-05). |
| EVP-09 [condition 13; OD-7J-10] | **Failure is explicit, and it is not compliance.** A capture that fails, or that cannot durably verify its digests, is recorded as `_PRESERVATION_FAILED`, raises a SEV1 alert at once with the time remaining to the source's expiry, and is escalated to the security owner, the privacy owner and legal counsel for the matter. It is retried. The fail-safe is a **secondary capture path with its own authorization**: an infrastructure-role export of the same scope directly from the store into the evidence prefix, requested and approved separately (two named people, recorded before it runs), so that a fault or a compromise of the primary path's authorization does not carry over. If the source expires before any capture succeeds, the record states exactly what was and was not preserved. **It is never reported as preserved, and recording the failure does not satisfy the preservation obligation**: the matter's owners are told the evidence does not exist. Expiry is not suspended, for the scoped organization or for anyone else, to avoid the loss. This residual is RR-7J-06, accepted by the owner in OD-7J-10. |
| EVP-10 [condition 14] | An alert, a dashboard, an ordinary log line or an incident note is never evidence of preservation. Only the audit row and the verified objects are. |
| EVP-11 [conditions 7, 11] | **Inspection.** Reading preserved evidence needs a named person, a purpose, the case reference and an approval by a second person, recorded before release (proposed kind `TELEMETRY_EVIDENCE_ACCESSED`). T2 and T3 roles do not reach the evidence prefix: its credentials are held by the evidence function alone. Customer material and sealed content remain under 7I §13.5 and SEAL-08 and are never part of a telemetry evidence set. |
| EVP-12 [condition 16] | **Independence from the tenant's request.** Evidence under a `PLATFORM` hold or an incident order is released only by the release of that hold or order, under its own dual control. A tenant rejecting or withdrawing a data-subject request releases nothing here. |
| EVP-13 [condition 17] | **Expiry.** When the authorizing hold or order is released, the evidence set is deleted at the next retention pass unless another recorded hold or order names it; the deletion verifies absence and is audited (`TELEMETRY_EVIDENCE_EXPIRED`). There is no grace period and no default extension. An evidence set never outlives every obligation that named it. |
| EVP-14 [condition 6] | **Erasure.** A data-subject erasure does not delete evidence that a `PLATFORM` hold preserves; the hold pauses it, as 7I HLD-07 states for its own stores. When the hold ends, EVP-13 applies. |
| EVP-15 [condition 19] | Compatibility: the new audit kinds extend the 5J §14.3 vocabulary as 7I ERR-7I-06 does (ERR-7J-10); the key purpose is ERR-7J-13. No frozen audit or evidence-retention rule is changed. |
| EVP-16 [7J] | **Nothing in this section exists.** The evidence function is a requirement on the event-operations tooling (IR-7J-40) and is gated (AG-7J-11): until it exists, a `PLATFORM` hold cannot rely on telemetry evidence being preserved, and that fact must be stated to whoever places the hold. |
| EVP-17 [OD-7J-10] | **Conditions of OD-7J-10, each met by a rule.** Prompt capture when preservation becomes required: EVP-08. Independently authorized secondary capture: EVP-09. Durable integrity verification: EVP-05, EVP-09 (digests of each object and of the set, verified before `_PRESERVED` is recorded). SEV1 notification when a critical preservation fails: EVP-09. Legal and privacy escalation: EVP-09. Explicit record of what was and was not preserved: EVP-05, EVP-09. No claim that recording a failure satisfies a legal preservation obligation: EVP-09, EVP-10. No extension of unrelated tenants' general telemetry retention: EVP-01, EVP-04, EVP-09. The owner's acceptance of RR-7J-06 stands. |

---

## 28. Failure-Injection and Validation Matrix

### 28.1 Matrix — Failure and adversarial scenarios

"State" is the monitoring result in the vocabulary of PRN-03.

| ID | Scenario | Authoritative state | Expected signal | State | Alert | Investigation | Safe response | Residual risk | Test |
|---|---|---|---|---|---|---|---|---|---|
| FS-01 | Outbox claim without publish (relay dies after claiming) | Rows `CLAIMED`; lease expires; rows eligible again (7D LSE) | M-002 rises until reclaim; M-004 counts the reclaim; relay heartbeat gap | DELAYED | AL-01 if sustained; AL-51 | RB-01 | None; reclaim is automatic | One extra `attempt_count` per row | VT-7J-01 |
| FS-02 | Redis append without PostgreSQL mark-published | Entry exists; row not `PUBLISHED`; row republished later (7I ACC-18 a) | M-005 `CONFIRMED` twice for one row; M-012 or M-004; M-063 `ALREADY_COMMITTED` downstream | HEALTHY (duplicate, by design) | None | RB-01 if frequent | None | A duplicate delivery; guards absorb it | VT-7J-02 |
| FS-03 | Duplicate Redis publication (lease expiry, two relays) | Two positions recorded; one row `PUBLISHED` | M-012 CAS miss; duplicate handler outcome | HEALTHY | AL-06 on rate | RB-01 | Review lease and safety margin | None for correctness | VT-7J-02 |
| FS-04 | Worker commit succeeds, `XACK` fails | Effect and completion committed; entry pending | M-063 commit; M-067 `ERROR` or `TIMEOUT`; M-043 holds the entry; later `ALREADY_COMMITTED` | DELAYED | AL-11 if sustained | RB-04 | None; redelivery acknowledges | None | VT-7J-07 |
| FS-05 | Redis cursor advanced without valid completion evidence | No accounting row; position `GONE` | M-205 `GONE`; M-203 `OBLIGATION_UNACCOUNTED`; at latest at `T_obl` (ACC-17) | FAILED | AL-18 (SEV1) | RB-05 | R2 from the captured outbox row | Detection latency up to `T_obl` plus one reconciler period | VT-7J-46 |
| FS-06 | Group removed before its obligations are retired | Registration open; group absent | M-048 > 0; trim paused; pairs classify `GONE` | FAILED | AL-12 (SEV1); AL-18 | RB-03, RB-05 | Governed provisioning; R2 for unaccounted pairs | — | VT-7J-36 |
| FS-07 | Handler deployment missing an active contract generation | Admission refuses; entries held | M-072, M-073; M-062 holds; heartbeat absent after exit | HELD | AL-16 | RB-03 | Deploy compatible code | Hold bounded at 24 h, then parked (7G IMP-03) | VT-7J-36 |
| FS-08 | Recovery case without a replay source | Case exists; no permitted source | M-107 `SOURCE_MISSING` | FAILED | AL-22 | RB-07 | Owner reconciliation | The obligation may be closable only by the owner | VT-7J-37 |
| FS-09 | Inbound callback accepted, processing worker lost | Receipt `RECEIVED` or `PROCESSING` with stored input | M-155 rises; M-154 re-dispatch | DELAYED | AL-29 | RB-10 | Sweep re-dispatches | None | VT-7J-37 |
| FS-10 | Webhook attempt with an ambiguous outcome | Either the worker observed a timeout or reset after hand-off: closure `SENT`, category `TIMEOUT` or `CONNECTION_RESET`. Or the worker died after an admission: the sweep's closure, `CLAIM_EXPIRED`, send state **`UNCERTAIN`** (7H T-08) | M-128 with the recorded `send_state`; M-137 `UNCERTAIN`; M-144 class `UNCERTAIN`; retry scheduled | DELAYED | AL-24 on a rate of `UNCERTAIN` | RB-08 | None; receiver must deduplicate (7H HTP-13) | Receiver may see the event twice; for `UNCERTAIN` nobody knows whether it was sent | VT-7J-09, VT-7J-79 |
| FS-11 | Secret rotation during a delivery | Admission bound to one revision; re-check finds a change | M-135 mismatch, re-admission; M-133 `DUAL_SIGNATURE` | HEALTHY | None; AL-26 only for PREVIOUS unavailable | RB-09 | None | — | VT-7J-09 |
| FS-12 | Unauthorized replay attempt | Refused; audit row `FAILURE` | M-170 after the audit commit | HEALTHY (control held) | AL-31 | RB-11 | Review the actor | A legitimate credential misused within its capability is not refused | VT-7J-28 |
| FS-13 | Tenant context leakage through connection pooling | Connection carries a tenant setting at checkout | M-182; connection discarded | FAILED (attempt) | AL-30 (SEV1) | RB-11 | Recycle pool; find the path that left the setting | If the hook is absent the leak is invisible to telemetry; RLS and the context sequence remain the control | VT-7J-28 |
| FS-14 | Key-service outage during recovery | Parking cannot store material; entry stays pending | M-185; M-099 `KEY_SERVICE_UNAVAILABLE`; M-095 gate | HELD | AL-37; AL-22 inhibited | RB-07 | Restore the key service | Entries pin the stream meanwhile | VT-7J-10 |
| FS-15 | Erasure journal unavailable | Steps wait at `INTENT_REQUESTED` | M-210; M-212 with nearest deadline | HELD | AL-39 (SEV1) | RB-13 | Restore the journal | A deadline can pass during the outage; then AL-41 | VT-7J-39 |
| FS-16 | Restore to an older database snapshot | Incarnation changes; quarantine | M-216 `QUARANTINED`; M-218 from surviving workers | HELD | AL-40 | RB-14 | Reconcile before activation | RR-07 of 7I (journal durability) | VT-7J-39 |
| FS-17 | Sealed-content access while the sealing worker is down | Content past deadline still in its store, denied by the guard | M-254 denials; M-251, M-252 rise; M-262 stale | HELD (denied) and DELAYED (disposition) | AL-41; AL-43a if an attempt bypasses a guarded path | RB-12, RB-16 | Restore the pass | The guard, not the alert, protects the content (PRV-05) | VT-7J-18 |
| FS-18 | Platform legal hold not matched by a resource reference | Row is uncertain; skipped; decision record opened | M-234; M-237; at the limit M-240 | HELD, then FAILED (incident) | AL-42 | RB-12 | 7I decision procedure | RR-10 of 7I | VT-7J-39 |
| FS-19 | Legacy identity-index incompleteness | Organization `FROM_T0` or `NOT_CERTIFIED` | M-259; M-237 `LEGACY_HISTORY_UNKNOWN`; M-232 refusals | HELD | AL-43b on demotion or failure | RB-15 | Governed certification | RR-11 of 7I | VT-7J-39 |
| FS-20 | Monitoring backend unavailable | Event plane unaffected | Dead-man stops arriving | UNKNOWN | AL-54 | RB-17 | Direct checks of mandatory controls (MON-05) | Blind interval | VT-7J-40 |
| FS-21 | Metrics report zero while the authoritative backlog grows | Observer read failing or stale, for one source or all | The source's series absent, not zero (EVD-02); its expected-registry series has no fresh counterpart | UNKNOWN | AL-50 with that `source` (SEV1 for `outbox`), while other sources stay healthy | RB-17 | Restore the observer | None if EVD-02 and EVD-09 hold; the tests prove them | VT-7J-06, VT-7J-67 |
| FS-22 | Alert storm during a prolonged Redis outage | Gate open; outbox growing | One cause alert; symptoms inhibited | HELD | AL-09 or AL-08 only | RB-02 | Per runbook | Integrity alerts stay live by design | VT-7J-41 |
| FS-23 | Malicious or accidental unbounded label emission | Registry refuses the value | M-275; value to `other` or dropped | HEALTHY (guard held) | AL-53 | RB-17 | Fix the registration | A bounded label set can still be large; budget in §9.4 | VT-7J-14 |
| FS-24 | Cross-region telemetry export policy violation | Exporter destination outside the governed list | Build check fails; at run time the drift check | FAILED | AL-57 (SEV1) | RB-17 | Restore configuration; assess exposure | Exposure between the change and its detection | VT-7J-50 |
| FS-25 | Two observer replicas read the same published row | One outbox row `PUBLISHED`; one obligation record, closed once; its cohort hour incremented once | M-017 `_count` +1 on both replicas, identical; `max without (instance)` = +1 | HEALTHY | None | — | None | None | VT-7J-63 |
| FS-26 | Observer down longer than a source's guaranteed life | Source rows deleted unregistered; obligations with a recovery case still exist in the ledger | On the first fold after the outage: one `REGISTRATION_GAP` declaration proved from the run records; M-285 unmeasured seconds and cohort hours; those hours finalized `UNMEASURED` in order, the watermark advancing across them; M-086 `UNREGISTERED_CASE` for every such case; the windows that contain those hours `ESTABLISHED_PARTIAL` or, above 13 hours or with an unattributed obligation, `NOT_ESTABLISHED` | UNKNOWN while the watermark is old; then unmeasured for those hours; the unresolved cases still counted | AL-59 (SEV1 inside the margin; SEV2 after); AL-60; AL-15 for unregistered cases | RB-17 | Restore the observer; nothing is back-filled | The latency of unregistered obligations is unrecoverable; their existence, where a case exists, is not | VT-7J-65, VT-7J-85, VT-7J-95 |
| FS-27 | One evidence source, one component or one shard goes silent while the rest report | The silent one's state is unknown; the others are known | Expected-registry series with no fresh counterpart, for that label only | UNKNOWN for that one | AL-50 / AL-51 / AL-09, labelled | RB-17 | Per runbook | A registry that omits an entry cannot alert on it; unregistered reporters are shown | VT-7J-67, VT-7J-68 |
| FS-28 | One Redis shard fails durability while others carry most traffic | Entries routed to that shard are `UNKNOWN`; rows stay unpublished | M-035 for that `shard` all unconfirmed; regional ratio high | FAILED for that shard | AL-08 (b), SEV1, `shard` label | RB-02 | Per runbook | None | VT-7J-69 |
| FS-29 | Organization not active at admission (7H T-09) | Claim released; `attempt_count` unchanged; closure with `attempt_number` NULL | M-161 +1; M-164 +1; M-128 unchanged; M-144 `UNCOUNTED_RELEASE` +1; M-126 holds the row | HELD | None | RB-08 | None | None | VT-7J-80 |
| FS-30 | Outbox row deleted under 7I ACC-06 while a recovery case is still open | Obligation record (group, event) open, with `origin_at`; case `PARKED` | M-086 `PARKED` unchanged by the deletion; the pair stays valid and not good in its cohort | FAILED (obligation unresolved) | AL-20 | RB-06 | R2 or owner reconciliation | None for the measurement | VT-7J-83 |
| FS-31 | A fold commits observations long after their events (observer lag; batch spanning several days) | Each obligation attributed to the cohort hour of its origin time | Cohort hours not final until complete; finalization watermark ages; window state `UNKNOWN` if the lag passes its limit | DELAYED measurement, then correct | AL-60 | RB-17 | None | Fold-time histograms show the catch-up as a burst; no reported figure reads them | VT-7J-87 |
| FS-32 | An origin arrives for an already final cohort hour (late-visible commit; a producer-assigned past `occurred_at`) | Final row unchanged; correction counters for that hour incremented | M-293; window Gauge includes the correction | HEALTHY, restated | AL-60 on volume | RB-17 | None | A window already reported is restated in the next report | VT-7J-89 |
| FS-33 | One accounting stream's fold stops while every other stream and the `accounting` source report | That stream's obligations are no longer registered or closed | Expected-stream series with no fresh counterpart for that `stream` and `fold_kind` only; that stream's indicators `UNKNOWN` | UNKNOWN for that stream's indicators | AL-59 (a), labelled; AL-60 | RB-17 | Restore the fold | Registration loss if it lasts past the source's guaranteed life | VT-7J-90, VT-7J-91 |
| FS-34 | Database restored to an earlier point and activated later | Observations of the lost timeline are gone; the accounting relations return to the restore point with everything else | The fold refuses until activation (7I JRN-12); its first run under the new incarnation appends a `RESTORE_GAP` declaration; those hours are finalized `UNMEASURED`; the window keeps 672 consecutive hours and counts them in `unmeasured_hours` | UNKNOWN until the watermark is back inside its lag; then `ESTABLISHED_PARTIAL` or `NOT_ESTABLISHED` until the hours leave the window | AL-40; AL-59 (c); AL-60 | RB-14; RB-17 | None for the lost hours; they roll out of the window after 28 days | No verdict and no budget movement for any window that contains them (RR-7J-13) | VT-7J-88, VT-7J-93, VT-7J-99 |
| FS-35 | A lifecycle transaction starts before a delivery's deadline, takes the organization lock and commits after it (or after the fold's evaluation) | Its audit row is dated before the deadline although the status changed after it | The audit row is not read. The transition's `locked_at` is after the deadline, or the transition is not visible at the evaluation and therefore took effect after it: the delivery is settled `active_throughout`, valid and not good, and is not revised when the transaction commits. No correction entry; the final row unchanged | DELAYED, counted as the platform miss it is | None beyond AL-23 | RB-08 | None needed | None: this is the case the transaction-start timestamp would have got wrong | VT-7J-122, VT-7J-125 |
| FS-37 | Two lifecycle transactions of one organization overlap: the one that began first waits for the row lock and commits second | Their audit timestamps are in the reverse of the order in which the changes took effect | Transition sequence and `locked_at` are in commit order; the earlier-committed transition's band ends at the later one's `locked_at`, where the status is certain | As the evidence proves; `uncertain` only for a window that meets a band and no certain instant | AL-60 on the uncertain share only | RB-17 | None needed | Band width follows fold lag and lifecycle-transaction length (RR-7J-12) | VT-7J-124, VT-7J-126 |
| FS-38 | Lifecycle evidence is missing, gapped or contradicts the organization row; or the listing function fails | Eligibility cannot be proved for the affected organization | Records settled `uncertain`, basis `EVIDENCE_FAULT` or `EVIDENCE_UNAVAILABLE`; the window `NOT_ESTABLISHED`; a failing listing makes the fold stale | UNKNOWN for eligibility; no SLI-11 verdict | 7I STP-11 integrity alarm; AL-60; AL-59 (a) if the fold fails | RB-17 | Restore the evidence path; nothing is back-filled and no class is guessed | Those deliveries stay `uncertain` | VT-7J-132 |
| FS-39 | The fold is delayed between acquiring a snapshot and a later clock read, and a suspension commits in between | A classifier that took the later clock value as its cutoff would certify `ACTIVE` on a snapshot that does not contain the suspension | The cutoff is the value read before the evidence query; a snapshot taken before the deadline has a cutoff before the deadline, so nothing is settled and the record waits. The next fold's evidence contains the suspension and the delivery is settled held or `uncertain`, never `active_throughout` | DELAYED settlement only | None; AL-59 (b) if the fold stays slow | RB-17 | None needed | Settlement is later by one fold | VT-7J-133, VT-7J-138 |
| FS-36 | Dispatcher dies after claiming, repeatedly, and deliveries are later cancelled without ever being admitted | First-claim milestone happened; first admission never did | M-165 observes each first claim once; `…_never_admitted_total` rises; M-166 gains no observation; M-131 observes the terminal status once | DELAYED, then terminal | AL-24; AL-23 | RB-08 | Per 7H T-08, T-10, T-11 | None | VT-7J-101, VT-7J-102, VT-7J-105 |

### 28.2 Matrix — Validation requirements

**None of these tests has been run.** No implementation exists to run them against. Each is a requirement on the future implementation; "activation" names the gate of §32 that needs it passed.

| ID | Area | Input | Expected result | Authoritative check | Activation |
|---|---|---|---|---|---|
| VT-7J-01 | Counter boundary | Kill the relay after `XADD` and before the `WAITAOF` reply | No `CONFIRMED` increment for that entry | Outbox row not `PUBLISHED` | AG-7J-03 |
| VT-7J-02 | Duplicate emission | Force lease expiry so two relays confirm one row | M-005 `CONFIRMED` = 2; `PUBLISHED` rows = 1; M-017 has one observation | Outbox and position records | AG-7J-03 |
| VT-7J-03 | Histogram units | Inject a known 250 ms delay at each timed stage | Observation in the bucket containing 0.25, in seconds | Test clock | AG-7J-01 |
| VT-7J-04 | Gauge follows state | Insert N eligible rows; publish K | M-001 = N − K on the next read | Outbox count | AG-7J-03 |
| VT-7J-05 | Clocks | Skew the relay's and the observer's wall clocks by one hour | M-002, M-017 unchanged | Database timestamps | AG-7J-03 |
| VT-7J-06 | Unknown is not zero | Revoke the observer's database credential while rows are eligible | State series absent, not zero; AL-50 fires; no "healthy" tile | Outbox count read directly | AG-7J-02 |
| VT-7J-07 | Commit and acknowledgement are distinct | Fail `XACK` after a successful commit | M-063 `DURABLY_COMMITTED` +1; M-067 `ERROR` +1; no acknowledgement-based success | Owner row; PEL | AG-7J-05 |
| VT-7J-08 | Alert expressions | Replay recorded series through each rule | Fires and clears exactly at the documented conditions; labels and denominators as specified | Rule unit tests | AG-7J-01 |
| VT-7J-09 | Held is not failed | Suspend an organization with pending deliveries | Rows in M-126; absent from M-124, M-125, M-145 and SLI-11; a release at admission is `UNCOUNTED_RELEASE` and in none of SLI-12a, -12b, -12c; no failure alert | Delivery rows | AG-7J-07 |
| VT-7J-10 | Dependency gate | Make the owner database unavailable to one group | M-095 open; M-093 unchanged; AL-21 silent; AL-15 inhibited only while the dependency alert fires | Ledger: no failure record | AG-7J-05 |
| VT-7J-11 | Reconciliation pending is not success | Hand a case to reconciliation | In M-101 and M-103; absent from the SLI-09 numerator | Ledger state | AG-7J-05 |
| VT-7J-12 | Replay is not new business | Run an R2 and an R5 | M-107 by mode; M-005 and SLI-01 unchanged by R5; M-140 for R7 only | Operation items | AG-7J-05 |
| VT-7J-13 | Prohibited label at build | Register a metric with `organization_id`, `event_id`, a host label and a non-literal value set | Build fails for each | Build log | AG-7J-01 |
| VT-7J-14 | Prohibited label at run time | Emit an observation with a value outside the closed set, and 10,000 distinct values | No new series; M-275 increments; raw value not logged | Series count | AG-7J-01 |
| VT-7J-15 | Log redaction | Log every class P item through the helper and through a raw logger | Rejected at the helper; redacted by D0; never present in either sink | Sink search | AG-7J-01 |
| VT-7J-16 | No raw webhook body | Deliver and receive bodies containing a marker string, with failures at every stage | Marker absent from logs, spans, metrics and alert payloads | Sink and store search | AG-7J-07 |
| VT-7J-17 | No presigned URL | Process events and errors that involve a signed media reference | No URL path, query or signature in any telemetry | Sink and store search | AG-7J-01 |
| VT-7J-18 | Sealed content does not leak | Seal a row; read through every guarded path; fail the sealing worker | Denials counted; no content, digest or key reference in telemetry | Sink search; guard result | AG-7J-08 |
| VT-7J-19 | Secret scanner | Plant each pattern class in a test sink | Finding per class with no matched text recorded | Scanner output | AG-7J-06 |
| VT-7J-20 | Trace derivation | Process one event at four hops in separate processes | Same `event_trace_id` at every hop; anchor ID as specified; uniform ratio over 100,000 UUIDv7 values within tolerance of 25% | Trace store; arithmetic | AG-7J-01 |
| VT-7J-21 | Healthy trace sampling | 10,000 healthy events | About 25% of event traces present, each complete across hops; voice-call events 100% | Trace store | AG-7J-01 |
| VT-7J-22 | Late failure | An event outside the 25% fails at the consumer | The failing hop's spans present with `sampling.reason = fault`; earlier hops absent; later hops 100% | Trace store; ledger | AG-7J-05 |
| VT-7J-23 | Head-sampled-out fault | An unsampled event gets relay outcome `UNKNOWN` | SP-03 and SP-04 exported; M-005 `UNKNOWN` +1 regardless of the trace | Trace store; counter | AG-7J-03 |
| VT-7J-24 | Consumer retries | One event fails three times then succeeds | Four SP-07 siblings with `retry.number` 0 … 3; forward marking samples attempts 2 … 4 | Ledger failure count | AG-7J-05 |
| VT-7J-25 | Replay trace | R2 of a parked case | SP-13 in the event trace, linked to SP-12; mode attribute present | Operation item | AG-7J-05 |
| VT-7J-26 | Worker crash | Kill a worker mid-handler | No span for the dead attempt is required; the entry is pending; the next attempt is traced | PEL; ledger | AG-7J-05 |
| VT-7J-27 | Collector outage | Stop the Collector under load | Event throughput and latency unchanged within tolerance; drops counted; every alert still evaluates | Counters; throughput | AG-7J-01 |
| VT-7J-28 | Security incident capture | Tenant mismatch; unbound-group request; self-approval; pool setting at checkout | Counter, security-class record and alert for each; fault-sampled span where a span exists; the action still refused with telemetry disabled | Audit rows; cases | AG-7J-05 |
| VT-7J-29 | Tenant isolation of telemetry | Under a grant scoped to organization A, query for B's identifiers and for all organizations | Rejected or empty; attempt recorded | Broker record | AG-7J-06 |
| VT-7J-30 | Restricted query negatives | No role; role without ticket; closed ticket; expired grant; out-of-scope time range; shared account; T2 holder querying T3; revoked role mid-session; audit write failing | Refused in every case; with the audit write failing, no grant | Audit rows | AG-7J-06 |
| VT-7J-31 | Observer cannot mutate | With each telemetry credential attempt: `XACK`, `XGROUP`, `XADD`, `XDEL`; any `INSERT`, `UPDATE`, `DELETE`; a ledger function; an audit insert; a key-service decrypt | Every attempt denied by the target system | Target's own error | AG-7J-02 |
| VT-7J-32 | Observer functions are content-free | Call every observer function; inspect result types | Counts, bucket counts, ages, closed codes only; no identifier or text column; no organization argument | Function signatures | AG-7J-02 |
| VT-7J-33 | Redis observer ACL | As the observer: `XINFO STREAM`, `XRANGE`, `XREADGROUP`, `XINFO GROUPS` | First three denied; the last allowed. If subcommand scoping is unavailable, the fallback of OBP-05 is in force | Redis reply | AG-7J-02 |
| VT-7J-34 | Voice finalization | A conversation stalled before finalization; corrupt usage state | M-146, M-148; nothing sent to Billing | Voice state; Billing has no row | AG-7J-04 |
| VT-7J-35 | SIGNAL drop | Make the SIGNAL key unavailable | M-015 `DROPPED_TRANSPORT`; no durable indicator or alert changes | Indicator values | AG-7J-03 |
| VT-7J-36 | Stalled consumer | Stop all workers of one group while events flow | Lag and pending age rise; AL-15; not "idle"; with the group deleted, AL-12 and lag `UNKNOWN` | `XINFO GROUPS` | AG-7J-05 |
| VT-7J-37 | Recovery backlog | Park N cases; remove a replay source | M-101 = N; AL-20 at threshold; `SOURCE_MISSING` raises AL-22 | Ledger | AG-7J-05 |
| VT-7J-38 | Durability shortfall | Disconnect a shard's replica | M-035 `SHORTFALL_REPLICA`; relay outcomes `UNKNOWN`; gate opens; AL-08; no `CONFIRMED` | Adapter outcomes | AG-7J-03 |
| VT-7J-39 | Privacy faults | Journal unreachable; restore to an older snapshot; hold with no matching resource; `FROM_T0` organization with a subject hold | The signals and states of FS-15, FS-16, FS-18, FS-19; no erasure without a journal record | Step tables; journal | AG-7J-08 |
| VT-7J-40 | Lost telemetry | Stop Prometheus; stop Alertmanager; block the region's egress | Dead-man pages by the external receiver in each case | Receiver | AG-7J-01 |
| VT-7J-41 | Inhibition | Redis outage; then, during it, inject an unaccounted obligation and a tenant mismatch | One cause page; symptoms silent; AL-18 and AL-30 still page | Alert log | AG-7J-01 |
| VT-7J-42 | Notification payload | Render every alert with hostile label values (identifier-shaped, URL, free text); add an unlisted annotation | Output contains only NTF-01 fields; build fails on the annotation; content-free tier renders one fixed sentence | Rendered output | AG-7J-01 |
| VT-7J-43 | SLI reproducibility | Compute each SLI twice from the same recorded series, and once from the authoritative tables for the same period | Identical; table-derived value agrees within the stated estimation bound | Tables | AG-7J-01 |
| VT-7J-44 | Candidates are not promoted | Inspect rule files and reports | No burn-rate alert, freeze or report treats a `PROPOSED` objective as approved | Rule files | AG-7J-01 |
| VT-7J-45 | Error budget arithmetic | Synthetic 28-day series with known good and valid counts, with a stale interval | Budget, burn rate and exhaustion as computed by hand; a not-established window neither exhausts nor clears | Hand calculation | Before any SLO is approved |
| VT-7J-46 | Injected acknowledgement | With the gateway's Redis credential issue `XACK`, and separately `XREADGROUP … NOACK`, for one entry with no later entry | M-205 `GONE`; case opened; AL-18; with Redis reporting false state, the case opens at `T_obl` | Ledger; accounting | AG-7J-05 |
| VT-7J-47 | Payload-view audit | Approved unmasked view; denied view; view with the audit write failing | Audit row before release; counter after; no output without the row | Audit rows | AG-7J-05 |
| VT-7J-48 | Monitoring outage does not touch the event plane | Remove every telemetry backend; run voice calls and event processing | Turn latency and event throughput within tolerance of baseline; acknowledgements unaffected; readiness unaffected | Measured latency | AG-7J-01 |
| VT-7J-49 | Histogram interpretation | Report a quantile near a bucket boundary | Report states the bucket bounds; objective evaluated as share at or below a boundary | Report text | AG-7J-01 |
| VT-7J-50 | Residency | Add a remote-write target, a foreign exporter and a cross-region federation job | Build fails; if forced at run time, drift check raises AL-57 | Configuration | AG-7J-01 |
| VT-7J-51 | Missing evidence in a window | Remove evidence for 1 hour of a 28-day window, and for 2 days | First: `ESTABLISHED_PARTIAL` for an accounted indicator, shown as measured over 671 of 672 hours, with no verdict and no budget movement; second: reported not established | Report | AG-7J-01 |
| VT-7J-52 | Audit is not telemetry | Disable all telemetry; perform audited actions; fail the audit function | Audit rows written with telemetry off; the change is refused when the audit function fails | Audit tables | AG-7J-01 |
| VT-7J-53 | Trace expiry | Write a trace; advance time past 14 days | Not readable by any tier; verification job records it | Store query | AG-7J-12 |
| VT-7J-54 | Cold security records are minimized | Emit security-class lines carrying every class R and S field | Cold objects contain none of them; hot tier does until 90 days | Object inspection | AG-7J-12 |
| VT-7J-55 | SLO aggregates cannot identify a customer | Enumerate every label of every `slo:` series; attempt to add an identifier label | Only the RET-7J-02 list; build fails on the addition | Series metadata | AG-7J-12 |
| VT-7J-56 | Erasure leaves no unlawfully linkable telemetry | Erase a subject in an owning context; attempt to resolve hot telemetry references to the subject with T2 and with database access short of the journal's decrypt | No resolution; at 90 days no reference exists | Owning-context mapping; sink search | AG-7J-10 |
| VT-7J-57 | Hold preserves scoped evidence in time | Place a `PLATFORM` hold needing evidence 10 days after the events | Evidence set captured and verified before the 14-day trace expiry; manifest states any range already expired | Evidence objects; audit row | AG-7J-11 |
| VT-7J-58 | Other tenants keep expiring | With a hold on organization A, advance time | B's telemetry and A's ordinary telemetry expire on schedule | Store query | AG-7J-11 |
| VT-7J-59 | Failed export is not success | Break the evidence prefix; break digest verification | `_PRESERVATION_FAILED` row; SEV1; no `_PRESERVED` row | Audit rows | AG-7J-11 |
| VT-7J-60 | Restore does not resurrect telemetry | Restore a telemetry store from a snapshot older than its retention | Expired data not readable after the restore's retention pass; restore recorded | Store query | AG-7J-12 |
| VT-7J-61 | SRE credential cannot read evidence | With a T2 credential, and with the broker's credentials, read the evidence prefix | Denied | Object-store error | AG-7J-11 |
| VT-7J-62 | Audit and recovery obligations intact | Run every expiry, projection and evidence expiry | No audit row, recovery case, material, journal object or hold changed | Table and object counts | AG-7J-12 |
| VT-7J-63 | R01 trace A: two observer replicas | One row reaches `PUBLISHED`; both replicas run the fold and are scraped | One obligation record, registered once and closed once; its cohort hour's totals +1; both replicas export the same window and cumulative figures; `max without (instance)` yields 1; a `sum` across instances is rejected by the build check | Obligation record and cohort totals | AG-7J-13 |
| VT-7J-64 | R01 trace B: observer restart | Fold N rows; kill the observer before and, separately, after the fold commits; restart; fold again | Before commit: nothing counted, then N counted once. After commit: N counted once, the second fold adds 0. No in-memory state is needed | Obligation-record count = N; cohort totals = N | AG-7J-13 |
| VT-7J-65 | R01 trace C: cleanup during an outage | Publish rows; stop the observer beyond the outbox row's guaranteed life; run cleanup; restart | The deleted rows are in no bucket and no cohort; M-285 increases by the uncovered interval and its cohort hours; every window containing those hours beyond the 2% limit is `NOT_ESTABLISHED`; no value is estimated | Run record; final cohort rows | AG-7J-13 |
| VT-7J-66 | R01 trace D: equal and late timestamps | Three rows with the same `published_at`; a fourth whose transaction assigns an earlier `published_at` and commits after later rows were folded, first within the lookback and then beyond it | All four counted exactly once: the late row by the next routine fold, or, beyond the lookback, by the next completeness fold; none twice | Obligation-record count = 4 | AG-7J-13 |
| VT-7J-67 | R02 trace A: one source disappears | Stop the `journal` observer function only; wait for its series to expire | AL-50 fires with `source="journal"` at SEV1; no alert for the ten healthy sources; `absent()` of the bare metric would have stayed false. Then set the entry `DISABLED` with an expiry: no alert; after the expiry the build fails | Alert log; rule evaluation | AG-7J-01 |
| VT-7J-68 | R02 trace B: one component disappears | Stop the obligation reconciler; separately stop every worker of one consumer group; separately replace all instances of a component by new ones | AL-51 with `component="obligation_reconciler"`; AL-51 with `component="consumer"` and that `group`; no alert on replacement | Alert log | AG-7J-01 |
| VT-7J-69 | R02 trace C: one failing shard | Shard A: 10,000 confirmations. Shard B: 12 attempts, all unconfirmed | Regional ratio 99.88% would not cross a 1% threshold; AL-08 (a) and (b) fire for `shard="B"` only; SLI-03 records a bad interval | Adapter outcomes | AG-7J-03 |
| VT-7J-70 | R02 trace D: no measurements | Open the gate with rows eligible (no attempts at all); separately stop the Redis observer; separately make a shard idle with nothing owed | First: SLI-03 interval bad, not undefined. Second: unmeasured, AL-50 `redis_cluster` and `redis_group`, no tile green. Third: good (idle, shown by fresh evidence), and no durability alert | Outbox; evidence freshness | AG-7J-03 |
| VT-7J-71 | R03 A: handler time is not event latency | An event waits 30 s in the stream and its handler commits in 50 ms | M-068 observes 0.05 s; M-085 observes about 30 s; SLI-17 counts it not good against a 5 s boundary; no panel labels 0.05 s as processing latency | Completion record and outbox timestamps | AG-7J-05 |
| VT-7J-72 | R03 A: cohort denominator | In one cohort hour 99 events complete in 1 s; one is parked and never completes | At finalization the cohort is 99 good of 100 registered; M-086 `PARKED` = 1; the figure does not change when the outbox row is later deleted | Obligation records; ledger | AG-7J-05 |
| VT-7J-73 | R03 D: acknowledgement denominator | 1,000 commits; the gateway refuses 100 acknowledgements | SLI-06 = 900 of 1,000 | M-063, M-067 against the PEL | AG-7J-05 |
| VT-7J-74 | R03 D: recovery cohort | 10 cases parked; 9 resolve in an hour; one stays open past `T` | SLI-09 = 9 of 10; a case parked less than `T` ago is not in the cohort | Ledger history | AG-7J-05 |
| VT-7J-75 | R03 B: first-attempt latency | Fan-out in 0.1 s; dispatcher stopped for 10 minutes; then restarted. Separately: a suspended organization's delivery; a claim released by T-09 then claimed again | M-122 shows 0.1 s; M-145 counts the waiting rows; after restart M-168 records about 600 s each; SLI-11 not good. The suspended delivery (proved suspended inside its event-to-deadline window) is `held_interval`. The uncounted release does not end the interval; the first closure with `attempt_number = 1` does | Delivery, claim and closure records | AG-7J-07 |
| VT-7J-76 | R03 C: disjoint classes | Produce one closure of each of the nine rows of the §10.4 table | Each closure in exactly one class; 12a = 2 of 6, 12b = 4 of 8, 12c = 1 of 2; the receiver's 500 is in no excluded set of an indicator that counts it | Closure records | AG-7J-07 |
| VT-7J-77 | R03 C: class completeness | Property test over random valid closure field combinations, and over combinations 7H forbids | Every valid combination maps to exactly one of the seven named classes or `UNCOUNTED_RELEASE`; every forbidden one to `UNCLASSIFIED` with AL-25 | Class table | AG-7J-07 |
| VT-7J-78 | R03 D: callback acknowledgement | Return 2xx on the correct path, on a duplicate, and (by fault injection) before the receipt commits | Bases `RECEIPT_COMMITTED`, `DUPLICATE_OF_RECEIPT`, `NO_RECEIPT`; AL-29 SEV1 on the third | Receipt rows | AG-7J-07 |
| VT-7J-79 | R04: `UNCERTAIN` is observable | Kill a dispatcher after admission and before closure; let the sweep close the claim. Separately kill one before admission | First: closure `CLAIM_EXPIRED`, `UNCERTAIN`; M-128 and M-137 with `send_state="UNCERTAIN"`; M-144 `UNCERTAIN`; never under `SENT`, `NOT_SENT` or `other`; M-275 not incremented. Second: `NOT_SENT`, class `NOT_SENT_PLATFORM` | Closure records | AG-7J-07 |
| VT-7J-80 | R04: uncounted release | Suspend an organization between claim and admission | M-161 +1; M-164 +1; M-128 and M-163 unchanged; no `attempt_number` label value emitted or fabricated; `attempt_count` unchanged | Closure with `attempt_number` NULL | AG-7J-07 |
| VT-7J-81 | R04: the ten figures agree | Random interleavings of claim, admission, re-admission, closure, sweep and suspension (the 7H IO-7H-13 property test), with the metrics recorded | Claims ≥ closures; re-admissions = abandonments; counted closures = final `attempt_count` summed; `DELIVERED` closures = `DELIVERED` transitions; M-144 equals the record counts exactly | 7H history records | AG-7J-07 |
| VT-7J-82 | Inhibition cannot hide an unrelated incident | During a Redis outage, stop the journal source and inject a tenant mismatch; attempt to add an inhibition rule targeting an INT alert or matching by pattern | AL-50 `journal` and AL-30 page; the build rejects the rule | Alert log; build log | AG-7J-01 |
| VT-7J-83 | R05 A: an unresolved obligation survives outbox cleanup | Day 0 publish E; group G parks it; advance to Day 8 and run cleanup under ACC-06 (G has a case); advance to Day 10 | The outbox row is gone; the obligation record (G, E) is open with its `origin_at`; M-086 `PARKED` = 1 on Day 10; E is registered and not good in its Day-0 cohort hour; SLI-17's denominator for the window still contains it | Obligation record; ledger case; absence of the outbox row | AG-7J-13 |
| VT-7J-84 | R05 B: completion after cleanup | Continue VT-7J-83: on Day 12 an approved R2 replay commits a completion with origin `RECOVERY_ITEM` | The fold closes the record `COMPLETED`; latency = completion commit time minus the record's `origin_at` (about 12 days), observed in M-085 `origin="recovery"`; no read of the outbox row, of a position `recorded_at`, of an entry ID or of a worker clock; the cohort stays 0 good for that pair; M-086 `PARKED` returns to 0 | Completion record; obligation record | AG-7J-13 |
| VT-7J-85 | R05: registration missed, case still counted | Stop the observer before E is published; park E for G; delete the outbox row after 8 days; restart | No obligation record can be made (no surviving `occurred_at`); M-086 `UNREGISTERED_CASE` = 1 aged from the case's `first_seen_at`; AL-15 fires; the cohort hours of the outage are unmeasured; nothing is approximated from a position time | Ledger case; run record | AG-7J-13 |
| VT-7J-86 | R05: no extra obligations | Confirm one row twice from two relays; publish it to keys of two topology generations; redeliver and reclaim the entry; R2-replay it; R4-republish it; add a group that gains the type afterwards and R3-backfill it | Exactly one publication obligation and one processing obligation per pre-existing owed group; the later group's pair is `NOT_OWED` and its backfill is a replay item (M-107) only; a classification of each closing class (`COMPLETED`, `NOT_OWED`, `RECONCILED`, `REJECTED`, `GOVERNED_AWAY`) lands in exactly one class | Obligation records | AG-7J-13 |
| VT-7J-87 | R06 A – D: event-time cohort membership | (A) an obligation whose origin is one minute before the window's first cohort hour, folded ten minutes after it; (B) one whose origin is in the last hour before the evaluation, folded after the evaluation; (C) one fold batch containing obligations from three different days; (D) the observer stopped for four hours and restarted before any source row expires | (A) not in the window; in its own earlier hour. (B) its hour is not final at the evaluation, so it is in no reported window yet; it enters when the hour is final. (C) each in its own hour. (D) the four hours become final late and correctly; while the watermark lag exceeds its limit the state is `UNKNOWN`. In every case the fold-time counter difference gives a different number and is not what is reported | Final cohort rows | AG-7J-13 |
| VT-7J-88 | R06 E: restore during an open window | Restore the database to a point 3 hours earlier; activate it 2 hours later | The fold does not run before activation; the epoch increments; one `RESTORE_GAP` declaration covers the cohort hours from the restored last run record to the first fold after activation; they are finalized `UNMEASURED`; a window containing them is evaluated under SLI-R-04 and AOA-24; fold-time counters move backwards and no reported figure changes because of that | Epoch; declarations; final cohort rows | AG-7J-13 |
| VT-7J-89 | R06: finalization and corrections | Finalize an hour; then (i) commit a producer transaction that had been open since that hour; (ii) insert an event with `occurred_at` six hours in the past (the EV-079 pattern); (iii) reclassify a final-hour obligation `NOT_OWED` | The final row is byte-identical afterwards; correction counters for those hours move; the window Gauge includes them; M-293 increments; the history store's earlier samples are not rewritten. An hour is not finalized measured while an upstream stream is neither final for it nor past its lag bound (F3), or while a pair is unclassified (F4) | Final rows; correction counters | AG-7J-13 |
| VT-7J-90 | R07: one stream goes silent | With all top-level sources fresh and the other seven streams folding, stop only the `consumer_completion` fold (separately its routine fold only, then its completeness fold only); let its series go stale and then disappear | AL-59 (a) fires with `stream="consumer_completion"` and the exact `fold_kind`; no alert for the other seven; AL-50 does not fire for `accounting`, which shows why AL-50 alone was insufficient. An idle stream with zero traffic keeps folding and raises nothing. A stream `DISABLED` with an expiry raises nothing until the expiry, after which the build fails | Rule evaluation; run records | AG-7J-01, AG-7J-13 |
| VT-7J-91 | R07: a missing stream gates its indicator | Continue VT-7J-90 | SLI-17's window state becomes `UNKNOWN` for every group (watermark too old; then no state series at all, read as `UNKNOWN`); no figure, zero or otherwise, is reported; M-086 still shows open obligations registered before the stop and every `UNREGISTERED_CASE` since; no error budget is exhausted or cleared | Window state; reports | AG-7J-13 |
| VT-7J-92 | R08: one unmeasured hour inside 672 | A stream with 700 final hours, exactly one of them `UNMEASURED` inside the trailing 672, with non-zero `observed` counts and one correction entry on it | The read function returns `hours` 672, `measured_hours` 671, `unmeasured_hours` 1; every sum equals the sum over the 671 measured hours; the observed counts and the correction on the unmeasured hour are in no sum; state `ESTABLISHED_PARTIAL`; no verdict, no budget movement. Replacing that hour by a `MEASURED` hour with zero counts gives a different result (state `ESTABLISHED`), which shows the implementation does not read an unmeasured hour as an empty one. The window's first hour is `w − 672 h`, not an older measured hour | Hour ledger; read function | AG-7J-13 |
| VT-7J-93 | R08: five unmeasured hours after a restore | Restore to a point in the middle of hour `h`; activate so that the first fold runs in hour `h + 4`; then run several hundred fully measured hours | The fold refuses before activation. Its first run appends one `RESTORE_GAP` declaration for `h … h + 4`. Each of the five is finalized `UNMEASURED`, in order, once F1 holds for it, without F2 – F4; the watermark advances across all five and on through the later hours. While all five are inside the window `unmeasured_hours` is 5 and the state is `ESTABLISHED_PARTIAL`; no budget is consumed, exhausted or cleared; when the last of them leaves the 672 hours the state is `ESTABLISHED` | Run records; declaration; hour ledger; M-285, M-290, M-291 | AG-7J-13 |
| VT-7J-94 | R08: monitoring outage that recovers without loss | Stop both observers for a time shorter than `R_min − m` with traffic and cleanup running; restart | No declaration is appended; M-285 does not move. During the outage the hours stay `OPEN`, the watermark does not advance and the window is `UNKNOWN` once the lag bound passes. After the restart every source row is registered, the hours are finalized `MEASURED` in order, and the window returns to `ESTABLISHED` with `unmeasured_hours` 0 and the same sums a continuously running fold would have produced | Run records; hour ledger | AG-7J-13 |
| VT-7J-95 | R08: monitoring outage with irreversible source loss | Stop both observers for longer than `R_min − m` while cleanup deletes published rows; restart | The first completeness fold appends one `REGISTRATION_GAP` declaration for exactly the hours AOA-11 names; they are finalized `UNMEASURED`; rows of those hours that still exist are registered and kept as observed counts only; a window with more than 13 such hours is `NOT_ESTABLISHED`. Deleting the declaration or editing a final row is refused by the database | Run records; declarations | AG-7J-13 |
| VT-7J-96 | R08: missing accounting stream | Leave one stream `EXPECTED` in the registry and never run its fold; run the others | AL-59 (a) for that stream and fold kind; its window `UNKNOWN`, no figure; no hour of it becomes unmeasured by the passing of time. A downstream stream's hours are finalized once the lag bound of F3 has passed, and what the missing stream lets through later arrives as corrections | Rule evaluation; hour ledger | AG-7J-01, AG-7J-13 |
| VT-7J-97 | R08: late observation into an unmeasured hour | After VT-7J-95, publish an outbox row that was `PENDING` since an hour now final and `UNMEASURED`; separately insert an event past-dated into such an hour | Each obligation is registered with its true `origin_at`, has its record, appears in M-022 or M-086 while open, and is observed in its fold-time histogram at its close. Its count is appended to the hour's observed counts (M-293 `into_unmeasured`). The hour stays `UNMEASURED`; no window sum and no `unmeasured_hours` value changes | Obligation records; correction entries | AG-7J-13 |
| VT-7J-98 | R08: upstream permanently unmeasured, downstream assessable | Stop only the `outbox_publication` folds for longer than `R_min − m`; keep the `consumer_completion` folds running | Publication hours are finalized `UNMEASURED`; the same hours of `consumer_completion` are finalized `MEASURED` (F3 is satisfied by the upstream being final, and before that by the lag bound); SLI-01 is partial or not established while SLI-17 is `ESTABLISHED`; no hour waits for ever | Hour ledgers of both streams | AG-7J-13 |
| VT-7J-99 | R08: the window rolling across an unmeasured interval | Finalize hour by hour across a five-hour unmeasured interval and for 680 hours after it | At every step `measured_hours + unmeasured_hours = 672`; the window start and end each move by exactly one hour per finalized hour; `unmeasured_hours` goes 0, 1, 2, 3, 4, 5, stays 5 for 667 steps, then 4, 3, 2, 1, 0; no hour older than `w − 672 h` is ever summed. Property test over random ledgers: the read function's result equals a direct sum over the measured hours of that interval | Read function | AG-7J-13 |
| VT-7J-100 | R09: normal lifecycle | Delivery created at T0, first claim T1, first admission T2, `DELIVERED` at T3; run the folds at arbitrary times and in arbitrary numbers | Three records exist, one per milestone stream, each closed once. M-165 has one observation of T1 − T0, M-166 one of T2 − T0, M-131 one of T3 − T0 with `status = DELIVERED`; no further fold changes any of them | Obligation records; claim, admission and delivery rows | AG-7J-13 |
| VT-7J-101 | R09: claim without admission | Claim; the worker fails before admission and the claim is closed (T-06 or T-08, `NOT_SENT`); later a second claim is admitted | M-165 observes the first claim once. The first-admission record stays open through the first claim and closes at the second claim's admission; M-166 has exactly one observation, of that admission | Records | AG-7J-13 |
| VT-7J-102 | R09: first claim expires, second claim succeeds | Claim 1 at T1 is released by the sweep; claim 2 at T1′ delivers | M-165 holds T1 − T0 and never T1′ − T0; the claim with `claim_seq = 2` is not read by the stream | Claim records | AG-7J-13 |
| VT-7J-103 | R09: two admissions in one claim | Admission 1, a configuration change, abandonment, admission 2 in the same claim | M-166 observes admission 1's `admitted_at` once; the re-admission finds the record closed; the abandonment record is not read by any milestone stream | Admission records | AG-7J-13 |
| VT-7J-104 | R09: suspension with an uncounted release | Claim; suspend the organization; admission executes T-09; reactivate; claim 2; admission; delivered | M-165 observes claim 1. The uncounted release closes no milestone record and adds no observation anywhere in these streams. M-166 observes the admission of claim 2, measured from `created_at`. M-131 observes the terminal status once. `attempt_count`, the closure records and every delivery column are unchanged by the folds | Records; delivery row before and after | AG-7J-13 |
| VT-7J-105 | R09: cancellation before first admission | A `PENDING` delivery of a cancelled organization is closed by T-10; separately one that was claimed and released uncounted and then cancelled by T-11 | First: first-claim record closed `NEVER_CLAIMED`, first-admission record `NEVER_ADMITTED`, no bucket observation in M-165 or M-166, the two never-reached counters +1 each. Second: M-165 has one observation; first-admission `NEVER_ADMITTED`. In both M-131 observes `CANCELLED` once | Records | AG-7J-13 |
| VT-7J-106 | R09: dead-letter after repeated counted failures | Fail every attempt up to `max_attempts`: once with every failure before admission, once with admissions | M-165 one observation in both runs. M-166: none and `NEVER_ADMITTED` in the first run; exactly one, the earliest admission, in the second. M-131 one observation with `status = DEAD_LETTER`. The number of counted failures changes none of the three | Records | AG-7J-13 |
| VT-7J-107 | R09: observer crash between discovery and commit | Kill the observer inside the fold after it has selected rows and before its commit, at each milestone | No record, total or histogram series changed; the next fold produces exactly the single observation | Records; totals | AG-7J-13 |
| VT-7J-108 | R09: both observers at once | Run both replicas' folds concurrently across random interleavings of the lifecycle of VT-7J-100 | One of two concurrent calls returns "busy"; each milestone is observed once; both replicas export identical series; `max without (instance)` equals either | Records; exported series | AG-7J-13 |
| VT-7J-109 | R09: source cleanup after accounting | Close all three records; purge the delivery and its history; run routine and completeness folds | Nothing is re-registered, re-observed or reopened. Separately purge a delivery whose records are still open: they close `SOURCE_GONE` with no observation, and that is possible only inside a declared registration gap | Records; run records | AG-7J-13 |
| VT-7J-110 | R09: no content read, no mutation | As the observer principal: select from the delivery, claim, admission and closure relations; call every fold. Compare every source relation, row by row, before and after 1,000 folds. Scan the fold bodies | Direct selects are denied. The folds reference no body, hash, URL, fingerprint, host, port, address, `config_revision`, preview or secret-reference column, and no statement that writes or row-locks a relation outside accounting. Source relations are byte-identical before and after | Catalog privileges; body scan; relation comparison | AG-7J-13 |
| VT-7J-111 | R12: active throughout | Event 12:00:00; no lifecycle transition, before or after; delivery created 12:00:01; first counted closure 12:00:10 | Initial `active_throughout` (provisional); settled `active_throughout`; numerator +1, denominator +1; no move, no correction | No lifecycle evidence row for the organization; record with class, basis and `t_e` | AG-7J-13 |
| VT-7J-112 | R12: suspended before the event | Suspension `locked_at` 11:50:00, sighted 11:50:05, no later transition; event 12:00:00; delivery created 12:00:01 (7H FAN-05); never claimed | Initial `active_throughout`; settled `held_interval` (certainly `SUSPENDED` at 12:00:00); numerator 0, denominator −1 from the provisional count, `excluded_held` +1; M-126 +1; M-145 unchanged | Transition `k` with sequence, to-state and `locked_at`; its sighting; the record | AG-7J-13 |
| VT-7J-113 | R12: suspended after the event, before fan-out | Event 12:00:00; suspension `locked_at` 12:00:05, sighted 12:00:07; delivery created 12:00:12; no claim | Settled `held_interval` (certainly `SUSPENDED` from 12:00:07, inside `W`); out of numerator and denominator once; `excluded_held` +1. A window anchored at `created_at` would also see it; one anchored at the audit row would depend on that transaction's start time | Transition and sighting; record | AG-7J-13 |
| VT-7J-114 | R12: suspended and reactivated before the delivery is created (the review's counterexample) | Event 12:00:00; suspension `locked_at` 12:00:05; reactivation `locked_at` 12:00:20; delivery created 12:00:25; first counted closure 12:00:35; deadline 12:00:30. Run once with the fold sighting each transition within 1 s, once with no fold running until 12:02:00 | Settled `held_interval` in both runs: the organization is certainly `SUSPENDED` at 12:00:20, the reactivation's `locked_at`, whatever the fold's lag. Not counted valid and not good; `excluded_held` +1; M-167 and M-168 observe the closure under `held_interval`; M-296 observes about 21 s in the first run (35 s less the certain hold) and counts the delivery as unmeasurable in the second, where the band is 15 s wide | Transitions `k`, `k + 1` in sequence; record | AG-7J-13 |
| VT-7J-115 | R12: suspended after creation, before the first claim | Event 12:00:00; created 12:00:02; suspension `locked_at` 12:00:10, sighted 12:00:12; cohort hour `H` still open | Before settlement `H`'s (`topic`, `active_throughout`) registered count includes the delivery. Settlement is one compare-and-set: that count −1, (`topic`, `held_interval`) +1. Re-running the fold, or the other replica, changes nothing | Totals before and after; record | AG-7J-13 |
| VT-7J-116 | R12: suspended after the claim, before admission | Event 12:00:00; created 12:00:02; claim 12:00:04; suspension `locked_at` 12:00:06, sighted 12:00:08; the admission executes 7H T-09 at 12:00:09. Variant: the admission transaction began at 12:00:05 and waited for the lock, so its closure carries a stored time before the suspension | Settled `held_interval` from the lifecycle evidence in both variants. The uncounted release is consistent with it and is not the timing proof; its stored time is not compared with anything. Nothing is counted as an attempt or a failure; `attempt_count` unchanged | Transition and sighting; closure record with NULL `attempt_number`; record | AG-7J-13 |
| VT-7J-117 | R12: suspended during backoff | Event 12:00:00; first counted closure (a failure) 12:00:08; (i) suspension `locked_at` 12:00:15, sighted 12:00:17; (ii) instead suspension `locked_at` 12:00:40 | (i) Settled `held_interval`: the hold is proved inside `W`, so the whole delivery leaves numerator and denominator although its first closure was in time (the approved trade-off, AOA-27 l); `excluded_held` +1; M-296 observes 8 s. (ii) Settled `active_throughout`, good; the later hold is in M-126 only | Transition; closure with `attempt_number = 1`; record | AG-7J-13 |
| VT-7J-118 | R12: suspended after the deadline | Event 12:00:00; dispatcher stopped; no closure by 12:00:30; suspension `locked_at` 12:00:45 | Settled `active_throughout`, valid and not good; never moved; in M-126 and out of M-145 while held; back in M-145 on reactivation if still unclosed | Transition with `locked_at` after `decide_by`; record | AG-7J-13 |
| VT-7J-119 | R12: suspended after the first counted closure | Event 12:00:00; first counted closure 12:00:10; suspension `locked_at` 12:00:50 | Settled `active_throughout`, good; numerator +1, denominator +1; no move | Record | AG-7J-13 |
| VT-7J-120 | R12: two suspension and reactivation cycles | Event 12:00:00; `locked_at` of suspend, reactivate, suspend, reactivate at 12:00:03, 12:00:08, 12:00:15, 12:00:22; a repeated suspend call in between (the frozen no-op) | Four transitions with consecutive sequence numbers; the no-op writes none. Settled `held_interval` once; exactly one move; reactivation never moves a delivery back | Sequence without gap; record | AG-7J-13 |
| VT-7J-121 | R12: cancellation before closure | Event 12:00:00; created 12:00:02; (i) organization cancelled, `locked_at` 12:00:12; the 7H sweep later cancels the delivery (T-10); (ii) instead cancelled at 12:05:00 | (i) Settled `held_interval`; closing class `CANCELLED_UNATTEMPTED`; excluded once. (ii) Settled `active_throughout`, valid and not good; the later cancellation closes the record and moves nothing | Transition to `CANCELLED`; delivery `completed_at`; record | AG-7J-13 |
| VT-7J-122 | R11 A: long lifecycle transaction, audit row dated before the deadline | Event 12:00:00, deadline 12:00:30. A suspension transaction begins at 12:00:20, obtains the organization lock and updates at 12:00:40, commits at 12:00:41. Its audit row carries 12:00:20 | The lifecycle evidence has `locked_at` 12:00:40. The delivery is settled `active_throughout`, valid and not good. Asserted separately: a classifier that read the audit row's time would have returned held | Audit row `occurred_at` 12:00:20; transition `locked_at` 12:00:40; record | AG-7J-13 |
| VT-7J-123 | R11: rollback | A suspension transaction locks the row at 12:00:10, updates, inserts its audit and provenance rows, and rolls back at 12:00:12 | No audit row, no provenance row, no sequence number used; the delivery is settled `active_throughout` | Absence of rows; next transition takes the next number without a gap | AG-7J-13 |
| VT-7J-124 | R11 B: lock wait and reversed audit timestamps | Event 12:00:00. Transaction `B` (reactivate) begins at 12:00:10 and runs its statements that precede the lock (proof verification and the session read, 7I OLC-13); it has not yet requested the organization row lock. Transaction `A` (suspend) begins at 12:00:11 and obtains the row lock at 12:00:12. `B` requests the lock at 12:00:12.5 and waits for `A`. `A` commits at 12:00:13. `B` obtains the lock at 12:00:13.1, finds `SUSPENDED`, updates and commits at 12:00:14. The fixture holds `B` before its locking statement with a test-only advisory lock | Audit times: `B` 12:00:10 before `A` 12:00:11, although `B` took effect after `A`. Lifecycle evidence: `A` has the lower sequence and `locked_at` 12:00:12; `B` has the higher sequence and `locked_at` 12:00:13.1. The organization is certainly `SUSPENDED` at 12:00:13.1; the delivery is settled `held_interval`. Repeated with a tenant compare-and-swap in the place of `B` that finds zero rows after its wait (no transition, no row) | Both audit rows; both transitions; record | AG-7J-13 |
| VT-7J-125 | R11 C: late-visible lifecycle transaction | Event 12:00:00. A suspension transaction locks at 12:00:25 and is held open. The fold evaluates at `t_e` = 12:01:00 and the hour is finalized. The transaction commits at 13:30:00 | At 12:01:00 the transition is not visible, so it took effect after 12:01:00: the delivery is settled `active_throughout` and that is true. After the commit: the record is not revised, no correction entry is appended, the final row is byte-identical, M-293 does not move. The transition's band begins at 12:00:25 and matters only to windows that end after `t_e` could have seen it | Record with `t_e`; final row; correction list | AG-7J-13 |
| VT-7J-126 | R11: a band across the deadline gives `uncertain` | Event 12:00:00; suspension `locked_at` 12:00:28; commit 12:00:29 or 12:00:31 (two runs); first fold sighting 12:00:50; no later transition; first counted closure 12:00:20 in one run, none in another | In all runs the band (12:00:28, 12:00:50) covers the end of `W` and `W` holds no certainly non-`ACTIVE` instant: settled `uncertain`, basis `TIMING_BAND`. Not in numerator or denominator; `uncertain_registered` +1, and `uncertain_good` +1 where the closure was in time; the two bounds differ by exactly this delivery; the window is `ESTABLISHED_UNCERTAIN` and gives no verdict and no budget movement, whether or not the bounds agree (OD-7J-14) | Transition; sighting; record | AG-7J-13 |
| VT-7J-127 | R12: reclassification after finalization | An event's delivery row becomes visible only after its cohort hour `H` is final (a producer transaction open since then); its organization was suspended throughout `W` | In one fold: `+1 registered` on (`topic`, `active_throughout`), reason `LATE_REGISTRATION`; then `−1` there and `+1` on (`topic`, `held_interval`), reason `ELIGIBILITY_RECLASSIFIED`. The final row of `H` is byte-identical; final plus corrections is non-negative for every tuple; the window shows the delivery in `excluded_held` only; M-293 `eligibility_moved` +1 | Final row; correction entries | AG-7J-13 |
| VT-7J-128 | R12: restoration and cleanup of historical evidence | (i) Restore to a point after a delivery was settled. (ii) Restore to a point before a suspension that the lost timeline had committed. (iii) Purge a delivery, its history and the lifecycle rows after settlement. (iv) Settle a late-registered record whose lifecycle rows 7I no longer retains | (i) The record returns with its class, basis and `t_e`; nothing is re-evaluated. (ii) The hours from the restore point to the first fold after activation are `UNMEASURED` (AOA-14); nothing is inferred about the lost transition. (iii) No figure changes: the class is in the record. (iv) `uncertain`, basis `EVIDENCE_UNAVAILABLE`; never `active_throughout`; the window is `NOT_ESTABLISHED` | Records; hour ledger; declarations | AG-7J-13 |
| VT-7J-129 | R11, R12: idempotence and concurrency of settlement | Both replicas' folds evaluate the same records across random interleavings; a crash is injected between the record update and the count update; evidence is evaluated repeatedly | Exactly one settlement per record; record and counts change together or not at all; the same class from either replica | Records; totals | AG-7J-13 |
| VT-7J-130 | R12: exactness and bounds (property test) | Random histories of events, fan-out, claims, admissions, releases, closures, lifecycle transitions with random lock waits and commit delays, folds and finalizations | Every delivery is in exactly one of the three classes; the three sum to the registered deliveries of each hour; no value is negative; whenever `vA > 0`, `gA / (vA + vU − gU) ≤ gA / vA ≤ (gA + gU) / (vA + gU)`; whenever `vA = 0` the ratio and both bounds are absent; no generated history yields `NaN`, an infinity, or a verdict on a window that holds an uncertain delivery or no proven-eligible delivery; no delivery is `held_interval` unless the generated history had the organization non-`ACTIVE`, by commit, inside `W`, and none is `active_throughout` unless it was `ACTIVE`, by commit, throughout `W` | Read function; generator's commit log | AG-7J-13 |
| VT-7J-131 | R11: authorization of the lifecycle evidence | As the observer principal: call the listing function; select from the provenance relation, from `audit.audit_events` and from `organization.organizations`. As any login role: insert, update or delete a provenance row; call a lifecycle function without its proof. Scan the fold bodies | All denied. The listing function, called by the fold, returns sequence, state codes, `locked_at` and an opaque reference only. The folds reference no audit relation. No role but the lifecycle functions' owner can write a transition, and a duplicate or skipped sequence number is rejected by the constraint | Catalog privileges; body scan | AG-7J-13 |
| VT-7J-132 | R11: evidence fault | Remove one transition from the middle of an organization's sequence (as a restore-time defect would); separately set the organization row to a status its last transition does not name; separately make the listing function fail | First two: affected records settled `uncertain`, basis `EVIDENCE_FAULT`; the 7I integrity alarm; the window `NOT_ESTABLISHED`. Third: the fold fails as a whole and goes stale (AL-59); no record is settled; no class is guessed | Records; alarm; run records | AG-7J-13 |
| VT-7J-133 | R13 trace A (PostgreSQL 18 fault injection) | Event 12:00:00, deadline 12:00:30, settle delay 5 s. Start a fold so that its listing call reads `cutoff` at 12:00:27.9 and takes its evidence snapshot at 12:00:28; hold the fold with a deliberate delay; commit a suspension (locked 12:00:28.5) at 12:00:29; let the fold continue and read the clock at 12:00:40 for its sightings; then run a second fold | First fold: `t_e` is 12:00:27.9, before `decide_by` plus the settle delay, so the record is **not settled**; the 12:00:40 clock value is not a cutoff. Second fold: the suspension is returned; its band runs from 12:00:28.5 to that fold's sighting; settled `uncertain`, basis `TIMING_BAND`. In no run is the record `active_throughout`. Asserted separately: a classifier using the later clock read as its cutoff would have returned `active_throughout` | Record with `t_e`; run records; transition | AG-7J-13, AG-7J-14 |
| VT-7J-134 | R13 trace B | `cutoff` read at 12:00:36.0; suspension locks at 12:00:36.2 and commits at 12:00:36.5; evidence snapshot at 12:00:37 | The transition is returned with `locked_at` 12:00:36.2, after the deadline; every instant of `W` is certainly `ACTIVE`; settled `active_throughout`, valid, good or not good by its closure. Returning a transition that took effect after `t_e` cannot hurt: its lower bound already places it after `W` | Record; transition | AG-7J-13, AG-7J-14 |
| VT-7J-135 | R13 trace C | Suspension locks at 12:00:10, commits at 12:00:11. (i) A fold sights it at 12:00:12; (ii) no fold runs until the settling one. `cutoff` 12:00:36, snapshot after it | Returned in both. (i) Band 12:00:10 to 12:00:12; certainly `SUSPENDED` from 12:00:12; settled `held_interval`. (ii) Band 12:00:10 to the sighting after 12:00:36; no certain instant in `W`; settled `uncertain`. Never `active_throughout` | Record; sighting | AG-7J-13, AG-7J-14 |
| VT-7J-136 | R13 trace D | Suspension transaction begins at 12:00:20, locks at 12:00:31, commits at 12:00:33; `cutoff` 12:00:36 | Returned with `locked_at` 12:00:31, after the deadline; settled `active_throughout`, valid and not good if unclosed. Its audit row says 12:00:20 and is not read | Audit row; transition; record | AG-7J-13, AG-7J-14 |
| VT-7J-137 | R13 trace E | The fixture of VT-7J-124, settled by a fold with `cutoff` 12:00:36 | Both transitions returned in sequence order; certainly `SUSPENDED` at 12:00:13.1; settled `held_interval` | As VT-7J-124 | AG-7J-13, AG-7J-14 |
| VT-7J-138 | R13 trace F | `cutoff` 12:00:36, evidence snapshot 12:00:36.1; a suspension that locked at 12:00:29 commits at 12:00:37; the fold then reads the clock at 12:00:40 and commits | The transition is not returned, so it took effect after 12:00:36, after `W`; settled `active_throughout`, which is true: the organization was `ACTIVE` until 12:00:37. The 12:00:40 value is used only as the sighting of rows that were returned. The record is not revised later | Record with `t_e`; transition | AG-7J-13, AG-7J-14 |
| VT-7J-139 | R13 trace G | A suspension locks at 12:00:10, updates, and rolls back at 12:00:12; `cutoff` 12:00:36 | No row and no sequence number; settled `active_throughout`. The next real transition takes the next number without a gap | Absence of rows | AG-7J-13, AG-7J-14 |
| VT-7J-140 | R13 trace H | Kill the fold after its listing call returned and before its commit, with a transition returned and a settlement prepared | Nothing committed: record unsettled, counts unchanged, no sighting stored. The next fold reads a new `cutoff` and new evidence and commits exactly one settlement. Its band may be wider than the lost one (the sighting is later), so the class may be `uncertain` where the lost attempt would have proved more; it is never less safe | Record; totals; sightings | AG-7J-13, AG-7J-14 |
| VT-7J-141 | R13 trace I | Both replicas' folds evaluate the same record at overlapping times, each with its own `cutoff` and snapshot | One call holds the stream lock and the other returns "busy"; one compare-and-set succeeds; the stored `t_e`, class and basis are those of the transaction that committed; totals move once | Record; totals | AG-7J-13, AG-7J-14 |
| VT-7J-142 | R13 trace J | Settle records; sight transitions; restore to a point before some sightings and one transition; activate | Records, counts, sightings and evidence return to the restore point together. Settled records keep their class. The lost transition is not inferred from anything. The fold does not run before activation; the gap hours are `UNMEASURED`. A returned transition whose sighting was lost is sighted again, later, so its band is wider and never narrower | Hour ledger; declarations; sightings | AG-7J-13, AG-7J-14 |
| VT-7J-143 | Minor R03: zero denominators | Windows in which: there is no delivery; every delivery is `held_interval`; every delivery is `uncertain`; all uncertain deliveries are good and none is proved eligible | In each, `registered` for the eligible tuple is 0; the ratio and both bounds are absent (no sample, SQL `NULL`); no rule or panel shows 100%, 0%, `NaN` or infinity; no verdict; no budget figure; the last established budget state is preserved | Read function; recording rules | AG-7J-13 |
| VT-7J-144 | R13: declarations and isolation | Declare the listing function or a fold `STABLE`; call the listing function in a `REPEATABLE READ` and in a `SERIALIZABLE` transaction; scan the fold bodies for a call to the listing function inside a larger query, for a cached result, and for any use of `NOW()`, `transaction_timestamp()` or `statement_timestamp()` as a cutoff | The migration's assertion block fails on the declaration; the function raises under both isolation levels and returns nothing; the scan finds none | Catalog (`provolatile`); function bodies | AG-7J-13, AG-7J-14 |
| VT-7J-145 | OD-7J-15: evidence lifetime, fail closed | Run the removal function on an organization with transitions older than the lifetime; register late a delivery whose window begins before the resulting `covered_from`; separately one whose window begins after it, for an organization with no retained transition | First: settled `uncertain`, basis `EVIDENCE_UNAVAILABLE`, whatever the current status is; never `active_throughout` or `held_interval` by absence. Second: the status throughout the window is `base_state`, proved from `covered_from` forward, and the class follows from it. `covered_from` moved forward only, to an instant older than the lifetime; the sequence continues from its last value | Listing output with the baseline; record | AG-7J-14 |
| VT-7J-146 | R14 A: provenance starts while the organization is `ACTIVE` | Install the evidence at day 0 for an existing `ACTIVE` organization; event on day 1; separately an event one hour before installation | Baseline: sequence 0, `ACTIVE`, `covered_from` = the post-lock clock of the installation. Day-1 delivery: `active_throughout`, proved. The earlier one: `EVIDENCE_UNAVAILABLE` | Baseline row; records | AG-7J-14 |
| VT-7J-147 | R14 B: provenance starts while the organization is `SUSPENDED` | As VT-7J-146 with the organization `SUSPENDED` at installation; event on day 1; reactivation on day 2 | Baseline `SUSPENDED`. Day-1 delivery: `held_interval`. Nothing reads the organization as `ACTIVE` at installation | Baseline row; record | AG-7J-14 |
| VT-7J-148 | R14 C: no transition since the baseline | An organization with a sequence-0 baseline and no transition; events at several times after `covered_from` | Each window is proved `base_state` up to the evaluation cutoff; the class follows; the listing returns the baseline and no transition | Listing output | AG-7J-14 |
| VT-7J-149 | R14 D (the review's counterexample) | Day 0: `ACTIVE` → `SUSPENDED` (sequence 1). Day 1: the maintenance pass confirms it. Day 46: the pass removes it: baseline (1, `SUSPENDED`, day 1). Day 50: event; `B` = 30 s. Day 59: `SUSPENDED` → `ACTIVE` (sequence 2). Day 60: the fold settles | The listing returns the baseline and, as the first transition after the range, sequence 2 with from-state `SUSPENDED`. The chain continues the baseline. Status is certainly `SUSPENDED` from day 1 to the `locked_at` of sequence 2 on day 59, which contains the window: settled `held_interval`. The current status, `ACTIVE`, is returned and not used. Variant with the pass not having run before day 60: sequence 1 is still retained and precedes the window; same class | Baseline; transition 2; record | AG-7J-14 |
| VT-7J-150 | R14 E: earlier `ACTIVE` transition removed, later `SUSPENDED` retained | Reactivation (sequence 2) confirmed and removed: baseline (2, `ACTIVE`, its confirmation). Event later; suspension (sequence 3) after the window | Status certainly `ACTIVE` from `covered_from` to the `locked_at` of sequence 3: `active_throughout`, proved by the baseline and the successor, not assumed | Baseline; transition 3; record | AG-7J-14 |
| VT-7J-151 | R14 F: several retained transitions straddle the window | Transitions before, inside and after the window, all retained | The listing returns the last before, all inside and the first after; classification by the bands, as VT-7J-120 | Listing output; record | AG-7J-14 |
| VT-7J-152 | R14 G: a from-state that contradicts the baseline | Baseline (4, `ACTIVE`, …); the next retained transition is sequence 5 with from-state `SUSPENDED`; separately the next retained is sequence 6 | Both: `uncertain`, basis `EVIDENCE_FAULT`; the 7I integrity alarm; the window `NOT_ESTABLISHED`. No status is chosen between the two accounts | Listing output; record; alarm | AG-7J-14 |
| VT-7J-153 | R14 H: the earliest retained transition is in an uncertain band | Baseline covers the window's start; transition `base_seq + 1` has `locked_at` inside the window and no certain non-`ACTIVE` instant follows within it | `uncertain`, basis `TIMING_BAND`, exactly as for any transition; the baseline changes nothing about bands | Record | AG-7J-14 |
| VT-7J-154 | R14 I: prefix removal concurrent with a lifecycle read | Hold a removal transaction open after its delete and baseline update; run the listing; commit the removal; run the listing again. Then the reverse order | The first listing sees the old baseline and the old rows, the second the new baseline and fewer rows; neither sees a mixture. Both give the same class or the second gives `EVIDENCE_UNAVAILABLE`; never a different proved class. A record settled from the first is not revised | Listing outputs; record | AG-7J-14 |
| VT-7J-155 | R14 J: fold crash after obtaining evidence | Kill the fold after the listing returned a baseline and before its commit; run the removal function; run the fold again | Nothing was committed by the first fold; the second settles once, from the evidence then present | Record | AG-7J-14 |
| VT-7J-156 | R14 K: two folds race | Both replicas evaluate the same record, one before and one after a removal | One settlement, from the fold that commits; the stream lock and the compare-and-set as VT-7J-141 | Record | AG-7J-14 |
| VT-7J-157 | R14 L: restore keeps an older baseline and loses the latest transition | Restore to a point before the latest transition and before the last removal | Baseline, transitions, organization row and accounting return to one point and agree with each other; the removed prefix is back and is removed again later; the lost transition is not inferred; the gap hours are `UNMEASURED` | Baseline; hour ledger | AG-7J-14 |
| VT-7J-158 | R14 M: coverage begins after the event | `covered_from` is later than `occurred_at` and earlier than `decide_by` | `EVIDENCE_UNAVAILABLE`: the start of the window is not established, even though part of the window is covered | Record | AG-7J-14 |
| VT-7J-159 | R14 N: a transition commits after the cutoff, before the evidence query completes | As VT-7J-138 with a baseline and no retained transition before the window | The transition is returned or not; in both cases its `locked_at` or its absence places it after the window; the baseline establishes the start; the class is proved | Record with `t_e` | AG-7J-14 |
| VT-7J-160 | R14 O: a window older than the retained coverage; maintenance properties | A replayed fan-out creates a delivery whose event is 90 days old. Separately, property test of the maintenance function over random lifecycle histories, lock waits and pass times | The delivery: `EVIDENCE_UNAVAILABLE`; its cohort hour is outside every window. The function: `covered_from` never decreases; it never exceeds an instant at which the generated history had the organization in a status other than `base_state` after it; it is always older than the lifetime; no transition is removed whose proving instant is younger than the lifetime; a pass on a locked organization is skipped; M-284's unsettled-window age rises before any needed evidence is removable | Baseline history; generator's commit log | AG-7J-14 |

---
## 29. Owner Decisions

### 29.1 Register

The first ten were put to the platform owner as options with a recommendation and were approved on 2026-10-12. OD-7J-11 … OD-7J-13 were put the same way after the fourth independent review, which required the first two as owner confirmations, and were approved on 2026-10-12 in writing with numbered conditions (§29.3). OD-7J-14 and OD-7J-15 were put the same way after the fifth review, before the affected sections were written, and were approved on 2026-10-12 in writing with numbered conditions. OD-7J-01 … OD-7J-09 were approved in writing with numbered conditions. OD-7J-10 was approved by selection, and the owner's conditions on a failed preservation, as stated in the remediation directive that followed the first independent review, are recorded and mapped in §29.3 and EVP-17. Where the conditions are stricter than the option text first offered, the conditions govern and the difference is stated.

| ID | Decision | Approved | Governing rules |
|---|---|---|---|
| OD-7J-01 | Status of numeric event-pipeline objectives | Option A: candidates until 7K; binding only by explicit owner approval | SLO-01 … SLO-07; §11.2 |
| OD-7J-02 | Error-budget window and consequence | Option A: rolling 28 days; controlled change freeze | EB-01 … EB-12 |
| OD-7J-03 | Telemetry retention | Option A: raw metrics 30 days; SLO aggregates 13 months; traces 14 days; alert history 13 months; incident records 2 years | §27.1, RET-7J-01 … RET-7J-05 |
| OD-7J-04 | External alert payload | Option A: minimal metadata, with a content-free tier and an in-region-only tier where a contract requires | NTF-01 … NTF-14 |
| OD-7J-05 | Access to restricted telemetry | Option A: tiered, named, case-bound | §22.2, TQA-01 … TQA-16 |
| OD-7J-06 | Sampling of event-pipeline traces | Option A: 25% baseline plus critical-fault capture | SMP-01 … SMP-11 |
| OD-7J-07 | Paging policy | Option A: four severities; immediate paging for integrity, security and privacy | §23.1, ALR-01 … ALR-13 |
| OD-7J-08 | Data-subject erasure and telemetry | Option A: minimize; strip subject-linkable identifiers; 90-day maximum | RET-7J-06 … RET-7J-13; DSE-01 … DSE-08 |
| OD-7J-09 | Legal hold and telemetry | Option A: telemetry always expires; required evidence preserved separately | EVP-01 … EVP-16 |
| OD-7J-10 | Terminal behaviour when evidence capture cannot complete before the source expires | Option A: never suspend expiry; record the loss as a preservation failure; the residual is accepted by the owner | EVP-08, EVP-09; RR-7J-06 |
| OD-7J-11 | Partial measurement and error-budget governance | Option A: a window with any unmeasured hour gives no verdict and moves no budget | AOA-21, AOA-24; EB-01, EB-05, EB-11; RR-7J-13 |
| OD-7J-12 | Suspension eligibility for SLI-11 | Option A: whole-delivery exclusion when a non-`ACTIVE` interval is proved to overlap `[occurred_at, occurred_at + B)`; `uncertain` where it cannot be proved | AOA-27; SLI-R-03; SLI-11; M-296; RR-7J-14 |
| OD-7J-13 | Lifecycle-ordering evidence | Option A: a controlled refinement of 7I STP-11 for organization status (transition sequence and post-lock clock), read through one narrow listing function | AOA-27 (b) – (e); ERR-7J-15; IR-7J-48; RR-7J-12 |
| OD-7J-14 | Timing-band uncertainty and the SLI-11 verdict (the reading of OD-7J-13 condition 19) | Option A: strict. Any unresolved `TIMING_BAND` delivery in a cohort of the window prevents a verdict and any budget movement; bounds are diagnostics only | AOA-24; AOA-27 (h); EB-05; RR-7J-15 |
| OD-7J-15 | Minimum lifetime of lifecycle provenance | Option A: bounded minimum, fail closed. [CAND] 45 days from the post-lock observation, for 7K to validate; no indefinite retention; final finite policy through 7L before activation | AOA-27 (g); ERR-7J-15; IR-7J-48; AG-7J-14 |

### 29.2 Decision records

Each record gives the ten points the decision protocol requires. Alternatives are abridged to what distinguished them.

**OD-7J-01 — Status of event-pipeline SLO targets.** (1) Missing: any approved numeric objective for publication, consumption, delivery or recovery. (2) Source and gap: SRS NFR-PERF-001, -002 and NFR-AVAIL-001 are the only approved numbers and concern voice and API; 7A CON-05 declares the 4G §12.2 lag figures indicative. (3) A: candidates until 7K. (4) B: bind the 4G figures now. (5) C: adopt them as internal objectives with budgets from activation. (6) Security and privacy: none directly; invariants must not wait for objectives, which A states. (7) Reliability: B and C start budgets on unmeasured targets. (8) Cost: none for A. (9) Infrastructure: none. (10) Recommended and approved: A.

**OD-7J-02 — Error budget.** (1) Missing: window, burn-rate policy, consequence of exhaustion. (2) No frozen source defines any. (3) A: 28-day rolling with a change freeze. (4) B: 28-day advisory. (5) C: calendar month with freeze. (6) Security and privacy fixes are always exempt. (7) A forces reliability work; B does not; C resets on the first of the month. (8) Delivery speed is constrained only when a budget is exhausted. (9) None. (10) Approved: A.

**OD-7J-03 — Telemetry retention.** (1) Missing: retention of metrics, traces, alert history, incident records. (2) 3F §18.3 fixes logs only. (3) A: 30 days raw plus 13-month SLO aggregates; traces 14 days; alert history 13 months; incidents 2 years. (4) B: one store, 30 days. (5) C: minimal. (6) Less retained telemetry is less exposure; A keeps only identifier-free aggregates long. (7) A allows a 28-day budget to be recomputed and a year compared. (8) A adds a second Prometheus instance. (9) Same product, logically separate, in region. (10) Approved: A. **Difference from the option:** the option offered 30 days for security- or recovery-flagged traces; the approval sets traces at 14 days without exception, and 7J applies 14 days to all traces (SMP-11).

**OD-7J-04 — External alert payload.** (1) Missing: what an alert notification may carry out of region. (2) 3F §17.2 routes to a pager and a chat receiver and groups by `tenant_id`; 7I RSY-11 keeps logs, traces and metrics in region and does not address notifications. (3) A: minimal metadata. (4) B: nothing leaves for enterprise stacks. (5) C: full annotations. (6) C places operational metadata abroad. (7) B slows triage. (8) None material. (9) A needs fixed templates and a build check. (10) Approved: A. **Difference:** the approval adds a content-free tier and an in-region-only tier (conditions 7, 8), which 7J carries as NTF-07 and NTF-08; the in-region mechanism itself is not selected and is gated (AG-7J-09).

**OD-7J-05 — Restricted telemetry access.** (1) Missing: who may query class R telemetry and how it is bounded. (2) 7I RED-06 permits the organization UUID in internal logs and traces and defines no access model. (3) A: tiered, case-bound. (4) B: dual control for every tenant-scoped query. (5) C: all engineers with logging. (6) C is wide exposure; B is strongest. (7) B delays every investigation, including during an outage. (8) A needs a query broker. (9) The broker is a function of the tooling workload 7I already requires. (10) Approved: A.

**OD-7J-06 — Sampling.** (1) Missing: a rate for relay, consumer and dispatcher spans. (2) 3F §19.2 names voice, API and background tasks only. (3) A: 25% plus fault capture. (4) B: 100%. (5) C: 10% plus fault capture. (6) No difference in content rules. (7) No alert depends on a trace under any option. (8) B has the highest span volume. (9) Collector and Tempo sizing to 7K. (10) Approved: A. **Difference:** the approval requires an explicit mechanism for faults discovered after the head decision (condition 5) and an explicit statement of what cannot be reconstructed (condition 6): SMP-05 and SMP-07.

**OD-7J-07 — Paging.** (1) Missing: which classes page at any hour. (2) 3F §17.2 has `critical` and `warning` only. (3) A: integrity, security and privacy page immediately. (4) B: availability and integrity only. (5) C: every critical. (6) B lets an isolation signal or a missed erasure deadline wait. (7) C risks alert fatigue. (8) On-call load. (9) None. (10) Approved: A.

**OD-7J-08 — Erasure and telemetry.** (1) Missing: how a data-subject erasure applies to pseudonymous references in telemetry. (2) 3F §18.3 keeps security logs 2 years cold; neither 4I nor 7I addresses telemetry in an erasure. (3) A: minimize and strip, 90-day maximum. (4) B: active per-subject deletion. (5) C: expiry only. (6) C leaves call-linked references up to 2 years; B is strongest. (7) B needs identifier-scoped deletion in every store. (8) B is the most expensive. (9) A needs a projection at the cold output. (10) Approved: A. **Difference:** the approval's list of what a cold record may keep does not include organization or operator references, which the option kept; 7J follows the approval (RET-7J-06). It also requires an explicit linkability evaluation and a named requirement for per-subject deletion: DSE-02 … DSE-06.

**OD-7J-09 — Legal hold and telemetry.** (1) Missing: whether a hold affects telemetry expiry. (2) 7I designs holds for the content-bearing event stores only. (3) A: no; export scoped evidence to a separately governed record. (4) B: a hold freezes the scoped organization's telemetry. (5) C: a hold freezes all expiry. (6) B and C retain other subjects' references. (7) B needs per-organization separation of telemetry. (8) A adds a small evidence store. (9) A uses a dedicated prefix of the approved object storage. (10) Approved: A. **Difference:** the approval requires original evidence with provenance and chain of custody, not identifiers and codes alone (condition 4): EVP-05.

**OD-7J-10 — Capture that cannot complete in time.** (1) Missing: the terminal behaviour when OD-7J-09 condition 12 (do not lose known-required evidence) meets condition 1 (never freeze expiry). (2) The two conditions cannot both be absolute. (3) A: never freeze; record the loss. (4) B: a dual-controlled 72-hour suspension of one store. (5) C: a hold is not confirmed until the capture is verified. (6) B keeps every tenant's data past retention. (7) C can delay an urgent hold. (8) None material. (9) A needs a second capture path. (10) Approved: A, with the residual accepted (RR-7J-06).

**OD-7J-11 — Partial measurement and error-budget governance.** (1) Missing: whether a 28-day accounted window that contains an unmeasured hour may give a verdict or move a budget. (2) OD-7J-02 condition 5 says blindness is neither healthy nor a breach and does not say how much blindness; the third submission's author had tightened this without asking, and the fourth review required a confirmation. (3) A: no verdict and no budget movement with any unmeasured hour. (4) B: a qualified verdict under a separately approved coverage rule. (5) No third option. (6) None directly. (7) B can report an objective met over a window that lost the hours of an incident; A can leave a freeze unlifted for up to 28 days. (8) None. (9) None. (10) Approved: A, with that consequence explicitly accepted (condition 8).

**OD-7J-12 — Suspension eligibility.** (1) Missing: how a legitimate suspension affects SLI-11, over which interval, and what happens when the timing cannot be proved. (2) 7H holds dispatch for a non-`ACTIVE` organization and still creates rows (FAN-05, OD-7H-02); no frozen source says how a held delivery counts toward a latency indicator. (3) A: whole-delivery exclusion on a proved overlap with the event-to-deadline interval. (4) B: a pause-adjusted, active-time measure. (5) C: never exclude. (6) None; no tenant-derived label under any option. (7) A can exclude a delivery whose earlier delay was the platform's; B changes what SLI-11 and SLO-D1 mean; C reports tenant suspensions as platform misses. (8) B needs interval arithmetic over uncertain edges. (9) None. (10) Approved: A. **Differences from the option:** the approval requires active-time delay to be reported separately where measurable (condition 14), which the option did not offer and 7J meets with the diagnostic M-296; it forbids a pause-adjusted binding objective in V1 (condition 15); and it accepts by name the trade-off that a brief qualifying suspension excludes earlier active-time delay (condition 16).

**OD-7J-13 — Lifecycle-ordering evidence.** (1) Missing: any stored fact that orders an organization's status changes by when they took effect. (2) `072_5J` stores the transaction's start time; `107_5B5` writes only that audit row; 7I STP-11 designs a provenance row with "the time" and no stated clock. (3) A: refine that provenance row for organization status. (4) B: use audit rows as lower bounds only. (5) No third option. (6) A exposes less: the fold reads no audit row. (7) B widens the uncertain band by the length of the lifecycle transaction and infers order by counting. (8) A adds two values to a row 7I already requires. (9) None. (10) Approved: A, as a controlled erratum to be applied by a future governed migration; the frozen 7I document is not edited. **Differences from the option:** the approval states that a sequence number alone never proves a transition happened before a wall-clock deadline (condition 9) and that the post-lock clock is not a commit time (condition 6); 7J had designed bounds for exactly that reason (AOA-27 e). Condition 19 requires that, where temporal classification cannot be provided safely, eligibility stays unknown and definitive reporting is blocked for the affected cohorts. 7J applies it in two tiers and says so here because the reading is the author's: evidence that is missing or untrusted makes the window `NOT_ESTABLISHED` (AOA-27 g); a delivery whose window merely meets a timing band is `uncertain`, bounds the ratio both ways, and blocks a verdict only when the two bounds disagree (AOA-27 h). **That second tier is withdrawn.** The fifth review required the owner's confirmation of it, and the owner chose the strict rule instead (OD-7J-14): bounds are diagnostics and never a verdict.

**OD-7J-14 — Timing-band uncertainty and the verdict.** (1) Missing: an approved reading of OD-7J-13 condition 19 for a window whose cohorts hold `uncertain` deliveries. (2) The author had let a verdict stand when the best-case and worst-case ratios agreed; that was his reading and was not approved. (3) A: strict, no verdict and no budget movement while a relevant timing-band uncertainty remains. (4) B: a verdict when both bounds fall on the same side of the target. (5) No third option. (6) None. (7) Under A each suspension that lands near a deadline can leave SLI-11 without a verdict until its cohort hour leaves the window, up to 28 days; under B a verdict rests on bound arithmetic. (8) None. (9) None. (10) Approved: A, with that consequence recorded by name (condition 13; RR-7J-15). The earlier interpretation is withdrawn.

**OD-7J-15 — Lifetime of lifecycle provenance.** (1) Missing: how long the transition evidence of ERR-7J-15 must stay readable; 7I's retention matrix has no row for it. (2) It is class `PID` in 7I STP-11; it is not telemetry, so OD-7J-03 does not govern it. (3) A: a bounded minimum, fail closed, final period through 7L. (4) B: no period now. (5) C: follow audit retention. (6) C keeps identifier-bearing rows for years; A and B keep the least. (7) Too short a period makes late-registered deliveries `uncertain`; it never makes them wrong. (8) Storage is one small row per transition. (9) None. (10) Approved: A. **Differences from the option:** the 45 days are a candidate minimum for 7K to validate, not a production guarantee (condition 1); the approval states that 45 days is not assumed to cover every recovery or replay case and requires those cases to be evaluated explicitly, which §34.8 does; a longer bounded period, if one proves necessary, returns to the owner with its privacy, cost and reliability implications before it is final; the SLI-11 gate stays closed until the evidence model, the final retention bounds, the PostgreSQL concurrency validation and the reconciliation controls are implemented and verified (condition 18; AG-7J-14). **One reading the author states:** condition 9 (do not silently delete evidence still required for an active, legitimately classifiable obligation) is met by never removing evidence inside the minimum and by making any removal visible (`covered_from`; `EVIDENCE_UNAVAILABLE`; the window state). It is not met by making the Organization context's removal wait for the accounting fold: that would let monitoring delay a retention rule (PRN-01; AOA-10) and would conflict with condition 12.

### 29.3 Matrix — Conditions of each approval, mapped to rules

| Decision | Condition | Rule |
|---|---|---|
| OD-7J-01 | 1 formulas complete | SLI-R-01; §10.2 |
| | 2 preserve approved requirements | SLO-02 |
| | 3 4G indicative | SLO-03 |
| | 4 no invented guarantees | SLO-01, SLO-05 |
| | 5 7K benchmarks | HE-7K-7J-07, -13 |
| | 6 separate objectives | SLO-04; §11.2 classes |
| | 7 provisional alert thresholds | ALR-01 (PROV); SLO-05 |
| | 8 invariants alert independently | SLO-06; ALR-05 |
| | 9 not contractual | SLO-05; EB-12 |
| | 10 measured, estimated, unavailable | SLO-07; SLI-R-04 |
| OD-7J-02 | 1 only after approval and validated measurement | EB-01 |
| | 2 calculation, burn rate, exhaustion, recovery | EB-02 … EB-05, EB-11 |
| | 3 allowed changes | EB-07 |
| | 4 accountable approval and audit trail | EB-08 |
| | 5 blindness is neither healthy nor a breach | EB-05; SLI-R-04 |
| | 6 multi-window burn rate | EB-04 |
| | 7 internal governance versus SLA | EB-12 |
| | 8 no automatic stop of traffic or processing | EB-09 |
| | 9 ownership, authority, scope | EB-10 |
| | 10 durability and privacy controls preserved | EB-09; SLO-06 |
| OD-7J-03 | 1 region-local separate mechanism | RET-7J-01 |
| | 2 bounded dimensions | RET-7J-02 |
| | 3 no identifiers, payloads, credentials | RET-7J-02; LBL-01 |
| | 4 3F log retention preserved | LOG-12; §27.1 |
| | 5 audit retention independent | §14.1; RET-7J-13 |
| | 6 logs and audit are not metrics | §14.1; AUD-7J-06 |
| | 7 isolation, authorization, region | §22.2; RSD-7J-02 |
| | 8 expiry, verification, backups, restore | RET-7J-04, RET-7J-05 |
| | 9 aggregates validated before raw expiry | RET-7J-03 |
| | 10 sizing to 7K | HE-7K-7J-09 |
| OD-7J-04 | 1, 2, 3 never in a notification | NTF-02 |
| | 4 detail in region | NTF-09 |
| | 5 allow-listed server-side templates | NTF-03 |
| | 6 CI rejects unsafe fields | NTF-04; VT-7J-42 |
| | 7 content-free tier | NTF-07 |
| | 8 in-region mechanism | NTF-08; AG-7J-09 |
| | 9 separate authentication | NTF-06 |
| | 10 links | NTF-05 |
| | 11 no interference with processing or audit | NTF-10 |
| | 12 failure, fallback, routing health, escalation | NTF-11, NTF-12; AL-54, AL-55 |
| | 13 errata to 3F §17.2 | NTF-13; ERR-7J-05, ERR-7J-08 |
| | 14 7I residency preserved | NTF-14 |
| OD-7J-05 | 1 aggregate dashboards | T0; §9 |
| | 2 named authentication | TQA-01 |
| | 3 least-privilege roles | TQA-02 |
| | 4 ticket, purpose, bounded scope | TQA-03, TQA-04 |
| | 5, 6 independently protected record without results | TQA-08; AUD-7J-07 |
| | 7 no shared identities, no cross-tenant browsing | TQA-01, TQA-05 |
| | 8 in region | TQA-06 |
| | 9 security records separately authorized | TQA-14; T3 |
| | 10 no tenant access | TQA-13; TFS-01 |
| | 11 no mutation | TQA-07; OBP-07 |
| | 12 7I dual control for material | T4; EVP-11 |
| | 13 session, revocation, emergency, audit failure | TQA-09 … TQA-12 |
| | 14 platform-admin and tenant restrictions preserved | TQA-02 |
| OD-7J-06 | 1 deterministic and consistent | SMP-03; TRC-01 |
| | 2 links and correlation | TRC-03 … TRC-05 |
| | 3 no identifiers as labels | LBL-01 |
| | 4, 5 explicit fault mechanism; tail sampling | SMP-05, SMP-06 |
| | 6 no reconstruction claimed | SMP-07 |
| | 7, 8 independent evidence; no trace-only alert | SMP-08 |
| | 9 voice tracing and audio path | SMP-04; ISO-02 |
| | 10 no personal data in traces | TRC-09 … TRC-11; SMP-10 |
| | 11 propagation, retries, trace-parent, buffering, backpressure | SMP-03; TRC-06, TRC-07, TRC-12; SMP-09 |
| | 12 retention of late-outcome fault traces | SMP-05 (b); SMP-11 |
| | 13 cannot block processing | SMP-09; ISO-01 |
| | 14 cost and volume to 7K | HE-7K-7J-05 |
| | 15 policy is not a capacity guarantee | SMP-02 |
| OD-7J-07 | Critical 1 – 10 | §23.1 SEV1 and SEV2; AL-17, AL-18, AL-19 (1); AL-03, AL-09 (2); AL-30 (3); AL-17, AL-34 (4); AL-38, AL-39, AL-40 (5); AL-41 (6); AL-43a (7); AL-32, AL-33, AL-57 (8); AL-50, AL-54 (9); AL-26 (10) |
| | Warning 1 lag and backlog as tickets | §23.2 CON, EXT at SEV3 |
| | 2 no page for expected denials | ALR-06; SECM-04 |
| | 3 sustained conditions | ALR-03 |
| | 4 integrity, security, privacy always eligible | ALR-05 |
| | 5 deduplication, grouping, inhibition | ALR-07, ALR-08; §23.5 |
| | 6 primary, secondary, escalation, acknowledgement | §23.1 |
| | 7 a page is not self-approval | ALR-12 |
| | 8 minimal metadata | NTF-01 |
| | 9 content-free or in-region | NTF-07, NTF-08 |
| | 10 runbook, evidence source, resolution verification | ALR-10; §24 |
| | 11 routing failure monitored without coupling | AL-54, AL-55; NTF-10 |
| | 12 an alert stops and erases nothing | ALR-09 |
| OD-7J-08 | 1 no content or secrets | LOG-08; TRC-10 |
| | 2 pseudonymous references only where needed, restricted | §13.2 class R; DSE-01 |
| | 3 OD-7J-05 preserved | §22.3 |
| | 4 retention periods | §27.1 |
| | 5 strip before longer-lived tiers | RET-7J-06, RET-7J-08 |
| | 6 90 days is an upper limit | RET-7J-09 |
| | 7 cold records minimized | RET-7J-06 |
| | 8 a UUID is not anonymous | RET-7J-10 |
| | 9 linkability; per-subject deletion named | DSE-02 … DSE-06; IR-7J-39 |
| | 10 automated, idempotent, auditable, recoverable | RET-7J-12, RET-7J-04 |
| | 11 replicas, backups, restore, cross-region | RET-7J-05; RSD-7J-03 |
| | 12, 13 7I contracts and authoritative evidence untouched | RET-7J-13 |
| | 14 no identifiers in SLO aggregates | RET-7J-02 |
| | 15 verification, access, alerts, gates | RET-7J-04; AL-57; AG-7J-12 |
| | 16 no subject lookup | RET-7J-11 |
| | 17 residency | DSE-08; §27.4 |
| | 18 conflicts brought to the owner | DSE-05; AG-7J-10 |
| OD-7J-09 | 1 telemetry keeps expiring | EVP-01 |
| | 2 authorized scoped process before expiry | EVP-02, EVP-03, EVP-08 |
| | 3 only what is necessary | EVP-04 |
| | 4 original evidence, provenance, integrity, custody | EVP-05 |
| | 5, 6 separately governed record with its own controls | EVP-06, EVP-11, EVP-13 |
| | 7 7I dual control preserved | EVP-03, EVP-11 |
| | 8, 9 no unrelated organizations; no whole datasets | EVP-04 |
| | 10 durable record of the capture | EVP-07 |
| | 11 purpose-bound named access | EVP-11 |
| | 12 not deleted before preservation | EVP-08; OD-7J-10 |
| | 13 failure escalated, never claimed as success | EVP-09 |
| | 14 no substitute for durable evidence | EVP-10 |
| | 15 7I hold semantics preserved | EVP-02 |
| | 16 tenant rejection does not release | EVP-12 |
| | 17 safe expiry after release | EVP-13 |
| | 18 residency | EVP-06; RSD-7J-02 |
| | 19 errata | EVP-15; ERR-7J-10, ERR-7J-13 |
| | 20 no new API, provider or product | EVP-06; TFS-01 |
| OD-7J-10 | Prompt capture when preservation becomes required | EVP-08 |
| | Independently authorized secondary capture | EVP-09 |
| | Durable integrity verification | EVP-05, EVP-09 |
| | SEV1 notification when a critical preservation fails | EVP-09 |
| | Legal and privacy escalation | EVP-09 |
| | Explicit record of what was and was not preserved | EVP-05, EVP-09 |
| | A recorded failure does not satisfy a preservation obligation | EVP-09, EVP-10 |
| | No extension of unrelated tenants' telemetry retention | EVP-01, EVP-04, EVP-09 |
| | Residual RR-7J-06 accepted | §34.2 |
| OD-7J-11 | 1 exactly 672 consecutive UTC hours | AOA-21; SLI-R-13 |
| | 2 an unmeasured hour prevents a definitive verdict | AOA-24; EB-05 |
| | 3 `ESTABLISHED_PARTIAL` shows coverage, moves no budget | AOA-24; EB-05 |
| | 4 `UNKNOWN` and `NOT_ESTABLISHED` give no budget verdict | AOA-24; EB-05 |
| | 5 missing observations are never zero failures or success | AOA-12, AOA-21; SLI-R-04 |
| | 6 last established budget and freeze evidence preserved | EB-05, EB-11 |
| | 7 hard-invariant alerts independent of SLO completeness | SLO-06; EB-05 |
| | 8 up to 28 days of affected governance accepted | RR-7J-13 |
| | 9 blindness alerts, recovery ownership, escalation | AL-59, AL-60; RB-17; EB-05 |
| | 10 no binding numeric SLO | SLO-01 |
| OD-7J-12 | 1 interval begins at the event's `occurred_at` | AOA-27 (a) |
| | 2 upper boundary `occurred_at + B` | AOA-27 (a) |
| | 3 suspensions before fan-out and creation included | AOA-27 (a), (f) |
| | 4 a suspension effective after the deadline excuses nothing | AOA-27 (i), (l) |
| | 5 no inference from audit transaction-start times | AOA-27 (b), (d) |
| | 6 authorization and effective order through approved evidence | AOA-27 (c), (d); IR-7J-48 |
| | 7 excluded exactly once from numerator and denominator | AOA-27 (j) |
| | 8 exclusion reported through bounded diagnostics | M-290 `excluded_held`; M-293 |
| | 9 7H uncounted release and hold semantics preserved | AOA-27 (k); EXT-03, EXT-13 |
| | 10 signed corrections before and after finalization | AOA-22; AOA-27 (j) |
| | 11 unproved timing is `uncertain` | AOA-27 (f), (g) |
| | 12 uncertainty creates no misleading verdict | AOA-27 (h); AOA-24; EB-05 |
| | 13 platform delay distinct from authorized suspension | SLI-R-03; §10.5 |
| | 14 active-time delay reported separately where measurable | M-296 |
| | 15 no pause-adjusted binding SLO in V1 | M-296 backs no objective; SLO-D1 unchanged |
| | 16 trade-off of a brief suspension accepted | AOA-27 (l); RR-7J-14 |
| | 17 deterministic tests | VT-7J-111 … VT-7J-132 |
| OD-7J-13 | 1 per-organization increasing sequence | AOA-27 (c); ERR-7J-15 |
| | 2 advanced in the transition's transaction under the row lock | AOA-27 (c); IR-7J-48 |
| | 3 lifecycle functions, proofs, audit, integrity, lock order preserved | ERR-7J-15; IR-7J-48 |
| | 4 no manufacturing, reordering or bypass | AOA-27 (c); VT-7J-131 |
| | 5 database clock read after the lock | AOA-27 (c) |
| | 6 that clock is not the commit time | AOA-27 (b), (e) |
| | 7 precise evidence of when a transition took effect relative to a deadline | AOA-27 (e) |
| | 8 provable interval bounds, no asserted exact timestamp | AOA-27 (e) |
| | 9 sequence alone proves no wall-clock placement | AOA-27 (e) |
| | 10 undecidable side of the deadline is `uncertain` | AOA-27 (f) |
| | 11 7H admission, locking, suspension, reactivation preserved | AOA-27 (k); ERR-7J-15 |
| | 12 observability cannot mutate lifecycle state | AOA-04; AOA-27 (d), (k) |
| | 13 bounded evidence through narrowly authorized functions | AOA-27 (d); IR-7J-48 |
| | 14 no cross-tenant audit `SELECT`; no actor, customer or payload exposure | AOA-27 (d); AOA-04; VT-7J-131 |
| | 15 long transactions, rollback, concurrency, lock waits, restore, incarnation, late-visible audit | §34.7; VT-7J-122 … -125, -128; AOA-14 |
| | 16 append-only, transactionally consistent evidence; migrations reconciled | ERR-7J-15; IR-7J-48; HE-7L-7J-02 |
| | 17 a pre-deadline audit `NOW()` cannot excuse a later commit | §34.7 counterexample A; VT-7J-122 |
| | 18 deterministic concurrency and timing tests | VT-7J-122 … -126, -129, -130 |
| | 19 otherwise unknown eligibility and no definitive reporting | AOA-27 (g), (h); AOA-24; decided strictly by OD-7J-14 |
| | 20 minimum erratum and activation dependency; no change to 001 – 112 | ERR-7J-15; AG-7J-13 |
| OD-7J-14 | 1 full 672 consecutive hours preserved | AOA-21 |
| | 2 unproven suspension timing stays `uncertain` | AOA-27 (f) |
| | 3 never auto-classified active or held | AOA-27 (f), (g) |
| | 4 no definitive verdict while timing-band uncertainty remains | AOA-24; AOA-27 (h) |
| | 5 no budget exhausted or cleared on an uncertain window | EB-05 |
| | 6 last established governance state preserved | EB-05; EB-11 |
| | 7 verified counts, uncertain counts, ratio and bounds reported as diagnostics | M-290; AOA-27 (h); dashboard I |
| | 8 no bound authorizes a verdict | AOA-27 (h); EB-05 |
| | 9 zero eligible, all-held, zero denominators | AOA-27 (h); AOA-26 (f); EB-05; VT-7J-143 |
| | 10 missing or untrusted evidence stays `NOT_ESTABLISHED` or `UNKNOWN` | AOA-27 (g); AOA-24 |
| | 11 security, privacy, integrity and blindness alerts operational | SLO-06; EB-05; AL-59, AL-60 |
| | 12 OD-7J-11 … OD-7J-13 not weakened | §29; AOA-24, AOA-27 |
| | 13 consequence recorded | RR-7J-15 |
| | 14 no new binding numeric SLO | SLO-01 |
| OD-7J-15 | 1 45 days from the post-lock observation, as a candidate | IR-7J-48; HE-7K-7J-14 |
| | 2 7K evaluates finalization, late registration, recovery, outages, corrections, restore | HE-7K-7J-14 |
| | 3 7L reconciles the final policy with 7I | HE-7L-7J-07 |
| | 4 sequence, post-lock observation, visibility evidence, minimum information kept | AOA-27 (c), (e); IR-7J-48 |
| | 5 authoritative, immutable, tenant-safe, restricted | ERR-7J-15; AOA-27 (c), (d) |
| | 6 no stored time is a commit timestamp | AOA-27 (b), (e) |
| | 7 the R13 snapshot and visibility protocol preserved | AOA-27 (d), (e) |
| | 8 retention for late observations and unresolved deliveries defined | §34.8 (lifetime analysis); IR-7J-48 |
| | 9 no silent deletion of evidence still required | IR-7J-48; AOA-27 (g) (reading stated in §29.2) |
| | 10 nothing inferred from absence | AOA-27 (g) |
| | 11 such classifications `uncertain`, no verdict | AOA-27 (g), (h); AOA-24 |
| | 12 no indefinite retention by default | IR-7J-48 |
| | 13 finite final policy, erasure, backup and restore, preservation exceptions before activation | AG-7J-14; HE-7L-7J-07 |
| | 14 in region; restricted to authorized functions | AOA-27 (d); §27.4 |
| | 15 no organization, lifecycle-event or actor identifier as a label | LBL-01; AOA-03 |
| | 16 7I lifecycle authorization, audit, minimization preserved | ERR-7J-15 |
| | 17 governed migration requirement, no migration 113 | IR-7J-48 |
| | 18 SLI-11 gate closed until verified | AG-7J-14 |

### 29.4 Decisions inherited from frozen sources, and therefore not raised

| Subject | Frozen by |
|---|---|
| Telemetry of an `INDIA_ENTERPRISE` organization stays in region | 4I §9.1; 7I RSY-11 |
| Log retention by class | 3F §18.3 |
| Sampling for voice, API and background tasks; Collector tail sampling | 3F §19.2; 6A §25 |
| No tenant identifier in a metric label | 7A TEN-05; 7H OBS-7H-01; 7I RED-07; 6J §44 |
| Redaction rules for logs, traces, metrics, diagnostics | 7I RED-01 … RED-12 |
| Tenant-visible failure detail | 7I OD-7I-08 |
| Dual control for recovery, material view and sealed inspection | 7I OD-7I-05, OD-7I-07, SEAL-08 |
| Journal outage: wait and alert | 7I OD-7I-16 |
| Stack: OpenTelemetry, Prometheus, Grafana, Tempo, `structlog`, Alertmanager | 3E §14; 3F §17 – §19 |

---

## 30. Controlled Errata and Conflict Register

No frozen document was edited. Each erratum is the smallest statement needed and names the owner who may consolidate it, through 7L.

### 30.1 Conflicts

| ID | Sources | Conflict | 7J resolution |
|---|---|---|---|
| CNF-7J-01 | 7D §41.2 versus 7D §43.5 (HO-7J-01) and IO-7D-18 | §41.2 defines OBS-7D-01 … -18; the handoff and the obligation say "… -17" | All eighteen are covered (§4.2). The handoff wording is ERR-7J-09 |
| CNF-7J-02 | 3E §14.2, 6A §25 versus 7A TEN-05, 7H OBS-7H-01, 7I RED-07, 6J §44 | `tenant_id`, `agent_id`, `campaign_id`, `plugin_id` as metric labels | The later, stricter rule governs the event plane; no such label is adopted (LBL-01). ERR-7J-01, ERR-7J-02 |
| CNF-7J-03 | 3E §14.2, 6A §25, 6J §44.2 versus MN-05 | `webhook_delivery_success_rate` as an emitted metric | Recording rule instead (§7.4) |
| CNF-7J-04 | 7I HE-7J-7I-09, -14 ("by identity", "by organization") versus 7I RED-07 | A per-organization or per-identity breakdown cannot be a label | Counts of organizations or identities in a state; the identity is in the security-class record (LBL-04) |
| CNF-7J-05 | 7D OBS-7D-C1 ("unless 7J explicitly permits") | Leaves open whether 7J may permit a tenant label | 7J permits none (LBL-01) |
| CNF-7J-06 | 3F §19.1 Collector `redaction` (`allow_all_keys: true`) versus 7I RED-05 | Deny-list versus allow-list | Allow-list for event-plane spans (TRC-09). ERR-7J-07 |
| CNF-7J-07 | 3F §17.2 (`group_by` `tenant_id`; free annotations) versus LBL-10, OD-7J-04 | Alert grouping and payload | ERR-7J-05, ERR-7J-08 |
| CNF-7J-08 | 3F §18.1, §18.2 name one cloud provider's log service and a region variable; 4I §9.2 forbids region names in domain code | Infrastructure configuration, not domain code; no conflict of substance | 7J refers to "the log service" and to `region_class` only |
| CNF-7J-09 | 3E §14.1 mandatory span attribute `tenant.id` versus 7I RED-06 | Consistent; RED-06 adds the forms `platform` and `untrusted` | TRC attribute table follows RED-06 |
| CNF-7J-10 | 7E ENT-05 ("`transport_ref` is never persisted") versus 7I ACC-13 | Already resolved by 7I as ERR-7I-13 | 7J follows 7I; `transport_ref` is class R in telemetry |
| CNF-7J-11 | 3F §18.3 (security class 2 years cold) versus OD-7J-08 | 2 years of records, but without linkable references | Retention unchanged; cold content projected (RET-7J-06). ERR-7J-11 |
| CNF-7J-12 | 7I Matrix 6 (Redis users) has no observer | A payload-free observer user is added | ERR-7J-06 |
| CNF-7J-13 | 6J §44.2 (`platform_webhook_delivery_attempts_total{attempt_number}`) versus 7H DSM-05, DSM-07 H5, H6, T-09 | 6J gives the attempt counter one label, `attempt_number`. 7H later fixed that a closure may spend no attempt and then has no attempt number, and that a closure has one of three send states | M-128 counts counted closures by category, origin and send state; M-163 carries the attempt number; M-164 counts uncounted releases (§19.2). ERR-7J-14 |
| CNF-7J-14 | 7H HTP-14, HTP-19 | A failure origin is fixed in the cited text for the HTP-19 categories; none is printed for `CLAIM_EXPIRED` | The closure class is decided by the category for `CLAIM_EXPIRED` and by the recorded origin otherwise (CLO-02). 7J invents no origin value |
| CNF-7J-15 | 7H §19.3 ("fan-out lag (commit time − `occurred_at`)") versus `063_5I` | The delivery row has no `occurred_at` column | Fan-out lag reads `occurred_at` from the outbox row by `event_id`; where that row is gone the observation is counted as unmeasurable (§6.4). The envelope inside `payload_json` is never read for it |
| CNF-7J-16 | 7F §36.4 ("time from delivery to durable commit and to acknowledgement") versus 4G §12.2 and SLO-C1 … C3 (event to effect) | The 7F signal is handler execution; the 4G figures are end to end | Both exist and are named apart: M-068 (SLI-04) and M-085 (SLI-17) (§10.3) |
| CNF-7J-17 | 7I ACC-06 (an outbox row is deletable when every owed group has an accounting row **or a recovery case**) and 7G §18.1 (a case holds no `occurred_at`) versus 7A OBS-04, 7D OBS-7D-13 (event age and latency are measured from `occurred_at`) | After cleanup, an unresolved obligation has no surviving record of its original event time in any frozen relation | No frozen rule is changed. The accounting obligation record copies `occurred_at` from the outbox row at registration and keeps it while the obligation is open (AOA-19). Where registration was missed the obligation is counted from the ledger and its latency is declared unmeasured (RR-7J-09) |
| CNF-7J-18 | 7B OCC-01 … OCC-04 (the `occurred_at` of EV-079 is the service-end time, not the insertion time) versus event-time cohort finalization | An event can legitimately be inserted with an origin time in an already final cohort hour | Treated as a counted post-final correction (AOA-22); `occurred_at` stays the semantic time, as 7A OBS-04 and 7D OBS-7D-13 define it. 7J adds no insertion timestamp to the outbox |
| CNF-7J-19 | 7H TEN-7H-08 (the residual window is evidenced by comparing `admitted_at` and `closed_at` with "the organization audit event's time") and `072_5J` (`occurred_at` defaults to `NOW()` and the insert function never supplies it, so it is the start of the status-changing transaction) versus 7H ADM-02 and ADM-05 (decisions are ordered by the organization row lock, and the guarantees are stated against the commit `t_s`) | The stored audit time precedes the lock, the update and the commit by an unbounded amount, and two transitions' audit times can be in the reverse of their commit order. No frozen relation records the commit or a post-lock time | No frozen rule is changed and no frozen SQL is edited. 7J reads no audit time as a status time. Order and bounds come from the refinement of 7I STP-11 approved in OD-7J-13 (ERR-7J-15; AOA-27). TEN-7H-08 stays true as a description of evidence for a human reader; 7J does not rely on it for classification |

### 30.2 Errata

| ID | Frozen text | Controlled erratum | Owner |
|---|---|---|---|
| ERR-7J-01 | 3E §14.2, 6A §25: `platform_http_requests_total{…,tenant_id}`; `platform_active_calls{tenant_id,agent_id}`; voice metrics with `tenant_id` | A tenant or entity identifier is not a metric label. Outside 7J's scope to correct; recorded so the label is not propagated | 3E, 6A owners via 7L |
| ERR-7J-02 | 3E §14.2: `webhook_delivery_success_rate{tenant_id}`, `plugin_invocation_duration_seconds{plugin_id,tenant_id}`, `campaign_*{tenant_id,campaign_id}` | Superseded for the event plane by §7.4 | 3E owner via 7L |
| ERR-7J-03 | 6J §44: Gauges named `…_total` | Emitted without `_total` (§7.4) | 6J owner via 7L |
| ERR-7J-04 | 6J §44.3: `platform_plugin_installations_by_version{plugin_key,semver}` | Not a metric; a table query | 6J owner via 7L |
| ERR-7J-05 | 3F §17.2: `group_by: [alertname, tenant_id, service]` | `[alertname, region_class, component]` for event-plane alerts | 3F owner via 7L |
| ERR-7J-06 | 7I §9.2 Matrix 6 | One additional Redis ACL user, the state observer, with the command set of OBP-04, in the parity digest | 7I owner via 7L |
| ERR-7J-07 | 3F §19.1 Collector configuration example | Attribute allow-list for event-plane services | 3F owner via 7L |
| ERR-7J-08 | 3F §17.2 receiver configuration | Fixed allow-listed templates; tiers of NTF-07, NTF-08 | 3F owner via 7L |
| ERR-7J-09 | 7D §43.5 HO-7J-01; IO-7D-18: "OBS-7D-01 … OBS-7D-17" | Read as "… OBS-7D-18" | 7D owner via 7L |
| ERR-7J-10 | 5J §14.3 audit vocabulary | Proposed kinds: `TELEMETRY_RESTRICTED_ACCESS_GRANTED`, `_DENIED`; `TELEMETRY_RETENTION_VERIFIED`; `TELEMETRY_EVIDENCE_PRESERVED`, `_PRESERVATION_FAILED`, `_ACCESSED`, `_EXPIRED`. `action_kind` is open text, so no migration is needed for the names (as 7I §19.4 notes); the platform-event caller list change is 7I IR-15 | 5J owner via 7L |
| ERR-7J-11 | 3F §18.3: security-relevant logs, 2 years cold | The cold copy is the minimized projection of RET-7J-06 | 3F owner via 7L |
| ERR-7J-12 | 3F §19.2 sampling classes | Adds the class "event-pipeline hops: 25% baseline, deterministic per event, with the fault set always sampled" | 3F owner via 7L |
| ERR-7J-13 | 7I §12.1 key hierarchy | Adds the key purpose `PRESERVED_EVIDENCE`, per region, with decrypt held by the evidence function alone | 7I owner via 7L |
| ERR-7J-14 | 6J §44.2: `platform_webhook_delivery_attempts_total{attempt_number}` | Read as: counted closures, labelled `category`, `origin`, `send_state`; the attempt-number breakdown is `platform_webhook_attempts_by_number_total` | 6J owner via 7L |
| ERR-7J-15 | 7I STP-11 ("…from-state and to-state, cause, … `session_user` and the time") and OLC-06, OLC-09, OLC-13, OEA-16, as they apply to `organization.organizations.status` | The provenance row of an organization status transition additionally carries (a) a transition sequence, per organization, increasing by exactly one, assigned after the organization row lock is held, unique per (organization, sequence); (b) `locked_at`, `clock_timestamp()` read after that lock is held. Every path that 7I lets change the status writes it, the restore-only function of OEA-16 included. One Organization-owned `SECURITY DEFINER`, `VOLATILE` listing function, to the accounting folds' owner role only: it reads the clock as its cutoff, then in one query returns the organization's baseline and the bounded set of retained transitions of AOA-27 (d) (sequence, state codes, `locked_at`, an opaque row reference), with the current status for a consistency check only, and it refuses to run unless the isolation level is `READ COMMITTED` (AOA-27 d, e). One baseline per organization (`base_seq`, `base_state`, `covered_from`), written as sequence 0 under the row lock and advanced only by the Organization context's guarded maintenance function, which takes the organization row's share lock, confirms the latest transition, and removes a prefix only when the instant that proves the last removed transition had taken effect is older than [CAND] 45 days (AOA-27 c). The baseline is a status code, a sequence number and an instant; it is not a provenance row and carries no cause, actor, proof, session or key. The final, finite lifetime of the transition rows is set through 7L (OD-7J-15). Nothing else changes: the lifecycle functions' authorization, proofs, statements, audit rows, lock order (OLC-13) and 7H ADM-01 … ADM-07 are as frozen; no migration `001` – `112` is edited; the audit relation is not touched. Approved by OD-7J-13 as a future governed compatibility erratum | 7I and Organization (5B) owners via 7L |

---

## 31. Future Implementation Requirements

Nothing below is implemented. No migration is written by this phase; "governed migration" means a future, separately reviewed migration, not migration 113 of this baseline.

| ID | Class | Component | Existing contract | New telemetry requirement | Enforcement or emission point | Owner | Verification | Gate |
|---|---|---|---|---|---|---|---|---|
| IR-7J-01 | Application instrumentation | Metric registry module | 3E §14.2 (one registration module) | Register every §8 metric with type, unit, labels and closed sets | `platform/infrastructure/observability/metrics.py` | Platform | VT-7J-03, -13 | AG-7J-01 |
| IR-7J-02 | Application instrumentation | Instrumentation wrapper | D0 logging | Counter, histogram, span and log helpers that swallow their own errors (ISO-03) and accept only allow-listed fields | Shared library | Platform | VT-7J-15, -48 | AG-7J-01 |
| IR-7J-03 | Application instrumentation | Tracing | 3E §14.1 | Event trace derivation (TRC-01); anchor span; link rules; deterministic sampler; hop-local fault buffer; forward marking | SDK configuration and wrapper | Platform | VT-7J-20 … -27 | AG-7J-01 |
| IR-7J-04 | Security scan | Build checks | — | Label allow-list and deny patterns (LBL-07); notification templates (NTF-04); exporter destinations (RSD-7J-04); recording-rule labels (RET-7J-02) | CI | Platform | VT-7J-13, -42, -50, -55 | AG-7J-01 |
| IR-7J-05 | Application instrumentation | Relay and adapter | 7D §41; 7E §49.4 | M-003 … M-016, M-034 … M-038, M-051, M-052 at the stated boundaries | Relay; adapter | Platform | VT-7J-01, -02, -23, -38 | AG-7J-03 |
| IR-7J-06 | Application instrumentation | Consumers | 7F §36.4 | M-060 … M-084 | Consumer pipeline | Platform; contexts | VT-7J-07, -10 | AG-7J-05 |
| IR-7J-07 | Application instrumentation | Gateway and reconciler | 7I §9.5 – §9.7 | M-067, M-100, M-200 … M-208; `ack_without_accounting` rule | Gateway; reconciler | Platform | VT-7J-28, -46 | AG-7J-05 |
| IR-7J-08 | Application instrumentation | Recovery tooling | 7G §52.3 | M-090 … M-115, M-170 … M-172, counted after the audit commit | Tooling; sweep | Event operations | VT-7J-11, -12, -47 | AG-7J-05 |
| IR-7J-09 | Application instrumentation | External delivery | 7H §19 | M-120 … M-160 | Fan-out, dispatcher, sweeper, ingress, executor | Integrations | VT-7J-09, -16 | AG-7J-07 |
| IR-7J-10 | Database-derived metrics | Observer functions | — (no function exists; `app_readonly` must not be used, OBP-03) | Aggregate-only `SECURITY DEFINER` functions per evidence source, with supporting partial indexes, and the observer principal with `EXECUTE` on them only | **Governed migration** | Platform; 5J, 5I owners | VT-7J-06, -31, -32 | AG-7J-02 |
| IR-7J-11 | Database-derived metrics | Invariant queries | 7I HE-7J-7I-11 … -13 | The fixed invariant list of M-220 as observer functions | Governed migration | Security | VT-7J-28 | AG-7J-05 |
| IR-7J-12 | Database-derived metrics | Privacy state | 7I §14 | Observer functions over step tables, deadlines, holds, decisions, sealing, index and certification state, returning counts only | Governed migration (with 7I IR-21 … IR-53 as they land) | Privacy and security | VT-7J-18, -39 | AG-7J-08 |
| IR-7J-13 | Redis probes | Observer ACL user | 7I Matrix 6 | Payload-free user (OBP-04); subcommand scoping verified, else the OBP-05 fallback | Governed ACL provisioning | Platform | VT-7J-33 | AG-7J-02 |
| IR-7J-14 | Redis probes | Trim worker and provisioning | 7E TRM, TTL | M-045 … M-050 | Trim worker | Platform | VT-7J-36 | AG-7J-03 |
| IR-7J-15 | Exporter configuration | State observer | — | Two replicas; evidence freshness and failure export (EVD-01, EVD-02); bounded queries; region tag check | Observer workload | SRE | VT-7J-04, -06 | AG-7J-02 |
| IR-7J-16 | Exporter configuration | Prometheus | 3F §17 | Scrape with sample and label limits; `absent()` rules; SLO-history instance with `slo:` federation only | Configuration as code | SRE | VT-7J-40, -55 | AG-7J-01 |
| IR-7J-17 | Exporter configuration | Collector | 3F §19.1 | Attribute allow-list; tail sampling; shed order by `sampling.reason`; bounded queues | Configuration as code | SRE | VT-7J-27 | AG-7J-01 |
| IR-7J-18 | Exporter configuration | Log pipeline | 3F §18 | Routing by `sink_class`; separate security log group and credentials; **cold security projection** (RET-7J-06); node masking counters | Fluent Bit configuration | SRE | VT-7J-54 | AG-7J-12 |
| IR-7J-19 | Dashboard configuration | Dashboards A – I | 3E §14.3 | As §22.1, with freshness on every state panel | Files as code | SRE | Review against §22.1 | AG-7J-01 |
| IR-7J-20 | Alert evaluation | Rules | 3E §14.4 | The rulebook of §23.4 with status tags; inhibition of §23.5; rule unit tests | Rule files as code | SRE | VT-7J-08, -41, -44 | AG-7J-01 |
| IR-7J-21 | Alert evaluation | Notification | 3F §17.2 | Fixed templates; tier configuration; synthetic alert; dead-man heartbeat | Alertmanager configuration | SRE | VT-7J-40, -42 | AG-7J-01 |
| IR-7J-22 | Access-control configuration | Restricted query broker | 7I §7.3 tooling (IR-10) | TQA-01 … TQA-16 | Event-operations tooling | Event operations; security | VT-7J-29, -30 | AG-7J-06 |
| IR-7J-23 | Access-control configuration | Roles and store credentials | — | `telemetry.restricted.read`, `telemetry.security.read`; network policy closing direct store access | Identity provider; network policy | Security | VT-7J-30 | AG-7J-06 |
| IR-7J-24 | Audit dependencies | Audit caller list and vocabulary | 7I IR-15; ERR-7I-06 | Tooling principal may record the kinds of ERR-7J-10 | Governed migration (7I's) | 5J owner | VT-7J-30, -47 | AG-7J-06 |
| IR-7J-25 | Security scan | Sink scanner | 3F §18.3 masking | SCN-01 … SCN-07 | Scheduled in-region job | Security | VT-7J-19 | AG-7J-06 |
| IR-7J-26 | Security scan | Infrastructure log watchers | 7I RDS-11, JRN-18 | Break-glass, journal-prefix, key-service audit and network-deny watchers emitting M-176, M-214, M-186, M-177 | In-region jobs | Security | VT-7J-28 | AG-7J-05; AG-7J-08 |
| IR-7J-27 | Application instrumentation | Connection-pool hook | 7I §6.2 tenant-context sequence | M-182, M-183 at checkout and check-in | Database session factory | Platform | VT-7J-28 | AG-7J-05 |
| IR-7J-28 | Application instrumentation | Database error classifier | 7I HE-7J-7I-11 … -13 | Map `42501` and guarded-function refusals to closed classes (M-219, M-221, M-222) without recording object names | Database client wrapper | Platform | VT-7J-28 | AG-7J-05 |
| IR-7J-29 | Application instrumentation | Privacy components | 7I §14 | M-173, M-210 … M-218, M-234, M-243 … M-262 at the stated boundaries | Journal writer; retention pass; sealing; guard; certification | Privacy and security | VT-7J-18, -39 | AG-7J-08 |
| IR-7J-30 | Application instrumentation | Voice finalization | 7B IO-7B-15, -16, -21 | M-146 … M-148 | Finalization worker; reaper | Voice | VT-7J-34 | AG-7J-04 |
| IR-7J-31 | Deployment dependencies | Region tags and destination list | 7I RSY-02 | Telemetry workloads carry and check the region tag; governed destination list with drift check | Deployment | SRE | VT-7J-50 | AG-7J-01 |
| IR-7J-32 | Deployment dependencies | Retention verification | — | Weekly verification with an audit event (RET-7J-04); restore procedure of RET-7J-05 | In-region job | SRE | VT-7J-53, -60 | AG-7J-12 |
| IR-7J-33 | Capacity benchmarks | All of §26 | — | Measurements HE-7K-7J-01 … -13 | 7K | 7K | 7K | Before any PROV threshold or objective is confirmed |
| IR-7J-34 | Alert evaluation | SLO recording rules and reports | — | `slo:` rules of §10; evidence-class labelling (SLO-07); unmeasured time (SLI-R-04) | Rule files | SRE | VT-7J-43, -45, -51 | AG-7J-01 |
| IR-7J-35 | Access-control configuration | Incident tool template | — | No identifier fields (RET-7J-08) | Incident tracker configuration | SRE | Review | AG-7J-12 |
| IR-7J-36 | Deployment dependencies | In-region notification mechanism | — | **Not selected.** Needs the owner's approval of a mechanism (NTF-08) | — | Platform owner | — | AG-7J-09 |
| IR-7J-37 | Deployment dependencies | Network-policy deny log; origin check | 7I HE-7J-7I-04 | Sources for M-177 and M-180 | 7K (HE-7K-7I-04, HE-7K-7I-07) | 7K | — | Blocks only those two metrics |
| IR-7J-38 | Audit dependencies | Owning-context erasure | 7I HLD-14; HE-7L-7I-11 | Each context's erasure severs or anonymizes the resource-to-subject mapping (DSE-04) | 5C – 5G owners | 5C – 5G owners | VT-7J-56 | AG-7J-10 |
| IR-7J-39 | Deployment dependencies | Accelerated per-subject telemetry purge | — | **Not designed, not approved.** Named so it cannot be assumed to exist (DSE-06) | — | Platform owner | — | Only by a new owner decision |
| IR-7J-40 | Access-control configuration | Evidence function and prefix | 7I JRN-01 pattern (dedicated prefix, own credentials and key) | EVP-01 … EVP-16; key purpose `PRESERVED_EVIDENCE`; second capture path | Event-operations tooling; object storage | Security | VT-7J-57 … -59, -61 | AG-7J-11 |
| IR-7J-41 | Database-derived metrics | Observation accounting: obligation records, event-time cohorts and the hour ledger | — (nothing exists; no index on `published_at`; the 7H history records, the 7I completion, accounting and position records and the 7G ledger are themselves future) | Per stream of §6.4 (eight): the obligation record keyed by (stream, identity) holding `origin_at`, cohort hour, dimension codes and, once closed, `closed_at`, class and latency bucket, and nothing else (AOA-03); for `webhook_first_closure` also `created_at`, `decide_by`, `eligibility` and its evidence code, with the single settlement into one of three classes, its basis and `t_e`, and its count move (AOA-27); the sighting of each lifecycle transition, keyed by an opaque row reference; the three milestone streams with one record each (AOA-28). The hour ledger with one row per stream and UTC hour, in-order finalization and immutable final rows; append-only unmeasured declarations; hourly totals; immutable final rows; append-only signed correction entries with provenance; unattributed counts; the run record with incarnation (AOA-26). The guarded fold functions (register, evaluate eligibility, close, declare, finalize; routine and completeness), which obtain lifecycle evidence only through the listing function of IR-7J-48, read no audit row, and write no relation outside accounting (AOA-04, AOA-27 d); the incarnation check of 7I JRN-12 in every fold; supporting indexes; purge of closed records under AOA-23 by the maintenance principal. `EXECUTE` for the observer principal only; no login role has any table privilege | **Governed migration** | Platform; 5J, 5I, 7G, 7H, 7I owners for the source relations | VT-7J-63 … -66, -83 … -89, -92 … -160 | AG-7J-13 |
| IR-7J-42 | Alert evaluation | Expected registry | — | The code-owned registry of expected sources, (component, group) pairs, shards and **accounting streams with each fold kind and its permitted age**, with states `EXPECTED`, `DISABLED` (reason, expiry) and removal by governed change, and its generator of constant recording rules (EVD-08 … EVD-13); registry changes audited | Rule files generated at build | SRE | VT-7J-67, -68, -90 | AG-7J-01 |
| IR-7J-43 | Application instrumentation | Webhook claim, admission and closure taxonomy | 7H §8, DSM-07, MR-7H-06 | M-128, M-133, M-135, M-137, M-161 … M-164, M-169 at the stated boundaries; the one code-owned closure-class table of §19.2 used by both the dispatcher and the database fold; `send_state` with three values | Dispatcher; sweeper | Integrations | VT-7J-76, -77, -79 … -81 | AG-7J-07 |
| IR-7J-44 | Application instrumentation | Callback acknowledgement basis | 7H CBK rules | M-149 at the point the response is returned, with the basis fixed by the code path | Ingress | Voice; Integrations | VT-7J-78 | AG-7J-07 |
| IR-7J-45 | Database-derived metrics | Censoring and cohort figures | 7I ACC-03 (payload-free listing) | Observer functions for M-022, M-086, M-116, M-145: counts by closed dimension only. The M-145 function reads the current organization status of each open record's delivery inside the function and returns no organization | Governed migration (with IR-7J-10) | Platform | VT-7J-72, -74, -75, -121 | AG-7J-02 |
| IR-7J-46 | Security scan | Query and rule build checks | — | Reject: `sum` over observer `instance`; a bare `absent()` on a labelled metric; an inhibition rule outside the closed list of STM-05; an `slo:` rule that uses `rate` or `increase` for a reported window total (AOA-15) | CI | SRE | VT-7J-63, -67, -82 | AG-7J-01 |
| IR-7J-47 | Database-derived metrics | Window and state read functions | — | The read function of AOA-26 (f): per accounted indicator and bounded scope the window end, the 672 hours split into measured and unmeasured, the sums over measured hours, the signed corrections, `excluded_held`, the two `uncertain` counts, the unattributed count and the state of AOA-24 (including `ESTABLISHED_UNCERTAIN` for a timing band and `NOT_ESTABLISHED` for an evidence fault), with absent values and never `NaN` for a zero denominator, with its own consistency check; the finalization watermark; the latest final cohort hour's figures and measurement; and the unresolved-obligation figure M-086 as the union of open obligation records and non-terminal `CONSUMER` ledger cases without one. Counts and closed codes only; no identifier, no cohort hour as a dimension | **Governed migration** (with IR-7J-41) | Platform | VT-7J-83 … -85, -87, -89, -91 … -99, -127, -130, -143 | AG-7J-13 |
| IR-7J-48 | Lifecycle evidence (Organization context) | Transition sequence, post-lock clock and the listing function | — (none exists. Installed today: `107_5B5`, which writes only the audit row, dated at transaction start by `072_5J`; the tenant edges are a plain compare-and-swap `UPDATE` by `app_api`, 6C §7.6. The superseding lifecycle functions and the provenance row of 7I OLC-06 … OLC-11 and STP-11 are designed and not built) | ERR-7J-15, in the same governed migration that builds the 7I lifecycle functions: the two values on the provenance row; the unique (organization, sequence) constraint; the listing function with `EXECUTE` for the accounting folds' owner only and a fixed, closed return shape, built as AOA-27 (d) requires (`VOLATILE`; cutoff assigned before the one evidence query; raises unless `READ COMMITTED`), with a catalogue assertion that neither it nor a fold is `STABLE` or `IMMUTABLE`; **baseline, confirmation and removal** as AOA-27 (c) specifies: one baseline per organization (`base_seq`, `base_state`, `covered_from`), first written as sequence 0; the confirmation of the latest transition; prefix removal only when the proving instant `u_k` is older than the evidence lifetime, which is [CAND] 45 days (OD-7J-15) and equals the life of the accounting hourly rows that could still use the evidence (AOA-23); deletion and baseline update in one transaction under the organization row's share lock, taken with `SKIP LOCKED` and as the first lock of that transaction, so 7H ADM-04's lock order holds; `covered_from` monotone; the sequence continuing from its last value. 7J asks for nothing longer and sets no maximum. Removal is by the Organization context's own governed maintenance function under the final finite policy that 7L reconciles with 7I; it never waits for the accounting fold and is never silent, because the listing reports the baseline and M-284 shows an unsettled record nearing the lifetime. **The status before the retained transitions is given by the baseline and by nothing else**; the organization's current status is returned for a consistency check and is never used as a past status; erasure, backup, restore and any authorized preservation of these rows follow 7I's rules for `PID`-class evidence and are 7I's to state; no grant to the observer principal or to any login role; no change to any function's authorization, statements or lock order. For every organization that exists when it is installed, the migration writes the sequence-0 baseline under that organization's row lock, with the status it reads there, `ACTIVE` or not, and the post-lock clock as `covered_from`; nothing earlier is reconstructed, and a window that begins before that instant is `EVIDENCE_UNAVAILABLE` (AOA-27 g). An organization created later receives its baseline in its creation transaction, through the 7I creation path or an insert trigger, as the migration chooses; the sequence's last value is kept with the baseline and is advanced only under the row's exclusive lock | **Governed migration** (Organization, with 7I) | Organization (5B); 7I owner; Platform | VT-7J-122 … -126, -129, -131 … -142, -144 … -160 | AG-7J-13, AG-7J-14 |

---

## 32. Activation Gates

A gate names telemetry that must be operational **in addition to** the frozen gates of 7F §35, 7G §56, 7H §17.5 and 7I §24. It never replaces them. **A missing piece of telemetry is never a reason to bypass a durability or security gate, and passing a telemetry gate never opens a frozen one.**

| Gate | Blocks | Until |
|---|---|---|
| AG-7J-01 | Production activation of any event-plane component | The registry, wrappers, build checks, Prometheus with limits and `absent()` rules, the SLO-history instance, the Collector allow-list, the rulebook with inhibition, the notification templates and tier, the dead-man heartbeat, the destination list with its drift check, and dashboards A and I exist (IR-7J-01 … -04, -16, -17, -19 … -21, -31, -34); the expected registry with its generated rules and the query build checks exist (IR-7J-42, IR-7J-46); VT-7J-03, -08, -13 … -15, -17, -20, -21, -27, -40 … -44, -48 … -52, -67, -68, -82, -90 pass |
| AG-7J-02 | Emission of any database- or Redis-derived metric, and therefore every component whose Tier C set includes one | The observer functions, principal and ACL user exist (IR-7J-10, -13, -15); no telemetry component uses `app_readonly`, `app_worker`, `app_api` or `app_platform_admin`; VT-7J-06, -31 … -33 pass |
| AG-7J-03 | Production operation of the relay and the SIGNAL publisher (with 7I AB-7I-01, AB-7I-02) | Tier C metrics of §8.1 – §8.3 emitted and scraped; AL-01 … AL-14 wired; dashboards B and C; per-shard durability rules and the expected-shard registry in force; VT-7J-01, -02, -04, -05, -23, -35, -38, -69, -70 pass; AG-7J-13 open for M-017 |
| AG-7J-04 | Activation of the Voice accounting-finalization worker and reaper | IO-7B-15 and IO-7B-16 exist; M-146 … M-148 and AL-46; VT-7J-34 passes |
| AG-7J-05 | Activation of any durable consumer group, the stream gateway and any recovery operation (with 7I AB-7I-03, -04, -10, -11) | Tier C metrics of §8.4 – §8.8 and the security set of §8.13 emitted; AL-15 … AL-22, AL-30, AL-31, AL-33 … AL-35, AL-37, AL-38, AL-47, AL-48 wired; dashboards D, E, G; VT-7J-07, -10 … -12, -22, -24 … -26, -28, -36, -37, -46, -47, -71 … -74 pass; AG-7J-13 open for M-085 |
| AG-7J-06 | Any query of class R telemetry by any person; activation of dashboards G and H for use | The broker, the roles, the audit kinds and the scanner exist (IR-7J-22 … -25); VT-7J-19, -29, -30 pass. Until then class R fields are written and not queryable |
| AG-7J-07 | Webhook fan-out and dispatch, callback routes, plugin callouts (with 7H AB-7H-01 … -06; 7I AB-7I-05, -06, -15) | Tier C metrics of §8.9 – §8.11; AL-23 … AL-29, AL-32, AL-49; dashboard F; the taxonomy instrumentation and the acknowledgement-basis counter exist (IR-7J-43, IR-7J-44); VT-7J-09, -16, -75 … -81 pass; AG-7J-13 open for the webhook streams |
| AG-7J-08 | Executing or reporting any erasure for event stores; sealing; hold placement with subject scope (with 7I AB-7I-05, -14, -15, -16) | Tier C metrics of §8.14, §8.15; AL-39 … AL-43; dashboard H; the watchers of IR-7J-26; VT-7J-18, -39 pass |
| AG-7J-09 | Activating a stack bound by a contract that permits no external notification | An in-region notification mechanism is approved by the owner and built (NTF-08; IR-7J-36) |
| AG-7J-10 | Reporting a data-subject erasure in an owning context as leaving no linkable telemetry | That context's erasure design severs the mapping (IR-7J-38) and VT-7J-56 passes for it; or the owner has decided the DSE-05 case for it |
| AG-7J-11 | Relying on telemetry evidence for any `PLATFORM` hold or incident-preservation order | The evidence function, prefix, key purpose and second path exist (IR-7J-40); VT-7J-57 … -59, -61 pass. Until then whoever places a hold is told that telemetry evidence is not preserved |
| AG-7J-12 | Production retention of any restricted telemetry beyond its first expiry period | The cold projection, the retention verification, the restore procedure and the incident template exist (IR-7J-18, -32, -35); VT-7J-53 … -55, -60, -62 pass |
| AG-7J-13 | Emission of any accounted metric (M-017, M-022, M-085, M-086, M-122, M-131, M-144, M-145, M-165 … M-168, M-290 … M-295), reporting of any indicator that reads one (SLI-01, SLI-11, SLI-12a … c, SLI-17), and therefore the approval of any objective on them | The accounting relations, the hour ledger, folds, window functions and indexes exist (IR-7J-41, IR-7J-47) together with the future source records they read (7H MR-7H-06; 7I IR-41 completion records, the accounting and position records of 7I §9.6; the 7G ledger; the incarnation check of 7I JRN-12; the superseding organization lifecycle functions of 7I OLC-06 … OLC-11 with the provenance refinement and listing function of ERR-7J-15 (IR-7J-48), without which no delivery can be settled and SLI-11 is not reported); every one of the eight streams is in the expected registry and `EXPECTED` with both fold kinds (IR-7J-42); VT-7J-63 … -66 and VT-7J-83 … -160 pass, the timing and concurrency ones against a real PostgreSQL 18 instance with controlled lock waits and commit delays. A stream is activated separately: the three milestone streams and `webhook_first_closure` only with MR-7H-06. Until then those indicators are **not reported at all**: no figure from an observer watermark, a process counter, a fold-time counter difference or an estimate is substituted for them. After activation, an indicator whose stream is missing, or whose window state is `UNKNOWN` or `NOT_ESTABLISHED`, is not reported as a figure for that window, and one whose state is `ESTABLISHED_PARTIAL` or `ESTABLISHED_UNCERTAIN` is reported only with its coverage, counts and bounds, with no verdict (AOA-24) |
| AG-7J-14 | Reporting SLI-11, in any form, and the approval of any objective on it (SLO-D1). **Closed** (OD-7J-15 condition 18) | AG-7J-13, and in addition: the lifecycle evidence of ERR-7J-15 and its listing function are built and verified (IR-7J-48), including a sequence-0 baseline for every organization, the confirmation and prefix-removal function, and a `covered_from` that only moves forward; the final, finite retention of that evidence, with its erasure, backup and restore behaviour and any authorized preservation exception, is governed through 7L at or above the validated minimum (OD-7J-15 conditions 3, 13); 7K has validated the 45-day candidate against finalization lag, late registration, recovery and replay, observer outages, correction volume and restore (condition 2); VT-7J-122 … -126 and VT-7J-133 … -160 have passed on PostgreSQL 18 with controlled concurrency and deliberate statement delays; the consistency checks of AOA-26 (f) and AOA-27 (g) are in force. Until then SLI-11 is not reported and M-290 for it is not emitted |

**What a decision closes and what it does not.** The ten owner decisions settle policy. They build nothing: every gate above is closed today.

---

## 33. Phase 7K and 7L Handoffs

### 33.1 To 7K — Capacity, Performance and Resilience

7J claims no benchmark. Every value marked [CAND] or PROV in this document is unmeasured.

| ID | 7K receives | Exit condition |
|---|---|---|
| HE-7K-7J-01 | The cardinality budget of §9.4 (46,229 worst-case series by arithmetic; the five candidate limits; scrape interval and sample limits) | Measured series count at target scale; limits fixed |
| HE-7K-7J-02 | Instrumentation overhead on event-plane hops and proof of zero added synchronous I/O on the audio path (PRF-01, PRF-02) | Measured; budget fixed |
| HE-7K-7J-03 | Alert evaluation scalability: rule-group duration against interval; Alertmanager load in an outage | Measured |
| HE-7K-7J-04 | Cost of observer reads on the PostgreSQL primary and of Redis diagnostics on the primaries; polling cadence; observer connection budget; forensic-query limits (PRF-08 … PRF-11; RDO-06; OBP-09) | Cadence and budgets fixed |
| HE-7K-7J-05 | Trace volume at 25% plus the fault set; hop-local buffer memory; link cap; Tempo ingestion (OD-7J-06 condition 14) | Measured; values fixed |
| HE-7K-7J-06 | Collector and exporter scaling; SDK queue sizes; log token-bucket rates; Fluent Bit buffers (ISO-04; LOG-16) | Values fixed |
| HE-7K-7J-07 | Every `T_*` threshold of §23.4, in steady state and during catch-up after a prolonged outage; the freshness bound of EVD-03 | Values fixed; PROV status reviewed per alert |
| HE-7K-7J-08 | Regional failover: behaviour of each region's telemetry stack; the dead-man path per region; what operators see during and after | Drill performed |
| HE-7K-7J-09 | Storage capacity and cost: raw metrics 30 days; SLO history 13 months; traces 14 days; logs per 3F §18.3; alert history; the evidence prefix (OD-7J-03 condition 10) | Sized |
| HE-7K-7J-10 | Overhead of subject-index, hold, sealing and erasure observability: counts from maintained state, never scans (PRF-15) | Measured |
| HE-7K-7J-11 | Telemetry load of recovery and replay: operation and item counters, fault-sampled spans for every item, at the volume a prolonged group outage would produce (7I HE-7K-7I-10) | Measured |
| HE-7K-7J-12 | Relay throughput with and without instrumentation, including M-017's database-side bucketing | Measured |
| HE-7K-7J-13 | Benchmarks of every candidate objective of §11.2 under normal load, peak load, dependency outage, consumer recovery, Redis durability shortfall and catch-up (OD-7J-01 condition 5) | Results delivered to the owner for the approval decision |
| HE-7K-7J-14 | Cost of observation accounting (§6.4): obligation-record volume per stream against AOA-23; hourly cohort rows; routine and completeness fold duration and their load on the primary; the lookback `L`, the fold cadence, `T_fold`, the settle delay, the grace `G`, the permitted watermark lag `T_final_lag` and the safety margin against each source's guaranteed life; the window read functions; index cost on the outbox, the 7H history records, the completion records and the ledger; the expected volume of post-final corrections for past-dated origins such as EV-079 and of eligibility moves; the margin `m` against each `R_min`; the cost of the hour ledger, of the eligibility settlement; the unmeasured-hour tolerance (2%, 13 hours) and how often a single unmeasured hour would keep a window out of budget governance; the width of lifecycle bands in practice (fold cadence against lifecycle-transaction length), the resulting share of `uncertain` deliveries per suspension and `T_uncertain`; the cost of the lifecycle listing; the observer's per-instance series against the 6,000 limit; **validation of the 45-day candidate minimum for lifecycle evidence** (OD-7J-15 conditions 1, 2) against the finalization lag, late delivery registration, recovery and replay processing, observer outages, correction volume and restore behaviour, and how often a suspension near a deadline leaves SLI-11 without a verdict (OD-7J-14); the cadence of the Organization-side confirmation and removal pass, its share-lock cost against 7H admissions, `T_unsettled`, and how often a late-registered delivery falls before `covered_from` | Values fixed; proof that the fold never delays a relay, a consumer, a dispatcher or a cleanup; the finalization delay each objective can expect |

### 33.2 To 7L — Final Event Architecture Reconciliation

| ID | 7L receives | Exit condition |
|---|---|---|
| HE-7L-7J-01 | The metric-name reconciliations of §7.4 | Each accepted or declined by its owner |
| HE-7L-7J-02 | Errata ERR-7J-01 … ERR-7J-15 (ERR-7J-15 is the one that adds to a frozen 7I evidence contract; approved by OD-7J-13) and conflicts CNF-7J-01 … CNF-7J-19 | Each consolidated or explicitly declined |
| HE-7L-7J-03 | API metric-label compatibility: the 6A and 3E `tenant_id` labels (ERR-7J-01); the governance bound on `plugin_key` and `definition_key` (LBL-08) | A recorded decision by the 6A, 3E and 6J owners |
| HE-7L-7J-04 | Redaction reconciliations: Collector allow-list (ERR-7J-07); cold security projection (ERR-7J-11); log field classification of §13.2 against D0's redaction lists | Recorded |
| HE-7L-7J-05 | Owner decisions OD-7J-01 … OD-7J-15 | Recorded in the consolidated register |
| HE-7L-7J-06 | Operator access to in-region telemetry from outside the region (RSD-7J-06), with 7I HE-7L-7I-06 | Contract position recorded |
| HE-7L-7J-07 | Activation gates AG-7J-01 … AG-7J-14 and the governed-migration dependencies: IR-7J-10, -11, -12, -24, -41, -45, -47, -48 (and through them 7I IR-15); the final, finite retention of organization lifecycle provenance rows, with erasure, backup and restore and any authorized preservation exception, which 7I does not state: 7J requires only the candidate minimum of OD-7J-15 and sets no maximum, and AG-7J-14 stays closed until this is reconciled | One consolidated go-live checklist with 7G §56, 7H §17.5, 7I §24 |
| HE-7L-7J-08 | Tenant-facing operational capability: none exists; any future one is a new decision and a new API contract (TFS-04) | Recorded |
| HE-7L-7J-09 | Residual risks RR-7J-01 … RR-7J-16 and the Minor findings of §34.3 | Accepted or mitigated, by name |
| HE-7L-7J-10 | Trace propagation compatibility: derivation from `event_id` (TRC-01); no envelope, entry or header field; the option of a governed 7C field in a future version is not requested | Recorded |
| HE-7L-7J-11 | Final SLO authority: every objective of §11.2 is `PROPOSED`; approval is the owner's after 7K | Recorded |
| HE-7L-7J-12 | The two BLOCKED handoffs (H-7B-01; HE-7J-7I-04 in part) and the dependency of DSE-04 on HE-7L-7I-11 | Owners named; closed or carried |

---

## 34. Adversarial Verification

### 34.1 Attempted counterexamples

Each row is an attempt to break the design by reasoning from this document and the frozen sources. None was executed.

| # | Attempt | Result | Evidence | Residual risk | Correction made |
|---:|---|---|---|---|---|
| 1 | One tenant's metric values or traces visible to another tenant | Not reachable | No tenant has any telemetry access (TQA-13, TFS-01); metrics carry no tenant dimension (LBL-01); a T2 grant is scoped to one organization and the broker rejects the rest (TQA-04, TQA-05) | An operator with T3 and a security-investigation grant can group by organization; recorded (TQA-08) | — |
| 2 | Prometheus cardinality explosion | Bounded | Closed label sets; build and run-time guards; scrape limits (§9.5); worst case computed (§9.4) | `plugin_key` is bounded by governance only (LBL-08) | Cap and `other` bucket added |
| 3 | Sensitive identifiers reaching metrics | Blocked at build and at run time | LBL-06, LBL-07; "by organization" handoffs converted to counts (LBL-04) | A label with a legitimately closed but sensitive set (`secret_role`) exists on one restricted series | M-134 restricted to dashboard G; never in a notification |
| 4 | Credentials reaching logs or traces | Blocked by construction, then detected | Helper accepts only named typed fields (LOG-01); exceptions logged as categories (LOG-05); span allow-list twice (TRC-09); scanner (SCN) | Third-party library logging outside the helper relies on D0 redaction and the node filter | — |
| 5 | Sampled tracing hides a high-severity recovery incident | No | Every alert reads counters or state (SMP-08); the fault set is always exported from the failing hop onward (SMP-05, SMP-06) | Healthy earlier hops of an unsampled event are not recoverable (RR-7J-02) | Limitation stated (SMP-07) |
| 6 | A publication metric claims success before durable confirmation | No | `CONFIRMED` is counted only after the 7E criterion and the adapter's return (OBX-02); a `WAITAOF` timeout is `UNKNOWN` | — | — |
| 7 | A successful `XACK` counted as successful processing | No | Separate metrics, separate components, never combined (CNS-07); the contradiction rule (CNS-09) | — | — |
| 8 | A replay counted as a new business event | No | M-107 separate from M-005 and M-063; R4 and R5 excluded from SLI-01 … -03 (RCV-05, SLI-R-07) | A dashboard author could still add them; the build check on recording rules does not catch a panel | Stated on dashboard E's caveats |
| 9 | A stopped consumer appears healthy because telemetry is missing | No | Lag comes from Redis through the observer, not from the consumer; missing group or stale evidence is `UNKNOWN` with AL-12, AL-50; missing heartbeat is AL-51 (RDO-02, EVD-07) | Observer and consumer down together: AL-50 and AL-51 both fire | — |
| 10 | Lag computed from incomparable clocks | **Found in the first draft and corrected** | A relay-clock minus `occurred_at` latency and an entry-ID-as-time comparison were both possible readings of OBS-7D-13 and of trim lag | — | CLK-01 … CLK-06: database-clock ages; no entry ID as time |
| 11 | A legal hold disappears from retention monitoring | No | Standing panels with no time filter (PRV-07); M-227, M-196, M-241; held rows counted on every pass (M-234) | Depends on the observer functions of IR-7J-12 | — |
| 12 | Sealed data remains ordinarily accessible without an alert | The control is not the alert | The guard denies (7I CAG-01); denials counted (M-254); direct column access is `42501` (M-219) and AL-43a | If a raw grant is left in place contrary to 7I CAG-06, telemetry sees nothing until an attempt fails; that is 7I's gate AB-7I-15, not a monitoring gap 7J can close | PRV-05 states it |
| 13 | A restore resurrects old telemetry assumptions or privacy contents | Bounded | Telemetry is separate from the database and is never an input to reconciliation (PRV-10); a restored telemetry store runs its retention pass before serving (RET-7J-05); incarnation state exported (M-216) | — | — |
| 14 | Audit replaced by best-effort metrics | No | Audit commits first; the counter follows (AUD-7J-02); no function reads a metric (AUD-7J-03) | — | — |
| 15 | An observer principal with event-mutation privileges | **Found and corrected** | The obvious read-only role, `app_readonly`, holds `SELECT` on tenant content and on outbox payloads; `XINFO STREAM` returns entry content | — | OBP-02 … OBP-07: aggregate-only functions, a new principal, group-level Redis commands only |
| 16 | A tenant-facing dashboard reveals platform procurement cost | Not reachable | No tenant-facing dashboard exists (TFS-01); cost is not telemetry of this document (TFS-03) | — | — |
| 17 | A failed provider or receiver misclassified as an internal outage | No | Every closure is in exactly one class (§19.2); SLI-12a and SLI-12b count a sent, receiver-failed attempt as good, and only SLI-12c, which is not a platform objective, counts it as not good (EXT-02, SLI-R-05) | A receiver timing out because of a platform egress fault is recorded by the category the dispatcher can observe | Origin split shown on every panel |
| 18 | An SLO claims a guarantee the instrumentation does not support | No | Every objective is `PROPOSED`; evidence class on every figure (SLO-01, SLO-07); not-established windows (SLI-R-04) | — | — |
| 19 | A telemetry sink exports India-enterprise metadata out of region | Blocked, then detected | Governed destination list; build check; drift alert (RSD-7J-04); notifications minimal (NTF-01) | Exposure between an unauthorized change and its detection | AL-57 at SEV1 |
| 20 | A monitoring outage causes a voice-latency regression or an acknowledgement failure | No | No synchronous export; errors swallowed; bounded queues; no readiness coupling (ISO-01 … ISO-05) | Proven only when VT-7J-48 is run | — |
| 21 | Identifiers kept for 2 years through incident notes or cold security logs | **Found in the first draft and corrected** | An earlier rule exported identifiers into incident records | — | RET-7J-06, RET-7J-08; SMP-11 rewritten |
| 22 | An alert notification leaks a label value | **Found and corrected** | A template iterating over all labels would send whatever a rule carries | — | NTF-03, NTF-04 |
| 23 | A uniform sampler that is not uniform | **Found and corrected** | A UUIDv7 used directly as a trace ID biases ratio sampling | — | TRC-01, TRC-02 |

### 34.2 Residual risks, stated

| ID | Residual risk | Why it remains | Compensating controls | Status |
|---|---|---|---|---|
| RR-7J-01 | A compromised telemetry stack can read class R telemetry and hide or forge alerts | It must read what it stores, and it evaluates its own rules | No mutation privilege anywhere (OBP-07); external dead-man (MON-04); independent run records of mandatory controls (MON-05); audited access and configuration | For acceptance (7L) |
| RR-7J-02 | Spans of healthy hops before a fault are lost for events outside the 25% | A head decision precedes the fault | Authoritative records for every hop; forward marking | For acceptance (7L) |
| RR-7J-03 | Detection of an unaccounted obligation can take up to `T_obl` plus one reconciler period | Inherited from 7I ACC-17 | AL-18; early Redis-derived corroboration | Inherited |
| RR-7J-04 | An activity counter loses an increment when a process dies between the fact and the increment | No transaction spans both | Obligation indicators use keyed stores (DUP-03) | For acceptance (7L) |
| RR-7J-05 | Within 90 days, someone holding both the journal's decrypt permission and T2 access could relate a subject's erased resources to telemetry lines | The journal keeps resource references for restore safety (7I JRN-03) | Two separate, separately audited authorities; no subject key in telemetry | For acceptance (7L) |
| RR-7J-06 | Required telemetry evidence can be lost if every capture path fails until the source expires, or if it had already expired when the obligation became known | Expiry is never frozen | Immediate capture; second path; SEV1; the loss is recorded | **Accepted by the owner (OD-7J-10)** |
| RR-7J-07 | Restricted telemetry allows inference from metadata (organization, event types, timing) without any identifier of a person | Operational telemetry is metadata | Access tiers; 14- and 90-day lifetimes | For acceptance (7L) |
| RR-7J-08 | A security counter at zero does not prove no attempt occurred while its emitting component was down | Detection needs the detector | Heartbeats; the controls themselves do not depend on telemetry (SECM-01) | For acceptance (7L) |
| RR-7J-09 | If no completeness fold runs for a stream for longer than its sources' guaranteed life, obligations are not registered: their latency is unrecoverable and their cohort hours are declared and finalized unmeasured. Across a database restore, the hours from the restore point to the first fold after activation are unmeasured. A row that was both past-dated to before a declared interval and deleted unregistered is represented nowhere | Accounting follows the event plane and never delays cleanup (AOA-10); a recovery case holds no `occurred_at` (7G §18.1); a past-dated origin has no upper bound in the frozen sources | The loss is detected from run records and declared, permanently (AOA-11, AOA-14); the hours stay inside the window as unmeasured and remove it from every verdict (AOA-21, AOA-24); unresolved obligations with a case stay visible as `UNREGISTERED_CASE` and make the window not established (AOA-19, AOA-26); AL-59 escalates to SEV1 before the loss | For acceptance (7L) |
| RR-7J-10 | A source, component or shard that is missing from the expected registry cannot raise a blindness alert | The registry is the trust root for "what must report" | Registry generated beside the 7E group registry and the deployment manifest; anything reporting and unregistered is shown; registry changes audited | For acceptance (7L) |
| RR-7J-11 | A window that was reported can be restated: an obligation may reach an already final cohort hour (a late-visible commit, or a producer-assigned past `occurred_at` such as EV-079), be reclassified not owed, or be moved to `held_interval` by status evidence that became visible late | Finalization cannot wait for an arrival that has no upper bound in the frozen sources | Final rows are never edited; corrections are signed, appended with provenance, counted per hour, included in the window from then on and exported (M-293, AL-60); the volume is 7K's to measure | For acceptance (7L) |
| RR-7J-12 | The instant a status change takes effect is known only within a band, from the post-lock clock to the fold's first sighting or the next transition's lock. A delivery whose event-to-deadline window meets a band and holds no certainly non-`ACTIVE` instant is `uncertain`. A slow fold or a long lifecycle transaction widens the band and raises the uncertain share | PostgreSQL gives a transaction no way to record its own commit; 7J may not lock the organization row or wait on it (AOA-09) | Nothing is assumed either way: `uncertain` deliveries are outside both populations, and while one is in the window no verdict is given and no budget moves (AOA-27 h; OD-7J-14); the share is exported and alerted (M-290, AL-60); 7K measures the band (HE-7K-7J-14) | For acceptance (7L) |
| RR-7J-13 | One unmeasured cohort hour keeps an accounted window out of every verdict and every budget movement for up to 28 days. A freeze in force when a restore happens cannot be ended by a window during that time | Counting an unmeasured hour either way would report something that was not measured (OD-7J-02 condition 5) | The window state and the cause are shown; the last established budget and freeze evidence are preserved; burn-rate alerts on activity evidence and every invariant alert are unaffected; a change during such a freeze goes through EB-08 | **Accepted by the owner** (OD-7J-11 condition 8) |
| RR-7J-14 | Exclusion is of the whole delivery. A brief suspension proved inside the event-to-deadline window removes from SLI-11 a delivery that was already delayed by the platform, or already closed in time | A pause-adjusted measure was not approved as a binding objective in V1 (OD-7J-12 condition 15) | The active-time diagnostic M-296 shows the delay accrued while the organization was active; `excluded_held` shows how many deliveries were excluded | **Accepted by the owner** (OD-7J-12 condition 16) |
| RR-7J-15 | One delivery settled `uncertain` on a timing band keeps the SLI-11 window without a verdict and without budget movement until its cohort hour has left the window, up to 28 days. Suspensions that land near a deadline can therefore keep SLI-11 without a verdict for long stretches | A verdict over deliveries whose eligibility is not proved would rest on an assumption (OD-7J-13 condition 19) | Counts, the ratio and both bounds are still published; the last established budget state is preserved; the uncertain share is alerted (AL-60); 7K measures how often it happens and how narrow the bands can be made (HE-7K-7J-14) | **Accepted by the owner** (OD-7J-14 condition 13) |
| RR-7J-16 | `covered_from` is deliberately conservative. A window that begins before it is `EVIDENCE_UNAVAILABLE` even where the true status could have been inferred, and the latest transition of an organization is kept until its confirmation is older than the lifetime, so its evidence can live up to about twice the minimum | Only an instant proved under the row lock may claim coverage; the current status proves nothing about the past | Coverage always includes the last 45 days, which contain every delivery that can enter a reported window; older deliveries affect no reported figure; the unsettled-window age is exported before evidence can be removed (M-284, AL-60) | For acceptance (7L), with the final lifetime |

### 34.3 Findings ledger

Severity: **P0** a design that would lose an obligation or disclose tenant data in normal operation; **P1** a design defect that breaks a frozen rule or an owner condition; **Minor** a naming, wording or documentation issue.

| ID | Severity | Finding | Closure | Status |
|---|---|---|---|---|
| F-7J-01 | P1 | The existing read-only database role would give the exporter access to payloads and personal data | OBP-02, OBP-03; IR-7J-10; AG-7J-02 | Closed by design; gated |
| F-7J-02 | P1 | `XINFO STREAM` exposes entry content to an observer | OBP-04, OBP-05 | Closed by design; verification VT-7J-33 |
| F-7J-03 | P1 | Trace ID taken from a UUIDv7 would break deterministic ratio sampling | TRC-01, TRC-02 | Closed by design |
| F-7J-04 | P1 | Missing evidence could render as zero backlog or zero lag | EVD-01 … EVD-07 | Closed by design |
| F-7J-05 | P1 | Latency and lag computed across clocks or from entry IDs | CLK-01 … CLK-06 | Closed by design |
| F-7J-06 | P1 | Head sampling alone cannot capture late faults | SMP-05 … SMP-07 | Closed by design, with RR-7J-02 |
| F-7J-07 | P1 | Frozen Collector example redacts by deny-list | TRC-09; ERR-7J-07 | Closed by design |
| F-7J-08 | P1 | Frozen sources label metrics and group alerts by tenant | LBL-01, LBL-10; ERR-7J-01, -02, -05 | Closed for the event plane; API metrics handed to 7L |
| F-7J-09 | P1 | Identifiers would persist 2 years in incident records and cold security logs | RET-7J-06, RET-7J-08 | Closed by design |
| F-7J-10 | P1 | Notification templates could leak label values out of region | NTF-03, NTF-04 | Closed by design |
| F-7J-11 | P1 | Handoffs asking for per-organization figures would force tenant labels | LBL-04 | Closed by design |
| F-7J-12 | P1 | Evidence preservation and never-freeze expiry cannot both be absolute | EVP-08, EVP-09; OD-7J-10 | Closed by owner decision; residual accepted |
| F-7J-13 | Minor | 7D handoff lists OBS-7D-01 … -17 although -18 exists | CNF-7J-01; ERR-7J-09 | Recorded |
| F-7J-14 | Minor | Frozen Gauges named `_total`; a rate named as a metric; an unbounded `semver` label | §7.4; ERR-7J-03, -04 | Recorded |
| F-7J-15 | Minor | `secret_role` is a label on one restricted series | M-134; EXT-06 | Recorded |
| F-7J-16 | Minor | Two handoff signals have no source yet (M-177, M-180), and three Voice metrics have none (M-146 … M-148) | BLOCKED rows of §4; AG-7J-04 | Open dependency, gated |
| F-7J-17 | Minor | Linkability after erasure depends on owning-context designs that do not exist | DSE-04, DSE-05; AG-7J-10 | Open dependency, gated |
| F-7J-18 | Minor | The in-region-only notification mechanism is not selected | NTF-08; AG-7J-09 | Open dependency, gated |

Totals of this self-review ledger, as first submitted: P0 0; P1 12 raised and reported closed; Minor 6, of which 3 are open dependencies behind a gate. **That report was not accurate.** The independent review found four P1 defects that this ledger did not contain, and two of its rows (F-7J-04, F-7J-05) were closed incompletely. The findings of record are in §34.4 and §34.5.


### 34.4 First independent freeze-gate review: findings and remediation

The independent review of the first submission (2,744 lines, `6ae40698…67ed71`) did not approve it: P0 0, P1 4, Minor 2. All six are accepted as stated. The author's own ledger of §34.3 had reported P1 = 0 open; that was wrong, and two of its "closed" rows were closed incompletely (F-7J-04 by R02, F-7J-05 by R01). Everything below is static design evidence. No test was executed.

**P1-7J-R01 — Unreliable histogram observation accounting.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Original defect | M-017, M-122 and M-131 selected "rows since the previous watermark" in the observer. The watermark was process memory; two replicas each observed every row; a restart lost or repeated rows; a timestamp cursor can pass a row that commits late. DUP-04 prescribed `max` for gauges and said nothing valid for histogram buckets |
| 2 | Frozen-source evidence | `077_5J1`: the outbox has `published_at` and `occurred_at`, no monotone commit-ordered column and no index on `published_at`. 7D CLN-02: `PUBLISHED` rows are deleted after 7 days. `063_5I`: delivery rows have no `occurred_at`. 7H MR-7H-06 and 7I CEV-03: the records that carry the other timestamps are append-only and unique per identity |
| 3 | Corrected invariant | An accounted observation is counted exactly once per observation identity, in the database transaction that inserts its marker (AOA-02, AOA-03) |
| 4 | Measurement boundary | The fold transaction, after the source row is committed and visible; values are differences of stored PostgreSQL timestamps (CLK-03) |
| 5 | Trusted data source | The source relation of each stream and the durable totals (§6.4 stream table). No observer memory |
| 6 | Concurrency and crash | One fold at a time per stream by a lock; markers and totals commit together; a crash rolls both back; a restart needs no state (AOA-04, AOA-06, AOA-07) |
| 7 | Duplicates and replay | The marker's primary key; identity is the obligation, so duplicate confirmations, redeliveries and replays add nothing (AOA-17) |
| 8 | Failure and unknown evidence | Accounting behind: intervals unmeasured (AOA-12). Source deleted first: loss declared, counted where a longer-lived record allows, never estimated (AOA-11). Restore: epoch change, intervals unmeasured (AOA-14) |
| 9 | Privilege and tenant isolation | The observer gains `EXECUTE` on fold functions only; they read identifiers and timestamps, never content, write only the accounting relations, return counts; no organization dimension (AOA-08) |
| 10 | Implementation requirement | IR-7J-41 (governed migration: markers, totals, run records, folds, indexes), IR-7J-45, IR-7J-46 |
| 11 | Activation condition | AG-7J-13: until it opens the accounted indicators are not reported at all |
| 12 | Deterministic tests | VT-7J-63 (trace A), VT-7J-64 (trace B), VT-7J-65 (trace C), VT-7J-66 (trace D) |
| 13 | The counterexamples, excluded | **A.** E is `PUBLISHED`. Replica A's fold inserts marker (`outbox_publication`, E) and adds 1 to the totals. Replica B's fold finds the marker and adds nothing. Both read `_count` = n + 1. The query takes `max without (instance)`: n + 1, not n + 2. **B.** The observer dies after selecting rows. If before commit: no marker, no total; the next fold counts them once. If after: markers exist; the next fold skips them. The observer held nothing to lose. **C.** The observer is down past the 7-day cleanup. The rows are gone; their latencies cannot be known. The next fold sees its last completeness fold is older than the retention margin, adds the interval to M-285, counts the lost observations from position records where they still exist, and every window overlapping the interval is reported not established. No value is invented and no window is called complete. **D.** Three rows share a `published_at`: three identities, three markers. A fourth row's transaction assigned its `published_at` earlier and commits later: the routine fold finds it because it has no marker and is inside the lookback; if its commit lagged beyond the lookback, the daily completeness fold, which has no lookback, finds it. Its marker prevents a second count. No cursor decides anything (AOA-05) |

**P1-7J-R02 — Missing-source and per-shard alert blindness.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Original defect | AL-50 used `absent(M-270)` and AL-51 `absent` on the heartbeat, which are false while any one series of the metric exists. AL-08 divided regional sums, so a busy healthy shard hid a failing one |
| 2 | Frozen-source evidence | 7E WAO-04: a `WAITAOF` result applies per shard and never across shards. 7E §29: the group registry is closed and code-owned, so "what must exist" is knowable. 7E TRM-03, TRM-04: registered-missing and unregistered-present are distinct anomalies |
| 3 | Corrected invariant | Every expected source, (component, group) and shard has a constant series generated from a trusted registry, independent of the thing it names; its absence or staleness is detected by a label-preserving `unless` (EVD-08, EVD-09). Durability is judged per shard |
| 4 | Measurement boundary | Rule evaluation in Prometheus; the expected series do not come from the observer or from any workload |
| 5 | Trusted data source | The code-owned expected registry (reviewed, audited changes); for shards, the active topology generation |
| 6 | Concurrency and crash | Component replacement, shard primary failover and rolling deploys keep registry identity (logical names, never instances or nodes). A topology or group change updates the registry in the same governed change (EVD-10, EVD-11) |
| 7 | Duplicates and replay | Two replicas reporting one source: `max by (source)`; either one fresh is fresh |
| 8 | Failure and unknown evidence | A silent source is `UNKNOWN` for that source only. No samples is never success (EVD-12; SLI-03). Total blindness of observer, Prometheus or Alertmanager is the external dead-man (MON-04; AL-54) |
| 9 | Privilege and tenant isolation | Labels are `source`, `component`, `group`, `shard`, `state`: all in the allow-list, none tenant-derived |
| 10 | Implementation requirement | IR-7J-42 (registry and generated rules), IR-7J-46 (build rejects bare `absent()` and open inhibition) |
| 11 | Activation condition | AG-7J-01, AG-7J-03 |
| 12 | Deterministic tests | VT-7J-67 (trace A), VT-7J-68 (trace B), VT-7J-69 (trace C), VT-7J-70 (trace D), VT-7J-82 (inhibition) |
| 13 | The counterexamples, excluded | **A.** `journal` stops; its M-270 series expires. `platform_telemetry_expected_source{source="journal",state="EXPECTED"}` still exists, from the rule evaluator. The right-hand side of `unless on (source)` has ten sources and not `journal`, so the result is exactly the `journal` series: AL-50 fires with `source="journal"`, SEV1. **B.** The reconciler's heartbeat is gone; other components' are present. The same form on (`component`, `group`) returns exactly `obligation_reconciler`. **C.** Shard A 10,000 confirmed, shard B 12 unconfirmed. Per-shard ratio for B is 1.0, above any threshold; expression (b) returns B because B has unconfirmed results and no confirmation. A's volume appears in neither. **D.** With no samples the ratio in (a) is empty; nothing is concluded from that: the observer's absence is AL-50, the expected shard without capability evidence is AL-09, and SLI-03 counts the interval bad when rows were eligible and unmeasured otherwise. Inhibition cannot reach any of these (STM-05) |

**P1-7J-R03 — Incorrect SLI measurement boundaries and classifications.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Original defect | SLO-C1 … C3 claimed event-to-effect and pointed at SLI-04, which timed only receipt to commit. SLI-11 named "first attempt" and had no first-attempt metric (M-122 is fan-out lag; M-125 is an age). SLI-12 put sent, receiver-failed attempts in both the numerator and the exclusions. SLI-06, -08, -09, -13, -14, -15 had survivorship, identical numerator and denominator, or no source for a term |
| 2 | Frozen-source evidence | 7F §36.4 ("time from delivery to durable commit"); 4G §12.2 (event to effect); 7I CEV-03 (completion record, one per (group, event), commit time); 7H MR-7H-06 (C `claimed_at`, A `admitted_at`, X `closed_at` and `attempt_number`; no hand-off time); 7H DSM-07 H5, H6; HTP-14, HTP-19 |
| 3 | Corrected invariant | One name, one interval (SLI-R-11); every latency indicator has a censoring term (SLI-R-09); every ratio's classes are disjoint and complete (CLO-01) |
| 4 | Measurement boundary | §10.3: both ends of every objective-bearing interval are PostgreSQL timestamps of durable records |
| 5 | Trusted data source | Outbox row; completion record; delivery row; C, A, X records; ledger; M-149 for acknowledgements |
| 6 | Concurrency and crash | Accounted streams (R01). State gauges are exact at the read. Activity-grade indicators are labelled estimated (SLI-R-10) |
| 7 | Duplicates and replay | Per-contract in §10.4; recovery completions and replay deliveries are separated by dimension or predicate |
| 8 | Failure and unknown evidence | Unmeasured time and not-established windows (SLI-R-04); overdue obligations counted not good from the boundary |
| 9 | Privilege and tenant isolation | No new label beyond `closure_class`, `eligibility`, `origin`, `stream`: closed, small, not tenant-derived. The organization-status interval used for `eligibility` is read inside the fold and never exported |
| 10 | Implementation requirement | IR-7J-41, IR-7J-43, IR-7J-44, IR-7J-45 |
| 11 | Activation condition | AG-7J-05, AG-7J-07, AG-7J-13 |
| 12 | Deterministic tests | VT-7J-71 … VT-7J-78 |
| 13 | The counterexamples, excluded | An event that waits 30 s in transport and commits in 50 ms: SLI-04 = 0.05 s, labelled handler execution; SLI-17 = about 30 s and not good; the objective reads SLI-17. Each of the eight closures the review listed falls in exactly one class and the three indicators give 2 of 6, 4 of 8 and 1 of 2 (§10.4); the receiver's 500 after an actual send is `SENT_FAILED_EXTERNAL`: good in 12a and 12b, not good in 12c, excluded from none of them. All targets remain PROPOSED / REQUIRES BENCHMARK |

**P1-7J-R04 — Missing Phase 7H webhook closure outcomes.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Original defect | `send_state` allowed `SENT` and `NOT_SENT` only; M-128 claimed "one per closure record" with an `attempt_number` label on every observation |
| 2 | Frozen-source evidence | 7H DSM-07 H6: "a sweep closure is `UNCERTAIN` if any admission exists and `NOT_SENT` otherwise". T-08: `CLAIM_EXPIRED`, one attempt, `closed_by = SWEEP`. T-09: disposition `RELEASED_ORG_NOT_ACTIVE`, `NOT_SENT`, "no `attempt_number`", `attempt_count` unchanged. DSM-07 H5: `attempt_number` non-NULL exactly when the closure spent the budget. MR-7H-06: "`attempt_number` or NULL". HTP-19: the one claim that sends nothing and spends nothing is the organization hold |
| 3 | Corrected invariant | The four record kinds and both closure kinds are counted by their own metrics; `UNCERTAIN` is a first-class value everywhere; no attempt number is ever fabricated (EXT-05, EXT-13, §19.2) |
| 4 | Measurement boundary | After the transaction that writes the record commits (activity); in the fold (accounted, M-144) |
| 5 | Trusted data source | The 7H history records; the dispatcher's and sweeper's own results |
| 6 | Concurrency and crash | A closure is unique per (delivery, `claim_seq`) (MR-7H-06); a late worker cannot close through the fence (DSM-01) |
| 7 | Duplicates and replay | A public replay is a new delivery with its own claims and closures |
| 8 | Failure and unknown evidence | A combination outside the frozen vocabulary is `UNCLASSIFIED` and alerted, never dropped or coerced (CLO-01) |
| 9 | Privilege and tenant isolation | `secret_role`, claim and admission sequences stay class R; the new labels are closed sets |
| 10 | Implementation requirement | IR-7J-43 |
| 11 | Activation condition | AG-7J-07 |
| 12 | Deterministic tests | VT-7J-79, VT-7J-80, VT-7J-81, VT-7J-77 |
| 13 | The counterexamples, excluded | A T-09 release increments M-161 and M-164 and nothing with an attempt number: M-128 and M-163 are unchanged, so it is not a spent HTTP attempt and no attempt number is invented. A sweep closure after an admission is `send_state="UNCERTAIN"` on M-128 and M-137 and class `UNCERTAIN` on M-144; the label set contains the value, so the registry does not send it to `other` and M-275 does not move |

**Minor findings.**

| ID | Finding | Disposition |
|---|---|---|
| Minor-7J-R01 | The frozen 7A – 7C files are CRLF in the working tree; raw and LF-normalized hashes differ; the first version printed raw hashes unlabelled | §1.1 now gives both, labelled, with the on-disk line ending of each file. Frozen files untouched |
| Minor-7J-R02 | OD-7J-10 was reported as "approved by selection only" while the owner's conditions on a failed preservation exist | EVP-09 revised (independently authorized secondary path; legal and privacy escalation; a recorded failure is not compliance) and EVP-17 added, mapping each condition to a rule. RR-7J-06 remains accepted. No new decision was needed |

**Regression check of the first version's twelve self-reported P1 rows.**

| Row | Result after this remediation |
|---|---|
| F-7J-01 (exporter role) | Holds. The observer's one new privilege is `EXECUTE` on fold functions that read no content (OBP-02, AOA-08) |
| F-7J-02 (`XINFO STREAM`) | Holds; unchanged |
| F-7J-03 (trace ID digest) | Holds; unchanged |
| F-7J-04 (unknown as zero) | **Was closed incompletely.** EVD-02 was right; the absence detection built on it was not. Corrected by EVD-08 … EVD-12 (R02) |
| F-7J-05 (clocks) | **Was closed incompletely.** The single-clock rule holds; the watermark that fed the database-clock histograms was unsound. Corrected by §6.4 (R01) |
| F-7J-06 (late faults) | Holds; unchanged |
| F-7J-07 (Collector allow-list) | Holds; unchanged |
| F-7J-08 (tenant labels) | Holds. No new label is tenant-derived |
| F-7J-09 (identifiers for 2 years) | Holds; unchanged |
| F-7J-10 (notification templates) | Holds; alert labels added are from the allow-list |
| F-7J-11 (per-organization handoffs) | Holds; unchanged |
| F-7J-12 (evidence versus never-freeze) | Holds; conditions now mapped (EVP-17) |

**Regression check of the nineteen areas the review named.**

| # | Area | Result |
|---:|---|---|
| 1 | Incoming 7A – 7I handoffs | 88 rows, 86 closed, 2 blocked: unchanged; nine rows now cite the revised metrics |
| 2 | Metric catalogue | 254 metrics: the 232 of the first version, 10 of them redefined, plus 22 |
| 3 | Sensitive-label exclusions | LBL-01 unchanged; build deny patterns unchanged |
| 4 | Cardinality budget | Recomputed: 42,389 worst case against a 60,000 candidate budget (§9.4) |
| 5 | Event versus business-completion measurements | §17.2 unchanged; §10.3 adds the interval table |
| 6 | Gateway acknowledgement-integrity monitoring | §20.2 unchanged |
| 7 | Redis per-shard durability | AL-08, AL-09, SLI-03 per shard |
| 8 | 7H closure taxonomy | §19.2 |
| 9 | SLI and SLO formulas | §10.2 – §10.4; §11.2 re-pointed |
| 10 | OD-7J-01 … OD-7J-10 | Unchanged; every objective still PROPOSED |
| 11 | Trace sampling and fault capture | Unchanged |
| 12 | Restricted telemetry; audit separation | Unchanged |
| 13 | In-region observability; minimal egress | Unchanged; the expected-registry series stay in region |
| 14 | Retention and identifier minimization | Unchanged. Markers hold identifiers inside PostgreSQL only, are not telemetry, are unreadable by any login role and are purged with their source (AOA-10) |
| 15 | Sealed content and legal-hold monitoring | Unchanged |
| 16 | Evidence preservation and its residual | EVP-09, EVP-17 |
| 17 | Critical alerts, dashboards, runbooks | AL-01, -08, -09, -15, -23 … -25, -27, -29, -50, -51 revised; AL-59 added; dashboards D, F, I; RB-08, RB-17 |
| 18 | Monitoring-outage handling | §25 unchanged in direction; MON-03 corrected |
| 19 | 7K and 7L handoffs; activation | HE-7K-7J-14; AG-7J-13; IR-7J-41 … IR-7J-46 |

**Independent-review ledger.**

| ID | Severity | Status (author's reading; the re-review decides) |
|---|---|---|
| P1-7J-R01 | P1 | Remediated in the design; gated by AG-7J-13 |
| P1-7J-R02 | P1 | Remediated in the design; gated by AG-7J-01, AG-7J-03 |
| P1-7J-R03 | P1 | Remediated in the design; gated by AG-7J-05, AG-7J-07, AG-7J-13 |
| P1-7J-R04 | P1 | Remediated in the design; gated by AG-7J-07 |
| Minor-7J-R01 | Minor | Corrected |
| Minor-7J-R02 | Minor | Corrected |

---

### 34.5 Second independent freeze-gate review: findings and remediation

The independent review of the second submission (3,321 lines, `da25445d…70bf030`) found the four earlier P1 findings and both minors substantially resolved and raised three further P1 defects: P0 0, P1 3, new Minor 0. All three are accepted as stated; each was introduced or left open by the author's own first remediation (§6.4 as then written). Everything below is static design evidence. No test was executed. Where §34.4 speaks of "markers" and of counter differences, read it with this section: the marker is now the obligation record, and AOA-15 as then written is withdrawn. **This section is the record of the second round and is not rewritten.** Three things it states were changed by the third round (§34.6): the stream count (six then, eight now), finalization condition F5 and the window ("trailing 672 final cohort hours" then, 672 consecutive hours now), and the window states (three then, four now; five unmeasured hours give `ESTABLISHED_PARTIAL`, not `ESTABLISHED`).

**P1-7J-R05 — Outstanding-obligation measurement source.**

| Item | Evidence |
|---|---|
| Original failure | M-086 counted overdue pairs by reading `PUBLISHED` outbox rows without completion evidence, and M-085 read `occurred_at` from the outbox row when the completion was folded. Once the outbox row was deleted, an unresolved pair left M-086 and the SLI-17 denominator, and a later completion had no origin time |
| Frozen contract | 7I ACC-06: a `PUBLISHED` row is deletable when its 7 days have passed "and every group of its owed set has an accounting row **or a recovery case**". 7G §18.1: a recovery case holds group, `event_id`, `event_type`, state, `origin_obligation`, `first_seen_at`, `parked_at`, `resolved_at`, and **no `occurred_at`**. 7G PRT-02: an unresolved case never ages out. 7I ACC-13: a position record holds `recorded_at`, which is the publication record time, not the event time. 7I CEV-03: a completion record holds its commit time. `077_5J1`: `occurred_at` exists only on the outbox row |
| Corrected invariant | Every processing obligation has a payload-free obligation record that is created while the outbox row exists, stores the event's `occurred_at`, and stays open until a closing fact exists. A recovery case is never a closing fact. Outbox cleanup changes no figure (AOA-03, AOA-19) |
| Authoritative source and boundary | Registration: the outbox row and the owed set of 7I ACC-02 / ACC-15 through the payload-free listing of ACC-03; `origin_at` copied by the database. Closing: the completion record's commit time, an `UNSUBSCRIBED` accounting row, or a case's `resolved_at` with its resolution. Unresolved obligations at any moment: open obligation records, plus non-terminal `CONSUMER` cases in the ledger that have none (M-086) |
| Duplicates, retry, replay, groups, generations | One record per (logical group, `event_id`) by primary key; redelivery, reclaim, R2, R4 and a second generation's key add none; a later group's pair is `NOT_OWED` by origin provenance and its backfill is a replay item (AOA-17) |
| Crash, cleanup, restore | Fold crash: transaction rolled back, retried. Cleanup: irrelevant after registration. Registration missed because the observer was down past the row's guaranteed life: the pair cannot be given an origin time; if it has a case it is `UNREGISTERED_CASE` in M-086; its cohort hours are unmeasured (AOA-11). Restore: AOA-14 |
| Security and tenant isolation | The record holds `event_id`, group, timestamps and closed codes: no payload, no organization, no subject key. No login role has any privilege on it; observer functions return counts by `group` and `disposition` only. It keeps no identifier longer than a frozen relation keeps the same one (AOA-23). Erasure and holds: AOA-25 |
| Implementation requirements | IR-7J-41 (obligation records and folds), IR-7J-47 (read functions, the ledger union) |
| Activation gate | AG-7J-13 |
| Tests | VT-7J-83 (A), VT-7J-84 (B), VT-7J-85 (registration missed), VT-7J-86 (no extra obligations), VT-7J-72 |
| The counterexamples, prevented | **A.** Day 0: E published; the fold registers (G, E) with `origin_at` = E's `occurred_at`. G parks E. Day 8: cleanup deletes the outbox row under ACC-06. Day 10: the record is open; M-086 `PARKED` = 1; E is registered and not good in its Day-0 cohort hour, so it is in the SLI-17 denominator and not in the numerator. Nothing read the outbox row after Day 0. **B.** A later authorized R2 commits a completion with origin `RECOVERY_ITEM`. The fold closes the record `COMPLETED` at that commit time; latency = commit time − the record's `origin_at`. The surviving authoritative timestamp is `origin_at` in the obligation record, copied from the outbox column while it existed. A position `recorded_at`, an entry ID and a worker clock are not used (CLK-07) |
| Residual | RR-7J-09: a pair never registered has no recoverable latency. It is declared, and where a case exists it is still counted |

**P1-7J-R06 — Event-time SLO window accounting.**

| Item | Evidence |
|---|---|
| Original failure | AOA-15 (second submission) called `x − x offset 28d` over cumulative counters an exact 28-day total. A counter is incremented when the fold commits, so the difference counts observations by fold time |
| Existing 7J rule at fault | AOA-03, AOA-13, AOA-15 and SLI-R-04, SLI-R-09 as then written; the §10.4 contracts that wrote numerators as `Δ M-…_bucket` |
| Corrected invariant | Every accounted indicator has a named semantic time that is a stored PostgreSQL timestamp of the obligation; an obligation belongs to the cohort hour of that time and to no other; a reported window is a sum over final cohort hours computed in the database (AOA-18, AOA-20, AOA-21; SLI-R-12, SLI-R-13) |
| Authoritative source and boundary | Obligation records (origin and closing times); hourly cohort totals; immutable final cohort rows; per-hour correction counters. Prometheus scrape time and fold commit time are not inputs |
| Duplicates, retry, replay | One obligation, one cohort, by the record's primary key and the single open-to-closed transition |
| Crash, cleanup, restore | A fold crash leaves an hour not final; it finalizes on a later fold. Source deletion before registration: AOA-11. Restore: epoch change; the hours from restore point to activation unmeasured (AOA-14) |
| Completeness and finalization | AOA-20 (F1 … F5): time past the hour plus the largest boundary plus a grace; a completeness fold after that; upstream streams final; no unclassified pair; no unmeasured interval. An hour is not final while a visible older observation can still be registered into it. What cannot be bounded (a transaction that commits later than every completeness fold; a producer-assigned past `occurred_at`) is a counted correction (AOA-22), never a silent edit |
| States | `ESTABLISHED`, `NOT_ESTABLISHED`, `UNKNOWN` (AOA-24); neither of the last two exhausts or clears a budget (EB-05) |
| Retention | The 28-day figure is computed in PostgreSQL from final rows kept [CAND] 45 days; raw Prometheus retention (30 days) is not an input and no exemption from OD-7J-03 is taken. The 13-month history samples window and final-cohort Gauges; corrections are recorded, earlier samples are not rewritten (RET-7J-03) |
| Privacy and cardinality | No cohort hour is ever a label; exported series are window sums by `indicator`, `scope`, `part` (§9.1). Seven metrics added (M-289 … M-295); worst case recomputed as 43,683 series |
| Implementation, gate, tests | IR-7J-41, IR-7J-47; AG-7J-13; VT-7J-87 (A – D), VT-7J-88 (E), VT-7J-89 (finalization, corrections) |
| Residual | RR-7J-11: a reported window can be restated by a later correction; the restatement is counted and visible |

The five counterexamples. `W` is a 28-day window starting at `T0`; "old" is `x − x offset 28d` on the fold-time counter.

| # | Scenario | Expected membership (event time) | Old result | New result |
|---|---|---|---|---|
| A | Completed one minute before `T0`; fold commits ten minutes after `T0` | Not in `W` | Counted in `W` (+1) | In the cohort hour before `T0`; not in `W` |
| B | Completed one minute before the end of `W`; fold commits after the evaluation | In `W` | Missing from `W` (−1), counted in the next window instead | Its hour is not final at the evaluation, so `W` as reported ends before it; it is in the window once its hour is final |
| C | One fold batch inside `W` holds 100 observations from three days before `T0`, 100 from one day before `T0` and 100 from today | 100 in `W` | 300 in `W` | 100 in `W`; the other 200 in their own earlier hours |
| D | The observer is down from three hours before `T0` to one hour after; it catches up before any source row expires; 3,000 obligations completed in those three hours | None of the 3,000 in `W` | All 3,000 in `W` | Each in its own hour before `T0`; while the watermark lags past its limit the state is `UNKNOWN`; afterwards correct |
| E | Mid-window the database is restored 3 hours back; 10,000 observations of the lost timeline vanish; activation 2 hours later | The lost-timeline obligations happened but are no longer recorded anywhere | The counter falls by 10,000: a plain difference under-counts by 10,000; `increase()` would treat the fall as a reset and add the whole counter | Five cohort hours unmeasured and excluded from both sums; with 5 of 672 hours (0.7%) the window stays `ESTABLISHED` with 5 unmeasured hours shown; above 2% it is `NOT_ESTABLISHED` |

**P1-7J-R07 — Accounting-stream blindness.**

| Item | Evidence |
|---|---|
| Original failure | The expected registry covered sources, components and shards. AL-59 compared `time()` with a stream's last completeness fold only while that series existed; a stream whose series disappeared produced no alert, while the `accounting` source stayed fresh |
| Existing 7J rule at fault | EVD-08 and AL-59 of the second submission; AOA-12 |
| Corrected invariant | Every mandatory accounting stream has, per fold kind, an expected series generated from the trusted registry by the rule evaluator; a fold with no fresh counterpart is reported with its `stream` and `fold_kind`, independently of every other stream and of the `accounting` source (EVD-13) |
| Authoritative source and boundary | The code-owned registry (EVD-08); rule evaluation in Prometheus; the fold's own durable run record behind M-283 |
| Idle versus absent | A fold with nothing to do commits a run record and advances M-283, so an idle stream is fresh. Only a fold that did not run, did not commit or was not exported goes stale |
| States | `DISABLED` with reason and expiry before activation; `EXPECTED` from activation; removal only by a governed change that also retires its indicators (EVD-10, EVD-13) |
| No false health | A reported figure is never taken from a series that is not fresh (EVD-04); the window state is itself a series, and its absence is `UNKNOWN` (M-291, AOA-24, AL-60) |
| Severity | AL-59 (a) SEV2; SEV1 for the routine fold of `outbox_publication` or `consumer_completion` inside the safety margin of registration loss |
| Evaluator failure | If the rule evaluator or Alertmanager is down the expected series do not exist either; that is the external dead-man's case (MON-04, AL-54), unchanged |
| Security and labels | `stream` (6 values), `fold_kind` (2), `state`: closed, in the allow-list |
| Implementation, gates, tests | IR-7J-42 extended; AG-7J-01, AG-7J-13; VT-7J-90, VT-7J-91 |
| The counterexample, prevented | All sources fresh; five of six streams folding; `consumer_completion` stops; its M-283 samples go stale and vanish. `platform_telemetry_expected_stream{stream="consumer_completion", fold_kind="routine", state="EXPECTED"}` and the `completeness` one still exist. The right-hand side of `unless on (stream, fold_kind)` contains ten fresh (stream, fold kind) pairs and neither of these, so AL-59 (a) returns exactly these two series. AL-50 stays silent for `accounting`. SLI-17's window state goes `UNKNOWN` and no figure is reported |
| Residual | RR-7J-10: a stream omitted from the registry cannot alert; the registry is generated beside the stream definitions |

**Regression of the first review's findings.**

| Finding | Status after this round |
|---|---|
| R01 (histogram accounting) | Holds and is strengthened: uniqueness is the obligation record's primary key; replicas, restart, cleanup and late commits as in §34.4, with "marker" read as "obligation record". The fold-time histograms remain exact in count and are now explicitly not a window source |
| R02 (missing-source, per-shard) | Holds; extended to accounting streams (EVD-13, AL-59) |
| R03 (SLI boundaries, classes) | Holds. SLI-04 versus SLI-17 unchanged in meaning; SLI-01, -11, -17 are now cohort ratios; SLI-12a, -12b, -12c unchanged in classes, cohort by closure time |
| R04 (7H taxonomy) | Holds; unchanged |
| Minor-7J-R01 (hash representation) | Holds; unchanged |
| Minor-7J-R02 (OD-7J-10 traceability) | Holds; unchanged |

**Regression of the nineteen areas named by the second review.**

| # | Area | Result |
|---:|---|---|
| 1 | 88 incoming handoffs | Unchanged: 86 closed, 2 blocked |
| 2 | OD-7J-01 … OD-7J-10 | Unchanged; no new decision was needed (see the note below) |
| 3 | Unsafe labels | None added; a cohort hour is never a label |
| 4 | Cardinality | 261 metrics; 43,683 worst-case series against the 60,000 candidate budget |
| 5 | Observer least privilege | `EXECUTE` on read, fold and window functions only; no content read (AOA-08) |
| 6 | `XINFO STREAM` restriction | Unchanged |
| 7 | End-to-end versus handler-only latency | Unchanged in meaning (§10.3) |
| 8 | Unresolved obligations after outbox cleanup | AOA-19; M-086; VT-7J-83 |
| 9 | Three send states | Unchanged |
| 10 | Uncounted releases | Unchanged |
| 11 | Audit versus telemetry | Unchanged; accounting relations are neither |
| 12 | Erasure and legal-hold monitoring | Unchanged; AOA-25 for accounting records |
| 13 | Sealed-content monitoring | Unchanged |
| 14 | In-region telemetry; alert egress | Unchanged |
| 15 | Paging and runbooks | AL-15, AL-59 revised; AL-60 added; RB-17 |
| 16 | Candidate versus binding objectives | Unchanged; every objective PROPOSED |
| 17 | Error budget under missing evidence | EB-02, EB-05 with AOA-24 |
| 18 | Restricted access; sampling | Unchanged |
| 19 | 7K and 7L handoffs | HE-7K-7J-14 extended; HE-7L-7J-02, -09 ranges |

**Owner-decision note.** The correction adds a relation that stores `event_id` with `occurred_at` and adds no retention beyond what frozen relations already apply to the same identifier (AOA-23); it selects no product, sets no objective and changes no event semantics: `occurred_at` remains the event time by 7A OBS-04 and 7D OBS-7D-13. The author therefore raised no new owner decision. If the reviewer or the owner reads AOA-23 or the hourly cohort granularity as a material retention or policy choice, it is the one place a decision would attach.

**Second-review ledger.**

| ID | Severity | Status (author's reading; the re-review decides) |
|---|---|---|
| P1-7J-R05 | P1 | Remediated in the design; gated by AG-7J-13 |
| P1-7J-R06 | P1 | Remediated in the design; gated by AG-7J-13 |
| P1-7J-R07 | P1 | Remediated in the design; gated by AG-7J-01, AG-7J-13 |

### 34.6 Third independent freeze-gate review: findings and remediation

The independent review of the third submission (3,485 lines, `a1af3269…577e6a6d`) found R05 … R07 substantially resolved and raised three further P1 defects: P0 0, P1 3, new Minor 0. All three are accepted as stated. Each is a contradiction inside §6.4 as the author rewrote it in the second round. Everything below is static design evidence. No test was executed. **This section is the record of the third round and is not rewritten.** Its R10 evidence describes an eligibility interval that began at `created_at` and status edges read from audit rows; both were found wrong by the fourth review and are replaced by §34.7 and AOA-27 as it now stands. Its owner-decision note is superseded: the choices it lists were put to the owner and decided as OD-7J-11 … OD-7J-13.

**P1-7J-R08 — Unmeasured UTC-hour cohorts in the 28-day window.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Failing scenario | A restore leaves five consecutive UTC hours whose observations cannot be reconstructed. F5 refused to finalize an hour overlapping an unmeasured interval; the window was "the trailing 672 final cohort hours"; AOA-24 and SLI-R-04 counted unmeasured hours "among them". Read one way, the watermark stopped at the first of the five hours for ever and every window was `UNKNOWN`. Read the other way, the 672 final hours skipped the five, reached five hours further into the past, covered more than 28 days of wall time and always had zero unmeasured hours, so a window that had lost five hours of an incident reported `ESTABLISHED` |
| 2 | References | 7J AOA-11, AOA-12, AOA-14, AOA-20 (F5), AOA-21, AOA-24, SLI-R-04, SLI-R-13, EB-02, EB-05 as submitted. Owner condition: OD-7J-02 condition 5 (blindness is neither healthy nor a breach); OD-7J-01 condition 10 (measured, estimated and unavailable are never merged). Frozen: 7I JRN-12 (database incarnation; guarded functions refuse on a mismatch); 7D CLN-02 and 7I ACC-06 (source lifetimes); 7H MR-7H-07 |
| 3 | Corrected invariant | Every UTC hour of a stream has a ledger row. Assessment (`OPEN`, `FINAL`) and measurement (`MEASURED`, `UNMEASURED`) are separate. Hours are finalized in order, measured or unmeasured, so the final prefix has no gap. A window is the 672 consecutive hours ending at the watermark. An unmeasured hour is in the window, adds nothing to either sum and one to `unmeasured_hours`. A window with any unmeasured hour gives no verdict and moves no budget (AOA-12, AOA-20, AOA-21, AOA-24, AOA-26) |
| 4 | Identity and authoritative timestamps | Identity: (stream, UTC cohort hour). Permanent loss is proved from durable facts only: the start times of consecutive committed completeness folds against `R_min − m` (AOA-11), and the incarnation stored in the last run record against the one the running instance reports (AOA-14). All times are database times. No timeout, alert or operator statement makes an hour unmeasured |
| 5 | Database accounting and security boundaries | Hour ledger, append-only declarations, immutable final rows, append-only signed corrections, unattributed counts, run records (AOA-26). No identifier and no cohort hour leaves the database; the read function returns counts, a state and a window end per bounded scope. No login role has a table privilege; the observer has `EXECUTE` only |
| 6 | Concurrency and crash | One fold per stream at a time by its lock; declaration, finalization and counts commit in one transaction; a crash rolls all back and the next fold repeats the same deterministic decision from the same run records. In-order finalization is checked in the finalizing statement, so two replicas cannot finalize out of order |
| 7 | Duplicate and replay behaviour | A declaration for an interval already declared is not appended again (same stream, hours, cause and proving run records). Finalizing a final hour changes nothing: the row is immutable. A re-run fold is a no-op |
| 8 | Cleanup and retention | Accounting never delays cleanup (AOA-10); that is exactly why loss is possible and is declared. Ledger rows, declarations and corrections hold no identifier and are kept [CAND] 45 days (AOA-23); OD-7J-03 is not touched and no telemetry retention changes |
| 9 | Numerator and denominator | Both are sums over the measured hours of `[w − 672 h, w)` plus the signed corrections on those hours. An unmeasured hour's observed counts and corrections are in neither. `measured_hours + unmeasured_hours = 672` always. With `u` unmeasured hours: `u = 0` gives `ESTABLISHED`; `1 ≤ u ≤ 13` gives `ESTABLISHED_PARTIAL` (ratio shown as measured over `672 − u` hours; no verdict; no budget movement); `u > 13` or an unattributed obligation gives `NOT_ESTABLISHED`; an old watermark or absent evidence gives `UNKNOWN` |
| 10 | Future implementation requirements | IR-7J-41 (hour ledger, declarations, in-order finalization, incarnation check), IR-7J-47 (read function and its checks). No new telemetry product, store or metric: the existing metrics M-285 and M-290 … M-295 carry it |
| 11 | Activation gate | AG-7J-13 |
| 12 | Deterministic validation | VT-7J-92 (one hour), -93 (five hours after a restore), -94 (outage without loss), -95 (outage with loss), -96 (missing stream), -97 (late observation into an unmeasured hour), -98 (upstream unmeasured, downstream measured), -99 (rolling window; property test of the read function); VT-7J-51 and VT-7J-88 revised |
| 13 | The original failure, prevented | The answers below. Neither reading of the old text is possible now: the watermark crosses the five hours because they are finalized `UNMEASURED` (so no permanent `UNKNOWN`), and the window is defined by the clock, not by a count of usable hours (so no hour is skipped and none is borrowed from the past) |
| 14 | Residual | RR-7J-09 (a past-dated row lost unregistered outside a declared interval); RR-7J-13 (one unmeasured hour suspends verdicts for up to 28 days) |

The review's counterexample, answered. A restore is made to a point in the middle of hour `h`; the first fold after activation runs in hour `h + 4`; hundreds of later hours are fully measured; `w` is the watermark at the evaluation.

| Question | Answer |
|---|---|
| Which UTC hours belong to the window? | Exactly the 672 consecutive hours `[w − 672 h, w)` |
| Do the five missing hours count toward the 672? | Yes, for as long as they lie in that interval. They are never replaced by older hours |
| How are their counts represented? | Each has a final ledger row with measurement `UNMEASURED`, cause `RESTORE_GAP`, and `observed` counts kept for diagnosis. They are absent from every sum. They are not zero |
| Can the watermark advance across them? | Yes. Each is finalized `UNMEASURED` once F1 holds and a completeness fold has committed after the declaration; F2, F3 and F4 are not required. The later hours then finalize in order |
| What is `unmeasured_hours`? | 5 while all five are inside the window; then 4, 3, 2, 1, 0 as they leave it at its far end |
| `ESTABLISHED`, `NOT_ESTABLISHED`, `UNKNOWN`? | `UNKNOWN` from the restore until the watermark is back inside its lag. Then `ESTABLISHED_PARTIAL` (5 ≤ 13): the ratio is shown as measured over 667 of 672 hours, is not reported as met, and moves no budget. `ESTABLISHED` again when the last of the five has left the window. Had the gap been 14 hours or more: `NOT_ESTABLISHED` |
| Agreement with the approved policy | OD-7J-02 condition 5: the unmeasured hours are counted neither as healthy nor as a breach, and the window that contains them yields neither verdict |

Proof that missing source data cannot become a healthy objective. A window is reported met only in state `ESTABLISHED`. That state requires `unmeasured_hours = 0` over 672 consecutive hours (AOA-24). An hour whose observations were lost is either open, in which case the watermark stops before it and, once the lag bound passes, the state is `UNKNOWN`; or final and `UNMEASURED`, in which case it is counted in `unmeasured_hours` for every window that contains it. It cannot be final and `MEASURED`: F2 and F5 require a completeness fold that found nothing missing and no declaration over the hour, and a declaration is appended whenever the run records show that a row could have been deleted unseen or that the incarnation changed. It cannot be left out of the window, because the window is an interval of the clock. So no window that covers a lost hour is ever `ESTABLISHED`. The one case outside this argument is RR-7J-09.

**P1-7J-R09 — Three webhook milestones under one single-close identity.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Failing scenario | Delivery `D`: created T0, first claim T1, first admission T2, `DELIVERED` T3. The one record (`webhook_stages`, `D`) could be closed once (AOA-02). Closed at T1 it could never record T2 or T3; left open until T3 it either observed all three late in one fold or, on a crash-safe single compare-and-set, only one of them. "Three closing facts" contradicted "a second close changes nothing" |
| 2 | References | 7J AOA-01, AOA-02, AOA-04, AOA-13, the `webhook_stages` row, M-131, M-165, M-166 as submitted. Frozen: 7H T-04, T-04a, T-05 … T-11; DSM-07 H1 – H7; MR-7H-06 (unique (`delivery_id`, `claim_seq`) for claims and closures, unique (`delivery_id`, `claim_seq`, `admission_seq`) for admissions); §8.1 terminal statuses; MR-7H-07 |
| 3 | Corrected invariant | A stream has exactly one kind of closing fact. Each independently timed milestone is its own stream with its own record and its own single close: `webhook_first_claim`, `webhook_first_admission`, `webhook_terminal` (AOA-01, AOA-02, AOA-28) |
| 4 | Identity and authoritative timestamps | Identities (`webhook_first_claim`, `d`), (`webhook_first_admission`, `d`), (`webhook_terminal`, `d`). Origin for all three: the delivery's `created_at`. Destinations: `claimed_at` of the claim with `claim_seq = 1`; `admitted_at` of the admission with the lowest (`claim_seq`, `admission_seq`); the row's `completed_at`. All PostgreSQL timestamps written by 7H's own transactions |
| 5 | Database accounting and security boundaries | The fold reads sequence numbers, status and timestamps and no destination, configuration, body or secret column (AOA-04). It writes accounting relations only and contains no statement on any other relation, asserted by a body scan and proved by VT-7J-110. The observer principal has no table privilege |
| 6 | Concurrency and crash | Three primary keys, three compare-and-sets, the stream lock; a crash between discovery and commit rolls back record and totals together; two replicas produce one observation (AOA-06, AOA-07) |
| 7 | Duplicate and replay behaviour | A second or later claim has another `claim_seq` and is not read. A re-admission and later claims' admissions find the first-admission record closed. A terminal status has no exit; a public replay is a new delivery row with its own records. An uncounted release closes nothing |
| 8 | Cleanup and retention | A closed record needs nothing further from the delivery, so the purge of MR-7H-07 after the close changes nothing. An open record whose delivery is gone closes `SOURCE_GONE` with no observation, inside a declared gap only. Records follow AOA-23 and keep no identifier longer than a frozen relation does |
| 9 | Numerator and denominator | Not ratios: three histograms, Tier D, backing no objective. Each has at most one observation per delivery; M-165 and M-166 are accompanied by the count of deliveries that never reached the milestone, so observed plus never-reached plus open equals registered for each stream |
| 10 | Future implementation requirements | IR-7J-41 (three streams, their records and folds); IR-7J-42 generates their six registry entries from the stream table |
| 11 | Activation gate | AG-7J-13, with 7H MR-7H-06 (the claim and admission records do not exist today) |
| 12 | Deterministic validation | VT-7J-100 … VT-7J-110 |
| 13 | The original failure, prevented | Below |
| 14 | Residual | None specific. The stage timings include suspension time by design and are not objectives |

The counterexample, under the corrected model. Registration of `D` inserts three open records with `origin_at = T0`. A fold that sees the claim record with `claim_seq = 1` closes (`webhook_first_claim`, `D`) at T1 and adds one observation of T1 − T0 to M-165. A fold that sees the earliest admission closes (`webhook_first_admission`, `D`) at T2 and adds T2 − T0 to M-166. A fold that sees `DELIVERED` closes (`webhook_terminal`, `D`) at T3 and adds T3 − T0 to M-131 with `status = DELIVERED`. Each is the single open-to-closed transition of its own record, so AOA-02 holds for each, in whichever order and in however many folds the three become visible.

Stream catalogue, registry and labels after the change: eight streams (six before); sixteen expected-stream entries, each alerted on its own by AL-59 (a); `stream` label eight values; no new metric; bucket boundaries fixed per family, at most 12 (LBL-09); M-131 keeps `status` (3), M-165 and M-166 keep no label and gain a never-reached companion. Worst-case series recomputed: 44,133 (§9.4).

**P1-7J-R10 — Eligibility reclassification for SLI-11.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Failing scenario | `O` active; `D` created and registered `active_throughout`; cohort `H` counts `D` in its denominator; `O` suspended; `D` held with no counted attempt; `O` reactivated; first counted closure. SLI-11 said `D` "is moved, as a correction if its hour is final". The cohort totals were keyed by the dimensions stored at registration, and AOA-22 defined corrections for added obligations and for not-owed only, all positive. Nothing removed `D` from the `active_throughout` count, so `D` stayed in the denominator (counted as a platform miss) or, moved without a removal, was counted in both classes |
| 2 | References | 7J AOA-03, AOA-18, AOA-22, the `webhook_first_closure` row, SLI-11, SLI-R-03, M-145, M-167, M-168, M-290 as submitted. Frozen: 7H OD-7H-02, OD-7H-09; §8.1 ("held" is a derived condition, not a status); T-04, T-04a, T-09, T-10, T-11; DSM-05, DSM-07 H5; ADM-01, ADM-02, ADM-05 (G1 … G6); TEN-7H-08, TEN-7H-09; Trace 17. 7I OLC-01, OLC-03, OLC-06, OLC-10. `107_5B5` (the suspend and reactivate functions write `ORGANIZATION_SUSPENDED` and `ORGANIZATION_REACTIVATED` in the transition's transaction); `072_5J` (`occurred_at`, `idx_audit_action`); `003_5B` (`chk_orgs_status`) |
| 3 | Corrected invariant | Each delivery is counted in exactly one eligibility class of its one cohort hour at every committed state. Its class is decided by stored status evidence over a bounded decision interval and changes at most once, by one compare-and-set that moves its counts in the same transaction: in the hourly totals while the hour is open, as a `−1` and a `+1` correction once it is final (AOA-27, AOA-22) |
| 4 | Identity and authoritative timestamps | Identity: (`webhook_first_closure`, delivery `id`). Interval `[created_at, x)`, `x` the earliest of the first counted closure's `closed_at`, a cancellation's `completed_at`, and `decide_by = occurred_at + B` stored at registration. Evidence: the uncounted-release closure record of the delivery, decided under the organization row lock; and the organization's status-edge audit rows with their `occurred_at`. No observer clock and no fold time is an input |
| 5 | Database accounting and security boundaries | The record stores the class and a closed evidence code, never an organization. The fold reads `action_kind` and `occurred_at` of three audit action kinds for the delivery's organization and nothing else of the audit relation; it returns counts by `topic` and `eligibility`. The label set is unchanged (`eligibility`, two values) |
| 6 | Concurrency and crash | 7H's own ordering is kept: a claim or an admission and a status change are serialized by the organization row lock (ADM-02), and the fold only reads their committed records. The move is a compare-and-set under the stream lock; record and counts commit or roll back together. Suspension during an in-progress claim, during backoff and after the first closure are each decided in AOA-27 (d) |
| 7 | Duplicate and replay behaviour | A repeated suspend call is the frozen no-op and writes no audit row. Several edges, or an uncounted release and an edge together, still give one move. Reactivation never moves a delivery back. A re-run fold or a second replica finds the compare-and-set done |
| 8 | Cleanup and retention | Nothing is added to the delivery, its history or the organization. The record is purged under AOA-23 as before. The audit rows used are frozen audit evidence with their own retention; accounting copies none of their content |
| 9 | Numerator and denominator | Both are read from the tuple (`topic`, `active_throughout`): final counts plus signed corrections. A moved delivery leaves both at once (`−1 registered`, and `−1 good` if it had been counted good). `excluded_held` is the other tuple; the two sum to the registered deliveries of the hours. No value can be negative, because each `−1` belongs to a record that was counted `+1` in that tuple |
| 10 | Future implementation requirements | IR-7J-41 (the stored `decide_by`, the eligibility compare-and-set, signed corrections, the status-edge read); IR-7J-45 (M-145 excludes rows held at the read); IR-7J-47 (`excluded_held`, the non-negativity check) |
| 11 | Activation gate | AG-7J-13, with 7H MR-7H-06 and the lifecycle functions of 7I OLC-06 … OLC-11 |
| 12 | Deterministic validation | VT-7J-111 … VT-7J-121; VT-7J-75 revised |
| 13 | The original failure, prevented | Below |
| 14 | Residual | RR-7J-12: the stored edge time is the start of the status transaction, so a closure inside that transaction's span is classed held; and an edge visible only after the record's purge is not applied |

The counterexample, twice.

| Step | `H` still open | `H` already final |
|---|---|---|
| `D` registered | Totals of `H`: (`topic`, `active_throughout`) registered +1 | The same; then `H` is finalized with `D` counted there, open, valid and not good |
| `O` suspended inside `D`'s decision interval; the fold sees the edge (or the uncounted release) | One compare-and-set on `D`'s record. In the same transaction the totals of `H` change: `active_throughout` registered −1, `held_interval` registered +1 | One compare-and-set on `D`'s record. In the same transaction two entries are appended for `H`: `−1 registered` on `active_throughout`, `+1 registered` on `held_interval`, reason `ELIGIBILITY_RECLASSIFIED`. The final row is not touched |
| `O` reactivated | Nothing: the class does not move back | Nothing |
| First counted closure | The record closes; M-167 and M-168 observe it with `eligibility = held_interval`; the `held_interval` tuple's closed counts move, the `active_throughout` tuple's do not | The same; any good count is appended to the `held_interval` tuple only |
| SLI-11 denominator for `H` | `active_throughout` registered, which no longer contains `D` | Final count (contains `D`) plus corrections (−1) = without `D` |
| Excluded exactly once? | Yes: the compare-and-set succeeds once; a second fold, the other replica, or a second piece of evidence changes nothing | Yes, for the same reason; exactly one `−1` can exist for `D` |

What the correction deliberately does not do: if `O` is suspended only after `D` has passed `decide_by` unclosed, `D` is not moved. It had already missed the boundary while its organization was active, so its delay up to the boundary was not suspension delay. Excluding it would let a later, unrelated suspension erase a platform miss from the objective, and would allow reclassifications of hours older than any window. The time `D` then spends held is shown in M-126 and is counted against nothing.

**Regression of the earlier independent findings.**

| Finding | Status after this round |
|---|---|
| R01 (histogram accounting; durable identity; no double count) | Holds. Uniqueness is still the obligation record's primary key and single close; the three milestone histograms now have one record each, which removes the only place where one record fed several families |
| R02 (missing source, per shard, label-preserving absence) | Holds; unchanged. The expected-stream registry grows to sixteen entries by generation |
| R03 (SLI boundaries, disjoint sets) | Holds. SLI-11's included and excluded sets are now two tuples that partition the registered deliveries; SLI-12a, -12b, -12c unchanged |
| R04 (7H claim, admission and closure taxonomy; `UNCERTAIN`; counted versus uncounted) | Holds; unchanged. An uncounted release closes no milestone, spends nothing and is evidence of a hold only |
| R05 (obligation survives outbox cleanup; original `occurred_at`) | Holds. `origin_at` is still copied at registration; `webhook_fanout` may now also take it from the upstream obligation record, which holds the same `occurred_at` |
| R06 (event-time windows; no counter differences) | Holds and is completed: the window is an interval of event time, 672 consecutive hours, and no counter difference is used |
| R07 (accounting-stream blindness) | Holds; AL-59 (a) covers each of the sixteen entries. Eligibility evaluation, declaration and finalization are steps of the existing folds, so a failure of any of them makes that fold stale and is caught by the same alert |
| Minor-7J-R01 (raw and LF-normalized hashes) | Holds; §1.1 unchanged |
| Minor-7J-R02 (OD-7J-10 traceability) | Holds; unchanged |

**Regression of the areas the third review named.**

| Area | Result |
|---|---|
| Durable observation identity; no histogram double-counting; outbox-cleanup-safe records; original `occurred_at` | Preserved (AOA-02, AOA-03, AOA-19) |
| Event-time window semantics | Preserved and made exact (AOA-21) |
| Missing-source and missing-stream detection; per-shard Redis durability monitoring | Unchanged (EVD-08 … EVD-13; AL-09, AL-50, AL-51, AL-59) |
| 7H taxonomy, `UNCERTAIN`, counted versus uncounted attempts | Unchanged (§19.2) |
| OD-7J-01 … OD-7J-10; no unapproved target; rolling 28-day governance | Unchanged. No target was added or altered; the 2% tolerance and every other value remain [CAND]. EB-01, EB-02, EB-05 and EB-11 now say that a budget moves only on a fully measured window |
| In-region telemetry, restricted access, trace sampling | Unchanged |
| Label cardinality | No tenant- or event-derived label. `stream` 8, `part` 9, window `state` 4, `cause` 2, `kind` 5. 261 metrics; 44,133 worst-case series against the 60,000 candidate budget |
| Security monitoring; erasure journal; sealed-content monitoring; retention and legal-hold boundaries; evidence-preservation failure policy | Unchanged |
| Dashboards, alerts, runbooks | Dashboard I, AL-59 and AL-60 revised; FS-34 … FS-36 added; RB-17 unchanged |
| 7K and 7L handoffs | HE-7K-7J-01 (figure), HE-7K-7J-14 (extended); HE-7L-7J-02 and -09 (ranges) |
| Frozen Phase 7 contracts | None reopened. No column, trigger, function or event is added to 7H, 7I, the organization context or the audit relation |

**Owner-decision note.** No new decision was raised: the three corrections add no infrastructure, no retention, no identifier, no public API and no event, and change no numeric candidate. Three choices in them are the author's and are the places where a decision would attach if the owner or the reviewer reads them as policy. (1) A window with any unmeasured hour gives no verdict and moves no error budget (AOA-24, EB-05). This is stricter than the earlier text, which let a window with up to 2% unmeasured hours exhaust or clear a budget; the author reads OD-7J-02 condition 5 as requiring it. Its cost is RR-7J-13. (2) A delivery is excluded from SLI-11 as held only if the hold falls inside its decision interval, which ends at `occurred_at + B` (AOA-27). A hold that begins after the boundary was already missed excludes nothing. (3) The fold reads the time and kind of three organization-lifecycle audit actions as status evidence, across tenants inside a definer function, and stores none of it (AOA-27 b).

**Third-review ledger.**

| ID | Severity | Status (author's reading; the re-review decides) |
|---|---|---|
| P1-7J-R08 | P1 | Remediated in the design; gated by AG-7J-13 |
| P1-7J-R09 | P1 | Remediated in the design; gated by AG-7J-13 with 7H MR-7H-06 |
| P1-7J-R10 | P1 | Remediated in the design; gated by AG-7J-13 with 7H MR-7H-06 and 7I OLC-06 … OLC-11 |

### 34.7 Fourth independent freeze-gate review: findings and remediation

The independent review of the fourth submission (3,663 lines, `36d3a4f6…a236d635`) found R08 … R10 substantially successful and raised two further P1 defects in the eligibility model the author wrote in the third round: P0 0, P1 2, new Minor 0. It also required two owner confirmations. Both findings are accepted as stated. The owner decided OD-7J-11, OD-7J-12 and OD-7J-13 before the sections below were written (§29). **Everything in this section is architecture proof by static reasoning over the frozen documents and the migration SQL. No PostgreSQL concurrency test, and no other test, was executed**; the timing tests of §28.2 are requirements on the future implementation. Three things in this section were changed by the fifth round (§34.8): the cutoff is now read by the listing function before its evidence query, and no longer "read, then evidence read in one statement"; ratio bounds are diagnostics and never a verdict (OD-7J-14); and the fixture of counterexample B is restated so that it is physically possible.

**P1-7J-R11 — Authoritative organization-status ordering.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Source contradiction | AOA-27 of the fourth submission built an organization's status intervals from `audit.audit_events.occurred_at` of the lifecycle audit rows. 7H ADM-05 states its guarantees against `t_s`, "the commit time of a transaction that moves an organization out of `ACTIVE`". The audit column is not a commit time |
| 2 | Physical SQL evidence | `072_5J` L34: `occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`. `072_5J` L151 – L165: the `INSERT` of `audit.fn_insert_audit_event` lists sixteen columns and `occurred_at` is not among them, so the default applies; `NOW()` is the start time of the current transaction. No migration from `073` to `112` redefines that function or alters that table. `107_5B5` L368 – L396 (the installed body; it replaces `105_5B4`): `SELECT status … FOR UPDATE`, then `UPDATE … SET status = 'SUSPENDED', updated_at = NOW()`, then the audit insert, then return; the reactivate function is its mirror. `001_5B` `set_updated_at()` sets `updated_at = NOW()`. 6C §7.6: the tenant edges are a compare-and-swap `UPDATE` by `app_api` and "no bespoke `SECURITY DEFINER` function exists". So every stored time of a status change is the transaction's start; nothing stores the lock, the update or the commit; and nothing orders two transitions except the row lock itself |
| 3 | Original counterexamples | A, B and C below |
| 4 | Corrected invariant | No stored time is read as the instant a status change took effect. For each transition the evidence gives an order (a per-organization sequence assigned under the row lock, which is commit order) and two bounds on its commit, `locked_at < commit < hi`. Status is known outside those bands and unknown inside them. A delivery is classed held or active only on proof and `uncertain` otherwise (AOA-27 b – g) |
| 5 | Trusted timestamp and order source | The refined provenance row of 7I STP-11 (OD-7J-13; ERR-7J-15): sequence and `clock_timestamp()` after the lock, written in the transition's transaction. The upper bound is the next transition's `locked_at` or the fold's durable first sighting, a database clock value read after the row was visible. The evaluation instant `t_e` is read before the evidence is read |
| 6 | Transaction, locking and crash semantics | 7H's lock model is used as frozen and not extended: every lifecycle transition holds the organization row's exclusive lock to its commit (ADM-01, ADM-04; 7I OLC-13), so `k + 1` locks after `k` commits. The fold takes no lock on any organization or source row and never waits on one (AOA-09). A rolled-back transition leaves no row. A crash of the fold rolls back record, counts and sightings together. A restore returns evidence and accounting to one point; the gap hours are unmeasured (AOA-14) |
| 7 | Authorization and RLS | The fold reads no audit row, so the forced row-level security, the immutability and the grants of `audit.audit_events` are untouched and the cross-tenant audit read of the fourth submission is withdrawn. The provenance relation has no login-role privilege (7I STP-11). The one listing function is `SECURITY DEFINER`, Organization-owned, executable by the accounting folds' owner only, with a closed return shape that has no actor, cause, request, session, reason or key field; the observer principal cannot call it and cannot choose the organization (AOA-27 d; VT-7J-131) |
| 8 | Measurement and cohort impact | Three classes instead of two; `uncertain` is exported and bounded both ways. The cohort hour of a record never changes. A settled class is final, so lifecycle evidence that becomes visible later causes no post-final correction (item 14 C) |
| 9 | Correction and replay semantics | One compare-and-set per record; counts move with it in the hourly totals or as a signed pair; a re-run fold or the other replica changes nothing (AOA-27 j) |
| 10 | Future implementation requirement | IR-7J-48 (the erratum, in the migration that builds the 7I lifecycle functions); IR-7J-41 (settlement, sightings, three tuples); IR-7J-47 (bounds, evidence-fault state) |
| 11 | Activation gate | AG-7J-13: without the lifecycle evidence no delivery can be settled and SLI-11 is not reported |
| 12 | Deterministic validation | VT-7J-122 (A), -123 (rollback), -124 (B), -125 (C), -126 (band across the deadline), -129 (concurrent settlement), -130 (property test against the generator's commit log), -131 (authorization), -132 (evidence fault). They need a real PostgreSQL instance with controlled lock waits and commit delays, and none has been run |
| 13 | Residual | RR-7J-12: within a band the status is unknown, and the band is as wide as the lifecycle transaction's tail plus the fold's lag. The answer inside it is `uncertain`, never a guess |
| 14 | The original failures, prevented | Below |

Commit-visibility assumptions the proof rests on, stated so that they can be tested: (i) PostgreSQL holds a row's exclusive lock until the locking transaction ends; (ii) a statement at `READ COMMITTED` sees every transaction that committed before the statement began; (iii) `clock_timestamp()` returns the database server's current time and does not run backwards across the two reads compared (a clock step is detected by M-279 and makes the affected figures suspect, CLK-06); (iv) all of an organization's status changes go through functions that write the provenance row (7I OLC-01, OLC-11, OLC-12).

Counterexample A, a long-running suspension. Event at 12:00:00; `B` = 30 s; deadline 12:00:30. The transaction begins at 12:00:20, updates under the lock at 12:00:40 and commits at 12:00:41. Its audit row says 12:00:20. Fourth submission: an edge "inside the interval", so the delivery was excluded although the organization was `ACTIVE` until 12:00:41 and the miss was the platform's. Now: the audit row is not read; `locked_at` is 12:00:40, so the commit is after 12:00:40, after the deadline; every instant of the window is certainly `ACTIVE`; the delivery is `active_throughout`, valid and not good. An apparent pre-deadline `NOW()` cannot excuse it, because no rule consults it.

Counterexample B, lock wait and reversed timestamps. `B` begins at 12:00:10 and has not yet asked for the row lock; `A` begins at 12:00:11 and obtains the lock at 12:00:12; `B` asks for it at 12:00:12.5 and waits; `A` commits at 12:00:13; `B` then obtains the lock and commits at 12:00:14. The audit times are 12:00:10 for `B` and 12:00:11 for `A`: the reverse of the order in which the transitions took effect. **Audit timestamps do not necessarily reflect that order, and 7J does not claim they do.** The sequence numbers are assigned under the lock, so `A` has the lower one, and `locked_at` of `A` is before its commit, which is before `locked_at` of `B`.

Counterexample C, a late-visible transition. The lifecycle transaction locks at 12:00:25 and stays open; the fold evaluates at `t_e` = 12:01:00 and the hour is later finalized; the transaction commits at 13:30. Because it was not visible to a statement that began after `t_e` was read, it had not committed by `t_e`; the status was `ACTIVE` throughout the window, which ended at 12:00:30. The settled class `active_throughout` is correct and remains so. Effect on the final cohort: none. Effect on the correction ledger: no entry. The audit row dated 12:00:25, or earlier, appears to belong to the earlier interval and is irrelevant.

**P1-7J-R12 — Pre-fan-out suspension eligibility.**

| # | Item | Evidence |
|---:|---|---|
| 1 | Source contradiction | SLI-11 measures from the event's `occurred_at` (SLI-R-12; §10.2). AOA-27 of the fourth submission began the eligibility interval at the delivery's `created_at` and ended it at the earliest of the first closure, a cancellation and `decide_by`. A hold wholly before `created_at` was invisible to it |
| 2 | Physical and frozen evidence | 7H FAN-05: "Rows are created whatever the organization's status is. Organization status gates dispatch, not intent creation." 7H §14.2: fan-out still creates rows for a `SUSPENDED` organization. `063_5I`: the delivery row has `created_at` and no `occurred_at`. 7H FAN-04: the envelope `occurred_at` is the internal event's and never the fan-out or delivery-row time. So the delivery's creation time is neither the start of the measured interval nor a moment before which the organization's status is irrelevant |
| 3 | Original counterexample | Below |
| 4 | Corrected invariant | The eligibility window is the measured interval itself, `[occurred_at, occurred_at + B)`. The whole delivery is excluded when the organization is proved not `ACTIVE` at some instant of it; kept when proved `ACTIVE` throughout; `uncertain` otherwise (OD-7J-12; AOA-27 a, f) |
| 5 | Trusted timestamp and order source | `occurred_at` as preserved in the obligation record (`origin_at`, AOA-19); `decide_by` stored at registration; lifecycle evidence as in R11. `created_at`, `claimed_at`, `admitted_at` and `closed_at` do not enter the eligibility decision at all, so their own clock semantics cannot affect it |
| 6 | Transaction, locking and crash semantics | As R11 item 6. The decision uses no 7H record, so claim, admission, release and closure transactions are neither read for it nor ordered against lifecycle transitions by timestamp |
| 7 | Authorization and RLS | As R11 item 7 |
| 8 | Measurement and cohort impact | The delivery belongs to the cohort hour of `occurred_at`, as before. Its class is settled once, after the deadline. Delay accrued while the organization was active is not turned into a hold: a suspension that takes effect after the deadline moves nothing. Delay accrued while held does not count as a platform miss. The approved trade-off: a qualifying suspension excludes the whole delivery, including one already delayed or already closed in time (RR-7J-14); M-296 reports the active-time part where it can be measured |
| 9 | Correction and replay semantics | One settlement; counts move in the open hour's totals or as a `−1`, `+1` pair on a final hour; no duplicate contribution and no negative count (AOA-22; AOA-27 j) |
| 10 | Future implementation requirement | IR-7J-41; IR-7J-47 |
| 11 | Activation gate | AG-7J-13 |
| 12 | Deterministic validation | VT-7J-111 … VT-7J-121, VT-7J-127, VT-7J-128, each with exact event and transition times, initial and final class, numerator and denominator effect and the durable evidence required |
| 13 | Residual | RR-7J-14 (accepted by the owner); RR-7J-12 |
| 14 | The original failure, prevented | Below |

The counterexample.

| | Fourth submission | Corrected |
|---|---|---|
| Interval examined | `[created_at, min(first closure, decide_by))` = 12:00:25 to 12:00:30 | `[occurred_at, occurred_at + B)` = 12:00:00 to 12:00:30 |
| Evidence consulted | Audit rows at about 12:00:05 and 12:00:20; the latest at or before `created_at` is the reactivation | Transitions `k` (to `SUSPENDED`, `locked_at` 12:00:05) and `k + 1` (to `ACTIVE`, `locked_at` 12:00:20) |
| Finding | No non-`ACTIVE` instant in the interval | The organization is certainly `SUSPENDED` at 12:00:20: transition `k` committed before `k + 1` could lock, and `k + 1` had not committed when it read its clock |
| Class | `active_throughout` | `held_interval` |
| SLI-11 | Valid and not good (closure at 12:00:35): a platform miss, for a delivery that could not have been dispatched for 15 of its 30 seconds | In neither numerator nor denominator; `excluded_held` +1 |
| If the suspension had instead taken effect at 12:00:45 | — | `active_throughout`, valid and not good: the deadline had passed |

The event-to-deadline timeline, reconciled. Event occurrence opens the window. Fan-out and delivery creation happen inside or after it and do not move it; fan-out is not held by suspension (FAN-05), so a late fan-out for an active organization is the platform's delay and stays counted. A dispatch claim and an admission each commit only while the organization is `ACTIVE` under the row lock (ADM-01); an admission that finds it otherwise releases the claim uncounted (T-09), which spends nothing and closes nothing. The first counted closure closes the obligation and decides good or not good. Organization status transitions are placed on the same timeline by their bands. A terminal `CANCELLED` delivery with no counted closure closes `CANCELLED_UNATTEMPTED` and is valid and not good unless the delivery is excluded or uncertain.

**Regression of the earlier independent findings.**

| Finding | Status after this round |
|---|---|
| R01 (durable identity; no double count) | Holds; unchanged |
| R02 (missing source, per shard) | Holds; unchanged |
| R03 (SLI boundaries, disjoint sets) | Holds. SLI-11's population is now three disjoint tuples that sum to the registered deliveries |
| R04 (7H taxonomy; `UNCERTAIN` send state; counted and uncounted closures) | Holds; unchanged. The eligibility class `uncertain` is a different vocabulary on a different label and does not touch `send_state` |
| R05 (origin time survives outbox cleanup) | Holds; the window is anchored on that preserved `occurred_at` |
| R06 (event-time windows) | Holds; unchanged |
| R07 (per-stream blindness) | Holds. Settlement and sighting are steps of the existing `webhook_first_closure` folds; a failing lifecycle listing makes that fold stale and AL-59 (a) reports it |
| R08 (unmeasured hours; 672 consecutive hours) | Holds; now an owner decision (OD-7J-11). EB-05 additionally preserves the last established budget and freeze evidence |
| R09 (three milestone streams; one observation each) | Holds; unchanged |
| R10 (eligibility reclassification) | The signed move, its idempotence and its non-negativity hold. Its interval and its evidence were wrong and are replaced (R11, R12) |
| Minor-7J-R01, Minor-7J-R02 | Hold; unchanged |

**Regression of the areas the fourth review named.** Unchanged: obligation identity and durable accounting; outbox-cleanup-safe origin times; consecutive 672-hour windows; measured and unmeasured finalization; the three milestone streams; the 7H send-state taxonomy; candidate-only targets (no target was added or altered; `T_uncertain` is a provisional alert threshold); OD-7J-01 … OD-7J-10; regional residency; restricted log and trace access; privacy and legal-hold monitoring; the evidence-preservation failure policy; blindness alerts; runbooks. Changed: the `eligibility` label has a third closed value and `part` two more, neither tenant- nor event-derived; one diagnostic Histogram, M-296, is added; 262 metrics and 46,135 worst-case series against the 60,000 candidate budget; EB-05; AL-60; dashboards F and I; FS-35 rewritten and FS-37, FS-38 added.

**Fourth-review ledger.**

| ID | Severity | Status (author's reading; the re-review decides) |
|---|---|---|
| P1-7J-R11 | P1 | Remediated in the design under OD-7J-13; gated by AG-7J-13 with ERR-7J-15 (IR-7J-48) |
| P1-7J-R12 | P1 | Remediated in the design under OD-7J-12; gated by AG-7J-13 |

### 34.8 Fifth independent freeze-gate review: findings and remediation

The independent review of the fifth submission (3,829 lines, `7661317a…8795143d`) found R11 and R12 substantially resolved and raised one further P1 defect, two Minor findings and one owner-policy clarification: P0 0, P1 1, Minor 2. All are accepted as stated. The owner decided OD-7J-14 and OD-7J-15 before the sections below were written (§29). **Everything here is static reasoning about PostgreSQL's documented behaviour. No statement was run against a database, no concurrency or fault-injection test was executed, and VT-7J-133 … VT-7J-145 are requirements on the future implementation.** One thing in this section was changed by the sixth round (§34.9): the evidence query returns the organization's baseline, and the status before the retained transitions comes from that baseline and never from the current status; where this section speaks of "current status and `covered_from`" read it with AOA-27 (c), (d) as they now stand.

**P1-7J-R13 — The evaluation cutoff and the evidence snapshot.**

| Item | Evidence |
|---|---|
| Original defect | AOA-27 (e) said: "An evaluation reads the database clock as `t_e` and then reads the lifecycle evidence in one statement. Every transition that committed before `t_e` is visible to that statement." Read as one statement, the snapshot is taken when the statement starts and `clock_timestamp()` is evaluated whenever the executor reaches it, possibly much later. The second sentence is then false |
| Can the old text yield `active_throughout` in the review's counterexample? | Yes. Snapshot at 12:00:28; suspension commits at 12:00:29; the same statement reads the clock at 12:00:40. `t_e` = 12:00:40 is past `decide_by` plus the settle delay, so the record is settled; the snapshot holds no transition; the classifier certifies `ACTIVE` over 12:00:00 – 12:00:30. The organization was suspended from 12:00:29. The delivery is counted valid, and a legitimate hold is reported as a platform miss or, had it closed in time, as a platform success over an interval it could not have been dispatched in |
| Corrected protocol | (1) The listing function is `VOLATILE` and procedural and runs at `READ COMMITTED` or not at all. (2) Its first statement assigns `cutoff := clock_timestamp()`. (3) Its second statement is the single evidence query: transitions, current status and `covered_from` for one organization. (4) It returns the rows with `cutoff`. (5) The fold calls it as a statement of its own; the returned `cutoff` is `t_e`. (6) After the call has returned, a separate statement reads the clock for the sightings. (7) A record is settled only if `t_e` is at or after `decide_by` plus the settle delay; otherwise it waits (AOA-27 d, e, f) |
| Why every transition effective before the cutoff is visible | "Effective" is the instant `c` from which a new snapshot contains the transition. Statement (2) finishes before statement (3) starts. At `READ COMMITTED` each statement of a `VOLATILE` function takes a new snapshot when it starts. So the snapshot of (3) is acquired at an instant `s` with `t_e < s`. If `c < t_e` then `c < s`, and the transition is in the snapshot. Contrapositive: a transition not returned has `c > t_e` |
| What the proof does not use | Any clock value read during or after the evidence query; `statement_timestamp()` (receipt of the client's command: before the snapshot of that top-level statement, and unrelated to the order of an inner query's snapshot and a later commit); `transaction_timestamp()` and `NOW()` (transaction start); `locked_at` as a commit time; an audit timestamp |
| Nested functions and volatility | The fold and the listing function are both `SECURITY DEFINER` and both `VOLATILE`. A `STABLE` or `IMMUTABLE` function runs its queries on the snapshot of the statement that called it; a `VOLATILE` one takes a new snapshot for each of its own statements at `READ COMMITTED`. The migration's assertion block checks `provolatile` for both, and the fold never calls the listing from inside a larger query or reuses a result (VT-7J-144) |
| Stale transaction snapshots | At `REPEATABLE READ` or `SERIALIZABLE` the transaction's first statement fixes the snapshot, so step (3) could run on a snapshot older than `t_e`. The listing function checks the isolation level and raises |
| When visibility cannot be proved | It always can under the protocol. What can fail is the precondition: a `t_e` before the deadline plus the settle delay defers settlement; an unreadable, gapped, contradictory or expired evidence set gives `uncertain` (AOA-27 g) |
| What is preserved | Per-organization sequence and `locked_at` as a lower bound; the upper bound from the first sighting or the next transition's `locked_at`; the window `[occurred_at, occurred_at + B)`; whole-delivery exclusion on proof; a transition effective after the deadline excuses nothing; one settlement, transactional with its counts; the fold writes nothing outside accounting and reads lifecycle evidence only through the listing function |
| Long transactions, lock waits, rollback, delay, restore, clock | Traces D, E, G, A and F, J below. Clock discontinuity: every comparison is between values of the one database clock; values that contradict the order the row lock imposes are an evidence fault and give `uncertain` (AOA-27 g); a step is alerted by M-279 |
| Implementation requirement and gates | IR-7J-48 (the listing function as specified, with the catalogue assertion); IR-7J-41 (the fold's use of it); AG-7J-13 and AG-7J-14 |
| Tests | VT-7J-133 … VT-7J-142 (traces A – J), VT-7J-144 (declarations and isolation), on PostgreSQL 18 with advisory locks and deliberate delays to force each interleaving. None has been run |
| Residual | RR-7J-12 (the band is as wide as the fold's lag); RR-7J-15 (an `uncertain` delivery removes the verdict, accepted) |

The ten traces. In all of them the event occurred at 12:00:00, the deadline is 12:00:30 (`B` = 30 s, candidate) and the settle delay is 5 s, so a settlement needs `t_e` at or after 12:00:35. "Snapshot" is the instant the evidence query's snapshot is acquired; it is always after `t_e`.

| Case | Lifecycle lock; commit | Cutoff `t_e` | Snapshot | Evidence visible | Proven band | Class | SLI-11 effect | Invariant shown |
|---|---|---|---|---|---|---|---|---|
| A. Snapshot before the deadline; suspension commits inside it; clock read afterwards | 12:00:28.5; 12:00:29 | First fold 12:00:27.9. Second fold 12:00:41 | 12:00:28. Then 12:00:41.1 | First: none. Second: the suspension | Second: 12:00:28.5 to its sighting, about 12:00:41.2 | First fold: **not settled** (`t_e` before 12:00:35); the 12:00:40 clock read is not a cutoff. Second: `uncertain`, `TIMING_BAND` | Out of numerator and denominator; `uncertain_registered` +1; window `ESTABLISHED_UNCERTAIN` | A snapshot older than the deadline can never certify `ACTIVE`, because its cutoff is older still |
| B. Cutoff before the snapshot; suspension commits between them | 12:00:36.2; 12:00:36.5 | 12:00:36.0 | 12:00:37 | The suspension | From 12:00:36.2 | `active_throughout` | Valid; good or not good by its closure | A transition returned although effective after `t_e` is harmless: `locked_at` already places it after the window |
| C. Suspension commits before the cutoff; snapshot afterwards | 12:00:10; 12:00:11 | 12:00:36 | 12:00:36.1 | The suspension | (i) sighted at 12:00:12: 12:00:10 to 12:00:12. (ii) first sighted now: 12:00:10 to about 12:00:36.2 | (i) `held_interval`. (ii) `uncertain` | (i) Excluded; `excluded_held` +1. (ii) Uncertain counts +1 | Everything effective before `t_e` is visible; never `active_throughout` |
| D. Suspension begins before the deadline, commits after it | Begins 12:00:20; lock 12:00:31; commit 12:00:33 | 12:00:36 | 12:00:36.1 | The suspension | From 12:00:31 | `active_throughout` | Valid; not good if unclosed | A transition effective after the deadline excuses nothing, whatever its transaction's start time |
| E. Start times reversed relative to commit order | `A` (suspend): begins 12:00:11, lock 12:00:12, commit 12:00:13. `B` (reactivate): begins 12:00:10, asks for the lock 12:00:12.5, obtains it 12:00:13.1, commit 12:00:14 | 12:00:36 | 12:00:36.1 | Both, `A` with the lower sequence | `A`: 12:00:12 to 12:00:13.1. `B`: from 12:00:13.1 | `held_interval` (certainly `SUSPENDED` at 12:00:13.1) | Excluded; `excluded_held` +1 | Order comes from the lock, not from transaction-start times |
| F. A transition commits after the snapshot and before a later clock read | 12:00:29; 12:00:37 | 12:00:36 | 12:00:36.1; later clock read 12:00:40 | None | None for this record: not returned, so effective after 12:00:36 | `active_throughout`, which is true: `ACTIVE` until 12:00:37 | Valid | The later clock read is a sighting time only, never a cutoff; the record is not revised |
| G. Rollback after the lock | 12:00:10; rolled back 12:00:12 | 12:00:36 | 12:00:36.1 | None; no row, no sequence number | None | `active_throughout` | Valid | A transition that never committed leaves no evidence |
| H. Fold crashes between evidence and commit | 12:00:10; 12:00:11 | 12:00:36, lost. Next fold 12:00:50 | 12:00:36.1, lost. Then 12:00:50.1 | Second: the suspension | As case C with the sighting that exists | One settlement, by the second fold | Counted once | Record, counts and sightings commit together or not at all |
| I. Two replicas settle concurrently | 12:00:10; 12:00:11 | 12:00:36 and 12:00:36.3 | One each | The suspension, in whichever runs | That of the fold that commits | One class, from the committing fold | Counted once | Stream lock and compare-and-set: exactly one settlement |
| J. Restore invalidates sightings or evidence | 12:00:10; 12:00:11; restore to a point `P` | After activation | After activation | What had committed before `P` | Sightings after `P` are gone and are taken again, later: wider, never narrower | Settled records keep their class. A record whose window overlaps `P` lies in the gap hours | Gap hours `UNMEASURED`; nothing inferred about the lost timeline | Evidence, sightings and accounting are restored to one point; loss only widens uncertainty |

**Minor-7J-R03 — Zero denominators.** Accepted. The ratio and both bounds are defined only when the eligible tuple's valid count is positive; both bound denominators are then at least that count. With no proven-eligible delivery (no traffic; all held; all uncertain) the ratio and the bounds are absent, no verdict is given, no budget figure is computed and the last established budget state stands. Nothing is reported as 0/0, `NaN`, infinity or 100% (AOA-27 h; AOA-26 f; SLI-11; EB-05; VT-7J-130, VT-7J-143).

**Minor-7J-R04 — Lock-wait ordering in VT-7J-124.** Accepted. The fixture had `B` waiting for a lock that `A` had not yet taken. It now reads: `B` begins first and has not asked for the lock; `A` begins, locks; `B` asks and waits; `A` commits; `B` locks and commits. `B`'s audit `NOW()` still precedes `A`'s although `B` takes effect second. The same correction is made to counterexample B of §34.7 and is used by trace E and VT-7J-137.

**Owner-policy clarification, decided as OD-7J-14.** The two-tier reading of OD-7J-13 condition 19 is withdrawn. A window whose measured hours hold a delivery settled `uncertain` on a timing band is `ESTABLISHED_UNCERTAIN`: eligible counts, uncertain counts, the ratio and both bounds are published; no verdict is given and no budget moves until that cohort hour has left the window (AOA-24; AOA-27 h; EB-05; RR-7J-15).

**Lifecycle-provenance lifetime, decided as OD-7J-15.**

| Question | Disposition |
|---|---|
| What is it, in 7I's terms? | The STP-11 provenance row of an organization status transition, class `PID`, on a relation no login role can touch. It is not telemetry. OD-7J-03 does not govern it, and 7J's retention rules for metrics, traces and logs do not apply to it. 7I's retention matrix has no row for it |
| What does accounting need, and for how long? | Evidence for a delivery's window is needed once, at settlement. After that the class, the basis and `t_e` are in the obligation record, which holds no organization. A settlement matters to a reported figure only while the delivery's cohort hour can be in a window, and to any stored figure only while that hour's rows exist (AOA-23, [CAND] 45 days) |
| Minimum | No transition's evidence is removed sooner than [CAND] 45 days after its `locked_at`. This is a candidate for 7K to validate, not a guarantee |
| Ordinary settlement | Seconds to minutes after the deadline. Covered |
| Late registration (a producer transaction that commits late; a past-dated `occurred_at` such as EV-079) | Hours. Covered |
| Observer outage without loss | Bounded by `R_min − m`, about 7 days for these streams, before a registration gap is declared. Covered |
| Observer outage with loss | The hours are `UNMEASURED` whatever the lifecycle evidence says |
| Recovery and replay | **Not bounded by 45 days.** A parked webhook-engine case never ages out (7G PRT-02); a fan-out performed by an authorized replay months later creates a delivery whose event, and so whose window, is months old. Its evidence may be gone: the delivery is settled `uncertain`, basis `EVIDENCE_UNAVAILABLE`. Its cohort hour is older than every reported window and than the retained hourly rows, so no reported or stored SLI-11 figure depends on its class; it is still registered, closed and observed in the fold-time histograms. **The 45 days are therefore sufficient for every delivery that can enter a reported window, and insufficient to classify older ones, which no window uses.** If 7K finds a case in which a delivery older than the evidence can still enter a reported window (a finalization lag approaching 17 days without the window being `UNKNOWN`), a longer bounded period goes to the owner with its privacy, cost and reliability implications before it is adopted |
| Unresolved deliveries | A delivery that stays open for months was settled at its deadline; it needs no evidence afterwards |
| Absence | Never read as `ACTIVE` or as `SUSPENDED`. The listing reports `covered_from`; a window that begins before it is `EVIDENCE_UNAVAILABLE` (AOA-27 g) |
| Maximum; indefinite retention | 7J sets no maximum and requires nothing kept indefinitely. The sequence counter survives removal of old rows as a number, not as evidence. The final, finite period is 7I's and the Organization owner's, reconciled in 7L |
| Erasure, backup, restore, preservation | 7I's rules for `PID`-class evidence. A restore returns evidence and accounting to one point (trace J). An organization erasure that removes these rows leaves any unsettled record `uncertain`. A preservation need is met by 7I's own authorized mechanisms; 7J adds no hold and no exemption (OD-7J-09) |
| Region and exposure | The rows stay in the regional database; they are read only inside the listing function; no organization, transition or actor identifier is a label or is exported (LBL-01) |
| Activation | AG-7J-14 is closed until the final policy is governed and the 45-day candidate validated |

**Regression of the earlier independent findings.**

| Finding | Status after this round |
|---|---|
| R01 – R07; Minor-7J-R01, -R02 | Hold; unchanged |
| R08 (unmeasured hours; 672 consecutive hours) | Holds; unchanged. The window now has a fifth state, which like `ESTABLISHED_PARTIAL` carries no verdict |
| R09 (three milestone streams) | Holds; unchanged |
| R10 (signed eligibility corrections) | Holds; unchanged |
| R11 (lifecycle ordering) | Holds. Sequence, `locked_at` as a lower bound, and the upper bound are unchanged; the cutoff they are evaluated against is now proved to precede the evidence snapshot |
| R12 (event-to-deadline window; whole-delivery exclusion) | Holds; unchanged |

**Regression of the areas the fifth review named.** Unchanged: durable histogram accounting; outbox-cleanup-safe origin times; strict missing-evidence handling; per-stream blindness; per-shard durability monitoring; the 7H send-state taxonomy; candidate-only targets (none added or altered); restricted access; trace sampling; security monitoring; telemetry retention and legal-hold rules; monitoring resilience. Changed, narrowly: AOA-24, AOA-26 (f), AOA-27 (d) – (i), SLI-11, SLI-R-04, EB-05, M-291 (a fifth state value; 46,227 worst-case series), AL-60, dashboard I, FS-39, VT-7J-124, -126, -130 and the new VT-7J-133 … -145, ERR-7J-15, IR-7J-41, -47, -48, AG-7J-13, the new AG-7J-14, RR-7J-15, HE-7K-7J-01, -14 and HE-7L-7J-05, -07, -09. No label derived from a tenant or an event was added.

**Fifth-review ledger.**

| ID | Severity | Status (author's reading; the re-review decides) |
|---|---|---|
| P1-7J-R13 | P1 | Remediated in the design; gated by AG-7J-13 and AG-7J-14 |
| Minor-7J-R03 | Minor | Corrected |
| Minor-7J-R04 | Minor | Corrected |

### 34.9 Sixth independent freeze-gate review: findings and remediation

The independent review of the sixth submission (3,969 lines, `a0ef8af9…26498e27`) closed R13 and both Minor findings in design and raised one further P1 defect in the same area: P0 0, P1 1, new Minor 0. It is accepted as stated. No new owner decision was needed (see the note at the end). **Everything here is static reasoning. No statement was run against a database, and VT-7J-145 … VT-7J-160 are requirements on the future implementation.**

**P1-7J-R14 — The status at the start of a window after earlier transitions were removed.**

| Item | Evidence |
|---|---|
| Original contradiction | AOA-27 (d) returned the transitions in the requested range and the last one before it, the current status, and `covered_from`. IR-7J-48 said the status before the retained range "is given by the earliest retained transition's from-state or, where none is retained, by the current status". The earliest retained transition can lie after the range, where (d) did not return it; and AOA-27 (e) said the status was "`ACTIVE` before the first transition". `covered_from` was described only as "the instant from which the retained evidence is complete", with no rule for how it is set |
| The counterexample under the old text | Day 0 suspension removed; event on day 50; reactivation on day 59; evaluation on day 60. The query returns no transition in the range and none before it; the day-59 row is after the range and is not returned; the current status is `ACTIVE`; (e) reads "no transition" as `ACTIVE`. The delivery is settled `active_throughout` although the organization was suspended throughout: a held delivery is counted as a platform miss |
| Corrected invariant | The status at the start of a window is established only by a retained transition before it or by the organization's baseline, and the baseline says only what was proved under the organization row lock. The current status is never a past status. Where neither establishes it, the class is `uncertain` (AOA-27 c, d, e, g) |
| The baseline | `base_seq`, `base_state`, `covered_from`: every transition above `base_seq` is retained, and from `covered_from` until transition `base_seq + 1` takes effect the status was `base_state`. Written as sequence 0 under the row lock with the status read there; advanced only by the removal function |
| How `covered_from` is set and why it never over-claims | At installation: the clock read while the row lock is held; no transition can commit while it is held, so the status read is the status at that instant and until the next transition. At removal of a prefix ending at `k`: `u_k`, which is the `locked_at` of `k + 1` (transition `k` had committed before `k + 1` could lock) or the `confirm_at` of `k` (read under a share lock that no uncommitted lifecycle transaction can coexist with). In both cases transition `k` had taken effect before `u_k`, and no transition above `k` had taken effect at `u_k`: the status at `u_k` is the to-state of `k`. So the baseline's statement is true from `u_k` forward. It is the earliest instant *proved*, which is later than the earliest instant at which the status actually held, and unrelated to the time of the earliest retained row |
| What the query now guarantees | The baseline; the last retained transition before the range; all in the range; the first after it. With these the fold checks continuity (sequence `base_seq + 1`, from-state equal to `base_state`, each from-state equal to the preceding to-state) and knows where `base_state` ends |
| The counterexample, closed | Day 1: the maintenance pass confirms sequence 1 (`confirm_at` = day 1). Day 46: `confirm_at` is older than 45 days; the pass removes sequence 1 and writes the baseline (1, `SUSPENDED`, day 1). Day 59: sequence 2, from `SUSPENDED` to `ACTIVE`. Day 60: the listing returns that baseline and sequence 2 as the first transition after the range. Sequence 2 is `base_seq + 1` and its from-state equals `base_state`. Status is certainly `SUSPENDED` from day 1 to the `locked_at` of sequence 2, which contains day 50 to day 50 + `B`: `held_interval`. The current status is not consulted. If the pass had never run, sequence 1 would still be retained and would precede the window: same class. If the baseline's `covered_from` were later than day 50 for any reason: `EVIDENCE_UNAVAILABLE`, not `ACTIVE` |
| In-flight, committed, rolled-back and later-removed first transition | Not yet committed: not returned; it took effect after the cutoff (R13), so `base_state` holds to the cutoff. Committed: returned, with its band. Rolled back: no row, no sequence number used. Later removed: only once its own proving instant is older than the lifetime, and it then becomes the baseline |
| Concurrent removal | Deletion and baseline update are one transaction; the evidence query has one snapshot; it sees the state before or after. The later state proves less, never something different (AOA-27 i). A settled record is not revisited |
| Authorization | Unchanged in kind: the fold reads through the one listing function; the observer principal holds no privilege on the organization, provenance, baseline or audit relations; the result is bounded to the range plus two transitions and the baseline, with closed state codes. The maintenance function is the Organization context's, not 7J's; the fold cannot remove, confirm or write anything outside accounting |
| 7H locking | The maintenance function takes the organization row's share lock first and with `SKIP LOCKED`, as 7H's claim does. It conflicts only with a lifecycle transition, which it skips or which waits for it briefly; it never blocks a claim or an admission, and it holds no lock a lifecycle function waits for other than that one (7H ADM-01 … ADM-04; 7I OLC-13) |
| Preserved | Sequence and from/to states; `locked_at` as a lower bound; bands; the cutoff-before-snapshot protocol; one settlement; immutable final rows; signed corrections |
| Implementation requirement; gates | IR-7J-48 and ERR-7J-15 extended; AG-7J-13, AG-7J-14 |
| Tests | VT-7J-145 … VT-7J-160. None has been run |
| Residual | RR-7J-16: conservative coverage; the latest transition's evidence can live up to about twice the minimum |

The fifteen scenarios. `B` = 30 s; the requested interval is always `[occurred_at, occurred_at + B)`; "lifetime" is the [CAND] 45 days. In every row the error budget behaves as the window state dictates (EB-05): a proved class contributes normally; any `uncertain` class leaves the window without a verdict and the last established budget state preserved.

| Case | Event and interval | Retained; removed | Baseline (`base_seq`, `base_state`, `covered_from`) | Visible transitions; state bounds | Class | SLI-11 treatment | Test | Why no false class |
|---|---|---|---|---|---|---|---|---|
| A. Starts while `ACTIVE` | Day 1 | None; none | (0, `ACTIVE`, installation) | None; `ACTIVE` from installation to the cutoff | `active_throughout` | Valid; good or not by its closure | VT-7J-146 | The status was read under the row lock, not assumed |
| B. Starts while `SUSPENDED` | Day 1 | Sequence 1 on day 2; none | (0, `SUSPENDED`, installation) | Sequence 1 after the range; `SUSPENDED` to its `locked_at` | `held_interval` | Excluded; `excluded_held` +1 | VT-7J-147 | Installation does not presume `ACTIVE` |
| C. No transition since the baseline | Any day after `covered_from` | None; none or some | As it stands | None; `base_state` to the cutoff | By `base_state` | Valid, or excluded | VT-7J-148 | Continuity is proved forward from the baseline |
| D. Earlier `SUSPENDED` removed; later `ACTIVE` retained after the interval | Day 50 | Sequence 2 (day 59); sequence 1 (day 0) | (1, `SUSPENDED`, day 1) | Sequence 2 as first after the range; `SUSPENDED` from day 1 to day 59 | `held_interval` | Excluded | VT-7J-149 | The successor is returned by contract and continues the baseline; current status unused |
| E. Earlier `ACTIVE` removed; later `SUSPENDED` retained | After `covered_from` | Sequence 3; sequences 1, 2 | (2, `ACTIVE`, confirmation of 2) | Sequence 3 after the range | `active_throughout` | Valid | VT-7J-150 | `ACTIVE` is proved by the baseline, not by absence |
| F. Several retained transitions straddle the interval | Day 50 | Before, inside, after; older ones | Any earlier | Last before, all inside, first after; bands | By the bands | By class | VT-7J-151 | The baseline is not needed and is not used |
| G. From-state disagrees with the baseline | After `covered_from` | Sequence 5 from `SUSPENDED`; older ones | (4, `ACTIVE`, …) | Chain broken | `uncertain`, `EVIDENCE_FAULT` | Neither population; window `NOT_ESTABLISHED` | VT-7J-152 | Two accounts conflict; neither is chosen |
| H. Earliest retained transition in a band | Window meets its band | Sequence `base_seq + 1`; older | Covers the window's start | Band from its `locked_at` to its sighting | `uncertain`, `TIMING_BAND`, unless a certain non-`ACTIVE` instant is in the window | Neither population; `ESTABLISHED_UNCERTAIN` | VT-7J-153 | Bands apply to it as to any transition |
| I. Removal concurrent with the read | Any | Before or after the removal | Old or new | One snapshot; no mixture | Same proved class, or `EVIDENCE_UNAVAILABLE` after | By class | VT-7J-154 | Removal is atomic and only reduces what is proved |
| J. Fold crash after the evidence | Any | — | — | Evidence lost with the transaction | Settled once, by the next fold | Counted once | VT-7J-155 | Nothing is committed from a crashed fold |
| K. Two folds race | Any | — | — | Each its own snapshot | One settlement | Counted once | VT-7J-156 | Stream lock and compare-and-set |
| L. Restore keeps an older baseline, loses the latest transition | Around the restore point | As of the restore point | As of the restore point | Consistent with the restored organization row | Settled records keep their class | Gap hours `UNMEASURED` | VT-7J-157 | One restore point for all of it; the lost transition is not inferred |
| M. Coverage begins after `occurred_at` | `occurred_at` before `covered_from` | Any | `covered_from` inside or after the interval | Start of the interval not established | `uncertain`, `EVIDENCE_UNAVAILABLE` | Neither population; `NOT_ESTABLISHED` | VT-7J-158 | Partial coverage certifies nothing |
| N. Transition commits after the cutoff, before the query completes | After `covered_from` | Possibly that transition | Covers the start | Returned with `locked_at` after the interval, or not returned | Proved class | By class | VT-7J-159 | R13 protocol; the baseline gives the start |
| O. Interval older than the retained coverage | 90 days old | Recent; older | `covered_from` about 45 days old | — | `uncertain`, `EVIDENCE_UNAVAILABLE` | Neither population; its hour is outside every window | VT-7J-160 | Expired evidence is never read as a status |

**Compatibility with OD-7J-15.**

| Point | Disposition |
|---|---|
| 1. Removal authority | The Organization context's guarded maintenance function, under 7I's rules for the provenance relation. Never the fold, the observer or any telemetry component |
| 2. Finite lifetime | A transition's evidence is kept until the instant that proves it took effect is older than the lifetime: [CAND] 45 days, a minimum for 7K to validate. The final finite period and any upper bound are 7I's and the Organization owner's, through 7L. Nothing is kept indefinitely: the baseline is a status code, a sequence number and an instant, the same class of fact as the organization row's own `status` |
| 3. Recorded coverage after removal | `covered_from`, always older than the lifetime |
| 4. State baseline that proves it | `base_state` at `covered_from`, established under the row lock |
| 5. Obligations affected before removal | Evidence is needed once, at settlement, normally seconds after the deadline. M-284 exports the age of the oldest unsettled window and AL-60 fires at `T_unsettled`, well below the lifetime, so a record approaching it is known before any evidence it needs can be removed. Removal itself does not wait for accounting (PRN-01; AOA-10) |
| 6. Known loss recorded and surfaced | The record stores basis `EVIDENCE_UNAVAILABLE`; the listing reports the baseline; the window state shows it (AOA-24); AL-60 |
| 7. Effect on SLI-11 and the budget | `uncertain`; the window is `NOT_ESTABLISHED` while that cohort hour is in it; no verdict; the last established budget state preserved (OD-7J-14; EB-05) |
| 8. Restore, removal and retention together | A restore returns baseline, transitions and accounting to one point. A prefix removed after that point is back and is removed again by the next pass; `covered_from` is that of the restore point and moves forward again |
| 9. Overdue and unresolved deliveries | Settled at their deadline; an open record needs no lifecycle evidence afterwards, however long the delivery stays unresolved |
| 10. 7K or 7L | 7K: the 45-day candidate against finalization lag, late registration, recovery and replay, outages and restore; the maintenance cadence and its lock cost; `T_unsettled`. 7L: the final finite lifetime, erasure, backup and restore behaviour, authorized preservation, and the reconciliation of ERR-7J-15 with 7I |
| Is still-required evidence ever removed? | No evidence that a reported or stored SLI-11 figure can still depend on is removable: such a figure concerns a cohort hour at most as old as the accounting hourly rows (45 days), and coverage always includes the last 45 days. Evidence older than that serves only deliveries whose hours no window and no stored row contains; those are settled `uncertain`, visibly. The owner-approved trade-off is therefore unchanged and no further decision was required. If 7K shows the two periods must differ, that returns to the owner (OD-7J-15, clarification) |

**Regression of the earlier independent findings.**

| Finding | Status after this round |
|---|---|
| R01 – R10; Minor-7J-R01 … R04 | Hold; unchanged |
| R11 (lifecycle ordering; bands) | Holds; sequence, from/to states, `locked_at` and bands are used as before. The invented "`ACTIVE` before the first transition" is removed |
| R12 (event-to-deadline window; whole-delivery exclusion) | Holds; unchanged |
| R13 (cutoff before snapshot; `READ COMMITTED`; `VOLATILE`) | Holds; unchanged. The one evidence query now also reads the baseline, in the same snapshot |

**Regression of the areas the sixth review named.** Unchanged: the strict uncertain-delivery policy; the 672-consecutive-hour model; the milestone streams; counted and uncounted closures; obligation accounting after outbox cleanup; per-stream and per-shard missing-evidence alerts; histogram uniqueness; event-time boundaries; label safety; 262 metrics; tiered access; security, privacy and residency controls; OD-7J-01 … OD-7J-15. Changed, narrowly: AOA-27 (c), (d), (e), (g), (i); IR-7J-48; ERR-7J-15; AG-7J-13 and AG-7J-14 (test ranges and the baseline precondition); M-284 (one companion series; 46,229 worst-case series); AL-60 (one term); RR-7J-16; VT-7J-145 and the new VT-7J-146 … -160; HE-7K-7J-01, -14 and HE-7L-7J-09.

**Owner-decision note.** No decision was raised. The correction keeps the approved lifetime and its fail-closed rule and adds no retention of provenance: the baseline carries no cause, actor, proof, session, key or transition time, only a status code, a sequence number and the instant from which that status is proved. Two consequences are stated so that the owner can object: the latest transition of an organization is kept until its confirmation is older than the lifetime, which can be about twice the minimum; and the baseline itself lasts as long as the organization does, as the organization row's `status` does. If either is read as a retention choice, it is the one place a decision would attach.

**Sixth-review ledger.**

| ID | Severity | Status (author's reading; the re-review decides) |
|---|---|---|
| P1-7J-R14 | P1 | Remediated in the design; gated by AG-7J-13 and AG-7J-14 |

---

## 35. Final Freeze-Gate Evidence

### 35.1 Validation performed

| Kind | What was done |
|---|---|
| **Read-only repository inspection (executed)** | SHA-256 and line count of the nine frozen Phase 7 documents; count of SQL migrations and Alembic revisions; root and head derivation; search for migration 113; search of all frozen Phase 7 documents for 7J handoffs and observability rule identifiers; reading of 7B OCC-01 … OCC-04, 7D §41, 7E §14, §25, §29, §49.4, 7F §36.4, HCG-28 … HCG-31, 7G §18.1, PRT-01 … PRT-06, §10, §14, §22, §24, §30, §42.4, §52.3, 7H §8 (T-04 … T-09), DSM-01 … DSM-07, §9.6, HTP-14, HTP-19, §13.3 Matrix F, MR-7H-01 … -11, §19, 7I §7.3, §9.5 – §9.7 (ACC-01 … ACC-20, CEV-01 … CEV-16), §10.6, §14.7 – §14.8 (rule heads), §18.3, §19, §24.2, §27; 3E §14; 3F §17 – §20; 6A §25; 6J §44; 4G §12.2; 4I §9.1; grants of `app_readonly` and of the outbox in the migrations; the column and index definitions of `audit.domain_event_outbox` (`077_5J1`) and `webhooks.webhook_deliveries` (`063_5I`); `git ls-files --eol` for the frozen documents; the D0 observability module list. For the third round: 7H §8.1 – §8.5 (T-01 … T-12, DSM-01 … DSM-07 and the worked example), §14.2 (ADM-01 … ADM-09, TEN-7H-07 … -10), §17.3 (MR-7H-01 … -11), §17.4 and Trace 17; 7I OLC-01 … OLC-16, OEA-16 and JRN-12 … JRN-15; the installed bodies of `organization.fn_platform_suspend_organization` and `fn_platform_reactivate_organization` (`107_5B5`, which replaces `105_5B4`); the status check `chk_orgs_status` (`003_5B`); the columns and indexes of `audit.audit_events` (`072_5J`). For the fourth round: the full body of `audit.fn_insert_audit_event` (`072_5J` L98 – L169: `occurred_at` is not in its column list); a search of `073` – `112` for any later definition of that function or change to that table (none); `set_updated_at()` (`001_5B`); every statement in `001` – `112` that writes `organization.organizations.status` (`105_5B4`, replaced by `107_5B5`; none later); 6C §7.6; the 6M platform suspend and reactivate routes and functions; 7H FAN-04, FAN-05; 7I STP-10, STP-11, OLC-01 … OLC-16. For the fifth round: 7I's retention matrix (RET-01 … RET-28), which has no row for STP-11 transition provenance |
| **Static reasoning (not executed)** | Every design rule, every failure scenario of §28.1, every adversarial row of §34.1, the audit-recovery argument of AUD-7J-04 |
| **Documentation integrity checks (executed)** | Metric counts, type and tier totals and per-instance series sums recomputed from the §8 tables after each remediation (after the sixth: 262 metrics, 142 Counters, 92 Gauges, 28 Histograms, 46,229 series, recomputed by script from the §8 rows); raw and LF-normalized hashes of the frozen documents; duplicate metric-ID check; cross-reference check of metric, alert, rule, test, gate and handoff identifiers; hashes of frozen documents re-verified after authoring; working-tree status |
| **SQL, Redis, telemetry or runtime tests** | **None.** No SQL was run against a database, no Redis command was issued, no metric was emitted, no trace was produced, no alert was evaluated. Nothing in this document reports a runtime observation, and no test of §28.2 has passed or failed |

### 35.2 Freeze-gate criteria

| # | Criterion (assignment §27) | Evidence | Author's status |
|---:|---|---|---|
| 1 | Every 7A – 7I observability handoff resolved or accurately gated | §4: 88 rows, 86 closed, 2 blocked with owner and condition; 7H closure outcomes now complete (§19.2) | Met |
| 2 | All 7D semantic emission points covered | §4.2: OBS-7D-01 … -18, C1, C2 | Met |
| 3 | Redis durability, PEL, group and safe-trim health covered | §8.2, §8.3, §16 | Met |
| 4 | Commit and `XACK` measured as distinct boundaries | §17.2; M-063, M-068 versus M-067, M-069 | Met |
| 5 | Gateway acknowledgement-integrity risks observable | §20.2; AL-17 … AL-19 | Met |
| 6 | Recovery and replay metrics preserve frozen semantics | §18; RCV-01 … RCV-11 | Met |
| 7 | Webhook, callback and plugin metrics reuse frozen vocabulary | §7.4; §8.9 – §8.11 | Met |
| 8 | Mandatory audit separate from telemetry | §14 | Met |
| 9 | Security and privacy signals from final 7I included | §4.7; §20; §21 | Met |
| 10 | Sealed-content and retention-deadline monitoring specified | §21; §8.14, §8.15 | Met |
| 11 | Legacy subject-index certification monitored | M-259 … M-261; M-237; AL-43b | Met |
| 12 | All labels comply with the allow-list | §9.1, §9.2 | Met |
| 13 | SLI and SLO formulas accurate; approved where binding | §10.2 – §10.4 (corrected four times: boundaries and classes; then event-time cohorts; then unmeasured hours, milestone identity and eligibility reclassification; then the eligibility window and its lifecycle evidence); §11. No objective is binding (OD-7J-01) | Met in the author's reading |
| 14 | Dashboards and alerts have concrete sources and owners | §22.1; §23.4 | Met |
| 15 | Monitoring failure and absence of evidence handled | §6.1 (expected registry for sources, components, shards and accounting streams; label-preserving absence), §6.4 (measured and unmeasured final hours; four window states), §25 | Met in the author's reading |
| 16 | Every material owner decision approved | §29: fifteen of fifteen. OD-7J-11 … OD-7J-13 were decided by the owner during the fourth remediation and OD-7J-14, OD-7J-15 during the fifth, each before the affected sections were written | Met |
| 17 | No unresolved P0 or P1 | §34.4 – §34.9: the fourteen independent P1 findings of six reviews are remediated in the design. All six earlier submissions claimed this criterion and were wrong | Met in the author's reading; **for the re-review to decide** |
| 18 | Implementation and activation dependencies explicit | §31; §32 | Met |

### 35.3 Items that remain, with owner and bound

| Item | Owner | Bound |
|---|---|---|
| Source for M-146 … M-148 | Voice (6D) | AG-7J-04 |
| Sources for M-177 and M-180 | 7K | Those two metrics only |
| In-region-only notification mechanism | Platform owner | AG-7J-09 |
| Owning-context mapping severance | 5C – 5G owners | AG-7J-10 |
| Every [CAND] and PROV value | 7K, then the owner | §33.1 |
| Residual risks RR-7J-01, -02, -04, -05, -07, -08, -09, -10, -11, -12, -16 (RR-7J-13, -14 and -15 are accepted by the owner) | Platform owner through 7L | HE-7L-7J-09 |
| Observation accounting (§6.4) and its source records | Platform; 5I, 5J, 7H, 7I owners | AG-7J-13 |

### 35.4 What this document does not claim

It does not claim that any metric, span, log field, alert, dashboard, principal, function, broker, scanner, evidence store or gate exists. It does not claim any capacity, latency or cost figure was measured. It does not claim any objective is approved. It does not claim that a test passed. It does not claim that monitoring prevents anything.

### 35.5 Repository integrity after authoring

Recorded in the completion report that accompanies this document: the file's own line count and SHA-256 (which cannot be written inside the file they describe), the unchanged hashes of 7A – 7I, and the working-tree status showing this file as the only change.

### 35.6 Final status

The author's status line is given in the completion report. This document is not approved and not frozen; that determination belongs to the independent freeze-gate review and the platform owner.
