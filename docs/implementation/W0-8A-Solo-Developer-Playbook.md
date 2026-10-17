# W0 / 8A — Solo-Developer Engineering Playbook

| Field | Value |
|---|---|
| Wave | W0; applies to W1 – W6 |
| Date | 2026-10-16 (first submission); revised 2026-10-16 for the first independent review (M-W0-04 and the KMS rule below) — see [Review-resolution ledger](W0-8A-Review-Resolution-Ledger.md) |
| Status | Planning record for independent re-review |
| Reader | The owner (solo full-stack developer, strongest in TypeScript/React/Next.js) and the AI assistants working with them |

This playbook changes the **process** only. Every security, tenant-isolation, event-durability, billing, privacy and test requirement of Phases 1–7 and D0 applies unchanged (owner decision 3, 2026-10-16).

## 1. Who does what in one work package

| Step | Who | Output | Never |
|---|---|---|---|
| 1. Open the WP card | Claude or Codex | Filled card (template, Master Plan §7.2), ≤ 1 page, with frozen references checked by grep | Cite a rule, function or grant that was not found in the repository |
| 2. Small LLD (only if the card says "LLD: yes") | Claude | ≤ 2 pages: transaction boundaries, state transitions, error codes, events, tests | Restate frozen text; invent a route, table, permission, event or error code |
| 3. Owner check of open questions | Owner | Answer or "proceed" | — |
| 4. Implement with tests | Codex or Claude | Code + tests on a WP branch | Commit secrets; skip a failing test; mark a test xfail to pass the gate |
| 5. Run the gate locally | The implementer | Output of `uv run python scripts/verify.py` (and frontend checks) pasted into the PR | Paraphrase results; claim a run that did not happen |
| 6. Independent review | ChatGPT (with the diff, test output and the WP card) | Findings rated P0 / P1 / Minor (Master Plan §11.3) | Rate formatting or naming as P0/P1 |
| 7. Fix confirmed P0/P1 | Implementer | Commits referencing the finding ID | Fix unconfirmed findings silently |
| 8. As-built note | Implementer | Update `docs/implementation/as-built/<context>.md` (≤ 1 page per context: what exists, deviations, tests) and the Atlas status tag if it changed | Write a new architecture document |
| 9. Merge | Owner | Merge commit | Merge with an open P0/P1 |

Any tool may help at any step. A completion report from any assistant is a claim; the gate output and the reviewer's reading of the diff are the evidence.

## 2. Repository map

| Path | What it is | Edit? |
|---|---|---|
| `docs/phase-01-srs` … `docs/phase-07-event-architecture` | Frozen architecture | **Never.** Changes go through a controlled amendment |
| `docs/phase-05-database-design/5K/migrations/001_5B.sql` … `112_5H5.sql` and `…/alembic/versions` | Frozen schema | **Never.** New migrations are separate governed migrations |
| `docs/implementation/` | W0 plan, Atlas, as-built notes | Yes, through WPs |
| `backend/voice_agent/apps/api` | Core REST API deployable (D0) | Extend through WPs |
| `backend/voice_agent/platform` | Shared kernel and infrastructure (D0) | Extend through WPs; D0 tests must keep passing |
| `backend/voice_agent/modules/<context>` | Bounded contexts (created by W1-D1-01; layout 3A §3, 3B §3) | Yes |
| `backend/voice_agent/apps/voice_gateway`, `apps/worker` | Planned deployables (3A §3) | Created by their WPs |
| `backend/tests/{unit,integration,smoke}` | D0 test layout; `contract/` added for tenant-isolation contracts (3A §3) | Yes |
| `frontend/` | Next.js workspace (3A §4), created by W1-D8-01 | Yes |
| `infra/` | Dockerfile, Compose (D0) | Through WPs |
| `backend/scripts/check_repository.py` | Fails on **any** uncommitted change under `docs/`, including new files | Commit `docs/` changes before running `verify.py` |

## 3. Python and FastAPI for a TypeScript developer

