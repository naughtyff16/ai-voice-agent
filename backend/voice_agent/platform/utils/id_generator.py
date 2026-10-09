"""Time-sortable identifier generation (3A §6.4, 5A §8.1)."""

from __future__ import annotations

import secrets
import time
from uuid import UUID

_RAND_B_BITS = 62
_RAND_B_MASK = (1 << _RAND_B_BITS) - 1


def generate_uuid7() -> UUID:
    """Return an RFC 9562 UUIDv7: 48-bit Unix milliseconds followed by 74 random bits."""
    unix_ms = time.time_ns() // 1_000_000
    random_bits = secrets.randbits(74)
    rand_a = random_bits >> _RAND_B_BITS
    rand_b = random_bits & _RAND_B_MASK
    value = (
        ((unix_ms & 0xFFFF_FFFF_FFFF) << 80) | (0x7 << 76) | (rand_a << 64) | (0b10 << 62) | rand_b
    )
    return UUID(int=value)
