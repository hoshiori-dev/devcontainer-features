#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# dnf4 keeps its cache under /var/cache/dnf and dnf5 under /var/cache/libdnf5, and one of the two may be missing, so
# the helper judges what find prints, never its status.
metadata_remains() {
  local found
  found="$(find /var/cache/dnf /var/cache/libdnf5 -name repomd.xml 2>/dev/null || true)"
  [[ -n "${found}" ]]
}

check "Listed packages are installed: bc is installed" rpm -q bc
check "Listed packages are installed: file is installed" rpm -q file
# Package files are not asserted: native settings may delete them ("Native package retention is independent").
check "Feature cleanup is disabled: repository metadata is left in place" metadata_remains

reportResults
