"""CORS preflight honours the error envelope and request correlation (D0-P1-08).

Requests run through the complete ASGI middleware stack of the real
application; tests/smoke/test_server.py repeats the preflight cases over real
HTTP against uvicorn.
"""

from __future__ import annotations

import secrets
import uuid
from typing import Any

import httpx
import pytest
from fastapi import FastAPI

from tests.conftest import make_settings
from voice_agent.apps.api.error_catalog import ERROR_CATALOG, ApiErrorCode
from voice_agent.apps.api.main import create_app
from voice_agent.apps.api.middleware.correlation_id import (
    REQUEST_ID_HEADER,
    CorrelationIdMiddleware,
)
from voice_agent.apps.api.middleware.cors import ApiCorsMiddleware
from voice_agent.apps.api.middleware.error_handler import UnhandledErrorMiddleware
from voice_agent.platform.shared_kernel.request_context import current_request_context

pytestmark = pytest.mark.unit

_PASSWORD = secrets.token_urlsafe(12)
ALLOWED = "http://localhost:3000"
OTHER_ALLOWED = "https://app.example.com"
DISALLOWED = "https://evil.example"


def _app() -> FastAPI:
    return create_app(
        make_settings(
            database_url=f"postgresql+asyncpg://app_api:{_PASSWORD}@127.0.0.1:9/voice_agent_test_u",
            redis_url=f"redis://:{_PASSWORD}@127.0.0.1:9/0",
            api={"cors_allowed_origins": [ALLOWED, OTHER_ALLOWED]},
        )
    )


