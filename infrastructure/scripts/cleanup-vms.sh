#!/bin/bash
# Cleanup all Macula VMs and resources

echo "Destroying VMs..."
for vm in macula-hub-01 macula-edge-01 macula-edge-02 macula-edge-03 macula-edge-04; do
  sudo virsh destroy "$vm" 2>/dev/null || true
  sudo virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
  echo "  Removed: $vm"
done

echo "Removing network..."
sudo virsh net-destroy macula-net 2>/dev/null || true
sudo virsh net-undefine macula-net 2>/dev/null || true

echo "Cleaning disk images..."
sudo rm -f /var/lib/libvirt/images/macula-*
sudo rm -f /var/lib/libvirt/images/debian-12-generic-amd64.qcow2

echo "✓ VM cleanup complete!"
