#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# The scenario runner copies this helper beside the script; hooks may lint each script independently.
# shellcheck source=/dev/null
source "$(dirname "$0")/node_checks.sh"
check "empty Node options preserve the upstream LTS default alias" test \
  "$(cat /usr/local/share/nvm/alias/default)" = 'lts/*'
check "empty Node options retain pnpm and node-gyp defaults" node_default_tools
check "OpenCode and its initializer work with empty Node options" node_cli_and_initializer
reportResults
