#!/bin/sh
# Scenario: gitleaks installed with version "v8.28.0" on mcr.microsoft.com/devcontainers/base:ubuntu24.04.
# POSIX sh, as every gitleaks test: alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v gitleaks resolves to /usr/local/bin/gitleaks" gitleaks_resolves_to_usr_local_bin
check "gitleaks version reports 8.28.0" gitleaks_reports_version 8.28.0

reportResults
