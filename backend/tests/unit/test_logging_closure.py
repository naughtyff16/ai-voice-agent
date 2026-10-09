"""The order of the logging pipeline: sanitise last, and sanitise complete values.

Independent review 6 found five defects (F1-F5 in the D0 findings register).
Four of them had one cause, security processing in the wrong order, and the
tests are grouped by the invariant each one broke:

* *Nothing is joined after the sanitiser* (F1). Fragments under ``exception``
  or ``stack`` were sanitised one by one and joined afterwards, which put a
  credential folded over two fragments back together.
* *A name gives a value no standing* (F2). A field a caller called
  ``_record`` or ``_from_structlog`` was passed through as processor metadata
  and reached other handlers unsanitised.
* *A signed URL is one capability* (F3). The signature was masked and the
  expiry, policy, key and scope parameters beside it were not.
* *Operational metadata is not payload* (F4). The event name and the request
  ID competed with arbitrary fields for the same 200 places, and lost.
* *Measure before converting* (F5). A ``str`` subclass and a ``Decimal`` were
  copied or converted whole in order to be found too large.

Every credential test requires zero occurrences of a generated sentinel on
stdout and on stderr separately.
"""

from __future__ import annotations

import contextvars
import json
import logging
import secrets
import sys
import tracemalloc
from collections.abc import Callable, Iterator
from decimal import Decimal
from typing import Any
from urllib.parse import parse_qsl, quote, urlsplit

import httpx
import pytest
import structlog
from fastapi import APIRouter

from tests.conftest import make_settings
from voice_agent.apps.api.main import create_app
from voice_agent.apps.api.middleware.correlation_id import REQUEST_ID_HEADER
from voice_agent.platform.infrastructure.observability import logging as logging_module
from voice_agent.platform.infrastructure.observability.logging import (
    MAX_RENDERED_EVENT_LENGTH,
    RESERVED,
    FailClosedStreamHandler,
    configure_logging,
    get_logger,
    redact_sensitive_fields,
)
from voice_agent.platform.infrastructure.observability.redaction import (
    CYCLE,
    MAX_EVENT_FIELDS,
    MAX_STRING_LENGTH,
    REDACTED,
    REPEATED,
    TRUNCATED,
    UNSUPPORTED,
    sanitize,
    sanitize_event,
    scrub_text,
    stack_text,
    traceback_text,
)
from voice_agent.platform.shared_kernel.request_context import (
    RequestContext,
    bind_request_context,
    reset_request_context,
)

pytestmark = pytest.mark.unit

FORMATS = ("json", "console")
ASSEMBLED_FIELDS = ("exception", "stack")


@pytest.fixture
def sentinel() -> str:
    """A fresh, distinctive value per test; it is a secret only by where it is put."""
    return "D0LEAKSENTINEL" + secrets.token_hex(12)


@pytest.fixture(autouse=True)
def _clean_context() -> Iterator[None]:
    structlog.contextvars.clear_contextvars()
    yield
    structlog.contextvars.clear_contextvars()


def _configure(log_format: str = "json") -> None:
    configure_logging(
        service_name="voice-agent-test", environment="test", log_level="INFO", log_format=log_format
    )


def _attach_independent_handler() -> None:
    """A plain standard-library handler on stderr, beside the handler of the pipeline."""
    logging.getLogger().addHandler(logging.StreamHandler(sys.stderr))


def _json_lines(output: str) -> list[dict[str, Any]]:
    return [json.loads(line) for line in output.splitlines() if line.strip()]


def _assert_absent(capsys: pytest.CaptureFixture[str], secret: str, what: str) -> tuple[str, str]:
    """stdout and stderr are checked separately; returns both."""
    captured = capsys.readouterr()
    assert captured.out.count(secret) == 0, f"{what}: on stdout"
    assert captured.err.count(secret) == 0, f"{what}: on stderr"
    return captured.out, captured.err


def _peak_while(action: Callable[[], object]) -> int:
    tracemalloc.start()
    try:
        action()
        return tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()


def _in_a_context_of_its_own(scenario: Callable[[], None], bound: dict[str, Any]) -> None:
    """Run ``scenario`` so that the context variables it binds do not outlive it."""
    try:
        contextvars.copy_context().run(scenario)
    finally:
        registry = getattr(structlog.contextvars, "_CONTEXT_VARS", {})
        for name in bound:
            registry.pop(f"structlog_{name}", None)


def _logging(log: Any, field: str, value: object) -> Callable[[], object]:
    return lambda: log.info("probe", **{field: value})


def _through_every_structlog_channel(field: str, value: object) -> int:
    """Log ``value`` under ``field`` directly, through a bound logger and through the context."""
    log = get_logger("tests.closure")
    log.info("direct", **{field: value})
    log.bind(**{field: value}).info("bound")
    structlog.contextvars.bind_contextvars(**{field: value})
    try:
        log.info("context")
        logging.getLogger("tests.closure.stdlib").warning("context of a standard-library record")
    finally:
        structlog.contextvars.unbind_contextvars(field)
    return 4


# ---------------------------------------------------------------- F1: nothing is joined later


