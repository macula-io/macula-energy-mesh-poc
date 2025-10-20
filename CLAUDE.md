# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Macula Energy Mesh PoC** - A demonstration of Bondy's eventing mesh capabilities through a real-time energy trading simulation.

### Purpose
Create a compelling proof-of-concept that showcases how Bondy's WAMP-based eventing mesh can support a real-time energy exchange where homes with solar panels, wind turbines, and batteries dynamically switch energy provider contracts to optimize cost and energy usage.

### Target Audience
**Marketers and Investors** - This is NOT a technical demo. The focus is on:
- Visual impact (sexy UI)
- Easy to understand
- Shows scale and real-time capabilities
- One-command startup
- Impressive metrics and visualizations

## Strategic Decisions Made

### 1. Technology Stack
- **Language**: Elixir (chosen for BEAM ecosystem integration, excellent concurrency)
- **Web Framework**: Phoenix with LiveView (real-time UI without complex JavaScript)
- **Charting**: ApexCharts (prettier charts for investors)
- **Styling**: Tailwind CSS + custom dark theme
- **Visualization**: D3.js for network topology
- **WAMP Client**: Custom client via mesh_wamp
- **Infrastructure**: Bondy embedded in hub nodes, Docker Compose for deployment
- **Deployment**: Hub-and-spoke architecture with containerized edges

### 2. Architecture Choice
**Elixir Umbrella Application (Option A)** - Monorepo with multiple apps for:
- Single command startup (critical for demo)
- Shared code between components
- Standard Elixir pattern
- Easy LiveView integration

### 3. Simulation Configuration
- **Realms**: 5 (energy.region_1 through energy.region_5)
- **Homes**: 50 total (10 per region)
- **Providers**: 5 (competing across all regions)
- **Time Acceleration**: 100x speed (1 real hour = 36 seconds, full day in ~15 minutes)
- **Realism Level**: Moderate
  - Solar production follows sine wave (peak at noon)
  - Consumption has morning/evening peaks
  - Battery storage and sell-back enabled
  - Predictive contract switching

### 4. Dashboard Design
**Multiple Tabs Approach**:
- Overview (main metrics, topology, activity)
- Realms (region-specific views)
- Homes (list + detail on click)
- Providers (competition view)

**Key Visualizations**:
- Network topology with animated message flows
- Live metrics (big numbers: homes active, energy traded, switches, savings)
- Activity feed (scrolling contract switches)
- Charts (energy production/consumption, provider market share, price comparison, savings over time)

**Visual Style**:
- Dark theme with neon/electric colors
- Smooth animations
- Minimal text, maximum visual impact

### 5. Bot Behavior

#### Home Bots (GenServer per home)
**Production (Solar/Wind)**:
- Sine wave: 0W at night, peak 3-5kW at noon
- +/- 20% randomness
- Updates every 5 seconds (simulation time)

**Consumption**:
- Base load: 500W always
- Morning peak (7-9am): +1500W
- Evening peak (6-10pm): +2000W
- Random appliances: +/- 300W

**Battery**:
- 10kWh capacity
- Charges when production > consumption
- Discharges when consumption > production
- Can sell excess to grid

**Optimization**:
- Calculate cost for next 15 minutes with each provider
- Consider battery charge/discharge strategy
- Switch if savings > $0.10/hour
- 30-second cooldown between switches

#### Provider Bots (GenServer per provider)
**Pricing Strategies** (for variety):
- Provider A: "Steady Eddie" - consistent mid-range
- Provider B: "Night Owl" - cheap at night, expensive during day
- Provider C: "Solar Surfer" - follows solar production patterns
- Provider D: "Peak Predator" - high during peak hours
- Provider E: "Random Racer" - frequent small price changes

**Updates**:
- Every 30 seconds (simulation time)
- Buy-back rate = sell rate * 0.7

### 6. Event Topics Structure
```
energy.region_{N}.home.{home_id}.production
energy.region_{N}.home.{home_id}.consumption
energy.region_{N}.home.{home_id}.storage
energy.region_{N}.home.{home_id}.contract
energy.region_{N}.utility.{provider_id}.tariff
energy.market.switch
```

### 7. Simple Event Payloads
```json
// Production
{"home_id": "home_001", "watts": 3500, "source": "solar", "timestamp": "..."}

// Consumption
{"home_id": "home_001", "watts": 1200, "timestamp": "..."}

// Storage
{"home_id": "home_001", "battery_percent": 75, "capacity_kwh": 10, "timestamp": "..."}

// Tariff
{"provider_id": "provider_a", "price_per_kwh": 0.15, "timestamp": "..."}

// Contract Switch
{"home_id": "home_001", "from_provider": "provider_a", "to_provider": "provider_b", "reason": "cost_optimization", "savings": 0.23}
```

