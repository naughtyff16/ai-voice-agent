"""The real server process: boot, serve, and shut down on a signal."""

from __future__ import annotations

import json
import os
import secrets
import signal
import subprocess
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import httpx
import pytest

from tests.integration.conftest import application_connections
from tests.support.infrastructure import BACKEND_DIR, HOST, PostgresCluster, RedisServer, free_port

pytestmark = pytest.mark.smoke

SERVICE_NAME = "voice-agent-smoke"
_BOOT_TIMEOUT_SECONDS = 60.0
_EXIT_TIMEOUT_SECONDS = 30.0


@contextmanager
def server_process(
    env_overrides: dict[str, str], log_path: Path, port: int
) -> Iterator[subprocess.Popen[bytes]]:
    env = {
        name: value
        for name, value in os.environ.items()
        if not name.upper().startswith(("DATABASE__", "REDIS__", "API__", "OBSERVABILITY__"))
    }
    env.update({"SERVICE_NAME": SERVICE_NAME, "PYTHONUNBUFFERED": "1", **env_overrides})
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "--factory",
                "voice_agent.apps.api.asgi:application",
                "--host",
                HOST,
                "--port",
                str(port),
                "--no-access-log",
            ],
            cwd=BACKEND_DIR,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=creationflags,
        )
    try:
        yield process
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=_EXIT_TIMEOUT_SECONDS)


def _request_shutdown(process: subprocess.Popen[bytes]) -> None:
    # uvicorn handles SIGTERM, and SIGBREAK on Windows, as a graceful shutdown.
    process.send_signal(signal.CTRL_BREAK_EVENT if sys.platform == "win32" else signal.SIGTERM)


# After a graceful shutdown uvicorn re-raises the captured signal so the process
# ends with that signal's default status: killed by SIGTERM on POSIX, and the
# SIGBREAK default exit code 3 on Windows.
SIGNAL_EXIT_STATUS = 3 if sys.platform == "win32" else -signal.SIGTERM


def _wait_until_live(process: subprocess.Popen[bytes], base_url: str, log_path: Path) -> None:
    deadline = time.monotonic() + _BOOT_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if process.poll() is not None:
            pytest.fail(f"server exited during boot:\n{log_path.read_text(errors='replace')}")
        try:
            if httpx.get(f"{base_url}/health/live", timeout=1).status_code == 200:
                return
        except httpx.TransportError:
            time.sleep(0.2)
    pytest.fail(f"server did not become live:\n{log_path.read_text(errors='replace')}")


def _events(log_path: Path) -> list[str]:
    events = []
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            events.append(str(json.loads(line)["event"]))
        except (json.JSONDecodeError, KeyError, TypeError):
            continue
    return events


def test_server_boots_serves_and_shuts_down_gracefully(
    tmp_path: Path,
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
) -> None:
    port = free_port()
    base_url = f"http://{HOST}:{port}"
    log_path = tmp_path / "server.log"
    env = {
        "ENVIRONMENT": "test",
        "DATABASE__URL": postgres_cluster.runtime_url(migrated_database),
        "REDIS__URL": redis_service.url,
        "API__CORS_ALLOWED_ORIGINS": '["http://localhost:3000"]',
    }
    with server_process(env, log_path, port) as process:
        _wait_until_live(process, base_url, log_path)
        ready = httpx.get(f"{base_url}/health/ready", timeout=5)
        missing = httpx.get(f"{base_url}/api/v1/nothing-here", timeout=5)
        preflight = {"Access-Control-Request-Method": "GET"}
        allowed_preflight = httpx.options(
            f"{base_url}/health/ready",
            headers={**preflight, "Origin": "http://localhost:3000"},
            timeout=5,
        )
        rejected_preflight = httpx.options(
            f"{base_url}/health/ready",
            headers={**preflight, "Origin": "https://evil.example"},
            timeout=5,
        )
        connected = application_connections(postgres_cluster, migrated_database, SERVICE_NAME)

        _request_shutdown(process)
        exit_code = process.wait(timeout=_EXIT_TIMEOUT_SECONDS)

    assert ready.status_code == 200
    assert ready.json() == {"status": "ok", "checks": {"postgres": "ok", "redis": "ok"}}
    assert ready.headers["x-request-id"]
    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "RESOURCE_NOT_FOUND"
    assert connected >= 1

    # D0-P1-08 over real HTTP: preflights are correlated and rejections use the envelope.
    assert allowed_preflight.status_code == 200
    assert allowed_preflight.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert allowed_preflight.headers["x-request-id"]
    assert rejected_preflight.status_code == 400
    rejection = rejected_preflight.json()["error"]
    assert rejection["code"] == "VALIDATION_ERROR" and rejection["retryable"] is False
    assert rejection["request_id"] == rejected_preflight.headers["x-request-id"]
    assert "access-control-allow-origin" not in rejected_preflight.headers
    assert "Disallowed" not in rejected_preflight.text

    assert exit_code == SIGNAL_EXIT_STATUS, log_path.read_text(encoding="utf-8", errors="replace")
    events = _events(log_path)
    expected_order = [
        "application_starting",
        "infrastructure_ready",
        "application_started",
        "application_stopping",
        "redis_closed",
        "postgres_disposed",
        "application_stopped",
        "Finished server process",
    ]
    positions = [
        next(index for index, event in enumerate(events) if event.startswith(expected))
        for expected in expected_order
    ]
    assert positions == sorted(positions), events
    assert application_connections(postgres_cluster, migrated_database, SERVICE_NAME) == 0

    output = log_path.read_text(encoding="utf-8", errors="replace")
    assert postgres_cluster.runtime_password not in output
    assert redis_service.password not in output


def test_server_refuses_to_start_when_postgres_is_unreachable(
    tmp_path: Path, redis_service: RedisServer
) -> None:
    password = secrets.token_urlsafe(16)
    log_path = tmp_path / "server.log"
    env = {
        "ENVIRONMENT": "test",
        "DATABASE__URL": f"postgresql+asyncpg://app_api:{password}@{HOST}:{free_port()}/voice_agent_test_x",
        "REDIS__URL": redis_service.url,
    }
    with server_process(env, log_path, free_port()) as process:
        exit_code = process.wait(timeout=_BOOT_TIMEOUT_SECONDS)
    output = log_path.read_text(encoding="utf-8", errors="replace")
    assert exit_code != 0
    assert "infrastructure_start_failed" in _events(log_path)
    assert password not in output
    assert redis_service.password not in output


def test_server_refuses_to_start_with_invalid_configuration(tmp_path: Path) -> None:
    password = secrets.token_urlsafe(16)
    log_path = tmp_path / "server.log"
    env = {
        "ENVIRONMENT": "test",
        "DATABASE__URL": f"mysql://app_api:{password}@{HOST}/voice_agent_test_x",
    }
    with server_process(env, log_path, free_port()) as process:
        exit_code = process.wait(timeout=_BOOT_TIMEOUT_SECONDS)
    output = log_path.read_text(encoding="utf-8", errors="replace")
    assert exit_code != 0
    assert "Invalid configuration" in output
    assert "postgresql+asyncpg" in output
    assert password not in output
