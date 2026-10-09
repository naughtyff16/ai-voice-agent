"""Escaped and encoded credential forms never cross the logging boundary (D0-P0-01).

The independent review showed secrets leaking when the same credential was
written in an escaped or encoded form: JSON values containing escaped quotes,
libpq values with escapes, percent-encoded query keys. Each form below is sent
through every logging channel of the real pipeline with a fresh sentinel, and
the sentinel must occur zero times in everything written to stdout and stderr.

The invariant is "the secret bytes never leave", not "the output contains
[REDACTED]". Separate tests check that surrounding, non-sensitive text survives.
"""

from __future__ import annotations

import json
import logging
import secrets
import time
from collections.abc import Callable, Iterator
from typing import Any

import pytest
import structlog
from pydantic import BaseModel, ValidationError

from voice_agent.platform.infrastructure.observability.logging import (
    configure_logging,
    get_logger,
)
from voice_agent.platform.infrastructure.observability.redaction import (
    CYCLE,
    MAX_DEPTH,
    REDACTED,
    TRUNCATED,
    UNREADABLE,
    sanitize,
    scrub_text,
)

pytestmark = pytest.mark.unit

SENSITIVE_QUERY_KEYS = (
    "password",
    "passwd",
    "secret",
    "token",
    "access_token",
    "refresh_token",
    "api_key",
    "apikey",
    "authorization",
)


@pytest.fixture
def sentinel() -> str:
    """A fresh, distinctive value per test; it is a secret only by where it is put."""
    return "D0LEAKSENTINEL" + secrets.token_hex(12)


def _configure(log_format: str = "json") -> None:
    configure_logging(
        service_name="voice-agent-test", environment="test", log_level="INFO", log_format=log_format
    )


def _percent(text: str) -> str:
    return "".join(f"%{ord(char):02X}" for char in text)


def _nested_json(payload: dict[str, object], levels: int) -> str:
    text = json.dumps(payload)
    for level in range(levels):
        text = json.dumps({f"layer_{level}": text})
    return text


Form = Callable[[str], str]

