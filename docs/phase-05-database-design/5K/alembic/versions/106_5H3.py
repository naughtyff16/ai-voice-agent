"""Phase 5H.3 -- wraps controlled amendment migration 106_5H3.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/106_5H3.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

106_5H3 is a controlled, additive amendment on top of the validated
001-105 baseline, driven by Phase 6M (Admin/Platform Control-Plane API
design). It makes three changes, none of which edits 001-104 or
105_5B4's own text:

(0) CRITICAL SECURITY FIX. 6M's live adversarial validation on
    phase6m-pg18-incr discovered that 001_5B.sql's
    organization.is_platform_admin() -- `current_setting('app.is_platform
    _admin', true) = 'true'` -- returns SQL NULL, not FALSE, when that
    custom GUC has never been SET/RESET at all in the session, because
    current_setting(name, missing_ok=>true) returns NULL for an untouched
    custom GUC. Every guard of the shape `IF NOT organization.is_platform
    _admin() THEN RAISE EXCEPTION ...; END IF;` (used throughout
    087_5B1.sql, 105_5B4.sql, and this file) treats that NULL condition
    as FALSE and skips its own RAISE, so the privileged body runs anyway
    -- confirmed live: a brand-new connection that never touches
    app.is_platform_admin can call fn_platform_suspend_organization(...)
    and it succeeds instead of raising "caller is not authorized." This
    is a pre-existing Phase 5B defect, not something 105_5B4/106_5H3
    introduced, but 001_5B.sql is frozen, so the fix is a CREATE OR
    REPLACE of the same function here -- overriding 001_5B.sql's
    definition for every caller (including 087_5B1's frozen functions and
    the break_glass_grants RLS policy) without touching or re-checksumming
    001_5B.sql. The new body wraps the comparison in COALESCE so a
    never-set GUC evaluates to a proper, non-NULL FALSE.

(1) and (2) below are unchanged from the original two additive changes
    to already-frozen billing persistence (052_5H.sql, 055_5H.sql):

(1) Quota override lifecycle. 052_5H.sql's billing.quota_configs has
    soft_limit/hard_limit/override_reason but no effective-dating or
    attribution columns, so a persisted override could not answer "as of
    when" or "set by whom." This revision adds effective_from,
    expires_at (nullable, computed-at-read-time semantics matching
    break_glass_grants/contact_suppressions), and updated_by, plus
    fn_platform_set_quota_override -- a guarded SECURITY DEFINER upsert
    enforcing the 5H SS11.1 usage-dimension allow-list (the 14-value
    metric vocabulary already governing usage_events.metric) rather than
    a new table CHECK constraint, matching that vocabulary's own
    documented app-layer-validated extensibility design. The upsert
    relies on the existing uq_qc_org_metric unique constraint's atomic
    ON CONFLICT DO UPDATE for concurrency safety -- no extra locking.

(2) Guarded refund saga. 055_5H.sql's fn_validate_refund_amount trigger
    performs an unlocked SELECT SUM(...) check, which admits a real
    double-refund race between two concurrent INSERTs against the same
    payment_attempt_id. This revision does not touch that trigger;
    instead it adds a three-phase guarded path -- fn_platform_reserve_
    refund (takes a function-internal SELECT ... FOR UPDATE lock on the
    specific payment_attempts row, the same single-row-transition-safety
    pattern 087_5B1's fn_break_glass_release and 105_5B4's fn_platform_
    suspend_organization already establish, re-checks the refundable
    balance under that lock, and inserts a PENDING billing.refunds row),
    fn_platform_settle_refund, and fn_platform_fail_refund (idempotent
    terminal-state transitions, keyed by provider_refund_id / a bounded
    failure reason). The saga's reserve phase commits and returns before
    any external payment-provider call is made, and settle/fail run in
    an entirely separate transaction after that call -- no DB transaction
    is ever held open across the network call (6A). billing.refunds.
    provider_refund_id (NOT NULL in 055_5H.sql) is relaxed to nullable
    because the provider has not assigned one at reserve time, with a
    new CHECK requiring it once status = SUCCEEDED.

Both additions close schema/security gaps 6M identified rather than
inventing new domain behavior: this revision also REVOKEs
app_platform_admin's raw INSERT/UPDATE/DELETE on billing.quota_configs,
billing.refunds, and billing.payment_attempts (granted in 052_5H.sql /
055_5H.sql, left unedited) -- direct implementation of the 6M "Platform
Admin is not a database superuser" invariant at the DB privilege layer.
app_api's and app_worker's own existing grants on these tables are
untouched.

Full rationale in the SQL file's own header comment and in
docs/phase-06-api-design/6M-Admin-Platform-APIs.md.

Revision ID: 106_5H3
Revises: '105_5B4'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '106_5H3'
down_revision: Union[str, None] = '105_5B4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '106_5H3.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 106_5H3 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal, in order: GRANT INSERT, UPDATE, "
        "DELETE ON billing.payment_attempts, billing.refunds, billing."
        "quota_configs TO app_platform_admin; DROP FUNCTION IF EXISTS "
        "billing.fn_platform_fail_refund(UUID, UUID, TEXT); DROP FUNCTION "
        "IF EXISTS billing.fn_platform_settle_refund(UUID, UUID, TEXT); "
        "DROP FUNCTION IF EXISTS billing.fn_platform_reserve_refund(UUID, "
        "UUID, UUID, NUMERIC, CHAR(3), TEXT); ALTER TABLE billing.refunds "
        "DROP CONSTRAINT chk_ref_failure_reason_len, DROP CONSTRAINT chk_ref_"
        "provider_refund_id_when_succeeded, DROP COLUMN failure_reason; "
        "ALTER TABLE billing.refunds ALTER COLUMN provider_refund_id SET "
        "NOT NULL -- only safe if no PENDING row with a NULL provider_"
        "refund_id exists; DROP FUNCTION IF EXISTS billing.fn_platform_"
        "set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, "
        "TIMESTAMPTZ, TEXT); ALTER TABLE billing.quota_configs DROP CONSTRAINT "
        "chk_qc_expires_after_effective, DROP COLUMN updated_by, DROP "
        "COLUMN expires_at, DROP COLUMN effective_from -- but this "
        "reopens the fn_validate_refund_amount double-refund race and "
        "removes the only guarded platform-admin quota-override path; "
        "not recommended outside of restoring a pre-106 backup.)"
    )
