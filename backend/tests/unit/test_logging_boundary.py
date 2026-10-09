"""The logging trust boundary (D0-P0-01 and D0-M-04, independent review 4).

Review 4 reproduced six further credential exposures and three unbounded
stages. They had one cause each rather than one pattern each:

* the text rules read one grammar while the consumer of the text reads
  another (libpq keeps an EM SPACE in a value, its URI parser a tab or a
  newline; a folded header continues on the next line);
* text was cut before it was classified, so the cut decided the classification;
* a logger name was treated as safe text and shortened, not validated;
* a subclass of a known scalar was asked to convert itself;
* work was done (copying, interpolating, rendering) before any limit applied.

Every credential test here first asks an independent parser (libpq through
psycopg, SQLAlchemy, ``urllib``, the standard HTTP header parser) whether the
generated sentinel really is credential material in that input, and only then
requires zero occurrences on stdout and on stderr. No test opens a connection.
"""

from __future__ import annotations

import datetime as dt
import enum
import http.client
import io
import json
import logging
import secrets
import tracemalloc
import uuid
from collections.abc import Callable, Iterator, Mapping
from dataclasses import dataclass
from decimal import Decimal
from http import HTTPStatus
from pathlib import PurePosixPath, PureWindowsPath
from typing import Any
from urllib.parse import parse_qsl, urlsplit

import pytest
import structlog
from psycopg import Error as PsycopgError
from psycopg.conninfo import conninfo_to_dict
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

from voice_agent.platform.infrastructure.observability import logging as logging_module
from voice_agent.platform.infrastructure.observability import redaction
from voice_agent.platform.infrastructure.observability.logging import (
    MAX_FORMAT_WIDTH,
    MAX_RENDERED_EVENT_LENGTH,
    configure_logging,
    get_logger,
    redact_sensitive_fields,
)
from voice_agent.platform.infrastructure.observability.redaction import (
    MAX_EVENT_FIELDS,
    MAX_EVENT_OUTPUT,
    MAX_ITEMS,
    MAX_STRING_LENGTH,
    REDACTED,
    TRUNCATED,
    TRUNCATED_SENSITIVE,
    UNSUPPORTED,
    render_exception,
    sanitize,
    sanitize_event,
    scrub_text,
    trusted_identifier,
)

pytestmark = pytest.mark.unit

BACKSLASH = chr(92)
EM_SPACE = "\N{EM SPACE}"
NBSP = "\N{NO-BREAK SPACE}"
FORMATS = ("json", "console")
# Kept apart from what follows it so that no line of this file looks like a
# URL with a literal password (scripts/check_repository.py).
_URI_USER = "postgresql://u:"


@pytest.fixture
def sentinel() -> str:
    """A fresh, distinctive value per test; it is a secret only by where it is put."""
    return "D0LEAKSENTINEL" + secrets.token_hex(12)


def _digits(sentinel: str) -> str:
    """A long, purely numeric secret derived from the sentinel."""
    return str(int.from_bytes(sentinel.encode(), "big"))


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


# ---------------------------------------------------------------- independent parsers


def _libpq(text: str) -> str:
    """The password libpq itself reads from ``text`` (empty if it rejects the input)."""
    try:
        return str(conninfo_to_dict(text).get("password", ""))
    except (PsycopgError, UnicodeDecodeError):
        # Rejected, or split inside a multi-byte character by a C library whose
        # isspace() takes a continuation byte for whitespace.
        return ""


def _sqlalchemy(text: str) -> str:
    try:
        url = make_url(text)
    except ArgumentError:
        return ""
    return " ".join([url.password or "", *(str(v) for k, v in url.query.items() if "pass" in k)])


def _urllib(text: str) -> str:
    parts = urlsplit(text)
    return " ".join([parts.password or "", *(v for k, v in parse_qsl(parts.query) if "pass" in k)])


def _http(text: str) -> str:
    """Credential header values as the standard library's HTTP header parser reads them."""
    message = http.client.parse_headers(io.BytesIO(text.encode("latin-1") + b"\r\n\r\n"))
    names = ("Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie")
    return " ".join(str(message.get(name, "")) for name in names)


# ---------------------------------------------------------------- credential forms


@dataclass(frozen=True)
class Form:
    """One credential-bearing text and the parser that says what its credential is."""

    name: str
    build: Callable[[str], str]
    parser: Callable[[str], str]
    # What must not be emitted (the sentinel, unless the form derives another secret).
    secret: Callable[[str], str] = lambda s: s
    # False where the reading depends on the libpq build (C-library isspace()).
    confirmed_everywhere: bool = True


def _libpq_separator(name: str, separator: str, *, everywhere: bool) -> Form:
    return Form(
        f"libpq-value-then-{name}",
        lambda s: f"host=h password=[REDACTED]{separator}{s} dbname=x",
        _libpq,
        confirmed_everywhere=everywhere,
    )


def _long_password(sentinel: str, length: int) -> str:
    digits = _digits(sentinel)
    return digits + "7" * max(0, length - len(digits))


def _long_uri(length: int) -> Form:
    return Form(
        f"uri-password-of-{length}",
        lambda s: f"postgresql://u:{_long_password(s, length)}@host/db",
        _libpq,
        secret=_digits,
    )


