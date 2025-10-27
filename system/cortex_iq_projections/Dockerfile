####################################################################################################
# CortexIQ Projections Service
# Event-driven CQRS write-side projections from WAMP events to PostgreSQL/TimescaleDB
#
# Subscribes to all CortexIQ events and builds read models for dashboard queries
####################################################################################################

ARG ELIXIR_VERSION=1.18.1
ARG OTP_VERSION=26.2.5.6
ARG ALPINE_VERSION=3.20.3

####################################################################################################
# Stage 1: Builder
####################################################################################################
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    postgresql-dev

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy this application's mix files
COPY cortex_iq_projections/mix.exs cortex_iq_projections/mix.lock ./
COPY cortex_iq_projections/config ./config
COPY cortex_iq_projections/rel ./rel

# Copy path dependencies (required for compilation)
COPY cortex_iq_dashboard_schemas ../cortex_iq_dashboard_schemas
COPY cortex_iq_core ../cortex_iq_core
COPY macula_sdk ../macula_sdk

# Get dependencies
RUN mix deps.get --only prod

# Copy application source
COPY cortex_iq_projections/lib ./lib

# Compile
RUN mix compile

# Build release
RUN mix release cortex_iq_projections

####################################################################################################
# Stage 2: Runtime
####################################################################################################
FROM alpine:${ALPINE_VERSION} AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc \
    postgresql-client

# Create non-root user
RUN addgroup -g 1000 cortexiq && \
    adduser -D -u 1000 -G cortexiq cortexiq

WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=cortexiq:cortexiq /app/_build/prod/rel/cortex_iq_projections ./

USER cortexiq

# Runtime environment
ENV HOME=/app
ENV LANG=C.UTF-8

# Erlang VM memory optimization for containers
# Limit max ports to reduce memory pre-allocation from 2GB+ to reasonable levels
ENV ERL_MAX_PORTS=1024

# Default environment variables (can be overridden)
ENV BONDY_URL=ws://bondy.macula-hub.svc.cluster.local:18080/ws
ENV BONDY_REALM=be.cortexiq.energy
ENV DATABASE_URL=ecto://postgres:postgres@postgres.macula-hub.svc.cluster.local/mesh_hub
ENV POOL_SIZE=10

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/app/bin/cortex_iq_projections", "rpc", "1 + 1"]

ENTRYPOINT ["/app/bin/cortex_iq_projections"]
CMD ["start"]
