#!/usr/bin/env bash
# Scenario test_source_controls_ubuntu (scenarios.json): the devcontainer CLI installs sqlite3 with the five options of
# the second phase set: targetRelease=noble, installSuggests=true, conffilePolicy=replace, downloadRetries=2, and
# lockTimeout=5. Spec scenario "Suggested packages are installed": sqlite3 suggests sqlite3-doc. What each of the other
# options does is checked by the scenarios that run install.sh themselves.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

check "the feature installs sqlite3 with the five options set" installed sqlite3
check "the suggested package sqlite3-doc is installed with it" installed sqlite3-doc

reportResults
