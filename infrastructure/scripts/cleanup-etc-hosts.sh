#!/bin/bash
# Remove manual Macula DNS entries from /etc/hosts
# These are now managed by PowerDNS + ExternalDNS

set -e

echo "Backing up /etc/hosts..."
sudo cp /etc/hosts /etc/hosts.backup-$(date +%Y%m%d-%H%M%S)

echo "Removing Macula DNS entries from /etc/hosts..."
sudo sed -i.bak '/macula\.local\|cortexiq\.local\|beam\.local/d' /etc/hosts

echo "✓ Cleaned up /etc/hosts"
echo ""
echo "All services now accessible via DNS:"
echo "  - portal.macula.local"
echo "  - hub.macula.local"
echo "  - console.macula.local"
echo "  - analytics.macula.local"
echo "  - telemetry.macula.local"
echo ""
echo "Note: DNS server is at 192.168.129.9 (PowerDNS)"
echo "Make sure your system is configured to use this DNS server"
echo "or access via: curl --resolve portal.macula.local:80:192.168.129.9 http://portal.macula.local/"
