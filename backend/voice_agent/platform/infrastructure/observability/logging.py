"""Structured logging foundation (3A §12.4).

One processor pipeline serves both ``structlog`` loggers and standard-library
loggers (uvicorn, SQLAlchemy, asyncio), so every line the process emits has the
same shape and passes through the same redaction step. Final telemetry
conventions are owned by Phase 7J; this module only establishes the pipeline.

Everything a caller hands to a logger is untrusted, and stays untrusted: no
stage recognises a value as "already sanitised" by its type, by the name of
the field that carries it or by anything else it brings along. One rule
orders the whole path:

    No caller-controlled value reaches an output handler without passing
    through the sanitiser *after its final transformation*.

So everything that joins, formats or assembles a value happens before the
sanitiser, and nothing after it changes a value. The path of one event::

    logging call
      1. operational metadata   level, logger, service, environment and
                                timestamp are established by the pipeline; the
                                request ID is taken from the request context
                                the server set. None of it is read from the
                                fields of the call, and none of it takes part
                                in the field or event budget. It is
                                established again in step 8, for every record
      2. bounded admission      at most MAX_EVENT_FIELDS call, bound and
                                context fields are admitted; a
                                standard-library record is reduced to its
                                standard attributes; a format string must be
                                bounded
      3. reserved names         a field a caller wrote under a name reserved
                                for processor metadata (``_record``,
                                ``_from_structlog``) or for operational
                                metadata is removed: a name gives a value no
                                standing
      4. normalisation          exc_info and stack_info become a traceback and
                                a stack constructed from validated frame
                                metadata, each as one complete text
      5. assembly               fragments a caller put under ``exception`` or
                                ``stack`` (a list of lines, lists in lists)
                                are joined into the text they will be laid
                                out as; standard-library arguments are
                                interpolated into their message
      6. sanitising             redaction.sanitize_event, on the complete
                                values: exact types only, one work and output
                                budget for the whole event; the event name
                                and the traceback are sanitised first, so
                                other fields cannot displace them
      7. log record             the sanitised event is what any handler sees
      8. final pass             for every record, whatever made it: step 1
                                again, from the log record, the configuration
                                and the request context, replacing whatever
                                the event holds under those names; then steps
                                3, 5 and 6 again on the whole event,
                                immediately before layout
      9. bounded rendering      layout into one line; a line above
                                MAX_RENDERED_EVENT_LENGTH is replaced by a
                                fixed record
     10. stream

The only things trusted are fixed text in this package and identifiers that
passed their grammar. The one stage after the final sanitiser lays values out
as a line: it receives nothing but the sanitiser's output, cannot be reached
by a caller without passing it, joins no two values into one and adds only
the syntax of its format.

Where a record came from is not read from the record. A standard-library
record is an event of this pipeline only if its message *is* the object the
pipeline produced last in the same thread (``_PIPELINE_STATE``); the
attributes by which structlog marks its records (``_logger``, ``_name``) can
be attached by any caller through ``extra=`` and are never copied from a
record. And nothing depends on that decision but the shape of the event: the
final pass (step 8) gives a record of either origin the same operational
metadata from the same sources and sanitises all of it, so a record that were
taken for an event of the pipeline would gain no standing by it.

What a handler other than this module's receives (step 7): for an event made
through structlog, the sanitised event. A record made by a standard-library
logger reaches every handler on that logger as its caller made it; only this
module's handler sanitises it. An additional handler must therefore use
``FailClosedStreamHandler`` and the formatter installed here.

The pipeline fails closed at every stage:

* the pipeline is guarded: if any step raises, the event is replaced by a
  fixed ``log_processing_failed`` record instead of propagating an exception
  (whose text may carry the payload) into the caller;
* exceptions and stacks are built by ``redaction.traceback_text`` and
  ``redaction.stack_text``, never by the standard formatter that embeds raw
  exception text, filenames and source lines;
* the sanitiser runs again immediately before rendering, on every value, so
  nothing a processor added escapes it and nothing is exempt from it;
* nothing is copied, interpolated or converted to text before it has been
  admitted and sanitised: call fields, context variables and record attributes
  beyond the limit are never visited, an oversized scalar is measured before
  it is copied or converted, and a format string whose width or precision
  could allocate without bound is replaced by a fixed
  ``log_record_unsafe_format`` record;
* the handler never lets the logging module print a failed record: a format
  failure emits a fixed JSON line, and an emit failure writes a fixed
  diagnostic to stderr. Both carry only fixed text and validated identifiers,
  never the message, arguments or an unvalidated name of the record.
"""

