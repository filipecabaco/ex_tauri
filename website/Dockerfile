ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4
ARG DEBIAN_VERSION=bookworm-20250520-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# Build Stage
FROM ${BUILDER_IMAGE} AS build
ENV MIX_ENV=prod

RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

COPY . .

RUN mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile
RUN mix assets.build
RUN mix release

# Run Stage
FROM ${RUNNER_IMAGE} AS run
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

WORKDIR /app
ENV MIX_ENV=prod
ENV HOME=/app

COPY --from=build /app/_build/${MIX_ENV}/rel/ex_tauri_website ./
COPY --from=build /app/priv ./priv

EXPOSE 4000

CMD ["bin/ex_tauri_website", "start"]
