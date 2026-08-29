# Phase 5K — Alembic integration layer

**Baseline note (2026-08-29):** PostgreSQL 18.x is now the platform's authoritative database baseline (see `5K-Database-Migration-and-Implementation.md` §5, `6J-Integrations-Webhooks-Plugins-APIs.md` §63). The "Update (Phase 5K final validation, 2026-08-19)" section below is retained unchanged as an accurate historical record of the original PostgreSQL 16 validation run — it is not rewritten. A CI/local disposable-database test pattern going forward should use a PostgreSQL 18 image (e.g. `pgvector/pgvector:pg18`, unverified exact tag — confirm against the current published tag before use) in place of the `pg16` tag that historical run used.

## What this is (and isn't)

This directory does **not** define the schema. The schema of record is
the frozen, canonical SQL package at [`5K/migrations/001_5B.sql`
.. `075_5J.sql`](../migrations/). Alembic here is strictly a
**tracking/integration layer**:

- `target_metadata = None` in [`env.py`](env.py) — there is no ORM
  model to diff against, so `alembic revision --autogenerate` cannot
  propose a second, competing schema history.
- Each file in [`versions/`](versions/) is a 1:1 wrapper around exactly
  one frozen `.sql` file, named after it (`001_5B.py` wraps
  `001_5B.sql`, … `075_5J.py` wraps `075_5J.sql`). `upgrade()` reads
  that file's bytes and executes them verbatim via
  `op.get_bind().exec_driver_sql(...)` (see
  [`_frozen_sql.py`](_frozen_sql.py)). No revision file embeds a copy
  of migration SQL.
- The chain is linear and matches the manifest in
  `5K-Database-Migration-and-Implementation.md` §22 exactly: root
  `001_5B`, head `075_5J`, 75 revisions, no branches (verified
  programmatically — see Verification below).
- `downgrade()` on every revision raises `NotImplementedError`. The
  frozen SQL package is forward-only — no `.sql` file defines rollback
  DDL, and none is authored here, because doing so would itself be a
  schema change living outside the canonical migration files. Recovery
  from a bad migration is: fix forward, or restore from backup — never
  an Alembic downgrade.

## DATABASE_URL

`alembic.ini` has no `sqlalchemy.url` and never will. `env.py`'s
`get_url()` reads `DATABASE_URL` from the environment and raises if
it's unset. No credentials are read from or written to any file in
this directory.

```bash
export DATABASE_URL="postgresql+psycopg2://<user>:<password>@<host>:5432/voice_agent_dev"
```

## Transaction behavior

`env.py` configures `transaction_per_migration=True`: each of the 75
revisions commits or rolls back independently, matching how 001–075
were actually run (§15.1/§20 of the frozen spec) — a failure in one
revision doesn't unwind everything before it.

**On migration 043 specifically:** the frozen spec (§21) describes
migration 043 as needing non-transactional/autocommit handling because
`CREATE INDEX CONCURRENTLY` cannot run inside a transaction. **The
frozen `migrations/043_5F.sql` file itself does not do this** — its
own header comment explains that `document_chunks` is partitioned, the
only partition at migration time is the empty DEFAULT partition, and a
plain transactional `CREATE INDEX` (no `CONCURRENTLY`) is used instead;
`CONCURRENTLY` is deferred to the application-layer
`create_kb_partition()` path for future per-KB partitions. So
`versions/043_5F.py` runs transactionally like every other revision —
this matches the actual frozen SQL, not the narrative in §21/§8.2 of
the spec doc, which predates that implementation decision. This
discrepancy between the spec doc and the frozen SQL is noted here
rather than silently resolved one way; the SQL file (what will actually
execute) was treated as authoritative.

The autocommit mechanism these revisions *would* use, if a future
revision genuinely needed it, is Alembic's own
`context.autocommit_block()`:

```python
def upgrade() -> None:
    with op.get_context().autocommit_block():
        run_frozen_sql(SQL_FILE)
```

`gen_revisions.py` (the one-time generator used to produce
`versions/001_5B.py`..`075_5J.py`, kept in this repo for
reproducibility — see below) has an explicit, currently-empty
`AUTOCOMMIT_REVISIONS` set for this purpose.

## Regenerating `versions/`

