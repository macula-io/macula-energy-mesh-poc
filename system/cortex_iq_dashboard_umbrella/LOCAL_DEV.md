# CortexIQ Dashboard - Local Development

This guide explains how to run the CortexIQ Dashboard locally while connecting to the cluster's WAMP router and services.

## Architecture

When running locally, the dashboard connects to:
- **Bondy WAMP Router**: Running in the KinD cluster (`macula-hub`)
- **PostgreSQL**: Running in the KinD cluster (via port-forward)
- **Real-time events**: From homes/providers running in the cluster

```
┌─────────────────────────────┐
│ Your Local Machine          │
│                             │
│  ┌──────────────────────┐   │
│  │ Phoenix Dashboard    │   │
│  │ localhost:4000       │   │
│  └──────┬───────────────┘   │
│         │                   │
└─────────┼───────────────────┘
          │
          ▼ via localhost:30080 (NodePort)
┌─────────────────────────────┐
│ KinD Cluster (macula-hub)   │
│                             │
│  ┌──────────────────────┐   │
│  │ Bondy WAMP Router    │   │
│  │ (macula-system)      │   │
│  └──────────────────────┘   │
│                             │
│  ┌──────────────────────┐   │
│  │ CortexIQ Services    │   │
│  │ - cortex_iq_homes    │   │
│  │ - cortex_iq_utilities│   │
│  │ - cortex_iq_queries  │   │
│  └──────────────────────┘   │
└─────────────────────────────┘
```

## Quick Start

### Option 1: Using the Convenience Script (Recommended)

```bash
cd system/cortex_iq_dashboard_umbrella
./dev-local.sh
```

This script automatically:
- ✅ Checks KinD cluster status
- ✅ Verifies Bondy accessibility
- ✅ Sets up PostgreSQL port-forwarding
- ✅ Loads environment variables
- ✅ Starts Phoenix server

### Option 2: Manual Setup

**1. Verify KinD cluster is running:**

```bash
kubectl --context kind-macula-hub cluster-info
```

**2. Check Bondy is accessible:**

```bash
# Bondy should be exposed via NodePort 30080
nc -z localhost 30080 && echo "Bondy is accessible" || echo "Bondy not accessible"
```

**3. Set up PostgreSQL port-forwarding (in a separate terminal):**

```bash
kubectl --context kind-macula-hub port-forward -n macula-hub svc/postgres 5432:5432
```

**4. Load environment variables:**

```bash
source .env.dev
```

**5. Start the Phoenix server:**

```bash
mix phx.server
```

**6. Access the dashboard:**

Open your browser to:
- **Overview**: http://localhost:4000/
- **Homes**: http://localhost:4000/homes
- **Providers**: http://localhost:4000/providers

## Environment Configuration

The `.env.dev` file contains all necessary environment variables:

```bash
# WAMP Configuration
BONDY_URL="ws://localhost:30080/ws"
BONDY_REALM="be.cortexiq.energy"
BONDY_ADMIN_URL="http://localhost:30082"

# Database Configuration
DATABASE_URL="ecto://cortexiq:cortexiq123@localhost:5432/cortexiq_dashboard"

# Phoenix Configuration
PHX_HOST="localhost"
PHX_PORT="4000"
SECRET_KEY_BASE="dev_secret_key_base_that_needs_to_be_at_least_64_characters_long_for_phoenix"
```

## Port Mappings

The KinD cluster exposes services via NodePort:

| Service | Cluster Port | NodePort | Local Access |
|---------|-------------|----------|--------------|
| Bondy WAMP | 18080 | 30080 | ws://localhost:30080/ws |
| Bondy Admin | 18081 | 30082 | http://localhost:30082 |
| PostgreSQL | 5432 | (port-forward) | localhost:5432 |
| Dashboard | 4000 | - | localhost:4000 |

## Troubleshooting

### "Bondy not accessible"

**Check if Bondy is running:**
```bash
kubectl --context kind-macula-hub get pods -n macula-system -l app=bondy
```

**Check NodePort mapping:**
```bash
kubectl --context kind-macula-hub get svc -n macula-system bondy
```

**Verify port forwarding:**
```bash
docker ps --filter "name=macula-hub-control-plane" --format "{{.Ports}}"
# Should show: 0.0.0.0:30080-30081->30080-30081/tcp
```

### "PostgreSQL connection failed"

**Check if port-forward is running:**
```bash
lsof -i :5432
```

**Restart port-forward:**
```bash
kubectl --context kind-macula-hub port-forward -n macula-hub svc/postgres 5432:5432
```

### "No events received"

**Check if homes/providers are running:**
```bash
kubectl --context kind-macula-hub get pods -n macula-apps
```

**Check WAMP subscriptions in logs:**
```bash
mix phx.server
# Look for: "Subscribed to WAMP topic: be.cortexiq.home. (prefix)"
```

### "Database migration errors"

**Run migrations:**
```bash
cd apps/cortex_iq_dashboard_schemas
mix ecto.migrate
```

## Development Workflow

1. **Start cluster services** (if not already running)
2. **Run `./dev-local.sh`** to start local dashboard
3. **Make code changes** - Phoenix live reload will update automatically
4. **Test in browser** - Navigate to http://localhost:4000
5. **Check logs** - Watch terminal for WAMP events and errors

## Architecture Notes

### Zero Database Dependencies

The dashboard LiveViews use **WAMP RPC** to query data (no direct database access):

- `QueryClient.get_overview()` → `cortex_iq_queries` service
- `QueryClient.get_homes(opts)` → `cortex_iq_queries` service
- `QueryClient.get_providers()` → `cortex_iq_queries` service

All database queries are handled by the `cortex_iq_queries` service running in the cluster.

### Real-time Events

The dashboard receives real-time events via WAMP subscriptions:
- Home measurements (production, consumption, battery)
- Provider offers and pricing
- Contract switches and confirmations
- Simulation time updates

## Stopping

Press `Ctrl+C` to stop the Phoenix server.

If you started PostgreSQL port-forwarding manually, find and kill the process:

```bash
lsof -i :5432
kill <PID>
```

## Additional Commands

**View cluster logs:**
```bash
kubectl --context kind-macula-hub logs -n macula-hub -l app=cortex-iq-dashboard --tail=100
```

**Check database contents:**
```bash
kubectl --context kind-macula-hub exec -n macula-hub -it deployment/postgres -- psql -U cortexiq -d cortexiq_dashboard
```

**Restart cluster dashboard:**
```bash
kubectl --context kind-macula-hub rollout restart -n macula-hub deployment/cortex-iq-dashboard
```
