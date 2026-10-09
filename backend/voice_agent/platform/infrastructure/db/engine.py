"""Async SQLAlchemy engine factory for PostgreSQL (3F §15.1)."""

from __future__ import annotations

from uuid import uuid4

from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from voice_agent.platform.config.base_settings import DatabaseSettings


def _unique_prepared_statement_name() -> str:
    return f"__asyncpg_{uuid4()}__"


def create_database_engine(settings: DatabaseSettings, *, application_name: str) -> AsyncEngine:
    """Build the engine. No connection is opened until the pool is first used.

    Production traffic reaches PostgreSQL through PgBouncer in transaction-pooling
    mode (3F §15.1), where server-side prepared statements cannot be relied on
    (5A §27.1). Statement caches are therefore disabled and every prepared
    statement gets a unique name, which is also correct on a direct connection.

    The connection identity is passed to asyncpg explicitly from the validated
    ``DatabaseTarget``. Explicit arguments win over URL options and over libpq
    environment variables, so the driver connects exactly where validation said.
    """
    target = settings.target()
    return create_async_engine(
        settings.sqlalchemy_url(),
        pool_size=settings.pool_size,
        max_overflow=settings.max_overflow,
        pool_timeout=settings.pool_timeout_seconds,
        pool_recycle=settings.pool_recycle_seconds,
        pool_pre_ping=True,
        connect_args={
            "host": target.host,
            "port": target.port,
            "user": target.user,
            "database": target.database,
            "timeout": settings.connect_timeout_seconds,
            "command_timeout": settings.command_timeout_seconds,
            "statement_cache_size": 0,
            "prepared_statement_cache_size": 0,
            "prepared_statement_name_func": _unique_prepared_statement_name,
            "server_settings": {"application_name": application_name},
        },
    )
