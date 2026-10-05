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

# Succeeds when the package cache holds no package file, at either depth libzypp stores them.
no_package_file_remains() {
  local package_file
  for package_file in /var/cache/zypp/packages/*/*.rpm /var/cache/zypp/packages/*/*/*.rpm; do
    if [[ -f "${package_file}" ]]; then return 1; fi
  done
  return 0
}

check "bc is installed with refreshPolicy=always and installRecommends=true" rpm -q bc
check "file is installed with refreshPolicy=always and installRecommends=true" rpm -q file
check "cleanup=packages leaves usable metadata in the parsed metadata cache" parsed_metadata_remains
check "cleanup=packages removes package files from the managed cache" no_package_file_remains

reportResults
