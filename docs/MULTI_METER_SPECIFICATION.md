# Multi-Meter Data Model Specification

## Overview

Realistic energy monitoring systems track multiple utility meters per home. This document specifies the multi-meter data model for CortexIQ homes.

## Meter Types

### 1. Electricity Meters (Dual-Tariff)

Belgium and Netherlands commonly use **day/night split tariffs** (dag/nachttarief). This requires two separate electricity meters.

**Day Meter (6am - 10pm):**
- **EAN Format**: 18 digits
- **Belgium prefix**: `541449` + 12 random digits
- **Netherlands prefix**: `871686` + 12 random digits
- **Measures**: Production (solar) and consumption during day hours
- **Example**: `541449000012345678`

**Night Meter (10pm - 6am):**
- **EAN Format**: 18 digits
- **Belgium prefix**: `541449` + 12 random digits (different from day meter)
- **Netherlands prefix**: `871686` + 12 random digits
- **Measures**: Consumption during night hours (no solar production at night)
- **Example**: `541449000087654321`

**Note**: Some homes may have single-rate meters instead. Store as `electricity_single_meter_ean`.

### 2. Gas Meter (Optional)

Not all homes use gas (electric heating alternatives).

**Gas Meter:**
- **EAN Format**: 18 digits
- **Belgium prefix**: `374606` + 12 random digits
- **Netherlands prefix**: `871687` + 12 random digits
- **Measures**: Natural gas consumption in cubic meters (m³)
- **Example**: `374606000045678912`

**Distribution**: ~70% of homes have gas meters (older homes, heating preference)

### 3. Water Meter (Optional)

Water metering is becoming more common but not universal.

**Water Meter:**
- **EAN Format**: 18 digits
- **Belgium prefix**: `550778` + 12 random digits
- **Netherlands prefix**: `871688` + 12 random digits
- **Measures**: Water consumption in cubic meters (m³)
- **Example**: `550778000098765432`

**Distribution**: ~80% of homes have water meters (mandatory in newer buildings)

## Database Schema Extension

### HomeState Table (cortex_iq_dashboard_schemas)

```elixir
defmodule CortexIqDashboardSchemas.Projections.HomeState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:home_id, :string, autogenerate: false}
  schema "home_states" do
    # Existing fields...
    field :name, :string
    field :location, :string
    field :latitude, :float
    field :longitude, :float

    # UPDATED: Multiple meter EANs
    field :electricity_day_meter_ean, :string    # Day tariff (6am-10pm)
    field :electricity_night_meter_ean, :string  # Night tariff (10pm-6am)
    field :electricity_single_meter_ean, :string # Single-rate (if no day/night split)
    field :gas_meter_ean, :string                # Gas meter (optional)
    field :water_meter_ean, :string              # Water meter (optional)

    # Meter readings (cumulative)
    field :electricity_day_cumulative_kwh, :float
    field :electricity_night_cumulative_kwh, :float
    field :gas_cumulative_m3, :float
    field :water_cumulative_m3, :float

    # ... other fields
    timestamps()
  end
end
```

## Event Payload Structure

### Topic: `be.cortexiq.home.measured`

**Single topic for ALL homes** (IDs in payload, not topic!)

```json
{
  "home_id": "019a2400-0005-7000-a001-000000000001",
  "name": "Peeters Family",
  "iot_provider": "Solar Edge",
  "location": "Gent",
  "street": "Korenmarkt 23",
  "postal_code": "9000",
  "region": "belgium_flanders",
  "latitude": 51.0543,
  "longitude": 3.7174,
  "solar_capacity_kw": 4.5,
  "battery_capacity_kwh": 11.5,

  "simulation_time": "2025-11-04T14:30:00Z",

  "electricity_day_meter": {
    "ean": "541449000012345678",
    "production_w": 3500,
    "consumption_w": 1200,
    "cumulative_kwh": 2450.5,
    "net_import_kwh": 890.2,
    "net_export_kwh": 1234.8
  },

  "electricity_night_meter": {
    "ean": "541449000087654321",
    "consumption_w": 0,
    "cumulative_kwh": 1567.3,
    "net_import_kwh": 1567.3,
    "net_export_kwh": 0.0
  },

  "gas_meter": {
    "ean": "374606000045678912",
    "consumption_m3_hour": 0.85,
    "cumulative_m3": 1240.7
  },

  "water_meter": {
    "ean": "550778000098765432",
    "consumption_m3_hour": 0.025,
    "cumulative_m3": 342.9
  },

  "battery": {
    "percent": 75,
    "state": "charging",
    "power_w": 2000
  },

  "provider_id": "provider_a",
  "contract_id": "contract_xyz_2025"
}
```

