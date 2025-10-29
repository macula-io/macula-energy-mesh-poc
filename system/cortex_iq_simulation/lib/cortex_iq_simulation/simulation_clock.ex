defmodule CortexIqSimulation.SimulationClock do
  @moduledoc """
  Centralized simulation clock for the CortexIQ energy mesh.

  Manages simulation time with configurable speed multiplier.
  Default: 105,120x (1 year = 5 minutes real-time).

  Provides:
  - Current simulation time calculation
  - Time broadcast via WAMP (every 1 second)
  - Time queries for bots

  Configuration via ENV:
  - SIMULATION_SPEED (default: 105120)
  - SIMULATION_START_DATE (default: 2025-01-01T00:00:00Z)
  - BONDY_URL (default: ws://172.20.0.2:30080/ws)
  - BONDY_REALM (default: be.cortexiq.energy)
  """

  use GenServer
  require Logger
  alias MaculaSdk.Wamp.Client

  # Default configuration
  @default_speed 105_120
  @default_start_date ~U[2025-01-01 00:00:00Z]
  @broadcast_interval_ms 1000

  defstruct [
    :speed,
    :start_simulation_time,
    :start_real_time,
    :wamp_client,
    :realm,
    :bondy_url,
    :connection_status,
    :retry_count,
    paused: false,
    pause_time: nil,
    accumulated_elapsed_ms: 0
  ]

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

    bondy_url = Keyword.get(opts, :bondy_url) || System.get_env("BONDY_URL", "ws://172.20.0.2:30080/ws")
    realm = Keyword.get(opts, :realm) || System.get_env("BONDY_REALM", "be.cortexiq.energy")

    Logger.info("""
    SimulationClock starting:
      Speed: #{speed}x
      Start time: #{DateTime.to_iso8601(start_simulation_time)}
      1 year = #{Float.round(525_600 / speed, 2)} minutes real-time
      Bondy URL: #{bondy_url}
      Realm: #{realm}
    """)

    state = %__MODULE__{
      speed: speed,
      start_simulation_time: start_simulation_time,
      start_real_time: System.monotonic_time(:millisecond),
      bondy_url: bondy_url,
      realm: realm,
      connection_status: :connecting,
      retry_count: 0,
      wamp_client: nil
    }

    # Connect asynchronously (don't crash if Bondy isn't ready)
    {:ok, state, {:continue, :connect_wamp}}
  end

  @impl true
  def handle_continue(:connect_wamp, state) do
    Logger.info("SimulationClock: Attempting to connect to WAMP (#{state.bondy_url})...")

    # Get authentication credentials from environment
    username = System.get_env("BONDY_USERNAME")
    password = System.get_env("BONDY_PASSWORD")

    # Build connection options
    connect_opts = [
      url: state.bondy_url,
      realm: state.realm,
      username: username,
      password: password
    ]

    case MaculaSdk.Wamp.Client.start_link(connect_opts) do
      {:ok, wamp_client} ->
        Logger.info("SimulationClock: Connected to WAMP, waiting for connection to stabilize...")
        # Wait a bit for connection to fully establish before subscribing
        Process.send_after(self(), :subscribe_to_control, 2000)
        Process.send_after(self(), :broadcast_time, @broadcast_interval_ms)

        {:noreply, %{state | wamp_client: wamp_client, connection_status: :connected, retry_count: 0}}

      {:error, reason} ->
        retry_delay = min(1000 * :math.pow(2, state.retry_count), 30_000) |> round()
        Logger.warning(
          "SimulationClock: Failed to connect to WAMP: #{inspect(reason)}. " <>
          "Retrying in #{retry_delay}ms (attempt #{state.retry_count + 1})"
        )

        Process.send_after(self(), :retry_connect, retry_delay)
        {:noreply, %{state | connection_status: :disconnected, retry_count: state.retry_count + 1}}
    end
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
  def handle_info(:retry_connect, state) do
    Logger.info("SimulationClock: Retrying WAMP connection...")
    {:noreply, state, {:continue, :connect_wamp}}
  end

  def handle_info(:subscribe_to_control, state) do
    if state.wamp_client do
      Logger.info("SimulationClock: Subscribing to control topics...")
      subscribe_to_control_topics(state.wamp_client)
    else
      Logger.warning("SimulationClock: Cannot subscribe, WAMP client not available")
    end
    {:noreply, state}
  end

  def handle_info(:broadcast_time, state) do
    # Only broadcast if connected
    state =
      if state.connection_status == :connected && state.wamp_client do
        sim_time = calculate_simulation_time(state)
        real_elapsed = get_real_elapsed_ms(state)

        # Publish directly to WAMP
        topic = "be.cortexiq.simulation.time_advanced"

        event = %{
          "simulation_time" => DateTime.to_iso8601(sim_time),
          "speed" => state.speed,
          "paused" => state.paused,
          "real_elapsed_ms" => real_elapsed
        }

        try do
          Client.publish(state.wamp_client, topic, [], event, %{})

          # Log occasionally (every 10 seconds) and when state changes
          if rem(real_elapsed, 10000) < 1000 do
            status = if state.paused, do: "PAUSED", else: "#{state.speed}x"
            Logger.info("SimulationClock: Broadcasting time to WAMP: #{event["simulation_time"]} (#{status})")
          end

          state
        rescue
          e ->
            Logger.error("SimulationClock: Failed to publish time to WAMP: #{inspect(e)}")
            # Connection might be lost, trigger reconnect
            Logger.warning("SimulationClock: Connection lost, will retry...")
            Process.send_after(self(), :retry_connect, 1000)
            %{state | connection_status: :disconnected, wamp_client: nil}
        end
      else
        # Not connected yet, skip this broadcast
        state
      end

    # Schedule next broadcast regardless of connection status
    Process.send_after(self(), :broadcast_time, @broadcast_interval_ms)

    {:noreply, state}
  end

  # Control command handlers

  def handle_info({:wamp_event, "be.cortexiq.simulation.control.pause", _args, _kwargs, _details}, state) do
    if not state.paused do
      Logger.info("SimulationClock: PAUSE command received")
      new_state = pause_simulation(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:wamp_event, "be.cortexiq.simulation.control.resume", _args, _kwargs, _details}, state) do
    if state.paused do
      Logger.info("SimulationClock: RESUME command received")
      new_state = resume_simulation(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:wamp_event, "be.cortexiq.simulation.control.reset", _args, _kwargs, _details}, state) do
    Logger.info("SimulationClock: RESET command received")
    new_state = reset_simulation(state)
    {:noreply, new_state}
  end

  def handle_info({:wamp_event, "be.cortexiq.simulation.control.set_speed", _args, kwargs, _details}, state) do
    speed = Map.get(kwargs, "speed", state.speed)
    Logger.info("SimulationClock: SET_SPEED command received: #{speed}x")
    new_state = set_speed(state, speed)
    {:noreply, new_state}
  end

  # Private Helpers

  defp subscribe_to_control_topics(wamp_client) do
    control_topics = [
      "be.cortexiq.simulation.control.pause",
      "be.cortexiq.simulation.control.resume",
      "be.cortexiq.simulation.control.reset",
      "be.cortexiq.simulation.control.set_speed"
    ]

    sim_clock_pid = self()

    handler = fn topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      details = Map.get(event_data, :details, %{})
      send(sim_clock_pid, {:wamp_event, topic, [], kwargs, details})
    end

    Enum.each(control_topics, fn topic ->
      case Client.subscribe(wamp_client, topic, handler) do
        :ok ->
          Logger.info("SimulationClock: Subscribed to #{topic}")
        {:error, reason} ->
          Logger.error("SimulationClock: Failed to subscribe to #{topic}: #{inspect(reason)}")
      end
    end)
  end

  defp pause_simulation(state) do
    # Record when we paused and how much time had elapsed
    current_real_ms = System.monotonic_time(:millisecond)
    elapsed_since_start = current_real_ms - state.start_real_time

    %{state |
      paused: true,
      pause_time: current_real_ms,
      accumulated_elapsed_ms: state.accumulated_elapsed_ms + elapsed_since_start
    }
  end

  defp resume_simulation(state) do
    # Reset start_real_time to now, keeping accumulated elapsed time
    %{state |
      paused: false,
      start_real_time: System.monotonic_time(:millisecond),
      pause_time: nil,
      accumulated_elapsed_ms: state.accumulated_elapsed_ms
    }
  end

  defp reset_simulation(state) do
    # Reset to initial state
    current_real_ms = System.monotonic_time(:millisecond)

    new_state = %{state |
      start_simulation_time: @default_start_date,
      start_real_time: current_real_ms,
      paused: false,
      pause_time: nil,
      accumulated_elapsed_ms: 0
    }

    # Publish reset event to notify dashboard and other components
    publish_reset_event(new_state)

    new_state
  end

  defp set_speed(state, new_speed) when is_integer(new_speed) and new_speed > 0 do
    # Preserve current simulation time when changing speed
    current_sim_time = calculate_simulation_time(state)
    current_real_ms = System.monotonic_time(:millisecond)

    %{state |
      speed: new_speed,
      start_simulation_time: current_sim_time,
      start_real_time: current_real_ms,
      accumulated_elapsed_ms: 0
    }
  end
  defp set_speed(state, _invalid_speed), do: state

  defp get_real_elapsed_ms(state) do
    if state.paused do
      state.accumulated_elapsed_ms
    else
      current_real_ms = System.monotonic_time(:millisecond)
      state.accumulated_elapsed_ms + (current_real_ms - state.start_real_time)
    end
  end

  defp calculate_simulation_time(state) do
    real_elapsed_ms = get_real_elapsed_ms(state)
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

  defp publish_reset_event(state) do
    topic = "be.cortexiq.simulation.reset"

    event = %{
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      new_start_time: DateTime.to_iso8601(state.start_simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
    Logger.info("SimulationClock: Published reset event to #{topic}")
  end
end
