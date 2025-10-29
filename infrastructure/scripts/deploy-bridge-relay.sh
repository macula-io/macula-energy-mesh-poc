#!/usr/bin/env bash
##
## deploy-bridge-relay.sh - Deploy Bondy Bridge Relay architecture
##
## This script deploys the cross-cluster WAMP communication setup:
## - Hub on beam-01 (k3s) with bridge relay listener
## - Edge Bondy instances on KinD clusters with bridge relay clients
## - All CortexIQ workloads configured to use local edge Bondy
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GITOPS_DIR="$INFRA_DIR/gitops"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_context() {
    local context=$1
    if ! kubectl config get-contexts "$context" &>/dev/null; then
        log_error "Context $context not found in kubeconfig"
        return 1
    fi
    log_success "Context $context found"
    return 0
}

wait_for_pods() {
    local context=$1
    local namespace=$2
    local label=$3
    local timeout=${4:-300}

    log_info "Waiting for pods with label $label in namespace $namespace on $context..."

    if kubectl --context "$context" wait --for=condition=ready pod \
        -l "$label" \
        -n "$namespace" \
        --timeout="${timeout}s" 2>/dev/null; then
        log_success "Pods ready: $label"
        return 0
    else
        log_warn "Timeout waiting for pods: $label"
        return 1
    fi
}

##
## Deploy Hub on beam-01
##
deploy_hub() {
    log_info "=========================================="
    log_info "Deploying Hub on beam-01"
    log_info "=========================================="

    if ! check_context "beam01"; then
        log_error "beam01 context not configured. Please set up kubectl access to beam-01 k3s cluster."
        exit 1
    fi

    # Deploy Bondy Hub
    log_info "Deploying Bondy hub with bridge relay listener..."
    kubectl --context beam01 apply -k "$GITOPS_DIR/k3s/clusters/beam-01/bondy"

    # Wait for Bondy to be ready
    wait_for_pods "beam01" "macula-platform" "app=bondy"

    # Deploy PostgreSQL
    log_info "Deploying PostgreSQL/TimescaleDB..."
    kubectl --context beam01 apply -k "$GITOPS_DIR/k3s/clusters/beam-01/postgres"

    wait_for_pods "beam01" "macula-hub" "app=postgres"

    # Deploy hub applications
    log_info "Deploying dashboard..."
    kubectl --context beam01 apply -k "$GITOPS_DIR/k3s/clusters/beam-01/cortex-iq-dashboard"

    log_info "Deploying projections..."
    kubectl --context beam01 apply -k "$GITOPS_DIR/k3s/clusters/beam-01/cortex-iq-projections"

    log_info "Deploying queries..."
    kubectl --context beam01 apply -k "$GITOPS_DIR/k3s/clusters/beam-01/cortex-iq-queries"

    wait_for_pods "beam01" "macula-hub" "app=cortex-iq-dashboard" 180
    wait_for_pods "beam01" "macula-hub" "app=cortex-iq-projections" 180
    wait_for_pods "beam01" "macula-hub" "app=cortex-iq-queries" 180

    log_success "Hub deployment complete on beam-01"
    log_info ""
    log_info "Bondy Hub Bridge Relay Listener: tls://192.168.1.11:30093"
    log_info ""
}

##
## Deploy Edge Clusters (KinD)
##
deploy_edges() {
    log_info "=========================================="
    log_info "Deploying Edge Clusters (KinD)"
    log_info "=========================================="

    local edges=("edge-01" "edge-02" "edge-03" "edge-04")

    for edge in "${edges[@]}"; do
        local context="kind-macula-$edge"

        log_info "Deploying $edge..."

        if ! check_context "$context"; then
            log_warn "Skipping $edge - context not found"
            continue
        fi

        # Deploy Bondy edge with bridge relay client
        log_info "  - Deploying Bondy edge router..."
        kubectl --context "$context" apply -k "$GITOPS_DIR/kind/clusters/$edge/bondy"

        # Wait for Bondy edge to be ready
        wait_for_pods "$context" "macula-platform" "app=bondy-edge" 180

        # Deploy workloads
        log_info "  - Deploying workloads..."
        kubectl --context "$context" apply -k "$GITOPS_DIR/kind/clusters/$edge"

        sleep 5  # Give pods time to start

        log_success "$edge deployed"
        log_info ""
    done

    log_success "All edge clusters deployed"
}

##
## Verify Deployment
##
verify_deployment() {
    log_info "=========================================="
    log_info "Verifying Deployment"
    log_info "=========================================="

    # Check hub
    log_info "Hub (beam-01):"
    kubectl --context beam01 get pods -n macula-platform -l app=bondy -o wide || true
    kubectl --context beam01 get pods -n macula-hub -o wide || true
    log_info ""

    # Check edges
    for edge in edge-01 edge-02 edge-03 edge-04; do
        local context="kind-macula-$edge"
        if check_context "$context" &>/dev/null; then
            log_info "$edge:"
            kubectl --context "$context" get pods -n macula-platform -l app=bondy-edge -o wide || true
            kubectl --context "$context" get pods -n macula-apps -o wide || true
            log_info ""
        fi
    done

    log_info "=========================================="
    log_info "Deployment Complete!"
    log_info "=========================================="
    log_info ""
    log_info "Next steps:"
    log_info "1. Check bridge relay connectivity:"
    log_info "   kubectl --context beam01 logs -n macula-platform -l app=bondy --tail=50 | grep bridge"
    log_info ""
    log_info "2. Monitor events:"
    log_info "   kubectl --context beam01 logs -n macula-hub -l app=cortex-iq-projections -f"
    log_info ""
    log_info "3. Access dashboard:"
    log_info "   kubectl --context beam01 port-forward -n macula-hub svc/cortex-iq-dashboard 4000:4000"
    log_info "   Open http://localhost:4000"
    log_info ""
    log_info "See infrastructure/BRIDGE_RELAY_SETUP.md for troubleshooting and details."
}

##
## Main
##
main() {
    log_info "Macula Energy Mesh - Bridge Relay Deployment"
    log_info "=============================================="
    log_info ""

    # Check if we're in the right directory
    if [[ ! -d "$GITOPS_DIR" ]]; then
        log_error "GitOps directory not found: $GITOPS_DIR"
        log_error "Please run this script from the infrastructure directory"
        exit 1
    fi

    # Deploy hub
    deploy_hub

    # Wait a bit for hub to stabilize
    log_info "Waiting 30 seconds for hub to stabilize..."
    sleep 30

    # Deploy edges
    deploy_edges

    # Wait for everything to settle
    log_info "Waiting 30 seconds for pods to stabilize..."
    sleep 30

    # Verify
    verify_deployment
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
