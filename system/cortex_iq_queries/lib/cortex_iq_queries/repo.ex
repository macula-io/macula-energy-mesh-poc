defmodule CortexIqQueries.Repo do
  use Ecto.Repo,
    otp_app: :cortex_iq_queries,
    adapter: Ecto.Adapters.Postgres
end
