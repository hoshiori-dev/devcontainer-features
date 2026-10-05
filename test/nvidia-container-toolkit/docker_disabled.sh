#!/usr/bin/env bash
# Scenario (build): configureDocker disabled on an image with the distribution's Docker daemon and a seeded
# daemon.json; the file stays byte-identical to the copy the Dockerfile saved.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# Precondition of Scenario "Docker configuration disabled" (an image with a Docker daemon), not a behavior of the
# feature: without a daemon the feature leaves daemon.json alone whatever configureDocker says.
dockerd_installed() {
  [[ -x /usr/sbin/dockerd || -x /usr/bin/dockerd ]]
}

check "a Docker daemon is installed" dockerd_installed
check "daemon.json is neither created nor changed" cmp /etc/docker/daemon.json.seeded "${TOOLKIT_DAEMON_JSON}"
check "nvidia-ctk runs for the remote user" nvidia-ctk --version

reportResults
