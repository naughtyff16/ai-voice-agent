"""Database session and transaction contract.

Ownership rules:

* One ``Database`` owns one engine (and its connection pool) for the lifetime
  of the process. It is created and disposed by ``InfrastructureRuntime``.
* A session exists only inside ``Database.transaction()``. That scope owns the
  transaction: it commits when the block exits normally and rolls back when it
  raises. Callers never commit, and no session outlives its scope or is shared
  between requests or tasks.

The module has no dependency on FastAPI, so workers can use it unchanged.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Awaitable, Callable, Sequence
from contextlib import asynccontextmanager

import asyncpg
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import QueuePool

from voice_agent.platform.infrastructure.db.errors import (
    is_connection_acquisition_unavailable,
    is_database_unavailable,
)
from voice_agent.platform.shared_kernel.errors import DatabaseError

# Everything that means "PostgreSQL could not be used right now". asyncpg errors
# raised while the pool opens a new connection (refused authentication, a
# database not accepting connections) reach the caller unwrapped by SQLAlchemy.
CONNECTIVITY_ERRORS: tuple[type[BaseException], ...] = (
    SQLAlchemyError,
    asyncpg.PostgresError,
    asyncpg.InterfaceError,
    OSError,
    TimeoutError,
)

# Runs inside every transaction, immediately after BEGIN. This is the seam where
# the tenancy phase issues ``SET LOCAL app.tenant_id`` (5B §16.1); transaction
# scope keeps it correct under PgBouncer transaction pooling (5A §27.1).
SessionInitializer = Callable[[AsyncSession], Awaitable[None]]


def _unreachable(exc: BaseException, *, phase: str) -> DatabaseError:
    return DatabaseError(
        "PostgreSQL is not reachable.",
        context={
            "reason": "postgres_unreachable",
            "phase": phase,
            "error_type": type(exc).__name__,
        },
    )


class Database:
    def __init__(
        self,
        engine: AsyncEngine,
        *,
        session_initializers: Sequence[SessionInitializer] = (),
    ) -> None:
        self._engine = engine
        self._session_factory = async_sessionmaker(engine, expire_on_commit=False)
        self._session_initializers = tuple(session_initializers)
        # _disposing refuses new work as soon as dispose() begins; _disposed is set
        # only once the pool is actually closed, so an interrupted dispose can be retried.
        self._disposing = False
        self._disposed = False

    @asynccontextmanager
    async def transaction(self) -> AsyncIterator[AsyncSession]:
        """Yield a session bound to one transaction: commit on success, rollback on error.

        This is the infrastructure boundary for outages: a failure that means
        PostgreSQL is unavailable (see ``db.errors``) leaves the block as
        ``DatabaseError``, after the session has been rolled back and closed.
        That covers failing to obtain a connection at all, and losing one mid-way.
        Every other exception, including cancellation, propagates unchanged.
        """
        if self._disposing:
            raise DatabaseError("The database has been disposed.")
        try:
            async with self._session_factory() as session, session.begin():
                # The connection is acquired here, explicitly, instead of lazily by
                # the first statement. A failure in this step is by construction a
                # connection-acquisition failure, which is the only context in which
                # a refusal such as "database is not accepting connections"
                # (SQLSTATE 55000) means the dependency is unavailable.
                try:
                    await session.connection()
                except Exception as exc:
                    if not is_connection_acquisition_unavailable(exc):
                        raise
                    raise _unreachable(exc, phase="connection_acquisition") from exc
                for initialize in self._session_initializers:
                    await initialize(session)
                yield session
        except Exception as exc:
            # A DatabaseError is already normalised (e.g. by the acquisition step above).
            if isinstance(exc, DatabaseError) or not is_database_unavailable(exc):
                raise
            raise _unreachable(exc, phase="transaction") from exc

    async def ping(self, *, timeout_seconds: float) -> None:
        """Prove a pooled connection can run a query, or raise ``DatabaseError``."""
        if self._disposing:
            raise DatabaseError("The database has been disposed.")
        try:
            async with asyncio.timeout(timeout_seconds), self._engine.connect() as connection:
                await connection.execute(text("SELECT 1"))
        except CONNECTIVITY_ERRORS as exc:
            raise DatabaseError(
                "PostgreSQL is not reachable.", context={"error_type": type(exc).__name__}
            ) from exc

    def checked_out_connections(self) -> int:
        """Connections currently in use; zero whenever no transaction is open."""
        pool = self._engine.pool
        return pool.checkedout() if isinstance(pool, QueuePool) else 0

    @property
    def is_disposed(self) -> bool:
        """True once every pooled connection has been closed."""
        return self._disposed

    async def dispose(self) -> None:
        """Close every pooled connection.

        Idempotent once it has completed. If it raises or is cancelled part-way,
        calling it again finishes the release: disposing an engine twice is safe.
        """
        if self._disposed:
            return
        self._disposing = True
        await self._engine.dispose()
        self._disposed = True
