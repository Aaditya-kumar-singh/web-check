FROM mcr.microsoft.com/devcontainers/javascript-node:24-bookworm
USER root
RUN apt-get update && apt-get install -y --no-install-recommends chromium traceroute && rm -rf /var/lib/apt/lists/*
