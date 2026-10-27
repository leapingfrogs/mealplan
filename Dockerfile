# syntax=docker/dockerfile:1

# Production image: Elixir release on a slim Debian runtime, non-root, compatible
# with a read-only root filesystem (writable /tmp only).
#
# Base images are pinned by digest and kept current by Dependabot. The Elixir and
# Erlang versions in the builder tag must match .tool-versions (checked by
# `just docker-versions`, which CI runs).

# ---------------------------------------------------------------------------
# Build stage
# ---------------------------------------------------------------------------
FROM hexpm/elixir:1.20.4-erlang-29.1.2-debian-trixie-20261005-slim@sha256:c2cc01de71909db898a4d9ee3a379dcf1b1403b292a5b1ff76f4f0e133e75077 AS build

# build-essential: argon2_elixir NIF; git: git-sourced asset deps (heroicons, daisyui)
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Dependencies first so they're cached until mix.exs/mix.lock change.
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod --check-locked
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile
RUN mix assets.setup

# Application code. Compile before building assets: LiveView's colocated hooks
# are extracted at compile time and bundled by esbuild.
COPY priv priv
COPY lib lib
COPY assets assets
RUN mix compile
RUN mix assets.deploy

# runtime.exs and release overlays only affect the release step.
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM debian:trixie-20261005-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

ARG VERSION=dev
ARG REVISION=unknown

LABEL org.opencontainers.image.title="mealplan" \
      org.opencontainers.image.description="Family meal planning and recipe management" \
      org.opencontainers.image.source="https://github.com/leapingfrogs/mealplan" \
      org.opencontainers.image.licenses="NONE" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

# Only what the BEAM needs at runtime: C++ runtime (NIFs), libcrypto/libssl
# (crypto, ssl), libsctp (loaded by the socket NIF; warns if missing) and CA
# roots (SMTP TLS verification). libtinfo is in the base.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 libssl3t64 libsctp1 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# C.UTF-8 ships with glibc, so no locales package is needed. The release writes
# its temporary files and any crash dump to /tmp, the only writable path.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_ENV=prod \
    PORT=4000 \
    RELEASE_TMP=/tmp \
    ERL_CRASH_DUMP=/tmp/erl_crash.dump

RUN groupadd --system --gid 10001 mealplan \
 && useradd --system --uid 10001 --gid mealplan --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin mealplan

WORKDIR /app
# Owned by root and not writable by the app user: the code can't modify itself.
COPY --from=build /app/_build/prod/rel/mealplan ./

USER 10001:10001
EXPOSE 4000
STOPSIGNAL SIGTERM

# No curl in the image: bash's /dev/tcp does a minimal HTTP request. The Host
# header is localhost, which is exempt from the HTTPS redirect.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${PORT} && printf 'GET /health/live HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && head -n1 <&3 | grep -q ' 200 '"]

# Runs pending migrations, then starts the server (rel/overlays/bin/server).
CMD ["/app/bin/server"]
