"""Phase 5K — wraps frozen migration 058_5H.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/058_5H.sql verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen) and adding parallel DDL here would
create a second, competing schema history — see 5K/alembic/README.md.

Revision ID: 058_5H
Revises: '057_5H'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = '058_5H'
down_revision: Union[str, None] = '057_5H'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '058_5H.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 058_5H is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/058_5H.sql). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied."
    )