## Actual Umbrella Structure

```
macula-energy-mesh-poc/
├── system/                        # Umbrella application root
│   ├── apps/
│   │   ├── mesh_core/             # Core domain models (structs, events)
│   │   ├── mesh_wamp/             # WAMP client library
│   │   ├── mesh_hub/              # Hub infrastructure (Bondy, realm management)
│   │   ├── mesh_hub_web/          # Phoenix LiveView dashboard
│   │   ├── mesh_edge/             # Generic edge runtime (bot OS)
│   │   ├── mesh_edge_homes/       # Home bot implementation
│   │   └── mesh_edge_utilities/   # Utility provider bot implementation
│   ├── config/                    # Shared configuration
│   └── mix.exs                    # Umbrella root
├── dev-env/
│   └── docker-compose.yml         # Hub + Edge containers
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEMO_SCRIPT.md
│   └── screenshots/
└── start_demo.sh                  # One-command startup
```

**Edge Runtime Architecture**:
- **mesh_edge**: Generic edge runtime ("Edge OS")
  - Bot lifecycle management (start, stop, reload)
  - WAMP connection management via mesh_wamp
  - Dynamic bot loading (future: remote deployment)
  - Health monitoring and telemetry
  - **Roadmap**: Load bot modules dynamically and remotely

- **mesh_edge_homes**, **mesh_edge_utilities**: Domain-specific bot implementations
  - Current: Statically compiled with specific bots
  - Future: Deployed as modules into mesh_edge runtime
  - Think: Docker containers (mesh_edge) vs Images (mesh_edge_homes)

**Future Extensibility**:
- `mesh_edge_commercial/` - Commercial analytics bots
- `mesh_edge_aggregators/` - Data aggregation services
- `mesh_edge_analytics/` - Real-time analytics engines
- All deployable to `mesh_edge` runtime dynamically

## App Responsibilities

### mesh_core
- Domain models: Home, Provider, Realm, Market (pure structs)
- Event schemas: ProductionEvent, ConsumptionEvent, TariffEvent, ContractSwitchEvent
- Business logic utilities (pure functions)
- **No processes, pure data structures**
- Shared by all applications

### mesh_wamp
- `MeshWamp.Client` - WAMP client wrapper
- `MeshWamp.Connection` - WebSocket connection management
- `MeshWamp.Publisher` - Publish helper (events to topics)
- `MeshWamp.Subscriber` - Subscribe helper (topics to callbacks)
- WAMP protocol implementation (HELLO, WELCOME, PUBLISH, SUBSCRIBE, etc.)
- Used by all edge applications to connect to hub

### mesh_hub
- `MeshHub.Application` - Supervision tree
- **Embeds Bondy** - Starts Bondy WAMP router in supervision tree
- **Hosts WAMP realm** - `energy.hub` (or `energy.region_N`)
- Realm management and configuration
- **Pure infrastructure - no domain bots**
- Optional: Simulation clock (shared time reference)
- Optional: Aggregation helpers for analytics
- Depends on: mesh_core

### mesh_hub_web
- `MeshHubWeb.Endpoint` - Phoenix endpoint (HTTP/WebSocket for dashboard)
- `MeshHubWeb.OverviewLive` - Main dashboard
- `MeshHubWeb.RealmsLive` - Realms view
- `MeshHubWeb.HomesLive` - Homes list/detail
- `MeshHubWeb.ProvidersLive` - Providers view
- Components: topology_map, metrics_card, activity_feed, charts
- **Subscribes to events via WAMP** (not local queries)
- Aggregates and visualizes mesh-wide activity
- Depends on: mesh_hub

### mesh_edge
- `MeshEdge.Application` - Generic edge runtime supervision tree
- `MeshEdge.BotSupervisor` - Dynamic supervisor for bot instances
- `MeshEdge.Runtime` - Bot lifecycle management (start, stop, reload)
- `MeshEdge.Connection` - WAMP connection management (via mesh_wamp)
- `MeshEdge.Health` - Health checks and telemetry
- `MeshEdge.Loader` - Dynamic module loading (future: remote deployment)
- **Provides**: Generic bot runtime environment
- **Roadmap**: Remote bot deployment, hot-code reloading, A/B testing bots
- Depends on: mesh_wamp, mesh_core

