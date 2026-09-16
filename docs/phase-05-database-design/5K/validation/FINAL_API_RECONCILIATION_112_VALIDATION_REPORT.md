# Final API Reconciliation — Migration 112_5H5 Validation Report

**Capacity-Quota Final Closure Pass**

| | |
|---|---|
| Migration under validation | `112_5H5` |
| Parent revision | `111_5H4` |
| Project head after this pass | `112_5H5` (single head) |
| Owner decision in force | **FAR-OD-03 = OPTION B** |
| Defects addressed | FAR-P1-06, FAR-P2-08, FAR-P2-09 |
| Engine | PostgreSQL 18.6 (Debian 18.6-1.pgdg12+2) on x86_64-pc-linux-gnu, image `pgvector/pgvector:pg18` |
| Status | **Evidence complete — submitted for independent review** |

> This report records what was executed and what was observed. It does not
> approve, accept or freeze anything. Those decisions belong to the
> independent reviewer.

---

## 1. Owner decision FAR-OD-03 = Option B, as implemented

`CONCURRENT_CALLS` is a **CAPACITY / ENTITLEMENT quota** — instantaneous
occupied capacity — and is **not** a sixteenth accumulated USAGE metric.

The canonical 15-metric usage vocabulary owned by 5H §11.1 is **unchanged**:

```
CALL_MINUTES            AI_MINUTES              STT_SECONDS
TTS_CHARACTERS          LLM_PROMPT_TOKENS       LLM_COMPLETION_TOKENS
EMBEDDING_TOKENS        CAMPAIGN_CALLS          WORKFLOW_EXECUTIONS
TOOL_EXECUTIONS         KNOWLEDGE_RETRIEVALS    STORAGE_GB
API_REQUESTS            ACTIVE_AGENTS           ACTIVE_PHONE_NUMBERS
```

`CONCURRENT_CALLS` was **not** added to that list. It is the sole member of a
separate, governed capacity vocabulary introduced by 112. The two domains were
not collapsed: they have separate vocabulary predicates, separate override
stores, separate resolvers, and a dispatching Platform Admin setter.

| Property | USAGE / ACCOUNTING | CAPACITY / ENTITLEMENT |
|---|---|---|
| Vocabulary | the canonical 15 metrics (5H §11.1) | `CONCURRENT_CALLS` only |
| Vocabulary predicate | `billing.fn_is_canonical_usage_metric` | `billing.fn_is_canonical_capacity_quota_metric` |
| Override store | `billing.quota_overrides` | `billing.capacity_quota_overrides` |
| Resolver | `billing.fn_resolve_effective_quota` | `billing.fn_resolve_effective_capacity_quota` |
| Accumulation model | monotonic, accumulates over a period | instantaneous gauge, must decrement |
| Admission model | bounded over-consumption tolerated | hard, atomic, reservation-based |
| Base commercial limit | `billing.quota_configs` | `billing.quota_configs` |
| Administrative overlay | separate table, separate resolver | separate table, separate resolver |

Both domains resolve their base commercial limit from `billing.quota_configs`.
Only the administrative overlay is separate. This is deliberate: the
commercial product catalogue is one thing, and it is not forked by 112.

**Verification that the domains did not leak into one another** — FAR_112_03
§7, cases H.1–H.7b:

- usage resolver **rejects** `CONCURRENT_CALLS`;
- capacity resolver **accepts** `CONCURRENT_CALLS`;
- capacity resolver **rejects** `ACTIVE_AGENTS`;
- legacy `AGENT_COUNT` **rejected by both**, and not aliased into either;
- `NULL` **rejected by both**;
- the two predicates are disjoint and NULL-safe (H.6);
- `concurrent_calls_in_usage_store = 0`, `active_agents_in_capacity_store = 0`
  (H.7, H.7b) — no row has ever crossed.

