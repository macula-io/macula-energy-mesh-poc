#!/usr/bin/env elixir

# Massive Seed Data Generator for Bondy Stress Testing
# Generates 50,000 homes split into 500-home chunks for easy distribution
#
# Usage: elixir generate_massive_seed_data.exs

# Load the base generator
Code.require_file("generate_expanded_seed_data.exs", __DIR__)

defmodule MassiveSeedDataGenerator do
  @moduledoc """
  Generates 50,000 homes for Bondy stress testing.
  Creates multiple 500-home files per region for distribution across many replicas.
  """

  def run(total_homes \\ 50_000, chunk_size \\ 500) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Massive Seed Data Generator for Bondy Stress Testing")
    IO.puts("Generating #{total_homes} homes in #{chunk_size}-home chunks")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Generate all homes using the existing generator
    homes = ExpandedSeedDataGenerator.generate_all_homes(total_homes)

    # Group by region
    regional_homes = Enum.group_by(homes, fn h -> h["address"]["region"] end)

    IO.puts("\nRegional Distribution:")
    IO.puts(String.duplicate("-", 60))

    # For each region, split into chunks and save
    regional_homes
    |> Enum.sort_by(fn {region, _} -> region end)
    |> Enum.each(fn {region, region_homes} ->
      homes_count = length(region_homes)
      chunks = Enum.chunk_every(region_homes, chunk_size)
      chunk_count = length(chunks)

      IO.puts("#{String.pad_trailing(region, 35)} #{homes_count} homes → #{chunk_count} files")

      # Save each chunk
      chunks
      |> Enum.with_index(1)
      |> Enum.each(fn {chunk, idx} ->
        filename = chunk_filename(region, idx, chunk_count)
        ExpandedSeedDataGenerator.save_to_file(chunk, filename)
      end)
    end)

    # Also save complete list
    ExpandedSeedDataGenerator.save_to_file(homes, "all_#{total_homes}_homes.json")

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("✅ Massive seed data generation complete!")
    IO.puts("   Total: #{length(homes)} homes")
    IO.puts("   Regions: #{map_size(regional_homes)}")
    IO.puts("   Chunk size: #{chunk_size} homes per file")

    total_files = regional_homes
      |> Enum.map(fn {_, region_homes} -> ceil(length(region_homes) / chunk_size) end)
      |> Enum.sum()

    IO.puts("   Total files: #{total_files + 1} (#{total_files} chunks + 1 combined)")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp chunk_filename(region, chunk_idx, total_chunks) do
    # Map region name to short name
    short_name = case region do
      "belgium_flanders_west" -> "flanders_west"
      "belgium_flanders_central" -> "flanders_central"
      "belgium_flanders_east" -> "flanders_east"
      "belgium_brussels" -> "brussels"
      "belgium_wallonia_north" -> "wallonia_north"
      "belgium_wallonia_south" -> "wallonia_south"
      "netherlands_west" -> "netherlands_west"
      "netherlands_north" -> "netherlands_north"
      "netherlands_central" -> "netherlands_central"
      "netherlands_south" -> "netherlands_south"
      "netherlands_east" -> "netherlands_east"
    end

    # Use padded numbers for better sorting
    pad_width = String.length(Integer.to_string(total_chunks))
    chunk_num = String.pad_leading(Integer.to_string(chunk_idx), pad_width, "0")

    "#{short_name}_homes_chunk_#{chunk_num}.json"
  end
end

# Run if called directly
if System.get_env("MIX_ENV") != "test" do
  {:ok, _} = Application.ensure_all_started(:jason)
  MassiveSeedDataGenerator.run(50_000, 500)
end