### mesh_edge_homes
- `MeshEdgeHomes.Application` - Supervision tree
- `MeshEdgeHomes.HomeBot` - GenServer per home (N homes, configurable via ENV)
- `MeshEdgeHomes.Simulation.Solar` - Solar production calculations
- `MeshEdgeHomes.Simulation.Consumption` - Consumption patterns (base + peaks)
- `MeshEdgeHomes.Simulation.Battery` - Battery charge/discharge logic
- `MeshEdgeHomes.Optimization` - Contract switching decisions
- **Publishes**: production, consumption, storage, contract events
- **Subscribes**: provider tariff updates
- **Current**: Standalone application
- **Future**: Deployable module for mesh_edge runtime
- Depends on: mesh_wamp, mesh_core (future: mesh_edge)

### mesh_edge_utilities
- `MeshEdgeUtilities.Application` - Supervision tree
- `MeshEdgeUtilities.ProviderBot` - GenServer per provider (N providers, configurable via ENV)
- `MeshEdgeUtilities.Simulation.Pricing` - Pricing strategies per provider
  - "Steady Eddie", "Night Owl", "Solar Surfer", "Peak Predator", "Random Racer"
- **Publishes**: tariff updates (price per kWh, buy-back rates)
- **Subscribes**: (optional) market events for dynamic pricing
- **Current**: Standalone application
- **Future**: Deployable module for mesh_edge runtime
- Depends on: mesh_wamp, mesh_core (future: mesh_edge)

## Communication Architecture

**Hub-and-Spoke Topology**:
```
┌──────────────────────────────────────────────────────┐
│  Hub Container (mesh_hub + mesh_hub_web)             │
│  ┌────────────────────────────────────────────────┐  │
│  │  mesh_hub                                      │  │
│  │  ┌──────────────────────────────────────────┐ │  │
│  │  │  Bondy (WAMP Router)                     │ │  │
│  │  │  Realm: energy.hub                       │ │  │
│  │  └──────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────┐  │
│  │  mesh_hub_web                                  │  │
│  │  ┌──────────────────────────────────────────┐ │  │
│  │  │  Phoenix Dashboard (subscribes via WAMP) │ │  │
│  │  └──────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
         ▲                    ▲                  ▲
         │ WAMP               │ WAMP             │ WAMP
         │                    │                  │
┌────────┴─────────┐  ┌───────┴──────────┐  ┌───┴──────────────┐
│ mesh_edge_homes  │  │ mesh_edge_homes  │  │ mesh_edge_       │
│   (Container 1)  │  │   (Container 2)  │  │   utilities      │
│                  │  │                  │  │                  │
│ Home Bots (3)    │  │ Home Bots (3)    │  │ Provider Bots(5) │
└──────────────────┘  └──────────────────┘  └──────────────────┘

Future: Add more edge types
┌──────────────────┐
│ mesh_edge_       │
│   commercial     │  ← New participant type!
│                  │
│ Analytics Bots   │
└──────────────────┘
```

**Communication Patterns**:

1. **mesh_edge_homes → Bondy (WAMP Publish)**:
   - Home bots publish production/consumption/storage/contract events
   - Topics: `energy.hub.home.{home_id}.{event_type}`
   - Example: `energy.hub.home.home_001.production`

2. **mesh_edge_utilities → Bondy (WAMP Publish)**:
   - Provider bots publish tariff updates
   - Topics: `energy.hub.utility.{provider_id}.tariff`
   - Example: `energy.hub.utility.provider_a.tariff`

3. **mesh_edge_homes subscribes (via mesh_wamp)**:
   - Home bots subscribe to ALL provider tariffs
   - Pattern: `energy.hub.utility.*.tariff`
   - Triggers contract optimization when prices change

4. **mesh_hub_web subscribes (via mesh_wamp)**:
   - Dashboard subscribes to ALL events for visualization
   - Patterns: `energy.hub.home.*.production`, `energy.hub.utility.*.tariff`, etc.
   - Aggregates real-time data for charts and metrics

5. **Pure Event-Driven**:
   - No direct communication between edges
   - All communication flows through Bondy (in mesh_hub)
   - Easy to add new participants - just subscribe/publish

**Data Flow**:
```
Simulation Clock (in mesh_hub) → broadcasts time tick
    ↓
mesh_edge_utilities: Provider Bots calculate prices
    ↓
Provider publishes tariff → Bondy → mesh_edge_homes subscribes
    ↓
mesh_edge_homes: Home Bot receives tariff → Recalculates optimization
    ↓
Home publishes events → Bondy → mesh_hub_web subscribes
    ↓
Dashboard LiveView aggregates and displays in real-time
```

## Architecture Decisions Made

1. **WAMP Library**: ✅ Custom implementation via mesh_wamp
   - More control over protocol details
   - Tailored to our specific needs

2. **Bot Configuration**: ✅ Environment variables at container startup
   - `NUM_HOMES` per edge container
   - `NUM_PROVIDERS` in hub container
   - Easy scaling via docker-compose