`versions/*.py` were produced once by a small generator script from
the `migrations/` directory listing, not written by hand or by
`alembic revision --autogenerate`. It is deterministic (revision id =
filename stem, down_revision = previous file's stem) and is safe to
re-run if `migrations/` ever gains a genuinely new, additional file
after 075 — **never** to regenerate 001–075 differently, since those
are frozen.

## Baseline strategy for the existing database

**The local database already has 001–075 applied.** Do not run
`alembic upgrade head` against it — Alembic has no record of that
history yet, and would attempt to re-run all 75 `CREATE SCHEMA` /
`CREATE TABLE` / etc. statements from scratch. Most of this package
uses `IF NOT EXISTS` / `ON CONFLICT DO NOTHING` guards, but not
uniformly (e.g. plain `CREATE INDEX`, `ALTER TABLE ... ADD CONSTRAINT`
without existence checks), so a blind `upgrade head` against an
already-migrated database can fail partway or, worse, partially
succeed against the wrong objects.

The correct procedure is to **stamp**, not upgrade:

```bash
cd 5K/alembic
export DATABASE_URL="postgresql+psycopg2://...voice_agent_dev"

# 1. Confirm current DB state first (read-only) — do NOT skip this.
psql "$DATABASE_URL" -c "\dn"                              # expect 15 schemas
psql "$DATABASE_URL" -c "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema');"
psql "$DATABASE_URL" -c "select to_regclass('public.alembic_version');"  # expect NULL if never stamped

# 2. Only after confirming the schema already matches 001-075, record
#    that fact in Alembic's own bookkeeping table without executing
#    any migration SQL:
alembic -c alembic.ini stamp 075_5J

# 3. Verify
alembic -c alembic.ini current      # -> 075_5J (head)
psql "$DATABASE_URL" -c "table alembic_version;"
```

`alembic stamp <revision>` only writes/updates the `alembic_version`
table; it never executes any `upgrade()`/`downgrade()` function. This
is the only Alembic command that should touch this database until the
stamp has been applied and verified.

From then on, `alembic upgrade head` is a no-op against this database
(already at head), and any future 076+ migration is added the normal
way: a new frozen `.sql` file plus one new wrapper revision with
`down_revision = "075_5J"`.

## Update (Phase 5K final validation, 2026-08-19): executed against a live database

The "What was NOT done" section below described the state of this package
before Phase 5K final validation. It has since been **executed successfully
against a genuinely fresh, empty PostgreSQL 16 database** (`pgvector/pgvector:pg16`,
disposable Docker instance, dropped and recreated immediately before the run
to guarantee emptiness): `alembic upgrade head` applied all 75 revisions in
order, `alembic current` / `alembic heads` both report `075_5J (head)`, and
the resulting schema was independently queried and validated. Full command
output is in `../execution_logs/`; the consolidated result is in
`../validation/ALEMBIC_VALIDATION_REPORT.md` (the interim
`01_final_validation_report.md` this used to point to has since been split
into the four §7-mandated validation reports and removed).

One real defect was found and fixed during this run: `_frozen_sql.py`'s
`run_frozen_sql()` originally called `op.get_bind().exec_driver_sql(sql)`
with no `execution_options`. Several frozen files (e.g. `002_5B.sql`) contain
literal `%` characters — `LIKE 'secret_manager://%'` patterns and
`RAISE EXCEPTION '...: %, %'` format specifiers — which psycopg2's default
pyformat paramstyle misreads as bind-parameter placeholders, failing with
`TypeError: ... immutabledict is not a sequence` before any SQL reaches the
server. Fix: `bind.execution_options(no_parameters=True).exec_driver_sql(sql)`
tells the DBAPI the statement takes no bind parameters, so `%` passes through
verbatim. This is an Alembic-integration-layer defect only — no `.sql` file
in `migrations/` was touched. Re-run from a dropped/recreated empty database
confirmed 75/75 revisions pass cleanly with the fix applied.

Given this, the manual "Baseline strategy: stamp, don't upgrade" procedure
below still applies to any database that already has 001-075 applied outside
of Alembic's bookkeeping (e.g. an existing `voice_agent_dev`) — use `alembic
stamp 075_5J` there, exactly as documented. It does **not** apply to a
genuinely empty database, which should simply run `alembic upgrade head`.

## What was NOT done in this environment (historical — see update above)

This section describes an earlier point in Phase 5K's history, before final
validation. At that time, this Alembic package had been authored and
syntax-checked (`python3 -m py_compile` on all 75 revision files; chain
linearity verified programmatically: single root `001_5B`, single head
`075_5J`, 75 nodes, no branches) but **not yet executed against a live
database**:

- `alembic`, `sqlalchemy`, and a PostgreSQL driver (`psycopg2`/`psycopg`)
  were not installed in that environment, and installing them required
  `pip`/`venv` support (`ensurepip`) that wasn't available without `sudo`.
- No PostgreSQL credentials for `voice_agent_dev` (or any role) were
  available in that environment, repo, or a `.env` file — `psql`
  connection attempts with no password failed authentication.

Because of this, `alembic stamp 075_5J` was not run at that time. Doing so
blind, without confirming the live schema state first, would have been
exactly the "blindly run upgrade head" failure mode this package is designed
to avoid — so it was left as a documented, reviewable manual step instead of
guessed at. That gap has since been closed for the fresh-database case (see
the update above); the stamp procedure remains the correct path for an
already-migrated database.