from __future__ import annotations

import contextlib
import contextvars
import datetime as dt
import json
import logging
import sys
import threading
from collections.abc import Mapping, Sequence
from itertools import islice
from types import FrameType
from typing import Any, Final, Self, TextIO

import structlog
from structlog.contextvars import STRUCTLOG_KEY_PREFIX
from structlog.typing import EventDict, Processor, WrappedLogger

from voice_agent.platform.infrastructure.observability.redaction import (
    MAX_EVENT_FIELDS,
    MAX_STRING_LENGTH,
    REDACTED,
    TRUNCATED,
    exception_type_name,
    leading_text,
    sanitize,
    sanitize_event,
    stack_text,
    traceback_text,
    trusted_identifier,
)
from voice_agent.platform.shared_kernel.request_context import current_request_context

__all__ = ["REDACTED", "configure_logging", "get_logger", "redact_sensitive_fields"]

_UVICORN_LOGGERS: Final = ("uvicorn", "uvicorn.error", "uvicorn.access")
# The two keys under which structlog's ProcessorFormatter keeps its own
# metadata in an event. The names mean nothing by themselves: a caller can
# write a field called ``_record`` as easily as any other. Only the formatter
# is believed, at the one point where it has just written them (the final
# ``_EventPipeline``, which is the first thing the formatter calls and takes
# both out of the event); a field of that name from anywhere else is removed.
_PROCESSOR_META_KEYS: Final = ("_record", "_from_structlog")
# The operational metadata of a line, and the fixed word that replaces a value
# that is not well-formed. It is established by the pipeline, never taken from
# the fields of a call, and is no part of the field or event budget: nothing a
# caller sends can displace or replace it.
_IDENTITY_FALLBACKS: Final[Mapping[str, str]] = {
    "timestamp": "unknown",
    "level": "unknown",
    "logger": "untrusted_logger",
    "service": "untrusted_service",
    "environment": "untrusted_environment",
    "request_id": "untrusted_request_id",
}
# Sanitised first and outside the field limit (``redaction.sanitize_event``):
# what the event is called, and the traceback and stack that explain it.
_LEADING_FIELDS: Final = ("event", "exception", "stack")
# Fields laid out as one text. Whatever a caller puts there is assembled into
# that text before it is sanitised; nothing is joined afterwards.
_ASSEMBLED_FIELDS: Final = frozenset(("exception", "stack"))
# Names that are never read as fields of the caller.
_NOT_PAYLOAD: Final = frozenset((*_IDENTITY_FALLBACKS, *_PROCESSOR_META_KEYS))
# Names that do not take one of the MAX_EVENT_FIELDS places.
_UNCOUNTED: Final = frozenset((*_NOT_PAYLOAD, *_LEADING_FIELDS, "exc_info", "stack_info"))
_REQUEST_ID_VARIABLE: Final = STRUCTLOG_KEY_PREFIX + "request_id"
_MISSING: Final = object()
_FIELDS_NOTE: Final = "event field limit reached"
# Says that a caller used a name reserved for processor metadata. Fixed text.
RESERVED: Final = "[RESERVED]"
_RESERVED_NOTE: Final = "reserved field names removed"
# Context variables looked at for one event. Other libraries keep variables in
# the same context, so more are examined than fields can be admitted.
MAX_CONTEXT_VARIABLES: Final = 4 * MAX_EVENT_FIELDS
# Every attribute of a standard-library record that this pipeline reads: what
# ``logging`` itself sets. Anything else on a record (``extra=``) is never
# copied, visited or emitted. That includes ``_logger`` and ``_name``, by which
# structlog's formatter tells its own records: a caller can attach both.
_RECORD_ATTRIBUTES: Final = (
    "name",
    "msg",
    "args",
    "levelname",
    "levelno",
    "pathname",
    "filename",
    "module",
    "exc_info",
    "exc_text",
    "stack_info",
    "lineno",
    "funcName",
    "created",
    "msecs",
    "relativeCreated",
    "thread",
    "threadName",
    "processName",
    "process",
    "taskName",
)
# What makes structlog's formatter read the message of a record as an event.
# Set by the handler on its own copy of a record, never taken from a record.
_EVENT_RECORD_ATTRIBUTES: Final[Mapping[str, object]] = {"_logger": None, "_name": "event"}
# The event the structlog pipeline produced last in this thread. A logging call
# is synchronous from the pipeline to the handlers, so the record a handler is
# given carries that very object as its message, or it was not made by the
# pipeline. Identity cannot be passed in through a logging call.
_PIPELINE_STATE: Final = threading.local()
# Modules whose frames are the logging machinery, not the caller's stack.
_LOGGING_MODULES: Final = ("structlog", "logging", __name__)
_MAX_SKIPPED_FRAMES: Final = 64
# Absolute bound on one rendered line, whatever the renderer. The sanitiser's
# event budget keeps normal output far below it; a line that still exceeds it
# is replaced by a fixed record, never cut and never written.
MAX_RENDERED_EVENT_LENGTH: Final = 131_072
# Standard-library format strings. ``msg % args`` allocates whatever a width or
# precision asks for, before anything can examine the result.
MAX_FORMAT_TEMPLATE_LENGTH: Final = MAX_STRING_LENGTH
MAX_FORMAT_WIDTH: Final = 256
MAX_FORMAT_DIRECTIVES: Final = 64
_FORMAT_FLAGS: Final = "-+ #0"
_DIGITS: Final = "0123456789"


