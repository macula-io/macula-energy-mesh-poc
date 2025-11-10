#!/usr/bin/env bash
# Fix Dockerfiles to use correct official Elixir Debian images

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DOCKERFILES=(
  "system/cortex_iq_simulation/Dockerfile"
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

  echo "Fixing $dockerfile..."

  # Replace hexpm image with official Elixir image (Debian-based)
  sed -i 's|FROM hexpm/elixir:1\.18\.1-erlang-26\.2\.5\.6-debian-bookworm-20241202-slim|FROM elixir:1.18-otp-26|g' "$filepath"

  # Replace runtime Debian image tag
  sed -i 's|FROM debian:bookworm-20241202-slim|FROM debian:bookworm-slim|g' "$filepath"

  echo "✓ Fixed $dockerfile"
done

echo ""
echo "All Dockerfiles updated with correct base images!"
