#!/bin/bash
# Local development startup script
# Starts Macula Platform with CortexIQ application

set -e

echo "🚀 Starting Macula Platform - Local Development"
echo "   Demo: CortexIQ Energy Trading Simulation"
echo ""

# Start infrastructure if not already running
if ! curl -s http://localhost:18081/realms >/dev/null 2>&1; then
  echo "📦 Starting infrastructure (Bondy, PostgreSQL)..."
  cd "$(dirname "$0")/dev-env"
  docker compose up -d
  cd ..

  echo "⏳ Waiting for services to be ready..."
  sleep 5
else
  echo "✅ Infrastructure already running"
fi

# Setup Bondy realm
echo ""
cd "$(dirname "$0")/dev-env"
./setup-realm.sh
cd ..

cd "$(dirname "$0")/system"

# Setup database if needed
echo "🗄️  Setting up database..."
mix ecto.create 2>/dev/null || echo "   Database already exists"
mix ecto.migrate

echo ""
echo "✅ Infrastructure ready!"
echo ""
echo "📊 Available services:"
echo "   - Bondy WAMP Router: ws://localhost:18080/ws"
echo "   - Bondy Admin API: http://localhost:18081"
echo "   - Bondy Console: http://localhost:3000"
echo "   - PostgreSQL: localhost:5432"
echo ""

# Set environment variables for local development
export MACULA_MODE="development" # Development mode (all-in-one)
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="be.cortexiq.energy" # CortexIQ realm
export BONDY_ADMIN_URL="http://localhost:18081"
export CORTEXIQ_HOME_COUNT="${CORTEXIQ_HOME_COUNT:-50}"        # Default: 50 homes
export CORTEXIQ_PROVIDER_COUNT="${CORTEXIQ_PROVIDER_COUNT:-5}" # Default: 5 providers
export SIMULATION_SPEED="${SIMULATION_SPEED:-105120}"          # 105,120x = 1 year in 5 min
export PHX_HOST="localhost"
export PORT="4000"

echo "🏢 Macula Platform Configuration:"
echo "   - Mode: All-in-one (development)"
echo "   - Realm: be.cortexiq.energy"
echo ""
echo "⚡ CortexIQ Simulation:"
echo "   - Homes: $CORTEXIQ_HOME_COUNT"
echo "   - Providers: $CORTEXIQ_PROVIDER_COUNT"
echo "   - Time acceleration: ${SIMULATION_SPEED}x"
echo ""
echo "📊 Dashboard: http://localhost:4000"
echo ""
echo "💡 Tips:"
echo "   - Override home count: CORTEXIQ_HOME_COUNT=100 ./start-local-dev.sh"
echo "   - Slow down time: SIMULATION_SPEED=10512 ./start-local-dev.sh (1 year in 50 min)"
echo ""

# Start all applications
iex --sname macula_dev -S mix phx.server
