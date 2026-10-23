#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# The scenario runner copies this helper beside the script; hooks may lint each script independently.
# shellcheck source=/dev/null
source "$(dirname "$0")/node_checks.sh"
# Expansion belongs to the child shell that runs the assertion.
# shellcheck disable=SC2016
check "explicit Node version and default alias are retained" bash -c \
  '[[ "$(node --version)" == v22.* && "$(cat /usr/local/share/nvm/alias/default)" == 22 ]]'
check "explicit npm version is retained" test "$(npm --version)" = 10.9.4
check "explicit pnpm version is retained" test "$(pnpm --version)" = 9.15.9
check "Codex and initializer work alongside explicit Node options" node_cli_and_initializer
reportResults
