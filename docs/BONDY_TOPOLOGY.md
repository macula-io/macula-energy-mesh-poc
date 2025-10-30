# Bondy Deployment Topology

This document describes the deployment topology for Bondy WAMP routers across different environments.

## Overview

Macula Platform uses different Bondy deployment topologies based on the deployment environment:

| Environment | Topology | Bondy Instances | Rationale |
|-------------|----------|-----------------|-----------|
| **KinD (Local Dev)** | Hub-Spoke | 1 (hub only) | Simplicity, resource efficiency, fast iteration |
| **Beam Clusters (Production-like)** | Full Mesh | 4 (one per cluster) | Resilience, fault tolerance, production validation |

---

## KinD Deployment: Hub-Spoke Topology

### Architecture

```
                    ┌──────────────────────────┐
                    │   Hub Cluster            │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │ Bondy WAMP Router  │  │
                    │  │ (macula-system)    │  │
                    │  │                    │  │
                    │  │ Realm:             │  │
                    │  │ be.cortexiq.energy │  │
                    │  └─────────┬──────────┘  │
                    └────────────┼─────────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
                │                │                │
      ┌─────────▼────────┐  ┌────▼───────┐  ┌────▼───────┐
      │ Edge-01          │  │ Edge-02    │  │ Edge-03    │
      │                  │  │            │  │            │
      │ Payloads:        │  │ Payloads:  │  │ Payloads:  │
      │ - Dashboard      │  │ - Homes    │  │ - Homes    │
      │ - Projections    │  │ - Utilities│  │            │
      │ - Postgres       │  │            │  │            │
      └──────────────────┘  └────────────┘  └────────────┘
             ▲                    ▲               ▲
             │                    │               │
             └────────────────────┴───────────────┘
                  All connect to hub Bondy via:
                  ws://172.20.0.5:30080/ws
```

### Configuration

**Hub Bondy:**
- Namespace: `macula-system`
- Service: `bondy.macula-system.svc.cluster.local:18080`
- NodePort: `30080` (accessible from edges via Docker bridge `172.20.0.5`)
- Authentication: Anonymous (security disabled for PoC)

**Edge Applications:**
- Connect to hub via: `ws://172.20.0.5:30080/ws`
- Realm: `be.cortexiq.energy`
- No local Bondy instance

### Advantages

1. **Simplicity**
   - Single Bondy instance to configure and manage
   - Easy to understand and explain in demos
   - Clear, centralized message routing

2. **Resource Efficiency**
   - Only ~2Gi memory for Bondy (vs 10Gi for mesh)
   - Low CPU overhead
   - Critical for laptop/desktop development

3. **Fast Development Iteration**
   - Changes require updating only hub Bondy
   - Quick restarts and debugging
   - Single log stream to monitor

4. **Easy Observability**
   - All WAMP traffic visible in one place
   - Simple message tracing
   - Single point for metrics collection

5. **Demo-Friendly**
   - Architecture diagram is simple to explain
   - "All edges connect to hub" is intuitive
   - Focuses attention on application logic, not infrastructure

### Limitations

1. **Single Point of Failure**: Hub Bondy crash = complete system failure
2. **Scalability Bottleneck**: All traffic funnels through one router
3. **No Partition Tolerance**: Edge clusters can't operate during hub outage
4. **Unrealistic for Production**: Doesn't demonstrate distributed resilience

### When to Use

- ✅ Local development on laptops/desktops
- ✅ PoC demonstrations and investor pitches
- ✅ Integration testing
- ✅ Rapid prototyping
- ❌ Production deployments
- ❌ High-availability requirements

---

## Beam Cluster Deployment: Full Mesh Topology

### Architecture

```
  ┌─────────────────────────────────────────────────────────┐
  │                   Full Bondy Mesh                       │
  │                                                         │
  │    beam00 (Hub)          beam01                        │
  │    ┌──────────┐          ┌──────────┐                  │
  │    │  Bondy   │◄────────►│  Bondy   │                  │
  │    └────┬─────┘          └─────┬────┘                  │
  │         │  ╲                 ╱  │                       │
  │         │   ╲     Bridge   ╱   │                       │
  │         │    ╲   Relays   ╱    │                       │
  │         │     ╲         ╱      │                       │
  │         │      ╲       ╱       │                       │
  │    ┌────┴───┐   ╲   ╱   ┌──────┴───┐                  │
  │    │ Bondy  │◄───╳───────►│  Bondy   │                 │
  │    └────────┘   ╱   ╲   └──────────┘                  │
  │    beam02      ╱     ╲     beam03                      │
  │               ╱       ╲                                 │
  │              ╱         ╲                                │
  │             ╱           ╲                               │
  │            ╱             ╲                              │
  │           ╱               ╲                             │
  │          ╱                 ╲                            │
  └─────────────────────────────────────────────────────────┘

  Each node:
  - Runs local Bondy instance in macula-system namespace
  - Hosts application payloads (homes, utilities, dashboard, etc.)
  - Applications connect to local Bondy (localhost or ClusterIP)
  - Bondy instances form mesh via bridge relays
```

