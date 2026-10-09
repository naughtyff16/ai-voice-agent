from __future__ import annotations

import secrets
from pathlib import Path

import pytest
from pydantic import ValidationError

from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.config.loader import load_settings
from voice_agent.platform.shared_kernel.errors import ConfigurationError

pytestmark = pytest.mark.unit

# Generated per run, so the suite contains no password-like literal.
PASSWORD = secrets.token_urlsafe(16)
DB_URL = f"postgresql+asyncpg://app_api:{PASSWORD}@db.internal:5432/voice_agent_dev"
TEST_DB_URL = f"postgresql+asyncpg://app_api:{PASSWORD}@127.0.0.1:5432/voice_agent_test_unit"
REDIS_URL = f"redis://:{PASSWORD}@cache.internal:6379/0"
PROD_DB_URL = f"{DB_URL}?ssl=verify-full"
PROD_REDIS_URL = f"rediss://:{PASSWORD}@cache.internal:6380/0"


def _set_env(monkeypatch: pytest.MonkeyPatch, **values: str) -> None:
    for name, value in values.items():
        monkeypatch.setenv(name, value)


def _load(monkeypatch: pytest.MonkeyPatch, tmp_path: Path, **values: str) -> ApiSettings:
    monkeypatch.chdir(tmp_path)  # no stray .env.local can be picked up
    _set_env(monkeypatch, **values)
    return load_settings(ApiSettings)