FORMS: list[Form] = [
    # --- 1. libpq keyword/value: what ends an unquoted value is libpq's decision
    _libpq_separator("em-space", EM_SPACE, everywhere=True),
    _libpq_separator("ideographic-space", "\N{IDEOGRAPHIC SPACE}", everywhere=True),
    _libpq_separator("thin-space", "\N{THIN SPACE}", everywhere=True),
    _libpq_separator("line-separator", "\N{LINE SEPARATOR}", everywhere=True),
    _libpq_separator("file-separator", "\x1c", everywhere=True),
    _libpq_separator("nbsp", NBSP, everywhere=False),
    _libpq_separator("next-line", "\x85", everywhere=False),
    # ASCII whitespace ends the value in libpq: the parser does not confirm these.
    _libpq_separator("space", " ", everywhere=False),
    _libpq_separator("tab", "\t", everywhere=False),
    _libpq_separator("newline", "\n", everywhere=False),
    _libpq_separator("crlf", "\r\n", everywhere=False),
    Form(
        "libpq-quoted-em-space", lambda s: f"host=h password='pa ss{EM_SPACE}{s}' dbname=x", _libpq
    ),
    Form("libpq-quoted-tab", lambda s: f"host=h password='[REDACTED]\t{s}' dbname=x", _libpq),
    Form("libpq-quoted-newline", lambda s: f"host=h password='a\n{s}' dbname=x", _libpq),
    Form(
        "libpq-quoted-escaped-quote",
        lambda s: f"host=h password='it{BACKSLASH}'s {s}' dbname=x",
        _libpq,
    ),
    Form(
        "libpq-backslash-escaped",
        lambda s: f"host=h password=pa{BACKSLASH} ss{BACKSLASH}'{s} dbname=x",
        _libpq,
    ),
    Form(
        "libpq-backslash-escaped-tab",
        lambda s: f"host=h password=pa{BACKSLASH}\t{s} dbname=x",
        _libpq,
    ),
    # --- 2. PostgreSQL URIs: whitespace does not end a credential
    Form("uri-query-tab", lambda s: f"postgresql://host/db?password=[REDACTED]\t{s}", _libpq),
    Form("uri-query-newline", lambda s: f"postgresql://host/db?password=[REDACTED]\n{s}", _libpq),
    Form("uri-query-crlf", lambda s: f"postgresql://host/db?password=[REDACTED]\r\n{s}", _libpq),
    Form(
        "uri-query-encoded-tab", lambda s: f"postgresql://host/db?password=[REDACTED]%09{s}", _libpq
    ),
    Form("uri-query-encoded-newline", lambda s: f"postgresql://host/db?password=a%0A{s}", _libpq),
    Form("uri-query-hash", lambda s: f"postgresql://host/db?password=a#{s}", _libpq),
    Form("uri-query-space", lambda s: f"postgresql://host/db?password=a {s}", _sqlalchemy),
    Form("uri-query-key-with-tab", lambda s: f"postgresql://host/db?pass\tword={s}", _urllib),
    Form("uri-userinfo-unusual", lambda s: f"postgresql://u:p'a;s$!*(),+{s}@host/db", _libpq),
    Form("uri-userinfo-newline", lambda s: f"{_URI_USER}pa\n{s}@host/db", _libpq),
    Form("uri-userinfo-tab", lambda s: f"{_URI_USER}pa\t{s}@host/db", _libpq),
    Form("uri-userinfo-space", lambda s: f"postgresql://u:pa {s}@host/db", _sqlalchemy),
    Form("uri-userinfo-slash-space", lambda s: f"postgresql://u:1234/ {s}@host/db", _sqlalchemy),
    Form("uri-userinfo-slash-newline", lambda s: f"postgresql://u:1234/\n{s}@host/db", _sqlalchemy),
    Form("uri-scheme-with-tab", lambda s: f"postgresql:/\t/u:{s}\n@host/db", _urllib),
    Form(
        "uri-userinfo-and-query",
        lambda s: f"postgresql://u:{s}@host/db?sslmode=require&password=a\t{s}",
        _libpq,
    ),
    Form(
        "uri-long-with-userinfo-and-query",
        lambda s: "connect " + "x" * 4_000 + f" postgresql://u:{s}@host/db?password=a\n{s}",
        lambda text: _libpq(text[text.index("postgresql://") :]),
    ),
    # --- 3. HTTP credential headers and their folded continuation lines
    Form("header-authorization-basic", lambda s: f"Authorization: Basic {s}", _http),
    Form("header-authorization-bearer", lambda s: f"Authorization: Bearer {s}", _http),
    Form(
        "header-digest-response",
        lambda s: f'Authorization: Digest username="u", realm="r", response="{s}"',
        _http,
    ),
    Form(
        "header-folded-digest-tab",
        lambda s: f'Authorization: Digest username="u",\r\n\tresponse="{s}"',
        _http,
    ),
    Form(
        "header-folded-digest-spaces",
        lambda s: f'Authorization: Digest username="u",\r\n    response="{s}"',
        _http,
    ),
    Form("header-cookie-continuation", lambda s: f"Cookie: session=\r\n\t{s}", _http),
    Form("header-folded-cookie-value", lambda s: f"Cookie: theme=dark;\r\n session={s}", _http),
    Form("header-folded-set-cookie", lambda s: f"Set-Cookie: sid=\r\n  {s}; HttpOnly", _http),
    Form(
        "header-folded-proxy-authorization", lambda s: f"Proxy-Authorization: Basic\r\n\t{s}", _http
    ),
    Form(
        "header-folded-after-other-header",
        lambda s: f"Accept: */*\r\nCookie: a=b;\r\n\tsession={s}\r\nHost: h",
        _http,
    ),
    # --- 4. long credentials: the delimiter lies beyond a processing limit
    *(
        _long_uri(length)
        for length in (127, 128, 2_047, 2_048, 2_049, 3_000, 16_383, 16_384, 16_385, 20_000, 70_000)
    ),
]


def test_every_form_carries_the_sentinel_as_credential_material(sentinel: str) -> None:
    """The parser, not this suite, says that the sentinel is part of a credential."""
    for form in FORMS:
        confirmed = form.secret(sentinel) in form.parser(form.build(sentinel))
        if form.confirmed_everywhere:
            assert confirmed, form.name
    names = [form.name for form in FORMS]
    assert len(names) == len(set(names))
    for required in (
        "libpq-value-then-em-space",
        "uri-query-tab",
        "uri-query-newline",
        "header-cookie-continuation",
        "header-folded-digest-tab",
        "uri-password-of-3000",
    ):
        assert required in names


# ---------------------------------------------------------------- logging channels


def _structlog_event(log: Any, text: str) -> None:
    log.info(text)


def _structlog_field(log: Any, text: str) -> None:
    log.info("probe", detail=text)


def _structlog_nested_field(log: Any, text: str) -> None:
    log.info("probe", payload={"items": [text, {"note": text}]})


def _structlog_positional(log: Any, text: str) -> None:
    log.info("probe %s", text)


def _structlog_exception(log: Any, text: str) -> None:
    try:
        raise RuntimeError(text)
    except RuntimeError:
        log.exception("probe")


def _structlog_exception_value(log: Any, text: str) -> None:
    log.error("probe", error=RuntimeError(text))


def _structlog_chained_exception(log: Any, text: str) -> None:
    try:
        try:
            raise ValueError(text)
        except ValueError as inner:
            raise ConnectionError("outer failure") from inner
    except ConnectionError:
        log.exception("probe")


def _stdlib_direct(_log: Any, text: str) -> None:
    logging.getLogger("tests.boundary.stdlib").warning(text)


def _stdlib_percent(_log: Any, text: str) -> None:
    logging.getLogger("tests.boundary.stdlib").warning("probe %s and %r", text, text)


def _stdlib_mapping(_log: Any, text: str) -> None:
    logging.getLogger("tests.boundary.stdlib").warning("probe %(value)s", {"value": text})


def _stdlib_adapter(_log: Any, text: str) -> None:
    adapter = logging.LoggerAdapter(logging.getLogger("tests.boundary.stdlib"), {"detail": text})
    adapter.warning("probe %s", text)


def _stdlib_exception(_log: Any, text: str) -> None:
    try:
        raise RuntimeError(text)
    except RuntimeError:
        logging.getLogger("tests.boundary.stdlib").exception("probe %s", text)


CHANNELS: tuple[Callable[[Any, str], None], ...] = (
    _structlog_event,
    _structlog_field,
    _structlog_nested_field,
    _structlog_positional,
    _structlog_exception,
    _structlog_exception_value,
    _structlog_chained_exception,
    _stdlib_direct,
    _stdlib_percent,
    _stdlib_mapping,
    _stdlib_adapter,
    _stdlib_exception,
)

_FORM_IDS = [form.name for form in FORMS]


