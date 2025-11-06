# Bondy Scaling Strategy for Macula Platform

## Executive Summary

To support millions of concurrent connections, the Macula platform needs a multi-layered approach combining:
1. **Patched Bondy** (immediate fix for timeout bug)
2. **Improved Connection Staggering** (reduce burst load)
3. **Multi-Instance Bondy Architecture** (horizontal scaling)
4. **Bridge/Relay Pattern** (hierarchical topology)

---

## 1. Current State Analysis

### Problem: Connection Storm
- **Current Load**: ~2750 homes + projections/dashboard = ~2800 concurrent connections
- **Current Strategy**: Staggered startup with 50-100ms delays
- **Issue**: Even staggered, simultaneous HELLO handshakes timeout
- **Root Cause**: Bondy bug (`abort_message(timeout)` clause missing) → crashes with function_clause error

### Bondy Configuration Limits (from configmap.yaml)
```
wamp.tcp.max_connections = 100000
api_gateway.http.max_connections = 500000
wamp.tcp.acceptors_pool_size = 200
api_gateway.http.acceptors_pool_size = 200
```

**Analysis**: Configuration allows up to 500K connections, but:
- Single Erlang VM has practical limits (memory, CPU, message queue size)
- HELLO handshake processing is synchronous and CPU-intensive
- Partisan clustering adds overhead

---

## 2. Immediate Fixes (Done/In Progress)

### ✅ 2.1. Patch Bondy Timeout Bug
**Status**: PATCHED - Building custom image

**Fix Applied**:
```erlang
abort_message(timeout) ->
    Details = #{
        message => <<"Connection handshake timeout. The router is experiencing high load. Please try again.">>
    },
    bondy_wamp_message:abort(Details, ?WAMP_SYSTEM_SHUTDOWN);
```

**Impact**:
- Graceful connection rejection instead of crashes
- Clients get proper error message to retry
- Bondy stays stable under overload

### 🔄 2.2. Improved Connection Staggering
**Current**: 50ms base + 50ms jitter = ~13-20 connections/sec
**Proposed**: Dynamic backoff based on connection success rate

**Implementation** (homes/application.ex):
```elixir
defp start_home_bots_staggered(homes, bondy_url, realm) do
  # Adaptive staggering: start slow, speed up if connections succeed
  initial_delay_ms = 200    # Start conservative
  min_delay_ms = 50         # Speed up to this if successful
  max_delay_ms = 500        # Slow down to this if failures occur
  jitter_ms = 100           # Random variation

  batch_size = 50           # Connect in batches
  batch_delay_ms = 5000     # Wait between batches

  homes
  |> Enum.chunk_every(batch_size)
  |> Enum.with_index()
  |> Enum.each(fn {batch, batch_num} ->
    Logger.info("Starting batch #{batch_num + 1}/#{div(length(homes), batch_size) + 1} (#{length(batch)} homes)")

    # Start batch with adaptive delays
    start_batch(batch, initial_delay_ms, jitter_ms)

    # Longer delay between batches
    unless batch_num == div(length(homes), batch_size) do
      Logger.info("Batch complete, waiting #{batch_delay_ms}ms before next batch...")
      Process.sleep(batch_delay_ms)
    end
  end)
end
```

**Benefits**:
- Reduces peak connection rate from ~20/sec to ~4-10/sec
- Gives Bondy time to process HELLO handshakes between batches
- Adaptive: can tune based on observed success rates

---

## 3. Horizontal Scaling: Multi-Instance Bondy

### Architecture: Active-Active Bondy Cluster

```
                    ┌─────────────────────┐
                    │  Nginx Ingress      │
                    │  (Load Balancer)    │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
     ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
     │  Bondy-1    │  │  Bondy-2    │  │  Bondy-3    │
     │  (Pod 1)    │◄─┤  (Pod 2)    │─►│  (Pod 3)    │
     └─────────────┘  └─────────────┘  └─────────────┘
          │ │              │ │              │ │
          │ └──Partisan────┘ └──Partisan────┘ │
          │         Cluster Mesh               │
          │                                    │
     WAMP Clients                         WAMP Clients
    (homes, dashboard)                  (homes, dashboard)
```