def _folded_credentials(secret: str) -> dict[str, object]:
    """Fragments that are harmless one by one and a credential when joined."""
    return {
        "folded-cookie": ["Cookie: session=[REDACTED]", " " + secret],
        "folded-digest": ['Authorization: Digest username="app",', f' response="{secret}"'],
        "multiline-postgresql-uri": ["postgresql://app:first", f"{secret}@db.internal:5432/app"],
        "masked-prefix-secret-suffix": ["password=[REDACTED]", secret],
        "nested-lists": [["Cookie: session=[REDACTED]"], [[" " + secret]]],
        "tuple-of-fragments": ("Cookie: session=[REDACTED]", " " + secret),
    }


@pytest.mark.parametrize("form", sorted(_folded_credentials("")))
@pytest.mark.parametrize("field", ASSEMBLED_FIELDS)
@pytest.mark.parametrize("log_format", FORMATS)
def test_fragments_of_a_credential_are_not_reunited_after_sanitising(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, field: str, form: str
) -> None:
    _configure(log_format)
    fragments = _folded_credentials(sentinel)[form]
    lines = _through_every_structlog_channel(field, fragments)
    stdlib = logging.getLogger("tests.closure.stdlib")
    stdlib.error("failed: %s", fragments)
    stdlib.error("failed", extra={field: fragments})
    out, _ = _assert_absent(capsys, sentinel, f"{form} under {field}")
    assert len(_events(out, log_format)) == lines + 2


def _events(output: str, log_format: str) -> list[str]:
    """The lines that start an event (a console traceback continues on further lines)."""
    if log_format == "json":
        return [line for line in output.splitlines() if line.startswith("{")]
    return [line for line in output.splitlines() if line[:4].isdigit() and "[" in line]


@pytest.mark.parametrize("field", ASSEMBLED_FIELDS)
def test_fragments_are_assembled_before_the_sanitiser_reads_them(sentinel: str, field: str) -> None:
    for form, fragments in _folded_credentials(sentinel).items():
        event = redact_sensitive_fields(None, "info", {"event": "probe", field: fragments})
        # One text, sanitised as one text: no list is left for a later stage to join.
        assert type(event[field]) is str, form
        assert sentinel not in json.dumps(event), form
        assert redact_sensitive_fields(None, "info", dict(event)) == event, form


def test_no_stage_follows_the_final_sanitiser_except_the_renderer() -> None:
    for log_format in FORMATS:
        _configure(log_format)
        (handler,) = logging.getLogger().handlers
        formatter = handler.formatter
        assert isinstance(formatter, structlog.stdlib.ProcessorFormatter)
        *_, sanitiser, renderer = formatter.processors
        assert sanitiser is redact_sensitive_fields
        assert isinstance(
            renderer, structlog.processors.JSONRenderer | structlog.dev.ConsoleRenderer
        )


