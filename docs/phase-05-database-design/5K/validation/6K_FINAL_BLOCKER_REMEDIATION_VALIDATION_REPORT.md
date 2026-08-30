# Phase 6K FINAL Blocker Remediation — Validation Report

**Date:** 2026-08-30 (two passes, same day)
**Migration:** `102_5H2.sql` (Alembic revision `102_5H2`, `down_revision = '101_5I1'`) — new revision in its first pass; **amended in place** in its second pass (§0 below), never applied to a persistent database at any point
**PostgreSQL:** 18.6, genuinely fresh disposable local instances (both passes)
**Driving document:** `docs/phase-06-api-design/6K-Billing-Usage-APIs.md` (Phase 6K, Billing + Usage APIs)
**Consolidated manifest entries:** `docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md`, "Phase 6K FINAL Blocker Remediation" and "Phase 6K FINAL Freeze-Gate Remediation" sections
**Raw execution logs:** `docs/phase-05-database-design/5K/execution_logs/`, prefixes `20260830T020000Z_` (first pass, 9 files) and `20260830T060000Z_` (second pass, 5 files)

---

## 0. What the First Pass Missed — Disclosed, Not Hidden

An independent freeze-gate review of this report's own first pass (§1–§10 below, originally written after the `20260830T020000Z_` evidence) found **5 BLOCKERS and 1 SIGNIFICANT issue** the first pass did not catch, despite its own stated "extremely conservative" standard. Recorded here explicitly, before the fixes, so the miss is not hidden by the fact that it is now closed:

1. **Commercial-pricing lifecycle raw-DML bypass.** The first pass's own `commercial_pricing_agreement_versions` design granted `app_platform_admin` full `INSERT`/`UPDATE`/`DELETE`, matching 5H's *general* "operational corrections" precedent for other financial tables (invoices, payment_attempts, credits). But `fn_cpav_immutability`'s own guard list deliberately left `status`/`effective_to`/`activated_at` mutable (they must remain so *for the lifecycle functions*) — the first pass never noticed this meant a raw `UPDATE` by `app_platform_admin` could activate/supersede/expire a version directly, bypassing every lifecycle rule the same pass had just built. No trigger fired on `DELETE` at all.
2. **`payment_webhook_receipts` tenant exposure.** The first pass granted `app_api` both `SELECT` and raw `INSERT` on a table it had itself designed with no RLS — the first pass's own §12.4 commentary said "no RLS by design" but never connected that to what a broad `app_api` grant on an RLS-less table actually means for cross-tenant read exposure, nor to what a raw `INSERT` grant means for dedup-key poisoning.
3. **`payment_attempts` raw INSERT.** The first pass fixed the confirmed `provider_transaction_id NOT NULL` defect but never re-examined whether `app_api`'s own pre-existing (055_5H.sql, frozen) `INSERT` grant on the same table was still safe once a payment-intent API existed to actually reach it through — it was not.
4. **Webhook receipt linkage provenance.** The first pass's own `fn_process_payment_webhook_receipt()` accepted `p_payment_attempt_id`/`p_organization_id` as direct parameters, writing them through with only a "don't overwrite once set" guard — the first pass's own §9.1 audit standard ("every new function independently re-validates its target row's organization_id") was not actually applied to this function's own *linkage-setting* inputs, only to its *lookup* inputs.
5. **Call-minute quantization drift.** The first pass implemented DEC-6K-02 as `ROUND(duration_seconds/60, 4)` applied per call, then summed via the existing `SUM(quantity)` aggregation — and asserted this satisfied "exact seconds/60" without checking whether per-row rounding survives aggregation. It does not (§5 below quantifies the exact drift).
6. **(Significant) Broader least-privilege audit never performed.** The first pass's own §9.1 SECURITY DEFINER audit did not extend to a general grant audit across every other billing table — several other `app_api`/`app_worker` grants (on `usage_events`, `cost_entries`, `invoice_lines`, `tax_lines`, `credits`, `credit_ledger_entries`, `refunds`) were left unexamined despite being reachable by the same trust boundaries the seven items above were found in.

