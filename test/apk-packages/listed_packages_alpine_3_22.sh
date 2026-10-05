#!/bin/sh
# Scenario listed_packages_alpine_3_22 (scenarios.json): spec scenarios "Listed packages are installed"
# and "Caches are removed".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "file is installed" installed file
check "tree is installed" installed tree
check "file runs" file --version
check "tree runs" tree --version
check "the dependency libmagic is installed" installed libmagic
check "file is a line of apk's world" in_world file
check "tree is a line of apk's world" in_world tree
check "/var/cache/apk is empty" cache_empty
check "no temporary directory of the feature is left" no_temporary_dir

reportResults
