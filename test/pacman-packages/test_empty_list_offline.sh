#!/usr/bin/env bash
# Scenario test_empty_list_offline (scenarios.json): the container has no network, and this script runs install.sh with
# lists that name no package. Spec scenarios "Omitted packages" and "Empty list is a no-op".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly EMPTY_LISTS=("" $' , ,\t, ' ",")

database_before="$(local_database)"

run_install
check "without packages the feature exits with status 0" exited_with 0
check "the run without packages downloaded no sync database" no_sync_databases
check "the run without packages installed, upgraded, and removed nothing" local_database_is "${database_before}"

for list in "${EMPTY_LISTS[@]}"; do
  run_install PACKAGES="${list}"
  check "with packages='${list}' the feature exits with status 0" exited_with 0
done
check "no run with an empty list downloaded a sync database" no_sync_databases
check "no run with an empty list installed, upgraded, or removed a package" local_database_is "${database_before}"

reportResults
