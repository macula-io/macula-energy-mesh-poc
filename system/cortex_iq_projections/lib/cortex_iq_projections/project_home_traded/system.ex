defmodule CortexIqProjections.ProjectHomeTraded.System do
  @moduledoc """
  Supervises the complete vertical slice for projecting home.traded events.

  Projects home.traded events (energy buy/sell transactions)

  ## Architecture

  WAMP Client → Subscriber → GenServer Projector → Database

  ## Strategy

  Uses `:rest_for_one` strategy for cascading restart behavior.
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
    client_name = :wamp_project_home_traded

    Logger.info("ProjectHomeTraded.System starting")
    Logger.info("  WAMP client: #{inspect(client_name)}")

    children = [
      # 1. WAMP Client
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

      # 2. Subscriber
      {CortexIqProjections.ProjectHomeTraded.Subscriber, [
        client: client_name
      ]},

      # 3. GenServer Projector
      {CortexIqProjections.ProjectHomeTraded.Projector, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
