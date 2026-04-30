# CortexIQ Migration Plan: Bondy/WAMP → Macula HTTP/3

This document outlines the migration strategy for moving the CortexIQ proof-of-concept from Bondy/WAMP to the new Macula HTTP/3 (QUIC) mesh platform.

## Current Architecture (Bondy/WAMP)

```
CortexIQ Apps → Bondy WAMP Router → CortexIQ Apps
  (WebSocket)                        (WebSocket)
```

**Problems:**
- WebSocket doesn't work well through NAT/firewalls
- Centralized router is single point of failure
- Complex setup and configuration
- Not edge-friendly

## Target Architecture (Macula HTTP/3)

```
CortexIQ Apps → Macula Gateway → CortexIQ Apps
  (HTTP/3 QUIC)   (bootstrap)    (HTTP/3 QUIC)
```

**Benefits:**
- HTTP/3 (QUIC) works through NAT/firewalls
- Decentralized mesh network
- Gateway only for bootstrap/discovery
- Edge-native design
- Simpler deployment

## Components to Migrate

### ✅ Already Created
- **macula_client_ex/** - Elixir client wrapper (needs verification)
- **macula_gateway_ex/** - Elixir gateway service (needs verification)
- **macula_gateway_service/** - Gateway deployment service
- **Adapter files** - `macula_client_ex_adapter.ex` in each app

### 🔄 CortexIQ Applications

#### High Priority (Core)
1. **cortex_iq_simulation** - Simulates homes and devices
   - Currently uses: WAMP pub/sub for events
   - Migration: Use `macula_client` pub/sub
   - Topics: `energy.home.measured`, `energy.device.event`

2. **cortex_iq_homes** - Home management service
   - Currently uses: WAMP pub/sub + RPC
   - Migration: Use `macula_client` pub/sub + RPC
   - Topics: `energy.home.*`
   - RPCs: `energy.home.get`, `energy.home.create`

3. **cortex_iq_utilities** - Utility company service
   - Currently uses: WAMP pub/sub + RPC
   - Migration: Use `macula_client` pub/sub + RPC
   - Topics: `energy.utility.*`
   - RPCs: `energy.utility.get_pricing`

#### Medium Priority (Aggregation)
4. **cortex_iq_projections** - Event projections and read models
   - Currently uses: WAMP subscriptions
   - Migration: Use `macula_client` subscriptions
   - Subscribes to: All `energy.*` topics

5. **cortex_iq_queries** - Query service with RPC endpoints
   - Currently uses: WAMP RPC server
   - Migration: Use `macula_client` RPC server
   - Provides: Query procedures

#### Low Priority (Dashboard)
6. **cortex_iq_dashboard_umbrella** - Phoenix LiveView dashboard
   - Currently uses: WAMP client in LiveView
   - Migration: Use `macula_client` in LiveView
   - Subscribes to: Dashboard-specific topics

#### Optional (External Integrations)
7. **cortex_iq_open_weather_map** - Weather data integration
8. **cortex_iq_prezio** - Prezio integration

## Migration Strategy

### Phase 1: Infrastructure (COMPLETE)
✅ Macula Gateway deployed in Kubernetes
✅ Erlang `macula_client` implemented
✅ Examples created (chat, IoT sensors)

### Phase 2: Direct Erlang Integration (CURRENT)
**Decision**: Use Erlang `macula_client` directly from Elixir, no wrapper needed!

Why this approach:
- Elixir and Erlang are both BEAM languages - perfect interop
- No wrapper layer = simpler, less code to maintain
- Direct access to all Erlang functions
- Better performance (no translation layer)

Tasks:
🔄 Add Erlang `macula` as dependency in Elixir apps
🔄 Test calling `:macula_client` from Elixir
🔄 Create Elixir convenience functions if needed

### Phase 3: Simulation Layer
1. Migrate **cortex_iq_simulation**
   - Update to use `macula_client_ex`
   - Test event publishing
   - Verify NAT traversal

2. Migrate **cortex_iq_homes**
   - Update to use `macula_client_ex`
   - Test pub/sub + RPC
   - Verify end-to-end flow

3. Migrate **cortex_iq_utilities**
   - Update to use `macula_client_ex`
   - Test pricing RPC calls

### Phase 4: Aggregation Layer
4. Migrate **cortex_iq_projections**
   - Update all projections to subscribe via `macula_client_ex`
   - Test event aggregation
   - Verify read model updates

5. Migrate **cortex_iq_queries**
   - Convert RPC server to use `macula_client_ex`
   - Test query procedures

### Phase 5: Dashboard
6. Migrate **cortex_iq_dashboard_umbrella**
   - Update LiveView to use `macula_client_ex`
   - Test real-time updates
   - Verify user experience

## Technical Migration Steps

### For Each Component:

#### 1. Update Dependencies
```elixir
# In mix.exs
def deps do
  [
    # Use Erlang macula library directly
    {:macula, git: "https://github.com/macula-io/macula", tag: "0.4.4"},
    # Or for local development:
    # {:macula, path: "../../macula", override: true},

    # Remove: {:macula_sdk, ...}  (old WAMP SDK)
    # Remove: {:macula_client_ex, ...}  (wrapper not needed)
  ]
end
```

#### 2. Update Configuration
```elixir
# In config/runtime.exs
config :my_app,
  macula_url: System.get_env("MACULA_URL", "https://localhost:9443"),
  macula_realm: System.get_env("MACULA_REALM", "com.cortexiq.energy")
```

#### 3. Update Application Startup
```elixir
# In application.ex
defmodule MyApp.Application do
  def start(_type, _args) do
    # Ensure Erlang macula app is started
    Application.ensure_all_started(:macula)

    # Connect to Macula mesh
    url = Application.fetch_env!(:my_app, :macula_url)
    realm = Application.fetch_env!(:my_app, :macula_realm)
    node_id = "my-app-#{:rand.uniform(1000)}"

    {:ok, client} = :macula_client.connect(
      url,
      %{realm: realm, node_id: node_id}
    )

    # Store client pid for app use
    :persistent_term.put(:macula_client, client)

    children = [
      # Other children...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

#### 4. Update Pub/Sub Code
```elixir
# Get client from persistent_term or pass as argument
client = :persistent_term.get(:macula_client)

# Before (WAMP):
MaculaSdk.Wamp.Client.publish(client, "topic", %{data: "value"})
MaculaSdk.Wamp.Client.subscribe(client, "topic", handler)

# After (Macula - Direct Erlang calls):
:macula_client.publish(client, "topic", %{data: "value"})
:macula_client.subscribe(client, "topic", handler)

# Optional: Create Elixir wrapper module for convenience
defmodule MyApp.Macula do
  def publish(topic, data) when is_binary(topic) do
    client = :persistent_term.get(:macula_client)
    :macula_client.publish(client, topic, data)
  end

  def subscribe(topic, callback) when is_binary(topic) do
    client = :persistent_term.get(:macula_client)
    :macula_client.subscribe(client, topic, callback)
  end
end
```

#### 5. Update RPC Code

⚠️ **IMPORTANT: RPC Registration Not Supported in HTTP/3 Client SDK**

The `macula_client` SDK does NOT support service registration. This is by design - Macula's decentralized architecture doesn't use centralized RPC registration like WAMP.

**What Works:**
- ✅ `call/3` - Call RPC procedures on other services (works)

**What Doesn't Work:**
- ❌ `register/3` - NO FUNCTION EXISTS in macula_client
- ❌ Client applications cannot expose RPC endpoints via the SDK

**Why?**
A "Client" implementing "Register/Unregister" doesn't align with Macula's decentralization goals. See `DECENTRALIZED_RPC_RESEARCH.md` for detailed analysis of alternative approaches.

**Recommended Solution:**
Use **DHT-based service advertisement** (see research document):
- Services advertise capabilities to the distributed hash table (DHT)
- Clients discover services via DHT lookup
- Fully decentralized, supports multiple providers, fault tolerant

```elixir
# Get client from persistent_term or pass as argument
client = :persistent_term.get(:macula_client)

# Calling RPC works as expected:
{:ok, result} = :macula_client.call(client, "procedure", args)

# Registering RPC procedures requires DHT-based service advertisement:
# (To be implemented - see DECENTRALIZED_RPC_RESEARCH.md)
{:ok, _ref} = :macula_client.advertise(client, "procedure", handler, %{ttl: 300})
```

**Migration Impact:**
CortexIQ applications that use RPC registration (e.g., `cortex_iq_queries`) will need to:
1. Wait for DHT-based service advertisement implementation in Macula
2. OR convert RPC to pub/sub patterns (less ideal)
3. OR use internal mesh node RPC (requires running as mesh node, not client)

See **DECENTRALIZED_RPC_RESEARCH.md** for complete analysis and proposed solutions.

## Realm Structure

Keep existing realm structure:
- **com.cortexiq.energy** - Main energy trading realm
- Topics remain the same
- RPCs remain the same
- No protocol changes needed!

## Testing Strategy

### Unit Tests
- Test individual component migrations
- Mock `macula_client_ex` in tests
- Verify pub/sub and RPC calls

### Integration Tests
- Test component-to-component communication
- Verify end-to-end event flow
- Test NAT traversal scenarios

### System Tests
- Deploy all components to Kubernetes
- Simulate real-world scenarios
- Monitor performance and reliability

## Deployment Strategy

### Development
- Local development with `kind` cluster
- Port-forward gateway to localhost:9443
- Run components locally or in Docker

### Staging
- Deploy to beam cluster
- Test with real network conditions
- Verify firewall traversal

### Production
- Rolling deployment per component
- Blue/green strategy
- Rollback plan ready

## Success Criteria

✅ All CortexIQ components communicate via Macula HTTP/3
✅ No WAMP/Bondy dependencies remaining
✅ System works behind NAT/firewalls
✅ Performance meets or exceeds WAMP baseline
✅ Dashboard shows real-time updates
✅ All tests pass

## Rollback Plan

If migration fails:
1. Revert to tagged Docker images (pre-migration)
2. Redeploy Bondy router
3. Restore WAMP SDK dependencies
4. Roll back GitOps manifests

## Timeline Estimate

- **Phase 2** (SDK Enhancement): 2 days
- **Phase 3** (Simulation Layer): 3 days
- **Phase 4** (Aggregation Layer): 2 days
- **Phase 5** (Dashboard): 2 days
- **Testing & Refinement**: 3 days

**Total**: ~2 weeks for complete migration

## Next Steps

1. ✅ Create migration plan document
2. 🔄 Verify `macula_client_ex` implementation
3. 🔄 Start with cortex_iq_simulation migration
4. Test end-to-end flow
5. Proceed with remaining components

---

**Created**: 2025-11-10
**Status**: Phase 2 - SDK Enhancement
**Owner**: Migration Team
