"""Base Redis client for the shared hot tier.

This is connection management only. It deliberately exposes no key operations:
tenant-namespaced access (3A §6.3) and the Streams event transport (7E, which
runs on its own dedicated cluster) are added by their owning phases. Nothing
here can flush or enumerate a keyspace.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable
from dataclasses import dataclass
from typing import Final, cast

from redis.asyncio import Redis
from redis.exceptions import RedisError

from voice_agent.platform.config.base_settings import RedisSettings
from voice_agent.platform.shared_kernel.errors import CacheError

# WAITAOF, on which the frozen event transport depends, does not exist before 7.2 (7E TOPO-01).
MINIMUM_REDIS_VERSION: Final[tuple[int, int]] = (7, 2)


@dataclass(frozen=True, slots=True)
class RedisBaselineReport:
    server_version: str


class RedisClient:
    """Owns one connection pool. Created and closed by ``InfrastructureRuntime``."""

    def __init__(self, settings: RedisSettings, *, client_name: str) -> None:
        # from_url() builds the pool lazily: no socket is opened here. A rediss://
        # URL enables TLS with certificate verification required.
        self._redis: Redis = Redis.from_url(
            settings.url.get_secret_value(),
            max_connections=settings.max_connections,
            socket_timeout=settings.socket_timeout_seconds,
            socket_connect_timeout=settings.socket_connect_timeout_seconds,
            health_check_interval=settings.health_check_interval_seconds,
            client_name=client_name,
        )
        # _closing refuses new work as soon as close() begins; _closed is set only
        # once the pool is actually released, so an interrupted close can be retried.
        self._closing = False
        self._closed = False

    async def ping(self, *, timeout_seconds: float) -> None:
        """Prove the server answers PING with PONG, or raise ``CacheError``.

        redis-py turns the reply into ``True`` only for ``PONG``; any other
        well-formed reply becomes ``False`` and a malformed one raises. Only an
        exact ``True`` counts as healthy. The raw reply is never exposed.
        """
        if self._closing:
            raise CacheError("The Redis client has been closed.")
        try:
            async with asyncio.timeout(timeout_seconds):
                # redis-py annotates commands for its sync and asyncio clients at once
                # (Awaitable[T] | T); on redis.asyncio.Redis the result is always awaitable.
                reply = await cast("Awaitable[object]", self._redis.ping())
        except (RedisError, OSError, TimeoutError) as exc:
            raise CacheError(
                "Redis is not reachable.",
                context={"reason": "redis_unreachable", "error_type": type(exc).__name__},
            ) from exc
        if reply is not True:
            raise CacheError(
                "Redis answered PING with an unexpected reply.",
                context={"reason": "redis_ping_unexpected_reply"},
            )

    async def verify_baseline(self, *, timeout_seconds: float) -> RedisBaselineReport:
        """Check connectivity and the minimum server version. Run once at startup."""
        await self.ping(timeout_seconds=timeout_seconds)
        try:
            async with asyncio.timeout(timeout_seconds):
                server_info = await self._redis.info("server")
        except (RedisError, OSError, TimeoutError) as exc:
            raise CacheError(
                "Redis server information is not available.",
                context={"reason": "redis_info_unavailable", "error_type": type(exc).__name__},
            ) from exc
        version = str(server_info.get("redis_version", ""))
        if _parse_major_minor(version) < MINIMUM_REDIS_VERSION:
            raise CacheError(
                "Redis is older than the supported minimum.",
                context={"reason": "redis_version_unsupported", "server_version": version},
            )
        return RedisBaselineReport(server_version=version)

    @property
    def is_closed(self) -> bool:
        """True once every pooled connection has been released."""
        return self._closed

    async def close(self) -> None:
        """Close the client and every pooled connection.

        Idempotent once it has completed. If it raises or is cancelled part-way,
        calling it again finishes the release: disconnecting the pool twice is safe.
        """
        if self._closed:
            return
        self._closing = True
        await self._redis.aclose()
        self._closed = True


def _parse_major_minor(version: str) -> tuple[int, int]:
    parts = version.split(".")
    try:
        return int(parts[0]), int(parts[1])
    except (IndexError, ValueError):
        return (0, 0)
