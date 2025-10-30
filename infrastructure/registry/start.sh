#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Starting Macula Container Registry"
echo "========================================="
echo ""

# Start Registry
cd "$SCRIPT_DIR"
docker-compose up -d

echo ""
echo "Waiting for registry to be healthy..."
sleep 5

# Wait for nginx to be healthy
until docker inspect macula-registry-nginx --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; do
  echo "  Waiting for registry services..."
  sleep 3
done

echo ""
echo "✓ Registry is running!"
echo ""
echo "========================================="
echo "Access Information"
echo "========================================="
echo ""
echo "Registry UI:    http://registry.macula.local:5000"
echo "Docker API:     registry.macula.local:5000"
echo ""
echo "========================================="
echo "Quick Test"
echo "========================================="
echo ""
echo "# Test registry API:"
echo "curl http://registry.macula.local:5000/v2/_catalog"
echo ""
echo "# Tag and push an image:"
echo "docker tag alpine:latest registry.macula.local:5000/alpine:latest"
echo "docker push registry.macula.local:5000/alpine:latest"
echo ""
echo "========================================="
echo "Add to /etc/hosts:"
echo "========================================="
echo "127.0.0.1 registry.macula.local"
echo ""
echo "Or run: sudo ./infrastructure/scripts/setup-hosts.sh"
echo ""
