#!/usr/bin/env bash
set -eu
# shellcheck source=/dev/null
source dev-container-features-test-lib
installed() { rpm -q "$1" >/dev/null 2>&1; }
check "bc installed" installed bc
check "file installed" installed file
reportResults
