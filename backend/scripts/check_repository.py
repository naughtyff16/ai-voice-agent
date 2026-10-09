"""Repository guards run by CI and by ``scripts/verify.py``.

1. The frozen architecture under ``docs/`` has no uncommitted change.
2. No committed or pending file outside ``docs/`` contains a credential.

The frozen migration package itself is verified by ``db_migrate.py graph``.
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Final

REPOSITORY_ROOT: Final = Path(__file__).resolve().parents[2]
FROZEN_PATH: Final = "docs"

# Only an example/template environment file may be versioned.
_FORBIDDEN_FILE_NAMES: Final = re.compile(r"(^|/)\.env(\.[^/]*)?$")
_ALLOWED_ENV_TEMPLATES: Final = re.compile(r"(^|/)\.env(\.[a-z]+)?\.example$")

_PRIVATE_KEY: Final = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")
_TOKEN_PATTERNS: Final = (
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),  # AWS access key id
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),  # GitHub token
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"),  # Slack token
    re.compile(r"\bsk-[A-Za-z0-9_-]{32,}\b"),  # provider API secret key
)
# scheme://user:password@ — the password group is checked against placeholders.
_URL_PASSWORD: Final = re.compile(
    r"[a-z][a-z0-9+.\-]*://[^\s/:@'\"]*:([^\s@/'\"]+)@", re.IGNORECASE
)
# Interpolations ({x}, ${X}, <x>) and obviously fake literals used in tests and docs.
_PLACEHOLDER: Final = re.compile(
    r"^(\{[^}]*\}|\$\{[^}]*\}|<[^>]*>|\*+|p|pw|password|change-me[a-z0-9-]*|wrong-.*)$",
    re.IGNORECASE,
)
_SCANNED_SUFFIXES: Final = frozenset(
    {
        "",
        ".cfg",
        ".dockerfile",
        ".example",
        ".ini",
        ".json",
        ".lock",
        ".md",
        ".py",
        ".sh",
        ".toml",
        ".txt",
        ".yaml",
        ".yml",
    }
)


def find_secrets(path: str, text: str) -> list[str]:
    findings: list[str] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if _PRIVATE_KEY.search(line):
            findings.append(f"{path}:{number}: private key material")
        findings.extend(
            f"{path}:{number}: token-like secret"
            for pattern in _TOKEN_PATTERNS
            if pattern.search(line)
        )
        for match in _URL_PASSWORD.finditer(line):
            if not _PLACEHOLDER.match(match.group(1)):
                findings.append(f"{path}:{number}: URL with an embedded password")
    return findings


def forbidden_files(paths: Iterable[str]) -> list[str]:
    return [
        f"{path}: environment files must not be committed"
        for path in paths
        if _FORBIDDEN_FILE_NAMES.search(path) and not _ALLOWED_ENV_TEMPLATES.search(path)
    ]


def _git(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise SystemExit(f"error: git {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout


def check_frozen_documents() -> list[str]:
    changed = _git("status", "--porcelain", "--untracked-files=all", "--", FROZEN_PATH).splitlines()
    return [f"frozen document changed: {line.strip()}" for line in changed]


def check_secrets() -> list[str]:
    tracked_and_pending = _git(
        "ls-files", "--cached", "--others", "--exclude-standard"
    ).splitlines()
    candidates = [path for path in tracked_and_pending if not path.startswith(f"{FROZEN_PATH}/")]
    problems = forbidden_files(candidates)
    for relative in candidates:
        path = REPOSITORY_ROOT / relative
        if path.suffix.lower() not in _SCANNED_SUFFIXES or not path.is_file():
            continue
        problems.extend(find_secrets(relative, path.read_text(encoding="utf-8", errors="replace")))
    return problems


def main(argv: Sequence[str] | None = None) -> int:
    del argv
    problems = check_frozen_documents() + check_secrets()
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if problems:
        return 1
    print("result: OK: frozen documents unchanged, no committed secrets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
