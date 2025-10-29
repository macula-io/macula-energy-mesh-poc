# Macula Mesh - Dynamic DNS Setup Guide

## Overview

This guide documents the PowerDNS + ExternalDNS setup for dynamic DNS management across the Macula mesh (5 KinD clusters + 4 k3s beam clusters).

**Architecture:** PowerDNS (containerized) with PostgreSQL backend, accessed by External DNS instances in each cluster via HTTP API.

---

## ✅ Completed Setup

### 1. PowerDNS Infrastructure (Containerized)

**Files Created:**
- `infrastructure/docker-compose.dns.yml` - PowerDNS + PostgreSQL containers
- `infrastructure/config/powerdns/init-schema.sql` - Database schema with initial zones
- `infrastructure/scripts/setup-dns-powerdns.sh` - Setup script with systemd integration
- `infrastructure/.gitignore` - Excludes secrets and data from git

**Services:**
- **PostgreSQL**: Port 5432 (internal) - Database backend
- **PowerDNS**: Port 53 (UDP/TCP) - DNS server
- **PowerDNS API**: Port 8081 - HTTP API for ExternalDNS
- **PowerDNS-Admin**: Port 9191 - Web UI (optional)

**Zones Created:**
- `macula.local` - Platform services (hub, console, portal, analytics, telemetry)
- `cortexiq.local` - CortexIQ application (dashboard)
- `beam.local` - Beam cluster services (future)

### 2. ExternalDNS Base Configuration

**Fixed:** `infrastructure/gitops/kind/base/external-dns/deployment.yaml`
- Changed from CoreDNS provider to PowerDNS (`--provider=pdns`)
- Added PowerDNS API endpoint configuration (`--pdns-server`)
- Added API key from Secret (`external-dns-pdns`)
- Fixed image registry (registry.k8s.io)

### 3. ExternalDNS Overlay for hub-01

**Created:** `infrastructure/gitops/kind/clusters/hub-01/external-dns/`
- Kustomization with patches for hub-01 specifics
- PowerDNS API endpoint: `http://192.168.129.9:8081`
- Domain filter: `macula.local`
- Owner ID: `hub-01`

**Updated:** `infrastructure/gitops/kind/clusters/hub-01/kustomization.yaml`
- Changed from base reference to overlay

---

## 🚀 Quick Start

### Step 1: Start PowerDNS

```bash
cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/infrastructure

# Run setup script (installs and starts services)
./scripts/setup-dns-powerdns.sh

# Verify services are running
docker-compose -f docker-compose.dns.yml ps

# Check PowerDNS API (replace API_KEY from .env.dns)
source .env.dns
curl -H "X-API-Key: $POWERDNS_API_KEY" http://localhost:8081/api/v1/servers/localhost
```

### Step 2: Create PowerDNS API Key Secret in hub-01

```bash
# Get API key from .env.dns
source infrastructure/.env.dns

# Create secret in hub-01 cluster
kubectl --context kind-macula-hub create secret generic external-dns-pdns \
  --namespace=external-dns \
  --from-literal=api-key="$POWERDNS_API_KEY"
```

### Step 3: Wait for Flux to Reconcile

Flux will detect the changes in git and deploy ExternalDNS to hub-01.

```bash
# Watch Flux reconciliation
flux --context kind-macula-hub get kustomizations -n flux-system

# Watch ExternalDNS deployment
kubectl --context kind-macula-hub get pods -n external-dns -w
```

### Step 4: Test DNS Resolution

```bash
# Query PowerDNS directly
dig @localhost hub.macula.local

# If working, configure system DNS
# Add "nameserver 192.168.129.9" to /etc/resolv.conf
# Or configure NetworkManager/systemd-resolved
```

---

## 📋 Remaining Tasks

### Task 1: Create ExternalDNS Overlays for Edge Clusters

Need to create overlays for `edge-01`, `edge-02`, `edge-03`, `edge-04`:

```bash
# For each edge cluster (example: edge-01)
mkdir -p infrastructure/gitops/kind/clusters/edge-01/external-dns

cat > infrastructure/gitops/kind/clusters/edge-01/external-dns/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: external-dns

resources:
  - ../../../base/external-dns

secretGenerator:
  - name: external-dns-pdns
    namespace: external-dns
    literals:
      - api-key=PLACEHOLDER

patches:
  - target:
      kind: Deployment
      name: external-dns
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/args/3
        value: --pdns-server=http://192.168.129.9:8081
      - op: replace
        path: /spec/template/spec/containers/0/args/4
        value: --domain-filter=cortexiq.local
      - op: replace
        path: /spec/template/spec/containers/0/args/6
        value: --txt-owner-id=edge-01
EOF

# Update cluster kustomization
# Add "- external-dns" to infrastructure/gitops/kind/clusters/edge-01/kustomization.yaml

# Create secret
kubectl --context kind-macula-edge-01 create secret generic external-dns-pdns \
  --namespace=external-dns \
  --from-literal=api-key="$POWERDNS_API_KEY"
```

Repeat for edge-02, edge-03, edge-04 (changing cluster context and owner ID).

### Task 2: Create ExternalDNS Overlays for Beam Clusters

Similar process for `beam-00`, `beam-01`, `beam-02`, `beam-03`.

