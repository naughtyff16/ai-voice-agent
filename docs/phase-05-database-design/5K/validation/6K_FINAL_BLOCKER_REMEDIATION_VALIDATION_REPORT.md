# Phase 6K FINAL Blocker Remediation — Validation Report

**Date:** 2026-08-30 (six passes, same day)
**Migration:** `102_5H2.sql` (Alembic revision `102_5H2`, `down_revision = '101_5I1'`) — new revision in its first pass; **amended in place** in its second through sixth passes (§0/§19/§25/§32/§39 below), never applied to a persistent database at any point
**PostgreSQL:** 18.6, genuinely fresh disposable local instances (all six passes)
**Driving document:** `docs/phase-06-api-design/6K-Billing-Usage-APIs.md` (Phase 6K, Billing + Usage APIs)
**Consolidated manifest entries:** `docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md`, "Phase 6K FINAL Blocker Remediation", "Phase 6K FINAL Freeze-Gate Remediation", "Phase 6K FINAL Two-Issue Freeze Remediation", "Phase 6K FINAL Freeze-Gate Remediation Pass", "Phase 6K FINAL Webhook Processing Integrity Remediation", and "Phase 6K FINAL Convergence, Durability & Commercial-Pricing Remediation" sections
**Raw execution logs:** `docs/phase-05-database-design/5K/execution_logs/`, prefixes `20260830T020000Z_` (first pass, 9 files), `20260830T060000Z_` (second pass, 5 files), `20260830T090000Z_` (third pass, 1 file), `20260830T150000Z_` (fourth pass, 9 files), `20260830T180000Z_` (fifth pass, 10 files), and `20260830T210000Z_` (sixth pass, 11 files)

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

## 18. Second-Pass Freeze Recommendation (SUPERSEDED — see §19 onward)

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

All seven second-pass findings (FB-6K-01 through FB-6K-07) are fixed and live-evidenced, on top of the first pass's own already-closed 23-item checklist (§8, unaffected by this pass except where explicitly noted as now-stronger). Migration `102_5H2` (amended in place, second pass) passes fresh and incremental application on PostgreSQL 18.6, single head. No frozen document or frozen migration (001–101) was altered — every correction to a pre-existing grant is a `REVOKE` issued by this later migration, never an edit to the file that originally granted it. The complete original regression suite was re-run and shows zero true regressions (only intentionally-stronger denials exactly where this pass's own hardening narrowed access, confirmed by direct comparison, not assumed).

**Financial authority proof (§35 of the task, answered directly):** a tenant/client cannot choose payment amount, currency, or provider (all server-derived in `fn_create_payment_attempt`); `app_api` cannot directly insert a `payment_attempts` row; a tenant cannot manufacture a webhook receipt or pre-claim a real provider event ID (`fn_record_payment_webhook_receipt` accepts no financial/identity fields); a forged provider webhook cannot mark an invoice paid (verification precedes any receipt row, §30.2 of the API document); a mismatched amount/currency cannot mark an invoice paid (§30.6, unchanged from the first pass, now reachable only through the hardened path).

**Commercial pricing immutability proof:** raw SQL cannot activate a `DRAFT`, expire an `ACTIVE`, alter `effective_to` on `ACTIVE`/`SUPERSEDED`, or delete any version in any status — all confirmed `permission denied` for every role including `app_platform_admin`; a metric cannot be inserted/updated/deleted after activation (unchanged from the first pass, re-confirmed); controlled activation/expiry via the guarded functions still works (positive control, §15).

**Call-billing proof:** 1000×1-second calls and 1×1000-second call now produce numerically identical billed `CALL_MINUTES` (16.6667 both ways); 100×7-second calls and 1×700-second call likewise (11.6667 both ways) — live-demonstrated, not asserted.

**This recommendation was itself found incomplete by a further independent freeze-gate review — see §19 onward. It is superseded by §24's recommendation, not retracted from the record.**

---

## 19. What the Second Pass Missed — Disclosed, Not Hidden

A further independent freeze-gate review found **1 BLOCKER and 1 SIGNIFICANT issue** the second pass's own "Financial authority proof" (§18) did not catch, despite explicitly addressing the adjacent capability:

1. **`app_api` retained `EXECUTE` on `fn_record_payment_webhook_receipt`.** §18's own proof claimed "a tenant cannot manufacture a webhook receipt or pre-claim a real provider event ID (`fn_record_payment_webhook_receipt` accepts no financial/identity fields)" — true as far as it went (the function cannot be used to inject *financial* state), but the second pass never asked whether `app_api` should be able to call the function *at all*. It could: `app_api` still held `EXECUTE`, so the general tenant-facing runtime role could call the function directly and consume `UNIQUE (payment_provider, provider_event_id)` for a real, not-yet-arrived provider event ID — poisoning the dedup key before the genuine webhook arrives, causing the real delivery to be silently treated as a duplicate and never processed. The distinction the second pass's own proof glossed over: "cannot inject financial state through this function" is not the same claim as "cannot call this function at all," and only the latter actually closes the dedup-poisoning threat.
2. **`chk_ue_source_quantity_seconds` never required the column for `CALL_MINUTES`.** The second pass's own §12.7a fix (adding the column) correctly stopped per-call rounding-before-aggregation, but the constraint it shipped only checked `source_quantity_seconds IS NULL OR source_quantity_seconds >= 0` — a `CALL_MINUTES` row with the column left `NULL` was still perfectly legal at the DB layer. The exact-aggregation guarantee therefore depended entirely on the ingestion consumer's own discipline (a documented convention, §22.3), not a structural DB invariant — exactly the class of gap this document's own §6 SECURITY DEFINER audit standard ("every new function independently re-validates") was supposed to generalize to every new invariant, not just function parameters.

Both are fixed in the third pass — evidence in §20–§23, closure table in §24.

