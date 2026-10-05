#!/usr/bin/env bash
set -eu
# shellcheck source=/dev/null
source dev-container-features-test-lib
installed() { rpm -q "$1" >/dev/null 2>&1; }
check "empty default installs no bc" bash -c "! rpm -q bc"
check "empty default installs no file" bash -c "! rpm -q file"
reportResults
