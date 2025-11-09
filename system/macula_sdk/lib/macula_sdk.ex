defmodule MaculaSdk do
  @moduledoc """
  Macula SDK for Elixir - HTTP/3 Transport.

  This is the new Macula SDK that uses HTTP/3 (QUIC) instead of WAMP.
  It provides a compatibility layer for applications migrating from the
  legacy WAMP-based SDK.

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
  {:ok, client} = MaculaSdk.Client.start_link(
    url: "https://localhost:9443",
    realm: "be.cortexiq.energy"
  )
  ```

  All pub/sub and RPC operations remain identical.

  ## Architecture

  This Elixir SDK is a thin wrapper around the Erlang `macula_sdk` module:

  - **Erlang Layer** (`macula_sdk`): Core QUIC/HTTP/3 implementation
  - **Elixir Layer** (`MaculaSdk.Client`): Idiomatic Elixir API

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

      {:ok, client} = MaculaSdk.start_link(
        url: "https://localhost:9443",
        realm: "be.cortexiq.energy"
      )
  """
  defdelegate start_link(opts \\ []), to: MaculaSdk.Client

  @doc """
  Publish a message to a topic.

  See `MaculaSdk.Client.publish/5` for details.
  """
  defdelegate publish(client, topic, args \\ [], kwargs \\ %{}, options \\ %{}),
    to: MaculaSdk.Client

  @doc """
  Subscribe to a topic.

  See `MaculaSdk.Client.subscribe/4` for details.
  """
  defdelegate subscribe(client, topic, handler_fun, options \\ %{}),
    to: MaculaSdk.Client

  @doc """
  Call a remote procedure.

  See `MaculaSdk.Client.call/5` for details.
  """
  defdelegate call(client, procedure, args \\ [], kwargs \\ %{}, options \\ %{}),
    to: MaculaSdk.Client

  @doc """
  Get client status.

  See `MaculaSdk.Client.status/1` for details.
  """
  defdelegate status(client), to: MaculaSdk.Client

  @doc """
  Stop the client.

  See `MaculaSdk.Client.stop/1` for details.
  """
  defdelegate stop(client), to: MaculaSdk.Client
end