### Mesh Connectivity Matrix

| From/To | beam00 | beam01 | beam02 | beam03 |
|---------|--------|--------|--------|--------|
| beam00  | -      | ✓      | ✓      | ✓      |
| beam01  | ✓      | -      | ✓      | ✓      |
| beam02  | ✓      | ✓      | -      | ✓      |
| beam03  | ✓      | ✓      | ✓      | -      |

Each Bondy node maintains bridge relay connections to all other nodes (6 total connections).

### Configuration

**Per-Cluster Bondy:**
```yaml
# Each beam cluster has its own Bondy
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bondy
  namespace: macula-system
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: bondy
        image: leapsight/bondy:1.0.0-rc.46
        ports:
        - name: wamp-ws
          containerPort: 18080
        - name: admin-api
          containerPort: 18081
        - name: cluster
          containerPort: 18086  # For bridge relay
        env:
        - name: BONDY_CLUSTER_ENABLED
          value: "true"
        # Bridge relay configuration to other beams
        - name: BONDY_BRIDGE_RELAY_beam01
          value: "ws://bondy.macula-system.svc.beam-01.local:18086"
        # ... other bridge relays
```

**Application Configuration:**
```yaml
# Applications connect to local Bondy
env:
- name: BONDY_URL
  value: "ws://bondy.macula-system.svc.cluster.local:18080/ws"
- name: BONDY_REALM
  value: "be.cortexiq.energy"
```

### Advantages

1. **Resilience & Fault Tolerance** ⭐⭐⭐
   - No single point of failure
   - System continues operating if one Bondy crashes
   - Network partition tolerance (split-brain scenarios)
   - Individual clusters can operate autonomously

2. **Performance**
   - Low latency: Apps connect to local Bondy
   - Load distribution: Routing load spread across 4 nodes
   - Reduced network hops for intra-cluster communication
   - Better bandwidth utilization

3. **Scalability**
   - Horizontal scaling: Add new beam nodes without overloading central node
   - Independent scaling: Each cluster scales Bondy independently
   - Geographic distribution ready

4. **Production Realism**
   - Validates production architecture
   - Tests distributed edge computing scenarios
   - Demonstrates platform resilience
   - Validates failure recovery mechanisms

5. **Edge Autonomy**
   - Edge sites can function during WAN outages
   - Critical for IoT/edge computing use cases
   - Local data processing during disconnection

### Implementation Considerations

#### 1. Bridge Relay Setup

Each Bondy must configure bridge relays to peer nodes:

```erlang
%% bondy.conf for beam00
[
  {bondy, [
    {bridge_relay, [
      #{
        endpoint => <<"ws://bondy.macula-system.svc.beam-01.local:18086/ws">>,
        realm => <<"be.cortexiq.energy">>,
        enabled => true
      },
      #{
        endpoint => <<"ws://bondy.macula-system.svc.beam-02.local:18086/ws">>,
        realm => <<"be.cortexiq.energy">>,
        enabled => true
      },
      #{
        endpoint => <<"ws://bondy.macula-system.svc.beam-03.local:18086/ws">>,
        realm => <<"be.cortexiq.energy">>,
        enabled => true
      }
    ]}
  ]}
].
```

#### 2. DNS Configuration

Each beam cluster needs DNS resolution for peer clusters:

```yaml
# CoreDNS/PowerDNS configuration
bondy.macula-system.svc.beam-00.local → 192.168.1.10
bondy.macula-system.svc.beam-01.local → 192.168.1.11
bondy.macula-system.svc.beam-02.local → 192.168.1.12
bondy.macula-system.svc.beam-03.local → 192.168.1.13
```

#### 3. Network Connectivity

**Requirements:**
- Each Bondy must reach others on port 18086 (bridge relay)
- Network must support bidirectional communication
- Firewall rules must allow cross-cluster traffic

**Verification:**
```bash
# From beam00, test connectivity to beam01
curl -v http://bondy.macula-system.svc.beam-01.local:18081/health
```

#### 4. Security Considerations

**Bridge Relay Authentication:**
```erlang
%% Use dedicated credentials for inter-Bondy communication
#{
  endpoint => <<"ws://bondy.beam-01:18086/ws">>,
  realm => <<"be.cortexiq.energy">>,
  authid => <<"bondy_bridge_beam00">>,
  credentials => {ticket, <<"secure_bridge_token">>}
}
```

**TLS for Production:**
```erlang
#{
  endpoint => <<"wss://bondy.beam-01:18086/ws">>,
  tls_opts => [
    {verify, verify_peer},
    {cacertfile, "/etc/bondy/ca.pem"},
    {certfile, "/etc/bondy/cert.pem"},
    {keyfile, "/etc/bondy/key.pem"}
  ]
}
```

#### 5. Monitoring & Observability

**Metrics to Monitor:**
- Bridge relay connection status (up/down)
- Message latency between nodes
- Message routing paths
- Bridge relay reconnection attempts
- Cluster partition events

