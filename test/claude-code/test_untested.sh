#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
output="$(env VERSION=latest _REMOTE_USER=root _REMOTE_USER_HOME=/root bash "$(dirname "$0")/_feature/install.sh")"
# Expansion belongs to the child shell that runs the assertion.
# shellcheck disable=SC2016
check "covered untested distributions warn and attempt installation" bash -c \
  '[[ "$1" == *"warning: untested distribution debian 13; attempting the official native package"* ]]' _ "${output}"
check "native CLI executes on a covered untested distribution" claude --version
check "initialization works on a covered untested distribution" /usr/local/share/claude-code-feature/initialize
check "the native route does not install Node on an untested target" bash -c '! command -v node && ! command -v npm'
reportResults