class _UnboundedFormatError(Exception):
    """A standard-library format string that could allocate without bound."""


def _identity(event_dict: Mapping[str, Any]) -> dict[str, object]:
    """The identifiers present in the event, each validated or replaced."""
    found: dict[str, object] = {}
    for key, fallback in _IDENTITY_FALLBACKS.items():
        value = event_dict.get(key, _MISSING)
        if value is not _MISSING:
            found[key] = trusted_identifier(value, key, fallback)
    return found


def _failure_event(identity: Mapping[str, object], event: str, exc: BaseException) -> EventDict:
    """The fixed record that replaces an event the pipeline could not process safely.

    Fixed text, the class name of the error and identifiers that were already
    validated. Nothing of the event that failed is carried over.
    """
    return {"event": event, "error_type": exception_type_name(exc), **identity}


def _sanitized_fields(event_dict: Mapping[str, Any]) -> dict[str, object]:
    """Every field of the caller, sanitised as the complete value that will be emitted."""
    return sanitize_event(
        event_dict, skip=_NOT_PAYLOAD, leading=_LEADING_FIELDS, assembled=_ASSEMBLED_FIELDS
    )


def redact_sensitive_fields(
    _logger: WrappedLogger, _method_name: str, event_dict: EventDict
) -> EventDict:
    """Replace the event with a sanitised copy; on any failure, with a fixed record.

    This is the security boundary, and it is the last stage that changes a
    value: whatever joining or formatting a field needs has been done by the
    time its value is sanitised (``sanitize_event``), and only layout into a
    line follows. No field is exempt and none is passed through as it came:
    the identifiers are accepted by grammar or replaced, the processor
    metadata keys are dropped, and everything else is sanitised.

    The event is not copied first: ``sanitize_event`` admits a bounded number
    of fields straight from it and never visits the rest.
    """
    identity: dict[str, object] = {}
    try:
        identity = _identity(event_dict)
        result = dict(identity)
        for key, value in _sanitized_fields(event_dict).items():
            result.setdefault(key, value)
        return result
    except Exception as exc:  # noqa: BLE001 — the event is replaced, never passed through
        return _failure_event(identity, "log_event_redaction_failed", exc)


