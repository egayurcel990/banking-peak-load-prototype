#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/banking-cloud-demo-k6-user-data.log | logger -t banking-cloud-demo-k6 -s 2>/dev/console) 2>&1

apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y git curl gnupg ca-certificates

curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y k6

cd /home/ubuntu
if [ ! -d banking-peak-load-prototype ]; then
  git clone ${repo_url}
fi
cd banking-peak-load-prototype
git pull --ff-only || true

cat > /home/ubuntu/run-mixed.sh <<'RUNEOF'
#!/bin/bash
set -euo pipefail
cd /home/ubuntu/banking-peak-load-prototype

echo "Checking target: ${app_base_url}/metrics"
for i in $(seq 1 60); do
  if curl -fsS "${app_base_url}/metrics" >/dev/null; then
    break
  fi
  echo "Target is not ready yet. Retry $i/60..."
  sleep 5
done

curl -fsS "${app_base_url}/metrics" >/dev/null
BASE_URL="${app_base_url}" k6 run scripts/load-test/mixed.js
RUNEOF

cat > /home/ubuntu/run-status.sh <<'RUNEOF'
#!/bin/bash
set -euo pipefail
cd /home/ubuntu/banking-peak-load-prototype
curl -fsS "${app_base_url}/metrics" >/dev/null
BASE_URL="${app_base_url}" k6 run scripts/load-test/status.js
RUNEOF

chmod +x /home/ubuntu/run-mixed.sh /home/ubuntu/run-status.sh
chown -R ubuntu:ubuntu /home/ubuntu/banking-peak-load-prototype /home/ubuntu/run-mixed.sh /home/ubuntu/run-status.sh

touch /home/ubuntu/k6-runner-ready
echo "k6 runner ready"