Separation is enforced at **three independent layers**: the table `CHECK`
constraints (`chk_qo_metric_canonical`, `chk_cqo_metric_canonical`), which bind
even the table owner; the two resolvers; and the Platform Admin dispatcher.

---

## 2. Issue closure

### FAR-P1-06 — CLOSED by migration 112 plus controlled API amendments

**The defect.** `CONCURRENT_CALLS` was governed as a per-organization limit by
three frozen Phase-6 documents — 6D (`ConcurrentCallQuotaNotExceeded`,
`CheckQuota(CONCURRENT_CALLS)`), 6H (campaign dispatch fail-closed rule) and 6K
(quota vocabulary and 429 mapping) — but was **not representable anywhere in
the database**. It was outside the canonical 15-metric usage vocabulary, so
`billing.fn_platform_set_quota_override` could not write it, and
`billing.fn_resolve_effective_quota` raised on it. A limit three API contracts
depend on could not be configured, overridden, or read.

**The closure.** Migration 112 creates the governed capacity domain: the
vocabulary predicate, the `billing.capacity_quota_overrides` store with its
partial unique index and RLS, the `billing.fn_resolve_effective_capacity_quota`
resolver, and domain dispatch inside the existing 8-argument Platform Admin
setter — whose public signature and UUID return are **unchanged**, so 6M §18's
endpoint contract is preserved.

**Evidence.** FAR_112_02 §1 captures the before-state at head `111_5H4`
(`to_regclass('billing.capacity_quota_overrides')` → NULL; billing functions
matching `%capacity%` → 0). FAR_112_02 §§2–13 capture the after-state:
vocabulary, base resolution, temporary override, expiry fallback, supersession,
NULL `hard_limit`, Platform Admin dispatch, read model and audit contract.
FAR_112_03 §7 captures domain separation.

The accompanying controlled API amendments (5H, 6K §54, 6D, 6H, 6M) are
recorded in the master Final API Reconciliation document, not here.

### FAR-P2-08 — CLOSED by migration 112

**The defect.** The canonical-metric guard was written as
`p_metric = ANY(ARRAY[...])`. In SQL three-valued logic that expression yields
**NULL**, not FALSE, for a NULL input, and a PL/pgSQL `IF NOT <NULL>` takes its
false branch. The guard therefore **silently did not fire** on a NULL metric.

**The closure.** The predicate is wrapped in `COALESCE(..., FALSE)`, and both
resolvers validate `p_metric IS NOT NULL` explicitly before any vocabulary test.

**Evidence.** FAR_112_03 §7:

- H.5 — usage resolver raises on a NULL metric;
- H.5b — capacity resolver raises: *"p_metric is required and must not be NULL."*;
- H.6 — the observable fix: both predicates return `f`, not NULL, for a NULL
  metric.

### FAR-P2-09 — CLOSED, recorded as a controlled audit-contract extension

Pre-111 override audit events carry `resource_type = QUOTA_CONFIG`; 111 and
later carry `resource_type = QUOTA_OVERRIDE`. `action_kind` remains
`QUOTA_OVERRIDE_SET` across the boundary.

This is **not** "unchanged in shape and literal," and is not described that way.
It is a controlled extension of the audit contract at the 111 boundary, and it
is recorded as such in FAR_112_02 §14 and in the Event/Audit ledger.

**Why no additional migration was required** — FAR_112_03 §10.4, case P11:
the constraints on `audit.audit_events` are **length-only**
(`length(action_kind) BETWEEN 1 AND 200`, `length(resource_type) BETWEEN 1 AND
200`), not an enumerated domain. `'QUOTA_OVERRIDE'` is therefore structurally
permitted with no constraint change. This is a positive catalog fact read from
`pg_constraint`, not an inference from migration source.

**Audit domain integrity** — FAR_112_03 §10.3, case P10: every audited
`resource_id` resolves in exactly the domain its `resource_snapshot` claims, and
none points at a `billing.quota_configs` base row. The audit trail cannot be
used to attribute a capacity change to the usage domain or the reverse.

