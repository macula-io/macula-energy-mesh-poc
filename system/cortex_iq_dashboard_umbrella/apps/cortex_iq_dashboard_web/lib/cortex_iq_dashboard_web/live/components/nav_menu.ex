defmodule CortexIqDashboardWeb.Components.NavMenu do
  @moduledoc """
  Side navigation menu component for CortexIQ Dashboard.

  Displays navigation links for:
  - Overview (platform-wide metrics)
  - Homes (home list and details)
  - Providers (provider competition)

  Highlights the currently active page.

  ## Usage

      <CortexIqDashboardWeb.Components.NavMenu.render current_path={@current_path} />
  """
  use Phoenix.Component

  attr :current_path, :string, required: true
  attr :simulation_time, :any, default: nil
  attr :simulation_speed, :integer, default: 105_120
  attr :simulation_paused, :boolean, default: false

  def render(assigns) do
    ~H"""
    <nav class="w-64 bg-gray-900 border-r border-gray-700 flex flex-col h-screen">
      <!-- Header -->
      <div class="p-6 border-b border-gray-700">
        <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-400 to-purple-400 bg-clip-text text-transparent">
          VoltNet
        </h1>
        <p class="text-xs text-gray-400 mt-1">Energy Exchange</p>
      </div>

      <!-- Navigation Links -->
      <div class="py-6">
        <div class="space-y-1 px-3">
          <.nav_link
            label="Exchange Overview"
            path="/"
            icon="📊"
            active={@current_path == "/" or @current_path == "/overview"}
          />

          <.nav_link
            label="Homes"
            path="/homes"
            icon="🏠"
            active={@current_path == "/homes"}
          />

          <.nav_link
            label="Providers"
            path="/providers"
            icon="⚡"
            active={@current_path == "/providers"}
          />
        </div>
      </div>

      <!-- Simulation Controls -->
      <div class="px-3 pb-4 border-t border-gray-700 pt-4">
        <div class="text-xs text-gray-400 uppercase tracking-wide mb-3 px-1">Simulation</div>

        <!-- Time Display -->
        <div class="bg-gray-800 rounded-lg p-3 mb-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs text-gray-400">Date</span>
            <span class="text-lg" title={day_night_label(@simulation_time)}>
              {day_night_icon(@simulation_time)}
            </span>
          </div>
          <div class="text-sm font-mono text-indigo-300 font-semibold">
            {format_simulation_date(@simulation_time)}
          </div>
          <div class="flex items-center justify-between mt-2 pt-2 border-t border-gray-700">
            <div>
              <div class="text-xs text-gray-400">Status</div>
              <div class="text-xs font-semibold">
                <%= if @simulation_paused do %>
                  <span class="text-yellow-400">⏸ Paused</span>
                <% else %>
                  <span class="text-green-400">▶ Running</span>
                <% end %>
              </div>
            </div>
            <div class="text-right">
              <div class="text-xs text-gray-400">Speed</div>
              <div class="text-xs font-bold text-purple-300">
                {format_speed(@simulation_speed)}
              </div>
            </div>
          </div>
        </div>

        <!-- Control Buttons -->
        <div class="space-y-2">
          <!-- Play/Pause -->
          <%= if @simulation_paused do %>
            <button
              phx-click="simulation_resume"
              class="w-full px-3 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-semibold transition-all flex items-center justify-center gap-2"
            >
              <span>▶</span>
              Resume
            </button>
          <% else %>
            <button
              phx-click="simulation_pause"
              class="w-full px-3 py-2 bg-yellow-600 hover:bg-yellow-700 text-white rounded-lg text-sm font-semibold transition-all flex items-center justify-center gap-2"
            >
              <span>⏸</span>
              Pause
            </button>
          <% end %>

          <!-- Speed Controls -->
          <div class="grid grid-cols-5 gap-1">
            <%= for {speed, label} <- [{1, "1x"}, {100, "100x"}, {1000, "1K"}, {10000, "10K"}, {105120, "Max"}] do %>
              <button
                phx-click="simulation_set_speed"
                phx-value-speed={speed}
                class={"px-1 py-1 rounded text-xs font-semibold transition-all #{if @simulation_speed == speed, do: "bg-purple-600 text-white", else: "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"}"}
                title={"#{speed}x speed"}
              >
                {label}
              </button>
            <% end %>
          </div>

          <!-- Reset -->
          <button
            phx-click="simulation_reset"
            class="w-full px-3 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-semibold transition-all flex items-center justify-center gap-2"
          >
            <span>⟳</span>
            Reset
          </button>
        </div>
      </div>

      <!-- Footer Info -->
      <div class="p-4 border-t border-gray-700">
        <div class="text-xs text-gray-500">
          <div class="flex items-center justify-between mb-2">
            <span>Supercluster Status</span>
            <span class="flex items-center gap-1">
              <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
              <span class="text-green-400">Live</span>
            </span>
          </div>
          <div class="text-gray-600 space-y-1 mt-2">
            <div><span class="text-gray-500">Realm:</span> be.cortexiq.energy</div>
            <div class="flex items-center gap-2">
              <span class="text-gray-500">Processing:</span>
              <span class="text-indigo-400 font-mono">~2.4k msg/s</span>
            </div>
          </div>
        </div>
      </div>
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false

  defp nav_link(assigns) do
    base_classes = "flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-200"

    assigns =
      assign(
        assigns,
        :classes,
        if assigns.active do
          base_classes <>
            " bg-gradient-to-r from-indigo-600 to-purple-600 text-white shadow-lg"
        else
          base_classes <> " text-gray-400 hover:bg-gray-800 hover:text-white"
        end
      )

    ~H"""
    <.link navigate={@path} class={@classes}>
      <span class="text-xl">{@icon}</span>
      <span class="font-medium">{@label}</span>
    </.link>
    """
  end

  # Simulation helper functions

  defp format_simulation_date(nil), do: "No Time"
  defp format_simulation_date(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> format_simulation_date(dt)
      _ -> "Invalid Time"
    end
  end
  defp format_simulation_date(%DateTime{} = time) do
    Calendar.strftime(time, "%Y-%m-%d %Hh")
  end

  defp format_speed(nil), do: "N/A"
  defp format_speed(speed) when speed >= 1000 do
    "#{div(speed, 1000)}K×"
  end
  defp format_speed(speed), do: "#{speed}×"

  defp day_night_icon(nil), do: "🌓"
  defp day_night_icon(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> day_night_icon(dt)
      _ -> "🌓"
    end
  end
  defp day_night_icon(%DateTime{} = time) do
    hour = time.hour
    cond do
      hour >= 6 and hour < 18 -> "☀️"
      true -> "🌙"
    end
  end

  defp day_night_label(nil), do: "Unknown"
  defp day_night_label(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> day_night_label(dt)
      _ -> "Unknown"
    end
  end
  defp day_night_label(%DateTime{} = time) do
    hour = time.hour
    cond do
      hour >= 6 and hour < 18 -> "Day (6am-6pm)"
      true -> "Night (6pm-6am)"
    end
  end
end
