#!/usr/bin/env python3
"""
Generate 3000 realistic home seed data files for CortexIQ
Split into regional files for multi-replica deployment
"""

import json
import random
from typing import Dict, List, Tuple

# Regional city definitions with (city, postal_code, lat, lon)
REGIONS = {
    "flanders_west": [
        ("Gent", "9000", 51.0543, 3.7174),
        ("Brugge", "8000", 51.2093, 3.2247),
        ("Kortrijk", "8500", 50.8280, 3.2647),
        ("Oostende", "8400", 51.2189, 2.9312),
        ("Roeselare", "8800", 50.9467, 3.1246)
    ],
    "flanders_central": [
        ("Antwerpen", "2000", 51.2194, 4.4025),
        ("Mechelen", "2800", 51.0259, 4.4777),
        ("Leuven", "3000", 50.8798, 4.7005),
        ("Aalst", "9300", 50.9381, 4.0414),
        ("Sint-Niklaas", "9100", 51.1656, 4.1431)
    ],
    "flanders_east": [
        ("Hasselt", "3500", 50.9307, 5.3378),
        ("Genk", "3600", 50.9658, 5.5015),
        ("Turnhout", "2300", 51.3227, 4.9447),
        ("Mol", "2400", 51.1918, 5.1149),
        ("Tongeren", "3700", 50.7807, 5.4650)
    ],
    "brussels": [
        ("Bruxelles", "1000", 50.8503, 4.3517),
        ("Etterbeek", "1040", 50.8325, 4.3889),
        ("Ixelles", "1050", 50.8343, 4.3661),
        ("Jette", "1090", 50.8794, 4.3276),
        ("Uccle", "1180", 50.7989, 4.3258),
        ("Schaerbeek", "1030", 50.8678, 4.3733)
    ],
    "wallonia_north": [
        ("Charleroi", "6000", 50.4108, 4.4446),
        ("Mons", "7000", 50.4542, 3.9564),
        ("La Louvière", "7100", 50.4754, 4.1877),
        ("Tournai", "7500", 50.6060, 3.3883),
        ("Mouscron", "7700", 50.7451, 3.2062)
    ],
    "wallonia_south": [
        ("Liège", "4000", 50.6326, 5.5797),
        ("Namur", "5000", 50.4674, 4.8720),
        ("Verviers", "4800", 50.5893, 5.8629),
        ("Seraing", "4100", 50.5862, 5.4998),
        ("Arlon", "6700", 49.6856, 5.8175)
    ],
    "netherlands_west": [
        ("Den Haag", "2500", 52.0705, 4.3007),
        ("Rotterdam", "3000", 51.9225, 4.4792),
        ("Leiden", "2300", 52.1601, 4.4970),
        ("Delft", "2600", 52.0116, 4.3571),
        ("Dordrecht", "3300", 51.8133, 4.6901)
    ],
    "netherlands_north": [
        ("Amsterdam", "1000", 52.3676, 4.9041),
        ("Haarlem", "2000", 52.3874, 4.6462),
        ("Zaanstad", "1500", 52.4388, 4.8260),
        ("Groningen", "9700", 53.2194, 6.5665),
        ("Leeuwarden", "8900", 53.2012, 5.7999),
        ("Alkmaar", "1800", 52.6318, 4.7518)
    ],
    "netherlands_central": [
        ("Utrecht", "3500", 52.0907, 5.1214),
        ("Almere", "1300", 52.3508, 5.2647),
        ("Amersfoort", "3800", 52.1561, 5.3878),
        ("Apeldoorn", "7300", 52.2112, 5.9699),
        ("Nijmegen", "6500", 51.8426, 5.8539),
        ("Arnhem", "6800", 51.9851, 5.8987)
    ],
    "netherlands_south": [
        ("Eindhoven", "5600", 51.4416, 5.4697),
        ("Tilburg", "5000", 51.5556, 5.0919),
        ("Breda", "4800", 51.5878, 4.7755),
        ("'s-Hertogenbosch", "5200", 51.6881, 5.3032),
        ("Maastricht", "6200", 50.8514, 5.6910),
        ("Venlo", "5900", 51.3704, 6.1724)
    ],
    "netherlands_east": [
        ("Enschede", "7500", 52.2215, 6.8937),
        ("Zwolle", "8000", 52.5125, 6.0944),
        ("Deventer", "7400", 52.2551, 6.1639),
        ("Almelo", "7600", 52.3567, 6.6625),
        ("Hengelo", "7550", 52.2657, 6.7935)
    ]
}

