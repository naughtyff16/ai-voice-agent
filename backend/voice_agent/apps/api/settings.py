"""Settings for the Core REST API deployable (3A §9.1)."""

from __future__ import annotations

import ipaddress
import re
from typing import Final, Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from voice_agent.platform.config.base_settings import BaseAppSettings

# scheme://host[:port] and nothing else. The host is a DNS name or a bracketed
# IPv6 literal; userinfo, path, query, fragment and wildcards cannot match.
_ORIGIN: Final = re.compile(
    r"^(?P<scheme>https?)://"
    r"(?P<host>\[[0-9a-f:.]+\]|[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)"
    r"(?::(?P<port>[0-9]{1,5}))?$"
)
_DEFAULT_PORTS: Final = {"http": 80, "https": 443}
_ORIGIN_RULE: Final = (
    "each CORS origin must be an explicit, lowercase scheme://host[:port] with an "
    "http or https scheme, a port between 1 and 65535 (default ports omitted), and "
    "no wildcard, credentials, path, query or fragment"
)


def _is_valid_origin(origin: str) -> bool:
    match = _ORIGIN.fullmatch(origin)
    if match is None:
        return False
    host = match["host"]
    if host.startswith("["):
        try:
            ipaddress.IPv6Address(host[1:-1])
        except ValueError:
            return False
    port = match["port"]
    if port is None:
        return True
    number = int(port)
    # Browsers omit a default port from the Origin header, so an origin spelling
    # it out would never match a request.
    return 1 <= number <= 65535 and number != _DEFAULT_PORTS[match["scheme"]]


class ApiHttpSettings(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    # Explicit browser origins allowed to call the API (6A §22). Empty means no
    # cross-origin access at all, which is the default in every environment.
    cors_allowed_origins: tuple[str, ...] = ()
    # Interactive API documentation is off unless explicitly enabled.
    docs_enabled: bool = False
    readiness_timeout_seconds: float = Field(default=2.0, gt=0, le=30)

    @field_validator("cors_allowed_origins")
    @classmethod
    def _validate_origins(cls, origins: tuple[str, ...]) -> tuple[str, ...]:
        if not all(_is_valid_origin(origin) for origin in origins):
            raise ValueError(_ORIGIN_RULE)
        return origins


class ApiSettings(BaseAppSettings):
    api: ApiHttpSettings = ApiHttpSettings()

    @model_validator(mode="after")
    def _enforce_api_environment_rules(self) -> Self:
        if self.is_production_like and any(
            not origin.startswith("https://") for origin in self.api.cors_allowed_origins
        ):
            raise ValueError(f"{self.environment} requires https:// CORS origins")
        return self
