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

check "bc is installed with refreshPolicy=always and installRecommends=true" rpm -q bc
check "file is installed with refreshPolicy=always and installRecommends=true" rpm -q file
check "cleanup=none leaves the parsed metadata cache in place" parsed_metadata_remains

reportResults
