"""Sanitiser invariants: no trusted masks, no fixed counts, bounded events (D0-P0-01, D0-M-04).

The third independent review leaked secrets through six forms that earlier
passes had patched around: a value that merely *starts* with the mask, more
whitespace than a pattern allowed, an apostrophe in URL userinfo, and JSON
wrapped more often than a nesting limit. It also showed a small graph of shared
references expanding into megabytes. The tests below pin the invariants rather
than those strings:

* only the exact mask is a mask;
* whitespace, quoting and encoding are read by scanners, in any amount;
* URL userinfo is masked whatever characters it contains;
* a limit that is reached masks or truncates, it never passes input through;
* one event has a whole-event work and output budget, and a container is
  expanded once.

Every leak test uses a fresh sentinel and requires zero occurrences in
everything written to stdout and stderr, through every logging channel and both
renderers.
"""

from __future__ import annotations

import json
import logging
import secrets
import subprocess
import sys
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any
from urllib.parse import quote

import pytest

from voice_agent.platform.infrastructure.observability import logging as logging_module
from voice_agent.platform.infrastructure.observability import redaction
from voice_agent.platform.infrastructure.observability.logging import (
    MAX_RENDERED_EVENT_LENGTH,
    configure_logging,
    get_logger,
)
from voice_agent.platform.infrastructure.observability.redaction import (
    CYCLE,
    MAX_EVENT_NODES,
    MAX_EVENT_OUTPUT,
    MAX_ITEMS,
    MAX_STRING_LENGTH,
    REDACTED,
    REPEATED,
    TRUNCATED,
    TRUNCATED_SENSITIVE,
    UNSUPPORTED,
    is_sensitive_key,
    sanitize,
    scrub_text,
)

pytestmark = pytest.mark.unit

BACKEND_DIR = Path(__file__).resolve().parents[2]
Form = Callable[[str], str]

