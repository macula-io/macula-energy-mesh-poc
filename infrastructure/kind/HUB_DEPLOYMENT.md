# Hub Deployment - Bondy WAMP Router

## Overview

The hub cluster runs **only** the Bondy WAMP router. The dashboard and all other payloads (including CortexIQ Dashboard) are deployed to edge clusters.

## Architecture

```
┌──────────────────────────────────────┐
│ macula-hub (KinD Cluster)           │
│                                      │
│  ┌────────────────────────────────┐ │
│  │ Namespace: macula-hub          │ │
│  │                                │ │
│  │  ┌──────────────────────────┐  │ │
│  │  │ Bondy WAMP Router        │  │ │
│  │  │ - Port 18080 (WS/HTTP)   │  │ │
│  │  │ - Port 18081 (Admin API) │  │ │
│  │  └──────────────────────────┘  │ │
│  └────────────────────────────────┘ │
│                                      │
│  Exposed via NodePort:               │
│  - 30080 → Bondy WS/HTTP (18080)     │
│  - 30081 → Bondy Admin API (18081)   │
└──────────────────────────────────────┘
```

## Deployment Details

### Resources Created

1. **Namespace**: `macula-hub`
2. **ConfigMap**: `bondy-config` (contains bondy.conf)
3. **Deployment**: `bondy` (1 replica, 2Gi-4Gi memory)
4. **Service**: `bondy` (NodePort, exposing 30080, 30081)

### Configuration

**Key Settings** (from bondy.conf):
- Anonymous access: Enabled (PoC only)
- Auto-create realms: Enabled
- WebSocket WAMP: Port 18080
- Admin API: Port 18081
- Store partitions: 16

**Security Context**:
- Runs as UID/GID 1000 (bondy user)
- fsGroup: 1000 (ensures volume permissions)

**Volumes**:
- Config: ConfigMap mounted at `/bondy/etc/bondy.conf`
- Data: emptyDir at `/bondy/data` (for runtime state)

### Verification

```bash
# Check pod status
kubectl --context kind-macula-hub get pods -n macula-hub

# Check logs
kubectl --context kind-macula-hub logs -n macula-hub -l app=bondy

# Test connectivity (from within cluster)
kubectl --context kind-macula-hub run -it --rm debug \
  --image=curlimages/curl --restart=Never \
  -- curl http://bondy.macula-hub:18080

# Port forward to local machine
kubectl --context kind-macula-hub port-forward \
  -n macula-hub svc/bondy 18080:18080
```

### Access from Edge Clusters

Edge pods can connect to Bondy using the Docker network:

```
BONDY_WS_URL=ws://macula-hub-control-plane:30080/ws
```

**Why this works**:
- KinD clusters are Docker containers
- They share Docker's default bridge network
- Containers can resolve each other via `<cluster-name>-control-plane`
- NodePort 30080 is exposed on the control-plane container

## Deployment Steps

1. **Create cluster**:
   ```bash
   ./kind/create-clusters.sh
   ```

2. **Deploy Bondy**:
   ```bash
   kubectl --context kind-macula-hub apply -k infrastructure/gitops/kind/hub/bondy/
   ```

3. **Verify**:
   ```bash
   kubectl --context kind-macula-hub get pods,svc -n macula-hub
   ```

## Manifest Structure

```
infrastructure/gitops/kind/hub/bondy/
├── namespace.yaml       # macula-hub namespace
├── configmap.yaml       # bondy.conf configuration
├── deployment.yaml      # Bondy deployment (leapsight/bondy:1.0.0-rc.14)
├── service.yaml         # NodePort service (30080, 30081)
└── kustomization.yaml   # Kustomize config
```

## Troubleshooting

### Common Issues

1. **Pod CrashLoopBackOff with "eacces" error**
   - **Cause**: Volume permission issues
   - **Fix**: Ensure securityContext with fsGroup: 1000 is set
   - **Fix**: Mount emptyDir at `/bondy/data`

2. **OOMKilled**
   - **Cause**: Insufficient memory
   - **Fix**: Increase memory limits (currently 4Gi)

3. **Connection refused from edge**
   - **Cause**: NodePort not accessible or wrong URL
   - **Fix**: Use `macula-hub-control-plane:30080` as hostname
   - **Fix**: Verify port mapping with `docker port <cluster-container>`

### Debug Commands

```bash
# Get detailed pod info
kubectl --context kind-macula-hub describe pod -n macula-hub -l app=bondy

# Check Bondy logs
kubectl --context kind-macula-hub logs -n macula-hub -l app=bondy -f

# Exec into pod
kubectl --context kind-macula-hub exec -it -n macula-hub \
  deployment/bondy -- /bin/bash

# Check connectivity from another cluster
kubectl --context kind-macula-edge-01 run -it --rm debug \
  --image=curlimages/curl --restart=Never \
  -- curl -v http://macula-hub-control-plane:30080
```

## Next Steps

1. Build and push container images for edge payloads
2. Create base manifests for edge payloads (dashboard, homes, utilities)
3. Set up FluxCD on edge clusters
4. Configure GitOps to deploy payloads to edges
5. Test end-to-end connectivity

## Notes

- **Dashboard is NOT on hub** - it's an edge payload
- Hub contains ONLY Bondy WAMP router
- No PostgreSQL on hub (dashboard DB will be on edge with dashboard)
- Single replica for PoC (could be scaled for production)
- EmptyDir volumes are ephemeral (use PersistentVolumes for production)
