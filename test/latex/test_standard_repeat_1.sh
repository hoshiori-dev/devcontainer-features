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
check_academic
check "documented editor recipes compile" check_editor_recipes
report_installation_timing
reportResults
