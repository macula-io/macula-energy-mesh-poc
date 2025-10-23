# Macula Platform on KinD

Kubernetes-in-Docker (KinD) deployment for the Macula distributed application platform with CortexIQ energy trading simulation.

## Quick Start

Deploy the entire platform with one command:

```bash
./deploy-all.sh
```

This will:
1. Create 5 KinD clusters (1 hub + 4 edge)
2. Deploy Bondy WAMP router to hub
3. Build and load container images (~15 minutes)
4. Deploy payloads to edge clusters
5. Wait for all pods to be ready

## What Gets Deployed

### Hub Cluster (macula-hub)
- **Bondy WAMP Router** - Message routing and pub/sub
- Exposed ports: 30080 (WebSocket), 30081 (Admin API)

### Edge Clusters

| Cluster | Payloads | Description |
|---------|----------|-------------|
| **edge-01** | Dashboard + PostgreSQL + 13 Homes | Web UI, analytics, database, home bots |
| **edge-02** | 13 Homes | Home simulation bots |
| **edge-03** | 5 Utilities | Energy provider bots |
| **edge-04** | 11 Homes | Additional home bots (total: 50) |

**Total**: 50 homes, 5 energy providers, 1 dashboard

## Manual Deployment Steps

If you prefer step-by-step deployment:

### 1. Create Clusters

```bash
./create-clusters.sh
```

### 2. Deploy Hub

```bash
kubectl --context kind-macula-hub apply -k ../gitops/kind/hub/bondy/
```

### 3. Build and Load Images

```bash
./build-and-load-images.sh
```

### 4. Deploy Edge Payloads

```bash
# Edge-01: Dashboard + Homes
kubectl --context kind-macula-edge-01 apply -k ../gitops/kind/clusters/edge-01/

# Edge-02: Homes
kubectl --context kind-macula-edge-02 apply -k ../gitops/kind/clusters/edge-02/

# Edge-03: Utilities
kubectl --context kind-macula-edge-03 apply -k ../gitops/kind/clusters/edge-03/

# Edge-04: Homes
kubectl --context kind-macula-edge-04 apply -k ../gitops/kind/clusters/edge-04/
```

## Accessing the Dashboard

The CortexIQ dashboard is accessible via NodePort 30000 on edge-01:

```bash
# Option 1: Port forward (recommended)
kubectl --context kind-macula-edge-01 port-forward \
  -n macula-system svc/cortex-iq-dashboard 4000:4000

# Then open: http://localhost:4000
```

```bash
# Option 2: Direct access (find edge-01 IP first)
docker inspect macula-edge-01-control-plane | grep IPAddress
# Then: http://<IP>:30000
```

## Checking Status

```bash
# Quick status of all clusters
./status.sh

# Detailed hub status
kubectl --context kind-macula-hub get pods,svc -n macula-hub

# Detailed edge status
kubectl --context kind-macula-edge-01 get pods -n macula-system
kubectl --context kind-macula-edge-02 get pods -n macula-system
kubectl --context kind-macula-edge-03 get pods -n macula-system
kubectl --context kind-macula-edge-04 get pods -n macula-system
```

## Viewing Logs

```bash
# Bondy logs
kubectl --context kind-macula-hub logs -n macula-hub -l app=bondy -f

# Dashboard logs
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-dashboard -f

# Home bots logs
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-homes

# Provider bots logs
kubectl --context kind-macula-edge-03 logs -n macula-system -l app=cortex-iq-utilities
```

## Architecture

### Network Topology

```
Docker Bridge Network
    │
    ├── macula-hub-control-plane (Bondy on 30080, 30081)
    │
    ├── macula-edge-01-control-plane (Dashboard on 30000)
    │
    ├── macula-edge-02-control-plane
    │
    ├── macula-edge-03-control-plane
    │
    └── macula-edge-04-control-plane
```

### Communication

