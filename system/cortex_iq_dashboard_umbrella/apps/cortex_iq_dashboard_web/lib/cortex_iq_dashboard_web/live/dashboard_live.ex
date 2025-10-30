defmodule CortexIqDashboardWeb.DashboardLive do
  use CortexIqDashboardWeb, :live_view

  alias CortexIqDashboard.Views.{OverviewAggregator, HomesViewAggregator, ProvidersViewAggregator}

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.info("DashboardLive: mount() called, connected: #{connected?(socket)}")

    # Subscribe to view updates (pure push, no polling)
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "view:overview")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "view:homes")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "view:providers")
      Logger.info("DashboardLive: Subscribed to view updates (push-based)")
    end

    # Load Belgian locations for map
    locations = CortexIqCore.Geography.all_locations()

    # Load initial data from database (where EventAggregator has been persisting events)
    {home_states, unique_homes, home_contracts, home_balances} = load_home_states_from_db()
    {provider_states, unique_providers, provider_market_share} = load_provider_states_from_db()
    {simulation_time, simulation_speed, simulation_paused, db_stats} = load_system_stats_from_db()
    overview = OverviewAggregator.get_state()

    {:ok,
     socket
     |> assign(:overview, overview)
     |> assign(:unique_homes, unique_homes)
     |> assign(:unique_providers, unique_providers)
     |> assign(:locations, locations)
     |> assign(:home_states, home_states)
     |> assign(:home_history, %{})
     |> assign(:home_contracts, home_contracts)
     |> assign(:home_balances, home_balances)
     |> assign(:provider_states, provider_states)
     |> assign(:provider_history, %{})
     |> assign(:provider_market_share, provider_market_share)
     |> assign(:aggregate_history, [])
     |> assign(:selected_home, nil)
     |> assign(:selected_provider, nil)
     |> assign(:selected_region, :all)
     |> assign(:active_tab, :overview)
     |> assign(:search_query, "")
     |> assign(:sort_by, :location)
     |> assign(:sort_direction, :asc)
     |> assign(:page, 1)
     |> assign(:per_page, 10)
     |> assign(:simulation_time, simulation_time)
     |> assign(:simulation_speed, simulation_speed)
     |> assign(:simulation_paused, simulation_paused)
     |> assign(:stats, db_stats)
     |> assign(:view_stack, [:overview])}
  end

  @impl true
  def handle_info(:view_updated, socket) do
    require Logger
    Logger.debug("DashboardLive: View updated, reloading from view aggregators")

    # View aggregator signaled change - reload from in-memory views (instant, no DB)
    {home_states, unique_homes, home_contracts, home_balances} = load_home_states_from_db()
    {provider_states, unique_providers, provider_market_share} = load_provider_states_from_db()
    {simulation_time, simulation_speed, simulation_paused, db_stats} = load_system_stats_from_db()
    overview = OverviewAggregator.get_state()

    # Update socket with new data (but don't push to map - let it update on user interaction only)
    {:noreply,
     socket
     |> assign(:overview, overview)
     |> assign(:unique_homes, unique_homes)
     |> assign(:unique_providers, unique_providers)
     |> assign(:home_contracts, home_contracts)
     |> assign(:home_balances, home_balances)
     |> assign(:home_states, home_states)
     |> assign(:provider_states, provider_states)
     |> assign(:provider_market_share, provider_market_share)
     |> assign(:simulation_time, simulation_time)
     |> assign(:simulation_speed, simulation_speed)
     |> assign(:simulation_paused, simulation_paused)
     |> assign(:stats, db_stats)}
  end

  @impl true
  def handle_event("select_home", %{"home_id" => home_id}, socket) do
    # Navigate to home detail view
    require Logger
    Logger.info("SELECT_HOME event received for: #{home_id}")

    {:noreply,
     socket
     |> assign(:selected_home, home_id)
     |> assign(:selected_provider, nil)
     |> assign(:view_stack, [:homes, {:home_detail, home_id}])
     |> assign(:active_tab, :homes)}
  end

  @impl true
  def handle_event("select_provider", %{"provider_id" => provider_id}, socket) do
    # Navigate to provider detail view
    {:noreply,
     socket
     |> assign(:selected_provider, provider_id)
     |> assign(:selected_home, nil)
     |> assign(:view_stack, [:providers, {:provider_detail, provider_id}])
     |> assign(:active_tab, :providers)}
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
  def handle_event("navigate_back", _params, socket) do
    # Navigate back in view stack
    new_stack =
      case socket.assigns.view_stack do
        [_current | [_ | _] = rest] -> rest
        _ -> [:overview]
      end

    {:noreply,
     socket
     |> assign(:view_stack, new_stack)
     |> assign(:selected_home, nil)
     |> assign(:selected_provider, nil)}
  end

  @impl true
  def handle_event("navigate_to_list", %{"tab" => tab}, socket) do
    # Navigate to list view (homes or providers)
    tab_atom = String.to_atom(tab)

    {:noreply,
     socket
     |> assign(:view_stack, [tab_atom])
     |> assign(:active_tab, tab_atom)
     |> assign(:selected_home, nil)
     |> assign(:selected_provider, nil)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    require Logger
    tab_atom = String.to_atom(tab)
    Logger.info("Switching to tab: #{tab_atom}")

    socket =
      socket
      |> assign(:active_tab, tab_atom)
      |> assign(:view_stack, [tab_atom])
      |> assign(:selected_home, nil)
      |> assign(:selected_provider, nil)

    # Don't push map updates during tab switch - the map hook will request data when it mounts
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_homes", %{"search" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:page, 1)

    # Don't push map updates - the map hook will request data when it mounts
    {:noreply, socket}
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

    {:noreply, socket |> assign(:sort_by, sort_by) |> assign(:sort_direction, sort_direction) |> assign(:page, 1)}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    new_page = max(socket.assigns.page - 1, 1)
    socket = socket |> assign(:page, new_page)
    {:noreply, socket}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    pagination = get_pagination_info(socket.assigns)
    new_page = min(socket.assigns.page + 1, pagination.total_pages)
    socket = socket |> assign(:page, new_page)
    {:noreply, socket}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page}, socket) do
    page_num = String.to_integer(page)
    pagination = get_pagination_info(socket.assigns)
    new_page = max(1, min(page_num, pagination.total_pages))
    socket = socket |> assign(:page, new_page)
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_per_page", %{"per_page" => per_page}, socket) do
    per_page_num = String.to_integer(per_page)
    socket = socket |> assign(:per_page, per_page_num) |> assign(:page, 1)
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_pause", _params, socket) do
    require Logger
    Logger.info("DashboardLive: Pausing simulation")

    # Publish pause command to WAMP
    CortexIqDashboard.WampSubscriber.publish_control_command("pause")

    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_resume", _params, socket) do
    require Logger
    Logger.info("DashboardLive: Resuming simulation")

    # Publish resume command to WAMP
    CortexIqDashboard.WampSubscriber.publish_control_command("resume")

    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_reset", _params, socket) do
    require Logger
    Logger.info("DashboardLive: Resetting simulation")

    # Publish reset command to WAMP
    CortexIqDashboard.WampSubscriber.publish_control_command("reset")

    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_set_speed", %{"speed" => speed_str}, socket) do
    require Logger
    speed = String.to_integer(speed_str)
    Logger.info("DashboardLive: Setting simulation speed to #{speed}x")

    # Publish set_speed command to WAMP
    CortexIqDashboard.WampSubscriber.publish_control_command("set_speed", %{"speed" => speed})

    {:noreply, socket}
  end

  # Home detail view
  defp render_home_detail(assigns) do
    home_state = Map.get(assigns.home_states, assigns.selected_home, %{})
    home_history = Map.get(assigns.home_history, assigns.selected_home, [])
    contract = Map.get(assigns.home_contracts, assigns.selected_home, %{})
    balance = Map.get(assigns.home_balances, assigns.selected_home, %{})

    assigns = assign(assigns,
      home_state: home_state,
      home_history: home_history,
      contract: contract,
      balance: balance
    )

    ~H"""
    <div class="space-y-6">
      <!-- Detail Header -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <h2 class="text-2xl font-bold text-blue-400 mb-2">{@selected_home}</h2>
        <div class="text-gray-400 text-sm">
          {Map.get(@home_state, :city, "Unknown")}, {Map.get(@home_state, :postal_code, "")}
        </div>
        <%= if Map.get(@home_state, :region) do %>
          <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold rounded-full bg-blue-600 text-white">
            {CortexIqCore.Geography.region_name(
              String.to_atom(Map.get(@home_state, :region, "unknown"))
            )}
          </span>
        <% end %>
      </div>

      <!-- Current Metrics -->
      <div class="grid grid-cols-3 gap-4">
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <div class="text-gray-400 text-xs">Production</div>
          <div class="text-3xl font-bold text-green-400">
            {format_power(Map.get(@home_state, :production_kw, 0.0))}
          </div>
        </div>
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <div class="text-gray-400 text-xs">Consumption</div>
          <div class="text-3xl font-bold text-red-400">
            {format_power(Map.get(@home_state, :consumption_kw, 0.0))}
          </div>
        </div>
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <div class="text-gray-400 text-xs">Battery</div>
          <div class="text-3xl font-bold text-blue-400">
            {Float.round(Map.get(@home_state, :state_of_charge_pct, 0), 1)}%
          </div>
        </div>
      </div>

      <!-- Historical Sparklines -->
      <%= if length(@home_history) > 1 do %>
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h3 class="text-lg font-semibold text-gray-300 mb-3">
            Production vs Consumption (Last 5 min)
          </h3>
          <div
            id={"power-sparkline-#{@selected_home}"}
            phx-hook="PowerSparkline"
            phx-update="ignore"
            data-history={Jason.encode!(@home_history)}
          >
          </div>
        </div>

        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h3 class="text-lg font-semibold text-gray-300 mb-3">Battery Charge (Last 5 min)</h3>
          <div
            id={"battery-sparkline-#{@selected_home}"}
            phx-hook="BatterySparkline"
            phx-update="ignore"
            data-history={Jason.encode!(@home_history)}
          >
          </div>
        </div>
      <% end %>

      <!-- Financial Performance - Key Selling Point! -->
      <div class="bg-gradient-to-r from-purple-900/50 to-blue-900/50 rounded-lg p-6 border-2 border-purple-500/50">
        <h3 class="text-xl font-bold text-purple-300 mb-4">💰 Cost Optimization Performance</h3>
        <div class="grid grid-cols-3 gap-4">
          <div class="bg-gray-800/80 rounded-lg p-4">
            <div class="text-gray-400 text-xs mb-1">Energy Bought</div>
            <div class="text-2xl font-bold text-red-400">
              {Float.round(Map.get(@balance, :energy_bought_kwh, 0.0), 1)} kWh
            </div>
            <div class="text-sm text-gray-500 mt-1">
              Cost: €{Float.round(Map.get(@balance, :cost_paid, 0.0), 2)}
            </div>
          </div>
          <div class="bg-gray-800/80 rounded-lg p-4">
            <div class="text-gray-400 text-xs mb-1">Energy Sold</div>
            <div class="text-2xl font-bold text-green-400">
              {Float.round(Map.get(@balance, :energy_sold_kwh, 0.0), 1)} kWh
            </div>
            <div class="text-sm text-gray-500 mt-1">
              Revenue: €{Float.round(Map.get(@balance, :revenue_received, 0.0), 2)}
            </div>
          </div>
          <div class="bg-gray-800/80 rounded-lg p-4">
            <div class="text-gray-400 text-xs mb-1">Net Cost</div>
            <div class={"text-2xl font-bold " <> if Map.get(@balance, :net_cost, 0.0) < 0, do: "text-green-400", else: "text-yellow-400"}>
              €{Float.round(Map.get(@balance, :net_cost, 0.0), 2)}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              Balance: {Float.round(Map.get(@balance, :net_balance_kwh, 0.0), 1)} kWh
            </div>
          </div>
        </div>
      </div>

      <!-- CortexIQ Savings Performance -->
      <%= if Map.get(@balance, :contract_switches_count, 0) > 0 do %>
        <div class="bg-gradient-to-r from-green-900/50 to-blue-900/50 rounded-lg p-6 border-2 border-green-500/50">
          <h3 class="text-xl font-bold text-green-300 mb-4">✨ CortexIQ Savings Performance</h3>
          <p class="text-sm text-gray-400 mb-4">
            Your home has switched contracts {Map.get(@balance, :contract_switches_count, 0)} time(s) to maximize savings!
          </p>
          <div class="grid grid-cols-4 gap-4">
            <div class="bg-gray-800/80 rounded-lg p-4">
              <div class="text-gray-400 text-xs mb-1">Total Gross Savings</div>
              <div class="text-2xl font-bold text-green-400">
                €{Float.round(Map.get(@balance, :cortexiq_total_savings, 0.0), 2)}
              </div>
              <div class="text-xs text-gray-500 mt-1">Before commission</div>
            </div>
            <div class="bg-gray-800/80 rounded-lg p-4">
              <div class="text-gray-400 text-xs mb-1">CortexIQ Commission</div>
              <div class="text-2xl font-bold text-yellow-400">
                €{Float.round(Map.get(@balance, :cortexiq_total_commission, 0.0), 2)}
              </div>
              <div class="text-xs text-gray-500 mt-1">20% service fee</div>
            </div>
            <div class="bg-gray-800/80 rounded-lg p-4">
              <div class="text-gray-400 text-xs mb-1">Your Net Savings</div>
              <div class="text-2xl font-bold text-blue-400">
                €{Float.round(Map.get(@balance, :cortexiq_net_savings, 0.0), 2)}
              </div>
              <div class="text-xs text-gray-500 mt-1">80% goes to you</div>
            </div>
            <div class="bg-gray-800/80 rounded-lg p-4">
              <div class="text-gray-400 text-xs mb-1">Your ROI</div>
              <div class="text-2xl font-bold text-purple-400">
                <%= if Map.get(@balance, :cortexiq_total_commission, 0.0) > 0 do %>
                  {Float.round(Map.get(@balance, :cortexiq_net_savings, 0.0) / Map.get(@balance, :cortexiq_total_commission, 1.0) * 100, 0)}%
                <% else %>
                  0%
                <% end %>
              </div>
              <div class="text-xs text-gray-500 mt-1">Return on fees paid</div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Current Contract -->
      <%= if Map.get(@contract, :provider_id) do %>
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h3 class="text-lg font-semibold text-gray-300 mb-4">📋 Current Energy Contract</h3>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <div class="text-sm text-gray-400">Provider</div>
              <div class="text-lg font-bold text-blue-400">
                {get_provider_name(Map.get(@contract, :provider_id, "Unknown"))}
              </div>
              <div class="text-xs text-gray-500 mt-1">
                Contract: {Map.get(@contract, :contract_id, "N/A")}
              </div>
            </div>
            <div>
              <div class="text-sm text-gray-400">Contract Start</div>
              <div class="text-sm text-gray-300">
                <%= if Map.get(@contract, :signed_at) do %>
                  {Calendar.strftime(Map.get(@contract, :signed_at), "%Y-%m-%d %H:%M")}
                <% else %>
                  Not available
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <div class="bg-yellow-900/30 rounded-lg p-6 border border-yellow-600/50">
          <div class="flex items-center gap-3">
            <div class="text-3xl">⚠️</div>
            <div>
              <div class="text-lg font-semibold text-yellow-300">No Active Contract</div>
              <div class="text-sm text-gray-400">This home is currently on spot market pricing</div>
            </div>
          </div>
        </div>
      <% end %>

    </div>
    """
  end

  # Provider detail view
  defp render_provider_detail(assigns) do
    provider_state = Map.get(assigns.provider_states, assigns.selected_provider, %{})
    provider_history = Map.get(assigns.provider_history, assigns.selected_provider, [])

    assigns = assign(assigns, provider_state: provider_state, provider_history: provider_history)

    ~H"""
    <div class="space-y-6">
      <!-- Detail Header -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <h2 class="text-2xl font-bold text-yellow-400 mb-2">
          {Map.get(@provider_state, :provider_name, @selected_provider)}
        </h2>
        <div class="text-gray-400 text-sm">
          Provider ID: {@selected_provider}
        </div>
        <%= if Map.get(@provider_state, :strategy) do %>
          <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold rounded-full bg-yellow-600 text-white">
            {format_strategy(Map.get(@provider_state, :strategy))}
          </span>
        <% end %>
      </div>

      <!-- Contract Offer Details -->
      <%= if Map.get(@provider_state, :contract_offer) do %>
        <% contract = Map.get(@provider_state, :contract_offer) %>
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h3 class="text-lg font-semibold text-gray-300 mb-4">12-Month Contract Offer</h3>

          <!-- Day/Night Pricing Grid -->
          <div class="grid grid-cols-2 gap-4 mb-4">
            <div class="bg-gray-700 rounded-lg p-4">
              <div class="text-yellow-400 text-sm font-semibold mb-3">☀️ Day Rates (6am-6pm)</div>
              <div class="flex justify-between items-center mb-2">
                <span class="text-gray-400 text-sm">Buy:</span>
                <span class="text-green-400 font-semibold text-lg">€{Float.round(Map.get(contract, :day_buy_price, 0), 4)}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-400 text-sm">Sell:</span>
                <span class="text-blue-400 font-semibold text-lg">€{Float.round(Map.get(contract, :day_sell_price, 0), 4)}</span>
              </div>
            </div>

            <div class="bg-gray-700 rounded-lg p-4">
              <div class="text-purple-400 text-sm font-semibold mb-3">🌙 Night Rates (6pm-6am)</div>
              <div class="flex justify-between items-center mb-2">
                <span class="text-gray-400 text-sm">Buy:</span>
                <span class="text-green-400 font-semibold text-lg">€{Float.round(Map.get(contract, :night_buy_price, 0), 4)}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-400 text-sm">Sell:</span>
                <span class="text-blue-400 font-semibold text-lg">€{Float.round(Map.get(contract, :night_sell_price, 0), 4)}</span>
              </div>
            </div>
          </div>

          <!-- Contract Terms -->
          <div class="space-y-3 bg-gray-700 rounded-lg p-4">
            <div class="flex justify-between items-center text-sm">
              <span class="text-gray-400">Switching Discount:</span>
              <span class="text-yellow-400 font-semibold">€{Float.round(Map.get(contract, :switching_discount, 0), 2)}</span>
            </div>
            <div class="flex justify-between items-center text-sm">
              <span class="text-gray-400">Min. Monthly Usage:</span>
              <span class="text-white font-semibold">{Float.round(Map.get(contract, :minimum_monthly_kwh, 0), 0)} kWh</span>
            </div>
            <div class="flex justify-between items-center text-sm">
              <span class="text-gray-400">Contract Duration:</span>
              <span class="text-white font-semibold">{Map.get(contract, :duration_months, 12)} months</span>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Market Share -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <h3 class="text-lg font-semibold text-gray-300 mb-2">Market Share</h3>
        <% connected_homes = count_homes_by_provider(@home_states, @selected_provider) %>
        <div class="text-4xl font-bold text-yellow-400 mb-1">
          {connected_homes}
        </div>
        <div class="text-sm text-gray-500">homes connected</div>
      </div>

    </div>
    """
  end

  # Breadcrumb navigation
  defp render_breadcrumbs(assigns) do
    ~H"""
    <%= if length(@view_stack) > 1 do %>
      <div class="mb-4 flex items-center gap-2 text-sm">
        <%= for {item, index} <- Enum.with_index(@view_stack) do %>
          <%= if index > 0 do %>
            <span class="text-gray-600">/</span>
          <% end %>

          <%= case item do %>
            <% :overview -> %>
              <button
                phx-click="switch_tab"
                phx-value-tab="overview"
                class="text-blue-400 hover:text-blue-300"
              >
                Overview
              </button>
            <% :homes -> %>
              <button
                phx-click="navigate_to_list"
                phx-value-tab="homes"
                class={
                  if index == length(@view_stack) - 1,
                    do: "text-gray-300",
                    else: "text-blue-400 hover:text-blue-300"
                }
              >
                Homes
              </button>
            <% :providers -> %>
              <button
                phx-click="navigate_to_list"
                phx-value-tab="providers"
                class={
                  if index == length(@view_stack) - 1,
                    do: "text-gray-300",
                    else: "text-blue-400 hover:text-blue-300"
                }
              >
                Providers
              </button>
            <% {:home_detail, home_id} -> %>
              <span class="text-gray-300">{home_id}</span>
            <% {:provider_detail, provider_id} -> %>
              <span class="text-gray-300">{get_provider_name(provider_id)}</span>
            <% _ -> %>
              <span class="text-gray-500">Unknown</span>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Render homes list with search/filter/sort
  defp render_homes_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Toolbar: Search + Pagination -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <% pagination = get_pagination_info(assigns) %>

        <!-- Top Row: Search + Info -->
        <div class="flex gap-4 items-center mb-4">
          <div class="flex-1">
            <input
              type="text"
              placeholder="Search by Location..."
              value={@search_query}
              phx-keyup="search_homes"
              phx-debounce="300"
              name="search"
              class="w-full px-4 py-2 bg-gray-900 border border-gray-600 rounded-lg text-gray-100 placeholder-gray-500 focus:border-blue-500 focus:outline-none"
            />
          </div>
          <div class="text-gray-400 text-sm whitespace-nowrap">
            Showing {pagination.showing_from}-{pagination.showing_to} of {pagination.total_homes} homes
          </div>
        </div>

        <!-- Bottom Row: Pagination Controls -->
        <%= if pagination.total_pages > 1 do %>
          <div class="flex items-center justify-between border-t border-gray-700 pt-4">
            <!-- Per Page Selector -->
            <div class="flex items-center gap-2">
              <span class="text-sm text-gray-400">Show:</span>
              <select
                phx-change="change_per_page"
                name="per_page"
                class="px-3 py-1 bg-gray-900 border border-gray-600 rounded text-sm text-gray-300 focus:border-blue-500 focus:outline-none"
              >
                <%= for option <- [10, 25, 50, 100] do %>
                  <option value={option} selected={@per_page == option}>{option}</option>
                <% end %>
              </select>
              <span class="text-sm text-gray-400">per page</span>
            </div>

            <!-- Page Navigation -->
            <div class="flex items-center gap-2">
              <!-- Previous Button -->
              <button
                phx-click="prev_page"
                disabled={@page == 1}
                class={"px-3 py-1 rounded text-sm font-semibold transition-colors #{if @page == 1, do: "bg-gray-700 text-gray-500 cursor-not-allowed", else: "bg-blue-600 hover:bg-blue-700 text-white"}"}
              >
                ← Prev
              </button>

              <!-- Page Numbers -->
              <div class="flex gap-1">
                <%= for page_num <- pagination_range(pagination.current_page, pagination.total_pages) do %>
                  <%= if page_num == :ellipsis do %>
                    <span class="px-3 py-1 text-gray-500">...</span>
                  <% else %>
                    <button
                      phx-click="goto_page"
                      phx-value-page={page_num}
                      class={"px-3 py-1 rounded text-sm font-semibold transition-colors #{if page_num == @page, do: "bg-blue-600 text-white", else: "bg-gray-700 hover:bg-gray-600 text-gray-300"}"}
                    >
                      {page_num}
                    </button>
                  <% end %>
                <% end %>
              </div>

              <!-- Next Button -->
              <button
                phx-click="next_page"
                disabled={@page == pagination.total_pages}
                class={"px-3 py-1 rounded text-sm font-semibold transition-colors #{if @page == pagination.total_pages, do: "bg-gray-700 text-gray-500 cursor-not-allowed", else: "bg-blue-600 hover:bg-blue-700 text-white"}"}
              >
                Next →
              </button>
            </div>

            <!-- Page Info -->
            <div class="text-sm text-gray-400 whitespace-nowrap">
              Page {@page} of {pagination.total_pages}
            </div>
          </div>
        <% end %>
      </div>

      <!-- Map Section - Shows Currently Visible Homes -->
      <% visible_home_count = length(get_filtered_homes(assigns)) %>
      <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
        <div class="p-4 border-b border-gray-700">
          <h2 class="text-xl font-bold text-gray-100">Homes Map</h2>
          <p class="text-sm text-gray-400 mt-1">Showing {visible_home_count} homes on current page</p>
        </div>
        <!-- Map Container -->
        <div
          id="belgium-map"
          phx-hook="BelgiumMap"
          phx-update="ignore"
          data-locations={Jason.encode!(@locations)}
          data-selected-region={@selected_region}
          style="height: 500px;"
        >
        </div>
        <!-- Map Legend -->
        <div class="p-4 bg-gray-700 border-t border-gray-700">
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

      <!-- Homes Table -->
      <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="bg-gray-900 border-b border-gray-700">
              <tr>
                <%= for {column, label} <- [
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
                <tr class="hover:bg-gray-700 transition-colors">
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
                      €{Float.round(net_cost, 2)}
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

  defp render_providers_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Search and Filter Controls -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="flex gap-4 items-center">
          <div class="flex-1">
            <div class="text-sm text-gray-400">
              {Enum.count(@provider_states)} providers competing for market share
            </div>
          </div>
        </div>
      </div>

      <!-- Providers Table -->
      <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="bg-gray-900 border-b border-gray-700">
              <tr>
                <th class="px-4 py-3 text-left text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Provider
                </th>
                <th class="px-4 py-3 text-left text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Strategy
                </th>
                <th class="px-4 py-3 text-right text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Market Share
                </th>
                <th class="px-4 py-3 text-right text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Customers
                </th>
                <th class="px-4 py-3 text-right text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Day Buy
                </th>
                <th class="px-4 py-3 text-right text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Night Buy
                </th>
                <th class="px-4 py-3 text-right text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Avg Spread
                </th>
                <th class="px-4 py-3 text-right text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Discount
                </th>
                <th class="px-4 py-3 text-left text-gray-400 font-semibold text-xs uppercase tracking-wide">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
              <%= for {provider_id, provider} <- Enum.sort_by(@provider_states, fn {_id, p} -> -(Map.get(p, :market_share_percent, 0.0)) end) do %>
                <% market_share = safe_float(Map.get(provider, :market_share_percent, 0.0)) %>
                <% day_buy = safe_float(Map.get(provider, :day_buy_price, 0.0)) %>
                <% night_buy = safe_float(Map.get(provider, :night_buy_price, 0.0)) %>
                <% day_sell = safe_float(Map.get(provider, :day_sell_price, 0.0)) %>
                <% night_sell = safe_float(Map.get(provider, :night_sell_price, 0.0)) %>
                <% discount = safe_float(Map.get(provider, :switching_discount, 0.0)) %>
                <% avg_spread = ((day_buy - day_sell) + (night_buy - night_sell)) / 2 %>

                <tr class="hover:bg-gray-700 transition-colors">
                  <td class="px-4 py-3">
                    <div class="font-semibold text-sm text-yellow-400">{Map.get(provider, :provider_name, provider_id)}</div>
                    <div class="text-xs text-gray-500 font-mono">{provider_id}</div>
                  </td>
                  <td class="px-4 py-3">
                    <span class="px-2 py-1 text-xs font-semibold rounded bg-blue-600 text-white">
                      {format_strategy(Map.get(provider, :strategy, "unknown"))}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="flex items-center justify-end gap-2">
                      <div class="flex-1 bg-gray-700 rounded-full h-2 w-16">
                        <div
                          class="h-full rounded-full bg-gradient-to-r from-blue-500 to-green-500"
                          style={"width: #{Float.round(market_share, 1)}%"}>
                        </div>
                      </div>
                      <span class="text-sm font-bold text-green-400 w-12">
                        {Float.round(market_share, 1)}%
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="text-sm font-semibold text-white">{Map.get(provider, :active_contracts, 0)}</div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="text-sm text-red-400">€{Float.round(day_buy, 3)}</div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="text-sm text-blue-400">€{Float.round(night_buy, 3)}</div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="text-sm text-purple-400">€{Float.round(avg_spread, 3)}</div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="text-sm text-yellow-400">€{Float.round(discount, 0)}</div>
                  </td>
                  <td class="px-4 py-3">
                    <button
                      phx-click="select_provider"
                      phx-value-provider_id={provider_id}
                      class="px-3 py-1 bg-yellow-600 hover:bg-yellow-700 rounded text-xs font-semibold transition-colors"
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

        <!-- Simulation Controls -->
        <div class="mb-6 bg-gradient-to-r from-indigo-900/50 to-purple-900/50 rounded-lg p-4 border border-indigo-500/50">
          <div class="flex items-center justify-between gap-6">
            <!-- Simulation Time Display -->
            <div class="flex items-center gap-4">
              <div>
                <div class="text-xs text-gray-400 uppercase tracking-wide">Simulation Date</div>
                <div class="flex items-center gap-3">
                  <div class="text-2xl font-bold text-indigo-300 font-mono">
                    {format_simulation_date(@simulation_time)}
                  </div>
                  <div class="text-3xl" title={day_night_label(@simulation_time)}>
                    {day_night_icon(@simulation_time)}
                  </div>
                </div>
              </div>
              <div class="h-12 w-px bg-gray-700"></div>
              <div>
                <div class="text-xs text-gray-400 uppercase tracking-wide">Status</div>
                <div class="text-lg font-semibold">
                  <%= if @simulation_paused do %>
                    <span class="text-yellow-400">⏸ PAUSED</span>
                  <% else %>
                    <span class="text-green-400">▶ Running</span>
                  <% end %>
                </div>
              </div>
              <div class="h-12 w-px bg-gray-700"></div>
              <div>
                <div class="text-xs text-gray-400 uppercase tracking-wide">Speed</div>
                <div class="text-lg font-bold text-purple-300">
                  {format_speed(@simulation_speed)}
                </div>
              </div>
            </div>

            <!-- Control Buttons -->
            <div class="flex items-center gap-3">
              <!-- Play/Pause -->
              <%= if @simulation_paused do %>
                <button
                  phx-click="simulation_resume"
                  class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg font-semibold transition-all flex items-center gap-2"
                  title="Resume Simulation"
                >
                  <span class="text-xl">▶</span>
                  Resume
                </button>
              <% else %>
                <button
                  phx-click="simulation_pause"
                  class="px-4 py-2 bg-yellow-600 hover:bg-yellow-700 text-white rounded-lg font-semibold transition-all flex items-center gap-2"
                  title="Pause Simulation"
                >
                  <span class="text-xl">⏸</span>
                  Pause
                </button>
              <% end %>

              <!-- Speed Controls -->
              <div class="flex gap-1 bg-gray-800 rounded-lg p-1">
                <%= for {speed, label} <- [{1, "1x"}, {100, "100x"}, {1000, "1K"}, {10000, "10K"}, {105120, "Max"}] do %>
                  <button
                    phx-click="simulation_set_speed"
                    phx-value-speed={speed}
                    class={"px-3 py-1 rounded text-sm font-semibold transition-all #{if @simulation_speed == speed, do: "bg-purple-600 text-white", else: "text-gray-400 hover:text-white hover:bg-gray-700"}"}
                    title={"Set speed to #{speed}x"}
                  >
                    {label}
                  </button>
                <% end %>
              </div>

              <!-- Reset -->
              <button
                phx-click="simulation_reset"
                class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg font-semibold transition-all flex items-center gap-2"
                title="Reset to 2025-01-01"
                data-confirm="Reset simulation to 2025-01-01? This will restart all homes and providers."
              >
                <span class="text-xl">⟳</span>
                Reset
              </button>
            </div>
          </div>
        </div>

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

        <!-- Breadcrumb Navigation -->
        <%= render_breadcrumbs(assigns) %>

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

    <!-- Stats Cards -->
        <div class="grid grid-cols-6 gap-4 mb-6">
          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Connected Homes</div>
            <div class="text-2xl font-bold text-green-400">{@stats.homes}</div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Energy Bought</div>
            <div class="text-lg font-bold text-red-400">
              {format_energy(@stats.total_energy_bought_kwh)}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              €{Float.round(@stats.total_cost_paid, 2)}
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Energy Sold</div>
            <div class="text-lg font-bold text-green-400">
              {format_energy(@stats.total_energy_sold_kwh)}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              €{Float.round(@stats.total_revenue_received, 2)}
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Net Balance</div>
            <div class={"text-lg font-bold #{if @stats.total_energy_bought_kwh - @stats.total_energy_sold_kwh > 0, do: "text-red-400", else: "text-green-400"}"}>
              {format_energy(abs(@stats.total_energy_bought_kwh - @stats.total_energy_sold_kwh))}
            </div>
            <div class="text-xs text-gray-500 mt-1">
              Net: €{Float.round(@stats.total_cost_paid - @stats.total_revenue_received, 2)}
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

    <!-- CortexIQ Financial Summary -->
        <div class="mb-6">
          <h3 class="text-sm font-semibold text-gray-400 mb-3">CortexIQ Platform Revenue - Savings Optimization Service</h3>
          <div class="grid grid-cols-4 gap-4">
            <!-- Total Customer Savings -->
            <div class="bg-gradient-to-br from-green-900 to-green-800 rounded-lg p-4 border-2 border-green-600">
              <div class="text-gray-300 text-xs">Customer Savings (Gross)</div>
              <div class="text-3xl font-bold text-green-300">
                €{Float.round(@stats.cortexiq_total_savings, 2)}
              </div>
              <div class="text-xs text-green-400 mt-1">
                From {@stats.contract_switches} switches
              </div>
            </div>

            <!-- CortexIQ Commission -->
            <div class="bg-gradient-to-br from-yellow-900 to-yellow-800 rounded-lg p-4 border-2 border-yellow-600">
              <div class="text-gray-300 text-xs">CortexIQ Revenue (20%)</div>
              <div class="text-3xl font-bold text-yellow-300">
                €{Float.round(@stats.cortexiq_total_commission, 2)}
              </div>
              <div class="text-xs text-yellow-400 mt-1">
                Platform commission
              </div>
            </div>

            <!-- Net Customer Savings -->
            <div class="bg-gradient-to-br from-blue-900 to-blue-800 rounded-lg p-4 border-2 border-blue-600">
              <div class="text-gray-300 text-xs">Customer Savings (Net)</div>
              <div class="text-3xl font-bold text-blue-300">
                €{Float.round(@stats.cortexiq_net_savings, 2)}
              </div>
              <div class="text-xs text-blue-400 mt-1">
                After commission
              </div>
            </div>

            <!-- ROI for Customers -->
            <div class="bg-gradient-to-br from-purple-900 to-purple-800 rounded-lg p-4 border-2 border-purple-600">
              <div class="text-gray-300 text-xs">Customer ROI</div>
              <% roi = if @stats.cortexiq_total_commission > 0, do: Float.round((@stats.cortexiq_net_savings / @stats.cortexiq_total_commission) * 100, 1), else: 0.0 %>
              <div class="text-3xl font-bold text-purple-300">
                {roi}%
              </div>
              <div class="text-xs text-purple-400 mt-1">
                Savings per € paid
              </div>
            </div>
          </div>
        </div>

    <!-- Cumulative Savings Chart -->
        <%= if length(@overview.savings_history || []) > 0 do %>
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
          <%= if @selected_home do %>
            <%= render_home_detail(assigns) %>
          <% else %>
            <%= render_homes_list(assigns) %>
          <% end %>
        <% end %>

    <!-- Providers Tab Content -->
        <%= if @active_tab == :providers do %>
          <%= if @selected_provider do %>
            <%= render_provider_detail(assigns) %>
          <% else %>
            <%= render_providers_list(assigns) %>
          <% end %>
        <% end %>

      </div>
    </div>
    """
  end

  # Helper functions for homes list

  defp get_filtered_homes(assigns) do
    get_filtered_homes_all(assigns)
    |> paginate_homes(assigns.page, assigns.per_page)
  end

  defp get_filtered_homes_all(assigns) do
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
            get_in(assigns.home_states, [home.home_id, :state_of_charge_pct]) || 0.0

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

  defp paginate_homes(homes, page, per_page) do
    homes
    |> Enum.drop((page - 1) * per_page)
    |> Enum.take(per_page)
  end

  defp get_pagination_info(assigns) do
    total_homes = get_filtered_homes_all(assigns) |> length()
    total_pages = max(ceil(total_homes / assigns.per_page), 1)

    %{
      current_page: assigns.page,
      total_pages: total_pages,
      per_page: assigns.per_page,
      total_homes: total_homes,
      showing_from: min((assigns.page - 1) * assigns.per_page + 1, total_homes),
      showing_to: min(assigns.page * assigns.per_page, total_homes)
    }
  end

  # Generate page numbers with ellipsis for pagination UI
  # Shows: [1, 2, 3, ..., 8, 9, 10] or [1, ..., 5, 6, 7, ..., 10]
  defp pagination_range(current_page, total_pages) when total_pages <= 7 do
    # Show all pages if 7 or fewer
    1..total_pages |> Enum.to_list()
  end

  defp pagination_range(current_page, total_pages) when current_page <= 4 do
    # Near start: [1, 2, 3, 4, 5, ..., total]
    [1, 2, 3, 4, 5, :ellipsis, total_pages]
  end

  defp pagination_range(current_page, total_pages) when current_page >= total_pages - 3 do
    # Near end: [1, ..., total-4, total-3, total-2, total-1, total]
    [1, :ellipsis, total_pages - 4, total_pages - 3, total_pages - 2, total_pages - 1, total_pages]
  end

  defp pagination_range(current_page, total_pages) do
    # Middle: [1, ..., current-1, current, current+1, ..., total]
    [1, :ellipsis, current_page - 1, current_page, current_page + 1, :ellipsis, total_pages]
  end

  defp toggle_direction(:asc), do: :desc
  defp toggle_direction(:desc), do: :asc

  defp battery_color(percent) when percent > 75, do: "bg-green-500"
  defp battery_color(percent) when percent > 50, do: "bg-blue-500"
  defp battery_color(percent) when percent > 25, do: "bg-yellow-500"
  defp battery_color(_), do: "bg-red-500"

  # Event type color coding
  defp event_type_color(type) when is_binary(type) do
    cond do
      String.contains?(type, "production") -> "text-green-400"
      String.contains?(type, "consumption") -> "text-red-400"
      String.contains?(type, "storage") or String.contains?(type, "battery") -> "text-blue-400"
      String.contains?(type, "contract") -> "text-purple-400"
      String.contains?(type, "tariff") or String.contains?(type, "offer") -> "text-yellow-400"
      String.contains?(type, "balance") or String.contains?(type, "trade") -> "text-cyan-400"
      true -> "text-gray-400"
    end
  end

  defp event_type_color(_), do: "text-gray-400"

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

  defp format_simulation_datetime(nil), do: "Loading..."

  defp format_simulation_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_simulation_datetime(_), do: "Invalid"

  # Format simulation date (just YYYY-MM-DD)
  defp format_simulation_date(nil), do: "Loading..."

  defp format_simulation_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end

  defp format_simulation_date(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d")
      _ -> "Invalid"
    end
  end

  defp format_simulation_date(_), do: "Invalid"

  # Day/night icon (day = 6AM-6PM, night = 6PM-6AM)
  defp day_night_icon(nil), do: "⏳"

  defp day_night_icon(%DateTime{} = dt) do
    if is_daytime?(dt), do: "☀️", else: "🌙"
  end

  defp day_night_icon(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> day_night_icon(dt)
      _ -> "⏳"
    end
  end

  defp day_night_icon(_), do: "⏳"

  # Day/night label for tooltip
  defp day_night_label(nil), do: "No time data"

  defp day_night_label(%DateTime{} = dt) do
    hour = dt.hour
    if is_daytime?(dt) do
      "Daytime (#{format_hour(hour)})"
    else
      "Nighttime (#{format_hour(hour)})"
    end
  end

  defp day_night_label(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> day_night_label(dt)
      _ -> "No time data"
    end
  end

  defp day_night_label(_), do: "No time data"

  # Helper: check if it's daytime (6AM to 6PM)
  defp is_daytime?(%DateTime{hour: hour}) do
    hour >= 6 and hour < 18
  end

  # Helper: format hour for display
  defp format_hour(hour) when hour == 0, do: "12 AM"
  defp format_hour(hour) when hour < 12, do: "#{hour} AM"
  defp format_hour(hour) when hour == 12, do: "12 PM"
  defp format_hour(hour), do: "#{hour - 12} PM"

  defp format_speed(speed) when is_integer(speed) and speed >= 100_000 do
    "#{div(speed, 1000)}K×"
  end

  defp format_speed(speed) when is_integer(speed) and speed >= 1000 do
    "#{Float.round(speed / 1000, 1)}K×"
  end

  defp format_speed(speed) when is_integer(speed) do
    "#{speed}×"
  end

  defp format_speed(_), do: "1×"

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
    battery_percent = Map.get(kwargs, "state_of_charge_pct", 0) |> Float.round(1)

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
            battery_percent: Map.get(kwargs, "state_of_charge_pct", 50.0),
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
            battery_percent: Map.get(kwargs, "state_of_charge_pct", 50.0),
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
      battery_percent: Map.get(updated_state, :state_of_charge_pct, 50.0)
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
        {sum + Map.get(state, :state_of_charge_pct, 0.0), count + 1}
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

  # Helper to safely convert values to float
  defp safe_float(val) when is_float(val), do: val
  defp safe_float(val) when is_integer(val), do: val * 1.0
  defp safe_float(nil), do: 0.0
  defp safe_float(_), do: 0.0

  # Push home state updates to map JavaScript hook (only for filtered homes on current page)
  defp push_home_updates_to_map(socket, _home_states) do
    # Get only the currently visible filtered homes
    visible_homes = get_filtered_homes(socket.assigns)

    # Push each home individually (map aggregates by city on JS side)
    Enum.reduce(visible_homes, socket, fn home_data, acc_socket ->
      home_id = home_data.home_id

      # Get actual state from HomesViewAggregator (via home_states)
      case Map.get(socket.assigns.home_states, home_id) do
        nil ->
          acc_socket

        state ->
          # Convert kW to W (database stores in kW, map expects W)
          # Handle nil values safely
          production_kw = state.production_kw || 0.0
          consumption_kw = state.consumption_kw || 0.0
          production_w = production_kw * 1000.0
          consumption_w = consumption_kw * 1000.0

          # Get location (already in state from database)
          city = state.location || home_data.location

          # Push event to map hook with proper data structure
          push_event(acc_socket, "update_home", %{
            home_id: home_id,
            city: city,
            state: %{
              production_w: production_w,
              consumption_w: consumption_w,
              battery_percent: state.battery_percent || 50.0,
              state_of_charge_pct: state.battery_percent || 50.0,
              city: city
            }
          })
      end
    end)
  end

  # Database loaders - load initial state from persisted data

  defp load_home_states_from_db do
    # Query HomesViewAggregator (in-memory)
    homes = HomesViewAggregator.get_homes()

    unique_homes = homes |> Enum.map(& &1.home_id) |> MapSet.new()

    home_states =
      homes
      |> Enum.map(fn home ->
        # Handle both HomeState (DB) with battery_percent and HomeAggregate (in-memory) with state_of_charge_pct
        battery_pct = Map.get(home, :battery_percent) || Map.get(home, :state_of_charge_pct) || 0.0

        {home.home_id, %{
          production_kw: home.production_kw || 0.0,  # Keep in kW
          consumption_kw: home.consumption_kw || 0.0,  # Keep in kW
          battery_percent: battery_pct,
          city: home.location,
          postal_code: home.postal_code,
          region: home.region
        }}
      end)
      |> Enum.into(%{})

    home_contracts =
      homes
      |> Enum.filter(& &1.provider_id)
      |> Enum.map(fn home ->
        {home.home_id, %{
          provider_id: home.provider_id,
          contract_id: home.contract_id,
          end_date: home.contract_expires_at
        }}
      end)
      |> Enum.into(%{})

    home_balances =
      homes
      |> Enum.map(fn home ->
        {home.home_id, %{
          energy_bought_kwh: Map.get(home, :energy_bought_kwh, 0.0),
          energy_sold_kwh: Map.get(home, :energy_sold_kwh, 0.0),
          net_balance_kwh: Map.get(home, :net_balance_kwh, 0.0),
          cost_paid: Map.get(home, :cost_paid, 0.0),
          revenue_received: Map.get(home, :revenue_received, 0.0),
          net_cost: Map.get(home, :net_cost, 0.0),
          cortexiq_total_commission: Map.get(home, :cortexiq_total_commission, 0.0),
          cortexiq_total_savings: Map.get(home, :cortexiq_total_savings, 0.0),
          cortexiq_net_savings: Map.get(home, :cortexiq_net_savings, 0.0),
          contract_switches_count: Map.get(home, :contract_switches_count, 0)
        }}
      end)
      |> Enum.into(%{})

    {home_states, unique_homes, home_contracts, home_balances}
  end

  defp load_provider_states_from_db do
    # Query ProvidersViewAggregator (in-memory, includes calculated market share)
    providers = ProvidersViewAggregator.get_providers()

    unique_providers = providers |> Enum.map(& &1.provider_id) |> MapSet.new()

    provider_states =
      providers
      |> Enum.map(fn provider ->
        {provider.provider_id, %{
          provider_name: get_provider_name(provider.provider_id),
          strategy: provider.strategy,
          active_contracts: provider.active_contracts || 0,
          market_share_percent: provider.market_share_percent || 0.0,
          day_buy_price: provider.day_buy_price || 0.0,
          night_buy_price: provider.night_buy_price || 0.0,
          day_sell_price: provider.day_sell_price || 0.0,
          night_sell_price: provider.night_sell_price || 0.0,
          switching_discount: provider.switching_discount || 0.0,
          price_per_kwh: (provider.day_buy_price || 0.0) * 0.6 + (provider.night_buy_price || 0.0) * 0.4,
          sell_back_rate: (provider.day_sell_price || 0.0) * 0.8 + (provider.night_sell_price || 0.0) * 0.2,
          contract_offer: %{
            day_buy_price: provider.day_buy_price || 0.0,
            night_buy_price: provider.night_buy_price || 0.0,
            day_sell_price: provider.day_sell_price || 0.0,
            night_sell_price: provider.night_sell_price || 0.0,
            switching_discount: provider.switching_discount || 0.0
          }
        }}
      end)
      |> Enum.into(%{})

    provider_market_share =
      providers
      |> Enum.map(fn provider ->
        {provider.provider_id, provider.active_contracts || 0}
      end)
      |> Enum.into(%{})

    {provider_states, unique_providers, provider_market_share}
  end

  defp load_system_stats_from_db do
    # Query OverviewAggregator (in-memory, calculated from entity aggregates)
    overview = OverviewAggregator.get_state()

    {overview.simulation_time, overview.simulation_speed, overview.simulation_paused || false, %{
      homes: overview.total_homes || 0,
      providers: overview.total_providers || 0,
      events_received: 0,
      total_production_kwh: (overview.total_production_kw || 0.0),  # Already in kW
      total_consumption_kwh: (overview.total_consumption_kw || 0.0),  # Already in kW
      total_energy_bought_kwh: overview.total_energy_bought_kwh || 0.0,
      total_energy_sold_kwh: overview.total_energy_sold_kwh || 0.0,
      total_cost_paid: overview.total_cost_paid || 0.0,
      total_revenue_received: overview.total_revenue_received || 0.0,
      contract_switches: overview.total_contract_switches || 0,
      avg_battery_percent: overview.avg_battery_percent || 0.0,
      # CortexIQ financial metrics
      cortexiq_total_commission: overview.cortexiq_total_commission || 0.0,
      cortexiq_total_savings: overview.cortexiq_total_savings || 0.0,
      cortexiq_net_savings: overview.cortexiq_net_savings || 0.0
    }}
  end
end
