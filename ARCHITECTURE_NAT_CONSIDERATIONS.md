# NAT Considerations for Energy PoC Architecture

**TL;DR**: ✅ Current hub-based architecture handles NAT naturally. No changes needed.

---

## Current Architecture: Hub-Spoke Model

### Deployment Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Hub Cluster (Public IP)                             │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Dashboard    │  │ Simulation   │  │ Projections  │        │
│  │ (HTTP/3 SDK) │  │ (HTTP/3 SDK) │  │ (HTTP/3 SDK) │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                 │
│  All apps connect peer-to-peer within cluster (no NAT)        │
└─────────────────────────────────────────────────────────────────┘
           ▲                    ▲                    ▲
           │                    │                    │
      HTTP/3 QUIC          HTTP/3 QUIC          HTTP/3 QUIC
      (Outbound)           (Outbound)           (Outbound)
           │                    │                    │
           │                    │                    │
┌──────────┴──────┐  ┌──────────┴──────┐  ┌──────────┴──────┐
│ Edge: Homes     │  │ Edge: Utilities │  │ Edge: Queries   │
│ (Behind NAT)    │  │ (Behind NAT)    │  │ (Behind NAT)    │
│                 │  │                 │  │                 │
│ 192.168.1.x     │  │ 10.0.0.x        │  │ 172.16.0.x      │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Why This Works

**All connections are OUTBOUND from edge to hub**:
1. ✅ NAT allows outbound UDP (QUIC uses UDP)
2. ✅ Hub has stable public IP/DNS endpoint
3. ✅ Edge apps initiate connections (client mode)
4. ✅ Hub accepts connections (server mode)
5. ✅ Bidirectional communication over single QUIC connection

**No peer-to-peer required**:
- Edge apps don't connect directly to each other
- All messages route through hub (message broker pattern)
- Hub acts as central exchange point

---

## NAT Behavior

### Outbound Connections (What We Use) ✅

**Scenario**: Edge app behind NAT → Hub with public IP

```
┌──────────────┐                    ┌──────────────┐
│ Edge App     │                    │ Hub Cluster  │
│ 192.168.1.10 │                    │ 1.2.3.4      │
└──────┬───────┘                    └──────┬───────┘
       │                                    │
       │ 1. QUIC CONNECT (UDP)             │
       │ Src: 192.168.1.10:random          │
       │ Dst: 1.2.3.4:9443                 │
       ├────────────────────────────────────>
       │                                    │
  ┌────▼─────┐                              │
  │   NAT    │  2. NAT Translation          │
  │ Router   │  Src: 5.6.7.8:54321          │
  └────┬─────┘  Dst: 1.2.3.4:9443          │
       ├────────────────────────────────────>
       │                                    │
       │ 3. QUIC CONNECTION ESTABLISHED    │
       <────────────────────────────────────┤
       │                                    │
       │ 4. Bidirectional messaging        │
       <────────────────────────────────────>
       │    over single QUIC connection    │
```

**Key Points**:
- NAT creates mapping: `192.168.1.10:random ↔ 5.6.7.8:54321`
- Mapping stays alive as long as QUIC connection alive
- QUIC keepalives maintain NAT mapping
- Hub can send messages back over same connection

### Inbound Connections (NOT Used) ❌

**Scenario**: Hub trying to connect TO edge app (not our pattern)

```
┌──────────────┐                    ┌──────────────┐
│ Hub Cluster  │                    │ Edge App     │
│ 1.2.3.4      │                    │ 192.168.1.10 │
└──────┬───────┘                    └──────┬───────┘
       │                                    │
       │ 1. QUIC CONNECT attempt           │
       │ Src: 1.2.3.4:9443                 │
       │ Dst: 5.6.7.8:54321 ❌             │
       ├────────────────────────────────────>
       │                              ┌─────▼─────┐
       │                              │   NAT     │
       │                              │  Router   │
       │                              └─────┬─────┘
       │                                    │
       │                              No mapping!  │
       │                              Packet dropped ❌
```

