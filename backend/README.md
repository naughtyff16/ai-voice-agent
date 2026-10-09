# Backend — development guide

The Python backend of the AI Voice Agent Platform: a FastAPI modular monolith
(Phase 2 §7.1). This guide covers running, testing and verifying it. The
architecture lives in [`docs/`](../docs) and is authoritative; this file does
not restate it.

## What exists today

Only the engineering foundation (development phase D0): configuration,
PostgreSQL and Redis lifecycle, health probes, structured logging, the error
envelope, request correlation, migration tooling and the test harness. No
product feature, API resource or event pipeline is implemented yet.

```text
backend/
  voice_agent/                 the single root package (see "Package root" below)
    apps/api/                  Core REST API deployable: factory, settings, health, middleware
    platform/config/           typed settings and loader                    (3A §9)
    platform/shared_kernel/    errors, request context                      (3A §6, §12)
    platform/infrastructure/   db/, cache/, observability/, runtime.py      (3A §6.3)
    platform/utils/            single-purpose helpers (UUIDv7)              (3A §6.4)
  scripts/                     db_migrate.py, check_repository.py, verify.py
  docs/                        D0 findings register and controlled reconciliations (not frozen)
  tests/                       unit/, integration/, smoke/, support/
```

**Package root.** 3A §3 names the shared package `platform/`, which collides
with Python's standard-library `platform` module. With the owner's approval
the 3A hierarchy is kept unchanged under one root package, so imports are
`voice_agent.platform...` and `voice_agent.apps...`.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| [uv](https://docs.astral.sh/uv/) | 0.12.x | Installs Python and every dependency from `uv.lock`. |
| Python | **3.12** (`.python-version`) | uv provisions it. 3.12 is the 3F §3.1 container base image, and every locked dependency supports it. |
| PostgreSQL | **18** with `pgvector` | Server binaries (`initdb`, `pg_ctl`) are needed by the tests. Set `PG_BIN_DIR` if they are not on `PATH`. `pg_stat_statements` must be in `shared_preload_libraries` on any long-lived server. |
| Redis | **7.2 or later** | `redis-server` on `PATH`, or `REDIS_SERVER_BIN`. |
| Docker (optional) | Compose v2 | Alternative way to run PostgreSQL and Redis locally. |

## Install

```bash
cd backend
uv sync --locked          # runtime + dev + migration tooling, exactly as locked
```

Runtime dependencies are in `[project.dependencies]`. `migrations` (Alembic,
psycopg) and `dev` (pytest, ruff, mypy, httpx) are separate dependency groups;
the container image installs neither (`uv sync --no-dev`).

## Configuration

Settings are typed and validated at startup; an invalid or missing value stops
the process with a message that never contains a secret. Nested values use the
`__` delimiter.

| Variable | Required | Meaning |
|---|---|---|
| `ENVIRONMENT` | yes | `local`, `test`, `staging` or `production`. Never defaulted. |
| `DATABASE__URL` | yes | `postgresql+asyncpg://app_api:<password>@host:port/db`. Superuser, `app_migration` and `app_platform_admin` are refused. Exactly one host; the only query parameter accepted is `ssl`. |
| `REDIS__URL` | yes | `redis://` or `rediss://` (TLS). |
| `SERVICE_NAME` | no | Log identity and PostgreSQL `application_name`. Default `voice-agent`. |
| `OBSERVABILITY__LOG_LEVEL` / `__LOG_FORMAT` | no | Default `INFO` / `json`. `console` is for local terminals. |
| `API__CORS_ALLOWED_ORIGINS` | no | JSON list of exact, lowercase `scheme://host[:port]` origins. Default: none. Wildcards, credentials, paths, malformed or default ports are rejected. |
| `API__DOCS_ENABLED` | no | Serves `/docs` and `/openapi.json`. Default `false`. |
| `DATABASE__POOL_SIZE`, `__MAX_OVERFLOW`, … | no | Pool tuning; defaults follow 3F §15.1. |

Environment rules:

- **local** — `backend/.env.local` is read for convenience (copy
  `.env.local.example`). `ENVIRONMENT=local` itself must come from the shell.
- **test** — the database name must start with `voice_agent_test_`, so tests can
  never reach a development or shared database.
- **staging / production** — fail closed: PostgreSQL TLS (`?ssl=require` or
  stricter), `rediss://`, JSON logs, no `DEBUG`, `https://` CORS origins only.
  No dotenv file is read; values come from the secret manager (3F §7).

**The database identity is the one validated.** SQLAlchemy forwards URL query
parameters to the driver, where `database`, `host`, `port`, `user`, `service`
and similar options would replace the host, database or role that was checked.
`DATABASE__URL` therefore accepts no query parameter except `ssl`, and the
engine passes host, port, user and database to asyncpg explicitly, so libpq
environment variables (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSERVICE`)
cannot change them either.

## Local dependencies

Either use your own PostgreSQL 18 (+ pgvector) and Redis 7.2+, or Docker:

```bash
cp ../infra/docker-compose/.env.example ../infra/docker-compose/.env   # then fill in values
docker compose -f ../infra/docker-compose/docker-compose.yml up -d --wait
```

PostgreSQL listens on `127.0.0.1:54320`, Redis on `127.0.0.1:63790`.

## Migrate the database

The schema is owned by the frozen SQL package under
`docs/phase-05-database-design/5K` (112 migrations, `001_5B` → `112_5H5`). The
application never migrates on startup; migration is an explicit step.

`MIGRATION_DATABASE_URL` is the administrative migration/deployment identity
(`postgresql+psycopg://user:<password>@host:port/db`). Migration `001_5B`
creates the platform roles and extensions, so a fresh database needs an
identity allowed to do that. It is never a runtime role: `app_api`,
`app_worker` and `app_readonly` are refused by every command.

Before connecting, every command derives the target libpq will really use and
refuses anything that could redirect it: a URL without an explicit port, a host
list or socket path, query parameters other than TLS/timeout options (`host`,
`hostaddr`, `port`, `dbname`, `user`, `service`, `servicefile`, `options` are
all refused), and the `PGHOSTADDR`, `PGSERVICE` and `PGSERVICEFILE` variables.

```bash
export MIGRATION_DATABASE_URL='postgresql+psycopg://voice_agent_bootstrap:<password>@127.0.0.1:54320/voice_agent_dev'

uv run python scripts/db_migrate.py graph                 # validate the package, no database
uv run python scripts/db_migrate.py check                 # server prerequisites + current revision
uv run python scripts/db_migrate.py upgrade               # upgrade to 112_5H5
uv run python scripts/db_migrate.py check --expect-head   # fail unless at head with extensions installed
uv run python scripts/db_migrate.py gate --expected-head 112_5H5   # deployment gate, see below
```

`upgrade` refuses a database that already contains the schema but has no
`alembic_version` table; such a database must be stamped as described in
[`5K/alembic/README.md`](../docs/phase-05-database-design/5K/alembic/README.md).

The migration creates `app_api` without a password (5K §9.1). On a local
machine, give it the password from your `DATABASE__URL`:

```bash
ENVIRONMENT=local uv run python scripts/db_migrate.py set-runtime-password
```

This command only runs for `local`/`test`. Both URLs must name the same
loopback host, the same explicit port and the same database, and before the
role is altered the server actually reached must report a loopback address and
that port and database.

### Deployment gate: is the target schema current?

```bash
MIGRATION_DATABASE_URL='postgresql+psycopg://<deployment role>:<password>@<host>:<port>/<db>?sslmode=verify-full' \
  uv run python scripts/db_migrate.py gate --expected-head 112_5H5
```

Run this **before every rollout, against the actual target database, with
migration/deployment credentials**. It exits non-zero unless all of these hold:

- the repository migration graph is the frozen baseline (112 revisions, sole head);
- `--expected-head` is exactly that repository head and the head this build requires;
- the connection is not a runtime role and reached the database named in the URL;
- `alembic_version` exists and records exactly the expected head (a stale,
  unknown, missing or multiple revision fails, each with its own message);
- the required extensions are installed.

Output names the target and the revisions, never a credential. In CI/CD, call
the reusable workflow `.github/workflows/deployment-schema-gate.yaml` before
the rollout job; operators run the command above by hand.

## Run the API

```bash
ENVIRONMENT=local uv run uvicorn --factory voice_agent.apps.api.asgi:application --reload
curl http://127.0.0.1:8000/health/live
curl http://127.0.0.1:8000/health/ready
```

Stop with Ctrl+C: the server stops accepting requests, closes Redis and
disposes the PostgreSQL pool, logging each step.

## Probes and startup policy

| Endpoint | Meaning | Response |
|---|---|---|
| `GET /health/live` | The process is serving. Checks nothing external. | `200 {"status":"ok"}` |
| `GET /health/ready` | PostgreSQL and Redis both answer now (checked in order, first failure stops). | `200` with every check `ok`, else `503 {"status":"unavailable","checks":{...}}` with `ok`/`failed`/`skipped` per check |

Startup **fails fast**: if PostgreSQL or Redis is unreachable, PostgreSQL is
not version 16+ (18 is the baseline), required extensions are missing, the
runtime role is a superuser or bypasses RLS, or Redis is older than 7.2, the
process exits non-zero. After startup, an outage only makes readiness fail;
liveness stays healthy and readiness recovers on its own.

### Runtime readiness is not the schema check

| | Proves | Runs | Credentials |
|---|---|---|---|
| **Runtime readiness** (`/health/ready`) | PostgreSQL and Redis are operationally reachable now (Redis must answer `PING` with `PONG`). | Continuously, in the application. | Runtime role `app_api`. |
| **Deployment gate** (`db_migrate.py gate`) | The target database's schema revision equals the expected head. | Once per rollout, before it, outside the application. | Migration/deployment role. |

Readiness never claims the migrations are current. The least-privileged
`app_api` role has no access to `alembic_version` in the frozen schema and is
not given any, so startup logs `schema_revision_status=deployment_gated`: schema
currency is owned by the deployment gate. (Controlled architecture
reconciliation OD-D0-01, see `docs/D0-FINDINGS-AND-RECONCILIATIONS.md`.)

## Errors

Every error uses the frozen envelope
`{"error": {code, message, details, request_id, retryable}}`. D0 emits
`VALIDATION_ERROR` (400/422), `RESOURCE_NOT_FOUND` (404), `INTERNAL_ERROR` (500),
`DEPENDENCY_UNAVAILABLE` (503, retryable) and `METHOD_NOT_ALLOWED` (405, with
the `Allow` header; controlled API erratum OD-D0-02). A PostgreSQL or Redis
outage during a request is `DEPENDENCY_UNAVAILABLE`, including a database that
refuses new connections; a constraint violation or SQL error is not.

Every response carries a server-generated `X-Request-ID`, CORS preflights
included. A rejected preflight is a `VALIDATION_ERROR` (400) envelope, not a
plain-text body. Middleware order: correlation → CORS → error capture → routes.

## Logging

Everything handed to a logger is untrusted, and the logging pipeline is a trust
boundary (`observability/logging.py`, `observability/redaction.py`). Nothing is
exempt from it: there is no "already sanitised" type or marker, and the event is
sanitised in full a second time immediately before it is rendered. The design
is set out in `docs/D0-FINDINGS-AND-RECONCILIATIONS.md` §2c.

| Input | Treatment |
|---|---|
| Logger, service and environment names, level, timestamp, request ID | Accepted only if they match a short identifier grammar; otherwise replaced by a fixed word (`untrusted_logger`, …). Never shortened or cleaned up. |
| Structured fields | A bounded number is admitted; each value is rebuilt from exact built-in types. Credential-named keys are masked. |
| Signed or presigned media and storage URLs (6A §22) | Masked by the name of the field that carries them (`download_url`, `upload_url`, `presigned_url`, `signed_url`, `recording_url`, `media_url`, … in any case style), whatever the value looks like. Never log the response body of an endpoint that returns one. |
| Tracebacks and stacks | Built from frame metadata, one unit per frame: a filename is validated whole (or replaced by `<unsafe filename>` / `<filename too long>`), and no source line is shown. |
| Free text (event text, string fields, exception messages) | Grammar-aware masking of the supported forms below; ambiguous or oversized text is replaced whole. |
| Objects | Never asked to convert themselves. `str`/`int`/`float` subclasses are read through the base type; UUID, Decimal, dates, times, paths and bytes are rendered for their exact type only; anything else is `[UNSUPPORTED]`. |
| Failures of the pipeline itself | A fixed record or a fixed stderr diagnostic built from validated identifiers only. |

Supported text forms: `key=value` / `key: value` pairs and libpq connection
strings (quoted, escaped and percent-encoded forms included), URL userinfo and
sensitive query or fragment parameters, credential headers (`Authorization`,
`Proxy-Authorization`, `Cookie`, `Set-Cookie`, API-key headers), bearer and
Digest credentials, JWTs, PEM private keys, JSON embedded in text, and
`user:password@host` written as one token without a scheme.

What is not a supported form is not guessed at:

- A string in which anything was masked and which also contains a control
  character (tab, CR, LF, …) or non-ASCII whitespace is logged as `[REDACTED]`
  in full. Parsers disagree about those characters (libpq keeps an EM SPACE in
  a password, its URI parser a tab or newline, a folded header continues on the
  next line), so a partial mask cannot be trusted there. Multi-line text
  without any credential is unaffected. A traceback is not multi-line text to
  the sanitiser: it is a list of separately validated units until it is laid
  out.
- A string longer than 16,384 characters that shows any sign of a credential
  in its examined part is logged as `[TRUNCATED_SENSITIVE_VALUE]`; text is
  never cut first and classified afterwards.
- A sensitive URL parameter is masked to the next `&` or to the end of the
  string, and a URL credential is looked for across whitespace.
- A string in which a credential is only visible after decoding, or that does
  not decode to a fixed point within three rounds, is logged as `[REDACTED]`.

Do not rely on any of this to hide a bare secret logged under an innocent field
name, a capability URL written as bare text, or a credential written in a form
not listed above: never log secrets.

One event is bounded from the first step, not only at the end. At most 200
fields are admitted, counting context-local fields (the rest are never visited
or copied, and a standard-library record is reduced to its standard attributes
without its `extra=` attributes being traversed); 2,048 values are
visited; 524,288 characters of text are examined; 65,536 characters are
rendered, each scalar charged what it actually renders as; containers are
limited to depth 8 and 200 items and are expanded once per event (`[REPEATED]`,
`[CYCLE]`); integers above 128 bits and Decimals above 40 digits are replaced
by a marker without being rendered. A standard-library format string is
interpolated only if its widths and precisions are at most 256 (no `*`), it has
at most 64 directives and at most 16,384 characters; otherwise a fixed
`log_record_unsafe_format` record is emitted. A rendered line above 131,072
characters is replaced by a fixed `log_record_oversized` record. Whatever a
limit cuts off becomes `[TRUNCATED]`; the identifying fields survive. Reaching
a limit costs detail, never confidentiality.

## Tests and quality commands

```bash
uv run ruff format --check .                     # formatting
uv run ruff check .                              # lint (includes print() ban and security rules)
uv run mypy                                      # strict static typing
uv run pytest -m unit                            # no external process
uv run pytest -m "integration or smoke"          # real PostgreSQL 18 + Redis
uv run python scripts/check_repository.py        # frozen docs unchanged, no committed secrets
uv run python scripts/verify.py                  # all of the above + migration graph; non-zero on any failure
uv run pytest --test-order=reverse               # also: --test-order=random:<seed>
```

- **unit** — pure logic and HTTP behaviour without dependencies; may use test doubles.
- **integration** — real databases and Redis: migrations, sessions, readiness failures.
- **smoke** — the real `uvicorn` process: boot, serve, signal-driven shutdown.

Integration and smoke tests start a **private PostgreSQL 18 cluster** (`initdb`
in a temp directory, random port and password, bound to `127.0.0.1`) and
private `redis-server` processes, migrate one template database with the CLI,
and give each test its own copy, dropped afterwards. They never connect to an
existing server, and every create/drop is refused unless the target is a
`voice_agent_test_*` database on a cluster the harness created. If a binary is
missing, the tests fail and say which one.

Each test has its own event loop; engines, Redis clients and the runtime are
created and closed inside the test that uses them.

## Reset the local stack

```bash
docker compose -f ../infra/docker-compose/docker-compose.yml down        # stop, keep data
docker compose -f ../infra/docker-compose/docker-compose.yml down -v     # stop and delete local data
```

Test infrastructure needs no reset: it lives in temporary directories removed
at the end of every run.
