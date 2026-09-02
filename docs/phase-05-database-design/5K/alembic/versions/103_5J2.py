"""Phase 5J.2 -- wraps controlled amendment migration 103_5J2.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/103_5J2.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

103_5J2 is a controlled, additive amendment on top of the validated
001-102 baseline (102_5H2 unedited, SHA-256 unchanged), driven by
Phase 6L (Analytics + Audit APIs) Schema Gap Analysis
(SCHEMA-GAP-6L-01). It adds FX-normalization column sets --
{amount in a single common currency, fx_rate_used, fx_rate_source,
fx_rate_captured_at} -- to analytics.roi_by_campaign and
analytics.billing_revenue_monthly, mirroring the pattern
billing.cost_entries (5H Section 7, migration 051_5H.sql) already
established for the identical provider-cost-vs-tenant-currency
problem. Full rationale, the exact frozen-source contradiction being
closed (4I Section 11.3/17.4, 6K INV-6K-14/Section 32), and the NOT
VALID constraint-validation strategy are documented in the SQL file's
own header comment and in
docs/phase-06-api-design/6L-Analytics-Audit-APIs.md Section 53-55.

VALIDATION STATUS (recorded here per 5K's own established pattern of
stating exactly what was and was not run against a live database):
this revision has NOT been applied to a live PostgreSQL 18 instance.
A local PostgreSQL 18.6 server was present in the authoring session but
required a password that session did not have, and this migration
package does not attempt to alter that server's authentication
configuration to obtain one. No fabricated validation evidence is
recorded anywhere in this package for this revision -- see 6L Section
55 for what a live validation pass must still confirm before this file
is applied to any environment (fresh 001->103 chain, incremental
102_5H2->103_5J2, exactly one Alembic head, and the tenant-isolation /
gross-margin-column-invisibility checks 6L Section 73 specifies).

Revision ID: 103_5J2
Revises: '102_5H2'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '103_5J2'
down_revision: Union[str, None] = '102_5H2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '103_5J2.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 103_5J2 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal, in dependency order: ALTER TABLE "
        "analytics.billing_revenue_monthly DROP CONSTRAINT "
        "chk_brm_margin_pct_requires_amount, DROP CONSTRAINT "
        "chk_brm_margin_requires_normalization, DROP COLUMN "
        "gross_margin_pct, DROP COLUMN gross_margin_amount, DROP COLUMN "
        "provider_cost_fx_rate_captured_at, DROP COLUMN "
        "provider_cost_fx_rate_source, DROP COLUMN "
        "provider_cost_fx_rate_used, DROP COLUMN "
        "provider_cost_amount_org_currency; ALTER TABLE "
        "analytics.roi_by_campaign DROP CONSTRAINT "
        "chk_rbc_roi_requires_normalization, DROP CONSTRAINT "
        "chk_rbc_revenue_normalization_present, DROP CONSTRAINT "
        "chk_rbc_cost_normalization_present, DROP CONSTRAINT "
        "chk_rbc_org_currency_code, DROP COLUMN "
        "estimated_revenue_fx_rate_captured_at, DROP COLUMN "
        "estimated_revenue_fx_rate_source, DROP COLUMN "
        "estimated_revenue_fx_rate_used, DROP COLUMN "
        "estimated_revenue_amount_org_currency, DROP COLUMN "
        "total_cost_fx_rate_captured_at, DROP COLUMN "
        "total_cost_fx_rate_source, DROP COLUMN total_cost_fx_rate_used, "
        "DROP COLUMN total_cost_amount_org_currency, DROP COLUMN "
        "org_currency -- but this reintroduces SCHEMA-GAP-6L-01, the "
        "cross-currency ROI/margin defect this revision closes; not "
        "recommended.)"
    )
