# Build stage
FROM hexpm/elixir:1.16.2-erlang-26.2.5-alpine-3.20.1 AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

# Copy shared libraries first (for better layer caching)
COPY bot_army_library_core ./bot_army_library_core/
COPY bot_army_library_runtime ./bot_army_library_runtime/

# Copy app
COPY bot_army_bridge_lite ./bot_army_bridge_lite/

WORKDIR /app/bot_army_bridge_lite

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix release --overwrite

# Runtime stage
FROM alpine:3.20 AS runtime

RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app
COPY --from=builder /app/bot_army_bridge_lite/_build/prod/rel/bridge_lite ./

ENV MIX_ENV=prod
ENV NATS_SERVERS=nats://nats:4222

EXPOSE 9090

CMD ["bridge_lite", "start"]