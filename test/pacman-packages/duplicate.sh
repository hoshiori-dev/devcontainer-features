#!/usr/bin/env bash
# Install-twice test: pacman-packages is installed with packages=bc,tree, cleanup=packages, and parallelDownloads=3,
# then with the defaults, an empty list, cleanup=all, and no parallelDownloads. Scenarios "Listed packages are
# installed", "Only package files are cleaned", and "Temporary configuration is removed" for the first install, and
# "Omitted packages" and "Omitted parallelDownloads" for the second, whose default cleanup=all must remove nothing.
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

# pacman logs each command line, so the log shows the configuration file the first install handed to pacman.
first_install_used_a_temporary_configuration() {
  grep -q "Running 'pacman --config /tmp/pacman-packages\.[A-Za-z0-9]* --sync " /var/log/pacman.log
}

no_temporary_configuration() {
  [[ -z "$(find /tmp -name 'pacman-packages.*' -print -quit)" ]]
}

# The devcontainer CLI gives the first install, for each option, the `proposals` entry or `enum` value at index 1 when
# the default is empty or sits at index 0: packages=bc,tree, cleanup=packages, and parallelDownloads=3. Re-check the
# literals below when the CLI's selection, the proposals, or the enum order changes.
check "bc from the first install is installed" installed bc
check "tree from the first install is installed" installed tree
check "package files are removed from /var/cache/pacman/pkg" no_package_files
check "sync databases remain in /var/lib/pacman/sync after the empty second install" sync_databases_remain
check "the first install ran pacman with a temporary configuration for parallelDownloads=3" \
  first_install_used_a_temporary_configuration
check "no temporary configuration is left under /tmp after both installs" no_temporary_configuration

reportResults
