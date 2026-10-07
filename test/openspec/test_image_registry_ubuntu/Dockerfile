# "Registry configured in the image": before the feature installs, root's npm configuration names
# an unreachable registry for the @fission-ai scope, which a --registry flag does not override.
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04

RUN printf '@fission-ai:registry=https://example.invalid/\n' >/root/.npmrc
