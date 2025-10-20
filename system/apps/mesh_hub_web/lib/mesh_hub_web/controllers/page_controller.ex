defmodule MeshHubWeb.PageController do
  use MeshHubWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
