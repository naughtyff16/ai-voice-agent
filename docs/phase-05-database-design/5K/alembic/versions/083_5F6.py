"""Phase 5F.6 — wraps controlled amendment migration 083_5F6.sql.

Executes 5K/migrations/083_5F6.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

083_5F6 is a Phase 5L Global Database Reconciliation migration. It
resolves DEP-6F-02 (real reindex) by adding
document_chunks.index_generation, widening uq_chunk_position to include
it, and adding four SECURITY DEFINER functions
(fn_kb_reindex_begin/complete/fail/cleanup_old_generations).

Revision ID: 083_5F6
Revises: '082_5F5'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '083_5F6'
down_revision: Union[str, None] = '082_5F5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '083_5F6.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 083_5F6 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed."
    )
