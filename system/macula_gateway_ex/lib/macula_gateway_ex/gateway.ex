defmodule MaculaGatewayEx.Gateway do
  @moduledoc """
  Elixir wrapper for the Erlang `:macula_gateway` embedded gateway.

  This GenServer manages an embedded Macula gateway that runs in the same
  BEAM instance as your application, enabling true peer-to-peer mesh networking.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :gateway_pid,  # Erlang :macula_gateway process
      :port,
      :realm,
      :status
    ]
  end

  ## Client API

  @doc """
  Start an embedded Macula gateway.

  ## Options
  - `:port` - Port to listen on (default: 9443)
  - `:realm` - Realm name (default: "macula.default")
  - `:name` - GenServer name (optional)

  ## Examples

      {:ok, gateway} = MaculaGatewayEx.Gateway.start_link(
        port: 9443,
        realm: "be.cortexiq.energy"
      )
  """
  def start_link(opts \\ []) do
    {gen_opts, gateway_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, gateway_opts, gen_opts)
  end

  @doc """
  Get gateway statistics.

  Returns a map with:
  - `:port` - Listen port
  - `:realm` - Realm name
  - `:clients` - Number of connected clients
  - `:subscriptions` - Number of active subscriptions
  - `:registrations` - Number of RPC registrations
  """
  def get_stats(gateway) do
    GenServer.call(gateway, :get_stats)
  end

  @doc """
  Stop the gateway.
  """
  def stop(gateway) do
    GenServer.stop(gateway)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 9443)
    realm = Keyword.get(opts, :realm, "macula.default") |> to_charlist()

    # Start the Erlang macula_gateway
    gateway_opts = [
      {:port, port},
      {:realm, realm}
    ]

    case :macula_gateway.start_link(gateway_opts) do
      {:ok, gateway_pid} ->
        Logger.info("Macula Gateway started on port #{port} (realm: #{realm})")

        state = %State{
          gateway_pid: gateway_pid,
          port: port,
          realm: realm,
          status: :running
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start Macula Gateway: #{inspect(reason)}")
        {:stop, {:gateway_start_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats =
      case :macula_gateway.get_stats(state.gateway_pid) do
        stats_map when is_map(stats_map) ->
          # Convert Erlang map to Elixir map with atom keys
          Map.new(stats_map, fn {k, v} -> {k, v} end)

        other ->
          Logger.warning("Unexpected stats format: #{inspect(other)}")
          %{}
      end

    {:reply, stats, state}
  end

  @impl true
  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.gateway_pid do
      :macula_gateway.stop(state.gateway_pid)
    end

    :ok
  end
end
