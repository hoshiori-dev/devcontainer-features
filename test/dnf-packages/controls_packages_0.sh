#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# dnf4 keeps its cache under /var/cache/dnf and dnf5 under /var/cache/libdnf5, and one of the two may be missing, so
# both helpers judge what find prints, never its status.
metadata_remains() {
  local found
  found="$(find /var/cache/dnf /var/cache/libdnf5 -name repomd.xml 2>/dev/null || true)"
  [[ -n "${found}" ]]
}

package_files_are_removed() {
  local found
  found="$(find /var/cache/dnf /var/cache/libdnf5 -name '*.rpm' 2>/dev/null || true)"
  [[ -z "${found}" ]]
}

check "Listed packages are installed: bc is installed" rpm -q bc
check "Listed packages are installed: file is installed" rpm -q file
check "Only package files are cleaned: repository metadata remains" metadata_remains
# dnf's default keepcache=0 deletes each downloaded package after the transaction, so this check only shows that no
# package file is left; no test plants one to see `dnf clean packages` remove it.
check "Only package files are cleaned: no package file is left in the cache" package_files_are_removed

reportResults
