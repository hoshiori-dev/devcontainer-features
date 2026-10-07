#!/usr/bin/env bash
# Scenario test_listed_packages_debian (scenarios.json): spec scenarios "Listed packages are installed", "Missing index
# is refreshed" (the image ships no package index, so the installation succeeds only after a refresh), and "Caches are
# removed".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

# The image's docker-clean APT hook deletes downloaded package files too, so this check cannot fail on it;
# the scenarios test_control_runs_* prove the cleanup with a relocated archive directory.
no_package_files() {
  [[ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]]
}

no_index_files() {
  [[ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]]
}

check "bc is installed" installed bc
check "file is installed" installed file
check "bc, with its dependencies, is installed: it computes 6*7" bash -c 'echo "6*7" | bc | grep -qx 42'
check "file, with its dependencies, is installed: it prints its version" file --version
check "file's dependency libmagic-mgc is installed" installed libmagic-mgc
check "the image holds no downloaded package files" no_package_files
check "the image holds no package index files" no_index_files

reportResults
