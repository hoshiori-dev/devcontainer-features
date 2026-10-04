FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04

# The distribution's Docker daemon package, so the feature finds dockerd at build time. policy-rc.d keeps the
# package from starting the daemon during the image build; it stays, as this image only runs tests.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/*

# Settings the feature must keep: another runtime, a default runtime, and a log level.
RUN mkdir -p /etc/docker \
    && printf '%s\n' '{"default-runtime": "custom", "log-level": "warn",' \
        '"runtimes": {"custom": {"path": "/usr/bin/runc"}}}' > /etc/docker/daemon.json