## Seed Data Format

### JSON Structure (priv/homes/*.json)

```json
[
  {
    "id": "019a2400-0005-7000-a001-000000000001",
    "name": "Peeters Family",
    "iot_provider": "Solar Edge",
    "address": {
      "city": "Gent",
      "postal_code": "9000",
      "street": "Korenmarkt 23",
      "region": "belgium_flanders",
      "latitude": 51.0543,
      "longitude": 3.7174
    },
    "solar_capacity_kw": 4.5,
    "battery_capacity_kwh": 11.5,
    "meters": {
      "electricity_day_ean": "541449000012345678",
      "electricity_night_ean": "541449000087654321",
      "gas_ean": "374606000045678912",
      "water_ean": "550778000098765432"
    }
  }
]
```

## EAN Generation Algorithm

```elixir
defmodule CortexIqHomes.MeterEanGenerator do
  @moduledoc """
  Generates realistic EAN-18 meter numbers for Belgium and Netherlands.
  """

  @belgium_electricity_prefix "541449"
  @netherlands_electricity_prefix "871686"
  @belgium_gas_prefix "374606"
  @netherlands_gas_prefix "871687"
  @belgium_water_prefix "550778"
  @netherlands_water_prefix "871688"

  def generate_electricity_ean(region) do
    prefix = electricity_prefix(region)
    random_digits = random_digits(12)
    prefix <> random_digits
  end

  def generate_gas_ean(region) do
    prefix = gas_prefix(region)
    random_digits = random_digits(12)
    prefix <> random_digits
  end

  def generate_water_ean(region) do
    prefix = water_prefix(region)
    random_digits = random_digits(12)
    prefix <> random_digits
  end

  defp electricity_prefix("belgium_" <> _), do: @belgium_electricity_prefix
  defp electricity_prefix("netherlands_" <> _), do: @netherlands_electricity_prefix

  defp gas_prefix("belgium_" <> _), do: @belgium_gas_prefix
  defp gas_prefix("netherlands_" <> _), do: @netherlands_gas_prefix

  defp water_prefix("belgium_" <> _), do: @belgium_water_prefix
  defp water_prefix("netherlands_" <> _), do: @netherlands_water_prefix

  defp random_digits(count) do
    1..count
    |> Enum.map(fn _ -> Enum.random(0..9) end)
    |> Enum.join()
  end
end
```

## Meter Presence Logic

Not all homes have all meters:

```elixir
# Electricity: 100% (everyone has electricity)
electricity_day_ean: always present
electricity_night_ean: always present

# Gas: 70% (older homes, heating preference)
gas_ean: random(70%)

# Water: 80% (newer regulations)
water_ean: random(80%)
```

## Migration Plan

1. **Add columns to home_states table** (migration)
2. **Update HomeState schema** (add new fields)
3. **Generate new seed data** (1000 homes with realistic EANs)
4. **Update home worker** (include meters in event payload)
5. **Update projections** (store meter data)
6. **Update dashboard** (display multi-meter data)

## Performance Considerations

**Payload Size:**
- Current: ~100 bytes/event
- With multi-meter: ~400 bytes/event
- **1000 homes × 1 event/sec = 400 KB/sec** (acceptable)

**Database Impact:**
- 4 new columns (meter EANs): strings (18 chars each) = ~72 bytes/home
- 4 new columns (cumulative readings): floats = 32 bytes/home
- **Total: ~100 bytes/home × 1000 homes = 100 KB** (negligible)

## Next Steps

1. Create database migration for new meter columns
2. Update HomeState schema
3. Create EAN generator module
4. Generate seed data for 1000 homes
5. Update home worker to publish enhanced events
6. Update dashboard to visualize multi-meter data
