#!/bin/sh
# Scenario test_version_floor: alpine:3.24 with version v1.63.0, the minimum with a leading "v". Shows that the oldest
# supported release installs through BusyBox unzip on musl and generates the completion files. POSIX sh, because
# alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v rclone resolves to /usr/local/bin/rclone" rclone_resolves_to_usr_local_bin
check "rclone version reports v1.63.0" rclone_reports_version 1.63.0
check "the completion files equal what rclone 1.63.0 generates" completions_match
check "no temporary directory or staged file of the install remains" no_install_leftovers

reportResults
