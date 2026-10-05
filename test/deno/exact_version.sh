#!/usr/bin/env bash
# Scenario: version 2.8.0 on base:ubuntu24.04 as vscode; deno reports it for vscode and for root.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the remote user is not root" test "$(id -u)" != 0
check "deno --version reports 2.8.0 as the remote user" bash -c \
  "deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"
check "deno --version reports 2.8.0 as root" bash -c "sudo -n deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"

# The remote user writes both directories through group deno; root owns them.
tools_access() {
  local group=root
  local mode=755
  local dir
  if [[ "$(id -u)" != 0 ]]; then
    group=deno
    mode=2775
    [[ " $(id -nG) " == *" deno "* ]] || return 1
  fi
  for dir in /usr/local/share/deno /usr/local/share/deno/bin; do
    [[ "$(stat -c '%U:%G:%a' "${dir}")" == "root:${group}:${mode}" ]] || return 1
    [[ -w "${dir}" ]] || return 1
  done
}
check "the tools directories are owned by root and writable by the remote user" tools_access

reportResults