BELGIAN_NAMES = [
    "Peeters", "Janssens", "Maes", "Jacobs", "Willems", "Goossens", "Wouters", "Claes", "Mertens",
    "Simon", "Laurent", "Dubois", "Lambert", "Fontaine", "Rousseau", "Vincent", "Gerard", "Dupont",
    "Vermeulen", "Smet", "Desmet", "Devos", "Baert", "Bogaert", "Coppens", "Hendrickx", "Van den Berg",
    "Martens", "Hermans", "Claessens", "Aerts", "Vandenberghe", "Dewilde", "Verhoeven", "Michiels"
]

DUTCH_NAMES = [
    "De Jong", "Jansen", "Bakker", "Visser", "Smit", "Meijer", "De Boer", "Mulder", "De Groot", "Bos",
    "Vos", "Peters", "Hendriks", "Van Dijk", "Van den Berg", "Van Leeuwen", "Dekker", "Brouwer",
    "De Wit", "Koning", "Van der Meer", "De Vries", "Kok", "Jacobs", "De Haan", "Van der Linden"
]

IOT_PROVIDERS = ["HomeWizard", "Smappee", "SolarEdge", "Enphase", "Tesla Powerwall", "Huawei FusionSolar", "SMA Sunny Portal"]


def generate_ean(prefix: str, length: int = 18) -> str:
    """Generate a random EAN with given prefix"""
    remaining = length - len(prefix)
    return prefix + ''.join(str(random.randint(0, 9)) for _ in range(remaining))


def generate_home(index: int, region: str, cities: List[Tuple[str, str, float, float]]) -> Dict:
    """Generate a single home with realistic data"""
    city, postal_code, lat, lon = random.choice(cities)

    is_belgian = region in ["flanders_west", "flanders_central", "flanders_east", "brussels", "wallonia_north", "wallonia_south"]
    names = BELGIAN_NAMES if is_belgian else DUTCH_NAMES
    family_name = random.choice(names)

    # Add coordinate variation (+/- ~1km)
    lat_offset = (random.random() - 0.5) * 0.02
    lon_offset = (random.random() - 0.5) * 0.02

    # Generate meter EANs
    elec_prefix = "541449" if is_belgian else "871686"
    gas_prefix = "374606" if is_belgian else "871687"
    water_prefix = "550778" if is_belgian else "871688"

    meters = {
        "electricity_day_ean": generate_ean(elec_prefix),
        "electricity_night_ean": generate_ean(elec_prefix)
    }

    # 70% chance of gas meter
    if random.random() < 0.7:
        meters["gas_ean"] = generate_ean(gas_prefix)

    # 80% chance of water meter
    if random.random() < 0.8:
        meters["water_ean"] = generate_ean(water_prefix)

    # Realistic capacities
    solar_kw = round(random.uniform(2.5, 5.5), 1)
    battery_kwh = round(random.uniform(8.0, 14.0), 1)

    return {
        "id": f"019a2400-{index:04d}-7000-a001-{index:012d}",
        "name": f"{family_name} Family",
        "iot_provider": random.choice(IOT_PROVIDERS),
        "address": {
            "city": city,
            "postal_code": postal_code,
            "street": f"Straat {random.randint(1, 200)}",
            "region": f"belgium_{region}" if is_belgian else f"netherlands_{region.replace('netherlands_', '')}",
            "latitude": round(lat + lat_offset, 4),
            "longitude": round(lon + lon_offset, 4)
        },
        "solar_capacity_kw": solar_kw,
        "battery_capacity_kwh": battery_kwh,
        "meters": meters
    }


def main():
    print("Generating 3000 homes across 11 regions...")

    # Calculate homes per region (evenly distributed)
    total_homes = 3000
    homes_per_region = total_homes // len(REGIONS)

    all_homes = {}
    index = 1

    for region, cities in REGIONS.items():
        print(f"\nGenerating {region}...")
        regional_homes = []

        for _ in range(homes_per_region):
            home = generate_home(index, region, cities)
            regional_homes.append(home)
            index += 1

        all_homes[region] = regional_homes

        # Save to file
        filename = f"{region}_homes.json"
        with open(filename, 'w') as f:
            json.dump(regional_homes, f, indent=2)
        print(f"✓ Saved {len(regional_homes)} homes to {filename}")

    # Save complete list
    all_homes_list = [home for homes in all_homes.values() for home in homes]
    with open("all_3000_homes.json", 'w') as f:
        json.dump(all_homes_list, f, indent=2)

    print(f"\n✅ Generation complete!")
    print(f"   Total: {len(all_homes_list)} homes across {len(REGIONS)} regions")

    # Print summary
    print("\n=== Regional Distribution ===")
    for region, homes in all_homes.items():
        print(f"  {region}: {len(homes)} homes")


if __name__ == "__main__":
    main()
