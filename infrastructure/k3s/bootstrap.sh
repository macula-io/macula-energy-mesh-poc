#!/bin/bash
################################################################################
# Macula Platform - K3s Bootstrap Script
# Installs K3s on edge nodes (Raspberry Pi or x86)
################################################################################

set -e

# Configuration
K3S_VERSION="${K3S_VERSION:-v1.28.5+k3s1}"
CLUSTER_TOKEN="${CLUSTER_TOKEN:-macula-cluster-token-change-in-production}"
INSTALL_DIR="/usr/local/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
}

# Check if running on Raspberry Pi
is_raspberry_pi() {
    if [ -f /proc/device-tree/model ]; then
        grep -q "Raspberry Pi" /proc/device-tree/model
        return $?
    fi
    return 1
}

# Install K3s server (control plane)
install_server() {
    log_info "Installing K3s server (version: $K3S_VERSION)"

    INSTALL_ARGS=""

    # Raspberry Pi specific optimizations
    if is_raspberry_pi; then
        log_info "Detected Raspberry Pi - applying optimizations"
        INSTALL_ARGS="--flannel-backend=host-gw"

        # Enable cgroups for Raspberry Pi
        if ! grep -q "cgroup_memory=1 cgroup_enable=memory" /boot/cmdline.txt; then
            log_warn "Enabling cgroups in /boot/cmdline.txt (reboot required)"
            sudo sed -i '$ s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/cmdline.txt
        fi
    fi

    # Install K3s
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        K3S_TOKEN="$CLUSTER_TOKEN" \
        sh -s - server \
        --write-kubeconfig-mode=644 \
        --disable=traefik \
        --disable=servicelb \
        --cluster-init \
        $INSTALL_ARGS

    log_info "K3s server installed successfully"
    log_info "Kubeconfig: /etc/rancher/k3s/k3s.yaml"

    # Wait for node to be ready
    log_info "Waiting for node to be ready..."
    kubectl wait --for=condition=Ready node/$(hostname) --timeout=120s

    log_info "K3s server is ready!"
}

# Install K3s agent (worker node)
install_agent() {
    if [ -z "$SERVER_URL" ]; then
        log_error "SERVER_URL environment variable must be set for agent installation"
        log_error "Example: SERVER_URL=https://192.168.1.100:6443 ./bootstrap.sh agent"
        exit 1
    fi

    log_info "Installing K3s agent (server: $SERVER_URL)"

    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        K3S_URL="$SERVER_URL" \
        K3S_TOKEN="$CLUSTER_TOKEN" \
        sh -

    log_info "K3s agent installed successfully"
}

# Uninstall K3s
uninstall() {
    log_info "Uninstalling K3s..."

    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        /usr/local/bin/k3s-uninstall.sh
    elif [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
        /usr/local/bin/k3s-agent-uninstall.sh
    else
        log_warn "K3s uninstall script not found - K3s may not be installed"
    fi

    log_info "K3s uninstalled"
}

# Show status
show_status() {
    log_info "K3s Status:"
    kubectl get nodes
    echo ""
    kubectl get pods -A
}

# Main
main() {
    COMMAND="${1:-server}"

    case $COMMAND in
        server)
            install_server
            show_status
            ;;
        agent)
            install_agent
            ;;
        uninstall)
            uninstall
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {server|agent|uninstall|status}"
            echo ""
            echo "Commands:"
            echo "  server     - Install K3s server (control plane)"
            echo "  agent      - Install K3s agent (requires SERVER_URL env var)"
            echo "  uninstall  - Remove K3s"
            echo "  status     - Show cluster status"
            echo ""
            echo "Environment Variables:"
            echo "  K3S_VERSION     - K3s version (default: v1.28.5+k3s1)"
            echo "  CLUSTER_TOKEN   - Cluster join token"
            echo "  SERVER_URL      - Server URL for agent (e.g., https://192.168.1.100:6443)"
            exit 1
            ;;
    esac
}

main "$@"
