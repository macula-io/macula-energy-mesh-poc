#!/bin/bash
set -euo pipefail

# Restart services after deploying metrics system
# This script restarts projections and dashboard to pick up new images from registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo -e "${CYAN}Restarting Metrics Services${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Restart projections (hub cluster)
log_step "Restarting cortex-iq-projections on macula-hub..."
kubectl --context kind-macula-hub delete pods -n macula-hub -l app=cortex-iq-projections
log_info "Projections pods deleted - will pull new image on restart"

# Restart dashboard (hub cluster)
log_step "Restarting cortex-iq-dashboard on macula-hub..."
kubectl --context kind-macula-hub delete pods -n macula-hub -l app=cortex-iq-dashboard
log_info "Dashboard pods deleted - will pull new image on restart"

echo ""
log_step "Waiting for pods to come back up..."
sleep 5

# Check projections status
log_step "Checking projections status..."
kubectl --context kind-macula-hub get pods -n macula-hub -l app=cortex-iq-projections

echo ""

# Check dashboard status
log_step "Checking dashboard status..."
kubectl --context kind-macula-hub get pods -n macula-hub -l app=cortex-iq-dashboard

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Services Restarted!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Metrics flow:"
echo "  Events → CalculateMetrics (projections)"
echo "  → macula.metrics.totals_calculated"
echo "  → SubscribeMetricsTotals (dashboard)"
echo "  → Phoenix.PubSub (dashboard:metrics_totals)"
echo "  → LiveView"
echo ""
echo "Check logs:"
echo "  kubectl --context kind-macula-hub logs -n macula-hub -l app=cortex-iq-projections --tail=50"
echo "  kubectl --context kind-macula-hub logs -n macula-hub -l app=cortex-iq-dashboard --tail=50"
echo ""
