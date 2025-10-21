defmodule MeshEdgeUtilities.ProviderBot do
  @moduledoc """
  GenServer representing an energy provider with dynamic pricing.

  Publishes to WAMP topics:
  - energy.utility.{id}.tariff

  Pricing strategies:
  - Provider A: "Steady Eddie" - consistent mid-range pricing
  - Provider B: "Night Owl" - cheap at night, expensive during day
  - Provider C: "Solar Surfer" - follows solar production patterns
  - Provider D: "Peak Predator" - high during peak hours
  - Provider E: "Random Racer" - frequent small price changes
  """
  use GenServer
  require Logger

  alias MeshWamp

  defstruct [
    :provider_id,
    :provider_name,
    :regions,
    :wamp_client,
    :realm,
    :strategy,
    :base_price,
    :sim_time
  ]

  @update_interval_ms 10_000  # Update every 10 seconds (faster for demo)

  # Real Belgian utility providers with their strategies and regional coverage
  @providers %{
    "engie" => %{
      name: "Engie",
      strategy: :steady_eddie,
      regions: [:brussels, :flanders, :wallonia]  # Nationwide
    },
    "luminus" => %{
      name: "Luminus",
      strategy: :night_owl,
      regions: [:brussels, :flanders, :wallonia]  # Nationwide
    },
    "essent" => %{
      name: "Essent",
      strategy: :solar_surfer,
      regions: [:brussels, :flanders, :wallonia]  # Nationwide
    },
    "totalenergies" => %{
      name: "TotalEnergies",
      strategy: :peak_predator,
      regions: [:brussels, :wallonia]  # Not in Flanders
    },
    "bolt" => %{
      name: "Bolt",
      strategy: :random_racer,
      regions: [:brussels, :flanders]  # Flanders specialist
    }
  }

  ## Client API

  def start_link(opts) do
    provider_id = Keyword.fetch!(opts, :provider_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(provider_id))
  end

  def get_state(provider_id) do
    GenServer.call(via_tuple(provider_id), :get_state)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    provider_id = Keyword.fetch!(opts, :provider_id)
    realm = Keyword.get(opts, :realm, "com.energy.mesh")
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")

    # Get provider metadata
    provider_info = Map.get(@providers, provider_id)
    provider_name = provider_info.name
    strategy = provider_info.strategy
    regions = provider_info.regions

    Logger.info("Starting ProviderBot for #{provider_name} (#{provider_id})")

    # Connect to WAMP
    {:ok, wamp_client} = MeshWamp.start_link(
      url: bondy_url,
      realm: realm
    )

    state = %__MODULE__{
      provider_id: provider_id,
      provider_name: provider_name,
      regions: regions,
      wamp_client: wamp_client,
      realm: realm,
      strategy: strategy,
      base_price: 0.12 + :rand.uniform() * 0.06,  # €0.12-0.18 per kWh
      sim_time: 0
    }

    # Schedule first update
    schedule_update()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:update, state) do
    Logger.debug("Provider #{state.provider_id} :update triggered")

    # Update simulation time (100x speed)
    new_sim_time = state.sim_time + 1000  # 10 seconds * 100

    # Calculate price based on strategy
    price_per_kwh = calculate_price(state.strategy, new_sim_time, state.base_price)

    # Publish tariff
    publish_tariff(state, price_per_kwh)

    # Schedule next update
    schedule_update()

    new_state = %{state | sim_time: new_sim_time}

    {:noreply, new_state}
  end

  ## Private Functions

  defp via_tuple(provider_id) do
    {:via, Registry, {MeshEdgeUtilities.Registry, provider_id}}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @update_interval_ms)
  end

  defp calculate_price(:steady_eddie, _sim_time, base_price) do
    # Consistent mid-range price with small random variation
    base_price * (0.98 + :rand.uniform() * 0.04)
  end

  defp calculate_price(:night_owl, sim_time, base_price) do
    # Cheap at night (10pm-6am), expensive during day
    hour_of_day = hour_from_sim_time(sim_time)

    if hour_of_day >= 22 or hour_of_day < 6 do
      # Night time - 30% cheaper
      base_price * 0.7
    else
      # Day time - 20% more expensive
      base_price * 1.2
    end
  end

  defp calculate_price(:solar_surfer, sim_time, base_price) do
    # Follows solar production - cheap when sun is shining
    hour_of_day = hour_from_sim_time(sim_time)

    if hour_of_day >= 10 and hour_of_day <= 16 do
      # Peak solar hours - 25% cheaper
      base_price * 0.75
    else
      # Other times - standard or higher
      base_price * 1.1
    end
  end

  defp calculate_price(:peak_predator, sim_time, base_price) do
    # High prices during peak consumption hours
    hour_of_day = hour_from_sim_time(sim_time)

    cond do
      # Morning peak (7-9am)
      hour_of_day >= 7 and hour_of_day < 9 ->
        base_price * 1.4

      # Evening peak (6-10pm)
      hour_of_day >= 18 and hour_of_day < 22 ->
        base_price * 1.5

      # Off-peak
      true ->
        base_price * 0.8
    end
  end

  defp calculate_price(:random_racer, _sim_time, base_price) do
    # Frequent random changes +/- 25%
    base_price * (0.75 + :rand.uniform() * 0.5)
  end

  defp hour_from_sim_time(sim_time) do
    day_seconds = 86400
    rem(sim_time, day_seconds) / 3600.0
  end

  defp publish_tariff(state, price_per_kwh) do
    topic = "energy.utility.#{state.provider_id}.tariff"

    # Buy-back rate (selling to grid) is typically 70% of purchase price
    sell_back_rate = price_per_kwh * 0.7

    payload = %{
      "provider_id" => state.provider_id,
      "provider_name" => state.provider_name,
      "regions" => Enum.map(state.regions, &Atom.to_string/1),
      "price_per_kwh" => Float.round(price_per_kwh, 4),
      "sell_back_rate" => Float.round(sell_back_rate, 4),
      "strategy" => Atom.to_string(state.strategy),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("⚡ Publishing tariff: #{state.provider_name} -> €#{Float.round(price_per_kwh, 4)}/kWh to #{topic}")

    # Publish with payload as kwargs (4th argument), not args
    MeshWamp.publish(state.wamp_client, topic, [], payload, %{})
  end
end
