defmodule CortexIqDashboard.Aggregates.HomeAggregate do
  @moduledoc """
  One GenServer per home - maintains home state in-memory.

  Subscribes to events for this specific home and updates its internal state.
  Broadcasts state changes to view aggregators via PubSub.
  """
  use GenServer
  require Logger

  defstruct [
    :home_id,
    # Home metadata (from registration/initialization)
    :name,                             # Family name
    :iot_provider,                     # IoT platform
    :location,                         # City
    :street,                           # Street address
    :postal_code,
    :region,
    :latitude,
    :longitude,
    :solar_capacity_kw,
    :battery_capacity_kwh,
    # HomeWizard-compatible fields
    power_w: 0.0,                      # Grid power (positive = import, negative = export)
    energy_import_kwh: 0.0,            # Cumulative grid import
    energy_export_kwh: 0.0,            # Cumulative grid export
    state_of_charge_pct: 0.0,          # Battery state of charge
    # Internal fields (from _internal payload)
    production_kw: 0.0,
    consumption_kw: 0.0,
    battery_kwh: 0.0,
    # Balance tracking (from separate balance events)
    energy_bought_kwh: 0.0,
    energy_sold_kwh: 0.0,
    net_balance_kwh: 0.0,
    cost_paid: 0.0,
    revenue_received: 0.0,
    net_cost: 0.0,
    # CortexIQ financial tracking
    cortexiq_total_commission: 0.0,
    cortexiq_total_savings: 0.0,
    cortexiq_net_savings: 0.0,
    # Contract info
    provider_id: nil,
    contract_id: nil,
    contract_expires_at: nil,
    # Status
    status: 1,                         # Default to RESERVED (1)
    last_event_at: nil
  ]

  # Client API

  def start_link(home_id) do
    GenServer.start_link(__MODULE__, home_id, name: via_tuple(home_id))
  end

  def update_measurement(home_id, measurement_data) do
    GenServer.cast(via_tuple(home_id), {:update_measurement, measurement_data})
  end

  def update_balance(home_id, balance_data) do
    GenServer.cast(via_tuple(home_id), {:update_balance, balance_data})
  end

  def update_contract(home_id, contract_data) do
    GenServer.cast(via_tuple(home_id), {:update_contract, contract_data})
  end

  def update_metadata(home_id, metadata) do
    GenServer.cast(via_tuple(home_id), {:update_metadata, metadata})
  end

  def update_status(home_id, status) do
    GenServer.cast(via_tuple(home_id), {:update_status, status})
  end

  def get_state(home_id) do
    GenServer.call(via_tuple(home_id), :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(home_id) do
    # Query database for full home metadata via WAMP RPC
    metadata = case load_home_metadata(home_id) do
      {:ok, data} -> data
      {:error, _reason} ->
        # Fallback to geography-derived location if database query fails
        location = CortexIqCore.Geography.location_for_home(home_id)
        %{
          "location" => location.city,
          "postal_code" => location.postal_code,
          "region" => to_string(location.region)
        }
    end

    state = %__MODULE__{
      home_id: home_id,
      name: Map.get(metadata, "name"),
      iot_provider: Map.get(metadata, "iot_provider"),
      location: Map.get(metadata, "location"),
      street: Map.get(metadata, "street"),
      postal_code: Map.get(metadata, "postal_code"),
      region: Map.get(metadata, "region"),
      latitude: Map.get(metadata, "latitude"),
      longitude: Map.get(metadata, "longitude"),
      solar_capacity_kw: Map.get(metadata, "solar_capacity_kw"),
      battery_capacity_kwh: Map.get(metadata, "battery_capacity_kwh"),
      status: Map.get(metadata, "status", 1)  # Default to RESERVED (1)
    }

    Logger.info("HomeAggregate: Initialized for #{home_id} - #{state.name} (#{state.location})")

    # Broadcast initial state
    broadcast_state_change(state)

    {:ok, state}
  end

  @impl true
  def handle_cast({:update_measurement, measurement_data}, state) do
    # Parse HomeWizard P1 Meter compatible measurement payload (DSMR 5.0)
    power_w = Map.get(measurement_data, "power_w", 0.0)
    energy_import_kwh = Map.get(measurement_data, "energy_import_kwh", 0.0)
    energy_export_kwh = Map.get(measurement_data, "energy_export_kwh", 0.0)
    state_of_charge_pct = Map.get(measurement_data, "state_of_charge_pct", 0.0)

    # Extract actual production/consumption from internal fields
    production_w = Map.get(measurement_data, "_production_w", 0.0)
    consumption_w = Map.get(measurement_data, "_consumption_w", 0.0)
    production_kw = production_w / 1000.0
    consumption_kw = consumption_w / 1000.0

    battery_kwh = Map.get(measurement_data, "_battery_kwh", 0.0)

    Logger.debug("HomeAggregate #{state.home_id}: production=#{production_kw}kW, consumption=#{consumption_kw}kW, grid_power=#{power_w}W, import=#{energy_import_kwh}kWh, export=#{energy_export_kwh}kWh, battery=#{state_of_charge_pct}%")

    new_state = %{state |
      # HomeWizard P1 Meter fields
      power_w: power_w,
      energy_import_kwh: energy_import_kwh,
      energy_export_kwh: energy_export_kwh,
      state_of_charge_pct: state_of_charge_pct,
      # Actual production/consumption from simulation
      production_kw: production_kw,
      consumption_kw: consumption_kw,
      battery_kwh: battery_kwh,
      last_event_at: DateTime.utc_now()
    }

    broadcast_state_change(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_balance, balance_data}, state) do
    new_state = %{state |
      energy_bought_kwh: Map.get(balance_data, "energy_bought_kwh", state.energy_bought_kwh),
      energy_sold_kwh: Map.get(balance_data, "energy_sold_kwh", state.energy_sold_kwh),
      net_balance_kwh: Map.get(balance_data, "net_balance_kwh", state.net_balance_kwh),
      cost_paid: Map.get(balance_data, "cost_paid", state.cost_paid),
      revenue_received: Map.get(balance_data, "revenue_received", state.revenue_received),
      net_cost: Map.get(balance_data, "net_cost", state.net_cost),
      last_event_at: DateTime.utc_now()
    }

    broadcast_state_change(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_contract, contract_data}, state) do
    Logger.info("HomeAggregate #{state.home_id}: Received contract update: provider=#{Map.get(contract_data, "provider_id")}, contract=#{Map.get(contract_data, "contract_id")}, expires=#{Map.get(contract_data, "end_date")}")

    new_state = %{state |
      provider_id: Map.get(contract_data, "provider_id"),
      contract_id: Map.get(contract_data, "contract_id"),
      contract_expires_at: parse_datetime(Map.get(contract_data, "end_date")),
      last_event_at: DateTime.utc_now()
    }

    Logger.info("HomeAggregate #{state.home_id}: Updated state - provider=#{new_state.provider_id}, contract=#{new_state.contract_id}, expires=#{inspect(new_state.contract_expires_at)}")

    broadcast_state_change(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_metadata, metadata}, state) do
    Logger.info("HomeAggregate #{state.home_id}: Updating metadata - name=#{Map.get(metadata, "name")}, iot_provider=#{Map.get(metadata, "iot_provider")}")

    new_state = %{state |
      name: Map.get(metadata, "name"),
      iot_provider: Map.get(metadata, "iot_provider"),
      street: Map.get(metadata, "street"),
      latitude: Map.get(metadata, "latitude"),
      longitude: Map.get(metadata, "longitude"),
      solar_capacity_kw: Map.get(metadata, "solar_capacity_kw"),
      battery_capacity_kwh: Map.get(metadata, "battery_capacity_kwh"),
      last_event_at: DateTime.utc_now()
    }

    broadcast_state_change(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_status, status}, state) do
    new_state = %{state |
      status: status,
      last_event_at: DateTime.utc_now()
    }

    broadcast_state_change(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Private helpers

  defp load_home_metadata(home_id) do
    # Query database for home metadata via WAMP RPC
    try do
      case CortexIqDashboard.QueryClient.get_home(home_id) do
        {:ok, wamp_result} ->
          # Extract home data from WAMP result
          actual_result = case Map.get(wamp_result, :args) do
            [result | _] -> result
            _ -> %{}
          end
          home_data = Map.get(actual_result, "home", %{})
          {:ok, home_data}

        {:error, reason} ->
          Logger.warning("HomeAggregate: Failed to load metadata for #{home_id}: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      :exit, reason ->
        Logger.warning("HomeAggregate: WAMP pool unavailable for #{home_id}: #{inspect(reason)}")
        {:error, :pool_unavailable}
    end
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqDashboard.HomeRegistry, home_id}}
  end

  defp broadcast_state_change(state) do
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "entity:home",
      {:home_state_changed, state.home_id, state}
    )
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: nil
end
