defmodule MaculaGatewayService do
  @moduledoc """
  Standalone Macula Gateway Service.

  This service runs a single Macula gateway for a city or region.
  All applications in the city connect to this shared gateway as clients.

  ## Architecture

  **Single Gateway Per City (Simplified Hub-Spoke)**:
  ```
  City A Gateway (port 9443)
      ↕
  ┌───┼───┬───┼───┐
  │   │   │   │   │
  App1 App2 App3 App4 App5
  (all connect to localhost:9443)
  ```

  ## Configuration

  Environment variables:
  - `MACULA_GATEWAY_PORT` - Port to listen on (default: 9443)
  - `MACULA_REALM` - Realm name (default: "be.cortexiq.energy")

  ## Usage

  Start the gateway service:

  ```bash
  MACULA_GATEWAY_PORT=9443 MACULA_REALM=be.cortexiq.energy mix run --no-halt
  ```

  Or in a Docker container:

  ```dockerfile
  ENV MACULA_GATEWAY_PORT=9443
  ENV MACULA_REALM=be.cortexiq.energy
  CMD ["mix", "run", "--no-halt"]
  ```
  """
end