def _context_request_id() -> object:
    """The request ID bound through structlog's context variables, found without a scan."""
    registry = getattr(structlog.contextvars, "_CONTEXT_VARS", None)
    variable = registry.get(_REQUEST_ID_VARIABLE) if type(registry) is dict else None
    if isinstance(variable, contextvars.ContextVar):
        value = variable.get(Ellipsis)
        if value is not Ellipsis:
            return value
    return _MISSING


def merge_bounded_contextvars(
    _logger: WrappedLogger, _method_name: str, event_dict: EventDict
) -> EventDict:
    """Merge context-local fields into the event, admitting a bounded number of them.

    ``structlog.contextvars.merge_contextvars`` visits every variable of the
    context and fetches the value of each bound field before any limit exists.
    Here the context is read lazily: at most ``MAX_CONTEXT_VARIABLES``
    variables are looked at, and a value is fetched only for a field that is
    admitted. What lies beyond either limit is never visited; a marker says so.

    A field of the call is never replaced by one of the context, with one
    exception: ``request_id``. A request ID bound to the context identifies
    the work in progress and is not for a single call to rename. It is looked
    up directly, so it is found however many variables the context holds, and
    it takes none of the places the field limit allows.
    """
    bound_request_id = _context_request_id()
    if bound_request_id is not _MISSING:
        event_dict["request_id"] = bound_request_id
    context = contextvars.copy_context()  # constant time: contexts are persistent maps
    room = MAX_EVENT_FIELDS - len(event_dict) + sum(1 for key in _UNCOUNTED if key in event_dict)
    examined = 0
    for variable in context:
        if examined >= MAX_CONTEXT_VARIABLES:
            event_dict.setdefault(TRUNCATED, _FIELDS_NOTE)
            break
        examined += 1
        name = variable.name
        if not name.startswith(STRUCTLOG_KEY_PREFIX):
            continue
        key = name[len(STRUCTLOG_KEY_PREFIX) :]
        if key == "request_id":
            if bound_request_id is _MISSING:
                value = context[variable]
                if value is not Ellipsis:
                    event_dict[key] = value
            continue
        if key in event_dict or key in _IDENTITY_FALLBACKS:
            continue
        value = context[variable]
        if value is Ellipsis:  # structlog's marker for a field that was unbound again
            continue
        if room <= 0 and key not in _UNCOUNTED:
            # One value was fetched to learn that a field really is left out.
            event_dict.setdefault(TRUNCATED, _FIELDS_NOTE)
            break
        event_dict[key] = value
        if key not in _UNCOUNTED:
            room -= 1
    return event_dict


def _calling_frame() -> FrameType | None:
    """The innermost frame that is not part of the logging machinery."""
    frame: FrameType | None = sys._getframe(1)
    for _ in range(_MAX_SKIPPED_FRAMES):
        if frame is None:
            return None
        module = frame.f_globals.get("__name__") if type(frame.f_globals) is dict else None
        if type(module) is not str or not module.startswith(_LOGGING_MODULES):
            return frame
        frame = frame.f_back
    return frame


def render_stack_info(
    _logger: WrappedLogger, _method_name: str, event_dict: EventDict
) -> EventDict:
    """Replace ``stack_info`` with the calling stack, built as a traceback is, under ``stack``.

    Whatever ``stack_info`` held (for a standard-library record, a stack the
    ``logging`` module formatted with raw filenames and source lines) is
    discarded, never emitted.
    """
    if event_dict.pop("stack_info", None):
        event_dict["stack"] = stack_text(_calling_frame())
    return event_dict


def render_exc_info(_logger: WrappedLogger, _method_name: str, event_dict: EventDict) -> EventDict:
    """Replace ``exc_info`` with a constructed traceback under ``exception``.

    The traceback is one complete text in the standard layout. It has no
    special standing afterwards: the sanitiser reads it whole, as it reads a
    text a caller put under the same name.
    """
    exc_info = event_dict.pop("exc_info", None)
    if not exc_info:
        return event_dict
    exc: BaseException | None
    if isinstance(exc_info, BaseException):
        exc = exc_info
    elif isinstance(exc_info, tuple) and len(exc_info) == 3:
        exc = exc_info[1] if isinstance(exc_info[1], BaseException) else None
    else:
        exc = sys.exc_info()[1]
    if exc is not None:
        event_dict["exception"] = traceback_text(exc)
    return event_dict


