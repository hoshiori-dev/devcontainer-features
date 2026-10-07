#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The compatibility list selects no scenario architectures, so scenarios run on amd64 only, where the entry bc.x86_64
# names the image's native architecture.
bc_is_installed_for_x86_64() {
  local architecture
  architecture="$(rpm -q --qf '%{ARCH}' bc)"
  [[ "${architecture}" == x86_64 ]]
}

check "Native architecture qualifier is installed: bc is installed for x86_64" bc_is_installed_for_x86_64

reportResults
