defmodule MaculaSdk.Wamp do
  @moduledoc """
  Convenience wrapper for WAMP client operations.

  This module provides a simpler interface to the WAMP client,
  delegating to MaculaSdk.Wamp.Client.
  """

  alias MaculaSdk.Wamp.Client

  @doc """
  Start a WAMP client connection.

  This is a convenience function that delegates to MaculaSdk.Wamp.Client.start_link/1.

  ## Options

    * `:url` - WebSocket URL to connect to (required)
    * `:realm` - WAMP realm to join (required)
    * `:name` - Optional name for the client process

  ## Examples

      {:ok, client} = MaculaSdk.Wamp.start_link(
        url: "ws://bondy:18080/ws",
        realm: "be.cortexiq.energy"
      )
  """
  defdelegate start_link(opts \\ []), to: Client
end
