"""Static validation of the frozen migration package.

Reads the Alembic revision wrappers and SQL files on disk without importing or
executing them and without a database. Used by the operator CLI
(``scripts/db_migrate.py graph``), by CI and by the test suite to prove that
the package the application expects is exactly the frozen one.
"""

from __future__ import annotations

import ast
import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from voice_agent.platform.infrastructure.db.schema_baseline import (
    EXPECTED_REVISION_COUNT,
    EXPECTED_SCHEMA_HEAD,
    EXPECTED_SCHEMA_ROOT,
    FROZEN_MIGRATION_PACKAGE_SHA256,
)
from voice_agent.platform.shared_kernel.errors import PlatformError

_ORDINAL: Final = re.compile(r"^(\d{3})_")
_GENERATED_DIRECTORY: Final = "__pycache__"


class MigrationGraphError(PlatformError):
    """The migration package on disk is not the expected frozen baseline."""

    code = "migration_graph_invalid"


@dataclass(frozen=True, slots=True)
class Revision:
    revision: str
    down_revision: str | None
    sql_file: str | None


@dataclass(frozen=True, slots=True)
class MigrationGraphReport:
    revision_count: int
    sql_file_count: int
    roots: tuple[str, ...]
    heads: tuple[str, ...]
    # Revision ids from root to head; empty when the graph is not a single chain.
    chain: tuple[str, ...]
    package_sha256: str
    # Structural defects found while reading the package.
    defects: tuple[str, ...]


