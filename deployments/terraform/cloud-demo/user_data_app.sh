#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/banking-cloud-demo-user-data.log | logger -t banking-cloud-demo -s 2>/dev/console) 2>&1

apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y git docker.io curl ca-certificates gnupg

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu || true

mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

docker compose version

cd /home/ubuntu
if [ ! -d banking-peak-load-prototype ]; then
  git clone ${repo_url}
fi

cd banking-peak-load-prototype
git pull --ff-only || true

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

docker compose --profile optimized --profile observability up -d --build

echo "Waiting for app metrics endpoint..."
for i in $(seq 1 120); do
  if curl -fsS http://localhost:8080/metrics >/dev/null; then
    break
  fi
  docker compose ps || true
  docker compose logs app --tail=40 || true
  sleep 5
done
curl -fsS http://localhost:8080/metrics >/dev/null

echo "Seeding database for mixed.js defaults..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d banking <<'SQLEOF'
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

docker compose restart app prometheus grafana

echo "Waiting after restart..."
sleep 15
curl -fsS http://localhost:8080/metrics >/dev/null
curl -fsS http://localhost:9090/-/ready >/dev/null

docker compose exec -T postgres psql -U postgres -d banking -c "SELECT COUNT(*) AS accounts FROM accounts;"
docker compose exec -T postgres psql -U postgres -d banking -c "SELECT COUNT(*) AS transactions FROM transactions;"

docker compose ps
chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype

touch /home/ubuntu/cloud-demo-ready
echo "cloud-demo app server ready"
