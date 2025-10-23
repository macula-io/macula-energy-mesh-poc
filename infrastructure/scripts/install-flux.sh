#!/usr/bin/env bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
FLUX_VERSION="latest"
FLUX_INSTALL_URL="https://github.com/fluxcd/flux2/releases/${FLUX_VERSION}/download/install.yaml"

# All cluster contexts
CLUSTER_CONTEXTS=(
  "kind-macula-hub"
  "kind-macula-edge-01"
  "kind-macula-edge-02"
  "kind-macula-edge-03"
  "kind-macula-edge-04"
)

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_step() {
  echo -e "${CYAN}[STEP]${NC} $*"
}

install_flux_on_cluster() {
  local context=$1
  local cluster_name=${context#kind-}

  log_step "Installing Flux on ${cluster_name}..."

  if kubectl --context "${context}" apply -f "${FLUX_INSTALL_URL}" &>/dev/null; then
    log_info "✓ Flux installed on ${cluster_name}"
  else
    echo -e "${YELLOW}[WARN]${NC} Failed to install Flux on ${cluster_name}"
    return 1
  fi
}

wait_for_flux_ready() {
  local context=$1
  local cluster_name=${context#kind-}

  log_step "Waiting for Flux controllers to be ready on ${cluster_name}..."

  kubectl --context "${context}" wait --for=condition=ready pod \
    -n flux-system \
    --all \
    --timeout=120s &>/dev/null || true

  log_info "✓ Flux ready on ${cluster_name}"
}

main() {
  log_info "========================================="
  log_info "Installing Flux on all KinD clusters"
  log_info "========================================="
  echo ""

  # Install on all clusters
  for context in "${CLUSTER_CONTEXTS[@]}"; do
    install_flux_on_cluster "${context}"
    wait_for_flux_ready "${context}"
    echo ""
  done

  log_info "========================================="
  log_info "✓ Flux installed on all clusters"
  log_info "========================================="
  echo ""

  # Show status
  log_info "Flux system pods:"
  for context in "${CLUSTER_CONTEXTS[@]}"; do
    cluster_name=${context#kind-}
    echo ""
    echo "=== ${cluster_name} ==="
    kubectl --context "${context}" get pods -n flux-system
  done
}

main "$@"
