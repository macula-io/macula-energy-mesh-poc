#!/bin/bash
# Local development startup script
# Starts all applications in the umbrella for testing

set -e

echo "🚀 Starting Macula Energy Mesh - Local Development"
echo ""

cd "$(dirname "$0")/system"

# Check if Bondy is running
if ! curl -s http://localhost:18081/realms > /dev/null 2>&1; then
  echo "❌ Bondy is not running at localhost:18081"
  echo "   Start Bondy first with: cd dev-env && docker-compose up -d"
  exit 1
fi

echo "✅ Bondy is running"
echo ""

# Set environment variables for local development
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="com.energy.mesh"
export BONDY_ADMIN_URL="http://localhost:18081"
export HOME_COUNT="10"        # 10 homes for local testing
export PROVIDER_COUNT="5"     # 5 providers
export PHX_HOST="localhost"
export PORT="4000"

echo "🏠 Starting with $HOME_COUNT homes and $PROVIDER_COUNT providers"
echo "📊 Dashboard will be at http://localhost:4000"
echo ""

# Start all applications (.iex.exs will auto-start bots)
iex -S mix phx.server
