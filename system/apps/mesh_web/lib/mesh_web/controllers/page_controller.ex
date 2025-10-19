defmodule MeshWeb.PageController do
  use MeshWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
