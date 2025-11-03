#!/usr/bin/env bash
set -euo pipefail

echo "🔨 Rebuilding cortex-iq-projections and cortex-iq-queries with system_stats updates..."

cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc

# Build and push projections image
echo "📦 Building cortex-iq-projections..."
docker build -t macula/cortex-iq-projections:latest \
  -t registry.macula.local:5000/macula/cortex-iq-projections:latest \
  -f system/cortex_iq_projections/Dockerfile system

echo "📤 Pushing cortex-iq-projections to registry..."
docker push registry.macula.local:5000/macula/cortex-iq-projections:latest

# Build and push queries image
echo "📦 Building cortex-iq-queries..."
docker build -t macula/cortex-iq-queries:latest \
  -t registry.macula.local:5000/macula/cortex-iq-queries:latest \
  -f system/cortex_iq_queries/Dockerfile system

echo "📤 Pushing cortex-iq-queries to registry..."
docker push registry.macula.local:5000/macula/cortex-iq-queries:latest

# Restart deployments to pull new images
echo "🔄 Restarting cortex-iq-projections..."
kubectl --context kind-macula-hub rollout restart deployment cortex-iq-projections -n macula-hub

echo "🔄 Restarting cortex-iq-queries..."
kubectl --context kind-macula-hub rollout restart deployment cortex-iq-queries -n macula-hub

echo "⏳ Waiting for rollouts to complete..."
kubectl --context kind-macula-hub rollout status deployment cortex-iq-projections -n macula-hub --timeout=120s
kubectl --context kind-macula-hub rollout status deployment cortex-iq-queries -n macula-hub --timeout=120s

echo "✅ Done! Services rebuilt and restarted."
echo ""
echo "📊 Check projections logs for system_stats writes:"
echo "kubectl --context kind-macula-hub logs -n macula-hub -l app=cortex-iq-projections --tail=50"
