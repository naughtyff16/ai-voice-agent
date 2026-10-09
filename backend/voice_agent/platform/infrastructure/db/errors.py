"""Which database failures mean "PostgreSQL is unavailable right now".

Request-time code never inspects driver exceptions. ``Database.transaction()``
passes every failure through ``is_database_unavailable`` and turns the ones it
recognises into ``DatabaseError``, which the API maps to 503
``DEPENDENCY_UNAVAILABLE`` (retryable). Everything else keeps its own type: a
constraint violation, a SQL error or an application error is not an outage, and
cancellation is never classified at all.

Recognised as unavailable:

* the connection was lost and SQLAlchemy invalidated it (``connection_invalidated``);
* SQLSTATE class 08 (connection exception), 57P01/57P02/57P03/57P05 (server
  shutdown, crash, starting up, idle-session timeout), 53300 (too many
  connections) and 3D000 (the database no longer exists);
* asyncpg reporting a closed connection;
* socket-level failures while connecting: refused, reset, aborted, broken
  pipe, DNS failure, unreachable network or host, and connect timeouts;
* the pool timing out while waiting for a connection.

Context matters for one more case. SQLSTATE 55000 (object not in prerequisite
state) is what PostgreSQL answers when a database is not accepting connections
(``ALLOW_CONNECTIONS false``), but an ordinary statement can raise it too, for
unrelated reasons. It is therefore an outage **only while a connection is
being acquired** (``is_connection_acquisition_unavailable``), never for a
statement running on an established connection. Rejected credentials
(SQLSTATE class 28) are a configuration fault, not an outage, in either phase.
"""

from __future__ import annotations

import errno
import socket
from typing import Final

import asyncpg
from sqlalchemy.exc import DBAPIError
from sqlalchemy.exc import TimeoutError as PoolTimeoutError

_UNAVAILABLE_SQLSTATE_CLASS: Final = "08"
_UNAVAILABLE_SQLSTATES: Final[frozenset[str]] = frozenset(
    {"57P01", "57P02", "57P03", "57P05", "53300", "3D000"}
)
# Refusals that mean "unavailable" only when raised while connecting.
_ACQUISITION_ONLY_SQLSTATES: Final[frozenset[str]] = frozenset({"55000"})
_NETWORK_ERRNOS: Final[frozenset[int]] = frozenset(
    {
        errno.ECONNREFUSED,
        errno.ECONNRESET,
        errno.ECONNABORTED,
        errno.EPIPE,
        errno.ENETDOWN,
        errno.ENETUNREACH,
        errno.ENETRESET,
        errno.EHOSTDOWN,
        errno.EHOSTUNREACH,
        errno.ETIMEDOUT,
    }
)
_MAX_CHAIN: Final = 8


def _causes(exc: BaseException) -> list[BaseException]:
    """``exc`` and what it wraps: the DBAPI error behind a SQLAlchemy error and explicit causes.

    ``__context__`` is deliberately not followed: an unrelated error raised while
    handling an outage must not be mistaken for one.
    """
    chain: list[BaseException] = []
    current: BaseException | None = exc
    while current is not None and len(chain) < _MAX_CHAIN and current not in chain:
        chain.append(current)
        wrapped = current.orig if isinstance(current, DBAPIError) else None
        current = wrapped if isinstance(wrapped, BaseException) else current.__cause__
    return chain


def _is_network_failure(exc: BaseException) -> bool:
    if not isinstance(exc, OSError):
        return False
    if isinstance(exc, ConnectionError | TimeoutError | socket.gaierror):
        return True
    if exc.errno in _NETWORK_ERRNOS:
        return True
    # asyncio.create_connection() aggregates per-address failures into a plain
    # OSError when a host name resolves to several addresses (e.g. localhost).
    return exc.errno is None and str(exc).startswith("Multiple exceptions:")


def is_database_unavailable(exc: BaseException) -> bool:
    """True if ``exc`` means PostgreSQL cannot be used right now, not that the request is wrong."""
    for candidate in _causes(exc):
        if isinstance(candidate, BaseException) and not isinstance(candidate, Exception):
            return False  # cancellation and interpreter exits are never an outage
        if isinstance(candidate, DBAPIError) and candidate.connection_invalidated:
            return True
        if isinstance(candidate, PoolTimeoutError):
            return True
        if isinstance(candidate, asyncpg.ConnectionDoesNotExistError):
            return True
        sqlstate = getattr(candidate, "sqlstate", None)
        if isinstance(sqlstate, str) and (
            sqlstate.startswith(_UNAVAILABLE_SQLSTATE_CLASS) or sqlstate in _UNAVAILABLE_SQLSTATES
        ):
            return True
        if _is_network_failure(candidate):
            return True
    return False


def is_connection_acquisition_unavailable(exc: BaseException) -> bool:
    """Like ``is_database_unavailable``, for a failure raised while acquiring a connection.

    Adds the refusals that only mean "unavailable" at connect time. The caller
    is responsible for knowing that the failure happened during acquisition.
    """
    if is_database_unavailable(exc):
        return True
    for candidate in _causes(exc):
        if not isinstance(candidate, Exception):
            return False
        if getattr(candidate, "sqlstate", None) in _ACQUISITION_ONLY_SQLSTATES:
            return True
    return False
