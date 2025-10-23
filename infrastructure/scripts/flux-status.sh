#!/usr/bin/env bash

echo "========================================="
echo "FluxCD GitOps Status - All Clusters"
echo "========================================="
echo ""

CLUSTERS=("macula-hub" "macula-edge-01" "macula-edge-02" "macula-edge-03" "macula-edge-04")

for cluster in "${CLUSTERS[@]}"; do
  context="kind-${cluster}"
  echo "=== ${cluster} ==="
  echo "GitRepository:"
  kubectl --context "${context}" get gitrepo -n flux-system -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,REVISION:.status.artifact.revision 2>/dev/null || echo "  N/A"
  echo ""
  echo "Kustomizations:"
  kubectl --context "${context}" get kustomizations -n flux-system -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status 2>/dev/null || echo "  N/A"
  echo ""
  echo "---"
  echo ""
done

echo "========================================="
echo "✓ Status check complete"
echo "========================================="
