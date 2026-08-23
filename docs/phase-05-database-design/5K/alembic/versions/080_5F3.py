"""Phase 5F.3 — wraps controlled amendment migration 080_5F3.sql.

Executes 5K/migrations/080_5F3.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

080_5F3 is a Phase 5L Global Database Reconciliation migration. It
resolves DEP-6F-09 by adding knowledge.fn_docver_mark_failed() — a new
SECURITY DEFINER function, no existing object changed.

Revision ID: 080_5F3
Revises: '079_5F2'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '080_5F3'
down_revision: Union[str, None] = '079_5F2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '080_5F3.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 080_5F3 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: this revision only adds a new "
        "function, knowledge.fn_docver_mark_failed() — "
        "DROP FUNCTION knowledge.fn_docver_mark_failed(UUID, UUID, TEXT);)"
    )
