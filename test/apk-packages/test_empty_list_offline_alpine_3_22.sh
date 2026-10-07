#!/bin/sh
# Scenario test_empty_list_offline_alpine_3_22 (scenarios.json): the container has no network, and this script runs
# install.sh with lists that name no package. Spec scenarios "Omitted packages" and "Empty list is a no-op".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

TAB="$(printf '\t')"
readonly TAB

state_before="$(apk_state)"

run_install
check "without packages the feature exits with status 0" exited_with 0
check "the run without packages changed nothing: apk's world, its installed database, and the caches" \
  apk_state_is "${state_before}"

for list in "" " , ,${TAB}, " ","; do
  run_install PACKAGES="${list}"
  check "with packages='${list}' the feature exits with status 0" exited_with 0
done
check "the runs with an empty list changed nothing: apk's world, its installed database, and the caches" \
  apk_state_is "${state_before}"

reportResults