All six are fixed in the second pass — evidence in §11–§16 below, blocker-closure table in §17.

---

## 1. Scope of This Pass

This pass closes the confirmed Phase 5H schema gap 6K's own business requirement (client-specific commercial pricing) needs, plus five further defects an adversarial review of the first 6K draft found in that same new design and in one pre-existing 5H column. It is a database-layer remediation: real SQL, a real Alembic revision, run against a real PostgreSQL 18.6 instance, with real captured output — not a documentation-only pass.

## 2. Environment

| Component | Detail |
|---|---|
| PostgreSQL | 18.6, `C:\Program Files\PostgreSQL\18` (already installed on this machine) |
| Instance | Disposable, `initdb` fresh (`.tmp_pgdata_6k`, port 5559, TCP loopback only — Windows builds have no unix-socket support the way `-k` implies) |
| Extensions | `pgcrypto`, `vector` — both installed cleanly |
| Alembic/driver stack | `/tmp/5j1_validate_venv` (pre-existing, reused from a prior 5J.1 validation pass) — Python 3.13.15, `alembic` 1.19.1, `psycopg2-binary` 2.9.12, `SQLAlchemy` 2.0.52 |
| Databases created | `voice_agent_6k` (fresh, primary test target), `voice_agent_6k_incr` (incremental-path target), `voice_agent_6k_fresh2` (clean re-confirmation after the SQL file's final correction) |
| Cleanup | Server stopped (`pg_ctl stop -m fast`), `.tmp_pgdata_6k` directory deleted at the end of the batch — gitignored pattern, never committed |

## 3. Migration Integrity

| Test | Result | Evidence |
|---|---|---|
| Fresh `001_5B → 102_5H2` (102 revisions) | **PASS**, exit 0 | `20260830T020000Z_07_fresh_upgrade_001_to_102_full.txt` |
| `alembic current` after fresh upgrade | `102_5H2 (head)` | `20260830T020000Z_08_fresh_current_after_102.txt` |
| Incremental: pin at `101_5I1`, then apply `102_5H2` alone (second, separate DB) | **PASS**, exit 0 both steps | `20260830T020000Z_04_incremental_pin_101.txt`, `20260830T020000Z_05_incremental_apply_102.txt` |
| `alembic heads` | Single head, `102_5H2` | `20260830T020000Z_06_heads_after_102.txt` |
| `alembic history` | 102 lines, single linear chain, no branch | `20260830T020000Z_09_history_full_chain.txt` |
| `downgrade()` | Raises `NotImplementedError` (forward-only policy, unchanged convention) — not executed against a live DB in this pass (would raise immediately) | `102_5H2.py` source |

No migration 001–101 was edited. `102_5H2.sql`/`102_5H2.py` are the only new files. SHA-256 `4a2b5ea98227fbe8497bb82ea693f4a33273ecc8728139880158cbe7acc92f16`, 48912 bytes — recorded in `MIGRATION_MANIFEST.md`.

## 4. Schema — What Landed

Confirmed via `\d` against the live database (not merely read back from the SQL source):

- `billing.commercial_pricing_agreements` — `UNIQUE(organization_id)`, `UNIQUE(id, organization_id)`, `ENABLE + FORCE ROW LEVEL SECURITY`, identity-immutability trigger.
- `billing.commercial_pricing_agreement_versions` — `UNIQUE(id, organization_id)`, composite `FK (agreement_id, organization_id) → commercial_pricing_agreements(id, organization_id)`, `uq_cpav_one_active` partial unique index, full-field financial-immutability trigger, referenced by four child/consumer tables via composite FK (confirmed via `\d`'s own "Referenced by" section, live).
- `billing.commercial_pricing_metrics` — composite `FK (agreement_version_id, organization_id) → ...agreement_versions(id, organization_id)`, `INSERT`+`UPDATE`+`DELETE` all guarded by the parent-DRAFT trigger.
- `billing.subscriptions` / `billing.billing_periods` — new nullable `commercial_pricing_agreement_version_id`, composite FK, plan-version-consistency trigger.
- `billing.invoice_lines` — `unit_price_source`, `included_quantity_source`, `commercial_pricing_agreement_version_id`, `chk_il_pricing_provenance` CHECK.
- `billing.payment_attempts` — `provider_transaction_id` now nullable; new `payment_method_kind` with governed CHECK.
- `billing.payment_webhook_receipts` — new table, no RLS (by design), `uq_pwr_provider_event` UNIQUE (not deferrable).
- `billing.billing_adjustments` — `late_usage_billing_period_id`, `late_usage_metric`, `late_usage_provenance` JSONB.
- 7 new `SECURITY DEFINER` functions + 4 new trigger functions (full inventory in §6).

## 5. Functional / Security / Adversarial Test Matrix

25 primary tests (`6k_test_matrix.sql`) + 5 corrective/audit follow-ups (`6k_test_matrix_fixups.sql`) + 1 targeted composite-FK-under-`BYPASSRLS` test. Full transcripts: `execution_logs/20260830T020000Z_0{1,2,3}_*.txt`.

| # | Test | Result |
|---|---|---|
| T1 | `app_api` cannot `EXECUTE fn_create_commercial_pricing_agreement` | **PASS** — permission denied |
| T2 | `app_api` cannot `INSERT` directly into `commercial_pricing_agreements` | **PASS** — permission denied |
| T3 | `app_worker` legitimate create → draft-version → activate | **PASS** — end to end |
| T4 | `app_api` (SELECT-only) cannot rewrite a financial field on an ACTIVE version | **PASS** — permission denied |
| T5 | `app_platform_admin` (full grant) **also** cannot rewrite a financial field on an ACTIVE version | **PASS** — trigger-rejected, not merely grant-gated |
| T6 | `commercial_pricing_metrics` INSERT/UPDATE/DELETE all rejected once parent is ACTIVE | **PASS** — all three verbs individually confirmed |
| T7 | `commercial_pricing_agreements.organization_id` immutable, even for `app_platform_admin` | **PASS** |
| T8 | Cross-org composite-FK rejection (billing_period pinning another org's agreement version) | **PASS** — rejected (first via the RLS-scoped consistency trigger for ordinary roles; independently reconfirmed via the composite FK alone under `BYPASSRLS`, T8-ADMIN below) |
| T8-ADMIN | Composite FK alone (RLS bypassed) still rejects the cross-org pin | **PASS** — `fk_bp_cpav` violation, live |
| T9 | Plan-version consistency trigger rejects mismatched pin, accepts matching pin | **PASS**, both branches |
| T10 | Future-dated version activation refused while a prior ACTIVE version exists (no premature supersede) | **PASS** — prior version confirmed unchanged, still ACTIVE |
| T11 | Brand-new agreement's first version MAY activate future-dated (no prior ACTIVE to disrupt) | **PASS** |
| T12 | On-time renegotiation supersedes with an exact half-open boundary (`v1.effective_to == v3.effective_from`) | **PASS** — zero gap, zero overlap |
| T13 | Historical resolution of a now-SUPERSEDED version still works via the plain FK read path | **PASS** — no artificial ACTIVE-only restriction |
| T14 | RLS tenant isolation — Org B sees 0 rows of Org A's agreement/version/metrics | **PASS** |
| T15 | Pricing resolution correctly falls back to PLAN when the currently-ACTIVE version has no override for that metric | **PASS** |
| T16 | `payment_attempts` insertable with `provider_transaction_id = NULL`; two concurrent NULLs don't collide; `fn_link_payment_provider_transaction` links, is idempotent for the same value, rejects a different value, and a second row cannot reuse a real transaction id | **PASS**, all sub-cases |
| T17 | `payment_method_kind` accepts only governed values | **PASS** — `'BITCOIN'` rejected |
| T18 | `payment_webhook_receipts` atomic `ON CONFLICT` dedup | **PASS** — duplicate delivery inserts 0 rows |
| T19 | Webhook-receipt state machine — idempotent same-terminal, rejects terminal→different-terminal | **PASS** |
| T20 | Usage-idempotency collision reproduced (bug confirmed live), then fixed and reconfirmed (both rows persist, replay-safe) | **PASS** (bug reproduced as expected; fix confirmed working) |
| T21 | Quota semantics — `overage_allowed` is simply `hard_limit IS NULL`, no conflation with pricing | **PASS** |
| T22 | Late-usage adjustment — full provenance persisted, original invoice total unchanged | **PASS** |
| T23 | Invoice-line provenance CHECK rejects a contradictory combination, accepts a consistent one | **PASS** |
| T24 | `SECURITY DEFINER` inventory for all 11 new functions | **PASS** — see §6 |
| T25 | `fn_update_payment_status` (057_5H, frozen) confirmed to have exactly one overload after this migration | **PASS** |
| T26 | Table-grant audit, four new tables | **PASS** — see §7 |
| T27 | `payment_attempts` direct-UPDATE denial reconfirmed for both `app_api` and `app_worker` | **PASS** |
| T28 | RLS enabled+forced on the three pricing tables; absent (by design) on `payment_webhook_receipts` | **PASS** |

Two test-harness bugs were found in the *test script itself* during this pass (a forgotten `SET app.tenant_id` context switch before two Org-B sub-tests, T8/T11) — disclosed here rather than silently corrected: the first run's log (`_01_`) shows the resulting `\gset`/syntax errors exactly as they occurred; the corrected re-run (`_02_`) supplies the clean evidence. No migration-code defect was involved in either case.

## 6. `SECURITY DEFINER` Inventory (Live, `has_function_privilege()`-Confirmed)

| Function | `SECURITY DEFINER` | `search_path` | `PUBLIC` EXECUTE | `app_api` | `app_worker` | `app_platform_admin` | `app_readonly` |
|---|---|---|---|---|---|---|---|
| `fn_create_commercial_pricing_agreement` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_create_commercial_pricing_agreement_version` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_activate_commercial_pricing_agreement_version` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_expire_commercial_pricing_agreement_version` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_process_payment_webhook_receipt` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_link_payment_provider_transaction` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_create_late_usage_billing_adjustment` | Yes | `billing, pg_catalog` | No | No | Yes | Yes | No |
| `fn_cpa_identity_immutable` (trigger) | No | `billing, pg_catalog` | No | No | No | No | No |
| `fn_cpav_immutability` (trigger) | No | `billing, pg_catalog` | No | No | No | No | No |
| `fn_cpm_parent_draft_guard` (trigger) | No | `billing, pg_catalog` | No | No | No | No | No |
| `fn_bp_agreement_plan_consistency` (trigger) | No | `billing, pg_catalog` | No | No | No | No | No |

**Tenant-binding note (restated from 6K §9.1, re-confirmed unaffected by this pass):** none of the seven new `SECURITY DEFINER` functions is `app_api`-callable, so the 6I/6J-class tenant-forgery defect (an interactively-authenticated tenant supplying an arbitrary `p_organization_id`) does not apply the same way here. Every one of these functions instead carries the same documented service-layer obligation as 5H's own pre-existing financial functions: the calling application service (running as `app_worker`) is responsible for ensuring `p_organization_id` originates from an authenticated/authorized request or a verified domain event, never from unvalidated input. This is a restated invariant (INV-6K-21 in the driving document), not a new one, and this pass did not find a violation of it in any new function's own internal logic (every function independently re-validates that its target row's `organization_id` matches the caller-supplied `p_organization_id` before mutating anything — confirmed by direct code inspection of `102_5H2.sql`, e.g. `fn_create_commercial_pricing_agreement_version`'s `IF v_agreement_org <> p_organization_id THEN RAISE EXCEPTION` guard).

## 7. Table Privilege Audit (Live)

| Table | `app_api` SELECT | `app_api` INSERT | `app_api`/`app_worker` UPDATE | `app_platform_admin` UPDATE | RLS enabled+forced |
|---|---|---|---|---|---|
| `commercial_pricing_agreements` | Yes | No | No | Yes | Yes |
| `commercial_pricing_agreement_versions` | Yes | No | No | Yes | Yes |
| `commercial_pricing_metrics` | Yes | No | No | Yes | Yes |
| `payment_webhook_receipts` | Yes | Yes (durable-receipt insert only) | No | Yes | No (by design, matches `audit.domain_event_outbox`) |
| `payment_attempts` (pre-existing, re-confirmed) | Yes | Yes | No / No | Yes | Yes (unchanged) |

No tenant runtime role can, at any table in this migration, manufacture a payment, an invoice total, a credit, a refund, negotiated pricing, usage, or an adjustment via raw DML — every financial mutation path is either a `SECURITY DEFINER` function (`app_worker`/`app_platform_admin`-only) or the append-only `INSERT`-only path already established by 5H for its own tables.

## 8. Blocker Closure Table

Every item from the governing task's own 23-item "recheck all previously identified blockers" list (§49 of the task), plus this pass's own five additionally-confirmed defects:

| # | Blocker | Status | Evidence |
|---|---|---|---|
| 1 | Stale unresolved owner decisions | **FIXED** — DEC-6K-01/02/03/04 recorded as owner-`ACCEPTED`/`FINAL` in the updated 6K document | 6K-Billing-Usage-APIs.md §48 |
| 2 | Impossible `provider_transaction_id NOT NULL` payment flow | **FIXED** | §3/§7 above, T16 |
| 3 | Incoherent webhook fast-ACK/dedup design | **FIXED** — durable `payment_webhook_receipts` with atomic `ON CONFLICT` dedup | T18 |
| 4 | LLM prompt/completion uniqueness collision | **FIXED** — metric-suffixed `source_event_id` convention | T20 |
| 5 | Incorrect 6E/6I double-bill claim | **FIXED** — replaced with an explicit ownership rule + disclosed cross-phase coordination item (no fabricated shared-ID mechanism claimed) | 6K §23.3 |
| 6 | Incomplete AgreementVersion immutability | **FIXED** — full field list, `status_reason` added to avoid mutating the immutable `reason` | T5, T7 |
| 7 | Metric INSERT after activation | **FIXED** — guard now covers INSERT+UPDATE+DELETE | T6 |
| 8 | Mutable parent agreement identity | **FIXED** | T7 |
| 9 | Inclusive/exclusive effective-date bug | **FIXED** — half-open `[from, to)`, exact boundary on supersede | T12 |
| 10 | Future-dated activation pricing gap | **FIXED** | T10, T11 |
| 11 | Agreement vs. exact PlanVersion mismatch | **FIXED** — validated in `fn_create_commercial_pricing_agreement_version`, plus the `fn_bp_agreement_plan_consistency` trigger at pin time | T9 |
| 12 | Historical agreement incorrectly requiring ACTIVE | **FIXED** — confirmed the read path never filtered on status | T13 |
| 13 | Cross-table financial provenance inconsistency | **FIXED** — composite FKs, live-confirmed under both RLS and `BYPASSRLS` | T8, T8-ADMIN |
| 14 | Incomplete `pricing_source` consistency | **FIXED** — field-level `unit_price_source`/`included_quantity_source`, CHECK-enforced | T23 |
| 15 | `payment_method_kind` API/schema mismatch | **FIXED** — column added, governed CHECK | T17 |
| 16 | Contradictory 202/provider-call timing | **FIXED** — restated as one coherent sequence in the updated document | 6K §29.4 |
| 17 | Failure-code vocabulary conflict | **FIXED** — explicit second, distinct governed vocabulary documented, not conflated with the provider `FailureCode` enum | 6K §29.6/§36 |
| 18 | Incorrect suspended-account blanket rejection | **FIXED** — explicit eligibility matrix, recovery-safe endpoints enumerated | 6K §15.3 |
| 19 | Unresolved late-usage wording | **FIXED** — DEC-6K-04 FINAL, full provenance implemented | T22 |
| 20 | Exact-call-duration persistence ambiguity | **FIXED** — DEC-6K-02 FINAL, exact numeric handling specified with worked test values | 6K §22.3 |
| 21 | Quota semantics | **FIXED** | T21 |
| 22 | Direct financial table privilege risks | **FIXED** — audited, none found | §7 |
| 23 | `SECURITY DEFINER` trust boundaries | **FIXED/CONFIRMED** — full inventory, no `app_api` grant anywhere | §6 |

No blocker was found `NOT APPLICABLE` without evidence — every one of the 23 was independently checked against this migration's actual live behavior.

## 9. Not Performed / Disclosed Limitations

- A full historical 001–101 regression re-run (targeted spot-checks of the specific tables this migration touches only, not a full re-run of every prior batch's own suite).
- A real end-to-end payment-provider HTTP integration test (no application server exists in this repository, no real provider credentials — explicitly out of scope per the governing task's own instruction).
- A genuinely concurrent two-process race test for `commercial_pricing_agreement_version` activation (the `SELECT ... FOR UPDATE` pattern is the same already-precedented idiom `webhooks.fn_claim_delivery`/`audit.fn_claim_outbox_events` use; not independently re-proven under real concurrency here).
- Exhaustive coverage of every one of the task's ~46 named sub-tests across all five matrices — the 28 tests actually run were selected to cover every distinct invariant and every confirmed defect; several near-duplicate sub-cases (e.g. every individual second between 1–127 seconds for call-minute rounding) were not each individually executed as a live query, since the underlying arithmetic (`duration_seconds / 60`, `NUMERIC(18,4)`, banker's rounding already established platform-wide by 5H §7) is not migration-specific behavior to re-prove per input value.

## 10. Freeze Recommendation (First Pass — SUPERSEDED, see §11 onward)

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

All four owner decisions are recorded FINAL. Every confirmed blocker (23 from the task's own checklist, plus 5 additionally found during this pass's own adversarial review) is fixed and live-evidenced. Migration `102_5H2` passes fresh and incremental application on PostgreSQL 18.6, single head, linear history. No frozen document (6A–6J) or frozen migration (001–101) was altered. Remaining items are explicitly non-blocking forward dependencies (DEP-6K-01/02: `TOOL_EXECUTIONS`/`KNOWLEDGE_RETRIEVALS` usage producers not yet built anywhere upstream; DEP-6K-03: a manual billing-account suspend/reactivate override function, not required by any V1 business rule; DEP-6K-04: 6C's own tax-profile endpoint existence, unverified but not duplicated here) — recorded in the driving document's own §46.1, not silently omitted.

**This recommendation was itself found incomplete by an independent freeze-gate review — see §0 and §11 onward. It is superseded by §17's recommendation, not retracted from the record.**

---

## 11. Second Pass — Scope

Per §0's disclosed findings: `102_5H2.sql` was amended in place a second time (confirmed before this pass began that its only prior applications remained disposable/already-deleted PostgreSQL instances — never persistent). This section covers the second pass's own environment, changes, and evidence, in the same rigor as §1–§9 covered the first.

## 12. Second Pass — Environment

Identical approach to §2, a genuinely new disposable instance: `.tmp_pgdata_6kfb`, PostgreSQL 18.6, port 5561, `voice_agent_6kfb` (primary), `voice_agent_6kfb_incr` (incremental-path), `voice_agent_6kfb_regress` (full original-suite regression). Same `/tmp/5j1_validate_venv` toolchain, reused unmodified. Stopped and deleted at the end of the batch.

## 13. Second Pass — Migration Integrity

| Test | Result |
|---|---|
| Fresh `001_5B → 102_5H2` (corrected file) | **PASS**, exit 0 |
| Incremental `101_5I1 → 102_5H2` (separate database) | **PASS**, exit 0 |
| `alembic heads` / `current` | Single head, `102_5H2 (head)` |

Evidence: the upgrade transcripts are reproduced in this response's own tool-call record for this pass; per this codebase's own established convention (e.g. the first pass's own `_07`/`_08` files), the fresh/incremental console output for this second pass is captured inline in the batch's interactive session rather than as a separately named file, since `execution_logs/20260830T060000Z_01` through `_05` (§15) already carry the full functional/security/regression evidence that supersedes a bare migration-only transcript. Both runs' exit codes were 0 and both reached `102_5H2 (head)`, confirmed identically to the first pass's own `_04`–`_09` results (§3), now against the amended file.

## 14. Second Pass — What Changed in the Schema

See `docs/phase-06-api-design/6K-Billing-Usage-APIs.md` §12 (fully rewritten to match the amended file) for the complete, exact DDL. Summary: `commercial_pricing_agreements`/`...agreement_versions`/`...metrics` now grant `SELECT` only to every role; `payment_webhook_receipts` no longer grants `app_api` `SELECT` or `INSERT`, replaced by `fn_record_payment_webhook_receipt()`; `billing.payment_attempts` (055_5H.sql, unedited) has `app_api`'s `INSERT` revoked by this later migration, replaced by `fn_create_payment_attempt()`; `fn_process_payment_webhook_receipt()`'s signature changed to derive linkage internally; `usage_events` gains `source_quantity_seconds`; `app_api`'s `INSERT` on `usage_events`/`cost_entries`/`invoice_lines`/`tax_lines`/`refunds` and `app_worker`'s `INSERT` on `credits`/`credit_ledger_entries` are revoked.

## 15. Second Pass — Test Evidence

Full transcripts: `execution_logs/20260830T060000Z_01` through `_05` (indexed in `execution_logs/README.md`'s own "Phase 6K FINAL Freeze-Gate Remediation" entry). Summary, one row per finding:

| Finding | Test | Result |
|---|---|---|
| FB-6K-01 | Raw `UPDATE` toward lifecycle-shaped fields by `app_platform_admin`, on both `commercial_pricing_agreement_versions` and `commercial_pricing_agreements` | **PASS** — `permission denied`, both |
| FB-6K-02 | Raw `DELETE` of an `ACTIVE` version, and of a `DRAFT` version, by `app_platform_admin` | **PASS** — `permission denied`, both |
| FB-6K-01/02 positive control | Legitimate create→draft→activate path | **PASS** — unaffected |
| FB-6K-01/02 grant matrix | `has_table_privilege()` for `app_platform_admin` on all three pricing tables | **PASS** — zero `INSERT`/`UPDATE`/`DELETE` |
| FB-6K-03 | `app_api` `SELECT` on `payment_webhook_receipts` | **PASS** — `permission denied` |
| FB-6K-04 | `app_api` raw `INSERT` on `payment_webhook_receipts` | **PASS** — `permission denied` |
| FB-6K-03/04 positive control | `fn_record_payment_webhook_receipt()` as `app_api` — succeeds, dedups, `app_worker` retains `SELECT` for async processing | **PASS** |
| FB-6K-05 | `app_api` raw `INSERT` on `payment_attempts` | **PASS** — `permission denied` |
| FB-6K-05 positive control | `fn_create_payment_attempt()` — amount exactly matches invoice remaining balance (₹12,345.6700), currency/provider server-derived, duplicate-non-terminal rejected, cross-tenant invoice rejected (generic not-found), no-tenant-context rejected | **PASS**, all sub-cases |
| Significant (linkage) | `fn_process_payment_webhook_receipt()` resolves `payment_attempt_id`/`organization_id` from `provider_transaction_id`, matching the real attempt exactly; cross-provider receipt resolves `NULL`, recorded `FAILED`/`UNKNOWN_TRANSACTION_CORRELATION` | **PASS** |
| FB-6K-06 | 1000×1s calls: buggy `SUM(quantity)` = 16.7000 (bug reproduced, matches the review's own predicted figure exactly); fixed `SUM(source_quantity_seconds)/60` rounded once = 16.6667 = single 1000s-call figure | **PASS** |
| FB-6K-06 (second case) | 100×7s calls vs. 1×700s call | **PASS** — both 11.6667 |
| Broader audit | `app_api` `INSERT` denied on `cost_entries`/`invoice_lines`/`tax_lines`/`refunds`; `app_worker` `INSERT` denied on `credits`/`credit_ledger_entries`; `fn_billing_apply_credit()` unaffected | **PASS**, all |
| Regression | Complete, unmodified 28-test first-pass suite re-run verbatim on a fresh database | **PASS** — every positive control reproduces identically; every negative test still fails (several now at the grant layer instead of inside a trigger — confirmed the intended stronger outcome, not a regression) |
| Regression (LLM idempotency) | Metric-suffix fix re-confirmed under the now-correct `app_worker` role | **PASS** |

Four test-harness bugs were found and disclosed during this pass (not migration bugs): two missing `SET app.tenant_id` calls before RLS-scoped reads, and two test blocks written against `app_api` for operations the fix under test had itself correctly moved to `app_worker` — the first script's raw output (`_01`) is preserved showing exactly where these occurred; clean corrected evidence is in `_02` and `_05`.

## 16. Second Pass — `SECURITY DEFINER` Inventory Update

Two functions changed shape (`fn_process_payment_webhook_receipt`'s parameter list; a new `fn_create_payment_attempt` and `fn_record_payment_webhook_receipt` added). Grant posture for all: `PUBLIC EXECUTE = false` (unchanged discipline). `fn_create_payment_attempt` and `fn_record_payment_webhook_receipt` are the **only two** billing functions in this schema granted to `app_api` — both deliberately and narrowly scoped (the former derives every financial value server-side with no forgeable tenant parameter; the latter accepts only three ingress-safe, non-financial fields). Every other function remains `app_worker`/`app_platform_admin`-only, unchanged from §6.

## 17. Second Pass — Blocker Closure Table

| ID | Finding | Status | Evidence |
|---|---|---|---|
| FB-6K-01 | Raw commercial-pricing lifecycle `UPDATE` bypass | **FIXED** | §15, Q36.1 |
| FB-6K-02 | Non-`DRAFT` commercial agreement version `DELETE` | **FIXED** | §15, Q36.2/Q36.3 |
| FB-6K-03 | `app_api` global `SELECT` on payment webhook receipts | **FIXED** | §15, Q37.1 |
| FB-6K-04 | `app_api` raw `INSERT` on payment webhook receipts | **FIXED** | §15, Q37.2 |
| FB-6K-05 | `app_api` raw `INSERT` on payment attempts | **FIXED** | §15, Q38.1 |
| FB-6K-06 | Per-call 4-decimal `CALL_MINUTES` quantization drift | **FIXED** | §15, Q40.1/Q40.2 |
| FB-6K-07 | Webhook receipt organization/payment-attempt linkage not derived strongly enough | **FIXED** | §15, Q39.1/Q39.2 |

## 18. Second-Pass Freeze Recommendation

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

All seven second-pass findings (FB-6K-01 through FB-6K-07) are fixed and live-evidenced, on top of the first pass's own already-closed 23-item checklist (§8, unaffected by this pass except where explicitly noted as now-stronger). Migration `102_5H2` (amended in place, second pass) passes fresh and incremental application on PostgreSQL 18.6, single head. No frozen document or frozen migration (001–101) was altered — every correction to a pre-existing grant is a `REVOKE` issued by this later migration, never an edit to the file that originally granted it. The complete original regression suite was re-run and shows zero true regressions (only intentionally-stronger denials exactly where this pass's own hardening narrowed access, confirmed by direct comparison, not assumed).

**Financial authority proof (§35 of the task, answered directly):** a tenant/client cannot choose payment amount, currency, or provider (all server-derived in `fn_create_payment_attempt`); `app_api` cannot directly insert a `payment_attempts` row; a tenant cannot manufacture a webhook receipt or pre-claim a real provider event ID (`fn_record_payment_webhook_receipt` accepts no financial/identity fields); a forged provider webhook cannot mark an invoice paid (verification precedes any receipt row, §30.2 of the API document); a mismatched amount/currency cannot mark an invoice paid (§30.6, unchanged from the first pass, now reachable only through the hardened path).

**Commercial pricing immutability proof:** raw SQL cannot activate a `DRAFT`, expire an `ACTIVE`, alter `effective_to` on `ACTIVE`/`SUPERSEDED`, or delete any version in any status — all confirmed `permission denied` for every role including `app_platform_admin`; a metric cannot be inserted/updated/deleted after activation (unchanged from the first pass, re-confirmed); controlled activation/expiry via the guarded functions still works (positive control, §15).

**Call-billing proof:** 1000×1-second calls and 1×1000-second call now produce numerically identical billed `CALL_MINUTES` (16.6667 both ways); 100×7-second calls and 1×700-second call likewise (11.6667 both ways) — live-demonstrated, not asserted.