**Important:** Ensure beam clusters can reach host IP `192.168.129.9:8081` (firewall/network routing).

### Task 3: Update Ingress Resources with ExternalDNS Annotations

Add annotations to all Ingress resources so ExternalDNS creates DNS records:

```yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: hub.macula.local
    external-dns.alpha.kubernetes.io/ttl: "300"
```

**Ingresses to update:**
- `infrastructure/gitops/kind/clusters/hub-01/bondy/ingress.yaml`
- `infrastructure/gitops/kind/clusters/hub-01/portal/ingress.yaml`
- `infrastructure/gitops/kind/clusters/hub-01/grafana/ingress.yaml`
- `infrastructure/gitops/kind/clusters/hub-01/prometheus/ingress.yaml`
- `infrastructure/gitops/kind/clusters/edge-01/*/ingress.yaml` (dashboard)

### Task 4: Configure System DNS

Once DNS is working, configure your system to use PowerDNS:

**Option 1: NetworkManager (recommended)**
```bash
# Add DNS server
nmcli connection modify "Your Connection" ipv4.dns "192.168.129.9"
nmcli connection down "Your Connection" && nmcli connection up "Your Connection"
```

**Option 2: systemd-resolved**
```bash
sudo systemd-resolve --set-dns=192.168.129.9 --interface=eth0
```

**Option 3: /etc/resolv.conf**
```bash
echo "nameserver 192.168.129.9" | sudo tee /etc/resolv.conf
```

### Task 5: Remove /etc/hosts Workaround

Once DNS is verified working, remove manual entries:
```bash
# Backup current /etc/hosts
sudo cp /etc/hosts /etc/hosts.backup

# Remove macula entries manually or restore pre-macula version
```

---

## 🔍 Troubleshooting

### PowerDNS Not Starting

```bash
# Check logs
docker-compose -f infrastructure/docker-compose.dns.yml logs powerdns
docker-compose -f infrastructure/docker-compose.dns.yml logs postgres

# Restart services
docker-compose -f infrastructure/docker-compose.dns.yml restart
```

### ExternalDNS CrashLoopBackOff

```bash
# Check logs
kubectl --context kind-macula-hub logs -n external-dns deployment/external-dns

# Common issues:
# 1. Secret not created: kubectl create secret...
# 2. PowerDNS API unreachable: Check firewall, API endpoint
# 3. Invalid API key: Check .env.dns and secret match
```

### DNS Queries Not Resolving

```bash
# Test PowerDNS directly
dig @localhost macula.local SOA
dig @localhost hub.macula.local

# Check PowerDNS zones
curl -H "X-API-Key: $POWERDNS_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost/zones

# Check DNS records in zone
curl -H "X-API-Key: $POWERDNS_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost/zones/macula.local
```

### ExternalDNS Not Creating Records

```bash
# Check ExternalDNS logs for API errors
kubectl --context kind-macula-hub logs -n external-dns deployment/external-dns -f

# Verify Ingress has correct annotations
kubectl --context kind-macula-hub get ingress -A -o yaml | grep -A 5 annotations

# Manually test PowerDNS API
curl -X PATCH -H "X-API-Key: $POWERDNS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"rrsets": [{"name": "test.macula.local.", "type": "A", "changetype": "REPLACE", "records": [{"content": "192.168.1.100", "disabled": false}]}]}' \
  http://localhost:8081/api/v1/servers/localhost/zones/macula.local
```

---

## 📚 References

- **PowerDNS Documentation**: https://doc.powerdns.com/authoritative/
- **PowerDNS API Reference**: https://doc.powerdns.com/authoritative/http-api/
- **ExternalDNS Documentation**: https://github.com/kubernetes-sigs/external-dns
- **ExternalDNS PowerDNS Provider**: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/pdns.md

---

## 🔐 Security Notes

1. **API Key Security**: The PowerDNS API key is stored in `.env.dns` (gitignored) and Kubernetes Secrets
2. **API Access**: PowerDNS API is exposed on `0.0.0.0:8081` - restrict with firewall if needed
3. **Database Credentials**: PostgreSQL password is in `.env.dns` - rotate periodically
4. **Web UI**: PowerDNS-Admin is on port 9191 - default credentials: admin/admin (CHANGE IMMEDIATELY)

---

## 📊 Monitoring

**PowerDNS Metrics**: Available at `http://localhost:9153/metrics` (Prometheus format)

**Useful Queries:**
```bash
# Check if DNS server is responding
dig @localhost macula.local SOA

# List all zones
curl -H "X-API-Key: $POWERDNS_API_KEY" http://localhost:8081/api/v1/servers/localhost/zones | jq

# Check specific record
dig @localhost hub.macula.local A

# View ExternalDNS managed records (TXT records)
dig @localhost external-dns-hub.macula.local TXT
```

---

## 🎯 Next Steps After Completion

1. **SSL/TLS**: Add cert-manager for automatic HTTPS certificates
2. **DNS-over-HTTPS**: Configure DoH for encrypted DNS queries
3. **DNSSEC**: Enable DNSSEC for zone signing
4. **Monitoring**: Integrate PowerDNS metrics with Prometheus/Grafana
5. **Backup**: Set up automated PostgreSQL backups
6. **High Availability**: Add PowerDNS replicas with database replication
