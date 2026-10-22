#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# The scenario runner copies this helper beside the script; hooks may lint each script independently.
# shellcheck source=/dev/null
source "$(dirname "$0")/node_checks.sh"
# Expansion belongs to the child shell that runs the assertion.
# shellcheck disable=SC2016
check "partial Node options preserve requested version and alias" bash -c \
  '[[ "$(node --version)" == v22.* && "$(cat /usr/local/share/nvm/alias/default)" == 22 ]]'
check "omitted pnpm and node-gyp options retain upstream defaults" node_default_tools
check "Claude Code and initializer work with partial Node options" node_cli_and_initializer
reportResults
