defmodule CortexIqHomes.ConfigLoader do
  @moduledoc """
  Loads persistent home configurations from JSON files.

  JSON files are stored in priv/homes/ and contain pre-generated home
  configurations with UUID7 identifiers, realistic addresses across Belgium
  and Netherlands, and varied solar/battery capacities.

  Example JSON structure:
  ```json
  [
    {
      "id": "019a2400-0005-7000-a001-000000000001",
      "name": "Peeters Family",
      "iot_provider": "HomeWizard",
      "address": {
        "street": "Veldstraat 145",
        "city": "Gent",
        "postal_code": "9000",
        "region": "belgium_flanders",
        "latitude": 51.0543,
        "longitude": 3.7174
      },
      "solar_capacity_kw": 4.5,
      "battery_capacity_kwh": 11.5,
      "meters": {
        "electricity_day_ean": "541449123456789012",
        "electricity_night_ean": "541449987654321098",
        "gas_ean": "374606234567890123",
        "water_ean": "550778345678901234"
      }
    }
  ]
  ```

  Multi-meter support:
  - `electricity_day_ean`: Day tariff meter (6am-10pm)
  - `electricity_night_ean`: Night tariff meter (10pm-6am)
  - `gas_ean`: Gas meter (optional - ~70% of homes)
  - `water_ean`: Water meter (optional - ~80% of homes)

  All meter EANs use 18-digit European Article Number format with
  country-specific prefixes (Belgium: 541449/374606/550778,
  Netherlands: 871686/871687/871688).
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
    # Extract meters from data
    meters = Map.get(data, "meters", %{})

    %Home{
      id: data["id"],
      name: data["name"],
      iot_provider: data["iot_provider"],
      meter_ean: data["meter_ean"],  # Legacy field - kept for backward compatibility
      # Multi-meter EANs (18-digit European Article Numbers)
      electricity_day_meter_ean: Map.get(meters, "electricity_day_ean"),
      electricity_night_meter_ean: Map.get(meters, "electricity_night_ean"),
      gas_meter_ean: Map.get(meters, "gas_ean"),
      water_meter_ean: Map.get(meters, "water_ean"),
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
