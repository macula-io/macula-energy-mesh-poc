defmodule CortexIqDashboard.SimulationClock do
  @moduledoc """
  Centralized simulation clock for the energy mesh.

  Manages simulation time with configurable speed multiplier.
  Default: 105,120x (1 year = 5 minutes real-time).

  Provides:
  - Current simulation time calculation
  - Time broadcast via WAMP (every 1 second)
  - Time queries for bots

  Configuration via ENV:
  - SIMULATION_SPEED (default: 105120)
  - SIMULATION_START_DATE (default: 2025-01-01T00:00:00Z)
  """

  use GenServer
  require Logger

  # Default configuration
  @default_speed 105_120
  @default_start_date ~U[2025-01-01 00:00:00Z]
  @broadcast_interval_ms 1000

  # Client API

  @doc """
  Start the simulation clock.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current simulation time.
  """
  @spec current_time() :: DateTime.t()
  def current_time do
    GenServer.call(__MODULE__, :current_time)
  end

  @doc """
  Get the simulation speed multiplier.
  """
  @spec speed() :: integer()
  def speed do
    GenServer.call(__MODULE__, :speed)
  end

  @doc """
  Get clock state for debugging.
  """
  @spec state() :: map()
  def state do
    GenServer.call(__MODULE__, :state)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Get configuration from environment or opts
    speed =
      Keyword.get(opts, :speed) ||
        System.get_env("SIMULATION_SPEED", "#{@default_speed}")
        |> parse_integer(@default_speed)

    start_date_str =
      Keyword.get(opts, :start_date) ||
        System.get_env("SIMULATION_START_DATE")

    start_simulation_time =
      case start_date_str do
        nil ->
          @default_start_date

        str when is_binary(str) ->
          case DateTime.from_iso8601(str) do
            {:ok, dt, _} -> dt
            _ -> @default_start_date
          end

        %DateTime{} = dt ->
          dt
      end

    state = %{
      speed: speed,
      start_simulation_time: start_simulation_time,
      start_real_time: System.monotonic_time(:millisecond)
    }

    Logger.info("""
    SimulationClock started:
      Speed: #{speed}x
      Start time: #{DateTime.to_iso8601(start_simulation_time)}
      1 year = #{Float.round(525_600 / speed, 2)} minutes real-time
    """)

    # Schedule periodic time broadcasts
    Process.send_after(self(), :broadcast_time, @broadcast_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:current_time, _from, state) do
    sim_time = calculate_simulation_time(state)
    {:reply, sim_time, state}
  end

  @impl true
  def handle_call(:speed, _from, state) do
    {:reply, state.speed, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    sim_time = calculate_simulation_time(state)
    real_elapsed = System.monotonic_time(:millisecond) - state.start_real_time

    info = %{
      speed: state.speed,
      start_simulation_time: state.start_simulation_time,
      current_simulation_time: sim_time,
      real_elapsed_ms: real_elapsed,
      simulation_elapsed_days: DateTime.diff(sim_time, state.start_simulation_time, :day)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info(:broadcast_time, state) do
    sim_time = calculate_simulation_time(state)
    real_elapsed = System.monotonic_time(:millisecond) - state.start_real_time

    # Broadcast simulation time via Phoenix.PubSub
    # The WAMP subscriber (in mesh_hub or mesh_hub_web) will forward it to WAMP
    event = %{
      "simulation_time" => DateTime.to_iso8601(sim_time),
      "speed" => state.speed,
      "real_elapsed_ms" => real_elapsed
    }

    # Publish to local PubSub (this will be picked up by WAMP publisher)
    result =
      Phoenix.PubSub.broadcast(
        CortexIqDashboard.PubSub,
        "simulation:time",
        {:simulation_time, event}
      )

    # Log occasionally (every 10 seconds)
    if rem(real_elapsed, 10000) < 1000 do
      Logger.info("SimulationClock broadcasting time: #{event["simulation_time"]} (result: #{inspect(result)})")
    end

    # Schedule next broadcast
    Process.send_after(self(), :broadcast_time, @broadcast_interval_ms)

    {:noreply, state}
  end

  # Private Helpers

  defp calculate_simulation_time(state) do
    real_elapsed_ms = System.monotonic_time(:millisecond) - state.start_real_time
    simulation_elapsed_ms = real_elapsed_ms * state.speed
    DateTime.add(state.start_simulation_time, simulation_elapsed_ms, :millisecond)
  end

  defp parse_integer(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(int, _default) when is_integer(int), do: int
  defp parse_integer(_, default), do: default
end
