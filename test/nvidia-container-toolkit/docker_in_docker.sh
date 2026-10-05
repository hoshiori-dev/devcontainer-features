#!/usr/bin/env bash
# Scenario: installed with docker-in-docker and configureDocker unset. The feature registers the nvidia runtime in
# daemon.json at build time; the daemon docker-in-docker starts with the container reads it.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# The daemon starts with the container, not before the test: wait for it, at most 120 seconds.
docker_daemon_ready() {
  local attempt
  for attempt in $(seq 1 60); do
    if as_root docker info >/dev/null 2>&1; then return 0; fi
    printf '%s\n' "waiting for the Docker daemon (${attempt})" >&2
    sleep 2
  done
  return 1
}

daemon_lists_nvidia() {
  local runtimes
  runtimes="$(as_root docker info --format '{{json .Runtimes}}')" || return
  jq -e 'has("nvidia")' <<<"${runtimes}" >/dev/null
}

check "daemon.json registers runtimes.nvidia with path nvidia-container-runtime" daemon_json_has_nvidia
check "daemon.json does not change the default runtime" \
  jq -e 'has("default-runtime") | not' "${TOOLKIT_DAEMON_JSON}"
check "the Docker daemon is running" docker_daemon_ready
check "the Docker daemon lists the nvidia runtime" daemon_lists_nvidia

reportResults
