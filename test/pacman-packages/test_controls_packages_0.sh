#!/usr/bin/env bash
# Scenario test_controls_packages_0 (scenarios.json): spec scenario "Only package files are cleaned", with packages=tree
# and cleanup=packages.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

no_package_files() {
  [[ -z "$(find /var/cache/pacman/pkg -mindepth 1 -print -quit)" ]]
}

sync_databases_remain() {
  [[ -n "$(find /var/lib/pacman/sync -name '*.db' -print -quit)" ]]
}

check "tree is installed" installed tree
check "package files are removed from /var/cache/pacman/pkg" no_package_files
check "sync databases remain in /var/lib/pacman/sync" sync_databases_remain

reportResults
