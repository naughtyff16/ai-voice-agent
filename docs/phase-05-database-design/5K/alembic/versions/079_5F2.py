"""Phase 5F.2 — wraps controlled amendment migration 079_5F2.sql.

Executes 5K/migrations/079_5F2.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

079_5F2 is a Phase 5L Global Database Reconciliation migration. It
resolves DEP-6F-01 (FR-RAG-004) by adding knowledge.fn_docver_rollback()
— a new SECURITY DEFINER function, no existing object changed. See
5K/migrations/079_5F2.sql for the DDD-grounded interpretation this
function implements.

Revision ID: 079_5F2
Revises: '078_5F1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '079_5F2'
down_revision: Union[str, None] = '078_5F1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '079_5F2.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 079_5F2 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: this revision only adds a new "
        "function, knowledge.fn_docver_rollback() — "
        "DROP FUNCTION knowledge.fn_docver_rollback(UUID, UUID, UUID);)"
    )
