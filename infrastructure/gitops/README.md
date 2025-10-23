# Macula GitOps Repository

This directory contains Kustomize manifests for deploying CortexIQ payloads to Macula edge clusters via FluxCD.

## Structure

```
gitops/
├── base/                          # Base manifests
│   ├── macula-os/                 # MaculaOs platform resources
│   ├── cortex-iq-homes/           # Home bots payload
│   └── cortex-iq-utilities/       # Provider bots payload
│
├── overlays/                      # Environment-specific patches
│   ├── edge-01/                   # 13 home bots
│   ├── edge-02/                   # 13 home bots
│   ├── edge-03/                   # 5 provider bots
│   └── edge-04/                   # 11 home bots
│
└── clusters/                      # Cluster entry points (for FluxCD)
    ├── macula-edge-01/
    ├── macula-edge-02/
    ├── macula-edge-03/
    └── macula-edge-04/
```

## Payload Distribution

- **edge-01**: 13 home bots
- **edge-02**: 13 home bots
- **edge-03**: 5 provider bots (utilities)
- **edge-04**: 11 home bots

**Total**: 37 homes + 5 providers = 42 simulated agents

## FluxCD Bootstrap

Each edge cluster is bootstrapped with FluxCD pointing to its cluster directory:

```bash
# On edge-01
flux bootstrap git \
  --url=ssh://git@github.com/macula-io/macula-energy-mesh-poc \
  --branch=main \
  --path=infrastructure/gitops/clusters/macula-edge-01

# On edge-02
flux bootstrap git \
  --url=ssh://git@github.com/macula-io/macula-energy-mesh-poc \
  --branch=main \
  --path=infrastructure/gitops/clusters/macula-edge-02

# ... and so on
```

## Deployment Workflow

1. **Developer pushes code change**:
   ```bash
   vim system/apps/cortex_iq_homes/lib/cortex_iq_homes/home_bot.ex
   git commit -am "Optimize battery usage algorithm"
   git push
   ```

2. **Build new Docker image**:
   ```bash
   cd infrastructure/docker
   ./build.sh
   docker push macula/cortex-iq-homes:v1.2.0
   ```

3. **Update manifest**:
   ```bash
   vim infrastructure/gitops/base/cortex-iq-homes/deployment.yaml
   # Change image: macula/cortex-iq-homes:v1.2.0
   git commit -am "Deploy homes v1.2.0"
   git push
   ```

4. **FluxCD auto-deploys** (within 1 minute):
   - Detects git commit
   - Reconciles cluster state
   - Pulls new image
   - Rolls out deployment

5. **Verify**:
   ```bash
   macula-ctl flux edge-01 status
   macula-ctl logs edge-01 cortex-iq-homes
   ```

## Manual Reconciliation

Force FluxCD to sync immediately:

```bash
# Via macula-ctl
macula-ctl flux edge-01 reconcile

# Or directly via SSH
ssh ubuntu@192.168.100.11 "flux reconcile kustomization flux-system --with-source"
```

## Testing Locally

Validate manifests before pushing:

```bash
# Build kustomization
kustomize build overlays/edge-01

# Apply to test cluster
kustomize build overlays/edge-01 | kubectl apply --dry-run=client -f -
```

## Scaling Payloads

To change the number of bots on an edge:

```bash
# Edit overlay
vim overlays/edge-01/kustomization.yaml
# Change NUM_HOMES from 13 to 20

git commit -am "Scale edge-01 to 20 homes"
git push

# FluxCD will auto-deploy within 60 seconds
```

## Monitoring

View FluxCD status:

```bash
macula-ctl flux edge-01 status
macula-ctl flux edge-02 status
macula-ctl flux edge-03 status
macula-ctl flux edge-04 status
```

View pod logs:

```bash
macula-ctl logs edge-01        # All pods
macula-ctl logs edge-03 cortex-iq-utilities  # Specific app
```

## Troubleshooting

### FluxCD not reconciling

```bash
# Check source controller
ssh ubuntu@192.168.100.11
kubectl logs -n flux-system deploy/source-controller

# Check kustomize controller
kubectl logs -n flux-system deploy/kustomize-controller

# Force reconcile
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

### Pods not starting

```bash
# Check pod status
kubectl get pods -n macula-system

# Check events
kubectl describe pod <pod-name> -n macula-system

# Check logs
kubectl logs <pod-name> -n macula-system
```

### Image pull errors

Ensure Docker images are pushed to a registry accessible from the cluster:

```bash
# Check image exists
docker pull macula/cortex-iq-homes:latest

# Push to DockerHub
docker tag macula/cortex-iq-homes:latest yourusername/cortex-iq-homes:latest
docker push yourusername/cortex-iq-homes:latest

# Update manifest to use public image
vim base/cortex-iq-homes/deployment.yaml
```

## Notes

- FluxCD polls Git every 60 seconds by default
- Use `flux reconcile` to force immediate sync
- All changes should go through Git (GitOps principle)
- Never `kubectl apply` directly - use GitOps workflow
