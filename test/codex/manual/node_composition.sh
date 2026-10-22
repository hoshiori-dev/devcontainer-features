#!/usr/bin/env bash
# Host-side check: install the actual Node Feature after Codex and compare its options with Node-only containers.
# Run from any directory; requires Docker, devcontainer CLI, and jq. Uses isolated scratch workspaces and fake state.
# Optional $1 is a prebuilt image with this checkout's Codex already installed without Node.
set -euo pipefail

repository="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d /tmp/codex-node-composition.XXXXXX)"
containers=()
volumes=()
images=()
image_prefix="codex-node-check-$$"

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
    '{{range .Mounts}}{{if eq .Destination "/var/lib/codex"}}{{.Name}}{{end}}{{end}}')"
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

mkdir -p "${work}/codex/.devcontainer"
cp -R "${repository}/src/codex" "${work}/codex/.devcontainer/codex"
initial_image="${1-mcr.microsoft.com/devcontainers/base:ubuntu24.04}"
initial_features='{"./codex":{}}'
if [[ "$#" -gt 0 ]]; then initial_features='{}'; fi
jq -n --arg image "${initial_image}" --argjson features "${initial_features}" \
  '{image:$image,remoteUser:"vscode",features:$features}' >"${work}/codex/.devcontainer/devcontainer.json"
up "${work}/codex"
codex_container="$(jq -r .containerId "${work}/up.json")"
codex_image="${image_prefix}-base"
docker image tag "$(docker inspect "${codex_container}" --format '{{.Image}}')" "${codex_image}"
images+=("${codex_image}")
devcontainer exec --workspace-folder "${work}/codex" bash -c '
  set -e
  ! command -v node
  ! command -v npm
  codex --version
  /usr/local/share/codex-feature/initialize
  umask 077
  printf "private composition fixture\n" > ~/.codex/composition-fixture
  printf "%s\n" "test-placeholder-not-a-real-key" | codex login --with-api-key >/dev/null 2>&1
'
docker rm --force "${codex_container}" >/dev/null

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
  jq -n --arg image "${codex_image}" --argjson options "${options}" \
    '{image:$image,remoteUser:"vscode",features:{"ghcr.io/devcontainers/features/node:2":$options}}' \
    >"${work}/codex/.devcontainer/devcontainer.json"
  up "${work}/codex"
  node_snapshot "${work}/codex" "${work}/after-${mode}.txt"
  cmp "${work}/oracle-${mode}.txt" "${work}/after-${mode}.txt"
  # The child shell reads only the private fixture inside its container.
  # shellcheck disable=SC2016
  devcontainer exec --workspace-folder "${work}/codex" bash -c '
    set -e
    codex --version
    /usr/local/share/codex-feature/initialize
    codex login status >/dev/null 2>&1
    test "$(cat ~/.codex/composition-fixture)" = "private composition fixture"
  '
  session_mode=restore
  if [[ "${mode}" == explicit ]]; then session_mode=create; fi
  docker cp "${repository}/test/codex/session_fixture.mjs" \
    "$(jq -r .containerId "${work}/up.json"):/tmp/codex-session-fixture.mjs"
  devcontainer exec --workspace-folder "${work}/codex" node /tmp/codex-session-fixture.mjs "${session_mode}"
  codex_image="${image_prefix}-codex-${mode}"
  docker image tag "$(docker inspect "$(jq -r .containerId "${work}/up.json")" --format '{{.Image}}')" "${codex_image}"
  images+=("${codex_image}")
  docker rm --force "$(jq -r .containerId "${work}/up.json")" >/dev/null
  printf 'Node installed after Codex matches the Node-only %s configuration; CLI, initializer and private state pass.\n' "${mode}"
done
