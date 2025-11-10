#!/usr/bin/env bash
# Update macula_client_ex dependency version across all CortexIQ apps
set -euo pipefail

NEW_VERSION="${1:-0.2.2}"

echo "==================================================================="
echo "Updating macula_client_ex to version ~> ${NEW_VERSION}"
echo "==================================================================="
echo ""

cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/system

# Find all mix.exs files with macula_client_ex dependency
APPS=(
  "cortex_iq_simulation"
  "cortex_iq_homes"
  "cortex_iq_utilities"
  "cortex_iq_projections"
  "cortex_iq_queries"
  "cortex_iq_dashboard_umbrella/apps/cortex_iq_dashboard"
)

for app in "${APPS[@]}"; do
  MIX_FILE="$app/mix.exs"

  if [ -f "$MIX_FILE" ]; then
    echo "Updating $MIX_FILE..."
    sed -i "s/{:macula_client_ex, \"~> 0\.2\.[0-9]\+\"/{:macula_client_ex, \"~> ${NEW_VERSION}\"/" "$MIX_FILE"
    echo "  ✅ Updated to ~> ${NEW_VERSION}"
  else
    echo "  ⚠️  File not found: $MIX_FILE"
  fi
done

echo ""
echo "==================================================================="
echo "✅ Version update complete!"
echo "==================================================================="
echo ""
echo "Next step: Rebuild Docker images"
echo "  cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc"
echo "  ./scripts/build-all-images.sh"
echo ""
