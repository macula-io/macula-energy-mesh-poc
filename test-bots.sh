#!/bin/bash
set -e

echo "=========================================="
echo "  Energy Mesh - Test Bots"
echo "=========================================="
echo ""

# Check if realm exists
if ! curl -s http://localhost:18081/realms/com.energy.mesh > /dev/null 2>&1; then
    echo "Error: Realm 'com.energy.mesh' does not exist!"
    echo "Start mesh_hub first to create the realm."
    echo ""
    echo "Run: ./test-local.sh"
    exit 1
fi

echo "Realm 'com.energy.mesh' exists!"
echo ""

# Set environment variables
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="com.energy.mesh"

echo "Choose which bots to run:"
echo "1) Home bots (5 homes)"
echo "2) Provider bots (5 providers)"
echo "3) Both"
echo ""
read -p "Enter choice (1-3): " choice

cd system

case $choice in
    1)
        echo "Starting 5 home bots..."
        export HOME_COUNT=5
        export HOME_ID_OFFSET=0
        iex -S mix run -e "Application.ensure_all_started(:mesh_edge_homes)"
        ;;
    2)
        echo "Starting 5 provider bots..."
        export PROVIDER_COUNT=5
        iex -S mix run -e "Application.ensure_all_started(:mesh_edge_utilities)"
        ;;
    3)
        echo "Starting both home and provider bots..."
        echo "This will run in foreground. Press Ctrl+C to stop."
        export HOME_COUNT=5
        export HOME_ID_OFFSET=0
        export PROVIDER_COUNT=5

        # Start both applications
        iex -S mix run -e "Application.ensure_all_started(:mesh_edge_homes); Application.ensure_all_started(:mesh_edge_utilities)"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
