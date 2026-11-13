#!/bin/sh
# Scenario test_version_explicit: opensuse/leap:16.0 with version 1.12.12, an explicit release of an older maintained
# line, on the zypper family. POSIX sh, like the other opentofu tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "command -v tofu resolves to /usr/local/bin/tofu" tofu_resolves_to_usr_local_bin
check "tofu version reports v1.12.12" tofu_reports_version 1.12.12
check "no temporary directory or staged file of the install remains" no_install_leftovers

reportResults