def _confirmed_secret(form: Form, sentinel: str) -> tuple[str, str]:
    """The text of a form and its secret, once the parser has confirmed it.

    Forms the parser does not confirm on this platform (ASCII whitespace ends a
    libpq value) are still sent through every channel, but nothing is claimed
    about them: a probe is a leak only where the sentinel is credential material.
    """
    text, secret = form.build(sentinel), form.secret(sentinel)
    if secret not in form.parser(text):
        assert not form.confirmed_everywhere, form.name
        return text, ""
    return text, secret


@pytest.mark.parametrize("log_format", FORMATS)
@pytest.mark.parametrize("channel", CHANNELS, ids=lambda channel: channel.__name__.lstrip("_"))
@pytest.mark.parametrize("form", FORMS, ids=_FORM_IDS)
def test_a_parser_confirmed_credential_never_reaches_stdout_or_stderr(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    form: Form,
    channel: Callable[[Any, str], None],
    log_format: str,
) -> None:
    text, secret = _confirmed_secret(form, sentinel)
    _configure(log_format)
    channel(get_logger("tests.boundary"), text)
    captured = capsys.readouterr()
    assert captured.out.strip(), "the channel must emit something"
    if secret:
        assert captured.out.count(secret) == 0, f"{form.name}: on stdout"
        assert captured.err.count(secret) == 0, f"{form.name}: on stderr"


@pytest.mark.parametrize("form", FORMS, ids=_FORM_IDS)
def test_scrub_text_removes_a_parser_confirmed_credential(sentinel: str, form: Form) -> None:
    text, secret = _confirmed_secret(form, sentinel)
    if secret:
        assert secret not in scrub_text(text), form.name
        assert secret not in json.dumps(sanitize({"detail": text, "items": [text]})), form.name
        assert secret not in render_exception(RuntimeError(text)), form.name


class _BrokenStream:
    def __init__(self, text: str) -> None:
        self._text = text

    def write(self, _text: str) -> int:
        raise OSError(f"disk full while writing {self._text}")

    def flush(self) -> None:
        raise OSError(f"flush failed for {self._text}")


