# D0 — findings register and controlled reconciliations

Development phase D0 (Engineering Foundation & Backend Bootstrap). This is a
**non-frozen development record**. It does not modify any frozen architecture
document; the two reconciliations below are carried here until they are
formally consolidated into the frozen set.

Status of D0 after remediation pass 7 (targeted logging provenance
remediation, D0-P1-12): **ready for final independent development freeze-gate
review**. It has not been approved or frozen. The statements "ready" made
after passes 1 to 6 were each shown wrong by the review that followed (for
pass 6: review 7, one finding); they are kept below as they were made.

Review history:

| Review | Result | Open after review |
|---|---|---|
| Codex review 1 | REMEDIATION REQUIRED | P0 = 1, P1 = 6, Minor = 3 |
| Codex review 2 (after remediation pass 1) | REMEDIATION REQUIRED | P0 = 1 (D0-P0-01 still open), P1 = 2 (D0-P1-07, D0-P1-08 new), Minor = 0. Confirmed resolved: D0-P1-01 … D0-P1-06 (original reproduction), D0-M-01 … D0-M-03; OD-D0-01 and OD-D0-02 correctly applied |
| After remediation pass 2 | awaiting independent re-review | P0 = 0, P1 = 0, Minor = 0 (self-assessed; review 3 showed this was wrong for D0-P0-01) |
| Codex review 3 (after remediation pass 2) | REMEDIATION REQUIRED | P0 = 1 (D0-P0-01 still open: six further reproductions), P1 = 0, Minor = 1 (D0-M-04 new). Confirmed resolved: D0-P1-01 … D0-P1-08, D0-M-01 … D0-M-03; OD-D0-01 and OD-D0-02 correctly applied |
| After remediation pass 3 (final targeted) | awaiting final independent review | P0 = 0, P1 = 0, Minor = 0 (self-assessed; review 4 showed this was wrong for D0-P0-01 and D0-M-04) |
| Codex review 4 (after remediation pass 3) | REMEDIATION REQUIRED | P0 = 1 (D0-P0-01 still open: six further exposure classes, §2b), P1 = 0, Minor = 1 (D0-M-04 still open: incomplete whole-event boundedness), owner decisions = 0. Confirmed resolved: D0-P1-01 … D0-P1-08, D0-M-01 … D0-M-03; OD-D0-01 and OD-D0-02 correctly applied |
| After remediation pass 4 (security boundary) | awaiting independent review | P0 = 0, P1 = 0, Minor = 0 (self-assessed; review 5 showed this was wrong for D0-P0-01 and D0-M-04) |
| Independent ZIP review 5 (after remediation pass 4) | REMEDIATION REQUIRED | P0 = 1 (D0-P0-01 still open: a constructible trusted-text type bypasses redaction; a multi-line traceback filename leaks, §2c), P1 = 1 (D0-P1-09 new: signed-media URL fields not redacted), Minor = 1 (D0-M-04 still open: work before admission), owner decisions = 0. No new regression in D0-P1-01 … D0-P1-08; OD-D0-01 = B and OD-D0-02 = A remain binding |
| After remediation pass 5 (trust model) | awaiting independent review | P0 = 0, P1 = 0, Minor = 0 (self-assessed; review 6 showed this was wrong) |
| Codex review 6 (after remediation pass 5) | REMEDIATION REQUIRED | P0 = 2 (D0-P0-02 = F1, D0-P0-03 = F2), P1 = 2 (D0-P1-10 = F3, D0-P1-11 = F4), Minor = 1 (D0-M-05 = F5), owner decisions = 0. All existing quality gates passed while the defects were present (independent probes: 24 stdout sentinel occurrences for F1, 4 stderr occurrences for F2) |
| After remediation pass 6 (pipeline order) | awaiting independent review | P0 = 0, P1 = 0, Minor = 0 (self-assessed; review 7 showed this was wrong) |
| Independent review 7 (after remediation pass 6) | REMEDIATION REQUIRED | P0 = 0, P1 = 1 (D0-P1-12 new: standard-library `LogRecord` attributes bypass authoritative logging metadata), Minor = 0, owner decisions = 0 |
| After remediation pass 7 (logging provenance) | awaiting final independent review | P0 = 0, P1 = 0, Minor = 0 (self-assessed; §2e) |

## 1. Controlled reconciliations pending formal consolidation

### CONTROLLED ARCHITECTURE RECONCILIATION — OD-D0-01 (owner decision B)

**Subject.** Where "the database schema is at the expected migration head" is verified.

**Frozen wording affected.** 3E and 3F describe application readiness as
including a migrations-current check. Under the frozen Phase-5 grants the
least-privileged runtime role `app_api` holds no `SELECT` on
`public.alembic_version`, so the application cannot perform that check.

**Decision.** Migration-current verification is a mandatory **deployment /
pre-rollout gate against the actual target database**, run with
migration/deployment credentials. The runtime role gains no access:
no migration 113, no grant on `alembic_version`.

| | Runtime readiness | Deployment gate |
|---|---|---|
| Question | Are PostgreSQL and Redis operationally reachable now? | Is the target schema at exactly the expected head? |
| Where | `GET /health/ready`, inside the application | `scripts/db_migrate.py gate --expected-head <rev>`, before rollout |
| Credentials | `app_api` | migration/deployment role (runtime roles refused) |
| Claims schema currency | Never | Yes; exits non-zero on any doubt |

**Implementation.**

- `scripts/db_migrate.py gate`: validates the repository graph against the frozen
  baseline; requires `--expected-head` to equal the repository head and the head
  the build requires; derives and checks the libpq target before connecting;
  refuses runtime roles (URL user, `session_user`, `current_user`); requires the
  connected database to be the one named; requires `alembic_version` to record
  exactly the expected head; requires the extensions. Fails closed; output
  carries no credential.
- `.github/workflows/deployment-schema-gate.yaml`: reusable gate job for
  deployment pipelines (target environment secret `MIGRATION_DATABASE_URL`).
- Startup logs `schema_revision_status=deployment_gated` (previously
  `unverifiable`), stating ownership rather than suggesting a failed check.
- README distinguishes the two checks; no D0 text says readiness verifies the head.

**To consolidate later.** Amend the 3E/3F readiness wording to match the table above.

### CONTROLLED API ERRATUM — OD-D0-02 (owner decision A)

**Subject.** The frozen `API-ERROR-CATALOG.md` has no code for a request made
with a method the route does not support.

**Decision.** `METHOD_NOT_ALLOWED`, HTTP 405, `retryable = false`, in the
standard error envelope, with the HTTP `Allow` header preserved. 405 is not
exempt from the envelope and is not reported as `VALIDATION_ERROR`.

**Implementation.** `voice_agent/apps/api/error_catalog.py` is the governed
catalog adapter: every error response is built from it. Each entry records its
authority (`API-ERROR-CATALOG` or `OD-D0-02`). Tests cross-check every
frozen-authority entry against the frozen document and assert that
`METHOD_NOT_ALLOWED` is the only entry outside it.

**To consolidate later.** Add the `METHOD_NOT_ALLOWED` row to the frozen catalog.

## 2. Findings from the independent review (Codex)

Independent result: **REMEDIATION REQUIRED** — P0 = 1, P1 = 6, Minor = 3,
architecture/owner reconciliations = 1, environmental evidence gaps = 2. The
existing suite (140 tests) passed while these defects were present.

A finding is marked RESOLVED only where its regression tests pass in the full
suite and a mutation probe re-introducing the defect is detected (§4).

