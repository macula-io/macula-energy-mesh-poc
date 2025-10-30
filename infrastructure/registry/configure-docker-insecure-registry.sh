#!/bin/bash
set -euo pipefail

# Configure Docker to trust insecure registry
# Run this script with: sudo ./configure-docker-insecure-registry.sh

echo "Configuring Docker daemon to trust insecure registry..."

# Backup existing daemon.json if it exists
if [ -f /etc/docker/daemon.json ]; then
  cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
  echo "✓ Backed up existing daemon.json"
fi

# Write new daemon.json
tee /etc/docker/daemon.json <<'EOF'
{
  "insecure-registries": ["registry.macula.local:5000", "localhost:5000"]
}
EOF

echo ""
echo "✓ Docker daemon.json configured"
echo ""
echo "Restarting Docker..."
systemctl restart docker

echo ""
echo "✓ Docker restarted"
echo ""
echo "Test the registry:"
echo "  docker pull alpine:latest"
echo "  docker tag alpine:latest registry.macula.local:5000/test/alpine:latest"
echo "  docker push registry.macula.local:5000/test/alpine:latest"
