#!/bin/bash
set -e

# Log all output
exec > /var/log/user-data.log 2>&1

echo "=== Starting k6 runner setup ==="

# Update system
apt-get update -y
apt-get upgrade -y

# Install dependencies
apt-get install -y curl git unzip

# Install k6
echo "=== Installing k6 ==="
curl -fsSL https://pkg.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | tee /etc/apt/sources.list.d/k6.list
apt-get update -y
apt-get install -y k6

# Verify k6 installation
k6 version

# Clone repo
echo "=== Cloning repository ==="
cd /home/ubuntu
git clone ${repo_url} banking-peak-load-prototype
chown -R ubuntu:ubuntu banking-peak-load-prototype

# Write env file with target URL
cat > /home/ubuntu/banking-peak-load-prototype/.env.k6 << EOF
BASE_URL=${base_url}
EOF

# Create convenience run scripts
cat > /home/ubuntu/run-mixed.sh <<'RUNEOF'
#!/bin/bash
set -e
cd /home/ubuntu/banking-peak-load-prototype
BASE_URL="${base_url}" k6 run scripts/load-test/mixed.js
RUNEOF

cat > /home/ubuntu/run-optimized.sh <<'RUNEOF'
#!/bin/bash
set -e
cd /home/ubuntu/banking-peak-load-prototype
BASE_URL="${base_url}" k6 run scripts/load-test/optimized.js
RUNEOF

cat > /home/ubuntu/run-spike.sh <<'RUNEOF'
#!/bin/bash
set -e
cd /home/ubuntu/banking-peak-load-prototype
BASE_URL="${base_url}" k6 run scripts/load-test/spike.js
RUNEOF

chmod +x /home/ubuntu/run-*.sh
chown ubuntu:ubuntu /home/ubuntu/run-*.sh

echo "=== Setup complete! ==="
echo "k6 version: $(k6 version)"
echo "Repo cloned to: /home/ubuntu/banking-peak-load-prototype"
echo "Target URL: ${base_url}"
echo ""
echo "Run load test with:"
echo "  ./run-mixed.sh"
echo "  ./run-optimized.sh"
echo "  ./run-spike.sh"