| ID | Severity | Finding (as independently reported) | Remediation | Regression tests | Status |
|---|---|---|---|---|---|
| D0-P0-01 | P0 | Credential text redaction. Review 1: query-string passwords, secrets nested past the recursion limit, exception text, credential URLs, cyclic data, formatter failure paths, logging-stack stderr diagnostics. **Review 2 (still open):** escaped JSON password and access-token values, escaped libpq password values, percent-encoded sensitive query keys, exceptions containing escaped JSON credentials; a mapping whose `items()` raises made the sanitiser raise | Pass 1: fail-closed structural sanitiser and guarded pipeline. Pass 2: the pattern-based text layer was replaced by layers that interpret the text — embedded JSON is parsed and sent through the structural sanitiser; key/value pairs are found by a scanner that classifies the percent-decoded key and delimits values with an escape- and quote-aware state machine, masking to the end where a value cannot be delimited; percent-decoded and backslash-unescaped views are scrubbed and a view revealing a hidden credential masks the token/string; unreadable containers become a marker; `sanitize`/`scrub_text` cannot raise; standard-library log arguments are sanitised structurally before interpolation; mapping keys are scrubbed like values | `tests/unit/test_logging.py`; `tests/unit/test_redaction_encodings.py` (77 text forms × 7 logging channels, 16 structured shapes × 2 renderers, formatter and writer failure, precision and performance). **Review 3 (still open after pass 2):** six further leaks — a value that merely starts with `[REDACTED]` (libpq and query), nine spaces after and before `=`, an apostrophe in URL userinfo, credential JSON wrapped seven times. **Pass 3:** see §2a **Review 4 (still open after pass 3):** six further exposure classes — a libpq value continued after an EM SPACE; a PostgreSQL URI password continued after a tab or newline; folded `Cookie` and Digest `Authorization` headers; a long URI password in an exception, cut before it was classified; a long URL-shaped logger name on the formatter-failure (stdout) and writer-failure (stderr) paths; subclasses of path, Decimal, UUID and date types converting themselves. **Pass 4:** see §2b | pass 2 tests plus `tests/unit/test_redaction_invariants.py` and `tests/unit/test_redaction_fuzz.py` (§2a); pass 4: `tests/unit/test_logging_boundary.py` (§2b) | RESOLVED (pass 5, §2c: no trusted text, constructed tracebacks; `tests/unit/test_logging_trust.py`. Previously marked resolved after passes 1, 2, 3 and 4 and reopened by reviews 2, 3, 4 and 5) |
| D0-P1-01 | P1 | Cancellation loses resource ownership: references cleared before cleanup; cancel during Redis close skipped PostgreSQL disposal; second `stop()` reported STOPPED | Reference kept until its release completes; release runs in its own task and the cancelled caller waits for it before re-raising; failed/timed-out release stays owned and retryable; STOPPED only when nothing is owned; `close()`/`dispose()` retry-safe | `tests/unit/test_runtime_release.py`; `tests/integration/test_dependency_outage.py::test_cancelled_shutdown_leaves_no_connection_behind` | RESOLVED |
| D0-P1-02 | P1 | DB query options bypass the test-target guard (`?database=…` changes the effective asyncpg target) | Only `ssl` accepted as a query parameter; single-host and port validation; engine passes host/port/user/database explicitly so URL options and `PG*` variables cannot override | `tests/unit/test_database_target.py` (inspects real `asyncpg.connect` arguments and resolves them with asyncpg's parser under a hostile environment) | RESOLVED |
| D0-P1-03 | P1 | Runtime-password tool local guard bypass via libpq query options | Effective libpq target derived and validated before any connection (query allowlist, explicit port, single host, `PGHOSTADDR`/`PGSERVICE`/`PGSERVICEFILE` refused, same host/port/database for both URLs); server actually reached verified before `ALTER ROLE` | `tests/unit/test_migration_cli.py` (`_connect` intercepted) | RESOLVED |
| D0-P1-04 | P1 | Unauthorized 405 code/status mapping (405 emitted as `VALIDATION_ERROR`) | OD-D0-02 applied through the governed catalog; uncataloged HTTP statuses can no longer be emitted | `tests/unit/test_api_http.py` | RESOLVED |
| D0-P1-05 | P1 | Redis non-PONG accepted (PING result discarded) | Only an exact positive reply is healthy; anything else is a safe `CacheError`; raw reply never exposed | `tests/unit/test_dependency_failures.py`; `tests/integration/test_redis.py`; `tests/integration/test_dependency_outage.py` (fake RESP peer, real Redis recovery) | RESOLVED |
| D0-P1-06 | P1 | General request-time DB outages mapped to `INTERNAL_ERROR` 500 | Central classifier (`db/errors.py`) applied at `Database.transaction()`: outages become `DatabaseError` → 503 `DEPENDENCY_UNAVAILABLE` retryable; constraint/SQL/application errors and cancellation unchanged | `tests/unit/test_dependency_failures.py`; `tests/integration/test_dependency_outage.py` | RESOLVED |
| D0-P1-07 | P1 | (Review 2) Connection-acquisition refusal: with `ALLOW_CONNECTIONS false` and existing sessions terminated, a request got 500 `INTERNAL_ERROR` (asyncpg `ObjectNotInPrerequisiteStateError`, SQLSTATE 55000) while readiness reported PostgreSQL unavailable | `Database.transaction()` now acquires its connection explicitly as a distinct step; a failure there is by construction an acquisition failure and is classified by `is_connection_acquisition_unavailable`, which adds SQLSTATE 55000 for that phase only. 55000 raised by a statement on an established connection is unchanged (500). Rejected credentials (class 28) are not an outage in either phase | `tests/integration/test_dependency_outage.py::test_database_refusing_new_connections_then_recovery` (real PostgreSQL 18), `::test_sqlstate_55000_from_a_statement_is_not_an_outage`, `::test_rejected_credentials_at_acquisition_are_not_an_outage`; `tests/unit/test_dependency_failures.py` | RESOLVED |
| D0-P1-08 | P1 | (Review 2) CORS preflight bypassed the error and correlation contract: rejected preflight was `400 text/plain "Disallowed CORS origin"` with no envelope and no `X-Request-ID`; successful preflight had no `X-Request-ID` | Project-owned `ApiCorsMiddleware` (subclass of Starlette's) keeps Starlette's policy evaluation and CORS headers and replaces a rejection body with the cataloged `VALIDATION_ERROR` / 400 envelope (no new error code). Middleware order is now correlation → CORS → error capture → routes, so every preflight carries a server-generated request ID. Rejection reasons go to the log only | `tests/unit/test_cors.py` (full ASGI stack); `tests/smoke/test_server.py` (real HTTP against uvicorn) | RESOLVED |
| D0-P1-09 | P1 | (Review 5) Signed-media URL fields not redacted: `sanitize_event` emitted the values of `download_url`, `upload_url`, `presigned_url` and `signed_url`, which 6A §22 prohibits by name. Such a URL is a bearer capability and need not contain `signature` or `token` | Structural classification by field name (`_CAPABILITY_KEY`), in structured data, embedded JSON and `key=value` text; provider signing parameters masked by name. See §2c | `tests/unit/test_logging_trust.py` (capability fields) | RESOLVED |
| D0-P0-02 | P0 | (Review 6, F1) **Post-sanitizer join credential disclosure.** `exception=["Cookie: session=[REDACTED]", " " + secret]` (and the same under `stack`): each list item was sanitised alone and `join_unit_lists` joined them *after* the final sanitiser, recreating a folded credential. 24 stdout sentinel occurrences across logger types, renderers and credential forms | Nothing is joined after the sanitiser. Caller fragments under `exception`/`stack` (lists, tuples, nested lists) are assembled into the one text they are laid out as *before* sanitising (`redaction._assembled_text`, bounded), and the complete text is sanitised as one string. `join_unit_lists` is removed. Internally built tracebacks and stacks are produced as one complete text (`traceback_text`, `stack_text`) checked whole against the sanitiser. See §2d | `tests/unit/test_logging_closure.py` (F1 group) | RESOLVED (pass 6, §2d) |
| D0-P0-03 | P0 | (Review 6, F2) **Reserved metadata disclosure to additional handlers.** A caller field named `_record` or `_from_structlog` was copied past the sanitiser as "processor metadata" by `redact_sensitive_fields`, so an independent `StreamHandler(sys.stderr)` received `password=<secret>` (4 stderr occurrences). The project formatter happened to overwrite the key, so its own output was clean | A field name gives a value no standing. Callers' `_record`/`_from_structlog` are removed at entry (after context merge, before anything reads them) and their removal is noted by a fixed `[RESERVED]` field. The genuine formatter metadata is believed only where the formatter has just written it, decided by where the pipeline instance is installed (`foreign=True` pre-chain), never by the event's content; it is dropped by `_discard_processor_metadata` before the final pass. The final pass passes no key through unsanitised. Operational metadata (level, logger, service, environment, timestamp) is established by the pipeline itself, not from event fields. See §2d | `tests/unit/test_logging_closure.py` (F2 group) | RESOLVED (pass 6, §2d) |
| D0-P1-10 | P1 | (Review 6, F3) **Signed URL scope/expiry data retained.** A CloudFront URL kept `Expires` and `Key-Pair-Id` beside a masked `Signature`; an Azure SAS URL kept `sv`, `se`, `sp`, `sr` beside a masked `sig` (6A §22) | A URL whose query or fragment carries a signature or signing-key parameter is a capability as a whole and is replaced from its scheme to the end of its last parameter. The parameter set is read as a whole: case-insensitive, percent-decoded keys, any order, extra parameters included. Covers CloudFront, Azure SAS, AWS SigV4/SigV2, Google V4/V2, Alibaba OSS V1/V4, Tencent COS, and scheme-less request-line forms. Ordinary unsigned URLs are unchanged. See §2d | `tests/unit/test_logging_closure.py` (F3 group) | RESOLVED (pass 6, §2d) |
| D0-P1-11 | P1 | (Review 6, F4) **Loss of event/request ID at the admission boundary.** With `request_id` bound, 199 fields dropped the request ID and 200+ dropped the event name too; an HTTP request returned a valid `X-Request-ID` whose log line had neither | Operational metadata is a protected schema outside the payload budget. Level, logger, service, environment and timestamp are established by the pipeline; the request ID comes from the server's request context, then a context binding, then (outside a request) a call field, and is never displaced or renamed by payload. The event name, traceback and stack are sanitised first and take none of the 200 field places (`sanitize_event(leading=…)`); the bound logger's admission likewise keeps `event`/`exc_info` apart. Payload beyond 200 fields is cut with `[TRUNCATED]: event field limit reached`. See §2d | `tests/unit/test_logging_closure.py` (F4 group, incl. real ASGI middleware) | RESOLVED (pass 6, §2d) |
| D0-P1-12 | P1 | (Review 7) **Standard-library LogRecord attributes bypass authoritative logging metadata.** The handler took a record for one made by structlog if it had the attributes `_logger` and `_name`, which any standard-library caller can attach through `extra=`. Such a record skipped the stage that establishes operational metadata, and the final pass read that metadata from the event: a mapping logged as a message chose its own `request_id`, `service`, `environment`, `level` and `timestamp`, also while a server `RequestContext` was bound | No stage reads the origin of a record from the record. The final pass establishes level, logger, timestamp, service, environment and the server request ID for *every* record, from the log record, the configuration and the request context, and reads none of them from the event. `_logger`/`_name` are never copied from a record; a record is an event of the pipeline only if its message is the very object the pipeline produced last in the same thread, and that decision confers no metadata. See §2e | `tests/unit/test_logging_provenance.py` | RESOLVED (pass 7, §2e) |
| D0-M-05 | Minor | (Review 6, F5) **Oversized scalar pre-admission allocation.** A 10,000,000-character `str` subclass allocated about 10 MB inside logging before rejection (`str.__str__` copy); a 10,000,000-digit `Decimal` about 4 MB (`create_decimal`) | Size is checked before any copy or conversion: `str` subclasses are measured with `str.__len__` and only a bounded prefix is taken with `str.__getitem__` (`leading_text`); a `Decimal` is refused by `Decimal.__sizeof__` before its coefficient is read; an `int` subclass by `int.bit_length` before `int.__int__` copies it (found in this pass). Applied to values, mapping keys, exception messages, standard-library format strings and assembled fragments. See §2d | `tests/unit/test_logging_closure.py` (F5 group) | RESOLVED (pass 6, §2d) |
| D0-M-01 | Minor | Malformed CORS port accepted (`https://app.example:notaport`) | Strict origin grammar: scheme, host, numeric port 1–65535, no wildcard/userinfo/path/query/fragment; HTTPS still required in staging/production | `tests/unit/test_config.py` | RESOLVED |
| D0-M-02 | Minor | `infra/**` changes skip CI | Path filters include `infra/docker/**` and `infra/docker-compose/**`; new `container` job builds the image and runs the Compose stack | `tests/unit/test_repository_guards.py` | RESOLVED (static; see §5) |
| D0-M-03 | Minor | Test password appears in `repr` | Passwords excluded from harness dataclass reprs; Redis password passed on stdin, not argv | `tests/unit/test_migration_cli.py::test_harness_objects_never_show_generated_passwords_in_repr`; `tests/integration/test_redis.py::test_harness_never_exposes_the_redis_password` | RESOLVED |

| D0-M-04 | Minor | (Review 3) Shared-container traversal/output amplification: the structured sanitiser bounded depth, items per container and active-ancestor cycles, but had no whole-event budget, so a small acyclic graph of repeated references expanded to more than 1 MB of output and seconds of work | Whole-event budget shared by every value of one sanitisation (values visited, text examined, rendered output); a container is expanded once per event and a later reference is `[REPEATED]`; an absolute bound on the rendered line. See §2a **Review 4 (still open after pass 3): incomplete whole-event boundedness** — `logging.py` copied every event field before the sanitiser's limits applied (a 100,000-entry mapping: all entries visited, 5.77 MB allocated); a format string such as `%10000000s` was interpolated before anything bounded it (about 10 MB); non-string scalars were charged a fixed 24 characters, so integers rendered about 79,404 characters against a 65,536 budget. **Pass 4:** bounded admission at the first traversal, bounded percent formats, actual scalar accounting; see §2b | `tests/unit/test_redaction_invariants.py` (shared references, node/scan/output budgets, rendered-line bound, hostile text, fresh-interpreter run); pass 4: `tests/unit/test_logging_boundary.py` (admission counters, allocation peaks, percent formats, scalar accounting) | RESOLVED (pass 5, §2c: context variables, record attributes and traceback filenames admitted before any work; `tests/unit/test_logging_trust.py`. Previously marked resolved after passes 3 and 4 and reopened by reviews 4 and 5) |

Owner reconciliation raised by the review: migration-current verification →
OD-D0-01 above (applied).

### 2a. Pass 3 — what changed for D0-P0-01 and D0-M-04

The six reproductions were not patched individually. The causes were four
assumptions, each removed:

| Assumption that leaked | Replaced by |
|---|---|
| A value beginning with `[REDACTED]` is already masked | No rule looks at whether a value resembles a mask. Text that starts with, ends with or contains the marker is scrubbed like any other. Nothing is skipped for being "already masked" |
| At most eight spaces surround a separator (and at most eight backslashes precede a quote) | Keys, separators and values are read by a deterministic scanner: any amount and kind of whitespace (including whitespace written as an escape), single- and double-quoted values with backslash and doubled-quote escapes, brackets, subscripted keys. No bounded-repetition pattern is involved |
| Userinfo consists of characters from a hand-written list (which omitted `'`) | The authority is delimited as a URL parser does and the whole userinfo is masked whatever it contains. Query and fragment parameters are split on `&` and classified by their percent-decoded keys. An authority that looks like `user:password` but has no `@` in reach (password containing `/`, `?`, `#` or a space) is masked |
| JSON nested deeper than a fixed count can be passed through | Embedded JSON is unwrapped until nothing is left to unwrap. The nesting limit and the parse allowance still exist so that work is bounded, but reaching either masks the unexamined JSON instead of emitting it |

Two structural changes support these:

- **Sanitised JSON is opaque to the text rules.** A structurally sanitised
  fragment is held aside and represented by a placeholder while the text rules
  run, so they neither re-read its content as free text nor split it; a rule
  whose value is the fragment (`credentials={…}`) masks it whole. Pass 2 needed
  the "already masked" shortcut precisely because its text rules re-read the
  JSON layer's output.
- **Decoded views are compared with the original, not applied to the result.**
  The original text is decoded round by round (percent, backslash, character
  reference, compatibility forms; whole and token by token) and each form is
  scrubbed on its own. Everything the scrubbed raw text still shows must also
  be shown by each view; otherwise, or if decoding does not reach a fixed
  point in three rounds, the whole string is masked.

Every limit now costs fidelity only: nesting, parse allowance, decode rounds,
string length, scan budget, node budget, output budget and the rendered-line
bound all end in a marker, never in unexamined input.

**D0-M-04 limits (documented D0 values, `redaction.py` / `logging.py`).**

| Limit | Value | When reached |
|---|---|---|
| Values visited per event (`MAX_EVENT_NODES`) | 2,048 | further values become `[TRUNCATED]`; the open container gets one marker and stops |
| Text examined per event, all passes (`MAX_EVENT_SCAN`) | 524,288 characters | further strings become `[TRUNCATED]`; a decoded view that cannot be afforded masks its string |
| Rendered scalar text per event (`MAX_EVENT_OUTPUT`) | 65,536 characters (JSON-rendered length) | the current, already scrubbed string is cut and marked; later values become `[TRUNCATED]` |
| Rendered line (`MAX_RENDERED_EVENT_LENGTH`) | 131,072 characters | the line is replaced by a fixed `log_record_oversized` record |
| Per value (unchanged) | depth 8, 200 items, 16,384 characters | `[TRUNCATED]` |

These are deterministic work limits, not timers. Repeat policy: a non-empty
container is expanded once per event; a second reference is `[REPEATED]`, a
reference to a container still being expanded is `[CYCLE]`. Neither uses the
object's `repr`. Identity fields (timestamp, level, logger, service,
environment, request ID) are sanitised first so they survive an event that
exhausts the budget.

The sanitiser also now returns exact built-in types only: subclasses of `str`,
`int` and `float` are rebuilt, oversized integers and non-identifier type names
become markers.

### 2b. Pass 4 — the logging trust boundary (D0-P0-01, D0-M-04)

Review 4 reproduced six further exposure classes and three unbounded stages.
All twelve were reproduced against the pass-3 code before anything was changed
(nine leaks on stdout or stderr; 100,000 of 100,000 entries visited with a
5.77 MB peak; a 10.04 MB peak for `%10000000s`; 83,621 rendered characters of
integers against the 65,536 budget).

They were not patched one pattern at a time. Passes 1–3 kept adding rules that
recognise credentials; each review then found a form the rules read
differently from the software that would consume the text. Pass 4 changes
what is allowed to reach a sink instead:

> Unknown or ambiguous input is replaced by a fixed marker before it can reach
> stdout, stderr or a handler. The sanitiser does not claim to find every
> secret in arbitrary text.

| Cause (review 4) | Was | Now |
|---|---|---|
| Grammar confusion: libpq EM SPACE, URI tab/newline, folded headers | Each rule decided alone where a value ends; Python's `str.isspace()` ended a libpq value; whitespace ended a URL; a newline ended a header | An unquoted value ends only at the ASCII whitespace libpq itself uses. A URL credential is searched for across whitespace, and a sensitive parameter is masked to the next `&` or the end of the string. Above all, **a string in which any rule masked something — as written, or with control characters and non-ASCII whitespace removed, as parsers that delete them read it — and which contains such a character is replaced whole** (`[REDACTED]`). A credential header and its folded continuation therefore go together |
| Truncation-induced reclassification: a long URI password in an exception | The message was cut to 2,048 characters and then scrubbed; without its `@host` the rest looked like `host:port` | Text is classified in full within the scrubber's limit and only its *scrubbed* form is shortened. Text beyond the limit (16,384 characters, or the event's scan budget) is never classified from its prefix: any sign of a credential in the examined part yields `[TRUNCATED_SENSITIVE_VALUE]`; otherwise the last, possibly incomplete, token is dropped as well |
| Logger name treated as safe text | Shortened to 128 characters, then scrubbed; the formatter- and writer-failure paths printed that | Logger, service and environment names, level, timestamp and request ID are **trusted identifiers**: an exact `str` of at most 128 characters that matches the grammar of its kind and that the text rules leave untouched. Anything else is replaced by a fixed word (`untrusted_logger`, `untrusted_service`, `untrusted_environment`, `untrusted_request_id`, `unknown`). Nothing is cut or converted first, and the emergency paths use only these validated values and fixed text |
| Subclass conversion trusted | `isinstance()` followed by `str(value)` / `value.isoformat()` | The real type decides (`type(value)`, never `__class__`). `str`, `int`, `float` subclasses are read through the base type's own slots. UUID, Decimal, date, time, datetime (standard `tzinfo` only), timedelta, pure and concrete paths, bytes: exact type only, rendered by a serializer of the sanitiser's own. Enum members: the stored `_value_`, not a `value` property. Everything else, including every subclass of the above: `[UNSUPPORTED]`. Type names of unknown objects are no longer emitted |