**Example Prometheus Metrics:**
```
bondy_bridge_relay_status{from="beam00",to="beam01"} 1  # 1=up, 0=down
bondy_bridge_relay_messages_total{from="beam00",to="beam01"} 15234
bondy_bridge_relay_latency_seconds{from="beam00",to="beam01"} 0.045
```

#### 6. Resource Requirements

**Per Beam Node:**
- **Memory**: 2-4Gi per Bondy instance
- **CPU**: 500m-1000m
- **Storage**: 10Gi for persistent data (if using embedded DB)
- **Network**: ~10Mbps per bridge relay connection

**Total for 4-node mesh:**
- Memory: 8-16Gi
- CPU: 2-4 cores
- Network bandwidth: ~60Mbps (6 connections × 10Mbps)

### Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| **Split-brain scenarios** | Implement realm consensus protocol, last-write-wins with timestamps |
| **Message ordering** | Use Bondy's message sequencing, accept eventual consistency |
| **Connection flapping** | Exponential backoff, health checks, circuit breakers |
| **Debugging complexity** | Centralized logging (Loki), distributed tracing (Jaeger) |
| **Configuration drift** | GitOps for Bondy configs, automated config validation |

### When to Use

- ✅ Production deployments
- ✅ High-availability requirements
- ✅ Geographic distribution
- ✅ Edge computing scenarios
- ✅ Validating distributed systems behavior
- ❌ Local development (too resource-intensive)
- ❌ Simple demos (too complex to explain)

---

## Migration Path: Hub-Spoke → Full Mesh

### Phase 1: Preparation (Current)
- ✅ Hub-spoke on KinD clusters
- ✅ All applications use `BONDY_URL` environment variable
- ✅ No hardcoded Bondy endpoints in code
- ✅ Documentation complete

### Phase 2: Hybrid Testing
- Deploy Bondy on one edge cluster (beam01)
- Configure bridge relay: beam00 ↔ beam01
- Test failover scenarios
- Validate message routing

### Phase 3: Full Mesh Deployment
- Deploy Bondy on all 4 beam clusters
- Configure full mesh (6 bridge relays)
- Migrate applications to use local Bondy
- Validate production readiness

### Phase 4: Production Hardening
- Enable TLS for all bridge relays
- Implement authentication for inter-Bondy communication
- Set up comprehensive monitoring
- Document runbooks for failure scenarios

---

## Comparison Matrix

| Aspect | Hub-Spoke (KinD) | Full Mesh (Beam) |
|--------|------------------|------------------|
| **Bondy Instances** | 1 | 4 |
| **Memory Usage** | ~2Gi | ~10Gi |
| **Single Point of Failure** | Yes | No |
| **Partition Tolerance** | No | Yes |
| **Configuration Complexity** | Low | High |
| **Debugging Difficulty** | Easy | Hard |
| **Production Ready** | No | Yes |
| **Demo Friendly** | Yes | No |
| **Edge Autonomy** | No | Yes |
| **Resource Efficiency** | High | Low |
| **Scalability** | Limited | Excellent |
| **Fault Tolerance** | None | High |

---

## Decision Rationale

### Why Hub-Spoke for KinD?

**Development Efficiency:**
- KinD clusters run on a single machine (laptop/desktop)
- Limited resources (8-16GB RAM typical)
- Need fast iteration and debugging
- Focus on application development, not infrastructure

**Demo Requirements:**
- Presentations need simple, clear architecture
- "All connect to hub" is easy to explain to investors
- Visual diagrams are cleaner and more intuitive
- Reduces cognitive load on audience

**Operational Simplicity:**
- Single Bondy instance to start/stop/debug
- One log stream to monitor
- Easier troubleshooting for developers new to WAMP

### Why Full Mesh for Beam?

**Production Validation:**
- Beam clusters (4 physical machines with 16-32GB RAM each) represent production environment
- Need to validate resilience and fault tolerance
- Test real-world failure scenarios (network partitions, node crashes)

**High Availability:**
- Production systems cannot tolerate single point of failure
- Edge computing requires autonomy during WAN outages
- Customers expect 99.9%+ uptime

**Scalability Testing:**
- Validate horizontal scaling of Bondy
- Test load distribution across multiple routers
- Measure performance under realistic conditions

**Edge Computing Reality:**
- Real edge deployments are geographically distributed
- Edge sites need local autonomy
- WAN connectivity is unreliable in many industrial/IoT scenarios

---

## References

- [Bondy Bridge Relay Documentation](https://docs.bondy.io/reference/clustering/bridge_relay)
- [WAMP Distributed Routing](https://wamp-proto.org/wamp_latest.html#x14-4-4-distributed-pubsub)
- [Macula Architecture Overview](./ARCHITECTURE.md)

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2025-10-30 | Initial documentation | Claude + RL |

---

## Future Considerations

1. **Hybrid Topology**: Hub as coordinator with edge Bondys for autonomy
2. **Dynamic Mesh**: Bondy nodes join/leave mesh dynamically
3. **Hierarchical Routing**: Regional hubs with local edge clusters
4. **Multi-Region**: Cross-datacenter Bondy mesh with WAN optimization
