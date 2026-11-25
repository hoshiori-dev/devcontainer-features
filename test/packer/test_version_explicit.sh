#!/bin/sh
# Scenario test_version_explicit: opensuse/leap:16.0 with version 1.15.4, an explicit release of the previous line, on
# the zypper family. POSIX sh, like the other packer tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v packer resolves to /usr/local/bin/packer" packer_resolves_to_usr_local_bin
check "packer version reports v1.15.4" packer_reports_version 1.15.4
check "no temporary directory or staged file of the install remains" no_install_leftovers

reportResults
