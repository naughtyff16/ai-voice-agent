"""Fail-closed sanitisation of everything that reaches a log line (3A §12.4, 6A §22).

Every value is rebuilt from scratch rather than filtered in place: the result
contains only ``None``, ``bool``, ``int``, ``float``, ``str``, ``list`` and
``dict`` (exact built-in types, never a subclass), so a renderer never has to
fall back to ``repr()`` of an object it does not understand. Anything the
sanitiser cannot prove safe is replaced by a fixed marker. Nothing here ever
returns an original container or object, and no public entry point can raise.

Invariants
    * A mask is never trusted because of how a value *looks*. Text that starts
      with, ends with or contains ``[REDACTED]`` is ordinary text and is
      scrubbed like any other; no rule skips a value because it resembles one
      that was already masked.
    * No recognition rule depends on a fixed amount of whitespace, a fixed
      number of escapes or a hand-written set of "allowed" characters.
      Key/value pairs, quoted values and URLs are read by deterministic
      scanners whose work is linear in the input.
    * Every limit affects fidelity, never confidentiality. When a nesting,
      work or output limit is reached, what has not been examined is replaced
      by a marker; the original is never emitted in its place.

Whole-event budget
    One ``_Budget`` is shared by every value of one ``sanitize`` call:

    * ``MAX_EVENT_FIELDS`` fields admitted; the rest are never visited;
    * ``MAX_EVENT_NODES`` values visited (containers, scalars, markers);
    * ``MAX_EVENT_SCAN`` characters of text examined, counting every pass
      (nested JSON, decoded views);
    * ``MAX_EVENT_OUTPUT`` characters rendered: every scalar is charged the
      length it is actually rendered with, plus the separators and brackets
      around it. A scalar is never rendered, converted or copied in order to
      be measured: a string (or subclass of it) by the length the base type
      reports, an integer by its bit length, a Decimal by the size the object
      reports and only then by rounding to a fixed precision.

    The fields an event cannot do without (its name, its traceback, its
    stack) are sanitised first and outside the field limit
    (``sanitize_event``, ``leading``), so no number of other fields displaces
    them.

    These are deterministic work limits, not timers. Containers are also
    limited individually (``MAX_DEPTH``, ``MAX_ITEMS``) and strings by
    ``MAX_STRING_LENGTH``. Input is iterated lazily and never copied first, so
    what lies beyond a limit is not visited at all.

Shared references
    A container is expanded once per event. Meeting it again while it is being
    expanded yields ``[CYCLE]``; meeting it again afterwards yields
    ``[REPEATED]``. A graph of shared references therefore costs what its
    distinct containers cost, not what its expansion would.

Text, in layers
    1. *Embedded JSON.* Every JSON object or array found in the string is
       parsed and passed through the structured sanitiser, then re-serialised;
       strings inside it are scrubbed the same way, so JSON nested in JSON is
       unwrapped until nothing is left to unwrap. Parsing has a work allowance
       and unwrapping a nesting limit; beyond either, the unexamined JSON is
       masked whole. While the text rules below run, a sanitised fragment is an
       opaque placeholder: they neither re-read it as text nor split it.
    2. *Token forms.* PEM private keys, bearer credentials and JWTs.
    3. *URLs.* For each ``scheme://`` the authority is delimited as a URL
       parser would; the whole userinfo is masked, whatever characters it
       contains. Query and fragment parameters are split on ``&`` and their
       percent-decoded keys classified. An authority that looks like it
       carries a password but cannot be delimited is masked.
    4. *Key/value pairs.* A scanner finds sensitive keys and the value that
       follows (``key=value``, ``key: value``, ``'key', 'value'``,
       ``KEY 'value'``, ``--key value``, ``<key>value<``): libpq keyword
       strings, headers, dict reprs, malformed JSON. The key is classified by
       its meaning after decoding. The value is delimited by a state machine
       that honours quotes, backslash escapes and brackets; where it cannot be
       delimited, the rest of the line or string is masked.
    5. *Bare authorities.* ``user:password@host`` without a scheme.
    6. *Decoded views.* The original text is decoded (percent, backslash,
       character-reference and compatibility forms; whole, and token by token)
       round by round, and each decoded form is scrubbed on its own. Whatever
       the scrubbed raw text still shows must also be shown by every such
       view. If a view masks something the raw rules left readable, or the
       text cannot be decoded to a fixed point within the allowed rounds, the
       whole string is masked.

    7. *Ambiguity.* The rules above read one grammar at a time, and grammars
       disagree about control characters and non-ASCII whitespace: libpq keeps
       an EM SPACE inside an unquoted value, its URI parser keeps a tab or a
       newline inside a password, URL libraries delete tabs and newlines
       before parsing, and a folded header continues on the next line. A
       string in which any rule masked something (as written, or with those
       characters removed) and which contains such a character is therefore
       replaced whole. So is a string too long to examine in full if the
       examined part shows any sign of a credential
       (``[TRUNCATED_SENSITIVE_VALUE]``): no classification is ever made from
       a prefix whose delimiters may lie beyond the cut.

Trust boundary
    * *Untrusted:* every string, whatever it claims to be; exception text;
      every object. Objects are never converted with ``str()``, ``repr()``,
      ``format()`` or a method a subclass could override. ``str``, ``int`` and
      ``float`` subclasses are read through the base type's own slots; the
      other supported scalars (UUID, Decimal, dates, times, paths, bytes) are
      rendered only for their exact type; everything else becomes
      ``[UNSUPPORTED]``. The one conversion that does run is ``str()`` of an
      exception, the only way to obtain its message; the result is untrusted
      text like any other.
    * *Trusted identifiers:* logger, service and environment names, levels,
      timestamps and request IDs are accepted only when they match a short,
      conservative grammar (``trusted_identifier``); anything else is replaced
      by a fixed word. No prefix of a rejected identifier is kept.
    * *Trusted text:* none. No type, marker, prefix or attribute makes a
      value exempt: every string that enters a public function is scrubbed,
      whoever produced it, including this module's own earlier output. A
      Python class says nothing about where a value came from (anyone can
      construct one), so nothing here hands out an object that a later call
      would believe. Passing output through a second time therefore costs a
      second scrub; it is safe because every unit this module emits is one the
      text rules leave unchanged or mask further.

Capability fields
    A signed or presigned media/storage URL is a bearer capability whatever
    its text looks like (6A §22); it need not contain "signature" or "token".
    Such values are recognised by the *name of the field* that carries them
    (``download_url``, ``upload_url``, ``presigned_url``, ``recording_url``,
    ...; ``_CAPABILITY_KEY``) and masked whole, in structured data, in
    embedded JSON and after ``key=``/``key:`` in text.

    A URL whose query or fragment shows it to be signed is recognised
    wherever it stands and replaced whole, from its scheme to the end of its
    last parameter: AWS (``X-Amz-*``; ``AWSAccessKeyId`` with ``Signature``),
    CloudFront (``Signature``, ``Key-Pair-Id``, with ``Expires`` or
    ``Policy``), Azure SAS (``sig`` with ``sv``, ``se``, ``sp``, ``sr``,
    ``st``), Google Cloud (``X-Goog-*``; ``GoogleAccessId``), Alibaba OSS
    (``X-Oss-*``; ``OSSAccessKeyId``), Tencent COS (``q-signature``). The
    parameters are read as a set: one signature or signing-key parameter
    makes the path and every other parameter (expiry, policy, scope, key
    identifier) part of the capability, whatever their order or spelling. A
    bare capability URL in free text, with no field name and no signing
    parameter, cannot be told from an ordinary URL and is not claimed to be
    detected: such URLs must be logged, if at all, under a field name.

Exceptions and tracebacks
    An exception is rendered as type plus scrubbed message, and a validation
    error is summarised from its error list without the rejected input. A
    traceback is *constructed*, never formatted and then cleaned: the frames
    are read as metadata (``co_filename``, line number, ``co_name``), and

    * a filename is measured before it is read; one longer than
      ``_MAX_FILENAME_LENGTH`` is replaced by a fixed word without being
      copied, formatted or scanned;
    * the complete filename is then validated as one unit: it must be
      printable, hold no quote, control character or ambiguous whitespace,
      and be left unchanged by the text rules. Otherwise it is replaced by a
      fixed word; no part of it is kept;
    * the function name is accepted by grammar or replaced, the line number
      is an integer, and source lines are never read or shown;
    * the finished frame line must itself be unchanged by the text rules, or
      a fixed line replaces it.

    The result is one complete text in the standard layout
    (``traceback_text``, ``stack_text``), bounded in frames walked, frames
    kept, lines and length before a line is built. It has no standing with
    the sanitiser, which reads it whole like any other string, so it is built
    to be a text the sanitiser emits unchanged, and that is checked on the
    complete text: each frame line as it stands with a line after it, and
    then the assembled traceback. A message that does not survive that check
    in the company of the other lines is withheld (``TypeName: [REDACTED]``);
    the frames and the exception types remain.

Assembled fields
    A field that is laid out as one text (``exception``, ``stack``) may be
    handed a list of lines by a caller. The fragments are joined into that
    text *before* it is sanitised (``_assembled_text``), bounded in number,
    depth and length, and the complete text is then sanitised as one string.
    Nothing is joined after the sanitiser has run: joining two values that
    were sanitised apart can put a credential back together (a header and its
    folded continuation, a URI and the rest of its password).
"""

from __future__ import annotations

import datetime as dt
import enum
import html
import json
import re
import types
import unicodedata
import uuid
import zoneinfo
from collections import deque
from collections.abc import Callable, Iterable, Mapping
from decimal import MAX_EMAX, MIN_EMIN, Context, Decimal, Inexact, Rounded
from itertools import islice
from pathlib import PosixPath, PurePosixPath, PureWindowsPath, WindowsPath
from typing import Any, Final
from urllib.parse import unquote, unquote_plus

from pydantic import SecretBytes, SecretStr

REDACTED: Final = "[REDACTED]"
TRUNCATED: Final = "[TRUNCATED]"
CYCLE: Final = "[CYCLE]"
REPEATED: Final = "[REPEATED]"
UNREADABLE: Final = "[UNREADABLE]"
UNSUPPORTED: Final = "[UNSUPPORTED]"
TRUNCATED_SENSITIVE: Final = "[TRUNCATED_SENSITIVE_VALUE]"

