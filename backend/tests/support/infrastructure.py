"""Disposable PostgreSQL and Redis servers for integration and smoke tests.

Every server is started by this module, from local binaries, in a fresh
temporary directory, bound to 127.0.0.1 on a free port, with a random password,
and destroyed afterwards. Tests therefore never touch a developer's database or
any shared service: a cluster created here is disposable by construction.

Binaries are located through ``PG_BIN_DIR`` / ``REDIS_SERVER_BIN`` or ``PATH``.
If a prerequisite is missing, ``InfrastructureUnavailableError`` explains which.
"""

from __future__ import annotations

import os
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Final

import psycopg
from psycopg import sql
from redis import Redis
from redis.exceptions import RedisError

from tests.support.disposable import (
    DISPOSABLE_CLUSTER_MARKER_DATABASE,
    require_disposable_database_name,
    require_loopback,
)
from voice_agent.platform.config.base_settings import TEST_DATABASE_NAME_PREFIX

HOST: Final = "127.0.0.1"
BOOTSTRAP_ROLE: Final = "d0_bootstrap"
RUNTIME_ROLE: Final = "app_api"
BACKEND_DIR: Final = Path(__file__).resolve().parents[2]
_STARTUP_TIMEOUT_SECONDS: Final = 60.0
_POLL_INTERVAL_SECONDS: Final = 0.1
_DEFAULT_PG_BIN_DIRS: Final = (
    "/usr/lib/postgresql/18/bin",
    "C:/Program Files/PostgreSQL/18/bin",
)


class InfrastructureUnavailableError(RuntimeError):
    """A local prerequisite for the disposable test infrastructure is missing."""


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind((HOST, 0))
        port: int = probe.getsockname()[1]
        return port


def _executable(name: str) -> str:
    return f"{name}.exe" if sys.platform == "win32" else name


def find_postgres_bin_dir() -> Path:
    candidates: list[Path] = []
    if configured := os.environ.get("PG_BIN_DIR"):
        candidates.append(Path(configured))
    if on_path := shutil.which("initdb"):
        candidates.append(Path(on_path).parent)
    candidates.extend(Path(path) for path in _DEFAULT_PG_BIN_DIRS)
    for candidate in candidates:
        if (candidate / _executable("initdb")).is_file() and (
            candidate / _executable("pg_ctl")
        ).is_file():
            return candidate
    raise InfrastructureUnavailableError(
        "PostgreSQL 18 server binaries (initdb, pg_ctl) were not found. "
        "Set PG_BIN_DIR to the PostgreSQL 18 bin directory."
    )


def find_redis_server() -> Path:
    configured = os.environ.get("REDIS_SERVER_BIN") or shutil.which("redis-server")
    if configured and Path(configured).is_file():
        return Path(configured)
    raise InfrastructureUnavailableError(
        "redis-server (7.2 or later) was not found. Put it on PATH or set REDIS_SERVER_BIN."
    )


def remove_tree(path: Path) -> None:
    """Delete a harness directory, failing loudly if it cannot be removed.

    On Windows a just-killed process can hold its log file open for a moment,
    so removal is retried briefly instead of being silently skipped.
    """
    deadline = time.monotonic() + _STARTUP_TIMEOUT_SECONDS / 6
    while True:
        try:
            shutil.rmtree(path)
            return
        except FileNotFoundError:
            return
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(_POLL_INTERVAL_SECONDS)


def _wait_until(probe_ready: object, description: str, log_path: Path) -> None:
    assert callable(probe_ready)
    deadline = time.monotonic() + _STARTUP_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if probe_ready():
            return
        time.sleep(_POLL_INTERVAL_SECONDS)
    log_tail = log_path.read_text(encoding="utf-8", errors="replace")[-2000:]
    raise InfrastructureUnavailableError(f"{description} did not become ready:\n{log_tail}")


