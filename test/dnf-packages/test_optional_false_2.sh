#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# ipcalc recommends geolite2-city in the repositories of every image in the compatibility list, and nothing that is
# installed requires it.
check "Weak dependencies are left out: the listed package ipcalc is installed" rpm -q ipcalc
check "Weak dependencies are left out: the recommended package geolite2-city is not installed" \
  bash -c '! rpm -q geolite2-city'

reportResults
