#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
FLUX_SYSTEM_DIR="infrastructure/gitops/kind/flux-system"

# Cluster contexts
HUB_CONTEXT="kind-macula-hub"
EDGE_CONTEXTS=(
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

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

bootstrap_cluster() {
  local context=$1
  local cluster_name=${context#kind-}

  log_step "Bootstrapping Flux GitOps on ${cluster_name}..."

  # Apply GitRepository
  kubectl --context "${context}" apply -f "${FLUX_SYSTEM_DIR}/git-repository.yaml"

  # Apply appropriate Kustomizations based on cluster type
  if [[ "${cluster_name}" == "macula-hub" ]]; then
    kubectl --context "${context}" apply -f "${FLUX_SYSTEM_DIR}/hub-kustomization.yaml"
  else
    # Extract edge number (e.g., "01" from "macula-edge-01")
    edge_num="${cluster_name##*-}"
    kubectl --context "${context}" apply -f "${FLUX_SYSTEM_DIR}/edge-${edge_num}-kustomization.yaml"
  fi

  log_info "✓ ${cluster_name} bootstrapped"
}

main() {
  log_info "========================================="
  log_info "Bootstrapping Flux GitOps"
  log_info "========================================="
  echo ""

  # Check if we're in a Git repo
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    log_warn "Not in a Git repository!"
    exit 1
  fi

  log_info "Current branch: $(git branch --show-current)"
  log_info "Remote URL: $(git remote get-url origin)"
  echo ""

  # Bootstrap hub
  bootstrap_cluster "${HUB_CONTEXT}"
  echo ""

  # Bootstrap all edge clusters
  for context in "${EDGE_CONTEXTS[@]}"; do
    bootstrap_cluster "${context}"
    echo ""
  done

  log_info "========================================="
  log_info "✓ All clusters bootstrapped"
  log_info "========================================="
  echo ""

  log_info "Checking Flux reconciliation status..."
  echo ""

  # Check GitRepository sync
  for context in "${HUB_CONTEXT}" "${EDGE_CONTEXTS[@]}"; do
    cluster_name=${context#kind-}
    echo "=== ${cluster_name} ==="
    kubectl --context "${context}" get gitrepository -n flux-system || true
    echo ""
  done

  echo ""
  log_info "Wait a few moments, then check Kustomization status with:"
  echo "  kubectl get kustomizations -n flux-system --context kind-macula-hub"
  echo "  kubectl get kustomizations -n flux-system --context kind-macula-edge-01"
}

main "$@"
