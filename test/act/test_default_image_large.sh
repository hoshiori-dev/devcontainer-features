#!/bin/sh
# Scenario: act installed with defaultImage "large" on alpine:3.24, with root as the remote user.
# POSIX sh, as every act test: alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "root's configuration file holds exactly the large lines" config_holds_lines /root/.config/act/actrc full

reportResults
