# MaculaGatewayEx

Elixir wrapper for embedded Macula Gateway - enables peer-to-peer mesh networking.

## Installation

**Note**: This is a proprietary library requiring access to private Macula packages.

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:macula_gateway_ex, git: "https://github.com/macula-io/macula-energy-mesh-poc", sparse: "system/macula_gateway_ex"}
  ]
end
```

## Usage

### 1. Start Embedded Gateway

In your application supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start embedded gateway
      {MaculaGatewayEx, port: 9443, realm: "my.realm"},

      # Start client connecting to local gateway
      {MaculaClientEx,
        url: "https://localhost:9443",
        realm: "my.realm",
        name: MyApp.MaculaClient}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 2. Use Client as Normal

```elixir
# Publish
MaculaClientEx.publish(MyApp.MaculaClient, "my.topic", [], %{data: "value"})

# Subscribe
MaculaClientEx.subscribe(MyApp.MaculaClient, "my.topic", fn topic, event ->
  IO.inspect({topic, event})
end)
```

## Architecture

**Before (Client Mode)**:
```
App A  ──→  Central Gateway  ←──  App B
```

**After (Embedded Gateway)**:
```
App A (with gateway)  ←→  App B (with gateway)
       ↕                       ↕
App C (with gateway)  ←→  App D (with gateway)
```

## Benefits

- **Zero Network Hops**: Client connects to localhost
- **True P2P**: No single point of failure
- **Resilience**: Mesh continues if nodes go down
- **Scalability**: No central bottleneck

## License

Proprietary - contact sales@macula.io
