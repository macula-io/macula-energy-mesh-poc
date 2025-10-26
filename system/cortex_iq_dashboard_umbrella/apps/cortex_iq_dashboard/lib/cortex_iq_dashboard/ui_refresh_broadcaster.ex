defmodule CortexIqDashboard.UiRefreshBroadcaster do
  @moduledoc """
  Simple broadcaster that tells LiveView to refresh every 2 seconds.

  NO event processing - just a timer that broadcasts.
  LiveView reads latest data from database when it receives the signal.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start interval timer (fires every 2 seconds)
    {:ok, timer_ref} = :timer.send_interval(2000, self(), :ui_refresh)
    Logger.info("UiRefreshBroadcaster: Started with 2-second interval, ref: #{inspect(timer_ref)}")

    {:ok, %{timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:ui_refresh, state) do
    Logger.info("UiRefreshBroadcaster: Timer fired, broadcasting UI refresh")

    # Broadcast to LiveView
    Phoenix.PubSub.broadcast(CortexIqDashboard.PubSub, "dashboard:updates", :refresh_data)

    {:noreply, state}
  end
end
