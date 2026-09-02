# Phase 6L — Final Freeze-Gate Validation Report

**Scope:** migrations `103_5J2` and `104_5B3` (chain `102_5H2 → 103_5J2 → 104_5B3`), validated against the **exact final bytes** of both files after the freeze-gate remediation's stale-comment correction (BLOCKER 5 of the governing task).

**Method:** a disposable, locally self-hosted PostgreSQL 18.6 instance — an isolated data directory and port, never the operator's own shared/production server, initialized and used solely for this validation pass — plus a real, isolated `alembic`/`sqlalchemy`/`psycopg2` installation (not a hand-rolled substitute for the actual CLI).

**Raw evidence location:** `docs/phase-05-database-design/5K/execution_logs/`, files prefixed `20260903T000000Z_6L_01` through `_6L_13` (initial validation) and `20260904T000000Z_6L_14` through `_6L_17` (final narrow remediation — complete security test matrix + constraint-count correction, §9). Every command below cites the exact raw file it came from — this report is a guide to that evidence, not a replacement for it.

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
| 6. Fixture-row survival + constraint-validation-state + new-write behavior | `20260903T000000Z_6L_11_incremental_step6_fixture_survival_check.txt` | Legacy `roi_by_campaign` row **still present**, `roi_pct` unchanged (`300.0000`), new FX columns correctly `NULL` (never silently backfilled/guessed); legacy `billing_revenue_monthly` row **still present**, new margin columns `NULL`; all five `NOT VALID` guard constraints show `convalidated = f` (corrected count — see §9; this row's original query only selected the guard constraints, not the sixth, immediately-`VALID` currency-format constraint), matching the fresh database exactly; a **new** non-normalized insert is **rejected** (`chk_rbc_roi_requires_normalization` violation); a **new** fully-normalized insert **succeeds** |
| 7. Full sensitive-media / RLS / SECURITY DEFINER / audit assertion battery (sections A–L, identical script to the fresh run) | `20260903T000000Z_6L_12_incremental_step7_full_rbac_rls_audit_assertions.txt` | **All pass, byte-for-byte identical outcomes to the fresh database** (§5 below) |

**This is the complete, independent incremental-chain evidence the prior pass's §68 admitted was missing.** Two genuinely separate databases, two separate pin points, real pre-existing data exercised through the exact migration boundary, both converging on identical final state.

## 5. Assertion Battery — Identical Script, Run Against Both Databases

Both `..._6L_05_fresh_assertions_full.txt` and `..._6L_12_incremental_...assertions.txt` ran the **same** SQL script (`assertions.sql`, sections A–L) and produced **identical outcomes**:

| § | Assertion | Fresh DB result | Incremental DB result |
|---|---|---|---|
| A/B | New FX-normalization columns present on both tables | ✅ | ✅ |
| C | **Six** constraints total: **five** guard constraints `NOT VALID`, **one** format-check `VALID` (corrected count, §9 — an earlier draft of this report undercounted the guard set as four) | ✅ | ✅ |
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

This is real, live, database-layer verification — schema, constraints, RLS, permission seeds, `SECURITY DEFINER` grants, and the audit function's actual behavior, all exercised against a genuine PostgreSQL 18.6 server. It is **not** an HTTP-level test of a running FastAPI application, because no such application exists in this repository at this phase. Every claim in this report is either a direct quotation of raw command output in the cited evidence file, or a statement clearly marked as design-level (matching the discipline the 6L document itself already applies in its own §57.12).

## 8. Verdict for This Report's Original Scope (superseded in numeric precision by §9, not in substance)

Both the fresh chain and a genuinely separate incremental chain — pinned at `102_5H2`, exercised with real pre-existing non-conforming data across the exact `103_5J2` migration boundary — independently confirm: exit code 0 at every step, exactly one Alembic head (`104_5B3`) in both databases, `current == head` in both, identical and correct RBAC/RLS/audit/SECURITY DEFINER behavior in both, and correct backward-compatible handling of pre-migration data. No discrepancy was found between the two runs.

---

## 9. Final Narrow Remediation (this pass) — Complete Security Test Matrix + Constraint-Count Correction

A second, independent review found two remaining gaps in the report above: (1) several security assertions the *original* Phase 6L task required (audit cross-tenant RLS, platform-audit-event hiding, provider-health denial for both `app_api` and `app_readonly`, and audit immutability across UPDATE/DELETE in addition to INSERT) had not yet been executed with raw evidence; (2) this report's own §5/§4 undercounted migration `103_5J2`'s `NOT VALID` constraint set as four when it is actually five (six constraints total, one immediately `VALID`). Both are closed in this pass, against the same two databases (A = `voice_agent_fresh2`, B = `voice_agent_incr`), with **no change to any migration's DDL** — both gaps were test-coverage and documentation-counting defects, not schema defects.

### 9.1 Corrected Constraint Count (Live-Reconfirmed)

```
analytics.roi_by_campaign        — 4 new CHECK constraints — 1 VALID (chk_rbc_org_currency_code) + 3 NOT VALID
analytics.billing_revenue_monthly — 2 new CHECK constraints — 2 NOT VALID
TOTAL                             — 6 new CHECK constraints — 1 VALID + 5 NOT VALID
```

Live-reconfirmed via `pg_constraint.convalidated` against both databases — evidence: `20260904T000000Z_6L_14_fresh_final_full_security_and_constraint_battery.txt` (Section 1) and `20260904T000000Z_6L_15_incremental_final_full_security_and_constraint_battery.txt` (Section 1) — both show the identical 6-row (12-row including partition propagation onto `billing_revenue_monthly`'s child partitions, which is normal PostgreSQL CHECK-constraint-on-partitioned-table behavior, not a distinct constraint) result.

### 9.2 Complete Constraint Functional Test — All Six Constraints, Individually Isolated

Each constraint was tested in isolation (satisfying every *other* constraint's own OR-branch) so the specific constraint under test — and only that one — is what actually fires. An earlier draft of Test A (currency-format check) did not do this correctly and was corrected before being reported (§9.4).

| Test | Constraint | Result (both databases, identical) |
|---|---|---|
| A | `chk_rbc_org_currency_code` — invalid code | **Rejected**, specifically by `chk_rbc_org_currency_code` |
| A2 | `chk_rbc_org_currency_code` — valid code | **Accepted** |
| B | `chk_rbc_cost_normalization_present` — mismatch, no normalization | **Rejected**, specifically by `chk_rbc_cost_normalization_present` |
| B2 | `chk_rbc_cost_normalization_present` — mismatch, normalized | **Accepted** |
| C | `chk_rbc_revenue_normalization_present` — mismatch, no normalization | **Rejected**, specifically by `chk_rbc_revenue_normalization_present` |
| C2 | `chk_rbc_revenue_normalization_present` — mismatch, normalized | **Accepted** |
| D | `chk_rbc_roi_requires_normalization` — `roi_pct` set, no normalization | **Rejected**, specifically by `chk_rbc_roi_requires_normalization` |
| E | (positive control) fully normalized ROI | **Accepted** |
| F | `chk_brm_margin_requires_normalization` | **Rejected**, specifically by `chk_brm_margin_requires_normalization` |
| G | `chk_brm_margin_pct_requires_amount` | **Rejected**, specifically by `chk_brm_margin_pct_requires_amount` |
| H | (positive control) fully normalized billing revenue row | **Accepted** |

Evidence: `20260904T000000Z_6L_14`/`_15`, Sections "TEST A" through "TEST H".

### 9.3 Complete Original Security Test Matrix

| Requirement | Result | Evidence |
|---|---|---|
| Tenant A cannot read Tenant B analytics | PASS (§4/§5 above) | `6L_05`/`6L_12` |
| Tenant A cannot read Tenant B audit | **PASS — newly tested.** Two real audit rows via `fn_insert_audit_event()` for two orgs; `app_api` under each context sees only its own; unset context sees zero | `6L_14`/`6L_15`, Section 2A |
| Tenant cannot read platform audit events | **PASS — newly tested,** including a negative control proving `SET ROLE app_worker` alone (which does not change `session_user`) is correctly denied, and a genuine `app_worker` connection (`session_user` confirmed via query) is what the approved path actually requires | `6L_14`/`6L_15`, Section 2B |
| Ordinary tenant cannot read provider health | **PASS — newly tested for both `app_api` and `app_readonly`** (a prior pass tested neither live); `app_worker` confirmed to retain its approved access | `6L_14`/`6L_15`, Section 2C |
| `analytics:read` cannot bypass `analytics_cost:read` | PASS by design — moot after DEC-6L-02 = Option A (no tenant cost endpoint exists to bypass into) | 6L document §26/§27 |
| Audit events remain immutable | **PASS — INSERT (prior pass) + UPDATE + DELETE (newly tested) all denied** to `app_api` | `6L_14`/`6L_15`, Section 2D |
| No new raw audit mutation privilege | PASS — `104_5B3` touches no `audit.*` object; `fn_compute_chain_hash` re-confirmed denied to `app_api` | `6L_14`/`6L_15`, Section 2D |
| Financial analytics values remain tenant-safe and currency-correct | PASS — §9.2's full constraint battery + DEC-6L-02 = Option A's confidentiality reclassification | `6L_14`/`6L_15` |

### 9.4 Custom-Role Extension — Both Sensitive Permissions Together

A tenant-owned custom role was granted **both** `recording:access_media` and `transcript:access_content` (a prior pass proved only the recording permission alone) — confirmed by direct read-back showing exactly those two rows attached to the role, with no touch to any system role's own grant set. Evidence: `6L_14`/`6L_15`, Section 2E.

### 9.5 Test-Design Corrections (Transparency)

Two test-*design* defects were found and corrected while building this final battery — reported here, not hidden, per the same evidence discipline as the rest of this document:

1. Test A's first draft inadvertently also violated `chk_rbc_cost_normalization_present`, which fired first — the test did not actually exercise `chk_rbc_org_currency_code`. Corrected by isolating the row.
2. The platform-audit-event test's first draft used `SET ROLE app_worker`, which does not change `session_user` — the value the function's platform-event check actually inspects. Corrected using a genuine new connection authenticated as `app_worker`, with the `SET ROLE` attempt retained as a documented negative control.

Neither correction required any change to migration DDL, a grant, or an RLS policy — both were fixes to the *test script*, confirmed by rerunning against both databases with clean results.

### 9.6 Final Heads / Current / Checksums (This Pass)

**Evidence:** `20260904T000000Z_6L_16_final_heads_current_both_databases.txt`, `20260904T000000Z_6L_17_final_checksums_confirm_unchanged.txt`.

```
Database A (voice_agent_fresh2): heads = 104_5B3 (head); current = 104_5B3 (head)
Database B (voice_agent_incr):   heads = 104_5B3 (head); current = 104_5B3 (head)

102_5H2.sql  73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d  127,971 bytes  UNCHANGED
103_5J2.sql  fba53d7ecc09b345335ea4aea600ca2ffbb288aed42775ff986dcabf8e8dfb87   13,907 bytes  UNCHANGED (matches the checksum this report already recorded in §1 — no edit made this pass)
104_5B3.sql  4b8ab081e9064c96ecdbc59545fa9af3ffd878032a47baff45af6ee6a2ca8183    6,649 bytes  UNCHANGED
```

**No migration DDL, Alembic wrapper, or grant was changed in this final narrow remediation pass.** Every gap closed in §9 was a test-coverage or documentation-counting defect, confirmed by live re-execution, not a schema defect.