| Python / FastAPI | Closest TypeScript / Node analogy | Rule here |
|---|---|---|
| `uv` + `pyproject.toml` + `uv.lock` | pnpm + `package.json` + lockfile | `uv sync --locked`; add a dependency only through a WP that names why |
| Virtual environment `.venv` | `node_modules` per project | Created by uv; never committed |
| Type hints + `mypy --strict` | `tsc --strict` | Every function typed; no `Any` without a comment |
| Pydantic model | Zod schema + inferred type | Every request and response body; `extra="forbid"` at the API boundary |
| `async def` / `await` | `async` / `await` | Never call blocking I/O inside `async def` (ruff `ASYNC` rules) |
| `asyncio.Queue`, tasks | Streams / async iterators in Node | The voice pipeline uses them (3B §12) |
| FastAPI `Depends()` | Express/Nest middleware or DI provider | Auth, tenant context and DB session come from dependencies, never from globals |
| Context variables (`contextvars`) | `AsyncLocalStorage` | Request and tenant context (D0 `request_context.py`) |
| SQLAlchemy async session + `async with` transaction | Prisma `$transaction` / Knex transaction | One unit of work per use case; no transaction across provider I/O |
| `pytest` fixtures | Jest `beforeEach` with dependency injection | Integration fixtures create disposable databases (D0 harness) |
| Exceptions | Thrown errors | Raise typed platform errors; never swallow; the error catalog maps them (D0) |
| `structlog` logger | pino | Fields, not interpolated strings; never log secrets, audio, transcript text or signed URLs (D0 README "Logging") |

## 4. Local setup and daily commands

```bash
# one-time
cd backend && uv sync --locked
cp ../infra/docker-compose/.env.example ../infra/docker-compose/.env      # fill local-only values
docker compose -f ../infra/docker-compose/docker-compose.yml up -d --wait

# migrate the local database (bootstrap identity, never the runtime role)
export MIGRATION_DATABASE_URL='postgresql+psycopg://voice_agent_bootstrap:<password>@127.0.0.1:54320/voice_agent_dev'
uv run python scripts/db_migrate.py graph
uv run python scripts/db_migrate.py upgrade
uv run python scripts/db_migrate.py check --expect-head
ENVIRONMENT=local uv run python scripts/db_migrate.py set-runtime-password

# run
ENVIRONMENT=local uv run uvicorn --factory voice_agent.apps.api.asgi:application --reload

# test and gate (CI runs the same)
uv run pytest -m unit
uv run pytest -m "integration or smoke"      # needs PostgreSQL 18 binaries and redis-server on PATH
uv run python scripts/verify.py
```

Windows note: D0 uses `uvicorn` directly on Windows (gunicorn does not run there). PostgreSQL 18 binaries are on `PATH` on the owner's machine; set `PG_BIN_DIR` otherwise.

## 5. Coding standards that reviews enforce

| Standard | Concretely |
|---|---|
| Typing and validation | `mypy --strict` clean; Pydantic for every boundary; typed allow-lists, never a free JSON bag at the API (6D §8.2) |
| Boundaries | A module imports another module only through its public application interface (3A §2.3); a CI import check (W1-D1-01) fails otherwise. Cross-context data is referenced by ID (5A §2.2) |
| Transactions | One use case = one transaction, opened by the unit of work; audit (`audit.fn_insert_audit_event`) and outbox rows in the **same** transaction (6D §24.0; 7D PTX); no transaction open during provider or network I/O (6A §35) |
| Tenant isolation | `organization_id` comes from the server-side context, never from the request body; every tenant transaction sets `app.tenant_id` with `SET LOCAL`; every new table access gets an RLS-negative test |
| SQL | SQLAlchemy Core/ORM or bound parameters only; no string-built SQL; guarded functions are called, never bypassed with direct DML |
| Errors | Only cataloged codes (D0 `error_catalog.py`); new statuses need a controlled catalog entry (OD-D0-02 precedent) |
| Async workers | Idempotent by a durable key; safe to rerun after a crash at any line; no in-memory-only state that matters (3A principles) |
| Logging and tracing | Structured, correlated by request/call ID; redaction is a second line of defence, not permission to log sensitive data |
| Secrets | From environment/secret manager only; database stores `secret_manager://` references (5C `chk_pn_cred_ref`, `chk_pc_cred_ref` pattern) |
| Server authority | Prices, quotas, capacity, permissions and usage are computed server-side; the frontend only displays them |

## 6. Database and migration workflow

1. Need a schema change? Check the Register §4: is it an existing G-nn/CM-nn requirement? If not, it needs an owner decision first.
2. Confirm the approval it depends on is recorded (packet stage approval and migration authorization). No approval → the WP is BLOCKED.
3. Author one forward-only migration (next number assigned by the Phase-5 process; never edit 001–112), with its Alembic wrapper.
4. Test: fresh upgrade 001 → new head on the disposable PostgreSQL 18 cluster; grants and RLS assertions; concurrency tests for every guard; `db_migrate.py gate --expected-head <new>`.
5. Independent review (database checklist: privileges, RLS, SECURITY DEFINER search_path, triggers on every path including INSERT/DELETE/TRUNCATE, CHECK constraints against every state edge).
6. Apply to the target only through `db_migrate.py upgrade` with the migration identity, after the gate.

