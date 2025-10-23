defmodule CortexIqDashboardWeb.DashboardLive do
  use CortexIqDashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to WAMP events
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "wamp:events")
    end

    # Load Belgian locations for map
    locations = CortexIqCore.Geography.all_locations()

    {:ok,
     socket
     |> assign(:events, [])
     |> assign(:unique_homes, MapSet.new())
     |> assign(:unique_providers, MapSet.new())
     |> assign(:locations, locations)
     |> assign(:home_states, %{})
     |> assign(:home_history, %{})
     |> assign(:home_contracts, %{})
     |> assign(:home_balances, %{})
     |> assign(:provider_states, %{})
     |> assign(:provider_history, %{})
     |> assign(:provider_market_share, %{})
     |> assign(:aggregate_history, [])
     |> assign(:selected_home, nil)
     |> assign(:selected_provider, nil)
     |> assign(:selected_region, :all)
     |> assign(:active_tab, :overview)
     |> assign(:search_query, "")
     |> assign(:sort_by, :home_id)
     |> assign(:sort_direction, :asc)
     |> assign(:simulation_time, nil)
     |> assign(:simulation_speed, nil)
     |> assign(:stats, %{
       homes: 0,
       providers: 0,
       events_received: 0,
       total_production_kwh: 0.0,
       total_consumption_kwh: 0.0,
       total_energy_bought_kwh: 0.0,
       total_energy_sold_kwh: 0.0,
       total_cost_paid: 0.0,
       total_revenue_received: 0.0,
       contract_switches: 0,
       avg_battery_percent: 0.0
     })}
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, socket) do
    # Extract the REAL topic from event details (not the subscription prefix)
    real_topic = get_in(event_data, [:details, "topic"]) || "unknown"

    # Skip some events to reduce load (process every 5th event for non-critical data)
    # This keeps the UI responsive while still showing real-time updates
    should_process = :rand.uniform(5) == 1 or String.contains?(real_topic, ["simulation.time", "contract"])

    if not should_process do
      {:noreply, socket}
    else
      handle_wamp_event(real_topic, event_data, socket)
    end
  end

  defp handle_wamp_event(real_topic, event_data, socket) do
    # Debug: log event type distribution occasionally
    # 0.1% sample
    if :rand.uniform() < 0.001 do
      require Logger
      event_type = extract_event_type(real_topic)
      Logger.debug("Received event type: #{event_type}, topic: #{real_topic}")
    end

    # Handle simulation time separately
    socket =
      if String.contains?(real_topic, "simulation.time") do
        update_simulation_time(socket, event_data)
      else
        socket
      end

    # Add event to the list (keep last 50)
    events = [format_event(real_topic, event_data) | socket.assigns.events] |> Enum.take(50)

    # Track unique homes and providers
    {unique_homes, unique_providers} =
      track_unique_entities(
        socket.assigns.unique_homes,
        socket.assigns.unique_providers,
        real_topic,
        event_data
      )

    # Update home contracts and balances
    {home_contracts, home_balances} =
      update_home_contracts_and_balances(
        socket.assigns.home_contracts,
        socket.assigns.home_balances,
        real_topic,
        event_data
      )

    # Update home states and push to map
    {home_states, home_history, socket} =
      update_home_states(
        socket,
        real_topic,
        event_data
      )

    # Update provider states and history
    {provider_states, provider_history} =
      update_provider_states(
        socket.assigns.provider_states,
        socket.assigns.provider_history,
        real_topic,
        event_data
      )

    # Calculate provider market share based on contracts
    provider_market_share = calculate_provider_market_share(home_contracts)

    # Calculate aggregate stats
    stats =
      calculate_aggregate_stats(
        socket.assigns.stats,
        unique_homes,
        unique_providers,
        home_states,
        home_balances,
        real_topic,
        event_data
      )

    # Update aggregate history (keep last 100 measurements)
    aggregate_history =
      update_aggregate_history(
        socket.assigns.aggregate_history,
        home_states,
        provider_states
      )

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:unique_homes, unique_homes)
     |> assign(:unique_providers, unique_providers)
     |> assign(:home_contracts, home_contracts)
     |> assign(:home_balances, home_balances)
     |> assign(:home_states, home_states)
     |> assign(:home_history, home_history)
     |> assign(:provider_states, provider_states)
     |> assign(:provider_history, provider_history)
     |> assign(:provider_market_share, provider_market_share)
     |> assign(:aggregate_history, aggregate_history)
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_event("select_home", %{"home_id" => home_id}, socket) do
    {:noreply, socket |> assign(:selected_home, home_id) |> assign(:selected_provider, nil)}
  end

  @impl true
  def handle_event("select_provider", %{"provider_id" => provider_id}, socket) do
    {:noreply, socket |> assign(:selected_provider, provider_id) |> assign(:selected_home, nil)}
  end

  @impl true
  def handle_event("select_region", %{"region" => region}, socket) do
    region_atom = String.to_atom(region)

    socket =
      socket
      |> assign(:selected_region, region_atom)
      |> push_event("filter_region", %{region: region})

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_detail_panel", _params, socket) do
    {:noreply, socket |> assign(:selected_home, nil) |> assign(:selected_provider, nil)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    require Logger
    tab_atom = String.to_atom(tab)
    Logger.info("Switching to tab: #{tab_atom}")
    {:noreply, socket |> assign(:active_tab, tab_atom)}
  end

  @impl true
  def handle_event("search_homes", %{"search" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query)}
  end

  @impl true
  def handle_event("sort_homes", %{"column" => column}, socket) do
    column_atom = String.to_atom(column)

    # Toggle direction if same column, otherwise default to asc
    {sort_by, sort_direction} =
      if socket.assigns.sort_by == column_atom do
        {column_atom, toggle_direction(socket.assigns.sort_direction)}
      else
        {column_atom, :asc}
      end

    {:noreply, socket |> assign(:sort_by, sort_by) |> assign(:sort_direction, sort_direction)}
  end

  # Render homes list with search/filter/sort
  defp render_homes_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Search and Filter Controls -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="flex gap-4 items-center">
          <div class="flex-1">
            <input
              type="text"
              placeholder="Search by Home ID or Location..."
              value={@search_query}
              phx-keyup="search_homes"
              phx-debounce="300"
              name="search"
              class="w-full px-4 py-2 bg-gray-900 border border-gray-600 rounded-lg text-gray-100 placeholder-gray-500 focus:border-blue-500 focus:outline-none"
            />
          </div>
          <div class="text-gray-400 text-sm">
            {length(get_filtered_homes(assigns))} / {@stats.homes} homes
          </div>
        </div>
      </div>

      <!-- Homes Table -->
      <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="bg-gray-900 border-b border-gray-700">
              <tr>
                <%= for {column, label} <- [
                  {:home_id, "Home ID"},
                  {:location, "Location"},
                  {:provider, "Provider"},
                  {:production, "Production"},
                  {:consumption, "Consumption"},
                  {:battery, "Battery"},
                  {:balance, "Energy Balance"},
                  {:cost, "Net Cost"}
                ] do %>
                  <th class="px-4 py-3 text-left">
                    <button
                      phx-click="sort_homes"
                      phx-value-column={column}
                      class="flex items-center gap-2 text-gray-400 hover:text-gray-200 font-semibold text-xs uppercase tracking-wide"
                    >
                      {label}
                      <%= if @sort_by == column do %>
                        <span class="text-blue-400">
                          {if @sort_direction == :asc, do: "▲", else: "▼"}
                        </span>
                      <% end %>
                    </button>
                  </th>
                <% end %>
                <th class="px-4 py-3 text-left text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
              <%= for home <- get_filtered_homes(assigns) do %>
                <% home_state = Map.get(@home_states, home.home_id, %{}) %>
                <% contract = Map.get(@home_contracts, home.home_id) %>
                <% balance = Map.get(@home_balances, home.home_id, %{}) %>
                <tr class="hover:bg-gray-750 transition-colors">
                  <td class="px-4 py-3">
                    <div class="font-mono text-sm text-blue-400">{home.home_id}</div>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm">{home.location}</div>
                    <div class="text-xs text-gray-500">{home.region |> to_string() |> String.capitalize()}</div>
                  </td>
                  <td class="px-4 py-3">
                    <%= if contract do %>
                      <div class="text-sm text-yellow-400">{get_provider_name(contract.provider_id)}</div>
                      <div class="text-xs text-gray-500">
                        Expires: {format_short_date(contract.end_date)}
                      </div>
                    <% else %>
                      <div class="text-sm text-gray-500">No contract</div>
                    <% end %>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm text-green-400">
                      {format_power(Map.get(home_state, :production_kw, 0.0))}
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm text-red-400">
                      {format_power(Map.get(home_state, :consumption_kw, 0.0))}
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <% battery_pct = Map.get(home_state, :battery_percent, 0.0) %>
                    <div class="flex items-center gap-2">
                      <div class="flex-1 bg-gray-700 rounded-full h-2 w-16">
                        <div
                          class={"h-full rounded-full #{battery_color(battery_pct)}"}
                          style={"width: #{battery_pct}%"}
                        >
                        </div>
                      </div>
                      <div class="text-xs text-gray-400 w-10 text-right">
                        {Float.round(battery_pct, 0)}%
                      </div>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <% net_balance = Map.get(balance, :net_balance_kwh, 0.0) %>
                    <div class={"text-sm font-semibold #{if net_balance > 0, do: "text-red-400", else: "text-green-400"}"}>
                      {if net_balance > 0, do: "+", else: ""}{format_energy(net_balance)}
                    </div>
                    <div class="text-xs text-gray-500">
                      {if net_balance > 0, do: "buying", else: "selling"}
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <% net_cost = Map.get(balance, :net_cost, 0.0) %>
                    <div class={"text-sm font-semibold #{if net_cost > 0, do: "text-red-400", else: "text-green-400"}"}>
                      ${Float.round(net_cost, 2)}
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <button
                      phx-click="select_home"
                      phx-value-home_id={home.home_id}
                      class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs font-semibold transition-colors"
                    >
                      View Details
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-gray-100">
      <div class="container mx-auto p-8">
        <h1 class="text-4xl font-bold mb-6 text-blue-400">CortexIQ Energy Exchange</h1>

    <!-- Main Navigation Tabs -->
        <div class="flex gap-2 mb-6 border-b border-gray-700">
          <%= for {tab, label, icon} <- [{:overview, "Overview", "📊"}, {:homes, "Homes", "🏠"}, {:providers, "Providers", "⚡"}] do %>
            <button
              phx-click="switch_tab"
              phx-value-tab={tab}
              class={"px-6 py-3 font-semibold transition-all #{if @active_tab == tab, do: "text-blue-400 border-b-2 border-blue-400", else: "text-gray-400 hover:text-gray-300"}"}
            >
              <span class="mr-2">{icon}</span>{label}
            </button>
          <% end %>
        </div>

    <!-- Regional Tabs (shown for Overview and Homes tabs) -->
        <%= if @active_tab in [:overview, :homes] do %>
        <div class="flex gap-2 mb-6">
          <%= for {region, label} <- [{:all, "All Regions"}, {:brussels, "Brussels"}, {:flanders, "Flanders"}, {:wallonia, "Wallonia"}] do %>
            <button
              phx-click="select_region"
              phx-value-region={region}
              class={"px-6 py-3 rounded-lg font-semibold transition-all #{if @selected_region == region, do: "bg-blue-600 text-white", else: "bg-gray-800 text-gray-400 hover:bg-gray-700"}"}
            >
              {label}
            </button>
          <% end %>
        </div>
        <% end %>

    <!-- Overview Tab Content -->
        <%= if @active_tab == :overview do %>
    <!-- Provider Cards -->
        <div class="mb-6">
          <h3 class="text-sm font-semibold text-gray-400 mb-3">Energy Providers - Market Competition</h3>
          <div class="grid grid-cols-5 gap-4">
            <%= for provider_id <- ["provider_a", "provider_b", "provider_c", "provider_d", "provider_e"] do %>
              <% provider_state = Map.get(@provider_states, provider_id, %{}) %>
              <% market_share = Map.get(@provider_market_share, provider_id, 0) %>
              <% total_homes = @stats.homes %>
              <% share_percent = if total_homes > 0, do: Float.round(market_share / total_homes * 100, 1), else: 0.0 %>
              <button
                phx-click="select_provider"
                phx-value-provider_id={provider_id}
                class={"bg-gray-800 rounded-lg p-4 border-2 transition-all hover:border-yellow-500 #{if @selected_provider == provider_id, do: "border-yellow-500", else: "border-gray-700"}"}
              >
                <div class="text-left">
                  <div class="text-sm font-bold text-yellow-400">
                    {get_provider_name(provider_id)}
                  </div>
                  <div class="mt-2">
                    <div class="text-xs text-gray-400">Market Share</div>
                    <div class="text-2xl font-bold text-white">
                      {share_percent}%
                    </div>
                    <div class="text-xs text-gray-500">{market_share} contracts</div>
                  </div>
                  <%= if Map.get(provider_state, :strategy) do %>
                    <div class="text-xs text-gray-400 mt-2 truncate">
                      {format_strategy(Map.get(provider_state, :strategy))}
                    </div>
                  <% end %>
                </div>
              </button>
            <% end %>
          </div>
        </div>
        
    <!-- Simulation Time Display -->
        <%= if @simulation_time do %>
          <div class="mb-4 bg-gray-800 rounded-lg p-4 border border-blue-500">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-gray-400 text-sm">Simulation Time:</span>
                <span class="text-blue-400 font-mono text-lg ml-2">{format_simulation_time(@simulation_time)}</span>
              </div>
              <%= if @simulation_speed do %>
                <div class="text-gray-500 text-sm">
                  Speed: <span class="text-blue-400 font-bold">{format_number(@simulation_speed)}x</span>
                  <span class="text-gray-600 ml-2">(1 year = 5 min)</span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

    <!-- Stats Cards -->
        <div class="grid grid-cols-6 gap-4 mb-6">
          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Active Homes</div>
            <div class="text-2xl font-bold text-green-400">{@stats.homes}</div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Energy Bought</div>
            <div class="text-lg font-bold text-red-400">
              {format_energy(@stats.total_energy_bought_kwh)}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              ${Float.round(@stats.total_cost_paid, 2)}
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Energy Sold</div>
            <div class="text-lg font-bold text-green-400">
              {format_energy(@stats.total_energy_sold_kwh)}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              ${Float.round(@stats.total_revenue_received, 2)}
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Net Balance</div>
            <div class={"text-lg font-bold #{if @stats.total_energy_bought_kwh - @stats.total_energy_sold_kwh > 0, do: "text-red-400", else: "text-green-400"}"}>
              {format_energy(abs(@stats.total_energy_bought_kwh - @stats.total_energy_sold_kwh))}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              Net: ${Float.round(@stats.total_cost_paid - @stats.total_revenue_received, 2)}
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Avg Battery</div>
            <div class="text-2xl font-bold text-blue-400">
              {Float.round(@stats.avg_battery_percent, 1)}%
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Contract Switches</div>
            <div class="text-2xl font-bold text-purple-400">{@stats.contract_switches}</div>
          </div>
        </div>
        
    <!-- Main Content: Map + Event Feed -->
        <div class="grid grid-cols-12 gap-6">
          <!-- Map Section (70%) -->
          <div class="col-span-8">
            <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
              <div class="p-4 border-b border-gray-700">
                <h2 class="text-xl font-bold text-gray-100">Belgium Energy Mesh</h2>
              </div>
              <!-- Map Container -->
              <div
                id="belgium-map"
                phx-hook="BelgiumMap"
                phx-update="ignore"
                data-locations={Jason.encode!(@locations)}
                data-selected-region={@selected_region}
                style="height: 600px;"
              >
              </div>
              <!-- Map Legend -->
              <div class="p-4 bg-gray-750 border-t border-gray-700">
                <div class="flex items-center gap-6 text-sm">
                  <div class="flex items-center gap-2">
                    <div class="w-4 h-4 rounded-full bg-green-500"></div>
                    <span class="text-gray-300">Producing</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-4 h-4 rounded-full bg-yellow-500"></div>
                    <span class="text-gray-300">Balanced</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-4 h-4 rounded-full bg-red-500"></div>
                    <span class="text-gray-300">Consuming</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Live Events Feed (30%) -->
          <div class="col-span-4">
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h2 class="text-xl font-bold mb-4 text-gray-100">Live Events</h2>

              <div class="space-y-2 overflow-y-auto" style="height: 600px;">
                <%= if Enum.empty?(@events) do %>
                  <div class="text-gray-500 text-center py-8">
                    Waiting for events...
                  </div>
                <% else %>
                  <%= for event <- @events do %>
                    <div class="bg-gray-700 rounded p-3 text-sm font-mono">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <span class={"px-2 py-1 rounded text-xs font-semibold #{event_color(event.type)}"}>
                            {event.type}
                          </span>
                        </div>
                        <div class="text-gray-500 text-xs">{event.time}</div>
                      </div>
                      <div class="mt-2 text-gray-400 text-xs">
                        <%= if is_map(event.data) and Map.has_key?(event.data, :provider_id) do %>
                          <button
                            phx-click="select_provider"
                            phx-value-provider_id={event.data.provider_id}
                            class="text-yellow-400 hover:text-yellow-300 underline cursor-pointer"
                          >
                            {event.data.text}
                          </button>
                        <% else %>
                          {event.data}
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        
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
              
    <!-- Provider Market Share Chart -->
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-gray-300 mb-4">Provider Market Share</h3>
                <div
                  id="market-share-chart"
                  phx-hook="MarketShareChart"
                  phx-update="ignore"
                  data-home-states={Jason.encode!(@home_states)}
                  data-provider-states={Jason.encode!(@provider_states)}
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
              
    <!-- Price Comparison Chart -->
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-gray-300 mb-4">Provider Price Comparison</h3>
                <div
                  id="price-comparison-chart"
                  phx-hook="PriceComparisonChart"
                  phx-update="ignore"
                  data-provider-history={Jason.encode!(@provider_history)}
                >
                </div>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- System Status -->
        <div class="mt-6 text-gray-500 text-sm">
          <p>Realm: <%= System.get_env("BONDY_REALM", "be.cortexiq.energy") %> | WAMP Router: Bondy @ <%= System.get_env("BONDY_URL", "ws://localhost:18080/ws") %></p>
        </div>
        <% end %>

    <!-- Homes Tab Content -->
        <%= if @active_tab == :homes do %>
          <%= render_homes_list(assigns) %>
        <% end %>

    <!-- Providers Tab Content -->
        <%= if @active_tab == :providers do %>
          <div class="text-center text-gray-500 mt-20">
            <div class="text-6xl mb-4">⚡</div>
            <h2 class="text-2xl mb-2">Providers View</h2>
            <p>Coming soon: Detailed provider comparison and analytics</p>
          </div>
        <% end %>

      </div>

    <!-- Home Detail Panel (Slide-in) -->
      <%= if @selected_home do %>
        <% home_state = Map.get(@home_states, @selected_home, %{}) %>
        <% home_history = Map.get(@home_history, @selected_home, []) %>

        <div
          class="fixed inset-0 bg-black bg-opacity-50 z-40"
          phx-click="close_detail_panel"
        >
        </div>

        <div
          class="fixed right-0 top-0 bottom-0 w-1/3 bg-gray-800 shadow-2xl z-50 overflow-y-auto border-l border-gray-700"
          style="animation: slideIn 0.3s ease-out;"
        >
          <!-- Panel Header -->
          <div class="sticky top-0 bg-gray-900 border-b border-gray-700 p-6 flex justify-between items-start">
            <div>
              <h2 class="text-2xl font-bold text-blue-400">{@selected_home}</h2>
              <div class="text-gray-400 text-sm mt-1">
                {Map.get(home_state, :city, "Unknown")}, {Map.get(home_state, :postal_code, "")}
              </div>
              <%= if Map.get(home_state, :region) do %>
                <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold rounded-full bg-blue-600 text-white">
                  {CortexIqCore.Geography.region_name(
                    String.to_atom(Map.get(home_state, :region, "unknown"))
                  )}
                </span>
              <% end %>
            </div>
            <button
              phx-click="close_detail_panel"
              class="text-gray-400 hover:text-white transition-colors"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
          
    <!-- Panel Content -->
          <div class="p-6 space-y-6">
            <!-- Current Metrics -->
            <div class="grid grid-cols-3 gap-4">
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Production</div>
                <div class="text-2xl font-bold text-green-400">
                  {round(Map.get(home_state, :production_w, 0))}W
                </div>
              </div>
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Consumption</div>
                <div class="text-2xl font-bold text-red-400">
                  {round(Map.get(home_state, :consumption_w, 0))}W
                </div>
              </div>
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Battery</div>
                <div class="text-2xl font-bold text-blue-400">
                  {Float.round(Map.get(home_state, :battery_percent, 0), 1)}%
                </div>
              </div>
            </div>
            
    <!-- 3-Phase Power Distribution -->
            <%= if Map.has_key?(home_state, :power_l1_w) do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">3-Phase Power Distribution</h3>
                <div
                  id={"phase-chart-#{@selected_home}"}
                  phx-hook="PhaseChart"
                  phx-update="ignore"
                  data-l1={Map.get(home_state, :power_l1_w, 0)}
                  data-l2={Map.get(home_state, :power_l2_w, 0)}
                  data-l3={Map.get(home_state, :power_l3_w, 0)}
                >
                </div>
              </div>
            <% end %>
            
    <!-- Voltage & Frequency -->
            <%= if Map.has_key?(home_state, :voltage_v) do %>
              <div class="grid grid-cols-2 gap-4">
                <div class="bg-gray-700 rounded-lg p-4">
                  <div class="text-gray-400 text-xs">Voltage</div>
                  <div class="text-xl font-bold text-yellow-400">
                    {Float.round(Map.get(home_state, :voltage_v, 230.0), 1)}V
                  </div>
                </div>
                <div class="bg-gray-700 rounded-lg p-4">
                  <div class="text-gray-400 text-xs">Frequency</div>
                  <div class="text-xl font-bold text-yellow-400">
                    {Float.round(Map.get(home_state, :frequency_hz, 50.0), 2)}Hz
                  </div>
                </div>
              </div>
            <% end %>
            
    <!-- Historical Sparklines -->
            <%= if length(home_history) > 1 do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">
                  Production vs Consumption (Last 5 min)
                </h3>
                <div
                  id={"power-sparkline-#{@selected_home}"}
                  phx-hook="PowerSparkline"
                  phx-update="ignore"
                  data-history={Jason.encode!(home_history)}
                >
                </div>
              </div>

              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">Battery Charge (Last 5 min)</h3>
                <div
                  id={"battery-sparkline-#{@selected_home}"}
                  phx-hook="BatterySparkline"
                  phx-update="ignore"
                  data-history={Jason.encode!(home_history)}
                >
                </div>
              </div>
            <% end %>
            
    <!-- Provider Info -->
            <%= if Map.get(home_state, :current_provider) do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-2">Current Provider</h3>
                <div class="text-lg font-bold text-blue-400">
                  {Map.get(home_state, :current_provider)}
                </div>
                <%= if Map.get(home_state, :current_rate) do %>
                  <div class="text-sm text-gray-400 mt-1">
                    Rate: €{Map.get(home_state, :current_rate)}/kWh
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <style>
          @keyframes slideIn {
            from {
              transform: translateX(100%);
            }
            to {
              transform: translateX(0);
            }
          }
        </style>
      <% end %>
      
    <!-- Provider Detail Panel (Slide-in) -->
      <%= if @selected_provider do %>
        <% provider_state = Map.get(@provider_states, @selected_provider, %{}) %>
        <% provider_history = Map.get(@provider_history, @selected_provider, []) %>

        <div
          class="fixed inset-0 bg-black bg-opacity-50 z-40"
          phx-click="close_detail_panel"
        >
        </div>

        <div
          class="fixed right-0 top-0 bottom-0 w-1/3 bg-gray-800 shadow-2xl z-50 overflow-y-auto border-l border-gray-700"
          style="animation: slideIn 0.3s ease-out;"
        >
          <!-- Panel Header -->
          <div class="sticky top-0 bg-gray-900 border-b border-gray-700 p-6 flex justify-between items-start">
            <div>
              <h2 class="text-2xl font-bold text-yellow-400">
                {Map.get(provider_state, :provider_name, @selected_provider)}
              </h2>
              <div class="text-gray-400 text-sm mt-1">
                Provider ID: {@selected_provider}
              </div>
              <%= if Map.get(provider_state, :strategy) do %>
                <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold rounded-full bg-yellow-600 text-white">
                  {format_strategy(Map.get(provider_state, :strategy))}
                </span>
              <% end %>
            </div>
            <button
              phx-click="close_detail_panel"
              class="text-gray-400 hover:text-white transition-colors"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
          
    <!-- Panel Content -->
          <div class="p-6 space-y-6">
            <!-- Contract Offer Details -->
            <%= if Map.get(provider_state, :contract_offer) do %>
              <% contract = Map.get(provider_state, :contract_offer) %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">12-Month Contract Offer</h3>

                <!-- Day/Night Pricing Grid -->
                <div class="grid grid-cols-2 gap-3 mb-4">
                  <div class="bg-gray-800 rounded p-3">
                    <div class="text-yellow-400 text-xs font-semibold mb-2">☀️ Day Rates (6am-6pm)</div>
                    <div class="flex justify-between items-center mb-1">
                      <span class="text-gray-400 text-xs">Buy:</span>
                      <span class="text-green-400 font-semibold">€{Float.round(Map.get(contract, :day_buy_price, 0), 4)}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-gray-400 text-xs">Sell:</span>
                      <span class="text-blue-400 font-semibold">€{Float.round(Map.get(contract, :day_sell_price, 0), 4)}</span>
                    </div>
                  </div>

                  <div class="bg-gray-800 rounded p-3">
                    <div class="text-purple-400 text-xs font-semibold mb-2">🌙 Night Rates (6pm-6am)</div>
                    <div class="flex justify-between items-center mb-1">
                      <span class="text-gray-400 text-xs">Buy:</span>
                      <span class="text-green-400 font-semibold">€{Float.round(Map.get(contract, :night_buy_price, 0), 4)}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-gray-400 text-xs">Sell:</span>
                      <span class="text-blue-400 font-semibold">€{Float.round(Map.get(contract, :night_sell_price, 0), 4)}</span>
                    </div>
                  </div>
                </div>

                <!-- Contract Terms -->
                <div class="space-y-2 text-sm">
                  <div class="flex justify-between items-center">
                    <span class="text-gray-400">Switching Discount:</span>
                    <span class="text-yellow-400 font-semibold">€{Float.round(Map.get(contract, :switching_discount, 0), 2)}</span>
                  </div>
                  <div class="flex justify-between items-center">
                    <span class="text-gray-400">Min. Monthly Usage:</span>
                    <span class="text-white font-semibold">{Float.round(Map.get(contract, :minimum_monthly_kwh, 0), 0)} kWh</span>
                  </div>
                  <div class="flex justify-between items-center">
                    <span class="text-gray-400">Contract Duration:</span>
                    <span class="text-white font-semibold">{Map.get(contract, :duration_months, 12)} months</span>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Spot Market Pricing (if available) -->
            <%= if Map.get(provider_state, :spot_price) do %>
              <% spot = Map.get(provider_state, :spot_price) %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">Spot Market (No Contract)</h3>
                <div class="grid grid-cols-2 gap-4">
                  <div>
                    <div class="text-gray-400 text-xs">Buy Price</div>
                    <div class="text-xl font-bold text-red-400">
                      €{Float.round(Map.get(spot, :buy_price, 0), 4)}
                    </div>
                    <div class="text-xs text-gray-500">per kWh</div>
                  </div>
                  <div>
                    <div class="text-gray-400 text-xs">Sell Price</div>
                    <div class="text-xl font-bold text-blue-400">
                      €{Float.round(Map.get(spot, :sell_price, 0), 4)}
                    </div>
                    <div class="text-xs text-gray-500">per kWh</div>
                  </div>
                </div>
                <div class="mt-2 text-xs text-gray-500">
                  ⚠️ Spot prices are more volatile and less favorable than contract rates
                </div>
              </div>
            <% end %>

            <!-- Average Rates (for comparison) -->
            <div class="grid grid-cols-2 gap-4">
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Avg Purchase Rate</div>
                <div class="text-2xl font-bold text-green-400">
                  €{Float.round(Map.get(provider_state, :price_per_kwh, 0), 4)}
                </div>
                <div class="text-xs text-gray-500">per kWh (weighted)</div>
              </div>
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Avg Sell-back Rate</div>
                <div class="text-2xl font-bold text-blue-400">
                  €{Float.round(Map.get(provider_state, :sell_back_rate, 0), 4)}
                </div>
                <div class="text-xs text-gray-500">per kWh (weighted)</div>
              </div>
            </div>
            
    <!-- Regions Served -->
            <%= if Map.get(provider_state, :regions) && length(Map.get(provider_state, :regions, [])) > 0 do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-2">Regions Served</h3>
                <div class="flex flex-wrap gap-2">
                  <%= for region <- Map.get(provider_state, :regions, []) do %>
                    <span class="px-3 py-1 text-xs font-semibold rounded-full bg-blue-600 text-white">
                      {region}
                    </span>
                  <% end %>
                </div>
              </div>
            <% end %>
            
    <!-- Pricing History Chart -->
            <%= if length(provider_history) > 1 do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">
                  Pricing History (Last 10 min)
                </h3>
                <div
                  id={"pricing-chart-#{@selected_provider}"}
                  phx-hook="PricingChart"
                  phx-update="ignore"
                  data-history={Jason.encode!(provider_history)}
                  data-provider-name={Map.get(provider_state, :provider_name, @selected_provider)}
                >
                </div>
              </div>
            <% end %>
            
    <!-- Connected Homes -->
            <div class="bg-gray-700 rounded-lg p-4">
              <h3 class="text-sm font-semibold text-gray-300 mb-2">Market Share</h3>
              <% connected_homes = count_homes_by_provider(@home_states, @selected_provider) %>
              <div class="text-3xl font-bold text-yellow-400">
                {connected_homes}
              </div>
              <div class="text-xs text-gray-500">homes connected</div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions for homes list

  defp get_filtered_homes(assigns) do
    # Get all homes from home_states (these are the actual active homes)
    homes =
      assigns.home_states
      |> Map.keys()
      |> Enum.map(fn home_id ->
        # Get location for this home
        location = CortexIqCore.Geography.location_for_home(home_id)

        %{
          home_id: home_id,
          location: location.city,
          postal_code: location.postal_code,
          region: location.region
        }
      end)

    # Apply search filter
    homes =
      if assigns.search_query != "" do
        query = String.downcase(assigns.search_query)

        Enum.filter(homes, fn home ->
          String.contains?(String.downcase(home.home_id), query) ||
            String.contains?(String.downcase(home.location), query)
        end)
      else
        homes
      end

    # Apply region filter
    homes =
      if assigns.selected_region != :all do
        Enum.filter(homes, fn home -> home.region == assigns.selected_region end)
      else
        homes
      end

    # Apply sorting
    homes
    |> Enum.sort_by(
      fn home ->
        case assigns.sort_by do
          :home_id -> home.home_id
          :location -> home.location
          :provider -> get_in(assigns.home_contracts, [home.home_id, :provider_id]) || ""

          :production ->
            get_in(assigns.home_states, [home.home_id, :production_kw]) || 0.0

          :consumption ->
            get_in(assigns.home_states, [home.home_id, :consumption_kw]) || 0.0

          :battery ->
            get_in(assigns.home_states, [home.home_id, :battery_percent]) || 0.0

          :balance ->
            get_in(assigns.home_balances, [home.home_id, :net_balance_kwh]) || 0.0

          :cost ->
            get_in(assigns.home_balances, [home.home_id, :net_cost]) || 0.0

          _ ->
            home.home_id
        end
      end,
      if(assigns.sort_direction == :asc, do: :asc, else: :desc)
    )
  end

  defp toggle_direction(:asc), do: :desc
  defp toggle_direction(:desc), do: :asc

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

  defp format_short_date(%DateTime{} = dt) do
    "#{dt.month}/#{dt.day}/#{dt.year}"
  end

  defp format_short_date(_), do: "N/A"

  defp format_event(topic, event_data) do
    type = extract_event_type(topic)

    # Debug logging
    require Logger
    Logger.debug("Event type detected: #{type} for topic: #{topic}")

    # Extract relevant data from kwargs
    data =
      event_data
      |> Map.get(:kwargs, %{})
      |> format_kwargs(type)

    %{
      type: type,
      topic: topic,
      data: data,
      time: format_time(DateTime.utc_now())
    }
  end

  defp extract_event_type(topic) do
    cond do
      String.contains?(topic, "online") -> "online"
      String.contains?(topic, "offline") -> "offline"
      String.contains?(topic, "measurement") -> "measurement"
      String.contains?(topic, "production") -> "production"
      String.contains?(topic, "consumption") -> "consumption"
      String.contains?(topic, "storage") -> "storage"
      String.contains?(topic, "contract_offer") -> "contract_offer"
      String.contains?(topic, "spot_price") -> "spot_price"
      String.contains?(topic, "tariff") -> "tariff"
      String.contains?(topic, "contract") -> "contract"
      true -> "other"
    end
  end

  defp format_energy(kwh) when is_float(kwh) or is_number(kwh) do
    cond do
      kwh >= 1_000_000 ->
        # GWh (Gigawatt-hours)
        value = kwh / 1_000_000
        "#{Float.round(value, 2)} GWh"

      kwh >= 1_000 ->
        # MWh (Megawatt-hours)
        value = kwh / 1_000
        "#{Float.round(value, 2)} MWh"

      kwh >= 1 ->
        # kWh
        "#{Float.round(kwh, 2)} kWh"

      kwh >= 0.001 ->
        # Wh (Watt-hours)
        value = kwh * 1_000
        "#{Float.round(value, 2)} Wh"

      true ->
        # Very small values
        "#{Float.round(kwh, 4)} kWh"
    end
  end

  defp format_energy(_), do: "0.00 kWh"

  defp format_kwargs(kwargs, "production") do
    home_id = Map.get(kwargs, "home_id", "unknown")
    city = Map.get(kwargs, "city", "Unknown")
    watts = Map.get(kwargs, "watts", 0) |> round()
    source = Map.get(kwargs, "source", "solar")

    "#{home_id} (#{city}): #{watts}W from #{source}"
  end

  defp format_kwargs(kwargs, "consumption") do
    home_id = Map.get(kwargs, "home_id", "unknown")
    city = Map.get(kwargs, "city", "Unknown")
    watts = Map.get(kwargs, "watts", 0) |> round()

    "#{home_id} (#{city}): consuming #{watts}W"
  end

  defp format_kwargs(kwargs, "storage") do
    home_id = Map.get(kwargs, "home_id", "unknown")
    city = Map.get(kwargs, "city", "Unknown")
    battery_percent = Map.get(kwargs, "battery_percent", 0) |> Float.round(1)

    "#{home_id} (#{city}): Battery #{battery_percent}%"
  end

  defp format_kwargs(kwargs, "tariff") do
    provider_id = Map.get(kwargs, "provider_id", "unknown")
    provider_name = Map.get(kwargs, "provider_name", provider_id)
    price = Map.get(kwargs, "price_per_kwh", 0)
    regions = Map.get(kwargs, "regions", []) |> Enum.join(", ")

    # Return a map with provider_id for clickable rendering
    %{
      provider_id: provider_id,
      text: "#{provider_name}: €#{price}/kWh (#{regions})"
    }
  end

  defp format_kwargs(kwargs, "measurement") do
    home_id = Map.get(kwargs, "home_id", "unknown")
    city = Map.get(kwargs, "city", "Unknown")
    power = Map.get(kwargs, "power_w", 0) |> Float.round(0)
    l1 = Map.get(kwargs, "power_l1_w", 0) |> Float.round(0)
    l2 = Map.get(kwargs, "power_l2_w", 0) |> Float.round(0)
    l3 = Map.get(kwargs, "power_l3_w", 0) |> Float.round(0)
    voltage = Map.get(kwargs, "voltage_v", 0) |> Float.round(1)

    "#{home_id} (#{city}): #{power}W (L1:#{l1} L2:#{l2} L3:#{l3}), #{voltage}V"
  end

  defp format_kwargs(kwargs, "online") do
    home_id = Map.get(kwargs, "home_id", "unknown")
    city = Map.get(kwargs, "city", "Unknown")
    region = Map.get(kwargs, "region", "unknown")
    provider = Map.get(kwargs, "current_provider", "none")

    "#{home_id} (#{city}, #{region}) came online with provider #{provider}"
  end

  defp format_kwargs(kwargs, "offline") do
    home_id = Map.get(kwargs, "home_id", "unknown")
    city = Map.get(kwargs, "city", "Unknown")

    "#{home_id} (#{city}) went offline"
  end

  defp format_kwargs(kwargs, _type) do
    inspect(kwargs, limit: 100)
  end

  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0..7)
  end

  defp event_color("production"), do: "bg-green-600 text-white"
  defp event_color("consumption"), do: "bg-red-600 text-white"
  defp event_color("storage"), do: "bg-blue-600 text-white"
  defp event_color("tariff"), do: "bg-yellow-600 text-white"
  defp event_color("contract"), do: "bg-purple-600 text-white"
  defp event_color("measurement"), do: "bg-cyan-600 text-white"
  defp event_color("online"), do: "bg-emerald-600 text-white"
  defp event_color("offline"), do: "bg-slate-600 text-white"
  defp event_color(_), do: "bg-gray-600 text-white"

  defp track_unique_entities(unique_homes, unique_providers, topic, event_data)
       when is_binary(topic) do
    kwargs = Map.get(event_data, :kwargs, %{})

    updated_homes =
      kwargs
      |> Map.get("home_id")
      |> case do
        home_id when is_binary(home_id) and home_id != "" ->
          MapSet.put(unique_homes, home_id)

        _ ->
          unique_homes
      end

    updated_providers =
      kwargs
      |> Map.get("provider_id")
      |> case do
        provider_id when is_binary(provider_id) and provider_id != "" ->
          MapSet.put(unique_providers, provider_id)

        _ ->
          unique_providers
      end

    {updated_homes, updated_providers}
  end

  defp track_unique_entities(unique_homes, unique_providers, _topic, _event_data) do
    {unique_homes, unique_providers}
  end

  defp update_home_states(socket, topic, event_data) when is_binary(topic) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")
    city = Map.get(kwargs, "city")

    home_id
    |> case do
      id when is_binary(id) and id != "" ->
        update_home_state_for_event(socket, id, city, topic, kwargs)

      _ ->
        {socket.assigns.home_states, socket.assigns.home_history, socket}
    end
  end

  defp update_home_states(socket, _topic, _event_data) do
    {socket.assigns.home_states, socket.assigns.home_history, socket}
  end

  defp update_home_state_for_event(socket, home_id, city, topic, kwargs) do
    current_state =
      Map.get(socket.assigns.home_states, home_id, %{
        production_w: 0,
        consumption_w: 0,
        battery_percent: 50.0,
        city: city,
        postal_code: Map.get(kwargs, "postal_code", ""),
        region: Map.get(kwargs, "region", ""),
        current_provider: nil,
        current_rate: nil
      })

    # Update state based on event type
    updated_state =
      topic
      |> extract_event_type()
      |> case do
        "production" ->
          Map.merge(current_state, %{
            production_w: Map.get(kwargs, "watts", 0),
            city: city || current_state.city,
            postal_code: Map.get(kwargs, "postal_code", current_state.postal_code),
            region: Map.get(kwargs, "region", current_state.region)
          })

        "consumption" ->
          Map.merge(current_state, %{
            consumption_w: Map.get(kwargs, "watts", 0),
            city: city || current_state.city,
            postal_code: Map.get(kwargs, "postal_code", current_state.postal_code),
            region: Map.get(kwargs, "region", current_state.region)
          })

        "storage" ->
          Map.merge(current_state, %{
            battery_percent: Map.get(kwargs, "battery_percent", 50.0),
            city: city || current_state.city,
            postal_code: Map.get(kwargs, "postal_code", current_state.postal_code),
            region: Map.get(kwargs, "region", current_state.region)
          })

        "measurement" ->
          # Measurement has power_w (absolute value) and source ("solar" or "grid")
          # Convert to production_w and consumption_w based on source
          power_w = Map.get(kwargs, "power_w", 0)
          source = Map.get(kwargs, "source", "grid")

          {production_w, consumption_w} =
            case source do
              # Producing from solar
              "solar" -> {power_w, 0}
              # Consuming from grid
              _ -> {0, power_w}
            end

          Map.merge(current_state, %{
            production_w: production_w,
            consumption_w: consumption_w,
            battery_percent: Map.get(kwargs, "battery_percent", 50.0),
            voltage_v: Map.get(kwargs, "voltage_v", 230.0),
            frequency_hz: Map.get(kwargs, "frequency_hz", 50.0),
            power_l1_w: Map.get(kwargs, "power_l1_w", 0),
            power_l2_w: Map.get(kwargs, "power_l2_w", 0),
            power_l3_w: Map.get(kwargs, "power_l3_w", 0),
            city: city || current_state.city,
            postal_code: Map.get(kwargs, "postal_code", current_state.postal_code),
            region: Map.get(kwargs, "region", current_state.region)
          })

        "online" ->
          Map.merge(current_state, %{
            city: Map.get(kwargs, "city"),
            postal_code: Map.get(kwargs, "postal_code"),
            region: Map.get(kwargs, "region"),
            latitude: Map.get(kwargs, "latitude"),
            longitude: Map.get(kwargs, "longitude"),
            solar_capacity_kw: Map.get(kwargs, "solar_capacity_kw"),
            battery_capacity_kwh: Map.get(kwargs, "battery_capacity_kwh"),
            current_provider: Map.get(kwargs, "current_provider"),
            status: "online"
          })

        "offline" ->
          Map.put(current_state, :status, "offline")

        _ ->
          current_state
      end

    # Update home states map
    home_states = Map.put(socket.assigns.home_states, home_id, updated_state)

    # Store historical data (last 20 measurements)
    current_history = Map.get(socket.assigns.home_history, home_id, [])
    timestamp = DateTime.utc_now()

    measurement = %{
      timestamp: timestamp,
      production_w: Map.get(updated_state, :production_w, 0),
      consumption_w: Map.get(updated_state, :consumption_w, 0),
      battery_percent: Map.get(updated_state, :battery_percent, 50.0)
    }

    updated_history = [measurement | current_history] |> Enum.take(20)
    home_history = Map.put(socket.assigns.home_history, home_id, updated_history)

    # Push update to map JavaScript hook if we have city info
    socket =
      updated_state.city
      |> case do
        c when is_binary(c) and c != "" ->
          push_event(socket, "update_home", %{
            home_id: home_id,
            city: c,
            state: updated_state
          })

        _ ->
          socket
      end

    {home_states, home_history, socket}
  end

  defp update_provider_states(provider_states, provider_history, topic, event_data)
       when is_binary(topic) do
    event_type = extract_event_type(topic)
    kwargs = Map.get(event_data, :kwargs, %{})
    provider_id = Map.get(kwargs, "provider_id")

    case {event_type, provider_id} do
      {"contract_offer", id} when is_binary(id) and id != "" ->
        update_provider_contract_offer(provider_states, provider_history, kwargs)

      {"spot_price", id} when is_binary(id) and id != "" ->
        update_provider_spot_price(provider_states, provider_history, kwargs)

      _ ->
        {provider_states, provider_history}
    end
  end

  defp update_provider_states(provider_states, provider_history, _topic, _event_data) do
    {provider_states, provider_history}
  end

  defp update_provider_contract_offer(provider_states, provider_history, kwargs) do
    provider_id = Map.get(kwargs, "provider_id")

    current_state =
      Map.get(provider_states, provider_id, %{
        provider_name: Map.get(kwargs, "provider_name", provider_id),
        strategy: nil,
        contract_offer: nil,
        spot_price: nil
      })

    # Calculate average prices (weighted: 60% day usage, 40% night)
    day_buy = Map.get(kwargs, "day_buy_price", 0)
    night_buy = Map.get(kwargs, "night_buy_price", 0)
    day_sell = Map.get(kwargs, "day_sell_price", 0)
    night_sell = Map.get(kwargs, "night_sell_price", 0)

    avg_buy_price = day_buy * 0.6 + night_buy * 0.4
    avg_sell_price = day_sell * 0.8 + night_sell * 0.2  # 80% day production (solar)

    contract_offer = %{
      day_buy_price: day_buy,
      night_buy_price: night_buy,
      day_sell_price: day_sell,
      night_sell_price: night_sell,
      avg_buy_price: avg_buy_price,
      avg_sell_price: avg_sell_price,
      switching_discount: Map.get(kwargs, "switching_discount", 0),
      minimum_monthly_kwh: Map.get(kwargs, "minimum_monthly_kwh", 0),
      duration_months: Map.get(kwargs, "duration_months", 12)
    }

    updated_state =
      Map.merge(current_state, %{
        provider_name: Map.get(kwargs, "provider_name", current_state.provider_name),
        strategy: Map.get(kwargs, "strategy", current_state.strategy),
        contract_offer: contract_offer,
        # For backwards compatibility with old UI
        price_per_kwh: avg_buy_price,
        sell_back_rate: avg_sell_price
      })

    # Update provider states
    provider_states = Map.put(provider_states, provider_id, updated_state)

    # Store pricing history (last 20 measurements)
    current_history = Map.get(provider_history, provider_id, [])
    timestamp = DateTime.utc_now()

    measurement = %{
      timestamp: timestamp,
      price_per_kwh: avg_buy_price
    }

    updated_history = [measurement | current_history] |> Enum.take(20)
    provider_history = Map.put(provider_history, provider_id, updated_history)

    {provider_states, provider_history}
  end

  defp update_provider_spot_price(provider_states, provider_history, kwargs) do
    provider_id = Map.get(kwargs, "provider_id")

    current_state =
      Map.get(provider_states, provider_id, %{
        provider_name: Map.get(kwargs, "provider_name", provider_id),
        strategy: nil,
        contract_offer: nil,
        spot_price: nil
      })

    spot_price = %{
      buy_price: Map.get(kwargs, "buy_price", 0),
      sell_price: Map.get(kwargs, "sell_price", 0)
    }

    updated_state =
      Map.merge(current_state, %{
        provider_name: Map.get(kwargs, "provider_name", current_state.provider_name),
        strategy: Map.get(kwargs, "strategy", current_state.strategy),
        spot_price: spot_price
      })

    # Update provider states
    provider_states = Map.put(provider_states, provider_id, updated_state)

    # Don't update history for spot prices - they're too volatile
    # and we want to track contract prices instead

    {provider_states, provider_history}
  end

  defp format_strategy(strategy) when is_binary(strategy) do
    strategy
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_strategy(_), do: "Unknown Strategy"

  defp count_homes_by_provider(home_states, provider_id) do
    home_states
    |> Enum.count(fn {_home_id, state} ->
      Map.get(state, :current_provider) == provider_id
    end)
  end

  defp calculate_aggregate_stats(
         current_stats,
         unique_homes,
         unique_providers,
         home_states,
         home_balances,
         topic,
         event_data
       ) do
    # Calculate average battery percentage
    {total_battery, home_count} =
      home_states
      |> Enum.reduce({0.0, 0}, fn {_id, state}, {sum, count} ->
        {sum + Map.get(state, :battery_percent, 0.0), count + 1}
      end)

    avg_battery = if home_count > 0, do: total_battery / home_count, else: 0.0

    event_type = extract_event_type(topic)

    # Track contract switches (only count "switched" events, not "signed")
    contract_switches =
      if String.contains?(topic, ".contract.switched") do
        current_stats.contract_switches + 1
      else
        current_stats.contract_switches
      end

    # Calculate energy balance totals from home_balances
    {total_bought, total_sold, total_cost, total_revenue} =
      home_balances
      |> Enum.reduce({0.0, 0.0, 0.0, 0.0}, fn {_id, balance}, {bought, sold, cost, revenue} ->
        {
          bought + Map.get(balance, :energy_bought_kwh, 0.0),
          sold + Map.get(balance, :energy_sold_kwh, 0.0),
          cost + Map.get(balance, :cost_paid, 0.0),
          revenue + Map.get(balance, :revenue_received, 0.0)
        }
      end)

    # Accumulate energy from production and consumption events
    # Each event represents energy since last update (roughly every 100ms real-time = ~3 sim hours at 105120x speed)
    {production_kwh_delta, consumption_kwh_delta} =
      case event_type do
        "production" ->
          # Get watts from kwargs
          kwargs = get_in(event_data, [:kwargs]) || %{}
          watts = Map.get(kwargs, "watts", 0.0)
          # Convert to kWh: at 105120x speed, 0.1s real = ~3 hours sim = watts * 3 / 1000
          kwh = watts * 3.0 / 1000.0
          {kwh, 0.0}

        "consumption" ->
          kwargs = get_in(event_data, [:kwargs]) || %{}
          watts = Map.get(kwargs, "watts", 0.0)
          kwh = watts * 3.0 / 1000.0
          {0.0, kwh}

        _ ->
          {0.0, 0.0}
      end

    %{
      homes: MapSet.size(unique_homes),
      providers: MapSet.size(unique_providers),
      events_received: current_stats.events_received + 1,
      total_production_kwh: current_stats.total_production_kwh + production_kwh_delta,
      total_consumption_kwh: current_stats.total_consumption_kwh + consumption_kwh_delta,
      total_energy_bought_kwh: total_bought,
      total_energy_sold_kwh: total_sold,
      total_cost_paid: total_cost,
      total_revenue_received: total_revenue,
      contract_switches: contract_switches,
      avg_battery_percent: avg_battery
    }
  end

  defp update_aggregate_history(history, home_states, provider_states) do
    # Calculate totals across all homes
    {total_production, total_consumption} =
      home_states
      |> Enum.reduce({0.0, 0.0}, fn {_id, state}, {prod, cons} ->
        {prod + Map.get(state, :production_w, 0), cons + Map.get(state, :consumption_w, 0)}
      end)

    # Get regional breakdown
    regional_data =
      home_states
      |> Enum.group_by(fn {_id, state} ->
        Map.get(state, :region, "unknown")
      end)
      |> Enum.map(fn {region, homes} ->
        {total_prod, total_cons} =
          homes
          |> Enum.reduce({0.0, 0.0}, fn {_id, state}, {prod, cons} ->
            {prod + Map.get(state, :production_w, 0), cons + Map.get(state, :consumption_w, 0)}
          end)

        {region, %{production: total_prod, consumption: total_cons, count: length(homes)}}
      end)
      |> Enum.into(%{})

    measurement = %{
      timestamp: DateTime.utc_now(),
      total_production_w: total_production,
      total_consumption_w: total_consumption,
      regional_data: regional_data,
      provider_prices:
        provider_states
        |> Enum.map(fn {id, state} ->
          {id, Map.get(state, :price_per_kwh, 0)}
        end)
        |> Enum.into(%{})
    }

    [measurement | history] |> Enum.take(100)
  end

  # New functions for contract-based system

  defp update_simulation_time(socket, event_data) do
    kwargs = get_in(event_data, [:kwargs]) || %{}
    simulation_time = Map.get(kwargs, "simulation_time")
    speed = Map.get(kwargs, "speed")

    socket
    |> assign(:simulation_time, simulation_time)
    |> assign(:simulation_speed, speed)
  end

  defp update_home_contracts_and_balances(home_contracts, home_balances, topic, event_data) do
    kwargs = get_in(event_data, [:kwargs]) || %{}

    cond do
      String.contains?(topic, ".contract.signed") or String.contains?(topic, ".contract.switched") ->
        home_id = Map.get(kwargs, "home_id")
        provider_id = Map.get(kwargs, "provider_id") || Map.get(kwargs, "to_provider_id")
        contract_id = Map.get(kwargs, "contract_id") || Map.get(kwargs, "to_contract_id")

        new_contracts =
          if home_id && provider_id do
            Map.put(home_contracts, home_id, %{
              provider_id: provider_id,
              contract_id: contract_id,
              signed_at: DateTime.utc_now()
            })
          else
            home_contracts
          end

        {new_contracts, home_balances}

      String.contains?(topic, ".balance") ->
        home_id = Map.get(kwargs, "home_id")

        new_balances =
          if home_id do
            Map.put(home_balances, home_id, %{
              energy_bought_kwh: Map.get(kwargs, "energy_bought_kwh", 0.0),
              energy_sold_kwh: Map.get(kwargs, "energy_sold_kwh", 0.0),
              net_balance_kwh: Map.get(kwargs, "net_balance_kwh", 0.0),
              cost_paid: Map.get(kwargs, "cost_paid", 0.0),
              revenue_received: Map.get(kwargs, "revenue_received", 0.0),
              net_cost: Map.get(kwargs, "net_cost", 0.0)
            })
          else
            home_balances
          end

        {home_contracts, new_balances}

      true ->
        {home_contracts, home_balances}
    end
  end

  defp calculate_provider_market_share(home_contracts) do
    # Count how many homes each provider has
    home_contracts
    |> Enum.reduce(%{}, fn {_home_id, contract_info}, acc ->
      provider_id = contract_info.provider_id
      Map.update(acc, provider_id, 1, &(&1 + 1))
    end)
  end

  defp format_simulation_time(nil), do: "No time data"

  defp format_simulation_time(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")

      _ ->
        iso_string
    end
  end

  defp format_simulation_time(_), do: "Invalid time"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(num), do: inspect(num)

  defp get_provider_name("provider_a"), do: "Steady Eddie Energy"
  defp get_provider_name("provider_b"), do: "Night Owl Power"
  defp get_provider_name("provider_c"), do: "Solar Surfer Electric"
  defp get_provider_name("provider_d"), do: "Peak Predator Energy"
  defp get_provider_name("provider_e"), do: "Discount King Power"
  defp get_provider_name(id), do: String.capitalize(id)
end
