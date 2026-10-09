"""No trusted text, constructed tracebacks, capability fields, early admission.

Independent review 5 (D0-P0-01, D0-P1-09, D0-M-04). Each finding had an
architectural cause, and the tests are grouped by cause rather than by input:

* *Provenance by type.* The sanitiser skipped strings of a private ``str``
  subclass, and handed instances of it to callers. A class is not a
  provenance guarantee; there is now no value the sanitiser does not scrub.
* *Formatting before validation.* Tracebacks were formatted by the standard
  library and cleaned line by line, so a filename spanning lines lost its
  credential context. Tracebacks are now constructed from validated frame
  metadata, one unit per frame.
* *Classification by content.* A signed media URL is a bearer capability
  with no recognisable word in it. It is now classified by the field that
  carries it.
* *Work before admission.* Context variables, record attributes and
  filenames were copied or formatted before any limit applied.

Every test requires zero occurrences of a generated sentinel on stdout and on
stderr separately.
"""

from __future__ import annotations

import contextvars
import json
import logging
import secrets
import tracemalloc
import types
from collections.abc import Callable, Iterator
from typing import Any

import pytest
import structlog

from voice_agent.platform.infrastructure.observability import logging as logging_module
from voice_agent.platform.infrastructure.observability import redaction
from voice_agent.platform.infrastructure.observability.logging import (
    MAX_CONTEXT_VARIABLES,
    MAX_RENDERED_EVENT_LENGTH,
    configure_logging,
    get_logger,
    merge_bounded_contextvars,
    redact_sensitive_fields,
)
from voice_agent.platform.infrastructure.observability.redaction import (
    MAX_EVENT_FIELDS,
    MAX_ITEMS,
    REDACTED,
    TRUNCATED,
    render_exception,
    sanitize,
    sanitize_event,
    scrub_text,
    stack_lines,
    traceback_lines,
)

pytestmark = pytest.mark.unit

FORMATS = ("json", "console")
CAPABILITY_HOST = "https://storage.example/private/"


@pytest.fixture
def sentinel() -> str:
    """A fresh, distinctive value per test; it is a secret only by where it is put."""
    return "D0LEAKSENTINEL" + secrets.token_hex(12)


def _configure(log_format: str = "json") -> None:
    configure_logging(
        service_name="voice-agent-test", environment="test", log_level="INFO", log_format=log_format
    )


def _json_lines(output: str) -> list[dict[str, Any]]:
    return [json.loads(line) for line in output.splitlines() if line.strip()]


def _assert_absent(capsys: pytest.CaptureFixture[str], secret: str, what: str) -> str:
    """stdout and stderr are checked separately; returns everything written."""
    captured = capsys.readouterr()
    assert captured.out.count(secret) == 0, f"{what}: on stdout"
    assert captured.err.count(secret) == 0, f"{what}: on stderr"
    return captured.out + captured.err


def _peak_while(action: Callable[[], object]) -> int:
    tracemalloc.start()
    try:
        action()
        return tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()


class _BrokenStream:
    def write(self, _text: str) -> int:
        raise OSError("disk full")

    def flush(self) -> None:
        raise OSError("flush failed")


# ---------------------------------------------------------------- no trusted text


class _Loud(str):
    """A ``str`` subclass that claims whatever it can about itself."""

    __slots__ = ()

    def __str__(self) -> str:
        return "harmless"

    def __repr__(self) -> str:
        return "'harmless'"


def _forgeries(text: str) -> Iterator[tuple[str, str]]:
    """``text`` as every type a caller could hope the sanitiser believes."""
    yield "type of render_exception()", type(render_exception(ValueError("ordinary")))(text)
    yield "type of a traceback unit", type(traceback_lines(ValueError("ordinary"))[0])(text)
    sanitised: Any = sanitize_event({"a": "b"})["a"]
    yield "type of a sanitised value", type(sanitised)(text)
    yield "type of scrub_text()", type(scrub_text("ordinary"))(text)
    yield "str subclass", _Loud(text)
    for name, value in vars(redaction).items():
        if isinstance(value, type) and issubclass(value, str) and value is not str:
            forged: str = value(text)
            yield f"redaction.{name}", forged


