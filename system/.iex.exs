# .iex.exs - Automatically loaded by IEx
# Starts all bot applications for local development

if Code.ensure_loaded?(IEx) do
  # Only run in development
  if Mix.env() == :dev do
    # Start bot applications
    IO.puts("\n🚀 Starting bot applications...")

    case Application.ensure_all_started(:mesh_edge_homes) do
      {:ok, _} -> IO.puts("✅ mesh_edge_homes started")
      {:error, reason} -> IO.puts("❌ Failed to start mesh_edge_homes: #{inspect(reason)}")
    end

    case Application.ensure_all_started(:mesh_edge_utilities) do
      {:ok, _} -> IO.puts("✅ mesh_edge_utilities started")
      {:error, reason} -> IO.puts("❌ Failed to start mesh_edge_utilities: #{inspect(reason)}")
    end

    IO.puts("📊 Dashboard at http://localhost:4000\n")
  end
end
