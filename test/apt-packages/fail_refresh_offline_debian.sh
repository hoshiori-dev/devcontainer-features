#!/usr/bin/env bash
# Scenario fail_refresh_offline_debian (scenarios.json): the container has no network and the image holds no package
# index, and this script runs install.sh with a list that needs one. Spec scenarios "Failed refresh fails the feature"
# and "Missing cached metadata fails without refresh".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# apt-get starts a line with one of these words for every index or package file it tries to fetch.
attempted_no_download() {
  if output_matches '^(Get|Hit|Ign|Err):'; then
    echo "apt-get tried to fetch a file" >&2
    return 1
  fi
}

status_before="$(dpkg_status)"
configuration_before="$(apt_configuration)"

run_install PACKAGES=bc
check "a refresh that fails exits with a non-zero status" failed
check "a refresh that fails installs nothing" dpkg_status_is "${status_before}"

run_install PACKAGES=bc REFRESHPOLICY=never CLEANUP=packages
check "refreshPolicy=never without a package index exits with a non-zero status" failed
check "refreshPolicy=never without a package index names the missing index" \
  printed "refreshPolicy=never needs a package index"
check "refreshPolicy=never without a package index attempts no download" attempted_no_download
check "refreshPolicy=never without a package index installs nothing" dpkg_status_is "${status_before}"
check "refreshPolicy=never without a package index leaves the apt configuration unchanged" \
  apt_configuration_is "${configuration_before}"

reportResults
