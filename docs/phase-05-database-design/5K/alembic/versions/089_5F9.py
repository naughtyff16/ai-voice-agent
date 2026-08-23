"""Phase 5F.9 — wraps controlled correction migration 089_5F9.sql.

Executes 5K/migrations/089_5F9.sql verbatim (see 078_5F1.py's header for
the shared wrapper convention this revision follows).

089_5F9 is a Phase 5L.1 post-reconciliation correction. It fixes the
cross-feature gap between fn_docver_rollback() (079_5F2.sql) and
fn_kb_reindex_cleanup_old_generations() (083_5F6.sql): unconditional
old-generation cleanup could delete the sole surviving chunk copy of a
still-rollback-eligible (SUPERSEDED) document version, making a
subsequent rollback succeed at the SQL layer while leaving zero
searchable content. CREATE OR REPLACEs fn_kb_reindex_cleanup_old_generations
with a per-version-scoped deletion predicate and adds a supporting index.

Revision ID: 089_5F9
Revises: '088_5F8'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '089_5F9'
down_revision: Union[str, None] = '088_5F8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '089_5F9.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 089_5F9 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed."
    )
