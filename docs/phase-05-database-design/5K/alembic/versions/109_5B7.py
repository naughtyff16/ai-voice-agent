"""Phase 5B.7 -- wraps Phase 6M Admin Platform API DB-layer closure
migration 109_5B7.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/109_5B7.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

109_5B7 is the final migration of the Phase 6M closure pass. It adds
14 new SECURITY DEFINER guarded-command wrapper functions (Platform
Admin manual credit, billing adjustment, Plan/PlanVersion/PlanPrice
catalog commands including plan deactivation, Commercial Pricing
Agreement lifecycle wrappers, Tax category/rule commands, and a
guarded forced-session-revocation command), 3 new column-restricted
safe identity views
(identity.v_platform_safe_users/sessions/api_keys), and narrows
app_platform_admin's direct table/function grants that those new
guarded paths now supersede: billing.credits, billing.
credit_ledger_entries, billing.billing_adjustments, billing.plans,
billing.plan_versions, billing.plan_prices, billing.tax_categories,
billing.tax_rules, identity.users, identity.sessions, identity.
api_keys (full REVOKE ALL, replaced by SELECT on the 3 new views), and
webhooks.webhook_deliveries plus all of its existing child partitions
(REVOKE INSERT/UPDATE/DELETE only, SELECT retained -- same pg_inherits-
walking pattern as 108_5B6.sql's fix for voice.transcript_segments,
reused here verbatim with no column restriction since webhook delivery
metadata carries no equivalent sensitive-content column).

billing.billing_accounts and billing.invoices are explicitly untouched
by this migration -- ADR-5H-006 concluded no runtime-principal
hardening is needed there. app_worker's own direct grants on every
table/function touched above are left unaffected throughout; only
app_platform_admin's over-broad direct grants are narrowed.

Every new function follows the exact template already established by
107_5B5.sql's fn_break_glass_grant/fn_break_glass_release and
fn_platform_set_quota_override: re-verify
organization.is_platform_admin() as the first statement, validate
input against the real schema, derive the audit actor/created_by_ref
server-side rather than trusting a client-supplied value, and write an
immutable audit.audit_events row via audit.fn_insert_audit_event() in
the same local transaction as the mutation, before REVOKE ALL FROM
PUBLIC / REVOKE EXECUTE FROM app_api / GRANT EXECUTE TO
app_platform_admin only.

This is the final migration of the Phase 6M closure pass -- no
subsequent revision is authored to repair this file; any defect found
during validation is fixed in place here before freeze.

Revision ID: 109_5B7
Revises: 108_5B6
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '109_5B7'
down_revision: Union[str, None] = '108_5B6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '109_5B7.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 109_5B7 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Manual reversal would require: dropping the 14 new "
        "fn_platform_* guarded functions and identity."
        "fn_platform_revoke_all_sessions; dropping the 3 new views "
        "identity.v_platform_safe_users/v_platform_safe_sessions/"
        "v_platform_safe_api_keys; and re-issuing GRANT INSERT, UPDATE, "
        "DELETE (as applicable) TO app_platform_admin on billing.credits, "
        "billing.credit_ledger_entries, billing.billing_adjustments, "
        "billing.plans, billing.plan_versions, billing.plan_prices, "
        "billing.tax_categories, billing.tax_rules, and GRANT SELECT, "
        "INSERT, UPDATE, DELETE TO app_platform_admin on identity.users, "
        "identity.sessions, identity.api_keys, plus re-issuing GRANT "
        "INSERT, UPDATE, DELETE TO app_platform_admin on webhooks."
        "webhook_deliveries and each of its existing child partitions, "
        "and re-issuing GRANT EXECUTE TO app_platform_admin on the six "
        "raw functions this migration narrowed (billing."
        "fn_billing_apply_credit, billing.fn_create_billing_adjustment, "
        "billing.fn_create_commercial_pricing_agreement[_version], "
        "billing.fn_activate_commercial_pricing_agreement_version, "
        "billing.fn_expire_commercial_pricing_agreement_version) -- this "
        "recreates every over-broad Platform Admin grant Phase 6M's "
        "closure pass exists to remove, and is NOT recommended outside "
        "of restoring a pre-109 backup.)"
    )
