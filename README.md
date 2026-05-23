<h1 align="center">Banking Peak Load Prototype</h1>

<p align="center">
  Defense-in-depth scalability prototype — simulating how a bank survives 1M transactions/hour without crashing.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Go-1.25-00ADD8?style=flat-square&logo=go&logoColor=white" />
  <img src="https://img.shields.io/badge/PostgreSQL-16-4169E1?style=flat-square&logo=postgresql&logoColor=white" />
  <img src="https://img.shields.io/badge/PgBouncer-Connection%20Pool-336791?style=flat-square" />
  <img src="https://img.shields.io/badge/Redis-7-DC382D?style=flat-square&logo=redis&logoColor=white" />
  <img src="https://img.shields.io/badge/RabbitMQ-Queue-FF6600?style=flat-square&logo=rabbitmq&logoColor=white" />
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
  <img src="https://img.shields.io/badge/Prometheus-Grafana-E6522C?style=flat-square&logo=prometheus&logoColor=white" />
  <img src="https://img.shields.io/badge/k6-Load%20Testing-7D64FF?style=flat-square&logo=k6&logoColor=white" />
  <img src="https://github.com/ahargunyllib/banking-peak-load-prototype/actions/workflows/ci.yaml/badge.svg" />
</p>

---

## Problem Statement

A major bank (inspired by CIMB Niaga) experiences system crashes during peak load: **1M transactions/hour causing >20% error rate, >10s latency, and cost spikes**. Root causes: no backpressure, DB connection exhaustion, heavy queries without caching, and reactive scaling.

This prototype demonstrates how **four layered protection mechanisms** bring the system from unstable to production-grade.

---

## Results

| Metric | Baseline | Optimized | Improvement |
|---|---|---|---|
| p95 Latency (read) | > 2s | **< 500ms** | 4× faster |
| p95 Latency (write) | > 5s | **< 2s** | 2.5× faster |
| Error Rate at peak | > 20% | **< 0.5%** | 40× lower |
| Max TPS | < 100 | **> 300** | 3× throughput |
| Cache Hit Rate | N/A | **> 80%** | — |
| Availability | — | **99.5%** | — |

Grafana Dashboard:

![Dashboard](docs/grafana-screenshot.jpeg)

k6 Load Test:

![Dashboard](docs/k6-loadtest-screenshot.jpeg)

---

## Architecture

Defense-in-depth: four protection layers between client and database. Each layer reduces load on the layer below it.

```
Client Request
      │
      ▼
┌─────────────────────────┐
│  Layer 1: Rate Limiter  │  Token bucket per client IP → HTTP 429
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Layer 2: Circuit Breaker│  Monitor downstream health → HTTP 503
└───────┬─────────┬───────┘
        │         │
      READ      WRITE
        │         │
        ▼         ▼
┌───────────┐  ┌──────────────┐
│ Layer 3a  │  │  Layer 3b    │
│ Redis     │  │  RabbitMQ    │
│ Cache     │  │  Queue       │
└─────┬─────┘  └──────┬───────┘
      │                │
      ▼                ▼
┌───────────┐  ┌──────────────┐
│  Read     │  │  Worker      │
│  Replica  │  │  Consumer    │
└─────┬─────┘  └──────┬───────┘
      │                │
      ▼                ▼
┌─────────────────────────┐
│  Layer 4: PostgreSQL 16 │
│  via PgBouncer pooling  │
│  Primary (write only)   │
│  Replica (read only)    │
└─────────────────────────┘
```

**Read path:** Rate limit → Circuit breaker → Redis cache → (miss) Read replica via PgBouncer → cache & return

**Write path (optimized):** Rate limit → Circuit breaker → Validate → Publish to RabbitMQ → HTTP 202 (async)

