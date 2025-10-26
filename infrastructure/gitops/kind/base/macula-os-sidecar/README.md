# MaculaOs Sidecar Base

This directory contains the reusable MaculaOs sidecar container definition.

## Usage

To add the MaculaOs sidecar to a deployment:

1. **Reference this base in your deployment's kustomization.yaml**
2. **Override the secret name** for the specific API key
3. **Update application container** to connect to `localhost:8080`

## Example

```yaml
# In your deployment's kustomization.yaml
bases:
  - ../../base/macula-os-sidecar

patchesJson6902:
  - target:
      kind: Deployment
      name: your-app
    patch: |-
      - op: add
        path: /spec/template/spec/containers/-
        value:
          $ref: ../../base/macula-os-sidecar/sidecar-container.yaml
      - op: replace
        path: /spec/template/spec/containers/1/env/3/valueFrom/secretKeyRef/name
        value: your-app-macula-apikey
```

## Configuration

The sidecar reads configuration from environment variables:

- `MACULA_PORT` - Port to listen on (default: 8080)
- `BONDY_URL` - Upstream Bondy WebSocket URL
- `BONDY_REALM` - WAMP realm to join
- `MACULA_API_KEY` - API key for authentication (from secret)

## Endpoints

- `GET /health` - Health check (returns upstream connection status)
- `GET /metrics` - Prometheus metrics
- `GET /ws` - WebSocket upgrade for WAMP connections

## Resource Limits

- Requests: 128Mi RAM, 100m CPU
- Limits: 256Mi RAM, 200m CPU

Adjust based on your workload's needs.
