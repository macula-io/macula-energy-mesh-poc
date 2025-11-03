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
  alias CortexIqDashboard.Views.HomesViewAggregator
  alias CortexIqDashboardWeb.Components.NavMenu
  alias CortexIqDashboardSchemas.HomeStatus

  @per_page 10  # Show 10 homes per page (temporarily reduced to see pagination)

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.info("HomesLive: mount() called, connected: #{connected?(socket)}")

    # Subscribe to simulation time, control events, and home lifecycle only
    # DISABLED: real-time home state updates to prevent shaky rendering
    # The homes list is primarily for navigation, not live monitoring
    if connected?(socket) do
      # Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "view:homes")  # DISABLED
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:home_connected")
      Logger.info("HomesLive: Subscribed to simulation time, control events, and home lifecycle")
    end

    # Load full home list via WAMP RPC to get all home IDs and total count
    # This is lightweight - just IDs and metadata, no real-time state
    Logger.info("HomesLive: Loading home IDs via WAMP RPC...")
    {all_home_ids, total_homes} = case QueryClient.get_homes(page: 1, per_page: 10_000) do
      {:ok, result} ->
        Logger.info("HomesLive: get_homes(10_000) RPC result keys: #{inspect(Map.keys(result))}")
        homes_list = Map.get(result, "homes", [])
        Logger.info("HomesLive: homes_list length: #{length(homes_list)}, first home: #{inspect(List.first(homes_list))}")
        ids = Enum.map(homes_list, &Map.get(&1, "home_id"))
        total = Map.get(result, "total", length(ids))
        Logger.info("HomesLive: Loaded #{length(ids)} home IDs, total=#{total}")
        {ids, total}
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load home IDs: #{inspect(reason)}")
        {[], 0}
    end

    Logger.info("HomesLive: Loaded #{total_homes} home IDs")

    # Calculate page 1 home IDs (first @per_page homes)
    page_1_ids = Enum.take(all_home_ids, @per_page)

    # Get initial page 1 data from database via WAMP RPC
    # This provides the baseline state. Real-time updates will come from aggregator.
    Logger.info("HomesLive: Loading page 1 data for #{length(page_1_ids)} homes")
    homes_maps = case QueryClient.get_homes(page: 1, per_page: @per_page) do
      {:ok, result} ->
        Logger.info("HomesLive: get_homes(#{@per_page}) RPC result keys: #{inspect(Map.keys(result))}")
        homes = Map.get(result, "homes", [])
        Logger.info("HomesLive: Received #{length(homes)} homes for page 1")
        homes
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load page 1 homes: #{inspect(reason)}")
        []
    end

    # Tell the aggregator to track only these visible homes
    # This creates aggregates that will receive real-time updates
    if connected?(socket) do
      Logger.info("HomesLive: Tracking #{length(page_1_ids)} homes for real-time updates")
      HomesViewAggregator.track_homes(page_1_ids)
    end

    Logger.info("HomesLive: Loaded #{length(homes_maps)} homes for page 1")

    {:ok,
     socket
     |> assign(:current_path, "/homes")
     |> assign(:homes, homes_maps)
     |> assign(:all_home_ids, all_home_ids)  # Keep all IDs for pagination
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)
     |> assign(:total_homes, total_homes)
     |> assign(:selected_home, nil)
     |> assign(:search_query, "")
     |> assign(:sort_by, :location)
     |> assign(:sort_direction, :asc)
     |> assign(:simulation_time, nil)
     |> assign(:simulation_speed, 105_120)
     |> assign(:simulation_paused, false)}
  end

  @impl true
  def handle_info(:view_updated, socket) do
    require Logger
    Logger.debug("HomesLive: View updated, refreshing from local aggregator")

    # Get real-time state from local aggregator (fast GenServer call, no WAMP)
    aggregate_homes = HomesViewAggregator.get_homes()

    # Merge aggregate updates with existing home data to preserve metadata
    # Aggregates only track real-time data (production, consumption, battery, balance)
    # Static metadata (name, location, etc.) comes from initial database load
    existing_homes = socket.assigns.homes

    updated_homes = Enum.map(existing_homes, fn existing_home ->
      home_id = Map.get(existing_home, "home_id")

      # Find corresponding aggregate for this home
      case Enum.find(aggregate_homes, fn agg -> agg.home_id == home_id end) do
        nil ->
          # No aggregate update, keep existing data
          existing_home

        aggregate ->
          # Merge real-time data from aggregate with static metadata from database
          Map.merge(existing_home, %{
            "production_kw" => aggregate.production_kw,
            "consumption_kw" => aggregate.consumption_kw,
            "battery_percent" => aggregate.state_of_charge_pct,
            "net_balance_kwh" => aggregate.net_balance_kwh,
            "provider_id" => aggregate.provider_id,
            "status" => aggregate.status
          })
      end
    end)

    {:noreply, assign(socket, :homes, updated_homes)}
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
    Logger.info("HomesLive: Received reset_simulation, clearing homes list and scheduling reload")

    # Clear the homes list and tell aggregator to stop tracking all homes
    HomesViewAggregator.track_homes([])

    # Schedule a reload after homes have had time to restart (homes restart with 50ms stagger)
    # Wait 5 seconds to give all homes time to restart and publish their first events
    Process.send_after(self(), :reload_after_reset, 5_000)

    {:noreply,
     socket
     |> assign(:homes, [])
     |> assign(:all_home_ids, [])
     |> assign(:total_homes, 0)
     |> assign(:page, 1)
     |> assign(:selected_home, nil)}
  end

  @impl true
  def handle_info(:reload_after_reset, socket) do
    require Logger
    Logger.info("HomesLive: Reloading homes data after reset")

    # Load full home list via WAMP RPC to get all home IDs and total count
    {all_home_ids, total_homes} = case QueryClient.get_homes(page: 1, per_page: 10_000) do
      {:ok, result} ->
        homes_list = Map.get(result, "homes", [])
        ids = Enum.map(homes_list, &Map.get(&1, "home_id"))
        total = Map.get(result, "total", length(ids))
        {ids, total}
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to reload home IDs: #{inspect(reason)}")
        {[], 0}
    end

    Logger.info("HomesLive: Reloaded #{total_homes} home IDs after reset")

    # Calculate page 1 home IDs
    page_1_ids = Enum.take(all_home_ids, @per_page)

    # Get page 1 data
    homes_maps = case QueryClient.get_homes(page: 1, per_page: @per_page) do
      {:ok, result} ->
        Map.get(result, "homes", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to reload page 1 homes: #{inspect(reason)}")
        []
    end

    # Tell aggregator to track these homes for real-time updates
    HomesViewAggregator.track_homes(page_1_ids)

    Logger.info("HomesLive: Reloaded #{length(homes_maps)} homes for page 1 after reset")

    {:noreply,
     socket
     |> assign(:homes, homes_maps)
     |> assign(:all_home_ids, all_home_ids)
     |> assign(:total_homes, total_homes)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_info({:home_connected, kwargs}, socket) do
    require Logger
    home_id = Map.get(kwargs, "home_id")
    Logger.info("HomesLive: Home connected: #{home_id}")

    # Check if this home is already in our list
    all_home_ids = socket.assigns.all_home_ids

    if home_id not in all_home_ids do
      # Add to the list of all home IDs
      new_all_home_ids = [home_id | all_home_ids]
      new_total = socket.assigns.total_homes + 1

      Logger.info("HomesLive: Added new home #{home_id}, total homes: #{new_total}")

      # If this home should be visible on current page, query its data and add it
      current_page = socket.assigns.page
      per_page = socket.assigns.per_page
      start_idx = (current_page - 1) * per_page
      visible_ids = new_all_home_ids |> Enum.drop(start_idx) |> Enum.take(per_page)

      if home_id in visible_ids do
        # Query the new home's data
        case QueryClient.get_home(home_id) do
          {:ok, result} ->
            home_data = Map.get(result, "home")

            if home_data do
              # Add to visible homes list
              new_homes = [home_data | socket.assigns.homes] |> Enum.take(per_page)

              # Tell aggregator to track this new home
              HomesViewAggregator.track_homes(visible_ids)

              {:noreply,
               socket
               |> assign(:homes, new_homes)
               |> assign(:all_home_ids, new_all_home_ids)
               |> assign(:total_homes, new_total)}
            else
              {:noreply,
               socket
               |> assign(:all_home_ids, new_all_home_ids)
               |> assign(:total_homes, new_total)}
            end

          {:error, reason} ->
            Logger.warning("HomesLive: Failed to query new home #{home_id}: #{inspect(reason)}")
            {:noreply,
             socket
             |> assign(:all_home_ids, new_all_home_ids)
             |> assign(:total_homes, new_total)}
        end
      else
        # Home is not on current page, just update the count
        {:noreply,
         socket
         |> assign(:all_home_ids, new_all_home_ids)
         |> assign(:total_homes, new_total)}
      end
    else
      # Home already exists, nothing to do
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_home", %{"home_id" => home_id}, socket) do
    {:noreply, assign(socket, :selected_home, home_id)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply, assign(socket, :selected_home, nil)}
  end

  @impl true
  def handle_event("search_homes", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("sort_homes", %{"column" => column}, socket) do
    column_atom = String.to_atom(column)

    new_direction =
      if socket.assigns.sort_by == column_atom do
        toggle_direction(socket.assigns.sort_direction)
      else
        :asc
      end

    {:noreply,
     socket
     |> assign(:sort_by, column_atom)
     |> assign(:sort_direction, new_direction)}
  end

  @impl true
  def handle_event("change_page", %{"page" => page_str}, socket) do
    require Logger
    page = String.to_integer(page_str)
    per_page = socket.assigns.per_page
    all_home_ids = socket.assigns.all_home_ids

    # Calculate visible home IDs for this page
    start_idx = (page - 1) * per_page
    visible_ids = all_home_ids |> Enum.drop(start_idx) |> Enum.take(per_page)

    Logger.info("HomesLive: Changing to page #{page}, loading #{length(visible_ids)} homes")

    # Load page data from database via WAMP RPC
    homes_maps = case QueryClient.get_homes(page: page, per_page: per_page) do
      {:ok, result} ->
        Map.get(result, "homes", [])
      {:error, reason} ->
        Logger.warning("HomesLive: Failed to load page #{page}: #{inspect(reason)}")
        []
    end

    # Tell aggregator to track only these homes for real-time updates
    # This will destroy aggregates for old page and create for new page
    HomesViewAggregator.track_homes(visible_ids)

    Logger.info("HomesLive: Loaded #{length(homes_maps)} homes for page #{page}")

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:homes, homes_maps)}
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
          <%= if @selected_home do %>
            <%= render_home_detail(assigns) %>
          <% else %>
            <%= render_homes_list(assigns) %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Render homes list
  defp render_homes_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Page Header -->
      <div class="mb-6">
        <h1 class="text-3xl font-bold text-gray-100">Homes</h1>
        <p class="text-gray-400 text-sm mt-1">Monitor all homes in real-time</p>
      </div>

      <!-- Combined Search and Pagination Controls -->
      <% total_pages = ceil(@total_homes / @per_page) %>
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="flex flex-col lg:flex-row gap-4 items-start lg:items-center justify-between">
          <!-- Search Input (Left Side) -->
          <div class="flex-1 w-full lg:w-auto lg:max-w-md">
            <input
              type="text"
              placeholder="Search by location..."
              value={@search_query}
              phx-keyup="search_homes"
              phx-debounce="300"
              name="search"
              class="w-full px-4 py-2 bg-gray-900 border border-gray-600 rounded-lg text-gray-100 placeholder-gray-500 focus:border-blue-500 focus:outline-none"
            />
          </div>

          <!-- Pagination Controls (Right Side) -->
          <%= if total_pages > 1 do %>
            <div class="flex flex-col sm:flex-row gap-3 items-start sm:items-center w-full lg:w-auto">
              <!-- Page Info -->
              <div class="text-sm text-gray-400 whitespace-nowrap">
                Showing <%= (@page - 1) * @per_page + 1 %>-<%= min(@page * @per_page, @total_homes) %> of <%= @total_homes %>
              </div>

              <!-- Page Buttons -->
              <div class="flex gap-2">
                <%= if @page > 1 do %>
                  <button
                    phx-click="change_page"
                    phx-value-page={@page - 1}
                    class="px-3 py-1 bg-gray-700 hover:bg-gray-600 text-gray-300 rounded transition-colors"
                    title="Previous page"
                  >
                    ←
                  </button>
                <% end %>

                <%= for page_num <- pagination_range(@page, total_pages) do %>
                  <%= if page_num == :ellipsis do %>
                    <span class="px-3 py-1 text-gray-500">...</span>
                  <% else %>
                    <button
                      phx-click="change_page"
                      phx-value-page={page_num}
                      class={"px-3 py-1 rounded transition-colors #{if page_num == @page, do: "bg-blue-600 text-white font-semibold", else: "bg-gray-700 hover:bg-gray-600 text-gray-300"}"}
                      title={"Go to page #{page_num}"}
                    >
                      <%= page_num %>
                    </button>
                  <% end %>
                <% end %>

                <%= if @page < total_pages do %>
                  <button
                    phx-click="change_page"
                    phx-value-page={@page + 1}
                    class="px-3 py-1 bg-gray-700 hover:bg-gray-600 text-gray-300 rounded transition-colors"
                    title="Next page"
                  >
                    →
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
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
                  {:name, "Family"},
                  {:iot_provider, "IoT Provider"},
                  {:provider, "Energy Provider"},
                  {:production, "Production"},
                  {:consumption, "Consumption"},
                  {:battery, "Battery"},
                  {:balance, "Energy Balance"},
                  {:status, "Status"}
                ] do %>
                  <th class="px-4 py-3 text-left">
                    <button
                      phx-click="sort_homes"
                      phx-value-column={column}
                      class="flex items-center gap-2 text-gray-400 hover:text-gray-200 font-semibold text-xs uppercase tracking-wide"
                    >
                      <%= label %>
                      <%= if @sort_by == column do %>
                        <span class="text-blue-400">
                          <%= if @sort_direction == :asc, do: "▲", else: "▼" %>
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
              <%= for home <- @homes do %>
                <tr class="hover:bg-gray-700 transition-colors">
                  <td class="px-4 py-3">
                    <div class="text-sm font-medium"><%= Map.get(home, "location", "Unknown") %></div>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm text-gray-300"><%= format_family_name(home) %></div>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm text-gray-300"><%= format_iot_provider(Map.get(home, "iot_provider")) %></div>
                  </td>
                  <td class="px-4 py-3">
                    <%= if Map.get(home, "provider_id") do %>
                      <div class="text-sm text-yellow-400"><%= get_provider_name(Map.get(home, "provider_id")) %></div>
                    <% else %>
                      <div class="text-sm text-gray-500">No contract</div>
                    <% end %>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm text-green-400">
                      <%= format_power(Map.get(home, "production_kw", 0.0)) %>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm text-red-400">
                      <%= format_power(Map.get(home, "consumption_kw", 0.0)) %>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <% battery_pct = Map.get(home, "battery_percent") || 0.0 %>
                    <div class="flex items-center gap-2">
                      <div class="flex-1 bg-gray-700 rounded-full h-2 w-16">
                        <div
                          class={"h-full rounded-full #{battery_color(battery_pct)}"}
                          style={"width: #{battery_pct}%"}
                        >
                        </div>
                      </div>
                      <span class="text-xs text-gray-400"><%= Float.round(battery_pct, 0) %>%</span>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <% net_kwh = Map.get(home, "net_balance_kwh") || 0.0 %>
                    <div class={"text-sm #{if net_kwh > 0, do: "text-red-400", else: "text-green-400"}"}>
                      <%= format_energy(abs(net_kwh)) %>
                      <span class="text-xs text-gray-500">
                        <%= if net_kwh > 0, do: " (buying)", else: " (selling)" %>
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <% status = Map.get(home, "status", 0) %>
                    <div class={"text-xs px-2 py-1 rounded inline-block #{status_color(status)}"}>
                      <%= format_status(status) %>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <button
                      phx-click="select_home"
                      phx-value-home_id={Map.get(home, "home_id")}
                      class="px-3 py-1 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded transition-colors"
                    >
                      View
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <!-- Bottom Pagination (Simplified) -->
        <%= if total_pages > 1 do %>
          <div class="px-4 py-3 bg-gray-900 border-t border-gray-700 flex items-center justify-between">
            <div class="text-sm text-gray-400">
              Page <%= @page %> of <%= total_pages %>
            </div>
            <div class="flex gap-2">
              <%= if @page > 1 do %>
                <button
                  phx-click="change_page"
                  phx-value-page={@page - 1}
                  class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded transition-colors"
                  title="Previous page"
                >
                  ← Previous
                </button>
              <% end %>

              <%= if @page < total_pages do %>
                <button
                  phx-click="change_page"
                  phx-value-page={@page + 1}
                  class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded transition-colors"
                  title="Next page"
                >
                  Next →
                </button>
              <% end %>
            </div>
          </div>
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
      <div class="flex items-center gap-4">
        <button
          phx-click="back_to_list"
          class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg transition-colors"
        >
          ← Back to List
        </button>
        <div>
          <h1 class="text-3xl font-bold text-gray-100">Home Details</h1>
          <p class="text-gray-400 text-sm mt-1">{@selected_home}</p>
        </div>
      </div>

      <!-- Home Detail Content -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <p class="text-gray-400">Detailed home view coming soon...</p>
        <p class="text-sm text-gray-500 mt-2">This will show charts, energy history, and contract details.</p>
      </div>
    </div>
    """
  end

  # Helper Functions
  # (Filtering and sorting now handled by cortex_iq_queries via WAMP RPC)

  # Convert home aggregate struct to map for template (using string keys)
  defp home_to_map(home) do
    %{
      "home_id" => home.home_id,
      "location" => home.location,
      "name" => home.name,
      "iot_provider" => home.iot_provider,
      "street" => home.street,
      "latitude" => home.latitude,
      "longitude" => home.longitude,
      "solar_capacity_kw" => home.solar_capacity_kw,
      "battery_capacity_kwh" => home.battery_capacity_kwh,
      "provider_id" => home.provider_id,
      "production_kw" => home.production_kw,
      "consumption_kw" => home.consumption_kw,
      "battery_percent" => home.state_of_charge_pct,
      "net_balance_kwh" => home.net_balance_kwh,
      "status" => home.status
    }
  end

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

  defp toggle_direction(:asc), do: :desc
  defp toggle_direction(:desc), do: :asc

  # Generate smart pagination range (e.g., 1 ... 4 5 6 ... 20)
  defp pagination_range(_current, total) when total <= 7 do
    # Show all pages if 7 or fewer
    1..total |> Enum.to_list()
  end

  defp pagination_range(current, total) do
    # Always show: first, current +/- 1, last
    # Use :ellipsis for gaps
    first = 1
    last = total

    cond do
      # Current near start: 1 2 3 4 5 ... last
      current <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, last]

      # Current near end: 1 ... N-4 N-3 N-2 N-1 N
      current >= total - 3 ->
        [first, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]

      # Current in middle: 1 ... current-1 current current+1 ... last
      true ->
        [first, :ellipsis, current - 1, current, current + 1, :ellipsis, last]
    end
  end

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
