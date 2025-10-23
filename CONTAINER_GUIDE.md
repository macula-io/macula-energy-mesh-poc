# Macula Platform - Container-First Architecture Guide

## Overview

Macula is a **container-first distributed application platform** for the BEAM ecosystem. Each application runs in its own container and communicates via WAMP through the Bondy router.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Macula Platform                              │
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐   │
│  │   Bondy      │◄────┤  Dashboard   │◄────┤  PostgreSQL  │   │
│  │ WAMP Router  │     │     Hub      │     │   Database   │   │
│  │              │     │ (Phoenix UI) │     │              │   │
│  └──────┬───────┘     └──────────────┘     └──────────────┘   │
│         │                                                       │
│         │ WAMP (WebSocket)                                     │
│         │                                                       │
│    ┌────┴────────┬───────────────┬──────────────┐             │
│    │             │               │              │             │
│ ┌──▼────────┐ ┌──▼────────┐  ┌──▼────────┐  ┌──▼────────┐   │
│ │  Homes #1 │ │  Homes #2 │  │ Utilities │  │  Future   │   │
│ │ Payload   │ │ Payload   │  │  Payload  │  │  Payload  │   │
│ │ (25 bots) │ │ (25 bots) │  │ (5 bots)  │  │           │   │
│ └───────────┘ └───────────┘  └───────────┘  └───────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Each payload includes MaculaOs for secure realm connectivity
```

## Key Concepts

### **MaculaOs - The Security Gatekeeper**

All payloads **must** include `MaculaOs` as a dependency. MaculaOs provides:
- ✅ **Authenticated WAMP connectivity** - Signed messages with payload identity
- ✅ **Permission validation** - Enforces what topics each payload can access
- ✅ **Credential management** - Handles realm authentication
- ✅ **Rate limiting** - Prevents abuse
- ✅ **Audit logging** - Tracks all WAMP interactions

**Without MaculaOs, payloads cannot connect to Macula realms.**

### **Payloads - Containerized Applications**

Each payload is:
- A standalone OTP application
- Packaged as a Docker container
- Includes MaculaOs for realm access
- Communicates only via WAMP (no direct connections)
- Can be written in any language (future)
- Scalable independently

### **Bondy - WAMP Router**

The central message router that:
- Validates payload identities
- Enforces RBAC policies
- Routes pub/sub and RPC messages
- Provides realm management

## Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- 8GB RAM minimum
- Ports 4000, 5432, 18080, 18081 available

### 1. Clone and Navigate

```bash
git clone <repo-url>
cd macula-energy-mesh-poc
```

### 2. Build All Containers

```bash
# Build all services
docker-compose build

# Or build individually
docker-compose build dashboard
docker-compose build homes_1
docker-compose build utilities
```

**First build takes 10-15 minutes** (downloads dependencies, compiles code)

### 3. Start the Platform

```bash
# Start all services
docker-compose up

# Or start in detached mode
docker-compose up -d

# View logs
docker-compose logs -f
```

### 4. Access the Dashboard

Open browser to: **http://localhost:4000**

You should see:
- Real-time home production/consumption
- Provider market competition
- Contract switching events
- Energy trading metrics

### 5. Monitor Services

```bash
# Check service health
docker-compose ps

# View logs for specific service
docker-compose logs -f homes_1
docker-compose logs -f dashboard

# Check Bondy WAMP router
curl http://localhost:18081/api/status
```

### 6. Scale Payloads

```bash
# Run more home containers
docker-compose up --scale homes_1=3

# Adjust homes per container
NUM_HOMES_PER_CONTAINER=50 docker-compose up
```

### 7. Stop the Platform

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (fresh start)
docker-compose down -v
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# Simulation Configuration
SIMULATION_SPEED=105120          # Time acceleration (105,120x = 1 year in 5 min)
SIMULATION_START_DATE=2025-01-01T00:00:00Z

# Payload Scaling
NUM_HOMES_PER_CONTAINER=25       # Homes per container instance
NUM_PROVIDERS=5                   # Number of energy providers

# Security (CHANGE IN PRODUCTION!)
SECRET_KEY_BASE=your_secret_key_here_minimum_64_characters_long_required
POSTGRES_PASSWORD=your_postgres_password

# Database
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/cortex_iq_dashboard_dev
```

### Custom Bondy Configuration

Edit `dev-env/bondy_config/bondy.conf` for:
- Realm security settings
- RBAC policies
- Payload permissions
- Rate limiting

## Development Workflow

### Local Development (Without Containers)

```bash
# Terminal 1: Start PostgreSQL and Bondy
docker-compose up postgres bondy

# Terminal 2: Start dashboard
cd system/cortex_iq_dashboard_umbrella
mix deps.get
mix ecto.setup
iex -S mix phx.server

# Terminal 3: Start homes payload
cd system/cortex_iq_homes
mix deps.get
iex -S mix

# Terminal 4: Start utilities payload
cd system/cortex_iq_utilities
mix deps.get
iex -S mix
```

### Rebuild After Code Changes

```bash
# Rebuild specific service
docker-compose build dashboard

# Rebuild and restart
docker-compose up -d --build dashboard

# Force complete rebuild
docker-compose build --no-cache
```

