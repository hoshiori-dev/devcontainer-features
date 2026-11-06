#!/usr/bin/env bash
# Install-twice test: Pi 1.4.0 first, then the default latest; option values arrive as VERSION and VERSION__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The release the GitHub releases API names latest when the test runs; a release between build and test fails once.
latest="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location \
  https://api.github.com/repos/earendil-works/pi/releases/latest \
  | jq --raw-output .tag_name)"
readonly latest

single_link() { [[ "$(find "${HOME}/.pi" -mindepth 1 -maxdepth 1 | wc -l)" == 1 ]]; }
single_installation() {
  [[ -x /usr/local/lib/pi/pi ]] && ! compgen -G '/usr/local/lib/.pi-install.*' >/dev/null
}

check "the options of both installations arrive" test "${VERSION-}:${VERSION__DEFAULT-}" = 1.4.0:latest
check "the later latest installation wins" test "$(pi --version)" = "${latest#v}"
check "one installation remains in /usr/local/lib/pi" single_installation
check "creation-time initialization works after two installations" /usr/local/share/pi-feature/initialize
check "the home's .pi directory holds exactly one entry, the agent link" single_link
check "the agent directory still links to the state volume" \
  test "$(readlink "${HOME}/.pi/agent")" = /var/lib/pi/agent
reportResults
