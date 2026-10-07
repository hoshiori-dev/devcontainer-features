#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "bc.x86_64 installs bc for the x86_64 architecture" bash -c "rpm -q --qf '%{ARCH}' bc | grep -qx x86_64"

reportResults
