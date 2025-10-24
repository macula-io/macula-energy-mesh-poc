#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../gitops/kind"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if cluster exists
cluster_exists() {
    local cluster=$1
    kind get clusters 2>/dev/null | grep -q "^${cluster}$"
}

# Deploy nginx-ingress to a cluster
deploy_nginx_ingress() {
    local cluster=$1
    local context="kind-${cluster}"

    log_info "Deploying nginx-ingress to ${cluster}..."

    # Create ingress-nginx namespace
    kubectl --context "${context}" create namespace ingress-nginx --dry-run=client -o yaml | \
        kubectl --context "${context}" apply -f -

    # Apply nginx-ingress base manifests
    kubectl --context "${context}" apply -k "${GITOPS_DIR}/base/nginx-ingress"

    # Wait for nginx-ingress controller to be ready
    log_info "Waiting for nginx-ingress controller in ${cluster}..."
    kubectl --context "${context}" wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s || {
        log_error "Failed to wait for nginx-ingress controller in ${cluster}"
        return 1
    }

    log_info "✓ nginx-ingress deployed successfully to ${cluster}"
}

# Deploy Ingress resources to hub cluster
deploy_hub_ingress() {
    local context="kind-macula-hub"

    log_info "Deploying Bondy Ingress to macula-hub..."
    kubectl --context "${context}" apply -f "${GITOPS_DIR}/hub/bondy/ingress.yaml"

    log_info "✓ Bondy Ingress deployed to macula-hub"
}

# Deploy Ingress resources to edge-01 cluster
deploy_edge01_ingress() {
    local context="kind-macula-edge-01"

    log_info "Deploying Dashboard Ingress to macula-edge-01..."
    kubectl --context "${context}" apply -f "${GITOPS_DIR}/base/cortex-iq-dashboard/ingress.yaml"

    log_info "✓ Dashboard Ingress deployed to macula-edge-01"
}

# Verify ingress deployment
verify_ingress() {
    local cluster=$1
    local context="kind-${cluster}"

    log_info "Verifying ingress in ${cluster}..."

    # Check if ingress controller is running
    local controller_pods
    controller_pods=$(kubectl --context "${context}" get pods -n ingress-nginx \
        -l app.kubernetes.io/component=controller \
        -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")

    if [[ "${controller_pods}" == *"Running"* ]]; then
        log_info "✓ Ingress controller running in ${cluster}"
    else
        log_warn "⚠ Ingress controller not running in ${cluster}"
        return 1
    fi

    # List ingress resources
    local ingress_count
    ingress_count=$(kubectl --context "${context}" get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)

    if [[ ${ingress_count} -gt 0 ]]; then
        log_info "✓ Found ${ingress_count} Ingress resource(s) in ${cluster}"
        kubectl --context "${context}" get ingress --all-namespaces
    else
        log_info "  No Ingress resources in ${cluster}"
    fi
}

main() {
    log_info "========================================"
    log_info "Setting up nginx-ingress for KinD clusters"
    log_info "========================================"
    echo

    # List of clusters
    local clusters=(
        "macula-hub"
        "macula-edge-01"
        "macula-edge-02"
        "macula-edge-03"
        "macula-edge-04"
    )

    # Check that all clusters exist
    log_info "Checking for KinD clusters..."
    for cluster in "${clusters[@]}"; do
        if ! cluster_exists "${cluster}"; then
            log_error "Cluster ${cluster} does not exist. Run setup-kind.sh first."
            exit 1
        fi
    done
    log_info "✓ All clusters found"
    echo

    # Deploy nginx-ingress to all clusters
    log_info "Deploying nginx-ingress controllers..."
    for cluster in "${clusters[@]}"; do
        deploy_nginx_ingress "${cluster}" || {
            log_error "Failed to deploy nginx-ingress to ${cluster}"
            exit 1
        }
    done
    echo

    # Deploy Ingress resources
    log_info "Deploying Ingress resources..."
    deploy_hub_ingress || {
        log_error "Failed to deploy Bondy Ingress"
        exit 1
    }

    deploy_edge01_ingress || {
        log_error "Failed to deploy Dashboard Ingress"
        exit 1
    }
    echo

    # Verify all deployments
    log_info "Verifying ingress deployments..."
    for cluster in "${clusters[@]}"; do
        verify_ingress "${cluster}"
    done
    echo

    log_info "========================================"
    log_info "✓ nginx-ingress setup complete!"
    log_info "========================================"
    echo
    log_info "Next steps:"
    log_info "1. Run ./setup-hosts.sh to configure /etc/hosts"
    log_info "2. Test connectivity:"
    log_info "   - http://hub.macula.local:8080/api/status"
    log_info "   - http://dashboard.cortexiq.local:8080/"
}

main "$@"
