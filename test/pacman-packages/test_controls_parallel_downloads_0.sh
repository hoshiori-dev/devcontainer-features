#!/usr/bin/env bash
# Scenario test_controls_parallel_downloads_0 (scenarios.json): the devcontainer CLI installs the feature with
# packages="extra/bc, tree" and parallelDownloads=3. Spec scenarios "Explicit parallel downloads reach pacman" (the
# option reaches install.sh through the CLI), "Parallel downloads apply to repository-qualified entries", "Qualified
# entry resolves in the named repository" (a package of an image repository), and "Temporary configuration is
# removed".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

# pacman logs each command line, so the log shows the one call the feature made, with the configuration file it handed
# to pacman and each entry as it reached pacman.
feature_ran_pacman_once_with_a_temporary_configuration() {
  local calls
  local call="Running 'pacman --config /tmp/pacman-packages\.[A-Za-z0-9]*"
  calls="$(grep -c "Running 'pacman " /var/log/pacman.log)"
  [[ "${calls}" -eq 1 ]] \
    && grep -q "${call} --sync --refresh --sysupgrade --needed --noconfirm -- extra/bc tree'" /var/log/pacman.log
}

no_temporary_configuration() {
  [[ -z "$(find /tmp -name 'pacman-packages.*' -print -quit)" ]]
}

no_cache_left() {
  [[ -z "$(find /var/cache/pacman/pkg /var/lib/pacman/sync -mindepth 1 -print -quit)" ]]
}

check "bc, listed as extra/bc, is installed" installed bc
check "tree is installed" installed tree
check "the feature ran pacman once, with a temporary configuration and both entries" \
  feature_ran_pacman_once_with_a_temporary_configuration
check "the temporary configuration is removed" no_temporary_configuration
check "the default cleanup=all removed the package files and the sync databases" no_cache_left

reportResults
