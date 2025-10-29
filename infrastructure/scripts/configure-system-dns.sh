#!/bin/bash
# Configure system DNS to use PowerDNS for .local domains

set -e

PDNS_IP="192.168.129.9"

echo "Configuring NetworkManager to use dnsmasq with PowerDNS..."

# Create NetworkManager dnsmasq configuration
echo "Creating NetworkManager dnsmasq configuration..."
sudo mkdir -p /etc/NetworkManager/dnsmasq.d

cat <<EOF | sudo tee /etc/NetworkManager/dnsmasq.d/macula-local.conf
# Forward all .local domain queries to PowerDNS
server=/local/$PDNS_IP

# Explicitly forward our zones
server=/macula.local/$PDNS_IP
server=/cortexiq.local/$PDNS_IP
server=/beam.local/$PDNS_IP
EOF

# Configure NetworkManager to use dnsmasq
echo "Configuring NetworkManager main config..."
sudo mkdir -p /etc/NetworkManager/conf.d

cat <<EOF | sudo tee /etc/NetworkManager/conf.d/00-use-dnsmasq.conf
[main]
dns=dnsmasq
EOF

echo "Restarting NetworkManager..."
sudo systemctl restart NetworkManager

echo ""
echo "Waiting for NetworkManager to settle..."
sleep 3

echo ""
echo "✓ DNS configured successfully!"
echo ""
echo "Testing DNS resolution..."
echo "  portal.macula.local:"
dig @127.0.0.1 portal.macula.local +short 2>/dev/null || nslookup portal.macula.local 127.0.0.1 2>/dev/null | grep Address | tail -1

echo ""
echo "You can now access services via DNS:"
echo "  http://portal.macula.local"
echo "  http://hub.macula.local"
echo "  http://console.macula.local"
echo ""
echo "Note: .local queries → PowerDNS (192.168.129.9)"
echo "      Other queries → Your regular DNS"
