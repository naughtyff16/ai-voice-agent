"""Aggregate verification: the single command CI and developers run.

Runs every gate even after a failure, prints a summary, and exits non-zero if
any gate failed. Usage (from backend/)::

    uv run python scripts/verify.py
"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path
from typing import Final

BACKEND_DIR: Final = Path(__file__).resolve().parents[1]
PYTHON: Final = sys.executable

GATES: Final[tuple[tuple[str, list[str]], ...]] = (
    ("format-check", [PYTHON, "-m", "ruff", "format", "--check", "."]),
    ("lint", [PYTHON, "-m", "ruff", "check", "."]),
    ("type-check", [PYTHON, "-m", "mypy"]),
    ("migration-graph", [PYTHON, "scripts/db_migrate.py", "graph"]),
    ("repository-guards", [PYTHON, "scripts/check_repository.py"]),
    ("unit-tests", [PYTHON, "-m", "pytest", "-m", "unit", "-q"]),
    ("integration-and-smoke-tests", [PYTHON, "-m", "pytest", "-m", "integration or smoke", "-q"]),
)


def main() -> int:
    results: list[tuple[str, int, float]] = []
    for name, command in GATES:
        shown = " ".join("python" if part == PYTHON else part for part in command)
        print(f"\n=== {name}: {shown}")
        sys.stdout.flush()
        started = time.monotonic()
        returncode = subprocess.run(command, cwd=BACKEND_DIR, check=False).returncode
        results.append((name, returncode, time.monotonic() - started))

    print("\n=== summary")
    for name, returncode, seconds in results:
        print(f"{'PASS' if returncode == 0 else 'FAIL':4}  {name:30} {seconds:7.1f}s")
    failed = [name for name, returncode, _ in results if returncode != 0]
    if failed:
        print(f"\nverification FAILED: {', '.join(failed)}")
        return 1
    print("\nverification PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
