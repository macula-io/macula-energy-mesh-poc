#!/usr/bin/env bash

# Local Development Script for CortexIQ Projections Service
# Runs the projections Broadway pipeline locally for development

set -e

echo "🚀 Starting CortexIQ Projections Service in local development mode"
echo ""

# Check prerequisites
echo "📡 Checking prerequisites..."

if ! kubectl --context kind-macula-hub get nodes &>/dev/null; then
    echo "❌ KinD cluster 'macula-hub' not running"
    echo "   Start it with: kind create cluster --name macula-hub"
    exit 1
fi

# Check WAMP connectivity
if ! curl -s http://localhost:30080 &>/dev/null; then
    echo "❌ Bondy WAMP router not accessible at localhost:30080"
    echo "   Ensure Bondy is running and port-forwarded"
    exit 1
fi

echo "✓ KinD cluster is running"
echo "✓ Bondy is accessible at ws://localhost:30080/ws"

# Check database connectivity (PostgreSQL should be accessible at localhost:5432)
# This requires kubectl port-forward to be running:
#   kubectl --context kind-macula-hub port-forward -n macula-hub svc/postgres 5432:5432
if ! timeout 2 bash -c "</dev/tcp/localhost/5432" 2>/dev/null; then
    echo "❌ PostgreSQL not accessible at localhost:5432"
    echo "   Start port-forward with:"
    echo "   kubectl --context kind-macula-hub port-forward -n macula-hub svc/postgres 5432:5432"
    exit 1
fi

echo "✓ PostgreSQL is accessible at localhost:5432"
echo ""

# Set environment variables for projections service
export DATABASE_URL="ecto://cortexiq:cortexiq123@localhost:5432/cortexiq_dashboard"
export BONDY_URL="ws://localhost:30080/ws"
export BONDY_REALM="be.cortexiq.energy"

echo "🔗 Connection Configuration:"
echo "   WAMP: $BONDY_URL"
echo "   Realm: $BONDY_REALM"
echo "   Database: $DATABASE_URL"
echo ""

echo "🎯 Starting Projections Service..."
echo "   Press Ctrl+C to stop"
echo ""

cd "$(dirname "$0")"
exec mix run --no-halt
