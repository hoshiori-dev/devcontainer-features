#!/usr/bin/env bash
# Scenario: installed with docker-outside-of-docker, which installs only the Docker CLI. With no dockerd
# the feature skips the Docker configuration (its build log says so) and creates no daemon.json.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

no_dockerd() {
  ! PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin" command -v dockerd >/dev/null 2>&1
}

check "the Docker CLI is installed" command -v docker
check "no Docker daemon is installed" no_dockerd
check "nvidia-ctk runs for the remote user" nvidia-ctk --version
check "no daemon.json is created" no_daemon_json

reportResults
