defmodule MeshEdgeHomes.HomeBot do
  @moduledoc """
  GenServer representing a single home with solar panels, battery, and consumption.

  Publishes to WAMP topics:
  - energy.home.{id}.production
  - energy.home.{id}.consumption
  - energy.home.{id}.storage
  - energy.home.{id}.contract
  """
  use GenServer
  require Logger

  alias MeshWamp

  defstruct [
    :home_id,
    :wamp_client,
    :realm,
    # Production (solar/wind)
    :solar_capacity_kw,
    # Consumption
    :base_load_w,
    # Battery
    :battery_capacity_kwh,
    :battery_charge_percent,
    # Provider contract
    :current_provider,
    # Simulation time
    :sim_time
  ]

  @update_interval_ms 5_000  # Update every 5 seconds

  ## Client API

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  def get_state(home_id) do
    GenServer.call(via_tuple(home_id), :get_state)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    realm = Keyword.get(opts, :realm, "com.energy.mesh")
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")

    Logger.info("Starting HomeBot for #{home_id}")

    # Connect to WAMP
    {:ok, wamp_client} = MeshWamp.start_link(
      url: bondy_url,
      realm: realm
    )

    # Initialize state with randomized values for diversity
    state = %__MODULE__{
      home_id: home_id,
      wamp_client: wamp_client,
      realm: realm,
      solar_capacity_kw: 3.0 + :rand.uniform() * 2.0,  # 3-5 kW
      base_load_w: 300 + :rand.uniform(200),  # 300-500 W
      battery_capacity_kwh: 10.0,
      battery_charge_percent: 50.0 + :rand.uniform() * 30.0,  # 50-80%
      current_provider: "provider_#{:rand.uniform(5)}",
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
    # Update simulation time (100x speed: 1 real second = 100 sim seconds)
    new_sim_time = state.sim_time + 500  # 5 seconds * 100

    # Calculate solar production based on time of day
    production_w = calculate_solar_production(new_sim_time, state.solar_capacity_kw)

    # Calculate consumption based on time of day
    consumption_w = calculate_consumption(new_sim_time, state.base_load_w)

    # Update battery
    net_power = production_w - consumption_w
    new_battery_percent = update_battery(state.battery_charge_percent, net_power, state.battery_capacity_kwh)

    # Publish production event
    publish_production(state, production_w)

    # Publish consumption event
    publish_consumption(state, consumption_w)

    # Publish storage event
    publish_storage(state, new_battery_percent)

    # Schedule next update
    schedule_update()

    new_state = %{state |
      sim_time: new_sim_time,
      battery_charge_percent: new_battery_percent
    }

    {:noreply, new_state}
  end

  ## Private Functions

  defp via_tuple(home_id) do
    {:via, Registry, {MeshEdgeHomes.Registry, home_id}}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @update_interval_ms)
  end

  defp calculate_solar_production(sim_time_seconds, capacity_kw) do
    # Simulate 24-hour day cycle
    day_seconds = 86400  # 24 hours
    hour_of_day = rem(sim_time_seconds, day_seconds) / 3600.0

    # Solar production peaks at noon (hour 12)
    # Use sine wave: 0 at night, peak at noon
    if hour_of_day >= 6 and hour_of_day <= 18 do
      # Daylight hours (6am to 6pm)
      angle = (hour_of_day - 6) / 12.0 * :math.pi()
      peak_production = capacity_kw * 1000  # Convert to watts
      production = peak_production * :math.sin(angle)

      # Add some randomness (+/- 20%)
      production * (0.8 + :rand.uniform() * 0.4)
    else
      0.0
    end
  end

  defp calculate_consumption(sim_time_seconds, base_load_w) do
    day_seconds = 86400
    hour_of_day = rem(sim_time_seconds, day_seconds) / 3600.0

    # Base consumption patterns (ensure float result)
    consumption = base_load_w * 1.0 +
      # Morning peak (7-9am): +1500W
      morning_peak(hour_of_day) +
      # Evening peak (6-10pm): +2000W
      evening_peak(hour_of_day) +
      # Random appliances
      :rand.uniform(300)

    consumption
  end

  defp morning_peak(hour) when hour >= 7 and hour < 9, do: 1500
  defp morning_peak(_), do: 0

  defp evening_peak(hour) when hour >= 18 and hour < 22, do: 2000
  defp evening_peak(_), do: 0

  defp update_battery(current_percent, net_power_w, capacity_kwh) do
    # Convert net power to kWh over 5-second interval
    energy_kwh = net_power_w / 1000.0 * (5.0 / 3600.0)  # 5 seconds in hours

    # Update percentage
    delta_percent = (energy_kwh / capacity_kwh) * 100.0
    new_percent = current_percent + delta_percent

    # Clamp between 0 and 100
    min(100.0, max(0.0, new_percent))
  end

  defp publish_production(state, watts) do
    topic = "energy.home.#{state.home_id}.production"
    payload = %{
      "home_id" => state.home_id,
      "watts" => Float.round(watts, 2),
      "source" => "solar",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Publish with payload as kwargs (4th argument), not args
    MeshWamp.publish(state.wamp_client, topic, [], payload, %{})
  end

  defp publish_consumption(state, watts) do
    topic = "energy.home.#{state.home_id}.consumption"
    payload = %{
      "home_id" => state.home_id,
      "watts" => Float.round(watts, 2),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Publish with payload as kwargs (4th argument), not args
    MeshWamp.publish(state.wamp_client, topic, [], payload, %{})
  end

  defp publish_storage(state, battery_percent) do
    topic = "energy.home.#{state.home_id}.storage"
    payload = %{
      "home_id" => state.home_id,
      "battery_percent" => Float.round(battery_percent, 2),
      "capacity_kwh" => state.battery_capacity_kwh,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Publish with payload as kwargs (4th argument), not args
    MeshWamp.publish(state.wamp_client, topic, [], payload, %{})
  end
end
