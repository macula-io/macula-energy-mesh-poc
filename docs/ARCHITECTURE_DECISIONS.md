# Macula Platform Architecture Decisions

## ADR-001: Why Bondy Instead of NATS

**Date**: 2025-10-26
**Status**: Decided
**Decision Makers**: Architecture Team

### Context

During early development, we evaluated replacing Bondy (WAMP router) with NATS (cloud-native messaging system) for the Macula platform messaging layer.

**Initial Assumption**: NATS appeared to be a "better, more modern alternative" to Bondy due to its popularity in cloud-native ecosystems.

**NATS Advantages Considered:**
- Modern, cloud-native messaging system
- Better performance for high-throughput pub/sub
- Wider adoption and operational maturity
- Rich ecosystem of tools and integrations
- Multi-language client support
- Simpler deployment (single Go binary)

### The Evaluation Journey

**Phase 1: Initial Appeal**
NATS seemed like the obvious choice - it's widely adopted, has better tooling, and is the "modern" choice for cloud-native applications. We began implementing a NATS client for MaculaOs.

**Phase 2: The Critical Question**
During implementation, a crucial architectural question emerged:

> "Bondy, since it is built upon Erlang, claims to support direct node-to-node communication inside a realm. Will this still be possible using NATS?"

This question revealed a fundamental misunderstanding about what the Macula platform actually needs.

**Phase 3: Architectural Clarity**
The question forced us to clarify what "direct node-to-node communication" means:

**Within Bondy:**
- **Bondy Router Cluster**: Multiple Bondy nodes form an Erlang cluster using Distributed Erlang (via Partisan)
- **Internal Routing**: When a WAMP client on Node A publishes, and a subscriber is on Node B, Bondy routers communicate using **native Erlang message passing** internally
- **Transparent to Clients**: WAMP clients use WAMP protocol, but routers leverage BEAM distribution

**The Realization:**
Bondy's "direct communication" isn't about WAMP - it's about the **underlying Distributed Erlang infrastructure** that makes Macula Rings possible.

### The Critical Requirement: "One Big Computer"

**Macula's core value proposition is Macula Rings** - clusters of nodes that operate as "one big computer" using:
- **Distributed Erlang** clustering
- **Swarm** or libcluster for global process coordination
- **Global process registry** across nodes
- **Cross-node supervision trees**
- **Process migration** between nodes
- **Shared state primitives** (distributed ETS, etc.)

### Why NATS Cannot Support This

**NATS is a message broker, not a distributed runtime:**

❌ **No Distributed Erlang Support**
- NATS is written in Go, not Erlang/Elixir
- Cannot participate in BEAM distribution
- No access to Erlang's cluster primitives

❌ **No Global Process Coordination**
- Cannot use Swarm for global process registry
- No cross-node `GenServer.call({MyProc, :node@host}, :msg)`
- No distributed supervision trees

❌ **Just Message Passing**
- NATS provides pub/sub and request/reply
- Does NOT provide "one big computer" semantics
- Cannot share state or coordinate processes natively

### Why Bondy is the RIGHT Choice

**Bondy was designed for exactly this use case:**

✅ **Built on Erlang/OTP**
- Native Distributed Erlang support
- Uses Partisan for advanced clustering
- Full access to BEAM distribution primitives

✅ **Supports Macula Ring Architecture**
```
Ring A (Europe)                         Ring B (Asia)
┌──────────────────────────────────┐   ┌──────────────────────────────┐
│ Bondy Cluster                    │   │ Bondy Cluster                │
│ (Distributed Erlang)             │   │ (Distributed Erlang)         │
│                                  │   │                              │
│  Node 1 ←─┐                      │   │  Node 4 ←─┐                  │
│  Node 2 ←─┼─ Swarm/libcluster    │   │  Node 5 ←─┼─ Swarm          │
│  Node 3 ←─┘                      │   │  Node 6 ←─┘                  │
│                                  │   │                              │
│  "One Big Computer"              │   │  "One Big Computer"          │
└──────────────┬───────────────────┘   └──────────────┬───────────────┘
               │                                      │
               │         ┌────────────────┐           │
               └────────►│  Bondy Bridge  │◄──────────┘
                         │ (Realm Bridge) │
                         └────────────────┘
```

✅ **Realm Bridging**
- Connect multiple rings through bridge nodes
- Route WAMP messages between isolated rings
- Federated topology support

✅ **Provides Both Layers**
- **Infrastructure**: Distributed Erlang for platform coordination
- **Application**: WAMP pub/sub and RPC for payloads

### What We Keep with Bondy

**Platform Capabilities:**
- Macula Rings operate as unified BEAM clusters
- Global process registry across ring nodes
- Cross-node supervision and fault tolerance
- Process migration for load balancing
- Distributed state management

**Application Capabilities:**
- WAMP pub/sub for event-driven architecture
- WAMP RPC for request/reply patterns
- Topic-based routing and filtering
- Built-in authentication and authorization

### What We Would Lose with NATS

**Critical Platform Features:**
- ❌ "One big computer" semantics
- ❌ Distributed Erlang clustering
- ❌ Swarm/libcluster coordination
- ❌ Global process registry
- ❌ Cross-node supervision
- ❌ Native BEAM integration

**The platform would be fundamentally weakened.**

