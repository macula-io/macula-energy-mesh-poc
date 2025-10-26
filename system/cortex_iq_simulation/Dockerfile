# Multi-stage Dockerfile for CortexIQ Simulation Service
# This service provides simulation infrastructure (clock) for the CortexIQ platform

# Build stage
FROM hexpm/elixir:1.18.1-erlang-26.2.5.6-alpine-3.20.3 AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base

# Prepare build directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency specs
COPY cortex_iq_simulation/mix.exs cortex_iq_simulation/mix.lock ./

# Copy dependency source (MaculaOs)
COPY macula_os ../macula_os

# Set production environment
ENV MIX_ENV=prod

# Get dependencies
RUN mix deps.get --only prod

# Copy application source
COPY cortex_iq_simulation/config ./config
COPY cortex_iq_simulation/lib ./lib

# Compile application
RUN mix compile

# Build release
RUN mix release cortex_iq_simulation

# Runtime stage
FROM alpine:3.20.3

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc

# Create non-root user
RUN addgroup -g 1000 cortexiq && \
    adduser -D -u 1000 -G cortexiq cortexiq

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=cortexiq:cortexiq /app/_build/prod/rel/cortex_iq_simulation ./

# Switch to non-root user
USER cortexiq

# Expose no ports (WAMP client only)

# Environment variables with defaults
ENV BONDY_URL=ws://172.20.0.2:30080/ws \
    BONDY_REALM=be.cortexiq.energy \
    SIMULATION_SPEED=105120 \
    SIMULATION_START_DATE=2025-01-01T00:00:00Z

# Start the application
CMD ["/app/bin/cortex_iq_simulation", "start"]
