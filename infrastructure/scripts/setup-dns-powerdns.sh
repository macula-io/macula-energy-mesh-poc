#!/bin/bash
#
# setup-dns-powerdns.sh
# Setup PowerDNS with PostgreSQL in Docker for Macula dynamic DNS
#
# This script:
# 1. Creates data directories for persistent storage
# 2. Generates secure secrets for database and API
# 3. Creates .env file for docker-compose
# 4. Starts PowerDNS services via docker-compose
# 5. Creates systemd service for auto-start on boot
# 6. Verifies DNS server is working
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$INFRA_DIR")"
COMPOSE_FILE="$INFRA_DIR/docker-compose.dns.yml"
ENV_FILE="$INFRA_DIR/.env.dns"
DATA_DIR="${DATA_DIR:-$INFRA_DIR/data/powerdns}"

echo "=========================================="
echo "Macula DNS Setup: PowerDNS + PostgreSQL"
echo "=========================================="
echo "Infrastructure dir: $INFRA_DIR"
echo "Data directory: $DATA_DIR"
echo "Compose file: $COMPOSE_FILE"
echo ""

# Check docker and docker-compose
if ! command -v docker &> /dev/null; then
    echo "❌ Error: docker is not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null &&  ! docker compose version &> /dev/null; then
    echo "❌ Error: docker-compose is not installed"
    exit 1
fi

# Use 'docker compose' or 'docker-compose' depending on what's available
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo "✓ Docker found: $(docker --version)"
echo "✓ Docker Compose found: $($DOCKER_COMPOSE version --short 2>/dev/null || echo 'installed')"
echo ""

# Create data directory
echo "📁 Creating data directories..."
mkdir -p "$DATA_DIR/postgres"
chmod 755 "$DATA_DIR"
chmod 700 "$DATA_DIR/postgres"
echo "✓ Data directory created: $DATA_DIR"
echo ""

# Generate secrets if .env file doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    echo "🔐 Generating secure secrets..."

    # Generate random secrets
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    POWERDNS_API_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    PDNS_ADMIN_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)

    cat > "$ENV_FILE" << EOF
# Macula DNS - PowerDNS Environment Configuration
# Generated on $(date)
# DO NOT COMMIT THIS FILE TO GIT

# Data directory (persistent storage for PostgreSQL)
DATA_DIR=$DATA_DIR

# PostgreSQL credentials
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# PowerDNS API key (used by ExternalDNS)
POWERDNS_API_KEY=$POWERDNS_API_KEY

# PowerDNS-Admin secret key (for web UI session security)
PDNS_ADMIN_SECRET_KEY=$PDNS_ADMIN_SECRET

# Network configuration
# If your clusters cannot reach localhost/127.0.0.1, set this to your host IP
# HOST_IP=192.168.1.100
EOF

    chmod 600 "$ENV_FILE"
    echo "✓ Generated .env file: $ENV_FILE"
    echo "⚠️  IMPORTANT: Keep this file secure! It contains secrets."
    echo ""
else
    echo "✓ Using existing .env file: $ENV_FILE"
    echo ""
fi

# Source .env file
set -a
source "$ENV_FILE"
set +a

# Generate PowerDNS configuration file with secrets
echo "📝 Generating PowerDNS configuration..."
PDNS_CONF="$INFRA_DIR/config/powerdns/pdns.conf"
cat > "$PDNS_CONF" << EOF
# PowerDNS Authoritative Server Configuration
# Generated on $(date)
# For Macula Dynamic DNS with PostgreSQL backend

# PostgreSQL Backend
launch=gpgsql
gpgsql-host=postgres
gpgsql-port=5432
gpgsql-dbname=powerdns
gpgsql-user=powerdns
gpgsql-password=$POSTGRES_PASSWORD
gpgsql-dnssec=yes

# Bind to all interfaces
local-address=0.0.0.0,::
local-port=53

# API and Webserver
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=0.0.0.0/0,::/0
api=yes
api-key=$POWERDNS_API_KEY

# Logging
loglevel=5
log-dns-queries=yes
log-dns-details=yes

# Performance
receiver-threads=2
distributor-threads=3

# Security
setuid=pdns
setgid=pdns
EOF

chmod 600 "$PDNS_CONF"
echo "✓ Generated PowerDNS config: $PDNS_CONF"
echo ""

# Start PowerDNS services
echo "🚀 Starting PowerDNS services..."
cd "$INFRA_DIR"
$DOCKER_COMPOSE -f docker-compose.dns.yml up -d

echo "⏳ Waiting for services to be healthy..."
sleep 5

# Check service status
echo ""
echo "📊 Service status:"
$DOCKER_COMPOSE -f docker-compose.dns.yml ps

# Verify PowerDNS API is accessible
echo ""
echo "🔍 Verifying PowerDNS API..."
API_URL="http://localhost:8081/api/v1/servers/localhost"
if curl -s -H "X-API-Key: $POWERDNS_API_KEY" "$API_URL" > /dev/null; then
    echo "✓ PowerDNS API is accessible"
else
    echo "⚠️  PowerDNS API may not be ready yet (this is normal on first start)"
    echo "   Give it 10-15 seconds and check: curl -H 'X-API-Key: $POWERDNS_API_KEY' $API_URL"
fi

# Create systemd service for auto-start on boot
SYSTEMD_DIR="$HOME/.config/systemd/user"
if command -v systemctl &> /dev/null; then
    echo ""
    echo "🔧 Creating systemd service for auto-start..."
    mkdir -p "$SYSTEMD_DIR"

    cat > "$SYSTEMD_DIR/macula-dns.service" << EOF
[Unit]
Description=Macula DNS - PowerDNS with PostgreSQL
Documentation=https://doc.powerdns.com/
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INFRA_DIR
EnvironmentFile=$ENV_FILE

# Start services
ExecStart=$DOCKER_COMPOSE -f $COMPOSE_FILE up -d

# Stop services
ExecStop=$DOCKER_COMPOSE -f $COMPOSE_FILE down

# Restart policy
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

    echo "✓ Systemd service created: $SYSTEMD_DIR/macula-dns.service"
    echo ""
    echo "To enable auto-start on boot:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable macula-dns"
    echo "  systemctl --user start macula-dns"
    echo ""
fi

# Print summary
echo "=========================================="
echo "✅ PowerDNS Setup Complete!"
echo "=========================================="
echo ""
echo "Services running:"
echo "  - PostgreSQL: localhost:5432 (internal)"
echo "  - PowerDNS DNS: localhost:53 (UDP/TCP)"
echo "  - PowerDNS API: http://localhost:8081"
echo "  - PowerDNS-Admin UI: http://localhost:9191"
echo ""
echo "Configuration:"
echo "  - Data directory: $DATA_DIR"
echo "  - Environment file: $ENV_FILE"
echo "  - API Key: $POWERDNS_API_KEY"
echo ""
echo "Next steps:"
echo "1. Configure system DNS to use localhost:53"
echo "2. Update ExternalDNS configuration with API key"
echo "3. Test DNS resolution: dig @localhost macula.local"
echo "4. Access web UI: http://localhost:9191 (default: admin/admin)"
echo ""
echo "Management commands:"
echo "  Start:   $DOCKER_COMPOSE -f $COMPOSE_FILE up -d"
echo "  Stop:    $DOCKER_COMPOSE -f $COMPOSE_FILE down"
echo "  Logs:    $DOCKER_COMPOSE -f $COMPOSE_FILE logs -f"
echo "  Restart: $DOCKER_COMPOSE -f $COMPOSE_FILE restart"
echo ""
