# CortexIQ Energy Dashboard - Quick Start

Get the CortexIQ Energy Trading Dashboard running in minutes with Docker Compose.

## What You'll Get

- **Real-time energy trading simulation** with 50 homes and 5 providers
- **Phoenix LiveView dashboard** showing live metrics and market dynamics
- **Event-driven architecture** with WAMP pub/sub messaging
- **CQRS pattern** with projections and queries

## Prerequisites

- Docker (20.10+)
- Docker Compose (2.0+)
- 8GB RAM recommended
- 20GB free disk space

## Quick Start

### Option 1: Build and Run (First Time)

```bash
./start-demo.sh -d
```

This will:
1. Build all 8 container images (~10-20 minutes first time)
2. Start all services in background
3. Show access URLs

### Option 2: Run Without Rebuilding

```bash
./start-demo.sh --no-build -d
```

Use this after the first run for faster startup.

### Option 3: Run in Foreground (See Logs)

```bash
./start-demo.sh
```

Press CTRL+C to stop.

## Access the Dashboard

Once started, open your browser to:

- **Dashboard:** http://localhost:4000
- **Excalidraw:** http://localhost:3000

The **dashboard** shows:
- Live energy production/consumption metrics
- Real-time contract switching events
- Provider market share charts
- Home energy balance tracking

**Excalidraw** is available for creating architecture diagrams during demos.

## Services Running

| Service | Port | Description |
|---------|------|-------------|
| **Dashboard** | 4000 | Phoenix LiveView web UI |
| **Excalidraw** | 3000 | Collaborative whiteboarding |
| **Bondy** | 18080 | WAMP router (WebSocket) |
| **Bondy API** | 18081 | Admin API |
| **PostgreSQL** | 5432 | Database (postgres/postgres) |
| simulation | - | Simulation clock service |
| projections | - | Event→DB projections |
| queries | - | WAMP RPC query API |
| homes_1, homes_2 | - | 50 home simulation bots |
| utilities | - | 5 provider bots |

## Useful Commands

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f dashboard
docker compose logs -f excalidraw
docker compose logs -f homes_1
docker compose logs -f projections
```

### Check Status

```bash
docker compose ps
```

### Restart a Service

```bash
docker compose restart dashboard
```

### Stop Everything

```bash
docker compose down
```

### Clean Up (Remove Volumes)

```bash
docker compose down -v
```

## Troubleshooting

### Dashboard Not Loading

1. Check if all services are running:
   ```bash
   docker compose ps
   ```

2. Check dashboard logs:
   ```bash
   docker compose logs dashboard
   ```

3. Ensure PostgreSQL is healthy:
   ```bash
   docker compose logs postgres
   ```

### Database Migration Errors

Restart the dashboard to retry migrations:
```bash
docker compose restart dashboard
```

### Port Already in Use

If port 4000 is busy, stop the conflicting service or change the port in `docker-compose.yml`:
```yaml
dashboard:
  ports:
    - "4001:4000"  # Change left side to any free port
```

### Out of Memory

Reduce the number of home bots by setting environment variable:
```bash
NUM_HOMES_PER_CONTAINER=10 ./start-demo.sh -d
```

## What's Happening Under the Hood

1. **Bondy** starts as WAMP router
2. **PostgreSQL** initializes database
3. **Dashboard** runs migrations and connects to Bondy
4. **Simulation** service broadcasts time ticks every second
5. **Homes** (50 bots) simulate solar production, consumption, battery usage
6. **Utilities** (5 providers) publish contract offers with dynamic pricing
7. **Projections** subscribe to events and write to database
8. **Queries** expose WAMP RPC API for dashboard queries
9. **Dashboard** subscribes to events and displays real-time data

## Configuration

Edit `docker-compose.yml` to customize:

```yaml
environment:
  # Simulation speed (1 year = 5 minutes)
  SIMULATION_SPEED: 105120

  # Number of homes per container
  NUM_HOMES_PER_CONTAINER: 25

  # Number of providers
  NUM_PROVIDERS: 5
```

## Next Steps

- Check `CLAUDE.md` for architecture details
- See `infrastructure/kind/` for Kubernetes deployment
- Read `docs/ARCHITECTURE.md` for system design

## Support

For issues:
1. Check logs with `docker compose logs <service>`
2. Verify all services are healthy with `docker compose ps`
3. Review `CLAUDE.md` for detailed architecture guidance

---

**Demo Ready in ~15 minutes** | **50 Homes** | **5 Providers** | **Real-time Trading**
