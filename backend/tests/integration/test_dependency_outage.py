"""Dependency loss while the application is running, against real PostgreSQL and Redis.

D0-P1-06: a PostgreSQL outage during a request becomes 503 DEPENDENCY_UNAVAILABLE
(retryable) in the standard envelope, the transaction is rolled back and the
connection returned; request errors keep their own mapping.
D0-P1-05: readiness and startup require a positive PONG.
D0-P1-01: cancelling shutdown cannot orphan a real connection.

The application reaches PostgreSQL through ``TcpProxy``, which the test cuts to
make the server unreachable and restores to bring it back.
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass

import asyncpg
import httpx
import pytest
from fastapi import APIRouter, FastAPI
from psycopg import sql
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from tests.conftest import make_settings
from tests.integration.conftest import application_connections, count_markers
from tests.support.infrastructure import (
    PostgresCluster,
    RedisServer,
    redis_server,
    start_redis_server,
)
from tests.support.network import FakeRespServer, TcpProxy
from voice_agent.apps.api.dependencies.infrastructure import DbSessionDependency
from voice_agent.apps.api.main import create_app
from voice_agent.apps.api.middleware.correlation_id import REQUEST_ID_HEADER
from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.infrastructure.db.engine import create_database_engine
from voice_agent.platform.infrastructure.db.session import Database
from voice_agent.platform.infrastructure.runtime import InfrastructureRuntime, RuntimeState
from voice_agent.platform.shared_kernel.errors import CacheError, DatabaseError

pytestmark = pytest.mark.integration

SLEEP_SQL = "SELECT pg_sleep(:seconds)"
# "lastval is not yet defined in this session": a genuine server-raised 55000.
LASTVAL_SQL = "SELECT lastval()"
RAISE_55000_SQL = "DO $$ BEGIN RAISE EXCEPTION 'not ready' USING ERRCODE = '55000'; END $$"
FIND_SLEEPING_BACKEND_SQL = (
    "SELECT pid FROM pg_stat_activity "
    "WHERE datname = %s AND application_name = %s AND query LIKE %s AND state = 'active'"
)


@dataclass
class _Stack:
    app: FastAPI
    client: httpx.AsyncClient
    proxy: TcpProxy
    settings: ApiSettings

    @property
    def runtime(self) -> InfrastructureRuntime:
        runtime: InfrastructureRuntime = self.app.state.runtime
        return runtime


def _proxied_settings(
    cluster: PostgresCluster, database: str, redis_url: str, proxy: TcpProxy
) -> ApiSettings:
    url = cluster.runtime_url(database).replace(f":{cluster.port}/", f":{proxy.port}/")
    return make_settings(database_url=url, redis_url=redis_url)


@asynccontextmanager
async def _running(
    cluster: PostgresCluster, database: str, redis_url: str, insert_sql: str | None = None
) -> AsyncIterator[_Stack]:
    proxy = TcpProxy(cluster.port)
    await proxy.start()
    settings = _proxied_settings(cluster, database, redis_url, proxy)
    app = create_app(settings)
    router = APIRouter()

    @router.get("/__probe/read")
    async def read(session: DbSessionDependency) -> dict[str, int]:
        return {"value": int((await session.execute(text("SELECT 1"))).scalar_one())}

    @router.post("/__probe/write/{marker}")
    async def write(marker: str, session: DbSessionDependency, sleep: float = 0) -> dict[str, str]:
        assert insert_sql is not None
        await session.execute(text(insert_sql), {"marker": marker})
        await session.flush()
        if sleep:
            await session.execute(text(SLEEP_SQL), {"seconds": sleep})
        return {"written": marker}

    @router.post("/__probe/duplicate/{marker}")
    async def duplicate(marker: str, session: DbSessionDependency) -> None:
        assert insert_sql is not None
        await session.execute(text(insert_sql), {"marker": marker})
        await session.execute(text(insert_sql), {"marker": marker})

    @router.get("/__probe/sqlstate-55000/{variant}")
    async def sqlstate_55000(variant: str, session: DbSessionDependency) -> None:
        # Both statements fail with SQLSTATE 55000 on a healthy, established connection.
        await session.execute(text("SELECT 1"))
        await session.execute(text(LASTVAL_SQL if variant == "lastval" else RAISE_55000_SQL))

    @router.get("/__probe/bad-sql")
    async def bad_sql(session: DbSessionDependency) -> None:
        await session.execute(text("SELEKT nothing FROM nowhere"))

    app.include_router(router)
    try:
        async with app.router.lifespan_context(app):
            transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
            async with httpx.AsyncClient(
                transport=transport, base_url="http://testserver"
            ) as client:
                yield _Stack(app, client, proxy, settings)
    finally:
        await proxy.close()


def _assert_dependency_unavailable(response: httpx.Response, cluster: PostgresCluster) -> None:
    assert response.status_code == 503, response.text
    body = response.json()
    assert set(body) == {"error"}
    error = body["error"]
    assert set(error) == {"code", "message", "details", "request_id", "retryable"}
    assert error["code"] == "DEPENDENCY_UNAVAILABLE"
    assert error["retryable"] is True
    assert error["details"] == {}
    assert error["request_id"] == response.headers[REQUEST_ID_HEADER]
    assert uuid.UUID(error["request_id"]).version == 7
    for internal in (
        cluster.runtime_password,
        "asyncpg",
        "sqlalchemy",
        "Traceback",
        "Connection",
        "127.0.0.1",
        "voice_agent_test",
    ):
        assert internal not in response.text


async def _wait_for(
    condition: Callable[[], Awaitable[bool] | bool], *, seconds: float = 20
) -> None:
    deadline = asyncio.get_running_loop().time() + seconds
    while asyncio.get_running_loop().time() < deadline:
        result = condition()
        if (await result) if isinstance(result, Awaitable) else result:
            return
        await asyncio.sleep(0.05)
    raise AssertionError("condition was not reached in time")


# ---------------------------------------------------------------- PostgreSQL (D0-P1-06)


async def test_server_unreachable_before_the_query_then_recovery(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    capsys: pytest.CaptureFixture[str],
) -> None:
    async with _running(postgres_cluster, migrated_database, redis_service.url) as stack:
        assert (await stack.client.get("/__probe/read")).status_code == 200

        await stack.proxy.cut()
        down = await stack.client.get("/__probe/read")
        _assert_dependency_unavailable(down, postgres_cluster)
        assert stack.runtime.database.checked_out_connections() == 0
        assert (await stack.client.get("/health/live")).status_code == 200
        assert (await stack.client.get("/health/ready")).status_code == 503

        await stack.proxy.start()
        recovered = await stack.client.get("/__probe/read")
        assert recovered.status_code == 200
        assert (await stack.client.get("/health/ready")).status_code == 200
        assert stack.runtime.database.checked_out_connections() == 0
    logs = capsys.readouterr().out
    assert '"event": "dependency_unavailable"' in logs
    assert '"reason": "postgres_unreachable"' in logs
    assert postgres_cluster.runtime_password not in logs


async def test_database_disappearing_after_startup(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    async with _running(postgres_cluster, migrated_database, redis_service.url) as stack:
        assert (await stack.client.get("/__probe/read")).status_code == 200
        postgres_cluster.drop_database(migrated_database)  # WITH (FORCE): sessions are killed
        gone = await stack.client.get("/__probe/read")
        _assert_dependency_unavailable(gone, postgres_cluster)
        assert stack.runtime.database.checked_out_connections() == 0


async def test_connection_terminated_during_an_active_request_rolls_back(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    probe_table: str,
) -> None:
    async with _running(
        postgres_cluster, migrated_database, redis_service.url, probe_table
    ) as stack:
        request = asyncio.create_task(
            stack.client.post("/__probe/write/in-flight", params={"sleep": "30"})
        )

        def sleeping_backends() -> list[int]:
            with postgres_cluster.admin_connect() as admin:
                rows = admin.execute(
                    FIND_SLEEPING_BACKEND_SQL,
                    (migrated_database, stack.settings.service_name, "%pg_sleep%"),
                ).fetchall()
            return [int(str(row[0])) for row in rows]

        await _wait_for(lambda: bool(sleeping_backends()))
        with postgres_cluster.admin_connect() as admin:
            for pid in sleeping_backends():
                admin.execute("SELECT pg_terminate_backend(%s)", (pid,))

        terminated = await request
        _assert_dependency_unavailable(terminated, postgres_cluster)
        assert stack.runtime.database.checked_out_connections() == 0
        # The pool replaces the dead connection: the next request succeeds.
        assert (await stack.client.post("/__probe/write/after-recovery")).status_code == 200
    assert count_markers(postgres_cluster, migrated_database, "in-flight") == 0
    assert count_markers(postgres_cluster, migrated_database, "after-recovery") == 1


async def test_network_cut_during_an_active_request_rolls_back(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    probe_table: str,
) -> None:
    async with _running(
        postgres_cluster, migrated_database, redis_service.url, probe_table
    ) as stack:
        request = asyncio.create_task(
            stack.client.post("/__probe/write/cut-off", params={"sleep": "30"})
        )
        await _wait_for(lambda: stack.runtime.database.checked_out_connections() == 1)
        await asyncio.sleep(0.5)  # let the INSERT reach the server before the cut
        await stack.proxy.cut()
        _assert_dependency_unavailable(await request, postgres_cluster)
        assert stack.runtime.database.checked_out_connections() == 0
        await stack.proxy.start()
        assert (await stack.client.get("/__probe/read")).status_code == 200

    async def rolled_back() -> bool:
        return count_markers(postgres_cluster, migrated_database, "cut-off") == 0

    # The server notices the lost client and aborts its transaction.
    await _wait_for(rolled_back)


async def test_database_refusing_new_connections_then_recovery(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    capsys: pytest.CaptureFixture[str],
) -> None:
    # D0-P1-07: ALLOW_CONNECTIONS false makes PostgreSQL refuse the pool's new
    # connection with SQLSTATE 55000. That is an outage at acquisition time.
    database_name = sql.Identifier(migrated_database)
    async with _running(postgres_cluster, migrated_database, redis_service.url) as stack:
        assert (await stack.client.get("/__probe/read")).status_code == 200
        with postgres_cluster.admin_connect() as admin:
            admin.execute(
                sql.SQL("ALTER DATABASE {} ALLOW_CONNECTIONS false").format(database_name)
            )
            admin.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s",
                (migrated_database,),
            )
        try:
            for _ in range(3):  # every attempt, not only the one that finds the dead connection
                refused = await stack.client.get("/__probe/read")
                _assert_dependency_unavailable(refused, postgres_cluster)
                for raw in ("55000", "not currently accepting", "ObjectNotInPrerequisiteState"):
                    assert raw not in refused.text
                assert stack.runtime.database.checked_out_connections() == 0
            assert (await stack.client.get("/health/ready")).status_code == 503
            assert (await stack.client.get("/health/live")).status_code == 200
        finally:
            with postgres_cluster.admin_connect() as admin:
                admin.execute(
                    sql.SQL("ALTER DATABASE {} ALLOW_CONNECTIONS true").format(database_name)
                )
        recovered = await stack.client.get("/__probe/read")
        assert recovered.status_code == 200
        assert stack.runtime.database.checked_out_connections() == 0
    logs = capsys.readouterr().out
    assert '"phase": "connection_acquisition"' in logs
    assert '"error_type": "ObjectNotInPrerequisiteStateError"' in logs


@pytest.mark.parametrize("variant", ["lastval", "raised"])
async def test_sqlstate_55000_from_a_statement_is_not_an_outage(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    variant: str,
) -> None:
    # The same SQLSTATE as a refused connection, but raised by a statement on a
    # healthy connection: classification follows the phase, not the code.
    async with _running(postgres_cluster, migrated_database, redis_service.url) as stack:
        response = await stack.client.get(f"/__probe/sqlstate-55000/{variant}")
        assert response.status_code == 500
        error = response.json()["error"]
        assert error["code"] == "INTERNAL_ERROR"
        assert error["retryable"] is False
        assert stack.runtime.database.checked_out_connections() == 0
        assert (await stack.client.get("/__probe/read")).status_code == 200
        assert (await stack.client.get("/health/ready")).status_code == 200

        with pytest.raises(DBAPIError) as raised:
            async with stack.runtime.database.transaction() as session:
                await session.execute(text(LASTVAL_SQL))
        assert getattr(raised.value.orig, "sqlstate", None) == "55000"


async def test_rejected_credentials_at_acquisition_are_not_an_outage(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    settings = make_settings(
        database_url=postgres_cluster.runtime_url(migrated_database).replace(
            postgres_cluster.runtime_password, "wrong-" + "x" * 12
        ),
        redis_url=redis_service.url,
    )
    database = Database(create_database_engine(settings.database, application_name="d0-outage"))
    try:
        with pytest.raises(asyncpg.InvalidPasswordError):
            async with database.transaction():
                pass
        assert database.checked_out_connections() == 0
    finally:
        await database.dispose()


@pytest.mark.parametrize(
    ("method", "path"),
    [("POST", "/__probe/duplicate/twice"), ("GET", "/__probe/bad-sql")],
    ids=["integrity-violation", "sql-error"],
)
async def test_request_errors_are_not_reported_as_an_outage(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    probe_table: str,
    method: str,
    path: str,
) -> None:
    async with _running(
        postgres_cluster, migrated_database, redis_service.url, probe_table
    ) as stack:
        response = await stack.client.request(method, path)
        assert response.status_code == 500
        error = response.json()["error"]
        assert error["code"] == "INTERNAL_ERROR"
        assert error["retryable"] is False
        for internal in ("duplicate key", "SELEKT", "syntax", "d0_probe"):
            assert internal not in response.text
        assert stack.runtime.database.checked_out_connections() == 0
        assert (await stack.client.get("/__probe/read")).status_code == 200
    assert count_markers(postgres_cluster, migrated_database, "twice") == 0


async def test_transaction_boundary_normalises_outages_and_only_outages(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    proxy = TcpProxy(postgres_cluster.port)
    await proxy.start()
    settings = _proxied_settings(postgres_cluster, migrated_database, redis_service.url, proxy)
    database = Database(create_database_engine(settings.database, application_name="d0-outage"))
    try:
        async with database.transaction() as session:
            await session.execute(text("SELECT 1"))
        await proxy.cut()
        with pytest.raises(DatabaseError) as raised:
            async with database.transaction() as session:
                await session.execute(text("SELECT 1"))
        assert raised.value.context["reason"] == "postgres_unreachable"
        assert raised.value.context["phase"] == "connection_acquisition"
        assert raised.value.__cause__ is not None
        assert postgres_cluster.runtime_password not in str(raised.value)
        assert database.checked_out_connections() == 0

        await proxy.start()
        entered = asyncio.Event()

        async def sleeper() -> None:
            async with database.transaction() as session:
                entered.set()
                await session.execute(text(SLEEP_SQL), {"seconds": 30})

        task = asyncio.create_task(sleeper())
        await entered.wait()
        await asyncio.sleep(0.2)
        task.cancel()
        # Cancellation stays cancellation: it is never turned into DatabaseError.
        with pytest.raises(asyncio.CancelledError):
            await task
        assert database.checked_out_connections() == 0
        await database.ping(timeout_seconds=5)
    finally:
        await database.dispose()
        await proxy.close()


# ---------------------------------------------------------------- Redis (D0-P1-05)


async def test_startup_fails_against_a_peer_that_does_not_answer_pong(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    fake = FakeRespServer(b"+NOTPONG\r\n")
    await fake.start()
    settings = make_settings(
        database_url=postgres_cluster.runtime_url(migrated_database), redis_url=fake.url
    )
    app = create_app(settings)
    try:
        with pytest.raises(CacheError) as raised:
            async with app.router.lifespan_context(app):
                pass
    finally:
        await fake.close()
    # Refused either by the client's PING check or, earlier, by redis-py's own
    # connection health check, which also requires PONG.
    assert raised.value.context["reason"] in {"redis_ping_unexpected_reply", "redis_unreachable"}
    assert "NOTPONG" not in str(raised.value) + repr(raised.value.context)
    assert app.state.runtime.state is RuntimeState.STOPPED
    assert application_connections(postgres_cluster, migrated_database, settings.service_name) == 0


async def test_readiness_follows_the_ping_reply_and_recovers(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    fake = FakeRespServer(b"+PONG\r\n")
    await fake.start()
    settings = make_settings(
        database_url=postgres_cluster.runtime_url(migrated_database), redis_url=fake.url
    )
    app = create_app(settings)
    try:
        async with app.router.lifespan_context(app):
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(transport=transport, base_url="http://t") as client:
                assert (await client.get("/health/ready")).status_code == 200
                for reply in (b"+NOTPONG\r\n", b":0\r\n", b"?garbage\r\n"):
                    fake.ping_reply = reply
                    down = await client.get("/health/ready")
                    assert down.status_code == 503
                    assert down.json() == {
                        "status": "unavailable",
                        "checks": {"postgres": "ok", "redis": "failed"},
                    }
                    assert "NOTPONG" not in down.text and "garbage" not in down.text
                fake.ping_reply = b"+PONG\r\n"
                assert (await client.get("/health/ready")).status_code == 200
    finally:
        await fake.close()


async def test_readiness_recovers_when_a_real_redis_comes_back(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    with redis_server() as first:
        settings = make_settings(
            database_url=postgres_cluster.runtime_url(migrated_database), redis_url=first.url
        )
        app = create_app(settings)
        async with app.router.lifespan_context(app):
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(transport=transport, base_url="http://t") as client:
                assert (await client.get("/health/ready")).status_code == 200
                first.process.kill()
                first.process.wait(timeout=30)
                assert (await client.get("/health/ready")).status_code == 503

                second = start_redis_server(port=first.port, password=first.password)
                try:
                    recovered = await client.get("/health/ready")
                    assert recovered.status_code == 200
                    assert recovered.json()["checks"] == {"postgres": "ok", "redis": "ok"}
                finally:
                    second.stop()


# ---------------------------------------------------------------- shutdown (D0-P1-01)


@pytest.mark.parametrize("blocked", ["redis", "postgres"])
async def test_cancelled_shutdown_leaves_no_connection_behind(
    live_settings: ApiSettings,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    blocked: str,
) -> None:
    runtime = InfrastructureRuntime(live_settings)
    await runtime.start()
    database, redis = runtime.database, runtime.redis
    async with database.transaction() as session:
        await session.execute(text("SELECT 1"))
    service = live_settings.service_name
    assert application_connections(postgres_cluster, migrated_database, service) >= 1

    resource = redis if blocked == "redis" else database
    real_release = redis.close if blocked == "redis" else database.dispose
    entered, gate, calls = asyncio.Event(), asyncio.Event(), 0

    async def gated_release() -> None:
        nonlocal calls
        calls += 1
        entered.set()
        await gate.wait()
        await real_release()

    setattr(resource, "close" if blocked == "redis" else "dispose", gated_release)

    stopping = asyncio.create_task(runtime.stop())
    await entered.wait()
    stopping.cancel()
    await asyncio.sleep(0.1)
    # Not STOPPED, and nothing dropped, while a resource is still being released.
    assert not stopping.done()
    assert runtime.state.value == RuntimeState.STOPPING.value
    assert blocked in runtime.owned_resources

    gate.set()
    with pytest.raises(asyncio.CancelledError):
        await stopping
    assert runtime.state.value == RuntimeState.STOPPED.value
    assert runtime.owned_resources == ()
    assert redis.is_closed and database.is_disposed
    assert application_connections(postgres_cluster, migrated_database, service) == 0

    await runtime.stop()  # second stop: nothing left to do, nothing released twice
    assert calls == 1
