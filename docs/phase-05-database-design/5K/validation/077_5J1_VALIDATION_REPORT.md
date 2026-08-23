# Migration 077_5J1 — Validation Report (Phase 6C dependency-closure package, DEP-6C-16)

**Date:** 2026-08-23 (live validation pass; supersedes the static-only report
of the same date earlier in this session — see "Revision history" at the
bottom).
**Scope:** validation of migration `077_5J1.sql` (`audit.domain_event_outbox`
+ `fn_claim_outbox_events`/`fn_mark_outbox_published`/`fn_mark_outbox_failed`/
`fn_outbox_tenant_check`), authored to resolve
`docs/phase-06-api-design/6C-Core-Platform-APIs.md`'s `DEP-6C-16`.

## 0. Validation method

This pass has a **live PostgreSQL 18 server** available (`postgresql-x64-18`,
a local native Windows service — not Docker; no Docker engine exists in this
environment). A dedicated, disposable database (`voice_agent_5j1_validate`)
was created for this validation, dropped and recreated once (to get a
genuinely empty starting point after an environment gap — see note below —
was resolved), and is separate from any shared or production database.
Every check below marked **LIVE** was executed against real running SQL in
that database, with raw command/query output captured under
`../execution_logs/` (prefix `20260823T061055Z`, files `51`-`62`) — not
reasoned about from the SQL text alone. Two structural counts in the prior
static-only version of this report were wrong and are corrected here (§1-2,
§3): **17 columns** (not 16), **7 CHECK constraints + 1 PRIMARY KEY** (not 8
CHECK constraints).

**Environment note.** This server initially lacked the `vector` extension
required by migration `034_5F` (Phase 5F, unrelated to 5J.1). No official
Windows pgvector build exists, and building one in this session was not
practical (no MSVC toolchain). After an explicit tradeoff discussion, the
user installed `vector` 0.8.6 on their own server themselves — this session
did not install it. See `../execution_logs/README.md`'s "Fifth batch" section
for full detail.

---

## STATIC VALIDATION (structure of `077_5J1.sql` itself, corrected)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Table exists | PASS | Exactly one `CREATE TABLE audit.domain_event_outbox` statement (`077_5J1.sql:48`). |
| 2 | Columns / types | PASS — **corrected to 17** | `id`, `event_type`, `event_version`, `organization_id`, `aggregate_type`, `aggregate_id`, `payload`, `occurred_at`, `status`, `attempt_count`, `max_attempts`, `available_at`, `claimed_by`, `claimed_at`, `published_at`, `last_attempt_at`, `last_error` — **17**, not 16 as the prior static-only report miscounted. Reconfirmed live (§1 below). |
| 3 | Constraints | PASS — **corrected to 7 CHECK + 1 PRIMARY KEY** | `pk_outbox` (PK) + `chk_outbox_status`, `chk_outbox_event_type_len`, `chk_outbox_attempt_count`, `chk_outbox_max_attempts`, `chk_outbox_published_state`, `chk_outbox_payload_size`, `chk_outbox_last_error_len` — **7 named CHECK constraints**, not 8 as the prior report's prose miscounted in one place. Reconfirmed live (§2 below). |
| 4 | Indexes | PASS | Exactly 4 `CREATE INDEX` statements, each matching a real hot-path predicate. Reconfirmed live (§3 below). |
| 5 | Role grants | PASS | Deny-by-default + narrow re-grant pattern, matching the 5B-5K convention. Reconfirmed live (§4 below). |
| 6 | No unintended RLS bypass | PASS | No `ENABLE ROW LEVEL SECURITY` anywhere in the file; tenant-forgery guarded structurally by `trg_outbox_tenant_check`, not RLS. Reconfirmed live (function/trigger exists, §5). |

---

## LIVE DB VALIDATION

### §0. Alembic state (execution_logs `51`)

Genuinely empty database confirmed (`pg_tables` count = 0) immediately before
upgrade. Full chain executed:

```
alembic current   (pre)   -> (empty / base)
alembic heads     (pre)   -> 077_5J1 (head)
alembic upgrade head      -> exit code 0, all "Running upgrade" lines
                              001_5B -> 002_5B -> ... -> 076_5K1 -> 077_5J1
alembic current   (post)  -> 077_5J1 (head)
alembic heads     (post)  -> 077_5J1 (head)
```

This run also stands in for Phase 5K's own "fresh-DB 001→077" gate (§FRESH
DB VALIDATION below) — no separate run was performed since this one already
starts from a genuinely empty database and walks the full chain.

