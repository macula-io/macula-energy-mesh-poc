defmodule CortexIqDashboard.Repo do
  use Ecto.Repo,
    otp_app: :cortex_iq_dashboard,
    adapter: Ecto.Adapters.Postgres
end
