# Phase 3F — Low-Level Design: Deployment Internals

| | |
|---|---|
| **Roadmap phase** | Phase 3 (Low-Level Design) — sub-phase 3F: Deployment Internals |
| **Status** | Draft v1.0, for review |
| **Source of truth (approved, not redesigned here)** | Phase 1 SRS, Phase 2 HLA, Phase 3A–3E Platform LLD documents |
| **Explicitly out of scope** | Application business logic — this document covers only infrastructure, platform operations, and deployment mechanics |

## 0. Scope and Traceability

This document designs everything required to run the platform in production: how every application component is containerised, orchestrated, scaled, secured at the network layer, observed, recovered from failure, and continuously deployed. It assumes all bounded contexts from 3A–3E are the software being deployed — it does not redefine them, only defines the infrastructure that hosts them.

| # | Requested item | Section |
|---|---|---|
| 1 | Docker | §3 |
| 2 | Docker Compose | §4 |
| 3 | Kubernetes | §5 |
| 4 | GitHub Actions | §6 |
| 5 | Secrets | §7 |
| 6 | NGINX | §8 |
| 7 | Autoscaling | §9 |
| 8 | Disaster Recovery | §10 |
| 9 | Backup Strategy | §11 |
| 10 | Multi Region | §12 |
| 11 | CDN | §13 |
| 12 | Networking | §14 |
| 13 | Load Balancer | §8 |
| 14 | Database Scaling | §15 |
| 15 | Redis Scaling | §16 |
| 16 | Monitoring | §17 |
| 17 | Logging | §18 |
| 18 | Tracing | §19 |
| 19 | Health Checks | §20 |
| 20 | Deployment Strategy | §21 |
| 21 | Blue Green Deployment | §21.2 |
| 22 | Everything required for production | throughout |

---

## 1. Architecture Review Notes

*(Observations flagged for confirmation — nothing here changes an approved Phase 1/2/3A–3E decision.)*

1. **Cloud provider not specified anywhere upstream.** `TECH_STACK.md` names AWS S3, Supabase, Docker, Kubernetes, and NGINX — but not an underlying cloud (AWS, GCP, Azure, or a bare-metal Kubernetes provider). This document is deliberately cloud-provider-neutral in all Kubernetes manifests and CI/CD pipelines. Where a cloud-specific service is referenced (e.g., a managed Kubernetes offering, a secrets manager), the specific vendor is treated as a deployment-time decision and abstracted behind a named configuration variable. Recommend confirming the primary cloud provider before Phase 24.

2. **Supabase PostgreSQL as the managed database.** `TECH_STACK.md` mandates Supabase PostgreSQL. This constrains the database-scaling options to those Supabase supports (read replicas, connection pooler, point-in-time recovery) — §15 designs within those constraints. If a self-managed Postgres cluster is ever preferred, §15's architecture (PgBouncer, read-replica routing, WAL-based backup) applies unchanged with a different control plane.

3. **Multi-region is a Phase 2+ aspiration, not a Day 1 requirement.** `PRODUCT_VISION.md` states "cloud-native deployment" and mentions "multi-region" capability; `NFR-AVAIL-001` targets 99.9%+ monthly availability. §12 designs a multi-region architecture that can be activated incrementally — single-region at launch is the base configuration, additional regions are additive, not a rebuild.

4. **The Voice Gateway requires sticky routing at the load-balancer level.** As established in 3B §8, a live WebSocket voice call is pinned to the pod that accepted it. §8.4 formalises this as an NGINX upstream configuration requirement — it is not a new constraint, but it must be enforced at the infrastructure level, not just in application code.

5. **Secret management tooling is not in `TECH_STACK.md`.** 3A §9.1 identified that secrets must come from a secret manager in staging/prod but deferred vendor selection. This document proposes HashiCorp Vault (cloud-agnostic) or the cloud provider's native secret manager (AWS Secrets Manager / GCP Secret Manager) as the adapter behind 3A's `SecretsProvider` port — selection is a deployment-time decision, the port contract does not change.

6. **ClickHouse is not deployed in this document.** 3E §5.1 / Review Note 1 deferred ClickHouse until a volume trigger. This document includes a placeholder Kubernetes namespace and a one-line comment in Docker Compose marking where ClickHouse slots in — it is not configured beyond that.

---

## 2. Repository Layout — Infrastructure as Code

All infrastructure definitions live alongside application code in the same monorepo, in a top-level `infra/` directory. This keeps the application code and the infrastructure that runs it versioned together — a drift between app version and infra version is a build failure, not a runtime surprise.

```text
infra/
├── docker/
│   ├── api.Dockerfile
│   ├── voice_gateway.Dockerfile
│   ├── worker.Dockerfile
│   └── nginx/
│       ├── nginx.conf
│       └── conf.d/
│           ├── api.conf
│           ├── voice_gateway.conf
│           └── web.conf
├── docker-compose/
│   ├── docker-compose.yml          # local development full-stack
│   ├── docker-compose.test.yml     # CI integration test stack
│   └── .env.example                # committed — lists all required vars, no values
├── kubernetes/
│   ├── base/                       # Kustomize base — environment-agnostic manifests
│   │   ├── namespaces.yaml
│   │   ├── api/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── hpa.yaml
│   │   │   └── pdb.yaml
│   │   ├── voice_gateway/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── hpa.yaml
│   │   │   └── pdb.yaml
│   │   ├── worker/
│   │   │   ├── deployment.yaml
│   │   │   ├── hpa.yaml
│   │   │   └── pdb.yaml
│   │   ├── web/
│   │   │   ├── deployment.yaml
│   │   │   └── service.yaml
│   │   ├── nginx_ingress/
│   │   │   ├── ingress.yaml
│   │   │   └── ingress_ws.yaml     # separate ingress for WS with sticky sessions
│   │   └── rbac/
│   │       ├── service_accounts.yaml
│   │       └── roles.yaml
│   ├── overlays/
│   │   ├── staging/
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/            # resource limits, replica counts, feature flags
│   │   └── production/
│   │       ├── kustomization.yaml
│   │       └── patches/
│   └── helm/                       # third-party charts pinned at exact versions
│       ├── redis/values.yaml
│       ├── prometheus/values.yaml
│       ├── grafana/values.yaml
│       ├── otel-collector/values.yaml
│       └── cert-manager/values.yaml
├── github-actions/                 # symlinked from .github/workflows/ — single source of truth
│   ├── ci.yaml
│   ├── deploy-staging.yaml
│   ├── deploy-production.yaml
│   ├── security-scan.yaml
│   └── db-migration.yaml
├── prometheus/
│   ├── prometheus.yaml
│   └── alerts/
│       ├── voice_slo.yaml          # defined in 3E §14.4
│       ├── infrastructure.yaml
│       ├── security.yaml
│       └── business.yaml
├── grafana/
│   └── dashboards/                 # versioned JSON per 3E §14.3
└── scripts/
    ├── bootstrap_local.sh          # one-command local dev setup
    ├── db_migrate.sh               # wraps alembic, used in CI and deploy pipelines
    ├── rollback.sh                 # manual rollback trigger with blue-green swap
    └── smoke_test.sh               # post-deploy health + canary verification
```

**Why Kustomize over raw YAML templating:** Kustomize keeps base manifests readable (no `{{ }}` noise in YAML) and allows overlays to patch only the fields that differ between environments — replica counts, resource limits, image tags — without duplicating entire manifests. Helm is used only for third-party charts (Redis, Prometheus, Grafana) where the chart's own templating is unavoidable; first-party manifests stay in Kustomize.

---

## 3. Docker — Image Design

### 3.1 Base Image Strategy

```dockerfile
# infra/docker/api.Dockerfile
# Stage 1: builder
FROM python:3.12-slim AS builder
WORKDIR /build
RUN pip install uv --no-cache-dir
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --group api   # installs only api-group deps, no dev tools

# Stage 2: runtime — smallest possible surface
FROM python:3.12-slim AS runtime
RUN groupadd --gid 10001 appgroup \
 && useradd --uid 10001 --gid appgroup --no-create-home appuser
WORKDIR /app
COPY --from=builder /build/.venv /app/.venv
COPY backend/ /app/backend/
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
USER appuser
EXPOSE 8000
ENTRYPOINT ["gunicorn", "apps.api.asgi:application",
            "--worker-class", "uvicorn.workers.UvicornWorker",
            "--bind", "0.0.0.0:8000",
            "--workers", "2"]
```