# Per-value limits.
MAX_DEPTH: Final = 8
MAX_ITEMS: Final = 200
# Fields of one event that are admitted at all; the rest are never visited.
MAX_EVENT_FIELDS: Final = MAX_ITEMS
MAX_STRING_LENGTH: Final = 16_384
# Whole-event limits (see the module docstring). A normal event uses a few
# dozen nodes and a few kilobytes; these leave room for a full traceback and a
# sizeable payload while keeping one event's work and output bounded.
MAX_EVENT_NODES: Final = 2_048
MAX_EVENT_SCAN: Final = 524_288
MAX_EVENT_OUTPUT: Final = 65_536
# JSON nested in JSON strings doubles its escaping at every level, so a string
# of MAX_STRING_LENGTH cannot hold this many levels; the limit exists so that
# unwrapping is bounded by construction, and reaching it masks the remainder.
MAX_JSON_NESTING: Final = 16
# Characters a JSON parse attempt may consume per character of the string.
_JSON_WORK_FACTOR: Final = 8
_MAX_DECODE_ROUNDS: Final = 3
_MAX_VIEW_LENGTH: Final = 4 * MAX_STRING_LENGTH
_MAX_KEY_LENGTH: Final = 256
_MAX_SUBSCRIPT_LENGTH: Final = 64
_MAX_SWALLOWED_KEYS: Final = 8
_MAX_INT_BITS: Final = 128
_MAX_DECIMAL_DIGITS: Final = 40
# What a Decimal object may report as its own size before it is read at all. A
# coefficient of _MAX_DECIMAL_DIGITS digits fits in the object itself; a larger
# one lives in an allocation the object counts in ``__sizeof__``.
_MAX_DECIMAL_SIZE: Final = 256
_MAX_SCALAR_TEXT: Final = 64
_MAX_MESSAGE_LENGTH: Final = 2_048
_MAX_EXCEPTION_CHAIN: Final = 10
_MAX_SUB_EXCEPTIONS: Final = 5
_MAX_SUMMARY_ERRORS: Final = 20
# Tracebacks: the innermost frames kept per exception, the links followed to
# find them, and the lines and characters of one rendered traceback. The
# length stays below MAX_STRING_LENGTH so that the assembled text is examined
# in full, as one string, by every later pass.
_MAX_TRACEBACK_FRAMES: Final = 32
_MAX_TRACEBACK_WALK: Final = 4_096
_MAX_TRACEBACK_LINES: Final = 192
_MAX_TRACEBACK_LENGTH: Final = MAX_STRING_LENGTH - 64
_MAX_DESCRIPTION_LENGTH: Final = 8_192
# A longer filename is not read at all.
_MAX_FILENAME_LENGTH: Final = 512
_MAX_IDENTIFIER_LENGTH: Final = 128
_QUERY_LOOKBACK: Final = 4_096
# Rendered size of what surrounds a value: ", " between items, the brackets of
# a container, ": " after a key.
_SEPARATOR_COST: Final = 2
_BUDGET_NOTE: Final = "event budget exhausted"
_FIELDS_NOTE: Final = "event field limit reached"

# Fields whose value is a bearer capability whatever it looks like (6A §22):
# signed/presigned URLs and the media and storage locations that are handed
# out as such. The name of the field decides; the value is never inspected for
# a "signature" or "token", which a capability URL need not contain. Matches
# snake_case, kebab-case and camelCase (download_url, uploadUrl, MediaUrl0).
_CAPABILITY_KEY: Final = (
    r"pre[_-]?sign|signed[_-]?(?:ur[li]|link|href|request)|sas[_-]?ur[li]|result[_-]?ref"
    r"|(?:download|upload|recording|media|playback|stream|audio|voicemail|transcript|export"
    r"|storage|object|blob|bucket|(?<!pro)file|attachment|artifact)[_-]?(?:ur[li]|link|href)"
)
# Field names whose values never reach a log line (6A §22: phone_number, email,
# token, password, secret) plus credential-bearing transport fields.
_SENSITIVE_KEY: Final = re.compile(
    r"passw(?:or)?d|passphrase|pwd|secret|token|authori[sz]ation|cookie|api[_-]?key"
    r"|credential|private[_-]?key|signature|session[_-]?(?:id|key)|access[_-]?key"
    r"|key[_-]?pair[_-]?id|google[_-]?access[_-]?id"
    r"|dsn|conninfo|connection[_-]?string|phone|email|" + _CAPABILITY_KEY,
    re.IGNORECASE,
)
# Keys recognised inside free text. Narrower than the structured list: prose
# mentions e-mail addresses and phone numbers without carrying one.
_SENSITIVE_TEXT_KEY: Final = re.compile(
    r"passw(?:or)?d|passphrase|pwd|secret|token|authori[sz]ation|cookie|api[_-]?key|apikey"
    r"|credential|private[_-]?key|signature|session[_-]?(?:id|key)|access[_-]?key"
    r"|key[_-]?pair[_-]?id|google[_-]?access[_-]?id|" + _CAPABILITY_KEY,
    re.IGNORECASE,
)
# Query parameters that show a URL to be signed (6A §22): a signature, or the
# identity of the key that made it. The provider namespaces of AWS SigV4,
# Google Cloud and Alibaba OSS; Azure SAS ("sig"); CloudFront ("Signature",
# "Key-Pair-Id"); the access-key forms of AWS SigV2, Google Cloud V2 and OSS
# V1; Tencent COS ("q-..."). One of them makes the whole URL a capability:
# its path, expiry, policy and scope parameters go with the signature.
_SIGNING_PARAMETER: Final = re.compile(
    r"sig|signature|x-(?:amz|goog|oss)-[\w\-]*|key-pair-id|security-token"
    r"|(?:aws|oss)accesskeyid|googleaccessid|q-(?:signature|sign-algorithm|sign-time|key-time|ak)",
    re.IGNORECASE,
)
_SCHEME_CHARACTERS: Final = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+.-"
)
# Header-like keys whose whole line is the credential ("Authorization: Basic ...").
_HEADER_KEY: Final = re.compile(r"authori[sz]ation|cookie", re.IGNORECASE)

# The patterns below only ever match runs of one character class or a literal
# followed by disjoint classes, so none of them can backtrack super-linearly.
_KEY_RUN: Final = re.compile(r"[\w.\-%]+")
_TOKEN: Final = re.compile(r"\S+")
_WHITESPACE: Final = re.compile(r"\s")
_NEWLINE: Final = re.compile(r"[\r\n]")
# What ends an unquoted libpq value in every build: the C-locale isspace() set.
# str.isspace() is wider (EM SPACE, NBSP, U+001C, ...), and libpq keeps those
# characters in the value.
_VALUE_DELIMITERS: Final = " \t\n\r\v\f"
# Characters about which the grammars read here disagree (see "Ambiguity" in
# the module docstring): C0/C1 controls, non-ASCII whitespace, line and
# paragraph separators, invisible format characters.
_AMBIGUOUS: Final = re.compile(
    "[\x00-\x1f\x7f-\xa0\xad\u1680\u180e\u2000-\u200f\u2028-\u202f\u205f-\u2064\u3000\ufeff]"
)
# In text too long to examine in full: anything whose meaning could depend on
# what was cut off.
_CUT_INDICATOR: Final = re.compile(
    r"://|@|passw|pwd|secret|token|authori|cookie|credential|key|signature|session|bearer|eyJ",
    re.IGNORECASE,
)
# Digest credentials written without their header name: the rest of the line.
_DIGEST: Final = re.compile(r"\b(?P<scheme>digest)\s+(?=[A-Za-z]+\s*=)[^\r\n]*", re.IGNORECASE)
_JSON_OPENER: Final = re.compile(r"[{\[]")
_AUTHORITY_END: Final = re.compile(r"[/?#]")
_QUERY_START: Final = re.compile(r"[?#]")
_PARAMETER_END: Final = re.compile(r"[&#]")
_SIGNED_PARAMETER_END: Final = re.compile(r"[&#?]")
# What may follow "host:" in an authority that carries no password: a port,
# optionally more "host:port" entries (multi-host URLs).
_PORTS: Final = re.compile(r"\d*(?:,[^:,@]*(?::\d*)?)*")
_DRIVE_PATH: Final = re.compile(r"[\"'(\[]*[A-Za-z]:[\\/]")
_JWT_RUN: Final = re.compile(r"[A-Za-z0-9_.\-]+")
_PEM: Final = re.compile(
    r"-----BEGIN [A-Z ]{0,40}PRIVATE KEY-----.*?(?:-----END [A-Z ]{0,40}PRIVATE KEY-----|$)",
    re.DOTALL,
)
# Bearer credentials: everything up to the next whitespace.
_BEARER: Final = re.compile(r"\b(?P<scheme>bearer)\s+\S+", re.IGNORECASE)
# "token <value>" where the value is token-shaped (long, contains a digit).
_TOKEN_VALUE: Final = re.compile(
    r"\b(?P<scheme>token)\s+(?=[A-Za-z0-9\-._~+/]{0,256}\d)[A-Za-z0-9\-._~+/]{16,}=*",
    re.IGNORECASE,
)
# Escaped quotes are deliberately not decoded: a view in which they had become
# bare quotes would no longer show where a quoted value ends.
# One backslash escape, read left to right: "\\u0041" is an escaped backslash
# followed by "u0041", which only a second round of decoding turns into "A".
_BACKSLASH_ESCAPE: Final = re.compile(
    r"\\(?:u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|U([0-9a-fA-F]{8})|([\\/ntrfv]))"
)
_SIMPLE_ESCAPES: Final = {"n": "\n", "t": "\t", "r": "\r", "f": "\f", "v": "\v"}
# A complete character reference only. A reference cut short by another
# encoding ("&quot%3B") is left for the round in which it has become whole.
_ENTITY: Final = re.compile("&(?:#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});")
# Characters that render as nothing and could split a key from its separator.
_INVISIBLE: Final = re.compile("[\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff]")
_HEX: Final = re.compile(r"[0-9a-fA-F]+")
_TYPE_NAME: Final = re.compile(r"[A-Za-z_][A-Za-z0-9_.<>]{0,127}")
# A function name as the interpreter writes it: an identifier, "<module>", "<lambda>".
_FRAME_NAME: Final = re.compile(r"[A-Za-z_<][A-Za-z0-9_.<>]{0,127}")
_TRACEBACK_HEADER: Final = "Traceback (most recent call last):"
_STACK_HEADER: Final = "Stack (most recent call last):"
_CAUSE_LINK: Final = "The above exception was the direct cause of the following exception:"
_CONTEXT_LINK: Final = "During handling of the above exception, another exception occurred:"
# What stands for a frame's filename or function name that is not shown.
_UNKNOWN_FILE: Final = "<unknown file>"
_LONG_FILE: Final = "<filename too long>"
_UNSAFE_FILE: Final = "<unsafe filename>"
_UNKNOWN_NAME: Final = "<unknown>"
# Grammars of the identifiers a log line is labelled with (trusted_identifier).
_IDENTIFIER_GRAMMARS: Final[Mapping[str, re.Pattern[str]]] = {
    # A Python logger name: dotted identifiers.
    "logger": re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*"),
    "service": re.compile(r"[A-Za-z0-9][A-Za-z0-9_.\-]*"),
    "environment": re.compile(r"[A-Za-z0-9][A-Za-z0-9_.\-]*"),
    "level": re.compile(r"[A-Za-z]+|[Ll]evel [0-9]{1,4}"),
    "timestamp": re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]{5,15}(?:Z|[+\-][0-9:]{2,5})?"),
    "request_id": re.compile(r"[A-Za-z0-9][A-Za-z0-9_.\-]*"),
}
_JSON: Final = json.JSONDecoder()
_ABSENT: Final = object()

