# Bondy Deployment Topology

This document describes the deployment topology for Bondy WAMP routers across different environments.

## Architecture Principles

Macula Platform follows a **hierarchical hub-and-spoke architecture** that mirrors real-world B2B/B2C deployment patterns:

### 1. Hub Clusters (Business Infrastructure)

**Definition:** Hub clusters represent infrastructure provided by businesses and organizations.

**Characteristics:**
- **Host heavy workloads**: Dashboards, analytics, storage, centralized services
- **More powerful nodes**: Higher CPU, memory, and storage capacity
- **Multi-tenant**: Serve multiple edge customers
- **B2B connectivity**: Hubs connect to other hubs via Bondy clustering

**Examples:**
- Energy analytics companies (hosting dashboards and projections)
- Utility providers (managing customer data and billing)
- IoT platforms (aggregating device data)
- SaaS providers (offering services to edge customers)

**Role in Architecture:**
- Central coordination point for edge clusters
- Data aggregation and analytics
- Cross-organization communication via hub-to-hub clustering
- Realm management and configuration

### 2. Edge Clusters (Customer/User Infrastructure)

**Definition:** Edge clusters represent infrastructure provided by end users and customers.

**Characteristics:**
- **Host user applications**: Lightweight workloads, customer-specific logic
- **Resource-constrained**: Optimized for edge devices (IoT, field sites, homes)
- **Autonomous operation**: Can function independently during WAN outages
- **Local event sourcing**: Future integration with ExESDB Event Store for local-first architecture

**Examples:**
- Home energy management systems
- Field IoT devices and sensors
- Customer premises equipment (CPE)
- Manufacturing floor controllers
- Retail point-of-sale systems

**Role in Architecture:**
- Execute customer-specific application logic
- Collect and process local data
- Connect to parent hub for coordination and data sharing
- Operate autonomously when disconnected

### 3. Supercluster Topology

Macula deployments are organized into **superclusters**, each with one hub and multiple edges:

```
Supercluster = 1 Hub + N Edges

Example:
┌─────────────────────────────────────┐
│  KinD Supercluster                  │
│                                     │
│  Hub: kind-hub-01                   │
│  Edges: kind-edge-01, kind-edge-02, │
│         kind-edge-03, kind-edge-04  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Beam Supercluster                  │
│                                     │
│  Hub: beam00                        │
│  Edges: beam01, beam02, beam03      │
└─────────────────────────────────────┘
```

**Inter-Supercluster Connectivity:**
Hubs from different superclusters connect via **Bondy clustering** (not bridge relay):
- kind-hub-01 ↔ beam00 (clustered)
- Enables cross-organization communication
- B2B connectivity (e.g., analytics company ↔ energy provider)

---

## Current Deployment Architecture

### Overview

```
                Hub-to-Hub Clustering (Bondy Cluster)
                ┌─────────────────────────────┐
                │                             │
        ┌───────▼────────┐          ┌────────▼──────┐
        │  KinD Hub      │          │  Beam Hub     │
        │  (kind-hub-01) │◄────────►│  (beam00)     │
        │                │          │               │
        │  Bondy Router  │  Bondy   │  Bondy Router │
        │  macula-system │ Cluster  │  macula-system│
        └────────┬───────┘          └───────┬───────┘
                 │                          │
         ┌───────┼────────┐         ┌───────┼────────┐
         │       │        │         │       │        │
    ┌────▼──┐ ┌─▼────┐ ┌─▼────┐ ┌──▼───┐ ┌─▼────┐ ┌─▼────┐
    │Edge-01│ │Edge-02│ │Edge-03│ │beam01│ │beam02│ │beam03│
    │       │ │       │ │       │ │      │ │      │ │      │
    │Dash+  │ │Homes+ │ │Homes  │ │Homes │ │Utils │ │Homes │
    │Proj   │ │Utils  │ │       │ │      │ │      │ │      │
    └───────┘ └───────┘ └───────┘ └──────┘ └──────┘ └──────┘

    Spoke connections: ws://hub-bondy:port/ws
```

### KinD Supercluster (Local Development)

