#!/usr/bin/env bash
# Add cmake and linux-headers to all CortexIQ Dockerfiles for quicer NIF compilation

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
)

for dockerfile in "${DOCKERFILES[@]}"; do
  filepath="$REPO_ROOT/$dockerfile"

  if [ ! -f "$filepath" ]; then
    echo "Skipping $dockerfile (not found)"
    continue
  fi

  # Check if cmake is already in the file
  if grep -q "cmake" "$filepath"; then
    echo "✓ $dockerfile already has cmake"
    continue
  fi

  echo "Adding cmake and linux-headers to $dockerfile..."

  # Find the RUN apk add line and add cmake + linux-headers
  sed -i '/RUN apk add --no-cache/,/openssh-client/ {
    s/openssh-client/openssh-client \\\n    cmake \\\n    linux-headers/
  }' "$filepath"

  echo "✓ Updated $dockerfile"
done

echo ""
echo "All Dockerfiles updated with quicer build dependencies!"
