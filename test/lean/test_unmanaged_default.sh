#!/usr/bin/env bash
# Scenario "test_unmanaged_default": debian:12 as root with defaultToolchain empty ("Empty defaultToolchain", "Default
# changed by the user").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/lean-feature/initialize"

# Whether lean, run outside any project, fails because elan has no default toolchain.
no_default_toolchain() {
  local output
  if output="$(cd / && lean --version 2>&1)"; then return 1; fi
  [[ "${output}" == *"no default toolchain configured"* ]]
}

default_is() {
  local shown
  shown="$(cd / && elan show)"
  [[ "${shown}" == *"(resolved from default '$1')"* ]]
}

check "the recorded default toolchain is empty" [ -z "$(cat /usr/local/share/lean-feature/default-toolchain)" ]
check "elan has no default toolchain on a new volume" no_default_toolchain

elan default v4.35.0
"${INITIALIZE}"
check "the user's default survives a new creation" default_is v4.35.0

reportResults