TEXT_FORMS: list[tuple[str, Form]] = [
    # --- JSON text
    ("json-password", lambda s: json.dumps({"password": s})),
    ("json-password-escaped-quote", lambda s: json.dumps({"password": 'prefix"' + s})),
    ("json-access-token-escaped-quote", lambda s: json.dumps({"access_token": 'prefix\\"' + s})),
    ("json-escaped-backslashes", lambda s: json.dumps({"secret": "a\\\\" + s + "\\"})),
    (
        "json-trailing-backslash-then-quote",
        lambda s: json.dumps({"password": "x\\", "n": s[:0]}) + json.dumps({"token": '\\"' + s}),
    ),
    ("json-unicode-escaped-key", lambda s: '{"p\\u0061ssword": "' + s + '"}'),
    ("json-unicode-escaped-value", lambda s: json.dumps({"password": "é\u2028" + s})),
    ("json-mixed-case-key", lambda s: json.dumps({"PassWord": s, "API_KEY": 'k"' + s})),
    (
        "json-nested-objects-and-arrays",
        lambda s: json.dumps({"a": [{"b": {"c": [{"client_secret": 'x"' + s}]}}]}),
    ),
    # Keys that only the structured policy treats as sensitive: parsed JSON gets
    # exactly the treatment of a mapping, not a text approximation of it.
    (
        "json-structured-policy-keys",
        lambda s: json.dumps({"database_dsn": f"x {s}", "phone_number": s, "Email": s}),
    ),
    ("json-array-root", lambda s: json.dumps([{"token": 'x"' + s}, "ok"])),
    ("json-compact", lambda s: json.dumps({"password": 'p"' + s}, separators=(",", ":"))),
    (
        "json-embedded-in-prose",
        lambda s: "upstream said " + json.dumps({"password": 'p"' + s}) + " and closed",
    ),
    (
        "json-two-fragments",
        lambda s: json.dumps({"ok": 1}) + " then " + json.dumps({"refresh_token": '"' + s}),
    ),
    ("json-inside-json-string", lambda s: _nested_json({"password": 'p"' + s}, 1)),
    ("json-nested-to-the-limit", lambda s: _nested_json({"password": 'p"' + s}, 3)),
    (
        "json-nested-beyond-the-limit",
        lambda s: _nested_json({"password": 'p"' + s}, 6),
    ),
    ("json-as-a-json-string", lambda s: json.dumps(json.dumps({"password": 'p"' + s}))),
    # --- malformed JSON carrying credential-like text
    ("malformed-json-truncated", lambda s: '{"password": "prefix\\"' + s + '", "user": '),
    ("malformed-json-unterminated-value", lambda s: '{"password":"abc' + s),
    ("malformed-json-unicode-key", lambda s: '{"p\\u0061ssword": "x\\"' + s),
    ("malformed-json-trailing-comma", lambda s: '{"access_token": "a\\"' + s + '",}'),
    ("escaped-json-text", lambda s: '{\\"password\\": \\"pre\\\\\\"' + s + '\\"}'),
    ("python-dict-repr", lambda s: repr({"password": "pre'fix\"" + s})),
    # --- URLs
    ("url-userinfo", lambda s: f"postgresql+asyncpg://app_api:{s}@db:5432/x"),
    ("url-userinfo-with-at", lambda s: f"rediss://default:p@{s}@cache:6380/0"),
    ("url-query-password", lambda s: f"https://api.example.test/cb?code=1&password={s}&x=2"),
    ("url-percent-encoded-password-key", lambda s: f"https://h.test/cb?%70assword={s}&x=1"),
    ("url-mixed-case-percent-key", lambda s: f"https://h.test/cb?%50%41ssWORD={s}&x=1"),
    ("url-lowercase-hex-key", lambda s: f"https://h.test/cb?api%5fkey={s}"),
    ("url-fully-encoded-key", lambda s: f"https://h.test/cb?{_percent('access_token')}={s}"),
    ("url-double-encoded-key", lambda s: f"https://h.test/cb?%2570assword={s}"),
    ("url-encoded-separator", lambda s: f"https://h.test/cb?next=%2Fx%3Fpassword%3D{s}"),
    ("url-encoded-key-and-separator", lambda s: f"https://h.test/cb?n=%74oken%3D{s}"),
    (
        "url-duplicate-sensitive-parameters",
        lambda s: f"https://h.test/cb?password={s}a&password={s}b&%74oken={s}c",
    ),
    ("url-query-value-with-quote", lambda s: f'https://h.test/cb?token=ab"{s}&x=1'),
    ("query-only", lambda s: f"password={s}&%73ecret={s}"),
    # --- libpq / DSN text
    ("libpq-unquoted", lambda s: f"host=db user=app password={s} dbname=x"),
    ("libpq-single-quoted", lambda s: f"host=db password='pre fix {s}' dbname=x"),
    ("libpq-double-quoted", lambda s: f'host=db password="pre fix {s}" dbname=x'),
    ("libpq-escaped-quote", lambda s: f"host=db password='pre\\'fix {s}' dbname=x"),
    ("libpq-escaped-backslash-and-quote", lambda s: f"host=db password='a\\\\\\'{s}' dbname=x"),
    ("libpq-unquoted-with-escapes", lambda s: f"password=pre\\ fix\\'{s} dbname=x"),
    ("libpq-unquoted-quote-inside", lambda s: f'password=pre"{s} dbname=x'),
    ("libpq-spaces-around-equals", lambda s: f"password = '{s}' dbname=x"),
    ("libpq-doubled-quote", lambda s: f"password='pre''{s}' dbname=x"),
    ("libpq-unterminated-quote", lambda s: f"password='pre {s} dbname=x"),
    # --- headers and tokens
    ("authorization-bearer", lambda s: f"Authorization: Bearer {s}"),
    ("authorization-value-with-quote", lambda s: f'Authorization: Bearer abc"{s}'),
    ("authorization-basic-equals", lambda s: f"proxy-authorization=Basic {s}"),
    ("bearer-bare-with-quotes", lambda s: f"using bearer ab\"c'{s} now"),
    ("cookie-header", lambda s: f"Cookie: sid={s}; theme=dark"),
    ("header-in-curl", lambda s: f"curl -H 'X-Api-Key: {s}' https://h.test/"),
    # --- other encodings and layouts
    ("backslash-x-escaped-key", lambda s: f"p\\x61ssword={s}"),
    ("backslash-u-escaped-key", lambda s: f"\\u0074oken={s}"),
    ("value-on-next-line", lambda s: f"password:\n    {s}\nuser: bob"),
    ("tab-separated", lambda s: f"password\t=\t{s}"),
    ("prefixed-and-suffixed-key", lambda s: f"db_password_v2={s}"),
    ("very-long-key", lambda s: "k" * 400 + f"_password={s}"),
]


