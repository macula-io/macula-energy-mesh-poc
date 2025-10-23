defmodule CortexIqDashboard.EventAggregator do
  @moduledoc """
  Subscribes to WAMP events and aggregates them into the database.

  This reduces load on the LiveView by pre-aggregating data.
  LiveView can then poll the database instead of processing every event.
  """
  use GenServer
  require Logger
  import Ecto.Query
  alias CortexIqDashboard.Repo
  alias CortexIqDashboard.Schemas.{HomeState, ProviderState, SystemStats}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to WAMP events via PubSub
    if connected?() do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "wamp:events")
      Logger.info("EventAggregator: Subscribed to WAMP events")
    end

    # Initialize system stats if doesn't exist
    Repo.insert!(
      %SystemStats{id: 1},
      on_conflict: :nothing,
      conflict_target: :id
    )

    {:ok, %{event_count: 0}}
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, state) do
    real_topic = get_in(event_data, [:details, "topic"]) || "unknown"

    # Process event and update database
    process_event(real_topic, event_data)

    # Log every 1000 events
    new_count = state.event_count + 1
    if rem(new_count, 1000) == 0 do
      Logger.info("EventAggregator: Processed #{new_count} events")
    end

    {:noreply, %{state | event_count: new_count}}
  end

  defp process_event(topic, event_data) do
    kwargs = event_data[:kwargs] || %{}

    cond do
      # Home production event
      String.contains?(topic, ".home.") && String.contains?(topic, ".production") ->
        update_home_production(topic, kwargs)

      # Home consumption event
      String.contains?(topic, ".home.") && String.contains?(topic, ".consumption") ->
        update_home_consumption(topic, kwargs)

      # Home storage/battery event
      String.contains?(topic, ".home.") && String.contains?(topic, ".storage") ->
        update_home_battery(topic, kwargs)

      # Home balance event
      String.contains?(topic, ".home.") && String.contains?(topic, ".balance") ->
        update_home_balance(topic, kwargs)

      # Home contract event
      String.contains?(topic, ".home.") && String.contains?(topic, ".contract") ->
        update_home_contract(topic, kwargs)

      # Provider contract offer
      String.contains?(topic, ".provider.") && String.contains?(topic, ".contract_offer") ->
        update_provider_offer(topic, kwargs)

      # Simulation time
      String.contains?(topic, ".simulation.time") ->
        update_simulation_time(kwargs)

      # Contract switch event
      String.contains?(topic, ".market.contract.switched") ->
        increment_contract_switches()

      true ->
        :ok
    end
  end

  defp update_home_production(topic, kwargs) do
    home_id = extract_home_id(topic)
    production_kw = Map.get(kwargs, "watts", 0.0) / 1000.0

    ensure_home_exists(home_id)

    from(h in HomeState, where: h.home_id == ^home_id)
    |> Repo.update_all(
      set: [
        production_kw: production_kw,
        last_event_at: DateTime.utc_now()
      ]
    )
  end

  defp update_home_consumption(topic, kwargs) do
    home_id = extract_home_id(topic)
    consumption_kw = Map.get(kwargs, "watts", 0.0) / 1000.0

    ensure_home_exists(home_id)

    from(h in HomeState, where: h.home_id == ^home_id)
    |> Repo.update_all(
      set: [
        consumption_kw: consumption_kw,
        last_event_at: DateTime.utc_now()
      ]
    )
  end

  defp update_home_battery(topic, kwargs) do
    home_id = extract_home_id(topic)
    battery_percent = Map.get(kwargs, "battery_percent", 0.0)

    ensure_home_exists(home_id)

    from(h in HomeState, where: h.home_id == ^home_id)
    |> Repo.update_all(
      set: [
        battery_percent: battery_percent,
        last_event_at: DateTime.utc_now()
      ]
    )
  end

  defp update_home_balance(topic, kwargs) do
    home_id = extract_home_id(topic)

    ensure_home_exists(home_id)

    from(h in HomeState, where: h.home_id == ^home_id)
    |> Repo.update_all(
      set: [
        energy_bought_kwh: Map.get(kwargs, "energy_bought_kwh", 0.0),
        energy_sold_kwh: Map.get(kwargs, "energy_sold_kwh", 0.0),
        net_balance_kwh: Map.get(kwargs, "net_balance_kwh", 0.0),
        cost_paid: Map.get(kwargs, "cost_paid", 0.0),
        revenue_received: Map.get(kwargs, "revenue_received", 0.0),
        net_cost: Map.get(kwargs, "net_cost", 0.0),
        last_event_at: DateTime.utc_now()
      ]
    )
  end

  defp update_home_contract(topic, kwargs) do
    home_id = extract_home_id(topic)

    ensure_home_exists(home_id)

    from(h in HomeState, where: h.home_id == ^home_id)
    |> Repo.update_all(
      set: [
        provider_id: Map.get(kwargs, "provider_id"),
        contract_id: Map.get(kwargs, "contract_id"),
        contract_expires_at: parse_datetime(Map.get(kwargs, "end_date")),
        last_event_at: DateTime.utc_now()
      ]
    )
  end

  defp update_provider_offer(topic, kwargs) do
    provider_id = extract_provider_id(topic)

    Repo.insert!(
      %ProviderState{
        provider_id: provider_id,
        provider_name: Map.get(kwargs, "provider_name"),
        strategy: Map.get(kwargs, "strategy"),
        day_buy_price: Map.get(kwargs, "day_buy_price"),
        night_buy_price: Map.get(kwargs, "night_buy_price"),
        day_sell_price: Map.get(kwargs, "day_sell_price"),
        night_sell_price: Map.get(kwargs, "night_sell_price"),
        switching_discount: Map.get(kwargs, "switching_discount"),
        last_event_at: DateTime.utc_now()
      },
      on_conflict: [
        set: [
          provider_name: Map.get(kwargs, "provider_name"),
          strategy: Map.get(kwargs, "strategy"),
          day_buy_price: Map.get(kwargs, "day_buy_price"),
          night_buy_price: Map.get(kwargs, "night_buy_price"),
          day_sell_price: Map.get(kwargs, "day_sell_price"),
          night_sell_price: Map.get(kwargs, "night_sell_price"),
          switching_discount: Map.get(kwargs, "switching_discount"),
          last_event_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :provider_id
    )

    # Update market share
    update_market_shares()
  end

  defp update_simulation_time(kwargs) do
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(
      set: [
        simulation_time: parse_datetime(Map.get(kwargs, "simulation_time")),
        simulation_speed: Map.get(kwargs, "speed"),
        updated_at: DateTime.utc_now()
      ]
    )
  end

  defp increment_contract_switches do
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(inc: [contract_switches_count: 1])
  end

  defp ensure_home_exists(home_id) do
    location = CortexIqCore.Geography.location_for_home(home_id)

    Repo.insert!(
      %HomeState{
        home_id: home_id,
        location: location.city,
        postal_code: location.postal_code,
        region: to_string(location.region)
      },
      on_conflict: :nothing,
      conflict_target: :home_id
    )
  end

  defp update_market_shares do
    # Count contracts per provider
    contract_counts =
      from(h in HomeState,
        where: not is_nil(h.provider_id),
        group_by: h.provider_id,
        select: {h.provider_id, count(h.home_id)}
      )
      |> Repo.all()
      |> Map.new()

    total_contracts = Enum.sum(Map.values(contract_counts))

    # Update each provider's market share
    Enum.each(contract_counts, fn {provider_id, count} ->
      share_percent = if total_contracts > 0, do: count / total_contracts * 100, else: 0.0

      from(p in ProviderState, where: p.provider_id == ^provider_id)
      |> Repo.update_all(
        set: [
          active_contracts: count,
          market_share_percent: share_percent
        ]
      )
    end)
  end

  defp extract_home_id(topic) do
    # Topic format: "energy.hub.home.home_0001.production"
    topic
    |> String.split(".")
    |> Enum.at(3, "unknown")
  end

  defp extract_provider_id(topic) do
    # Topic format: "energy.hub.provider.provider_a.contract_offer"
    topic
    |> String.split(".")
    |> Enum.at(3, "unknown")
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: nil

  defp connected?, do: Process.whereis(CortexIqDashboard.PubSub) != nil
end