---

## 3. Execution results

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Fresh path `001 → 112` | **PASS** | FAR_112_01 §5 |
| 2 | Incremental path `111 → 112` | **PASS** | FAR_112_01 §6 |
| 3 | Catalog convergence, fresh vs incremental | **PASS** | FAR_112_01 §8 |
| 4 | Security-surface convergence, fresh vs incremental | **PASS** | FAR_112_03 §INSTANCES, DISCLOSURE 6 |
| 5 | Single head `112_5H5`, no branch | **PASS** | FAR_112_01 §7 |
| 6 | No migration 113 | **PASS** | FAR_112_01 §4; re-verified below |
| 7 | Migrations 001–111 byte-unchanged | **PASS** | FAR_112_01 §2; re-verified below |
| 8 | Targeted 110 Agent regression | **PASS** | FAR_112_03 §§1–5 |
| 9 | Targeted 111 usage-quota regression | **PASS** | FAR_112_03 §6 |
| 10 | Capacity domain (vocabulary, resolver, override lifecycle) | **PASS** | FAR_112_02 §§2–13 |
| 11 | USAGE / CAPACITY domain separation | **PASS** | FAR_112_03 §7 |
| 12 | Cross-domain security, ACLs, RLS, audit atomicity | **PASS** | FAR_112_03 §§8–11 |

### 3.1 Fresh path `001 → 112` — PASS

`far112_fresh` was confirmed empty (no `alembic_version` table, no application
schemas), then `alembic upgrade head` applied **all 112 revisions in one pass**,
exit status 0, no error and no manual intervention.

### 3.2 Incremental path `111 → 112` — PASS

`far112_incr` was brought to `111_5H4` and held there (`alembic current` →
`111_5H4`). The pre-112 defect reproduction was captured at that head, including
a **real** `ACTIVE_AGENTS` usage override written through the 111 Platform Admin
function (`01a0a932-92dc-724d-9919-191506e37ee6`), so that a genuine pre-existing
111 row would be present across the upgrade. The single incremental step then
applied with exit status 0.

That pre-existing 111 row **survived the upgrade unchanged** and still resolves
through `billing.fn_resolve_effective_quota` as `source = PLATFORM_OVERRIDE`,
soft `18.0000` / hard `20.0000` — FAR_112_03 §6, case G.1. This is the specific
property that distinguishes a safe forward migration from one that merely
produces the right schema: pre-existing tenant data was carried forward intact.

### 3.3 Catalog convergence — PASS

A catalog fingerprint was extracted from each instance covering columns,
constraints, indexes, function identity arguments and `SECURITY DEFINER` flag
and volatility **and an md5 of the complete `pg_get_functiondef` output**, RLS
policies, `relrowsecurity` / `relforcerowsecurity`, table grants and triggers:

```
far112_fresh fingerprint lines .......... 3969
far112_incr  fingerprint lines .......... 3969
diff fresh vs incremental ............... IDENTICAL (zero differing lines)
```

Including the md5 of each function's **full definition** means this is not
merely a signature match — the function **bodies** agree. That is the property
that matters for a migration whose principal content is `CREATE OR REPLACE`.

### 3.4 Security-surface convergence — PASS

`catalog.sql` dumps table grants but **not** role attributes and **not**
function ACLs (`proacl`). A separate probe covering role attributes, EXECUTE
ACLs, PUBLIC privileges, RLS enable/force flags and trigger definitions was run
unchanged against both instances and the outputs compared byte for byte after
trailing-whitespace normalisation: **identical**. See FAR_112_03 DISCLOSURE 6
for why this was necessary and how the two evidence sets divide.

### 3.5 Single head, no 113, frozen history — PASS

```
                        alembic current      alembic heads
far112_fresh            112_5H5 (head)       112_5H5 (head)
far112_incr             112_5H5 (head)       112_5H5 (head)
rows in alembic_version (both instances)     1
```

