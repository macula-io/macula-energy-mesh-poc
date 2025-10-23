# KinD Deployment Guide - Macula Platform

Complete guide for deploying the Macula platform with CortexIQ on KinD clusters.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Hub Cluster (macula-hub)                                        │
│  - Bondy WAMP Router                                            │
│  - Ports: 30080 (WS), 30081 (Admin API)                        │
└─────────────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼────────────────┬────────────────┐
          │               │                │                │
    ┌─────▼─────┐   ┌────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
    │ Edge-01   │   │ Edge-02  │   │ Edge-03   │   │ Edge-04   │
    │ Dashboard │   │ 13 Homes │   │ 5 Utility │   │ 11 Homes  │
    │ + 13 Homes│   │          │   │ Providers │   │           │
    │ + Postgres│   │          │   │           │   │           │
    └───────────┘   └──────────┘   └───────────┘   └───────────┘
```

## Deployment Steps

### 1. Create KinD Clusters

```bash
cd infrastructure/kind
./create-clusters.sh
```

This creates 5 clusters:
- **macula-hub**: WAMP router hub
- **macula-edge-01** through **edge-04**: Edge nodes for payloads

### 2. Deploy Hub (Bondy)

```bash
kubectl --context kind-macula-hub apply -k ../gitops/kind/hub/bondy/
```

Verify Bondy is running:
```bash
kubectl --context kind-macula-hub get pods -n macula-hub
kubectl --context kind-macula-hub logs -n macula-hub -l app=bondy
```

### 3. Build and Load Container Images

Build all payload images and load them into the appropriate KinD clusters:

```bash
./build-and-load-images.sh
```

This script:
1. Builds `macula/os-base:latest` (base image with MaculaOs + cortex_iq_core)
2. Builds `macula/cortex-iq-dashboard:latest` (dashboard + web UI)
3. Builds `macula/cortex-iq-homes:latest` (home simulation bots)
4. Builds `macula/cortex-iq-utilities:latest` (energy provider bots)
5. Loads images into the appropriate edge clusters

**Note**: This may take 10-15 minutes depending on your machine.

### 4. Deploy Edge Payloads

Deploy to each edge cluster:

```bash
# Edge-01: Dashboard + Postgres + 13 Homes
kubectl --context kind-macula-edge-01 apply -k ../gitops/kind/clusters/edge-01/

# Edge-02: 13 Homes
kubectl --context kind-macula-edge-02 apply -k ../gitops/kind/clusters/edge-02/

# Edge-03: 5 Utility Providers
kubectl --context kind-macula-edge-03 apply -k ../gitops/kind/clusters/edge-03/

# Edge-04: 11 Homes (optional, completes 50 homes total)
kubectl --context kind-macula-edge-04 apply -k ../gitops/kind/clusters/edge-04/
```

### 5. Verify Deployment

Check pod status on all clusters:

```bash
./status.sh
```

Or manually:
```bash
kubectl --context kind-macula-edge-01 get pods -n macula-system
kubectl --context kind-macula-edge-02 get pods -n macula-system
kubectl --context kind-macula-edge-03 get pods -n macula-system
kubectl --context kind-macula-edge-04 get pods -n macula-system
```

### 6. Access Dashboard

The dashboard is exposed on edge-01 via NodePort 30000:

```bash
# Port forward from local machine
kubectl --context kind-macula-edge-01 port-forward \
  -n macula-system svc/cortex-iq-dashboard 4000:4000
```

Open http://localhost:4000 in your browser.

## Manifest Structure

```
infrastructure/gitops/kind/
├── hub/
│   └── bondy/                    # Hub: Bondy WAMP router only
│       ├── namespace.yaml
│       ├── configmap.yaml        # Bondy configuration
│       ├── deployment.yaml
│       ├── service.yaml
│       └── kustomization.yaml
│
├── base/                          # Base manifests for payloads
│   ├── cortex-iq-dashboard/      # Dashboard + PostgreSQL
│   │   ├── namespace.yaml
│   │   ├── postgres.yaml
│   │   ├── dashboard.yaml
│   │   └── kustomization.yaml
│   ├── cortex-iq-homes/          # Home simulation bots
│   │   ├── deployment.yaml
│   │   └── kustomization.yaml
│   └── cortex-iq-utilities/      # Provider bots
│       ├── deployment.yaml
│       └── kustomization.yaml
│
└── clusters/                      # Cluster-specific overlays
    ├── edge-01/                   # Dashboard + 13 homes
    │   └── kustomization.yaml
    ├── edge-02/                   # 13 homes
    │   └── kustomization.yaml
    ├── edge-03/                   # 5 providers
    │   └── kustomization.yaml
    └── edge-04/                   # 11 homes
        └── kustomization.yaml
