#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/checks.sh
source ./checks.sh
cp documents/* .
check_common
check_ownership
check_chinese
check_japanese
report_installation_timing
reportResults