# Private-use characters delimiting the placeholder of a sanitised JSON
# fragment. They are removed from every input before placeholders are made, so
# no input can forge one.
_FRAGMENT_OPEN: Final = "\ue000"
_FRAGMENT_CLOSE: Final = "\ue001"
_FRAGMENT: Final = re.compile("\ue000([0-9]+)\ue001")
_NO_FRAGMENT_MARKS: Final = str.maketrans({"\ue000": "\ufffd", "\ue001": "\ufffd"})

_QUOTES: Final = "\"'"
_OPENERS: Final = "([{"
_CLOSERS: Final = ")]}"
# What may sit between a key and its separator: a closing quote (possibly
# escaped), closing brackets, a form-encoded space.
_KEY_TRAILERS: Final = "\\\"'])}+"
_STRING_PREFIXES: Final = "bBuUrReE"


class _Budget:
    """The work and output allowance shared by every value of one sanitisation."""

    __slots__ = ("active", "nodes", "output", "scan", "seen")

    def __init__(self) -> None:
        self.nodes = MAX_EVENT_NODES
        self.scan = MAX_EVENT_SCAN
        self.output = MAX_EVENT_OUTPUT
        # Containers being expanded (cycles) and every container expanded so
        # far (repeats). The object is kept so its id cannot be reused.
        self.active: set[int] = set()
        self.seen: dict[int, object] = {}

    @property
    def exhausted(self) -> bool:
        return self.nodes <= 0 or self.output <= 0

    def charge(self, rendered_length: int, nesting: int) -> bool:
        """Charge the rendered size of one value and the separator that follows it.

        False if the value does not fit in what is left: the budget is then
        spent and the caller emits a marker instead of the value.
        """
        if nesting:
            return True
        cost = rendered_length + _SEPARATOR_COST
        if cost > self.output:
            self.output = 0
            return False
        self.output -= cost
        return True


# ---------------------------------------------------------------- public entry points


def scrub_text(text: str) -> str:
    """Return ``text`` with every recognised credential form masked. Never raises."""
    try:
        return _scrub(text, _Budget(), 0)
    except Exception:  # noqa: BLE001 — text that cannot be scrubbed is not emitted
        return UNREADABLE


def sanitize(value: object) -> object:
    """A JSON-safe copy of ``value`` with every secret masked. Never raises."""
    try:
        return _sanitize(value, 0, _Budget(), 0)
    except Exception:  # noqa: BLE001 — a value that cannot be sanitised is not emitted
        return UNREADABLE


def sanitize_event(
    event: Mapping[Any, Any],
    *,
    skip: frozenset[str] = frozenset(),
    leading: tuple[str, ...] = (),
    assembled: frozenset[str] = frozenset(),
) -> dict[str, object]:
    """A sanitised copy of the fields of one log event, except those named in ``skip``.

    The fields named in ``leading`` are looked up by name and sanitised first.
    They take from the event budget before any other field can, and do not
    count towards the field limit: what an event is called, and the traceback
    that explains it, cannot be displaced by however many other fields the
    caller sends. Being named there is a matter of priority only. A leading
    field is as untrusted as any other and is sanitised the same way.

    The rest of the mapping is iterated lazily and never copied: at most
    ``MAX_EVENT_FIELDS`` fields are admitted, and once that limit or the event
    budget is reached the remaining entries are not visited, referenced or
    rendered.

    A field named in ``assembled`` is one that is laid out as a single text
    (a traceback, a stack). Whatever it holds is assembled into that text
    *before* it is sanitised (``_assembled_text``), so the sanitiser reads the
    text exactly as it will be emitted and nothing is joined afterwards.

    Every value is untrusted, whatever its type and whether or not an earlier
    call returned it. May raise; the caller replaces the event with a fixed
    record.
    """
    budget = _Budget()
    result: dict[str, object] = {}
    for key in leading:
        value = event.get(key, _ABSENT)
        if value is not _ABSENT:
            result[key] = _sanitize_field(key, value, budget, assembled)
    _sanitize_entries(
        event,
        0,
        budget,
        0,
        result,
        MAX_EVENT_FIELDS,
        skip.union(leading),
        _FIELDS_NOTE,
        assembled,
    )
    return result


def trusted_identifier(value: object, kind: str, fallback: str) -> str:
    """``value`` if it is a well-formed identifier of ``kind``, else ``fallback``.

    Identifiers label a log line (logger, service, environment, level,
    timestamp, request ID) and also appear in the emergency diagnostics, so
    they are accepted by grammar rather than cleaned up: an exact ``str`` of
    bounded length that matches the grammar of its kind and that the text
    rules leave untouched. Anything else is replaced by ``fallback`` whole; no
    part of a rejected value is kept, and it is never converted or cut first.
    Never raises.
    """
    try:
        if type(value) is not str or not 0 < len(value) <= _MAX_IDENTIFIER_LENGTH:
            return fallback
        if _IDENTIFIER_GRAMMARS[kind].fullmatch(value) is None:
            return fallback
        return value if _scrub(value, _Budget(), 0) == value else fallback
    except Exception:  # noqa: BLE001 — an identifier that cannot be checked is not emitted
        return fallback


def is_sensitive_key(key: str) -> bool:
    """True if ``key`` names sensitive data, as written or in any decoded form."""
    return _names_sensitive_data(key, _SENSITIVE_KEY)


# ---------------------------------------------------------------- decoding


def _unescape(match: re.Match[str]) -> str:
    simple = match.group(4)
    if simple is not None:
        return _SIMPLE_ESCAPES.get(simple, simple)
    code = int(match.group(1) or match.group(2) or match.group(3), 16)
    return chr(code) if code <= 0x10FFFF else match.group(0)


def _decode_once(text: str) -> str:
    if "\\" in text:
        text = _BACKSLASH_ESCAPE.sub(_unescape, text)
    if "%" in text:
        text = unquote(text)
    if "&" in text:
        text = _ENTITY.sub(lambda match: html.unescape(match.group(0)), text)
    if not text.isascii():
        text = _INVISIBLE.sub("", unicodedata.normalize("NFKC", text))
    return text


def _decoded_forms(text: str) -> tuple[list[str], bool]:
    """Each successive decoding of ``text``, and whether a fixed point was reached.

    Decoding is repeated a bounded number of times, and every intermediate
    form is returned: a credential may be readable after one round and garbled
    by the next. Text that is still changing afterwards is reported as
    unstable; callers treat that as sensitive rather than decode further.
    """
    forms: list[str] = []
    for _ in range(_MAX_DECODE_ROUNDS):
        decoded = _decode_once(text)
        if decoded == text:
            return forms, True
        if len(decoded) > _MAX_VIEW_LENGTH:
            return forms, False
        forms.append(decoded)
        text = decoded
    return forms, _decode_once(text) == text


def _names_sensitive_data(key: str, pattern: re.Pattern[str]) -> bool:
    if pattern.search(key) is not None:
        return True
    if not _has_escapes(key):
        return False
    forms, stable = _decoded_forms(key)
    return not stable or any(pattern.search(form) is not None for form in forms)


def _has_escapes(text: str) -> bool:
    return "%" in text or "\\" in text or "&" in text or not text.isascii()


# ---------------------------------------------------------------- text layers


def _exact_str(value: str) -> str:
    # A str subclass may override anything; only its character data is used.
    # Copies a subclass whole: only for a value whose length has been checked.
    return value if type(value) is str else str.__str__(value)


def leading_text(value: str, limit: int) -> tuple[str, bool]:
    """At most ``limit`` characters of ``value`` as an exact ``str``, and whether it was longer.

    Measured and sliced through the base type's own slots, in that order: a
    subclass is never asked to convert itself, and a value over the limit is
    never copied whole in order to be found too long.
    """
    if str.__len__(value) > limit:
        return str.__getitem__(value, slice(0, limit)), True
    return _exact_str(value), False


def _scrub(text: str, budget: _Budget, nesting: int) -> str:
    """A scrubbed copy of at most ``MAX_STRING_LENGTH`` characters of ``text``."""
    limit = min(MAX_STRING_LENGTH, budget.scan)
    if limit <= 0:
        return TRUNCATED
    text, cut = leading_text(text, limit)
    budget.scan -= len(text)
    fragments: list[str] = []
    held = _hold_json(text, budget, nesting, fragments)
    scrubbed = _scrub_held(held, budget, cut=cut)
    # Decoded views are judged with the fragments still held aside: what is
    # inside them was sanitised, views included, string by string.
    scrubbed = _scrub_decoded_views(scrubbed, held, budget, nesting)
    if cut:
        # The delimiters that decide what a credential-bearing form means may
        # lie beyond the cut. If the examined part shows any sign of one, no
        # part of the value is emitted; otherwise the last, possibly incomplete,
        # token is dropped with what was not examined.
        if scrubbed != held or _CUT_INDICATOR.search(held) is not None:
            return TRUNCATED_SENSITIVE
        scrubbed = held[: max(0, held.rfind(" "))]
    if fragments:
        scrubbed = _FRAGMENT.sub(lambda match: fragments[int(match.group(1))], scrubbed)
    if cut:
        return f"{scrubbed} {TRUNCATED}" if scrubbed else TRUNCATED
    return scrubbed


def _scrub_held(held: str, budget: _Budget, *, cut: bool) -> str:
    """The text rules, then the ambiguity rule (module docstring, layer 7)."""
    scrubbed = _scrub_free_text(held, cut=cut)
    if _AMBIGUOUS.search(held) is None:
        return scrubbed
    if scrubbed != held:
        # Something was masked in text whose delimiters cannot be relied on.
        return REDACTED
    # Parsers that delete or keep these characters read the text joined up.
    joined = _AMBIGUOUS.sub("", held)
    budget.scan -= len(joined)
    return REDACTED if _scrub_free_text(joined, cut=cut) != joined else scrubbed


def _hold_json(text: str, budget: _Budget, nesting: int, fragments: list[str]) -> str:
    """Sanitise embedded JSON into ``fragments``, leaving placeholders in the text.

    Each sanitised JSON fragment stands in the text as an opaque placeholder
    while the text rules run. They therefore cannot mistake its (already safe)
    content for free text, and a rule whose value *is* the fragment
    (``credentials={...}``, userinfo) masks it whole.
    """
    if _FRAGMENT_OPEN in text or _FRAGMENT_CLOSE in text:
        text = text.translate(_NO_FRAGMENT_MARKS)
    return _scrub_json_fragments(text, budget, nesting, fragments)