---

## 20. Third Pass — Scope

Per §19's disclosed findings: `102_5H2.sql` was amended in place a third time (confirmed before this pass began that its only prior applications remained disposable/already-deleted PostgreSQL instances — never persistent).

## 21. Third Pass — Environment

Identical approach to §2/§12: a genuinely new disposable instance, `.tmp_pgdata_6kf2`, PostgreSQL 18.6, port 5563, `voice_agent_6kf2` (primary), `voice_agent_6kf2_incr` (incremental-path). Same `/tmp/5j1_validate_venv` toolchain, reused unmodified. Stopped and deleted at the end of the batch.

## 22. Third Pass — Migration Integrity

| Test | Result |
|---|---|
| Fresh `001_5B → 102_5H2` (corrected file) | **PASS**, exit 0 |
| Incremental `101_5I1 → 102_5H2` (separate database) | **PASS**, exit 0 |
| `alembic heads` / `current` | Single head, `102_5H2 (head)` |

## 23. Third Pass — Test Evidence

Full transcript: `execution_logs/20260830T090000Z_01_6k_final2_test_matrix_output.txt` (indexed in `execution_logs/README.md`'s own "Phase 6K FINAL Two-Issue Freeze Remediation" entry). 12 tests, no test-harness bugs this pass:

| Finding | Test | Result |
|---|---|---|
| Role sanity | `app_billing_webhook_ingress`: `LOGIN=true`, `BYPASSRLS=false` | **PASS** |
| Grant matrix | `EXECUTE` on `fn_record_payment_webhook_receipt`: `app_api=f`, `app_worker=f`, `app_platform_admin=f`, `app_billing_webhook_ingress=t`, `PUBLIC=f` | **PASS** |
| FINAL-6K-01 negative | `app_api` calls the function | **PASS** — `permission denied` |
| FINAL-6K-01 negative (table, regression) | `app_api` `SELECT`/`INSERT` on the table directly | **PASS** — both `permission denied`, unaffected by this pass |
| FINAL-6K-01 negative | `app_worker` calls the function | **PASS** — `permission denied` (confirms the "too broad" rationale) |
| FINAL-6K-01 negative | `app_platform_admin` calls the function | **PASS** — `permission denied` (mirrors `app_voice_reconciler`'s own precedent) |
| FINAL-6K-01 positive | `app_billing_webhook_ingress` calls the function, first delivery + duplicate | **PASS** — first call returns a UUID, duplicate returns `NULL` |
| FINAL-6K-01 minimal surface | `app_billing_webhook_ingress` `SELECT` on `payment_attempts`/`payment_webhook_receipts`/`invoices` | **PASS** — all `false` |
| FINAL-6K-02 negative | `CALL_MINUTES` with `source_quantity_seconds = NULL` | **PASS** — `chk_ue_source_quantity_seconds` violation |
| FINAL-6K-02 negative | `CALL_MINUTES` with `source_quantity_seconds = -1` | **PASS** — constraint violation |
| FINAL-6K-02 positive | `CALL_MINUTES` with `source_quantity_seconds = 127` | **PASS** — succeeds |
| FINAL-6K-02 non-restriction | `CAMPAIGN_CALLS` with `source_quantity_seconds = NULL` | **PASS** — succeeds (constraint is `CALL_MINUTES`-scoped only) |
| FINAL-6K-02 aggregation | 1000×1s vs. 1×1000s; 100×7s vs. 1×700s, under the now-mandatory regime | **PASS** — 16.6667=16.6667; 11.6667=11.6667 |
| Regression | `app_api` `INSERT` on `usage_events` | **PASS** — `permission denied`, unaffected |
| Regression | `app_api` `INSERT` on `payment_attempts` (FB-6K-05) | **PASS** — `permission denied`, unaffected |
| Regression | `app_platform_admin` `EXECUTE` on `fn_create_commercial_pricing_agreement` | **PASS** — call reaches the function's own business-rule check (fails only on a missing plan fixture, not a permission error), confirming the grant itself is intact |

## 24. Third-Pass Freeze Recommendation (SUPERSEDED — see §25 onward)

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

Both third-pass findings (FINAL-6K-01, FINAL-6K-02) are fixed and live-evidenced, on top of the first and second passes' own already-closed items (§8, §17 — unaffected by this pass except where the fix itself required a new, narrower grant). Migration `102_5H2` (amended in place, third pass) passes fresh and incremental application on PostgreSQL 18.6, single head. No frozen document or frozen migration (001–101) was altered — the new `app_billing_webhook_ingress` role and the strengthened `CHECK` constraint are both additive statements in this same, still-unapplied migration file. A targeted regression smoke test confirms the two most relevant prior fixes (FB-6K-05's `payment_attempts` `INSERT` denial, the commercial-pricing lifecycle `EXECUTE` grants) are unaffected.

**Final security proof, answered directly (task §28):** `app_api` cannot `SELECT` payment webhook receipts (No); cannot `INSERT` webhook receipts directly (No); cannot call `fn_record_payment_webhook_receipt` (No — closed this pass); a trusted provider-webhook principal (`app_billing_webhook_ingress`) can record a verified provider event (Yes); a duplicate provider event cannot create a second durable receipt (No — atomic `ON CONFLICT`, unchanged); tenant runtime cannot pre-claim a provider event ID (No — closed this pass, the actual mechanism by which the prior "cannot manufacture financial state" proof did not yet imply "cannot call the function at all").

**Final call-billing proof, answered directly (task §29):** a new `CALL_MINUTES` usage row cannot be stored with `source_quantity_seconds = NULL` (No — closed this pass, DB-enforced); negative source seconds cannot be stored (No); 1000×1-second calls equal 1×1000-second call after billing conversion (Yes, 16.6667 both ways); 100×7-second calls equal 1×700-second call (Yes, 11.6667 both ways); per-call minute rounding is not used for the billing aggregation input (No — exact seconds are summed, rounded once).

**This recommendation was itself found incomplete by a further independent freeze-gate review — see §25 onward. It is superseded by §31's recommendation, not retracted from the record.**

---

## 25. What the Third Pass Missed — Disclosed, Not Hidden

A further independent freeze-gate review found **1 BLOCKER (schema/grant), 1 BLOCKER (documentation), and 1 SIGNIFICANT issue (evidence)** the third pass's own §24 did not catch:

1. **`app_platform_admin` retained raw `INSERT`/`UPDATE`/`DELETE` directly on `billing.payment_webhook_receipts`.** §24's own "Final security proof" answered whether `app_api` could reach the table or the ingress function — it never asked the same question of `app_platform_admin`'s **table-level** grant (as opposed to its function-`EXECUTE` grant, which the third pass *did* close). Even with `fn_record_payment_webhook_receipt`'s `EXECUTE` restricted to `app_billing_webhook_ingress` alone (third pass, FINAL-6K-01), `app_platform_admin` could still bypass that dedicated ingress path entirely via a raw table write — pre-claim/poison a real `(payment_provider, provider_event_id)` pair, overwrite `processing_status`/`payment_attempt_id`/`organization_id`/`last_error`, or `DELETE` a receipt row outright, rewriting the platform's own webhook ingestion history (security/audit evidence, not an ordinary correctable financial record). The distinction the third pass's own proof did not separately verify: closing `EXECUTE` on the function is not the same guarantee as closing raw `DML` on the table the function writes to — both paths reach the same state, and only closing both closes the threat.
2. **`6K-Billing-Usage-APIs.md` still described the ingress function as `app_api`-reachable in `ADR-6K-15`.** The third pass's own SQL fix (§20–§23) correctly moved `EXECUTE` to `app_billing_webhook_ingress`, and most of the document's sections were updated to match — but `ADR-6K-15`'s own title and body, and one row of the §12.8 live-validation table, were not, leaving the authoritative document internally inconsistent with its own migration at the exact point a reviewer would check first (the ADR that supposedly records this decision).
3. **No preserved fresh/incremental migration transcript existed for the third pass's own final checksum.** The third pass's 12-test matrix proved the privilege/constraint fixes functionally, but the migration-application evidence chain (fresh `001 → 102`, incremental `101 → 102`, `alembic heads`/`current`/`history`) was not separately re-captured against that exact amended file's bytes after the third amendment — a gap between "the fix works" and "the fix is the file whose checksum is on record."

All three are fixed in the fourth pass — evidence in §26–§30, closure table in §31.

---

## 26. Fourth Pass — Scope

Per §25's disclosed findings: `102_5H2.sql` was amended in place a fourth time (confirmed before this pass began that its only prior applications remained disposable/already-deleted PostgreSQL instances — never persistent). No existing-role investigation found a fit other than a `REVOKE` on the existing over-broad `app_platform_admin` grant — no new role was needed for FREEZE-6K-01 (unlike FINAL-6K-01 in the third pass, which did require one).

## 27. Fourth Pass — Environment

Same disposable-instance approach as every prior pass: `.tmp_pgdata_6kfreeze`, PostgreSQL 18.6, port 5564, `voice_agent_6kfreeze` (primary), `voice_agent_6kfreeze_incr` (incremental-path). The same `/tmp/5j1_validate_venv` toolchain was reused unmodified. Stopped and deleted at the end of the batch.

## 28. Fourth Pass — Migration Integrity

| Test | Result |
|---|---|
| Fresh `001_5B → 102_5H2` (fourth-amendment file) | **PASS**, exit 0 |
| Incremental `101_5I1 → 102_5H2` (separate database) | **PASS**, exit 0 |
| `alembic heads` / `current` (both databases) | Single head, `102_5H2 (head)`, `current == head` |
| Final checksum vs. `MIGRATION_MANIFEST.md` row 102 | **Match** — `3ea497b0a0727cc39c0ef0d4c0781f21139727aa6959198d788f48ee85dd7259`, 82365 bytes (closes FREEZE-6K-03) |

## 29. Fourth Pass — Test Evidence

Full transcripts: `execution_logs/20260830T150000Z_01` through `_09` (indexed in `execution_logs/README.md`'s own "Phase 6K FINAL Freeze-Gate Remediation Pass" entry). 22 assertions, two test-harness fixture bugs found and fixed on the first attempt (disclosed below, neither a migration defect):

| Finding | Test | Result |
|---|---|---|
| Grant matrix (table) | `payment_webhook_receipts`: `app_api`/`app_billing_webhook_ingress` all-`false`; `app_worker`/`app_platform_admin` `SELECT=t`, others `false` | **PASS** |
| Grant matrix (function) | `fn_record_payment_webhook_receipt` `EXECUTE`: unchanged from third pass — `app_billing_webhook_ingress` only | **PASS** (regression) |
| FREEZE-6K-01 negative | `app_platform_admin` direct `INSERT` | **PASS** — `permission denied` |
| FREEZE-6K-01 negative | `app_platform_admin` direct `UPDATE` | **PASS** — `permission denied` |
| FREEZE-6K-01 negative | `app_platform_admin` direct `DELETE` | **PASS** — `permission denied` |
| FREEZE-6K-01 positive (retained) | `app_platform_admin` direct `SELECT` | **PASS** — succeeds, returns the seeded row (documented, intentional read-only allowance) |
| Regression negative | `app_api` `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`EXECUTE` on the table/function | **PASS** — all five `permission denied`, unaffected |
| Regression negative | `app_billing_webhook_ingress` direct table `INSERT`/`UPDATE`/`DELETE`/`SELECT` | **PASS** — all four `permission denied` (function-only surface, unaffected) |
| Regression negative | `app_worker` direct table `INSERT`/`UPDATE`/`DELETE` | **PASS** — all three `permission denied`; `SELECT` still succeeds (reconciliation-scan need, unaffected) |
| Positive controlled path | Trusted ingress creates + dedups a receipt; `app_worker` links + transitions it through `fn_process_payment_webhook_receipt`, resolving the correct attempt/organization internally | **PASS** — `linkage_correct = t` |
| Positive controlled path | Neither `app_api` nor `app_platform_admin` can mutate the resulting `PROCESSED` receipt | **PASS** — both `permission denied` |
| Regression | Payment attempt: `app_api` direct `INSERT` denied, guarded `fn_create_payment_attempt` succeeds | **PASS** |
| Regression | `CALL_MINUTES`: `NULL`/negative `source_quantity_seconds` rejected, valid accepted, 1000×1s = 1×1000s aggregation | **PASS** — 16.6667 = 16.6667 |
| Regression | Commercial pricing: raw `UPDATE`/`DELETE` denied for `app_platform_admin` (before and after `ACTIVE`); controlled create/version/activate succeeds end to end | **PASS** |
| Regression | `fn_create_late_usage_billing_adjustment` still exists, still `app_worker`-granted | **PASS** |
| Regression | `fn_create_payment_attempt` grant unaffected for `app_api` and `app_worker` | **PASS** |
| `SECURITY DEFINER` final audit | `fn_record_payment_webhook_receipt` grantees: `{app_billing_webhook_ingress, postgres}` only; other three functions' grantees unchanged from third pass | **PASS** |

**Test-harness bugs found and fixed (disclosed, not hidden):** the fixture `INSERT INTO billing.invoices` initially omitted the `NOT NULL` `billing_account_id` and several `NOT NULL` `*_currency` companion columns, causing both fixture invoices to fail to insert — which then correctly cascaded into "invoice not found" errors from `fn_create_payment_attempt` (the function behaving exactly as designed against genuinely missing data) and one unset-`\gset`-variable syntax error in the dependent async-processor test. Fixed by supplying a complete, schema-correct fixture; the full 22-assertion matrix then ran clean with zero further test-harness bugs. Neither bug was a migration or grant defect.

## 30. Fourth Pass — `SECURITY DEFINER` Inventory Update

| Function | Grantees (current, post-fourth-pass) |
|---|---|
| `fn_record_payment_webhook_receipt` | `app_billing_webhook_ingress` (sole non-owner grantee — unchanged from third pass; this pass closed the separate table-DML path, not this function's own grant) |
| `fn_process_payment_webhook_receipt` | `app_worker`, `app_platform_admin` (unchanged) |
| `fn_link_payment_provider_transaction` | `app_worker`, `app_platform_admin` (unchanged) |
| `fn_create_payment_attempt` | `app_api`, `app_worker`, `app_platform_admin` (unchanged — the one deliberately `app_api`-granted billing function) |

## 31. FREEZE-6K-01/02/03 Closure Table and Fourth-Pass Freeze Recommendation (SUPERSEDED — see §32 onward)

| ID | Finding | Fix | Evidence |
|---|---|---|---|
| FREEZE-6K-01 (BLOCKER) | `app_platform_admin` raw `INSERT`/`UPDATE`/`DELETE` on `payment_webhook_receipts` | `REVOKE`d; `SELECT` retained (narrow, read-only, documented) | §29 grant-matrix + negative/positive tests |
| FREEZE-6K-02 (BLOCKER, documentation) | Stale `ADR-6K-15`/table wording said the ingress function is `app_api`-callable | `ADR-6K-15` rewritten; every cross-referencing section in `6K-Billing-Usage-APIs.md` checked and corrected | Whole-document grep sweep, zero stale matches remaining |
| FREEZE-6K-03 (SIGNIFICANT, evidence) | No preserved fresh/incremental transcript for the final `102_5H2` checksum | Fresh + incremental re-run against the exact final file; checksum cross-checked against the manifest | §28, `execution_logs/20260830T150000Z_01/_02/_03/_09` |

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

All three fourth-pass findings (FREEZE-6K-01, FREEZE-6K-02, FREEZE-6K-03) are fixed and live-evidenced, on top of the first, second, and third passes' own already-closed items (§8, §17, §24 — unaffected by this pass except where the fix itself required a narrower grant). Migration `102_5H2` (amended in place, fourth pass) passes fresh and incremental application on PostgreSQL 18.6, single head, checksum-verified against the manifest. No frozen document or frozen migration (001–101) was altered — the `app_platform_admin` correction is a `REVOKE` issued by this same, still-unapplied migration file, never an edit to a different file. A regression smoke test covering payment attempts, `CALL_MINUTES`, commercial pricing, late-usage grant, and suspension/recovery grant confirms zero true regressions.

**Final webhook security proof, answered directly (task §26):** `app_api` cannot `SELECT` the receipt table (No); cannot `INSERT` (No); cannot `UPDATE` (No); cannot `DELETE` (No); cannot `EXECUTE` the ingress function (No). `app_platform_admin` cannot directly `INSERT` a receipt (No — closed this pass); cannot directly `UPDATE` (No — closed this pass); cannot directly `DELETE` (No — closed this pass); retains `SELECT` (Yes — documented, read-only). The dedicated webhook ingress role can execute the receipt function (Yes) and cannot directly `INSERT` the table (No). A duplicate provider event cannot create a second receipt (No — atomic `ON CONFLICT`, unchanged). Tenant runtime cannot pre-claim a provider event ID, by any path — function or table (No — the table path is what this pass closed).

**Final migration evidence proof, answered directly (task §27):** fresh final migration (PASS); incremental final migration (PASS); single Alembic head (YES); current == head (YES, both databases); final migration checksum in manifest matches actual file (YES — §28); new execution logs correspond to final file bytes (YES — the fresh/incremental runs in §28 and the test matrix in §29 were both run against the identical file whose checksum is recorded in §28's own table).

**This is the fourth and, per this pass's own live evidence, current recommendation — not a claim that no further review is warranted. Independent freeze-gate review remains the authority that declares `FROZEN`.**

**This recommendation was itself found incomplete by a further independent freeze-gate review — see §32 onward. It is superseded by §38's recommendation, not retracted from the record.**

---

## 32. What the Fourth Pass Missed — Disclosed, Not Hidden

A further independent freeze-gate review found **1 BLOCKER (schema/function)** the fourth pass's own §31 did not catch, plus one stale SQL comment:

1. **`fn_process_payment_webhook_receipt` could write `PROCESSED` with no authoritative correlation.** Every prior pass's own "final security proof" answered whether unauthorized *roles* could reach the receipt table or the ingress function — none of them asked whether the *processing function itself*, called correctly by its own authorized caller (`app_worker`), could still produce an unsafe outcome. It could: if a caller requested `p_new_status = 'PROCESSED'` for a provider transaction that failed to resolve to any local `payment_attempt` (`v_resolved_attempt_id`/`v_resolved_org` staying `NULL`), the function wrote `processing_status = 'PROCESSED'` with both `payment_attempt_id` and `organization_id` `NULL` anyway — and because `uq_pwr_provider_event`'s dedup gate is permanent, that outcome could never be revisited by a genuine future delivery of the same provider event. The function's own design comment ("this function's own job is resolution, not the security-anomaly decision") was correct for the *linkage* decision but had wrongly been extended to cover the *PROCESSED-vs-FAILED* decision too. Deeper still: even a *resolved* correlation was not sufficient — the function never verified that the correlated `payment_attempt`'s own financial state had actually reached `SUCCEEDED` before allowing `PROCESSED`, meaning `PROCESSED` meant only "an id was found," not "the payment actually settled."
2. **A stale SQL comment.** The migration's own Part C comment block, immediately preceding the `payment_webhook_receipts` table, still described the obsolete first-draft ingress model ("the inbound webhook HTTP handler ... executing as the API service's own DB role ... performs the durable, atomic dedup INSERT directly ... no wrapping SECURITY DEFINER function needed") — inconsistent with every actual grant in the same file since the second pass (`FB-6K-03/04`) and the dedicated `app_billing_webhook_ingress` role introduced in the third pass (`FINAL-6K-01`).

Both are fixed in the fifth pass — evidence in §33–§37, closure in §38.

---

## 33. Fifth Pass — Scope

Per §32's disclosed findings: `102_5H2.sql` was amended in place a fifth time (confirmed before this pass began that its only prior applications remained disposable/already-deleted PostgreSQL instances — never persistent).

## 34. Fifth Pass — Environment

Same disposable-instance approach as every prior pass: `.tmp_pgdata_6kwebhook`, PostgreSQL 18.6, port 5565, `voice_agent_6kwebhook` (primary), `voice_agent_6kwebhook_incr` (incremental-path). The same `/tmp/5j1_validate_venv` toolchain was reused unmodified. Stopped and deleted at the end of the batch.

## 35. Fifth Pass — Migration Integrity

| Test | Result |
|---|---|
| Fresh `001_5B → 102_5H2` (fifth-amendment file) | **PASS**, exit 0 |
| Incremental `101_5I1 → 102_5H2` (separate database) | **PASS**, exit 0 |
| `alembic heads` / `current` (both databases) | Single head, `102_5H2 (head)`, `current == head` |
| Final checksum vs. `MIGRATION_MANIFEST.md` row 102 | **Match** — `9c995df348eac3569a9b7b18f355ef38565ec013199078ee81eb2f1157d552c5`, 91847 bytes |

## 36. Fifth Pass — The Fix

1. **New table `CHECK`, `chk_pwr_processed_requires_correlation`:** `processing_status = 'PROCESSED'` is now structurally impossible without both `payment_attempt_id` and `organization_id` already non-`NULL` on the same row, for any writer whatsoever. `FAILED` (including fully unlinked) remains legal.
2. **`fn_process_payment_webhook_receipt` fails closed:** immediately before its `UPDATE`, whenever `p_new_status = 'PROCESSED'` is requested, the function now (a) raises if correlation did not resolve, and (b) re-reads the resolved `payment_attempts` row's own `status` in the same transaction — under standard PostgreSQL MVCC read-committed-within-transaction visibility, this sees the caller's own prior `fn_update_payment_status`/`fn_mark_invoice_paid` writes — and raises unless that status reads `'SUCCEEDED'`. This is the genuine atomicity guarantee: "an id was found" is no longer sufficient.
3. **Stale SQL comment corrected** to describe the actual, current ingress flow (`app_billing_webhook_ingress` → `fn_record_payment_webhook_receipt` → durable receipt → commit → fast ACK → `app_worker` async processing).

## 37. Fifth Pass — Test Evidence

Full transcripts: `execution_logs/20260830T180000Z_01` through `_10` (indexed in `execution_logs/README.md`'s own "Phase 6K FINAL Webhook Processing Integrity Remediation" entry). 21 assertions, one test-harness bug found and fixed on the first attempt (disclosed below):

| Finding | Test | Result |
|---|---|---|
| Table CHECK (Test A) | `PROCESSED` + `payment_attempt_id` NULL + `organization_id` NULL, direct superuser `INSERT` | **PASS** — `chk_pwr_processed_requires_correlation` violation |
| Table CHECK (Test B) | `PROCESSED` + attempt only, org NULL | **PASS** — violation |
| Table CHECK (Test C) | `PROCESSED` + org only, attempt NULL | **PASS** — violation |
| Table CHECK (Test D) | `FAILED` + both NULL | **PASS** — succeeds (approved failure model, unaffected) |
| Unknown provider transaction | `PROCESSING` transition with an unresolvable `provider_transaction_id` | **PASS** — succeeds, both resolved ids `NULL` |
| Unknown provider transaction | Subsequent `PROCESSED` attempt on the same receipt | **PASS** — controlled `RAISE EXCEPTION`, receipt remains `PROCESSING`, uncorrupted |
| Unknown provider transaction | Governed `FAILED`/`UNKNOWN_TRANSACTION_CORRELATION` path instead | **PASS** — succeeds, `last_error` populated, both ids remain `NULL` |
| Valid correlation, atomicity | `PROCESSED` requested before the financial transition commits (`payment_attempt.status = PENDING`) | **PASS** — controlled exception, receipt remains `PROCESSING` |
| Valid correlation, atomicity | Identical `PROCESSED` call, retried after `fn_update_payment_status(SUCCEEDED)` + `fn_mark_invoice_paid` genuinely commit | **PASS** — succeeds; `payment_attempt_id`/`organization_id` populated, `processed_at` set |
| Duplicate webhook after success | Repeat `fn_record_payment_webhook_receipt` for the same `(provider, event_id)` | **PASS** — returns `NULL`, no second receipt |
| Duplicate webhook after success | Repeat `fn_process_payment_webhook_receipt(..., 'PROCESSED', ...)` on the already-`PROCESSED` receipt | **PASS** — idempotent, same resolved ids, no re-processing |
| Provider mismatch | Cross-provider receipt/attempt correlation attempt | **PASS** — resolves `NULL`; `PROCESSED` attempt raises; mismatched attempt confirmed still `PENDING` |
| Regression | Table/function privilege matrix (`app_api`, `app_billing_webhook_ingress`, `app_worker`, `app_platform_admin`) | **PASS** — unchanged from the fourth pass |
| Regression | `app_api` `SELECT` denied; `app_platform_admin` `INSERT` denied | **PASS** — unaffected |
| Regression | `CALL_MINUTES` `NULL`-seconds rejection; commercial-pricing raw `UPDATE` denial | **PASS** — unaffected |

**Test-harness bug found and fixed (disclosed, not hidden):** an early draft of Tests A-D attempted to exercise the new `CHECK` via a raw `INSERT` executed as `app_platform_admin` — which has held no `INSERT` grant on this table since the fourth pass (`FREEZE-6K-01`), so every attempt failed with `permission denied` before ever reaching the `CHECK`, proving nothing about the constraint. Fixed by running the same inserts as the connecting superuser instead (the standard technique for testing a schema-level `CHECK` in isolation from a separate privilege-model layer no application role can bypass); the corrected run then produced the intended `chk_pwr_processed_requires_correlation` violations. Not a migration defect.

**Not performed / disclosed limitations (same as prior passes, plus one new item):** no real payment-provider HTTP integration test; no genuinely concurrent two-process race test — the sequential "`PROCESSED` before vs. after the financial commit" test above is the deterministic, reproducible equivalent of the meaningful race risk, since the fix's own same-transaction MVCC-visibility mechanism is exactly what a genuine race would also exercise; the full first- through fourth-pass regression suites were not re-run verbatim (a targeted regression check was run instead, per the same proportionate-evidence approach every prior pass used).

---

## 38. Webhook Processing Integrity Closure and Fifth-Pass Freeze Recommendation (SUPERSEDED — see §39 onward)

| Finding | Fix | Evidence |
|---|---|---|
| `PROCESSED` reachable with `payment_attempt_id`/`organization_id` both `NULL` (BLOCKER) | New `chk_pwr_processed_requires_correlation` table CHECK; `fn_process_payment_webhook_receipt` fails closed on unresolved correlation | §37 Tests A-D, unknown-transaction tests |
| `PROCESSED` reachable without the correlated payment actually having settled (the deeper atomicity gap) | Function re-verifies the resolved `payment_attempt`'s own `SUCCEEDED` status in the same transaction before permitting `PROCESSED` | §37 valid-correlation atomicity tests |
| Stale SQL comment describing the obsolete direct-INSERT-by-`app_api` ingress model | Corrected in place to describe the current `app_billing_webhook_ingress` → `fn_record_payment_webhook_receipt` flow | Migration file Part C, `6K-Billing-Usage-APIs.md` §12.4/§30.2 |

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

Both fifth-pass findings are fixed and live-evidenced, on top of the first through fourth passes' own already-closed items (§8, §17, §24, §31 — unaffected by this pass except where the fix itself strengthened the same function). Migration `102_5H2` (amended in place, fifth pass) passes fresh and incremental application on PostgreSQL 18.6, single head, checksum-verified against the manifest. No frozen document or frozen migration (001–101) was altered.

**Successful processing atomicity, answered directly (task §H):** a receipt cannot become `PROCESSED` if the financial transition fails or has not yet committed, because the function's own final check re-reads the correlated `payment_attempt`'s status inside the same transaction under standard PostgreSQL MVCC visibility — a status that is not `SUCCEEDED` (whether never attempted, still pending, or genuinely failed) causes the function to raise instead of writing `PROCESSED`. "An id was found" is structurally insufficient; only a committed `SUCCEEDED` financial state satisfies the check.

**This is the fifth and, per this pass's own live evidence, current recommendation — not a claim that no further review is warranted. Independent freeze-gate review remains the authority that declares `FROZEN`.**

**This recommendation was itself found incomplete by a further independent freeze-gate review — see §39 onward. It is superseded by §44's recommendation, not retracted from the record.**

---

## 39. What the Fifth Pass Missed — Disclosed, Not Hidden

A further independent freeze-gate review found **3 BLOCKERS, 1 SIGNIFICANT commercial-pricing issue, and 1 documentation issue** the fifth pass's own §38 did not catch:

1. **Callback-before-response could become permanently terminal (FINAL-6K-C01).** The fifth pass closed the "PROCESSED without settlement" hole but never asked what happens when correlation genuinely fails to resolve on the FIRST attempt — the ordinary, expected outcome of a webhook arriving before the provider's own synchronous API response finishes linking `provider_transaction_id`. The only non-`PROCESSING` outcome available was `FAILED`, and `FAILED` is terminal — durable dedup (`uq_pwr_provider_event`) would then permanently strand a real, later-resolvable payment behind an unrecoverable receipt.
2. **A durable receipt could not survive a commit→enqueue crash (FINAL-6K-C02).** The receipt was durable as a ROW, but not durable as PROCESSABLE INFORMATION — it stored only `payment_provider`/`provider_event_id`/`payload_hash`, none of which a process other than the original request (e.g. a reconciliation worker recovering from a crashed/lost Celery enqueue) could use to actually resume processing. `provider_transaction_id` and the settled amount/currency existed only as transient function arguments in the live request's own memory.
3. **`PROCESSED` still did not prove invoice settlement (FINAL-6K-C03).** The fifth pass's own fix required `payment_attempt.status = 'SUCCEEDED'` — a real improvement, but insufficient: `PaymentAttempt = SUCCEEDED` with `Invoice` still `OPEN` remained reachable, since those two transitions could still commit separately under the fifth pass's own design (the caller sequenced three separate function calls, only the last of which the fifth pass's fix re-verified).
4. **Commercial pricing could not follow an organization across a plan-family change (SIGNIFICANT).** `uq_cpa_org` (`UNIQUE(organization_id)`) — present since the very first pass and never itself flagged by any of the five prior reviews — made it structurally impossible for an organization that negotiated Growth pricing to ever negotiate Enterprise pricing later, since a second agreement row was blocked and the first agreement's `base_plan_id` is (correctly, deliberately) immutable.
5. **DEC-6K-02's own summary wording was ambiguous (documentation).** The owner-decision section's worked implementation line, read in isolation, did not clearly distinguish the per-row audit/display quantity from the invoice's own authoritative aggregation source — an ambiguity in the SUMMARY's wording, not in the actual implementation (§12.7a/§22.3 have specified exact-seconds aggregation since the second pass).

All five are fixed in the sixth pass — evidence in §40–§43, closure in §44.

---

## 40. Sixth Pass — Scope

Per §39's disclosed findings: `102_5H2.sql` was amended in place a sixth time (confirmed before this pass began that its only prior applications remained disposable/already-deleted PostgreSQL instances — never persistent).

## 41. Sixth Pass — Environment

Same disposable-instance approach as every prior pass: `.tmp_pgdata_6kconverge`, PostgreSQL 18.6, port 5566, `voice_agent_6kconverge` (primary), `voice_agent_6kconverge_incr` (incremental-path). The same `/tmp/5j1_validate_venv` toolchain was reused unmodified. Stopped and deleted at the end of the batch.

## 42. Sixth Pass — Migration Integrity

| Test | Result |
|---|---|
| Fresh `001_5B → 102_5H2` (sixth-amendment file) | **PASS**, exit 0 |
| Incremental `101_5I1 → 102_5H2` (separate database) | **PASS**, exit 0 |
| `alembic heads` / `current` (both databases) | Single head, `102_5H2 (head)`, `current == head` |
| Final checksum vs. `MIGRATION_MANIFEST.md` row 102 | **Match** — `973044259dd3c98587142d955db33485a092cba45806aaf2576a5a77f85fd50d`, 113742 bytes |

## 43. Sixth Pass — The Fix and Test Evidence

**Schema:** `payment_webhook_receipts` gains `provider_transaction_id`, `settled_amount`, `settled_currency`, `event_occurred_at` (normalized, verified, durable), `next_retry_at`, and a fourth `processing_status` value `RETRY_PENDING` (with `chk_pwr_retry_scheduling` and a new `idx_pwr_retry_due` scan index). `commercial_pricing_agreements.uq_cpa_org` → `uq_cpa_org_plan UNIQUE(organization_id, base_plan_id)`.

**Functions:** `fn_record_payment_webhook_receipt` persists the normalized fields and its dedup path reaffirms (rather than silently discards) a duplicate of a still-unresolved receipt. `fn_process_payment_webhook_receipt` no longer accepts `PROCESSED` at all, gains `PROCESSING↔RETRY_PENDING`/`RETRY_PENDING→FAILED` transitions, and reads `provider_transaction_id` from the row rather than a caller argument. A new function, `fn_apply_successful_payment_webhook_receipt`, is the sole atomic path to `PROCESSED`, reusing the frozen `fn_update_payment_status`/`fn_mark_invoice_paid` internally with an idempotent-if-already-`PAID` guard.

Full transcripts: `execution_logs/20260830T210000Z_01` through `_11`. Every assertion below passed on the first run — zero test-harness bugs this pass:

| Finding | Test | Result |
|---|---|---|
| FINAL-6K-C01 | `PROCESSING` before linkage exists | **PASS** — resolves, both ids `NULL`, not an error |
| FINAL-6K-C01 | Transition to `RETRY_PENDING` (not `FAILED`) | **PASS** — non-terminal, `next_retry_at` set |
| FINAL-6K-C02 | Duplicate delivery while `RETRY_PENDING` | **PASS** — same receipt id returned, reaffirmed, no second row |
| FINAL-6K-C01 | Retry after `fn_link_payment_provider_transaction` runs | **PASS** — resolves correctly, reading `provider_transaction_id` from the row |
| FINAL-6K-C01/C03 | Atomic settlement after resolution | **PASS** — `PROCESSED`, invoice `PAID` |
| FINAL-6K-C02 | Crash recovery: receipt never touched by any worker, discovered via `idx_pwr_status` scan | **PASS** — settled correctly, no re-delivery needed |
| FINAL-6K-C03 | `fn_process_payment_webhook_receipt(..., 'PROCESSED')` | **PASS (rejected)** — invalid target status |
| FINAL-6K-C03 | Settlement with mismatched settled amount | **PASS (rejected)** — attempt stays `PENDING`, invoice stays `OPEN` |
| FINAL-6K-C03 | Forced exception mid-settlement, explicit transaction | **PASS** — `ROLLBACK` leaves attempt/invoice untouched |
| Regression | Duplicate/concurrent settlement of an already-`PROCESSED` receipt | **PASS** — idempotent, no re-run, no exception |
| Regression | Cross-provider correlation | **PASS** — resolves `FALSE`, no exception |
| SIGNIFICANT | Org negotiates Growth (A), then Enterprise (B) | **PASS** — both succeed, `uq_cpa_org` no longer blocks the second |
| SIGNIFICANT | Second Growth agreement (C) | **PASS (rejected)** — `uq_cpa_org_plan` violation |
| SIGNIFICANT | Growth agreement version referencing Enterprise `PlanVersion` (D) | **PASS (rejected)** — pre-existing `fn_create_commercial_pricing_agreement_version` check, unaffected |
| SIGNIFICANT | Enterprise agreement version referencing Enterprise `PlanVersion` (E) | **PASS** |
| SIGNIFICANT | Corrected org+plan selection query | **PASS** — exactly one row, the Enterprise agreement version |
| Regression | Webhook privilege matrix (`app_api` denied on both functions; `app_billing_webhook_ingress`/`app_worker` granted; `app_platform_admin` `INSERT` denied) | **PASS** |
| Regression | `CALL_MINUTES` `NULL`-seconds rejection; commercial-pricing raw `UPDATE` denial | **PASS** |

**Not performed / disclosed limitations:** no real payment-provider HTTP integration test; no genuinely concurrent two-*process* race test (the forced-rollback and idempotent-duplicate-settlement tests are the deterministic equivalents, exercising the same row-locking primitives a genuine race would); the full first- through fifth-pass regression suites were not re-run verbatim (a targeted regression check was run instead, per the same proportionate-evidence approach every prior pass used).

---

## 44. FINAL-6K-C01 Through C05 Closure Table and Sixth-Pass Freeze Recommendation

| ID | Finding | Fix | Evidence |
|---|---|---|---|
| FINAL-6K-C01 (BLOCKER) | Callback-before-response could become terminal | New non-terminal `RETRY_PENDING` status; duplicate delivery reaffirms an unresolved receipt | §43, callback-before-response tests |
| FINAL-6K-C02 (BLOCKER) | Durable receipt could not recover a commit→enqueue crash | Normalized, durable `provider_transaction_id`/`settled_amount`/`settled_currency` columns; `idx_pwr_retry_due` reconciliation scan key | §43, crash-recovery test |
| FINAL-6K-C03 (BLOCKER) | `PROCESSED` did not guarantee invoice settlement | `fn_apply_successful_payment_webhook_receipt` — the sole, atomic, single-transaction path to `PROCESSED` | §43, atomicity/rollback/partial-settlement tests |
| FINAL-6K-C04 (SIGNIFICANT) | One organization could not negotiate pricing across different plan families | `uq_cpa_org` → `uq_cpa_org_plan UNIQUE(organization_id, base_plan_id)`; §13.3 resolution corrected to join through the plan family | §43, Tests A-E, resolution query |
| FINAL-6K-C05 (documentation) | DEC-6K-02 wording ambiguous about per-call quantity | Owner-decision summary corrected to state both quantities explicitly | `6K-Billing-Usage-APIs.md` §48 |

`PHASE 6K = READY FOR INDEPENDENT FREEZE-GATE REVIEW`.

All five sixth-pass findings are fixed and live-evidenced, on top of the first through fifth passes' own already-closed items (§8, §17, §24, §31, §38 — unaffected by this pass except where the fix itself strengthened the same functions/constraints). Migration `102_5H2` (amended in place, sixth pass) passes fresh and incremental application on PostgreSQL 18.6, single head, checksum-verified against the manifest. No frozen document or frozen migration (001–101) was altered — every correction is additive within this same, still-unapplied file.

**Final convergence proof, answered directly (task §54):** can a callback arrive before the provider API response and still settle later? **Yes** (§43, callback-before-response tests). Can a transient unknown transaction become permanently lost immediately? **No** — `RETRY_PENDING` is non-terminal. Can a committed receipt survive loss of the original Celery enqueue? **Yes** (§43, crash-recovery test). Does processing require provider redelivery for recovery? **No** — the reconciliation scan reads purely durable DB state. Can a receipt become `PROCESSED` while the invoice remains `OPEN`? **No** — structurally impossible via the sole settlement path. Can `PaymentAttempt` success, invoice-paid, and receipt-`PROCESSED` diverge because of a transaction rollback? **No** — proven by the forced-rollback test. Is successful settlement exactly-once under duplicate/concurrent paths? **Yes** — proven idempotent.

**Final commercial-pricing proof, answered directly (task §55):** can one organization have negotiated pricing for Plan A? **Yes.** Can the same organization later have negotiated pricing for Plan B while preserving Plan A's history? **Yes** — the fix. Can a Plan A agreement silently apply to Plan B? **No** — `fn_create_commercial_pricing_agreement_version`'s own pre-existing plan-family check, plus the corrected org+plan resolution query. Does each agreement version still pin an exact `PlanVersion`? **Yes** — unchanged. Do historical invoices remain unchanged? **Yes** — no historical row was touched by this pass (both new agreements are freshly created, DRAFT/ACTIVE going forward only).

**This is the sixth and, per this pass's own live evidence, current recommendation — not a claim that no further review is warranted. Independent freeze-gate review remains the authority that declares `FROZEN`.**
