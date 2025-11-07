defmodule CortexIqDashboardWeb.OverviewLive do
  @moduledoc """
  Overview page LiveView - Platform-wide metrics and performance.

  Displays:
  - Simulation controls (time, speed, pause/resume, reset)
  - Platform-wide statistics (homes, energy, battery, switches)
  - Financial summary (CortexIQ revenue model)
  - Performance charts (savings, production/consumption, market trends)
  """
  use CortexIqDashboardWeb, :live_view

  alias CortexIqDashboard.Views.OverviewAggregator
  alias CortexIqDashboard.QueryClient
  alias CortexIqDashboard.SimulationClient
  alias CortexIqDashboardWeb.Components.{NavMenu, SimulationControls, StatsCards, FinancialSummary}

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.info("OverviewLive: mount() called, connected: #{connected?(socket)}")

    if connected?(socket) do
      # Just-in-Time WAMP subscription model
      bondy_url = System.get_env("BONDY_URL", "ws://bondy.macula-system.svc.cluster.local:18080/ws")
      realm_uri = System.get_env("BONDY_REALM", "be.cortexiq.energy")

      # Start WAMP client connection (async)
      Logger.info("OverviewLive: Starting WAMP client for JIT subscription")
      {:ok, wamp_client} = MaculaSdk.Wamp.Client.start_link(
        url: bondy_url,
        realm: realm_uri,
        serializer: :json
      )

      # Schedule subscription after connection establishes (2 second delay)
      Process.send_after(self(), :subscribe_to_events, 2_000)

      Logger.info("OverviewLive: WAMP client started, subscriptions scheduled")

      {:ok,
       socket
       |> assign(:current_path, "/")
       |> assign(:wamp_client, wamp_client)
       |> assign(:waiting_for_data, true)
       |> assign(:overview, %{})
       |> assign(:simulation_time, nil)
       |> assign(:simulation_speed, 105_120)
       |> assign(:simulation_paused, false)
       |> assign(:stats, default_stats())
       |> assign(:aggregate_history, [])}
    else
      # Initial render (not connected yet)
      {:ok,
       socket
       |> assign(:current_path, "/")
       |> assign(:wamp_client, nil)
       |> assign(:waiting_for_data, true)
       |> assign(:overview, %{})
       |> assign(:simulation_time, nil)
       |> assign(:simulation_speed, 105_120)
       |> assign(:simulation_paused, false)
       |> assign(:stats, default_stats())
       |> assign(:aggregate_history, [])}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Cleanup: stop WAMP client when LiveView terminates
    if socket.assigns[:wamp_client] do
      Logger.info("OverviewLive: Terminating, stopping WAMP client")
      MaculaSdk.Wamp.Client.stop(socket.assigns.wamp_client)
    end
    :ok
  end

  # Handle delayed subscription (after WAMP client connects)

  @impl true
  def handle_info(:subscribe_to_events, socket) do
    wamp_client = socket.assigns[:wamp_client]

    if wamp_client do
      self_pid = self()

      # Subscribe to history updates (for charts)
      case MaculaSdk.Wamp.Client.subscribe(
        wamp_client,
        "be.cortexiq.projections.history_updated",
        fn _topic, event_data ->
          send(self_pid, {:wamp_event, :history_updated, event_data})
        end,
        %{}
      ) do
        :ok -> Logger.info("OverviewLive: ✅ Subscribed to be.cortexiq.projections.history_updated")
        {:error, reason} -> Logger.error("OverviewLive: Failed to subscribe to history_updated: #{inspect(reason)}")
      end

      # Subscribe to simulation time
      case MaculaSdk.Wamp.Client.subscribe(
        wamp_client,
        "be.cortexiq.simulation.time_advanced",
        fn _topic, event_data ->
          send(self_pid, {:wamp_event, :time_advanced, event_data})
        end,
        %{}
      ) do
        :ok -> Logger.info("OverviewLive: ✅ Subscribed to be.cortexiq.simulation.time_advanced")
        {:error, reason} -> Logger.error("OverviewLive: Failed to subscribe to time_advanced: #{inspect(reason)}")
      end

      # Subscribe to totals calculated (main overview data)
      case MaculaSdk.Wamp.Client.subscribe(
        wamp_client,
        "be.cortexiq.projections.totals_calculated",
        fn _topic, event_data ->
          send(self_pid, {:wamp_event, :totals_calculated, event_data})
        end,
        %{}
      ) do
        :ok -> Logger.info("OverviewLive: ✅ Subscribed to be.cortexiq.projections.totals_calculated")
        {:error, reason} -> Logger.error("OverviewLive: Failed to subscribe to totals_calculated: #{inspect(reason)}")
      end

      Logger.info("OverviewLive: All WAMP subscriptions attempted")
    else
      Logger.error("OverviewLive: No WAMP client available for subscription")
    end

    {:noreply, socket}
  end

  # Handle WAMP events (JIT subscription model)

  @impl true
  def handle_info({:wamp_event, :totals_calculated, event_data}, socket) do
    # Main overview data from projections service
    kwargs = Map.get(event_data, :kwargs, %{})

    Logger.info("OverviewLive: Received totals_calculated event")

    stats = %{
      homes: Map.get(kwargs, "total_homes", 0),
      connected_homes: Map.get(kwargs, "connected_homes_count", 0),
      total_production_kw: Map.get(kwargs, "total_production_kw", 0.0),
      total_consumption_kw: Map.get(kwargs, "total_consumption_kw", 0.0),
      total_energy_bought_kwh: Map.get(kwargs, "total_energy_bought_kwh", 0.0),
      total_energy_sold_kwh: Map.get(kwargs, "total_energy_sold_kwh", 0.0),
      total_cost_paid: Map.get(kwargs, "total_cost_paid", 0.0),
      total_revenue_received: Map.get(kwargs, "total_revenue_received", 0.0),
      avg_battery_percent: Map.get(kwargs, "avg_battery_percent", 0.0),
      contract_switches: Map.get(kwargs, "contract_switches", 0),
      cortexiq_total_savings: Map.get(kwargs, "cortexiq_total_savings", 0.0),
      cortexiq_total_commission: Map.get(kwargs, "cortexiq_total_commission", 0.0),
      cortexiq_net_savings: Map.get(kwargs, "cortexiq_net_savings", 0.0)
    }

    {:noreply,
     socket
     |> assign(:waiting_for_data, false)
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_info({:wamp_event, :time_advanced, event_data}, socket) do
    # Simulation time updates
    kwargs = Map.get(event_data, :kwargs, %{})
    simulation_time = Map.get(kwargs, "simulation_time")
    simulation_speed = Map.get(kwargs, "speed", socket.assigns.simulation_speed)
    simulation_paused = Map.get(kwargs, "paused", socket.assigns.simulation_paused)

    {:noreply,
     socket
     |> assign(:simulation_time, simulation_time)
     |> assign(:simulation_speed, simulation_speed)
     |> assign(:simulation_paused, simulation_paused)}
  end

  @impl true
  def handle_info({:wamp_event, :history_updated, event_data}, socket) do
    # History updates for charts
    kwargs = Map.get(event_data, :kwargs, %{})

    history_point = %{
      timestamp: Map.get(kwargs, "timestamp"),
      total_production_w: Map.get(kwargs, "total_production_w", 0),
      total_consumption_w: Map.get(kwargs, "total_consumption_w", 0),
      avg_battery_percent: Map.get(kwargs, "avg_battery_percent", 0.0),
      total_homes: Map.get(kwargs, "total_homes", 0)
    }

    # Add new point and keep last 100
    new_history = (socket.assigns.aggregate_history ++ [history_point]) |> Enum.take(-100)

    Logger.info("OverviewLive: History updated, buffer size: #{length(new_history)}, pushing to charts")

    # Push updated history to chart hooks
    {:noreply,
     socket
     |> assign(:aggregate_history, new_history)
     |> push_event("history_updated", %{history: new_history})}
  end

  @impl true
  def handle_info({:reset_simulation}, socket) do
    require Logger
    Logger.info("OverviewLive: Received reset_simulation event")

    # Clear local state
    {:noreply,
     socket
     |> assign(:overview, %{})
     |> assign(:aggregate_history, [])
     |> assign(:stats, %{
       homes: 0,
       connected_homes: 0,
       total_production_kw: 0.0,
       total_consumption_kw: 0.0,
       total_energy_bought_kwh: 0.0,
       total_energy_sold_kwh: 0.0,
       total_cost_paid: 0.0,
       total_revenue_received: 0.0,
       avg_battery_percent: 0.0,
       contract_switches: 0,
       cortexiq_total_savings: 0.0,
       cortexiq_total_commission: 0.0,
       cortexiq_net_savings: 0.0
     })}
  end

  @impl true
  def handle_info({:simulation_control, :pause}, socket) do
    require Logger
    Logger.warning("OverviewLive: Received {:simulation_control, :pause} message!")

    parent = self()
    Task.start(fn ->
      result = SimulationClient.pause_simulation()
      send(parent, {:rpc_pause_result, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rpc_pause_result, {:ok, result}}, socket) do
    message = Map.get(result, "message", "Simulation paused")
    {:noreply, socket
     |> assign(:simulation_paused, true)
     |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:rpc_pause_result, {:error, reason}}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:simulation_control, :resume}, socket) do
    parent = self()
    Task.start(fn ->
      result = SimulationClient.resume_simulation()
      send(parent, {:rpc_resume_result, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rpc_resume_result, {:ok, result}}, socket) do
    message = Map.get(result, "message", "Simulation resumed")
    {:noreply, socket
     |> assign(:simulation_paused, false)
     |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:rpc_resume_result, {:error, reason}}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:simulation_control, :set_speed, speed}, socket) do
    parent = self()
    Task.start(fn ->
      result = SimulationClient.set_simulation_speed(speed)
      send(parent, {:rpc_set_speed_result, result, speed})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rpc_set_speed_result, {:ok, result}, speed}, socket) do
    message = Map.get(result, "message", "Speed updated to #{speed}x")
    {:noreply, socket
     |> assign(:simulation_speed, speed)
     |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:rpc_set_speed_result, {:error, reason}, _speed}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to set speed: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:simulation_control, :reset}, socket) do
    require Logger
    Logger.warning("OverviewLive: Received {:simulation_control, :reset} message!")

    # Make RPC call in separate task to avoid blocking/crashing LiveView
    parent = self()
    Task.start(fn ->
      Logger.warning("OverviewLive: Calling SimulationClient.reset_simulation() in task...")
      result = SimulationClient.reset_simulation()
      send(parent, {:rpc_reset_result, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rpc_reset_result, {:ok, result}}, socket) do
    require Logger
    Logger.warning("OverviewLive: RPC succeeded! Result: #{inspect(result)}")
    message = Map.get(result, "message", "Simulation reset successfully")
    new_start_time = Map.get(result, "new_start_time")
    Logger.warning("OverviewLive: Updating assigns - simulation_time: #{inspect(new_start_time)}, simulation_paused: false")

    {:noreply, socket
     |> assign(:simulation_time, new_start_time)
     |> assign(:simulation_paused, false)
     |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:rpc_reset_result, {:error, reason}}, socket) do
    require Logger
    Logger.error("OverviewLive: RPC failed! Reason: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Failed to reset: #{inspect(reason)}")}
  end

  @impl true
  def handle_event("lv:clear-flash", _params, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_event("simulation_pause", _params, socket) do
    send(self(), {:simulation_control, :pause})
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_resume", _params, socket) do
    send(self(), {:simulation_control, :resume})
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_reset", _params, socket) do
    send(self(), {:simulation_control, :reset})
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_set_speed", %{"speed" => speed_str}, socket) do
    case Integer.parse(speed_str) do
      {speed, ""} ->
        send(self(), {:simulation_control, :set_speed, speed})
        {:noreply, socket}
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-950 text-white">
      <!-- Side Navigation with Simulation Controls -->
      <NavMenu.render
        current_path={@current_path}
        simulation_time={@simulation_time}
        simulation_speed={@simulation_speed}
        simulation_paused={@simulation_paused}
      />

      <!-- Main Content -->
      <div class="flex-1 overflow-auto">
        <div class="p-6">
          <!-- Toast Notifications -->
          <%= if @waiting_for_data do %>
            <div
              id="toast-waiting"
              class="fixed top-4 right-4 z-50 bg-blue-600 text-white px-6 py-3 rounded-lg shadow-lg flex items-center gap-3 animate-pulse"
            >
              <span class="text-xl">⏳</span>
              <span>Waiting for data...</span>
            </div>
          <% end %>
          <%= if @flash do %>
            <%= if Phoenix.Flash.get(@flash, :info) do %>
              <div
                id="toast-info"
                phx-hook="AutoDismissToast"
                class="fixed top-4 right-4 z-50 bg-green-600 text-white px-6 py-3 rounded-lg shadow-lg flex items-center gap-3 animate-slide-in-right"
              >
                <span class="text-xl">✓</span>
                <span><%= Phoenix.Flash.get(@flash, :info) %></span>
              </div>
            <% end %>
            <%= if Phoenix.Flash.get(@flash, :error) do %>
              <div
                id="toast-error"
                phx-hook="AutoDismissToast"
                class="fixed top-4 right-4 z-50 bg-red-600 text-white px-6 py-3 rounded-lg shadow-lg flex items-center gap-3 animate-slide-in-right"
              >
                <span class="text-xl">✗</span>
                <span><%= Phoenix.Flash.get(@flash, :error) %></span>
              </div>
            <% end %>
          <% end %>

          <!-- Page Header -->
          <div class="mb-6">
            <h1 class="text-3xl font-bold text-gray-100">Exchange Overview</h1>
            <p class="text-gray-400 text-sm mt-1">Real-time energy exchange metrics and performance</p>
          </div>

          <!-- Stats Cards -->
          <.live_component
            module={StatsCards}
            id="stats-cards"
            stats={@stats}
          />

          <!-- Financial Summary -->
          <.live_component
            module={FinancialSummary}
            id="financial-summary"
            stats={@stats}
          />

          <!-- Cumulative Savings Chart -->
          <%= if length(@overview[:savings_history] || []) > 0 do %>
            <div class="mt-6">
              <h2 class="text-2xl font-bold mb-4 text-gray-100">Financial Performance Over Time</h2>
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-gray-300 mb-4">Cumulative Savings & Commission</h3>
                <div
                  id="savings-history-chart"
                  phx-hook="SavingsHistoryChart"
                  phx-update="ignore"
                  data-savings-history={Jason.encode!(@overview.savings_history)}
                >
                </div>
              </div>
            </div>
          <% end %>

          <!-- Analytics Charts -->
          <div class="mt-6">
            <h2 class="text-2xl font-bold mb-4 text-gray-100">System Analytics</h2>

            <div class="grid grid-cols-2 gap-6">
                <!-- Production vs Consumption Chart -->
                <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-gray-300 mb-4">Production vs Consumption</h3>
                  <div
                    id="aggregate-power-chart"
                    phx-hook="AggregatePowerChart"
                    phx-update="ignore"
                    data-history={Jason.encode!(@aggregate_history)}
                  >
                  </div>
                </div>

                <!-- Regional Energy Balance Chart -->
                <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                  <h3 class="text-lg font-semibold text-gray-300 mb-4">Regional Energy Balance</h3>
                  <div
                    id="regional-balance-chart"
                    phx-hook="RegionalBalanceChart"
                    phx-update="ignore"
                    data-history={Jason.encode!(@aggregate_history)}
                  >
                  </div>
                </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp parse_stats(overview_data) when is_map(overview_data) do
    # Handle both atom keys (from OverviewAggregator) and string keys (from WAMP RPC)
    %{
      homes: Map.get(overview_data, :total_homes, Map.get(overview_data, "total_homes", 0)),
      connected_homes: Map.get(overview_data, :connected_homes_count, Map.get(overview_data, "connected_homes_count", 0)),
      total_production_kw: Map.get(overview_data, :total_production_kw, Map.get(overview_data, "total_production_kw", 0.0)),
      total_consumption_kw: Map.get(overview_data, :total_consumption_kw, Map.get(overview_data, "total_consumption_kw", 0.0)),
      total_energy_bought_kwh: Map.get(overview_data, :total_energy_bought_kwh, Map.get(overview_data, "total_energy_bought_kwh", 0.0)),
      total_energy_sold_kwh: Map.get(overview_data, :total_energy_sold_kwh, Map.get(overview_data, "total_energy_sold_kwh", 0.0)),
      total_cost_paid: Map.get(overview_data, :total_cost_paid, Map.get(overview_data, "total_cost_paid", 0.0)),
      total_revenue_received: Map.get(overview_data, :total_revenue_received, Map.get(overview_data, "total_revenue_received", 0.0)),
      avg_battery_percent: Map.get(overview_data, :avg_battery_percent, Map.get(overview_data, "avg_battery_percent", 0.0)),
      contract_switches: Map.get(overview_data, :total_contract_switches, Map.get(overview_data, "contract_switches", 0)),
      cortexiq_total_savings: Map.get(overview_data, :cortexiq_total_savings, Map.get(overview_data, "cortexiq_total_savings", 0.0)),
      cortexiq_total_commission: Map.get(overview_data, :cortexiq_total_commission, Map.get(overview_data, "cortexiq_total_commission", 0.0)),
      cortexiq_net_savings: Map.get(overview_data, :cortexiq_net_savings, Map.get(overview_data, "cortexiq_net_savings", 0.0))
    }
  end

  defp parse_stats(_), do: default_stats()

  defp default_stats do
    %{
      homes: 0,
      connected_homes: 0,
      total_production_kw: 0.0,
      total_consumption_kw: 0.0,
      total_energy_bought_kwh: 0.0,
      total_energy_sold_kwh: 0.0,
      total_cost_paid: 0.0,
      total_revenue_received: 0.0,
      avg_battery_percent: 0.0,
      contract_switches: 0,
      cortexiq_total_savings: 0.0,
      cortexiq_total_commission: 0.0,
      cortexiq_net_savings: 0.0
    }
  end

  defp format_with_unit_prefix(value) when is_number(value) do
    abs_value = abs(value)
    sign = if value < 0, do: "-", else: ""

    cond do
      abs_value >= 1.0e24 -> "#{sign}#{Float.round(abs_value / 1.0e24, 1)}Y"  # yotta
      abs_value >= 1.0e21 -> "#{sign}#{Float.round(abs_value / 1.0e21, 1)}Z"  # zetta
      abs_value >= 1.0e18 -> "#{sign}#{Float.round(abs_value / 1.0e18, 1)}E"  # exa
      abs_value >= 1.0e15 -> "#{sign}#{Float.round(abs_value / 1.0e15, 1)}P"  # peta
      abs_value >= 1.0e12 -> "#{sign}#{Float.round(abs_value / 1.0e12, 1)}T"  # tera
      abs_value >= 1.0e9 -> "#{sign}#{Float.round(abs_value / 1.0e9, 1)}G"    # giga
      abs_value >= 1.0e6 -> "#{sign}#{Float.round(abs_value / 1.0e6, 1)}M"    # mega
      abs_value >= 1.0e3 -> "#{sign}#{Float.round(abs_value / 1.0e3, 1)}k"    # kilo
      abs_value >= 10.0 -> "#{sign}#{trunc(abs_value)}"                       # No decimal for values >= 10 (use trunc for integers)
      abs_value > 0 -> "#{sign}#{Float.round(abs_value * 1.0, 1)}"           # 1 decimal for small values (force float)
      true -> "0"
    end
  end

  defp format_with_unit_prefix(_), do: "0"
end
