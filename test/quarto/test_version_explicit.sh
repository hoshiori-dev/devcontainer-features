#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "leading v selects the exact stable version" test "$(quarto --version)" = 1.9.38
reportResults
