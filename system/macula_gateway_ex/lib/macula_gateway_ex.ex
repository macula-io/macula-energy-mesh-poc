defmodule MaculaGatewayEx do
  @moduledoc """
  Macula Gateway for Elixir - Embedded P2P Mesh Networking (Proprietary).

  This library enables peer-to-peer mesh networking by embedding a Macula gateway
  directly in your application. Unlike the free `macula_client_ex` which connects
  to a central gateway, this creates a fully decentralized mesh where each node
  is both a client and a gateway.

  ## Architecture

  **Client Mode** (Free - `macula_client_ex`):
  ```
  App A  ──→  Central Gateway  ←──  App B
  ```

  **Embedded Gateway Mode** (This Library):
  ```
  App A (with gateway)  ←→  App B (with gateway)
         ↕                       ↕
  App C (with gateway)  ←→  App D (with gateway)
  ```

  ## Usage

  Start an embedded gateway in your application's supervision tree:

  ```elixir
  # In your application.ex
  children = [
    {MaculaGatewayEx, port: 9443, realm: "be.cortexiq.energy"}
  ]
  ```

  Then connect clients to your local gateway:

  ```elixir
  {:ok, client} = MaculaClientEx.start_link(
    url: "https://localhost:9443",
    realm: "be.cortexiq.energy"
  )
  ```

  ## Benefits

  - **Zero Network Hops**: Client connects to localhost gateway
  - **True P2P**: No single point of failure
  - **Resilience**: Mesh continues working if nodes go down
  - **Scalability**: No bottleneck from central gateway
  - **Latency**: Direct node-to-node communication

  ## License

  Proprietary - requires access to private Macula packages.
  Contact sales@macula.io for licensing.
  """

  @doc """
  Start an embedded gateway.

  ## Options
  - `:port` - Port to listen on (default: 9443)
  - `:realm` - Realm name (default: "macula.default")
  - `:name` - GenServer name (optional)

  ## Examples

      {:ok, gateway} = MaculaGatewayEx.start_link(
        port: 9443,
        realm: "be.cortexiq.energy"
      )
  """
  defdelegate start_link(opts \\ []), to: MaculaGatewayEx.Gateway

  @doc """
  Get gateway statistics.
  """
  defdelegate get_stats(gateway), to: MaculaGatewayEx.Gateway

  @doc """
  Stop the gateway.
  """
  defdelegate stop(gateway), to: MaculaGatewayEx.Gateway
end
