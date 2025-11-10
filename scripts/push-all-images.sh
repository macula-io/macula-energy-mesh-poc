#!/usr/bin/env bash
# Push all CortexIQ Docker images to registry
set -euo pipefail

REGISTRY="${REGISTRY:-registry.macula.local:5000}"
TAG="${TAG:-latest}"

echo "==================================================================="
echo "Pushing CortexIQ Docker Images"
echo "==================================================================="
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "==================================================================="

IMAGES=(
  "macula/macula-gateway-service"
  "macula/cortex-iq-simulation"
  "macula/cortex-iq-homes"
  "macula/cortex-iq-utilities"
  "macula/cortex-iq-projections"
  "macula/cortex-iq-queries"
  "macula/cortex-iq-dashboard"
)

for IMAGE in "${IMAGES[@]}"; do
  echo ""
  echo ">>> Pushing $IMAGE:$TAG..."
  docker push "$REGISTRY/$IMAGE:$TAG"
done

echo ""
echo "==================================================================="
echo "✅ All images pushed successfully!"
echo "==================================================================="
echo ""
echo "Images available at:"
for IMAGE in "${IMAGES[@]}"; do
  echo "  - $REGISTRY/$IMAGE:$TAG"
done
echo ""
echo "Next steps:"
echo "  1. Commit GitOps changes: git add kind/ && git commit && git push"
echo "  2. Bootstrap clusters: cd kind/ && ./bootstrap-gitops.sh"
echo ""
