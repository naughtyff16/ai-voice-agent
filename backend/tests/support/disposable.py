"""Guards that every destructive test operation must pass.

"Not production" is not enough: a target must be positively identified as
disposable before anything is created, altered or dropped on it.
"""

from __future__ import annotations

import re
from typing import Final

from voice_agent.platform.config.base_settings import TEST_DATABASE_NAME_PREFIX

LOOPBACK_HOSTS: Final = frozenset({"127.0.0.1", "::1", "localhost"})
# An externally provided cluster is only used if it contains this database,
# which only a disposable test stack creates (infra/docker-compose/docker-compose.test.yml).
DISPOSABLE_CLUSTER_MARKER_DATABASE: Final = "voice_agent_test_disposable_cluster"
_HARNESS_DATABASE: Final = re.compile(rf"^{TEST_DATABASE_NAME_PREFIX}[a-z0-9_]{{8,40}}$")


class UnsafeTestTargetError(RuntimeError):
    """A destructive test operation was pointed at a target not proven disposable."""


def require_loopback(host: str | None) -> str:
    if host not in LOOPBACK_HOSTS:
        raise UnsafeTestTargetError(f"refusing a non-loopback test host: {host!r}")
    return host


def require_disposable_database_name(name: str) -> str:
    if name == DISPOSABLE_CLUSTER_MARKER_DATABASE or not _HARNESS_DATABASE.fullmatch(name):
        raise UnsafeTestTargetError(f"refusing to create or drop non-test database {name!r}")
    return name
