#!/bin/bash
set -euo pipefail

# Provision Macula Hub VM
# Installs Bondy, MaculaOs, and dashboard payloads

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$INFRA_DIR")"

HUB_IP="192.168.100.10"
SSH_KEY="$HOME/.ssh/macula_rsa"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

ssh_exec() {
  ssh $SSH_OPTS ubuntu@$HUB_IP "$@"
}

scp_file() {
  scp $SSH_OPTS "$1" ubuntu@$HUB_IP:"$2"
}

main() {
  log_info "=== Provisioning Hub VM ($HUB_IP) ==="

  # Check connectivity
  if ! ssh_exec "echo OK" &>/dev/null; then
    log_error "Cannot connect to Hub VM at $HUB_IP"
    exit 1
  fi

  # Copy project code to hub (using tar over ssh, doesn't require rsync)
  log_info "Syncing project code to /opt/macula..."
  ssh_exec "sudo mkdir -p /opt/macula && sudo chown ubuntu:ubuntu /opt/macula"
  cd "$PROJECT_ROOT"
  tar czf - --exclude='_build' --exclude='deps' --exclude='.git' --exclude='infrastructure' . | \
    ssh $SSH_OPTS ubuntu@$HUB_IP "cd /opt/macula && tar xzf -"
  cd - >/dev/null

  # Install Bondy
  log_info "Installing Bondy WAMP router..."
  ssh_exec bash <<'EOF'
set -euo pipefail

# Download Bondy release (adjust version as needed)
BONDY_VERSION="1.0.0-rc.7"
BONDY_URL="https://github.com/bondy-io/bondy/releases/download/${BONDY_VERSION}/bondy-${BONDY_VERSION}-ubuntu-20.04-x86_64.tar.gz"

if [[ ! -d /opt/macula/bondy ]]; then
  cd /opt/macula
  wget -q "$BONDY_URL" -O bondy.tar.gz
  tar -xzf bondy.tar.gz
  mv bondy-* bondy
  rm bondy.tar.gz
fi

# Configure Bondy realm
cat > /opt/macula/bondy/etc/bondy.conf <<BONDY_CONFIG
nodename = bondy@127.0.0.1
distributed_cookie = macula_secret
log.console.level = info
log.file.level = info

# WAMP WebSocket
wamp.websocket.enabled = on
wamp.websocket.port = 18080
wamp.websocket.path = /ws

# HTTP API
api.http.enabled = on
api.http.port = 18081
BONDY_CONFIG

# Create realm configuration
cat > /opt/macula/bondy/create_realm.sh <<'REALM_SCRIPT'
#!/bin/bash
/opt/macula/bondy/bin/bondy eval '
  case bondy_realm:get(<<"be.cortexiq.energy">>) of
    {error, not_found} ->
      Realm = #{
        uri => <<"be.cortexiq.energy">>,
        description => <<"CortexIQ Energy Trading Realm">>,
        authmethods => [anonymous],
        security_enabled => false
      },
      bondy_realm:create(Realm);
    _ ->
      ok
  end.
'
REALM_SCRIPT
chmod +x /opt/macula/bondy/create_realm.sh

# Start Bondy
sudo systemctl daemon-reload
sudo systemctl enable bondy
sudo systemctl start bondy || true

# Wait for Bondy to start
sleep 5

# Create realm
/opt/macula/bondy/create_realm.sh || echo "Realm may already exist"

echo "Bondy installed and configured"
EOF

  # Compile MaculaOs and payloads
  log_info "Compiling MaculaOs and CortexIQ payloads..."
  ssh_exec bash <<'EOF'
set -euo pipefail

cd /opt/macula/system

# Get dependencies
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix deps.compile

# Compile all apps
MIX_ENV=prod mix compile

# Run database migrations for dashboard
cd apps/cortex_iq_dashboard
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate
cd ../..

echo "MaculaOs compiled successfully"
EOF

  # Configure and start MaculaOs services
  log_info "Configuring MaculaOs services..."
  ssh_exec bash <<'EOF'
set -euo pipefail

# Update systemd service for macula-os
sudo tee /etc/systemd/system/macula-os.service >/dev/null <<SERVICE
[Unit]
Description=MaculaOs Runtime (Hub Mode)
After=network.target bondy.service postgresql.service
Requires=bondy.service postgresql.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/macula/system
Environment="MACULA_MODE=realm_hub"
Environment="REALM_URI=be.cortexiq.energy"
Environment="BONDY_WS_URL=ws://localhost:18080/ws"
Environment="DATABASE_URL=ecto://cortexiq:cortexiq123@localhost/cortexiq_dashboard"
Environment="PHX_HOST=192.168.100.10"
Environment="PHX_PORT=4000"
Environment="SECRET_KEY_BASE=$(mix phx.gen.secret)"
ExecStart=/opt/macula/system/_build/prod/rel/cortex_iq_dashboard_web/bin/cortex_iq_dashboard_web start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable macula-os
sudo systemctl start macula-os || true

echo "MaculaOs services configured"
EOF

  log_info ""
  log_info "=== Hub VM Provisioned Successfully ==="
  log_info "Access dashboard at: http://$HUB_IP:4000"
  log_info "Bondy WebSocket: ws://$HUB_IP:18080/ws"
  log_info ""
  log_info "Check status:"
  log_info "  ssh $SSH_OPTS ubuntu@$HUB_IP 'sudo systemctl status bondy'"
  log_info "  ssh $SSH_OPTS ubuntu@$HUB_IP 'sudo systemctl status macula-os'"
}

main "$@"
