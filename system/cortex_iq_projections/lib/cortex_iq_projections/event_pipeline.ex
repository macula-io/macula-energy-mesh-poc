defmodule CortexIqProjections.EventPipeline do
  @moduledoc """
  Broadway pipeline for processing WAMP events with back-pressure.

  Configuration via environment variables:
  - BROADWAY_CONCURRENCY: Number of concurrent processors (default: 10)
  - BROADWAY_BATCH_SIZE: Batch size for database writes (default: 50)
  """
  use Broadway
  require Logger
  import Ecto.Query
  import Ecto.Query.API, only: [fragment: 1]
  alias Broadway.Message
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState, SystemStats}
  alias CortexIqDashboardSchemas.TimeSeries.{EnergyEvent, EnergyTrade, ContractEvent}

  def start_link(_opts) do
    # Fetch WAMP client from EventProjector (retries if not ready yet)
    wamp_client = get_wamp_client_with_retry()

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {CortexIqProjections.WampProducer, wamp_client: wamp_client},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: System.get_env("BROADWAY_CONCURRENCY", "10") |> String.to_integer(),
          max_demand: 1
        ]
      ],
      batchers: [
        database: [
          concurrency: System.get_env("BROADWAY_BATCH_CONCURRENCY", "5") |> String.to_integer(),
          batch_size: System.get_env("BROADWAY_BATCH_SIZE", "50") |> String.to_integer(),
          batch_timeout: 100
        ]
      ]
    )
  end

  # Pattern-matched handle_message clauses (idiomatic Elixir)

  @impl true
  def handle_message(:default, %Message{data: {:home_event, topic, event_data}} = message, _context) do
    process_home_event(topic, event_data)
    message |> Message.put_batcher(:database)
  end

  @impl true
  def handle_message(:default, %Message{data: {:provider_event, topic, event_data}} = message, _context) do
    process_provider_event(topic, event_data)
    message |> Message.put_batcher(:database)
  end

  @impl true
  def handle_message(:default, %Message{data: {:market_event, topic, event_data}} = message, _context) do
    process_market_event(topic, event_data)
    message |> Message.put_batcher(:database)
  end

  @impl true
  def handle_message(:default, %Message{data: {:time_advanced, _topic, event_data}} = message, _context) do
    process_time_advanced(event_data)
    message |> Message.put_batcher(:database)
  end

  # Fallthrough handler - CRITICAL to prevent mailbox clogging
  @impl true
  def handle_message(:default, %Message{data: event} = message, _context) do
    # Sample 1% to avoid log spam
    if :rand.uniform(100) == 1 do
      Logger.warning("EventPipeline: Unknown event type (sampled 1%): #{inspect(event)}")
    end

    # Still put in batcher to avoid blocking pipeline
    message |> Message.put_batcher(:database)
  end

  @impl true
  def handle_batch(:database, messages, _batch_info, _context) do
    # Batch database writes here if needed
    # For now, events are already written in handle_message
    # In future, we could collect all writes and do them in one transaction
    messages
  end

  # Event Processors

  defp process_home_event(topic, event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    case String.split(topic, ".") do
      ["be", "cortexiq", "home", "measured"] ->
        project_combined_home_event(kwargs)

      ["be", "cortexiq", "home", home_id, event_type] ->
        project_home_event(home_id, event_type, kwargs)

      _ ->
        # Sample 1% for unexpected topics to avoid log spam
        if :rand.uniform(100) == 1 do
          Logger.warning("EventPipeline: Unexpected home topic: #{topic}")
        end
    end
  end

  defp process_provider_event(topic, event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    case String.split(topic, ".") do
      ["be", "cortexiq", "provider", provider_id, event_type] ->
        project_provider_event(provider_id, event_type, kwargs)

      _ ->
        if :rand.uniform(100) == 1 do
          Logger.warning("EventPipeline: Unexpected provider topic: #{topic}")
        end
    end
  end

  defp process_market_event(topic, event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    case String.split(topic, ".") do
      ["be", "cortexiq", "market", event_type | _rest] ->
        project_market_event(event_type, kwargs)

      _ ->
        if :rand.uniform(100) == 1 do
          Logger.warning("EventPipeline: Unexpected market topic: #{topic}")
        end
    end
  end

  defp process_time_advanced(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})
    simulation_time = parse_datetime(kwargs["simulation_time"])
    speed = kwargs["speed"] || 105_120

    Repo.insert!(
      %SystemStats{id: 1},
      on_conflict: [set: [simulation_time: simulation_time, simulation_speed: speed, updated_at: DateTime.utc_now()]],
      conflict_target: :id
    )
  rescue
    error ->
      Logger.error("EventPipeline: Error handling time_advanced: #{inspect(error)}")
  end

  # Home Event Projections

  defp project_combined_home_event(kwargs) do
    home_id = kwargs["home_id"]

    unless is_nil(home_id) do
      internal = kwargs["_internal"] || %{}
      production_w = internal["production_w"] || 0.0
      consumption_w = internal["consumption_w"] || 0.0
      battery_kwh = internal["battery_kwh"] || 0.0
      battery_capacity_kwh = internal["battery_capacity_kwh"] || 10.0

      battery_percent = if battery_capacity_kwh > 0, do: (battery_kwh / battery_capacity_kwh) * 100.0, else: 0.0
      simulation_time = parse_datetime(kwargs["timestamp"])

      Repo.insert!(
        %HomeState{home_id: home_id},
        on_conflict: [
          set: [
            production_kw: production_w / 1000.0,
            consumption_kw: consumption_w / 1000.0,
            battery_percent: battery_percent,
            battery_kwh: battery_kwh,
            battery_capacity_kwh: battery_capacity_kwh,
            last_event_at: simulation_time,
            updated_at: DateTime.utc_now()
          ]
        ],
        conflict_target: :home_id
      )

      Repo.insert!(
        %EnergyEvent{
          home_id: home_id,
          simulation_time: simulation_time,
          production_watts: production_w,
          consumption_watts: consumption_w,
          battery_percent: battery_percent,
          battery_kwh: battery_kwh,
          recorded_at: DateTime.utc_now()
        },
        on_conflict: :nothing,
        conflict_target: [:home_id, :simulation_time]
      )
    end
  rescue
    error ->
      Logger.error("EventPipeline: Error projecting combined home event: #{inspect(error)}")
  end

  defp project_home_event(home_id, "production", kwargs) do
    watts = kwargs["watts"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [set: [production_kw: watts / 1000.0, last_event_at: simulation_time, updated_at: DateTime.utc_now()]],
      conflict_target: :home_id
    )

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

    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [set: [consumption_kw: watts / 1000.0, last_event_at: simulation_time, updated_at: DateTime.utc_now()]],
      conflict_target: :home_id
    )

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

  defp project_home_event(home_id, "contract" <> _, kwargs) do
    contract_id = kwargs["contract_id"]
    provider_id = kwargs["provider_id"]
    start_date = parse_datetime(kwargs["start_date"])
    end_date = parse_datetime(kwargs["end_date"])
    simulation_time = parse_datetime(kwargs["simulation_time"])
    reason = kwargs["reason"] || "new"

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

  defp project_home_event(_home_id, _event_type, _kwargs) do
    # Fallthrough - ignore unknown event types
    :ok
  end

  # Provider Event Projections

  defp project_provider_event(provider_id, "contract_offer", kwargs) do
    day_buy_price = kwargs["day_buy_price"]
    night_buy_price = kwargs["night_buy_price"]
    day_sell_price = kwargs["day_sell_price"]
    night_sell_price = kwargs["night_sell_price"]
    switching_discount = kwargs["switching_discount"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

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

  defp project_provider_event(_provider_id, _event_type, _kwargs) do
    # Fallthrough
    :ok
  end

  # Market Event Projections

  defp project_market_event("contract" <> _, kwargs) do
    home_id = kwargs["home_id"]
    from_provider_id = kwargs["from_provider_id"]
    to_provider_id = kwargs["to_provider_id"] || kwargs["provider_id"]
    contract_id = kwargs["to_contract_id"] || kwargs["contract_id"]
    simulation_time = parse_datetime(kwargs["simulation_time"])
    reason = kwargs["reason"] || "switch"

    if from_provider_id do
      from(p in ProviderState, where: p.provider_id == ^from_provider_id)
      |> Repo.update_all(
        set: [
          active_contracts: fragment("GREATEST(0, active_contracts - 1)"),
          updated_at: DateTime.utc_now()
        ]
      )
    end

    query = from(p in ProviderState, where: p.provider_id == ^to_provider_id)
    case Repo.update_all(query, inc: [active_contracts: 1], set: [updated_at: DateTime.utc_now()]) do
      {0, _} ->
        Repo.insert!(
          %ProviderState{provider_id: to_provider_id, active_contracts: 1},
          on_conflict: :nothing,
          conflict_target: :provider_id
        )
      _ -> :ok
    end

    if reason == "switch" do
      from(s in SystemStats, where: s.id == 1)
      |> Repo.update_all(inc: [contract_switches_count: 1], set: [updated_at: DateTime.utc_now()])
    end

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

  defp project_market_event(_event_type, _kwargs) do
    # Fallthrough
    :ok
  end

  # Helper Functions

  defp get_wamp_client_with_retry(retries \\ 10) do
    case GenServer.call(CortexIqProjections.EventProjector, :get_wamp_client, 5000) do
      nil when retries > 0 ->
        Logger.warning("EventPipeline: WAMP client not ready, retrying... (#{retries} left)")
        Process.sleep(500)
        get_wamp_client_with_retry(retries - 1)

      nil ->
        raise "EventPipeline: Failed to get WAMP client after retries"

      wamp_client ->
        Logger.info("EventPipeline: Got WAMP client: #{inspect(wamp_client)}")
        wamp_client
    end
  rescue
    error ->
      if retries > 0 do
        Logger.warning("EventPipeline: Error getting WAMP client (#{inspect(error)}), retrying... (#{retries} left)")
        Process.sleep(500)
        get_wamp_client_with_retry(retries - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
  defp parse_datetime(%DateTime{} = dt), do: dt
end
