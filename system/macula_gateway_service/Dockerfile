# Multi-stage Dockerfile for Macula Gateway Service
# Standalone HTTP/3 (QUIC) gateway for city deployments

# syntax=docker/dockerfile:1.4
# Build stage
FROM hexpm/elixir:1.18.1-erlang-26.2.5.6-alpine-3.20.3 AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    cmake \
    ninja \
    perl \
    linux-headers \
    openssl-dev

# Prepare build directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency specs
COPY macula_gateway_service/mix.exs macula_gateway_service/mix.lock ./

# Copy dependency source (Macula Gateway Ex wrapper + Erlang libraries)
COPY macula_gateway_ex ../macula_gateway_ex
COPY macula_client_ex ../macula_client_ex

# Copy Erlang macula libraries (required by macula_gateway_ex)
COPY --from=macula_libs /macula/apps/macula_gateway /home/rl/work/github.com/macula-io/macula/apps/macula_gateway
COPY --from=macula_libs /macula/apps/macula_pubsub /home/rl/work/github.com/macula-io/macula/apps/macula_pubsub
COPY --from=macula_libs /macula/apps/macula_rpc /home/rl/work/github.com/macula-io/macula/apps/macula_rpc
COPY --from=macula_libs /macula/apps/macula_topology /home/rl/work/github.com/macula-io/macula/apps/macula_topology

# Set production environment
ENV MIX_ENV=prod

# Get dependencies
RUN mix deps.get --only prod

# Copy application source
COPY macula_gateway_service/config ./config
COPY macula_gateway_service/lib ./lib

# Compile application
RUN mix compile

# Build release
RUN mix release macula_gateway_service

# Runtime stage
FROM alpine:3.20.3

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc

# Create non-root user
RUN addgroup -g 1000 macula && \
    adduser -D -u 1000 -G macula macula

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=macula:macula /app/_build/prod/rel/macula_gateway_service ./

# Switch to non-root user
USER macula

# Expose QUIC port
EXPOSE 9443/udp

# Environment variables with defaults
ENV MACULA_GATEWAY_PORT=9443 \
    MACULA_REALM=be.cortexiq.energy

# Start the application
CMD ["/app/bin/macula_gateway_service", "start"]
