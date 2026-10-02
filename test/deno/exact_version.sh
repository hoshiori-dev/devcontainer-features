#!/usr/bin/env bash
# Scenario: version 2.8.0 on base:ubuntu24.04 as vscode; deno reports it for vscode and for root.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the remote user is not root" test "$(id -u)" != 0
check "deno reports 2.8.0 as $(id -un)" bash -c "deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"
check "deno reports 2.8.0 as root" bash -c "sudo -n deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"
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
