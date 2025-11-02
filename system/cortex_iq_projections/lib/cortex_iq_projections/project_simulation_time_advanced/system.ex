defmodule CortexIqProjections.ProjectSimulationTimeAdvanced.System do
  @moduledoc """
  Supervises the complete vertical slice for projecting simulation.time_advanced events.

  This system manages:
  - One dedicated WAMP client (for subscribing to simulation.time_advanced events)
  - One subscriber (receives events from WAMP)
  - One GenServer projector (simple writes to database - low volume)

  ## Architecture

  WAMP Client → Subscriber → GenServer Projector → Database

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - GenServer projector starts third, receiving events from subscriber
  - If WAMP client crashes, all restart
  - If subscriber crashes, only subscriber and projector restart
  - If projector crashes, only projector restarts

  ## Why GenServer (not Broadway)?

  simulation.time_advanced is LOW-VOLUME (1 event/sec).
  Simple GenServer projector is sufficient - no need for batching overhead.
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    bondy_url = Keyword.get(opts, :bondy_url, System.get_env("BONDY_URL", "ws://localhost:18080/ws"))
    realm_uri = Keyword.get(opts, :realm_uri, System.get_env("BONDY_REALM", "be.cortexiq.energy"))

    # Unique WAMP client name for this event type
    wamp_client_name = :wamp_project_simulation_time_advanced

    Logger.info("ProjectSimulationTimeAdvanced.System starting")
    Logger.info("  WAMP client: #{inspect(wamp_client_name)}")

    children = [
      # 1. WAMP Client
      %{
        id: wamp_client_name,
        start: {MaculaSdk.Wamp, :start_link, [[
          url: bondy_url,
          realm: realm_uri,
          name: wamp_client_name
        ]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      },

      # 2. Subscriber
      {CortexIqProjections.ProjectSimulationTimeAdvanced.Subscriber, [
        wamp_client: wamp_client_name
      ]},

      # 3. GenServer Projector
      {CortexIqProjections.ProjectSimulationTimeAdvanced.Projector, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
