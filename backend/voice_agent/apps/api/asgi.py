"""Process entrypoint for the ASGI server (3F §3.1).

Server usage::

    uvicorn --factory voice_agent.apps.api.asgi:application

Settings are read when the server calls ``application()``, not at import time,
so importing this module has no side effects.
"""

from __future__ import annotations

from fastapi import FastAPI

from voice_agent.apps.api.main import create_app
from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.config.loader import load_settings


def application() -> FastAPI:
    return create_app(load_settings(ApiSettings))
