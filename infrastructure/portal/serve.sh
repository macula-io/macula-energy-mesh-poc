#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-3000}"

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_step() {
    echo -e "${CYAN}▸${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}!${NC} $1"
}

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    log_warn "python3 not found, trying python..."
    if ! command -v python &> /dev/null; then
        echo "Error: Neither python3 nor python is available"
        exit 1
    fi
    PYTHON_CMD="python"
else
    PYTHON_CMD="python3"
fi

echo ""
log_info "=========================================="
log_info "Macula Platform Portal Server"
log_info "=========================================="
echo ""

log_step "Starting HTTP server on port ${PORT}..."
log_info "Portal URL: http://localhost:${PORT}"
echo ""
log_info "Press Ctrl+C to stop the server"
echo ""

cd "$SCRIPT_DIR"

# Start simple HTTP server
$PYTHON_CMD -m http.server "$PORT"