## 7. Secrets and provider credentials

- Real keys live in `backend/.env.local` (git-ignored; `check_repository.py` refuses committed env files and scans for tokens) or the OS keychain. Never paste keys into prompts for AI assistants, issues, logs or documents.
- Each provider gets a separate key per environment, least scope, spending limit set in the provider console, rotated after any suspected exposure.
- Database rows store references (`secret_manager://…`), never values. In local/test the secret provider resolves references from environment variables (3A §3 `env_secrets_provider`); staging/production use the secret manager + External Secrets Operator (3F §7).
- Exotel webhook/stream credentials are verified before any row is written; failures log the reason class, never the presented credential.
- The `CALLBACK_INPUT` key service (OD-W0-08, -13) uses a managed cloud KMS reached through workload identities, never a static access key in `.env` files: the ingress workload may only generate wrapped data keys, the processing workload may only decrypt (7I KEY-08); non-production and production root keys are separate (KEY-05); no person or AI assistant is given either permission for debugging, and decrypted processing inputs are never logged, traced or printed (7I CBI-06, CBI-12).

## 8. Debugging recipes

| Need | How |
|---|---|
| Call an API | `curl -i http://127.0.0.1:8000/...` or `httpx` in a pytest; every response carries `X-Request-ID` — search logs by it |
| Inspect the outbox | As a read-only role: `SELECT event_type, status, attempt_count, occurred_at FROM audit.domain_event_outbox ORDER BY occurred_at DESC LIMIT 20;` (M1 rows must be `PENDING`) |
| Inspect Redis Streams | `redis-cli -p 63790 XINFO STREAM <key>`, `XINFO GROUPS <key>`, `XPENDING <key> <group>` (read-only commands only) |
| Debug a WebSocket | A small pytest client (`httpx-ws` or the `websockets` library) replaying recorded provider frames; a CLI such as `websocat` for manual probing (install only on the dev machine) |
| Trace a call | Find the call's trace ID in the gateway log, open it in the trace viewer (W1-D9-01), check per-stage spans |
| Reproduce a race | Two real connections in an integration test with an explicit lock or barrier (D0 integration tests show the pattern) |

## 9. Frontend ↔ backend integration

FastAPI publishes OpenAPI (`/openapi.json`, enabled locally by `API__DOCS_ENABLED=true`). The frontend client is generated from it (`openapi-typescript`, 3A §4 `packages/api-client/generated`, never hand-edited) and wrapped with TanStack Query. CORS origins are exact (D0). Access tokens stay in memory; the refresh token is an `httpOnly` cookie (6B §10). The UI hides what a user cannot do, but the server enforces it.

## 10. Provider testing procedure

1. Read the provider's current documentation; record URL and date in the FS report.
2. Use a sandbox or test account with a spending cap; use only the owner's and consenting testers' voices; no customer data.
3. Script each test; capture raw request/response metadata (no secrets, no audio in logs); store audio samples only in the evaluation set location the WP names.
4. Record verdicts as SUPPORTED / NOT SUPPORTED / UNVERIFIED with evidence links.
5. Never upgrade a mocked result to "provider validated".

## 11. Commits, branches and checkpoints

- One branch per WP: `wp/W1-D2-01-tenant-transactions`. Small commits, each green on `verify.py` where feasible.
- Commit message: `W1-D2-01: <what changed>`; reference finding IDs when fixing (`fixes W1-D2-01-R1-P1-02`).
- Tag accepted milestones (`m1-verified`) only after the slice gate and the owner's acceptance.
- Before a risky change, commit or stash; never use destructive Git commands on shared history.

## 12. Failure report template

```text
WP / finding ID:
Environment: local | test | M1 | staging     Commit: <sha>
What I ran (exact command):
Expected (cite the frozen rule or test):
Actual (paste output; redact secrets):
Reproduces? always | intermittent (n of m)
Request / trace / call IDs:
Data touched (tables, org IDs - synthetic only):
Suspected cause (optional):
Severity proposal: P0 | P1 | Minor, with the reason
```

## 13. Review request template (to ChatGPT or another reviewer)

```text
WP: <ID and name>      Branch/commit: <sha>
Frozen contracts in scope: <rule IDs and sections>
What changed: <files>
Evidence: <verify.py output; integration output; provider evidence if any>
Known limitations and closed gates: <list>
Ask: review against the contracts; rate P0/P1/Minor per Master Plan §11.3; do not re-open approved architecture without contradicting source evidence.
```
