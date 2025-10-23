# Macula Infrastructure Architecture

## Overview

This infrastructure creates a 5-VM distributed Macula platform demonstrating hub-spoke topology with Kubernetes-based edge clusters.

## VM Topology

```
┌──────────────────────────────────────────────────────────────┐
│ Host Machine (Linux/KVM)                                     │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ macula-hub-01 (192.168.100.10)                         │  │
│  │ - OS: Ubuntu 22.04                                     │  │
│  │ - RAM: 4GB, vCPU: 2                                    │  │
│  │ - Bondy WAMP Router (ports: 18080/WSS, 18081/HTTP)    │  │
│  │ - MaculaOs (realm_hub mode)                           │  │
│  │ - Realm: be.cortexiq.energy                           │  │
│  │ - Payloads: cortex_iq_dashboard + dashboard_web       │  │
│  │ - Phoenix UI: http://192.168.100.10:4000              │  │
│  └────────────────────────────────────────────────────────┘  │
│           ▲              ▲              ▲              ▲      │
│           │ WAMP         │ WAMP         │ WAMP         │      │
│           │              │              │              │      │
│  ┌────────┴────┐  ┌──────┴──────┐  ┌───┴──────────┐  ┌┴────┐│
│  │ macula-     │  │ macula-     │  │ macula-      │  │ ... ││
│  │ edge-01     │  │ edge-02     │  │ edge-03      │  │     ││
│  │ .11         │  │ .12         │  │ .13          │  │ .14 ││
│  │             │  │             │  │              │  │     ││
│  │ K3d cluster │  │ K3d cluster │  │ K3d cluster  │  │ ... ││
│  │ FluxCD      │  │ FluxCD      │  │ FluxCD       │  │     ││
│  │ MaculaOs    │  │ MaculaOs    │  │ MaculaOs     │  │     ││
│  │ (edge mode) │  │ (edge mode) │  │ (edge mode)  │  │     ││
│  │             │  │             │  │              │  │     ││
│  │ Payload:    │  │ Payload:    │  │ Payload:     │  │ ... ││
│  │ cortex_iq_  │  │ cortex_iq_  │  │ cortex_iq_   │  │     ││
│  │  homes      │  │  homes      │  │  utilities   │  │     ││
│  │ (13 bots)   │  │ (13 bots)   │  │ (5 bots)     │  │     ││
│  └─────────────┘  └─────────────┘  └──────────────┘  └─────┘│
│                                                               │
└──────────────────────────────────────────────────────────────┘

Network: 192.168.100.0/24 (libvirt network: macula-net)
```

## VM Specifications

### Hub VM (macula-hub-01)
- **OS**: Ubuntu 22.04 LTS
- **Resources**: 4GB RAM, 2 vCPU, 20GB disk
- **IP**: 192.168.100.10 (static)
- **Services**:
  - Bondy WAMP Router (v1.0.0-rc.7+)
  - MaculaOs (compiled from source)
  - CortexIQ Dashboard payloads
  - PostgreSQL (for dashboard)
- **Ports**:
  - 18080: Bondy WebSocket (WSS)
  - 18081: Bondy HTTP API
  - 4000: Phoenix Dashboard UI
  - 5432: PostgreSQL

### Edge VMs (macula-edge-01 through macula-edge-04)
- **OS**: Ubuntu 22.04 LTS
- **Resources**: 2GB RAM, 2 vCPU, 15GB disk each
- **IPs**: 192.168.100.11-14 (static)
- **Services**:
  - K3d (lightweight K8s)
  - FluxCD (GitOps controller)
  - MaculaOs (edge mode, deployed as K8s workload)
  - CortexIQ payloads (deployed via GitOps)
- **K3s Configuration**:
  - Single-node cluster per VM
  - Traefik disabled (not needed)
  - Local path provisioner for storage

## Technology Stack

### VM Management
- **Hypervisor**: KVM/QEMU via libvirt
- **Provisioning**: virsh + cloud-init
- **Networking**: libvirt virtual network (NAT + DHCP with static leases)
- **Image**: Ubuntu 22.04 cloud image

### TUI (macula-ctl)
- **Framework**: Bubbletea (Go)
- **Features**:
  - VM status dashboard (CPU, RAM, network)
  - Start/stop/restart VMs
  - View VM logs (serial console)
  - SSH into VMs
  - FluxCD reconciliation status
  - Real-time event stream from WAMP
- **Build**: Single Go binary

### Edge Clusters
- **Container Runtime**: containerd (via K3s)
- **Kubernetes**: K3d (K3s in Docker)
- **GitOps**: FluxCD v2
- **Registry**: Docker Hub (public images)
- **Manifests**: Kustomize overlays

## GitOps Repository Structure

