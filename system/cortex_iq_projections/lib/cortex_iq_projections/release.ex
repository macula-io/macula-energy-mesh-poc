defmodule CortexIqProjections.Release do
  @moduledoc """
  Release tasks for CortexIQ Projections.

  Used for running migrations in production releases.
  """
  @app :cortex_iq_projections

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, migrations_path(), :up, all: true))
    end
  end

  defp migrations_path do
    # Migrations are in cortex_iq_dashboard_schemas package
    :code.priv_dir(:cortex_iq_dashboard_schemas)
    |> Path.join("repo/migrations")
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
