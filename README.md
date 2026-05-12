# Banking Peak Load Management Prototype

[![CI](https://github.com/ahargunyllib/banking-peak-load-prototype/actions/workflows/ci.yaml/badge.svg)](https://github.com/ahargunyllib/banking-peak-load-prototype/actions/workflows/ci.yaml)

A university prototype demonstrating defense-in-depth scalability for banking peak load — simulating CIMB Niaga's problem of 1M transactions/hour causing crashes, 10s latency, and cost spikes.

## Problem Statement

A major bank experiences system crashes during peak load. Root causes: no load shedding or backpressure, database connection exhaustion, heavy queries without caching, and reactive (not proactive) scaling. This prototype shows how layered protection mechanisms bring the system from >80% error rate and >5s p95 latency down to <0.1% errors and <10ms p95 latency.

## Architecture

Defense-in-depth: four protection layers between client and database. Each layer reduces load on the layer below it.

```
Client
  │
  ▼
┌──────────────────────────┐
│  Layer 1: Rate Limiter   │  Token bucket per client IP
│  (middleware)            │  Reject early → HTTP 429
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│  Layer 2: Circuit Breaker│  Monitor downstream health
│  (middleware)            │  Fail-fast → HTTP 503
└────────┬─────────┬───────┘
         │         │
       READ      WRITE
         │         │
         ▼         ▼
┌────────────┐ ┌──────────┐
│ Layer 3a:  │ │Layer 3b: │
│ Redis Cache│ │  Queue   │
│ (cache-    │ │(producer)│
│  aside)    │ │          │
└─────┬──────┘ └────┬─────┘
      │              │
      ▼              ▼
┌──────────┐  ┌────────────┐
│ Read     │  │  Worker    │
│ Replica  │  │ (consumer) │
└─────┬────┘  └─────┬──────┘
      │              │
      ▼              ▼
┌──────────────────────────┐
│  Layer 4: PostgreSQL     │
│  (via PgBouncer)         │
│  Primary: writes only    │
│  Replica: reads only     │
└──────────────────────────┘
```

**Read path:** Rate limit → Circuit breaker → Redis cache lookup → (miss) Read replica via PgBouncer → cache + return

**Write path (optimized):** Rate limit → Circuit breaker → Validate → Publish to queue → HTTP 202. Worker: check balance → debit/credit → commit → invalidate cache

**Write path (baseline):** Synchronous DB transaction → HTTP 201

## Tech Stack

| Component | Technology |
| --- | --- |
| Language | Go 1.25 |
| HTTP Router | Echo |
| Database | PostgreSQL 16 + PgBouncer (transaction pooling) |
| Cache | Redis 7 |
| Message Queue | RabbitMQ |
| Observability | Prometheus + Grafana |
| Load Testing | k6 |
| Infrastructure | Kubernetes (K8s) + Docker Compose |

## API Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/api/v1/transactions` | Create transaction (async via queue when enabled) |
| `GET` | `/api/v1/transactions/:id/status` | Transaction status inquiry |
| `GET` | `/api/v1/accounts/:id/balance` | Account balance inquiry |

## Feature Flags

All protection/optimization layers are toggled via environment variables. Baseline = all off. Optimized = all on.

| Variable | Default | Description |
| --- | --- | --- |
| `CACHE_ENABLED` | `false` | Redis cache for read path |
| `QUEUE_ENABLED` | `false` | Async write via message queue |
| `RATE_LIMIT_ENABLED` | `false` | Token bucket rate limiting |
| `CIRCUIT_BREAKER_ENABLED` | `false` | Fail-fast on unhealthy downstream |
| `DB_READ_REPLICA_ENABLED` | `false` | Route reads to replica |

See [Development Guide](docs/development.md) for the full environment variable reference.

## Quick Start

### Option A: Docker Compose (Local Development)

**Prerequisites:** Go 1.25, Docker & Docker Compose v2, k6, Make

```bash
# Install Go tooling
make init

# --- Baseline (API + PostgreSQL only) ---
cp .env.baseline.example .env
docker compose up -d
k6 run scripts/load-test/baseline.js

# --- Optimized (+ Redis, RabbitMQ, read replica) ---
cp .env.optimized.example .env
docker compose --profile optimized up -d
k6 run scripts/load-test/optimized.js

# --- Full stack (+ Prometheus, Grafana) ---
docker compose --profile optimized --profile observability up -d
# Grafana: http://localhost:3000
# Prometheus: http://localhost:9090
```

### Option B: Kubernetes (Recommended)

**Prerequisites:** kubectl, minikube (or any K8s cluster), k6, Make

```bash
# 1. Start cluster
minikube start

# 2. Apply all manifests
kubectl apply -f deployments/k8s/

# 3. Wait until all pods ready
kubectl get pods -n banking -w

# 4. Seed dummy data (requires port-forward)
kubectl port-forward deployment/postgres -n banking 5432:5432 &
make seed

# 5. Run load test
k6 run scripts/load-test/optimized.js
```

**Access services:**

```bash
# Application
minikube service banking-app -n banking

# Grafana dashboard
kubectl port-forward deployment/grafana -n banking 3000:3000

# Prometheus
kubectl port-forward deployment/prometheus -n banking 9090:9090
```

**Shutdown:**

```bash
kubectl scale deployment banking-app pgbouncer postgres redis rabbitmq prometheus grafana --replicas=0 -n banking
minikube stop
```

## Demo Steps

**Prerequisites:** minikube, kubectl, k6, Make — make sure all are installed.

```bash
# 1. Start cluster
minikube start

# 2. Apply all manifests (safe to re-run)
kubectl apply -f deployments/k8s/

# 3. Scale up all deployments
kubectl scale deployment banking-app pgbouncer postgres redis rabbitmq prometheus grafana --replicas=1 -n banking
kubectl scale deployment banking-app --replicas=3 -n banking

# 4. Wait until all pods are Running
kubectl get pods -n banking -w
```

Open **4 separate terminals** for monitoring and demo:

```bash
# Terminal 1 — Grafana dashboard
kubectl port-forward svc/grafana 3000:3000 -n banking
# Open http://localhost:3000

# Terminal 2 — Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n banking
# Open http://localhost:9090

# Terminal 3 — Watch auto-scaling live
kubectl get hpa -n banking -w

# Terminal 4 — Watch pods live
kubectl get pods -n banking -w
```

Run load test:

```bash
# Get application URL
minikube service banking-app -n banking --url

# Run load test
k6 run scripts/load-test/optimized.js
```

**If data is missing (account not found / insufficient funds):**

```bash
# Port-forward postgres
kubectl port-forward deployment/postgres -n banking 5432:5432

# Seed data
make seed
```

**Shutdown after demo:**

```bash
kubectl scale deployment banking-app pgbouncer postgres redis rabbitmq prometheus grafana --replicas=0 -n banking
minikube stop
```

**Resume next session:**

```bash
minikube start
kubectl scale deployment banking-app pgbouncer postgres redis rabbitmq prometheus grafana --replicas=1 -n banking
kubectl scale deployment banking-app --replicas=3 -n banking
kubectl get pods -n banking -w  # wait until all Running before proceeding
```

## Kubernetes Infrastructure

The `deployments/k8s/` folder contains all manifests:

| File | Description |
| --- | --- |
| `secret.yaml` | DB credentials (base64 encoded) |
| `configmap.yaml` | App configuration & feature flags |
| `app.yaml` | Banking app deployment + NodePort service |
| `hpa.yaml` | Horizontal Pod Autoscaler (2–15 replicas, CPU 50%) |
| `pgbouncer.yaml` | PgBouncer connection pooler (2 replicas, pool size 50) |
| `postgres.yaml` | PostgreSQL with tuned parameters & PVC |
| `redis.yaml` | Redis cache (LRU, 256MB) |
| `rabbitmq.yaml` | RabbitMQ message broker |
| `prometheus.yaml` | Metrics collection |
| `grafana.yaml` | Metrics visualization dashboard |

## Makefile Commands

| Command | Description |
| --- | --- |
| `make init` | Download Go modules and install dev tools (air, golangci-lint) |
| `make dev` | Start server with live reload (air) |
| `make lint` | Run golangci-lint |
| `make test` | Run unit tests (`go test -v ./...`) |
| `make build` | Compile binary to `bin/app` |
| `make seed` | Seed dummy data to database (100K accounts, 1M transactions) |

## Docker Compose Profiles

| Command | Services |
| --- | --- |
| `docker compose up` | API + PostgreSQL (baseline) |
| `docker compose --profile optimized up` | + Redis, RabbitMQ, read replica |
| `docker compose --profile observability up` | + Prometheus, Grafana |
| `docker compose --profile optimized --profile observability up` | Full stack |

## Load Test Results

Results from k6 load test simulating banking peak load (~1000 VUs, ~562 req/s):

| Metric | Before PgBouncer | After PgBouncer | After Full Tuning | Target |
| --- | --- | --- | --- | --- |
| p(95) Latency | 5s | 2.2s | **5.18ms** | < 1000ms ✅ |
| HTTP Fail Rate | 82.42% | 15.04% | **0.04%** | < 1% ✅ |
| Success Rate | 12.56% | 74.24% | **99.95%** | > 99% ✅ |
| Throughput | ~562 req/s | ~562 req/s | ~562 req/s | — |

Estimated capacity: **~2,000,000 requests/hour** (exceeds 1M transactions/hour target).

Root cause of original failures: **PostgreSQL connection exhaustion** — without PgBouncer, 1000+ VUs each opened direct DB connections, exceeding `max_connections`. Fixed by:
1. PgBouncer transaction-mode pooling (1000+ clients → 50 DB connections)
2. Go `database/sql` pool tuning (`SetMaxOpenConns(20)`, `SetMaxIdleConns(10)`)
3. PostgreSQL parameter tuning (`max_connections=200`, `shared_buffers=512MB`)
4. HPA scale-up behavior tuning (faster pod provisioning under load)

## SLO Targets

| Metric | Baseline | Optimized | Achieved |
| --- | --- | --- | --- |
| p95 Latency | > 5s | < 1s | **5.18ms** ✅ |
| Error Rate at peak | > 80% | < 1% | **0.04%** ✅ |
| Success Rate | < 15% | > 99% | **99.95%** ✅ |
| Estimated Capacity | ~100K req/hr | > 1M req/hr | **~2M req/hr** ✅ |

## Project Structure

```
banking-peak-load-prototype/
├── cmd/
│   ├── server/main.go         # Entry point
│   └── seeds/main.go          # Data seeder
├── internal/
│   ├── config/                # Env-based configuration
│   ├── domain/                # Domain models (account, transaction)
│   ├── handler/               # HTTP handlers
│   ├── infrastructure/        # DB, Redis, Queue clients
│   ├── middleware/            # Rate limiter, circuit breaker, logging
│   ├── repository/            # DB access + cache-aside logic
│   ├── service/               # Business logic
│   └── worker/                # Queue consumer worker
├── migrations/                # SQL migrations
├── scripts/
│   └── load-test/             # k6 scripts
├── deployments/
│   ├── k8s/                   # Kubernetes manifests (production-ready)
│   │   ├── app.yaml
│   │   ├── configmap.yaml
│   │   ├── grafana.yaml
│   │   ├── hpa.yaml
│   │   ├── namespace.yaml
│   │   ├── pgbouncer.yaml
│   │   ├── postgres.yaml
│   │   ├── prometheus.yaml
│   │   ├── rabbitmq.yaml
│   │   ├── redis.yaml
│   │   └── secret.yaml
│   └── docker/                # Dockerfiles
├── docs/                      # All documentation & ADRs
├── Makefile
└── docker-compose.yml
```

## Documentation

| Document | Description |
| --- | --- |
| [PRD](docs/prd.md) | Problem statement, requirements, success criteria, milestones |
| [Architecture](docs/architecture.md) | System design, read/write paths, cache TTLs, DB schema, metrics |
| [Development Guide](docs/development.md) | Setup, env vars, coding conventions, testing |
| [Workflow](docs/workflow.md) | Git branching, commit conventions, PR checklist |
| [ADR-001](docs/adrs/001-go-over-rust.md) | Go over Rust for language choice |
| [ADR-002](docs/adrs/002-feature-flag-over-branches.md) | Feature flags over branches for comparison |
| [ADR-003](docs/adrs/003-pgbouncer-connection-pooling.md) | PgBouncer for connection pooling |
| [ADR-004](docs/adrs/004-redis-caching-strategy.md) | Cache-aside pattern with Redis |
| [ADR-005](docs/adrs/005-async-write-via-queue.md) | Async writes via message queue |

## Testing

```bash
# Unit tests
go test ./...

# Integration tests (requires docker compose up)
go test -tags=integration ./...

# Load tests
k6 run scripts/load-test/baseline.js
k6 run scripts/load-test/optimized.js
```