```dockerfile
# infra/docker/voice_gateway.Dockerfile  (same two-stage pattern)
# Difference: entrypoint targets apps.voice_gateway.main:app
# --workers 1 per pod — the WS pod owns its sessions (3B §8)
ENTRYPOINT ["gunicorn", "apps.voice_gateway.main:app",
            "--worker-class", "uvicorn.workers.UvicornWorker",
            "--bind", "0.0.0.0:8001",
            "--workers", "1"]
```

```dockerfile
# infra/docker/worker.Dockerfile
ENTRYPOINT ["celery", "-A", "apps.worker.celery_app", "worker",
            "--loglevel=info", "--concurrency=4", "--queues=default,voice,campaigns"]
```

**Why `--workers 1` for Voice Gateway pods:** established in 3B §8 — a live WebSocket is pinned to the OS process that accepted it. Multiple gunicorn workers in one pod would mean a reconnect might land on a different worker and lose the `ConnectionManager`'s in-memory socket handle. One worker per pod, scale via Kubernetes pod count.

**Why multi-stage builds:** the `builder` stage installs build tools, compilers, and dev dependencies that have no place in production — they expand the image attack surface and size. The `runtime` stage copies only the virtual environment and application code. Practical result: the runtime image is roughly 40–60% smaller and has fewer exploitable binaries.

**Non-root user in every image:** `appuser` (uid 10001) — `CODING_STANDARDS.md`'s security-by-design principle; if a container is compromised, the process has no root privileges on the host.

### 3.2 Image Tagging Strategy

| Tag | When produced | Purpose |
|---|---|---|
| `:<git-sha>` | Every push to any branch | Immutable, auditable — what exactly is running in staging/prod |
| `:staging` | On deploy to staging | Mutable convenience tag — "what is in staging right now" |
| `:latest` | On deploy to production | Mutable convenience tag — never used in Kubernetes manifests, only for human inspection |
| `:v<semver>` | On a tagged release | Release correlation for changelog and rollback reference |

**Kubernetes manifests always use the immutable `:<git-sha>` tag.** `:latest` is explicitly forbidden in manifests — it makes "what is running" ambiguous and breaks rollbacks.

### 3.3 Container Registry

