defmodule CortexIqDashboard.Aggregates.ProviderAggregate do
  @moduledoc """
  One GenServer per provider - maintains provider state in-memory.

  Subscribes to events for this specific provider and updates its internal state.
  Broadcasts state changes to view aggregators via PubSub.
  """
  use GenServer
  require Logger

  defstruct [
    :provider_id,
    :provider_name,
    :strategy,
    day_buy_price: 0.0,
    night_buy_price: 0.0,
    day_sell_price: 0.0,
    night_sell_price: 0.0,
    switching_discount: 0.0,
    active_contracts: 0,
    market_share_percent: 0.0,
    last_event_at: nil
  ]

  # Client API

  def start_link(provider_id) do
    GenServer.start_link(__MODULE__, provider_id, name: via_tuple(provider_id))
  end

  def update_contract_offer(provider_id, offer_data) do
    GenServer.cast(via_tuple(provider_id), {:update_contract_offer, offer_data})
  end

  def get_state(provider_id) do
    GenServer.call(via_tuple(provider_id), :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(provider_id) do
    state = %__MODULE__{
      provider_id: provider_id
    }

    Logger.info("ProviderAggregate: Initialized for #{provider_id}")

    # Broadcast initial state
    broadcast_state_change(state)

    {:ok, state}
  end

  @impl true
  def handle_cast({:update_contract_offer, offer_data}, state) do
    new_state = %{state |
      provider_name: Map.get(offer_data, "provider_name", state.provider_name),
      strategy: Map.get(offer_data, "strategy", state.strategy),
      day_buy_price: Map.get(offer_data, "day_buy_price", state.day_buy_price),
      night_buy_price: Map.get(offer_data, "night_buy_price", state.night_buy_price),
      day_sell_price: Map.get(offer_data, "day_sell_price", state.day_sell_price),
      night_sell_price: Map.get(offer_data, "night_sell_price", state.night_sell_price),
      switching_discount: Map.get(offer_data, "switching_discount", state.switching_discount),
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

  defp via_tuple(provider_id) do
    {:via, Registry, {CortexIqDashboard.ProviderRegistry, provider_id}}
  end

  defp broadcast_state_change(state) do
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "entity:provider",
      {:provider_state_changed, state.provider_id, state}
    )
  end
end