**Trust model.** (§17 of the remediation brief.)

| Question | Answer |
|---|---|
| Which values are trusted? | Fixed text in the pipeline; identifiers that pass `trusted_identifier`; exception class names that match an ASCII identifier grammar; text the sanitiser itself produced (carried in a private `str` type, recognised only by its exact type, so that the second sanitising pass does not re-read an assembled traceback as one unknown multi-line string) |
| Which values are untrusted? | Every string, including event text and the format string of a standard-library call; every argument and field; every object; exception text; the logger name and every other record attribute |
| Which formats are supported for semantic redaction? | `key=value` / `key: value` pairs and libpq connection strings (quoted, escaped, percent-encoded); URL userinfo and sensitive query/fragment parameters; credential headers; bearer and Digest credentials; JWTs; PEM private keys; JSON embedded in text; `user:password@host` as one whitespace-free token |
| What happens when the format is unknown? | A string is emitted as written only if no rule finds anything in it, as written and joined up. An object of an unsupported type is `[UNSUPPORTED]` |
| What happens when parsing is incomplete? | A value that cannot be delimited masks the rest of its line or string (pass 3); a credential beside a control character or non-ASCII whitespace masks the whole string (pass 4) |
| What happens when the value is over budget? | `[TRUNCATED_SENSITIVE_VALUE]`, or `[TRUNCATED]` with at most the examined, credential-free part. Never an unexamined remainder |
| Can a custom object conversion execute before sanitisation? | No `__str__`, `__repr__`, `__format__`, `isoformat`, `__fspath__` or `value` property of an untrusted object is called. One conversion does run: `str()` of an exception, the only way to obtain its message; its result is untrusted text and is scrubbed as such. A container's own `__len__` and iteration run and yield values that are sanitised in turn |
| Can logging metadata contain untrusted text? | Not in the output: every identifier is validated or replaced; module, path and function names of a record are not emitted |
| Can failure diagnostics bypass the sanitiser? | The formatter-failure, oversized-line, unsafe-format and writer-failure paths emit fixed text, validated identifiers and a validated exception class name. They never read the record's message or arguments |
| Can an intermediate stage allocate unbounded data? | Not in this module's code; see the limits below. What the caller allocated before calling (a huge string, the keyword dictionary Python builds for `**fields`) and what an exception's own `__str__` allocates are outside it |

**Limits (D0-M-04).** One budget covers the event from the first traversal to
the rendered line. Each limit is a deterministic count, applied before the
work it bounds.

| Stage | Limit | When reached |
|---|---|---|
| Admission of fields (`MAX_EVENT_FIELDS`) | 200 per call, per `bind()` and per event | The event mapping is iterated lazily and never copied; the remaining entries are not visited, referenced or rendered; one `[TRUNCATED]` field stands for them. The bound logger drops surplus keyword arguments before structlog copies them |
| Standard-library interpolation | Format string of at most 16,384 characters and 64 directives; width and precision at most 256; no `*` | A fixed `log_record_unsafe_format` record; nothing is interpolated. Arguments are sanitised (and thereby bounded) before interpolation |
| Values visited (`MAX_EVENT_NODES`) | 2,048 | `[TRUNCATED]` |
| Text examined (`MAX_EVENT_SCAN`) | 524,288 characters, all passes | `[TRUNCATED]` / `[TRUNCATED_SENSITIVE_VALUE]` |
| Text rendered (`MAX_EVENT_OUTPUT`) | 65,536 characters. Every scalar is charged its actual rendered length plus separators; a value that does not fit is replaced, not emitted. Markers standing for what was cut are not charged: at most two per open container (under 512 characters in all) | `[TRUNCATED]` |
| Scalar size | Integers above 128 bits (rejected by bit length); Decimals above 40 significant digits (rejected by rounding to a fixed precision) | `<int: N bits>`, `<Decimal: too long>`; the number is never rendered to be measured |
| Per value | depth 8, 200 items, 16,384 characters | `[TRUNCATED]` |
| Repeated references | A container is expanded once per event | `[REPEATED]`, `[CYCLE]` |
| Traceback | 32 innermost frames per exception, 10 chained exceptions, 32,768 characters | `[TRUNCATED]` |
| Rendered line (`MAX_RENDERED_EVENT_LENGTH`) | 131,072 characters | fixed `log_record_oversized` record |

Measured after pass 4: 201 entries visited for mappings of 2,000, 20,000 and
100,000 entries (peak allocation 0.03 MB); `%10000000s` produces the fixed
record with a peak below 0.2 MB; 2,400 integers of 39 digits render within the
budget plus markers; `10**1_000_000` and a 100,000-digit Decimal are rejected
with a peak below 0.05 MB.

