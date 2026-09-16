FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        python3 \
        tar \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
        https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh \
        -o /tmp/setup-codex.sh \
    && sh /tmp/setup-codex.sh --root \
    && rm /tmp/setup-codex.sh

ENV PATH="/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override:/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin:/opt/codex/runtimes/codex-primary-runtime/dependencies/node/bin:/opt/codex/runtimes/codex-primary-runtime/dependencies/bin:/root/.local/bin:${PATH}:/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/fallback"

WORKDIR /workspace

ENTRYPOINT ["codex", "-c", "sandbox_mode=\"danger-full-access\"", "app-server"]
CMD ["--listen", "ws://127.0.0.1:4500", "--remote-control"]