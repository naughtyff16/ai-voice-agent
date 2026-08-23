"""Phase 5H.1 — wraps controlled amendment migration 086_5H1.sql.

Executes 5K/migrations/086_5H1.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

086_5H1 is a Phase 5L Global Database Reconciliation migration. It adds
billing.fn_create_billing_adjustment() (SECURITY DEFINER) and revokes
app_worker's direct INSERT on billing.billing_adjustments, per 5H's own
recommended-but-unbuilt financial-control-parity hardening.

Revision ID: 086_5H1
Revises: '085_5D1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '086_5H1'
down_revision: Union[str, None] = '085_5D1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '086_5H1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 086_5H1 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: GRANT INSERT ON billing.billing_adjustments "
        "TO app_worker; DROP FUNCTION billing.fn_create_billing_adjustment"
        "(UUID, UUID, TEXT, TEXT, NUMERIC, CHAR, TEXT); — but this "
        "reintroduces the direct-INSERT financial-control gap this "
        "revision closes.)"
    )