def _scrub_free_text(text: str, *, cut: bool) -> str:
    text = _scrub_tokens(text)
    text = _scrub_signed_references(text)
    text = _scrub_urls(text, cut=cut)
    text = _scrub_pairs(text)
    return _scrub_bare_authorities(text)


def _scrub_layers(text: str, budget: _Budget, nesting: int) -> str:
    """Every text rule applied to a decoded view; it is compared, never emitted."""
    return _scrub_held(_hold_json(text, budget, nesting, []), budget, cut=False)


def _replace_spans(text: str, spans: list[tuple[int, int]]) -> str:
    """``text`` with every span replaced by the mask; overlapping spans are merged."""
    if not spans:
        return text
    spans.sort()
    merged: list[tuple[int, int]] = []
    for start, end in spans:
        if end <= start:
            continue
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    parts: list[str] = []
    copied = 0
    for start, end in merged:
        parts.append(text[copied:start])
        parts.append(REDACTED)
        copied = end
    parts.append(text[copied:])
    return "".join(parts)


def _scrub_json_fragments(text: str, budget: _Budget, nesting: int, fragments: list[str]) -> str:
    """Sanitise each embedded JSON object/array structurally.

    The sanitised form is appended to ``fragments`` and a placeholder naming
    it is left in the returned text.
    """
    if "{" not in text and "[" not in text:
        return text
    length = len(text)
    work = _JSON_WORK_FACTOR * length + 1_024
    parts: list[str] = []
    copied = position = 0
    while (opener := _JSON_OPENER.search(text, position)) is not None:
        start = opener.start()
        if work <= 0:
            # The parse allowance is spent and unexamined JSON may follow.
            parts.append(text[copied:start])
            parts.append(REDACTED)
            copied = length
            break
        try:
            value, end = _JSON.raw_decode(text, start)
        except (ValueError, RecursionError) as exc:
            failed_at = getattr(exc, "pos", None)
            work -= max(1, (failed_at if isinstance(failed_at, int) else length) - start)
            position = start + 1
            continue
        work -= end - start
        if isinstance(value, dict | list) and value:
            if nesting >= MAX_JSON_NESTING:
                # Too deeply nested to examine: masked, never passed through.
                replacement = REDACTED
            else:
                # The parsed value goes through the same sanitiser as any other
                # structure; it never reaches the output any other way.
                clean = _sanitize(value, 0, budget, nesting + 1)
                replacement = f"{_FRAGMENT_OPEN}{len(fragments)}{_FRAGMENT_CLOSE}"
                fragments.append(json.dumps(clean, ensure_ascii=False))
            parts.append(text[copied:start])
            parts.append(replacement)
            copied = end
        position = end
    parts.append(text[copied:])
    return "".join(parts)


def _scrub_tokens(text: str) -> str:
    if "PRIVATE KEY-----" in text:
        text = _PEM.sub(lambda _: REDACTED, text)
    text = _BEARER.sub(rf"\g<scheme> {REDACTED}", text)
    text = _DIGEST.sub(rf"\g<scheme> {REDACTED}", text)
    text = _TOKEN_VALUE.sub(rf"\g<scheme> {REDACTED}", text)
    if "eyJ" not in text:
        return text

    def mask_jwt(match: re.Match[str]) -> str:
        # A JSON Web Token (or JWE): "eyJ" at the start of a dot-separated
        # segment with at least two more segments. Masked to the end of the run.
        run = match.group(0)
        index = run.find("eyJ")
        while index >= 0:
            if index == 0 or run[index - 1] in "-.":
                if run.count(".", index) < 2:
                    break  # no later candidate has more dots than this one
                return run[:index] + REDACTED
            index = run.find("eyJ", index + 1)
        return run

    return _JWT_RUN.sub(mask_jwt, text)


def _userinfo_end(text: str, start: int, token_end: int, last_at: int, cut: bool) -> int:
    """Where the credential of the URL whose authority begins at ``start`` ends.

    Returns ``start`` if it carries none. Whitespace does not end a URL here:
    parsers disagree about it, and each of these is a password to one of them.

    * The last ``@`` before the first ``/``, ``?`` or ``#`` ends the userinfo
      (``urllib``; libpq takes the first, which lies before it).
    * ``scheme://user:pass/word@host`` and ``scheme://user:pa ss@host``: with a
      ``:`` before the first ``/``, SQLAlchemy reads a password up to the next
      ``@`` wherever it is, across ``/`` and whitespace alike.
    * In text cut by a limit the ``@`` may be among what was cut off.

    ``token_end`` is the next whitespace and ``last_at`` the last ``@`` of the text.
    """
    length = len(text)
    stop = _AUTHORITY_END.search(text, start)
    netloc_end = stop.start() if stop else length
    at = text.rfind("@", start, netloc_end) if last_at >= start else -1
    if at >= 0:
        return at
    slash = text.find("/", start)
    host_start = start
    if text.startswith("[", start):  # IPv6 literal: its colons are not separators
        closing = text.find("]", start, netloc_end)
        if closing >= 0:
            host_start = closing + 1
    colon = text.find(":", host_start, slash if slash >= 0 else length)
    if colon < 0:
        return start
    if last_at >= netloc_end:
        at = text.rfind("@", netloc_end, token_end)
        return at if at >= 0 else text.find("@", token_end)
    if cut:
        return length
    authority_end = min(netloc_end, token_end)
    if _PORTS.fullmatch(text, colon + 1, authority_end) is None:
        return authority_end  # "host:<not a port>" with no "@" anywhere after it
    return start


def _is_sensitive_parameter(key: str) -> bool:
    return any(
        is_sensitive_key(form) or _SIGNING_PARAMETER.fullmatch(form) is not None
        for form in (key, unquote_plus(key))
    )


def _is_signing_parameter(key: str) -> bool:
    # The key as written after any whitespace: in "my file?sig" the key is "sig".
    name = key[max(key.rfind(space) for space in _VALUE_DELIMITERS) + 1 :]
    return any(
        _SIGNING_PARAMETER.fullmatch(form) is not None for form in (name, unquote_plus(name))
    )


def _signed_url_end(text: str, query_from: int, region_end: int) -> int:
    """Where the parameters of a signed URL end, or -1 if the URL is not signed.

    ``query_from`` is the first character after the ``?`` or ``#`` of one URL
    and ``region_end`` the start of the next URL, or the end of the text. The
    parameters are read as a set: if any of them shows the URL to be signed,
    all of them belong to the capability, whatever their names and order.
    """
    signed = False
    end = -1
    index = query_from
    while index < region_end:
        stop = _SIGNED_PARAMETER_END.search(text, index, region_end)
        segment_end = stop.start() if stop else region_end
        equals = text.find("=", index, segment_end)
        if equals >= 0:
            signed = signed or _is_signing_parameter(text[index:equals])
            space = _WHITESPACE.search(text, equals + 1, segment_end)
            end = space.start() if space else segment_end
        index = segment_end + 1
    return end if signed else -1


def _scrub_signed_references(text: str) -> str:
    """Mask a signed URL that is written without a scheme.

    A request line or an access log shows a signed URL as a path and a query
    (``GET /media/call.wav?Expires=...&Signature=...``), or as a host and
    path. It is the same capability: the token is replaced whole.
    """
    if "?" not in text:
        return text
    spans: list[tuple[int, int]] = []
    for match in _TOKEN.finditer(text):
        token = match.group(0)
        question = token.find("?")
        if question < 0 or "://" in token:
            continue  # no query, or a URL with a scheme (_scrub_urls)
        if _signed_url_end(text, match.start() + question + 1, match.end()) >= 0:
            spans.append((match.start(), match.end()))
    return _replace_spans(text, spans)


def _scrub_urls(text: str, *, cut: bool) -> str:
    """Mask the credentials of every URL, and every signed URL whole.

    The userinfo and the sensitive query/fragment parameters are masked where
    they stand. A URL that is recognisably signed is a bearer capability as a
    whole (6A §22): it is replaced from its scheme to the end of its last
    parameter, so that neither its path nor its expiry, policy, key or scope
    parameters remain beside a masked signature.
    """
    if "://" not in text:
        return text
    length = len(text)
    spans: list[tuple[int, int]] = []
    urls: list[tuple[int, int, int]] = []
    position = token_end = 0
    parameters_from = -1
    last_at = text.rfind("@")
    while (marker := text.find("://", position)) >= 0:
        start = position = marker + 3
        if start > token_end:
            space = _WHITESPACE.search(text, start)
            token_end = space.start() if space else length
        mask_end = _userinfo_end(text, start, token_end, last_at, cut)
        spans.append((start, mask_end))
        urls.append((marker, max(start, mask_end), token_end))
        if parameters_from < 0:
            opener = _QUERY_START.search(text, max(start, mask_end))
            if opener is not None:
                parameters_from = opener.end()
    for number, (marker, after_userinfo, url_token_end) in enumerate(urls):
        region_end = urls[number + 1][0] if number + 1 < len(urls) else length
        opener = _QUERY_START.search(text, after_userinfo, region_end)
        if opener is None:
            continue
        signed_end = _signed_url_end(text, opener.end(), region_end)
        if signed_end < 0:
            continue
        scheme_start = marker
        while scheme_start > 0 and text[scheme_start - 1] in _SCHEME_CHARACTERS:
            scheme_start -= 1
        spans.append((scheme_start, max(signed_end, min(url_token_end, region_end))))
    # Parameters, examined once from the first query to the end of the text. A
    # sensitive value runs to the next "&" or to the end: libpq keeps "#", tabs
    # and newlines in it, and SQLAlchemy keeps spaces.
    index = parameters_from if parameters_from >= 0 else length
    while index < length:
        stop = _PARAMETER_END.search(text, index)
        segment_end = stop.start() if stop else length
        equals = text.find("=", index, segment_end)
        if equals >= 0 and _is_sensitive_parameter(text[index:equals]):
            ampersand = text.find("&", equals)
            segment_end = ampersand if ampersand >= 0 else length
            spans.append((equals + 1, segment_end))
        index = segment_end + 1
    return _replace_spans(text, spans)


