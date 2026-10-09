"""Generated attacks on the sanitiser (D0-P0-01 final self-review).

The fixed matrices in ``test_redaction_invariants`` list representations
someone thought of. This module builds representations nobody listed: a
credential is written in one of twenty syntaxes with randomly chosen keys,
encodings, whitespace, quoting and mask-lookalike prefixes, then wrapped zero
to four times (JSON, ``repr``, percent-encoding, character references, unicode
escapes, prose, duplication). The generator is seeded, so a failure reproduces.

The forms in ``REGRESSIONS`` are the classes this generator found while the
sanitiser was being hardened; each leaked at the time and is pinned here in a
readable shape:

* text that is the ``repr``/JSON encoding of other text, so that the
  whitespace around a separator is written ``\\n`` or ``\\t``;
* keys escaped twice (``\\\\u0064``), which only a second decoding round reveals;
* a value that an early rule delimited wrongly, which removed the very
  characters a decoded view needed to show the credential;
* a span that ran past its value and swallowed the key of the next pair;
* a quote behind several backslashes, whose meaning depends on an unknown
  escaping depth;
* encodings layered in an order that leaves a character reference incomplete
  until another decoding has run.

One invariant throughout: the sentinel occurs zero times in the output.
"""

from __future__ import annotations

import html
import json
import logging
import random
import secrets
from collections.abc import Callable
from urllib.parse import quote

import pytest

from voice_agent.platform.infrastructure.observability.logging import (
    configure_logging,
    get_logger,
)
from voice_agent.platform.infrastructure.observability.redaction import sanitize, scrub_text

pytestmark = pytest.mark.unit

Form = Callable[[str], str]
BACKSLASH = chr(92)
APOSTROPHE = chr(39)

KEYS = (
    "password",
    "passwd",
    "secret",
    "token",
    "access_token",
    "refresh_token",
    "api_key",
    "authorization",
    "client_secret",
    "db_password",
    "sslpassword",
    "private_key",
    "pwd",
)
WHITESPACE = ("", " ", "  ", "\t", " \t ", " " * 9, " " * 40, "\u00a0", "\n", "\r\n ")
MASK_LOOKALIKES = (
    "",
    "[REDACTED]",
    "[REDACTED] ",
    "[REDACTED]\t",
    "'[REDACTED]'",
    "[TRUNCATED]",
    "[REDACTED][REDACTED]",
)
VALUE_PREFIXES = (
    "",
    "pre ",
    "a'b",
    'a"b',
    "a" + BACKSLASH * 2,
    "a=b ",
    "a&b",
    "a@b:",
    "{x}",
    "[1]",
)
VALUE_SUFFIXES = ("", " tail", "'", '"', BACKSLASH, "]", "[REDACTED]")
URL_JUNK = ("'", '"', "!$", "(x)", "*+,;=", "<>", "a:b:", "%41")


def _dsn(userinfo: str, tail: str = "db:5432/x") -> str:
    # Assembled here so no source line holds a URL with an embedded password.
    return "postgresql://" + userinfo + "@" + tail


def _quoted(value: str, mark: str) -> str:
    escaped = value.replace(BACKSLASH, BACKSLASH * 2).replace(mark, BACKSLASH + mark)
    return mark + escaped + mark


def _key_variant(rng: random.Random, key: str) -> str:
    choice = rng.randrange(8)
    if choice == 0:
        return key.upper()
    if choice == 1:
        return "".join(char.upper() if rng.random() < 0.5 else char for char in key)
    if choice == 2:
        index = rng.randrange(len(key))
        return key[:index] + f"%{ord(key[index]):02x}" + key[index + 1 :]
    if choice == 3:
        return "".join(f"%{ord(char):02X}" for char in key)
    if choice == 4:
        index = rng.randrange(len(key))
        return key[:index] + BACKSLASH + f"u{ord(key[index]):04x}" + key[index + 1 :]
    if choice == 5:
        return "x_" + key + "_v2"
    if choice == 6:
        return f"user[{key}]"
    return key


