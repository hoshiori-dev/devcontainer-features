#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# Computed test paths cannot be resolved by shellcheck.
# shellcheck source=/dev/null
source "$(dirname "$0")/assertions.sh"
check "redirected sources do not prevent official-source installation" reports_release 0.7.2
check "colab uses managed Python despite older system Python" image_interpreter
check "system Python version is unchanged" bash -c 'python3 --version | cmp - /opt/system-python-version'
check "system Python path is unchanged" bash -c 'readlink -f /usr/bin/python3 | cmp - /opt/system-python-path'
reportResults
