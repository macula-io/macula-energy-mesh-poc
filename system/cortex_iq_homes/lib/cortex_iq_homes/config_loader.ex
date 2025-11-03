defmodule CortexIqHomes.ConfigLoader do
  @moduledoc """
  Loads persistent home configurations from JSON files.

  JSON files are stored in priv/homes/ and contain pre-generated home
  configurations with UUID7 identifiers, Flanders addresses, and varied
  solar/battery capacities.

  Example JSON structure:
  ```json
  [
    {
      "id": "019a23e0-8254-75aa-aa44-b30b6d08b76c",
      "name": "Segers Residence",
      "iot_provider": "HomeWizard",
      "meter_ean": "541234567890123456",
      "address": {
        "street": "Stationsstraat 245",
        "city": "Leuven",
        "postal_code": "3000",
        "region": "flanders",
        "latitude": 50.875,
        "longitude": 4.698
      },
      "solar_capacity_kw": 3.14,
      "battery_capacity_kwh": 14.14
    }
  ]
  ```
  """

  require Logger
  alias CortexIqCore.Home

  @doc """
  Load homes from a JSON file in priv/homes/.

  Returns a list of Home structs with configurations from the file.

  ## Examples

      iex> ConfigLoader.load_homes("flanders_test_homes.json")
      [%Home{id: "019a...", ...}, ...]
  """
  @spec load_homes(String.t()) :: [Home.t()]
  def load_homes(filename) do
    priv_dir = :code.priv_dir(:cortex_iq_homes) |> to_string()
    file_path = Path.join([priv_dir, "homes", filename])

    Logger.info("Loading homes from #{file_path}")

    case File.read(file_path) do
      {:ok, content} ->
        homes =
          content
          |> Jason.decode!()
          |> Enum.map(&parse_home/1)

        Logger.info("✓ Loaded #{length(homes)} homes from #{filename}")
        homes

      {:error, reason} ->
        Logger.error("Failed to read #{file_path}: #{inspect(reason)}")
        raise "Could not load home configurations from #{filename}"
    end
  end

  @doc """
  Load homes from multiple JSON files.

  Accepts a comma-separated list of filenames and returns a combined list
  of homes from all files.

  ## Examples

      iex> ConfigLoader.load_homes_from_sources("file1.json,file2.json")
      [%Home{}, %Home{}, ...]
  """
  @spec load_homes_from_sources(String.t()) :: [Home.t()]
  def load_homes_from_sources(sources_string) when is_binary(sources_string) do
    sources_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&load_homes/1)
  end

  defp parse_home(data) do
    %Home{
      id: data["id"],
      name: data["name"],
      iot_provider: data["iot_provider"],
      meter_ean: data["meter_ean"],
      location: %{
        street: data["address"]["street"],
        city: data["address"]["city"],
        postal_code: data["address"]["postal_code"],
        region: String.to_atom(data["address"]["region"]),
        latitude: data["address"]["latitude"],
        longitude: data["address"]["longitude"]
      },
      solar_capacity_kw: data["solar_capacity_kw"],
      battery_capacity_kwh: data["battery_capacity_kwh"],
      current_contract_id: nil
    }
  end
end
