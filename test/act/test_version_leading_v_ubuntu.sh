#!/bin/sh
# Scenario: act installed with version "v0.2.80" on mcr.microsoft.com/devcontainers/base:ubuntu24.04.
# POSIX sh, as every act test: alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v act resolves to /usr/local/bin/act" act_resolves_to_usr_local_bin
check "act --version reports 0.2.80" act_reports_version 0.2.80

reportResults
