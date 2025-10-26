# Monitoring Setup - Hub-01

This document describes the Prometheus and Grafana monitoring setup for the Macula Platform PoC.

## Overview

**Monitoring Stack:**
- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards

**Deployment:**
- Namespace: `monitoring`
- Cluster: `macula-hub-01` (hub cluster)

## Access URLs

Once deployed to KinD cluster with ingress configured:

| Service    | Business Name        | URL (via Ingress)                        | Credentials         |
|------------|----------------------|------------------------------------------|---------------------|
| Prometheus | Platform Telemetry   | http://telemetry.macula.local:8080       | None (no auth)      |
| Grafana    | Platform Analytics   | http://analytics.macula.local:8080       | admin / macula123   |

**Alternative Access (NodePort):**
- Prometheus: http://localhost:30090
- Grafana: http://localhost:30030

**Business-Friendly Naming:**
The services are exposed with generic, business-oriented names that don't reveal the underlying technology stack:
- `telemetry.macula.local` - Platform metrics and monitoring backend (Prometheus)
- `analytics.macula.local` - Platform observability dashboards (Grafana)

This maintains the brand distinction:
- **Macula Platform** monitoring → `*.macula.local`
- **CortexIQ Application** dashboard → `dashboard.cortexiq.local`

## Prometheus Configuration

**Scrape Jobs:**
- `prometheus` - Self-monitoring
- `kubernetes-apiservers` - K8s API server metrics
- `kubernetes-nodes` - Node metrics
- `kubernetes-pods` - Pod metrics (auto-discovery via annotations)
- `kubernetes-services` - Service metrics
- `macula-os-sidecars` - MaculaOs sidecar metrics (port 8080)
- `bondy` - Bondy WAMP router metrics

**Retention:** 30 days

**Resources:**
- Requests: 512Mi memory, 250m CPU
- Limits: 2Gi memory, 1000m CPU

## Grafana Dashboards

Two pre-configured dashboards are included:

### 1. Macula Platform Overview
**UID:** `macula-platform`

**Panels:**
- Total Pods
- MaculaOs Sidecars Running
- CPU Usage by Container
- Memory Usage by Container
- Pod Restarts
- Network Traffic

### 2. CortexIQ Energy Mesh
**UID:** `cortexiq-energy`

**Panels:**
- Home Bots Active
- Provider Bots Active
- Dashboard Health
- Homes CPU Usage
- Homes Memory Usage
- MaculaOs Sidecar Resource Usage

## Metrics Collection

### Annotating Pods for Scraping

Prometheus auto-discovers pods with these annotations:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"      # Optional, defaults to pod port
    prometheus.io/path: "/metrics"  # Optional, defaults to /metrics
```

### MaculaOs Sidecar Metrics

The MaculaOs sidecars are automatically scraped on port 8080. To expose metrics from MaculaOs, implement a `/metrics` endpoint that returns Prometheus-formatted metrics.

**Recommended Metrics:**
- `macula_wamp_connections_total` - Total WAMP connections established
- `macula_wamp_messages_published_total` - Messages published through sidecar
- `macula_wamp_messages_subscribed_total` - Messages received via subscriptions
- `macula_api_key_requests_total{status="success|denied"}` - API key auth requests
- `macula_connection_errors_total` - Connection errors to Bondy

## Deployment

Prometheus and Grafana are deployed automatically via FluxCD GitOps:

```bash
# Check monitoring namespace
kubectl --context kind-macula-hub-01 get pods -n monitoring

# View Prometheus targets
kubectl --context kind-macula-hub-01 port-forward -n monitoring svc/prometheus 9090:9090

# Access Grafana
kubectl --context kind-macula-hub-01 port-forward -n monitoring svc/grafana 3000:3000
```

## Troubleshooting

### Prometheus not scraping pods

1. Check pod annotations:
   ```bash
   kubectl --context kind-macula-hub-01 get pod <pod-name> -n macula-system -o yaml | grep prometheus
   ```

2. Check Prometheus targets:
   - Open http://telemetry.macula.local:8080/targets
   - Look for your pod in the list
   - Check "State" column for errors

3. Check Prometheus logs:
   ```bash
   kubectl --context kind-macula-hub-01 logs -n monitoring deployment/prometheus
   ```

### Grafana dashboards not loading

1. Check Grafana logs:
   ```bash
   kubectl --context kind-macula-hub-01 logs -n monitoring deployment/grafana
   ```

2. Verify datasource connection:
   - Login to Grafana (http://analytics.macula.local:8080)
   - Go to Configuration > Data Sources
   - Click "Prometheus" and test connection

3. Check ConfigMaps:
   ```bash
   kubectl --context kind-macula-hub-01 get configmaps -n monitoring
   ```

### No metrics from MaculaOs sidecars

MaculaOs sidecars need to expose metrics on `/metrics` endpoint. Check if the endpoint exists:

```bash
# Port-forward to a sidecar
kubectl --context kind-macula-hub-01 port-forward -n macula-system pod/<pod-name> 8080:8080

# Check metrics endpoint
curl http://localhost:8080/metrics
```

If no metrics endpoint exists, implement it in MaculaOs using the `telemetry_metrics_prometheus` library.

## Future Enhancements

- [ ] Add Alertmanager for alerting
- [ ] Configure alert rules (pod restarts, high CPU, memory pressure)
- [ ] Add Loki for log aggregation
- [ ] Create dashboard for Bondy metrics
- [ ] Add custom CortexIQ business metrics (energy traded, contracts signed, etc.)
- [ ] Configure Grafana authentication via OAuth
- [ ] Persistent storage for Prometheus data (PVC instead of emptyDir)

## Security Notes

**⚠️ IMPORTANT FOR PRODUCTION:**

1. **Change Grafana admin password** - Default is `macula123`
2. **Enable authentication on Prometheus** - Currently no auth
3. **Use secrets for credentials** - Not hardcoded in ConfigMaps
4. **Enable TLS** - Use HTTPS for all monitoring services
5. **Network policies** - Restrict access to monitoring namespace
6. **RBAC** - Limit Prometheus service account permissions

This is a **PoC setup** optimized for ease of use. Production deployments require hardening.
