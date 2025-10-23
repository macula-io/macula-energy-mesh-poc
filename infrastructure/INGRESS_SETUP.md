# nginx-ingress Setup for KinD Clusters

## Overview
This document describes the nginx-ingress setup for the Macula Platform KinD clusters, enabling HTTP/HTTPS access to services without port-forwarding.

## Architecture

### Clusters
- **macula-hub** (172.20.0.2) - Hub cluster with Bondy WAMP router
- **macula-edge-01** (172.21.0.2) - Edge cluster with Dashboard + Homes
- **macula-edge-02** (172.22.0.2) - Edge cluster with Homes
- **macula-edge-03** (172.23.0.2) - Edge cluster with Homes
- **macula-edge-04** (172.24.0.2) - Edge cluster with Utilities

### nginx-ingress Controllers
Each cluster has its own nginx-ingress controller deployed to the `ingress-nginx` namespace:
- Controller listens on hostPort 8080 (HTTP) and 8443 (HTTPS)
- Uses IngressClass `nginx` (default)
- NodePort service on 30180/30143 as backup

## Deployed Services

### ✅ Working Services

#### Bondy Admin API
- **URL**: http://hub.macula.local:8080/admin/
- **Ingress**: `gitops/kind/hub/bondy/ingress.yaml`
- **Backend**: bondy.macula-hub:18081
- **Features**:
  - Path-based routing with regex
  - Admin API on `/admin/*` → port 18081
  - API Gateway on `/*` → port 18080

#### Bondy Web Console
- **URL**: http://console.macula.local:8080/
- **Ingress**: `gitops/kind/hub/bondy-console/ingress.yaml`
- **Backend**: bondy-console.macula-hub:8080
- **Features**:
  - Full web UI for Bondy management
  - WebSocket support for real-time updates
  - Connects to Bondy Admin API internally

### ✅ Dashboard (Working)

#### CortexIQ Dashboard
- **URL**: http://dashboard.macula.local:8080/
- **Ingress**: `gitops/kind/base/cortex-iq-dashboard/ingress.yaml`
- **Backend**: cortex-iq-dashboard.macula-system:4000
- **Status**: ✅ Working - HTTP 200 OK
- **Features**:
  - Phoenix LiveView dashboard
  - Real-time energy exchange visualization
  - WebSocket support for live updates
  - Leaflet.js maps and ApexCharts

## Files Created

### nginx-ingress Controller (Base)
```
gitops/kind/base/nginx-ingress/
├── controller.yaml        # Main controller deployment
├── rbac.yaml             # RBAC permissions
├── ingress-class.yaml    # IngressClass definition
└── kustomization.yaml    # Kustomize config
```

### Bondy Ingress (Hub)
```
gitops/kind/hub/bondy/
├── ingress.yaml          # Path-based routing
└── service.yaml          # Updated with admin-api port 18081
```

### Bondy Console (Hub)
```
gitops/kind/hub/bondy-console/
├── namespace.yaml        # Shared macula-hub namespace
├── configmap.yaml        # Console configuration
├── deployment.yaml       # Console deployment
├── service.yaml          # Console service
├── ingress.yaml          # Console ingress
└── kustomization.yaml    # Kustomize config
```

### Dashboard Ingress (Edge-01)
```
gitops/kind/base/cortex-iq-dashboard/
├── ingress.yaml          # Dashboard ingress with WebSocket support
└── kustomization.yaml    # Updated to include ingress
```

### Helper Scripts
```
scripts/
├── setup-ingress.sh      # Deploy nginx-ingress to all clusters
└── setup-hosts.sh        # Configure /etc/hosts with DNS mappings
```

## DNS Configuration

### /etc/hosts Entries
```
# Macula Platform - KinD Cluster Ingress
172.20.0.2      hub.macula.local console.macula.local
172.21.0.2      dashboard.macula.local
172.22.0.2      edge02.macula.local
172.23.0.2      edge03.macula.local
172.24.0.2      edge04.macula.local
```

### Managing /etc/hosts
```bash
# Update /etc/hosts (requires sudo)
cd infrastructure
sudo ./scripts/setup-hosts.sh

# Dry-run (show what would be added)
./scripts/setup-hosts.sh
```

## Deployment

### Initial Setup
```bash
cd infrastructure

# Deploy nginx-ingress to all clusters
./scripts/setup-ingress.sh

# Configure /etc/hosts
sudo ./scripts/setup-hosts.sh
```

### Updating Ingress Resources
```bash
# Update Bondy ingress
kubectl --context kind-macula-hub apply -f gitops/kind/hub/bondy/ingress.yaml

# Update Bondy Console
kubectl --context kind-macula-hub apply -k gitops/kind/hub/bondy-console

# Update Dashboard ingress
kubectl --context kind-macula-edge-01 apply -f gitops/kind/base/cortex-iq-dashboard/ingress.yaml
```

### Restarting nginx-ingress
```bash
# Restart controller in hub cluster
kubectl --context kind-macula-hub rollout restart deployment/ingress-nginx-controller -n ingress-nginx

# Restart controller in edge-01 cluster
kubectl --context kind-macula-edge-01 rollout restart deployment/ingress-nginx-controller -n ingress-nginx
```

## Testing

### Verify Deployment
```bash
# Check ingress controller status
kubectl --context kind-macula-hub get pods -n ingress-nginx

# Check ingress resources
kubectl --context kind-macula-hub get ingress -A
```

### Test Endpoints
```bash
# Bondy Admin API
curl http://hub.macula.local:8080/admin/realms | jq '.[] | .uri'

# Bondy Web Console (in browser)
open http://console.macula.local:8080/

# Dashboard (currently 502 - app issue)
curl http://dashboard.macula.local:8080/
```

## Troubleshooting

### 502 Bad Gateway
- **Symptom**: nginx returns 502 when accessing service
- **Cause**: Backend service not responding
- **Debug**:
  ```bash
  # Check backend pod
  kubectl --context <context> get pods -n <namespace>

  # Check service endpoints
  kubectl --context <context> get endpoints <service> -n <namespace>

  # Check if service is listening
  kubectl --context <context> exec -n <namespace> deploy/<name> -- ss -tlnp
  ```

### 503 Service Unavailable
- **Symptom**: nginx returns 503
- **Cause**: No backend endpoints available
- **Debug**:
  ```bash
  # Check if ingress controller can find endpoints
  kubectl --context <context> logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
  ```

### DNS Not Resolving
- **Symptom**: `curl: (6) Could not resolve host`
- **Cause**: /etc/hosts not configured
- **Fix**:
  ```bash
  sudo ./scripts/setup-hosts.sh
  cat /etc/hosts | grep macula
  ```

## Known Issues

None - All services working correctly!

## Future Enhancements

1. **TLS/HTTPS Support**
   - Generate self-signed certificates for *.macula.local
   - Update ingress resources with TLS configuration
   - Access services via https://

2. **Additional Ingress Resources**
   - Add ingress for edge-02, edge-03, edge-04 clusters
   - Create edge02.macula.local, etc.

3. **LoadBalancer MetalLB**
   - Deploy MetalLB for true LoadBalancer support
   - Eliminate need for hostPort binding
   - Use standard HTTP ports (80/443)

4. **Cert-Manager Integration**
   - Automate certificate management
   - Support Let's Encrypt for public domains
   - Automatic certificate renewal

## References

- [nginx-ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [KinD Ingress Guide](https://kind.sigs.k8s.io/docs/user/ingress/)
- [Bondy Documentation](https://docs.bondy.io/)
