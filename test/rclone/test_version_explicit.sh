#!/bin/sh
# Scenario test_version_explicit: fedora:44 with version 1.70.0, an explicit release older than the newest. POSIX sh,
# like the other rclone tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v rclone resolves to /usr/local/bin/rclone" rclone_resolves_to_usr_local_bin
check "rclone version reports v1.70.0" rclone_reports_version 1.70.0
check "the completion files equal what rclone 1.70.0 generates" completions_match
check "apt's package lists, dnf's cache, and apk's cache hold no file" package_caches_empty
check "no temporary directory or staged file of the install remains" no_install_leftovers

reportResults
