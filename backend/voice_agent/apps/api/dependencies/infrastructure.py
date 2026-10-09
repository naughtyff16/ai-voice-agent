"""FastAPI dependencies exposing the process-owned infrastructure (3A §8)."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.infrastructure.runtime import InfrastructureRuntime


def get_api_settings(request: Request) -> ApiSettings:
    settings: ApiSettings = request.app.state.settings
    return settings


def get_runtime(request: Request) -> InfrastructureRuntime:
    runtime: InfrastructureRuntime = request.app.state.runtime
    return runtime


async def get_db_session(
    runtime: Annotated[InfrastructureRuntime, Depends(get_runtime)],
) -> AsyncIterator[AsyncSession]:
    """One session and one transaction per request.

    The transaction commits after the endpoint returns and rolls back if it
    raises. The session is never shared with another request.
    """
    async with runtime.database.transaction() as session:
        yield session


ApiSettingsDependency = Annotated[ApiSettings, Depends(get_api_settings)]
RuntimeDependency = Annotated[InfrastructureRuntime, Depends(get_runtime)]
# scope="function" ends the dependency, and so commits, before the response is
# sent. With the default request scope the commit would run after the status
# line is on the wire, and a failed commit could follow a success response.
DbSessionDependency = Annotated[AsyncSession, Depends(get_db_session, scope="function")]
