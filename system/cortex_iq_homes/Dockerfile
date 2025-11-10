# syntax=docker/dockerfile:1.4
####################################################################################################
# CortexIQ Homes Payload
# Home simulation bots with solar, battery, and contract optimization
#
# Requires MaculaOs for secure realm connectivity
####################################################################################################

ARG ELIXIR_VERSION=1.18.1
ARG OTP_VERSION=27.2
ARG ALPINE_VERSION=3.21.0

####################################################################################################
# Stage 1: Builder
####################################################################################################
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    openssh-client \
    cmake \
    libssl-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy this application's mix files
# Cache bust argument (forces fresh dependency fetch)
ARG CACHE_BUST

COPY cortex_iq_homes/mix.exs cortex_iq_homes/mix.lock ./
COPY cortex_iq_homes/config ./config

# Copy path dependencies (required for compilation)
COPY cortex_iq_core ../cortex_iq_core

# Get dependencies

RUN mix deps.get --only prod

# Copy application source
COPY cortex_iq_homes/lib ./lib
COPY cortex_iq_homes/priv ./priv

# Compile
RUN mix compile

# Build release
RUN mix release cortex_iq_homes

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
COPY --from=builder --chown=cortexiq:cortexiq /app/_build/prod/rel/cortex_iq_homes ./

# Copy priv directory to the correct location for :code.priv_dir/1
COPY --from=builder --chown=cortexiq:cortexiq /app/priv ./lib/cortex_iq_homes-0.1.0/priv

USER cortexiq

# Runtime environment
ENV HOME=/app
ENV LANG=C.UTF-8

# Default environment variables (can be overridden)
ENV MACULA_URL=https://macula-gateway:9443
ENV MACULA_REALM=be.cortexiq.energy
ENV NUM_HOMES=25
ENV HOME_ID_OFFSET=0

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/app/bin/cortex_iq_homes", "rpc", "1 + 1"]

ENTRYPOINT ["/app/bin/cortex_iq_homes"]
CMD ["start"]
