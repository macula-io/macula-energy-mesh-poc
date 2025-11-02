defmodule CortexIqDashboardWeb.ProvidersLive do
  @moduledoc """
  Providers page LiveView - Monitor energy providers and market competition.

  Displays:
  - List of all providers sorted by market share
  - Provider strategies and pricing
  - Contract offers and market positioning
  - Individual provider details on click
  """
  use CortexIqDashboardWeb, :live_view

  alias CortexIqDashboard.QueryClient
  alias CortexIqDashboard.SimulationClient
  alias CortexIqDashboardWeb.Components.NavMenu

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.info("ProvidersLive: mount() called, connected: #{connected?(socket)}")

    # Subscribe to providers view updates, simulation time, control events, and provider initialization
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "view:providers")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:provider_initialized")
      Logger.info("ProvidersLive: Subscribed to providers updates, simulation time, control events, and provider initialization")
    end

    # Load initial data via WAMP RPC (NO database access!)
    providers = case QueryClient.get_providers() do
      {:ok, providers_data} ->
        Logger.info("ProvidersLive: Loaded #{length(Map.get(providers_data, "providers", []))} providers")
        Map.get(providers_data, "providers", [])
      {:error, reason} ->
        Logger.warning("ProvidersLive: Failed to load providers: #{inspect(reason)}")
        []
    end

    {:ok,
     socket
     |> assign(:current_path, "/providers")
     |> assign(:providers, providers)
     |> assign(:selected_provider, nil)
     |> assign(:simulation_time, nil)
     |> assign(:simulation_speed, 105_120)
     |> assign(:simulation_paused, false)}
  end

  @impl true
  def handle_info(:view_updated, socket) do
    require Logger
    Logger.debug("ProvidersLive: View updated, reloading providers data")

    # Reload via WAMP RPC
    case QueryClient.get_providers() do
      {:ok, providers_data} ->
        {:noreply, assign(socket, :providers, Map.get(providers_data, "providers", []))}

      {:error, reason} ->
        Logger.error("ProvidersLive: Failed to get providers data: #{inspect(reason)}")
        {:noreply, socket}
    end
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
    Logger.info("ProvidersLive: Received reset_simulation, clearing providers list and scheduling reload")

    # Schedule a reload after providers have had time to restart (providers restart with 200ms stagger)
    # Wait 3 seconds to give all providers time to restart and publish their first events
    Process.send_after(self(), :reload_after_reset, 3_000)

    {:noreply, assign(socket, :providers, [])}
  end

  @impl true
  def handle_info(:reload_after_reset, socket) do
    require Logger
    Logger.info("ProvidersLive: Reloading providers data after reset")

    # Reload via WAMP RPC
    providers = case QueryClient.get_providers() do
      {:ok, providers_data} ->
        Logger.info("ProvidersLive: Reloaded #{length(Map.get(providers_data, "providers", []))} providers")
        Map.get(providers_data, "providers", [])
      {:error, reason} ->
        Logger.warning("ProvidersLive: Failed to reload providers: #{inspect(reason)}")
        []
    end

    {:noreply, assign(socket, :providers, providers)}
  end

  @impl true
  def handle_info({:provider_initialized, kwargs}, socket) do
    require Logger
    provider_id = Map.get(kwargs, "provider_id")
    Logger.info("ProvidersLive: New provider initialized: #{provider_id}")

    # Check if this provider is already in our list
    providers = socket.assigns.providers
    provider_exists = Enum.any?(providers, fn p -> Map.get(p, "provider_id") == provider_id end)

    if not provider_exists do
      # Reload all providers to get the new one
      # (Simpler than querying individual provider since there are few providers)
      case QueryClient.get_providers() do
        {:ok, providers_data} ->
          new_providers = Map.get(providers_data, "providers", [])
          Logger.info("ProvidersLive: Added new provider #{provider_id}, total: #{length(new_providers)}")
          {:noreply, assign(socket, :providers, new_providers)}

        {:error, reason} ->
          Logger.warning("ProvidersLive: Failed to reload providers after new provider: #{inspect(reason)}")
          {:noreply, socket}
      end
    else
      # Provider already exists, nothing to do
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_provider", %{"provider_id" => provider_id}, socket) do
    {:noreply, assign(socket, :selected_provider, provider_id)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply, assign(socket, :selected_provider, nil)}
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
          <%= if @selected_provider do %>
            <%= render_provider_detail(assigns) %>
          <% else %>
            <%= render_providers_list(assigns) %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Render providers list
  defp render_providers_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Page Header -->
      <div class="mb-6">
        <h1 class="text-3xl font-bold text-gray-100">Energy Providers</h1>
        <p class="text-gray-400 text-sm mt-1">
          {length(@providers)} providers competing for market share
        </p>
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
              <%= for provider <- Enum.sort_by(@providers, fn p -> -(Map.get(p, "market_share_percent", 0.0)) end) do %>
                <% provider_id = Map.get(provider, "provider_id", "") %>
                <% market_share = Map.get(provider, "market_share_percent", 0.0) %>
                <% day_buy = Map.get(provider, "day_buy_price", 0.0) %>
                <% night_buy = Map.get(provider, "night_buy_price", 0.0) %>
                <% day_sell = Map.get(provider, "day_sell_price", 0.0) %>
                <% night_sell = Map.get(provider, "night_sell_price", 0.0) %>
                <% discount = Map.get(provider, "switching_discount", 0.0) %>
                <% avg_spread = ((day_buy - day_sell) + (night_buy - night_sell)) / 2 %>

                <tr class="hover:bg-gray-700 transition-colors">
                  <td class="px-4 py-3">
                    <div class="font-semibold text-sm text-yellow-400">
                      {Map.get(provider, "name", get_provider_name(provider_id))}
                    </div>
                    <div class="text-xs text-gray-500 font-mono">{provider_id}</div>
                  </td>
                  <td class="px-4 py-3">
                    <span class="px-2 py-1 text-xs font-semibold rounded bg-blue-600 text-white">
                      {format_strategy(Map.get(provider, "strategy", "unknown"))}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="flex items-center justify-end gap-2">
                      <div class="flex-1 bg-gray-700 rounded-full h-2 w-16">
                        <div
                          class="h-full rounded-full bg-gradient-to-r from-blue-500 to-green-500"
                          style={"width: #{Float.round(market_share, 1)}%"}
                        >
                        </div>
                      </div>
                      <span class="text-sm font-bold text-green-400 w-12">
                        {Float.round(market_share, 1)}%
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="text-sm font-semibold text-white">
                      {Map.get(provider, "active_contracts", 0)}
                    </div>
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
                      class="px-3 py-1 bg-yellow-600 hover:bg-yellow-700 text-white text-xs font-semibold rounded transition-colors"
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

  # Render provider detail view
  defp render_provider_detail(assigns) do
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
          <h1 class="text-3xl font-bold text-gray-100">Provider Details</h1>
          <p class="text-gray-400 text-sm mt-1">{@selected_provider}</p>
        </div>
      </div>

      <!-- Provider Detail Content -->
      <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
        <p class="text-gray-400">Detailed provider view coming soon...</p>
        <p class="text-sm text-gray-500 mt-2">
          This will show historical pricing, contract history, and performance metrics.
        </p>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp get_provider_name("provider_a"), do: "Essent"
  defp get_provider_name("provider_b"), do: "Eneco"
  defp get_provider_name("provider_c"), do: "Vattenfall"
  defp get_provider_name("provider_d"), do: "Greenchoice"
  defp get_provider_name("provider_e"), do: "Budget Energie"
  defp get_provider_name(_), do: "Unknown"

  defp format_strategy("steady_eddie"), do: "Steady Eddie"
  defp format_strategy("night_owl"), do: "Night Owl"
  defp format_strategy("solar_surfer"), do: "Solar Surfer"
  defp format_strategy("peak_predator"), do: "Peak Predator"
  defp format_strategy("discount_king"), do: "Discount King"
  defp format_strategy(strategy) when is_binary(strategy) do
    strategy
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp format_strategy(_), do: "Unknown"

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
