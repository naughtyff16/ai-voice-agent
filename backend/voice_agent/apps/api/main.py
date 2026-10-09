"""Core REST API application factory (3A §3)."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Final

from fastapi import FastAPI

from voice_agent.apps.api import health
from voice_agent.apps.api.middleware.correlation_id import (
    REQUEST_ID_HEADER,
    CorrelationIdMiddleware,
)
from voice_agent.apps.api.middleware.cors import ApiCorsMiddleware
from voice_agent.apps.api.middleware.error_handler import (
    UnhandledErrorMiddleware,
    register_error_handlers,
)
from voice_agent.apps.api.settings import ApiSettings
from voice_agent.platform.infrastructure.observability.logging import (
    configure_logging,
    get_logger,
)
from voice_agent.platform.infrastructure.runtime import InfrastructureRuntime

APP_TITLE: Final = "AI Voice Agent Platform API"
APP_VERSION: Final = "0.1.0"

logger = get_logger(__name__)


def create_app(settings: ApiSettings) -> FastAPI:
    """Build the ASGI application.

    Construction opens no connection. PostgreSQL and Redis are connected in the
    lifespan startup and released in the lifespan shutdown, both owned by the
    single ``InfrastructureRuntime`` created here.
    """
    configure_logging(
        service_name=settings.service_name,
        environment=settings.environment,
        log_level=settings.observability.log_level,
        log_format=settings.observability.log_format,
    )
    runtime = InfrastructureRuntime(settings)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        logger.info("application_starting", environment=settings.environment)
        await runtime.start()
        logger.info("application_started")
        try:
            yield
        finally:
            logger.info("application_stopping")
            await runtime.stop()
            # "stopping" here means a resource could not be released (see runtime.py).
            logger.info("application_stopped", infrastructure_state=runtime.state.value)

    docs_enabled = settings.api.docs_enabled
    app = FastAPI(
        title=APP_TITLE,
        version=APP_VERSION,
        lifespan=lifespan,
        # Never serve framework debug pages; errors go through the handlers below.
        debug=False,
        docs_url="/docs" if docs_enabled else None,
        redoc_url=None,
        openapi_url="/openapi.json" if docs_enabled else None,
    )
    app.state.settings = settings
    app.state.runtime = runtime

    register_error_handlers(app)
    app.include_router(health.router)

    # Added innermost first. Request order: correlation ID → CORS → error capture → routes.
    # Correlation is outermost so that every response, including a preflight that
    # the CORS layer answers itself, carries a request ID; CORS is outside error
    # capture so that error responses also receive the CORS headers.
    app.add_middleware(UnhandledErrorMiddleware)
    if settings.api.cors_allowed_origins:
        app.add_middleware(
            ApiCorsMiddleware,
            allow_origins=list(settings.api.cors_allowed_origins),
            # Bearer-token auth (6A §22): no ambient browser credentials.
            allow_credentials=False,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "If-Match"],
            expose_headers=[REQUEST_ID_HEADER],
        )
    app.add_middleware(CorrelationIdMiddleware)
    return app
