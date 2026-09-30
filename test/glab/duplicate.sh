#!/bin/sh
# Install-twice test: glab is installed with version 1.47.0 (VERSION), then with the default
# latest (VERSION__DEFAULT), so the second install replaces the first. POSIX sh, because
# alpine:3.24 ships no bash.
set -e

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

latest=$(latest_version)
echo "first install: ${VERSION-unset}; second install: ${VERSION__DEFAULT-unset}; latest now: $latest"

check "glab resolves to /usr/local/bin/glab" glab_resolves_to_usr_local_bin
check "/usr/local/bin holds only one glab file" only_one_glab
check "glab is the release the second install selected" equals "$(installed_version)" "$latest"
check "the second install replaced 1.47.0" test "$latest" != 1.47.0
check "no temporary files of the installs remain" no_install_leftovers

reportResults
