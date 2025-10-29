#!/bin/bash
# Setup nginx reverse proxy for KinD LoadBalancer IPs

set -e

LB_IP="172.20.255.10"
HOST_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K[^ ]+')

echo "Setting up reverse proxy for KinD LoadBalancer..."
echo "LoadBalancer IP: $LB_IP"
echo "Host IP: $HOST_IP"

# Create nginx configuration
mkdir -p /tmp/kind-proxy
cat > /tmp/kind-proxy/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    # Upstream for macula services
    upstream macula_lb {
        server 172.20.255.10:80;
    }

    # Catch-all server that proxies based on Host header
    server {
        listen 80;
        server_name
_;

        location / {
            proxy_pass http://macula_lb;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

# Stop existing proxy if running
docker rm -f kind-loadbalancer-proxy 2>/dev/null || true

# Start nginx proxy connected to kind network
docker run -d \
  --name kind-loadbalancer-proxy \
  --network kind \
  -p 80:80 \
  -v /tmp/kind-proxy/nginx.conf:/etc/nginx/nginx.conf:ro \
  --restart unless-stopped \
  nginx:alpine

echo "✓ Reverse proxy running"
echo ""
echo "You can now access services at:"
echo "  http://portal.macula.local"
echo "  http://hub.macula.local"
echo "  http://console.macula.local"
echo "  http://analytics.macula.local"
echo "  http://telemetry.macula.local"
echo ""
echo "Make sure these are in your /etc/hosts pointing to $HOST_IP or 127.0.0.1"
