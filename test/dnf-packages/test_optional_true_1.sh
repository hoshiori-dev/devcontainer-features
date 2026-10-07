#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# ipcalc recommends geolite2-city in the repositories of every image in the compatibility list, and nothing that is
# installed requires it.
check "Optional dependency selection is enabled: the listed package ipcalc is installed" rpm -q ipcalc
check "Optional dependency selection is enabled: the recommended package geolite2-city is installed" \
  rpm -q geolite2-city

reportResults
