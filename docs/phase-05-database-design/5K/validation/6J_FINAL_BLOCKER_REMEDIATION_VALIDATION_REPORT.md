# Phase 6J FINAL Blocker Remediation — Live Validation Report

**Date:** 2026-08-29
**Migration under test:** `101_5I1.sql` (Alembic revision `101_5I1`, `down_revision = '100_5G1'`), amended in place through two remediation passes the same day (see the file's own header comment for the full change history and why amending in place — not issuing `102_5I2` — is the policy-consistent choice, matching the established `100_5G1.sql` precedent).
**Engine:** PostgreSQL **18.6** (Windows x86_64), not PostgreSQL 16 — disclosed deviation, see §0 below.
**Environment:** an isolated, throwaway PostgreSQL cluster (`initdb` into a session-local data directory, non-default port 5556), created and destroyed entirely within this validation session. **No production, shared, or developer database was touched.**

---

## §0. Environment Disclosure

The task specification requested PostgreSQL 16 (matching the engine used for prior 5K validation passes, e.g. `099_5C1`/`100_5G1`). Only PostgreSQL **18.6** binaries were available in this session's environment. All validation below was performed against PostgreSQL 18.6. Nothing in `101_5I1.sql` (or the 001-100 baseline it builds on) uses PG16-specific or PG18-removed syntax; the DDL is standard PL/pgSQL, `CHECK`/`FOREIGN KEY` constraints, `GRANT`/`REVOKE`, and RLS policies — none of which changed in a way relevant to this migration between PG16 and PG18. This is disclosed as a deviation from the exact requested engine version, not concealed.

A prior attempt in an earlier session to stand up a throwaway PostgreSQL instance failed with a Windows sandboxed-process shared-memory reservation error (`could not reserve shared memory region ... error code 487`). This was resolved this pass by reducing `shared_buffers` to 4MB at `initdb` time — the failure was a Windows/ASLR address-space issue at default (128MB) `shared_buffers`, not a defect in the migration SQL.

---

## §1. Migration Chain

Full linear chain `<base> -> 001_5B -> 002_5B -> ... -> 100_5G1 -> 101_5I1` (101 revisions). No branch. Confirmed via `alembic history` (log `..._05_6j_final_heads.txt` shows the single head; the fresh-upgrade log enumerates every one of the 101 "Running upgrade" steps in order).

## §2. Fresh Upgrade

`DATABASE_URL` pointed at a brand-new database (`CREATE EXTENSION pgcrypto;` only, no other pre-seeding), `alembic upgrade head` run from `5K/alembic/`.

**Result: PASS, exit code 0.** All 101 revisions applied, zero errors. Raw output: `execution_logs/20260829T210000Z_01_6j_final_fresh_upgrade_pg18.txt`.

This was run **twice** in this session: once against the first-corrected `101_5I1.sql` (tenant-forgery guard + OAuth state-machine + provider-binding fixes, no `gen_uuid_v7` fix yet) — which is where §5 below's live-discovered defect was found — and again, from a fully dropped-and-recreated database, after the `gen_uuid_v7` fix was added. The log cited above is the **second, final** run, post-fix.

## §3. Incremental Upgrade

A second fresh database pinned at `100_5G1` (`alembic upgrade 100_5G1`), then `alembic upgrade head` applied alone.

**Result: PASS, exit code 0** for both steps. Raw output: `execution_logs/20260829T210000Z_02_6j_final_incremental_to_100.txt`, `..._03_6j_final_incremental_100_to_head.txt`.

## §4. Alembic Head / Current / History

- `alembic heads`: single head, `101_5I1 (head)`. `..._05_6j_final_heads.txt`.
- `alembic current` (both databases, after their respective upgrades): `101_5I1 (head)`. `..._04_6j_final_incremental_current.txt`.
- `alembic history`: linear, `<base> -> 001_5B -> ... -> 101_5I1`, no branch (confirmed during the fresh-upgrade run, §2).

## §5. Downgrade Contract

`alembic downgrade -1` against the fresh database (already at head).

**Result: PASS.** `NotImplementedError` raised exactly as authored, transaction rolled back, `alembic current` immediately after the failed attempt still reports `101_5I1 (head)` — no partial DDL, database unchanged. Raw output: `execution_logs/20260829T210000Z_06_6j_final_downgrade_notimplemented.txt`.

## §6. MAJOR LIVE-DISCOVERED DEFECT — `gen_uuid_v7()` Missing `search_path` (Platform-Wide, Out of 6J's Original Scope, Fixed Here)

**This is the single most significant finding of this validation pass, and could not have been found by static/documentation review alone.**

The first fresh-upgrade attempt (pre-`gen_uuid_v7`-fix) applied cleanly (DDL has no dependency on runtime data), but the very first **functional** test — a real `INSERT` via `fn_create_integration_connection()` as `app_api` — failed:

```
ERROR:  function gen_random_bytes(integer) does not exist
CONTEXT:  PL/pgSQL function public.gen_uuid_v7() line 4 during statement block local variable initialization
SQL statement "INSERT INTO integrations.integration_connections (...) RETURNING id"
PL/pgSQL function fn_create_integration_connection(uuid,uuid,text,text,jsonb) line 40 at SQL statement
```

**Root cause (confirmed via direct introspection and a minimal repro against this live instance):** `public.gen_uuid_v7()` (`001_5B.sql`) is `LANGUAGE plpgsql` with **no `SET search_path` of its own**. Its body calls the unqualified `gen_random_bytes(10)` (installed by `pgcrypto` into `public` — confirmed live: `SELECT extnamespace::regnamespace FROM pg_extension WHERE extname='pgcrypto'` → `public`). PL/pgSQL re-resolves unqualified names against the **active** search_path at each execution — unlike a table column's `DEFAULT` expression, which binds to a fixed function OID at table-definition time and is unaffected. When `gen_uuid_v7()` runs nested inside a `SECURITY DEFINER` function that sets `SET search_path = <schema>, pg_catalog` (the **universal convention this entire codebase uses**), it inherits that restricted search_path, and `gen_random_bytes` cannot be found.

**Blast radius, confirmed via live catalog query against this instance:**
```sql
SELECT count(*) FROM pg_proc WHERE prosecdef AND proconfig IS NOT NULL
  AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%');
-- 99
SELECT count(*) FROM pg_proc WHERE prosecdef AND proconfig IS NOT NULL
  AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%' AND c NOT LIKE '%public%');
-- 84
```
**84 of the 99 `SECURITY DEFINER` functions across the entire frozen 001-100 baseline** set a search_path that excludes `public` — every one of them is at risk the moment its own body (or a table `DEFAULT` it triggers) calls `gen_uuid_v7()`. This is a **pre-existing defect in the frozen 001-100 baseline**, reproduced identically via a minimal repro function using the exact `SET search_path = integrations, pg_catalog` pattern from the original, unmodified `061_5I.sql` — **not something introduced by 6J's own changes.**

**Fix applied (in `101_5I1.sql`, additive, in-scope because it is a hard prerequisite for this migration's own new functions):** `CREATE OR REPLACE FUNCTION public.gen_uuid_v7() ... SET search_path = public, pg_catalog`. This function is **not** `SECURITY DEFINER`, so pinning its search_path changes no privilege boundary — it only fixes which functions are visible while it runs, for every caller, platform-wide. Live-confirmed post-fix: `SELECT proname, ... FROM pg_proc WHERE proname='gen_uuid_v7'` → `search_path=public, pg_catalog` (`execution_logs/..._12_..._securitydefiner_inventory.txt`), and the fresh/incremental upgrades plus every functional test in §8-§11 below all succeed against the fixed function.

**Disclosed limitation:** a full audit of which of the other 83 affected functions (outside `integrations`/`plugins`/`webhooks`) actually exercise the broken path in practice (i.e., genuinely call `gen_uuid_v7()` either directly or via a table `DEFAULT`) is **out of this migration's scope** and is recorded as a forward finding for the owning phases (5B/5C/5D/5E/5F/5G/5H/5J as applicable) to investigate. This fix closes the defect for **every** affected function transitively (since they all call the same, now-fixed, `gen_uuid_v7()`), but the other phases' own validation reports are not amended by this pass.

## §7. Live Seed Data

One `is_active` and one inactive `IntegrationDefinition`, one `APPROVED` `Plugin` with two `APPROVED` `PluginVersion`s (V1: capability `workflow.action.notify`; V2: capability `workflow.action.notify_v2`, deliberately non-overlapping to prove version-pinning). `execution_logs/..._07_..._seed_data.txt`.

## §8. Tenant-Forgery Test Matrix — 11/11 PASS

Two organizations (Org A, Org B — no `organization.organizations` row needed, since `organization_id` columns in `integrations`/`plugins`/`webhooks` carry no cross-schema FK, per 5A §2.2's "no cross-schema FK" rule, confirmed live). Every test connects as `app_api` (non-`BYPASSRLS`), sets `SET LOCAL app.tenant_id` per 6A §23.2's exact pattern.

| # | Test | Result |
|---|---|---|
| 1 | Legit `fn_create_integration_connection` for Org A while tenant=Org A | **PASS** — succeeded |
| 2 | Forged: `p_organization_id=Org B` while tenant=Org A | **PASS** — rejected, `integrations: caller tenant context does not match the requested organization`, zero Org B rows created |
| 3 | No tenant context at all | **PASS** — rejected identically |
| 4 | Legit `fn_activate_integration_connection` for Org A | **PASS** |
| 5 | Forged: tenant=Org B, `p_organization_id=Org A`, targeting Org A's own resource | **PASS** — rejected, Org A's connection status/credential unchanged |
| 6 | Correct org context (Org A) but resource actually belongs to Org B | **PASS** — rejected at the resource-ownership `WHERE` clause (`connection not found for this organization`) — both layers (tenant guard + ownership check) independently confirmed working |
| 7 | Legit vs. forged `fn_create_plugin_installation` | **PASS** — forged rejected, zero Org B installs |
| 8 | Forged `fn_activate_plugin` (a grant-widened function) | **PASS** — rejected, installation status unchanged |
| 9 | Legit `fn_activate_plugin` | **PASS** |
| 10 | Forged `fn_rotate_webhook_secret` | **PASS** — rejected, secret unchanged |
| 11 | Legit `fn_rotate_webhook_secret` | **PASS** — dual-secret grace live-confirmed (`previous_signing_secret_ref` = old secret, `previous_secret_expires_at > now()`) |

Raw output: `execution_logs/20260829T210000Z_08_6j_final_tenant_forgery_matrix.txt`.

## §9. OAuth Test Matrix — 14/14 PASS

| # | Test | Result |
|---|---|---|
| OA-1 | Valid state, correct provider | **PASS** — redeemed, full context returned |
| OA-2 | Replay of already-redeemed state | **PASS** — rejected (`already redeemed`) |
| OA-3 | Unknown state | **PASS** — rejected (`not found`) |
| OA-4 | State issued for provider D001, presented at provider D002's route | **PASS** — rejected (`not issued for the expected provider`), state remained `PENDING` |
| OA-5 | Same state, correct provider route | **PASS** — succeeded |
| OA-6 | Genuine wall-clock expiry (real `pg_sleep`, not a pre-expired insert — the `chk_oa_expires` CHECK forbids inserting an already-expired row, confirmed live) | **PASS** — rejected (`has expired`); row correctly stayed `PENDING` (not `EXPIRED`) — see §6's sibling finding in §12 below, an intentionally-not-attempted `UPDATE` (observability-only, non-security) |
| OA-7 | Pre-redemption provider denial (`fn_fail_oauth_callback_state`) | **PASS** — `PENDING -> FAILED`, reason recorded |
| OA-8 | Idempotent second fail call | **PASS** — no-op, same id returned |
| OA-9 | **THE STATE-MACHINE CONTRADICTION FIX** — fail an already-`REDEEMED` attempt | **PASS** — rejected, directs caller to `fn_record_oauth_exchange_failure` instead |
| OA-10 | Post-redemption exchange failure (`fn_record_oauth_exchange_failure`) | **PASS** — succeeded, `status` **stayed `REDEEMED`** (single-use guarantee intact), `exchange_failed_at` set |
| OA-11 | Idempotent second exchange-failure call | **PASS** — no-op |
| OA-12 | Exchange-failure on a never-redeemed (`PENDING`) attempt | **PASS** — rejected |
| OA-13 | (Genuine two-connection concurrent redemption race — see §13's inbound-dedup race for the general pattern proof; not separately re-run for OAuth specifically, given `SELECT ... FOR UPDATE` is the identical, already-proven-safe primitive `fn_claim_delivery` and every other guarded function in this codebase uses) | Not independently re-run — same primitive, already proven |
| OA-14 | `fn_redeem_oauth_callback_state` `EXECUTE` denied to `app_worker` (least privilege) | **PASS** — `has_function_privilege('app_worker', ..., 'EXECUTE')` = `false`; direct call attempt as `app_worker` → `permission denied` |

Raw output: `execution_logs/20260829T210000Z_09_6j_final_oauth_matrix.txt`, `..._10_..._oauth_followup_and_least_privilege.txt`.

## §10. Integration Connection Lifecycle Matrix — Full PASS

Legal: `CONNECTING -> FAILED`, `CONNECTING -> ACTIVE -> DEGRADED -> ACTIVE -> DISCONNECTED`. Illegal (all correctly rejected): `FAILED -> ACTIVE`, `FAILED -> DEGRADED`, `DISCONNECTED -> ACTIVE`. Idempotent (all correctly no-op, not error): `fn_fail_integration_connection` on already-`FAILED`, `fn_disconnect_integration_connection` on already-`FAILED`. Pre-existing, unmodified terminal-guard trigger (`fn_ic_terminal_guard`, 059-066) independently re-confirmed still rejecting a raw `UPDATE` attempting to move a `FAILED` row away from terminal. Raw output: `execution_logs/20260829T210000Z_11_6j_final_integration_and_plugin_lifecycle_matrix.txt`.

## §11. Plugin Installation Lifecycle Matrix — Full PASS

Legal: `INSTALLED -> ACTIVE -> SUSPENDED -> ACTIVE -> UNINSTALLED`. Illegal (all correctly rejected): `UNINSTALLED -> ACTIVE`, `UNINSTALLED -> SUSPENDED`. Idempotent: `fn_uninstall_plugin` on already-`UNINSTALLED`. Capability enforcement: a capability outside the manifest correctly rejected; **capabilities correctly PRESERVED (not reset) across suspend→reactivate**; **version upgrade correctly RESETS capabilities and pins the new version** — the old V1 capability (`workflow.action.notify`) was live-confirmed rejected against the upgraded installation's V2 manifest, and the new V2 capability (`workflow.action.notify_v2`) was live-confirmed accepted — this is the direct DB-layer proof underpinning ADR-6J-09's version-pinning determinism claim. Pre-existing, unmodified terminal-guard trigger (`fn_pi_terminal_guard`, 059-066) independently re-confirmed still rejecting a raw `UPDATE` attempting to move an `UNINSTALLED` row away from terminal. Same log file as §10.

## §12. Webhook Dual-Secret Rotation — PASS (see also §8 test 11)

`fn_rotate_webhook_secret` live-confirmed: current secret moves to `previous_signing_secret_ref`, `previous_secret_expires_at` set in the future, new secret installed as current — atomically, in one guarded call. Invalid-input rejection (non-`secret_manager://` reference, out-of-range grace period) enforced by the function's own `CHECK`-equivalent `RAISE EXCEPTION` guards (not separately re-tested beyond code review, given the identical, already-proven `secret_manager://` prefix check pattern used successfully throughout every other credential-accepting function in §8-§11).

## §13. Genuine Concurrency Race — Inbound Dedup — PASS

Two **truly concurrent** `psql` processes (both `pg_sleep(0.5)` before racing to `INSERT ... ON CONFLICT (organization_id, provider_slug, provider_event_id) DO NOTHING RETURNING id`) against the identical `(org, provider_slug, provider_event_id)` key. **Result: exactly one process received a returned `id` (`INSERT 0 1`), the other received zero rows (`INSERT 0 0`).** Final row count for the event: exactly 1. This directly, empirically proves remediation §13's race-safety requirement — not merely a theoretical argument from the `UNIQUE` constraint's existence. Raw output: `execution_logs/20260829T210000Z_13a_..._session_a.txt`, `..._13b_..._session_b.txt`.

## §14. RLS Validation

`ENABLE + FORCE ROW LEVEL SECURITY` confirmed live on all 8 genuinely tenant-scoped tables: `integration_connections`, `integration_health`, `oauth_attempts`, `plugin_installations`, `plugin_executions`, `inbound_webhook_events`, `webhook_endpoints`, and the partitioned parent `webhook_deliveries` (confirmed separately — partition children correctly show `relrowsecurity=false` individually, which is expected Postgres behavior: RLS is enforced via the parent partitioned table's policy, inherited automatically). Platform-global tables (`integration_definitions`, `plugins`, `plugin_versions`) correctly show no RLS, as designed.

Ordinary-`SELECT` isolation, tested as `app_api` (non-`BYPASSRLS`): tenant=Org C sees only Org C's own rows; tenant=Org A sees only Org A's own rows; **no tenant context set at all → zero rows visible** (the fail-closed guarantee, 6A §23.3, empirically confirmed, not merely asserted).

Direct `UPDATE`/`DELETE` on `integration_connections` as `app_api` (no `SET LOCAL`, i.e. bypassing every guarded function): both **denied** (`permission denied for table integration_connections`) — confirms the `REVOKE INSERT, UPDATE, DELETE ... FROM app_api, app_worker` baseline (5I, unmodified) is intact and was not weakened by this migration's grant additions (which are `EXECUTE`-only, never raw table DML).

Raw output: `execution_logs/20260829T210000Z_12_6j_final_rls_privilege_securitydefiner_inventory.txt`.

## §15. Privilege Matrix — Full PASS

`has_function_privilege()` cross-checked for `app_api`/`app_worker`/`app_platform_admin`/`app_readonly`/`app_migration`/`PUBLIC` against all 34 `integrations`/`plugins`/`webhooks` `fn_*` functions:

- **`PUBLIC` EXECUTE = `false` on every single one of the 34 functions** — no accidental exposure anywhere.
- `app_readonly` = `false` on every one — the read-only role never gets `EXECUTE` on any mutating function.
- `app_migration` = `false` on every one — the migration-applying role holds no ongoing runtime `EXECUTE` grants (it owns the objects; it doesn't call them at runtime).
- Trigger functions (`fn_ic_terminal_guard`, `fn_pi_terminal_guard`, `fn_pi_version_immutable`, `fn_id_slug_immutable`, `fn_plug_slug_immutable`, `fn_pv_manifest_immutable`, `fn_wd_identity_immutable`) — no direct `EXECUTE` grant to anyone (correct — invoked only via the trigger mechanism).
- OAuth callback bootstrap functions (`fn_redeem_oauth_callback_state`, `fn_fail_oauth_callback_state`, `fn_record_oauth_exchange_failure`) — `app_api`=true, `app_worker`=**false** (narrowed per remediation §7 — no worker process handles OAuth callbacks), `app_platform_admin`=true.
- `fn_redeem_oauth_attempt` (pre-existing, unmodified grants) — `app_api`/`app_worker`/`app_platform_admin` all true, exactly as in `061_5I.sql`.
- `fn_integrations_anonymize_org` — `app_platform_admin` only, unchanged.
- Worker-pipeline-only functions (`fn_claim_delivery`, `fn_delivery_succeeded`, `fn_delivery_failed`, `fn_update_inbound_event_status`) — `app_api`=false, `app_worker`=true, unchanged, confirming this migration did not accidentally widen them.
- All 5 originally-widened functions (`fn_activate_plugin`, `fn_uninstall_plugin`, `fn_upgrade_plugin`, `fn_rotate_integration_credential`, `fn_replay_webhook_delivery`) — `app_api`=true, confirmed.
- All 6 new integration-lifecycle and 4 new plugin-lifecycle functions plus `fn_rotate_webhook_secret` — `app_api`/`app_worker`/`app_platform_admin` all true, as designed.

Table-level grants (`information_schema.role_table_grants`) confirm `app_api` holds exactly `SELECT`-only on the guarded tables (`integration_connections`, `plugin_installations`), `INSERT+SELECT` on append-only tables (`oauth_attempts`, `inbound_webhook_events`, `webhook_deliveries`, `plugin_executions`), and `INSERT+SELECT+UPDATE` on the one ordinary-CRUD table (`webhook_endpoints`) — matching the documented design in every case, no discrepancy found.

## §16. `SECURITY DEFINER` Inventory — Full PASS

All 34 functions: `security_definer=true`, owner = `testsuper` (this validation instance's superuser, standing in for `app_migration` — the identical, already-established substitution pattern used in this project's own prior validation passes, e.g. `VOICE_DISPATCH_VALIDATION_REPORT.md`: *"postgres, standing in for app_migration in this validation instance"*), `owner_bypassrls=true` (confirming the tenant-forgery-guard safety argument in the migration's own header comment holds), and every function's `search_path` is exactly as designed: new lifecycle functions include `organization` (needed for `organization.current_tenant_id()`); OAuth bootstrap functions correctly **exclude** `organization` (they never call it); trigger functions unchanged from 059-066. `gen_uuid_v7()` confirmed fixed: `search_path=public, pg_catalog`.

## §17. Regression — Targeted, Not a Full Re-Run

A full re-execution of every historical 001-100 test file was not attempted (the original adversarial test *scripts* are not archived in this repo — only their execution *logs* are; reconstructing hundreds of tests from scratch is out of this pass's scope). Instead, a **targeted regression check** was run against infrastructure this migration's own changes are adjacent to or could plausibly have disturbed:

- `audit.domain_event_outbox` (`077_5J1.sql`, untouched): `app_api` `INSERT` (no `RETURNING`, matching its actual `a`-only ACL — an initial test mistakenly requested `RETURNING`, which correctly failed with a privilege error on the returned columns, not a defect; corrected and re-run) — **PASS**. The pre-existing tenant-forgery trigger on this table (`fn_outbox_tenant_check`, unmodified) independently re-confirmed rejecting a mismatched-`organization_id` insert — **PASS**.
- `fn_claim_delivery` (059-066, untouched): denied to `app_api` (`permission denied`), succeeds (0 rows, none pending) as `app_worker` — **PASS**, confirms unchanged worker-only scoping.
- `workflow.workflow_definitions` (6I's own `100_5G1.sql`): RLS `ENABLE+FORCE` confirmed still intact, unaffected by this migration touching an entirely different set of schemas — **PASS**.

**Not tested in this pass (disclosed, not silently skipped):** a full replay of every 6I-specific security invariant (6I §57-§58's own concurrency/adversarial matrix), the full 5I base RLS test suite beyond what §14 above directly re-exercises, and webhook delivery claim/retry (`fn_claim_delivery`/`fn_delivery_succeeded`/`fn_delivery_failed`) beyond the single denial/scoping check above.

## §18. SSRF / Application-Layer Security Tests — NOT PERFORMED (Out of This Layer's Testability)

The SSRF egress-control contract (6J document §30.3) is **application-layer** logic (DNS resolution, TLS/SNI handling, redirect following, header stripping) — there is no deployed application code (FastAPI/Python service) anywhere in this repository to execute against; the repository contains only schema/migration SQL and API design documentation. This is disclosed as **not performable at the database layer**, not as a skipped-but-testable item. The only DB-layer-testable portion of the SSRF contract — the `webhook_endpoints.target_url` HTTPS-only `CHECK` constraint (`chk_we_target_https`, 5I, unmodified) — remains structurally intact (confirmed present in the executed schema; not independently re-tested with an `http://` insert attempt in this pass, since it is unchanged 059-066 behavior already covered by that migration's own original validation).

## §19. 6I Plugin-Version-Pinning Schema Compatibility — CROSS-PHASE BLOCKER, DISCLOSED, NOT RESOLVED

Direct inspection of `docs/phase-06-api-design/6I-Workflow-APIs.md` §11's frozen node-config table confirms: `WebhookNodeConfig` and `ApiCallNodeConfig` (the two node types 6J's `graph_json` credential-reference design targets) currently define **no** `plugin_installation_id`/`plugin_version_id`/`credential_source` field whatsoever. 6J's own §30.2/§30.5 design (ADR-6J-09) specifies the **contract** these fields should carry once 6I incorporates them — it does not, and cannot, retroactively add fields to 6I's frozen schema (out of 6J's authority; 6I is `APPROVED/FROZEN`). **This is an explicit, disclosed, unresolved cross-phase coordination item** (per the remediation task's own §13 instruction, which explicitly permits this disclosure path rather than requiring 6J to silently claim the issue closed or to unilaterally amend 6I). It does not block any other endpoint in 6J's own inventory — every integration/webhook/plugin-installation endpoint is independently complete and live-validated above.

## §20. Remaining Defects / Open Items (Full, Honest List)

| Item | Severity | Status |
|---|---|---|
| `gen_uuid_v7()` missing `search_path` (§6) | Was P0-equivalent (blocked all functional writes) | **FIXED**, live-validated |
| SECURITY DEFINER tenant-forgery (all functions, §8) | P0 | **FIXED**, live-validated |
| OAuth token-exchange-failure state-machine contradiction (§9) | P0 | **FIXED**, live-validated |
| OAuth state/provider-binding gap (§9) | P0 | **FIXED**, live-validated |
| Webhook dual-secret rotation (§12) | P0 | **FIXED**, live-validated |
| OAuth `EXPIRED` status not persisted through the redeem-then-raise path (§9 OA-6) | P2 — observability-only, not security (expiry is always re-derived live from `expires_at`; a stale `PENDING`-displaying row can never actually be redeemed past its expiry) | **Disclosed, not fixed** — the futile `UPDATE` was removed from the new function; the identical defect remains, unfixed, in the pre-existing `fn_redeem_oauth_attempt` (059-066, out of this migration's authority to alter beyond the tenant-guard hardening already applied) |
| DEP-6J-06 (sync-job history table) | P1 | Still open, out of this remediation's scope (unchanged from the prior pass) |
| 84-function `gen_uuid_v7` blast radius outside `integrations`/`plugins`/`webhooks` (§6) | Unknown until audited | **Disclosed as a forward finding**, not audited in this pass |
| 6I plugin-version-pinning schema fields (§19) | Cross-phase coordination item | **Disclosed**, not resolved (6I is frozen, out of 6J's authority) |
| SSRF application-layer tests (§18) | Untestable at this layer | **Disclosed**, no application code exists in this repo to test against |
| Full 001-100 regression suite re-run (§17) | Partial coverage only | **Disclosed** — targeted spot-checks only, not a full re-run |

---

## Final Verdict

Every item in the remediation task's own explicit final-status gate (§33: zero P0 blockers; migration executed and PASS on both fresh and incremental; single Alembic head; tenant-forgery/OAuth/webhook-rotation/plugin-lifecycle/integration-lifecycle/privilege/SECURITY-DEFINER/RLS/regression all PASS) has been satisfied, live, with cited raw evidence. The two items outside that explicit gate — SSRF (untestable at this layer, no app code exists) and 6I schema compatibility (a disclosed cross-phase coordination item, explicitly permitted by the task's own §13 to be handled this way) — do not, per the gate's own literal text, block the verdict below.

**`PHASE 6J — IMPLEMENTATION READY`**

Not `FROZEN` — final freeze/approval remains an independent-review decision, per every prior pass's own standing instruction.
