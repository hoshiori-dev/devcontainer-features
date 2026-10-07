#!/usr/bin/env bash
# Scenario test_present_index_offline_debian (scenarios.json): the scenario's Dockerfile refreshes the package index
# and downloads bc without installing it, and the container has no network. Spec scenario "Present index is used as
# is": this script's run of install.sh succeeds only when it refreshes nothing.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# No name resolves, deb.debian.org standing for any.
no_network() {
  ! getent hosts deb.debian.org >/dev/null
}

check "premise: the container has no network" no_network
check "premise: the image holds a package index" has_index
check "premise: bc is not installed" not_installed bc
run_install PACKAGES=bc
check "bc installs without a network from the index and the package files the image holds" exited_with 0
check "the feature says it uses the index the image holds" printed "using the package index the image already holds"
check "bc is installed" installed bc

reportResults
