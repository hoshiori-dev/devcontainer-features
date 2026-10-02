#!/usr/bin/env bash
# Scenario (build): configureDocker disabled on an image with the distribution's Docker daemon and a seeded
# daemon.json; the file stays byte-identical to the copy the Dockerfile saved.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "a Docker daemon is installed" test -x /usr/sbin/dockerd -o -x /usr/bin/dockerd
check "daemon.json is byte-identical to the seeded copy" cmp /etc/docker/daemon.json.seeded "$TOOLKIT_DAEMON_JSON"
check "nvidia-ctk runs for the remote user" nvidia-ctk --version

reportResults