A private registry (cloud provider's native offering or self-hosted Harbor). Image vulnerability scanning runs on every push via the `security-scan.yaml` workflow (§6.3) — a critical/high CVE in a runtime layer blocks the deploy pipeline.

---

## 4. Docker Compose — Local Development and CI

### 4.1 Local Full-Stack (`docker-compose.yml`)

```yaml
# infra/docker-compose/docker-compose.yml
version: "3.9"

services:
  postgres:
    image: supabase/postgres:15.1.0.117
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: platform_dev
    ports: ["5432:5432"]
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./scripts/init_rls.sql:/docker-entrypoint-initdb.d/01_rls.sql

  redis:
    image: redis:7.2-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    ports: ["6379:6379"]
    volumes:
      - redis_data:/data

  api:
    build:
      context: ../../backend
      dockerfile: ../infra/docker/api.Dockerfile
      target: runtime
    environment:
      ENVIRONMENT: local
      DATABASE__URL: postgresql+asyncpg://postgres:${POSTGRES_PASSWORD}@postgres:5432/platform_dev
      REDIS__URL: redis://:${REDIS_PASSWORD}@redis:6379/0
    env_file: [.env.local]
    ports: ["8000:8000"]
    volumes:
      - ../../backend:/app/backend       # hot reload in local dev
    depends_on: [postgres, redis]
    command: uvicorn apps.api.asgi:application --reload --host 0.0.0.0 --port 8000

  voice_gateway:
    build:
      context: ../../backend
      dockerfile: ../infra/docker/voice_gateway.Dockerfile
      target: runtime
    environment:
      ENVIRONMENT: local
      DATABASE__URL: postgresql+asyncpg://postgres:${POSTGRES_PASSWORD}@postgres:5432/platform_dev
      REDIS__URL: redis://:${REDIS_PASSWORD}@redis:6379/0
    env_file: [.env.local]
    ports: ["8001:8001"]
    volumes:
      - ../../backend:/app/backend
    depends_on: [postgres, redis]

  worker:
    build:
      context: ../../backend
      dockerfile: ../infra/docker/worker.Dockerfile
      target: runtime
    environment:
      ENVIRONMENT: local
      DATABASE__URL: postgresql+asyncpg://postgres:${POSTGRES_PASSWORD}@postgres:5432/platform_dev
      REDIS__URL: redis://:${REDIS_PASSWORD}@redis:6379/0
    env_file: [.env.local]
    volumes:
      - ../../backend:/app/backend
    depends_on: [postgres, redis]

  web:
    build:
      context: ../../frontend
      dockerfile: ../infra/docker/web.Dockerfile
    ports: ["3000:3000"]
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:8000
    volumes:
      - ../../frontend:/app
      - /app/node_modules            # preserve container node_modules from host mount

  nginx:
    image: nginx:1.25-alpine
    ports: ["80:80"]
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    depends_on: [api, voice_gateway, web]

  # Observability (local)
  prometheus:
    image: prom/prometheus:v2.51.0
    ports: ["9090:9090"]
    volumes:
      - ../../infra/prometheus/prometheus.yaml:/etc/prometheus/prometheus.yml:ro

  grafana:
    image: grafana/grafana:10.3.0
    ports: ["3001:3000"]
    volumes:
      - ../../infra/grafana/dashboards:/var/lib/grafana/dashboards:ro
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}

  # ClickHouse placeholder — not configured until analytics volume trigger (3E Review Note 1)
  # clickhouse:
  #   image: clickhouse/clickhouse-server:24.3

volumes:
  postgres_data:
  redis_data:
```

### 4.2 CI Integration Test Stack (`docker-compose.test.yml`)

Extends the base with ephemeral, isolated services — no volume mounts, no ports exposed to the host, single-use for the CI run then discarded.

```yaml
# infra/docker-compose/docker-compose.test.yml
version: "3.9"

services:
  postgres_test:
    image: supabase/postgres:15.1.0.117
    environment:
      POSTGRES_PASSWORD: test_password
      POSTGRES_DB: platform_test
    tmpfs: [/var/lib/postgresql/data]  # ephemeral — data lost on container stop

  redis_test:
    image: redis:7.2-alpine
    command: redis-server --save ""    # no persistence in tests

  api_test:
    build: { context: ../../backend, dockerfile: ../infra/docker/api.Dockerfile }
    environment:
      ENVIRONMENT: local
      DATABASE__URL: postgresql+asyncpg://postgres:test_password@postgres_test:5432/platform_test
      REDIS__URL: redis://redis_test:6379/0
    depends_on: [postgres_test, redis_test]
    command: pytest tests/integration --tb=short -q
```

---

## 5. Kubernetes — Cluster Architecture

### 5.1 Namespace Strategy

```mermaid
flowchart TB
    subgraph Cluster["Kubernetes Cluster"]
        NS_APP[app — all platform deployments]
        NS_DATA[data — Redis cluster, in-cluster caches]
        NS_OBS[observability — Prometheus, Grafana, OTel Collector]
        NS_INGRESS[ingress — NGINX Ingress Controller]
        NS_CERT[cert-manager — TLS certificate automation]
        NS_SECRETS[secrets — external secrets operator]
        NS_CH[clickhouse — reserved, empty until activation]
    end
```

**Why separate namespaces per concern rather than one namespace:** Kubernetes RBAC, NetworkPolicy, and ResourceQuota are all namespace-scoped — separation gives free isolation between concerns. The observability namespace can be granted read-only access to all pods' metrics scrape endpoints without having any write access to the app namespace. A compromised app pod cannot read secrets mounted into the secrets namespace.

### 5.2 Core Workload Manifests

#### API Deployment

```yaml
# infra/kubernetes/base/api/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: app
spec:
  revisionHistoryLimit: 5          # retain 5 previous ReplicaSets for fast rollback
  selector:
    matchLabels: { app: api }
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0            # zero-downtime rolling update
  template:
    metadata:
      labels: { app: api }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: api-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: { type: RuntimeDefault }
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels: { app: api }
      containers:
        - name: api
          image: REGISTRY/platform-api:GIT_SHA    # replaced by Kustomize image transform
          ports:
            - containerPort: 8000
          resources:
            requests: { cpu: "500m", memory: "512Mi" }
            limits: { cpu: "2000m", memory: "1Gi" }
          envFrom:
            - secretRef: { name: platform-secrets }   # injected by External Secrets Operator
          livenessProbe:
            httpGet: { path: /health/live, port: 8000 }
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3
          readinessProbe:
            httpGet: { path: /health/ready, port: 8000 }
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 2
      terminationGracePeriodSeconds: 60      # allow in-flight requests to complete
```

#### Voice Gateway Deployment

```yaml
# infra/kubernetes/base/voice_gateway/deployment.yaml
# Key differences from API deployment:
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2
      maxUnavailable: 0            # new pods ready before old are drained
  template:
    spec:
      terminationGracePeriodSeconds: 300    # allow active calls to complete before SIGTERM
      containers:
        - name: voice_gateway
          ports:
            - containerPort: 8001
          resources:
            requests: { cpu: "1000m", memory: "1Gi" }   # higher: N concurrent audio streams
            limits: { cpu: "4000m", memory: "2Gi" }
          lifecycle:
            preStop:
              exec:
                command: ["/app/scripts/graceful_shutdown.sh"]
                # signals new calls to not land here; waits for active calls to drain
```

**Why `terminationGracePeriodSeconds: 300` for Voice Gateway:** Kubernetes sends `SIGTERM` and then waits `terminationGracePeriodSeconds` before sending `SIGKILL`. A phone call can last up to ~5 minutes in the 99th percentile. Without a 300s grace period, a rolling update could `SIGKILL` a pod mid-call. The `preStop` hook signals the pod to stop accepting new calls (marking it unavailable in the NGINX sticky session upstream) while existing calls drain naturally.

#### Worker Deployment

```yaml
# infra/kubernetes/base/worker/deployment.yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1            # one pod at a time is acceptable for async work
  template:
    spec:
      terminationGracePeriodSeconds: 120    # allow Celery tasks to complete
      containers:
        - name: worker
          resources:
            requests: { cpu: "500m", memory: "512Mi" }
            limits: { cpu: "2000m", memory: "2Gi" }  # scoring tasks may be CPU-heavy
```

### 5.3 PodDisruptionBudget — Minimum Availability During Upgrades

```yaml
# infra/kubernetes/base/api/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: app
spec:
  minAvailable: 2        # at least 2 API pods always available, even during node drain
  selector:
    matchLabels: { app: api }

# voice_gateway/pdb.yaml
spec:
  minAvailable: 1        # at least 1 always available; sticky sessions mean zero is catastrophic
```

### 5.4 NetworkPolicy — Zero-Trust Pod-to-Pod

```yaml
# infra/kubernetes/base/api/network_policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-netpol
  namespace: app
spec:
  podSelector:
    matchLabels: { app: api }
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: ingress }
      ports:
        - protocol: TCP
          port: 8000
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: observability }
      ports:
        - protocol: TCP
          port: 8000        # metrics scrape
  egress:
    - to:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: data }
      ports:
        - { protocol: TCP, port: 6379 }    # Redis
    - to: [{}]
      ports:
        - { protocol: TCP, port: 443 }     # external HTTPS (Supabase, providers)
        - { protocol: TCP, port: 5432 }    # Supabase Postgres
```

**Default-deny posture:** without an explicit `NetworkPolicy`, all pod-to-pod traffic is allowed. Applying a default-deny-all policy in each namespace and then explicitly permitting only required traffic is OWASP-aligned (`NFR-SEC-008`) and implements the zero-trust lateral movement constraint at the infrastructure layer, not just application code.

### 5.5 RBAC — Kubernetes Service Accounts

```yaml
# infra/kubernetes/base/rbac/service_accounts.yaml
# Each workload gets its own service account — no sharing
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-sa
  namespace: app
  annotations:
    # Cloud provider IRSA/Workload Identity annotation — maps to an IAM role
    # that has exactly: s3:GetObject, s3:PutObject on the platform bucket
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/platform-api-role
```

Minimum-privilege IAM roles per workload — API pods can read/write S3; they cannot read secrets from the secrets manager (that is the External Secrets Operator's job, running under its own service account).

---

## 6. GitHub Actions — CI/CD Pipelines

### 6.1 CI Pipeline (`ci.yaml`)

Triggered on every push to every branch and every pull request.

```mermaid
flowchart LR
    Push --> Lint["lint + typecheck
ruff, mypy, eslint"]
    Lint --> UnitTests["unit tests
pytest / vitest"]
    UnitTests --> IntTests["integration tests
docker-compose.test.yml"]
    IntTests --> SecScan["security scan
trivy image scan
bandit (Python)
npm audit"]
    SecScan --> Build["docker build
all three images"]
    Build --> Push2["push :<git-sha>
to private registry"]
```

```yaml
# .github/workflows/ci.yaml (abbreviated)
name: CI
on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
      - run: uv run ruff check backend/
      - run: uv run mypy backend/
      - run: pnpm --filter web eslint

  unit-tests:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - run: uv run pytest tests/unit --tb=short -q --cov=backend --cov-fail-under=80

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - run: docker compose -f infra/docker-compose/docker-compose.test.yml up --abort-on-container-exit
      - run: docker compose -f infra/docker-compose/docker-compose.test.yml down -v

  security-scan:
    runs-on: ubuntu-latest
    needs: integration-tests
    steps:
      - uses: actions/checkout@v4
      - uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          severity: CRITICAL,HIGH
          exit-code: 1            # fail the pipeline on critical/high CVEs

  build-and-push:
    runs-on: ubuntu-latest
    needs: security-scan
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/staging'
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ vars.REGISTRY }}
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
      - run: |
          SHA=${{ github.sha }}
          docker buildx build --push \
            --tag ${{ vars.REGISTRY }}/platform-api:${SHA} \
            --cache-from type=registry,ref=${{ vars.REGISTRY }}/platform-api:buildcache \
            --cache-to type=registry,ref=${{ vars.REGISTRY }}/platform-api:buildcache,mode=max \
            -f infra/docker/api.Dockerfile backend/
```

**BuildKit layer caching** (`--cache-from/--cache-to` registry mode) is non-negotiable at this scale: without it, every CI run reinstalls all Python dependencies from scratch. With it, a typical code-only change builds in under 2 minutes rather than 10+.

### 6.2 Database Migration Pipeline (`db-migration.yaml`)

Database migrations run as a **separate job before the application deployment** — not inside the application container on startup. This gives explicit control over whether a migration succeeded before any new application code starts handling traffic.

```yaml
# .github/workflows/db-migration.yaml
jobs:
  migrate:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}   # production or staging
    steps:
      - uses: actions/checkout@v4
      - name: Run Alembic migrations
        run: |
          uv run infra/scripts/db_migrate.sh ${{ inputs.environment }}
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
      - name: Verify migration
        run: uv run alembic current     # exits non-zero if head != current
```

**Why separate from app startup:** if a migration fails, the pipeline stops — no new pods are deployed with code that requires a schema that doesn't exist yet. Running migrations inside the app container's startup means a failed migration causes all pods to crash-loop before anyone notices there is a schema problem.

### 6.3 Staging Deploy (`deploy-staging.yaml`)

```yaml
jobs:
  deploy-staging:
    needs: [build-and-push, migrate]
    environment: staging
    steps:
      - name: Update Kustomize image tag
        run: |
          cd infra/kubernetes/overlays/staging
          kustomize edit set image platform-api=${{ vars.REGISTRY }}/platform-api:${{ github.sha }}
          kustomize edit set image platform-voice-gateway=${{ vars.REGISTRY }}/platform-voice-gateway:${{ github.sha }}
          kustomize edit set image platform-worker=${{ vars.REGISTRY }}/platform-worker:${{ github.sha }}
      - name: Apply to cluster
        run: kubectl apply -k infra/kubernetes/overlays/staging
      - name: Wait for rollout
        run: |
          kubectl rollout status deployment/api -n app --timeout=300s
          kubectl rollout status deployment/voice_gateway -n app --timeout=300s
          kubectl rollout status deployment/worker -n app --timeout=300s
      - name: Smoke tests
        run: infra/scripts/smoke_test.sh staging
```

### 6.4 Production Deploy — Blue-Green (`deploy-production.yaml`)

Full blue-green mechanics described in §21.2. The pipeline drives the switch.

```yaml
jobs:
  deploy-production:
    needs: [build-and-push, migrate]
    environment: production          # requires manual approval gate in GitHub Environments
    steps:
      - name: Identify inactive slot
        id: slot
        run: |
          ACTIVE=$(kubectl get service platform-active -n app -o jsonpath='{.spec.selector.slot}')
          echo "inactive=$([ "$ACTIVE" = "blue" ] && echo "green" || echo "blue")" >> $GITHUB_OUTPUT
      - name: Deploy to inactive slot
        run: |
          kustomize edit set image ... # same as staging but with slot=${{ steps.slot.outputs.inactive }}
          kubectl apply -k infra/kubernetes/overlays/production/${{ steps.slot.outputs.inactive }}
      - name: Wait for inactive slot readiness
        run: kubectl rollout status deployment/api-${{ steps.slot.outputs.inactive }} -n app --timeout=600s
      - name: Smoke test against inactive slot
        run: infra/scripts/smoke_test.sh production ${{ steps.slot.outputs.inactive }}
      - name: Switch traffic
        run: |
          kubectl patch service platform-active -n app \
            -p '{"spec":{"selector":{"slot":"${{ steps.slot.outputs.inactive }}"}}}'
      - name: Monitor for 5 minutes
        run: sleep 300 && infra/scripts/smoke_test.sh production active
      - name: Drain old slot (optional — keep for rollback window)
        run: echo "Old slot retained for 1 hour rollback window — see rollback.sh"
```

---

## 7. Secrets Management

### 7.1 Secret Hierarchy

```mermaid
flowchart TB
    SecretStore["Secret Store
HashiCorp Vault / Cloud Provider Secret Manager"]
    ESO["External Secrets Operator (Kubernetes)"]
    K8sSecret["Kubernetes Secret (namespace-scoped)
auto-rotated by ESO"]
    Pod["Pod (environment variable injection via secretRef)"]

    SecretStore --> ESO
    ESO -->|reconciles every 1h| K8sSecret
    K8sSecret --> Pod
```

**Why External Secrets Operator (ESO) rather than mounting the secret store directly in pods:** ESO decouples the secret store vendor from the pod spec — switching from Vault to AWS Secrets Manager means changing the `ExternalSecret` CRD's `spec.secretStoreRef`, not rewriting pod templates. It also handles rotation: when a secret rotates in the store, ESO automatically updates the Kubernetes Secret, and a pod rolling update picks up the new value on the next scheduled rotation window.

### 7.2 Secret Classification

| Secret class | Rotates | Where stored | Who injects |
|---|---|---|---|
| Database credentials | 90 days | Secret store | ESO → K8s Secret → pod env |
| Provider API keys (OpenAI, Deepgram, ElevenLabs, Exotel, etc.) | On compromise / 180 days | Secret store (per-tenant secrets stored in a tenant-scoped path) | ESO → K8s Secret |
| JWT signing key | 90 days | Secret store | ESO → K8s Secret |
| Internal service HMAC keys (webhook signing, plugin signing) | 180 days | Secret store | ESO → K8s Secret |
| Grafana admin password | Never rotated automatically | Secret store | ESO → K8s Secret |
| CI/CD deploy credentials | On offboarding | GitHub Encrypted Secrets | GitHub Actions runner |

**Tenant-specific provider keys** (an org's own OpenAI key, their own Exotel SID) are stored in a tenant-namespaced path in the secret store (`secrets/tenants/{tenant_id}/provider_keys`) and fetched at runtime by the `CloudSecretsProvider` adapter (3A §6.3) — not injected as environment variables at pod startup, because they are per-request runtime values, not per-process static config.

### 7.3 What Never Enters Source Control

- Any credential, key, or token with a real value.
- `.env.local` (git-ignored; listed in `.gitignore` at repo root).
- Kubernetes `Secret` YAML with real values (ESO `ExternalSecret` CRDs, which reference paths in the secret store but contain no values themselves, are committed).

Enforced mechanically: `gitleaks` runs as a pre-commit hook and in the `security-scan.yaml` workflow — a committed secret fails the build and triggers an alert.

---

## 8. NGINX — Ingress, Load Balancing, and Sticky Sessions

### 8.1 NGINX Ingress Controller

The NGINX Ingress Controller runs in the `ingress` namespace as a DaemonSet (one pod per node in the ingress node pool) with an external load balancer in front of it (cloud provider's L4 load balancer — TCP passthrough, not L7, so TLS termination happens at NGINX, not at the cloud LB).

### 8.2 TLS Termination

cert-manager (in the `cert-manager` namespace) manages TLS certificates via Let's Encrypt (or an enterprise CA for production) using the ACME HTTP-01 or DNS-01 challenge. Certificates are automatically renewed 30 days before expiry.

```yaml
# infra/kubernetes/base/nginx_ingress/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-ingress
  namespace: app
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"     # CSV upload limit
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
    nginx.ingress.kubernetes.io/rate-limit: "100"          # rps per IP — coarse DDoS protection
spec:
  tls:
    - hosts: [api.platform.example.com]
      secretName: platform-api-tls
  rules:
    - host: api.platform.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: api, port: { number: 8000 } }
```

### 8.3 WebSocket Ingress (Voice Gateway) — Sticky Sessions

```yaml
# infra/kubernetes/base/nginx_ingress/ingress_ws.yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"   # 1hr — long-lived WS
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "voice-session"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "3600"
    nginx.ingress.kubernetes.io/session-cookie-samesite: "None"
    nginx.ingress.kubernetes.io/session-cookie-secure: "true"
    # NGINX upstream hash — back-up to cookie affinity for WebSocket upgrade requests
    nginx.ingress.kubernetes.io/upstream-hash-by: "$http_x_call_sid"
spec:
  rules:
    - host: voice.platform.example.com
      http:
        paths:
          - path: /ws
            backend:
              service: { name: voice-gateway, port: { number: 8001 } }
```

**Two sticky-session mechanisms, layered:** the cookie-based affinity routes reconnects from the same browser/client to the same pod; the `upstream-hash-by: "$http_x_call_sid"` header hash routes the initial telephony provider WebSocket connection deterministically to a specific pod based on the call SID header the telephony provider sends. Both are belt-and-suspenders for the critical constraint established in 3B §8.

### 8.4 NGINX Configuration — Rate Limiting Zones

```nginx
# infra/docker/nginx/nginx.conf
http {
    # Per-tenant rate limit — keyed on the resolved tenant_id header
    # injected by the API after auth (the NGINX limit_req is a second line of defence)
    limit_req_zone $http_x_tenant_id zone=per_tenant:10m rate=500r/m;
    limit_req_zone $binary_remote_addr zone=per_ip:10m rate=60r/m;

    # Connection limit for WS (voice) — prevents one source from consuming all WS slots
    limit_conn_zone $binary_remote_addr zone=ws_conn:10m;
    limit_conn ws_conn 5;

    include /etc/nginx/conf.d/*.conf;
}
```

---

## 9. Autoscaling

### 9.1 Horizontal Pod Autoscaler (HPA)

```yaml
# infra/kubernetes/base/api/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3          # minimum 3 across nodes for HA (PDB enforces minAvailable: 2)
  maxReplicas: 50
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 65      # scale up before saturation
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60    # avoid thrashing on spikes
      policies:
        - type: Pods
          value: 4
          periodSeconds: 60             # add at most 4 pods per minute
    scaleDown:
      stabilizationWindowSeconds: 300   # 5 min cool-down before scale-down
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
```

```yaml
# voice_gateway HPA — keyed on active call count (custom metric via Prometheus adapter)
spec:
  minReplicas: 2
  maxReplicas: 100
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 50 }   # lower threshold — audio processing
    - type: Pods
      pods:
        metric:
          name: platform_active_calls   # from 3E §14.2 metric
        target:
          type: AverageValue
          averageValue: "50"            # target: 50 active calls per pod
```

**Why a custom metric for Voice Gateway HPA, not CPU alone:** CPU utilization is a trailing indicator for voice load — an async I/O-heavy workload (waiting on STT/LLM/TTS network) can have many active calls at low CPU. `platform_active_calls` per pod directly measures the resource the pod is constrained by (WebSocket connections and in-memory audio buffers), not an indirect proxy for it.

**Prometheus Adapter** (KEDA or the official `prometheus-adapter`) bridges `platform_active_calls` from Prometheus into the Kubernetes custom metrics API so the HPA can read it.

### 9.2 Cluster Autoscaler (Node-Level)

The cloud provider's Cluster Autoscaler or Karpenter is configured with:

| Node pool | Instance type | Min nodes | Max nodes | Purpose |
|---|---|---|---|---|
| `general` | 4 vCPU / 8 GB | 3 | 30 | API pods, worker pods |
| `voice` | 8 vCPU / 16 GB | 2 | 50 | Voice Gateway pods (audio I/O heavy) |
| `ingress` | 2 vCPU / 4 GB | 2 | 5 | NGINX DaemonSet (low churn) |
| `observability` | 4 vCPU / 16 GB | 1 | 3 | Prometheus (high memory for TSDB) |

Node pools are separated by `nodeSelector` / `taints+tolerations` on deployments — voice gateway pods are scheduled only on `voice` nodes, ensuring noisy-neighbour CPU competition from API pods doesn't affect voice processing latency.

### 9.3 Vertical Pod Autoscaler (VPA)

VPA runs in recommendation mode only — it does not automatically resize pods (which would cause restarts). Its recommendations are reviewed weekly and applied as manual patches to the base `requests`/`limits` in the manifests. Fully automatic VPA is too disruptive for the Voice Gateway (a pod restart terminates active calls).

---

## 10. Disaster Recovery

### 10.1 Failure Mode Taxonomy

| Failure | Scope | RTO target | RPO target |
|---|---|---|---|
| Single pod crash | One workload instance | 0 (HPA replaces immediately) | 0 (stateless) |
| Node failure | All pods on one node | < 2 min (Kubernetes reschedules) | 0 (stateless pods) |
| Availability zone failure | 1/3 of cluster capacity | < 5 min (auto-rebalanced across remaining AZs) | 0 |
| Entire region failure | All capacity in primary region | < 30 min (multi-region §12) | < 5 min (replication lag) |
| Database corruption (Supabase) | All application data | < 4 hours (PITR restore §11) | < 15 min (WAL shipping) |
| Redis cluster failure | All hot state (sessions, caches) | < 5 min (Redis cluster repair or failover) | Acceptable loss — Redis is a cache, not a source of truth |
| Secrets manager unavailability | Pod startup blocked | Mitigated: existing running pods use in-process cached secrets; new pod starts blocked | 0 for running workloads |

### 10.2 Pod-Level Resilience

- **`topologySpreadConstraints`** on every Deployment (shown in §5.2) — pods are spread across availability zones and nodes. A single node failure cannot take down more than `maxSkew: 1` extra pod above the average.
- **PodDisruptionBudgets** (§5.3) — ensure at least 2 API pods and 1 Voice Gateway pod survive any planned disruption (node drain, cluster upgrade).
- **`preStop` hook on Voice Gateway** — pods stop accepting new calls before the SIGTERM is sent; existing calls are given up to `terminationGracePeriodSeconds` to complete naturally.

### 10.3 Provider-Level Resilience

Covered by 3B §20 (STT/LLM/TTS failover) and 3D §11.3 (LLM circuit breaker). From an infrastructure perspective, all external provider traffic exits the cluster through a single SNAT address per AZ — rate limits enforced by providers are per-source-IP, so per-pod IP variety would consume per-IP rate limit budgets faster than necessary.

### 10.4 Runbooks (Referenced, Not Detailed Here)

| Scenario | Runbook location |
|---|---|
| Voice Gateway pod OOM | `docs/runbooks/voice-gateway-oom.md` |
| Redis cluster split-brain | `docs/runbooks/redis-split-brain.md` |
| Provider circuit breaker stuck open | `docs/runbooks/provider-circuit-open.md` |
| Database connection pool exhaustion | `docs/runbooks/db-pool-exhaustion.md` |
| Manual rollback | `infra/scripts/rollback.sh` + `docs/runbooks/rollback.md` |

---

## 11. Backup Strategy

### 11.1 PostgreSQL (Supabase)

| Backup type | Frequency | Retention | Mechanism |
|---|---|---|---|
| Continuous WAL shipping | Real-time | 7 days | Supabase PITR (built-in) |
| Daily logical snapshot | Daily 02:00 UTC | 30 days | `pg_dump` via Celery task → encrypted S3 |
| Weekly full snapshot | Sunday 03:00 UTC | 1 year | `pg_dump` → encrypted S3, replicated to secondary region |

**Why both WAL PITR and logical snapshots:** WAL PITR allows recovery to any point in the past 7 days (e.g., "restore to 14:32:05 yesterday before the bad migration ran") — optimal RPO. Logical snapshots survive Supabase outages (the dump is in S3, not on Supabase infrastructure) and are portable to any Postgres installation — survivability if the provider itself has a problem.

**Backup encryption:** `pg_dump` output is encrypted with AES-256 before upload using a key stored in the secret manager. The encryption key itself is backed up separately from the data — both are needed to restore.

### 11.2 Redis

Redis persistence is configured as `AOF` (Append-Only File, `appendfsync everysec`) with an additional `BGSAVE` RDB snapshot every 15 minutes. These are stored in a PersistentVolume (backed by the cloud provider's block storage) that survives pod restarts.

**Backup strategy:** daily S3 copy of the RDB snapshot. However, Redis is a cache and session store — a Redis restore from backup is almost never the right recovery path (applications simply rebuild their cache on startup). Backup exists for audit purposes and the unusual case of a persistent queue (Celery) having un-processed tasks that need recovery.

### 11.3 Object Storage (S3 / Supabase Storage)

S3 is configured with:
- **Versioning enabled** on the primary bucket — deleted or overwritten recordings can be recovered.
- **Cross-region replication** to the secondary region bucket — RPO near-zero for storage objects.
- **Lifecycle policy:** recordings → Glacier/cold tier after 90 days (configurable per tenant based on retention policy `FR-COMPLY-001`).

### 11.4 Restore Test Schedule

Backups that are never tested are backups that may not work when needed. A monthly automated restore drill runs in an isolated Kubernetes namespace: it restores the previous day's Postgres snapshot into a fresh database, runs the full integration test suite against it, and posts the result to a monitoring dashboard. A failed drill pages the on-call engineer.

---

## 12. Multi-Region Architecture

### 12.1 Active-Passive at Launch — Active-Active as Phase 2

```mermaid
flowchart TB
    subgraph R1["Region 1 — Primary (Active)"]
        K8s1[Kubernetes Cluster]
        DB1[(Supabase Postgres Primary)]
        Redis1[(Redis Cluster)]
        S3_1[(S3 Primary Bucket)]
    end
    subgraph R2["Region 2 — Secondary (Passive)"]
        K8s2[Kubernetes Cluster — scaled down, warm standby]
        DB2[(Supabase Postgres Read Replica)]
        Redis2[(Redis Replica — cold standby)]
        S3_2[(S3 Replica Bucket — replication enabled)]
    end
    CDN[CDN — routes to nearest healthy region]
    Users((Users / Telephony Providers))

    Users --> CDN
    CDN -->|primary traffic| K8s1
    CDN -.->|failover only| K8s2
    DB1 -->|WAL replication| DB2
    S3_1 -->|CRR| S3_2
```

**Phase 1 (Launch):** Single active region. Secondary region runs warm-standby Kubernetes cluster with 0 replicas (or minimum 1 per deployment for fast scale-up). Failover is manual — a runbook-driven DNS/CDN switch plus a `kubectl scale` command to bring the secondary cluster to full capacity.

**Phase 2 (When warranted):** Active-active with read workloads served from the nearest region (analytics queries, admin console), write workloads routed to the primary region's Postgres. True active-active for write workloads requires multi-master Postgres (e.g., Citus or a cloud-native multi-region DB) — deferred until write throughput justifies the complexity and cost.

### 12.2 Failover Decision Tree

```mermaid
flowchart TD
    Alert[Prometheus alert: region health < threshold] --> IsAuto{Automatic failover configured?}
    IsAuto -->|No| Page[Page on-call engineer]
    Page --> Assess{Primary recoverable < 10 min?}
    Assess -->|Yes| Wait[Wait and monitor]
    Assess -->|No| Failover
    IsAuto -->|Yes — future Phase 2| Failover
    Failover --> DNS[Update CDN/DNS to point to secondary]
    DNS --> ScaleUp[kubectl scale deployments to full capacity in R2]
    ScaleUp --> PromoteDB[Promote R2 Postgres replica to primary]
    PromoteDB --> Smoke[Run smoke tests against R2]
    Smoke --> Notify[Notify engineering team + status page]
```

### 12.3 RTO / RPO by Region Failure

| Failure scope | RTO (Phase 1) | RPO (Phase 1) | RTO (Phase 2) |
|---|---|---|---|
| AZ failure within region | < 5 min | 0 | < 5 min |
| Full region failure | < 30 min (manual runbook) | < 5 min (WAL lag) | < 2 min (automated) |

---

## 13. CDN

### 13.1 What Is CDN-Served and What Is Not

| Asset | CDN-served? | Rationale |
|---|---|---|
| Next.js static assets (`/_next/static/`) | Yes | Immutable, content-hash filenames — infinite cache TTL |
| Next.js pages (RSC / HTML) | Yes, short TTL (60s) | Reduces origin load for public pages; private dashboard pages skip CDN with `Cache-Control: private` |
| API REST responses | No | Tenant-scoped, auth-gated — CDN caching of API responses risks cross-tenant leakage |
| Call recordings (S3) | Yes, via signed CDN URLs | Large binary files with access control; signed URLs expire (15 min) and are generated per-request by the API |
| WebSocket (Voice Gateway) | No | WebSocket upgrades are not CDN-terminatable |

### 13.2 CDN Configuration

```
Cache-Control headers set by Next.js:
  /_next/static/*         → max-age=31536000, immutable
  /                       → no-cache (RSC)
  /api/*                  → no-store (never CDN-cached)

CDN rules:
  - Forward X-Forwarded-For to origin (real IP preserved for rate limiting)
  - Block: known-bad bot user agents (WAF rule)
  - Block: requests with >10 query parameters (WAF rule — parameter pollution)
  - Block: requests with abnormally large headers (WAF rule)
  - Pass: all WebSocket upgrade headers untouched to NGINX ingress
```

---

## 14. Networking

### 14.1 Cluster Network Architecture

```mermaid
flowchart TB
    Internet((Internet))
    CloudLB["Cloud L4 Load Balancer
    TCP passthrough — TLS at NGINX"]
    NGINX["NGINX Ingress (DaemonSet)
    TLS termination, rate limiting"]
    subgraph AppNS["app namespace"]
        API[API pods]
        VG[Voice Gateway pods]
        Web[Next.js pods]
        Worker[Worker pods]
    end
    subgraph DataNS["data namespace"]
        Redis[Redis Cluster]
    end
    subgraph External["External Services"]
        Supabase[(Supabase Postgres)]
        S3[(AWS S3)]
        Providers[STT/TTS/LLM/Telephony APIs]
    end

    Internet --> CloudLB
    CloudLB --> NGINX
    NGINX --> API & VG & Web
    API & VG & Worker -->|private subnet egress| Supabase & S3 & Providers
    API & VG & Worker -->|ClusterIP| Redis
```

### 14.2 Egress Control

All outbound traffic from pods to external services exits via a dedicated NAT gateway per availability zone (static egress IP). This provides:
- A predictable source IP that can be allowlisted with telephony/STT/TTS/LLM providers.
- A single place to enforce egress firewall rules (block unexpected outbound destinations).
- Per-AZ redundancy — one NAT gateway failure does not affect pods in other AZs.

### 14.3 DNS

Internal DNS: Kubernetes CoreDNS resolves `service.namespace.svc.cluster.local` for pod-to-pod communication. Services reference each other by service name only (e.g., `redis.data.svc.cluster.local:6379`).

External DNS: an ExternalDNS controller watches Ingress resources and automatically creates/updates DNS records in the cloud provider's DNS service when an Ingress is created or its host changes — no manual DNS management.

---

## 15. Database Scaling

### 15.1 Supabase PostgreSQL — Connection Management

At "tens of thousands of concurrent calls" (`NFR-SCALE-001`), the number of Postgres connections from application pods grows rapidly — each pod's SQLAlchemy `AsyncSession` pool maintains connections. Postgres's process-per-connection model means connections are the primary bottleneck before CPU or storage.

**PgBouncer (connection pooler):** Supabase provides a built-in PgBouncer. All application pods connect to PgBouncer (port 5432 transaction-mode pool), not directly to Postgres. PgBouncer maintains a small pool of server-side connections (typically 20–50 per shard) and multiplexes thousands of application-side connections onto them.

```python
# platform/infrastructure/db/engine.py
engine = create_async_engine(
    settings.database.url,          # points to PgBouncer, not Postgres directly
    pool_size=10,                   # per-pod pool toward PgBouncer
    max_overflow=5,
    pool_pre_ping=True,
    pool_recycle=1800,              # recycle connections every 30 min (avoids stale conn issues with pgbouncer)
)
```

### 15.2 Read Replicas

Supabase supports read replicas in the same region. The platform routes these queries to a read-replica connection string:

| Query type | Routes to | How |
|---|---|---|
| Write (INSERT/UPDATE/DELETE) | Primary | Default `DATABASE__URL` |
| CQRS read model queries (§3C/3D/3E) | Read replica | `DATABASE__READ_URL` setting |
| Analytics projection queries | Read replica | Same |
| Per-turn Orchestrator reads (session, prompt) | Primary (Redis cache usually hits first) | Staleness risk too high for a replica |

The read vs. write session factory is a 3A infrastructure concern — `db/session.py` exposes `get_read_session()` and `get_write_session()` that the DI container binds appropriately.

### 15.3 Table Partitioning (Phase 5 Pre-Design)

High-volume tables expected to need partitioning at scale — defined here so Phase 5 (Database Design) builds them partitioned from the start rather than migrating later:

| Table | Partition key | Strategy |
|---|---|---|
| `call_sessions` | `started_at` | Range (monthly) — most queries filter by recent date |
| `turns` | `started_at` | Range (monthly) — aligned with `call_sessions` |
| `usage_records` | `recorded_at` | Range (monthly) — billing period aligned |
| `audit_events` | `occurred_at` | Range (monthly) — compliance query aligned |
| `campaign_leads` | `campaign_id` | List — queries almost always filter by campaign |
| `document_chunks` | `knowledge_base_id` | List — RAG queries always filter by KB |

### 15.4 Index Strategy Principles (Pre-Design for Phase 5)

- Every foreign key that is used in a join has an index.
- Every `tenant_id` column is covered by a composite index `(tenant_id, <primary_sort_column>)`.
- `document_chunks.embedding` uses a pgvector HNSW index with a partial index on `(tenant_id, knowledge_base_id)` — per 3D §9.4's design.
- Indexes on high-cardinality filter columns (`status`, `direction`) are partial (e.g., `WHERE status = 'ACTIVE'`) to stay small.
- `BRIN` indexes on monotonically-increasing `created_at` columns (append-only tables like `audit_events`) instead of B-tree — dramatically smaller for time-series-like data.

---

## 16. Redis Scaling

### 16.1 Redis Cluster Mode

At "tens of thousands of concurrent voice sessions" scale, a single Redis instance is both a performance bottleneck and a single point of failure. Redis Cluster (native sharding + replication) is used in production:

```
Cluster topology (minimum production):
  - 3 primary shards
  - 3 replicas (1 per primary)
  - Keyslot assignment: automatic (Redis Cluster hash slots)
  - Automatic failover: replica promoted on primary failure in < 30s
```

Deployed via the Helm chart `infra/helm/redis/values.yaml` with `architecture: cluster`.

### 16.2 Key Space Namespacing and Cluster Compatibility

Redis Cluster routes keys to shards by `{hash tag}` — curly-brace-enclosed portion of the key. All Redis keys defined in 3B §16, 3C §10, and 3E §16 use `{tenant_id}` as the hash tag:

```
session:{tenant_id}:{call_id}          → hash tag is tenant_id
campaign:queue:{tenant_id}:{campaign_id} → hash tag is tenant_id
rbac:permissions:{tenant_id}:{user_id}  → hash tag is tenant_id
```

This ensures all keys for one tenant land on the same shard — cross-shard operations (`MULTI/EXEC` transactions, `EVAL` scripts) are not needed, since all operations touching the same tenant's data go to the same slot. **This is a design constraint that must be honoured when any new Redis key is introduced** — the namespacing convention in 3A §6.3's Redis wrapper enforces this by constructing keys with `{tenant_id}` as the first `{}` segment.

### 16.3 Redis Memory Management

| Key space | Eviction policy | TTL enforced by |
|---|---|---|
| Session state (`session:*`) | `allkeys-lru` | Application (explicit TTL set on write) |
| RBAC/API key cache | `volatile-lru` | Application (TTL set on write) |
| Queue keys (`campaign:queue:*`) | `noeviction` — queue data must not be silently dropped | No TTL — cleared by application on completion |
| Retry queue (`campaign:retry_queue:*`) | `noeviction` | No TTL — members removed by `ZREM` when due |

**`noeviction` on queue keys** with a hard memory limit alarm: if Redis memory exceeds 80% of limit, an alert pages on-call before it reaches the eviction threshold. The alternative (allowing eviction on queue keys) would silently drop campaign leads — an undetectable data loss.

---

## 17. Monitoring (Infrastructure Layer)

Extends 3E §14's application-layer monitoring with infrastructure-level concerns.

### 17.1 Infrastructure Metrics

| Metric | Source | Alert threshold |
|---|---|---|
| Node CPU utilisation | kubelet | > 80% sustained 5m → scale up |
| Node memory utilisation | kubelet | > 85% → alert |
| Pod restart count | kube-state-metrics | > 3 restarts in 10m → alert |
| PVC utilisation | kubelet | > 80% → alert (Redis AOF, Prometheus TSDB) |
| Redis memory utilisation | Redis exporter | > 80% → alert |
| Redis cluster OK | Redis exporter | `redis_cluster_state != 1` → critical alert |
| Postgres connections (via pgBouncer) | pgBouncer exporter | Active connections > 80% of max pool → alert |
| Certificate expiry | cert-manager | < 14 days remaining → alert |
| Ingress 5xx rate | NGINX exporter | > 1% of requests → alert |

### 17.2 Alertmanager Routing

```yaml
# infra/prometheus/alertmanager.yaml
route:
  group_by: [alertname, tenant_id, service]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: slack-default
  routes:
    - match: { severity: critical }
      receiver: pagerduty-critical
      group_wait: 0s          # no wait for critical
    - match: { severity: warning }
      receiver: slack-warnings
    - match: { alertname: VoiceTurnLatencyP50Breach }
      receiver: pagerduty-critical   # voice SLO breach is always critical

receivers:
  - name: pagerduty-critical
    pagerduty_configs:
      - routing_key: ${PAGERDUTY_KEY}
  - name: slack-warnings
    slack_configs:
      - api_url: ${SLACK_WEBHOOK_URL}
        channel: "#infra-alerts"
```

---

## 18. Logging

### 18.1 Log Pipeline

```mermaid
flowchart LR
    Pods["All Pods — structlog JSON to stdout"] --> FluentBit
    FluentBit["Fluent Bit DaemonSet
    (one per node)
    parse + tag + buffer"] --> Backend
    Backend{"Log Backend"}
    Backend --> CloudLogs["Cloud Provider Logs
    (primary — 30 day retention)"]
    Backend --> S3Logs["S3 Cold Storage
    (90 day — compliance)"]
```

**Why stdout, not file-based logging:** Kubernetes collects container stdout/stderr automatically via the container runtime. Fluent Bit then reads the raw JSON lines from the container log files on the node (not via a sidecar per pod — DaemonSet mode is more resource-efficient at scale). The application never manages log files or rotation — that is entirely the infrastructure's job.

### 18.2 Fluent Bit Configuration

```ini
[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Multiline.Parser  cri
    Tag               kube.*

[FILTER]
    Name   kubernetes
    Match  kube.*
    Merge_Log On         # parse JSON log lines into structured fields
    Keep_Log Off

[FILTER]
    Name  grep
    Match kube.*
    Exclude log .*healthcheck.*    # suppress /health/live noise

[OUTPUT]
    Name  cloudwatch_logs
    Match kube.*
    region ${AWS_REGION}
    log_group_name platform-production
    log_stream_prefix kube/
    auto_create_group On
```

### 18.3 Log Retention and PII

Retention periods:

| Log class | Hot retention | Cold retention (S3) |
|---|---|---|
| Application logs | 30 days (cloud) | 90 days |
| Audit events | 1 year (Postgres) | 7 years (S3 — compliance) |
| Infrastructure logs (node, NGINX) | 14 days (cloud) | 30 days |
| Security-relevant (auth, RBAC denial) | 90 days (cloud, fast queryable) | 2 years |

PII protection at the log pipeline level: a Fluent Bit `lua` filter applies a regex-based masking pass over log lines before they leave the node — phone numbers, email addresses, and JWT tokens are replaced with `[REDACTED]`. This is a defence-in-depth supplement to the application-level masking in 3A §12.4 — it catches any PII that slips through at the application layer.

---

## 19. Tracing

### 19.1 OpenTelemetry Collector (Cluster-Wide)

The OTel Collector runs as a Deployment (not DaemonSet) in the `observability` namespace — it is not on the per-request hot path; pods export spans via gRPC to the collector asynchronously in batches.

```yaml
# infra/helm/otel-collector/values.yaml (abbreviated)
config:
  receivers:
    otlp:
      protocols:
        grpc: { endpoint: 0.0.0.0:4317 }
  processors:
    batch:
      timeout: 5s
      send_batch_size: 1024
    resource:
      attributes:
        - key: deployment.environment
          value: production
          action: insert
    redaction:                          # strip PII from span attributes
      allow_all_keys: true
      blocked_values:
        - "phone_number|email|token|password|secret"
  exporters:
    otlp/tempo:
      endpoint: tempo.observability:4317   # Grafana Tempo backend
    prometheus:
      endpoint: 0.0.0.0:8889              # expose as Prometheus metrics for HPA
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch, resource, redaction]
        exporters: [otlp/tempo]
      metrics:
        receivers: [otlp]
        processors: [batch]
        exporters: [prometheus]
```

**Grafana Tempo** is the trace backend — it integrates with Grafana for trace-to-metrics and trace-to-log correlation (clicking a trace point in Grafana opens the correlated log lines from the same `correlation_id`).

### 19.2 Trace Sampling

100% sampling in staging (every request traced). In production, **adaptive sampling**:

- Voice call traces: 100% sampled — every call is auditable.
- API requests: 10% baseline, escalating to 100% for any request that results in a 5xx status or exceeds the p99 latency threshold.
- Celery tasks: 25% baseline.

Implemented via the OTel SDK's `ParentBasedTraceIdRatioBased` sampler at the application layer, with a tail-based sampler at the Collector layer that upgrades any trace containing an error span to 100% regardless of head-sampling decision.

---

## 20. Health Checks

### 20.1 Application-Level Health Checks (From 3E §14.6)

| Endpoint | Response | Kubernetes use |
|---|---|---|
| `GET /health/live` | `200 {"status":"ok"}` unconditionally | Liveness probe — restart if fails 3× |
| `GET /health/ready` | `200` only if Postgres+Redis reachable and migrations current | Readiness probe — remove from LB if fails 2× |

**Why separate liveness and readiness:** a pod that has started but whose database connection pool is temporarily exhausted should not be restarted (liveness) — it should simply be temporarily removed from the load balancer (readiness) until the pool recovers. If liveness and readiness were the same check, a temporary DB outage would trigger a cascade of pod restarts that make the DB pool exhaustion worse, not better.

### 20.2 Startup Probe

```yaml
startupProbe:
  httpGet: { path: /health/ready, port: 8000 }
  failureThreshold: 30
  periodSeconds: 5        # 30 × 5s = 150s max startup time before considered failed
```

The startup probe gives newly launched pods up to 150 seconds to become ready (Alembic checks, connection pool warm-up) before the liveness probe kicks in. Without a startup probe, the liveness probe's `initialDelaySeconds` is a guess — too short causes restarts during slow startup, too long delays detection of a truly broken pod.

### 20.3 External Synthetic Monitoring

Beyond Kubernetes probes (which only verify that the pod is alive from inside the cluster), an external synthetic monitor (e.g., UptimeRobot, Better Uptime, or a cloud-provider uptime check) polls `https://api.platform.example.com/health/ready` every 60 seconds from outside the cluster. This catches scenarios where the pods are healthy but NGINX or the cloud load balancer is the failing component — invisible to Kubernetes probes.

### 20.4 Voice Pipeline Synthetic Call

A scheduled Celery task (every 5 minutes, in production) places a synthetic outbound call to a dedicated test phone number using a test agent. The call exercises the full stack: telephony → gateway → STT → LLM → TTS → hang up. The result (answered/failed, duration, per-stage latency) is recorded as a synthetic metric in Prometheus. An alert fires if the synthetic call fails two consecutive times — this catches voice pipeline degradation that generic HTTP health checks cannot detect.

---

## 21. Deployment Strategy

### 21.1 Environment Progression

```mermaid
flowchart LR
    Dev[Developer laptop
    docker-compose] -->|PR merge to staging branch| Staging
    Staging[Staging cluster
    rolling update, auto-deploy] -->|Manual approval gate| Production
    Production[Production cluster
    blue-green deploy]
```

**Why a manual approval gate before production:** the platform handles live phone calls with real tenants. An automated staging-to-production pipeline with no gate would deploy a regression to production before anyone has verified staging behaviour. The GitHub Environments feature provides the gate — a designated reviewer approves the deployment workflow run after reviewing the staging smoke test results.

### 21.2 Blue-Green Deployment (Production)

```mermaid
flowchart TB
    subgraph Cluster["Production Kubernetes Cluster"]
        LB["platform-active Service
        (selector: slot=blue OR slot=green)"]
        subgraph Blue["Blue Slot"]
            API_B[api-blue Deployment - v1]
            VG_B[voice_gateway-blue - v1]
            W_B[worker-blue - v1]
        end
        subgraph Green["Green Slot"]
            API_G[api-green Deployment - v2]
            VG_G[voice_gateway-green - v2]
            W_G[worker-green - v2]
        end
    end

    LB -->|100% traffic| Blue
    LB -.->|0% — standby| Green
```

**Deploy sequence:**
1. Identify the inactive slot (whichever of blue/green is not serving live traffic).
2. Deploy new image to inactive slot — `kubectl apply -k overlays/production/green` (or blue).
3. Wait for all inactive-slot pods to pass readiness probes.
4. Run smoke tests against the inactive slot directly (via a separate internal service, bypassing `platform-active`).
5. **Atomic traffic switch:** `kubectl patch service platform-active --patch '{"spec":{"selector":{"slot":"green"}}}'` — this is a single Kubernetes API call, effectively instantaneous.
6. Monitor error rate and p50 latency for 5 minutes via Prometheus alerts.
7. If monitoring passes: retain old slot for 1 hour (instant rollback available), then scale it down.
8. If monitoring fails: **rollback** is `kubectl patch service platform-active ... slot=blue` — under 10 seconds.

**Why blue-green over canary for this workload:** canary (gradually shifting traffic percentage) is optimal for stateless HTTP workloads. This platform has a stateful component — WebSocket voice calls are pinned to the pod/slot they started on (3B §8). If 10% of traffic goes to the new slot and a call starts there, it stays there for its duration regardless of the traffic split. A buggy new version affecting only 10% of *new* calls but 10% of all *calls* (including long-running ones that started in the canary) is hard to attribute cleanly. Blue-green's hard boundary (all *new* connections go to the new slot, all *existing* connections stay on the old slot) is the correct model for WebSocket-pinned workloads.

**Voice Gateway-specific blue-green handling:** the `preStop` hook on Voice Gateway pods prevents the old slot from being scaled down while calls are active — it checks `platform_active_calls` for that pod and delays the SIGTERM until zero. The 1-hour "retain old slot" window before scale-down covers even the longest expected calls.

### 21.3 Database Migration Policy

| Migration type | Procedure | Rollback |
|---|---|---|
| Additive (new table, new nullable column, new index) | Run before deploy — safe with old and new code simultaneously | Drop the added object |
| Column rename | Two-step: (1) add new column + backfill + dual-write; (2) next deploy drops old column | Revert dual-write code |
| Breaking (drop column, change type, remove constraint) | Only after the old code reading that column is fully deployed everywhere | Restore from backup if caught late |

**Never run a breaking migration while old code is in production.** The blue-green slot switch means old and new code can coexist for the duration of the switch (minutes) — both versions of the application must be compatible with the post-migration schema during that window.

### 21.4 Rollback Strategy

| Rollback type | Mechanism | Time to effect |
|---|---|---|
| Application code (blue-green) | `kubectl patch service platform-active` to previous slot | < 10 seconds |
| Application code (staging rolling update) | `kubectl rollout undo deployment/api` | < 2 min (Kubernetes reverts to previous ReplicaSet) |
| Database schema (additive migration) | Drop added objects via Alembic downgrade script | 1–5 min |
| Database schema (destructive migration) | PITR restore to pre-migration point (§11.1) | < 4 hours |
| Secrets rotation (bad rotation) | Restore previous secret version in secret store; ESO picks up on next reconcile | < 5 min (ESO reconcile interval) |

---

## 22. Complete Infrastructure Checklist — Production Readiness

The following must all be true before the first production tenant onboards. This list operationalises the deployment requirements across the full Phase 3 LLD:

| Category | Requirement | Source |
|---|---|---|
| Containers | All images built from multi-stage Dockerfiles; non-root user; no dev dependencies in runtime layers | §3 |
| Containers | Image vulnerability scan passes (no CRITICAL/HIGH CVEs) | §6.3 |
| Kubernetes | All pods have liveness, readiness, and startup probes | §20 |
| Kubernetes | All pods have CPU/memory requests and limits | §5.2 |
| Kubernetes | PodDisruptionBudgets applied to all critical workloads | §5.3 |
| Kubernetes | NetworkPolicy applied: default deny + explicit allow rules | §5.4 |
| Kubernetes | topologySpreadConstraints applied: pods spread across AZs | §5.2 |
| Kubernetes | terminationGracePeriodSeconds correct for each workload | §5.2 |
| Scaling | HPA applied to all three primary workloads (api, voice_gateway, worker) | §9.1 |
| Scaling | Cluster autoscaler configured with per-workload node pools | §9.2 |
| Secrets | No credentials in source control (gitleaks in CI) | §7.3 |
| Secrets | All secrets sourced from secret manager via ESO | §7.1 |
| Secrets | Secret rotation schedule defined and implemented | §7.2 |
| Security | NGINX rate limiting configured for API and WS | §8.4 |
| Security | TLS on all external endpoints; cert-manager auto-renewal active | §8.2 |
| Security | PII masking in logs (application layer + Fluent Bit filter) | §18.3 |
| Observability | Prometheus scraping all pods | §17 |
| Observability | All alert rules loaded; Alertmanager routes confirmed | §17.2 |
| Observability | Grafana dashboards provisioned from code | §14.3 (3E) |
| Observability | OTel Collector receiving and exporting traces | §19 |
| Observability | Synthetic voice call monitor active | §20.4 |
| Observability | External HTTP uptime monitor active | §20.3 |
| Deployment | Blue-green slots both operational; switch script tested | §21.2 |
| Deployment | Database migration pipeline runs before app deploy in CI | §6.2 |
| Backup | Postgres PITR enabled; daily snapshot to S3 | §11.1 |
| Backup | Backup restore drill scheduled and first run verified | §11.4 |
| Disaster Recovery | Multi-AZ pod distribution verified | §10.2 |
| DR | Regional failover runbook documented and tested in staging | §10 |
| Multi-Region | Secondary region warm-standby cluster operational | §12.1 |
| Multi-Region | S3 cross-region replication enabled | §11.3 |
| CDN | Static asset caching configured; API endpoints excluded | §13 |

---

## 23. Open Items for Phase 22 (Deployment) and Phase 24 (Implementation)

| Item | Needed from | Feeds into |
|---|---|---|
| Primary cloud provider selection (Review Note 1) | Product/Architecture | Kubernetes hosting choice, secret manager, NAT gateway, load balancer specifics |
| Secret manager vendor (Review Note 5) | Architecture sign-off | `SecretsProvider` adapter implementation (3A §6.3) |
| ClickHouse activation trigger definition (Review Note 1 from 3E) | Product | Phase 22 capacity planning, `AnalyticsWritePort` adapter switch |
| Active-active multi-region timeline (Review Note 3) | Product/Architecture | Phase 22 — whether Citus/multi-master Postgres needs to be designed |
| Automated failover vs. manual runbook for regional failure | Architecture sign-off | Phase 22 and DR runbook authoring |
| Log aggregation backend vendor (CloudWatch vs. Elasticsearch vs. Loki) | Architecture | Fluent Bit output config, Grafana data source |
| Grafana Tempo vs. Jaeger as trace backend | Architecture | OTel Collector exporter config |
| KEDA vs. Prometheus Adapter for custom HPA metrics | Architecture | `platform_active_calls` metric wiring for Voice Gateway HPA |

**This completes Phase 3 (Low-Level Design) in full across all sub-phases 3A–3F.** The full Phase 3 LLD corpus covers: Platform Foundation (3A), Voice Platform (3B), CRM & Campaigns (3C), Workflow/RAG/LLM (3D), Platform Services (3E), and Deployment Internals (3F). All six documents are now ready for Phase 4 (Domain-Driven Design) review.