Re-verified at the time this report was written:

```
$ ls 5K/alembic/versions/*.py | wc -l
112
$ ls 5K/alembic/versions/ | grep -c '^113'
0
$ sha256sum -c baseline_001_111.sha256
OK = 222        FAILED = 0        entries = 222
```

Frozen-history integrity is asserted against a SHA-256 manifest of all 222
frozen files (111 `.sql` + 111 `.py`) captured **before** authoring began and
stored outside the repository — **not** by reading `git status` alone. Some
prior reconciliation files in this repository are uncommitted, so `git status`
on its own cannot distinguish "unchanged" from "changed but never committed".

Migrations `110_5C2` and `111_5H4` were **not** amended, **not** re-run and
**not** edited for prose. Migration 111 in particular was left untouched even
where its docstring over-attributes closure (FAR-P3-06); that correction is
recorded in the manifest and the FAR ledger rather than by editing a frozen
file.

### 3.6 Targeted 110 Agent regression — PASS

112 `CREATE OR REPLACE`s the same Platform Admin setter that 110/111 depend on,
so the Agent admission path was re-proven rather than presumed:

- limit `2` admits two agents and refuses the third with SQLSTATE `53400`;
  counted stays at 2; the rejected request wrote no row;
- fractional limit `1.5000` admits one and refuses the second, and the limit is
  **never rounded** (FAR-P1-02 property; still stored as `1.5000` afterwards);
- **create concurrency** — two real sessions released at a barrier 96
  microseconds apart contend for one slot; exactly one admitted; counted 2,
  never 3;
- **clone concurrency** — two real sessions; exactly one clone created; counted
  3, never 4;
- **actor guard** — non-member, other-tenant and NULL `created_by` all refused,
  on both the create and the clone path, and the guard fires *before* the quota
  gate so an unauthorized actor cannot consume a slot even transiently;
- **lifecycle guard** — terminal-state violations, skip transitions,
  tenant-ownership transfer and **soft-delete resurrection** all refused. The
  resurrection case matters most for quota integrity: un-deleting a row would
  re-enter the counted set with no admission check at all.

The concurrency cases used genuinely concurrent sessions, not sequential calls.
A sequential probe cannot distinguish a correctly serialized admission gate from
a racy one. Serialization is the transaction-scoped advisory lock taken **inside
the database boundary**, as frozen 6A §17.3 requires.

### 3.7 Targeted 111 usage-quota regression — PASS

- an active override wins, and the commercial **base underneath is intact**
  (not overwritten) — the core FAR-P1-05 property, still closed after 112;
- a base change made *while* an override is active is **staged**, not lost;
- **expiry falls back to the CURRENT base** (`12.0000 / 15.0000 | BASE`), not to
  a snapshot of what the base was when the override was created, and **not to
  unlimited** — the FAR-OD-02 closure, still closed;
- superseded overrides never reactivate; expiry is a **window test, not a
  deletion**, so the expired row remains the single current row and simply stops
  applying;
- `hard_limit IS NULL` on an existing effective row remains **explicitly
  uncapped**, and the admission guard honours it.

### 3.8 Capacity domain — PASS

Vocabulary, NULL safety, base capacity resolution, temporary override, expiry
fallback, base changes under an active override, permanent override,
supersession, absence of old-override reactivation, NULL `hard_limit`,
cross-domain rejection, Platform Admin dispatcher, Platform Admin read model,
audit resource contract, and the zero-row / no-configuration case are all
recorded with actual output in FAR_112_02.

The capacity resolver shares the usage resolver's effective-window semantics
(FAR_112_03 §6, case G.4.7) but not its vocabulary.

### 3.9 Cross-domain security — PASS

- exactly **one** of the five functions 112 created or replaced is
  `SECURITY DEFINER`, and it is the mutation path; both resolvers are
  `SECURITY INVOKER`, so a tenant reads through its own RLS and grants rather
  than borrowing the definer's authority;
