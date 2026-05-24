#!/bin/bash
set -eux

apt update -y
apt install -y git docker.io docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

cd /home/ubuntu
git clone ${repo_url}
cd banking-peak-load-prototype

docker compose up -d

chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype