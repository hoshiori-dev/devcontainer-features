#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "Omitted packages: bc is not installed" bash -c '! rpm -q bc'
check "Omitted packages: file is not installed" bash -c '! rpm -q file'

reportResults
