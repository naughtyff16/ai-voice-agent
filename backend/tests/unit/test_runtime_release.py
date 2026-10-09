"""Resource ownership through shutdown, failure and cancellation (D0-P1-01).

The runtime is driven with instrumented stand-ins for the Redis client and the
database so each test can stop a release at an exact point. The same paths are
exercised against real PostgreSQL and Redis in tests/integration/test_runtime.py.
"""

from __future__ import annotations

import asyncio
import secrets
from collections.abc import Iterator
from dataclasses import dataclass, field

import pytest

from tests.conftest import make_settings
from voice_agent.platform.infrastructure import runtime as runtime_module
from voice_agent.platform.infrastructure.cache.redis_client import RedisBaselineReport
from voice_agent.platform.infrastructure.db.schema_baseline import (
    DatabaseBaselineReport,
    SchemaRevisionStatus,
)
from voice_agent.platform.infrastructure.runtime import InfrastructureRuntime, RuntimeState
from voice_agent.platform.shared_kernel.errors import CacheError

pytestmark = pytest.mark.unit

_PASSWORD = secrets.token_urlsafe(12)
SETTINGS = make_settings(
    database_url=f"postgresql+asyncpg://app_api:{_PASSWORD}@127.0.0.1:9/voice_agent_test_unit",
    redis_url=f"redis://:{_PASSWORD}@127.0.0.1:9/0",
)


@dataclass
class _Resource:
    name: str
    journal: list[str]
    # Blocks the release after it has begun, until set.
    gate: asyncio.Event | None = None
    # Blocks after the release has finished its work but before it returns.
    after: asyncio.Event | None = None
    fail_times: int = 0
    calls: int = 0
    released: bool = False
    entered: asyncio.Event = field(default_factory=asyncio.Event)
    finished: asyncio.Event = field(default_factory=asyncio.Event)

    async def release(self) -> None:
        self.calls += 1
        self.journal.append(f"{self.name}:begin")
        self.entered.set()
        if self.gate is not None:
            await self.gate.wait()
        if self.fail_times:
            self.fail_times -= 1
            self.journal.append(f"{self.name}:failed")
            raise OSError(f"{self.name} release failed")
        self.released = True
        self.journal.append(f"{self.name}:done")
        self.finished.set()
        if self.after is not None:
            await self.after.wait()


class _FakeRedis(_Resource):
    verify_error: BaseException | None = None
    verify_gate: asyncio.Event | None = None

    async def close(self) -> None:
        await self.release()

    async def verify_baseline(self, *, timeout_seconds: float) -> RedisBaselineReport:
        del timeout_seconds
        if self.verify_gate is not None:
            await self.verify_gate.wait()
        if self.verify_error is not None:
            raise self.verify_error
        return RedisBaselineReport(server_version="7.2.4")


class _FakeDatabase(_Resource):
    async def dispose(self) -> None:
        await self.release()


@dataclass
class _Harness:
    runtime: InfrastructureRuntime
    redis: _FakeRedis
    database: _FakeDatabase
    journal: list[str]


@pytest.fixture
def harness(monkeypatch: pytest.MonkeyPatch) -> Iterator[_Harness]:
    journal: list[str] = []
    redis = _FakeRedis("redis", journal)
    database = _FakeDatabase("postgres", journal)

    async def verify_database_baseline(_database: object) -> DatabaseBaselineReport:
        return DatabaseBaselineReport(
            server_version_num=180000,
            runtime_role="app_api",
            schema_revision_status=SchemaRevisionStatus.DEPLOYMENT_GATED,
        )

    monkeypatch.setattr(runtime_module, "create_database_engine", lambda *_a, **_k: object())
    monkeypatch.setattr(runtime_module, "Database", lambda _engine: database)
    monkeypatch.setattr(runtime_module, "RedisClient", lambda *_a, **_k: redis)
    monkeypatch.setattr(runtime_module, "verify_database_baseline", verify_database_baseline)
    yield _Harness(InfrastructureRuntime(SETTINGS), redis, database, journal)


def _state(runtime: InfrastructureRuntime) -> RuntimeState:
    # Read through a call so the type checker does not assume the state is unchanged
    # between two assertions; it changes while the release task runs.
    return runtime.state


def _owned(runtime: InfrastructureRuntime) -> tuple[str, ...]:
    return runtime.owned_resources


async def _yield_to_loop(times: int = 5) -> None:
    for _ in range(times):
        await asyncio.sleep(0)


async def _started(harness: _Harness) -> InfrastructureRuntime:
    await harness.runtime.start()
    assert _state(harness.runtime) is RuntimeState.READY
    return harness.runtime


FULL_RELEASE = ["redis:begin", "redis:done", "postgres:begin", "postgres:done"]


async def test_stop_releases_redis_then_postgres_exactly_once(harness: _Harness) -> None:
    runtime = await _started(harness)
    await runtime.stop()
    assert _state(runtime) is RuntimeState.STOPPED
    assert _owned(runtime) == ()
    assert harness.journal == FULL_RELEASE
    await runtime.stop()
    await runtime.stop()
    assert (harness.redis.calls, harness.database.calls) == (1, 1)


