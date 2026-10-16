#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh
# shellcheck source=test/latex/checks.sh
source ./checks.sh
printf 'preserved\n' > "${HOME}/.TinyTeX/before-full-upgrade"
check "basic upgrades to full without replacing the tree" run_installer PROFILE=full LANGUAGES=zh,ja
check "full scheme is installed" tlmgr info --only-installed scheme-full
check "profile upgrade preserves user files" grep -qx preserved "${HOME}/.TinyTeX/before-full-upgrade"
cp documents/* .
check_common
check_ownership
check_chinese
check_japanese
check_academic
report_installation_timing
reportResults
