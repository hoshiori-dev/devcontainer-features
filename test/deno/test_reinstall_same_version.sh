#!/usr/bin/env bash
# Scenario: the image already has a deno reporting 2.8.0 and a tool in the tools directory; the feature installs
# 2.8.0, so it keeps the existing executable and the tool.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "/usr/local/bin/deno is unchanged" sha256sum -c /opt/deno-stub.sha256
check "deno --version reports 2.8.0" bash -c "deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"
tool_runs() {
  [[ "$(bash -c preinstalled-tool)" == "preinstalled tool" ]]
}
check "the tool in /usr/local/share/deno/bin still runs by name" tool_runs

reportResults
