# The Ubuntu compatibility image with apt-ftparchive and gpg, with which the scenario's script publishes a signed
# repository of its own (repository.sh). The package index goes again: the compatibility image ships none.
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04

RUN apt-get update --error-on=any \
  && apt-get install --yes --no-install-recommends apt-utils gnupg \
  && rm -rf /var/lib/apt/lists/*
