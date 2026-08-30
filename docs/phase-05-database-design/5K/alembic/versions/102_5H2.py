"""Phase 5H.2 — wraps controlled amendment migration 102_5H2.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/102_5H2.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

102_5H2 is a controlled amendment on top of the validated 001-101
baseline, driven by Phase 6K (Billing + Usage APIs) FINAL Blocker
Remediation. It:

  1. Adds first-class, organization-specific Commercial Pricing
     Agreement persistence (billing.commercial_pricing_agreements /
     ...agreement_versions / ...metrics) — closing the confirmed Phase
     5H schema gap 6K's business requirement (client-specific pricing)
     needs and 5H's own executed DDL never provided. Per DEC-6K-01
     (owner-accepted, FINAL): immutable, versioned agreement terms,
     layered on an exact base billing.plan_versions row.
  2. Pins billing.subscriptions and billing.billing_periods to the
     effective commercial_pricing_agreement_version via a tenant-scoped
     COMPOSITE foreign key (id, organization_id) — not a plain FK on id
     alone — so a cross-tenant pricing relationship is structurally
     impossible to persist, not merely convention-guarded. A dedicated
     trigger additionally enforces that a pinned agreement version's own
     base_plan_version_id always matches the period's plan_version_id.
  3. Adds field-level pricing provenance to billing.invoice_lines
     (unit_price_source, included_quantity_source, a composite-FK'd
     commercial_pricing_agreement_version_id) so a finalized invoice
     line can answer, independently, which source produced its monetary
     rate and which source produced its included-quantity allowance.
  4. Fixes a confirmed, blocking schema defect in the frozen
     billing.payment_attempts table (migration 055_5H.sql): provider_
     transaction_id was NOT NULL, which makes it impossible to insert
     the local payment-attempt row before the payment provider is ever
     called — the platform's own required payment-transaction-boundary
     invariant. DROP NOT NULL (metadata-only, no rewrite); the existing
     uq_pa_provider_tx UNIQUE constraint continues to work correctly
     with multiple NULL values under PostgreSQL's standard NULL-
     distinctness semantics for unique constraints.
  5. Adds billing.payment_webhook_receipts — a durable, atomically-
     deduplicated (INSERT ... ON CONFLICT ... RETURNING, mirroring 6J
     §24.3's own inbound-webhook pattern) receipt table for inbound
     payment-provider webhooks, replacing an UPDATE-based dedup attempt
     against payment_attempts that could not provide the same atomic
     "insert once" guarantee. Adds payment_attempts.payment_method_kind
     (provider-confirmed, never client-authoritative) to back the 6K
     API's own response model.
  6. Adds late-usage adjustment provenance columns to billing.
     billing_adjustments (late_usage_billing_period_id, ...metric,
     ...provenance JSONB) plus a dedicated
     fn_create_late_usage_billing_adjustment() SECURITY DEFINER function
     — per DEC-6K-04 (owner-accepted, FINAL): late-arriving usage after
     invoice finalization is never applied by mutating the finalized
     invoice; it becomes a fully-provenanced next-cycle billing
     adjustment instead, using the ORIGINAL billing period's pinned
     pricing basis, never today's plan/agreement.

Every new SECURITY DEFINER function follows the exact grant pattern
5H's own existing financial functions already use (confirmed by this
same remediation pass's own audit, docs/phase-06-api-design/
6K-Billing-Usage-APIs.md §9.1): app_worker/app_platform_admin EXECUTE
only, REVOKE ALL FROM PUBLIC, explicit SET search_path — never granted
to app_api, with exactly one deliberate exception (item 7 below). No
existing 5H table, column, constraint, index, function, or grant from
migrations 001-101 is altered — every correction to a frozen grant is a
REVOKE statement issued by this later, still-unapplied migration
(087_5B1/096_5B2/101_5I1's own established pattern), never an edit to
the original file.

SECOND PASS (2026-08-30, same day) — amended in place, same policy as
086_5H1/101_5I1 (confirmed before this pass began: this file's only
prior applications were against genuinely disposable, already-deleted
local PostgreSQL 18.6 validation instances, never a persistent
database). An independent freeze-gate review found 5 BLOCKERS and 1
SIGNIFICANT issue the first pass missed — full narrative in the SQL
file's own header comment and in
docs/phase-05-database-design/5K/validation/
6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md:

  7. commercial_pricing_agreements/...agreement_versions/...metrics
     lose ALL non-SELECT grants for every role including
     app_platform_admin (FB-6K-01/02) — SECURITY DEFINER functions
     never needed the caller's own table grants, so items 1's four
     lifecycle functions are unaffected; only the raw-DML bypass class
     is closed.
  8. billing.payment_webhook_receipts loses app_api's SELECT and INSERT
     (FB-6K-03/04); a new, narrow fn_record_payment_webhook_receipt()
     — the one function in this migration granted to app_api — replaces
     the raw INSERT path, accepting only the three ingress-safe fields.
  9. billing.payment_attempts (055_5H.sql, frozen, unedited) loses
     app_api's INSERT (FB-6K-05); a new fn_create_payment_attempt() —
     the first app_api-callable billing SECURITY DEFINER function in
     this schema — derives every financial value server-side and binds
     tenant context via organization.current_tenant_id() with no
     p_organization_id parameter to forge.
  10. fn_process_payment_webhook_receipt's signature changes: it no
      longer accepts p_payment_attempt_id/p_organization_id as direct
      input (the significant, non-FB-numbered finding) — it now takes
      p_provider_transaction_id and internally resolves + cross-
      validates the linkage against the platform's own data.
  11. billing.usage_events gains source_quantity_seconds (FB-6K-06) —
      exact pre-conversion seconds preserved for lossless CALL_MINUTES
      aggregation; per-call rounding before summation is confirmed
      mathematically non-equivalent to DEC-6K-02's own exact-seconds
      mandate once many calls are aggregated.
  12. Broader least-privilege audit: app_api's unnecessary INSERT on
      usage_events/cost_entries/invoice_lines/tax_lines revoked;
      app_worker's INSERT on credits/credit_ledger_entries revoked
      (reconciling the executed grants with 5H's own already-stated
      §20 security-model intent); app_api's INSERT on refunds revoked
      (contradicted 6K's own "no tenant-facing refund creation" design).

THIRD PASS (2026-08-30, same day) — amended in place a third time, same
policy, confirmed again before this pass began. A further independent
freeze-gate review found two remaining issues:

  13. FINAL-6K-01 (BLOCKER): fn_record_payment_webhook_receipt() (added
      by the second pass) was still granted EXECUTE to app_api — the
      general tenant-facing runtime role could still call it and pre-
      claim/poison a real provider event ID. Fixed: a new, minimal role,
      app_billing_webhook_ingress (LOGIN, NOT BYPASSRLS, no table DML,
      USAGE on schema billing + EXECUTE on exactly this one function),
      mirroring the existing voice.app_voice_reconciler precedent
      (099_5C1.sql) exactly — neither app_api, app_worker, nor
      app_platform_admin retains EXECUTE.
  14. FINAL-6K-02 (SIGNIFICANT): usage_events.chk_ue_source_quantity_
      seconds only enforced non-negativity, never that a CALL_MINUTES
      row actually carries a non-NULL source_quantity_seconds. Fixed:
      the CHECK now also requires metric <> 'CALL_MINUTES' OR
      source_quantity_seconds IS NOT NULL, added at full validation
      strength (no historical rows exist for this never-applied
      migration's own new column).

FOURTH PASS (2026-08-30, same day) — amended in place a fourth time, same
policy, confirmed again before this pass began. A further independent
freeze-gate review found one remaining schema/grant issue plus a
documentation-consistency issue:

  15. FREEZE-6K-01 (BLOCKER): billing.payment_webhook_receipts still
      granted app_platform_admin full SELECT/INSERT/UPDATE/DELETE
      directly on the table — even with EXECUTE on the ingress function
      closed (item 13), a platform-admin session could bypass it
      entirely via a raw table write, pre-claiming/poisoning a real
      provider event ID or rewriting/deleting receipt rows outright.
      Fixed: INSERT/UPDATE/DELETE revoked from app_platform_admin;
      SELECT retained (narrow, read-only support/incident-response
      allowance). No role holds DELETE on this table at all.
  16. FREEZE-6K-02 (BLOCKER, documentation only, no SQL change): the
      authoritative 6K-Billing-Usage-APIs.md still normatively described
      fn_record_payment_webhook_receipt as app_api-reachable/callable in
      its own ADR-6K-15 and one live-validation-table row, stale
      relative to item 13's own fix. Corrected in the document; no
      migration content change.

Revision ID: 102_5H2
Revises: '101_5I1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '102_5H2'
down_revision: Union[str, None] = '101_5I1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '102_5H2.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 102_5H2 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal, in dependency order: ALTER TABLE "
        "billing.usage_events DROP CONSTRAINT chk_ue_source_quantity_seconds "
        "(re-add the original non-negative-only version if truly reverting "
        "-- not recommended, re-opens FINAL-6K-02); GRANT INSERT, UPDATE, "
        "DELETE ON billing.payment_webhook_receipts TO app_platform_admin "
        "if truly reverting (re-opens FREEZE-6K-01 -- not recommended); "
        "REVOKE EXECUTE ON "
        "FUNCTION billing.fn_record_payment_webhook_receipt(TEXT, TEXT, CHAR) "
        "FROM app_billing_webhook_ingress; DROP ROLE app_billing_webhook_"
        "ingress (only if no other object references it); GRANT back the "
        "REVOKEd frozen-file grants (payment_attempts/usage_events/"
        "cost_entries/invoice_lines/tax_lines/credits/credit_ledger_entries/"
        "refunds INSERT, per the SQL file's own Part G) if truly reverting; "
        "ALTER TABLE billing.usage_events DROP CONSTRAINT "
        "chk_ue_source_quantity_seconds, DROP COLUMN "
        "source_quantity_seconds; DROP FUNCTION "
        "billing.fn_create_payment_attempt(UUID, TEXT); DROP FUNCTION "
        "billing.fn_record_payment_webhook_receipt(TEXT, TEXT, CHAR); "
        "GRANT back commercial_pricing_agreements/...agreement_versions/"
        "...metrics INSERT/UPDATE/DELETE to app_platform_admin if truly "
        "reverting (re-opens FB-6K-01/02 — not recommended); DROP FUNCTION "
        "billing.fn_create_late_usage_billing_adjustment(UUID, UUID, TEXT, "
        "NUMERIC, CHAR, TEXT, UUID, TEXT, JSONB); ALTER TABLE "
        "billing.billing_adjustments DROP COLUMN late_usage_provenance, "
        "DROP COLUMN late_usage_metric, DROP COLUMN "
        "late_usage_billing_period_id; DROP FUNCTION "
        "billing.fn_process_payment_webhook_receipt(UUID, TEXT, TEXT, "
        "TEXT); DROP TABLE billing.payment_webhook_receipts; ALTER TABLE "
        "billing.payment_attempts DROP CONSTRAINT chk_pa_method_kind, DROP "
        "COLUMN payment_method_kind; ALTER TABLE billing.payment_attempts "
        "ALTER COLUMN provider_transaction_id SET NOT NULL (only safe if "
        "no NULL rows exist); ALTER TABLE billing.invoice_lines DROP "
        "CONSTRAINT fk_il_cpav, DROP CONSTRAINT chk_il_pricing_provenance, "
        "DROP CONSTRAINT chk_il_included_qty_source, DROP CONSTRAINT "
        "chk_il_unit_price_source, DROP COLUMN "
        "commercial_pricing_agreement_version_id, DROP COLUMN "
        "included_quantity_source, DROP COLUMN unit_price_source; DROP "
        "TRIGGER trg_sub_agreement_plan_consistency ON billing.subscriptions; "
        "DROP TRIGGER trg_bp_agreement_plan_consistency ON "
        "billing.billing_periods; DROP FUNCTION "
        "billing.fn_bp_agreement_plan_consistency(); ALTER TABLE "
        "billing.billing_periods DROP CONSTRAINT fk_bp_cpav, DROP COLUMN "
        "commercial_pricing_agreement_version_id; ALTER TABLE "
        "billing.subscriptions DROP CONSTRAINT fk_sub_cpav, DROP COLUMN "
        "commercial_pricing_agreement_version_id; DROP FUNCTION "
        "billing.fn_expire_commercial_pricing_agreement_version(UUID, UUID, "
        "TEXT); DROP FUNCTION "
        "billing.fn_activate_commercial_pricing_agreement_version(UUID, "
        "UUID); DROP FUNCTION "
        "billing.fn_create_commercial_pricing_agreement_version(UUID, UUID, "
        "UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, TEXT, "
        "JSONB); DROP FUNCTION "
        "billing.fn_create_commercial_pricing_agreement(UUID, UUID, TEXT, "
        "TEXT); DROP TABLE billing.commercial_pricing_metrics; DROP TABLE "
        "billing.commercial_pricing_agreement_versions; DROP TABLE "
        "billing.commercial_pricing_agreements — but this reintroduces "
        "every gap this revision closes.)"
    )