**Hub: kind-hub-01 (macula-hub)**
- **Namespace**: `macula-system`
- **Bondy Service**: `bondy.macula-system.svc.cluster.local:18080`
- **NodePort**: `30080` (exposed to Docker bridge `172.20.0.5`)
- **Hosts**:
  - Bondy WAMP Router
  - Bondy Console (management UI)
  - Portal (monitoring)
  - Future: Monitoring stack (Prometheus, Grafana)

**Edges (kind-edge-01 through kind-edge-04)**
- **Connection**: `ws://172.20.0.5:30080/ws` (hub NodePort)
- **Realm**: `be.cortexiq.energy`
- **Authentication**: Anonymous (PoC only)
- **Workloads**:
  - `kind-edge-01`: Dashboard, Projections, Postgres (analytics company infra)
  - `kind-edge-02`: Homes, Utilities (mixed customer workloads)
  - `kind-edge-03`: Homes (residential customer)
  - `kind-edge-04`: Homes (residential customer)

### Beam Supercluster (Production-like)

**Hub: beam00**
- **IP**: `192.168.1.10`
- **Namespace**: `macula-system`
- **Bondy Service**: `bondy.macula-system.svc.cluster.local:18080`
- **NodePort**: TBD (will be exposed for edge connectivity)
- **Hardware**: 16GB RAM, 1x 932GB HDD, 1x 224GB NVMe
- **Hosts**:
  - Bondy WAMP Router (clustered with kind-hub-01)
  - Monitoring and centralized services
  - Hub-level analytics and dashboards

**Edges (beam01, beam02, beam03)**
- **Connection**: `ws://beam00-ip:port/ws`
- **Realm**: `be.cortexiq.energy`
- **Authentication**: Token-based (production-ready)
- **Hardware**: 32GB RAM each, 2x 932GB HDD, 1x NVMe
- **Workloads**:
  - `beam01`: Customer homes simulation
  - `beam02`: Utility provider applications
  - `beam03`: Additional customer workloads
  - Future: ExESDB Event Store for local event sourcing

---

## Hub-to-Hub Connectivity

### Bondy Clustering (Not Bridge Relay)

Hubs connect using **Bondy's native clustering**, not bridge relays:

**Why Clustering?**
- **Shared realm state**: Consistent view of realm configuration
- **Load balancing**: Clients can connect to any hub
- **Automatic failover**: If one hub fails, edges can reconnect to another
- **Session mobility**: Sessions can move between hubs
- **Single logical realm**: Appears as one realm despite multiple physical routers

**Configuration Example:**

```erlang
%% kind-hub-01 bondy.conf
[
  {bondy, [
    {cluster, [
      {enabled, true},
      {discovery, [
        {type, static},
        {nodes, [
          <<"bondy@kind-hub-01.macula-system.svc.cluster.local">>,
          <<"bondy@beam00.macula-system.svc.beam-00.local">>
        ]}
      ]}
    ]}
  ]}
].
```

### Inter-Supercluster Communication

```
Organization A (Hub: kind-hub-01)
    ↓ publishes event
Bondy Cluster (kind-hub-01 + beam00)
    ↓ routes to
Organization B (Hub: beam00)
    ↓ forwards to edge
Edge Customer (beam01)
    ↓ receives event
```

**Use Cases:**
- Analytics company (kind-edge-01) aggregates data from all edges (both superclusters)
- Energy provider (beam02 utilities) offers contracts to homes (kind-edge-02, beam01)
- Cross-organization data sharing with proper ACLs
- Multi-tenant isolation with shared infrastructure

---

## Edge Autonomy & Local Event Sourcing

### Current State
Edges connect to hub for all WAMP operations (pub/sub, RPC).

### Future: ExESDB on Edges

**Vision:** Each edge cluster runs a local ExESDB Event Store for local-first architecture.

```
┌─────────────────────────────────────┐
│  Edge Cluster (e.g., beam01)        │
│                                     │
│  ┌──────────────┐  ┌─────────────┐ │
│  │  ExESDB      │  │  Local Apps │ │
│  │  Event Store │◄─┤  (Homes)    │ │
│  └──────┬───────┘  └─────────────┘ │
│         │                           │
│         │ Sync events               │
│         ▼                           │
│  ┌──────────────┐                  │
│  │  Bondy       │                  │
│  │  (to Hub)    │                  │
│  └──────────────┘                  │
└─────────────────────────────────────┘
```