**Result: single head, both pre- and post-upgrade. DB revision after = `077_5J1`.**

### §1. Outbox table + columns (execution_logs `52`) — LIVE

```sql
SELECT to_regclass('audit.domain_event_outbox');
-- audit.domain_event_outbox
```

`information_schema.columns` returns exactly **17 rows**, in the same order,
types, nullability, and defaults as `077_5J1.sql`'s `CREATE TABLE`:
`id uuid NOT NULL DEFAULT gen_uuid_v7()`, `event_type text NOT NULL`,
`event_version integer NOT NULL DEFAULT 1`, `organization_id uuid`,
`aggregate_type text`, `aggregate_id uuid`, `payload jsonb NOT NULL`,
`occurred_at timestamptz NOT NULL DEFAULT now()`, `status text NOT NULL
DEFAULT 'PENDING'`, `attempt_count integer NOT NULL DEFAULT 0`,
`max_attempts integer NOT NULL DEFAULT 10`, `available_at timestamptz NOT
NULL DEFAULT now()`, `claimed_by text`, `claimed_at timestamptz`,
`published_at timestamptz`, `last_attempt_at timestamptz`, `last_error text`.

**Result: 17/17 columns match exactly. PASS.**

### §2. Constraints (execution_logs `53`) — LIVE

`pg_constraint` for `audit.domain_event_outbox`:

| contype | count | names |
|---|---|---|
| `c` (CHECK) | **7** | `chk_outbox_attempt_count`, `chk_outbox_event_type_len`, `chk_outbox_last_error_len`, `chk_outbox_max_attempts`, `chk_outbox_payload_size`, `chk_outbox_published_state`, `chk_outbox_status` |
| `p` (PRIMARY KEY) | 1 | `pk_outbox` |
| `n` (NOT NULL) | 9 | PostgreSQL 18 catalog detail — PG18 surfaces each `NOT NULL` column as its own `pg_constraint` row; this is **not** an additional CHECK constraint and does not appear in `077_5J1.sql`'s DDL as a named constraint. |

**Result: exactly 7 CHECK constraints + 1 PRIMARY KEY, as the governing task
requires. The prior report's "8 CHECK constraints" phrasing is corrected —
it was a miscount of the 7 actual named CHECK constraints, not a discovery of
an 8th. PASS.**

### §3. Indexes (execution_logs `53`) — LIVE

`pg_indexes` for `audit.domain_event_outbox` — definitions, not just names:

| Index | Definition (live) | Matches migration? |
|---|---|---|
| `idx_outbox_claim` | `btree (available_at, id) WHERE (status = 'PENDING'::text)` | Yes — exact predicate `fn_claim_outbox_events` scans for fresh PENDING rows. |
| `idx_outbox_claimed_stuck` | `btree (claimed_at) WHERE (status = 'CLAIMED'::text)` | Yes — supports the stuck-reclaim branch. |
| `idx_outbox_org_type` | `btree (organization_id, event_type, occurred_at DESC) WHERE (organization_id IS NOT NULL)` | Yes — observability/dashboard lookup. |
| `idx_outbox_status` | `btree (status, occurred_at DESC)` | Yes — general status dashboarding. |
| `pk_outbox` | `UNIQUE btree (id)` | Implicit index backing the PK. |

**Result: all 4 explicit indexes + 1 implicit PK index, definitions verified
live, not just names. PASS.**

### §4. Functions, SECURITY DEFINER, search_path, trigger (execution_logs `54`) — LIVE

| Function | Args | Returns | Owner | `prosecdef` | `search_path` |
|---|---|---|---|---|---|
| `fn_claim_outbox_events` | `p_worker_id text, p_limit integer, p_claim_timeout_seconds integer` | `SETOF audit.domain_event_outbox` | postgres | **true** | `audit, pg_catalog` |
| `fn_mark_outbox_published` | `p_id uuid, p_worker_id text` | `boolean` | postgres | **true** | `audit, pg_catalog` |
| `fn_mark_outbox_failed` | `p_id uuid, p_worker_id text, p_error text, p_next_attempt_at timestamptz` | `text` | postgres | **true** | `audit, pg_catalog` |
| `fn_outbox_tenant_check` (trigger fn) | (none) | `trigger` | postgres | **true** | `audit, organization, pg_catalog` |

`EXECUTE` grants: `app_worker` and `app_platform_admin` on all three
callable functions; **none to `app_api`** (matches design — request
handlers only ever INSERT); no explicit grant on the trigger function
(correct — invoked by the trigger mechanism, not called directly).

