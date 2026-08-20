"""Phase 5K.1 — wraps frozen corrective migration 076_5K1.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/076_5K1.sql verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen) and adding parallel DDL here would
create a second, competing schema history — see 5K/alembic/README.md.

076_5K1 is a corrective patch on top of the validated 001-075 Phase 5K
baseline. It fixes two confirmed BLOCKING defects discovered during
Phase 5K final validation:
  1. SECURITY DEFINER search_path dependencies (5 functions missing
     `public` in their search_path, needed for public.gen_uuid_v7()/
     pgcrypto's public.gen_random_bytes()).
  2. workflow.workflow_executions INSERT privilege regression
     (migration 046's blanket grant silently undid migration 041's
     deliberate revoke of INSERT from app_platform_admin).
See 5K/migrations/076_5K1.sql for full root-cause and scope comments.

Revision ID: 076_5K1
Revises: '075_5J'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = '076_5K1'
down_revision: Union[str, None] = '075_5J'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '076_5K1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 076_5K1 is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/076_5K1.sql). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied."
    )
