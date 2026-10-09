"""Target safety of the migration CLI (D0-P1-03) and the deployment gate (OD-D0-01).

``_connect`` is replaced by a recorder in every test, so a refusal can be proven
to happen before any network connection, and the valid paths run against a
scripted connection instead of a server. The same commands run against real
PostgreSQL in tests/integration/test_migrations.py and test_deployment_gate.py.
"""

from __future__ import annotations

import importlib.util
import secrets
import shutil
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path
from types import ModuleType
from typing import Any

import psycopg
import pytest

from tests.support.infrastructure import PostgresCluster, RedisServer

pytestmark = pytest.mark.unit

BACKEND_DIR = Path(__file__).resolve().parents[2]
PASSWORD = secrets.token_urlsafe(16)
RUNTIME_URL = f"postgresql+asyncpg://app_api:{PASSWORD}@127.0.0.1:5432/voice_agent_test_cli"
MIGRATION_URL = f"postgresql+psycopg://d0_bootstrap:{PASSWORD}@127.0.0.1:5432/voice_agent_test_cli"
# session_user, current_user, current_database(), server address, server port
IDENTITY: tuple[object, ...] = (
    "d0_bootstrap",
    "d0_bootstrap",
    "voice_agent_test_cli",
    "127.0.0.1",
    5432,
)


class _FakeResult:
    def __init__(self, row: tuple[object, ...] | None) -> None:
        self._row = row

    def fetchone(self) -> tuple[object, ...] | None:
        return self._row

    def fetchall(self) -> list[tuple[object, ...]]:
        return [] if self._row is None else [self._row]

    def __iter__(self) -> Iterator[tuple[object, ...]]:
        return iter(self.fetchall())


class _FakeConnection:
    """Answers the CLI's identity query; records every statement."""

    def __init__(self, identity: tuple[object, ...]) -> None:
        self.identity = identity
        self.statements: list[str] = []

    def __enter__(self) -> _FakeConnection:
        return self

    def __exit__(self, *_exc: object) -> None:
        return None

    def execute(self, statement: object, _params: object = None) -> _FakeResult:
        text = statement if isinstance(statement, str) else repr(statement)
        self.statements.append(text)
        return _FakeResult(self.identity if "inet_server_addr" in text else None)


class _Recorder:
    def __init__(self) -> None:
        self.identity = IDENTITY
        self.connections: list[_FakeConnection] = []

    def connect(self, _url: object) -> _FakeConnection:
        connection = _FakeConnection(self.identity)
        self.connections.append(connection)
        return connection