def test_the_reviewer_reproduction_of_the_forged_trusted_type() -> None:
    secret = "SYNTHETIC_SECRET"  # noqa: S105 — the reviewer's literal reproduction
    trusted_type = type(render_exception(ValueError("ordinary")))
    forged = trusted_type("password=" + secret)
    result = sanitize_event({"detail": forged})
    assert secret not in str(result)
    assert result == {"detail": f"password={REDACTED}"}


def test_the_module_defines_no_string_type_and_returns_only_built_in_strings() -> None:
    defined = [
        name
        for name, value in vars(redaction).items()
        if isinstance(value, type) and issubclass(value, str) and value is not str
    ]
    assert defined == []
    try:
        raise ValueError("ordinary")
    except ValueError as exc:
        assert type(render_exception(exc)) is str
        assert all(type(unit) is str for unit in traceback_lines(exc))
        event = sanitize_event({"error": exc, "text": _Loud("x"), "items": [_Loud("y")]})
    assert type(event["error"]) is str and type(event["text"]) is str
    assert [type(item) for item in event["items"]] == [str]  # type: ignore[attr-defined]


def test_a_forged_string_is_scrubbed_wherever_it_is_placed(sentinel: str) -> None:
    for name, forged in _forgeries(f"password={sentinel}"):
        placements: dict[str, object] = {
            "field": {"detail": forged},
            "nested": {"outer": {"inner": [{"detail": forged}]}},
            "list": {"items": [forged, (forged,)]},
            "exception-field": {"exception": forged},
            "exception-units": {"exception": [forged], "stack": [forged]},
            "key": {forged: "value"},
        }
        for where, event in placements.items():
            once = sanitize_event(event)  # type: ignore[arg-type]
            twice = sanitize_event(once)
            for result in (once, twice, sanitize(event)):
                assert sentinel not in json.dumps(result), f"{name} as {where}"


