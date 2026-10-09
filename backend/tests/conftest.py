"""Shared fixtures.

Event-loop strategy: pytest-asyncio gives every test its own event loop
(function scope). Anything bound to a loop — engines, Redis clients, the
application runtime — is created inside the test that uses it and closed
before it ends. Session-scoped fixtures are synchronous process handles only,
so no asyncio object ever crosses a loop.
"""

from __future__ import annotations

import os
import random
from collections.abc import Iterator

import pytest

from tests.support.infrastructure import (
    InfrastructureUnavailableError,
    PostgresCluster,
    RedisServer,
    start_postgres_cluster,
    start_redis_server,
)
from voice_agent.apps.api.settings import ApiSettings

# Settings a developer shell may export. Cleared for every test so no test can
# pick up a real database or Redis endpoint from the surrounding environment.
_CONFIG_ENV_PREFIXES = (
    "ENVIRONMENT",
    "SERVICE_NAME",
    "DATABASE__",
    "REDIS__",
    "OBSERVABILITY__",
    "API__",
    "MIGRATION_DATABASE_URL",
)
_CATEGORY_MARKERS = frozenset({"unit", "integration", "smoke"})


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--test-order",
        default="normal",
        help="normal, reverse, or random:<seed> — proves tests do not depend on run order",
    )


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    """Every test belongs to exactly one category, so `-m` selections are complete."""
    for item in items:
        categories = {marker.name for marker in item.iter_markers()} & _CATEGORY_MARKERS
        if len(categories) != 1:
            raise pytest.UsageError(
                f"{item.nodeid} must carry exactly one of {sorted(_CATEGORY_MARKERS)}"
            )
    order = str(config.getoption("--test-order"))
    if order == "reverse":
        items.reverse()
    elif order.startswith("random:"):
        # Deterministic shuffle for reproducible order checks; not a security use.
        random.Random(int(order.removeprefix("random:"))).shuffle(items)  # noqa: S311
    elif order != "normal":
        raise pytest.UsageError("--test-order must be normal, reverse or random:<seed>")


@pytest.fixture(autouse=True)
def _isolated_config_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in list(os.environ):
        if name.upper().startswith(_CONFIG_ENV_PREFIXES):
            monkeypatch.delenv(name)


@pytest.fixture(scope="session")
def postgres_cluster() -> Iterator[PostgresCluster]:
    try:
        cluster = start_postgres_cluster()
    except InfrastructureUnavailableError as exc:
        pytest.fail(f"Integration prerequisite missing: {exc}", pytrace=False)
    try:
        yield cluster
    finally:
        cluster.stop()


@pytest.fixture(scope="session")
def redis_service() -> Iterator[RedisServer]:
    try:
        server = start_redis_server()
    except InfrastructureUnavailableError as exc:
        pytest.fail(f"Integration prerequisite missing: {exc}", pytrace=False)
    try:
        yield server
    finally:
        server.stop()


@pytest.fixture
def migrated_database(postgres_cluster: PostgresCluster) -> Iterator[str]:
    """A private copy of the database migrated to the frozen head, dropped after the test."""
    name = postgres_cluster.create_database(template=postgres_cluster.migrated_template())
    try:
        yield name
    finally:
        postgres_cluster.drop_database(name)


def make_settings(*, database_url: str, redis_url: str, **overrides: object) -> ApiSettings:
    values: dict[str, object] = {
        "environment": "test",
        "service_name": "voice-agent-test",
        "database": {
            "url": database_url,
            "pool_size": 2,
            "max_overflow": 0,
            "connect_timeout_seconds": 3,
        },
        "redis": {
            "url": redis_url,
            "socket_timeout_seconds": 2,
            "socket_connect_timeout_seconds": 2,
        },
    }
    values.update(overrides)
    return ApiSettings.model_validate(values)


@pytest.fixture
def live_settings(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> ApiSettings:
    return make_settings(
        database_url=postgres_cluster.runtime_url(migrated_database), redis_url=redis_service.url
    )
