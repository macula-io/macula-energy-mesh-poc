defmodule CortexIqDashboardWeb.PageController do
  use CortexIqDashboardWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
