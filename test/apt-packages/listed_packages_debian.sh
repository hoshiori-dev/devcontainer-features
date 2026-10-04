#!/usr/bin/env bash
# Scenario listed_packages_debian (scenarios.json): spec scenarios "Listed packages are installed",
# "Missing index is refreshed" (the image ships no index), and "Caches are removed".
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
}

no_package_files() {
  [ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]
}

no_index_files() {
  [ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]
}

check "bc is installed" installed bc
check "file is installed" installed file
check "bc runs" bash -c 'echo "6*7" | bc | grep -qx 42'
check "file runs" file --version
check "the dependency libmagic-mgc is installed" installed libmagic-mgc
check "no downloaded package file is left" no_package_files
check "no package index file is left" no_index_files

reportResults
