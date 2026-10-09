"""The frozen migration chain on a real, clean PostgreSQL 18 cluster."""

from __future__ import annotations

import pytest
from psycopg import sql

from tests.conftest import make_settings
from tests.support.infrastructure import BOOTSTRAP_ROLE, RUNTIME_ROLE, PostgresCluster, RedisServer
from voice_agent.platform.infrastructure.db.engine import create_database_engine
from voice_agent.platform.infrastructure.db.schema_baseline import (
    EXPECTED_SCHEMA_HEAD,
    REQUIRED_EXTENSIONS,
    SchemaRevisionStatus,
    verify_database_baseline,
)
from voice_agent.platform.infrastructure.db.session import Database
from voice_agent.platform.shared_kernel.errors import DatabaseError

pytestmark = pytest.mark.integration


def _database(
    cluster: PostgresCluster, name: str, redis: RedisServer, *, user: str = RUNTIME_ROLE
) -> Database:
    settings = make_settings(database_url=cluster.runtime_url(name, user=user), redis_url=redis.url)
    return Database(create_database_engine(settings.database, application_name="d0-migration-test"))


def test_migration_graph_cli_accepts_the_frozen_package(postgres_cluster: PostgresCluster) -> None:
    result = postgres_cluster.run_migration_cli("unused", "graph")
    assert result.returncode == 0, result.stderr
    assert "revisions:      112" in result.stdout
    assert "sql migrations: 112" in result.stdout
    assert "roots:          001_5B" in result.stdout
    assert "heads:          112_5H5" in result.stdout
    assert "linear chain:   yes" in result.stdout


def test_clean_postgres_18_database_reaches_the_frozen_head(
    postgres_cluster: PostgresCluster,
) -> None:
    template = postgres_cluster.migrated_template()  # upgraded from empty by the CLI
    check = postgres_cluster.run_migration_cli(template, "check", "--expect-head")
    assert check.returncode == 0, check.stdout + check.stderr
    assert f"current revision: {EXPECTED_SCHEMA_HEAD}" in check.stdout
    with postgres_cluster.admin_connect(template) as connection:
        version = connection.execute("SELECT current_setting('server_version_num')::int").fetchone()
        revisions = connection.execute("SELECT version_num FROM alembic_version").fetchall()
        extensions: dict[object, object] = dict(
            (row[0], row[1])
            for row in connection.execute("SELECT extname, extversion FROM pg_extension")
        )
        preload = connection.execute("SHOW shared_preload_libraries").fetchone()
        statements = connection.execute("SELECT count(*) FROM pg_stat_statements").fetchone()
    assert version is not None and 180000 <= int(str(version[0])) < 190000
    assert revisions == [(EXPECTED_SCHEMA_HEAD,)]
    assert set(REQUIRED_EXTENSIONS) <= set(extensions)
    assert preload is not None and "pg_stat_statements" in str(preload[0])
    assert statements is not None  # the extension is not only installed but functional


def test_upgrade_at_head_is_a_no_op(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    result = postgres_cluster.run_migration_cli(migrated_database, "upgrade")
    assert result.returncode == 0, result.stderr
    assert f"database at {EXPECTED_SCHEMA_HEAD}" in result.stdout


def test_upgrade_refuses_a_schema_without_alembic_bookkeeping(
    postgres_cluster: PostgresCluster, migrated_database: str
) -> None:
    with postgres_cluster.admin_connect(migrated_database) as connection:
        connection.execute("DROP TABLE public.alembic_version")
    result = postgres_cluster.run_migration_cli(migrated_database, "upgrade")
    assert result.returncode == 1
    assert "must be stamped, not upgraded" in result.stderr


def test_check_reports_an_unmigrated_database(postgres_cluster: PostgresCluster) -> None:
    empty = postgres_cluster.create_database()
    try:
        result = postgres_cluster.run_migration_cli(empty, "check", "--expect-head")
    finally:
        postgres_cluster.drop_database(empty)
    assert result.returncode == 1
    assert "not at the frozen head" in result.stderr
    assert "extension 'vector' is not installed" in result.stderr


async def test_runtime_role_is_least_privileged_and_schema_currency_is_deployment_gated(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    database = _database(postgres_cluster, migrated_database, redis_service)
    try:
        report = await verify_database_baseline(database)
    finally:
        await database.dispose()
    assert report.runtime_role == RUNTIME_ROLE
    assert report.server_version_num >= 180000
    # The frozen grants give app_api no access to alembic_version (OD-D0-01: no grant is
    # added); startup reports that currency is the deployment gate's, never "verified".
    assert report.schema_revision_status is SchemaRevisionStatus.DEPLOYMENT_GATED


def _grant_revision_read(
    cluster: PostgresCluster, name: str, *, set_revision: str | None = None
) -> None:
    # Test-only privilege on a disposable copy, used to exercise the comparison.
    with cluster.admin_connect(name) as connection:
        connection.execute(
            sql.SQL("GRANT SELECT ON public.alembic_version TO {}").format(
                sql.Identifier(RUNTIME_ROLE)
            )
        )
        if set_revision is not None:
            connection.execute(
                "UPDATE public.alembic_version SET version_num = %s", (set_revision,)
            )


async def test_matching_revision_is_verified_when_readable(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    _grant_revision_read(postgres_cluster, migrated_database)
    database = _database(postgres_cluster, migrated_database, redis_service)
    try:
        report = await verify_database_baseline(database)
    finally:
        await database.dispose()
    assert report.schema_revision_status is SchemaRevisionStatus.VERIFIED


async def test_revision_mismatch_is_rejected(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    _grant_revision_read(postgres_cluster, migrated_database, set_revision="111_5H4")
    database = _database(postgres_cluster, migrated_database, redis_service)
    try:
        with pytest.raises(DatabaseError) as raised:
            await verify_database_baseline(database)
    finally:
        await database.dispose()
    assert raised.value.context["reason"] == "schema_revision_mismatch"
    assert raised.value.context["found"] == ["111_5H4"]


async def test_missing_required_extension_is_rejected(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    with postgres_cluster.admin_connect(migrated_database) as connection:
        connection.execute("DROP EXTENSION pg_stat_statements")
    database = _database(postgres_cluster, migrated_database, redis_service)
    try:
        with pytest.raises(DatabaseError) as raised:
            await verify_database_baseline(database)
    finally:
        await database.dispose()
    assert raised.value.context == {
        "reason": "required_extension_missing",
        "missing": ["pg_stat_statements"],
    }


async def test_unmigrated_database_is_rejected(
    postgres_cluster: PostgresCluster, redis_service: RedisServer
) -> None:
    postgres_cluster.migrated_template()  # ensures the app_api role and its password exist
    empty = postgres_cluster.create_database()
    database = _database(postgres_cluster, empty, redis_service)
    try:
        with pytest.raises(DatabaseError) as raised:
            await verify_database_baseline(database)
    finally:
        await database.dispose()
        postgres_cluster.drop_database(empty)
    assert raised.value.context["reason"] == "required_extension_missing"


async def test_superuser_runtime_identity_is_rejected(
    postgres_cluster: PostgresCluster, migrated_database: str, redis_service: RedisServer
) -> None:
    database = _database(postgres_cluster, migrated_database, redis_service, user=BOOTSTRAP_ROLE)
    try:
        with pytest.raises(DatabaseError) as raised:
            await verify_database_baseline(database)
    finally:
        await database.dispose()
    assert raised.value.context["reason"] == "runtime_role_overprivileged"
