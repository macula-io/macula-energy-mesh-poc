#!/bin/bash

# Wrapper script to run edge-k3s-setup.sh with environment variables from .k3s-env
# This script sources the environment before executing the main setup script

echo "🔧 Loading environment from ~/.k3s-env..."

# Source .k3s-env to get environment variables
if [ -f ~/.k3s-env ]; then
    source ~/.k3s-env
else
    echo "❌ ERROR: ~/.k3s-env not found"
    exit 1
fi

# Verify required environment variables
if [ -z "$GITHUB_USER" ]; then
    echo "❌ ERROR: GITHUB_USER not set"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ ERROR: GITHUB_TOKEN not set"
    exit 1
fi

if [ -z "$GITOPS_REPO" ]; then
    echo "❌ ERROR: GITOPS_REPO not set"
    exit 1
fi

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ ERROR: CLUSTER_NAME not set"
    exit 1
fi

echo "✅ Environment loaded:"
echo "   CLUSTER_NAME: $CLUSTER_NAME"
echo "   GITHUB_USER: $GITHUB_USER"
echo "   GITOPS_REPO: $GITOPS_REPO"
echo ""

# Export all variables to ensure they're available to child processes
export GITHUB_USER
export GITHUB_TOKEN
export GITOPS_REPO
export CLUSTER_NAME
export GITOPS_BRANCH="${GITOPS_BRANCH:-feature/competition}"

# Run the actual setup script
exec bash ~/edge-k3s-setup.sh "$@"