### Alternative: Hybrid Approach (Rejected)

We considered using BOTH systems:
- Distributed Erlang + Swarm for intra-ring coordination
- NATS for inter-ring application messaging

**Rejected because:**
- Too complex (two messaging systems)
- Unclear boundaries for developers
- Bondy already solves both problems
- Added operational burden
- Marginal performance gains don't justify complexity

### Decision

**Use Bondy for the Macula Platform.**

**Rationale:**
1. Macula Rings require "one big computer" semantics
2. This requires Distributed Erlang (non-negotiable)
3. Bondy provides Distributed Erlang + WAMP routing
4. Bondy supports realm bridging for inter-ring communication
5. Single system is simpler than hybrid approach
6. WAMP is sufficient for application-level messaging

### Consequences

**Positive:**
- ✅ Full "one big computer" capability within rings
- ✅ Simpler architecture (one messaging system)
- ✅ Native BEAM integration
- ✅ Realm bridging for multi-ring topologies
- ✅ Leverages Erlang/OTP strengths

**Negative:**
- ❌ Bondy less well-known than NATS
- ❌ Smaller ecosystem and community
- ❌ WAMP less familiar than NATS protocols
- ❌ Fewer monitoring/tooling options

**Trade-offs Accepted:**
- We accept smaller ecosystem for platform capabilities
- We accept WAMP learning curve for "one big computer"
- Macula's differentiation IS the distributed runtime, not just messaging

### Lessons Learned

**1. "Modern" ≠ "Right"**
- NATS is modern for cloud-native microservices messaging
- Bondy is right for distributed BEAM runtime platforms
- Technology choices must align with architectural requirements, not trends

**2. Understand Your Core Value Proposition**
Macula's differentiation is NOT messaging - it's the distributed runtime capability:
- If Macula were "just another message broker wrapper," NATS would be fine
- But Macula Rings are "one big computer" - that requires Distributed Erlang
- **The platform's unique value depends on BEAM distribution**

**3. Question the Right Things**
The critical question wasn't "Can NATS do pub/sub?" (yes, it can).

The critical question was "Can NATS support Macula Rings as 'one big computer'?" (no, it cannot).

**4. Technology Constraints Can Clarify Architecture**
The NATS evaluation forced us to articulate exactly what Macula Rings need:
- Not just message routing
- Not just pub/sub patterns
- **Distributed Erlang clustering with Swarm coordination**

This clarity strengthens our positioning and roadmap.

### What Changed Our Mind

**The "One Big Computer" Vision:**
When we articulated that Macula Rings should operate as "one big computer" (using Distributed Erlang + Swarm), it became immediately clear that:

1. **NATS Cannot Provide This** - It's a Go-based message broker with no BEAM integration
2. **Bondy Was Purpose-Built For This** - It's an Erlang/OTP application with Partisan clustering
3. **This IS Our Differentiation** - The "one big computer" capability is what makes Macula unique

**The moment we said "one big computer," the decision was obvious.**

### Future Considerations

**If requirements change:**
- Could add NATS later for specific use cases (external integrations, non-BEAM apps)
- Could use NATS as "north-south" bridge (external → Macula)
- Could provide both WAMP and NATS APIs to applications

**Possible Future Scenario:**
```
┌─────────────────────────────────┐
│ External Services               │
│ (Python, Go, Rust apps)         │
└────────────┬────────────────────┘
             │ NATS (optional)
             ↓
┌─────────────────────────────────┐
│ Macula Platform (Bondy)         │
│ - Rings as "one big computer"   │
│ - Distributed Erlang + Swarm    │
│ - WAMP for internal messaging   │
└─────────────────────────────────┘
```

**For now, Bondy is the foundation. NATS could be an integration option later, not a replacement.**

### References

- [Bondy Documentation](https://developer.bondy.io)
- [WAMP Protocol Specification](https://wamp-proto.org/)
- [Partisan - High-Performance Distributed Erlang](https://github.com/lasp-lang/partisan)
- [Swarm - Distributed Process Registry](https://github.com/bitwalker/swarm)
- [NATS Documentation](https://docs.nats.io/) - Excellent for cloud-native messaging, but different use case

---

## Key Insights

### "Modern" vs "Right"

> **NATS is "modern" for cloud-native microservices messaging.**
> **Bondy is "right" for distributed BEAM runtime platforms.**

NATS is an excellent technology - widely adopted, well-documented, operationally mature. But it solves a different problem than Macula needs to solve.

### Macula's Unique Value

Macula is not just a messaging platform - it's a **distributed runtime for BEAM applications**.

- **Without Distributed Erlang**: Macula is "just another message broker wrapper"
- **With Distributed Erlang**: Macula is a "platform for building distributed BEAM systems"

NATS is excellent for messaging but cannot provide the "one big computer" semantics that make Macula unique and valuable.

### The Right Tool for the Job

We initially thought NATS would be better because:
- It's more popular
- It has better tooling
- It's "the modern choice"

**We were wrong** - not because NATS is bad, but because we were solving the wrong problem.

Macula needs:
- ✅ Distributed Erlang clustering
- ✅ Global process coordination (Swarm)
- ✅ Cross-node supervision
- ✅ "One big computer" semantics

**Bondy provides all of this. NATS provides none of it.**

**The right choice became obvious once we clarified our requirements.**
