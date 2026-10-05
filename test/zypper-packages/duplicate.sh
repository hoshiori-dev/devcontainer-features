#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the second installation, with an empty list, leaves bc installed" rpm -q bc
check "the second installation, with an empty list, leaves file installed" rpm -q file
check "the second installation, with an empty list, removes nothing: bc still computes 2+3" \
  bash -c 'echo 2+3 | bc | grep -qx 5'
check "the second installation, with an empty list, removes nothing: file still reports its version" file --version

reportResults