def _credential(rng: random.Random, secret: str) -> str:
    """The secret, written as a credential in one of twenty syntaxes."""
    key = _key_variant(rng, rng.choice(KEYS))
    value = (
        rng.choice(MASK_LOOKALIKES)
        + rng.choice(VALUE_PREFIXES)
        + secret
        + rng.choice(VALUE_SUFFIXES)
    )
    before, after = rng.choice(WHITESPACE), rng.choice(WHITESPACE)
    style = rng.randrange(20)
    if style == 0:
        return f"host=h {key}{before}={after}{_quoted(value, APOSTROPHE)} dbname=x"
    if style == 1:
        return f"{key}{before}={after}{_quoted(value, chr(34))} next=1"
    if style == 2:
        return f"{key}{before}:{after}{_quoted(value, chr(34))}"
    if style == 3:
        return f"https://h.test/cb?a=1&{key}={quote(value, safe='')}&z=2"
    if style == 4:
        return f"https://h.test/cb?a=1&{key}={quote(value, safe=APOSTROPHE + '[]@:')}"
    if style == 5:
        return _dsn("user:" + quote(value, safe="'[]!$&()*+,;="))
    if style == 6:
        return _dsn("user:" + value.replace("@", "%40"))
    if style == 7:
        return json.dumps({key: value, "ok": 1})
    if style == 8:
        return repr({key: value, "ok": 1})
    if style == 9:
        escaped = value.replace(" ", BACKSLASH + " ").replace("\t", BACKSLASH + "\t")
        return f"{key}{before}={after}{escaped}"
    if style == 10:
        doubled = value.replace(APOSTROPHE, APOSTROPHE * 2)
        return f"ALTER ROLE r {key}{before or ' '}{APOSTROPHE}{doubled}{APOSTROPHE}"
    if style == 11:
        return f"{key}{before}:{after}{value}"
    if style == 12:
        return f"Authorization{before}:{after}Bearer {value.replace(' ', '')}"
    if style == 13:
        return f"cmd --{key}{before or ' '}{_quoted(value, APOSTROPHE)} --x 1"
    if style == 14:
        pair = f"({_quoted(key, APOSTROPHE)},{after}{_quoted(value, APOSTROPHE)})"
        return f"[{pair}, ('ok', 1)]"
    if style == 15:
        return f"<{key}>{value.replace('<', '')}</{key}>"
    if style == 16:
        return f"https://h.test/cb#{key}={quote(value, safe='')}&state=1"
    if style == 17:
        junk = rng.choice(URL_JUNK)
        return "redis://:" + junk + secret + junk + "@cache:6379/0"
    if style == 18:
        inner = "amqp://u:" + rng.choice(("'", "p/", "p?", "")) + secret + "@mq/v"
        return "https://proxy.test/?next=" + inner + "&x=1"
    return "user:" + rng.choice(("'", '"', "p", "[1]")) + secret + "@tcp(db:3306)/app"


def _wrap(rng: random.Random, text: str) -> str:
    """Zero to four layers of the encodings and containers text passes through."""
    for _ in range(rng.randrange(5)):
        choice = rng.randrange(13)
        if choice == 0:
            text = json.dumps({"wrapper": text})
        elif choice == 1:
            text = json.dumps(text)
        elif choice == 2:
            text = "prefix " + text + " suffix"
        elif choice == 3:
            text = "/cb?next=" + quote(text, safe="")
        elif choice == 4:
            text = json.dumps([text, {"n": text}])[1:]
        elif choice == 5:
            text = "{" * rng.randrange(40) + text
        elif choice == 6:
            text = repr(text)
        elif choice == 7:
            text = "line one\n    " + text + "\nline three"
        elif choice == 8:
            text = html.escape(text)
        elif choice == 9:
            text = "note=" + text
        elif choice == 10:
            text = quote(text, safe="/:?=&")
        elif choice == 11:
            text = text.encode("unicode_escape").decode("ascii")
    return text


def _graph(rng: random.Random, secret: str, text: str) -> object:
    shared: dict[str, object] = {_key_variant(rng, rng.choice(KEYS)): secret, "detail": text}
    graph: object = shared
    for _ in range(rng.randrange(5)):
        graph = rng.choice(
            ([graph, graph], {"a": graph, "b": [graph]}, (graph, text), {text: graph})
        )
    return graph


@pytest.mark.parametrize("seed", [20261007, 1, 2, 3])
def test_generated_credential_representations_never_leak(seed: int) -> None:
    # Deterministic, reproducible generation; not a security use of random.
    rng = random.Random(seed)  # noqa: S311
    leaks: list[str] = []
    for index in range(2_500):
        secret = "D0LEAK" + secrets.token_hex(8)
        text = _wrap(rng, _credential(rng, secret))
        if secret in scrub_text(text):
            leaks.append(text)
        if index % 4 == 0 and secret in json.dumps(sanitize(_graph(rng, secret, text))):
            leaks.append(text)
    assert not leaks, f"{len(leaks)} leaking forms with seed {seed}; first: {leaks[0]!r}"


def _two_copies(text: str) -> str:
    return json.dumps([text, {"n": text}])[1:]