def test_the_second_pass_scrubs_what_the_first_pass_returned_and_what_was_added(
    sentinel: str,
) -> None:
    first = redact_sensitive_fields(None, "info", {"event": "probe", "note": "ordinary"})
    # Whatever a processor between the two passes puts into the event, of any type.
    for name, forged in _forgeries(f"password={sentinel}"):
        first[f"added_{len(first)}"] = forged
        first["exception"] = [forged]
        second = redact_sensitive_fields(None, "info", first)
        assert sentinel not in json.dumps(second), name
        # Review 6 (F1): fragments under a traceback field are assembled into the
        # text they will be laid out as before they are sanitised, never after.
        assert second["exception"] == f"password={REDACTED}"
    assert second["note"] == "ordinary"


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_forged_string_is_scrubbed_through_every_logging_channel(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    log = get_logger("tests.trust")
    stdlib = logging.getLogger("tests.trust.stdlib")
    count = 0
    for _, forged in _forgeries(f"password={sentinel}"):
        log.info("probe", detail=forged, nested={"deep": [forged]})
        log.info(forged)
        log.info("positional %s", forged)
        log.info("probe", exception=forged)
        log.info("probe", exception=[forged, forged], stack=[forged])
        log.bind(bound=forged).warning("probe")
        stdlib.warning("positional %s and %s", forged, [forged])
        stdlib.warning("keyed %(detail)s", {"detail": forged})
        stdlib.warning(forged)
        stdlib.warning(forged, "argument")
        count += 10
    output = _assert_absent(capsys, sentinel, "forged text")
    assert len(output.splitlines()) >= count
    assert REDACTED in output


# ---------------------------------------------------------------- constructed tracebacks


def _raise_in(filename: object, name: object = "handler") -> BaseException:
    """An exception raised from code whose filename and function name are as given."""
    code = compile('raise ValueError("ordinary")', "placeholder.py", "exec")
    code = code.replace(co_filename=filename, co_name=name)  # type: ignore[arg-type]
    try:
        exec(code, {})  # noqa: S102 — a synthetic frame for the traceback under test
    except ValueError as exc:
        return exc
    raise AssertionError("the synthetic code did not raise")


def _hostile_filenames(secret: str) -> dict[str, str]:
    long = 1_000_000
    return {
        "multiline-uri": "postgresql://h/db?password=[REDACTED]\n" + secret,
        "multiline-uri-crlf": "postgresql://h/db?sslmode=require&password=\r\n" + secret,
        "uri-with-tab": f"postgresql://h/db?password=a\t{secret}",
        "folded-header": f"Authorization: Basic\n {secret}",
        "folded-header-crlf": f"X-Note: a\r\n\tCookie: session={secret}",
        "key-then-newline": "password=\n" + secret,
        "single-line-uri": f"redis://cache/0?password={secret}",
        "pair": f"/srv/app.py password={secret}",
        "bearer": f"/srv/Bearer {secret}",
        "closes-the-quote": f'x.py", line 1, in f\npassword="{secret}',
        "line-separator": f"password=\u2028{secret}",
        "nul": f"password=\x00{secret}",
        "long": "x" * long + f" password={secret}",
        "long-secret-first": f"password={secret} " + "x" * long,
        "long-multiline": f"password=\n{secret}\n" * (long // 64),
    }


class _Filename(str):
    """A filename whose own length and text claim to be harmless."""

    __slots__ = ()

    def __len__(self) -> int:
        return 4

    def __str__(self) -> str:
        return "x.py"


def test_the_reviewer_reproduction_of_the_multi_line_filename() -> None:
    secret = "SYNTHETIC_SECRET"  # noqa: S105 — the reviewer's literal reproduction
    filename = "postgresql://h/db?password=[REDACTED]\n" + secret
    try:
        exec(compile('raise ValueError("ordinary")', filename, "exec"))  # noqa: S102
    except ValueError as exc:
        result = render_exception(exc)
        units = traceback_lines(exc)
    assert secret not in result
    assert '  File "<unsafe filename>", line 1, in <module>' in units
    assert units[-1] == "ValueError: ordinary"


def test_no_part_of_an_unsafe_filename_is_rendered(sentinel: str) -> None:
    for name, filename in _hostile_filenames(sentinel).items():
        for candidate in (filename, _Filename(filename)):
            exc = _raise_in(candidate)
            units = traceback_lines(exc)
            rendered = render_exception(exc)
            assert sentinel not in rendered and sentinel not in "".join(units), name
            # The frame is still there, with a fixed word for its filename.
            expected = "<filename too long>" if len(filename) > 512 else "<unsafe filename>"
            assert f'  File "{expected}", line 1, in handler' in units, name
            assert rendered.endswith("ValueError: ordinary\n")
            assert len(rendered) < 1_024


def test_a_hostile_function_name_or_frame_field_is_replaced(sentinel: str) -> None:
    for name in (f"password={sentinel}", f"x\npassword={sentinel}", "a" * 1_000_000, ""):
        units = traceback_lines(_raise_in("module.py", name))
        assert '  File "module.py", line 1, in <unknown>' in units
        assert sentinel not in "".join(units)
    forged = types.TracebackType(None, _raise_in("module.py").__traceback__.tb_frame, 0, -7)  # type: ignore[union-attr]
    exc = ValueError("ordinary").with_traceback(forged)
    (frame,) = traceback_lines(exc)[1:-1]
    assert frame.endswith(", line ?, in _raise_in")


def test_every_unit_of_a_traceback_is_unchanged_by_a_later_pass(sentinel: str) -> None:
    exceptions = [_raise_in(filename) for filename in _hostile_filenames(sentinel).values()]
    exceptions.append(_raise_in("D:\\projects\\@scope\\x64\\server.py", "serve"))
    exceptions.append(_raise_in("/srv/app/voice_agent/api.py", "<lambda>"))
    # Unchanged on their own, but a credential key once they stand in a frame line.
    exceptions += [_raise_in(name) for name in ("password=", "/srv/password=", "Authorization:")]
    try:
        raise ConnectionError(f"cannot reach db password={sentinel}") from exceptions[0]
    except ConnectionError as chained:
        exceptions.append(chained)
    for exc in exceptions:
        units = traceback_lines(exc)
        assert all(scrub_text(unit) == unit for unit in units)
        assert sanitize(units) == units
        assert sanitize_event({"exception": units})["exception"] == units
        assert sentinel not in "".join(units)


def test_an_ordinary_traceback_keeps_its_frames_and_shows_no_source_lines() -> None:
    def fails() -> None:
        raise RuntimeError("bottom of the stack")  # marker-source-line

    try:
        fails()
    except RuntimeError as exc:
        units = traceback_lines(exc)
        rendered = render_exception(exc)
    assert units[0] == "Traceback (most recent call last):"
    assert units[-1] == "RuntimeError: bottom of the stack"
    frames = units[1:-1]
    assert len(frames) == 2
    assert all(__file__ in frame for frame in frames)
    assert frames[-1].endswith(", in fails")
    assert "marker-source-line" not in rendered and "raise RuntimeError" not in rendered
    assert rendered == "\n".join(units) + "\n"


def _log_hostile_chain(log: Any, filename: str) -> None:
    try:
        try:
            raise _raise_in(filename)
        except ValueError as inner:
            raise ConnectionError("outer failure") from inner
    except ConnectionError:
        log.exception("probe")


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_hostile_filename_leaks_through_no_logger_and_no_renderer(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    filenames = _hostile_filenames(sentinel)
    for filename in filenames.values():
        _log_hostile_chain(get_logger("tests.trust"), filename)
        _log_hostile_chain(logging.getLogger("tests.trust.stdlib"), filename)
    output = _assert_absent(capsys, sentinel, "traceback filename")
    # Every event still carries both exceptions of the chain and the safe frames.
    assert output.count("ConnectionError: outer failure") == 2 * len(filenames)
    assert output.count("ValueError: ordinary") == 2 * len(filenames)
    assert output.count("direct cause of the following exception") == 2 * len(filenames)
    assert output.count("in _log_hostile_chain") >= 2 * len(filenames)
    assert "<unsafe filename>" in output and "<filename too long>" in output
    assert "log_record_oversized" not in output and "log_processing_failed" not in output


def test_a_traceback_is_rendered_as_text_in_the_standard_layout(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    _log_hostile_chain(get_logger("tests.trust"), f"/srv/app.py?password={sentinel}")
    (line,) = _json_lines(_assert_absent(capsys, sentinel, "traceback"))
    exception = line["exception"]
    assert type(exception) is str
    units = exception.split("\n")
    assert units[0] == "Traceback (most recent call last):"
    assert '  File "<unsafe filename>", line 1, in handler' in units
    assert units[-1] == "ConnectionError: outer failure"
    middle = units.index("The above exception was the direct cause of the following exception:")
    assert units[middle - 1] == units[middle + 1] == ""
    assert units[middle - 2] == "ValueError: ordinary"


@pytest.mark.parametrize("log_format", FORMATS)
def test_the_emergency_paths_show_nothing_of_a_hostile_traceback(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    stdlib = logging.getLogger("tests.trust.stdlib")
    for filename in _hostile_filenames(sentinel).values():
        try:
            raise _raise_in(filename, f"password={sentinel}")
        except ValueError:
            # An unbounded format string: the record is replaced by a fixed line.
            stdlib.exception("%10000000s", f"password={sentinel}")
    output = _assert_absent(capsys, sentinel, "unsafe-format path")
    assert output.count("log_record_unsafe_format") == len(_hostile_filenames(sentinel))

    handler = logging.getLogger().handlers[0]
    assert isinstance(handler, logging.StreamHandler)
    handler.setStream(_BrokenStream())
    for filename in _hostile_filenames(sentinel).values():
        _log_hostile_chain(get_logger("tests.trust"), filename)
        _log_hostile_chain(stdlib, filename)
    captured = capsys.readouterr()
    assert captured.out.count(sentinel) == 0 and captured.err.count(sentinel) == 0
    assert captured.out == ""
    assert captured.err.count("a log record could not be written") == 2 * len(
        _hostile_filenames(sentinel)
    )
    assert "Traceback" not in captured.err and "File" not in captured.err


def test_a_long_exception_chain_stays_within_the_traceback_limits(sentinel: str) -> None:
    def recurse(depth: int, text: str) -> None:
        if depth == 0:
            raise RuntimeError(text)
        recurse(depth - 1, text)

    error: BaseException | None = None
    for index in range(40):
        try:
            try:
                recurse(60, f"failure {index} " + "y" * 4_000 + f" password={sentinel}")
            except RuntimeError as raised:
                raise raised from error
        except RuntimeError as raised:
            error = raised
    assert error is not None
    units = traceback_lines(error)
    assert sentinel not in "".join(units)
    assert len(units) < MAX_ITEMS
    assert sum(map(len, units)) + len(units) <= 32_768 + len(TRUNCATED) + 1
    # The oldest exceptions are the ones left out; the one raised is complete.
    assert units[0] == TRUNCATED
    assert units[-1].startswith("RuntimeError: failure 39 ")
    assert sum(unit.endswith(", in recurse") for unit in units) <= 32 * 10
    assert sanitize_event({"exception": units})["exception"] == units


def test_a_stack_is_built_like_a_traceback(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    def from_hostile_code() -> list[str]:
        namespace: dict[str, Any] = {"stack_lines": stack_lines}
        code = compile("import sys\nresult = stack_lines(sys._getframe())", "x.py", "exec")
        exec(code.replace(co_filename=f"/srv/app?password=\n{sentinel}"), namespace)  # noqa: S102
        return list(namespace["result"])

    units = from_hostile_code()
    assert units[0].startswith("Stack (most recent call last):")
    assert units[-1] == '  File "<unsafe filename>", line 2, in <module>'
    assert units[-2].endswith(", in from_hostile_code")
    assert sentinel not in "".join(units) and len(units) <= 33

    _configure()
    get_logger("tests.trust").info("probe", stack_info=True)
    logging.getLogger("tests.trust.stdlib").warning("probe", stack_info=True)
    lines = _json_lines(_assert_absent(capsys, sentinel, "stack"))
    for line in lines:
        stack = line["stack"].split("\n")
        assert stack[0].startswith("Stack (most recent call last):")
        assert stack[-1].endswith(", in test_a_stack_is_built_like_a_traceback")
        # No source line and no frame of the logging machinery.
        assert all(unit.startswith("  File ") for unit in stack[1:])
        assert "stack_info=True" not in line["stack"]
        assert "structlog" not in line["stack"]


# ---------------------------------------------------------------- capability fields

_CAPABILITY_FIELDS = (
    "download_url",
    "upload_url",
    "presigned_url",
    "signed_url",
    "recording_url",
    "media_url",
    "playback_url",
    "pre_signed_url",
    "presigned_post",
    "sas_url",
    "storage_url",
    "blob_uri",
    "object_url",
    "file_url",
    "attachment_link",
    "result_ref",
    # Mixed case and the spellings of other producers.
    "Download_URL",
    "UPLOAD_URL",
    "downloadUrl",
    "uploadURL",
    "presignedUrl",
    "PreSignedUrl",
    "signedUrl",
    "RecordingUrl",
    "MediaUrl0",
    "recording-url",
    "x-upload-url",
    "export_download_url",
)
# Ordinary references that are not handed out as capabilities.
_ORDINARY_FIELDS = (
    "url",
    "target_url",
    "base_url",
    "logo_url",
    "redirect_uri",
    "documentation_url",
    "profile_url",
    "assigned_to",
    "is_signed",
)


def _capability(secret: str) -> str:
    # Nothing in it says "signature" or "token": it is a capability by its use.
    return f"{CAPABILITY_HOST}{secret}"


def test_the_reviewer_reproduction_of_the_signed_media_fields() -> None:
    capability = "https://storage.example/private/opaque-capability"
    for field in ("download_url", "upload_url", "presigned_url"):
        result = sanitize_event({field: capability})
        assert capability not in str(result)
        assert result == {field: REDACTED}


@pytest.mark.parametrize("field", _CAPABILITY_FIELDS)
def test_a_capability_field_is_masked_whatever_its_value_looks_like(
    field: str, sentinel: str
) -> None:
    values: list[object] = [
        _capability(sentinel),
        f"/relative/{sentinel}",
        sentinel,
        [_capability(sentinel)],
        {"href": _capability(sentinel), "expires_in": 300},
    ]
    for value in values:
        placements: list[object] = [
            {field: value},
            {"data": {"recording": {field: value}}},
            {"items": [{"id": 1, field: value}]},
            {"body": json.dumps({"data": {field: value}})},
            {"body": json.dumps({"wrapped": json.dumps({field: value})})},
        ]
        for event in placements:
            for result in (sanitize(event), sanitize_event(event)):  # type: ignore[arg-type]
                assert sentinel not in json.dumps(result), (field, value)
    assert sanitize({field: _capability(sentinel)}) == {field: REDACTED}
    assert redaction.is_sensitive_key(field)


@pytest.mark.parametrize("field", ["download_url", "upload_url", "presignedUrl", "RecordingUrl"])
def test_a_capability_named_in_text_is_masked(field: str, sentinel: str) -> None:
    capability = _capability(sentinel)
    for text in (
        f"{field}={capability}",
        f"{field}: {capability}",
        f'{field}="{capability}"',
        f"created export {field}={capability} expires_in=300",
        f"{{'{field}': '{capability}'}}",
        f"response was {json.dumps({field: capability})}",
        f"GET /callback?{field}={capability}&state=ok",
    ):
        assert sentinel not in scrub_text(text), text
        assert sentinel not in redaction.describe_exception(RuntimeError(text)), text


def test_a_url_with_provider_signing_parameters_is_masked_whole(sentinel: str) -> None:
    url = (
        f"https://bucket.s3.amazonaws.com/rec.wav?X-Amz-Algorithm=AWS4-HMAC-SHA256"
        f"&X-Amz-Credential={sentinel}a&X-Amz-Expires=300&X-Amz-Signature={sentinel}b"
        f"&X-Goog-Signature={sentinel}c&sig={sentinel}d&se=2026&part=1"
    )
    scrubbed = scrub_text(f"fetching {url}")
    # Review 6 (F3): this test used to require "&se=2026&part=1" to survive
    # beside the masked signature. Expiry and scope belong to the capability.
    assert scrubbed == f"fetching {REDACTED}"


def test_ordinary_reference_fields_are_not_capabilities() -> None:
    event = {field: "https://example.org/page" for field in _ORDINARY_FIELDS}
    assert sanitize(event) == event
    assert not any(redaction.is_sensitive_key(field) for field in _ORDINARY_FIELDS)


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_capability_field_leaks_through_no_logger_and_no_renderer(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    log = get_logger("tests.trust")
    stdlib = logging.getLogger("tests.trust.stdlib")
    capability = _capability(sentinel)
    for field in _CAPABILITY_FIELDS:
        log.info("recording_ready", **{field: capability})
        log.info("response", body={"data": {field: capability, "expires_in": 300}})
        log.bind(**{field: capability}).info("bound")
        log.info(f"{field}={capability}")
        stdlib.warning("%s=%s", field, capability)
        stdlib.warning(f"{field}=%s", capability)
        stdlib.warning("response %s", {"data": {field: capability}})
        stdlib.warning("response %(body)s", {"body": {field: capability}})
        stdlib.warning("ready", extra={field: capability})
        try:
            raise RuntimeError(f"upload failed {field}={capability}")
        except RuntimeError as exc:
            log.exception("failed", error=exc)
            stdlib.exception("failed")
    structlog.contextvars.bind_contextvars(download_url=capability)
    try:
        log.info("from_context")
    finally:
        structlog.contextvars.unbind_contextvars("download_url")
    output = _assert_absent(capsys, sentinel, "capability field")
    assert CAPABILITY_HOST not in output
    assert len(output.splitlines()) >= 11 * len(_CAPABILITY_FIELDS) + 1
    assert "from_context" in output and f"download_url={REDACTED}" in output.replace('": "', "=")


# ---------------------------------------------------------------- admission: context


class _CountingContext:
    """Stands in for a ``contextvars.Context``; counts variables seen and values fetched."""

    def __init__(self, names: list[str]) -> None:
        self._variables = [contextvars.ContextVar[object](name) for name in names]
        self.visited = 0
        self.fetched = 0

    def __len__(self) -> int:
        return len(self._variables)

    def __iter__(self) -> Iterator[contextvars.ContextVar[object]]:
        for variable in self._variables:
            self.visited += 1
            yield variable

    def __getitem__(self, variable: contextvars.ContextVar[object]) -> object:
        self.fetched += 1
        return f"value of {variable.name}"


@pytest.mark.parametrize("prefix", ["structlog_", "other_library_"])
def test_context_fields_beyond_the_limit_are_never_visited(
    monkeypatch: pytest.MonkeyPatch, prefix: str
) -> None:
    context = _CountingContext([f"{prefix}field_{index}" for index in range(100_000)])
    monkeypatch.setattr(contextvars, "copy_context", lambda: context)
    event = merge_bounded_contextvars(None, "info", {"event": "probe"})
    if prefix == "structlog_":
        # One value per admitted field, and one more to learn that a field really
        # is left out (a variable that was unbound again is not one). The event
        # name takes none of the places (review 6, F4).
        assert context.fetched == MAX_EVENT_FIELDS + 1
        assert context.visited == MAX_EVENT_FIELDS + 1
        assert len(event) == MAX_EVENT_FIELDS + 2
    else:
        # Variables of other libraries: looked at up to the limit, never fetched.
        assert context.fetched == 0
        assert context.visited == MAX_CONTEXT_VARIABLES + 1
        assert len(event) == 2
    assert event[TRUNCATED] == "event field limit reached"
    assert event["event"] == "probe"


def test_context_fields_never_replace_the_fields_of_the_call(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = _CountingContext(["structlog_request_id", "structlog_event", "structlog_extra"])
    monkeypatch.setattr(contextvars, "copy_context", lambda: context)
    event = merge_bounded_contextvars(None, "info", {"event": "probe"})
    assert event == {
        "event": "probe",
        "request_id": "value of structlog_request_id",
        "extra": "value of structlog_extra",
    }
    assert context.fetched == 2


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_hundred_thousand_real_context_fields_cost_a_bounded_amount(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    fields = {f"ctx_{index}": index for index in range(100_000)}
    fields["password"] = sentinel  # type: ignore[assignment]
    fields["download_url"] = _capability(sentinel)  # type: ignore[assignment]
    peaks: list[int] = []

    def scenario() -> None:
        structlog.contextvars.bind_contextvars(**fields)
        log = get_logger("tests.trust")
        stdlib = logging.getLogger("tests.trust.stdlib")
        log.info("warm-up")
        peaks.append(_peak_while(lambda: log.info("probe", request_id="req-1")))
        peaks.append(_peak_while(lambda: stdlib.warning("probe %s", "argument")))

    try:
        contextvars.copy_context().run(scenario)
    finally:
        registry = getattr(structlog.contextvars, "_CONTEXT_VARS", {})
        for name in fields:
            registry.pop(f"structlog_{name}", None)
    output = _assert_absent(capsys, sentinel, "context fields")
    lines = output.splitlines()
    assert len(lines) == 3
    assert all(len(line) < MAX_RENDERED_EVENT_LENGTH for line in lines)
    assert all("event field limit reached" in line for line in lines)
    if log_format == "json":
        assert all(len(line) <= MAX_EVENT_FIELDS + 8 for line in _json_lines(output))
    # Fetching 100,000 values into an event dict alone is several megabytes.
    assert max(peaks) < 512_000, peaks


# ---------------------------------------------------------------- admission: records


def _record_with_extras(count: int, secret: str) -> logging.LogRecord:
    record = logging.LogRecord(
        "tests.trust.stdlib", logging.WARNING, __file__, 1, "probe %s", ("argument",), None
    )
    record.__dict__.update({f"extra_{index}": f"{secret}-{index}" for index in range(count)})
    record.__dict__["password"] = secret
    return record


class _CountingAttributes(dict[str, Any]):
    """A record ``__dict__`` that counts every traversal and copy of itself."""

    traversals = 0

    def __iter__(self) -> Iterator[str]:
        type(self).traversals += 1
        return super().__iter__()

    def keys(self) -> Any:
        type(self).traversals += 1
        return super().keys()

    def items(self) -> Any:
        type(self).traversals += 1
        return super().items()

    def values(self) -> Any:
        type(self).traversals += 1
        return super().values()

    def copy(self) -> dict[str, Any]:
        type(self).traversals += 1
        return super().copy()


@pytest.mark.parametrize("log_format", FORMATS)
@pytest.mark.parametrize("message", ["probe %s", "plain message", {"a": "mapping"}])
def test_a_record_with_a_hundred_thousand_attributes_is_not_copied(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, message: object
) -> None:
    _configure(log_format)
    handler = logging.getLogger().handlers[0]
    record = _record_with_extras(100_000, sentinel)
    record.msg = message
    record.args = ("argument",) if message == "probe %s" else ()
    handler.handle(record)  # warm-up: caches, lazily created objects
    capsys.readouterr()

    small = _peak_while(lambda: handler.handle(_record_with_extras(0, sentinel)))
    peak = _peak_while(lambda: handler.handle(record))
    # A shallow copy of the attributes is over 5 MB; the bounded copy is constant.
    assert peak < small + 64_000, (peak, small)

    # No stage iterates, copies or lists the attributes; only fixed names are looked up.
    counted = _CountingAttributes(record.__dict__)
    _CountingAttributes.traversals = 0
    copy = logging_module._with_sanitized_arguments(record)
    assert copy is not record and len(copy.__dict__) < 32
    record.__dict__ = counted
    handler.handle(record)
    assert _CountingAttributes.traversals == 0

    output = _assert_absent(capsys, sentinel, "record attributes")
    lines = output.splitlines()
    assert len(lines) == 3
    assert all("extra_" not in line and len(line) < 1_024 for line in lines)


def test_a_structlog_record_is_also_formatted_from_a_bounded_copy(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    handler = logging.getLogger().handlers[0]
    peaks: list[int] = []
    sizes: list[int] = []
    original = handler.format

    def measure(record: logging.LogRecord) -> str:
        # A record made by structlog, to which something has attached attributes.
        assert hasattr(record, "_logger") and type(record.msg) is dict
        record.__dict__.update({f"extra_{index}": sentinel for index in range(100_000)})
        sizes.append(len(logging_module._bounded_copy(record).__dict__))
        rendered: list[str] = []
        peaks.append(_peak_while(lambda: rendered.append(original(record))))
        return rendered[0]

    with pytest.MonkeyPatch.context() as patch:
        patch.setattr(handler, "format", measure)
        get_logger("tests.trust").info("warm-up")
        get_logger("tests.trust").info("probe", field="value")
    (_, line) = _json_lines(_assert_absent(capsys, sentinel, "structlog record"))
    assert line["event"] == "probe" and line["field"] == "value"
    # structlog's formatter copies the record it is given: it is given the bounded one.
    assert peaks[1] < 128_000, peaks
    assert all(size < 32 for size in sizes)


# ---------------------------------------------------------------- admission: filenames


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_million_character_filename_is_never_formatted(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    filename = f"postgresql://h/db?password={sentinel}\n" + "x" * 1_000_000 + f"\n{sentinel}"
    exc = _raise_in(filename)
    log = get_logger("tests.trust")
    stdlib = logging.getLogger("tests.trust.stdlib")

    def log_both() -> None:
        try:
            raise exc
        except ValueError:
            log.exception("probe")
            stdlib.exception("probe %s", "argument")

    log_both()  # warm-up
    capsys.readouterr()
    ordinary = _raise_in("module.py")
    peaks = {
        "traceback_lines": _peak_while(lambda: traceback_lines(exc)),
        "render_exception": _peak_while(lambda: render_exception(exc)),
        "describe": _peak_while(lambda: sanitize_event({"error": exc, "exception": exc})),
        "loggers": _peak_while(log_both),
    }
    baseline = _peak_while(lambda: traceback_lines(ordinary))
    # One copy of the filename is 1 MB (4 MB as wide text); nothing proportional is made.
    assert peaks["traceback_lines"] < baseline + 16_000, (peaks, baseline)
    assert max(peaks.values()) < 256_000, peaks

    units = traceback_lines(exc)
    assert '  File "<filename too long>", line 1, in handler' in units
    assert sum(map(len, units)) < 512
    output = _assert_absent(capsys, sentinel, "long filename")
    assert len(output) < 8_192
    assert output.count("<filename too long>") == 2


def test_work_limits_are_reached_without_showing_what_was_left_out(sentinel: str) -> None:
    # Every limit of the traceback builder at once: a chain longer than is
    # followed, frames deeper than are kept, filenames longer than are read
    # and messages longer than are shown, each carrying the sentinel.
    def recurse(code: types.CodeType, depth: int) -> None:
        if depth == 0:
            exec(code, {})  # noqa: S102 — a synthetic frame for the traceback under test
        recurse(code, depth - 1)

    error: BaseException | None = None
    for index in range(16):
        filename = f"password={sentinel}\n" + "x" * (10_000 * (index % 3))
        code = compile(f"raise ValueError('token={sentinel} ' + 'z' * 20000)", "x.py", "exec")
        try:
            try:
                recurse(code.replace(co_filename=filename), 80)
            except ValueError as raised:
                raise raised from error
        except ValueError as raised:
            error = raised
    assert error is not None
    units = traceback_lines(error)
    rendered = render_exception(error)
    assert sentinel not in rendered
    assert len(units) < MAX_ITEMS and len(rendered) < 40_000
    assert TRUNCATED in rendered
    event = redact_sensitive_fields(None, "error", {"event": "probe", "exception": units})
    assert sentinel not in json.dumps(redact_sensitive_fields(None, "error", event))
