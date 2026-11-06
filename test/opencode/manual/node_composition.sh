#!/usr/bin/env bash
# Host-side check: install the actual Node Feature after OpenCode and compare its options with Node-only containers.
# Run from any directory; requires Docker, devcontainer CLI, and jq. Uses isolated scratch workspaces and synthetic
# state only. Optional $1 is a prebuilt image with this checkout's OpenCode already installed without Node.
set -euo pipefail

repository="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d /tmp/opencode-node-composition.XXXXXX)"
containers=()
volumes=()
images=()
image_prefix="opencode-node-check-$$"

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
    '{{range .Mounts}}{{if eq .Destination "/var/lib/opencode"}}{{.Name}}{{end}}{{end}}')"
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

mkdir -p "${work}/opencode/.devcontainer"
cp -R "${repository}/src/opencode" "${work}/opencode/.devcontainer/opencode"
initial_image="${1-mcr.microsoft.com/devcontainers/base:ubuntu24.04}"
initial_features='{"./opencode":{}}'
if [[ "$#" -gt 0 ]]; then initial_features='{}'; fi
jq -n --arg image "${initial_image}" --argjson features "${initial_features}" \
  '{image:$image,remoteUser:"vscode",features:$features}' >"${work}/opencode/.devcontainer/devcontainer.json"
up "${work}/opencode"
opencode_container="$(jq -r .containerId "${work}/up.json")"
opencode_image="${image_prefix}-base"
docker image tag "$(docker inspect "${opencode_container}" --format '{{.Image}}')" "${opencode_image}"
images+=("${opencode_image}")
docker cp "${repository}/test/opencode/credential_fixture.json" "${opencode_container}:/tmp/credential_fixture.json"
docker cp "${repository}/test/opencode/session_fixture.json" "${opencode_container}:/tmp/session_fixture.json"
devcontainer exec --workspace-folder "${work}/opencode" bash -c '
  set -e
  if command -v node || command -v npm; then exit 1; fi
  opencode --version
  /usr/local/share/opencode-feature/initialize
  mkdir -p /tmp/opencode-session-fixture && cd /tmp/opencode-session-fixture
  opencode auth import --standalone /tmp/credential_fixture.json >/dev/null
  opencode session import --standalone /tmp/session_fixture.json >/dev/null
'
docker rm --force "${opencode_container}" >/dev/null

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
  jq -n --arg image "${opencode_image}" --argjson options "${options}" \
    '{image:$image,remoteUser:"vscode",features:{"ghcr.io/devcontainers/features/node:2":$options}}' \
    >"${work}/opencode/.devcontainer/devcontainer.json"
  up "${work}/opencode"
  node_snapshot "${work}/opencode" "${work}/after-${mode}.txt"
  cmp "${work}/oracle-${mode}.txt" "${work}/after-${mode}.txt"
  devcontainer exec --workspace-folder "${work}/opencode" bash -c '
    set -e
    opencode --version
    /usr/local/share/opencode-feature/initialize
    mkdir -p /tmp/opencode-session-fixture && cd /tmp/opencode-session-fixture
    opencode auth list --standalone | grep -q "Synthetic fixture"
    opencode session list --standalone --format json | grep -q ses_fixture0000000000000000001
    if npm ls --global --depth=0 | grep -q opencode; then exit 1; fi
  '
  opencode_image="${image_prefix}-opencode-${mode}"
  docker image tag "$(docker inspect "$(jq -r .containerId "${work}/up.json")" --format '{{.Image}}')" "${opencode_image}"
  images+=("${opencode_image}")
  docker rm --force "$(jq -r .containerId "${work}/up.json")" >/dev/null
  printf 'Node installed after OpenCode matches the Node-only %s configuration; CLI, initializer and private state pass.\n' "${mode}"
done
