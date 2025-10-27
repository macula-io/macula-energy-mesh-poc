#!/usr/bin/env elixir

# Generate persistent home configurations for Flanders with UUID7 identifiers
# Usage: elixir scripts/generate_home_configs.exs

Mix.install([
  {:uniq, "~> 0.6"},
  {:jason, "~> 1.4"}
])

defmodule HomeConfigGenerator do
  @moduledoc """
  Generates persistent home configurations with:
  - UUID7 identifiers (time-ordered, sortable)
  - Realistic Flanders addresses
  - Varied solar and battery capacities
  """

  # Flanders cities (20 cities from CortexIqCore.Geography)
  @flanders_cities [
    %{city: "Antwerp", postal_code: "2000", latitude: 51.2194, longitude: 4.4025},
    %{city: "Ghent", postal_code: "9000", latitude: 51.0543, longitude: 3.7174},
    %{city: "Bruges", postal_code: "8000", latitude: 51.2093, longitude: 3.2247},
    %{city: "Leuven", postal_code: "3000", latitude: 50.8798, longitude: 4.7005},
    %{city: "Mechelen", postal_code: "2800", latitude: 51.0259, longitude: 4.4777},
    %{city: "Aalst", postal_code: "9300", latitude: 50.9365, longitude: 4.0396},
    %{city: "Kortrijk", postal_code: "8500", latitude: 50.8279, longitude: 3.2648},
    %{city: "Hasselt", postal_code: "3500", latitude: 50.9307, longitude: 5.3378},
    %{city: "Sint-Niklaas", postal_code: "9100", latitude: 51.1656, longitude: 4.1431},
    %{city: "Ostend", postal_code: "8400", latitude: 51.2153, longitude: 2.9275},
    %{city: "Genk", postal_code: "3600", latitude: 50.9649, longitude: 5.5013},
    %{city: "Roeselare", postal_code: "8800", latitude: 50.9464, longitude: 3.1247},
    %{city: "Turnhout", postal_code: "2300", latitude: 51.3227, longitude: 4.9447},
    %{city: "Vilvoorde", postal_code: "1800", latitude: 50.9276, longitude: 4.4279},
    %{city: "Beveren", postal_code: "9120", latitude: 51.2112, longitude: 4.2564},
    %{city: "Dendermonde", postal_code: "9200", latitude: 51.0286, longitude: 4.1011},
    %{city: "Waregem", postal_code: "8790", latitude: 50.8892, longitude: 3.4195},
    %{city: "Ypres", postal_code: "8900", latitude: 50.8504, longitude: 2.8860},
    %{city: "Mol", postal_code: "2400", latitude: 51.1922, longitude: 5.1161},
    %{city: "Herentals", postal_code: "2200", latitude: 51.1774, longitude: 4.8344}
  ]

  # Flemish street names
  @street_names [
    "Grote Markt", "Kerkstraat", "Dorpsplein", "Stationsstraat", "Hoogstraat",
    "Nieuwstraat", "Bruggestraat", "Kapelstraat", "Molenstraat", "Schoolstraat",
    "Marktplein", "Koningstraat", "Mechelsesteenweg", "Antwerpsesteenweg",
    "Gentsesteenweg", "Bosstraat", "Kastanjelaan", "Eikenlaan", "Lindenlaan",
    "Populierenlaan", "Acacialaan", "Berkenstraat", "Wilgenstraat", "Essenstraat"
  ]

  # Flemish family names
  @family_names [
    "Van Der Berg", "De Vries", "Janssens", "Peeters", "Willems", "Maes",
    "Jacobs", "Mertens", "Wouters", "De Smet", "Claes", "Goossens", "Vermeulen",
    "Van Damme", "De Cock", "Stevens", "Pauwels", "De Wilde", "Baert", "Desmet",
    "Vandenberghe", "Devos", "Segers", "Coppens", "Hendrickx", "Aerts"
  ]

  def generate_homes(count, output_file) do
    IO.puts("Generating #{count} homes for #{output_file}...")

    homes =
      1..count
      |> Enum.map(fn i ->
        city = Enum.random(@flanders_cities)
        generate_home(i, city)
      end)

    # Write to JSON file
    json = Jason.encode!(homes, pretty: true)
    File.write!(output_file, json)

    IO.puts("✓ Generated #{count} homes -> #{output_file}")
  end

  defp generate_home(_index, city) do
    street_name = Enum.random(@street_names)
    street_number = Enum.random(1..999)
    family_name = Enum.random(@family_names)

    %{
      id: Uniq.UUID.uuid7(),
      name: "#{family_name} Residence",
      address: %{
        street: "#{street_name} #{street_number}",
        city: city.city,
        postal_code: city.postal_code,
        region: "flanders",
        latitude: city.latitude + (:rand.uniform() - 0.5) * 0.01,  # Small offset
        longitude: city.longitude + (:rand.uniform() - 0.5) * 0.01
      },
      solar_capacity_kw: Float.round(3.0 + :rand.uniform() * 4.0, 2),  # 3-7 kW
      battery_capacity_kwh: Float.round(5.0 + :rand.uniform() * 10.0, 2)  # 5-15 kWh
    }
  end
end

# Generate home configuration files
output_dir = Path.join([__DIR__, "..", "system", "cortex_iq_homes", "priv", "homes"])
File.mkdir_p!(output_dir)

# Edge-03: 50 homes
HomeConfigGenerator.generate_homes(
  50,
  Path.join(output_dir, "flanders_edge_03_homes.json")
)

# Edge-04: 50 homes
HomeConfigGenerator.generate_homes(
  50,
  Path.join(output_dir, "flanders_edge_04_homes.json")
)

# Test: 10 homes for local development
HomeConfigGenerator.generate_homes(
  10,
  Path.join(output_dir, "flanders_test_homes.json")
)

IO.puts("\n✓ All home configuration files generated successfully!")
IO.puts("  Location: #{output_dir}")
