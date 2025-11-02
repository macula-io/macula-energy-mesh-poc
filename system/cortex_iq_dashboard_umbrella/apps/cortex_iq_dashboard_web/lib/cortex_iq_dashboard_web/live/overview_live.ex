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

    # Subscribe to overview updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "view:overview")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      # Subscribe to simulation time broadcasts directly
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
      Logger.info("OverviewLive: Subscribed to overview updates and simulation time")
    end

    # Load initial state from OverviewAggregator (in-memory, event-sourced)
    overview = OverviewAggregator.get_state()

    # Get additional overview data via WAMP RPC
    # Get overview data with timeout - don't block mount if RPC is slow
    task = Task.async(fn -> QueryClient.get_overview() end)
    overview_data =
      case Task.yield(task, 1000) || Task.shutdown(task) do
        {:ok, {:ok, data}} -> data
        {:ok, {:error, reason}} ->
          Logger.warning("Failed to get overview data: #{inspect(reason)}")
          %{}
        nil ->
          Logger.warning("Timeout getting overview data")
          %{}
      end

    {:ok,
     socket
     |> assign(:current_path, "/")
     |> assign(:overview, overview)
     |> assign(:simulation_time, Map.get(overview_data, "simulation_time"))
     |> assign(:simulation_speed, Map.get(overview_data, "simulation_speed", 105_120))
     |> assign(:simulation_paused, Map.get(overview_data, "simulation_paused", false))
     |> assign(:stats, parse_stats(overview))  # Use in-memory data, not stale DB data
     |> assign(:aggregate_history, Map.get(overview_data, "aggregate_history", []))}
  end

  @impl true
  def handle_info(:view_updated, socket) do
    require Logger
    Logger.info("OverviewLive: View updated, reloading from OverviewAggregator")

    # Reload from in-memory aggregator
    overview = OverviewAggregator.get_state()
    Logger.info("OverviewLive: Overview state - total_homes=#{overview.total_homes}, total_production=#{overview.total_production_kw}, total_consumption=#{overview.total_consumption_kw}")

    # Use in-memory aggregator data directly (NO database query!)
    # parse_stats expects the same shape as the WAMP RPC response, so pass overview directly
    {:noreply,
     socket
     |> assign(:overview, overview)
     |> assign(:stats, parse_stats(overview))}
  end

  @impl true
  def handle_info({:time_advanced, kwargs}, socket) do
    # Update simulation time from direct broadcast
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
          <%= if length(@aggregate_history) > 5 do %>
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
          <% end %>
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
end
