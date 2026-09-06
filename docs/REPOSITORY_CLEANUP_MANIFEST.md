# Repository Cleanup Manifest

**Date:** 2026-09-06
**Scope:** Repository hygiene / consolidation pass only. No product design, database
design, or API contract changes. No new migration. No migrations 001-109 modified.
No database, Alembic, or Docker execution performed — all verification in this pass
is static (file inventory, grep-based reference analysis, SHA-256 hashing).

Phase 6M remains **APPROVED / FROZEN**; migration head remains `109_5B7`. This pass
did not touch, re-open, or re-litigate that status.

---

## 1. Baseline (pre-cleanup)

- 109 SQL migrations (`docs/phase-05-database-design/5K/migrations/`)
- 109 Alembic revision wrappers (`docs/phase-05-database-design/5K/alembic/versions/`)
- 13 Phase 6 canonical API-design documents (`docs/phase-06-api-design/6A`–`6M`)
- 10 Phase 5 canonical database-design documents (`docs/phase-05-database-design/5A`–`5J`)
- ~416 files under `docs/phase-05-database-design/5K/execution_logs/` (raw validation/
  remediation transcripts and fixture/test scripts, including `README.md` and the
  `scripts/` subdirectory)
- 24 files under `docs/phase-05-database-design/5K/validation/` (curated validation
  reports)

## 2. Deleted (45 files total, all under `5K/execution_logs/`)

Every deleted file was (a) not cited by filename, range, or wildcard from any
retained canonical document, validation report, `MIGRATION_MANIFEST.md`, or
`EXECUTION_REPORT.md` anywhere in the repository, and (b) either a repeated/
single-count query capture, a superseded intermediate fixture/gate/command
script, or a scratch pairing whose actual result is preserved in a companion
file that was **not** deleted. No canonical document was deleted. No file whose
deletion would have left a unique, un-reproduced piece of evidence was removed.

### 2a. First batch (Phase 5K, `20260819T061806Z` / `20260819T072859Z` prefixes) — 23 files
Single-count/repeated-capture schema queries and one Alembic-preflight/post-upgrade
pair whose values are already captured, in full, by the retained consolidated file
`20260819T061806Z_09_schema_tables_full.txt`:
`02_alembic_history_order.txt`, `03_alembic_heads_preflight.txt`,
`06_alembic_current_post_upgrade.txt`, `07_alembic_heads_post_upgrade.txt`,
`08_schema_extensions.txt`, `10_schema_table_counts_by_schema.txt`,
`11_schema_fk_count.txt`, `12_schema_pk_count.txt`, `13_schema_unique_count.txt`,
`14_schema_check_count.txt`, `15_schema_index_count.txt`, `16_schema_view_count.txt`,
`17_schema_matview_count.txt`, `18_schema_function_count.txt`,
`19_schema_trigger_count.txt`, `20_schema_enum_count.txt`,
`21_schema_sequence_count.txt`, `22_schema_rls_tables.txt`,
`23_schema_policy_count.txt` (19 files) — plus the fixture-setup/scratch pairing
`26_fixture_setup.txt`, `31_fixture_setup_2.txt`, `33_fixture_orgb.txt`, and the
superseded `36_security_row5_worker_row13_readonly.txt` (its corrected,
authoritative re-run is retained as `36b_security_row5_worker_direct_auth.txt` /
`36c_security_row6_appapi_platform_event_denied.txt` / the retained `37` file).

### 2b. First-batch fixture/scratch scripts (`5K/execution_logs/scripts/`) — 4 files
`20260819T072859Z_setup_fixtures.sql`, `20260819T072859Z_fixtures_2.sql`,
`20260819T072859Z_fixtures_orgb.sql`, `20260819T072859Z_test18_row5_worker_readonly.sql`
— fixture/setup source for the 2a scratch-log pairing above and for the superseded
row-5/row-13 test, superseded by the corrected `36b`/`36c` re-run scripts (retained).

### 2c. Sixth batch (Phase 6H, `20260828T143000Z` prefix) — 2 files
`68_fixture_setup.sql`, `70_reserve_dispatch_tests.sql` — command/fixture inputs
whose results are fully captured by the retained result files `69_privilege_and_
dispatch_state_machine_tests.txt` and `71_voice_dispatch_claim_concurrency_race.txt`.

### 2d. Seventh batch (Phase 6H Final Micro-Remediation, `20260828T210000Z` prefix) — 8 files
`74_final_pg16_fresh_upgrade.txt`, `75_final_alembic_heads.txt`,
`76_final_alembic_current.txt`, `77_final_pg16_incremental_upgrade_to_097.txt`,
`78_final_pg16_incremental_upgrade_097_to_head.txt`,
`79_final_reconciliation_fixture_setup.sql`, `80_final_reconciliation_tests.sql`,
`82_final_regression_tests.sql` — fresh/incremental-chain gate and command/fixture
inputs; their outcomes are fully captured by the retained result files
`81_final_reconciliation_privilege_and_provenance_output.txt` and
`83_final_regression_output.txt`.

### 2e. Eighth batch (Phase 6H Final Micro-Fix, `20260828T231500Z` prefix) — 8 files
`84_final_pg16_fresh_upgrade.txt`, `85_final_alembic_heads.txt`,
`86_final_alembic_current.txt`, `87_final_pg16_incremental_upgrade_to_097.txt`,
`88_final_pg16_incremental_upgrade_097_to_head.txt`,
`89_final_provenance_fixture_setup.sql`, `90_final_provenance_tests.sql`,
`92_final_regression_tests.sql` — same rationale as 2d; outcomes fully captured
by the retained result files `91_final_provenance_output.txt` and
`93_final_regression_output.txt`.