SENSITIVE_QUERY_KEYS = (
    "password",
    "passwd",
    "secret",
    "token",
    "access_token",
    "refresh_token",
    "api_key",
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


def _dsn(userinfo: str, tail: str = "host:5432/db") -> str:
    # Assembled here so no source line holds a URL with an embedded password.
    return "postgresql://" + userinfo + "@" + tail


def _wrapped(payload: object, layers: int) -> str:
    """``payload`` as JSON, wrapped ``layers`` times in ``{"wrapper": "<json>"}``."""
    text = json.dumps(payload)
    for _ in range(layers):
        text = json.dumps({"wrapper": text})
    return text


def _percent(text: str) -> str:
    return "".join(f"%{ord(char):02X}" for char in text)


def _alternately_encoded(key: str) -> str:
    return "".join(f"%{ord(char):02x}" if index % 2 else char for index, char in enumerate(key))


def _mixed_case(key: str) -> str:
    return "".join(char.upper() if index % 2 else char for index, char in enumerate(key))


# ---------------------------------------------------------------- the form matrix

# The six reproductions from the third independent review, exactly as reported.
CODEX_FORMS: list[tuple[str, Form]] = [
    ("codex-1-mask-prefix-libpq", lambda s: f"host=h password='{REDACTED}{s}' dbname=x"),
    ("codex-2-mask-prefix-query", lambda s: f"https://h/?password={REDACTED}{s}"),
    (
        "codex-3-nine-spaces-after-equals",
        lambda s: "host=h password=" + " " * 9 + "'" + s + "' dbname=x",
    ),
    (
        "codex-4-nine-spaces-before-equals",
        lambda s: "host=h password" + " " * 9 + "=" + s + " dbname=x",
    ),
    ("codex-5-apostrophe-in-userinfo", lambda s: _dsn(f"user:pre'{s}")),
    ("codex-6-json-wrapped-seven-times", lambda s: _wrapped({"password": s}, 7)),
]

FORMS: list[tuple[str, Form]] = list(CODEX_FORMS)

# --- a value is not safe because of how it begins, ends or what it contains
_MASK_VARIANTS: list[tuple[str, Form]] = [
    ("prefix", lambda s: f"{REDACTED}{s}"),
    ("suffix", lambda s: f"{s}{REDACTED}"),
    ("space", lambda s: f"{REDACTED} {s}"),
    ("tab", lambda s: f"{REDACTED}\t{s}"),
    ("embedded", lambda s: f"{s[:8]}{REDACTED}{s}"),
    ("doubled", lambda s: f"{REDACTED}{REDACTED}{s}"),
    ("quoted-mask", lambda s: f'"{REDACTED}"{s}'),
]


def _mask_contexts(variant: Form) -> list[tuple[str, Form]]:
    return [
        ("libpq-quoted", lambda s: f"host=h password='{variant(s)}' dbname=x"),
        ("json", lambda s: json.dumps({"password": variant(s), "user": "bob"})),
        ("json-in-prose", lambda s: "got " + json.dumps({"api_key": variant(s)}) + " back"),
        ("query", lambda s: f"https://h.test/cb?password={quote(variant(s), safe='[]')}&x=1"),
        ("encoded-pair", lambda s: f"/cb?n=%70assword%3D{quote(variant(s), safe='[]')}"),
        ("header", lambda s: f"Authorization: {variant(s)}"),
        ("bearer", lambda s: f"Bearer {variant(s).replace(' ', '').replace(chr(9), '')}"),
        ("userinfo", lambda s: _dsn("user:" + quote(variant(s), safe="[]"))),
        ("sql", lambda s: f"ALTER ROLE app_api PASSWORD '{variant(s)}'"),
    ]


for _variant_id, _variant in _MASK_VARIANTS:
    FORMS.extend(
        (f"mask-{_variant_id}-{context_id}", form) for context_id, form in _mask_contexts(_variant)
    )

# --- whitespace of any amount and kind around the key and the separator
_WHITESPACE_RUNS: list[tuple[str, str]] = [
    ("0", ""),
    ("1", " "),
    ("8", " " * 8),
    ("9", " " * 9),
    ("32", " " * 32),
    ("300", " " * 300),
    ("tab", "\t"),
    ("tabs", "\t" * 12),
    ("mixed", " \t  \t\t \t"),
    ("newline", " \n "),
    ("crlf", "\r\n\t"),
    ("nbsp", "\u00a0\u2003"),
]


def _whitespace_forms(gap: str) -> list[tuple[str, Form]]:
    wide = gap or " "
    return [
        ("before-equals", lambda s: f"host=h password{gap}={s} dbname=x"),
        ("after-equals", lambda s: f"host=h password={gap}{s} dbname=x"),
        ("around-equals", lambda s: f"host=h password{gap}={gap}{s} dbname=x"),
        ("around-equals-quoted", lambda s: f"host=h password{gap}={gap}'pre {s}' dbname=x"),
        ("before-colon", lambda s: f"password{gap}: {s}"),
        ("json-like", lambda s: '{"access_token"' + gap + ":" + gap + '"pre\\"' + s),
        ("bearer", lambda s: f"using Bearer{wide}{s} now"),
        ("sql", lambda s: f"ALTER ROLE app_api PASSWORD{wide}'{s}'"),
        ("flag", lambda s: f"redis-cli --password{wide}{s} ping"),
    ]


for _gap_id, _gap in _WHITESPACE_RUNS:
    FORMS.extend(
        (f"whitespace-{_gap_id}-{form_id}", form) for form_id, form in _whitespace_forms(_gap)
    )

# --- URL userinfo, with URL semantics rather than a list of allowed characters
FORMS.extend(
    [
        ("userinfo-apostrophe", lambda s: _dsn(f"user:a'{s}'b")),
        ("userinfo-colon", lambda s: _dsn(f"user:a:b:{s}")),
        ("userinfo-percent-encoded", lambda s: _dsn("user:" + _percent(s[:4]) + s)),
        ("userinfo-encoded-at", lambda s: _dsn(f"user:a%40{s}")),
        ("userinfo-encoded-colon", lambda s: _dsn(f"user:a%3A{s}%3a")),
        ("userinfo-raw-at", lambda s: _dsn(f"user:a@{s}@b")),
        ("userinfo-double-quote", lambda s: _dsn(f'user:a"{s}')),
        ("userinfo-angle-brackets", lambda s: _dsn(f"user:a<{s}>")),
        ("userinfo-backslash", lambda s: _dsn(f"user:a\\{s}")),
        ("userinfo-slash", lambda s: _dsn(f"user:a/{s}")),
        ("userinfo-question-mark", lambda s: _dsn(f"user:a?{s}")),
        ("userinfo-hash", lambda s: _dsn(f"user:a#{s}")),
        ("userinfo-space", lambda s: _dsn(f"user:a {s}")),
        ("userinfo-sub-delimiters", lambda s: _dsn(f"user:!$&'()*+,;={s}")),
        ("userinfo-token-only", lambda s: _dsn(s, "github.test/org/repo.git")),
        ("userinfo-ipv6-host", lambda s: _dsn(f"user:{s}", "[::1]:5432/db")),
        (
            "userinfo-and-query-password",
            lambda s: _dsn(f"user:a'{s}x") + f"?sslmode=require&password={s}y",
        ),
        ("userinfo-in-nested-url", lambda s: "https://proxy.test/?next=" + _dsn(f"u:a'{s}")),
        ("userinfo-without-scheme", lambda s: f"user:a'{s}@tcp(db:3306)/app"),
        ("userinfo-in-quotes", lambda s: 'dsn_url="' + _dsn(f"user:a'{s}") + '", pool=5'),
        ("url-fragment-token", lambda s: f"https://app.test/cb#access_token={s}&state=1"),
        ("url-query-bracketed-key", lambda s: f"https://app.test/cb?user[password]={s}&x=1"),
        ("url-query-array-key", lambda s: f"https://app.test/cb?password[]={s}"),
        ("url-query-encoded-brackets", lambda s: f"https://app.test/cb?user%5Btoken%5D={s}"),
        ("url-query-email", lambda s: f"https://app.test/cb?email={s}%40example.test"),
    ]
)

# --- libpq keyword/value text, read by a tokenizer
FORMS.extend(
    [
        ("libpq-unquoted", lambda s: f"host=h user=app password={s} dbname=x"),
        ("libpq-single-quoted", lambda s: f"host=h password='two words {s}' dbname=x"),
        ("libpq-escaped-quote", lambda s: f"host=h password='a\\'b {s}' dbname=x"),
        ("libpq-escaped-backslash", lambda s: f"host=h password='a\\\\ {s}' dbname=x"),
        ("libpq-escaped-backslash-quote", lambda s: f"host=h password='a\\\\\\' {s}' dbname=x"),
        ("libpq-equals-in-value", lambda s: f"host=h password='x=1 dbname=y {s}' dbname=x"),
        ("libpq-long-whitespace", lambda s: f"host=h password{' ' * 64}={' ' * 64}'{s}'"),
        ("libpq-tabs", lambda s: f"host=h\tpassword\t=\t'a\t{s}'\tdbname=x"),
        ("libpq-newlines", lambda s: f"host=h\npassword\n=\n'{s}'\ndbname=x"),
        ("libpq-adjacent-pairs", lambda s: f"password='a {s}'sslpassword='b {s}'dbname=x"),
        ("libpq-unterminated", lambda s: f"host=h password='a {s} dbname=x"),
        ("libpq-unquoted-escaped-space", lambda s: f"host=h password=a\\ {s} dbname=x"),
    ]
)


# --- query parameters: the percent-decoded key decides
def _query_forms(key: str) -> list[tuple[str, Form]]:
    return [
        ("plain", lambda s: f"https://h.test/cb?x=1&{key}={s}&y=2"),
        ("first-letter-encoded", lambda s: f"https://h.test/cb?%{ord(key[0]):02x}{key[1:]}={s}"),
        ("mixed-case", lambda s: f"https://h.test/cb?{_mixed_case(key)}={s}"),
        ("partially-encoded", lambda s: f"/cb?{_alternately_encoded(key)}={s}&x=1"),
        ("fully-encoded-uppercase", lambda s: f"/cb?x=1&{_percent(key.upper())}={s}"),
        (
            "duplicated",
            lambda s: f"https://h.test/cb?{key}={s}a&{key}={s}b&{_percent(key)}={s}c",
        ),
        ("form-space", lambda s: f"https://h.test/cb?{key}+={s}&x=1"),
        ("encoded-space", lambda s: f"/cb?%20{key}%20={s}"),
        ("mask-prefixed-value", lambda s: f"https://h.test/cb?{key}=%5BREDACTED%5D{s}"),
    ]


for _key in SENSITIVE_QUERY_KEYS:
    FORMS.extend((f"query-{_key}-{form_id}", form) for form_id, form in _query_forms(_key))

# --- JSON wrapped in JSON strings, to any depth
_NESTING_LEVELS = (1, 2, 5, 7, 10, 20)


def _nested_forms(layers: int) -> list[tuple[str, Form]]:
    return [
        ("password", lambda s: _wrapped({"password": 'p"' + s}, layers)),
        # Keys only the structured policy masks: no text rule can stand in for
        # parsing here, so a nesting limit that passed input through would leak.
        ("structured-keys", lambda s: _wrapped({"phone_number": s, "Email": s, "n": 1}, layers)),
        ("in-prose", lambda s: "upstream: " + _wrapped([{"client_secret": s}], layers) + " end"),
    ]


for _layers in _NESTING_LEVELS:
    FORMS.extend(
        (f"nested-json-{_layers}-{form_id}", form) for form_id, form in _nested_forms(_layers)
    )

# --- further representations found by attacking the sanitiser
FORMS.extend(
    [
        ("sql-alter-role", lambda s: f"ALTER ROLE app_api WITH PASSWORD 'a'' {s}'"),
        ("sql-escape-string", lambda s: f"CREATE USER u PASSWORD E'a\\' {s}'"),
        ("cli-flag", lambda s: f"psql --password {s} --host h"),
        ("tuple-pair", lambda s: f"[('host', 'h'), ('password', 'a {s}')]"),
        ("header-tuple-bytes", lambda s: f"[(b'x-api-key', b'a {s}')]"),
        ("hash-rocket", lambda s: f"{{:password => 'a {s}'}}"),
        ("walrus", lambda s: f"password := {s}"),
        ("xml-element", lambda s: f"<password>a {s}</password>"),
        ("bytes-repr", lambda s: f"password=b'a {s}'"),
        ("call-repr", lambda s: f"password=Secret('a {s}')"),
        ("list-value", lambda s: f"credentials=['a', 'b {s}'] next=1"),
        ("multi-line-value", lambda s: f"credentials={{\n  'a': 'b {s}'\n}}"),
        ("yaml-block", lambda s: f"credentials:\n  first: 1\n  second: {s}\nuser: bob"),
        ("html-entities", lambda s: f"&#x70;assword&#61;{s}"),
        ("fullwidth-key", lambda s: f"\uff50\uff41\uff53\uff53\uff57\uff4f\uff52\uff44\uff1d{s}"),
        ("zero-width-before-separator", lambda s: f"password\u200b={s}"),
        ("zero-width-inside-key", lambda s: f"pass\u200bword={s}"),
        ("mixed-encodings", lambda s: f"%70\\u0061ssword={s}"),
        ("double-escaped-unicode", lambda s: f"\\\\u0070assword={s}"),
        ("percent-encoded-four-times", lambda s: f"/cb?%2525252570assword={s}"),
        ("escaped-json-many-backslashes", lambda s: '{"password' + "\\" * 127 + '": "' + s + '"}'),
        (
            "json-four-times-escaped",
            lambda s: json.dumps(json.dumps(json.dumps(json.dumps({"password": s}))))[1:-1],
        ),
        ("json-after-many-braces", lambda s: "{" * 300 + json.dumps({"email": s})),
        ("jwe-five-segments", lambda s: f"eyJhbGciOiJSUzI1NiJ9.aaaa.bbbb.{s}.cccc"),
        ("non-ascii-key-suffix", lambda s: f"password\u00e9={s}"),
        ("subscripted-key", lambda s: f"config['password'][0] = {s}"),
        ("bearer-with-mask-inside", lambda s: f"Authorization: Bearer {REDACTED}.{s}"),
    ]
)


def _structlog_event(log: Any, text: str) -> None:
    log.info(text)


def _structlog_field(log: Any, text: str) -> None:
    log.info("event", detail=text)


def _structlog_nested_field(log: Any, text: str) -> None:
    log.info("event", context={"items": [("note", text)], "deep": {text: text}})


def _structlog_exception(log: Any, text: str) -> None:
    try:
        raise RuntimeError(text)
    except RuntimeError as exc:
        log.exception("failed", error=exc)


def _stdlib_direct(_log: Any, text: str) -> None:
    logging.getLogger("tests.stdlib").warning(text)


def _stdlib_adapter(_log: Any, text: str) -> None:
    adapter = logging.LoggerAdapter(logging.getLogger("tests.adapter"), {"detail": text})
    adapter.warning("adapter saw %s", text)


def _stdlib_percent_format(_log: Any, text: str) -> None:
    logger = logging.getLogger("uvicorn.error")
    logger.warning("request failed: %s / %r / %-10s", text, text, text)
    logger.warning("request failed: %(detail)s", {"detail": text})


def _stdlib_exception(_log: Any, text: str) -> None:
    try:
        raise RuntimeError(text)
    except RuntimeError:
        logging.getLogger("asyncio").exception("Task exception was never retrieved: %s", text)


CHANNELS: list[Callable[[Any, str], None]] = [
    _structlog_event,
    _structlog_field,
    _structlog_nested_field,
    _structlog_exception,
    _stdlib_direct,
    _stdlib_adapter,
    _stdlib_percent_format,
    _stdlib_exception,
]


@pytest.mark.parametrize("log_format", ["json", "console"])
@pytest.mark.parametrize("channel", CHANNELS, ids=lambda channel: channel.__name__.lstrip("_"))
@pytest.mark.parametrize(("form_id", "form"), FORMS, ids=[name for name, _ in FORMS])
def test_no_representation_reaches_stdout_or_stderr(
    capsys: pytest.CaptureFixture[str],
    sentinel: str,
    form_id: str,
    form: Form,
    channel: Callable[[Any, str], None],
    log_format: str,
) -> None:
    _configure(log_format)
    channel(get_logger("tests.invariants"), form(sentinel))
    captured = capsys.readouterr()
    assert captured.out.strip(), "the channel must emit a line"
    assert captured.out.count(sentinel) == 0, form_id
    assert captured.err.count(sentinel) == 0, form_id


def test_the_matrix_contains_the_six_independent_reproductions() -> None:
    assert [name for name, _ in FORMS[:6]] == [name for name, _ in CODEX_FORMS]
    assert len(CODEX_FORMS) == 6
    assert len({name for name, _ in FORMS}) == len(FORMS)


@pytest.mark.parametrize(("form_id", "form"), FORMS, ids=[name for name, _ in FORMS])
def test_scrub_text_removes_every_representation(sentinel: str, form_id: str, form: Form) -> None:
    assert sentinel not in scrub_text(form(sentinel)), form_id


# ---------------------------------------------------------------- the mask marker


def test_only_the_exact_mask_is_left_alone() -> None:
    for text in (
        f"password={REDACTED}",
        f"host=h password='{REDACTED}' dbname=x",
        f"https://h.test/cb?password={REDACTED}&x=1",
        f"Authorization: {REDACTED}",
        f"postgresql://{REDACTED}@db:5432/x",
        json.dumps({"password": REDACTED, "user": "bob"}),
        f"a note that mentions {REDACTED} in passing",
    ):
        assert scrub_text(text) == text
    assert sanitize({"note": REDACTED, "items": [REDACTED]}) == {
        "note": REDACTED,
        "items": [REDACTED],
    }


@pytest.mark.parametrize(
    ("variant_id", "variant"), _MASK_VARIANTS, ids=[name for name, _ in _MASK_VARIANTS]
)
def test_a_value_containing_the_mask_is_still_masked(
    sentinel: str, variant_id: str, variant: Form
) -> None:
    value = variant(sentinel)
    assert sanitize({"password": value, "nested": {"api_key": value}}) == {
        "password": REDACTED,
        "nested": {"api_key": REDACTED},
    }
    assert json.loads(scrub_text(json.dumps({"password": value, "user": "bob"}))) == {
        "password": REDACTED,
        "user": "bob",
    }
    # A tab in a string that carries a credential makes it ambiguous: grammars
    # disagree about what a tab delimits, so nothing of the string is kept.
    assert scrub_text(f"host=h password='{value}' dbname=x") == (
        REDACTED if "\t" in value else f"host=h password='{REDACTED}' dbname=x"
    )
    encoded = quote(value, safe="[]")
    # (An encoded tab is a tab to whoever decodes the URL.)
    assert scrub_text(f"https://h.test/cb?password={encoded}&x=1") == (
        REDACTED if "\t" in value else f"https://h.test/cb?password={REDACTED}&x=1"
    )
    # A decoded view that merely contains the mask is not thereby "already masked".
    assert sentinel not in scrub_text(f"/cb?n=%70assword%3D{encoded}"), variant_id


# ---------------------------------------------------------------- precision


@pytest.mark.parametrize("gap", [gap for _, gap in _WHITESPACE_RUNS if gap.strip(" ")])
def test_a_credential_beside_other_whitespace_masks_the_whole_string(
    sentinel: str, gap: str
) -> None:
    # Tabs, newlines and non-ASCII whitespace delimit a value in one grammar and
    # belong to it in another (libpq keeps an EM SPACE, its URI parser a tab).
    assert scrub_text(f"host=h password{gap}={gap}{sentinel} dbname=x") == REDACTED
    assert scrub_text(f"host=h password{gap}={gap}'a {sentinel}' dbname=x") == REDACTED


@pytest.mark.parametrize("gap", [gap for _, gap in _WHITESPACE_RUNS if not gap.strip(" ")])
def test_whitespace_is_preserved_and_only_the_value_is_masked(sentinel: str, gap: str) -> None:
    assert scrub_text(f"host=h password{gap}={gap}{sentinel} dbname=x") == (
        f"host=h password{gap}={gap}{REDACTED} dbname=x"
    )
    assert scrub_text(f"host=h password{gap}={gap}'a {sentinel}' dbname=x") == (
        f"host=h password{gap}={gap}'{REDACTED}' dbname=x"
    )


@pytest.mark.parametrize(
    ("userinfo", "tail", "expected_tail"),
    [
        ("user:a'{s}", "host:5432/db", "host:5432/db"),
        ("user:a:b:{s}", "host:5432/db?sslmode=require", "host:5432/db?sslmode=require"),
        ("user:a%40{s}%3A", "host/db", "host/db"),
        ("user:{s}", "[::1]:5432/db", "[::1]:5432/db"),
        ("user:a/{s}", "host/db", "host/db"),
        ("user:a {s}", "host/db", "host/db"),
        ("{s}", "host/path/@team", "host/path/@team"),
    ],
)
def test_userinfo_is_masked_whole_and_the_rest_of_the_url_kept(
    sentinel: str, userinfo: str, tail: str, expected_tail: str
) -> None:
    scrubbed = scrub_text("connecting to " + _dsn(userinfo.format(s=sentinel), tail) + " now")
    assert scrubbed == f"connecting to postgresql://{REDACTED}@{expected_tail} now"


def test_userinfo_and_query_credentials_are_masked_separately(sentinel: str) -> None:
    url = _dsn(f"user:a'{sentinel}") + f"?sslmode=require&%70assword={sentinel}&application_name=x"
    assert scrub_text(url) == (
        f"postgresql://{REDACTED}@host:5432/db"
        f"?sslmode=require&%70assword={REDACTED}&application_name=x"
    )


@pytest.mark.parametrize(
    "text",
    [
        "token expired for https://example.com/docs/@team page",
        "connect to redis://cache:6379/0 failed; http://[::1]:8080/x is up",
        "postgresql://h1:5432,h2:5433/db is a multi-host target",
        'password authentication failed for user "app_api"',
        '127.0.0.1:52345 - "GET /health/ready HTTP/1.1" 200',
        'File "D:\\projects\\@scope\\x64\\server.py", line 12, in serve',
        "see https://example.com/a?page=2&sort=name#section-3 for details",
        "mail bob@example.test or call the desk: extension 12",
        "the token bucket refills 5 tokens per second",
        "caf\u00e9 r\u00e9sum\u00e9 \u2014 100% d\u00e9j\u00e0 vu &amp; more",
    ],
)
def test_ordinary_text_survives_unchanged(text: str) -> None:
    assert scrub_text(text) == text


@pytest.mark.parametrize("layers", [1, 2, 5, 7, 10])
def test_nested_json_is_unwrapped_and_only_secrets_are_removed(sentinel: str, layers: int) -> None:
    # Small enough that ten layers of doubled escaping still fit in one string.
    payload = {"password": sentinel, "n": 3, "phone": 5550100}
    text = _wrapped(payload, layers)
    assert len(text) < MAX_STRING_LENGTH
    value: object = json.loads(scrub_text(text))
    for _ in range(layers):
        assert isinstance(value, dict) and set(value) == {"wrapper"}
        value = json.loads(value["wrapper"])
    assert value == {"password": REDACTED, "n": 3, "phone": REDACTED}


# ---------------------------------------------------------------- limits fail closed


def test_reaching_the_json_nesting_limit_masks_what_was_not_examined(
    monkeypatch: pytest.MonkeyPatch, sentinel: str
) -> None:
    monkeypatch.setattr(redaction, "MAX_JSON_NESTING", 2)
    for layers in (2, 3, 5, 9):
        # Neither value is in a form any text rule recognises: only parsing or
        # masking the unparsed remainder keeps it out.
        scrubbed = scrub_text(_wrapped({"phone_number": sentinel, "items": [sentinel]}, layers))
        assert sentinel not in scrubbed, layers
        assert REDACTED in scrubbed


def test_exhausting_the_json_parse_allowance_masks_the_remainder(
    monkeypatch: pytest.MonkeyPatch, sentinel: str
) -> None:
    monkeypatch.setattr(redaction, "_JSON_WORK_FACTOR", 0)
    text = '{"a": [' * 400 + " then " + json.dumps({"email": sentinel, "items": [sentinel]})
    scrubbed = scrub_text(text)
    assert sentinel not in scrubbed
    assert scrubbed.endswith(REDACTED)


def test_text_that_cannot_be_decoded_to_a_fixed_point_is_masked(sentinel: str) -> None:
    key = "password"
    for _ in range(6):
        key = quote(key[0], safe="") + key[1:] if "%" in key else f"%{ord(key[0]):02X}{key[1:]}"
    assert key.startswith("%2525252525")
    assert sentinel not in scrub_text(f"/cb?{key}={sentinel}")
    result = sanitize({key: sentinel})
    assert isinstance(result, dict) and list(result.values()) == [REDACTED]
    assert is_sensitive_key(key)


def test_a_string_cut_by_the_length_limit_never_shows_what_followed(sentinel: str) -> None:
    for prefix in ("x" * (MAX_STRING_LENGTH - 30), "x " * (MAX_STRING_LENGTH // 2 - 12)):
        for tail in (f" password='{sentinel}", " " + _dsn(f"u:{sentinel}"), f" token={sentinel}"):
            scrubbed = scrub_text(prefix + tail + "y" * 64)
            assert sentinel not in scrubbed
            # What was cut off may have held the delimiter that decides what the
            # examined part means, so none of it is emitted.
            assert scrubbed == TRUNCATED_SENSITIVE
    # Text without any sign of a credential keeps its examined part.
    plain = scrub_text("word " * MAX_STRING_LENGTH)
    assert plain.startswith("word word") and plain.endswith(TRUNCATED)


# ---------------------------------------------------------------- shared references (D0-M-04)


class _CountingDict(dict[str, object]):
    """A mapping that counts how often its content is read."""

    reads = 0

    def items(self) -> Any:
        type(self).reads += 1
        return super().items()


def _count_nodes(value: object) -> int:
    if isinstance(value, dict):
        return 1 + sum(_count_nodes(item) for item in value.values())
    if isinstance(value, list):
        return 1 + sum(_count_nodes(item) for item in value)
    return 1


def _fanout(leaf: object, width: int, levels: int) -> object:
    node = leaf
    for _ in range(levels):
        node = [node] * width
    return node


def test_a_shared_container_is_expanded_once(sentinel: str) -> None:
    _CountingDict.reads = 0
    shared = _CountingDict(note="kept", password=sentinel)
    result = sanitize({"first": shared, "again": shared, "list": [shared, shared]})
    assert result == {
        "first": {"note": "kept", "password": REDACTED},
        "again": REPEATED,
        "list": [REPEATED, REPEATED],
    }
    assert _CountingDict.reads == 1


def test_repeated_acyclic_references_do_not_multiply_the_output(sentinel: str) -> None:
    # The review's shape: 8 references per level; 8**6 leaf visits if expanded.
    leaf = {"note": "n" * 50, "detail": f"token={sentinel}", "password": sentinel}
    graph = _fanout(leaf, 8, 6)
    result = sanitize(graph)
    rendered = json.dumps(result)
    assert sentinel not in rendered
    assert REPEATED in rendered
    assert len(rendered) < 2_000
    assert _count_nodes(result) < 100


def test_nested_fanout_of_distinct_containers_stops_at_the_node_budget() -> None:
    # No sharing and no scalar output: only a whole-event node budget bounds this.
    graph: list[object] = [[[[]] for _ in range(MAX_ITEMS)] for _ in range(MAX_ITEMS)]
    result = sanitize(graph)
    rendered = json.dumps(result)
    assert _count_nodes(result) <= MAX_EVENT_NODES + 2 * 8
    assert TRUNCATED in rendered
    assert len(rendered) < 16 * MAX_EVENT_NODES


def test_cycles_and_repeats_are_both_bounded(sentinel: str) -> None:
    inner: dict[str, object] = {"password": sentinel, "hint": f"secret={sentinel}"}
    outer: dict[str, object] = {"inner": inner, "inner_again": inner}
    inner["back"] = outer
    outer["self"] = outer
    ring: list[object] = [outer, inner]
    ring.append(ring)
    result = sanitize({"outer": outer, "ring": ring, "fan": _fanout(ring, 6, 6)})
    rendered = json.dumps(result)
    assert sentinel not in rendered
    assert CYCLE in rendered and REPEATED in rendered
    assert len(rendered) < 2_000


def test_a_repeated_reference_to_a_secret_container_never_shows_the_secret(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    class _Leaky:
        def __repr__(self) -> str:
            return f"<holding {sentinel}>"

        __str__ = __repr__

    secret_holder = {"password": sentinel, "note": f"api_key={sentinel}", "obj": _Leaky()}
    for log_format in ("json", "console"):
        _configure(log_format)
        get_logger("tests.invariants").info(
            "event", first=secret_holder, second=secret_holder, many=[secret_holder] * 50
        )
        logging.getLogger("tests.stdlib").warning("%s and %s", secret_holder, [secret_holder] * 9)
    captured = capsys.readouterr()
    assert captured.out.count(REPEATED) >= 4
    assert (captured.out + captured.err).count(sentinel) == 0


def test_equal_but_distinct_containers_and_empty_ones_are_not_repeats() -> None:
    empty: tuple[object, ...] = ()
    assert sanitize({"a": [1, 2], "b": [1, 2], "c": empty, "d": empty, "e": {}, "f": {}}) == {
        "a": [1, 2],
        "b": [1, 2],
        "c": [],
        "d": [],
        "e": {},
        "f": {},
    }


# ---------------------------------------------------------------- whole-event budget


def test_the_output_budget_bounds_an_event_of_many_large_strings(sentinel: str) -> None:
    strings = [f"item {index} password={sentinel} " + "x" * 4_000 for index in range(MAX_ITEMS)]
    result = sanitize({"batch": [strings[:100], strings[100:]], "after": f"token={sentinel}"})
    rendered = json.dumps(result)
    assert sentinel not in rendered
    assert TRUNCATED in rendered
    assert len(rendered) < MAX_EVENT_OUTPUT + 4_096


def test_what_follows_an_exhausted_budget_is_replaced_never_passed_through(sentinel: str) -> None:
    class _Leaky:
        def __repr__(self) -> str:
            return f"<holding {sentinel}>"

    filler = ["y" * 8_000 for _ in range(40)]
    late: list[object] = [f"password={sentinel}", sentinel, _Leaky(), {"k": sentinel}, [sentinel]]
    result = sanitize({"filler": filler, "late": late, "last": sentinel})
    assert isinstance(result, dict)
    rendered = json.dumps(result)  # raises if anything but JSON-safe types came back
    # Even the bare sentinel, which no rule recognises, is gone: nothing original
    # is emitted once the budget is spent.
    assert sentinel not in rendered
    assert set(result) == {"filler", TRUNCATED}
    assert len(rendered) < MAX_EVENT_OUTPUT + 4_096


def test_the_scan_budget_bounds_the_text_examined_in_one_event(
    monkeypatch: pytest.MonkeyPatch, sentinel: str
) -> None:
    monkeypatch.setattr(redaction, "MAX_EVENT_SCAN", 1_000)
    strings = [f"n{index} " + "z" * 300 + f" password={sentinel}" for index in range(20)]
    result = sanitize(strings)
    assert isinstance(result, list)
    rendered = json.dumps(result)
    assert sentinel not in rendered
    assert result[-1] == TRUNCATED
    assert len(rendered) < 2_000


def test_identity_fields_survive_an_event_that_exhausts_the_budget(
    capsys: pytest.CaptureFixture[str], sentinel: str
) -> None:
    _configure()
    get_logger("tests.invariants").info(
        "huge_event",
        request_id="req-1",
        blob=["x" * 8_000 for _ in range(60)],
        late=f"password={sentinel}",
    )
    (line,) = capsys.readouterr().out.splitlines()
    assert sentinel not in line
    assert len(line) < MAX_RENDERED_EVENT_LENGTH
    event = json.loads(line)
    assert event["level"] == "info"
    assert event["logger"] == "tests.invariants"
    assert event["service"] == "voice-agent-test"
    assert event["request_id"] == "req-1"
    assert str(event["timestamp"]).endswith("Z")


@pytest.mark.parametrize("log_format", ["json", "console"])
def test_a_rendered_line_above_the_limit_is_replaced_by_a_fixed_record(
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
    sentinel: str,
    log_format: str,
) -> None:
    monkeypatch.setattr(logging_module, "MAX_RENDERED_EVENT_LENGTH", 512)
    _configure(log_format)
    get_logger("tests.invariants").info("big", detail=sentinel + "x" * 2_000)
    logging.getLogger("tests.stdlib").warning("big %s", sentinel + "x" * 2_000)
    captured = capsys.readouterr()
    assert (captured.out + captured.err).count(sentinel) == 0
    lines = [json.loads(line) for line in captured.out.splitlines()]
    assert [line["event"] for line in lines] == ["log_record_oversized"] * 2
    assert all(len(line) <= 512 for line in captured.out.splitlines())


@pytest.mark.parametrize("log_format", ["json", "console"])
def test_every_rendered_event_stays_under_the_absolute_bound(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    _configure(log_format)
    log = get_logger("tests.invariants")
    leaf = {"note": "n" * 50, "password": sentinel}
    log.info("shared", graph=_fanout(leaf, 8, 8))
    log.info("wide", graph=[[f"v{i}-{j}" for j in range(200)] for i in range(200)])
    log.info("large", graph=[f"token={sentinel} " + "\u00e9\x00" * 8_000 for _ in range(200)])
    log.info("x" * 500_000, detail="y" * 500_000)
    logging.getLogger("tests.stdlib").warning("%s", ["z" * 20_000] * 200)
    captured = capsys.readouterr()
    lines = captured.out.splitlines()
    assert len(lines) == 5
    assert all(len(line) <= MAX_RENDERED_EVENT_LENGTH for line in lines)
    assert (captured.out + captured.err).count(sentinel) == 0


# ---------------------------------------------------------------- exact types only


class _TextSubclass(str):
    hidden = ""

    def __repr__(self) -> str:
        return f"<text {self.hidden}>"

    __str__ = __repr__


class _IntSubclass(int):
    hidden = ""

    def __repr__(self) -> str:
        return f"<int {self.hidden}>"

    __str__ = __repr__


class _FloatSubclass(float):
    hidden = ""

    def __repr__(self) -> str:
        return f"<float {self.hidden}>"

    __str__ = __repr__


def _exact_types_only(value: object) -> Iterator[type]:
    yield type(value)
    if isinstance(value, dict):
        for key, item in value.items():
            yield type(key)
            yield from _exact_types_only(item)
    elif isinstance(value, list):
        for item in value:
            yield from _exact_types_only(item)


@pytest.mark.parametrize("log_format", ["json", "console"])
def test_subclasses_of_builtin_scalars_are_rebuilt_as_exact_types(
    capsys: pytest.CaptureFixture[str], sentinel: str, log_format: str
) -> None:
    text = _TextSubclass("plain")
    text.hidden = sentinel
    number = _IntSubclass(7)
    number.hidden = sentinel
    ratio = _FloatSubclass(1.5)
    ratio.hidden = sentinel
    payload = {"text": text, "number": number, "ratio": ratio, text: [text], number: ratio}
    result = sanitize(payload)
    assert set(_exact_types_only(result)) <= {dict, list, str, int, float}
    assert result == {"text": "plain", "number": 7, "ratio": 1.5, "plain": ["plain"], "7": 1.5}
    _configure(log_format)
    get_logger("tests.invariants").info("event", payload=payload, direct=number)
    logging.getLogger("tests.stdlib").warning("%s %r %s", text, number, ratio)
    captured = capsys.readouterr()
    assert (captured.out + captured.err).count(sentinel) == 0


def test_oversized_integers_and_hostile_type_names_become_markers(sentinel: str) -> None:
    hostile = type(f"password={sentinel} " + "T" * 300, (), {})
    result = sanitize({"big": 10**5_000, "obj": hostile(), "ok": 2**64})
    assert result == {"big": "<int: 16610 bits>", "obj": UNSUPPORTED, "ok": 2**64}


# ---------------------------------------------------------------- bounded work

_HOSTILE_TEXTS: list[tuple[str, str]] = [
    ("spaces-after-key", "password" + " " * 16_000),
    ("spaces-after-many-keys", ("password" + " " * 40) * 340),
    ("unterminated-quotes", "password='" * 1_600),
    ("doubled-quotes", "password='" + "''" * 8_000),
    ("open-brackets", "password=(" * 1_600),
    ("schemes", "://" * 5_400),
    ("schemes-with-queries", "?a=1&://" * 2_000),
    ("schemes-with-colons", "://a:b " * 2_300),
    ("authorities", "a:b@" * 4_000),
    ("jwt-prefixes", "eyJ-" * 4_000),
    ("bearer-runs", "bearer " * 2_300),
    ("percent-runs", "%25" * 5_400),
    ("entities", "&amp;" * 3_200),
    ("fullwidth", "\uff50" * 16_000),
    ("json-openers", '{"a":[' * 2_700),
    ("nested-json", _wrapped({"k": "v"}, 12)),
    ("key-runs", "password." * 1_800 + "=x"),
    ("subscripts", "password" + "[0]" * 5_000 + "=x"),
    ("block-keys", "password:\n" * 1_600),
    ("letters", "a" * 16_000),
]


@pytest.mark.parametrize(("text_id", "text"), _HOSTILE_TEXTS, ids=[n for n, _ in _HOSTILE_TEXTS])
def test_hostile_text_produces_bounded_output(text_id: str, text: str) -> None:
    scrubbed = scrub_text(text)
    assert isinstance(scrubbed, str)
    # Masking can lengthen text by at most the mask per pair; never unboundedly.
    assert len(scrubbed) <= 4 * MAX_STRING_LENGTH, text_id
    rendered = json.dumps(sanitize({"a": [text] * MAX_ITEMS, "b": {text: text}}))
    assert len(rendered) < MAX_EVENT_OUTPUT + 4_096, text_id


_BOUNDEDNESS_SCRIPT = """
import json, sys
from voice_agent.platform.infrastructure.observability.redaction import sanitize, scrub_text

leaf = {"note": "n" * 50, "password": "p"}
graph = leaf
for _ in range(12):
    graph = [graph] * 12
wide = [[[[]] for _ in range(200)] for _ in range(200)]
texts = ["://" * 5400, "password='" * 1600, '{"a":[' * 2700, "%25" * 5400, "a:b@" * 4000]
total = 0
for value in (graph, wide, texts * 40, {"k": [t * 50 for t in texts]}):
    total += len(json.dumps(sanitize(value)))
for text in texts:
    total += len(scrub_text(text * 100))
sys.stdout.write(str(total))
"""


def test_adversarial_events_finish_quickly_in_a_fresh_interpreter() -> None:
    # Secondary defence only: correctness rests on the deterministic budgets
    # asserted above. The ceiling is generous so that a slow CI runner passes
    # while an exponential or quadratic regression (minutes, or never) does not.
    completed = subprocess.run(
        [sys.executable, "-c", _BOUNDEDNESS_SCRIPT],
        cwd=BACKEND_DIR,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr[-2_000:]
    assert 0 < int(completed.stdout) < 1_000_000
