"""Where a record came from is not read from the record.

Independent review 7 (D0-P1-12). The handler recognised a record made by
structlog by two attributes, ``_logger`` and ``_name``, which any
standard-library caller can attach through ``extra=``. A record so marked
skipped the stage that establishes operational metadata, and the final pass
read that metadata from the event: a mapping logged as a message chose its
own request ID, service, environment, level and timestamp.

The cause was a decision of trust taken from what a record says about itself.
Two things replace it, and the tests are grouped by them:

* *Authoritative metadata for every record.* The final pass establishes level,
  logger, time, service, environment and the server's request ID from the log
  record, the configuration and the request context, for a record of either
  origin, and reads none of them from the event.
* *Origin by identity.* A record is an event of the pipeline only if its
  message is the object the pipeline has just produced. The marking
  attributes are never copied from a record.

Every test requires zero occurrences of a generated sentinel on stdout and on
stderr separately.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import re
import secrets
import sys
import threading
import tracemalloc
from collections.abc import Callable, Iterator
from typing import Any

import pytest
import structlog

from voice_agent.platform.infrastructure.observability import logging as logging_module
from voice_agent.platform.infrastructure.observability.logging import (
    MAX_RENDERED_EVENT_LENGTH,
    RESERVED,
    FailClosedStreamHandler,
    configure_logging,
    get_logger,
)
from voice_agent.platform.infrastructure.observability.redaction import REDACTED
from voice_agent.platform.shared_kernel.request_context import (
    RequestContext,
    bind_request_context,
    reset_request_context,
)

pytestmark = pytest.mark.unit

FORMATS = ("json", "console")
SERVICE = "voice-agent-test"
ENVIRONMENT = "test"
SERVER_REQUEST_ID = "actual-server-request"
FORGED_REQUEST_ID = "forged-client-request"
FORGED_TIMESTAMP = "1999-01-01T00:00:00Z"
STDLIB_LOGGER = "real.source"
STRUCTLOG_LOGGER = "real.structured"
METADATA = ("timestamp", "level", "logger", "service", "environment", "request_id")
_CONSOLE_LINE = re.compile(r"^(?P<timestamp>\S+) \[(?P<level>[a-z]+) *\] (?P<rest>.*)$")


@pytest.fixture
def sentinel() -> str:
    """A fresh, distinctive value per test; it is a secret only by where it is put."""
    return "D0LEAKSENTINEL" + secrets.token_hex(12)


@pytest.fixture(autouse=True)
def _clean_context() -> Iterator[None]:
    structlog.contextvars.clear_contextvars()
    yield
    structlog.contextvars.clear_contextvars()


@pytest.fixture(params=[True, False], ids=["in-request", "no-request"])
def request_id(request: pytest.FixtureRequest) -> Iterator[str | None]:
    """The request ID the server assigned, or ``None`` outside a request."""
    if not request.param:
        yield None
        return
    token = bind_request_context(RequestContext(request_id=SERVER_REQUEST_ID))
    try:
        yield SERVER_REQUEST_ID
    finally:
        reset_request_context(token)


@pytest.fixture
def in_request() -> Iterator[str]:
    token = bind_request_context(RequestContext(request_id=SERVER_REQUEST_ID))
    try:
        yield SERVER_REQUEST_ID
    finally:
        reset_request_context(token)


def _configure(log_format: str = "json") -> None:
    configure_logging(
        service_name=SERVICE, environment=ENVIRONMENT, log_level="INFO", log_format=log_format
    )


def _assert_absent(capsys: pytest.CaptureFixture[str], secret: str, what: str) -> tuple[str, str]:
    """stdout and stderr are checked separately; returns both."""
    captured = capsys.readouterr()
    assert captured.out.count(secret) == 0, f"{what}: on stdout"
    assert captured.err.count(secret) == 0, f"{what}: on stderr"
    return captured.out, captured.err


def _forged(secret: str) -> dict[str, Any]:
    """An event as a caller would write it to pass for one of the pipeline."""
    return {
        "event": "probe",
        "request_id": FORGED_REQUEST_ID,
        "service": "fake-service",
        "environment": "production",
        "timestamp": FORGED_TIMESTAMP,
        "level": "critical",
        "logger": "fake.logger",
        "password": secret,
    }


def _line_metadata(line: str, logger: str) -> dict[str, Any]:
    """What one output line says about itself, in either format.

    A JSON line is returned as it is. Of a console line: the leading
    timestamp and level, the logger in brackets, and the ``key=value`` fields
    that follow it; the text of the event is returned under ``event``.
    """
    if line.startswith("{"):
        parsed: dict[str, Any] = json.loads(line)
        return parsed
    match = _CONSOLE_LINE.match(line)
    assert match is not None, line
    event, bracket, tail = match["rest"].rpartition(f" [{logger}] ")
    assert bracket, f"no logger {logger!r} in: {line}"
    found: dict[str, Any] = {
        "timestamp": match["timestamp"],
        "level": match["level"],
        "logger": logger,
        "event": event.rstrip(),
    }
    for token in tail.split():
        key, separator, value = token.partition("=")
        if separator and key.isidentifier():
            assert key not in found, f"{key} appears twice in: {line}"
            found[key] = value
    return found


def _lines(output: str) -> list[str]:
    """The lines that start an event (a console traceback continues on further lines)."""
    return [
        line
        for line in output.splitlines()
        if line.startswith("{") or (line[:4].isdigit() and "[" in line)
    ]


def _assert_authoritative(
    found: dict[str, Any], *, level: str, logger: str, request_id: str | None
) -> None:
    assert found["service"] == SERVICE, found
    assert found["environment"] == ENVIRONMENT, found
    assert found["level"] == level, found
    assert found["logger"] == logger, found
    assert found.get("request_id") == request_id, found
    written = dt.datetime.fromisoformat(found["timestamp"])
    assert abs(dt.datetime.now(dt.UTC) - written) < dt.timedelta(minutes=5), found


class _FakeLogger:
    """What a caller might attach as ``_logger``."""

    name = "fake.logger"
    level = logging.CRITICAL


# ---------------------------------------------------------------- the reproduction


@pytest.mark.parametrize("log_format", FORMATS)
def test_the_reviewer_reproduction_of_the_marked_standard_library_record(
    capsys: pytest.CaptureFixture[str], log_format: str
) -> None:
    _configure(log_format)
    logger = logging.getLogger(STDLIB_LOGGER)
    token = bind_request_context(RequestContext(request_id=SERVER_REQUEST_ID))
    try:
        logger.info(
            {
                "event": "probe",
                "request_id": "forged-client-request",
                "service": "fake-service",
                "environment": "production",
                "timestamp": "2026-01-01T00:00:00Z",
                "level": "critical",
            },
            extra={"_logger": logger, "_name": "info"},
        )
    finally:
        reset_request_context(token)
    captured = capsys.readouterr()
    assert captured.err == ""
    (line,) = _lines(captured.out)
    found = _line_metadata(line, STDLIB_LOGGER)
    _assert_authoritative(found, level="info", logger=STDLIB_LOGGER, request_id=SERVER_REQUEST_ID)
    assert not found["timestamp"].startswith("2026-01-01T00:00:00")
    # The mapping is the message of the record, and nothing but its message.
    assert "forged-client-request" in found["event"]
    if log_format == "json":
        assert set(found) == {*METADATA, "event"}


# ---------------------------------------------------------------- authoritative metadata


def _hand_built_record(logger: logging.Logger, fields: dict[str, Any]) -> None:
    record = logging.LogRecord(logger.name, logging.INFO, __file__, 1, dict(fields), (), None)
    record.__dict__.update(fields, _logger=logger, _name="info", _from_structlog=True)
    logger.handle(record)


# Every way a standard-library caller can present the forged event. Each logs
# one record at INFO.
_STDLIB_CHANNELS: dict[str, Callable[[logging.Logger, dict[str, Any]], None]] = {
    "marked-mapping": lambda logger, fields: logger.info(
        dict(fields), extra={"_logger": logger, "_name": "info"}
    ),
    "marked-mapping-foreign-logger": lambda logger, fields: logger.info(
        dict(fields), extra={"_logger": _FakeLogger(), "_name": "critical"}
    ),
    "marked-mapping-with-processor-metadata": lambda logger, fields: logger.info(
        dict(fields),
        extra={"_logger": logger, "_name": "info", "_record": None, "_from_structlog": True},
    ),
    "mapping": lambda logger, fields: logger.info(dict(fields)),
    "extra-fields": lambda logger, fields: logger.info("probe", extra=dict(fields)),
    "marked-text": lambda logger, fields: logger.info(
        "probe password=%s",
        fields["password"],
        extra={"_logger": logger, "_name": "info", **fields},
    ),
    "marked-plain-text": lambda logger, fields: logger.info(
        "probe", extra={"_logger": logger, "_name": "info", **fields}
    ),
    "marked-keyed-arguments": lambda logger, fields: logger.info(
        "probe %(request_id)s %(level)s %(password)s",
        dict(fields),
        extra={"_logger": logger, "_name": "info"},
    ),
    "hand-built-record": _hand_built_record,
}


@pytest.mark.parametrize("channel", sorted(_STDLIB_CHANNELS))
@pytest.mark.parametrize("log_format", FORMATS)
def test_a_standard_library_record_cannot_choose_its_operational_metadata(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    log_format: str,
    channel: str,
    request_id: str | None,
) -> None:
    _configure(log_format)
    _STDLIB_CHANNELS[channel](logging.getLogger(STDLIB_LOGGER), _forged(sentinel))
    out, err = _assert_absent(capsys, sentinel, channel)
    assert err == ""
    (line,) = _lines(out)
    found = _line_metadata(line, STDLIB_LOGGER)
    # Outside a request there is no request ID: a standard-library record has
    # no field that could carry one.
    _assert_authoritative(found, level="info", logger=STDLIB_LOGGER, request_id=request_id)
    if log_format == "json":
        # Nothing of the forged event became a field of the line.
        assert set(found) == {*METADATA, "event"} - (
            {"request_id"} if request_id is None else set()
        )
        assert "log_record_unrenderable" not in line and "log_processing_failed" not in line
    if "password" in found["event"]:
        assert REDACTED in found["event"]


def _structlog_call(log: Any, fields: dict[str, Any]) -> None:
    log.info(fields["event"], **{key: value for key, value in fields.items() if key != "event"})


def _structlog_bound(log: Any, fields: dict[str, Any]) -> None:
    log.bind(**{key: value for key, value in fields.items() if key != "event"}).info("probe")


def _structlog_context(log: Any, fields: dict[str, Any]) -> None:
    structlog.contextvars.bind_contextvars(**fields)
    log.info("probe")


_STRUCTLOG_CHANNELS: dict[str, Callable[[Any, dict[str, Any]], None]] = {
    "call-fields": _structlog_call,
    "bound-fields": _structlog_bound,
    "context-fields": _structlog_context,
}


@pytest.mark.parametrize("channel", sorted(_STRUCTLOG_CHANNELS))
@pytest.mark.parametrize("log_format", FORMATS)
def test_a_structlog_event_cannot_choose_its_operational_metadata(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    log_format: str,
    channel: str,
    in_request: str,
) -> None:
    _configure(log_format)
    _STRUCTLOG_CHANNELS[channel](get_logger(STRUCTLOG_LOGGER), _forged(sentinel))
    out, _ = _assert_absent(capsys, sentinel, channel)
    (line,) = _lines(out)
    found = _line_metadata(line, STRUCTLOG_LOGGER)
    _assert_authoritative(found, level="info", logger=STRUCTLOG_LOGGER, request_id=in_request)
    assert found["event"] == "probe" and found["password"] == REDACTED
    assert FORGED_REQUEST_ID not in line and "fake-service" not in line


@pytest.mark.parametrize("method", ["info", "warning", "error", "critical"])
@pytest.mark.parametrize("log_format", FORMATS)
def test_the_level_of_a_line_is_the_level_of_the_logging_call(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, method: str, in_request: str
) -> None:
    _configure(log_format)
    stdlib = logging.getLogger(STDLIB_LOGGER)
    claimed = "info" if method == "critical" else "critical"
    fields = {**_forged(sentinel), "level": claimed}
    getattr(stdlib, method)(dict(fields), extra={"_logger": stdlib, "_name": claimed})
    getattr(stdlib, method)("probe", extra={"_name": claimed, "level": claimed})
    getattr(get_logger(STRUCTLOG_LOGGER), method)("probe", level=claimed, _name=claimed)
    out, _ = _assert_absent(capsys, sentinel, method)
    first, second, third = _lines(out)
    for line, logger in (
        (first, STDLIB_LOGGER),
        (second, STDLIB_LOGGER),
        (third, STRUCTLOG_LOGGER),
    ):
        found = _line_metadata(line, logger)
        _assert_authoritative(found, level=method, logger=logger, request_id=in_request)


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_filtered_level_stays_filtered_whatever_the_record_claims(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    stdlib = logging.getLogger(STDLIB_LOGGER)
    stdlib.debug(_forged(sentinel), extra={"_logger": stdlib, "_name": "critical"})
    captured = capsys.readouterr()
    assert captured.out == "" and captured.err == ""


# ---------------------------------------------------------------- origin by identity


def test_the_marking_attributes_are_never_copied_from_a_record(sentinel: str) -> None:
    _configure()
    logger = logging.getLogger(STDLIB_LOGGER)
    record = logging.LogRecord(
        STDLIB_LOGGER, logging.INFO, __file__, 1, _forged(sentinel), (), None
    )
    record.__dict__.update(_logger=logger, _name="info", _record=record, _from_structlog=True)
    copy = logging_module._with_sanitized_arguments(record)
    assert copy is not record
    assert not {"_logger", "_name", "_record", "_from_structlog"} & set(copy.__dict__)
    # The mapping has become a message: one sanitised text, with no arguments.
    assert type(copy.msg) is str and copy.args == ()
    assert sentinel not in copy.msg and REDACTED in copy.msg


class _Capture(logging.Handler):
    """Keeps the records it is given, as a handler beside the pipeline's would see them."""

    def __init__(self) -> None:
        super().__init__()
        self.records: list[logging.LogRecord] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.records.append(record)


