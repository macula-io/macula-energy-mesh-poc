defmodule CortexIqDashboardWeb.Components.SimulationControls do
  @moduledoc """
  LiveComponent for simulation control bar.

  Displays and controls:
  - Simulation date/time with day/night indicator
  - Pause/Resume button
  - Speed controls (1x, 100x, 1K, 10K, Max)
  - Reset button
  """
  use CortexIqDashboardWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
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
              phx-target={@myself}
              class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg font-semibold transition-all flex items-center gap-2"
              title="Resume Simulation"
            >
              <span class="text-xl">▶</span>
              Resume
            </button>
          <% else %>
            <button
              phx-click="simulation_pause"
              phx-target={@myself}
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
                phx-target={@myself}
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
            phx-target={@myself}
            class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg font-semibold transition-all flex items-center gap-2"
            title="Reset to 2025-01-01"
          >
            <span class="text-xl">⟳</span>
            Reset
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("simulation_pause", _params, socket) do
    require Logger
    Logger.warning("SimulationControls: PAUSE button clicked!")
    # Send event to parent LiveView
    send(self(), {:simulation_control, :pause})
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_resume", _params, socket) do
    require Logger
    Logger.warning("SimulationControls: RESUME button clicked!")
    send(self(), {:simulation_control, :resume})
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_set_speed", %{"speed" => speed_str}, socket) do
    require Logger
    speed = String.to_integer(speed_str)
    Logger.warning("SimulationControls: SET SPEED button clicked! Speed: #{speed}")
    send(self(), {:simulation_control, :set_speed, speed})
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulation_reset", _params, socket) do
    require Logger
    Logger.error("=" <> String.duplicate("=", 70))
    Logger.error("SIMULATION CONTROLS: RESET BUTTON CLICKED!")
    Logger.error("Socket assigns: #{inspect(Map.keys(socket.assigns))}")
    Logger.error("Sending {:simulation_control, :reset} to parent PID: #{inspect(self())}")
    Logger.error("=" <> String.duplicate("=", 70))

    send(self(), {:simulation_control, :reset})
    {:noreply, socket}
  end

  # Helper functions

  defp format_simulation_date(nil), do: "No Time"
  defp format_simulation_date(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> format_simulation_date(dt)
      _ -> "Invalid Time"
    end
  end
  defp format_simulation_date(%DateTime{} = time) do
    # Format: YYYY-MM-DD HH (24-hour, 2-digit: 01, 02, 14, 23)
    Calendar.strftime(time, "%Y-%m-%d %H")
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
