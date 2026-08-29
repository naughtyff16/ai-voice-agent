# PostgreSQL 18 Baseline Reconciliation & Phase 6J Final Validation Report

**Date:** 2026-08-29
**Purpose:** (1) reconcile the platform's authoritative database baseline from PostgreSQL 16 to PostgreSQL 18, verifying every required extension directly on PostgreSQL 18 rather than assuming compatibility from prior PostgreSQL 16 evidence; (2) re-confirm, on a brand-new disposable PostgreSQL 18.6 cluster never previously touched by this document series' own work, that the Phase 6J closure delivered by `6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` still holds; (3) record the closure of `DEP-6J-06` (V1 scope decision) and `DEP-6J-12` (6I compatibility amendment).

This report supplements, and does not replace, `6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` — that report's own PostgreSQL 18.6 execution (a different disposable cluster, same day) remains valid, unmodified evidence; the SQL under test is byte-for-byte identical between the two passes (`101_5I1.sql` was not touched in this pass).

---

## 1. PostgreSQL 18 Environment

Fresh, isolated, throwaway cluster, never used for anything but this pass's own tests:

```
initdb -D .tmp_pgdata_pg18v2 -U testsuper -A trust -E UTF8 --locale=C
port = 5557 | listen_addresses = 127.0.0.1 | shared_buffers = 4MB
max_connections = 20 | shared_preload_libraries = 'pg_stat_statements'
```