class _EventPipeline:
    """The path of one event: before the log record, and again before layout.

    The order is the security design (module docstring): operational metadata
    is established, the fields of the caller are admitted in bounded number,
    names reserved for processor metadata are taken out of them, tracebacks
    are constructed, and only then is everything sanitised, once, as the
    complete values that will be emitted. Nothing is added afterwards.

    Two instances exist. One receives the events of structlog loggers, in
    which every key was written by a caller, and produces the event the log
    record carries. The other (``final``) is the first thing structlog's
    formatter calls for every record this module's handler formats: the
    formatter has just written ``_record`` (its copy of the record being
    formatted) and ``_from_structlog`` into the event. Which of the two
    applies is decided by where an instance is installed, never by what an
    event contains.

    The final instance establishes the operational metadata of every line it
    lets through, from the log record, the configuration and the request
    context: the level and logger of the logging call that made the record,
    the time the record was created, the service and environment this process
    was configured with, the request ID the server assigned. What an event
    holds under those names is not read (outside a request, a request ID
    that has passed the first instance or the context merge is kept). A
    record that did not come from the first instance is taken through the
    whole path here. Either is then sanitised once more, as a whole, by
    ``redact_sensitive_fields``.

    If any step raises, the event is replaced by a fixed record.
    """

    def __init__(self, *, service: str, environment: str, final: bool) -> None:
        self._service = service
        self._environment = environment
        self._final = final
        self._stamp = structlog.processors.TimeStamper(fmt="iso", utc=True, key="timestamp")

    def __call__(self, logger: WrappedLogger, method_name: str, event_dict: EventDict) -> EventDict:
        identity: dict[str, object] = {}
        try:
            if self._final:
                result = self._finish(logger, method_name, event_dict, identity)
            else:
                self._establish_identity(identity, logger, method_name)
                result = self._process(logger, method_name, event_dict, identity)
        except Exception as exc:  # noqa: BLE001 — the event is replaced, never passed through
            result = _failure_event(identity, "log_processing_failed", exc)
        if not self._final:
            _PIPELINE_STATE.event = result
        return result

    def _establish_identity(
        self, identity: dict[str, object], logger: WrappedLogger, method_name: str
    ) -> None:
        """Level, logger, service, environment and time of a structlog call."""
        level = structlog.stdlib.add_log_level(logger, method_name, {})["level"]
        identity["level"] = trusted_identifier(level, "level", _IDENTITY_FALLBACKS["level"])
        name = getattr(logger, "name", None)
        identity["logger"] = trusted_identifier(name, "logger", _IDENTITY_FALLBACKS["logger"])
        identity["service"] = self._service
        identity["environment"] = self._environment
        timestamp = self._stamp(logger, method_name, {})["timestamp"]
        identity["timestamp"] = trusted_identifier(
            timestamp, "timestamp", _IDENTITY_FALLBACKS["timestamp"]
        )

    def _establish_record_identity(self, identity: dict[str, object], record: object) -> None:
        """Level, logger, service, environment and time, from the log record itself."""
        identity["logger"], identity["level"] = _record_identity(record)
        identity["service"] = self._service
        identity["environment"] = self._environment
        identity["timestamp"] = _record_timestamp(record)

    @staticmethod
    def _establish_request_id(identity: dict[str, object], event_dict: EventDict) -> None:
        """The request ID the server assigned; outside a request, the one of the event.

        The request ID the server assigned outranks one bound to the context,
        which outranks a field of the call (merge_bounded_contextvars).
        """
        request_context = current_request_context()
        request_id = (
            request_context.request_id
            if request_context is not None
            else event_dict.get("request_id", _MISSING)
        )
        if request_id is not _MISSING:
            identity["request_id"] = trusted_identifier(
                request_id, "request_id", _IDENTITY_FALLBACKS["request_id"]
            )

    @staticmethod
    def _assemble(event_dict: EventDict, identity: dict[str, object]) -> EventDict:
        """The established metadata and, sanitised, every other field of the event."""
        try:
            fields = _sanitized_fields(event_dict)
        except Exception as exc:  # noqa: BLE001 — the event is replaced, never passed through
            return _failure_event(identity, "log_event_redaction_failed", exc)
        result: EventDict = {key: identity[key] for key in _IDENTITY_FALLBACKS if key in identity}
        for key, value in fields.items():
            result.setdefault(key, value)
        return result

    def _process(
        self,
        logger: WrappedLogger,
        method_name: str,
        event_dict: EventDict,
        identity: dict[str, object],
    ) -> EventDict:
        merge_bounded_contextvars(logger, method_name, event_dict)
        # Whatever is under these names now was written by a caller: directly,
        # through a bound logger or through the context.
        reserved = False
        for key in _PROCESSOR_META_KEYS:
            reserved = event_dict.pop(key, _MISSING) is not _MISSING or reserved
        self._establish_request_id(identity, event_dict)
        render_stack_info(logger, method_name, event_dict)
        render_exc_info(logger, method_name, event_dict)
        result = self._assemble(event_dict, identity)
        if reserved:
            result[RESERVED] = _RESERVED_NOTE
        return result

    def _finish(
        self,
        logger: WrappedLogger,
        method_name: str,
        event_dict: EventDict,
        identity: dict[str, object],
    ) -> EventDict:
        # The formatter has just written these two; nothing else is believed.
        record = event_dict.pop("_record", None)
        processed = event_dict.pop("_from_structlog", None) is True
        self._establish_record_identity(identity, record)
        # Known before anything of the event is read, so that the fixed record
        # of a failure below belongs to its request as well.
        self._establish_request_id(identity, {})
        if not processed:
            event_dict = self._process(logger, method_name, event_dict, identity)
        self._establish_request_id(identity, event_dict)
        # What the event holds under the names of operational metadata is
        # left behind: the metadata established here stands in its place.
        result: EventDict = {key: identity[key] for key in _IDENTITY_FALLBACKS if key in identity}
        for key, value in event_dict.items():
            result.setdefault(key, value)
        return result


