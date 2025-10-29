#!/bin/bash
# Update dnsmasq configuration after PowerDNS restart
# PowerDNS now runs at 172.22.0.10 (Docker network, not host)

set -e

echo "Updating dnsmasq configuration..."
echo "PowerDNS is now at 172.22.0.10 (Docker network)"
echo ""

cat <<'EOF' | sudo tee /etc/NetworkManager/dnsmasq.d/macula-local.conf
# Forward only our specific zones to PowerDNS
# DO NOT forward all .local (breaks mDNS/Avahi)
# PowerDNS runs in Docker at 172.22.0.10
server=/macula.local/172.22.0.10
server=/cortexiq.local/172.22.0.10
server=/beam.local/172.22.0.10
EOF

echo ""
echo "Restarting NetworkManager..."
sudo systemctl restart NetworkManager

echo ""
echo "Waiting for DNS to stabilize..."
sleep 5

echo ""
echo "✓ DNS configuration updated!"
echo ""
echo "Testing DNS resolution..."
echo "Google (regular DNS):"
getent hosts google.com | head -1

echo ""
echo "Portal (PowerDNS via dnsmasq):"
getent hosts portal.macula.local || echo "⚠ Portal not resolving - may need to wait for DNS records to be re-created"

echo ""
echo "If portal doesn't resolve, check:"
echo "  1. PowerDNS API: curl -s http://192.168.129.9:8081/api/v1/servers/localhost/zones/macula.local. -H 'X-API-Key: SPUnDmhuBFnNgKYizc94HbMVdFpCs9st'"
echo "  2. ExternalDNS pods: kubectl get pods -n external-dns --context kind-macula-hub"
