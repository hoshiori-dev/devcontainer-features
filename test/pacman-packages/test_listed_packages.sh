#!/usr/bin/env bash
# Scenario test_listed_packages (scenarios.json): spec scenarios "Listed packages are installed", "Missing database is
# downloaded" (the image ships no sync database), "Installation runs without a terminal" (the CLI builds without one),
# and "Caches are removed". jq needs oniguruma, which the image lacks.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

no_package_files() {
  [[ -z "$(find /var/cache/pacman/pkg -mindepth 1 -print -quit)" ]]
}

no_sync_databases() {
  [[ -z "$(find /var/lib/pacman/sync -mindepth 1 -print -quit)" ]]
}

check "bc is installed" installed bc
check "jq is installed" installed jq
check "bc runs" bash -c 'echo "6*7" | bc | grep -qx 42'
check "jq runs" bash -c 'echo "{\"a\":42}" | jq .a | grep -qx 42'
check "the dependency oniguruma is installed" installed oniguruma
check "no downloaded package or signature file is left" no_package_files
check "no sync database file is left" no_sync_databases

reportResults
