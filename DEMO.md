# Macula Platform Demo Guide

This guide will help you set up and run the Macula Platform demonstration using the CortexIQ energy trading simulation.

## What You'll See

**Macula Platform** - A distributed application platform for BEAM
- Configuration-driven realm management
- Event-driven communication via WAMP
- Scalable payload deployment

**CortexIQ Application** - Real-time energy trading simulation
- 50 homes with solar panels and batteries
- 5 energy providers competing for customers
- Dynamic contract optimization
- Real-time visualization dashboard

## Prerequisites

- **Docker & Docker Compose** (for Bondy and PostgreSQL)
- **Elixir 1.18+** with **Erlang/OTP 27+**
- **Node.js & npm** (for Phoenix assets)
- **Git** (to clone the repository)

## Quick Start (5 minutes)

### 1. Start Infrastructure

```bash
# Start Bondy (WAMP router) and PostgreSQL
cd dev-env
docker compose up -d
cd ..
```

**Verify infrastructure is running:**
```bash
curl http://localhost:18081/realms
# Should return JSON with realms
```

### 2. Install Dependencies

```bash
cd system

# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies for Phoenix assets
cd apps/cortex_iq_dashboard_web/assets
npm install
cd ../../../
```

### 3. Setup Database

```bash
mix ecto.create
mix ecto.migrate
```

### 4. Start the Platform

```bash
# Quick start with defaults (50 homes, 5 providers)
mix phx.server

# OR use the startup script
../start-local-dev.sh
```

### 5. Open Dashboard

Open your browser to: **http://localhost:4000**

You should see:
- Real-time energy production/consumption graphs
- Contract switching events
- Provider market share
- Network topology visualization

## Advanced Configuration

### Customize Simulation

```bash
# More homes for scale demo
CORTEXIQ_HOME_COUNT=200 ./start-local-dev.sh

# Fewer providers
CORTEXIQ_PROVIDER_COUNT=3 ./start-local-dev.sh

# Slower simulation (easier to follow)
SIMULATION_SPEED=10512 ./start-local-dev.sh  # 1 year in 50 minutes instead of 5
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CORTEXIQ_HOME_COUNT` | 50 | Number of home simulation bots |
| `CORTEXIQ_PROVIDER_COUNT` | 5 | Number of energy provider bots |
| `SIMULATION_SPEED` | 105120 | Time acceleration (1 year = 5 real minutes) |
| `BONDY_URL` | ws://localhost:18080/ws | WAMP router WebSocket URL |
| `BONDY_REALM` | be.cortexiq.energy | WAMP realm name |
| `PORT` | 4000 | Phoenix dashboard port |

## What's Happening Under the Hood

### Macula Platform Layer

1. **macula_os** provides:
   - WAMP client/server infrastructure (`MaculaOs.Wamp`)
   - Connection to Bondy realm: `be.cortexiq.energy`
   - Event routing for all payloads

### CortexIQ Application Payloads

2. **cortex_iq_dashboard** + **cortex_iq_dashboard_web**:
   - Subscribes to ALL events from homes and providers
   - Aggregates real-time data
   - Broadcasts simulation time (105,120x accelerated)
   - Displays Phoenix LiveView dashboard

3. **cortex_iq_homes** (50 bots):
   - Each home simulates:
     - Solar production (0W at night, 3-5kW at noon)
     - Consumption (500W base + peaks)
     - 10kWh battery storage
   - Subscribes to provider contract offers
   - Optimizes contracts to minimize cost
   - Publishes events every ~3 simulation hours (100ms real-time)

4. **cortex_iq_utilities** (5 bots):
   - Each provider has a pricing strategy:
     - "Steady Eddie" - consistent mid-range
     - "Night Owl" - cheap at night
     - "Solar Surfer" - cheap during solar peak
     - "Peak Predator" - dynamic based on demand
     - "Discount King" - big switching discounts
   - Publishes contract offers every ~15 simulation hours
   - Competes for market share

### Event Flow

```
Dashboard → Publishes simulation time
    ↓
Providers → Calculate prices → Publish contract offers
    ↓
Homes → Receive offers → Evaluate optimization → Switch if better
    ↓
Homes → Publish production/consumption/contract events
    ↓
Dashboard → Subscribes to events → Updates visualization
```

## Exploring the Demo

### Dashboard Views

1. **Overview Tab**:
   - Total homes active
   - Energy traded (MWh)
   - Contract switches counter
   - Total savings
   - Real-time activity feed

2. **Network Topology**:
   - Visual representation of the Macula Ring
   - Animated message flows between payloads
   - Shows WAMP pub/sub patterns

3. **Charts**:
   - Energy production vs consumption over time
   - Provider market share (pie chart)
   - Price comparison across providers
   - Cumulative savings

