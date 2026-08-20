# Phase 5K — Alembic Validation Report

**Date:** 2026-08-19
**Scope:** `docs/phase-05-database-design/5K/alembic/` only. This report covers chain
integrity, the fresh-database upgrade gate, and downgrade policy. Schema-content
validation is in `SCHEMA_VALIDATION_REPORT.md`; migration-manifest/defect reconciliation
is in `MIGRATION_RECONCILIATION_REPORT.md`; the consolidated gate table is in
`FINAL_5K_VALIDATION_REPORT.md`.

This file is one of the four mandated §7 validation reports, split out of the
original interim `validation/01_final_validation_report.md` (now removed).

---

## 1. Alembic chain integrity

| Check | Result |
|---|---|
| Revision count | 75, matches `migrations/*.sql` count exactly, 1:1 by filename |
| Root | `001_5B`, `down_revision=None` |
| Head | `075_5J` — single head, confirmed via `alembic heads` (both pre- and post-upgrade) |
| Branches | None — `alembic history` shows one linear chain, base → head |
| Duplicate/orphan/missing revisions | None found |
| `alembic.ini` | No baked-in `sqlalchemy.url`; standard logging config; sound |
| `env.py` | `DATABASE_URL` read exclusively from environment, raises loudly if unset; `target_metadata = None` (autogenerate deliberately disabled, cannot propose a competing schema); `transaction_per_migration=True` in both offline and online modes |
| Destructive-autogenerate risk | None — `target_metadata=None` makes `alembic revision --autogenerate` a no-op against this package by design |

Evidence: `execution_logs/20260819T061806Z_01_alembic_history_verbose.txt`, `_02_alembic_history_order.txt`, `_03_alembic_heads_preflight.txt`.

**Result: PASS.**

---

## 2. Fresh-database upgrade (critical gate)

A disposable PostgreSQL 16 container (`pgvector/pgvector:pg16`) was dropped and recreated immediately before this run to guarantee a genuinely empty starting database (confirmed via `\dn`/`\dt *.*` showing zero user schemas/tables beforehand).

```
alembic upgrade head
  -> 75/75 "Running upgrade" steps, base -> 075_5J, exit code 0
alembic current  -> 075_5J (head)
alembic heads    -> 075_5J (head)
```

**One real defect was found and fixed during this gate**, on the first true fresh-DB attempt:

- **Symptom:** failed at revision `002_5B` with `TypeError: sqlalchemy.cyextension.immutabledict.immutabledict is not a sequence`.
- **Root cause:** `_frozen_sql.py`'s `run_frozen_sql()` called `op.get_bind().exec_driver_sql(sql)` with no execution options. Several frozen files contain literal `%` characters (`LIKE 'secret_manager://%'` patterns in `002_5B.sql`, `RAISE EXCEPTION '...: %, %'` format specifiers) that psycopg2's default pyformat paramstyle misreads as bind-parameter placeholders.
- **Classification:** implementation defect in the Alembic integration layer only. No `.sql` file in `migrations/` was modified. No Phase 5A-5J design was touched.
- **Fix:** `bind.execution_options(no_parameters=True).exec_driver_sql(sql)` — tells the DBAPI the statement takes no bind parameters, so `%` passes through verbatim. Applied in `alembic/_frozen_sql.py`.
- **Re-validation:** database dropped and recreated again from zero; `alembic upgrade head` re-run; all 75 revisions applied cleanly, exit code 0.