**Verification after pass 4.** 8,889 tests (8,815 unit, 74 integration and
smoke against disposable PostgreSQL 18 and Redis) pass in normal, reverse and
seeded random order (`random:20261007`); `ruff format --check`, `ruff check`,
`mypy` and `scripts/verify.py` pass. `tests/unit/test_logging_boundary.py`
adds 1,949 tests: 55 credential forms, 49 of them confirmed as credential
material by an independent parser on every platform (libpq through psycopg,
SQLAlchemy, `urllib`, the standard HTTP header parser; no connection is
opened) and 6 only where the local libpq reads them so, through 12 logging channels and 3 failure paths in
both renderers, with stdout and stderr checked separately. A further random
probe of about 58,000 parser-confirmed libpq and URI forms found no leak. Of
the 6,937 tests that existed before pass 4, twelve asserted the behaviour that
pass 4 deliberately changed (partial masking beside a tab or newline, a
`[TRUNCATED]` suffix on cut credential text, type names for unknown objects)
and were updated to the new policy; none was removed.

**Not covered, by design.** These are stated so that they are not mistaken for
guarantees:

- A bare secret in an ordinary string or under an innocent field name. Nothing
  marks it as a credential.
- `user:password@host` without a scheme where the password contains
  whitespace; a `Basic` credential without its header name; a key and value
  separated only by a tab. None is a form any parser in this stack reads.
- An exception whose own `__str__` returns a bare secret, which is the same
  case as the first.

### 2c. Pass 5 — no trusted text (D0-P0-01, D0-P1-09, D0-M-04)

Review 5 reproduced two exposures, one unprotected field class and three
stages that worked before any limit applied. All were reproduced against the
pass-4 source before anything was changed, and again after (§2c "Results").

Pass 4 had introduced the defect it was trying to avoid. Because the event is
sanitised twice, and an assembled traceback read as one multi-line string
would be masked whole by the ambiguity rule, pass 4 marked its own output with
a private `str` subclass and skipped strings of that type (D0-SR-13). A class
is not a statement about where a value came from: `type(render_exception(e))`
handed the class to any caller, who could then construct an instance holding
anything. The traceback itself was formatted by `traceback.format_tb` and
cleaned one line at a time, so a filename spanning two lines lost the
credential context of its first line on its second.

Neither was fixed by hiding the type or adding a pattern. The cause was that
the design needed a notion of "already safe" at all. It no longer has one.

#### Security design of the logging boundary

*(Kept as written after pass 5. Pass 6 (§2d) changed two points below: a
traceback is no longer a list of units joined after the final pass, and
processor metadata is no longer passed through the sanitiser by key name.)*

**What is trusted.** Only two things: fixed text written in this package
(event names of the emergency records, the traceback header and link lines,
the fixed words that replace an unsafe value), and identifiers that passed
`trusted_identifier` (logger, service, environment, level, timestamp, request
ID: an exact `str` of bounded length matching a conservative grammar that the
text rules also leave unchanged). There is no trusted text, no trusted type
and no trusted object. `redaction.py` defines no `str` subclass and every
string it returns is the exact built-in type.

**Where untrusted values are admitted.** At the first stage the logging
package owns, and in bounded number:

| Source | Admission | Limit |
|---|---|---|
| Fields of a structlog call, bound fields | `BoundedBoundLogger` (before structlog copies them) | `MAX_EVENT_FIELDS` = 200 |
| Context-local fields | `merge_bounded_contextvars`: the context is iterated lazily; a value is fetched only for an admitted field | 200 fields, 800 variables looked at |
| A standard-library record | `_bounded_copy`: a fixed set of 23 attribute names is looked up; `record.__dict__` is never iterated or copied, by this package or by structlog's formatter, which receives only the bounded copy | constant |
| A standard-library format string and its arguments | `_is_bounded_template`, then structural sanitising of the arguments before interpolation | 16,384 characters, width 256, 64 directives |
| `exc_info`, `stack_info` | `traceback_lines`, `stack_lines` (below) | 32 frames per exception, 192 units, 32,768 characters |
| Every field value | `sanitize_event` | 2,048 values, 524,288 characters examined, 65,536 rendered |

**Where redaction occurs.** In `redact_sensitive_fields`, which runs twice on
every event: at the end of the shared processor chain (so that the event held
in a `LogRecord`, visible to any other handler, is already clean) and again as
the last step before layout and rendering. Both runs treat every value as
untrusted, including everything the first run returned. Standard-library
arguments are additionally sanitised before `%` interpolation.

**Why a caller cannot bypass it.** A bypass needs a value the sanitiser
declines to read. `_text` has one path: scrub, then charge. `_sanitize`
dispatches on the real type (`type(value)`), reads `str`, `int` and `float`
subclasses through the base type's own slots, and replaces anything it does
not recognise by a fixed marker. No branch depends on a class a caller can
construct, on an attribute, on a prefix such as `[REDACTED]`, or on a key such
as `exception`. The functions that produce safe text (`render_exception`,
`traceback_lines`, `describe_exception`, `scrub_text`) return plain strings
with no standing: handed back to a logger they are scrubbed again.

Running the sanitiser twice is safe without an exemption because of how its
output is shaped, not because it is recognised: every unit the module emits is
one that the text rules leave unchanged or mask further. A second pass can
therefore lose fidelity but never confidentiality, and for tracebacks it loses
nothing (next paragraph).

**How traceback values are processed.** A traceback is constructed from frame
metadata; nothing the standard library formatted is ever cleaned up.

1. The exception chain is followed through `BaseException`'s own descriptors
   (at most 10 links), and each traceback's `tb_next` links are walked (at
   most 4,096) keeping the innermost 32. Only links are followed at this
   point.
2. For each kept frame, `co_filename` is measured through `str.__len__`
   before it is read. Above 512 characters it becomes `<filename too long>`
   and is not copied, scanned or formatted.
3. Otherwise the complete filename is validated as one unit: printable, no
   double quote, no control character or ambiguous whitespace, and unchanged
   by the full text scrubber. If any of that fails it becomes
   `<unsafe filename>`. No part of a rejected filename is kept, and a filename
   is never shortened.
4. `co_name` must match an identifier grammar (`<module>`, `<lambda>`
   included) or becomes `<unknown>`; the line number must be an exact
   non-negative `int` or becomes `?`.
5. The frame line `File "…", line N, in name` is built, and emitted only if
   the text scrubber leaves the whole line unchanged; otherwise a fixed line
   replaces it. Source lines are never read or shown (no `linecache` access).
6. The exception itself is `TypeName: message`, the message scrubbed as one
   unit before any cut, as before.

The result is a **list of units** (one per frame, one per description), not a
string. Both sanitising passes scrub each unit on its own like any list of
strings; because each unit was built as a fixed point of the scrubber, both
passes return it unchanged. Units are never read joined together, so no
credential context can be lost or created across a line boundary. After the
final pass, `join_unit_lists` joins the list with newlines so that JSON and
console output keep the standard layout.

**How signed capability fields are protected.** By the name of the field that
carries them, never by the look of the value. `_CAPABILITY_KEY` is part of
both key classifiers: `download_url`, `upload_url`, `presigned_url`,
`signed_url`, `recording_url`, `media_url`, `playback_url`, `sas_url`,
`result_ref`, storage/object/blob/file/attachment URL fields, and their
kebab-case and camelCase spellings (`downloadUrl`, `RecordingUrl`,
`MediaUrl0`). The whole value is replaced, whether it is a string, a list or
a mapping, in structured data, in JSON embedded in a string, and after
`key=` / `key:` in text. Query parameters with which a provider signs a URL
(`X-Amz-*`, `X-Goog-*`, `X-Oss-*`, `sig`) are masked by name wherever a URL
appears. Ordinary reference fields (`url`, `target_url`, `base_url`,
`logo_url`, `redirect_uri`) are unaffected.

**What happens when a work limit is exhausted.** Every limit costs fidelity,
never confidentiality: what was not examined is not emitted. Fields beyond
the admission limits are never visited and one `[TRUNCATED]` entry stands for
them. A value reached after the event budget is spent is `[TRUNCATED]`. Text
too long to scan in full is `[TRUNCATED_SENSITIVE_VALUE]` if its examined part
shows any sign of a credential. A traceback that exceeds its line or length
limit drops whole exceptions from the old end of the chain and begins with
`[TRUNCATED]`; a frame line that cannot be validated within the scan budget is
replaced by the fixed line. A rendered line above 131,072 characters is
replaced by a fixed `log_record_oversized` record.

**Why rendering and fallback paths cannot emit unsanitised input.**

- Two stages follow the final sanitising pass. `join_unit_lists` reads only
  that pass's output and adds newlines between strings the pass has already
  cleared for emission as they are: it can show nothing that the same strings
  in a list would not, and a list a caller supplies under `exception` or
  `stack` is treated the same way (each item scrubbed, then joined). The
  renderer receives exact built-in types only and has a `default=` that
  returns a fixed word, so it never calls `repr()`.
- If any processor raises, `_FailClosedChain` replaces the event with a fixed
  record carrying the exception's class name and validated identifiers.
- If formatting raises, or the format string is unbounded, or the line is
  oversized, `FailClosedStreamHandler.format` returns a fixed JSON line built
  from fixed text and validated identifiers.
- If writing fails, `handleError` writes one fixed diagnostic to stderr. The
  record's message, arguments, traceback and unvalidated name are used by none
  of these paths.

**What is not claimed.** A secret in ordinary free text under an innocent
field name cannot be inferred from its content, and neither can a bare
capability URL in a message with no field name and no signing parameter. The
protection for those is structural: log such values under their field name
(where they are masked) or not at all, and never log the bodies of the
endpoints that return them (§6).

#### Results (pass 5)

Reviewer reproductions, before and after, same script against both sources:

| Reproduction | Pass-4 source | Pass-5 source |
|---|---|---|
| `sanitize_event({"detail": type(render_exception(e))("password=" + secret)})` | secret emitted | `{"detail": "password=[REDACTED]"}` |
| `render_exception` of an exception raised from code whose filename is `postgresql://h/db?password=[REDACTED]\n` + secret | secret emitted | frame shown as `File "<unsafe filename>", line 1, in <module>` |
| `sanitize_event({field: capability})` for `download_url`, `upload_url`, `presigned_url`, `signed_url`, `recording_url`, `media_url` | capability emitted (6 of 6) | `[REDACTED]` (6 of 6) |
| 52 events through the configured pipeline (JSON and console renderers; structlog and standard-library loggers; forged text, three hostile filenames, four capability fields) | stdout: secret × 14, capability × 32; stderr: 0 | stdout: 0 and 0; stderr: 0 and 0 |

Work, measured with the same script:

| Stage | Pass-4 source | Pass-5 source |
|---|---|---|
| 100,000 context fields | 100,000 variables visited, 200,000 values fetched, 100,001 fields in the event | 200 visited, 199 fetched, 201 fields (one is the marker) |
| Record with 100,000 extra attributes | 7,692,170 bytes peak; attributes traversed | 2,980 bytes peak (3,419 with no extras); no traversal |
| Traceback with a 1,000,000-character filename | 2,020,591 bytes peak | 5,131 bytes peak, the same as for an ordinary filename |

#### Changes to earlier behaviour (pass 5)

