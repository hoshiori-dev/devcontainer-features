#!/bin/sh
# Scenario: glab installed with version "v1.119.0" on fedora:44.
# POSIX sh, as every glab test: alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v glab resolves to /usr/local/bin/glab" glab_resolves_to_usr_local_bin
check "glab --version reports 1.119.0" glab_reports_version 1.119.0

reportResults
