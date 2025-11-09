# Macula Gateway Service

Standalone Macula Gateway for city/region deployments.

## Overview

This service runs a single Macula gateway that all applications in a city connect to as clients. This simplified hub-spoke architecture is ideal for proof-of-concept deployments and smaller-scale systems.

## Architecture

### Single Gateway Per City (Simplified)

```
┌─────────────────────────────────────────────────┐
│         City A (Realm: be.cortexiq.energy)      │
│                                                 │
│   ┌──────────────────────────────────┐         │
│   │  Macula Gateway Service          │         │
│   │  (port 9443)                     │         │
│   └────────┬─────────────────────────┘         │
│            │                                    │
│   ┌────────┼────────┬─────────┬────────┐       │
│   │        │        │         │        │       │
│   ▼        ▼        ▼         ▼        ▼       │
│  App1    App2    App3      App4     App5       │
│  (simulation) (homes) (utilities) (queries) (dashboard) │
│                                                 │
│  All connect to localhost:9443                 │
└─────────────────────────────────────────────────┘
```

### Benefits

- **Simple Deployment**: One gateway per city/region
- **Easy Development**: All apps connect to localhost
- **Port Management**: Single port per city (e.g., 9443 for City A, 9543 for City B)
- **PoC Ready**: Perfect for demonstrations and initial deployments

### Future: Inter-City Mesh

```
City A Gateway         City B Gateway         City C Gateway
(port 9443)    ←────→  (port 9543)    ←────→  (port 9643)
     ↕                      ↕                      ↕
 Apps A1-A5             Apps B1-B5             Apps C1-C5
```

Gateway bridges will enable cross-city communication for federated mesh deployments.

## Usage

### Local Development

Start the gateway service:

```bash
MACULA_GATEWAY_PORT=9443 MACULA_REALM=be.cortexiq.energy mix run --no-halt
```

### Docker Deployment

```dockerfile
FROM elixir:1.18-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Set working directory
WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./
COPY ../macula_gateway_ex ../macula_gateway_ex
COPY ../macula_client_ex ../macula_client_ex

# Install dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

# Copy source
COPY lib ./lib

# Build release
ENV MIX_ENV=prod
RUN mix compile && \
    mix release

FROM alpine:3.19 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/_build/prod/rel/macula_gateway_service ./

ENV MACULA_GATEWAY_PORT=9443
ENV MACULA_REALM=be.cortexiq.energy

CMD ["bin/macula_gateway_service", "start"]
```

### Environment Variables

- `MACULA_GATEWAY_PORT` - Port to listen on (default: 9443)
- `MACULA_REALM` - Realm name (default: "be.cortexiq.energy")

## Client Configuration

Applications connect to the gateway using `macula_client_ex`:

```elixir
# In application.ex
children = [
  {MyApp.SomeSystem,
   macula_url: System.get_env("MACULA_URL", "https://localhost:9443"),
   realm: System.get_env("MACULA_REALM", "be.cortexiq.energy")}
]
```

Environment variables for client apps:
- `MACULA_URL` - Gateway URL (e.g., "https://localhost:9443")
- `MACULA_REALM` - Realm name (must match gateway's realm)

## Next Steps

This simplified architecture is perfect for:
1. ✅ Proof of concept deployments
2. ✅ Single-city/region applications
3. ✅ Development and testing

For production multi-city deployments, consider:
- [ ] Gateway bridges for inter-city communication
- [ ] Discovery services (mDNS, DHT, rendezvous)
- [ ] NAT traversal capabilities
- [ ] Full P2P mesh with `macula_membership` and `macula_topology`

## License

Proprietary - contact sales@macula.io