### Bondy Console

Explore the WAMP router directly:

**http://localhost:3000** (Bondy Web Console)

- View active realms: `be.cortexiq.energy`
- Monitor sessions (one per payload)
- See subscriptions and publications
- Watch real-time message flow

### WAMP Topics

All CortexIQ events use this pattern:
- Homes: `be.cortexiq.energy.home.{home_id}.{event_type}`
- Providers: `be.cortexiq.energy.utility.{provider_id}.{event_type}`
- Simulation: `be.cortexiq.energy.simulation.time`

## Troubleshooting

### Infrastructure Not Starting

```bash
# Check if ports are available
lsof -i :18080  # Bondy WAMP
lsof -i :18081  # Bondy Admin
lsof -i :5432   # PostgreSQL
lsof -i :4000   # Phoenix

# View logs
cd dev-env
docker compose logs -f bondy
docker compose logs -f postgres
```

### Database Issues

```bash
# Reset database
mix ecto.drop
mix ecto.create
mix ecto.migrate
```

### Compilation Errors

```bash
# Clean and recompile
mix deps.clean --all
mix deps.get
mix compile
```

### No Events Showing in Dashboard

1. Check Bondy is running: `curl http://localhost:18081/realms`
2. Check logs in `iex` console for connection errors
3. Verify realm name matches: `be.cortexiq.energy`
4. Check browser console for WebSocket errors

## Stopping the Demo

```bash
# Stop Phoenix (Ctrl+C twice in iex console)

# Stop infrastructure
cd dev-env
docker compose down

# Stop and remove all data
docker compose down -v
```

## Demo Script (for Presentations)

### Part 1: Platform Introduction (2 minutes)

"Today I'm showing you **Macula** - a distributed application platform for the BEAM ecosystem.

Think of it like Kubernetes, but designed specifically for Erlang/Elixir applications, using WAMP for event-driven communication instead of HTTP.

The key features are:
- Configuration-driven realm management
- Event-driven pub/sub communication
- Dynamic payload deployment
- Built on Bondy WAMP router"

### Part 2: CortexIQ Demo (3 minutes)

"To demonstrate the platform, we've built **CortexIQ** - a real-time energy trading simulation.

[Open dashboard at http://localhost:4000]

What you're seeing:
- 50 homes, each with solar panels and batteries
- 5 energy providers competing for customers
- Simulation running at 105,000x speed - one year happens in 5 minutes

[Point to activity feed]

Watch the contract switches - homes are autonomously optimizing their energy contracts based on:
- Their production patterns
- Battery storage
- Provider pricing strategies
- Time of day rates

[Point to charts]

This chart shows provider market share changing in real-time as homes switch.
This shows the total savings as homes optimize.

**All of this is happening through pure event-driven architecture** - homes don't know about providers, providers don't know about homes. They only know WAMP topics."

### Part 3: Architecture Highlight (2 minutes)

"The beauty of Macula is that all these components - homes, providers, dashboard - they're all just **payloads** running on the platform.

[Open Bondy console at http://localhost:3000]

In the Bondy console, you can see the realm `be.cortexiq.energy` and all the active sessions.

Adding a new participant is trivial - just deploy another payload that publishes/subscribes to the right topics. No changes to the platform needed.

This demonstrates horizontal scalability - we could run 10,000 homes across multiple nodes, all communicating through the same WAMP mesh."

### Part 4: Platform Value (1 minute)

"The value proposition:
1. **Event-driven by default** - loose coupling, easy to extend
2. **BEAM-native** - OTP supervision, hot code reloading, clustering
3. **Configuration-driven** - no code changes to scale or add realms
4. **Proven tech** - Bondy is production-ready, WAMP is a standard protocol

CortexIQ is just one application. You could build IoT platforms, financial trading systems, multiplayer games - anything that needs real-time, distributed coordination."

## Next Steps

### For Developers

1. Read `CLAUDE.md` for architecture details
2. Explore the code in `system/apps/`
3. Try modifying a payload (e.g., add a new provider strategy)
4. Experiment with dynamic payload loading (future roadmap)

### For Platform Evaluation

1. Test scalability (increase `CORTEXIQ_HOME_COUNT`)
2. Monitor resource usage
3. Explore multi-node deployment (see `Dockerfile.hub`, `Dockerfile.edge`)
4. Review WAMP protocol usage (Bondy console)

### For Investors

1. Review business case: platform vs. point solution
2. Evaluate market fit: BEAM ecosystem, IoT, real-time systems
3. Consider extension paths: multi-realm, dynamic deployment, A/B testing

## Support

- Report issues: https://github.com/macula-io/macula-energy-mesh-poc/issues
- Bondy documentation: https://developer.bondy.io
- WAMP protocol: https://wamp-proto.org
