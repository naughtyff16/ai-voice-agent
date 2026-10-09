"""The logging pipeline: shape, context preservation and fail-closed redaction (D0-P0-01).

Every leak test plants the same distinctive, per-run sentinel in one data shape
and asserts it occurs zero times in everything the process wrote to stdout and
stderr. The sentinel is never a recognisable credential on its own: it only
becomes one through the form it is placed in (a password field, a URL, a header).
"""

from __future__ import annotations

import json
import logging
import secrets
import time
from collections.abc import Callable
from typing import Any

import pytest
import structlog
from pydantic import BaseModel, ValidationError

from voice_agent.platform.infrastructure.observability import logging as logging_module
from voice_agent.platform.infrastructure.observability.logging import (
    REDACTED,
    configure_logging,
    get_logger,
    redact_sensitive_fields,
)
from voice_agent.platform.infrastructure.observability.redaction import (
    CYCLE,
    MAX_DEPTH,
    MAX_STRING_LENGTH,
    TRUNCATED,
    TRUNCATED_SENSITIVE,
    UNSUPPORTED,
    render_exception,
    sanitize,
    scrub_text,
)

pytestmark = pytest.mark.unit

# Generated per run, so the suite contains no password-like literal.
SECRET = secrets.token_urlsafe(16)
SENTINEL = "D0LEAKSENTINEL" + secrets.token_hex(12)


def _configure(log_format: str = "json") -> None:
    configure_logging(
        service_name="voice-agent-test", environment="test", log_level="INFO", log_format=log_format
    )


def _json_lines(output: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in output.splitlines() if line.strip()]


def _all_output(capsys: pytest.CaptureFixture[str]) -> str:
    captured = capsys.readouterr()
    return captured.out + captured.err


def _assert_no_sentinel(output: str) -> None:
    assert output.count(SENTINEL) == 0, output


