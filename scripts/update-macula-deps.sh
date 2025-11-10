#!/bin/bash
#
# Update all CortexIQ apps to use macula v0.3.4 from Hex
# instead of old macula_client_ex and macula_sdk packages
#

set -e

APPS=(
  "cortex_iq_homes"
  "cortex_iq_utilities"
  "cortex_iq_projections"
  "cortex_iq_queries"
  "cortex_iq_dashboard_umbrella/apps/cortex_iq_dashboard"
)

for app in "${APPS[@]}"; do
  MIX_FILE="system/${app}/mix.exs"

  if [ ! -f "$MIX_FILE" ]; then
    echo "Skipping $app - mix.exs not found"
    continue
  fi

  echo "Updating $app..."

  # Replace macula_client_ex and macula_sdk with macula
  sed -i 's/{:macula_client_ex, "~> 0\.3\.0", override: true}/{:macula, "~> 0.3.4"}/g' "$MIX_FILE"
  sed -i 's/{:macula_client_ex, "~> 0\.3\.0"}/{:macula, "~> 0.3.4"}/g' "$MIX_FILE"
  sed -i 's/{:macula_sdk, "~> 0\.3\.0", override: true}/{:macula, "~> 0.3.4"}/g' "$MIX_FILE"
  sed -i 's/{:macula_sdk, "~> 0\.3\.0"}/{:macula, "~> 0.3.4"}/g' "$MIX_FILE"

  # Update comments
  sed -i 's/# Client library (Free, Open Source) - connects to standalone gateway/# Macula HTTP\/3 Mesh Platform/g' "$MIX_FILE"
  sed -i 's/# Macula SDK/# Macula HTTP\/3 Mesh Platform/g' "$MIX_FILE"
done

echo "✅ All apps updated to use {:macula, \"~> 0.3.4\"}"
echo ""
echo "Next steps:"
echo "1. Clean deps: find system -name deps -type d -exec rm -rf {} +"
echo "2. Clean build: find system -name _build -type d -exec rm -rf {} +"
echo "3. Rebuild images: ./scripts/build-all-images.sh"
