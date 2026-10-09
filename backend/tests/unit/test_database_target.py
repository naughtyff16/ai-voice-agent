"""The runtime database identity is validated where the driver actually connects (D0-P1-02).

SQLAlchemy forwards every URL query parameter to ``asyncpg.connect()``, and
asyncpg falls back to libpq environment variables for anything not given
explicitly. These tests therefore inspect the keyword arguments the engine
really passes to asyncpg, and resolve them with asyncpg's own target parser,
instead of trusting the parsed URL.
"""

from __future__ import annotations

import secrets
from pathlib import Path
from typing import Any

import asyncpg
import pytest
from asyncpg import connect_utils
from pydantic import ValidationError

from tests.conftest import make_settings
from voice_agent.platform.config.base_settings import DatabaseSettings, DatabaseTarget
from voice_agent.platform.infrastructure.db.engine import create_database_engine

pytestmark = pytest.mark.unit

PASSWORD = secrets.token_urlsafe(16)
BASE = f"postgresql+asyncpg://app_api:{PASSWORD}@127.0.0.1:5432/voice_agent_test_unit"
REDIS_URL = f"redis://:{PASSWORD}@127.0.0.1:6379/0"


@pytest.mark.parametrize(
    "query",
    [
        "database=voice_agent_prod",
        "dbname=voice_agent_prod",
        "host=prod.example.com",
        "hostaddr=10.0.0.5",
        "port=6543",
        "user=postgres",
        "username=postgres",
        "service=prod",
        "servicefile=/etc/pg_service.conf",
        "passfile=/tmp/pgpass",
        "options=-c%20role%3Dpostgres",
        "dsn=postgresql://prod.example.com/voice_agent_prod",
        "host=a.example.com:5432&host=b.example.com:5432",
        "target_session_attrs=read-write",
        "ssl=require&database=voice_agent_prod",
    ],
)
def test_query_parameters_that_could_redirect_the_identity_are_refused(query: str) -> None:
    with pytest.raises(ValidationError) as raised:
        DatabaseSettings.model_validate({"url": f"{BASE}?{query}"})
    message = str(raised.value)
    assert "query parameters" in message
    assert PASSWORD not in message
    assert "voice_agent_prod" not in message and "prod.example.com" not in message


@pytest.mark.parametrize(
    ("url", "fragment"),
    [
        (
            f"postgresql+asyncpg://app_api:{PASSWORD}@a.example.com,b.example.com/voice_agent_test_x",
            "exactly one host",
        ),
        (
            f"postgresql+asyncpg://app_api:{PASSWORD}@a:5432,b:5432/voice_agent_test_x",
            "not a valid database URL",
        ),
        (
            f"postgresql+asyncpg://app_api:{PASSWORD}@%2Fvar%2Frun%2Fpostgresql/voice_agent_test_x",
            "exactly one host",
        ),
        (f"postgresql+asyncpg://app_api:{PASSWORD}@h:0/voice_agent_test_x", "port"),
        (f"postgresql+asyncpg://app_api:{PASSWORD}@h:70000/voice_agent_test_x", "port"),
        (f"postgresql+asyncpg://app_api:{PASSWORD}@h:port/voice_agent_test_x", "not a valid"),
        (f"{BASE}?ssl=require&ssl=disable", "ssl at most once"),
        (f"{BASE}?ssl=sometimes", "ssl at most once"),
    ],
)
def test_ambiguous_targets_are_refused(url: str, fragment: str) -> None:
    with pytest.raises(ValidationError) as raised:
        DatabaseSettings.model_validate({"url": url})
    assert fragment in str(raised.value)
    assert PASSWORD not in str(raised.value)


