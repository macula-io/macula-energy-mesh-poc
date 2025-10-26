defmodule MaculaOs.Proxy.Server do
  @moduledoc """
  HTTP/WebSocket server accepting connections from application containers.

  Listens on localhost (configurable port) and upgrades to WebSocket
  for WAMP protocol communication.
  """
  require Logger

  def child_spec(opts) do
    port = Keyword.get(opts, :port, 8080)
    scheme = Keyword.get(opts, :scheme, :http)

    Plug.Cowboy.child_spec(
      scheme: scheme,
      plug: __MODULE__,
      options: [port: port, ip: {127, 0, 0, 1}]
    )
  end

  use Plug.Router

  plug :match
  plug :dispatch

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(MaculaOs.Proxy.WebSocketHandler, %{}, timeout: 60_000)
    |> halt()
  end

  get "/health" do
    # Health check endpoint
    upstream_status = MaculaOs.Proxy.Upstream.status()

    response = Jason.encode!(%{
      status: "healthy",
      upstream: upstream_status
    })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, response)
  end

  get "/metrics" do
    # Metrics endpoint for monitoring
    all_stats = MaculaOs.Metering.get_all_stats()

    # Format as Prometheus-style metrics
    metrics = format_prometheus_metrics(all_stats)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  ## Private Functions

  defp format_prometheus_metrics(stats) do
    # Simple Prometheus text format
    lines = [
      "# HELP macula_os_wamp_operations_total Total WAMP operations by API key and type",
      "# TYPE macula_os_wamp_operations_total counter"
    ]

    metric_lines = Enum.flat_map(stats, fn {api_key, %{publish: pub, subscribe: sub, call: call}} ->
      [
        ~s(macula_os_wamp_operations_total{api_key="#{api_key}",operation="publish"} #{pub}),
        ~s(macula_os_wamp_operations_total{api_key="#{api_key}",operation="subscribe"} #{sub}),
        ~s(macula_os_wamp_operations_total{api_key="#{api_key}",operation="call"} #{call})
      ]
    end)

    Enum.join(lines ++ metric_lines, "\n") <> "\n"
  end
end
