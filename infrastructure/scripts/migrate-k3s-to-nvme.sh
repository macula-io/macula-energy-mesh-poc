#!/bin/bash
set -e

# Migrate k3s data directory from root partition to NVMe storage
# This script moves /var/lib/rancher/k3s to /fast/k3s-data and updates k3s service

HOST=$1
NEW_DATA_DIR="/fast/k3s-data"
OLD_DATA_DIR="/var/lib/rancher/k3s"

if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname>"
  echo "Example: $0 beam00.lab"
  exit 1
fi

echo "=== Migrating k3s data on $HOST to NVMe ==="

# Execute migration on remote host
sshpass -p 'rl' ssh -o StrictHostKeyChecking=no rl@$HOST bash -s << 'ENDSSH'
set -e

NEW_DATA_DIR="/fast/k3s-data"
OLD_DATA_DIR="/var/lib/rancher/k3s"

echo "→ Stopping k3s service..."
sudo systemctl stop k3s.service

echo "→ Moving data from $OLD_DATA_DIR to $NEW_DATA_DIR..."
if [ -d "$OLD_DATA_DIR" ]; then
  sudo mkdir -p /fast
  sudo mv $OLD_DATA_DIR $NEW_DATA_DIR
  echo "✓ Data moved ($(du -sh $NEW_DATA_DIR | cut -f1))"
else
  echo "ℹ No existing data to move"
  sudo mkdir -p $NEW_DATA_DIR
fi

echo "→ Updating k3s service to use new data directory..."
# Check if data-dir is already configured
if grep -q "data-dir" /etc/systemd/system/k3s.service 2>/dev/null; then
  echo "ℹ data-dir already configured in service file"
else
  # Add --data-dir to ExecStart line
  sudo sed -i "/ExecStart=/ s|$| --data-dir=$NEW_DATA_DIR|" /etc/systemd/system/k3s.service
  echo "✓ Service file updated"
fi

echo "→ Reloading systemd and starting k3s..."
sudo systemctl daemon-reload
sudo systemctl start k3s.service

echo "→ Waiting for k3s to be ready..."
sleep 5

if sudo systemctl is-active --quiet k3s.service; then
  echo "✓ k3s service is running"
  echo ""
  echo "Storage summary:"
  df -h / /fast | grep -v Filesystem
else
  echo "✗ k3s service failed to start"
  sudo systemctl status k3s.service --no-pager
  exit 1
fi
ENDSSH

echo "✓ Migration complete for $HOST"
