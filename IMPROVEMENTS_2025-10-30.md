# System Improvements - 2025-10-30

## Overview
Comprehensive improvements to WAMP event delivery, subscription patterns, and configuration management.

## A. Enhanced Logging in MaculaSdk

### Files Modified:
- `system/macula_sdk/lib/macula_sdk/wamp/connection.ex`
- `system/macula_sdk/lib/macula_sdk/wamp/client.ex`

### Improvements:
1. **Connection-level logging**:
   - Log WAMP message types (WELCOME, EVENT, SUBSCRIBED, etc.)
   - Track subscription_id mappings
   - Debug event routing

2. **Client-level logging**:
   - Log when events are received
   - Show which handler is invoked
   - Track handler execution and errors
   - Display active subscription_ids

### Benefits:
- Easy diagnosis of event delivery issues
- Clear audit trail of WAMP communication
- Immediate visibility into subscription problems

## B. Refactored Subscription Pattern

### Files Modified:
- `system/cortex_iq_projections/lib/cortex_iq_projections/event_projector.ex`

### Changes:
**Before (Wildcard Subscriptions)**:
```elixir
# Problem: Less clear intent, harder to debug
Client.subscribe(client, "be.cortexiq.home.", handler, %{match: "prefix"})
Client.subscribe(client, "be.cortexiq.market.", handler, %{match: "prefix"})
```

**After (Individual Topic Subscriptions)**:
```elixir
# Clearer intent, easier debugging, better traceability
topics = [
  {"be.cortexiq.home.initialized", &handle_home_event/2},
  {"be.cortexiq.home.connected", &handle_home_event/2},
  {"be.cortexiq.home.measured", &handle_home_event/2},
  {"be.cortexiq.market.contract_confirmed", &handle_market_event/2},
  # ... 17 specific topics total
]
```

### Benefits:
1. ✅ **Explicit intent** - Clear what events we care about
2. ✅ **Easier debugging** - Can trace each subscription separately
3. ✅ **Better logging** - Each topic logs independently
4. ✅ **Follows WAMP best practices** - Matches bondy-demo-marketplace pattern
5. ✅ **Selective sampling** - Apply different sampling rates per topic

### Sampling Strategy:
- `home.measured`: 10% (high frequency measurements)
- `home.traded`: 20% (moderate frequency trades)
- All lifecycle events: 100% (critical for state)
- All market events: 100% (critical for business logic)

## C. Centralized Bondy Configuration

### Files Created:
- `infrastructure/gitops/kind/base/bondy-client-config/configmap.yaml`
- `infrastructure/gitops/kind/base/bondy-client-config/kustomization.yaml`

### Files Modified:
- `infrastructure/gitops/kind/base/cortex-iq-homes/deployment.yaml`
- `infrastructure/gitops/kind/base/cortex-iq-homes/kustomization.yaml`

### Configuration:
```yaml
# Centralized in ConfigMap
BONDY_URL: "ws://172.20.0.5:30080/ws"
BONDY_REALM: "be.cortexiq.energy"
```

**Why This IP?**
- `172.20.0.5` = Hub cluster control plane (Docker bridge network)
- `30080` = NodePort for Bondy service (maps to 18080)
- All KinD clusters share same Docker network
- Direct, reliable connection for cross-cluster communication

### Benefits:
1. ✅ **Single source of truth** - Change once, applies everywhere
2. ✅ **Documented** - Clear explanation of why this IP/port
3. ✅ **Easy to update** - Change ConfigMap, restart pods
4. ✅ **Production-ready pattern** - Easy to swap for external LB/DNS

## Architecture Insights from bondy-demo-marketplace

### Key Finding: Centralized Bondy Architecture
The demo marketplace uses:
- **ONE Bondy instance** (not distributed!)
- All clients connect to same Bondy
- No edge routers or mesh topology
- This is the standard WAMP pattern

### Implications for Our System:
**Current Correct Setup**:
```
✓ All services → Hub Bondy (172.20.0.5:30080)
✓ Single message bus
✓ Events routed correctly
```

**Previous Problem**:
```
✗ Homes → Edge Bondy (hypothetical)
✗ Projections → Hub Bondy
Result: Events never crossed router boundaries!
```

## Next Steps

### 1. Deploy Updated Images
```bash
# Build completed - now deploy
kubectl --context kind-macula-hub rollout restart deployment cortex-iq-projections -n macula-apps
kubectl --context kind-macula-edge-03 rollout restart deployment cortex-iq-homes -n macula-apps
kubectl --context kind-macula-edge-04 rollout restart deployment cortex-iq-homes -n macula-apps
```

