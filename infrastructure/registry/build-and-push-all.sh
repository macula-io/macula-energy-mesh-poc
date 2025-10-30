#!/bin/bash
set -euo pipefail

# Build and push all Macula images to registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="registry.macula.local:5000"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}✓${NC} $1"
}

log_step() {
  echo -e "${CYAN}▸${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Building & Pushing Macula Images${NC}"
echo -e "${CYAN}Registry: $REGISTRY${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Build and push MaculaOs sidecar
log_step "Building macula-os..."
docker build \
  -f "$PROJECT_ROOT/system/macula_os/Dockerfile" \
  -t macula/macula-os:latest \
  -t "$REGISTRY/macula/macula-os:latest" \
  "$PROJECT_ROOT/system"
log_info "Built macula-os"

log_step "Pushing macula-os..."
docker push "$REGISTRY/macula/macula-os:latest"
log_info "Pushed macula-os"

# Build and push homes
log_step "Building cortex-iq-homes..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_homes/Dockerfile" \
  -t macula/cortex-iq-homes:latest \
  -t "$REGISTRY/macula/cortex-iq-homes:latest" \
  "$PROJECT_ROOT/system"
log_info "Built cortex-iq-homes"

log_step "Pushing cortex-iq-homes..."
docker push "$REGISTRY/macula/cortex-iq-homes:latest"
log_info "Pushed cortex-iq-homes"

# Build and push utilities
log_step "Building cortex-iq-utilities..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_utilities/Dockerfile" \
  -t macula/cortex-iq-utilities:latest \
  -t "$REGISTRY/macula/cortex-iq-utilities:latest" \
  "$PROJECT_ROOT/system"
log_info "Built cortex-iq-utilities"

log_step "Pushing cortex-iq-utilities..."
docker push "$REGISTRY/macula/cortex-iq-utilities:latest"
log_info "Pushed cortex-iq-utilities"

# Build and push simulation
log_step "Building cortex-iq-simulation..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_simulation/Dockerfile" \
  -t macula/cortex-iq-simulation:latest \
  -t "$REGISTRY/macula/cortex-iq-simulation:latest" \
  "$PROJECT_ROOT/system"
log_info "Built cortex-iq-simulation"

log_step "Pushing cortex-iq-simulation..."
docker push "$REGISTRY/macula/cortex-iq-simulation:latest"
log_info "Pushed cortex-iq-simulation"

# Build and push dashboard
log_step "Building cortex-iq-dashboard..."
docker build \
  -f "$PROJECT_ROOT/Dockerfile.hub" \
  -t macula/cortex-iq-dashboard:latest \
  -t "$REGISTRY/macula/cortex-iq-dashboard:latest" \
  "$PROJECT_ROOT"
log_info "Built cortex-iq-dashboard"

log_step "Pushing cortex-iq-dashboard..."
docker push "$REGISTRY/macula/cortex-iq-dashboard:latest"
log_info "Pushed cortex-iq-dashboard"

# Build and push projections
log_step "Building cortex-iq-projections..."
docker build \
  -f "$PROJECT_ROOT/system/cortex_iq_projections/Dockerfile" \
  -t macula/cortex-iq-projections:latest \
  -t "$REGISTRY/macula/cortex-iq-projections:latest" \
  "$PROJECT_ROOT/system"
log_info "Built cortex-iq-projections"

log_step "Pushing cortex-iq-projections..."
docker push "$REGISTRY/macula/cortex-iq-projections:latest"
log_info "Pushed cortex-iq-projections"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ All Images Built and Pushed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Images in registry:"
curl -s http://$REGISTRY/v2/_catalog | jq -r '.repositories[]' | sort | sed 's/^/  - /'
echo ""
echo "View in UI: http://registry.macula.local:5000"
echo ""
