#!/bin/bash
set -euo pipefail

# Build all Docker images for Macula PoC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT"

echo "Building Macula Docker images..."

# Build base image first
echo "1. Building macula/os-base..."
docker build \
  -f infrastructure/docker/Dockerfile.macula-os-base \
  -t macula/os-base:latest \
  .

# Build payload images
echo "2. Building macula/cortex-iq-homes..."
docker build \
  -f infrastructure/docker/Dockerfile.cortex-iq-homes \
  -t macula/cortex-iq-homes:latest \
  .

echo "3. Building macula/cortex-iq-utilities..."
docker build \
  -f infrastructure/docker/Dockerfile.cortex-iq-utilities \
  -t macula/cortex-iq-utilities:latest \
  .

echo "4. Building macula/cortex-iq-dashboard..."
docker build \
  -f infrastructure/docker/Dockerfile.cortex-iq-dashboard \
  -t macula/cortex-iq-dashboard:latest \
  .

echo ""
echo "✓ All images built successfully"
echo ""
echo "Images:"
docker images | grep macula
echo ""
echo "To push to registry:"
echo "  docker push macula/os-base:latest"
echo "  docker push macula/cortex-iq-homes:latest"
echo "  docker push macula/cortex-iq-utilities:latest"
echo "  docker push macula/cortex-iq-dashboard:latest"
