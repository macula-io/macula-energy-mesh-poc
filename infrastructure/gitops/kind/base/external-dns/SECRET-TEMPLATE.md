# PowerDNS API Key Secret

The ExternalDNS deployment requires a Secret containing the PowerDNS API key.

## Creating the Secret in Overlays

Each cluster overlay must create this secret with the PowerDNS API key from `.env.dns`:

### Option 1: Using kubectl (manual)

```bash
# Get the API key from .env.dns
source infrastructure/.env.dns

# Create the secret in the cluster
kubectl create secret generic external-dns-pdns \
  --namespace=external-dns \
  --from-literal=api-key="$POWERDNS_API_KEY"
```

### Option 2: Using Flux Kustomization with SopsSecret (recommended for production)

1. Encrypt the API key using SOPS
2. Create a SopsSecret resource
3. Reference it in the overlay kustomization

### Option 3: Using Kustomize secretGenerator (for development)

Add to the cluster overlay's `kustomization.yaml`:

```yaml
secretGenerator:
  - name: external-dns-pdns
    namespace: external-dns
    literals:
      - api-key=YOUR_API_KEY_HERE
```

**Note:** This secret is NOT included in the base to avoid committing sensitive data to git.
Each cluster overlay is responsible for creating it.
