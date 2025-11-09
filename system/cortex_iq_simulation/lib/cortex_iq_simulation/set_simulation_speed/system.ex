defmodule CortexIqSimulation.SetSimulationSpeed.System do
  @moduledoc """
  RPC System for setting the simulation speed.

  Registers WAMP RPC procedure: be.cortexiq.simulation.set_speed

  Handles RPC calls by sending messages to SimulationClock and returning the result.
  Runs in a separate process to avoid blocking the WAMP client.
  """
  use GenServer
  require Logger

  alias MaculaClientEx.Client

  @reconnect_interval 5_000
  @rpc_procedure "be.cortexiq.simulation.set_speed"

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    macula_url = Keyword.fetch!(opts, :macula_url)
    realm = Keyword.fetch!(opts, :realm)
    simulation_clock = Keyword.fetch!(opts, :simulation_clock)

    state = %{
      macula_url: macula_url,
      realm: realm,
      simulation_clock: simulation_clock,
      client: nil
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("SetSimulationSpeed: Connecting to Macula realm #{state.realm} at #{state.macula_url}")

    case Client.start_link(url: state.macula_url, realm: state.realm) do
      {:ok, client} ->
        Logger.info("SetSimulationSpeed: Client started, waiting for session...")
        Process.send_after(self(), :register_procedure, 2000)
        {:noreply, %{state | client: client}}

      {:error, reason} ->
        Logger.error("SetSimulationSpeed: Connection failed: #{inspect(reason)}, retrying in #{@reconnect_interval}ms")
        Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:register_procedure, state) do
    with {:ok, client} <- get_client(state),
         :connected <- get_client_status(client) do
      handler = fn _args, kwargs, _details ->
        handle_set_speed_rpc(state, kwargs)
      end

      case Client.register(client, @rpc_procedure, handler) do
        :ok ->
          Logger.info("SetSimulationSpeed: Registered RPC procedure #{@rpc_procedure}")
          {:noreply, state}

        {:ok, _registration_id} ->
          Logger.info("SetSimulationSpeed: Registered RPC procedure #{@rpc_procedure}")
          {:noreply, state}

        {:error, reason} ->
          Logger.error("SetSimulationSpeed: Failed to register #{@rpc_procedure}: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      _ ->
        Logger.warning("SetSimulationSpeed: Session not ready, retrying in 1s...")
        Process.send_after(self(), :register_procedure, 1000)
        {:noreply, state}
    end
  end

  # Private functions

  defp get_client(%{client: nil}), do: {:error, :no_client}
  defp get_client(%{client: client}), do: {:ok, client}

  defp get_client_status(client) do
    case Client.status(client) do
      %{status: :connected} -> :connected
      _ -> :not_connected
    end
  end

  defp handle_set_speed_rpc(state, kwargs) do
    ref = make_ref()
    send(state.simulation_clock, {:rpc_set_speed, ref, self(), kwargs})

    receive do
      {:rpc_result, ^ref, result} ->
        result
    after
      5000 ->
        Logger.error("SetSimulationSpeed: Timeout waiting for SimulationClock response")
        {:error, %{"error" => "timeout"}}
    end
  end
end
