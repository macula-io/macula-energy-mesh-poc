#!/bin/bash
# Publish macula_client_ex 0.3.1 to Hex.pm
set -euo pipefail

cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/system/macula_client_ex

echo "========================================="
echo "Publishing macula_client_ex 0.3.1"
echo "========================================="
echo ""
echo "Now depends on consolidated macula package:"
echo "  {:macula, \"~> 0.3.1\"}"
echo ""

# Clean old dependencies
rm -rf mix.lock deps _build

echo "Fetching dependencies..."
mix deps.get

echo ""
echo "Building package..."
mix hex.build

echo ""
echo "Publishing to Hex.pm..."
mix hex.publish

echo ""
echo "✓ macula_client_ex 0.3.1 published successfully!"
echo "  Package: https://hex.pm/packages/macula_client_ex"
echo "  Docs: https://hexdocs.pm/macula_client_ex/"
echo ""
echo "CortexIQ apps can now use:"
echo "  {:macula_client_ex, \"~> 0.3.1\"}"
