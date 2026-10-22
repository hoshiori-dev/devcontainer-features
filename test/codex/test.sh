#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
readonly INITIALIZE="/usr/local/share/codex-feature/initialize"

stable_cli() { [[ "$(codex --version)" =~ ^codex-cli\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; }
default_home() { [[ "${CODEX_HOME+x}" != x && "$(readlink -f "${HOME}/.codex")" == /var/lib/codex ]]; }
private_root() { [[ "$(stat -c %u:%a /var/lib/codex)" == "$(id -u):700" ]]; }
no_account() { [[ ! -e /var/lib/codex/auth.json ]]; }
check "CLI runs as the remote user with a stable release" stable_cli
check "creation-time initialization succeeds with no credentials" "${INITIALIZE}"
check "default home links to the project volume without CODEX_HOME" default_home
check "state root belongs privately to the remote user" private_root
check "installation and initialization do not log in" no_account
check "native application remains outside the volume" test -x /usr/local/share/codex/bin/codex
check "native package retains its code-mode companion" test -x /usr/local/share/codex/bin/codex-code-mode-host
check "native package retains its search companion" test -x /usr/local/share/codex/codex-path/rg
check "standalone installation does not provision Node" bash -c '! command -v node && ! command -v npm'
check "repeated initialization preserves the mapping" "${INITIALIZE}"
reportResults
