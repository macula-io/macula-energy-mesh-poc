defmodule CortexIqDashboardWeb.HomesLive do
  @moduledoc """
  Homes page LiveView - Interactive map showing all connected homes.

  Displays:
  - Zoomable map with all homes plotted geographically
  - Search functionality to filter/highlight homes on map
  - Individual home details on marker click
  - Real-time energy production, consumption, battery status
  """
  use CortexIqDashboardWeb, :live_view

  alias CortexIqDashboard.QueryClient
  alias CortexIqDashboard.SimulationClient
  alias CortexIqDashboardWeb.Components.NavMenu
  alias CortexIqDashboardSchemas.HomeStatus

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.info("HomesLive: mount() called, connected: #{connected?(socket)}")

    # Subscribe to simulation time and control events only
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Logger.info("HomesLive: Subscribed to simulation time and control events")
    end

    # Load ALL homes for the map (request large page size)
    Logger.info("HomesLive: Loading all homes via WAMP RPC...")
    homes = case QueryClient.get_homes(page: 1, per_page: 1000) do
      {:ok, result} ->
        Logger.info("HomesLive: get_homes() returned #{inspect(length(Map.get(result, "homes", [])))} homes")
        Map.get(result, "homes", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load homes: #{inspect(reason)}")
        []
    end

    Logger.info("HomesLive: Loaded #{length(homes)} homes for map")

    {:ok,
     socket
     |> assign(:current_path, "/homes")
     |> assign(:view_mode, :map)  # :map | :detail
     |> assign(:homes, homes)
     |> assign(:search_query, "")
     |> assign(:selected_home, nil)
     |> assign(:selected_home_data, nil)
     |> assign(:home_history, [])
     |> assign(:home_trades, [])
     |> assign(:simulation_time, nil)
     |> assign(:simulation_speed, 105_120)
     |> assign(:simulation_paused, false)}
  end

  # Real-time updates for simulation time
  @impl true
  def handle_info({:time_advanced, kwargs}, socket) do
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
  def handle_info({:simulation_control, :pause}, socket), do: send_simulation_command(socket, :pause)

  @impl true
  def handle_info({:simulation_control, :resume}, socket), do: send_simulation_command(socket, :resume)

  @impl true
  def handle_info({:simulation_control, :reset}, socket), do: send_simulation_command(socket, :reset)

  @impl true
  def handle_info({:simulation_control, :set_speed, speed}, socket), do: send_simulation_command(socket, {:set_speed, speed})

  @impl true
  def handle_info({:reset_simulation}, socket) do
    require Logger
    Logger.info("HomesLive: Received reset_simulation, reloading homes")

    # Reload all homes after reset
    homes = case QueryClient.get_homes(page: 1, per_page: 1000) do
      {:ok, result} -> Map.get(result, "homes", [])
      {:error, _} -> []
    end

    {:noreply,
     socket
     |> assign(:view_mode, :map)
     |> assign(:homes, homes)
     |> assign(:search_query, "")
     |> assign(:selected_home, nil)
     |> assign(:selected_home_data, nil)
     |> assign(:home_history, [])
     |> assign(:home_trades, [])}
  end

  @impl true
  def handle_event("select_home", %{"home_id" => home_id}, socket) do
    require Logger
    Logger.info("HomesLive: Selecting home #{home_id}")

    # Load full home data, history, and trades via WAMP RPC
    home_data = case QueryClient.get_home(home_id) do
      {:ok, result} ->
        Logger.info("HomesLive: get_home() succeeded")
        Map.get(result, "home")
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load home data: #{inspect(reason)}")
        nil
    end

    history = case QueryClient.get_home_history(home_id, 24) do
      {:ok, result} ->
        Logger.info("HomesLive: get_home_history() returned #{inspect(length(Map.get(result, "events", [])))} events")
        Map.get(result, "events", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load home history: #{inspect(reason)}")
        []
    end

    trades = case QueryClient.get_home_trades(home_id, 24) do
      {:ok, result} ->
        Logger.info("HomesLive: get_home_trades() returned #{inspect(length(Map.get(result, "trades", [])))} trades")
        Map.get(result, "trades", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load home trades: #{inspect(reason)}")
        []
    end

    {:noreply,
     socket
     |> assign(:view_mode, :detail)
     |> assign(:selected_home, home_id)
     |> assign(:selected_home_data, home_data)
     |> assign(:home_history, history)
     |> assign(:home_trades, trades)}
  end

  @impl true
  def handle_event("back_to_map", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :map)
     |> assign(:selected_home, nil)
     |> assign(:selected_home_data, nil)
     |> assign(:home_history, [])
     |> assign(:home_trades, [])}
  end

  @impl true
  def handle_event("search_homes", %{"query" => query}, socket) do
    require Logger
    Logger.info("HomesLive: Searching for '#{query}'")

    # Push search to JavaScript hook for client-side filtering
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> push_event("filter_homes", %{query: query})}
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
      <div class="flex-1 overflow-hidden">
        <%= case @view_mode do %>
          <% :detail -> %>
            <%= render_home_detail(assigns) %>
          <% _ -> %>
            <%= render_map_view(assigns) %>
        <% end %>
      </div>
    </div>
    """
  end

  # Render map view with search overlay
  defp render_map_view(assigns) do
    # Serialize homes to JSON for the JavaScript hook
    homes_json = Jason.encode!(assigns.homes)

    assigns = assign(assigns, :homes_json, homes_json)

    ~H"""
    <div class="relative w-full h-full">
      <!-- Map Container -->
      <div
        id="homes-map"
        class="w-full h-full"
        style="min-height: 600px;"
        phx-hook="HomesMap"
        phx-update="ignore"
        data-homes={@homes_json}
      >
      </div>

      <!-- Search Overlay (top-left corner) -->
      <div class="absolute top-4 left-4 z-[1000] w-96">
        <div class="bg-gray-900/95 backdrop-blur rounded-lg shadow-2xl border border-gray-700 p-4">
          <h2 class="text-lg font-bold text-gray-100 mb-3">Find Homes</h2>
          <input
            type="text"
            placeholder="Search by name, location, or meter EAN..."
            value={@search_query}
            phx-keyup="search_homes"
            phx-debounce="300"
            name="query"
            class="w-full px-4 py-2 bg-gray-800 border border-gray-600 rounded-lg text-gray-100 placeholder-gray-500 focus:border-blue-500 focus:outline-none"
            autocomplete="off"
          />
          <div class="mt-2 text-xs text-gray-400">
            <%= length(@homes) %> homes online
          </div>
        </div>
      </div>

      <!-- Legend (bottom-right corner) -->
      <div class="absolute bottom-4 right-4 z-[1000]">
        <div class="bg-gray-900/95 backdrop-blur rounded-lg shadow-2xl border border-gray-700 p-3">
          <div class="text-xs font-bold text-gray-300 mb-2">Status</div>
          <div class="space-y-1 text-xs">
            <div class="flex items-center gap-2">
              <div class="w-3 h-3 rounded-full bg-green-500"></div>
              <span class="text-gray-400">Producing</span>
            </div>
            <div class="flex items-center gap-2">
              <div class="w-3 h-3 rounded-full bg-red-500"></div>
              <span class="text-gray-400">Consuming</span>
            </div>
            <div class="flex items-center gap-2">
              <div class="w-3 h-3 rounded-full bg-yellow-500"></div>
              <span class="text-gray-400">Balanced</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Render home detail view (reuse from previous implementation)
  defp render_home_detail(assigns) do
    ~H"""
    <div class="p-6 overflow-auto h-full">
      <div class="space-y-6">
        <!-- Header with Back Button -->
        <div class="flex items-center gap-4 mb-6">
          <button
            phx-click="back_to_map"
            class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg transition-colors border border-gray-600"
          >
            ← Back to Map
          </button>
          <div>
            <h1 class="text-3xl font-bold text-gray-100"><%= get_in(@selected_home_data, ["name"]) || "Home Details" %></h1>
            <p class="text-gray-400 text-sm mt-1 font-mono"><%= get_in(@selected_home_data, ["meter_ean"]) || @selected_home %></p>
          </div>
        </div>

        <%= if @selected_home_data do %>
          <!-- Property Information -->
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h2 class="text-xl font-bold text-gray-100 mb-4">Property Information</h2>
              <div class="space-y-3">
                <div class="flex justify-between items-start">
                  <span class="text-gray-400 text-sm">Home ID</span>
                  <span class="text-gray-100 text-sm font-mono text-right"><%= get_in(@selected_home_data, ["home_id"]) %></span>
                </div>
                <div class="flex justify-between items-start">
                  <span class="text-gray-400 text-sm">Location</span>
                  <span class="text-gray-100 text-sm text-right"><%= get_in(@selected_home_data, ["location"]) || "Unknown" %></span>
                </div>
                <%= if get_in(@selected_home_data, ["latitude"]) && get_in(@selected_home_data, ["longitude"]) do %>
                  <div class="flex justify-between items-start">
                    <span class="text-gray-400 text-sm">Coordinates</span>
                    <span class="text-gray-100 text-sm text-right font-mono">
                      <%= Float.round(get_in(@selected_home_data, ["latitude"]), 4) %>,
                      <%= Float.round(get_in(@selected_home_data, ["longitude"]), 4) %>
                    </span>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Equipment -->
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h2 class="text-xl font-bold text-gray-100 mb-4">Equipment</h2>
              <div class="space-y-4">
                <div class="flex items-center gap-4">
                  <div class="w-12 h-12 bg-yellow-500/20 rounded-lg flex items-center justify-center">
                    <svg class="w-6 h-6 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
                    </svg>
                  </div>
                  <div class="flex-1">
                    <div class="text-gray-400 text-sm">Solar Capacity</div>
                    <div class="text-gray-100 text-lg font-semibold"><%= Float.round(get_in(@selected_home_data, ["solar_capacity_kw"]) || 0.0, 1) %> kW</div>
                  </div>
                </div>

                <div class="flex items-center gap-4">
                  <div class="w-12 h-12 bg-green-500/20 rounded-lg flex items-center justify-center">
                    <svg class="w-6 h-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
                    </svg>
                  </div>
                  <div class="flex-1">
                    <div class="text-gray-400 text-sm">Battery Capacity</div>
                    <div class="text-gray-100 text-lg font-semibold"><%= Float.round(get_in(@selected_home_data, ["battery_capacity_kwh"]) || 0.0, 1) %> kWh</div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Real-Time Metrics -->
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <h2 class="text-xl font-bold text-gray-100 mb-6">Real-Time Metrics</h2>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <!-- Production -->
              <div class="bg-gray-900 rounded-lg p-4 border border-gray-700">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-gray-400 text-sm">Production</span>
                  <svg class="w-5 h-5 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
                  </svg>
                </div>
                <div class="text-2xl font-bold text-yellow-400">
                  <%= format_power(get_in(@selected_home_data, ["production_kw"]) || 0.0) %>
                </div>
              </div>

              <!-- Consumption -->
              <div class="bg-gray-900 rounded-lg p-4 border border-gray-700">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-gray-400 text-sm">Consumption</span>
                  <svg class="w-5 h-5 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                  </svg>
                </div>
                <div class="text-2xl font-bold text-red-400">
                  <%= format_power(get_in(@selected_home_data, ["consumption_kw"]) || 0.0) %>
                </div>
              </div>

              <!-- Battery -->
              <div class="bg-gray-900 rounded-lg p-4 border border-gray-700">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-gray-400 text-sm">Battery</span>
                  <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
                  </svg>
                </div>
                <div class="text-2xl font-bold text-green-400">
                  <%= Float.round(get_in(@selected_home_data, ["battery_percent"]) || 0.0, 1) %>%
                </div>
                <div class="mt-2 w-full bg-gray-700 rounded-full h-2">
                  <div class={"rounded-full h-2 transition-all duration-300 #{battery_color(get_in(@selected_home_data, ["battery_percent"]) || 0.0)}"} style={"width: #{get_in(@selected_home_data, ["battery_percent"]) || 0}%"}></div>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <p class="text-gray-400">Loading home details...</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp battery_color(percent) when percent > 75, do: "bg-green-500"
  defp battery_color(percent) when percent > 50, do: "bg-blue-500"
  defp battery_color(percent) when percent > 25, do: "bg-yellow-500"
  defp battery_color(_), do: "bg-red-500"

  defp format_power(kw) when is_float(kw) or is_number(kw) do
    cond do
      kw >= 1.0 -> "#{Float.round(kw, 2)} kW"
      kw >= 0.001 -> "#{Float.round(kw * 1000, 0)} W"
      true -> "0 W"
    end
  end

  defp format_power(_), do: "0 W"

  # Simulation control helpers

  defp send_simulation_command(socket, :pause) do
    Task.start(fn -> SimulationClient.pause_simulation() end)
    {:noreply, socket}
  end

  defp send_simulation_command(socket, :resume) do
    Task.start(fn -> SimulationClient.resume_simulation() end)
    {:noreply, socket}
  end

  defp send_simulation_command(socket, :reset) do
    Task.start(fn -> SimulationClient.reset_simulation() end)
    {:noreply, socket}
  end

  defp send_simulation_command(socket, {:set_speed, speed}) do
    Task.start(fn -> SimulationClient.set_simulation_speed(speed) end)
    {:noreply, socket}
  end
end
