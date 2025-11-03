defmodule CortexIqDashboardWeb.HomesLive do
  @moduledoc """
  Homes page LiveView - Manage and monitor all connected homes.

  Displays:
  - List of all homes with real-time status
  - Search and filtering capabilities
  - Individual home details on click
  - Energy production, consumption, battery status
  - Contract information and balance
  """
  use CortexIqDashboardWeb, :live_view

  alias CortexIqDashboard.QueryClient
  alias CortexIqDashboard.SimulationClient
  alias CortexIqDashboardWeb.Components.NavMenu
  alias CortexIqDashboardSchemas.HomeStatus

  @impl true
  def mount(_params, session, socket) do
    require Logger
    Logger.info("HomesLive: mount() called, connected: #{connected?(socket)}")

    # Subscribe to simulation time and control events only
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Logger.info("HomesLive: Subscribed to simulation time and control events")
    end

    # Load locations for the browse interface
    Logger.info("HomesLive: Loading locations via WAMP RPC...")
    locations = case QueryClient.get_locations() do
      {:ok, result} ->
        Logger.info("HomesLive: get_locations() returned #{inspect(length(Map.get(result, "locations", [])))} locations")
        Map.get(result, "locations", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load locations: #{inspect(reason)}")
        []
    end

    Logger.info("HomesLive: Loaded #{length(locations)} locations")

    # Get recent homes from session (last 5 viewed)
    recent_home_ids = Map.get(session, "recent_homes", [])
    Logger.info("HomesLive: Recent home IDs from session: #{inspect(recent_home_ids)}")

    {:ok,
     socket
     |> assign(:current_path, "/homes")
     |> assign(:view_mode, :search)  # :search | :browse | :detail
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:locations, locations)
     |> assign(:selected_location, nil)
     |> assign(:location_homes, [])
     |> assign(:recent_homes, recent_home_ids)
     |> assign(:selected_home, nil)
     |> assign(:selected_home_data, nil)  # Full home data when viewing detail
     |> assign(:home_history, [])  # Energy events for charts
     |> assign(:home_trades, [])  # Trade data for financial charts
     |> assign(:simulation_time, nil)
     |> assign(:simulation_speed, 105_120)
     |> assign(:simulation_paused, false)}
  end

  # Real-time updates are now handled differently:
  # - When viewing detail, we'll subscribe to specific home updates
  # - Search/browse views don't need real-time updates (just for navigation)

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
    Logger.info("HomesLive: Received reset_simulation, clearing state")

    # Clear selected home if viewing detail
    # Locations will be reloaded on next search/browse

    {:noreply,
     socket
     |> assign(:view_mode, :search)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_location, nil)
     |> assign(:location_homes, [])
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

    # Add to recent homes (keep last 5)
    recent_homes = [home_id | Enum.reject(socket.assigns.recent_homes, &(&1 == home_id))] |> Enum.take(5)

    {:noreply,
     socket
     |> assign(:view_mode, :detail)
     |> assign(:selected_home, home_id)
     |> assign(:selected_home_data, home_data)
     |> assign(:home_history, history)
     |> assign(:home_trades, trades)
     |> assign(:recent_homes, recent_homes)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :search)
     |> assign(:selected_home, nil)
     |> assign(:selected_home_data, nil)
     |> assign(:home_history, [])
     |> assign(:home_trades, [])}
  end

  @impl true
  def handle_event("search_homes", %{"query" => query}, socket) when byte_size(query) >= 2 do
    require Logger
    Logger.info("HomesLive: Searching for '#{query}'")

    # Call search RPC
    search_results = case QueryClient.search_homes(query, 10) do
      {:ok, result} ->
        Logger.info("HomesLive: search_homes() returned #{inspect(length(Map.get(result, "homes", [])))} results")
        Map.get(result, "homes", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Search failed: #{inspect(reason)}")
        []
    end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, search_results)}
  end

  @impl true
  def handle_event("search_homes", %{"query" => query}, socket) do
    # Query too short, clear results
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("select_location", %{"location" => location}, socket) do
    require Logger
    Logger.info("HomesLive: Selecting location '#{location}'")

    # Load homes for this location
    location_homes = case QueryClient.get_homes_by_location(location) do
      {:ok, result} ->
        Logger.info("HomesLive: get_homes_by_location() returned #{inspect(length(Map.get(result, "homes", [])))} homes")
        Map.get(result, "homes", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load homes for location: #{inspect(reason)}")
        []
    end

    {:noreply,
     socket
     |> assign(:view_mode, :browse)
     |> assign(:selected_location, location)
     |> assign(:location_homes, location_homes)}
  end

  @impl true
  def handle_event("clear_location", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :search)
     |> assign(:selected_location, nil)
     |> assign(:location_homes, [])}
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
          <%= case @view_mode do %>
            <% :detail -> %>
              <%= render_home_detail(assigns) %>
            <% :browse -> %>
              <%= render_location_browse(assigns) %>
            <% _ -> %>
              <%= render_search_interface(assigns) %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Render search interface (main entry point)
  defp render_search_interface(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Page Header -->
      <div class="mb-6">
        <h1 class="text-3xl font-bold text-gray-100">Find a Home</h1>
        <p class="text-gray-400 text-sm mt-1">Search by meter EAN or home ID, or browse by location</p>
      </div>

      <!-- Search Bar -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <label class="block text-sm font-medium text-gray-300 mb-2">Search Homes</label>
        <input
          type="text"
          placeholder="Type meter EAN or home ID..."
          value={@search_query}
          phx-keyup="search_homes"
          phx-debounce="300"
          name="query"
          class="w-full px-4 py-3 bg-gray-900 border border-gray-600 rounded-lg text-gray-100 placeholder-gray-500 focus:border-blue-500 focus:outline-none text-lg"
        />

        <!-- Search Results (Autocomplete) -->
        <%= if length(@search_results) > 0 do %>
          <div class="mt-4 space-y-2">
            <p class="text-sm text-gray-400">Results:</p>
            <%= for result <- @search_results do %>
              <button
                phx-click="select_home"
                phx-value-home_id={Map.get(result, "home_id")}
                class="w-full p-4 bg-gray-900 hover:bg-gray-700 border border-gray-600 rounded-lg transition-colors text-left"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <div class="text-white font-medium"><%= Map.get(result, "name", "Unknown Home") %></div>
                    <div class="text-sm text-gray-400"><%= Map.get(result, "location", "Unknown Location") %></div>
                  </div>
                  <div class="text-sm font-mono text-gray-500"><%= Map.get(result, "meter_ean") %></div>
                </div>
              </button>
            <% end %>
          </div>
        <% end %>

        <%= if byte_size(@search_query) >= 2 && length(@search_results) == 0 do %>
          <div class="mt-4 p-4 bg-gray-900 border border-gray-600 rounded-lg">
            <p class="text-gray-400 text-sm">No homes found matching "<%= @search_query %>"</p>
          </div>
        <% end %>
      </div>

      <!-- Location Browser -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <h2 class="text-xl font-bold text-gray-100 mb-4">Browse by Location</h2>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          <%= for location <- @locations do %>
            <button
              phx-click="select_location"
              phx-value-location={Map.get(location, "location")}
              class="p-4 bg-gray-900 hover:bg-gray-700 border border-gray-600 rounded-lg transition-colors text-left"
            >
              <div class="text-white font-medium"><%= Map.get(location, "location") %></div>
              <div class="text-sm text-gray-400"><%= Map.get(location, "home_count") %> homes</div>
            </button>
          <% end %>
        </div>
      </div>

      <!-- Recent Homes (if any) -->
      <%= if length(@recent_homes) > 0 do %>
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 class="text-xl font-bold text-gray-100 mb-4">Recently Viewed</h2>
          <div class="flex flex-wrap gap-2">
            <%= for home_id <- @recent_homes do %>
              <button
                phx-click="select_home"
                phx-value-home_id={home_id}
                class="px-4 py-2 bg-gray-900 hover:bg-gray-700 border border-gray-600 rounded-lg transition-colors text-sm text-gray-300"
              >
                <%= String.slice(home_id, 0..7) %>...
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Render location browse view (list of homes in selected city)
  defp render_location_browse(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header with Back Button -->
      <div class="flex items-center gap-4 mb-6">
        <button
          phx-click="clear_location"
          class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg transition-colors"
        >
          ← Back to Search
        </button>
        <div>
          <h1 class="text-3xl font-bold text-gray-100">Homes in <%= @selected_location %></h1>
          <p class="text-gray-400 text-sm mt-1"><%= length(@location_homes) %> homes found</p>
        </div>
      </div>

      <!-- Homes Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for home <- @location_homes do %>
          <button
            phx-click="select_home"
            phx-value-home_id={Map.get(home, "home_id")}
            class="p-6 bg-gray-800 hover:bg-gray-700 border border-gray-600 rounded-lg transition-colors text-left"
          >
            <div class="space-y-2">
              <div class="text-lg font-bold text-white"><%= format_family_name(home) %></div>
              <div class="text-sm text-gray-400">
                <span class="font-mono"><%= Map.get(home, "meter_ean", "N/A") %></span>
              </div>
              <%= if Map.get(home, "provider_id") do %>
                <div class="text-xs text-yellow-400">
                  Provider: <%= get_provider_name(Map.get(home, "provider_id")) %>
                </div>
              <% end %>
            </div>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Render home detail view
  defp render_home_detail(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header with Back Button -->
      <div class="flex items-center gap-4 mb-6">
        <button
          phx-click="back_to_list"
          class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg transition-colors border border-gray-600"
        >
          ← Back to Search
        </button>
        <div>
          <h1 class="text-3xl font-bold text-gray-100"><%= get_in(@selected_home_data, ["name"]) || "Home Details" %></h1>
          <p class="text-gray-400 text-sm mt-1 font-mono"><%= get_in(@selected_home_data, ["meter_ean"]) || @selected_home %></p>
        </div>
      </div>

      <%= if @selected_home_data do %>
        <!-- Static Information Section -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Left Column: Identification & Location -->
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <h2 class="text-xl font-bold text-gray-100 mb-4">Property Information</h2>
            <div class="space-y-3">
              <div class="flex justify-between items-start">
                <span class="text-gray-400 text-sm">Home ID</span>
                <span class="text-gray-100 text-sm font-mono text-right"><%= get_in(@selected_home_data, ["home_id"]) %></span>
              </div>
              <div class="flex justify-between items-start">
                <span class="text-gray-400 text-sm">Meter EAN</span>
                <span class="text-gray-100 text-sm font-mono text-right"><%= get_in(@selected_home_data, ["meter_ean"]) || "N/A" %></span>
              </div>
              <div class="border-t border-gray-700 my-2"></div>
              <div class="flex justify-between items-start">
                <span class="text-gray-400 text-sm">Location</span>
                <span class="text-gray-100 text-sm text-right"><%= get_in(@selected_home_data, ["location"]) || "Unknown" %></span>
              </div>
              <div class="flex justify-between items-start">
                <span class="text-gray-400 text-sm">Address</span>
                <div class="text-gray-100 text-sm text-right">
                  <div><%= get_in(@selected_home_data, ["street"]) || "N/A" %></div>
                  <div><%= get_in(@selected_home_data, ["postal_code"]) || "" %> <%= get_in(@selected_home_data, ["location"]) || "" %></div>
                </div>
              </div>
              <div class="flex justify-between items-start">
                <span class="text-gray-400 text-sm">Region</span>
                <span class="text-gray-100 text-sm text-right capitalize"><%= get_in(@selected_home_data, ["region"]) || "N/A" %></span>
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
              <div class="border-t border-gray-700 my-2"></div>
              <div class="flex justify-between items-start">
                <span class="text-gray-400 text-sm">IoT Provider</span>
                <span class="text-gray-100 text-sm text-right"><%= format_iot_provider(get_in(@selected_home_data, ["iot_provider"])) %></span>
              </div>
            </div>
          </div>

          <!-- Right Column: Equipment Specs -->
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <h2 class="text-xl font-bold text-gray-100 mb-4">Equipment</h2>
            <div class="space-y-4">
              <!-- Solar Panel -->
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

              <!-- Battery -->
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

        <!-- Real-Time Metrics Section -->
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 class="text-xl font-bold text-gray-100 mb-6">Real-Time Metrics</h2>

          <!-- Status Badge -->
          <div class="mb-6">
            <span class={"px-3 py-1 rounded-full text-sm font-medium #{status_color(get_in(@selected_home_data, ["status"]))}"}>
              <%= format_status(get_in(@selected_home_data, ["status"])) %>
            </span>
          </div>

          <!-- Energy Flow Grid -->
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
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
              <div class="text-xs text-gray-500 mt-1">
                <%= Float.round((get_in(@selected_home_data, ["battery_percent"]) || 0.0) * (get_in(@selected_home_data, ["battery_capacity_kwh"]) || 0.0) / 100.0, 2) %> kWh
              </div>
              <!-- Battery Bar -->
              <div class="mt-2 w-full bg-gray-700 rounded-full h-2">
                <div class={"rounded-full h-2 transition-all duration-300 #{battery_color(get_in(@selected_home_data, ["battery_percent"]) || 0.0)}"} style={"width: #{get_in(@selected_home_data, ["battery_percent"]) || 0}%"}></div>
              </div>
            </div>
          </div>

          <!-- Provider & Contract Info -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="bg-gray-900 rounded-lg p-4 border border-gray-700">
              <div class="text-gray-400 text-sm mb-1">Current Provider</div>
              <div class="text-xl font-bold text-blue-400">
                <%= get_provider_name(get_in(@selected_home_data, ["provider_id"])) %>
              </div>
              <%= if get_in(@selected_home_data, ["contract_id"]) do %>
                <div class="text-xs text-gray-500 mt-2 font-mono">
                  Contract: <%= String.slice(get_in(@selected_home_data, ["contract_id"]), 0..7) %>...
                </div>
                <%= if get_in(@selected_home_data, ["contract_expires_at"]) do %>
                  <div class="text-xs text-gray-500">
                    Expires: <%= Calendar.strftime(get_in(@selected_home_data, ["contract_expires_at"]), "%b %d, %Y") %>
                  </div>
                <% end %>
              <% end %>
            </div>

            <div class="bg-gray-900 rounded-lg p-4 border border-gray-700">
              <div class="text-gray-400 text-sm mb-1">Net Energy Balance</div>
              <div class="text-xl font-bold" class={if (get_in(@selected_home_data, ["net_balance_kwh"]) || 0.0) > 0, do: "text-red-400", else: "text-green-400"}>
                <%= format_energy(abs(get_in(@selected_home_data, ["net_balance_kwh"]) || 0.0)) %>
              </div>
              <div class="text-xs text-gray-500 mt-1">
                <%= if (get_in(@selected_home_data, ["net_balance_kwh"]) || 0.0) > 0 do %>
                  Net import from grid
                <% else %>
                  Net export to grid
                <% end %>
              </div>
              <%= if get_in(@selected_home_data, ["net_cost"]) do %>
                <div class="text-xs text-gray-500 mt-2">
                  Cost: €<%= Float.round(get_in(@selected_home_data, ["net_cost"]) || 0.0, 2) %>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Charts Section (Placeholder) -->
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 class="text-xl font-bold text-gray-100 mb-4">Energy History</h2>
          <p class="text-gray-400 text-sm">Charts coming soon...</p>
          <p class="text-xs text-gray-500 mt-1">
            <%= length(@home_history) %> historical events loaded,
            <%= length(@home_trades) %> trades loaded
          </p>
        </div>
      <% else %>
        <!-- Loading state or error -->
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <p class="text-gray-400">Loading home details...</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper Functions
  # (Filtering and sorting now handled by cortex_iq_queries via WAMP RPC)

  defp get_provider_name("provider_a"), do: "Essent"
  defp get_provider_name("provider_b"), do: "Eneco"
  defp get_provider_name("provider_c"), do: "Vattenfall"
  defp get_provider_name("provider_d"), do: "Greenchoice"
  defp get_provider_name("provider_e"), do: "Budget Energie"
  defp get_provider_name(_), do: "Unknown"

  defp format_family_name(home) do
    name = Map.get(home, "name")
    location = Map.get(home, "location", "Unknown")

    cond do
      # If name is set and not a UUID, use it
      name && String.length(name) > 0 && !String.starts_with?(name, "019") ->
        name

      # Generate friendly name from location
      location != "Unknown" ->
        "#{location} Home"

      # Fallback
      true ->
        "Home"
    end
  end

  defp format_iot_provider("home_connect"), do: "Home Connect"
  defp format_iot_provider("smartthings"), do: "SmartThings"
  defp format_iot_provider("home_assistant"), do: "Home Assistant"
  defp format_iot_provider("homekit"), do: "HomeKit"
  defp format_iot_provider("alexa"), do: "Alexa"
  defp format_iot_provider(nil), do: "None"
  defp format_iot_provider(""), do: "None"
  defp format_iot_provider(provider) when is_binary(provider), do: provider
  defp format_iot_provider(_), do: "None"

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

  defp format_energy(kwh) when is_float(kwh) or is_number(kwh) do
    cond do
      kwh >= 1000.0 -> "#{Float.round(kwh / 1000.0, 2)} MWh"
      kwh >= 1.0 -> "#{Float.round(kwh, 2)} kWh"
      true -> "#{Float.round(kwh * 1000, 0)} Wh"
    end
  end

  defp format_energy(_), do: "0 kWh"

  defp format_status(status) when is_integer(status) do
    status
    |> HomeStatus.highest()
    |> format_status_atom()
  end

  defp format_status(_), do: "Unknown"

  # Convert status atoms to readable strings
  defp format_status_atom(:connected), do: "Connected"
  defp format_status_atom(:disconnected), do: "Disconnected"
  defp format_status_atom(:initialized), do: "Initialized"
  defp format_status_atom(:reserved), do: "Reserved"
  defp format_status_atom(atom) when is_atom(atom), do: atom |> Atom.to_string() |> String.capitalize()
  defp format_status_atom(_), do: "Unknown"

  defp status_color(status) when is_integer(status) do
    cond do
      HomeStatus.is_connected?(status) -> "bg-green-600 text-green-100"
      HomeStatus.is_disconnected?(status) -> "bg-gray-600 text-gray-300"
      HomeStatus.is_initialized?(status) -> "bg-blue-600 text-blue-100"
      HomeStatus.is_reserved?(status) -> "bg-yellow-600 text-yellow-100"
      true -> "bg-gray-700 text-gray-400"
    end
  end

  defp status_color(_), do: "bg-gray-700 text-gray-400"

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
