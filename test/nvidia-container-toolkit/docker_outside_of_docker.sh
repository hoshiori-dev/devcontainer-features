#!/usr/bin/env bash
# Scenario: installed with docker-outside-of-docker, which installs only the Docker CLI. With no dockerd the feature
# skips the Docker configuration (its build log says so) and creates no daemon.json.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# sbin directories too: distribution packages install dockerd there, and the remote user's PATH may omit them.
no_dockerd() {
  ! PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin" command -v dockerd >/dev/null 2>&1
}

# The first two checks are the preconditions of Scenario "No Docker daemon" (an image without dockerd, including one
# with only the Docker CLI), not behaviors of the feature: they show that docker-outside-of-docker set that image up.
check "the Docker CLI is installed" command -v docker
check "no Docker daemon is installed" no_dockerd
check "nvidia-ctk runs for the remote user" nvidia-ctk --version
check "no daemon.json is created" no_daemon_json

reportResults
