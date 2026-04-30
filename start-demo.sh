#!/bin/bash
set -euo pipefail

####################################################################################################
# CortexIQ Energy Trading Dashboard - Quick Start
#
# This script builds and starts the complete CortexIQ platform via Docker Compose
####################################################################################################

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}✓${NC} $1"
}

log_step() {
  echo -e "${CYAN}▸${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

log_section() {
  echo ""
  echo -e "${CYAN}========================================${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}========================================${NC}"
}

# Check prerequisites
check_prereqs() {
  log_section "Checking Prerequisites"

  if ! command -v docker &> /dev/null; then
    log_error "docker is not installed"
    exit 1
  fi
  log_info "docker installed"

  if ! command -v docker compose &> /dev/null; then
    log_error "docker compose is not installed"
    exit 1
  fi
  log_info "docker compose installed"
}

# Parse arguments
BUILD=true
DETACH=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-build)
      BUILD=false
      shift
      ;;
    -d|--detach)
      DETACH=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --no-build    Skip building images (use existing images)"
      echo "  -d, --detach  Run in detached mode (background)"
      echo "  --help        Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                    # Build and run in foreground"
      echo "  $0 --no-build -d      # Use existing images and run in background"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

# Main script
main() {
  log_section "CortexIQ Energy Trading Dashboard"

  check_prereqs

  # Clean up old containers (optional)
  log_step "Stopping any existing containers..."
  docker compose down 2>/dev/null || true

  if [ "$BUILD" = true ]; then
    log_section "Building Container Images"
    log_step "This may take 10-20 minutes on first run..."
    log_step "Building all images..."

    docker compose build

    log_info "All images built successfully!"
  else
    log_step "Skipping build (using existing images)"
  fi

  log_section "Starting Services"

  if [ "$DETACH" = true ]; then
    log_step "Starting in detached mode..."
    docker compose up -d

    log_section "Waiting for Services to be Ready"
    log_step "Waiting for Bondy WAMP router..."
    sleep 5

    log_step "Waiting for PostgreSQL..."
    sleep 3

    log_step "Waiting for Dashboard..."
    sleep 10

    log_info "All services started!"

    log_section "Service Status"
    docker compose ps

  else
    log_step "Starting in foreground mode (CTRL+C to stop)..."
    log_step "Services will start in dependency order..."
    docker compose up
  fi

  if [ "$DETACH" = true ]; then
    log_section "Access Information"
    echo ""
    echo -e "${GREEN}Dashboard URL:${NC} http://localhost:4000"
    echo -e "${GREEN}Excalidraw:${NC} http://localhost:3000"
    echo -e "${GREEN}Bondy Admin API:${NC} http://localhost:18081"
    echo -e "${GREEN}Bondy WebSocket:${NC} ws://localhost:18080/ws"
    echo -e "${GREEN}PostgreSQL:${NC} localhost:5432 (postgres/postgres)"
    echo ""
    log_section "Useful Commands"
    echo ""
    echo "View logs:"
    echo "  docker compose logs -f                   # All services"
    echo "  docker compose logs -f dashboard         # Dashboard only"
    echo "  docker compose logs -f homes_1 homes_2   # Home bots"
    echo "  docker compose logs -f utilities         # Provider bots"
    echo "  docker compose logs -f projections       # Event projections"
    echo ""
    echo "Check service status:"
    echo "  docker compose ps"
    echo ""
    echo "Stop services:"
    echo "  docker compose down"
    echo ""
    echo "Restart a service:"
    echo "  docker compose restart dashboard"
    echo ""
    log_info "CortexIQ Platform is running! 🚀"
    echo ""
  fi
}

main
