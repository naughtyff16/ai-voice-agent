"""CORS that honours the API error and correlation contract (6A §22, §24).

Starlette's ``CORSMiddleware`` answers a rejected preflight itself, with a
``text/plain`` body such as ``Disallowed CORS origin`` and no error envelope.
``ApiCorsMiddleware`` keeps Starlette's policy evaluation and every CORS header
it computes, and replaces only the body of a rejection with the governed
``VALIDATION_ERROR`` (400) envelope.

It must be installed *inside* ``CorrelationIdMiddleware`` (see ``main.py``): the
request ID then exists when the envelope is built and is added to every
preflight response, accepted or rejected.
"""

from __future__ import annotations

from typing import Final

from starlette.datastructures import Headers
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import Response

from voice_agent.apps.api.error_catalog import ApiErrorCode
from voice_agent.apps.api.middleware.error_handler import error_response
from voice_agent.platform.infrastructure.observability.logging import get_logger

logger = get_logger(__name__)

# The body headers of Starlette's plain-text rejection; everything else it set
# (Vary, Access-Control-*) is CORS policy output and is preserved.
_BODY_HEADERS: Final = frozenset({"content-type", "content-length"})
_REJECTION_PREFIX: Final = "Disallowed CORS "
_KNOWN_REJECTIONS: Final = frozenset({"origin", "method", "headers", "private-network"})


class ApiCorsMiddleware(CORSMiddleware):
    def preflight_response(self, request_headers: Headers) -> Response:
        decision = super().preflight_response(request_headers)
        if decision.status_code < 400:
            return decision
        # Which dimensions failed goes to the log only, from a fixed vocabulary;
        # the client gets the stable catalog message.
        reasons = bytes(decision.body).decode("ascii", "replace").removeprefix(_REJECTION_PREFIX)
        logger.info(
            "cors_preflight_rejected",
            rejected=sorted(_KNOWN_REJECTIONS.intersection(reasons.split(", "))),
        )
        response = error_response(ApiErrorCode.VALIDATION_ERROR, status_code=400)
        for name, value in decision.headers.items():
            if name.lower() not in _BODY_HEADERS:
                response.headers[name] = value
        return response