Evidence: `execution_logs/20260819T061806Z_04_alembic_current_preflight.txt` (pre-existing state before drop), `_05_alembic_upgrade_head_fresh_db.txt` (the successful fresh run), `_06_alembic_current_post_upgrade.txt`, `_07_alembic_heads_post_upgrade.txt`. (The single earlier failing attempt's raw output was overwritten by the successful re-run and is not preserved as a standalone file; its root cause, fix, and re-validation are documented here and in `EXECUTION_REPORT.md` and `alembic/README.md`.)

**Result: PASS** (after one fix, re-verified from a genuinely empty database).

The disposable container was reused (without re-dropping) for the subsequent §18/§19
live-test batches documented in `FINAL_5K_VALIDATION_REPORT.md` — it remained at
`075_5J` throughout, no re-migration was needed, and no schema-altering statement was
issued by any of those tests (only fixture-row `INSERT`/`DELETE` and read/write
security-and-concurrency probes against the already-migrated schema).

---

## 3. Downgrade policy validation

Phase 5K is **forward-only by explicit, documented design**:

- Every one of the 75 `alembic/versions/*.py` files' `downgrade()` raises `NotImplementedError`, with an identical, explicit rationale: no rollback DDL exists in the frozen SQL package, and none is authored in the Alembic layer, to avoid creating a second schema-change surface outside `migrations/*.sql`. Spot-checked across `001_5B.py`, `043_5F.py`, and confirmed the pattern is generated deterministically (not hand-varied) by `alembic/gen_revisions.py`'s single shared template — so it is universal across all 75, not just the files individually inspected.
- `alembic/README.md` states this policy explicitly: *"Recovery from a bad migration is: fix forward, or restore from backup — never an Alembic downgrade."*
- `5K-Database-Migration-and-Implementation.md` §15 ("Migration Failure and Recovery") describes automatic per-revision transactional rollback-on-*failure* (a mechanical property of `transaction_per_migration=True`, already confirmed structurally in `env.py`) — this is a different concept from downgrading an already-successfully-applied revision, and does not conflict with the forward-only policy above.

Per the task's explicit instruction not to invent downgrade behavior or blindly downgrade against a documented upgrade-only policy: **no live downgrade test was performed.** Running one would contradict the documented architecture rather than validate it.

**Result: PASS** (policy confirmed forward-only; consistently implemented across all 75 revisions; no live downgrade test required or performed).

---

## Section result

**ALEMBIC VALIDATION: PASS.** Chain integrity confirmed real (not assumed), fresh-database
upgrade gate passed after one real, correctly-classified implementation-layer fix,
downgrade policy confirmed forward-only and consistently implemented. No architectural
change was made to Phase 5A-5J; the one fix applied was strictly to
`alembic/_frozen_sql.py`, not to any frozen `.sql` migration.

---

## 4. Phase 5K.1 — corrective patch chain re-validation (2026-08-19)

A new forward revision, `076_5K1` (`down_revision = "075_5J"`), was added on
top of the validated 75-revision chain above to fix two BLOCKING defects
found during Phase 5K final validation (see `MIGRATION_RECONCILIATION_REPORT.md`
and `FINAL_5K_VALIDATION_REPORT.md`). None of the 75 pre-existing revisions
were modified, renumbered, or had their revision IDs changed.

| Check | Result |
|---|---|
| Revision count | 76, matches `migrations/*.sql` count exactly (76), 1:1 by filename |
| New head | `076_5K1` — single head, confirmed via `alembic heads` |
| `down_revision` of `076_5K1` | `075_5J` — correctly chains onto the prior head |
| Branches | None — `alembic branches` returned no output; `alembic history \| grep -c '\->'` = 76 |
| `alembic current` after upgrade | `076_5K1 (head)` |
| Downgrade policy | `076_5K1.py`'s `downgrade()` raises `NotImplementedError`, identical pattern to all 75 prior revisions — forward-only policy preserved, not broken by the patch |

Fresh-database re-run (governing-spec §10): a genuinely empty PostgreSQL 16
container was created (not the reused validation container), and `alembic
upgrade head` was run from base:

```
alembic upgrade head
  -> 76/76 "Running upgrade" steps, base -> 076_5K1, exit code 0
     (final step: Running upgrade 075_5J -> 076_5K1)
alembic current  -> 076_5K1 (head)
alembic heads    -> 076_5K1 (head)
alembic branches -> (empty, no branch points)
```

Evidence: `../execution_logs/20260819T110500Z_42_fresh_docker_env_setup_5K1.txt`
(empty-DB confirmation), `_43_alembic_upgrade_head_001_to_076_fresh_db.txt`
(full 76/76 upgrade log), `_44_alembic_history_heads_current_post076.txt`
(heads/current/branches/history count + file-count cross-check).

**Result: PASS.** Single linear chain, single new head `076_5K1`, correct
`down_revision`, forward-only policy intact, 76/76 revisions apply cleanly
against a fresh database.
