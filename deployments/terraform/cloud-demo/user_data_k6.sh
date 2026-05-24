#!/bin/bash
set -euxo pipefail

apt update -y
apt install -y git curl gnupg ca-certificates

curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
apt update -y
apt install -y k6

cd /home/ubuntu
if [ ! -d banking-peak-load-prototype ]; then
  git clone ${repo_url}
fi
cd banking-peak-load-prototype

cat > /home/ubuntu/run-mixed.sh <<'RUNEOF'
#!/bin/bash
set -euo pipefail
cd /home/ubuntu/banking-peak-load-prototype
BASE_URL="${app_base_url}" k6 run scripts/load-test/mixed.js
RUNEOF

cat > /home/ubuntu/run-status.sh <<'RUNEOF'
#!/bin/bash
set -euo pipefail
cd /home/ubuntu/banking-peak-load-prototype
BASE_URL="${app_base_url}" k6 run scripts/load-test/status.js
RUNEOF

chmod +x /home/ubuntu/run-mixed.sh /home/ubuntu/run-status.sh
chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype /home/ubuntu/run-mixed.sh /home/ubuntu/run-status.sh
