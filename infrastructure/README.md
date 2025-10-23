# Macula Infrastructure

Virtualized Kubernetes infrastructure for the Macula platform PoC using KVM/libvirt, K3d, and FluxCD.

## Overview

This infrastructure creates **5 virtual machines** on your Linux host:
- **1 Hub VM**: Bondy WAMP router + MaculaOs (realm_hub mode) + CortexIQ Dashboard
- **4 Edge VMs**: K3d clusters + FluxCD + MaculaOs (edge mode) + CortexIQ payloads

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Host Machine (Linux/KVM)                                    │
│                                                              │
│  Hub VM (192.168.100.10)          Edge VMs                  │
│  ┌────────────────────┐          ┌──────────┐              │
│  │ Bondy WAMP Router  │◄─────────│ edge-01  │              │
│  │ MaculaOs (hub)     │          │ K3d+Flux │              │
│  │ Dashboard (UI)     │          │ 13 homes │              │
│  └────────────────────┘          └──────────┘              │
│           ▲                       ┌──────────┐              │
│           │                       │ edge-02  │              │
│           │                       │ K3d+Flux │              │
│           │                       │ 13 homes │              │
│           │                       └──────────┘              │
│           │                       ┌──────────┐              │
│           │                       │ edge-03  │              │
│           └───────────────────────│ K3d+Flux │              │
│                                   │ 5 utils  │              │
│                                   └──────────┘              │
│                                   ┌──────────┐              │
│                                   │ edge-04  │              │
│                                   │ K3d+Flux │              │
│                                   │ 11 homes │              │
│                                   └──────────┘              │
└─────────────────────────────────────────────────────────────┘
```

**Total Simulated Agents**: 37 homes + 5 providers = **42 autonomous bots**

## Prerequisites

### Required Software

```bash
# Ubuntu/Debian
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients \
  virtinst bridge-utils cpu-checker \
  virt-top virt-viewer \
  genisoimage

# Add yourself to libvirt group
sudo usermod -aG libvirt $USER
newgrp libvirt

# Verify KVM support
kvm-ok
```

### System Requirements

**Minimum**:
- CPU: 4 cores (with KVM support)
- RAM: 12GB
- Disk: 100GB free
- OS: Linux with KVM (Ubuntu 22.04+, Fedora, Arch, etc.)

**Recommended**:
- CPU: 8+ cores
- RAM: 16GB+
- Disk: 200GB SSD

## Quick Start

### 1. Bootstrap Infrastructure

Create VMs and network:

```bash
cd infrastructure
./macula-ctl bootstrap
```

This will:
- Create libvirt network (192.168.100.0/24)
- Download Ubuntu 22.04 cloud image
- Create 5 VMs with cloud-init
- Wait for SSH accessibility (~5 minutes)

### 2. Provision Hub VM

Install Bondy, MaculaOs, and dashboard:

```bash
./macula-ctl provision hub
```

This will (~10 minutes):
- Install Erlang/Elixir
- Install and configure Bondy WAMP router
- Compile MaculaOs and CortexIQ apps
- Set up PostgreSQL database
- Start services

### 3. Provision Edge VMs

Install K3d, FluxCD, and payloads:

```bash
# Provision all edges at once
./macula-ctl provision all

# Or individually
./macula-ctl provision edge-01
./macula-ctl provision edge-02
./macula-ctl provision edge-03
./macula-ctl provision edge-04
```

This will (per edge, ~5 minutes):
- Create K3d cluster
- Install FluxCD
- Deploy MaculaOs (edge mode)
- Deploy CortexIQ payload (homes or utilities)

### 4. Check Status

```bash
./macula-ctl status
```

Expected output:
```
=== Macula Infrastructure Status ===

VMs:
✓ macula-hub-01: running
✓ macula-edge-01: running
✓ macula-edge-02: running
✓ macula-edge-03: running
✓ macula-edge-04: running

Hub WAMP Router:
✓ Bondy HTTP API reachable at 192.168.100.10:18081

Edge Clusters:
✓ edge-01: K3d cluster running
✓ edge-02: K3d cluster running
✓ edge-03: K3d cluster running
✓ edge-04: K3d cluster running

FluxCD Deployments:
✓ edge-01: FluxCD running
✓ edge-02: FluxCD running
✓ edge-03: FluxCD running
✓ edge-04: FluxCD running
```

### 5. Access Dashboard

```bash
./macula-ctl dashboard
```

Or manually: http://192.168.100.10:4000

## Management Commands

### VM Management

```bash
# Use standard libvirt tools
virt-top                        # Real-time VM monitoring
virsh list --all                # List all VMs
virsh start macula-edge-01      # Start a VM
virsh shutdown macula-edge-01   # Shutdown a VM
virsh destroy macula-edge-01    # Force stop
virt-manager                    # GUI (if installed)

# Or use macula-ctl shortcuts
./macula-ctl vms                # Show VM commands
./macula-ctl ssh hub            # SSH to hub
./macula-ctl ssh edge-01        # SSH to edge
```

### Log Viewing

```bash
# Hub logs
./macula-ctl logs hub bondy
./macula-ctl logs hub macula-os