### 2. Verify Event Delivery
```bash
# Watch projections logs for EVENT reception
kubectl --context kind-macula-hub logs -n macula-apps -l app=cortex-iq-projections -f | grep "EVENT\|Received"

# Should see:
# [info] Received EVENT on topic: be.cortexiq.home.measured
# [info] EventProjector: Received home event: be.cortexiq.home.measured
```

### 3. Verify Database Population
```bash
# Check if homes are being registered
kubectl --context kind-macula-hub exec -n macula-apps deployment/cortex-iq-queries -- \
  /app/bin/cortex_iq_queries rpc "CortexIqQueries.Repo.aggregate(CortexIqDashboardSchemas.Projections.HomeState, :count)"

# Should return count > 0
```

### 4. Test RPC Queries
```bash
# Test get_homes RPC
kubectl --context kind-macula-hub exec -n macula-apps deployment/cortex-iq-dashboard -- \
  /app/bin/cortex_iq_dashboard rpc 'client = elem(GenServer.whereis(CortexIqDashboard.WampSubscriber), 1); MaculaSdk.Wamp.Client.call(client.wamp_client, "be.cortexiq.energy.queries.get_homes", [], %{page: 1, page_size: 10})'
```

## Summary of Benefits

### Operational:
- 🔍 **Comprehensive logging** - Easy troubleshooting
- 📊 **Clear metrics** - Know what's working/failing
- 🎯 **Explicit configuration** - No magic IPs scattered around

### Architectural:
- ✅ **Standard WAMP patterns** - Follows best practices
- ✅ **Centralized message bus** - Simpler, more reliable
- ✅ **Individual subscriptions** - Clearer intent, easier debugging

### Maintainability:
- 🛠️ **Easier to debug** - Logs tell the whole story
- 📝 **Self-documenting** - Code explains itself
- 🔄 **Easy to change** - ConfigMap-driven configuration
     STDIN
   1 
   2 ## Deployment Results ✅
   3 
   4 ### Images Built and Deployed Successfully (2025-10-30 00:25)
   5 ```
   6 ✓ macula/macula-os:latest
   7 ✓ macula/cortex-iq-simulation:latest
   8 ✓ macula/cortex-iq-projections:latest
   9 ✓ macula/cortex-iq-dashboard:latest
  10 ✓ macula/cortex-iq-homes:latest
  11 ✓ macula/cortex-iq-utilities:latest
  12 ```
  13 
  14 ### Event Delivery Verified ✅
  15 **Logs confirm events flowing correctly:**
  16 ```
  17 [info] Received EVENT on topic: be.cortexiq.home.measured, subscription_id: 1461181216544869
  18 [info] Client received EVENT: topic=be.cortexiq.home.measured, subscription_id=1461181216544869
  19 [info] EventProjector: Received home event: be.cortexiq.home.measured
  20 
  21 [info] Received EVENT on topic: be.cortexiq.market.trade_executed, subscription_id: 3986298522644966
  22 [info] Client received EVENT: topic=be.cortexiq.market.trade_executed, subscription_id=3986298522644966
  23 [info] EventProjector: Received market event: be.cortexiq.market.trade_executed
  24 ```
  25 
  26 **Key Findings:**
  27 - ✅ WAMP messages arrive as **lists** (not tuples) - format: `[36, subscription_id, publication_id, details, args, kwargs]`
  28 - ✅ Individual topic subscriptions working perfectly
  29 - ✅ Two distinct subscription_ids mapped correctly:
  30   - `1461181216544869` → home events
  31   - `3986298522644966` → market events
  32 - ✅ Events include full payload data (home_id, energy metrics, contract details)
  33 
  34 ### Critical Bug Fixes Applied
  35 
  36 #### Bug #1: ArgumentError in String Interpolation
  37 **Location**: `system/macula_sdk/lib/macula_sdk/wamp/connection.ex:194`
  38 
  39 **Problem**:
  40 ```elixir
  41 Logger.debug("Received WAMP message: #{msg}")  # ❌ Crashes if msg is binary
  42 ```
  43 
  44 **Fix**:
  45 ```elixir
  46 Logger.debug("Received WAMP message (#{byte_size(msg)} bytes)")  # ✅ Safe
  47 ```
  48 
  49 #### Bug #2: Unsafe elem() Call
  50 **Location**: `system/macula_sdk/lib/macula_sdk/wamp/connection.ex:198`
  51 
  52 **Problem**:
  53 ```elixir
  54 Logger.info("Decoded WAMP message type: #{elem(message, 0)}")  # ❌ Assumes tuple
  55 ```
  56 
  57 **Fix**:
  58 ```elixir
  59 message_type = case message do
  60   tuple when is_tuple(tuple) and tuple_size(tuple) > 0 -> elem(tuple, 0)
  61   other -> "non-tuple: #{inspect(other)}"  # ✅ Handles lists
  62 end
  63 Logger.info("Decoded WAMP message type: #{message_type}")
  64 ```
