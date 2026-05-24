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

cat > /home/ubuntu/run-mixed.sh <<'EOF'
#!/bin/bash
cd /home/ubuntu/banking-peak-load-prototype
BASE_URL="${app_base_url}" k6 run scripts/load-test/mixed.js
EOF

chmod +x /home/ubuntu/run-mixed.sh
chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype /home/ubuntu/run-mixed.sh