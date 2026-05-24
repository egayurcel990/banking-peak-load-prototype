#!/bin/bash
set -euxo pipefail

apt update -y
apt install -y git docker.io curl ca-certificates gnupg

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu || true

mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

cd /home/ubuntu
if [ ! -d banking-peak-load-prototype ]; then
  git clone ${repo_url}
fi
cd banking-peak-load-prototype

cat > .env <<'ENVEOF'
APP_PORT=8080
APP_ENV=production

CACHE_ENABLED=true
QUEUE_ENABLED=true
RATE_LIMIT_ENABLED=true
RATE_LIMIT_RPS=1000
RATE_LIMIT_BURST=2000
CIRCUIT_BREAKER_ENABLED=true
CB_MAX_FAILURES=5
CB_TIMEOUT_SECONDS=10

DB_READ_REPLICA_ENABLED=false
DB_PRIMARY_DSN=postgres://postgres:postgres@postgres:5432/banking?sslmode=disable
PGBOUNCER_DSN=postgres://postgres:postgres@pgbouncer:5432/banking?sslmode=disable
PGBOUNCER_READ_DSN=postgres://postgres:postgres@pgbouncer:5432/banking?sslmode=disable

REDIS_ADDR=redis:6379
CACHE_BALANCE_TTL=10s
CACHE_TX_STATUS_TTL=30s

QUEUE_URL=amqp://guest:guest@rabbitmq:5672/
QUEUE_WORKERS=10
ENVEOF

# Start all runtime and observability services.
docker compose --profile optimized --profile observability up -d --build

# Wait for the application to run its migrations and expose metrics.
until curl -fsS http://localhost:8080/metrics >/dev/null; do
  docker compose ps || true
  docker compose logs app --tail=30 || true
  sleep 5
done

# Seed data matching k6 mixed.js defaults:
# accounts: 1001..101000, transactions: txn0000000000000000000000..txn0000000000000000999999
# This avoids account not found and transaction not found errors during load testing.
docker compose exec -T postgres psql -U postgres -d banking <<'SQLEOF'
SET synchronous_commit = off;
TRUNCATE TABLE transactions, accounts CASCADE;

INSERT INTO accounts (id, name, balance, updated_at)
SELECT
  1000 + i,
  'Account ' || (1000 + i),
  1000000000.00,
  NOW()
FROM generate_series(1, 100000) AS i;

INSERT INTO transactions (id, source_account, dest_account, amount, status, created_at, updated_at)
SELECT
  'txn' || lpad(i::text, 22, '0'),
  1001 + (i % 100000),
  1001 + ((i + 1) % 100000),
  1000.00 + (i % 9000),
  CASE
    WHEN i % 12 < 8 THEN 'completed'
    WHEN i % 12 < 11 THEN 'pending'
    ELSE 'failed'
  END,
  NOW() - ((i % 720) * INTERVAL '1 hour'),
  NOW()
FROM generate_series(0, 999999) AS i;

SELECT COUNT(*) AS accounts_seeded FROM accounts;
SELECT COUNT(*) AS transactions_seeded FROM transactions;
SQLEOF

# Restart the app so cache/queue state starts clean after the large seed.
docker compose restart app prometheus grafana
sleep 10
curl -fsS http://localhost:8080/metrics >/dev/null
curl -fsS http://localhost:9090/-/ready >/dev/null

chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype
