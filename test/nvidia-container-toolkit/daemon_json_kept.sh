#!/usr/bin/env bash
# Scenario (build): the Dockerfile installs the distribution's Docker daemon and seeds daemon.json with another
# runtime, a default runtime, and a log level; the feature adds the nvidia runtime and keeps them all.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "daemon.json registers runtimes.nvidia with path nvidia-container-runtime" daemon_json_has_nvidia
check "the other runtime is kept" jq -e '.runtimes.custom.path == "/usr/bin/runc"' "${TOOLKIT_DAEMON_JSON}"
check "the default runtime is unchanged" jq -e '.["default-runtime"] == "custom"' "${TOOLKIT_DAEMON_JSON}"
check "the log level is kept" jq -e '.["log-level"] == "warn"' "${TOOLKIT_DAEMON_JSON}"
check "nothing else is added" \
  jq -e '(keys == ["default-runtime", "log-level", "runtimes"]) and (.runtimes | keys == ["custom", "nvidia"])' \
  "${TOOLKIT_DAEMON_JSON}"

reportResults
