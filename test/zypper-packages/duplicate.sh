#!/usr/bin/env bash
set -eu
# shellcheck source=/dev/null
source dev-container-features-test-lib
installed() { rpm -q "$1" >/dev/null 2>&1; }
check "bc survives the empty second invocation" installed bc
check "file survives the empty second invocation" installed file
check "bc runs" bash -c "echo 2+3 | bc | grep -qx 5"
check "file runs" file --version
reportResults
