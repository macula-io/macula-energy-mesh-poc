defmodule CortexIqUtilities.Application do
  @moduledoc """
  Application supervisor for CortexIQ Utilities.

  Manages energy provider bot processes with different pricing strategies.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    providers_sources = get_env("PROVIDERS_SOURCES", "benelux_energy_providers.json")
    macula_url = get_env("MACULA_URL", "https://localhost:9443")
    realm = get_env("MACULA_REALM", "be.cortexiq.energy")

    # Load providers from JSON configuration (supports comma-separated list)
    providers = CortexIqUtilities.ConfigLoader.load_providers_from_sources(providers_sources)

    Logger.info("Starting #{length(providers)} provider bots from #{providers_sources}")

    children = [
      # Registry for provider bots
      {Registry, keys: :unique, name: CortexIqUtilities.Registry},

      # Singleton subscriber for simulation reset events
      {CortexIqUtilities.SubscribeSimulationReset.Subscriber, [macula_url: macula_url, realm: realm]},

      # Dynamic supervisor for provider bots
      {DynamicSupervisor, name: CortexIqUtilities.BotSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: CortexIqUtilities.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Start provider bots
        start_provider_bots(providers, macula_url, realm)
        {:ok, pid}

      error ->
        error
    end
  end

  defp start_provider_bots(providers, macula_url, realm) do
    Enum.each(providers, fn provider ->
      spec = {CortexIqUtilities.ProviderBot, [
        provider_id: provider.id,
        provider: provider,  # Pass full provider struct
        macula_url: macula_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqUtilities.BotSupervisor, spec) do
        {:ok, _pid} ->
          Logger.info("Started ProviderBot: #{provider.name} (#{provider.id})")

        {:error, reason} ->
          Logger.error("Failed to start ProviderBot #{provider.id}: #{inspect(reason)}")
      end
    end)
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end
end
