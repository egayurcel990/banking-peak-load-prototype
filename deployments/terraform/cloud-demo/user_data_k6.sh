#!/bin/bash
set -eux

apt update -y
apt install -y git curl gnupg ca-certificates

curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
apt update -y
apt install -y k6

cd /home/ubuntu
git clone ${repo_url}
cd banking-peak-load-prototype

chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype