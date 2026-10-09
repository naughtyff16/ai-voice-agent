from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path
from types import ModuleType

import pytest

pytestmark = pytest.mark.unit

BACKEND_DIR = Path(__file__).resolve().parents[2]


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "check_repository", BACKEND_DIR / "scripts" / "check_repository.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("check_repository", module)
    spec.loader.exec_module(module)
    return module


# Assembled at runtime so this file never contains the literal patterns it tests.
_KEY_HEADER = "-----BEGIN " + "RSA PRIVATE KEY-----"
_AWS_KEY = "AKIA" + "ABCDEFGHIJKLMNOP"
_DB_URL = "postgresql+asyncpg://app_api:" + "Xk9vQ2rLmT" + "@db.internal:5432/voice"
_REDIS_URL = "rediss://default:" + "Zr8uYt6wQp" + "@cache:6380/0"


@pytest.mark.parametrize(
    "line",
    [
        f"DATABASE__URL={_DB_URL}",
        f"url = '{_REDIS_URL}'",
        _KEY_HEADER,
        f"aws_access_key_id = {_AWS_KEY}",
    ],
)
def test_real_looking_secrets_are_reported(line: str) -> None:
    assert _load().find_secrets("file.txt", line)


@pytest.mark.parametrize(
    "line",
    [
        'url = f"postgresql+asyncpg://app_api:{password}@127.0.0.1/db"',
        "DATABASE__URL=postgresql+asyncpg://app_api:<password>@localhost:5432/voice_agent_dev",
        "REDIS__URL=redis://:${REDIS_PASSWORD}@redis:6379/0",
        "MIGRATION_DATABASE_URL=postgresql+psycopg://admin:change-me@localhost/x",
        "postgresql://u:p@127.0.0.1/voice_agent_test_x",
        "https://example.com/path@section",
    ],
)
def test_placeholders_are_not_reported(line: str) -> None:
    assert _load().find_secrets("file.txt", line) == []


def test_environment_files_cannot_be_committed() -> None:
    guards = _load()
    flagged = guards.forbidden_files(
        [".env", "backend/.env.local", "infra/docker-compose/.env", "backend/.env.local.example"]
    )
    assert flagged == [
        ".env: environment files must not be committed",
        "backend/.env.local: environment files must not be committed",
        "infra/docker-compose/.env: environment files must not be committed",
    ]


# ---------------------------------------------------------------- CI triggers (D0-M-02)

WORKFLOW = BACKEND_DIR.parent / ".github" / "workflows" / "backend-ci.yaml"


def _trigger_paths(event: str) -> list[str]:
    """The `paths:` filter of one trigger event, read from the block-style workflow."""
    paths: list[str] = []
    in_event = in_paths = False
    for line in WORKFLOW.read_text(encoding="utf-8").splitlines():
        if re.fullmatch(r"  [a-z_]+:", line):
            in_event, in_paths = line.strip() == f"{event}:", False
        elif in_event and line == "    paths:":
            in_paths = True
        elif in_paths and (item := re.fullmatch(r'      - "([^"]+)"', line)):
            paths.append(item.group(1))
        elif in_paths:
            in_paths = False
    return paths


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    # GitHub filter semantics: ** crosses directories, * does not.
    parts = re.split(r"(\*\*|\*)", pattern)
    body = "".join(
        ".*" if part == "**" else "[^/]*" if part == "*" else re.escape(part) for part in parts
    )
    return re.compile(rf"^{body}$")


def _triggers(event: str, changed: str) -> bool:
    return any(_glob_to_regex(pattern).match(changed) for pattern in _trigger_paths(event))


@pytest.mark.parametrize("event", ["push", "pull_request"])
@pytest.mark.parametrize(
    "changed",
    [
        "infra/docker/api.Dockerfile",
        "infra/docker-compose/docker-compose.yml",
        "infra/docker-compose/.env.example",
        "backend/voice_agent/apps/api/main.py",
        "backend/pyproject.toml",
        "backend/uv.lock",
        "backend/.python-version",
        ".github/workflows/backend-ci.yaml",
        "docs/phase-05-database-design/5K/migrations/001_5B.sql",
    ],
)
def test_ci_runs_for_every_relevant_change(event: str, changed: str) -> None:
    assert _triggers(event, changed)


@pytest.mark.parametrize("event", ["push", "pull_request"])
@pytest.mark.parametrize("changed", ["docs/product/vision.md", "README.md"])
def test_ci_skips_unrelated_documentation(event: str, changed: str) -> None:
    assert not _triggers(event, changed)


def test_ci_has_a_container_job_that_builds_and_runs_the_stack() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "\n  container:\n" in workflow
    assert "docker build -f infra/docker/api.Dockerfile" in workflow
    assert "docker compose up -d --wait postgres redis" in workflow
    assert "db_migrate.py gate --expected-head" in workflow
    assert "docker compose stop --timeout 30 api" in workflow