def _admitted(values: dict[str, Any], room: int) -> dict[str, Any]:
    """``values`` itself if it fits, else its first ``room`` fields and a marker.

    The names that are no fields of the caller (``exc_info``, the event name,
    operational metadata) are looked up by name and take none of the places:
    the instruction to log a traceback is not cut off by the fields before it.
    """
    if len(values) <= room:
        return values
    apart = {key: values[key] for key in _UNCOUNTED if key in values}
    fields = (item for item in values.items() if item[0] not in _UNCOUNTED)
    admitted = dict(islice(fields, max(0, room)))
    if len(admitted) + len(apart) < len(values):
        admitted[TRUNCATED] = _FIELDS_NOTE
    admitted.update(apart)
    return admitted


class BoundedBoundLogger(structlog.stdlib.BoundLogger):
    """A bound logger that admits at most ``MAX_EVENT_FIELDS`` fields per call.

    structlog copies the bound context and the keyword arguments of every call
    into a new event dict before the first processor runs. Admission therefore
    happens here: what exceeds the limit is dropped before that copy, so no
    stage of the pipeline ever holds or visits it.
    """

    def bind(self, **new_values: Any) -> Self:
        return super().bind(**_admitted(new_values, MAX_EVENT_FIELDS - len(self._context)))

    def new(self, **new_values: Any) -> Self:
        return super().new(**_admitted(new_values, MAX_EVENT_FIELDS))

    def _process_event(
        self, method_name: str, event: str | None, event_kw: dict[str, Any]
    ) -> tuple[Sequence[Any], Mapping[str, Any]]:
        return super()._process_event(method_name, event, _admitted(event_kw, MAX_EVENT_FIELDS))


def _unserializable(_value: object) -> str:
    # Unreachable after sanitisation; present so json.dumps can never call repr().
    return "[UNSUPPORTED]"


def _record_identity(record: object) -> tuple[str, str]:
    """The validated logger name and level of a record."""
    name = getattr(record, "name", None)
    level = getattr(record, "levelname", None)
    return (
        trusted_identifier(name, "logger", _IDENTITY_FALLBACKS["logger"]),
        trusted_identifier(level.lower() if type(level) is str else None, "level", "unknown"),
    )


