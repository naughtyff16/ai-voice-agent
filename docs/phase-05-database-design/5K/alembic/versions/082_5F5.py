"""Phase 5F.5 — wraps controlled amendment migration 082_5F5.sql.

Executes 5K/migrations/082_5F5.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

082_5F5 is a Phase 5L Global Database Reconciliation migration. It
resolves DEP-6F-14 (KB-wide content dedup) by adding
document_versions.knowledge_base_id (server-derived, backfilled, FK-
enforced) and replacing uq_dv_content_hash (document_id, content_hash)
with uq_dv_content_hash_kb (knowledge_base_id, content_hash). Includes
a preflight duplicate-check DO block that raises rather than silently
resolving any pre-existing violation.

Revision ID: 082_5F5
Revises: '081_5F4'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '082_5F5'
down_revision: Union[str, None] = '081_5F4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '082_5F5.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 082_5F5 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. This "
        "revision adds a NOT NULL column with a FK and replaces a unique "
        "index — a manual reversal is nontrivial (would need to restore "
        "the old document-scoped uq_dv_content_hash and drop the new "
        "column/FK/trigger) and is not attempted here."
    )
