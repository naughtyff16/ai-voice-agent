"""Request/correlation ID assignment — the first stage of the request pipeline (6A §9.1)."""

from __future__ import annotations

from typing import Final

import structlog
from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from voice_agent.platform.shared_kernel.request_context import (
    RequestContext,
    bind_request_context,
    reset_request_context,
)
from voice_agent.platform.utils.id_generator import generate_uuid7

REQUEST_ID_HEADER: Final = "X-Request-ID"


class CorrelationIdMiddleware:
    """Assign a server-generated request ID and expose it to logs and the response.

    The ID is always generated here; a client-supplied value is never trusted.
    Implemented as plain ASGI middleware so the context variable is set in the
    same task that runs the endpoint.
    """

    def __init__(self, app: ASGIApp) -> None:
        self._app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self._app(scope, receive, send)
            return

        request_id = str(generate_uuid7())

        async def send_with_request_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)[REQUEST_ID_HEADER] = request_id
            await send(message)

        token = bind_request_context(RequestContext(request_id=request_id))
        try:
            with structlog.contextvars.bound_contextvars(request_id=request_id):
                await self._app(scope, receive, send_with_request_id)
        finally:
            reset_request_context(token)