- every one of the five carries an explicit `SET search_path`;
- **no PUBLIC EXECUTE** on any of the five, and **no PUBLIC privilege** of any
  kind on any governed quota table. PostgreSQL grants EXECUTE to PUBLIC by
  default, so each of these had to be explicitly revoked;
- the guarded setter is executable by **`app_platform_admin` alone**, with
  `app_api` explicitly **revoked** — necessary because the function is
  `CREATE OR REPLACE`d and a replace preserves the prior ACL;
- **no application role holds any write privilege** on
  `billing.capacity_quota_overrides`. The guarded function is not merely the
  preferred write path; it is the only one available to any app role;
- an ordinary tenant is refused `INSERT`, `UPDATE` **and** `DELETE` with `42501`,
  and is equally refused EXECUTE on the guarded setter — it can neither write
  the table nor borrow the function that can;
- a tenant reads **both** its usage and its capacity effective quota with
  `is_platform_admin()` returning **false** — no privilege escalation is
  required to read one's own entitlement;
- RLS is `ENABLE`d **and** `FORCE`d on all three governed quota tables; the
  tenant sees 6 of its own rows and **0** belonging to another tenant;
- **112 added no new BYPASSRLS role** and granted BYPASSRLS to no role — it
  contains no role statement of any kind. The two application roles that hold
  BYPASSRLS (`app_migration`, `app_platform_admin`) are pre-existing from
  `001_5B.sql:41` and `:44`.

> **ERRATUM — controlled clarification (`FAR-P3-07`, 2026-09-16; additive, no evidence re-run).** The phrase "the five functions 112 created or replaced" above is inaccurate as a label, and so are the matching heading "EXECUTE ACLs on every function 112 created or replaced" in `FAR_112_03` §8.1 and the phrase "the three pre-existing functions it forward-replaces" in `FAR_112_01` §2. `112_5H5.sql` contains **four** `CREATE OR REPLACE FUNCTION` statements (lines 147, 199, 373 and 518). Two of them replace pre-existing functions: `billing.fn_is_canonical_usage_metric` and `billing.fn_platform_set_quota_override`. The other two create new ones: `billing.fn_is_canonical_capacity_quota_metric` and `billing.fn_resolve_effective_capacity_quota`. `FAR_112_02` §1 shows zero `%capacity%` billing functions at `111_5H4`. The fifth function in the probed set, `billing.fn_resolve_effective_quota`, belongs to `111_5H4` and is **not** modified by 112. The probe set is therefore the five **governed quota functions** at head `112_5H5`. Every catalog observation recorded for those five (one `SECURITY DEFINER`, explicit `search_path` on all five, no PUBLIC `EXECUTE`) stands unchanged. Only the label is corrected. The captured transcripts are left verbatim, consistent with L3.

### 3.10 Audit atomicity — PASS

This property had no captured negative-path evidence in any earlier run, so a
targeted probe was written and executed rather than the property being asserted
from reading SQL:

| Step | Observation |
|---|---|
| baseline | audit rows **13**, capacity rows **7** |
| setter called inside an explicit transaction | **14** / **8** — both advance by exactly one, together |
| audit row for the still-uncommitted write | visible in the same transaction, `resource_id` already resolving into the capacity store |
| **`ROLLBACK`** | **13** / **7** — **both gone** |
| rejected call (`AGENT_COUNT`, `P0001`) | **13** / **7** — unchanged |

The rollback is the decisive observation. Were the audit write autonomous — a
`dblink` call, a separate connection, an out-of-band emitter, a deferred worker
— the audit row would have **survived** the rollback and left a permanent record
of an override that does not exist. It did not survive. Neither an override
without its audit event nor an audit event without its override is reachable
through the sanctioned path.

---

## 4. What is *not* claimed

Precision here was itself a finding (FAR-P3-04), so the boundary is stated
explicitly.

