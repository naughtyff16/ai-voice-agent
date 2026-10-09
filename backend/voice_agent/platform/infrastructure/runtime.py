"""Process-wide infrastructure lifecycle.

``InfrastructureRuntime`` is the single owner of the database engine and the
Redis client. A deployable creates exactly one at startup and stops it at
shutdown; nothing else creates or closes these resources.

Startup failure policy: fail fast. If PostgreSQL or Redis is unreachable, or
does not satisfy the baseline, ``start()`` raises and the process exits
non-zero instead of serving in a degraded state. Once started, a dependency
outage does not stop the process: liveness stays healthy and readiness reports
unavailable until the dependency returns (3F §20.1).

Readiness is operational only: it proves PostgreSQL and Redis answer now. It
does not claim the schema is current; that is the deployment gate's job
(``scripts/db_migrate.py gate``, controlled reconciliation OD-D0-01).

Ownership and release:

* A resource stays referenced from the moment it is created until its own
  release has completed. A release that fails or times out keeps the
  reference, so ``stop()`` can be called again to retry it; the state stays
  ``STOPPING`` and never claims ``STOPPED`` while anything is still owned.
* Release runs in its own task. Cancelling the caller of ``stop()`` (or of a
  failing ``start()``) does not interrupt it: the caller waits until the
  release has finished, and only then is the cancellation re-raised.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from enum import StrEnum
from typing import Final

from voice_agent.platform.config.base_settings import BaseAppSettings
from voice_agent.platform.infrastructure.cache.redis_client import RedisClient
from voice_agent.platform.infrastructure.db.engine import create_database_engine
from voice_agent.platform.infrastructure.db.schema_baseline import verify_database_baseline
from voice_agent.platform.infrastructure.db.session import Database
from voice_agent.platform.infrastructure.observability.logging import get_logger
from voice_agent.platform.shared_kernel.errors import InfrastructureError

logger = get_logger(__name__)

# Upper bound for releasing one resource; a hung close must not block shutdown forever.
RELEASE_TIMEOUT_SECONDS: Final = 15.0


class RuntimeState(StrEnum):
    NEW = "new"
    STARTING = "starting"
    READY = "ready"
    # Release has begun and at least one resource may still be owned.
    STOPPING = "stopping"
    # Every resource has been released.
    STOPPED = "stopped"


class CheckStatus(StrEnum):
    OK = "ok"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass(frozen=True, slots=True)
class ReadinessReport:
    ready: bool
    checks: dict[str, CheckStatus]


class InfrastructureRuntime:
    def __init__(
        self, settings: BaseAppSettings, *, release_timeout_seconds: float = RELEASE_TIMEOUT_SECONDS
    ) -> None:
        self._settings = settings
        self._release_timeout_seconds = release_timeout_seconds
        self._state = RuntimeState.NEW
        self._database: Database | None = None
        self._redis: RedisClient | None = None
        self._release_task: asyncio.Task[None] | None = None

    @property
    def state(self) -> RuntimeState:
        return self._state

    @property
    def owned_resources(self) -> tuple[str, ...]:
        """Resources created and not yet released, in creation order."""
        owned = (("postgres", self._database), ("redis", self._redis))
        return tuple(name for name, resource in owned if resource is not None)

    @property
    def database(self) -> Database:
        if self._state is not RuntimeState.READY or self._database is None:
            raise RuntimeError("Infrastructure is not running.")
        return self._database

    @property
    def redis(self) -> RedisClient:
        if self._state is not RuntimeState.READY or self._redis is None:
            raise RuntimeError("Infrastructure is not running.")
        return self._redis

    async def start(self) -> None:
        """Create and verify every required resource, or release them all and raise."""
        if self._state is not RuntimeState.NEW:
            raise RuntimeError(f"Infrastructure cannot be started from state '{self._state}'.")
        self._state = RuntimeState.STARTING
        settings = self._settings
        logger.info("infrastructure_starting")
        try:
            self._database = Database(
                create_database_engine(settings.database, application_name=settings.service_name)
            )
            database_report = await verify_database_baseline(self._database)
            logger.info(
                "postgres_ready",
                server_version_num=database_report.server_version_num,
                runtime_role=database_report.runtime_role,
                schema_revision_status=database_report.schema_revision_status.value,
            )

            self._redis = RedisClient(settings.redis, client_name=settings.service_name)
            redis_report = await self._redis.verify_baseline(
                timeout_seconds=settings.redis.socket_connect_timeout_seconds
            )
            logger.info("redis_ready", server_version=redis_report.server_version)
        except BaseException as exc:
            if isinstance(exc, InfrastructureError):
                logger.error(
                    "infrastructure_start_failed", error_code=exc.code, error_context=exc.context
                )
            self._state = RuntimeState.STOPPING
            await self._release()
            raise
        self._state = RuntimeState.READY
        logger.info("infrastructure_ready")

    async def stop(self) -> None:
        """Release every owned resource.

        Idempotent and safe after a failed start. If a release failed earlier,
        calling ``stop()`` again retries it.
        """
        if self._state is RuntimeState.NEW:
            self._state = RuntimeState.STOPPED
            return
        if self._state is RuntimeState.STOPPED:
            return
        if self._state is RuntimeState.STARTING:
            raise RuntimeError("Infrastructure is starting; cancel the start to abort it.")
        if self._state is RuntimeState.READY:
            self._state = RuntimeState.STOPPING
            logger.info("infrastructure_stopping")
        await self._release()

    async def check_readiness(self, *, timeout_seconds: float) -> ReadinessReport:
        """Probe each required dependency in order, stopping at the first failure (3E §14.6)."""
        checks = {"postgres": CheckStatus.SKIPPED, "redis": CheckStatus.SKIPPED}
        database, redis = self._database, self._redis
        if self._state is not RuntimeState.READY or database is None or redis is None:
            return ReadinessReport(ready=False, checks=checks)
        try:
            await database.ping(timeout_seconds=timeout_seconds)
            checks["postgres"] = CheckStatus.OK
            await redis.ping(timeout_seconds=timeout_seconds)
            checks["redis"] = CheckStatus.OK
        except InfrastructureError as exc:
            failed = "postgres" if checks["postgres"] is CheckStatus.SKIPPED else "redis"
            checks[failed] = CheckStatus.FAILED
            logger.warning(
                "readiness_check_failed",
                check=failed,
                error_code=exc.code,
                error_context=exc.context,
            )
            return ReadinessReport(ready=False, checks=checks)
        return ReadinessReport(ready=True, checks=checks)

    async def _release(self) -> None:
        """Run (or join) the release task and wait for it, whatever happens to the caller."""
        task = self._release_task
        if task is None or task.done():
            task = asyncio.get_running_loop().create_task(
                self._release_owned_resources(), name="infrastructure-release"
            )
            self._release_task = task
        pending_cancellation: asyncio.CancelledError | None = None
        while not task.done():
            try:
                await asyncio.shield(task)
            except asyncio.CancelledError as cancellation:
                if task.cancelled():
                    # The release itself was cancelled (e.g. event-loop teardown).
                    # Unreleased resources stay owned and the state stays STOPPING.
                    raise
                # The caller was cancelled. Abandoning the release now could orphan
                # a resource, so wait for it to finish and re-raise afterwards.
                pending_cancellation = cancellation
        if pending_cancellation is not None:
            if not task.cancelled():
                task.exception()  # mark any unexpected failure as retrieved
            raise pending_cancellation

    async def _release_owned_resources(self) -> None:
        # Reverse order of creation. A failure to release one resource does not
        # prevent the other from being released.
        if self._redis is not None and await self._release_one(
            self._redis.close, done="redis_closed", failed="redis_close_failed"
        ):
            self._redis = None
        if self._database is not None and await self._release_one(
            self._database.dispose, done="postgres_disposed", failed="postgres_dispose_failed"
        ):
            self._database = None
        retained = self.owned_resources
        if retained:
            logger.error("infrastructure_release_incomplete", retained=list(retained))
            return
        self._state = RuntimeState.STOPPED
        logger.info("infrastructure_stopped")

    async def _release_one(
        self, release: Callable[[], Awaitable[None]], *, done: str, failed: str
    ) -> bool:
        """Release one resource; True once released, False if it must be retried."""
        try:
            async with asyncio.timeout(self._release_timeout_seconds):
                await release()
        except Exception:
            # Logged, and the resource stays owned for a retry. CancelledError is
            # not an Exception: a cancelled release propagates.
            logger.exception(failed)
            return False
        logger.info(done)
        return True
