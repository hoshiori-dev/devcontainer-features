#!/usr/bin/env bash
# Scenario native_architecture (scenarios.json): spec scenarios "Native architecture qualifier is installed"
# with bc:amd64 (scenario jobs run on amd64) and "Caches are removed".
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

native_bc() {
  [ "$(dpkg --print-architecture)" = amd64 ] && [ "$(dpkg-query -W -f='${Architecture}' bc)" = amd64 ]
}

check "bc is installed" installed bc
check "bc is installed for the native architecture amd64" native_bc
check "no foreign architecture was enabled" test -z "$(dpkg --print-foreign-architectures)"
check "no downloaded package file is left" no_package_files
check "no package index file is left" no_index_files

reportResults
