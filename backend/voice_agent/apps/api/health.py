"""Liveness and readiness probes (3F §20.1, 3E §14.6, 6A §7.2).

Both routes are unversioned and unauthenticated, and return only a status
word per dependency: never a DSN, host name, version or exception text.
"""

from __future__ import annotations

from typing import Final

from fastapi import APIRouter
from starlette.responses import JSONResponse

from voice_agent.apps.api.dependencies.infrastructure import (
    ApiSettingsDependency,
    RuntimeDependency,
)

router = APIRouter(tags=["health"])

LIVENESS_PATH: Final = "/health/live"
READINESS_PATH: Final = "/health/ready"
_NO_STORE: Final = {"Cache-Control": "no-store"}


@router.get(LIVENESS_PATH)
async def liveness() -> JSONResponse:
    """The process is running and serving its event loop. Checks no dependency."""
    return JSONResponse({"status": "ok"}, headers=_NO_STORE)


@router.get(READINESS_PATH)
async def readiness(runtime: RuntimeDependency, settings: ApiSettingsDependency) -> JSONResponse:
    """The instance can take traffic: PostgreSQL and Redis both answer now."""
    report = await runtime.check_readiness(timeout_seconds=settings.api.readiness_timeout_seconds)
    return JSONResponse(
        {
            "status": "ok" if report.ready else "unavailable",
            "checks": {name: status.value for name, status in report.checks.items()},
        },
        status_code=200 if report.ready else 503,
        headers=_NO_STORE,
    )