@pytest.mark.parametrize("blocked", ["redis", "postgres"])
async def test_cancelling_stop_mid_release_cannot_orphan_a_resource(
    harness: _Harness, blocked: str
) -> None:
    runtime = await _started(harness)
    resource = harness.redis if blocked == "redis" else harness.database
    resource.gate = asyncio.Event()
    stopping = asyncio.create_task(runtime.stop())
    await resource.entered.wait()

    stopping.cancel()
    await _yield_to_loop()
    # The caller keeps waiting: the release must reach a safe state first.
    assert not stopping.done()
    assert _state(runtime) is RuntimeState.STOPPING
    assert blocked in runtime.owned_resources

    resource.gate.set()
    with pytest.raises(asyncio.CancelledError):
        await stopping
    assert _state(runtime) is RuntimeState.STOPPED
    assert _owned(runtime) == ()
    assert harness.journal == FULL_RELEASE

    await runtime.stop()  # idempotent after the cancelled stop
    assert (harness.redis.calls, harness.database.calls) == (1, 1)


async def test_cancelling_stop_between_the_two_releases(harness: _Harness) -> None:
    runtime = await _started(harness)
    harness.redis.after = asyncio.Event()
    stopping = asyncio.create_task(runtime.stop())
    await harness.redis.finished.wait()

    stopping.cancel()
    await _yield_to_loop()
    assert harness.database.calls == 0  # PostgreSQL release has not begun yet
    assert not stopping.done()
    assert _state(runtime) is RuntimeState.STOPPING

    harness.redis.after.set()
    with pytest.raises(asyncio.CancelledError):
        await stopping
    assert harness.journal == FULL_RELEASE
    assert _state(runtime) is RuntimeState.STOPPED


async def test_repeated_cancellation_still_completes_the_release(harness: _Harness) -> None:
    runtime = await _started(harness)
    harness.database.gate = asyncio.Event()
    stopping = asyncio.create_task(runtime.stop())
    await harness.database.entered.wait()
    for _ in range(3):
        stopping.cancel()
        await _yield_to_loop()
    assert not stopping.done()
    harness.database.gate.set()
    with pytest.raises(asyncio.CancelledError):
        await stopping
    assert _state(runtime) is RuntimeState.STOPPED


async def test_failed_release_keeps_ownership_and_can_be_retried(harness: _Harness) -> None:
    runtime = await _started(harness)
    harness.redis.fail_times = 1
    await runtime.stop()
    # PostgreSQL is still released; Redis stays owned and the state says so.
    assert _state(runtime) is RuntimeState.STOPPING
    assert _owned(runtime) == ("redis",)
    assert harness.database.released

    await runtime.stop()
    assert _state(runtime) is RuntimeState.STOPPED
    assert _owned(runtime) == ()
    assert (harness.redis.calls, harness.database.calls) == (2, 1)  # no double dispose


async def test_hung_release_times_out_keeps_ownership_and_can_be_retried(
    harness: _Harness,
) -> None:
    runtime = InfrastructureRuntime(SETTINGS, release_timeout_seconds=0.05)
    await runtime.start()
    harness.database.gate = asyncio.Event()
    await runtime.stop()
    assert _state(runtime) is RuntimeState.STOPPING
    assert _owned(runtime) == ("postgres",)

    harness.database.gate.set()
    await runtime.stop()
    assert _state(runtime) is RuntimeState.STOPPED
    assert harness.database.calls == 2


async def test_cancelled_release_task_keeps_ownership(harness: _Harness) -> None:
    runtime = await _started(harness)
    harness.redis.gate = asyncio.Event()
    stopping = asyncio.create_task(runtime.stop())
    await harness.redis.entered.wait()
    # Simulates event-loop teardown cancelling the release itself.
    release_task = runtime._release_task
    assert release_task is not None
    release_task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await stopping
    assert _state(runtime) is RuntimeState.STOPPING
    assert _owned(runtime) == ("postgres", "redis")

    harness.redis.gate.set()
    await runtime.stop()
    assert _state(runtime) is RuntimeState.STOPPED
    assert _owned(runtime) == ()


async def test_concurrent_stops_share_one_release(harness: _Harness) -> None:
    runtime = await _started(harness)
    harness.redis.gate = asyncio.Event()
    first = asyncio.create_task(runtime.stop())
    await harness.redis.entered.wait()
    second = asyncio.create_task(runtime.stop())
    await _yield_to_loop()
    harness.redis.gate.set()
    await asyncio.gather(first, second)
    assert (harness.redis.calls, harness.database.calls) == (1, 1)
    assert _state(runtime) is RuntimeState.STOPPED


async def test_failed_start_releases_partial_resources(harness: _Harness) -> None:
    harness.redis.verify_error = CacheError("Redis is not reachable.")
    with pytest.raises(CacheError):
        await harness.runtime.start()
    assert _state(harness.runtime) is RuntimeState.STOPPED
    assert harness.journal == FULL_RELEASE


async def test_cancelled_start_releases_partial_resources_before_propagating(
    harness: _Harness,
) -> None:
    harness.redis.verify_gate = asyncio.Event()
    harness.database.gate = asyncio.Event()
    starting = asyncio.create_task(harness.runtime.start())
    await _yield_to_loop()
    starting.cancel()
    await harness.database.entered.wait()
    assert not starting.done()
    assert _state(harness.runtime) is RuntimeState.STOPPING
    harness.database.gate.set()
    with pytest.raises(asyncio.CancelledError):
        await starting
    assert _state(harness.runtime) is RuntimeState.STOPPED
    assert harness.journal == FULL_RELEASE


async def test_stop_while_starting_is_refused(harness: _Harness) -> None:
    harness.redis.verify_gate = asyncio.Event()
    starting = asyncio.create_task(harness.runtime.start())
    await _yield_to_loop()
    with pytest.raises(RuntimeError, match="starting"):
        await harness.runtime.stop()
    harness.redis.verify_gate.set()
    await starting
    await harness.runtime.stop()
    assert _state(harness.runtime) is RuntimeState.STOPPED