**Benefits:**
- **Offline operation**: Apps continue working during WAN outages
- **Local-first**: Events stored locally before syncing to hub
- **Performance**: Low latency for local operations
- **Data sovereignty**: Customer data stays on premises
- **Resilience**: No data loss during network partitions

**Implementation Plan:**
1. Phase 1: Edges connect directly to hub Bondy (✅ Current)
2. Phase 2: Deploy ExESDB on one edge (beam01) for testing
3. Phase 3: Sync ExESDB → Hub via WAMP events
4. Phase 4: Deploy ExESDB on all production edges
5. Phase 5: Edge apps use local ExESDB, sync via Bondy

---

## Resource Requirements

### KinD Supercluster (Development)

**Hub (kind-hub-01):**
- Memory: 4Gi (Bondy 2Gi + services 2Gi)
- CPU: 1000m
- Storage: 20Gi

**Per Edge:**
- Memory: 2-4Gi (varies by workload)
- CPU: 500-1000m
- Storage: 10Gi

**Total KinD:** ~20Gi memory, 5 CPU cores (single laptop/desktop)

### Beam Supercluster (Production-like)

**Hub (beam00):**
- Memory: 4-8Gi (Bondy + monitoring)
- CPU: 2 cores
- Storage: 100Gi (/bulk0)
- Hardware: 16GB RAM, dedicated machine

**Per Edge (beam01-03):**
- Memory: 4-8Gi (apps + future ExESDB)
- CPU: 2 cores
- Storage: 200Gi (/bulk0, /bulk1)
- Hardware: 32GB RAM, dedicated machines

**Total Beam:** ~24Gi memory, 8 CPU cores (4 physical machines)

---

## Deployment Strategy

### KinD (Current)

**Purpose:** Local development, PoC demos, investor presentations

**Topology:**
- 1 Hub (kind-hub-01) with Bondy
- 4 Edges connecting to hub
- Hub-spoke only (no hub-to-hub yet)

**Advantages:**
- Fast iteration and debugging
- Single-machine deployment
- Simple to understand and demo
- Low resource usage

**Limitations:**
- Not production-ready
- Single point of failure (hub)
- No inter-supercluster testing

### Beam (Planned)

**Purpose:** Production validation, performance testing, customer demos

**Topology:**
- 1 Hub (beam00) with Bondy
- 3 Edges (beam01-03) connecting to hub
- Hub-to-hub clustering with kind-hub-01

**Advantages:**
- Production-realistic architecture
- Physical network (not Docker bridge)
- Real hardware performance validation
- Multi-organization testing (via hub clustering)

**Implementation Steps:**
1. Deploy Bondy on beam00 (hub)
2. Configure Bondy clustering: kind-hub-01 ↔ beam00
3. Deploy edge workloads on beam01-03
4. Test cross-supercluster communication
5. Add ExESDB on one edge (beam01)
6. Validate failover and partition scenarios

---

## Commercial Model Alignment

This architecture aligns with real-world commercial models:

### Hub Operators (SaaS Providers)

**Who:** Analytics companies, utility providers, IoT platforms

**What they do:**
- Host dashboards and analytics (heavy workloads on hubs)
- Provide APIs and services to edge customers
- Aggregate data from multiple edge customers
- Offer multi-tenant SaaS services

**Revenue model:**
- Charge edges per API call, data volume, or monthly subscription
- B2B connectivity to other hub operators (data exchange fees)

**Macula role:**
- Hub clusters run on hub operator infrastructure
- Bondy clustering enables B2B connectivity
- Hub hosts heavy services (dashboards, storage, analytics)

### Edge Customers (End Users)

**Who:** Homeowners, small businesses, field sites, IoT devices

**What they do:**
- Run lightweight applications on edge infrastructure
- Collect and process local data (energy, sensors, etc.)
- Connect to hub for coordination and data sharing
- Operate autonomously when possible

**Payment model:**
- Pay hub operator for services (API calls, storage, analytics)
- Want data sovereignty (local ExESDB)
- Need offline operation (local-first with sync)

**Macula role:**
- Edge clusters run on customer infrastructure
- Lightweight workloads optimized for edge
- Future ExESDB for local event sourcing