- D0-SR-13 is superseded: no value is exempt from the second pass.
- Tracebacks show no source lines, and `stack_info` produces a stack built the
  same way (structlog's `StackInfoRenderer`, which formats raw frames, is no
  longer in the chain).
- `render_exception` returns a plain string. Logged again as a field it is
  one multi-line string and, if anything in it is masked, is masked whole by
  the ambiguity rule; the pipeline itself uses `traceback_lines`.
- One pass-4 test asserted the trusted type and was rewritten to assert its
  absence (`test_no_string_type_is_trusted_by_the_sanitiser`); none was removed.

### 2d. Pass 6 — the order of the pipeline (D0-P0-02, D0-P0-03, D0-P1-10, D0-P1-11, D0-M-05)

Review 6 reproduced five defects (F1–F5) while every existing gate passed.
All five were reproduced against the pass-5 source before anything was
changed. The pass-5 sources were kept byte-for-byte
(`logging.py` SHA-256 `99a92fa0…6b721`, `redaction.py` `587fc32c…62`) so that
each regression test could be run against them afterwards.

Four of the five had one cause: **security processing in the wrong order.**
Pass 5 sanitised values and then did more work on them: it joined
sanitised traceback units into one string (F1), copied processor metadata
past the sanitiser by key name (F2), and admitted the event name and request
ID through the same budget as arbitrary payload, after it (F4). No credential
pattern was added for any of them. The pipeline was reordered instead:

> No caller-controlled value reaches an output handler without passing
> through the sanitiser *after its final transformation*.

#### The pipeline after pass 6

| Step | What happens | Where |
|---|---|---|
| 1. Operational metadata | Level, logger, service, environment and timestamp are established by the pipeline from its own sources (the method name, the logger object or the genuine record, the configuration, the clock). The request ID is taken from the server's `RequestContext`, then from a structlog context binding, then (outside any request) from a call field, and is validated by grammar. None of it is read from payload fields, and none of it counts against any budget | `_EventPipeline._establish_identity`, `_process` |
| 2. Bounded admission | At most 200 call, bound and context fields. `event`, `exc_info`, `stack_info`, operational and reserved names take none of the places | `BoundedBoundLogger`, `merge_bounded_contextvars` |
| 3. Reserved names | A caller's `_record` / `_from_structlog` (call, bound or context) is removed, and a fixed `[RESERVED]` field says so. The formatter's genuine `_record` is believed only by the pipeline instance installed as the formatter's pre-chain (`foreign=True`), where the formatter has just created the event | `_EventPipeline.__call__`, `_process` |
| 4. Normalisation | `exc_info` and `stack_info` become one complete traceback / stack text, constructed from validated frame metadata | `traceback_text`, `stack_text` |
| 5. Assembly | Caller fragments under `exception`/`stack` (string, list, tuple, nested lists) are joined into the text they will be laid out as; non-text fragments become `[UNSUPPORTED]`. Bounded: 200 values, depth 8, 16,385 characters copied | `redaction._assembled_text` |
| 6. Sanitising | `sanitize_event` on the complete values. The event name, traceback and stack are sanitised first (`leading`), so payload can neither displace them nor exhaust the budget before them | `redaction.sanitize_event` |
| 7. Log record | The sanitised event is what every handler on the logger receives | `wrap_for_formatter` |
| 8. Final sanitising | Steps 3, 5 and 6 again on the whole event; no key is passed through. *(Pass 7, §2e: preceded, for every record, by step 1 again from the log record, the configuration and the request context; `_discard_processor_metadata` and the `foreign=True` pre-chain instance no longer exist)* | `_EventPipeline(final=True)`, `redact_sensitive_fields` |
| 9. Rendering | JSON or console layout; no value is joined or changed; the 131,072-character line bound still applies | renderer, `FailClosedStreamHandler` |

The only stage after the final sanitiser is the renderer
(`test_no_stage_follows_the_final_sanitiser_except_the_renderer`).

#### Root cause and correction per finding

**F1 — D0-P0-02, post-sanitizer join.** Pass 5 treated a list under
`exception` or `stack` as a list of independent strings, scrubbed each, and
joined them with newlines afterwards. Each fragment was harmless alone; joined,
`Cookie: session=[REDACTED]` + newline + ` secret` is a folded header whose
continuation is the credential. The join was a transformation after the
security boundary that was not provably safe.
*Correction:* the join moved before the sanitiser. Every caller-provided value
under those names is untrusted and is assembled into the complete text, which
is then sanitised as one string, so the existing cross-line rules (folded
headers, multi-line URIs, the ambiguity rule) see the whole credential.
Internally generated tracebacks are not a trusted list either: they are now
built as one text, and that text is checked against the sanitiser *whole*
(each frame line also as it stands with a line after it, so that a function
named `bearer` cannot become a credential prefix of the next line). A message
that does not survive the whole-text check is withheld in steps
(`TypeName: [REDACTED]`), keeping frames, types and chain links. No trusted
string type was introduced; nothing distinguishes the pipeline's own text
from a caller's except where it was built.

**F2 — D0-P0-03, reserved metadata.** `redact_sensitive_fields` copied
`event_dict["_record"]` and `["_from_structlog"]` past the sanitiser because
structlog's formatter needs them, but it decided *by key name*, and a caller
can use any key name. The project's formatter overwrote the key before
rendering, so only an additional handler showed the leak.
*Correction:* a field name confers nothing. Callers' reserved keys are
removed at entry and noted with fixed text. Genuine formatter metadata is
identified by *where* the pipeline instance runs, never by event content, and
is consumed (logger name of a foreign record) before any caller field could
be merged. Operational metadata likewise no longer comes from event fields, so
structlog's `add_logger_name` (which read `_record.name`) is gone from the
chain. Pass 5 also let a call field override `service` and `environment`
(`setdefault`) — found while fixing F2, recorded as D0-SR-21.

**F3 — D0-P1-10, signed URL bundles.** Signing parameters were classified one
at a time and only those named like a signature were masked.
*Correction:* the parameters of a URL are read as a set. One signature or
signing-key parameter (`Signature`, `sig`, `Key-Pair-Id`, `X-Amz-*`,
`X-Goog-*`, `X-Oss-*`, `AWSAccessKeyId`, `GoogleAccessId`, `OSSAccessKeyId`,
`security-token`, `q-signature`, …; case-insensitive, percent-decoded, any
position) makes the whole URL — scheme, host, path and every parameter — the
capability, replaced by `[REDACTED]`. The same applies to a signed reference
written without a scheme (`GET /media/x.wav?Expires=…&Signature=… HTTP/1.1`).
A URL without such a parameter, even with `expires`, `policy` or `sv`, is an
ordinary URL and is logged as it is.

**F4 — D0-P1-11, admission boundary.** The event name and request ID were
ordinary entries of the event dict. structlog puts `event` after the keyword
arguments and the context merge appended `request_id` last, so both competed
with payload for the 200 places and were the first dropped (199 fields: no
request ID; 200: no event).
*Correction:* operational metadata is a protected schema outside the payload
budget (step 1); the event name, traceback and stack are sanitised first
(step 6). The request ID is looked up directly in structlog's registry, so it
is found among any number of context variables. Precedence prevents a caller
from renaming an authoritative ID: request context > context binding > call
field (`test_a_request_id_cannot_be_renamed_by_a_field`).

**F5 — D0-M-05, pre-admission allocation.** Size checks ran after
conversion: `str.__str__` copied a `str` subclass whole, and
`Context.create_decimal` read the whole coefficient, before either was found
too large.
*Correction:* every check reads size through a constant-time slot first —
`str.__len__` then a bounded `str.__getitem__` slice; `Decimal.__sizeof__`
(the digits of a Decimal are counted in its own size, so a 40-digit value is
≤ 104 bytes and a 10-million-digit one 4.2 MB) against a fixed 256-byte
limit; `int.bit_length` before `int.__int__` (D0-SR-22). No overridden method
of a subclass is called (the tests use subclasses whose every conversion
method raises).

#### Results (pass 6)

Reviewer reproductions, same script (`structlog` and standard-library loggers,
direct, bound and context-variable fields) against both sources:

| Reproduction | Pass-5 source | Pass-6 source |
|---|---|---|
| F1: 4 folded forms × `exception`/`stack` × direct/bound/context × JSON/console | stdout sentinel × **48**, stderr × 0 | stdout **0**, stderr **0** |
| F2: `_record`/`_from_structlog` × direct/bound/context × JSON/console, independent `StreamHandler(sys.stderr)` attached | stdout × 0, stderr sentinel × **12** | stdout **0**, stderr **0** |
| F3: CloudFront URL from the review | `…?Expires=4102444800&Signature=[REDACTED]&Key-Pair-Id=QUERY_SCOPE_SENTINEL` | `[REDACTED]` |
| F3: Azure SAS URL | `…?sv=…&se=…&sr=b&sp=QUERY_SCOPE_SENTINEL&sig=[REDACTED]` | `[REDACTED]` |
| F4: 198 / 199 / 200 / 201 / 1,000 fields + bound `request_id` | event ✓✓✗✗✗, request ID ✓✗✗✗✗ | event ✓✓✓✓✓, request ID ✓✓✓✓✓ |
| F5: 10,000,000-character exact `str` (logging-owned peak) | 19,429 B | 19,901 B |
| F5: same length, `str` subclass | **10,018,160 B** | 19,901 B |
| F5: 10,000,000-digit `Decimal` | **4,215,050 B** | 9,419 B |
| F5: `Decimal("12.50")` (control) | 5,989 B, `"12.50"` | 6,901 B, `"12.50"` |
| D0-SR-22: 80,000,000-bit `int` subclass (`sanitize`) | 10,676,037 B | 7,406 B |

The scalars were allocated before measurement began; the peaks are what
logging itself allocated (tracemalloc around the call). Every emitted line
stayed within the event budget.

`tests/unit/test_logging_closure.py` adds 123 tests, grouped by invariant (F1
33, F2 15, F3 23, F4 44, F5 8 including the limits regression), each requiring
zero sentinel occurrences on stdout and stderr separately. Against the pass-5
sources (the module was given the three new helper names as thin wrappers
over the old functions, so that behaviour, not an import, is measured),
**109–113 of 123 fail**; the 10–14 that pass are the controls (ordinary
tracebacks, ordinary URLs, ordinary Decimals, the 10-million-character exact
string and plain integer, which were already bounded) and the 198-field cases,
which the pass-5 source passes or fails depending on the iteration order of
the context (its merge counted variables that had already been unbound).
On the pass-6 source all 123 pass in normal, reverse and seeded random order.

F4 through the real middleware: `create_app` with a probe route logging
`request_id="forged-by-the-handler"` plus 198/199/200/201/1,000 fields, request
sent with `X-Request-ID: forged-by-the-client`; in both renderers the log line
carries the event name and exactly the server-generated `X-Request-ID` of the
response, and neither forged value appears.

F3 coverage: CloudFront canned and custom policy, Azure SAS, AWS SigV4 and
SigV2, Google V4 and V2, Alibaba OSS V1 and V4, Tencent COS; each as issued,
with mixed-case keys, percent-encoded keys, reversed order, extra innocent
parameters and in a fragment; through structured fields, nested fields,
messages, bound fields, standard-library arguments and exception text (logged
with `exception()` in both logging systems), in both renderers. Controls:
eight ordinary URLs, including `expires`/`policy`/`sv`/`se`/`sp` without any
signature, are emitted unchanged.

