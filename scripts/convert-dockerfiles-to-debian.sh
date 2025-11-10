#!/usr/bin/env bash
# Convert all CortexIQ Dockerfiles from Alpine to Debian for better quicer support

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

  echo "Converting $dockerfile to Debian..."

  # Replace Alpine builder image with Debian
  sed -i 's|hexpm/elixir:1\.18\.1-erlang-26\.2\.5\.6-alpine-3\.20\.3|hexpm/elixir:1.18.1-erlang-26.2.5.6-debian-bookworm-20241202-slim|g' "$filepath"

  # Replace Alpine runtime image with Debian
  sed -i 's|alpine:3\.20\.3|debian:bookworm-20241202-slim|g' "$filepath"

  # Replace apk commands with apt-get for build dependencies
  sed -i '/RUN apk add --no-cache/,/linux-headers/ {
    s|RUN apk add --no-cache|RUN apt-get update \&\& apt-get install -y|
    s|build-base|build-essential|
    s|openssh-client|openssh-client|
    s|cmake|cmake|
    s|linux-headers|libssl-dev \&\& rm -rf /var/lib/apt/lists/*|
  }' "$filepath"

  # Replace apk commands for runtime dependencies
  sed -i '/# Install runtime dependencies/,/libgcc/ {
    s|RUN apk add --no-cache|RUN apt-get update \&\& apt-get install -y|
    s|openssl|openssl|
    s|ncurses-libs|libncurses6|
    s|libstdc++|libstdc++6|
    s|libgcc|libssl3 \&\& rm -rf /var/lib/apt/lists/*|
  }' "$filepath"

  # Replace Alpine adduser/addgroup with Debian groupadd/useradd
  sed -i 's|addgroup -g 1000 cortexiq|groupadd -g 1000 cortexiq|g' "$filepath"
  sed -i 's|adduser -D -u 1000 -G cortexiq cortexiq|useradd -u 1000 -g cortexiq -m -s /bin/bash cortexiq|g' "$filepath"

  echo "✓ Converted $dockerfile"
done

echo ""
echo "All Dockerfiles converted to Debian!"
