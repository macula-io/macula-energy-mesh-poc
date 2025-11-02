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
RUN apk add --no-cache \
    git \
    build-base

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy this application's mix files
COPY cortex_iq_homes/mix.exs cortex_iq_homes/mix.lock ./
COPY cortex_iq_homes/config ./config

# Copy path dependencies (required for compilation)
COPY cortex_iq_core ../cortex_iq_core
COPY macula_sdk ../macula_sdk

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
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc

# Create non-root user
RUN addgroup -g 1000 cortexiq && \
    adduser -D -u 1000 -G cortexiq cortexiq

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
ENV MACULA_REALM_URL=ws://bondy:18080/ws
ENV MACULA_REALM=be.cortexiq.energy
ENV NUM_HOMES=25
ENV HOME_ID_OFFSET=0

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/app/bin/cortex_iq_homes", "rpc", "1 + 1"]

ENTRYPOINT ["/app/bin/cortex_iq_homes"]
CMD ["start"]
