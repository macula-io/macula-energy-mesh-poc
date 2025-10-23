defmodule CortexIqCore.Geography do
  @moduledoc """
  Belgian geography data for realistic home locations.

  Provides cities, postal codes, and coordinates across Belgium's three regions:
  Brussels-Capital, Flanders, and Wallonia.
  """

  @type location :: %{
          city: String.t(),
          postal_code: String.t(),
          latitude: float(),
          longitude: float(),
          region: atom()
        }

  @type region :: :brussels | :flanders | :wallonia

  @locations [
    # Brussels-Capital Region (10 cities)
    %{city: "Brussels", postal_code: "1000", latitude: 50.8503, longitude: 4.3517, region: :brussels},
    %{city: "Brussels Ixelles", postal_code: "1050", latitude: 50.8333, longitude: 4.3667, region: :brussels},
    %{city: "Brussels Etterbeek", postal_code: "1040", latitude: 50.8368, longitude: 4.3891, region: :brussels},
    %{city: "Brussels Schaerbeek", postal_code: "1030", latitude: 50.8676, longitude: 4.3732, region: :brussels},
    %{city: "Brussels Anderlecht", postal_code: "1070", latitude: 50.8364, longitude: 4.3137, region: :brussels},
    %{city: "Brussels Uccle", postal_code: "1180", latitude: 50.7989, longitude: 4.3342, region: :brussels},
    %{city: "Brussels Molenbeek", postal_code: "1080", latitude: 50.8583, longitude: 4.3140, region: :brussels},
    %{city: "Brussels Woluwe", postal_code: "1150", latitude: 50.8261, longitude: 4.4242, region: :brussels},
    %{city: "Brussels Jette", postal_code: "1090", latitude: 50.8797, longitude: 4.3237, region: :brussels},
    %{city: "Brussels Koekelberg", postal_code: "1081", latitude: 50.8634, longitude: 4.3284, region: :brussels},

    # Flanders (20 cities)
    %{city: "Antwerp", postal_code: "2000", latitude: 51.2194, longitude: 4.4025, region: :flanders},
    %{city: "Ghent", postal_code: "9000", latitude: 51.0543, longitude: 3.7174, region: :flanders},
    %{city: "Bruges", postal_code: "8000", latitude: 51.2093, longitude: 3.2247, region: :flanders},
    %{city: "Leuven", postal_code: "3000", latitude: 50.8798, longitude: 4.7005, region: :flanders},
    %{city: "Mechelen", postal_code: "2800", latitude: 51.0259, longitude: 4.4777, region: :flanders},
    %{city: "Aalst", postal_code: "9300", latitude: 50.9365, longitude: 4.0396, region: :flanders},
    %{city: "Kortrijk", postal_code: "8500", latitude: 50.8279, longitude: 3.2648, region: :flanders},
    %{city: "Hasselt", postal_code: "3500", latitude: 50.9307, longitude: 5.3378, region: :flanders},
    %{city: "Sint-Niklaas", postal_code: "9100", latitude: 51.1656, longitude: 4.1431, region: :flanders},
    %{city: "Ostend", postal_code: "8400", latitude: 51.2153, longitude: 2.9275, region: :flanders},
    %{city: "Genk", postal_code: "3600", latitude: 50.9649, longitude: 5.5013, region: :flanders},
    %{city: "Roeselare", postal_code: "8800", latitude: 50.9464, longitude: 3.1247, region: :flanders},
    %{city: "Turnhout", postal_code: "2300", latitude: 51.3227, longitude: 4.9447, region: :flanders},
    %{city: "Vilvoorde", postal_code: "1800", latitude: 50.9276, longitude: 4.4279, region: :flanders},
    %{city: "Beveren", postal_code: "9120", latitude: 51.2112, longitude: 4.2564, region: :flanders},
    %{city: "Dendermonde", postal_code: "9200", latitude: 51.0286, longitude: 4.1011, region: :flanders},
    %{city: "Waregem", postal_code: "8790", latitude: 50.8892, longitude: 3.4195, region: :flanders},
    %{city: "Ypres", postal_code: "8900", latitude: 50.8504, longitude: 2.8860, region: :flanders},
    %{city: "Mol", postal_code: "2400", latitude: 51.1922, longitude: 5.1161, region: :flanders},
    %{city: "Herentals", postal_code: "2200", latitude: 51.1774, longitude: 4.8344, region: :flanders},

    # Wallonia (10 cities)
    %{city: "Liège", postal_code: "4000", latitude: 50.6326, longitude: 5.5797, region: :wallonia},
    %{city: "Charleroi", postal_code: "6000", latitude: 50.4108, longitude: 4.4446, region: :wallonia},
    %{city: "Namur", postal_code: "5000", latitude: 50.4674, longitude: 4.8720, region: :wallonia},
    %{city: "Mons", postal_code: "7000", latitude: 50.4542, longitude: 3.9565, region: :wallonia},
    %{city: "Tournai", postal_code: "7500", latitude: 50.6054, longitude: 3.3889, region: :wallonia},
    %{city: "Verviers", postal_code: "4800", latitude: 50.5893, longitude: 5.8632, region: :wallonia},
    %{city: "La Louvière", postal_code: "7100", latitude: 50.4758, longitude: 4.1886, region: :wallonia},
    %{city: "Mouscron", postal_code: "7700", latitude: 50.7454, longitude: 3.2066, region: :wallonia},
    %{city: "Arlon", postal_code: "6700", latitude: 49.6836, longitude: 5.8167, region: :wallonia},
    %{city: "Wavre", postal_code: "1300", latitude: 50.7167, longitude: 4.6111, region: :wallonia}
  ]

  @doc """
  Get a random Belgian location.
  """
  @spec random_location() :: location()
  def random_location do
    Enum.random(@locations)
  end

  @doc """
  Get all locations in a specific region.
  """
  @spec locations_by_region(region()) :: [location()]
  def locations_by_region(region) when region in [:brussels, :flanders, :wallonia] do
    @locations
    |> Enum.filter(&(&1.region == region))
  end

  def locations_by_region(_invalid_region), do: []

  @doc """
  Get deterministic location for a home_id.

  Same home_id always returns same location (uses hash for consistency).
  """
  @spec location_for_home(String.t()) :: location()
  def location_for_home(home_id) when is_binary(home_id) do
    hash =
      home_id
      |> :erlang.phash2(length(@locations))

    Enum.at(@locations, hash)
  end

  @doc """
  Get all available locations.
  """
  @spec all_locations() :: [location()]
  def all_locations, do: @locations

  @doc """
  Get region name as string for display.
  """
  @spec region_name(region()) :: String.t()
  def region_name(:brussels), do: "Brussels-Capital"
  def region_name(:flanders), do: "Flanders"
  def region_name(:wallonia), do: "Wallonia"
  def region_name(_), do: "Unknown"
end