def test_a_test_database_path_cannot_resolve_to_another_database() -> None:
    # The exact independent-review reproduction: a validated voice_agent_test_*
    # path with a query parameter naming the production database.
    with pytest.raises(ValidationError, match="query parameters"):
        make_settings(database_url=f"{BASE}?database=voice_agent_prod", redis_url=REDIS_URL)


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        (BASE, DatabaseTarget("127.0.0.1", 5432, "voice_agent_test_unit", "app_api")),
        (
            f"postgresql+asyncpg://app_api:{PASSWORD}@db.internal/voice_agent_dev?ssl=verify-full",
            DatabaseTarget("db.internal", 5432, "voice_agent_dev", "app_api"),
        ),
        (
            f"postgresql+asyncpg://app_api:{PASSWORD}@[::1]:6432/voice_agent_test_v6",
            DatabaseTarget("::1", 6432, "voice_agent_test_v6", "app_api"),
        ),
        (
            f"postgresql+asyncpg://app_worker:{PASSWORD}@postgres_1:5432/voice_agent_dev",
            DatabaseTarget("postgres_1", 5432, "voice_agent_dev", "app_worker"),
        ),
    ],
)
def test_valid_urls_expose_their_target(url: str, expected: DatabaseTarget) -> None:
    assert DatabaseSettings.model_validate({"url": url}).target() == expected


class _Captured(Exception):
    pass


async def _driver_arguments(settings: DatabaseSettings, monkeypatch: pytest.MonkeyPatch) -> Any:
    """The keyword arguments the engine passes to asyncpg.connect(); nothing connects."""
    captured: dict[str, Any] = {}

    async def fake_connect(*args: object, **kwargs: object) -> None:
        assert not args
        captured.update(kwargs)
        raise _Captured

    monkeypatch.setattr(asyncpg, "connect", fake_connect)
    engine = create_database_engine(settings, application_name="d0-target-test")
    try:
        with pytest.raises(_Captured):
            async with engine.connect():
                pass
    finally:
        await engine.dispose()
    return captured


def _resolve_with_asyncpg(arguments: dict[str, Any]) -> tuple[list[tuple[str, int]], str, str]:
    """Run asyncpg's own target resolution (explicit args, then PG* variables, then services)."""
    addresses, params = connect_utils._parse_connect_dsn_and_args(
        dsn=None,
        host=arguments.get("host"),
        port=arguments.get("port"),
        user=arguments.get("user"),
        password=arguments.get("password"),
        passfile=arguments.get("passfile"),
        database=arguments.get("database"),
        ssl=arguments.get("ssl"),
        service=arguments.get("service"),
        servicefile=arguments.get("servicefile"),
        direct_tls=None,
        server_settings=arguments.get("server_settings"),
        target_session_attrs=None,
        krbsrvname=None,
        gsslib=None,
    )
    return [(str(host), int(port)) for host, port in addresses], params.user, params.database


@pytest.fixture
def hostile_libpq_environment(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    service_file = tmp_path / "pg_service.conf"
    service_file.write_text(
        "[prod]\nhost=prod.example.com\nport=6543\ndbname=voice_agent_prod\nuser=postgres\n",
        encoding="utf-8",
    )
    for name, value in {
        "PGHOST": "prod.example.com",
        "PGPORT": "6543",
        "PGDATABASE": "voice_agent_prod",
        "PGUSER": "postgres",
        "PGSERVICE": "prod",
        "PGSERVICEFILE": str(service_file),
    }.items():
        monkeypatch.setenv(name, value)


@pytest.mark.usefixtures("hostile_libpq_environment")
@pytest.mark.parametrize(
    "url",
    # Explicit port, no port (PGPORT must not apply), and the permitted ssl option.
    [BASE, BASE.replace("127.0.0.1:5432", "127.0.0.1"), f"{BASE}?ssl=prefer"],
)
async def test_driver_connects_exactly_to_the_validated_target(
    monkeypatch: pytest.MonkeyPatch, url: str
) -> None:
    settings = DatabaseSettings.model_validate({"url": url})
    arguments = await _driver_arguments(settings, monkeypatch)
    target = settings.target()
    assert (arguments["host"], arguments["port"], arguments["user"], arguments["database"]) == (
        target.host,
        target.port,
        target.user,
        target.database,
    )
    assert "service" not in arguments and "servicefile" not in arguments
    addresses, user, database = _resolve_with_asyncpg(arguments)
    assert addresses == [("127.0.0.1", 5432)]
    assert (user, database) == ("app_api", "voice_agent_test_unit")
