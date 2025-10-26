# Macula Platform - Demo Quick Start Guide

**For Presenters:** Get the demo running in 5 minutes

---

## Prerequisites Check

```bash
# Verify clusters are running
kind get clusters
# Should show: macula-hub, macula-edge-01, macula-edge-02, macula-edge-03, macula-edge-04

# Verify images are loaded (if you just built them, skip this)
docker images | grep macula
# Should show: macula-os, cortex-iq-homes, cortex-iq-utilities, cortex-iq-dashboard
```

---

## 1. Deploy Everything (30 seconds)

```bash
# Deploy hub infrastructure (monitoring + portal)
kubectl --context kind-macula-hub apply -k infrastructure/gitops/kind/clusters/hub-01

# Deploy payloads to edges
kubectl --context kind-macula-edge-01 apply -k infrastructure/gitops/kind/clusters/edge-01
kubectl --context kind-macula-edge-02 apply -k infrastructure/gitops/kind/clusters/edge-02
kubectl --context kind-macula-edge-03 apply -k infrastructure/gitops/kind/clusters/edge-03
kubectl --context kind-macula-edge-04 apply -k infrastructure/gitops/kind/clusters/edge-04
```

---

## 2. Setup DNS (10 seconds)

```bash
sudo infrastructure/scripts/setup-hosts.sh
```

This adds entries to `/etc/hosts`:
- portal.macula.local ⭐
- hub.macula.local
- console.macula.local
- telemetry.macula.local
- analytics.macula.local
- dashboard.cortexiq.local

---

## 3. Wait for Pods (1-2 minutes)

```bash
# Watch pods come online
watch kubectl --context kind-macula-hub-01 get pods -n monitoring

# Should see:
# prometheus-xxx   1/1  Running
# grafana-xxx      1/1  Running

# Check edge pods (Ctrl+C to exit watch)
watch kubectl --context kind-macula-edge-01 get pods -n macula-system

# Should see:
# cortex-iq-dashboard-xxx   2/2  Running  <- Note: 2/2 (app + sidecar)
# cortex-iq-homes-xxx       2/2  Running
```

---

## 4. Access Portal

Open in browser: **http://portal.macula.local:8080**

**Note**: Portal is deployed to the hub cluster and accessible via ingress.

**Alternative (local development)**: If you prefer to run the portal locally:
```bash
./infrastructure/portal/serve.sh  # Then open http://localhost:3000
```

---

## 5. Demo Flow (10 minutes)

### A. Introduction (30 seconds)
1. Open portal: http://portal.macula.local:8080
2. "Welcome to Macula Platform - a distributed application platform for the BEAM"
3. "Notice how services are organized: Platform Infrastructure, Platform Observability, and Applications"

### B. Platform Infrastructure (1 minute)
1. Click **Bondy Admin API**
   - "This is our WAMP routing layer"
   - Show the API endpoints
2. Click **Bondy Console**
   - "Web-based management console"
   - Show realms, connections

### C. Platform Observability (2 minutes)
1. Click **Platform Telemetry**
   - "Notice we call it 'Telemetry' not Prometheus - business-friendly naming"
   - Show targets: Status > Targets
   - Show some queries: Graph tab
2. Click **Platform Analytics** (login: admin / macula123)
   - "Pre-configured dashboards"
   - Open "Macula Platform Overview" dashboard
   - Open "CortexIQ Energy Mesh" dashboard
   - Show pod counts, CPU/memory usage

### D. CortexIQ Application Demo (5-7 minutes)
1. Click **CortexIQ Dashboard**
   - Main demo - watch live energy trading
   - Home bots optimizing contracts
   - Real-time event stream
   - Charts and metrics

### E. Architecture Highlight (1 minute)
Go back to **Platform Analytics**, show:
- "Every application pod runs 2 containers"
- "App container + MaculaOs sidecar"
- Show sidecar resource usage graph
- "This enables multi-language support - any language can use the platform"

### F. Wrap Up (30 seconds)
- "Macula is the platform (like Kubernetes)"
- "CortexIQ is one application running on it"
- "Platform approach enables monetization via usage metering"
- "Business-friendly URLs make professional presentations"

---

## Quick Verification Commands

