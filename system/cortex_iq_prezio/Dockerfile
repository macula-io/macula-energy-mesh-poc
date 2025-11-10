####################################################################################################
# CortexIQ Prezio Adapter
# API adapter that polls Prezio API and publishes WAMP events
####################################################################################################

ARG ELIXIR_VERSION=1.18.1
ARG OTP_VERSION=26.2.5.6
ARG ALPINE_VERSION=3.20.3

####################################################################################################
# Stage 1: Builder
####################################################################################################
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy this application's mix files
# Cache bust argument (forces fresh dependency fetch)
ARG CACHE_BUST

COPY cortex_iq_prezio/mix.exs ./
COPY cortex_iq_prezio/config ./config

# Copy path dependencies (required for compilation)
COPY cortex_iq_core ../cortex_iq_core
COPY macula_sdk ../macula_sdk

# Get dependencies
RUN mix deps.get --only prod

# Copy application source
COPY cortex_iq_prezio/lib ./lib

# Compile
RUN mix compile

# Build release
RUN mix release cortex_iq_prezio

####################################################################################################
# Stage 2: Runtime
####################################################################################################
FROM alpine:${ALPINE_VERSION} AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    openssl \
    libncurses6 \
    libstdc++6 \
    libssl3 && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -g 1000 cortexiq && \
    useradd -u 1000 -g cortexiq -m -s /bin/bash cortexiq

WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=cortexiq:cortexiq /app/_build/prod/rel/cortex_iq_prezio ./

USER cortexiq

# Runtime environment
ENV HOME=/app
ENV LANG=C.UTF-8

# Erlang VM memory optimization for containers
ENV ERL_MAX_PORTS=1024

# Default environment variables (can be overridden)
ENV BONDY_URL=ws://bondy.macula-hub.svc.cluster.local:18080/ws
ENV BONDY_REALM=be.cortexiq.energy
ENV POLL_INTERVAL_MS=7200000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/app/bin/cortex_iq_prezio", "rpc", "1 + 1"]

ENTRYPOINT ["/app/bin/cortex_iq_prezio"]
CMD ["start"]
