#!/bin/bash
set -e

# Migrate k3s data from root partition to NVMe storage using symlink
# This script is safe to run multiple times

HOST=$1

if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname>"
  echo "Example: $0 beam01.lab"
  exit 1
fi

echo "=== Migrating k3s data on $HOST to NVMe ==="

sshpass -p 'rl' ssh -o StrictHostKeyChecking=no rl@$HOST bash << 'ENDSSH'
set -e

# Stop k3s
echo "→ Stopping k3s..."
sudo systemctl stop k3s.service
sudo /usr/local/bin/k3s-killall.sh 2>/dev/null || true

# Check if already migrated
if [ -L "/var/lib/rancher/k3s" ]; then
  echo "ℹ Already migrated (symlink exists)"
  TARGET=$(readlink /var/lib/rancher/k3s)
  echo "  Symlink points to: $TARGET"
else
  echo "→ Migrating data..."

  # Move old data if it exists
  if [ -d "/var/lib/rancher/k3s" ]; then
    echo "  Moving data from /var/lib/rancher/k3s to /fast/k3s-data..."
    sudo mkdir -p /fast
    sudo mv /var/lib/rancher/k3s /fast/k3s-data
    OLD_SIZE=$(sudo du -sh /fast/k3s-data | cut -f1)
    echo "  ✓ Moved $OLD_SIZE"
  else
    echo "  No existing data to move"
    sudo mkdir -p /fast/k3s-data
  fi

  # Create symlink
  echo "  Creating symlink..."
  sudo mkdir -p /var/lib/rancher
  sudo ln -s /fast/k3s-data /var/lib/rancher/k3s
  echo "  ✓ Symlink created"
fi

# Remove K3S_DATA_DIR from env file if present (we use symlink now)
if [ -f "/etc/systemd/system/k3s.service.env" ]; then
  sudo sed -i '/K3S_DATA_DIR/d' /etc/systemd/system/k3s.service.env
fi

# Start k3s
echo "→ Starting k3s..."
sudo systemctl daemon-reload
sudo systemctl start k3s.service
sleep 10

# Verify
if sudo systemctl is-active --quiet k3s.service; then
  echo "✓ k3s is running"
  echo ""
  echo "Storage summary:"
  df -h / /fast | grep -v Filesystem
else
  echo "✗ k3s failed to start"
  sudo systemctl status k3s.service --no-pager | head -20
  exit 1
fi
ENDSSH

echo "✓ Migration complete for $HOST"
