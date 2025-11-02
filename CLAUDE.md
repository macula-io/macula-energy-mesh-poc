# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Macula Platform PoC** - A distributed application platform for the BEAM, demonstrated through a real-time energy trading simulation (CortexIQ).

### Purpose
Create a compelling proof-of-concept that showcases **Macula** - a distributed application platform built on WAMP and Bondy. The energy trading simulation (**CortexIQ**) demonstrates how applications can be built on this platform to create real-time, event-driven distributed systems.

**Key Value Propositions:**
1. **Macula Platform** - The product being sold
   - Distributed runtime for BEAM applications
   - Event-driven communication via WAMP
   - Configuration-driven realm management
   - Dynamic payload deployment (roadmap)

2. **CortexIQ Application** - Reference implementation showing platform capabilities
   - Real-time energy trading simulation
   - Dynamic contract optimization
   - Event-driven architecture
   - Scalable bot-based simulation

### Target Audience
**Marketers and Investors** - This is a platform play. The focus is on:
- **Primary**: Macula as a distributed application platform
- **Secondary**: CortexIQ as proof of platform capabilities
- Visual impact (sexy UI showing real-time events)
- Easy to understand and demonstrate
- Shows scale and real-time capabilities
- One-command startup
- Impressive metrics and visualizations

## Architecture Principles

### SCREAMING ARCHITECTURE - Critical Implementation Guideline

**The intent of a module MUST be IMMEDIATELY clear from its filename.**