def _first_letter_encoded(key: str) -> Form:
    return lambda s: f"/cb?%{ord(key[0]):02x}{key[1:]}={s}"


def _uppercase_fully_encoded(key: str) -> Form:
    return lambda s: f"/cb?x=1&{_percent(key.upper())}={s}"


for _key in SENSITIVE_QUERY_KEYS:
    TEXT_FORMS.append((f"url-percent-first-letter-{_key}", _first_letter_encoded(_key)))
    TEXT_FORMS.append((f"url-uppercase-fully-encoded-{_key}", _uppercase_fully_encoded(_key)))


class _Probe(BaseModel):
    count: int


def _channel_message(log: Any, text: str) -> None:
    log.info(text)


def _channel_field(log: Any, text: str) -> None:
    log.info("event", detail=text)


def _channel_nested_field(log: Any, text: str) -> None:
    log.info("event", context={"items": [("note", text)], "more": {"deep": {text: text}}})


def _channel_exception(log: Any, text: str) -> None:
    try:
        raise RuntimeError(text)
    except RuntimeError:
        log.exception("failed")


def _channel_chained_exception(log: Any, text: str) -> None:
    try:
        try:
            raise ValueError(text)
        except ValueError as inner:
            raise ConnectionError(f"wrapped: {text}") from inner
    except ConnectionError as outer:
        log.error("failed", exc_info=outer, error=outer)


def _channel_stdlib_message(_log: Any, text: str) -> None:
    logging.getLogger("uvicorn.error").warning("request failed: %s", text)


def _channel_stdlib_exception(_log: Any, text: str) -> None:
    try:
        raise RuntimeError(text)
    except RuntimeError:
        logging.getLogger("asyncio").exception("Task exception was never retrieved")


CHANNELS: list[Callable[[Any, str], None]] = [
    _channel_message,
    _channel_field,
    _channel_nested_field,
    _channel_exception,
    _channel_chained_exception,
    _channel_stdlib_message,
    _channel_stdlib_exception,
]


@pytest.mark.parametrize("channel", CHANNELS, ids=lambda channel: channel.__name__[9:])
@pytest.mark.parametrize(("form_id", "form"), TEXT_FORMS, ids=[name for name, _ in TEXT_FORMS])
def test_no_form_of_a_credential_reaches_stdout_or_stderr(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    form_id: str,
    form: Form,
    channel: Callable[[Any, str], None],
) -> None:
    _configure()
    channel(get_logger("tests.encodings"), form(sentinel))
    captured = capsys.readouterr()
    assert captured.out.strip(), "the channel must emit a line"
    assert captured.out.count(sentinel) == 0, (form_id, captured.out)
    assert captured.err.count(sentinel) == 0, (form_id, captured.err)


@pytest.mark.parametrize(("form_id", "form"), TEXT_FORMS, ids=[name for name, _ in TEXT_FORMS])
def test_no_form_survives_the_console_renderer(
    capsys: pytest.CaptureFixture[str], sentinel: str, form_id: str, form: Form
) -> None:
    _configure("console")
    log = get_logger("tests.encodings")
    _channel_field(log, form(sentinel))
    _channel_exception(log, form(sentinel))
    captured = capsys.readouterr()
    assert (captured.out + captured.err).count(sentinel) == 0, form_id


# ---------------------------------------------------------------- structured values


class _RaisingItems(dict[str, object]):
    def items(self) -> Any:
        raise RuntimeError(f"password={self['password']}")


class _RaisingIteration(list[object]):
    def __iter__(self) -> Iterator[object]:
        raise RuntimeError("cannot iterate")


class _HostileRepr:
    def __init__(self, value: str) -> None:
        self._value = value

    def __repr__(self) -> str:
        return f"<holding {self._value}>"

    __str__ = __repr__


def _cyclic(value: str) -> dict[str, object]:
    mapping: dict[str, object] = {"password": value, "items": [{"token": value}]}
    mapping["self"] = mapping
    mapping["items"].append(mapping)  # type: ignore[attr-defined]
    return mapping


def _deep(value: str) -> dict[str, object]:
    node: dict[str, object] = {"password": value}
    for level in range(MAX_DEPTH * 3):
        node = {f"level_{level}": [node]}
    return node


