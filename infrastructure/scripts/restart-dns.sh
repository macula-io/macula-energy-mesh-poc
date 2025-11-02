#!/bin/bash
# Restart NetworkManager to reload dnsmasq configuration
# This is needed after DNS record changes in PowerDNS

echo "=== Restarting NetworkManager/dnsmasq ==="
sudo systemctl restart NetworkManager

echo "Waiting for NetworkManager to restart..."
sleep 3

echo ""
echo "=== Testing DNS Resolution ==="
echo "→ Testing portal.macula.local..."
getent hosts portal.macula.local || echo "✗ Failed to resolve"

echo "→ Testing dashboard.cortexiq.local..."
getent hosts dashboard.cortexiq.local || echo "✗ Failed to resolve"

echo "→ Testing pgadmin.macula.local..."
getent hosts pgadmin.macula.local || echo "✗ Failed to resolve"

echo ""
echo "=== DNS Restart Complete ==="
