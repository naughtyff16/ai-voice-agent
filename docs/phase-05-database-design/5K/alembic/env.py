"""Phase 5K — Alembic environment.

Alembic is an INTEGRATION/TRACKING layer here, not a schema authority.
The canonical schema is the frozen SQL package at ../migrations/001-075.
Each revision under versions/ executes exactly one of those files via
op.execute(); target_metadata is deliberately None so that
`alembic revision --autogenerate` cannot propose a second, competing
schema history against these tables.

DATABASE_URL is read exclusively from the environment. No credentials
are read from, or written to, alembic.ini.
"""
from __future__ import annotations

import os
import sys
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

# Make _frozen_sql.py (this directory) importable from versions/*.py
# regardless of the process's current working directory or how
# alembic.ini's prepend_sys_path resolves — version scripts do
# `from _frozen_sql import run_frozen_sql`.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Alembic Config object, providing access to values in alembic.ini.
config = context.config

# Interpret the config file for Python logging, unless silenced.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# No ORM metadata: this package does not autogenerate schema. The
# schema of record is 5K/migrations/001-075.sql, applied by the
# versions/*.py wrappers below.
target_metadata = None


def get_url() -> str:
    """Resolve the database URL exclusively from the environment.

    Never falls back to a value baked into alembic.ini — there isn't
    one. Fails loudly rather than silently connecting to the wrong
    (or no) database.
    """
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError(
            "DATABASE_URL is not set. Phase 5K Alembic configuration "
            "requires DATABASE_URL as an environment variable (e.g. "
            "postgresql+psycopg2://user:pass@host:5432/voice_agent_dev). "
            "Refusing to fall back to a default or a value stored in "
            "alembic.ini — no credentials are committed to this repo."
        )
    return url


def run_migrations_offline() -> None:
    """Emit SQL to stdout without a live DB connection ("--sql" mode).

    Supported because the underlying content is already plain SQL —
    each revision just prints the frozen migration file it wraps, in
    order. Useful for producing a reviewable script for a DBA-gated
    production window without granting this process a live connection.
    """
    url = get_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        # One transaction per migration in offline mode too, so the
        # emitted script's BEGIN/COMMIT boundaries match what online
        # mode actually does per revision.
        transaction_per_migration=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations against a live PostgreSQL connection (PostgreSQL 18.x is the
    authoritative baseline as of 2026-08-29; PostgreSQL 16+ remains supported as a
    floor — see 5K-Database-Migration-and-Implementation.md §5).

    transaction_per_migration=True: each revision (each frozen SQL
    file) commits or rolls back on its own — matching how 001-075 were
    actually executed (§15.1/§20 of the 5K spec) and keeping a partial
    failure isolated to a single revision rather than the whole batch.

    A revision that genuinely cannot run inside a transaction (e.g. a
    CREATE INDEX CONCURRENTLY on a live/populated table) is expected
    to open its own context.autocommit_block() inside upgrade() rather
    than have this function change transaction handling globally. As
    frozen, none of 001-075 require this — see
    versions/043_5F.py and the 5K/alembic/README.md note on why.
    """
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = get_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            transaction_per_migration=True,
            compare_type=False,
            compare_server_default=False,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