STRUCTURES: list[tuple[str, Callable[[str], object]]] = [
    ("password-mapping", lambda s: {"password": s}),
    ("uppercase-password-mapping", lambda s: {"PASSWORD": s, "Db_Password": s}),
    ("access-token-mapping", lambda s: {"access_token": s, "refreshToken": s}),
    ("nested-secret", lambda s: {"config": {"database": {"client_secret": s}}}),
    ("deeply-nested-secret", _deep),
    ("cyclic-object", _cyclic),
    (
        "mixed-list-tuple-dict",
        lambda s: [({"a": ({"api_key": s},)}, [f"token={s}"]), {"note": f"secret={s}"}],
    ),
    ("set-and-frozenset", lambda s: {f"secret={s}", frozenset({f"password={s}"})}),
    ("percent-encoded-mapping-key", lambda s: {"%70assword": s, "%41PI_KEY": s}),
    ("sensitive-key-with-container-value", lambda s: {"credentials": {"anything": [s]}}),
    ("bytes-value", lambda s: {"payload": s.encode(), "raw": bytearray(s.encode())}),
    ("hostile-repr", lambda s: {"obj": _HostileRepr(s), "list": [_HostileRepr(s)]}),
    ("hostile-repr-as-key", lambda s: {_HostileRepr(s): "value"}),
    ("mapping-items-raising", lambda s: {"broken": _RaisingItems(password=s), "ok": 1}),
    ("iteration-raising", lambda s: {"broken": _RaisingIteration([s]), "ok": 1}),
    ("exception-value", lambda s: {"error": RuntimeError(json.dumps({"password": 'p"' + s}))}),
]


@pytest.mark.parametrize(
    ("structure_id", "build"), STRUCTURES, ids=[name for name, _ in STRUCTURES]
)
@pytest.mark.parametrize("log_format", ["json", "console"])
def test_no_structured_value_leaks(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    structure_id: str,
    build: Callable[[str], object],
    log_format: str,
) -> None:
    _configure(log_format)
    get_logger("tests.encodings").info("event", payload=build(sentinel))
    logging.getLogger("tests.stdlib").warning("payload %s", build(sentinel))
    captured = capsys.readouterr()
    assert captured.out.strip()
    assert (captured.out + captured.err).count(sentinel) == 0, structure_id


def test_unreadable_containers_become_a_marker_and_siblings_survive(sentinel: str) -> None:
    result = sanitize(
        {
            "a": _RaisingItems(password=sentinel),
            "b": _RaisingIteration([sentinel]),
            "ok": 1,
            "note": "kept",
        }
    )
    assert result == {"a": UNREADABLE, "b": UNREADABLE, "ok": 1, "note": "kept"}


def test_sanitize_and_scrub_never_raise(sentinel: str) -> None:
    class _Everything(dict[str, object]):
        def items(self) -> Any:
            raise RecursionError(sentinel)

        def __len__(self) -> int:
            raise RuntimeError(sentinel)

    for value in (_Everything(), [_Everything()], {"k": _Everything()}, _cyclic(sentinel)):
        rendered = json.dumps(sanitize(value))
        assert sentinel not in rendered
    assert sentinel not in json.dumps(sanitize(_deep(sentinel)))
    assert TRUNCATED in json.dumps(sanitize(_deep(sentinel)))
    assert CYCLE in json.dumps(sanitize(_cyclic(sentinel)))
    for text in ("\\u", "\\x", "%", "%%%", "{", "[" * 5000, '{"a":' * 2000, "\x00\ud800"):
        assert isinstance(scrub_text(text), str)


