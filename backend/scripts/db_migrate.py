"""Operator CLI for the frozen database migration package.

The schema is owned by the frozen SQL package under
``docs/phase-05-database-design/5K``. This tool only validates that package and
drives its existing Alembic integration layer; it never authors a migration.
Application startup never migrates: migrations are an explicit, separate
deployment step (3F §6.2).

Commands::

    graph                  validate the migration graph on disk (no database)
    check                  report server prerequisites and the current revision
    upgrade                upgrade the target database to the frozen head
    gate                   DEPLOYMENT GATE: fail unless the target database is at
                           exactly the expected head (run before every rollout)
    set-runtime-password   local/test only: give a runtime role a login password

Deployment gate (controlled architecture reconciliation OD-D0-01): schema
currency is proven here, against the actual target database, with migration
credentials, before the application is rolled out. The application's runtime
readiness probe checks operational connectivity only and never claims the
schema is current; the least-privileged runtime role cannot read
``alembic_version`` and is not granted that access.

Credentials:

* ``MIGRATION_DATABASE_URL`` (``postgresql+psycopg://``) is the administrative
  migration/deployment identity. Migration 001 creates roles and extensions, so
  a fresh database needs a bootstrap role with those rights (a superuser on a
  local disposable cluster; Supabase pre-installs the extensions). It is never
  a runtime identity: ``app_api``, ``app_worker`` and ``app_readonly`` are refused.
* ``DATABASE__URL`` is the runtime identity, used only by ``set-runtime-password``.

Target safety: before any connection, every command derives the target libpq
will actually use and refuses forms that could redirect it — query parameters
such as host, hostaddr, port, dbname, user, service, servicefile or options; a
host list or socket path; a missing port; and the PGHOSTADDR, PGSERVICE and
PGSERVICEFILE environment variables.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Final

import psycopg
from psycopg import sql
from pydantic import ValidationError
from sqlalchemy.engine import URL, make_url
from sqlalchemy.exc import ArgumentError

from voice_agent.platform.config.base_settings import DatabaseSettings, is_single_host
from voice_agent.platform.infrastructure.db.migration_graph import (
    MigrationGraphError,
    MigrationGraphReport,
    find_baseline_violations,
    inspect_migration_package,
)
from voice_agent.platform.infrastructure.db.schema_baseline import (
    BASELINE_POSTGRES_MAJOR,
    EXPECTED_SCHEMA_HEAD,
    MINIMUM_POSTGRES_VERSION_NUM,
    REQUIRED_EXTENSIONS,
)

REPOSITORY_ROOT: Final = Path(__file__).resolve().parents[2]
MIGRATION_PACKAGE_DIR: Final = REPOSITORY_ROOT / "docs" / "phase-05-database-design" / "5K"
ALEMBIC_DIR: Final = MIGRATION_PACKAGE_DIR / "alembic"

MIGRATION_URL_ENV: Final = "MIGRATION_DATABASE_URL"
RUNTIME_URL_ENV: Final = "DATABASE__URL"
MIGRATION_DRIVER: Final = "postgresql+psycopg"
# A schema created by migration 001; its presence without alembic_version means
# the database was migrated outside Alembic and must be stamped, not upgraded.
SENTINEL_SCHEMA: Final = "identity"
RUNTIME_ROLES: Final = frozenset({"app_api", "app_worker", "app_readonly"})
LOOPBACK_HOSTS: Final = frozenset({"127.0.0.1", "::1", "localhost"})
LOOPBACK_SERVER_ADDRESSES: Final = frozenset({"127.0.0.1", "::1"})
PASSWORD_ENVIRONMENTS: Final = frozenset({"local", "test"})

# libpq URI query parameters that cannot change which server, database or role
# the connection reaches. Everything else is refused.
SAFE_LIBPQ_QUERY_PARAMETERS: Final = frozenset(
    {
        "application_name",
        "channel_binding",
        "connect_timeout",
        "gssencmode",
        "ssl_max_protocol_version",
        "ssl_min_protocol_version",
        "sslcert",
        "sslcrl",
        "sslcrldir",
        "sslkey",
        "sslmode",
        "sslnegotiation",
        "sslrootcert",
        "sslsni",
    }
)
# Named in refusals; any other unrecognised parameter is reported generically.
_TARGET_KEYWORDS: Final = frozenset(
    {"host", "hostaddr", "port", "dbname", "user", "service", "servicefile", "options"}
)
# libpq reads these even when the URL is explicit: PGHOSTADDR replaces the
# address actually dialled, and a service definition can supply hostaddr.
REDIRECTING_ENVIRONMENT: Final = ("PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE")


class CommandError(Exception):
    """A refusal or failure reported to the operator; never carries credentials."""


@dataclass(frozen=True, slots=True)
class LibpqTarget:
    """Where libpq will connect: every field is explicit, so no default or variable applies."""

    host: str
    port: int
    dbname: str
    user: str

    def describe(self) -> str:
        return f"{self.user}@{self.host}:{self.port}/{self.dbname}"


def _migration_url() -> URL:
    raw = os.environ.get(MIGRATION_URL_ENV)
    if not raw:
        raise CommandError(f"{MIGRATION_URL_ENV} is not set.")
    try:
        url = make_url(raw)
        _ = url.port
    except (ArgumentError, ValueError):
        raise CommandError(f"{MIGRATION_URL_ENV} is not a valid database URL.") from None
    if url.drivername != MIGRATION_DRIVER:
        raise CommandError(f"{MIGRATION_URL_ENV} must use the {MIGRATION_DRIVER} driver.")
    if url.username in RUNTIME_ROLES:
        raise CommandError(
            f"{MIGRATION_URL_ENV} names the runtime role '{url.username}'. Migrations and the "
            "deployment gate run with migration/deployment credentials, never a runtime identity."
        )
    return url


def migration_target(url: URL) -> LibpqTarget:
    """Derive the effective libpq target of ``url``, or refuse. Opens no connection."""
    unsafe = sorted(set(url.query) - SAFE_LIBPQ_QUERY_PARAMETERS)
    if unsafe:
        named = [name for name in unsafe if name in _TARGET_KEYWORDS]
        found = ", ".join(named) if named else "unrecognised parameters"
        raise CommandError(
            f"{MIGRATION_URL_ENV} must not carry connection-target query parameters "
            f"({found}); only TLS and timeout options are accepted."
        )
    redirecting = [name for name in REDIRECTING_ENVIRONMENT if os.environ.get(name)]
    if redirecting:
        raise CommandError(
            f"Refusing to connect while {', '.join(redirecting)} is set: libpq would use it "
            "to redirect the connection away from the URL's host."
        )
    if not url.host or not is_single_host(url.host):
        raise CommandError(
            f"{MIGRATION_URL_ENV} must name exactly one host (a DNS name or IP address); "
            "host lists and socket paths are not supported."
        )
    if url.port is None or not 1 <= url.port <= 65535:
        raise CommandError(f"{MIGRATION_URL_ENV} must name its port explicitly (1-65535).")
    if not url.database or not url.username:
        raise CommandError(f"{MIGRATION_URL_ENV} must name a database and a user.")
    return LibpqTarget(host=url.host, port=url.port, dbname=url.database, user=url.username)


def _connect(url: URL) -> psycopg.Connection[tuple[object, ...]]:
    # libpq accepts the URL itself once the SQLAlchemy driver suffix is removed;
    # the remaining query parameters are the TLS/timeout options checked above.
    conninfo = url.set(drivername="postgresql").render_as_string(hide_password=False)
    return psycopg.connect(conninfo, connect_timeout=10, application_name="db_migrate")


def _connected_identity(
    connection: psycopg.Connection[tuple[object, ...]],
) -> tuple[str, str, str, str | None, int | None]:
    """session_user, current_user, current_database, server address, server port."""
    row = connection.execute(
        "SELECT session_user, current_user, current_database(), "
        "host(inet_server_addr()), inet_server_port()"
    ).fetchone()
    if row is None:
        raise CommandError("Could not read the connected identity.")
    session_user, current_user, database, address, port = row
    return (
        str(session_user),
        str(current_user),
        str(database),
        None if address is None else str(address),
        None if port is None else int(str(port)),
    )


def missing_prerequisites(
    *, server_version_num: int, available: set[str], preloaded_libraries: set[str]
) -> list[str]:
    """Server-level problems that would stop a clean upgrade or the runtime check."""
    problems: list[str] = []
    if server_version_num < MINIMUM_POSTGRES_VERSION_NUM:
        problems.append(f"PostgreSQL {server_version_num} is below the supported minimum")
    for extension in REQUIRED_EXTENSIONS:
        if extension not in available:
            problems.append(f"extension '{extension}' is not available on the server")
    if "pg_stat_statements" not in preloaded_libraries:
        problems.append("shared_preload_libraries does not include pg_stat_statements")
    return problems


def revision_problem(
    revisions: list[str] | None, *, expected: str, chain: Sequence[str]
) -> str | None:
    """Why the recorded revisions are not exactly ``expected``; None when they are."""
    if revisions is None:
        return (
            "the database has no alembic_version table: it has not been migrated, or it was "
            "migrated outside Alembic and must be stamped"
        )
    if revisions == [expected]:
        return None
    if not revisions:
        return "alembic_version records no revision"
    if len(revisions) > 1:
        return f"alembic_version records several revisions {revisions}"
    (found,) = revisions
    if found not in chain:
        return f"the database is at unknown revision {found!r}, not in the repository graph"
    if expected in chain and chain.index(found) < chain.index(expected):
        behind = chain.index(expected) - chain.index(found)
        return f"the database is stale: at {found}, {behind} revision(s) behind {expected}"
    return f"the database is at {found}, not {expected}"


def _validated_graph() -> MigrationGraphReport:
    report = inspect_migration_package(MIGRATION_PACKAGE_DIR)
    violations = find_baseline_violations(report)
    if violations:
        raise CommandError(
            "Migration graph is NOT the frozen baseline:\n  " + "\n  ".join(violations)
        )
    return report


def command_graph(_args: argparse.Namespace) -> None:
    report = inspect_migration_package(MIGRATION_PACKAGE_DIR)
    print(f"revisions:      {report.revision_count}")
    print(f"sql migrations: {report.sql_file_count}")
    print(f"roots:          {', '.join(report.roots)}")
    print(f"heads:          {', '.join(report.heads)}")
    print(f"linear chain:   {'yes' if report.chain else 'no'}")
    print(f"package sha256: {report.package_sha256}")
    _validated_graph()
    print(f"result:         OK: frozen baseline, sole head {EXPECTED_SCHEMA_HEAD}")


def _current_revisions(connection: psycopg.Connection[tuple[object, ...]]) -> list[str] | None:
    exists = connection.execute("SELECT to_regclass('public.alembic_version')").fetchone()
    if exists is None or exists[0] is None:
        return None
    rows = connection.execute("SELECT version_num FROM public.alembic_version").fetchall()
    return sorted(str(row[0]) for row in rows)


def _installed_extensions(connection: psycopg.Connection[tuple[object, ...]]) -> set[str]:
    return {str(row[0]) for row in connection.execute("SELECT extname FROM pg_extension")}


def command_check(args: argparse.Namespace) -> None:
    url = _migration_url()
    migration_target(url)
    with _connect(url) as connection:
        version_row = connection.execute("SELECT current_setting('server_version_num')").fetchone()
        server_version_num = int(str(version_row[0])) if version_row else 0
        available = {
            str(row[0])
            for row in connection.execute("SELECT name FROM pg_available_extensions").fetchall()
        }
        installed = _installed_extensions(connection)
        preload_row = connection.execute(
            "SELECT current_setting('shared_preload_libraries')"
        ).fetchone()
        preloaded = {part.strip() for part in str(preload_row[0] if preload_row else "").split(",")}
        revisions = _current_revisions(connection)

    print(f"server_version_num: {server_version_num} (baseline major {BASELINE_POSTGRES_MAJOR})")
    for extension in REQUIRED_EXTENSIONS:
        state = (
            "installed"
            if extension in installed
            else ("available" if extension in available else "MISSING")
        )
        print(f"extension {extension}: {state}")
    print(f"current revision: {', '.join(revisions) if revisions else 'none'}")

    problems = missing_prerequisites(
        server_version_num=server_version_num, available=available, preloaded_libraries=preloaded
    )
    if args.expect_head and revisions != [EXPECTED_SCHEMA_HEAD]:
        problems.append(f"database is not at the frozen head {EXPECTED_SCHEMA_HEAD}")
    if args.expect_head:
        problems.extend(
            f"extension '{name}' is not installed"
            for name in REQUIRED_EXTENSIONS
            if name not in installed
        )
    if problems:
        raise CommandError("Prerequisite check failed:\n  " + "\n  ".join(problems))
    print("result: OK")


def command_gate(args: argparse.Namespace) -> None:
    """The deployment schema-current gate. Exits non-zero on every doubt."""
    expected: str = args.expected_head
    # 1. The repository graph is the frozen baseline and its sole head is the expected one.
    report = _validated_graph()
    (repository_head,) = report.heads
    if expected != repository_head:
        raise CommandError(
            f"Deployment gate FAILED: expected head {expected!r} is not the repository "
            f"head {repository_head}."
        )
    if expected != EXPECTED_SCHEMA_HEAD:
        raise CommandError(
            f"Deployment gate FAILED: expected head {expected!r} is not the head this "
            f"application build requires ({EXPECTED_SCHEMA_HEAD})."
        )
    # 2. The target is derived and checked before connecting.
    url = _migration_url()
    target = migration_target(url)
    print(f"target:           {target.describe()}")
    # 3. The actual target database, read with migration/deployment credentials.
    with _connect(url) as connection:
        session_user, current_user, database, address, port = _connected_identity(connection)
        if session_user in RUNTIME_ROLES or current_user in RUNTIME_ROLES:
            raise CommandError(
                "Deployment gate FAILED: connected as a runtime role. The gate must use "
                "migration/deployment credentials."
            )
        if database != target.dbname:
            raise CommandError(
                f"Deployment gate FAILED: connected to database {database!r}, "
                f"not {target.dbname!r}."
            )
        revisions = _current_revisions(connection)
        installed = _installed_extensions(connection)
    print(f"connected:        {session_user}@{address or 'local socket'}:{port}/{database}")
    print(f"expected head:    {expected}")
    print(f"repository head:  {repository_head}")
    print(f"current revision: {', '.join(revisions) if revisions else 'none'}")
    problems = []
    if (problem := revision_problem(revisions, expected=expected, chain=report.chain)) is not None:
        problems.append(problem)
    problems.extend(
        f"required extension '{name}' is not installed"
        for name in REQUIRED_EXTENSIONS
        if name not in installed
    )
    if problems:
        raise CommandError("Deployment gate FAILED:\n  " + "\n  ".join(problems))
    print(f"result: OK: deployment gate passed, target database is at {expected}")


def command_upgrade(_args: argparse.Namespace) -> None:
    command_graph(_args)
    url = _migration_url()
    migration_target(url)
    with _connect(url) as connection:
        revisions = _current_revisions(connection)
        sentinel = connection.execute(
            "SELECT 1 FROM pg_namespace WHERE nspname = %s", (SENTINEL_SCHEMA,)
        ).fetchone()
    if revisions is None and sentinel is not None:
        raise CommandError(
            "The database contains the platform schema but no alembic_version table. It was "
            "migrated outside Alembic and must be stamped, not upgraded: see "
            "docs/phase-05-database-design/5K/alembic/README.md, 'Baseline strategy'."
        )
    if revisions is not None and len(revisions) > 1:
        raise CommandError(f"The database records several revisions: {revisions}.")

    # The frozen env.py reads DATABASE_URL; it is set for the child process only.
    env = {**os.environ, "DATABASE_URL": url.render_as_string(hide_password=False)}
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "-c", "alembic.ini", "upgrade", EXPECTED_SCHEMA_HEAD],
        cwd=ALEMBIC_DIR,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        raise CommandError(f"alembic upgrade failed with exit code {result.returncode}.")
    with _connect(url) as connection:
        revisions = _current_revisions(connection)
    if revisions != [EXPECTED_SCHEMA_HEAD]:
        raise CommandError(f"After upgrade the database records {revisions}.")
    print(f"result: OK: database at {EXPECTED_SCHEMA_HEAD}")


def command_set_runtime_password(_args: argparse.Namespace) -> None:
    """Local/test only. Every check below runs before the first connection."""
    environment = os.environ.get("ENVIRONMENT")
    if environment not in PASSWORD_ENVIRONMENTS:
        raise CommandError(
            "set-runtime-password is only available when ENVIRONMENT is local or test."
        )
    raw_runtime = os.environ.get(RUNTIME_URL_ENV)
    if not raw_runtime:
        raise CommandError(f"{RUNTIME_URL_ENV} is not set.")
    try:
        runtime = DatabaseSettings.model_validate({"url": raw_runtime})
    except ValidationError:
        raise CommandError(f"{RUNTIME_URL_ENV} is not a valid runtime database URL.") from None
    runtime_url = runtime.sqlalchemy_url()
    runtime_target = runtime.target()
    migration_url = _migration_url()
    migration = migration_target(migration_url)

    if runtime_url.port is None:
        raise CommandError(f"{RUNTIME_URL_ENV} must name its port explicitly for this command.")
    if runtime_target.host not in LOOPBACK_HOSTS or migration.host not in LOOPBACK_HOSTS:
        raise CommandError("set-runtime-password only targets a PostgreSQL on this machine.")
    if (runtime_target.host, runtime_target.port, runtime_target.database) != (
        migration.host,
        migration.port,
        migration.dbname,
    ):
        raise CommandError(
            f"{RUNTIME_URL_ENV} and {MIGRATION_URL_ENV} must name the same local host, port "
            "and database."
        )
    if runtime_target.user not in RUNTIME_ROLES:
        raise CommandError(f"The runtime role must be one of {sorted(RUNTIME_ROLES)}.")
    password = runtime_url.password
    if not password:
        raise CommandError(f"{RUNTIME_URL_ENV} has no password to set.")

    with _connect(migration_url) as connection:
        # Defence in depth: the server actually reached must be the local one named.
        _, _, database, address, port = _connected_identity(connection)
        if address not in LOOPBACK_SERVER_ADDRESSES or (port, database) != (
            migration.port,
            migration.dbname,
        ):
            raise CommandError(
                "Refusing to alter a role: the connected server is not the local "
                f"database {migration.dbname} on port {migration.port}."
            )
        connection.execute(
            sql.SQL("ALTER ROLE {} WITH LOGIN PASSWORD {}").format(
                sql.Identifier(runtime_target.user), sql.Literal(password)
            )
        )
    print(f"result: OK: login password set for {runtime_target.user}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="db_migrate", description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("graph", help="validate the migration graph on disk").set_defaults(
        handler=command_graph
    )
    check = commands.add_parser("check", help="report prerequisites and current revision")
    check.add_argument("--expect-head", action="store_true", help="fail unless at the frozen head")
    check.set_defaults(handler=command_check)
    gate = commands.add_parser(
        "gate", help="deployment gate: fail unless the target database is at the expected head"
    )
    gate.add_argument(
        "--expected-head",
        required=True,
        help="the exact revision the application being rolled out requires",
    )
    gate.set_defaults(handler=command_gate)
    commands.add_parser("upgrade", help="upgrade to the frozen head").set_defaults(
        handler=command_upgrade
    )
    commands.add_parser(
        "set-runtime-password", help="local/test only: set the runtime role password"
    ).set_defaults(handler=command_set_runtime_password)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        args.handler(args)
    except (CommandError, MigrationGraphError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except psycopg.Error as exc:
        # The driver message can name the host but never contains the password;
        # only the exception type is reported.
        print(f"error: database operation failed ({type(exc).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