def test_an_ordinary_list_of_traceback_lines_keeps_its_layout(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    lines = [
        "Traceback (most recent call last):",
        '  File "/srv/app/handlers.py", line 42, in create_call',
        "ValueError: unsupported codec 'g729'",
    ]
    get_logger("tests.closure").error("call_failed", exception=lines, stack=[lines[:2]])
    (event,) = _json_lines(capsys.readouterr().out)
    assert event["exception"] == "\n".join(lines)
    assert event["stack"] == "\n".join(lines[:2])


def _raise_chain(inner: str, outer: str) -> BaseException:
    try:
        try:
            raise ValueError(inner)
        except ValueError as exc:
            raise ConnectionError(outer) from exc
    except ConnectionError as exc:
        return exc


@pytest.mark.parametrize("log_format", FORMATS)
def test_an_application_traceback_stays_useful(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    log = get_logger("tests.closure")
    stdlib = logging.getLogger("tests.closure.stdlib")
    try:
        raise _raise_chain(f"bad option password={sentinel}", "could not reach the database")
    except ConnectionError:
        log.exception("structlog_failure")
        stdlib.exception("stdlib failure")
        log.error("with_stack", stack_info=True)
    out, _ = _assert_absent(capsys, sentinel, "traceback")
    # Frames, exception types, the chain and the credential-free message all remain.
    assert out.count("Traceback (most recent call last):") == 4
    assert out.count("direct cause of the following exception") == 2
    assert out.count("in _raise_chain") == 4
    assert out.count("test_logging_closure.py") >= 6
    assert out.count("ConnectionError: could not reach the database") == 2
    assert out.count(f"ValueError: bad option password={REDACTED}") == 2
    assert "Stack (most recent call last):" in out
    assert "in test_an_application_traceback_stays_useful" in out


def _exception_from(filename: str, name: str, message: str) -> BaseException:
    code = compile(f"raise RuntimeError({message!r})", "placeholder.py", "exec")
    code = code.replace(co_filename=filename, co_name=name)
    try:
        exec(code, {})  # noqa: S102 — a synthetic frame for the traceback under test
    except RuntimeError as exc:
        return exc
    raise AssertionError("the synthetic code did not raise")


def test_a_constructed_traceback_is_a_text_the_sanitiser_emits_unchanged(sentinel: str) -> None:
    url = f"https://api.example/v1/calls?token={sentinel}"
    exceptions = {
        "plain": _exception_from("/srv/app.py", "handler", "ordinary failure"),
        "credential": _exception_from("/srv/app.py", "handler", f"password={sentinel}"),
        "credential-in-chain": _raise_chain(f"password={sentinel}", "outer"),
        "masked-to-the-end": _raise_chain(f"GET {url} failed", "outer"),
        "multi-line message": _raise_chain(f"first line\nCookie: a={sentinel}\nlast", "outer"),
        # Reads as the start of a credential only when another line follows it.
        "frame named bearer": _raise_chain("inner", "outer").with_traceback(
            _exception_from("/srv/auth.py", "bearer", "x").__traceback__
        ),
        "group": ExceptionGroup("several", [ValueError(f"secret={sentinel}"), KeyError("k")]),
    }
    for name, exc in exceptions.items():
        text = traceback_text(exc)
        assert sentinel not in text, name
        assert scrub_text(text) == text, name
        assert sanitize_event({"exception": text}, assembled=frozenset({"exception"})) == {
            "exception": text
        }, name
        # The type of every exception survives whatever happened to its message.
        assert text.splitlines()[-1].startswith(type(exc).__name__ + ":"), name
        assert text != REDACTED, name
    assert "ValueError: [REDACTED]" in traceback_text(exceptions["masked-to-the-end"])
    assert 'File "/srv/auth.py"' not in traceback_text(exceptions["frame named bearer"])
    stack = stack_text(sys._getframe())
    assert scrub_text(stack) == stack
    assert "in test_a_constructed_traceback_is_a_text_the_sanitiser_emits_unchanged" in stack


@pytest.mark.parametrize("log_format", FORMATS)
def test_empty_and_malformed_fragments_cost_a_bounded_amount(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    looped: list[object] = ["Cookie: session=[REDACTED]"]
    looped.append(looped)
    deep: object = " " + sentinel
    for _ in range(64):
        deep = [deep]
    malformed: dict[str, object] = {
        "empty-list": [],
        "empty-strings": ["", "", "\n"],
        "not-text": [None, 5, 1.5, b"bytes", {"password": sentinel}, object()],
        "mapping": {"password": sentinel},
        "number": 5,
        "self-referential": looped,
        "deeper-than-any-limit": ["Cookie: session=[REDACTED]", deep],
        "many-fragments": ["Cookie: a=[REDACTED]", *[" " + sentinel] * 100_000],
        "many-empty-lists": [[[] for _ in range(200)] for _ in range(200)],
        "huge-fragment": ["password=[REDACTED]", sentinel * 400_000],
    }
    log = get_logger("tests.closure")
    for name, value in malformed.items():
        for field in ASSEMBLED_FIELDS:
            peak = _peak_while(_logging(log, field, value))
            assert peak < 1_000_000, (name, field, peak)
    out, _ = _assert_absent(capsys, sentinel, "malformed fragments")
    events = _events(out, log_format)
    assert len(events) == 2 * len(malformed)
    assert all("probe" in line for line in events)
    assert redact_sensitive_fields(None, "info", {"exception": [None, 5]})["exception"] == (
        f"{UNSUPPORTED}\n{UNSUPPORTED}"
    )


# ---------------------------------------------------------------- F2: reserved names


RESERVED_NAMES = ("_record", "_from_structlog")


class _Impostor:
    """What a caller might put under ``_record`` to pass for a log record."""

    def __init__(self, secret: str) -> None:
        self.name = f"password={secret}"
        self.levelname = secret
        self.msg = secret

    def __repr__(self) -> str:
        return f"<record password={self.name}>"


def _names_field(output: str, name: str) -> bool:
    return any(form in output for form in (f'"{name}"', f"'{name}'", f"{name}="))


def _reserved_values(secret: str) -> dict[str, object]:
    return {
        "text": f"password={secret}",
        "bare": secret,
        "impostor": _Impostor(secret),
        "mapping": {"detail": secret},
    }


@pytest.mark.parametrize("name", RESERVED_NAMES)
@pytest.mark.parametrize("log_format", FORMATS)
def test_a_caller_field_with_a_reserved_name_reaches_no_handler(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, name: str
) -> None:
    _configure(log_format)
    _attach_independent_handler()
    lines = 0
    for value in _reserved_values(sentinel).values():
        lines += _through_every_structlog_channel(name, value)
    out, err = _assert_absent(capsys, sentinel, name)
    # Both handlers received every event; neither received the field.
    assert len(_events(out, log_format)) == lines
    assert len(err.splitlines()) == lines
    assert not _names_field(out + err, name)
    # The removal is said, in fixed words, in every event of the pipeline. (The
    # independent handler prints a standard-library record as its caller made it.)
    structlog_events = 3 * len(_reserved_values(sentinel))
    assert out.count(RESERVED) == lines and err.count(RESERVED) == structlog_events
    assert "tests.closure" in out and "untrusted_logger" not in out


def test_processor_metadata_is_not_read_from_the_fields_of_a_caller(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    get_logger("tests.closure").info("probe", _record=_Impostor(sentinel), _from_structlog=False)
    (event,) = _json_lines(_assert_absent(capsys, sentinel, "impostor")[0])
    # structlog's own add_logger_name would have taken the name from the impostor.
    assert event["logger"] == "tests.closure"
    assert event["level"] == "info"
    assert event[RESERVED] == "reserved field names removed"
    assert not set(RESERVED_NAMES) & set(event)
    # The final pass passes nothing through under those names either.
    final = redact_sensitive_fields(
        None, "info", {"event": "probe", "_record": f"password={sentinel}", "_from_structlog": 1}
    )
    assert final == {"event": "probe"}


class _BrokenStream:
    def write(self, _text: str) -> int:
        raise OSError("disk full")

    def flush(self) -> None:
        raise OSError("flush failed")


def _fail_in_processor(monkeypatch: pytest.MonkeyPatch, secret: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> object:
        raise RuntimeError(f"timestamper broke on password={secret}")

    monkeypatch.setattr(structlog.processors.TimeStamper, "__call__", explode)


def _fail_in_sanitiser(monkeypatch: pytest.MonkeyPatch, secret: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> object:
        raise RecursionError(f"sanitiser broke on password={secret}")

    monkeypatch.setattr(logging_module, "sanitize_event", explode)


def _fail_in_formatter(monkeypatch: pytest.MonkeyPatch, secret: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> str:
        raise ValueError(f"cannot render password={secret}")

    monkeypatch.setattr(structlog.processors.JSONRenderer, "__call__", explode)
    monkeypatch.setattr(structlog.dev.ConsoleRenderer, "__call__", explode)


def _fail_in_writer(_monkeypatch: pytest.MonkeyPatch, _secret: str) -> None:
    handler = logging.getLogger().handlers[0]
    assert isinstance(handler, FailClosedStreamHandler)
    handler.setStream(_BrokenStream())  # type: ignore[arg-type]


_FAILURES: dict[str, tuple[Callable[[pytest.MonkeyPatch, str], None], str]] = {
    "processor": (_fail_in_processor, "log_processing_failed"),
    "sanitiser": (_fail_in_sanitiser, "log_event_redaction_failed"),
    "formatter": (_fail_in_formatter, "log_record_unrenderable"),
    "writer": (_fail_in_writer, "a log record could not be written"),
}


@pytest.mark.parametrize("failure", sorted(_FAILURES))
@pytest.mark.parametrize("log_format", FORMATS)
def test_a_reserved_name_reaches_no_handler_when_the_pipeline_fails(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    log_format: str,
    failure: str,
) -> None:
    _configure(log_format)
    _attach_independent_handler()
    install, expected = _FAILURES[failure]
    install(monkeypatch, sentinel)
    lines = 0
    for name in RESERVED_NAMES:
        lines += _through_every_structlog_channel(name, f"password={sentinel}")
    out, err = _assert_absent(capsys, sentinel, f"{failure} failure")
    assert (out + err).count(expected) >= lines
    assert not any(_names_field(out + err, name) for name in RESERVED_NAMES)


@pytest.mark.parametrize("log_format", FORMATS)
def test_genuine_processor_metadata_still_works(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    # A caller's field of the same name, bound to the context, changes nothing.
    structlog.contextvars.bind_contextvars(_record=_Impostor(sentinel))
    stdlib = logging.getLogger("tests.closure.genuine")
    stdlib.warning("stdlib %s", "message")
    try:
        raise LookupError("nothing found")
    except LookupError:
        stdlib.exception("stdlib failure")
    get_logger("tests.closure.structured").warning("structlog_message")
    out, _ = _assert_absent(capsys, sentinel, "genuine metadata")
    if log_format == "json":
        first, second, third = _json_lines(out)
        # The name and level of a standard-library record come from the record.
        assert (first["logger"], first["level"]) == ("tests.closure.genuine", "warning")
        assert first["event"] == "stdlib message"
        assert (second["logger"], second["level"]) == ("tests.closure.genuine", "error")
        assert second["exception"].endswith("LookupError: nothing found")
        assert third["logger"] == "tests.closure.structured"
        assert all(not set(RESERVED_NAMES) & set(event) for event in (first, second, third))
    else:
        assert "stdlib message" in out and "[tests.closure.genuine]" in out
        assert "LookupError: nothing found" in out


# ---------------------------------------------------------------- F3: signed URLs


def _signed_urls(secret: str) -> dict[str, str]:
    """One signed URL per provider form. Every parameter value carries the sentinel."""

    def url(base: str, parameters: str) -> str:
        query = "&".join(
            f"{key}={secret}{index}" for index, key in enumerate(parameters.split(), start=1)
        )
        return f"{base}/media-{secret}.wav?{query}"

    aws = "https://bucket.s3.eu-west-1.amazonaws.com"
    google = "https://storage.googleapis.com/bucket"
    oss = "https://bucket.oss-eu-central-1.aliyuncs.com"
    return {
        "cloudfront-canned": url("https://d111.cloudfront.net", "Expires Signature Key-Pair-Id"),
        "cloudfront-custom": url("https://d111.cloudfront.net", "Policy Signature Key-Pair-Id"),
        "azure-sas": url(
            "https://account.blob.core.windows.net/recordings", "sv st se sr sp spr sig"
        ),
        "aws-sigv4": url(
            aws,
            "X-Amz-Algorithm X-Amz-Credential X-Amz-Date X-Amz-Expires X-Amz-SignedHeaders"
            " X-Amz-Security-Token X-Amz-Signature",
        ),
        "aws-sigv2": url(aws, "AWSAccessKeyId Expires Signature"),
        "google-v4": url(
            google,
            "X-Goog-Algorithm X-Goog-Credential X-Goog-Date X-Goog-Expires X-Goog-SignedHeaders"
            " X-Goog-Signature",
        ),
        "google-v2": url(google, "GoogleAccessId Expires Signature"),
        "alibaba-oss-v1": url(oss, "OSSAccessKeyId Expires Signature security-token"),
        "alibaba-oss-v4": url(
            oss,
            "x-oss-signature-version x-oss-credential x-oss-date x-oss-expires x-oss-signature",
        ),
        "tencent-cos": url(
            "https://bucket-1250000000.cos.ap-guangzhou.myqcloud.com",
            "q-sign-algorithm q-ak q-sign-time q-key-time q-signature",
        ),
    }


def _url_variants(url: str) -> dict[str, str]:
    """The same signed URL as different software would write it."""
    parts = urlsplit(url)
    parameters = parse_qsl(parts.query, keep_blank_values=True)
    base = f"{parts.scheme}://{parts.netloc}{parts.path}"

    def rebuilt(pairs: list[tuple[str, str]]) -> str:
        return base + "?" + "&".join(f"{key}={value}" for key, value in pairs)

    return {
        "as-issued": url,
        "mixed-case-keys": rebuilt([(key.swapcase(), value) for key, value in parameters]),
        "percent-encoded-keys": rebuilt(
            [(f"%{ord(key[0]):02X}{quote(key[1:])}", value) for key, value in parameters]
        ),
        "reversed-order": rebuilt(parameters[::-1]),
        "innocent-parameters": rebuilt([("part", "1"), *parameters, ("lang", "en")]),
        "in-a-fragment": url.replace("?", "#", 1),
    }


@pytest.mark.parametrize("provider", sorted(_signed_urls("")))
@pytest.mark.parametrize("log_format", FORMATS)
def test_a_signed_url_leaves_no_query_material_in_any_log(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, provider: str
) -> None:
    _configure(log_format)
    log = get_logger("tests.closure")
    stdlib = logging.getLogger("tests.closure.stdlib")
    variants = _url_variants(_signed_urls(sentinel)[provider])
    for url in variants.values():
        log.info("fetch_failed", detail=url)
        log.info("fetch_failed", response={"items": [{"note": f"see {url} for the file"}]})
        log.info(f"fetch of {url} failed with 403")
        log.bind(detail=url).warning("bound")
        stdlib.warning("fetch of %s failed", url)
        try:
            raise RuntimeError(f"GET {url} returned 403")
        except RuntimeError as exc:
            log.exception("fetch_failed", error=exc)
            stdlib.exception("fetch failed")
    out, _ = _assert_absent(capsys, sentinel, provider)
    assert len(_events(out, log_format)) == 7 * len(variants)
    # No part of the URL remains: not its host, and not a parameter without its value.
    assert urlsplit(variants["as-issued"]).netloc not in out
    assert "fetch_failed" in out and "returned 403" in out


def test_a_signed_url_is_replaced_whole_and_its_surroundings_kept(sentinel: str) -> None:
    for provider, url in _signed_urls(sentinel).items():
        for variant, written in _url_variants(url).items():
            assert scrub_text(written) == REDACTED, (provider, variant)
            # Recognised by the URL rule itself, which keeps the text around it,
            # not only by a later layer that masks the whole string.
            line = f"GET {written}&lang=en returned 403"
            assert scrub_text(line) == f"GET {REDACTED} returned 403", (provider, variant)
            assert sanitize({"a": {"b": [written]}}) == {"a": {"b": [REDACTED]}}, (
                provider,
                variant,
            )
        # After a parameter that is itself a credential, the rest of the text goes too.
        assert scrub_text(f"GET {url} returned 403").startswith(f"GET {REDACTED}"), provider
        assert scrub_text(f"GET {url}&lang=en returned 403") == f"GET {REDACTED} returned 403"
        assert scrub_text(f'{{"detail": "{url}"}}') == f'{{"detail": "{REDACTED}"}}', provider
    review = (
        "https://cdn.example/recording.wav?Expires=4102444800"
        f"&Signature={sentinel}&Key-Pair-Id=QUERY_SCOPE_SENTINEL"
    )
    assert scrub_text(review) == REDACTED
    sas = f"https://a.blob.core.windows.net/c/r.wav?sv=2022-11-02&se=2030-01-01&sp=r&sig={sentinel}"
    assert scrub_text(sas) == REDACTED
    # A signed URL beside an ordinary one: only the signed one is a capability.
    assert scrub_text(f"see https://example.org/help?topic=1 and {review}") == (
        f"see https://example.org/help?topic=1 and {REDACTED}"
    )
    # Written without a scheme, as a request line or an access log shows it.
    for provider, url in _signed_urls(sentinel).items():
        parts = urlsplit(url)
        request_line = f'"GET {parts.path}?{parts.query}&lang=en HTTP/1.1" 403'
        assert scrub_text(request_line) == f'"GET {REDACTED} HTTP/1.1" 403', provider
        assert scrub_text(f"{parts.netloc}{parts.path}?{parts.query}") == REDACTED, provider
    assert scrub_text('"GET /v1/calls?limit=5&cursor=abc HTTP/1.1" 200') == (
        '"GET /v1/calls?limit=5&cursor=abc HTTP/1.1" 200'
    )
    # A signed URL as the value of a parameter of another URL.
    assert sentinel not in scrub_text(f"https://example.org/open?next={sas}")
    assert "sv=" not in scrub_text(f"https://example.org/open?next={sas}")


_ORDINARY_URLS = (
    "https://example.org/docs/page?page=2&sort=asc#section-4",
    "https://api.example/v1/calls?limit=50&cursor=abc123",
    "https://cdn.example/recording.wav?v=3",
    "http://127.0.0.1:8000/health/ready",
    "postgresql://db.internal:5432/app?sslmode=require",
    # Expiry or version parameters without a signature sign nothing.
    "https://example.org/offer?expires=2030-01-01&policy=standard",
    "https://example.org/list?sv=2&se=3&sp=4&sr=b",
    "https://example.org/design?style=cursive&signed=false&expires=never",
)


@pytest.mark.parametrize("log_format", FORMATS)
def test_ordinary_urls_are_logged_as_they_are(
    capsys: pytest.CaptureFixture[str], log_format: str
) -> None:
    _configure(log_format)
    log = get_logger("tests.closure")
    for url in _ORDINARY_URLS:
        assert scrub_text(url) == url
        assert scrub_text(f"GET {url} returned 404") == f"GET {url} returned 404"
        log.info("fetched", detail=url, nested={"links": [url]})
        logging.getLogger("tests.closure.stdlib").warning("fetched %s", url)
    out = capsys.readouterr().out
    assert REDACTED not in out
    assert all(out.count(url) == 3 for url in _ORDINARY_URLS)


# ---------------------------------------------------------------- F4: operational metadata

FIELD_COUNTS = (198, 199, 200, 201, 1_000)


def _fields(count: int, secret: str) -> dict[str, object]:
    fields: dict[str, object] = {f"field_{index}": index for index in range(count)}
    # Credentials among the fields, inside and outside what is admitted.
    fields["field_7"] = f"password={secret}"
    fields[f"field_{count - 1}"] = f"Cookie: session={secret}"
    return fields


def _parsed(line: str, log_format: str) -> dict[str, Any]:
    """The fields of one rendered event (for the console renderer, its key=value pairs)."""
    if log_format == "json":
        parsed: dict[str, Any] = json.loads(line)
        return parsed
    head, *pairs = line.split(" field_")
    fields: dict[str, Any] = {f"field_{pair.split('=', 1)[0]}": pair for pair in pairs}
    for key in ("request_id", "service", "environment", TRUNCATED):
        if f" {key}=" in line:
            fields[key] = line.split(f" {key}=", 1)[1].split(" ", 1)[0].strip("'")
    fields["event"] = head.split("] ", 1)[1].split(" ", 1)[0]
    return fields


@pytest.mark.parametrize("count", FIELD_COUNTS)
@pytest.mark.parametrize("channel", ["direct", "bound", "context"])
@pytest.mark.parametrize("log_format", FORMATS)
def test_event_name_and_request_id_survive_any_number_of_fields(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, channel: str, count: int
) -> None:
    _configure(log_format)
    fields = _fields(count, sentinel)
    log = get_logger("tests.closure")

    def scenario() -> None:
        structlog.contextvars.bind_contextvars(request_id="review-request")
        if channel == "direct":
            log.info("large_event", **fields)
        elif channel == "bound":
            log.bind(**fields).info("large_event")
        else:
            structlog.contextvars.bind_contextvars(**fields)
            log.info("large_event")

    _in_a_context_of_its_own(scenario, fields)
    out, _ = _assert_absent(capsys, sentinel, f"{count} fields")
    (line,) = out.splitlines()
    assert len(line) < MAX_RENDERED_EVENT_LENGTH
    event = _parsed(line, log_format)
    assert event["event"] == "large_event"
    assert event["request_id"] == "review-request"
    assert event["service"] == "voice-agent-test" and event["environment"] == "test"
    admitted = [key for key in event if key.startswith("field_")]
    assert len(admitted) == min(count, MAX_EVENT_FIELDS)
    # Arbitrary fields are what is cut, and a fixed marker says so.
    assert (TRUNCATED in event) == (count > MAX_EVENT_FIELDS)
    if log_format == "json" and count > MAX_EVENT_FIELDS:
        assert event[TRUNCATED] == "event field limit reached"


def test_an_event_that_exhausts_the_budget_keeps_its_name_and_traceback(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    fields = {f"field_{index}": f"{index} " + "x" * 2_000 for index in range(MAX_EVENT_FIELDS)}
    try:
        raise LookupError(f"missing password={sentinel}")
    except LookupError:
        get_logger("tests.closure").exception("budget_exhausted", **fields)
    (event,) = _json_lines(_assert_absent(capsys, sentinel, "budget")[0])
    assert event["event"] == "budget_exhausted"
    assert event["exception"].endswith(f"LookupError: missing password={REDACTED}")
    assert (
        "in test_an_event_that_exhausts_the_budget_keeps_its_name_and_traceback"
        in (event["exception"])
    )
    assert TRUNCATED in json.dumps(event)


def test_operational_metadata_is_not_taken_from_the_fields_of_a_call(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    forged = {
        "level": "critical",
        "logger": "forged.logger",
        "service": "forged-service",
        "environment": "production",
        "timestamp": "1999-01-01T00:00:00Z",
    }
    log = get_logger("tests.closure")
    log.info("forged_identity", **forged)
    log.bind(**forged).info("forged_identity")
    structlog.contextvars.bind_contextvars(**forged)
    log.info("forged_identity")
    logging.getLogger("tests.closure.stdlib").warning("forged identity")
    events = _json_lines(capsys.readouterr().out)
    assert len(events) == 4
    for event in events:
        assert event["service"] == "voice-agent-test"
        assert event["environment"] == "test"
        assert event["level"] in ("info", "warning")
        assert event["logger"].startswith("tests.closure")
        assert not event["timestamp"].startswith("1999")


def test_a_request_id_cannot_be_renamed_by_a_field(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    log = get_logger("tests.closure")
    stdlib = logging.getLogger("tests.closure.stdlib")

    # 1. No request in progress: a field is all there is, and it is validated.
    log.info("job", request_id="job-17")
    log.info("job", request_id="not a request id")

    # 2. A request ID bound to the context outranks a field of the call.
    structlog.contextvars.bind_contextvars(request_id="context-id")
    log.info("in_context", request_id="forged-id")
    log.bind(request_id="forged-id").info("in_context")

    # 3. The request context the server set outranks both.
    token = bind_request_context(RequestContext(request_id="server-id"))
    try:
        structlog.contextvars.bind_contextvars(request_id="forged-context-id")
        log.info("in_request", request_id="forged-id")
        log.bind(request_id="forged-id").info("in_request")
        stdlib.warning("in request", extra={"request_id": "forged-id"})
    finally:
        reset_request_context(token)
    identifiers = [event["request_id"] for event in _json_lines(capsys.readouterr().out)]
    assert identifiers == [
        "job-17",
        "untrusted_request_id",
        "context-id",
        "context-id",
        "server-id",
        "server-id",
        "server-id",
    ]


def test_the_bound_request_id_is_found_among_any_number_of_context_variables(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    fields = {f"ctx_{index}": index for index in range(5_000)}

    def scenario() -> None:
        structlog.contextvars.bind_contextvars(request_id="review-request", **fields)
        get_logger("tests.closure").info("crowded_context")

    _in_a_context_of_its_own(scenario, fields)
    (event,) = _json_lines(capsys.readouterr().out)
    assert event["request_id"] == "review-request"
    assert event["event"] == "crowded_context"
    assert event[TRUNCATED] == "event field limit reached"


@pytest.mark.parametrize("count", FIELD_COUNTS)
@pytest.mark.parametrize("log_format", FORMATS)
async def test_a_request_keeps_its_server_generated_request_id_in_the_log(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str, count: int
) -> None:
    app = create_app(
        make_settings(
            database_url=f"postgresql+asyncpg://app_api:{sentinel}@127.0.0.1:9/voice_agent_test_unit",
            redis_url=f"redis://:{sentinel}@127.0.0.1:9/0",
            observability={"log_format": log_format},
        )
    )
    probe = APIRouter()

    @probe.get("/__probe/large-event")
    async def large_event() -> dict[str, bool]:
        get_logger("tests.closure.http").info(
            "large_event", request_id="forged-by-the-handler", **_fields(count, sentinel)
        )
        return {"logged": True}

    app.include_router(probe)
    capsys.readouterr()
    transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get(
            "/__probe/large-event", headers={REQUEST_ID_HEADER: "forged-by-the-client"}
        )
    assert response.status_code == 200
    request_id = response.headers[REQUEST_ID_HEADER]
    assert request_id not in ("forged-by-the-client", "forged-by-the-handler")
    out, _ = _assert_absent(capsys, sentinel, "request")
    (line,) = [line for line in out.splitlines() if "large_event" in line]
    event = _parsed(line, log_format)
    assert event["event"] == "large_event"
    assert event["request_id"] == request_id
    assert len([key for key in event if key.startswith("field_")]) == min(count, MAX_EVENT_FIELDS)
    assert "forged-by" not in out


# ---------------------------------------------------------------- F5: measure before converting

TEN_MILLION = 10_000_000


class _Text(str):
    """A ``str`` subclass whose every conversion claims to be something else."""

    __slots__ = ()
    conversions = 0

    def _converted(self, *_args: object) -> Any:
        type(self).conversions += 1
        raise AssertionError("a conversion method of the subclass was called")

    __str__ = __repr__ = __len__ = __getitem__ = __iter__ = __format__ = _converted


class _Number(int):
    __slots__ = ()
    conversions = 0

    def _converted(self, *_args: object) -> Any:
        type(self).conversions += 1
        raise AssertionError("a conversion method of the subclass was called")

    __str__ = __repr__ = __int__ = __index__ = __format__ = _converted


def _oversized_scalars() -> dict[str, tuple[object, str]]:
    """Scalars of about ten megabytes, allocated here: before any measurement begins."""
    text = "a" * TEN_MILLION
    return {
        "exact-string": (text, TRUNCATED),
        "string-subclass": (_Text(text), TRUNCATED),
        "decimal": (Decimal("9" * TEN_MILLION), "<Decimal: too long>"),
        "integer": (1 << (8 * TEN_MILLION), f"<int: {8 * TEN_MILLION + 1} bits>"),
        "integer-subclass": (_Number(1 << (8 * TEN_MILLION)), f"<int: {8 * TEN_MILLION + 1} bits>"),
    }


# What logging itself may allocate for one such event: far below the megabytes
# that copying or converting the value costs, far above an ordinary event.
LOGGING_OWNED_LIMIT = 200_000


@pytest.mark.parametrize("scalar", sorted(_oversized_scalars()))
def test_an_oversized_scalar_is_refused_before_it_is_copied_or_converted(
    capsys: pytest.CaptureFixture[str], scalar: str
) -> None:
    value, marker = _oversized_scalars()[scalar]
    _configure()
    log = get_logger("tests.closure")
    stdlib = logging.getLogger("tests.closure.stdlib")
    log.info("warm-up", detail="ordinary")
    stdlib.warning("warm-up %s", "ordinary")
    capsys.readouterr()
    actions: dict[str, Callable[[], object]] = {
        "sanitize": lambda: sanitize({"detail": value}),
        "field": lambda: log.info("probe", detail=value),
        "nested": lambda: log.info("probe", detail={"items": [value]}),
        "bound": lambda: log.bind(detail=value).info("probe"),
        "argument": lambda: stdlib.warning("probe %s", value),
        "fragment": lambda: log.info("probe", exception=["line", value]),
    }
    if issubclass(type(value), str):
        actions["event"] = lambda: log.info(value)  # type: ignore[arg-type]
        actions["key"] = lambda: sanitize({value: "x"})
        actions["message"] = lambda: stdlib.warning(value)
        actions["template"] = lambda: stdlib.warning(value, "argument")
    for name, action in actions.items():
        peak = _peak_while(action)
        assert peak < LOGGING_OWNED_LIMIT, (scalar, name, peak)
    assert sanitize({"detail": value}) == {"detail": marker}
    out = capsys.readouterr().out
    assert len(out) < 16 * LOGGING_OWNED_LIMIT
    assert all(len(line) < MAX_STRING_LENGTH for line in out.splitlines())
    assert _Text.conversions == 0 and _Number.conversions == 0


def test_ordinary_decimals_are_still_logged(capsys: pytest.CaptureFixture[str]) -> None:
    values = {
        "12.50": "12.50",
        "-0.001": "-0.001",
        "1E+5": "1E+5",
        "NaN": "NaN",
        "9" * 40: "9" * 40,
        # The digit limit still decides for a value that is small enough to be read.
        "9" * 41: "<Decimal: too long>",
        "9" * 400: "<Decimal: too long>",
    }
    assert sanitize([Decimal(text) for text in values]) == list(values.values())
    _configure()
    get_logger("tests.closure").info("priced", amount=Decimal("12.50"))
    (event,) = _json_lines(capsys.readouterr().out)
    assert event["amount"] == "12.50"


def test_a_subclass_is_read_through_the_base_type_and_then_sanitised(sentinel: str) -> None:
    class Quiet(str):
        __slots__ = ()

        def __str__(self) -> str:
            return "harmless"

        def __len__(self) -> int:
            return 0

    class Priced(Decimal):
        def __str__(self) -> str:
            return sentinel

    assert sanitize(Quiet(f"password={sentinel}")) == f"password={REDACTED}"
    assert sanitize({Quiet("password"): sentinel}) == {"password": REDACTED}
    assert sanitize(Priced("1.5")) == UNSUPPORTED
    assert sanitize(_Number(7)) == 7
    # A reserved name written as a subclass is the same name.
    event = redact_sensitive_fields(None, "info", {Quiet("_record"): sentinel, "event": "probe"})
    assert event == {"event": "probe"}


def test_the_other_limits_of_an_event_are_unchanged(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    shared = [f"password={sentinel}", "shared"]
    looped: dict[str, object] = {"name": "loop"}
    looped["self"] = looped

    def recurse(depth: int) -> None:
        if depth == 0:
            raise RuntimeError(f"deep failure token={sentinel}")
        recurse(depth - 1)

    _configure()
    log = get_logger("tests.closure")
    try:
        recurse(500)
    except RuntimeError:
        log.exception(
            "limits",
            first=shared,
            second=shared,
            cycle=looped,
            many=list(range(5_000)),
            long="word " * 10_000,
            big=10**60,
            **{f"extra_{index}": index for index in range(1_000)},
        )
    (line,) = _assert_absent(capsys, sentinel, "limits")[0].splitlines()
    assert len(line) < MAX_RENDERED_EVENT_LENGTH
    event = json.loads(line)
    assert event["event"] == "limits"
    assert event["first"] == [f"password={REDACTED}", "shared"] and event["second"] == REPEATED
    assert event["cycle"] == {"name": "loop", "self": CYCLE}
    assert len(event["many"]) == 201 and str(event["many"][-1]).startswith(TRUNCATED)
    assert event["long"].endswith(TRUNCATED) and len(event["long"]) <= MAX_STRING_LENGTH + 16
    assert event["big"] == "<int: 200 bits>"
    assert event[TRUNCATED] == "event field limit reached"
    traceback = event["exception"]
    assert len(traceback) <= MAX_STRING_LENGTH and traceback.count("in recurse") == 32
    assert traceback.endswith(f"RuntimeError: deep failure token={REDACTED}")
