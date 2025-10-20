#!/bin/bash
set -e

echo "=========================================="
echo "  Quick Shutdown Test"
echo "=========================================="
echo ""

BONDY_ADMIN_URL="http://localhost:18081"
REALM_URI="com.energy.mesh"

# Check if Bondy is running
if ! curl -s -f "${BONDY_ADMIN_URL}/ping" > /dev/null 2>&1; then
    echo "❌ Bondy is not running!"
    echo "   Start it with: cd dev-env && docker-compose up -d bondy"
    exit 1
fi

echo "✅ Bondy is running"
echo ""

# Clean up existing realm
curl -s -X DELETE "${BONDY_ADMIN_URL}/realms/${REALM_URI}" > /dev/null 2>&1 || true
sleep 1

echo "Starting hub in background..."
cd system
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="${REALM_URI}"
export BONDY_ADMIN_URL="${BONDY_ADMIN_URL}"
export DATABASE_URL="ecto://postgres:postgres@localhost/mesh_hub_dev"
export SECRET_KEY_BASE="test-secret-key-base"
export PHX_HOST="localhost"
export PORT="4000"

mix run --no-halt > /tmp/hub_shutdown_test.log 2>&1 &
PID=$!
cd ..

echo "Hub PID: $PID"
echo "Waiting for startup (5 seconds)..."
sleep 5

# Check if realm was created
if curl -s "${BONDY_ADMIN_URL}/realms" | grep -q "\"uri\":\"${REALM_URI}\""; then
    echo "✅ Realm exists in Bondy"
else
    echo "❌ Realm not found in Bondy"
    kill -9 $PID 2>/dev/null || true
    exit 1
fi

echo ""
echo "Sending SIGTERM to hub (PID: $PID)..."
kill -TERM $PID

echo "Waiting for shutdown (3 seconds)..."
sleep 3

echo ""
echo "============================================================"
echo "Shutdown Logs:"
echo "============================================================"
grep -E "(shutdown|terminate|Deleting realm|Successfully deleted)" /tmp/hub_shutdown_test.log | tail -15

echo ""
echo "============================================================"
echo "Realm Status After Shutdown:"
echo "============================================================"

if curl -s "${BONDY_ADMIN_URL}/realms" | grep -q "\"uri\":\"${REALM_URI}\""; then
    echo "❌ FAIL: Realm still exists in Bondy"
    echo ""
    echo "Check logs in: /tmp/hub_shutdown_test.log"
    exit 1
else
    echo "✅ SUCCESS: Realm deleted from Bondy"
fi

echo ""
echo "Full logs available in: /tmp/hub_shutdown_test.log"
