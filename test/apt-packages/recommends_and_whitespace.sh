#!/usr/bin/env bash
# Scenario recommends_and_whitespace (scenarios.json): spec scenarios "Recommended packages are left out",
# "Spaces and empty entries are ignored", and "Caches are removed". wget recommends ca-certificates,
# which nothing else on debian:12 needs; the value has spaces, a tab, and an empty entry.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
}

not_installed() {
  ! installed "$1"
}

no_package_files() {
  [ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]
}

no_index_files() {
  [ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]
}

check "wget is installed" installed wget
check "bc is installed" installed bc
check "ca-certificates, which wget only recommends, is not installed" not_installed ca-certificates
check "no downloaded package file is left" no_package_files
check "no package index file is left" no_index_files

reportResults