#### Mutation probes (pass 6)

Each probe was applied to a scratch copy of `voice_agent/` and `tests/`; the
repository files were never modified (SHA-256 of `logging.py`, `redaction.py`,
`test_logging_closure.py` and `test_logging_trust.py` compared before and
after: unchanged). An unmutated baseline copy passes. `test_logging_trust.py::
test_a_million_character_filename_is_never_formatted` is deselected in the
copies only: it bounds a traceback length that includes the checkout path,
which is longer in the scratch directory; it passes in the repository.

| # | Defect re-introduced | Result |
|---|---|---|
| F1a | caller lists sanitised item by item and joined after the final pass (the pass-5 design) | detected (31 failures) |
| F1b | traceback text not checked as a complete text | detected (3) |
| F1c | frame line checked alone, not as it stands among other lines | detected (1) |
| F2a | caller's reserved names neither removed nor excluded from the fields | detected (10) |
| F2b | final pass passes processor metadata through (pass-5 behaviour) | detected (2) |
| F2c | logger name read from the event's `_record` | detected (3) |
| F3a | whole-URL rule removed (parameter-by-parameter masking only) | detected (22) |
| F3b | signing parameter keys not percent-decoded | detected (1) |
| F3c | pass-5 signing-parameter list | detected (13) |
| F3d | scheme-less signed reference not recognised | detected (1) |
| F4a | event name competes with payload (no leading fields) | detected (27) |
| F4b | context request ID renamed by a call field | detected (1) |
| F4c | server request context ignored | detected (1) |
| F4d | bound-logger admission counts `event`/`exc_info` as payload | detected (2) |
| F4e | operational metadata taken from call fields (pass-5 `setdefault`) | detected (30) |
| F5a | `str` subclass copied whole before it is measured | detected (1) |
| F5b | Decimal size preflight removed | detected (1) |
| F5c | `int` subclass converted before its bit length is read | detected (1) |

18 of 18 detected. On the first run three probes were not detected, and
each was examined rather than discarded: F2a and F4e had mutated only one of
two independent layers (removal at entry *and* exclusion from the payload
fields), so the probes were made to remove both; F3b was caught by the
decoded-view layer, which masks the whole string, so a test was added that
pins the URL rule's own output (the text around a signed URL is kept), after
which it is detected.

#### Changes to earlier behaviour (pass 6)

- `exception` and `stack` are always one string, never a list, at every stage,
  including in the record that other handlers see (supersedes the pass-5 note
  in §6).
- A traceback message in which anything is masked is shown as
  `TypeName: [REDACTED]` if, read together with the following lines, it would
  otherwise change under the sanitiser; frames and types remain.
- A signed URL is `[REDACTED]` in full; pass 5 kept its host, path and
  non-signature parameters.
- A field named `_record` or `_from_structlog` is removed and the line carries
  `"[RESERVED]": "reserved field names removed"`. Fields named `level`,
  `logger`, `service`, `environment` or `timestamp` are not emitted from the
  call; the pipeline's values are.
- A `request_id` field of a call is used only outside a request and when no
  `request_id` is bound to the context.
- The event name, traceback and stack no longer count against the 200-field
  limit; an event may therefore carry 200 payload fields plus those.
- Three existing tests asserted pass-5 behaviour that review 6 showed to be
  defective and were updated, none removed:
  `test_logging_trust.py::test_the_second_pass_scrubs_what_the_first_pass_returned_and_what_was_added`
  (expected a list under `exception`: now the assembled string),
  `::test_provider_signing_parameters_are_masked_by_name` (renamed
  `test_a_url_with_provider_signing_parameters_is_masked_whole`; required
  `&se=2026&part=1` to survive beside a masked `sig`),
  `::test_context_fields_beyond_the_limit_are_never_visited` (counts: the event
  name no longer takes a place; one value is fetched to learn that a field is
  really left out, since unbound variables are skipped).

#### Limitations stated honestly (pass 6)

- **Standard-library records and other handlers.** An event made through
  structlog reaches every handler already sanitised. A record made by a
  standard-library logger (`logging.getLogger(...).warning(...)`) reaches the
  other handlers of that logger as its caller made it: the logging module
  hands the same record to each handler, and only this module's handler
  sanitises it. Handlers must therefore be installed only through
  `configure_logging`, which replaces the root handlers; an additional handler
  must use `FailClosedStreamHandler` with the installed formatter. This is not
  new in pass 6; it is stated here because F2 concerns other handlers.
- **Decomposed signed-URL parameters.** A signed URL logged as separate
  structured fields (`{"Expires": …, "Signature": …, "Key-Pair-Id": …}`) has
  no URL to recognise: `Signature` and `Key-Pair-Id` are masked by key name,
  `Expires`, `sv`, `se` and similar are not. Log the resource ID instead.
- **Unknown signing schemes.** A signed URL is recognised by the parameter
  names of the providers listed above. A provider that signs with a parameter
  of another name is not recognised from the URL alone (the field-name rule
  for `download_url` etc. still applies).
- **Over-masking.** After a signed URL's credential parameter, the rest of the
  text up to the next `&` is masked as before, so a message continuing after
  a signed URL without `&` may lose its tail.

**Verification after pass 6.** 9,082 tests (9,008 unit, 74 integration and
smoke against disposable PostgreSQL 18 and Redis) pass in normal, reverse and
seeded random order (`random:20261008`); `uv sync --locked`,
`ruff format --check`, `ruff check`, `mypy` (75 source files) and
`scripts/verify.py` (all seven gates, including the migration graph: 112
revisions, 112 SQL migrations, root `001_5B`, sole head `112_5H5`, linear;
repository guards: frozen documents unchanged) pass. Docker/Compose and GitHub
Actions remain unexecuted (§5).

### 2e. Pass 7 — the origin of a record (D0-P1-12)

Review 7 reproduced one defect while every existing gate passed. It was
reproduced against the pass-6 source before anything was changed; that source
was kept byte-for-byte (`logging.py` SHA-256 `79df1c96…d8e5a6`) so that the
regression tests could be run against it afterwards.

**Root cause: a decision of trust taken from what a record says about
itself.** `_with_sanitized_arguments` computed
`is_structlog_record = hasattr(record, "_logger") and hasattr(record, "_name")`.
Both attributes are ordinary `extra=` keys. Three consequences followed from
that one line, in this order:

1. the handler passed the record on without sanitising its message, as "an
   event the processor chain has already sanitised";
2. structlog's `ProcessorFormatter`, which uses the same two attributes, read
   the message as an event dict and skipped `foreign_pre_chain`, the only
   place where a standard-library record received its operational metadata;
3. the final pass (`redact_sensitive_fields`) validated the *grammar* of
   whatever stood under `timestamp`, `level`, `logger`, `service`,
   `environment` and `request_id` and emitted it. It had been written on the
   assumption that an earlier stage had established those values; for this
   record no stage had.

The payload was still sanitised (the final pass sanitises every field), so no
secret was disclosed. What was lost was the integrity of the line: the request
ID, service, environment, level and time were the caller's.

**Correction.** Two changes, either of which closes the reproduction; they
are independent on purpose.

- *Authoritative metadata for every record, in the final pass.* The pipeline
  instance installed as the first of the formatter's processors
  (`_EventPipeline(final=True)`) takes `_record` and `_from_structlog` out of
  the event (the formatter has just written both, over anything a caller put
  there) and establishes: `level` and `logger` from the record's `levelname`
  and `name`, `timestamp` from the record's `created`, `service` and
  `environment` from the configuration, and `request_id` from the server's
  `RequestContext`. Each is validated by grammar. What the event holds under
  those names is left behind. Outside a request, a request ID that came
  through the structlog stage or the context merge is kept, as in pass 6
  (D0-P1-11). There is no `foreign_pre_chain` any more: a standard-library
  record goes through the whole path (bounded context merge, reserved names,
  constructed traceback and stack, sanitising) in the same instance.
  `redact_sensitive_fields` still follows it and is still the only stage
  before the renderer.
- *Origin by identity, not by attribute.* `_logger` and `_name` are no longer
  among the attributes copied from a record (`_RECORD_ATTRIBUTES`), so nothing
  a caller attaches reaches structlog's formatter. The structlog stage keeps
  the event it has just produced in a thread-local (`_PIPELINE_STATE`); the
  handler reads a record's message as an event only if it *is* that object,
  and then sets the two attributes itself, to fixed values, on its own
  bounded copy. A logging call is synchronous from the pipeline to the
  handlers, so a genuine record always carries that object; a mapping passed
  to a standard-library logger never does, however it is marked, and is a
  message like any other (sanitised structurally, then laid out as one JSON
  text under `event`).

No trusted string, type or marker was introduced. The identity check decides
only the *shape* of the event (fields, or one message text); it grants no
metadata and exempts nothing from sanitising. Code inside the process that
obtains the pipeline's own event object and logs it again (a handler or
filter can) is read as an event, and its line still carries the level and
logger of the call that logged it, the configured service and environment and
the server's request ID
(`test_even_the_event_of_the_pipeline_itself_gains_no_metadata_by_being_logged_again`).

Differences a reader of the logs can see: none for ordinary records. The
`timestamp` of a line is now the creation time of its log record rather than
the time the structlog stage ran (microseconds apart). Preserved from pass 6:
reserved-name removal and the `[RESERVED]` marker, assembly before sanitising
(F1), the sanitised event for independent handlers (F2), signed-URL masking
(F3), the protected event name and request ID (F4), bounded preparation (F5).

#### Results (pass 7)

