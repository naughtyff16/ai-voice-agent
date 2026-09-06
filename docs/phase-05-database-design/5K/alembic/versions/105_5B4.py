"""Phase 5B.4 -- wraps controlled amendment migration 105_5B4.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/105_5B4.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

105_5B4 is a controlled, additive amendment on top of the validated
001-104 baseline, driven by Phase 6M (Admin/Platform Control-Plane API
design) and the cross-phase controlled reconciliation of DEP-6B-01. It
makes two independent, additive changes to already-frozen persistence
(087_5B1.sql, 003_5B.sql), neither of which edits 001-104:

(1) Break-glass purpose authorization. 087_5B1's durable
    organization.break_glass_grants table establishes grant lifecycle
    (issue / active / expire / release) but has no way to express *what*
    a grant authorizes -- so a valid, unexpired, unreleased grant alone
    was sufficient to pass every check in fn_break_glass_check, which
    would let a generic support grant serve cross-tenant recording
    playback / transcript content. This revision adds an allow-listed,
    immutable-after-creation purposes TEXT[] column (candidate shape B
    from the 6M cross-phase reconciliation, chosen over a single
    purpose_code or a normalized grant-purpose relation as the smallest
    safe representation), a trigger extension that folds purposes into
    the existing immutability guard, and a new required p_required_purpose
    parameter threaded through fn_break_glass_grant and fn_break_glass_check
    so that generic break-glass validity is necessary but never sufficient
    for sensitive-media access (6M Block 1 SS10-11). Forbidden wildcard
    values ('*', 'ALL', 'ALL_ACCESS', 'SUPER_ADMIN') are rejected by a
    CHECK constraint, not just by convention.

(2) Guarded platform-admin organization suspend/reactivate.
    003_5B.sql's organization.organizations has an ACTIVE/SUSPENDED/
    CANCELLED status machine, but before this revision no guarded
    SECURITY DEFINER function existed for a platform admin to drive it
    -- 6C's OWNER self-service suspend uses a raw conditional UPDATE
    (ADR-6C-02's atomic CAS pattern), which is a different actor and a
    different guard shape. fn_platform_suspend_organization and
    fn_platform_reactivate_organization add that guarded lifecycle path:
    is_platform_admin() check, bounded mandatory reason, idempotent
    no-op on the already-target state, and a hard rejection of any
    transition out of the terminal CANCELLED state. Both take a
    function-internal SELECT ... FOR UPDATE on the specific organization
    row (the same single-row-transition-safety pattern 087_5B1's
    fn_break_glass_release already established) -- not API-layer locking.

Both additions close a live schema/security gap 6M identified rather
than inventing new domain behavior: this revision also REVOKEs
app_platform_admin's raw INSERT/UPDATE/DELETE on organization.organizations
(granted in 008_5B.sql, left unedited), so lifecycle mutation is only
reachable through the new guarded functions -- direct implementation of
the 6M "Platform Admin is not a database superuser" invariant at the DB
privilege layer, not just as a documentation assertion.

Full rationale in the SQL file's own header comment and in
docs/phase-06-api-design/6M-Admin-Platform-APIs.md.

Revision ID: 105_5B4
Revises: '104_5B3'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '105_5B4'
down_revision: Union[str, None] = '104_5B3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '105_5B4.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 105_5B4 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal, in order: GRANT INSERT, UPDATE, "
        "DELETE ON organization.organizations TO app_platform_admin; "
        "DROP FUNCTION IF EXISTS organization.fn_platform_reactivate_"
        "organization(UUID, UUID, TEXT); DROP FUNCTION IF EXISTS "
        "organization.fn_platform_suspend_organization(UUID, UUID, TEXT); "
        "DROP FUNCTION IF EXISTS organization.fn_break_glass_check(UUID, "
        "UUID, UUID, TEXT, TEXT); restore fn_break_glass_grant to its "
        "087_5B1.sql 5-argument form; ALTER TABLE organization.break_glass_"
        "grants DROP CONSTRAINT chk_bgg_purposes_no_wildcard, DROP "
        "CONSTRAINT chk_bgg_purposes_allowed, DROP CONSTRAINT chk_bgg_"
        "purposes_nonempty, DROP COLUMN purposes -- but this reopens the "
        "6M SS10-11 blocker (generic break-glass alone would again be "
        "sufficient for sensitive-media access) and removes the only "
        "guarded platform-admin org lifecycle path; not recommended "
        "outside of restoring a pre-105 backup.)"
    )
