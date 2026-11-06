#!/usr/bin/env bash
# Host-side check: install the actual Node Feature after Pi and compare its options with Node-only containers.
# Run from any directory; requires Docker, devcontainer CLI, and jq. Uses isolated scratch workspaces and synthetic
# state only. Optional $1 is a prebuilt image with this checkout's Pi already installed without Node.
set -euo pipefail

repository="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d /tmp/pi-node-composition.XXXXXX)"
containers=()
volumes=()
images=()
image_prefix="pi-node-check-$$"

cleanup() {
  local container volume image
  for container in "${containers[@]}"; do docker rm --force "${container}" >/dev/null 2>&1 || true; done
  for volume in "${volumes[@]}"; do docker volume rm "${volume}" >/dev/null 2>&1 || true; done
  for image in "${images[@]}"; do docker image rm "${image}" >/dev/null 2>&1 || true; done
  rm -rf "${work}"
}
trap cleanup EXIT

up() {
  local workspace="$1" container volume
  devcontainer up --workspace-folder "${workspace}" >"${work}/up.json" 2>"${work}/up.log" || {
    cat "${work}/up.log" >&2
    return 1
  }
  container="$(jq -r .containerId "${work}/up.json")"
  containers+=("${container}")
  volume="$(docker inspect "${container}" --format \
    '{{range .Mounts}}{{if eq .Destination "/var/lib/pi"}}{{.Name}}{{end}}{{end}}')"
  if [[ -n "${volume}" ]]; then volumes+=("${volume}"); fi
}

node_snapshot() {
  # The child container shell expands tool names and command substitutions.
  # shellcheck disable=SC2016
  devcontainer exec --workspace-folder "$1" bash -c '
    set -e
    node --version
    npm --version
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version
    cat /usr/local/share/nvm/alias/default
    command -v node
    for tool in python3 make g++; do command -v "$tool" || true; done
  ' >"$2"
}

mkdir -p "${work}/pi/.devcontainer"
cp -R "${repository}/src/pi" "${work}/pi/.devcontainer/pi"
initial_image="${1-mcr.microsoft.com/devcontainers/base:ubuntu24.04}"
initial_features='{"./pi":{}}'
if [[ "$#" -gt 0 ]]; then initial_features='{}'; fi
jq -n --arg image "${initial_image}" --argjson features "${initial_features}" \
  '{image:$image,remoteUser:"vscode",features:$features}' >"${work}/pi/.devcontainer/devcontainer.json"
up "${work}/pi"
pi_container="$(jq -r .containerId "${work}/up.json")"
pi_image="${image_prefix}-base"
docker image tag "$(docker inspect "${pi_container}" --format '{{.Image}}')" "${pi_image}"
images+=("${pi_image}")
docker cp "${repository}/test/pi/auth_fixture.json" "${pi_container}:/tmp/auth_fixture.json"
docker cp "${repository}/test/pi/session_fixture.jsonl" "${pi_container}:/tmp/session_fixture.jsonl"
# The child container shell expands HOME; the fixtures are synthetic and never reach a provider.
# shellcheck disable=SC2016
devcontainer exec --workspace-folder "${work}/pi" bash -c '
  set -e
  if command -v node || command -v npm; then exit 1; fi
  pi --version
  /usr/local/share/pi-feature/initialize
  install -m 0600 /tmp/auth_fixture.json ~/.pi/agent/auth.json
  mkdir -p ~/.pi/agent/sessions/--tmp-pi-session-fixture--
  cp /tmp/session_fixture.jsonl \
    ~/.pi/agent/sessions/--tmp-pi-session-fixture--/2026-10-23T00-00-00-000Z_fixture-session.jsonl
'
docker rm --force "${pi_container}" >/dev/null

oracle_image="mcr.microsoft.com/devcontainers/base:ubuntu24.04"
for mode in explicit partial defaults; do
  options='{}'
  if [[ "${mode}" == explicit ]]; then
    options='{"version":"22","npmVersion":"10.9.4","pnpmVersion":"9.15.9","nodeGypDependencies":false}'
  elif [[ "${mode}" == partial ]]; then
    options='{"version":"22"}'
  fi
  mkdir -p "${work}/oracle-${mode}/.devcontainer"
  jq -n --arg image "${oracle_image}" --argjson options "${options}" \
    '{image:$image,remoteUser:"vscode",features:{"ghcr.io/devcontainers/features/node:2":$options}}' \
    >"${work}/oracle-${mode}/.devcontainer/devcontainer.json"
  up "${work}/oracle-${mode}"
  node_snapshot "${work}/oracle-${mode}" "${work}/oracle-${mode}.txt"
  oracle_image="${image_prefix}-oracle-${mode}"
  docker image tag "$(docker inspect "$(jq -r .containerId "${work}/up.json")" --format '{{.Image}}')" "${oracle_image}"
  images+=("${oracle_image}")
  jq -n --arg image "${pi_image}" --argjson options "${options}" \
    '{image:$image,remoteUser:"vscode",features:{"ghcr.io/devcontainers/features/node:2":$options}}' \
    >"${work}/pi/.devcontainer/devcontainer.json"
  up "${work}/pi"
  node_snapshot "${work}/pi" "${work}/after-${mode}.txt"
  cmp "${work}/oracle-${mode}.txt" "${work}/after-${mode}.txt"
  # The child container shell expands command substitutions; the fixtures are synthetic.
  # shellcheck disable=SC2016
  devcontainer exec --workspace-folder "${work}/pi" bash -c '
    set -e
    pi --version
    /usr/local/share/pi-feature/initialize
    mkdir -p /tmp/pi-session-fixture && cd /tmp/pi-session-fixture
    test "$(pi auth check --provider anthropic --no-refresh)" = ready
    printf "%s\n" "{\"type\":\"get_entries\"}" | pi --offline --mode rpc --session fixture-session \
      | grep -q "synthetic fixture message"
    if npm ls --global --depth=0 | grep -q @earendil-works/; then exit 1; fi
  '
  pi_image="${image_prefix}-pi-${mode}"
  docker image tag "$(docker inspect "$(jq -r .containerId "${work}/up.json")" --format '{{.Image}}')" "${pi_image}"
  images+=("${pi_image}")
  docker rm --force "$(jq -r .containerId "${work}/up.json")" >/dev/null
  printf 'Node installed after Pi matches the Node-only %s configuration; CLI, initializer and private state pass.\n' \
    "${mode}"
done
