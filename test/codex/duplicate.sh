#!/usr/bin/env bash
# The CLI performs both image-build installations: pinned 0.162.0 then latest.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
[[ "${VERSION-}" == 0.162.0 && "${VERSION__DEFAULT-}" == latest ]]
# Latest is resolved at test time because it is a moving upstream channel.
latest="$(npm view @openai/codex@latest version --registry=https://registry.npmjs.org/)"
reports_latest() { [[ "$(codex --version)" == "codex-cli ${latest}" ]]; }
check "the second installation selects the current stable release" reports_latest
check "creation-time initialization works after two installations" /usr/local/share/codex-feature/initialize
check "one home link points at the state volume" test "$(readlink -f "${HOME}/.codex")" = /var/lib/codex
check "no build-time credential cache was created" test ! -e /var/lib/codex/auth.json
reportResults
