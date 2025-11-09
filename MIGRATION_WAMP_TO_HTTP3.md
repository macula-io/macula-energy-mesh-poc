# Migration Plan: WAMP → HTTP/3 (QUIC)

**Date:** 2025-11-09
**Scope:** Migrate CortexIQ Energy PoC from WAMP/Bondy to Macula HTTP/3

---

## Overview

We're migrating the energy mesh PoC from WAMP (WebSocket-based) to HTTP/3 (QUIC-based) transport using the new Erlang `macula_sdk`.

### What Changes
- **Transport Layer**: WAMP over WebSocket → HTTP/3 over QUIC
- **SDK**: `MaculaSdk.Wamp.Client` → `MaculaSdk.Client` (new Elixir wrapper)
- **URL Scheme**: `ws://` → `https://`
- **Router**: Bondy → Macula Gateway (HTTP/3 server)

### What Stays the Same
- **Application Code**: 99% unchanged (same API)
- **Topics**: Same topic naming conventions
- **Event Payloads**: Same data structures
- **Architecture**: Still pub/sub + RPC mesh

---

## Migration Strategy

### Phase 1: SDK Wrapper (✅ Complete)

**Goal**: Create Elixir wrapper that maintains API compatibility

**Actions**:
1. ✅ Created `MaculaSdk.Client` - Drop-in replacement for `MaculaSdk.Wamp.Client`
2. ✅ Created `MaculaSdk` module - Top-level API
3. ✅ Maintained same function signatures:
   - `publish(client, topic, args, kwargs, options)`
   - `subscribe(client, topic, handler_fun, options)`
   - `call(client, procedure, args, kwargs, options)`

**Result**: Applications can switch with minimal code changes

---

### Phase 2: Infrastructure Setup (In Progress)

**Goal**: Deploy HTTP/3 gateway to replace Bondy

**Actions**:
1. [ ] Build Macula Gateway HTTP/3 server
2. [ ] Deploy to Kubernetes (hub cluster)
3. [ ] Configure TLS certificates
4. [ ] Expose service on port 9443
5. [ ] Test connectivity

**Files to Modify**:
- `/infrastructure/k8s/hub/macula-gateway.yaml` (new)
- `/infrastructure/k8s/hub/kustomization.yaml`

---

### Phase 3: Application Migration (Pending)

**Goal**: Update all PoC applications to use new SDK

#### Applications to Migrate

**Dashboard** (`cortex_iq_dashboard`):
- **Files**:
  - `lib/cortex_iq_dashboard/event_subscribers/*_subscriber.ex` (10+ files)
  - `lib/cortex_iq_dashboard/application.ex`
- **Changes**:
  ```elixir
  # Before (WAMP)
  {:ok, wamp_client} = MaculaSdk.Wamp.Client.start_link(
    url: "ws://bondy:18082/ws",
    realm: "be.cortexiq.energy"
  )

  # After (HTTP/3)
  {:ok, client} = MaculaSdk.Client.start_link(
    url: "https://macula-gateway:9443",
    realm: "be.cortexiq.energy"
  )
  ```

**Homes** (`cortex_iq_homes`):
- **Files**:
  - Subscription modules
  - Publisher modules
- **Changes**: Same URL/realm update

**Utilities** (`cortex_iq_utilities`):
- **Files**:
  - Provider bots
- **Changes**: Same URL/realm update

**Simulation** (`cortex_iq_simulation`):
- **Files**:
  - Simulation clock
- **Changes**: Same URL/realm update

**Projections** (`cortex_iq_projections`):
- **Files**:
  - Event handlers
- **Changes**: Same URL/realm update

**Queries** (`cortex_iq_queries`):
- **Files**:
  - RPC handlers
- **Changes**: Same URL/realm update

---

### Phase 4: Configuration Update (Pending)

**Goal**: Update environment variables and configs

**Actions**:
1. [ ] Update `config/runtime.exs`
2. [ ] Update Kubernetes ConfigMaps
3. [ ] Update `.env` files
4. [ ] Update Docker Compose (if used)

**Environment Variables**:
```bash
# Before
WAMP_URL=ws://bondy:18082/ws
WAMP_REALM=be.cortexiq.energy

# After
MACULA_URL=https://macula-gateway:9443
MACULA_REALM=be.cortexiq.energy
```

---

### Phase 5: Testing (Pending)

**Goal**: Verify all functionality works with HTTP/3

**Test Plan**:

1. **Connection Test**
   - [ ] All apps connect successfully
   - [ ] TLS handshake succeeds
   - [ ] Realm authentication works

2. **Pub/Sub Test**
   - [ ] Dashboard receives all events
   - [ ] Homes publish measurements
   - [ ] Utilities publish offers
   - [ ] Event delivery is reliable

3. **RPC Test**
   - [ ] Query service responds to calls
   - [ ] Timeout handling works
   - [ ] Error responses propagate correctly

4. **Performance Test**
   - [ ] Latency comparable to WAMP
   - [ ] No message loss
   - [ ] Handles 50 homes + 5 utilities

5. **Resilience Test**
   - [ ] Gateway restart doesn't crash apps
   - [ ] Reconnection works
   - [ ] Message queuing during disconnect

---

## Code Changes Summary

### Minimal Changes Required

