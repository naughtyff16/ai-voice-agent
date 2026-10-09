"""Root of the platform error hierarchy (3A §12.1)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import ClassVar


class PlatformError(Exception):
    """Base class for every error the platform raises deliberately.

    ``code`` is a stable internal identifier used in logs. ``context`` is
    structured diagnostic data for logs only: it is never serialized into a
    client response (3A §12.1, 6A §24.3).
    """

    code: ClassVar[str] = "platform_error"

    def __init__(self, message: str, *, context: Mapping[str, object] | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.context: dict[str, object] = dict(context or {})


class ConfigurationError(PlatformError):
    """Process configuration is missing or invalid; the process must not start (3A §9.3)."""

    code = "configuration_invalid"
