#!/usr/bin/env bash
# Scenario test_empty_list_offline_ubuntu (scenarios.json): the container has no network, and this script runs
# install.sh with lists that name no package. Spec scenarios "Omitted packages" and "Empty list is a no-op".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly EMPTY_LISTS=("" $' , ,\t, ' ",")

status_before="$(dpkg_status)"

run_install
check "without packages the feature exits with status 0" exited_with 0
for list in "${EMPTY_LISTS[@]}"; do
  run_install PACKAGES="${list}"
  check "with packages='${list}' the feature exits with status 0" exited_with 0
done
check "no run refreshed the package index" no_index
check "no run installed or removed a package" dpkg_status_is "${status_before}"

reportResults
