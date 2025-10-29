#!/bin/bash
set -euo pipefail

# --- Install prerequisites ---
echo "🔧 Installing prerequisites (curl, git)..."
sudo apt-get update -y
sudo apt-get install -y curl git

# --- Install k3s (single-node cluster) ---
echo "🚀 Installing k3s (single-node cluster)..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --disable traefik" sh -s -

# --- Verify k3s installation ---
echo "✅ Verifying k3s installation..."
sudo kubectl get nodes
sudo kubectl get pods -A

# --- Install Flux CD CLI ---
echo "🔧 Installing Flux CD CLI..."
curl -s https://fluxcd.io/install.sh | sudo bash

# --- Bootstrap Flux CD (GitOps) ---
echo "🌱 Bootstrapping Flux CD..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export GITHUB_USER="$GITHUB_USER"
export GITHUB_TOKEN="$GITHUB_TOKEN"
export GITHUB_REPO="$GITOPS_REPO"
export GITOPS_CLUSTER_PATH="./infrastructure/gitops/kind/clusters/$CLUSTER_NAME"
export GITOPS_BRANCH="feature/competition"

sudo -E flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$GITHUB_REPO" \
  --branch="$GITOPS_BRANCH" \
  --path="$GITOPS_CLUSTER_PATH" \
  --personal

# --- Verify Flux installation ---
echo "✅ Verifying Flux installation..."
sudo -E flux check

echo "🎉 k3s + Flux CD installation complete!"
echo "Your cluster is now managed via GitOps. Commit your manifests to $GITHUB_REPO to start reconciling!"
