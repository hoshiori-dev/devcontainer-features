#!/usr/bin/env bash
# Scenario recommends_and_whitespace (scenarios.json): spec scenarios "Recommended packages are left out", "Spaces and
# empty entries are ignored", and "Caches are removed". wget recommends ca-certificates, which nothing else on
# debian:12 needs; the option value has spaces, a tab, and an empty entry.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

not_installed() {
  ! installed "$1"
}

# The image's docker-clean APT hook deletes downloaded package files too, so this check cannot fail on it;
# control_checks.ts proves the cleanup with a relocated archive directory.
no_package_files() {
  [[ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]]
}

no_index_files() {
  [[ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]]
}

check "wget, listed between spaces, is installed" installed wget
check "bc, listed after a tab and before an empty entry, is installed" installed bc
check "the recommended package ca-certificates is not installed" not_installed ca-certificates
check "the image holds no downloaded package files" no_package_files
check "the image holds no package index files" no_index_files

reportResults
