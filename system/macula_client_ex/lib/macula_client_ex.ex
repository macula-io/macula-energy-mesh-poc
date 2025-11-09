defmodule MaculaClientEx do
  @moduledoc """
  Macula Client for Elixir - HTTP/3 Transport (Free, Open Source).

  This is the free Macula client that connects to Macula gateways using HTTP/3 (QUIC).
  It provides a compatibility layer for applications migrating from WAMP-based systems.

  ## Migration Guide

  The API remains largely the same, with only transport-level changes:

  ### Old (WAMP):
  ```elixir
  {:ok, client} = MaculaSdk.Wamp.Client.start_link(
    url: "ws://localhost:18082/ws",
    realm: "be.cortexiq.energy"
  )
  ```

  ### New (HTTP/3):
  ```elixir
  {:ok, client} = MaculaClientEx.start_link(
    url: "https://localhost:9443",
    realm: "be.cortexiq.energy"
  )
  ```

  All pub/sub and RPC operations remain identical.

  ## Architecture

  This Elixir client is a thin wrapper around the Erlang `macula_sdk` module:

  - **Erlang Layer** (`macula_sdk`): Core QUIC/HTTP/3 implementation
  - **Elixir Layer** (`MaculaClientEx.Client`): Idiomatic Elixir API

  ## Key Differences from WAMP

  1. **Transport**: HTTP/3 (QUIC) instead of WebSocket
  2. **URL Scheme**: `https://` instead of `ws://` or `wss://`
  3. **Connection**: Single bidirectional stream instead of WebSocket
  4. **Encoding**: MessagePack instead of JSON (internal)
  5. **Payload**: JSON for application data (same as WAMP)

  ## Features

  - ✅ Pub/Sub messaging
  - ✅ RPC (Remote Procedure Calls)
  - ✅ Multiple concurrent subscriptions
  - ✅ Connection management
  - ✅ Error handling
  - ⏳ Connection pooling (roadmap)
  - ⏳ Automatic reconnection (roadmap)
  - ⏳ Authentication (roadmap)
  """

  @doc """
  Convenience function to start a client with default options.

  ## Examples

      {:ok, client} = MaculaClientEx.start_link(
        url: "https://localhost:9443",
        realm: "be.cortexiq.energy"
      )
  """
  defdelegate start_link(opts \\ []), to: MaculaClientEx.Client

  @doc """
  Publish a message to a topic.

  See `MaculaClientEx.Client.publish/5` for details.
  """
  defdelegate publish(client, topic, args \\ [], kwargs \\ %{}, options \\ %{}),
    to: MaculaClientEx.Client

  @doc """
  Subscribe to a topic.

  See `MaculaClientEx.Client.subscribe/4` for details.
  """
  defdelegate subscribe(client, topic, handler_fun, options \\ %{}),
    to: MaculaClientEx.Client

  @doc """
  Call a remote procedure.

  See `MaculaClientEx.Client.call/5` for details.
  """
  defdelegate call(client, procedure, args \\ [], kwargs \\ %{}, options \\ %{}),
    to: MaculaClientEx.Client

  @doc """
  Get client status.

  See `MaculaClientEx.Client.status/1` for details.
  """
  defdelegate status(client), to: MaculaClientEx.Client

  @doc """
  Stop the client.

  See `MaculaClientEx.Client.stop/1` for details.
  """
  defdelegate stop(client), to: MaculaClientEx.Client
end