def _closing_quote(text: str, opening_at: int, limit: int) -> int:
    """Index of the quote closing the one at ``opening_at``, or -1 before ``limit``.

    A doubled quote is an escaped quote and so is a quote behind a backslash;
    neither ends the value. A quote behind several backslashes is ambiguous:
    text may be escaped to an unknown depth, so the parity of the run proves
    nothing. The value then counts as undelimited (-1) and the caller masks to
    its limit, rather than guess and stop inside some later value.
    """
    quote = text[opening_at]
    index = opening_at + 1
    while index < limit:
        char = text[index]
        if char == "\\":
            run_start = index
            while index < limit and text[index] == "\\":
                index += 1
            if index - run_start > 1 and text.startswith(quote, index):
                return -1
            index += 1  # whatever follows the run is escaped
            continue
        if char == quote:
            if index > opening_at + 1 and text.startswith(quote, index + 1):
                index += 2
                continue
            return index
        index += 1
    return -1


def _unquoted_end(text: str, start: int, *, to_end_of_line: bool, in_query: bool) -> int:
    """Where the unquoted value starting at ``start`` ends.

    The value ends at ASCII whitespace, as in the libpq grammar (or at ``&`` in
    a query), or at the end of the line for line-oriented keys. Any other
    whitespace is part of the value. Quoted sections and brackets inside it are
    honoured so that whitespace within them does not end it. A value opening
    with a bracket may span lines until the bracket closes. Wherever the end
    cannot be established, the rest of the line or of the string is the value.
    """
    length = len(text)
    newline = _NEWLINE.search(text, start)
    line_end = newline.start() if newline else length
    spans_lines = text[start] in _OPENERS
    depth = 0
    index = start
    while index < length:
        char = text[index]
        if char in "\r\n" and not (spans_lines and depth > 0):
            break
        if char == "\\":
            # A backslash run escapes what follows, whatever its length (see
            # _closing_quote): "a\\ b" and its re-escaped form "a\\\\ b" are one value.
            while index < length and text[index] == "\\":
                index += 1
            index += 1
            continue
        if char in _QUOTES and (depth > 0 or not to_end_of_line):
            limit = length if spans_lines and depth > 0 else line_end
            closing = _closing_quote(text, index, limit)
            if closing < 0:
                return limit
            index = closing + 1
            continue
        if char in _OPENERS:
            depth += 1
        elif char in _CLOSERS:
            depth = max(0, depth - 1)
        elif (
            depth == 0
            and not to_end_of_line
            and (char in _VALUE_DELIMITERS or (in_query and char == "&"))
        ):
            break
        index += 1
    return min(index, length)


def _block_span(text: str, newline_at: int, key_start: int) -> tuple[int, int]:
    """The lines below a ``key:`` that ends its own line (block style)."""
    length = len(text)
    line_start = max(text.rfind("\n", 0, key_start), text.rfind("\r", 0, key_start)) + 1
    key_indent = 0
    while line_start + key_indent < key_start and text[line_start + key_indent] in " \t":
        key_indent += 1
    start = newline_at
    while start < length and text[start].isspace():
        start += 1
    if start >= length:
        return start, start
    stop = _NEWLINE.search(text, start)
    end = stop.start() if stop else length
    # Further lines belong to the value while they are indented below the key.
    while end < length:
        following = end + 1
        if text.startswith("\r\n", end):
            following = end + 2
        indent = following
        while indent < length and text[indent] in " \t":
            indent += 1
        if indent >= length or text[indent] in "\r\n" or indent - following <= key_indent:
            break
        stop = _NEWLINE.search(text, indent)
        end = stop.start() if stop else length
    return start, end


def _in_query_string(text: str, key_start: int) -> bool:
    """True if the key at ``key_start`` is a URL query parameter (so ``&`` ends its value)."""
    if text[max(0, key_start - 1) : key_start] in ("&", "?"):
        return True
    window_start = max(0, key_start - _QUERY_LOOKBACK)
    token_start = max(text.rfind(space, window_start, key_start) for space in " \t\r\n")
    return "?" in text[max(token_start + 1, window_start) : key_start]


def _escaped_space(text: str, index: int) -> int:
    """Length of an escaped whitespace sequence at ``index`` (0 if there is none).

    Text that is the repr or JSON encoding of other text writes whitespace as
    an escape (backslash-n, backslash-t, backslash-xa0, backslash-u00a0), behind
    any number of backslashes. Such a sequence separates a key from its value
    exactly as the whitespace would.
    """
    length = len(text)
    end = index
    while end < length and text[end] == "\\":
        end += 1
    if end == index or end >= length:
        return 0
    char = text[end]
    if char in "ntrfv":
        return end + 1 - index
    digits = 2 if char == "x" else 4 if char == "u" else 0
    code = text[end + 1 : end + 1 + digits]
    if digits and len(code) == digits and _HEX.fullmatch(code) and chr(int(code, 16)).isspace():
        return end + 1 + digits - index
    return 0


def _is_sensitive_text_key(key: str) -> bool:
    return _names_sensitive_data(key, _SENSITIVE_TEXT_KEY)


def _opens_quote(text: str, index: int) -> bool:
    """True if a quoted value starts at ``index``: bare, prefixed (b'..') or escaped."""
    if text[index : index + 1] in _STRING_PREFIXES and text[index + 1 : index + 2] in _QUOTES:
        return True
    while text.startswith("\\", index):
        index += 1
    return index < len(text) and text[index] in _QUOTES


def _locate_value(text: str, key_start: int, key_end: int) -> tuple[int, str] | None:
    """Where the value of the key ending at ``key_end`` starts, and how it is introduced.

    Whitespace of any kind and amount may surround the separator. Returns
    ``None`` when nothing after the key introduces a value.
    """
    length = len(text)
    index = key_end
    closed_quote = False
    while index < length:
        char = text[index]
        if char == "\\":
            if _escaped_space(text, index):
                break  # escaped whitespace: handled with the whitespace below
            while index < length and text[index] == "\\":
                index += 1
        elif char in _KEY_TRAILERS:
            closed_quote = closed_quote or char in _QUOTES
            index += 1
        elif char in ("[", _FRAGMENT_OPEN):
            # A subscript: user[password][0]. One that happens to be JSON ([0])
            # stands here as a fragment placeholder.
            closer = "]" if char == "[" else _FRAGMENT_CLOSE
            closing = text.find(closer, index + 1, index + 1 + _MAX_SUBSCRIPT_LENGTH)
            if closing < 0:
                break
            index = closing + 1
        else:
            break
    after = index
    while after < length:
        if text[after].isspace():
            after += 1
        elif escaped := _escaped_space(text, after):
            after += escaped
        else:
            break
    if after >= length:
        return None
    char = text[after]
    following = text[after + 1 : after + 2]
    if char == "=":
        return (after + 2 if following == ">" else after + 1), "="
    if char == ":":
        return (after + 2, "=") if following == "=" else (after + 1, ":")
    if char == ">" and after == index:
        return after + 1, ">"  # <key>value</key>
    if char == "," and closed_quote:
        # 'key', 'value' — a pair written as a tuple or list.
        value = after + 1
        while value < length and text[value].isspace():
            value += 1
        return (value, "'") if _opens_quote(text, value) else None
    if after > index:
        if _opens_quote(text, after):
            return after, "'"  # KEY 'value' — no separator at all
        if text[key_start] == "-":
            return after, "="  # --key value
    return None


def _value_span(
    text: str,
    start: int,
    kind: str,
    *,
    key_start: int,
    header: bool,
    to_end_of_line: bool,
    in_query: bool,
) -> tuple[int, int, str]:
    """``(start, end, replacement)`` of the value introduced at ``start``.

    Whenever the end of the value cannot be established, the span runs to the
    end of the line or of the string.
    """
    length = len(text)
    if kind == ">":
        closing = text.find("<", start)
        return start, (length if closing < 0 else closing), REDACTED
    index = start
    if kind == ":":
        while index < length and text[index].isspace() and text[index] not in "\r\n":
            index += 1
        if index < length and text[index] in "\r\n":
            return (*_block_span(text, index, key_start), REDACTED)
    else:
        # Escaped whitespace before the value is skipped like whitespace, but
        # masked with the value: it may equally be the start of the secret.
        first_escape = -1
        while index < length:
            if text[index].isspace():
                index += 1
            elif escaped := _escaped_space(text, index):
                first_escape = index if first_escape < 0 else first_escape
                index += escaped
            else:
                break
        if first_escape >= 0:
            if index >= length:
                return first_escape, length, REDACTED
            _, end, _ = _value_span(
                text,
                index,
                kind,
                key_start=key_start,
                header=header,
                to_end_of_line=to_end_of_line,
                in_query=in_query,
            )
            return first_escape, max(end, index), REDACTED
    if index >= length:
        return index, index, ""
    quote_at = index
    if text[index] in _STRING_PREFIXES and text[index + 1 : index + 2] in _QUOTES:
        quote_at = index + 1
    quote = text[quote_at]
    if quote in _QUOTES:
        closing = _closing_quote(text, quote_at, length)
        if closing < 0:
            return quote_at, length, f"{quote}{REDACTED}"  # unterminated quote
        after = closing + 1
        following = after
        while following < length and text[following] in " \t":
            following += 1
        delimiters = "\r\n,)]}" if header else "\r\n,)]};&"
        if following >= length or text[following] in delimiters:
            return quote_at, after, f"{quote}{REDACTED}{quote}"
        if following == after or to_end_of_line:
            # More follows the closing quote ('a'b, "a" b on a credential line):
            # the quoted part is not the whole value.
            end = _unquoted_end(text, after, to_end_of_line=to_end_of_line, in_query=in_query)
            return quote_at, end, REDACTED
        return quote_at, after, f"{quote}{REDACTED}{quote}"
    if text[index] == "\\":
        escapes = index
        while escapes < length and text[escapes] == "\\":
            escapes += 1
        if escapes < length and text[escapes] in _QUOTES:
            # Text that is itself an escaped string (\"...\"): its quoting depth is
            # unknown, so the value cannot be delimited. Mask the remainder.
            return index, length, REDACTED
    end = _unquoted_end(text, index, to_end_of_line=to_end_of_line, in_query=in_query)
    return index, end, REDACTED


def _pair_span(text: str, match: re.Match[str]) -> tuple[int, int, str] | None:
    """``(start, end, replacement)`` of the value of the key ``match``, if it has one."""
    key = match.group(0)
    if not _is_sensitive_text_key(key):
        return None
    located = _locate_value(text, match.start(), match.end())
    if located is None:
        return None
    value_start, kind = located
    header = _HEADER_KEY.search(key) is not None
    return _value_span(
        text,
        value_start,
        kind,
        key_start=match.start(),
        header=header,
        to_end_of_line=kind == ":" or (header and kind == "="),
        in_query=kind == "=" and _in_query_string(text, match.start()),
    )


