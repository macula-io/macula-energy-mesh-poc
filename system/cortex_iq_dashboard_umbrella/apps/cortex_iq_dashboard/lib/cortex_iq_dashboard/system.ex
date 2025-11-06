defmodule CortexIqDashboard.System do
  @moduledoc """
  Top-level supervisor for the CortexIqDashboard system.

  Manages the WAMP realm lifecycle (RealmManager) and event subscription (WampSubscriber).
  Handles OS signals for graceful shutdown with proper realm cleanup.
  """
  use Supervisor
  require Logger

  ## Client API

  def start_link(opts) when is_list(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Supervisor Callbacks

  @impl true
  def init(opts) do
    realm_uri = Keyword.fetch!(opts, :realm_uri)
    bondy_admin_url = Keyword.fetch!(opts, :bondy_admin_url)
    bondy_url = Keyword.fetch!(opts, :bondy_url)

    # Set up signal handlers for graceful shutdown
    setup_signal_handlers()

    # JIT Subscription Model: NO persistent WAMP connections
    # LiveViews manage their own WAMP clients (connect on mount, disconnect on unmount)
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end

  ## Private Functions

  defp setup_signal_handlers do
    # Handle SIGTERM and SIGQUIT for graceful shutdown
    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigquit, :handle)

    # Spawn a linked process to handle signals
    # This ensures it dies with the supervisor
    spawn_link(fn -> signal_handler_loop() end)
  end

  defp signal_handler_loop do
    receive do
      {:signal, :sigterm} ->
        Logger.warning("📡 SIGTERM received - initiating graceful shutdown")
        initiate_shutdown(:sigterm)

      {:signal, :sigquit} ->
        Logger.warning("📡 SIGQUIT received - initiating graceful shutdown")
        initiate_shutdown(:sigquit)

      msg ->
        Logger.warning("❓ Unknown signal received: #{inspect(msg)}")
    end

    # Continue listening
    signal_handler_loop()
  end

  defp initiate_shutdown(reason) do
    Logger.warning("=" <> String.duplicate("=", 60))
    Logger.warning("🛑 INITIATING GRACEFUL SHUTDOWN")
    Logger.warning("  Reason: #{inspect(reason)}")
    Logger.warning("=" <> String.duplicate("=", 60))

    # Stop the application gracefully - this will trigger supervisor shutdown
    # which will call terminate/2 on all supervised children (including RealmManager)
    Task.start(fn ->
      # Small delay to ensure log message is written
      Process.sleep(100)
      Logger.warning("Calling Application.stop(:cortex_iq_dashboard)...")
      result = Application.stop(:cortex_iq_dashboard)
      Logger.warning("Application.stop result: #{inspect(result)}")
    end)
  end

  @doc """
  Manually trigger graceful shutdown (useful for development/testing).
  Call this from IEx: CortexIqDashboard.System.shutdown()
  """
  def shutdown do
    Logger.warning("Manual shutdown triggered from IEx")
    initiate_shutdown(:manual)
  end
end
