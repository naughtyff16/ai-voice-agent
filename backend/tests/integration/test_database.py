"""The session/transaction contract against real PostgreSQL."""

from __future__ import annotations

import asyncio
import secrets

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from tests.integration.conftest import count_markers
from tests.support.infrastructure import PostgresCluster, free_port
from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.config.base_settings import DatabaseSettings
from voice_agent.platform.infrastructure.db.engine import create_database_engine
from voice_agent.platform.infrastructure.db.session import Database
from voice_agent.platform.shared_kernel.errors import DatabaseError

pytestmark = pytest.mark.integration


class _Boom(Exception):
    pass


def _database(settings: ApiSettings) -> Database:
    return Database(create_database_engine(settings.database, application_name="d0-db-test"))


async def _insert(database: Database, insert_sql: str, marker: str) -> None:
    async with database.transaction() as session:
        await session.execute(text(insert_sql), {"marker": marker})


async def test_connectivity(live_settings: ApiSettings) -> None:
    database = _database(live_settings)
    try:
        await database.ping(timeout_seconds=5)
        async with database.transaction() as session:
            assert (await session.execute(text("SELECT current_user"))).scalar_one() == "app_api"
    finally:
        await database.dispose()


async def test_successful_block_commits(
    live_settings: ApiSettings,
    probe_table: str,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
) -> None:
    database = _database(live_settings)
    try:
        await _insert(database, probe_table, "committed")
        assert database.checked_out_connections() == 0
    finally:
        await database.dispose()
    assert count_markers(postgres_cluster, migrated_database, "committed") == 1


async def test_raised_exception_rolls_back(
    live_settings: ApiSettings,
    probe_table: str,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
) -> None:
    database = _database(live_settings)
    try:
        with pytest.raises(_Boom):
            async with database.transaction() as session:
                await session.execute(text(probe_table), {"marker": "rolled-back"})
                await session.flush()
                raise _Boom
        assert database.checked_out_connections() == 0
    finally:
        await database.dispose()
    assert count_markers(postgres_cluster, migrated_database, "rolled-back") == 0


async def test_database_error_inside_block_rolls_back_everything(
    live_settings: ApiSettings,
    probe_table: str,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
) -> None:
    database = _database(live_settings)
    try:
        await _insert(database, probe_table, "duplicate")
        with pytest.raises(Exception, match="duplicate key"):
            async with database.transaction() as session:
                await session.execute(text(probe_table), {"marker": "first-half"})
                await session.execute(text(probe_table), {"marker": "duplicate"})
        assert database.checked_out_connections() == 0
    finally:
        await database.dispose()
    assert count_markers(postgres_cluster, migrated_database, "first-half") == 0


async def test_cancellation_rolls_back_and_returns_the_connection(
    live_settings: ApiSettings,
    probe_table: str,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
) -> None:
    database = _database(live_settings)
    inserted = asyncio.Event()

    async def slow_writer() -> None:
        async with database.transaction() as session:
            await session.execute(text(probe_table), {"marker": "cancelled"})
            inserted.set()
            await session.execute(text("SELECT pg_sleep(30)"))

    try:
        task = asyncio.create_task(slow_writer())
        await inserted.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert database.checked_out_connections() == 0
        await database.ping(timeout_seconds=5)
    finally:
        await database.dispose()
    assert count_markers(postgres_cluster, migrated_database, "cancelled") == 0


async def test_concurrent_transactions_never_share_a_connection(live_settings: ApiSettings) -> None:
    database = _database(live_settings)
    barrier = asyncio.Barrier(2)

    async def backend_pid() -> int:
        async with database.transaction() as session:
            pid = int((await session.execute(text("SELECT pg_backend_pid()"))).scalar_one())
            await barrier.wait()  # both transactions are open at the same time
            return pid

    try:
        first, second = await asyncio.gather(backend_pid(), backend_pid())
    finally:
        await database.dispose()
    assert first != second


async def test_session_initializers_run_inside_each_transaction(live_settings: ApiSettings) -> None:
    # The seam later used for SET LOCAL app.tenant_id: transaction-scoped, never leaking
    # to the next transaction on the same pooled connection.
    calls = 0

    async def set_marker_once(session: AsyncSession) -> None:
        nonlocal calls
        calls += 1
        if calls == 1:
            await session.execute(text("SELECT set_config('d0.marker', 'scoped', true)"))

    single_connection = live_settings.database.model_copy(update={"pool_size": 1})
    database = Database(
        create_database_engine(single_connection, application_name="d0-db-test"),
        session_initializers=[set_marker_once],
    )
    read_marker = text("SELECT current_setting('d0.marker', true)")
    try:
        async with database.transaction() as session:
            first_pid = (await session.execute(text("SELECT pg_backend_pid()"))).scalar_one()
            assert (await session.execute(read_marker)).scalar_one() == "scoped"
        async with database.transaction() as session:
            second_pid = (await session.execute(text("SELECT pg_backend_pid()"))).scalar_one()
            assert (await session.execute(read_marker)).scalar_one() in (None, "")
    finally:
        await database.dispose()
    assert first_pid == second_pid
    assert calls == 2


async def test_unreachable_database_raises_database_error() -> None:
    password = secrets.token_urlsafe(16)
    settings = DatabaseSettings.model_validate(
        {
            "url": f"postgresql+asyncpg://app_api:{password}@127.0.0.1:{free_port()}/voice_agent_test_none",
            "connect_timeout_seconds": 2,
        }
    )
    database = Database(create_database_engine(settings, application_name="d0-db-test"))
    try:
        with pytest.raises(DatabaseError) as raised:
            await database.ping(timeout_seconds=5)
    finally:
        await database.dispose()
    assert password not in str(raised.value) and password not in repr(raised.value.context)


async def test_disposed_database_refuses_new_work(live_settings: ApiSettings) -> None:
    database = _database(live_settings)
    await database.dispose()
    await database.dispose()  # idempotent
    with pytest.raises(DatabaseError):
        async with database.transaction():
            pass
    with pytest.raises(DatabaseError):
        await database.ping(timeout_seconds=1)
