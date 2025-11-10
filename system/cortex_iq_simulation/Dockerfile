# Multi-stage Dockerfile for CortexIQ Simulation Service
# This service provides simulation infrastructure (clock) for the CortexIQ platform

# syntax=docker/dockerfile:1.4
# Build stage
FROM elixir:1.18-otp-26 AS builder

# Install build dependencies (including cmake for quicer NIF)
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Prepare build directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Cache bust argument (forces fresh dependency fetch)
ARG CACHE_BUST

# Copy dependency specs
COPY cortex_iq_simulation/mix.exs cortex_iq_simulation/mix.lock ./

# Set production environment
ENV MIX_ENV=prod

# Get dependencies (macula_client_ex fetched from Hex.pm)
RUN mix deps.get --only prod

# Copy application source
COPY cortex_iq_simulation/config ./config
COPY cortex_iq_simulation/lib ./lib

# Compile application
RUN mix compile

# Build release
RUN mix release cortex_iq_simulation

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    openssl \
    libssl3 \
    libncurses6 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -g 1000 cortexiq && \
    useradd -u 1000 -g cortexiq -m -s /bin/bash cortexiq

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=cortexiq:cortexiq /app/_build/prod/rel/cortex_iq_simulation ./

# Switch to non-root user
USER cortexiq

# Expose no ports (HTTP/3 client only)

# Environment variables with defaults
ENV MACULA_URL=https://macula-gateway:9443 \
    MACULA_REALM=be.cortexiq.energy \
    SIMULATION_SPEED=105120 \
    SIMULATION_START_DATE=2025-01-01T00:00:00Z

# Start the application
CMD ["/app/bin/cortex_iq_simulation", "start"]
