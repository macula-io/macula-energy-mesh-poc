defmodule CortexIqDashboard.SimulationClient do
  @moduledoc """
  WAMP RPC client for simulation control commands.

  All simulation control operations (pause, resume, reset, set speed) go through this module.
  This is separate from QueryClient which handles data queries only.

  Available procedures:
  - reset_simulation/0 - Reset simulation to initial state
  - pause_simulation/0 - Pause the simulation
  - resume_simulation/0 - Resume the simulation
  - set_simulation_speed/1 - Change simulation speed multiplier
  """
  require Logger

  alias CortexIqDashboard.WampSubscriber

  @doc """
  Reset the simulation to the default start date.

  This will:
  - Truncate all database tables
  - Restart all home bots with staggered initialization
  - Restart all provider bots with staggered initialization
  - Clear all dashboard aggregates
  - Reset simulation time to 2025-01-01 00:00:00

  Returns:
    {:ok, result} | {:error, reason}

  Example result:
    %{
      "message" => "Simulation reset successfully",
      "new_start_time" => "2025-01-01T00:00:00Z"
    }
  """
  def reset_simulation do
    call_procedure("be.cortexiq.simulation.reset", [], %{})
  end

  @doc """
  Pause the simulation.

  Returns:
    {:ok, result} | {:error, reason}

  Example result:
    %{"message" => "Simulation paused", "paused" => true}
  """
  def pause_simulation do
    call_procedure("be.cortexiq.simulation.pause", [], %{})
  end

  @doc """
  Resume the simulation.

  Returns:
    {:ok, result} | {:error, reason}

  Example result:
    %{"message" => "Simulation resumed", "paused" => false}
  """
  def resume_simulation do
    call_procedure("be.cortexiq.simulation.resume", [], %{})
  end

  @doc """
  Set the simulation speed.

  Parameters:
    - speed: simulation speed multiplier (e.g., 1, 100, 1000, 10000, 105120)

  Returns:
    {:ok, result} | {:error, reason}

  Example result:
    %{"message" => "Speed updated to 1000x", "speed" => 1000}
  """
  def set_simulation_speed(speed) when is_integer(speed) do
    call_procedure("be.cortexiq.simulation.set_speed", [], %{speed: speed})
  end

  # Private Helpers

  defp call_procedure(uri, args, kwargs) do
    # Get WAMP client from WampSubscriber (it manages the connection)
    case GenServer.call(WampSubscriber, :get_wamp_client, 5_000) do
      {:ok, wamp_client} ->
        Logger.debug("SimulationClient: Calling RPC #{uri}")

        case MaculaSdk.Client.call(wamp_client, uri, args, kwargs, %{}) do
          {:ok, result} ->
            Logger.debug("SimulationClient: RPC #{uri} succeeded")
            {:ok, result}

          {:error, reason} = error ->
            Logger.error("SimulationClient: RPC #{uri} failed: #{inspect(reason)}")
            error
        end

      {:error, :not_connected} ->
        Logger.warning("SimulationClient: WAMP client not connected yet")
        {:error, :not_connected}

      {:error, reason} = error ->
        Logger.error("SimulationClient: Failed to get WAMP client: #{inspect(reason)}")
        error
    end
  rescue
    error ->
      Logger.error("SimulationClient: Exception during RPC call: #{inspect(error)}")
      {:error, :exception}
  end
end
