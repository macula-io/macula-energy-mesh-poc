#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Stopping Harbor Registry"
echo "========================================="

cd "$SCRIPT_DIR"
docker-compose down

echo ""
echo "✓ Harbor stopped"
echo ""
echo "To remove all data, run:"
echo "  docker-compose down -v"
echo ""