### Debug Container

```bash
# Enter running container
docker exec -it macula_homes_1 /bin/sh

# Check Elixir release console
docker exec -it macula_homes_1 /app/bin/cortex_iq_homes remote

# View environment
docker exec -it macula_homes_1 env
```

## Adding a New Payload

### 1. Create Elixir Application

```bash
cd system
mix new my_new_payload --sup
cd my_new_payload
```

### 2. Add MaculaOs Dependency

Edit `mix.exs`:

```elixir
defp deps do
  [
    {:macula_os, path: "../macula_os"},
    {:cortex_iq_core, path: "../cortex_iq_core"}
  ]
end

defp releases do
  [
    my_new_payload: [
      include_executables_for: [:unix],
      applications: [runtime_tools: :permanent],
      steps: [:assemble, :tar]
    ]
  ]
end
```

### 3. Connect to Realm in Application

```elixir
defmodule MyNewPayload.Application do
  use Application

  def start(_type, _args) do
    # Connect to realm via MaculaOs
    {:ok, conn} = MaculaOs.connect(
      realm: System.get_env("MACULA_REALM", "be.cortexiq.energy"),
      hub_url: System.get_env("MACULA_REALM_URL", "ws://bondy:18080/ws"),
      identity: %{
        payload_name: "my_new_payload",
        payload_version: "0.1.0",
        instance_id: System.get_env("INSTANCE_ID", "instance_1")
      }
    )

    children = [
      {MyNewPayload.RealmConnection, conn},
      # Your GenServers here
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 4. Create Dockerfile

```dockerfile
FROM hexpm/elixir:1.17.3-erlang-26.2.5.6-alpine-3.20.3 AS builder

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
COPY ../cortex_iq_core ../cortex_iq_core
COPY ../macula_os ../macula_os

RUN mix deps.get --only prod
COPY lib ./lib
RUN mix compile && mix release my_new_payload

FROM alpine:3.20.3 AS runtime
RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/my_new_payload ./

ENV MACULA_REALM_URL=ws://bondy:18080/ws
ENV MACULA_REALM=be.cortexiq.energy

CMD ["/app/bin/my_new_payload", "start"]
```

### 5. Add to Docker Compose

Edit `docker-compose.yml`:

```yaml
  my_new_payload:
    build:
      context: ./system
      dockerfile: my_new_payload/Dockerfile
    container_name: macula_my_new_payload
    environment:
      MACULA_REALM_URL: ws://bondy:18080/ws
      MACULA_REALM: be.cortexiq.energy
      INSTANCE_ID: my_new_payload_1
    depends_on:
      bondy:
        condition: service_healthy
    networks:
      - macula_network
```

### 6. Deploy

```bash
docker-compose build my_new_payload
docker-compose up -d my_new_payload
docker-compose logs -f my_new_payload
```

## Security

### Payload Authentication

Each payload authenticates with Bondy using:
1. **Payload Identity** - Declared in MaculaOs.connect()
2. **Signed Messages** - MaculaOs signs all WAMP messages
3. **RBAC Enforcement** - Bondy validates permissions

### Permission Model

Defined in `dev-env/bondy_config/security.config`:

```erlang
{payload, "cortex_iq_homes", [
    {permissions, [
        {publish, ["energy.hub.home.*"]},
        {subscribe, ["energy.hub.simulation.time", "energy.hub.provider.*"]}
    ]}
]}
```

### Secrets Management

**Development:**
- Use `.env` file (gitignored)
- Docker Compose reads from `.env`

**Production:**
- Use Docker secrets or environment injection
- Kubernetes secrets
- Vault integration

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker-compose logs <service_name>

# Check dependencies
docker-compose ps

# Rebuild
docker-compose build --no-cache <service_name>
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker-compose ps postgres

# Check database exists
docker exec -it macula_postgres psql -U postgres -l

# Run migrations manually
docker exec -it macula_dashboard /app/bin/cortex_iq_dashboard eval "CortexIqDashboard.Release.migrate"
```

### WAMP Connection Failures

```bash
# Check Bondy is healthy
curl http://localhost:18081/api/status

# Check realm exists
curl http://localhost:18081/api/realms/be.cortexiq.energy

# View Bondy logs
docker-compose logs bondy
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Reduce simulation speed
SIMULATION_SPEED=10512 docker-compose up

# Scale down payloads
NUM_HOMES_PER_CONTAINER=10 docker-compose up
```

## Production Deployment

### Kubernetes

See `k8s/` directory for manifests:
- Deployments for each payload
- Services for networking
- ConfigMaps for configuration
- Secrets for credentials

### Docker Swarm

```bash
docker stack deploy -c docker-compose.yml macula
```

### Monitoring

Add monitoring services to `docker-compose.yml`:
- Prometheus for metrics
- Grafana for visualization
- Jaeger for distributed tracing

## Next Steps

- 📖 Read [CLAUDE.md](./CLAUDE.md) for architecture details
- 🔍 Explore [TESTING.md](./TESTING.md) for testing guide
- 🚀 Deploy to production environment
- 🔌 Add your own payloads to the platform

---

**Macula Platform** - A container-first distributed application platform for BEAM
