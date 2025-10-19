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
- **WAMP Client**: awre library (fallback to custom if needed)
- **Infrastructure**: Bondy 3-node cluster via Docker Compose

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
energy.region_{N}.provider.{provider_id}.tariff
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

## Proposed Umbrella Structure

```
macula-energy-mesh-poc/
├── apps/
│   ├── mesh_core/              # Core domain logic (models, events)
│   ├── mesh_bots/              # Bot implementations (Home, Provider)
│   ├── mesh_wamp/              # WAMP client, Bondy integration
│   └── mesh_web/               # Phoenix LiveView dashboard
├── config/                     # Shared configuration
├── dev-env/
│   ├── docker-compose.yml      # 3-node Bondy cluster
│   └── bondy/                  # Node configurations
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEMO_SCRIPT.md
│   └── screenshots/
├── mix.exs                     # Umbrella root
└── start_demo.sh               # One-command startup
```

## App Responsibilities

### mesh_core
- Domain models: Realm, Home, Provider, Market
- Event schemas
- Business logic utilities
- No processes, pure data structures

### mesh_bots
- `MeshBots.Application` - Supervision tree
- `MeshBots.BotSupervisor` - Manages all bot instances
- `MeshBots.HomeBot` - GenServer per home (50 instances)
- `MeshBots.ProviderBot` - GenServer per provider (5 instances)
- `MeshBots.Simulation.Clock` - 100x time acceleration
- `MeshBots.Simulation.Solar` - Solar production logic
- `MeshBots.Simulation.Consumption` - Consumption patterns
- `MeshBots.Simulation.Battery` - Battery simulation

### mesh_wamp
- `MeshWamp.Client` - WAMP client wrapper
- `MeshWamp.Connection` - WebSocket connection management
- `MeshWamp.Publisher` - Publish helper
- `MeshWamp.Subscriber` - Subscribe helper
- `MeshWamp.RealmManager` - Realm setup via Bondy API

### mesh_web
- `MeshWeb.OverviewLive` - Main dashboard
- `MeshWeb.RealmsLive` - Realms view
- `MeshWeb.HomesLive` - Homes list/detail
- `MeshWeb.ProvidersLive` - Providers view
- `MeshWeb.HomeDetailLive` - Individual home detail
- Components: topology_map, metrics_card, activity_feed, charts

## Communication Architecture

**Dashboard ↔ Bots** (Hybrid approach):
1. **Direct queries** (via Registry): LiveView mounts → get initial state
2. **PubSub updates** (via Phoenix.PubSub): Bots broadcast state changes

**Bots → Bondy**:
- Bots publish events to WAMP topics
- Bots subscribe to provider tariffs via WAMP

**Data Flow**:
```
Simulation Clock (1/sec = 100 sim sec)
    ↓
Home/Provider Bots calculate state
    ↓
    ├─→ WAMP publish to Bondy (mesh events)
    └─→ PubSub broadcast (dashboard updates)
         ↓
    Dashboard LiveView (re-render)
```

## Open Questions to Resolve

1. **WAMP Library**: Try `awre` first or build minimal custom client?
   - **Recommendation**: Try awre, fall back to custom if issues

2. **Database**: Needed for history/persistence?
   - **Recommendation**: No DB for PoC (keeps it simple, all in-memory)

3. **Bot Configuration**: How to configure 50 homes and 5 providers?
   - **Recommendation**: Generated on startup with configurable counts

4. **WAMP Subscriptions**: Should home bots subscribe to provider tariffs?
   - **Recommendation**: Yes, makes demo more realistic (homes react to price changes)

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

**Project State**: Architecture and strategy defined, ready to begin implementation

**Next Steps**:
1. Create umbrella app structure (`mix new macula_energy_mesh_poc --umbrella`)
2. Create four child apps (mesh_core, mesh_bots, mesh_wamp, mesh_web)
3. Set up Bondy docker-compose configuration
4. Begin Phase 1 implementation

**Decisions Pending**: None - all major decisions made, ready to build

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