- **Edges → Hub**: Via Docker DNS `macula-hub-control-plane:30080`
- **WAMP Protocol**: WebSocket-based pub/sub and RPC
- **Dashboard**: Subscribes to all events for visualization
- **Bots**: Publish telemetry and state changes

## File Structure

```
infrastructure/kind/
├── README.md                      # This file
├── DEPLOYMENT_GUIDE.md            # Detailed deployment guide
├── HUB_DEPLOYMENT.md              # Hub-specific documentation
├── KIND_ARCHITECTURE.md           # Architecture overview
│
├── create-clusters.sh             # Create KinD clusters
├── status.sh                      # Check cluster status
├── build-and-load-images.sh       # Build and load images
├── deploy-all.sh                  # Complete deployment script
│
└── ../gitops/kind/                # Kubernetes manifests
    ├── hub/bondy/                 # Hub: Bondy WAMP router
    ├── base/                      # Base payload manifests
    │   ├── cortex-iq-dashboard/
    │   ├── cortex-iq-homes/
    │   └── cortex-iq-utilities/
    └── clusters/                   # Cluster-specific overlays
        ├── edge-01/
        ├── edge-02/
        ├── edge-03/
        └── edge-04/
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

## System Requirements

- **Docker**: Latest version
- **kind**: v0.20.0+
- **kubectl**: v1.28.0+
- **RAM**: 6-12GB (for all clusters)
- **Disk**: 20GB free space
- **CPU**: 4+ cores recommended

## Build Times

- Cluster creation: ~30 seconds
- Image builds: ~15 minutes (first time)
- Pod startup: ~2-3 minutes
- **Total**: ~20 minutes for complete deployment

## Troubleshooting

### Pods Not Starting

Check events:
```bash
kubectl --context kind-macula-edge-01 describe pod -n macula-system <pod-name>
```

### Image Pull Errors

Images are loaded into KinD with `imagePullPolicy: Never`. If you see pull errors:
```bash
# Rebuild and reload
./build-and-load-images.sh
```

### Connection Issues

Test Bondy connectivity from an edge:
```bash
kubectl --context kind-macula-edge-01 run -it --rm debug \
  --image=curlimages/curl --restart=Never \
  -- curl -v http://macula-hub-control-plane:30080
```

### Dashboard Not Loading

1. Check if PostgreSQL is ready
2. Check dashboard logs for migration errors
3. Verify Bondy is accessible

```bash
kubectl --context kind-macula-edge-01 get pods -n macula-system
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-dashboard
```

## Development Workflow

1. **Make code changes** in `system/apps/`
2. **Rebuild affected image**:
   ```bash
   docker build -f infrastructure/docker/Dockerfile.cortex-iq-homes \
     -t macula/cortex-iq-homes:latest .
   ```
3. **Reload into KinD**:
   ```bash
   kind load docker-image macula/cortex-iq-homes:latest --name macula-edge-01
   ```
4. **Restart deployment**:
   ```bash
   kubectl --context kind-macula-edge-01 rollout restart \
     -n macula-system deployment/cortex-iq-homes
   ```

## Next Steps

- **FluxCD**: Set up GitOps for automatic deployments
- **Monitoring**: Add Prometheus/Grafana
- **Scaling**: Increase replica counts for load testing
- **Production**: Use PersistentVolumes, proper secrets, and RBAC

## Resources

- [KinD Documentation](https://kind.sigs.k8s.io/)
- [Bondy WAMP Router](https://developer.bondy.io/)
- [Kustomize](https://kustomize.io/)
- Main project: `../../CLAUDE.md`

## Support

For issues specific to this KinD deployment:
1. Check logs with commands above
2. Review DEPLOYMENT_GUIDE.md for detailed troubleshooting
3. Verify Docker and Kubernetes are running correctly

---

**Last Updated**: 2025-10-23
**Platform Version**: Macula PoC
**Bondy Version**: 1.0.0-rc.14
**Kubernetes**: 1.27+ (via KinD)
