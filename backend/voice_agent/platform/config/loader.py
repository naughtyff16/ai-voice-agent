"""Configuration loading with fail-fast validation (3A §9.3)."""

from __future__ import annotations

import os
from typing import Final

from pydantic import ValidationError

from voice_agent.platform.config.base_settings import BaseAppSettings
from voice_agent.platform.shared_kernel.errors import ConfigurationError

# The dotenv convenience exists for developer machines only (3A §9.2). Every
# other environment is configured exclusively through real environment variables.
LOCAL_ENV_FILE: Final = ".env.local"


def load_settings[SettingsT: BaseAppSettings](settings_cls: type[SettingsT]) -> SettingsT:
    """Build the frozen settings object or raise ``ConfigurationError``.

    ``ENVIRONMENT`` must come from the real process environment: it decides
    whether a dotenv file may be read at all, so it cannot be defined inside one.
    """
    env_file = LOCAL_ENV_FILE if os.environ.get("ENVIRONMENT") == "local" else None
    try:
        return settings_cls(_env_file=env_file)
    except ValidationError as exc:
        # Raised without chaining: the ValidationError may reference raw input values.
        raise ConfigurationError(_describe(exc)) from None


def _describe(exc: ValidationError) -> str:
    problems = [
        f"{'.'.join(str(part) for part in error['loc']) or 'settings'}: {error['msg']}"
        for error in exc.errors(include_input=False, include_url=False, include_context=False)
    ]
    return "Invalid configuration: " + "; ".join(problems)
