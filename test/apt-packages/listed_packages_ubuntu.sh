#!/usr/bin/env bash
# Scenario listed_packages_ubuntu (scenarios.json): spec scenarios "Listed packages are installed", "Missing index is
# refreshed" (the image ships no package index, so the installation succeeds only after a refresh), and "Caches are
# removed".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

# The image's docker-clean APT hook deletes downloaded package files too, so this check cannot fail on it;
# control_checks.ts proves the cleanup with a relocated archive directory.
no_package_files() {
  [[ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]]
}

no_index_files() {
  [[ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]]
}

check "bc is installed" installed bc
check "file is installed" installed file
check "the installed bc runs" bash -c 'echo "6*7" | bc | grep -qx 42'
check "the installed file runs" file --version
check "file's dependency libmagic-mgc is installed" installed libmagic-mgc
check "the image holds no downloaded package files" no_package_files
check "the image holds no package index files" no_index_files

reportResults
