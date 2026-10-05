#!/usr/bin/env bash
# Scenario controls_none_1 (scenarios.json): spec scenario "Feature cleanup is disabled", with bc and file installed
# under cleanup=none, refreshPolicy=always, networkTimeout=10, and installRecommends=true. Retained package files are
# not asserted: the image's docker-clean APT hook deletes them whatever the feature does (spec scenario "Native package
# retention is independent").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

has_index() {
  [[ -n "$(find /var/lib/apt/lists -name '*_Packages*' -print -quit)" ]]
}

check "bc is installed" installed bc
check "file is installed" installed file
check "the feature leaves metadata in place" has_index

reportResults
