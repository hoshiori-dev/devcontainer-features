FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# The distribution's Docker daemon package, so the feature finds dockerd at build time. policy-rc.d keeps the
# package from starting the daemon during the image build; it stays, as this image only runs tests.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/*

# A zero-length daemon.json, which the feature treats as {}.
RUN mkdir -p /etc/docker && : > /etc/docker/daemon.json
