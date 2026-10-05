#!/bin/sh
# Scenario controls_packages_1 (scenarios.json, alpine:3.24): spec scenario "Only package files are cleaned",
# after an install of tree with cleanup=packages. The scenario's other controls (refreshPolicy=always,
# networkTimeout=10, upgradePackages=true) are a smoke combination this script does not assert.
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The managed cache /var/cache/apk-packages holds a package index in either format apk writes.
managed_cache_holds_metadata() {
  for managed_cache_holds_metadata_file in /var/cache/apk-packages/APKINDEX.*.tar.gz /var/cache/apk-packages/*.adb; do
    if [ -f "${managed_cache_holds_metadata_file}" ]; then return 0; fi
  done
  return 1
}

managed_cache_holds_no_package_file() {
  for managed_cache_holds_no_package_file_path in /var/cache/apk-packages/*.apk; do
    [ ! -e "${managed_cache_holds_no_package_file_path}" ] || return 1
  done
}

check "tree is installed" installed tree
check "tree is a line of apk's world" in_world tree
check "package files are removed from the managed cache" managed_cache_holds_no_package_file
check "usable metadata remains in the managed cache" managed_cache_holds_metadata

reportResults
