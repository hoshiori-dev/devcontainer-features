#!/usr/bin/env bash
# Scenario test_native_architecture (scenarios.json): spec scenarios "Native architecture qualifier is installed", with
# bc:amd64 (scenario jobs run on amd64), and "Caches are removed".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

native_bc() {
  [[ "$(dpkg --print-architecture)" == amd64 && "$(dpkg-query -W -f='${Architecture}' bc)" == amd64 ]]
}

no_foreign_architecture() {
  [[ -z "$(dpkg --print-foreign-architectures)" ]]
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
check "bc is installed for the native architecture amd64" native_bc
check "the feature enables no architecture" no_foreign_architecture
check "the image holds no downloaded package files" no_package_files
check "the image holds no package index files" no_index_files

reportResults
