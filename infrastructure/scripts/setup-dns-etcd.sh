#!/bin/bash
#
# setup-dns-etcd.sh
# Install and configure etcd for dynamic DNS backend
#
# Purpose: etcd serves as the key-value store backend for CoreDNS,
# allowing ExternalDNS instances across all clusters to write DNS records
# that CoreDNS reads and serves to clients.
#

set -euo pipefail

# Configuration
ETCD_VERSION="${ETCD_VERSION:-v3.5.11}"
ETCD_DIR="${ETCD_DIR:-$HOME/.local/share/macula-dns/etcd}"
ETCD_DATA_DIR="${ETCD_DATA_DIR:-$ETCD_DIR/data}"
ETCD_BIN_DIR="${ETCD_BIN_DIR:-$HOME/.local/bin}"
ETCD_PORT="${ETCD_PORT:-2379}"
ETCD_PEER_PORT="${ETCD_PEER_PORT:-2380}"

echo "=================================================="
echo "Macula DNS Setup: etcd Installation"
echo "=================================================="
echo "Version: $ETCD_VERSION"
echo "Install directory: $ETCD_BIN_DIR"
echo "Data directory: $ETCD_DATA_DIR"
echo "Client port: $ETCD_PORT"
echo ""

# Create directories
mkdir -p "$ETCD_BIN_DIR"
mkdir -p "$ETCD_DATA_DIR"

# Check if etcd is already installed
if [ -f "$ETCD_BIN_DIR/etcd" ]; then
    current_version=$("$ETCD_BIN_DIR/etcd" --version | head -1 | awk '{print $3}')
    echo "✓ etcd already installed: $current_version"
    if [ "$current_version" = "$ETCD_VERSION" ]; then
        echo "✓ Version matches, skipping download"
        SKIP_DOWNLOAD=true
    else
        echo "⚠ Version mismatch, will download $ETCD_VERSION"
        SKIP_DOWNLOAD=false
    fi
else
    echo "Installing etcd $ETCD_VERSION..."
    SKIP_DOWNLOAD=false
fi

# Download and install etcd
if [ "${SKIP_DOWNLOAD:-false}" != "true" ]; then
    ETCD_ARCHIVE="etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
    ETCD_URL="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/${ETCD_ARCHIVE}"

    echo "📥 Downloading etcd from $ETCD_URL"
    curl -L "$ETCD_URL" -o "/tmp/$ETCD_ARCHIVE"

    echo "📦 Extracting etcd..."
    tar xzf "/tmp/$ETCD_ARCHIVE" -C "/tmp"

    echo "📁 Installing binaries to $ETCD_BIN_DIR..."
    cp "/tmp/etcd-${ETCD_VERSION}-linux-amd64/etcd" "$ETCD_BIN_DIR/"
    cp "/tmp/etcd-${ETCD_VERSION}-linux-amd64/etcdctl" "$ETCD_BIN_DIR/"
    chmod +x "$ETCD_BIN_DIR/etcd" "$ETCD_BIN_DIR/etcdctl"

    echo "🧹 Cleaning up..."
    rm -rf "/tmp/$ETCD_ARCHIVE" "/tmp/etcd-${ETCD_VERSION}-linux-amd64"

    echo "✅ etcd installed successfully"
fi

# Create systemd service file (if running with systemd)
SYSTEMD_DIR="$HOME/.config/systemd/user"
if command -v systemctl &> /dev/null; then
    echo ""
    echo "Creating systemd user service..."
    mkdir -p "$SYSTEMD_DIR"

    cat > "$SYSTEMD_DIR/macula-dns-etcd.service" << EOF
[Unit]
Description=etcd key-value store for Macula DNS
Documentation=https://etcd.io/docs/
After=network.target

[Service]
Type=notify
ExecStart=$ETCD_BIN_DIR/etcd \\
  --name=macula-dns-etcd \\
  --data-dir=$ETCD_DATA_DIR \\
  --listen-client-urls=http://0.0.0.0:$ETCD_PORT \\
  --advertise-client-urls=http://localhost:$ETCD_PORT \\
  --listen-peer-urls=http://localhost:$ETCD_PEER_PORT \\
  --initial-advertise-peer-urls=http://localhost:$ETCD_PEER_PORT \\
  --initial-cluster=macula-dns-etcd=http://localhost:$ETCD_PEER_PORT \\
  --initial-cluster-token=macula-dns-cluster \\
  --initial-cluster-state=new \\
  --log-level=info
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    echo "✅ Systemd service created: $SYSTEMD_DIR/macula-dns-etcd.service"
    echo ""
    echo "To enable and start the service:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable macula-dns-etcd"
    echo "  systemctl --user start macula-dns-etcd"
    echo "  systemctl --user status macula-dns-etcd"
fi

# Verify installation
echo ""
echo "=================================================="
echo "Installation Complete!"
echo "=================================================="
echo ""
echo "Installed binaries:"
ls -lh "$ETCD_BIN_DIR/etcd" "$ETCD_BIN_DIR/etcdctl"
echo ""
echo "Data directory: $ETCD_DATA_DIR"
echo ""
echo "Next steps:"
echo "1. Start etcd:"
if command -v systemctl &> /dev/null; then
    echo "   systemctl --user start macula-dns-etcd"
else
    echo "   $ETCD_BIN_DIR/etcd --data-dir=$ETCD_DATA_DIR --listen-client-urls=http://0.0.0.0:$ETCD_PORT --advertise-client-urls=http://localhost:$ETCD_PORT &"
fi
echo "2. Verify etcd is running:"
echo "   $ETCD_BIN_DIR/etcdctl --endpoints=http://localhost:$ETCD_PORT endpoint health"
echo "3. Run ./setup-dns-coredns.sh to install CoreDNS"
echo ""
