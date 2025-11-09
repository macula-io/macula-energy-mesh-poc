defmodule CortexIqProjections.RegisterHome.RpcHandler do
  @moduledoc """
  RPC handler for register_home procedure.

  Registers the WAMP procedure: be.cortexiq.energy.projections.register_home
  Handles calls by inserting home data into the database.
  """

  use GenServer
  require Logger

  alias CortexIqDashboardSchemas.Projections.HomeState
  alias CortexIqProjections.Repo

  import Ecto.Query

  @realm "be.cortexiq.energy"
  @procedure_uri "be.cortexiq.energy.projections.register_home"

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("RegisterHome.RpcHandler: Starting RPC handler")

    macula_url = System.get_env("MACULA_URL", "https://localhost:9443")

    Logger.info("RegisterHome.RpcHandler: Connecting to WAMP realm #{@realm} at #{macula_url}")

    case MaculaSdk.Client.start_link(
           realm: @realm,
           url: macula_url,
           name: CortexIqProjections.RegisterHome.WampPool,
           pool_size: 2
         ) do
      {:ok, _pid} ->
        Logger.info("RegisterHome.RpcHandler: WAMP pool started, waiting for session...")

        # Give the pool a moment to establish sessions
        Process.sleep(2000)

        # Register the procedure
        register_procedure()

        {:ok, %{}}

      {:error, reason} ->
        Logger.error("RegisterHome.RpcHandler: Failed to start WAMP pool: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  # Private functions

  defp register_procedure do
    Logger.info("RegisterHome.RpcHandler: Registering procedure #{@procedure_uri}")

    case MaculaSdk.Client.register(
           @procedure_uri,
           &handle_call/3,
           %{},
           CortexIqProjections.RegisterHome.WampPool
         ) do
      :ok ->
        Logger.info("RegisterHome.RpcHandler: Successfully registered procedure")

      {:error, reason} ->
        Logger.error("RegisterHome.RpcHandler: Failed to register procedure: #{inspect(reason)}")
    end
  end

  # RPC call handler

  defp handle_call(_args, kwargs, _details) do
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

    Logger.info("RegisterHome.RpcHandler: register_home called with home_id=#{inspect(home_id)}, name=#{inspect(name)}")

    unless home_id do
      Logger.warning("RegisterHome.RpcHandler: Missing home_id")
      {:error, "wamp.error.invalid_argument"}
    else
      # Check if home already exists
      exists = Repo.exists?(from h in HomeState, where: h.home_id == ^home_id)

      if exists do
        Logger.warning("RegisterHome.RpcHandler: home_id #{home_id} already exists")
        {:error, "wamp.error.already_exists"}
      else
        # Create complete record with RESERVED status
        changeset =
          HomeState.changeset(%HomeState{}, %{
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
            battery_capacity_kwh: battery_capacity_kwh,
            status: 1,
            # RESERVED flag
            energy_bought_kwh: 0.0,
            energy_sold_kwh: 0.0,
            net_balance_kwh: 0.0,
            cost_paid: 0.0,
            revenue_received: 0.0,
            net_cost: 0.0,
            cortexiq_total_commission: 0.0,
            cortexiq_total_savings: 0.0,
            cortexiq_net_savings: 0.0,
            contract_switches_count: 0
          })

        case Repo.insert(changeset) do
          {:ok, _home_state} ->
            Logger.info("RegisterHome.RpcHandler: Successfully registered home #{home_id}")
            {:ok, %{registered: true, home_id: home_id}}

          {:error, changeset} ->
            Logger.error(
              "RegisterHome.RpcHandler: Failed to register home #{home_id}: #{inspect(changeset)}"
            )

            {:error, "wamp.error.runtime_error"}
        end
      end
    end
  rescue
    e ->
      Logger.error("RegisterHome.RpcHandler: Unexpected error: #{inspect(e)}")
      {:error, "wamp.error.runtime_error"}
  end
end
