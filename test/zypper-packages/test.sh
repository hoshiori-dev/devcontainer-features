#!/usr/bin/env bash
set -eu
# TEMPORARY (#43): compatibility.json omits Tumbleweed arm64 after native package digest failures.
# Restore that combination and verify it on the next zypper-packages feature change.
# shellcheck source=/dev/null
source dev-container-features-test-lib
installed() { rpm -q "$1" >/dev/null 2>&1; }
check "empty default installs no bc" bash -c "! rpm -q bc"
check "empty default installs no file" bash -c "! rpm -q file"
reportResults
