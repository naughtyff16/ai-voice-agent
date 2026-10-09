"""Typed, validated, immutable process configuration (3A §9).

Ownership: these settings describe the *process* and the infrastructure it
connects to. Tenant and product configuration belongs in the database and is
never read from the process environment.

Environment variable names follow the nested ``__`` delimiter frozen in 3A §9.1
and 3F §4.1, e.g. ``DATABASE__URL`` and ``REDIS__URL``.
"""

from __future__ import annotations

import ipaddress
import re
from dataclasses import dataclass
from typing import Final, Literal, Self
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL, make_url
from sqlalchemy.exc import ArgumentError

Environment = Literal["local", "test", "staging", "production"]

# Environments that carry real tenants or mirror the topology that does.
PRODUCTION_LIKE_ENVIRONMENTS: Final[frozenset[str]] = frozenset({"staging", "production"})

DATABASE_DRIVER: Final = "postgresql+asyncpg"

# ENVIRONMENT=test only ever accepts a database carrying this prefix, so a test
# run cannot be pointed at a development, shared or production database.
TEST_DATABASE_NAME_PREFIX: Final = "voice_agent_test_"

# Identities the application runtime must never connect as (5A §1.3, §26.2):
# the cluster superuser, the migration runner and the RLS-bypassing admin role.
FORBIDDEN_RUNTIME_DATABASE_USERS: Final[frozenset[str]] = frozenset(
    {"postgres", "app_migration", "app_platform_admin"}
)

_DATABASE_TLS_MODES: Final[frozenset[str]] = frozenset({"require", "verify-ca", "verify-full"})
_DATABASE_SSL_VALUES: Final[frozenset[str]] = frozenset(
    {"disable", "allow", "prefer", *_DATABASE_TLS_MODES}
)

# The only query parameter DATABASE__URL may carry. SQLAlchemy forwards every URL
# query parameter to asyncpg.connect() as a keyword argument, and parameters such
# as database, host, port, user, service or servicefile would silently replace the
# identity validated below. Everything else is therefore refused.
PERMITTED_DATABASE_URL_QUERY_PARAMETERS: Final[frozenset[str]] = frozenset({"ssl"})
DEFAULT_POSTGRES_PORT: Final = 5432

_HOSTNAME: Final = re.compile(
    r"^(?=.{1,253}$)[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?"
    r"(?:\.[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$"
)


def is_single_host(host: str) -> bool:
    """One DNS name or IP address: no host list, socket path or other target form."""
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return _HOSTNAME.fullmatch(host) is not None
    return True


@dataclass(frozen=True, slots=True)
class DatabaseTarget:
    """The connection identity the runtime actually connects with.

    ``create_database_engine`` passes every field to the driver explicitly, so
    neither a URL option nor a libpq environment variable (``PGHOST``,
    ``PGPORT``, ``PGDATABASE``, ``PGUSER``, ``PGSERVICE``) can change it.
    """

    host: str
    port: int
    database: str
    user: str


