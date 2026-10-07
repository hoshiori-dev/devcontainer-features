#!/usr/bin/env bash
# Scenario fail_refresh_offline (scenarios.json): the container has no network, and this script runs install.sh with a
# list that names a package. Spec scenario "Failed refresh fails the feature".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

database_before="$(local_database)"

run_install PACKAGES=bc
check "a synchronization that fails exits with a non-zero status" failed
check "pacman reports the failed synchronization" printed "failed to synchronize"
check "a synchronization that fails installs and upgrades nothing" local_database_is "${database_before}"

reportResults
