#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y shellcheck

curl -fsSL https://deno.land/install.sh | CI=1 sh

curl -fsSL \
  https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh \
  | sh

deno install --global --force \
  --allow-read \
  --allow-write \
  --allow-env \
  --allow-sys=cpus,homedir,uid \
  --allow-net=edge.openspec.dev \
  npm:@fission-ai/openspec@latest

pre-commit install
