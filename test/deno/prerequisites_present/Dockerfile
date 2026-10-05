# Saves the package listing before the feature runs; the image already has curl,
# ca-certificates, and unzip.
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04
RUN dpkg-query -W >/opt/packages-before.txt
