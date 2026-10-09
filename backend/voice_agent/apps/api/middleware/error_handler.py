"""Exception → HTTP mapping using the frozen error envelope (6A §24, API-ERROR-CATALOG §3).

Only codes in ``error_catalog.ERROR_CATALOG`` are emitted: the frozen catalog
plus the controlled D0 erratum OD-D0-02 (``METHOD_NOT_ALLOWED``). Diagnostic
detail goes to the structured log, correlated by ``request_id``; a response body
never carries exception text, a traceback or any internal name (6A §24.3).
"""

from __future__ import annotations

from typing import Final

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from voice_agent.apps.api.error_catalog import ApiErrorCode, contract_for
from voice_agent.platform.infrastructure.observability.logging import get_logger
from voice_agent.platform.shared_kernel.errors import (
    CacheError,
    DatabaseError,
    PlatformError,
)
from voice_agent.platform.shared_kernel.request_context import current_request_context

logger = get_logger(__name__)

_UNKNOWN_REQUEST_ID: Final = "unknown"

# Framework-raised HTTP statuses with a cataloged meaning. Any other status
# raised as an HTTPException has no catalog entry and is a programming error.
_HTTP_STATUS_CODES: Final[dict[int, ApiErrorCode]] = {
    400: ApiErrorCode.VALIDATION_ERROR,
    404: ApiErrorCode.RESOURCE_NOT_FOUND,
    405: ApiErrorCode.METHOD_NOT_ALLOWED,
    422: ApiErrorCode.VALIDATION_ERROR,
}


def error_response(code: ApiErrorCode, *, status_code: int | None = None) -> JSONResponse:
    """The standard envelope for ``code``; message and ``retryable`` come from the catalog."""
    status, contract = contract_for(code, status_code)
    context = current_request_context()
    return JSONResponse(
        status_code=status,
        content={
            "error": {
                "code": code.value,
                "message": contract.message,
                # No error family emitted here defines a details schema (catalog §19).
                "details": {},
                "request_id": context.request_id if context else _UNKNOWN_REQUEST_ID,
                "retryable": contract.retryable,
            }
        },
    )


async def _handle_platform_error(_request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, PlatformError):
        raise exc
    if isinstance(exc, DatabaseError | CacheError):
        logger.error("dependency_unavailable", error_code=exc.code, error_context=exc.context)
        return error_response(ApiErrorCode.DEPENDENCY_UNAVAILABLE)
    logger.error(
        "unmapped_platform_error", error_code=exc.code, error_context=exc.context, exc_info=exc
    )
    return error_response(ApiErrorCode.INTERNAL_ERROR)


async def _handle_http_exception(_request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, StarletteHTTPException):
        raise exc
    code = _HTTP_STATUS_CODES.get(exc.status_code)
    if code is None:
        logger.error("uncataloged_http_status", status_code=exc.status_code)
        return error_response(ApiErrorCode.INTERNAL_ERROR)
    response = error_response(code, status_code=exc.status_code)
    # Preserve protocol headers the framework attached, e.g. Allow on a 405.
    if exc.headers:
        response.headers.update(exc.headers)
    return response


async def _handle_request_validation_error(_request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, RequestValidationError):
        raise exc
    # 400 for an unparseable body, 422 for a well-formed but invalid one (6A §7.4).
    malformed = any(error.get("type") == "json_invalid" for error in exc.errors())
    return error_response(ApiErrorCode.VALIDATION_ERROR, status_code=400 if malformed else 422)


class UnhandledErrorMiddleware:
    """Turn any exception no handler claimed into a generic INTERNAL_ERROR response.

    Sits inside ``CorrelationIdMiddleware`` so the response and the log line
    both carry the request ID. Starlette's own catch-all runs outside all user
    middleware, where that context is already gone.
    """

    def __init__(self, app: ASGIApp) -> None:
        self._app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self._app(scope, receive, send)
            return

        response_started = False

        async def tracking_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self._app(scope, receive, tracking_send)
        except Exception:
            logger.exception("unhandled_exception", path=scope.get("path"))
            if response_started:
                # Headers are already on the wire; the server must abort the connection.
                raise
            await error_response(ApiErrorCode.INTERNAL_ERROR)(scope, receive, send)


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(PlatformError, _handle_platform_error)
    app.add_exception_handler(StarletteHTTPException, _handle_http_exception)
    app.add_exception_handler(RequestValidationError, _handle_request_validation_error)
