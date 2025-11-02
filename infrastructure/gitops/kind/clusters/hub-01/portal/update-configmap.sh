#!/bin/bash
# Script to update portal ConfigMap with new HTML content

cd "$(dirname "$0")"

# Create ConfigMap from portal directory
kubectl create configmap portal-html \
  --from-file=index.html=/home/rl/work/github.com/macula-io/macula-energy-mesh-poc/infrastructure/portal/index.html \
  --from-file=macula-logo-animated.svg=/home/rl/work/github.com/macula-io/macula-energy-mesh-poc/infrastructure/portal/macula-logo-animated.svg \
  --namespace=macula-system \
  --dry-run=client \
  -o yaml > configmap-new.yaml

echo "✓ New ConfigMap generated at configmap-new.yaml"
echo "Review and replace configmap.yaml manually"