❌ **NEVER use generic/abstract names:**
- `SubscriberSystem` (generic - doesn't tell WHAT it subscribes to)
- `PublisherSystem` (generic - doesn't tell WHAT it publishes)
- `EventHandler` (generic - doesn't tell WHICH event)
- `Manager`, `Service`, `Helper` (vague - no business meaning)

✅ **ALWAYS use specific, descriptive names:**
- `SimulationTimeAdvancedSystem` (SCREAMS: handles simulation time events!)
- `HomeMeasuredPublisherSystem` (SCREAMS: publishes home measurements!)
- `ContractProposedSubscriber` (SCREAMS: subscribes to contract proposals!)

**Rationale:**
- File names should tell the complete story
- No mental mapping or configuration reading required
- Self-documenting codebase
- Easy navigation in large projects
- Business domain visible in file structure

**See:** `system/cortex_iq_homes/ARCHITECTURE_GUIDELINES.md` for complete guidelines and examples.

### IDIOMATIC ELIXIR - Critical Coding Practices

**Write declarative, pattern-matched Elixir code.**

✅ **ALWAYS:**
- Use pattern matching on function heads (primary control flow)
- Write separate function clauses for different cases
- Use guards for simple conditions (`when capacity > 10`)
- Use Enum functions for collections
- Use tail recursion when needed
- Write declarative code (express WHAT, not HOW)

❌ **AVOID:**
- `if` statements (use pattern matching instead)
- `case` statements (use pattern matching instead)
- `cond` statements (use pattern matching instead)
- `try/catch` (use pattern matching on `{:ok, _}` / `{:error, _}`)
- Imperative code (nested logic, manual loops)
- Loops (don't exist in Elixir - use Enum or recursion)

**Example:**
```elixir
# ❌ BAD: Using case
def handle_event(data, state) do
  case data.type do
    :measurement -> handle_measurement(data, state)
    :contract -> handle_contract(data, state)
  end
end

# ✅ GOOD: Pattern matching on function heads
def handle_event(%{type: :measurement} = data, state), do: handle_measurement(data, state)
def handle_event(%{type: :contract} = data, state), do: handle_contract(data, state)
```

**See:** `system/cortex_iq_homes/ARCHITECTURE_GUIDELINES.md` - Idiomatic Elixir section for complete examples.

### TESTING REQUIREMENTS - Critical Quality Practice

**No module is complete without passing tests.**

✅ **ALWAYS:**
- Write tests for every module
- Tests must PASS before committing
- Test public functions and edge cases
- Mirror source structure in test directory
- Test pattern-matched function clauses

❌ **NEVER:**
- Skip writing tests
- Commit code without tests
- Leave failing tests
- Test as an afterthought

**Test Structure:**
```
lib/cortex_iq_homes/subscribe_simulation_time_advanced/
├── system.ex
└── subscriber.ex

test/cortex_iq_homes/subscribe_simulation_time_advanced/
├── system_test.exs
└── subscriber_test.exs
```

**Key Principle:** If it doesn't have tests, it's not done.

**See:** `system/cortex_iq_homes/ARCHITECTURE_GUIDELINES.md` - Testing Requirements section for examples.

## Strategic Decisions Made

### 1. Technology Stack

**Macula Platform:**
- **Language**: Elixir (BEAM ecosystem, excellent concurrency, OTP supervision)
- **WAMP Router**: Bondy (embedded in realm hub nodes)
- **WAMP Client**: Custom implementation (MaculaOs.Wamp)
- **Runtime**: MaculaOs (dual-mode: realm hub or edge)
- **Deployment**: Docker Compose for multi-node deployment

**CortexIQ Application (Demo):**
- **Web Framework**: Phoenix with LiveView (real-time UI without complex JavaScript)
- **Charting**: ApexCharts (prettier charts for investors)
- **Styling**: Tailwind CSS + custom dark theme
- **Visualization**: D3.js for network topology
- **Deployment**: Hub-and-spoke architecture with containerized payloads

### 2. Architecture Choice
**Elixir Umbrella Application (Option A)** - Monorepo with multiple apps for:
- Single command startup (critical for demo)
- Shared code between components
- Standard Elixir pattern
- Easy LiveView integration

### 3. Simulation Configuration
- **Realms**: 1 (energy.hub - simplified from 5 regions)
- **Homes**: 50 total (configurable via ENV)
- **Providers**: 5 (competing for market share)
- **Time Acceleration**: **105,120x speed (configurable via ENV)**
  - 1 simulation year = 5 minutes real-time
  - 1 simulation month = ~25 seconds real-time
  - 1 simulation day = ~0.82 seconds real-time
  - 1 simulation hour = ~34 milliseconds real-time
- **Contract System**: Yearly contracts with discounts
  - Providers offer 12-month contracts
  - One-time switching discount applied day before expiry
  - Day rates vs night rates (6am-6pm vs 6pm-6am)
  - Separate buy/sell prices
  - Minimum energy purchase requirements
- **Market Modes**:
  - Contract mode: Fixed prices per contract terms
  - Spot mode: Real-time market prices (for non-contracted customers)
- **Realism Level**: Balanced
  - Solar production follows sine wave (peak at noon)
  - Consumption has morning/evening peaks
  - Battery storage and sell-back enabled
  - Contract lifecycle with discount optimization

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
**Update Frequency**: Every 100ms real-time (~3 simulation hours)

**Production (Solar/Wind)**:
- Sine wave: 0W at night, peak 3-5kW at noon
- +/- 20% randomness
- Calculated based on current simulation time

**Consumption**:
- Base load: 500W always
- Morning peak (7-9am): +1500W
- Evening peak (6-10pm): +2000W
- Random appliances: +/- 300W
- Calculated based on current simulation time

**Battery**:
- 10kWh capacity
- Charges when production > consumption
- Discharges when consumption > production
- Can sell excess to grid

**Energy Balance Optimization** (Goal: minimize bought - sold):
- Track total energy bought vs sold over contract period
- Consider contract terms: day/night rates, buy/sell prices
- Optimize battery charge/discharge to minimize balance
- Use battery to buy at cheap times, sell at expensive times

**Contract Management**:
- Start with random 12-month contract (random start date within past year)
- Monitor all provider offers (via WAMP subscriptions)
- Evaluate switching opportunities:
  - Compare projected balance over remaining contract period
  - Factor in switching discount (only if switching before expiry-1 day)
  - Account for minimum purchase requirements
  - Switch if projected savings > threshold
- On contract expiry: automatically switch to best offer
- Can operate on spot market if no active contract

#### Provider Bots (GenServer per provider)
**Update Frequency**: Every 500ms real-time (~14.6 simulation hours)

**Contract Offers** (published continuously):
- 12-month duration
- Day buy price ($/kWh) - price customer pays when buying during day
- Night buy price ($/kWh) - price customer pays when buying at night
- Day sell price ($/kWh) - price provider pays when customer sells during day
- Night sell price ($/kWh) - price provider pays when customer sells at night
- Switching discount ($) - one-time discount applied day before contract expiry
- Minimum monthly purchase (kWh) - penalty if not met

**Spot Market Prices** (for non-contracted customers):
- Updated more frequently than contract offers
- Higher volatility than contract prices
- Designed to encourage contract adoption

**Pricing Strategies** (for market variety):
- Provider A: "Steady Eddie" - consistent mid-range, small discount, low minimum
- Provider B: "Night Owl" - cheap at night (50% discount), expensive day, big discount
- Provider C: "Solar Surfer" - cheap during solar peak, expensive at night
- Provider D: "Peak Predator" - high during consumption peaks, low otherwise
- Provider E: "Discount King" - competitive rates, huge switching discount, high minimum

**Revenue Goals**:
- Maximize (energy_sold_to_customers * buy_price) - (energy_bought_from_customers * sell_price)
- Maximize market share (number of active contracts)
- Balance acquisition cost (switching discounts) vs customer lifetime value

### 6. Event Topics Structure
```
# Simulation time (broadcast from hub)
energy.hub.simulation.time

# Home events (published by home bots)
energy.hub.home.{home_id}.production
energy.hub.home.{home_id}.consumption
energy.hub.home.{home_id}.storage
energy.hub.home.{home_id}.balance        # NEW: energy bought vs sold
energy.hub.home.{home_id}.contract       # Contract signed/renewed/expired

# Provider events (published by provider bots)
energy.hub.provider.{provider_id}.contract_offer    # NEW: contract terms
energy.hub.provider.{provider_id}.spot_price        # NEW: spot market prices

# Market events (published by either)
energy.hub.market.contract.signed
energy.hub.market.contract.switched
energy.hub.market.trade                  # NEW: buy/sell transaction
```

### 7. Event Payloads

```elixir
# Simulation Time (broadcast every 1 second real-time)
%{
  simulation_time: ~U[2025-06-15 14:32:00Z],  # Current simulation datetime
  speed: 105_120,                              # Speed multiplier
  real_elapsed_ms: 150_000                     # Real milliseconds since start
}

# Production
%{
  home_id: "home_001",
  watts: 3500,
  source: "solar",
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Consumption
%{
  home_id: "home_001",
  watts: 1200,
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Storage
%{
  home_id: "home_001",
  battery_percent: 75,
  capacity_kwh: 10.0,
  state: :charging | :discharging | :idle,
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Energy Balance (published periodically, e.g., hourly)
%{
  home_id: "home_001",
  contract_id: "contract_xyz",
  period_start: ~U[2025-01-01 00:00:00Z],
  period_end: ~U[2025-06-15 14:00:00Z],
  energy_bought_kwh: 1250.5,
  energy_sold_kwh: 890.3,
  net_balance_kwh: 360.2,              # bought - sold
  cost_paid: 187.56,
  revenue_received: 62.32,
  net_cost: 125.24,                    # paid - received
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Contract Offer (published by providers every ~15 simulation hours)
%{
  provider_id: "provider_a",
  offer_id: "offer_12345",
  duration_months: 12,
  day_buy_price: 0.15,        # $/kWh customer pays during day (6am-6pm)
  night_buy_price: 0.08,      # $/kWh customer pays during night (6pm-6am)
  day_sell_price: 0.10,       # $/kWh provider pays during day
  night_sell_price: 0.05,     # $/kWh provider pays during night
  switching_discount: 25.00,  # $ one-time discount (applied day before expiry)
  minimum_monthly_kwh: 100,   # Minimum purchase requirement
  valid_from: ~U[2025-06-15 14:32:00Z],
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Spot Price (published by providers, higher frequency, more volatile)
%{
  provider_id: "provider_a",
  buy_price: 0.22,           # $/kWh - more expensive than contract
  sell_price: 0.08,          # $/kWh - less attractive than contract
  valid_from: ~U[2025-06-15 14:32:00Z],
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Contract Signed (home accepts provider offer)
%{
  contract_id: "contract_xyz",
  home_id: "home_001",
  provider_id: "provider_a",
  offer_id: "offer_12345",
  start_date: ~U[2025-06-15 14:32:00Z],
  end_date: ~U[2026-06-15 14:32:00Z],
  terms: %{...},  # Copy of contract terms
  reason: :new | :renewal | :switch,
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Contract Switched (home switches from one provider to another)
%{
  home_id: "home_001",
  from_contract_id: "contract_abc",
  from_provider_id: "provider_b",
  to_contract_id: "contract_xyz",
  to_provider_id: "provider_a",
  reason: "balance_optimization",
  projected_savings: 45.50,            # Projected savings over contract period
  days_before_expiry: 180,             # How early they switched
  discount_received: 25.00,            # If switched before expiry-1 day, 0
  simulation_time: ~U[2025-06-15 14:32:00Z]
}

# Trade (buy or sell transaction)
%{
  home_id: "home_001",
  provider_id: "provider_a",
  type: :buy | :sell,
  kwh: 0.35,                  # Energy amount (for ~3 sim hour update at 100ms)
  price_per_kwh: 0.15,
  total: 0.0525,              # kwh * price
  is_day: true,               # Day rate vs night rate
  contract_id: "contract_xyz" | nil,  # nil if spot market
  simulation_time: ~U[2025-06-15 14:32:00Z]
}
```

## Actual Umbrella Structure

```
macula-energy-mesh-poc/
├── system/                          # Umbrella application root
│   ├── apps/
│   │   ├── macula_os/               # MACULA PLATFORM (The Product)
│   │   │                            # Distributed runtime for BEAM applications
│   │   │                            # - Dual mode: realm_hub or edge
│   │   │                            # - Embeds Bondy (hub mode)
│   │   │                            # - WAMP client (MaculaOs.Wamp)
│   │   │                            # - Payload management (future)
│   │   │                            # - Realm lifecycle management
│   │   │
│   │   ├── cortex_iq_core/          # CORTEXIQ: Domain models
│   │   │                            # - Home, Provider, Contract, etc.
│   │   │                            # - Shared by all CortexIQ payloads
│   │   │
│   │   ├── cortex_iq_dashboard/     # CORTEXIQ PAYLOAD: Analytics
│   │   │                            # - Event aggregation
│   │   │                            # - Business logic
│   │   │
│   │   ├── cortex_iq_dashboard_web/ # CORTEXIQ PAYLOAD: Visualization
│   │   │                            # - Phoenix LiveView UI
│   │   │                            # - Real-time dashboard
│   │   │                            # (dashboard + dashboard_web = one payload)
│   │   │
│   │   ├── cortex_iq_homes/         # CORTEXIQ PAYLOAD: Home bots
│   │   │                            # - Simulates homes with solar/battery
│   │   │                            # - Contract optimization
│   │   │
│   │   └── cortex_iq_utilities/     # CORTEXIQ PAYLOAD: Provider bots
│   │                                # - Pricing strategies
│   │                                # - Contract offers
│   │
│   ├── config/                      # Shared configuration
│   └── mix.exs                      # Umbrella root
│
├── dev-env/
│   └── docker-compose.yml           # Infrastructure (Bondy, Postgres)
│
├── Dockerfile.hub                   # Hub node (MaculaOs + Dashboard payload)
├── Dockerfile.edge                  # Edge nodes (MaculaOs + domain payloads)
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEMO_SCRIPT.md
│   └── screenshots/
│
└── start_demo.sh                    # One-command startup
```

**Architecture Philosophy**:

**Macula = The Platform**
- `macula_os` is the distributed runtime (like Kubernetes for BEAM apps)
- Runs in two modes: `realm_hub` (hosts realm + Bondy) or `edge` (connects to realm)
- Provides WAMP infrastructure for all payloads
- Configuration-driven, ephemeral, stateless where possible

**CortexIQ = Reference Application**
- All `cortex_iq_*` apps are payloads running on Macula
- Dashboard is NOT infrastructure - it's just another payload that visualizes events
- Demonstrates event-driven architecture on the platform

**Future Extensibility**:
- New payloads can be added without changing Macula platform
- Dynamic payload loading (roadmap)
- Multi-realm support via configuration
- Organization onboarding via configuration files

## App Responsibilities

### MACULA PLATFORM

#### macula_os
**WAMP Gateway Sidecar - The platform's secure proxy to Macula realms**

**Architecture**: MaculaOs runs as a **sidecar container** alongside application containers in Kubernetes pods. Applications connect to `localhost:<port>` and MaculaOs proxies WAMP traffic to Bondy with authentication, metering, and connection resilience.

**Why Sidecar Pattern?**
- **Multi-language support**: Applications can be written in any language (Python, Go, Rust, JS, etc.)
- **Container-based deployment**: Maintains GitOps workflow, no BEAM release coupling
- **Monetization ready**: API key auth, usage metering, quota enforcement
- **Connection resilience**: Automatic retry and reconnection when Bondy restarts
- **Security**: Applications never directly access Bondy, all traffic authenticated/metered

**Pod Architecture**:
```
┌─────────────────────────────────────────┐
│ Kubernetes Pod                          │
│                                         │
│  ┌────────────────┐  ┌───────────────┐ │
│  │ Application    │→ │  MaculaOs     │ │
│  │ Container      │  │  Sidecar      │ │
│  │ (any language) │  │               │ │
│  │                │  │ WAMP Proxy    │ │
│  │ localhost:8080 │  │ + Auth        │ │
│  └────────────────┘  │ + Metering    │ │
│                      │ + Retry       │ │
│                      └───────┬───────┘ │
└──────────────────────────────┼─────────┘
                               ↓ WAMP/WS
                    ┌──────────────────┐
                    │  Bondy (Hub)     │
                    └──────────────────┘
```

**Core Components**:
- `MaculaOs.Application` - Main supervision tree
- `MaculaOs.Proxy.Server` - WebSocket server accepting localhost connections
- `MaculaOs.Proxy.Upstream` - WAMP client to Bondy with retry logic
- `MaculaOs.Auth.ApiKey` - API key validation and namespace enforcement
- `MaculaOs.Metering` - Usage tracking (pub/sub operations per API key)
- `MaculaOs.Wamp.Protocol` - WAMP protocol message handling

**Features**:
1. **API Key Authentication**:
   - Each application has unique API key
   - Keys map to organization/namespace
   - Topic prefix enforcement (e.g., `cortexiq.homes.*`)

2. **Usage Metering**:
   - Track PUBLISH/SUBSCRIBE/CALL operations
   - Per API key metrics
   - Prometheus export for billing integration

3. **Connection Resilience**:
   - Exponential backoff reconnection to Bondy
   - Queue messages during disconnect
   - Replay on reconnection
   - Transparent to applications

4. **Multi-Tenancy**:
   - Namespace isolation via topic prefixes
   - Prevent cross-organization access
   - Future: topic-level ACLs

**Configuration**:
```yaml
# Kubernetes Deployment with MaculaOs sidecar
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      # Application container
      - name: my-app
        image: my-app:latest
        env:
        - name: MACULA_URL
          value: "ws://localhost:8080/ws"
        - name: MACULA_API_KEY
          valueFrom:
            secretKeyRef:
              name: my-app-apikey
              key: key

      # MaculaOs sidecar
      - name: macula-os
        image: macula/macula-os:latest
        ports:
        - containerPort: 8080
        env:
        - name: BONDY_URL
          value: "ws://172.20.0.2:30080/ws"
        - name: BONDY_REALM
          value: "be.cortexiq.energy"
```

**API Key Secret**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-apikey
stringData:
  key: "unique-api-key-xyz"
  namespace: "my-org.my-app"  # Topic prefix allowed
```

**Client Connection** (any language with WAMP library):
```python
# Python example
from autobahn.asyncio.wamp import ApplicationSession

class MyApp(ApplicationSession):
    async def onConnect(self):
        self.join(
            realm="be.cortexiq.energy",
            authmethods=["macula-apikey"],
            authextra={"macula_apikey": os.getenv("MACULA_API_KEY")}
        )

    async def onJoin(self, details):
        # Application code - standard WAMP
        await self.publish("my-org.my-app.events.something", "data")
```

**Dependencies**:
- `jason` - JSON encoding/decoding
- `websockex` - WebSocket client (upstream to Bondy)
- `plug_cowboy` - HTTP/WebSocket server (localhost proxy)
- `telemetry` - Metrics/instrumentation

---

### CORTEXIQ APPLICATION (Payloads)

#### cortex_iq_core
**Shared domain models for CortexIQ payloads**

- Domain models: `Home`, `Provider`, `Contract`, `ContractOffer`, `EnergyBalance`, `SpotPrice`
- Utilities: `SimulationTime`, `Geography`
- **No processes, pure data structures**
- Shared by all CortexIQ payloads

**Dependencies**: None

---

#### cortex_iq_dashboard + cortex_iq_dashboard_web
**Analytics and Visualization Payload** (one logical unit, two apps)

**cortex_iq_dashboard**:
- `CortexIqDashboard.Application` - Supervision tree
- `CortexIqDashboard.WampSubscriber` - Subscribes to ALL events via MaculaOs.Wamp
- `CortexIqDashboard.Aggregator` - Real-time event aggregation
- `CortexIqDashboard.SimulationClock` - Shared simulation time (broadcasts to realm)
- **Subscribes**: All CortexIQ events (homes, utilities)
- **Publishes**: Simulation time events

**cortex_iq_dashboard_web**:
- `CortexIqDashboardWeb.Endpoint` - Phoenix HTTP/WebSocket endpoint
- `CortexIqDashboardWeb.DashboardLive` - Main real-time dashboard
- Components: topology, metrics, activity feed, charts
- **Displays**: Aggregated data from cortex_iq_dashboard

**Dependencies**: `macula_os`, `cortex_iq_core`, `phoenix`, `phoenix_live_view`

---

#### cortex_iq_homes
**Home Simulation Bots Payload**

- `CortexIqHomes.Application` - Supervision tree
- `CortexIqHomes.HomeBot` - GenServer per home (N homes, ENV configurable)
- Solar production, consumption, battery simulation
- Contract optimization and switching logic
- **Publishes**: production, consumption, storage, balance, contract events
- **Subscribes**: provider contract offers, simulation time

**Dependencies**: `macula_os`, `cortex_iq_core`

---

#### cortex_iq_utilities
**Energy Provider Bots Payload**

- `CortexIqUtilities.Application` - Supervision tree
- `CortexIqUtilities.ProviderBot` - GenServer per provider (N providers, ENV configurable)
- Pricing strategies: "Steady Eddie", "Night Owl", "Solar Surfer", "Peak Predator", "Discount King"
- **Publishes**: contract offers, spot prices
- **Subscribes**: simulation time, (future: market events)

**Dependencies**: `macula_os`, `cortex_iq_core`

## Communication Architecture

**Macula Ring Topology** (Realm: `be.cortexiq.energy`):
```
┌────────────────────────────────────────────────────────────┐
│ Hub Node (MaculaOs - realm_hub mode)                      │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │ MaculaOs Platform                                │    │
│  │  ┌────────────────────────────────────────────┐  │    │
│  │  │ Bondy (WAMP Router)                        │  │    │
│  │  │ Realm: be.cortexiq.energy                  │  │    │
│  │  └────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────┘    │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │ CortexIQ Payloads                                │    │
│  │  • cortex_iq_dashboard (analytics)               │    │
│  │  • cortex_iq_dashboard_web (Phoenix UI)          │    │
│  └──────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
          ▲                     ▲                  ▲
          │ WAMP                │ WAMP             │ WAMP
          │                     │                  │
┌─────────┴──────────┐  ┌───────┴───────────┐  ┌──┴─────────────┐
│ Edge Node 1        │  │ Edge Node 2       │  │ Edge Node 3    │
│ (MaculaOs - edge)  │  │ (MaculaOs - edge) │  │ (MaculaOs)     │
│                    │  │                   │  │                │
│ Payload:           │  │ Payload:          │  │ Payload:       │
│ cortex_iq_homes    │  │ cortex_iq_homes   │  │ cortex_iq_     │
│ (25 bots)          │  │ (25 bots)         │  │  utilities     │
│                    │  │                   │  │ (5 bots)       │
└────────────────────┘  └───────────────────┘  └────────────────┘

Future: Add more payload types
┌──────────────────┐
│ Edge Node N      │
│ (MaculaOs)       │  ← New payload type!
│                  │
│ Payload:         │
│ cortex_iq_       │
│  analytics       │
└──────────────────┘
```

**Communication Patterns** (via MaculaOs.Wamp):

1. **cortex_iq_homes → Bondy (WAMP Publish)**:
   - Home bots publish production/consumption/storage/contract events
   - Topics: `be.cortexiq.energy.home.{home_id}.{event_type}`
   - Example: `be.cortexiq.energy.home.home_001.production`

2. **cortex_iq_utilities → Bondy (WAMP Publish)**:
   - Provider bots publish contract offers and spot prices
   - Topics: `be.cortexiq.energy.utility.{provider_id}.{type}`
   - Example: `be.cortexiq.energy.utility.provider_a.contract_offer`

3. **cortex_iq_homes subscribes (via MaculaOs.Wamp)**:
   - Home bots subscribe to ALL provider contract offers
   - Pattern: `be.cortexiq.energy.utility.*.contract_offer`
   - Triggers contract optimization when new offers arrive

4. **cortex_iq_dashboard subscribes (via MaculaOs.Wamp)**:
   - Dashboard subscribes to ALL events for visualization
   - Patterns: `be.cortexiq.energy.home.*.*`, `be.cortexiq.energy.utility.*.*`
   - Aggregates real-time data for charts and metrics

5. **Pure Event-Driven Architecture**:
   - No direct communication between payloads
   - All communication flows through Bondy (MaculaOs realm hub)
   - Easy to add new payloads - just subscribe/publish via MaculaOs.Wamp
   - Payloads are loosely coupled, independently deployable

**Data Flow**:
```
Simulation Clock (cortex_iq_dashboard) → broadcasts time tick
    ↓
cortex_iq_utilities: Provider Bots calculate prices
    ↓
Provider publishes contract offer → Bondy → cortex_iq_homes subscribes
    ↓
cortex_iq_homes: Home Bot receives offer → Evaluates optimization
    ↓
Home publishes events → Bondy → cortex_iq_dashboard subscribes
    ↓
Dashboard aggregates and displays in real-time via Phoenix LiveView
```

**Key Insight**: All payloads use `MaculaOs.Wamp` to communicate. They don't know about each other - they only know topics and events. This makes the system highly extensible.

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

**Project State**: Phase 1/2 - Core infrastructure complete, implementing contract system

**Completed**:
- ✅ Umbrella app structure created in `system/`
- ✅ Seven apps created:
  - Infrastructure: mesh_core, mesh_wamp, mesh_hub, mesh_hub_web
  - Edge runtime: mesh_edge (generic bot OS)
  - Bot implementations: mesh_edge_homes, mesh_edge_utilities
- ✅ Architecture decisions finalized (hub-spoke, embedded Bondy, edge runtime pattern)
- ✅ **Domain models implemented** (mesh_core):
  - `MeshCore.SimulationTime` - Time utilities (day/night, date calculations)
  - `MeshCore.Contract` - 12-month contracts with day/night pricing
  - `MeshCore.ContractOffer` - Provider offers with switching discounts
  - `MeshCore.EnergyBalance` - Track energy bought vs sold
  - `MeshCore.SpotPrice` - Spot market pricing
  - `MeshCore.Home` - Home metadata with location
  - `MeshCore.Provider` - Provider metadata with 5 strategies
- ✅ **Simulation clock implemented** (mesh_hub):
  - `MeshHub.SimulationClock` - Configurable speed (default: 105,120x)
  - ENV: `SIMULATION_SPEED`, `SIMULATION_START_DATE`
  - Broadcasts time every 1 second to `energy.hub.simulation.time`
  - 1 simulation year = 5 real minutes

**Current Task**:
- 🔄 Implementing contract-based provider and home bots
  - Provider bots: publish contract offers + spot prices
  - Home bots: contract lifecycle management, balance optimization
  - Event topics updated for contract system

**Next Steps**:
1. Redesign provider bot (mesh_edge_utilities) for contract offers
2. Redesign home bot (mesh_edge_homes) for contract management
3. Update dashboard to show contracts and energy balance
4. Create Dockerfiles for hub and edge
5. Set up docker-compose.yml
6. Test end-to-end contract lifecycle

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
- in our scripts, environment variables should not reflect choices in terms of distros, but should reflect their purpose
- CortexIQ Dashboard DOES NOT need to connect to postgres! All data in the dashboard must come from 2  sources only: eiter by subscribing to a WAMP topic (and processing the events that are published on it) OR cortex_iq_queries, by CALLING a published RPC