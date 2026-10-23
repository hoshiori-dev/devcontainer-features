#!/usr/bin/env bash
# Install-twice test: OpenCode 2.1.2 first, then the default latest; option values arrive as VERSION and
# VERSION__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The release the latest dist-tag names when the test runs; a release between build and test fails once.
latest="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
  https://registry.npmjs.org/-/package/@opencode%2fcli/dist-tags \
  | jq --raw-output .latest)"

single_links() {
  [[ "$(find "${HOME}/.local/share" "${HOME}/.config" "${HOME}/.local/state" "${HOME}/.cache" -maxdepth 1 \
    -name 'opencode*' | wc -l)" == 4 ]]
}

check "the options of both installations arrive" test "${VERSION-}:${VERSION__DEFAULT-}" = 2.1.2:latest
check "the later latest installation wins" test "$(opencode --version)" = "opencode v${latest}"
check "creation-time initialization works after two installations" /usr/local/share/opencode-feature/initialize
check "each OpenCode XDG directory has exactly one link" single_links
check "the data directory still links to the state volume" \
  test "$(readlink "${HOME}/.local/share/opencode")" = /var/lib/opencode/data
reportResults