def _record_timestamp(record: object) -> str:
    """The time a record was created, as the pipeline writes a time; never raises."""
    created = getattr(record, "created", None)
    timestamp: object = None
    if type(created) is float:
        with contextlib.suppress(Exception):
            timestamp = (
                dt.datetime.fromtimestamp(created, tz=dt.UTC).isoformat().replace("+00:00", "Z")
            )
    return trusted_identifier(timestamp, "timestamp", _IDENTITY_FALLBACKS["timestamp"])


def _emergency_line(record: logging.LogRecord, event: str, error_type: str) -> str:
    """A fixed line built from fixed text and validated identifiers only."""
    logger_name, level = _record_identity(record)
    return json.dumps(
        {
            "event": event,
            "level": level,
            "logger": logger_name,
            "timestamp": _record_timestamp(record),
            "error_type": error_type,
        }
    )


def _is_bounded_template(template: str) -> bool:
    """True if ``template % args`` cannot allocate more than its arguments call for.

    The scan follows the interpreter's own reading of a ``%`` directive: an
    optional ``(key)``, flags, width, ``.precision``, conversion. A width or
    precision is acceptable only as at most ``MAX_FORMAT_WIDTH``; one taken
    from the arguments (``*``) is not, and neither is a key the scan cannot
    delimit exactly as the interpreter would.
    """
    length = len(template)
    if length > MAX_FORMAT_TEMPLATE_LENGTH:
        return False
    directives = 0
    index = template.find("%")
    while index >= 0:
        index += 1
        if template.startswith("(", index):
            closing = template.find(")", index)
            if closing < 0 or template.find("(", index + 1, closing) >= 0:
                return False
            index = closing + 1
        while index < length and template[index] in _FORMAT_FLAGS:
            index += 1
        for part in ("width", "precision"):
            if template.startswith("*", index):
                return False
            start = index
            while index < length and template[index] in _DIGITS:
                index += 1
            if index - start > 3 or (
                index > start and int(template[start:index]) > MAX_FORMAT_WIDTH
            ):
                return False
            if part == "precision" or not template.startswith(".", index):
                break
            index += 1
        directives += 1
        if directives > MAX_FORMAT_DIRECTIVES:
            return False
        # Step over the conversion character, which may itself be "%".
        index = template.find("%", index + 1)
    return True


def _bounded_copy(record: logging.LogRecord) -> logging.LogRecord:
    """A new record holding only the standard attributes of ``record``.

    A record carries whatever a caller passed as ``extra=``: any number of
    attributes. Copying ``record.__dict__`` (as ``logging.makeLogRecord`` and
    structlog's formatter both do) costs in proportion to them. A fixed set
    of names is looked up instead, so the copy costs the same whatever else
    the record holds, and nothing outside that set travels any further.
    """
    attributes = record.__dict__
    return logging.makeLogRecord(
        {name: attributes[name] for name in _RECORD_ATTRIBUTES if name in attributes}
    )