3. **WAMP Subscriptions**: ✅ Yes, homes subscribe to provider tariffs
   - Makes demo more realistic
   - Shows true mesh communication

4. **Bondy Deployment**: ✅ Embedded in mesh_hub (not mesh_hub_web)
   - Standard umbrella pattern: infrastructure in core app
   - mesh_hub = pure infrastructure (Bondy + realm management)
   - mesh_hub_web = presentation layer (subscribes via WAMP like any edge)
   - Keeps option open for headless hubs

5. **Edge Application Pattern**: ✅ Runtime + Bot separation
   - mesh_edge - Generic edge runtime ("Edge OS")
   - mesh_edge_homes, mesh_edge_utilities - Bot implementations
   - Current: Standalone apps (for simplicity in PoC)
   - Future: Dynamic bot loading into mesh_edge runtime
   - Vision: Deploy new bots remotely without redeploying containers

6. **Extensible Ecosystem**: ✅ Demonstrates event-driven growth
   - New participant types just subscribe/publish
   - No changes to existing participants
   - mesh_edge runtime enables dynamic ecosystem evolution

## Development Phases

### Phase 1: Core Infrastructure (Day 1-2)
- [ ] Create umbrella app structure
- [ ] Bondy docker-compose setup (3-node cluster)
- [ ] Realm configuration script (create 5 realms)
- [ ] Basic WAMP client connection (mesh_wamp app)
- [ ] Home bot skeleton (mesh_bots)
- [ ] Provider bot skeleton (mesh_bots)
- [ ] Phoenix app with basic LiveView (mesh_web)

### Phase 2: Simulation Logic (Day 2-3)
- [ ] Simulation clock (100x acceleration)
- [ ] Home production/consumption simulation
- [ ] Battery simulation
- [ ] Provider pricing strategies
- [ ] Contract switching logic
- [ ] Energy buy/sell logic

### Phase 3: Dashboard (Day 3-4)
- [ ] Network topology visualization (D3.js)
- [ ] Live metrics display (big numbers)
- [ ] Activity feed (scrolling events)
- [ ] Charts (ApexCharts integration)
  - [ ] Energy production/consumption
  - [ ] Provider market share
  - [ ] Price comparison
  - [ ] Savings over time
- [ ] Multiple tabs (Overview, Realms, Homes, Providers)
- [ ] Dark theme styling (Tailwind + custom)

### Phase 4: Polish & Demo Script (Day 4-5)
- [ ] One-command startup script
- [ ] README with screenshots
- [ ] Demo script for presentation
- [ ] Performance tuning
- [ ] Documentation

## Key Demo Talking Points

The dashboard should make these points visually obvious:

1. **Scale** - "50 homes making autonomous decisions in real-time"
2. **Speed** - "Hundreds of messages per second, zero latency"
3. **Efficiency** - "Watch total savings counter increase"
4. **Decentralization** - "No central controller, pure mesh"
5. **Real-time Optimization** - "Homes switch contracts automatically"
6. **Multi-region** - "5 markets operating independently but connected"

## Current Status

**Project State**: Phase 1 - Setting up infrastructure

**Completed**:
- ✅ Umbrella app structure created in `system/`
- ✅ Seven apps created:
  - Infrastructure: mesh_core, mesh_wamp, mesh_hub, mesh_hub_web
  - Edge runtime: mesh_edge (generic bot OS)
  - Bot implementations: mesh_edge_homes, mesh_edge_utilities
- ✅ Architecture decisions finalized (hub-spoke, embedded Bondy, edge runtime pattern)

**Current Task**:
- 🔄 Setting up minimal working mesh
  - Containerize mesh_hub_web with embedded Bondy
  - Containerize mesh_edge
  - Docker Compose with 1 hub + 2 edge containers
  - Single realm (`energy.hub`)
  - Test WAMP connections

**Next Steps**:
1. Configure app dependencies in mix.exs files
2. Implement basic WAMP client in mesh_wamp
3. Embed Bondy in mesh_hub_web
4. Create Dockerfiles for hub and edge
5. Set up docker-compose.yml
6. Test end-to-end connectivity

## Notes

- This is a **proof-of-concept** for marketing/investor demos
- Focus on visual impact over production readiness
- Prioritize "wow factor" - smooth animations, impressive numbers, clear visualizations
- Must be runnable with single command (`./start_demo.sh`)
- Target demo length: 15 minutes (shows full day/night cycle at 100x speed)

## References

- **Bondy Documentation**: https://developer.bondy.io
- **Bondy WAMP API**: See `/home/rl/work/github.com/bondy-io/bondy_docs/`
- **Bondy Codebase**: `/home/rl/work/github.com/bondy-io/bondy/`
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view/
- **WAMP Protocol**: https://wamp-proto.org/
