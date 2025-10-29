#!/bin/bash
# Fix dnsmasq configuration to not break mDNS

set -e

echo "Fixing dnsmasq configuration..."
echo "Problem: server=/local/ breaks mDNS (Avahi/Bonjour)"
echo "Solution: Only forward our specific zones"
echo ""

cat <<'EOF' | sudo tee /etc/NetworkManager/dnsmasq.d/macula-local.conf
# Forward only our specific zones to PowerDNS
# DO NOT forward all .local (breaks mDNS/Avahi)
server=/macula.local/192.168.129.9
server=/cortexiq.local/192.168.129.9
server=/beam.local/192.168.129.9
EOF

echo ""
echo "Restarting NetworkManager..."
sudo systemctl restart NetworkManager

echo ""
echo "Waiting for DNS to stabilize..."
sleep 5

echo ""
echo "✓ DNS configuration fixed!"
echo ""
echo "Testing DNS resolution..."
echo "Google (regular DNS):"
getent hosts google.com | head -1

echo ""
echo "Portal (PowerDNS):"
getent hosts portal.macula.local

echo ""
echo "If portal doesn't resolve, check PowerDNS:"
echo "  docker ps | grep powerdns"
echo "  curl -s http://192.168.129.9:8081/api/v1/servers/localhost/zones/macula.local. -H 'X-API-Key: SPUnDmhuBFnNgKYizc94HbMVdFpCs9st'"
