"""Phase 5F.12 — wraps controlled correction migration 092_5F12.sql.

Executes 5K/migrations/092_5F12.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

092_5F12 is a Phase 5L.2 final-freeze-review correction. It tightens
the reindex manifest predicate (fn_kb_reindex_begin/complete,
088_5F8.sql) from `d.status <> 'DELETED'` to `d.status = 'READY'` —
the former incorrectly required ARCHIVED documents (excluded from
retrieval by 6F's ArchivedDocumentNotQueryable policy) to be present in
the rebuild manifest, which would have wrongly blocked completion for a
reindex worker that correctly skipped non-searchable content.

Revision ID: 092_5F12
Revises: '091_5F11'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '092_5F12'
down_revision: Union[str, None] = '091_5F11'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '092_5F12.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 092_5F12 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed."
    )
