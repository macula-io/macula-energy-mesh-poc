defmodule Mesh.Repo do
  use Ecto.Repo,
    otp_app: :mesh,
    adapter: Ecto.Adapters.Postgres
end
