#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y shellcheck

curl -fsSL https://deno.land/install.sh | CI=1 sh

curl -fsSL \
  https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh \
  | sh

openspec_package="$(sed -n 's/^[[:space:]]*\(npm:@fission-ai\/openspec@[0-9][0-9.]*\)[[:space:]]*$/\1/p' \
  "$(dirname "${BASH_SOURCE[0]}")/../.github/actions/setup-tools/action.yml")"
: "${openspec_package:?OpenSpec pin not found in .github/actions/setup-tools/action.yml}"

deno install --global --force \
  --allow-read \
  --allow-write \
  --allow-env \
  --allow-sys=cpus,homedir,uid \
  --allow-net=edge.openspec.dev \
  "${openspec_package}"

pre-commit install
