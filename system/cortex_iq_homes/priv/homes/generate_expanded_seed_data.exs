#!/usr/bin/env elixir

# Expanded Seed Data Generator for CortexIQ Homes
# Generates 3000 homes with realistic multi-meter data for Belgium and Netherlands
# Splits into multiple files per region for multi-replica deployment
#
# Usage: elixir generate_expanded_seed_data.exs

defmodule ExpandedSeedDataGenerator do
  @moduledoc """
  Generates realistic seed data for 3000 homes across Belgium and Netherlands.
  Splits into sub-regional files for distribution across Kubernetes replicas.

  Features:
  - Multiple meter EANs per home (electricity day/night, gas, water)
  - Realistic city distribution
  - Accurate coordinates for each city
  - Belgian and Dutch family names
  - Realistic solar/battery capacities
  - Sub-regional files for load balancing
  """

  # Belgian cities with coordinates (Flanders)
  @flanders_west_cities [
    {"Gent", "9000", 51.0543, 3.7174},
    {"Brugge", "8000", 51.2093, 3.2247},
    {"Kortrijk", "8500", 50.8280, 3.2647},
    {"Oostende", "8400", 51.2189, 2.9312},
    {"Roeselare", "8800", 50.9467, 3.1246}
  ]

  @flanders_central_cities [
    {"Antwerpen", "2000", 51.2194, 4.4025},
    {"Mechelen", "2800", 51.0259, 4.4777},
    {"Leuven", "3000", 50.8798, 4.7005},
    {"Aalst", "9300", 50.9381, 4.0414},
    {"Sint-Niklaas", "9100", 51.1656, 4.1431}
  ]

  @flanders_east_cities [
    {"Hasselt", "3500", 50.9307, 5.3378},
    {"Genk", "3600", 50.9658, 5.5015},
    {"Turnhout", "2300", 51.3227, 4.9447},
    {"Mol", "2400", 51.1918, 5.1149},
    {"Tongeren", "3700", 50.7807, 5.4650}
  ]

  # Belgian cities (Brussels)
  @brussels_cities [
    {"Bruxelles", "1000", 50.8503, 4.3517},
    {"Etterbeek", "1040", 50.8325, 4.3889},
    {"Ixelles", "1050", 50.8343, 4.3661},
    {"Jette", "1090", 50.8794, 4.3276},
    {"Uccle", "1180", 50.7989, 4.3258},
    {"Schaerbeek", "1030", 50.8678, 4.3733}
  ]

  # Belgian cities (Wallonia)
  @wallonia_north_cities [
    {"Charleroi", "6000", 50.4108, 4.4446},
    {"Mons", "7000", 50.4542, 3.9564},
    {"La Louvière", "7100", 50.4754, 4.1877},
    {"Tournai", "7500", 50.6060, 3.3883},
    {"Mouscron", "7700", 50.7451, 3.2062}
  ]

  @wallonia_south_cities [
    {"Liège", "4000", 50.6326, 5.5797},
    {"Namur", "5000", 50.4674, 4.8720},
    {"Verviers", "4800", 50.5893, 5.8629},
    {"Seraing", "4100", 50.5862, 5.4998},
    {"Arlon", "6700", 49.6856, 5.8175}
  ]

  # Dutch cities (regions)
  @netherlands_west_cities [
    {"Den Haag", "2500", 52.0705, 4.3007},
    {"Rotterdam", "3000", 51.9225, 4.4792},
    {"Leiden", "2300", 52.1601, 4.4970},
    {"Delft", "2600", 52.0116, 4.3571},
    {"Dordrecht", "3300", 51.8133, 4.6901}
  ]

  @netherlands_north_cities [
    {"Amsterdam", "1000", 52.3676, 4.9041},
    {"Haarlem", "2000", 52.3874, 4.6462},
    {"Zaanstad", "1500", 52.4388, 4.8260},
    {"Groningen", "9700", 53.2194, 6.5665},
    {"Leeuwarden", "8900", 53.2012, 5.7999},
    {"Alkmaar", "1800", 52.6318, 4.7518}
  ]

  @netherlands_central_cities [
    {"Utrecht", "3500", 52.0907, 5.1214},
    {"Almere", "1300", 52.3508, 5.2647},
    {"Amersfoort", "3800", 52.1561, 5.3878},
    {"Apeldoorn", "7300", 52.2112, 5.9699},
    {"Nijmegen", "6500", 51.8426, 5.8539},
    {"Arnhem", "6800", 51.9851, 5.8987}
  ]

  @netherlands_south_cities [
    {"Eindhoven", "5600", 51.4416, 5.4697},
    {"Tilburg", "5000", 51.5556, 5.0919},
    {"Breda", "4800", 51.5878, 4.7755},
    {"'s-Hertogenbosch", "5200", 51.6881, 5.3032},
    {"Maastricht", "6200", 50.8514, 5.6910},
    {"Venlo", "5900", 51.3704, 6.1724}
  ]

  @netherlands_east_cities [
    {"Enschede", "7500", 52.2215, 6.8937},
    {"Zwolle", "8000", 52.5125, 6.0944},
    {"Deventer", "7400", 52.2551, 6.1639},
    {"Almelo", "7600", 52.3567, 6.6625},
    {"Hengelo", "7550", 52.2657, 6.7935}
  ]

  # Regional groupings
  @regions %{
    "belgium_flanders_west" => @flanders_west_cities,
    "belgium_flanders_central" => @flanders_central_cities,
    "belgium_flanders_east" => @flanders_east_cities,
    "belgium_brussels" => @brussels_cities,
    "belgium_wallonia_north" => @wallonia_north_cities,
    "belgium_wallonia_south" => @wallonia_south_cities,
    "netherlands_west" => @netherlands_west_cities,
    "netherlands_north" => @netherlands_north_cities,
    "netherlands_central" => @netherlands_central_cities,
    "netherlands_south" => @netherlands_south_cities,
    "netherlands_east" => @netherlands_east_cities
  }

  # Belgian family names
  @belgian_names ~w(
    Peeters Janssens Maes Jacobs Willems Goossens Wouters Claes Mertens
    Simon Laurent Dubois Lambert Fontaine Rousseau Vincent Gerard Dupont
    Vermeulen Smet Desmet Devos Baert Bogaert Coppens Hendrickx Van_den_Berg
    Martens Hermans Claessens Aerts Vandenberghe Dewilde Verhoeven Michiels
    Vanderhaeghen Matthijs De_Cock De_Pauw Lemmens Stevens Evers Govaerts
    Vandamme Moens Lejeune Renard Thomas Petit Michel Robert Durand
  )

  # Dutch family names
  @dutch_names ~w(
    De_Jong Jansen Bakker Visser Smit Meijer De_Boer Mulder De_Groot Bos
    Vos Peters Hendriks Van_Dijk Van_den_Berg Van_Leeuwen Dekker Brouwer
    De_Wit Koning Van_der_Meer De_Vries Kok Jacobs De_Haan Van_der_Linden
    Vermeulen Schouten Van_der_Veen Hoek Kuiper Kuijpers Timmermans Groen
    Gerritsen Jonker Van_Dam Prins De_Ruiter Wolters Scholten Bosch Spruit
    Van_de_Ven Berg Willems Hermans Driessen Maas Verhoeven De_Vos
  )

  # IoT providers
  @iot_providers ~w(HomeWizard Smappee SolarEdge Enphase Tesla_Powerwall Huawei_FusionSolar SMA_Sunny_Portal)

  def generate_all_homes(count \\ 3000) do
    IO.puts("Generating #{count} homes with realistic multi-meter data...")

    # Calculate homes per region (distribute evenly)
    regions = Map.keys(@regions)
    homes_per_region = div(count, length(regions))

    homes =
      regions
      |> Enum.with_index()
      |> Enum.flat_map(fn {region, region_idx} ->
        start_idx = region_idx * homes_per_region + 1
        end_idx = start_idx + homes_per_region - 1

        Enum.map(start_idx..end_idx, fn index ->
          generate_home(index, region)
        end)
      end)

    IO.puts("✓ Generated #{length(homes)} homes")
    homes
  end

  def generate_home(index, region) do
    # Get cities for this region
    cities = Map.fetch!(@regions, region)
    {city, postal_code, lat, lon} = Enum.random(cities)

    # Determine if Belgian or Dutch
    is_belgian = String.starts_with?(region, "belgium_")

    # Choose appropriate name
    family_name = if is_belgian, do: Enum.random(@belgian_names), else: Enum.random(@dutch_names)
    street = "#{Enum.random(["Straat", "Laan", "Weg", "Plein"])} #{Enum.random(1..200)}"

    # Add slight coordinate variation (+/- 0.01 degrees = ~1km)
    lat_offset = (:rand.uniform() - 0.5) * 0.02
    lon_offset = (:rand.uniform() - 0.5) * 0.02

    # Generate meter EANs
    electricity_day_ean = generate_electricity_ean(is_belgian)
    electricity_night_ean = generate_electricity_ean(is_belgian)

    # 70% chance of gas meter
    gas_ean = if :rand.uniform() < 0.7, do: generate_gas_ean(is_belgian), else: nil

    # 80% chance of water meter
    water_ean = if :rand.uniform() < 0.8, do: generate_water_ean(is_belgian), else: nil

    # Realistic solar and battery capacities
    solar_kw = :rand.uniform() * 3.0 + 2.5  # 2.5 - 5.5 kW
    battery_kwh = :rand.uniform() * 6.0 + 8.0  # 8.0 - 14.0 kWh

    home = %{
      "id" => generate_home_id(index),
      "name" => "#{String.replace(family_name, "_", " ")} Family",
      "iot_provider" => Enum.random(@iot_providers),
      "address" => %{
        "city" => city,
        "postal_code" => postal_code,
        "street" => street,
        "region" => region,
        "latitude" => Float.round(lat + lat_offset, 4),
        "longitude" => Float.round(lon + lon_offset, 4)
      },
      "solar_capacity_kw" => Float.round(solar_kw, 1),
      "battery_capacity_kwh" => Float.round(battery_kwh, 1),
      "meters" => %{
        "electricity_day_ean" => electricity_day_ean,
        "electricity_night_ean" => electricity_night_ean,
        "gas_ean" => gas_ean,
        "water_ean" => water_ean
      }
    }

    # Remove nil meters
    home = put_in(home, ["meters"], Enum.reject(home["meters"], fn {_k, v} -> is_nil(v) end) |> Map.new())

    home
  end

  defp generate_home_id(index) do
    # Generate UUIDv7-like ID
    timestamp_part = "019a2400"
    sequence_part = String.pad_leading(Integer.to_string(index), 4, "0")
    random_part = "7000-a001-#{String.pad_leading(Integer.to_string(index), 12, "0")}"
    "#{timestamp_part}-#{sequence_part}-#{random_part}"
  end

  defp generate_electricity_ean(is_belgian) do
    prefix = if is_belgian, do: "541449", else: "871686"
    random_digits = Enum.map(1..12, fn _ -> Enum.random(0..9) end) |> Enum.join()
    prefix <> random_digits
  end

  defp generate_gas_ean(is_belgian) do
    prefix = if is_belgian, do: "374606", else: "871687"
    random_digits = Enum.map(1..12, fn _ -> Enum.random(0..9) end) |> Enum.join()
    prefix <> random_digits
  end

  defp generate_water_ean(is_belgian) do
    prefix = if is_belgian, do: "550778", else: "871688"
    random_digits = Enum.map(1..12, fn _ -> Enum.random(0..9) end) |> Enum.join()
    prefix <> random_digits
  end

  def save_to_file(homes, filename) do
    json = Jason.encode!(homes, pretty: true)
    File.write!(filename, json)
    IO.puts("✓ Saved #{length(homes)} homes to #{filename}")
  end

  def run do
    # Generate all homes
    homes = generate_all_homes(3000)

    # Split into regional files
    regional_homes = Enum.group_by(homes, fn h -> h["address"]["region"] end)

    IO.puts("\nRegional distribution:")

    Enum.each(regional_homes, fn {region, region_homes} ->
      IO.puts("#{region}: #{length(region_homes)} homes")

      # Map region name to filename
      filename = case region do
        "belgium_flanders_west" -> "flanders_west_homes.json"
        "belgium_flanders_central" -> "flanders_central_homes.json"
        "belgium_flanders_east" -> "flanders_east_homes.json"
        "belgium_brussels" -> "brussels_homes.json"
        "belgium_wallonia_north" -> "wallonia_north_homes.json"
        "belgium_wallonia_south" -> "wallonia_south_homes.json"
        "netherlands_west" -> "netherlands_west_homes.json"
        "netherlands_north" -> "netherlands_north_homes.json"
        "netherlands_central" -> "netherlands_central_homes.json"
        "netherlands_south" -> "netherlands_south_homes.json"
        "netherlands_east" -> "netherlands_east_homes.json"
      end

      save_to_file(region_homes, filename)
    end)

    # Also save complete list
    save_to_file(homes, "all_3000_homes.json")

    IO.puts("\n✅ Expanded seed data generation complete!")
    IO.puts("   Total: #{length(homes)} homes across #{map_size(regional_homes)} regions")
  end
end

# Run if called directly
if System.get_env("MIX_ENV") != "test" do
  {:ok, _} = Application.ensure_all_started(:jason)
  ExpandedSeedDataGenerator.run()
end
