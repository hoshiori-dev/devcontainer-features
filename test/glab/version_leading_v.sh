#!/bin/sh
# Scenario: glab installed with version "v1.119.0". POSIX sh, because alpine:3.24 ships no bash.
set -e

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "glab resolves to /usr/local/bin/glab" glab_resolves_to_usr_local_bin
check "glab reports the requested release" equals "$(installed_version)" 1.119.0

reportResults
