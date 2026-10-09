"""Per-request context carried in a ``ContextVar``.

A ``ContextVar`` is isolated per asyncio task, so concurrent requests never see
each other's context and there is no mutable global request state (3A §11.1).

Only the correlation/request ID exists today. Later phases extend
``RequestContext`` with the authenticated principal, tenant organization,
region and audit fields; because the object is immutable, each pipeline stage
binds a new value rather than mutating a shared one.
"""

from __future__ import annotations

from contextvars import ContextVar, Token
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RequestContext:
    request_id: str


_current_request_context: ContextVar[RequestContext | None] = ContextVar(
    "current_request_context", default=None
)


def bind_request_context(context: RequestContext) -> Token[RequestContext | None]:
    return _current_request_context.set(context)


def reset_request_context(token: Token[RequestContext | None]) -> None:
    _current_request_context.reset(token)


def current_request_context() -> RequestContext | None:
    return _current_request_context.get()