# Edge logs (Kubernetes pods)
./macula-ctl logs edge-01                      # All pods
./macula-ctl logs edge-01 cortex-iq-homes      # Specific app
./macula-ctl logs edge-03 cortex-iq-utilities
```

### FluxCD Management

```bash
# Check GitOps status
./macula-ctl flux edge-01 status

# Force reconciliation
./macula-ctl flux edge-01 reconcile

# Suspend/resume GitOps
./macula-ctl flux edge-01 suspend
./macula-ctl flux edge-01 resume
```

### Cleanup

```bash
# Destroy everything
./macula-ctl destroy

# This will:
# - Stop all VMs
# - Delete VM disks
# - Remove network
```

## Development Workflow

### 1. Build Docker Images

```bash
cd docker
./build.sh
```

This builds:
- `macula/os-base:latest` - MaculaOs platform
- `macula/cortex-iq-homes:latest` - Home bots payload
- `macula/cortex-iq-utilities:latest` - Provider bots payload
- `macula/cortex-iq-dashboard:latest` - Dashboard payload

### 2. Push to Registry

```bash
# Tag for your registry
docker tag macula/cortex-iq-homes:latest yourusername/cortex-iq-homes:latest

# Push
docker push yourusername/cortex-iq-homes:latest
```

### 3. Update GitOps Manifests

```bash
cd gitops/base/cortex-iq-homes
vim deployment.yaml
# Change image: yourusername/cortex-iq-homes:latest

git commit -am "Deploy homes v1.2.0"
git push
```

### 4. FluxCD Auto-Deploys

Within 60 seconds, FluxCD will:
- Detect git change
- Pull new image
- Roll out deployment

Verify:
```bash
./macula-ctl flux edge-01 status
./macula-ctl logs edge-01 cortex-iq-homes
```

## Directory Structure

```
infrastructure/
├── macula-ctl              # Main CLI tool
├── ARCHITECTURE.md         # Detailed architecture docs
├── README.md               # This file
│
├── scripts/                # Provisioning scripts
│   ├── bootstrap.sh        # Create VMs and network
│   ├── provision-hub.sh    # Provision hub VM
│   └── provision-edge.sh   # Provision edge VMs
│
├── libvirt/                # VM definitions
│   ├── macula-net.xml      # Network definition
│   ├── cloud-init-hub.yaml # Hub cloud-init
│   └── cloud-init-edge.yaml# Edge cloud-init
│
├── docker/                 # Docker images
│   ├── build.sh            # Build all images
│   ├── Dockerfile.macula-os-base
│   ├── Dockerfile.cortex-iq-homes
│   ├── Dockerfile.cortex-iq-utilities
│   └── Dockerfile.cortex-iq-dashboard
│
└── gitops/                 # Kubernetes manifests
    ├── base/               # Base resources
    ├── overlays/           # Environment patches
    ├── clusters/           # FluxCD entry points
    └── README.md           # GitOps workflow docs
```

## Troubleshooting

### VMs not starting

```bash
# Check libvirt service
sudo systemctl status libvirtd

# Check VM console
virsh console macula-hub-01

# Check VM logs
virsh dumpxml macula-hub-01
```

### Network issues

```bash
# Check network
virsh net-list --all
virsh net-info macula-net

# Restart network
virsh net-destroy macula-net
virsh net-start macula-net
```

### SSH connection refused

```bash
# Wait for cloud-init to finish
virsh console macula-hub-01
# Watch for "Cloud-init finished"

# Check SSH key
ls -la ~/.ssh/macula_rsa*
```

### Bondy not starting

```bash
./macula-ctl ssh hub
sudo journalctl -u bondy -f
sudo systemctl status bondy
```

### Pods not starting

```bash
./macula-ctl ssh edge-01
kubectl get pods -n macula-system
kubectl describe pod <pod-name> -n macula-system
kubectl logs <pod-name> -n macula-system
```

### FluxCD not reconciling

```bash
./macula-ctl ssh edge-01
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller
flux reconcile source git flux-system
```

## Performance Tuning

### Increase VM Resources

Edit `scripts/bootstrap.sh`:

```bash
# Hub VM
HUB_RAM=4096    # Increase to 8192
HUB_VCPUS=2     # Increase to 4

# Edge VMs
EDGE_RAM=2048   # Increase to 4096
EDGE_VCPUS=2    # Increase to 4
```

Then recreate VMs:

```bash
./macula-ctl destroy
./macula-ctl bootstrap
```

### Reduce Edge Count

If system is constrained, use fewer edges:

```bash
# Only create hub + 2 edges
./macula-ctl bootstrap
./macula-ctl provision hub
./macula-ctl provision edge-01
./macula-ctl provision edge-03  # Providers
```

## Next Steps

1. **Monitor VMs**: `virt-top`
2. **View Dashboard**: http://192.168.100.10:4000
3. **Watch Events**: `./macula-ctl logs edge-01`
4. **Develop Payloads**: Edit code, build images, push to GitOps
5. **Scale**: Adjust NUM_HOMES in GitOps overlays

## References

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Detailed architecture
- [gitops/README.md](./gitops/README.md) - GitOps workflow
- [libvirt documentation](https://libvirt.org/)
- [K3d documentation](https://k3d.io/)
- [FluxCD documentation](https://fluxcd.io/)
- [Bondy documentation](https://developer.bondy.io/)
