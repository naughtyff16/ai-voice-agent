"""How dependency failures are recognised: Redis PING (D0-P1-05) and PostgreSQL outages (D0-P1-06).

Real-server behaviour (a malformed RESP peer, a PostgreSQL that disappears)
is covered in tests/integration; these tests pin the classification rules.
"""

from __future__ import annotations

import asyncio
import errno
import secrets
import socket

import asyncpg
import pytest
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import InvalidResponse
from sqlalchemy.exc import DBAPIError, IntegrityError, ProgrammingError
from sqlalchemy.exc import TimeoutError as PoolTimeoutError

from voice_agent.platform.config.base_settings import RedisSettings
from voice_agent.platform.infrastructure.cache.redis_client import RedisClient
from voice_agent.platform.infrastructure.db.errors import (
    is_connection_acquisition_unavailable,
    is_database_unavailable,
)
from voice_agent.platform.shared_kernel.errors import CacheError, DatabaseError

pytestmark = pytest.mark.unit

PASSWORD = secrets.token_urlsafe(12)


class _StubRedis:
    """Stands in for redis.asyncio.Redis: ping() returns or raises what it is told to."""

    def __init__(self, outcome: object) -> None:
        self._outcome = outcome

    async def ping(self) -> object:
        if isinstance(self._outcome, BaseException):
            raise self._outcome
        if self._outcome == "hang":
            await asyncio.sleep(3600)
        return self._outcome


def _client(outcome: object) -> RedisClient:
    settings = RedisSettings.model_validate({"url": f"redis://:{PASSWORD}@127.0.0.1:6379/0"})
    client = RedisClient(settings, client_name="d0-unit")
    client._redis = _StubRedis(outcome)  # type: ignore[assignment]
    return client


async def test_ping_accepts_only_a_positive_pong() -> None:
    await _client(True).ping(timeout_seconds=1)


@pytest.mark.parametrize(
    "reply",
    [False, None, "PONG", b"PONG", "OK", 1, "+PONG"],
    ids=["false", "none", "str-pong", "bytes-pong", "ok", "one", "raw-pong"],
)
async def test_ping_rejects_any_other_reply_without_exposing_it(reply: object) -> None:
    with pytest.raises(CacheError) as raised:
        await _client(reply).ping(timeout_seconds=1)
    assert raised.value.context == {"reason": "redis_ping_unexpected_reply"}
    assert repr(reply) not in str(raised.value)


@pytest.mark.parametrize(
    "failure",
    [
        InvalidResponse("Protocol Error: b'?garbage'"),
        RedisConnectionError("Connection refused"),
        ConnectionRefusedError(errno.ECONNREFUSED, "refused"),
        "hang",
    ],
    ids=["malformed-resp", "redis-connection-error", "refused", "timeout"],
)
async def test_ping_failures_become_cache_errors(failure: object) -> None:
    with pytest.raises(CacheError) as raised:
        await _client(failure).ping(timeout_seconds=0.05)
    assert raised.value.context["reason"] == "redis_unreachable"
    assert "garbage" not in str(raised.value)


# ---------------------------------------------------------------- PostgreSQL outages


class _DriverError(Exception):
    def __init__(self, sqlstate: str) -> None:
        super().__init__(f"driver error {sqlstate}")
        self.sqlstate = sqlstate


def _wrapped(sqlstate: str, *, error_class: type[DBAPIError] = DBAPIError) -> DBAPIError:
    return error_class("SELECT 1", {}, _DriverError(sqlstate))


def _caused_by(outer: Exception, cause: BaseException) -> Exception:
    outer.__cause__ = cause
    return outer


def _raised_while_handling(outer: Exception, handled: BaseException) -> Exception:
    outer.__context__ = handled  # implicit chaining, not a cause
    return outer


