defmodule CortexIqProjections.ProjectHomeMeasured.System do
  @moduledoc """
  Supervises the complete vertical slice for projecting home_measured events.

  This system manages:
  - One dedicated WAMP client (for subscribing to home.measured events)
  - One subscriber (receives events from WAMP)
  - One Broadway projector (batches events and writes to database)

  ## Architecture

  WAMP Client → Subscriber → Broadway Projector → Database

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - Broadway projector starts third, receiving events from subscriber
  - If WAMP client crashes, all restart
  - If subscriber crashes, only subscriber and projector restart
  - If projector crashes, only projector restarts

  ## Why Broadway?

  home_measured is HIGH-VOLUME (500 homes * every 100ms = 5000 events/sec).
  Broadway provides:
  - Back-pressure management
  - Batch database writes (50 events per batch)
  - Concurrency control
  - Automatic demand management
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    macula_url = Keyword.get(opts, :macula_url, System.get_env("MACULA_URL", "https://localhost:9443"))
    realm_uri = Keyword.get(opts, :realm_uri, System.get_env("MACULA_REALM", "be.cortexiq.energy"))

    # Unique WAMP client name for this event type
    client_name = :wamp_project_home_measured

    Logger.info("ProjectHomeMeasured.System starting")
    Logger.info("  WAMP client: #{inspect(client_name)}")
    Logger.info("  Bondy URL: #{macula_url}")
    Logger.info("  Realm: #{realm_uri}")

    children = [
      # 1. WAMP Client - dedicated connection for this event type
      %{
        id: client_name,
        start: {MaculaSdk.Wamp, :start_link, [[
          url: macula_url,
          realm: realm_uri,
          name: client_name
        ]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      },

      # 2. Subscriber - subscribes to be.cortexiq.home.measured and forwards to projector
      {CortexIqProjections.ProjectHomeMeasured.Subscriber, [
        client: client_name
      ]},

      # 3. Broadway Projector - batches and projects to database
      {CortexIqProjections.ProjectHomeMeasured.Projector, []}
    ]

    # rest_for_one: cascading restarts from top to bottom
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
