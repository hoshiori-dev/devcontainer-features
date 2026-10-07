#!/usr/bin/env bash
# Scenario test_unexpired_metadata_offline_0 (scenarios.json): the scenario's Dockerfile downloads the repository
# metadata and the package files of bc without installing it, and the container has no network. Spec scenario
# "Unexpired metadata is used as is": this script's run of install.sh succeeds only when it downloads nothing.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# No name resolves, mirrors.fedoraproject.org standing for any.
no_network() {
  ! getent hosts mirrors.fedoraproject.org >/dev/null
}

check "premise: the container has no network" no_network
check "premise: the image holds repository metadata" has_metadata
check "premise: bc is not installed" not_installed bc
configuration_before="$(dnf_configuration)"
run_install PACKAGES=bc CLEANUP=none
check "bc installs without a network from the metadata and the package files the image holds" exited_with 0
check "bc is installed" installed bc
check "the installation without a network leaves the dnf configuration unchanged" \
  dnf_configuration_is "${configuration_before}"

reportResults