Trigger `trg_outbox_tenant_check`: `BEFORE INSERT ON audit.domain_event_outbox
FOR EACH ROW EXECUTE FUNCTION audit.fn_outbox_tenant_check()`, enabled
(`tgenabled='O'`).

**Security requirement check: all 4 SECURITY DEFINER functions have an
explicit, non-empty `search_path` — no bare/implicit/public-only regression.
PASS.**

---

## SECURITY/GRANT VALIDATION (execution_logs `55`, `55b`) — LIVE, via `SET ROLE`

| Role | Test | Result |
|---|---|---|
| `app_api` | INSERT (plain, no `RETURNING`) | **PASS** — succeeds |
| `app_api` | INSERT with `RETURNING` / direct `SELECT` | **PASS (correctly denied)** — `app_api` has INSERT-only, no SELECT, by design; this is not a defect, it is the deny-by-default grant working exactly as specified |
| `app_api` | UPDATE | **PASS (correctly denied)** — `permission denied for table domain_event_outbox` |
| `app_api` | DELETE | **PASS (correctly denied)** |
| `app_api` | `fn_claim_outbox_events` | **PASS (correctly denied)** — `permission denied for function` |
| `app_api` | `fn_mark_outbox_published` | **PASS (correctly denied)** |
| `app_worker` | INSERT | **PASS** — succeeds |
| `app_worker` | `fn_claim_outbox_events` | **PASS** — succeeds, claims rows |
| `app_worker` | direct UPDATE (bypassing the functions) | **PASS (correctly denied)** |
| `app_worker` | direct DELETE | **PASS (correctly denied)** |
| `app_readonly` | SELECT | **PASS** — succeeds |
| `app_readonly` | INSERT | **PASS (correctly denied)** |
| — | `pg_roles.rolbypassrls` for `app_api`/`app_worker`/`app_readonly` | **PASS** — all `false`; no BYPASSRLS workaround introduced |

**Result: every mandatory grant behavior confirmed live. No defect found.**

---

## LIVE DB VALIDATION — transactional-outbox invariant (execution_logs `56`)

**Atomic COMMIT test:** `BEGIN; INSERT INTO organization.organizations ...;
INSERT INTO audit.domain_event_outbox (event_type='organization.created', ...)
...; COMMIT;` — both rows present afterward, verified by direct `SELECT`,
then cleaned up.

**Atomic ROLLBACK test:** identical shape, `ROLLBACK` instead of `COMMIT` —
both rows **absent** afterward (org count = 0, outbox count = 0).

**Result: PASS. Proven live, not just "by construction."**

### `organization.created` and `compliance.policy_activated` flows (execution_logs `57`)

Both event types inserted with a structurally valid payload (`organization_id`,
`aggregate_type`/`aggregate_id`, JSONB payload), landed as `PENDING`, and were
both successfully claimed via `fn_claim_outbox_events` as `app_worker` (→
`CLAIMED`). Fixtures cleaned up after.

**Result: PASS. DEP-6C-16's two required 6C flows are backed by the DB
implementation, live.**

---

## CONCURRENCY VALIDATION (execution_logs `58`) — LIVE, mandatory

20 PENDING rows seeded. Two **genuinely overlapping** `psql` sessions:

- **Session A** (backgrounded): `BEGIN` → `fn_claim_outbox_events('concurrency_worker_A', 10, 300)` → `SELECT pg_sleep(6)` (holds row locks open on its 10 claimed rows) → `COMMIT`.
- **Session B** (started 2 seconds into A's sleep, i.e. while A's transaction and row locks were still open): `BEGIN` → `fn_claim_outbox_events('concurrency_worker_B', 10, 300)` → `COMMIT`. B returned **immediately** (did not block waiting on A's locks), proving `SKIP LOCKED` behavior rather than lock-wait.

Programmatic verification of the returned id sets:

- A claimed 10 ids, B claimed 10 ids.
- **Intersection: empty** (0 ids returned to both workers).
- **Union: 20 distinct ids** (every seeded row claimed exactly once).
- Final DB state: 10 rows `CLAIMED` by `concurrency_worker_A`, 10 rows `CLAIMED` by `concurrency_worker_B`, no double-claims.

**Result: PASS. This is a real concurrency test — B's transaction was open
and racing against A's, not two sequential calls presented as concurrent.**

### Publish success / wrong-worker rejection / re-mark (execution_logs `59`)

- Correct-worker publish: `fn_mark_outbox_published(id, 'concurrency_worker_A')` on a row that worker holds → returns `true`, `status→PUBLISHED`, `published_at` set, `claimed_by`/`claimed_at` cleared.
- Wrong-worker publish attempt: same call with a different worker id on a row held by `concurrency_worker_A` → returns `false`, row **unchanged** (still `CLAIMED` by the original worker).
- Re-mark: calling publish again on the now-`PUBLISHED` row → returns `false` (no-op — CAS-guarded on `status='CLAIMED'`, correctly refuses to act on a non-CLAIMED row).

**Result: PASS on all three sub-cases.**

### Retry/failure (execution_logs `59`)

`fn_mark_outbox_failed(id, worker, error)` on a CLAIMED row before max
attempts → returns `PENDING`; `attempt_count` unchanged by the fail call
itself (only claim increments it); `available_at` pushed forward (~30s
default backoff); `claimed_by`/`claimed_at` cleared; `last_error` populated
with the given text. `last_attempt_at` reflects the most recent *claim* time
(set by `fn_claim_outbox_events`, not re-touched by the fail function) — this
is the function's actual, correct contract (a claim is an attempt; a fail is
its outcome), not a defect.