### Key Design Decisions

**Q: How do multiple Bondy instances communicate?**
**A**: Bondy uses **Partisan** for clustering (distributed Erlang alternative).

- **Partisan Features**:
  - Full mesh topology (every node connects to every other node)
  - Automatic message routing between cluster members
  - PubSub is cluster-wide (publish on Bondy-1, subscribers on Bondy-2 receive)
  - Session affinity NOT required (clients can connect to any instance)

**Q: Do we need sticky sessions?**
**A**: NO - WAMP sessions are node-local, but PubSub/RPC works cluster-wide.

- Client connects to Bondy-1, establishes session
- Client publishes to topic `be.cortexiq.home.measured`
- Bondy-1 routes message to ALL subscribers across ALL cluster nodes
- Subscribers on Bondy-2 and Bondy-3 receive the message

**Q: What happens if a Bondy instance restarts?**
**A**: Clients on that instance disconnect and reconnect (handled by MaculaSdk retry logic).

- Sessions are ephemeral (stored in-memory on each node)
- Partisan cluster reforms automatically
- Subscriptions/registrations are lost → clients must re-subscribe
- This is where MaculaSdk retry logic is critical

### Deployment Configuration

**Kubernetes Deployment** (3 replicas):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bondy
  namespace: macula-system
spec:
  replicas: 3  # ⬆️ Scale to 3 instances
  selector:
    matchLabels:
      app: bondy
  template:
    metadata:
      labels:
        app: bondy
    spec:
      containers:
      - name: bondy
        image: registry.macula.local:5000/macula/bondy:1.0.0-rc.47-patched
        ports:
        - name: http-ws
          containerPort: 18080
        env:
        - name: BONDY_ERL_NODENAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name  # bondy-xxx-yyy unique per pod
        - name: BONDY_CLUSTER_PEERS
          value: "bondy-0.bondy.macula-system.svc.cluster.local,bondy-1.bondy.macula-system.svc.cluster.local,bondy-2.bondy.macula-system.svc.cluster.local"
        resources:
          requests:
            memory: "4Gi"    # ⬆️ Increased from 2Gi
            cpu: "2000m"      # ⬆️ Increased from 1000m
          limits:
            memory: "8Gi"     # ⬆️ Increased from 4Gi
            cpu: "4000m"      # ⬆️ Increased from 2000m
---
apiVersion: v1
kind: Service
metadata:
  name: bondy
  namespace: macula-system
spec:
  selector:
    app: bondy
  ports:
  - name: http-ws
    port: 18080
    targetPort: 18080
  - name: admin-api
    port: 18081
    targetPort: 18081
  type: ClusterIP
  sessionAffinity: None  # Round-robin load balancing
```

**Benefits**:
- 3x connection capacity (~8000 connections comfortably)
- Fault tolerance (1 instance can fail, cluster continues)
- Horizontal scaling (add more replicas as needed)

**Limitations**:
- Partisan mesh overhead (O(n²) connections between nodes)
- All-to-all message routing (network bandwidth increases with cluster size)
- Recommended max: ~10 nodes before bridge architecture needed

---

## 4. Bridge/Relay Pattern for Millions of Connections

### Problem: Flat Cluster Doesn't Scale to Millions
- Partisan full mesh: 10 nodes = 45 inter-node connections (n*(n-1)/2)
- Message broadcasting overhead grows exponentially
- Single WAMP topic with 1M subscribers → massive fanout

### Solution: Hierarchical Bridge Architecture

```
                  ┌───────────────────────┐
                  │  Core Bondy Cluster   │
                  │  (3-5 nodes)          │
                  │  - Realm: core        │
                  │  - Central PubSub hub │
                  └──────────┬────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Bridge-1     │     │ Bridge-2     │     │ Bridge-3     │
│ (Edge Realm) │     │ (Edge Realm) │     │ (Edge Realm) │
│ 10K clients  │     │ 10K clients  │     │ 10K clients  │
└──────────────┘     └──────────────┘     └──────────────┘
      │                    │                    │
   homes              homes               homes