def _with_sanitized_arguments(record: logging.LogRecord) -> logging.LogRecord:
    """A bounded copy of a record whose message parts are safe to interpolate.

    ``logging`` builds the message with ``str(msg) % args`` before any processor
    runs: an object's ``__str__``, raw bytes, a broken container or a huge
    field width would be turned into text that can no longer be interpreted or
    bounded. The message is therefore reduced to an exact ``str`` without
    asking it to convert itself, the format string is checked, and the
    arguments are sanitised structurally (which also bounds how much of them is
    visited) before anything is interpolated. The original record is never
    handed on: every later stage, structlog's formatter included, works on the
    bounded copy.

    A record whose message is the event the structlog pipeline has just
    produced in this thread carries that event, sanitised and bounded, and no
    arguments; the copy is marked for the formatter to read it as an event.
    Nothing the record says about itself takes part in that: an ordinary
    record with a mapping for a message, whatever its attributes, is a
    message like any other.
    """
    safe = _bounded_copy(record)
    message = record.msg
    if type(message) is dict and getattr(_PIPELINE_STATE, "event", None) is message:
        safe.__dict__.update(_EVENT_RECORD_ATTRIBUTES)
        return safe
    if type(message) is str and not record.args:
        return safe
    if not issubclass(type(message), str):
        sanitized = sanitize(message)
        safe.msg = sanitized if type(sanitized) is str else json.dumps(sanitized)
        safe.args = ()
        return safe
    # A str subclass: its character data, not whatever its __str__ would return,
    # and no more of it than can be examined. One character past the limit is
    # what tells the template check and the scrubber that it was longer.
    template, _ = leading_text(message, MAX_FORMAT_TEMPLATE_LENGTH + 1)
    safe.msg = template
    if not record.args:
        safe.args = ()
        return safe
    if not _is_bounded_template(template):
        raise _UnboundedFormatError
    arguments = sanitize(record.args)
    if isinstance(arguments, dict):
        safe.args = arguments
    elif isinstance(arguments, list):
        safe.args = tuple(arguments)
    else:
        raise TypeError("log arguments could not be sanitised")
    return safe


class FailClosedStreamHandler(logging.StreamHandler[TextIO]):
    """A stream handler that can never write an unsanitised record anywhere."""

    def format(self, record: logging.LogRecord) -> str:
        try:
            line = super().format(_with_sanitized_arguments(record))
        except _UnboundedFormatError:
            return _emergency_line(record, "log_record_unsafe_format", "UnboundedLogFormat")
        except Exception as exc:  # noqa: BLE001 — a fixed line replaces the unrenderable record
            return _emergency_line(record, "log_record_unrenderable", exception_type_name(exc))
        if len(line) > MAX_RENDERED_EVENT_LENGTH:
            return _emergency_line(record, "log_record_oversized", "OversizedLogRecord")
        return line

    def handleError(self, record: logging.LogRecord) -> None:
        # logging.Handler.handleError prints the record's message and arguments to
        # stderr, which may hold secrets. Only fixed text and validated
        # identifiers are written.
        error = sys.exc_info()[1]
        with contextlib.suppress(Exception):
            logger_name, level = _record_identity(record)
            sys.stderr.write(
                "voice_agent.logging: a log record could not be written "
                f"(logger={logger_name}, level={level}, "
                f"error={exception_type_name(error) if error else 'unknown'})\n"
            )


def configure_logging(
    *, service_name: str, environment: str, log_level: str, log_format: str
) -> None:
    """Install the process-wide logging pipeline. Safe to call more than once."""
    service = trusted_identifier(service_name, "service", _IDENTITY_FALLBACKS["service"])
    environment_label = trusted_identifier(
        environment, "environment", _IDENTITY_FALLBACKS["environment"]
    )

    renderer: Processor = (
        structlog.dev.ConsoleRenderer(colors=False)
        if log_format == "console"
        else structlog.processors.JSONRenderer(default=_unserializable)
    )

    structlog.configure(
        processors=[
            _EventPipeline(service=service, environment=environment_label, final=False),
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=BoundedBoundLogger,
        # Not cached: a later configure_logging() call must take effect everywhere.
        cache_logger_on_first_use=False,
    )

    handler = FailClosedStreamHandler(sys.stdout)
    handler.setFormatter(
        structlog.stdlib.ProcessorFormatter(
            # No pre-chain: a record of either origin goes straight to the
            # final pipeline, which establishes its operational metadata.
            processors=[
                _EventPipeline(service=service, environment=environment_label, final=True),
                # Final net: everything that reached this point is sanitised
                # once more, whatever produced it, as the complete values the
                # renderer will lay out. Nothing after it changes a value.
                redact_sensitive_fields,
                renderer,
            ],
        )
    )
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(log_level)

    # uvicorn installs its own plain-text handlers; route it through the pipeline instead.
    for name in _UVICORN_LOGGERS:
        uvicorn_logger = logging.getLogger(name)
        uvicorn_logger.handlers = []
        uvicorn_logger.propagate = True


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    logger: structlog.stdlib.BoundLogger = structlog.get_logger(name)
    return logger
