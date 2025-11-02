#!/usr/bin/env bash
# Local development startup script for CortexIQ Dashboard
#
# This script:
# 1. Checks if KinD cluster is running
# 2. Verifies Bondy is accessible
# 3. Sets up port forwarding for PostgreSQL (optional)
# 4. Loads environment variables
# 5. Starts the Phoenix server

set -e

echo "🚀 Starting CortexIQ Dashboard in local development mode"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if KinD cluster is running
echo "📡 Checking KinD cluster status..."
if ! kubectl --context kind-macula-hub cluster-info &>/dev/null; then
    echo -e "${RED}❌ KinD cluster 'macula-hub' is not accessible${NC}"
    echo "   Start the cluster first with: kind create cluster --name macula-hub"
    exit 1
fi
echo -e "${GREEN}✓ KinD cluster is running${NC}"
echo ""

# Check if Bondy is accessible
echo "🔌 Checking Bondy WAMP router..."
if ! nc -z localhost 30080 2>/dev/null; then
    echo -e "${RED}❌ Bondy is not accessible on localhost:30080${NC}"
    echo "   Make sure the KinD cluster has Bondy deployed and NodePort is mapped correctly"
    echo "   Check: kubectl --context kind-macula-hub get svc -n macula-system bondy"
    exit 1
fi
echo -e "${GREEN}✓ Bondy is accessible at ws://localhost:30080/ws${NC}"
echo ""

# Check if PostgreSQL port forwarding is needed
echo "🗄️  Checking PostgreSQL access..."
if ! nc -z localhost 5432 2>/dev/null; then
    echo -e "${YELLOW}⚠ PostgreSQL is not accessible on localhost:5432${NC}"
    echo "   Starting port-forward in background..."
    kubectl --context kind-macula-hub port-forward -n macula-hub svc/postgres 5432:5432 &>/dev/null &
    PG_PF_PID=$!
    sleep 2
    if nc -z localhost 5432 2>/dev/null; then
        echo -e "${GREEN}✓ PostgreSQL port-forward established (PID: $PG_PF_PID)${NC}"
        echo "   To stop: kill $PG_PF_PID"
    else
        echo -e "${RED}❌ Failed to establish PostgreSQL port-forward${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ PostgreSQL is accessible at localhost:5432${NC}"
fi
echo ""

# Load environment variables
echo "📝 Loading environment variables from .env.dev..."
if [ -f ".env.dev" ]; then
    source .env.dev
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}❌ .env.dev file not found${NC}"
    exit 1
fi
echo ""

# Display connection info
echo "🔗 Connection Configuration:"
echo "   WAMP: ${BONDY_URL}"
echo "   Realm: ${BONDY_REALM}"
echo "   Database: ${DATABASE_URL}"
echo "   Phoenix: http://localhost:${PHX_PORT}"
echo ""

# Start Phoenix server
echo "🎯 Starting Phoenix server..."
echo "   Press Ctrl+C to stop"
echo ""
mix phx.server