**The guarantee.** Within the application's runtime trust boundary — every
session connecting as one of the eight non-superuser application roles, which is
how the application, its workers and its administrators actually connect — the
capacity-quota mutation contract is enforced by the guarded `SECURITY DEFINER`
function with its explicit `search_path`, minimum EXECUTE grants, absence of any
raw DML path, in-function validation, same-transaction audit, the partial unique
index backstop, RLS for tenant read isolation, and — on the Agent path — a
`BEFORE UPDATE` trigger that binds even the table owner.

**The following statements are FALSE and are made nowhere in this
reconciliation:**

- ❌ *"PostgreSQL superuser privilege cannot be bypassed."* It can. A superuser
  can disable triggers, drop constraints, alter function bodies, read and write
  any table, and set any GUC.
- ❌ *"FORCE ROW LEVEL SECURITY binds a postgres-owned SECURITY DEFINER function
  against superuser bypass."* It does not. `FORCE` removes the **owner's**
  exemption from RLS for ordinary DML. It has no effect on a superuser, who
  bypasses RLS entirely and unconditionally. This was the exact imprecision
  recorded as FAR-P3-04.
- ❌ *"No role can bypass RLS on the quota tables."* Two application roles hold
  BYPASSRLS from `001_5B`, and `postgres` holds it as a superuser.
- ❌ *"The lifecycle trigger is unbypassable."* It binds all ordinary DML
  including the owner's. It does not bind `ALTER TABLE ... DISABLE TRIGGER`,
  `SET session_replication_role = replica`, or `DROP TRIGGER`.

**Deliberate superuser or table-owner action is outside this guarantee.**
Protection against that class of action belongs to credential custody,
connection policy, network segmentation and infrastructure audit — not to this
schema.

What *is* claimed, and is tested: `organization.is_platform_admin()` requires
`session_user = 'app_platform_admin'` **and** the request-scoped GUC, together.
`session_user` does not change after `SET ROLE`, so a session connected as
`postgres` can **never** satisfy this predicate and can never pass the
platform-admin RLS policy, regardless of its superuser status.

**Additionally not claimed:**

- **The capacity runtime is not implemented.** Migration 112 establishes the
  governed vocabulary, the entitlement store and the resolver. The
  reservation/gauge runtime — acquire, release, crash reconciliation — is an API
  contract owned by 6K §54 and is deliberately not application code in this
  pass.
- **No test is claimed that is not shown.** Every result in FAR_112_01,
  FAR_112_02 and FAR_112_03 is transcribed from a captured output file.
- **No APPROVED or FROZEN status is claimed.**

---

## 5. Disclosed harness limitations

Reported because a reviewer is entitled to know how the evidence was produced,
including where a probe was mislabelled or a first attempt failed. Full detail
is in FAR_112_02 (DISCLOSURES 1–n) and FAR_112_03 (DISCLOSURES 1–7).

**L1 — Structural and behavioural evidence came from different instances.**
`far112_fresh` holds the schema but **zero fixture rows**; every behavioural
result therefore comes from `far112_incr`, and the ACL/role/RLS/trigger
structure comes from `far112_fresh`. Rather than assume the two agree, the
structural probe was re-run unchanged against `far112_incr` and the outputs
compared byte for byte: **identical**. This is disclosed rather than buried,
because the ACL table and the tenant behaviour in FAR_112_03 were not observed
in the same database.

**L2 — `NOW()` is `transaction_timestamp()`, not `clock_timestamp()`.** The
effective-window predicate is evaluated **once per transaction, at transaction
start**. An expiry falling during a long transaction becomes visible to the
*next* transaction, not mid-statement. This is correct and intended behaviour,
but it invalidated a first attempt at the expiry-fallback case, which had sent
the sleep and the re-resolve in a single implicit transaction and so reported a
still-active override. The case was re-run with each statement in its own
transaction, and the semantics were then proven directly
(`now_is_transaction_timestamp t`, `now_is_clock_timestamp f`). The original
line is retained in the captured output and must **not** be read as a failure
to expire.