def _pipeline_event(capture: _Capture) -> dict[str, Any]:
    """The event the pipeline produced for the last structlog call."""
    message = capture.records[-1].msg
    assert type(message) is dict
    return message


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_copy_of_a_pipeline_event_is_a_message_like_any_other(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, request_id: str | None
) -> None:
    _configure(log_format)
    capture = _Capture()
    logging.getLogger().addHandler(capture)
    get_logger(STRUCTLOG_LOGGER).info("genuine")
    capsys.readouterr()
    # Equal in every key to what the pipeline made, and not the object it made.
    lookalike = {**_pipeline_event(capture), **_forged(sentinel)}
    stdlib = logging.getLogger(STDLIB_LOGGER)
    stdlib.warning(lookalike, extra={"_logger": stdlib, "_name": "info"})
    out, _ = _assert_absent(capsys, sentinel, "lookalike")
    (line,) = _lines(out)
    found = _line_metadata(line, STDLIB_LOGGER)
    _assert_authoritative(found, level="warning", logger=STDLIB_LOGGER, request_id=request_id)
    if log_format == "json":
        assert "password" not in found and type(found["event"]) is str
        assert json.loads(found["event"])["request_id"] == FORGED_REQUEST_ID


@pytest.mark.parametrize("log_format", FORMATS)
def test_even_the_event_of_the_pipeline_itself_gains_no_metadata_by_being_logged_again(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, in_request: str
) -> None:
    """Being taken for an event of the pipeline confers nothing.

    Code inside the process that holds the very object the pipeline produced
    (here: a handler) changes it and logs it again. It is read as an event,
    and its metadata is still that of the call that logged it.
    """
    _configure(log_format)
    capture = _Capture()
    logging.getLogger().addHandler(capture)
    get_logger(STRUCTLOG_LOGGER).info("genuine")
    capsys.readouterr()
    event = _pipeline_event(capture)
    event.update(
        _forged(sentinel), _record=f"password={sentinel}", exception=["password=", sentinel]
    )
    logging.getLogger(STDLIB_LOGGER).warning(event)
    out, _ = _assert_absent(capsys, sentinel, "replayed event")
    (line,) = _lines(out)
    found = _line_metadata(line, STDLIB_LOGGER)
    _assert_authoritative(found, level="warning", logger=STDLIB_LOGGER, request_id=in_request)
    assert FORGED_REQUEST_ID not in line and "fake-service" not in line
    assert FORGED_TIMESTAMP not in line and "_record" not in line


