defmodule MeshCore.Geography do
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
    # Brussels-Capital Region
    %{
      city: "Brussels",
      postal_code: "1000",
      latitude: 50.8503,
      longitude: 4.3517,
      region: :brussels
    },
    %{
      city: "Brussels Ixelles",
      postal_code: "1050",
      latitude: 50.8333,
      longitude: 4.3667,
      region: :brussels
    },
    # Flanders
    %{
      city: "Antwerp",
      postal_code: "2000",
      latitude: 51.2194,
      longitude: 4.4025,
      region: :flanders
    },
    %{
      city: "Ghent",
      postal_code: "9000",
      latitude: 51.0543,
      longitude: 3.7174,
      region: :flanders
    },
    %{
      city: "Bruges",
      postal_code: "8000",
      latitude: 51.2093,
      longitude: 3.2247,
      region: :flanders
    },
    %{
      city: "Leuven",
      postal_code: "3000",
      latitude: 50.8798,
      longitude: 4.7005,
      region: :flanders
    },
    %{
      city: "Mechelen",
      postal_code: "2800",
      latitude: 51.0259,
      longitude: 4.4777,
      region: :flanders
    },
    %{
      city: "Aalst",
      postal_code: "9300",
      latitude: 50.9365,
      longitude: 4.0396,
      region: :flanders
    },
    # Wallonia
    %{
      city: "Liège",
      postal_code: "4000",
      latitude: 50.6326,
      longitude: 5.5797,
      region: :wallonia
    },
    %{
      city: "Charleroi",
      postal_code: "6000",
      latitude: 50.4108,
      longitude: 4.4446,
      region: :wallonia
    },
    %{
      city: "Namur",
      postal_code: "5000",
      latitude: 50.4674,
      longitude: 4.8720,
      region: :wallonia
    },
    %{
      city: "Mons",
      postal_code: "7000",
      latitude: 50.4542,
      longitude: 3.9565,
      region: :wallonia
    }
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
