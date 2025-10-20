#!/bin/bash
set -e

# Setup script for Energy Mesh PoC
# NOTE: Realms are now created dynamically by mesh_hub when it starts!
# This script just verifies Bondy is accessible.

BONDY_ADMIN_API="${BONDY_ADMIN_API:-http://localhost:18081}"

echo "Checking Bondy status..."

# Check if Bondy is running
if ! curl -s -f "${BONDY_ADMIN_API}/ping" > /dev/null 2>&1; then
    echo "Error: Bondy Admin API is not accessible at ${BONDY_ADMIN_API}"
    echo "Make sure Bondy is running: docker-compose up -d bondy"
    exit 1
fi

echo ""
echo "✅ Bondy is running and accessible!"
echo "   Admin API: ${BONDY_ADMIN_API}"
echo ""
echo "NOTE: Realms are created automatically by mesh_hub when it starts."
echo "      Start the hub to create the 'com.energy.mesh' realm."
echo ""
echo "To list current realms:"
echo "  curl -s ${BONDY_ADMIN_API}/realms | python3 -m json.tool"
echo ""
echo "Run tests with: cd ../system && mix test apps/mesh_wamp/test/integration_test.exs"
