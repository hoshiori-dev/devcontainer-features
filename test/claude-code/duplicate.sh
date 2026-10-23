#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
[[ "${VERSION-}" == 2.1.89 && "${VERSION__DEFAULT-}" == latest ]]
latest="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location \
  https://downloads.claude.ai/claude-code-releases/latest)"
check "the second installation selects the current stable release" test "$(claude --version)" = "${latest} (Claude Code)"
check "state readiness survives installation twice" /usr/local/share/claude-code-feature/initialize
reportResults
