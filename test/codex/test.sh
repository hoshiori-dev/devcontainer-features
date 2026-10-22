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
check "CLI and Node dependencies remain outside the volume" test -x /usr/local/share/codex/node_modules/.bin/codex
check "repeated initialization preserves the mapping" "${INITIALIZE}"
reportResults
