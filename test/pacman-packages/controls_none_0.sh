#!/usr/bin/env bash
# Scenario controls_none_0 (scenarios.json): spec scenario "Feature cleanup is disabled", with packages=tree and
# cleanup=none, on an image where pacman and the image's hooks retain downloads.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

package_files_remain() {
  [[ -n "$(find /var/cache/pacman/pkg -name '*.pkg.tar.*' -print -quit)" ]]
}

sync_databases_remain() {
  [[ -n "$(find /var/lib/pacman/sync -name '*.db' -print -quit)" ]]
}

check "tree is installed" installed tree
check "downloaded package files are left in /var/cache/pacman/pkg" package_files_remain
check "sync databases are left in /var/lib/pacman/sync" sync_databases_remain

reportResults
