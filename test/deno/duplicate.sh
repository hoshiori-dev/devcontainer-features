#!/usr/bin/env bash
# Install-twice test: deno is installed with the first non-default proposal (VERSION, 2.8.0) and
# then with the default (VERSION__DEFAULT, latest), so the second install replaces the first.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

latest="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
    https://dl.deno.land/release-latest.txt | tr -d '[:space:]')"
latest="${latest#v}"

check "the two installs used different versions" test "${VERSION}" != "${VERSION__DEFAULT}"
check "deno reports the version latest resolved to (${latest})" bash -c \
    "deno --version | head -n 1 | grep -qx 'deno ${latest} (.*'"
check "deno resolves to /usr/local/bin/deno" test "$(command -v deno)" = /usr/local/bin/deno
no_staging_file() {
    local entry
    for entry in /usr/local/bin/.deno.*; do
        [ ! -e "${entry}" ] || return 1
    done
}
check "no staging file is left in /usr/local/bin" no_staging_file
tools_access() {
    local group=root mode=755 dir
    if [ "$(id -u)" != 0 ]; then
        group=deno
        mode=2775
        case " $(id -nG) " in *" deno "*) ;; *) return 1 ;; esac
    fi
    for dir in /usr/local/share/deno /usr/local/share/deno/bin; do
        [ "$(stat -c '%U:%G:%a' "${dir}")" = "root:${group}:${mode}" ] || return 1
        [ -w "${dir}" ] || return 1
    done
}
check "tools directories have the expected owner, group, mode, and access" tools_access

reportResults
