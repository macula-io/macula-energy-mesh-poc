# Installing KVM/libvirt Prerequisites

## For Arch Linux

### 1. Install Required Packages

```bash
# Core virtualization packages
sudo pacman -S qemu-full libvirt virt-manager virt-viewer \
  dnsmasq bridge-utils openbsd-netcat dmidecode \
  ebtables iptables-nft

# Additional tools
sudo pacman -S virt-install cdrtools  # cdrtools provides mkisofs
```

### 2. Enable and Start libvirt Service

```bash
# Enable libvirt service
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Verify it's running
sudo systemctl status libvirtd
```

### 3. Add Your User to Required Groups

```bash
# Add to libvirt and kvm groups
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Apply group changes (re-login or use newgrp)
newgrp libvirt
```

### 4. Verify KVM Support

```bash
# Check if KVM is available
LC_ALL=C lscpu | grep Virtualization

# Should show: Virtualization: VT-x (Intel) or AMD-V (AMD)

# Check if KVM module is loaded
lsmod | grep kvm

# Should show: kvm_intel or kvm_amd
```

### 5. Test Installation

```bash
# Test virsh (should work without sudo now)
virsh list --all

# Should output empty list (no VMs yet)

# Test virt-top
virt-top

# Press 'q' to quit
```

### 6. Configure libvirt Network (Optional)

```bash
# Enable default network (optional, we create our own)
virsh net-autostart default
virsh net-start default
```

## Troubleshooting

### Issue: "Cannot access /dev/kvm"

```bash
# Check KVM permissions
ls -la /dev/kvm

# Should show: crw-rw----+ 1 root kvm

# Ensure you're in kvm group
groups | grep kvm

# If not, add yourself and re-login
sudo usermod -aG kvm $USER
```

### Issue: "Failed to connect to libvirtd"

```bash
# Start the service
sudo systemctl start libvirtd

# Enable auto-start on boot
sudo systemctl enable libvirtd

# Check status
sudo systemctl status libvirtd
```

### Issue: "QEMU not found"

```bash
# Install QEMU
sudo pacman -S qemu-full
```

### Issue: "virsh: command not found"

```bash
# Install libvirt client
sudo pacman -S libvirt
```

## Verification Checklist

After installation, verify everything works:

```bash
# 1. KVM module loaded
lsmod | grep kvm
# ✓ Should show kvm_intel or kvm_amd

# 2. User in correct groups
groups
# ✓ Should include: libvirt, kvm

# 3. libvirt service running
sudo systemctl status libvirtd
# ✓ Should show: active (running)

# 4. virsh works without sudo
virsh list --all
# ✓ Should not error

# 5. virt-top available
which virt-top
# ✓ Should show: /usr/bin/virt-top
```

## Disk Space Check

KVM VMs require disk space. Check available space:

```bash
df -h /var/lib/libvirt/images

# Recommended: 200GB+ free
# Minimum: 100GB free
```

## Memory Check

```bash
free -h

# Recommended: 16GB+ RAM
# Minimum: 12GB RAM
```

## Next Steps

Once installed and verified, proceed with:

```bash
cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/infrastructure
./macula-ctl bootstrap
```

## Alternative: For Other Distributions

### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients \
  virtinst bridge-utils cpu-checker \
  virt-top virt-viewer virt-manager \
  genisoimage

sudo usermod -aG libvirt,kvm $USER
newgrp libvirt

# Verify
kvm-ok
```

### Fedora

```bash
sudo dnf install -y \
  @virtualization \
  virt-top virt-viewer virt-install \
  genisoimage

sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm $USER
newgrp libvirt
```

## Docker Alternative (If KVM Not Available)

If you cannot use KVM (e.g., running in a VM yourself), you can still use the original Docker Compose approach. See `CONTAINER_GUIDE.md` in the project root.
