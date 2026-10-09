"""Infrastructure-layer errors (3A §12.1)."""

from __future__ import annotations

from voice_agent.platform.shared_kernel.errors.base import PlatformError


class InfrastructureError(PlatformError):
    """A dependency the platform runs on failed or is unusable."""

    code = "infrastructure_error"


class DatabaseError(InfrastructureError):
    """PostgreSQL is unreachable or does not satisfy the required baseline."""

    code = "database_error"


class CacheError(InfrastructureError):
    """Redis is unreachable or does not satisfy the required baseline."""

    code = "cache_error"
