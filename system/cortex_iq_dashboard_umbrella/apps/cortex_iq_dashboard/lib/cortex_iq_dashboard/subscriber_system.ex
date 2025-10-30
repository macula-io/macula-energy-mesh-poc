defmodule CortexIqDashboard.SubscriberSystem do
  @moduledoc """
  Supervises a WAMP client and its associated event subscriber.

  Each subscriber system manages:
  - One dedicated WAMP client with unique name
  - One event subscriber

  This ensures:
  - Proper supervision (if client crashes, subscriber restarts)
  - Unique WAMP client naming (no conflicts)
  - Cohesion (each event type has its complete system grouped)

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - If client crashes, subscriber also restarts
  - If subscriber crashes, client remains running

  ## Example

      {CortexIqDashboard.SubscriberSystem, [
        event_type: :home_initialized,
        subscriber_module: CortexIqDashboard.EventSubscribers.HomeInitializedSubscriber,
        bondy_url: "ws://bondy:18080/ws",
        realm_uri: "be.cortexiq.energy"
      ]}
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    event_type = Keyword.fetch!(opts, :event_type)
    name = Module.concat(__MODULE__, event_type)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    event_type = Keyword.fetch!(opts, :event_type)
    subscriber_module = Keyword.fetch!(opts, :subscriber_module)
    bondy_url = Keyword.fetch!(opts, :bondy_url)
    realm_uri = Keyword.fetch!(opts, :realm_uri)

    # Generate unique WAMP client name based on event type
    wamp_client_name = :"wamp_#{event_type}"

    Logger.info("SubscriberSystem starting for event: #{event_type}")
    Logger.info("  WAMP client name: #{inspect(wamp_client_name)}")
    Logger.info("  Subscriber module: #{inspect(subscriber_module)}")

    children = [
      # Start WAMP client first with unique name
      {MaculaSdk.Wamp, [
        url: bondy_url,
        realm: realm_uri,
        name: wamp_client_name
      ]},
      # Then start subscriber, passing it the WAMP client name
      {subscriber_module, [
        wamp_client: wamp_client_name
      ]}
    ]

    # rest_for_one: if WAMP client crashes, restart subscriber too
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
