"""The API error codes this build may emit, and their contract.

Every error response is built from this catalog, so the code, the permitted
HTTP status and ``retryable`` always come from one place. Each entry records
its authority:

* ``API-ERROR-CATALOG`` — the frozen Phase-6 catalog
  (docs/phase-06-api-design/API-ERROR-CATALOG.md §3);
* ``OD-D0-02`` — CONTROLLED API ERRATUM approved by the owner during D0 and
  pending formal reconciliation into the frozen catalog. The frozen catalog
  has no entry for a request using an unsupported method; rather than mislabel
  it ``VALIDATION_ERROR``, D0 emits ``METHOD_NOT_ALLOWED`` (405, not retryable)
  in the standard envelope with the ``Allow`` header preserved.

A test cross-checks every ``API-ERROR-CATALOG`` entry against the frozen document.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from types import MappingProxyType
from typing import Final, Literal

FROZEN_CATALOG: Final = "API-ERROR-CATALOG"
ERRATUM_OD_D0_02: Final = "OD-D0-02"


class ApiErrorCode(StrEnum):
    VALIDATION_ERROR = "VALIDATION_ERROR"
    RESOURCE_NOT_FOUND = "RESOURCE_NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    DEPENDENCY_UNAVAILABLE = "DEPENDENCY_UNAVAILABLE"


@dataclass(frozen=True, slots=True)
class ErrorContract:
    # The statuses this build may pair with the code; the first is the default.
    statuses: tuple[int, ...]
    retryable: bool
    message: str
    authority: Literal["API-ERROR-CATALOG", "OD-D0-02"]

    @property
    def default_status(self) -> int:
        return self.statuses[0]


ERROR_CATALOG: Final[Mapping[ApiErrorCode, ErrorContract]] = MappingProxyType(
    {
        # 400 for an unparseable body, 422 for a well-formed but invalid one (6A §7.4).
        ApiErrorCode.VALIDATION_ERROR: ErrorContract(
            statuses=(422, 400),
            retryable=False,
            message="The request is invalid.",
            authority=FROZEN_CATALOG,
        ),
        ApiErrorCode.RESOURCE_NOT_FOUND: ErrorContract(
            statuses=(404,),
            retryable=False,
            message="The requested resource could not be found.",
            authority=FROZEN_CATALOG,
        ),
        ApiErrorCode.METHOD_NOT_ALLOWED: ErrorContract(
            statuses=(405,),
            retryable=False,
            message="The request method is not supported for this resource.",
            authority=ERRATUM_OD_D0_02,
        ),
        ApiErrorCode.INTERNAL_ERROR: ErrorContract(
            statuses=(500,),
            retryable=False,
            message="An unexpected error occurred.",
            authority=FROZEN_CATALOG,
        ),
        # The catalog also allows 502 on one Phase-6F route; no D0 path emits it.
        ApiErrorCode.DEPENDENCY_UNAVAILABLE: ErrorContract(
            statuses=(503,),
            retryable=True,
            message="A required dependency is temporarily unavailable.",
            authority=FROZEN_CATALOG,
        ),
    }
)


def contract_for(code: ApiErrorCode, status_code: int | None = None) -> tuple[int, ErrorContract]:
    """The status to send and the contract for ``code``; refuses an uncataloged pairing."""
    contract = ERROR_CATALOG[code]
    status = contract.default_status if status_code is None else status_code
    if status not in contract.statuses:
        raise ValueError(f"{code} is not cataloged with HTTP status {status}")
    return status, contract
