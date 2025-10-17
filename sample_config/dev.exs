# Configure Poll Master Demo
config :poll_master, :ex_esdb,
  data_dir: "data/poll_master",
  store_id: :poll_master,
  timeout: 10_000,
  db_type: :single,
  pub_sub: :poll_master_pubsub,
  store_description: "Poll Master Event Store",
  store_tags: ["poll_master", "demo", "event-sourcing", "development"]

config :poll_master, PollMaster.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    store_id: :poll_master,
    stream_prefix: "poll_master_",
    serializer: Jason,
    event_type_mapper: PollMaster.EventTypeMapper
  ],
  # pubsub: [
  #   phoenix_pubsub: [
  #     name: PollMaster.PubSub
  #   ]
  # ],
  snapshotting: %{
    PollMaster.History => [
      snapshot_every: 1,
      snapshot_version: 1
    ]
  },
  subscribe_to_all_streams?: false

# Override libcluster configuration for single-node development
# Since this is running as an umbrella app on a single node,
# we disable clustering to avoid connection attempts to non-existent nodes
config :libcluster,
  topologies: []

# Alternative: If you want clustering in development, use Gossip strategy
# config :libcluster,
#   topologies: [
#     domain_cluster: [
#       strategy: Cluster.Strategy.Gossip,
#       config: [
#         port: 45_890,
#         if_addr: "127.0.0.1",
#         multicast_addr: "230.1.1.251",
#         multicast_ttl: 1,
#         secret: "domain_cluster_dev_secret"
#       ]
#     ]
#   ]

# Configure EmitterPool settings for development
config :ex_esdb, :emitter_pools,
  pool_size: 2,
  max_overflow: 4,
  eager_start: true

# Suppress OS monitoring warnings
config :os_mon,
  start_cpu_sup: false,
  start_disksup: false,
  start_memsup: false

# Ensure data directories exist
# Configure logger to reduce noise from distributed systems components
config :logger,
  compile_time_purge_matching: [
    # Swarm modules - only show errors
    [module: Swarm.Distribution.Ring, level_lower_than: :error],
    [module: Swarm.Distribution.Strategy, level_lower_than: :error],
    [module: Swarm.Registry, level_lower_than: :error],
    [module: Swarm.Tracker, level_lower_than: :error],
    [module: Swarm.Distribution.StaticQuorumRing, level_lower_than: :error],
    [module: Swarm.Distribution.Handler, level_lower_than: :error],
    [module: Swarm.IntervalTreeClock, level_lower_than: :error],
    [module: Swarm.Logger, level_lower_than: :error],
    [module: Swarm, level_lower_than: :error],
    # Ra and Khepri modules - reduce noise
    [module: :ra_server, level_lower_than: :error],
    [module: :ra_log, level_lower_than: :error],
    [module: :khepri, level_lower_than: :warning],
    [module: :khepri_cluster, level_lower_than: :warning]
  ]
