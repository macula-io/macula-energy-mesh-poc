defmodule MeshHubWeb.DashboardLive do
  use MeshHubWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to WAMP events
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MeshHub.PubSub, "wamp:events")
    end

    # Load Belgian locations for map
    locations = MeshCore.Geography.all_locations()

    {:ok,
     socket
     |> assign(:events, [])
     |> assign(:unique_homes, MapSet.new())
     |> assign(:unique_providers, MapSet.new())
     |> assign(:locations, locations)
     |> assign(:home_states, %{})
     |> assign(:home_history, %{})
     |> assign(:provider_states, %{})
     |> assign(:provider_history, %{})
     |> assign(:aggregate_history, [])
     |> assign(:selected_home, nil)
     |> assign(:selected_provider, nil)
     |> assign(:selected_region, :all)
     |> assign(:stats, %{
       homes: 0,
       providers: 0,
       events_received: 0,
       total_production_kwh: 0.0,
       total_consumption_kwh: 0.0,
       contract_switches: 0,
       avg_battery_percent: 0.0
     })}
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, socket) do
    # Extract the REAL topic from event details (not the subscription prefix)
    real_topic = get_in(event_data, [:details, "topic"]) || "unknown"

    # Add event to the list (keep last 50)
    events = [format_event(real_topic, event_data) | socket.assigns.events] |> Enum.take(50)

    # Track unique homes and providers
    {unique_homes, unique_providers} = track_unique_entities(
      socket.assigns.unique_homes,
      socket.assigns.unique_providers,
      real_topic,
      event_data
    )

    # Update home states and push to map
    {home_states, home_history, socket} = update_home_states(
      socket,
      real_topic,
      event_data
    )

    # Update provider states and history
    {provider_states, provider_history} = update_provider_states(
      socket.assigns.provider_states,
      socket.assigns.provider_history,
      real_topic,
      event_data
    )

    # Calculate aggregate stats
    stats = calculate_aggregate_stats(
      socket.assigns.stats,
      unique_homes,
      unique_providers,
      home_states,
      real_topic,
      event_data
    )

    # Update aggregate history (keep last 100 measurements)
    aggregate_history = update_aggregate_history(
      socket.assigns.aggregate_history,
      home_states,
      provider_states
    )

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:unique_homes, unique_homes)
     |> assign(:unique_providers, unique_providers)
     |> assign(:home_states, home_states)
     |> assign(:home_history, home_history)
     |> assign(:provider_states, provider_states)
     |> assign(:provider_history, provider_history)
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
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-gray-100">
      <div class="container mx-auto p-8">
        <h1 class="text-4xl font-bold mb-6 text-blue-400">Energy Mesh Dashboard</h1>

        <!-- Regional Tabs -->
        <div class="flex gap-2 mb-6">
          <%= for {region, label} <- [{:all, "All Regions"}, {:brussels, "Brussels"}, {:flanders, "Flanders"}, {:wallonia, "Wallonia"}] do %>
            <button
              phx-click="select_region"
              phx-value-region={region}
              class={"px-6 py-3 rounded-lg font-semibold transition-all #{if @selected_region == region, do: "bg-blue-600 text-white", else: "bg-gray-800 text-gray-400 hover:bg-gray-700"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>

        <!-- Provider Cards -->
        <div class="mb-6">
          <h3 class="text-sm font-semibold text-gray-400 mb-3">Energy Providers</h3>
          <div class="grid grid-cols-5 gap-4">
            <%= for provider_id <- ["engie", "luminus", "essent", "totalenergies", "bolt"] do %>
              <% provider_state = Map.get(@provider_states, provider_id, %{}) %>
              <button
                phx-click="select_provider"
                phx-value-provider_id={provider_id}
                class={"bg-gray-800 rounded-lg p-4 border-2 transition-all hover:border-yellow-500 #{if @selected_provider == provider_id, do: "border-yellow-500", else: "border-gray-700"}"}
              >
                <div class="text-left">
                  <div class="text-sm font-bold text-yellow-400">
                    <%= Map.get(provider_state, :provider_name, String.capitalize(provider_id)) %>
                  </div>
                  <%= if Map.get(provider_state, :price_per_kwh) do %>
                    <div class="text-2xl font-bold text-white mt-2">
                      €<%= Float.round(Map.get(provider_state, :price_per_kwh, 0), 4) %>
                    </div>
                    <div class="text-xs text-gray-500">per kWh</div>
                  <% else %>
                    <div class="text-xs text-gray-500 mt-2">No pricing data yet</div>
                  <% end %>
                  <%= if Map.get(provider_state, :strategy) do %>
                    <div class="text-xs text-gray-400 mt-2 truncate">
                      <%= format_strategy(Map.get(provider_state, :strategy)) %>
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
            <div class="text-gray-400 text-xs">Active Homes</div>
            <div class="text-2xl font-bold text-green-400"><%= @stats.homes %></div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Providers</div>
            <div class="text-2xl font-bold text-blue-400"><%= @stats.providers %></div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Total Production</div>
            <div class="text-2xl font-bold text-green-400">
              <%= Float.round(@stats.total_production_kwh, 2) %>
            </div>
            <div class="text-xs text-gray-500">kWh</div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Total Consumption</div>
            <div class="text-2xl font-bold text-red-400">
              <%= Float.round(@stats.total_consumption_kwh, 2) %>
            </div>
            <div class="text-xs text-gray-500">kWh</div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Avg Battery</div>
            <div class="text-2xl font-bold text-blue-400">
              <%= Float.round(@stats.avg_battery_percent, 1) %>%
            </div>
          </div>

          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <div class="text-gray-400 text-xs">Contract Switches</div>
            <div class="text-2xl font-bold text-purple-400"><%= @stats.contract_switches %></div>
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
                style="height: 600px;">
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
                            <%= event.type %>
                          </span>
                        </div>
                        <div class="text-gray-500 text-xs"><%= event.time %></div>
                      </div>
                      <div class="mt-2 text-gray-400 text-xs">
                        <%= if is_map(event.data) and Map.has_key?(event.data, :provider_id) do %>
                          <button
                            phx-click="select_provider"
                            phx-value-provider_id={event.data.provider_id}
                            class="text-yellow-400 hover:text-yellow-300 underline cursor-pointer">
                            <%= event.data.text %>
                          </button>
                        <% else %>
                          <%= event.data %>
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
                  data-history={Jason.encode!(@aggregate_history)}>
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
                  data-provider-states={Jason.encode!(@provider_states)}>
                </div>
              </div>

              <!-- Regional Energy Balance Chart -->
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-gray-300 mb-4">Regional Energy Balance</h3>
                <div
                  id="regional-balance-chart"
                  phx-hook="RegionalBalanceChart"
                  phx-update="ignore"
                  data-history={Jason.encode!(@aggregate_history)}>
                </div>
              </div>

              <!-- Price Comparison Chart -->
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-gray-300 mb-4">Provider Price Comparison</h3>
                <div
                  id="price-comparison-chart"
                  phx-hook="PriceComparisonChart"
                  phx-update="ignore"
                  data-provider-history={Jason.encode!(@provider_history)}>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <!-- System Status -->
        <div class="mt-6 text-gray-500 text-sm">
          <p>Realm: com.energy.mesh | WAMP Router: Bondy @ ws://localhost:18080/ws</p>
        </div>
      </div>

      <!-- Home Detail Panel (Slide-in) -->
      <%= if @selected_home do %>
        <% home_state = Map.get(@home_states, @selected_home, %{}) %>
        <% home_history = Map.get(@home_history, @selected_home, []) %>

        <div class="fixed inset-0 bg-black bg-opacity-50 z-40"
             phx-click="close_detail_panel">
        </div>

        <div class="fixed right-0 top-0 bottom-0 w-1/3 bg-gray-800 shadow-2xl z-50 overflow-y-auto border-l border-gray-700"
             style="animation: slideIn 0.3s ease-out;">
          <!-- Panel Header -->
          <div class="sticky top-0 bg-gray-900 border-b border-gray-700 p-6 flex justify-between items-start">
            <div>
              <h2 class="text-2xl font-bold text-blue-400"><%= @selected_home %></h2>
              <div class="text-gray-400 text-sm mt-1">
                <%= Map.get(home_state, :city, "Unknown") %>,
                <%= Map.get(home_state, :postal_code, "") %>
              </div>
              <%= if Map.get(home_state, :region) do %>
                <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold rounded-full bg-blue-600 text-white">
                  <%= MeshCore.Geography.region_name(String.to_atom(Map.get(home_state, :region, "unknown"))) %>
                </span>
              <% end %>
            </div>
            <button
              phx-click="close_detail_panel"
              class="text-gray-400 hover:text-white transition-colors">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
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
                  <%= round(Map.get(home_state, :production_w, 0)) %>W
                </div>
              </div>
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Consumption</div>
                <div class="text-2xl font-bold text-red-400">
                  <%= round(Map.get(home_state, :consumption_w, 0)) %>W
                </div>
              </div>
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Battery</div>
                <div class="text-2xl font-bold text-blue-400">
                  <%= Float.round(Map.get(home_state, :battery_percent, 0), 1) %>%
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
                  data-l3={Map.get(home_state, :power_l3_w, 0)}>
                </div>
              </div>
            <% end %>

            <!-- Voltage & Frequency -->
            <%= if Map.has_key?(home_state, :voltage_v) do %>
              <div class="grid grid-cols-2 gap-4">
                <div class="bg-gray-700 rounded-lg p-4">
                  <div class="text-gray-400 text-xs">Voltage</div>
                  <div class="text-xl font-bold text-yellow-400">
                    <%= Float.round(Map.get(home_state, :voltage_v, 230.0), 1) %>V
                  </div>
                </div>
                <div class="bg-gray-700 rounded-lg p-4">
                  <div class="text-gray-400 text-xs">Frequency</div>
                  <div class="text-xl font-bold text-yellow-400">
                    <%= Float.round(Map.get(home_state, :frequency_hz, 50.0), 2) %>Hz
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Historical Sparklines -->
            <%= if length(home_history) > 1 do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">Production vs Consumption (Last 5 min)</h3>
                <div
                  id={"power-sparkline-#{@selected_home}"}
                  phx-hook="PowerSparkline"
                  phx-update="ignore"
                  data-history={Jason.encode!(home_history)}>
                </div>
              </div>

              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">Battery Charge (Last 5 min)</h3>
                <div
                  id={"battery-sparkline-#{@selected_home}"}
                  phx-hook="BatterySparkline"
                  phx-update="ignore"
                  data-history={Jason.encode!(home_history)}>
                </div>
              </div>
            <% end %>

            <!-- Provider Info -->
            <%= if Map.get(home_state, :current_provider) do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-2">Current Provider</h3>
                <div class="text-lg font-bold text-blue-400">
                  <%= Map.get(home_state, :current_provider) %>
                </div>
                <%= if Map.get(home_state, :current_rate) do %>
                  <div class="text-sm text-gray-400 mt-1">
                    Rate: €<%= Map.get(home_state, :current_rate) %>/kWh
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

        <div class="fixed inset-0 bg-black bg-opacity-50 z-40"
             phx-click="close_detail_panel">
        </div>

        <div class="fixed right-0 top-0 bottom-0 w-1/3 bg-gray-800 shadow-2xl z-50 overflow-y-auto border-l border-gray-700"
             style="animation: slideIn 0.3s ease-out;">
          <!-- Panel Header -->
          <div class="sticky top-0 bg-gray-900 border-b border-gray-700 p-6 flex justify-between items-start">
            <div>
              <h2 class="text-2xl font-bold text-yellow-400">
                <%= Map.get(provider_state, :provider_name, @selected_provider) %>
              </h2>
              <div class="text-gray-400 text-sm mt-1">
                Provider ID: <%= @selected_provider %>
              </div>
              <%= if Map.get(provider_state, :strategy) do %>
                <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold rounded-full bg-yellow-600 text-white">
                  <%= format_strategy(Map.get(provider_state, :strategy)) %>
                </span>
              <% end %>
            </div>
            <button
              phx-click="close_detail_panel"
              class="text-gray-400 hover:text-white transition-colors">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>

          <!-- Panel Content -->
          <div class="p-6 space-y-6">
            <!-- Current Pricing -->
            <div class="grid grid-cols-2 gap-4">
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Purchase Rate</div>
                <div class="text-2xl font-bold text-green-400">
                  €<%= Float.round(Map.get(provider_state, :price_per_kwh, 0), 4) %>
                </div>
                <div class="text-xs text-gray-500">per kWh</div>
              </div>
              <div class="bg-gray-700 rounded-lg p-4">
                <div class="text-gray-400 text-xs">Sell-back Rate</div>
                <div class="text-2xl font-bold text-blue-400">
                  €<%= Float.round(Map.get(provider_state, :sell_back_rate, 0), 4) %>
                </div>
                <div class="text-xs text-gray-500">per kWh</div>
              </div>
            </div>

            <!-- Regions Served -->
            <%= if Map.get(provider_state, :regions) && length(Map.get(provider_state, :regions, [])) > 0 do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-2">Regions Served</h3>
                <div class="flex flex-wrap gap-2">
                  <%= for region <- Map.get(provider_state, :regions, []) do %>
                    <span class="px-3 py-1 text-xs font-semibold rounded-full bg-blue-600 text-white">
                      <%= region %>
                    </span>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Pricing History Chart -->
            <%= if length(provider_history) > 1 do %>
              <div class="bg-gray-700 rounded-lg p-4">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">Pricing History (Last 10 min)</h3>
                <div
                  id={"pricing-chart-#{@selected_provider}"}
                  phx-hook="PricingChart"
                  phx-update="ignore"
                  data-history={Jason.encode!(provider_history)}
                  data-provider-name={Map.get(provider_state, :provider_name, @selected_provider)}>
                </div>
              </div>
            <% end %>

            <!-- Connected Homes -->
            <div class="bg-gray-700 rounded-lg p-4">
              <h3 class="text-sm font-semibold text-gray-300 mb-2">Market Share</h3>
              <% connected_homes = count_homes_by_provider(@home_states, @selected_provider) %>
              <div class="text-3xl font-bold text-yellow-400">
                <%= connected_homes %>
              </div>
              <div class="text-xs text-gray-500">homes connected</div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

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
      String.contains?(topic, "measurement") -> "measurement"
      String.contains?(topic, "production") -> "production"
      String.contains?(topic, "consumption") -> "consumption"
      String.contains?(topic, "storage") -> "storage"
      String.contains?(topic, "tariff") -> "tariff"
      String.contains?(topic, "contract") -> "contract"
      true -> "other"
    end
  end

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
    current_state = Map.get(socket.assigns.home_states, home_id, %{
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
          Map.merge(current_state, %{
            production_w: Map.get(kwargs, "power_w", 0),
            consumption_w: 0,
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
    topic
    |> extract_event_type()
    |> case do
      "tariff" ->
        kwargs = Map.get(event_data, :kwargs, %{})
        provider_id = Map.get(kwargs, "provider_id")

        provider_id
        |> case do
          id when is_binary(id) and id != "" ->
            update_provider_tariff(provider_states, provider_history, kwargs)
          _ ->
            {provider_states, provider_history}
        end
      _ ->
        {provider_states, provider_history}
    end
  end

  defp update_provider_states(provider_states, provider_history, _topic, _event_data) do
    {provider_states, provider_history}
  end

  defp update_provider_tariff(provider_states, provider_history, kwargs) do
    provider_id = Map.get(kwargs, "provider_id")

    current_state = Map.get(provider_states, provider_id, %{
      provider_name: Map.get(kwargs, "provider_name", provider_id),
      regions: [],
      strategy: nil
    })

    updated_state = Map.merge(current_state, %{
      provider_name: Map.get(kwargs, "provider_name", current_state.provider_name),
      price_per_kwh: Map.get(kwargs, "price_per_kwh", 0),
      sell_back_rate: Map.get(kwargs, "sell_back_rate", 0),
      regions: Map.get(kwargs, "regions", current_state.regions),
      strategy: Map.get(kwargs, "strategy", current_state.strategy)
    })

    # Update provider states
    provider_states = Map.put(provider_states, provider_id, updated_state)

    # Store pricing history (last 20 measurements)
    current_history = Map.get(provider_history, provider_id, [])
    timestamp = DateTime.utc_now()

    measurement = %{
      timestamp: timestamp,
      price_per_kwh: Map.get(updated_state, :price_per_kwh, 0)
    }

    updated_history = [measurement | current_history] |> Enum.take(20)
    provider_history = Map.put(provider_history, provider_id, updated_history)

    {provider_states, provider_history}
  end

  defp region_label(:all), do: "All Regions"
  defp region_label(:brussels), do: "Brussels-Capital"
  defp region_label(:flanders), do: "Flanders"
  defp region_label(:wallonia), do: "Wallonia"
  defp region_label(_), do: "Unknown"

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

  defp calculate_aggregate_stats(current_stats, unique_homes, unique_providers, home_states, topic, event_data) do
    # Calculate average battery percentage
    {total_battery, home_count} =
      home_states
      |> Enum.reduce({0.0, 0}, fn {_id, state}, {sum, count} ->
        {sum + Map.get(state, :battery_percent, 0.0), count + 1}
      end)

    avg_battery = if home_count > 0, do: total_battery / home_count, else: 0.0

    # Track contract switches
    contract_switches =
      topic
      |> extract_event_type()
      |> case do
        "contract" -> current_stats.contract_switches + 1
        _ -> current_stats.contract_switches
      end

    # Accumulate energy (very rough approximation)
    # In a real system, you'd integrate power over time properly
    {production_kwh, consumption_kwh} =
      home_states
      |> Enum.reduce({0.0, 0.0}, fn {_id, state}, {prod_acc, cons_acc} ->
        # Convert watts to kWh (assuming 5 second intervals: W * 5s / 3600s)
        prod_w = Map.get(state, :production_w, 0)
        cons_w = Map.get(state, :consumption_w, 0)
        {prod_acc + (prod_w * 5 / 3600 / 1000), cons_acc + (cons_w * 5 / 3600 / 1000)}
      end)

    %{
      homes: MapSet.size(unique_homes),
      providers: MapSet.size(unique_providers),
      events_received: current_stats.events_received + 1,
      total_production_kwh: current_stats.total_production_kwh + production_kwh,
      total_consumption_kwh: current_stats.total_consumption_kwh + consumption_kwh,
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
      provider_prices: provider_states |> Enum.map(fn {id, state} ->
        {id, Map.get(state, :price_per_kwh, 0)}
      end) |> Enum.into(%{})
    }

    [measurement | history] |> Enum.take(100)
  end
end