**Total deleted: 19 + 4 + 4 + 2 + 8 + 8 = 45 files.**

No files were deleted from `docs/phase-05-database-design/5K/validation/`
(24/24 retained — the default per the task's conservative-KEEP policy; no
report met all conditions required to justify removal), from the migration or
Alembic directories, or from any Phase 1-4 / Phase 5 / Phase 6 canonical
document location. No generated-artifact files (`__pycache__/`, `*.pyc`,
`*.tmp`, `.DS_Store`, etc.) were found anywhere in the repository.

## 3. Retained canonical evidence (explicitly verified present, untouched)

- `docs/phase-05-database-design/5K/validation/6M_FINAL_VALIDATION_REPORT.md`
- `docs/phase-05-database-design/5K/validation/6M_FREEZE_01_fresh_incremental_upgrade.txt`
- `docs/phase-05-database-design/5K/validation/6M_FREEZE_02_platform_billing_security.txt`
- `docs/phase-05-database-design/5K/validation/6M_FREEZE_03_identity_webhook_security.txt`
- `docs/phase-05-database-design/5K/validation/6M_FREEZE_04_heads_checksums.txt`
- All 10 Phase 5 canonical documents (5A-5J), all 13 Phase 6 canonical documents
  (6A-6M), all Phase 1-4 documents — byte-for-byte unmodified by this pass.
- All 109 SQL migrations and all 109 Alembic revision wrappers — byte-for-byte
  unmodified (see Integrity, below).
- All 24 files in `docs/phase-05-database-design/5K/validation/`.
- 371 remaining files in `docs/phase-05-database-design/5K/execution_logs/`
  (370 raw evidence/script files plus the rewritten `README.md` index).

## 4. `execution_logs/README.md`

This is the one file the task authorized for rewrite. It was edited surgically
(not rewritten wholesale) to remove/consolidate table rows and narrative
references for the 45 files deleted above, while preserving every narrative
section name verbatim ("First batch" through "Ninth batch", "Phase 6K FINAL
Freeze-Gate Remediation", "Phase 6K FINAL Freeze-Gate Remediation Pass",
"Phase 6K FINAL Webhook Processing Integrity Remediation") and all defect-
discovery/finding prose. Each removed-row note points back to this manifest.
No architectural, design, or semantic content was altered — only bookkeeping
of which raw files still exist on disk.

## 5. Integrity

**Migrations (109/109) and Alembic revisions (109/109):** SHA-256 hashed before
and after the cleanup pass. Result: **100% byte-identical**, including the
frozen head:

- `109_5B7.sql` — `a761239d7e63e3d2d982f4dbf7291b81711a24dc051c2577bc44ff46052b0cf3` (53,473 bytes) — verified unchanged.
- `109_5B7.py` — `d60f497b9c6c494e051b86d2f086211c77aef8e6b46bc390321e179e83fb9602` (4,949 bytes) — verified unchanged.

No migration numbered 110 exists. No migration in the 001-109 range was
renamed, renumbered, reformatted, regenerated, or merged. `MIGRATION_MANIFEST.md`
and the Alembic package files were not modified.

**Broken-reference scan:** every one of the 45 deleted filenames was grepped
(by basename) against every Markdown file in the repository, both before
deletion (as a pre-flight safety check) and after (as a final verification).
Result both times: **0 hits** outside the file being edited (`README.md`
itself, whose own remaining references were converted to explanatory notes
pointing at this manifest).

**Canonical document counts (post-cleanup, verified):**
- Phase 5 canonical documents: 10/10 present.
- Phase 6 canonical documents: 13/13 present.
- Phase 1-4 canonical documents: present (directory-level check).
- SQL migrations: 109/109, no `110_*`.
- Alembic revisions: 109/109, no `110_*`.

**`git status` after cleanup:** exactly 45 deletions (all under
`5K/execution_logs/`, including its `scripts/` subdirectory) and one
modification (`5K/execution_logs/README.md`). No other file in the repository
was touched by this pass.

## 6. Discovered pre-existing inconsistencies (reported, not fixed)

Per the task's instructions, these were found during analysis and are reported
here without modification, since fixing them would go beyond a hygiene pass:

- `MIGRATION_MANIFEST.md:1830` cites the evidence file as
  `20260904T012500Z_6M_25_06_incr_fixture_survival_check.sql.txt`. Both a `.sql`
  and a `.txt` variant of this file genuinely exist on disk under
  `execution_logs/`; the `.sql.txt` citation appears to be a pre-existing
  typo predating this cleanup pass. Both files were retained untouched.
- A repo-wide scan for temp/scratch/backup-style filenames flagged
  `20260823T061055Z_60_max_attempts_failed_state_test.txt` as a false positive
  (the substring "temp" occurs inside "atTEMPts", not as a temp-file marker).
  Inspected and confirmed to be legitimate, protected Fifth-batch content
  (files 51-62, covered by the `MIGRATION_MANIFEST.md`/`6C-Core-Platform-APIs.md`
  range citation). No action taken.

No architectural contradictions were discovered during this pass.

## 7. Result

The repository is smaller (45 redundant execution-log/script files removed,
~11% of the `5K/execution_logs/` directory by file count), retains full
traceability for every canonical claim in Phase 1-6M, and has zero broken
local references. All frozen migration/Alembic content is verified
byte-identical to its pre-cleanup state. No product design, database design,
or API contract was changed. No file was executed.

**REPOSITORY CLEANUP = READY FOR INDEPENDENT REVIEW**