`shared_buffers` reduced from the PostgreSQL default (128MB) to 4MB — a disclosed Windows-sandboxed-process shared-memory-reservation constraint (the same one recorded in the prior pass's own evidence), not a PostgreSQL 18-specific issue; the cluster otherwise runs with stock defaults.

```
postgres --version   -> postgres (PostgreSQL) 18.6
psql --version       -> psql (PostgreSQL) 18.6
pg_config --version  -> PostgreSQL 18.6
SELECT version();    -> PostgreSQL 18.6 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit
```

Raw log: `execution_logs/20260829T220000Z_01_pg18_extension_compat_and_vector_sanity.txt` (version/extension section).

## 2. Previous PostgreSQL 16 Baseline

`5K-Database-Migration-and-Implementation.md` (pre-2026-08-29) declared PostgreSQL 16 as "the deployment target," and the original 75 migrations were first generated, executed, and certified against a genuinely fresh PostgreSQL 16 instance (`EXECUTION_REPORT.md`, `PG16_MIGRATION_VALIDATION_REPORT.md`, 75/75 PASS). That evidence is **not superseded, not rewritten, and not invalidated** by this report — it remains an accurate historical record of a real event. It is retained going forward as **legacy compatibility evidence**: proof that the schema and migrations are also compatible with PostgreSQL 16, not merely with 18.

## 3. Baseline Reconciliation

| Field | Value |
|---|---|
| Previous baseline | PostgreSQL 16 |
| New baseline | PostgreSQL 18.x |
| Reason | Pre-production platform; PostgreSQL 18 was already the active development-environment engine in practice — every recent live-validation pass (including Phase 6J's own pass-2 closure) already ran on PostgreSQL 18.6; eliminating the resulting version-drift-vs-stated-target before the Phase 6 freeze is a deliberate, one-time decision rather than a per-document disclosed deviation repeated indefinitely. |
| Scope | Runtime engine version only. Does **not** change: data model, bounded contexts, RLS design, authorization model, API contracts, modular-monolith architecture, Redis Streams/outbox pattern, or the Alembic migration strategy. No table, column, function signature, RLS policy, grant, or API endpoint is altered by this decision. |
| Documents updated to reflect current baseline | `5K-Database-Migration-and-Implementation.md` §5 (and intro), `alembic/env.py` docstring, `alembic/README.md` (addendum, historical section untouched), `6J-Integrations-Webhooks-Plugins-APIs.md` (§1, §56, §60, §62, new §63) |
| Documents deliberately left as accurate history | `5C-Voice-Schema.md`, `5E-Campaign-Schema.md`, `5G-Workflow-Prompt-Memory-Schema.md` (own historical narrative passages), `EXECUTION_REPORT.md`, `PG16_MIGRATION_VALIDATION_REPORT.md`, every pre-2026-08-29 `execution_logs/`/`validation/*.md` file, `6I-Workflow-APIs.md` §63's "PostgreSQL 16.10" statement, `6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`'s own original engine-disclosure section (its raw results are unmodified; only 6J's own *current-state* framing elsewhere in the same document — not this report file — was updated) |

## 4. Extension Compatibility (Verified Directly on PostgreSQL 18, Not Assumed)

```sql
SELECT name, default_version, installed_version FROM pg_available_extensions
WHERE name IN ('vector','pgcrypto','pg_stat_statements') ORDER BY name;
```

| Extension | Version available | `CREATE EXTENSION` result |
|---|---|---|
| `vector` (pgvector) | 0.8.6 | `CREATE EXTENSION` — success |
| `pgcrypto` | 1.4 | `CREATE EXTENSION` — success |
| `pg_stat_statements` | 1.12 | `CREATE EXTENSION` — success |

**Functional sanity, not merely "extension loads":**

```sql
CREATE TABLE vec_test (id serial primary key, embedding vector(3));
INSERT INTO vec_test (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT id, embedding <-> '[1,2,3]' AS distance FROM vec_test ORDER BY distance;
-- id=1 distance=0, id=2 distance=5.196152422706632  (correct Euclidean distance)
DROP TABLE vec_test;
```

**Result: PASS, no P0.** All three required extensions install cleanly and, for `vector`, function correctly on PostgreSQL 18.6. Raw log: `execution_logs/20260829T220000Z_01_pg18_extension_compat_and_vector_sanity.txt`.

## 5. Fresh Migration Result

Database `voice_agent_pg18_fresh` created, `pgcrypto`/`vector`/`pg_stat_statements` extensions installed, then:

```
DATABASE_URL=postgresql+psycopg2://testsuper@127.0.0.1:5557/voice_agent_pg18_fresh
alembic upgrade head
```

**Result: PASS.** All 101 revisions (`001_5B` → `101_5I1`) applied in linear order from a genuinely empty database, exit code 0, no errors. Raw log: `execution_logs/20260829T220000Z_02_fresh_migration_upgrade_head.txt`.

## 6. Incremental Migration Result

Second, independent database `voice_agent_pg18_incr`, same extension setup:

```
alembic upgrade 100_5G1   -- pre-6J baseline
alembic current            -- confirms 100_5G1
alembic upgrade head       -- incremental step onto 101_5I1
alembic current            -- confirms 101_5I1 (head)
```

**Result: PASS.** The single 6J-closure migration applies cleanly as an incremental step onto an already-migrated (pre-6J) database, exactly as it would in a real deployment. Raw log: `execution_logs/20260829T220000Z_04_incremental_migration_100_to_101.txt`.

## 7. Alembic Integrity

```
alembic heads     -> 101_5I1 (head)
alembic current   -> 101_5I1 (head)
alembic history   -> single linear chain, <base> -> 001_5B -> ... -> 101_5I1, no branches
```

**Result: PASS.** Single head, `current == head`, fully linear history — no branch point, no divergent revision. Raw log: `execution_logs/20260829T220000Z_03_alembic_integrity_heads_current_history.txt`.

## 8. Security-Definer Inventory

```sql
SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosecdef = true AND n.nspname NOT IN ('pg_catalog','information_schema');
-- 99 SECURITY DEFINER functions total, platform-wide
```

`gen_uuid_v7()` `search_path` fix re-confirmed present: `proconfig = {"search_path=public, pg_catalog"}`.

Tenant-forgery guard classification, queried directly against every `SECURITY DEFINER` function in `integrations`/`plugins`/`webhooks` (34 functions):

| Class | Guard present | Count | Examples |
|---|---|---:|---|
| Tenant-bound, `p_organization_id`-taking | `true` | 19 | `fn_create_integration_connection`, `fn_activate_plugin`, `fn_rotate_webhook_secret`, all six new integration-lifecycle functions, all four new plugin-lifecycle functions |
| OAuth callback bootstrap | `false` (by design — no tenant context exists yet) | 3 | `fn_redeem_oauth_callback_state`, `fn_fail_oauth_callback_state`, `fn_record_oauth_exchange_failure` |
| Trigger / immutability-guard functions (no `p_organization_id` parameter at all) | `false` (not applicable) | 8 | `fn_ic_terminal_guard`, `fn_id_slug_immutable`, `fn_pi_terminal_guard`, `fn_pv_manifest_immutable`, `fn_wd_identity_immutable`, etc. |
| Worker/system functions (cross-tenant by design) | `false` (by design) | 4 | `fn_claim_delivery`, `fn_delivery_failed`, `fn_delivery_succeeded`, `fn_update_inbound_event_status` |

**Result: PASS.** The three-class guard-presence pattern documented in 6J §31.1 matches exactly what is live on PostgreSQL 18.6 — every tenant-bound function has the guard, and every function correctly lacking it belongs to one of the two documented exempt classes. Raw log: `execution_logs/20260829T220000Z_05_security_definer_inventory_and_guard_classification.txt`.

## 9. Tenant-Forgery Result

Representative adversarial re-confirmation (full 11-test matrix already live-proven in the prior pass against unchanged SQL; this pass re-proves the core cases fresh):

| Test | Result |
|---|---|
| `fn_create_integration_connection`, caller tenant = A, `p_organization_id` = B (forged) | **Rejected** — `integrations: caller tenant context does not match the requested organization` |
| `fn_create_integration_connection`, caller tenant = A, `p_organization_id` = A (legit) | **Succeeds** — row created |
| `fn_fail_integration_connection` → `fn_activate_integration_connection` from `FAILED` (legit tenant) | **Rejected on business-rule grounds** (`cannot activate connection from status FAILED`) — proves the terminal-state guard, not the tenant guard, fires here (both layers independently exercised across the matrix) |
| `fn_create_plugin_installation`, caller tenant = A, `p_organization_id` = B (forged) | **Rejected** — `plugins: caller tenant context does not match the requested organization` |
| `fn_reactivate_plugin_installation`, caller tenant context = B, `p_organization_id` argument = A (forged) | **Rejected** — identical guard message |

**Result: PASS**, zero forged mutations succeeded. Raw logs: `execution_logs/20260829T220000Z_06_tenant_forgery_oauth_integration_lifecycle_matrix.txt`, `..._07_plugin_tenant_forgery_and_lifecycle_matrix.txt`.

## 10. OAuth Result

| Test | Result |
|---|---|
| Redemption with correct `p_expected_definition_id` | **Succeeds**, `oauth_attempt_id` returned |
| Same state, second redemption attempt (single-use) | **Rejected** — `already redeemed` |
| Redemption with wrong `p_expected_definition_id` (provider-binding mismatch) | **Rejected** — `OAuth attempt was not issued for the expected provider` |
| Genuine wall-clock expiry (`pg_sleep(3)` past a 2-second `expires_at`) then redemption | **Rejected** — `OAuth attempt ... has expired` |

**Result: PASS** for every case re-run this pass (single-use, provider-binding, genuine expiry). The full 14-case matrix from the prior pass exercises additional sub-cases (pre-redemption denial, post-redemption exchange-failure split, RLS on `oauth_attempts`) against unchanged SQL and is cited, not re-run, here. Raw log: `execution_logs/20260829T220000Z_06_tenant_forgery_oauth_integration_lifecycle_matrix.txt`.

## 11. Integration Lifecycle Result

| Transition | Result |
|---|---|
| `CONNECTING → FAILED` (`fn_fail_integration_connection`) | Succeeds, `status = FAILED` |
| `FAILED → ACTIVE` (`fn_activate_integration_connection`) | **Rejected** — `cannot activate connection from status FAILED` |
| `CONNECTING → ACTIVE → DISCONNECTED` (`fn_activate_integration_connection` then `fn_disconnect_integration_connection`) | Succeeds, `status = DISCONNECTED` |
| `DISCONNECTED → ACTIVE` (`fn_activate_integration_connection`) | **Rejected** — `cannot activate connection from status DISCONNECTED` |
| RLS: `SELECT` for a foreign `organization_id` as `app_api` | 0 rows |
| RLS: `SELECT` for the caller's own `organization_id` as `app_api` | 1 row (the row created earlier in the same test) |

**Result: PASS.** No `FAILED→ACTIVE`, no `DISCONNECTED→ACTIVE` — both explicitly-forbidden terminal-state transitions are rejected live. Raw log: `execution_logs/20260829T220000Z_06_tenant_forgery_oauth_integration_lifecycle_matrix.txt`.

## 12. Plugin Lifecycle Result

| Transition | Result |
|---|---|
| Install (`fn_create_plugin_installation`) | Succeeds, `status = INSTALLED` |
| `INSTALLED → ACTIVE` (`fn_activate_plugin`, `enabled_capabilities = {send_message}`) | Succeeds, `status = ACTIVE` |
| `ACTIVE → SUSPENDED` (`fn_suspend_plugin_installation`) | Succeeds, `status = SUSPENDED` |
| `SUSPENDED → ACTIVE` (`fn_reactivate_plugin_installation`), forged caller tenant = B / `p_organization_id` = A | **Rejected** — tenant-forgery guard |

**Result: PASS.** Install→activate→suspend all succeed for the legitimate tenant; the cross-tenant forged reactivate is rejected. Raw log: `execution_logs/20260829T220000Z_07_plugin_tenant_forgery_and_lifecycle_matrix.txt`.

## 13. Plugin/Workflow Version-Pinning Result

**Contract-level only — explicitly not a DB execution test.** No `workflow.*` runtime code exists anywhere in this repository (6I is itself a design-only document, per its own governing constraint), so there is nothing to execute for "publish a workflow node referencing a plugin capability and observe `PLUGIN_VERSION_PINNED_MISMATCH`." What this pass verifies instead:

- 6I §67 (`6I-Workflow-APIs.md`) now defines the `credential_reference` field (`credential_source`, `plugin_installation_id`, `plugin_version_id`, `capability`) on `WebhookNodeConfig`/`ApiCallNodeConfig`, matching 6J §30.2's contract shape verbatim (cross-checked field-by-field, §30.2 vs. §67.2 — identical).
- 6I §67.3 specifies the exact five publish-time checks (org match, `ACTIVE` status, exact `plugin_version_id` equality, capability enabled, capability in manifest) and the runtime re-check (org, status, exact version equality, capability enabled) — matching 6J §30.5's contract exactly.
- `PLUGIN_VERSION_PINNED_MISMATCH` is defined as the same canonical error code on both sides of the boundary (6J §35/ADR-6J-09; 6I §47/§67.3) — not a synonym invented independently by either document.
- The underlying DB-level primitives this contract depends on — `plugin_installations.plugin_version_id`, `plugin_installations.enabled_capabilities`, `plugin_installations.status`, `plugin_versions.manifest` — were all directly queried and confirmed to exist with the expected shape during §12's plugin lifecycle test.

**Result: Contract-level PASS (specification consistency confirmed by direct cross-document field/check comparison); no runtime execution claim is made, and none is warranted given no application code exists to execute.**

## 14. Webhook Signing/Rotation Result

```sql
-- endpoint created with signing_secret_ref = 'secret_manager://webhook/v1'
SELECT webhooks.fn_rotate_webhook_secret(org_id, endpoint_id, 'secret_manager://webhook/v2', 3600);
-- signing_secret_ref = 'secret_manager://webhook/v2'
-- previous_signing_secret_ref = 'secret_manager://webhook/v1'
-- previous_secret_expires_at > NOW()  -> true (grace window active)
```

**Result: PASS.** The rotated endpoint carries both the new current secret and the prior secret with a live, unexpired grace-period timestamp in the same atomic call — a delivery worker can verify against either during the grace window. Re-confirms the identical result already proven in the prior pass against the same unchanged function. Raw log: `execution_logs/20260829T220000Z_06_tenant_forgery_oauth_integration_lifecycle_matrix.txt` (test 8).

## 15. Inbound Callback Security Result

Not re-executed this pass — the underlying mechanism (opaque per-connection routing segment resolved before payload trust, `INSERT ... ON CONFLICT DO NOTHING RETURNING id` dedup pattern) is unchanged SQL, already live-proven in the prior pass including a genuine two-session concurrent-duplicate-delivery race (`execution_logs/20260829T210000Z_13a_...`/`13b_...`). Cited as still-valid, unchanged-SQL evidence, not re-claimed as freshly executed this pass.

## 16. SSRF Result

**Not executed — application-layer logic with no deployed application code anywhere in this repository to run it against.** This is unchanged from the prior pass's own disclosure (6J §30.3/§60) and remains an honest statement about the repository's contents, not a skipped test. The only DB-layer-enforceable portion of the SSRF contract — `webhook_endpoints.target_url` HTTPS-only `CHECK` constraint — was confirmed structurally present (`chk_we_target_https` in the `\d webhooks.webhook_endpoints` output captured during §14's test).

## 17. RLS Result

`rls_ic_tenant`, `rls_oa_tenant`, `rls_we_tenant` (and by extension the rest of `integrations`/`plugins`/`webhooks`'s `ENABLE + FORCE` policies) re-confirmed structurally present via `\d` on each table during this pass's own test scripts, and functionally re-proven for `integration_connections`: a cross-tenant `SELECT` as `app_api` returns 0 rows; the caller's own-tenant `SELECT` returns the expected row. **Result: PASS.**

## 18. Privileges Result

Not independently re-queried in full this pass (unchanged `GRANT`/`REVOKE` statements, already fully inventoried and live-proven in the prior pass — `PUBLIC EXECUTE = false` on all 34 functions, every role's grant matching design, validation report §15). The one privilege-relevant behavior this pass did re-exercise organically: the tenant-forgery and terminal-state rejections above all fired from calls made as the seeding superuser acting under `SET LOCAL app.tenant_id`, not `app_api`/`app_worker` role-switched sessions, for test-script simplicity — this is a weaker proof of role-level privilege separation than the prior pass's dedicated `has_function_privilege()` sweep, which remains the authoritative privilege evidence. **Result: PASS (cited from prior pass, not independently re-swept this pass).**

## 19. Regression Result

Fresh + incremental migration (§5-§6) exercising all 101 revisions from `001_5B` onward is itself a full-platform regression check — no migration in the chain failed, meaning no regression was introduced in any schema/function/grant belonging to Phases 5B-5J or 6J's own closure. No targeted spot-check beyond this was performed this pass (the prior pass's own targeted regression spot-check on the outbox, worker-only scoping, and 6I's own RLS remains the authoritative regression evidence for those specific areas, validation report §17). **Result: PASS** (full linear migration replay; no independent additional spot-check this pass).

## 20. Remaining P0/P1/P2

**P0: none.** Every check above is either a live PASS on PostgreSQL 18.6 or an explicitly-disclosed, honestly-labeled non-DB-executable item (SSRF, plugin-version-pinning runtime code).

**P1: none remaining as open.** `DEP-6J-06` closed by explicit V1 scope decision (§56 of `6J-Integrations-Webhooks-Plugins-APIs.md`) — V1 sync is frozen as an async trigger only; no sync-job table is required or planned for V1.

**P2 (non-blocking, unchanged from the prior pass, carried forward as future enhancements, not defects):**
- `DEP-6J-03` — no DB-level uniqueness constraint on `(definition_id, external_account_ref)`.
- `DEP-6J-07` — no auto-suspend mechanism for chronically-dead-lettered webhook endpoints.
- `DEP-6J-08` — `category`/`configuration_schema`/`feature_maturity` remain application-layer metadata, not DB columns (by design, matches executed DDL).
- 83 of 84 `gen_uuid_v7`-affected functions outside `integrations`/`plugins`/`webhooks` — root-cause fix applied and benefits all 84 transitively; a full audit of which of the other 83 actually exercise the previously-broken code path is out of this document's scope.

---

## Verdict

`PHASE 6J — IMPLEMENTATION READY` (restated; PostgreSQL 18.6 authoritative baseline).

Zero P0. Zero implementation-blocking P1. `DEP-6J-06` closed by V1 scope decision. `DEP-6J-12` closed via the 6I §67 compatibility amendment. Every remaining item is either explicitly non-blocking or honestly labeled as untestable at this repository's current layer (no application code exists to execute against). This report does not declare itself, nor `6J-Integrations-Webhooks-Plugins-APIs.md`, `FROZEN` — final freeze/approval remains an independent-review decision.
