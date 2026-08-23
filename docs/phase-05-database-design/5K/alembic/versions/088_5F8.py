"""Phase 5F.8 — wraps controlled correction migration 088_5F8.sql.

Executes 5K/migrations/088_5F8.sql verbatim (see 078_5F1.py's header for
the shared wrapper convention this revision follows).

088_5F8 is a Phase 5L.1 post-reconciliation correction. It fixes two
independent-review findings against migration 083_5F6.sql:
fn_kb_reindex_fail() had no proof that its p_failed_generation argument
was actually the pending build generation (could delete a serving or
historical generation); fn_kb_reindex_complete() only proved "at least
one chunk exists" for the new generation, not that the rebuild was
actually complete. Adds knowledge.kb_reindex_jobs and
knowledge.kb_reindex_job_manifest (new tables) and CREATE OR REPLACEs
fn_kb_reindex_begin/complete/fail to use them.

Revision ID: 088_5F8
Revises: '087_5B1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '088_5F8'
down_revision: Union[str, None] = '087_5B1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '088_5F8.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 088_5F8 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed."
    )
