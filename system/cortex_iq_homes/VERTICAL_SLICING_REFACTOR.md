# HomeBot Vertical Slicing Refactoring

## Architecture Overview

### BEFORE (Monolithic WAMP in HomeBot)
```
HomeBot
├── One WAMP client
├── Subscribes to 5 topics directly
├── Publishes to 13 topics directly
└── All WAMP operations in one process
```

**Problem**: Tight coupling, single point of failure, no fault isolation

### AFTER (Vertical Slicing)
```
HomeSupervisor (per home)
├── HomeBot (coordinator - NO WAMP client)
├── SimulationTimeSystem → WampClient + SimulationTimeSubscriber
├── ContractOfferSystem → WampClient + ContractOfferSubscriber
├── SpotPriceSystem → WampClient + SpotPriceSubscriber
├── ContractLifecycleSystem → WampClient + ContractLifecycleSubscriber
├── MeasurementPublisherSystem → WampClient + MeasurementPublisher
├── HomeLifecyclePublisherSystem → WampClient + HomeLifecyclePublisher
├── ContractPublisherSystem → WampClient + ContractPublisher
└── TradingPublisherSystem → WampClient + TradingPublisher
```

**Benefits**:
- Each slice has dedicated WAMP client (8 clients per home)
- Proper OTP supervision (if one client crashes, only that slice restarts)
- Fault isolation (measurement publisher crash doesn't affect contract subscriber)
- Clear separation of concerns
- Cohesion (all code for a feature together)
- Scalability (easy to add new event types)

## HomeBot State Changes

### REMOVE from state:
```elixir
:wamp_client,  # No longer needed - each system has its own
```

### KEEP in state:
- All business logic fields (home, battery, contracts, etc.)
- All simulation state
- All tracking fields

## HomeBot Refactoring Required

### 1. Remove WAMP Client Initialization
**BEFORE**:
```elixir
def init(opts) do
  # ...
  {:ok, wamp_client} = MaculaSdk.Wamp.Client.start_link(...)
  state = %__MODULE__{
    wamp_client: wamp_client,
    # ...
  }
end
```

**AFTER**:
```elixir
def init(opts) do
  # ...
  # No WAMP client - systems handle this
  state = %__MODULE__{
    # wamp_client removed
    # ...
  }

  # Don't send :subscribe message
  # Subscribers handle their own subscriptions
end
```

### 2. Replace Subscription Logic

**REMOVE** these functions:
- `subscribe_to_simulation_time/1`
- `subscribe_to_simulation_reset/1`
- `subscribe_to_all_contract_offers/1`
- `subscribe_to_market_spot_price/1`
- `subscribe_to_contract_responses/1`

**REMOVE** this handle_info:
```elixir
def handle_info(:subscribe, state) do
  # ... all subscription code
end
```

**ADD** message handlers for subscriber notifications:

```elixir
# From SimulationTimeSubscriber
def handle_info({:simulation_time_tick, simulation_time}, state) do
  # Existing simulation loop logic
end

# From ContractOfferSubscriber
def handle_info({:contract_offer, offer}, state) do
  provider_offers = Map.put(state.provider_offers, offer.provider_id, offer)
  {:noreply, %{state | provider_offers: provider_offers}}
end

# From SpotPriceSubscriber
def handle_info({:spot_price_update, price}, state) do
  new_history = [price | state.spot_price_history] |> Enum.take(24)
  {:noreply, %{state | current_spot_price: price, spot_price_history: new_history}}
end

# From ContractLifecycleSubscriber
def handle_info({:contract_confirmed, kwargs}, state) do
  # Existing contract confirmation logic
end

def handle_info({:contract_rejected, kwargs}, state) do
  # Existing rejection logic
end
```

**REMOVE** these pattern-matched WAMP handlers (from refactored code):
```elixir
# These are now handled by subscribers
def handle_info({:wamp_event, "be.cortexiq.market.contract_proposed", ...}, state)
def handle_info({:wamp_event, "be.cortexiq.market.spot_price_updated", ...}, state)
def handle_info({:wamp_event, "be.cortexiq.market.contract_confirmed", ...}, state)
def handle_info({:wamp_event, "be.cortexiq.market.contract_rejected", ...}, state)
```

### 3. Replace Publication Logic

**REPLACE** all `publish_*` functions that call `Client.publish`:

**BEFORE**:
```elixir
defp publish_measurement(state, prod_w, cons_w, soc, power_w, sim_time) do
  data = %{...}
  Client.publish(state.wamp_client, topic, [], data, %{})
end
```

**AFTER**:
```elixir
defp publish_measurement(state, prod_w, cons_w, soc, power_w, sim_time) do
  data = %{...}
  CortexIqHomes.Publishers.MeasurementPublisher.publish(state.home_id, data)
end
```

**Publications to refactor** (13 total):
1. `publish_measurement` → MeasurementPublisher
2. `publish_home_initialized` → HomeLifecyclePublisher.publish(home_id, :initialized, data)
3. `publish_home_connected` → HomeLifecyclePublisher.publish(home_id, :connected, data)
4. `publish_home_disconnected` → HomeLifecyclePublisher.publish(home_id, :disconnected, data)
5. `publish_initial_contract` → ContractPublisher.publish(home_id, :signed, data)
6. `publish_contract_switched` → ContractPublisher.publish(home_id, :switched, data)
7. `publish_contract_expired` → ContractPublisher.publish(home_id, :expired, data)
8. `publish_trades` → TradingPublisher.publish(home_id, :trade, data)
9. `publish_arbitrage_profit` → TradingPublisher.publish(home_id, :arbitrage, data)
10. `publish_balance` → TradingPublisher.publish(home_id, :balance, data)

## Application Supervision Tree Changes

**BEFORE**:
```elixir
children = [
  {CortexIqHomes.HomeBotSupervisor, [homes: homes, realm: realm, bondy_url: bondy_url]}
]
```

**AFTER**:
```elixir
children = [
  {Registry, keys: :unique, name: CortexIqHomes.Registry},
  {CortexIqHomes.HomeBotSupervisor, [homes: homes, realm: realm, bondy_url: bondy_url]}
]
```

**HomeBotSupervisor Changes**:
```elixir
# BEFORE: Start HomeBots directly
{CortexIqHomes.HomeBot, [home_id: home_id, home: home, ...]}

# AFTER: Start HomeSupervisors
{CortexIqHomes.HomeSupervisor, [home_id: home_id, home: home, ...]}
```

## Testing Plan

1. **Compilation**: Verify all modules compile
2. **Supervision Tree**: Check all processes start correctly
3. **Subscriptions**: Verify homes receive WAMP events via subscribers
4. **Publications**: Verify measurements appear in dashboard
5. **Fault Tolerance**: Kill a WAMP client, verify system recovers
6. **Performance**: Ensure no degradation with 50+ homes

## Migration Steps

1. ✅ Create generic SubscriberSystem and PublisherSystem modules
2. ✅ Create specific subscriber modules (4 types)
3. ✅ Create specific publisher modules (4 types)
4. ✅ Create HomeSupervisor
5. ✅ Add `whereis/1` to HomeBot
6. 🔄 Refactor HomeBot init (remove WAMP client)
7. 🔄 Replace subscription logic with message handlers
8. 🔄 Replace publication calls with publisher API calls
9. 🔄 Update Application.ex to add Registry and use HomeSupervisor
10. 🔄 Build, deploy, and verify

## Expected Result

- **50 homes** × **8 systems/home** = **400 lightweight processes**
- Each process supervised independently
- Clear separation of concerns
- Easy to add new event types
- Proper OTP fault tolerance
