# VM Infrastructure Setup - Summary

## What We Just Built

A complete **virtualized Kubernetes infrastructure** for deploying the Macula platform using KVM/libvirt, K3d, and FluxCD.

**Created**: 32 files across infrastructure tooling, provisioning scripts, Docker images, and GitOps manifests.

## Quick Overview

### Architecture

- **1 Hub VM** (192.168.100.10): Bondy + MaculaOs (realm_hub) + Dashboard
- **4 Edge VMs** (192.168.100.11-14): K3d + FluxCD + MaculaOs (edge) + Payloads
- **Network**: libvirt NAT network (192.168.100.0/24)
- **Total Agents**: 37 homes + 5 providers = 42 simulated bots

### Key Components

1. **macula-ctl** - Simple Bash CLI for infrastructure management
2. **bootstrap.sh** - Creates VMs and network automatically
3. **provision-hub.sh** - Sets up hub with Bondy + MaculaOs + Dashboard
4. **provision-edge.sh** - Sets up edges with K3d + FluxCD + payloads
5. **Dockerfiles** - Container images for MaculaOs and CortexIQ payloads
6. **GitOps manifests** - Kustomize-based Kubernetes deployments

## Usage

### Bootstrap Everything (30 minutes)

```bash
cd infrastructure

# 1. Create VMs (5 min)
./macula-ctl bootstrap

# 2. Provision hub (10 min)
./macula-ctl provision hub

# 3. Provision edges (15 min)
./macula-ctl provision all

# 4. Check status
./macula-ctl status

# 5. Open dashboard
./macula-ctl dashboard  # → http://192.168.100.10:4000
```

### Daily Operations

```bash
# Monitor VMs
virt-top

# Check Macula status
./macula-ctl status

# SSH into VMs
./macula-ctl ssh hub
./macula-ctl ssh edge-01

# View logs
./macula-ctl logs edge-01
./macula-ctl logs hub bondy

# Manage VMs
virsh list --all
virsh start macula-edge-01
virsh shutdown macula-edge-01
```

### GitOps Workflow

```bash
# 1. Build images
cd docker && ./build.sh

# 2. Push to registry
docker push macula/cortex-iq-homes:latest

# 3. Update manifest
vim gitops/base/cortex-iq-homes/deployment.yaml

# 4. Commit and push
git commit -am "Update homes" && git push

# 5. FluxCD auto-deploys (within 60s)
./macula-ctl flux edge-01 status
```

## Key Decisions

### 1. Use Standard Tools (Not Custom TUI)

**Decided**: Use `virt-top`, `virsh`, `virt-manager` for VM management instead of building a custom TUI.

**Rationale**:
- Don't reinvent the wheel
- Mature, well-tested tools available
- macula-ctl focuses on Macula-specific orchestration only

### 2. K3d + FluxCD (Not Systemd Services)

**Decided**: Deploy payloads via Kubernetes (K3d) with GitOps (FluxCD).

**Rationale**:
- Industry-standard deployment pattern
- GitOps workflow (git push → auto-deploy)
- Production-representative
- Impressive for investor demos

### 3. Simple Bash CLI (Not Go Bubbletea)

**Decided**: macula-ctl as Bash script with subcommands.

**Rationale**:
- Faster to build and maintain
- Wraps existing tools (virsh, kubectl, flux)
- Easier to debug and extend

## Files Created (32 total)

```
infrastructure/
├── macula-ctl                      # Main CLI (Bash)
├── ARCHITECTURE.md                 # Detailed design docs
├── README.md                       # Comprehensive guide
├── QUICKSTART.md                   # 30-minute quick start
├── SUMMARY.md                      # This file
│
├── scripts/ (3 files)
│   ├── bootstrap.sh
│   ├── provision-hub.sh
│   └── provision-edge.sh
│
├── libvirt/ (3 files)
│   ├── macula-net.xml
│   ├── cloud-init-hub.yaml
│   └── cloud-init-edge.yaml
│
├── docker/ (5 files)
│   ├── build.sh
│   ├── Dockerfile.macula-os-base
│   ├── Dockerfile.cortex-iq-homes
│   ├── Dockerfile.cortex-iq-utilities
│   └── Dockerfile.cortex-iq-dashboard
│
└── gitops/ (15+ files)
    ├── base/macula-os/
    ├── base/cortex-iq-homes/
    ├── base/cortex-iq-utilities/
    ├── overlays/edge-01/
    ├── overlays/edge-02/
    ├── overlays/edge-03/
    ├── overlays/edge-04/
    ├── clusters/macula-edge-01/
    ├── clusters/macula-edge-02/
    ├── clusters/macula-edge-03/
    ├── clusters/macula-edge-04/
    └── README.md
```

