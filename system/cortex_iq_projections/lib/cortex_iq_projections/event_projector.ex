defmodule CortexIqProjections.EventProjector do
  @moduledoc """
  Subscribes to WAMP events and projects them into database read models.

  This is the write side of the CQRS pattern:
  - Event producers (homes, utilities) publish events to WAMP
  - EventProjector consumes events and builds projections (read models)
  - Dashboard queries the projections for display
  """
  use GenServer
  require Logger
  import Ecto.Query, only: [from: 2]
  alias MaculaOs.Wamp.Client
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState, SystemStats}
  alias CortexIqDashboardSchemas.TimeSeries.{EnergyEvent, EnergyTrade, ContractEvent}

  defmodule State do
    @moduledoc false
    defstruct [:wamp_client, :connection_status]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    bondy_realm = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    state = %State{
      connection_status: :connecting
    }

    # Start WAMP client connection
    case Client.start_link(
           url: bondy_url,
           realm: bondy_realm,
           name: :event_projector_wamp_client
         ) do
      {:ok, wamp_client} ->
        Logger.info("EventProjector: WAMP client started, connecting to #{bondy_url}")

        # Wait for connection before subscribing
        Process.send_after(self(), :subscribe_to_events, 5000)

        {:ok, %{state | wamp_client: wamp_client}}

      {:error, reason} ->
        Logger.error("EventProjector: Failed to start WAMP client: #{inspect(reason)}")
        # Retry connection
        Process.send_after(self(), :retry_connection, 5000)
        {:ok, state}
    end
  end

  @impl true
  def handle_info(:retry_connection, state) do
    {:stop, :retry_connection, state}
  end

  def handle_info(:subscribe_to_events, %{wamp_client: wamp_client} = state) do
    Logger.info("EventProjector: Subscribing to WAMP event topics")

    topics = [
      # Home events - wildcard prefix match (matches be.cortexiq.home.*)
      {"be.cortexiq.home..", &handle_home_event/2},

      # Provider events - wildcard prefix match (matches be.cortexiq.provider.*)
      {"be.cortexiq.provider..", &handle_provider_event/2},

      # Market events - wildcard prefix match (matches be.cortexiq.market.*)
      {"be.cortexiq.market..", &handle_market_event/2},

      # Simulation time - exact match
      {"be.cortexiq.simulation.time_advanced", &handle_time_advanced/2}
    ]

    Enum.each(topics, fn {topic, handler} ->
      case Client.subscribe(wamp_client, topic, handler) do
        :ok ->
          Logger.info("EventProjector: Subscribed to #{topic}")
        {:error, reason} ->
          Logger.error("EventProjector: Failed to subscribe to #{topic}: #{inspect(reason)}")
      end
    end)

    {:noreply, %{state | connection_status: :connected}}
  end

  def handle_info(msg, state) do
    Logger.debug("EventProjector: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handlers

  defp handle_home_event(topic, event_data) do
    # Extract kwargs from WAMP event
    kwargs = Map.get(event_data, :kwargs, %{})

    # Extract event type from topic: be.cortexiq.home.{home_id}.{event_type}
    case String.split(topic, ".") do
      ["be", "cortexiq", "home", home_id, event_type] ->
        project_home_event(home_id, event_type, kwargs)

      _ ->
        Logger.warning("EventProjector: Unexpected home topic format: #{topic}")
    end
  rescue
    error ->
      Logger.error("EventProjector: Error handling home event: #{inspect(error)}")
      Logger.error(Exception.format(:error, error, __STACKTRACE__))
  end

  defp handle_provider_event(topic, event_data) do
    # Extract kwargs from WAMP event
    kwargs = Map.get(event_data, :kwargs, %{})

    # Extract event type from topic: be.cortexiq.provider.{provider_id}.{event_type}
    case String.split(topic, ".") do
      ["be", "cortexiq", "provider", provider_id, event_type] ->
        project_provider_event(provider_id, event_type, kwargs)

      _ ->
        Logger.warning("EventProjector: Unexpected provider topic format: #{topic}")
    end
  rescue
    error ->
      Logger.error("EventProjector: Error handling provider event: #{inspect(error)}")
      Logger.error(Exception.format(:error, error, __STACKTRACE__))
  end

  defp handle_market_event(topic, event_data) do
    # Extract kwargs from WAMP event
    kwargs = Map.get(event_data, :kwargs, %{})

    # Extract event type from topic: be.cortexiq.market.{event_type}
    case String.split(topic, ".") do
      ["be", "cortexiq", "market", event_type | _rest] ->
        project_market_event(event_type, kwargs)

      _ ->
        Logger.warning("EventProjector: Unexpected market topic format: #{topic}")
    end
  rescue
    error ->
      Logger.error("EventProjector: Error handling market event: #{inspect(error)}")
      Logger.error(Exception.format(:error, error, __STACKTRACE__))
  end

  defp handle_time_advanced(_topic, event_data) do
    # Extract kwargs from WAMP event
    kwargs = Map.get(event_data, :kwargs, %{})

    # Update system stats with current simulation time
    simulation_time = parse_datetime(kwargs["simulation_time"])
    speed = kwargs["speed"] || 105_120

    Repo.insert!(
      %SystemStats{id: 1},
      on_conflict: [set: [simulation_time: simulation_time, simulation_speed: speed, updated_at: DateTime.utc_now()]],
      conflict_target: :id
    )
  rescue
    error ->
      Logger.error("EventProjector: Error handling time_advanced: #{inspect(error)}")
  end

  # Home Event Projections

  defp project_home_event(home_id, "production", kwargs) do
    watts = kwargs["watts"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update home_states
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [set: [production_kw: watts / 1000.0, last_event_at: simulation_time, updated_at: DateTime.utc_now()]],
      conflict_target: :home_id
    )

    # Insert into energy_events time-series
    Repo.insert!(
      %EnergyEvent{
        home_id: home_id,
        simulation_time: simulation_time,
        production_watts: watts,
        recorded_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      conflict_target: [:home_id, :simulation_time]
    )
  end

  defp project_home_event(home_id, "consumption", kwargs) do
    watts = kwargs["watts"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update home_states
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [set: [consumption_kw: watts / 1000.0, last_event_at: simulation_time, updated_at: DateTime.utc_now()]],
      conflict_target: :home_id
    )

    # Update energy_events time-series
    Repo.insert!(
      %EnergyEvent{
        home_id: home_id,
        simulation_time: simulation_time,
        consumption_watts: watts,
        recorded_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      conflict_target: [:home_id, :simulation_time]
    )
  end

  defp project_home_event(home_id, "storage", kwargs) do
    battery_percent = kwargs["battery_percent"] || 0.0
    capacity_kwh = kwargs["capacity_kwh"] || 10.0
    state_atom = String.to_atom(kwargs["state"] || "idle")
    simulation_time = parse_datetime(kwargs["simulation_time"])

    battery_kwh = capacity_kwh * (battery_percent / 100.0)

    # Update home_states
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          battery_percent: battery_percent,
          battery_kwh: battery_kwh,
          battery_capacity_kwh: capacity_kwh,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    # Update energy_events time-series
    Repo.insert!(
      %EnergyEvent{
        home_id: home_id,
        simulation_time: simulation_time,
        battery_percent: battery_percent,
        battery_kwh: battery_kwh,
        battery_state: Atom.to_string(state_atom),
        recorded_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      conflict_target: [:home_id, :simulation_time]
    )
  end

  defp project_home_event(home_id, "balance", kwargs) do
    energy_bought_kwh = kwargs["energy_bought_kwh"] || 0.0
    energy_sold_kwh = kwargs["energy_sold_kwh"] || 0.0
    net_balance_kwh = kwargs["net_balance_kwh"] || 0.0
    cost_paid = kwargs["cost_paid"] || 0.0
    revenue_received = kwargs["revenue_received"] || 0.0
    net_cost = kwargs["net_cost"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update home_states
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          energy_bought_kwh: energy_bought_kwh,
          energy_sold_kwh: energy_sold_kwh,
          net_balance_kwh: net_balance_kwh,
          cost_paid: cost_paid,
          revenue_received: revenue_received,
          net_cost: net_cost,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )
  end

  defp project_home_event(home_id, "contract" <> _, kwargs) do
    contract_id = kwargs["contract_id"]
    provider_id = kwargs["provider_id"]
    start_date = parse_datetime(kwargs["start_date"])
    end_date = parse_datetime(kwargs["end_date"])
    simulation_time = parse_datetime(kwargs["simulation_time"])
    reason = kwargs["reason"] || "new"

    # Update home_states with contract info
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          provider_id: provider_id,
          contract_id: contract_id,
          contract_expires_at: end_date,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    # Insert contract event
    Repo.insert!(%ContractEvent{
      contract_id: contract_id,
      home_id: home_id,
      provider_id: provider_id,
      event_type: reason,
      simulation_time: simulation_time,
      start_date: start_date,
      end_date: end_date,
      day_buy_price: kwargs["terms"]["day_buy_price"],
      night_buy_price: kwargs["terms"]["night_buy_price"],
      day_sell_price: kwargs["terms"]["day_sell_price"],
      night_sell_price: kwargs["terms"]["night_sell_price"],
      switching_discount: kwargs["terms"]["switching_discount"]
    })
  end

  defp project_home_event(_home_id, event_type, _kwargs) do
    Logger.debug("EventProjector: Unhandled home event type: #{event_type}")
  end

  # Provider Event Projections

  defp project_provider_event(provider_id, "contract_offer", kwargs) do
    day_buy_price = kwargs["day_buy_price"]
    night_buy_price = kwargs["night_buy_price"]
    day_sell_price = kwargs["day_sell_price"]
    night_sell_price = kwargs["night_sell_price"]
    switching_discount = kwargs["switching_discount"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update provider_states with latest offer
    Repo.insert!(
      %ProviderState{provider_id: provider_id},
      on_conflict: [
        set: [
          day_buy_price: day_buy_price,
          night_buy_price: night_buy_price,
          day_sell_price: day_sell_price,
          night_sell_price: night_sell_price,
          switching_discount: switching_discount,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :provider_id
    )
  end

  defp project_provider_event(_provider_id, event_type, _kwargs) do
    Logger.debug("EventProjector: Unhandled provider event type: #{event_type}")
  end

  # Market Event Projections

  defp project_market_event("contract" <> _, kwargs) do
    home_id = kwargs["home_id"]
    from_provider_id = kwargs["from_provider_id"]
    to_provider_id = kwargs["to_provider_id"] || kwargs["provider_id"]
    contract_id = kwargs["to_contract_id"] || kwargs["contract_id"]
    simulation_time = parse_datetime(kwargs["simulation_time"])
    reason = kwargs["reason"] || "switch"

    # Update contract counts for providers using update_all (atomic)
    if from_provider_id do
      # Decrement old provider (ensure doesn't go below 0)
      from(p in ProviderState, where: p.provider_id == ^from_provider_id)
      |> Repo.update_all(
        set: [
          active_contracts: Ecto.Query.fragment("GREATEST(0, active_contracts - 1)"),
          updated_at: DateTime.utc_now()
        ]
      )
    end

    # Increment new provider (or insert if doesn't exist)
    query = from(p in ProviderState, where: p.provider_id == ^to_provider_id)
    case Repo.update_all(query, inc: [active_contracts: 1], set: [updated_at: DateTime.utc_now()]) do
      {0, _} ->
        # Provider doesn't exist, insert it
        Repo.insert!(
          %ProviderState{provider_id: to_provider_id, active_contracts: 1},
          on_conflict: :nothing,
          conflict_target: :provider_id
        )
      _ -> :ok
    end

    # Update system stats
    if reason == "switch" do
      from(s in SystemStats, where: s.id == 1)
      |> Repo.update_all(inc: [contract_switches_count: 1], set: [updated_at: DateTime.utc_now()])
    end

    # Insert contract event
    Repo.insert!(%ContractEvent{
      contract_id: contract_id,
      home_id: home_id,
      provider_id: to_provider_id,
      event_type: reason,
      simulation_time: simulation_time,
      previous_contract_id: kwargs["from_contract_id"],
      previous_provider_id: from_provider_id,
      switch_reason: kwargs["reason"],
      projected_savings: kwargs["projected_savings"],
      days_before_expiry: kwargs["days_before_expiry"],
      day_buy_price: kwargs["terms"]["day_buy_price"],
      night_buy_price: kwargs["terms"]["night_buy_price"],
      day_sell_price: kwargs["terms"]["day_sell_price"],
      night_sell_price: kwargs["terms"]["night_sell_price"],
      switching_discount: kwargs["terms"]["switching_discount"]
    })
  end

  defp project_market_event("trade", kwargs) do
    home_id = kwargs["home_id"]
    provider_id = kwargs["provider_id"]
    contract_id = kwargs["contract_id"]
    type = String.to_atom(kwargs["type"] || "buy")
    kwh = kwargs["kwh"] || 0.0
    price_per_kwh = kwargs["price_per_kwh"] || 0.0
    total = kwargs["total"] || 0.0
    is_day = kwargs["is_day"] || true
    simulation_time = parse_datetime(kwargs["simulation_time"])

    {import_kwh, export_kwh, import_cost, export_revenue} =
      case type do
        :buy -> {kwh, 0.0, total, 0.0}
        :sell -> {0.0, kwh, 0.0, total}
      end

    # Insert energy trade
    Repo.insert!(
      %EnergyTrade{
        home_id: home_id,
        provider_id: provider_id,
        contract_id: contract_id,
        simulation_time: simulation_time,
        simulation_hour: simulation_time.hour,
        grid_import_kwh: import_kwh,
        grid_export_kwh: export_kwh,
        import_price_per_kwh: if(type == :buy, do: price_per_kwh, else: nil),
        export_price_per_kwh: if(type == :sell, do: price_per_kwh, else: nil),
        is_day: is_day,
        import_cost: import_cost,
        export_revenue: export_revenue,
        net_cost: import_cost - export_revenue,
        recorded_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      conflict_target: [:home_id, :simulation_time]
    )
  end

  defp project_market_event(event_type, _kwargs) do
    Logger.debug("EventProjector: Unhandled market event type: #{event_type}")
  end

  # Helper Functions

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
  defp parse_datetime(%DateTime{} = dt), do: dt
end
