# K3s Infrastructure

Scripts for bootstrapping K3s clusters on edge nodes (Raspberry Pi or x86).

## Quick Start

### Install K3s Server (Control Plane)

```bash
# On your Raspberry Pi or edge node
curl -sfL https://raw.githubusercontent.com/macula-io/macula-platform/main/infrastructure/k3s/bootstrap.sh | sudo bash -s server
```

### Install K3s Agent (Worker Node)

```bash
# On additional nodes
export SERVER_URL=https://192.168.1.100:6443
export CLUSTER_TOKEN=your-cluster-token

curl -sfL https://raw.githubusercontent.com/macula-io/macula-platform/main/infrastructure/k3s/bootstrap.sh | sudo bash -s agent
```

## Raspberry Pi Optimizations

The bootstrap script automatically detects Raspberry Pi and applies:
- Host-gw flannel backend (faster than vxlan)
- Cgroup enablement in `/boot/cmdline.txt`
- Lightweight configuration

## Post-Installation

After K3s is installed, deploy Macula platform components:

```bash
# Install Bondy (local WAMP router)
kubectl apply -f platform/charts/bondy/

# Install ArgoCD (GitOps)
kubectl apply -f platform/charts/argocd/

# Install MaculaOs sidecar injector
kubectl apply -f platform/admission-webhook/
```

## Monitoring

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# View K3s logs
sudo journalctl -u k3s -f
```

## Troubleshooting

### Node not ready

```bash
# Check K3s service
sudo systemctl status k3s

# Restart K3s
sudo systemctl restart k3s
```

### Pod scheduling issues

```bash
# Check node resources
kubectl describe node $(hostname)

# Check pod events
kubectl describe pod <pod-name>
```
