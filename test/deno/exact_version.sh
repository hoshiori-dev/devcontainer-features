#!/usr/bin/env bash
# Scenario: version 2.8.0 on base:ubuntu-24.04 as vscode; deno reports it for vscode and for root.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the remote user is not root" test "$(id -u)" != 0
check "deno reports 2.8.0 as $(id -un)" bash -c "deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"
check "deno reports 2.8.0 as root" bash -c "sudo -n deno --version | head -n 1 | grep -qx 'deno 2.8.0 (.*'"
check "the tools tree is owned by $(id -un)" bash -c \
    "[ -z \"\$(find /usr/local/share/deno ! -user $(id -un))\" ]"

reportResults
