#!/usr/bin/env bash
# Scenario controls_packages_1 (scenarios.json): spec scenario "Only package files are cleaned", with bc and file
# installed under cleanup=packages, refreshPolicy=always, networkTimeout=10, and installRecommends=true.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

# The image's docker-clean APT hook deletes downloaded package files too, so this check cannot fail on it;
# control_checks.ts proves the cleanup with a relocated archive directory.
no_package_files() {
  [[ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]]
}

has_index() {
  [[ -n "$(find /var/lib/apt/lists -name '*_Packages*' -print -quit)" ]]
}

check "bc is installed" installed bc
check "file is installed" installed file
check "package files are removed from the managed cache" no_package_files
check "usable metadata remains" has_index

reportResults
