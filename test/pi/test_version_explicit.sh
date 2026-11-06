#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the exact stable release is installed" test "$(pi --version)" = 1.4.0
check "state initialization works with the exact release" /usr/local/share/pi-feature/initialize
reportResults
