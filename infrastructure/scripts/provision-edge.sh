#!/bin/bash
set -euo pipefail

# Provision Macula Edge VM
# Sets up K3d cluster and FluxCD

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <edge-name>"
  echo "  Example: $0 edge-01"
  exit 1
fi

EDGE_NAME=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$INFRA_DIR")"

# Edge VM IPs
declare -A EDGE_IPS=(
  [edge-01]="192.168.100.11"
  [edge-02]="192.168.100.12"
  [edge-03]="192.168.100.13"
  [edge-04]="192.168.100.14"
)

EDGE_IP="${EDGE_IPS[$EDGE_NAME]}"
SSH_KEY="$HOME/.ssh/macula_rsa"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no"
HUB_IP="192.168.100.10"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

ssh_exec() {
  ssh $SSH_OPTS ubuntu@$EDGE_IP "$@"
}

main() {
  log_info "=== Provisioning Edge VM: macula-$EDGE_NAME ($EDGE_IP) ==="

  # Check connectivity
  if ! ssh_exec "echo OK" &>/dev/null; then
    log_error "Cannot connect to Edge VM at $EDGE_IP"
    exit 1
  fi

  # Create K3d cluster
  log_info "Creating K3d cluster..."
  ssh_exec bash <<'EOF'
set -euo pipefail

CLUSTER_NAME="macula-edge"

# Check if cluster already exists
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME already exists, skipping creation"
else
  # Create single-node K3s cluster
  k3d cluster create $CLUSTER_NAME \
    --agents 0 \
    --servers 1 \
    --port "30000-30100:30000-30100@server:0" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait

  echo "K3d cluster created"
fi

# Configure kubectl
mkdir -p ~/.kube
k3d kubeconfig get $CLUSTER_NAME > ~/.kube/config
EOF

  # Install FluxCD
  log_info "Installing FluxCD..."
  ssh_exec bash <<'EOF'
set -euo pipefail

# Check if FluxCD is already installed
if kubectl get namespace flux-system &>/dev/null; then
  echo "FluxCD already installed, skipping"
else
  # Pre-create namespace
  kubectl create namespace flux-system

  # Bootstrap FluxCD (without Git repository for now)
  flux install

  echo "FluxCD installed"
fi
EOF

  # Deploy MaculaOs and payloads
  log_info "Deploying MaculaOs (edge mode) and payloads..."

  # Determine which payload to deploy based on edge name
  local PAYLOAD="cortex-iq-homes"
  local NUM_BOTS=13

  if [[ "$EDGE_NAME" == "edge-03" ]]; then
    PAYLOAD="cortex-iq-utilities"
    NUM_BOTS=5
  fi

  ssh_exec bash <<EOF
set -euo pipefail

# Create macula-system namespace
kubectl create namespace macula-system --dry-run=client -o yaml | kubectl apply -f -

# Deploy MaculaOs (edge mode) - placeholder, will use GitOps later
cat <<MACULA_DEPLOY | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: macula-os-config
  namespace: macula-system
data:
  MACULA_MODE: "edge"
  REALM_URI: "be.cortexiq.energy"
  BONDY_WS_URL: "ws://$HUB_IP:18080/ws"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: macula-os
  namespace: macula-system
  labels:
    app: macula-os
spec:
  replicas: 1
  selector:
    matchLabels:
      app: macula-os
  template:
    metadata:
      labels:
        app: macula-os
    spec:
      containers:
      - name: macula-os
        image: busybox:latest  # Placeholder - will be replaced with real image
        command: ["sleep", "infinity"]
        envFrom:
        - configMapRef:
            name: macula-os-config
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $PAYLOAD
  namespace: macula-system
  labels:
    app: $PAYLOAD
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $PAYLOAD
  template:
    metadata:
      labels:
        app: $PAYLOAD
    spec:
      containers:
      - name: $PAYLOAD
        image: busybox:latest  # Placeholder - will be replaced with real image
        command: ["sleep", "infinity"]
        env:
        - name: NUM_BOTS
          value: "$NUM_BOTS"
        - name: BONDY_WS_URL
          value: "ws://$HUB_IP:18080/ws"
        - name: REALM_URI
          value: "be.cortexiq.energy"
MACULA_DEPLOY

echo "MaculaOs and $PAYLOAD deployed (placeholder images)"
EOF

  log_info ""
  log_info "=== Edge VM Provisioned Successfully ==="
  log_info "Cluster: macula-edge on $EDGE_IP"
  log_info "Payload: $PAYLOAD with $NUM_BOTS bots"
  log_info ""
  log_info "Access cluster:"
  log_info "  ssh $SSH_OPTS ubuntu@$EDGE_IP"
  log_info "  kubectl get pods -n macula-system"
  log_info ""
  log_info "Next: Build and push Docker images, then update manifests"
}

main "$@"
