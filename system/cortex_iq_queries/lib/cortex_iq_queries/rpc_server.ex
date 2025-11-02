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
          {"be.cortexiq.energy.queries.get_home", &handle_get_home/3},
          {"be.cortexiq.energy.queries.get_homes", &handle_get_homes/3},
          {"be.cortexiq.energy.queries.get_providers", &handle_get_providers/3},
          {"be.cortexiq.energy.queries.get_overview", &handle_get_overview/3},
          {"be.cortexiq.energy.queries.home_exists", &handle_home_exists/3},
          {"be.cortexiq.energy.queries.provider_exists", &handle_provider_exists/3},
          {"be.cortexiq.energy.queries.reserve_home_id", &handle_reserve_home_id/3},
          {"be.cortexiq.energy.projections.register_home", &handle_register_home/3}
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

  defp handle_get_home(_args, kwargs, _details) do
    home_id = Map.get(kwargs, "home_id")
    Logger.info("RpcServer: get_home called with home_id=#{inspect(home_id)}")

    unless home_id do
      {:error, "wamp.error.invalid_argument"}
    else
      case Queries.get_home(home_id) do
        nil ->
          {:error, "wamp.error.no_such_home"}
        home ->
          {:ok, %{home: home}}
      end
    end
  rescue
    e ->
      Logger.error("RpcServer: get_home error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_get_homes(_args, kwargs, _details) do
    Logger.info("RpcServer: get_homes called with kwargs=#{inspect(kwargs)}")

    # Accept both "page_size" and "per_page" for compatibility
    page_size = Map.get(kwargs, "per_page") || Map.get(kwargs, "page_size", 20)

    opts = %{
      page: Map.get(kwargs, "page", 1),
      page_size: page_size,
      region: Map.get(kwargs, "region"),
      search: Map.get(kwargs, "search"),
      sort_by: Map.get(kwargs, "sort_by", "home_id"),
      sort_direction: Map.get(kwargs, "sort_direction", "asc")
    }

    result = Queries.get_homes(opts)
    {:ok, result}
  rescue
    e ->
      Logger.error("RpcServer: get_homes error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_get_providers(_args, kwargs, _details) do
    Logger.info("RpcServer: get_providers called with kwargs=#{inspect(kwargs)}")

    opts = %{
      page: Map.get(kwargs, "page", 1),
      page_size: Map.get(kwargs, "page_size", 20)
    }

    result = Queries.get_providers(opts)
    {:ok, result}
  rescue
    e ->
      Logger.error("RpcServer: get_providers error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_get_overview(_args, _kwargs, _details) do
    Logger.info("RpcServer: get_overview called")

    result = Queries.get_overview()
    {:ok, result}
  rescue
    e ->
      Logger.error("RpcServer: get_overview error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_home_exists(_args, kwargs, _details) do
    home_id = Map.get(kwargs, "home_id")

    unless home_id do
      {:error, "wamp.error.invalid_argument"}
    else
      exists = Queries.home_exists?(home_id)
      {:ok, %{exists: exists}}
    end
  rescue
    e ->
      Logger.error("RpcServer: home_exists error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_provider_exists(_args, kwargs, _details) do
    provider_id = Map.get(kwargs, "provider_id")

    unless provider_id do
      {:error, "wamp.error.invalid_argument"}
    else
      exists = Queries.provider_exists?(provider_id)
      {:ok, %{exists: exists}}
    end
  rescue
    e ->
      Logger.error("RpcServer: provider_exists error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_reserve_home_id(_args, kwargs, _details) do
    home_id = Map.get(kwargs, "home_id")

    Logger.info("RpcServer: reserve_home_id called with home_id=#{inspect(home_id)}")

    unless home_id do
      {:error, "wamp.error.invalid_argument"}
    else
      case Queries.reserve_home_id(home_id) do
        {:ok, reserved} ->
          Logger.info("RpcServer: Successfully reserved home_id #{home_id}")
          {:ok, %{reserved: reserved, home_id: home_id}}

        {:error, :already_exists} ->
          Logger.warning("RpcServer: home_id #{home_id} already exists")
          {:error, "wamp.error.already_exists"}

        {:error, reason} ->
          Logger.error("RpcServer: Failed to reserve home_id #{home_id}: #{inspect(reason)}")
          {:error, "wamp.error.runtime_error"}
      end
    end
  rescue
    e ->
      Logger.error("RpcServer: reserve_home_id error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end

  defp handle_register_home(_args, kwargs, _details) do
    home_id = Map.get(kwargs, "home_id")
    name = Map.get(kwargs, "name")
    iot_provider = Map.get(kwargs, "iot_provider")
    location = Map.get(kwargs, "location")
    street = Map.get(kwargs, "street")
    postal_code = Map.get(kwargs, "postal_code")
    region = Map.get(kwargs, "region")
    latitude = Map.get(kwargs, "latitude")
    longitude = Map.get(kwargs, "longitude")
    solar_capacity_kw = Map.get(kwargs, "solar_capacity_kw")
    battery_capacity_kwh = Map.get(kwargs, "battery_capacity_kwh")

    Logger.info("RpcServer: register_home called with home_id=#{inspect(home_id)}, name=#{inspect(name)}")

    unless home_id do
      {:error, "wamp.error.invalid_argument"}
    else
      case Queries.register_home(%{
        home_id: home_id,
        name: name,
        iot_provider: iot_provider,
        location: location,
        street: street,
        postal_code: postal_code,
        region: region,
        latitude: latitude,
        longitude: longitude,
        solar_capacity_kw: solar_capacity_kw,
        battery_capacity_kwh: battery_capacity_kwh
      }) do
        {:ok, registered} ->
          Logger.info("RpcServer: Successfully registered home #{home_id}")
          {:ok, %{registered: registered, home_id: home_id}}

        {:error, :already_exists} ->
          Logger.warning("RpcServer: home_id #{home_id} already exists")
          {:error, "wamp.error.already_exists"}

        {:error, reason} ->
          Logger.error("RpcServer: Failed to register home #{home_id}: #{inspect(reason)}")
          {:error, "wamp.error.runtime_error"}
      end
    end
  rescue
    e ->
      Logger.error("RpcServer: register_home error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end
end
