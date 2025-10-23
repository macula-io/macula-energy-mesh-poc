# Macula on KinD - Architecture

## Overview

KinD (Kubernetes in Docker) based deployment of Macula platform - **much lighter than VMs!**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Host Machine (Docker)                                        │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ macula-hub (KinD cluster)                            │   │
│  │ ┌────────────────────────────────────────────────┐   │   │
│  │ │ Namespace: macula-hub                          │   │   │
│  │ │ - Bondy (WAMP router)                          │   │   │
│  │ │ - PostgreSQL                                   │   │   │
│  │ │ - Dashboard (Phoenix)                          │   │   │
│  │ └────────────────────────────────────────────────┘   │   │
│  │ Port: 30080 (Bondy WS), 30000 (Dashboard)           │   │
│  └──────────────────────────────────────────────────────┘   │
│           ▲              ▲              ▲              ▲     │
│           │              │              │              │     │
│  ┌────────┴────┐  ┌──────┴──────┐  ┌───┴──────┐  ┌───┴───┐ │
│  │ macula-     │  │ macula-     │  │ macula-  │  │ ...   │ │
│  │ edge-01     │  │ edge-02     │  │ edge-03  │  │       │ │
│  │ (KinD)      │  │ (KinD)      │  │ (KinD)   │  │       │ │
│  │             │  │             │  │          │  │       │ │
│  │ FluxCD      │  │ FluxCD      │  │ FluxCD   │  │       │ │
│  │ 13 homes    │  │ 13 homes    │  │ 5 utils  │  │       │ │
│  └─────────────┘  └─────────────┘  └──────────┘  └───────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Cluster Specifications

### Hub Cluster (macula-hub)
- **Purpose**: WAMP router + Dashboard
- **Namespaces**:
  - `macula-hub` - Bondy, Dashboard, PostgreSQL
- **Exposed Ports**:
  - 30080 → Bondy WebSocket
  - 30081 → Bondy HTTP API
  - 30000 → Phoenix Dashboard
  - 30432 → PostgreSQL (for debugging)

### Edge Clusters (macula-edge-01 through macula-edge-04)
- **Purpose**: Run payload containers
- **Namespaces**:
  - `macula-system` - MaculaOs + payloads
  - `flux-system` - FluxCD controllers
- **Resources per cluster**:
  - 1 control plane node
  - No exposed ports (connect to hub internally)

## Networking

### Docker Network
All KinD clusters connect via Docker's default bridge network:
```
docker network ls | grep kind
```

Clusters can reach each other via Docker DNS:
- Hub: `macula-hub-control-plane`
- Edges: `macula-edge-01-control-plane`, etc.

### WAMP Connection
Edge pods connect to hub via:
```
BONDY_WS_URL=ws://macula-hub-control-plane:30080/ws
```

## Deployment Flow

### 1. Create Clusters
```bash
./kind/create-clusters.sh
```

Creates:
- 1 hub cluster (macula-hub)
- 4 edge clusters (macula-edge-01 through 04)

### 2. Deploy Hub
```bash
kubectl --context kind-macula-hub apply -k gitops/kind/hub/
```

Deploys:
- Bondy WAMP router
- PostgreSQL
- Dashboard (Phoenix + LiveView)

### 3. Bootstrap FluxCD on Edges
```bash
./kind/bootstrap-flux.sh edge-01
./kind/bootstrap-flux.sh edge-02
./kind/bootstrap-flux.sh edge-03
./kind/bootstrap-flux.sh edge-04
```

Each edge:
- Installs FluxCD
- Points to gitops/kind/clusters/edge-XX/
- Auto-deploys payloads via GitOps

### 4. Verify
```bash
./kind/status.sh
```

Shows:
- ✓ All clusters running
- ✓ Hub services healthy
- ✓ Edge payloads deployed
- ✓ WAMP connections active

## Resource Requirements

**Much lighter than VMs!**

- **RAM**: 4-6GB (vs 12GB for VMs)
- **CPU**: 2-4 cores (vs 8+ for VMs)
- **Disk**: 10GB (vs 100GB for VMs)
- **Startup**: 30 seconds (vs 5+ minutes for VMs)

## Benefits Over VMs

| Aspect | VMs | KinD |
|--------|-----|------|
| Startup time | 5-10 minutes | 30 seconds |
| Resource usage | Heavy (12GB RAM) | Light (4-6GB RAM) |
| Cleanup | Manual, slow | `kind delete cluster` |
| Debugging | SSH, complex | `kubectl`, `docker logs` |
| Iteration | Slow (rebuild VMs) | Fast (redeploy pods) |
| Realistic | Very (actual VMs) | Very (actual K8s) |

## Quick Commands

```bash
# Create all clusters
./kind/create-clusters.sh

# List clusters
kind get clusters

# Get kubeconfig for a cluster
kind get kubeconfig --name macula-hub

# Access dashboard
kubectl --context kind-macula-hub port-forward -n macula-hub svc/dashboard 4000:4000
# Open http://localhost:4000

# View hub logs
kubectl --context kind-macula-hub logs -n macula-hub -l app=bondy

# View edge-01 pods
kubectl --context kind-macula-edge-01 get pods -n macula-system

# Cleanup
kind delete clusters macula-hub macula-edge-01 macula-edge-02 macula-edge-03 macula-edge-04
```

## GitOps Structure

```
infrastructure/gitops/kind/
├── hub/
│   ├── bondy/
│   ├── postgresql/
│   └── dashboard/
├── base/
│   ├── macula-os/
│   ├── cortex-iq-homes/
│   └── cortex-iq-utilities/
└── clusters/
    ├── edge-01/
    ├── edge-02/
    ├── edge-03/
    └── edge-04/
```

## Next Steps

1. Create clusters: `./kind/create-clusters.sh`
2. Deploy hub: Apply hub manifests
3. Bootstrap edges: FluxCD on each edge
4. Verify: `./kind/status.sh`
5. Access dashboard: Port-forward to localhost

**Much simpler than VMs!** 🚀
