#!/bin/sh
# Scenario test_controls_none_1 (scenarios.json, alpine:3.24): spec scenario "Feature cleanup is disabled", after an
# install of tree with cleanup=none: the feature's cache holds the package index of every configured repository and
# the package file of tree, which apk had to download. The scenario's other controls (refreshPolicy=always,
# networkTimeout=10, upgradePackages=true) are a smoke combination this script does not assert.
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The managed cache /var/cache/apk-packages holds as many package indexes, in either format apk writes, as
# /etc/apk/repositories configures repositories.
managed_cache_holds_every_index() {
  managed_cache_holds_every_index_configured="$(grep -c '^[^#]' /etc/apk/repositories)" || return 1
  managed_cache_holds_every_index_found=0
  for managed_cache_holds_every_index_file in /var/cache/apk-packages/APKINDEX.*.tar.gz \
    /var/cache/apk-packages/*.adb; do
    if [ -f "${managed_cache_holds_every_index_file}" ]; then
      managed_cache_holds_every_index_found=$((managed_cache_holds_every_index_found + 1))
    fi
  done
  if [ "${managed_cache_holds_every_index_found}" -ne "${managed_cache_holds_every_index_configured}" ]; then
    echo "/var/cache/apk-packages holds ${managed_cache_holds_every_index_found} package indexes for" \
      "${managed_cache_holds_every_index_configured} configured repositories" >&2
    return 1
  fi
}

# The managed cache holds the package file of the package $1, which apk names <package>-<version>.<checksum>.apk.
managed_cache_holds_package_file() {
  for managed_cache_holds_package_file_path in /var/cache/apk-packages/"$1"-[0-9]*.apk; do
    if [ -f "${managed_cache_holds_package_file_path}" ]; then return 0; fi
  done
  echo "/var/cache/apk-packages holds no package file of $1" >&2
  return 1
}

check "tree is installed" installed tree
check "tree is a line of apk's world" in_world tree
check "the feature's cache holds the package index of every configured repository" managed_cache_holds_every_index
check "the feature's cache holds the package file of tree" managed_cache_holds_package_file tree

reportResults