```

## Payload Distribution

| Cluster | Payloads | Bots |
|---------|----------|------|
| macula-hub | Bondy WAMP router | - |
| macula-edge-01 | Dashboard, PostgreSQL, Homes | 13 homes |
| macula-edge-02 | Homes | 13 homes |
| macula-edge-03 | Utilities | 5 providers |
| macula-edge-04 | Homes | 11 homes |
| **Total** | | **50 homes, 5 providers** |

## Key Configuration

### Bondy Connection

All edge payloads connect to Bondy using Docker networking:
```
BONDY_WS_URL=ws://macula-hub-control-plane:30080/ws
```

This works because:
- KinD clusters are Docker containers
- They share Docker's default bridge network
- Container DNS resolves `<cluster-name>-control-plane`

### Environment Variables

**Dashboard**:
- `DATABASE_URL`: PostgreSQL connection (postgres service in macula-system)
- `SIMULATION_SPEED`: 105120 (1 sim year = 5 real minutes)
- `SECRET_KEY_BASE`: Phoenix secret (change in production)

**Homes**:
- `NUM_HOMES`: Number of home bots per deployment (13, 13, 11)

**Utilities**:
- `NUM_PROVIDERS`: Number of provider bots (5)

## Troubleshooting

### Images Not Found

If you see `ImagePullBackOff` errors:
```bash
# Check if image exists in cluster
docker exec macula-edge-01-control-plane crictl images | grep macula

# Reload image if needed
kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-01
```

### Pods CrashLooping

Check logs:
```bash
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-dashboard
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-homes
```

Common issues:
- Database connection failure (dashboard): Check if postgres pod is running
- Bondy connection failure: Check if Bondy is running on hub cluster
- Permission errors: Check security contexts in deployments

### Network Connectivity

Test connectivity from edge to hub:
```bash
kubectl --context kind-macula-edge-01 run -it --rm debug \
  --image=curlimages/curl --restart=Never \
  -- curl -v http://macula-hub-control-plane:30080
```

### Database Issues

Reset database:
```bash
kubectl --context kind-macula-edge-01 delete pod -n macula-system -l app=postgres
```

## Cleanup

Remove all clusters:
```bash
kind delete clusters macula-hub macula-edge-01 macula-edge-02 macula-edge-03 macula-edge-04
```

Or selectively:
```bash
kind delete cluster --name macula-edge-01
```

## Next Steps

### FluxCD GitOps (Optional)

For automatic deployment via GitOps, bootstrap FluxCD on edge clusters:

```bash
./bootstrap-flux.sh edge-01
./bootstrap-flux.sh edge-02
./bootstrap-flux.sh edge-03
./bootstrap-flux.sh edge-04
```

This will configure FluxCD to automatically apply manifests from the GitOps directory.

### Production Considerations

1. **Persistent Volumes**: Use PersistentVolumeClaims instead of emptyDir
2. **Secrets Management**: Use Kubernetes Secrets or external secret managers
3. **Resource Limits**: Tune based on actual usage patterns
4. **High Availability**: Scale Bondy and dashboard deployments
5. **Monitoring**: Add Prometheus/Grafana for observability
6. **Security**: Enable RBAC, network policies, and Pod Security Standards

## Performance Notes

**Resource Usage** (approximate):
- Hub cluster: 2-4GB RAM
- Each edge cluster: 1-2GB RAM
- Total: 6-12GB RAM

**Build Times**:
- Base image: 5-8 minutes
- Each payload: 2-3 minutes
- Total: ~15 minutes

**Startup Times**:
- Clusters: 30 seconds
- Bondy: 30-60 seconds
- Dashboard: 60-90 seconds (includes DB migration)
- Bots: 30 seconds

## Helpful Commands

```bash
# Watch all pods across clusters
watch -n 2 'for ctx in kind-macula-hub kind-macula-edge-01 kind-macula-edge-02 kind-macula-edge-03 kind-macula-edge-04; do echo "=== $ctx ==="; kubectl --context $ctx get pods -A; done'

# Stream logs from dashboard
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-dashboard -f

# Check Bondy realms
kubectl --context kind-macula-hub exec -it -n macula-hub deployment/bondy -- bondy realm list

# Restart a deployment
kubectl --context kind-macula-edge-01 rollout restart -n macula-system deployment/cortex-iq-dashboard
```