**Write path (baseline):** Synchronous DB transaction → HTTP 201

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Go 1.25 + Echo router |
| Database | PostgreSQL 16 + PgBouncer (transaction pooling) |
| Cache | Redis 7 (cache-aside pattern) |
| Message Queue | RabbitMQ |
| Observability | Prometheus + Grafana |
| Load Testing | k6 |
| Infrastructure | Docker Compose (profile-based) |
| CI | GitHub Actions |
| Dev tooling | air (live reload), golangci-lint, Nix flake |

---

## Quick Start

**Prerequisites:** Go 1.25, Docker & Docker Compose v2, k6, Make

```bash
# Install Go tooling
make init

# Baseline (API + PostgreSQL only)
cp .env.baseline.example .env
docker compose up -d
k6 run scripts/load-test/baseline.js

# Optimized (+ Redis, RabbitMQ, read replica)
cp .env.optimized.example .env
docker compose --profile optimized up -d
k6 run scripts/load-test/optimized.js

# Full stack (+ Prometheus + Grafana)
docker compose --profile optimized --profile observability up -d
# Grafana:    http://localhost:3000
# Prometheus: http://localhost:9090
```

Seed dummy data (100K accounts, 1M transactions):
```bash
make seed
```

---

## Feature Flags

All protection layers are toggled via environment variables — baseline = all off, optimized = all on.

| Variable | Default | Description |
|---|---|---|
| `CACHE_ENABLED` | `false` | Redis cache for read path |
| `QUEUE_ENABLED` | `false` | Async write via message queue |
| `RATE_LIMIT_ENABLED` | `false` | Token bucket rate limiting |
| `CIRCUIT_BREAKER_ENABLED` | `false` | Fail-fast on unhealthy downstream |
| `DB_READ_REPLICA_ENABLED` | `false` | Route reads to replica |

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/transactions` | Create transaction (async when queue enabled) |
| `GET` | `/api/v1/transactions/:id/status` | Transaction status inquiry |
| `GET` | `/api/v1/accounts/:id/balance` | Account balance inquiry |

---

## Project Structure

```
banking-peak-load-prototype/
├── cmd/server/main.go          # Entry point
├── internal/
│   ├── config/                 # Env-based configuration
│   ├── handler/                # HTTP handlers
│   ├── middleware/             # Rate limiter, circuit breaker
│   ├── repository/             # DB access + cache-aside logic
│   ├── service/                # Business logic
│   ├── queue/                  # RabbitMQ producer + worker
│   └── model/                  # Domain types
├── migrations/                 # SQL migrations
├── scripts/load-test/          # k6 scripts (baseline.js, optimized.js)
├── deployments/
│   ├── pgbouncer/              # PgBouncer config
│   ├── prometheus/             # prometheus.yml
│   └── grafana/                # Dashboard JSON provisioning
├── docs/                       # PRD, Architecture, ADRs
├── Makefile
└── docker-compose.yml
```

---

## Documentation

| Document | Description |
|---|---|
| [PRD](docs/prd.md) | Problem statement, requirements, success criteria |
| [Architecture](docs/architecture.md) | System design, read/write paths, DB schema |
| [Development Guide](docs/development.md) | Setup, env vars, conventions |
| [ADR-001](docs/adrs/001-go-over-rust.md) | Go over Rust — language choice |
| [ADR-002](docs/adrs/002-feature-flag-over-branches.md) | Feature flags over branches for comparison |
| [ADR-003](docs/adrs/003-pgbouncer-connection-pooling.md) | PgBouncer for connection pooling |
| [ADR-004](docs/adrs/004-redis-caching-strategy.md) | Cache-aside pattern with Redis |
| [ADR-005](docs/adrs/005-async-write-via-queue.md) | Async writes via message queue |

---

## Makefile Commands

```bash
make init    # Download Go modules + install dev tools
make dev     # Start server with live reload (air)
make lint    # Run golangci-lint
make test    # Run unit tests
make build   # Compile binary to bin/app
make seed    # Seed 100K accounts + 1M transactions
```

---

<p align="center">
  <i>Built as a university capstone · Universitas Brawijaya · 2025</i>
</p>