def _module_constants(path: Path) -> dict[str, object]:
    constants: dict[str, object] = {}
    for node in ast.parse(path.read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target, value = node.targets[0], node.value
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            target, value = node.target, node.value
        else:
            continue
        if isinstance(target, ast.Name) and target.id in {"revision", "down_revision", "SQL_FILE"}:
            constants[target.id] = ast.literal_eval(value)
    return constants


def read_revisions(versions_dir: Path) -> tuple[list[Revision], list[str]]:
    revisions: list[Revision] = []
    defects: list[str] = []
    for path in sorted(versions_dir.glob("*.py")):
        constants = _module_constants(path)
        revision = constants.get("revision")
        down_revision = constants.get("down_revision")
        sql_file = constants.get("SQL_FILE")
        if not isinstance(revision, str):
            defects.append(f"{path.name}: no string 'revision' identifier")
            continue
        if revision != path.stem:
            defects.append(f"{path.name}: revision id {revision!r} does not match the file name")
        if down_revision is not None and not isinstance(down_revision, str):
            # A tuple here is an Alembic merge point, i.e. a branched history.
            defects.append(f"{path.name}: down_revision is not a single revision")
            continue
        revisions.append(
            Revision(
                revision=revision,
                down_revision=down_revision,
                sql_file=sql_file if isinstance(sql_file, str) else None,
            )
        )
    return revisions, defects


def _walk_chain(revisions: list[Revision], roots: list[str]) -> tuple[str, ...]:
    children: dict[str, list[str]] = {}
    for item in revisions:
        if item.down_revision is not None:
            children.setdefault(item.down_revision, []).append(item.revision)
    if len(roots) != 1 or any(len(found) > 1 for found in children.values()):
        return ()
    chain = [roots[0]]
    while chain[-1] in children:
        chain.append(children[chain[-1]][0])
    return tuple(chain) if len(chain) == len(revisions) else ()


def compute_package_digest(package_dir: Path) -> str:
    """SHA-256 over every file of the migration package, by relative path and content.

    Line endings are normalized to LF first so the digest is identical on a
    checkout that converts text files to CRLF.
    """
    files = {
        path.relative_to(package_dir).as_posix(): path
        for directory in ("alembic", "migrations")
        for path in (package_dir / directory).rglob("*")
        if path.is_file() and _GENERATED_DIRECTORY not in path.parts
    }
    digest = hashlib.sha256()
    # Sorted by the POSIX path string, byte-wise: Path ordering is case-insensitive
    # on Windows and case-sensitive elsewhere, which would make the digest OS-dependent.
    for relative_path in sorted(files):
        content = files[relative_path].read_bytes().replace(b"\r\n", b"\n")
        digest.update(relative_path.encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(content).hexdigest().encode())
        digest.update(b"\n")
    return digest.hexdigest()


def inspect_migration_package(package_dir: Path) -> MigrationGraphReport:
    """Describe the package at ``package_dir`` (the directory holding alembic/ and migrations/)."""
    versions_dir = package_dir / "alembic" / "versions"
    migrations_dir = package_dir / "migrations"
    if not versions_dir.is_dir() or not migrations_dir.is_dir():
        raise MigrationGraphError(
            "Migration package not found.", context={"package_dir": str(package_dir)}
        )

    revisions, defects = read_revisions(versions_dir)
    revision_ids = [item.revision for item in revisions]
    known = set(revision_ids)
    sql_files = sorted(path.name for path in migrations_dir.glob("*.sql"))

    for duplicate in sorted({rid for rid in revision_ids if revision_ids.count(rid) > 1}):
        defects.append(f"revision id {duplicate!r} is defined more than once")
    for item in revisions:
        if item.down_revision is not None and item.down_revision not in known:
            defects.append(f"{item.revision}: down_revision {item.down_revision!r} does not exist")
        if item.sql_file != f"{item.revision}.sql":
            defects.append(f"{item.revision}: does not wrap {item.revision}.sql")
    for missing in sorted({f"{rid}.sql" for rid in known} - set(sql_files)):
        defects.append(f"{missing}: SQL file is missing")
    for orphan in sorted(set(sql_files) - {f"{rid}.sql" for rid in known}):
        defects.append(f"{orphan}: SQL file has no Alembic revision")

    referenced = {item.down_revision for item in revisions if item.down_revision is not None}
    roots = sorted(item.revision for item in revisions if item.down_revision is None)
    heads = sorted(known - referenced)
    chain = _walk_chain(revisions, roots)
    if not chain:
        defects.append("revisions do not form a single linear chain")
    else:
        ordinals = [int(match.group(1)) if (match := _ORDINAL.match(rid)) else -1 for rid in chain]
        if ordinals != list(range(1, len(chain) + 1)):
            defects.append(
                "revision ordinals are not the contiguous sequence 001..N in chain order"
            )

    return MigrationGraphReport(
        revision_count=len(revisions),
        sql_file_count=len(sql_files),
        roots=tuple(roots),
        heads=tuple(heads),
        chain=chain,
        package_sha256=compute_package_digest(package_dir),
        defects=tuple(defects),
    )


def find_baseline_violations(report: MigrationGraphReport) -> list[str]:
    """Compare a report with the frozen baseline; an empty list means it matches exactly."""
    violations = list(report.defects)
    if report.revision_count != EXPECTED_REVISION_COUNT:
        violations.append(
            f"expected {EXPECTED_REVISION_COUNT} Alembic revisions, found {report.revision_count}"
        )
    if report.sql_file_count != EXPECTED_REVISION_COUNT:
        violations.append(
            f"expected {EXPECTED_REVISION_COUNT} SQL migrations, found {report.sql_file_count}"
        )
    if report.roots != (EXPECTED_SCHEMA_ROOT,):
        violations.append(f"expected sole root {EXPECTED_SCHEMA_ROOT}, found {list(report.roots)}")
    if report.heads != (EXPECTED_SCHEMA_HEAD,):
        violations.append(f"expected sole head {EXPECTED_SCHEMA_HEAD}, found {list(report.heads)}")
    if report.package_sha256 != FROZEN_MIGRATION_PACKAGE_SHA256:
        violations.append(
            "migration package content differs from the frozen baseline "
            f"(sha256 {report.package_sha256})"
        )
    return violations


def validate_frozen_baseline(package_dir: Path) -> MigrationGraphReport:
    """Return the report if the package is exactly the frozen baseline, else raise."""
    report = inspect_migration_package(package_dir)
    violations = find_baseline_violations(report)
    if violations:
        raise MigrationGraphError(
            "Migration package does not match the frozen baseline: " + "; ".join(violations),
            context={"violations": violations},
        )
    return report
