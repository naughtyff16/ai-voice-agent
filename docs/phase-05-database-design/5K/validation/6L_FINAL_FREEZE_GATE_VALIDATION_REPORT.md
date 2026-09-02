# Phase 6L — Final Freeze-Gate Validation Report

**Scope:** migrations `103_5J2` and `104_5B3` (chain `102_5H2 → 103_5J2 → 104_5B3`), validated against the **exact final bytes** of both files after the freeze-gate remediation's stale-comment correction (BLOCKER 5 of the governing task).

**Method:** a disposable, locally self-hosted PostgreSQL 18.6 instance — an isolated data directory and port, never the operator's own shared/production server, initialized and used solely for this validation pass — plus a real, isolated `alembic`/`sqlalchemy`/`psycopg2` installation (not a hand-rolled substitute for the actual CLI).

**Raw evidence location:** `docs/phase-05-database-design/5K/execution_logs/`, files prefixed `20260903T000000Z_6L_01` through `20260903T000000Z_6L_13`. Every command below cites the exact raw file it came from — this report is a guide to that evidence, not a replacement for it.

---

## 1. Final Migration Bytes Under Test

| File | SHA-256 | Size | Evidence |
|---|---|---|---|
| `102_5H2.sql` | `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` | 127,971 bytes | `20260903T000000Z_6L_13_final_checksums_and_sizes.txt` — **unchanged**, reconfirmed |
| `103_5J2.sql` | `fba53d7ecc09b345335ea4aea600ca2ffbb288aed42775ff986dcabf8e8dfb87` | 13,907 bytes | Same file — **new checksum**, post stale-comment correction (BLOCKER 5) |
| `104_5B3.sql` | `4b8ab081e9064c96ecdbc59545fa9af3ffd878032a47baff45af6ee6a2ca8183` | 6,649 bytes | Same file — unchanged from the prior pass |

**Both validation runs below (fresh and incremental) were executed against these exact bytes** — the stale-comment correction to `103_5J2.sql` was applied *before* either run began, not after.

## 2. PostgreSQL / Client Version

**Evidence:** `20260903T000000Z_6L_01_server_client_version.txt`

```
psql (PostgreSQL) 18.6
PostgreSQL 18.6 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit
```

## 3. Fresh Chain Validation (Database A: `voice_agent_fresh2`, empty at start)

| Step | Evidence file | Result |
|---|---|---|
| `alembic upgrade head` (`001_5B → 104_5B3`) | `20260903T000000Z_6L_02_fresh_upgrade_001_to_104.txt` | **104/104 revisions applied, exit code 0** |
| `alembic heads` / `current` | `20260903T000000Z_6L_03_fresh_heads_current_history.txt` | `104_5B3 (head)` for both — exactly one head, current == head |
| `alembic history` (full, head-to-base) | `20260903T000000Z_6L_04_fresh_history_full.txt` | 104 lines, single linear chain, no branch, `103_5J2 -> 104_5B3 (head)` at top |
| Schema/constraint/RBAC/RLS/audit assertion battery (sections A–L, see §5 below) | `20260903T000000Z_6L_05_fresh_assertions_full.txt` | **All pass** |

## 4. Genuinely Separate Incremental Chain Validation (Database B: `voice_agent_incr`, empty at start — a wholly different database from A)

This is **not** a re-description of the fresh chain's tail — it is an independent database, pinned mid-chain, with representative pre-migration data inserted at the pin point, continued forward, and re-verified.

| Step | Evidence file | Result |
|---|---|---|
| 1. `alembic upgrade 102_5H2` (target the specific revision, not head) | `20260903T000000Z_6L_06_incremental_step1_upgrade_to_102.txt` | **102/102 revisions applied (001→102 only), exit code 0** |
| 2. `alembic current` while pinned, plus `alembic heads` for contrast | `20260903T000000Z_6L_07_incremental_step2_current_pinned_at_102.txt` | `current` → `102_5H2` (**no** `(head)` suffix — genuinely mid-chain); `heads` → `104_5B3 (head)` (the package's head, unaffected by this DB's own pin) — the two commands' differing output is itself proof the pin is real |
| 3. Insert representative pre-103 fixture data, using **only** the pre-103 column set (the `103_5J2` FX-normalization columns do not exist yet on this database at this point) | `20260903T000000Z_6L_08_incremental_step3_pre103_fixture_insert.txt` | Two legacy-shaped rows inserted: a `roi_by_campaign` row with `roi_pct = 300.0000` already populated (simulating a real pre-migration application that computed ROI without FX normalization) and a `billing_revenue_monthly` row — both confirmed present via `\d` showing the pre-103 schema shape |
| 4. `alembic upgrade 103_5J2` (with the fixture rows already present) | `20260903T000000Z_6L_09_incremental_step4_upgrade_102_to_103.txt` | **Exit code 0** — the migration succeeded *with* the non-normalized legacy row already in the table, proving the `NOT VALID` constraint strategy (§56.3 of the 6L document) actually works against real pre-existing non-conforming data, not merely against an empty table |
| 5. `alembic upgrade head` (`103_5J2 → 104_5B3`), then `heads`/`current` | `20260903T000000Z_6L_10_incremental_step5_upgrade_103_to_104_and_heads_current.txt` | Exit code 0; `heads` → `104_5B3 (head)`; `current` → `104_5B3 (head)` — now matching head, exactly one head |
| 6. Fixture-row survival + constraint-validation-state + new-write behavior | `20260903T000000Z_6L_11_incremental_step6_fixture_survival_check.txt` | Legacy `roi_by_campaign` row **still present**, `roi_pct` unchanged (`300.0000`), new FX columns correctly `NULL` (never silently backfilled/guessed); legacy `billing_revenue_monthly` row **still present**, new margin columns `NULL`; all 4 `NOT VALID` guard constraints show `convalidated = f`, matching the fresh database exactly; a **new** non-normalized insert is **rejected** (`chk_rbc_roi_requires_normalization` violation); a **new** fully-normalized insert **succeeds** |
| 7. Full sensitive-media / RLS / SECURITY DEFINER / audit assertion battery (sections A–L, identical script to the fresh run) | `20260903T000000Z_6L_12_incremental_step7_full_rbac_rls_audit_assertions.txt` | **All pass, byte-for-byte identical outcomes to the fresh database** (§5 below) |

