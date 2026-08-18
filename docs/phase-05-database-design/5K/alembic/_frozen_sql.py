"""Shared helper for Phase 5K revision wrappers.

Every revision in versions/ executes exactly one file from the frozen,
canonical SQL migration package at 5K/migrations/. This module centralizes
the "read the frozen file verbatim and run it" behavior so that no
revision script ever embeds a copy of migration SQL — the migrations/
directory remains the single source of truth, byte for byte.
"""
from __future__ import annotations

from pathlib import Path

from alembic import op

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


def read_frozen_sql(filename: str) -> str:
    """Read a frozen migration file's exact bytes as text.

    Raises FileNotFoundError loudly if 5K/migrations/<filename> has
    moved or been renamed — this must never fail silently into a
    no-op upgrade().
    """
    path = MIGRATIONS_DIR / filename
    if not path.is_file():
        raise FileNotFoundError(
            f"Frozen migration file not found: {path}. Revisions in "
            f"5K/alembic/versions/ wrap 5K/migrations/*.sql by reference "
            f"and must not embed migration content directly."
        )
    return path.read_text(encoding="utf-8")


def run_frozen_sql(filename: str) -> None:
    """Execute a frozen migration file's raw SQL against the current bind.

    Uses exec_driver_sql (not op.execute(text(...))) so the file's
    content is sent to the DBAPI verbatim, with no bind-parameter
    parsing — several of the frozen files contain PL/pgSQL bodies with
    literal ':=' assignment and '::' casts that must not be
    reinterpreted as SQLAlchemy bind parameters.
    """
    sql = read_frozen_sql(filename)
    op.get_bind().exec_driver_sql(sql)
