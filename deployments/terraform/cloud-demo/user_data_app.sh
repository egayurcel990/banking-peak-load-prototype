#!/bin/bash
set -eux

apt update -y
apt install -y git docker.io curl ca-certificates gnupg golang-go

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

cd /home/ubuntu
git clone ${repo_url}
cd banking-peak-load-prototype

cp .env.optimized.example .env

docker compose --profile optimized --profile observability up -d --build

sleep 45

DB_PRIMARY_DSN="postgres://postgres:postgres@localhost:5432/banking?sslmode=disable" \
  go run ./cmd/seeds/main.go

chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype