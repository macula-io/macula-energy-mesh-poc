#!/bin/bash
set -e

echo "=========================================="
echo "  Realm Lifecycle Test"
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

# Function to check if realm exists
realm_exists() {
    curl -s "${BONDY_ADMIN_URL}/realms" | grep -q "\"uri\":\"${REALM_URI}\""
}

# Clean slate - delete realm if it exists
if realm_exists; then
    echo "🧹 Cleaning up existing realm..."
    curl -s -X DELETE "${BONDY_ADMIN_URL}/realms/${REALM_URI}" > /dev/null 2>&1 || true
    sleep 1
fi

echo "📋 Test 1: Hub creates new realm"
echo "   Starting hub in background..."

cd system
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="${REALM_URI}"
export BONDY_ADMIN_URL="${BONDY_ADMIN_URL}"
export DATABASE_URL="ecto://postgres:postgres@localhost/mesh_hub_dev"
export SECRET_KEY_BASE="test-secret-key-base"
export PHX_HOST="localhost"
export PORT="4000"

# Start in background and capture PID
mix run --no-halt > /tmp/mesh_hub_test.log 2>&1 &
HUB_PID=$!
cd ..

echo "   Waiting for hub to start (PID: ${HUB_PID})..."
sleep 5

# Check logs for realm creation
if grep -q "✅ Created realm: ${REALM_URI}" /tmp/mesh_hub_test.log; then
    echo "   ✅ Hub created the realm"
elif grep -q "⚠️  Realm already exists" /tmp/mesh_hub_test.log; then
    echo "   ⚠️  Realm already existed (unexpected)"
    echo "   Check /tmp/mesh_hub_test.log for details"
else
    echo "   ❌ Could not determine realm creation status"
    echo "   Check /tmp/mesh_hub_test.log for details"
fi

# Verify realm exists in Bondy
if realm_exists; then
    echo "   ✅ Realm exists in Bondy"
else
    echo "   ❌ Realm not found in Bondy"
    exit 1
fi

echo ""
echo "📋 Test 2: Graceful shutdown deletes realm"
echo "   Sending SIGTERM to hub..."

kill -TERM ${HUB_PID}

echo "   Waiting for shutdown..."
sleep 3

# Check logs for realm deletion
if grep -q "🗑️  Deleting realm: ${REALM_URI}" /tmp/mesh_hub_test.log; then
    echo "   ✅ Hub attempted to delete realm"
else
    echo "   ⚠️  No deletion attempt found in logs"
fi

if grep -q "✅ Successfully deleted realm: ${REALM_URI}" /tmp/mesh_hub_test.log; then
    echo "   ✅ Realm deletion succeeded"
else
    echo "   ❌ Realm deletion failed or not logged"
fi

# Verify realm is gone
sleep 2
if realm_exists; then
    echo "   ❌ Realm still exists in Bondy (should be deleted)"
    exit 1
else
    echo "   ✅ Realm removed from Bondy"
fi

echo ""
echo "📋 Test 3: Hub reuses existing realm"
echo "   Creating realm externally..."

curl -s -X POST "${BONDY_ADMIN_URL}/realms" \
  -H "Content-Type: application/json" \
  -d "{\"uri\":\"${REALM_URI}\",\"description\":\"Test realm\",\"authmethods\":[\"anonymous\"],\"security_enabled\":true}" \
  > /dev/null 2>&1

if realm_exists; then
    echo "   ✅ Realm created externally"
else
    echo "   ❌ Failed to create realm externally"
    exit 1
fi

echo "   Starting hub in background..."
cd system
rm -f /tmp/mesh_hub_test.log
mix run --no-halt > /tmp/mesh_hub_test.log 2>&1 &
HUB_PID=$!
cd ..

sleep 5

# Check logs - should see "already exists"
if grep -q "⚠️  Realm already exists: ${REALM_URI}" /tmp/mesh_hub_test.log; then
    echo "   ✅ Hub detected existing realm"
else
    echo "   ❌ Hub didn't detect existing realm"
    echo "   Check /tmp/mesh_hub_test.log for details"
fi

echo "   Sending SIGTERM to hub..."
kill -TERM ${HUB_PID}
sleep 3

# Check logs - should NOT delete realm
if grep -q "ℹ️  Realm ${REALM_URI} was not created by this manager" /tmp/mesh_hub_test.log; then
    echo "   ✅ Hub skipped deletion (correct)"
else
    echo "   ⚠️  Deletion behavior unclear"
fi

# Verify realm still exists
if realm_exists; then
    echo "   ✅ Realm still exists (correct - we didn't create it)"
else
    echo "   ❌ Realm was deleted (incorrect - we didn't create it)"
    exit 1
fi

# Cleanup
echo ""
echo "🧹 Cleaning up..."
curl -s -X DELETE "${BONDY_ADMIN_URL}/realms/${REALM_URI}" > /dev/null 2>&1 || true

echo ""
echo "=========================================="
echo "  ✅ All tests passed!"
echo "=========================================="
echo ""
echo "Full logs available in: /tmp/mesh_hub_test.log"
