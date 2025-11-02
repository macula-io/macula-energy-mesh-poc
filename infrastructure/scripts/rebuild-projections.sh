#!/usr/bin/env bash
set -e

echo "🔧 Rebuilding cortex-iq-projections with fixed migrations..."
echo ""

cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/system

# Build the image
echo "📦 Building Docker image..."
docker build -f cortex_iq_projections/Dockerfile -t macula/cortex-iq-projections:latest .

# Load into KinD cluster
echo "📥 Loading image into kind-macula-hub..."
kind load docker-image macula/cortex-iq-projections:latest --name macula-hub

# Restart the deployment
echo "🔄 Restarting deployment..."
kubectl --context kind-macula-hub rollout restart -n macula-hub deployment/cortex-iq-projections

echo ""
echo "⏳ Waiting for rollout to complete..."
kubectl --context kind-macula-hub rollout status -n macula-hub deployment/cortex-iq-projections --timeout=120s

echo ""
echo "✅ Deployment complete! Checking logs..."
echo ""

# Wait a moment for the pod to start
sleep 5

# Show migration logs
kubectl --context kind-macula-hub logs -n macula-hub deploy/cortex-iq-projections --tail=100 | grep -A10 -B5 "migrat"

echo ""
echo "🔍 Verifying database tables..."
kubectl --context kind-macula-hub exec -n macula-hub deploy/cortex-iq-projections -- \
  psql postgresql://cortexiq:cortexiq123@postgres.macula-hub.svc.cluster.local:5432/cortexiq_projections \
  -c "\dt"

echo ""
echo "✅ Done!"