**Result: PASS.**

### Max-attempts / terminal FAILED state (execution_logs `60`)

A row driven through 10 claim→fail cycles (`attempt_count` 1→10, using
`p_next_attempt_at=NOW()` to skip the real backoff wait rather than waiting
30 real seconds × 9). At `attempt_count = max_attempts = 10`, the row
transitions to terminal `status='FAILED'`, is no longer returned by
`fn_claim_outbox_events`, and remains visible in the table (not silently
dropped) with `last_error` populated.

The file's first 9 sub-attempts are a documented test-design correction
(visible inline in the log): they first tried to steal the row from its
*original* claiming worker while that claim was still fresh (well within the
300s `claim_timeout_seconds`) and were correctly rejected as no-ops — itself
a valid confirmation of "a fresh, non-expired claim is not stolen," formally
re-tested as its own case next.

**Result: PASS.**

### Stale-claim recovery, with negative control (execution_logs `61`)

One `CLAIMED` row's `claimed_at` was manually backdated to 10 minutes ago
(simulating a crashed worker); a second `CLAIMED` row was left untouched
(~2 minutes old) as a negative control. A new worker called
`fn_claim_outbox_events(..., p_claim_timeout_seconds=300)` (5 minutes):

- The 10-minute-stale row **was** reclaimed by the new worker (`attempt_count` incremented 1→2).
- The ~2-minute fresh control row was **not** touched — remained claimed by its original worker, `attempt_count` unchanged.

**Result: PASS on both the positive and negative case.**

### Duplicate-delivery semantics (design property, confirmed against live function behavior)

Confirmed, not just asserted: nothing in the live schema or functions
transitions a row to `PUBLISHED` except an explicit
`fn_mark_outbox_published` call (tested above), and nothing deletes a row on
claim. If a worker's Redis publish succeeds but the process crashes or the
DB call fails before `fn_mark_outbox_published` commits, the row remains
`CLAIMED` and is later reclaimed as `PENDING` (proven live above, via the
stale-claim test) — it will be published again by a subsequent claim.

**Documented semantic: AT-LEAST-ONCE DELIVERY + IDEMPOTENT CONSUMERS.** No
attempt was made (or is required) to make Redis + PostgreSQL a single
distributed transaction.

### Redis integration (optional, Step 17) — explicitly not performed, not fabricated

No Redis instance and no runnable outbox-publisher application code exist
anywhere in this repository at this stage (Phase 6D/implementation has not
started). Per the governing task's own instruction:

**DB outbox persistence and publisher claiming semantics = LIVE VERIFIED.**
**Redis publisher application integration = not part of this migration
validation; no implementation exists yet to test.** This does not block
6C — DEP-6C-16 is about durable Postgres persistence backing the outbox, not
about the Redis publisher application (which is Phase 6D+ scope).

---

## FRESH DB VALIDATION (execution_logs `51`)

The same run recorded in "§0. Alembic state" above **is** the fresh-DB test:
a genuinely empty database, confirmed empty immediately before upgrade,
walked through the entire `001_5B → ... → 076_5K1 → 077_5J1` chain in one
`alembic upgrade head` invocation, exit code 0, single head `077_5J1`
afterward. No separate run was performed since one run already satisfies
both "confirm 077 applies on a genuinely fresh DB" and "confirm the full
historical chain still applies cleanly."

**Result: PASS.**

---

## REGRESSION VALIDATION (execution_logs `62`) — LIVE

