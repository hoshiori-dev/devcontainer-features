#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the exact stable release is installed" test "$(opencode --version)" = "opencode v2.1.2"
check "state initialization works with the exact release" /usr/local/share/opencode-feature/initialize
reportResults