**Before** (WAMP):
```elixir
defmodule MySubscriber do
  use GenServer

  def init(opts) do
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    case MaculaSdk.Wamp.Client.subscribe(wamp_client, @topic, handler) do
      :ok -> Logger.info("Subscribed")
      {:error, reason} -> Logger.error("Failed: #{inspect(reason)}")
    end

    {:ok, %{wamp_client: wamp_client}}
  end
end
```

**After** (HTTP/3):
```elixir
defmodule MySubscriber do
  use GenServer

  def init(opts) do
    client = Keyword.fetch!(opts, :client)  # Changed name (optional)

    case MaculaSdk.Client.subscribe(client, @topic, handler) do
      :ok -> Logger.info("Subscribed")
      {:error, reason} -> Logger.error("Failed: #{inspect(reason)}")
    end

    {:ok, %{client: client}}
  end
end
```

**Only 2 changes**:
1. `MaculaSdk.Wamp.Client` → `MaculaSdk.Client`
2. URL in config: `ws://` → `https://`

---

## Deployment Strategy

### Option A: Big Bang (Recommended for PoC)

**Approach**: Migrate everything at once

**Steps**:
1. Deploy Macula Gateway
2. Update all application code
3. Build new Docker images
4. Deploy to Kubernetes
5. Verify

**Pros**:
- Clean cut
- No hybrid state
- Faster overall

**Cons**:
- Higher risk
- All-or-nothing

**Timeline**: 1-2 days

---

### Option B: Gradual Migration

**Approach**: Run WAMP and HTTP/3 in parallel

**Steps**:
1. Deploy Macula Gateway alongside Bondy
2. Migrate apps one-by-one
3. Verify each app
4. Decomm Bondy when done

**Pros**:
- Lower risk
- Can rollback per-app
- Test incrementally

**Cons**:
- More complex
- Hybrid state confusing
- Longer timeline

**Timeline**: 3-5 days

---

## Rollback Plan

If migration fails:

1. **Keep Legacy SDK**: `macula_sdk_wamp_legacy` still exists
2. **Git Revert**: All changes in version control
3. **Kubernetes**: Easy to redeploy old images
4. **Config**: Switch env vars back to Bondy

**Recovery Time**: < 30 minutes

---

## Dependencies

### Erlang SDK
- Location: `/home/rl/work/github.com/macula-io/macula/apps/macula_sdk`
- Status: ✅ Complete (39 tests passing)
- Integration: Needs to be compiled and available to Elixir apps

### Macula Gateway
- Location: `/home/rl/work/github.com/macula-io/macula/apps/macula_gateway`
- Status: ⚠️ Empty module - needs implementation
- Required: HTTP/3 server accepting SDK connections

---

## Next Steps

1. **Immediate** (Today):
   - [ ] Implement Macula Gateway HTTP/3 server
   - [ ] Test Erlang SDK end-to-end
   - [ ] Deploy gateway to hub cluster

2. **Short Term** (Tomorrow):
   - [ ] Migrate one app (e.g., simulation) as proof
   - [ ] Verify pub/sub works
   - [ ] Document any issues

3. **Medium Term** (This Week):
   - [ ] Migrate all remaining apps
   - [ ] Full system testing
   - [ ] Performance tuning
   - [ ] Update documentation

---

## Success Criteria

Migration is complete when:

1. ✅ All 6 applications connect via HTTP/3
2. ✅ Dashboard displays real-time events
3. ✅ Homes publish measurements
4. ✅ Utilities publish offers
5. ✅ RPC queries work
6. ✅ No WAMP/Bondy dependencies remain
7. ✅ Performance matches or exceeds WAMP
8. ✅ System runs stable for 1 hour

---

## Questions & Decisions

### Q: Do we need the Erlang SDK compiled into Elixir releases?

**A**: Yes. Two options:
1. **Path Dependency**: Add macula umbrella as path dep in mix.exs
2. **Precompiled**: Copy compiled .beam files to priv/

**Decision**: Use path dependency for now, easier development.

### Q: How to handle TLS certificates?

**A**: Use self-signed certs for PoC, same as before.

### Q: What about connection pooling?

**A**: Phase 4-7 features in SDK. Not required for initial migration.

### Q: Can we test without gateway?

**A**: Yes! SDK integration tests use a mock server. But need gateway for full PoC.

---

## Appendix: File Locations

### New Files Created
- `system/macula_sdk/lib/macula_sdk.ex`
- `system/macula_sdk/lib/macula_sdk/client.ex`
- `system/macula_sdk/mix.exs`
- `MIGRATION_WAMP_TO_HTTP3.md` (this file)

### Files to Modify
- All `*_subscriber.ex` files in cortex_iq_dashboard
- All `*_publisher.ex` files in cortex_iq_* apps
- Application supervision trees
- Config files (`config/runtime.exs`)
- Environment variables (`.env`, ConfigMaps)
- Kubernetes deployments

### Files to Keep (Legacy)
- `system/macula_sdk_wamp_legacy/*` - Archived for reference

---

## Timeline Estimate

**Optimistic** (Big Bang, No Issues): 1 day
- 4 hours: Gateway implementation
- 2 hours: Application updates
- 2 hours: Testing

**Realistic** (Big Bang, Some Issues): 2 days
- 6 hours: Gateway + debugging
- 4 hours: Application updates
- 4 hours: Testing + fixes

**Pessimistic** (Gradual, Many Issues): 5 days
- 8 hours: Gateway
- 16 hours: App-by-app migration
- 8 hours: Testing + fixes

**Recommended**: Plan for 2 days, execute Big Bang strategy.
