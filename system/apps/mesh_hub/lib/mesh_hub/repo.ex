defmodule MeshHub.Repo do
  use Ecto.Repo,
    otp_app: :mesh_hub,
    adapter: Ecto.Adapters.Postgres
end