The reviewer's reproduction (`logger.info({...}, extra={"_logger": logger,
"_name": "info"})` on logger `real.source`, `RequestContext(request_id=
"actual-server-request")` bound, a `password` added), against both sources:

| Output | Pass-6 source | Pass-7 source |
|---|---|---|
| `request_id` (request context bound) | `forged-client-request` | `actual-server-request` |
| `request_id` (no request context) | `forged-client-request` | absent |
| `service` / `environment` | `fake-service` / `production` | configured values |
| `level` | `critical` | `info` (the call was `logger.info`) |
| `timestamp` | `2026-01-01T00:00:00Z` | creation time of the record |
| `logger` | absent | `real.source` |
| forged mapping | fields of the line | the message text under `event` |
| `password` | `[REDACTED]` | `[REDACTED]` |

Identical in JSON and console mode. Of the 93 tests in
`tests/unit/test_logging_provenance.py`, 61 fail against the pass-6 source and
all pass against the pass-7 source. They cover: the literal reproduction; nine
standard-library forms (marked mapping, marked mapping with a foreign
`_logger`, with forged `_record`/`_from_structlog`, unmarked mapping, forged
`extra` fields, marked text with and without arguments, keyed arguments, a
hand-built record) × with and without a request context × JSON/console;
structlog call, bound and context fields; the level of every logging method;
a filtered level; a copy of a genuine pipeline event; the genuine event object
logged again; an event of another thread; unchanged structlog and
standard-library logging including exceptions and mapping messages; processor,
sanitiser, formatter and writer failures; unbounded format strings and
oversized messages on marked records (allocation bounded); a second
`FailClosedStreamHandler` on the root and on a named logger; and an
independent plain handler.

**Mutation probes (pass 7).** Eight probes, each re-introducing one defect
into `logging.py`, all detected by `tests/unit/test_logging_provenance.py`,
file restored byte-identically (SHA-256 checked): origin inferred from record
attributes again · marking attributes copied from the record · final pass not
establishing record metadata for a pipeline event · final pass not
establishing the request ID · event metadata outranking the established
metadata · pipeline state shared between threads · service and environment of
the final pass not taken from the configuration · timestamp of the final pass
not taken from the record.

**Residual limitations (pass 7).**

- The supported handler configuration is unchanged from pass 6: an additional
  handler must be a `FailClosedStreamHandler` with the formatter installed by
  `configure_logging`. The formatter on a plain `logging.StreamHandler` is not
  supported: the bounded copy, where the marking attributes are dropped, is
  made by the handler.
- A handler that formats records in another thread than the logging call
  (`QueueHandler`/`QueueListener`) is outside the supported configuration: a
  structlog event would be laid out there as one message text (sanitised,
  with authoritative level, logger, service, environment and time), and the
  request context of the call is not visible in that thread.
- Outside an HTTP request a structlog caller can still name a `request_id`
  (pass 6, D0-P1-11: "then, outside any request, from a call field"). A
  standard-library record cannot.

**Verification after pass 7.** 9,175 tests (9,101 unit, 74 integration
and smoke against disposable PostgreSQL 18 and Redis) pass in normal, reverse
and seeded random order (`random:20261009`); the 9,082 tests of pass 6 are
unchanged and pass. `uv sync --locked`, `ruff format --check`, `ruff check`,
`mypy` (76 source files) and `scripts/verify.py` (all seven gates, including
the migration graph: 112 revisions, 112 SQL migrations, root `001_5B`, sole
head `112_5H5`, linear; repository guards: frozen documents unchanged) pass.
Docker/Compose and GitHub Actions remain unexecuted (§5).

## 3. Found during remediation self-review

| ID | Severity | Finding | Remediation | Status |
|---|---|---|---|---|
| D0-SR-01 | Minor | `REDIS__URL` query parameters become redis-py client arguments, so `?ssl_cert_reqs=none` could disable certificate verification on a `rediss://` URL | Query parameters and fragments refused; tuning stays in typed `REDIS__*` settings (`tests/unit/test_config.py`) | RESOLVED |
| D0-SR-02 | Minor | `application_stopped` was logged identically whether or not every resource had been released | The line now carries `infrastructure_state` | RESOLVED |

Pass 3 self-review (all part of D0-P0-01; found by attacking the rewritten
sanitiser with a seeded generator, `tests/unit/test_redaction_fuzz.py`, and
fixed before completion). Each leaked a generated sentinel at the time:

| ID | Finding | Remediation |
|---|---|---|
| D0-SR-03 | The decoded-view check compared counts of `[REDACTED]` in the output, so a percent-encoded `password=[REDACTED]<secret>` was judged to reveal nothing — the mask-prefix defect in a second place | Views are compared piece by piece with the original (§2a); no count of markers is used anywhere |
| D0-SR-04 | Text that is the `repr`/JSON encoding of other text writes whitespace as `\n`, `\t`, `\xa0`; the scanner did not treat it as whitespace around a separator, and masked the escape instead of the value | Escaped whitespace separates key, separator and value like whitespace and is masked together with the value |
| D0-SR-05 | A key escaped twice (`\\u0064`) is only readable after a second decoding round, and a later round garbles it again | Backslash escapes are decoded left to right, one level per round, and every intermediate form is examined |
| D0-SR-06 | An early rule that delimited a value wrongly replaced the characters a decoded view needed, so the view of the *result* showed nothing | Views are taken from the original text (§2a) |
| D0-SR-07 | A span that ran past its value could end just after the key of the next pair, leaving that pair's value unmarked | A span containing a sensitive key whose own value reaches beyond it masks the remainder of the string |
| D0-SR-08 | A quote behind several backslashes closes or does not close a value depending on an escaping depth the sanitiser cannot know | Such a value counts as undelimited and is masked to the end of its line or string; in unquoted values a backslash run of any length escapes what follows |
| D0-SR-09 | Encodings layered so that a character reference is incomplete until another decoding has run (`&quot%3B`) were decoded in the wrong order | Only complete character references are decoded; the rest wait for a later round |
| D0-SR-10 | Further credential syntaxes: `KEY 'value'` (SQL `PASSWORD '…'`), `--key value`, `'key', 'value'` tuples and byte-string header lists, `key => value`, `key := value`, `<key>value</key>`, `user[key]=`, `user:password@tcp(host)/db` without a scheme, URL fragment parameters, a password containing a space, full-width and zero-width forms of a key | Recognised by the pair scanner, the URL layer and the decoded views |
| D0-SR-11 | A quoted value followed directly by more text (`'[REDACTED]'<secret>`) was masked only up to the closing quote | The value continues to its delimiter |
| D0-SR-12 | `bearer`/`token` values were recognised after at most eight spaces or tabs | Any whitespace |

One generated form was deliberately not treated as a leak in pass 3: in
`password=[REDACTED]<TAB>word` (unquoted) the value ends at the whitespace by
the libpq grammar, exactly as in `password=abc<TAB>word`, and `word` is not
part of it. Quoted (`'[REDACTED]<TAB>secret'`), JSON, query-encoded and header
forms of the same value are masked in full. *Superseded by pass 4:* that
reading holds for libpq keyword/value strings but not for a PostgreSQL URI,
where the tab is part of the password (review 4). The sanitiser no longer
chooses between the two: a string that carries a credential and a tab is
masked whole (§2b).

Pass 4 self-review (found while rebuilding the boundary and attacking it; each
is covered by `tests/unit/test_logging_boundary.py` and fixed):

| ID | Finding | Remediation |
|---|---|---|
| D0-SR-13 (superseded by pass 5, §2c: the private type was itself a bypass) | The event is sanitised twice (in the shared chain and again before rendering). The second pass re-read an assembled traceback as one unknown multi-line string, which the new ambiguity rule would mask whole, and re-applied the item limits to the first pass's own markers (`1800 more entries` became `1 more entries`) | Text produced by the sanitiser carries a private type and is charged, not re-read; a marker of an earlier pass is kept as the entry beyond the limit |
| D0-SR-14 | The validation-error summary built its text with `str()` of `loc` parts and by formatting `msg` and `type`, so a subclass or arbitrary object there converted itself | Only exact strings and small exact integers are used; each part is scrubbed as a unit and anything else is `[UNSUPPORTED]` |
| D0-SR-15 | `urllib` deletes tabs and newlines before parsing, so `pass<TAB>word=` is a `password` parameter and `scheme:/<TAB>/` a scheme separator | The ambiguity rule also reads the text with those characters removed |
| D0-SR-16 | A standard-library record whose message is a `str` subclass was passed on unchanged, and `LogRecord.getMessage()` calls `str()` on it | The message is reduced to an exact `str` through the base type before anything else |
| D0-SR-17 | `datetime.isoformat()` and `time.isoformat()` call `utcoffset()` of a user-defined `tzinfo` | Only `None`, `datetime.timezone` and `zoneinfo.ZoneInfo` are rendered |
| D0-SR-18 | An object can report itself as `str` through a `__class__` property; `isinstance()` believed it and the value (or the whole event) was then lost to an internal error | The real type is used throughout the sanitiser |
| D0-SR-19 | Exception links and tracebacks were read through attributes a subclass may override, and a deep recursion produced a traceback of unbounded length | Read through `BaseException`'s own descriptors; 32 innermost frames per exception and 32,768 characters in all |
| D0-SR-20 | SQLAlchemy reads `scheme://user:1234/ x@host` as a password `1234/ x` (the part after the colon looks like a port, and the `@` lies beyond a `/` and a space) | With a `:` before the first `/`, the userinfo is masked up to the next `@` wherever it is |

Pass 6 self-review (found while reordering the pipeline; each is covered by
`tests/unit/test_logging_closure.py` and fixed):

