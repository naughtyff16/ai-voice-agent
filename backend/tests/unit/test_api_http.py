"""HTTP-layer contracts that need no running dependency.

Requests go through ``httpx.ASGITransport``, which does not run the lifespan,
so no connection is attempted: the runtime stays in its initial state.
"""

from __future__ import annotations

import asyncio
import re
import secrets
import uuid
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi import APIRouter, FastAPI, HTTPException
from pydantic import BaseModel

from tests.conftest import make_settings
from voice_agent.apps.api.error_catalog import (
    ERRATUM_OD_D0_02,
    ERROR_CATALOG,
    FROZEN_CATALOG,
    ApiErrorCode,
    contract_for,
)
from voice_agent.apps.api.main import create_app
from voice_agent.apps.api.middleware.correlation_id import REQUEST_ID_HEADER
from voice_agent.platform.shared_kernel.errors import CacheError, DatabaseError
from voice_agent.platform.shared_kernel.request_context import (
    RequestContext,
    bind_request_context,
    current_request_context,
    reset_request_context,
)

pytestmark = pytest.mark.unit

# Generated per run, so the suite contains no password-like literal.
SECRET = secrets.token_urlsafe(16)
# Port 9 (discard) on loopback: never contacted, because the lifespan does not run.
DB_URL = f"postgresql+asyncpg://app_api:{SECRET}@127.0.0.1:9/voice_agent_test_unit"
REDIS_URL = f"redis://:{SECRET}@127.0.0.1:9/0"


class EchoBody(BaseModel):
    count: int


def _app(**overrides: object) -> FastAPI:
    app = create_app(make_settings(database_url=DB_URL, redis_url=REDIS_URL, **overrides))
    probe = APIRouter()

    @probe.get("/__probe/crash")
    async def crash() -> None:
        raise RuntimeError(f"boom while using {DB_URL}")

    @probe.get("/__probe/database-down")
    async def database_down() -> None:
        raise DatabaseError("PostgreSQL is not reachable.", context={"host": "db.internal"})

    @probe.get("/__probe/cache-down")
    async def cache_down() -> None:
        raise CacheError("Redis is not reachable.")

    @probe.post("/__probe/echo")
    async def echo(body: EchoBody) -> dict[str, int]:
        return {"count": body.count}

    @probe.get("/__probe/teapot")
    async def teapot() -> None:
        raise HTTPException(status_code=418, detail=f"secret detail {SECRET}")

    app.include_router(probe)
    return app


async def _send(app: FastAPI, method: str, url: str, **kwargs: Any) -> httpx.Response:
    transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
        return await client.request(method, url, **kwargs)


def _assert_error_envelope(body: dict[str, object], *, code: str, retryable: bool) -> str:
    assert set(body) == {"error"}
    error = body["error"]
    assert isinstance(error, dict)
    assert set(error) == {"code", "message", "details", "request_id", "retryable"}
    assert error["code"] == code
    assert error["retryable"] is retryable
    assert error["details"] == {}
    request_id = error["request_id"]
    assert isinstance(request_id, str)
    return request_id


def test_app_construction_opens_no_connection() -> None:
    app = _app()
    assert app.state.runtime.state.value == "new"
    assert app.docs_url is None and app.openapi_url is None