```
infrastructure/
├── gitops/
│   ├── clusters/
│   │   ├── macula-edge-01/
│   │   │   ├── flux-system/           # FluxCD bootstrap
│   │   │   └── kustomization.yaml     # Cluster-specific config
│   │   ├── macula-edge-02/
│   │   ├── macula-edge-03/
│   │   └── macula-edge-04/
│   │
│   ├── base/
│   │   ├── macula-os/                 # MaculaOs base manifests
│   │   │   ├── deployment.yaml
│   │   │   ├── configmap.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   ├── cortex-iq-homes/           # Home bot payload
│   │   │   ├── deployment.yaml
│   │   │   ├── configmap.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   └── cortex-iq-utilities/       # Provider bot payload
│   │       ├── deployment.yaml
│   │       ├── configmap.yaml
│   │       └── kustomization.yaml
│   │
│   └── overlays/
│       ├── edge-01/                   # Edge-01 specific config
│       │   ├── macula-os-patch.yaml   # MACULA_MODE=edge, hub URL
│       │   └── homes-patch.yaml       # NUM_HOMES=13
│       ├── edge-02/
│       ├── edge-03/                   # Utilities payload
│       └── edge-04/
```

## Deployment Flow

### 1. Initial Setup (macula-ctl bootstrap)
```bash
# Creates VMs, networks, and provisions base OS
macula-ctl bootstrap
```

**Steps**:
1. Create libvirt network `macula-net` (192.168.100.0/24)
2. Download Ubuntu 22.04 cloud image
3. Create 5 VMs with cloud-init
4. Wait for VMs to boot and become SSH-accessible
5. Run provisioning playbooks/scripts

### 2. Hub VM Provisioning (automated)
```bash
# Executed by macula-ctl during bootstrap
./infrastructure/scripts/provision-hub.sh
```

**Steps**:
1. Install Erlang/Elixir runtime
2. Clone/copy Macula codebase
3. Install Bondy (from release or compile)
4. Configure Bondy realm (be.cortexiq.energy)
5. Compile MaculaOs + CortexIQ apps
6. Install PostgreSQL
7. Create systemd services
8. Start services

### 3. Edge VM Provisioning (automated)
```bash
# Executed by macula-ctl during bootstrap
./infrastructure/scripts/provision-edge.sh <vm-name>
```

**Steps**:
1. Install Docker
2. Install K3d
3. Create K3s cluster (single node)
4. Install FluxCD
5. Bootstrap FluxCD to gitops repo
6. FluxCD pulls manifests and deploys MaculaOs + payloads

### 4. GitOps Deployment (automated by FluxCD)
- FluxCD watches `infrastructure/gitops/clusters/<cluster-name>/`
- On git push, FluxCD reconciles cluster state
- MaculaOs pods connect to hub VM (192.168.100.10:18080)
- Payloads start publishing/subscribing to WAMP topics

## Networking

### libvirt Network (macula-net)
```xml
<network>
  <name>macula-net</name>
  <forward mode='nat'/>
  <bridge name='virbr-macula'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.200'/>
      <host mac='52:54:00:00:00:10' name='macula-hub-01' ip='192.168.100.10'/>
      <host mac='52:54:00:00:00:11' name='macula-edge-01' ip='192.168.100.11'/>
      <host mac='52:54:00:00:00:12' name='macula-edge-02' ip='192.168.100.12'/>
      <host mac='52:54:00:00:00:13' name='macula-edge-03' ip='192.168.100.13'/>
      <host mac='52:54:00:00:00:14' name='macula-edge-04' ip='192.168.100.14'/>
    </dhcp>
  </ip>
</network>
```

### Port Forwarding (Host → VMs)
```bash
# Access Phoenix dashboard from host
ssh -L 4000:localhost:4000 ubuntu@192.168.100.10

# Or via libvirt network routing (if host is on same subnet)
curl http://192.168.100.10:4000
```

## TUI Commands (macula-ctl)

```bash
# Bootstrap entire infrastructure
macula-ctl bootstrap

# VM Management
macula-ctl vms list                    # Show all VMs with status
macula-ctl vms start <name>            # Start a VM
macula-ctl vms stop <name>             # Graceful shutdown
macula-ctl vms restart <name>          # Restart a VM
macula-ctl vms ssh <name>              # SSH into VM
macula-ctl vms logs <name>             # View serial console

# FluxCD Management
macula-ctl flux status <cluster>       # Show FluxCD reconciliation status
macula-ctl flux reconcile <cluster>    # Force reconciliation
macula-ctl flux suspend <cluster>      # Pause GitOps sync

# Monitoring
macula-ctl dashboard                   # Launch interactive TUI
macula-ctl events                      # Stream WAMP events (live tail)
macula-ctl metrics                     # Show aggregated metrics

# Cleanup
macula-ctl destroy                     # Destroy all VMs and networks
```

## Build & Deployment Workflow

