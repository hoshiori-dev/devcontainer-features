#!/usr/bin/env bash
# Install-twice test: the CLI installs deno with the first non-default proposal (VERSION, 2.8.0) and then with the
# default (VERSION__DEFAULT, latest). The two are different versions, so the second install replaces the first.
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

check "deno --version reports the version latest resolved to (${latest})" bash -c \
  "deno --version | head -n 1 | grep -qx 'deno ${latest} (.*'"
check "deno by name is /usr/local/bin/deno" test "$(readlink -f "$(command -v deno)")" = /usr/local/bin/deno

no_staging_file() {
  local entry
  for entry in /usr/local/bin/.deno.*; do
    if [[ -e "${entry}" ]]; then return 1; fi
  done
}
check "no partially written executable is left in /usr/local/bin" no_staging_file

# Root owns both directories; a non-root remote user writes them through group deno, root as their owner.
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