def test_an_event_of_another_thread_is_not_an_event_of_this_one(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    capture = _Capture()
    logging.getLogger().addHandler(capture)
    worker = threading.Thread(target=lambda: get_logger(STRUCTLOG_LOGGER).info("from_worker"))
    worker.start()
    worker.join()
    (first,) = (json.loads(line) for line in capsys.readouterr().out.splitlines())
    # A structlog call is an event in whichever thread it is made.
    assert first["event"] == "from_worker" and first["logger"] == STRUCTLOG_LOGGER
    event = _pipeline_event(capture)
    event.update(_forged(sentinel))
    logging.getLogger(STDLIB_LOGGER).warning(event)
    out, _ = _assert_absent(capsys, sentinel, "event of another thread")
    (second,) = (json.loads(line) for line in out.splitlines())
    assert set(second) == {"timestamp", "level", "logger", "service", "environment", "event"}
    assert (second["level"], second["logger"]) == ("warning", STDLIB_LOGGER)


# ---------------------------------------------------------------- what still works


@pytest.mark.parametrize("log_format", FORMATS)
def test_structlog_events_keep_their_fields_and_their_metadata(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, request_id: str | None
) -> None:
    _configure(log_format)
    log = get_logger(STRUCTLOG_LOGGER)
    log.info("call_started", attempt=3, password=sentinel)
    log.bind(tenant="acme").warning("call_slow", elapsed_ms=1250)
    try:
        raise LookupError(f"nothing found password={sentinel}")
    except LookupError:
        log.exception("call_failed")
    log.info("with_reserved", _record=sentinel)
    out, _ = _assert_absent(capsys, sentinel, "structlog events")
    lines = _lines(out)
    assert len(lines) == 4
    expected = (("info", "call_started"), ("warning", "call_slow"), ("error", "call_failed"))
    for line, (level, event) in zip(lines, expected, strict=False):
        found = _line_metadata(line, STRUCTLOG_LOGGER)
        _assert_authoritative(found, level=level, logger=STRUCTLOG_LOGGER, request_id=request_id)
        assert found["event"] == event
    assert _line_metadata(lines[0], STRUCTLOG_LOGGER)["password"] == REDACTED
    assert "LookupError: nothing found" in out and RESERVED in lines[3]
    if log_format == "json":
        first, second, third, _ = (json.loads(line) for line in lines)
        assert first["attempt"] == 3
        assert (second["tenant"], second["elapsed_ms"]) == ("acme", 1250)
        assert third["exception"].startswith("Traceback (most recent call last):")


def test_outside_a_request_a_structlog_request_id_is_kept_as_before(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    log = get_logger(STRUCTLOG_LOGGER)
    log.info("job", request_id="job-17")
    log.info("job", request_id="not a request id")
    structlog.contextvars.bind_contextvars(request_id="context-id")
    log.info("job", request_id="forged-id")
    logging.getLogger(STDLIB_LOGGER).info("job", extra={"request_id": "forged-id"})
    identifiers = [json.loads(line)["request_id"] for line in capsys.readouterr().out.splitlines()]
    assert identifiers == ["job-17", "untrusted_request_id", "context-id", "context-id"]


@pytest.mark.parametrize("log_format", FORMATS)
def test_ordinary_standard_library_logging_is_unchanged(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, request_id: str | None
) -> None:
    _configure(log_format)
    stdlib = logging.getLogger(STDLIB_LOGGER)
    stdlib.info("plain message")
    stdlib.warning("call %s took %d ms", "c-1", 1250)
    stdlib.warning("keyed %(call)s", {"call": "c-1"})
    stdlib.info({"call": "c-1", "password": sentinel})
    try:
        raise LookupError("nothing found")
    except LookupError:
        stdlib.exception("lookup failed for %s", "c-1")
    out, _ = _assert_absent(capsys, sentinel, "ordinary records")
    lines = _lines(out)
    expected = (
        ("info", "plain message"),
        ("warning", "call c-1 took 1250 ms"),
        ("warning", "keyed c-1"),
        ("info", json.dumps({"call": "c-1", "password": REDACTED})),
        ("error", "lookup failed for c-1"),
    )
    assert len(lines) == len(expected)
    for line, (level, event) in zip(lines, expected, strict=True):
        found = _line_metadata(line, STDLIB_LOGGER)
        _assert_authoritative(found, level=level, logger=STDLIB_LOGGER, request_id=request_id)
        assert found["event"] == event
    assert "LookupError: nothing found" in out


# ---------------------------------------------------------------- failure paths


class _BrokenStream:
    def write(self, _text: str) -> int:
        raise OSError("disk full")

    def flush(self) -> None:
        raise OSError("flush failed")


def _fail_in_processor(monkeypatch: pytest.MonkeyPatch, secret: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> object:
        raise RuntimeError(f"context merge broke on password={secret}")

    monkeypatch.setattr(logging_module, "merge_bounded_contextvars", explode)


def _fail_in_sanitiser(monkeypatch: pytest.MonkeyPatch, secret: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> object:
        raise RecursionError(f"sanitiser broke on password={secret}")

    monkeypatch.setattr(logging_module, "sanitize_event", explode)


def _fail_in_formatter(monkeypatch: pytest.MonkeyPatch, secret: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> str:
        raise ValueError(f"cannot render password={secret}")

    monkeypatch.setattr(structlog.processors.JSONRenderer, "__call__", explode)
    monkeypatch.setattr(structlog.dev.ConsoleRenderer, "__call__", explode)


_PIPELINE_FAILURES: dict[str, tuple[Callable[[pytest.MonkeyPatch, str], None], str, bool]] = {
    # name: (installer, the fixed event, whether the fixed record is rendered by the pipeline)
    "processor": (_fail_in_processor, "log_processing_failed", True),
    "sanitiser": (_fail_in_sanitiser, "log_event_redaction_failed", True),
    "formatter": (_fail_in_formatter, "log_record_unrenderable", False),
}


def _log_forged_everywhere(secret: str) -> int:
    stdlib = logging.getLogger(STDLIB_LOGGER)
    fields = _forged(secret)
    stdlib.info(dict(fields), extra={"_logger": stdlib, "_name": "info"})
    stdlib.info("probe password=%s", secret, extra={"_logger": stdlib, "_name": "info", **fields})
    _structlog_call(get_logger(STDLIB_LOGGER), fields)
    return 3


@pytest.mark.parametrize("failure", sorted(_PIPELINE_FAILURES))
@pytest.mark.parametrize("log_format", FORMATS)
def test_the_fixed_record_of_a_failure_carries_authoritative_metadata(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    log_format: str,
    failure: str,
    in_request: str,
) -> None:
    _configure(log_format)
    install, expected, rendered = _PIPELINE_FAILURES[failure]
    install(monkeypatch, sentinel)
    count = _log_forged_everywhere(sentinel)
    out, err = _assert_absent(capsys, sentinel, f"{failure} failure")
    assert err == ""
    lines = _lines(out)
    assert len(lines) == count and out.count(expected) == count
    for line in lines:
        assert FORGED_REQUEST_ID not in line and "fake-service" not in line
        assert FORGED_TIMESTAMP not in line and "critical" not in line
        found = _line_metadata(line, STDLIB_LOGGER)
        if rendered:
            _assert_authoritative(found, level="info", logger=STDLIB_LOGGER, request_id=in_request)
        else:
            # The handler's own fixed line: fixed text and the record's identifiers.
            assert set(found) == {"event", "level", "logger", "timestamp", "error_type"}
            assert (found["level"], found["logger"]) == ("info", STDLIB_LOGGER)


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_writer_failure_shows_nothing_of_a_marked_record(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, in_request: str
) -> None:
    _configure(log_format)
    handler = logging.getLogger().handlers[0]
    assert isinstance(handler, FailClosedStreamHandler)
    handler.setStream(_BrokenStream())  # type: ignore[arg-type]
    count = _log_forged_everywhere(sentinel)
    out, err = _assert_absent(capsys, sentinel, "writer failure")
    assert out == ""
    assert (
        err.splitlines()
        == [
            "voice_agent.logging: a log record could not be written "
            f"(logger={STDLIB_LOGGER}, level=info, error=OSError)"
        ]
        * count
    )


# ---------------------------------------------------------------- bounded preparation


def _peak_while(action: Callable[[], object]) -> int:
    tracemalloc.start()
    try:
        action()
        return tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_marked_record_with_an_unbounded_format_is_replaced_by_a_fixed_record(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, in_request: str
) -> None:
    _configure(log_format)
    stdlib = logging.getLogger(STDLIB_LOGGER)
    marks = {"_logger": stdlib, "_name": "info", **_forged(sentinel)}
    templates = ("%10000000s", "%*d", "%.10000000f", "%(password)10000000s")
    stdlib.info("warm-up")
    capsys.readouterr()
    peaks = []
    for template in templates:
        arguments: tuple[object, ...] = (
            ({"password": sentinel},) if "(" in template else (7, 7)[: template.count("*") + 1]
        )
        peaks.append(_peak_while(lambda: stdlib.info(template, *arguments, extra=marks)))  # noqa: B023
    out, err = _assert_absent(capsys, sentinel, "unbounded format")
    assert err == ""
    lines = [json.loads(line) for line in out.splitlines()]
    assert [line["event"] for line in lines] == ["log_record_unsafe_format"] * len(templates)
    assert all((line["level"], line["logger"]) == ("info", STDLIB_LOGGER) for line in lines)
    # A width of ten million would have allocated ten megabytes.
    assert max(peaks) < 256_000, peaks


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_marked_oversized_message_costs_a_bounded_amount(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, in_request: str
) -> None:
    _configure(log_format)
    stdlib = logging.getLogger(STDLIB_LOGGER)
    marks = {"_logger": stdlib, "_name": "info"}
    wide: dict[str, Any] = {f"field_{index}": index for index in range(100_000)}
    wide.update(_forged(sentinel))

    class LongText(str):
        __slots__ = ()

    long_text = LongText("x" * 10_000_000 + f" password={sentinel}")
    messages: dict[str, tuple[object, tuple[object, ...]]] = {
        "wide-mapping": (wide, ()),
        "long-text": (long_text, ()),
        "long-template": (long_text, ("argument",)),
        "long-argument": ("probe %s", (long_text,)),
    }
    stdlib.info({"warm": "up"}, extra=marks)
    stdlib.info("warm-up %s", "argument", extra=marks)
    capsys.readouterr()
    peaks = {
        name: _peak_while(lambda: stdlib.info(message, *arguments, extra=marks))  # noqa: B023
        for name, (message, arguments) in messages.items()
    }
    out, err = _assert_absent(capsys, sentinel, "oversized message")
    assert err == ""
    lines = _lines(out)
    assert len(lines) == len(messages)
    for name, line in zip(messages, lines, strict=True):
        assert len(line) < MAX_RENDERED_EVENT_LENGTH
        found = _line_metadata(line, STDLIB_LOGGER)
        if name == "long-template":
            # A format string too long to examine: the handler's own fixed line.
            assert found["event"] == "log_record_unsafe_format"
            assert (found["level"], found["logger"]) == ("info", STDLIB_LOGGER)
            continue
        _assert_authoritative(found, level="info", logger=STDLIB_LOGGER, request_id=in_request)
    # A copy of the mapping is over five megabytes, one of the text ten.
    assert max(peaks.values()) < 1_000_000, peaks


# ---------------------------------------------------------------- secondary handlers


def _attach_supported_handler(logger: logging.Logger) -> None:
    """A second handler as the module documents one: its class and its formatter."""
    handler = FailClosedStreamHandler(sys.stderr)
    handler.setFormatter(logging.getLogger().handlers[0].formatter)
    logger.addHandler(handler)


@pytest.mark.parametrize("attach_to", ["root", STDLIB_LOGGER])
@pytest.mark.parametrize("log_format", FORMATS)
def test_a_second_supported_handler_writes_the_same_authoritative_line(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    log_format: str,
    attach_to: str,
    request_id: str | None,
) -> None:
    _configure(log_format)
    named = logging.getLogger(STDLIB_LOGGER)
    target = logging.getLogger() if attach_to == "root" else named
    _attach_supported_handler(target)
    try:
        for channel in sorted(_STDLIB_CHANNELS):
            _STDLIB_CHANNELS[channel](named, _forged(sentinel))
        # An event of the pipeline is an event for every handler that formats it.
        get_logger(STDLIB_LOGGER).warning("genuine", attempt=3, password=sentinel)
    finally:
        if target is named:
            named.handlers.clear()
    out, err = _assert_absent(capsys, sentinel, "second handler")
    out_lines, err_lines = _lines(out), _lines(err)
    assert len(out_lines) == len(err_lines) == len(_STDLIB_CHANNELS) + 1
    for stream in (out_lines, err_lines):
        for line in stream[:-1]:
            found = _line_metadata(line, STDLIB_LOGGER)
            _assert_authoritative(found, level="info", logger=STDLIB_LOGGER, request_id=request_id)
        genuine = _line_metadata(stream[-1], STDLIB_LOGGER)
        _assert_authoritative(genuine, level="warning", logger=STDLIB_LOGGER, request_id=request_id)
        assert genuine["event"] == "genuine" and genuine["password"] == REDACTED
    # Both handlers laid out the same event: same fields, same metadata.
    strip = re.compile(r"\d{4}-\d{2}-\d{2}T[0-9:.]+Z")
    assert [strip.sub("", line) for line in out_lines] == [
        strip.sub("", line) for line in err_lines
    ]


@pytest.mark.parametrize("log_format", FORMATS)
def test_an_independent_handler_receives_a_structlog_event_with_authoritative_metadata(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, in_request: str
) -> None:
    """A plain handler prints the record's message: for structlog, the event of the pipeline."""
    _configure(log_format)
    capture = _Capture()
    logging.getLogger().addHandler(capture)
    logging.getLogger().addHandler(logging.StreamHandler(sys.stderr))
    for channel in sorted(_STRUCTLOG_CHANNELS):
        structlog.contextvars.clear_contextvars()
        _STRUCTLOG_CHANNELS[channel](get_logger(STRUCTLOG_LOGGER), _forged(sentinel))
    _, err = _assert_absent(capsys, sentinel, "independent handler")
    assert len(err.splitlines()) == len(capture.records) == len(_STRUCTLOG_CHANNELS)
    assert FORGED_REQUEST_ID not in err and "fake-service" not in err
    for record in capture.records:
        event = record.msg
        assert type(event) is dict
        _assert_authoritative(event, level="info", logger=STRUCTLOG_LOGGER, request_id=in_request)
        assert event["password"] == REDACTED