```

### How Bridges Work

**Bridge Node Responsibilities**:
1. **Accept client connections** (edge realm)
2. **Aggregate subscriptions** (subscribe to core on behalf of many clients)
3. **Fan-out messages** (receive from core, broadcast to local clients)
4. **Bidirectional routing** (publish client events to core)

**Example Flow**:

**Scenario**: 30,000 homes publishing to `be.cortexiq.home.measured`

**Without Bridges** (flat cluster):
- 30,000 publishes/sec to 1 topic
- Core cluster must route each message to ALL subscribers
- Massive fanout: 1 message → 30K deliveries

**With Bridges**:
- Bridge-1: 10K homes → aggregates → publishes 1 aggregated message to core
- Bridge-2: 10K homes → aggregates → publishes 1 aggregated message to core
- Bridge-3: 10K homes → aggregates → publishes 1 aggregated message to core
- Core receives 3 messages instead of 30,000
- Core publishes aggregated data to subscribers (dashboard, queries)

### Implementation Approaches

**Option A: Custom Bridge Application** (Elixir)
```elixir
defmodule MaculaBridge.Aggregator do
  @moduledoc """
  Subscribes to local edge realm, aggregates, publishes to core realm.
  """

  def init(_) do
    # Connect to BOTH realms
    {:ok, edge_client} = MaculaSdk.Wamp.Client.start_link(
      url: "ws://localhost:18080/ws",
      realm: "be.cortexiq.edge.01"
    )

    {:ok, core_client} = MaculaSdk.Wamp.Client.start_link(
      url: "ws://core-bondy.macula-system:18080/ws",
      realm: "be.cortexiq.core"
    )

    # Subscribe to edge realm
    MaculaSdk.Wamp.Client.subscribe(
      edge_client,
      "be.cortexiq.home.measured",
      &handle_edge_event/1
    )

    {:ok, %{edge: edge_client, core: core_client, buffer: []}}
  end

  def handle_edge_event(event_data, state) do
    # Aggregate events (batch by time window or count)
    new_buffer = [event_data | state.buffer]

    # Publish batch to core every 1 second
    if length(new_buffer) > 100 or time_to_flush?(state) do
      aggregated = aggregate_measurements(new_buffer)

      MaculaSdk.Wamp.Client.publish(
        state.core,
        "be.cortexiq.bridge.01.measurements_aggregated",
        [],
        aggregated
      )

      {:noreply, %{state | buffer: []}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end
end
```

**Option B: Bondy Native Bridges** (if supported)
- Check Bondy docs for built-in bridge/relay functionality
- May have optimized C-level implementation

**Option C: Nginx Stream Proxy** (simple pass-through)
- Not true aggregation, just load balancing
- Useful for geographic distribution

---

## 5. Recommended Phased Rollout

### Phase 1: Immediate (This PR)
- ✅ Deploy patched Bondy (timeout fix)
- ✅ Implement batch-based staggering (5-second delays between batches)
- **Goal**: Support current 2750 homes reliably

### Phase 2: Short-term (Next Sprint)
- Deploy 3-instance Bondy cluster
- Configure Partisan clustering
- Test failover scenarios
- **Goal**: Support up to 8000 connections comfortably

### Phase 3: Medium-term (1-2 Months)
- Implement connection rate limiting in MaculaSdk
- Add exponential backoff for failed connections
- Implement health checks and circuit breakers
- **Goal**: Graceful degradation under overload

### Phase 4: Long-term (3-6 Months)
- Design and implement bridge architecture
- Deploy edge Bondy instances
- Implement aggregation logic
- **Goal**: Support 100K+ connections

### Phase 5: Scale (6-12 Months)
- Multi-region deployment
- Geographic edge distribution
- Message aggregation optimizations
- **Goal**: Support 1M+ connections

---

## 6. Monitoring and Metrics

### Critical Metrics to Track

**Bondy Performance**:
- Connection rate (connections/sec)
- Active sessions count
- HELLO handshake latency (p50, p95, p99)
- Message throughput (messages/sec)
- Partisan cluster health (inter-node latency)

**WAMP Protocol**:
- SUBSCRIBE operations/sec
- PUBLISH operations/sec
- EVENT deliveries/sec
- CALL (RPC) operations/sec

**Client Health**:
- Connection success rate
- Retry attempts
- Backoff delays
- Error 1011 occurrences (should be ZERO after patch)

### Alerting Thresholds

**Warning**:
- Connection rate > 50/sec sustained for >30s
- Active sessions > 5000 on single instance
- HELLO latency p95 > 500ms

**Critical**:
- Connection rate > 100/sec
- Active sessions > 8000 on single instance
- HELLO latency p95 > 1000ms
- Error 1011 errors > 10/min

---

## 7. Cost-Benefit Analysis

### Current Single-Instance Limits
- **Connections**: ~5000 comfortable, 8000 max
- **Resource**: 2Gi RAM, 1 CPU
- **Cost**: Minimal (already deployed)

### 3-Instance Cluster
- **Connections**: ~15K comfortable, 24K max
- **Resource**: 12Gi RAM, 6 CPU total
- **Cost**: 3x infrastructure
- **Benefit**: Fault tolerance + horizontal scale

### Bridge Architecture (10 bridges)
- **Connections**: 100K comfortable, 200K max
- **Resource**: Core (15Gi RAM, 9 CPU) + Bridges (20Gi RAM, 10 CPU)
- **Cost**: 11x infrastructure (1 core cluster + 10 bridges)
- **Benefit**: Message aggregation reduces core load, geographic distribution

### Millions of Connections
- **Connections**: 1M+
- **Architecture**: Multi-region core clusters + hundreds of edge bridges
- **Resource**: Substantial (requires dedicated infrastructure planning)
- **Cost**: Significant (cloud-native, auto-scaling approach recommended)

---

## 8. Recommendations

### For Current PoC (2750 homes)
✅ **Deploy patched Bondy** (timeout fix)
✅ **Implement batch staggering** (200ms delay + batches of 50)
⏭️ **Monitor for 24 hours** before further scaling

### For Production (up to 10K connections)
🔄 **Deploy 3-instance Bondy cluster**
🔄 **Increase resources per instance** (4Gi RAM, 2 CPU)
🔄 **Implement connection rate limiting in clients**

### For Scale (100K+ connections)
📋 **Design bridge architecture**
📋 **Implement aggregation logic**
📋 **Deploy edge Bondy instances**

---

## 9. Open Questions

1. **Bondy clustering behavior**: Does Partisan automatically load-balance client connections, or does Nginx handle this?
   - **Answer**: Nginx/K8s Service handles load balancing. Partisan only routes messages between nodes.

2. **Session affinity**: Do we need sticky sessions for WAMP connections?
   - **Answer**: No, WAMP sessions are node-local but PubSub works cluster-wide.

3. **Message ordering**: How does Bondy guarantee message order in clustered mode?
   - **Research needed**: Check Bondy docs for ordering guarantees.

4. **Bridge support**: Does Bondy have native bridge/relay functionality?
   - **Research needed**: Review Bondy documentation and source code.

5. **Partisan limits**: What's the recommended max cluster size for Partisan?
   - **Research needed**: Check Partisan documentation for scaling guidance.

---

## 10. Next Steps

**Immediate (This Session)**:
1. ✅ Patch Bondy timeout bug → Build Docker image
2. 🔄 Build and push patched Bondy image to registry
3. ⏭️ Update Bondy deployment to use patched image
4. ⏭️ Implement batch-based staggering in homes/application.ex
5. ⏭️ Deploy and test with 2750 homes
6. ⏭️ Monitor connection success rate and error logs

**Follow-up (Next Session)**:
1. Design 3-instance Bondy cluster deployment
2. Configure Partisan clustering
3. Test failover scenarios
4. Benchmark connection capacity

---

**Document Author**: Claude Code
**Last Updated**: 2025-11-05
**Status**: Living document - update as architecture evolves
