"""Phase 5F.7 — wraps controlled amendment migration 084_5F7.sql.

Executes 5K/migrations/084_5F7.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

084_5F7 is a Phase 5L Global Database Reconciliation migration. It adds
documents.content_language / document_chunks.content_language and
replaces knowledge.update_chunk_tsvector() (CREATE OR REPLACE, same
trigger binding) with a language-aware version, resolving the
multilingual full-text-search carry-forward (5F §19) ahead of 6F's
hybrid-retrieval contract.

Revision ID: 084_5F7
Revises: '083_5F6'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '084_5F7'
down_revision: Union[str, None] = '083_5F6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '084_5F7.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 084_5F7 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed."
    )
