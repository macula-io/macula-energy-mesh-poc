####################################################################################################
# MaculaOs - WAMP Gateway Sidecar
# Secure proxy between application containers and Bondy WAMP router
#
# Features:
# - API key authentication
# - Usage metering
# - Connection resilience (automatic retry/reconnect)
# - Namespace isolation
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
    build-base

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY macula_os/mix.exs macula_os/mix.lock ./
COPY macula_os/config ./config

# Get dependencies
RUN mix deps.get --only prod

# Copy application source
COPY macula_os/lib ./lib

# Compile
RUN mix compile

# Build release
RUN mix release macula_os

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
RUN addgroup -g 1000 macula && \
    adduser -D -u 1000 -G macula macula

WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=macula:macula /app/_build/prod/rel/macula_os ./

USER macula

# Runtime environment
ENV HOME=/app
ENV LANG=C.UTF-8

# Default environment variables (can be overridden)
ENV MACULA_PORT=8080
ENV BONDY_URL=ws://172.20.0.2:30080/ws
ENV BONDY_REALM=be.cortexiq.energy

# Expose proxy port (only accessible from pod localhost)
EXPOSE 8080

# Health check - check if server is responding
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app/bin/macula_os", "rpc", "1 + 1"]

ENTRYPOINT ["/app/bin/macula_os"]
CMD ["start"]
