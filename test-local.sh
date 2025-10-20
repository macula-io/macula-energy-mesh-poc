#!/bin/bash
set -e

echo "=========================================="
echo "  Energy Mesh - Local Test"
echo "=========================================="
echo ""

# Ensure Bondy is running
if ! curl -s -f http://localhost:18081/ping > /dev/null 2>&1; then
    echo "Starting Bondy..."
    cd dev-env
    docker-compose up -d bondy
    cd ..

    echo "Waiting for Bondy to start..."
    for i in {1..30}; do
        if curl -s -f http://localhost:18081/ping > /dev/null 2>&1; then
            echo "Bondy is ready!"
            break
        fi
        sleep 1
        echo -n "."
    done
    echo ""
fi

echo ""
echo "Starting mesh_hub (creates realm automatically)..."
echo "Press Ctrl+C to stop"
echo ""

cd system

# Set environment variables
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="com.energy.mesh"
export BONDY_ADMIN_URL="http://localhost:18081"
export DATABASE_URL="ecto://postgres:postgres@localhost/mesh_hub_dev"
export SECRET_KEY_BASE="local-test-secret-key-base-not-for-production"
export PHX_HOST="localhost"
export PORT="4000"

# Start the Phoenix server
iex -S mix phx.server