## What's Next

### Before You Can Test

1. **Prerequisites**: Install libvirt/KVM on your host machine
   ```bash
   sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients \
     virtinst bridge-utils virt-top genisoimage
   sudo usermod -aG libvirt $USER && newgrp libvirt
   ```

2. **System Requirements**: 12GB+ RAM, 100GB+ disk, 4+ CPU cores

3. **Build Docker Images**: The Dockerfiles reference apps that may need adjustment
   ```bash
   cd docker && ./build.sh
   ```

4. **Test Bootstrap**: Try creating the VMs
   ```bash
   ./macula-ctl bootstrap
   ```

### Integration Tasks

The infrastructure is ready, but may need integration with existing code:

1. **Align system/ directory structure** with Docker build expectations
2. **Test Docker builds** for all payloads
3. **Verify WAMP connectivity** between hub and edges
4. **Test GitOps flow** end-to-end
5. **Create demo script** for investors

### Optional Enhancements

- **Monitoring**: Add Prometheus + Grafana to hub VM
- **Multi-region**: Create multiple hub VMs with inter-realm routing
- **Scaling**: Add more edge VMs dynamically
- **CI/CD**: Integrate with GitHub Actions for auto-builds

## Benefits Over Docker Compose

| Aspect | Docker Compose (Old) | VM Infrastructure (New) |
|--------|---------------------|------------------------|
| Distribution | All on one host | True distributed VMs |
| Edge Concept | Simulated | Real VMs with isolation |
| Deployment | Manual | GitOps (auto-deploy) |
| Scaling | Limited | Add VMs easily |
| Production-like | No | Yes (K8s + FluxCD) |
| Demo Impact | Moderate | High (real infrastructure) |

## Documentation

- **README.md**: Comprehensive guide with all commands
- **QUICKSTART.md**: 30-minute quick start guide
- **ARCHITECTURE.md**: Detailed architecture and design
- **gitops/README.md**: GitOps workflow documentation

## Commands Reference

```bash
# Infrastructure
./macula-ctl bootstrap          # Create VMs
./macula-ctl provision <vm>     # Provision hub/edges
./macula-ctl status             # Check everything
./macula-ctl destroy            # Cleanup all VMs

# Access
./macula-ctl ssh <vm>           # SSH to VM
./macula-ctl logs <vm> [svc]    # View logs
./macula-ctl dashboard          # Open UI

# FluxCD
./macula-ctl flux <edge> status
./macula-ctl flux <edge> reconcile

# VM Management (standard tools)
virt-top                        # Monitor VMs
virsh list --all                # List VMs
virsh start <vm>                # Start VM
virsh shutdown <vm>             # Stop VM
```

## Support

- **Prerequisites issues**: Check README.md troubleshooting section
- **VM creation fails**: Check libvirt logs, verify KVM support
- **Pods not starting**: Check Docker images, verify registry access
- **FluxCD not working**: Check GitOps manifest syntax, flux logs

## Success Criteria

You'll know it works when:

- ✅ 5 VMs running (`virsh list`)
- ✅ virt-top shows activity on all VMs
- ✅ Bondy responds (`curl http://192.168.100.10:18081`)
- ✅ Dashboard loads (http://192.168.100.10:4000)
- ✅ Pods running on edges (`kubectl get pods -n macula-system`)
- ✅ Events flowing (`./macula-ctl logs edge-01`)

## Timeline

- **Design & Planning**: Completed ✅
- **Infrastructure Code**: Completed ✅ (32 files)
- **Documentation**: Completed ✅
- **Testing**: Not started ⏳
- **Integration**: Not started ⏳
- **Demo Ready**: Pending testing & integration

---

**Ready to try**: `cd infrastructure && ./macula-ctl bootstrap`

**Questions?** Read README.md, QUICKSTART.md, or ARCHITECTURE.md
