#!/usr/bin/env bash
# Scenario: the image already has a deno reporting 2.8.0 and a tool in the tools directory; the feature installs
# latest, so the real Deno replaces the stub and the tool stays.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The version the latest-release pointer names when the test runs; a release between build and test fails once.
latest="$(
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
    https://dl.deno.land/release-latest.txt \
    | tr -d '[:space:]'
)"
latest="${latest#v}"

check "the earlier /usr/local/bin/deno is replaced" bash -c '! sha256sum --status -c /opt/deno-stub.sha256'
check "deno --version reports the version latest resolved to (${latest})" bash -c \
  "deno --version | head -n 1 | grep -qx 'deno ${latest} (.*'"
check "deno runs by name" bash -c "[[ \"\$(deno eval 'console.log(1 + 1)')\" == 2 ]]"
tool_runs() {
  [[ "$(bash -c preinstalled-tool)" == "preinstalled tool" ]]
}
check "the tool in /usr/local/share/deno/bin still runs by name" tool_runs

reportResults
