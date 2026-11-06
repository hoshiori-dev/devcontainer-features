#!/usr/bin/env bash
# Default installation on every compatibility image, checked as the image's remote user.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/pi-feature/initialize"

# The release the GitHub releases API names latest when the test runs; a release between build and test fails once.
latest="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location \
  https://api.github.com/repos/earendil-works/pi/releases/latest \
  | jq --raw-output .tag_name)"
readonly latest

# Runs before any check starts Pi, which creates its own files in the agent directory.
no_build_state() {
  [[ -z "$(ls -A /var/lib/pi/agent)" ]] && ! compgen -G '/usr/local/lib/.pi-install.*' >/dev/null
}
check "the build leaves no Pi state, credentials, or download files behind" no_build_state
check "the omitted version installs the latest stable release" test "$(pi --version)" = "${latest#v}"
check "/usr/local/bin/pi links to the executable in /usr/local/lib/pi" \
  test "$(readlink /usr/local/bin/pi)" = /usr/local/lib/pi/pi
# Pi reads its bundled themes only in the interactive interface, and reports one it cannot load at startup. timeout
# keeps Pi in the pseudo-terminal's foreground group (--foreground): a background group is stopped when Pi sets up the
# terminal, and a stopped Pi outlives a plain timeout.
bundled_theme_loads() {
  local output
  output="$(cd /tmp && TERM=xterm-256color timeout --kill-after=5 30 script --quiet --command \
    'stty rows 30 cols 100 && exec timeout --foreground --kill-after=5 10 pi --offline --no-session --use-theme dark' \
    /dev/null 2>&1)" || true
  [[ "${output}" == *"v${latest#v}"* && "${output}" != *"Failed to load theme"* ]]
}
check "the remote user's CLI loads its bundled themes through the link" bundled_theme_loads
check "the state volume is mounted at /var/lib/pi" mountpoint -q /var/lib/pi
check "creation-time initialization succeeds without credentials" "${INITIALIZE}"
check "the home's .pi/agent links to the state volume" test "$(readlink "${HOME}/.pi/agent")" = /var/lib/pi/agent
private_state() {
  [[ "$(stat -c %u:%a /var/lib/pi)" == "$(id -u):700" && "$(stat -c %u:%a /var/lib/pi/agent)" == "$(id -u):700" ]]
}
check "the state root and the agent directory are private to the remote user" private_state
check "the installation adds neither Node.js nor npm" bash -c '! command -v node && ! command -v npm'
check "the installation leaves PI_CODING_AGENT_DIR unset" test -z "${PI_CODING_AGENT_DIR-}"
no_startup_entry() {
  ! grep -rqsF -e /usr/local/lib/pi -e .pi/agent /etc/profile /etc/profile.d /etc/bash.bashrc /etc/environment \
    "${HOME}/.bashrc" "${HOME}/.profile"
}
check "the installation adds no PATH or shell startup entry" no_startup_entry
initialization_keeps_mapping() {
  "${INITIALIZE}" && [[ "$(readlink "${HOME}/.pi/agent")" == /var/lib/pi/agent ]] && private_state
}
check "repeated initialization keeps the mapping and private state" initialization_keeps_mapping
reportResults
