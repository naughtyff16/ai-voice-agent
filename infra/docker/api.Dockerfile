# Core REST API image (3F §3.1). Build context: backend/.
#   docker build -f infra/docker/api.Dockerfile backend/

FROM python:3.12-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never
WORKDIR /app
# Dependencies first, from the lockfile only, so code changes reuse this layer.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-dev --no-install-project
COPY voice_agent ./voice_agent
COPY README.md ./
RUN uv sync --locked --no-dev --no-editable

FROM python:3.12-slim AS runtime
RUN groupadd --gid 10001 appgroup \
 && useradd --uid 10001 --gid appgroup --no-create-home --shell /usr/sbin/nologin appuser
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
USER appuser
EXPOSE 8000
# Settings are read by the factory at worker start; the image holds no configuration.
ENTRYPOINT ["gunicorn", "voice_agent.apps.api.asgi:application()", \
            "--worker-class", "uvicorn_worker.UvicornWorker", \
            "--bind", "0.0.0.0:8000", \
            "--workers", "2", \
            "--graceful-timeout", "30"]
