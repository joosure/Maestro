# syntax=docker/dockerfile:1.7

ARG ELIXIR_IMAGE=elixir:1.19.5-otp-28-slim
ARG RUNTIME_IMAGE=debian:trixie-slim
ARG OPENCODE_VERSION=1.14.33
ARG CODEBUDDY_VERSION=2.99.1

FROM ${ELIXIR_IMAGE} AS build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV MIX_ENV=prod

WORKDIR /app/elixir

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
  && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force \
  && mix local.rebar --force

COPY elixir/mix.exs elixir/mix.lock ./
COPY elixir/mise.toml ./
COPY elixir/config ./config

RUN --mount=type=cache,target=/root/.hex \
  --mount=type=cache,target=/root/.cache/rebar3 \
  mix deps.get --only prod \
  && mix deps.compile

COPY elixir ./

RUN mix compile \
  && mix release symphony --overwrite

FROM ${RUNTIME_IMAGE} AS runtime-base

ARG SYMPHONY_UID=10001
ARG SYMPHONY_GID=10001

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.title="Maestro Symphony Elixir Runtime" \
  org.opencontainers.image.description="Containerized Maestro/Symphony Elixir control-plane runtime" \
  org.opencontainers.image.source="https://github.com/joosure/Maestro"

ENV LANG=C.UTF-8
ENV MIX_ENV=prod
ENV HOME=/home/symphony
ENV SYMPHONY_WORKSPACE_ROOT=/workspaces
ENV HOST=0.0.0.0
ENV PORT=4000

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    libstdc++6 \
    libtinfo6 \
    locales \
    openssl \
    openssh-client \
  && sed -i '/C.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --gid "${SYMPHONY_GID}" symphony \
  && useradd --uid "${SYMPHONY_UID}" --gid "${SYMPHONY_GID}" --create-home --shell /bin/bash symphony \
  && install -d -o symphony -g symphony /workspaces /app/.symphony /app/var /app/log

COPY --from=build --chown=symphony:symphony /app/elixir/_build/prod/rel/symphony ./
COPY docker/app/entrypoint.sh /usr/local/bin/symphony-entrypoint

RUN chmod +x /usr/local/bin/symphony-entrypoint

USER symphony

EXPOSE 4000

STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/symphony-entrypoint"]
CMD ["serve"]

FROM runtime-base AS runtime-agent

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    gh \
    nodejs \
    npm \
    python3 \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN install -d -o symphony -g symphony /home/symphony/.ssh

USER symphony

FROM runtime-agent AS runtime-agent-opencode

ARG OPENCODE_VERSION=1.14.33

USER root

RUN npm install --global "opencode-ai@${OPENCODE_VERSION}" \
  && npm cache clean --force \
  && install -d -o symphony -g symphony \
    /home/symphony/.cache/opencode \
    /home/symphony/.config/opencode \
    /home/symphony/.local/share/opencode \
    /home/symphony/.local/state/opencode \
  && chown -R symphony:symphony /home/symphony/.cache /home/symphony/.config /home/symphony/.local

USER symphony

RUN opencode --version

FROM runtime-agent AS runtime-agent-codex

ARG CODEX_VERSION=0.135.0

ENV CODEX_HOME=/home/symphony/.codex

USER root

RUN npm install --global "@openai/codex@${CODEX_VERSION}" \
  && npm cache clean --force \
  && install -d -o symphony -g symphony "${CODEX_HOME}" /home/symphony/.local/share/codex \
  && chown -R symphony:symphony "${CODEX_HOME}" /home/symphony/.local

USER symphony

RUN codex --version

FROM runtime-agent AS runtime-agent-claude-code

ARG CLAUDE_CODE_VERSION=2.1.158

ENV CLAUDE_CONFIG_DIR=/home/symphony/.claude

USER root

RUN npm install --global "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && npm cache clean --force \
  && install -d -o symphony -g symphony /home/symphony/.claude /home/symphony/.local/share/claude \
  && chown -R symphony:symphony /home/symphony/.claude /home/symphony/.local

USER symphony

RUN claude --version

FROM runtime-agent AS runtime-agent-codebuddy

ARG CODEBUDDY_VERSION=2.99.1

ENV CODEBUDDY_CONFIG_DIR=/home/symphony/.codebuddy
ENV DISABLE_AUTOUPDATER=1

USER root

RUN npm install --global "@tencent-ai/codebuddy-code@${CODEBUDDY_VERSION}" \
  && npm cache clean --force \
  && install -d -o symphony -g symphony \
    /home/symphony/.codebuddy \
    /home/symphony/.local/share/codebuddy \
  && chown -R symphony:symphony /home/symphony/.codebuddy /home/symphony/.local

USER symphony

RUN codebuddy --version
