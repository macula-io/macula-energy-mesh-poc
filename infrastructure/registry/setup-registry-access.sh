#!/bin/bash
set -euo pipefail

# Setup registry access - run with sudo

echo "========================================="
echo "Setting up Registry Access"
echo "========================================="
echo ""

# Step 1: Add to /etc/hosts
echo "Step 1: Adding registry.macula.local to /etc/hosts..."
if ! grep -q "registry.macula.local" /etc/hosts; then
  echo "127.0.0.1 registry.macula.local" >> /etc/hosts
  echo "✓ Added registry.macula.local to /etc/hosts"
else
  echo "✓ registry.macula.local already in /etc/hosts"
fi
echo ""

# Step 2: Create /etc/docker if it doesn't exist
echo "Step 2: Creating /etc/docker directory..."
mkdir -p /etc/docker
echo "✓ /etc/docker directory ready"
echo ""

# Step 3: Backup existing daemon.json
if [ -f /etc/docker/daemon.json ]; then
  cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d-%H%M%S)
  echo "✓ Backed up existing daemon.json"
fi

# Step 4: Configure Docker daemon
echo "Step 3: Configuring Docker daemon..."
tee /etc/docker/daemon.json <<'EOF'
{
  "insecure-registries": [
    "registry.macula.local:5000",
    "localhost:5000",
    "127.0.0.1:5000"
  ]
}
EOF
echo "✓ Docker daemon.json configured"
echo ""

# Step 5: Restart Docker
echo "Step 4: Restarting Docker..."
systemctl restart docker
echo "✓ Docker restarted"
echo ""

echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Verify the configuration:"
echo "  docker info | grep -A 5 'Insecure Registries'"
echo ""
echo "Test push/pull:"
echo "  docker pull alpine:latest"
echo "  docker tag alpine:latest registry.macula.local:5000/test/alpine:latest"
echo "  docker push registry.macula.local:5000/test/alpine:latest"
echo "  curl http://registry.macula.local:5000/v2/_catalog"
echo ""
