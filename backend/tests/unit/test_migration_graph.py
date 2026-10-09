"""The frozen migration package and the validator that guards it.

The baseline tests read the real package in docs/. The mutation tests apply one
defect each to a private copy of it, never to the original.
"""

from __future__ import annotations

import shutil
from collections.abc import Callable
from pathlib import Path

import pytest

from voice_agent.platform.infrastructure.db.migration_graph import (
    MigrationGraphError,
    compute_package_digest,
    find_baseline_violations,
    inspect_migration_package,
    validate_frozen_baseline,
)
from voice_agent.platform.infrastructure.db.schema_baseline import (
    EXPECTED_REVISION_COUNT,
    EXPECTED_SCHEMA_HEAD,
    EXPECTED_SCHEMA_ROOT,
    FROZEN_MIGRATION_PACKAGE_SHA256,
)

pytestmark = pytest.mark.unit

FROZEN_PACKAGE = Path(__file__).resolve().parents[3] / "docs" / "phase-05-database-design" / "5K"


@pytest.fixture
def package_copy(tmp_path: Path) -> Path:
    target = tmp_path / "5K"
    for directory in ("alembic", "migrations"):
        shutil.copytree(
            FROZEN_PACKAGE / directory,
            target / directory,
            ignore=shutil.ignore_patterns("__pycache__"),
        )
    return target


def _versions(package: Path) -> Path:
    return package / "alembic" / "versions"


def _replace(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text
    path.write_text(text.replace(old, new), encoding="utf-8")


def test_frozen_package_is_exactly_the_expected_baseline() -> None:
    report = validate_frozen_baseline(FROZEN_PACKAGE)
    assert report.revision_count == EXPECTED_REVISION_COUNT == 112
    assert report.sql_file_count == 112
    assert report.roots == (EXPECTED_SCHEMA_ROOT,) == ("001_5B",)
    assert report.heads == (EXPECTED_SCHEMA_HEAD,) == ("112_5H5",)
    assert report.chain[0] == "001_5B" and report.chain[-1] == "112_5H5"
    assert len(report.chain) == 112
    assert report.defects == ()
    assert report.package_sha256 == FROZEN_MIGRATION_PACKAGE_SHA256


def test_no_migration_113_exists() -> None:
    assert not list((FROZEN_PACKAGE / "migrations").glob("113*"))
    assert not list((FROZEN_PACKAGE / "alembic" / "versions").glob("113*"))


def test_unmodified_copy_passes(package_copy: Path) -> None:
    validate_frozen_baseline(package_copy)


def test_digest_ignores_line_ending_conversion(package_copy: Path) -> None:
    sql_file = package_copy / "migrations" / "001_5B.sql"
    content = sql_file.read_bytes().replace(b"\r\n", b"\n")
    sql_file.write_bytes(content.replace(b"\n", b"\r\n"))
    assert compute_package_digest(package_copy) == FROZEN_MIGRATION_PACKAGE_SHA256


def _add_revision_113(package: Path) -> None:
    (package / "migrations" / "113_5X.sql").write_text("SELECT 1;\n", encoding="utf-8")
    (_versions(package) / "113_5X.py").write_text(
        "revision = '113_5X'\ndown_revision = '112_5H5'\nSQL_FILE = '113_5X.sql'\n",
        encoding="utf-8",
    )


def _add_second_head(package: Path) -> None:
    (package / "migrations" / "113_5X.sql").write_text("SELECT 1;\n", encoding="utf-8")
    (_versions(package) / "113_5X.py").write_text(
        "revision = '113_5X'\ndown_revision = '111_5H4'\nSQL_FILE = '113_5X.sql'\n",
        encoding="utf-8",
    )


def _break_link(package: Path) -> None:
    _replace(
        _versions(package) / "050_5H.py",
        "down_revision: Union[str, None] = '049_5H'",
        "down_revision: Union[str, None] = '049_XX'",
    )


def _wrong_head(package: Path) -> None:
    (_versions(package) / "112_5H5.py").unlink()
    (package / "migrations" / "112_5H5.sql").unlink()


def _orphan_sql(package: Path) -> None:
    (package / "migrations" / "113_5X.sql").write_text("SELECT 1;\n", encoding="utf-8")


def _edit_frozen_sql(package: Path) -> None:
    sql_file = package / "migrations" / "042_5G.sql"
    sql_file.write_bytes(sql_file.read_bytes() + b"\n-- tampered\n")


def _rewire_wrapper(package: Path) -> None:
    _replace(_versions(package) / "010_5C.py", "SQL_FILE = '010_5C.sql'", "SQL_FILE = '011_5C.sql'")


def _merge_point(package: Path) -> None:
    _replace(
        _versions(package) / "112_5H5.py",
        "down_revision: Union[str, None] = '111_5H4'",
        "down_revision: Union[str, None] = ('110_5C2', '111_5H4')",
    )


@pytest.mark.parametrize(
    ("mutate", "expected"),
    [
        (_add_revision_113, "expected sole head 112_5H5"),
        (_add_second_head, "expected sole head 112_5H5"),
        (_break_link, "does not exist"),
        (_wrong_head, "expected 112 Alembic revisions"),
        (_orphan_sql, "has no Alembic revision"),
        (_edit_frozen_sql, "differs from the frozen baseline"),
        (_rewire_wrapper, "does not wrap 010_5C.sql"),
        (_merge_point, "not a single revision"),
    ],
    ids=lambda value: getattr(value, "__name__", str(value)),
)
def test_mutated_package_is_rejected(
    package_copy: Path, mutate: Callable[[Path], None], expected: str
) -> None:
    mutate(package_copy)
    violations = find_baseline_violations(inspect_migration_package(package_copy))
    assert any(expected in violation for violation in violations), violations
    with pytest.raises(MigrationGraphError):
        validate_frozen_baseline(package_copy)


def test_two_heads_are_reported_as_such(package_copy: Path) -> None:
    _add_second_head(package_copy)
    report = inspect_migration_package(package_copy)
    assert report.heads == ("112_5H5", "113_5X")
    assert report.chain == ()


def test_missing_package_is_an_error(tmp_path: Path) -> None:
    with pytest.raises(MigrationGraphError, match="not found"):
        inspect_migration_package(tmp_path)
