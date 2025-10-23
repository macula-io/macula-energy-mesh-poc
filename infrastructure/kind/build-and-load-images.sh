#!/bin/bash
set -euo pipefail

# Build and load container images into KinD clusters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}✓${NC} $1"
}

log_step() {
  echo -e "${CYAN}▸${NC} $1"
}

# Build homes image
log_step "Building cortex-iq-homes image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_homes/Dockerfile" \
  -t macula/cortex-iq-homes:latest \
  "$PROJECT_ROOT/system/cortex_iq_homes"
log_info "Homes image built"

# Build utilities image
log_step "Building cortex-iq-utilities image..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_utilities/Dockerfile" \
  -t macula/cortex-iq-utilities:latest \
  "$PROJECT_ROOT/system/cortex_iq_utilities"
log_info "Utilities image built"

# Build dashboard image using Dockerfile.hub
log_step "Building cortex-iq-dashboard image..."
docker build \
  -f "$PROJECT_ROOT/Dockerfile.hub" \
  -t macula/cortex-iq-dashboard:latest \
  "$PROJECT_ROOT"
log_info "Dashboard image built"

# Load images into KinD clusters
log_step "Loading images into KinD clusters..."

# Load dashboard into edge-01 (where dashboard will run)
log_step "Loading dashboard image into macula-edge-01..."
kind load docker-image macula/cortex-iq-dashboard:latest --name macula-edge-01
log_info "Dashboard image loaded into edge-01"

# Load homes into edge-01, edge-02, and edge-04
log_step "Loading homes image into macula-edge-01, edge-02, and edge-04..."
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-01
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-02
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-04
log_info "Homes image loaded into edge-01, edge-02, and edge-04"

# Load utilities into edge-03
log_step "Loading utilities image into macula-edge-03..."
kind load docker-image macula/cortex-iq-utilities:latest --name macula-edge-03
log_info "Utilities image loaded into edge-03"

echo ""
log_info "All images built and loaded!"
echo ""
echo "Images:"
echo "  - macula/os-base:latest"
echo "  - macula/cortex-iq-dashboard:latest (loaded into edge-01)"
echo "  - macula/cortex-iq-homes:latest (loaded into edge-01, edge-02)"
echo "  - macula/cortex-iq-utilities:latest (loaded into edge-03)"
