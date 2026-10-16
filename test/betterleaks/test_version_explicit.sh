#!/bin/sh
# Scenario: betterleaks installed with version "1.8.1" on debian:12.
# POSIX sh, as every betterleaks test: alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v betterleaks resolves to /usr/local/bin/betterleaks" betterleaks_resolves_to_usr_local_bin
check "betterleaks version reports 1.8.1" betterleaks_reports_version 1.8.1

reportResults
