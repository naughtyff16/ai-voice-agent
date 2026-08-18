#!/usr/bin/env python3
"""Generate 5K/alembic/versions/*.py from 5K/migrations/*.sql (one-time).

Deterministic: revision id = filename stem (e.g. "001_5B"), down_revision
= previous file's stem (None for the first). This mirrors the manifest
table in 5K-Database-Migration-and-Implementation.md §22 exactly.
"""
import pathlib

ROOT = pathlib.Path("/home/crm-lp-1/karthi/Chunk_Mates/ai-voice-agent-platform/docs/phase-05-database-design/5K")
MIGRATIONS = ROOT / "migrations"
VERSIONS = ROOT / "alembic" / "versions"

files = sorted(p.name for p in MIGRATIONS.glob("*.sql"))
assert len(files) == 75, f"expected 75 migrations, found {len(files)}"

TEMPLATE = '''"""Phase 5K — wraps frozen migration {filename}.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/{filename} verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen) and adding parallel DDL here would
create a second, competing schema history — see 5K/alembic/README.md.

Revision ID: {revision}
Revises: {down_revision_repr}
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = {revision!r}
down_revision: Union[str, None] = {down_revision_repr}
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = {filename!r}


def upgrade() -> None:
{upgrade_body}


def downgrade() -> None:
    raise NotImplementedError(
        "Migration {revision} is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/{filename}). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied."
    )
'''

AUTOCOMMIT_TEMPLATE = "    with op.get_context().autocommit_block():\n        run_frozen_sql(SQL_FILE)\n"
NORMAL_TEMPLATE = "    run_frozen_sql(SQL_FILE)\n"

# Migrations requiring a non-transactional (autocommit) execution block.
# As frozen, NONE of 001-075 require this: 043_5F.sql was authored to
# avoid CREATE INDEX CONCURRENTLY entirely (see its own header comment
# and 5K/alembic/README.md). Kept as an explicit, empty set — not
# inferred — so a future genuinely-concurrent revision has a clear,
# documented place to be added.
AUTOCOMMIT_REVISIONS: set[str] = set()

prev_stem = None
for fname in files:
    stem = fname[:-4]  # strip ".sql"
    down_repr = "None" if prev_stem is None else repr(prev_stem)
    body = AUTOCOMMIT_TEMPLATE if stem in AUTOCOMMIT_REVISIONS else NORMAL_TEMPLATE
    # need "from alembic import op" only for autocommit path
    content = TEMPLATE.format(
        filename=fname,
        revision=stem,
        down_revision_repr=down_repr,
        upgrade_body=body,
    )
    if stem in AUTOCOMMIT_REVISIONS:
        content = content.replace(
            "from _frozen_sql import run_frozen_sql",
            "from alembic import op\n\nfrom _frozen_sql import run_frozen_sql",
        )
    out = VERSIONS / f"{stem}.py"
    out.write_text(content, encoding="utf-8")
    prev_stem = stem

print(f"generated {len(files)} revision files; head = {prev_stem}")