### Check All Pods Running
```bash
# Hub monitoring
kubectl --context kind-macula-hub-01 get pods -n monitoring

# Edge payloads
kubectl --context kind-macula-edge-01 get pods -n macula-system
kubectl --context kind-macula-edge-02 get pods -n macula-system
kubectl --context kind-macula-edge-03 get pods -n macula-system
kubectl --context kind-macula-edge-04 get pods -n macula-system
```

### Test Service URLs
```bash
# Quick test (should all return 200 OK)
curl -s -o /dev/null -w "%{http_code}" http://telemetry.macula.local:8080/
curl -s -o /dev/null -w "%{http_code}" http://analytics.macula.local:8080/
curl -s -o /dev/null -w "%{http_code}" http://dashboard.cortexiq.local:8080/
```

### View Logs
```bash
# Dashboard logs
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-dashboard -c dashboard

# Sidecar logs
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-dashboard -c macula-os

# Grafana logs
kubectl --context kind-macula-hub-01 logs -n monitoring -l app=grafana
```

---

## Troubleshooting

### Pods not starting?
```bash
# Describe pod to see events
kubectl --context kind-macula-edge-01 describe pod <pod-name> -n macula-system

# Common issues:
# - Image not loaded: Run build-and-load-images.sh again
# - API key secret missing: Check infrastructure/gitops/kind/base/secrets/
```

### Services not accessible?
```bash
# Check nginx-ingress is running
kubectl --context kind-macula-hub-01 get pods -n ingress-nginx

# Re-run DNS setup
sudo infrastructure/scripts/setup-hosts.sh

# Verify /etc/hosts entries
grep macula /etc/hosts
```

### Dashboard shows no data?
```bash
# Check home bots are running
kubectl --context kind-macula-edge-01 get pods -n macula-system -l app=cortex-iq-homes

# Check provider bots are running
kubectl --context kind-macula-edge-03 get pods -n macula-system -l app=cortex-iq-utilities

# Check WAMP connections
kubectl --context kind-macula-edge-01 logs -n macula-system -l app=cortex-iq-homes -c homes | grep "Connected"
```

---

## Cleanup (After Demo)

```bash
# Delete all deployments
kubectl --context kind-macula-hub-01 delete -k infrastructure/gitops/kind/clusters/hub-01/prometheus
kubectl --context kind-macula-hub-01 delete -k infrastructure/gitops/kind/clusters/hub-01/grafana
kubectl --context kind-macula-edge-01 delete -k infrastructure/gitops/kind/clusters/edge-01
kubectl --context kind-macula-edge-02 delete -k infrastructure/gitops/kind/clusters/edge-02
kubectl --context kind-macula-edge-03 delete -k infrastructure/gitops/kind/clusters/edge-03
kubectl --context kind-macula-edge-04 delete -k infrastructure/gitops/kind/clusters/edge-04

# Or delete entire clusters
kind delete cluster --name macula-hub
kind delete cluster --name macula-edge-01
kind delete cluster --name macula-edge-02
kind delete cluster --name macula-edge-03
kind delete cluster --name macula-edge-04
```

---

## Key Talking Points for Investors

1. **Platform Play**
   - "Macula is the platform, CortexIQ is just one application"
   - "Like Kubernetes for distributed BEAM applications"

2. **Multi-Language Support**
   - "Sidecar architecture enables any language, not just Elixir"
   - "Python, Go, Rust, JavaScript - all can use Macula"
   - "Show sidecar containers running alongside apps"

3. **Monetization Ready**
   - "API key authentication per application"
   - "Usage metering built into every sidecar"
   - "Foundation for SaaS pricing model"

4. **Professional Presentation**
   - "Business-friendly URLs: 'telemetry' not 'prometheus'"
   - "Clear platform vs application distinction"
   - "Polished monitoring dashboards"

5. **Production Features**
   - "Connection resilience - automatic reconnection"
   - "Comprehensive monitoring - Prometheus + Grafana"
   - "Container-first, GitOps-ready architecture"

---

## Questions?

- **Full Documentation:** `infrastructure/SIDECAR_IMPLEMENTATION.md`
- **Portal Guide:** `infrastructure/portal/README.md`
- **Monitoring Guide:** `infrastructure/gitops/kind/clusters/hub-01/MONITORING.md`
- **Session Summary:** `SESSION_SUMMARY.md`

---

**Ready to impress!** 🚀
