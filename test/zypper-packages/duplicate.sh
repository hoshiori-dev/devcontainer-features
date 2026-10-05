#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the second installation, with an empty list, leaves bc installed" rpm -q bc
check "the second installation, with an empty list, leaves file installed" rpm -q file
check "bc runs after the second installation" bash -c 'echo 2+3 | bc | grep -qx 5'
check "file runs after the second installation" file --version

reportResults