**Why it fails**:
- NAT has no mapping for unsolicited inbound UDP
- Edge app is unreachable from outside
- **We don't use this pattern**, so not a problem

---

## Protocol Advantages

### QUIC Multiplexing ✅

**Single connection, multiple streams**:

```erlang
%% One QUIC connection from edge to hub
{ok, Conn} = macula_quic:connect("hub.macula.io", 9443, [], 5000),

%% Open multiple independent streams over same connection
{ok, PubStream} = macula_quic:open_stream(Conn),   % For publishing
{ok, SubStream} = macula_quic:open_stream(Conn),   % For subscribing
{ok, RpcStream} = macula_quic:open_stream(Conn),   % For RPC

%% Each stream is independent
%% Packet loss on one stream doesn't block others (no head-of-line blocking)
```

**Benefits**:
1. ✅ One NAT mapping serves all streams
2. ✅ No head-of-line blocking (TCP problem solved)
3. ✅ Stream-level flow control
4. ✅ Lower latency than multiple TCP connections

### QUIC Connection Migration ✅

**Edge app changes networks** (e.g., laptop moves from WiFi to cellular):

```
Time 0: Edge app on WiFi
┌──────────────┐  QUIC Connection   ┌──────────────┐
│ Edge App     │  Connection ID: X  │ Hub Cluster  │
│ WiFi IP: A   ├────────────────────┤ 1.2.3.4      │
└──────────────┘                    └──────────────┘

Time 1: Network change detected
┌──────────────┐                    ┌──────────────┐
│ Edge App     │  Connection BROKEN │ Hub Cluster  │
│ Cell IP: B   │  ❌ (with TCP)     │ 1.2.3.4      │
└──────────────┘                    └──────────────┘

Time 2: QUIC reconnects automatically
┌──────────────┐  QUIC Connection   ┌──────────────┐
│ Edge App     │  Same Connection ID│ Hub Cluster  │
│ Cell IP: B   ├────────────────────┤ 1.2.3.4      │
└──────────────┘  No app disruption!└──────────────┘
```

**Benefits**:
- ✅ Transparent network changes
- ✅ No application-level reconnection needed
- ✅ Connection ID stays same
- ✅ Perfect for mobile edge devices

---

## Deployment Scenarios

### Scenario 1: All Apps in Kubernetes (Current PoC)

```
┌─────────────────────────────────────────┐
│ Kubernetes Cluster (kind-macula-hub)   │
│                                         │
│  Pod Network: 10.42.0.0/16             │
│                                         │
│  ┌──────────┐  ┌──────────┐  ┌───────┐│
│  │Dashboard │  │Simulation│  │ Homes ││
│  │10.42.0.2 │  │10.42.0.3 │  │10.42. ││
│  └─────┬────┘  └─────┬────┘  └───┬───┘│
│        │             │             │    │
│        └─────────────┼─────────────┘    │
│                      │                   │
│         HTTP/3 QUIC (direct, no NAT)   │
└─────────────────────────────────────────┘
```

**NAT Status**: ❌ No NAT (flat pod network)
**Result**: ✅ Everything works perfectly

### Scenario 2: Edge Apps Outside Cluster

```
┌─────────────────────────────────────────┐
│ Kubernetes Hub                          │
│                                         │
│  Service: macula-hub.example.com       │
│  Public IP: 203.0.113.10               │
│  Port: 9443 (QUIC/UDP)                 │
└─────────────┬───────────────────────────┘
              │
              │ Internet
              │
     ┌────────┼─────────┬────────────┐
     │        │         │            │
┌────▼────┐ ┌▼────────┐ ┌▼──────────▼┐
│Home     │ │Utility  │ │Dashboard  │
│NAT'd    │ │NAT'd    │ │Browser    │
│192.168. │ │10.0.0.  │ │(WebSocket)│
└─────────┘ └─────────┘ └───────────┘
```

**NAT Status**: ✅ Edge apps behind NAT
**Connection**: ✅ Outbound QUIC to hub
**Result**: ✅ Works perfectly

### Scenario 3: Multi-Cluster (Future)

