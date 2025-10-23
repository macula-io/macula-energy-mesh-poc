# Macula PoC - Quick Start Guide

Get the Macula platform running in **under 30 minutes**.

## Prerequisites Check

```bash
# 1. Verify KVM support
kvm-ok
# Should output: "KVM acceleration can be used"

# 2. Check libvirt
virsh list --all
# Should work without sudo

# 3. Verify resources
free -h    # Need at least 12GB RAM
df -h      # Need at least 100GB disk free
```

## Step 1: Bootstrap (5 minutes)

```bash
cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/infrastructure

./macula-ctl bootstrap
```

**What happens**:
- Creates libvirt network (192.168.100.0/24)
- Downloads Ubuntu 22.04 cloud image (~700MB)
- Creates 5 VMs:
  - macula-hub-01 (192.168.100.10)
  - macula-edge-01 (192.168.100.11)
  - macula-edge-02 (192.168.100.12)
  - macula-edge-03 (192.168.100.13)
  - macula-edge-04 (192.168.100.14)
- Waits for all VMs to be SSH-accessible

**Expected output**:
```
[INFO] Checking prerequisites...
[INFO] Prerequisites OK
[INFO] Generating SSH key pair: /home/rl/.ssh/macula_rsa
[INFO] Downloading Ubuntu 22.04 cloud image...
[INFO] Setting up libvirt network: macula-net
[INFO] Network macula-net created and started
[INFO] Creating Hub VM: macula-hub-01
[INFO] Hub VM macula-hub-01 created
[INFO] Creating Edge VM: macula-edge-01
...
[INFO] All VMs created. Waiting for them to boot...
[INFO] macula-hub-01 is ready!
[INFO] macula-edge-01 is ready!
...
[INFO] === Bootstrap Complete ===
```

## Step 2: Provision Hub (10 minutes)

```bash
./macula-ctl provision hub
```

**What happens**:
- Installs Erlang 27 + Elixir 1.17
- Downloads and configures Bondy WAMP router
- Compiles MaculaOs platform
- Compiles CortexIQ dashboard apps
- Sets up PostgreSQL database
- Creates systemd services
- Starts Bondy and dashboard

**Expected output**:
```
[INFO] === Provisioning Hub VM (192.168.100.10) ===
[INFO] Syncing project code to /opt/macula...
[INFO] Installing Bondy WAMP router...
[INFO] Compiling MaculaOs and CortexIQ payloads...
[INFO] Configuring MaculaOs services...
[INFO]
[INFO] === Hub VM Provisioned Successfully ===
[INFO] Access dashboard at: http://192.168.100.10:4000
[INFO] Bondy WebSocket: ws://192.168.100.10:18080/ws
```

**Verify**:
```bash
# Check Bondy is running
curl http://192.168.100.10:18081

# SSH into hub
./macula-ctl ssh hub
sudo systemctl status bondy
sudo systemctl status macula-os
exit
```

## Step 3: Provision Edges (15 minutes for all)

```bash
./macula-ctl provision all
```

Or provision individually:

```bash
./macula-ctl provision edge-01  # 13 home bots
./macula-ctl provision edge-02  # 13 home bots
./macula-ctl provision edge-03  # 5 provider bots
./macula-ctl provision edge-04  # 11 home bots
```

**What happens** (per edge):
- Installs Docker
- Installs K3d and creates cluster
- Installs FluxCD
- Deploys MaculaOs (edge mode)
- Deploys CortexIQ payload (homes or utilities)

**Expected output**:
```
[INFO] === Provisioning Edge VM: macula-edge-01 (192.168.100.11) ===
[INFO] Creating K3d cluster...
[INFO] Installing FluxCD...
[INFO] Deploying MaculaOs (edge mode) and payloads...
[INFO]
[INFO] === Edge VM Provisioned Successfully ===
[INFO] Cluster: macula-edge on 192.168.100.11
[INFO] Payload: cortex-iq-homes with 13 bots
```

**Verify**:
```bash
./macula-ctl ssh edge-01
kubectl get pods -n macula-system
# Should show cortex-iq-homes pod running
exit
```

## Step 4: Check Status

```bash
./macula-ctl status
```

**Expected**:
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

All green ✓ means success!

## Step 5: Access Dashboard

```bash
./macula-ctl dashboard
```

Or open manually: **http://192.168.100.10:4000**

You should see:
- Real-time energy trading simulation
- 37 homes + 5 providers
- Live contract switching events
- Energy production/consumption graphs

## Monitor VMs

Open a new terminal:

```bash
virt-top
```

You'll see live CPU/RAM/network usage for all VMs.

## View Live Logs

```bash
# Watch all events on edge-01
./macula-ctl logs edge-01

# Watch provider bots
./macula-ctl logs edge-03 cortex-iq-utilities

# Watch hub services
./macula-ctl logs hub macula-os
```

## Common Issues

### "Cannot connect to libvirt"

```bash
# Add yourself to libvirt group
sudo usermod -aG libvirt $USER
newgrp libvirt
```

### "KVM not available"

```bash
# Enable virtualization in BIOS
# Check: egrep -c '(vmx|svm)' /proc/cpuinfo
# Should be > 0
```

### "Hub not responding"

```bash
# Check hub VM
virsh domstate macula-hub-01  # Should be "running"

# Check console
virsh console macula-hub-01

# Wait for cloud-init to finish
# Look for: "Cloud-init finished. Hub VM ready for provisioning."
```

### "Pods not starting"

```bash
# Check if Docker images exist
./macula-ctl ssh edge-01
kubectl describe pod -n macula-system

# If ImagePullBackOff, you need to build and push images:
cd /path/to/project/infrastructure/docker
./build.sh
# Then push to a registry
```

## Next Steps

1. **Watch the simulation**: http://192.168.100.10:4000
2. **Monitor VMs**: `virt-top` in separate terminal
3. **Stream events**: `./macula-ctl logs edge-01`
4. **Scale up**: Edit `gitops/overlays/edge-01/kustomization.yaml` to increase NUM_HOMES

## Cleanup

When done:

```bash
./macula-ctl destroy
```

This removes all VMs and networks. You can re-bootstrap anytime.

## Getting Help

```bash
./macula-ctl --help

# Or read docs
cat README.md
cat ARCHITECTURE.md
cat gitops/README.md
```

## Success Checklist

- [ ] 5 VMs running (`virsh list`)
- [ ] virt-top shows activity
- [ ] Bondy responds (`curl http://192.168.100.10:18081`)
- [ ] Dashboard loads (http://192.168.100.10:4000)
- [ ] All pods running (`./macula-ctl ssh edge-01 && kubectl get pods -n macula-system`)
- [ ] Events flowing (`./macula-ctl logs edge-01`)

If all checked, **you're running Macula!** 🎉
