"""The database baseline this code is built against, and its runtime verification.

The schema is migration-authoritative: the frozen SQL package under
``docs/phase-05-database-design/5K`` defines it and nothing here redefines it.
These constants only state which baseline the application expects.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Final

from sqlalchemy import text

from voice_agent.platform.infrastructure.db.session import CONNECTIVITY_ERRORS, Database
from voice_agent.platform.shared_kernel.errors import DatabaseError

EXPECTED_SCHEMA_ROOT: Final = "001_5B"
EXPECTED_SCHEMA_HEAD: Final = "112_5H5"
EXPECTED_REVISION_COUNT: Final = 112

# SHA-256 over the 230 files of the frozen package (5K/alembic + 5K/migrations) at
# commit b48c666, as computed by migration_graph.compute_package_digest.
FROZEN_MIGRATION_PACKAGE_SHA256: Final = (
    "a426138ed4a83c4cdfe892e281ffcd49823689345cc02198861ac3e9242be0b2"
)

REQUIRED_EXTENSIONS: Final[tuple[str, ...]] = ("pg_stat_statements", "pgcrypto", "vector")

# PostgreSQL 18.x is the authoritative baseline; 16 is the supported floor (5K §5).
BASELINE_POSTGRES_MAJOR: Final = 18
MINIMUM_POSTGRES_VERSION_NUM: Final = 160000


class SchemaRevisionStatus(StrEnum):
    """What application startup observed about the schema revision.

    Schema currency is owned by the deployment gate (``scripts/db_migrate.py
    gate``), run against the target database with migration credentials before
    rollout (controlled reconciliation OD-D0-01). The least-privileged runtime
    role holds no SELECT on ``alembic_version`` in the frozen schema, so startup
    normally cannot and need not read it.
    """

    # The runtime role could read the revision and it equals the expected head.
    VERIFIED = "verified"
    # The normal case: currency was proven by the deployment gate, not by startup.
    DEPLOYMENT_GATED = "deployment_gated"


@dataclass(frozen=True, slots=True)
class DatabaseBaselineReport:
    server_version_num: int
    runtime_role: str
    schema_revision_status: SchemaRevisionStatus


async def verify_database_baseline(database: Database) -> DatabaseBaselineReport:
    """Check the connected database against the baseline or raise ``DatabaseError``.

    Run once at startup. Every failure carries a ``reason`` in its context.
    """
    try:
        async with database.transaction() as session:
            server_version_num = int(
                (
                    await session.execute(text("SELECT current_setting('server_version_num')"))
                ).scalar_one()
            )
            if server_version_num < MINIMUM_POSTGRES_VERSION_NUM:
                raise DatabaseError(
                    "PostgreSQL is older than the supported minimum.",
                    context={
                        "reason": "postgres_version_unsupported",
                        "server_version_num": server_version_num,
                    },
                )

            role = (
                await session.execute(
                    text(
                        "SELECT rolname, rolsuper, rolbypassrls FROM pg_roles "
                        "WHERE rolname = current_user"
                    )
                )
            ).one()
            if role.rolsuper or role.rolbypassrls:
                # Running as such a role would silently defeat row-level security.
                raise DatabaseError(
                    "The application runtime role must not be a superuser or bypass RLS.",
                    context={"reason": "runtime_role_overprivileged", "role": role.rolname},
                )

            installed = set(
                (await session.execute(text("SELECT extname FROM pg_extension"))).scalars()
            )
            missing = sorted(set(REQUIRED_EXTENSIONS) - installed)
            if missing:
                raise DatabaseError(
                    "Required PostgreSQL extensions are not installed.",
                    context={"reason": "required_extension_missing", "missing": missing},
                )

            # has_table_privilege() is used instead of attempting the read: a denied
            # SELECT would abort the transaction. NULL means the table does not exist.
            can_read_revision = (
                await session.execute(
                    text(
                        "SELECT has_table_privilege(current_user, "
                        "to_regclass('public.alembic_version'), 'SELECT')"
                    )
                )
            ).scalar_one()
            if can_read_revision is None:
                raise DatabaseError(
                    "The database has not been migrated.",
                    context={"reason": "schema_not_migrated"},
                )
            if not can_read_revision:
                revision_status = SchemaRevisionStatus.DEPLOYMENT_GATED
            else:
                revisions = sorted(
                    (
                        await session.execute(text("SELECT version_num FROM alembic_version"))
                    ).scalars()
                )
                if revisions != [EXPECTED_SCHEMA_HEAD]:
                    raise DatabaseError(
                        "The database schema revision does not match this build.",
                        context={
                            "reason": "schema_revision_mismatch",
                            "expected": EXPECTED_SCHEMA_HEAD,
                            "found": revisions,
                        },
                    )
                revision_status = SchemaRevisionStatus.VERIFIED
    except DatabaseError:
        raise
    except CONNECTIVITY_ERRORS as exc:
        raise DatabaseError(
            "PostgreSQL is not reachable.",
            context={"reason": "postgres_unreachable", "error_type": type(exc).__name__},
        ) from exc

    return DatabaseBaselineReport(
        server_version_num=server_version_num,
        runtime_role=role.rolname,
        schema_revision_status=revision_status,
    )