---

## Comparison: Current vs Previous Mesh Proposal

| Aspect | Previous (Full Mesh) | Current (Hub-Spoke + Hub Clustering) |
|--------|---------------------|--------------------------------------|
| **Complexity** | High (N² connections) | Low (spoke to hub, hub clustering) |
| **Resource Usage** | Very high (Bondy everywhere) | Moderate (Bondy on hubs only) |
| **Commercial Model** | Unclear | Clear (hub = SaaS, edge = customer) |
| **Scalability** | Limited by mesh complexity | Excellent (add edges without hub changes) |
| **B2B Connectivity** | Not addressed | Native via hub clustering |
| **Edge Autonomy** | Via local Bondy | Via future ExESDB |
| **Conceptual Clarity** | Confusing | Clear (business vs customer infra) |
| **Demo-Friendliness** | Poor | Good (aligns with real-world) |

---

## Migration Path

### Phase 1: KinD Hub-Spoke (✅ Current)
- 1 Hub on KinD (kind-hub-01)
- 4 Edges on KinD
- No hub clustering yet
- Focus: Development velocity, demos

### Phase 2: Beam Hub + Edges
- Deploy Bondy on beam00 (hub)
- Deploy edge workloads on beam01-03
- Edges connect to beam00 hub
- No hub clustering yet
- Focus: Production validation

### Phase 3: Hub-to-Hub Clustering
- Configure Bondy clustering: kind-hub-01 ↔ beam00
- Test cross-supercluster communication
- Validate B2B use cases
- Focus: Multi-organization scenarios

### Phase 4: Edge Event Sourcing
- Deploy ExESDB on beam01 (test edge)
- Integrate apps with local ExESDB
- Sync events to hub via WAMP
- Validate offline operation
- Focus: Edge autonomy

### Phase 5: Production Hardening
- TLS for all connections
- Token-based authentication for edges
- Monitoring and observability
- Runbooks and operational procedures
- Focus: Production readiness

---

## Decision Rationale

### Why Hub-Spoke + Hub Clustering?

1. **Aligns with Reality**
   - Businesses (hubs) provide infrastructure to customers (edges)
   - Mirrors SaaS/edge deployment patterns
   - Clear commercial model

2. **Scalability**
   - Add edges without increasing hub complexity
   - Hubs cluster for B2B (not with every edge)
   - Scales to 100s-1000s of edges per hub

3. **Resource Efficiency**
   - Edges don't need Bondy (future: optional local Bondy for ultra-high-availability)
   - Hub Bondy handles coordination
   - Edges run lightweight workloads

4. **Operational Simplicity**
   - Fewer moving parts than full mesh
   - Clear failure domains (hub vs edge)
   - Easier to debug and monitor

5. **Future-Proof**
   - ExESDB on edges provides local-first benefits
   - Hub clustering enables multi-org scenarios
   - Can add more hubs/edges without architecture changes

### Why Not Full Mesh?

1. **Conceptual Mismatch**: Edges are customers, not peers
2. **Over-Engineering**: Complexity without clear benefit
3. **Resource Waste**: Bondy on every edge is overkill
4. **Operational Burden**: Too many Bondy instances to manage
5. **Unclear Value Prop**: Doesn't align with commercial model

---

## References

- [Bondy Clustering Documentation](https://docs.bondy.io/reference/clustering/)
- [WAMP Router Bridge](https://wamp-proto.org/wamp_latest.html#router-bridge)
- [Macula Architecture Overview](./ARCHITECTURE.md)
- [ExESDB Local-First Event Store](https://github.com/beam-campus/ex-esdb)

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2025-10-30 | Initial documentation (full mesh) | Claude + RL |
| 2025-10-30 | Revised to hub-spoke + hub clustering | Claude + RL |

---

## Glossary

- **Hub**: Business/organization infrastructure hosting centralized services
- **Edge**: Customer/user infrastructure hosting lightweight applications
- **Supercluster**: 1 Hub + N Edges forming a logical deployment unit
- **Hub Clustering**: Bondy's native clustering protocol connecting hubs
- **Bridge Relay**: WAMP router-to-router connection (NOT used in our architecture)
- **ExESDB**: BEAM-native Event Store for local event sourcing
