defmodule MeshHubWeb.DashboardLive do
  use MeshHubWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to WAMP events
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MeshHub.PubSub, "wamp:events")
    end

    {:ok,
     socket
     |> assign(:events, [])
     |> assign(:stats, %{
       homes: 0,
       providers: 0,
       events_received: 0
     })}
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, socket) do
    # Extract the REAL topic from event details (not the subscription prefix)
    real_topic = get_in(event_data, [:details, "topic"]) || "unknown"

    # Add event to the list (keep last 50)
    events = [format_event(real_topic, event_data) | socket.assigns.events] |> Enum.take(50)

    # Update stats using the real topic
    stats = update_stats(socket.assigns.stats, real_topic, event_data)

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:stats, stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-gray-100">
      <div class="container mx-auto p-8">
        <h1 class="text-4xl font-bold mb-8 text-blue-400">Energy Mesh Dashboard</h1>

        <!-- Stats Cards -->
        <div class="grid grid-cols-3 gap-6 mb-8">
          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div class="text-gray-400 text-sm">Active Homes</div>
            <div class="text-3xl font-bold text-green-400"><%= @stats.homes %></div>
          </div>

          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div class="text-gray-400 text-sm">Providers</div>
            <div class="text-3xl font-bold text-blue-400"><%= @stats.providers %></div>
          </div>

          <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div class="text-gray-400 text-sm">Events Received</div>
            <div class="text-3xl font-bold text-purple-400"><%= @stats.events_received %></div>
          </div>
        </div>

        <!-- Live Events Feed -->
        <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 class="text-2xl font-bold mb-4 text-gray-100">Live Events</h2>

          <div class="space-y-2 max-h-96 overflow-y-auto">
            <%= if Enum.empty?(@events) do %>
              <div class="text-gray-500 text-center py-8">
                Waiting for events... Make sure bots are running.
              </div>
            <% else %>
              <%= for event <- @events do %>
                <div class="bg-gray-700 rounded p-3 text-sm font-mono">
                  <div class="flex justify-between items-start">
                    <div class="flex-1">
                      <span class={"px-2 py-1 rounded text-xs font-semibold #{event_color(event.type)}"}>
                        <%= event.type %>
                      </span>
                      <span class="ml-2 text-gray-300"><%= event.topic %></span>
                    </div>
                    <div class="text-gray-500 text-xs"><%= event.time %></div>
                  </div>
                  <div class="mt-2 text-gray-400"><%= event.data %></div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <!-- System Status -->
        <div class="mt-8 text-gray-500 text-sm">
          <p>Realm: com.energy.mesh</p>
          <p>WAMP Router: Bondy @ ws://localhost:18080/ws</p>
        </div>
      </div>
    </div>
    """
  end

  defp format_event(topic, event_data) do
    type = cond do
      String.contains?(topic, "production") -> "production"
      String.contains?(topic, "consumption") -> "consumption"
      String.contains?(topic, "storage") -> "storage"
      String.contains?(topic, "tariff") -> "tariff"
      String.contains?(topic, "contract") -> "contract"
      true -> "other"
    end

    # Extract relevant data from kwargs
    data = case event_data do
      %{kwargs: kwargs} when is_map(kwargs) ->
        format_kwargs(type, kwargs)
      _ ->
        inspect(event_data)
    end

    %{
      type: type,
      topic: topic,
      data: data,
      time: format_time(DateTime.utc_now())
    }
  end

  defp format_kwargs("production", kwargs) do
    "#{Map.get(kwargs, "home_id", "unknown")}: #{Map.get(kwargs, "watts", 0) |> round()}W"
  end

  defp format_kwargs("consumption", kwargs) do
    "#{Map.get(kwargs, "home_id", "unknown")}: #{Map.get(kwargs, "watts", 0) |> round()}W"
  end

  defp format_kwargs("storage", kwargs) do
    "#{Map.get(kwargs, "home_id", "unknown")}: #{Map.get(kwargs, "battery_percent", 0) |> Float.round(1)}%"
  end

  defp format_kwargs("tariff", kwargs) do
    "#{Map.get(kwargs, "provider_id", "unknown")}: $#{Map.get(kwargs, "price_per_kwh", 0)}/kWh"
  end

  defp format_kwargs(_type, kwargs) do
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
  defp event_color(_), do: "bg-gray-600 text-white"

  defp update_stats(stats, topic, event_data) do
    stats
    |> update_in([:events_received], &(&1 + 1))
    |> maybe_update_homes(topic, event_data)
    |> maybe_update_providers(topic, event_data)
  end

  defp maybe_update_homes(stats, topic, %{kwargs: %{"home_id" => _home_id}}) when is_binary(topic) do
    if String.contains?(topic, "home") do
      # Simple approximation - in real app, track unique IDs
      home_num = extract_home_number(topic)
      update_in(stats, [:homes], fn h -> max(h, home_num) end)
    else
      stats
    end
  end
  defp maybe_update_homes(stats, _topic, _data), do: stats

  defp maybe_update_providers(stats, topic, %{kwargs: %{"provider_id" => _provider_id}}) when is_binary(topic) do
    if String.contains?(topic, "utility") do
      # Simple approximation
      provider_num = extract_provider_number(topic)
      update_in(stats, [:providers], fn p -> max(p, provider_num) end)
    else
      stats
    end
  end
  defp maybe_update_providers(stats, _topic, _data), do: stats

  defp extract_home_number(topic) do
    # Extract number from "energy.home.home_001.production"
    case Regex.run(~r/home_(\d+)/, topic) do
      [_, num] -> String.to_integer(num)
      _ -> 0
    end
  end

  defp extract_provider_number(topic) do
    # Extract number from "energy.utility.provider_1.tariff"
    case Regex.run(~r/provider_(\d+)/, topic) do
      [_, num] -> String.to_integer(num)
      _ -> 0
    end
  end
end
