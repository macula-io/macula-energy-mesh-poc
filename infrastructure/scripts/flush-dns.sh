#!/bin/bash
# Flush DNS caches and reload PowerDNS

echo "=== Flushing DNS Caches ==="

# Flush systemd-resolved cache if running
if systemctl is-active --quiet systemd-resolved; then
    echo "→ Flushing systemd-resolved cache..."
    sudo resolvectl flush-caches || sudo systemd-resolve --flush-caches
    echo "✓ systemd-resolved cache flushed"
else
    echo "ℹ systemd-resolved is not running"
fi

# Flush NetworkManager's dnsmasq if running
if pgrep -x dnsmasq > /dev/null; then
    echo "→ Restarting NetworkManager to flush dnsmasq cache..."
    sudo systemctl restart NetworkManager
    echo "✓ NetworkManager restarted"
else
    echo "ℹ dnsmasq is not running"
fi

# Restart PowerDNS container
echo "→ Restarting PowerDNS container..."
docker restart macula-dns-powerdns
echo "✓ PowerDNS container restarted"

# Wait for PowerDNS to be healthy
echo "→ Waiting for PowerDNS to become healthy..."
for i in {1..30}; do
    status=$(docker inspect --format='{{.State.Health.Status}}' macula-dns-powerdns 2>/dev/null || echo "unknown")
    if [ "$status" = "healthy" ]; then
        echo "✓ PowerDNS is healthy"
        break
    fi
    echo "  Waiting... ($i/30) Status: $status"
    sleep 2
done

# Test DNS resolution
echo ""
echo "=== Testing DNS Resolution ==="
echo "→ Testing portal.macula.local..."
getent hosts portal.macula.local || echo "✗ Failed to resolve portal.macula.local"

echo "→ Testing pgadmin.macula.local..."
getent hosts pgadmin.macula.local || echo "✗ Failed to resolve pgadmin.macula.local"

echo "→ Testing dashboard.cortexiq.local..."
getent hosts dashboard.cortexiq.local || echo "✗ Failed to resolve dashboard.cortexiq.local"

echo ""
echo "=== DNS Flush Complete ==="
echo "If DNS records still don't resolve, they may need to be added to PowerDNS database."
echo "Check with: docker exec macula-dns-postgres psql -U powerdns -d powerdns -c \"SELECT name, content FROM records WHERE name LIKE '%macula.local';\""
