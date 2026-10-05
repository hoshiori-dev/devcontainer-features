#!/bin/sh
# Install-twice test: apk-packages is installed once with non-default options, then once with the
# defaults. Scenario "Listed packages are installed" for the first install; scenario "Empty list is a
# no-op" for the second, which leaves those packages and their world lines; and requirement "Clean
# package caches" for /var/cache/apk staying as the image ships it and no temporary directory remaining.
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# file and tree are written out: the devcontainer CLI takes the first install's `packages` from the
# option's second proposal, "file,tree" (devcontainer-feature.json).
check "file from the first install is installed" installed file
check "file is a line of apk's world" in_world file
check "tree from the first install is installed" installed tree
check "tree is a line of apk's world" in_world tree
check "/var/cache/apk is left as it was, empty" cache_left_empty
check "no temporary directory of the feature is left" no_temporary_dir

reportResults
