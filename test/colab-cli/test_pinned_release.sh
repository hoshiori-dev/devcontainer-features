#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# Computed test paths cannot be resolved by shellcheck.
# shellcheck source=/dev/null
source "$(dirname "$0")/assertions.sh"
check "colab reports the pinned release" reports_release 0.7.2
check "colab help succeeds without credentials" colab --help
check "image without system Python uses managed Python 3.12" image_interpreter
check "system Python was not added" test ! -e /usr/bin/python3
reportResults