def _break_the_formatter(monkeypatch: pytest.MonkeyPatch, text: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> str:
        raise ValueError(f"cannot render {text}")

    monkeypatch.setattr(structlog.processors.JSONRenderer, "__call__", explode)
    monkeypatch.setattr(structlog.dev.ConsoleRenderer, "__call__", explode)


def _break_the_writer(text: str) -> None:
    handler = logging.getLogger().handlers[0]
    assert isinstance(handler, logging.StreamHandler)
    handler.setStream(_BrokenStream(text))


def _break_the_sanitiser(monkeypatch: pytest.MonkeyPatch, text: str) -> None:
    def explode(*_args: object, **_kwargs: object) -> dict[str, object]:
        raise RuntimeError(f"sanitiser broke on {text}")

    monkeypatch.setattr(logging_module, "sanitize_event", explode)


@pytest.mark.parametrize("log_format", FORMATS)
@pytest.mark.parametrize("failure", ["formatter", "writer", "sanitiser"])
@pytest.mark.parametrize("form", FORMS, ids=_FORM_IDS)
def test_a_failing_pipeline_stage_emits_no_credential(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    form: Form,
    failure: str,
    log_format: str,
) -> None:
    text, secret = _confirmed_secret(form, sentinel)
    _configure(log_format)
    if failure == "formatter":
        _break_the_formatter(monkeypatch, text)
    elif failure == "writer":
        _break_the_writer(text)
    else:
        _break_the_sanitiser(monkeypatch, text)
    for channel in (_structlog_event, _structlog_field, _stdlib_percent, _structlog_exception):
        channel(get_logger("tests.boundary"), text)
    captured = capsys.readouterr()
    assert (captured.out + captured.err).strip(), "a fixed record or diagnostic is expected"
    if secret:
        assert captured.out.count(secret) == 0, f"{form.name}: on stdout"
        assert captured.err.count(secret) == 0, f"{form.name}: on stderr"


# ---------------------------------------------------------------- grammar: libpq values


@pytest.mark.parametrize(
    "separator",
    [EM_SPACE, NBSP, "\N{IDEOGRAPHIC SPACE}", "\N{LINE SEPARATOR}", "\x1c", "\x1f", "\x85"],
    ids=["em-space", "nbsp", "ideographic", "line-separator", "fs", "us", "nel"],
)
def test_only_ascii_whitespace_ends_an_unquoted_value(sentinel: str, separator: str) -> None:
    """The scanner itself, below the ambiguity rule that would also mask these."""
    text = f"host=h password=first{separator}{sentinel} dbname=x"
    start = text.index("first")
    end = redaction._unquoted_end(text, start, to_end_of_line=False, in_query=False)
    assert text[start:end] == f"first{separator}{sentinel}"
    assert sentinel not in redaction._scrub_pairs(text)
    assert redaction._scrub_pairs(text).endswith(" dbname=x")


@pytest.mark.parametrize("separator", [" ", "\t", "\n", "\r", "\v", "\f"])
def test_ascii_whitespace_ends_an_unquoted_value_as_in_libpq(separator: str) -> None:
    text = f"password=first{separator}second"
    assert redaction._unquoted_end(
        text, len("password="), to_end_of_line=False, in_query=False
    ) == (len("password=first"))


def test_a_credential_beside_ambiguous_whitespace_masks_the_whole_string(sentinel: str) -> None:
    for separator in (EM_SPACE, NBSP, "\t", "\n", "\r\n", "\x1c", "\N{ZERO WIDTH SPACE}"):
        assert scrub_text(f"host=h password=[REDACTED]{separator}{sentinel} dbname=x") == REDACTED


def test_ordinary_whitespace_keeps_the_rest_of_a_connection_string(sentinel: str) -> None:
    assert scrub_text(f"host=db user=app password={sentinel} dbname=x") == (
        f"host=db user=app password={REDACTED} dbname=x"
    )


def test_multi_line_text_without_a_credential_is_left_alone() -> None:
    for text in (
        "first line\nsecond line\twith a tab",
        "retrying in 3s\r\nattempt 2 of 5",
        f"caf{chr(0xE9)}{NBSP}au lait",
        "see https://example.com/docs\nand https://example.com/faq",
    ):
        assert scrub_text(text) == text


# ---------------------------------------------------------------- grammar: URIs


def test_a_sensitive_uri_parameter_is_masked_to_the_next_ampersand_or_the_end(
    sentinel: str,
) -> None:
    assert scrub_text(f"https://h.test/cb?a=1&password={sentinel}&state=ok") == (
        f"https://h.test/cb?a=1&password={REDACTED}&state=ok"
    )
    # Not to the next space or "#": parsers keep both in the value.
    assert scrub_text(f"postgresql://h/db?password=a {sentinel} trailing") == (
        f"postgresql://h/db?password={REDACTED}"
    )
    assert scrub_text(f"postgresql://h/db?password=a#{sentinel}") == (
        f"postgresql://h/db?password={REDACTED}"
    )


def test_whitespace_does_not_end_the_search_for_userinfo(sentinel: str) -> None:
    assert (
        scrub_text(f"postgresql://u:pa {sentinel}@db:5432/x")
        == f"postgresql://{REDACTED}@db:5432/x"
    )
    assert sentinel not in scrub_text(f"postgresql://u:1234/ {sentinel}@db/x")
    assert sentinel not in redaction._scrub_urls(f"postgresql://us er:{sentinel}@db/x", cut=False)


def test_urls_without_credentials_survive(sentinel: str) -> None:
    for text in (
        "Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)",
        "token expired for https://example.com/docs/@team page",
        "GET https://api.example.test/v1/items?page=2&size=50 took 12ms",
        "see http://[::1]:8000/health and http://localhost:8000/health",
    ):
        assert scrub_text(text) == text


# ---------------------------------------------------------------- grammar: headers


def test_a_single_line_credential_header_keeps_its_name(sentinel: str) -> None:
    assert scrub_text(f"Authorization: Bearer {sentinel}") == f"Authorization: {REDACTED}"
    assert scrub_text(f"Cookie: session={sentinel}; theme=dark") == f"Cookie: {REDACTED}"
    assert scrub_text(f'Digest username="u", response="{sentinel}"') == f"Digest {REDACTED}"


@pytest.mark.parametrize("fold", ["\r\n\t", "\r\n ", "\r\n    ", "\n\t", "\n "])
def test_a_folded_credential_header_is_masked_with_its_continuation(
    sentinel: str, fold: str
) -> None:
    for header in (
        f"Cookie: session={fold}{sentinel}",
        f'Authorization: Digest username="u",{fold}response="{sentinel}"',
        f"Proxy-Authorization: Basic{fold}{sentinel}",
        f"Set-Cookie: sid={fold}{sentinel}; HttpOnly",
        f"X-Api-Key:{fold}{sentinel}",
        f"request failed\r\nCookie: a=b;{fold}session={sentinel}\r\nHost: h",
    ):
        assert scrub_text(header) == REDACTED


# ---------------------------------------------------------------- truncation


@pytest.mark.parametrize("length", [127, 128, 2_047, 2_048, 2_049, 3_000, 16_000])
def test_a_long_uri_password_is_classified_whole_in_an_exception(
    sentinel: str, length: int
) -> None:
    password = _long_password(sentinel, length)
    text = f"connect failed: postgresql://u:{password}@host/db"
    assert password in _libpq(text[text.index("postgresql://") :])
    for rendered in (
        redaction.describe_exception(RuntimeError(text)),
        render_exception(RuntimeError(text)),
        json.dumps(sanitize({"error": RuntimeError(text)})),
    ):
        assert _digits(sentinel) not in rendered
        assert "7" * 32 not in rendered
        # Classified with its "@" in view, so the surroundings survive.
        assert f"RuntimeError: connect failed: postgresql://{REDACTED}@host/db" in rendered


@pytest.mark.parametrize("length", [16_385, 20_000, 70_000])
def test_a_credential_whose_delimiter_lies_beyond_the_limit_is_replaced_whole(
    sentinel: str, length: int
) -> None:
    password = _long_password(sentinel, length)
    text = f"connect failed: postgresql://u:{password}@host/db"
    assert scrub_text(text) == TRUNCATED_SENSITIVE
    assert sanitize({"detail": text}) == {"detail": TRUNCATED_SENSITIVE}
    described = redaction.describe_exception(RuntimeError(text))
    assert described == f"RuntimeError: {TRUNCATED_SENSITIVE}"


def test_oversized_text_is_never_reclassified_from_its_prefix(sentinel: str) -> None:
    filler = "7" * MAX_STRING_LENGTH
    for text in (
        f"{_URI_USER}{_digits(sentinel)}{filler}@host/db",  # port-shaped once cut
        f"password='{sentinel}{filler}'",
        f"Authorization: Basic {sentinel}{filler}",
        f"the token is {sentinel}{filler}",  # a sign of a credential in the examined part
    ):
        assert scrub_text(text) == TRUNCATED_SENSITIVE
    # No sign of a credential: the examined part is kept, minus its last, cut token.
    plain = scrub_text("alpha beta " * MAX_STRING_LENGTH)
    assert plain.startswith("alpha beta alpha") and plain.endswith(f"beta {TRUNCATED}")
    assert len(plain) <= MAX_STRING_LENGTH + len(TRUNCATED) + 1
    # A single unbroken token cannot be cut safely at all.
    assert scrub_text("a" * (MAX_STRING_LENGTH + 1)) == TRUNCATED
    # Nor is a secret kept whose only sign of being one lies beyond the cut.
    assert scrub_text(f"{sentinel}{filler} password=x") == TRUNCATED
    assert scrub_text(f"user:{_digits(sentinel)}{filler}@tcp(host)/db") == TRUNCATED


# ---------------------------------------------------------------- logger metadata


def _hostile_names(sentinel: str) -> list[tuple[str, str]]:
    digits = _digits(sentinel)
    return [
        (f"postgresql://u:{sentinel}@host/db", sentinel),
        (f"postgresql://u:{digits}{'7' * 3_000}@host/db", digits),  # secret before any cut
        (f"{'x' * 300}://u:{sentinel}@host/db", sentinel),  # secret after any cut
        (f"svc password={sentinel}", sentinel),
        (f"Cookie: session=\r\n\t{sentinel}", sentinel),
        (f"tests.boundary\n{sentinel}", sentinel),
    ]


@pytest.mark.parametrize("log_format", FORMATS)
@pytest.mark.parametrize("failure", ["none", "formatter", "writer", "sanitiser"])
@pytest.mark.parametrize("index", range(6))
def test_an_untrusted_logger_name_is_replaced_never_shortened(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    index: int,
    failure: str,
    log_format: str,
) -> None:
    name, secret = _hostile_names(sentinel)[index]
    _configure(log_format)
    if failure == "formatter":
        _break_the_formatter(monkeypatch, name)
    elif failure == "writer":
        _break_the_writer(name)
    elif failure == "sanitiser":
        _break_the_sanitiser(monkeypatch, name)
    get_logger(name).info("probe")
    logging.getLogger(name).warning("probe")
    try:
        raise RuntimeError("probe")
    except RuntimeError:
        get_logger(name).exception("probe")
    captured = capsys.readouterr()
    assert captured.out.count(secret) == 0, "on stdout"
    assert captured.err.count(secret) == 0, "on stderr"
    # Not even a harmless-looking prefix of the name survives.
    assert name[:12] not in captured.out + captured.err
    # (The traceback of the third record names this test as well.)
    assert (captured.out + captured.err).count("untrusted_logger") >= 3


def test_a_well_formed_logger_name_is_kept_on_every_path(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    _configure()
    get_logger("voice_agent.apps.api").info("probe")
    (line,) = _json_lines(capsys.readouterr().out)
    assert line["logger"] == "voice_agent.apps.api"
    _break_the_formatter(monkeypatch, "x")
    logging.getLogger("uvicorn.error").warning("probe")
    (line,) = _json_lines(capsys.readouterr().out)
    assert (line["event"], line["logger"]) == ("log_record_unrenderable", "uvicorn.error")
    _break_the_writer("x")
    logging.getLogger("uvicorn.error").warning("probe")
    assert "logger=uvicorn.error, level=warning, error=OSError" in capsys.readouterr().err


@pytest.mark.parametrize("log_format", FORMATS)
def test_service_environment_and_request_id_are_validated_identifiers(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    configure_logging(
        service_name=f"svc://u:{sentinel}@host",
        environment=f"prod\r\nCookie: a={sentinel}",
        log_level="INFO",
        log_format=log_format,
    )
    get_logger("tests.boundary").info("probe", request_id=f"req password={sentinel}")
    logging.getLogger("tests.boundary").warning("probe")
    output = _assert_absent(capsys, sentinel, "identity")
    assert output.count("untrusted_service") == 2
    assert output.count("untrusted_environment") == 2
    assert output.count("untrusted_request_id") == 1


def test_trusted_identifier_accepts_by_grammar_and_keeps_no_part_of_a_rejected_value(
    sentinel: str,
) -> None:
    assert trusted_identifier("voice_agent.apps.api", "logger", "x") == "voice_agent.apps.api"
    assert trusted_identifier("__main__", "logger", "x") == "__main__"
    assert trusted_identifier("voice-agent-api", "service", "x") == "voice-agent-api"
    assert trusted_identifier("warning", "level", "x") == "warning"
    assert trusted_identifier("2026-10-08T05:43:14.243072Z", "timestamp", "x") == (
        "2026-10-08T05:43:14.243072Z"
    )
    assert trusted_identifier("0190a6b2-0000-7000-8000-000000000000", "request_id", "x") == (
        "0190a6b2-0000-7000-8000-000000000000"
    )

    class _Name(str):
        __slots__ = ()

        def __str__(self) -> str:
            return sentinel

    rejected: list[object] = [
        "",
        "a" * 129,
        f"a.{sentinel}/x",
        "voice agent",
        "a..b",
        ".a",
        "a\n",
        f"postgresql://u:{sentinel}@h",
        # Well-formed as a name, but a token by the text rules.
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJl",
        _Name("tests.boundary"),
        None,
        7,
        object(),
    ]
    for value in rejected:
        assert trusted_identifier(value, "logger", "untrusted_logger") == "untrusted_logger"
    assert trusted_identifier("anything", "no-such-kind", "fallback") == "fallback"


def test_emergency_paths_use_no_record_attribute_unvalidated(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch, sentinel: str
) -> None:
    _configure()
    _break_the_formatter(monkeypatch, sentinel)
    record = logging.LogRecord(
        f"n://u:{sentinel}@h", logging.WARNING, f"/src/{sentinel}.py", 1, f"m {sentinel}", (), None
    )
    record.levelname = f"WARN password={sentinel}"
    record.created = f"created {sentinel}"  # type: ignore[assignment]
    handler = logging.getLogger().handlers[0]
    handler.handle(record)
    _break_the_writer(sentinel)
    handler.handle(record)
    captured = capsys.readouterr()
    assert captured.out.count(sentinel) == 0
    assert captured.err.count(sentinel) == 0
    (line,) = _json_lines(captured.out)
    assert line == {
        "event": "log_record_unrenderable",
        "level": "unknown",
        "logger": "untrusted_logger",
        "timestamp": "unknown",
        "error_type": "ValueError",
    }
    assert "logger=untrusted_logger, level=unknown" in captured.err


# ---------------------------------------------------------------- object conversion


class _Hostile:
    """What the conversion methods of every hostile class below return."""

    text = ""
    raises = False


def _leak(*_args: object, **_kwargs: object) -> str:
    if _Hostile.raises:
        raise RuntimeError(f"conversion failed: {_Hostile.text}")
    return _Hostile.text


class _HostileWindowsPath(PureWindowsPath):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __fspath__(self) -> str:
        return _leak()

    def as_posix(self) -> str:
        return _leak()


class _HostilePosixPath(PurePosixPath):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileDecimal(Decimal):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __format__(self, _spec: str, _context: object = None) -> str:
        return _leak()


class _HostileUUID(uuid.UUID):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileDate(dt.date):
    def isoformat(self) -> str:
        return _leak()

    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __format__(self, _spec: str) -> str:
        return _leak()


class _HostileDateTime(dt.datetime):
    def isoformat(self, sep: str = "T", timespec: str = "auto") -> str:
        return _leak()

    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileTime(dt.time):
    def isoformat(self, timespec: str = "auto") -> str:
        return _leak()

    def __str__(self) -> str:
        return _leak()


class _HostileTimedelta(dt.timedelta):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileTimezone(dt.tzinfo):
    def utcoffset(self, _moment: dt.datetime | None) -> dt.timedelta:
        _leak()
        return dt.timedelta(0)

    def tzname(self, _moment: dt.datetime | None) -> str:
        return _leak()

    def dst(self, _moment: dt.datetime | None) -> dt.timedelta:
        return dt.timedelta(0)

    def __repr__(self) -> str:
        return _leak()


class _HostileInt(int):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __format__(self, _spec: str) -> str:
        return _leak()


class _HostileFloat(float):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __format__(self, _spec: str) -> str:
        return _leak()


class _HostileStr(str):
    __slots__ = ()

    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __format__(self, _spec: str) -> str:
        return _leak()


class _HostileBytes(bytes):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileEnum(enum.Enum):
    MEMBER = "member"

    @property
    def value(self) -> str:
        return _leak()

    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileDict(dict[str, object]):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileList(list[object]):
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileObject:
    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()

    def __format__(self, _spec: str) -> str:
        return _leak()


class _Impostor:
    """Claims to be a str; its real type is what counts."""

    @property  # type: ignore[misc]
    def __class__(self) -> type:
        return str

    def __str__(self) -> str:
        return _leak()

    def __repr__(self) -> str:
        return _leak()


class _HostileError(Exception):
    """Validation-style errors whose parts convert themselves to the secret."""

    def errors(self) -> list[dict[str, object]]:
        return [
            {"loc": (_HostileStr("field"), _HostileInt(3)), "msg": _HostileObject(), "type": "x"},
            {"loc": _HostileList(), "msg": _HostileStr("plain"), "type": _HostileObject()},
        ]

    def __repr__(self) -> str:
        return _leak()


def _hostile_values() -> list[tuple[str, object]]:
    return [
        ("windows-path", _HostileWindowsPath("C:/logs/app.log")),
        ("posix-path", _HostilePosixPath("/var/log/app.log")),
        ("decimal", _HostileDecimal("12.50")),
        ("uuid", _HostileUUID(int=5)),
        ("date", _HostileDate(2026, 1, 2)),
        ("datetime", _HostileDateTime(2026, 1, 2, 3, 4, 5)),
        ("time", _HostileTime(3, 4, 5)),
        ("timedelta", _HostileTimedelta(seconds=90)),
        ("datetime-with-hostile-timezone", dt.datetime(2026, 1, 2, tzinfo=_HostileTimezone())),
        ("time-with-hostile-timezone", dt.time(3, 4, tzinfo=_HostileTimezone())),
        ("int", _HostileInt(42)),
        ("float", _HostileFloat(1.5)),
        ("str", _HostileStr("plain text")),
        ("bytes", _HostileBytes(b"abc")),
        ("enum", _HostileEnum.MEMBER),
        ("dict", _HostileDict(count=1)),
        ("list", _HostileList([1, 2])),
        ("object", _HostileObject()),
        ("impostor", _Impostor()),
        ("exception", _HostileError("plain message")),
    ]


_HOSTILE_IDS = [name for name, _ in _hostile_values()]


def _log_object_everywhere(value: object) -> None:
    log: Any = get_logger("tests.boundary")
    stdlib = logging.getLogger("tests.boundary.stdlib")
    log.info("probe", direct=value, items=[value], mapping={"inner": value}, pair=(value, value))
    log.info("probe %s", value)
    log.info(value)
    stdlib.warning("%s and %r", value, value)
    stdlib.warning("%(value)s", {"value": value})
    stdlib.warning(value)
    stdlib.warning(value, "argument")
    logging.LoggerAdapter(stdlib, {"extra": value}).warning("adapter %s", value)
    try:
        raise _HostileError("plain message")
    except _HostileError:
        log.exception("probe", detail=value)
    try:
        keyed = {value: "value"}
    except (TypeError, RuntimeError):
        return  # unhashable, or its own __hash__ converts it: it cannot be a key at all
    log.info("probe", keyed=keyed)


@pytest.mark.parametrize("log_format", FORMATS)
@pytest.mark.parametrize("raises", [False, True], ids=["returns-secret", "raises"])
@pytest.mark.parametrize("index", range(len(_HOSTILE_IDS)), ids=_HOSTILE_IDS)
def test_no_conversion_method_of_an_untrusted_object_reaches_the_log(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    index: int,
    raises: bool,
    log_format: str,
) -> None:
    monkeypatch.setattr(_Hostile, "text", sentinel)
    monkeypatch.setattr(_Hostile, "raises", raises)
    _, value = _hostile_values()[index]
    _configure(log_format)
    _log_object_everywhere(value)
    captured = capsys.readouterr()
    assert captured.out.count(sentinel) == 0, "on stdout"
    assert captured.err.count(sentinel) == 0, "on stderr"
    assert captured.err == ""
    assert len(captured.out.splitlines()) >= 9


@pytest.mark.parametrize("index", range(len(_HOSTILE_IDS)), ids=_HOSTILE_IDS)
def test_subclasses_are_read_through_base_slots_or_replaced_by_a_fixed_marker(
    monkeypatch: pytest.MonkeyPatch, sentinel: str, index: int
) -> None:
    monkeypatch.setattr(_Hostile, "text", sentinel)
    name, value = _hostile_values()[index]
    expected: dict[str, object] = {
        # str, int and float subclasses: the base type's own data.
        "int": 42,
        "float": 1.5,
        "str": "plain text",
        "enum": "member",
        "dict": {"count": 1},
        "list": [1, 2],
        "exception": (
            "_HostileError: 2 validation error(s): "
            f"{UNSUPPORTED}.{UNSUPPORTED}: {UNSUPPORTED} [x]; <root>: {UNSUPPORTED} [{UNSUPPORTED}]"
        ),
    }
    assert sanitize(value) == expected.get(name, UNSUPPORTED)
    result = sanitize({"value": value})
    assert sentinel not in json.dumps(result)


def test_exact_scalar_types_keep_their_useful_rendering(capsys: pytest.CaptureFixture[str]) -> None:
    class _Colour(enum.Enum):
        RED = "red"

    _configure()
    get_logger("tests.boundary").info(
        "probe",
        id=uuid.UUID(int=5),
        amount=Decimal("12.50"),
        day=dt.date(2026, 1, 2),
        at=dt.datetime(2026, 1, 2, 3, 4, 5, tzinfo=dt.UTC),
        local=dt.datetime(2026, 1, 2, 3, 4, 5),
        clock=dt.time(3, 4, 5),
        took=dt.timedelta(milliseconds=1500),
        path=PurePosixPath("/var/log/app.log"),
        colour=_Colour.RED,
        status=HTTPStatus.OK,
        blob=b"abc",
        count=3,
        ratio=0.25,
        ready=True,
        missing=None,
    )
    (line,) = _json_lines(capsys.readouterr().out)
    assert line["id"] == "00000000-0000-0000-0000-000000000005"
    assert line["amount"] == "12.50"
    assert line["day"] == "2026-01-02"
    assert line["at"] == "2026-01-02T03:04:05+00:00"
    assert line["local"] == "2026-01-02T03:04:05"
    assert line["clock"] == "03:04:05"
    assert line["took"] == 1.5
    assert line["path"] == "/var/log/app.log"
    assert line["colour"] == "red"
    assert line["status"] == 200
    assert line["blob"] == "<bytes: 3 bytes>"
    assert (line["count"], line["ratio"], line["ready"], line["missing"]) == (3, 0.25, True, None)


def test_a_path_is_still_scrubbed_as_text(sentinel: str) -> None:
    assert (
        sanitize(PurePosixPath(f"/srv/app?password={sentinel}")) == f"/srv/app?password={REDACTED}"
    )


def test_no_string_type_is_trusted_by_the_sanitiser(sentinel: str) -> None:
    # The type of what the module itself returns is the plain built-in: there
    # is no class a caller could construct to be believed (see
    # tests/unit/test_logging_trust.py for the full boundary).
    produced = type(render_exception(ValueError("ordinary")))
    assert produced is str

    class _Forged(str):
        __slots__ = ()

    for forged in (produced(f"password={sentinel}"), _Forged(f"password={sentinel}")):
        assert sentinel not in json.dumps(sanitize({"note": forged}))
        assert sentinel not in json.dumps(sanitize_event({"note": forged}))
    # A plain string added after the first pass is scrubbed by the second.
    first = sanitize_event({"note": "ordinary", "event": "probe"})
    first["added_later"] = f"password={sentinel}"
    second = sanitize_event(first)
    assert second == {"note": "ordinary", "event": "probe", "added_later": f"password={REDACTED}"}


def test_a_multi_line_traceback_survives_both_sanitising_passes(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    _structlog_chained_exception(get_logger("tests.boundary"), f"bad option password={sentinel}")
    (line,) = _json_lines(_assert_absent(capsys, sentinel, "traceback"))
    exception = line["exception"]
    assert exception.count("Traceback (most recent call last):") == 2
    assert f"ValueError: bad option password={REDACTED}" in exception
    assert "ConnectionError: outer failure" in exception
    assert "_structlog_chained_exception" in exception


# ---------------------------------------------------------------- D0-M-04: admission


class _CountingMapping(Mapping[str, object]):
    """A mapping that counts every entry visited and every value fetched."""

    def __init__(self, size: int) -> None:
        self.size = size
        self.visited = 0
        self.fetched = 0

    def __len__(self) -> int:
        return self.size

    def __iter__(self) -> Iterator[str]:
        for index in range(self.size):
            self.visited += 1
            yield f"field_{index}"

    def __getitem__(self, key: str) -> object:
        if not key.startswith("field_"):
            raise KeyError(key)
        self.fetched += 1
        return int(key.removeprefix("field_"))


@pytest.mark.parametrize("size", [2_000, 20_000, 100_000])
def test_event_preparation_visits_a_bounded_number_of_fields(size: int) -> None:
    mapping = _CountingMapping(size)
    result = redact_sensitive_fields(None, "info", mapping)  # type: ignore[arg-type]
    # The limit, plus the one entry that shows the limit was reached.
    assert mapping.visited == MAX_EVENT_FIELDS + 1
    assert mapping.fetched <= MAX_EVENT_FIELDS + 1
    assert len(result) == MAX_EVENT_FIELDS + 1
    assert result[TRUNCATED] == "event field limit reached"
    assert result["field_0"] == 0 and f"field_{MAX_EVENT_FIELDS}" not in result


def test_a_mapping_that_never_ends_is_not_followed() -> None:
    class _Endless(Mapping[str, object]):
        visited = 0

        def __len__(self) -> int:
            return 1

        def __iter__(self) -> Iterator[str]:
            while True:
                self.visited += 1
                yield "logger"  # a key the event sanitiser skips, for ever

        def __getitem__(self, key: str) -> object:
            if key != "logger":
                raise KeyError(key)
            return "tests.boundary"

    endless = _Endless()
    result = redact_sensitive_fields(None, "info", endless)  # type: ignore[arg-type]
    assert result == {"logger": "tests.boundary"}
    assert endless.visited <= MAX_EVENT_FIELDS + 16


def test_event_preparation_does_not_copy_the_event_first() -> None:
    event = {f"field_{index}": index for index in range(100_000)}
    redact_sensitive_fields(None, "info", dict(event))  # warm-up: imports, caches
    tracemalloc.start()
    try:
        redact_sensitive_fields(None, "info", event)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    # A copy of 100,000 entries alone is over 5 MB.
    assert peak < 256_000


@pytest.mark.parametrize("size", [2_000, 100_000])
def test_nested_and_standard_library_mappings_are_visited_within_the_limit(
    capsys: pytest.CaptureFixture[str], size: int
) -> None:
    _configure()
    nested, arguments = _CountingMapping(size), _CountingMapping(size)
    get_logger("tests.boundary").info("probe", payload=nested)
    logging.getLogger("tests.boundary.stdlib").warning("first is %(field_0)s", arguments)
    lines = _json_lines(capsys.readouterr().out)
    assert nested.visited == MAX_ITEMS + 1
    assert arguments.visited == MAX_ITEMS + 1
    assert lines[0]["payload"][TRUNCATED] == f"{size - MAX_ITEMS} more entries"
    assert lines[1]["event"] == "first is 0"


@pytest.mark.parametrize("log_format", FORMATS)
def test_a_call_with_too_many_fields_is_admitted_up_to_the_limit(
    capsys: pytest.CaptureFixture[str], log_format: str
) -> None:
    _configure(log_format)
    seen: list[int] = []
    original = structlog.stdlib.BoundLogger._process_event

    def spy(self: Any, method_name: str, event: Any, event_kw: dict[str, Any]) -> Any:
        seen.append(len(event_kw))
        return original(self, method_name, event, event_kw)

    with pytest.MonkeyPatch.context() as patch:
        patch.setattr(structlog.stdlib.BoundLogger, "_process_event", spy)
        get_logger("tests.boundary").info("probe", **{f"field_{i}": i for i in range(100_000)})
        bound = get_logger("tests.boundary").bind(**{f"bound_{i}": i for i in range(100_000)})
        bound.info("probe", extra=1)
    # structlog's own copy of the call's fields never sees more than the limit.
    assert seen == [MAX_EVENT_FIELDS + 1, 1]
    assert len(bound._context) <= MAX_EVENT_FIELDS + 1
    output = capsys.readouterr().out
    assert len(output.splitlines()) == 2
    assert "event field limit reached" in output
    assert all(len(line) < MAX_RENDERED_EVENT_LENGTH for line in output.splitlines())
    assert "field_99999" not in output and "bound_99999" not in output


# ---------------------------------------------------------------- D0-M-04: percent formats


def _peak_while(action: Callable[[], object]) -> int:
    tracemalloc.start()
    try:
        action()
        return tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()


_UNBOUNDED_FORMATS: list[tuple[str, str, tuple[object, ...] | dict[str, object]]] = [
    ("width", "%10000000s", ("x",)),
    ("width-just-over", f"%{MAX_FORMAT_WIDTH + 1}s", ("x",)),
    ("zero-padded", "%010000000d", (7,)),
    ("precision", "%.10000000f", (1.5,)),
    ("width-and-precision", "%5.10000000s", ("x",)),
    ("star-width", "%*s", (10_000_000, "x")),
    ("star-precision", "%.*f", (10_000_000, 1.5)),
    ("keyed-width", "%(value)10000000s", {"value": "x"}),
    ("nested-key", "%(a(b)c)10000000s", {"a(b)c": "x"}),
    ("after-literal-percent", "100%% then %10000000s", ("x",)),
    ("many-directives", "%s" * 65, ("x",) * 65),
    ("long-template", "x" * 1_000_000 + " %s", ("x",)),
]


@pytest.mark.parametrize("log_format", FORMATS)
@pytest.mark.parametrize(
    ("case", "template", "arguments"), _UNBOUNDED_FORMATS, ids=[c for c, _, _ in _UNBOUNDED_FORMATS]
)
def test_an_unbounded_percent_format_is_replaced_before_it_is_interpolated(
    capsys: pytest.CaptureFixture[str],
    case: str,
    template: str,
    arguments: tuple[object, ...] | dict[str, object],
    log_format: str,
) -> None:
    _configure(log_format)
    logger = logging.getLogger("tests.boundary.stdlib")
    logger.warning("warm-up %s", "x")
    capsys.readouterr()
    if isinstance(arguments, dict):
        peak = _peak_while(lambda: logger.warning(template, arguments))
    else:
        peak = _peak_while(lambda: logger.warning(template, *arguments))
    # Interpolating any of these would allocate megabytes.
    assert peak < 200_000, case
    captured = capsys.readouterr()
    assert captured.err == ""
    (line,) = _json_lines(captured.out)
    assert line == {
        "event": "log_record_unsafe_format",
        "level": "warning",
        "logger": "tests.boundary.stdlib",
        "timestamp": line["timestamp"],
        "error_type": "UnboundedLogFormat",
    }


def test_ordinary_percent_formats_still_interpolate(capsys: pytest.CaptureFixture[str]) -> None:
    _configure()
    logger = logging.getLogger("tests.boundary.stdlib")
    logger.warning("plain %s", "value")
    logger.warning("%s, %s and %s", "one", 2, 3.5)
    logger.warning("%-10s|%5d|%8.3f|%x|%r|100%%", "left", 42, 3.14159, 255, "quoted")
    logger.warning("%(name)s has %(count)d items", {"name": "queue", "count": 3})
    logger.warning(f"%{MAX_FORMAT_WIDTH}s", "edge")
    logger.warning("literal 100% with no arguments")
    events = [line["event"] for line in _json_lines(capsys.readouterr().out)]
    assert events == [
        "plain value",
        "one, 2 and 3.5",
        "left      |   42|   3.142|ff|'quoted'|100%",
        "queue has 3 items",
        " " * (MAX_FORMAT_WIDTH - 4) + "edge",
        "literal 100% with no arguments",
    ]


@pytest.mark.parametrize(
    ("template", "arguments"),
    [("%z", ("x",)), ("%s and %s", ("only one",)), ("%d", ("not a number",)), ("%", ("x",))],
    ids=["unknown-conversion", "too-few-arguments", "wrong-type", "dangling-percent"],
)
def test_a_malformed_percent_format_emits_a_fixed_record(
    capsys: pytest.CaptureFixture[str], sentinel: str, template: str, arguments: tuple[object, ...]
) -> None:
    _configure()
    logging.getLogger("tests.boundary.stdlib").warning(
        template + f" password={sentinel}", *arguments
    )
    (line,) = _json_lines(_assert_absent(capsys, sentinel, "malformed format"))
    assert line["event"] == "log_record_unrenderable"


def test_the_template_scan_reads_directives_as_the_interpreter_does() -> None:
    bounded = logging_module._is_bounded_template
    for template in ("", "no directives", "%s", "%%", "%5%", "%(k)s", "%-08.3f", "%256s", "%.256f"):
        assert bounded(template), template
    for template in ("%257s", "%.257f", "%0257d", "%*d", "%.*f", "%(k)257s", "%(a(b)c)s", "%(k"):
        assert not bounded(template), template
    assert bounded("x" * MAX_STRING_LENGTH)
    assert not bounded("x" * (MAX_STRING_LENGTH + 1))


# ---------------------------------------------------------------- D0-M-04: scalar accounting


# Markers that stand for what the budget cut off are not charged to it: at most
# two per open container (depth 8), each a few dozen characters.
_MARKER_ALLOWANCE = 512


def _rendered(payload: object) -> str:
    return json.dumps(sanitize(payload))


def test_numeric_scalars_are_charged_what_they_actually_render_as() -> None:
    # 2,400 integers of 39 digits: about 98,000 characters if each counted as 24.
    payload = {f"k{i}": [2**127 - 1] * 200 for i in range(12)}
    assert len(_rendered(payload)) <= MAX_EVENT_OUTPUT + _MARKER_ALLOWANCE
    assert TRUNCATED in _rendered(payload)
    for scalar in (2**127 - 1, -(2**127), 1.7976931348623157e308, -2.2250738585072014e-308, True):
        many = {f"k{i}": [scalar] * 200 for i in range(40)}
        assert len(_rendered(many)) <= MAX_EVENT_OUTPUT + _MARKER_ALLOWANCE
    mixed = {
        f"k{i}": [1, 2.5, None, False, "text", Decimal("1.5"), uuid.UUID(int=i)] * 28
        for i in range(40)
    }
    assert len(_rendered(mixed)) <= MAX_EVENT_OUTPUT + _MARKER_ALLOWANCE


def test_short_numbers_are_unchanged_and_cheap() -> None:
    payload = {"count": 3, "ratio": 0.5, "big": 2**64, "values": list(range(150))}
    assert sanitize(payload) == payload


@pytest.mark.parametrize("digits", [100, 5_000, 79_404, 1_000_000])
def test_an_oversized_integer_is_rejected_without_being_rendered(digits: int) -> None:
    number = 10**digits
    payload = {"value": number, "items": [number, -number]}
    sanitize({"warm": 1})
    peak = _peak_while(lambda: sanitize(payload))
    # str(number) alone would be `digits` bytes.
    assert peak < 50_000
    bits = number.bit_length()
    assert sanitize({"value": number, 10**50: "key"}) == {
        "value": f"<int: {bits} bits>",
        "<int: 167 bits>": "key",
    }


def test_a_long_decimal_is_rejected_without_being_rendered() -> None:
    huge = Decimal("1" * 100_000)
    sanitize({"warm": Decimal("1.5")})
    assert _peak_while(lambda: sanitize({"value": huge})) < 50_000
    assert sanitize({"value": huge}) == {"value": "<Decimal: too long>"}
    assert sanitize(Decimal("0." + "3" * 60)) == "<Decimal: too long>"
    assert sanitize(Decimal("12345678901234567890.12345678901234567890")) == (
        "12345678901234567890.12345678901234567890"
    )
    for text in ("12.50", "-0.001", "1E+1000000", "NaN", "-Infinity", "0E-1000000"):
        assert sanitize(Decimal(text)) == text


@pytest.mark.parametrize("log_format", FORMATS)
def test_one_budget_covers_the_whole_event_on_every_path(
    capsys: pytest.CaptureFixture[str], log_format: str
) -> None:
    _configure(log_format)
    numbers = {f"k{i}": [2**127 - 1] * 200 for i in range(40)}
    text = {f"t{i}": "word " * 3_000 for i in range(40)}
    get_logger("tests.boundary").info("probe", **numbers)
    get_logger("tests.boundary").info("probe", **text)
    get_logger("tests.boundary").info("probe", payload=[numbers, text, numbers])
    logging.getLogger("tests.boundary.stdlib").warning("%s %s", numbers, text)
    logging.getLogger("tests.boundary.stdlib").warning("%(k0)s", numbers)
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 5
    for line in lines:
        # The event budget, a second rendering of escapes by the console
        # renderer, and the fixed identity fields.
        assert len(line) < MAX_EVENT_OUTPUT * 2
        assert "log_record_oversized" not in line
    assert all(TRUNCATED in line for line in lines[:4])


def test_identity_fields_survive_an_event_that_exhausts_every_budget(
    capsys: pytest.CaptureFixture[str],
) -> None:
    _configure()
    fields = {f"field_{i}": "x" * 2_000 for i in range(5_000)}
    get_logger("tests.boundary").info("probe", request_id="req-1", **fields)
    (line,) = _json_lines(capsys.readouterr().out)
    assert line["logger"] == "tests.boundary"
    assert line["level"] == "info"
    assert line["service"] == "voice-agent-test"
    assert line["environment"] == "test"
    assert line["request_id"] == "req-1"
    assert line["timestamp"].endswith("Z")


def test_a_deep_traceback_is_rendered_within_bounds() -> None:
    def recurse(depth: int) -> None:
        if depth == 0:
            raise RuntimeError("bottom of the stack")
        recurse(depth - 1)

    try:
        recurse(400)
    except RuntimeError as exc:
        rendered = render_exception(exc)
    assert rendered.endswith("RuntimeError: bottom of the stack\n")
    assert rendered.count("in recurse") <= 32
    assert len(rendered) < 32_768 + 64
