defmodule CortexIqQueries.RpcServer do
  @moduledoc """
  WAMP RPC Server that registers query procedures.

  Provides paged database queries via WAMP RPC:
  - be.cortexiq.energy.queries.get_homes
  - be.cortexiq.energy.queries.get_providers
  - be.cortexiq.energy.queries.get_overview
  """
  use GenServer
  require Logger

  alias MaculaSdk.Wamp.Client
  alias CortexIqQueries.Queries

  @reconnect_interval 5_000

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    bondy_url = Keyword.fetch!(opts, :bondy_url)
    realm = Keyword.fetch!(opts, :realm)

    state = %{
      bondy_url: bondy_url,
      realm: realm,
      wamp_client: nil,
      procedures: []
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("RpcServer: Connecting to WAMP realm #{state.realm} at #{state.bondy_url}")

    case Client.start_link(url: state.bondy_url, realm: state.realm) do
      {:ok, client} ->
        Logger.info("RpcServer: WAMP client process started, waiting for session establishment...")

        # Define procedures to register (but don't register yet)
        procedures = [
          {"be.cortexiq.energy.queries.get_homes", &handle_get_homes/2},
          {"be.cortexiq.energy.queries.get_providers", &handle_get_providers/2},
          {"be.cortexiq.energy.queries.get_overview", &handle_get_overview/2},
          {"be.cortexiq.energy.queries.home_exists", &handle_home_exists/2},
          {"be.cortexiq.energy.queries.provider_exists", &handle_provider_exists/2}
        ]

        # Wait for session to be established before registering
        Process.send_after(self(), :register_procedures, 2000)

        {:noreply, %{state | wamp_client: client, procedures: procedures}}

      {:error, reason} ->
        Logger.error("RpcServer: Connection failed: #{inspect(reason)}, retrying in #{@reconnect_interval}ms")
        Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:register_procedures, state) do
    if state.wamp_client do
      # Check if connected
      case Client.status(state.wamp_client) do
        %{status: :connected} ->
          Logger.info("RpcServer: Session established, registering procedures...")

          Enum.each(state.procedures, fn {uri, handler} ->
            case Client.register(state.wamp_client, uri, handler) do
              :ok ->
                Logger.info("RpcServer: Registered procedure #{uri}")
              {:error, reason} ->
                Logger.error("RpcServer: Failed to register #{uri}: #{inspect(reason)}")
            end
          end)

          {:noreply, state}

        _ ->
          Logger.warning("RpcServer: Session not yet established, retrying in 1s...")
          Process.send_after(self(), :register_procedures, 1000)
          {:noreply, state}
      end
    else
      Logger.error("RpcServer: No WAMP client available for registration")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:wamp, :goodbye, _details}, state) do
    Logger.warning("RpcServer: Received GOODBYE from WAMP, reconnecting")
    Process.send_after(self(), :connect, @reconnect_interval)
    {:noreply, %{state | wamp_client: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("RpcServer: Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # RPC Handlers

  defp handle_get_homes(_args, kwargs) do
    Logger.info("RpcServer: get_homes called with kwargs=#{inspect(kwargs)}")

    opts = %{
      page: Map.get(kwargs, "page", 1),
      page_size: Map.get(kwargs, "page_size", 20),
      region: Map.get(kwargs, "region"),
      search: Map.get(kwargs, "search"),
      sort_by: Map.get(kwargs, "sort_by", "home_id"),
      sort_direction: Map.get(kwargs, "sort_direction", "asc")
    }

    result = Queries.get_homes(opts)
    {:ok, [], result}
  rescue
    e ->
      Logger.error("RpcServer: get_homes error: #{inspect(e)}")
      {:error, %{error: "internal_error", message: Exception.message(e)}}
  end

  defp handle_get_providers(_args, kwargs) do
    Logger.info("RpcServer: get_providers called with kwargs=#{inspect(kwargs)}")

    opts = %{
      page: Map.get(kwargs, "page", 1),
      page_size: Map.get(kwargs, "page_size", 20)
    }

    result = Queries.get_providers(opts)
    {:ok, [], result}
  rescue
    e ->
      Logger.error("RpcServer: get_providers error: #{inspect(e)}")
      {:error, %{error: "internal_error", message: Exception.message(e)}}
  end

  defp handle_get_overview(_args, _kwargs) do
    Logger.info("RpcServer: get_overview called")

    result = Queries.get_overview()
    {:ok, [], result}
  rescue
    e ->
      Logger.error("RpcServer: get_overview error: #{inspect(e)}")
      {:error, %{error: "internal_error", message: Exception.message(e)}}
  end

  defp handle_home_exists(_args, kwargs) do
    home_id = Map.get(kwargs, "home_id")

    unless home_id do
      {:error, %{error: "missing_parameter", message: "home_id is required"}}
    else
      exists = Queries.home_exists?(home_id)
      {:ok, [], %{exists: exists}}
    end
  rescue
    e ->
      Logger.error("RpcServer: home_exists error: #{inspect(e)}")
      {:error, %{error: "internal_error", message: Exception.message(e)}}
  end

  defp handle_provider_exists(_args, kwargs) do
    provider_id = Map.get(kwargs, "provider_id")

    unless provider_id do
      {:error, %{error: "missing_parameter", message: "provider_id is required"}}
    else
      exists = Queries.provider_exists?(provider_id)
      {:ok, [], %{exists: exists}}
    end
  rescue
    e ->
      Logger.error("RpcServer: provider_exists error: #{inspect(e)}")
      {:error, %{error: "internal_error", message: Exception.message(e)}}
  end
end
