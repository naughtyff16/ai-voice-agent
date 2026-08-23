"""Phase 5B.1 — wraps controlled amendment migration 087_5B1.sql.

Executes 5K/migrations/087_5B1.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

087_5B1 is a Phase 5L Global Database Reconciliation migration. It
resolves DEP-6B-01 by adding organization.break_glass_grants (durable
break-glass grant-lifecycle persistence) plus fn_break_glass_grant() /
fn_break_glass_release() (both SECURITY DEFINER), an immutable-fields
trigger, and platform-admin-only RLS. No existing object is changed.

Revision ID: 087_5B1
Revises: '086_5H1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '087_5B1'
down_revision: Union[str, None] = '086_5H1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '087_5B1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 087_5B1 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal if no rows have been written yet: "
        "DROP TABLE organization.break_glass_grants CASCADE; "
        "DROP FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT), "
        "organization.fn_break_glass_release(UUID, UUID), "
        "organization.prevent_bgg_immutable_field_mutation();)"
    )