```
┌─────────────────┐         ┌─────────────────┐
│ Hub Cluster 1   │         │ Hub Cluster 2   │
│ US-East         │◄───────►│ EU-West         │
│ Public IP: A    │  QUIC   │ Public IP: B    │
└────────┬────────┘ Peering └────────┬────────┘
         │                            │
    ┌────▼─────┐                 ┌────▼─────┐
    │ Edge     │                 │ Edge     │
    │ Apps     │                 │ Apps     │
    └──────────┘                 └──────────┘
```

**NAT Status**: ✅ Hub-to-hub direct (public IPs)
**Edge Connections**: ✅ Outbound to nearest hub
**Result**: ✅ Works perfectly

---

## Configuration

### Hub Configuration

```yaml
# Kubernetes Service (NodePort or LoadBalancer)
apiVersion: v1
kind: Service
metadata:
  name: macula-hub
spec:
  type: LoadBalancer  # or NodePort
  ports:
  - port: 9443
    protocol: UDP      # QUIC uses UDP
    name: quic
  selector:
    app: macula-gateway
```

### Edge App Configuration

```elixir
# config/runtime.exs
config :cortex_iq_homes,
  macula_url: System.get_env("MACULA_URL", "https://hub.macula.io:9443"),
  macula_realm: System.get_env("MACULA_REALM", "be.cortexiq.energy")
```

**DNS Resolution**:
- Hub: `hub.macula.io` → Public IP
- Edge: Doesn't need to be reachable
- Connection: Edge initiates to hub

---

## Firewall Considerations

### Hub Firewall Rules

```bash
# Allow inbound QUIC
iptables -A INPUT -p udp --dport 9443 -j ACCEPT

# Or via cloud provider security group
# AWS: Allow UDP 9443 from 0.0.0.0/0
# GCP: Allow UDP 9443 from any
```

### Edge Firewall Rules

```bash
# Only need outbound UDP (usually allowed by default)
# No inbound rules needed!

# If corporate firewall blocks UDP:
# - Use VPN
# - Or implement TCP fallback (future)
```

---

## Testing NAT Scenarios

### Test 1: Verify QUIC Connection Through NAT

```bash
# From edge device behind NAT
curl -v --http3 https://hub.macula.io:9443

# Should succeed if:
# - Hub has public IP
# - UDP port 9443 open
# - Outbound UDP allowed on edge
```

### Test 2: Verify Multiplexing

```bash
# Start edge app, monitor streams
# Should see multiple streams over one connection

netstat -anp | grep 9443
# Expected: Single UDP connection with multiple application streams
```

### Test 3: Connection Migration

```bash
# On laptop edge device:
# 1. Connect via WiFi
# 2. Disable WiFi
# 3. Enable cellular

# QUIC should migrate automatically
# App should not disconnect
```

---

## Summary

### ✅ What Works Today

| Feature | Status | Notes |
|---------|--------|-------|
| Outbound connections | ✅ Works | Edge → Hub |
| NAT traversal | ✅ Works | Outbound only |
| Multiplexing | ✅ Works | Multiple streams per connection |
| Connection migration | ✅ Works | Network changes handled |
| Bidirectional messaging | ✅ Works | Over established connection |

### ❌ What Doesn't Work (Not Needed)

| Feature | Status | Notes |
|---------|--------|-------|
| Inbound to NAT | ❌ Blocked | Not used in our architecture |
| Peer-to-peer | ❌ Blocked | Hub mediates all communication |
| Symmetric NAT direct | ❌ Blocked | Would need STUN/TURN |

### 🔮 Future Enhancements

See `NAT_TRAVERSAL_ROADMAP.md` for full details:
- Phase 1: Hub relay (already works!)
- Phase 2: STUN for direct P2P
- Phase 3: TURN for symmetric NAT
- Phase 4: ICE-like negotiation

---

## Conclusion

**Current architecture is NAT-friendly by design** ✅

No changes needed for PoC or initial production deployment.
NAT traversal enhancements are future optimizations for
true peer-to-peer mesh scenarios.
