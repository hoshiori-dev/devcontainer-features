#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
output="$(env _REMOTE_USER=root _REMOTE_USER_HOME=/root bash "$(dirname "$0")/_feature/install.sh")"
# Expansion belongs to the child shell that runs the assertion.
# shellcheck disable=SC2016
check "a covered untested distribution warns and attempts installation" bash -c \
  '[[ "$1" == *"warning: untested distribution debian 13; attempting the official linux_"* ]]' _ "${output}"
check "agy runs on a covered untested distribution" agy --version
check "initialization works on a covered untested distribution" /usr/local/share/antigravity-feature/initialize
reportResults
