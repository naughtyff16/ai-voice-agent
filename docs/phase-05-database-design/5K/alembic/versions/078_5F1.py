"""Phase 5F.1 — wraps controlled amendment migration 078_5F1.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/078_5F1.sql verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen once merged) and adding parallel DDL
here would create a second, competing schema history — see
5K/alembic/README.md.

078_5F1 is a Phase 5L Global Database Reconciliation migration on top
of the validated 001-077 baseline. It resolves DEP-6F-16 (Phase 6F —
Knowledge/RAG APIs): knowledge.fn_docver_publish() had no guard against
publishing onto an already-DELETED document, and
knowledge.documents.current_version_id (the publication gate) had no
column-level restriction preventing app_api/app_worker from setting it
directly, bypassing fn_docver_publish() entirely. It replaces one
existing function (fn_docver_publish, CREATE OR REPLACE — its signature
and grants are unchanged) and narrows one column-level privilege. No
existing 001-077 object is dropped or renamed.

See 5K/migrations/078_5F1.sql for full rationale.

Revision ID: 078_5F1
Revises: '077_5J1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = '078_5F1'
down_revision: Union[str, None] = '077_5J1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '078_5F1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 078_5F1 is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/078_5F1.sql). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied. "
        "(Operational runbook note, not an Alembic-managed downgrade: "
        "restoring the pre-078 fn_docver_publish body from 034_5F.sql "
        "and re-granting table-level UPDATE on knowledge.documents to "
        "app_api/app_worker would reverse this revision's effects, but "
        "reintroduces the DEP-6F-16 gap this revision closes.)"
    )