def test_validation_error_with_an_escaped_json_credential(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    try:
        _Probe.model_validate({"count": json.dumps({"password": 'p"' + sentinel})})
    except ValidationError as exc:
        get_logger("tests.encodings").exception("validation_failed", error=exc)
        logging.getLogger("tests.stdlib").error("validation: %s", exc, exc_info=True)
    captured = capsys.readouterr()
    assert captured.out.strip()
    assert (captured.out + captured.err).count(sentinel) == 0


# ---------------------------------------------------------------- failure paths


@pytest.mark.parametrize(
    ("form_id", "form"),
    [
        item
        for item in TEXT_FORMS
        if item[0]
        in {
            "json-password-escaped-quote",
            "libpq-escaped-quote",
            "url-percent-encoded-password-key",
        }
    ],
)
def test_formatter_failure_does_not_emit_the_event(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    form_id: str,
    form: Form,
) -> None:
    text = form(sentinel)

    def explode(*_args: object, **_kwargs: object) -> str:
        raise ValueError(f"cannot render {text}")

    monkeypatch.setattr(structlog.processors.JSONRenderer, "__call__", explode)
    _configure()
    get_logger("tests.encodings").info(text, detail=text)
    logging.getLogger("tests.stdlib").warning("%s", text)
    captured = capsys.readouterr()
    assert (captured.out + captured.err).count(sentinel) == 0, form_id
    lines = [json.loads(line) for line in captured.out.splitlines()]
    assert [line["event"] for line in lines] == ["log_record_unrenderable"] * 2


class _BrokenStream:
    def __init__(self, text: str) -> None:
        self._text = text

    def write(self, _text: str) -> int:
        raise OSError(f"write failed for {self._text}")

    def flush(self) -> None:
        raise OSError(f"flush failed for {self._text}")


def test_output_writer_failure_uses_a_fixed_stderr_diagnostic(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    text = json.dumps({"password": 'p"' + sentinel})
    _configure()
    handler = logging.getLogger().handlers[0]
    assert isinstance(handler, logging.StreamHandler)
    handler.setStream(_BrokenStream(text))
    get_logger("tests.encodings").error(text, detail=text)
    logging.getLogger("tests.stdlib").error("lost %s", text)
    captured = capsys.readouterr()
    assert (captured.out + captured.err).count(sentinel) == 0
    assert captured.err.count("voice_agent.logging: a log record could not be written") == 2
    assert "Traceback" not in captured.err and "password" not in captured.err


# ---------------------------------------------------------------- precision


def test_json_text_stays_json_and_keeps_non_sensitive_fields(sentinel: str) -> None:
    text = json.dumps(
        {"user": "bob", "password": 'p"' + sentinel, "meta": {"n": 3, "Token": sentinel}}
    )
    assert json.loads(scrub_text(text)) == {
        "user": "bob",
        "password": REDACTED,
        "meta": {"n": 3, "Token": REDACTED},
    }


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        (
            "https://h.test/cb?code=1&%70assword={s}&state=ok",
            f"https://h.test/cb?code=1&%70assword={REDACTED}&state=ok",
        ),
        (
            "host=db user=app password='a\\'{s}' dbname=x sslmode=require",
            f"host=db user=app password='{REDACTED}' dbname=x sslmode=require",
        ),
        (
            'retry {{"password": "p\\"{s}", "attempt": 2}} later',
            f'retry {{"password": "{REDACTED}", "attempt": 2}} later',
        ),
        # A credential in multi-line text: the next line may continue it (a
        # folded header), so the string is masked whole.
        ("Authorization: Bearer {s}\nX-Trace: abc", REDACTED),
        ("Authorization: Bearer {s} X-Trace: abc", f"Authorization: {REDACTED}"),
    ],
)
def test_only_the_secret_is_removed(sentinel: str, text: str, expected: str) -> None:
    assert scrub_text(text.format(s=sentinel)) == expected


@pytest.mark.parametrize(
    "text",
    [
        "token expired for https://example.com/docs/@team page",
        "GET /health/ready 200 in 1.5ms",
        "https://example.com/a%20b?page=2&sort=name%2Cdesc",
        'File "D:\\projects\\uvicorn\\x64\\server.py", line 12, in serve',
        '{"status": "ok", "checks": {"postgres": "ok", "redis": "ok"}}',
        "retry 3 of 5: [1, 2, 3] {} []",
        "100% done, 50%25 escaped",
    ],
)
def test_ordinary_text_is_left_alone(text: str) -> None:
    assert scrub_text(text) == text


@pytest.mark.parametrize(
    "text",
    [
        "[" * 16_000,
        '{"a":' * 3_000,
        "a=b " * 4_000,
        "%41" * 5_000,
        "?a=1&" * 3_000 + "password=x",
        '\\"' * 8_000,
        "password=" + "\\" * 16_000,
    ],
    ids=["brackets", "open-objects", "pairs", "percent", "query", "escaped-quotes", "backslashes"],
)
def test_scrubbing_stays_fast_on_hostile_input(text: str) -> None:
    started = time.monotonic()
    scrub_text(text)
    assert time.monotonic() - started < 1.0
