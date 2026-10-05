#!/usr/bin/env bash
# Scenario (build): the Dockerfile installs the distribution's Docker daemon and leaves a zero-length
# daemon.json; the build succeeds and the file holds valid JSON with the nvidia runtime.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "daemon.json is valid JSON" jq -e . "$TOOLKIT_DAEMON_JSON"
check "daemon.json registers runtimes.nvidia with path nvidia-container-runtime" daemon_json_has_nvidia

reportResults