def _load_cli() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "db_migrate", BACKEND_DIR / "scripts" / "db_migrate.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("db_migrate", module)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def cli(monkeypatch: pytest.MonkeyPatch) -> ModuleType:
    module = _load_cli()
    for name in ("PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("DATABASE__URL", RUNTIME_URL)
    monkeypatch.setenv("MIGRATION_DATABASE_URL", MIGRATION_URL)
    return module


@pytest.fixture
def recorder(cli: ModuleType, monkeypatch: pytest.MonkeyPatch) -> _Recorder:
    recording = _Recorder()
    monkeypatch.setattr(cli, "_connect", recording.connect)
    return recording


def _run(cli: ModuleType, capsys: pytest.CaptureFixture[str], *argv: str) -> tuple[int, str]:
    code = cli.main(list(argv))
    captured = capsys.readouterr()
    output = captured.out + captured.err
    assert PASSWORD not in output
    return code, output


# ---------------------------------------------------- set-runtime-password target (D0-P1-03)


@pytest.mark.parametrize(
    ("variable", "value", "expected"),
    [
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?host=db.internal", "(host)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?hostaddr=10.0.0.5", "(hostaddr)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?port=6543", "(port)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?dbname=voice_agent_prod", "(dbname)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?user=postgres", "(user)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?service=prod", "(service)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?servicefile=/tmp/x", "(servicefile)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?options=-crole%3Dx", "(options)"),
        ("MIGRATION_DATABASE_URL", f"{MIGRATION_URL}?frobnicate=1", "unrecognised parameters"),
        (
            "MIGRATION_DATABASE_URL",
            MIGRATION_URL.replace("127.0.0.1:5432", "127.0.0.1,10.0.0.5"),
            "exactly one host",
        ),
        (
            "MIGRATION_DATABASE_URL",
            MIGRATION_URL.replace("127.0.0.1:5432", "%2Fvar%2Frun%2Fpostgresql"),
            "exactly one host",
        ),
        (
            "MIGRATION_DATABASE_URL",
            MIGRATION_URL.replace("127.0.0.1:5432", "127.0.0.1"),
            "port explicitly",
        ),
        ("MIGRATION_DATABASE_URL", MIGRATION_URL.replace(":5432", ":5433"), "same local host"),
        (
            "MIGRATION_DATABASE_URL",
            MIGRATION_URL.replace("voice_agent_test_cli", "voice_agent_test_other"),
            "same local host",
        ),
        ("MIGRATION_DATABASE_URL", MIGRATION_URL.replace("127.0.0.1", "localhost"), "same local"),
        ("MIGRATION_DATABASE_URL", MIGRATION_URL.replace("127.0.0.1", "10.0.0.5"), "this machine"),
        ("DATABASE__URL", f"{RUNTIME_URL}?database=voice_agent_prod", "not a valid runtime"),
        ("DATABASE__URL", RUNTIME_URL.replace("127.0.0.1:5432", "127.0.0.1"), "port explicitly"),
        ("PGHOSTADDR", "10.0.0.5", "PGHOSTADDR"),
        ("PGSERVICE", "prod", "PGSERVICE"),
        ("PGSERVICEFILE", "pg_service.conf", "PGSERVICEFILE"),
        ("ENVIRONMENT", "staging", "only available when ENVIRONMENT is local or test"),
    ],
)
def test_set_runtime_password_refuses_redirection_before_connecting(
    cli: ModuleType,
    recorder: _Recorder,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    variable: str,
    value: str,
    expected: str,
) -> None:
    monkeypatch.setenv(variable, value)
    code, output = _run(cli, capsys, "set-runtime-password")
    assert code == 1
    assert expected in output
    assert recorder.connections == []


def test_set_runtime_password_sets_the_password_on_a_verified_local_target(
    cli: ModuleType, recorder: _Recorder, capsys: pytest.CaptureFixture[str]
) -> None:
    code, output = _run(cli, capsys, "set-runtime-password")
    assert code == 0, output
    (connection,) = recorder.connections
    assert "inet_server_addr" in connection.statements[0]
    assert "ALTER ROLE" in connection.statements[1]
    assert "login password set for app_api" in output


@pytest.mark.parametrize(
    "identity",
    [
        ("d0_bootstrap", "d0_bootstrap", "voice_agent_test_cli", "10.0.0.5", 5432),
        ("d0_bootstrap", "d0_bootstrap", "voice_agent_test_cli", None, 5432),
        ("d0_bootstrap", "d0_bootstrap", "voice_agent_test_cli", "127.0.0.1", 6543),
        ("d0_bootstrap", "d0_bootstrap", "voice_agent_prod", "127.0.0.1", 5432),
    ],
    ids=["remote-address", "unix-socket", "other-port", "other-database"],
)
def test_set_runtime_password_alters_nothing_unless_the_server_reached_is_the_local_target(
    cli: ModuleType,
    recorder: _Recorder,
    capsys: pytest.CaptureFixture[str],
    identity: tuple[object, ...],
) -> None:
    recorder.identity = identity
    code, output = _run(cli, capsys, "set-runtime-password")
    assert code == 1
    assert "Refusing to alter a role" in output
    (connection,) = recorder.connections
    assert not any("ALTER ROLE" in statement for statement in connection.statements)


# ---------------------------------------------------------------- deployment gate (OD-D0-01)


@pytest.mark.parametrize("command", ["gate", "check", "upgrade"])
@pytest.mark.parametrize("role", ["app_api", "app_worker", "app_readonly"])
def test_no_database_command_accepts_a_runtime_identity(
    cli: ModuleType,
    recorder: _Recorder,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    command: str,
    role: str,
) -> None:
    monkeypatch.setenv("MIGRATION_DATABASE_URL", MIGRATION_URL.replace("d0_bootstrap", role))
    argv = [command, "--expected-head", "112_5H5"] if command == "gate" else [command]
    code, output = _run(cli, capsys, *argv)
    assert code == 1
    assert f"runtime role '{role}'" in output
    assert recorder.connections == []


@pytest.mark.parametrize("expected_head", ["111_5H4", "113_5X", "112_5h5", "112_5H5 ", ""])
def test_gate_refuses_a_wrong_expected_head_before_connecting(
    cli: ModuleType, recorder: _Recorder, capsys: pytest.CaptureFixture[str], expected_head: str
) -> None:
    code, output = _run(cli, capsys, "gate", "--expected-head", expected_head)
    assert code == 1
    assert "is not the repository head 112_5H5" in output
    assert recorder.connections == []


def test_gate_refuses_an_invalid_repository_graph_before_connecting(
    cli: ModuleType,
    recorder: _Recorder,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    package = tmp_path / "5K"
    for directory in ("alembic", "migrations"):
        shutil.copytree(
            cli.MIGRATION_PACKAGE_DIR / directory,
            package / directory,
            ignore=shutil.ignore_patterns("__pycache__"),
        )
    (package / "migrations" / "113_5X.sql").write_text("SELECT 1;\n", encoding="utf-8")
    (package / "alembic" / "versions" / "113_5X.py").write_text(
        "revision = '113_5X'\ndown_revision = '112_5H5'\nSQL_FILE = '113_5X.sql'\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(cli, "MIGRATION_PACKAGE_DIR", package)
    code, output = _run(cli, capsys, "gate", "--expected-head", "112_5H5")
    assert code == 1
    assert "Migration graph is NOT the frozen baseline" in output
    assert recorder.connections == []


@pytest.mark.parametrize("position", [0, 1], ids=["session_user", "current_user"])
def test_gate_fails_if_the_connection_resolves_to_a_runtime_role(
    cli: ModuleType, recorder: _Recorder, capsys: pytest.CaptureFixture[str], position: int
) -> None:
    identity = list(IDENTITY)
    identity[position] = "app_api"  # e.g. a role switched by SET ROLE
    recorder.identity = tuple(identity)
    code, output = _run(cli, capsys, "gate", "--expected-head", "112_5H5")
    assert code == 1
    assert "connected as a runtime role" in output


def test_gate_fails_if_connected_to_another_database(
    cli: ModuleType, recorder: _Recorder, capsys: pytest.CaptureFixture[str]
) -> None:
    recorder.identity = ("d0_bootstrap", "d0_bootstrap", "voice_agent_prod", "10.0.0.5", 5432)
    code, output = _run(cli, capsys, "gate", "--expected-head", "112_5H5")
    assert code == 1
    assert "connected to database 'voice_agent_prod'" in output


def test_gate_reports_a_driver_failure_without_credentials(
    cli: ModuleType, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    def refuse(_url: object) -> Any:
        raise psycopg.OperationalError(f"connection to 127.0.0.1 failed: password={PASSWORD}")

    monkeypatch.setattr(cli, "_connect", refuse)
    code, output = _run(cli, capsys, "gate", "--expected-head", "112_5H5")
    assert code == 1
    assert "database operation failed (OperationalError)" in output


CHAIN = ("001_5B", "002_5B", "111_5H4", "112_5H5")


@pytest.mark.parametrize(
    ("revisions", "expected_problem"),
    [
        (["112_5H5"], None),
        (["111_5H4"], "stale: at 111_5H4, 1 revision(s) behind 112_5H5"),
        (["001_5B"], "stale: at 001_5B, 3 revision(s) behind 112_5H5"),
        (["999_ZZ"], "unknown revision '999_ZZ'"),
        (None, "no alembic_version table"),
        ([], "records no revision"),
        (["111_5H4", "112_5H5"], "several revisions"),
    ],
)
def test_revision_problem_explains_every_mismatch(
    cli: ModuleType, revisions: list[str] | None, expected_problem: str | None
) -> None:
    problem = cli.revision_problem(revisions, expected="112_5H5", chain=CHAIN)
    if expected_problem is None:
        assert problem is None
    else:
        assert problem is not None and expected_problem in problem


# ---------------------------------------------------------------- harness repr (D0-M-03)


def test_harness_objects_never_show_generated_passwords_in_repr(tmp_path: Path) -> None:
    bootstrap = secrets.token_urlsafe(24)
    cluster = PostgresCluster(
        bin_dir=tmp_path / "bin", root=tmp_path / "pg", port=5432, bootstrap_password=bootstrap
    )
    rendered = repr(cluster)
    assert bootstrap not in rendered
    assert cluster.runtime_password not in rendered
    assert "port=5432" in rendered  # still useful for debugging

    process = subprocess.Popen([sys.executable, "-c", "pass"])
    process.wait(timeout=30)
    password = secrets.token_urlsafe(24)
    server = RedisServer(process=process, root=tmp_path / "redis", port=6379, password=password)
    assert password not in repr(server)
    assert "port=6379" in repr(server)
