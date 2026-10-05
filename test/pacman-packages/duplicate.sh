#!/usr/bin/env bash
# Install-twice test: pacman-packages is installed with packages=bc,tree and cleanup=packages, then with the defaults,
# an empty list and cleanup=all. Scenarios "Listed packages are installed" and "Only package files are cleaned" for the
# first install, and "Omitted packages" for the second, whose default cleanup=all must remove nothing.
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

# The devcontainer CLI gives the first install, for each option, the `proposals` entry or `enum` value at index 1 when
# the default is empty or sits at index 0: packages=bc,tree and cleanup=packages. Re-check the literals below when the
# CLI's selection, the proposals, or the enum order changes.
check "bc from the first install is installed" installed bc
check "tree from the first install is installed" installed tree
check "package files are removed from /var/cache/pacman/pkg" no_package_files
check "sync databases remain in /var/lib/pacman/sync after the empty second install" sync_databases_remain

reportResults
