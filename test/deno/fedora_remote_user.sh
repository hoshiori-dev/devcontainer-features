#!/usr/bin/env bash
# Scenario: version 2.8.0 on an almalinux:9 image (dnf 4) with the non-root remote user devuser, who reaches the tools
# directories through group deno. The checks run as devuser, the scenario's remoteUser.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Requirement "Shared location for global tools": ownership and mode only; the next checks show the write access.
tools_directories_belong_to_group_deno() {
  [[ "$(stat -c %U:%G:%a /usr/local/share/deno)" == root:deno:2775 ]] || return 1
  [[ "$(stat -c %U:%G:%a /usr/local/share/deno/bin)" == root:deno:2775 ]]
}
check "the tools directories are root:deno with mode 2775" tools_directories_belong_to_group_deno
remote_user_in_group_deno() {
  [[ " $(id -nG) " == *" deno "* ]]
}
check "the remote user is a member of group deno" remote_user_in_group_deno

script="$(mktemp -d)/hello.ts"
echo 'console.log("group access");' >"${script}"
check "deno install --global succeeds without elevated privileges" \
  deno install --global --name deno-group-hello "${script}"
tool_runs() {
  [[ "$(bash -c deno-group-hello)" == "group access" ]]
}
check "the tool runs by name from a new shell" tool_runs

reportResults
