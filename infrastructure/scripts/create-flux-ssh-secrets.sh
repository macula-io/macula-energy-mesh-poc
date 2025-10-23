#!/usr/bin/env bash

set -euo pipefail

# Configuration
SSH_PRIVATE_KEY="${HOME}/.ssh/id_ed25519"
SSH_PUBLIC_KEY="${HOME}/.ssh/id_ed25519.pub"

CLUSTER_CONTEXTS=(
  "kind-macula-hub"
  "kind-macula-edge-01"
  "kind-macula-edge-02"
  "kind-macula-edge-03"
  "kind-macula-edge-04"
)

# Get GitHub known hosts
KNOWN_HOSTS=$(ssh-keyscan github.com 2>/dev/null)

for context in "${CLUSTER_CONTEXTS[@]}"; do
  cluster_name=${context#kind-}
  echo "Creating SSH secret on ${cluster_name}..."

  kubectl --context "${context}" create secret generic flux-system \
    --from-file=identity="${SSH_PRIVATE_KEY}" \
    --from-file=identity.pub="${SSH_PUBLIC_KEY}" \
    --from-literal=known_hosts="${KNOWN_HOSTS}" \
    --namespace=flux-system \
    --dry-run=client -o yaml | kubectl --context "${context}" apply -f -

  echo "✓ ${cluster_name} done"
done

echo ""
echo "✓ SSH secrets created on all clusters"
