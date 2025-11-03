#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo
log_info "========================================"
log_info "Rebuild and Deploy CortexIQ Dashboard"
log_info "========================================"
echo

cd "${PROJECT_ROOT}"

log_step "Building dashboard Docker image..."
docker build -f Dockerfile.hub \
  -t macula/cortex-iq-dashboard:latest \
  .
echo

log_step "Loading dashboard image into macula-hub cluster..."
kind load docker-image macula/cortex-iq-dashboard:latest --name macula-hub
echo

log_step "Restarting dashboard deployment..."
kubectl --context kind-macula-hub rollout restart deployment cortex-iq-dashboard -n macula-hub
echo

log_step "Waiting for dashboard to be ready..."
kubectl --context kind-macula-hub wait --for=condition=available \
  --timeout=120s deployment/cortex-iq-dashboard -n macula-hub
echo

log_info "========================================"
log_info "✓ Dashboard rebuild complete!"
log_info "========================================"
echo
log_info "Dashboard: http://dashboard.cortexiq.local:8080/"
echo
