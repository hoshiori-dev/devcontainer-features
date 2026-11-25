#!/bin/sh
# Scenario test_version_floor: alpine:3.24 with version v1.7.0, the minimum with a leading "v". Shows that the oldest
# supported release installs through BusyBox unzip on musl. POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v packer resolves to /usr/local/bin/packer" packer_resolves_to_usr_local_bin
check "packer version reports v1.7.0" packer_reports_version 1.7.0
check "no temporary directory or staged file of the install remains" no_install_leftovers

reportResults
