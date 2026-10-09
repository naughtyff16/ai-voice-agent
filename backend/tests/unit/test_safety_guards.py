from __future__ import annotations

import importlib.util
import sys
import uuid
from pathlib import Path
from types import ModuleType

import pytest

from tests.support.disposable import (
    DISPOSABLE_CLUSTER_MARKER_DATABASE,
    UnsafeTestTargetError,
    require_disposable_database_name,
    require_loopback,
)
from voice_agent.platform.utils.id_generator import generate_uuid7

pytestmark = pytest.mark.unit

BACKEND_DIR = Path(__file__).resolve().parents[2]


def _load_cli() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "db_migrate", BACKEND_DIR / "scripts" / "db_migrate.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("db_migrate", module)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    "name",
    [
        "postgres",
        "voice_agent_dev",
        "voice_agent",
        "voice_agent_test_",
        "voice_agent_test_x",
        "VOICE_AGENT_TEST_ABCDEFGH",
        "voice_agent_test_abcdefgh; DROP DATABASE prod",
        DISPOSABLE_CLUSTER_MARKER_DATABASE,
    ],
)
def test_destructive_operations_refuse_non_test_databases(name: str) -> None:
    with pytest.raises(UnsafeTestTargetError):
        require_disposable_database_name(name)


def test_harness_database_names_are_accepted() -> None:
    assert require_disposable_database_name("voice_agent_test_db_0123456789ab")


@pytest.mark.parametrize("host", ["db.internal", "10.0.0.5", "prod.example.com", None, ""])
def test_destructive_operations_refuse_remote_hosts(host: str | None) -> None:
    with pytest.raises(UnsafeTestTargetError):
        require_loopback(host)


def test_prerequisite_check_reports_each_missing_item() -> None:
    cli = _load_cli()
    ok = cli.missing_prerequisites(
        server_version_num=180006,
        available={"vector", "pgcrypto", "pg_stat_statements"},
        preloaded_libraries={"pg_stat_statements"},
    )
    assert ok == []
    problems = cli.missing_prerequisites(
        server_version_num=150004, available={"pgcrypto"}, preloaded_libraries={""}
    )
    joined = "\n".join(problems)
    assert "below the supported minimum" in joined
    assert "'vector' is not available" in joined
    assert "'pg_stat_statements' is not available" in joined
    assert "shared_preload_libraries" in joined


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+asyncpg://u:p@127.0.0.1/voice_agent_test_x",
        "postgresql://u:p@127.0.0.1/voice_agent_test_x",
        "nonsense",
    ],
)
def test_migration_cli_requires_its_own_psycopg_url(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], url: str
) -> None:
    monkeypatch.setenv("MIGRATION_DATABASE_URL", url)
    assert _load_cli().main(["check"]) == 1
    error = capsys.readouterr().err
    assert "MIGRATION_DATABASE_URL" in error
    assert ":p@" not in error


def test_set_runtime_password_is_refused_outside_local_and_test(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("ENVIRONMENT", "production")
    assert _load_cli().main(["set-runtime-password"]) == 1
    assert "only available when ENVIRONMENT is local or test" in capsys.readouterr().err


def test_set_runtime_password_is_refused_for_remote_hosts(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("ENVIRONMENT", "local")
    monkeypatch.setenv(
        "DATABASE__URL", "postgresql+asyncpg://app_api:pw@db.internal:5432/voice_agent"
    )
    monkeypatch.setenv(
        "MIGRATION_DATABASE_URL", "postgresql+psycopg://admin:pw@db.internal:5432/voice_agent"
    )
    assert _load_cli().main(["set-runtime-password"]) == 1
    assert "only targets a PostgreSQL on this machine" in capsys.readouterr().err


def test_uuid7_layout_and_ordering() -> None:
    values = [generate_uuid7() for _ in range(200)]
    assert all(value.version == 7 and value.variant == uuid.RFC_4122 for value in values)
    assert len(set(values)) == len(values)
    timestamps = [value.int >> 80 for value in values]
    assert timestamps == sorted(timestamps)