Run against the same post-077 fresh database:

| Check | Result |
|---|---|
| Any `SECURITY DEFINER` function (repo-wide) with missing/unsafe `search_path` | **0 found** — 077's own 4 functions included, no regression in the pre-existing ones |
| `BYPASSRLS` role list | Unchanged: `app_migration`, `app_platform_admin` (+ the connecting superuser) |
| Phase 5K.1 Defect B fix (`app_platform_admin` must not have `INSERT` on `workflow.workflow_executions`) | Still holds — only `SELECT`/`UPDATE`/`DELETE` granted |
| `audit.audit_events` / `audit.audit_chain` | Untouched — 17 columns (unchanged baseline), table still present |
| Aggregate counts (tables/functions/triggers/indexes/RLS tables) | 200 tables, 66 non-system-schema functions, 106 triggers, 826 indexes, 91 RLS-enabled tables — consistent with the 076 baseline plus exactly 077's own additions (1 table, 4 functions, 1 trigger, 4 explicit indexes), nothing else moved |

**Result: PASS. No regression from 077.**

---

## Summary table

| # | Check | Classification |
|---|---|---|
| 1 | Table exists | PASS (LIVE) |
| 2 | Columns/types — **17, corrected from prior report's 16** | PASS (LIVE) |
| 3 | Constraints — **7 CHECK + 1 PK, corrected from prior report's "8 CHECK"** | PASS (LIVE) |
| 4 | Indexes (definitions, not just names) | PASS (LIVE) |
| 5 | Role grants | PASS (LIVE) |
| 6 | No unintended RLS bypass | PASS (LIVE) |
| 7 | Two workers can't double-claim | **PASS (LIVE) — genuine overlapping-transaction test, not construction-by-analogy** |
| 8 | Event insertable in same transaction as domain state, COMMIT | PASS (LIVE) |
| 9 | Rollback of domain transaction also rolls back outbox row | PASS (LIVE) |
| 10 | Publisher failure leaves event retryable | PASS (LIVE) |
| 11 | Duplicate Redis publication safe by design | PASS (LIVE function-behavior confirmation; Redis-side integration N/A, no implementation exists yet) |
| 12 | `organization.created` flow can write and be claimed | PASS (LIVE) |
| 13 | `compliance.policy_activated` flow can write and be claimed | PASS (LIVE) |
| 14 | Wrong-worker publish rejected | PASS (LIVE) |
| 15 | Max-attempts → terminal FAILED, no longer claimable, still observable | PASS (LIVE) |
| 16 | Stale claim reclaimed; fresh claim not stolen | PASS (LIVE, positive + negative case) |
| 17 | Fresh DB 001→077 upgrade | PASS (LIVE) |
| 18 | Regression/security suite | PASS (LIVE) |

**Overall: 18/18 PASS, all with live execution evidence captured in
`../execution_logs/` (files `51`-`62`, prefix `20260823T061055Z`). No defect
was found in `077_5J1.sql` or `077_5J1.py` — no SQL was modified, and the
file's SHA-256 (`eac7022c...4a990`, 15559 bytes) is unchanged from
`MIGRATION_MANIFEST.md`'s recorded value.**

---

## What this report does NOT claim

- It does not claim exactly-once delivery — the design is deliberately
  at-least-once, with idempotent consumers as the documented consumer-side
  requirement.
- It does not claim a live end-to-end Redis Streams publish test was
  performed — no publisher application code exists yet to test (Phase 6D+
  scope); this is stated explicitly, not silently assumed passing.
- It does not claim the future `POST /organizations` / compliance-activation
  endpoint *implementations* already call this table correctly — only that
  the table and functions, as committed and now live-verified, impose no
  obstacle to their doing so correctly.
- It does not claim this validation database's structural counts were
  compared row-for-row against every one of Phase 5K's original ~50 checks —
  the regression pass targeted the security/Alembic invariants 077 could
  realistically affect, per the governing task's own instruction for when
  the full suite is expensive to re-run in full.

## Revision history

- **2026-08-23, static-only version (superseded):** written in a session
  with no functional `psql`/Python/Alembic runtime available; 13/13
  static/structural checks PASS, but explicitly not live-execution evidence,
  and contained two structural miscounts (16 columns instead of 17; "8 CHECK
  constraints" instead of the actual 7) corrected in this version.
- **2026-08-23, this version:** full live PostgreSQL 18 validation,
  concurrency-tested, security/grant-tested, fresh-DB tested, regression
  tested. Supersedes the static-only version above.
