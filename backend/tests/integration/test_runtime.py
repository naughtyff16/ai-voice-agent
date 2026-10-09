"""Startup, readiness and shutdown of the real application against real dependencies."""

from __future__ import annotations

import secrets
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import httpx
import pytest
from fastapi import APIRouter, FastAPI
from psycopg import sql
from sqlalchemy import text

from tests.conftest import make_settings
from tests.integration.conftest import application_connections, count_markers
from tests.support.infrastructure import HOST, PostgresCluster, RedisServer, free_port, redis_server
from voice_agent.apps.api.dependencies.infrastructure import DbSessionDependency
from voice_agent.apps.api.main import create_app
from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.infrastructure.runtime import InfrastructureRuntime, RuntimeState
from voice_agent.platform.shared_kernel.errors import CacheError, DatabaseError

pytestmark = pytest.mark.integration


@asynccontextmanager
async def running(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    """Run the application's real lifespan and talk to it in-process."""
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            yield client


def _service_connections(cluster: PostgresCluster, database: str, settings: ApiSettings) -> int:
    return application_connections(cluster, database, settings.service_name)


async def test_startup_readiness_and_graceful_shutdown(
    live_settings: ApiSettings, postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    app = create_app(live_settings)
    runtime: InfrastructureRuntime = app.state.runtime
    async with running(app) as client:
        assert runtime.state is RuntimeState.READY
        live = await client.get("/health/live")
        ready = await client.get("/health/ready")
        assert live.status_code == 200
        assert ready.status_code == 200
        assert ready.json() == {"status": "ok", "checks": {"postgres": "ok", "redis": "ok"}}
        assert _service_connections(postgres_cluster, migrated_database, live_settings) >= 1
    assert runtime.state.value == RuntimeState.STOPPED.value
    assert _service_connections(postgres_cluster, migrated_database, live_settings) == 0
    with pytest.raises(RuntimeError):
        _ = runtime.database


async def test_runtime_cannot_be_started_twice(live_settings: ApiSettings) -> None:
    runtime = InfrastructureRuntime(live_settings)
    await runtime.start()
    try:
        with pytest.raises(RuntimeError, match="cannot be started"):
            await runtime.start()
    finally:
        await runtime.stop()
        await runtime.stop()  # idempotent
    with pytest.raises(RuntimeError, match="cannot be started"):
        await runtime.start()  # a stopped runtime is never reused


async def test_postgres_unavailable_at_startup_fails_and_leaks_nothing(
    redis_service: RedisServer,
) -> None:
    password = secrets.token_urlsafe(16)
    settings = make_settings(
        database_url=f"postgresql+asyncpg://app_api:{password}@{HOST}:{free_port()}/voice_agent_test_down",
        redis_url=redis_service.url,
    )
    app = create_app(settings)
    with pytest.raises(DatabaseError) as raised:
        async with running(app):
            pass
    assert app.state.runtime.state is RuntimeState.STOPPED
    assert password not in str(raised.value)


async def test_rejected_database_credentials_fail_startup_as_database_error(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    wrong = secrets.token_urlsafe(16)
    url = postgres_cluster.runtime_url(migrated_database).replace(
        postgres_cluster.runtime_password, wrong
    )
    app = create_app(make_settings(database_url=url, redis_url=redis_service.url))
    with pytest.raises(DatabaseError) as raised:
        async with running(app):
            pass
    assert raised.value.context["reason"] == "postgres_unreachable"
    assert wrong not in str(raised.value)
    assert app.state.runtime.state is RuntimeState.STOPPED


async def test_redis_unavailable_at_startup_fails_and_releases_postgres(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    settings = make_settings(
        database_url=postgres_cluster.runtime_url(migrated_database),
        redis_url=f"redis://:{secrets.token_urlsafe(8)}@{HOST}:{free_port()}/0",
    )
    app = create_app(settings)
    with pytest.raises(CacheError):
        async with running(app):
            pass
    assert app.state.runtime.state is RuntimeState.STOPPED
    # The engine opened during startup was disposed when Redis failed.
    assert _service_connections(postgres_cluster, migrated_database, settings) == 0


async def test_readiness_fails_while_postgres_is_unavailable_and_recovers(
    live_settings: ApiSettings, postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    app = create_app(live_settings)
    database_name = sql.Identifier(migrated_database)
    async with running(app) as client:
        with postgres_cluster.admin_connect() as admin:
            admin.execute(
                sql.SQL("ALTER DATABASE {} ALLOW_CONNECTIONS false").format(database_name)
            )
            admin.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s",
                (migrated_database,),
            )
        try:
            down = await client.get("/health/ready")
            assert down.status_code == 503
            assert down.json() == {
                "status": "unavailable",
                "checks": {"postgres": "failed", "redis": "skipped"},
            }
            assert (await client.get("/health/live")).status_code == 200
        finally:
            with postgres_cluster.admin_connect() as admin:
                admin.execute(
                    sql.SQL("ALTER DATABASE {} ALLOW_CONNECTIONS true").format(database_name)
                )
        recovered = await client.get("/health/ready")
        assert recovered.status_code == 200


async def test_readiness_fails_while_redis_is_offline(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    with redis_server() as server:
        settings = make_settings(
            database_url=postgres_cluster.runtime_url(migrated_database), redis_url=server.url
        )
        app = create_app(settings)
        async with running(app) as client:
            assert (await client.get("/health/ready")).status_code == 200
            server.process.kill()
            server.process.wait(timeout=30)
            down = await client.get("/health/ready")
            assert down.status_code == 503
            assert down.json() == {
                "status": "unavailable",
                "checks": {"postgres": "ok", "redis": "failed"},
            }
            assert server.password not in down.text
            assert (await client.get("/health/live")).status_code == 200
    # Shutdown with a dead Redis still completes and releases PostgreSQL.
    assert app.state.runtime.state is RuntimeState.STOPPED
    assert _service_connections(postgres_cluster, migrated_database, settings) == 0


async def test_request_session_commits_on_success_and_rolls_back_on_error(
    live_settings: ApiSettings,
    probe_table: str,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
) -> None:
    app = create_app(live_settings)
    router = APIRouter()

    @router.post("/__probe/write/{marker}")
    async def write(
        marker: str, session: DbSessionDependency, fail: bool = False
    ) -> dict[str, Any]:
        await session.execute(text(probe_table), {"marker": marker})
        await session.flush()
        if fail:
            raise RuntimeError("handler failed after writing")
        return {"written": marker}

    app.include_router(router)
    async with running(app) as client:
        ok = await client.post("/__probe/write/kept")
        failed = await client.post("/__probe/write/discarded", params={"fail": "true"})
        assert app.state.runtime.database.checked_out_connections() == 0
    assert ok.status_code == 200
    assert failed.status_code == 500
    assert failed.json()["error"]["code"] == "INTERNAL_ERROR"
    assert "handler failed" not in failed.text
    assert count_markers(postgres_cluster, migrated_database, "kept") == 1
    assert count_markers(postgres_cluster, migrated_database, "discarded") == 0


DEFERRED_PROBE_DDL = (
    "CREATE TABLE d0_probe.deferred_probe ("
    " id integer, CONSTRAINT uq_deferred_probe UNIQUE (id) DEFERRABLE INITIALLY DEFERRED)"
)
DEFERRED_PROBE_GRANT = "GRANT SELECT, INSERT ON d0_probe.deferred_probe TO app_api"
DEFERRED_PROBE_INSERT = "INSERT INTO d0_probe.deferred_probe (id) VALUES (1)"


async def test_commit_failure_is_reported_before_the_response_is_sent(
    live_settings: ApiSettings,
    probe_table: str,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
) -> None:
    # A deferred constraint only fails at COMMIT, after the endpoint has returned.
    with postgres_cluster.admin_connect(migrated_database) as connection:
        connection.execute(DEFERRED_PROBE_DDL)
        connection.execute(DEFERRED_PROBE_GRANT)
    app = create_app(live_settings)
    router = APIRouter()

    @router.post("/__probe/deferred")
    async def deferred(session: DbSessionDependency) -> dict[str, str]:
        await session.execute(text(DEFERRED_PROBE_INSERT))
        await session.execute(text(DEFERRED_PROBE_INSERT))
        return {"status": "endpoint returned"}

    app.include_router(router)
    async with running(app) as client:
        response = await client.post("/__probe/deferred")
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "INTERNAL_ERROR"
    assert "endpoint returned" not in response.text
    with postgres_cluster.admin_connect(migrated_database) as connection:
        row = connection.execute("SELECT count(*) FROM d0_probe.deferred_probe").fetchone()
    assert row is not None and row[0] == 0
