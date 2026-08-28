# PostgreSQL 16 Migration Validation Report

**Date:** 2026-08-28 (Phase 6H Final Blocker Remediation pass)
**Scope:** re-validate `098_5E1.sql`/`099_5C1.sql` (post-rewrite) against the
declared production baseline, PostgreSQL 16 — every prior 6H validation pass
had run only against a local PostgreSQL 18 instance.

## Environment

No Docker engine is available in this environment (reconfirmed in this
pass). A native PostgreSQL 18 install already exists at `C:\Program
Files\PostgreSQL\18` (used by unrelated, earlier validation passes) — it was
never touched by this batch.

The EDB full GUI installer for PostgreSQL 16.10
(`postgresql-16.10-1-windows-x64.exe`, downloaded directly from
`get.enterprisedb.com`) was attempted first, in fully unattended/silent mode
(`--mode unattended --unattendedmodeui minimal`). It genuinely failed:

```
Start-Process : This command cannot be run due to the error: The requested
operation requires elevation.
```

This is reported as a real, encountered failure, not smoothed over — the
current OS user is a member of `Administrators` but the shell session runs
at a non-elevated token (standard Windows UAC split-token behavior), and no
interactive UAC prompt can be answered in this non-interactive environment.
Rather than claim PostgreSQL 16 was unavailable, the binaries-only
distribution (`postgresql-16.10-1-windows-x64-binaries.zip`, same host, same
version) was used instead — a zip of the server binaries with no installer
and no Windows service registration, which requires no elevation. It was
extracted to `C:\Users\Dell\pgval16\pgsql` (a short path was required —
extracting under this session's much longer temp scratchpad path hit
Windows' `MAX_PATH` limit partway through the bundled pgAdmin4 Python
package tree, confirmed by the actual `DirectoryNotFoundException`, not
assumed). `initdb` and `pg_ctl start -o "-p 5433"` were run directly as the
current OS user, with `trust` authentication for local/loopback connections
— appropriate for a disposable, throwaway validation instance never exposed
beyond `127.0.0.1`.

```
2026-08-28 20:00:55.057 IST LOG:  starting PostgreSQL 16.10, compiled by Visual C++ build 1944, 64-bit
2026-08-28 20:00:55.061 IST LOG:  listening on IPv4 address "127.0.0.1", port 5433
2026-08-28 20:00:55.158 IST LOG:  database system is ready to accept connections
```

### Required extensions

`pgcrypto` and `pg_stat_statements` are bundled with the binaries-only zip
and loaded without incident. `vector` (pgvector) is **not** bundled in the
binaries-only zip (only the full GUI installer's Stack Builder add-on
carries it, and that path was unavailable per above). Rather than skip
pgvector or assume it would behave identically to the already-installed
PostgreSQL 18 build, it was built from source:

1. Copying the existing PostgreSQL 18 `vector.dll` into the PG16 install and
   attempting `CREATE EXTENSION vector` was tried first, specifically to
   empirically confirm (not assume) that extension binaries are
   major-version-locked. It failed exactly as expected:
   `ERROR: incompatible library ... version mismatch DETAIL: Server is
   version 16, library is version 18.` The mismatched files were removed
   immediately after this confirmation.
2. `pgvector` source tag `v0.8.0` was downloaded from GitHub and built via
   its documented Windows path (`nmake /f Makefile.win`) using the Visual
   Studio 18 (MSVC 14.51.36231) toolchain already present on this machine,
   against this PG16 install's own `include/server` headers and
   `postgres.lib` import library. Build succeeded cleanly (no errors); `nmake
   /f Makefile.win install` copied the resulting `vector.dll`,
   `vector.control`, and SQL definition files into the PG16 install tree.

```
CREATE EXTENSION
CREATE EXTENSION
CREATE EXTENSION
      extname       | extversion
--------------------+------------
 plpgsql            | 1.0
 vector             | 0.8.0
 pgcrypto           | 1.3
 pg_stat_statements | 1.10
(4 rows)
```

All three required extensions confirmed loadable on genuine PostgreSQL
16.10, live, before any migration was run.

## Fresh-database validation

`voice_agent_pg16_fresh` created empty; `alembic upgrade head` run from a
throwaway `uv`-managed Python 3.12 venv (`alembic==1.19.1`,
`sqlalchemy==2.0.52`, `psycopg[binary]==3.3.4`) at
`docs/phase-05-database-design/5K/.venv_validation_pg16` (removed at the end
of this batch).

**Result: PASS, exit code 0.** Full `001_5B → … → 099_5C1` chain applied,
raw output in `execution_logs/20260828T143000Z_63_pg16_fresh_upgrade_001_to_099.txt`.

```
$ alembic -c alembic.ini heads
099_5C1 (head)
$ alembic -c alembic.ini current
099_5C1 (head)
```

Single head, current equals head — see `execution_logs/…_64…txt` and
`…_65…txt`.

## Incremental upgrade validation

A second database, `voice_agent_pg16_incremental`, was pinned at `097_5D5`
first (`alembic upgrade 097_5D5`, exit code 0 — `execution_logs/…_66…txt`),
mirroring a real pre-remediation deployment, then upgraded forward:

```
INFO  Running upgrade 097_5D5 -> 098_5E1, ...
INFO  Running upgrade 098_5E1 -> 099_5C1, ...
```

**Result: PASS, exit code 0** (`execution_logs/…_67…txt`).
`alembic current`/`alembic heads` both confirm `099_5C1 (head)` afterward.

## What this report does NOT claim

This report does not re-run the full Phase 5K structural inventory (table/
FK/index/RLS counts) already established on PostgreSQL 16 and 18 in earlier
batches (see `execution_logs/README.md`, first batch) — those counts are
unaffected by this remediation, which is additive-only within `campaign`
and `voice`. It also does not claim the EDB full installer works in this
environment; it explicitly failed and that failure is preserved above
rather than omitted.

## Cleanup

At the end of this batch: `pg_ctl stop` was run against the PG16 instance;
the entire `C:\Users\Dell\pgval16` tree (binaries, data directory, pgvector
source, both validation databases) was deleted; the throwaway
`.venv_validation_pg16` virtual environment and any `__pycache__`
directories it created were removed. The pre-existing PostgreSQL 18 instance
was never started, stopped, or modified by this batch.
