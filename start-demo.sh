#!/bin/bash
set -e

echo "=========================================="
echo "  Macula Energy Mesh PoC - Starting Demo"
echo "=========================================="
echo ""

# Step 1: Start Bondy and Bondy Console
echo "Step 1/3: Starting Bondy WAMP router..."
cd dev-env
docker-compose up -d bondy bondy_console

# Wait for Bondy to be ready
echo "Waiting for Bondy to start..."
max_attempts=30
attempt=0
while ! curl -s -f http://localhost:18081/ping > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "Error: Bondy failed to start after ${max_attempts} seconds"
        exit 1
    fi
    sleep 1
    echo -n "."
done
echo " Bondy is ready!"

# Step 2: Setup realm
echo ""
echo "Step 2/3: Configuring Energy Mesh realm..."
./setup-realm.sh

# Step 3: Run tests to verify everything works
echo ""
echo "Step 3/3: Running integration tests..."
cd ../system
mix deps.get
mix compile
mix test apps/mesh_wamp/test/integration_test.exs

echo ""
echo "=========================================="
echo "  ✅ Demo Environment Ready!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Bondy WAMP Router: ws://localhost:18080/ws"
echo "  - Bondy Admin API: http://localhost:18081"
echo "  - Bondy Console: http://localhost:3000"
echo ""
echo "Realm: com.energy.mesh (anonymous auth)"
echo ""
echo "Next steps:"
echo "  - Implement home and provider bots"
echo "  - Build Phoenix LiveView dashboard"
echo "  - Start energy trading simulation"
echo ""
