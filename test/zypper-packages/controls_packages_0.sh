#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Succeeds when a parsed metadata cache holds data. A glob, because the image ships no find.
parsed_metadata_remains() {
  local solv_file
  for solv_file in /var/cache/zypp/solv/*/solv; do
    if [[ -s "${solv_file}" ]]; then return 0; fi
  done
  return 1
}

# Succeeds when the package cache holds no package file one to three levels below it: libzypp stores a download in
# <alias>/<arch> on Tumbleweed and in <alias>/%2E%2E/<arch> on Leap 16.0.
no_package_file_remains() {
  local package_file
  local packages_dir="/var/cache/zypp/packages"
  for package_file in "${packages_dir}"/*/*.rpm "${packages_dir}"/*/*/*.rpm "${packages_dir}"/*/*/*/*.rpm; do
    if [[ -f "${package_file}" ]]; then return 1; fi
  done
  return 0
}

check "bc is installed with refreshPolicy=always and installRecommends=true" rpm -q bc
check "file is installed with refreshPolicy=always and installRecommends=true" rpm -q file
check "cleanup=packages leaves usable metadata in the parsed metadata cache" parsed_metadata_remains
# libzypp deletes each downloaded package after installing it unless its repository sets keeppackages, which none of
# the image's repositories does: after cleanup=none the package cache holds no package file either. So this check
# only shows that no package file is left; no test plants one to see `zypper clean` remove it.
check "cleanup=packages leaves no package file in the managed cache" no_package_file_remains

reportResults
