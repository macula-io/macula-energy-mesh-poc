# Macula Platform - Demo Environment

Local multi-cluster environment for development and demonstration.

## Quick Start

### 1. Install Prerequisites

```bash
# Install k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Verify installation
k3d version
kubectl version --client
helm version
```

### 2. Create Demo Clusters

```bash
# Create 5 clusters (home-a, home-b, business-a, business-b, regional-hub)
chmod +x k3d-setup.sh
./k3d-setup.sh create
```

This creates:
- **home-a**: 1 server + 2 agents → http://localhost:8081
- **home-b**: 1 server + 2 agents → http://localhost:8082
- **business-a**: 1 server + 3 agents → http://localhost:8083
- **business-b**: 1 server + 2 agents → http://localhost:8084
- **regional-hub**: 1 server + 2 agents → http://localhost:8080

### 3. Verify Clusters

```bash
# Show status
./k3d-setup.sh status

# Check resource usage
./k3d-setup.sh resources

# List all clusters
k3d cluster list
```

### 4. Switch Between Clusters

```bash
# Switch to home-a
kubectl config use-context k3d-home-a

# List nodes
kubectl get nodes

# Switch to regional-hub
kubectl config use-context k3d-regional-hub
```

## Demo Scenarios

### Scenario 1: Offline Operation

```bash
# Stop home-a cluster (simulates offline)
k3d cluster stop home-a

# Verify payloads keep running locally
kubectl config use-context k3d-home-a
# (cluster is offline, but last state is cached)

# Restart cluster
k3d cluster start home-a

# Watch event sync
kubectl logs -n macula-system -l app=bondy -f
```

### Scenario 2: GitOps Deployment

```bash
# Deploy a payload via ArgoCD
kubectl config use-context k3d-home-a

# Create application
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cortex-iq-homes
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/macula-io/macula-platform
    path: payloads/charts/cortex-iq-homes
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: macula-payloads
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Watch deployment
kubectl get pods -n macula-payloads -w
```

### Scenario 3: Cross-Cluster Messaging

```bash
# Publish from home-a, subscribe in business-a
# (requires Bondy federation - see platform/charts/bondy)
```

## Resource Usage

Expected usage on your 128GB / 32-core desktop:

```
15 containers (5 clusters × 3 nodes avg)
~20GB RAM
~15 cores

Leaves:
~108GB RAM available
~17 cores available
```

## Cleanup

```bash
# Delete all clusters
./k3d-setup.sh delete

# Verify cleanup
k3d cluster list
docker ps | grep k3d
```

## Troubleshooting

### Cluster won't start

```bash
# Check Docker
docker ps

# Restart Docker daemon
sudo systemctl restart docker

# Recreate cluster
k3d cluster delete home-a
k3d cluster create home-a --servers 1 --agents 2
```

### Port conflicts

```bash
# Check what's using the port
sudo lsof -i :8081

# Change port in k3d-setup.sh
# Edit CLUSTERS array and rebuild
```

### Out of resources

```bash
# Check Docker resources
docker info | grep -i memory

# Reduce number of clusters or agents
# Edit CLUSTERS array in k3d-setup.sh
```

## Next Steps

1. Deploy Bondy on each cluster: `kubectl apply -f ../platform/charts/bondy/`
2. Install ArgoCD: `kubectl apply -f ../platform/charts/argocd/`
3. Deploy payloads: `kubectl apply -f ../payloads/charts/`
4. Open MaculaCtrl: http://localhost:8080
