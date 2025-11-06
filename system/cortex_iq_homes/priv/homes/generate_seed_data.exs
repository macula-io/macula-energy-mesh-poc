#!/usr/bin/env elixir

# Seed Data Generator for CortexIQ Homes
# Generates 1000 homes with realistic multi-meter data for Belgium and Netherlands
#
# Usage: elixir generate_seed_data.exs

defmodule SeedDataGenerator do
  @moduledoc """
  Generates realistic seed data for 1000 homes across Belgium and Netherlands.

  Features:
  - Multiple meter EANs per home (electricity day/night, gas, water)
  - Realistic city distribution
  - Accurate coordinates for each city
  - Belgian and Dutch family names
  - Realistic solar/battery capacities
  """

  # Belgian cities with coordinates
  @belgian_cities [
    {"Gent", "9000", 51.0543, 3.7174, "belgium_flanders"},
    {"Antwerpen", "2000", 51.2194, 4.4025, "belgium_flanders"},
    {"Brugge", "8000", 51.2093, 3.2247, "belgium_flanders"},
    {"Leuven", "3000", 50.8798, 4.7005, "belgium_flanders"},
    {"Mechelen", "2800", 51.0259, 4.4777, "belgium_flanders"},
    {"Aalst", "9300", 50.9381, 4.0414, "belgium_flanders"},
    {"Hasselt", "3500", 50.9307, 5.3378, "belgium_flanders"},
    {"Genk", "3600", 50.9658, 5.5015, "belgium_flanders"},
    {"Turnhout", "2300", 51.3227, 4.9447, "belgium_flanders"},
    {"Bruxelles", "1000", 50.8503, 4.3517, "belgium_brussels"},
    {"Etterbeek", "1040", 50.8325, 4.3889, "belgium_brussels"},
    {"Ixelles", "1050", 50.8343, 4.3661, "belgium_brussels"},
    {"Jette", "1090", 50.8794, 4.3276, "belgium_brussels"},
    {"Uccle", "1180", 50.7989, 4.3258, "belgium_brussels"},
    {"Charleroi", "6000", 50.4108, 4.4446, "belgium_wallonia"},
    {"Liège", "4000", 50.6326, 5.5797, "belgium_wallonia"},
    {"Namur", "5000", 50.4674, 4.8720, "belgium_wallonia"},
    {"Mons", "7000", 50.4542, 3.9564, "belgium_wallonia"},
    {"Verviers", "4800", 50.5893, 5.8629, "belgium_wallonia"},
    {"Tournai", "7500", 50.6060, 3.3883, "belgium_wallonia"}
  ]

  # Dutch cities with coordinates
  @dutch_cities [
    {"Amsterdam", "1000", 52.3676, 4.9041, "netherlands_north"},
    {"Rotterdam", "3000", 51.9225, 4.4792, "netherlands_south"},
    {"Den Haag", "2500", 52.0705, 4.3007, "netherlands_south"},
    {"Utrecht", "3500", 52.0907, 5.1214, "netherlands_central"},
    {"Eindhoven", "5600", 51.4416, 5.4697, "netherlands_south"},
    {"Tilburg", "5000", 51.5556, 5.0919, "netherlands_south"},
    {"Groningen", "9700", 53.2194, 6.5665, "netherlands_north"},
    {"Almere", "1300", 52.3508, 5.2647, "netherlands_central"},
    {"Breda", "4800", 51.5878, 4.7755, "netherlands_south"},
    {"Nijmegen", "6500", 51.8426, 5.8539, "netherlands_central"},
    {"Enschede", "7500", 52.2215, 6.8937, "netherlands_east"},
    {"Apeldoorn", "7300", 52.2112, 5.9699, "netherlands_central"},
    {"Haarlem", "2000", 52.3874, 4.6462, "netherlands_north"},
    {"Arnhem", "6800", 51.9851, 5.8987, "netherlands_central"},
    {"Zaanstad", "1500", 52.4388, 4.8260, "netherlands_north"},
    {"Amersfoort", "3800", 52.1561, 5.3878, "netherlands_central"},
    {"'s-Hertogenbosch", "5200", 51.6881, 5.3032, "netherlands_south"},
    {"Hoofddorp", "2130", 52.3031, 4.6891, "netherlands_north"},
    {"Maastricht", "6200", 50.8514, 5.6910, "netherlands_south"},
    {"Leiden", "2300", 52.1601, 4.4970, "netherlands_south"},
    {"Dordrecht", "3300", 51.8133, 4.6901, "netherlands_south"},
    {"Zoetermeer", "2700", 52.0575, 4.4932, "netherlands_south"},
    {"Zwolle", "8000", 52.5125, 6.0944, "netherlands_east"},
    {"Deventer", "7400", 52.2551, 6.1639, "netherlands_east"},
    {"Delft", "2600", 52.0116, 4.3571, "netherlands_south"},
    {"Emmen", "7800", 52.7792, 6.9003, "netherlands_north"},
    {"Venlo", "5900", 51.3704, 6.1724, "netherlands_south"},
    {"Ede", "6710", 52.0409, 5.6575, "netherlands_central"},
    {"Leeuwarden", "8900", 53.2012, 5.7999, "netherlands_north"},
    {"Roosendaal", "4700", 51.5316, 4.4656, "netherlands_south"},
    {"Purmerend", "1440", 52.5051, 4.9595, "netherlands_north"},
    {"Oss", "5340", 51.7648, 5.5179, "netherlands_south"},
    {"Schiedam", "3100", 51.9194, 4.3961, "netherlands_south"},
    {"Spijkenisse", "3200", 51.8447, 4.3289, "netherlands_south"},
    {"Helmond", "5700", 51.4816, 5.6558, "netherlands_south"},
    {"Almelo", "7600", 52.3567, 6.6625, "netherlands_east"},
    {"Heerlen", "6400", 50.8871, 5.9817, "netherlands_south"},
    {"Hoogeveen", "7900", 52.7261, 6.4760, "netherlands_north"},
    {"Alkmaar", "1800", 52.6318, 4.7518, "netherlands_north"},
    {"Assen", "9400", 52.9960, 6.5628, "netherlands_north"}
  ]

  @all_cities @belgian_cities ++ @dutch_cities

  # Belgian family names
  @belgian_names ~w(
    Peeters Janssens Maes Jacobs Willems Goossens Wouters Claes Mertens
    Simon Laurent Dubois Lambert Fontaine Rousseau Vincent Gerard Dupont
    Vermeulen Smet Desmet Devos Baert Bogaert Coppens Hendrickx Van_den_Berg
    Martens Hermans Claessens Aerts Vandenberghe Dewilde Verhoeven Michiels
    Vanderhaeghen Matthijs De_Cock De_Pauw Lemmens Stevens Evers Govaerts
  )

  # Dutch family names
  @dutch_names ~w(
    De_Jong Jansen Bakker Visser Smit Meijer De_Boer Mulder De_Groot Bos
    Vos Peters Hendriks Van_Dijk Van_den_Berg Van_Leeuwen Dekker Brouwer
    De_Wit Koning Van_der_Meer De_Vries Kok Jacobs De_Haan Van_der_Linden
    Vermeulen Schouten Van_der_Veen Hoek Kuiper Kuijpers Timmermans Groen
    Gerritsen Jonker Van_Dam Prins De_Ruiter Wolters Scholten Bosch Spruit
  )

  # IoT providers
  @iot_providers ~w(HomeWizard Toon SolarEdge Enphase Tesla_Powerwall Huawei_FusionSolar SMA_Sunny_Portal)

  # Street names (generic, will be used with numbers)
  @belgian_streets ~w(Markt Grote_Markt Korenmarkt Veldstraat Groenplaats Meir Steenstraat Kasteelstraat)
  @dutch_streets ~w(Hoofdstraat Kerkstraat Schoolstraat Molenstraat Dorpsstraat Stationsweg Marktplein)

  def generate_all_homes(count \\ 1000) do
    IO.puts("Generating #{count} homes with realistic multi-meter data...")

    homes =
      1..count
      |> Enum.map(fn index ->
        generate_home(index)
      end)

    IO.puts("✓ Generated #{length(homes)} homes")
    homes
  end

  def generate_home(index) do
    # Choose random city
    {city, postal_code, lat, lon, region} = Enum.random(@all_cities)

    # Determine if Belgian or Dutch
    is_belgian = String.starts_with?(region, "belgium_")

    # Choose appropriate name and street
    family_name = if is_belgian, do: Enum.random(@belgian_names), else: Enum.random(@dutch_names)
    street_base = if is_belgian, do: Enum.random(@belgian_streets), else: Enum.random(@dutch_streets)
    street = "#{String.replace(street_base, "_", " ")} #{Enum.random(1..200)}"

    # Add slight coordinate variation (+/- 0.01 degrees = ~1km)
    lat_offset = (:rand.uniform() - 0.5) * 0.02
    lon_offset = (:rand.uniform() - 0.5) * 0.02

    # Generate meter EANs
    electricity_day_ean = generate_electricity_ean(region)
    electricity_night_ean = generate_electricity_ean(region)

    # 70% chance of gas meter
    gas_ean = if :rand.uniform() < 0.7, do: generate_gas_ean(region), else: nil

    # 80% chance of water meter
    water_ean = if :rand.uniform() < 0.8, do: generate_water_ean(region), else: nil

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

  defp generate_electricity_ean(region) do
    prefix = if String.starts_with?(region, "belgium_"), do: "541449", else: "871686"
    random_digits = Enum.map(1..12, fn _ -> Enum.random(0..9) end) |> Enum.join()
    prefix <> random_digits
  end

  defp generate_gas_ean(region) do
    prefix = if String.starts_with?(region, "belgium_"), do: "374606", else: "871687"
    random_digits = Enum.map(1..12, fn _ -> Enum.random(0..9) end) |> Enum.join()
    prefix <> random_digits
  end

  defp generate_water_ean(region) do
    prefix = if String.starts_with?(region, "belgium_"), do: "550778", else: "871688"
    random_digits = Enum.map(1..12, fn _ -> Enum.random(0..9) end) |> Enum.join()
    prefix <> random_digits
  end

  def save_to_file(homes, filename) do
    json = Jason.encode!(homes, pretty: true)
    File.write!(filename, json)
    IO.puts("✓ Saved to #{filename}")
  end

  def run do
    # Generate all homes
    homes = generate_all_homes(1000)

    # Split into regional files (200 homes each)
    belgium_flanders = Enum.filter(homes, fn h -> h["address"]["region"] == "belgium_flanders" end)
    belgium_brussels = Enum.filter(homes, fn h -> h["address"]["region"] == "belgium_brussels" end)
    belgium_wallonia = Enum.filter(homes, fn h -> h["address"]["region"] == "belgium_wallonia" end)
    netherlands_north = Enum.filter(homes, fn h -> h["address"]["region"] == "netherlands_north" end)
    netherlands_south = Enum.filter(homes, fn h -> h["address"]["region"] == "netherlands_south" end)
    netherlands_central = Enum.filter(homes, fn h -> h["address"]["region"] == "netherlands_central" end)
    netherlands_east = Enum.filter(homes, fn h -> h["address"]["region"] == "netherlands_east" end)

    IO.puts("\nRegional distribution:")
    IO.puts("Belgium Flanders: #{length(belgium_flanders)} homes")
    IO.puts("Belgium Brussels: #{length(belgium_brussels)} homes")
    IO.puts("Belgium Wallonia: #{length(belgium_wallonia)} homes")
    IO.puts("Netherlands North: #{length(netherlands_north)} homes")
    IO.puts("Netherlands South: #{length(netherlands_south)} homes")
    IO.puts("Netherlands Central: #{length(netherlands_central)} homes")
    IO.puts("Netherlands East: #{length(netherlands_east)} homes")

    # Save to regional files
    save_to_file(belgium_flanders, "belgium_flanders_homes.json")
    save_to_file(belgium_brussels, "belgium_brussels_homes.json")
    save_to_file(belgium_wallonia, "belgium_wallonia_homes.json")
    save_to_file(netherlands_north, "netherlands_north_homes.json")
    save_to_file(netherlands_south, "netherlands_south_homes.json")
    save_to_file(netherlands_central, "netherlands_central_homes.json")
    save_to_file(netherlands_east, "netherlands_east_homes.json")

    # Also save complete list
    save_to_file(homes, "all_1000_homes.json")

    IO.puts("\n✅ Seed data generation complete!")
  end
end

# Run if called directly
if System.get_env("MIX_ENV") != "test" do
  {:ok, _} = Application.ensure_all_started(:jason)
  SeedDataGenerator.run()
end
