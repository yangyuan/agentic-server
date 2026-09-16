FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base

USER root

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /opt/agentic/proxy

RUN curl -fsSL \
	https://raw.githubusercontent.com/yangyuan/agentic-server/master/proxy/setup.sh \
	-o /opt/agentic/proxy/setup.sh \
	&& sh /opt/agentic/proxy/setup.sh

ENTRYPOINT ["/opt/agentic/proxy/.venv/bin/python", "/opt/agentic/proxy/proxy.py"]