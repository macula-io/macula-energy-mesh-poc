#!/usr/bin/env bash
set -e

echo "🗑️  Resetting CortexIQ database..."
echo ""

# Terminate connections to the database
echo "Terminating existing connections..."
kubectl --context kind-macula-hub exec -n macula-hub deploy/postgres -- \
  psql -U cortexiq -d postgres -c "
    SELECT pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE pg_stat_activity.datname = 'cortexiq_dashboard'
      AND pid <> pg_backend_pid();"

# Drop and recreate the database
echo "Dropping and recreating cortexiq_dashboard database..."
kubectl --context kind-macula-hub exec -n macula-hub deploy/postgres -- \
  psql -U cortexiq -d postgres -c "DROP DATABASE IF EXISTS cortexiq_dashboard;"

kubectl --context kind-macula-hub exec -n macula-hub deploy/postgres -- \
  psql -U cortexiq -d postgres -c "CREATE DATABASE cortexiq_dashboard OWNER cortexiq;"

echo "✅ Database reset complete!"
echo ""

# Restart projections to run migrations
echo "🔄 Restarting cortex-iq-projections to run migrations..."
kubectl --context kind-macula-hub rollout restart -n macula-hub deployment/cortex-iq-projections

echo "⏳ Waiting for projections to start..."
kubectl --context kind-macula-hub rollout status -n macula-hub deployment/cortex-iq-projections --timeout=60s

echo ""
echo "📊 Checking migrations ran..."
kubectl --context kind-macula-hub logs -n macula-hub deploy/cortex-iq-projections --tail=50 | grep -i "migration"

echo ""
echo "🔍 Verifying tables..."
kubectl --context kind-macula-hub exec -n macula-hub deploy/cortex-iq-projections -- \
  psql postgresql://cortexiq:cortexiq123@postgres.macula-hub.svc.cluster.local:5432/cortexiq_dashboard \
  -c "\dt"

echo ""
echo "✅ Database reset and migrations complete!"
echo ""
echo "Next: Restart the simulation to populate data:"
echo "  - Restart homes: kubectl --context kind-macula-edge-02 rollout restart -n macula-edge deploy/cortex-iq-homes"
echo "  - Or use the reset button in the dashboard"
