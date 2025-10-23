#!/bin/bash
################################################################################
# Macula Platform - K3d Multi-Cluster Demo Setup
# Creates multiple K3s clusters in Docker for local development/demo
#
# Requirements:
# - Docker 20.10+
# - k3d 5.0+ (install: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash)
# - kubectl
# - helm 3+
################################################################################

set -e

# Configuration
CLUSTERS=(
    "home-a:2:8081"           # name:agents:port
    "home-b:2:8082"
    "business-a:3:8083"
    "business-b:2:8084"
    "regional-hub:2:8080"
)

K3S_IMAGE="rancher/k3s:v1.28.5-k3s1"
REGISTRY_NAME="macula-registry"
REGISTRY_PORT="5432"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! command -v k3d &> /dev/null; then
        log_error "k3d is not installed."
        log_info "Install with: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed."
        exit 1
    fi

    log_info "All prerequisites met ✓"
}

# Create local registry for container images
create_registry() {
    if docker ps | grep -q $REGISTRY_NAME; then
        log_info "Registry '$REGISTRY_NAME' already exists"
        return
    fi

    log_step "Creating local Docker registry..."

    k3d registry create $REGISTRY_NAME \
        --port 0.0.0.0:$REGISTRY_PORT

    log_info "Registry created at localhost:$REGISTRY_PORT"
}

# Create a single cluster
create_cluster() {
    local name=$1
    local agents=$2
    local port=$3

    log_step "Creating cluster: $name (agents: $agents, port: $port)"

    # Check if cluster already exists
    if k3d cluster list | grep -q $name; then
        log_warn "Cluster '$name' already exists - skipping"
        return
    fi

    # Create cluster
    k3d cluster create $name \
        --image $K3S_IMAGE \
        --servers 1 \
        --agents $agents \
        --port "$port:80@loadbalancer" \
        --registry-use k3d-$REGISTRY_NAME:$REGISTRY_PORT \
        --k3s-arg "--disable=traefik@server:0" \
        --k3s-arg "--disable=servicelb@server:0" \
        --wait \
        --timeout 120s

    log_info "Cluster '$name' created successfully"
}

# Create all clusters
create_all_clusters() {
    log_step "Creating ${#CLUSTERS[@]} clusters..."

    for cluster_spec in "${CLUSTERS[@]}"; do
        IFS=':' read -r name agents port <<< "$cluster_spec"
        create_cluster "$name" "$agents" "$port"
    done

    log_info "All clusters created ✓"
}

# Install platform components on a cluster
install_platform() {
    local cluster=$1

    log_step "Installing Macula platform on cluster: $cluster"

    # Switch context
    kubectl config use-context k3d-$cluster

    # Create namespaces
    kubectl create namespace macula-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace macula-payloads --dry-run=client -o yaml | kubectl apply -f -

    log_info "Platform components installed on '$cluster'"
}

# Install platform on all clusters
install_platform_all() {
    log_step "Installing Macula platform on all clusters..."

    for cluster_spec in "${CLUSTERS[@]}"; do
        IFS=':' read -r name _ _ <<< "$cluster_spec"
        install_platform "$name"
    done

    log_info "Platform installed on all clusters ✓"
}

# Show cluster status
show_status() {
    log_step "Cluster Status:"
    echo ""

    k3d cluster list

    echo ""
    log_step "Clusters Details:"
    echo ""

    for cluster_spec in "${CLUSTERS[@]}"; do
        IFS=':' read -r name agents port <<< "$cluster_spec"

        echo -e "${GREEN}$name${NC}"
        echo "  URL: http://localhost:$port"
        echo "  Nodes: 1 server + $agents agents"

        kubectl config use-context k3d-$name &>/dev/null
        echo -n "  Status: "
        kubectl get nodes --no-headers 2>/dev/null | wc -l | xargs -I {} echo "{} nodes ready"
        echo ""
    done
}

# Delete all clusters
delete_all() {
    log_step "Deleting all clusters..."

    for cluster_spec in "${CLUSTERS[@]}"; do
        IFS=':' read -r name _ _ <<< "$cluster_spec"

        if k3d cluster list | grep -q $name; then
            log_info "Deleting cluster: $name"
            k3d cluster delete $name
        fi
    done

    # Delete registry
    if docker ps -a | grep -q $REGISTRY_NAME; then
        log_info "Deleting registry: $REGISTRY_NAME"
        k3d registry delete k3d-$REGISTRY_NAME
    fi

    log_info "All clusters deleted ✓"
}

# Get kubeconfig for all clusters
get_kubeconfig() {
    log_step "Merging kubeconfig for all clusters..."

    # k3d automatically updates kubeconfig when creating clusters
    # Show current contexts
    echo ""
    kubectl config get-contexts | grep k3d-

    echo ""
    log_info "Switch context with: kubectl config use-context k3d-<cluster-name>"
}

# Show resource usage
show_resources() {
    log_step "Resource Usage:"
    echo ""

    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep k3d

    echo ""
    log_step "Total Resource Estimate:"

    local total_containers=$(docker ps | grep -c k3d || echo 0)
    echo "  Containers: $total_containers"

    # Rough estimate
    local estimated_ram=$((total_containers * 500))
    echo "  Estimated RAM: ~${estimated_ram}MB"
}

# Main help
show_help() {
    cat <<EOF
Macula Platform - K3d Multi-Cluster Demo Setup

Usage: $0 <command>

Commands:
    create              Create all clusters and install platform
    delete              Delete all clusters
    status              Show cluster status
    resources           Show resource usage
    kubeconfig          Get kubeconfig for all clusters
    install-platform    Install Macula platform on all clusters

Clusters Created:
EOF

    for cluster_spec in "${CLUSTERS[@]}"; do
        IFS=':' read -r name agents port <<< "$cluster_spec"
        echo "  - $name (1 server + $agents agents) → http://localhost:$port"
    done

    cat <<EOF

Examples:
    # Create all clusters
    $0 create

    # Check status
    $0 status

    # Switch to a cluster
    kubectl config use-context k3d-home-a

    # Delete everything
    $0 delete

Environment:
    - 128GB RAM, 32 cores → Can run all 5 clusters comfortably
    - Estimated usage: ~20GB RAM, 15 cores
EOF
}

# Main
main() {
    COMMAND="${1:-help}"

    case $COMMAND in
        create)
            check_prerequisites
            create_registry
            create_all_clusters
            install_platform_all
            show_status
            get_kubeconfig
            echo ""
            log_info "✓ Demo environment ready!"
            log_info "Next: kubectl config use-context k3d-home-a"
            ;;
        delete)
            delete_all
            ;;
        status)
            show_status
            ;;
        resources)
            show_resources
            ;;
        kubeconfig)
            get_kubeconfig
            ;;
        install-platform)
            install_platform_all
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