**L3 — Two probe column labels encode expectations the data contradicts.**
A column named `bypassrls_app_roles_must_be_0` returned **2**, and a clone-count
column headed "EXPECT: exactly 1 new row" returned **2**. In both cases the
**probe label is wrong and the migration is not**: BYPASSRLS is held by two
pre-existing `001_5B` roles, and the clone count includes the clone *source* as
well as the clone. Both wrong labels are reproduced verbatim in FAR_112_03
alongside the corrections, rather than being quietly re-run with friendlier
labels. The claims actually made were narrowed to what the data supports.

**L4 — Two probes were first pointed at the wrong target and failed.** The
single-current-row probe first ran as `app_platform_admin` and hit the ACL
(`42501`) before ever reaching the unique index, so it proved an ACL rather than
the index; it was re-run as the table owner to reach `23505`. The
audit-atomicity probe first ran against the fixture-empty instance and was
correctly refused by the setter's in-function organization-existence validation.
Both first attempts are retained in the record — the second is itself
corroboration that the setter validates organization existence before writing.

**L5 — Fixture state is cumulative across the regression battery.** Cases ran in
sequence against one database and each inherits the prior case's state, so
absolute row counts reflect the whole battery. Every case that depends on a
starting condition establishes and prints that condition first, and counts
should be read as deltas against those printed baselines.

**L6 — Two cases were deliberately run as the table owner.** The lifecycle
trigger case and the unique-index case exist specifically to test mechanisms
claimed to bind the owner. Running them as an application role would have been
stopped earlier by an ACL and would have proven nothing about those mechanisms.
The scope and limits of owner-level binding are stated in FAR_112_03 §§5.1 and
11.3.

**L7 — Disposable local containers, not a production-representative fleet.**
All execution was against disposable single-node PostgreSQL 18.6 containers
created empty for this pass. No shared, long-lived or production database was
used. Nothing here speaks to replication, connection pooling under load,
failover, or behaviour at production data volumes.

---

## 6. Evidence index

| File | Contents |
|---|---|
| `FAR_112_01_migration_integrity.txt` | Migration execution on both paths, single-head ownership, file hashes, repository counts, frozen-history integrity for 001–111, catalog convergence |
| `FAR_112_02_capacity_quota_battery.txt` | Capacity vocabulary, resolver semantics, override lifecycle, Platform Admin dispatch and read model, audit resource contract, zero-row / no-configuration semantics |
| `FAR_112_03_cross_domain_security_regression.txt` | Targeted 110 and 111 regressions, create and clone concurrency, actor and lifecycle guards, domain separation, ACLs, RLS, BYPASSRLS provenance, audit atomicity, the exact scoped security guarantee |
| This file | Consolidated validation result for migration 112_5H5 |

Earlier evidence sets — `FAR_DB_01..03` (migration 110) and `FAR_111_01..03`
(migration 111) — remain valid for the migrations they describe and were **not**
rewritten. Exactly one class of statement in `FAR_111_*` is superseded: any
statement of the form *"no migration 112 exists"* or *"112 is the next
unallocated revision"*. Nothing else in either earlier set is withdrawn.

---

## 7. Status

Migration `112_5H5` executed successfully on both the fresh `001 → 112` path and
the incremental `111 → 112` path, converged to a byte-identical catalog on both,
left migrations 001–111 byte-unchanged, created no migration 113, and holds the
project's single head. FAR-P1-06, FAR-P2-08 and FAR-P2-09 are closed on the
evidence recorded above. The targeted 110 and 111 regressions pass. The capacity
domain behaves as owner decision FAR-OD-03 Option B specifies, and the usage and
capacity domains were not collapsed.

**This report is submitted for independent review. It does not approve, accept
or freeze anything.**
