#!/usr/bin/env bash
# Default installation on every compatibility image, checked as the image's remote user.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/opencode-feature/initialize"

stable_cli() { [[ "$(opencode --version)" =~ ^opencode\ v2\.[0-9]+\.[0-9]+$ ]]; }
links_to_volume() {
  [[ "$(readlink "${HOME}/.local/share/opencode")" == /var/lib/opencode/data \
    && "$(readlink "${HOME}/.config/opencode")" == /var/lib/opencode/config \
    && "$(readlink "${HOME}/.local/state/opencode")" == /var/lib/opencode/state \
    && "$(readlink "${HOME}/.cache/opencode")" == /var/lib/opencode/cache ]]
}
private_state() {
  local directory
  for directory in /var/lib/opencode /var/lib/opencode/{data,config,state,cache}; do
    [[ "$(stat -c %u:%a "${directory}")" == "$(id -u):700" ]] || return 1
  done
}

check "the native CLI runs as the remote user with a stable 2.x release" stable_cli
check "the executable is installed at /usr/local/bin/opencode" test -x /usr/local/bin/opencode
check "the state volume is mounted at /var/lib/opencode" mountpoint -q /var/lib/opencode
check "creation-time initialization succeeds without credentials" "${INITIALIZE}"
check "the OpenCode XDG directories link to the state volume" links_to_volume
check "the state root and its directories are private to the remote user" private_state
check "the installation stores no credentials" test ! -e /var/lib/opencode/data/opencode.db
check "the installation adds neither Node.js nor npm" bash -c '! command -v node && ! command -v npm'
no_global_xdg() { [[ -z "${XDG_DATA_HOME-}${XDG_CONFIG_HOME-}${XDG_STATE_HOME-}${XDG_CACHE_HOME-}" ]]; }
check "the installation sets no global XDG root" no_global_xdg
check "repeated initialization keeps the mapping" "${INITIALIZE}"
reportResults
