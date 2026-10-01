#!/usr/bin/env bash
# Scenario optional_dependencies_and_whitespace (scenarios.json): spec scenarios "Optional dependencies
# are left out", "Spaces and empty entries are ignored", and "Caches are removed". rsync names python
# as an optional dependency, which nothing in the image needs; the value has spaces, a tab, and an
# empty entry.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

not_installed() {
  ! installed "$1"
}

no_package_files() {
  [ -z "$(find /var/cache/pacman/pkg -mindepth 1 -print -quit)" ]
}

no_sync_databases() {
  [ -z "$(find /var/lib/pacman/sync -mindepth 1 -print -quit)" ]
}

check "rsync is installed" installed rsync
check "bc is installed" installed bc
check "rsync runs" rsync --version
check "python, which rsync only names as an optional dependency, is not installed" not_installed python
check "no downloaded package or signature file is left" no_package_files
check "no sync database file is left" no_sync_databases

reportResults
