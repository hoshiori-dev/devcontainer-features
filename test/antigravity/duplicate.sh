#!/usr/bin/env bash
# Install-twice test: the feature has no options, so the CLI installs it twice with the same (empty) configuration.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly STATE_DIR="/var/lib/antigravity"
readonly MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"

# The version the current manifest names when the test runs; a release between build and test fails once.
case "$(uname -m)" in
  x86_64) platform=linux_amd64 ;;
  aarch64) platform=linux_arm64 ;;
esac
current="$(curl --fail --silent --show-error --location "${MANIFEST_URL}/${platform}.json" | jq -r .version)"

check "the second installation keeps the manifest's current version" test "$(agy --version)" = "${current}"
check "creation-time initialization works after two installations" /usr/local/share/antigravity-feature/initialize
check "the CLI data link still points at the volume" \
  test "$(readlink -f "${HOME}/.gemini/antigravity-cli")" = "${STATE_DIR}/cli"
check "no staged executable or staging directory remains" \
  bash -c '! compgen -G "/usr/local/share/.antigravity-install.*" && test ! -e /usr/local/share/antigravity/.agy.new'
check "the state volume holds one directory per mapping" \
  test "$(find "${STATE_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 3
check "no login token was created at build time" test ! -e "${STATE_DIR}/cli/antigravity-oauth-token"

reportResults
