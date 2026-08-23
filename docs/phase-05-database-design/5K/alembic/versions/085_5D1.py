"""Phase 5D.1 — wraps controlled amendment migration 085_5D1.sql.

Executes 5K/migrations/085_5D1.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

085_5D1 is a Phase 5L Global Database Reconciliation migration. It adds
a DB-level partial unique index (uq_sup_active, NULLS NOT DISTINCT) on
crm.contact_suppressions closing the concurrent-duplicate-ACTIVE-
suppression race the 5D design doc itself carried forward.

Revision ID: 085_5D1
Revises: '084_5F7'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '085_5D1'
down_revision: Union[str, None] = '084_5F7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '085_5D1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 085_5D1 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: DROP INDEX crm.uq_sup_active;)"
    )
