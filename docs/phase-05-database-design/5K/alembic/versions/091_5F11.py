"""Phase 5F.11 — wraps controlled correction migration 091_5F11.sql.

Executes 5K/migrations/091_5F11.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

091_5F11 is a Phase 5L.1 post-reconciliation correction (item #6,
QP-09). Adds a supporting index for the corrected, language-consistent
hybrid keyword retrieval query shape documented in 5F/6F's Phase 5L/5L.1
amendments (no query shape can be enforced by DDL; this migration adds
only the index the corrected two-branch OR query needs).

Revision ID: 091_5F11
Revises: '090_5F10'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '091_5F11'
down_revision: Union[str, None] = '090_5F10'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '091_5F11.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 091_5F11 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: DROP INDEX knowledge.idx_dc_kb_language;)"
    )
