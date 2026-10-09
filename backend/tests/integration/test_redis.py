"""The base Redis client against a real redis-server."""

from __future__ import annotations

import secrets

import pytest
from redis import Redis

from tests.support.infrastructure import HOST, RedisServer, free_port, redis_server
from tests.support.network import FakeRespServer
from voice_agent.platform.config.base_settings import RedisSettings
from voice_agent.platform.infrastructure.cache.redis_client import RedisClient
from voice_agent.platform.shared_kernel.errors import CacheError

pytestmark = pytest.mark.integration

CLIENT_NAME = "d0-redis-test"


def _settings(url: str) -> RedisSettings:
    return RedisSettings.model_validate(
        {"url": url, "socket_timeout_seconds": 2, "socket_connect_timeout_seconds": 2}
    )


def _named_clients(server: RedisServer) -> int:
    with Redis(host=HOST, port=server.port, password=server.password) as admin:
        return sum(1 for client in admin.client_list() if client.get("name") == CLIENT_NAME)


async def test_ping_and_minimum_version(redis_service: RedisServer) -> None:
    client = RedisClient(_settings(redis_service.url), client_name=CLIENT_NAME)
    try:
        await client.ping(timeout_seconds=5)
        report = await client.verify_baseline(timeout_seconds=5)
    finally:
        await client.close()
    major, minor = (int(part) for part in report.server_version.split(".")[:2])
    assert (major, minor) >= (7, 2)


async def test_construction_opens_no_connection_and_close_releases_all(
    redis_service: RedisServer,
) -> None:
    client = RedisClient(_settings(redis_service.url), client_name=CLIENT_NAME)
    assert _named_clients(redis_service) == 0
    await client.ping(timeout_seconds=5)
    assert _named_clients(redis_service) == 1
    await client.close()
    await client.close()  # idempotent
    assert client.is_closed
    assert _named_clients(redis_service) == 0
    with pytest.raises(CacheError):
        await client.ping(timeout_seconds=1)


async def test_offline_redis_raises_cache_error_without_credentials() -> None:
    password = secrets.token_urlsafe(16)
    client = RedisClient(
        _settings(f"redis://:{password}@{HOST}:{free_port()}/0"), client_name=CLIENT_NAME
    )
    try:
        with pytest.raises(CacheError) as raised:
            await client.verify_baseline(timeout_seconds=3)
    finally:
        await client.close()
    assert password not in str(raised.value)
    assert password not in repr(raised.value.context)


async def test_wrong_password_raises_cache_error(redis_service: RedisServer) -> None:
    client = RedisClient(
        _settings(f"redis://:wrong-{secrets.token_hex(4)}@{HOST}:{redis_service.port}/0"),
        client_name=CLIENT_NAME,
    )
    try:
        with pytest.raises(CacheError):
            await client.ping(timeout_seconds=3)
    finally:
        await client.close()


async def test_server_loss_after_connect_is_detected() -> None:
    with redis_server() as server:
        client = RedisClient(_settings(server.url), client_name=CLIENT_NAME)
        try:
            await client.ping(timeout_seconds=5)
            server.process.kill()
            server.process.wait(timeout=30)
            with pytest.raises(CacheError):
                await client.ping(timeout_seconds=3)
        finally:
            await client.close()


# ---------------------------------------------------------------- D0-P1-05 / D0-M-03


def test_harness_never_exposes_the_redis_password(redis_service: RedisServer) -> None:
    assert redis_service.password not in repr(redis_service)
    assert redis_service.password not in repr(redis_service.process)
    assert redis_service.password not in " ".join(map(str, redis_service.process.args))  # type: ignore[arg-type]


async def test_a_peer_answering_pong_passes_the_fake_handshake() -> None:
    # Control: proves the fake peer is a usable Redis stand-in, so the failures
    # below are caused by the PING reply alone.
    server = FakeRespServer(b"+PONG\r\n")
    await server.start()
    client = RedisClient(_settings(server.url), client_name=CLIENT_NAME)
    try:
        await client.ping(timeout_seconds=3)
        report = await client.verify_baseline(timeout_seconds=3)
    finally:
        await client.close()
        await server.close()
    assert report.server_version == "7.2.4"


@pytest.mark.parametrize(
    "reply",
    [
        b"+NOTPONG\r\n",
        b"+OK\r\n",
        b":1\r\n",
        b"$-1\r\n",
        b"$4\r\nPING\r\n",
        b"-ERR no\r\n",
        b"?x\r\n",
    ],
    ids=["other-status", "ok", "integer", "null", "echo", "error", "malformed-type-byte"],
)
async def test_a_peer_not_answering_pong_fails_ping_and_startup_verification(reply: bytes) -> None:
    server = FakeRespServer(reply)
    await server.start()
    client = RedisClient(_settings(server.url), client_name=CLIENT_NAME)
    try:
        with pytest.raises(CacheError) as raised:
            await client.ping(timeout_seconds=3)
        with pytest.raises(CacheError):
            await client.verify_baseline(timeout_seconds=3)
    finally:
        await client.close()
        await server.close()
    assert server.pings >= 1
    assert "NOTPONG" not in str(raised.value) and "NOTPONG" not in repr(raised.value.context)


async def test_a_silent_peer_times_out_as_a_cache_error() -> None:
    server = FakeRespServer(None)
    await server.start()
    client = RedisClient(_settings(server.url), client_name=CLIENT_NAME)
    try:
        with pytest.raises(CacheError) as raised:
            await client.ping(timeout_seconds=0.5)
    finally:
        await client.close()
        await server.close()
    assert raised.value.context["reason"] == "redis_unreachable"
