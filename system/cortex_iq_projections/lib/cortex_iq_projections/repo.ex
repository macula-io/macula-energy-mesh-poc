defmodule CortexIqProjections.Repo do
  use Ecto.Repo,
    otp_app: :cortex_iq_projections,
    adapter: Ecto.Adapters.Postgres

  # Override default_options to use migrations from shared schemas package
  # Note: Use :code.priv_dir/1 instead of Application.app_dir/2 because
  # cortex_iq_dashboard_schemas is a library (not an OTP application)
  @impl true
  def default_options(_operation) do
    [priv: :code.priv_dir(:cortex_iq_dashboard_schemas) |> Path.join("repo") |> to_charlist()]
  end
end