async def test_liveness_is_independent_of_dependencies() -> None:
    response = await _send(_app(), "GET", "/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["cache-control"] == "no-store"


async def test_readiness_is_not_just_process_health() -> None:
    # The process is alive, but infrastructure has not started: it must not be ready.
    response = await _send(_app(), "GET", "/health/ready")
    assert response.status_code == 503
    assert response.json() == {
        "status": "unavailable",
        "checks": {"postgres": "skipped", "redis": "skipped"},
    }


async def test_every_response_carries_a_server_generated_uuid7_request_id() -> None:
    app = _app()
    first = await _send(app, "GET", "/health/live", headers={REQUEST_ID_HEADER: "client-chosen"})
    second = await _send(app, "GET", "/health/live")
    ids = [first.headers[REQUEST_ID_HEADER], second.headers[REQUEST_ID_HEADER]]
    assert "client-chosen" not in ids
    assert ids[0] != ids[1]
    assert all(uuid.UUID(value).version == 7 for value in ids)


async def test_unhandled_exception_returns_internal_error_without_internals() -> None:
    response = await _send(_app(), "GET", "/__probe/crash")
    assert response.status_code == 500
    request_id = _assert_error_envelope(response.json(), code="INTERNAL_ERROR", retryable=False)
    assert request_id == response.headers[REQUEST_ID_HEADER]
    text = response.text
    for leaked in (SECRET, "Traceback", "RuntimeError", "boom", "asyncpg"):
        assert leaked not in text


@pytest.mark.parametrize("path", ["/__probe/database-down", "/__probe/cache-down"])
async def test_infrastructure_failure_maps_to_dependency_unavailable(path: str) -> None:
    response = await _send(_app(), "GET", path)
    assert response.status_code == 503
    _assert_error_envelope(response.json(), code="DEPENDENCY_UNAVAILABLE", retryable=True)
    assert "db.internal" not in response.text


async def test_unknown_route_uses_the_catalog_not_found_code() -> None:
    response = await _send(_app(), "GET", "/api/v1/does-not-exist")
    assert response.status_code == 404
    _assert_error_envelope(response.json(), code="RESOURCE_NOT_FOUND", retryable=False)


async def test_wrong_method_is_method_not_allowed_with_allow_header() -> None:
    # Controlled API erratum OD-D0-02: 405 METHOD_NOT_ALLOWED, not retryable,
    # standard envelope, Allow preserved.
    response = await _send(_app(), "POST", "/health/live")
    assert response.status_code == 405
    assert response.headers["allow"] == "GET"
    request_id = _assert_error_envelope(response.json(), code="METHOD_NOT_ALLOWED", retryable=False)
    assert request_id == response.headers[REQUEST_ID_HEADER]
    assert uuid.UUID(request_id).version == 7
    assert response.headers["content-type"] == "application/json"
    for leaked in ("Traceback", "Method Not Allowed", '"detail"'):
        assert leaked not in response.text


async def test_uncataloged_http_status_becomes_internal_error() -> None:
    response = await _send(_app(), "GET", "/__probe/teapot")
    assert response.status_code == 500
    _assert_error_envelope(response.json(), code="INTERNAL_ERROR", retryable=False)
    assert SECRET not in response.text


async def test_validation_errors_distinguish_malformed_from_invalid() -> None:
    app = _app()
    malformed = await _send(
        app,
        "POST",
        "/__probe/echo",
        content=b"{not json",
        headers={"content-type": "application/json"},
    )
    assert malformed.status_code == 400
    _assert_error_envelope(malformed.json(), code="VALIDATION_ERROR", retryable=False)
    invalid = await _send(app, "POST", "/__probe/echo", json={"count": "many"})
    assert invalid.status_code == 422
    _assert_error_envelope(invalid.json(), code="VALIDATION_ERROR", retryable=False)
    assert "many" not in invalid.text


async def test_no_cors_headers_without_configured_origins() -> None:
    response = await _send(
        _app(), "GET", "/health/live", headers={"Origin": "https://evil.example"}
    )
    assert "access-control-allow-origin" not in response.headers


async def test_cors_allows_only_explicit_origins_and_never_credentials() -> None:
    app = _app(api={"cors_allowed_origins": ["http://localhost:3000"]})
    allowed = await _send(
        app,
        "OPTIONS",
        "/health/live",
        headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET"},
    )
    assert allowed.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "access-control-allow-credentials" not in allowed.headers
    denied = await _send(app, "GET", "/health/live", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in denied.headers


async def test_request_context_is_isolated_between_concurrent_tasks() -> None:
    seen: dict[str, str | None] = {}

    async def handle(request_id: str) -> None:
        token = bind_request_context(RequestContext(request_id=request_id))
        try:
            await asyncio.sleep(0)
            context = current_request_context()
            seen[request_id] = context.request_id if context else None
        finally:
            reset_request_context(token)

    await asyncio.gather(*(handle(f"req-{index}") for index in range(20)))
    assert seen == {f"req-{index}": f"req-{index}" for index in range(20)}
    assert current_request_context() is None


# ---------------------------------------------------------------- error catalog

FROZEN_CATALOG_DOCUMENT = (
    Path(__file__).resolve().parents[3] / "docs" / "phase-06-api-design" / "API-ERROR-CATALOG.md"
)


def _frozen_catalog_row(code: str) -> tuple[str, str]:
    """(status column, retryable column) of the code's row in the frozen catalog's §3 table."""
    pattern = re.compile(
        rf"^\| {code} \| (?P<status>[^|]+) \| [^|]+ \| [^|]+ \| (?P<retry>[^|]+) \|"
    )
    for line in FROZEN_CATALOG_DOCUMENT.read_text(encoding="utf-8").splitlines():
        if match := pattern.match(line):
            return match["status"].strip(), match["retry"].strip()
    raise AssertionError(f"{code} is not in the frozen API error catalog")


@pytest.mark.parametrize(
    "code",
    [code for code, contract in ERROR_CATALOG.items() if contract.authority == FROZEN_CATALOG],
)
def test_frozen_catalog_entries_match_the_frozen_document(code: ApiErrorCode) -> None:
    contract = ERROR_CATALOG[code]
    status_column, retry_column = _frozen_catalog_row(code.value)
    for status in contract.statuses:
        assert str(status) in status_column, (code, status, status_column)
    if contract.retryable:
        assert retry_column.startswith("conditional") and "true by default" in retry_column
    else:
        assert retry_column == "false"


def test_only_the_approved_erratum_is_outside_the_frozen_catalog() -> None:
    errata = {
        code for code, contract in ERROR_CATALOG.items() if contract.authority != FROZEN_CATALOG
    }
    assert errata == {ApiErrorCode.METHOD_NOT_ALLOWED}
    assert ERROR_CATALOG[ApiErrorCode.METHOD_NOT_ALLOWED].authority == ERRATUM_OD_D0_02
    assert ERROR_CATALOG[ApiErrorCode.METHOD_NOT_ALLOWED].statuses == (405,)
    assert ERROR_CATALOG[ApiErrorCode.METHOD_NOT_ALLOWED].retryable is False
    with pytest.raises(AssertionError):
        _frozen_catalog_row("METHOD_NOT_ALLOWED")  # still pending formal reconciliation


def test_uncataloged_code_status_pairs_are_refused() -> None:
    with pytest.raises(ValueError, match="not cataloged"):
        contract_for(ApiErrorCode.VALIDATION_ERROR, 405)
    with pytest.raises(ValueError, match="not cataloged"):
        contract_for(ApiErrorCode.DEPENDENCY_UNAVAILABLE, 500)


EMITTED_ERROR_PROBES: list[tuple[str, str, dict[str, Any]]] = [
    ("GET", "/api/v1/does-not-exist", {}),
    ("POST", "/health/live", {}),
    ("DELETE", "/health/ready", {}),
    (
        "POST",
        "/__probe/echo",
        {"content": b"{not json", "headers": {"content-type": "application/json"}},
    ),
    ("POST", "/__probe/echo", {"json": {"count": "many"}}),
    ("GET", "/__probe/crash", {}),
    ("GET", "/__probe/database-down", {}),
    ("GET", "/__probe/cache-down", {}),
    ("GET", "/__probe/teapot", {}),
]


@pytest.mark.parametrize(("method", "path", "kwargs"), EMITTED_ERROR_PROBES)
async def test_every_emitted_error_is_a_cataloged_combination(
    method: str, path: str, kwargs: dict[str, Any]
) -> None:
    response = await _send(_app(), method, path, **kwargs)
    error = response.json()["error"]
    code = ApiErrorCode(error["code"])
    contract = ERROR_CATALOG[code]
    assert response.status_code in contract.statuses
    assert error["retryable"] is contract.retryable
    assert error["message"] == contract.message