def _swallows_a_value(text: str, start: int, end: int) -> bool:
    """True if the span holds a sensitive key whose own value reaches beyond it.

    A span that ran too far (text escaped to an unknown depth, a quote that
    was not one) can end after the *key* of the next pair, which would then
    leave that pair's value standing with nothing in front of it to mark it.
    """
    examined = 0
    for match in _KEY_RUN.finditer(text, start, end):
        inner = _pair_span(text, match)
        if inner is None:
            continue
        examined += 1
        if examined > _MAX_SWALLOWED_KEYS or inner[1] > end:
            return True
    return False


def _scrub_pairs(text: str) -> str:
    """Mask the value that follows every sensitive key."""
    length = len(text)
    parts: list[str] = []
    copied = position = 0
    while (match := _KEY_RUN.search(text, position)) is not None:
        position = match.end()
        span = _pair_span(text, match)
        if span is None:
            continue
        start, end, replacement = span
        if end <= start:
            continue
        if end < length and _swallows_a_value(text, start, end):
            # The value cannot be delimited reliably: mask the remainder.
            end, replacement = length, REDACTED
        parts.append(text[copied:start])
        parts.append(replacement)
        copied = position = end
    parts.append(text[copied:])
    return "".join(parts)


def _scrub_bare_authorities(text: str) -> str:
    """Mask ``user:password@`` written without a scheme (``user:pw@tcp(host)/db``)."""
    if "@" not in text:
        return text

    def replace(match: re.Match[str]) -> str:
        token = match.group(0)
        at = token.rfind("@")
        if at <= 0 or "://" in token:
            return token
        colon = token.find(":")
        if not 0 < colon < at - 1 or token[:at] == REDACTED:
            return token  # needs a user before the colon and a password after it
        if _DRIVE_PATH.match(token) is not None and token.count(":", 0, at) == 1:
            return token  # a Windows path whose only colon follows the drive letter
        return REDACTED + token[at:]

    return _TOKEN.sub(replace, text)


def _view(form: str, budget: _Budget, nesting: int) -> str | None:
    """A decoded form after every text rule; ``None`` if the budget cannot pay for it."""
    if len(form) > budget.scan:
        return None
    budget.scan -= len(form)
    return _scrub_layers(form, budget, nesting)


def _decode_tokens_once(text: str) -> str:
    """Decode each token on its own, joining any whitespace the decoding produces.

    ``n=%70assword%3Dfirst%20second``: the space that appears is part of a
    query value, not the end of it, so within a token it must not delimit.
    """
    return _TOKEN.sub(lambda match: _WHITESPACE.sub("_", _decode_once(match.group(0))), text)


def _shows_more_than_its_views(scrubbed: str, original: str, budget: _Budget, nesting: int) -> bool:
    """True if ``scrubbed`` still shows text that a decoded view of ``original`` masks.

    Each decoded form of the original text is scrubbed on its own. Whatever
    ``scrubbed`` leaves readable, decoded the same way, must then be readable
    in that view as well; a piece that is not was masked there, so the text
    rules missed it or delimited it wrongly on the raw form. The original is
    examined untouched because a wrongly placed mask has already replaced the
    very characters a view needs in order to show the credential.

    Two decodings are examined round by round: the whole text, and each token
    on its own with decoded whitespace joined.

    Also true when decoding does not settle within the allowed rounds, or the
    budget cannot pay for the examination: text that cannot be examined in
    full is not emitted.
    """
    if not _decoded_forms(original)[1]:
        return True
    marked = scrubbed.translate(_NO_FRAGMENT_MARKS)
    for decode in (_decode_once, _decode_tokens_once):
        form, shown = original, marked
        for _ in range(_MAX_DECODE_ROUNDS):
            decoded = decode(form)
            if decoded == form:
                break
            if len(decoded) > _MAX_VIEW_LENGTH:
                return True
            form = decoded
            view = _view(form, budget, nesting)
            if view is None:
                return True
            shown = decode(shown)
            if any(piece not in view for piece in shown.split(REDACTED)):
                return True
    return False


def _scrub_decoded_views(scrubbed: str, original: str, budget: _Budget, nesting: int) -> str:
    """Mask ``scrubbed`` whole if a decoded view shows the text rules missed something.

    ``original`` is the text before the rules ran.
    """
    if _has_escapes(original) and _shows_more_than_its_views(scrubbed, original, budget, nesting):
        return REDACTED
    return scrubbed


# ---------------------------------------------------------------- structured data


def _type_name(value: object) -> str:
    """The class name of an exception: a code identifier, accepted by grammar only."""
    try:
        name = type(value).__qualname__
    except Exception:  # noqa: BLE001 — a hostile metaclass names nothing
        return "object"
    return name if type(name) is str and _TYPE_NAME.fullmatch(name) else "object"


def exception_type_name(exc: BaseException) -> str:
    """The class name of ``exc`` if it is a well-formed identifier, else ``object``."""
    return _type_name(exc)


def _emit(text: str, budget: _Budget, nesting: int) -> str:
    """Charge an already-safe string to the output budget, shortening it to fit.

    The cost is the string's rendered JSON length. Text inside nested JSON is
    charged once, when the string that contains it is emitted.
    """
    if nesting:
        return text
    cost = len(json.dumps(text)) + _SEPARATOR_COST
    if cost <= budget.output:
        budget.output -= cost
        return text
    # Only already-scrubbed text is ever cut here; nothing original is appended.
    keep = max(0, budget.output - len(TRUNCATED) - 5) // (6 if text.isascii() else 12)
    budget.output = 0
    return f"{text[:keep]} {TRUNCATED}" if keep else TRUNCATED


def _text(value: str, budget: _Budget, nesting: int) -> str:
    # Every string is scrubbed. Its type is never a reason not to: a class
    # proves nothing about where a value came from.
    return _emit(_scrub(value, budget, nesting), budget, nesting)


def _uuid_text(value: uuid.UUID) -> str:
    number = value.int
    if type(number) is not int or not 0 <= number < 1 << 128:
        return UNSUPPORTED
    digits = f"{number:032x}"
    return f"{digits[:8]}-{digits[8:12]}-{digits[12:16]}-{digits[16:20]}-{digits[20:]}"


def _decimal_text(value: Decimal) -> str:
    # Size first, in constant time and without touching the coefficient: a
    # Decimal counts the allocation that holds its digits in __sizeof__, so a
    # ten-million-digit value is refused before anything reads or copies it.
    if Decimal.__sizeof__(value) > _MAX_DECIMAL_SIZE:
        return "<Decimal: too long>"
    # Rounding to a fixed precision then reads what is by now a small
    # coefficient without rendering it.
    context = Context(prec=_MAX_DECIMAL_DIGITS, Emax=MAX_EMAX, Emin=MIN_EMIN, traps=[])
    rounded = context.create_decimal(value)
    if context.flags[Inexact] or context.flags[Rounded]:
        return "<Decimal: too long>"
    text = str(rounded)
    return text if len(text) <= _MAX_SCALAR_TEXT else "<Decimal: too long>"


def _has_plain_timezone(value: dt.datetime | dt.time) -> bool:
    # isoformat() calls tzinfo.utcoffset(); only the standard implementations may run.
    return value.tzinfo is None or type(value.tzinfo) in (dt.timezone, zoneinfo.ZoneInfo)


def _moment_text(value: dt.datetime | dt.time) -> str:
    return value.isoformat() if _has_plain_timezone(value) else UNSUPPORTED


def _byte_count(value: bytes | bytearray | memoryview) -> str:
    return f"<{type(value).__name__}: {len(value)} bytes>"


# Scalars rendered by a serializer of their own, for their exact type only: a
# subclass may override any conversion method, so it is never asked for one.
_FIXED_RENDERERS: Final[Mapping[type, Callable[..., str]]] = {
    uuid.UUID: _uuid_text,
    Decimal: _decimal_text,
    dt.datetime: _moment_text,
    dt.time: _moment_text,
    dt.date: dt.date.isoformat,
    bytes: _byte_count,
    bytearray: _byte_count,
    memoryview: _byte_count,
}
# Paths render as text that is scrubbed like any other string.
_PATH_TYPES: Final = frozenset({PurePosixPath, PureWindowsPath, PosixPath, WindowsPath})
_CONTAINER_TYPES: Final = (Mapping, list, tuple, set, frozenset)


def _marker(text: str, budget: _Budget, nesting: int) -> str:
    return text if budget.charge(len(text) + 2, nesting) else TRUNCATED


def _sanitize(value: object, depth: int, budget: _Budget, nesting: int) -> object:
    if budget.exhausted:
        return TRUNCATED
    budget.nodes -= 1
    # The real type decides, never what the object says of itself (__class__).
    kind = type(value)
    if issubclass(kind, str):
        return _text(value, budget, nesting)  # type: ignore[arg-type]
    if issubclass(kind, _CONTAINER_TYPES):
        return _sanitize_container(value, depth, budget, nesting)  # type: ignore[arg-type]
    if value is None or kind is bool:
        return value if budget.charge(5, nesting) else TRUNCATED
    if issubclass(kind, int):
        # The base type's own slots: an overridden __int__/__index__/__str__ is
        # not run. Measured before it is converted: int.__int__ copies a subclass.
        bits = int.bit_length(value)  # type: ignore[arg-type]
        if bits > _MAX_INT_BITS:
            # Rejected by size before it is rendered; str() of it is never built.
            return _marker(f"<int: {bits} bits>", budget, nesting)
        number = int.__int__(value)  # type: ignore[arg-type]
        # At most 40 characters here, so measuring it by rendering it is cheap.
        return number if budget.charge(len(str(number)), nesting) else TRUNCATED
    if issubclass(kind, float):
        real = float.__float__(value)  # type: ignore[arg-type]
        return real if budget.charge(len(repr(real)), nesting) else TRUNCATED
    if issubclass(kind, SecretStr | SecretBytes):
        return _marker(REDACTED, budget, nesting)
    if issubclass(kind, BaseException):
        described = _describe_exception(value, budget)  # type: ignore[arg-type]
        return _emit(described, budget, nesting)
    if issubclass(kind, enum.Enum):
        # The member's stored value, not a ``value`` property a subclass may define.
        return _sanitize(vars(value).get("_value_"), depth, budget, nesting)
    if kind is dt.timedelta:
        seconds = float(value.total_seconds())  # type: ignore[attr-defined]
        return seconds if budget.charge(len(repr(seconds)), nesting) else TRUNCATED
    if kind in _PATH_TYPES:
        return _text(str(value), budget, nesting)
    renderer = _FIXED_RENDERERS.get(kind)
    if renderer is not None:
        return _marker(renderer(value), budget, nesting)
    # Unknown objects, and subclasses of the scalars above, are never rendered:
    # their repr()/str()/format() may return anything.
    return _marker(UNSUPPORTED, budget, nesting)