def test_json_lines_carry_timestamp_level_and_service_identity(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    get_logger("tests.logging").info("something_happened", attempt=3)
    (line,) = _json_lines(capsys.readouterr().out)
    assert line["event"] == "something_happened"
    assert line["level"] == "info"
    assert line["service"] == "voice-agent-test"
    assert line["environment"] == "test"
    assert line["logger"] == "tests.logging"
    assert line["attempt"] == 3
    assert isinstance(line["timestamp"], str) and line["timestamp"].endswith("Z")


def test_standard_library_loggers_share_the_pipeline(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    logging.getLogger("uvicorn.error").warning(
        "connection to %s failed", f"redis://:{SECRET}@h:6379"
    )
    (line,) = _json_lines(capsys.readouterr().out)
    assert line["level"] == "warning"
    assert line["service"] == "voice-agent-test"
    assert SECRET not in json.dumps(line)


def test_sensitive_fields_and_url_credentials_are_redacted(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    get_logger("tests.logging").info(
        "connecting",
        password=SECRET,
        authorization=f"Bearer {SECRET}",
        api_key=SECRET,
        phone_number="+919876543210",
        database_dsn=f"postgresql+asyncpg://app_api:{SECRET}@db:5432/x",
        target=f"postgresql+asyncpg://app_api:{SECRET}@db:5432/x",
        nested={"headers": {"Authorization": SECRET, "x-ok": "visible"}},
        items=[f"rediss://default:{SECRET}@cache:6380/0"],
    )
    output = capsys.readouterr().out
    assert SECRET not in output
    assert "+919876543210" not in output
    (line,) = _json_lines(output)
    assert line["password"] == REDACTED
    assert line["nested"] == {"headers": {"Authorization": REDACTED, "x-ok": "visible"}}
    assert line["target"] == f"postgresql+asyncpg://{REDACTED}@db:5432/x"


def test_exception_tracebacks_are_redacted(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    try:
        raise ConnectionError(f"cannot reach redis://:{SECRET}@cache:6379/0")
    except ConnectionError:
        get_logger("tests.logging").exception("redis_failed")
    output = capsys.readouterr().out
    assert "redis_failed" in output
    assert "ConnectionError" in output
    assert SECRET not in output


def test_console_format_is_human_readable(capsys: pytest.CaptureFixture[str]) -> None:
    _configure("console")
    get_logger("tests.logging").info("hello_console", password=SECRET)
    output = capsys.readouterr().out
    assert "hello_console" in output
    assert SECRET not in output
    with pytest.raises(json.JSONDecodeError):
        json.loads(output.splitlines()[0])


def test_redaction_processor_leaves_ordinary_fields_untouched() -> None:
    event = {"event": "x", "count": 2, "path": "/health/ready", "tags": ("a", "b")}
    assert redact_sensitive_fields(None, "info", dict(event)) == {**event, "tags": ["a", "b"]}


# ---------------------------------------------------------------- D0-P0-01 leak matrix


class _Probe(BaseModel):
    # No hide_input_in_errors: str(ValidationError) would echo the rejected input.
    count: int


class _Leaky:
    # The bare sentinel, in no recognisable credential form: only never calling
    # repr()/str() on an unknown object keeps it out of the log.
    def __repr__(self) -> str:
        return f"<_Leaky holding {SENTINEL}>"

    def __str__(self) -> str:
        return f"leaky {SENTINEL}"


class _UnprintableError(Exception):
    def __str__(self) -> str:
        raise RuntimeError(f"password={SENTINEL}")


def _nested(depth: int, leaf: dict[str, object]) -> dict[str, object]:
    node: dict[str, object] = leaf
    for level in range(depth):
        node = {f"level_{level}": node}
    return node


def _log_normal_dict(log: Any) -> None:
    log.info("event", password=SENTINEL, headers={"Authorization": f"Bearer {SENTINEL}"})


def _log_nested_dict(log: Any) -> None:
    log.info("event", config={"database": {"credentials": {"client_secret": SENTINEL}}})


def _log_beyond_depth(log: Any) -> None:
    log.info("event", deep=_nested(MAX_DEPTH * 4, {"password": SENTINEL, "note": SENTINEL}))


def _log_collections(log: Any) -> None:
    log.info(
        "event",
        items=[{"token": SENTINEL}],
        pair=(f"password={SENTINEL}",),
        tags={f"api_key={SENTINEL}"},
        frozen=frozenset({f"secret={SENTINEL}"}),
    )


def _log_cycle(log: Any) -> None:
    mapping: dict[str, object] = {"password": SENTINEL, "hint": f"token={SENTINEL}"}
    mapping["self"] = mapping
    sequence: list[object] = [mapping, f"passwd={SENTINEL}"]
    sequence.append(sequence)
    log.info("event", mapping=mapping, sequence=sequence)


def _log_query_credential_urls(log: Any) -> None:
    log.info(
        f"calling https://api.example.test/callback?code=1&access_token={SENTINEL}&state=ok",
        target=f"postgresql://db.example.test/app?sslmode=require&password={SENTINEL}",
        webhook=f"https://hooks.example.test/x?api-key={SENTINEL}",
    )


def _log_userinfo_urls(log: Any) -> None:
    log.info(
        f"connecting to postgresql+asyncpg://app_api:{SENTINEL}@db:5432/x",
        cache=f"rediss://default:p@{SENTINEL}@cache:6380/0",
        broker=f"amqp://user:{SENTINEL}/x@broker/vhost",
    )


def _log_authorization_text(log: Any) -> None:
    log.info(
        f"upstream sent Authorization: Bearer {SENTINEL}",
        raw=f"proxy-authorization=Basic {SENTINEL}",
        header_line=f"curl -H 'Authorization: Token {SENTINEL}'",
        bare=f"using bearer {SENTINEL}",
    )


def _log_exception_message(log: Any) -> None:
    try:
        raise RuntimeError(f"upstream rejected Authorization: Bearer {SENTINEL}")
    except RuntimeError:
        log.exception("call_failed")


def _log_chained_traceback(log: Any) -> None:
    try:
        try:
            raise ValueError(f"bad option password={SENTINEL}")
        except ValueError as inner:
            raise ConnectionError(f"cannot reach redis://:{SENTINEL}@cache:6379/0") from inner
    except ConnectionError:
        log.exception("chained_failure")


def _log_validation_exception(log: Any) -> None:
    try:
        _Probe.model_validate({"count": SENTINEL})
    except Exception as exc:
        log.exception("validation_failed")
        log.error("validation_failed_as_value", error=exc)


def _log_unsupported_object(log: Any) -> None:
    log.info("event", obj=_Leaky(), items=[_Leaky()], mapping={_Leaky(): _Leaky()})


def _log_unprintable_exception(log: Any) -> None:
    try:
        raise _UnprintableError
    except _UnprintableError as exc:
        log.exception("unprintable", error=exc)


def _log_positional_arguments(log: Any) -> None:
    log.info("event %s", f"password={SENTINEL}")


def _stdlib_exception(_log: Any) -> None:
    try:
        raise RuntimeError(f"token={SENTINEL}")
    except RuntimeError:
        logging.getLogger("uvicorn.error").exception(
            "ASGI failure for %s", f"https://u:{SENTINEL}@h/"
        )


def _stdlib_bad_format_arguments(_log: Any) -> None:
    # Too few arguments: getMessage() raises inside the formatter.
    logging.getLogger("tests.stdlib").warning("value %s and %s", f"password={SENTINEL}")


def _stdlib_validation_exception(_log: Any) -> None:
    try:
        _Probe.model_validate({"count": SENTINEL})
    except Exception:
        logging.getLogger("tests.stdlib").error("validation", exc_info=True)


LEAK_SCENARIOS: tuple[Callable[[Any], None], ...] = (
    _log_normal_dict,
    _log_nested_dict,
    _log_beyond_depth,
    _log_collections,
    _log_cycle,
    _log_query_credential_urls,
    _log_userinfo_urls,
    _log_authorization_text,
    _log_exception_message,
    _log_chained_traceback,
    _log_validation_exception,
    _log_unsupported_object,
    _log_unprintable_exception,
    _log_positional_arguments,
    _stdlib_exception,
    _stdlib_bad_format_arguments,
    _stdlib_validation_exception,
)


@pytest.mark.parametrize("log_format", ["json", "console"])
@pytest.mark.parametrize("scenario", LEAK_SCENARIOS, ids=lambda scenario: scenario.__name__)
def test_secret_never_reaches_stdout_or_stderr(
    capsys: pytest.CaptureFixture[str], scenario: Callable[[Any], None], log_format: str
) -> None:
    _configure(log_format)
    scenario(get_logger("tests.leak"))
    output = _all_output(capsys)
    assert output.strip(), "the scenario must emit something"
    _assert_no_sentinel(output)


def test_depth_cycles_and_unknown_objects_are_replaced_by_markers(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    log = get_logger("tests.leak")
    _log_beyond_depth(log)
    _log_cycle(log)
    _log_unsupported_object(log)
    output = capsys.readouterr().out
    assert TRUNCATED in output
    assert CYCLE in output
    assert UNSUPPORTED in output
    assert "_Leaky" not in output


def test_chained_traceback_keeps_its_structure(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    _log_chained_traceback(get_logger("tests.leak"))
    (line,) = _json_lines(capsys.readouterr().out)
    exception = str(line["exception"])
    assert exception.count("Traceback (most recent call last):") == 2
    assert "direct cause of the following exception" in exception
    assert "ValueError: bad option password=[REDACTED]" in exception
    assert "ConnectionError: cannot reach redis://[REDACTED]@cache:6379/0" in exception
    assert "_log_chained_traceback" in exception  # frames survive


def test_validation_errors_are_summarised_without_input(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    _log_validation_exception(get_logger("tests.leak"))
    lines = _json_lines(capsys.readouterr().out)
    assert "1 validation error(s): count: Input should be a valid integer" in str(
        lines[0]["exception"]
    )
    assert str(lines[1]["error"]).startswith("ValidationError: 1 validation error(s)")


def test_renderer_failure_emits_a_fixed_line(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    def explode(*_args: object, **_kwargs: object) -> str:
        raise ValueError(f"cannot render password={SENTINEL} {SENTINEL}")

    monkeypatch.setattr(structlog.processors.JSONRenderer, "__call__", explode)
    _configure()
    get_logger("tests.leak").info("about_to_fail", password=SENTINEL)
    output = _all_output(capsys)
    _assert_no_sentinel(output)
    (line,) = _json_lines(output)
    assert line["event"] == "log_record_unrenderable"
    assert line["error_type"] == "ValueError"
    assert line["logger"] == "tests.leak"


def test_sanitiser_failure_replaces_the_event(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    def explode(*_args: object, **_kwargs: object) -> dict[str, object]:
        raise RecursionError(f"sanitiser broke on {SENTINEL}")

    monkeypatch.setattr(logging_module, "sanitize_event", explode)
    _configure()
    get_logger("tests.leak").info("about_to_fail", password=SENTINEL, request_id="req-1")
    output = _all_output(capsys)
    _assert_no_sentinel(output)
    (line,) = _json_lines(output)
    assert line["event"] == "log_event_redaction_failed"
    assert line["error_type"] == "RecursionError"
    assert line["request_id"] == "req-1"


def test_processor_failure_replaces_the_event(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    def explode(*_args: object, **_kwargs: object) -> object:
        raise RuntimeError(f"timestamper broke on {SENTINEL}")

    monkeypatch.setattr(structlog.processors.TimeStamper, "__call__", explode)
    _configure()
    get_logger("tests.leak").info("about_to_fail", password=SENTINEL)
    output = _all_output(capsys)
    _assert_no_sentinel(output)
    (line,) = _json_lines(output)
    assert line["event"] == "log_processing_failed"


def test_bad_stdlib_format_arguments_emit_a_fixed_line(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    _stdlib_bad_format_arguments(None)
    output = _all_output(capsys)
    _assert_no_sentinel(output)
    (line,) = _json_lines(output)
    assert line["event"] == "log_record_unrenderable"
    assert line["logger"] == "tests.stdlib"


class _BrokenStream:
    def write(self, _text: str) -> int:
        raise OSError(f"disk full while writing password={SENTINEL}")

    def flush(self) -> None:
        raise OSError(f"flush failed {SENTINEL}")


def test_emit_failure_writes_only_a_fixed_diagnostic_to_stderr(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    handler = logging.getLogger().handlers[0]
    assert isinstance(handler, logging.StreamHandler)
    handler.setStream(_BrokenStream())
    get_logger("tests.leak").error("lost", password=SENTINEL)
    logging.getLogger("tests.stdlib").error("lost %s", f"token={SENTINEL}")
    captured = capsys.readouterr()
    _assert_no_sentinel(captured.out + captured.err)
    assert captured.err.count("voice_agent.logging: a log record could not be written") == 2
    assert "Traceback" not in captured.err
    assert "error=OSError" in captured.err


def test_useful_context_is_preserved(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    get_logger("tests.context").info(
        "request_completed",
        request_id="0190a6b2-0000-7000-8000-000000000000",
        path="/health/ready",
        status=200,
        duration_ms=1.5,
        ready=True,
        nested={"tenant": "t-1", "items": [1, 2, 3], "check": {"postgres": "ok"}},
        note="token expired for https://example.com/docs/@team page",
        error_code="database_error",
        tags=("a", "b"),
    )
    (line,) = _json_lines(capsys.readouterr().out)
    assert line["request_id"] == "0190a6b2-0000-7000-8000-000000000000"
    assert line["path"] == "/health/ready"
    assert line["status"] == 200
    assert line["duration_ms"] == 1.5
    assert line["ready"] is True
    assert line["nested"] == {"tenant": "t-1", "items": [1, 2, 3], "check": {"postgres": "ok"}}
    assert line["note"] == "token expired for https://example.com/docs/@team page"
    assert line["error_code"] == "database_error"
    assert line["tags"] == ["a", "b"]


# ---------------------------------------------------------------- sanitiser units


@pytest.mark.parametrize(
    ("text", "kept"),
    [
        (f"Authorization: Bearer {SENTINEL}", "Authorization: "),
        (f"bearer {SENTINEL}", "bearer "),
        (f"password={SENTINEL}", "password="),
        (f"passwd={SENTINEL}", "passwd="),
        (f"secret={SENTINEL}", "secret="),
        (f"token={SENTINEL}", "token="),
        (f"api_key={SENTINEL}", "api_key="),
        (f"api-key: {SENTINEL}", "api-key: "),
        (f"X-Api-Key: {SENTINEL}", "X-Api-Key: "),
        (f'{{"client_secret": "{SENTINEL}"}}', '"client_secret": '),
        (f"host=db user=app password={SENTINEL} dbname=x", "dbname=x"),
        (f"https://h/cb?x=1&refresh_token={SENTINEL}&y=2", "&y=2"),
        (f"postgresql://u:{SENTINEL}@db:5432/x", "@db:5432/x"),
        (f"redis://:{SENTINEL}@cache:6379/0", "@cache:6379/0"),
        (f"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIx{SENTINEL}.sig", ""),
        (f"token {SENTINEL}", "token "),
    ],
    # Neutral ids: pytest would otherwise print the parameter, sentinel included.
    ids=[f"form-{index}" for index in range(16)],
)
def test_scrub_text_masks_credential_forms(text: str, kept: str) -> None:
    scrubbed = scrub_text(text)
    assert SENTINEL not in scrubbed
    assert kept in scrubbed


def test_scrub_text_handles_a_secret_cut_by_truncation() -> None:
    text = "x" * (MAX_STRING_LENGTH - 20) + f" redis://:{SENTINEL}@cache"
    scrubbed = scrub_text(text)
    assert SENTINEL not in scrubbed
    assert scrubbed == TRUNCATED_SENSITIVE


@pytest.mark.parametrize(
    "text",
    ["a." * (MAX_STRING_LENGTH // 2), "a:" * (MAX_STRING_LENGTH // 2), "x-" * MAX_STRING_LENGTH],
    ids=["dots", "colons", "dashes-beyond-limit"],
)
def test_scrub_text_stays_fast_on_pathological_input(text: str) -> None:
    started = time.monotonic()
    scrub_text(text)
    assert time.monotonic() - started < 1.0


def test_sanitize_returns_only_json_safe_copies() -> None:
    original: dict[str, object] = {"a": [1, {"b": (2, 3)}], "c": {4, 5}}
    result = sanitize(original)
    assert result == {"a": [1, {"b": [2, 3]}], "c": [4, 5]}
    assert result is not original
    json.dumps(result)


def test_render_exception_never_uses_raw_exception_text() -> None:
    try:
        _Probe.model_validate({"count": SENTINEL})
    except ValidationError as exc:
        rendered = render_exception(exc)
    assert SENTINEL not in rendered
    assert rendered.startswith("Traceback (most recent call last):")