def test_valid_local_configuration_parses(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    settings = _load(
        monkeypatch,
        tmp_path,
        ENVIRONMENT="local",
        DATABASE__URL=DB_URL,
        DATABASE__POOL_SIZE="7",
        REDIS__URL=REDIS_URL,
        OBSERVABILITY__LOG_FORMAT="console",
    )
    assert settings.environment == "local"
    assert settings.database.pool_size == 7
    assert settings.observability.log_format == "console"
    assert settings.api.cors_allowed_origins == ()
    assert settings.api.docs_enabled is False
    assert not settings.is_production_like


def test_settings_are_immutable(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    settings = _load(
        monkeypatch, tmp_path, ENVIRONMENT="local", DATABASE__URL=DB_URL, REDIS__URL=REDIS_URL
    )
    with pytest.raises(ValidationError):
        settings.environment = "production"  # type: ignore[misc]  # asserting the frozen guard


@pytest.mark.parametrize(
    ("overrides", "expected_fragment"),
    [
        ({"ENVIRONMENT": ""}, "environment"),
        ({"ENVIRONMENT": "prod"}, "environment"),
        ({"DATABASE__URL": None}, "database"),
        ({"REDIS__URL": None}, "redis"),
        ({"DATABASE__URL": "not a url at all"}, "not a valid database URL"),
        ({"DATABASE__URL": f"postgresql://app_api:{PASSWORD}@h/d"}, "postgresql+asyncpg"),
        ({"DATABASE__URL": "postgresql+asyncpg://app_api@/voice_agent_dev"}, "host"),
        ({"REDIS__URL": "http://cache.internal:6379"}, "redis://"),
        ({"REDIS__URL": "redis://cache.internal:notaport"}, "not a valid Redis URL"),
        ({"REDIS__URL": f"{REDIS_URL}?ssl_cert_reqs=none"}, "query parameters"),
        ({"REDIS__URL": f"{REDIS_URL}?host=other.internal"}, "query parameters"),
        ({"REDIS__URL": f"{REDIS_URL}#frag"}, "query parameters"),
        ({"DATABASE__POOL_SIZE": "0"}, "pool_size"),
        ({"OBSERVABILITY__LOG_LEVEL": "LOUD"}, "log_level"),
    ],
)
def test_invalid_configuration_fails_fast_without_leaking_secrets(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    overrides: dict[str, str | None],
    expected_fragment: str,
) -> None:
    values: dict[str, str | None] = {
        "ENVIRONMENT": "local",
        "DATABASE__URL": DB_URL,
        "REDIS__URL": REDIS_URL,
        **overrides,
    }
    monkeypatch.chdir(tmp_path)
    for name, value in values.items():
        if value is not None:
            monkeypatch.setenv(name, value)
    with pytest.raises(ConfigurationError) as raised:
        load_settings(ApiSettings)
    message = str(raised.value)
    assert expected_fragment.lower() in message.lower()
    assert PASSWORD not in message
    assert raised.value.__cause__ is None
    assert raised.value.__suppress_context__


@pytest.mark.parametrize("user", ["postgres", "app_migration", "app_platform_admin"])
def test_runtime_rejects_privileged_database_identities(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, user: str
) -> None:
    with pytest.raises(ConfigurationError, match="runtime identity"):
        _load(
            monkeypatch,
            tmp_path,
            ENVIRONMENT="local",
            DATABASE__URL=f"postgresql+asyncpg://{user}:{PASSWORD}@h:5432/voice_agent_dev",
            REDIS__URL=REDIS_URL,
        )


def test_test_environment_refuses_a_non_test_database(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    with pytest.raises(ConfigurationError, match="voice_agent_test_"):
        _load(monkeypatch, tmp_path, ENVIRONMENT="test", DATABASE__URL=DB_URL, REDIS__URL=REDIS_URL)
    settings = _load(
        monkeypatch, tmp_path, ENVIRONMENT="test", DATABASE__URL=TEST_DB_URL, REDIS__URL=REDIS_URL
    )
    assert settings.environment == "test"


@pytest.mark.parametrize("environment", ["staging", "production"])
@pytest.mark.parametrize(
    ("overrides", "expected_fragment"),
    [
        ({"DATABASE__URL": DB_URL}, "TLS to PostgreSQL"),
        ({"DATABASE__URL": f"{DB_URL}?ssl=prefer"}, "TLS to PostgreSQL"),
        ({"REDIS__URL": REDIS_URL}, "TLS to Redis"),
        ({"OBSERVABILITY__LOG_FORMAT": "console"}, "LOG_FORMAT=json"),
        ({"OBSERVABILITY__LOG_LEVEL": "DEBUG"}, "DEBUG"),
        ({"API__CORS_ALLOWED_ORIGINS": '["http://app.example.com"]'}, "https://"),
    ],
)
def test_production_like_environments_fail_closed(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    environment: str,
    overrides: dict[str, str],
    expected_fragment: str,
) -> None:
    values = {
        "ENVIRONMENT": environment,
        "DATABASE__URL": PROD_DB_URL,
        "REDIS__URL": PROD_REDIS_URL,
        **overrides,
    }
    with pytest.raises(ConfigurationError, match=expected_fragment):
        _load(monkeypatch, tmp_path, **values)


def test_production_configuration_with_safe_values_parses(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    settings = _load(
        monkeypatch,
        tmp_path,
        ENVIRONMENT="production",
        DATABASE__URL=PROD_DB_URL,
        REDIS__URL=PROD_REDIS_URL,
        API__CORS_ALLOWED_ORIGINS='["https://app.example.com"]',
    )
    assert settings.is_production_like
    assert settings.redis.uses_tls()
    assert settings.api.cors_allowed_origins == ("https://app.example.com",)


@pytest.mark.parametrize(
    "origin",
    [
        "*",
        "https://*.example.com",
        "https://app.example.com/",
        "app.example.com",
        "null",
        # D0-M-01: malformed or unusable ports.
        "https://app.example:notaport",
        "https://app.example:0",
        "https://app.example:65536",
        "https://app.example:99999",
        "https://app.example:+443",
        "https://app.example: 8443",
        "https://app.example:",
        "https://app.example.com:443",
        "http://localhost:80",
        # Credentials, path, query, fragment.
        "https://user:pw@app.example.com",
        "https://user@app.example.com",
        "https://app.example.com/path",
        "https://app.example.com?x=1",
        "https://app.example.com#frag",
        # Scheme and host shape.
        "ftp://app.example.com",
        "https:///app.example.com",
        "https://APP.example.com",
        "HTTPS://app.example.com",
        "https://app..example.com",
        "https://-app.example.com",
        "https://app.example.com.",
        "https://[::1",
        "https://[not-an-ip]:3000",
        " https://app.example.com",
    ],
)
def test_cors_origins_must_be_explicit(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, origin: str
) -> None:
    with pytest.raises(ConfigurationError, match="CORS origin"):
        _load(
            monkeypatch,
            tmp_path,
            ENVIRONMENT="local",
            DATABASE__URL=DB_URL,
            REDIS__URL=REDIS_URL,
            API__CORS_ALLOWED_ORIGINS=f'["{origin}"]',
        )


def test_secrets_never_appear_in_repr_or_serialization(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    settings = _load(
        monkeypatch, tmp_path, ENVIRONMENT="local", DATABASE__URL=DB_URL, REDIS__URL=REDIS_URL
    )
    for rendered in (
        repr(settings),
        str(settings),
        settings.model_dump_json(),
        str(settings.model_dump()),
    ):
        assert PASSWORD not in rendered


def test_dotenv_file_is_read_only_for_local(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    (tmp_path / ".env.local").write_text(
        f"DATABASE__URL={DB_URL}\nREDIS__URL={REDIS_URL}\n", encoding="utf-8"
    )
    local = _load(monkeypatch, tmp_path, ENVIRONMENT="local")
    assert local.database.url.get_secret_value() == DB_URL

    # Outside local the file is ignored, so a missing real variable is still an error.
    with pytest.raises(ConfigurationError, match="database"):
        _load(monkeypatch, tmp_path, ENVIRONMENT="production")


def test_environment_cannot_be_set_from_the_dotenv_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    (tmp_path / ".env.local").write_text(
        f"ENVIRONMENT=local\nDATABASE__URL={DB_URL}\nREDIS__URL={REDIS_URL}\n", encoding="utf-8"
    )
    with pytest.raises(ConfigurationError, match="environment"):
        _load(monkeypatch, tmp_path)


@pytest.mark.parametrize(
    "origin",
    [
        "http://localhost:3000",
        "http://127.0.0.1:5173",
        "http://[::1]:3000",
        "https://app.example.com",
        "https://app.example.com:8443",
        "https://a-b.c-d.example.co:65535",
    ],
)
def test_explicit_local_and_https_origins_are_accepted(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, origin: str
) -> None:
    settings = _load(
        monkeypatch,
        tmp_path,
        ENVIRONMENT="local",
        DATABASE__URL=DB_URL,
        REDIS__URL=REDIS_URL,
        API__CORS_ALLOWED_ORIGINS=f'["{origin}"]',
    )
    assert settings.api.cors_allowed_origins == (origin,)


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_production_like_cors_rejects_malformed_https_ports(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, environment: str
) -> None:
    with pytest.raises(ConfigurationError, match="CORS origin"):
        _load(
            monkeypatch,
            tmp_path,
            ENVIRONMENT=environment,
            DATABASE__URL=PROD_DB_URL,
            REDIS__URL=PROD_REDIS_URL,
            API__CORS_ALLOWED_ORIGINS='["https://app.example:notaport"]',
        )
