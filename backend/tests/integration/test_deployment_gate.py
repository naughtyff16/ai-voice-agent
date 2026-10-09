"""The deployment schema-current gate against real PostgreSQL 18 (OD-D0-01).

Each test runs the real CLI as a subprocess, with migration credentials, against
a disposable copy of the migrated database that stands in for the deployment
target.
"""

from __future__ import annotations

import secrets
import subprocess

import pytest
from psycopg import sql

from tests.conftest import make_settings
from tests.support.infrastructure import (
    HOST,
    RUNTIME_ROLE,
    PostgresCluster,
    RedisServer,
    free_port,
)
from voice_agent.apps.api.main import create_app
from voice_agent.platform.infrastructure.db.schema_baseline import EXPECTED_SCHEMA_HEAD

pytestmark = pytest.mark.integration

GATE = ("gate", "--expected-head", EXPECTED_SCHEMA_HEAD)


def _output(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def _assert_no_credentials(cluster: PostgresCluster, text: str) -> None:
    assert cluster.bootstrap_password not in text
    assert cluster.runtime_password not in text


def _set_revision(cluster: PostgresCluster, database: str, revision: str) -> None:
    with cluster.admin_connect(database) as connection:
        connection.execute("UPDATE public.alembic_version SET version_num = %s", (revision,))


def test_gate_passes_on_a_target_at_the_exact_expected_head(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    result = postgres_cluster.run_migration_cli(migrated_database, *GATE)
    output = _output(result)
    assert result.returncode == 0, output
    assert f"expected head:    {EXPECTED_SCHEMA_HEAD}" in output
    assert f"repository head:  {EXPECTED_SCHEMA_HEAD}" in output
    assert f"current revision: {EXPECTED_SCHEMA_HEAD}" in output
    # The actual target is reported, as observed from the server.
    assert f"/{migrated_database}" in output
    assert "deployment gate passed" in output
    _assert_no_credentials(postgres_cluster, output)


def test_gate_fails_on_a_stale_target(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    _set_revision(postgres_cluster, migrated_database, "111_5H4")
    result = postgres_cluster.run_migration_cli(migrated_database, *GATE)
    assert result.returncode == 1
    assert "Deployment gate FAILED" in result.stderr
    assert "stale: at 111_5H4, 1 revision(s) behind 112_5H5" in result.stderr
    assert "gate passed" not in _output(result)


def test_gate_fails_on_an_unknown_revision(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    _set_revision(postgres_cluster, migrated_database, "999_ZZ")
    result = postgres_cluster.run_migration_cli(migrated_database, *GATE)
    assert result.returncode == 1
    assert "unknown revision '999_ZZ'" in result.stderr


def test_gate_fails_without_an_alembic_version_table(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    with postgres_cluster.admin_connect(migrated_database) as connection:
        connection.execute("DROP TABLE public.alembic_version")
    result = postgres_cluster.run_migration_cli(migrated_database, *GATE)
    assert result.returncode == 1
    assert "no alembic_version table" in result.stderr


def test_gate_fails_on_an_unmigrated_target(postgres_cluster: PostgresCluster) -> None:
    empty = postgres_cluster.create_database()
    try:
        result = postgres_cluster.run_migration_cli(empty, *GATE)
    finally:
        postgres_cluster.drop_database(empty)
    assert result.returncode == 1
    assert "no alembic_version table" in result.stderr
    assert "required extension 'vector' is not installed" in result.stderr


def test_gate_fails_on_a_wrong_expected_head(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    # Even though the database itself is at 111_5H4, a build expecting it is refused:
    # the expected head must be the repository head.
    _set_revision(postgres_cluster, migrated_database, "111_5H4")
    result = postgres_cluster.run_migration_cli(
        migrated_database, "gate", "--expected-head", "111_5H4"
    )
    assert result.returncode == 1
    assert "is not the repository head 112_5H5" in result.stderr


def test_gate_fails_closed_when_the_target_is_unreachable(
    postgres_cluster: PostgresCluster,
) -> None:
    password = secrets.token_urlsafe(16)
    url = f"postgresql+psycopg://deployer:{password}@{HOST}:{free_port()}/voice_agent_test_gone"
    result = postgres_cluster.run_migration_cli(
        "unused", *GATE, env_overrides={"MIGRATION_DATABASE_URL": url}
    )
    output = _output(result)
    assert result.returncode == 1
    assert "error: database operation failed (" in result.stderr
    assert password not in output
    assert "gate passed" not in output


def test_gate_fails_closed_on_rejected_credentials(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    wrong = secrets.token_urlsafe(16)
    url = postgres_cluster.migration_url(migrated_database).replace(
        postgres_cluster.bootstrap_password, wrong
    )
    result = postgres_cluster.run_migration_cli(
        migrated_database, *GATE, env_overrides={"MIGRATION_DATABASE_URL": url}
    )
    assert result.returncode == 1
    assert wrong not in _output(result)


def test_gate_refuses_runtime_credentials(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    # The runtime role's real, working credentials: refused by identity, not by failure.
    url = (
        f"postgresql+psycopg://{RUNTIME_ROLE}:{postgres_cluster.runtime_password}"
        f"@{HOST}:{postgres_cluster.port}/{migrated_database}"
    )
    result = postgres_cluster.run_migration_cli(
        migrated_database, *GATE, env_overrides={"MIGRATION_DATABASE_URL": url}
    )
    output = _output(result)
    assert result.returncode == 1
    assert "runtime role 'app_api'" in result.stderr
    _assert_no_credentials(postgres_cluster, output)


def test_gate_refuses_a_session_switched_to_a_runtime_role(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    # A deployment role whose sessions run as app_api must not satisfy the gate either.
    with postgres_cluster.admin_connect(migrated_database) as connection:
        role = sql.Identifier("d0_gate_switcher")
        password = secrets.token_urlsafe(16)
        connection.execute(
            sql.SQL("CREATE ROLE {} LOGIN PASSWORD {} IN ROLE {}").format(
                role, sql.Literal(password), sql.Identifier(RUNTIME_ROLE)
            )
        )
        connection.execute(
            sql.SQL("ALTER ROLE {} SET role = {}").format(role, sql.Literal(RUNTIME_ROLE))
        )
    try:
        url = (
            f"postgresql+psycopg://d0_gate_switcher:{password}"
            f"@{HOST}:{postgres_cluster.port}/{migrated_database}"
        )
        result = postgres_cluster.run_migration_cli(
            migrated_database, *GATE, env_overrides={"MIGRATION_DATABASE_URL": url}
        )
    finally:
        with postgres_cluster.admin_connect() as connection:
            connection.execute("DROP ROLE d0_gate_switcher")
    assert result.returncode == 1
    assert "connected as a runtime role" in result.stderr
    assert password not in _output(result)


async def test_runtime_readiness_never_claims_the_schema_is_current(
    postgres_cluster: PostgresCluster,
    migrated_database: str,
    redis_service: RedisServer,
    capsys: pytest.CaptureFixture[str],
) -> None:
    # A stale target: the deployment gate rejects it...
    _set_revision(postgres_cluster, migrated_database, "111_5H4")
    gate = postgres_cluster.run_migration_cli(migrated_database, *GATE)
    assert gate.returncode == 1

    # ...while runtime readiness, being operational only, still answers for
    # connectivity and says nothing about migrations.
    import httpx

    settings = make_settings(
        database_url=postgres_cluster.runtime_url(migrated_database), redis_url=redis_service.url
    )
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            ready = await client.get("/health/ready")
    assert ready.status_code == 200
    assert ready.json() == {"status": "ok", "checks": {"postgres": "ok", "redis": "ok"}}
    logs = capsys.readouterr().out
    assert '"schema_revision_status": "deployment_gated"' in logs
    assert '"schema_revision_status": "verified"' not in logs
    for claim in ("migration", "schema_current", "alembic"):
        assert claim not in ready.text
