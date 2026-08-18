"""Phase 5K — wraps frozen migration 032_5E.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/032_5E.sql verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen) and adding parallel DDL here would
create a second, competing schema history — see 5K/alembic/README.md.

Revision ID: 032_5E
Revises: '031_5E'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = '032_5E'
down_revision: Union[str, None] = '031_5E'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '032_5E.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 032_5E is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/032_5E.sql). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied."
    )