| ID | Finding | Remediation |
|---|---|---|
| D0-SR-21 | A call field named `service` or `environment` replaced the configured value (`add_service_identity` used `setdefault`), and a context-bound `_record` made the logger name `untrusted_logger` (structlog's `add_logger_name` read `_record.name`) | Operational metadata is established by the pipeline and never read from event fields (§2d step 1) |
| D0-SR-22 | `int.__int__` of an `int` subclass copies the number before its bit length was checked: 10.7 MB for an 80-million-bit value | `int.bit_length` first, conversion only within 128 bits |
| D0-SR-23 | A constructed traceback could be changed by a second sanitising pass once its units were read together: a message ending in a masked URL parameter masks to the end of the text, and a frame named `bearer` followed by a newline reads as a credential prefix | The traceback is checked as one complete text; a frame line is checked as it stands with a line after it; failing messages are withheld in steps (§2d, F1) |
| D0-SR-24 | `merge_bounded_contextvars` stopped at the field limit on reaching a variable that had been unbound again (`Ellipsis`), so the outcome at 198–200 fields depended on the iteration order of the context | An unbound variable is skipped before the limit is applied |

## 4. Adversarial mutation probes

Each probe re-introduced one defect into the remediated source, ran the tests
expected to catch it, and required a failure. All were detected; every mutated
file was restored byte-identically afterwards.

Nested secret beyond depth · cyclic payload · formatter failure not contained ·
logging stack dumping the record to stderr · query password leak · exception
Authorization leak · validation input leak · unknown object rendered with
`repr` · cancellation abandoning the release (Redis close and DB dispose) ·
reference dropped before release completes · DB URL query redirecting the
database · driver identity not pinned · migration tool query redirect · libpq
service/hostaddr redirection · runtime/migration target mismatch · reached
server not verified · 405 mapped to `VALIDATION_ERROR` · 405 losing `Allow` ·
Redis PING `False` accepted · malformed RESP accepted · connection refusal
mapped to `INTERNAL_ERROR` · integrity error mapped to `DEPENDENCY_UNAVAILABLE`
· malformed CORS port accepted · infra-only diff skipped by CI · test
credential in `repr` · stale target passing the gate · gate accepting `app_api`
· gate ignoring the connected role · startup claiming migration-current ·
migration 113 accepted by the graph validator.

Second pass (22 probes, all detected, files restored byte-identically):
escape-aware quoted parsing removed · query keys not decoded (with and without
the decoded-view layer) · decoded views not scrubbed · original value returned
at max depth · `repr` fallback for unknown objects · original event logged when
the formatter fails · parsed JSON bypassing structural redaction · JSON layer
removed · standard-library arguments interpolated unsanitised · unreadable
container propagating its error · unterminated quote not masked · emit failure
dumping the record to stderr · CORS moved outside correlation · raw Starlette
preflight errors restored · request ID dropped from OPTIONS · failed preflight
mapped to another code · allow-origin emitted for a disallowed origin · CORS
policy headers dropped from a rejection · acquisition context ignored · SQLSTATE
55000 classified as an outage globally · rejected credentials classified as an
outage. The first-pass probes were re-run afterwards and are all still detected.

The first run of the "unknown object" probe was not detected: the test object's
`repr` happened to use a form the text scrubber masks. The test was
strengthened to carry the bare value, after which the probe is detected.

Two further defects were found by the second-pass regression suite itself and
fixed before completion: standard-library `logger.x("%s", obj)` calls let
`logging` call `str(obj)` before the pipeline ran (arguments are now sanitised
structurally first), and mapping keys were scrubbed with the JSON layer disabled
and truncated before scrubbing (keys are now scrubbed in full, then shortened).

Third pass (18 probes against the redaction and logging tests, all detected,
`redaction.py` and `logging.py` restored byte-identically — SHA-256 compared
before and after). The seven required by review 3:

1. prefix-based "already masked" check restored;
2. whitespace limited to eight characters again (before and after the separator);
3. URL userinfo matched by the earlier pattern that excludes the apostrophe;
4. nested JSON handling stopped at the previous level (3), the rest passed through;
5. global traversal (node) budget removed;
6. seen-reference handling reverted to ancestor-only cycle detection;
7. original content returned when the output budget expires.

Eleven more, one per new invariant: decoded views taken from the scrubbed text
instead of the original · a span swallowing the next key accepted · a quote
behind several backslashes taken at face value · escaped whitespace not treated
as whitespace · exhausted JSON parse allowance passing the remainder through ·
text that does not decode to a fixed point emitted · a string beyond the scan
budget returned unscrubbed · `int` subclasses returned as they are · a rendered
line above the absolute bound written · identity fields not sanitised first ·
sanitised JSON fragments re-read as free text.

Two of the eleven (the backslash-quote and escaped-whitespace rules) were not
detected on the first run: another layer caught the same inputs, so no test
depended on the rule itself. A test pinning each rule's own behaviour was added,
after which both are detected.

Fourth pass (22 probes against `tests/unit/`, all detected). Each probe was
applied to a temporary copy of the sources; the repository files were not
touched, and their SHA-256 digests were compared before and after. The ten
required by review 4 (eleven probes; number 10 was probed in two ways):

1. Unicode whitespace treated as a libpq delimiter again (`str.isspace()`);
2. a URI credential ending at whitespace again;
3. header continuation ignored (tab, CR and LF no longer ambiguous);
4. a long credential truncated before parsing (exception message cut first);
5. an unsafe logger-name prefix retained (cut and scrubbed instead of rejected);
6. `isinstance()` subclass conversion trusted (paths, dates, fixed renderers);
7. unbounded initial mapping copy in event preparation;
8. unbounded percent width (template check disabled);
9. fixed-size scalar accounting restored;
10. event-wide budget bypassed before rendering (surplus fields copied by the
    logger; standard-library arguments interpolated unsanitised).

Eleven more, one per further control: cut text reclassified from its prefix · the
emergency line using the raw logger name · a `str` subclass asked to convert
itself · an enum member asked for its `value` property · a subclass of the
sanitised-text type trusted · the event field limit removed · an oversized
integer rendered to be measured · a long Decimal rendered directly · the
joined-up reading removed from the ambiguity rule · whitespace ending the
search for URL userinfo · exception-summary parts converted with `str()`.

Probes 2 and 3 share a mutation of the ambiguity rule: with that rule intact,
a URI credential beside a tab is masked whole whatever the URL rule does, so a
mutation of the URL rule alone is detected only by the test of that rule's own
behaviour (a space or `#` in a sensitive parameter), not by the tab forms.

Fifth pass (11 probes, all detected by `tests/unit/test_logging_trust.py`,
files restored byte-identically): strings of a non-built-in type skipped by
the sanitiser again · filename scrubbed line by line instead of validated
whole · frame line not checked as a unit · filename length checked after the
filename is read · capability field names not classified (structured) ·
capability field names not classified (text) · structlog's unbounded context
merge restored · context value fetched before admission · record `__dict__`
copied · original record handed to structlog's formatter · traceback joined
into one string before the final pass.

Sixth pass (18 probes, all detected by `tests/unit/test_logging_closure.py`
and `tests/unit/test_logging_trust.py`; applied to scratch copies, repository
files unchanged by SHA-256): see §2d "Mutation probes (pass 6)".

Seventh pass (8 probes, all detected by
`tests/unit/test_logging_provenance.py`, file restored byte-identically): see
§2e "Mutation probes (pass 7)".

## 5. Environmental evidence gaps

| Gap | State |
|---|---|
| Docker / Compose runtime | **Not executed.** Docker is not installed in the remediation environment. The Dockerfile and Compose file were validated statically only. The new CI `container` job builds the image and exercises Compose health checks, the deployment gate and graceful shutdown; it has not run yet. |
| GitHub Actions execution | **Not executed.** No Actions-compatible runner was available. Both workflows parse as YAML and were checked statically (working directory, Python 3.12 via `.python-version`, `uv sync --locked`, PostgreSQL 18 + pgvector, `pg_stat_statements` preload supplied by the test harness, Redis ≥ 7.2-compatible commands only, `verify.py` exit code as the step result, path triggers including `infra/`). Runtime execution is pending. |

Local Redis used for integration tests was 8.x; the code uses only commands
available in the frozen 7.2 floor (`PING`, `INFO`, `CLIENT SETNAME`).

## 6. Behaviour notes for later phases

- **Phase-6 obligation, recorded here and not implemented in D0 (6A §22,
  signed/presigned media URL handling).** Any endpoint whose response body
  contains a signed or presigned URL (for example 6D §16.2
  `GET /recordings/{id}/download-url`, upload-URL and export-download
  endpoints) must have request/response body logging disabled: the logging
  and tracing pipeline for that endpoint class records method, path, status,
  latency and request ID only. Such a URL must never be put into a log field,
  a span attribute, a metric label, an audit `resource_snapshot` or an error
  payload. The field-name redaction added in pass 5 is a second line of
  defence for that rule, not a substitute for it: it cannot recognise a
  capability URL logged as bare text or under a field name it does not know.
  New response fields that carry a capability must use one of the classified
  names or extend `_CAPABILITY_KEY` deliberately.
- (Pass 5) The value of a field named like a media or storage URL
  (`download_url`, `upload_url`, `presigned_url`, `signed_url`,
  `recording_url`, `media_url`, `file_url`, `result_ref`, …) is logged as
  `[REDACTED]`. To correlate, log the resource ID instead.
- (Pass 5) A traceback shows `File "…", line N, in name` for each frame and
  no source lines. A frame whose filename is longer than 512 characters, is
  not printable, or would be changed by the scrubber appears as
  `<filename too long>` or `<unsafe filename>`.
- (Pass 5) Attributes passed to a standard-library logger with `extra=` are
  not emitted (they never were) and are no longer copied. Context-local
  fields beyond 200, or beyond the first 800 context variables, are dropped
  with a `[TRUNCATED]` marker.
- (Pass 5, superseded by pass 6) Between the two sanitising passes the
  `exception` and `stack` fields are lists of strings; a handler attached
  beside the project's own sees them in that form. *Pass 6:* they are one
  string at every stage.
- (Pass 6) A URL carrying a provider signature or signing-key parameter is
  logged as `[REDACTED]` in full, host and path included. To correlate, log
  the media resource ID.
- (Pass 6) Do not log under `_record`, `_from_structlog`, `level`, `logger`,
  `service`, `environment` or `timestamp`: the first two are removed (and the
  line says `[RESERVED]`), the others are always the pipeline's own values.
  `request_id` from a call is used only outside an HTTP request.
- (Pass 6) A list passed as `exception=` or `stack=` is logged as its lines
  joined with newlines and sanitised as one text; if anything in it is masked
  next to a newline, the whole field is `[REDACTED]`.
- (Pass 6) Only handlers installed by `configure_logging` (or a
  `FailClosedStreamHandler` with its formatter) may be attached: a
  standard-library record reaches any other handler unsanitised.
- (Pass 7) `extra={"_logger": …, "_name": …}` on a standard-library logger has
  no effect, and a mapping logged through a standard-library logger is always
  one message text under `event`; for fields, log through `get_logger`. The
  `level`, `logger`, `timestamp`, `service`, `environment` and in-request
  `request_id` of every line are set in the final pass from the log record,
  the configuration and the request context. Handlers must format in the
  thread of the logging call (no `QueueHandler`).
- A database refusing new connections (SQLSTATE 55000 while acquiring a
  connection) is `DEPENDENCY_UNAVAILABLE`; the same SQLSTATE from a statement
  is not. Rejected credentials are deliberately **not** an outage and surface
  as `INTERNAL_ERROR`; readiness still reports PostgreSQL as failed.
- A rejected CORS preflight is `VALIDATION_ERROR` / 400 with the stable catalog
  message; which of origin, method or headers failed is logged, not returned.
- Free-text log scrubbing masks to the end of the line after a sensitive
  `key:` and after `Authorization`/`Cookie`, and masks a whole token whose
  percent-decoded form hides a credential. Over-masking is intended.
- (Pass 4) A string that carries a credential and also contains a tab, a
  newline, another control character or non-ASCII whitespace is logged as
  `[REDACTED]` in full. To keep context readable, log the credential-free
  parts as separate fields rather than as one multi-line string.
- (Pass 4) A string over 16,384 characters with any sign of a credential in
  its examined part is logged as `[TRUNCATED_SENSITIVE_VALUE]`.
- (Pass 4) After a sensitive URL parameter everything up to the next `&`, or
  to the end of the string, is masked; a URL with `host:port` followed later in
  the same string by an `@` is masked up to that `@`.
- (Pass 4) Objects are not rendered by type name any more: an unsupported
  value is `[UNSUPPORTED]`. Subclasses of UUID, Decimal, date/time and path
  types are unsupported; log `str(value)` of a value you trust, or the exact
  type. Enum members are logged by their stored value.
- (Pass 4) A logger name must be a dotted Python identifier of at most 128
  characters, a service or environment name and a request ID must match
  `[A-Za-z0-9][A-Za-z0-9_.-]*`; anything else appears as `untrusted_logger`,
  `untrusted_service`, `untrusted_environment` or `untrusted_request_id`.
- (Pass 4) One event carries at most 200 fields; a standard-library format
  string with a width or precision above 256, a `*` width, more than 64
  directives or more than 16,384 characters is replaced by a fixed
  `log_record_unsafe_format` record.
- A string whose credential is only visible after decoding, or that does not
  decode to a fixed point in three rounds (for example text escaped four or
  more times outside valid JSON), is logged as `[REDACTED]` in full. A value
  that cannot be delimited (unterminated or ambiguous quote, a span reaching
  into the next pair) masks the rest of its line or string.
- A container logged twice in one event appears in full once and as
  `[REPEATED]` afterwards; log a copy if both occurrences must be readable.
- One event is limited to 200 fields, 2,048 values and 65,536 rendered characters;
  what exceeds that is `[TRUNCATED]`. Large payloads belong in a store, with a
  reference in the log.
- Text of the form `user:something@host` is masked up to the `@` even without
  a URL scheme.
- The log sanitiser masks any mapping key containing `token`; a later phase
  that logs token *counts* should use a key such as `prompt_units` or extend the
  rules deliberately.
- An `HTTPException` with a status that has no catalog entry is a programming
  error and is returned as `INTERNAL_ERROR`; new statuses require a catalog entry.