async def _send(method: str, path: str, headers: dict[str, str]) -> httpx.Response:
    transport = httpx.ASGITransport(app=_app(), raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.request(method, path, headers=headers)
    # The request context never outlives the request.
    assert current_request_context() is None
    return response


def _preflight(
    origin: str, method: str = "GET", request_headers: str | None = None
) -> dict[str, str]:
    headers = {"Origin": origin, "Access-Control-Request-Method": method}
    if request_headers is not None:
        headers["Access-Control-Request-Headers"] = request_headers
    return headers


def _assert_request_id(response: httpx.Response) -> str:
    request_id = response.headers[REQUEST_ID_HEADER]
    assert uuid.UUID(request_id).version == 7
    return request_id


def _assert_rejected(response: httpx.Response) -> dict[str, Any]:
    assert response.status_code == 400
    assert response.headers["content-type"] == "application/json"
    body = response.json()
    assert set(body) == {"error"}
    error: dict[str, Any] = body["error"]
    assert set(error) == {"code", "message", "details", "request_id", "retryable"}
    contract = ERROR_CATALOG[ApiErrorCode(error["code"])]
    assert error["code"] == "VALIDATION_ERROR"
    assert 400 in contract.statuses
    assert error["retryable"] is False
    assert error["message"] == contract.message
    assert error["details"] == {}
    assert error["request_id"] == _assert_request_id(response)
    for raw in ("Disallowed", "CORS", "Traceback", "evil.example", "starlette"):
        assert raw not in response.text
    return error


@pytest.mark.parametrize("origin", [ALLOWED, OTHER_ALLOWED])
@pytest.mark.parametrize("path", ["/health/live", "/api/v1/not-a-route"])
async def test_allowed_preflight_succeeds_with_cors_headers_and_a_request_id(
    origin: str, path: str
) -> None:
    response = await _send(
        "OPTIONS", path, _preflight(origin, "POST", "Authorization, Content-Type, Idempotency-Key")
    )
    assert response.status_code == 200
    _assert_request_id(response)
    assert response.headers["access-control-allow-origin"] == origin
    assert "POST" in response.headers["access-control-allow-methods"]
    allowed_headers = response.headers["access-control-allow-headers"].lower()
    assert "authorization" in allowed_headers and "idempotency-key" in allowed_headers
    assert "Origin" in response.headers["vary"]
    assert "access-control-allow-credentials" not in response.headers


@pytest.mark.parametrize(
    "headers",
    [
        _preflight(DISALLOWED),
        _preflight("null"),
        _preflight(ALLOWED.upper()),
        _preflight(f"{ALLOWED}/"),
        _preflight("http://localhost:3001"),
        _preflight(ALLOWED, "TRACE"),
        _preflight(ALLOWED, "OPTIONS"),
        _preflight(ALLOWED, "GET", "X-Custom-Secret"),
        _preflight(ALLOWED, "GET", "Authorization, X-Other"),
        _preflight(DISALLOWED, "TRACE", "X-Custom-Secret"),
        {**_preflight(ALLOWED), "Access-Control-Request-Private-Network": "true"},
    ],
    ids=[
        "origin",
        "null-origin",
        "origin-case",
        "origin-trailing-slash",
        "origin-other-port",
        "method",
        "method-options",
        "header",
        "one-bad-header",
        "origin-method-and-header",
        "private-network",
    ],
)
@pytest.mark.parametrize("path", ["/health/live", "/api/v1/not-a-route"])
async def test_rejected_preflight_uses_the_error_envelope_and_a_request_id(
    headers: dict[str, str], path: str
) -> None:
    response = await _send("OPTIONS", path, {**headers, REQUEST_ID_HEADER: "client-chosen"})
    error = _assert_rejected(response)
    assert error["request_id"] != "client-chosen"  # always server-generated
    origin = headers["Origin"]
    if origin in {ALLOWED, OTHER_ALLOWED}:
        assert response.headers["access-control-allow-origin"] == origin
    else:
        # Never an allow-origin header, and never a wildcard, for a disallowed origin.
        assert "access-control-allow-origin" not in response.headers
    assert "Origin" in response.headers["vary"]
    assert "access-control-allow-credentials" not in response.headers


async def test_rejected_preflight_reasons_are_logged_not_returned(
    capsys: pytest.CaptureFixture[str],
) -> None:
    response = await _send("OPTIONS", "/health/live", _preflight(DISALLOWED, "TRACE", "X-Nope"))
    request_id = _assert_rejected(response)["request_id"]
    logs = capsys.readouterr().out
    assert '"event": "cors_preflight_rejected"' in logs
    assert '"rejected": ["headers", "method", "origin"]' in logs
    assert f'"request_id": "{request_id}"' in logs


async def test_options_without_preflight_headers_is_an_ordinary_request() -> None:
    response = await _send("OPTIONS", "/health/live", {"Origin": ALLOWED})
    assert response.status_code == 405
    assert response.json()["error"]["code"] == "METHOD_NOT_ALLOWED"
    assert response.json()["error"]["request_id"] == _assert_request_id(response)
    assert response.headers["allow"] == "GET"
    # An error response to an allowed origin still carries the CORS headers.
    assert response.headers["access-control-allow-origin"] == ALLOWED


async def test_simple_requests_follow_the_allowlist() -> None:
    allowed = await _send("GET", "/health/live", {"Origin": ALLOWED})
    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == ALLOWED
    assert allowed.headers["access-control-expose-headers"] == REQUEST_ID_HEADER
    _assert_request_id(allowed)

    # The server still answers; the browser enforces the policy because no
    # allow-origin header is present.
    denied = await _send("GET", "/health/live", {"Origin": DISALLOWED})
    assert denied.status_code == 200
    assert "access-control-allow-origin" not in denied.headers
    _assert_request_id(denied)

    missing = await _send("GET", "/api/v1/nope", {"Origin": ALLOWED})
    assert missing.status_code == 404
    assert missing.headers["access-control-allow-origin"] == ALLOWED


def test_middleware_order_is_correlation_then_cors_then_error_capture() -> None:
    # Starlette lists user middleware outermost first.
    order: list[object] = [middleware.cls for middleware in _app().user_middleware]
    assert order == [CorrelationIdMiddleware, ApiCorsMiddleware, UnhandledErrorMiddleware]