UNAVAILABLE: list[tuple[str, BaseException]] = [
    ("connection refused", ConnectionRefusedError(errno.ECONNREFUSED, "refused")),
    ("connection reset", ConnectionResetError(errno.ECONNRESET, "reset")),
    ("broken pipe", BrokenPipeError(errno.EPIPE, "broken pipe")),
    ("connect timeout", TimeoutError()),
    ("dns failure", socket.gaierror(socket.EAI_NONAME, "unknown host")),
    ("host unreachable", OSError(errno.EHOSTUNREACH, "no route")),
    ("several addresses refused", OSError("Multiple exceptions: [Errno 111] ..., [Errno 111] ...")),
    ("pool exhausted", PoolTimeoutError("QueuePool limit reached")),
    (
        "invalidated connection",
        DBAPIError("SELECT 1", {}, Exception("closed"), connection_invalidated=True),
    ),
    ("connection failure 08006", _wrapped("08006")),
    ("connection does not exist 08003", _wrapped("08003")),
    ("admin shutdown 57P01", _wrapped("57P01")),
    ("crash shutdown 57P02", _wrapped("57P02")),
    ("cannot connect now 57P03", _wrapped("57P03")),
    ("too many connections 53300", _wrapped("53300")),
    ("database dropped 3D000", _wrapped("3D000")),
    ("asyncpg closed connection", asyncpg.ConnectionDoesNotExistError("closed mid-operation")),
    ("asyncpg admin shutdown", asyncpg.AdminShutdownError("terminating connection")),
    ("asyncpg cannot connect now", asyncpg.CannotConnectNowError("starting up")),
    (
        "sqlalchemy error caused by a refused connect",
        _caused_by(RuntimeError("wrapper"), ConnectionRefusedError(errno.ECONNREFUSED, "x")),
    ),
]

NOT_UNAVAILABLE: list[tuple[str, BaseException]] = [
    ("unique violation", _wrapped("23505", error_class=IntegrityError)),
    ("foreign key violation", _wrapped("23503", error_class=IntegrityError)),
    ("syntax error", _wrapped("42601", error_class=ProgrammingError)),
    ("undefined table", _wrapped("42P01", error_class=ProgrammingError)),
    ("invalid password", _wrapped("28P01")),
    ("statement timeout", _wrapped("57014")),
    # 55000 from a statement on a healthy connection (D0-P1-07 false-positive guard).
    ("object not in prerequisite state 55000", _wrapped("55000")),
    ("asyncpg 55000", asyncpg.ObjectNotInPrerequisiteStateError("lastval is not yet defined")),
    ("asyncpg unique violation", asyncpg.UniqueViolationError("duplicate key")),
    ("asyncpg interface misuse", asyncpg.InterfaceError("another operation is in progress")),
    ("application error", ValueError("bad input")),
    ("file not found", FileNotFoundError(errno.ENOENT, "missing")),
    ("permission denied", PermissionError(errno.EACCES, "denied")),
    ("platform database error", DatabaseError("already normalised")),
    ("cancellation", asyncio.CancelledError()),
    ("keyboard interrupt", KeyboardInterrupt()),
    (
        "error raised while handling an outage",
        _raised_while_handling(ValueError("bad"), ConnectionRefusedError(errno.ECONNREFUSED, "x")),
    ),
]


@pytest.mark.parametrize(("case", "exc"), UNAVAILABLE, ids=[case for case, _ in UNAVAILABLE])
def test_outages_are_recognised(case: str, exc: BaseException) -> None:
    assert is_database_unavailable(exc), case


@pytest.mark.parametrize(
    ("case", "exc"), NOT_UNAVAILABLE, ids=[case for case, _ in NOT_UNAVAILABLE]
)
def test_request_and_application_errors_are_not_outages(case: str, exc: BaseException) -> None:
    assert not is_database_unavailable(exc), case


def test_cancellation_anywhere_in_the_chain_is_never_an_outage() -> None:
    wrapper = _caused_by(RuntimeError("wrapper"), asyncio.CancelledError())
    assert not is_database_unavailable(wrapper)


# ---------------------------------------------------------------- acquisition phase (D0-P1-07)


@pytest.mark.parametrize(
    "exc",
    [
        asyncpg.ObjectNotInPrerequisiteStateError("database is not accepting connections"),
        _wrapped("55000"),
        ConnectionRefusedError(errno.ECONNREFUSED, "refused"),
        _wrapped("57P03"),
        _wrapped("3D000"),
    ],
    ids=["asyncpg-55000", "wrapped-55000", "refused", "starting-up", "database-dropped"],
)
def test_refusals_while_acquiring_a_connection_are_outages(exc: BaseException) -> None:
    assert is_connection_acquisition_unavailable(exc)


@pytest.mark.parametrize(
    "exc",
    [
        asyncpg.InvalidPasswordError("password authentication failed"),
        asyncpg.InvalidAuthorizationSpecificationError("role does not exist"),
        _wrapped("28P01"),
        _wrapped("42501"),
        ValueError("bug in an initializer"),
        asyncio.CancelledError(),
    ],
    ids=["bad-password", "bad-role", "wrapped-28P01", "no-privilege", "bug", "cancelled"],
)
def test_authentication_and_other_errors_while_acquiring_are_not_outages(
    exc: BaseException,
) -> None:
    assert not is_connection_acquisition_unavailable(exc)
