# Decentralized RPC Service Discovery Research

**Created**: 2025-11-10
**Context**: Migrating CortexIQ from WAMP/Bondy to Macula HTTP/3
**Problem**: How can services advertise RPC capabilities in a decentralized mesh without centralized registration?

## The Problem

In the WAMP/Bondy architecture, services could register RPC procedures with the central router:
```elixir
# WAMP centralized approach (old)
:wamp_client.register(client, "energy.home.get", handler_fun)
```

The new Macula HTTP/3 architecture is **decentralized** - there is no central authority. The `macula_client` SDK has:
- ✅ `call/3` - Can invoke procedures on OTHER services
- ❌ NO `register/3` - Cannot expose procedures to the mesh

**Why?** A "Client" implementing "Register/Unregister" doesn't align with Macula's decentralization goals.

## Research: Decentralized Service Discovery Patterns

### 1. DHT-Based Service Advertisement (IPFS "Providers" Pattern)

**How it works:**
- Each service type has a unique **service identifier** (like a content hash)
- Services advertise: "I provide service X" by publishing their node ID to the DHT at key `hash(service_id)`
- Clients discover: "Who provides service X?" by querying DHT for key `hash(service_id)`
- DHT returns list of nodes providing that service

**IPFS Implementation:**
```
Service Registration:
  service_id = "energy.home.get"
  key = hash(service_id)
  DHT.put(key, my_node_id)

Service Discovery:
  service_id = "energy.home.get"
  key = hash(service_id)
  providers = DHT.get(key)  // Returns [node_id_1, node_id_2, ...]
  pick provider and send RPC call
```

**Advantages:**
- ✅ Fully decentralized - no central registry
- ✅ Multiple providers supported (returns list)
- ✅ Load balancing possible (client picks from list)
- ✅ Fault tolerant (if one provider fails, try another)
- ✅ Leverages existing DHT infrastructure

**Disadvantages:**
- ⚠️ DHT lookup latency before each call
- ⚠️ Stale entries if providers go offline (requires TTL and re-advertisement)
- ⚠️ DHT overhead for each service type

**Macula Integration:**
Macula already has a Kademlia DHT in `macula_topology`. Could extend with:
```erlang
% In macula_client.erl
advertise_service(Client, ServiceId) ->
    Key = hash(ServiceId),
    macula_dht:put(Key, node_id(Client)).

discover_service(Client, ServiceId) ->
    Key = hash(ServiceId),
    macula_dht:get(Key).  % Returns list of provider node IDs
```

---

### 2. Gossip-Based Service Advertisement

**How it works:**
- Each node maintains a **local service registry** (what services I provide)
- Periodically, nodes exchange service lists with random neighbors
- Over time, service information spreads "epidemically" through the network
- Each node builds a **view of all services** in the mesh

**Gossip Protocol:**
```
Every N seconds:
  1. Pick 3-5 random neighbors
  2. Send them my service list + my cached view of other services
  3. Receive their service lists
  4. Merge into my local view (with timestamps)
  5. Prune stale entries (> timeout)

On RPC Call:
  1. Look up service in local view
  2. Pick provider from list
  3. Send RPC call directly
```

**Advantages:**
- ✅ Fully decentralized
- ✅ Eventually consistent service view
- ✅ Low latency lookups (local cache)
- ✅ Fault tolerant (gossip continues if nodes fail)
- ✅ Scales well (each node only talks to few neighbors)

**Disadvantages:**
- ⚠️ Eventual consistency (takes time to propagate)
- ⚠️ Constant network chatter (gossip overhead)
- ⚠️ Memory overhead (each node caches full service view)
- ⚠️ Stale entries possible during network partitions

**Real-world examples:**
- Consul - Service mesh using gossip for membership
- Cassandra - Uses gossip for cluster state
- SWIM protocol - Scalable membership management

**Macula Integration:**
Could implement as `macula_gossip` module:
```erlang
% macula_gossip.erl
-export([advertise_service/2, discover_service/1]).

advertise_service(ServiceId, HandlerPid) ->
    gen_server:call(?MODULE, {advertise, ServiceId, HandlerPid}).

discover_service(ServiceId) ->
    gen_server:call(?MODULE, {discover, ServiceId}).  % Returns cached list

% Periodic gossip
handle_info(gossip_tick, State) ->
    Peers = select_random_peers(3),
    lists:foreach(fun(Peer) ->
        send_service_list(Peer, State#state.my_services),
        receive_service_list(Peer)
    end, Peers).
```

---

### 3. Rendezvous Hashing for Service Placement

**How it works:**
- **Deterministic** algorithm to map service IDs to nodes
- All nodes run the same algorithm
- Given `service_id` and `list_of_nodes`, algorithm always picks the same node
- No communication needed - pure computation

