defmodule MaculaOs.Wamp do
  @moduledoc """
  WAMP (Web Application Messaging Protocol) client library.

  Provides a simple interface for connecting to WAMP routers (like Bondy)
  and performing pub/sub operations.

  ## Examples

      # Start a client
      {:ok, client} = MaculaOs.Wamp.start_link(
        url: "ws://localhost:18082/ws",
        realm: "app.production"
      )

      # Subscribe to a topic
      MaculaOs.Wamp.subscribe(client, "app.events.user.created", fn topic, event ->
        IO.inspect({topic, event})
      end)

      # Publish an event
      MaculaOs.Wamp.publish(client, "app.events.user.created", [], %{user_id: 123})
  """

  alias MaculaOs.Wamp.Client

  @doc """
  Start a WAMP client connection.

  ## Options
  - `:url` - WebSocket URL (default: ws://localhost:18082/ws)
  - `:realm` - WAMP realm to join (required)
  - `:name` - GenServer name (optional)
  """
  defdelegate start_link(opts \\ []), to: Client

  @doc """
  Publish a message to a topic.
  """
  defdelegate publish(client, topic, args \\ [], kwargs \\ %{}, options \\ %{}), to: Client

  @doc """
  Subscribe to a topic with a handler function.
  """
  defdelegate subscribe(client, topic, handler_fun, options \\ %{}), to: Client

  @doc """
  Get client connection status.
  """
  defdelegate status(client), to: Client

  @doc """
  Stop the client.
  """
  defdelegate stop(client), to: Client
end
