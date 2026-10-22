#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the exact stable release is installed" test "$(codex --version)" = "codex-cli 0.162.0"
check "state initialization works with the exact release" /usr/local/share/codex-feature/initialize
reportResults