### Building Container Images
```bash
# Build MaculaOs base image
docker build -f infrastructure/docker/Dockerfile.macula-os -t macula/os:latest .

# Build payload images
docker build -f infrastructure/docker/Dockerfile.homes -t macula/cortex-iq-homes:latest .
docker build -f infrastructure/docker/Dockerfile.utilities -t macula/cortex-iq-utilities:latest .

# Push to registry (DockerHub or private)
docker push macula/os:latest
docker push macula/cortex-iq-homes:latest
docker push macula/cortex-iq-utilities:latest
```

### GitOps Deployment
```bash
# 1. Update manifest in gitops repo
vim infrastructure/gitops/base/cortex-iq-homes/deployment.yaml
# Change: image: macula/cortex-iq-homes:v1.2.0

# 2. Commit and push
git add infrastructure/gitops/
git commit -m "Update homes payload to v1.2.0"
git push origin main

# 3. FluxCD auto-deploys within 1 minute (or force reconcile)
macula-ctl flux reconcile macula-edge-01
```

## Resource Requirements (Host Machine)

**Minimum**:
- CPU: 4 cores (2 for hub, 2 shared by edges)
- RAM: 12GB (4GB hub + 8GB edges)
- Disk: 100GB free
- OS: Linux with KVM support (Ubuntu 22.04+, Fedora, Arch, etc.)

**Recommended**:
- CPU: 8+ cores
- RAM: 16GB+
- Disk: 200GB SSD
- Network: Gigabit (for VM-to-VM communication)

## Security Considerations

### VM Access
- SSH key-based authentication only (no passwords)
- Host key: `~/.ssh/macula_rsa` (auto-generated by macula-ctl)
- VMs accessible only from host (NAT network, no external exposure)

### WAMP Security
- **Phase 1 (PoC)**: Anonymous authentication (realm: be.cortexiq.energy)
- **Phase 2 (Production)**: WAMP-CRA or TLS client certs
- WSS (WebSocket Secure) enabled by default

### Kubernetes
- K3s with default RBAC
- FluxCD with read-only Git access (SSH deploy key)
- No external LoadBalancer (NodePort only for demo)

## Monitoring & Observability

### Logs
- **Hub VM**: journalctl -u bondy, journalctl -u macula-os
- **Edge VMs**: kubectl logs -n macula-system <pod>
- **FluxCD**: kubectl logs -n flux-system <controller>

### Metrics (Future)
- Prometheus (deployed to hub VM)
- Grafana dashboards (energy metrics, WAMP message rates, VM resources)

### WAMP Event Stream
- macula-ctl events - Live tail of all WAMP messages
- Useful for debugging and demos

## Demo Workflow

### 1. Bootstrap Infrastructure (1 minute)
```bash
macula-ctl bootstrap
# Creates 5 VMs, installs software, starts services
```

### 2. Verify Status (30 seconds)
```bash
macula-ctl dashboard
# Shows:
# - All VMs running (green)
# - Hub connected (Bondy healthy)
# - 4 edge clusters connected to realm
# - FluxCD reconciled (all payloads deployed)
```

### 3. Open Phoenix Dashboard (browser)
```bash
# From host machine
firefox http://192.168.100.10:4000
# Shows real-time energy trading simulation
```

### 4. Live Deploy New Payload (30 seconds)
```bash
# Add a new home bot payload to edge-04
vim infrastructure/gitops/overlays/edge-04/homes-patch.yaml
# Change NUM_HOMES from 13 to 20

git commit -am "Scale homes on edge-04"
git push

macula-ctl flux status macula-edge-04
# Watch reconciliation... deployed in 10-20 seconds
```

### 5. Stream Live Events (terminal)
```bash
macula-ctl events --filter="contract.switched"
# Shows real-time contract switching events as homes optimize
```

## Troubleshooting

### VM won't start
```bash
# Check libvirt status
sudo systemctl status libvirtd
virsh list --all

# Check VM console
virsh console macula-hub-01

# Destroy and recreate
virsh destroy macula-hub-01
virsh undefine macula-hub-01
macula-ctl bootstrap --only hub-01
```

### FluxCD not reconciling
```bash
# SSH into edge VM
macula-ctl vms ssh macula-edge-01

# Check FluxCD pods
kubectl get pods -n flux-system

# Check source controller
kubectl logs -n flux-system deploy/source-controller

# Force reconcile
flux reconcile source git flux-system
```

### WAMP connection issues
```bash
# From edge VM, test Bondy connectivity
curl -k https://192.168.100.10:18080/ws

# Check Bondy realm
ssh ubuntu@192.168.100.10
bondy eval 'bondy_realm:list().'

# Check MaculaOs logs
kubectl logs -n macula-system -l app=macula-os
```

## Next Steps

1. Implement macula-ctl TUI (Bubbletea)
2. Create VM provisioning scripts
3. Build Dockerfiles for MaculaOs and payloads
4. Set up GitOps repository structure
5. Test end-to-end deployment
6. Add monitoring and observability
7. Create demo script and screenshots
