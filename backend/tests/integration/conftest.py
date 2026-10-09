from __future__ import annotations

from collections.abc import Iterator

import pytest
from psycopg import sql

from tests.support.infrastructure import RUNTIME_ROLE, PostgresCluster

PROBE_SCHEMA = "d0_probe"
# Literal statements: the probe table name is fixed, nothing is interpolated.
CREATE_PROBE_TABLE_SQL = "CREATE TABLE d0_probe.rollback_probe (marker text PRIMARY KEY)"
GRANT_PROBE_TABLE_SQL = "GRANT SELECT, INSERT ON d0_probe.rollback_probe TO app_api"
INSERT_MARKER_SQL = "INSERT INTO d0_probe.rollback_probe (marker) VALUES (:marker)"
COUNT_MARKER_SQL = "SELECT count(*) FROM d0_probe.rollback_probe WHERE marker = %s"


@pytest.fixture
def probe_table(postgres_cluster: PostgresCluster, migrated_database: str) -> Iterator[str]:
    """A scratch table in this test's disposable database copy; yields its INSERT statement.

    The frozen schema offers no table the runtime role can write without tenant
    context, so the session-contract tests use this one. It is never part of any
    migration and disappears with the database.
    """
    with postgres_cluster.admin_connect(migrated_database) as connection:
        connection.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(PROBE_SCHEMA)))
        connection.execute(CREATE_PROBE_TABLE_SQL)
        connection.execute(
            sql.SQL("GRANT USAGE ON SCHEMA {} TO {}").format(
                sql.Identifier(PROBE_SCHEMA), sql.Identifier(RUNTIME_ROLE)
            )
        )
        connection.execute(GRANT_PROBE_TABLE_SQL)
    yield INSERT_MARKER_SQL


def count_markers(cluster: PostgresCluster, database: str, marker: str) -> int:
    with cluster.admin_connect(database) as connection:
        row = connection.execute(COUNT_MARKER_SQL, (marker,)).fetchone()
    assert row is not None
    return int(str(row[0]))


def application_connections(cluster: PostgresCluster, database: str, application_name: str) -> int:
    with cluster.admin_connect() as connection:
        row = connection.execute(
            "SELECT count(*) FROM pg_stat_activity WHERE datname = %s AND application_name = %s",
            (database, application_name),
        ).fetchone()
    assert row is not None
    return int(str(row[0]))