class DatabaseSettings(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    url: SecretStr
    # Pool defaults are the per-pod values frozen in 3F §15.1.
    pool_size: int = Field(default=10, ge=1, le=100)
    max_overflow: int = Field(default=5, ge=0, le=100)
    pool_timeout_seconds: float = Field(default=10.0, gt=0, le=60)
    pool_recycle_seconds: int = Field(default=1800, ge=60)
    connect_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    command_timeout_seconds: float = Field(default=30.0, gt=0, le=300)

    @field_validator("url")
    @classmethod
    def _validate_url(cls, value: SecretStr) -> SecretStr:
        # Messages never echo the URL or its query: either may contain a secret.
        try:
            url = make_url(value.get_secret_value())
            port = url.port
        except (ArgumentError, ValueError):
            raise ValueError("is not a valid database URL") from None
        if url.drivername != DATABASE_DRIVER:
            raise ValueError(f"must use the {DATABASE_DRIVER} driver")
        if not url.host or not url.database or not url.username:
            raise ValueError("must include a host, a database name and a username")
        if not is_single_host(url.host):
            raise ValueError(
                "must name exactly one host (a DNS name or IP address); host lists "
                "and socket paths are not supported"
            )
        if port is not None and not 1 <= port <= 65535:
            raise ValueError("must use a port between 1 and 65535")
        if set(url.query) - PERMITTED_DATABASE_URL_QUERY_PARAMETERS:
            raise ValueError(
                "must not carry query parameters other than ssl: other driver "
                "options can redirect the connection to a different host, port, "
                "database or role"
            )
        ssl = url.query.get("ssl")
        if ssl is not None and (not isinstance(ssl, str) or ssl not in _DATABASE_SSL_VALUES):
            raise ValueError(
                "must set ssl at most once, to disable, allow, prefer, require, "
                "verify-ca or verify-full"
            )
        if url.username in FORBIDDEN_RUNTIME_DATABASE_USERS:
            raise ValueError(
                "must not use a superuser, migration or platform-admin role "
                "as the application runtime identity"
            )
        return value

    def sqlalchemy_url(self) -> URL:
        return make_url(self.url.get_secret_value())

    def target(self) -> DatabaseTarget:
        """The validated identity; URL validation guarantees every part exists."""
        url = self.sqlalchemy_url()
        if url.host is None or url.database is None or url.username is None:
            raise ValueError("database URL is incomplete")  # unreachable after validation
        return DatabaseTarget(
            host=url.host,
            port=url.port or DEFAULT_POSTGRES_PORT,
            database=url.database,
            user=url.username,
        )


class RedisSettings(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    url: SecretStr
    max_connections: int = Field(default=50, ge=1, le=1000)
    socket_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    socket_connect_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    health_check_interval_seconds: int = Field(default=30, ge=0, le=300)

    @field_validator("url")
    @classmethod
    def _validate_url(cls, value: SecretStr) -> SecretStr:
        try:
            parts = urlsplit(value.get_secret_value())
            _ = parts.port
        except ValueError:
            raise ValueError("is not a valid Redis URL") from None
        if parts.scheme not in {"redis", "rediss"}:
            raise ValueError("must use the redis:// or rediss:// scheme")
        if not parts.hostname:
            raise ValueError("must include a host")
        if parts.query or parts.fragment:
            # redis-py turns URL query parameters into client arguments, including
            # ones that weaken the connection (e.g. ssl_cert_reqs=none). Tuning
            # belongs in the typed REDIS__* settings instead.
            raise ValueError(
                "must not carry query parameters or a fragment; use the REDIS__* settings"
            )
        return value

    def uses_tls(self) -> bool:
        return urlsplit(self.url.get_secret_value()).scheme == "rediss"


class ObservabilitySettings(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    # "json" is the machine-readable production form; "console" is for local terminals.
    log_format: Literal["json", "console"] = "json"


class BaseAppSettings(BaseSettings):
    """Settings shared by every deployable (api, voice_gateway, worker)."""

    model_config = SettingsConfigDict(
        env_nested_delimiter="__",
        frozen=True,
        hide_input_in_errors=True,
    )

    # No default: the environment is always stated explicitly, never assumed.
    environment: Environment
    service_name: str = Field(default="voice-agent", pattern=r"^[a-z][a-z0-9-]{1,62}$")
    database: DatabaseSettings
    redis: RedisSettings
    observability: ObservabilitySettings = ObservabilitySettings()

    @property
    def is_production_like(self) -> bool:
        return self.environment in PRODUCTION_LIKE_ENVIRONMENTS

    @model_validator(mode="after")
    def _enforce_environment_rules(self) -> Self:
        database_url = self.database.sqlalchemy_url()
        # Checked against the effective target, which the URL cannot override (target()).
        if self.environment == "test" and not self.database.target().database.startswith(
            TEST_DATABASE_NAME_PREFIX
        ):
            raise ValueError(
                f"ENVIRONMENT=test requires a database named {TEST_DATABASE_NAME_PREFIX}*"
            )
        if self.is_production_like:
            # 5A §26.3: TLS is enforced for every PostgreSQL and Redis connection.
            if database_url.query.get("ssl") not in _DATABASE_TLS_MODES:
                raise ValueError(
                    f"{self.environment} requires TLS to PostgreSQL: set the ssl query "
                    "parameter of DATABASE__URL to require, verify-ca or verify-full"
                )
            if not self.redis.uses_tls():
                raise ValueError(
                    f"{self.environment} requires TLS to Redis: REDIS__URL must use rediss://"
                )
            if self.observability.log_format != "json":
                raise ValueError(f"{self.environment} requires OBSERVABILITY__LOG_FORMAT=json")
            if self.observability.log_level == "DEBUG":
                raise ValueError(f"{self.environment} must not run at DEBUG log level")
        return self
