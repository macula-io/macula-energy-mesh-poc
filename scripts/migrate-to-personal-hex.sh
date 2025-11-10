#!/usr/bin/env bash
# Migrate macula_client_ex from "macula" user account to "rgfaber" personal account
set -euo pipefail

echo "==================================================================="
echo "Migrating macula_client_ex Ownership"
echo "==================================================================="
echo ""
echo "Current state:"
echo "  - macula_sdk (Erlang): Owned by 'rgfaber' (correct!)"
echo "  - macula_client_ex (Elixir): Owned by 'macula' user (needs transfer)"
echo ""
echo "Package transfer requires access to BOTH accounts:"
echo "  1. 'macula' account - to add rgfaber as owner"
echo "  2. 'rgfaber' account - to accept ownership and remove macula"
echo ""
echo "Options:"
echo "  A) Transfer ownership (if you control 'macula' account)"
echo "  B) Just use existing package (keep under 'macula' user)"
echo ""

read -p "Choose option (A/B): " -n 1 -r
echo

if [[ $REPLY =~ ^[Bb]$ ]]; then
    echo ""
    echo "Keeping package under 'macula' user account."
    echo "No action needed - package is already public and usable."
    exit 0
fi

if [[ ! $REPLY =~ ^[Aa]$ ]]; then
    echo "Invalid choice. Aborted."
    exit 1
fi

echo ""
echo "==================================================================="
echo "Transfer Process"
echo "==================================================================="
echo ""
echo "Step 1: Add rgfaber as owner (requires 'macula' account API key)"
echo "---------------------------------------------------------------"
echo "You need to run this command while authenticated as 'macula':"
echo ""
echo "  export HEX_API_KEY=<macula-account-key>"
echo "  mix hex.owner add macula_client_ex rgfaber"
echo ""
read -p "Have you added rgfaber as owner? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please add rgfaber as owner first."
    exit 1
fi

echo ""
echo "Step 2: Switch to rgfaber account"
echo "---------------------------------------------------------------"
echo "Current HEX_API_KEY: ${HEX_API_KEY:0:20}..."
echo ""
echo "If this is still the 'macula' key, please:"
echo "  1. Get your rgfaber API key: mix hex.user key list"
echo "  2. Export it: export HEX_API_KEY=<your-rgfaber-key>"
echo ""
read -p "Is HEX_API_KEY set to rgfaber account? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please set your rgfaber HEX_API_KEY and run this script again."
    exit 1
fi

echo ""
echo "Step 3: Remove 'macula' as owner (requires 'rgfaber' account)"
echo "---------------------------------------------------------------"
echo "Now we'll remove the 'macula' account as owner:"
echo ""

cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc/system/macula_client_ex

mix hex.owner remove macula_client_ex macula

echo ""
echo "==================================================================="
echo "✅ Ownership Transfer Complete!"
echo "==================================================================="
echo ""
echo "Package 'macula_client_ex' is now owned by 'rgfaber' only."
echo ""
echo "All three versions (0.2.0, 0.2.1, 0.2.2) remain published and usable."
echo "No rebuild needed - apps can continue using the existing versions."
echo ""
