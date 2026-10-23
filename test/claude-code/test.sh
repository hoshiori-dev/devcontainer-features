#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "native CLI runs" claude --version
check "creation readiness succeeds" /usr/local/share/claude-code-feature/initialize
check "default home maps into the volume" test "$(readlink -f "${HOME}/.claude")" = /var/lib/claude-code
check "state root is private" test "$(stat -c %u:%a /var/lib/claude-code)" = "$(id -u):700"
check "no authentication is requested or created" test ! -e /var/lib/claude-code/.credentials.json
check "application remains outside state" test -x /usr/local/share/claude-code/claude
check "no Node runtime is provisioned" bash -c '! command -v node && ! command -v npm'
reportResults