def _sanitize_container(
    value: Mapping[object, object]
    | list[object]
    | tuple[object, ...]
    | set[object]
    | frozenset[object],
    depth: int,
    budget: _Budget,
    nesting: int,
) -> object:
    marker = id(value)
    if marker in budget.active:
        return CYCLE
    if depth >= MAX_DEPTH:
        return TRUNCATED
    is_mapping = issubclass(type(value), Mapping)
    try:
        budget.charge(_SEPARATOR_COST, nesting)
        if len(value) == 0:
            return {} if is_mapping else []
        if marker in budget.seen:
            # Already expanded once in this event; expanding it again is how a
            # small graph of shared references becomes a huge log line.
            return REPEATED
        budget.seen[marker] = value
        budget.active.add(marker)
        try:
            if is_mapping:
                result: dict[str, object] = {}
                _sanitize_entries(value, depth, budget, nesting, result, MAX_ITEMS)  # type: ignore[arg-type]
                return result
            return _sanitize_sequence(value, depth, budget, nesting)  # type: ignore[arg-type]
        finally:
            budget.active.discard(marker)
    except Exception:  # noqa: BLE001 — a container that cannot be read is not emitted
        # A hostile or broken container (len(), items() or iteration raising):
        # none of its partially read content is returned.
        return UNREADABLE


def _sanitize_key(key: object, budget: _Budget, nesting: int) -> tuple[bool, str]:
    """Whether ``key`` names sensitive data, and its safe rendering."""
    kind = type(key)
    if issubclass(kind, str):
        # Sensitivity is decided on the key as given, before any scrubbing of
        # it. A key too long to classify within the budget is treated as
        # sensitive, and is measured before it is copied.
        affordable = str.__len__(key) <= min(MAX_STRING_LENGTH, budget.scan)  # type: ignore[arg-type]
        if affordable:
            key = _exact_str(key)  # type: ignore[arg-type]
            budget.scan -= len(key)
        sensitive = not affordable or is_sensitive_key(key)  # type: ignore[arg-type]
        # Scrubbed in full, as a value would be, and only then shortened: cutting
        # first could break the very structure the scrubber needs to recognise.
        scrubbed = _scrub(key, budget, nesting)  # type: ignore[arg-type]
        safe = _exact_str(_emit(scrubbed[:_MAX_KEY_LENGTH], budget, nesting))
        return sensitive or is_sensitive_key(safe), safe
    if key is None or kind is bool:
        safe = str(key)
    elif issubclass(kind, int):
        bits = int.bit_length(key)  # type: ignore[arg-type]
        if bits <= _MAX_INT_BITS:
            safe = str(int.__int__(key))  # type: ignore[arg-type]
        else:
            safe = f"<int: {bits} bits>"
    elif issubclass(kind, float):
        safe = repr(float.__float__(key))  # type: ignore[arg-type]
    else:
        safe = UNSUPPORTED
    budget.charge(len(safe) + 2, nesting)
    return False, safe


def _sanitize_entries(
    value: Mapping[object, object],
    depth: int,
    budget: _Budget,
    nesting: int,
    result: dict[str, object],
    limit: int,
    skip: frozenset[str] = frozenset(),
    note: str | None = None,
    assembled: frozenset[str] = frozenset(),
) -> None:
    """Sanitise up to ``limit`` entries of ``value`` into ``result``.

    The mapping is iterated lazily. When the limit or the event budget is
    reached, iteration stops: the remaining entries are neither visited nor
    referenced, and one marker stands for them.
    """
    admitted = 0
    # A mapping has each skipped key at most once; one that keeps yielding them
    # is not followed past this many entries.
    for key, item in islice(value.items(), limit + len(skip) + 1):
        if skip and _is_named_in(key, skip):
            continue
        if admitted >= limit:
            if type(key) is str and key == TRUNCATED:
                # Output of an earlier pass: its own marker is the entry beyond
                # the limit, and it still says how much was left out.
                result[TRUNCATED] = _sanitize(item, depth + 1, budget, nesting)
            else:
                result[TRUNCATED] = note or f"{len(value) - limit} more entries"
            break
        if budget.exhausted:
            result[TRUNCATED] = _BUDGET_NOTE
            break
        admitted += 1
        sensitive, safe_key = _sanitize_key(key, budget, nesting)
        if sensitive:
            budget.nodes -= 1
            result[safe_key] = _marker(REDACTED, budget, nesting)
        elif assembled and _is_named_in(key, assembled):
            result[safe_key] = _sanitize(_assembled_text(item), depth + 1, budget, nesting)
        else:
            result[safe_key] = _sanitize(item, depth + 1, budget, nesting)


def _is_named_in(key: object, names: frozenset[str]) -> bool:
    # By the character data of the key, read through the base type: a key of a
    # str subclass is the same field to the mapping that holds it.
    if not issubclass(type(key), str) or str.__len__(key) > _MAX_KEY_LENGTH:  # type: ignore[arg-type]
        return False
    return _exact_str(key) in names  # type: ignore[arg-type]


def _sanitize_field(key: str, value: object, budget: _Budget, assembled: frozenset[str]) -> object:
    """One top-level field of an event, assembled into its final text first if it has one."""
    if key in assembled:
        value = _assembled_text(value)
    return _sanitize(value, 1, budget, 0)


def _collect_fragments(value: object, depth: int, fragments: list[str], room: list[int]) -> None:
    """Append the text fragments of ``value`` in order; ``room`` is [characters, values] left."""
    if room[0] <= 0 or room[1] <= 0:
        return
    room[1] -= 1
    kind = type(value)
    if issubclass(kind, str):
        text, _ = leading_text(value, room[0])  # type: ignore[arg-type]
        room[0] -= len(text) + 1
        fragments.append(text.removesuffix("\n"))
    elif issubclass(kind, list | tuple) and depth < MAX_DEPTH:
        for item in islice(value, MAX_ITEMS):  # type: ignore[call-overload]
            _collect_fragments(item, depth + 1, fragments, room)
    else:
        # Neither text nor a list of it: nothing of it is laid out.
        room[0] -= len(UNSUPPORTED) + 1
        fragments.append(UNSUPPORTED)


def _assembled_text(value: object) -> str:
    """The single text that a traceback or stack field will be laid out as.

    A caller may hand such a field a string, a list of lines or lists within
    lists. All of it is caller-controlled, and none of it is sanitised here:
    the fragments are only put in order and joined with newlines, so that the
    sanitiser afterwards reads the complete text, every line in the context
    of its neighbours. A credential folded over two fragments (a header and
    its continuation, a URI and the rest of its password) is one credential
    again by the time it is examined.

    The work is bounded before any of it is done: at most ``MAX_ITEMS``
    values are visited, to ``MAX_DEPTH`` levels, and one character more than
    ``MAX_STRING_LENGTH`` is copied, which is what tells the sanitiser that
    the text was cut. Anything that is not text becomes a fixed marker.
    """
    if type(value) is str:
        return value
    try:
        fragments: list[str] = []
        room = [MAX_STRING_LENGTH + 1, MAX_ITEMS]
        _collect_fragments(value, 0, fragments, room)
        if room[1] <= 0:
            fragments.append(TRUNCATED)
        return "\n".join(fragments)
    except Exception:  # noqa: BLE001 — fragments that cannot be read are not emitted
        return UNREADABLE


def _sanitize_sequence(
    value: list[object] | tuple[object, ...] | set[object] | frozenset[object],
    depth: int,
    budget: _Budget,
    nesting: int,
) -> list[object]:
    result: list[object] = []
    note: str | None = None
    for index, item in enumerate(value):
        if index >= MAX_ITEMS:
            if issubclass(type(item), str) and str.startswith(item, TRUNCATED):  # type: ignore[arg-type]
                # Output of an earlier pass: its own marker is the item beyond the limit.
                result.append(_sanitize(item, depth + 1, budget, nesting))
            else:
                note = f"{TRUNCATED} {len(value) - MAX_ITEMS} more items"
            break
        if budget.exhausted:
            note = TRUNCATED
            break
        result.append(_sanitize(item, depth + 1, budget, nesting))
    if issubclass(type(value), set | frozenset):
        # Iteration order of a set is arbitrary; sort for stable output. Only
        # sanitised built-in values are rendered for the comparison.
        result.sort(key=repr)
    if note is not None:
        result.append(note)
    return result


# ---------------------------------------------------------------- exceptions


def _summary_part(value: object, budget: _Budget, limit: int) -> str:
    """One piece of a validation summary: an exact ``str``, scrubbed and then shortened.

    Each piece is a unit of its own. It is scrubbed in full before it is cut,
    and the pieces are never read again as one string. Anything that is not an
    exact ``str`` is not converted.
    """
    if type(value) is not str:
        return UNSUPPORTED
    scrubbed = _scrub(value, budget, 0)
    return scrubbed if len(scrubbed) <= limit else f"{scrubbed[:limit]} {TRUNCATED}"


def _validation_summary(exc: BaseException, budget: _Budget) -> str | None:
    """Summarise an exception exposing a pydantic-style ``errors()`` list, never its input."""
    errors_method = getattr(exc, "errors", None)
    if not callable(errors_method):
        return None
    errors = errors_method()
    if type(errors) not in (list, tuple):
        return None
    problems = []
    for error in islice(errors, _MAX_SUMMARY_ERRORS):
        if type(error) is not dict:
            continue
        parts: Iterable[object] = error.get("loc", ())
        if type(parts) not in (list, tuple):
            parts = ()
        # Only exact strings and integers: a subclass could render as anything.
        location = ".".join(
            str(part)
            if type(part) is int and part.bit_length() <= _MAX_INT_BITS
            else _summary_part(part, budget, _MAX_SUBSCRIPT_LENGTH)
            for part in islice(parts, MAX_DEPTH)
        )
        message = _summary_part(error.get("msg", ""), budget, _MAX_KEY_LENGTH)
        kind = _summary_part(error.get("type", ""), budget, _MAX_SUBSCRIPT_LENGTH)
        problems.append(f"{location or '<root>'}: {message} [{kind}]")
    return f"{len(errors)} validation error(s): " + "; ".join(problems)


def _exception_message(exc: BaseException, budget: _Budget) -> str:
    try:
        scrubbed = _validation_summary(exc, budget)
    except Exception:  # noqa: BLE001 — a broken errors() falls back to the plain message
        scrubbed = None
    if scrubbed is None:
        try:
            # The one conversion of an untrusted object: there is no other way
            # to obtain an exception's message. Its result is untrusted text.
            # One character past the limit, which tells the scrubber it was cut.
            message, _ = leading_text(str(exc), MAX_STRING_LENGTH + 1)
        except Exception:  # noqa: BLE001 — an unprintable message is itself reported, never raised
            message = "<unprintable message>"
        # Classified in full, within the scrubber's own limits, and only then
        # shortened: a prefix cut before scrubbing may have lost the "@" or the
        # quote that shows what the rest of it is.
        scrubbed = _scrub(message, budget, 0)
    if len(scrubbed) > _MAX_MESSAGE_LENGTH:
        return f"{scrubbed[:_MAX_MESSAGE_LENGTH]} {TRUNCATED}"
    return scrubbed


