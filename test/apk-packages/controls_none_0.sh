#!/bin/sh
# Scenario controls_none_0 (scenarios.json, alpine:3.22): spec scenario "Feature cleanup is disabled", after an
# install of tree with cleanup=none. Of what that scenario names, this script asserts the metadata: whether package
# files stay is apk's decision. The scenario's other controls (refreshPolicy=always, networkTimeout=10,
# upgradePackages=true) are a smoke combination this script does not assert.
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

check "tree is installed" installed tree
check "tree is a line of apk's world" in_world tree
check "the feature leaves cached metadata in place" managed_cache_holds_metadata

reportResults
