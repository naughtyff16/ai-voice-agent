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
to app_api. No existing 5H table, column, constraint, index, function,
or grant from migrations 001-101 is altered, except the two documented,
additive ALTER TABLE statements in item 4 above (DROP NOT NULL, ADD
COLUMN) — nothing is edited "in place" the way 086_5H1/101_5I1's own
amendment history did with not-yet-applied content; 001-101 are treated
as frozen and applied, per this remediation pass's own explicit
instruction.

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
        "(Low-risk manual reversal, in dependency order: DROP FUNCTION "
        "billing.fn_create_late_usage_billing_adjustment(UUID, UUID, TEXT, "
        "NUMERIC, CHAR, TEXT, UUID, TEXT, JSONB); ALTER TABLE "
        "billing.billing_adjustments DROP COLUMN late_usage_provenance, "
        "DROP COLUMN late_usage_metric, DROP COLUMN "
        "late_usage_billing_period_id; DROP FUNCTION "
        "billing.fn_process_payment_webhook_receipt(UUID, TEXT, UUID, UUID, "
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
