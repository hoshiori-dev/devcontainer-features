# The Ubuntu compatibility image with a package index and the package files of bc, which the scenario then installs
# without a network.
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04

RUN apt-get update --error-on=any \
  && apt-get install --download-only --yes --no-install-recommends bc