@dataclass
class PostgresCluster:
    """A throwaway PostgreSQL cluster owned by this test session.

    Generated passwords are excluded from ``repr`` so that pytest failure output
    and debugging never print them (D0-M-03).
    """

    bin_dir: Path
    root: Path
    port: int
    bootstrap_password: str = field(repr=False)
    runtime_password: str = field(default_factory=lambda: secrets.token_urlsafe(24), repr=False)
    _template_database: str | None = None

    @property
    def data_dir(self) -> Path:
        return self.root / "data"

    @property
    def log_path(self) -> Path:
        return self.root / "postgres.log"

    def _bin(self, name: str) -> str:
        return str(self.bin_dir / _executable(name))

    def admin_connect(self, database: str = "postgres") -> psycopg.Connection[tuple[object, ...]]:
        return psycopg.connect(
            host=require_loopback(HOST),
            port=self.port,
            dbname=database,
            user=BOOTSTRAP_ROLE,
            password=self.bootstrap_password,
            autocommit=True,
            connect_timeout=5,
        )

    def migration_url(self, database: str) -> str:
        return (
            f"postgresql+psycopg://{BOOTSTRAP_ROLE}:{self.bootstrap_password}"
            f"@{HOST}:{self.port}/{database}"
        )

    def runtime_url(self, database: str, *, user: str = RUNTIME_ROLE) -> str:
        password = self.bootstrap_password if user == BOOTSTRAP_ROLE else self.runtime_password
        return f"postgresql+asyncpg://{user}:{password}@{HOST}:{self.port}/{database}"

    def start(self) -> None:
        password_file = self.root / "bootstrap.pw"
        password_file.write_text(self.bootstrap_password, encoding="utf-8")
        with (self.root / "initdb.log").open("w", encoding="utf-8") as initdb_log:
            result = subprocess.run(
                [
                    self._bin("initdb"),
                    "--pgdata",
                    str(self.data_dir),
                    "--username",
                    BOOTSTRAP_ROLE,
                    "--auth",
                    "scram-sha-256",
                    "--pwfile",
                    str(password_file),
                    "--encoding",
                    "UTF8",
                    "--no-sync",
                    "--no-instructions",
                ],
                stdout=initdb_log,
                stderr=subprocess.STDOUT,
                check=False,
            )
        password_file.unlink()
        if result.returncode != 0:
            raise InfrastructureUnavailableError(f"initdb failed (exit {result.returncode}).")

        server_options = " ".join(
            [
                f"-p {self.port}",
                f"-c listen_addresses={HOST}",
                "-c shared_preload_libraries=pg_stat_statements",
                "-c max_connections=200",
                "-c fsync=off",
                "-c synchronous_commit=off",
            ]
        )
        # Output goes to a file, never a pipe: the postmaster inherits pg_ctl's
        # handles and would otherwise keep a captured pipe open indefinitely.
        subprocess.run(
            [
                self._bin("pg_ctl"),
                "start",
                "--pgdata",
                str(self.data_dir),
                "--log",
                str(self.log_path),
                "--options",
                server_options,
                "--wait",
                "--timeout",
                "60",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        _wait_until(self._accepts_connections, "PostgreSQL", self.log_path)
        with self.admin_connect() as connection:
            connection.execute(
                sql.SQL("CREATE DATABASE {}").format(
                    sql.Identifier(DISPOSABLE_CLUSTER_MARKER_DATABASE)
                )
            )

    def _accepts_connections(self) -> bool:
        try:
            with self.admin_connect():
                return True
        except psycopg.OperationalError:
            return False

    def stop(self) -> None:
        if self.data_dir.is_dir():
            subprocess.run(
                [
                    self._bin("pg_ctl"),
                    "stop",
                    "--pgdata",
                    str(self.data_dir),
                    "--mode",
                    "immediate",
                    "--wait",
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        remove_tree(self.root)

    def _assert_is_disposable_cluster(self) -> None:
        # Positive identification: only a cluster this harness created carries the marker.
        with self.admin_connect() as connection:
            marker = connection.execute(
                "SELECT 1 FROM pg_database WHERE datname = %s",
                (DISPOSABLE_CLUSTER_MARKER_DATABASE,),
            ).fetchone()
        if marker is None:
            raise RuntimeError("refusing to modify a cluster without the disposable marker")

    def create_database(self, *, template: str | None = None) -> str:
        self._assert_is_disposable_cluster()
        name = require_disposable_database_name(
            f"{TEST_DATABASE_NAME_PREFIX}db_{secrets.token_hex(6)}"
        )
        statement = sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name))
        if template is not None:
            statement = sql.SQL("CREATE DATABASE {} TEMPLATE {}").format(
                sql.Identifier(name), sql.Identifier(require_disposable_database_name(template))
            )
        with self.admin_connect() as connection:
            connection.execute(statement)
        return name

    def drop_database(self, name: str) -> None:
        self._assert_is_disposable_cluster()
        require_disposable_database_name(name)
        with self.admin_connect() as connection:
            connection.execute(
                sql.SQL("DROP DATABASE IF EXISTS {} WITH (FORCE)").format(sql.Identifier(name))
            )

    def run_migration_cli(
        self, database: str, *arguments: str, env_overrides: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "MIGRATION_DATABASE_URL": self.migration_url(database),
            "ENVIRONMENT": "test",
            "DATABASE__URL": self.runtime_url(database),
            "PYTHONIOENCODING": "utf-8",
            **(env_overrides or {}),
        }
        return subprocess.run(
            [sys.executable, "scripts/db_migrate.py", *arguments],
            cwd=BACKEND_DIR,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

    def migrated_template(self) -> str:
        """A database upgraded once to the frozen head with the CLI; cloned per test."""
        if self._template_database is None:
            name = self.create_database()
            upgrade = self.run_migration_cli(name, "upgrade")
            if upgrade.returncode != 0:
                raise RuntimeError(f"migration of the template failed:\n{upgrade.stderr[-3000:]}")
            password = self.run_migration_cli(name, "set-runtime-password")
            if password.returncode != 0:
                raise RuntimeError(f"set-runtime-password failed:\n{password.stderr}")
            self._template_database = name
        return self._template_database


def start_postgres_cluster() -> PostgresCluster:
    cluster = PostgresCluster(
        bin_dir=find_postgres_bin_dir(),
        root=Path(tempfile.mkdtemp(prefix="voice_agent_test_pg_")),
        port=free_port(),
        bootstrap_password=secrets.token_urlsafe(24),
    )
    try:
        cluster.start()
    except BaseException:
        cluster.stop()
        raise
    return cluster


@dataclass
class RedisServer:
    """A throwaway redis-server process; nothing is persisted to disk.

    The password is excluded from ``repr`` and is passed to the server through a
    its standard input, never on the command line, so it does
    not appear in the ``Popen`` repr or in process listings (D0-M-03).
    """

    process: subprocess.Popen[bytes]
    root: Path
    port: int
    password: str = field(repr=False)

    @property
    def url(self) -> str:
        return f"redis://:{self.password}@{HOST}:{self.port}/0"

    def is_running(self) -> bool:
        return self.process.poll() is None

    def stop(self) -> None:
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait(timeout=30)
        remove_tree(self.root)


def start_redis_server(*, port: int | None = None, password: str | None = None) -> RedisServer:
    """Start a redis-server; ``port`` and ``password`` allow restarting "the same" server."""
    binary = find_redis_server()
    root = Path(tempfile.mkdtemp(prefix="voice_agent_test_redis_"))
    port = free_port() if port is None else port
    password = secrets.token_urlsafe(24) if password is None else password
    log_path = root / "redis.log"
    config_lines = [
        f"port {port}",
        f"bind {HOST}",
        'save ""',
        "appendonly no",
        f'dir "{root.as_posix()}"',
        f"requirepass {password}",
    ]
    with log_path.open("w", encoding="utf-8") as log:
        # "-" makes redis-server read its configuration from stdin.
        process = subprocess.Popen(
            [str(binary), "-"],
            stdin=subprocess.PIPE,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    assert process.stdin is not None
    process.stdin.write("".join(f"{line}\n" for line in config_lines).encode())
    process.stdin.close()
    server = RedisServer(process=process, root=root, port=port, password=password)

    def answers_ping() -> bool:
        if not server.is_running():
            raise InfrastructureUnavailableError(
                "redis-server exited:\n" + log_path.read_text(encoding="utf-8", errors="replace")
            )
        try:
            with Redis(host=HOST, port=port, password=password, socket_timeout=1) as client:
                return bool(client.ping())
        except RedisError:
            return False

    try:
        _wait_until(answers_ping, "Redis", log_path)
    except BaseException:
        server.stop()
        raise
    return server


@contextmanager
def redis_server() -> Iterator[RedisServer]:
    server = start_redis_server()
    try:
        yield server
    finally:
        server.stop()
