#!/usr/bin/env bash
# Build all CortexIQ Docker images for deployment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="${REGISTRY:-registry.macula.local:5000}"
TAG="${TAG:-latest}"
CACHE_BUST="$(date +%s)"

echo "==================================================================="
echo "Building CortexIQ Docker Images"
echo "==================================================================="
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "Cache Bust: $CACHE_BUST"
echo "==================================================================="

cd "$REPO_ROOT"

# Skip macula_gateway_service for now (requires Erlang macula libraries)
# TODO: Build actual Erlang gateway or create standalone gateway service
echo ""
echo ">>> Skipping macula_gateway_service (not ready for containerization yet)..."

# Build cortex_iq_simulation
echo ""
echo ">>> Building cortex_iq_simulation..."
docker build \
  --build-arg CACHE_BUST="$CACHE_BUST" \
  -f system/cortex_iq_simulation/Dockerfile \
  -t "$REGISTRY/macula/cortex-iq-simulation:$TAG" \
  system/

# Build cortex_iq_homes
echo ""
echo ">>> Building cortex_iq_homes..."
docker build \
  --build-arg CACHE_BUST="$CACHE_BUST" \
  -f system/cortex_iq_homes/Dockerfile \
  -t "$REGISTRY/macula/cortex-iq-homes:$TAG" \
  system/

# Build cortex_iq_utilities
echo ""
echo ">>> Building cortex_iq_utilities..."
docker build \
  --build-arg CACHE_BUST="$CACHE_BUST" \
  -f system/cortex_iq_utilities/Dockerfile \
  -t "$REGISTRY/macula/cortex-iq-utilities:$TAG" \
  system/

# Build cortex_iq_projections
echo ""
echo ">>> Building cortex_iq_projections..."
docker build \
  --build-arg CACHE_BUST="$CACHE_BUST" \
  -f system/cortex_iq_projections/Dockerfile \
  -t "$REGISTRY/macula/cortex-iq-projections:$TAG" \
  system/

# Build cortex_iq_queries
echo ""
echo ">>> Building cortex_iq_queries..."
docker build \
  --build-arg CACHE_BUST="$CACHE_BUST" \
  -f system/cortex_iq_queries/Dockerfile \
  -t "$REGISTRY/macula/cortex-iq-queries:$TAG" \
  system/

# Build cortex_iq_dashboard (from Dockerfile.hub)
echo ""
echo ">>> Building cortex_iq_dashboard..."
docker build \
  --build-arg CACHE_BUST="$CACHE_BUST" \
  -f Dockerfile.hub \
  -t "$REGISTRY/macula/cortex-iq-dashboard:$TAG" \
  .

echo ""
echo "==================================================================="
echo "✅ All images built successfully!"
echo "==================================================================="
echo ""
echo "Images built:"
echo "  - $REGISTRY/macula/cortex-iq-simulation:$TAG"
echo "  - $REGISTRY/macula/cortex-iq-homes:$TAG"
echo "  - $REGISTRY/macula/cortex-iq-utilities:$TAG"
echo "  - $REGISTRY/macula/cortex-iq-projections:$TAG"
echo "  - $REGISTRY/macula/cortex-iq-queries:$TAG"
echo "  - $REGISTRY/macula/cortex-iq-dashboard:$TAG"
echo ""
echo "Skipped:"
echo "  - macula-gateway-service (requires Erlang macula libraries - TODO)"
echo ""
echo "Next steps:"
echo "  1. Push images: ./scripts/push-all-images.sh"
echo "  2. Commit GitOps changes: git add kind/ && git commit && git push"
echo "  3. Bootstrap clusters: cd kind/ && ./bootstrap-gitops.sh"
echo ""
