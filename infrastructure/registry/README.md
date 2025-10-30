# Macula Container Registry

Simple, lightweight Docker Registry v2 with web UI for local development.

## Quick Start

### 1. Start the Registry

```bash
cd /home/rl/work/github.com/macula-io/macula-energy-mesh-poc
./infrastructure/registry/start.sh
```

### 2. Configure DNS and Docker

**Option A: Using Scripts (Recommended)**

```bash
# Add to /etc/hosts
sudo /tmp/add-registry-to-hosts.sh

# Configure Docker daemon
sudo /tmp/configure-docker-registry.sh

# Restart Docker
sudo systemctl restart docker
```

**Option B: Manual Configuration**

```bash
# Add to /etc/hosts
echo "127.0.0.1 registry.macula.local" | sudo tee -a /etc/hosts

# Configure Docker for insecure registry
sudo tee /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["registry.macula.local:5000"]
}
EOF

# Restart Docker
sudo systemctl restart docker
```

## Access

- **Web UI**: http://registry.macula.local:5000
- **Docker API**: registry.macula.local:5000

## Usage

### Push an Image

```bash
# Tag your image
docker tag macula/cortex-iq-dashboard:latest registry.macula.local:5000/macula/cortex-iq-dashboard:latest

# Push to registry
docker push registry.macula.local:5000/macula/cortex-iq-dashboard:latest
```

### Pull an Image

```bash
docker pull registry.macula.local:5000/macula/cortex-iq-dashboard:latest
```

### List Images

```bash
curl http://registry.macula.local:5000/v2/_catalog
```

## KinD Integration

To use this registry with KinD clusters, the registry must be accessible from within the cluster nodes.

### Option 1: Connect Registry to KinD Network

```bash
# Connect registry nginx container to kind network
docker network connect kind macula-registry-nginx

# Now KinD can access registry at: http://macula-registry-nginx:80
```

### Option 2: Use Host IP

KinD nodes can access the host via special DNS name `host.docker.internal` or the host's IP.

```bash
# Get host IP
HOST_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# Use in KinD: registry at $HOST_IP:5000
```

### Option 3: Configure KinD to Use Registry

Add to your KinD cluster config:

```yaml
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.macula.local:5000"]
    endpoint = ["http://registry.macula.local:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.macula.local:5000".tls]
    insecure_skip_verify = true
```

Or configure existing clusters:

```bash
for cluster in macula-hub macula-edge-01 macula-edge-02 macula-edge-03 macula-edge-04; do
  docker exec ${cluster}-control-plane sh -c "
    mkdir -p /etc/containerd/certs.d/registry.macula.local:5000
    cat > /etc/containerd/certs.d/registry.macula.local:5000/hosts.toml <<EOF
server = 'http://registry.macula.local:5000'

[host.'http://registry.macula.local:5000']
  capabilities = ['pull', 'resolve', 'push']
  skip_verify = true
EOF
  "

  # Restart containerd
  docker exec ${cluster}-control-plane systemctl restart containerd
done
```

## DNS Configuration

### PowerDNS (Preferred)

The DNS record `registry.macula.local` → `192.168.129.9` is already configured in PowerDNS.

To make PowerDNS work as system DNS:
1. Ensure PowerDNS exposes port 53
2. Configure `/etc/resolv.conf` to use PowerDNS

### /etc/hosts (Temporary)

For quick testing, add to `/etc/hosts`:
```
127.0.0.1 registry.macula.local
```

## Architecture

```
┌─────────────────────────────────────┐
│ Nginx (Port 5000)                   │
│  ├─ / → Registry UI                 │
│  └─ /v2/ → Docker Registry API      │
└─────────────────────────────────────┘
           │              │
     ┌─────┴──────┐  ┌───┴─────────────┐
     │ Registry UI │  │ Docker Registry │
     │  (joxit)    │  │  (registry:2)   │
     └─────────────┘  └─────────────────┘
```

## Management

### View Logs

```bash
cd infrastructure/registry
docker-compose logs -f
```

### Stop Registry

```bash
./infrastructure/registry/stop.sh
```

### Remove All Data

```bash
cd infrastructure/registry
docker-compose down -v
```

### Garbage Collection

Delete unused layers:

```bash
docker exec macula-registry bin/registry garbage-collect /etc/docker/registry/config.yml
```

## Troubleshooting

### Cannot push/pull images

1. Check Docker daemon.json includes insecure registry
2. Restart Docker after config changes
3. Verify registry is accessible: `curl http://registry.macula.local:5000/v2/_catalog`

### DNS not resolving

1. Check /etc/hosts has entry
2. Or verify PowerDNS is running and port 53 is accessible
3. Test: `ping registry.macula.local`

### KinD cannot access registry

1. Connect registry to kind network: `docker network connect kind macula-registry-nginx`
2. Or use host IP instead of DNS name
3. Verify containerd configuration in KinD nodes

## Security Notes

⚠️ **This setup is for local development only!**

- Uses HTTP (not HTTPS)
- No authentication
- Insecure registry configuration
- No image scanning

For production, use proper solutions like Harbor, GitLab Registry, or cloud registries (ECR, GCR, ACR).