**This is the complete, independent incremental-chain evidence the prior pass's §68 admitted was missing.** Two genuinely separate databases, two separate pin points, real pre-existing data exercised through the exact migration boundary, both converging on identical final state.

## 5. Assertion Battery — Identical Script, Run Against Both Databases

Both `..._6L_05_fresh_assertions_full.txt` and `..._6L_12_incremental_...assertions.txt` ran the **same** SQL script (`assertions.sql`, sections A–L) and produced **identical outcomes**:

| § | Assertion | Fresh DB result | Incremental DB result |
|---|---|---|---|
| A/B | New FX-normalization columns present on both tables | ✅ | ✅ |
| C | 4 guard constraints `NOT VALID`, 1 format-check `VALID` | ✅ | ✅ |
| D | Non-normalized `roi_pct` insert rejected | ✅ `ERROR: ...chk_rbc_roi_requires_normalization` | ✅ identical |
| E | Fully-normalized insert accepted | ✅ | ✅ |
| F | Sensitive-media permission grants: `recording:access_media`/`transcript:access_content` → OWNER, ADMIN only; `recording:read`/`transcript:read` → OWNER, ADMIN, MEMBER, VIEWER (unchanged); BILLING_ADMIN → neither | ✅ exact match to owner-approved policy | ✅ identical |
| F2 | Permission `display_name` clarification applied | ✅ | ✅ |
| G | Tenant custom role can be granted `recording:access_media` and assigned to a user — the "MEMBER via explicit custom role" path is mechanically live, no schema change needed | ✅ | ✅ |
| H | `SECURITY DEFINER` inventory: `app_api` holds EXECUTE on exactly `fn_insert_audit_event`, not `fn_compute_chain_hash` or any projection function | ✅ | ✅ identical |
| I | RLS cross-tenant isolation: Org A sees only its own row, Org B sees only its own row, unset tenant context sees zero rows (fail-closed) | ✅ | ✅ identical |
| J | `RECORDING_ACCESS_GRANTED` audit event written via `fn_insert_audit_event()` and read back — `resource_snapshot` contains only `call_id`/`expires_in_seconds`, no URL/token/credential | ✅ | ✅ identical |
| K | Direct `INSERT` into `audit.audit_events` as `app_api` denied | ✅ `permission denied for table audit_events` | ✅ identical |
| L | `fn_compute_chain_hash()` call as `app_api` denied | ✅ `permission denied for function fn_compute_chain_hash` | ✅ identical |

## 6. Checksums / Sizes (Final)

**Evidence:** `20260903T000000Z_6L_13_final_checksums_and_sizes.txt` — reproduced in §1 above.

## 7. Scope Limit (Restated Honestly)

This is real, live, database-layer verification — schema, constraints, RLS, permission seeds, `SECURITY DEFINER` grants, and the audit function's actual behavior, all exercised against a genuine PostgreSQL 18.6 server. It is **not** an HTTP-level test of a running FastAPI application, because no such application exists in this repository at this phase. Every claim in this report is either a direct quotation of raw command output in the cited evidence file, or a statement clearly marked as design-level (matching the discipline the 6L document itself already applies in its own §57.9).

## 8. Verdict for This Report's Scope

Both the fresh chain and a genuinely separate incremental chain — pinned at `102_5H2`, exercised with real pre-existing non-conforming data across the exact `103_5J2` migration boundary — independently confirm: exit code 0 at every step, exactly one Alembic head (`104_5B3`) in both databases, `current == head` in both, identical and correct RBAC/RLS/audit/SECURITY DEFINER behavior in both, and correct backward-compatible handling of pre-migration data. No discrepancy was found between the two runs.