# Classes found by the generator, in readable form.
REGRESSIONS: list[tuple[str, Form]] = [
    ("repr-with-escaped-newline-before-equals", lambda s: repr(f"db_password\n=\t'a {s}'\"")),
    ("json-string-with-escaped-tab-after-equals", lambda s: json.dumps(f"token \t = \t {s}")),
    ("repr-of-json-with-escaped-crlf", lambda s: repr(json.dumps(f"secret\n:\r\n a {s}'"))),
    (
        "escaped-tab-then-mask-lookalike",
        lambda s: json.dumps(f"user[password]= \t [REDACTED]a@b:{s}"),
    ),
    ("escaped-nbsp-then-quoted-value", lambda s: repr(f"api_key=\u00a0 'a {s}'\"")),
    (
        "re-escaped-backslash-space",
        lambda s: json.dumps(f"sslpassword = [REDACTED]{BACKSLASH} pre{BACKSLASH} {s}"),
    ),
    (
        "key-escaped-twice",
        lambda s: json.dumps("pw" + BACKSLASH + "u0064 = " + f"'a {s}'"),
    ),
    (
        "key-escaped-twice-in-dict-repr",
        lambda s: "prefix " + repr({"authorizatio" + BACKSLASH + "u006e": f"a#b{s}"}) + " suffix",
    ),
    (
        "span-swallowing-the-next-key",
        lambda s: repr(_two_copies(f"PASSWORD   =   [TRUNCATED]a{BACKSLASH}\"b{s}'")),
    ),
    (
        "span-swallowing-the-next-key-escaped-tab",
        lambda s: repr(_two_copies(f"token \t =[REDACTED]{BACKSLASH}ta=b{BACKSLASH} {s}'")),
    ),
    (
        "quote-behind-several-backslashes",
        lambda s: json.dumps(
            _two_copies(f"host=h refresh_token =\t'[REDACTED]\ta=b {s}{BACKSLASH * 2}' dbname=x")
        ),
    ),
    (
        "separator-less-value-with-escaped-quote",
        lambda s: repr(f"ALTER ROLE r TOKEN '[REDACTED]a&b{s}\"'"),
    ),
    (
        "url-password-with-space-and-escaped-quotes",
        lambda s: repr(_dsn(f"user:'[REDACTED]'pre {s}\"")),
    ),
    (
        "html-escaped-url-with-encoded-whitespace",
        lambda s: html.escape(f"https://h.test/cb?a=1&access_token=[REDACTED]%09a'b{s}'"),
    ),
    (
        "character-references-then-percent-encoding",
        lambda s: "note=" + quote(html.escape(json.dumps({"api_key": f"a&b{s}'"})), safe=":"),
    ),
    (
        "percent-encoding-twice-around-references",
        lambda s: (
            "/cb?next=" + quote(quote(html.escape(json.dumps({"api_key": s})), safe=""), safe="")
        ),
    ),
    (
        "key-hidden-and-separator-masked-as-authority",
        lambda s: "db_pass" + BACKSLASH + f'u0077ord\u00a0:"a@b:{s}"',
    ),
    (
        "encoded-key-token-followed-by-its-value",
        lambda s: json.dumps(f"host=h pass%77ord\u00a0=\r\n 'a {s}' dbname=x"),
    ),
    (
        "percent-encoded-xml-with-tab",
        lambda s: "/cb?next=" + quote(f"<access_token>[REDACTED]\t{s}</access_token>", safe=""),
    ),
    ("xml-with-subscripted-key", lambda s: f"<user[password]>a=b {s} tail</user[password]>"),
    (
        "four-layers-of-encoding",
        lambda s: quote(html.escape(repr(json.dumps({"wrapper": f"password = 'a {s}'"}))), safe=""),
    ),
]


def _configure(log_format: str) -> None:
    configure_logging(
        service_name="voice-agent-test", environment="test", log_level="INFO", log_format=log_format
    )


@pytest.fixture
def sentinel() -> str:
    return "D0LEAKSENTINEL" + secrets.token_hex(12)


@pytest.mark.parametrize("log_format", ["json", "console"])
@pytest.mark.parametrize(("form_id", "form"), REGRESSIONS, ids=[name for name, _ in REGRESSIONS])
def test_generator_found_classes_stay_closed_on_every_channel(
    capsys: pytest.CaptureFixture[str], sentinel: str, form_id: str, form: Form, log_format: str
) -> None:
    text = form(sentinel)
    assert sentinel in text
    assert sentinel not in scrub_text(text), form_id
    _configure(log_format)
    log = get_logger("tests.fuzz")
    log.info(text)
    log.info("event", detail=text, nested={"items": [text], text: text})
    logging.getLogger("tests.stdlib").warning(text)
    logging.getLogger("uvicorn.error").warning("failed: %s / %r", text, text)
    try:
        raise RuntimeError(text)
    except RuntimeError as exc:
        log.exception("failed", error=exc)
        logging.getLogger("asyncio").exception("Task exception was never retrieved: %s", text)
    captured = capsys.readouterr()
    assert captured.out.count("\n") >= 6
    assert captured.out.count(sentinel) == 0, form_id
    assert captured.err.count(sentinel) == 0, form_id


def test_escaped_whitespace_delimits_like_whitespace_and_only_the_value_is_masked(
    sentinel: str,
) -> None:
    # Without this rule the escape itself would be taken for the value; a decoded
    # view would still catch that, but only by masking the whole string.
    # (An escaped tab or newline would decode to a control character, and a
    # credential beside one masks the whole string; an escaped space does not.)
    gap = BACKSLASH + "x20"
    text = f'"host=h token {gap}={gap} {sentinel} dbname=x"'
    scrubbed = scrub_text(text)
    assert sentinel not in scrubbed
    assert scrubbed.startswith('"host=h token ')
    assert scrubbed.endswith(' dbname=x"')


def test_a_quote_behind_several_backslashes_leaves_the_value_undelimited(sentinel: str) -> None:
    # Closed at depth one, still open at depth two: the rest is masked either way.
    text = "host=h password='a" + BACKSLASH * 2 + f"' x {sentinel}' dbname=x"
    assert scrub_text(text) == "host=h password='[REDACTED]"