**Algorithm:**
```erlang
find_service_provider(ServiceId, AllNodes) ->
    % Each node gets a "score" for this service
    Scored = lists:map(fun(Node) ->
        Score = hash(ServiceId ++ Node),
        {Score, Node}
    end, AllNodes),

    % Pick node with highest score
    {_Score, BestNode} = lists:max(Scored),
    BestNode.
```

**Advantages:**
- ✅ Zero latency lookups (pure computation)
- ✅ Zero network overhead (deterministic)
- ✅ Consistent across all nodes (same input = same output)
- ✅ Simple to implement

**Disadvantages:**
- ❌ Requires global view of all nodes (membership protocol needed)
- ❌ Single provider per service (no redundancy)
- ❌ Not flexible (can't have multiple providers for load balancing)

**Use case:** Better for **data sharding** than service discovery. Works when you need exactly one owner per key.

**Macula Integration:**
Could use for deterministic service placement combined with gossip for membership:
```erlang
% All nodes know each other via gossip membership
AllNodes = macula_membership:get_all_nodes(),

% Deterministic lookup - no communication
Provider = rendezvous_hash(ServiceId, AllNodes),

% Call the provider directly
macula_client:call(Provider, ServiceId, Args).
```

---

### 4. Service Announcement via Pub/Sub Topics

**How it works:**
- Services announce availability by publishing to well-known topics
- Clients subscribe to announcement topics and cache available services
- Heartbeat messages keep service list fresh

**Example:**
```erlang
% Service announces itself
:macula_client.publish(client,
    "service.announce.energy.home.get",
    %{node_id: my_node_id, capabilities: [...]})

% Client subscribes to announcements
:macula_client.subscribe(client,
    "service.announce.energy.home.get",
    fn announcement ->
        cache_service(announcement.node_id)
    end)

% Periodic heartbeat
:macula_client.publish(client,
    "service.heartbeat.energy.home.get",
    %{node_id: my_node_id, timestamp: now()})
```

**Advantages:**
- ✅ Uses existing pub/sub infrastructure
- ✅ Real-time updates (immediate notification of new services)
- ✅ Natural fit for event-driven architecture
- ✅ Multiple providers supported

**Disadvantages:**
- ⚠️ Topic explosion (one topic per service type)
- ⚠️ Constant heartbeat traffic
- ⚠️ Late joiners miss initial announcements (needs replay or query)

---

## Recommended Solution for Macula

### Hybrid Approach: **DHT-Based Service Advertisement + Local Cache**

**Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│ Service Provider Node                                   │
│                                                         │
│  Application advertises service:                       │
│    macula_client:advertise("energy.home.get", handler) │
│                                                         │
│  ↓ Publishes to Macula DHT:                           │
│    Key = hash("energy.home.get")                       │
│    Value = {node_id, endpoint, metadata, ttl}         │
│                                                         │
│  ↓ Periodic re-advertisement (TTL renewal)            │
│    Every 60 seconds                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Service Consumer Node                                   │
│                                                         │
│  Application calls RPC:                                │
│    macula_client:call("energy.home.get", args)         │
│                                                         │
│  ↓ Check local cache first                             │
│    If cached → Call directly                           │
│                                                         │
│  ↓ If not cached → Query DHT                           │
│    Key = hash("energy.home.get")                       │
│    Providers = DHT.get(Key)  % Returns list            │
│                                                         │
│  ↓ Pick provider (round-robin, random, etc.)          │
│    Cache result locally (TTL)                          │
│                                                         │
│  ↓ Send RPC call to provider                           │
│    HTTP/3 QUIC → MSG_CALL                              │
└─────────────────────────────────────────────────────────┘
```

**Implementation Plan:**

1. **Extend `macula_client.erl` with service advertisement:**
```erlang
%% @doc Advertise that this client provides a service (RPC procedure)
-spec advertise(pid(), binary(), handler_fn(), map()) -> {ok, reference()} | {error, term()}.
advertise(Client, ServiceId, HandlerFn, Opts) ->
    gen_server:call(Client, {advertise_service, ServiceId, HandlerFn, Opts}).

%% Internal: Publish to DHT
handle_call({advertise_service, ServiceId, HandlerFn, Opts}, _from, State) ->
    Key = crypto:hash(sha256, ServiceId),
    Value = #{
        node_id => State#state.node_id,
        service_id => ServiceId,
        handler => HandlerFn,
        metadata => maps:get(metadata, Opts, #{}),
        ttl => maps:get(ttl, Opts, 300),  % 5 minutes default
        timestamp => erlang:system_time(second)
    },

    % Publish to DHT
    case macula_dht:put(Key, Value) of
        ok ->
            % Store locally to handle incoming calls
            NewState = register_local_handler(ServiceId, HandlerFn, State),

            % Schedule re-advertisement (TTL renewal)
            Ref = schedule_readvertise(ServiceId, Value#{ ttl}),

            {reply, {ok, Ref}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end.
```

2. **Extend `macula_client.erl` to discover services:**
```erlang
%% @doc Call a service by ID (discovers provider via DHT)
-spec call(pid(), binary(), map()) -> {ok, term()} | {error, term()}.
call(Client, ServiceId, Args) ->
    call(Client, ServiceId, Args, #{}).

-spec call(pid(), binary(), map(), map()) -> {ok, term()} | {error, term()}.
call(Client, ServiceId, Args, Opts) ->
    gen_server:call(Client, {call_service, ServiceId, Args, Opts}, 30000).

handle_call({call_service, ServiceId, Args, Opts}, _from, State) ->
    case find_service_provider(ServiceId, State) of
        {ok, Provider} ->
            % Make RPC call to provider
            Result = macula_rpc:call(Provider, ServiceId, Args, Opts),
            {reply, Result, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end.

%% Internal: Find provider via cache or DHT
find_service_provider(ServiceId, State) ->
    % 1. Check local cache first
    case cache_lookup(ServiceId, State) of
        {ok, Provider} ->
            {ok, Provider};

        % 2. Query DHT
        not_found ->
            Key = crypto:hash(sha256, ServiceId),
            case macula_dht:get(Key) of
                {ok, Providers} when is_list(Providers) ->
                    % Pick one (round-robin, random, etc.)
                    Provider = pick_provider(Providers),

                    % Cache for future calls
                    cache_store(ServiceId, Provider, State),

                    {ok, Provider};

                {ok, []} ->
                    {error, no_providers};

                {error, Reason} ->
                    {error, Reason}
            end
    end.
```

3. **Add incoming RPC handler to `macula_connection.erl`:**
```erlang
%% Handle incoming MSG_CALL for advertised services
handle_message(?MSG_CALL, Data, State) ->
    #{
        <<"service_id">> := ServiceId,
        <<"args">> := Args,
        <<"call_id">> := CallId
    } = Data,

    % Look up local handler
    case macula_client:get_local_handler(ServiceId) of
        {ok, HandlerFn} ->
            % Execute handler
            Result = HandlerFn(Args),

            % Send reply
            Reply = #{
                <<"call_id">> => CallId,
                <<"result">> => Result
            },
            send_message(?MSG_REPLY, Reply, State);

        not_found ->
            % Service not found
            Error = #{
                <<"call_id">> => CallId,
                <<"error">> => <<"service_not_found">>
            },
            send_message(?MSG_ERROR, Error, State)
    end.
```

**Advantages of this approach:**
- ✅ Fully decentralized (uses existing Macula DHT)
- ✅ Multiple providers supported (DHT returns list)
- ✅ Low latency after first lookup (local cache)
- ✅ Fault tolerant (try another provider if one fails)
- ✅ No protocol changes needed (uses existing HTTP/3 transport)
- ✅ Minimal overhead (only DHT queries + periodic re-advertisement)

**Migration path for CortexIQ:**
```elixir
# Before (WAMP):
:wamp_client.register(client, "energy.home.get", handler)

# After (Macula with DHT service discovery):
:macula_client.advertise(client, "energy.home.get", handler, %{ttl: 300})
```

---

## Alternative: mDNS for Local Service Discovery

For **local mesh networks** (same LAN/subnet), mDNS offers simpler discovery:

**How it works:**
- Services announce themselves via multicast DNS
- No DHT needed - pure local broadcast
- Zero configuration

**Macula already has mDNS** (shortishly/mdns in _checkouts):
```erlang
% Advertise service
mdns:advertise("_energy-home-get._tcp", #{port => 9443, metadata => [...]}).

% Discover services
Services = mdns:discover("_energy-home-get._tcp").
```

**Use case:** Edge devices on same network (homes, sensors, local mesh)

**Limitation:** Doesn't work across WAN (internet). DHT approach works globally.

---

## Conclusion

**Recommended Implementation:**

1. **DHT-based service advertisement** (primary mechanism)
   - Global service discovery across the internet
   - Uses existing `macula_topology` DHT infrastructure
   - Supports multiple providers, load balancing, fault tolerance

2. **mDNS for local networks** (optimization)
   - Fast local discovery without DHT overhead
   - Perfect for edge devices on same LAN
   - Fallback to DHT if mDNS fails

3. **Local caching** (performance)
   - Cache DHT lookups locally with TTL
   - Reduces DHT query overhead
   - Faster subsequent calls

**This aligns with Macula's decentralization goals** - no central authority, services advertise themselves, clients discover via distributed protocols.

**Next Steps:**
1. Implement `macula_client:advertise/3` and `macula_client:discover/1`
2. Extend `macula_dht` to support service advertisement (if needed)
3. Add incoming `MSG_CALL` handler to `macula_connection`
4. Update CortexIQ applications to use new API
5. Test service discovery across multiple nodes
