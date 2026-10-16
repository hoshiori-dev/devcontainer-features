#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh

reject_option() {
  local expected="$1"
  shift
  if run_installer "$@" > rejected.log 2>&1; then cat rejected.log; return 1; fi
  grep -F "${expected}" rejected.log
}
check "unknown profile fails" reject_option 'invalid profile' PROFILE=unknown
check "empty languages fail" reject_option 'languages is empty' LANGUAGES=
check "unknown language fails" reject_option 'invalid languages token' LANGUAGES=ko
check "empty language token fails" reject_option 'invalid languages token' LANGUAGES=zh,
check "mixed none and a language fails" reject_option 'none cannot be combined' LANGUAGES=none,zh
check "package arguments cannot be options" reject_option 'invalid package name' PACKAGES=--help
# The literal shell expression is the input whose rejection is being tested.
# shellcheck disable=SC2016
check "package arguments cannot execute shell code" reject_option 'invalid package name' 'PACKAGES=$(touch injected)'
check "rejected package did not run a shell" test ! -e injected
check "HTTP mirror fails" reject_option 'HTTPS repository URL' CTANMIRROR=http://mirror.ctan.org
check "mirror credentials fail" reject_option 'HTTPS repository URL' CTANMIRROR=https://example:password@example.com
reportResults
