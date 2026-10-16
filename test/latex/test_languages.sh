#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/checks.sh
source ./checks.sh
# shellcheck source=test/latex/installer.sh
source ./installer.sh
cp documents/* .
check_common
check "Chinese selection accepts whitespace and duplicates" run_installer PROFILE=basic LANGUAGES=' zh , zh '
check_chinese
check "Japanese-only selection provides independent Japanese support" run_installer PROFILE=basic LANGUAGES=ja
check_japanese
reportResults
