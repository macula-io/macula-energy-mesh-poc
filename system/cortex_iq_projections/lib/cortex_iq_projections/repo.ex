defmodule CortexIqProjections.Repo do
  use Ecto.Repo,
    otp_app: :cortex_iq_projections,
    adapter: Ecto.Adapters.Postgres

  # Override default_options to use migrations from shared schemas package
  @impl true
  def default_options(_operation) do
    [priv: Application.app_dir(:cortex_iq_dashboard_schemas, "priv/repo")]
  end
end
