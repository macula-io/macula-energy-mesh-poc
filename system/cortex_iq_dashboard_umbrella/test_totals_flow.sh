#!/bin/bash
# Test script for totals calculation flow refactoring
# Expected flow:
# 1. cortex_iq_projections: CalculateSystemTotals.Aggregator subscribes to home.measured
# 2. cortex_iq_projections: Calculates totals every 500ms
# 3. cortex_iq_projections: Publishes to be.cortexiq.projections.totals_calculated
# 4. cortex_iq_dashboard: SubscribeTotalsCalculated.Subscriber receives totals
# 5. cortex_iq_dashboard: Broadcasts to dashboard:totals_calculated
# 6. cortex_iq_dashboard: OverviewAggregator receives and stores totals
# 7. cortex_iq_dashboard: Broadcasts to view:overview
# 8. cortex_iq_dashboard_web: OverviewLive updates UI

echo "=== Testing Totals Calculation Flow Refactoring ==="
echo ""
echo "Expected log flow:"
echo "  [cortex_iq_projections] CalculateSystemTotals.Aggregator: Subscribed to be.cortexiq.home.measured"
echo "  [cortex_iq_projections] CalculateSystemTotals.Aggregator: Received measurement from home_XXX"
echo "  [cortex_iq_projections] CalculateSystemTotals.Aggregator: Publishing totals - homes=N"
echo "  [cortex_iq_dashboard] SubscribeTotalsCalculated.Subscriber: Received totals - homes=N"
echo "  [cortex_iq_dashboard] OverviewAggregator: Received totals - homes=N, prod=XXX, cons=XXX, battery=XXX"
echo "  [cortex_iq_dashboard] OverviewAggregator: Broadcasting view update"
echo ""
echo "Starting test run for 30 seconds..."
echo ""

timeout 30 ./dev-local.sh 2>&1 | grep -E \
  "(CalculateSystemTotals|SubscribeTotalsCalculated|OverviewAggregator: Received totals|Broadcasting view)" \
  | head -50

echo ""
echo "=== Test Complete ==="
