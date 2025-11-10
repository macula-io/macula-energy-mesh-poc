#!/usr/bin/env bash
# Add CACHE_BUST ARG to all CortexIQ Dockerfiles to force fresh dependency fetches

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DOCKERFILES=(
  "system/cortex_iq_homes/Dockerfile"
  "system/cortex_iq_utilities/Dockerfile"
  "system/cortex_iq_projections/Dockerfile"
  "system/cortex_iq_queries/Dockerfile"
  "system/cortex_iq_prezio/Dockerfile"
  "system/cortex_iq_open_weather_map/Dockerfile"
  "system/cortex_iq_dashboard_umbrella/Dockerfile"
)

for dockerfile in "${DOCKERFILES[@]}"; do
  filepath="$REPO_ROOT/$dockerfile"

  if [ ! -f "$filepath" ]; then
    echo "Skipping $dockerfile (not found)"
    continue
  fi

  # Check if ARG CACHE_BUST already exists
  if grep -q "ARG CACHE_BUST" "$filepath"; then
    echo "✓ $dockerfile already has CACHE_BUST"
    continue
  fi

  echo "Adding CACHE_BUST to $dockerfile..."

  # Add ARG CACHE_BUST before the COPY mix.exs line
  # Using sed to insert before the first COPY line that contains mix.exs
  sed -i '/^COPY.*mix\.exs/i\# Cache bust argument (forces fresh dependency fetch)\nARG CACHE_BUST\n' "$filepath"

  echo "✓ Updated $dockerfile"
done

echo ""
echo "All Dockerfiles updated!"
