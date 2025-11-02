defmodule CortexIqUtilities.ConfigLoader do
  @moduledoc """
  Loads persistent energy provider configurations from JSON files.

  JSON files are stored in priv/providers/ and contain pre-configured
  Benelux energy providers with realistic pricing strategies and metadata.

  Example JSON structure:
  ```json
  [
    {
      "id": "019a5e70-0000-7000-8000-000000000001",
      "name": "Essent",
      "country": "NL",
      "regions": ["randstad", "north", "east", "south"],
      "strategy": "steady_eddie",
      "headquarters": "Den Bosch",
      "description": "Netherlands' largest energy provider...",
      "market_share_target": 0.25,
      "base_day_buy_price": 0.28,
      "base_night_buy_price": 0.22,
      "base_day_sell_price": 0.12,
      "base_night_sell_price": 0.08
    }
  ]
  ```
  """

  require Logger
  alias CortexIqCore.Provider

  @doc """
  Load providers from a JSON file in priv/providers/.

  Returns a list of Provider structs with configurations from the file.

  ## Examples

      iex> ConfigLoader.load_providers("benelux_energy_providers.json")
      [%Provider{id: "019a...", ...}, ...]
  """
  @spec load_providers(String.t()) :: [Provider.t()]
  def load_providers(filename) do
    priv_dir = :code.priv_dir(:cortex_iq_utilities)
    file_path = Path.join([priv_dir, "providers", filename])

    Logger.info("Loading providers from #{file_path}")

    case File.read(file_path) do
      {:ok, content} ->
        providers =
          content
          |> Jason.decode!()
          |> Enum.map(&parse_provider/1)

        Logger.info("✓ Loaded #{length(providers)} providers from #{filename}")
        providers

      {:error, reason} ->
        Logger.error("Failed to read #{file_path}: #{inspect(reason)}")
        raise "Could not load provider configurations from #{filename}"
    end
  end

  @doc """
  Load providers from multiple JSON files.

  Accepts a comma-separated list of filenames and returns a combined list
  of providers from all files.

  ## Examples

      iex> ConfigLoader.load_providers_from_sources("file1.json,file2.json")
      [%Provider{}, %Provider{}, ...]
  """
  @spec load_providers_from_sources(String.t()) :: [Provider.t()]
  def load_providers_from_sources(sources_string) when is_binary(sources_string) do
    sources_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&load_providers/1)
  end

  defp parse_provider(data) do
    # Get strategy-specific defaults
    strategy = String.to_atom(data["strategy"])
    base_provider = Provider.new(data["id"], data["name"], strategy)

    # Override with JSON data where provided
    %Provider{
      base_provider |
      country: data["country"],
      regions: data["regions"],
      headquarters: data["headquarters"],
      description: data["description"],
      market_share_target: data["market_share_target"],
      # Override base pricing if provided in JSON
      base_day_buy_price: data["base_day_buy_price"] || base_provider.base_day_buy_price,
      base_night_buy_price: data["base_night_buy_price"] || base_provider.base_night_buy_price,
      base_day_sell_price: data["base_day_sell_price"] || base_provider.base_day_sell_price,
      base_night_sell_price: data["base_night_sell_price"] || base_provider.base_night_sell_price
    }
  end
end
