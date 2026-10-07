FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04

# The distribution's Docker daemon package, so the feature finds dockerd at build time. policy-rc.d keeps the
# package from starting the daemon during the image build; it stays, as this image only runs tests.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/*

# A daemon.json and a copy of it: with configureDocker disabled the file must stay byte-identical.
RUN mkdir -p /etc/docker \
    && printf '%s\n' '{"log-level": "warn"}' > /etc/docker/daemon.json \
    && cp /etc/docker/daemon.json /etc/docker/daemon.json.seeded
