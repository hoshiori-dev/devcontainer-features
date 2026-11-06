#!/usr/bin/env bash
# Debian 13 is outside the compatibility list but covered by the native packages.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

output="$(env VERSION=latest _REMOTE_USER=root _REMOTE_USER_HOME=/root bash "$(dirname "$0")/_feature/install.sh")"
# Expansion belongs to the child shell that runs the assertion.
# shellcheck disable=SC2016
check "a covered untested distribution warns and attempts installation" bash -c \
  '[[ "$1" == *"warning: untested distribution debian 13; attempting the native package"* ]]' _ "${output}"
check "the native CLI runs on a covered untested distribution" opencode --version
check "initialization works on a covered untested distribution" /usr/local/share/opencode-feature/initialize
check "the native route installs neither Node.js nor npm" bash -c '! command -v node && ! command -v npm'
reportResults
