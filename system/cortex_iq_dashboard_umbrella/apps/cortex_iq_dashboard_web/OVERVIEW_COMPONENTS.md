# Overview Page - Modular Component Architecture

## Overview Page Structure (Simplified)

The overview page focuses on **platform-wide metrics only**, removing provider-specific details.

### Component Hierarchy

```
DashboardLive (Overview Tab)
├── SimulationControls          # Simulation time, play/pause, speed, reset
├── StatsCards                  # 6 platform-wide metrics
├── FinancialSummary            # CortexIQ revenue tracking (4 cards)
└── PlatformCharts              # Time-series visualizations (4 charts)
```

### Components Created

#### 1. SimulationControls (`simulation_controls.ex`)
**Purpose**: Control simulation state and display current time

**Features:**
- Simulation date/time with day/night indicator (☀️/🌙)
- Status display (Running/Paused)
- Speed display and controls (1x, 100x, 1K, 10K, Max)
- Play/Pause toggle button
- Reset button with confirmation

**Props:**
- `simulation_time` - Current simulation datetime
- `simulation_speed` - Current speed multiplier
- `simulation_paused` - Boolean pause state

**Events:** Sends messages to parent LiveView
- `{:simulation_control, :pause}`
- `{:simulation_control, :resume}`
- `{:simulation_control, :set_speed, speed}`
- `{:simulation_control, :reset}`

---

#### 2. StatsCards (`stats_cards.ex`)
**Purpose**: Display 6 key platform-wide metrics

**Metrics:**
1. Connected Homes (green)
2. Energy Bought (red) with cost
3. Energy Sold (green) with revenue
4. Net Balance (red/green) with net cost
5. Average Battery % (blue)
6. Contract Switches (purple)

**Props:**
- `stats` - Map with all metrics

**Features:**
- Color-coded metrics
- Energy formatting (kWh/MWh)
- Currency formatting

---

#### 3. FinancialSummary (`financial_summary.ex`)
**Purpose**: Display CortexIQ platform financial performance

**Metrics (4 cards):**
1. Customer Savings (Gross) - Total savings before commission
2. CortexIQ Revenue (20%) - Platform commission
3. Customer Savings (Net) - After commission
4. Customer ROI - Return on investment percentage

**Props:**
- `stats` - Map with financial metrics

**Features:**
- Gradient backgrounds (green/yellow/blue/purple)
- Automatic ROI calculation
- From/After annotations

---

#### 4. PlatformCharts (`platform_charts.ex`)
**Purpose**: Visualize platform-wide KPIs over time

**Charts (4 time-series):**
1. **Connected Homes** - Track platform growth
2. **Production vs Consumption** - System energy balance
3. **Contract Switches (Cumulative)** - Market activity
4. **Financial Performance** - Savings and commission trends

**Props:**
- `aggregate_history` - Time-series data array
- `overview` - Contains `savings_history`

**Features:**
- Requires minimum 5 data points to display
- Shows placeholder message when insufficient data
- Uses ApexCharts via Phoenix LiveView hooks

---

## Removed from Overview

### ProviderCards (moved to Providers tab only)
- Individual provider market share
- Provider strategy displays
- Provider selection

**Rationale**: The overview should show platform-wide health, not individual provider details. Provider-specific information belongs in the dedicated Providers tab.

---

## Benefits of Modular Architecture

### 1. Maintainability
- **Before**: 2397-line monolithic file
- **After**: 4 focused components (190 + 71 + 53 + 78 = ~392 lines for overview)
- **Reduction**: ~83% less code in main LiveView for overview section

### 2. Testability
- Each component can be tested independently
- Mock props for unit testing
- Isolated event handling

### 3. Reusability
- SimulationControls can be used across all tabs
- StatsCards can be embedded in other views
- Components are composable

### 4. Separation of Concerns
- Each component has a single, clear responsibility
- Event handling is localized
- Data formatting is encapsulated

---

## Usage Example

```elixir
defmodule CortexIqDashboardWeb.DashboardLive do
  use CortexIqDashboardWeb, :live_view

  # In render function for overview tab
  def render(assigns) do
    ~H"""
    <%= if @active_tab == :overview do %>
      <!-- Simulation Controls -->
      <.live_component
        module={CortexIqDashboardWeb.Components.SimulationControls}
        id="simulation-controls"
        simulation_time={@simulation_time}
        simulation_speed={@simulation_speed}
        simulation_paused={@simulation_paused}
      />

      <!-- Platform Metrics -->
      <.live_component
        module={CortexIqDashboardWeb.Components.StatsCards}
        id="stats-cards"
        stats={@stats}
      />

      <!-- Financial Summary -->
      <.live_component
        module={CortexIqDashboardWeb.Components.FinancialSummary}
        id="financial-summary"
        stats={@stats}
      />

      <!-- Time-Series Charts -->
      <.live_component
        module={CortexIqDashboardWeb.Components.PlatformCharts}
        id="platform-charts"
        aggregate_history={@aggregate_history}
        overview={@overview}
      />
    <% end %>
    """
  end

  # Handle events from SimulationControls
  def handle_info({:simulation_control, :pause}, socket) do
    # Implement pause logic
    {:noreply, socket}
  end

  def handle_info({:simulation_control, :resume}, socket) do
    # Implement resume logic
    {:noreply, socket}
  end

  def handle_info({:simulation_control, :set_speed, speed}, socket) do
    # Implement speed change logic
    {:noreply, socket}
  end

  def handle_info({:simulation_control, :reset}, socket) do
    # Implement reset logic
    {:noreply, socket}
  end
end
```

---

## Next Steps

1. ✅ Create core components (completed)
2. ⏳ Refactor DashboardLive to use new components
3. ⏳ Implement simulation reset mechanism
4. ⏳ Test components individually
5. ⏳ Deploy and verify in Kubernetes

---

## File Structure

```
apps/cortex_iq_dashboard_web/lib/cortex_iq_dashboard_web/
├── live/
│   ├── dashboard_live.ex                    # Main LiveView (simplified)
│   └── components/
│       ├── simulation_controls.ex           # ✅ 190 lines
│       ├── stats_cards.ex                   # ✅ 71 lines
│       ├── financial_summary.ex             # ✅ 53 lines
│       ├── platform_charts.ex               # ✅ 78 lines
│       └── provider_cards.ex                # ✅ 74 lines (Providers tab only)
```

Total: 466 lines of well-organized, testable component code vs 2397-line monolith.
