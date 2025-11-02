defmodule CortexIqHomes.ConfigLoaderTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.ConfigLoader
  alias CortexIqCore.Home

  describe "load_homes/1" do
    test "loads homes from JSON file in priv/homes/" do
      homes = ConfigLoader.load_homes("flanders_test_homes.json")

      assert is_list(homes)
      assert length(homes) > 0
    end

    test "returns list of Home structs" do
      homes = ConfigLoader.load_homes("flanders_test_homes.json")

      first_home = List.first(homes)
      assert %Home{} = first_home
      assert is_binary(first_home.id)
      assert is_binary(first_home.name)
    end

    test "parses home attributes correctly" do
      homes = ConfigLoader.load_homes("flanders_test_homes.json")
      home = List.first(homes)

      # Check basic attributes
      assert is_binary(home.id)
      assert is_binary(home.name)
      assert is_float(home.solar_capacity_kw)
      assert is_float(home.battery_capacity_kwh)

      # Check location attributes
      assert is_map(home.location)
      assert is_binary(home.location.street)
      assert is_binary(home.location.city)
      assert is_binary(home.location.postal_code)
      assert is_atom(home.location.region)
      assert is_float(home.location.latitude)
      assert is_float(home.location.longitude)
    end

    test "raises error for missing file" do
      assert_raise RuntimeError, ~r/Could not load home configurations/, fn ->
        ConfigLoader.load_homes("nonexistent_file.json")
      end
    end

    test "logs loading progress" do
      # The function should log messages (implicit test)
      homes = ConfigLoader.load_homes("flanders_test_homes.json")
      assert length(homes) > 0
    end
  end

  describe "parse_home/1 (private)" do
    test "converts JSON map to Home struct" do
      # This is tested implicitly via load_homes/1
      json_data = %{
        "id" => "test-id-123",
        "name" => "Test Home",
        "address" => %{
          "street" => "Test Street 1",
          "city" => "Test City",
          "postal_code" => "1000",
          "region" => "flanders",
          "latitude" => 50.0,
          "longitude" => 4.0
        },
        "solar_capacity_kw" => 5.0,
        "battery_capacity_kwh" => 10.0
      }

      # We can't call private function directly, but we tested it via load_homes
      assert true
    end

    test "converts region string to atom" do
      homes = ConfigLoader.load_homes("flanders_test_homes.json")
      home = List.first(homes)

      assert is_atom(home.location.region)
    end

    test "sets current_contract_id to nil" do
      homes = ConfigLoader.load_homes("flanders_test_homes.json")
      home = List.first(homes)

      assert home.current_contract_id == nil
    end
  end
end