def _describe_exception(exc: BaseException, budget: _Budget) -> str:
    text = f"{_type_name(exc)}: {_exception_message(exc, budget)}"
    if issubclass(type(exc), BaseExceptionGroup):
        members: list[str] = []
        exceptions = BaseExceptionGroup.exceptions.__get__(exc)
        for member in exceptions[:_MAX_SUB_EXCEPTIONS]:
            if budget.nodes <= 0:
                members.append(TRUNCATED)
                break
            budget.nodes -= 1
            members.append(_describe_exception(member, budget))
        text += " [" + "; ".join(members) + "]"
    return text


def describe_exception(exc: BaseException) -> str:
    """``TypeName: scrubbed message``, plus sub-exceptions of an exception group."""
    try:
        return _describe_exception(exc, _Budget())
    except Exception:  # noqa: BLE001 — an exception that cannot be described is not emitted
        return UNREADABLE


def _own(exc: BaseException, attribute: str) -> object:
    # Read through BaseException's own descriptor, not a property of a subclass.
    return getattr(BaseException, attribute).__get__(exc)


def _linked(exc: BaseException, attribute: str) -> BaseException | None:
    linked = _own(exc, attribute)
    return linked if isinstance(linked, BaseException) else None


def _frame_filename(value: object, budget: _Budget) -> str:
    """The filename of a frame if the whole of it is safe to show, else a fixed word.

    A filename is whatever was passed to ``compile()``: it can be a connection
    string, span several lines or be a million characters long. It is judged
    complete and as one unit, before any part of it is shortened or formatted.
    """
    if not issubclass(type(value), str):
        return _UNKNOWN_FILE
    # Measured through the base type before anything is read, copied or scanned.
    if str.__len__(value) > _MAX_FILENAME_LENGTH:  # type: ignore[arg-type]
        return _LONG_FILE
    text = _exact_str(value)  # type: ignore[arg-type]
    if not text or not text.isprintable() or '"' in text or _AMBIGUOUS.search(text) is not None:
        return _UNSAFE_FILE
    # Credential-bearing if any text rule would change it. Nothing of it is kept.
    return text if _scrub(text, budget, 0) == text else _UNSAFE_FILE


def _frame_line(code: object, lineno: object, budget: _Budget) -> str:
    """One frame as ``File "...", line N, in name``, built from validated metadata.

    Source lines are never read. The finished line is emitted only if the text
    rules leave it unchanged, so a later pass reads exactly what was built.
    """
    number = str(lineno) if type(lineno) is int and 0 <= lineno < 1_000_000_000 else "?"
    fallback = f'  File "{_UNSAFE_FILE}", line {number}, in {_UNKNOWN_NAME}'
    if type(code) is not types.CodeType:
        return fallback
    filename = _frame_filename(code.co_filename, budget)
    name = code.co_name
    if type(name) is not str or _FRAME_NAME.fullmatch(name) is None:
        name = _UNKNOWN_NAME
    line = f'  File "{filename}", line {number}, in {name}'
    # Checked as it will stand in a traceback, with another line after it: a
    # name that reads as the start of a credential only when something follows
    # ("bearer") is replaced here, not found when the traceback is assembled.
    stacked = f"{line}\n{line}"
    return line if _scrub(stacked, budget, 0) == stacked else fallback


def _traceback_frames(trace: types.TracebackType, budget: _Budget) -> list[str]:
    """The innermost frames of ``trace``, one line each."""
    kept: deque[types.TracebackType] = deque(maxlen=_MAX_TRACEBACK_FRAMES)
    node: types.TracebackType | None = trace
    steps = 0
    # Only links are followed here; nothing is formatted until the frames to
    # show have been chosen.
    while node is not None and steps < _MAX_TRACEBACK_WALK:
        kept.append(node)
        node = node.tb_next
        steps += 1
    lines = [_frame_line(item.tb_frame.f_code, item.tb_lineno, budget) for item in kept]
    if node is not None:
        lines.append(f"  {TRUNCATED}")  # deeper than the walk limit
    return lines


def _traceback_units(exc: BaseException, budget: _Budget) -> list[tuple[str, str | None]]:
    """The lines of a traceback, each with what replaces it if its message is withheld.

    The second item is ``None`` for a line built from fixed text and validated
    frame metadata, and ``TypeName: [REDACTED]`` for an exception description.
    """
    chain: list[tuple[BaseException, str | None]] = []
    seen: set[int] = set()
    current: BaseException | None = exc
    link: str | None = None
    while current is not None and id(current) not in seen and len(chain) < _MAX_EXCEPTION_CHAIN:
        seen.add(id(current))
        chain.append((current, link))
        cause = _linked(current, "__cause__")
        context = _linked(current, "__context__")
        if cause is not None:
            current, link = cause, "cause"
        elif context is not None and not _own(current, "__suppress_context__"):
            current, link = context, "context"
        else:
            current = None

    # Built from the exception that was raised backwards, so that when a limit
    # is reached it is the oldest part of the chain that is left out.
    blocks: list[list[tuple[str, str | None]]] = []
    lines_left = _MAX_TRACEBACK_LINES
    length_left = _MAX_TRACEBACK_LENGTH
    complete = True
    for position, (item, _) in enumerate(chain):
        block: list[tuple[str, str | None]] = []
        if position + 1 < len(chain):
            # Printed oldest first: the link from the older exception precedes this one.
            link_line = _CAUSE_LINK if chain[position + 1][1] == "cause" else _CONTEXT_LINK
            block += [("", None), (link_line, None), ("", None)]
        trace = _own(item, "__traceback__")
        if isinstance(trace, types.TracebackType):
            block.append((_TRACEBACK_HEADER, None))
            block += [(line, None) for line in _traceback_frames(trace, budget)]
        description = _describe_exception(item, budget)
        if len(description) > _MAX_DESCRIPTION_LENGTH:
            # Already scrubbed as a unit; a later pass reads the shortened unit again.
            description = f"{description[:_MAX_DESCRIPTION_LENGTH]} {TRUNCATED}"
        block.append((description, f"{_type_name(item)}: {REDACTED}"))
        length = sum(len(line) for line, _ in block) + len(block)
        if len(block) > lines_left or length > length_left:
            complete = False
            break
        lines_left -= len(block)
        length_left -= length
        blocks.append(block)
    units: list[tuple[str, str | None]] = [] if complete else [(TRUNCATED, None)]
    for block in reversed(blocks):
        units += block
    return units


def traceback_lines(exc: BaseException) -> list[str]:
    """The lines of a constructed traceback: one per frame, one per exception description.

    Constructed from frame metadata and scrubbed messages (see "Exceptions and
    tracebacks" in the module docstring); ``traceback.format_exception`` is
    not used because it embeds ``str(exc)``, raw filenames and source lines.
    The result is ordinary untrusted data to every later stage. The pipeline
    itself emits ``traceback_text``. Never raises.
    """
    try:
        return [line for line, _ in _traceback_units(exc, _Budget())]
    except Exception:  # noqa: BLE001 — an exception that cannot be rendered is not emitted
        return [UNREADABLE]


def _is_emitted_unchanged(text: str) -> bool:
    """True if the scrubber, reading ``text`` whole, would emit exactly ``text``."""
    return len(text) <= MAX_STRING_LENGTH and _scrub(text, _Budget(), 0) == text


def traceback_text(exc: BaseException) -> str:
    """A constructed traceback in the standard layout, as one complete text. Never raises.

    The text has no special standing afterwards: the pipeline sanitises it as
    it does any other string, whole, and nothing is joined to it later. It is
    therefore built to be a text the sanitiser emits unchanged, and that is
    checked here on the complete text, not line by line: a message can read
    differently beside the lines that follow it (a masked URL parameter runs
    to the end of the text; a header continues on the next line), and a text
    in which anything is masked beside a newline is masked whole.

    If the complete text is not emitted unchanged, the check is repeated on
    forms that give up a little more each time:

    1. a message in which something was masked, and which other lines follow,
       ends with a space. A masked value at the end of a line would otherwise
       be read on into the next line by a parser that drops newlines; the
       lines that follow a message are fixed text and validated frames, so
       there is nothing for it to continue into;
    2. the messages in which something was masked are withheld
       (``TypeName: [REDACTED]``);
    3. every message is withheld;
    4. the whole traceback is replaced.

    Frames and exception types survive the first three, so a traceback stays
    useful when a message carried a credential. Whichever form is returned,
    it is one the sanitiser was shown complete and left as it is.
    """
    try:
        units = _traceback_units(exc, _Budget())
        last = len(units) - 1
        masked = [
            withheld is not None and (REDACTED in line or TRUNCATED_SENSITIVE in line)
            for line, withheld in units
        ]
        candidates = (
            [line for line, _ in units],
            [
                f"{line} " if masked[index] and index < last else line
                for index, (line, _) in enumerate(units)
            ],
            [
                (withheld or line) if masked[index] else line
                for index, (line, withheld) in enumerate(units)
            ],
            [line if withheld is None else withheld for line, withheld in units],
        )
        for lines in candidates:
            text = "\n".join(lines)
            if _is_emitted_unchanged(text):
                return text
        return REDACTED
    except Exception:  # noqa: BLE001 — an exception that cannot be rendered is not emitted
        return UNREADABLE


def render_exception(exc: BaseException) -> str:
    """``traceback_text`` with a final newline. Never raises.

    The result is a plain ``str`` with no special standing: logged again as a
    field it is scrubbed as one multi-line string like any other text.
    """
    return traceback_text(exc) + "\n"


def stack_lines(frame: types.FrameType | None) -> list[str]:
    """The innermost frames of the stack ending at ``frame``, built as a traceback is."""
    try:
        budget = _Budget()
        lines: list[str] = []
        while frame is not None and len(lines) < _MAX_TRACEBACK_FRAMES:
            lines.append(_frame_line(frame.f_code, frame.f_lineno, budget))
            frame = frame.f_back
        lines.append(_STACK_HEADER if frame is None else f"{_STACK_HEADER} {TRUNCATED}")
        lines.reverse()
        return lines
    except Exception:  # noqa: BLE001 — a stack that cannot be rendered is not emitted
        return [UNREADABLE]


def stack_text(frame: types.FrameType | None) -> str:
    """The stack ending at ``frame`` as one complete text, checked as ``traceback_text`` is."""
    try:
        text = "\n".join(stack_lines(frame))
        return text if _is_emitted_unchanged(text) else REDACTED
    except Exception:  # noqa: BLE001 — a stack that cannot be rendered is not emitted
        return UNREADABLE
